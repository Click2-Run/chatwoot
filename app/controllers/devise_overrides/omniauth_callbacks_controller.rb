class DeviseOverrides::OmniauthCallbacksController < DeviseTokenAuth::OmniauthCallbacksController
  include EmailHelper

  def omniauth_success
    get_resource_from_auth_hash

    @resource.present? ? sign_in_user : sign_up_user
  end

  def redirect_callbacks
    # derive target redirect route from 'resource_class' param, which was set
    # before authentication.
    devise_mapping = get_devise_mapping
    redirect_route = get_redirect_route(devise_mapping)

    # preserve omniauth info for success route. ignore 'extra' in twitter
    # auth response to avoid CookieOverflow.
    session['dta.omniauth.auth'] = request.env['omniauth.auth'].except('extra')
    session['dta.omniauth.params'] = request.env['omniauth.params']

    redirect_to redirect_route, redirect_options
  end

  private

  def sign_in_user
    # Capture before skip_confirmation! sets confirmed_at, which would
    # make oauth_user_needs_password_reset? return false and skip the
    # password reset for persisted unconfirmed users.
    needs_password_reset = oauth_user_needs_password_reset?
    @resource.skip_confirmation! if confirmable_enabled?
    set_random_password_if_oauth_user if needs_password_reset

    # Sync profile from OpenID provider if enabled (default: true)
    # This updates name, email, and picture but preserves display_name (Chatwoot-specific)
    sync_profile_from_oauth if should_sync_oauth_profile?

    # once the resource is found and verified
    # we can just send them to the login page again with the SSO params
    # that will log them in
    encoded_email = ERB::Util.url_encode(@resource.email)
    redirect_to login_page_url(email: encoded_email, sso_auth_token: @resource.generate_sso_auth_token)
  end

  def sign_in_user_on_mobile
    # See comment in sign_in_user for why this is captured before skip_confirmation!
    needs_password_reset = oauth_user_needs_password_reset?
    @resource.skip_confirmation! if confirmable_enabled?
    set_random_password_if_oauth_user if needs_password_reset

    # once the resource is found and verified
    # we can just send them to the login page again with the SSO params
    # that will log them in
    encoded_email = ERB::Util.url_encode(@resource.email)
    params = { email: encoded_email, sso_auth_token: @resource.generate_sso_auth_token }.to_query

    mobile_deep_link_base = GlobalConfigService.load('MOBILE_DEEP_LINK_BASE', 'chatwootapp')
    redirect_to "#{mobile_deep_link_base}://auth/saml?#{params}", allow_other_host: true
  end

  def sign_up_user
    return redirect_to login_page_url(error: 'no-account-found') unless account_signup_allowed?
    # Skip domain validation for trusted OAuth providers (Click2Run, etc.)
    unless trusted_oauth_provider?
      return redirect_to login_page_url(error: 'business-account-only') unless validate_signup_email_is_business_domain?
    end

    create_account_for_user

    # For trusted OAuth providers (Click2Run/Logto), assign a secure random
    # password (so the User record satisfies devise-secure_password validators)
    # and sign in directly — these accounts are OAuth-only and never use a
    # password to log in.
    if trusted_oauth_provider?
      set_random_password_if_oauth_user
      sign_in_user
    else
      # For standard OAuth (Google), require password setup for account recovery
      set_random_password_if_oauth_user
      token = @resource.send(:set_reset_password_token)
      frontend_url = ENV.fetch('FRONTEND_URL', nil)
      redirect_to "#{frontend_url}/app/auth/password/edit?config=default&reset_password_token=#{token}"
    end
  end

  def login_page_url(error: nil, email: nil, sso_auth_token: nil)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    params = { email: email, sso_auth_token: sso_auth_token }.compact
    params[:error] = error if error.present?

    "#{frontend_url}/app/login?#{params.to_query}"
  end

  def account_signup_allowed?
    GlobalConfigService.account_signup_enabled?
  end

  def resource_class(_mapping = nil)
    User
  end

  def get_resource_from_auth_hash # rubocop:disable Naming/AccessorMethodName
    email = auth_hash.dig('info', 'email')
    @resource = resource_class.from_email(email)
  end

  def validate_signup_email_is_business_domain?
    # return true if the user is a business account, false if it is a blocked domain account
    Account::SignUpEmailValidationService.new(auth_hash['info']['email']).perform
  rescue CustomExceptions::Account::InvalidEmail
    false
  end

  def create_account_for_user
    # For Click2Run OpenID, use "Organization" as account name
    # For other providers, extract domain without TLD
    account_name = trusted_oauth_provider? ? 'Organization' : extract_domain_without_tld(auth_hash['info']['email'])

    @resource, @account = AccountBuilder.new(
      account_name: account_name,
      user_full_name: extract_full_name_from_auth_hash,
      email: auth_hash['info']['email'],
      locale: I18n.locale,
      confirmed: auth_hash['info']['email_verified']
    ).perform
    Avatar::AvatarFromUrlJob.perform_later(@resource, auth_hash['info']['image'])
  end

  def extract_full_name_from_auth_hash
    # Try to build full name from given_name and family_name (OpenID Connect standard claims)
    # Logto provides these as separate fields
    given_name = auth_hash['info']['given_name'] || auth_hash['info']['first_name']
    family_name = auth_hash['info']['family_name'] || auth_hash['info']['last_name']

    if given_name.present? && family_name.present?
      "#{given_name} #{family_name}".strip
    elsif given_name.present?
      given_name
    elsif family_name.present?
      family_name
    else
      # Fallback to 'name' field if given_name/family_name not available
      # If nothing is available, return empty string (user can set name later)
      auth_hash['info']['name'].presence || ''
    end
  end

  def oauth_user_needs_password_reset?
    @resource.present? && (@resource.new_record? || !@resource.confirmed?)
  end

  def set_random_password_if_oauth_user
    # Password must satisfy secure_password requirements (uppercase, lowercase, number, special char)
    @resource.update!(password: "#{SecureRandom.hex(16)}aA1!") if @resource.persisted?
  end

  def default_devise_mapping
    'user'
  end

  def trusted_oauth_provider?
    # List of OAuth providers that are trusted and should skip domain validation
    # Click2Run is a trusted SSO provider, so we allow any email domain
    trusted_providers = ['click2run']
    trusted_providers.include?(auth_hash['provider'])
  end

  def should_sync_oauth_profile?
    # Check if profile sync is enabled for Click2Run OpenID Connect
    # Default to true if not set (always sync)
    return false unless trusted_oauth_provider?

    sync_enabled = ENV.fetch('CLICK2RUN_OPENID_ALWAYS_SYNC', 'true')
    sync_enabled.to_s.downcase != 'false'
  end

  def sync_profile_from_oauth
    # Update user profile from OAuth provider data
    # Preserves display_name (Chatwoot-specific, user-customizable)
    @resource.name = extract_full_name_from_auth_hash
    @resource.email = auth_hash['info']['email'] if auth_hash['info']['email'].present?

    # Save changes if any field was modified
    @resource.save! if @resource.changed?

    # Update avatar from OAuth provider picture (async job)
    Avatar::AvatarFromUrlJob.perform_later(@resource, auth_hash['info']['image']) if auth_hash['info']['image'].present?
  end

  def generate_secure_random_password
    # Generate a password that meets Chatwoot's complexity requirements:
    # - 1 uppercase letter (A-Z)
    # - 1 lowercase letter (a-z)
    # - 1 number (0-9)
    # - 1 special character (!@#$%^&*()_+-=[]{}|')
    # - Minimum 8 characters (Devise default)
    uppercase = ('A'..'Z').to_a.sample
    lowercase = ('a'..'z').to_a.sample
    number = ('0'..'9').to_a.sample
    special = '!@#$%^&*()_+-=[]{}|'.chars.sample

    # Add 20 more random characters for total of 24 characters
    random_chars = 20.times.map do
      [('A'..'Z').to_a, ('a'..'z').to_a, ('0'..'9').to_a, '!@#$%^&*()_+-=[]{}|'.chars].flatten.sample
    end

    # Combine and shuffle to avoid predictable pattern
    [uppercase, lowercase, number, special, *random_chars].shuffle.join
  end
end

DeviseOverrides::OmniauthCallbacksController.prepend_mod_with('DeviseOverrides::OmniauthCallbacksController')
