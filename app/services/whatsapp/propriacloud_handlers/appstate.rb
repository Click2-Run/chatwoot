# frozen_string_literal: true

# Propagates phone-side conversation state (read / archive / delete /
# label assignment) into Chatwoot's existing Conversation + Label
# models. We only act on events that have a Chatwoot-side equivalent;
# everything else is no-op (so the curated webhook subscription
# can stay tight without each new event needing a new handler).
#
# Handles event_type:
#   appstate.mark_chat_as_read           → Conversation#last_seen
#   appstate.archive                     → Conversation#resolved
#   appstate.delete_chat                 → Conversation#resolved (no hard delete — Chatwoot retains history)
#   appstate.label_association_chat      → assign / remove Label on Conversation
#   appstate.label_association_message   → assign / remove Label on Message
#   appstate.label_edit                  → upsert Label name/color
module Whatsapp::PropriacloudHandlers::Appstate
  include Whatsapp::PropriacloudHandlers::Helpers

  private

  # Note on labels: WhatsApp labels are a separate taxonomy from
  # Chatwoot's account-level `labels`. We intentionally do NOT handle
  # `appstate.label_edit` / `label_association_chat` /
  # `label_association_message` here, and the propriacloud webhook
  # subscription no longer requests them. If you want to map WhatsApp
  # labels to a custom_attribute or anything else later, add an
  # explicit handler — the implicit "create a Chatwoot label with the
  # same name" bridge was wrong.
  def process_appstate
    data = processed_params[:data] || {}
    event = (processed_params[:event_type] || processed_params['event_type'] ||
             processed_params[:event] || processed_params['event']).to_s

    case event
    when 'appstate.mark_chat_as_read' then appstate_mark_read(data)
    when 'appstate.archive'           then appstate_archive(data)
    when 'appstate.delete_chat'       then appstate_delete_chat(data)
    end
  end

  def conversation_for(jid)
    return nil if jid.blank?

    phone = jid.to_s.split('@').first.split(':').first.gsub(/\D/, '')
    contact_inbox = ContactInbox.find_by(inbox_id: inbox.id, source_id: phone)
    return nil unless contact_inbox

    contact_inbox.conversations.where(status: %i[open pending snoozed]).order(created_at: :desc).first ||
      contact_inbox.conversations.order(created_at: :desc).first
  end

  # AppState events arriving out of order (e.g. retries, slow webhooks)
  # could otherwise toggle a conversation back to a stale state. Drop
  # any event whose own `timestamp` is older than the last update we
  # already applied to the conversation.
  def appstate_event_stale_for?(conversation, data)
    return false if conversation.blank?

    raw = data[:timestamp] || data['timestamp'] ||
          processed_params[:timestamp] || processed_params['timestamp']
    return false if raw.blank?

    event_time = parse_appstate_timestamp(raw)
    return false if event_time.blank?

    conversation.updated_at.present? && event_time < conversation.updated_at
  end

  def parse_appstate_timestamp(raw)
    case raw
    when Integer then Time.at(raw)
    when Float then Time.at(raw)
    when String
      raw.match?(/\A\d+\z/) ? Time.at(raw.to_i) : Time.iso8601(raw) rescue nil # rubocop:disable Style/RescueModifier
    when Time, ActiveSupport::TimeWithZone then raw
    end
  end

  def appstate_mark_read(data)
    conv = conversation_for(data[:chat_jid] || data['chat_jid'])
    return if appstate_event_stale_for?(conv, data)

    conv&.update!(contact_last_seen_at: Time.current)
  end

  def appstate_archive(data)
    conv = conversation_for(data[:chat_jid] || data['chat_jid'])
    return unless conv
    return if appstate_event_stale_for?(conv, data)

    archived = data.fetch(:archived, data['archived'])
    archived ? conv.toggle_status('resolved') : conv.toggle_status('open')
  end

  def appstate_delete_chat(data)
    conv = conversation_for(data[:chat_jid] || data['chat_jid'])
    return if appstate_event_stale_for?(conv, data)

    conv&.toggle_status('resolved')
  end

end
