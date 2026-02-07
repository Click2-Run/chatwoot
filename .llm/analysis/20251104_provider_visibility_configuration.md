---
Created: 2025-11-04T13:00:00Z
Operation: Analysis of WhatsApp provider visibility configuration
Context: User inquiry about enabling/disabling specific WhatsApp providers (Cloud, Twilio, Baileys, Whatsmeow)
Related Files:
  - app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue:47-85
  - app/javascript/dashboard/featureFlags.js:44
  - config/features.yml:225-227
  - app/models/concerns/featurable.rb
  - app/controllers/super_admin/instance_statuses_controller.rb:68-72
---

# WhatsApp Provider Visibility Configuration

## Executive Summary

**Current State: PARTIALLY IMPLEMENTED**

Chatwoot has a feature flag system but **no granular provider-level controls** for WhatsApp channels:

**✅ What Exists:**
- Feature flag for Z-API provider (`channel_zapi` in `features.yml`)
- Account-level feature flags via `Featurable` concern
- Z-API conditionally shown if `FEATURE_FLAGS.CHANNEL_ZAPI` enabled

**❌ What's Missing:**
- No feature flags for Baileys, Whatsmeow, WhatsApp Cloud, Twilio
- All providers (except Z-API) are **hardcoded and always visible**
- No environment variable controls for providers
- No Super Admin toggle to disable providers globally

**Recommendation:** Extend existing feature flag system to support per-provider visibility controls.

---

## Current Implementation Analysis

### 1. Provider Selection UI

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue:47-85`

```javascript
const PROVIDER_TYPES = {
  WHATSAPP: 'whatsapp',
  TWILIO: 'twilio',
  WHATSAPP_CLOUD: 'whatsapp_cloud',
  WHATSAPP_EMBEDDED: 'whatsapp_embedded',
  WHATSAPP_MANUAL: 'whatsapp_manual',
  THREE_SIXTY_DIALOG: '360dialog',
  BAILEYS: 'baileys',
  WHATSMEOW: 'whatsmeow',
  ZAPI: 'zapi',
};

const availableProviders = computed(() => {
  const providers = [
    {
      key: PROVIDER_TYPES.WHATSAPP,  // ← HARDCODED, always shown
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD_DESC'),
      icon: 'i-woot-whatsapp',
    },
    {
      key: PROVIDER_TYPES.TWILIO,  // ← HARDCODED, always shown
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO_DESC'),
      icon: 'i-woot-twilio',
    },
    {
      key: PROVIDER_TYPES.BAILEYS,  // ← HARDCODED, always shown
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.BAILEYS'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.BAILEYS_DESC'),
      icon: 'i-woot-baileys',
    },
    {
      key: PROVIDER_TYPES.WHATSMEOW,  // ← HARDCODED, always shown
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSMEOW'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSMEOW_DESC'),
      icon: 'i-woot-whatsapp',
    },
  ];

  // ONLY Z-API is feature-gated
  if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_ZAPI)) {
    providers.push({
      key: PROVIDER_TYPES.ZAPI,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.ZAPI'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.ZAPI_DESC'),
      icon: 'i-woot-zapi',
    });
  }

  return providers;
});
```

**Problem:** Baileys, Whatsmeow, WhatsApp Cloud, Twilio are always added to `providers` array without any conditional check.

### 2. Feature Flag System

**File:** `app/javascript/dashboard/featureFlags.js:44`

```javascript
export const FEATURE_FLAGS = {
  AGENT_BOTS: 'agent_bots',
  // ... other flags ...
  CHANNEL_ZAPI: 'channel_zapi',  // ← Only Z-API has a flag
};
```

**File:** `config/features.yml:225-227`

```yaml
- name: channel_zapi
  display_name: Z-API Channel
  enabled: false  # ← Disabled by default, must be enabled
