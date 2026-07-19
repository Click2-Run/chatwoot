# frozen_string_literal: true

# Marker module mixed into every WhatsApp provider error that the
# provider-agnostic group stack (Groups::CreateService and the
# Api::V1::Accounts::Contacts::Group* controllers) should translate into a
# friendly 422 instead of surfacing as a 500.
#
# Both Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError
# and Whatsapp::Providers::WhatsappPropriacloudService::ProviderUnavailableError
# include it, so a single `rescue Whatsapp::Providers::GroupOperationError`
# handles group failures regardless of which provider backs the inbox.
module Whatsapp::Providers::GroupOperationError; end
