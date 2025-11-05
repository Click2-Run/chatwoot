# Click2Run Auth OpenID Connect Integration - Setup Guide

**Branch:** `codi-click2run`
**Date:** 2025-11-04
**Implementation:** Simple OAuth approach following Google OAuth pattern

---

## Overview

This guide documents the Click2Run Auth OpenID Connect integration for Chatwoot. The implementation follows the existing Google OAuth pattern, treating Click2Run Auth as another OAuth provider using OmniAuth middleware.

### Architecture

```
User → Click "Login with Click2Run Auth" → /auth/click2run (OmniAuth)
                                        ↓
                                   Click2Run Authorization
                                        ↓
                         /omniauth/click2run/callback (OmniAuth)
                                        ↓
                    DeviseOverrides::OmniauthCallbacksController
                                        ↓
                              Create/Sign in User
                                        ↓
                              Redirect to Dashboard
```

---

## Implementation Summary

### Files Created (3 files)

1. **`app/javascript/v3/components/Click2Run AuthOauth/Button.vue`** (~50 lines)
   - Vue component for "Login with Click2Run Auth" button
   - Redirects to `/auth/click2run` to initiate OAuth flow

2. **`.llm/planning/20251104_click2run_oauth_implementation.md`**
   - Technical analysis and planning document

3. **`.codi/CLICK2RUN_SETUP_GUIDE.md`** (this file)
   - Setup and configuration guide

### Files Modified (5 files)

1. **`Gemfile`** (+1 line)
   - Added `gem 'omniauth-openid-connect'`

2. **`config/initializers/omniauth.rb`** (+14 lines)
   - Added Click2Run Auth OpenID Connect provider configuration
   - Conditional loading based on environment variables

3. **`.env.example`** (+5 lines)
   - Added Click2Run Auth environment variable documentation

4. **`app/views/layouts/vueapp.html.erb`** (+1 line)
   - Exposed `click2runClientId` to frontend via `window.chatwootConfig`

5. **`app/javascript/v3/views/login/Index.vue`** (~10 lines)
   - Imported Click2Run AuthOAuthButton component
   - Added `showClick2Run AuthOAuth` computed property
   - Added Click2Run Auth button to login form

6. **`app/javascript/dashboard/i18n/locale/en/login.json`** (+1 line)
   - Added `CLICK2RUN_LOGIN` translation key

### Total Code: ~75 lines

---

## Installation Steps

### 1. Install Dependencies

```bash
bundle install
pnpm install
```

This will install the `omniauth-openid-connect` gem required for Click2Run Auth integration.

### 2. Configure Click2Run Auth Application

#### 2.1 Create Click2Run Auth Application

1. Go to your Click2Run Auth Console: `https://your-tenant.click2run.app`
2. Navigate to **Applications**
3. Click **Create Application**
4. Select **Traditional Web Application**
5. Name it: `Chatwoot`

#### 2.2 Configure Application Settings

**Redirect URIs:**
- Development: `http://localhost:3000/omniauth/click2run/callback`
- Production: `https://your-domain.com/omniauth/click2run/callback`

**Post Sign-out Redirect URIs:**
- Development: `http://localhost:3000`
- Production: `https://your-domain.com`

**CORS Allowed Origins:**
- Not required for server-side OAuth flow

**Scopes:**
- `openid` (required)
- `profile` (required)
- `email` (required)

#### 2.3 Get Credentials

From the application details page, copy:
- **App ID** (Client ID)
- **App Secret** (Client Secret)
- **Issuer Endpoint** (e.g., `https://your-tenant.click2run.app/oidc`)

### 3. Configure Environment Variables

Edit your `.env` file:

```bash
# Click2Run Auth OpenID Connect Configuration
CLICK2RUN_ENDPOINT=https://your-tenant.click2run.app/oidc
CLICK2RUN_CLIENT_ID=your_app_id_from_click2run
CLICK2RUN_CLIENT_SECRET=your_app_secret_from_click2run
```

