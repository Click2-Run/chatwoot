# Própria Cloud / Chatwoot — Custom Changelog

Curated history of customizations made to this Chatwoot fork on top of
the upstream `fazer-ai/chatwoot` tree. Only commits authored by the
project owner are listed (filtered by `robson@robson.com.br`,
`robson@controle.digital`, `*@propria.cloud`, `*@controle.digital`).
Upstream merges and third-party PRs are intentionally excluded — they
are visible via `git log` against the remote tracking branches.

Newest first. Each entry shows the commit subject, the short SHA, and
the files touched (additions / deletions). Regenerate from inside the
rails container with:

```bash
git log --all --reverse --pretty=format:'COMMIT %H|%aI|%s' --numstat \
  --author='robson@robson.com.br' > .llm/temporary/our-history.txt
docker compose exec -T rails ruby /app/.codi/scripts/build-changelog.rb \
  .llm/temporary/our-history.txt CUSTOM-CHANGELOG.md
```

Add new author emails to the `--author` filter as the team grows; the
builder script accepts the input/output paths positionally.

## Version milestones

Each adopted upstream tag becomes its own `codi-vX.Y.Z-fazer-ai.N`
branch and gets a `codi-vX.Y.Z-fazer-ai.N.ITER` tag for every
Própria-Cloud-side release cut on top of it. The chatwoot core
version (`vX.Y.Z`) is the upstream Chatwoot release embedded inside
fazer-ai; the `.N` suffix is fazer-ai's own iteration counter.

Update this table whenever a new fazer-ai upstream tag is adopted
or a new `codi-*` release tag is cut. The script preserves the
block on regen — edit it directly inside `.codi/scripts/build-changelog.rb`.

