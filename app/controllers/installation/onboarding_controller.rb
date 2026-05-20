class Installation::OnboardingController < ApplicationController
  before_action :ensure_installation_onboarding
  before_action :redirect_to_sso_if_configured, only: [:index]

  def index; end

  def create
    begin
      AccountBuilder.new(
        account_name: onboarding_params.dig(:user, :company),
        user_full_name: onboarding_params.dig(:user, :name),
        email: onboarding_params.dig(:user, :email),
        user_password: params.dig(:user, :password),
        super_admin: true,
        confirmed: true
      ).perform
    rescue StandardError => e
      redirect_to '/', flash: { error: e.message } and return
    end
    finish_onboarding
    redirect_to '/'
  end

  private

  def onboarding_params
    params.permit(:subscribe_to_updates, user: [:name, :company, :email])
  end

  def finish_onboarding
    ::Redis::Alfred.delete(::Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)
    return if onboarding_params[:subscribe_to_updates].blank?

    ChatwootHub.register_instance(
      onboarding_params.dig(:user, :company),
      onboarding_params.dig(:user, :name),
      onboarding_params.dig(:user, :email)
    )
  end

  def ensure_installation_onboarding
    redirect_to '/' unless ::Redis::Alfred.get(::Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)
  end

  # When a trusted OIDC provider (Própria Cloud / Logto) is configured, route
  # the first-boot operator straight into the SSO flow instead of the legacy
  # email/password wizard. The OmniAuth callback handles SuperAdmin promotion
  # and clears the onboarding flag, producing an equivalent bootstrap result.
  def redirect_to_sso_if_configured
    return unless propriacloud_oidc_configured?

    redirect_to '/auth/propriacloud', allow_other_host: false
  end

  def propriacloud_oidc_configured?
    issuer = ENV['PROPRIACLOUD_OPENID_ISSUER'].presence ||
             ENV['LOGTO_ISSUER'].presence ||
             ENV['LOGTO_ENDPOINT'].presence
    app_id = ENV['PROPRIACLOUD_OPENID_APP_ID'].presence ||
             ENV['LOGTO_APP_ID'].presence ||
             ENV['LOGTO_CLIENT_ID'].presence
    issuer.present? && app_id.present?
  end
end
