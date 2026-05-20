---
Created: 2025-11-04T17:57:00Z
Operation: Feature Flag Implementation for Twilio and Bandwidth Providers
Context: User requested ability to enable/disable Twilio (WhatsApp and SMS) and Bandwidth (SMS) providers per account
Related Files:
  - config/features.yml
  - app/javascript/dashboard/featureFlags.js
  - app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue
  - app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Sms.vue
  - app/javascript/dashboard/i18n/locale/en/inboxMgmt.json
---

# Twilio and Bandwidth Feature Flags Implementation

## Summary

Implemented per-account feature flags for Twilio (WhatsApp and SMS) and Bandwidth (SMS) providers, allowing administrators to control which providers are visible during inbox creation.

## Implementation Details

### 1. Feature Flag Definitions (config/features.yml)

Added three new feature flags with default enabled state:

```yaml
- name: channel_twilio_sms
  display_name: Twilio SMS Provider
  enabled: true
  help_url: https://chwt.app/hc/twilio-sms

- name: channel_twilio_whatsapp
  display_name: Twilio WhatsApp Provider
  enabled: true
  help_url: https://chwt.app/hc/twilio-whatsapp

- name: channel_bandwidth_sms
  display_name: Bandwidth SMS Provider
  enabled: true
  help_url: https://chwt.app/hc/bandwidth
```

**Why default enabled: true?**
- Maintains backward compatibility
- New accounts inherit these defaults
- Existing accounts keep their current flag values
- Prevents breaking existing deployments

### 2. Frontend Constants (app/javascript/dashboard/featureFlags.js)

Added three new constants to the FEATURE_FLAGS object:

```javascript
export const FEATURE_FLAGS = {
  // ... existing flags
  CHANNEL_TWILIO_SMS: 'channel_twilio_sms',
  CHANNEL_TWILIO_WHATSAPP: 'channel_twilio_whatsapp',
  CHANNEL_BANDWIDTH_SMS: 'channel_bandwidth_sms',
};
```

### 3. WhatsApp Provider Selection (Whatsapp.vue)

**Before:** Twilio was always visible in provider list

**After:** Twilio conditionally shown based on feature flag

```javascript
const availableProviders = computed(() => {
  const providers = [
    {
      key: PROVIDER_TYPES.WHATSAPP,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD_DESC'),
      icon: 'i-woot-whatsapp',
    },
  ];

  // Twilio provider - feature flag controlled
  if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_TWILIO_WHATSAPP)) {
    providers.push({
      key: PROVIDER_TYPES.TWILIO,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO_DESC'),
      icon: 'i-woot-twilio',
    });
  }

  // ... Baileys, Whatsmeow, Z-API also feature-flag controlled
  return providers;
});
```

**Key Changes:**
- Only WhatsApp Cloud (Meta) is always shown
- Twilio wrapped in `isFeatureFlagEnabled()` check
- Follows same pattern as Baileys, Whatsmeow, Z-API

### 4. SMS Provider Selection (Sms.vue)

**Major Refactor:** Converted from Options API to Composition API with feature flag support

**Before:** Hardcoded dropdown with both providers always visible

```vue
<script>
export default {
  data() {
    return {
      provider: 'twilio', // Always defaulted to Twilio
    };
  },
};
</script>

<template>
  <select v-model="provider">
    <option value="twilio">Twilio</option>
    <option value="360dialog">Bandwidth</option>
  </select>
  <Twilio v-if="provider === 'twilio'" type="sms" />
  <BandwidthSms v-else />
</template>
```

**After:** Dynamic provider list based on feature flags

```vue
<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const { t } = useI18n();
const { isFeatureFlagEnabled } = usePolicy();

const availableProviders = computed(() => {
  const providers = [];

  if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_TWILIO_SMS)) {
    providers.push({
      value: 'twilio',
      label: t('INBOX_MGMT.ADD.SMS.PROVIDERS.TWILIO'),
    });
  }

  if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_BANDWIDTH_SMS)) {
    providers.push({
      value: 'bandwidth',
      label: t('INBOX_MGMT.ADD.SMS.PROVIDERS.BANDWIDTH'),
    });
  }

  return providers;
});

// Set default provider to first available, or empty string if none
const provider = ref(availableProviders.value[0]?.value || '');
</script>

<template>
  <div v-if="availableProviders.length > 0" class="flex-shrink-0 flex-grow-0">
    <!-- Only show dropdown if more than one provider -->
    <label v-if="availableProviders.length > 1">
      {{ $t('INBOX_MGMT.ADD.SMS.PROVIDERS.LABEL') }}
      <select v-model="provider">
        <option
          v-for="providerOption in availableProviders"
          :key="providerOption.value"
          :value="providerOption.value"
        >
          {{ providerOption.label }}
        </option>
      </select>
    </label>
    <Twilio v-if="provider === 'twilio'" type="sms" />
    <BandwidthSms v-else-if="provider === 'bandwidth'" />
  </div>
  <div v-else class="text-center py-8 text-slate-11">
    {{ $t('INBOX_MGMT.ADD.SMS.NO_PROVIDERS_AVAILABLE') }}
  </div>
</template>
```

