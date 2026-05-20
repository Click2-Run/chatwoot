---
Created: 2026-05-08T01:11:38Z
Task: Phase 5b.1 — Port Click2Run WhatsApp provider to whatsapp-api OpenAPI 3.1
Status: CODE COMPLETE; user-side validation pending in Docker
Impact: Click2Run channels now talk to the current Propria.Cloud whatsapp-api gateway, replacing the legacy /chatwoot/{aid}/inboxes surface. WABA support deferred to 5b.2.
Related Files:
  - .llm/project/002-planning/20260508010652-phase-5b-whatsapp-api-realignment-plan.md
  - app/services/whatsapp/providers/whatsapp_click2run_service.rb (rewritten)
  - app/models/channel/whatsapp.rb (instance_id seed)
  - .env.example, .env (env-var cascade)
---

# Phase 5b.1 — Click2Run WhatsApp port complete (Web/whatsmeow mode)

## Executive Summary

The Click2Run WhatsApp provider service in Chatwoot has been ported from the
legacy `/chatwoot/{account_id}/inboxes/{inbox_id}/...` surface to the current
**whatsapp-api OpenAPI 3.1 contract** (`/instances/...?instance_id=...`). The
new contract is the production Propria.Cloud Go service powered by whatsmeow.
Reference: TypeScript client `propriacloud.git/apps/minha/app/services/whatsapp.server.ts`.

This covers Phase 5b.1 (Web/whatsmeow). WABA / Embedded Signup is queued as 5b.2.

## Implementation Details

### Files changed
- `app/services/whatsapp/providers/whatsapp_click2run_service.rb` — full rewrite (288 deletions, 189 insertions). All 12 methods remapped to the new contract.
- `app/models/channel/whatsapp.rb:163-164` — `before_validation :ensure_webhook_verify_token` now also seeds `provider_config['instance_id']` with `SecureRandom.uuid` for click2run channels (jsonb — no migration).
- `.env.example`, `.env` — added `WHATSAPP_API_URL`, `WHATSAPP_API_KEY`, `META_WABA_API_URL`, `META_WABA_API_KEY` with cascade fallback to `CLICK2RUN_PROVIDER_DEFAULT_*`.

### Contract mapping (key endpoints)

| Method | Old path | New path |
|---|---|---|
| `setup_channel_provider` | POST `/chatwoot/{aid}/inboxes` + connect | POST `/instances/create` → POST `/webhooks?instance_id=` → POST `/instances/connect?instance_id=` |
| `disconnect_channel_provider` | POST `/.../disconnect` + DELETE `/.../inboxes/{id}` | POST `/instances/disconnect` + POST `/instances/delete` |
| `send_text_message` | POST `/.../messages/send/text` | POST `/messages/send?instance_id=...` `{to:{user,server}, message:{conversation:text}}` |
| `send_media_message` | POST `/.../messages/send/media` | POST `/messages/send-media?instance_id=...` `{to:{user}, media:[{type,data,mime_type,caption,file_name}]}` |
| `send_reaction_message` | POST `/.../messages/send/reaction` | POST `/messages/react?instance_id=...` |
| `read_messages` | POST `/.../messages/mark-read` | POST `/messages/mark-read?instance_id=...` |
| `toggle_typing_status` | PATCH `/.../presence` | POST `/presence/chat?instance_id=...` |
| `get_profile_pic` | GET `/.../profile-picture/{jid}` | GET `/contacts/profile-picture?instance_id=...&jid=...` |
| `on_whatsapp` | GET `/.../on_whatsapp/{phone}` | GET `/contacts/onwhatsapp?instance_id=...&phone=...` |
| `media_url` | `/.../media/{id}` | `/messages/{id}/media?instance_id=...` |
| `validate_provider_config?` | GET `/.../inboxes` | GET `/health` |

### Decisions implemented
- **Single `instance_id` per channel**: jsonb-stored UUID, seeded by the channel callback. Self-healing backfill in the service if missing.
- **Three-call setup**: instance create → webhook config → connect. Idempotent on 409.
- **Drop admin-token plumbing**: whatsapp-api has no need to call back into Chatwoot.
- **QR push-model preserved**: the existing `connection_update.rb` handler already consumes `qr_code` (the whatsapp-api naming), no handler change required.
- **Webhook secret**: passed in via the new `/webhooks` registration call, sourced from existing `provider_config['webhook_verify_token']`. Token-equality check in `incoming_message_click2run_service.rb` continues to work.
- **Response unwrapping**: helper `unwrap()` handles both `{success, data:{...}, timestamp}` and unwrapped shapes.
- **Env-var cascade**: `WHATSAPP_API_URL` / `WHATSAPP_API_KEY` are primary; `CLICK2RUN_PROVIDER_DEFAULT_URL` / `..._API_KEY` are kept as backwards-compat aliases. Same pattern as the existing `CLICK2RUN_OPENID_*` → `LOGTO_*` cascade — frictionless transition.