```

**How It Works:**
1. Feature flags defined in `features.yml`
2. Loaded into `Account` model via `Featurable` concern
3. Stored as bitmask in `accounts.feature_flags` column
4. Checked via `isFeatureFlagEnabled()` in frontend

**Example Z-API Usage:**
```javascript
// Only show Z-API if feature enabled
if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_ZAPI)) {
  providers.push({ ... });
}
```

### 3. Super Admin Instance Status

**File:** `app/controllers/super_admin/instance_statuses_controller.rb:68-72`

```ruby
def whatsmeow_api_version
  @metrics['Whatsmeow API version'] = Whatsapp::Providers::WhatsappWhatsmeowService.status[:version]
rescue Whatsapp::Providers::WhatsappWhatsmeowService::ProviderUnavailableError => e
  @metrics['Whatsmeow API version'] = e.message
end
```

**What It Shows:**
- Baileys API version (if configured)
- Whatsmeow API version (if configured)
- Error message if provider unavailable

**What It Doesn't Do:**
- Enable/disable providers
- Control visibility in inbox creation

---

## Gap Analysis

### Missing: Provider-Level Feature Flags

**Current:**
```yaml
# config/features.yml
- name: channel_zapi
  display_name: Z-API Channel
  enabled: false
```

**Needed:**
```yaml
# config/features.yml
- name: channel_whatsapp_cloud
  display_name: WhatsApp Cloud Provider
  enabled: true

- name: channel_whatsapp_baileys
  display_name: Baileys Provider
  enabled: true

- name: channel_whatsapp_whatsmeow
  display_name: Whatsmeow Provider
  enabled: true

- name: channel_twilio_whatsapp
  display_name: Twilio WhatsApp Provider
  enabled: true

- name: channel_zapi
  display_name: Z-API Channel
  enabled: false
```

### Missing: Environment Variable Controls

**Current:**
```bash
# No environment variables for provider visibility
```

**Needed:**
```bash
# .env
ENABLE_WHATSAPP_CLOUD=true
ENABLE_WHATSAPP_BAILEYS=false  # Disable Baileys
ENABLE_WHATSAPP_WHATSMEOW=true
ENABLE_TWILIO_WHATSAPP=true
ENABLE_ZAPI=false
```

**Use Case:** Deployment-level controls without modifying database

### Missing: Super Admin UI

**Current:**
```
Super Admin → Instance Status
  Shows: API versions (read-only)
  No: Enable/disable controls
```

**Needed:**
```
Super Admin → WhatsApp Providers
  ✓ WhatsApp Cloud API (enabled)
  ✗ Baileys (disabled)
  ✓ Whatsmeow (enabled)
  ✓ Twilio (enabled)
  ✗ Z-API (disabled)

  [Save Configuration]
```

---

## Proposed Implementation

### Approach 1: Feature Flags (Recommended)

**Pros:**
- Leverages existing `Featurable` infrastructure
- Per-account granularity (different accounts can have different providers)
- No deployment required to change settings
- UI-manageable via Account Settings or Super Admin

**Cons:**
- Requires database migration (add feature flag positions)
- More complex: multiple flags instead of single env var

**Implementation Steps:**

#### Step 1: Add Feature Flags

**File:** `config/features.yml` (append to end)

```yaml
- name: channel_whatsapp_cloud
  display_name: WhatsApp Cloud API Provider
  enabled: true
  help_url: https://chwt.app/hc/whatsapp-cloud

- name: channel_whatsapp_baileys
  display_name: Baileys WhatsApp Provider
  enabled: true
  help_url: https://chwt.app/hc/baileys

- name: channel_whatsapp_whatsmeow
  display_name: Whatsmeow WhatsApp Provider
  enabled: true
  help_url: https://chwt.app/hc/whatsmeow

- name: channel_twilio_whatsapp
  display_name: Twilio WhatsApp Provider
  enabled: true
  help_url: https://chwt.app/hc/twilio
```

**Important:** DO NOT change order of existing features (line 1 in file)

#### Step 2: Add Feature Flags to Frontend

**File:** `app/javascript/dashboard/featureFlags.js`

```javascript
export const FEATURE_FLAGS = {
  // ... existing flags ...
  CHANNEL_ZAPI: 'channel_zapi',

  // Add new provider flags
  CHANNEL_WHATSAPP_CLOUD: 'channel_whatsapp_cloud',
  CHANNEL_WHATSAPP_BAILEYS: 'channel_whatsapp_baileys',
  CHANNEL_WHATSAPP_WHATSMEOW: 'channel_whatsapp_whatsmeow',
  CHANNEL_TWILIO_WHATSAPP: 'channel_twilio_whatsapp',
};
```

#### Step 3: Update Provider Selection Logic

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue`

