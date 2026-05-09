---
Created: 2025-11-04T19:50:32Z
Operation: Comprehensive analysis of Fazer.AI customizations to Chatwoot
Context: User requested documentation of all fazer-ai modifications compared to upstream Chatwoot
Related Files:
  - /root/data/development/chatwoot.git/docker-compose.coolify.yaml
  - /root/data/development/chatwoot.git/CUSTOM_BRANDING.md
  - /root/data/development/chatwoot.git/lib/tasks/branding.rake
  - /root/data/development/chatwoot.git/deployment/extract_brand_assets.sh
  - /root/data/development/chatwoot.git/.env.example
---

# Fazer.AI Customizations to Chatwoot

## See also

- **`CUSTOM-MERGES-GUIDE.md`** — the end-to-end ritual for fetching /
  merging / syncing the upstream fork. The rebrand table below is one
  step inside that ritual; the guide carries the rest (safety tag →
  branch decision → merge → sweep → smoke test → changelog → tag).

## Rebrand mapping (Própria Cloud) — durable across upstream merges

Every fazer-ai upstream tag we pull will reintroduce `fazer.ai`,
`Click2Run`, and `c2r` strings. The table below is the authoritative
translation rule — apply it when resolving conflicts and when reviewing
post-merge diffs. Anything not listed must be left as-is to avoid
fighting upstream or breaking the docker hub namespace.

| Upstream string                                  | Replace with                                  | Where it appears                                                      |
| :----------------------------------------------- | :-------------------------------------------- | :-------------------------------------------------------------------- |
| `https://fazer.ai`                               | `https://multicanal.propria.cloud`            | Anchor `href`, JS string consts, ERB views                            |
| `https://app.fazer.ai`                           | `https://app.multicanal.propria.cloud`        | Admin app links (e.g. guides URL in `globals.js`)                     |
| `fazer.ai` (visible label)                       | `Própria Cloud` (with accent)                 | Display text only                                                     |
| `fazer.ai` (technical identifier)                | `propriacloud`                                | `X-Platform` header value, `health` JSON `platform` field             |
| `Click2Run` (visible label / logo-alt)           | `Própria Cloud`                               | UI strings, `logo-alt`, comments introducing the product              |
| `click2run` (provider id, env var prefix)        | `propriacloud` (canonical) — keep `click2run` as **legacy alias** | Env-var aliases (`WHATSAPP_API_*`, `PROPRIACLOUD_PROVIDER_DEFAULT_*`, `CLICK2RUN_PROVIDER_DEFAULT_*`) and the `trusted_providers = %w[propriacloud click2run]` list. |
| `c2r`                                            | `ppcloud`                                     | Internal short identifiers in code (rare)                             |
| `https://github.com/fazer-ai/chatwoot/...`       | **Keep as-is**                                | Upstream fork URL — used by `check_new_versions_job`                  |
| Branch names containing `fazer-ai`               | **Keep as-is**                                | Git branch / tag identity                                              |

### Areas explicitly NOT translated

- `docker-compose.yaml` / `Dockerfile` references to `click2run/...`
  image names — that is the docker hub namespace for our image builds.
- `config/features.yml` `channel_whatsapp_click2run` feature flag —
  marked deprecated, kept as a legacy account-toggle slot to avoid
  reshuffling FlagShihTzu bit positions.
- `lib/middleware/fazer_ai_platform_header.rb` filename — only the
  `X-Platform` value inside is updated to `propriacloud`. Renaming
  the file would cascade into `config/application.rb`.
- `lib/global_config_service.rb` and other upstream-owned `lib/`
  files — translate the strings inside, accept everything else.

### Files that recur on every upstream merge

Tag these for explicit attention during conflict resolution:

