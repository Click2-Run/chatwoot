# Própria Cloud — WhatsApp Integration Reference

> **Audience:** humans + LLM agents working on this fork.
> **Scope:** the `propriacloud` provider on `Channel::Whatsapp`, talking to the
> Própria Cloud `whatsapp-api` Go service (whatsmeow + Web pairing) at
> `../whatsapp-api.git` worktree `develop`, OpenAPI v1.4.0
> (`docs/openapi.yaml`, ~20.6k lines).
> **Companion docs:**
> [`CUSTOM-WHATSAPP-API.md`](./CUSTOM-WHATSAPP-API.md) (high-level rationale),
> [`CUSTOM-CLICK2RUN-API.md`](./CUSTOM-CLICK2RUN-API.md) (legacy click2run flow,
> still useful for historical context).
>
> **Last validated:** 2026-05-10 against
> `whatsapp-api.git.worktrees/develop @ a5f5471d` and
> `chatwoot.git @ codi-v4.13.0-fazer-ai.66 / c6e127b8`.

---

## 0. Status legend

| Marker | Meaning |
| --- | --- |
| ✅ | Verified working / spec-compliant |
| ⚠️ | Works but with caveats, gaps, or fragile assumptions |
| 🔴 | **Defect** — confirmed mismatch with the upstream contract; behavior is broken or will break |
| 🟡 | Improvement opportunity — not strictly broken |
| 🧭 | Design choice worth knowing |

A consolidated **Pending Issues** table is in [§13](#13-pending-issues--action-items).

---

## 1. Architecture at a glance

```
                ┌──────────────────────────────────────┐
                │ whatsapp-api (Go + whatsmeow)        │
                │   Própria Cloud, OpenAPI 3.1 v1.4.0  │
                │                                      │
                │   /api/v1/instances/*                │
                │   /api/v1/messages/*                 │
                │   /api/v1/sync/*                     │
                │   /api/v1/media/download             │
                │   /api/v1/webhooks                   │
                └──────────────┬───────────────────────┘
                               │ X-API-Key + X-Platform: propriacloud
                               │ JSON; HMAC-SHA256 (X-Webhook-Signature)
                               ▼
        ┌──────────────────────────────────────────────────┐
        │ Chatwoot (Ruby on Rails 7, Sidekiq, ActiveStorage)│
        │                                                  │
        │  Channel::Whatsapp(provider='propriacloud')      │
        │    ├─ Whatsapp::Providers::WhatsappPropriacloud  │
        │    │     (outbound + setup + status)             │
        │    ├─ Whatsapp::IncomingMessagePropriacloud      │
        │    │     (HMAC validate + custom_id + dispatch)  │
        │    │     ├── ConnectionUpdate                    │
        │    │     ├── MessagesUpsert                      │
        │    │     ├── MessagesUpdate                      │
        │    │     ├── MessagesFailure                     │
        │    │     ├── UserChanged                         │
        │    │     ├── Appstate                            │
        │    │     ├── HistorySync                         │
        │    │     └── InstanceRecovery                    │
        │    └─ Whatsapp::Propriacloud::HistoryBackfillJob │
        │           → HistoryBackfillService → /sync/*     │
        └──────────────────────────────────────────────────┘
```

🧭 **Identification model.** One Chatwoot inbox ⇄ one whatsapp-api instance.
The link is `provider_config['instance_id']`, seeded from the
`Channel::Whatsapp` PK as a string for new inboxes
(`whatsapp_propriacloud_service.rb:777`); legacy inboxes that already had
a UUID keep it. We also send the Chatwoot `account_id` as `custom_id`
(`whatsapp_propriacloud_service.rb:179`); it is verified on every inbound
event (defense-in-depth on top of HMAC).

🧭 **State model.** Two-axis:
- `connection_state ∈ {disconnected, connecting, connected, disconnecting}` (websocket)
- `pair_state ∈ {unpaired, pairing, paired, unpairing}` (device link)

Chatwoot persists both in `provider_connection` and additionally derives a
legacy single-axis `connection ∈ {open, connecting, close, reconnecting}`
for older UI code (`whatsapp_propriacloud_service.rb:573`).

🧭 **Trust path.** Two stacked guarantees on every inbound webhook:
1. HMAC-SHA256 of the raw body against the per-channel
   `webhook_verify_token` (the secret registered with the API).
2. `custom_id` equality with the inbox's `account_id` (cross-tenant
   defense; `incoming_message_propriacloud_service.rb:72`).

---

## 2. Configuration & environment

### 2.1 Connection credentials

| Field | Source | Notes |
| --- | --- | --- |
| API base URL | `provider_config['provider_url']` → `PROPRIACLOUD_API_URL` | DB-first; aliases `WHATSAPP_API_URL`, `PROPRIACLOUD_PROVIDER_DEFAULT_URL`, `CLICK2RUN_PROVIDER_DEFAULT_URL` are migrated into the canonical row on first read. URL must include the `/api/v1` prefix. |
| API key (`X-API-Key`) | `provider_config['api_key']` → `PROPRIACLOUD_API_KEY` | Same alias chain; aliases `WHATSAPP_API_KEY`, `PROPRIACLOUD_PROVIDER_DEFAULT_API_KEY`, `CLICK2RUN_PROVIDER_DEFAULT_API_KEY`. |
| Webhook callback base URL | `PROPRIACLOUD_WEBHOOK_BASE_URL` → falls back to `FRONTEND_URL` → `http://localhost:3000` | This is the URL the Go service POSTs back to. Must be reachable **from the API container**, not the user's browser (e.g. `http://host.docker.internal:3000` in compose). |

