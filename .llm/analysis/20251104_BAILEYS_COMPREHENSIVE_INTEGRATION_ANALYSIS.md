---
Created: 2025-11-04T00:00:00Z
Operation: Comprehensive Baileys implementation analysis
Context: Document all Baileys integration points across database, backend, frontend, and business logic layers
Related Files: All Baileys-related implementations in chatwoot.git
---

# Comprehensive Baileys Integration Analysis

## Executive Summary

Baileys is a non-official WhatsApp Web API provider integrated into Chatwoot. It allows users to connect WhatsApp channels without official Meta credentials by using a device-linking mechanism (QR code). The implementation spans across database schema, backend services, background jobs, webhook handlers, and frontend components.

**Provider Type**: Non-official WhatsApp Web API
**Authentication**: Device-based (QR code linking)
**Architecture**: External microservice model with webhook callbacks
**Status**: Fully implemented with connection management and comprehensive message handling

---

## 1. DATABASE LAYER

### 1.1 Schema

**File**: `/root/data/development/chatwoot.git/db/schema.rb`

The `channel_whatsapp` table includes:

```ruby
# Key columns:
id                             :bigint           # Primary key
phone_number                   :string           # Unique phone number (UNIQUE index)
provider                       :string           default("default") # 'baileys' value
provider_config                :jsonb            # Provider-specific configuration
provider_connection            :jsonb            # Connection status and QR data
message_templates              :jsonb
message_templates_last_updated :datetime
account_id                     :integer          # Foreign key to accounts
created_at                     :datetime
updated_at                     :datetime
```

### 1.2 Indexes

**File**: `/root/data/development/chatwoot.git/db/migrate/20250726142410_add_whatsapp_channel_provider_index.rb`

```ruby
# GIN index for JSON queries on provider_connection
add_index :channel_whatsapp, :provider_connection,
          using: :gin,
          where: "provider = 'baileys'",
          name: 'index_channel_whatsapp_provider_connection'
```

This optimizes queries filtering by `provider_connection` values for Baileys channels.

### 1.3 Migrations

#### Migration 1: Provider Connection Column
**File**: `/root/data/development/chatwoot.git/db/migrate/20250314185939_add_provider_connection_to_whatsapp.rb`

```ruby
class AddProviderConnectionToWhatsapp < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_whatsapp, :provider_connection, :jsonb, default: {}
  end
end
```

**Purpose**: Stores connection state and QR code data for device-based auth flow.

#### Migration 2: Baileys-specific Index
**File**: `/root/data/development/chatwoot.git/db/migrate/20250928173414_recreate_whatsapp_channel_provider_connection_index.rb`

Recreates index with support for both `baileys`, `zapi`, and `whatsmeow` providers:

```ruby
where: "(provider)::text = ANY ((ARRAY['baileys'::character varying, 'zapi'::character varying, 'whatsmeow'::character varying])::text[])"
```

### 1.4 Provider Configuration Storage

**Structure** in `provider_config` JSONB:

```ruby
{
  "webhook_verify_token" => "secure_random_hex(16)",  # Auto-generated
  "provider_url" => "http://localhost:3025",           # Optional override
  "api_key" => "baileys_api_key",                      # Optional override
  "mark_as_read" => true                               # Read receipt setting
}
```

**Structure** in `provider_connection` JSONB:

```ruby
{
  "connection" => "open|close|connecting|reconnecting", # Connection state
  "qr_data_url" => "data:image/png;base64,...",        # QR code image
  "error" => "User cancelled login"                     # Error message if present
}
```

### 1.5 PROVIDERS Enum

**File**: `/root/data/development/chatwoot.git/app/models/channel/whatsapp.rb` Line 30

```ruby
PROVIDERS = %w[default whatsapp_cloud baileys zapi whatsmeow].freeze
```

---

## 2. BACKEND LAYER

### 2.1 Model Definition

**File**: `/root/data/development/chatwoot.git/app/models/channel/whatsapp.rb`

#### Key Methods

```ruby
# Line 48-61: Provider service factory
def provider_service
  case provider
  when 'baileys'
    Whatsapp::Providers::WhatsappBaileysService.new(whatsapp_channel: self)
  # ... other providers
  end
end

# Line 63-66: Webhook URL configuration
def use_internal_host?
  (provider == 'baileys' && ENV.fetch('BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL', false)) ||
    (provider == 'whatsmeow' && ENV.fetch('WHATSMEOW_PROVIDER_USE_INTERNAL_HOST_URL', false))
end

# Line 80-87: Provider connection data exposure
def provider_connection_data
  data = { connection: provider_connection['connection'] }
  if Current.account_user&.administrator?
    data[:qr_data_url] = provider_connection['qr_data_url']
    data[:error] = provider_connection['error']
  end
  data
end

# Line 89-108: Multi-provider method delegation
delegate :setup_channel_provider, to: :provider_service
delegate :send_message, to: :provider_service
delegate :send_template, to: :provider_service
delegate :sync_templates, to: :provider_service
delegate :media_url, to: :provider_service
delegate :api_headers, to: :provider_service
```

#### Baileys-specific Methods

