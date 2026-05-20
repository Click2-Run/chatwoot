---
Created: 2025-11-04T00:00:00Z
Operation: Baileys quick reference guide
Context: Fast lookup for key Baileys integration files and patterns
---

# Baileys Integration - Quick Reference

## Critical Files

### Database
- `/root/data/development/chatwoot.git/db/migrate/20250314185939_add_provider_connection_to_whatsapp.rb` - Connection state column
- `/root/data/development/chatwoot.git/db/migrate/20250726142410_add_whatsapp_channel_provider_index.rb` - GIN index for queries

### Core Services (6 files)
1. `/root/data/development/chatwoot.git/app/models/channel/whatsapp.rb` (176 lines)
   - Provider factory method (line 48-61)
   - Provider connection data (line 80-87)
   - Baileys-specific methods (line 89-116)

2. `/root/data/development/chatwoot.git/app/services/whatsapp/providers/whatsapp_baileys_service.rb` (361 lines)
   - Configuration: DEFAULT_URL, DEFAULT_API_KEY, DEFAULT_CLIENT_NAME (lines 7-9)
   - Status check (lines 11-27)
   - Setup/disconnect (lines 29-56)
   - Send message (lines 58-74)
   - Presence/typing (lines 97-137)
   - Error handling (lines 319-360)

3. `/root/data/development/chatwoot.git/app/services/whatsapp/incoming_message_baileys_service.rb` (26 lines)
   - Webhook dispatcher
   - Routes to handlers

4. `/root/data/development/chatwoot.git/app/helpers/baileys_helper.rb` (46 lines)
   - Timestamp parsing (lines 5-15)
   - Channel locking (lines 17-32)

5. `/root/data/development/chatwoot.git/app/services/whatsapp/send_on_whatsapp_service.rb` (68 lines)
   - Baileys-specific send wrapper (lines 44-46)

### Message Handlers (4 files in `/app/services/whatsapp/baileys_handlers/`)
1. `connection_update.rb` - Handle connection state changes
2. `messages_upsert.rb` - Create incoming/outgoing messages
3. `messages_update.rb` - Update message status
4. `helpers.rb` - JID parsing, message type detection, contact info

### Webhook & Jobs
- `/root/data/development/chatwoot.git/app/controllers/webhooks/whatsapp_controller.rb` - Webhook entry point
- `/root/data/development/chatwoot.git/app/jobs/webhooks/whatsapp_events_job.rb` - Provider router
- `/root/data/development/chatwoot.git/app/jobs/channels/whatsapp/baileys_connection_check_scheduler_job.rb` - Health check scheduler
- `/root/data/development/chatwoot.git/app/jobs/channels/whatsapp/baileys_connection_check_job.rb` - Health check executor

### Frontend (3 files)
1. `/root/data/development/chatwoot.git/app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` - Provider selection
2. `/root/data/development/chatwoot.git/app/javascript/dashboard/routes/dashboard/settings/inbox/channels/BaileysWhatsapp.vue` - Baileys form
3. `/root/data/development/chatwoot.git/app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` - Translations (line 233-234)

---

## Key Code Patterns

### Provider Service Factory
```ruby
# File: app/models/channel/whatsapp.rb (lines 48-61)
def provider_service
  case provider
  when 'baileys'
    Whatsapp::Providers::WhatsappBaileysService.new(whatsapp_channel: self)
  end
end
```

### Webhook Token Generation
```ruby
# File: app/models/channel/whatsapp.rb (line 154)
provider_config['webhook_verify_token'] ||= SecureRandom.hex(16)
```

### Message Locking
```ruby
# File: app/helpers/baileys_helper.rb (lines 17-32)
with_baileys_channel_lock_on_outgoing_message(channel_id, timeout: 15.seconds) do
  # Critical section
end
```

### JID Parsing
```ruby
# File: app/services/whatsapp/baileys_handlers/helpers.rb (lines 122-130)
def phone_number_from_jid
  jid = @raw_message[:key][:remoteJid] # or :senderPn for LID
  jid.split('@').first.split(':').first.split('_').first
end
```

### Status Mapping
```ruby
# File: app/services/whatsapp/baileys_handlers/messages_update.rb (lines 35-60)
case status
when 0 then 'failed'
when 1, 2 then 'sent'
when 3 then 'delivered'
when 4 then 'read'
when 5 then nil # PLAYED (unsupported)
end
```

---

## Environment Variables

