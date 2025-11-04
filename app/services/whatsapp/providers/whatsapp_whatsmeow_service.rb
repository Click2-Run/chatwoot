# frozen_string_literal: true

# Whatsmeow WhatsApp Provider Service for Chatwoot
# Integrates with the Whatsmeow Multi-Device API
#
# Architecture:
# - Uses Whatsmeow API (/root/data/development/click2run/delivery.git/whatsmeow/)
# - Replaces Baileys with production-ready multi-device protocol support
# - Supports all critical WhatsApp operations: messages, media, reactions, typing, read receipts
#
# Configuration:
# - WHATSMEOW_PROVIDER_DEFAULT_URL: Whatsmeow API base URL (e.g., http://localhost:8080/api/v1/whatsmeow)
# - WHATSMEOW_PROVIDER_DEFAULT_API_KEY: Tenant API key for authentication
#
# @see /root/data/development/chatwoot.git/.llm/planning/20251104_whatsmeow_integration_plan.md
# @see /root/data/development/click2run/delivery.git/whatsmeow/.llm/implementation/20251104140000_all_features_complete.md

class Whatsapp::Providers::WhatsappWhatsmeowService < Whatsapp::Providers::BaseService
  include BaileysHelper # Reuse timestamp extraction helper

  class MessageContentTypeNotSupported < StandardError; end
  class ProviderUnavailableError < StandardError; end

  # Environment configuration
  DEFAULT_URL = ENV.fetch('WHATSMEOW_PROVIDER_DEFAULT_URL', nil)
  DEFAULT_API_KEY = ENV.fetch('WHATSMEOW_PROVIDER_DEFAULT_API_KEY', nil)

  # Service status check (class method)
  def self.status
    if DEFAULT_URL.blank? || DEFAULT_API_KEY.blank?
      raise ProviderUnavailableError, 'Missing WHATSMEOW_PROVIDER_DEFAULT_URL or WHATSMEOW_PROVIDER_DEFAULT_API_KEY'
    end

    response = HTTParty.get(
      "#{DEFAULT_URL}/health",
      headers: { 'X-API-Key' => DEFAULT_API_KEY }
    )

    unless response.success?
      Rails.logger.error response.body
      raise ProviderUnavailableError, 'Whatsmeow API is unavailable'
    end

    response.parsed_response.deep_symbolize_keys
  end

  # Setup channel provider (create instance + connect)
  # Whatsmeow uses two-step process: 1) create instance 2) connect
  def setup_channel_provider
    # Step 1: Create instance if not exists
    instance_id = normalized_phone_number
    create_instance_response = HTTParty.post(
      "#{provider_url}/instances",
      headers: api_headers,
      body: {
        instance_id: instance_id,
        phone_number: whatsapp_channel.phone_number
      }.to_json
    )

    # 404 or 409 (already exists) is OK, continue to connect
    unless [200, 201, 409].include?(create_instance_response.code)
      Rails.logger.error create_instance_response.body
      raise ProviderUnavailableError, 'Failed to create Whatsmeow instance'
    end

    # Step 2: Connect instance (initiates QR code generation)
    connect_response = HTTParty.post(
      "#{provider_url}/instances/#{instance_id}/connect",
      headers: api_headers
    )

    unless process_response(connect_response)
      raise ProviderUnavailableError, 'Failed to connect Whatsmeow instance'
    end

    # TODO: Webhook configuration
    # Whatsmeow API supports webhook delivery for events
    # Future enhancement: Configure webhook URL and verify token
    # POST /instances/:id/webhook with {url, secret}

    true
  end

  # Disconnect channel provider (disconnect + delete instance)
  def disconnect_channel_provider
    instance_id = normalized_phone_number

    # Step 1: Disconnect instance (graceful disconnection)
    disconnect_response = HTTParty.post(
      "#{provider_url}/instances/#{instance_id}/disconnect",
      headers: api_headers
    )

    # Log error but don't fail if already disconnected
    unless process_response(disconnect_response)
      Rails.logger.warn "Failed to disconnect Whatsmeow instance (may already be disconnected)"
    end

    # Step 2: Delete instance
    delete_response = HTTParty.delete(
      "#{provider_url}/instances/#{instance_id}",
      headers: api_headers
    )

    unless process_response(delete_response)
      raise ProviderUnavailableError, 'Failed to delete Whatsmeow instance'
    end

    true
  end

  # Send message (text, media, reaction, or location)
  def send_message(phone_number, message)
    @message = message
    @phone_number = phone_number

    # Determine message type and send accordingly
    if message.content_attributes[:is_reaction]
      send_reaction_message
    elsif message.attachments.present?
      send_media_message
    elsif message.content.present?
      send_text_message
    else
      @message.update!(is_unsupported: true)
      Rails.logger.warn "Unsupported message type", message_id: message.id
    end
  end

  # Send template (not implemented for whatsmeow - templates are for WhatsApp Business API)
  def send_template(phone_number, template_info)
    # Whatsmeow doesn't support templates (those are WhatsApp Business API specific)
    # Left empty for compatibility
  end

  # Sync templates (not implemented for whatsmeow)
  def sync_templates
    # Whatsmeow doesn't support templates
    # Left empty for compatibility
  end

  # Get media URL for download
  # Whatsmeow uses message_id to download media
  def media_url(media_id)
    instance_id = normalized_phone_number
    "#{provider_url}/instances/#{instance_id}/media/#{media_id}"
  end

  # API headers for authentication
  def api_headers
    { 'X-API-Key' => api_key, 'Content-Type' => 'application/json' }
  end

  # Validate provider configuration
  def validate_provider_config?
    instance_id = normalized_phone_number
    response = HTTParty.get(
      "#{provider_url}/instances/#{instance_id}/status",
      headers: api_headers
    )

    process_response(response)
  end

  # Toggle typing status (composing/recording/paused)
  def toggle_typing_status(typing_status, phone_number:, **)
    @phone_number = phone_number
    instance_id = normalized_phone_number

    # Map Chatwoot events to Whatsmeow presence types
    status_map = {
      Events::Types::CONVERSATION_TYPING_ON => 'composing',
      Events::Types::CONVERSATION_RECORDING => 'recording',
      Events::Types::CONVERSATION_TYPING_OFF => 'paused'
    }

    response = HTTParty.patch(
      "#{provider_url}/instances/#{instance_id}/presence",
      headers: api_headers,
      body: {
        to_jid: format_jid(phone_number),
        type: status_map[typing_status]
      }.to_json
    )

    unless process_response(response)
      raise ProviderUnavailableError, 'Failed to update presence'
    end

    true
  end

  # Update account presence (available/unavailable)
  # Note: Whatsmeow API doesn't currently expose account-level presence
  # This is chat-level presence (typing indicators) only
  def update_presence(status)
    # Not implemented in current Whatsmeow API
    # Whatsmeow API focuses on chat presence (typing) rather than account presence (online/offline)
    Rails.logger.debug "Account presence update not supported in Whatsmeow: #{status}"
    true
  end

  # Mark messages as read
  def read_messages(messages, phone_number:, **)
    @phone_number = phone_number
    instance_id = normalized_phone_number

    response = HTTParty.post(
      "#{provider_url}/instances/#{instance_id}/messages/mark-read",
      headers: api_headers,
      body: {
        messages: messages.map do |message|
          {
            id: message.source_id,
            remote_jid: format_jid(phone_number),
            from_me: message.message_type == 'outgoing'
          }
        end
      }.to_json
    )

    unless process_response(response)
      raise ProviderUnavailableError, 'Failed to mark messages as read'
    end

    true
  end

  # Mark chat as unread
  # Note: Not currently implemented in Whatsmeow API
  def unread_message(phone_number, message)
    @phone_number = phone_number
    # Not implemented in current Whatsmeow API
    Rails.logger.debug "Unread message not supported in Whatsmeow"
    true
  end

  # Send received receipts
  # Note: Whatsmeow handles this automatically at protocol level
  def received_messages(phone_number, messages)
    @phone_number = phone_number
    # Whatsmeow automatically sends received receipts at protocol level
    # No explicit API call needed
    Rails.logger.debug "Received receipts handled automatically by Whatsmeow"
    true
  end

  # Get profile picture URL
  def get_profile_pic(jid)
    instance_id = normalized_phone_number
    response = HTTParty.get(
      "#{provider_url}/instances/#{instance_id}/profile-picture/#{jid}",
      headers: api_headers,
      query: { preview: false } # Get full quality by default
    )

    return nil unless process_response(response)

    # Whatsmeow returns: {status: "success", jid: "...", url: "https://...", preview: false}
    response.parsed_response['url']
  end

  # Check if phone number is on WhatsApp
  def on_whatsapp(phone_number)
    @phone_number = phone_number
    instance_id = normalized_phone_number

    # Whatsmeow uses GET endpoint (Baileys uses POST)
    response = HTTParty.get(
      "#{provider_url}/instances/#{instance_id}/on_whatsapp/#{phone_number}",
      headers: api_headers
    )

    unless process_response(response)
      raise ProviderUnavailableError, 'Failed to check WhatsApp registration'
    end

    # Whatsmeow returns: {status: "success", query: "...", jid: "...", is_in: true/false}
    # Convert to Baileys format for compatibility
    parsed = response.parsed_response
    {
      'jid' => parsed['jid'],
      'exists' => parsed['is_in'],
      'lid' => nil # LID not used in multi-device protocol
    }
  end

  private

  # Get provider URL from channel config or default
  def provider_url
    whatsapp_channel.provider_config['provider_url'].presence || DEFAULT_URL
  end

  # Get API key from channel config or default
  def api_key
    whatsapp_channel.provider_config['api_key'].presence || DEFAULT_API_KEY
  end

  # Get normalized phone number (digits only) for instance_id
  def normalized_phone_number
    whatsapp_channel.phone_number.delete('+')
  end

  # Format phone number as WhatsApp JID
  # Example: +1234567890 -> 1234567890@s.whatsapp.net
  def format_jid(phone_number)
    "#{phone_number.delete('+')}@s.whatsapp.net"
  end

  # Send text message
  def send_text_message
    instance_id = normalized_phone_number

    # Check if this is a reply (quoted message)
    quoted_message_id = nil
    if @message.in_reply_to.present?
      reply_to = Message.find(@message.in_reply_to)
      quoted_message_id = reply_to.source_id if reply_to
    end

    response = HTTParty.post(
      "#{provider_url}/instances/#{instance_id}/messages/send/text",
      headers: api_headers,
      body: {
        to: format_jid(@phone_number),
        message: @message.content,
        quoted_message_id: quoted_message_id
      }.compact.to_json
    )

    unless process_response(response)
      raise ProviderUnavailableError, 'Failed to send text message'
    end

    update_external_created_at(response)
    response.parsed_response['message_id']
  end

  # Send media message (image, video, audio, document)
  def send_media_message
    instance_id = normalized_phone_number
    attachment = @message.attachments.first

    # Download attachment and encode as base64
    buffer = Base64.strict_encode64(attachment.file.download)

    # Determine media type
    media_type = case attachment.file_type
                 when 'image'
                   attachment.file.content_type
                 when 'audio'
                   attachment.file.content_type
                 when 'video'
                   attachment.file.content_type
                 when 'file'
                   attachment.file.content_type
                 when 'sticker'
                   'image/webp'
                 else
                   'application/octet-stream'
                 end

    response = HTTParty.post(
      "#{provider_url}/instances/#{instance_id}/messages/send/media",
      headers: api_headers,
      body: {
        to: format_jid(@phone_number),
        media_type: media_type,
        media_data: buffer, # Base64 encoded
        caption: @message.content,
        filename: attachment.file.filename.to_s
      }.compact.to_json
    )

    unless process_response(response)
      raise ProviderUnavailableError, 'Failed to send media message'
    end

    update_external_created_at(response)
    response.parsed_response['message_id']
  end

  # Send reaction message
  def send_reaction_message
    instance_id = normalized_phone_number
    reply_to = Message.find(@message.in_reply_to)

    response = HTTParty.post(
      "#{provider_url}/instances/#{instance_id}/messages/send/reaction",
      headers: api_headers,
      body: {
        to: format_jid(@phone_number),
        message_id: reply_to.source_id,
        emoji: @message.content
      }.to_json
    )

    unless process_response(response)
      raise ProviderUnavailableError, 'Failed to send reaction'
    end

    update_external_created_at(response)
    response.parsed_response['reaction_id']
  end

  # Process HTTP response
  def process_response(response)
    case response.code
    when 200..299
      true
    when 401
      Rails.logger.error "Whatsmeow authentication failed: #{response.body}"
      false
    when 404
      Rails.logger.error "Whatsmeow instance not found: #{response.body}"
      false
    else
      Rails.logger.error "Whatsmeow API error: #{response.code} - #{response.body}"
      false
    end
  end

  # Update message external_created_at timestamp
  def update_external_created_at(response)
    # Whatsmeow doesn't return timestamp in same format as Baileys
    # Set to current time as fallback
    @message.update!(external_created_at: Time.current)
  end

  # Error handling wrapper (same pattern as Baileys)
  private_class_method def self.with_error_handling(*method_names)
    method_names.each do |method_name|
      original_method = instance_method(method_name)

      define_method("#{method_name}_without_error_handling") do |*args, **kwargs, &block|
        original_method.bind_call(self, *args, **kwargs, &block)
      end

      define_method(method_name) do |*args, **kwargs, &block|
        original_method.bind_call(self, *args, **kwargs, &block)
      rescue StandardError => e
        handle_channel_error
        raise e
      end
    end
  end

  # Handle channel error (attempt reconnection)
  def handle_channel_error
    whatsapp_channel.update_provider_connection!(connection: 'close')

    return if @handling_error

    @handling_error = true
    begin
      setup_channel_provider_without_error_handling
    rescue StandardError => e
      Rails.logger.error "Failed to reconnect Whatsmeow channel after error: #{e.message}"
    ensure
      @handling_error = false
    end
  end

  # Apply error handling to critical methods
  with_error_handling :setup_channel_provider,
                      :disconnect_channel_provider,
                      :send_message,
                      :toggle_typing_status,
                      :read_messages,
                      :on_whatsapp
end
