# frozen_string_literal: true

# Whatsapp Incoming Message Service for Propriacloud Provider
#
# Processes webhook events from Propriacloud service
# Events: connection.update, messages.upsert, messages.update
#
# Webhook payload format:
# {
#   event: "connection.update" | "messages.upsert" | "messages.update",
#   instance_id: "1234567890",
#   phone_number: "+1234567890",
#   timestamp: 1699123456,
#   webhook_verify_token: "token_from_channel_config",
#   data: {...}
# }

class Whatsapp::IncomingMessagePropriacloudService < Whatsapp::IncomingMessageBaseService
  include Events::Types
  include Whatsapp::PropriacloudHandlers::ConnectionUpdate
  include Whatsapp::PropriacloudHandlers::MessagesUpsert
  include Whatsapp::PropriacloudHandlers::GroupMessage
  include Whatsapp::PropriacloudHandlers::MessagesUpdate
  include Whatsapp::PropriacloudHandlers::MessagesFailure
  include Whatsapp::PropriacloudHandlers::UserChanged
  include Whatsapp::PropriacloudHandlers::Appstate
  include Whatsapp::PropriacloudHandlers::HistorySync
  include Whatsapp::PropriacloudHandlers::InstanceRecovery
  include Whatsapp::PropriacloudHandlers::GroupUpdate

  class InvalidWebhookVerifyToken < StandardError; end
  class InvalidWebhookCustomId < StandardError; end

  def perform # rubocop:disable Metrics/AbcSize
    Rails.logger.tagged('propriacloud', "inbox=#{inbox.id}", "event=#{event_name || '?'}") do
      validate_webhook_token!
      validate_custom_id!
      return if event_name.blank? || processed_params[:data].blank?

      # Dispatch provider event for tracking/analytics
      Rails.configuration.dispatcher.dispatch(
        PROVIDER_EVENT_RECEIVED,
        Time.zone.now,
        inbox: inbox,
        event: event_name,
        payload: processed_params[:data]
      )

      # Process event based on type
      process_event
    end
  end

  # whatsapp-api delivers webhook events with `event_type` (e.g.
  # "connection.connected", "message.received"). Legacy delivery
  # backends used a plain `event` field. Accept both.
  def event_name
    processed_params[:event_type] ||
      processed_params['event_type'] ||
      processed_params[:event] ||
      processed_params['event']
  end

  private

  # Defense-in-depth on top of HMAC: every whatsapp-api event carries the
  # instance's `custom_id` (set on /instances/create — we set it to the
  # Chatwoot account_id). If the inbox's account_id and the event's
  # custom_id disagree, the payload is for a different tenant and must
  # be rejected even if the HMAC check passed (e.g. a leaked secret could
  # not be combined with cross-account routing).
  #
  # We tolerate a missing custom_id only for events emitted before the
  # instance was created in our flow (legacy data) — new instances always
  # have it because setup_channel_provider sets it explicitly.
  def validate_custom_id!
    incoming = processed_params[:custom_id] || processed_params['custom_id']
    incoming ||= processed_params.dig(:instance, :custom_id) ||
                 processed_params.dig('instance', 'custom_id')
    return if incoming.blank?

    expected = inbox.account_id.to_s
    raise InvalidWebhookCustomId unless ActiveSupport::SecurityUtils.secure_compare(incoming.to_s, expected)
  end

  def validate_webhook_token!
    expected_token = inbox.channel.provider_config['webhook_verify_token']
    raise InvalidWebhookVerifyToken if expected_token.blank?

    # whatsapp-api signs each delivery with HMAC-SHA256 in `X-Webhook-Signature`
    # (format: "sha256=<hex-digest>") computed over the raw request body, using
    # the secret we registered via POST /webhooks. Prefer that path when present.
    signature = processed_params[:_webhook_signature] || processed_params['_webhook_signature']
    raw_body = processed_params[:_webhook_raw_body] || processed_params['_webhook_raw_body']

    if signature.present? && raw_body.present?
      expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', expected_token, raw_body)}"
      raise InvalidWebhookVerifyToken unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)

      return
    end

    # Backwards-compat: legacy delivery backends echoed the secret in the body.
    webhook_token = processed_params[:webhook_verify_token] ||
                    processed_params['webhook_verify_token'] ||
                    processed_params[:webhookVerifyToken]

    raise InvalidWebhookVerifyToken if webhook_token != expected_token
  end

  # Map whatsapp-api's canonical event_type values to our handler methods.
  # Multiple events can route to the same handler — `connection.connected`,
  # `connection.disconnected`, and `pairing.*` all surface to the user as
  # connection-state changes via process_connection_update.
  EVENT_HANDLER_MAP = {
    # Connection lifecycle
    'connection.connected' => :process_connection_update,
    'connection.disconnected' => :process_connection_update,
    'connection.logged_out' => :process_connection_update,
    'connection.stream_replaced' => :process_connection_update,
    'connection.connect_failure' => :process_connection_update,
    'connection.client_outdated' => :process_connection_update,
    'connection.temporary_ban' => :process_connection_update,
    'connection.stream_error' => :process_connection_update,
    'connection.keepalive_timeout' => :process_connection_update,
    'connection.keepalive_restored' => :process_connection_update,
    # Pairing
    'pairing.qrcode' => :process_connection_update,
    'pairing.phonecode' => :process_connection_update,
    'pairing.success' => :process_connection_update,
    'pairing.error' => :process_connection_update,
    'pairing.qrcode_scanned_without_multidevice' => :process_connection_update,
    # Messaging — both inbound and outbound use the upsert handler since the
    # WhatsApp record shape is identical.
    'message.received' => :process_messages_upsert,
    'message.sent' => :process_messages_upsert,
    'message.fb_received' => :process_messages_upsert,
    'message.reaction' => :process_messages_upsert,
    # Receipts (delivery / read)
    'message.receipt' => :process_messages_update,
    'message.status' => :process_messages_update,
    # Failure / decrypt / media-retry surfacing
    'message.sent_failed' => :process_messages_failure,
    'message.error' => :process_messages_failure,
    'message.undecryptable' => :process_messages_failure,
    'message.media_retry' => :process_messages_failure,
    'message.media_retry_error' => :process_messages_failure,
    # Contact metadata
    'user.push_name_changed' => :process_user_changed,
    'user.business_name_changed' => :process_user_changed,
    'user.picture_changed' => :process_user_changed,
    # Group metadata/membership. whatsapp-api emits only these two group
    # events (no per-participant events), so both trigger a /groups/info
    # reconcile of an already-surfaced group conversation.
    'group.joined' => :process_group_update,
    'group.info_changed' => :process_group_update,
    # AppState (read/archive/delete). Labels are intentionally NOT
    # mapped — Chatwoot labels and WhatsApp labels are unrelated
    # taxonomies and bridging them was wrong.
    'appstate.mark_chat_as_read' => :process_appstate,
    'appstate.archive' => :process_appstate,
    'appstate.delete_chat' => :process_appstate,
    # History sync lifecycle
    'history.sync_started' => :process_history_sync,
    'history.sync_completed' => :process_history_sync,
    'history.sync_conversation' => :process_history_sync,
    'history.sync_messages' => :process_history_sync,
    'history.sync_contacts' => :process_history_sync,
    # Instance auto-recovery
    'instance.recovery.detected' => :process_instance_recovery,
    'instance.recovery.started' => :process_instance_recovery,
    'instance.recovery.retry' => :process_instance_recovery,
    'instance.recovery.success' => :process_instance_recovery,
    'instance.recovery.exhausted' => :process_instance_recovery,
    'instance.recovery.aborted' => :process_instance_recovery,
    # Legacy / baileys-style aliases (back-compat)
    'connection.update' => :process_connection_update,
    'messages.upsert' => :process_messages_upsert,
    'messages.update' => :process_messages_update,
    'messages.delete' => :process_messages_update
  }.freeze

  def process_event
    return unless event_name

    # First try the explicit map (whatsapp-api canonical event_type values).
    handler = EVENT_HANDLER_MAP[event_name.to_s]
    if handler
      send(handler)
      return
    end

    # Fallback: dotted/dashed event_name → method name
    # (e.g. "connection.update" → "process_connection_update").
    method_name = "process_#{event_name.to_s.gsub(/[\.-]/, '_')}"
    if respond_to?(method_name, true)
      send(method_name)
    else
      Rails.logger.debug { "Propriacloud unhandled event: #{event_name}" }
    end
  end
end
