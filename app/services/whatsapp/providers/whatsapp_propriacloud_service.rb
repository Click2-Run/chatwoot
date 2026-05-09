# frozen_string_literal: true

# Propriacloud WhatsApp Provider Service for Chatwoot.
#
# Targets the whatsapp-api OpenAPI 3.1 contract (Propria.Cloud product, Go +
# whatsmeow). Each Chatwoot WhatsApp inbox maps to one whatsapp-api instance
# identified by `provider_config['instance_id']` (UUID, seeded by the channel
# model). The base URL and API key come from env (with backward-compat aliases
# for the legacy PROPRIACLOUD_PROVIDER_DEFAULT_* names).
#
# Surface (paths used here):
#   POST   /instances/create                            create instance record
#   POST   /webhooks?instance_id=...                    register webhook + verify token
#   POST   /instances/connect?instance_id=...           start pairing (QR generation)
#   POST   /instances/disconnect?instance_id=...        graceful disconnect
#   POST   /instances/delete?instance_id=...            remove instance
#   GET    /instances/pair/qrcode?instance_id=...       pull QR (push via webhook is primary)
#   POST   /messages/send?instance_id=...               send text (Web)
#   POST   /messages/send-media?instance_id=...         send media (Web)
#   POST   /messages/react?instance_id=...              send reaction
#   POST   /messages/mark-read?instance_id=...          mark messages as read
#   POST   /presence/chat?instance_id=...               typing/recording/paused
#   GET    /contacts/profile-picture?instance_id=...&jid=...   profile picture
#   GET    /contacts/onwhatsapp?instance_id=...&phone=...      number-on-whatsapp check
#   GET    /health                                      service health
#
# Reference TS implementation: ../propriacloud.git/apps/minha/app/services/whatsapp.server.ts

