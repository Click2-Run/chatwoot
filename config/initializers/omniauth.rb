# OmniAuth configuration
# Sets the full host URL for callbacks and proper redirect handling
OmniAuth.config.full_host = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil), ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil), {
    provider_ignores_state: true
  }

  # Própria Cloud OpenID Connect provider
  # Cascade: PROPRIACLOUD_OPENID_* (current) -> LOGTO_* (upstream Logto naming)
  pc_issuer = ENV['PROPRIACLOUD_OPENID_ISSUER'].presence ||
              ENV['LOGTO_ISSUER'].presence ||
              ENV['LOGTO_ENDPOINT']
  pc_app_id = ENV['PROPRIACLOUD_OPENID_APP_ID'].presence ||
              ENV['LOGTO_APP_ID'].presence ||
              ENV['LOGTO_CLIENT_ID']
  pc_app_secret = ENV['PROPRIACLOUD_OPENID_APP_SECRET'].presence ||
                  ENV['LOGTO_APP_SECRET'].presence ||
                  ENV['LOGTO_CLIENT_SECRET']
  pc_scopes = (ENV['PROPRIACLOUD_OPENID_SCOPES'].presence ||
               ENV['LOGTO_SCOPES'].presence ||
               'openid profile email').split

  if pc_issuer.present? && pc_app_id.present?
    provider :openid_connect, {
      name: :propriacloud,
      issuer: pc_issuer,
      discovery: true,
      scope: pc_scopes,
      response_type: :code,
      provider_ignores_state: true,
      client_options: {
        identifier: pc_app_id,
        secret: pc_app_secret,
        redirect_uri: "#{ENV.fetch('FRONTEND_URL', 'https://localhost:3000')}/omniauth/propriacloud/callback"
      }
    }
  end
end
