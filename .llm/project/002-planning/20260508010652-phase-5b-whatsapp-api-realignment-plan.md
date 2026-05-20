---
Created: 2026-05-08T01:06:52Z
Operation: Phase 5b — Realign Click2Run WhatsApp provider in Chatwoot to the whatsapp-api OpenAPI 3.1 contract
Context: User identified ../whatsapp-api.git (Propria.Cloud's Go service, whatsmeow + WABA, 206 paths) as the new authoritative WhatsApp gateway. Existing app/services/whatsapp/providers/whatsapp_click2run_service.rb targets a legacy /chatwoot/{account_id}/inboxes/* surface that no longer exists. Reference TypeScript implementation lives in ../propriacloud.git/apps/minha/app/services/whatsapp.server.ts (5975 lines, 50+ methods, production-tested).
Related Files:
  - ../whatsapp-api.git.worktrees/develop/docs/openapi.yaml (20475 lines, 206 paths)
  - ../propriacloud.git/apps/minha/app/services/whatsapp.server.ts (reference TS client)
  - app/services/whatsapp/providers/whatsapp_click2run_service.rb (legacy 543-line service to rewrite)
  - app/services/whatsapp/click2run_handlers/{connection_update,helpers,messages_update,messages_upsert}.rb (legacy webhook handlers to rewrite)
  - app/services/whatsapp/incoming_message_click2run_service.rb (webhook entry — likely keep with new dispatcher)
  - app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Click2runWhatsapp.vue (UI — small adjustments)
  - app/models/channel/whatsapp.rb:30 — PROVIDERS already includes 'click2run'
  - CUSTOM_WHATSAPP-QRCODE.md (QR push-model architecture; revisit since whatsapp-api supports both push + pull)
---

# Phase 5b — Click2Run WhatsApp realignment to whatsapp-api OpenAPI

## Problem

The current Chatwoot Click2Run provider talks to a legacy "Click2Run delivery" backend whose surface is `/chatwoot/{account_id}/inboxes/{inbox_id}/...`. That backend has been **superseded by `whatsapp-api.git`** (a Go/whatsmeow service branded "Propria.Cloud Solution by Controle Digital") whose surface is **`/instances/...`** with `?instance_id=` query parameter — instances are first-class, multi-tenant, and support both whatsmeow web pairing and Meta WABA Cloud API in the same backend.

Reference implementation in TypeScript already exists at `propriacloud.git/apps/minha/app/services/whatsapp.server.ts`. The realignment is therefore a **port + adapt**, not a green-field design.

## Contract delta (current Click2Run vs whatsapp-api)

| Concern | Legacy Click2Run | whatsapp-api |
|---|---|---|
| Auth header | `X-API-Key` | `X-API-Key` ✓ same |
| Identity | `(account_id, inbox_id)` composite | single `instance_id` (UUID-style) |
| Path scope | `/chatwoot/{account_id}/inboxes/{inbox_id}/...` | `/instances/...?instance_id=...` |
| Create instance | POST `/chatwoot/{aid}/inboxes` with admin token + webhook embed | POST `/instances/create` `{instance_id, name, phone, group_id, custom_id, waba}` |
| Connect (start pairing) | POST `/.../inboxes/{id}/connect` | POST `/instances/connect?instance_id=...` |
| QR retrieval | webhook push only | both: webhook push (`connection.update` event) + pull GET `/instances/pair/qrcode` |
| Phone-code pairing | not supported | POST `/instances/pair/phonecode?instance_id=...` `{phone}` |
| Disconnect | POST `/.../inboxes/{id}/disconnect` | POST `/instances/disconnect?instance_id=...` |
| Unpair (logout) | not supported | POST `/instances/unpair?instance_id=...` |
| Delete | DELETE `/.../inboxes/{id}` | POST `/instances/delete?instance_id=...` |
| Send text (Web) | POST `/.../messages/send/text` `{to, message, quoted_message_id}` | POST `/messages/send?instance_id=...` `{to: {user, server}, message: {conversation: text}}` |
| Send text (WABA) | n/a | POST `/messages/send?instance_id=...` `{to: "5511…", message: {text: "..."}}` |
| Send media (Web) | POST `/.../messages/send/media` (base64 in body) | POST `/messages/send-media?instance_id=...` `{to: {user}, media: [{type, data\|url, caption, file_name}]}` |
| Send media (WABA) | n/a | POST `/messages/send` with `{message: {image: {link, caption}}}` etc. |
| Send reaction | POST `/.../messages/send/reaction` | POST `/messages/react?instance_id=...` |
| Mark read | POST `/.../messages/mark-read` | POST `/messages/mark-read?instance_id=...` (or `/chats/mark-read`) |
| Typing/presence | PATCH `/.../presence` | POST `/presence/send` or `/presence/chat?instance_id=...` |
| Profile picture | GET `/.../profile-picture/{jid}` | GET `/contacts/profile-picture?instance_id=...&jid=...` |
| On WhatsApp check | GET `/.../on_whatsapp/{phone}` | GET `/contacts/onwhatsapp?instance_id=...&phone=...` |
| Media download | GET `/.../media/{message_id}` | (TBD — confirm in OpenAPI; probably under `/messages/{id}/media` or in webhook payload) |
| Webhook config | embedded in create call | separate POST `/webhooks?instance_id=...` `{url, events, enabled, secret?}` |
| Health | GET `/health` (top-level) | GET `/health` or `/health/ready` ✓ same shape |
| Response shape | varies | mostly `{success, data: {...}, timestamp}`; sometimes unwrapped — handle both |

## Architectural decisions

### A1. Single `instance_id` per WhatsApp channel
Store as `provider_config['instance_id']` (jsonb — no migration needed). Generate UUID v4 at channel creation if absent. Persist for the channel's lifetime; re-create on disconnect/recreate maps to the same `instance_id`.

### A2. Web-only first; defer WABA
The whatsapp-api supports both modes via the `waba: bool` flag. **Initial port targets `waba: false`** (whatsmeow / QR pairing) — that matches what Click2Run already does today. WABA / Embedded Signup is a separate phase (call it 5b.2).

### A3. Drop the Chatwoot admin-token plumbing
The current service plumbs the Chatwoot admin user token + Chatwoot API URL into the Click2Run backend so it could call back. The new whatsapp-api does not need that — webhooks are the only Chatwoot-facing surface, and Chatwoot already exposes `/webhooks/whatsapp/{phone_number}`. Remove `find_account_admin` and the `admin_id`/`admin_token`/`api_url` body fields from `setup_channel_provider`.

### A4. QR delivery — keep push, add pull as fallback
`CUSTOM_WHATSAPP-QRCODE.md` documents the push model (Baileys-style). whatsapp-api supports the same push (`connection.update` event with `qr_code` field). **Keep the push handler** and additionally poll `/instances/pair/qrcode` only when the channel UI requests a re-render after timeout. Frontend already polls Chatwoot's own channel API every 2s — no UI change needed for the happy path.

### A5. Webhook configuration becomes a separate call
After `POST /instances/create`, the new flow is:
1. `POST /instances/create` with `{instance_id, name, phone}`
2. `POST /webhooks?instance_id=...` `{url: ${FRONTEND_URL}/webhooks/whatsapp/${phone_number}, events: [...], enabled: true, secret: ${webhook_verify_token}}`
3. `POST /instances/connect?instance_id=...`

If any step fails, roll back via `POST /instances/delete?instance_id=...`.

### A6. Event schema mapping
whatsapp-api emits 105 event types via webhooks. Our `click2run_handlers/` only handles a handful. The minimum mapping for parity with current Baileys handlers:
- `connection.update` → `process_connection_update` (existing)
- `messages.upsert` → `process_messages_upsert` (existing)
- `messages.update` → `process_messages_update` (existing)
- `presence.update` → typing indicators (existing helper)
- `messaging-history.set` → optional; defer

Spec the event prefix-to-method mapping in `incoming_message_click2run_service.rb#perform` (the existing pattern handles this dynamically via `event.gsub(/[\.-]/, '_')` — keep it).

### A7. Webhook signature verification
whatsapp-api supports a webhook `secret` field (HMAC). Current `webhookVerifyToken` matching in `incoming_message_click2run_service.rb` is a token-equality check on the body. Move to HMAC-SHA256 if the secret is configured; fall back to token-equality for backwards compat.

## Implementation phases

### 5b.1 — Web-only port (the bulk of the work)
1. **Service rewrite** (`whatsapp_click2run_service.rb`):
   - Strip the `/chatwoot/...` paths; switch to `/instances/...?instance_id=...`
   - Drop admin-token plumbing
   - Add helpers: `instance_id` (read or generate UUID), `instance_query` (`?instance_id=...`), `unwrap_response` (handle `{success, data:{...}}` and unwrapped shapes)
   - Implement: `setup_channel_provider` (3-call sequence: create → set_webhook → connect), `disconnect_channel_provider` (disconnect + delete), `send_text_message`, `send_media_message`, `send_reaction_message`, `read_messages`, `toggle_typing_status`, `get_profile_pic`, `on_whatsapp`, `media_url`
   - Keep `with_error_handling` wrapper pattern

2. **Webhook handlers** (`click2run_handlers/*.rb`):
   - Adjust payload shape to whatsapp-api's event schema (mostly compatible since both are whatsmeow-derived)
   - Update `connection_update.rb` to read `qr_code` field (whatsapp-api naming) in addition to `qrDataUrl` (legacy)

3. **Webhook entry** (`incoming_message_click2run_service.rb`):
   - Add HMAC verification path alongside token-equality
   - Confirm event-prefix → method-name dispatcher still works for whatsapp-api's event names

4. **UI** (`Click2runWhatsapp.vue`):
   - Confirm the QR display polls channel state correctly (no change expected)
   - Optional: surface phone-code pairing as alternative pathway in a follow-up commit

5. **Channel model** (`app/models/channel/whatsapp.rb`):
   - On channel create, if `provider == 'click2run'` and `provider_config['instance_id']` blank, populate with `SecureRandom.uuid`
   - Already has `webhook_verify_token` auto-population for click2run (line 163) — extend to also seed `instance_id`

6. **Tests**:
   - Mirror `spec/services/whatsapp/providers/whatsapp_baileys_service_spec.rb` structure
   - Use `WebMock` to stub `/instances/...` endpoints

7. **Docs**:
   - Update `CUSTOM_CLICK2-RUN.md` and `CUSTOM_CLICK2RUN-API.md` to reflect the new contract
   - Update `CUSTOM_WHATSAPP-QRCODE.md` to note pull-fallback support

### 5b.2 — WABA / Embedded Signup support (deferred)
- New env vars: `META_WABA_API_URL`, `META_WABA_API_KEY` (mirroring propriacloud's split)
- New channel field: `provider_config['waba'] = true|false`
- WABA-specific signup flow (`/api/v1/meta/{app_id}/waba/signup`) — separate engagement
- Cross-reference propriacloud's `wabaSignup`, `getWabaOnboardingStatus`, `requestPhoneVerificationCode`, `submitPhoneVerificationCode` implementations

### 5b.3 — Optional follow-ups (deferred)
- Phone-code pairing UI
- Group management (whatsapp-api has `/groups/*`)
- Newsletter management
- Audit & recovery (`/instances/audit/*`, `/appstate/recovery`)
- Templates (Web side via `/messages/send` with template payload, WABA side via `/templates/*`)

## Env vars introduced/changed

```bash
# whatsapp-api Web (whatsmeow) — replaces CLICK2RUN_PROVIDER_DEFAULT_URL/_API_KEY (keep aliases for backwards compat during transition)
WHATSAPP_API_URL=https://whatsapp-leadsok-0.propria.cloud
WHATSAPP_API_KEY=

# whatsapp-api WABA (Meta Cloud API) — phase 5b.2
META_WABA_API_URL=
META_WABA_API_KEY=

# Backwards-compat aliases (cascade in service code, drop after migration)
CLICK2RUN_PROVIDER_DEFAULT_URL=  # → WHATSAPP_API_URL
CLICK2RUN_PROVIDER_DEFAULT_API_KEY=  # → WHATSAPP_API_KEY
```

The cascade in code: `WHATSAPP_API_URL` > `CLICK2RUN_PROVIDER_DEFAULT_URL`; same for keys. Mirrors the existing CLICK2RUN_OPENID → LOGTO env-var cascade pattern, so users mid-migration keep working.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Existing Chatwoot installations have channels with `provider_config[]` lacking `instance_id` | Backfill on first request: if missing, generate + persist + re-create on backend |
| whatsapp-api OpenAPI surface is large (206 paths); our port covers ~12 | Scope: only port what current `whatsapp_click2run_service.rb` exposes; defer the rest |
| Webhook event schema differences between legacy and whatsapp-api | The reference TS client confirms whatsmeow event names line up; spot-check `messages.upsert`, `messages.update`, `connection.update` payloads against handlers |
| `Click2runWhatsapp.vue` may show stale state during transition | UI polls channel state (already does) — no transition-window change |
| Loss of admin-token plumbing means whatsapp-api can no longer call Chatwoot | Confirmed not needed: data flow is one-way (Chatwoot → whatsapp-api for actions, whatsapp-api → Chatwoot via webhook). The legacy admin token was for old Click2Run delivery, not whatsapp-api. |
| WABA users in the wild | None — WABA is a 5b.2 deferred phase; no current WABA Click2Run users |

## Estimate

- 5b.1 (Web port): ~1-2 days of focused work, including tests. The reference TS client makes this a port, not a research task.
- 5b.2 (WABA): ~2-3 days, separate engagement.
- 5b.3 (groups/templates/audit): on-demand.

## Out of scope

- 5c (Click2Run → Propria Cloud rebrand) — env-var driven, decoupled from this work
- Phase 5a-followup (Logto credentials) — independent
- Direct WABA Embedded Signup UI in Chatwoot — defer to 5b.2
- whatsapp-api project changes — not touched; this is purely a Chatwoot-side port

## Acceptance criteria

- [ ] `bundle exec rspec spec/services/whatsapp/providers/whatsapp_click2run_service_spec.rb` green against WebMock stubs of the new contract
- [ ] Click2Run inbox creation in Chatwoot UI reaches QR display via the new flow (manual smoke)
- [ ] Outgoing text + media + reaction messages reach the destination via whatsapp-api logs
- [ ] Incoming webhook events from whatsapp-api land in Chatwoot conversations
- [ ] Existing Click2Run channels with no `instance_id` self-heal on first connect
- [ ] CUSTOM_CLICK2-RUN.md / CUSTOM_CLICK2RUN-API.md / CUSTOM_WHATSAPP-QRCODE.md reflect the new surface
- [ ] Conclusion file written under `.llm/conclusions/`
