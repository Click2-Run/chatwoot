---
Created: 2025-11-04T00:00:00Z
Operation: Complete Baileys file index with line references
Context: Navigate to specific implementations quickly
---

# Baileys Implementation - Complete File Index

## All Files Containing Baileys References

### 1. DATABASE LAYER (3 files)

#### Migrations
| File | Lines | Purpose |
|------|-------|---------|
| `db/migrate/20250314185939_add_provider_connection_to_whatsapp.rb` | 1-5 | Adds provider_connection JSONB column |
| `db/migrate/20250726142410_add_whatsapp_channel_provider_index.rb` | 1-9 | Creates GIN index for Baileys provider_connection |
| `db/migrate/20250928173414_recreate_whatsapp_channel_provider_connection_index.rb` | 1-10 | Recreates index for baileys, zapi, whatsmeow |

#### Schema
| File | Lines | Purpose |
|------|-------|---------|
| `db/schema.rb` | 19 | Index definition with Baileys condition |

---

### 2. MODELS (1 file)

#### Channel Definition
| File | Lines | Purpose |
|------|-------|---------|
| `app/models/channel/whatsapp.rb` | - | Main WhatsApp channel model |
| | 30 | PROVIDERS enum includes 'baileys' |
| | 48-61 | provider_service factory method |
| | 63-66 | use_internal_host? method for Baileys |
| | 80-87 | provider_connection_data method |
| | 89-116 | Baileys-specific methods (unread, toggle_typing, etc) |
| | 137-142 | setup_webhooks method |
| | 154 | ensure_webhook_verify_token for Baileys |

---

### 3. SERVICES - PROVIDERS (6 files)

#### Main Provider Service
| File | Lines | Purpose |
|------|-------|---------|
| `app/services/whatsapp/providers/base_service.rb` | 1-100+ | Base class for all providers |
| `app/services/whatsapp/providers/whatsapp_baileys_service.rb` | - | Complete Baileys implementation |
| | 1-10 | Class definition and imports |
| | 7-9 | Configuration constants (DEFAULT_URL, API_KEY, CLIENT_NAME) |
| | 11-27 | self.status class method |
| | 29-45 | setup_channel_provider method |
| | 47-56 | disconnect_channel_provider method |
| | 58-74 | send_message method |
| | 76-78 | send_template and sync_templates stubs |
| | 80-82 | media_url method |
| | 84-86 | api_headers method |
| | 88-95 | validate_provider_config? method |
| | 97-117 | toggle_typing_status method |
| | 119-137 | update_presence method |
| | 139-159 | read_messages method |
| | 161-186 | unread_message method |
| | 188-208 | received_messages method |
| | 210-221 | get_profile_pic method |
| | 223-237 | on_whatsapp method |
| | 241-310 | Private helper methods |
| | 319-360 | Error handling setup |

#### Other Providers
| File | Purpose |
|------|---------|
| `app/services/whatsapp/providers/whatsapp_cloud_service.rb` | Cloud API provider |
| `app/services/whatsapp/providers/whatsapp_360_dialog_service.rb` | 360Dialog provider |
| `app/services/whatsapp/providers/whatsapp_zapi_service.rb` | Zapi provider |
| `app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb` | Whatsmeow provider |

---

### 4. SERVICES - INCOMING MESSAGES (5 files)

#### Main Incoming Service
| File | Lines | Purpose |
|------|-------|---------|
| `app/services/whatsapp/incoming_message_baileys_service.rb` | - | Webhook event dispatcher |
| | 1-5 | Imports and module includes |
| | 9-24 | perform method - event routing |

#### Handler Modules
| File | Lines | Purpose |
|------|-------|---------|
| `app/services/whatsapp/baileys_handlers/helpers.rb` | - | Message parsing utilities |
| | 6-8 | raw_message_id extraction |
| | 10-12 | sender_lid extraction |
| | 14-16 | incoming? predicate |
| | 18-40 | jid_type parsing |
| | 42-70 | message_type detection |
| | 72-96 | message_content extraction |
| | 98-104 | file_content_type mapping |
| | 106-120 | message_mimetype extraction |
| | 122-130 | phone_number_from_jid parsing |
| | 132-138 | contact_name extraction |
| | 140-143 | self_message? check |
| | 145-148 | ignore_message? filter |
| | 150-157 | fetch_profile_picture_url |
| | 159-165 | try_update_contact_avatar |
| | 167-170 | message_under_process? check |
| | 172-175 | cache_message_source_id_in_redis |
| | 177-180 | clear_message_source_id_from_redis |

| File | Lines | Purpose |
|------|-------|---------|
| `app/services/whatsapp/baileys_handlers/connection_update.rb` | - | Connection state handler |
| | 6-21 | process_connection_update method |

| File | Lines | Purpose |
|------|-------|---------|
| `app/services/whatsapp/baileys_handlers/messages_upsert.rb` | - | Message creation handler |
| | 7-21 | process_messages_upsert method |
| | 23-42 | handle_message method |
| | 44-67 | set_contact and update_contact_information |
| | 69-91 | handle_create_message and create_message |
| | 92-104 | message_content_attributes |
| | 105-131 | handle_attach_media and download_attachment_file |

