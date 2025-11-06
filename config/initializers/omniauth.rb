# OmniAuth configuration
# Sets the full host URL for callbacks and proper redirect handling
OmniAuth.config.full_host = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil), ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil), {
    provider_ignores_state: true
  }

  # Click2Run OpenID Connect provider
  # Supports multiple environment variable names for backward compatibility
  click2run_issuer = ENV['CLICK2RUN_OPENID_ISSUER'].presence || ENV['LOGTO_ISSUER'].presence || ENV['LOGTO_ENDPOINT']
  click2run_app_id = ENV['CLICK2RUN_OPENID_APP_ID'].presence || ENV['LOGTO_APP_ID'].presence || ENV['LOGTO_CLIENT_ID']
  click2run_app_secret = ENV['CLICK2RUN_OPENID_APP_SECRET'].presence || ENV['LOGTO_APP_SECRET'].presence || ENV['LOGTO_CLIENT_SECRET']
  click2run_scopes = ENV.fetch('CLICK2RUN_OPENID_SCOPES', ENV.fetch('LOGTO_SCOPES', 'openid profile email')).split

  if click2run_issuer.present? && click2run_app_id.present?
    provider :openid_connect, {
      name: :click2run,
      issuer: click2run_issuer,
      discovery: true,
      scope: click2run_scopes,
      response_type: :code,
      provider_ignores_state: true,
      client_options: {
        identifier: click2run_app_id,
        secret: click2run_app_secret,
        redirect_uri: "#{ENV.fetch('FRONTEND_URL', 'https://localhost:3000')}/omniauth/click2run/callback"
      }
    }
  end
end
