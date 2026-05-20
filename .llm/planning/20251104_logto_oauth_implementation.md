---
Created: 2025-11-04T00:00:00Z
Operation: Logto OAuth Implementation Plan
Context: Implementing Logto as OpenID Connect provider following Google OAuth pattern
Related Files:
  - config/initializers/omniauth.rb
  - app/controllers/devise_overrides/omniauth_callbacks_controller.rb
  - app/javascript/v3/views/login/Index.vue
---

# Logto OAuth Implementation - Simplified Approach

## Analysis: Google OAuth Pattern in Chatwoot

After analyzing the codebase, Chatwoot uses **OmniAuth** with **Devise** for Google OAuth authentication:

### Backend Flow:
1. **OmniAuth Strategy** - Defined in `config/initializers/omniauth.rb`:
   - Uses `omniauth-google-oauth2` gem
   - Configured with `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET`
   - Full host set to `FRONTEND_URL` for callback handling

2. **Callback Controller** - `devise_overrides/omniauth_callbacks_controller.rb`:
   - Inherits from `DeviseTokenAuth::OmniauthCallbacksController`
   - Handles the OAuth callback after Google authentication
   - Creates user account or signs in existing user
   - Uses SSO auth token for session creation
   - Redirects to login page with token

3. **User Flow**:
   - User exists → Sign in with SSO token
   - User doesn't exist → Create account (if signup allowed) → Set password

### Frontend Flow:
1. **GoogleOAuthButton** - `app/javascript/v3/components/GoogleOauth/Button.vue`:
   - Constructs OAuth URL manually (to avoid devise-token-auth redirect issue)
   - Uses `window.chatwootConfig.googleOAuthClientId` and callback URL
   - Redirects to Google's authorization endpoint

2. **Login Page** - `app/javascript/v3/views/login/Index.vue`:
   - Shows GoogleOAuthButton if `googleOAuthClientId` is configured
   - Handles SSO auth token from URL params on return
   - Auto-submits login with SSO token

## Logto Implementation Plan (Following Google Pattern)

### Phase 1: Backend Configuration

#### 1.1 Add OmniAuth Logto Strategy
**File**: `config/initializers/omniauth.rb`

Add Logto provider configuration:
```ruby
provider :openid_connect, {
  name: :logto,
  issuer: ENV.fetch('LOGTO_ENDPOINT', nil),
  discovery: true,
  client_auth_method: 'client_secret_basic',
  scope: [:openid, :profile, :email],
  client_options: {
    identifier: ENV.fetch('LOGTO_CLIENT_ID', nil),
    secret: ENV.fetch('LOGTO_CLIENT_SECRET', nil),
    redirect_uri: "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/omniauth/logto/callback"
  }
}
```

**Dependencies**:
- `omniauth-openid-connect` gem (check if already in Gemfile, add if needed)

#### 1.2 Environment Variables
**File**: `.env.example`

Add:
```bash
# Logto OpenID Connect Configuration
LOGTO_ENDPOINT=https://your-tenant.logto.app/oidc
LOGTO_CLIENT_ID=your_logto_application_id
LOGTO_CLIENT_SECRET=your_logto_application_secret
```

### Phase 2: Frontend Components

#### 2.1 Create LogtoOAuthButton Component
**File**: `app/javascript/v3/components/LogtoOauth/Button.vue`

Create similar to GoogleOAuthButton:
```vue
<script>
export default {
  methods: {
    getLogtoAuthUrl() {
      // Use /auth/logto route provided by OmniAuth
      return '/auth/logto';
    },
  },
};
</script>

<template>
  <div class="flex flex-col">
    <a
      :href="getLogtoAuthUrl()"
      class="inline-flex justify-center w-full px-4 py-3 bg-n-background dark:bg-n-solid-3 items-center rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
    >
      <span class="i-lucide-shield-check h-6 w-6 text-n-brand" />
      <span class="ml-2 text-base font-medium text-n-slate-12">
        {{ $t('LOGIN.OAUTH.LOGTO_LOGIN') }}
      </span>
    </a>
  </div>
</template>
```

#### 2.2 Update Login Page
**File**: `app/javascript/v3/views/login/Index.vue`

- Import LogtoOAuthButton
- Add computed property `showLogtoOAuth()`
- Add button above/below Google button

### Phase 3: Configuration & Testing

#### 3.1 Logto Application Setup
In Logto Console:
1. Create Traditional Web Application
2. Set redirect URI: `http://localhost:3000/omniauth/logto/callback` (dev)
3. Enable scopes: `openid`, `profile`, `email`
4. Copy Client ID and Secret to `.env`

#### 3.2 Backend Configuration Service
**File**: `app/controllers/super_admin/app_configs_controller.rb`

Add Logto config keys to expose to frontend (similar to Google):
- `LOGTO_CLIENT_ID` (public, safe to expose)

#### 3.3 Frontend Config
Expose in `window.chatwootConfig`:
- `logtoClientId`

### Phase 4: I18n

Add translation keys:
- `LOGIN.OAUTH.LOGTO_LOGIN` - "Sign in with Logto"

## Key Differences from Original Plan

### Simplified Approach:
1. **No custom Devise strategy** - Use OmniAuth's OpenID Connect strategy
2. **No JWT validation** - OmniAuth handles token exchange and validation
3. **No organization sync initially** - Focus on basic authentication first
4. **Reuse existing callback controller** - `DeviseOverrides::OmniauthCallbacksController` handles all OAuth providers

### Benefits:
- ~50 lines of code vs. ~450 lines
- No custom authentication logic
- Leverages existing OAuth infrastructure
- Faster implementation (1-2 days vs. 4-6 weeks)
- Less maintenance burden

### Limitations:
- No automatic organization/role sync (can be added later)
- No webhook integration initially
- Relies on Chatwoot's existing user model

## Implementation Order:

1. ✅ Analyze Google OAuth pattern (DONE)
2. Add `omniauth-openid-connect` gem (if needed)
3. Configure OmniAuth Logto provider
4. Add environment variables
5. Create LogtoOAuthButton component
6. Update login page
7. Add i18n keys
8. Configure Logto application
9. Test OAuth flow

## Testing Checklist:
- [ ] User can click "Sign in with Logto" button
- [ ] Redirects to Logto authorization page
- [ ] After successful authentication, redirects back to Chatwoot
- [ ] New user: Account created, password reset flow triggered
- [ ] Existing user: Signed in with SSO token
- [ ] Error handling: Shows appropriate error messages

## Future Enhancements (Phase 2):
- Organization/Account mapping
- Role synchronization
- Webhook integration
- Profile sync

## Notes:
- This approach treats Logto as just another OAuth provider (like Google)
- Keeps changes minimal and aligned with Chatwoot's architecture
- Easy to maintain and extend
- Compatible with upstream Chatwoot updates