```ruby
# Line 113-116: Mark messages as unread (Baileys support)
def unread_conversation(conversation)
  return unless provider_service.respond_to?(:unread_message)
  last_message = conversation.messages.last
  provider_service.unread_message(conversation.contact.phone_number, last_message) if last_message
end

# Line 137-142: Webhook setup for Baileys
def setup_webhooks
  perform_webhook_setup
rescue StandardError => e
  Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
  prompt_reauthorization!
end

# Line 154: Auto-generate webhook verify token for Baileys
def ensure_webhook_verify_token
  provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if provider.in?(%w[whatsapp_cloud baileys])
end

# Line 74-78: Safe provider connection updates
def update_provider_connection!(provider_connection)
  assign_attributes(provider_connection: provider_connection)
  save!(validate: false)
end

# Line 118-123: Graceful disconnect on destroy
def disconnect_channel_provider
  provider_service.disconnect_channel_provider
rescue StandardError => e
  Rails.logger.error "Failed to disconnect channel provider: #{e.message}"
end
```

### 2.2 Provider Service

**File**: `/root/data/development/chatwoot.git/app/services/whatsapp/providers/whatsapp_baileys_service.rb`

#### Configuration

```ruby
DEFAULT_CLIENT_NAME = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME', nil)
DEFAULT_URL = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_URL', nil)
DEFAULT_API_KEY = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_API_KEY', nil)

include BaileysHelper
```

#### Class Methods

**Status Check** (Line 11-27):
```ruby
def self.status
  # Validates provider availability
  # GET #{DEFAULT_URL}/status with x-api-key header
  # Raises ProviderUnavailableError if misconfigured
end
```

#### Instance Methods

**Channel Setup** (Line 29-45):
```ruby
def setup_channel_provider
  # POST /connections/{phone_number}
  # Payload:
  # - clientName: DEFAULT_CLIENT_NAME
  # - webhookUrl: whatsapp_channel.inbox.callback_webhook_url
  # - webhookVerifyToken: from provider_config
  # - includeMedia: false
  # Returns: true/raises ProviderUnavailableError
end

def disconnect_channel_provider
  # DELETE /connections/{phone_number}
  # Gracefully disconnects device
end
```

**Message Sending** (Line 58-74):
```ruby
def send_message(phone_number, message)
  # Determines message type (text, reaction, attachment)
  # For reactions: uses reaction_message_content
  # For attachments: downloads and base64-encodes files
  # For text: plain text content
  # POST /connections/{phone_number}/send-message
  # Returns: message source_id (external message ID)
end

def reaction_message_content
  # Finds original message by in_reply_to
  # Constructs react message with:
  # - key: {id, remoteJid, fromMe}
  # - text: reaction emoji/text
end

def attachment_message_content
  # Handles: image, audio, video, file, sticker
  # Base64-encodes attachment file
  # Sets mimetype and filename
  # Adds caption if present
  # Audio: supports ptt (Push-to-Talk) flag
end
```

**Presence & Typing** (Line 97-137):
```ruby
def toggle_typing_status(typing_status, phone_number:, **)
  # Maps Events::Types to Baileys presence values:
  # CONVERSATION_TYPING_ON   -> 'composing'
  # CONVERSATION_RECORDING   -> 'recording'
  # CONVERSATION_TYPING_OFF  -> 'paused'
  # PATCH /connections/{phone_number}/presence
end

def update_presence(status)
  # Maps to: available (online), unavailable (offline/busy)
  # PATCH /connections/{phone_number}/presence
end
```

**Message Status** (Line 139-208):
```ruby
def read_messages(messages, phone_number:, **)
  # POST /connections/{phone_number}/read-messages
  # Marks messages as read with:
  # - keys: [{id, remoteJid, fromMe}, ...]
end

def unread_message(phone_number, message)
  # POST /connections/{phone_number}/chat-modify
  # Marks message as unread using chat-modify endpoint
end

def received_messages(phone_number, messages)
  # POST /connections/{phone_number}/send-receipts
  # Sends delivery receipts for received messages
end
```

**Profile & Validation** (Line 210-237):
```ruby
def get_profile_pic(jid)
  # GET /connections/{phone_number}/profile-picture-url?jid={jid}
  # Returns profile picture URL
end

def on_whatsapp(phone_number)
  # POST /connections/{phone_number}/on-whatsapp
  # Checks if phone numbers exist on WhatsApp
  # Returns: [{jid, exists, lid}, ...]
end

def validate_provider_config?
  # GET /connections/{phone_number}/status/auth
  # Validates API credentials and connection
end
```

#### Error Handling (Line 319-360)

```ruby
with_error_handling :setup_channel_provider,
                    :disconnect_channel_provider,
                    :send_message,
                    :toggle_typing_status,
                    :update_presence,
                    :read_messages,
                    :unread_message,
                    :received_messages,
                    :on_whatsapp

def handle_channel_error
  # Updates connection to 'close'
  # Attempts automatic reconnection
  # Prevents infinite loops with @handling_error flag
end
```

### 2.3 Incoming Message Service

**File**: `/root/data/development/chatwoot.git/app/services/whatsapp/incoming_message_baileys_service.rb`

```ruby
class Whatsapp::IncomingMessageBaileysService < Whatsapp::IncomingMessageBaseService
  include Events::Types
  include Whatsapp::BaileysHandlers::ConnectionUpdate
  include Whatsapp::BaileysHandlers::MessagesUpsert
  include Whatsapp::BaileysHandlers::MessagesUpdate

  def perform
    # Validates webhook_verify_token
    # Dispatches PROVIDER_EVENT_RECEIVED event
    # Routes to process_{event_type} methods
    # Handles unsupported events gracefully
  end
end
```

### 2.4 Message Handlers

#### 2.4.1 Connection Update Handler

**File**: `/root/data/development/chatwoot.git/app/services/whatsapp/baileys_handlers/connection_update.rb`

