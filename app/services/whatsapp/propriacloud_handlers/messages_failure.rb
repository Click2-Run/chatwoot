# frozen_string_literal: true

# Surfaces send / decrypt / media-retry failures from whatsapp-api by
# flipping the matching Chatwoot Message into the `failed` status with
# a human-readable external_error. Reuses the same source_id lookup the
# upsert path uses, so payloads that reference unknown messages are
# silently dropped (e.g. delayed events for since-deleted conversations).
#
# Handles event_type:
#   message.sent_failed
#   message.undecryptable
#   message.error
#   message.media_retry_error
#   (message.media_retry is informational; we just log it.)
module Whatsapp::PropriacloudHandlers::MessagesFailure
  include Whatsapp::PropriacloudHandlers::Helpers

  private

  def process_messages_failure
    data = processed_params[:data] || {}
    event = (processed_params[:event_type] || processed_params['event_type'] ||
             processed_params[:event] || processed_params['event']).to_s

    source_id = data.dig(:key, :id) || data['key']&.dig('id') || data[:message_id] || data['message_id']
    return if source_id.blank?

    message = inbox.messages.find_by(source_id: source_id)
    return unless message

    if event == 'message.media_retry'
      Rails.logger.info "Propriacloud: media_retry queued for message #{source_id}"
      return
    end

    error_message = data[:error] || data['error'] || data[:reason] || data['reason'] || event.split('.').last
    message.update!(status: :failed, external_error: error_message.to_s.truncate(255))
  end
end
