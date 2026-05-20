---
Created: 2025-11-04T12:00:00Z
Operation: Analysis of Whatsmeow instance lifecycle and connection management
Context: User inquiry about Whatsmeow integration compliance with instance management
Related Files:
  - app/models/channel/whatsapp.rb
  - app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb
  - app/services/whatsapp/incoming_message_whatsmeow_service.rb
  - app/services/whatsapp/whatsmeow_handlers/connection_update.rb
  - app/controllers/api/v1/accounts/inboxes_controller.rb
---

# Whatsmeow Instance Lifecycle & Connection Management Analysis

## Executive Summary

**Status: ARCHITECTURALLY COMPLIANT with operational gaps**

The Whatsmeow integration correctly implements the Multi-Device architecture:
- **1 Chatwoot Inbox = 1 Whatsmeow Instance = 1 WhatsApp Device**
- Each inbox maintains isolated instance lifecycle
- Phone number serves as unique instance identifier
- Connection state properly tracked per-instance

The core architecture is **compliant**, but operational reliability has gaps compared to Baileys provider (missing QR polling, webhook config, status refresh).

---

## Multi-Device Architecture Compliance

### WhatsApp Multi-Device Protocol

WhatsApp's Multi-Device protocol allows a single WhatsApp account to be used across multiple devices simultaneously without requiring the phone to be online. Each device:
- Has independent encryption keys
- Receives messages directly from WhatsApp servers
- Can send/receive independently of other devices
- Requires QR code linking to authorize the device

### Whatsmeow Implementation Model

**Whatsmeow API Instance = WhatsApp Device**

```
┌─────────────────────────────────────────────────────────────┐
│                    WhatsApp Account                          │
│                   (+1234567890)                              │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
   ┌────────┐         ┌────────┐         ┌────────┐
   │ Phone  │         │ Device │         │ Device │
   │        │         │   #1   │         │   #2   │
   └────────┘         └────────┘         └────────┘
                           │                   │
                           │                   │
                    ┌──────▼──────┐     ┌──────▼──────┐
                    │ Whatsmeow   │     │ Whatsmeow   │
                    │ Instance #1 │     │ Instance #2 │
                    └──────┬──────┘     └──────┬──────┘
                           │                   │
                    ┌──────▼──────┐     ┌──────▼──────┐
                    │  Chatwoot   │     │  Chatwoot   │
                    │   Inbox #1  │     │   Inbox #2  │
                    └─────────────┘     └─────────────┘
```

### Chatwoot → Whatsmeow Mapping

**Current Implementation:**

```ruby
# app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb:51-59

instance_id = normalized_phone_number  # e.g., "1234567890"

create_instance_response = HTTParty.post(
  "#{provider_url}/instances",
  headers: api_headers,
  body: {
    instance_id: instance_id,        # ← Unique per inbox
    phone_number: whatsapp_channel.phone_number
  }.to_json
)
```

**Mapping:**
```
Chatwoot Inbox (ID: 123, Phone: +1234567890)
    ↓
Channel::Whatsapp (provider: 'whatsmeow', phone_number: '+1234567890')
    ↓
Whatsmeow Instance (instance_id: '1234567890')
    ↓
WhatsApp Device (linked via QR code)
```

### Compliance Verification

#### ✅ 1. Unique Instance Per Inbox

**Code Evidence:**
```ruby
# app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb:302-304
def normalized_phone_number
  whatsapp_channel.phone_number.delete('+')  # Phone number IS instance_id
end
```

**Database Constraint:**
```ruby
# app/models/channel/whatsapp.rb:34
validates :phone_number, presence: true, uniqueness: true
```

**Result:** ✅ Phone number uniqueness ensures 1 Inbox = 1 Instance

#### ✅ 2. Independent Lifecycle Management

**Instance Creation (Setup):**
```ruby
# Each inbox triggers independent instance creation
def setup_channel_provider
  instance_id = normalized_phone_number
  # POST /instances - Creates NEW instance
  # POST /instances/:id/connect - Generates NEW QR code
end
```

