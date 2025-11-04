# OmniAuth configuration
# Sets the full host URL for callbacks and proper redirect handling
OmniAuth.config.full_host = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil), ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil), {
    provider_ignores_state: true
  }

  # Logto OpenID Connect provider
  if ENV['LOGTO_ENDPOINT'].present? && ENV['LOGTO_CLIENT_ID'].present?
    provider :openid_connect, {
      name: :logto,
      issuer: ENV.fetch('LOGTO_ENDPOINT'),
      discovery: true,
      scope: [:openid, :profile, :email],
      response_type: :code,
      client_options: {
        identifier: ENV.fetch('LOGTO_CLIENT_ID'),
        secret: ENV.fetch('LOGTO_CLIENT_SECRET'),
        redirect_uri: "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/omniauth/logto/callback"
      }
    }
  end
end
