# frozen_string_literal: true

# Propriacloud Group Message Handler
#
# Ingests inbound/outbound messages whose `key.remote_jid` is a group
# (`<id>@g.us`) into Chatwoot group conversations, reaching parity with the
# baileys provider. Reuses the channel-agnostic GroupConversationHandler
# (group Contact + Conversation + GroupMember modeling) and the propriacloud
# message-parsing helpers (message_type/content/media download) so a group
# message flows through the SAME create pipeline as a 1:1 one.
#
# Gated by Whatsapp::Providers::WhatsappPropriacloudService.groups_enabled?
# at the messages_upsert routing layer, so a group-disabled install behaves
# exactly as before (group messages ignored).
#
# JID mapping (whatsmeow/protobuf → Chatwoot):
# - group_jid   : key.remote_jid   → group Contact#identifier & ContactInbox#source_id
#                 (full "<id>@g.us" so the outbound send path routes to g.us)
# - participant : key.participant   → the actual sender (a 1:1 phone contact)
module Whatsapp::PropriacloudHandlers::GroupMessage
  include GroupConversationHandler

  private

  def handle_group_message
    return if ignore_message?
    return if find_message_by_source_id(raw_message_id) || message_under_process?

    cache_message_source_id_in_redis
    process_group_message
  ensure
    clear_message_source_id_from_redis
  end

  def process_group_message
    @group_contact_inbox, @group_contact = find_or_create_group_contact
    @sender_contact = find_or_create_sender_contact
    add_group_member(@group_contact, @sender_contact) if @sender_contact

    # Incoming group messages must have a resolvable sender contact; drop the
    # ones we cannot attribute rather than persisting a senderless bubble.
    return if incoming? && @sender_contact.blank?

    @conversation = find_or_create_group_conversation(@group_contact_inbox)
    @contact_inbox = @group_contact_inbox
    @contact = incoming? ? @sender_contact : @group_contact

    handle_create_message

    # Keep group metadata/membership fresh without blocking ingestion. Soft
    # sync (no invite/avatar round-trips), rate-limited inside SyncGroupJob.
    Contacts::SyncGroupJob.perform_later(@group_contact, soft: true) if @group_contact
  end

  # ---- GroupConversationHandler abstract implementations ----

  def group_jid
    @raw_message[:key][:remote_jid] || @raw_message[:remote_jid]
  end

  # Full "<id>@g.us" — stored as Contact#identifier (no regex constraint) and
  # used as the group JID by the group-management controllers and the send path.
  def extract_group_identifier
    group_jid
  end

  # ContactInbox#source_id must match the WhatsApp digits regex, so it holds
  # the bare group id (digits) rather than the full "<id>@g.us" JID.
  def extract_group_source_id
    group_jid.to_s.split('@').first
  end

  # Group display name is resolved lazily by SyncGroupJob → /groups/info;
  # until then GroupConversationHandler falls back to the source_id.
  def extract_group_name
    nil
  end

  def extract_sender_identifier
    lid = group_sender_lid
    lid ? "#{lid}@lid" : nil
  end

  def extract_sender_source_id
    group_sender_phone || group_sender_lid
  end

  def extract_sender_name
    @raw_message[:push_name].presence || @raw_message[:pushname].presence ||
      group_sender_phone || group_sender_lid
  end

  def extract_sender_phone
    phone = group_sender_phone
    "+#{phone}" if phone.present?
  end

  # ---- sender (participant) JID parsing ----

  def participant_jid
    key = @raw_message[:key] || {}
    key[:participant] || key['participant'] ||
      key[:participant_alt] || key['participant_alt'] ||
      @raw_message[:participant] || @raw_message['participant']
  end

  def group_sender_phone
    jid = participant_jid.to_s
    return if jid.blank?
    return if jid.split('@')[1] == 'lid' # lid JIDs carry no phone number

    digits = jid.split('@').first.to_s.split(':').first.gsub(/\D/, '')
    digits.presence
  end

  def group_sender_lid
    jid = participant_jid.to_s
    return unless jid.split('@')[1] == 'lid'

    part = jid.split('@').first.to_s.split(':').first
    part if part.match?(/^\d+$/)
  end
end