```ruby
module Whatsapp::BaileysHandlers::ConnectionUpdate
  def process_connection_update
    # Connection states:
    # - 'close': Disconnected/failed
    # - 'connecting': QR code pending
    # - 'reconnecting': Establishing/relinking
    # - 'open': Ready for messaging
    
    # Updates provider_connection with:
    # - connection: current state
    # - qrDataUrl: QR code data URL (transient)
    # - error: i18n error message
  end
end
```

#### 2.4.2 Messages Upsert Handler

**File**: `/root/data/development/chatwoot.git/app/services/whatsapp/baileys_handlers/messages_upsert.rb`

Handles incoming and outgoing messages:

```ruby
def process_messages_upsert
  # For each message:
  # - Uses Baileys channel lock (avoid race conditions)
  # - Sets contact from phone number
  # - Creates conversation
  # - Handles media attachment download
  
  def set_contact
    # Creates/updates contact using:
    # - source_id: phone_number
    # - name: sender name or phone
    # - identifier: sender LID (WhatsApp Linked ID)
    # - phone_number: +{jid}
    # Updates contact avatar from profile picture
  end
  
  def handle_create_message
    # Creates message with:
    # - content: extracted from message type
    # - source_id: Baileys message ID
    # - sender: Contact (incoming) or User (outgoing)
    # - content_attributes: {external_created_at, in_reply_to_external_id, is_reaction}
    # - Attachments: auto-downloaded for media types
  end
end
```

#### 2.4.3 Messages Update Handler

**File**: `/root/data/development/chatwoot.git/app/services/whatsapp/baileys_handlers/messages_update.rb`

Handles message status and edits:

```ruby
def process_messages_update
  # For each update:
  # - Uses Baileys channel lock
  # - Updates message status if present
  # - Handles message edits if content changed
  
  def status_mapper
    # Maps Baileys status codes to Chatwoot:
    # 0 (ERROR)       -> 'failed'
    # 1,2 (PENDING)   -> 'sent'
    # 3 (DELIVERY_ACK)-> 'delivered'
    # 4 (READ)        -> 'read'
    # 5 (PLAYED)      -> unsupported (logged as warning)
  end
  
  def update_last_seen_at
    # Updates conversation.agent_last_seen_at when messages marked read
  end
  
  def handle_edited_content
    # Handles message edits
    # Updates message.content and marks is_edited=true
  end
end
```

#### 2.4.4 Helpers

**File**: `/root/data/development/chatwoot.git/app/services/whatsapp/baileys_handlers/helpers.rb`

```ruby
module Whatsapp::BaileysHandlers::Helpers
  # Message type detection (text, image, audio, video, file, sticker, reaction, etc.)
  def message_type
    # Complex logic: checks message.key structure
    # Handles extended text, reactions, contact messages
    # Falls back to 'unsupported' for unknown types
  end
  
  # JID parsing and validation
  def jid_type
    # Parses WhatsApp JID format
    # Returns: 'user', 'group', 'lid', 'status', 'broadcast', 'newsletter', 'call', 'unknown'
  end
  
  # Phone number extraction
  def phone_number_from_jid
    # Parses JID to extract phone number
    # Handles LID (Linked ID) format
    # Format: <user>_<agent>:<device>@<server>
  end
  
  # Contact name extraction
  def contact_name
    # Priority: verifiedBizName > pushName > phone_number
    # Prefers name for incoming/self messages
  end
  
  # Message content extraction
  def message_content
    # Extracts content based on message type
    # Handles text, captions, contact info
  end
  
  # Redis caching
  def cache_message_source_id_in_redis
    # Prevents duplicate message processing
    # Key: MESSAGE_SOURCE_KEY
  end
  
  # Avatar fetching
  def try_update_contact_avatar
    # Fetches profile picture from Baileys API
    # Enqueues Avatar::AvatarFromUrlJob
  end
end
```

### 2.5 Send Message Service

**File**: `/root/data/development/chatwoot.git/app/services/whatsapp/send_on_whatsapp_service.rb`

```ruby
class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  include BaileysHelper
  
  def perform_reply
    # Baileys-specific: Uses send_baileys_session_message
    # Wraps in baileys_channel_lock_on_outgoing_message
    # Prevents race conditions with incoming messages
  end
  
  def send_baileys_session_message
    with_baileys_channel_lock_on_outgoing_message(channel.id) { 
      send_session_message 
    }
  end
end
```

### 2.6 Helper Methods

**File**: `/root/data/development/chatwoot.git/app/helpers/baileys_helper.rb`

```ruby
module BaileysHelper
  CHANNEL_LOCK_ON_OUTGOING_MESSAGE_KEY = 
    'BAILEYS::CHANNEL_LOCK_ON_OUTGOING_MESSAGE::%<channel_id>s'
  CHANNEL_LOCK_ON_OUTGOING_MESSAGE_TIMEOUT = 15.seconds
  
  def baileys_extract_message_timestamp(timestamp)
    # Parses Baileys timestamp format
    # Handles: {low, high, unsigned} or string/number
    # Converts to Unix timestamp
  end
  
  def with_baileys_channel_lock_on_outgoing_message(channel_id, timeout:)
    # Redis-based distributed lock
    # Prevents race conditions between incoming/outgoing handlers
    # Times out after 15 seconds
    # Ensures clean lock cleanup in ensure block
  end
end
```

### 2.7 Webhook Handling

**File**: `/root/data/development/chatwoot.git/app/controllers/webhooks/whatsapp_controller.rb`