**Important:**
- `CLICK2RUN_ENDPOINT` should end with `/oidc` (the OpenID Connect issuer URL)
- Keep `CLICK2RUN_CLIENT_SECRET` secure and never commit it to version control

### 4. Restart Application

```bash
# If using overmind
overmind start -f Procfile.dev

# Or if running manually
rails server
pnpm dev
```

---

## How It Works

### User Flow

1. **User clicks "Login with Click2Run Auth"** on `/app/login`
2. **Browser redirects** to `/auth/click2run` (OmniAuth route)
3. **OmniAuth redirects** to Click2Run Auth authorization endpoint
4. **User authenticates** at Click2Run Auth (email/password, MFA, SSO, etc.)
5. **Click2Run Auth redirects back** to `/omniauth/click2run/callback` with authorization code
6. **OmniAuth exchanges** code for tokens
7. **Callback controller** (`DeviseOverrides::OmniauthCallbacksController`) processes:
   - **Existing user**: Signs in with SSO token
   - **New user**: Creates account (if signup enabled) and prompts password setup
8. **User redirected** to dashboard or login page with SSO token

### Authentication Data Flow

```ruby
# OmniAuth provides auth_hash:
{
  "provider" => "click2run",
  "uid" => "user_id_from_click2run",
  "info" => {
    "name" => "John Doe",
    "email" => "john@example.com",
    "email_verified" => true,
    "image" => "https://..."
  },
  "credentials" => {
    "token" => "access_token",
    "refresh_token" => "refresh_token",
    "expires_at" => 1234567890
  }
}
```

The callback controller uses this data to:
- Find or create user by email
- Set user name and avatar
- Generate SSO auth token for session
- Redirect to login page with token

---

## Configuration Options

### OmniAuth Click2Run Auth Provider

Located in `config/initializers/omniauth.rb`:

```ruby
provider :openid_connect, {
  name: :click2run,
  issuer: ENV.fetch('CLICK2RUN_ENDPOINT'),
  discovery: true,
  scope: [:openid, :profile, :email],
  response_type: :code,
  client_options: {
    identifier: ENV.fetch('CLICK2RUN_CLIENT_ID'),
    secret: ENV.fetch('CLICK2RUN_CLIENT_SECRET'),
    redirect_uri: "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/omniauth/click2run/callback"
  }
}
```

**Options explained:**
- `name: :click2run` - OmniAuth provider name (creates `/auth/click2run` route)
- `issuer` - Click2Run Auth OIDC issuer URL (enables discovery)
- `discovery: true` - Auto-discover endpoints from `/.well-known/openid-configuration`
- `scope` - Requested scopes (openid, profile, email)
- `response_type: :code` - Authorization code flow (server-side)
- `redirect_uri` - Where Click2Run Auth redirects after authentication

### Conditional Loading

The provider is only loaded if environment variables are set:

```ruby
if ENV['CLICK2RUN_ENDPOINT'].present? && ENV['CLICK2RUN_CLIENT_ID'].present?
  # ... provider configuration
end
```

This allows deploying without Click2Run Auth configuration in environments where it's not needed.

---

## Testing

### Manual Testing Checklist

- [ ] **New user registration**
  1. User doesn't exist in Chatwoot
  2. Click "Login with Click2Run Auth"
  3. Authenticate at Click2Run Auth
  4. Should create account and prompt for password setup
  5. Complete password setup
  6. Should be signed in

- [ ] **Existing user login**
  1. User exists in Chatwoot
  2. Click "Login with Click2Run Auth"
  3. Authenticate at Click2Run Auth
  4. Should be signed in immediately

- [ ] **Failed authentication**
  1. Cancel at Click2Run Auth login page
  2. Should return to Chatwoot login with error message

- [ ] **Invalid credentials**
  1. Use wrong credentials at Click2Run Auth
  2. Should show Click2Run Auth error page
  3. Should be able to retry

### Test Click2Run Auth Configuration

Verify OpenID Connect discovery endpoint:

