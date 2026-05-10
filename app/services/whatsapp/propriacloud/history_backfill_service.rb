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

  def initialize(channel:)
    @channel = channel
    @inbox = channel.inbox
    @account = @inbox.account
    @provider = channel.provider_service
  end

  def perform
    Rails.logger.info "Propriacloud backfill: start inbox=#{@inbox.id}"
    backfill_labels
    backfill_contacts
    backfill_conversations_and_messages
    stamp_completed!
    Rails.logger.info "Propriacloud backfill: done inbox=#{@inbox.id}"
  end

  private

  def backfill_labels
    each_page(:list_labels) do |label|
      title = (label[:name] || label['name']).to_s.strip
      next if title.blank?

      @account.labels.find_or_create_by!(title: title)
    end
  end

  def backfill_contacts
    each_page(:sync_contacts) do |row|
      jid = row[:jid] || row['jid']
      next if jid.blank?

      phone = jid.to_s.split('@').first.split(':').first.gsub(/\D/, '')
      next if phone.blank?

      name = row[:name] || row['name'] || row[:push_name] || row['push_name'] || phone

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
    loop do
      messages = @provider.sync_messages(chat_jid, page: page, page_size: PAGE_SIZE)
      break if messages.empty?

      dispatch_via_live_tail(messages)
      page += 1
    end
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
