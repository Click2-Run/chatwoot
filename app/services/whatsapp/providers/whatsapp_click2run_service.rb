# frozen_string_literal: true

# Click2Run WhatsApp Provider Service for Chatwoot
# Integrates with the Click2Run API via Click2Run
#
# Architecture:
# - Uses Click2Run (/root/data/development/click2run/delivery.git/click2run/)
# - Replaces Baileys with production-ready multi-device protocol support
# - Supports all critical WhatsApp operations: messages, media, reactions, typing, read receipts
#
# Configuration:
# - CLICK2RUN_PROVIDER_DEFAULT_URL: Click2Run base URL WITHOUT /chatwoot suffix (e.g., http://localhost:8080/api/v1)
# - CLICK2RUN_PROVIDER_DEFAULT_API_KEY: Tenant API key for authentication
#
# API Structure:
# - Base URL: http://localhost:8080/api/v1 (from env or user config)
# - All endpoints append: /chatwoot/{account_id}/inboxes/...
# - Example full URL: http://localhost:8080/api/v1/chatwoot/123/inboxes/456/messages/send/text
# - Channel ID format: {account_id}_{inbox_id} (not phone number)
#
# @see /root/data/development/chatwoot.git/.llm/planning/20251104_click2run_integration_plan.md
# @see /root/data/development/click2run/delivery.git/click2run/.llm/implementation/20251104140000_all_features_complete.md

