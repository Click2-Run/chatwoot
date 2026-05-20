# frozen_string_literal: true

# Async wrapper around Whatsapp::Propriacloud::HistoryBackfillService.
# Runs on Sidekiq's default queue with one in-flight job per channel
# (uniqueness keyed by channel id) so a re-pair doesn't double-run.
class Whatsapp::Propriacloud::HistoryBackfillJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  def perform(channel_id, force: false)
    channel = Channel::Whatsapp.find_by(id: channel_id)
    return unless channel
    return if channel.provider != 'propriacloud'
    return if channel.provider_config['history_backfill_completed_at'].present? && !force

    Whatsapp::Propriacloud::HistoryBackfillService.new(channel: channel).perform
  end
end
