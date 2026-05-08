# frozen_string_literal: true

# Whatsapp Incoming Message Service for Click2Run Provider
#
# Processes webhook events from Click2Run service
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

class Whatsapp::IncomingMessageClick2runService < Whatsapp::IncomingMessageBaseService
  include Events::Types
  include Whatsapp::Click2runHandlers::ConnectionUpdate
  include Whatsapp::Click2runHandlers::MessagesUpsert
  include Whatsapp::Click2runHandlers::MessagesUpdate

  class InvalidWebhookVerifyToken < StandardError; end

  def perform # rubocop:disable Metrics/AbcSize
    validate_webhook_token!
    return if processed_params[:event].blank? || processed_params[:data].blank?

    # Dispatch provider event for tracking/analytics
    Rails.configuration.dispatcher.dispatch(
      PROVIDER_EVENT_RECEIVED,
      Time.zone.now,
      inbox: inbox,
      event: processed_params[:event],
      payload: processed_params[:data]
    )

    # Process event based on type
    process_event
  end

  private

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

  def process_event
    event_name = processed_params[:event] || processed_params['event']
    return unless event_name

    # Convert event name to method name (connection.update → process_connection_update)
    event_prefix = event_name.to_s.gsub(/[\.-]/, '_')
    method_name = "process_#{event_prefix}"

    if respond_to?(method_name, true)
      send(method_name)
    else
      Rails.logger.warn "Click2Run unsupported event: #{event_name}"
    end
  end
end