**Key Improvements:**
1. **Composition API**: Follows project guidelines (always use `<script setup>`)
2. **Dynamic Provider List**: Conditionally includes providers based on flags
3. **Smart Defaults**: First available provider becomes default
4. **Empty State**: Shows message when no providers enabled
5. **Conditional Dropdown**: Hides dropdown if only one provider (better UX)

### 5. Internationalization (inboxMgmt.json)

Added new translation key for empty state:

```json
"SMS": {
  "TITLE": "SMS Channel",
  "DESC": "Start supporting your customers via SMS.",
  "NO_PROVIDERS_AVAILABLE": "No SMS providers are currently enabled for this account. Please contact your administrator.",
  "PROVIDERS": {
    "LABEL": "API Provider",
    "TWILIO": "Twilio",
    "BANDWIDTH": "Bandwidth"
  },
  // ...
}
```

## User Experience Scenarios

### Scenario 1: All Flags Enabled (Default)
**State:** All 3 flags enabled (default for new accounts)
**WhatsApp Providers:** WhatsApp Cloud, Twilio, Baileys, Whatsmeow, Z-API (if enabled)
**SMS Providers:** Twilio, Bandwidth dropdown

### Scenario 2: Twilio Disabled Globally
**Admin Action:**
```ruby
Account.find_each do |account|
  account.disable_features!(:channel_twilio_sms, :channel_twilio_whatsapp)
end
```

**Result:**
- WhatsApp: Only WhatsApp Cloud, Baileys, Whatsmeow, Z-API visible
- SMS: Only Bandwidth shown (no dropdown)

### Scenario 3: Bandwidth Disabled, Twilio Enabled
**Admin Action:**
```ruby
account = Account.find(123)
account.disable_features!(:channel_bandwidth_sms)
```

**Result:**
- WhatsApp: Twilio still visible
- SMS: Only Twilio shown (no dropdown)

### Scenario 4: All SMS Providers Disabled
**Admin Action:**
```ruby
account.disable_features!(:channel_twilio_sms, :channel_bandwidth_sms)
```

**Result:**
- SMS channel creation page shows: "No SMS providers are currently enabled for this account. Please contact your administrator."
- WhatsApp channel unaffected (uses separate flag)

### Scenario 5: Per-Account Customization
**Use Case:** SaaS deployment where some accounts want specific providers

```ruby
# Account A: Only Meta WhatsApp + Twilio SMS
account_a = Account.find(1)
account_a.disable_features!(
  :channel_whatsapp_baileys,
  :channel_whatsapp_whatsmeow,
  :channel_zapi,
  :channel_bandwidth_sms
)

# Account B: Only open-source providers
account_b = Account.find(2)
account_b.disable_features!(
  :channel_twilio_whatsapp,
  :channel_twilio_sms,
  :channel_bandwidth_sms,
  :channel_zapi
)
# Enables: WhatsApp Cloud, Baileys, Whatsmeow
```

## Feature Flag Management

### Check Current State
```ruby
account = Account.find(123)

# Check individual flags
account.feature_enabled?(:channel_twilio_sms)        # => true/false
account.feature_enabled?(:channel_twilio_whatsapp)   # => true/false
account.feature_enabled?(:channel_bandwidth_sms)     # => true/false

# List all enabled features
account.enabled_features
# => [:channel_email, :channel_twilio_sms, :channel_twilio_whatsapp, ...]
```

### Enable Flags
```ruby
# Enable single flag
account.enable_features!(:channel_twilio_sms)

# Enable multiple flags
account.enable_features!(:channel_twilio_sms, :channel_bandwidth_sms)
```

### Disable Flags
```ruby
# Disable single flag
account.disable_features!(:channel_twilio_whatsapp)

# Disable multiple flags
account.disable_features!(:channel_twilio_sms, :channel_bandwidth_sms)
```

### Bulk Operations
```ruby
# Disable Twilio for all accounts
Account.find_each do |account|
  account.disable_features!(:channel_twilio_sms, :channel_twilio_whatsapp)
end

# Enable Bandwidth for premium accounts
Account.where(plan: 'premium').find_each do |account|
  account.enable_features!(:channel_bandwidth_sms)
end
```

## Testing Guide