**Instance Deletion (Teardown):**
```ruby
# Each inbox cleanup is isolated
def disconnect_channel_provider
  instance_id = normalized_phone_number
  # POST /instances/:id/disconnect - Logs out THIS device only
  # DELETE /instances/:id - Removes THIS instance only
end
```

**Result:** ✅ Each inbox has independent create/destroy lifecycle

#### ✅ 3. Isolated Connection State

**State Storage:**
```ruby
# app/models/channel/whatsapp.rb:74-78
def update_provider_connection!(provider_connection)
  assign_attributes(provider_connection: provider_connection)
  save!(validate: false)  # Per-channel state
end
```

**Webhook Routing:**
```ruby
# app/services/whatsapp/incoming_message_whatsmeow_service.rb:26-41
# Webhook payload includes instance_id for routing
{
  event: "connection.update",
  instance_id: "1234567890",  # ← Routes to correct inbox
  data: { connection: "open" }
}

# Finds correct inbox by phone number
inbox = Inbox.joins(:channel)
             .where(channel: { phone_number: "+#{instance_id}" })
             .first
```

**Result:** ✅ Connection state tracked per-inbox, no cross-contamination

#### ✅ 4. QR Code Device Linking

**QR Code Generation:**
```ruby
# Triggered per-instance during connect
POST /instances/1234567890/connect
  → Whatsmeow generates device-specific QR code
  → Webhook delivers: { connection: "connecting", qr_code: "..." }
```

**QR Code Scanning:**
```
User scans QR code with WhatsApp app
  → WhatsApp authorizes THIS specific device
  → Whatsmeow instance receives auth credentials
  → Webhook delivers: { connection: "open" }
  → Chatwoot inbox becomes active
```

**Result:** ✅ Each inbox requires independent device authorization

#### ✅ 5. Multi-Inbox Support

**Scenario: Same Account, Multiple Inboxes**

```ruby
# Inbox A
phone_number: "+1234567890"
instance_id: "1234567890"
provider_connection: { connection: "open" }

# Inbox B (SEPARATE device on SAME WhatsApp account)
phone_number: "+1234567891"  # Different phone = Different account
instance_id: "1234567891"
provider_connection: { connection: "open" }
```

**Important:** Current implementation assumes **different phone numbers = different WhatsApp accounts**.

**Does NOT support:** Multiple inboxes for the SAME phone number (same account, multiple devices).

**Why:** `phone_number` uniqueness constraint prevents this.

**Implication:** Each Chatwoot inbox represents a UNIQUE WhatsApp business phone number, not multiple devices for the same number.

**Result:** ⚠️ Supports multi-device protocol, but 1:1 phone-to-inbox mapping

### Architecture Decision: Phone Number as Instance ID

**Current Design:**
```ruby
instance_id = normalized_phone_number  # "1234567890"
```

**Pros:**
- Simple, predictable mapping
- Natural uniqueness (phone number already unique)
- Easy debugging (instance ID == phone number)
- Idempotent instance creation (409 Conflict on duplicate)

**Cons:**
- Cannot support multiple Chatwoot inboxes for same WhatsApp number
- If phone number changes, instance must be recreated
- Instance ID tied to business logic (phone number)

**Alternative Design (Not Implemented):**
```ruby
instance_id = SecureRandom.uuid  # Random UUID per inbox
# Stored in provider_config['instance_id']
```

**Would Enable:**
- Multiple inboxes per WhatsApp account (different devices)
- Phone number changes without instance recreation
- True multi-device support

**Trade-off:**
- Added complexity (must track instance_id separately)
- Loses intuitive debugging (UUID vs phone number)
- Requires migration for existing inboxes

**Recommendation:** Current design is appropriate for Chatwoot's use case (1 business phone = 1 inbox).

---

## Current Implementation Flow

### 1. Inbox Creation Flow