```bash
curl https://your-tenant.click2run.app/oidc/.well-known/openid-configuration
```

Should return JSON with:
- `issuer`
- `authorization_endpoint`
- `token_endpoint`
- `userinfo_endpoint`
- `jwks_uri`

### Debug OAuth Flow

Enable OmniAuth developer mode in development:

```ruby
# config/environments/development.rb
OmniAuth.config.logger = Rails.logger
```

Check logs for OAuth flow details:
```bash
tail -f log/development.log | grep -i omniauth
```

---

## Troubleshooting

### Issue: "Login with Click2Run Auth" button doesn't appear

**Cause:** `CLICK2RUN_CLIENT_ID` not set or not exposed to frontend

**Solution:**
1. Check `.env` has `CLICK2RUN_CLIENT_ID=...`
2. Restart Rails server
3. Check browser console: `window.chatwootConfig.click2runClientId`
4. Should not be empty or undefined

### Issue: Redirect URI mismatch error

**Cause:** Redirect URI in Click2Run Auth doesn't match actual callback URL

**Solution:**
1. Go to Click2Run Auth Console → Application → Settings
2. Add redirect URI exactly as shown in error
3. Common values:
   - Dev: `http://localhost:3000/omniauth/click2run/callback`
   - Prod: `https://your-domain.com/omniauth/click2run/callback`
4. Note: Must use same protocol (http vs https)

### Issue: Invalid client or client authentication failed

**Cause:** Wrong `CLICK2RUN_CLIENT_ID` or `CLICK2RUN_CLIENT_SECRET`

**Solution:**
1. Verify credentials in Click2Run Auth Console
2. Copy exactly (no extra spaces)
3. Check if app secret was regenerated
4. Restart Rails server after changing `.env`

### Issue: User created but no account assigned

**Cause:** `ENABLE_ACCOUNT_SIGNUP` is disabled or business email validation failed

**Solution:**
1. Check `.env`: `ENABLE_ACCOUNT_SIGNUP=true`
2. Ensure email is not from blocked domain (like gmail.com)
3. Check logs for validation errors

### Issue: Discovery failed error

**Cause:** `CLICK2RUN_ENDPOINT` is incorrect or Click2Run Auth is unreachable

**Solution:**
1. Verify endpoint URL (should end with `/oidc`)
2. Test discovery URL: `curl https://your-tenant.click2run.app/oidc/.well-known/openid-configuration`
3. Check network/firewall settings
4. Verify Click2Run Auth tenant is active

---

## Security Considerations

### Client Secret Protection

- ✅ Client secret stored in environment variable (not in code)
- ✅ Only backend has access to secret
- ✅ Frontend only receives public client ID
- ✅ Secret not included in frontend bundle

### Token Handling

- ✅ Authorization code flow (server-side)
- ✅ Tokens exchanged on backend
- ✅ Access token not exposed to frontend
- ✅ Session managed by Devise (server-side)

### Callback Security

- ✅ State parameter handled by OmniAuth (CSRF protection)
- ✅ Callback route requires valid OAuth response
- ✅ Token validation before user creation
- ✅ Email verification checked from Click2Run Auth

### Best Practices

1. **Use HTTPS in production** - Required for OAuth2
2. **Rotate secrets regularly** - Update `CLICK2RUN_CLIENT_SECRET` periodically
3. **Restrict redirect URIs** - Only add necessary callback URLs in Click2Run Auth
4. **Monitor failed logins** - Check logs for suspicious activity
5. **Enable MFA in Click2Run Auth** - Additional security layer for users

---

## Future Enhancements

### Phase 2 Features (Not Implemented Yet)

1. **Organization/Account Mapping**
   - Map Click2Run Auth organizations to Chatwoot accounts
   - Sync organization membership
   - Role mapping (owner → administrator, member → agent)

2. **Profile Synchronization**
   - Auto-update user profile when changed in Click2Run Auth
   - Sync avatar, name, email changes
   - Webhook integration for real-time updates