| File | Lines | Purpose |
|------|-------|---------|
| `app/services/whatsapp/baileys_handlers/messages_update.rb` | - | Message status handler |
| | 8-20 | process_messages_update method |
| | 22-27 | handle_update method |
| | 29-33 | update_status method |
| | 35-61 | status_mapper method |
| | 63-69 | update_last_seen_at method |
| | 71-76 | status_transition_allowed? check |
| | 78-85 | handle_edited_content method |

---

### 5. SERVICES - SENDING (2 files)

| File | Lines | Purpose |
|------|-------|---------|
| `app/services/whatsapp/send_on_whatsapp_service.rb` | - | Message sending orchestrator |
| | 14-18 | perform_reply - Baileys-specific routing |
| | 44-46 | send_baileys_session_message with lock |
| | 54-61 | recipient_id for Baileys |
| `app/services/whatsapp/incoming_message_base_service.rb` | - | Base service for all incoming handlers |

---

### 6. HELPERS (1 file)

| File | Lines | Purpose |
|------|-------|---------|
| `app/helpers/baileys_helper.rb` | - | Baileys utility methods |
| | 2-3 | CHANNEL_LOCK constants |
| | 5-15 | baileys_extract_message_timestamp |
| | 17-32 | with_baileys_channel_lock_on_outgoing_message |
| | 36-39 | baileys_lock_channel_on_outgoing_message |
| | 41-44 | baileys_clear_channel_lock_on_outgoing_message |

---

### 7. CONTROLLERS & JOBS (4 files)

#### Webhook Entry Point
| File | Lines | Purpose |
|------|-------|---------|
| `app/controllers/webhooks/whatsapp_controller.rb` | - | Webhook receiver |
| | 4-22 | process_payload method |
| | 32-36 | valid_token? method |
| | 38-47 | inactive_whatsapp_number? check |

#### Async Processing
| File | Lines | Purpose |
|------|-------|---------|
| `app/jobs/webhooks/whatsapp_events_job.rb` | - | Provider router |
| | 11-18 | perform method - Baileys routing at line 14-15 |
| | 27-32 | find_channel method |
| | 35-40 | channel_is_inactive? check |

#### Background Health Check
| File | Lines | Purpose |
|------|-------|---------|
| `app/jobs/channels/whatsapp/baileys_connection_check_scheduler_job.rb` | - | Scheduler |
| | 4-10 | perform method |
| `app/jobs/channels/whatsapp/baileys_connection_check_job.rb` | - | Health check executor |
| | 4-6 | perform method |

---

### 8. FRONTEND - VUE COMPONENTS (2 files)

#### Provider Selection
| File | Lines | Purpose |
|------|-------|---------|
| `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` | - | Provider picker |
| | 29 | PROVIDER_TYPES.BAILEYS = 'baileys' |
| | 62-66 | Baileys provider option in availableProviders |
| | 95-99 | shouldShowCloudWhatsapp includes Baileys check |

#### Baileys Configuration
| File | Lines | Purpose |
|------|-------|---------|
| `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/BaileysWhatsapp.vue` | - | Setup form |
| | 23-28 | Form input refs |
| | 32-40 | Validation rules |
| | 49-85 | createChannel method |
| | 100-213 | Template with form fields |

---

### 9. INTERNATIONALIZATION (2 files)

| File | Lines | Purpose |
|------|-------|---------|
| `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` | - | English translations |
| | 233 | BAILEYS provider name |
| | 234 | BAILEYS_DESC description |
| | 286-290 | PROVIDER_URL fields |
| | 274-279 | API_KEY fields |
| | 291-293 | MARK_AS_READ toggle |

| File | Lines | Purpose |
|------|-------|---------|
| `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` | - | Portuguese (Brazil) translations |

---

### 10. CONFIGURATION (1 file)

| File | Lines | Purpose |
|------|-------|---------|
| `.env.example` | - | Environment example |
| | 270-273 | BAILEYS_PROVIDER_* variables |

---

### 11. DOCKER (1 file)

| File | Lines | Purpose |
|------|-------|---------|
| `docker-compose.coolify.yaml` | - | Docker compose config |

---

### 12. TEST FILES (7 files)

#### Service Tests
| File | Purpose |
|------|---------|
| `spec/services/whatsapp/providers/whatsapp_baileys_service_spec.rb` | Provider service tests |
| `spec/services/whatsapp/incoming_message_baileys_service_spec.rb` | Incoming message handler tests |

#### Helper Tests
| File | Purpose |
|------|---------|
| `spec/helpers/baileys_helper_spec.rb` | Helper utility tests |

#### Job Tests
| File | Purpose |
|------|---------|
| `spec/jobs/channels/whatsapp/baileys_connection_check_job_spec.rb` | Connection check job tests |
| `spec/jobs/channels/whatsapp/baileys_connection_check_scheduler_job_spec.rb` | Scheduler job tests |

#### Integration Tests
| File | Purpose |
|------|---------|
| `spec/models/channel/whatsapp_spec.rb` | Model tests |
| `spec/controllers/webhooks/whatsapp_controller_spec.rb` | Webhook controller tests |

