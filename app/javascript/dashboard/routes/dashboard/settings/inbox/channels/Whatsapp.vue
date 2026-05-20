<script setup>
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n, I18nT } from 'vue-i18n';
import Twilio from './Twilio.vue';
import ThreeSixtyDialogWhatsapp from './360DialogWhatsapp.vue';
import CloudWhatsapp from './CloudWhatsapp.vue';
import WhatsappEmbeddedSignup from './WhatsappEmbeddedSignup.vue';
import ChannelSelector from 'dashboard/components/ChannelSelector.vue';
import BaileysWhatsapp from './BaileysWhatsapp.vue';
import WhatsmeowWhatsapp from './WhatsmeowWhatsapp.vue';
import PropriacloudWhatsapp from './PropriacloudWhatsapp.vue';
import PropriacloudWhatsappEmbeddedSignup from './PropriacloudWhatsappEmbeddedSignup.vue';
import ZapiWhatsapp from './ZapiWhatsapp.vue';
import PromoBanner from 'dashboard/components-next/banner/PromoBanner.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const props = defineProps({
  mode: {
    type: String,
    default: 'create',
    validator: value => ['create', 'convert'].includes(value),
  },
  inbox: {
    type: Object,
    default: null,
  },
});

const isConvertMode = computed(() => props.mode === 'convert');

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const { isFeatureFlagEnabled } = usePolicy();

// Latched by the child once it triggers the post-success router.replace.
// Suppresses rendering during the navigation tail so the parent doesn't
// briefly re-render against the new route's query params (which would clear
// `route.query.provider` and flash the provider picker between the success
// toast and the unmount).
const isLeaving = ref(false);
const handleEmbeddedSignupLeaving = () => {
  isLeaving.value = true;
};

const PROVIDER_TYPES = {
  WHATSAPP: 'whatsapp',
  TWILIO: 'twilio',
  WHATSAPP_CLOUD: 'whatsapp_cloud',
  WHATSAPP_EMBEDDED: 'whatsapp_embedded',
  WHATSAPP_MANUAL: 'whatsapp_manual',
  THREE_SIXTY_DIALOG: '360dialog',
  BAILEYS: 'baileys',
  WHATSMEOW: 'whatsmeow',
  PROPRIACLOUD: 'propriacloud',
  ZAPI: 'zapi',
};

const hasEmbeddedSignupConfig = computed(() => {
  const { whatsappAppId, whatsappConfigurationId } =
    window.chatwootConfig ?? {};
  return (
    whatsappAppId &&
    whatsappAppId !== 'none' &&
    whatsappConfigurationId &&
    whatsappConfigurationId !== 'none'
  );
});

// Show the Propria.Cloud Embedded Signup panel when the deployment has been
// configured for it (env-driven flag on the chatwootConfig object). The
// option lives ALONGSIDE the existing manual propriacloud setup — both stay
// reachable so users can choose between supplying credentials manually OR
// running the Meta popup through propria.cloud's tech-provider.
const hasPropriacloudEmbeddedSignupConfig = computed(() => {
  const { propriacloudEmbeddedSignupEnabled } = window.chatwootConfig ?? {};
  return (
    propriacloudEmbeddedSignupEnabled === true ||
    propriacloudEmbeddedSignupEnabled === 'true'
  );
});
const propriacloudShowEmbeddedSignup = ref(false);
const togglePropriacloudEmbeddedSignup = () => {
  propriacloudShowEmbeddedSignup.value = !propriacloudShowEmbeddedSignup.value;
};

const selectedProvider = computed(() => route.query.provider);

const INBOX_PROVIDER_TO_KEY = {
  whatsapp_cloud: PROVIDER_TYPES.WHATSAPP,
  default: PROVIDER_TYPES.THREE_SIXTY_DIALOG,
  baileys: PROVIDER_TYPES.BAILEYS,
  zapi: PROVIDER_TYPES.ZAPI,
};

const currentProviderKey = computed(() => {
  if (!props.inbox?.provider) return null;
  return INBOX_PROVIDER_TO_KEY[props.inbox.provider] || null;
});

