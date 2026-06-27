# frozen_string_literal: true

# Whatsapp::PropriacloudEmbeddedSignupService
# ------------------------------------------
# Orchestrates an inbox-creation flow that produces a WABA-mode WhatsApp
# channel and asks minha for a public Embedded Signup URL the admin can
# forward to the customer.
#
# Path is intentionally the SAME as the existing web/QR propriacloud setup:
#
#   1. Build a Channel::Whatsapp + Inbox in a transaction with
#      provider_config carrying connection_type='waba' and the marker
#      `source: 'propriacloud_embedded_signup'`. This is the same
#      Channel::Whatsapp model the manual setup uses — only the
#      connection_type flag is flipped.
#   2. Reuse `WhatsappPropriacloudService#setup_channel_provider_without_error_handling(fetch_qr: false)`
#      to call whatsapp-api `/instances/create` with `waba: true` (same call
#      QR-pair flows make, just the WABA flag — see line 184 of
#      `whatsapp_propriacloud_service.rb`).
#   3. POST to minha `/api/external/whatsapp/v1/signup-sessions` with the
#      same tenant.key — minha re-validates by calling whatsapp-api with that
#      key for the instance, then mints the public URL.
#   4. Persist the returned URL on the channel's `provider_connection` so
#      the inbox UI (and the SignupLinkPanel-style component) can display it.
#
# Completion detection is the existing whatsapp-api → chatwoot event flow:
# when the customer finishes the Meta popup the instance flips to paired,
# the existing `instance.*` / `pairing.*` events update provider_connection,
# inbox transitions to "connected" — same path QR pairing uses.
#
# Counterparts:
#   * app/controllers/api/v1/accounts/propriacloud/authorizations_controller.rb
#   * app/models/propriacloud_embedded_signup_session.rb
#   * app/services/whatsapp/providers/whatsapp_propriacloud_service.rb (setup_channel_provider)
#
# Created: 2026-05-20
class Whatsapp::PropriacloudEmbeddedSignupService
  class ProviderError < StandardError; end

  DEFAULT_MINHA_BASE_URL = 'https://minha.propria.cloud'
  DEFAULT_TTL_MINUTES = 60

  def self.start(account:, tenant_key:, intended_inbox_name:, phone_number: nil,
                 mark_as_read: true, ttl_minutes: DEFAULT_TTL_MINUTES,
                 prefill: {})
    new.start(
      account: account, tenant_key: tenant_key,
      intended_inbox_name: intended_inbox_name, phone_number: phone_number,
      mark_as_read: mark_as_read, ttl_minutes: ttl_minutes, prefill: prefill
    )
  end

  def start(account:, tenant_key:, intended_inbox_name:, phone_number: nil,
            mark_as_read: true, ttl_minutes: DEFAULT_TTL_MINUTES, prefill: {})
    validate!(account: account, tenant_key: tenant_key, intended_inbox_name: intended_inbox_name)

    instance_id = generate_instance_id(account)

    session = PropriacloudEmbeddedSignupSession.create!(
      account: account,
      instance_id: instance_id,
      intended_inbox_name: intended_inbox_name,
      phone_number: phone_number,
      mark_as_read: mark_as_read,
      status: 'pending'
    )

    # Steps 1–2: build the channel + inbox + provision the instance through
    # the SAME existing flow QR pairing uses. The connection_type='waba'
    # flag flips `setup_channel_provider` to create the instance with
    # `waba: true` on whatsapp-api.
    channel = build_channel_and_inbox(
      account: account,
      tenant_key: tenant_key,
      instance_id: instance_id,
      phone_number: phone_number,
      intended_inbox_name: intended_inbox_name,
      mark_as_read: mark_as_read
    )

    # Step 3: ask minha to mint the public signup URL for the instance.
    url_data = post_mint_url(
      tenant_key: tenant_key,
      instance_id: instance_id,
      ttl_minutes: ttl_minutes,
      caller_metadata: {
        chatwoot_account_id: account.id,
        chatwoot_session_id: session.id,
        chatwoot_inbox_id: channel.inbox.id,
        intended_inbox_name: intended_inbox_name,
        intended_phone_number: phone_number,
        mark_as_read: mark_as_read
      },
      prefill: prefill
    )

    # Step 4: persist the URL on the channel so the inbox UI can display it.
    persist_signup_url_on_channel!(channel: channel, url_data: url_data)

    session.update!(minha_session_id: url_data['session_id'], inbox_id: channel.inbox.id)

    [session, url_data['signup_url'], channel.inbox, url_data['expires_at']]
  end

  private

  def validate!(account:, tenant_key:, intended_inbox_name:)
    raise ArgumentError, 'account required' if account.blank?
    raise ArgumentError, 'tenant_key required' if tenant_key.blank?
    raise ArgumentError, 'tenant_key must be 64-hex' unless tenant_key.match?(/\A[0-9a-f]{64}\z/)
    raise ArgumentError, 'intended_inbox_name required' if intended_inbox_name.blank?
  end

  def generate_instance_id(account)
    "chatwoot-#{account.id}-#{SecureRandom.hex(4)}"
  end

  def minha_base_url
    ENV.fetch('PROPRIACLOUD_MINHA_BASE_URL', DEFAULT_MINHA_BASE_URL)
  end

  def whatsapp_api_base_url
    ENV.fetch('PROPRIACLOUD_API_URL', 'https://whatsapp.propria.cloud/api/v1')
  end

  # Build Channel::Whatsapp + Inbox in a transaction with the embedded-signup
  # marker, then run the existing provider-service setup which calls
  # whatsapp-api `/instances/create` with `waba: true`. Returns the channel
  # (with `.inbox` populated).
  def build_channel_and_inbox(account:, tenant_key:, instance_id:, phone_number:,
                              intended_inbox_name:, mark_as_read:)
    provider_config = {
      'provider_url' => whatsapp_api_base_url,
      'api_key' => tenant_key,
      'instance_id' => instance_id,
      'connection_type' => 'waba',
      'source' => 'propriacloud_embedded_signup',
      'mark_as_read' => mark_as_read
    }

    channel = ActiveRecord::Base.transaction do
      ch = Channel::Whatsapp.create!(
        account: account,
        phone_number: phone_number.to_s,
        provider: 'propriacloud',
        provider_config: provider_config
      )
      account.inboxes.create!(name: intended_inbox_name, channel: ch)
      ch
    end

    # Same setup the inboxes_controller's eagerly_provision_upstream! calls
    # for any propriacloud channel — hits whatsapp-api /instances/create
    # with `waba: true` (because connection_type='waba'). fetch_qr is false
    # because we won't have a QR for WABA mode.
    channel.provider_service.setup_channel_provider_without_error_handling(fetch_qr: false)

    channel
  rescue Whatsapp::Providers::WhatsappPropriacloudService::ProviderUnavailableError => e
    Rails.logger.error "[PROPRIACLOUD EMBEDDED SIGNUP] provider unavailable during channel setup: #{e.message}"
    raise ProviderError, "whatsapp-api unavailable: #{e.message}"
  end

  def post_mint_url(tenant_key:, instance_id:, ttl_minutes:, caller_metadata:, prefill:)
    uri = URI.join("#{minha_base_url}/", 'api/external/whatsapp/v1/signup-sessions')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type'] = 'application/json'
    req['X-API-Key'] = tenant_key
    req.body = {
      instance_id: instance_id,
      ttl_minutes: ttl_minutes,
      caller_metadata: caller_metadata,
      prefill: prefill.presence
    }.compact.to_json

    res = http.request(req)
    if res.code.to_i >= 300
      raise ProviderError, "minha /signup-sessions returned #{res.code}: #{res.body.to_s.byteslice(0, 500)}"
    end

    JSON.parse(res.body)
  end

  def persist_signup_url_on_channel!(channel:, url_data:)
    merged = (channel.provider_connection || {}).deep_dup
    merged['signup_url']        = url_data['signup_url']
    merged['signup_session_id'] = url_data['session_id']
    merged['signup_expires_at'] = url_data['expires_at']
    channel.update_provider_connection!(merged)
  end
end