| Date       | Branch                          | Adopted upstream tag        | Chatwoot core | Notes                                                                                       |
| :--------- | :------------------------------ | :-------------------------- | :------------ | :------------------------------------------------------------------------------------------ |
| 2025-11-03 | `codi-v4.7.0-fazer-ai.6`        | `v4.7.0-fazer-ai.6`         | 4.7.0         | Initial fork — Click2Run / OpenID Connect / WhatsApp baseline.                              |
| 2026-05-07 | `codi-v4.9.0-fazer-ai.13`       | `v4.9.0-fazer-ai.13`        | 4.9.0         | Tagged `codi-v4.9.0-fazer-ai.13.1` after intermediate upgrade. Safety tag: `codi-pre-upgrade-2026-05-07`. |
| 2026-05-08 | `codi-v4.13.0-fazer-ai.66`      | `v4.13.0-fazer-ai.66`       | 4.13.0        | Tagged `codi-v4.13.0-fazer-ai.66.1`. Safety tag: `codi-pre-upgrade2-2026-05-08`. **Current branch.** |
| 2026-05-09 | _(still on `.66` branch)_       | `fazerai/main` head (post-`.66`) | 4.13.0   | Merged 2 untagged upstream commits (#285, #286) — within the `.66` cycle until fazer-ai cuts `.67`. |

Pre-upgrade safety tags taken before each version bump (kept as
rollback anchors): `codi-pre-upgrade-2026-05-07`, `codi-pre-upgrade2-2026-05-08`.


## 2026-05

### 2026-05-10
- **`83ac55615`** — fix(whatsapp-propriacloud): retry transient 500 on /instances/create + friendly setup errors
  - `app/controllers/api/v1/accounts/inboxes_controller.rb` +20/-0
  - `app/javascript/dashboard/store/modules/inboxes.js` +7/-1
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +18/-10
- **`eabe40b97`** — docs: refresh CUSTOM-CHANGELOG with two-axis status resolver
  - `CUSTOM-CHANGELOG.md` +9/-0
- **`c181c10f2`** — feat(whatsapp-propriacloud): two-axis status resolver + per-state action button (mirrors propriacloud.git/minha)
  - `app/javascript/dashboard/components/widgets/conversation/PropriacloudStatusBadge.vue` +23/-79
  - `app/javascript/dashboard/composables/usePropriacloudStatus.js` +159/-0
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +6/-0
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +6/-0
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue` +61/-25
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +7/-0
- **`3ad506390`** — docs: refresh CUSTOM-CHANGELOG with WhatsApp pair cooldown countdown
  - `CUSTOM-CHANGELOG.md` +9/-0
- **`c6a1d3d8b`** — feat(whatsapp-propriacloud): honor WhatsApp's recommended pair cooldown with persisted lock + live countdown
  - `app/controllers/api/v1/accounts/inboxes_controller.rb` +28/-0
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +2/-1
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +2/-1
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue` +48/-0
  - `app/javascript/dashboard/store/modules/inboxes.js` +12/-7
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +69/-7
- **`efa74eaac`** — docs: refresh CUSTOM-CHANGELOG with QR-on-phone-code fix
  - `CUSTOM-CHANGELOG.md` +9/-0
- **`bc05cf45e`** — fix(whatsapp-propriacloud): no implicit QR on phone-code path + friendly pair errors + correct error semantics
  - `app/controllers/api/v1/accounts/inboxes_controller.rb` +64/-18
  - `app/javascript/dashboard/api/inboxes.js` +2/-2
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue` +8/-1
  - `app/javascript/dashboard/store/modules/inboxes.js` +21/-4
  - `app/services/whatsapp/propriacloud_handlers/connection_update.rb` +16/-1
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +10/-2
- **`8939018b6`** — docs: refresh CUSTOM-CHANGELOG with refresh-status authz fix
  - `CUSTOM-CHANGELOG.md` +4/-0
- **`827a5f2dc`** — fix(inboxes-controller): refresh_provider_status authz uses inbox instance, not class
  - `app/controllers/api/v1/accounts/inboxes_controller.rb` +5/-1
- **`e76027a16`** — docs: refresh CUSTOM-CHANGELOG with backfill auth + Unpair fixes
  - `CUSTOM-CHANGELOG.md` +9/-0
- **`cfad7bcd4`** — fix(whatsapp-propriacloud): bypass webhook auth on backfill dispatch + rename Disconnect to Unpair
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +1/-1
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +1/-1
  - `app/services/whatsapp/propriacloud/history_backfill_service.rb` +5/-0
- **`0ad2155cc`** — fix(whatsapp-propriacloud): paged_get must walk data.<resource>[]; accept @lid chats in backfill
  - `app/services/whatsapp/propriacloud/history_backfill_service.rb` +6/-1
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +37/-2
- **`1912ee844`** — docs: refresh CUSTOM-CHANGELOG with frontend status auto-reconcile commit
  - `CUSTOM-CHANGELOG.md` +7/-0
- **`bafe4bd94`** — feat(whatsapp-propriacloud): auto-reconcile cached provider_connection on inbox visit
  - `app/javascript/dashboard/api/inboxes.js` +4/-0
  - `app/javascript/dashboard/components/widgets/conversation/PropriacloudStatusBadge.vue` +19/-1
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue` +9/-0
  - `app/javascript/dashboard/store/modules/inboxes.js` +24/-0
- **`3b093e0ca`** — docs: refresh CUSTOM-CHANGELOG with cross-stack webhook fix
  - `CUSTOM-CHANGELOG.md` +5/-0
- **`b8671f163`** — fix(whatsapp-propriacloud): publish rails on host port + reconcile webhook URL changes
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +38/-12
  - `docker-compose.yaml` +12/-2
- **`1bad70e49`** — docs: refresh CUSTOM-CHANGELOG with reconcile + Multicanal brand commits
  - `CUSTOM-CHANGELOG.md` +10/-0
- **`29338e6d6`** — feat(whatsapp-propriacloud): self-healing reconcile + auto-close on pair + Multicanal product brand
  - `app/controllers/api/v1/accounts/inboxes_controller.rb` +11/-2
  - `app/javascript/dashboard/i18n/locale/en/login.json` +1/-1
  - `app/javascript/dashboard/i18n/locale/pt_BR/login.json` +1/-1
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue` +22/-0
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +36/-0
- **`39253e4cc`** — docs: refresh CUSTOM-CHANGELOG to include latest changelog refresh entry
  - `CUSTOM-CHANGELOG.md` +2/-0

### 2026-05-09
- **`9b40aadef`** — docs: refresh changelog with status-reconciliation + sidebar fixes
  - `CUSTOM-CHANGELOG.md` +10/-0
- **`8c21657f5`** — fix(whatsapp-propriacloud): tolerant validate_provider_config + status reconciliation + sidebar polish
  - `app/controllers/api/v1/accounts/inboxes_controller.rb` +24/-0
  - `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` +18/-15
  - `app/javascript/dashboard/i18n/locale/en/settings.json` +1/-1
  - `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` +1/-1
  - `app/policies/inbox_policy.rb` +5/-0
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +75/-2
  - `config/routes.rb` +1/-0
- **`172a0b6fd`** — docs: refresh CUSTOM-CHANGELOG with auto-pairing fix + status badge commits
  - `CUSTOM-CHANGELOG.md` +17/-0
- **`c5660f91f`** — fix(whatsapp-propriacloud): kill auto-pairing paths and surface clean propriacloud status
  - `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue` +10/-0
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +4/-1
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +4/-1
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue` +16/-15
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue` +31/-3
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/ConfigurationPage.vue` +79/-64
  - `app/models/channel/whatsapp.rb` +14/-0
  - `app/services/whatsapp/propriacloud_handlers/connection_update.rb` +21/-0
  - `app/services/whatsapp/propriacloud_handlers/instance_recovery.rb` +6/-0
- **`28c7f2c33`** — feat(whatsapp-propriacloud): inline connection-state badge in conversation header
  - `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue` +2/-0
  - `app/javascript/dashboard/components/widgets/conversation/PropriacloudStatusBadge.vue` +85/-0
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +6/-0
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +6/-0
- **`e0d245efc`** — docs: refresh CUSTOM-CHANGELOG to include guide + milestones commits
  - `CUSTOM-CHANGELOG.md` +9/-0
- **`84ef72535`** — docs: add CUSTOM-MERGES-GUIDE.md and cross-link from CUSTOM-FAZER-AI
  - `CUSTOM-FAZER-AI.md` +7/-0
  - `CUSTOM-MERGES-GUIDE.md` +226/-0
- **`d57b24b94`** — docs(changelog): add Version milestones table tracking branch/tag bumps
  - `.codi/scripts/build-changelog.rb` +25/-0
  - `CUSTOM-CHANGELOG.md` +22/-0
- **`d06fea621`** — docs: refresh changelog after fazerai/main merge (159 commits)
  - `.codi/scripts/build-changelog.rb` +12/-2
  - `CUSTOM-CHANGELOG.md` +4/-0
- **`bbe00fc70`** — Merge remote-tracking branch 'fazerai/main' into codi-v4.13.0-fazer-ai.66
- **`78b4b7879`** — docs: refresh CUSTOM-CHANGELOG (157 commits) and persist regen script
  - `.codi/scripts/build-changelog.rb` +95/-0
  - `CUSTOM-CHANGELOG.md` +18/-2
- **`e9dfe16f0`** — refactor(whatsapp-propriacloud): unify pairing trigger as small "Emparelhar" button
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +2/-5
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +2/-5
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue` +28/-25
- **`f0d04498f`** — docs: add CUSTOM-CHANGELOG.md covering all 155 fork-owner commits
  - `CUSTOM-CHANGELOG.md` +529/-0
- **`b2ea56dfb`** — chore: ignore .llm and .claude runtime artifacts; sync schema.rb
  - `.gitignore` +2/-0
  - `db/schema.rb` +6/-12
- **`fa98b6e9c`** — chore(brand): replace fazer-ai/Click2Run mentions with Própria Cloud across user-facing surfaces
  - `CUSTOM-FAZER-AI.md` +50/-0
  - `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` +7/-6
  - `app/controllers/health_controller.rb` +1/-1
  - `app/controllers/webhooks/whatsapp_controller.rb` +1/-1
  - `app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue` +1/-1
  - `app/javascript/dashboard/components/app/UpdateBanner.vue` +1/-1
  - `app/javascript/dashboard/constants/globals.js` +6/-1
  - `app/javascript/dashboard/i18n/locale/en/kanban.json` +2/-2
  - `app/javascript/dashboard/i18n/locale/pt_BR/kanban.json` +2/-2
  - `app/javascript/dashboard/routes/dashboard/internalChat/ProFeatureNudge.vue` +1/-1
  - `app/javascript/dashboard/routes/dashboard/kanban/Index.vue` +1/-1
  - `app/javascript/dashboard/routes/dashboard/settings/account/components/BuildInfo.vue` +2/-2
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` +2/-2
  - `app/javascript/v3/views/login/Index.vue` +2/-2
  - `app/views/super_admin/devise/sessions/new.html.erb` +1/-1
  - `lib/middleware/fazer_ai_platform_header.rb` +1/-1
  - `lib/tasks/branding.rake` +1/-1
- **`f571466a1`** — feat(whatsapp-propriacloud): wire edit/delete message + use channel id as instance_id
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +46/-2
- **`eb8aa11d6`** — fix(super-admin): seed Própria Cloud DB rows from legacy env aliases on first read
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +37/-17
  - `app/views/super_admin/app_configs/_propriacloud_tabs.html.erb` +8/-0
- **`b46bc967c`** — feat(whatsapp-propriacloud): full event coverage + history backfill + custom_id sanity check
  - `app/jobs/whatsapp/propriacloud/history_backfill_job.rb` +19/-0
  - `app/services/whatsapp/incoming_message_propriacloud_service.rb` +58/-0
  - `app/services/whatsapp/propriacloud/history_backfill_service.rb` +115/-0
  - `app/services/whatsapp/propriacloud_handlers/appstate.rb` +109/-0
  - `app/services/whatsapp/propriacloud_handlers/connection_update.rb` +14/-0
  - `app/services/whatsapp/propriacloud_handlers/history_sync.rb` +40/-0
  - `app/services/whatsapp/propriacloud_handlers/instance_recovery.rb` +42/-0
  - `app/services/whatsapp/propriacloud_handlers/messages_failure.rb` +39/-0
  - `app/services/whatsapp/propriacloud_handlers/user_changed.rb` +44/-0
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +151/-10
- **`17acc182c`** — feat(whatsapp-propriacloud): send account id as custom_id to whatsapp-api
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +6/-1
- **`659574b55`** — feat(whatsapp-propriacloud): add small "OK" close button at modal bottom
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue` +4/-0
- **`7f71f3792`** — feat(super-admin): tabbed Própria Cloud config + move card to last position
  - `app/helpers/super_admin/features.yml` +8/-6
  - `app/views/super_admin/app_configs/_propriacloud_tabs.html.erb` +93/-0
  - `app/views/super_admin/app_configs/show.html.erb` +4/-0
- **`667d75238`** — feat(super-admin): Própria Cloud integration card with DB-backed config
  - `CUSTOM-WHATSAPP-API.md` +37/-7
  - `app/controllers/super_admin/app_configs_controller.rb` +1/-0
  - `app/helpers/super_admin/features.yml` +6/-0
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +38/-17
  - `config/installation_config.yml` +15/-0
- **`4c2b49048`** — refactor(whatsapp-propriacloud): drop redundant phone input from phone-code tab
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +1/-3
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +1/-3
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue` +2/-20
- **`6b188728b`** — feat(i18n): force pt_BR locale on new account and user creation
  - `.env.example` +8/-3
  - `CUSTOM-DEFAULT-LANGUAGE.md` +175/-0
  - `app/builders/account_builder.rb` +8/-1
  - `app/models/user.rb` +11/-0
- **`5268fabc1`** — feat(whatsapp-propriacloud): phone-code pairing UX with method picker
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +11/-1
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +11/-1
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue` +139/-33
  - `app/policies/inbox_policy.rb` +4/-0
- **`19bfebcef`** — docs(custom): rename CUSTOM_*.md to CUSTOM-*.md and refresh WhatsApp API doc
  - `CUSTOM_AUTH.md => CUSTOM-AUTH.md` +0/-0
  - `CUSTOM_BRANDING.md => CUSTOM-BRANDING.md` +0/-0
  - `CUSTOM_CADDY.md => CUSTOM-CADDY.md` +0/-0
  - `CUSTOM_CLICK2-RUN.md => CUSTOM-CLICK2-RUN.md` +0/-0
  - `CUSTOM_CLICK2RUN-API.md => CUSTOM-CLICK2RUN-API.md` +0/-0
  - `CUSTOM_FAZER-AI.md => CUSTOM-FAZER-AI.md` +0/-0
  - `CUSTOM-WHATSAPP-API.md` +293/-0
  - `CUSTOM_WHATSAPP-QRCODE.md` +0/-195
- **`9a588275a`** — fix(propriacloud): pull QR explicitly after connect — UI never receives a pairing.qrcode webhook on already-connected instances
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +33/-0
- **`b07c73c8c`** — fix(propriacloud): treat 409 from /webhooks as idempotent success
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +5/-0
- **`f99408161`** — feat(propriacloud): phone-code pairing as alternative to QR scan
  - `app/controllers/api/v1/accounts/inboxes_controller.rb` +14/-0
  - `app/javascript/dashboard/api/inboxes.js` +4/-0
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue` +108/-15
  - `app/javascript/dashboard/store/modules/inboxes.js` +9/-0
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +23/-0
  - `config/routes.rb` +1/-0

### 2026-05-08
- **`b3de10c38`** — feat(propriacloud): connection-status panel on Inbox Settings tab
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue` +79/-0
- **`9f4d2e085`** — fix(propriacloud): include propriacloud in Configuration tab gating
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue` +2/-1
- **`37af0092c`** — feat(propriacloud): wire UI predicates so Própria Cloud inboxes get the QR/connection management page
  - `app/javascript/dashboard/composables/useInbox.js` +8/-0
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/FinishSetup.vue` +4/-2
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue` +4/-0
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/ConfigurationPage.vue` +1/-1
  - `app/javascript/shared/mixins/inboxMixin.js` +6/-0
- **`89c523f5a`** — feat(propriacloud): wire whatsapp-api integration end-to-end
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/PropriacloudWhatsapp.vue` +22/-0
  - `app/services/whatsapp/incoming_message_propriacloud_service.rb` +59/-7
  - `app/services/whatsapp/propriacloud_handlers/connection_update.rb` +45/-31
  - `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` +14/-9
- **`9b53c087f`** — fix(env): document /api/v1 base path requirement for WHATSAPP_API_URL
  - `.env.example` +10/-4
- **`dd686d2e4`** — ui(whatsapp): tighten Própria Cloud picker labels
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +2/-2
  - `app/javascript/dashboard/i18n/locale/es/inboxMgmt.json` +2/-2
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +2/-2
- **`7b8e61957`** — ui(whatsapp): hide promo banners; default Própria Cloud picker only
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` +6/-28
- **`8aa7c78ea`** — feat(rebrand): rename click2run -> propriacloud (WhatsApp + OIDC layers)
  - _29 files touched_:
    - `Gemfile.lock` +52/-3
    - `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` +2/-1
    - `app/javascript/dashboard/featureFlags.js` +1/-1
    - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +10/-10
    - `app/javascript/dashboard/i18n/locale/en/login.json` +1/-1
    - `app/javascript/dashboard/i18n/locale/es/inboxMgmt.json` +10/-10
    - `app/javascript/dashboard/i18n/locale/es/login.json` +1/-1
    - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +10/-10
    - `app/javascript/dashboard/i18n/locale/pt_BR/login.json` +1/-1
    - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/{Click2runWhatsapp.vue => PropriacloudWhatsapp.vue}` +14/-11
    - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` +19/-17
    - `app/javascript/v3/components/{Click2RunOpenid => PropriacloudOpenid}/Button.vue` +14/-14
    - `app/javascript/v3/views/login/Index.vue` +14/-10
    - `app/jobs/webhooks/whatsapp_events_job.rb` +2/-2
    - `app/models/campaign.rb` +1/-1
    - … and 14 more
- **`c643747c8`** — fix(featurable): filter overflowing default features at account creation
  - `app/builders/account_builder.rb` +5/-2
  - `app/models/concerns/featurable.rb` +16/-1
- **`9beac19ff`** — feat(branding): drive generator meta tag from BRAND_NAME
  - `app/views/layouts/vueapp.html.erb` +1/-1
- **`921a55118`** — feat(auth): rename OIDC OmniAuth provider :click2run -> :propriacloud
  - `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` +1/-1
  - `app/javascript/v3/components/Click2RunOpenid/Button.vue` +1/-1
  - `app/javascript/v3/views/login/Index.vue` +1/-1
  - `config/initializers/omniauth.rb` +2/-2
- **`f69a19f9f`** — fix(assets): restore PromoBanner.vue used by Click2Run/Z-API banners
  - `app/javascript/dashboard/components-next/banner/PromoBanner.vue` +127/-0
- **`076e2024f`** — fix(assets): restore curved-arrow.svg used by Z-API promo banner
  - `app/javascript/dashboard/assets/images/curved-arrow.svg` +9/-0
- **`58fa49614`** — merge: bring in fazer-ai v4.13.0-fazer-ai.66
- **`226a33873`** — merge: bring in fazer-ai v4.13.0-fazer-ai.65
- **`f3243c6d9`** — merge: bring in fazer-ai v4.13.0-fazer-ai.64
- **`ce50f20ef`** — merge: bring in fazer-ai v4.13.0-fazer-ai.63
- **`08c95cf76`** — merge: bring in fazer-ai v4.13.0-fazer-ai.62
- **`f906a1330`** — merge: bring in fazer-ai v4.13.0-fazer-ai.61
- **`4950c20b2`** — merge: bring in fazer-ai v4.13.0-fazer-ai.60
- **`2b51f44ca`** — merge: bring in fazer-ai v4.13.0-fazer-ai.59
- **`c07103d36`** — merge: bring in fazer-ai v4.13.0-fazer-ai.58
- **`7e01210c2`** — merge: bring in fazer-ai v4.13.0-fazer-ai.57 (upstream Chatwoot 4.13.0)
- **`427d2e290`** — merge: bring in fazer-ai v4.12.0-fazer-ai.54
- **`5939a7c8f`** — merge: bring in fazer-ai v4.12.0-fazer-ai.53
- **`1cbc3dacf`** — merge: bring in fazer-ai v4.12.0-fazer-ai.52
- **`adeeae229`** — merge: bring in fazer-ai v4.12.0-fazer-ai.51
- **`bdaf7c5f4`** — merge: bring in fazer-ai v4.12.0-fazer-ai.50
- **`4b8ed2413`** — merge: bring in fazer-ai v4.12.0-fazer-ai.49
- **`be194b36a`** — merge: bring in fazer-ai v4.12.0-fazer-ai.48
- **`029371514`** — merge: bring in fazer-ai v4.12.0-fazer-ai.47
- **`308e3ecf4`** — merge: bring in fazer-ai v4.12.0-fazer-ai.46
- **`3b4484d72`** — merge: bring in fazer-ai v4.12.0-fazer-ai.45
- **`c92b67184`** — merge: bring in fazer-ai v4.12.0-fazer-ai.44
- **`bde8fe685`** — merge: bring in fazer-ai v4.12.0-fazer-ai.43
- **`bd1040bc4`** — merge: bring in fazer-ai v4.12.0-fazer-ai.42
- **`a3e7970d5`** — merge: bring in fazer-ai v4.12.0-fazer-ai.41
- **`789939a61`** — merge: bring in fazer-ai v4.12.0-fazer-ai.40
- **`818880523`** — merge: bring in fazer-ai v4.12.0-fazer-ai.39
- **`93a87ed54`** — merge: bring in fazer-ai v4.12.0-fazer-ai.38 (upstream Chatwoot 4.12.0)
- **`171054cbb`** — merge: bring in fazer-ai v4.11.1-fazer-ai.37
- **`5943f7010`** — merge: bring in fazer-ai v4.11.1-fazer-ai.36
- **`4f1323240`** — merge: bring in fazer-ai v4.11.1-fazer-ai.35
- **`80ab67a4a`** — merge: bring in fazer-ai v4.11.1-fazer-ai.34
- **`3c869f657`** — merge: bring in fazer-ai v4.11.0-fazer-ai.33
- **`3637163a2`** — merge: bring in fazer-ai v4.11.0-fazer-ai.32
- **`74544d289`** — merge: bring in fazer-ai v4.11.0-fazer-ai.31
- **`4978eb38d`** — merge: bring in fazer-ai v4.11.0-fazer-ai.30 (upstream Chatwoot 4.11.0)
- **`e92e09994`** — merge: bring in fazer-ai v4.10.0-fazer-ai.29
- **`53a7cbc68`** — merge: bring in fazer-ai v4.10.0-fazer-ai.28
- **`7f3bc7c02`** — merge: bring in fazer-ai v4.10.0-fazer-ai.27
- **`8f0da8b8a`** — merge: bring in fazer-ai v4.10.0-fazer-ai.26
- **`c87e7c5cb`** — merge: bring in fazer-ai v4.10.0-fazer-ai.25
- **`b3da2e644`** — merge: bring in fazer-ai v4.10.0-fazer-ai.24
- **`8bfbfeb51`** — merge: bring in fazer-ai v4.10.0-fazer-ai.23
- **`d03d43654`** — merge: bring in fazer-ai v4.10.0-fazer-ai.22
- **`73738136a`** — merge: bring in fazer-ai v4.10.0-fazer-ai.21
- **`905a1aada`** — merge: bring in fazer-ai v4.10.0-fazer-ai.20
- **`d88136c8e`** — merge: bring in fazer-ai v4.10.0-fazer-ai.19
- **`9df207aef`** — merge: bring in fazer-ai v4.10.0-fazer-ai.18
- **`d1b8befd9`** — merge: bring in fazer-ai v4.10.0-fazer-ai.17
- **`71c3335c5`** — merge: bring in fazer-ai v4.10.0-fazer-ai.16
- **`a381ed2a5`** — merge: bring in fazer-ai v4.10.0-fazer-ai.15
- **`a05c37500`** — merge: bring in fazer-ai v4.10.0-fazer-ai.14 (upstream Chatwoot 4.10.0)
- **`f89d1e308`** — chore(env): document DISABLE_ENTERPRISE explicitly in .env.example
  - `.env.example` +5/-1
- **`7e23549bf`** — fix(click2run): tolerate text/plain JSON responses + add host-gateway
  - `app/services/whatsapp/providers/whatsapp_click2run_service.rb` +16/-3
  - `docker-compose.yaml` +7/-0
- **`4258f450d`** — fix(click2run): convert wrong-method/wrong-shape API calls to schema
  - `app/services/whatsapp/providers/whatsapp_click2run_service.rb` +35/-14
- **`a5a7ebda7`** — fix(click2run): correct webhook scope body + media download contract
  - `app/services/whatsapp/click2run_handlers/messages_upsert.rb` +4/-3
  - `app/services/whatsapp/providers/whatsapp_click2run_service.rb` +29/-2
- **`285c12a93`** — feat(click2run): HMAC-SHA256 webhook signature verification
  - `app/controllers/webhooks/whatsapp_controller.rb` +11/-2
  - `app/services/whatsapp/incoming_message_click2run_service.rb` +17/-2
- **`cab44ad01`** — fix(build): make docker compose stack boot end-to-end after upgrade
  - `.env.example` +7/-0
  - `Gemfile` +3/-0
  - `Gemfile.lock` +52/-3
  - `app/services/whatsapp/providers/whatsapp_click2run_service.rb` +1/-1
  - `docker-compose.yaml` +1/-0
- **`a4a2a4729`** — docs(llm): add Phase 5c Propria Cloud rebrand plan
  - `.llm/project/002-planning/20260508011323-phase-5c-propria-cloud-rebrand-plan.md` +146/-0
- **`bb8930d6c`** — docs(llm): record Phase 5b.1 whatsapp-api port conclusion
  - `.llm/conclusions/20260508011138-phase-5b1-whatsapp-api-port-complete.md` +130/-0
- **`1f5e70758`** — feat(click2run): port WhatsApp provider to whatsapp-api OpenAPI 3.1
  - `.env.example` +16/-3
  - `app/models/channel/whatsapp.rb` +1/-0
  - `app/services/whatsapp/providers/whatsapp_click2run_service.rb` +172/-285
- **`7de7b2dda`** — docs(llm): add Phase 5b whatsapp-api realignment plan
  - `.llm/project/002-planning/20260508010652-phase-5b-whatsapp-api-realignment-plan.md` +184/-0

### 2026-05-07
- **`95fb82299`** — docs(llm): record Phase 3b smoke-test results
  - `.llm/qa/20260507234550-qa-phase-3b-smoke-tests/summary.md` +78/-0
- **`ca2bba88a`** — fix(deps): pin vite-plugin-ruby to 5.1.1 (avoid ESM-only 5.2.x)
  - `package.json` +1/-1
  - `pnpm-lock.yaml` +13/-44
- **`fa0f61b2b`** — chore: regenerate pnpm-lock.yaml after fazer-ai merges
  - `pnpm-lock.yaml` +40/-9
- **`45de0e5ef`** — docs(llm): add Logto OIDC reconfiguration survey (Phase 5a prep)
  - `.llm/analysis/20260507232234-logto-oidc-reconfiguration-survey.md` +147/-0
- **`923e8fcdb`** — docs(llm): record Phase 3a env & docker-compose sanitisation audit
  - `.llm/qa/20260507231954-qa-env-compose-sanitization/summary.md` +83/-0
- **`384b34939`** — docs(llm): add fazer-ai v4.9.13 upgrade conclusion
  - `.llm/conclusions/20260507221249-fazer-ai-v4.9.13-upgrade-complete.md` +165/-0
- **`c58cec8e7`** — chore: post-upgrade housekeeping
  - `CUSTOM_FAZER-AI.md` +34/-0
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Email.vue` +3/-1
- **`775f47cd8`** — merge: bring in fazer-ai v4.9.0-fazer-ai.13 (final target)
- **`c8cda81de`** — merge: bring in fazer-ai v4.9.0-fazer-ai.12
- **`9dae4e8ff`** — merge: bring in fazer-ai v4.9.0-fazer-ai.11
- **`a6d4a6d3c`** — merge: bring in fazer-ai v4.9.0-fazer-ai.10
- **`47d22141b`** — merge: bring in fazer-ai v4.9.0-fazer-ai.9
- **`b519c7aeb`** — merge: bring in fazer-ai v4.9.0-fazer-ai.8 (upstream Chatwoot 4.9.0 - Voice Channel, TikTok, Year-in-Review)
- **`b4ae22434`** — merge: bring in fazer-ai v4.8.0-fazer-ai.7
- **`fb8ce5c1b`** — merge: bring in fazer-ai v4.8.0-fazer-ai.6
- **`8a931d445`** — merge: bring in fazer-ai v4.8.0-fazer-ai.5
- **`b3b846f9f`** — merge: bring in fazer-ai v4.8.0-fazer-ai.4
- **`926898733`** — merge: bring in fazer-ai v4.8.0-fazer-ai.3
- **`127333c59`** — merge: bring in fazer-ai v4.8.0-fazer-ai.2
- **`2fa448742`** — merge: bring in fazer-ai v4.8.0-fazer-ai.1 (upstream Chatwoot 4.8.0)
- **`504cdba4f`** — merge: bring in fazer-ai v4.7.0-fazer-ai.9 (Baileys v7 upgrade)
- **`b234757b2`** — merge: bring in fazer-ai v4.7.0-fazer-ai.8
- **`cc87a1732`** — merge: bring in fazer-ai v4.7.0-fazer-ai.7
- **`d8ab6d11c`** — On codi-v4.7.0-fazer-ai.6: pre-upgrade-untracked-2026-05-07: ghost files from prior partial fazer-ai sync (894 files - .annotaterb.yml + 893 source/asset files)
- **`4f34086aa`** — index on codi-v4.7.0-fazer-ai.6: 4217259aae docs(llm): add fazer-ai v4.9.13 upgrade analysis and plan
- **`b621961b5`** — untracked files on codi-v4.7.0-fazer-ai.6: 4217259aae docs(llm): add fazer-ai v4.9.13 upgrade analysis and plan
  - _895 files touched_:
    - `.annotaterb.yml` +65/-0
    - `app/builders/v2/reports/channel_summary_builder.rb` +38/-0
    - `app/builders/v2/reports/first_response_time_distribution_builder.rb` +68/-0
    - `app/builders/v2/reports/inbox_label_matrix_builder.rb` +65/-0
    - `app/builders/v2/reports/outgoing_messages_count_builder.rb` +79/-0
    - `app/builders/v2/reports/timeseries/report_builder.rb` +9/-0
    - `app/builders/year_in_review_builder.rb` +74/-0
    - `app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb` +43/-0
    - `app/controllers/api/v1/accounts/captain/preferences_controller.rb` +76/-0
    - `app/controllers/api/v1/accounts/captain/tasks_controller.rb` +73/-0
    - `app/controllers/api/v1/accounts/concerns/whatsapp_health_management.rb` +55/-0
    - `app/controllers/api/v1/accounts/inbox_csat_templates_controller.rb` +135/-0
    - `app/controllers/api/v1/accounts/tiktok/authorizations_controller.rb` +15/-0
    - `app/controllers/api/v2/accounts/year_in_reviews_controller.rb` +26/-0
    - `app/controllers/auth/resend_confirmations_controller.rb` +18/-0
    - … and 880 more
- **`4217259aa`** — docs(llm): add fazer-ai v4.9.13 upgrade analysis and plan
  - `.llm/analysis/20260507214114-analysis-project-state-and-fazer-ai-upgrade-strategy.md` +332/-0
  - `.llm/project/002-planning/20260507214500-fazer-ai-v4.9.13-upgrade-plan.md` +170/-0
- **`55895c6f9`** — feat: configurable Click2Run OpenID label and auto-redirect
  - `.env.example` +9/-0
  - `app/javascript/v3/components/Click2RunOpenid/Button.vue` +20/-11
  - `app/javascript/v3/views/login/Index.vue` +10/-0
  - `app/views/layouts/vueapp.html.erb` +2/-0
- **`084139045`** — docs: add Click2Run customization and integration documentation
  - `.codi/CLICK2RUN_OPENID_INTEGRATION.md` +928/-0
  - `.codi/CLICK2RUN_OPENID_SETUP.md` +548/-0
  - `.codi/WHATSAPP_INTEGRATION.md` +81/-0
  - `.codi/WHATSMEOW_INTEGRATION.md` +265/-0
  - `CHATWOOT_READ-RECEIPTS.md` +152/-0
  - `CUSTOM_AUTH.md` +424/-0
  - `CUSTOM_CADDY.md` +376/-0
  - `CUSTOM_CLICK2-RUN.md` +1336/-0
  - `CUSTOM_CLICK2RUN-API.md` +1654/-0
  - `CUSTOM_FAZER-AI.md` +646/-0
  - `CUSTOM_WHATSAPP-QRCODE.md` +195/-0

## 2026-02

### 2026-02-07
- **`735c745c8`** — chore: standardize .llm directory structure
  - _27 files touched_:
    - `.llm/20251104000000_analysis_logto_oauth_validation_report.md` +686/-0
    - `.llm/20251104_fix_omniauth_openid_connect_gem.md` +126/-0
    - `.llm/analysis/20251104_ANALYSIS_SUMMARY.txt` +638/-0
    - `.llm/analysis/20251104_BAILEYS_COMPREHENSIVE_INTEGRATION_ANALYSIS.md` +1508/-0
    - `.llm/analysis/20251104_BAILEYS_FILE_INDEX.md` +403/-0
    - `.llm/analysis/20251104_BAILEYS_QUICK_REFERENCE.md` +240/-0
    - `.llm/analysis/20251104_BAILEYS_VS_WHATSMEOW_GAP_ANALYSIS.md` +572/-0
    - `.llm/analysis/20251104_IMPLEMENTATION_PLAN.md` +597/-0
    - `.llm/analysis/20251104_WHATSMEOW_COMPREHENSIVE_INTEGRATION_ANALYSIS.md` +1512/-0
    - `.llm/analysis/20251104_provider_visibility_configuration.md` +872/-0
    - `.llm/analysis/20251104_whatsmeow_deletion_flow_analysis.md` +796/-0
    - `.llm/analysis/20251104_whatsmeow_instance_lifecycle_analysis.md` +1135/-0
    - `.llm/analysis/20251104_whatsmeow_integration_status.md` +601/-0
    - `.llm/analysis/20251104_zapi_provider_explanation.md` +573/-0
    - `.llm/analysis/20251105000000_analysis_docker_volume_optimization.md` +98/-0
    - … and 12 more

## 2025-11

### 2025-11-06
- **`3011fb8ec`** — Merge tag 'v4.7.0-fazer-ai.6' into codi-v4.7.0-fazer-ai.6
- **`c32536d8d`** — Merge branch 'codi-v4.7.0-fazer-ai.4' into develop
- **`50bcc1af8`** — fix: optimize vite Docker setup with native gem support and faster startup
  - `docker/dockerfiles/vite.Dockerfile` +16/-1
  - `docker/entrypoints/vite.sh` +14/-10
- **`5abc2b80a`** — feat: add Click2Run OpenID integration with custom auth controls
  - `.codi/CLICK2RUN_OPENID_SETUP.md` +14/-0
  - `.env.example` +10/-0
  - `CUSTOM_AUTH.md` +424/-0
  - `CUSTOM_CADDY.md` +376/-0
  - `Caddyfile` +22/-0
  - `app/builders/account_builder.rb` +10/-0
  - `app/controllers/api/v1/accounts_controller.rb` +7/-0
  - `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` +96/-6
  - `app/controllers/devise_overrides/passwords_controller.rb` +11/-0
  - `app/controllers/devise_overrides/sessions_controller.rb` +14/-0
  - `app/javascript/v3/views/login/Index.vue` +17/-3
  - `app/views/layouts/vueapp.html.erb` +1/-0
  - `config/initializers/00_omniauth_config.rb` +17/-0
  - `config/initializers/omniauth.rb` +2/-1
  - `docker-compose.yaml` +22/-2
  - `lib/config_loader.rb` +14/-2
- **`2971cfb13`** — feat: enhance WhatsApp provider configuration and feature management
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +3/-3
  - `app/javascript/dashboard/i18n/locale/es/inboxMgmt.json` +3/-3
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +3/-3
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` +11/-5
  - `config/features.yml` +4/-4
- **`d75953a6c`** — feat: add optional Super Admin session reuse via ENV variable
  - `.env.example` +42/-2
  - `app/controllers/super_admin/application_controller.rb` +20/-1
- **`78595b194`** — fix: allow ENV variables to override empty database config values
  - `lib/global_config_service.rb` +1/-1

### 2025-11-05
- **`30a5fb218`** — feat: add Click2Run WhatsApp provider translations
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +2/-2
  - `app/javascript/dashboard/i18n/locale/es/inboxMgmt.json` +27/-0
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +27/-0
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` +20/-1
- **`a2f4243a2`** — fix: disable campaign creation buttons when no inbox exists
  - `app/javascript/dashboard/components-next/Campaigns/CampaignLayout.vue` +5/-0
  - `app/javascript/dashboard/routes/dashboard/campaigns/pages/LiveChatCampaignsPage.vue` +9/-0
  - `app/javascript/dashboard/routes/dashboard/campaigns/pages/SMSCampaignsPage.vue` +11/-0
  - `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignsPage.vue` +9/-0
- **`c46a1f754`** — fix: hide SLA Reports menu item when feature is disabled
  - `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` +11/-6
- **`0c0484ffb`** — enhance: parse FRONTEND_URL for accurate URL generation in development
  - `config/environments/development.rb` +7/-1
- **`d81ee0868`** — refactor: standardize authentication branding to Click2Run OpenID Connect
  - `.codi/{LOGTO_INTEGRATION_PLAN.md => CLICK2RUN_OPENID_INTEGRATION.md}` +197/-186
  - `.codi/{LOGTO_SETUP_GUIDE.md => CLICK2RUN_OPENID_SETUP.md}` +101/-101
  - `.env.example` +18/-6
  - `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` +14/-0
  - `app/javascript/dashboard/i18n/locale/en/login.json` +1/-1
  - `app/javascript/dashboard/i18n/locale/es/login.json` +1/-0
  - `app/javascript/dashboard/i18n/locale/pt_BR/login.json` +2/-1
  - `app/javascript/v3/components/{LogtoOauth => Click2RunOpenid}/Button.vue` +12/-12
  - `app/javascript/v3/views/login/Index.vue` +6/-6
  - `app/views/layouts/vueapp.html.erb` +1/-1
  - `config/initializers/omniauth.rb` +14/-8
- **`6b997b888`** — fix: Click2Run promo banner images and small fixes
  - `.env.example` +3/-3
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` +0/-5
  - `app/services/whatsapp/providers/whatsapp_click2run_service.rb` +1/-1
  - `config/features.yml` +5/-5
- **`b98b08d19`** — feat: add Click2Run WhatsApp provider integration
  - `.env.example` +4/-0
  - `CUSTOM_CLICK2RUN-API.md` +1654/-0
  - `app/javascript/dashboard/featureFlags.js` +1/-0
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +28/-5
  - `app/javascript/dashboard/i18n/locale/es/inboxMgmt.json` +3/-7
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +3/-7
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Click2runWhatsapp.vue` +216/-0
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` +46/-1
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsmeowWhatsapp.vue` +3/-29
  - `app/jobs/webhooks/whatsapp_events_job.rb` +2/-0
  - `app/models/channel/whatsapp.rb` +5/-3
  - `app/services/whatsapp/click2run_handlers/connection_update.rb` +79/-0
  - `app/services/whatsapp/click2run_handlers/helpers.rb` +215/-0
  - `app/services/whatsapp/click2run_handlers/messages_update.rb` +122/-0
  - `app/services/whatsapp/click2run_handlers/messages_upsert.rb` +196/-0
  - `app/services/whatsapp/incoming_message_click2run_service.rb` +69/-0
  - `app/services/whatsapp/providers/whatsapp_click2run_service.rb` +543/-0
  - `config/features.yml` +4/-0
  - `db/migrate/20251105180552_add_click2run_to_provider_connection_index.rb` +25/-0
  - `db/schema.rb` +2/-2
- **`34f6fdca0`** — feat: finalize Whatsmeow WhatsApp provider integration with improved configuration
  - `.env.example` +2/-3
  - `CHATWOOT_READ-RECEIPTS.md` +152/-0
  - `CUSTOM_WHATSAPP-QRCODE.md` +195/-0
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +6/-6
  - `app/models/channel/whatsapp.rb` +2/-3
  - `app/services/whatsapp/incoming_message_whatsmeow_service.rb` +1/-1
  - `app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb` +120/-50
  - `app/services/whatsapp/whatsmeow_handlers/connection_update.rb` +1/-1
  - `app/services/whatsapp/whatsmeow_handlers/messages_update.rb` +1/-1
  - `app/services/whatsapp/whatsmeow_handlers/messages_upsert.rb` +2/-2
  - `db/schema.rb` +1/-1
- **`156d742ee`** — fix: improve Docker development environment stability and build reliability
  - `Gemfile` +2/-1
  - `Gemfile.lock` +524/-403
  - `docker-compose.yaml` +6/-0
  - `docker/Dockerfile` +3/-1
  - `docker/entrypoints/rails.sh` +2/-1
  - `docker/entrypoints/vite.sh` +6/-3
- **`c25dcafcb`** — fix: correct alias method for User associations to resolve Rails 7.2 compatibility
  - `app/models/user.rb` +1/-1
- **`a50aa214d`** — fix: disable rubocop in pre-commit hook for Docker-only development environment
  - `.husky/pre-commit` +6/-2
- **`7ede6d9e0`** — fix: resolve Docker container initialization failures in development environment
  - `docker-compose.yaml` +1/-0
  - `docker/entrypoints/rails.sh` +2/-0
  - `docker/entrypoints/vite.sh` +16/-0
  - `package.json` +1/-1
  - `pnpm-lock.yaml` +8/-8

### 2025-11-04
- **`a8b0bd9f6`** — chore: disable Z-API feature flag for compliance with base fork
  - `config/features.yml` +1/-1
- **`dbb35fcef`** — Merge branch 'codi-v4.7.0-fazer-ai.4' into codi-logto
- **`2b8982f1d`** — docs: add Logto integration planning and setup documentation
  - `.codi/LOGTO_INTEGRATION_PLAN.md` +917/-0
  - `.codi/LOGTO_SETUP_GUIDE.md` +534/-0
- **`0449c36d9`** — docs: add comprehensive Fazer.AI customizations analysis
  - `CUSTOM_FAZER-AI.md` +646/-0
- **`115da4afa`** — Update WhatsApp provider translations for English, Spanish, and Portuguese
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +1/-1
  - `app/javascript/dashboard/i18n/locale/es/inboxMgmt.json` +110/-4
  - `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` +24/-0
- **`8b5a062d0`** — feat: add Logto OAuth login button to login page
  - `app/javascript/dashboard/i18n/locale/en/login.json` +1/-0
  - `app/javascript/v3/components/LogtoOauth/Button.vue` +47/-0
  - `app/javascript/v3/views/login/Index.vue` +7/-1
- **`ce777597c`** — feat: add Logto OpenID Connect authentication support
  - `.env.example` +7/-0
  - `Gemfile` +1/-0
  - `app/views/layouts/vueapp.html.erb` +1/-0
  - `config/initializers/omniauth.rb` +16/-0
- **`7ec6ecf75`** — feat: add feature flags and environment configuration for providers
  - `.env.example` +5/-0
  - `app/javascript/dashboard/featureFlags.js` +5/-0
  - `config/features.yml` +21/-1
- **`3b92c24fd`** — feat: add Whatsmeow provider UI and channel configuration
  - `app/controllers/super_admin/instance_statuses_controller.rb` +7/-0
  - `app/javascript/dashboard/components/widgets/ChannelItem.vue` +10/-1
  - `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` +23/-0
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Email.vue` +1/-1
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Sms.vue` +43/-22
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` +30/-6
  - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsmeowWhatsapp.vue` +214/-0
- **`69de6e61c`** — feat: extend WhatsApp channel model to support Whatsmeow provider
  - `app/models/channel/whatsapp.rb` +6/-3
  - `db/migrate/20251104052854_add_whatsmeow_to_provider_connection_index.rb` +25/-0
  - `db/schema.rb` +2/-2
- **`d9fd3cc64`** — feat: add Whatsmeow WhatsApp provider integration
  - `.codi/WHATSMEOW_INTEGRATION.md` +265/-0
  - `app/jobs/webhooks/whatsapp_events_job.rb` +2/-0
  - `app/services/whatsapp/incoming_message_whatsmeow_service.rb` +69/-0
  - `app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb` +473/-0
  - `app/services/whatsapp/whatsmeow_handlers/connection_update.rb` +79/-0
  - `app/services/whatsapp/whatsmeow_handlers/helpers.rb` +215/-0
  - `app/services/whatsapp/whatsmeow_handlers/messages_update.rb` +122/-0
  - `app/services/whatsapp/whatsmeow_handlers/messages_upsert.rb` +196/-0
- **`1cb32886a`** — fix: resolved various issues while configuring a development environment
  - `.gitignore` +1/-0
  - `.npmrc` +1/-0
  - `Gemfile.lock` +1/-2
  - `docker-compose.production.yaml` +1/-1
  - `docker-compose.test.yaml` +1/-1
  - `docker-compose.yaml` +13/-13
  - `docker/Dockerfile` +4/-4
  - `docker/dockerfiles/rails.Dockerfile` +3/-2
  - `docker/dockerfiles/vite.Dockerfile` +9/-2
  - `pnpm-lock.yaml` +11/-11
- **`b9213821e`** — chore: update schema and model annotations after migrations
  - `app/models/campaign.rb` +1/-1
  - `app/models/channel/whatsapp.rb` +1/-1
  - `app/models/super_admin.rb` +1/-1
  - `app/models/user.rb` +1/-1
  - `db/schema.rb` +90/-90
- **`972d9034d`** — feat: enable web console access in development environment
  - `config/environments/development.rb` +6/-1
- **`7c859b22f`** — fix: remove unsafe ActsAsTaggableOn call from migration
  - `db/migrate/20231211010807_add_cached_labels_list.rb` +3/-2

### 2025-11-03
- **`1fae8cc99`** — Configure Git LFS for large binary files
  - `.gitattributes` +1/-0
  - `vendor/db/sentiment-analysis.onnx` (binary)
