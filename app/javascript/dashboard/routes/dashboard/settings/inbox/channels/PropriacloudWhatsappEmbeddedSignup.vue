<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import propriacloudChannel from 'dashboard/api/channel/propriacloudChannel';
import NextButton from 'dashboard/components-next/button/Button.vue';

// PropriacloudWhatsappEmbeddedSignup.vue
// --------------------------------------
// Inbox-creation panel for the "Embedded Signup via Propria.Cloud" option.
//
// UX is a Vue port of the React `SignupLinkPanel` used by logged-in users
// inside minha — same three states (form/CTA, plaintext URL with copy +
// countdown, expired) so admins coming from minha to chatwoot do not have
// to re-learn the flow.

const { t } = useI18n();

const tenantKey = ref('');
const inboxName = ref('');
const phoneNumber = ref('');
const markAsRead = ref(true);

const formRules = {
  tenantKey: {
    required,
    is64Hex: value => /^[0-9a-f]{64}$/i.test((value || '').trim()),
  },
  inboxName: { required },
  phoneNumber: { required },
};

const v$ = useVuelidate(formRules, { tenantKey, inboxName, phoneNumber });

const isSubmitting = ref(false);
const signupUrl = ref('');
const sessionId = ref('');
const expiresAt = ref('');
const copied = ref(false);

const now = ref(Date.now());
let countdownTimer = null;

onMounted(() => {
  countdownTimer = setInterval(() => {
    now.value = Date.now();
  }, 1000);
});
onBeforeUnmount(() => {
  if (countdownTimer) clearInterval(countdownTimer);
});

const remainingMs = computed(() => {
  if (!expiresAt.value) return 0;
  return new Date(expiresAt.value).getTime() - now.value;
});
const expired = computed(() => !!expiresAt.value && remainingMs.value <= 0);
const hasPlaintext = computed(() => !!signupUrl.value && !expired.value);

const formatCountdown = ms => {
  if (ms <= 0) return '00:00';
  const total = Math.floor(ms / 1000);
  const m = String(Math.floor(total / 60)).padStart(2, '0');
  const s = String(total % 60).padStart(2, '0');
  return `${m}:${s}`;
};

const startEmbeddedSignup = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  isSubmitting.value = true;
  try {
    const { data } = await propriacloudChannel.startEmbeddedSignup({
      tenantKey: tenantKey.value.trim().toLowerCase(),
      inboxName: inboxName.value.trim(),
      phoneNumber: phoneNumber.value.trim(),
      markAsRead: markAsRead.value,
    });
    if (!data?.signup_url) throw new Error('signup_url missing from response');
    signupUrl.value = data.signup_url;
    sessionId.value = data.minha_session_id || data.session_id || '';
    expiresAt.value = data.expires_at || '';
  } catch (error) {
    const fallback = t(
      'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.GENERIC_ERROR'
    );
    const message = error.response?.data?.error || error.message || fallback;
    const prefix = t(
      'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.ERROR_PREFIX'
    );
    useAlert(`${prefix}: ${message}`);
  } finally {
    isSubmitting.value = false;
  }
};

const handleCopy = async () => {
  if (!signupUrl.value) return;
  try {
    await navigator.clipboard.writeText(signupUrl.value);
    copied.value = true;
    setTimeout(() => {
      copied.value = false;
    }, 2000);
  } catch (e) {
    useAlert(
      t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.GENERIC_ERROR')
    );
  }
};

const openInNewTab = () => {
  if (!signupUrl.value) return;
  window.open(signupUrl.value, '_blank', 'noopener,noreferrer');
};

const resetForm = () => {
  signupUrl.value = '';
  sessionId.value = '';
  expiresAt.value = '';
  copied.value = false;
};
</script>

