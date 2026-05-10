<script setup>
import { onMounted, computed, onUnmounted, ref, watch, watchEffect } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import InboxName from 'dashboard/components/widgets/InboxName.vue';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, required: true },
  onClose: { type: Function, required: true },
  isSetup: { type: Boolean, required: false },
  inbox: {
    type: Object,
    required: true,
  },
});

const store = useStore();

const providerConnection = computed(() => props.inbox.provider_connection);
const connection = computed(() => providerConnection.value?.connection);
const qrDataUrl = computed(() => providerConnection.value?.qr_data_url);
const error = computed(() => providerConnection.value?.error);

const loading = ref(false);
// Pairing mode: 'qr' (default) or 'phone' (8-char code into WhatsApp's
// "Link with phone number" flow). Only the propriacloud provider exposes
// the phone-code path right now via /instances/pair/phonecode.
const isPropriacloud = computed(
  () =>
    props.inbox.channel_type === 'Channel::Whatsapp' &&
    props.inbox.provider === 'propriacloud'
);
const pairingMode = ref('qr');
const phoneCode = ref('');
const phoneCodeLoading = ref(false);
const phoneCodeError = ref('');
// True only after the user has explicitly clicked "Emparelhar" in this
// modal session. Until then we never render an existing QR or phone
// code from provider_connection — even if the inbox row carries one
// from a previous attempt — so the modal opens to the tab picker
// every time and never implies pairing was already initiated.
const userInitiatedPairing = ref(false);

const handleError = e => {
  useAlert(e.message);
  loading.value = false;
};
const setup = () => {
  loading.value = true;
  store
    .dispatch('inboxes/setupChannelProvider', props.inbox.id)
    .catch(handleError);
};
const startQrPairing = () => {
  pairingMode.value = 'qr';
  userInitiatedPairing.value = true;
  setup();
};
const ensureConnectingForPhoneCode = async () => {
  if (!connection.value || connection.value === 'close') {
    await store.dispatch('inboxes/setupChannelProvider', props.inbox.id);
  }
};
const disconnect = () => {
  loading.value = true;
  store
    .dispatch('inboxes/disconnectChannelProvider', props.inbox.id)
    .catch(handleError);
};

const requestPhoneCode = async () => {
  userInitiatedPairing.value = true;
  phoneCodeError.value = '';
  phoneCode.value = '';
  phoneCodeLoading.value = true;
  try {
    await ensureConnectingForPhoneCode();
    const result = await store.dispatch('inboxes/pairPhoneCode', {
      inboxId: props.inbox.id,
      phone: props.inbox.phone_number,
    });
    phoneCode.value = result?.code || '';
    if (!phoneCode.value) {
      phoneCodeError.value = 'No code returned from provider';
    }
  } catch (e) {
    phoneCodeError.value = e?.message || 'Failed to request pairing code';
  } finally {
    phoneCodeLoading.value = false;
  }
};

// Single trigger shared by both pairing tabs: clicking "Emparelhar"
// fires the QR generation OR the phone-code request depending on the
// currently selected tab. Nothing runs until the user clicks.
const triggerPairing = () => {
  if (pairingMode.value === 'qr') {
    startQrPairing();
  } else {
    requestPhoneCode();
  }
};
const pairingButtonDisabled = computed(() => {
  if (pairingMode.value === 'phone') return !props.inbox.phone_number;
  return false;
});
const pairingButtonLoading = computed(
  () => loading.value || phoneCodeLoading.value
);

// Reset session state every time the modal opens so previously
// rendered QR / phone-code never leaks across opens. The user must
// click Emparelhar again on each modal session.
watch(
  () => props.show,
  val => {
    if (val) {
      userInitiatedPairing.value = false;
      phoneCode.value = '';
      phoneCodeError.value = '';
      phoneCodeLoading.value = false;
      loading.value = false;
      pairingMode.value = 'qr';
    }
  }
);

// Auto-close the modal once pairing succeeds. Only fires when the
// user explicitly initiated pairing in this session AND the modal
// is currently visible, so background webhook drift on an already-
// connected inbox can never auto-dismiss the modal. A short delay
// lets the "Connected" state flash so the agent understands what
// happened.
watch(
  () => connection.value,
  val => {
    if (
      props.show &&
      userInitiatedPairing.value &&
      val === 'open' &&
      typeof props.onClose === 'function'
    ) {
      setTimeout(() => {
        if (props.show) props.onClose();
      }, 1500);
    }
  }
);

// No auto-setup or auto-disconnect on mount/unmount — let the user
// pick the auth method and trigger explicitly. Only Propriacloud uses
// this modal; for Baileys/Zapi the prior auto-setup behaviour kicks in.
onMounted(() => {
  if (
    !isPropriacloud.value &&
    (!connection.value || connection.value === 'close')
  ) {
    setup();
  }
});
onUnmounted(() => {
  if (
    !isPropriacloud.value &&
    (connection.value === 'connecting' || connection.value === 'reconnecting')
  ) {
    disconnect();
  }
});
watchEffect(() => {
  if (connection.value) {
    loading.value = false;
  }
});
</script>

