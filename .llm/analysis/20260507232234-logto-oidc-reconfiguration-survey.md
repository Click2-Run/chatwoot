---
Created: 2026-05-07T23:22:34Z
Operation: Survey of Logto/Click2Run OIDC wiring and reconfiguration recipe (Phase 5a prep)
Context: User clarified Logto is the primary IdP (not dormant). Reconfiguration is gated on tenant credentials; this doc spec's exactly what's needed and how the cascade works so the actual switch becomes a 5-minute env-var change.
Related Files:
  - config/initializers/omniauth.rb
  - app/controllers/devise_overrides/omniauth_callbacks_controller.rb
  - app/javascript/v3/components/Click2RunOpenid/Button.vue
  - app/views/layouts/vueapp.html.erb
  - .codi/CLICK2RUN_OPENID_INTEGRATION.md
  - .codi/CLICK2RUN_OPENID_SETUP.md
  - CUSTOM_AUTH.md
---

# Logto / Click2Run OIDC Reconfiguration Survey

## Architecture summary

**Click2Run OpenID and Logto are the same OmniAuth provider** — the registered provider name is always `:click2run`, and every env var has a cascading fallback through both naming schemes. The user already standardised on Click2Run names as the canonical surface, with Logto names left as backwards-compatible aliases. Reconfiguring "Logto" means setting either set of variables to the current tenant.

```
OmniAuth provider registered as :click2run  (always)
    ↓
Login button label: configurable, defaults to i18n LOGIN.OAUTH.CLICK2RUN_LOGIN
    ↓
Devise omniauth callback: /omniauth/click2run/callback
    ↓
DeviseOverrides::OmniauthCallbacksController
    ↓ trusted_oauth_provider? → ['click2run'] → skip email domain validation
    ↓ should_sync_oauth_profile? → CLICK2RUN_OPENID_ALWAYS_SYNC
    ↓
Sign in / create user
```

## Env-var cascade (config/initializers/omniauth.rb:12-15)

| Logical setting | First match wins | Default |
|---|---|---|
| Issuer URL | `CLICK2RUN_OPENID_ISSUER` → `LOGTO_ISSUER` → `LOGTO_ENDPOINT` | (none — provider not registered if absent) |
| Client ID | `CLICK2RUN_OPENID_APP_ID` → `LOGTO_APP_ID` → `LOGTO_CLIENT_ID` | (none — provider not registered if absent) |
| Client Secret | `CLICK2RUN_OPENID_APP_SECRET` → `LOGTO_APP_SECRET` → `LOGTO_CLIENT_SECRET` | (empty) |
| Scopes | `CLICK2RUN_OPENID_SCOPES` → `LOGTO_SCOPES` | `"openid profile email"` |
| Button label | `CLICK2RUN_OPENID_LABEL` → `LOGTO_LABEL` (vueapp.html.erb:43) | i18n key `LOGIN.OAUTH.CLICK2RUN_LOGIN` |
| Auto-redirect to OIDC | `CLICK2RUN_OPENID_LOGIN_REDIRECT` (no LOGTO alias) | `false` |
| Profile sync on every login | `CLICK2RUN_OPENID_ALWAYS_SYNC` (no LOGTO alias) | `true` |
| Redirect URI | derived: `${FRONTEND_URL}/omniauth/click2run/callback` | `https://localhost:3000/omniauth/click2run/callback` if `FRONTEND_URL` unset |

## What needs to come from the user (the actual blocker)

To switch Logto from "dormant test config" to "this project's real IdP", the following values are required:

1. **Logto issuer URL** — the OIDC discovery endpoint for the target Logto tenant.
   Typically of the form `https://<tenant>.logto.app/oidc` or `https://auth.<your-domain>/oidc` for self-hosted.
2. **Logto application ID** (client ID).
3. **Logto application secret** (client secret).
4. **Login button label** — what users should see. Examples: "Login with Controle Digital", "Login with Propria Cloud".
5. **Auto-redirect on landing** — should guests be sent straight to Logto without seeing the form? (`true`/`false`)
6. **Scopes** — keep default `openid profile email` or add Logto-specific extras (`phone`, `address`, `custom_data`, `identities`, `organizations`, `organization_roles`)?
7. **Production FRONTEND_URL** — needed to compute the callback URI Logto must register.

## What needs to be configured on the Logto side

Inside the Logto admin console, on the application registered for this Chatwoot deployment:

- **Redirect URIs** must include exactly: `${FRONTEND_URL}/omniauth/click2run/callback`
  (`https://localhost:3000/omniauth/click2run/callback` for local dev).
