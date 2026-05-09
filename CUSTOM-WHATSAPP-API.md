# Custom WhatsApp API integration (Própria Cloud)

This document describes the **`propriacloud`** WhatsApp provider — the
custom Chatwoot channel that talks to the Própria Cloud
[`whatsapp-api`](https://github.com/fazer-ai/whatsapp-api) Go service
(an OpenAPI 3.1 wrapper around `whatsmeow`).

It supersedes the older fazer-ai `whatsmeow` and `baileys` wirings for
this fork while preserving the **push (webhook-driven) architecture** the
project has used since the original implementation (previously
`CUSTOM-WHATSAPP-QRCODE.md`).

## Architectural goals (preserved)

The original integration was push-based: Chatwoot registers a webhook
URL with the provider, the provider PUSHES connection-state updates and
QR codes to that webhook, and the frontend polls Chatwoot's own DB. That
contract is unchanged. Only the upstream API shape (and event names)
moved to the new OpenAPI 3.1 spec.

| Stage                | Before (Baileys/Whatsmeow)                              | Now (`propriacloud` / whatsapp-api)                                                  | Status |
| :------------------- | :------------------------------------------------------ | :----------------------------------------------------------------------------------- | :----- |
| Webhook registration | Embedded in `POST /connections/{phone}` body            | Dedicated `POST /webhooks` call (`scope: instance`, `events:['*']`, signing secret)  | OK — same intent, factored out by the new API |
| QR generation        | WhatsApp protocol (Baileys/whatsmeow)                   | WhatsApp protocol (whatsmeow inside `whatsapp-api`)                                  | OK     |
| QR delivery          | Provider PUSH `event:'connection.update'` w/`qrDataUrl` | Provider PUSH `event_type:'pairing.qrcode'` w/`data.img`                             | OK — push preserved, event vocabulary changed |
| Storage              | `channel.update_provider_connection!({connection, qr_data_url, error})` | Same identical call                                              | OK     |
| Frontend display     | Polls `GET .../channels/{id}` for `provider_connection` | Same                                                                                 | OK     |

Additive changes (not breaking):

- HMAC-SHA256 signature in `X-Webhook-Signature` header (was token-only).
- Catch-all event subscription with an `EVENT_HANDLER_MAP` translation
  table to map whatsapp-api event names to Chatwoot's connection-state
  vocabulary (`open` / `connecting` / `close`).
- Optional pull fallback `fetch_and_publish_qr_code` for the corner case
  where whatsapp-api answers `POST /instances/connect` with `"already
  connected"` and never re-emits `pairing.qrcode`.
- Phone-code pairing (`POST /instances/pair/phonecode`) alongside QR.

## End-to-end flow

```
┌──────────────────────────────────────────────────────────────────────┐
│             WhatsApp pairing flow (push model, propriacloud)         │
└──────────────────────────────────────────────────────────────────────┘

STEP 1 — Setup (idempotent, three-call sequence)
─────────────────────────────────────────────────────────────────────
Chatwoot
  ├─► POST {WHATSAPP_API_URL}/instances/create
  │     body: { instance_id, name, phone, custom_id }
  │     200/201/409 (409 == already exists, treated as success)
  │
  ├─► POST {WHATSAPP_API_URL}/webhooks
  │     body: {
  │       scope: "instance",
  │       instance_id, url: callback_webhook_url,
  │       events: ["*"], enabled: true,
  │       secret: provider_config.webhook_verify_token
  │     }
  │     200 / 409 (409 == webhook already registered, idempotent)
  │
  └─► POST {WHATSAPP_API_URL}/instances/connect?instance_id=…
        200 (or "already connected" — handled by pull fallback)


STEP 2 — Provider generates state and PUSHES via webhook
─────────────────────────────────────────────────────────────────────
whatsapp-api
  └─► POST {chatwoot}/webhooks/whatsapp/{phone_number}
        headers:
          X-Webhook-Signature: sha256=<hex HMAC of raw body using secret>
        body (e.g. pairing.qrcode):
        {
          "instance_id": "0119",
          "event_type": "pairing.qrcode",
          "timestamp":  1715200000,
          "data": { "img": "<base64 PNG>" }
        }


STEP 3 — Chatwoot validates + dispatches
─────────────────────────────────────────────────────────────────────
Webhooks::WhatsappController#process_payload
  ├─► attaches X-Webhook-Signature + raw_post into params
  ├─► returns 200 immediately
  └─► enqueues Webhooks::WhatsappEventsJob

WhatsappEventsJob (Sidekiq)
  └─► provider == "propriacloud"
      → Whatsapp::IncomingMessagePropriacloudService#perform
          ├─► HMAC verify: sha256=hex(HMAC_SHA256(secret, raw_body))
          │                 vs ActiveSupport::SecurityUtils.secure_compare
          ├─► EVENT_HANDLER_MAP[event_type] → handler symbol
          └─► Whatsapp::PropriacloudHandlers::ConnectionUpdate
              #process_connection_update
                channel.update_provider_connection!({
                  connection:  open|connecting|close,
                  qr_data_url: "data:image/png;base64,…",
                  error:        "logout" | nil
                })


STEP 4 — Frontend polls the channel object
─────────────────────────────────────────────────────────────────────
WhatsappLinkDeviceModal.vue / Settings.vue
  ├─► GET /api/v1/accounts/{id}/channels/{id}
  ├─► reads provider_connection.connection / .qr_data_url / .error
  └─► renders QR <img src="data:image/png;base64,…">
       OR phone code (8-char) returned synchronously by
          POST /inboxes/{id}/pair_phone_code
```

## Provider service entry points

`app/services/whatsapp/providers/whatsapp_propriacloud_service.rb`
(class `Whatsapp::Providers::WhatsappPropriacloudService`).

| Method                          | whatsapp-api endpoint                          | Notes                                                                                       |
| :------------------------------ | :--------------------------------------------- | :------------------------------------------------------------------------------------------ |
| `setup_channel_provider`        | `POST /instances/create` → `POST /webhooks` → `POST /instances/connect` | Idempotent. Each step accepts 409 as success. After `connect`, falls through to `fetch_and_publish_qr_code` for "already connected" instances. |
| `disconnect_channel_provider`   | `POST /instances/disconnect` → `POST /instances/delete` | Re-runs cleanly even if instance is already gone.                                  |
| `request_phone_pairing_code(phone)` | `POST /instances/pair/phonecode`           | Returns the 8-character pairing code synchronously. Used by the controller's `pair_phone_code` action. |
| `fetch_and_publish_qr_code`     | `GET /instances/pair/qrcode`                   | Pull fallback for already-connected-unpaired instances; updates `provider_connection.qr_data_url` directly. |
| `send_message`                  | `POST /messages/send` / `/messages/send-media` | Routes by content type (`text`, `image`, `audio`, `document`, `video`, `sticker`).         |
| `read_messages`                 | `POST /messages/mark-read`                     | Batch read receipts.                                                                        |
| `toggle_typing_status`          | `POST /presence/chat`                          | Maps Chatwoot's typing status → whatsapp-api `composing`/`paused`.                          |
| `download_media`                | `GET /media/download`                          | Returns binary, written into Active Storage.                                                |
| `register_webhook!` (private)   | `POST /webhooks`                               | Subscribes to `events:['*']`, treats 409 as success.                                        |

## Webhook signature verification

whatsapp-api signs every webhook delivery with HMAC-SHA256 over the raw
request body, using the same `secret` that was sent during `register
webhook` (Chatwoot stores it in `provider_config.webhook_verify_token`,
32 hex chars).

```ruby
# app/services/whatsapp/incoming_message_propriacloud_service.rb
expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', expected_token, raw_body)}"
raise InvalidWebhookVerifyToken unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)
```

The controller injects the signature + raw body into params before
enqueueing the Sidekiq job:

```ruby
# app/controllers/webhooks/whatsapp_controller.rb
_webhook_signature: request.headers['X-Webhook-Signature'],
_webhook_raw_body:  request.raw_post
```

## Event vocabulary

whatsapp-api uses a richer event taxonomy than the old `connection.update`
single event. They are mapped 1:1 to `process_connection_update` in
`EVENT_HANDLER_MAP` and reduced to Chatwoot's three connection states
inside `Whatsapp::PropriacloudHandlers::ConnectionUpdate#infer_connection_state`.

| whatsapp-api `event_type`                                                                                                                                                                                                  | Chatwoot connection state |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------ |
| `connection.connected`, `pairing.success`                                                                                                                                                                              | `open`                    |
| `pairing.qrcode`, `pairing.phonecode`                                                                                                                                                                                  | `connecting`              |
| `connection.disconnected`, `connection.logged_out`, `connection.stream_replaced`, `connection.connect_failure`, `connection.client_outdated`, `connection.temporary_ban`, `connection.stream_error`, `pairing.error` | `close`                   |
| `connection.update` (legacy)                                                                                                                                                                                           | uses `data.connection` directly |
| `message.received`, `message.update`, `messaging-history.set`                                                                                                                                                          | routed to message-creation handlers (separate concern) |

QR delivery field preference, in order:

1. `data.img` — full base64 PNG (preferred, ready to render).
2. `data.code` — pairing text; UI generates the QR image.
3. `data.qr_code` / `data.qrcode` — legacy fazer-ai naming kept for
   backward tolerance.

## Phone-code pairing

A new pairing path (not present in the original push-only flow) returns
an 8-character code that the user types into WhatsApp's *Link with phone
number* screen.

- Backend: `POST /api/v1/accounts/{id}/inboxes/{id}/pair_phone_code` →
  `Whatsapp::Providers::WhatsappPropriacloudService#request_phone_pairing_code`
  → whatsapp-api `POST /instances/pair/phonecode`.
- Pundit: `InboxPolicy#pair_phone_code?` (admin-only).
- Frontend: `WhatsappLinkDeviceModal.vue` exposes a method picker (QR
  Code / Phone Code) **before any backend call**. The user clicks the
  desired flow, the modal triggers `setup_channel_provider` lazily for
  the phone-code path if the instance is currently `close`, and renders
  the returned code in a monospace block.

## Files involved

| File                                                                                                | Role                                                                                              |
| :-------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------ |
| `app/services/whatsapp/providers/whatsapp_propriacloud_service.rb`                                  | Outbound provider service (Chatwoot → whatsapp-api).                                              |
| `app/services/whatsapp/incoming_message_propriacloud_service.rb`                                    | Inbound webhook dispatcher: signature verify + event routing.                                     |
| `app/services/whatsapp/propriacloud_handlers/connection_update.rb`                                  | Reduces every connection/pairing event to `update_provider_connection!`.                          |
| `app/services/whatsapp/propriacloud_handlers/helpers.rb` (and other `*_handlers/*.rb`)              | Helpers shared with the message-receive path.                                                     |
| `app/controllers/webhooks/whatsapp_controller.rb`                                                   | HTTP entry point; attaches `X-Webhook-Signature` + raw body before enqueueing.                    |
| `app/jobs/webhooks/whatsapp_events_job.rb`                                                          | Routes `provider == "propriacloud"` to `IncomingMessagePropriacloudService`.                      |
| `app/controllers/api/v1/accounts/inboxes_controller.rb` (`pair_phone_code` action)                  | REST endpoint exposing phone-code pairing.                                                        |
| `app/policies/inbox_policy.rb` (`pair_phone_code?`)                                                 | Admin-only authorization.                                                                         |
| `app/javascript/dashboard/api/inboxes.js` (`pairPhoneCode`)                                         | Frontend HTTP client.                                                                             |
| `app/javascript/dashboard/store/modules/inboxes.js` (`pairPhoneCode` action)                        | Vuex action.                                                                                      |
| `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue`   | UI: method picker + QR + phone-code code block.                                                   |
| `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue`                             | Connection-state panel surfaced on the inbox-settings tab.                                        |
| `app/javascript/shared/mixins/inboxMixin.js`, `app/javascript/dashboard/composables/useInbox.js`    | `isAWhatsAppPropriacloudChannel` predicate used across the dashboard.                             |
| `app/models/channel/whatsapp.rb`                                                                    | `propriacloud` registered in `PROVIDERS` and `REACTION_SUPPORTED_PROVIDERS`; `provider_service` dispatch. |
| `config/features.yml`                                                                               | `channel_whatsapp_propriacloud` feature toggle (replaces deprecated `channel_twitter` slot).      |
| `config/routes.rb`                                                                                  | Routes the webhook (existing) and `pair_phone_code` member action (new).                          |

## Environment variables

| Variable                    | Purpose                                                                                                                                                                                                  |
| :-------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `WHATSAPP_API_URL`          | Base URL of the whatsapp-api service. **Must include `/api/v1` prefix** (e.g. `http://host.docker.internal:8080/api/v1`). Falls back to `PROPRIACLOUD_PROVIDER_DEFAULT_URL`, then `CLICK2RUN_PROVIDER_DEFAULT_URL`. |
| `WHATSAPP_API_KEY`          | Bearer token sent to whatsapp-api on every request. Generated via the whatsapp-api admin tooling.                                                                                                        |
| `WHATSAPP_WEBHOOK_BASE_URL` | Base URL whatsapp-api should call back into. In Docker compose with separate stacks, this is the cross-network hostname (e.g. `http://chatwootgit-rails-1:3000`) — not `localhost`.                       |

The local docker compose stack also adds:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

to both `rails` and `sidekiq` so they can reach the whatsapp-api
container running on the host's loopback interface.

## Verifying the integration

End-to-end smoke (assumes whatsapp-api running and an instance already
created):

```bash
# 1. Confirm provider service is wired
docker compose exec -T rails bundle exec rails runner '
  ch = Channel::Whatsapp.find_by(provider: "propriacloud")
  puts "instance: #{ch.provider_config["instance_id"]}"
  puts "service:  #{ch.provider_service.class}"
'

# 2. Trigger phone-code pairing (replaces +5511999999999 with real number)
docker compose exec -T rails bundle exec rails runner '
  ch = Channel::Whatsapp.find_by(provider: "propriacloud")
  puts ch.provider_service.request_phone_pairing_code(ch.phone_number).inspect
'
# Expected: { "code" => "NFKR-GBMZ" } (8 alphanumeric chars, dash-separated)

# 3. Watch a webhook arriving (in another shell)
docker compose logs -f sidekiq | grep -E "PropriacloudHandlers|update_provider_connection"
```

QR-pull fallback (only used when the API replies "already connected"
instead of re-emitting `pairing.qrcode`):

```bash
docker compose exec -T rails bundle exec rails runner '
  ch = Channel::Whatsapp.find_by(provider: "propriacloud")
  ch.provider_service.fetch_and_publish_qr_code
  puts ch.reload.provider_connection.inspect
'
```

## Why a pull fallback exists at all

The push model is preserved in 100% of normal pairing flows. The
`fetch_and_publish_qr_code` helper exists strictly for this corner case:

> An instance was previously paired and remains in whatsapp-api's
> registry, but the WhatsApp session has expired silently (e.g. the user
> uninstalled WhatsApp on the phone). On the next `POST
> /instances/connect`, the API returns `"already connected"` and does
> **not** re-emit `pairing.qrcode`, leaving the Chatwoot UI without a QR
> to display.

In that case the helper does a one-shot GET against
`/instances/pair/qrcode` to seed `provider_connection.qr_data_url`. From
that point onward, all subsequent connection-state changes flow through
the normal push path again.

This is a UX patch around a single API-side edge case — it does not
shift the architecture from push to pull.

## Backward compatibility note

The internal Click2Run provider (`click2run`) is the old name of this
same integration before the Própria Cloud rebrand. The legacy provider
record is kept tolerant in the env-var resolution chain
(`WHATSAPP_API_URL` → `PROPRIACLOUD_PROVIDER_DEFAULT_URL` →
`CLICK2RUN_PROVIDER_DEFAULT_URL`) so existing dev environments keep
working while migrations roll out. New installs should use
`provider: 'propriacloud'`.