3. **Role Synchronization**
   - Map Click2Run Auth organization roles to Chatwoot roles
   - Update permissions when role changes in Click2Run Auth

4. **Machine-to-Machine Integration**
   - Use Click2Run Auth M2M tokens for API access
   - Automated user provisioning
   - Periodic sync jobs

5. **Advanced Features**
   - Logout from Click2Run Auth when logging out of Chatwoot
   - Token refresh handling
   - Multi-tenant support with organization selector

---

## Support & Resources

### Click2Run Auth Documentation

- **Click2Run Auth Docs**: https://docs.click2run.io/
- **OpenID Connect Spec**: https://openid.net/specs/openid-connect-core-1_0.html
- **OmniAuth OpenID Connect**: https://github.com/omniauth/omniauth_openid_connect

### Chatwoot OAuth Implementation

- **Google OAuth**: Reference implementation in same codebase
- **OmniAuth Config**: `config/initializers/omniauth.rb`
- **Callback Controller**: `app/controllers/devise_overrides/omniauth_callbacks_controller.rb`

### Getting Help

- **Click2Run Auth Discord**: https://discord.gg/UEPaF3j5e6
- **Chatwoot Docs**: https://www.chatwoot.com/docs/

---

## Deployment Checklist

### Pre-Deployment

- [ ] `bundle install` completed
- [ ] `pnpm install` completed
- [ ] Environment variables configured in `.env`
- [ ] Click2Run Auth application created and configured
- [ ] Redirect URIs added for production domain
- [ ] Application tested locally

### Production Deployment

1. **Set environment variables** on production server:
   ```bash
   CLICK2RUN_ENDPOINT=https://your-tenant.click2run.app/oidc
   CLICK2RUN_CLIENT_ID=your_production_app_id
   CLICK2RUN_CLIENT_SECRET=your_production_app_secret
   ```

2. **Add redirect URI** in Click2Run Auth:
   - `https://your-production-domain.com/omniauth/click2run/callback`

3. **Deploy code**:
   ```bash
   git push production codi-click2run:main
   ```

4. **Restart application**

5. **Verify deployment**:
   - Check "Login with Click2Run Auth" button appears
   - Test login flow with test user
   - Check logs for errors

### Post-Deployment

- [ ] Test login with existing user
- [ ] Test signup with new user (if enabled)
- [ ] Monitor error logs for OAuth failures
- [ ] Verify user profiles synced correctly
- [ ] Test from multiple browsers/devices

---

## Maintenance

### Monitoring

Watch for:
- Failed OAuth authentication attempts
- Invalid client errors (indicates secret issue)
- Redirect URI mismatch errors (indicates configuration issue)
- Discovery failures (indicates Click2Run Auth connectivity issue)

### Regular Tasks

- **Weekly**: Review error logs for OAuth failures
- **Monthly**: Check Click2Run Auth application settings for changes
- **Quarterly**: Review and update redirect URIs if domains change
- **Yearly**: Rotate `CLICK2RUN_CLIENT_SECRET`

---

## Rollback Plan

If issues occur after deployment:

### Quick Rollback

Remove environment variables:
```bash
unset CLICK2RUN_ENDPOINT
unset CLICK2RUN_CLIENT_ID
unset CLICK2RUN_CLIENT_SECRET
```

Restart application. Click2Run Auth button will not appear (conditional loading).

### Full Rollback

```bash
git revert <commit-hash>
git push production main
```

Users can still login with email/password (unchanged).

---

## Conclusion

This implementation provides a minimal, maintainable Click2Run Auth integration following Chatwoot's established OAuth patterns. The approach:

✅ Minimal code changes (~75 lines)
✅ Leverages existing infrastructure
✅ Compatible with upstream updates
✅ Easy to maintain and debug
✅ Secure by design
✅ Well documented

Total implementation time: ~2 hours
Maintenance burden: Low (standard OAuth)

For questions or issues, refer to the troubleshooting section or consult Click2Run Auth documentation.