- **Sign-out URIs** (optional): `${FRONTEND_URL}/auth/sign_out`.
- **CORS allowed origins**: `${FRONTEND_URL}` if Logto uses front-channel calls.
- **Token endpoint authentication method**: client secret post or basic — both work.
- **Application type**: traditional web app.
- **Profile claims**: must include `email`, `name`, `picture` for sync to work (sync_profile_from_oauth uses these — see omniauth_callbacks_controller.rb:159-167).

## Reconfiguration recipe (once values are provided)

Two files only — no code change required.

### `.env` (gitignored — local dev)

Replace the existing `CLICK2RUN_OPENID_*` block with the real values:

```bash
CLICK2RUN_OPENID_ISSUER=<logto issuer url>
CLICK2RUN_OPENID_APP_ID=<logto app id>
CLICK2RUN_OPENID_APP_SECRET=<logto app secret>
CLICK2RUN_OPENID_LABEL=<button label, e.g. "Login with Propria Cloud">
CLICK2RUN_OPENID_SCOPES=openid profile email
CLICK2RUN_OPENID_LOGIN_REDIRECT=true   # or false to keep showing the form
CLICK2RUN_OPENID_ALWAYS_SYNC=true
AUTH_DISABLE_DEFAULT=true              # if Logto-only deployment
AUTH_SUPERADMIN_SAME_SESSION=true      # if SuperAdmins authenticate via Logto
ENABLE_ACCOUNT_SIGNUP=true             # required to allow first-time Logto user creation
```

### `.env.example` (committed)

Already documents these keys with safe defaults. The placeholder issuer
(`https://your-tenant.click2.run/oidc`) is fine for the example file —
real values stay in `.env` only.

### Production / Coolify

In Coolify (`docker-compose.coolify.yaml` already references `${...}` env vars), set the same variables as Coolify environment values. No file change in the repo.

### Verification (Docker required)

```bash
docker compose up -d
docker compose exec rails rails runner "puts OmniAuth.config.builder.options"  # confirm :click2run registered
```

Then:

1. Navigate to `https://localhost:3000` (Caddy)
2. Confirm Click2Run/Logto button visible (with the configured label)
3. Click → redirected to Logto consent screen → enter creds → returned to Chatwoot dashboard
4. In Rails console: `User.last.provider` should be `"click2run"`, and `provider_uid` should be the Logto user ID
5. Toggle `CLICK2RUN_OPENID_LOGIN_REDIRECT=true` and reload the login page — should auto-redirect to Logto

## Affected code surface (already wired, nothing to change)

| File | Role |
|---|---|
| `config/initializers/omniauth.rb:5-32` | Registers `:click2run` OmniAuth provider with discovery |
| `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` | Handles `/omniauth/click2run/callback`; trusts the provider; syncs profile |
| `app/javascript/v3/components/Click2RunOpenid/Button.vue` | Login button — uses `window.chatwootConfig.click2runOpenidLabel` or i18n fallback |
| `app/javascript/v3/views/login/Index.vue` | Conditional render via `showClick2RunOpenid` (truthy `click2runOpenidAppId`); auto-redirect via `click2runOpenidLoginRedirect` (mounted hook) |
| `app/views/layouts/vueapp.html.erb:42-44` | Pipes the four runtime configs into `window.chatwootConfig` |
| `app/controllers/devise_overrides/sessions_controller.rb` | `check_default_auth_disabled` 403s email/password if `AUTH_DISABLE_DEFAULT=true` |
| `app/controllers/devise_overrides/passwords_controller.rb` | Same for password reset |
| `app/controllers/api/v1/accounts_controller.rb` | Same for signup endpoint |
| `app/controllers/super_admin/application_controller.rb` | `AUTH_SUPERADMIN_SAME_SESSION` reuse path |

## Open questions for the user (the blocker)

1. **Logto issuer URL** — what is it? (Logto cloud tenant or self-hosted?)
2. **Logto app ID + secret** — provide these (not for committal — only for `.env` and Coolify environment).
3. **Button label** — final wording for the OIDC button.
4. **Auto-redirect** — should the login page auto-forward to Logto, or keep the form visible?
5. **AUTH_DISABLE_DEFAULT** — go full Logto-only (true) or hybrid form-+-Logto (false)?
6. **AUTH_SUPERADMIN_SAME_SESSION** — should Logto SuperAdmins skip the second password gate?
7. **Production FRONTEND_URL** — to register the correct redirect URI in Logto.

Once these are provided, the reconfiguration is a `.env` edit + `docker compose restart rails` away.

## Note on the rebrand path

If the user wants the OIDC button branded as "Propria Cloud" without code changes, that is achievable today via `CLICK2RUN_OPENID_LABEL="Login with Propria Cloud"`. The OmniAuth provider name itself stays `:click2run` because changing it would invalidate existing user provider_uid links — keep that even after the rebrand. Phase 5c would only need to consider whether the `Click2RunOpenid` Vue namespace and the `click2run` provider name should also rename, which is a much larger code change with no functional benefit.
