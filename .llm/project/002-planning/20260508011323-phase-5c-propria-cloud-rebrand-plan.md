---
Created: 2026-05-08T01:13:23Z
Operation: Phase 5c — Click2Run → Propria Cloud rebrand plan (env-driven first, code-namespace optional)
Context: User intent is to migrate the user-facing brand from "Click2Run" to "Propria Cloud" while preserving working integrations. Three layers exist: env-driven UI strings (zero risk), Docker image names (deploy-coupled), and code namespaces (high churn, no functional benefit). Plan separates them so the safe layer can ship anytime and the deeper layers stay opt-in.
Related Files:
  - lib/tasks/branding.rake (defines the BRAND_* / INSTALLATION_NAME / LOGO_* env-var contract)
  - CUSTOM_BRANDING.md (existing branding docs, fazer-ai source)
  - .env.example, .env (where env values land)
  - app/javascript/v3/components/Click2RunOpenid/Button.vue (label rendered from CLICK2RUN_OPENID_LABEL)
  - docker-compose.yaml (image: click2run/chatwoot* — deploy concern)
  - app/services/whatsapp/providers/whatsapp_click2run_service.rb (provider class name; OmniAuth :click2run name; provider_uid links)
  - app/services/whatsapp/click2run_handlers/* (provider name in code paths)
---

# Phase 5c — Click2Run → Propria Cloud rebrand

## Three layers, three risk profiles

| Layer | Surface | Risk | When |
|---|---|---|---|
| **5c.1 — Env-driven UI** | Installation name, logos, brand URLs, OIDC button label, manifest, emails | Zero — env vars only, fully reversible | Anytime |
| **5c.2 — Docker / deployment** | `click2run/chatwoot*` image tags in docker-compose, ghcr image namespace | Medium — coupled to image registry & CI | When ready to publish under new namespace |
| **5c.3 — Code namespaces** | OmniAuth provider name `:click2run`, Vue dir `Click2RunOpenid/`, class `WhatsappClick2RunService`, feature-flag `CHANNEL_WHATSAPP_CLICK2RUN`, provider string `'click2run'` | High — breaks existing user provider_uid links, requires migration | Only if there is a real need |

**Recommendation**: ship 5c.1, defer 5c.2 indefinitely (cosmetic), do **NOT** ship 5c.3 unless there is a concrete reason.

## 5c.1 — Env-driven UI rebrand (zero-risk)

### Variables to set (in `.env` and Coolify production env — not committed)

```bash
# Installation-wide
INSTALLATION_NAME="Propria Cloud"

# Brand pipeline (consumed by `bundle exec rails branding:update`)
BRAND_NAME="Propria Cloud"
BRAND_URL="https://propria.cloud"
WIDGET_BRAND_URL="https://propria.cloud"
TERMS_URL="https://propria.cloud/terms"
PRIVACY_URL="https://propria.cloud/privacy"
LOGO=/brand-assets/logo.svg
LOGO_DARK=/brand-assets/logo_dark.svg
LOGO_THUMBNAIL=/brand-assets/logo_thumbnail.svg
DISPLAY_MANIFEST=false      # hide default Chatwoot metadata (favicon, upgrade banner)

# Asset bundle (extracted on container start by docker-compose.coolify.yaml post_start)
BRAND_ASSETS_URL=https://assets.propria.cloud/chatwoot-brand.zip

# OIDC button label (cascades through CLICK2RUN_OPENID_LABEL → LOGTO_LABEL)
CLICK2RUN_OPENID_LABEL="Login with Propria Cloud"
```

### Application

After setting the env, the rake task seeds installation_config rows:

```bash
docker compose exec rails bundle exec rails branding:update
```

That's it for UI rebrand. The dashboard title, login page, emails, and widget all switch.

### Asset bundle

`deployment/extract_brand_assets.sh` already pulls a ZIP from `BRAND_ASSETS_URL` on container post_start. Author the bundle once with the Propria Cloud favicons / logos following the file list in `CUSTOM_BRANDING.md`, host it at the URL, and every restart re-applies.

### What does NOT need a code change for 5c.1
- The OIDC button reads `window.chatwootConfig.click2runOpenidLabel` already (env-driven). Set `CLICK2RUN_OPENID_LABEL="Login with Propria Cloud"` and the button updates.
- `app/views/layouts/vueapp.html.erb:43` cascades `CLICK2RUN_OPENID_LABEL → LOGTO_LABEL` already.
- All `INSTALLATION_NAME`, `BRAND_NAME`, etc. consumers read from `installation_config` populated by the rake task.

### Doc updates
- `CUSTOM_BRANDING.md` — add a "Propria Cloud configuration example" section at the bottom. Keep the rest as the canonical doc.

### Acceptance
- [ ] Set the env vars above in dev `.env`, run the rake task
- [ ] Login page shows "Login with Propria Cloud" and the new logo
- [ ] Browser tab title and dashboard chrome show "Propria Cloud"
- [ ] Outbound emails footer shows "Powered by Propria Cloud" linking to propria.cloud
- [ ] `INSTALLATION_NAME` env override survives a container restart

## 5c.2 — Docker image name rebrand (deferred)

`docker-compose.yaml` currently overrides:
```yaml
image: click2run/chatwoot:development
image: click2run/chatwoot-rails:development
image: click2run/chatwoot-vite:development
```

These are local dev tags — they don't bind to any registry yet. The rebrand is mechanical (sed `click2run/` → `propriacloud/`) but couples to:
- whatever CI publishes images
- your Coolify image references
- `ghcr.io/fazer-ai/chatwoot:latest` (upstream image — keep as-is, it's the base)

**Defer until** a registry namespace exists for `propriacloud/*`. When done:
1. `git grep -lE 'click2run/(chatwoot|chatwoot-rails|chatwoot-vite)' | xargs sed -i 's|click2run/|propriacloud/|g'`
2. Rebuild/republish images under the new tag
3. Update Coolify's image pull config

## 5c.3 — Code-level namespace rename (NOT recommended)

The provider name `:click2run` is referenced in:
- `app/models/channel/whatsapp.rb` PROVIDERS array
- `app/jobs/webhooks/whatsapp_events_job.rb` dispatcher
- `app/services/whatsapp/providers/whatsapp_click2run_service.rb` (class name)
- `app/services/whatsapp/incoming_message_click2run_service.rb`
- `app/services/whatsapp/click2run_handlers/*`
- OmniAuth `:click2run` registration in `config/initializers/omniauth.rb`
- Devise callback URL `/omniauth/click2run/callback`
- Feature flag `CHANNEL_WHATSAPP_CLICK2RUN` in `featureFlags.js` and `config/features.yml`
- Vue dir `app/javascript/v3/components/Click2RunOpenid/`
- I18n key `LOGIN.OAUTH.CLICK2RUN_LOGIN`
- The provider config string `'click2run'` stored in every existing channel's `provider_config`

**Why NOT to rename**:
- All existing `User.provider == 'click2run'` rows have provider_uid linking. Renaming the provider key forces every existing user to re-authenticate as a "new" user — data loss risk.
- The OmniAuth callback URL `/omniauth/click2run/callback` is registered with the IdP (Logto). Renaming requires re-registering callbacks on the IdP.
- Existing WhatsApp channels with `provider: 'click2run'` would need data migration.
- No functional benefit — the user-facing label is already env-driven.

**Decision**: keep `:click2run` as the **internal stable identifier**, branded "Propria Cloud" via labels only. This is the same pattern that lets companies keep an internal codename while the customer-facing brand evolves.

### If you absolutely must rename later

The migration would be:
1. Add new provider strings (`'propria_cloud'`) alongside the old.
2. Code paths support both for one release.
3. Backfill migration: `UPDATE users SET provider = 'propria_cloud' WHERE provider = 'click2run';` plus channel provider_config update.
4. Re-register OAuth callbacks on the IdP.
5. Drop the old `'click2run'` strings.

This is at minimum a multi-week project gated on a database migration. Out of scope unless explicitly required.

## Out of scope
- Top-level repository rename (`Click2-Run/chatwoot` → `propriacloud/chatwoot`) — git-level, owner decision
- Registry namespace migration (`ghcr.io/click2run` → `ghcr.io/propriacloud`)
- Domain-name migration (click2run.com → propria.cloud) — DNS / cert work outside this codebase

## Acceptance for the recommended scope (5c.1 only)

- [x] Plan documented (this file)
- [ ] User picks final `BRAND_NAME` / asset URLs / domains and applies via env vars
- [ ] Run `bundle exec rails branding:update` once values are set
- [ ] Smoke: login page, dashboard chrome, email footer, widget — all show "Propria Cloud"
- [ ] No code change required
