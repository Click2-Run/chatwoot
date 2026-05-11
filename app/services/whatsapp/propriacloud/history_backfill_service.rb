# frozen_string_literal: true

# One-shot history backfill — paginated pulls of /sync/contacts,
# /sync/conversations, /sync/messages and /labels into the same Chatwoot
# models the live webhook tail writes to. Idempotent: every upsert keys
# off WhatsApp's stable identifiers (`Contact.identifier` = JID,
# `ContactInbox.source_id` = phone-number digits, `Message.source_id` =
# WhatsApp `key.id`), so re-running the job is safe.
#
# Triggered by ConnectionUpdate when the inbox transitions to `open` for
# the first time (provider_config['history_backfill_completed_at'] is
# blank). Sidekiq retries handle transient API failures.
class Whatsapp::Propriacloud::HistoryBackfillService
  PAGE_SIZE = 200
  # Hard cap to prevent a runaway backfill from overwhelming Sidekiq /
  # the upstream API on accounts with very long histories. 25 pages × 200
  # = 5,000 messages per chat — enough to seed Chatwoot with months of
  # context for active threads without saturating the worker.
  MAX_PAGES_PER_CHAT = 25
  # Skip messages older than this when streaming history. Hard cap that
  # mirrors WhatsApp Web's typical ~6-month export horizon. Configurable
  # per channel via `provider_config['history_backfill_max_age_days']`.
  DEFAULT_MAX_AGE_DAYS = 180

  def initialize(channel:)
    @channel = channel
    @inbox = channel.inbox
    @account = @inbox.account
    @provider = channel.provider_service
    @max_age_days = channel.provider_config['history_backfill_max_age_days'].presence&.to_i || DEFAULT_MAX_AGE_DAYS
    @cutoff_at = @max_age_days.positive? ? @max_age_days.days.ago : nil
  end

  def perform
    Rails.logger.tagged('propriacloud') do
      Rails.logger.info "backfill: start inbox=#{@inbox.id} cutoff=#{@cutoff_at&.iso8601 || 'none'}"
      # NOTE: WhatsApp labels (/labels) are intentionally NOT imported.
      # Chatwoot's `labels` table is an app-level construct scoped to
      # the Account; WhatsApp labels are a parallel, unrelated taxonomy
      # that lives in the WhatsApp Business app. Auto-creating Chatwoot
      # labels from WhatsApp label names polluted the account's label
      # space with rows the operator never asked for. Leaving the
      # `list_labels` provider helper in place for debugging, but the
      # backfill no longer calls it.
      backfill_push_names
      backfill_contacts
      backfill_conversations_and_messages
      stamp_completed!
      Rails.logger.info "backfill: done inbox=#{@inbox.id}"
    end
  end

  private

  # /sync/push-names is a lighter, denormalized view of contact display
  # names captured from the protobuf push_name field. Walking it first
  # gives the contact pass a richer name lookup table — without it, many
  # contacts seeded only via @lid end up keyed on phone digits.
  def backfill_push_names
    @push_name_index = {}
    each_page(:sync_push_names) do |row|
      jid = (row[:jid] || row['jid']).to_s
      name = (row[:push_name] || row['push_name']).to_s.strip
      next if jid.blank? || name.blank?

      phone = jid.split('@').first.split(':').first.gsub(/\D/, '')
      next if phone.blank?

      @push_name_index[phone] = name
    end
  end

  def backfill_contacts
    @push_name_index ||= {}
    each_page(:sync_contacts) do |row|
      jid = row[:jid] || row['jid']
      next if jid.blank?

      phone = jid.to_s.split('@').first.split(':').first.gsub(/\D/, '')
      next if phone.blank?

      name = row[:name] || row['name'] || row[:push_name] || row['push_name'] ||
             @push_name_index[phone] || phone

      ::ContactInboxWithContactBuilder.new(
        source_id: phone,
        inbox: @inbox,
        contact_attributes: {
          name: name,
          phone_number: "+#{phone}"
        }
      ).perform
    end
  end

  def backfill_conversations_and_messages
    each_page(:sync_conversations) do |conv|
      chat_jid = conv[:chat_jid] || conv['chat_jid']
      next if chat_jid.blank?
      # Skip groups/broadcasts/newsletters/status — Chatwoot has no
      # surface for those today. Accept both @s.whatsapp.net and @lid
      # (WhatsApp's Linked-Identity JID variant for privacy-preserving
      # 1:1 chats); the messages upsert handler downgrades @lid to a
      # phone number via pn_jid when present.
      next if chat_jid.match?(/@(g\.us|broadcast|newsletter|status)\b/)

      backfill_messages_for(chat_jid)
    end
  end

  def backfill_messages_for(chat_jid)
    page = 1
    while page <= MAX_PAGES_PER_CHAT
      messages = @provider.sync_messages(chat_jid, page: page, page_size: PAGE_SIZE)
      break if messages.empty?

      filtered, hit_cutoff = filter_recent(messages)
      dispatch_via_live_tail(filtered) if filtered.any?
      break if hit_cutoff

      page += 1
    end
  end

  def filter_recent(messages)
    return [messages, false] if @cutoff_at.blank?

    cutoff_epoch = @cutoff_at.to_i
    hit_cutoff = false
    keep = messages.select do |m|
      ts = (m[:timestamp] || m['timestamp'] || m[:message_timestamp] || m['message_timestamp']).to_i
      next true if ts.zero?

      if ts < cutoff_epoch
        hit_cutoff = true
        false
      else
        true
      end
    end
    [keep, hit_cutoff]
  end

  # Reuses the live-tail messages_upsert handler so backfill goes through
  # the SAME pipeline as webhook deliveries — same dedupe, same content
  # parsing, same Conversation/Message creation. Avoids forking logic.
  # We must pass `webhook_verify_token` and `custom_id` matching what the
  # live webhook would carry, because IncomingMessagePropriacloudService
  # validates both before dispatching to handlers.
  def dispatch_via_live_tail(messages)
    payload = {
      'event_type' => 'message.received',
      'instance_id' => @channel.provider_config['instance_id'],
      'custom_id' => @inbox.account_id.to_s,
      'webhook_verify_token' => @channel.provider_config['webhook_verify_token'],
      'data' => { 'messages' => messages.map { |m| m.deep_stringify_keys } }
    }
    Whatsapp::IncomingMessagePropriacloudService.new(inbox: @inbox, params: payload).perform
  rescue StandardError => e
    Rails.logger.warn "Propriacloud backfill: dispatch failed (#{e.class}: #{e.message[0..120]})"
  end

  def each_page(method)
    page = 1
    loop do
      rows = @provider.public_send(method, page: page, page_size: PAGE_SIZE)
      break if rows.empty?

      rows.each { |r| yield r }
      page += 1
    end
  end

  def stamp_completed!
    config = @channel.provider_config || {}
    config['history_backfill_completed_at'] = Time.current.iso8601
    @channel.update!(provider_config: config)
  end
end