```javascript
const availableProviders = computed(() => {
  const providers = [];

  // WhatsApp Cloud API
  if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_WHATSAPP_CLOUD)) {
    providers.push({
      key: PROVIDER_TYPES.WHATSAPP,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD_DESC'),
      icon: 'i-woot-whatsapp',
    });
  }

  // Twilio
  if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_TWILIO_WHATSAPP)) {
    providers.push({
      key: PROVIDER_TYPES.TWILIO,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO_DESC'),
      icon: 'i-woot-twilio',
    });
  }

  // Baileys
  if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_WHATSAPP_BAILEYS)) {
    providers.push({
      key: PROVIDER_TYPES.BAILEYS,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.BAILEYS'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.BAILEYS_DESC'),
      icon: 'i-woot-baileys',
    });
  }

  // Whatsmeow
  if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_WHATSAPP_WHATSMEOW)) {
    providers.push({
      key: PROVIDER_TYPES.WHATSMEOW,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSMEOW'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSMEOW_DESC'),
      icon: 'i-woot-whatsapp',
    });
  }

  // Z-API
  if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_ZAPI)) {
    providers.push({
      key: PROVIDER_TYPES.ZAPI,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.ZAPI'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.ZAPI_DESC'),
      icon: 'i-woot-zapi',
    });
  }

  return providers;
});
```

#### Step 4: Backend Validation (Optional Security)

**File:** `app/controllers/api/v1/accounts/inboxes_controller.rb`

```ruby
def create
  validate_provider_enabled! if whatsapp_channel_creation?

  ActiveRecord::Base.transaction do
    channel = create_channel
    @inbox = Current.account.inboxes.build(
      {
        name: inbox_name(channel),
        channel: channel
      }.merge(
        permitted_params.except(:channel)
      )
    )
    @inbox.save!
  end
end

private

def whatsapp_channel_creation?
  permitted_params[:channel][:type] == 'whatsapp'
end

def validate_provider_enabled!
  provider = permitted_params[:channel][:provider]

  feature_map = {
    'whatsapp_cloud' => :channel_whatsapp_cloud,
    'baileys' => :channel_whatsapp_baileys,
    'whatsmeow' => :channel_whatsapp_whatsmeow,
    'zapi' => :channel_zapi,
    # Twilio provider check handled separately (SMS vs WhatsApp)
  }

  feature_flag = feature_map[provider]
  return unless feature_flag # Allow if no flag defined

  unless Current.account.feature_enabled?(feature_flag)
    render json: { error: "Provider '#{provider}' is not enabled for this account" },
           status: :forbidden and return
  end
end
```