**Frontend (WhatsmeowWhatsapp.vue:45-81)**
```javascript
const whatsappChannel = await store.dispatch('inboxes/createChannel', {
  name: inboxName.value,
  channel: {
    type: 'whatsapp',
    phone_number: phoneNumber.value,
    provider: 'whatsmeow',
    provider_config: providerConfig,
  },
});
```

**Backend (InboxesController#create:30-43)**
```ruby
ActiveRecord::Base.transaction do
  channel = create_channel  # Creates Channel::Whatsapp record
  @inbox = Current.account.inboxes.build(
    name: inbox_name(channel),
    channel: channel
  )
  @inbox.save!
end
```

**Channel Model (channel/whatsapp.rb:22-40)**
- Creates `Channel::Whatsapp` record with:
  - `phone_number`: Unique identifier
  - `provider`: 'whatsmeow'
  - `provider_config`: API key, provider URL, webhook token
  - `provider_connection`: Empty on creation
- Triggers `after_create :sync_templates` (no-op for Whatsmeow)
- **DOES NOT** automatically call `setup_channel_provider`

### 2. Instance Setup Flow

**Current Behavior:**
Instance creation happens separately from inbox creation via manual action or during link device modal.

**WhatsappLinkDeviceModal.vue:45-49**
```javascript
onMounted(() => {
  if (!connection.value || connection.value === 'close') {
    setup();  // Calls setupChannelProvider action
  }
});
```

**Controller Endpoint (InboxesController#setup_channel_provider:68-77)**
```ruby
def setup_channel_provider
  channel = @inbox.channel
  unless channel.respond_to?(:setup_channel_provider)
    render json: { error: 'Channel does not support setup' }, status: :unprocessable_entity and return
  end
  channel.setup_channel_provider
  head :ok
end
```

**Service Method (WhatsappWhatsmeowService#setup_channel_provider:49-83)**
```ruby
def setup_channel_provider
  # Step 1: Create instance if not exists
  instance_id = normalized_phone_number  # e.g., "1234567890"

  create_instance_response = HTTParty.post(
    "#{provider_url}/instances",
    headers: api_headers,
    body: {
      instance_id: instance_id,
      phone_number: whatsapp_channel.phone_number
    }.to_json
  )

  # 409 Conflict (already exists) is OK
  unless [200, 201, 409].include?(create_instance_response.code)
    raise ProviderUnavailableError, 'Failed to create Whatsmeow instance'
  end

  # Step 2: Connect instance (generates QR code)
  connect_response = HTTParty.post(
    "#{provider_url}/instances/#{instance_id}/connect",
    headers: api_headers
  )

  unless process_response(connect_response)
    raise ProviderUnavailableError, 'Failed to connect Whatsmeow instance'
  end

  true
end
```

**Key Points:**
- Uses `phone_number` (digits only) as `instance_id`
- Two-step process: Create + Connect
- 409 Conflict handled (idempotent)
- No direct return of connection state (relies on webhooks)

### 3. Connection State Management

**State Storage (channel/whatsapp.rb:74-87)**
```ruby
def update_provider_connection!(provider_connection)
  assign_attributes(provider_connection: provider_connection)
  # Skip validation to allow quick updates
  save!(validate: false)
end

def provider_connection_data
  data = { connection: provider_connection['connection'] }
  if Current.account_user&.administrator?
    data[:qr_data_url] = provider_connection['qr_data_url']
    data[:error] = provider_connection['error']
  end
  data
end
```

**Webhook Updates (connection_update.rb:23-40)**
```ruby
def process_connection_update
  data = processed_params[:data] || {}

  connection_data = {
    connection: data[:connection] || data['connection'],
    qr_data_url: extract_qr_data_url(data),
    error: extract_error_message(data)
  }.compact

  inbox.channel.update_provider_connection!(connection_data)
  log_connection_state(data)
end
```

**Connection States:**
- `close`: Disconnected, no instance or logged out
- `connecting`: Connecting, QR code available
- `open`: Fully connected and authenticated

### 4. QR Code Lifecycle

**Current Behavior:**
QR codes are delivered via webhook events from Whatsmeow API.

**Webhook Flow:**
1. Chatwoot calls `POST /instances/:id/connect`
2. Whatsmeow API starts connection process
3. Whatsmeow API sends webhook: `connection.update` with `qr_code` field
4. Chatwoot receives webhook → `IncomingMessageWhatsmeowService`
5. Handler extracts QR code → updates `provider_connection.qr_data_url`
6. Frontend polls inbox state → displays QR code

**QR Code Extraction (connection_update.rb:42-53)**
```ruby
def extract_qr_data_url(data)
  qr_code = data[:qr_code] || data['qr_code']
  return nil unless qr_code

  # Convert to data URL if not already
  if qr_code.start_with?('data:image/')
    qr_code
  else
    "data:image/png;base64,#{qr_code}"
  end
end
```

### 5. Instance Destruction

**Controller (InboxesController#disconnect_channel_provider:79-90)**
```ruby
def disconnect_channel_provider
  channel = @inbox.channel

  unless channel.respond_to?(:disconnect_channel_provider)
    render json: { error: 'Channel does not support disconnect' }, status: :unprocessable_entity and return
  end

  channel.disconnect_channel_provider
  head :ok
ensure
  channel.update_provider_connection!(connection: 'close') if channel.respond_to?(:update_provider_connection!)
end
```

**Service Method (WhatsappWhatsmeowService#disconnect_channel_provider:86-111)**
```ruby
def disconnect_channel_provider
  instance_id = normalized_phone_number

  # Step 1: Disconnect (graceful logout)
  disconnect_response = HTTParty.post(
    "#{provider_url}/instances/#{instance_id}/disconnect",
    headers: api_headers
  )

  unless process_response(disconnect_response)
    Rails.logger.warn "Failed to disconnect (may already be disconnected)"
  end

  # Step 2: Delete instance
  delete_response = HTTParty.delete(
    "#{provider_url}/instances/#{instance_id}",
    headers: api_headers
  )

  unless process_response(delete_response)
    raise ProviderUnavailableError, 'Failed to delete instance'
  end

  true
end
```

**Model Hook (channel/whatsapp.rb:42)**
```ruby
before_destroy :disconnect_channel_provider,
  if: -> { provider_service.respond_to?(:disconnect_channel_provider) }
```

---

## Comparison with Baileys Provider

### Similarities

1. **Two-Step Setup:**
   - Both create instance then connect
   - Both use phone number as identifier

2. **Webhook-Driven State:**
   - Both receive connection updates via webhooks
   - Both update `provider_connection` JSONB column

3. **QR Code Delivery:**
   - Both deliver QR codes via webhook events
   - Both store in `provider_connection.qr_data_url`

4. **Lifecycle Hooks:**
   - Both implement `setup_channel_provider`
   - Both implement `disconnect_channel_provider`
   - Both called via `before_destroy` hook

### Key Differences

#### Baileys Has QR Code Polling Job

**ZapiQrCodeJob (app/jobs/channels/whatsapp/zapi_qr_code_job.rb)**
```ruby
def perform(whatsapp_channel, attempt = 1)
  return if attempt == 1 && whatsapp_channel.provider_connection['connection'] != 'close'
  return if attempt > 1 && whatsapp_channel.provider_connection['connection'] != 'connecting'

  if attempt > 3
    whatsapp_channel.update_provider_connection!(connection: 'close')
    return
  end

  fetch_and_update_qr_code(whatsapp_channel)
  self.class.set(wait: 30.seconds).perform_later(whatsapp_channel, attempt + 1)
end
```

**What This Provides:**
- Automatic QR code refresh every 30 seconds
- Timeout after 3 attempts (90 seconds)
- Fallback if webhooks fail to deliver QR code

**Whatsmeow Lacks This:**
- Relies entirely on webhook delivery
- No retry mechanism if webhook fails
- No automatic timeout

#### Baileys Setup Includes Webhook Configuration

**BaileysService#setup_channel_provider (line 29-45)**
```ruby
response = HTTParty.post(
  "#{provider_url}/connections/#{whatsapp_channel.phone_number}",
  headers: api_headers,
  body: {
    clientName: DEFAULT_CLIENT_NAME,
    webhookUrl: whatsapp_channel.inbox.callback_webhook_url,  # ← Webhook setup
    webhookVerifyToken: whatsapp_channel.provider_config['webhook_verify_token'],
    includeMedia: false
  }.compact.to_json
)
```

**Whatsmeow Defers This:**
```ruby
# TODO: Webhook configuration
# Whatsmeow API supports webhook delivery for events
# Future enhancement: Configure webhook URL and verify token
# POST /instances/:id/webhook with {url, secret}
```

**Impact:**
- Whatsmeow requires manual/global webhook configuration
- Baileys configures per-channel webhook during setup
- Whatsmeow may have webhook routing issues in multi-tenant scenarios

---

## Compliance Assessment

### ✅ What's Working Well

1. **Instance Lifecycle:**
   - Creates instances properly via API
   - Handles 409 Conflict (already exists)
   - Cleans up on destroy

2. **Connection State Tracking:**
   - Properly tracks `close`, `connecting`, `open` states
   - Updates via webhooks
   - UI responds to state changes

3. **QR Code Delivery:**
   - Receives QR codes via webhooks
   - Converts to data URLs
   - Displays in modal

4. **Error Handling:**
   - Graceful disconnect failures
   - Connection errors surfaced to UI
   - Logs for debugging

### ⚠️ Gaps & Issues

#### 1. No Automatic Instance Setup on Inbox Creation

**Current:**
```ruby
# InboxesController#create
channel = create_channel
@inbox.save!
# provider_connection is null/empty
```

**Should Be:**
```ruby
channel = create_channel
@inbox.save!

# Optionally trigger initial setup
if channel.respond_to?(:setup_channel_provider) && should_auto_setup?
  channel.setup_channel_provider
end
```

**Impact:**
- User must manually open "Link Device" modal
- No immediate connection attempt
- Inconsistent with Baileys behavior

**Recommendation:**
- Add optional `auto_setup` parameter to inbox creation
- Call `setup_channel_provider` after transaction commits
- Handle errors gracefully (don't block inbox creation)

#### 2. No QR Code Polling/Refresh Job

**Current:**
- 100% reliant on webhooks
- No retry mechanism
- No timeout handling

**Should Have:**
```ruby
# Similar to ZapiQrCodeJob
class WhatsmeowQrCodeJob < ApplicationJob
  queue_as :default

  def perform(whatsapp_channel, attempt = 1)
    return if attempt > 3  # Timeout after 90 seconds

    connection = whatsapp_channel.provider_connection['connection']
    return if connection == 'open'  # Already connected

    # Fetch QR code from Whatsmeow API status endpoint
    instance_id = whatsapp_channel.phone_number.delete('+')
    response = HTTParty.get(
      "#{provider_url}/instances/#{instance_id}/qr-code",
      headers: api_headers
    )

    if response.success? && response.parsed_response['qr_code']
      whatsapp_channel.update_provider_connection!(
        connection: 'connecting',
        qr_data_url: "data:image/png;base64,#{response.parsed_response['qr_code']}"
      )
    end

    # Schedule next attempt
    self.class.set(wait: 30.seconds).perform_later(whatsapp_channel, attempt + 1)
  end
end
```

**Benefits:**
- Redundancy if webhooks fail
- QR code refresh (WhatsApp QR expires after 60 seconds)
- User feedback (timeout with error message)

**Recommendation:**
- Implement `WhatsmeowQrCodeJob` (copy from ZapiQrCodeJob pattern)
- Trigger from `setup_channel_provider` after connect call
- Add API endpoint to fetch current QR code

#### 3. Missing Webhook Configuration During Setup

**Current:**
```ruby
# TODO comment in code (line 77-80)
```

**Should Be:**
```ruby
def setup_channel_provider
  # ... existing create + connect logic ...

  # Step 3: Configure webhook
  webhook_response = HTTParty.post(
    "#{provider_url}/instances/#{instance_id}/webhook",
    headers: api_headers,
    body: {
      url: whatsapp_channel.inbox.callback_webhook_url,
      secret: whatsapp_channel.provider_config['webhook_verify_token']
    }.to_json
  )

  unless process_response(webhook_response)
    Rails.logger.warn "Failed to configure webhook (may need global config)"
  end

  true
end
```

**Impact:**
- Whatsmeow API may not know where to send events
- Relies on global webhook configuration
- No per-channel routing

**Recommendation:**
- Implement webhook configuration if Whatsmeow API supports it
- Document global webhook setup requirements
- Add validation check during `validate_provider_config?`

#### 4. No Status Health Check Endpoint

**Current:**
```ruby
def validate_provider_config?
  instance_id = normalized_phone_number
  response = HTTParty.get(
    "#{provider_url}/instances/#{instance_id}/status",
    headers: api_headers
  )

  process_response(response)
end
```

**Gap:**
- Only checks if API responds (boolean)
- Doesn't update `provider_connection` state
- No sync mechanism if webhook missed

**Should Add:**
```ruby
def fetch_connection_status
  instance_id = normalized_phone_number
  response = HTTParty.get(
    "#{provider_url}/instances/#{instance_id}/status",
    headers: api_headers
  )

  return unless process_response(response)

  data = response.parsed_response
  whatsapp_channel.update_provider_connection!(
    connection: data['connection'],
    qr_data_url: extract_qr_data_url(data),
    error: data['error']
  )
end
```

**Use Cases:**
- Manual refresh button in UI
- Periodic sync job (every 5 minutes)
- Recovery after webhook delivery failure

**Recommendation:**
- Add `fetch_connection_status` method
- Expose via controller endpoint
- Add UI "Refresh" button

#### 5. Instance Creation Not Idempotent in All Scenarios

**Current:**
```ruby
unless [200, 201, 409].include?(create_instance_response.code)
  raise ProviderUnavailableError, 'Failed to create Whatsmeow instance'
end
```

**Edge Case:**
If instance exists but is in invalid state (e.g., crashed), 409 response may mask underlying issue.

**Recommendation:**
- Check instance status after 409 Conflict
- Attempt recovery/reconnect if needed
- Surface errors to user

---

## Architectural Questions

### 1. When Should Instance Be Created?

**Option A: On Inbox Creation (Proactive)**
```ruby
# InboxesController#create
after_transaction do
  SetupWhatsmeowInstanceJob.perform_later(@inbox.channel)
end
```

**Pros:**
- Immediate readiness
- User doesn't wait
- Consistent state

**Cons:**
- May waste resources if user never uses inbox
- Harder to surface setup errors
- Requires background job

**Option B: On First Access (Lazy)**
```ruby
# Current approach: WhatsappLinkDeviceModal.vue onMounted
if (!connection || connection === 'close') {
  setup();
}
```

**Pros:**
- Only creates when needed
- Errors surfaced to user immediately
- No background job complexity

**Cons:**
- User waits for setup
- Inconsistent state (inbox exists, no instance)
- Confusing UX

**Recommendation: Hybrid Approach**
```ruby
# InboxesController#create
after_transaction do
  if params[:auto_setup] != false  # Default: true
    SetupWhatsmeowInstanceJob.perform_later(@inbox.channel)
  end
end
```

- Default to proactive setup
- Allow opt-out via parameter
- Background job for async handling
- Frontend polls for status

### 2. How Should QR Codes Be Refreshed?

**Option A: Webhook-Only (Current)**
- Simple, no polling
- Efficient
- **Risk:** Webhook delivery failure = stuck state

**Option B: Polling Job (Like Baileys/Zapi)**
- Redundant delivery
- Handles failures
- **Cost:** API calls every 30s

**Option C: Hybrid**
- Primary: Webhooks
- Fallback: Polling job (3 attempts, 30s interval)
- Best of both worlds

**Recommendation: Option C (Hybrid)**
```ruby
# After setup_channel_provider
if response.success?
  WhatsmeowQrCodeJob.set(wait: 30.seconds).perform_later(channel, 1)
end
```

### 3. Should Instance Status Be Synced Periodically?

**Current:**
- Only updated via webhooks
- No recovery mechanism

**Proposed:**
- Periodic sync job (every 5-10 minutes)
- Only for `connecting` or `open` states
- Detect disconnections missed by webhooks

```ruby
class SyncWhatsmeowInstanceStatusJob < ApplicationJob
  def perform
    Channel::Whatsapp.where(provider: 'whatsmeow').find_each do |channel|
      connection = channel.provider_connection['connection']
      next if connection == 'close'  # Don't waste API calls

      channel.provider_service.fetch_connection_status
    rescue StandardError => e
      Rails.logger.error "Failed to sync Whatsmeow status",
                         channel_id: channel.id,
                         error: e.message
    end
  end
end
```

**Recommendation:**
- Add periodic sync (10 minute interval)
- Scope to active instances only
- Handle errors gracefully

---

## Recommendations Summary

### High Priority (MVP Blockers)

1. **Implement QR Code Polling Job**
   - Copy pattern from `ZapiQrCodeJob`
   - 3 attempts, 30s intervals
   - Timeout to `close` after 90s
   - **Files:** `app/jobs/channels/whatsapp/whatsmeow_qr_code_job.rb`

2. **Add Webhook Configuration**
   - Remove TODO comment
   - Implement webhook setup in `setup_channel_provider`
   - Document global webhook fallback
   - **Files:** `app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb:77-80`

3. **Add Status Refresh Endpoint**
   - Implement `fetch_connection_status` method
   - Expose via controller
   - Add UI refresh button
   - **Files:**
     - `app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb`
     - `app/controllers/api/v1/accounts/inboxes_controller.rb`
     - `app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue`

### Medium Priority (UX Improvements)

4. **Automatic Instance Setup**
   - Add `auto_setup` parameter to inbox creation
   - Background job for async setup
   - Poll for status in frontend
   - **Files:**
     - `app/controllers/api/v1/accounts/inboxes_controller.rb`
     - `app/jobs/channels/whatsapp/setup_whatsmeow_instance_job.rb` (new)

5. **Connection State Recovery**
   - Handle 409 Conflict with status check
   - Attempt reconnect if instance in bad state
   - Surface errors to UI
   - **Files:** `app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb:49-83`

### Low Priority (Operational)

6. **Periodic Status Sync**
   - Background job every 10 minutes
   - Only for active instances
   - Detect webhook delivery failures
   - **Files:** `app/jobs/channels/whatsapp/sync_whatsmeow_instance_status_job.rb` (new)

7. **Instance Cleanup Job**
   - Periodic cleanup of orphaned instances
   - Match instances on Whatsmeow API vs database
   - Delete unused instances
   - **Files:** `app/jobs/channels/whatsapp/cleanup_whatsmeow_instances_job.rb` (new)

---

## Code Examples

### Example 1: QR Code Polling Job

```ruby
# app/jobs/channels/whatsapp/whatsmeow_qr_code_job.rb
class Channels::Whatsapp::WhatsmeowQrCodeJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 3
  RETRY_INTERVAL = 30.seconds

  def perform(whatsapp_channel, attempt = 1)
    # Early return conditions
    return if attempt == 1 && whatsapp_channel.provider_connection['connection'] != 'close'
    return if attempt > 1 && whatsapp_channel.provider_connection['connection'] != 'connecting'

    # Timeout after max attempts
    if attempt > MAX_ATTEMPTS
      whatsapp_channel.update_provider_connection!(
        connection: 'close',
        error: 'QR code scan timeout'
      )
      return
    end

    # Fetch QR code
    fetch_and_update_qr_code(whatsapp_channel)

    # Schedule next attempt
    self.class.set(wait: RETRY_INTERVAL).perform_later(whatsapp_channel, attempt + 1)
  end

  private

  def fetch_and_update_qr_code(whatsapp_channel)
    service = whatsapp_channel.provider_service
    instance_id = service.send(:normalized_phone_number)

    response = HTTParty.get(
      "#{service.send(:provider_url)}/instances/#{instance_id}/qr-code",
      headers: service.api_headers
    )

    return unless response.success?

    qr_code = response.parsed_response['qr_code']
    return if qr_code.blank?

    # Avoid race condition: don't overwrite 'open' connection
    return if whatsapp_channel.reload.provider_connection['connection'] == 'open'

    qr_data_url = qr_code.start_with?('data:image/') ? qr_code : "data:image/png;base64,#{qr_code}"

    whatsapp_channel.update_provider_connection!(
      connection: 'connecting',
      qr_data_url: qr_data_url
    )
  end
end
```

### Example 2: Status Refresh Method

```ruby
# app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb

def fetch_connection_status
  instance_id = normalized_phone_number

  response = HTTParty.get(
    "#{provider_url}/instances/#{instance_id}/status",
    headers: api_headers
  )

  unless process_response(response)
    Rails.logger.error "Failed to fetch Whatsmeow status",
                       instance_id: instance_id
    return false
  end

  data = response.parsed_response

  connection_data = {
    connection: data['connection'] || 'close',
    qr_data_url: extract_qr_data_url_from_status(data),
    error: data['error']
  }.compact

  whatsapp_channel.update_provider_connection!(connection_data)
  true
end

private

def extract_qr_data_url_from_status(data)
  qr_code = data['qr_code']
  return nil unless qr_code

  qr_code.start_with?('data:image/') ? qr_code : "data:image/png;base64,#{qr_code}"
end
```

### Example 3: Controller Endpoint

```ruby
# app/controllers/api/v1/accounts/inboxes_controller.rb

def refresh_channel_status
  channel = @inbox.channel

  unless channel.respond_to?(:fetch_connection_status)
    render json: { error: 'Channel does not support status refresh' },
           status: :unprocessable_entity and return
  end

  success = channel.provider_service.fetch_connection_status

  if success
    render json: {
      connection: channel.provider_connection_data
    }, status: :ok
  else
    render json: {
      error: 'Failed to fetch connection status'
    }, status: :service_unavailable
  end
end
```

### Example 4: Frontend Refresh Button

```vue
<!-- app/javascript/dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue -->

<Button
  v-if="connection === 'connecting' && qrDataUrl"
  ghost
  :is-loading="loading"
  @click="refreshStatus"
>
  {{ $t('INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.REFRESH_QR') }}
</Button>

<script setup>
const refreshStatus = () => {
  loading.value = true;
  store
    .dispatch('inboxes/refreshChannelStatus', props.inbox.id)
    .catch(handleError);
};
</script>
```

---

## Conclusion

The Whatsmeow integration is **functionally compliant** but has gaps compared to Baileys/Zapi providers:

1. ✅ **Instance creation/deletion works correctly**
2. ✅ **Connection state tracking via webhooks functional**
3. ✅ **QR code delivery via webhooks works**
4. ⚠️ **Missing QR code polling job** (redundancy)
5. ⚠️ **Missing webhook configuration** (per-channel routing)
6. ⚠️ **Missing status refresh mechanism** (recovery)

**To achieve full compliance:**
- Implement QR code polling job (high priority)
- Add webhook configuration (high priority)
- Add status refresh endpoint (medium priority)
- Consider automatic instance setup (medium priority)

**Current state is production-ready** if:
- Webhooks are reliable
- Users understand manual "Link Device" step
- Support team can manually recover from stuck states

**Recommended improvements** for production robustness:
- Add redundancy (polling job)
- Add recovery mechanisms (status refresh)
- Improve UX (automatic setup)