```ruby
class Webhooks::WhatsappController < ActionController::API
  def process_payload
    # Validates phone_number against inactive list
    # Checks webhook verify token against channel config
    # Routes to Webhooks::WhatsappEventsJob
  end
  
  def valid_token?(token)
    # Retrieves channel by phone_number
    # Compares token with provider_config['webhook_verify_token']
  end
end
```

**File**: `/root/data/development/chatwoot.git/app/jobs/webhooks/whatsapp_events_job.rb`

```ruby
class Webhooks::WhatsappEventsJob < ApplicationJob
  def perform(params = {})
    # Routes to provider-specific service based on channel.provider
    # For Baileys: Whatsapp::IncomingMessageBaileysService
    # Validates channel is active before processing
  end
end
```

### 2.8 Background Jobs

**File**: `/root/data/development/chatwoot.git/app/jobs/channels/whatsapp/baileys_connection_check_scheduler_job.rb`

```ruby
class Channels::Whatsapp::BaileysConnectionCheckSchedulerJob < ApplicationJob
  queue_as :low
  
  def perform
    # Scheduled job that periodically checks connections
    # Finds all Baileys channels with 'open' connection status
    # Enqueues BaileysConnectionCheckJob for each
  end
end
```

**File**: `/root/data/development/chatwoot.git/app/jobs/channels/whatsapp/baileys_connection_check_job.rb`

```ruby
class Channels::Whatsapp::BaileysConnectionCheckJob < ApplicationJob
  queue_as :low
  
  def perform(whatsapp_channel)
    # Calls setup_channel_provider to verify connection
    # Triggers reconnection if needed
  end
end
```

---

## 3. ENVIRONMENT CONFIGURATION

**File**: `/root/data/development/chatwoot.git/.env.example` (Lines 270-273)

```bash
# Baileys API Whatsapp provider
BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME=Chatwoot
BAILEYS_PROVIDER_DEFAULT_URL=http://localhost:3025
BAILEYS_PROVIDER_DEFAULT_API_KEY=
```

**Configuration Usage in Code**:

```ruby
# app/services/whatsapp/providers/whatsapp_baileys_service.rb
DEFAULT_CLIENT_NAME = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME', nil)
DEFAULT_URL = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_URL', nil)
DEFAULT_API_KEY = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_API_KEY', nil)

# app/models/channel/whatsapp.rb
def use_internal_host?
  provider == 'baileys' && ENV.fetch('BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL', false)
end
```

---

## 4. FRONTEND LAYER

### 4.1 Channel Selection Component

**File**: `/root/data/development/chatwoot.git/app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue`

```vue
<script setup>
const PROVIDER_TYPES = {
  BAILEYS: 'baileys',
  // ... other providers
};

const availableProviders = computed(() => {
  const providers = [
    {
      key: PROVIDER_TYPES.BAILEYS,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.BAILEYS'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.BAILEYS_DESC'),
      icon: 'i-woot-baileys',
    },
    // ... other providers
  ];
});
</script>
```

### 4.2 Baileys Configuration Component

**File**: `/root/data/development/chatwoot.git/app/javascript/dashboard/routes/dashboard/settings/inbox/channels/BaileysWhatsapp.vue`

```vue
<script setup>
// Input fields:
const inboxName = ref('');
const phoneNumber = ref('');
const apiKey = ref('');
const providerUrl = ref('');
const showAdvancedOptions = ref(false);
const markAsRead = ref(true);

// Validation rules
const rules = computed(() => ({
  inboxName: { required },
  phoneNumber: { required, isPhoneE164OrEmpty },
  providerUrl: {
    isValidURL: value => !value || isValidURL(value),
    requiredIf: requiredIf(apiKey),
  },
  apiKey: { requiredIf: requiredIf(providerUrl) },
}));

const createChannel = async () => {
  // Creates channel with:
  const providerConfig = {
    mark_as_read: markAsRead.value,
  };

  if (apiKey.value || providerUrl.value) {
    providerConfig.api_key = apiKey.value;
    providerConfig.url = providerUrl.value;
  }

  const whatsappChannel = await store.dispatch('inboxes/createChannel', {
    name: inboxName.value,
    channel: {
      type: 'whatsapp',
      phone_number: phoneNumber.value,
      provider: 'baileys',
      provider_config: providerConfig,
    },
  });
};
</script>

<!-- Form fields:
- Inbox Name (required)
- Phone Number (required, E.164 format)
- Advanced Options:
  - Provider URL (optional, must be valid URL)
  - API Key (optional, required if providerUrl)
  - Mark as Read toggle
-->
```

### 4.3 Internationalization

**File**: `/root/data/development/chatwoot.git/app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` (Lines 233-234)

```json
{
  "WHATSAPP": {
    "PROVIDERS": {
      "BAILEYS": "Baileys",
      "BAILEYS_DESC": "Connect via non-official API Baileys"
    },
    "PROVIDER_URL": {
      "LABEL": "Provider URL",
      "PLACEHOLDER": "If provider is not running locally, please provide the URL",
      "ERROR": "Please enter a valid URL"
    },
    "API_KEY": {
      "LABEL": "API key",
      "PLACEHOLDER": "API key",
      "ERROR": "Please enter a valid value."
    },
    "MARK_AS_READ": {
      "LABEL": "Send read receipts"
    }
  }
}
```

---

## 5. BUSINESS LOGIC FLOWS

### 5.1 Channel Creation Flow

