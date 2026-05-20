# frozen_string_literal: true

# Propagates contact-profile changes from WhatsApp into Chatwoot's
# Contact record. We only touch fields Chatwoot already supports —
# name and avatar — to keep the model surface unchanged.
#
# Handles event_type:
#   user.push_name_changed
#   user.business_name_changed   → Contact#name
#   user.picture_changed         → invalidates avatar; refetch lazily
module Whatsapp::PropriacloudHandlers::UserChanged
  include Whatsapp::PropriacloudHandlers::Helpers

  private

  def process_user_changed
    data = processed_params[:data] || {}
    event = (processed_params[:event_type] || processed_params['event_type'] ||
             processed_params[:event] || processed_params['event']).to_s

    jid = data[:jid] || data['jid'] || data.dig(:user, :jid) || data.dig('user', 'jid')
    return if jid.blank?

    phone = jid.to_s.split('@').first.split(':').first.gsub(/\D/, '')
    return if phone.blank?

    contact_inbox = ContactInbox.find_by(inbox_id: inbox.id, source_id: phone)
    return unless contact_inbox

    contact = contact_inbox.contact

    case event
    when 'user.push_name_changed', 'user.business_name_changed'
      new_name = data[:new_name] || data['new_name'] || data[:name] || data['name']
      contact.update!(name: new_name) if new_name.present? && contact.name != new_name
    when 'user.picture_changed'
      # Drop the cached avatar and let the next message-receive path or
      # an explicit Avatar::AvatarFromUrlJob refetch it.
      contact.avatar.purge_later if contact.avatar.attached?
      url = inbox.channel.provider_service.get_profile_pic("#{phone}@s.whatsapp.net")
      ::Avatar::AvatarFromUrlJob.perform_later(contact, url) if url.present?
    end
  end
end