Resolution lives in
[`whatsapp_propriacloud_service.rb:46-82`](app/services/whatsapp/providers/whatsapp_propriacloud_service.rb#L46-L82).

### 2.2 Per-channel toggles (`provider_config`)

| Key | Default | Purpose |
| --- | --- | --- |
| `instance_id` | string id of `Channel::Whatsapp` (`SecureRandom.uuid` for legacy rows that already had one) | maps to whatsapp-api instance |
| `webhook_verify_token` | `SecureRandom.hex(16)` (32-char) | HMAC-SHA256 secret |
| `mark_as_read` | `true` for propriacloud | controls whether Chatwoot relays read receipts |
| `presence_subscribe` | `true` for propriacloud | informational; **see [§13 PEND-15]** |
| `paired_at` | set on `pairing.success` / `connection.connected` | gates auto-recovery handler |
| `pair_locked_until` | set when `/instances/pair/phonecode` returns 429 | UI-side cooldown gating |
| `pair_lock_code` | `PAIR_RATE_LIMITED` / `PAIR_DEVICE_LIMIT` | lock reason |
| `history_backfill_completed_at` | set when `HistoryBackfillService` finishes | idempotency gate |
| `history_sync_started_at` / `history_sync_completed_at` | set on the matching webhook events | UI surface only |

### 2.3 Persisted runtime state (`provider_connection`)

Mirrored from `/instances/status`:
`connection`, `connection_state`, `pair_state`, `is_paired`, `is_connected`,
`qr_data_url`, `error`. Updated through
`Channel::Whatsapp#update_provider_connection!` which **bypasses
validation** (`validate: false`) so a transient API blip does not flip the
inbox into "Invalid Credentials".

### 2.4 Storage backend (media)

ActiveStorage backend is `ENV['ACTIVE_STORAGE_SERVICE']`, defaulting to
`local` (`config/environments/{development,production}.rb`). With
defaults, downloaded media lands on the Rails container's filesystem under
`<rails_root>/storage/`. For HA / multi-replica deployments, override to
`amazon`/`s3_compatible`/`google`/`microsoft` so attachments are not
trapped on a single node. See `config/storage.yml` for the available
services.

---

## 3. Endpoint compatibility matrix (Chatwoot → whatsapp-api)

OpenAPI source: `whatsapp-api.git.worktrees/develop/docs/openapi.yaml`.
All endpoints are prefixed with `/api/v1`. Every call carries
`?instance_id=<id>` plus `X-API-Key`.

| Chatwoot caller | Endpoint | Method | Status | Notes |
| --- | --- | --- | --- | --- |
| `default_url + /health` (`status` class method) | `/health` | GET | ✅ | Used as a health probe before setup |
| `setup_channel_provider` | `/instances/create` | POST | ✅ | Body `{instance_id, name, phone, custom_id}`. Tolerates 200/201/409. Single 500 retry after 500ms (race with prior partial insert). |
| `setup_channel_provider` → `register_webhook!` | `/webhooks` | POST | ⚠️ | Sends `{scope: 'instance', instance_id, url, events, enabled, active, secret}`. The `enabled` field is undocumented (OpenAPI has only `active`); silently ignored. **PEND-09**. |
| `setup_channel_provider` | `/instances/connect` | POST | ✅ | Empty body. |
| `setup_channel_provider` (`fetch_qr: true`) | `/instances/pair/qrcode` | GET | ✅ | Reads `body['img'] \|\| body['code'] \|\| body['qr_code']`. ⚠️ Only `img` and `code` exist on response; `code` is plain text, **not** a base64 image — using it as a `data:image/png;base64,...` source produces a broken image. **PEND-10**. |
| `disconnect_channel_provider` | `/instances/disconnect` | POST | ✅ | Best-effort; logged on failure. |
| `disconnect_channel_provider` | `/instances/delete` | POST | ✅ | Hard teardown on inbox destroy. |
| `disconnect_only` | `/instances/disconnect` | POST | ✅ | UI button — keeps the device pair. |
| `unpair_only` | `/instances/unpair` | POST | ✅ | UI button — drops the device pair, keeps the instance. Also clears `provider_config['paired_at']`. |
| `request_phone_pairing_code` | `/instances/pair/phonecode` | POST | ⚠️ | Body `{phone}`. Reads response `body['code'] \|\| body['pairingCode'] \|\| body['pairing_code']` and `body['expires_in'] \|\| body['timeout']`. OpenAPI `PhoneCodeResponse` exposes only `{code, success}` — **no `expires_in`/`timeout`**, so the dashboard countdown will always be empty. **PEND-11**. Rate-limit handling (429 / `PAIR_RATE_LIMITED`) is correct. |
| `refresh_status_from_api!` / `reconcile!` | `/instances/status` | GET | ✅ | Reads `data.status.{connection_state, pair_state, is_paired, is_connected}`. |
| `send_text_message` | `/messages/send` | POST | ✅ | Body `{to: {user, server}, message: {conversation}, context_info?: {stanza_id}}`. Reply quoting works for 1:1; ⚠️ group `participant` not set — fine for current scope (no groups). |
| `send_media_message` | `/messages/send-media` | POST | ✅ | Body `{to, media: [{type, data, mime_type, caption?, file_name?, ptt?}]}`. PTT auto-detected from `audio/(ogg\|opus\|webm)`. **Outbound is base64-encoded** (data URL); for large attachments this doubles wire size — see [§7.4](#74-outbound-media-tradeoffs). 🟡 |
| `send_reaction_message` | `/messages/react` | POST | ✅ | Body `{chat, sender, message_id, reaction}`. Both `chat` and `sender` are JIDParam structs. Response: reads `reaction_id \|\| message_id` — only `message_id` actually exists, but the `\|\|` chain falls back correctly. |
| `read_messages` | `/messages/mark-read` | POST | ✅ | Body `{chat: JIDParam, message_ids: []}`. Note: per spec, `chat` accepts JIDParam OR string; we use JIDParam. |
| `edit_message` | `/messages/edit` | PUT | ✅ | Body `{chat, message_id, new_content: {conversation}}`. WhatsApp 20-min edit window is enforced by the API and surfaces as a 4xx that the agent UI shows. |
| `delete_message` | `/messages/revoke` | DELETE | ✅ | Body `{chat, message_id}`. |
| `toggle_typing_status` | `/presence/chat` | POST | ✅ | Body `{chat: JIDParam, state: composing\|recording\|paused}`. |
| `update_presence` | (no-op) | — | 🧭 | Account-level presence (online/offline) is not relayed; whatsapp-api exposes `/presence/send` but Chatwoot doesn't use it. |
| `get_profile_pic` | `/contacts/profile-picture` | POST | ✅ | Body `{jid, preview: false}`. Reads `body['url']`. |
| `on_whatsapp` | `/contacts/onwhatsapp` | POST | 🔴 | Body `{phones: [phone]}`. Reads `entry['is_in'] \|\| entry['exists'] \|\| entry['is_registered']` — but the API field per `IsOnWhatsAppResponse` is `is_on_whatsapp`. **None of the keys we read exist**; the call always returns `exists: false` regardless of reality. **PEND-04**. |
| `download_media` | `/media/download` | POST | 🔴 | **Two compounding defects, see §7.1**. Body wraps the whole webhook message under `{message: raw_message}` — the Go normalizer (`client/message_converter.go:101`) accepts only flat (`{url, mediaKey, mimetype, ...}`) or wrapped (`{imageMessage: {...}}`); our shape is rejected with `unable to detect media type from payload`. Even if the request succeeded, the response read uses `body['data'] \|\| body['body'] \|\| body['file']` while the API field per `DownloadMediaResponse` is `base64`. **PEND-01 (request) + PEND-02 (response)**. |
| `sync_contacts` (paged) | `/sync/contacts` | GET | ✅ | `?page,page_size,instance_id`. |
| `sync_conversations` (paged) | `/sync/conversations` | GET | ✅ | Same. |
| `sync_messages` (paged) | `/sync/messages` | GET | ⚠️ | `?chat_jid,page,page_size`. ⚠️ No time window — backfill walks entire history per chat. **PEND-12**. |
| `sync_push_names` (paged) | `/sync/push-names` | GET | ⚠️ | Coded but **not currently called** by `HistoryBackfillService`. **PEND-13**. |
| `list_labels` (paged) | `/labels` | GET | ✅ | Tenant-scoped (no `instance_id` qs). |
| `sync_webhook_subscription!` (reconcile) | `/webhooks?scope=instance&instance_id=X` | GET | ✅ | List for the instance, find the canonical row, PATCH it; delete orphans. |
| `sync_webhook_subscription!` (reconcile) | `/webhooks/{id}` | PATCH | ✅ | Updates `{url, events, enabled, active}`. |
| `sync_webhook_subscription!` (reconcile) | `/webhooks/{id}` | DELETE | ✅ | Removes orphans (e.g. legacy `host.docker.internal` URL after a host change). |

🧭 **Endpoints we explicitly do not use yet** (worth knowing they exist):
`/instances/recovery` (we react to its webhook events, but don't trigger
it), `/instances/restart`, `/instances/recreate`,
`/instances/audit/*`, `/runtime/*`, `/sync/sessions`,
`/sync/sessions/latest`, `/sync/status`,
`/sync/request-history` (**important — see [§5](#5-history-sync)**),
`/sync/group-participants`, `/sync/past-participants`,
`/sync/global-settings`, `/media/upload-limits`, `/media/thumbnail`,
`/media/download-path`, `/messages/build-revoke`, `/messages/revoke-others`,
`/messages/generate-id`, `/contacts/info`,
`/contacts/business-profile`, `/contacts/blocklist`, `/groups/*`,
`/newsletters/*`, `/labels/colors`, `/labels/info`, `/labels/chat`,
`/notes/*`, `/polls/*`, `/calls/*`, `/privacy/*`, `/system/*`,
`/appstate/*`, `/meta/waba/*`. Most are out of scope for current product;
`/sync/request-history` is the notable gap.

---

## 4. Webhook subscription & event filtering

### 4.1 Registration

`register_webhook!` (`whatsapp_propriacloud_service.rb:813-847`) POSTs to
`/webhooks` with:

```json
{
  "scope": "instance",
  "instance_id": "<channel.id>",
  "url": "<PROPRIACLOUD_WEBHOOK_BASE_URL>/webhooks/whatsapp/<phone_number>",
  "events": [...DEFAULT_WEBHOOK_EVENTS...],
  "enabled": true,
  "active": true,
  "secret": "<32-char hex>"
}
```

- `409` is treated as success (idempotent re-registration).
- After registration (or 409), `sync_webhook_subscription!` reconciles
  the canonical row's `{url, events}` and deletes orphans — this is what
  protects you when `PROPRIACLOUD_WEBHOOK_BASE_URL` changes (e.g.
  switching from a legacy compose-network alias to
  `host.docker.internal:3000`).
- Secret is the per-channel `webhook_verify_token` (32 hex chars). The
  spec requires ≥16 chars — ✅.
- ⚠️ `enabled` is not in the OpenAPI schema (`active` is); silently
  ignored. **PEND-09**.

### 4.2 Subscribed events

`DEFAULT_WEBHOOK_EVENTS`
(`whatsapp_propriacloud_service.rb:89-136`) is **explicitly enumerated**,
not wildcarded. This is intentional — fewer Sidekiq enqueues for events
we'd drop anyway (privacy, newsletter, call, system, group, poll). Trade-off:
when whatsapp-api adds a new sub-event under one of our subscribed
prefixes (e.g. `connection.cooldown` someday), we won't see it until the
list is updated.

The full subscription, grouped by domain:

| Domain | Events |
| --- | --- |
| Connection | `connection.connected`, `disconnected`, `logged_out`, `stream_replaced`, `connect_failure`, `client_outdated`, `temporary_ban`, `stream_error`, `keepalive_timeout`, `keepalive_restored` |
| Pairing | `pairing.qrcode`, `phonecode`, `success`, `error`, `qrcode_scanned_without_multidevice` |
| Messages | `message.received`, `sent`, `sent_failed`, `fb_received`, `receipt`, `reaction`, `undecryptable`, `media_retry`, `media_retry_error`, `error`, `status` |
| User | `user.push_name_changed`, `picture_changed`, `business_name_changed` |
| AppState | `appstate.mark_chat_as_read`, `archive`, `delete_chat`, `label_association_chat`, `label_association_message`, `label_edit` |
| History sync | `history.sync_started`, `sync_completed`, `sync_conversation`, `sync_messages`, `sync_contacts` |
| Recovery | `instance.recovery.detected`, `started`, `retry`, `success`, `exhausted`, `aborted` |

Per-event handler routing is in
`incoming_message_propriacloud_service.rb:111-173` (`EVENT_HANDLER_MAP`).
Legacy aliases (`connection.update`, `messages.upsert`, `messages.update`,
`messages.delete`) are accepted as a back-compat shim.

### 4.3 Event envelope & signature verification

Every delivery includes:
- HTTP body: `{event_type, instance_id, custom_id, timestamp, source,
  instance: {...}, data: {...}}` (per
  whatsapp-api's webhook publisher).
- Header: `X-Webhook-Signature: sha256=<hex>` over the **raw body**.

Chatwoot:
1. `Webhooks::WhatsappController#process_payload` reads
   `request.headers['X-Webhook-Signature']` and `request.raw_post`,
   merges them into params under `_webhook_signature` /
   `_webhook_raw_body`, and enqueues `Webhooks::WhatsappEventsJob`
   (or runs synchronously if `?awaitResponse=1`).
2. The job dispatches to `Whatsapp::IncomingMessagePropriacloudService`
   when `channel.provider == 'propriacloud'`.
3. The service `validate_webhook_token!` recomputes
   `sha256=HMAC(secret, raw_body)` with constant-time compare. A legacy
   path also accepts a verbatim `webhook_verify_token` field in the body
   for old delivery backends — **the new whatsapp-api always signs**, so
   the legacy fallback should not trigger in production.
4. `validate_custom_id!` rejects events whose `custom_id` (or
   `instance.custom_id`) does not equal `inbox.account_id`. ⚠️ A blank
   `custom_id` is tolerated to avoid breaking legacy data; new instances
   created via `setup_channel_provider` always carry it. **PEND-14**.

---

## 5. History sync

### 5.1 First-pair backfill (one-shot, idempotent)

Trigger: in `ConnectionUpdate#enqueue_history_backfill_if_needed`,
the first time the inbox flips from non-`open` to `open` and
`provider_config['history_backfill_completed_at']` is blank.

Flow (`Whatsapp::Propriacloud::HistoryBackfillService`):
1. `backfill_labels` → `GET /labels` paged, `Account#labels.find_or_create_by`.
2. `backfill_contacts` → `GET /sync/contacts` paged → upsert via
   `ContactInboxWithContactBuilder` keyed on phone-number digits
   (`source_id`). Skips empty JIDs.
3. `backfill_conversations_and_messages` →
   `GET /sync/conversations` paged → for each non-group/broadcast/
   newsletter/status `chat_jid`:
   - `GET /sync/messages?chat_jid=X` paged → wraps each batch in a
     synthetic `message.received` envelope and **dispatches through the
     live-tail handler** (`IncomingMessagePropriacloudService.new(...).perform`).
4. Stamps `history_backfill_completed_at`.

🧭 **Why it goes through the live tail.** Re-using
`MessagesUpsert#process_messages_upsert` keeps a single code path for
parsing, dedup, contact resolution, conversation creation, and avatar
fetch. It also means the backfill respects the same locks and
`MESSAGE_SOURCE_KEY` cache as the live tail — no new dedup story.

🧭 **Webhook auth bypass for backfill.** `HistoryBackfillService` builds
the synthetic payload with the channel's own `webhook_verify_token` and
`custom_id`, so `validate_webhook_token!` and `validate_custom_id!` both
pass. There is no HMAC signature on a backfill payload, which means the
service only enters the legacy verbatim-token branch — see
`incoming_message_propriacloud_service.rb:99-104`.

### 5.2 Lost-window recovery

| Scenario | Today | Gap |
| --- | --- | --- |
| Backfill fails partway | Sidekiq retries the job 5× (`exponentially_longer`). Idempotent at the dedup layer. | ✅ |
| Webhook delivery fails | The whatsapp-api retry config (`RetryConfigReq`) is **default** because Chatwoot doesn't override it (max_attempts=3, linear, 30s timeout). | ⚠️ For long Chatwoot outages, deliveries beyond the 3-attempt window are dropped. |
| Chatwoot down for hours | Backfill flag is already set → no automatic resync. | 🟡 **PEND-05**. Manual workaround: `Whatsapp::Propriacloud::HistoryBackfillJob.perform_later(channel_id, force: true)` from rails console. |
| Want older messages on demand | Not implemented. | 🟡 **PEND-06** — `/sync/request-history` exists but is unused. |
| Re-pair after unpair | `paired_at` is cleared, but `history_backfill_completed_at` stays. Next pair won't re-backfill unless explicitly forced. | 🟡 Acceptable: the new pair gets a fresh `INITIAL_BOOTSTRAP` history sync from whatsmeow itself, delivered via `history.sync_*` events; we just no-op those today (see §5.4). |

### 5.3 Self-healing on inbox open

`InboxesController#refresh_provider_status` (Chatwoot side, called by the
dashboard each time the user opens an inbox) hits
`channel.provider_service.reconcile!` behind a 60s rate limit. `reconcile!`:
1. `refresh_status_from_api!` — pulls truth from `/instances/status`,
   syncs `paired_at`.
2. `register_webhook!` — re-registers idempotently and re-runs
   `sync_webhook_subscription!`.
3. Enqueues `HistoryBackfillJob` if paired but never backfilled.

Effect: a session that paired during a Chatwoot outage / HMR restart
self-heals the moment the user opens the inbox. **PEND-05** addresses
the case where backfill *did* complete but events were lost during a
later outage.

### 5.4 What we do with `history.sync_*` push events

Today: `history.sync_started` and `history.sync_completed` stamp
timestamps in `provider_config`. The per-record events
(`history.sync_conversation`, `_messages`, `_contacts`) are intentionally
**no-op** — see `propriacloud_handlers/history_sync.rb:1-12`. The polled
`/sync/*` path is more deterministic and we want a single source of
truth. The events stay subscribed so we can switch to event-driven
backfill later without an API change.

---

## 6. Deduplication

### 6.1 Layers (innermost first)

1. **DB unique-by-source_id (per inbox).**
   `Whatsapp::PropriacloudHandlers::Helpers#message_under_process?`
   checks `inbox.messages.find_by(source_id: raw_message_id)` indirectly
   via `find_message_by_source_id` (in `IncomingMessageServiceHelpers`).
   This is the durable backstop and is correctly inbox-scoped.
2. **Redis lock on `MESSAGE_SOURCE_KEY`.** Race-condition guard between
   live tail and SendOnWhatsappService outbound echo.
   - ⚠️ Propriacloud uses `format(MESSAGE_SOURCE_KEY, id: raw_message_id)`
     (`propriacloud_handlers/helpers.rb:188-200`). Whatsmeow does the
     same. **Baileys/zapi** prefix with `inbox.id` to avoid cross-inbox
     collisions. WhatsApp message ids (`3EB0…`, 10-byte random) are
     unique-enough per account that real-world collision probability is
     near zero, and the DB layer would catch a true duplicate anyway —
     so this is a **LOW-severity inconsistency**, not a bug. **PEND-07**.
3. **Outgoing-echo lock.**
   `with_baileys_channel_lock_on_outgoing_message(inbox.channel.id)`
   (a Redis lock keyed on channel id) is held when handling outgoing
   (`from_me`) messages so an inbound `message.sent` echo can't race
   with `Whatsapp::SendOnWhatsappService`.
4. **HMAC + custom_id.** Cross-tenant filter at the entry of every
   webhook (§4.3 / §1).
5. **Backfill idempotency flag.**
   `provider_config['history_backfill_completed_at']` blocks re-runs
   unless `force: true`.

### 6.2 What we are *not* protecting against

- **Webhook redelivery storms when Sidekiq is wedged.** The Rails
  controller acks `200 OK` immediately after enqueuing. If Sidekiq is
  down so long that whatsapp-api's retry budget exhausts, we lose the
  event. There is no PGMQ DLQ replay tool wired into Chatwoot.
  **PEND-05**.
- **Same `appstate.archive` event delivered twice with toggling
  values.** Treated as idempotent state assignment, so two consecutive
  `archived: true` events are fine. But two **opposite** events arriving
  out of order (e.g. unarchive then archive, but processed in reversed
  order) would land us in the wrong state. Webhook ordering is
  best-effort. **PEND-08** — needs a timestamp guard on `appstate`
  handlers.
- **Reaction edits.** `MessagesUpsert#message_content_attributes` only
  flags reaction once and saves. Subsequent reaction-edit events arrive
  via `message.reaction` and would go through `find_message_by_source_id`
  → already exists → silently dropped. We do not currently *update* the
  emoji on the stored row. ⚠️ Minor.

---

## 7. Media handling

### 7.1 🔴 Inbound media download is broken (end-to-end)

`Whatsapp::PropriacloudHandlers::MessagesUpsert#handle_attach_media`
(`messages_upsert.rb:152-175`) calls
`provider_service.download_media(@raw_message)` where `@raw_message` is
the full webhook message object: `{key:{...}, message:{...}, push_name,
message_timestamp}`.

`Whatsapp::Providers::WhatsappPropriacloudService#download_media`
(`whatsapp_propriacloud_service.rb:327-341`) sends:

```json
{ "message": { "key": {...}, "message": { "imageMessage": {...} } } }
```

**Defect 1 — request shape mismatch (PEND-01):**
The Go handler `handlers/media.go:DownloadMedia` (line 173) calls
`client.NormalizeMediaMessageMap(messageMap)`
(`client/message_converter.go:101`). The normalizer accepts only:
- **Wrapped:** `{imageMessage: {url, mediaKey, ...}}` — the `message`
  key is not in `mediaTypeWrappers` so we fall through.
- **Flat:** `{url, mediaKey, mimetype: 'image/jpeg', ...}` at root —
  our root has only `message`, no `mimetype`/`PTT`/`fileName`/etc., so
  `detectMediaTypeFromPayload` returns `""`.

Result: `400 Bad Request — unable to detect media type from payload`.

**Defect 2 — response field mismatch (PEND-02):**
Even if the request were correct, the response read pulls
`body['data'] || body['body'] || body['file']`. The OpenAPI
`DownloadMediaResponse` (line 17762) defines the field as **`base64`**.
The Go handler returns `models.DownloadMediaResponse` via
`utils.Success(w, response)` which envelopes it as
`{success, data: {base64, mime_type, ...}, timestamp}`. After our
`unwrap` extracts `data`, none of the legacy keys we look for exist.

**Combined effect:** Every inbound image/video/audio/document/sticker
arrives as an attachment-less `Message` with `is_unsupported: true` (the
`Down::Error` rescue branch in
`messages_upsert.rb:165-167`). Agents see an empty message with no
preview.

Recommended fix:

```ruby
def download_media(raw_message)
  inner = raw_message[:message] || raw_message['message'] || {}
  payload = inner.transform_keys(&:to_s).slice(
    'imageMessage', 'videoMessage', 'audioMessage',
    'documentMessage', 'stickerMessage', 'extendedTextMessage'
  )
  return StringIO.new('') if payload.empty?

  response = HTTParty.post(
    "#{provider_url}/media/download#{instance_query}",
    headers: api_headers,
    body: payload.to_json # already in the wrapped form the API expects
  )
  raise Down::Error, "media download failed: #{response.code} #{response.body}" unless response.success?

  body = unwrap(response.parsed_response)
  encoded = body['base64'] || body['data'] || body['body'] || body['file']
  raise Down::Error, "media download response missing base64: #{response.body}" if encoded.blank?

  StringIO.new(Base64.decode64(encoded))
end
```

This needs:
1. Webhook payload casing audit — confirm whether the API publisher
   emits `imageMessage` (camelCase, matches the Go normalizer) or
   `image_message` (snake_case, matches our handlers' detection). If
   snake_case is what we receive, we must transform back to camelCase
   before sending to `/media/download`. **PEND-03 — verify casing
   on a real captured webhook before shipping the fix.**
2. A spec covering at least one image and one audio/PTT round trip
   (currently none).

### 7.2 Storage destination

After `download_media` returns a `StringIO`, `handle_attach_media`
attaches it through ActiveStorage:

```ruby
attachment.file = { io: attachment_file, filename: filename, content_type: mime_type }
```

ActiveStorage routes through `ENV['ACTIVE_STORAGE_SERVICE'] || :local`
→ on a default install the bytes land in
`<rails_root>/storage/<key>/<key>` and the metadata in the
`active_storage_blobs` / `active_storage_attachments` tables. Public
delivery happens via Chatwoot's signed-URL controller. There is no
direct CDN passthrough — the bytes always pass through Rails.

Implications:
- 🧭 Default (`local`) is **NOT safe** for >1 Rails replica.
- 🧭 No automatic media-expiry sweep — once stored, attachments live
  forever (subject to standard ActiveStorage `purge_later` on Message /
  Conversation deletion).
- 🟡 We do not respect the Go service's `MEDIA_UPLOAD_*_LIMIT` (queryable
  via `GET /media/upload-limits`) when deciding to attempt download.
  Failures show up as `Down::Error` only after a wasted CDN hit.

### 7.3 Outbound media (`send_media_message`)

`whatsapp_propriacloud_service.rb:929-968`:

- Reads attachment via `attachment.file.download` → base64 strict-encodes
  → ships as `media[0].data`.
- `mime_type` from the AS blob; `file_name` from the blob filename.
- PTT inferred from `audio/(ogg|opus|webm)` content type.
- ⚠️ Currently always sends ONE attachment per call (`media: [media_item]`)
  even though the API supports up to 12. Multi-attachment Chatwoot
  messages would only send the first; the rest are silently dropped.
  In practice Chatwoot UI sends them as separate messages, so the
  behavior is fine. **PEND-16 — known scope limit, not a bug**.

### 7.4 Outbound media trade-offs

🟡 Base64 wire-encoding doubles request size for every MB of media. The
API also accepts `url` (server fetches and uploads). For attachments
already living on a public S3 bucket we could short-circuit by passing
the URL — but ActiveStorage URLs are signed and time-limited, so this
optimization requires extra work to keep them valid for the API's
download window. Not worth doing for v1.

### 7.5 Status / story media

The whatsapp-api docs explicitly call out that status messages
(`contextInfo.statusSourceType: 1`) often fail with `invalid media hmac`.
We do not detect this case; a status reply would be saved as
`is_unsupported`. **PEND-17 — minor**.

---

## 8. Outbound message pipeline

```
agent → ConversationsController → Conversation::ReplyJob
        → Whatsapp::SendOnWhatsappService
        → Channel::Whatsapp#send_message
        → Whatsapp::Providers::WhatsappPropriacloudService#send_message
            ├── send_text_message → POST /messages/send
            ├── send_media_message → POST /messages/send-media
            └── send_reaction_message → POST /messages/react
        ← message_id returned
        ← persisted as Message.source_id
```

Outbound row is created **before** the API call (Chatwoot's standard
flow). When the matching `message.sent` webhook arrives later, the
upsert handler:
1. Acquires `with_baileys_channel_lock_on_outgoing_message` to coordinate
   with the still-running `SendOnWhatsappService`.
2. Looks up the row by `source_id` — finds it → no duplicate.
3. Falls through (handler treats existing row as already-handled).

Status receipts (`message.receipt`, `message.status`) drive the
`MessagesUpdate` handler, which transitions
`Message.status` through `sent → delivered → read`, with a guard against
backwards transitions (`status_transition_allowed?`). `failed` short-circuits
that ladder.

---

## 9. Inbound message pipeline (event by event)

| Event | Handler module | Side effects |
| --- | --- | --- |
| `message.received` / `.sent` / `.fb_received` / `.reaction` | `MessagesUpsert` | Resolve contact/inbox via `ContactInboxWithContactBuilder`; create conversation if needed; create Message; for media, attempt download (currently broken — §7.1); fetch profile picture lazily via `try_update_contact_avatar`. |
| `message.receipt` / `.status` | `MessagesUpdate` | Map status → Chatwoot status; update; on `read` for incoming, bump `agent_last_seen_at`/`assignee_last_seen_at`. Edits (`update.message.edited_message`) update Message content with `is_edited`. |
| `message.sent_failed` / `.error` / `.undecryptable` / `.media_retry_error` | `MessagesFailure` | Find by `source_id`; flip to `failed`; set `external_error`. |
| `message.media_retry` | `MessagesFailure` | Logged only, no state change. |
| `connection.*` / `pairing.*` | `ConnectionUpdate` | Update `provider_connection`; track `paired_at` on success / strip on logout / pairing.error; on `open` transition, kick `HistoryBackfillJob`. |
| `user.push_name_changed` / `.business_name_changed` | `UserChanged` | Update `Contact.name`. |
| `user.picture_changed` | `UserChanged` | Purge cached avatar; refetch via `get_profile_pic` + `Avatar::AvatarFromUrlJob`. |
| `appstate.mark_chat_as_read` | `Appstate` | `Conversation#contact_last_seen_at = now`. |
| `appstate.archive` | `Appstate` | Toggle `Conversation` resolved/open. |
| `appstate.delete_chat` | `Appstate` | Toggle `Conversation` to resolved (no hard delete — Chatwoot retains history). |
| `appstate.label_edit` | `Appstate` | `Account#labels.find_or_create_by!(title:)`. |
| `appstate.label_association_chat` | `Appstate` | Add/remove label on Conversation. |
| `appstate.label_association_message` | `Appstate` | Stash on `Message#additional_attributes['propriacloud_labels']` (Chatwoot has no per-message labels). |
| `history.sync_started` / `.sync_completed` | `HistorySync` | Stamp timestamps in `provider_config`. |
| `history.sync_conversation` / `.sync_messages` / `.sync_contacts` | `HistorySync` | No-op (we use `/sync/*` paged pulls). |
| `instance.recovery.detected` / `.started` / `.retry` | `InstanceRecovery` | If `paired_at` present → `connection: 'reconnecting'`. |
| `instance.recovery.success` | `InstanceRecovery` | `connection: 'open'`. |
| `instance.recovery.exhausted` / `.aborted` | `InstanceRecovery` | `connection: 'close'` + error. |

---

## 10. UI surface (frontend)

| Component | Path | Purpose |
| --- | --- | --- |
| Inbox setup wizard | `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/PropriacloudWhatsapp.vue` | Form: provider URL + API key (optional, falls back to env/DB defaults). |
| Provider selector | `…/inbox/channels/Whatsapp.vue` | Lists `propriacloud` as a provider option. |
| Status badge | `app/javascript/dashboard/components/widgets/conversation/PropriacloudStatusBadge.vue` | Compact chip in conversation header. |
| Inbox settings — Connection panel | `…/inbox/Settings.vue` | Status chips + Connect/Disconnect/Pair/Unpair buttons. Confirmations on destructive actions. |
| QR / phone-code modal | `…/inbox/components/WhatsappLinkDeviceModal.vue` | Renders the QR base64 image or the 8-char phone code. |
| Read-only Advanced tab | `…/settingsPage/ConfigurationPage.vue` | Shows `provider_connection` for support / debugging; renamed "Informações" tab. |
| OpenID button | `app/javascript/v3/components/PropriacloudOpenid/Button.vue` | Logto OIDC login (separate concern from this doc). |
| State resolver composable | `app/javascript/dashboard/composables/usePropriacloudStatus.js` | Pure-function `resolvePropriacloudStatus(inbox, t)` derives chips + actions from the two-axis state. Mirrors `propriacloud.git/apps/minha/instance-tags.ts`. |

---

## 11. Super Admin configuration

- DB-backed config rows in `installation_configs` keyed
  `PROPRIACLOUD_API_URL`, `PROPRIACLOUD_API_KEY`,
  `PROPRIACLOUD_WEBHOOK_BASE_URL`. Editable via Super Admin → Settings →
  Própria Cloud (tabbed view at
  `app/views/super_admin/app_configs/_propriacloud_tabs.html.erb`).
- On first read after deploy, env aliases (`WHATSAPP_API_*`,
  `PROPRIACLOUD_PROVIDER_DEFAULT_*`, `CLICK2RUN_PROVIDER_DEFAULT_*`)
  are migrated into the canonical row so the UI form is pre-populated.
  Race-safe via `first_or_create!`.
- 🧭 The OpenID Logto integration uses a parallel set of vars
  (`PROPRIACLOUD_OPENID_*`) — not in scope for this document.

---

## 12. Migrations & schema

| Migration | What it does | Status |
| --- | --- | --- |
| `db/migrate/20251105180552_add_click2run_to_provider_connection_index.rb` | Conditional GIN on `provider_connection` jsonb when `provider IN ('baileys','zapi','whatsmeow','click2run')` | ⚠️ **Stale.** `click2run` was renamed to `propriacloud`; the index now misses propriacloud rows so jsonb path queries (e.g. dashboard status filters) fall back to a sequential scan. **PEND-18.** |

🧭 No new columns were added for propriacloud — everything lives in the
existing `channel_whatsapp.provider_config` / `provider_connection`
jsonb columns. This intentionally trades index efficiency for schema
stability across Chatwoot upstream merges.

---

## 13. Pending issues / action items

> **2026-05-10 sweep.** All 20 items below were addressed. Each row is
> kept as a strikethrough record (with the closing PR / commit reference)
> rather than deleted, so future audits can see what was already
> investigated. Open this section first if you reopen the audit.

| ID | Severity | Area | Summary | Location | Resolution |
| --- | --- | --- | --- | --- | --- |
| ~~**PEND-01**~~ | 🔴 → ✅ | Media | `download_media` request body wraps under `{message: ...}` — rejected by `client.NormalizeMediaMessageMap`. | `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb` | **Closed 2026-05-10.** New `build_media_download_body` extracts the inner `<type>Message` wrapper from `raw_message[:message]`, normalizing snake_case (`image_message`) → camelCase (`imageMessage`). Spec coverage in `spec/services/whatsapp/providers/whatsapp_propriacloud_service_spec.rb`. |
| ~~**PEND-02**~~ | 🔴 → ✅ | Media | Reads response field `data\|body\|file`; OpenAPI is `base64`. | same | **Closed 2026-05-10.** Reads `body['base64']` first; legacy aliases retained as fallbacks. |
| ~~**PEND-03**~~ | ⚠️ → ✅ | Media | Unverified webhook payload casing (camelCase `imageMessage` vs snake_case `image_message`). | `helpers.rb`, `client/message_converter.go` | **Closed 2026-05-10.** Provider download path is now format-agnostic (accepts either casing on input and always sends camelCase to the Go normalizer). Same dual-casing applied to `MessagesUpsert#status_message?` for status detection. |
| ~~**PEND-04**~~ | 🔴 → ✅ | Contacts | `on_whatsapp` reads `is_in\|exists\|is_registered`; OpenAPI returns `is_on_whatsapp`. | `whatsapp_propriacloud_service.rb` | **Closed 2026-05-10.** Reads `is_on_whatsapp` first; legacy aliases retained for older deployments. Spec covers all three response shapes. |
| ~~**PEND-05**~~ | 🟡 → ✅ | Sync | No lost-window recovery after first backfill completes. | backfill service / job | **Closed 2026-05-10.** New `POST /api/v1/accounts/:id/inboxes/:id/resync_history` enqueues `HistoryBackfillJob.perform_later(channel.id, force: true)` behind a 1/hour Redis rate limit. |
| ~~**PEND-06**~~ | 🟡 → ✅ | Sync | `/sync/request-history` is unused → no "Load older messages" affordance. | new endpoint | **Closed 2026-05-10.** New provider method `request_chat_history` plus `POST /api/v1/accounts/:id/inboxes/:id/request_chat_history`. ON_DEMAND results arrive as `history.sync_messages` which we still no-op for now (events stay subscribed for the future-proof switch). |
| ~~**PEND-07**~~ | 🟢 → ✅ | Dedup | Redis `MESSAGE_SOURCE_KEY` not inbox-scoped. | `propriacloud_handlers/helpers.rb` | **Closed 2026-05-10.** New `message_processing_lock_key` prefixes with `inbox.id`, matching baileys/zapi. Spec asserts cross-inbox key isolation. |
| ~~**PEND-08**~~ | 🟡 → ✅ | AppState | No timestamp guard against out-of-order webhook deliveries. | `propriacloud_handlers/appstate.rb` | **Closed 2026-05-10.** New `appstate_event_stale_for?` compares event `timestamp` against `Conversation#updated_at` and short-circuits stale deliveries. |
| ~~**PEND-09**~~ | 🟢 → ✅ | Webhook reg | Undocumented `enabled: true` in `/webhooks` POST. | `whatsapp_propriacloud_service.rb` | **Closed 2026-05-10.** Field removed from both `register_webhook!` and `sync_webhook_subscription!` PATCH. |
| ~~**PEND-10**~~ | ⚠️ → ✅ | Pairing | Plain-text `code` falls back into a `data:image/png;base64,` URL. | provider service + connection_update | **Closed 2026-05-10.** Fallback chain now `img` → `qr_code` → `qrcode` only; plain `code` is never used as a base64 image. |
| ~~**PEND-11**~~ | 🟢 → ✅ | Pairing | Dead `expires_in/timeout` branches on `PhoneCodeResponse`. | provider service | **Closed 2026-05-10.** Defaults `expires_in` to 60 (WhatsApp's standard pair window) when not present in the response. |
| ~~**PEND-12**~~ | 🟡 → ✅ | Sync | Backfill walks every chat's full history with no cap. | `history_backfill_service.rb` | **Closed 2026-05-10.** New `MAX_PAGES_PER_CHAT = 25` (≈5,000 msgs/chat) plus per-channel `provider_config['history_backfill_max_age_days']` cutoff (default 180 days). Pagination stops early when oldest message in a page predates the cutoff. |
| ~~**PEND-13**~~ | 🟡 → ✅ | Sync | `sync_push_names` exposed but unused. | backfill service | **Closed 2026-05-10.** Now consumed before the contact pass to seed a richer name lookup for contacts seeded only via @lid. |
| ~~**PEND-14**~~ | 🟢 → ✅ | Security | `validate_custom_id!` returns early when blank. | `incoming_message_propriacloud_service.rb` | **Closed 2026-05-10 (no behavior change).** Confirmed the upstream develop event-message envelope strips `custom_id` (only `instance_id`/`tenant_id` are propagated to webhook deliveries — see `integration/queue/handlers.go:476-487`). Tightening to "reject blank" would break legitimate traffic; the HMAC layer remains the load-bearing guard. Documented for clarity. |
| ~~**PEND-15**~~ | 🟢 → ✅ | UX | `presence_subscribe` default toggle never consumed. | `app/models/channel/whatsapp.rb` | **Closed 2026-05-10.** Default removed; reintroduce only when `POST /presence/subscribe` is wired. |
| ~~**PEND-16**~~ | 🟢 → ✅ | Media | Outbound `/messages/send-media` only sends `media[0]`. | provider service | **Closed 2026-05-10.** New `MEDIA_PER_CALL_LIMIT = 12` plus `build_media_item` helper; iterates `@message.attachments` (capped to API limit) with caption applied to first item only. Returns `results[0].message_id`. |
| ~~**PEND-17**~~ | 🟢 → ✅ | Media | Status messages (`statusSourceType: 1`) always fail download. | `messages_upsert.rb` | **Closed 2026-05-10.** New `status_message?` detector + `attach_status_thumbnail_or_skip` attaches the embedded `jpegThumbnail` if present, falls back to `is_unsupported` otherwise. |
| ~~**PEND-18**~~ | 🟡 → ✅ | DB | Stale `click2run` partial GIN index predicate. | `db/migrate/...` | **Closed 2026-05-10.** New migration `20260510170000_update_provider_connection_index_for_propriacloud.rb` re-creates the index with `propriacloud` in the predicate. |
| ~~**PEND-19**~~ | 🟡 → ✅ | Tests | Zero RSpec coverage. | `spec/services/whatsapp/...` | **Closed 2026-05-10.** Added: `whatsapp_propriacloud_service_spec.rb` (provider — media, on_whatsapp, webhook, QR, phonecode, multi-attachment, request-history); `propriacloud_handlers/appstate_spec.rb` (timestamp guard); `propriacloud_handlers/helpers_spec.rb` (Redis lock isolation); `propriacloud/history_backfill_service_spec.rb` (page cap, age cutoff, push-names). |
| ~~**PEND-20**~~ | 🟢 → ✅ | Observability | No structured logging tag. | `incoming_message_propriacloud_service.rb` + backfill service | **Closed 2026-05-10.** `Rails.logger.tagged('propriacloud', "inbox=…", "event=…")` wraps `IncomingMessagePropriacloudService#perform`; backfill service tags its own block. |

---

## 14. Quick reference — full `whatsapp-api` endpoint catalog

The propriacloud provider has access to far more than what Chatwoot uses
today. Useful when scoping new features.

**Instances:** `/instances` (list/create), `/instances/test`,
`/instances/status`, `/instances/create`, `/instances/connect`,
`/instances/pair/{qrcode,phonecode}`, `/instances/disconnect`,
`/instances/unpair`, `/instances/update`, `/instances/delete`,
`/instances/restart`, `/instances/recreate`, `/instances/recovery`,
`/instances/audit{,/state,/stats,/timeline,/errors,/stream,/stream/stats}`,
`/runtime/{instances,devices,stats}`, `/devices/{paired,instances,version}`,
`/appstate/{recovery,sync}`,
`/system/{breakers/unexpected-logout{,/reset},appstate/unrecoverable,
appstate/clear-unrecoverable,jobs/purge/db/{table},integrity{,/cleanup},settings}`.

**Messages:** `/messages/send`, `/messages/send-media`,
`/messages/send-location`, `/messages/{revoke,build-revoke,revoke-others}`,
`/messages/react`, `/messages/edit`, `/messages/mark-read`,
`/messages/generate-id`, `/chats/mark-read`.

**Labels & Notes:** `/labels`, `/labels/{colors,info,chat}`, `/notes`,
`/notes/{chat,info}`.

**Contacts & Groups:** `/contacts`, `/contacts/{info,onwhatsapp,
profile-picture,business-profile,status-message,blocklist,qr-link,
resolve-qr,bots,bot-profiles,resolve-business-link}`,
`/groups{,/create,/info,/leave,/participants,/name,/description,
/invite-link,/join-with-link,/photo,/locked,/announce,/join-approval,
/member-add-mode,/preview,/pending,/link-community,/subgroups,
/info-from-invite,/join-with-invite,/linked-participants,/topic}`.

**Media:** `/media/upload`, `/media/download`, `/media/thumbnail`,
`/media/upload-limits`, `/media/download-path`.

**Presence:** `/presence/{send,subscribe,chat}`.

**Newsletters:** `/newsletters{,/info,/follow,/messages,/mute,
/info-with-invite,/message-updates,/mark-viewed,/react,/subscribe-live,
/upload-media}`.

**Privacy & Polls & Calls:** `/privacy/{settings,disappearing-timer,
status-privacy,chat-disappearing-timer,fetch-settings}`,
`/polls/{create,vote,results,decrypt-vote}`,
`/calls/{reject,capabilities,events}`.

**Webhooks:** `/webhooks`, `/webhooks/{id}`, `/webhooks/{id}/test`,
`/webhooks/{id}/{activate,deactivate}`, `/webhooks/instance`.

**Events/Adapters (PGMQ etc.):** `/events/adapters{,/pgmq/queues,
/pgmq/queues/{scope}/stats,/pgmq/dlq/messages{,/{msg_id}{,/requeue}},
/pgmq/archive/{scope}{,/{msg_id},/requeue,/requeue-async},
/pgmq/dlq/requeue,/pgmq/jobs/{id}}`.

**Sync (history/state):** `/sync/{sessions,sessions/latest,status,
conversations,conversations/info,messages,messages/info,contacts,
contacts/info,call-logs,push-names,stickers,past-participants,
group-participants,global-settings,request-history,stats,config,audit,
audit/count,export,features}`.

**Meta WABA (Business API — separate dual-path):** `/meta/waba/*`
(templates, phone-numbers, business-profile, profile-picture, analytics,
flows, qr-codes, conversation-windows, commerce). Not used by the
propriacloud provider; documented here for completeness.

---

## 15. Cross-references

- Webhook router: `app/controllers/webhooks/whatsapp_controller.rb`
- Job dispatcher: `app/jobs/webhooks/whatsapp_events_job.rb`
- Routes: `config/routes.rb` (search `webhooks/whatsapp`,
  `refresh_provider_status`, `convert_provider`).
- Provider class hierarchy:
  `app/services/whatsapp/providers/base_service.rb` →
  `whatsapp_propriacloud_service.rb`.
- Handler mixins live under
  `app/services/whatsapp/propriacloud_handlers/`.
- Frontend status logic: `app/javascript/dashboard/composables/usePropriacloudStatus.js`.
- Branding: `lib/middleware/fazer_ai_platform_header.rb` injects
  `X-Platform: propriacloud` on every outbound HTTP call to whatsapp-api.
- Existing reference docs (older but useful for diff context):
  `CUSTOM-WHATSAPP-API.md`, `CUSTOM-CLICK2RUN-API.md`,
  `CUSTOM-CHANGELOG.md`, `CUSTOM-FAZER-AI.md`, `CUSTOM-MERGES-GUIDE.md`.

---

## 16. How to keep this document up to date

This file is **authoritative** for any audit, refactor, or fork-merge
analysis touching the propriacloud provider. When a future change
modifies any of:
- `Whatsapp::Providers::WhatsappPropriacloudService`
- `Whatsapp::IncomingMessagePropriacloudService` or any
  `propriacloud_handlers/` module
- `Whatsapp::Propriacloud::HistoryBackfillService` /
  `HistoryBackfillJob`
- `Channel::Whatsapp` propriacloud-specific branches
- `Webhooks::WhatsappController` propriacloud paths
- `installation_config.yml` propriacloud keys

…update the relevant section here in the same PR, and re-validate the
endpoint matrix against the latest `develop` worktree of
`whatsapp-api.git` (`docs/openapi.yaml`) before merging. The
**Pending issues** table is the running ledger — when one is fixed,
strike it through with a date and PR link rather than deleting, so the
document remains a record of what we shipped.