```
1. User selects Baileys provider
   ↓
2. Enters: inbox name, phone number, optional API key/URL
   ↓
3. Frontend validates inputs (E.164 format, URL validation)
   ↓
4. Dispatches inboxes/createChannel action
   ↓
5. Backend creates Channel::Whatsapp with:
   - provider: 'baileys'
   - phone_number: validated E.164 number
   - provider_config: {
       webhook_verify_token: auto-generated secure random,
       api_key: optional override,
       provider_url: optional override,
       mark_as_read: boolean
     }
   - provider_connection: {} (empty initially)
   ↓
6. Calls setup_channel_provider via provider_service
   ↓
7. Makes POST /connections/{phone_number} to Baileys API
   ↓
8. Baileys API generates QR code
   ↓
9. Webhook callback with connection_update event
   ↓
10. Receives qr_data_url in provider_connection
    ↓
11. Frontend polls/displays QR code to user
    ↓
12. User scans with WhatsApp mobile
    ↓
13. Baileys API generates new webhook event with connection: 'open'
    ↓
14. Channel ready for messaging
```

### 5.2 Message Receive Flow

```
1. WhatsApp user sends message to linked number
   ↓
2. Baileys provider receives message
   ↓
3. Sends webhook POST to callback_webhook_url with:
   - phone_number: recipient number
   - event: 'messages.upsert'
   - webhookVerifyToken: for validation
   - data: {messages: [...]}
   ↓
4. Webhooks::WhatsappController#process_payload
   - Validates phone_number not in inactive list
   - Checks webhook verify token
   ↓
5. Enqueues Webhooks::WhatsappEventsJob
   ↓
6. Job routes to Whatsapp::IncomingMessageBaileysService
   ↓
7. Service processes message through handlers:
   a) Validates webhook token
   b) Dispatches PROVIDER_EVENT_RECEIVED
   c) Calls process_messages_upsert
   ↓
8. Messages Upsert Handler:
   - Applies Baileys channel lock
   - Determines if incoming/outgoing
   - Extracts JID and phone number
   - Creates/updates contact
   - Creates message with content_attributes
   - Downloads media if present
   - Calls received_messages webhook if incoming
   ↓
9. Message appears in conversation
```

### 5.3 Message Send Flow

```
1. Agent composes message in conversation
   ↓
2. Message created with:
   - sender: current user
   - sender_type: 'User'
   - message_type: 'outgoing'
   ↓
3. Whatsapp::SendOnWhatsappService#perform
   ↓
4. For Baileys:
   a) Calls with_baileys_channel_lock_on_outgoing_message
   b) Acquires Redis lock (prevents race with incoming)
   c) Calls channel.send_message
   ↓
5. Whatsapp::Providers::WhatsappBaileysService#send_message:
   - Determines message type (text/reaction/attachment)
   - Constructs message_content based on type
   - Makes POST /connections/{phone}/send-message
   - Receives message ID and timestamp
   ↓
6. Updates message with:
   - source_id: external message ID
   - external_created_at: timestamp from Baileys
   ↓
7. Redis lock released in ensure block
   ↓
8. Baileys API sends to WhatsApp servers
   ↓
9. WhatsApp delivers to recipient phone
```

### 5.4 Message Status Update Flow

```
1. WhatsApp server updates message status (sent/delivered/read)
   ↓
2. Baileys provider sends webhook:
   - event: 'messages.update'
   - data: [{key: {id, ...}, update: {status: code}}]
   ↓
3. Webhooks::WhatsappEventsJob routes to handler
   ↓
4. Messages Update Handler:
   - Applies Baileys channel lock
   - Finds message by source_id
   - Maps Baileys status code to Chatwoot status
   - Updates message.status
   - For 'read' status: updates conversation.agent_last_seen_at
   ↓
5. Message status reflected in UI
```

### 5.5 Connection Management Flow

```
Background Job (every N minutes):
Channels::Whatsapp::BaileysConnectionCheckSchedulerJob
  ↓
  Queries: Channel::Whatsapp.where(provider: 'baileys', connection: 'open')
  ↓
  For each: Enqueues Channels::Whatsapp::BaileysConnectionCheckJob
  ↓
  Job calls: whatsapp_channel.setup_channel_provider
  ↓
  Re-validates connection with Baileys API
  ↓
  If fails: Triggers error handling (see Error Handling Flow)


Webhook Event Flow:
1. Baileys sends connection.update event
   - connection: 'close|connecting|reconnecting|open'
   - qrDataUrl: QR code if needed
   - error: error message if failed
   ↓
2. Handler processes_connection_update
   ↓
3. Updates channel.provider_connection with new state
   ↓
4. Frontend polls and displays QR code if 'connecting'
```

### 5.6 Error Handling Flow

```
Provider Error (e.g., API unreachable):
1. WhatsappBaileysService method raises error
   ↓
2. with_error_handling wrapper catches exception
   ↓
3. Calls handle_channel_error:
   a) Sets connection to 'close'
   b) Sets @handling_error flag (prevent loops)
   c) Attempts automatic reconnect via setup_channel_provider
   d) Logs failure if reconnect fails
   e) Clears @handling_error flag
   ↓
4. Re-raises original exception
   ↓
5. Webhook job catches and logs error
   ↓
6. Channel marked as needing reauthorization


User Action (Channel deletion):
1. User deletes inbox
   ↓
2. Calls Channel::Whatsapp#disconnect_channel_provider (if method exists)
   ↓
3. Makes DELETE /connections/{phone_number}
   ↓
4. Baileys API unlinks device
   ↓
5. Channel destroyed with proper cleanup
```