class Whatsapp::Providers::WhatsappPropriacloudService < Whatsapp::Providers::BaseService
  include BaileysHelper

  class MessageContentTypeNotSupported < StandardError; end
  class ProviderUnavailableError < StandardError; end

  # Backwards-compat env-var cascade. Prefer WHATSAPP_API_* going forward.
  # Legacy CLICK2RUN_PROVIDER_DEFAULT_* retained as final fallback so existing
  # deployments mid-rebrand keep working without env changes.
  DEFAULT_URL = ENV['WHATSAPP_API_URL'].presence ||
                ENV['PROPRIACLOUD_PROVIDER_DEFAULT_URL'].presence ||
                ENV['CLICK2RUN_PROVIDER_DEFAULT_URL']
  DEFAULT_API_KEY = ENV['WHATSAPP_API_KEY'].presence ||
                    ENV['PROPRIACLOUD_PROVIDER_DEFAULT_API_KEY'].presence ||
                    ENV['CLICK2RUN_PROVIDER_DEFAULT_API_KEY']

  # whatsapp-api uses dotted event_type values like `connection.connected`,
  # `message.received`, `message.sent`, `message.edited`, `presence.update`,
  # etc. (105 total per OpenAPI). `*` is the catch-all wildcard the API
  # supports — future-proof against new event types and lets us handle
  # whichever subset our handlers can dispatch.
  DEFAULT_WEBHOOK_EVENTS = %w[*].freeze

  def self.status
    if DEFAULT_URL.blank? || DEFAULT_API_KEY.blank?
      raise ProviderUnavailableError, 'Missing WHATSAPP_API_URL or WHATSAPP_API_KEY (or legacy PROPRIACLOUD_PROVIDER_DEFAULT_*)'
    end

    response = HTTParty.get("#{DEFAULT_URL}/health", headers: { 'X-API-Key' => DEFAULT_API_KEY })

    unless response.success?
      Rails.logger.error response.body
      raise ProviderUnavailableError, 'whatsapp-api is unavailable'
    end

    body = response.parsed_response
    body = JSON.parse(body) if body.is_a?(String)
    body.deep_symbolize_keys
  end

  # Three-call setup: create instance → register webhook → connect.
  # Idempotent against existing instances (409 on create is treated as success).
  def setup_channel_provider
    create_response = HTTParty.post(
      "#{provider_url}/instances/create",
      headers: api_headers,
      body: {
        instance_id: instance_id,
        name: whatsapp_channel.inbox.name,
        phone: normalized_phone_number,
        custom_id: "chatwoot:account:#{whatsapp_channel.inbox.account_id}:inbox:#{whatsapp_channel.inbox.id}"
      }.compact.to_json
    )

    unless [200, 201, 409].include?(create_response.code)
      Rails.logger.error create_response.body
      raise ProviderUnavailableError, 'Failed to create whatsapp-api instance'
    end

    register_webhook!

    connect_response = HTTParty.post(
      "#{provider_url}/instances/connect#{instance_query}",
      headers: api_headers
    )

    unless process_response(connect_response)
      raise ProviderUnavailableError, 'Failed to connect whatsapp-api instance'
    end

    true
  end

  def disconnect_channel_provider
    disconnect_response = HTTParty.post(
      "#{provider_url}/instances/disconnect#{instance_query}",
      headers: api_headers
    )

    Rails.logger.warn "Failed to disconnect whatsapp-api instance (may already be disconnected)" unless process_response(disconnect_response)

    delete_response = HTTParty.post(
      "#{provider_url}/instances/delete#{instance_query}",
      headers: api_headers
    )

    raise ProviderUnavailableError, 'Failed to delete whatsapp-api instance' unless process_response(delete_response)

    true
  end

  def send_message(phone_number, message)
    @message = message
    @phone_number = phone_number

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

  # whatsapp-api Web mode does not consume Cloud-API templates. WABA mode handles
  # templates via separate /templates/* endpoints (deferred to Phase 5b.2).
  def send_template(_phone_number, _template_info); end

  def sync_templates; end

  # Legacy callers expect a media URL; whatsapp-api uses POST /media/download
  # with the raw message body. Kept for interface parity but actual download
  # happens via {#download_media}.
  def media_url(_media_id)
    "#{provider_url}/media/download#{instance_query}"
  end

  # POST the raw message back to whatsapp-api and return the decrypted bytes
  # as a StringIO. See OpenAPI: /media/download (line 6666).
  def download_media(raw_message)
    response = HTTParty.post(
      "#{provider_url}/media/download#{instance_query}",
      headers: api_headers,
      body: { message: raw_message }.to_json
    )

    raise Down::Error, "media download failed: #{response.code} #{response.body}" unless response.success?

    body = unwrap(response.parsed_response)
    encoded = body['data'] || body['body'] || body['file']
    raise Down::Error, "media download response missing data: #{response.body}" if encoded.blank?

    StringIO.new(Base64.decode64(encoded))
  end

  def api_headers
    { 'X-API-Key' => api_key, 'Content-Type' => 'application/json' }
  end

  def validate_provider_config?
    response = HTTParty.get("#{provider_url}/health", headers: api_headers)
    process_response(response)
  end

  def toggle_typing_status(typing_status, recipient_id: nil, phone_number: nil, **)
    @phone_number = recipient_id || phone_number

    presence_map = {
      Events::Types::CONVERSATION_TYPING_ON => 'composing',
      Events::Types::CONVERSATION_RECORDING => 'recording',
      Events::Types::CONVERSATION_TYPING_OFF => 'paused'
    }

    response = HTTParty.post(
      "#{provider_url}/presence/chat#{instance_query}",
      headers: api_headers,
      body: { chat: jid_param(phone_number), state: presence_map[typing_status] }.to_json
    )

    raise ProviderUnavailableError, 'Failed to update presence' unless process_response(response)

    true
  end

  def update_presence(_status)
    Rails.logger.debug 'Account-level presence not used by whatsapp-api integration'
    true
  end

  def read_messages(messages, recipient_id: nil, phone_number: nil, **)
    @phone_number = recipient_id || phone_number

    response = HTTParty.post(
      "#{provider_url}/messages/mark-read#{instance_query}",
      headers: api_headers,
      body: {
        chat: jid_param(phone_number),
        message_ids: messages.map(&:source_id).compact
      }.to_json
    )

    raise ProviderUnavailableError, 'Failed to mark messages as read' unless process_response(response)

    true
  end

  def unread_message(_phone_number, _message)
    Rails.logger.debug 'Mark-unread not exposed by whatsapp-api'
    true
  end

  def received_messages(_phone_number, _messages)
    Rails.logger.debug 'Received receipts handled at protocol level'
    true
  end

  def get_profile_pic(jid)
    response = HTTParty.post(
      "#{provider_url}/contacts/profile-picture#{instance_query}",
      headers: api_headers,
      body: { jid: jid_param(jid), preview: false }.to_json
    )

    return nil unless process_response(response)

    body = unwrap(response.parsed_response)
    body['url']
  end

  def on_whatsapp(phone_number)
    @phone_number = phone_number

    # POST with array body — API can check multiple phones at once.
    response = HTTParty.post(
      "#{provider_url}/contacts/onwhatsapp#{instance_query}",
      headers: api_headers,
      body: { phones: [phone_number.to_s] }.to_json
    )

    raise ProviderUnavailableError, 'Failed to check WhatsApp registration' unless process_response(response)

    parsed = response.parsed_response
    parsed = safe_parse_json(parsed) if parsed.is_a?(String)
    # Response is an array of IsOnWhatsAppResponse — pick first.
    entry = parsed.is_a?(Array) ? parsed.first : unwrap(parsed)
    entry ||= {}
    {
      'jid' => entry['jid'],
      'exists' => entry['is_in'] || entry['exists'] || entry['is_registered'] || false,
      'lid' => entry['lid']
    }
  end

  # whatsapp-api supports phone-code pairing as an alternative to QR scan.
  # The customer enters an 8-character code into WhatsApp's "Link with phone
  # number" flow on their phone instead of scanning a QR. The instance must
  # be in `connected: true, pair_state: unpaired` state when called.
  # See OpenAPI: POST /instances/pair/phonecode
  def request_phone_pairing_code(phone_number)
    digits = phone_number.to_s.delete('+').gsub(/\D/, '')
    response = HTTParty.post(
      "#{provider_url}/instances/pair/phonecode#{instance_query}",
      headers: api_headers,
      body: { phone: digits }.to_json
    )

    raise ProviderUnavailableError, "Failed to request pairing code: #{response.code} #{response.body}" unless process_response(response)

    body = unwrap(response.parsed_response)
    {
      'code' => body['code'] || body['pairingCode'] || body['pairing_code'],
      'phone' => digits,
      'expires_in' => body['expires_in'] || body['timeout']
    }
  end

  private

  def provider_url
    whatsapp_channel.provider_config['provider_url'].presence || DEFAULT_URL
  end

  def api_key
    whatsapp_channel.provider_config['api_key'].presence || DEFAULT_API_KEY
  end

  def instance_id
    whatsapp_channel.provider_config['instance_id'].presence ||
      (whatsapp_channel.provider_config['instance_id'] = SecureRandom.uuid).tap { whatsapp_channel.save! }
  end

  def instance_query(prefix: '?')
    "#{prefix}instance_id=#{CGI.escape(instance_id)}"
  end

  def inbox_webhook_url
    # The URL we register with whatsapp-api must be reachable from THAT
    # container, not from the user's browser. In docker-compose dev where
    # FRONTEND_URL=https://localhost:3000 (browser-facing), the whatsapp-api
    # container can't reach back to its own localhost — set
    # WHATSAPP_WEBHOOK_BASE_URL=http://host.docker.internal:3000 (or the
    # Chatwoot container's network alias) to override.
    base_url = ENV['WHATSAPP_WEBHOOK_BASE_URL'].presence ||
               ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    "#{base_url}/webhooks/whatsapp/#{whatsapp_channel.phone_number}"
  end

  def normalized_phone_number
    whatsapp_channel.phone_number.to_s.delete('+')
  end

  def format_jid(phone_number)
    "#{phone_number.to_s.delete('+')}@s.whatsapp.net"
  end

  # JIDParam structured form { user, server } as the OpenAPI components expect.
  # Some endpoints accept the string variant in examples; the structured form
  # works everywhere and matches the schema strictly.
  def jid_param(phone_or_jid)
    digits = phone_or_jid.to_s.split('@').first.to_s.delete('+').gsub(/\D/, '')
    server = phone_or_jid.to_s.split('@')[1].presence || 's.whatsapp.net'
    { user: digits, server: server }
  end

  def register_webhook!
    # CreateWebhookRequest schema requires `scope` and `url`; for instance
    # scope, `instance_id` is also required in the BODY (the query-param
    # variant is informational only). Secret must be 16+ chars (HMAC-SHA256
    # signing key); the channel's webhook_verify_token is exactly 32 hex chars.
    # /webhooks POST takes no query params — scope + instance_id live in the body.
    response = HTTParty.post(
      "#{provider_url}/webhooks",
      headers: api_headers,
      body: {
        scope: 'instance',
        instance_id: instance_id,
        url: inbox_webhook_url,
        events: DEFAULT_WEBHOOK_EVENTS,
        enabled: true,
        active: true,
        secret: whatsapp_channel.provider_config['webhook_verify_token']
      }.to_json
    )

    return if process_response(response)

    # 409 Conflict — the same {scope, instance_id, url} webhook already
    # exists. setup_channel_provider is idempotent, so this is a success
    # for our purposes (re-running setup must not error).
    return if response.code == 409

    Rails.logger.error "Failed to register webhook on whatsapp-api: #{response.body}"
    raise ProviderUnavailableError, 'Failed to register webhook on whatsapp-api'
  end

  def send_text_message
    quoted_id = quoted_message_source_id

    response = HTTParty.post(
      "#{provider_url}/messages/send#{instance_query}",
      headers: api_headers,
      body: {
        to: { user: normalized_to_user, server: 's.whatsapp.net' },
        message: { conversation: @message.content },
        context_info: ({ stanza_id: quoted_id } if quoted_id)
      }.compact.to_json
    )

    raise ProviderUnavailableError, 'Failed to send text message' unless process_response(response)

    update_external_created_at(response)
    unwrap(response.parsed_response)['message_id']
  end

  def send_media_message
    attachment = @message.attachments.first
    media_type = case attachment.file_type
                 when 'image' then 'image'
                 when 'audio' then 'audio'
                 when 'video' then 'video'
                 when 'sticker' then 'sticker'
                 else 'document'
                 end

    media_item = {
      type: media_type,
      data: Base64.strict_encode64(attachment.file.download),
      mime_type: attachment.file.content_type,
      caption: @message.content.presence,
      file_name: attachment.file.filename.to_s
    }.compact

    response = HTTParty.post(
      "#{provider_url}/messages/send-media#{instance_query}",
      headers: api_headers,
      body: {
        to: { user: normalized_to_user, server: 's.whatsapp.net' },
        media: [media_item]
      }.to_json
    )

    raise ProviderUnavailableError, 'Failed to send media message' unless process_response(response)

    update_external_created_at(response)
    unwrap(response.parsed_response)['message_id']
  end

  def send_reaction_message
    reply_to = Message.find(@message.in_reply_to)
    chat = jid_param(@phone_number)

    response = HTTParty.post(
      "#{provider_url}/messages/react#{instance_query}",
      headers: api_headers,
      body: {
        chat: chat,
        # For 1:1 chats sender == chat. For groups, the per-message sender JID
        # would be needed — out of scope for the initial port (Chatwoot does
        # not currently model group sender JIDs in our reaction outgoing flow).
        sender: chat,
        message_id: reply_to.source_id,
        reaction: @message.content
      }.to_json
    )

    raise ProviderUnavailableError, 'Failed to send reaction' unless process_response(response)

    update_external_created_at(response)
    unwrap(response.parsed_response)['reaction_id'] || unwrap(response.parsed_response)['message_id']
  end

  def normalized_to_user
    @phone_number.to_s.delete('+')
  end

  def quoted_message_source_id
    return nil if @message.in_reply_to.blank?

    Message.find_by(id: @message.in_reply_to)&.source_id
  end

  def process_response(response)
    case response.code
    when 200..299
      true
    when 401
      Rails.logger.error "whatsapp-api authentication failed: #{response.body}"
      false
    when 404
      Rails.logger.error "whatsapp-api instance not found: #{response.body}"
      false
    else
      Rails.logger.error "whatsapp-api error: #{response.code} - #{response.body}"
      false
    end
  end

  def update_external_created_at(_response)
    @message.update!(external_created_at: Time.current)
  end

  # whatsapp-api wraps most successful responses as { success, data: {...}, timestamp }.
  # Fall back to the unwrapped body for legacy/edge cases.
  # Tolerates String input — whatsapp-api ships JSON with text/plain content-type
  # so HTTParty hands back the raw string.
  def unwrap(body)
    return {} if body.blank?

    parsed = body.is_a?(String) ? safe_parse_json(body) : body
    return parsed['data'] if parsed.is_a?(Hash) && parsed['data'].is_a?(Hash)

    parsed.is_a?(Hash) ? parsed : {}
  end

  def safe_parse_json(body)
    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

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

  def handle_channel_error
    whatsapp_channel.update_provider_connection!(connection: 'close')

    return if @handling_error

    @handling_error = true
    begin
      setup_channel_provider_without_error_handling
    rescue StandardError => e
      Rails.logger.error "Failed to reconnect whatsapp-api instance after error: #{e.message}"
    ensure
      @handling_error = false
    end
  end

  with_error_handling :setup_channel_provider,
                      :disconnect_channel_provider,
                      :send_message,
                      :toggle_typing_status,
                      :read_messages,
                      :on_whatsapp
end