class Whatsapp::Providers::WhatsappClick2RunService < Whatsapp::Providers::BaseService
  include BaileysHelper # Reuse timestamp extraction helper

  class MessageContentTypeNotSupported < StandardError; end
  class ProviderUnavailableError < StandardError; end

  # Environment configuration
  DEFAULT_URL = ENV.fetch('CLICK2RUN_PROVIDER_DEFAULT_URL', nil)
  DEFAULT_API_KEY = ENV.fetch('CLICK2RUN_PROVIDER_DEFAULT_API_KEY', nil)

  # Service status check (class method)
  def self.status
    if DEFAULT_URL.blank? || DEFAULT_API_KEY.blank?
      raise ProviderUnavailableError, 'Missing CLICK2RUN_PROVIDER_DEFAULT_URL or CLICK2RUN_PROVIDER_DEFAULT_API_KEY'
    end

    response = HTTParty.get(
      "#{DEFAULT_URL}/health",
      headers: { 'X-API-Key' => DEFAULT_API_KEY }
    )

    unless response.success?
      Rails.logger.error response.body
      raise ProviderUnavailableError, 'Click2Run is unavailable'
    end

    response.parsed_response.deep_symbolize_keys
  end

  # Setup channel provider (create inbox + connect)
  # Click2Run uses two-step process: 1) create inbox 2) connect
  def setup_channel_provider
    # Step 1: Create inbox if not exists
    inbox = whatsapp_channel.inbox
    admin_user = find_account_admin

    create_instance_response = HTTParty.post(
      "#{provider_url}/chatwoot/#{inbox.account_id}/inboxes",
      headers: api_headers,
      body: {
        inbox_id: inbox.id,
        name: inbox.name,
        account_id: inbox.account_id,
        channel_type: inbox.channel_type,
        channel_id: inbox.channel_id,
        phone_number: whatsapp_channel.phone_number,
        provider: whatsapp_channel.provider,
        admin_id: admin_user.id,
        admin_token: admin_user.access_token.token,
        webhook_url: inbox_webhook_url,
        webhook_token: whatsapp_channel.provider_config['webhook_verify_token'],
        api_url: chatwoot_api_url
      }.to_json
    )

    # 404 or 409 (already exists) is OK, continue to connect
    unless [200, 201, 409].include?(create_instance_response.code)
      Rails.logger.error create_instance_response.body
      raise ProviderUnavailableError, 'Failed to create Click2Run inbox'
    end

    # Step 2: Connect inbox (initiates QR code generation)
    connect_response = HTTParty.post(
      "#{provider_url}/chatwoot/#{inbox.account_id}/inboxes/#{inbox.id}/connect",
      headers: api_headers
    )

    unless process_response(connect_response)
      raise ProviderUnavailableError, 'Failed to connect Click2Run channel'
    end

    # TODO: Webhook configuration
    # Click2Run supports webhook delivery for events
    # Future enhancement: Configure webhook URL and verify token
    # POST /channels/:id/webhook with {url, secret}

    true
  end

  # Disconnect channel provider (disconnect + delete channel)
  def disconnect_channel_provider
    inbox = whatsapp_channel.inbox
    account_id = inbox.account_id
    inbox_id = inbox.id

    # Step 1: Disconnect channel (graceful disconnection)
    disconnect_response = HTTParty.post(
      "#{provider_url}/chatwoot/#{account_id}/inboxes/#{inbox_id}/disconnect",
      headers: api_headers
    )

    # Log error but don't fail if already disconnected
    unless process_response(disconnect_response)
      Rails.logger.warn "Failed to disconnect Click2Run channel (may already be disconnected)"
    end

    # Step 2: Delete channel
    delete_response = HTTParty.delete(
      "#{provider_url}/chatwoot/#{account_id}/inboxes/#{inbox_id}",
      headers: api_headers
    )

    unless process_response(delete_response)
      raise ProviderUnavailableError, 'Failed to delete Click2Run channel'
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

  # Send template (not implemented for click2run - templates are for WhatsApp Business API)
  def send_template(phone_number, template_info)
    # Click2Run doesn't support templates (those are WhatsApp Business API specific)
    # Left empty for compatibility
  end

  # Sync templates (not implemented for click2run)
  def sync_templates
    # Click2Run doesn't support templates
    # Left empty for compatibility
  end

  # Get media URL for download
  # Click2Run uses message_id to download media
  def media_url(media_id)
    inbox = whatsapp_channel.inbox
    account_id = inbox.account_id
    inbox_id = inbox.id
    "#{provider_url}/chatwoot/#{account_id}/inboxes/#{inbox_id}/media/#{media_id}"
  end

  # API headers for authentication
  def api_headers
    { 'X-API-Key' => api_key, 'Content-Type' => 'application/json' }
  end

  # Validate provider configuration
  # Called during channel creation (before inbox is saved)
  # Validates API credentials by listing inboxes for the account
  def validate_provider_config?
    account_id = whatsapp_channel.inbox.account_id

    response = HTTParty.get(
      "#{provider_url}/chatwoot/#{account_id}/inboxes",
      headers: api_headers
    )

    # Accept 200 OK (empty list or existing inboxes)
    # Reject any error (401 Unauthorized, 403 Forbidden, 500 Server Error, etc.)
    process_response(response)
  end

  # Toggle typing status (composing/recording/paused)
  def toggle_typing_status(typing_status, phone_number:, **)
    @phone_number = phone_number
    inbox = whatsapp_channel.inbox
    account_id = inbox.account_id
    inbox_id = inbox.id

    # Map Chatwoot events to Click2Run presence types
    status_map = {
      Events::Types::CONVERSATION_TYPING_ON => 'composing',
      Events::Types::CONVERSATION_RECORDING => 'recording',
      Events::Types::CONVERSATION_TYPING_OFF => 'paused'
    }

    response = HTTParty.patch(
      "#{provider_url}/chatwoot/#{account_id}/inboxes/#{inbox_id}/presence",
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
  # Note: Click2Run doesn't currently expose account-level presence
  # This is chat-level presence (typing indicators) only
  def update_presence(status)
    # Not implemented in current Click2Run
    # Click2Run focuses on chat presence (typing) rather than account presence (online/offline)
    Rails.logger.debug "Account presence update not supported in Click2Run: #{status}"
    true
  end

  # Mark messages as read
  def read_messages(messages, phone_number:, **)
    @phone_number = phone_number
    inbox = whatsapp_channel.inbox
    account_id = inbox.account_id
    inbox_id = inbox.id

    response = HTTParty.post(
      "#{provider_url}/chatwoot/#{account_id}/inboxes/#{inbox_id}/messages/mark-read",
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
  # Note: Not currently implemented in Click2Run
  def unread_message(phone_number, message)
    @phone_number = phone_number
    # Not implemented in current Click2Run
    Rails.logger.debug "Unread message not supported in Click2Run"
    true
  end

  # Send received receipts
  # Note: Click2Run handles this automatically at protocol level
  def received_messages(phone_number, messages)
    @phone_number = phone_number
    # Click2Run automatically sends received receipts at protocol level
    # No explicit API call needed
    Rails.logger.debug "Received receipts handled automatically by Click2Run"
    true
  end

  # Get profile picture URL
  def get_profile_pic(jid)
    inbox = whatsapp_channel.inbox
    account_id = inbox.account_id
    inbox_id = inbox.id
    response = HTTParty.get(
      "#{provider_url}/chatwoot/#{account_id}/inboxes/#{inbox_id}/profile-picture/#{jid}",
      headers: api_headers,
      query: { preview: false } # Get full quality by default
    )

    return nil unless process_response(response)

    # Click2Run returns: {status: "success", jid: "...", url: "https://...", preview: false}
    response.parsed_response['url']
  end

  # Check if phone number is on WhatsApp
  def on_whatsapp(phone_number)
    @phone_number = phone_number
    inbox = whatsapp_channel.inbox
    account_id = inbox.account_id
    inbox_id = inbox.id

    # Click2Run uses GET endpoint (Baileys uses POST)
    response = HTTParty.get(
      "#{provider_url}/chatwoot/#{account_id}/inboxes/#{inbox_id}/on_whatsapp/#{phone_number}",
      headers: api_headers
    )

    unless process_response(response)
      raise ProviderUnavailableError, 'Failed to check WhatsApp registration'
    end

    # Click2Run returns: {status: "success", query: "...", jid: "...", is_in: true/false}
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

  # Find the first administrator user for the account
  # Chatwoot guarantees at least one undeletable admin per account
  def find_account_admin
    account = whatsapp_channel.inbox.account
    admin_user = account.account_users.find_by(role: :administrator)&.user

    raise ProviderUnavailableError, 'No administrator found for account' unless admin_user

    # Ensure user has an access token
    admin_user.access_token || admin_user.create_access_token

    admin_user
  end

  # Generate webhook URL for this inbox
  # Format: https://chatwoot.example.com/webhooks/whatsapp/{phone_number}
  def inbox_webhook_url
    base_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    "#{base_url}/webhooks/whatsapp/#{whatsapp_channel.phone_number}"
  end

  # Get Chatwoot API URL
  # Format: https://chatwoot.example.com/api/v1
  def chatwoot_api_url
    base_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    "#{base_url}/api/v1"
  end

  # Get normalized phone number (digits only)
  # Used for JID formatting
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
    inbox = whatsapp_channel.inbox
    account_id = inbox.account_id
    inbox_id = inbox.id

    # Check if this is a reply (quoted message)
    quoted_message_id = nil
    if @message.in_reply_to.present?
      reply_to = Message.find(@message.in_reply_to)
      quoted_message_id = reply_to.source_id if reply_to
    end

    response = HTTParty.post(
      "#{provider_url}/chatwoot/#{account_id}/inboxes/#{inbox_id}/messages/send/text",
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
    inbox = whatsapp_channel.inbox
    account_id = inbox.account_id
    inbox_id = inbox.id
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
      "#{provider_url}/chatwoot/#{account_id}/inboxes/#{inbox_id}/messages/send/media",
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
    inbox = whatsapp_channel.inbox
    account_id = inbox.account_id
    inbox_id = inbox.id
    reply_to = Message.find(@message.in_reply_to)

    response = HTTParty.post(
      "#{provider_url}/chatwoot/#{account_id}/inboxes/#{inbox_id}/messages/send/reaction",
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
      Rails.logger.error "Click2Run authentication failed: #{response.body}"
      false
    when 404
      Rails.logger.error "Click2Run instance not found: #{response.body}"
      false
    else
      Rails.logger.error "Click2Run error: #{response.code} - #{response.body}"
      false
    end
  end

  # Update message external_created_at timestamp
  def update_external_created_at(response)
    # Click2Run doesn't return timestamp in same format as Baileys
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
      Rails.logger.error "Failed to reconnect Click2Run channel after error: #{e.message}"
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
