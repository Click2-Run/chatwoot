# frozen_string_literal: true

# Whatsapp Incoming Message Service for Whatsmeow Provider
#
# Processes webhook events from Whatsmeow API service
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

class Whatsapp::IncomingMessageWhatsmeowService < Whatsapp::IncomingMessageBaseService
  include Events::Types
  include Whatsapp::WhatsmeowHandlers::ConnectionUpdate
  include Whatsapp::WhatsmeowHandlers::MessagesUpsert
  include Whatsapp::WhatsmeowHandlers::MessagesUpdate

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
    webhook_token = processed_params[:webhook_verify_token] ||
                    processed_params['webhook_verify_token'] ||
                    processed_params[:webhookVerifyToken]

    expected_token = inbox.channel.provider_config['webhook_verify_token']

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
      Rails.logger.warn "Whatsmeow unsupported event: #{event_name}"
    end
  end
end