### Test 1: Default State (All Enabled)
1. Create new account
2. Navigate to Settings → Inboxes → Add Inbox → WhatsApp
3. **Expected:** See WhatsApp Cloud, Twilio, Baileys, Whatsmeow, Z-API (if enabled)
4. Navigate back → Add Inbox → SMS
5. **Expected:** See dropdown with Twilio and Bandwidth

### Test 2: Disable Twilio WhatsApp
```ruby
rails console
account = Account.find_by(id: YOUR_ACCOUNT_ID)
account.disable_features!(:channel_twilio_whatsapp)
```
6. Refresh WhatsApp provider page
7. **Expected:** Twilio no longer visible in WhatsApp providers
8. Check SMS page
9. **Expected:** SMS still shows both providers (separate flag)

### Test 3: Disable All SMS Providers
```ruby
account.disable_features!(:channel_twilio_sms, :channel_bandwidth_sms)
```
10. Navigate to Add Inbox → SMS
11. **Expected:** See "No SMS providers are currently enabled" message
12. Check WhatsApp page
13. **Expected:** WhatsApp providers unaffected

### Test 4: Re-enable Flags
```ruby
account.enable_features!(:channel_twilio_sms, :channel_twilio_whatsapp)
```
14. Refresh pages
15. **Expected:** Twilio appears in both WhatsApp and SMS

### Test 5: Single Provider Only
```ruby
account.disable_features!(:channel_bandwidth_sms)
```
16. Navigate to SMS page
17. **Expected:** No dropdown shown (only one provider)
18. Twilio form directly visible

## Migration Strategy

### For Existing Installations

**No migration needed!** Feature flags default to `enabled: true`, maintaining current behavior.

**Optional: Disable Providers Globally**
```ruby
# Disable Twilio globally (self-hosted without Twilio account)
Account.find_each do |account|
  account.disable_features!(:channel_twilio_sms, :channel_twilio_whatsapp)
end
```

**Optional: Disable Commercial Providers**
```ruby
# Keep only open-source providers
Account.find_each do |account|
  account.disable_features!(
    :channel_twilio_sms,
    :channel_twilio_whatsapp,
    :channel_bandwidth_sms,
    :channel_zapi
  )
end
# Result: Only WhatsApp Cloud, Baileys, Whatsmeow available
```

### For New Deployments

**Environment-based Defaults:**

If you want to disable certain providers by default, modify `config/features.yml`:

```yaml
# Example: Disable commercial providers by default
- name: channel_twilio_sms
  display_name: Twilio SMS Provider
  enabled: false  # Changed from true
  help_url: https://chwt.app/hc/twilio-sms

- name: channel_bandwidth_sms
  display_name: Bandwidth SMS Provider
  enabled: false  # Changed from true
  help_url: https://chwt.app/hc/bandwidth
```

Then accounts created after this change inherit the new defaults.

## Files Modified

### Backend
- `config/features.yml` - Added 3 new feature flags

### Frontend
- `app/javascript/dashboard/featureFlags.js` - Added 3 new constants
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` - Wrapped Twilio in flag check
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Sms.vue` - Complete refactor to Composition API with feature flags
- `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` - Added NO_PROVIDERS_AVAILABLE key

## Architecture Notes

### Feature Flag System
- **Storage:** Bitmask in `accounts.feature_flags` column (FlagShihTzu gem)
- **Scope:** Per-account (not global)
- **Defaults:** Inherited from `config/features.yml` on account creation
- **Inheritance:** New accounts get defaults, existing accounts unchanged

### Provider Visibility Logic
- **WhatsApp:** Only Meta Cloud is always shown (official provider)
- **SMS:** Empty state if all providers disabled
- **Dropdown:** Hidden if only one provider (better UX)

### Separation of Concerns
- **channel_twilio_whatsapp:** Controls Twilio in WhatsApp provider list
- **channel_twilio_sms:** Controls Twilio in SMS provider list
- Independent flags allow granular control (e.g., disable WhatsApp but keep SMS)

## Benefits

1. **Per-Account Control:** Different accounts can have different providers
2. **Backward Compatible:** Defaults to enabled, no breaking changes
3. **Flexible:** Can disable specific providers per account or globally
4. **User Experience:** Empty states and smart defaults for edge cases
5. **Consistent:** Follows same pattern as Baileys, Whatsmeow, Z-API flags

## Limitations

1. **Runtime Only:** Requires database access (can't disable via env vars alone)
2. **No UI Toggle:** Requires Rails console for now (could add super admin UI later)
3. **No Validation:** Disabling all providers doesn't prevent SMS channel menu item (just shows empty state)

## Future Enhancements

1. **Super Admin UI:** Add toggle switches in admin panel
2. **Channel Menu Filtering:** Hide SMS/WhatsApp menu items if all providers disabled
3. **Environment Variable Override:** Allow env vars to force-disable providers
4. **Audit Logging:** Track who enabled/disabled which providers and when
