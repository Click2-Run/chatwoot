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

  # Resolution order (highest priority first):
  #   1. per-channel `provider_config['provider_url' / 'api_key']` overrides
  #   2. InstallationConfig (DB) — Super Admin → Própria Cloud form
  #   3. Legacy env-var aliases (WHATSAPP_API_*, PROPRIACLOUD_PROVIDER_DEFAULT_*,
  #      CLICK2RUN_PROVIDER_DEFAULT_*)
  #
  # When the canonical DB row is blank but an alias env var is set, the
  # alias value is migrated into the canonical InstallationConfig row on
  # first read. From that point on the Super Admin form shows the value
  # and saving via the UI takes precedence — DB always wins on the next
  # request because it's checked first.
  def self.default_url
    resolve_with_env_aliases(
      'PROPRIACLOUD_API_URL',
      %w[WHATSAPP_API_URL PROPRIACLOUD_PROVIDER_DEFAULT_URL CLICK2RUN_PROVIDER_DEFAULT_URL]
    )
  end

  def self.default_api_key
    resolve_with_env_aliases(
      'PROPRIACLOUD_API_KEY',
      %w[WHATSAPP_API_KEY PROPRIACLOUD_PROVIDER_DEFAULT_API_KEY CLICK2RUN_PROVIDER_DEFAULT_API_KEY]
    )
  end

  def self.default_webhook_base_url
    resolve_with_env_aliases(
      'PROPRIACLOUD_WEBHOOK_BASE_URL',
      %w[WHATSAPP_WEBHOOK_BASE_URL FRONTEND_URL]
    ) || 'http://localhost:3000'
  end

  # Resolve `canonical_key` from DB first; if blank, walk env aliases and
  # migrate the first hit into the canonical InstallationConfig row so
  # subsequent reads (and the Super Admin form) reflect the same value.
  def self.resolve_with_env_aliases(canonical_key, env_aliases)
    db_value = GlobalConfigService.load(canonical_key, nil)
    return db_value if db_value.present?

    env_value = env_aliases.lazy.map { |k| ENV[k] }.find { |v| v.present? }
    return nil if env_value.blank?

    # first_or_create! is race-safe; subsequent callers race onto the same row.
    config = InstallationConfig.where(name: canonical_key).first_or_create!(value: env_value, locked: false)
    config.update!(value: env_value) if config.value.blank?
    GlobalConfig.clear_cache
    config.value
  end

  # Curated subscription. whatsapp-api offers ~105 event types; we only
  # subscribe to the ones Chatwoot actually dispatches a handler for so
  # Sidekiq doesn't burn cycles enqueueing privacy/newsletter/call/system
  # events we'll immediately drop. Wildcards are supported by the API
  # (`message.*`, `instance.recovery.*`, etc.).
  DEFAULT_WEBHOOK_EVENTS = %w[
    connection.connected
    connection.disconnected
    connection.logged_out
    connection.stream_replaced
    connection.connect_failure
    connection.client_outdated
    connection.temporary_ban
    connection.stream_error
    connection.keepalive_timeout
    connection.keepalive_restored
    pairing.qrcode
    pairing.phonecode
    pairing.success
    pairing.error
    pairing.qrcode_scanned_without_multidevice
    message.received
    message.sent
    message.sent_failed
    message.fb_received
    message.receipt
    message.reaction
    message.undecryptable
    message.media_retry
    message.media_retry_error
    message.error
    message.status
    user.push_name_changed
    user.picture_changed
    user.business_name_changed
    appstate.mark_chat_as_read
    appstate.archive
    appstate.delete_chat
    appstate.label_association_chat
    appstate.label_association_message
    appstate.label_edit
    history.sync_started
    history.sync_completed
    history.sync_conversation
    history.sync_messages
    history.sync_contacts
    instance.recovery.detected
    instance.recovery.started
    instance.recovery.retry
    instance.recovery.success
    instance.recovery.exhausted
    instance.recovery.aborted
  ].freeze

  def self.status
    url = default_url
    key = default_api_key
    if url.blank? || key.blank?
      raise ProviderUnavailableError,
            'Missing PROPRIACLOUD_API_URL / PROPRIACLOUD_API_KEY ' \
            '(configure via Super Admin → Própria Cloud, or set the legacy WHATSAPP_API_* env vars).'
    end

    response = HTTParty.get("#{url}/health", headers: { 'X-API-Key' => key })

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
  #
  # `fetch_qr:` controls whether the final step pulls a QR via
  # /instances/pair/qrcode. Pulling a QR counts as a pairing attempt on
  # the WhatsApp side and contributes to the same rate-limit budget that
  # /instances/pair/phonecode uses. The phone-code flow MUST pass
  # fetch_qr: false so the user's explicit Emparelhar click is the only
  # pairing attempt registered. Default true keeps the legacy QR
  # "Connect" path unchanged.
  def setup_channel_provider(fetch_qr: true)
    # custom_id is the Chatwoot account (organization) id, set server-side
    # from the channel's inbox association. The client never has a chance to
    # influence this — setup_channel_provider only reads it off the
    # persisted record. Same value is sent regardless of the entry point
    # (UI inbox creation, future API onboarding, agent invite, etc.).
    create_body = {
      instance_id: instance_id,
      name: whatsapp_channel.inbox.name,
      phone: normalized_phone_number,
      custom_id: whatsapp_channel.inbox.account_id.to_s
    }.compact.to_json

    # whatsapp-api occasionally returns 500 on /instances/create when an
    # earlier partial insert is racing with the new request — retrying
    # 500ms later returns 409 ("already exists") which we already treat
    # as success. Single retry is enough; persistent 500 is a real
    # outage and should still bubble up.
    create_response = HTTParty.post("#{provider_url}/instances/create", headers: api_headers, body: create_body)
    if create_response.code == 500
      Rails.logger.warn "Propriacloud /instances/create transient 500, retrying in 500ms: #{create_response.body[0..200]}"
      sleep 0.5
      create_response = HTTParty.post("#{provider_url}/instances/create", headers: api_headers, body: create_body)
    end

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

    # whatsapp-api emits pairing.qrcode webhook events only on actual state
    # transitions. For instances that come back already in connected+unpaired
    # state, the API answers /instances/connect with `message: "already
    # connected"` and never re-emits a pairing.qrcode. The Chatwoot UI then
    # has no QR to show. Pull the current QR explicitly so the user sees it
    # immediately. If the instance is already paired, this returns nothing
    # and the channel stays in whatever state the webhook last set.
    fetch_and_publish_qr_code if fetch_qr

    true
  end

  # Pull the current pairing QR from whatsapp-api and stuff it into the
  # channel's provider_connection so the inbox UI displays it. No-op if the
  # API doesn't return a QR (instance is paired or in an error state).
  def fetch_and_publish_qr_code
    response = HTTParty.get(
      "#{provider_url}/instances/pair/qrcode#{instance_query}",
      headers: api_headers
    )
    return unless response.success?

    body = unwrap(response.parsed_response)
    qr = body['img'] || body['code'] || body['qr_code']
    return if qr.blank?

    qr_data_url = qr.start_with?('data:image/') ? qr : "data:image/png;base64,#{qr}"
    whatsapp_channel.update_provider_connection!(
      connection: 'connecting',
      qr_data_url: qr_data_url,
      error: nil
    )
  rescue StandardError => e
    Rails.logger.warn "Propriacloud: could not fetch QR (#{e.class}: #{e.message[0..120]})"
  end

  # Full teardown — disconnect AND delete the instance. Used by the
  # Channel::Whatsapp before_destroy hook when the inbox itself is being
  # removed from Chatwoot. NEVER call from a UI button — it permanently
  # removes the instance record on the api side.
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

  # POST /instances/disconnect — bring the websocket down but KEEP the
  # device pair on the api side. Re-Conectar later just brings the
  # connection back up; no re-emparelhamento required. Idempotent: a
  # second call when already disconnected is logged but does not raise.
  def disconnect_only
    response = HTTParty.post("#{provider_url}/instances/disconnect#{instance_query}",
                             headers: api_headers)
    Rails.logger.warn "disconnect_only: api returned #{response.code}" unless process_response(response)
    true
  end

  # POST /instances/unpair — remove the device link with WhatsApp but
  # KEEP the instance record on the api side. After this the instance
  # is connected+unpaired (or disconnected+unpaired depending on api
  # behaviour) and the user must pair again via QR or phone code.
  def unpair_only
    response = HTTParty.post("#{provider_url}/instances/unpair#{instance_query}",
                             headers: api_headers)
    raise ProviderUnavailableError, "Failed to unpair instance: #{response.code} #{response.body[0..200]}" unless process_response(response)

    config = whatsapp_channel.provider_config || {}
    if config['paired_at'].present?
      config.delete('paired_at')
      whatsapp_channel.update!(provider_config: config)
    end
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

  # Called as an ActiveModel validator on every Channel::Whatsapp save.
  # Must NOT fail just because the upstream API is briefly unreachable —
  # otherwise routine UI toggles (read receipts, presence, group sync,
  # etc.) start returning 422 Invalid Credentials whenever there's any
  # network blip between Chatwoot and whatsapp-api. Initial setup time
  # already validates credentials via setup_channel_provider; on
  # routine saves we treat the config as valid as long as URL + API
  # key are present.
  def validate_provider_config?
    return false if provider_url.blank? || api_key.blank?

    true
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

  # Chatwoot's Channel::Whatsapp routes message-edit / message-delete
  # actions to the provider service when it `respond_to?` the method.
  # WhatsApp imposes a 20-minute edit window per message; we let the API
  # surface the error so it bubbles up to the agent UI.

  def edit_message(recipient_id, message, new_content)
    response = HTTParty.put(
      "#{provider_url}/messages/edit#{instance_query}",
      headers: api_headers,
      body: {
        chat: jid_param(recipient_id),
        message_id: message.source_id,
        new_content: { conversation: new_content.to_s }
      }.to_json
    )

    raise ProviderUnavailableError, 'Failed to edit message' unless process_response(response)

    true
  end

  def delete_message(recipient_id, message)
    response = HTTParty.delete(
      "#{provider_url}/messages/revoke#{instance_query}",
      headers: api_headers,
      body: {
        chat: jid_param(recipient_id),
        message_id: message.source_id
      }.to_json
    )

    raise ProviderUnavailableError, 'Failed to delete message' unless process_response(response)

    true
  end

  # ---------- one-shot history pulls (used by HistoryBackfillJob) ----------
  # Each helper returns the parsed array of records or [] on failure. They
  # are paginated via page/page_size (1-based). The caller keeps incrementing
  # page until an empty page comes back.

  def sync_contacts(page: 1, page_size: 200)
    paged_get('/sync/contacts', page: page, page_size: page_size)
  end

  def sync_conversations(page: 1, page_size: 200)
    paged_get('/sync/conversations', page: page, page_size: page_size)
  end

  def sync_messages(chat_jid, page: 1, page_size: 200)
    paged_get('/sync/messages', extra: { chat_jid: chat_jid }, page: page, page_size: page_size)
  end

  def sync_push_names(page: 1, page_size: 500)
    paged_get('/sync/push-names', page: page, page_size: page_size)
  end

  def list_labels(page: 1, page_size: 100)
    paged_get('/labels', page: page, page_size: page_size, scope: :tenant)
  end

  # Self-healing post-pair convergence. Called on inbox-visit (via the
  # refresh_provider_status controller action) so a paired channel
  # always settles into the same end state regardless of which side
  # was offline when the pairing happened:
  #
  #   1. Pull truth from /instances/status — refreshes connection,
  #      pair_state, paired_at.
  #   2. Re-register the webhook with the curated DEFAULT_WEBHOOK_EVENTS
  #      list. register_webhook! is idempotent (409 → PATCH events).
  #   3. If paired but history_backfill_completed_at is blank,
  #      enqueue HistoryBackfillJob — itself idempotent (skips when
  #      completed_at is present).
  #
  # Effect: a freshly-paired session that landed during a Chatwoot
  # outage / HMR restart still ends up with webhook registered + full
  # history pulled the moment the user opens the inbox again.
  def reconcile!
    refresh_status_from_api!

    begin
      register_webhook!
    rescue StandardError => e
      Rails.logger.warn "Propriacloud reconcile webhook step skipped: #{e.class}: #{e.message[0..120]})"
    end

    paired = whatsapp_channel.provider_config['paired_at'].present?
    backfilled = whatsapp_channel.provider_config['history_backfill_completed_at'].present?
    Whatsapp::Propriacloud::HistoryBackfillJob.perform_later(whatsapp_channel.id) if paired && !backfilled

    {
      connection: whatsapp_channel.provider_connection['connection'],
      paired_at: whatsapp_channel.provider_config['paired_at'],
      history_backfill_completed_at: whatsapp_channel.provider_config['history_backfill_completed_at']
    }
  end

  # Hit /instances/status and reconcile our cached provider_connection
  # with what the API actually reports. Used on user-driven inbox
  # opens so a stale `connecting` (left over from an abandoned pairing
  # attempt) doesn't get stuck. Rate-limited externally by the
  # controller — this method just does the work.
  #
  # API state matrix (per OpenAPI /instances/status doc):
  #   connection_state | pair_state | meaning
  #   ---------------- | ---------- | -----------------------------------
  #   connected        | paired     | open
  #   connected        | pairing    | connecting (QR/phone code phase)
  #   connected        | unpaired   | close (ready to pair)
  #   connecting       | any        | connecting
  #   disconnected     | paired     | close (eligible for reconnect)
  #   disconnected     | unpaired   | close
  #   disconnecting    | any        | close
  def refresh_status_from_api!
    response = HTTParty.get(
      "#{provider_url}/instances/status#{instance_query}",
      headers: api_headers
    )
    return unless response.success?

    payload = unwrap(response.parsed_response)
    status = (payload['data'] && payload['data']['status']) || payload['status']
    return if status.blank?

    chat_state = map_api_status_to_chatwoot(
      status['connection_state'],
      status['pair_state']
    )

    new_conn = whatsapp_channel.provider_connection.deep_dup || {}
    if chat_state != 'connecting'
      new_conn['qr_data_url'] = nil
      new_conn['error'] = nil if chat_state == 'open'
    end
    new_conn['connection'] = chat_state
    # Surface the raw two-axis state from the API so the dashboard can
    # render the full propriacloud.git status taxonomy (paired+disconnected
    # → just needs reconnect, unpaired+connected → needs Emparelhar, etc.)
    new_conn['connection_state'] = status['connection_state']
    new_conn['pair_state'] = status['pair_state']
    new_conn['is_paired'] = status['is_paired']
    new_conn['is_connected'] = status['is_connected']
    whatsapp_channel.update_provider_connection!(new_conn)

    # Sync paired_at with API truth for the auto-recovery gate.
    config = whatsapp_channel.provider_config || {}
    if status['pair_state'] == 'paired' && config['paired_at'].blank?
      config['paired_at'] = Time.current.iso8601
      whatsapp_channel.update!(provider_config: config)
    elsif status['pair_state'] == 'unpaired' && config['paired_at'].present?
      config.delete('paired_at')
      whatsapp_channel.update!(provider_config: config)
    end

    { connection: chat_state, pair_state: status['pair_state'], connection_state: status['connection_state'] }
  rescue StandardError => e
    Rails.logger.warn "Propriacloud: refresh_status_from_api! failed (#{e.class}: #{e.message[0..120]})"
    nil
  end

  def map_api_status_to_chatwoot(connection_state, pair_state)
    return 'open' if connection_state == 'connected' && pair_state == 'paired'
    return 'connecting' if connection_state == 'connected' && pair_state == 'pairing'
    return 'connecting' if connection_state == 'connecting'

    'close'
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
  class PairRateLimitedError < StandardError
    attr_reader :code, :cooldown_seconds, :locked_until

    def initialize(code:, message:, cooldown_seconds:, locked_until: nil)
      super(message)
      @code = code
      @cooldown_seconds = cooldown_seconds
      @locked_until = locked_until
    end
  end

  def request_phone_pairing_code(phone_number)
    digits = phone_number.to_s.delete('+').gsub(/\D/, '')
    response = HTTParty.post(
      "#{provider_url}/instances/pair/phonecode#{instance_query}",
      headers: api_headers,
      body: { phone: digits }.to_json
    )

    if process_response(response)
      body = unwrap(response.parsed_response)
      return {
        'code' => body['code'] || body['pairingCode'] || body['pairing_code'],
        'phone' => digits,
        'expires_in' => body['expires_in'] || body['timeout']
      }
    end

    parsed_error = extract_pair_error(response)
    if parsed_error[:rate_limited]
      until_at = Time.current + parsed_error[:cooldown_seconds].to_i
      stamp_pair_lock!(parsed_error[:cooldown_seconds].to_i, parsed_error[:code])
      raise PairRateLimitedError.new(
        code: parsed_error[:code],
        message: parsed_error[:user_message],
        cooldown_seconds: parsed_error[:cooldown_seconds].to_i,
        locked_until: until_at.iso8601
      )
    end

    raise ProviderUnavailableError, parsed_error[:user_message] || "Failed to request pairing code: #{response.code}"
  end

  # Parse the structured error body whatsapp-api returns on 4xx/5xx
  # pairing failures and surface the bits useful to the dashboard:
  #   { rate_limited:, code:, user_message:, cooldown_seconds: }
  def extract_pair_error(response)
    parsed = response.parsed_response
    parsed = JSON.parse(parsed) rescue nil if parsed.is_a?(String) # rubocop:disable Style/RescueModifier
    err = (parsed.is_a?(Hash) && parsed['error']) || {}
    code = err['code'].to_s
    cooldown = err.dig('details', 'recommended_cooldown_seconds')
    rate_limited = code == 'PAIR_RATE_LIMITED' ||
                   response.code.to_i == 429 ||
                   err['message'].to_s.match?(/rate-?overlimit/i)
    user_message = if rate_limited
                     'WhatsApp temporarily blocked new pair attempts on this number. ' \
                       'Please wait the cooldown out before trying again.'
                   elsif code == 'PAIR_DEVICE_LIMIT'
                     'WhatsApp limit of linked devices reached. Open the app, remove an old linked device, and retry.'
                   else
                     'Could not request a pairing code. Please try again in a moment.'
                   end
    { rate_limited: rate_limited, code: code.presence || 'PAIR_FAILED',
      user_message: user_message, cooldown_seconds: cooldown }
  end

  # Persist when the channel is allowed to retry a pair so the
  # dashboard can disable the Emparelhar button and the controller
  # can short-circuit further requests instead of round-tripping to
  # WhatsApp just to re-collect the same 429.
  def stamp_pair_lock!(cooldown_seconds, code)
    return if cooldown_seconds.to_i <= 0

    config = whatsapp_channel.provider_config || {}
    config['pair_locked_until'] = (Time.current + cooldown_seconds.to_i).iso8601
    config['pair_lock_code'] = code
    whatsapp_channel.update!(provider_config: config)
  end

  private

  def provider_url
    whatsapp_channel.provider_config['provider_url'].presence || self.class.default_url
  end

  def api_key
    whatsapp_channel.provider_config['api_key'].presence || self.class.default_api_key
  end

  # Paginated GET for /sync/* and /labels endpoints. Returns an Array
  # of records (already symbolized). On non-2xx responses it logs and
  # returns [] so the backfill job can proceed without raising.
  # whatsapp-api response shapes for list endpoints, in observed order
  # of nesting:
  #   { success: true, data: { contacts: [...], pagination: {...} } }
  #   { success: true, data: { conversations: [...], pagination: {...} } }
  #   { success: true, data: { messages: [...], pagination: {...} } }
  #   { success: true, data: { labels: [...] } }
  # Some plain endpoints also return:
  #   { data: [...] } or [...]
  # paged_get walks through every plausible shape and returns the
  # array of records (deep-symbolized) or [] when nothing applies.
  RESOURCE_KEYS = %w[contacts conversations messages labels push_names call_logs items results data].freeze

  def paged_get(path, page: 1, page_size: 200, extra: {}, scope: :instance)
    qs = { page: page, page_size: page_size }
    qs.merge!(extra)
    qs[:instance_id] = instance_id if scope == :instance
    response = HTTParty.get(
      "#{provider_url}#{path}?#{qs.to_query}",
      headers: api_headers
    )
    return [] unless response.success?

    rows = extract_paged_rows(response.parsed_response)
    rows.map { |r| r.respond_to?(:deep_symbolize_keys) ? r.deep_symbolize_keys : r }
  rescue StandardError => e
    Rails.logger.warn "Propriacloud paged_get(#{path}) failed: #{e.class}: #{e.message[0..120]}"
    []
  end

  def extract_paged_rows(parsed)
    parsed = safe_parse_json(parsed) if parsed.is_a?(String)
    return parsed if parsed.is_a?(Array)
    return [] unless parsed.is_a?(Hash)

    # Top-level convenience keys.
    RESOURCE_KEYS.each do |k|
      v = parsed[k]
      return v if v.is_a?(Array)
    end

    inner = parsed['data']
    return inner if inner.is_a?(Array)
    return [] unless inner.is_a?(Hash)

    # data.<resource>[]
    RESOURCE_KEYS.each do |k|
      v = inner[k]
      return v if v.is_a?(Array)
    end

    []
  end

  # Use the local Chatwoot channel id as the propriacloud instance_id for
  # new inboxes — it's already a stable, unique handle that ties the two
  # systems together with no extra mapping. Existing rows that were
  # already paired with a UUID (e.g. dev instances created before this
  # change) keep their value so we don't orphan their server-side state.
  def instance_id
    return whatsapp_channel.provider_config['instance_id'] if whatsapp_channel.provider_config['instance_id'].present?

    whatsapp_channel.provider_config['instance_id'] = whatsapp_channel.id.to_s
    whatsapp_channel.save!
    whatsapp_channel.provider_config['instance_id']
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
    "#{self.class.default_webhook_base_url}/webhooks/whatsapp/#{whatsapp_channel.phone_number}"
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

    if process_response(response) || response.code == 409
      # ALWAYS run the dedupe sweep — even on a successful POST. The
      # webhook record is keyed on (scope, instance_id, url), so a URL
      # change (e.g. swapping a cross-stack container name for
      # host.docker.internal) creates a NEW row instead of replacing
      # the old one. sync_webhook_subscription! patches the canonical
      # entry to the desired (url, events) and deletes any orphans
      # left over from previous configurations.
      sync_webhook_subscription!
      return
    end

    Rails.logger.error "Failed to register webhook on whatsapp-api: #{response.body}"
    raise ProviderUnavailableError, 'Failed to register webhook on whatsapp-api'
  end

  # Find the existing instance-scoped webhook (matched by url) and PATCH
  # its event filter to DEFAULT_WEBHOOK_EVENTS. Best-effort — a sync
  # failure must not break setup_channel_provider; the next setup run
  # retries.
  # Reconcile the upstream webhook record with our current desired
  # state: the canonical Chatwoot URL (which can change when the host
  # mapping is changed, e.g. host.docker.internal:3003 vs the legacy
  # cross-stack container name) and the curated event subscription.
  # Strategy:
  #   1. List all instance-scoped webhooks for this instance_id.
  #   2. If one already matches the current URL, just PATCH events.
  #   3. Otherwise, PATCH the first stale entry with both url+events
  #      (single-instance webhooks are 1:1 in our model).
  #   4. Delete any leftover orphans pointing at obsolete URLs so the
  #      provider doesn't fan-out duplicate webhook deliveries.
  def sync_webhook_subscription!
    list = HTTParty.get("#{provider_url}/webhooks?scope=instance&instance_id=#{CGI.escape(instance_id)}",
                        headers: api_headers)
    return unless list.success?

    items = extract_webhook_list(list.parsed_response).select do |w|
      iid = w['instance_id'] || w[:instance_id] || w.dig('scope_target', 'instance_id')
      iid.to_s == instance_id.to_s
    end
    desired_url = inbox_webhook_url
    primary = items.find { |w| (w['url'] || w[:url]) == desired_url } ||
              items.find { |w| (w['url'] || w[:url]).to_s.include?('/webhooks/whatsapp/') } ||
              items.first
    return unless primary

    primary_id = primary['id'] || primary[:id]
    HTTParty.patch(
      "#{provider_url}/webhooks/#{primary_id}",
      headers: api_headers,
      body: { url: desired_url, events: DEFAULT_WEBHOOK_EVENTS, enabled: true, active: true }.to_json
    )

    items.each do |w|
      id = w['id'] || w[:id]
      next if id == primary_id

      HTTParty.delete("#{provider_url}/webhooks/#{id}", headers: api_headers)
    end
  rescue StandardError => e
    Rails.logger.warn "Propriacloud: webhook subscription sync skipped (#{e.class}: #{e.message[0..120]})"
  end

  # whatsapp-api wraps list responses as
  # {"success": true, "data": {"webhooks": [...], "count": N, ...}}
  # Walk every plausible nesting so we are tolerant to payload shape drift.
  def extract_webhook_list(parsed)
    parsed = safe_parse_json(parsed) if parsed.is_a?(String)
    return parsed if parsed.is_a?(Array)
    return [] unless parsed.is_a?(Hash)

    parsed['webhooks'] ||
      parsed.dig('data', 'webhooks') ||
      parsed['data'] ||
      []
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

    # PTT (push-to-talk = voice note) is the default UX for audio
    # captured from Chatwoot's mic recorder, which produces audio/ogg
    # (opus). File-style audio uploads (mp3/m4a/wav) ship as a regular
    # audio attachment so the recipient sees a player, not a voice note.
    is_voice_note = media_type == 'audio' &&
                    attachment.file.content_type.to_s.match?(%r{^audio/(ogg|opus|webm)})

    media_item = {
      type: media_type,
      data: Base64.strict_encode64(attachment.file.download),
      mime_type: attachment.file.content_type,
      caption: @message.content.presence,
      file_name: attachment.file.filename.to_s,
      ptt: is_voice_note ? true : nil
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
