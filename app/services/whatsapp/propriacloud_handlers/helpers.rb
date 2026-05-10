# frozen_string_literal: true

# Propriacloud Event Handlers - Helper Methods
# Adapted from Baileys handlers for Propriacloud event format
#
# Key Differences from Baileys:
# - Timestamp format: Unix int64 (not {low, high, unsigned})
# - Event structure: Simpler, more standardized
# - JID format: Same as Baileys (phone@s.whatsapp.net)
# - Message keys: Slightly different nesting

module Whatsapp::PropriacloudHandlers::Helpers # rubocop:disable Metrics/ModuleLength
  include Whatsapp::IncomingMessageServiceHelpers

  private

  def raw_message_id
    @raw_message[:key][:id] || @raw_message[:id]
  end

  def sender_lid
    # Propriacloud doesn't use LID in the same way as Baileys
    # LID (Linked ID) is handled internally by propriacloud
    @raw_message[:key][:sender_lid] || @raw_message[:sender_lid]
  end

  def incoming?
    !(@raw_message[:key][:from_me] || @raw_message[:from_me])
  end

  def jid_type # rubocop:disable Metrics/CyclomaticComplexity
    jid = @raw_message[:key][:remote_jid] || @raw_message[:remote_jid]
    return 'unknown' unless jid

    server = jid.split('@').last

    # Based on WhatsApp JID format (same as Baileys)
    case server
    when 's.whatsapp.net', 'c.us'
      'user'
    when 'g.us'
      'group'
    when 'lid'
      'lid'
    when 'broadcast'
      jid.start_with?('status@') ? 'status' : 'broadcast'
    when 'newsletter'
      'newsletter'
    when 'call'
      'call'
    else
      'unknown'
    end
  end

  def message_type # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength,Metrics/AbcSize
    msg = @raw_message[:message] || @raw_message
    return 'unsupported' unless msg.is_a?(Hash)

    # Propriacloud uses similar message structure to Baileys
    if msg.key?(:conversation) || msg.dig(:extended_text_message, :text).present? || msg.dig(:text_message, :text).present?
      'text'
    elsif msg.key?(:image_message)
      'image'
    elsif msg.key?(:audio_message)
      'audio'
    elsif msg.key?(:video_message)
      'video'
    elsif msg.key?(:document_message) || msg.key?(:document_with_caption_message)
      'file'
    elsif msg.key?(:sticker_message)
      'sticker'
    elsif msg.key?(:reaction_message)
      'reaction'
    elsif msg.key?(:edited_message)
      'edited'
    elsif msg.key?(:contact_message)
      match_phone_number = msg.dig(:contact_message, :vcard)&.match(/waid=(\d+)/)
      match_phone_number ? 'contact' : 'unsupported'
    elsif msg.key?(:protocol_message)
      'protocol'
    elsif msg.key?(:message_context_info) && msg.keys.count == 1
      'context'
    else
      'unsupported'
    end
  end

  def message_content # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
    msg = @raw_message[:message] || @raw_message
    return nil unless msg.is_a?(Hash)

    case message_type
    when 'text'
      msg[:conversation] || msg.dig(:extended_text_message, :text) || msg.dig(:text_message, :text)
    when 'image'
      msg.dig(:image_message, :caption)
    when 'video'
      msg.dig(:video_message, :caption)
    when 'file'
      msg.dig(:document_message, :caption).presence ||
        msg.dig(:document_with_caption_message, :message, :document_message, :caption)
    when 'reaction'
      msg.dig(:reaction_message, :text) || msg.dig(:reaction_message, :emoji)
    when 'contact'
      display_name = msg.dig(:contact_message, :display_name)
      vcard = msg.dig(:contact_message, :vcard)
      match_phone_number = vcard&.match(/waid=(\d+)/)

      return display_name unless match_phone_number
      return match_phone_number[1] if display_name&.start_with?('+')

      "#{display_name} - #{match_phone_number[1]}" if match_phone_number
    end
  end

  def file_content_type
    return :image if message_type.in?(%w[image sticker])
    return :video if message_type.in?(%w[video video_note])
    return :audio if message_type == 'audio'

    :file
  end

  def message_mimetype
    msg = @raw_message[:message] || @raw_message
    return nil unless msg.is_a?(Hash)

    case message_type
    when 'image'
      msg.dig(:image_message, :mime_type) || msg.dig(:image_message, :mimetype)
    when 'sticker'
      msg.dig(:sticker_message, :mime_type) || msg.dig(:sticker_message, :mimetype)
    when 'video'
      msg.dig(:video_message, :mime_type) || msg.dig(:video_message, :mimetype)
    when 'audio'
      msg.dig(:audio_message, :mime_type) || msg.dig(:audio_message, :mimetype)
    when 'file'
      msg.dig(:document_message, :mime_type) || msg.dig(:document_message, :mimetype) ||
        msg.dig(:document_with_caption_message, :message, :document_message, :mime_type)
    end
  end

  def phone_number_from_jid
    jid = @raw_message[:key][:remote_jid] || @raw_message[:remote_jid]
    return unless jid

    # JID shape: <phone>@s.whatsapp.net or <phone>:<device>@s.whatsapp.net
    # Extract phone number (digits only)
    jid.split('@').first.split(':').first.gsub(/\D/, '')
  end

  def contact_name
    # Propriacloud provides push_name in events
    name = @raw_message[:verified_biz_name].presence ||
           @raw_message[:push_name].presence ||
           @raw_message[:pushname].presence
    return name if name.present? && (self_message? || incoming?)

    phone_number_from_jid
  end

  def self_message?
    phone_number_from_jid == inbox.channel.phone_number.delete('+')
  end

  def ignore_message?
    message_type.in?(%w[protocol context edited]) ||
      (message_type == 'reaction' && message_content.blank?)
  end

  def fetch_profile_picture_url(phone_number)
    jid = "#{phone_number}@s.whatsapp.net"
    inbox.channel.provider_service.get_profile_pic(jid)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch profile picture for #{phone_number}: #{e.message}"
    nil
  end

  def try_update_contact_avatar
    return if @contact.avatar.attached?

    profile_pic_url = fetch_profile_picture_url(phone_number_from_jid)
    ::Avatar::AvatarFromUrlJob.perform_later(@contact, profile_pic_url) if profile_pic_url
  end

  # Redis lock key includes inbox.id so two propriacloud inboxes that happen
  # to receive a message with the same WhatsApp `key.id` don't shadow each
  # other's processing. WhatsApp message ids are random 10-byte strings so
  # collisions are vanishingly rare in practice, but the prefix keeps us
  # consistent with the baileys/zapi paths and removes a future foot-gun.
  def message_processing_lock_key
    format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: "#{inbox.id}_#{raw_message_id}")
  end

  def message_under_process?
    Redis::Alfred.get(message_processing_lock_key)
  end

  def cache_message_source_id_in_redis
    ::Redis::Alfred.setex(message_processing_lock_key, true)
  end

  def clear_message_source_id_from_redis
    ::Redis::Alfred.delete(message_processing_lock_key)
  end

  # Propriacloud uses Unix timestamps (int64), not Baileys' {low, high, unsigned}
  def extract_timestamp(timestamp_value)
    return Time.current unless timestamp_value

    # If it's already an integer timestamp
    return Time.at(timestamp_value) if timestamp_value.is_a?(Integer)

    # If it's a string, convert to integer
    return Time.at(timestamp_value.to_i) if timestamp_value.is_a?(String) && timestamp_value.match?(/^\d+$/)

    # Fallback to current time
    Time.current
  end
end
