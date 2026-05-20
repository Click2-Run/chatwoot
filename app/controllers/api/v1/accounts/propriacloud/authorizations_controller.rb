# frozen_string_literal: true

# POST /api/v1/accounts/:account_id/propriacloud/authorization
#
# Starts a Propria.Cloud Embedded Signup session for a new WhatsApp inbox.
# The user supplies their Propria.Cloud `tenant_key` (64-hex), the inbox name,
# and the phone number they want to onboard. We call minha's external-app
# API to create a one-time signup URL, persist the pending session, and
# return the URL for the frontend to open in a popup.
#
# Counterpart: Webhooks::PropriacloudController#embedded_signup
class Api::V1::Accounts::Propriacloud::AuthorizationsController < Api::V1::Accounts::BaseController
  def create
    validate_params!
    session, signup_url = Whatsapp::PropriacloudEmbeddedSignupService.start(
      account: Current.account,
      tenant_key: params[:tenant_key],
      intended_inbox_name: params[:inbox_name],
      phone_number: params[:phone_number],
      mark_as_read: params.fetch(:mark_as_read, true) == true || params[:mark_as_read].to_s == 'true',
      prefill: params[:prefill].permit!.to_h.deep_symbolize_keys
    )
    render json: {
      success: true,
      session_id: session.id,
      minha_session_id: session.minha_session_id,
      signup_url: signup_url,
      instance_id: session.instance_id
    }
  rescue ArgumentError => e
    render json: { success: false, error: e.message }, status: :bad_request
  rescue Whatsapp::PropriacloudEmbeddedSignupService::ProviderError => e
    Rails.logger.error "[PROPRIACLOUD AUTHORIZATION] minha call failed: #{e.message}"
    render json: { success: false, error: 'propriacloud_unavailable' }, status: :bad_gateway
  rescue StandardError => e
    Rails.logger.error "[PROPRIACLOUD AUTHORIZATION] unexpected error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def validate_params!
    missing = []
    missing << 'tenant_key' if params[:tenant_key].blank?
    missing << 'inbox_name' if params[:inbox_name].blank?
    missing << 'phone_number' if params[:phone_number].blank?
    raise ArgumentError, "Required parameters are missing: #{missing.join(', ')}" if missing.any?
  end
end
