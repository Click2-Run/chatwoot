# frozen_string_literal: true

# Configure OmniAuth path prefix early, before middleware is loaded
# This must be set before any OmniAuth::Builder middleware is instantiated
# devise_token_auth redirects from /auth/:provider to /omniauth/:provider
# so we configure OmniAuth to intercept /omniauth paths
OmniAuth.config.path_prefix = '/omniauth'

# Allow GET requests for OmniAuth (needed for devise_token_auth 307 redirects)
# omniauth-rails_csrf_protection requires POST by default, but devise_token_auth
# redirects with GET, so we need to allow it
OmniAuth.config.allowed_request_methods = [:get, :post]

# Disable CSRF verification for OAuth initiation (not the callback)
# The omniauth-rails_csrf_protection gem blocks GET requests by default
# but devise_token_auth uses 307 redirects which are GET requests
OmniAuth.config.request_validation_phase = nil