---

## 6. KEY INTEGRATION PATTERNS

### 6.1 Provider Pattern

All WhatsApp providers implement a common interface via `Whatsapp::Providers::BaseService`:

```ruby
# Required methods:
- send_message(phone_number, message)
- send_template(phone_number, template_info, message)
- sync_templates
- validate_provider_config?
- setup_channel_provider (optional)
- disconnect_channel_provider (optional)

# Baileys extends with additional methods:
- toggle_typing_status
- update_presence
- read_messages
- unread_message
- received_messages
- on_whatsapp
- get_profile_pic
- status (class method)
```

### 6.2 Webhook Handler Pattern

Message handlers use inclusion of multiple handler modules:

```ruby
class Whatsapp::IncomingMessageBaileysService
  include Whatsapp::BaileysHandlers::ConnectionUpdate
  include Whatsapp::BaileysHandlers::MessagesUpsert
  include Whatsapp::BaileysHandlers::MessagesUpdate
  
  # Each handler provides process_{event_type} methods
  # Dynamically called based on webhook event
end
```

### 6.3 Locking Pattern

Prevents race conditions between incoming webhook and outgoing send:

```ruby
with_baileys_channel_lock_on_outgoing_message(channel_id, timeout: 15.seconds) do
  # Critical section: message sending
end

# Uses Redis for distributed lock
# Key: BAILEYS::CHANNEL_LOCK_ON_OUTGOING_MESSAGE::{channel_id}
# Timeout: 15 seconds
```

### 6.4 Configuration Pattern

Three-tier configuration hierarchy:

```ruby
# 1. Environment variables (highest priority for default instance)
BAILEYS_PROVIDER_DEFAULT_URL
BAILEYS_PROVIDER_DEFAULT_API_KEY

# 2. Channel provider_config (per-channel override)
whatsapp_channel.provider_config['provider_url']
whatsapp_channel.provider_config['api_key']

# 3. Default constants (fallback)
Whatsapp::Providers::WhatsappBaileysService::DEFAULT_URL
```

---

## 7. API ENDPOINTS REFERENCE

### 7.1 Baileys API Endpoints Called

Base URL: `ENV['BAILEYS_PROVIDER_DEFAULT_URL']` or override in `provider_config['provider_url']`

Authentication: Header `x-api-key: ENV['BAILEYS_PROVIDER_DEFAULT_API_KEY']` or override

**Connection Management**:
- `POST /connections/{phone_number}` - Setup/link device with QR code
- `DELETE /connections/{phone_number}` - Disconnect device
- `GET /connections/{phone_number}/status/auth` - Validate credentials

**Messaging**:
- `POST /connections/{phone_number}/send-message` - Send message
- `POST /connections/{phone_number}/read-messages` - Mark messages read
- `POST /connections/{phone_number}/send-receipts` - Send delivery receipts
- `POST /connections/{phone_number}/chat-modify` - Mark message unread

**Presence**:
- `PATCH /connections/{phone_number}/presence` - Update typing/presence status

**Contact Info**:
- `GET /connections/{phone_number}/profile-picture-url?jid={jid}` - Get profile pic
- `POST /connections/{phone_number}/on-whatsapp` - Check if numbers on WhatsApp

**Status**:
- `GET /status` - Provider health check
- `GET /status/auth` - Authentication status

### 7.2 Chatwoot Webhook Endpoint

Receives callbacks from Baileys provider:

```
POST /api/v1/webhooks/whatsapp?phone_number={phone}&webhookVerifyToken={token}

Body: {
  "phone_number": "+55...",
  "webhookVerifyToken": "...",
  "event": "messages.upsert|messages.update|connection.update",
  "data": { ... event-specific payload ... }
}
```

---

## 8. DATA STRUCTURES

### 8.1 Message JID Format

WhatsApp Jabber ID (JID) format used by Baileys:

```
User message: {user_number}@s.whatsapp.net
Group message: {group_id}@g.us
Status message: status@broadcast
Broadcast: {id}@broadcast
Newsletter: {id}@newsletter
LID (Linked ID): {lid}@lid
```

### 8.2 Message Timestamp Format

Baileys sends timestamps in various formats:

```ruby
# Format 1: Simple number (Unix timestamp in seconds)
timestamp = 1748003165

# Format 2: BigInt hash (low/high components)
{
  "low" => 1748003165,
  "high" => 0,
  "unsigned" => true
}

# Conversion:
(high << 32) | low
```

### 8.3 Message Content Structures

```ruby
# Text message
{
  message: {
    conversation: "Hello",
    # or
    extendedTextMessage: { text: "Hello" }
  }
}

# Image with caption
{
  message: {
    imageMessage: {
      caption: "Look at this",
      mimetype: "image/jpeg",
      # ... media data
    }
  }
}

# Reaction (emoji/text response to another message)
{
  message: {
    reactionMessage: {
      text: "👍",  # emoji or text
      key: { id: "original_message_id", ... }
    }
  }
}

# Contact message
{
  message: {
    contactMessage: {
      displayName: "John Doe",
      vcard: "BEGIN:VCARD\n...waid=551187654321\n..."
    }
  }
}
```

---

## 9. CRITICAL IMPLEMENTATION DETAILS

### 9.1 Webhook Verification

Every webhook must include valid `webhookVerifyToken`:

```ruby
# Generated during channel creation:
SecureRandom.hex(16)  # 32 character hex string

# Verified on every request:
processed_params[:webhookVerifyToken] == 
  inbox.channel.provider_config['webhook_verify_token']
```

### 9.2 JID Parsing

Critical for extracting phone numbers from WhatsApp JIDs:

```ruby
def phone_number_from_jid
  jid = @raw_message[:key][:remoteJid]
  # Format: "1234567890_0:32@s.whatsapp.net" (LID)
  # or: "1234567890@s.whatsapp.net" (regular)
  jid.split('@').first.split(':').first.split('_').first
end
```

### 9.3 Message Type Detection

Uses complex nested key checking to determine message type:

```ruby
message_type_hierarchy = [
  :conversation        => 'text',
  :extendedTextMessage => 'text',
  :imageMessage        => 'image',
  :audioMessage        => 'audio',
  :videoMessage        => 'video',
  :documentMessage     => 'file',
  :stickerMessage      => 'sticker',
  :reactionMessage     => 'reaction',
  :editedMessage       => 'edited',
  :contactMessage      => 'contact',
  :protocolMessage     => 'protocol',
  # Special case for context-only messages
]
```

### 9.4 Status Code Mapping

Baileys sends numeric status codes:

```ruby
STATUS_MAP = {
  0 => 'failed',       # ERROR
  1 => 'sent',         # PENDING
  2 => 'sent',         # SERVER_ACK
  3 => 'delivered',    # DELIVERY_ACK
  4 => 'read',         # READ
  5 => nil             # PLAYED (unsupported)
}
```

### 9.5 Duplex Locking

Critical for preventing race conditions:

```ruby
# Shared lock between:
# 1. Incoming message handler (process_messages_upsert)
# 2. Outgoing message sender (send_baileys_session_message)

# Lock acquired for 15 seconds during critical section
# Prevents: Outgoing message being processed as incoming
#           and vice versa
```

---

## 10. FILE SUMMARY

### Core Implementation Files (12 main files)

| Category | File Path | Lines | Purpose |
|----------|-----------|-------|---------|
| Model | `/app/models/channel/whatsapp.rb` | 176 | WhatsApp channel model with provider routing |
| Provider | `/app/services/whatsapp/providers/whatsapp_baileys_service.rb` | 361 | Baileys API client implementation |
| Handlers | `/app/services/whatsapp/baileys_handlers/helpers.rb` | 182 | Message parsing and JID extraction |
| Handlers | `/app/services/whatsapp/baileys_handlers/messages_upsert.rb` | 132 | Incoming/outgoing message creation |
| Handlers | `/app/services/whatsapp/baileys_handlers/messages_update.rb` | 87 | Message status updates |
| Handlers | `/app/services/whatsapp/baileys_handlers/connection_update.rb` | 23 | Connection state management |
| Service | `/app/services/whatsapp/incoming_message_baileys_service.rb` | 26 | Webhook event dispatcher |
| Service | `/app/services/whatsapp/send_on_whatsapp_service.rb` | 68 | Message sending with provider routing |
| Helper | `/app/helpers/baileys_helper.rb` | 46 | Timestamp parsing and locking |
| Controller | `/app/controllers/webhooks/whatsapp_controller.rb` | 49 | Webhook routing |
| Job | `/app/jobs/webhooks/whatsapp_events_job.rb` | 54 | Async webhook processing |
| Jobs | `/app/jobs/channels/whatsapp/baileys_connection_check*.rb` | 19 | Connection health monitoring |

### Database Files (3 files)

| File | Purpose |
|------|---------|
| `db/migrate/20250314185939_add_provider_connection_to_whatsapp.rb` | Add JSONB connection state column |
| `db/migrate/20250726142410_add_whatsapp_channel_provider_index.rb` | Add GIN index for provider_connection |
| `db/migrate/20250928173414_recreate_whatsapp_channel_provider_connection_index.rb` | Recreate index for multiple providers |

### Frontend Files (3 files)

| File | Purpose |
|------|---------|
| `/app/javascript/dashboard/routes/.../channels/Whatsapp.vue` | Provider selection UI |
| `/app/javascript/dashboard/routes/.../channels/BaileysWhatsapp.vue` | Baileys configuration form |
| `/app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` | Internationalization strings |

### Test Files (7 files)

| File | Purpose |
|------|---------|
| `spec/services/whatsapp/providers/whatsapp_baileys_service_spec.rb` | Provider service tests |
| `spec/services/whatsapp/incoming_message_baileys_service_spec.rb` | Incoming message handler tests |
| `spec/jobs/channels/whatsapp/baileys_connection_check_job_spec.rb` | Connection check job tests |
| `spec/jobs/channels/whatsapp/baileys_connection_check_scheduler_job_spec.rb` | Scheduler job tests |
| `spec/helpers/baileys_helper_spec.rb` | Helper utility tests |
| `spec/models/channel/whatsapp_spec.rb` | Model tests |
| `spec/controllers/webhooks/whatsapp_controller_spec.rb` | Webhook controller tests |

---

## 11. SECURITY CONSIDERATIONS

### 11.1 Webhook Verification

Every webhook is validated with a secret token stored in `provider_config`:

```ruby
# Token validation:
processed_params[:webhookVerifyToken] == 
  inbox.channel.provider_config['webhook_verify_token']

# If invalid:
raise Whatsapp::IncomingMessageBaileysService::InvalidWebhookVerifyToken
# Returns HTTP 401 Unauthorized
```

### 11.2 API Key Security

API keys are stored in:
1. Environment variables (sensitive)
2. Channel `provider_config` JSONB (database)