const PROVIDER_CATALOG = computed(() => [
  {
    key: PROVIDER_TYPES.WHATSAPP,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD_DESC'),
    icon: 'i-woot-whatsapp',
  },
  {
    key: PROVIDER_TYPES.TWILIO,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO_DESC'),
    icon: 'i-woot-twilio',
  },
  {
    key: PROVIDER_TYPES.BAILEYS,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.BAILEYS'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.BAILEYS_DESC'),
    icon: 'i-woot-baileys',
  },
  {
    key: PROVIDER_TYPES.WHATSMEOW,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSMEOW'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSMEOW_DESC'),
    icon: 'i-woot-whatsapp',
  },
  {
    key: PROVIDER_TYPES.PROPRIACLOUD,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.PROPRIACLOUD'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.PROPRIACLOUD_DESC'),
    icon: 'i-lucide-qr-code',
  },
  {
    key: PROVIDER_TYPES.ZAPI,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.ZAPI'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.ZAPI_DESC'),
    icon: 'i-woot-zapi',
  },
  {
    key: PROVIDER_TYPES.THREE_SIXTY_DIALOG,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.360_DIALOG'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.360_DIALOG_DESC'),
    icon: 'i-woot-whatsapp',
  },
]);

// Keys shown in the picker. 360Dialog is intentionally hidden in create mode
// (URL-reachable only) but offered in convert mode where it is a valid target.
// PROVIDER_TYPES.WHATSAPP ("Cloud do WhatsApp" / "Conectar via API") is
// deliberately omitted from both pickers: this build routes Official API
// access exclusively through Própria Cloud, so the embedded-signup /
// manual-Cloud paths must not be reachable from the UI.
const CREATE_PICKER_KEYS = [
  PROVIDER_TYPES.TWILIO,
  PROVIDER_TYPES.BAILEYS,
  PROVIDER_TYPES.WHATSMEOW,
  PROVIDER_TYPES.PROPRIACLOUD,
  PROVIDER_TYPES.ZAPI,
];
const CONVERT_PICKER_KEYS = [
  PROVIDER_TYPES.BAILEYS,
  PROVIDER_TYPES.WHATSMEOW,
  PROVIDER_TYPES.PROPRIACLOUD,
  PROVIDER_TYPES.ZAPI,
  PROVIDER_TYPES.THREE_SIXTY_DIALOG,
];

const availableProviders = computed(() => {
  // Apply codi feature-flag gating on top of the upstream picker shape
  // (CONVERT_PICKER_KEYS / CREATE_PICKER_KEYS). The catalog already lists
  // all providers; the flags decide which extras (Twilio/Baileys/Whatsmeow/
  // Própria Cloud/Z-API) are exposed to the user.
  const flagFor = key => {
    switch (key) {
      case PROVIDER_TYPES.TWILIO:
        return FEATURE_FLAGS.CHANNEL_TWILIO_WHATSAPP;
      case PROVIDER_TYPES.BAILEYS:
        return FEATURE_FLAGS.CHANNEL_WHATSAPP_BAILEYS;
      case PROVIDER_TYPES.WHATSMEOW:
        return FEATURE_FLAGS.CHANNEL_WHATSAPP_WHATSMEOW;
      case PROVIDER_TYPES.PROPRIACLOUD:
        return FEATURE_FLAGS.CHANNEL_WHATSAPP_PROPRIACLOUD;
      case PROVIDER_TYPES.ZAPI:
        return FEATURE_FLAGS.CHANNEL_ZAPI;
      default:
        return null;
    }
  };
  const allowed = isConvertMode.value
    ? CONVERT_PICKER_KEYS
    : CREATE_PICKER_KEYS;
  return PROVIDER_CATALOG.value
    .filter(p => allowed.includes(p.key))
    .filter(p => !isConvertMode.value || p.key !== currentProviderKey.value)
    .filter(p => {
      const flag = flagFor(p.key);
      return flag === null || isFeatureFlagEnabled(flag);
    });
});

const currentProviderLabel = computed(() => {
  if (!isConvertMode.value || !currentProviderKey.value) return '';
  return (
    PROVIDER_CATALOG.value.find(({ key }) => key === currentProviderKey.value)
      ?.title || ''
  );
});