### Files NOT changed (intentional)
- `app/services/whatsapp/incoming_message_click2run_service.rb` — verify-token logic and event dispatcher work as-is.
- `app/services/whatsapp/click2run_handlers/connection_update.rb` — already reads `qr_code` (whatsapp-api naming).
- `app/services/whatsapp/click2run_handlers/messages_upsert.rb` / `messages_update.rb` / `helpers.rb` — whatsmeow-derived event payloads are compatible.
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Click2runWhatsapp.vue` — consumes Chatwoot's own channel state, already polling — no UI change.

## Testing & Validation

### What was validated
- [x] Code review against the TypeScript reference implementation
- [x] All 12 service methods map cleanly to documented OpenAPI paths
- [x] Channel model `before_validation` callback now seeds `instance_id` for click2run
- [x] No conflict markers / no syntax issues that grep-level review can find
- [x] Env vars added to both `.env.example` and `.env` with cascade comment

### What requires Docker / live environment (user-side)
- [ ] `bundle exec rspec spec/services/whatsapp/providers/whatsapp_click2run_service_spec.rb` (existing spec needs update to mock the new endpoints — see Future Work)
- [ ] `ruby -c app/services/whatsapp/providers/whatsapp_click2run_service.rb` (no Ruby on this host)
- [ ] Manual smoke: create a Click2Run inbox in Chatwoot UI → expect QR code via webhook push
- [ ] Send-text round-trip
- [ ] Send-media round-trip
- [ ] Read-receipt round-trip
- [ ] Disconnect → delete → recreate flow with the same `instance_id`

## Monitoring & Health

After deploying:

```bash
# In rails console
ch = Channel::Whatsapp.where(provider: 'click2run').first
ch.provider_config['instance_id']                                   # should be UUID
ch.provider_service.validate_provider_config?                       # GET /health → true

# Watch the whatsapp-api side
curl -H "X-API-Key: $WHATSAPP_API_KEY" $WHATSAPP_API_URL/instances?instance_id=$ID
```

## Success Metrics

| Metric | Before | After |
|---|---|---|
| Service path scope | `/chatwoot/{aid}/inboxes/{iid}/...` | `/instances/...?instance_id=...` |
| Setup calls | 2 (create + connect) | 3 (create + register webhook + connect) |
| Admin-token plumbing | yes (admin_id, admin_token, api_url) | no |
| Per-channel identity | composite (account+inbox) | single UUID `instance_id` |
| Service file size | 543 lines | 437 lines (-19%) |
| WABA support | no | scaffolded via env (5b.2) |
| Backwards-compat env vars | n/a | yes (`CLICK2RUN_PROVIDER_DEFAULT_*` aliases preserved) |

## Future Work

### Phase 5b.2 — WABA / Embedded Signup (deferred)
- Use `META_WABA_API_URL` / `META_WABA_API_KEY` (already documented in env)
- New flow: `POST /api/v1/meta/{app_id}/waba/signup` to upgrade a Web instance to WABA in-place
- Channel field `provider_config['waba'] = true` to switch send/receive paths
- Reference: `propriacloud.git/apps/minha/app/services/whatsapp.server.ts:912-1116`

### Phase 5b.3 — Optional follow-ups
- Phone-code pairing UI (whatsapp-api supports `POST /instances/pair/phonecode`)
- Group management endpoints (`/groups/*`)
- Audit/recovery endpoints (`/instances/audit/*`, `/appstate/recovery`)
- Spec rewrite for `whatsapp_click2run_service_spec.rb` against WebMock stubs of the new contract

### Test spec
The existing `spec/services/whatsapp/providers/whatsapp_click2run_service_spec.rb` (if present) was written against the legacy contract. It needs WebMock updates to match the new endpoints. Defer to next implementation pass — this conclusion is for the production code only.

## References

- Plan: `.llm/project/002-planning/20260508010652-phase-5b-whatsapp-api-realignment-plan.md`
- OpenAPI source of truth: `../whatsapp-api.git.worktrees/develop/docs/openapi.yaml` (20475 lines, 206 paths)
- TS reference client: `../propriacloud.git/apps/minha/app/services/whatsapp.server.ts` (5975 lines)
- `CUSTOM_WHATSAPP-QRCODE.md` — QR push-model architecture, still valid
- `CUSTOM_CLICK2-RUN.md` / `CUSTOM_CLICK2RUN-API.md` — should be revisited in a follow-up commit to reflect the new contract
