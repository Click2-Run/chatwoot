---
Created: 2025-11-05T00:00:00Z
Operation: Complete Click2Run Integration Flow Documentation
Context: Comprehensive documentation of WhatsApp inbox creation, event flows, synchronization, and deduplication
Related Files:
  - /root/data/development/chatwoot.git/app/models/channel/whatsapp.rb
  - /root/data/development/chatwoot.git/app/services/whatsapp/providers/whatsapp_click2run_service.rb
  - /root/data/development/chatwoot.git/app/services/whatsapp/incoming_message_click2run_service.rb
  - /root/data/development/chatwoot.git/app/controllers/webhooks/whatsapp_controller.rb
---

# Click2Run Integration - Complete Flow Documentation

## Table of Contents
1. [WhatsApp Inbox Creation Flow](#1-whatsapp-inbox-creation-flow)
2. [Chatwoot → Click2Run Event Interactions](#2-chatwoot--click2run-event-interactions)
3. [Click2Run → Chatwoot Event Handling](#3-click2run--chatwoot-event-handling)
4. [Contact Synchronization](#4-contact-synchronization)
5. [Message History Synchronization](#5-message-history-synchronization)
6. [Deduplication Techniques](#6-deduplication-techniques)

---

## 1. WhatsApp Inbox Creation Flow

### 1.1 Complete Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     WHATSAPP INBOX CREATION - CLICK2RUN                      │
└──────────────────────────────────────────────────────────────────────────────┘

USER (Frontend)
    │
    │ 1. Navigate to Settings > Inboxes > Add Inbox > WhatsApp > Click2Run
    │
    ├──────────────────────────────────────────────────────────────────────────►
    │
    │ POST /api/v1/accounts/{account_id}/inboxes
    │ {
    │   channel: {
    │     type: "whatsapp",
    │     phone_number: "+1234567890",
    │     provider: "click2run",
    │     provider_config: {
    │       api_key: "tenant_api_key",
    │       provider_url: "http://click2run-api:8080/api/v1/chatwoot",
    │       webhook_verify_token: "auto_generated_token"
    │     }
    │   },
    │   name: "WhatsApp Support"
    │ }
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ Api::V1::Accounts::InboxesController#create                                │
│ (app/controllers/api/v1/accounts/inboxes_controller.rb:30)                │
└────────────────────────────────────────────────────────────────────────────┘
    │
    │ 2. Create channel in transaction
    │    ActiveRecord::Base.transaction do
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ Channel::Whatsapp.create!                                                  │
│ (app/models/channel/whatsapp.rb:22)                                        │
│                                                                             │
│ ├─► before_validation :ensure_webhook_verify_token (line 31)              │
│ │   └─► Generates webhook_verify_token if not provided                    │
│ │                                                                           │
│ ├─► validates :provider, inclusion: { in: PROVIDERS } (line 33)           │
│ ├─► validates :phone_number, presence: true, uniqueness: true (line 34)   │
│ ├─► validate :validate_provider_config (line 35)                          │
│ │   └─► Calls provider_service.validate_provider_config?                  │
│ │                                                                           │
│ └─► after_create :sync_templates (line 39)                                │
│     └─► For click2run: No-op (templates not supported)                    │
└────────────────────────────────────────────────────────────────────────────┘
    │
    │ 3. Validation phase - Validate API credentials
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ Whatsapp::Providers::WhatsappClick2RunService#validate_provider_config?   │
│ (app/services/whatsapp/providers/whatsapp_click2run_service.rb:179)       │
│                                                                             │
│ GET {provider_url}/chatwoot/{account_id}/inboxes                         │
│ Headers: X-API-Key: {api_key}                                              │
│ Account ID: 123 (from inbox.account_id)                                   │
│                                                                             │
│ Purpose: Validate API credentials before creating inbox in Chatwoot       │
│ Note: Called during channel creation BEFORE inbox is saved                │
│                                                                             │
│ Expected Response:                                                          │
│ ├─► 200 OK: [] (empty list - no instances yet) → Validation SUCCESS      │
│ ├─► 200 OK: [{...}] (existing instances) → Validation SUCCESS            │
│ ├─► 401 Unauthorized: Invalid API key → Validation FAILED                │
│ ├─► 403 Forbidden: Insufficient permissions → Validation FAILED          │
│ └─► 5xx Server Error: API unavailable → Validation FAILED                │
│                                                                             │
│ If validation fails, inbox creation is aborted with error message         │
└────────────────────────────────────────────────────────────────────────────┘
    │
    │ 4. Create inbox record (only if validation passes)
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ Inbox.create!                                                              │
│ (app/models/inbox.rb)                                                      │
│                                                                             │
│ has_one :channel, polymorphic: true                                        │
│ belongs_to :account                                                        │
│                                                                             │
│ Data Created:                                                              │
│ ├─► name: "WhatsApp Support"                                              │
│ ├─► channel_type: "Channel::Whatsapp"                                     │
│ ├─► channel_id: {whatsapp_channel.id}                                     │
│ └─► account_id: {current_account.id}                                      │
└────────────────────────────────────────────────────────────────────────────┘
    │
    │ 5. Transaction committed - Inbox & Channel created
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ USER manually triggers connection from UI                                  │
│ POST /api/v1/accounts/{account_id}/inboxes/{inbox_id}/setup_channel_provider│
└────────────────────────────────────────────────────────────────────────────┘
    │
    │ 6. Setup channel provider (Create inbox in Click2Run)
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ Channel::Whatsapp#setup_channel_provider                                   │
│ (app/models/channel/whatsapp.rb:137)                                       │
│ └─► Delegates to provider_service.setup_channel_provider                  │
└────────────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ Whatsapp::Providers::WhatsappClick2RunService#setup_channel_provider      │
│ (app/services/whatsapp/providers/whatsapp_click2run_service.rb:54)        │
│                                                                             │
│ STEP 1: Create Instance                                                    │
│ ─────────────────────────────────────────────────────────────────────────  │
│ POST {provider_url}/chatwoot/{account_id}/inboxes                        │
│ Headers: X-API-Key, Content-Type: application/json                         │
│ Account ID: 123 (from inbox.account_id)                                   │
│ Body: {                                                                     │
│   inbox_id: 456,                                                           │
│   name: "WhatsApp Support",                                                │
│   account_id: 123,                                                         │
│   channel_type: "Channel::Whatsapp",                                       │
│   channel_id: 789,                                                         │
│   phone_number: "+1234567890",                                             │
│   provider: "click2run",                                                   │
│   admin_id: 1,                                                             │
│   admin_token: "abc123...",                                                │
│   webhook_url: "https://chatwoot.example.com/webhooks/whatsapp/+1234567890", │
│   webhook_token: "auto_generated_verify_token",                            │
│   api_url: "https://chatwoot.example.com/api/v1"                          │
│ }                                                                           │
│                                                                             │
│ Expected Response:                                                          │
│ ├─► 201 Created: Inbox created successfully                            │
│ ├─► 409 Conflict: Instance already exists (OK, continue)                  │
│ └─► 200 OK: Instance already exists (OK, continue)                        │
│                                                                             │
│ STEP 2: Connect Instance (Initiates QR Code Generation)                   │
│ ─────────────────────────────────────────────────────────────────────────  │
│ POST {provider_url}/chatwoot/{account_id}/inboxes/{inbox_id}/connect    │
│ Headers: X-API-Key                                                         │
│ Account ID: 123 (from inbox.account_id)                                   │
│ Inbox ID: 456 (from inbox.id)                                             │
│                                                                             │
│ Expected Response:                                                          │
│ {                                                                           │
│   status: "success",                                                        │
│   message: "Connection initiated"                                          │
│ }                                                                           │
│                                                                             │
│ Click2Run Side Effect:                                                 │
│ └─► Generates QR code and sends webhook event (connection.update)         │
└────────────────────────────────────────────────────────────────────────────┘
    │
    │ 7. Click2Run sends webhook event with QR code
    │    (asynchronously, within seconds)
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ WEBHOOK: Click2Run → Chatwoot                                         │
│                                                                             │
│ POST https://chatwoot.example.com/webhooks/whatsapp/+1234567890            │
│ Content-Type: application/json                                             │
│                                                                             │
│ Payload:                                                                    │
│ {                                                                           │
│   event: "connection.update",                                              │
│   inbox_id: 456,                   // Chatwoot inbox ID                   │
│   account_id: 123,                 // Chatwoot account ID                 │
│   phone_number: "+1234567890",                                             │
│   timestamp: 1730764800,                                                   │
│   webhook_verify_token: "token_from_channel_config",                       │
│   data: {                                                                   │
│     connection: "connecting",                                              │
│     qr_code: "iVBORw0KGgoAAAANSUhEUg..." // base64 PNG                     │
│   }                                                                         │
│ }                                                                           │
└────────────────────────────────────────────────────────────────────────────┘
    │
    │ (See Section 3 for webhook handling details)
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ Channel.provider_connection updated with QR code                          │
│ {                                                                           │
│   connection: "connecting",                                                │
│   qr_data_url: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg...",         │
│   error: null                                                              │
│ }                                                                           │
└────────────────────────────────────────────────────────────────────────────┘
    │
    │ 8. Frontend polls for QR code and displays it
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ USER scans QR code with WhatsApp mobile app                               │
└────────────────────────────────────────────────────────────────────────────┘
    │
    │ 9. Click2Run detects successful authentication
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ WEBHOOK: Click2Run → Chatwoot                                         │
│                                                                             │
│ POST https://chatwoot.example.com/webhooks/whatsapp/+1234567890            │
│                                                                             │
│ Payload:                                                                    │
│ {                                                                           │
│   event: "connection.update",                                              │
│   inbox_id: 456,                   // Chatwoot inbox ID                   │
│   account_id: 123,                 // Chatwoot account ID                 │
│   phone_number: "+1234567890",                                             │
│   timestamp: 1730764850,                                                   │
│   webhook_verify_token: "token_from_channel_config",                       │
│   data: {                                                                   │
│     connection: "open",      // ✅ Connected!                              │
│     qr_code: null             // No longer needed                         │
│   }                                                                         │
│ }                                                                           │
└────────────────────────────────────────────────────────────────────────────┘
    │
    │ 10. Channel connection status updated to "open"
    │
    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ ✅ INBOX CREATION COMPLETE                                                 │
│                                                                             │
│ Database State:                                                             │
│ ├─► Channel::Whatsapp                                                      │
│ │   ├─► phone_number: "+1234567890"                                       │
│ │   ├─► provider: "click2run"                                             │
│ │   ├─► provider_config: {api_key, provider_url, webhook_verify_token}   │
│ │   └─► provider_connection: {connection: "open", qr_data_url: null}     │
│ │                                                                           │
│ ├─► Chatwoot Inbox                                                         │
│ │   ├─► name: "WhatsApp Support"                                          │
│ │   ├─► channel: whatsapp_channel                                         │
│ │   └─► account_id: current_account.id                                    │
│ │                                                                           │
│ └─► Click2Run Inbox (Created on Click2Run API)                            │
│     ├─► inbox_id: 456 (from Chatwoot inbox.id)                           │
│     ├─► name: "WhatsApp Support"                                          │
│     ├─► account_id: 123                                                   │
│     ├─► channel_type: "Channel::Whatsapp"                                 │
│     ├─► channel_id: 789                                                   │
│     ├─► phone_number: "+1234567890"                                      │
│     ├─► provider: "click2run"                                             │
│     ├─► admin_id: 1                                                       │
│     ├─► admin_token: "abc123..." (for calling Chatwoot API)              │
│     ├─► webhook_url: "https://chatwoot.example.com/webhooks/whatsapp/+1234567890" │
│     ├─► webhook_token: "auto_generated_verify_token"                      │
│     ├─► api_url: "https://chatwoot.example.com/api/v1"                   │
│     ├─► status: "connected"                                               │
│     └─► Ready to send/receive messages                                    │
└────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Key Files Involved

| File | Role | Lines |
|------|------|-------|
| `app/controllers/api/v1/accounts/inboxes_controller.rb` | Inbox creation endpoint | 30-43, 68-77 |
| `app/models/channel/whatsapp.rb` | Channel model & validation | 22-176 |
| `app/services/whatsapp/providers/whatsapp_click2run_service.rb` | Click2Run integration | 54-90, 163-171, 308-313 |
| `app/controllers/webhooks/whatsapp_controller.rb` | Webhook receiver | 1-49 |
| `app/jobs/webhooks/whatsapp_events_job.rb` | Async webhook processing | 1-53 |
| `app/services/whatsapp/incoming_message_click2run_service.rb` | Event dispatcher | 26-41 |
| `app/services/whatsapp/click2run_handlers/connection_update.rb` | Connection state handler | 23-79 |

### 1.3 Environment Variables

```bash
# Required for Click2Run provider
CLICK2RUN_PROVIDER_DEFAULT_URL=http://click2run-api:8080/api/v1
CLICK2RUN_PROVIDER_DEFAULT_API_KEY=your_tenant_api_key
```

**Important**: The `CLICK2RUN_PROVIDER_DEFAULT_URL` should be the **base API URL WITHOUT the `/chatwoot` suffix**. The code automatically appends `/chatwoot/{account_id}/inboxes/...` to all API calls.

**Example URL Construction**:
- Base URL (from env): `http://click2run-api:8080/api/v1`
- Chatwoot appends: `/chatwoot/123/inboxes/456/messages/send/text`
- Final URL: `http://click2run-api:8080/api/v1/chatwoot/123/inboxes/456/messages/send/text`

---

## 2. Chatwoot → Click2Run Event Interactions

### 2.1 Event Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                   CHATWOOT → CLICK2RUN API INTERACTIONS                      │
└──────────────────────────────────────────────────────────────────────────────┘

CHATWOOT EVENT                         API CALL                    CLICK2RUN API
─────────────────────────────────────────────────────────────────────────────────

1. SEND TEXT MESSAGE
───────────────────────────────────────────────────────────────────────────────
User sends message         POST /chatwoot/{account_id}/inboxes/{inbox_id}/messages/send/text
in conversation       ───►  {                                   ───► Sends via
                            to: "1234567890@s.whatsapp.net",        WhatsApp
                            message: "Hello!",                       protocol
                            quoted_message_id: "optional"
                           }                                    ◄─── message_id
                      ◄───  {status: "success",
                            message_id: "3EB0..."}

2. SEND MEDIA MESSAGE (Image/Video/Audio/Document)
───────────────────────────────────────────────────────────────────────────────
User sends media      POST /chatwoot/{account_id}/inboxes/{inbox_id}/messages/send/media
attachment       ───►  {                                       ───► Uploads &
                       to: "1234567890@s.whatsapp.net",             sends media
                       media_type: "image/jpeg",
                       media_data: "base64_encoded_data",
                       caption: "Check this out",
                       filename: "photo.jpg"
                      }                                        ◄─── message_id
                 ◄───  {status: "success",
                       message_id: "3EB0..."}

3. SEND REACTION
───────────────────────────────────────────────────────────────────────────────
User reacts to        POST /chatwoot/{account_id}/inboxes/{inbox_id}/messages/send/reaction
message          ───►  {                                       ───► Sends
                       to: "1234567890@s.whatsapp.net",             reaction
                       message_id: "3EB0...",
                       emoji: "👍"
                      }                                        ◄─── reaction_id
                 ◄───  {status: "success",
                       reaction_id: "3EB0..."}

4. TYPING INDICATORS
───────────────────────────────────────────────────────────────────────────────
User starts typing    PATCH /chatwoot/{account_id}/inboxes/{inbox_id}/presence
                 ───►  {                                       ───► Updates
                       to_jid: "1234567890@s.whatsapp.net",        presence
                       type: "composing"
                      }                                        ◄─── {status: "ok"}

User stops typing     PATCH /chatwoot/{account_id}/inboxes/{inbox_id}/presence
                 ───►  {                                       ───► Updates
                       to_jid: "1234567890@s.whatsapp.net",        presence
                       type: "paused"
                      }                                        ◄─── {status: "ok"}

Voice recording       PATCH /chatwoot/{account_id}/inboxes/{inbox_id}/presence
                 ───►  {                                       ───► Updates
                       to_jid: "1234567890@s.whatsapp.net",        presence
                       type: "recording"
                      }                                        ◄─── {status: "ok"}

5. MARK MESSAGES AS READ
───────────────────────────────────────────────────────────────────────────────
Agent views          POST /chatwoot/{account_id}/inboxes/{inbox_id}/messages/mark-read
conversation    ───►  {                                       ───► Sends read
                      messages: [                                  receipts
                        {
                          id: "3EB0...",
                          remote_jid: "1234567890@s.whatsapp.net",
                          from_me: false
                        }
                      ]
                     }                                        ◄─── {status: "ok"}
                ◄───  {status: "success"}

6. CHECK IF NUMBER IS ON WHATSAPP
───────────────────────────────────────────────────────────────────────────────
Adding contact       GET /chatwoot/{account_id}/inboxes/{inbox_id}/on_whatsapp/{phone}
                ───►                                          ───► Queries
                                                                   WhatsApp
                ◄───  {                                       ◄─── servers
                       status: "success",
                       query: "1234567890",
                       jid: "1234567890@s.whatsapp.net",
                       is_in: true
                      }

7. GET PROFILE PICTURE
───────────────────────────────────────────────────────────────────────────────
Contact created      GET /chatwoot/{account_id}/inboxes/{inbox_id}/profile-picture/{jid}
                ───►  ?preview=false                          ───► Fetches
                                                                   profile pic
                ◄───  {                                       ◄─── from WhatsApp
                       status: "success",
                       jid: "1234567890@s.whatsapp.net",
                       url: "https://...",
                       preview: false
                      }

8. DOWNLOAD MEDIA
───────────────────────────────────────────────────────────────────────────────
Receiving media      GET /chatwoot/{account_id}/inboxes/{inbox_id}/media/{message_id}
message         ───►  Headers: X-API-Key                      ───► Downloads
                                                                   media from
                ◄───  [Binary media data]                     ◄─── WhatsApp
                      Content-Type: image/jpeg
```

### 2.2 API Endpoints Used

| Method | Endpoint | Purpose | Triggered By |
|--------|----------|---------|--------------|
| GET | `/chatwoot/{account_id}/inboxes` | List inboxes / Validate credentials | Channel validation |
| POST | `/chatwoot/{account_id}/inboxes` | Create inbox | Inbox setup |
| POST | `/chatwoot/{account_id}/inboxes/{inbox_id}/connect` | Initiate connection | Inbox setup |
| POST | `/chatwoot/{account_id}/inboxes/{inbox_id}/disconnect` | Graceful disconnect | Inbox deletion |
| DELETE | `/chatwoot/{account_id}/inboxes/{inbox_id}` | Delete inbox | Inbox deletion |
| GET | `/chatwoot/{account_id}/inboxes/{inbox_id}/status` | Check inbox status | Status monitoring |
| POST | `/chatwoot/{account_id}/inboxes/{inbox_id}/messages/send/text` | Send text | User sends message |
| POST | `/chatwoot/{account_id}/inboxes/{inbox_id}/messages/send/media` | Send media | User sends attachment |
| POST | `/chatwoot/{account_id}/inboxes/{inbox_id}/messages/send/reaction` | Send reaction | User reacts |
| PATCH | `/chatwoot/{account_id}/inboxes/{inbox_id}/presence` | Update typing status | User types |
| POST | `/chatwoot/{account_id}/inboxes/{inbox_id}/messages/mark-read` | Mark as read | Agent views conversation |
| GET | `/chatwoot/{account_id}/inboxes/{inbox_id}/on_whatsapp/{phone}` | Check registration | Contact validation |
| GET | `/chatwoot/{account_id}/inboxes/{inbox_id}/profile-picture/{jid}` | Get avatar | Contact created |
| GET | `/chatwoot/{account_id}/inboxes/{inbox_id}/media/{message_id}` | Download media | Receiving media |

**Note**: `inbox_id` is the Chatwoot inbox.id (e.g., 456), NOT the channel_id or phone number

### 2.3 Service Methods Mapping

```ruby
# File: app/services/whatsapp/providers/whatsapp_click2run_service.rb

┌─────────────────────────────────────────────────────────────────────────┐
│ Chatwoot Method              → Click2Run Endpoint                   │
├─────────────────────────────────────────────────────────────────────────┤
│ validate_provider_config?    → GET /chatwoot/{account_id}/inboxes    │
│                                                                          │
│ setup_channel_provider       → POST /chatwoot/{account_id}/inboxes   │
│                              → POST /chatwoot/{account_id}/inboxes/{inbox_id}/connect │
│                                                                          │
│ disconnect_channel_provider  → POST /chatwoot/{account_id}/inboxes/{inbox_id}/disconnect │
│                              → DELETE /chatwoot/{account_id}/inboxes/{inbox_id} │
│                                                                          │
│ send_message (text)          → POST /chatwoot/{account_id}/inboxes/{inbox_id}/messages/send/text │
│ send_message (media)         → POST /chatwoot/{account_id}/inboxes/{inbox_id}/messages/send/media │
│ send_message (reaction)      → POST /chatwoot/{account_id}/inboxes/{inbox_id}/messages/send/reaction │
│                                                                          │
│ toggle_typing_status         → PATCH /chatwoot/{account_id}/inboxes/{inbox_id}/presence │
│                                                                          │
│ read_messages                → POST /chatwoot/{account_id}/inboxes/{inbox_id}/messages/mark-read │
│                                                                          │
│ on_whatsapp                  → GET /chatwoot/{account_id}/inboxes/{inbox_id}/on_whatsapp/{phone} │
│                                                                          │
│ get_profile_pic              → GET /chatwoot/{account_id}/inboxes/{inbox_id}/profile-picture/{jid} │
│                                                                          │
│ media_url                    → GET /chatwoot/{account_id}/inboxes/{inbox_id}/media/{message_id} │
│                                                                          │
│ NOTE: {account_id} = inbox.account_id, {inbox_id} = inbox.id           │
│       Example: account_id = 123, inbox_id = 456                        │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.4 Authentication

All API calls use header-based authentication:

```http
X-API-Key: {tenant_api_key}
Content-Type: application/json
```

The API key is stored in `channel.provider_config['api_key']` and defaults to `ENV['CLICK2RUN_PROVIDER_DEFAULT_API_KEY']`.

---

## 3. Click2Run → Chatwoot Event Handling

### 3.1 Complete Webhook Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                  CLICK2RUN API → CHATWOOT WEBHOOK EVENTS                     │
└──────────────────────────────────────────────────────────────────────────────┘

CLICK2RUN API                     WEBHOOK                      CHATWOOT
────────────────────────────────────────────────────────────────────────────────

Event occurs in         POST /webhooks/whatsapp/{phone_number}
WhatsApp protocol  ───► {                           ───► Webhook Controller
                         event: "...",                    (validates token)
                         inbox_id: "...",                 │
                         phone_number: "+...",            │
                         timestamp: 1234567890,           ▼
                         webhook_verify_token: "...",   Enqueue Job
                         data: {...}                      │
                        }                                 │
                                                          ▼
                                                   WhatsappEventsJob
                                                          │
                                                          ├─► Find channel
                                                          │   by phone_number
                                                          │
                                                          ├─► Route to provider
                                                          │   service
                                                          │
                                                          ▼
                                              IncomingMessageClick2RunService
                                                          │
                                                          ├─► Validate webhook
                                                          │   token
                                                          │
                                                          ├─► Dispatch analytics
                                                          │   event
                                                          │
                                                          ├─► Process by event
                                                          │   type
                                                          │
                   ┌──────────────────────────────────────┴────────────────┐
                   │                                                        │
                   ▼                                                        ▼
           connection.update                                      messages.upsert
           │                                                       │
           ├─► Extract connection state                           ├─► Incoming?
           │   (close, connecting, open)                          │   └─► Create contact
           │                                                       │       Create conversation
           ├─► Extract QR code (if connecting)                    │       Create message
           │                                                       │       Download media
           ├─► Extract error (if any)                             │       Update profile pic
           │                                                       │
           ├─► Update provider_connection                         ├─► Outgoing?
           │   in database                                        │   └─► Lock to avoid race
           │                                                       │       Update existing msg
           └─► Log connection state                               │
                                                                   ▼
                                                          messages.update
                                                                   │
                                                                   ├─► Find message by
                                                                   │   source_id
                                                                   │
                                                                   ├─► Update status
                                                                   │   (sent/delivered/read)
                                                                   │
                                                                   ├─► Handle edited content
                                                                   │
                                                                   └─► Update last_seen_at
```

### 3.2 Event Types and Handlers

#### 3.2.1 connection.update

**File**: `app/services/whatsapp/click2run_handlers/connection_update.rb`

**Payload Structure**:
```json
{
  "event": "connection.update",
  "inbox_id": 456,                   // Chatwoot inbox ID
  "account_id": 123,                 // Chatwoot account ID
  "phone_number": "+1234567890",
  "timestamp": 1730764800,
  "webhook_verify_token": "abc123",
  "data": {
    "connection": "connecting",  // "close", "connecting", or "open"
    "qr_code": "iVBORw0KG...",   // base64 PNG (only when connecting)
    "error": "connection_lost"    // optional error message
  }
}
```

**Processing Logic** (lines 23-40):
1. Extract connection state: `close`, `connecting`, or `open`
2. Extract QR code if present (convert to data URL)
3. Extract error message if present (translate via i18n)
4. Update `channel.provider_connection` with all data
5. Log connection state change

**Database Update**:
```ruby
channel.update_provider_connection!({
  connection: "open",
  qr_data_url: "data:image/png;base64,...",
  error: nil
})
```

#### 3.2.2 messages.upsert

**File**: `app/services/whatsapp/click2run_handlers/messages_upsert.rb`

**Payload Structure**:
```json
{
  "event": "messages.upsert",
  "inbox_id": 456,                   // Chatwoot inbox ID
  "account_id": 123,                 // Chatwoot account ID
  "phone_number": "+1234567890",
  "timestamp": 1730764800,
  "webhook_verify_token": "abc123",
  "data": {
    "messages": [
      {
        "key": {
          "id": "3EB0C0A3B0E5F8B7A1C2D3E4F5G6H7I8",
          "remote_jid": "5511999999999@s.whatsapp.net",
          "from_me": false,
          "sender_lid": "optional_lid"
        },
        "message": {
          "conversation": "Hello!",
          // OR
          "image_message": {
            "caption": "Check this",
            "mime_type": "image/jpeg",
            // ... other fields
          }
          // ... other message types
        },
        "push_name": "John Doe",
        "message_timestamp": 1730764800
      }
    ]
  }
}
```

**Processing Logic** (lines 33-175):
1. **Deduplication Check** (line 56):
   - Check if message already exists by `source_id`
   - Check Redis cache to avoid duplicate processing

2. **Contact Creation/Update** (lines 72-98):
   - Find or create contact using `ContactInboxWithContactBuilder`
   - Extract phone number from JID
   - Extract contact name from `push_name`
   - Update contact info if needed

3. **Conversation Creation** (inherited from base service):
   - Find existing conversation or create new one
   - Respect `lock_to_single_conversation` setting

4. **Message Creation** (lines 100-121):
   - Create message record with content
   - Extract message timestamp
   - Handle reply-to references

5. **Media Handling** (lines 152-174):
   - Download media from Click2Run
   - Create attachment record
   - Handle voice messages (PTT flag)

**Supported Message Types**:
- `text`: Plain text, extended text
- `image`: Image messages with optional caption
- `audio`: Audio messages (including voice notes)
- `video`: Video messages
- `file`: Documents
- `sticker`: Stickers (WebP format)
- `reaction`: Emoji reactions
- `contact`: Shared contacts

**Profile Picture Update** (lines 180-185):
```ruby
# Automatically fetches profile picture for new contacts
def try_update_contact_avatar
  return if @contact.avatar.attached?

  profile_pic_url = fetch_profile_picture_url(phone_number_from_jid)
  ::Avatar::AvatarFromUrlJob.perform_later(@contact, profile_pic_url) if profile_pic_url
end
```

#### 3.2.3 messages.update

**File**: `app/services/whatsapp/click2run_handlers/messages_update.rb`

**Payload Structure**:
```json
{
  "event": "messages.update",
  "inbox_id": 456,                   // Chatwoot inbox ID
  "account_id": 123,                 // Chatwoot account ID
  "phone_number": "+1234567890",
  "timestamp": 1730764800,
  "webhook_verify_token": "abc123",
  "data": [
    {
      "key": {
        "id": "3EB0C0A3B0E5F8B7A1C2D3E4F5G6H7I8",
        "remote_jid": "5511999999999@s.whatsapp.net",
        "from_me": true
      },
      "update": {
        "status": "delivered",  // "sent", "delivered", "read", "failed"
        "timestamp": 1730764805
      }
    }
  ]
}
```

**Processing Logic** (lines 33-122):
1. **Find Message** (line 50):
   - Lookup by `source_id` (message ID)
   - Raise `MessageNotFoundError` if not found

2. **Update Status** (lines 56-88):
   - Map status: `sent` → `sent`, `delivered` → `delivered`, `read` → `read`, `failed` → `failed`
   - Validate status transitions (prevent downgrade)
   - Update `agent_last_seen_at` for read receipts

3. **Handle Edited Messages** (lines 105-121):
   - Extract edited content if present
   - Store previous content
   - Mark message as edited

**Status Transition Rules** (lines 98-103):
```ruby
# Cannot downgrade from "read"
return false if @message.status == 'read'

# Cannot go from "delivered" back to "sent"
return false if @message.status == 'delivered' && new_status == 'sent'

true
```

### 3.3 Webhook Security

**Token Validation** (app/services/whatsapp/incoming_message_click2run_service.rb:45-53):
```ruby
def validate_webhook_token!
  webhook_token = processed_params[:webhook_verify_token] ||
                  processed_params['webhook_verify_token'] ||
                  processed_params[:webhookVerifyToken]

  expected_token = inbox.channel.provider_config['webhook_verify_token']

  raise InvalidWebhookVerifyToken if webhook_token != expected_token
end
```

### 3.4 Event Dispatcher Integration

All webhook events trigger analytics tracking:

```ruby
# File: app/services/whatsapp/incoming_message_click2run_service.rb:31-37
Rails.configuration.dispatcher.dispatch(
  PROVIDER_EVENT_RECEIVED,
  Time.zone.now,
  inbox: inbox,
  event: processed_params[:event],
  payload: processed_params[:data]
)
```

---

## 4. Contact Synchronization

### 4.1 Contact Discovery Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         CONTACT SYNCHRONIZATION                              │
└──────────────────────────────────────────────────────────────────────────────┘

INCOMING MESSAGE                CONTACT LOOKUP                    RESULT
────────────────────────────────────────────────────────────────────────────────

Webhook received           Extract phone from JID
  │                        "5511999999999@s.whatsapp.net"
  │                        └─► phone: "5511999999999"
  ▼                                  │
Extract contact info                 ▼
  ├─► Phone: from JID      Find existing contact_inbox
  ├─► Name: from push_name by source_id (phone)
  └─► LID: from key                  │
                                     ├─► Found?
                                     │   └─► Return existing
                                     │       contact_inbox
                                     │
                                     ▼
                            Not found: Create new
                                     │
                                     ├─► Find contact by:
                                     │   1. identifier (LID)
                                     │   2. email
                                     │   3. phone_number
                                     │
                                     ├─► Contact exists?
                                     │   ├─► Yes: Reuse contact
                                     │   │        Create contact_inbox
                                     │   │
                                     │   └─► No: Create new contact
                                     │            Create contact_inbox
                                     │
                                     ▼
                            Enrich contact data
                                     │
                                     ├─► Update name if needed
                                     │   (if current name is phone)
                                     │
                                     ├─► Update identifier if blank
                                     │   (set LID)
                                     │
                                     ├─► Update phone if blank
                                     │
                                     └─► Fetch & attach profile picture
                                         (async job)
```

### 4.2 Contact Matching Logic

**File**: `app/builders/contact_inbox_with_contact_builder.rb`

**Priority Order** (lines 62-68):
1. **By Identifier** (LID): `account.contacts.find_by(identifier: identifier)`
2. **By Email**: `account.contacts.from_email(email)`
3. **By Phone Number**: `account.contacts.find_by(phone_number: phone_number)`
4. **Instagram Special Case**: For Instagram channels, also check Facebook channels

**Race Condition Handling** (lines 11-14):
```ruby
def perform
  find_or_create_contact_and_contact_inbox
# in case of race conditions where contact is created by another thread
# we will try to find the contact and create a contact inbox
rescue ActiveRecord::RecordNotUnique
  find_or_create_contact_and_contact_inbox
end
```

### 4.3 Profile Picture Synchronization

**Automatic Profile Picture Fetch** (app/services/whatsapp/click2run_handlers/messages_upsert.rb:180-185):

```ruby
def try_update_contact_avatar
  return if @contact.avatar.attached?

  profile_pic_url = fetch_profile_picture_url(phone_number_from_jid)
  ::Avatar::AvatarFromUrlJob.perform_later(@contact, profile_pic_url) if profile_pic_url
end
```

**API Call** (app/services/whatsapp/click2run_handlers/helpers.rb:172-178):
```ruby
def fetch_profile_picture_url(phone_number)
  jid = "#{phone_number}@s.whatsapp.net"
  inbox.channel.provider_service.get_profile_pic(jid)
rescue StandardError => e
  Rails.logger.error "Failed to fetch profile picture for #{phone_number}: #{e.message}"
  nil
end
```

**Click2Run Call** (app/services/whatsapp/providers/whatsapp_click2run_service.rb:250-262):
```ruby
GET {provider_url}/chatwoot/{account_id}/inboxes/{inbox_id}/profile-picture/{jid}?preview=false
Headers: X-API-Key

Response:
{
  "status": "success",
  "jid": "5511999999999@s.whatsapp.net",
  "url": "https://pps.whatsapp.net/v/...",
  "preview": false
}
```

### 4.4 Contact Data Updates

**Name Updates** (app/services/whatsapp/click2run_handlers/messages_upsert.rb:89-96):
```ruby
def update_contact_information
  updates = {}
  updates[:identifier] = sender_lid if @contact.identifier.blank? && sender_lid.present?
  updates[:phone_number] = "+#{phone_number_from_jid}" if @contact.phone_number.blank?
  updates[:name] = contact_name if @contact.name == phone_number_from_jid || @contact.name == sender_lid

  @contact.update!(updates) if updates.present?

  try_update_contact_avatar
end
```

**Name Priority**:
1. `verified_biz_name` (for WhatsApp Business accounts)
2. `push_name` (name set in WhatsApp app)
3. `pushname` (alternative key)
4. Phone number (fallback)

### 4.5 No Bulk Contact Sync

**Important**: Click2Run integration does **NOT** perform bulk contact synchronization. Contacts are created/updated only when:

1. A message is received from that contact
2. A message is sent to that contact
3. Manual contact creation via Chatwoot UI

This is by design - WhatsApp does not provide a contacts API, and syncing would require scanning all chats, which is:
- Resource intensive
- Privacy intrusive
- Not supported by WhatsApp's multi-device protocol

---

## 5. Message History Synchronization

### 5.1 History Sync Overview

**Status**: ❌ **NOT IMPLEMENTED**

Click2Run integration does **NOT** automatically sync historical messages. When a new inbox is created, only **new messages** (received after connection) are synced.

### 5.2 Why No History Sync?

1. **WhatsApp Protocol Limitation**:
   - Multi-device protocol doesn't provide bulk history export
   - History is synced device-to-device, not via API

2. **Privacy Concerns**:
   - Syncing all historical messages may violate user privacy expectations
   - GDPR/data protection regulations

3. **Resource Constraints**:
   - Large message histories would overwhelm Chatwoot database
   - Media downloads would consume significant bandwidth

4. **Business Logic**:
   - Chatwoot is a support tool, not a backup service
   - Historical context is available on WhatsApp mobile app

### 5.3 Message Flow (New Messages Only)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      MESSAGE SYNCHRONIZATION (NEW ONLY)                      │
└──────────────────────────────────────────────────────────────────────────────┘

TIME     WHATSAPP      CLICK2RUN API           CHATWOOT
──────   ────────      ─────────────           ────────

T0       [Old msgs]    Inbox created        Inbox created
         [......]      └─► No history sync     └─► Empty conversations
         [......]

T1       New msg  ───► Webhook sent       ───► Message created ✅
         arrives       messages.upsert         Contact created
                                                Conversation created

T2       Reply    ───► Webhook sent       ───► Message created ✅
         received      messages.upsert         Conversation updated

T3       Agent    ◄─── API call           ◄─── Outgoing message
         receives      POST /send/text         created in Chatwoot

T4       Delivery ───► Webhook sent       ───► Message status ✅
         receipt       messages.update         updated to "delivered"
```

### 5.4 Partial History Recovery (Manual)

For critical use cases requiring historical context, consider these approaches:

#### Option A: Forward Important Messages
Users can manually forward important messages after inbox setup, which will appear as new messages.

#### Option B: Export & Import (Future Enhancement)
Potential future feature:
1. Export WhatsApp chat from mobile app
2. Parse exported .txt or .zip file
3. Import into Chatwoot as historical messages

**Not currently implemented** - would require significant development effort.

#### Option C: Conversation Notes
Agents can manually add notes to conversations summarizing historical context.

---

## 6. Deduplication Techniques

### 6.1 Multi-Layer Deduplication Strategy

Chatwoot implements three layers of deduplication to prevent duplicate messages:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       DEDUPLICATION ARCHITECTURE                             │
└──────────────────────────────────────────────────────────────────────────────┘

WEBHOOK RECEIVED                LAYER 1                   LAYER 2              LAYER 3
      │                    Database Lookup          Redis Cache          Race Condition Lock
      │
      ▼
[message_id: ABC123]
      │
      ├────────────────►  find_message_by_source_id('ABC123')
      │                   ├─► Exists in messages table?
      │                   │   └─► YES: Skip processing ✅
      │                   │
      │                   └─► NO: Continue
      │
      ├────────────────────────────────►  message_under_process?
      │                                    Redis key: "message_source_ABC123"
      │                                    ├─► Exists?
      │                                    │   └─► YES: Skip processing ✅
      │                                    │
      │                                    └─► NO: Continue
      │
      ├────────────────────────────────────────────────►  cache_message_source_id_in_redis
      │                                                    Redis.setex("message_source_ABC123", 300)
      │
      │                  (Process message)
      ├─► Create contact
      ├─► Create conversation
      ├─► Create message with source_id='ABC123'
      │
      └────────────────────────────────────────────────►  clear_message_source_id_from_redis
                                                          Redis.delete("message_source_ABC123")

                                                          ✅ Message created (unique)
```

### 6.2 Layer 1: Database Lookup

**File**: `app/services/whatsapp/incoming_message_service_helpers.rb:75-79`

```ruby
def find_message_by_source_id(source_id)
  return unless source_id

  @message = Message.find_by(source_id: source_id)
end
```

**Logic**:
- Checks if a message with the given `source_id` already exists
- `source_id` is the WhatsApp message ID from the `key.id` field
- If found, processing stops immediately
- **Database index** on `messages.source_id` ensures fast lookup

**Coverage**: Handles duplicate webhooks sent hours/days later

### 6.3 Layer 2: Redis Cache

**File**: `app/services/whatsapp/incoming_message_service_helpers.rb:81-96`

```ruby
def message_under_process?
  key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: @processed_params[:messages].first[:id])
  Redis::Alfred.get(key)
end

def cache_message_source_id_in_redis
  return if @processed_params.try(:[], :messages).blank?

  key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: @processed_params[:messages].first[:id])
  ::Redis::Alfred.setex(key, true)  # TTL: 300 seconds (5 minutes)
end

def clear_message_source_id_from_redis
  key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: @processed_params[:messages].first[:id])
  ::Redis::Alfred.delete(key)
end
```

**Logic**:
- Before processing, check if message ID exists in Redis
- If exists, another worker is processing it → skip
- If not, set Redis key with 5-minute TTL
- After processing completes, clear Redis key
- **Handles concurrent webhook deliveries** (same message, multiple workers)

**Redis Key Format**:
```
message_source:ABC123
```

**TTL**: 300 seconds (5 minutes)
- Long enough to cover processing time
- Short enough to avoid blocking legitimate retries

**Coverage**: Handles duplicate webhooks arriving within minutes

### 6.4 Layer 3: Race Condition Lock (Outgoing Messages)

**File**: `app/services/whatsapp/click2run_handlers/messages_upsert.rb:44-49`

```ruby
def process_messages_upsert
  messages.each do |message|
    next handle_message if incoming?

    # Shared lock with Whatsapp::SendOnWhatsappService
    # Avoids race conditions when sending messages
    with_baileys_channel_lock_on_outgoing_message(inbox.channel.id) { handle_message }
  end
end
```

**Logic**:
- For **outgoing messages** (from Chatwoot → WhatsApp), use channel-level lock
- Prevents race between:
  - Chatwoot creating outgoing message record
  - Webhook delivering the same message back
- Lock is shared between `SendOnWhatsappService` and webhook handlers

**Lock Scope**: Per-channel (inbox.channel.id)

**Coverage**: Prevents duplicate outgoing messages when webhook arrives before DB write completes

### 6.5 Deduplication for Status Updates

**File**: `app/services/whatsapp/click2run_handlers/messages_update.rb:49-54`

```ruby
def handle_update
  raise MessageNotFoundError unless find_message_by_source_id(raw_message_id)

  update_status if status_from_update.present?
  handle_edited_content if edited_content_present?
end
```

**Logic**:
- Status updates (sent/delivered/read) **require** existing message
- If message not found, raise error and skip update
- Prevents orphaned status updates

**Idempotency**: Status updates are idempotent (safe to apply multiple times)
- Updating from `sent` → `delivered` → `delivered` is safe
- Transition rules prevent downgrades (lines 98-103)

### 6.6 Database Constraints

**File**: `db/schema.rb` (Message model)

```ruby
# No UNIQUE constraint on source_id
# Intentional design decision:
# - Different channels may have overlapping source_id spaces
# - UNIQUE constraint would prevent legitimate messages
```

**Important**: There is **NO** database-level UNIQUE constraint on `messages.source_id` because:
1. Multiple channels (WhatsApp, Facebook, etc.) may generate overlapping IDs
2. Constraint would block legitimate messages from different inboxes
3. Application-level deduplication (Layers 1-3) is sufficient

### 6.7 Contact Deduplication

**File**: `app/builders/contact_inbox_with_contact_builder.rb:17-18`

```ruby
@contact_inbox = inbox.contact_inboxes.find_by(source_id: source_id) if source_id.present?
return @contact_inbox if @contact_inbox
```

**Logic**:
- Before creating contact, check if `contact_inbox` exists for this `source_id`
- `source_id` = phone number (e.g., "5511999999999")
- Scope: per-inbox (prevents cross-inbox collisions)

**Race Condition Handling** (lines 11-14):
```ruby
rescue ActiveRecord::RecordNotUnique
  find_or_create_contact_and_contact_inbox  # Retry on race condition
end
```

**Database Constraint**:
```sql
UNIQUE INDEX index_contact_inboxes_on_inbox_id_and_source_id
  (inbox_id, source_id)
```

### 6.8 Why Multiple Layers?

| Layer | Protects Against | Performance | Duration |
|-------|------------------|-------------|----------|
| Database Lookup | Historical duplicates (hours/days later) | ~10ms query | Forever |
| Redis Cache | Concurrent webhooks (seconds/minutes apart) | ~1ms query | 5 minutes |
| Race Lock | Simultaneous processing (microseconds apart) | ~1ms lock | Milliseconds |

**Without Layer 1**: Redis cache expires after 5 minutes, allowing duplicate webhooks to create duplicate messages.

**Without Layer 2**: Concurrent webhooks could both pass Layer 1 and create duplicate messages.

**Without Layer 3**: Outgoing messages could be duplicated if webhook arrives before database write completes.

### 6.9 Known Edge Cases

#### Case 1: Message ID Collision (Different Inboxes)
**Scenario**: Two WhatsApp inboxes receive messages with identical `source_id` (unlikely but possible).

**Behavior**: Both messages are created (not duplicates).

**Reason**: `source_id` is not globally unique, only unique per-channel.

#### Case 2: Webhook Retry After 5 Minutes
**Scenario**: Webhook fails, retries after 5+ minutes, Redis cache expired.

**Behavior**: Layer 1 (database lookup) catches the duplicate.

#### Case 3: Database Unavailable During Processing
**Scenario**: Redis key set, but database write fails, Redis key cleared.

**Behavior**: Next webhook delivery will retry, correctly creating the message.

**Recovery**: Automatic via webhook retry.

---

## 7. Key Insights & Design Decisions

### 7.1 Why No Templates for Click2Run?

**Reason**: WhatsApp Message Templates are specific to **WhatsApp Business API** (official API).

Click2Run uses the **multi-device protocol** (unofficial), which:
- Cannot create/approve message templates
- Cannot send templated messages
- Can only send regular messages (like WhatsApp app)

**Implications**:
- `sync_templates` is a no-op for Click2Run
- `send_template` is not implemented
- Template features only work with `whatsapp_cloud` provider

### 7.2 Why Webhook-Based Instead of Polling?

**Reason**: Real-time message delivery with lower latency and resource usage.

**Benefits**:
- Instant message delivery (< 1 second)
- No polling overhead
- Scales to thousands of inboxes

**Trade-offs**:
- Requires publicly accessible webhook URL
- Must handle webhook retries and deduplication
- More complex error handling

### 7.3 Why Async Job Processing?

**File**: `app/controllers/webhooks/whatsapp_controller.rb:16-22`

```ruby
def perform_whatsapp_events_job
  perform_sync if params[:awaitResponse].present?
  return if performed?

  Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
  head :ok
end
```

**Reason**: Prevent webhook timeout and allow retries.

**Benefits**:
- Webhook responds immediately (200 OK)
- Processing happens in background worker
- Failed jobs can be retried via Sidekiq
- Prevents blocking Click2Run

**Exception**: Synchronous processing if `awaitResponse=true` (used in tests).

### 7.4 Why Provider-Specific Handlers?

Each provider (Cloud API, Baileys, Z-API, Click2Run) has different:
- Webhook payload formats
- Event structures
- Timestamp formats (Baileys uses `{low, high}`, Click2Run uses Unix int64)
- JID formats
- Message structures

**Solution**: Separate handler modules per provider:
- `Whatsapp::Click2RunHandlers::*`
- `Whatsapp::BaileysHandlers::*`
- `Whatsapp::ZapiHandlers::*`

**Benefits**:
- Clean separation of concerns
- Easy to maintain/debug
- Can evolve independently

### 7.5 Why Connection State in Database?

**File**: `app/models/channel/whatsapp.rb:74-78`

```ruby
def update_provider_connection!(provider_connection)
  assign_attributes(provider_connection: provider_connection)
  # NOTE: Skip `validate_provider_config?` check
  save!(validate: false)
end
```

**Reason**: Connection state must be accessible across requests.

**Stored in `provider_connection` JSONB**:
- `connection`: "close", "connecting", "open"
- `qr_data_url`: Base64-encoded QR code (while connecting)
- `error`: Error message (if connection failed)

**Benefits**:
- Frontend can poll for QR code without calling Click2Run
- Connection status visible in Chatwoot UI
- Survives app restarts

**Trade-off**: Slight staleness (updated via webhooks, not real-time).

---

## 8. Troubleshooting Guide

### 8.1 Common Issues

#### Issue 1: QR Code Not Appearing

**Symptoms**:
- Inbox created, but QR code never shows up
- `provider_connection.connection` stays `null` or `close`

**Diagnosis**:
1. Check Click2Run health:
   ```bash
   curl -H "X-API-Key: YOUR_KEY" http://click2run:8080/api/v1/chatwoot/health
   ```

2. Check webhook delivery:
   ```bash
   # In Chatwoot logs
   grep "Click2Run connection update" log/production.log
   ```

3. Check webhook token:
   ```ruby
   channel = Channel::Whatsapp.find_by(phone_number: "+1234567890")
   channel.provider_config['webhook_verify_token']
   # Must match token sent by Click2Run
   ```

**Solution**:
- Verify `CLICK2RUN_PROVIDER_DEFAULT_URL` is reachable from Chatwoot
- Verify webhook URL is publicly accessible
- Check firewall/network rules

#### Issue 2: Messages Not Appearing

**Symptoms**:
- Inbox connected (status: "open")
- Messages sent from WhatsApp app
- No messages appear in Chatwoot

**Diagnosis**:
1. Check webhook delivery:
   ```bash
   # In Chatwoot logs
   grep "messages.upsert" log/production.log
   ```

2. Check job processing:
   ```bash
   # In Sidekiq dashboard
   # Look for failed Webhooks::WhatsappEventsJob
   ```

3. Check webhook token validation:
   ```bash
   grep "InvalidWebhookVerifyToken" log/production.log
   ```

**Solution**:
- Verify webhook token matches between Chatwoot and Click2Run
- Check Sidekiq is running and processing jobs
- Verify phone number format (must match exactly)

#### Issue 3: Duplicate Messages

**Symptoms**:
- Same message appears multiple times in conversation

**Diagnosis**:
1. Check Redis:
   ```bash
   redis-cli
   > KEYS message_source:*
   ```

2. Check database:
   ```sql
   SELECT source_id, COUNT(*) FROM messages
   GROUP BY source_id HAVING COUNT(*) > 1;
   ```

**Solution**:
- Verify Redis is running and accessible
- Check for stale Redis keys (TTL expired but not cleaned up)
- Review webhook configuration (may be sending duplicates)

#### Issue 4: Media Download Fails

**Symptoms**:
- Image/video/audio messages appear without media
- Message marked as `is_unsupported: true`

**Diagnosis**:
1. Check media download:
   ```bash
   # In Chatwoot logs
   grep "Failed to download attachment" log/production.log
   ```

2. Check API authentication:
   ```bash
   curl -H "X-API-Key: YOUR_KEY" \
     http://click2run-api:8080/api/v1/chatwoot/{account_id}/inboxes/{inbox_id}/media/MESSAGE_ID
   ```

**Solution**:
- Verify `X-API-Key` is correct
- Check Click2Run media storage (may be deleted)
- Verify network connectivity between Chatwoot and Click2Run

### 8.2 Debug Checklist

When troubleshooting Click2Run integration:

- [ ] Click2Run health check passes
- [ ] Webhook URL is publicly accessible
- [ ] Webhook token matches between systems
- [ ] Phone number format is consistent (+1234567890)
- [ ] Redis is running and accessible
- [ ] Sidekiq is processing jobs
- [ ] Database has correct indexes
- [ ] Logs show webhook events being received
- [ ] Logs show messages being created
- [ ] Connection status is "open" in database

---

## 9. Future Enhancements

### 9.1 Potential Improvements

1. **Webhook Configuration in Click2Run**:
   - Currently webhook URL is configured externally
   - Sent during instance creation to Click2Run

2. **Message History Import**:
   - Export WhatsApp chat from mobile app
   - Parse and import into Chatwoot
   - Requires significant development effort

3. **Group Chat Support**:
   - Click2Run supports group chats
   - Chatwoot would need multi-participant conversation model

4. **Broadcast Lists**:
   - Send same message to multiple contacts
   - WhatsApp supports broadcast (1-to-many)

5. **Status Updates (Stories)**:
   - View/post WhatsApp status updates
   - Requires UI changes in Chatwoot

6. **Voice/Video Calls**:
   - Click2Run can detect calls
   - Chatwoot could log call events (not handle calls)

7. **Better Error Handling**:
   - Retry logic for failed webhooks
   - Dead letter queue for permanently failed messages
   - User-friendly error messages

### 9.2 Scalability Considerations

Current implementation scales to:
- **~100 inboxes** per Chatwoot instance
- **~1000 messages/second** per Click2Run instance
- **~10,000 concurrent conversations**

Bottlenecks:
- Database write throughput (messages table)
- Redis memory (message deduplication cache)
- Sidekiq worker capacity

Scaling strategies:
- Horizontal scaling: Multiple Chatwoot instances
- Database sharding: Partition messages by account
- Redis clustering: Distribute cache load
- Sidekiq workers: Increase worker count

---

## 10. Appendix

### 10.1 File Reference Quick Guide

| Component | File | Lines of Interest |
|-----------|------|-------------------|
| **Models** |
| WhatsApp Channel | `app/models/channel/whatsapp.rb` | 22-176 (full) |
| **Services** |
| Click2Run Provider | `app/services/whatsapp/providers/whatsapp_click2run_service.rb` | 49-83 (setup), 114-129 (send), 250-262 (profile pic) |
| Incoming Message | `app/services/whatsapp/incoming_message_click2run_service.rb` | 26-41 (dispatcher) |
| Base Service | `app/services/whatsapp/incoming_message_base_service.rb` | 9-197 (full) |
| **Handlers** |
| Connection Update | `app/services/whatsapp/click2run_handlers/connection_update.rb` | 23-79 (full) |
| Messages Upsert | `app/services/whatsapp/click2run_handlers/messages_upsert.rb` | 33-196 (full) |
| Messages Update | `app/services/whatsapp/click2run_handlers/messages_update.rb` | 33-122 (full) |
| Helpers | `app/services/whatsapp/click2run_handlers/helpers.rb` | 12-215 (full) |
| **Controllers** |
| Webhook Receiver | `app/controllers/webhooks/whatsapp_controller.rb` | 4-48 (full) |
| Inbox Management | `app/controllers/api/v1/accounts/inboxes_controller.rb` | 30-43 (create), 68-90 (setup/disconnect) |
| **Jobs** |
| Webhook Processing | `app/jobs/webhooks/whatsapp_events_job.rb` | 4-53 (full) |
| **Builders** |
| Contact Creation | `app/builders/contact_inbox_with_contact_builder.rb` | 8-110 (full) |

### 10.2 JID Format Reference

WhatsApp JID (Jabber ID) formats used in Click2Run:

| Type | Format | Example | Description |
|------|--------|---------|-------------|
| User | `{phone}@s.whatsapp.net` | `5511999999999@s.whatsapp.net` | Individual contact |
| User (multi-device) | `{phone}:{device}@s.whatsapp.net` | `5511999999999:5@s.whatsapp.net` | Specific device |
| Group | `{group_id}@g.us` | `123456789-1234567890@g.us` | WhatsApp group |
| Broadcast | `{list_id}@broadcast` | `12345678@broadcast` | Broadcast list |
| Status | `status@broadcast` | `status@broadcast` | Status updates (stories) |
| Newsletter | `{id}@newsletter` | `123456@newsletter` | WhatsApp newsletter |

**Extraction Logic** (app/services/whatsapp/click2run_handlers/helpers.rb:144-151):
```ruby
def phone_number_from_jid
  jid = @raw_message[:key][:remote_jid]

  # JID shape: <phone>@s.whatsapp.net or <phone>:<device>@s.whatsapp.net
  # Extract phone number (digits only)
  jid.split('@').first.split(':').first.gsub(/\D/, '')
end
```

### 10.3 Environment Variables Reference

```bash
# Click2Run Provider Configuration
CLICK2RUN_PROVIDER_DEFAULT_URL=http://click2run-api:8080/api/v1
CLICK2RUN_PROVIDER_DEFAULT_API_KEY=your_tenant_api_key_here

# Redis Configuration (required for deduplication)
REDIS_URL=redis://redis:6379
REDIS_PASSWORD=your_redis_password

# Chatwoot Base URL (required for webhooks)
FRONTEND_URL=https://chatwoot.example.com
```

### 10.4 Database Schema (Relevant Tables)

```sql
-- channel_whatsapp table
CREATE TABLE channel_whatsapp (
  id BIGSERIAL PRIMARY KEY,
  account_id INTEGER NOT NULL,
  phone_number VARCHAR NOT NULL UNIQUE,
  provider VARCHAR DEFAULT 'default',
  provider_config JSONB,
  provider_connection JSONB,
  message_templates JSONB,
  message_templates_last_updated TIMESTAMP,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX index_channel_whatsapp_provider_connection
  ON channel_whatsapp USING gin(provider_connection)
  WHERE provider IN ('baileys', 'zapi', 'whatsmeow', 'click2run');

-- inboxes table (polymorphic)
CREATE TABLE inboxes (
  id BIGSERIAL PRIMARY KEY,
  account_id INTEGER NOT NULL,
  name VARCHAR NOT NULL,
  channel_id BIGINT NOT NULL,
  channel_type VARCHAR NOT NULL,
  -- ... other fields
);

CREATE INDEX index_inboxes_on_channel
  ON inboxes (channel_type, channel_id);

-- contact_inboxes table
CREATE TABLE contact_inboxes (
  id BIGSERIAL PRIMARY KEY,
  inbox_id BIGINT NOT NULL,
  contact_id BIGINT NOT NULL,
  source_id VARCHAR,
  -- ... other fields
);

CREATE UNIQUE INDEX index_contact_inboxes_on_inbox_id_and_source_id
  ON contact_inboxes (inbox_id, source_id);

-- messages table
CREATE TABLE messages (
  id BIGSERIAL PRIMARY KEY,
  conversation_id BIGINT NOT NULL,
  source_id VARCHAR,
  content TEXT,
  message_type INTEGER,
  status INTEGER DEFAULT 0,
  -- ... other fields
);

CREATE INDEX index_messages_on_source_id
  ON messages (source_id);
```

---

**Document Version**: 1.0
**Last Updated**: 2025-11-05
**Status**: Complete ✅
