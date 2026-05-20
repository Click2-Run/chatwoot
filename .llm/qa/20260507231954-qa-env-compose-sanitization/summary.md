---
Created: 2026-05-07T23:19:54Z
Feature: Post-upgrade env files and docker-compose sanitization (Phase 3a)
Total Cycles: 1
Final Status: PASS (with one local-only fix applied)
---

## Result

PASS — all customisation env vars and docker-compose customisations are intact after the fazer-ai v4.9.0-fazer-ai.13 upgrade. One trivial local-only drift fixed in `.env` (no commit — `.env` is gitignored, as it should be).

## Inventory at HEAD

### `.env.example` (committed, source of truth)

- v4.9.0-fazer-ai.13: 63 unique env keys
- HEAD: 80 unique env keys
- **Net delta**: +17 keys, 0 keys lost

### Our 17 customisation keys preserved

| Key | Purpose |
|---|---|
| `AUTH_DISABLE_DEFAULT` | gate default email/password auth (CUSTOM_AUTH.md) |
| `AUTH_SUPERADMIN_SAME_SESSION` | reuse OIDC session for SuperAdmin (CUSTOM_AUTH.md) |
| `CLICK2RUN_OPENID_ISSUER` | OIDC issuer URL |
| `CLICK2RUN_OPENID_APP_ID` | OAuth client ID (cascades to LOGTO_APP_ID/CLIENT_ID) |
| `CLICK2RUN_OPENID_APP_SECRET` | OAuth client secret |
| `CLICK2RUN_OPENID_LABEL` | login button label override (cascades to LOGTO_LABEL) |
| `CLICK2RUN_OPENID_LOGIN_REDIRECT` | auto-redirect to OIDC on login page |
| `CLICK2RUN_OPENID_SCOPES` | OAuth scopes |
| `CLICK2RUN_OPENID_ALWAYS_SYNC` | sync profile on every login |
| `CLICK2RUN_PROVIDER_DEFAULT_API_KEY` | Click2Run WhatsApp provider key |
| `CLICK2RUN_PROVIDER_DEFAULT_URL` | Click2Run WhatsApp provider URL |
| `WHATSAPP_API_VERSION` | upstream Chatwoot Cloud API |
| `WHATSAPP_APP_ID` | upstream Chatwoot Cloud API |
| `WHATSAPP_APP_SECRET` | upstream Chatwoot Cloud API |
| `WHATSAPP_CONFIGURATION_ID` | upstream Chatwoot Cloud API |
| `WHATSMEOW_PROVIDER_DEFAULT_API_KEY` | Whatsmeow provider key |
| `WHATSMEOW_PROVIDER_DEFAULT_URL` | Whatsmeow provider URL |

Note: the four `WHATSAPP_*` keys are referenced by upstream code (`facebook_api_client.rb`, `health_service.rb`, `vueapp.html.erb`) and `config/installation_config.yml`; fazer-ai's `.env.example` happens to omit them but our codi `.env.example` documents them with safe empty defaults — keep.

### `.env` (gitignored, local dev)

Mirroring check vs `.env.example`:
- Initial drift: `.env` was missing `ACTION_MAILBOX_SES_SNS_TOPIC` (a Chatwoot SES setting). **Fixed in this session** — added with empty default and the same comment block as `.env.example`. No commit (file is gitignored).
- `.env` correctly carries `DISABLE_ENTERPRISE=true` (intentional local OSS-mode toggle); `.env.example` documents it as a commented hint at line 37 — acceptable.

### docker-compose files

| File | vs v4.9.13 | Status |
|---|---|---|
| `docker-compose.coolify.yaml` | identical | mirror intact |
| `docker-compose.production.yaml` | 1 line change | `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}` env-var override (ours) |
| `docker-compose.test.yaml` | 1 line change | `POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}` (ours) |
| `docker-compose.yaml` | 57-line dev override | All Click2Run dev customisations intact: `click2run/chatwoot*` image overrides, Caddy reverse proxy service + volumes, `git_bundler_cache` volume, `pnpm_store` volume, `HUSKY=0` env, ports for postgres/redis closed (Caddy fronts), Caddyfile mount, Caddy ports `3000` |

### Click2Run-customisation usage in code (corroboration)

| Source | Line | Keys used |
|---|---|---|
| `app/views/layouts/vueapp.html.erb` | 41-44 | `CLICK2RUN_OPENID_APP_ID` (with LOGTO_APP_ID/LOGTO_CLIENT_ID fallback), `CLICK2RUN_OPENID_LABEL` (with LOGTO_LABEL fallback), `CLICK2RUN_OPENID_LOGIN_REDIRECT` |
| `app/services/whatsapp/facebook_api_client.rb` | 13-14, 95-96 | `WHATSAPP_APP_ID`, `WHATSAPP_APP_SECRET` |
| `app/services/whatsapp/health_service.rb` | 7 | `WHATSAPP_API_VERSION` |
| `lib/chatwoot_app.rb` | 15 | `DISABLE_ENTERPRISE` |
| `config/initializers/mailer.rb` | 58 | `ACTION_MAILBOX_SES_SNS_TOPIC` |

## Issues Found and Fixed

| Issue | Impact | Resolution |
|---|---|---|
| `.env` missing `ACTION_MAILBOX_SES_SNS_TOPIC` | local-only — would have produced no error since the initializer guards with `.present?` | Added empty entry to `.env` to match `.env.example` order |

## Final Verification Checklist

- [x] `.env.example` retains all 17 customisation keys (no losses on upgrade)
- [x] All 4 `WHATSAPP_*` upstream Cloud-API keys present in our `.env.example` (fazer-ai ships them in code/installation_config.yml only)
- [x] `.env` mirrors `.env.example` after the SES topic fix
- [x] `docker-compose.coolify.yaml` matches fazer-ai exactly (no drift)
- [x] `docker-compose.{production,test}.yaml` only differ on `POSTGRES_PASSWORD` env-var override — intentional
- [x] `docker-compose.yaml` Caddy service + click2run images + volume customisations all intact
- [x] No undocumented env vars in `.env` (apart from the local `DISABLE_ENTERPRISE=true` — documented as commented hint in `.env.example`)