Best practices:
- Generate secure ENV variable during deployment
- Can override per-channel if needed
- Never logged in error messages

### 11.3 Phone Number Validation

E.164 format required:
- Must start with `+`
- Only digits allowed after `+`
- No spaces or special characters

### 11.4 Redis Lock Security

Distributed lock prevents race conditions:
- Key: `BAILEYS::CHANNEL_LOCK_ON_OUTGOING_MESSAGE::{channel_id}`
- Timeout: 15 seconds (auto-cleanup)
- Set with `nx` flag (atomic)

---

## 12. PERFORMANCE CONSIDERATIONS

### 12.1 Database Indexes

GIN index on `provider_connection` JSONB for Baileys channels:

```sql
CREATE INDEX index_channel_whatsapp_provider_connection 
  ON channel_whatsapp 
  USING gin (provider_connection) 
  WHERE provider = 'baileys';
```

Optimizes queries like:
```ruby
Channel::Whatsapp.where(provider: 'baileys')
                 .where("provider_connection->>'connection' = ?", 'open')
```

### 12.2 Message Deduplication

Redis-based caching prevents duplicate message processing:

```ruby
key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: raw_message_id)
Redis::Alfred.setex(key, true)  # Cached during processing
```

### 12.3 Lock Timeouts

15-second timeout prevents deadlocks:

```ruby
while (Time.now.to_i - start_time) < timeout
  break if baileys_lock_channel_on_outgoing_message(channel_id, timeout)
  sleep(0.1)
end
```

---

## 13. KNOWN LIMITATIONS & NOTES

### 13.1 Baileys Limitations

1. **Non-official API**: Not maintained by WhatsApp/Meta
2. **QR Linking**: Requires actual WhatsApp account scan
3. **Rate Limiting**: May be subject to WhatsApp throttling
4. **Device Sync**: Requires active device connection
5. **Multiple Devices**: Not supported simultaneously

### 13.2 Implementation Notes

1. **includeMedia: false**: Media not returned in webhook by default
2. **Message edits**: Handled via `editedMessage` in webhook
3. **Reactions**: Stored as message with `is_reaction` flag
4. **Read status**: Updates `agent_last_seen_at` on read
5. **Unread messages**: Supported via `chat-modify` endpoint

### 13.3 TODO Items in Code

```ruby
# app/services/whatsapp/baileys_service.rb line 37:
# TODO: Remove on Baileys v2, default will be false

# app/services/whatsapp/baileys_handlers/messages_upsert.rb line 46:
# FIXME: update the source_id to use sender LID

# app/services/whatsapp/baileys_handlers/helpers.rb line 141:
# TODO: Handle denormalized Brazilian phone numbers

# app/services/whatsapp/baileys_handlers/helpers.rb line 160:
# TODO: Current logic will never update avatar if changed on WhatsApp
```

---

## 14. DEPLOYMENT CHECKLIST

- [ ] Set `BAILEYS_PROVIDER_DEFAULT_URL` environment variable
- [ ] Set `BAILEYS_PROVIDER_DEFAULT_API_KEY` environment variable
- [ ] Set `BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME` (default: "Chatwoot")
- [ ] Configure `BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL` if needed (default: false)
- [ ] Run database migrations for provider_connection column
- [ ] Run database migrations for GIN indexes
- [ ] Enable/configure background job scheduler for connection health checks
- [ ] Test webhook connectivity from Baileys provider to Chatwoot instance
- [ ] Verify webhook token generation working correctly

---

## APPENDIX: API REQUEST/RESPONSE EXAMPLES

### A.1 Setup Channel Provider

**Request**:
```http
POST /connections/+551187654321 HTTP/1.1
Host: baileys-provider.example.com
x-api-key: your-api-key
Content-Type: application/json

{
  "clientName": "Chatwoot",
  "webhookUrl": "https://chatwoot.example.com/api/v1/webhooks/whatsapp",
  "webhookVerifyToken": "a1b2c3d4e5f6...",
  "includeMedia": false
}
```

**Response**:
```json
{
  "phone": "+551187654321",
  "connection": "connecting",
  "qrDataUrl": "data:image/png;base64,iVBORw0KGgoAAAANS..."
}
```

### A.2 Send Message

**Request**:
```http
POST /connections/+551187654321/send-message HTTP/1.1
Host: baileys-provider.example.com
x-api-key: your-api-key
Content-Type: application/json

{
  "jid": "551187654321@s.whatsapp.net",
  "messageContent": {
    "text": "Hello, world!"
  }
}
```

**Response**:
```json
{
  "data": {
    "key": {
      "id": "3EB0DD7F3DBE0F2A1B06A",
      "fromMe": true,
      "remoteJid": "551187654321@s.whatsapp.net"
    },
    "messageTimestamp": {
      "low": 1748003165,
      "high": 0,
      "unsigned": true
    }
  }
}
```

### A.3 Message Update Webhook

**Request**:
```http
POST /api/v1/webhooks/whatsapp HTTP/1.1
Host: chatwoot.example.com
Content-Type: application/json

{
  "phone_number": "+551187654321",
  "webhookVerifyToken": "a1b2c3d4e5f6...",
  "event": "messages.update",
  "data": [
    {
      "key": {
        "id": "3EB0DD7F3DBE0F2A1B06A",
        "remoteJid": "551187654321@s.whatsapp.net",
        "fromMe": true
      },
      "update": {
        "status": 4
      }
    }
  ]
}
```