---

### 13. DOCUMENTATION (2 files - LLM analysis)

| File | Purpose |
|------|---------|
| `.llm/analysis/20251104_BAILEYS_COMPREHENSIVE_INTEGRATION_ANALYSIS.md` | Complete 1000+ line analysis |
| `.llm/analysis/20251104_BAILEYS_QUICK_REFERENCE.md` | Quick reference guide |

---

## File Count Summary

| Category | Count |
|----------|-------|
| Database/Migrations | 4 |
| Models | 1 |
| Provider Services | 6 |
| Incoming Message Services | 5 |
| Sending Services | 2 |
| Helpers | 1 |
| Controllers/Jobs | 4 |
| Frontend Components | 2 |
| Internationalization | 2 |
| Configuration | 1 |
| Docker | 1 |
| Tests | 7 |
| Documentation | 2 |
| **TOTAL** | **38 files** |

---

## Quick Access by Task

### "I need to add a new Baileys endpoint"
- File: `app/services/whatsapp/providers/whatsapp_baileys_service.rb`
- Follow pattern: `Lines 30-45` (setup_channel_provider)

### "Messages not being received"
- File: `app/services/whatsapp/incoming_message_baileys_service.rb`
- File: `app/services/whatsapp/baileys_handlers/messages_upsert.rb` (Lines 7-21)
- Check: phone_number_from_jid (helpers.rb Lines 122-130)

### "Webhook verification failing"
- File: `app/controllers/webhooks/whatsapp_controller.rb` (Lines 32-36)
- Check: provider_config['webhook_verify_token'] (model.rb Line 154)

### "Fix status mapping"
- File: `app/services/whatsapp/baileys_handlers/messages_update.rb` (Lines 35-61)
- Reference: Baileys status codes 0-5

### "Connection stuck on QR code"
- File: `app/services/whatsapp/baileys_handlers/connection_update.rb` (Lines 6-21)
- Check: connection states and error messages

### "Add Baileys feature to frontend"
- Files:
  - Provider selection: `channels/Whatsapp.vue` (Lines 29, 62-66)
  - Configuration form: `channels/BaileysWhatsapp.vue`
  - Translations: `inboxMgmt.json` (Lines 233-234, 286-293)

### "Understand message flow"
- Incoming: helpers.rb → messages_upsert.rb (lines 23-42)
- Outgoing: send_on_whatsapp_service.rb (lines 44-46)
- Status: messages_update.rb (lines 22-27)

---

## Absolute File Paths

All paths relative to `/root/data/development/chatwoot.git/`:

```
DATABASE
  db/migrate/20250314185939_add_provider_connection_to_whatsapp.rb
  db/migrate/20250726142410_add_whatsapp_channel_provider_index.rb
  db/migrate/20250928173414_recreate_whatsapp_channel_provider_connection_index.rb
  db/schema.rb

MODELS
  app/models/channel/whatsapp.rb

PROVIDERS
  app/services/whatsapp/providers/base_service.rb
  app/services/whatsapp/providers/whatsapp_baileys_service.rb
  app/services/whatsapp/providers/whatsapp_cloud_service.rb
  app/services/whatsapp/providers/whatsapp_360_dialog_service.rb
  app/services/whatsapp/providers/whatsapp_zapi_service.rb
  app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb

INCOMING
  app/services/whatsapp/incoming_message_baileys_service.rb
  app/services/whatsapp/incoming_message_base_service.rb
  app/services/whatsapp/baileys_handlers/helpers.rb
  app/services/whatsapp/baileys_handlers/connection_update.rb
  app/services/whatsapp/baileys_handlers/messages_upsert.rb
  app/services/whatsapp/baileys_handlers/messages_update.rb

SENDING
  app/services/whatsapp/send_on_whatsapp_service.rb

HELPERS
  app/helpers/baileys_helper.rb

WEBHOOKS & JOBS
  app/controllers/webhooks/whatsapp_controller.rb
  app/jobs/webhooks/whatsapp_events_job.rb
  app/jobs/channels/whatsapp/baileys_connection_check_scheduler_job.rb
  app/jobs/channels/whatsapp/baileys_connection_check_job.rb

FRONTEND
  app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue
  app/javascript/dashboard/routes/dashboard/settings/inbox/channels/BaileysWhatsapp.vue
  app/javascript/dashboard/i18n/locale/en/inboxMgmt.json
  app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json

CONFIGURATION
  .env.example

DOCKER
  docker-compose.coolify.yaml

TESTS
  spec/services/whatsapp/providers/whatsapp_baileys_service_spec.rb
  spec/services/whatsapp/incoming_message_baileys_service_spec.rb
  spec/helpers/baileys_helper_spec.rb
  spec/jobs/channels/whatsapp/baileys_connection_check_job_spec.rb
  spec/jobs/channels/whatsapp/baileys_connection_check_scheduler_job_spec.rb
  spec/models/channel/whatsapp_spec.rb
  spec/controllers/webhooks/whatsapp_controller_spec.rb
```