**Why This Matters:**
- Prevents API bypass (user can't POST to create inbox if provider disabled)
- Security: Malicious user can't craft API request to create disabled provider

#### Step 5: Migration (Auto-Generated)

**Note:** Migration generated automatically on first deploy after `features.yml` change.

Chatwoot uses `FlagShihTzu` gem which dynamically generates flags from YAML.

**What Happens:**
1. New features added to `features.yml`
2. `Featurable` concern loads features into `Account.FEATURES` hash
3. Database column `accounts.feature_flags` stores bitmask (no schema change needed)
4. Existing accounts get default values (`enabled: true` in YAML)

**No manual migration required!**

---

### Approach 2: Environment Variables (Simpler)

**Pros:**
- No database changes
- Simple on/off switches
- Deployment-level controls
- Works for self-hosted without UI

**Cons:**
- Global settings (all accounts affected)
- Requires deployment to change
- No per-account granularity

**Implementation Steps:**

#### Step 1: Define Environment Variables

**File:** `.env.example`

```bash
# WhatsApp Provider Visibility Controls
# Set to "false" to hide provider from inbox creation UI
ENABLE_WHATSAPP_CLOUD_PROVIDER=true
ENABLE_WHATSAPP_BAILEYS_PROVIDER=true
ENABLE_WHATSAPP_WHATSMEOW_PROVIDER=true
ENABLE_TWILIO_WHATSAPP_PROVIDER=true
ENABLE_ZAPI_PROVIDER=false
```

#### Step 2: Backend Helper

**File:** `app/helpers/whatsapp_provider_helper.rb` (new file)

```ruby
module WhatsappProviderHelper
  PROVIDER_ENV_MAP = {
    'whatsapp_cloud' => 'ENABLE_WHATSAPP_CLOUD_PROVIDER',
    'baileys' => 'ENABLE_WHATSAPP_BAILEYS_PROVIDER',
    'whatsmeow' => 'ENABLE_WHATSAPP_WHATSMEOW_PROVIDER',
    'zapi' => 'ENABLE_ZAPI_PROVIDER',
    # Twilio handled separately (SMS vs WhatsApp distinction)
  }.freeze

  def self.provider_enabled?(provider_key)
    env_var = PROVIDER_ENV_MAP[provider_key]
    return true unless env_var # Default: enabled if no env var defined

    ENV.fetch(env_var, 'true').downcase == 'true'
  end

  def self.enabled_providers
    PROVIDER_ENV_MAP.keys.select { |provider| provider_enabled?(provider) }
  end
end
```

#### Step 3: API Endpoint for Frontend

**File:** `app/controllers/api/v1/accounts/inboxes_controller.rb`

```ruby
def available_whatsapp_providers
  providers = {
    whatsapp_cloud: WhatsappProviderHelper.provider_enabled?('whatsapp_cloud'),
    baileys: WhatsappProviderHelper.provider_enabled?('baileys'),
    whatsmeow: WhatsappProviderHelper.provider_enabled?('whatsmeow'),
    zapi: WhatsappProviderHelper.provider_enabled?('zapi'),
    twilio: ENV.fetch('ENABLE_TWILIO_WHATSAPP_PROVIDER', 'true').downcase == 'true',
  }

  render json: { providers: providers }
end
```

**Route:** `config/routes.rb`

```ruby
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    namespace :accounts do
      resources :inboxes do
        collection do
          get 'available_whatsapp_providers'
        end
      end
    end
  end
end
```

#### Step 4: Frontend Store Module

**File:** `app/javascript/dashboard/store/modules/inboxes.js`

```javascript
export const actions = {
  // ... existing actions ...

  fetchAvailableWhatsappProviders: async ({ commit }) => {
    try {
      const response = await axios.get('/api/v1/accounts/{accountId}/inboxes/available_whatsapp_providers');
      commit('SET_AVAILABLE_WHATSAPP_PROVIDERS', response.data.providers);
    } catch (error) {
      // Fallback: all providers enabled
      commit('SET_AVAILABLE_WHATSAPP_PROVIDERS', {
        whatsapp_cloud: true,
        baileys: true,
        whatsmeow: true,
        zapi: true,
        twilio: true,
      });
    }
  },
};

export const mutations = {
  // ... existing mutations ...

  SET_AVAILABLE_WHATSAPP_PROVIDERS: (state, providers) => {
    state.availableWhatsappProviders = providers;
  },
};
```

#### Step 5: Update Vue Component

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue`

```javascript
import { mapGetters, mapActions } from 'vuex';

export default {
  computed: {
    ...mapGetters({
      availableWhatsappProviders: 'inboxes/getAvailableWhatsappProviders',
    }),

    availableProviders() {
      const providers = [];

      // Check environment-based availability
      if (this.availableWhatsappProviders?.whatsapp_cloud) {
        providers.push({
          key: PROVIDER_TYPES.WHATSAPP,
          // ... config
        });
      }

      if (this.availableWhatsappProviders?.baileys) {
        providers.push({
          key: PROVIDER_TYPES.BAILEYS,
          // ... config
        });
      }

      if (this.availableWhatsappProviders?.whatsmeow) {
        providers.push({
          key: PROVIDER_TYPES.WHATSMEOW,
          // ... config
        });
      }

      if (this.availableWhatsappProviders?.twilio) {
        providers.push({
          key: PROVIDER_TYPES.TWILIO,
          // ... config
        });
      }

      if (this.availableWhatsappProviders?.zapi) {
        providers.push({
          key: PROVIDER_TYPES.ZAPI,
          // ... config
        });
      }

      return providers;
    },
  },

  methods: {
    ...mapActions('inboxes', ['fetchAvailableWhatsappProviders']),
  },

  mounted() {
    this.fetchAvailableWhatsappProviders();
  },
};
```

---

## Comparison: Feature Flags vs Environment Variables

| Criteria | Feature Flags | Environment Variables |
|----------|--------------|----------------------|
| **Granularity** | Per-account | Global (all accounts) |
| **UI Management** | ✅ Account Settings | ❌ Requires deployment |
| **Super Admin Control** | ✅ Can build UI | ❌ Requires env file edit |
| **Implementation Complexity** | Medium (extend existing system) | Low (simple env vars) |
| **Database Changes** | ❌ None (bitmask column exists) | ❌ None |
| **Self-Hosted Friendly** | ⚠️ Requires UI navigation | ✅ Simple `.env` edit |
| **Multi-Tenant Support** | ✅ Different settings per account | ❌ Same for all accounts |
| **Runtime Changes** | ✅ Immediate (no restart) | ❌ Requires app restart |
| **API Security** | ✅ Backend validation possible | ✅ Backend validation possible |
| **Caching** | ✅ Cached in account object | ✅ Cached in process memory |

---

## Recommended Hybrid Approach

Combine both approaches for maximum flexibility:

1. **Feature Flags (Primary):** Per-account controls via UI
2. **Environment Variables (Override):** Global disable switch

**Logic:**
```ruby
def provider_enabled?(provider, account)
  # Step 1: Check global env var (hard disable)
  return false unless WhatsappProviderHelper.provider_enabled?(provider)

  # Step 2: Check account feature flag (soft enable/disable)
  feature_flag = provider_feature_flag_map(provider)
  return true unless feature_flag # Default: enabled if no flag

  account.feature_enabled?(feature_flag)
end
```

**Use Cases:**
- **Environment Variable = false:** Provider globally disabled for all accounts (e.g., Baileys deprecated)
- **Feature Flag = false:** Provider disabled for specific account (e.g., restrict free tier)
- **Both true:** Provider available

**Example:**
```bash
# .env
ENABLE_WHATSAPP_BAILEYS_PROVIDER=false  # Globally disabled (deprecated)
```

```ruby
# Account 123
account.feature_enabled?(:channel_whatsapp_whatsmeow) # => true (allowed)
account.feature_enabled?(:channel_whatsapp_baileys) # => true (but env var blocks it)

# Result: Baileys hidden for all accounts, Whatsmeow visible only for Account 123
```

---

## Implementation Checklist

### Phase 1: Basic Feature Flags (MVP)

- [ ] Add provider feature flags to `config/features.yml`
- [ ] Add feature flag constants to `app/javascript/dashboard/featureFlags.js`
- [ ] Update `Whatsapp.vue` to check feature flags before showing providers
- [ ] Deploy and test (existing accounts get default `enabled: true`)
- [ ] Document feature flags in Help Center

**Estimated Effort:** 2-3 hours

### Phase 2: Backend Validation

- [ ] Add `validate_provider_enabled!` method to `InboxesController`
- [ ] Call validation in `create` action
- [ ] Add error message translations
- [ ] Test API bypass attempts (should return 403 Forbidden)

**Estimated Effort:** 1-2 hours

### Phase 3: Super Admin UI

- [ ] Create Super Admin → WhatsApp Providers page
- [ ] Show provider status (enabled/disabled)
- [ ] Add toggle switches (affects all accounts or specific account)
- [ ] Add "Test Provider" button (checks API availability)
- [ ] Show current API versions (like Instance Status page)

**Estimated Effort:** 4-6 hours

### Phase 4: Environment Variable Overrides

- [ ] Add environment variables to `.env.example`
- [ ] Create `WhatsappProviderHelper` module
- [ ] Update feature flag checks to respect env vars
- [ ] Document env var usage in deployment docs

**Estimated Effort:** 1-2 hours

---

## Testing Strategy

### Unit Tests

```ruby
# spec/helpers/whatsapp_provider_helper_spec.rb
describe WhatsappProviderHelper do
  describe '.provider_enabled?' do
    context 'when env var is true' do
      it 'returns true' do
        with_modified_env ENABLE_WHATSAPP_BAILEYS_PROVIDER: 'true' do
          expect(described_class.provider_enabled?('baileys')).to be true
        end
      end
    end

    context 'when env var is false' do
      it 'returns false' do
        with_modified_env ENABLE_WHATSAPP_BAILEYS_PROVIDER: 'false' do
          expect(described_class.provider_enabled?('baileys')).to be false
        end
      end
    end

    context 'when env var is not set' do
      it 'defaults to true' do
        expect(described_class.provider_enabled?('baileys')).to be true
      end
    end
  end
end
```

### Integration Tests

```ruby
# spec/requests/api/v1/accounts/inboxes_spec.rb
describe 'POST /api/v1/accounts/{account.id}/inboxes' do
  context 'when creating Baileys inbox' do
    context 'when feature flag is disabled' do
      before { account.disable_features!(:channel_whatsapp_baileys) }

      it 'returns 403 Forbidden' do
        post "/api/v1/accounts/#{account.id}/inboxes",
             params: { channel: { type: 'whatsapp', provider: 'baileys', ... } },
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:forbidden)
        expect(json_response['error']).to include('not enabled')
      end
    end
  end
