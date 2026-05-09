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

  def process_appstate # rubocop:disable Metrics/CyclomaticComplexity
    data = processed_params[:data] || {}
    event = (processed_params[:event_type] || processed_params['event_type'] ||
             processed_params[:event] || processed_params['event']).to_s

    case event
    when 'appstate.mark_chat_as_read'        then appstate_mark_read(data)
    when 'appstate.archive'                  then appstate_archive(data)
    when 'appstate.delete_chat'              then appstate_delete_chat(data)
    when 'appstate.label_edit'               then appstate_label_edit(data)
    when 'appstate.label_association_chat'   then appstate_label_chat(data)
    when 'appstate.label_association_message' then appstate_label_message(data)
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

  def appstate_mark_read(data)
    conv = conversation_for(data[:chat_jid] || data['chat_jid'])
    conv&.update!(contact_last_seen_at: Time.current)
  end

  def appstate_archive(data)
    conv = conversation_for(data[:chat_jid] || data['chat_jid'])
    return unless conv

    archived = data.fetch(:archived, data['archived'])
    archived ? conv.toggle_status('resolved') : conv.toggle_status('open')
  end

  def appstate_delete_chat(data)
    conv = conversation_for(data[:chat_jid] || data['chat_jid'])
    conv&.toggle_status('resolved')
  end

  # Labels are account-scoped in Chatwoot. Map the WhatsApp label id to
  # a Chatwoot Label by name (whatsapp-api supplies a stable label name).
  def appstate_label_edit(data)
    name = (data[:name] || data['name']).to_s.strip
    return if name.blank?

    inbox.account.labels.find_or_create_by!(title: name)
  end

  def appstate_label_chat(data)
    conv = conversation_for(data[:chat_jid] || data['chat_jid'])
    label = lookup_label(data)
    return unless conv && label

    if data.fetch(:associated, data['associated'])
      conv.add_labels([label.title])
    else
      labels = conv.label_list - [label.title]
      conv.update_labels(labels)
    end
  end

  def appstate_label_message(data)
    # Chatwoot Messages don't have a labels association today — treat as
    # informational. Recorded as additional_attributes for forward
    # compatibility so we don't lose the signal.
    source_id = data.dig(:key, :id) || data['key']&.dig('id')
    label = lookup_label(data)
    return if source_id.blank? || label.nil?

    msg = inbox.messages.find_by(source_id: source_id)
    return unless msg

    attrs = (msg.additional_attributes || {}).dup
    attrs['propriacloud_labels'] = ((attrs['propriacloud_labels'] || []) | [label.title])
    msg.update!(additional_attributes: attrs)
  end

  def lookup_label(data)
    name = (data[:label_name] || data['label_name']).to_s.strip
    return inbox.account.labels.find_by(title: name) if name.present?

    nil
  end
end