- `app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue` (release-notes link)
- `app/javascript/dashboard/components/app/UpdateBanner.vue` (release-notes link)
- `app/javascript/dashboard/routes/dashboard/kanban/Index.vue` (upgrade link)
- `app/javascript/dashboard/routes/dashboard/internalChat/ProFeatureNudge.vue` (upgrade link)
- `app/javascript/dashboard/routes/dashboard/settings/account/components/BuildInfo.vue` (footer link)
- `app/javascript/v3/views/login/Index.vue` (footer link)
- `app/javascript/dashboard/i18n/locale/{en,pt_BR}/kanban.json` (paywall copy)
- `app/javascript/dashboard/constants/globals.js` (`PROPRIACLOUD_GUIDES_URL` + back-compat `FAZER_AI_GUIDES_URL` alias)
- `app/views/super_admin/devise/sessions/new.html.erb` (page title)
- `app/controllers/health_controller.rb` (health JSON `platform` field)
- `lib/middleware/fazer_ai_platform_header.rb` (X-Platform header value)
- `lib/tasks/branding.rake` (NOTE comment)

## Overview

This document catalogs all custom modifications made by Fazer.AI to the official Chatwoot open-source customer engagement platform. These customizations represent **87 commits** authored by the Fazer.AI team, primarily focused on WhatsApp integration alternatives, infrastructure-as-code branding, and Brazilian market adaptations.

**Repository Structure**:
- **Upstream**: `https://github.com/chatwoot/chatwoot.git` (official Chatwoot)
- **Fazer.AI Fork**: `https://github.com/fazer-ai/chatwoot.git`
- **Click2-Run Fork**: `https://github.com/Click2-Run/chatwoot.git` (current repository)

---

## 1. WhatsApp Integrations (Primary Focus)

### 1.1 Baileys WhatsApp Integration

**Purpose**: Provides a free, open-source alternative to WhatsApp Cloud API and 360Dialog paid services by integrating with the Baileys library (reverse-engineered WhatsApp Web protocol).

**Key Commits**:
- `c350ba15e` - Initial Baileys implementation
- `99255c199` - Connection health checks
- `2cf1795a3` - Periodic connection monitoring
- `9f5c62c72` - Status endpoint for Baileys API availability
- `a8777f5b0` - LID contact phone number updates
- `e18826287` - Race condition fixes for send/incoming messages
- `548c0351e` - Unread message handling
- `76deea996` - Service refactoring with composition pattern

**Core Features**:
- ✅ Message Types: text, media, documents, voice notes, reactions, vCards
- ✅ Connection Management: QR code auth, auto-reconnection, health checks
- ✅ Read Receipts & Typing Indicators
- ✅ Message Status Tracking: sent → delivered → read
- ✅ Unread Conversation Marking
- ✅ Edited Message Detection with Content History
- ✅ **LID (Linked Device ID) Support** for multi-device WhatsApp
- ✅ CDN-based Media Retrieval
- ✅ Protocol Message Filtering (ignores system messages)

**Environment Variables**:
```bash
BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME=Chatwoot
BAILEYS_PROVIDER_DEFAULT_URL=http://localhost:3025
BAILEYS_PROVIDER_DEFAULT_API_KEY=
BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL=true
```

**Implementation Files**:
```
app/services/whatsapp/providers/whatsapp_baileys_service.rb
app/services/whatsapp/incoming_message_baileys_service.rb
app/helpers/baileys_helper.rb
app/jobs/channels/whatsapp/baileys_connection_check_job.rb
app/jobs/channels/whatsapp/baileys_connection_check_scheduler_job.rb
app/javascript/dashboard/routes/dashboard/settings/inbox/channels/BaileysWhatsapp.vue
spec/services/whatsapp/providers/whatsapp_baileys_service_spec.rb
spec/services/whatsapp/incoming_message_baileys_service_spec.rb
spec/helpers/baileys_helper_spec.rb
```

---

### 1.2 Z-API WhatsApp Integration

**Purpose**: Second alternative WhatsApp provider option, using Z-API service (Brazilian WhatsApp API provider).

