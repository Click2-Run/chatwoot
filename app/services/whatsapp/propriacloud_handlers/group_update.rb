# frozen_string_literal: true

# Propriacloud Group Update Handler
#
# whatsapp-api exposes only two group webhook events — `group.joined` and
# `group.info_changed` — and (unlike baileys) does NOT push discrete
# participant add/remove events. So membership is reconciled by pulling the
# authoritative roster from GET /groups/info whenever one of these fires.
#
# To avoid spamming the inbox with conversations for silent groups, we only
# reconcile groups that have ALREADY surfaced a conversation (i.e. a message
# arrived and GroupMessage created the group ContactInbox). Brand-new groups
# are picked up lazily on their first message instead.
module Whatsapp::PropriacloudHandlers::GroupUpdate
  private

  def process_group_update
    jid = resolve_group_jid
    return if jid.blank?

    # ContactInbox#source_id holds the bare group id (digits); the full
    # "<id>@g.us" JID lives in Contact#identifier.
    contact_inbox = inbox.contact_inboxes.find_by(source_id: jid.split('@').first)
    return if contact_inbox.blank?

    # force: true — a group.info_changed means something we cache (name,
    # settings, membership) is stale, so bypass the SyncGroupJob cooldown.
    Contacts::SyncGroupJob.perform_later(contact_inbox.contact, force: true)
  end

  def resolve_group_jid # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    data = processed_params[:data] || {}
    raw = %i[jid group_jid id].filter_map { |k| data[k] || data[k.to_s] }.first
    raw ||= data.dig(:group, :jid) || data.dig('group', 'jid')

    return raw if raw.is_a?(String)
    return if raw.blank? || !raw.respond_to?(:[])

    user = raw[:user] || raw['user']
    user.present? ? "#{user}@#{raw[:server] || raw['server'] || 'g.us'}" : nil
  end
end
