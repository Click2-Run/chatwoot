# Custom Authentication Configuration for Chatwoot

This document describes custom authentication enhancements for Chatwoot when using external Identity Providers (IdP) like Click2Run OpenID Connect, Logto, or other OAuth/SAML providers.

## Table of Contents

- [Overview](#overview)
- [Environment Variables](#environment-variables)
  - [AUTH_SUPERADMIN_SAME_SESSION](#auth_superadmin_same_session)
  - [AUTH_DISABLE_DEFAULT](#auth_disable_default)
- [Use Cases](#use-cases)
- [Security Considerations](#security-considerations)
- [Implementation Details](#implementation-details)

## Overview

When using an external Identity Provider (IdP) for authentication, Chatwoot's default email/password authentication system can be unnecessary or even problematic. These custom authentication features allow you to:

1. **Simplify Super Admin access** for SSO users who don't have passwords
2. **Disable default authentication** entirely when using external IdP exclusively

## Environment Variables

### AUTH_SUPERADMIN_SAME_SESSION

**Purpose**: Allow Super Admin panel access using existing authenticated user session.

**Default**: `false`

**Values**:
- `true`: Reuse existing session for Super Admin access (seamless for SSO users)
- `false`: Require separate Devise email/password authentication (default, more secure)

**When to use**:
- You're using SSO/OpenID/OAuth providers where users don't have passwords
- Your SuperAdmin users authenticate via external IdP
- You want seamless transition from regular dashboard to Super Admin panel

**Configuration**:

```bash
# .env.example (production default - more secure)
AUTH_SUPERADMIN_SAME_SESSION=false

# .env (local development with Click2Run OpenID)
AUTH_SUPERADMIN_SAME_SESSION=true
```

**How it works**:

1. User authenticates via OAuth/OpenID (e.g., Click2Run)
2. User is logged into Chatwoot dashboard
3. If user has `SuperAdmin` type and `AUTH_SUPERADMIN_SAME_SESSION=true`:
   - Clicking "Super Admin" menu automatically grants access
   - No password prompt required
4. If `AUTH_SUPERADMIN_SAME_SESSION=false`:
   - User must enter separate Devise password to access Super Admin panel
   - Default security model (separate authentication scope)

**Implementation**:
- Controller: `app/controllers/super_admin/application_controller.rb`
- Method: `authenticate_super_admin_or_redirect!`

---

### AUTH_DISABLE_DEFAULT

**Purpose**: Completely disable default Chatwoot email/password authentication when using external IdP.

**Default**: `false`

**Values**:
- `true`: Disable default auth (users must authenticate via OAuth/OpenID only)
- `false`: Enable default auth (users can use email/password or OAuth/OpenID)

**When to use**:
- You have a centralized Identity Provider (Click2Run Auth, Logto, Okta, etc.)
- ALL users must authenticate through the IdP (company policy/security requirement)
- You want to prevent password-based attacks and simplify user management
- You're managing users entirely in the external IdP

**⚠️ IMPORTANT**: Before enabling, ensure:
1. At least one OAuth/OpenID provider is properly configured
2. You have tested SSO login successfully
3. You have a backup SuperAdmin account accessible via IdP
4. You understand that password reset and email/password login will be completely disabled

**Configuration**:

```bash
# .env.example (production default - keep default auth enabled)
AUTH_DISABLE_DEFAULT=false

# .env (local development with Click2Run OpenID - disable default auth)
AUTH_DISABLE_DEFAULT=true
```

**What gets disabled**:

**Frontend (UI)**:
- ✗ Email/Password login form (hidden from login page)
- ✗ "Sign Up" link (hidden)
- ✗ "Forgot Password" link (hidden)
- ✓ OAuth/OpenID login buttons (still visible)
- ✓ SAML login button (still visible if Enterprise)

**Backend (API)**:
- ✗ `POST /auth/sign_in` - Email/password login (blocked)
- ✗ `POST /auth/password` - Password reset request (blocked)
- ✗ `PUT /auth/password` - Password reset confirmation (blocked)
- ✗ `POST /api/v1/accounts` - Account signup (blocked)
- ✓ OAuth/OpenID callbacks (still work)
- ✓ SSO authentication (still works)
- ✓ MFA verification (still works if using SSO+MFA)

**Implementation**:

1. **Frontend** (`app/javascript/v3/views/login/Index.vue`):
   - Checks `window.chatwootConfig.authDisableDefault`
   - Conditionally hides login form, signup link, forgot password link
   - Only shows OAuth/OpenID/SAML buttons

2. **Backend Controllers**:
   - `app/controllers/devise_overrides/sessions_controller.rb`:
     - `before_action :check_default_auth_disabled`
     - Returns 403 Forbidden for email/password login
   - `app/controllers/devise_overrides/passwords_controller.rb`:
     - `before_action :check_default_auth_disabled`
     - Returns 403 Forbidden for password reset
   - `app/controllers/api/v1/accounts_controller.rb`:
     - `before_action :check_default_auth_disabled`
     - Returns 404 Not Found for account signup

3. **Configuration Exposure** (`app/views/layouts/vueapp.html.erb`):
   - Exposes `authDisableDefault` to frontend via `window.chatwootConfig`

---

## Use Cases

### Use Case 1: SSO-Only Environment with Click2Run OpenID

**Scenario**: Company uses Click2Run Auth as centralized IdP for all services

**Configuration**:
```bash
# External IdP Configuration
CLICK2RUN_OPENID_ISSUER=https://auth.click2.run/oidc
CLICK2RUN_OPENID_APP_ID=your_app_id
CLICK2RUN_OPENID_APP_SECRET=your_app_secret
CLICK2RUN_OPENID_SCOPES=openid profile email

# Authentication Customization
AUTH_DISABLE_DEFAULT=true              # Disable email/password auth
AUTH_SUPERADMIN_SAME_SESSION=true      # Seamless SuperAdmin access
ENABLE_ACCOUNT_SIGNUP=true             # Allow OAuth account creation
```

**Result**:
- Users see only "Sign in with Click2Run" button
- No email/password form
- No signup or forgot password links
- SuperAdmins access panel without separate password
- All user management happens in Click2Run Auth

### Use Case 2: Hybrid Environment (Development/Testing)

**Scenario**: Testing SSO integration while keeping fallback authentication

**Configuration**:
```bash
CLICK2RUN_OPENID_ISSUER=https://auth.click2.run/oidc
CLICK2RUN_OPENID_APP_ID=your_app_id
CLICK2RUN_OPENID_APP_SECRET=your_app_secret

AUTH_DISABLE_DEFAULT=false             # Keep default auth enabled
AUTH_SUPERADMIN_SAME_SESSION=false     # Separate SuperAdmin password
ENABLE_ACCOUNT_SIGNUP=true
```

**Result**:
- Users can choose between Click2Run SSO or email/password
- Signup and password reset still available
- SuperAdmin requires separate password (more secure)

### Use Case 3: Enterprise with SAML + OAuth

**Scenario**: Large enterprise with SAML for employees + Click2Run for customers

**Configuration**:
```bash
# SAML Configuration (Enterprise)
# ... SAML settings ...

# Click2Run OAuth (Customer portal)
CLICK2RUN_OPENID_ISSUER=https://auth.click2.run/oidc
CLICK2RUN_OPENID_APP_ID=customer_app_id
CLICK2RUN_OPENID_APP_SECRET=customer_secret

# Authentication Settings
AUTH_DISABLE_DEFAULT=true              # Disable password auth
AUTH_SUPERADMIN_SAME_SESSION=true      # Seamless access
ENABLE_ACCOUNT_SIGNUP=true             # OAuth signup allowed
```

**Result**:
- Employees use SAML
- Customers use Click2Run OAuth
- No email/password authentication
- SuperAdmin access via existing session

---

## Security Considerations

### When AUTH_SUPERADMIN_SAME_SESSION=true

**Risks**:
- If regular user session is compromised, SuperAdmin panel is also accessible
- Single point of failure (no defense in depth)

**Mitigations**:
- Only enable in trusted environments (corporate network, VPN)
- Ensure strong SSO/IdP security (MFA, device trust)
- Use IP allowlisting for SuperAdmin routes if possible
- Regular security audits of IdP configuration
- Monitor SuperAdmin access logs

**Best Practice**: Use `AUTH_SUPERADMIN_SAME_SESSION=false` in production unless you have strong IdP security controls

### When AUTH_DISABLE_DEFAULT=true

**Risks**:
- If IdP becomes unavailable, NO ONE can login (including SuperAdmins)
- If OAuth/OpenID configuration breaks, system is inaccessible
- Account recovery becomes impossible without database access

**Mitigations**:
1. **Always have a backup plan**:
   ```bash
   # Emergency: Temporarily re-enable default auth via console
   docker compose exec rails rails c
   # In Rails console:
   ENV['AUTH_DISABLE_DEFAULT'] = 'false'
   # Then login with email/password
   ```

2. **Test thoroughly before enabling**:
   - Verify OAuth login works for multiple users
   - Confirm SuperAdmin access via OAuth
   - Test account creation flow
   - Document IdP configuration

3. **Monitor IdP health**:
   - Set up monitoring for IdP availability
   - Configure alerts for OAuth failures
   - Test failover procedures

4. **Backup SuperAdmin access**:
   - Keep at least one local SuperAdmin account (even if unused)
   - Document database recovery procedures
   - Store emergency access instructions securely

**Best Practice**: Only enable `AUTH_DISABLE_DEFAULT=true` when you have:
- Highly available IdP (99.9%+ uptime)
- Tested disaster recovery procedures
- Multiple ways to access Rails console if needed
- Clear understanding of the risks

---

## Implementation Details

### Frontend Changes

**File**: `app/javascript/v3/views/login/Index.vue`

**Added Computed Property**:
```javascript
isDefaultAuthDisabled() {
  // Check if default Chatwoot authentication is disabled (using external IdP)
  return parseBoolean(window.chatwootConfig.authDisableDefault);
}
```

**Conditional Rendering**:
```vue
<!-- Hide login form if default auth disabled -->
<form v-if="!isDefaultAuthDisabled" class="space-y-5" @submit.prevent="submitFormLogin">
  <!-- Email/Password inputs -->
</form>

<!-- Hide signup link if default auth disabled -->
<p v-if="showSignupLink && !isDefaultAuthDisabled">
  <router-link to="auth/signup">{{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}</router-link>
</p>

<!-- Hide divider if default auth disabled -->
<SimpleDivider v-if="!isDefaultAuthDisabled && (showGoogleOAuth || showClick2RunOpenid || showSamlLogin)" />
```

### Backend Changes

**File**: `app/controllers/devise_overrides/sessions_controller.rb`

```ruby
before_action :check_default_auth_disabled, only: [:create]

def check_default_auth_disabled
  # Block default email/password authentication if AUTH_DISABLE_DEFAULT=true
  # Allow SSO/OAuth authentication to pass through
  return if sso_authentication_request? || mfa_verification_request?

  is_disabled = ENV.fetch('AUTH_DISABLE_DEFAULT', 'false').to_s.downcase == 'true'
  return unless is_disabled

  render json: {
    error: 'Default authentication is disabled. Please use SSO/OAuth to sign in.'
  }, status: :forbidden
end
```

**File**: `app/controllers/devise_overrides/passwords_controller.rb`

```ruby
before_action :check_default_auth_disabled, only: [:create, :update]

def check_default_auth_disabled
  is_disabled = ENV.fetch('AUTH_DISABLE_DEFAULT', 'false').to_s.downcase == 'true'
  return unless is_disabled

  render json: {
    error: 'Password reset is disabled. Please contact your administrator or use SSO/OAuth to sign in.'
  }, status: :forbidden
end
```

**File**: `app/controllers/api/v1/accounts_controller.rb`

```ruby
before_action :check_default_auth_disabled, only: [:create]

def check_default_auth_disabled
  # Block account signup if default authentication is disabled
  is_disabled = ENV.fetch('AUTH_DISABLE_DEFAULT', 'false').to_s.downcase == 'true'
  raise ActionController::RoutingError, 'Not Found' if is_disabled
end
```

**File**: `app/controllers/super_admin/application_controller.rb`

```ruby
def authenticate_super_admin_or_redirect!
  return if super_admin_signed_in?

  # Allow Super Admin access via existing user session if enabled
  if ENV.fetch('AUTH_SUPERADMIN_SAME_SESSION', 'false') == 'true'
    if current_user&.is_a?(SuperAdmin)
      sign_in(:super_admin, current_user)
      return
    end
  end

  redirect_to new_super_admin_session_path unless super_admin_signed_in?
end
```

---

## Troubleshooting

### I enabled AUTH_DISABLE_DEFAULT and now I can't login!

**Solution**:
1. Access Rails console:
   ```bash
   docker compose exec rails rails c
   ```

2. Temporarily disable the check:
   ```ruby
   ENV['AUTH_DISABLE_DEFAULT'] = 'false'
   ```

3. Login with email/password

4. Fix your OAuth configuration

5. Re-enable: Set `AUTH_DISABLE_DEFAULT=false` in `.env` file

### OAuth users can't access SuperAdmin even with AUTH_SUPERADMIN_SAME_SESSION=true

**Possible causes**:
1. User is not actually a SuperAdmin type
2. ENV variable not loaded (restart required)
3. User session not properly authenticated

**Solution**:
```bash
# Check user type in Rails console
docker compose exec rails rails c
user = User.find_by(email: 'admin@example.com')
puts user.type  # Should be "SuperAdmin"

# Upgrade user to SuperAdmin if needed
user.type = 'SuperAdmin'
user.save!
```

### Password reset link still shows even with AUTH_DISABLE_DEFAULT=true

**Solution**: Clear browser cache and hard refresh (Ctrl+Shift+R / Cmd+Shift+R)

The frontend checks `window.chatwootConfig.authDisableDefault` which is rendered server-side. If the page was cached before enabling the ENV variable, the old version may still show.

---

## References

- [Click2Run OpenID Integration](/.codi/CLICK2RUN_OPENID_INTEGRATION.md)
- [Chatwoot OAuth Documentation](https://www.chatwoot.com/docs/product/channels/live-chat/integrations/google-oauth)
- [Devise Documentation](https://github.com/heartcombo/devise)
- [OAuth 2.0 Specification](https://oauth.net/2/)
- [OpenID Connect](https://openid.net/connect/)
