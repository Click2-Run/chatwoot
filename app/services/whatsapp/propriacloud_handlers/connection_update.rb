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

    # Connection states from Propriacloud:
    #   - `close`: Disconnected, no longer able to send/receive messages
    #   - `connecting`: In the process of connecting, QR code available
    #   - `open`: Connected and ready to send/receive messages

    connection_data = {
      connection: data[:connection] || data['connection'] || inbox.channel.provider_connection['connection'],
      qr_data_url: extract_qr_data_url(data),
      error: extract_error_message(data)
    }.compact

    inbox.channel.update_provider_connection!(connection_data)

    log_connection_state(data)
  end

  def extract_qr_data_url(data)
    # Propriacloud sends QR code as base64 PNG when connecting
    qr_code = data[:qr_code] || data['qr_code']
    return nil unless qr_code

    # Convert to data URL if not already in that format
    if qr_code.start_with?('data:image/')
      qr_code
    else
      "data:image/png;base64,#{qr_code}"
    end
  end

  def extract_error_message(data)
    error = data[:error] || data['error']
    return nil unless error

    # Translate error message using i18n
    I18n.t("errors.inboxes.channel.provider_connection.#{error}", default: error.to_s)
  end

  def log_connection_state(data)
    connection = data[:connection] || data['connection']
    error = data[:error] || data['error']

    if error.present?
      Rails.logger.error "Propriacloud connection error",
                         inbox_id: inbox.id,
                         phone_number: inbox.channel.phone_number,
                         error: error
    else
      Rails.logger.info "Propriacloud connection update",
                        inbox_id: inbox.id,
                        phone_number: inbox.channel.phone_number,
                        connection: connection
    end
  end
end