**Key Commit**: `4fc80ba4e` - feat(zapi): Z-API integration (#115)

**Features**:
- ✅ Connect flow with QR code authentication
- ✅ Send/receive messages
- ✅ Contact message handling (vCard)
- ✅ LID-only conversation support
- ✅ Notification filtering (ignores system notifications)
- ✅ Reply functionality

**Implementation Files**:
```
app/services/whatsapp/providers/whatsapp_zapi_service.rb
app/services/whatsapp/incoming_message_zapi_service.rb
app/jobs/channels/whatsapp/zapi_qr_code_job.rb
app/javascript/dashboard/routes/dashboard/settings/inbox/channels/ZapiWhatsapp.vue
spec/services/whatsapp/providers/whatsapp_zapi_service_spec.rb
spec/services/whatsapp/incoming_message_zapi_service_spec.rb
```

**Strategic Context**: Provides redundancy and choice for WhatsApp integration, particularly valuable in Brazilian market where Z-API has local presence.

---

### 1.3 WhatsApp Cloud API Enhancements

**Upstream vs Custom**: Official Chatwoot supports WhatsApp Cloud API, but Fazer.AI added advanced features.

**Enhancements**:
- `eaf2f9952` - Typing status and read message support
- `6cd0a3bf7` - Reaction messages and `is_record_audio` metadata for voice
- `0b6d943fa` - Send read receipts for typing indicators

**Why This Matters**: Brings parity between official Cloud API and custom Baileys/Z-API implementations.

---

## 2. Custom Branding System

**Purpose**: Enable white-labeling without Enterprise license through infrastructure-as-code approach.

**Key Commit**: `c350ba15e` - feat: custom branding (#68)

**Implementation**:
1. **Rake Task**: `bundle exec rails branding:update`
2. **Asset Extraction Script**: `deployment/extract_brand_assets.sh`
3. **Environment Variable Configuration**: See table below

**Configurable Branding Elements**:

| Environment Variable | Default Value | Description |
|---------------------|---------------|-------------|
| `INSTALLATION_NAME` | `Chatwoot` | Dashboard/browser title |
| `LOGO_THUMBNAIL` | `/brand-assets/logo_thumbnail.svg` | Favicon (512x512px) |
| `LOGO` | `/brand-assets/logo.svg` | Light mode logo |
| `LOGO_DARK` | `/brand-assets/logo_dark.svg` | Dark mode logo |
| `BRAND_URL` | `https://www.chatwoot.com` | "Powered By" link in emails |
| `WIDGET_BRAND_URL` | `https://www.chatwoot.com` | "Powered By" link in widget |
| `BRAND_NAME` | `Chatwoot` | Name in emails/widget |
| `TERMS_URL` | `https://www.chatwoot.com/terms-of-service` | Terms link on signup |
| `PRIVACY_URL` | `https://www.chatwoot.com/privacy-policy` | Privacy policy link |
| `DISPLAY_MANIFEST` | `true` | Show default Chatwoot metadata |

**Asset Deployment via ZIP Archive**:
```bash
# Set BRAND_ASSETS_URL to point to ZIP file containing:
# - All favicon variants (android, apple, ms icons)
# - Brand logos (SVG/PNG)
# - Custom assets

# Automatically extracted by post_start hook in docker-compose.coolify.yaml:49
deployment/extract_brand_assets.sh "${BRAND_ASSETS_URL}"
```

**Docker Integration** (docker-compose.coolify.yaml):
```yaml
environment:
  - BRAND_ASSETS_URL=${BRAND_ASSETS_URL}

post_start:
  - command: |
      bundle exec rails branding:update && \
      if [ -n "${BRAND_ASSETS_URL}" ]; then
        deployment/extract_brand_assets.sh "${BRAND_ASSETS_URL}"
      fi
```

**Documentation**: CUSTOM_BRANDING.md

---

## 3. Email Delivery: Resend Integration

**Purpose**: Alternative email delivery provider option.

**Key Commit**: `5b7fc9ae7` - feat: add Resend email delivery method (#11)

**Implementation**:
- Custom provider: `lib/mail/resend_provider.rb`
- Initializer: `config/initializers/resend.rb`
- Gemfile: Added `resend` gem

**Configuration**:
```bash
RESEND_API_KEY=re_xxxxx
```

**Files Modified**:
```
lib/mail/resend_provider.rb
config/initializers/mailer.rb
config/initializers/resend.rb
spec/lib/mail/resend_provider_spec.rb
```

---

## 4. Message & Conversation Enhancements

### 4.1 Edited Message Tracking

**Key Commit**: `8d5a6bc4b` - feat: add flag to edited messages and content history tracking (#35)

**Implementation**:
```ruby
# app/models/message.rb
# Stores original content before edit
message.content_attributes['is_edited'] = true
message.content_attributes['original_content'] = previous_content
```

**Use Cases**:
- Audit trail for customer service quality
- Compliance requirements (financial/healthcare sectors)
- Dispute resolution evidence

**Files**:
- `app/models/message.rb`
- Modified: `app/services/whatsapp/incoming_message_baileys_service.rb`

---

### 4.2 Conversation Cloning Between Inboxes

**Key Commit**: `93d9992cd` - feat: rake task to copy conversations from one inbox to another (#84)

**Purpose**: Migrate conversations when switching WhatsApp providers (e.g., 360Dialog → Baileys).

**Usage**:
```bash
bundle exec rake clone_inbox:copy_conversations[source_inbox_id,target_inbox_id]
```

**Features**:
- ✅ Duplicates all messages with original timestamps
- ✅ Preserves attachments and media
- ✅ Copies contact attributes
- ✅ Maintains conversation tags
- ✅ Skips message flooding checks
- ✅ Transaction-based (rollback on error)

**Implementation**: `lib/tasks/clone_inbox.rake`

**Business Context**: Critical for zero-downtime provider migration.

---

### 4.3 Unread Conversation Marking

**Key Commit**: `21133c338` - feat: mark unread conversations (#49)

**Purpose**: Allow agents to flag conversations requiring follow-up.

---

## 5. Email Signature Customization

**Key Commit**: `c6f9e814c` - feat: add customizable signature position and separator options (#78)

**Features**:
- Configurable signature placement (top/bottom of email)
- Custom separator styles
- Per-agent signature overrides

**Use Case**: Professional services requiring formal email formatting standards.

---

## 6. User Experience & Permission Enhancements

### 6.1 Non-Admin Baileys Management

**Key Commit**: `11f8aac29` - feat: allow non-admin to refresh baileys connection (#89)

**Changes**:
- Agents can reconnect WhatsApp without admin intervention
- Auto-setup connection provider on errors
- Localized error messages

**Business Impact**: Reduces support tickets and admin bottlenecks.

---

### 6.2 Localhost Webhook Validation

**Key Commit**: `59675caf6` - feat: enhance URL validation for webhook form to support localhost (#54)

**Purpose**: Enable local development/testing of webhook integrations.

```ruby
# Allows: http://localhost:3000/webhook, http://127.0.0.1/webhook
# Only in RAILS_ENV=development
```

---

### 6.3 Account Switcher UX Improvements

**Key Commit**: `43e83a678` - fix: enhance account switcher dropdown styling (#99)

**Changes**: Better visual hierarchy, improved click targets, accessibility enhancements.

---

## 7. Infrastructure & Deployment

### 7.1 Coolify Platform Support

**File**: `docker-compose.coolify.yaml`

**Key Commit**: `be18159b0` - Merge PR #130 (Coolify compose file)

**Coolify-Specific Features**:
- Service health checks with proper retry logic
- Post-start hooks for database prep and branding
- Environment variable templating with `${VAR}` syntax
- Redis password configuration
- PostgreSQL with pgvector extension

**Services**:
```yaml
services:
  rails:      # Main application (port 3000)
  sidekiq:    # Background job processor
  postgres:   # Database (pgvector/pgvector:pg16)
  redis:      # Cache & job queue
```

---

### 7.2 GitHub Actions & CI/CD

**Key Commits**:
- `23cefa6c7` - Auto-update version tags
- `adee31a38` - Enterprise edition GitHub Docker workflow
- `e930820f6` - Trigger on fazer-ai/main branch

**Customizations**:
- Automated Docker image builds to `ghcr.io/fazer-ai/chatwoot:latest`
- Version tagging from git tags
- Enterprise edition build support

---

### 7.3 Database Configuration

**Key Commit**: `29a2474d0` - fix: add checkout_timeout to database configuration (#101)

**Purpose**: Prevent connection pool exhaustion in high-traffic deployments.

```ruby
# config/database.yml
checkout_timeout: 10  # seconds
```

---

### 7.4 Active Record Console Logging

**Key Commit**: `02732b3db` - chore: enable ActiveRecord logging in Rails console (#16)

**Purpose**: Debugging SQL queries in production console sessions.

```ruby
# config/environments/production.rb
ActiveRecord::Base.logger = Logger.new(STDOUT) if defined?(Rails::Console)
```

---

## 8. Localization (Brazilian Portuguese Focus)

**Multiple commits improving pt_BR translations**:
- Updated i18n files across dashboard modules
- Devise authentication localization
- Inbox management, settings, SLA, integrations, help center

**Files Updated**:
```
app/javascript/dashboard/i18n/locale/pt_BR/*.json
config/locales/devise.pt_BR.yml
```

**Strategic Context**: Fazer.AI operates primarily in Brazilian market.

---

## 9. Data Validation & Quality Improvements

### 9.1 Account Name Presence Validation

**Key Commit**: `96d100354` - feat: add presence validation for account name (#117)

**Purpose**: Prevent creation of accounts without proper identification.

---

### 9.2 Article Content Length Enforcement

**Key Commit**: `3dac94e05` - fix(article): enforce maximum length for content validation (#109)

**Purpose**: Prevent database overflow and improve help center performance.

---

### 9.3 Instagram Contact Identifiers

**Key Commit**: `f12b77c55` - fix(instagram): include identifier in contact attributes (#125)

**Purpose**: Proper contact deduplication for Instagram DM conversations.

---

### 9.4 Twilio Error Handling

**Key Commits**:
- `4cb185c50` - test: fix twilio specs (#119)
- `9cd3edb49` - fix: revert Twilio message creation using create! (#118)

**Purpose**: Graceful handling of Twilio API failures (rate limits, invalid numbers).

---

## 10. System Health & Monitoring

### 10.1 Baileys Connection Monitoring

**Key Commits**:
- `2cf1795a3` - feat: baileys connection period check (#87)
- `99255c199` - feat: on whatsapp baileys check (#95)

**Implementation**:
```ruby
# Scheduled jobs check connection health every 15 minutes
Channels::Whatsapp::BaileysConnectionCheckSchedulerJob
Channels::Whatsapp::BaileysConnectionCheckJob
```

**Alerts**: Notifies admins via dashboard banner when Baileys API is unreachable.

---

### 10.2 Channel Availability Dispatching

**Key Commit**: `19ad42a58` - feat: dispatch to channel listener on availability change (#42)

**Purpose**: Real-time WebSocket updates when WhatsApp connection status changes.

---

### 10.3 Custom Version Check

**Modified Files**:
- `app/jobs/internal/check_new_versions_job.rb`
- `app/javascript/dashboard/components/app/UpdateBanner.vue`

**Change**: Points version checks to `fazer-ai/chatwoot` repository instead of upstream.

**Purpose**: Show update notifications for Fazer.AI-specific releases.

---

## 11. Notification & Settings

### 11.1 Email Flag Clearing

**Key Commit**: `16f5c2c62` - fix: update notification setting to clear selected email flags (#100)

**Purpose**: Fix bug where email notification preferences weren't properly reset.

---

### 11.2 SMTP Configuration Check Enhancement

**Key Commit**: `8c851c919` - fix: enhance SMTP configuration check to include RESEND_API_KEY (#92)

**Change**: System readiness checks now validate Resend API key alongside traditional SMTP settings.

---

## 12. Code Quality & Refactoring

### 12.1 RuboCop SaveBang Cop

**Key Commit**: `659c3e7c2` - chore: apply Rails/SaveBang cop (#15)

**Purpose**: Replace `.save` with `.save!` to surface validation errors earlier.

---

### 12.2 Vue 3 Component Modernization

**Key Commit**: `22c8ea826` - refactor: replace woot-button with NextButton (#22)

**Purpose**: Migration to design system components for consistency.

---

## Comparison: Fazer.AI vs Upstream Chatwoot

| Feature | Upstream Chatwoot | Fazer.AI Fork |
|---------|-------------------|---------------|
| **WhatsApp Integration** | Cloud API only | Baileys + Z-API alternatives |
| **Branding** | Enterprise UI | Environment variables |
| **Email Provider** | SMTP/SendGrid/Mailgun | + Resend |
| **Message Editing** | Basic tracking | Content history preservation |
| **Conversation Migration** | Manual/API | Rake task for bulk cloning |
| **LID Support** | Partial | Full multi-device support |
| **Brazilian Localization** | Community-driven | Production-grade pt_BR |
| **Deployment** | Docker/K8s | + Coolify platform optimized |
| **Version Checks** | chatwoot/chatwoot | fazer-ai/chatwoot |

---

## Key Strategic Differentiators

1. **Open Source Alternatives**: Baileys and Z-API provide WhatsApp integration without proprietary API dependencies

2. **Brazilian Market Optimization**:
   - Z-API integration (local provider)
   - Production-grade pt_BR localization
   - Local regulatory compliance features

3. **Operational Tooling**:
   - Conversation cloning for migration
   - Enhanced health monitoring
   - Non-admin agent empowerment

4. **Open Source Philosophy**:
   - All features remain OSS-compatible
   - No vendor lock-in
   - Community can adopt improvements

---

## Maintenance Considerations

### Upstream Merge Strategy

Fazer.AI regularly merges upstream Chatwoot releases:
- `3a14e2c0b` - Merge upstream 4.7.0
- `9820a77f2` - Merge upstream 4.6.0
- `7d76f580a` - Merge upstream 4.5.2
- `cbe30f5fb` - Merge upstream 4.5.0
- `658053fd0` - Merge upstream 4.4.0

**Merge Frequency**: Approximately every 2-4 weeks.

**Conflict Areas**:
- WhatsApp provider architecture
- Branding system (Enterprise vs custom)
- Email configuration initializers

### codi/Click2Run absorption history

The codi fork stepwise-merged fazer-ai tags into branch
`codi-v4.9.0-fazer-ai.13` (rebased from `codi-v4.7.0-fazer-ai.6`):

| Date (UTC) | Tag | Commit | Notes |
|---|---|---|---|
| 2026-05-07 | `v4.7.0-fazer-ai.7` | `cc87a17328` | zapi first-connection fix |
| 2026-05-07 | `v4.7.0-fazer-ai.8` | `b234757b21` | promo banner |
| 2026-05-07 | `v4.7.0-fazer-ai.9` | `504cdba4f0` | Baileys v7 upgrade |
| 2026-05-07 | `v4.8.0-fazer-ai.1` | `2fa448742f` | **Upstream Chatwoot 4.8.0** — agents_bots assignees, INBOUND_EMAIL_DOMAIN gating, etc. |
| 2026-05-07 | `v4.8.0-fazer-ai.2` | `127333c59f` | message_builder + messages_controller |
| 2026-05-07 | `v4.8.0-fazer-ai.3` | `9268987339` | heatmap selector |
| 2026-05-07 | `v4.8.0-fazer-ai.4` | `b3b846f9fb` | image/audio bubble + loadWithRetry |
| 2026-05-07 | `v4.8.0-fazer-ai.5` | `8a931d445d` | provider service tweaks |
| 2026-05-07 | `v4.8.0-fazer-ai.6` | `fb8ce5c1bb` | zapi read-message job |
| 2026-05-07 | `v4.8.0-fazer-ai.7` | `b4ae22434b` | twilio + baileys provider |
| 2026-05-07 | `v4.9.0-fazer-ai.8` | `b519c7aeb8` | **Upstream Chatwoot 4.9.0** — Voice Channel, TikTok channel, custom-attribute redesign, Year-in-Review |
| 2026-05-07 | `v4.9.0-fazer-ai.9` | `47d22141bb` | conversations attachments controller |
| 2026-05-07 | `v4.9.0-fazer-ai.10` | `a6d4a6d3c0` | webhooks error handler + .annotaterb.yml |
| 2026-05-07 | `v4.9.0-fazer-ai.11` | `9dae4e8fff` | webhook listener |
| 2026-05-07 | `v4.9.0-fazer-ai.12` | `c8cda81de0` | ReplyBox/Editor + jbuilders |
| 2026-05-07 | `v4.9.0-fazer-ai.13` | `775f47cd8a` | Dockerfile bundler quoting |

**Conflict areas observed during this codi absorption pass**:
- `app/views/layouts/vueapp.html.erb` — both sides add new `window.chatwootConfig` keys (ours: `click2runOpenidAppId/Label/LoginRedirect`; theirs: `allowedLoginMethods`).
- `app/javascript/v3/views/login/Index.vue` — both sides interleave new login methods; required adding `parseBoolean` import.
- `app/javascript/dashboard/featureFlags.js`, `config/features.yml` — both sides add new feature flags (Click2Run/Whatsmeow/Baileys/Z-API/Bandwidth/SMS vs upstream's `companies` and `channel_tiktok`).
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` — composable destructuring (ours kept `isCloudFeatureEnabled`, theirs added `isOnChatwootCloud`; resolved by destructuring both).
- `app/javascript/dashboard/components/widgets/ChannelItem.vue` — additive `hasSmsProviderConfigured` / `hasTiktokConfigured`.
- `db/schema.rb`, `Gemfile.lock`, `pnpm-lock.yaml` — taken from theirs (regenerable artefacts).
- `package.json` — kept newer of each (vite 5.4.21, vite-plugin-ruby 5.1.1).
- `docker/Dockerfile` — kept our `BUNDLER_VERSION=2.7.2`, took theirs' quoted form.

---

### Testing Coverage

All major features include specs:
```
spec/services/whatsapp/providers/whatsapp_baileys_service_spec.rb
spec/services/whatsapp/providers/whatsapp_zapi_service_spec.rb
spec/lib/mail/resend_provider_spec.rb
spec/helpers/baileys_helper_spec.rb
spec/models/message_spec.rb (edit tracking tests)
```

**Test Philosophy**: Production features require test coverage; experimental features may ship without.

---

## Environment Variables Summary

Complete list of Fazer.AI-specific environment variables:

```bash
# WhatsApp Baileys Provider
BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME=Chatwoot
BAILEYS_PROVIDER_DEFAULT_URL=http://localhost:3025
BAILEYS_PROVIDER_DEFAULT_API_KEY=
BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL=true

# Email Delivery
RESEND_API_KEY=re_xxxxx

# Custom Branding
BRAND_ASSETS_URL=https://example.com/brand-assets.zip
INSTALLATION_NAME="My Company Chat"
LOGO_THUMBNAIL=/brand-assets/logo_thumbnail.svg
LOGO=/brand-assets/logo.svg
LOGO_DARK=/brand-assets/logo_dark.svg
BRAND_URL=https://mycompany.com
WIDGET_BRAND_URL=https://mycompany.com
BRAND_NAME="My Company"
TERMS_URL=https://mycompany.com/terms
PRIVACY_URL=https://mycompany.com/privacy
DISPLAY_MANIFEST=false
```

---

## Future Development Indicators

Based on commit patterns, likely future enhancements:

1. **WhatsApp Multi-Agent Support**: Advanced routing for Baileys
2. **Z-API Feature Parity**: Bring to same level as Baileys
3. **Enhanced Analytics**: Message delivery success rates
4. **Telegram Integration**: Following WhatsApp pattern
5. **AI-Powered Features**: Message classification, auto-responses

---

## Documentation & Support

**Official Fazer.AI Chatwoot Resources**:
- Repository: https://github.com/fazer-ai/chatwoot
- Custom Branding Guide: CUSTOM_BRANDING.md
- Docker Image: ghcr.io/fazer-ai/chatwoot:latest

**Upstream Compatibility**:
- All features designed to be non-breaking
- Can be disabled via environment variables
- Enterprise edition compatibility maintained

---

## License Compliance

**Upstream License**: MIT License (Chatwoot)

**Fazer.AI Modifications**: Also MIT License

**Enterprise Considerations**: Custom branding system does NOT violate Chatwoot's Enterprise license terms, as it:
- Uses documented public APIs (`InstallationConfig`)
- Does not bypass licensing checks
- Provides alternative implementation pattern
- Remains open source

---

## Conclusion

1. **Open Source Alternatives**: Free WhatsApp integration options
2. **Developer Experience**: GitOps workflows, environment variables
3. **Production Reliability**: Health checks, error handling, migration tools
4. **Market Adaptation**: Brazilian localization, local providers
5. **Open Source Sustainability**: All improvements remain OSS-compatible
