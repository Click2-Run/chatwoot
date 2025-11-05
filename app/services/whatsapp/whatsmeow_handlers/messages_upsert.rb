# frozen_string_literal: true

# Whatsmeow Messages Upsert Handler
# Processes incoming and outgoing messages from Whatsmeow
#
# Event payload format from Whatsmeow:
# {
#   event: "messages.upsert",
#   instance_id: "1234567890",
#   timestamp: 1699123456,
#   data: {
#     messages: [
#       {
#         key: {
#           id: "message_id",
#           remote_jid: "1234567890@s.whatsapp.net",
#           from_me: false,
#           sender_lid: "optional_lid"
#         },
#         message: {...},  # Message content
#         push_name: "Contact Name",
#         message_timestamp: 1699123456
#       }
#     ]
#   }
# }

module Whatsapp::WhatsmeowHandlers::MessagesUpsert
  include Whatsapp::WhatsmeowHandlers::Helpers

  private

  def process_messages_upsert
    messages_data = processed_params[:data]
    messages = messages_data.is_a?(Hash) ? messages_data[:messages] || messages_data['messages'] : messages_data
    messages = [messages] unless messages.is_a?(Array)

    messages.each do |message|
      @message = nil
      @contact_inbox = nil
      @contact = nil
      @raw_message = message

      next handle_message if incoming?

      # Shared lock with Whatsapp::SendOnWhatsappService
      # Avoids race conditions when sending messages
      with_baileys_channel_lock_on_outgoing_message(inbox.channel.id) { handle_message }
    end
  end

  def handle_message # rubocop:disable Metrics/CyclomaticComplexity
    return unless %w[lid user].include?(jid_type)
    return if jid_type == 'lid' && !phone_number_from_jid
    return if ignore_message?
    return if find_message_by_source_id(raw_message_id) || message_under_process?

    cache_message_source_id_in_redis
    set_contact

    unless @contact
      clear_message_source_id_from_redis
      Rails.logger.warn "Contact not found for message: #{raw_message_id}"
      return
    end

    set_conversation
    handle_create_message
    clear_message_source_id_from_redis
  end

  def set_contact
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: phone_number_from_jid,
      inbox: inbox,
      contact_attributes: {
        name: contact_name,
        phone_number: "+#{phone_number_from_jid}",
        identifier: sender_lid
      }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact

    update_contact_information
  end

  def update_contact_information
    updates = {}
    updates[:identifier] = sender_lid if @contact.identifier.blank? && sender_lid.present?
    updates[:phone_number] = "+#{phone_number_from_jid}" if @contact.phone_number.blank?
    updates[:name] = contact_name if @contact.name == phone_number_from_jid || @contact.name == sender_lid

    @contact.update!(updates) if updates.present?

    try_update_contact_avatar
  end

  def handle_create_message
    create_message(attach_media: %w[image file video audio sticker].include?(message_type))
  end

  def create_message(attach_media: false)
    @message = @conversation.messages.build(
      content: message_content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      source_id: raw_message_id,
      sender: incoming? ? @contact : @inbox.account.account_users.first.user,
      sender_type: incoming? ? 'Contact' : 'User',
      message_type: incoming? ? :incoming : :outgoing,
      content_attributes: message_content_attributes
    )

    handle_attach_media if attach_media

    @message.save!

    inbox.channel.received_messages([@message], @conversation) if incoming?
  end

  def message_content_attributes
    type = message_type
    content_attributes = { external_created_at: extract_message_timestamp }

    if type == 'reaction'
      content_attributes[:in_reply_to_external_id] = extract_reaction_message_id
      content_attributes[:is_reaction] = true
    elsif type == 'unsupported'
      content_attributes[:is_unsupported] = true
    end

    content_attributes
  end

  def extract_message_timestamp
    # Whatsmeow uses Unix timestamps (int64)
    timestamp = @raw_message[:message_timestamp] || @raw_message['message_timestamp'] || @raw_message[:messageTimestamp]
    return extract_timestamp(timestamp) if timestamp

    Time.current
  end

  def extract_reaction_message_id
    msg = @raw_message[:message] || @raw_message
    msg.dig(:reaction_message, :key, :id) ||
      msg.dig(:reaction_message, 'key', 'id') ||
      msg.dig('reaction_message', 'key', 'id')
  end

  def handle_attach_media
    attachment_file = download_attachment_file

    attachment = @message.attachments.build(
      account_id: @message.account_id,
      file_type: file_content_type.to_s,
      file: { io: attachment_file, filename: filename, content_type: message_mimetype }
    )

    # Check if it's a recorded audio message (PTT - Push-to-Talk)
    msg = @raw_message[:message] || @raw_message
    is_ptt = msg.dig(:audio_message, :ptt) || msg.dig(:audio_message, 'ptt')
    attachment.meta = { is_recorded_audio: true } if is_ptt
  rescue Down::Error => e
    @message.update!(is_unsupported: true)
    Rails.logger.error "Failed to download attachment for message #{raw_message_id}: #{e.message}"
  end

  def download_attachment_file
    # Whatsmeow provides media download endpoint
    media_url = @conversation.inbox.channel.media_url(raw_message_id)
    Down.download(media_url, headers: @conversation.inbox.channel.api_headers)
  end

  def filename
    msg = @raw_message[:message] || @raw_message
    # Try to get filename from document message
    filename = msg.dig(:document_message, :file_name) ||
               msg.dig(:document_message, 'file_name') ||
               msg.dig('document_message', 'file_name')
    return filename if filename.present?

    # Generate filename based on type and timestamp
    ext = extract_file_extension
    "#{file_content_type}_#{raw_message_id}_#{Time.current.strftime('%Y%m%d')}#{ext}"
  end

  def extract_file_extension
    return '' unless message_mimetype.present?

    mime_parts = message_mimetype.split(';').first.split('/')
    ext = mime_parts.last
    ".#{ext}"
  end
end