const isValidSelectedProvider = computed(() => {
  if (!selectedProvider.value) return false;
  // In create mode, allow the legacy-URL path to 360Dialog even though it is
  // not in the picker. The Meta-Cloud paths (PROVIDER_TYPES.WHATSAPP and
  // PROVIDER_TYPES.WHATSAPP_MANUAL) are intentionally NOT whitelisted here:
  // this build forbids URL-hacking onto the embedded-signup / manual Cloud
  // forms, since Official API is served only through Própria Cloud.
  if (!isConvertMode.value) {
    if (selectedProvider.value === PROVIDER_TYPES.THREE_SIXTY_DIALOG)
      return true;
  }
  return availableProviders.value.some(
    ({ key }) => key === selectedProvider.value
  );
});

const showProviderSelection = computed(
  () => !isLeaving.value && !isValidSelectedProvider.value
);
const showConfiguration = computed(
  () => !isLeaving.value && isValidSelectedProvider.value
);

const selectProvider = providerValue => {
  router.push({
    name: route.name,
    params: route.params,
    query: { provider: providerValue },
  });
};

const shouldShowCloudWhatsapp = provider => {
  return (
    provider === PROVIDER_TYPES.WHATSAPP_MANUAL ||
    (provider === PROVIDER_TYPES.WHATSAPP && !hasEmbeddedSignupConfig.value)
  );
};

const handleManualLinkClick = () => {
  selectProvider(PROVIDER_TYPES.WHATSAPP_MANUAL);
};