<template>
  <woot-modal :show="show" size="small" @close="onClose">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.TITLE'
          )
        "
        :header-content="
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.SUBTITLE'
          )
        "
      />

      <div class="flex flex-col gap-4 p-8 pt-4">
        <div class="flex flex-col gap-4 items-center">
          <InboxName
            :inbox="inbox"
            class="!text-lg"
            with-phone-number
            with-provider-connection-status
          />

          <!-- Non-propriacloud (Baileys / Zapi / Whatsmeow) keeps the
               existing one-button "Link device" flow that auto-fetches QR. -->
          <template v-if="!isPropriacloud">
            <template v-if="!connection || connection === 'close' || error">
              <p v-if="error" class="text-red-500 text-center">
                {{ error }}
              </p>
              <Button :is-loading="loading" @click="setup">
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.LINK_DEVICE'
                  )
                }}
              </Button>
            </template>

            <template v-else-if="connection === 'connecting'">
              <div v-if="!qrDataUrl" class="flex flex-col gap-4 items-center">
                <p>
                  {{
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.LOADING_QRCODE'
                    )
                  }}
                </p>
                <Spinner />
              </div>
              <img
                v-else
                :src="qrDataUrl"
                alt="QR Code"
                class="w-[276px] h-[276px]"
              />
            </template>

            <template v-else-if="connection === 'reconnecting'">
              <p>
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.RECONNECTING'
                  )
                }}
              </p>
              <Spinner />
            </template>
          </template>

          <!-- Propriacloud: user picks pairing method first, no auto-setup. -->
          <template
            v-else-if="connection !== 'open' && connection !== 'reconnecting'"
          >
            <p v-if="error" class="text-red-500 text-center">
              {{ error }}
            </p>

            <div class="flex gap-2">
              <Button
                :solid="pairingMode === 'qr'"
                :ghost="pairingMode !== 'qr'"
                :label="
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.PAIRING_METHOD_QR'
                  )
                "
                @click="pairingMode = 'qr'"
              />
              <Button
                :solid="pairingMode === 'phone'"
                :ghost="pairingMode !== 'phone'"
                :label="
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.PAIRING_METHOD_PHONE'
                  )
                "
                @click="pairingMode = 'phone'"
              />
            </div>

            <template v-if="pairingMode === 'qr'">
              <!-- Render the QR only after the user has explicitly
                   clicked Emparelhar in THIS modal session.
                   `userInitiatedPairing` is reset on every modal open. -->
              <img
                v-if="userInitiatedPairing && qrDataUrl"
                :src="qrDataUrl"
                alt="QR Code"
                class="w-[276px] h-[276px]"
              />
              <div
                v-else-if="userInitiatedPairing && loading"
                class="flex flex-col gap-4 items-center"
              >
                <p>
                  {{
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.LOADING_QRCODE'
                    )
                  }}
                </p>
                <Spinner />
              </div>
              <div v-else class="flex flex-col gap-3 items-center">
                <p class="text-sm text-n-slate-11 text-center max-w-sm">
                  {{
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.QR_INSTRUCTIONS'
                    )
                  }}
                </p>
              </div>
            </template>

            <template v-else>
              <div class="flex flex-col gap-3 w-full max-w-sm">
                <p class="text-sm text-n-slate-11 text-center">
                  {{
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.PHONE_CODE_INSTRUCTIONS'
                    )
                  }}
                </p>
                <p
                  v-if="phoneCodeError"
                  class="text-xs text-red-500 text-center"
                >
                  {{ phoneCodeError }}
                </p>
                <div
                  v-if="phoneCode"
                  class="mt-2 px-4 py-3 bg-n-solid-2 rounded text-center"
                >
                  <p class="text-xs text-n-slate-11 mb-1">
                    {{
                      $t(
                        'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.ENTER_CODE_IN_WHATSAPP'
                      )
                    }}
                  </p>
                  <p class="text-2xl font-mono tracking-widest">
                    {{ phoneCode }}
                  </p>
                </div>
              </div>
            </template>

            <!-- Unified small action button — same "Emparelhar" label across
                 both QR and Phone Code tabs. Activation only fires when the
                 user clicks; nothing auto-runs on mount or tab switch. -->
            <Button
              size="sm"
              :is-loading="pairingButtonLoading"
              :disabled="pairingButtonDisabled"
              label="Emparelhar"
              @click="triggerPairing"
            />
          </template>

          <template v-else-if="connection === 'reconnecting'">
            <p>
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.RECONNECTING'
                )
              }}
            </p>
            <Spinner />
          </template>

          <template v-else-if="connection === 'open'">
            <p v-if="isSetup" class="text-center">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.CONNECTED'
                )
              }}
            </p>
            <div class="flex gap-2">
              <Button ghost :is-loading="loading" @click="disconnect">
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.DISCONNECT'
                  )
                }}
              </Button>
              <router-link
                v-if="isSetup"
                :to="{
                  name: 'inbox_dashboard',
                  params: { inboxId: inbox.id },
                }"
              >
                <Button
                  solid
                  teal
                  :label="$t('INBOX_MGMT.FINISH.BUTTON_TEXT')"
                />
              </router-link>
            </div>
          </template>
        </div>
      </div>
    </div>
  </woot-modal>
</template>
