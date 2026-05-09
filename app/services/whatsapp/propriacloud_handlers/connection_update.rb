# frozen_string_literal: true

# Propriacloud Connection Update Handler
# Processes connection state changes and QR code updates from Propriacloud
#
# Event payload format from Propriacloud:
# {
#   event: "connection.update",
#   instance_id: "1234567890",
#   timestamp: 1699123456,
#   data: {
#     connection: "connecting" | "open" | "close",
#     qr_code: "base64_png_data" (only when connection == "connecting"),
#     error: "connection_lost" | "logout" (optional)
#   }
# }

module Whatsapp::PropriacloudHandlers::ConnectionUpdate
  include Whatsapp::PropriacloudHandlers::Helpers

  private

  def process_connection_update
    data = processed_params[:data] || {}
    event = (processed_params[:event_type] || processed_params['event_type'] ||
             processed_params[:event] || processed_params['event']).to_s

    previous_state = inbox.channel.provider_connection&.dig('connection')

    connection_data = {
      connection: infer_connection_state(event, data),
      qr_data_url: extract_qr_data_url(data),
      error: extract_error_message(data, event)
    }.compact

    inbox.channel.update_provider_connection!(connection_data)

    log_connection_state(event, data)
    enqueue_history_backfill_if_needed(previous_state, connection_data[:connection])
  end

  # Trigger a one-shot history pull the first time the inbox transitions
  # into `open`. The job itself is idempotent (skips if already
  # completed) so even a flap that toggles open→close→open won't re-run.
  def enqueue_history_backfill_if_needed(previous_state, current_state)
    return unless current_state == 'open'
    return if previous_state == 'open'
    return if inbox.channel.provider_config['history_backfill_completed_at'].present?

    Whatsapp::Propriacloud::HistoryBackfillJob.perform_later(inbox.channel.id)
  end

  # Map whatsapp-api event_type values to the Chatwoot connection state
  # vocabulary (open / connecting / close). Falls back to the in-payload
  # `connection` field for legacy / generic events.
  def infer_connection_state(event, data)
    case event
    when 'connection.connected', 'pairing.success'
      'open'
    when 'pairing.qrcode', 'pairing.phonecode'
      'connecting'
    when 'connection.disconnected',
         'connection.logged_out',
         'connection.stream_replaced',
         'connection.connect_failure',
         'connection.client_outdated',
         'connection.temporary_ban',
         'connection.stream_error',
         'pairing.error'
      'close'
    else
      data[:connection] || data['connection'] || inbox.channel.provider_connection['connection']
    end
  end

  def extract_qr_data_url(data)
    # whatsapp-api QR delivery fields (in order of preference):
    #   - `img`: full base64 PNG (preferred for direct UI rendering)
    #   - `code`: the WhatsApp pairing code (text); UI generates QR from it
    #   - `qr_code`: legacy fazer-ai naming
    qr = data[:img] || data['img'] ||
         data[:qr_code] || data['qr_code'] ||
         data[:qrcode] || data['qrcode']
    return nil if qr.blank?

    return qr if qr.start_with?('data:image/')

    "data:image/png;base64,#{qr}"
  end

  def extract_error_message(data, event = nil)
    error = data[:error] || data['error']
    error ||= event.split('.', 2).last if event.to_s.start_with?('connection.', 'pairing.error')
    return nil if error.blank?

    I18n.t("errors.inboxes.channel.provider_connection.#{error}", default: error.to_s)
  end

  def log_connection_state(event, data)
    error = data[:error] || data['error']
    if error.present?
      Rails.logger.error "Propriacloud #{event} error: #{error} (inbox=#{inbox.id})"
    else
      Rails.logger.info "Propriacloud #{event} (inbox=#{inbox.id} state=#{inbox.channel.provider_connection['connection']})"
    end
  end
end