<template>
  <section>
    <!-- State 1: form (no session yet) -->
    <div v-if="!hasPlaintext && !expired">
      <p class="mb-4 text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.INTRO') }}
      </p>

      <div class="mb-4">
        <label class="block text-sm font-medium text-n-slate-12">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.TENANT_KEY_LABEL'
            )
          }}
        </label>
        <input
          v-model="tenantKey"
          type="password"
          autocomplete="off"
          spellcheck="false"
          class="mt-1 w-full font-mono text-sm rounded-md border border-n-weak bg-n-alpha-1 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-n-brand"
          :placeholder="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.TENANT_KEY_PLACEHOLDER'
            )
          "
        />
        <p v-if="v$.tenantKey.$error" class="mt-1 text-xs text-n-ruby-9">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.TENANT_KEY_ERROR'
            )
          }}
        </p>
      </div>

      <div class="mb-4">
        <label class="block text-sm font-medium text-n-slate-12">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.INBOX_NAME_LABEL'
            )
          }}
        </label>
        <input
          v-model="inboxName"
          type="text"
          class="mt-1 w-full rounded-md border border-n-weak bg-n-alpha-1 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-n-brand"
          :placeholder="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.INBOX_NAME_PLACEHOLDER'
            )
          "
        />
      </div>

      <div class="mb-4">
        <label class="block text-sm font-medium text-n-slate-12">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.PHONE_LABEL'
            )
          }}
        </label>
        <input
          v-model="phoneNumber"
          type="text"
          class="mt-1 w-full rounded-md border border-n-weak bg-n-alpha-1 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-n-brand"
          :placeholder="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.PHONE_PLACEHOLDER'
            )
          "
        />
      </div>

      <div class="mb-6 flex items-center gap-2">
        <input
          id="propriacloud-es-mark-as-read"
          v-model="markAsRead"
          type="checkbox"
        />
        <label
          for="propriacloud-es-mark-as-read"
          class="text-sm text-n-slate-11"
        >
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.MARK_AS_READ_LABEL'
            )
          }}
        </label>
      </div>

      <NextButton
        :is-loading="isSubmitting"
        :disabled="isSubmitting"
        :label="
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.CTA_GENERATE'
          )
        "
        @click="startEmbeddedSignup"
      />
    </div>

    <!-- State 2: plaintext URL just minted -->
    <div
      v-else-if="hasPlaintext"
      class="space-y-3 p-4 bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg"
    >
      <div class="flex items-start gap-3">
        <div class="flex-1 min-w-0">
          <h4 class="font-medium text-blue-800 dark:text-blue-200">
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.PANEL_TITLE'
              )
            }}
          </h4>
          <p class="text-xs text-blue-700 dark:text-blue-300 mt-1">
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.PANEL_HELP'
              )
            }}
          </p>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <code
          class="flex-1 min-w-0 overflow-x-auto px-3 py-2 bg-white dark:bg-n-alpha-2 border border-blue-200 dark:border-blue-700 rounded text-xs font-mono text-blue-900 dark:text-blue-100 whitespace-nowrap"
        >
          {{ signupUrl }}
        </code>
        <NextButton
          variant="outline"
          size="sm"
          :label="
            copied
              ? $t(
                  'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.COPIED'
                )
              : $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.COPY')
          "
          @click="handleCopy"
        />
        <NextButton
          variant="outline"
          size="sm"
          :label="
            $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.OPEN')
          "
          @click="openInNewTab"
        />
      </div>

      <p class="text-[11px] text-blue-600 dark:text-blue-400 italic">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.ONCE_WARNING'
          )
        }}
      </p>

      <div class="flex items-center justify-between text-xs">
        <span
          class="flex items-center gap-1.5 text-blue-700 dark:text-blue-300"
        >
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.EXPIRES_IN'
            )
          }}
          <span class="font-mono font-medium">
            {{ formatCountdown(remainingMs) }}
          </span>
        </span>
        <button
          type="button"
          class="text-red-600 dark:text-red-400 hover:underline"
          @click="resetForm"
        >
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.CANCEL_AND_REGENERATE'
            )
          }}
        </button>
      </div>

      <p class="text-[11px] text-blue-600 dark:text-blue-400 mt-2">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.SESSION_LABEL'
          )
        }}:
        <code class="font-mono">{{ sessionId }}</code>
      </p>
    </div>

    <!-- State 3: expired -->
    <div
      v-else
      class="p-4 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg"
    >
      <h4 class="font-medium text-amber-800 dark:text-amber-200">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.EXPIRED_TITLE'
          )
        }}
      </h4>
      <p class="text-xs text-amber-700 dark:text-amber-300 mt-1 mb-3">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.EXPIRED_HELP'
          )
        }}
      </p>
      <NextButton
        variant="outline"
        :label="
          $t('INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.BACK_BUTTON')
        "
        @click="resetForm"
      />
    </div>
  </section>
</template>
