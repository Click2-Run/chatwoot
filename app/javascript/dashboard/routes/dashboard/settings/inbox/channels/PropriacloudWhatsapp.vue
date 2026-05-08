<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required, requiredIf } from '@vuelidate/validators';
import { isPhoneE164OrEmpty } from 'shared/helpers/Validators';
import { isValidURL } from '../../../../../helper/URLHelper';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const router = useRouter();
const store = useStore();
const { t } = useI18n();

const inboxName = ref('');
const phoneNumber = ref('');
const apiKey = ref('');
const providerUrl = ref('');
const instanceId = ref('');
const showAdvancedOptions = ref(false);
const markAsRead = ref(true);

const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);

const rules = computed(() => ({
  inboxName: { required },
  phoneNumber: { required, isPhoneE164OrEmpty },
  providerUrl: {
    isValidURL: value => !value || isValidURL(value),
    requiredIf: requiredIf(apiKey),
  },
  apiKey: { requiredIf: requiredIf(providerUrl) },
}));

const v$ = useVuelidate(rules, {
  inboxName,
  phoneNumber,
  providerUrl,
  apiKey,
});

const createChannel = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) {
    return;
  }

  try {
    const providerConfig = {
      mark_as_read: markAsRead.value,
    };

    if (apiKey.value || providerUrl.value) {
      providerConfig.api_key = apiKey.value;
      providerConfig.provider_url = providerUrl.value;
    }

    // Optional: bind this Chatwoot inbox to an EXISTING whatsapp-api
    // instance instead of letting the model auto-generate a fresh UUID.
    // Useful for adopting an instance already paired (e.g. "0119").
    if (instanceId.value && instanceId.value.trim()) {
      providerConfig.instance_id = instanceId.value.trim();
    }

    const whatsappChannel = await store.dispatch('inboxes/createChannel', {
      name: inboxName.value,
      channel: {
        type: 'whatsapp',
        phone_number: phoneNumber.value,
        provider: 'propriacloud',
        provider_config: providerConfig,
      },
    });

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: {
        page: 'new',
        inbox_id: whatsappChannel.id,
      },
    });
  } catch (error) {
    useAlert(
      error.message ||
        t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.API.ERROR_MESSAGE')
    );
  }
};

const setShowAdvancedOptions = () => {
  showAdvancedOptions.value = true;
};
</script>

<template>
  <form class="flex flex-wrap mx-0" @submit.prevent="createChannel()">
    <div class="w-full mb-4">
      <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
        <div class="flex items-start">
          <div class="flex-shrink-0">
            <svg
              class="h-5 w-5 text-blue-400"
              fill="currentColor"
              viewBox="0 0 20 20"
            >
              <path
                fill-rule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                clip-rule="evenodd"
              />
            </svg>
          </div>
          <div class="ml-3">
            <h3 class="text-sm font-medium text-blue-800">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.INFO.TITLE') }}
            </h3>
            <p class="mt-1 text-sm text-blue-700">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.INFO.DESCRIPTION') }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <input
          v-model="phoneNumber"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          @blur="v$.phoneNumber.$touch"
        />
        <span v-if="v$.phoneNumber.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
        </span>
      </label>
    </div>

    <div
      v-if="!showAdvancedOptions"
      class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%] mb-4"
    >
      <NextButton icon="i-lucide-plus" sm link @click="setShowAdvancedOptions">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.ADVANCED_OPTIONS') }}
      </NextButton>
    </div>
    <template v-else>
      <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
        <span class="text-sm text-gray-600">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.ADVANCED_OPTIONS') }}
        </span>
        <label :class="{ error: v$.providerUrl.$error }">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.PROVIDER_URL.LABEL') }}
          <input
            v-model="providerUrl"
            type="text"
            :placeholder="
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.PROVIDER_URL.PLACEHOLDER'
              )
            "
          />
          <span v-if="v$.providerUrl.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.PROVIDER_URL.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
        <label :class="{ error: v$.apiKey.$error }">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.API_KEY.LABEL') }}
          <input
            v-model="apiKey"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.API_KEY.PLACEHOLDER')
            "
          />
          <span v-if="v$.apiKey.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.API_KEY.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
        <label>
          Instance ID (optional)
          <input
            v-model="instanceId"
            type="text"
            placeholder="Adopt an existing whatsapp-api instance, e.g. 0119"
          />
          <span class="message">
            Leave blank to generate a fresh UUID and create a new instance.
          </span>
        </label>
      </div>

      <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
        <label>
          <div class="flex mb-2 items-center">
            <span class="mr-2 text-sm">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.MARK_AS_READ.LABEL') }}
            </span>
            <Switch id="markAsRead" v-model="markAsRead" />
          </div>
        </label>
      </div>
    </template>

    <div class="w-full">
      <NextButton
        :is-loading="uiFlags.isCreating"
        type="submit"
        solid
        blue
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.SUBMIT_BUTTON')"
      />
    </div>
  </form>
</template>