// Promo banners (Própria Cloud / Z-API) are intentionally disabled — Própria
// Cloud is now the recommended path and shown directly in the picker; no
// cross-sell needed.
const shouldShowPropriacloudPromo = computed(() => false);
const shouldShowZApiPromo = computed(() => false);
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <div v-if="showProviderSelection">
      <div class="mb-10 text-left">
        <h1 class="mb-2 text-lg font-medium text-n-slate-12">
          {{
            isConvertMode
              ? $t('INBOX_MGMT.CONVERT.SELECT_PROVIDER_TITLE')
              : $t('INBOX_MGMT.ADD.WHATSAPP.SELECT_PROVIDER.TITLE')
          }}
        </h1>
        <p class="text-sm leading-relaxed text-n-slate-11">
          {{
            isConvertMode
              ? $t('INBOX_MGMT.CONVERT.SELECT_PROVIDER_DESCRIPTION', {
                  inboxName: inbox?.name,
                  currentProvider: currentProviderLabel,
                })
              : $t('INBOX_MGMT.ADD.WHATSAPP.SELECT_PROVIDER.DESCRIPTION')
          }}
        </p>
      </div>

      <div
        class="grid max-w-3xl grid-cols-1 xs:grid-cols-2 gap-6 sm:grid-cols-3"
      >
        <ChannelSelector
          v-for="provider in availableProviders"
          :key="provider.key"
          :title="provider.title"
          :description="provider.description"
          :icon="provider.icon"
          @click="selectProvider(provider.key)"
        />
      </div>

      <div
        v-if="shouldShowPropriacloudPromo && !isConvertMode"
        class="mt-6 relative overflow-visible"
      >
        <PromoBanner
          :title="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.SELECT_PROVIDER.PROPRIACLOUD_PROMO.TITLE'
            )
          "
          :description="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.SELECT_PROVIDER.PROPRIACLOUD_PROMO.DESCRIPTION'
            )
          "
          variant="success"
          logo-src=""
          logo-alt="Própria Cloud"
          :cta-text="
            $t('INBOX_MGMT.ADD.WHATSAPP.SELECT_PROVIDER.PROPRIACLOUD_PROMO.CTA')
          "
          @cta-click="selectProvider(PROVIDER_TYPES.PROPRIACLOUD)"
        />
      </div>

      <div
        v-if="shouldShowZApiPromo && !isConvertMode"
        class="mt-6 relative overflow-visible"
      >
        <img
          src="~dashboard/assets/images/curved-arrow.svg"
          alt=""
          class="absolute -top-12 right-0 w-20 h-20 pointer-events-none z-10 scale-y-[-1] -rotate-45"
        />
        <PromoBanner
          :title="
            $t('INBOX_MGMT.ADD.WHATSAPP.SELECT_PROVIDER.ZAPI_PROMO.TITLE')
          "
          :description="
            $t('INBOX_MGMT.ADD.WHATSAPP.SELECT_PROVIDER.ZAPI_PROMO.DESCRIPTION')
          "
          variant="success"
          logo-src="/assets/images/dashboard/channels/z-api/z-api-dark-green.png"
          logo-alt="Z-API"
          :cta-text="
            $t('INBOX_MGMT.ADD.WHATSAPP.SELECT_PROVIDER.ZAPI_PROMO.CTA')
          "
          @cta-click="selectProvider(PROVIDER_TYPES.ZAPI)"
        />
      </div>
    </div>

    <div v-else-if="showConfiguration">
      <div class="px-6 py-5 rounded-2xl border border-n-weak">
        <!-- Show embedded signup if app ID is configured -->
        <div
          v-if="
            hasEmbeddedSignupConfig &&
            selectedProvider === PROVIDER_TYPES.WHATSAPP
          "
        >
          <WhatsappEmbeddedSignup
            :mode="mode"
            :inbox="inbox"
            @leaving="handleEmbeddedSignupLeaving"
          />

          <!-- Manual setup fallback option -->
          <div class="pt-6 mt-6 border-t border-n-weak">
            <I18nT
              keypath="INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.MANUAL_FALLBACK"
              tag="p"
              class="text-sm text-n-slate-11"
            >
              <template #link>
                <a
                  href="#"
                  class="underline text-n-brand"
                  @click.prevent="handleManualLinkClick"
                >
                  {{
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.MANUAL_LINK_TEXT'
                    )
                  }}
                </a>
              </template>
            </I18nT>
          </div>
        </div>

        <!-- Show manual setup -->
        <CloudWhatsapp
          v-else-if="shouldShowCloudWhatsapp(selectedProvider)"
          :mode="mode"
          :inbox="inbox"
        />

        <!-- Other providers -->
        <Twilio
          v-else-if="selectedProvider === PROVIDER_TYPES.TWILIO"
          type="whatsapp"
        />
        <ThreeSixtyDialogWhatsapp
          v-else-if="selectedProvider === PROVIDER_TYPES.THREE_SIXTY_DIALOG"
          :mode="mode"
          :inbox="inbox"
        />
        <BaileysWhatsapp
          v-else-if="selectedProvider === PROVIDER_TYPES.BAILEYS"
          :mode="mode"
          :inbox="inbox"
        />
        <ZapiWhatsapp
          v-else-if="selectedProvider === PROVIDER_TYPES.ZAPI"
          :mode="mode"
          :inbox="inbox"
        />
        <WhatsmeowWhatsapp
          v-else-if="selectedProvider === PROVIDER_TYPES.WHATSMEOW"
        />
        <!-- Propria.Cloud — embedded signup gate -->
        <template v-else-if="selectedProvider === PROVIDER_TYPES.PROPRIACLOUD">
          <div v-if="hasPropriacloudEmbeddedSignupConfig">
            <PropriacloudWhatsappEmbeddedSignup
              v-if="propriacloudShowEmbeddedSignup"
            />
            <PropriacloudWhatsapp v-else />
            <div class="pt-4 mt-4 border-t border-n-weak text-sm">
              <a
                href="#"
                class="underline text-n-brand"
                @click.prevent="togglePropriacloudEmbeddedSignup"
              >
                {{
                  propriacloudShowEmbeddedSignup
                    ? $t(
                        'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.TOGGLE_TO_MANUAL'
                      )
                    : $t(
                        'INBOX_MGMT.ADD.WHATSAPP.PROPRIACLOUD.EMBEDDED_SIGNUP.TOGGLE_TO_EMBEDDED'
                      )
                }}
              </a>
            </div>
          </div>
          <PropriacloudWhatsapp v-else />
        </template>
      </div>
    </div>
  </div>
</template>
