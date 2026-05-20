# frozen_string_literal: true

# Records the lifecycle of whatsapp-api's HistorySync stream so that
# the inbox-settings UI can show "Sync in progress / Sync completed
# at <timestamp>". Per-record events
# (history.sync_conversation/_messages/_contacts) are intentionally
# NO-OP here — we rely on the dedicated HistoryBackfillJob to pull
# them via /sync/* endpoints, which is more deterministic than
# stream-driven event handling. Keeping the events in the
# subscription means we can swap to event-driven later without API
# changes.
#
# Handles event_type:
#   history.sync_started   → set provider_config['history_sync_started_at']
#   history.sync_completed → set provider_config['history_sync_completed_at']
module Whatsapp::PropriacloudHandlers::HistorySync
  include Whatsapp::PropriacloudHandlers::Helpers

  private

  def process_history_sync
    event = (processed_params[:event_type] || processed_params['event_type'] ||
             processed_params[:event] || processed_params['event']).to_s

    return unless event.start_with?('history.sync_')

    case event
    when 'history.sync_started'
      stamp_provider_config('history_sync_started_at')
    when 'history.sync_completed'
      stamp_provider_config('history_sync_completed_at')
    end
  end

  def stamp_provider_config(key)
    config = inbox.channel.provider_config || {}
    config[key] = Time.current.iso8601
    inbox.channel.update!(provider_config: config)
  end
end