```bash
# Required for Baileys provider
BAILEYS_PROVIDER_DEFAULT_URL=http://localhost:3025
BAILEYS_PROVIDER_DEFAULT_API_KEY=your-api-key

# Optional
BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME=Chatwoot
BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL=false
```

---

## Database Schema

### channel_whatsapp table
- `provider` - value: 'baileys'
- `provider_config` JSONB:
  - `webhook_verify_token` - auto-generated
  - `provider_url` - optional override
  - `api_key` - optional override
  - `mark_as_read` - boolean
- `provider_connection` JSONB:
  - `connection` - 'open'|'close'|'connecting'|'reconnecting'
  - `qr_data_url` - QR code data URL
  - `error` - error message if failed

---

## API Endpoints

### Called by Baileys Service
```
POST /connections/{phone}              - Setup
DELETE /connections/{phone}            - Disconnect
POST /connections/{phone}/send-message - Send message
POST /connections/{phone}/read-messages - Mark read
PATCH /connections/{phone}/presence    - Typing status
GET /connections/{phone}/profile-picture-url - Profile pic
POST /connections/{phone}/on-whatsapp  - Check number exists
GET /status                            - Health check
GET /status/auth                       - Auth check
```

### Webhook to Chatwoot
```
POST /api/v1/webhooks/whatsapp?phone_number={phone}&webhookVerifyToken={token}

Events: messages.upsert, messages.update, connection.update
```

---

## Message Flow Summary

### Incoming Message (Webhook)
WhatsApp → Baileys Provider → POST webhook → WhatsappController → WhatsappEventsJob → IncomingMessageBaileysService → MessagesUpsert Handler → Creates Message + Contact

### Outgoing Message
Agent Message → SendOnWhatsappService → (with lock) → BaileysService.send_message → POST /send-message → Updates source_id

### Status Update
Baileys webhook → MessagesUpdate Handler → Maps status (0-4) → Updates Message.status

### Connection
QR Code → connection.update event → Updates provider_connection.qr_data_url → Frontend displays → User scans → connection.open event → Ready

---

## Test Files Location

```
spec/services/whatsapp/providers/whatsapp_baileys_service_spec.rb
spec/services/whatsapp/incoming_message_baileys_service_spec.rb
spec/helpers/baileys_helper_spec.rb
spec/jobs/channels/whatsapp/baileys_connection_check_job_spec.rb
spec/jobs/channels/whatsapp/baileys_connection_check_scheduler_job_spec.rb
```

---

## Common Issues & Solutions

### Invalid Webhook Token
- Check token in provider_config matches webhook parameter
- Token is auto-generated (SecureRandom.hex(16))
- Stored in channel.provider_config['webhook_verify_token']

### Connection Status Stuck
- Check BAILEYS_PROVIDER_DEFAULT_URL is accessible
- Check BAILEYS_PROVIDER_DEFAULT_API_KEY is valid
- Connection health checked via background job scheduler

### Message Not Received
- Verify incoming? method returns correct value (checks [:key][:fromMe])
- Check JID parsing logic for phone number extraction
- Message cached in Redis to prevent duplicates

### Missing Phone Number
- LID format requires :senderPn instead of :remoteJid
- Fallback to :remoteJid if LID not available
- Normalization handles various formats

---

## Baileys-Specific Features

1. **Typing Status**: composing, recording, paused states
2. **Unread Messages**: Can mark messages as unread via chat-modify
3. **Read Receipts**: Configurable via mark_as_read in provider_config
4. **Profile Pictures**: Fetched on incoming message, enqueued to Avatar job
5. **Reactions**: Stored with is_reaction flag and in_reply_to_external_id
6. **Edits**: Tracked via editedMessage, updates original with is_edited flag
7. **Duplex Lock**: Prevents race between incoming webhook and outgoing send (15s timeout)
8. **Timestamp Formats**: Handles {low, high, unsigned} or numeric Unix timestamp

---

## Provider Comparison

| Feature | Baileys | WhatsApp Cloud | Twilio | 360Dialog | Zapi | Whatsmeow |
|---------|---------|---|---|---|---|---|
| Authentication | QR Code | OAuth | Credentials | API Key | API Key | QR Code |
| Non-official | Yes | No | No | No | Yes | No |
| Typing Status | Yes | Yes | No | No | No | Yes |
| Read Status | Yes | Yes | No | No | No | Yes |
| Unread Messages | Yes | No | No | No | No | Yes |
| Profile Pictures | Yes | Yes | No | No | No | Yes |
| Reactions | Yes | Yes | No | No | No | Yes |
| Message Edits | Yes | No | No | No | No | Yes |

