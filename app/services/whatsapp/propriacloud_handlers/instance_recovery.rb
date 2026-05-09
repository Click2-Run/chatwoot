# frozen_string_literal: true

# Surfaces whatsapp-api's automatic recovery lifecycle into Chatwoot's
# `provider_connection` so the inbox-settings panel can show the user
# what's happening when the underlying instance is reconnecting after
# an unexpected logout.
#
# Handles event_type:
#   instance.recovery.detected   → connection: 'reconnecting'
#   instance.recovery.started    → connection: 'reconnecting'
#   instance.recovery.retry      → connection: 'reconnecting'
#   instance.recovery.success    → connection: 'open'
#   instance.recovery.exhausted  → connection: 'close', error message
#   instance.recovery.aborted    → connection: 'close', error message
module Whatsapp::PropriacloudHandlers::InstanceRecovery
  include Whatsapp::PropriacloudHandlers::Helpers

  private

  def process_instance_recovery
    # Recovery events are meaningful only when the instance was actually
    # paired. For unpaired instances we'd be flipping the UI to
    # "Reconectando" / triggering reconnect flows on a session that has
    # nothing to recover, which floods the API and confuses agents.
    return if inbox.channel.provider_config['paired_at'].blank?

    event = (processed_params[:event_type] || processed_params['event_type'] ||
             processed_params[:event] || processed_params['event']).to_s
    data = processed_params[:data] || {}

    state, error = case event
                   when 'instance.recovery.detected',
                        'instance.recovery.started',
                        'instance.recovery.retry'
                     ['reconnecting', nil]
                   when 'instance.recovery.success'
                     ['open', nil]
                   when 'instance.recovery.exhausted',
                        'instance.recovery.aborted'
                     ['close', data[:error] || data['error'] || event.split('.').last]
                   end
    return if state.nil?

    inbox.channel.update_provider_connection!(
      { connection: state, error: error&.to_s }.compact
    )
  end
end