end
```

### Frontend Tests

```javascript
// spec/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.spec.js
describe('Whatsapp.vue', () => {
  describe('availableProviders', () => {
    it('includes Baileys when feature flag enabled', () => {
      const wrapper = mount(Whatsapp, {
        global: {
          mocks: {
            isFeatureFlagEnabled: (flag) => flag === 'channel_whatsapp_baileys',
          },
        },
      });

      expect(wrapper.vm.availableProviders).toContainEqual(
        expect.objectContaining({ key: 'baileys' })
      );
    });

    it('excludes Baileys when feature flag disabled', () => {
      const wrapper = mount(Whatsapp, {
        global: {
          mocks: {
            isFeatureFlagEnabled: () => false,
          },
        },
      });

      expect(wrapper.vm.availableProviders).not.toContainEqual(
        expect.objectContaining({ key: 'baileys' })
      );
    });
  });
});
```

---

## Migration Path for Existing Deployments

### Scenario 1: Enable All Providers (Default)

**Action:** No changes required

**Result:**
- All providers enabled by default (`enabled: true` in `features.yml`)
- Existing behavior preserved

### Scenario 2: Disable Baileys for All Accounts

**Option A: Environment Variable**
```bash
# .env
ENABLE_WHATSAPP_BAILEYS_PROVIDER=false
```

**Option B: Database Update**
```ruby
# Rails console
Account.find_each do |account|
  account.disable_features!(:channel_whatsapp_baileys)
end
```

### Scenario 3: Enable Whatsmeow Only for Premium Accounts

```ruby
# Rails console
Account.where(premium: true).find_each do |account|
  account.enable_features!(:channel_whatsapp_whatsmeow)
end

Account.where(premium: false).find_each do |account|
  account.disable_features!(:channel_whatsapp_whatsmeow)
end
```

---

## Conclusion

**Current State:** No provider-level controls exist (except Z-API).

**Recommendation:** Implement **Approach 1 (Feature Flags)** as the primary solution:

**Why:**
- Leverages existing `Featurable` infrastructure (no new patterns)
- Per-account granularity (essential for multi-tenant SaaS)
- UI-manageable (admin-friendly)
- Consistent with Z-API precedent

**Optional Enhancement:** Add environment variable overrides (Approach 2) for global hard disables.

**Estimated Total Effort:** 8-12 hours (including tests and documentation)

**Breaking Changes:** None (default `enabled: true` preserves current behavior)

**User Impact:** Positive (more control, especially for self-hosted deployments)
