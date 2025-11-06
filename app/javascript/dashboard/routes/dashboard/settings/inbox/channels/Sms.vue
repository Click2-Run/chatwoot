<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import PageHeader from '../../SettingsSubPageHeader.vue';
import BandwidthSms from './BandwidthSms.vue';
import Twilio from './Twilio.vue';
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
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="$t('INBOX_MGMT.ADD.SMS.TITLE')"
      :header-content="$t('INBOX_MGMT.ADD.SMS.DESC')"
    />
    <div v-if="availableProviders.length > 0" class="flex-shrink-0 flex-grow-0">
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
  </div>
</template>
