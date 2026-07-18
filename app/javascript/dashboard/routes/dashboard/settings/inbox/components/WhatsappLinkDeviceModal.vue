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
// Pair state is independent of websocket state. The modal's job is
// PAIRING, so it must branch on pair_state — not on `connection` (which
// only describes the websocket). Previously the modal hid the pair tabs
// whenever `connection === 'open'` even on unpaired instances, leaving
// the user staring at a header and an InboxName with nothing to click.
const isAlreadyPaired = computed(
  () => providerConnection.value?.is_paired === true
);

// Alternative onboarding when WhatsApp's extra device-linking verification blocks
// the QR: install the browser extension and import an already-linked session.
const extensionUrl =
  'https://chromewebstore.google.com/detail/fazerai-whatsapp-connecto/nchdjpjplcnggifnemiiclgjplooible';

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
// When WhatsApp returns PAIR_RATE_LIMITED we capture the unlock time
// so the button can be disabled until the cooldown ends and the user
// sees a live countdown rather than guessing how long to wait.
const pairLockedUntil = ref(null);
const nowTick = ref(Date.now());
const pairLockSecondsLeft = computed(() => {
  if (!pairLockedUntil.value) return 0;
  const ms = new Date(pairLockedUntil.value).getTime() - nowTick.value;
  return Math.max(0, Math.ceil(ms / 1000));
});
const pairLockedFormatted = computed(() => {
  const s = pairLockSecondsLeft.value;
  if (s <= 0) return '';
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m > 0 ? `${m}m ${r.toString().padStart(2, '0')}s` : `${r}s`;
});
// Per-tab activation flags. The previous single `userInitiatedPairing`
// was shared across both tabs, so clicking Emparelhar on Phone Code
// (which still triggers /instances/connect on the api side, which can
// emit a spontaneous pairing.qrcode webhook) populated qr_data_url and
// IMMEDIATELY rendered the QR if the user switched tabs. Splitting the
// flag per tab guarantees:
//   - QR tab renders the QR ONLY after the user clicked Emparelhar
//     while the QR tab was active
//   - Phone Code tab renders the 8-char code ONLY after the user
//     clicked Emparelhar while that tab was active
//   - Tab switching alone never reveals output
//   - Modal close + reopen / page refresh resets both flags
const qrInitiated = ref(false);
const phoneInitiated = ref(false);
// Convenience for the auto-close-on-success watcher: any tab counts.
const userInitiatedPairing = computed(
  () => qrInitiated.value || phoneInitiated.value
);
// Upstream's "import an existing WhatsApp Web session" disclosure toggle.
const showImportDetails = ref(false);

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
// QR pair = POST /instances/pair/qrcode (single call, auto-connects on
// the API side per spec). Replaces the older `setup_channel_provider`
// chain which did create+webhook+connect+QR every time the button
// was clicked. The new path also self-heals on 404 (instance deleted
// API-side) by rebuilding via setup before retrying.
const startQrPairing = async () => {
  pairingMode.value = 'qr';
  qrInitiated.value = true;
  loading.value = true;
  try {
    await store.dispatch('inboxes/pairQrcode', props.inbox.id);
  } catch (e) {
    handleError(e);
  } finally {
    loading.value = false;
  }
};
const disconnect = () => {
  loading.value = true;
  store
    .dispatch('inboxes/disconnectChannelProvider', props.inbox.id)
    .catch(handleError);
};

// Phone pair = POST /instances/pair/phonecode (auto-connects, also
// self-heals on 404 backend-side). No pre-flight setup needed.
const requestPhoneCode = async () => {
  phoneInitiated.value = true;
  phoneCodeError.value = '';
  phoneCode.value = '';
  phoneCodeLoading.value = true;
  try {
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
    pairLockedUntil.value = e?.lockedUntil || null;
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
  if (pairLockSecondsLeft.value > 0) return true;
  if (pairingMode.value === 'phone') return !props.inbox.phone_number;
  return false;
});
const pairingButtonLoading = computed(
  () => loading.value || phoneCodeLoading.value
);

// Reset session state every time the modal opens so previously
// rendered QR / phone-code never leaks across opens. The user must
// click Emparelhar again on each modal session.
let lockTickerId = null;
// Pair-detection poll. While the modal is open mid-pairing, the
// pair handshake fires server-side asynchronously and the Vuex inbox
// snapshot only updates when SOMETHING refetches. The connection.*
// webhook tail doesn't reliably refresh the Vuex cache (no cable
// subscription on provider_connection), so we poll the rate-limited
// /refresh_provider_status endpoint every 3s while pairing is in
// flight, until we observe `is_paired=true`. Then auto-close.
let pairPollId = null;
const startPairPoll = () => {
  // Propriacloud-only — non-propriacloud channels don't expose a
  // /refresh_provider_status endpoint and would just 422 every tick.
  if (!isPropriacloud.value) return;
  if (pairPollId) return;
  pairPollId = setInterval(() => {
    store.dispatch('inboxes/refreshProviderStatus', props.inbox.id);
  }, 3000);
};
const stopPairPoll = () => {
  if (pairPollId) {
    clearInterval(pairPollId);
    pairPollId = null;
  }
};
watch(
  () => props.show,
  val => {
    if (val) {
      qrInitiated.value = false;
      phoneInitiated.value = false;
      phoneCode.value = '';
      phoneCodeError.value = '';
      phoneCodeLoading.value = false;
      loading.value = false;
      pairingMode.value = 'qr';
      // Pair-lock state is keyed on the channel server-side. Read it
      // from the inbox's provider_config so the modal reflects the
      // cooldown even after a page reload.
      const lock = props.inbox?.provider_config?.pair_locked_until || null;
      pairLockedUntil.value = lock;
      // Drive the countdown without a heavy timer when no lock is set.
      if (!lockTickerId) {
        lockTickerId = setInterval(() => {
          nowTick.value = Date.now();
        }, 1000);
      }
    } else {
      if (lockTickerId) {
        clearInterval(lockTickerId);
        lockTickerId = null;
      }
      stopPairPoll();
    }
  }
);
onUnmounted(() => {
  if (lockTickerId) {
    clearInterval(lockTickerId);
    lockTickerId = null;
  }
  stopPairPoll();
});

// Start polling for pair success the moment the user kicks off a
// pair attempt (either QR or Phone-code tab). Propriacloud only —
// other providers use the legacy `connection`-driven flow below.
watch(userInitiatedPairing, val => {
  if (val && props.show && isPropriacloud.value) startPairPoll();
});

// Auto-close the modal once the device is actually paired. Triggers
// on `is_paired` flipping true via the Vuex inbox refresh — that's
// the only thing that actually means "pairing succeeded" upstream.
// The previous `connection === 'open'` watcher never fired because
// connection was already 'open' before the user pressed Emparelhar
// (the WS was up from the Conectar action). Propriacloud-only — non-
// propriacloud providers don't populate `is_paired` and continue to
// rely on the connection-axis watcher below.
watch(isAlreadyPaired, val => {
  if (
    props.show &&
    userInitiatedPairing.value &&
    val === true &&
    isPropriacloud.value &&
    typeof props.onClose === 'function'
  ) {
    stopPairPoll();
    setTimeout(() => {
      if (props.show) props.onClose();
    }, 1500);
  }
});

// Non-propriacloud auto-close: connection flipping to 'open' is the
// pair-success signal for the legacy Baileys / Zapi / Whatsmeow
// flows. Kept verbatim from the pre-propriacloud behaviour.
watch(
  () => connection.value,
  val => {
    if (
      props.show &&
      !isPropriacloud.value &&
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
          <InboxName :inbox="inbox" class="!text-lg" with-phone-number />

          <!-- ============================================================
               PROPRIACLOUD: pair-only modal. The modal's one job here is
               pairing. Disconnect / Reconnect live on the inbox page
               (Conectar / Desconectar buttons on the Informações tab),
               so we NEVER render the legacy "you're connected, click
               Disconnect" branch for propriacloud — that confused users
               into thinking they had to disconnect first to see the
               pair tabs. Branch is purely a function of pair_state:
                 - not paired → pair tabs (QR / Phone code)
                 - paired     → short "already paired" confirmation
               ============================================================ -->
          <!-- Legacy non-propriacloud flow (Baileys / Zapi / Whatsmeow):
               single "Link device" button → auto-fetched QR. Untouched. -->
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
          </template>

          <!-- Propriacloud: pair-only modal. The user always landed here
               by clicking Emparelhar — so the modal's job is pairing,
               full stop. Branch ONLY on pair_state. Disconnect lives on
               the inbox page (Desconectar button), never here. -->
          <template v-else-if="!isAlreadyPaired">
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
                   clicked Emparelhar with the QR tab active. The
                   backend's /instances/connect call (triggered by the
                   Phone Code path too) can produce a spontaneous
                   pairing.qrcode webhook that populates qr_data_url —
                   without this gate, switching to the QR tab would
                   reveal that QR even though the user never asked. -->
              <img
                v-if="qrInitiated && qrDataUrl"
                :src="qrDataUrl"
                alt="QR Code"
                class="w-[276px] h-[276px]"
              />
              <div
                v-else-if="qrInitiated && loading"
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
                  v-if="phoneInitiated && phoneCodeError"
                  class="text-xs text-red-500 text-center"
                >
                  {{ phoneCodeError }}
                  <span v-if="pairLockSecondsLeft > 0" class="block mt-1">
                    {{
                      $t(
                        'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.PAIR_LOCK_COUNTDOWN',
                        { time: pairLockedFormatted }
                      )
                    }}
                  </span>
                </p>
                <div
                  v-if="phoneInitiated && phoneCode"
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

          <!-- Propriacloud + already paired: short confirmation + close.
               No Disconnect button here — Desconectar lives on the inbox
               page where the rest of the action row sits. -->
          <template v-else>
            <p class="text-center text-sm text-n-slate-11">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.ALREADY_PAIRED'
                )
              }}
            </p>
            <router-link
              v-if="isSetup"
              :to="{
                name: 'inbox_dashboard',
                params: { inboxId: inbox.id },
              }"
            >
              <Button solid teal :label="$t('INBOX_MGMT.FINISH.BUTTON_TEXT')" />
            </router-link>
            <Button v-else size="sm" ghost label="OK" @click="onClose" />
          </template>

          <!-- Fallback kept available in every non-open state, including while the
               QR is shown: import an already-linked session via the extension.
               Baileys-only by design: `import_session` is defined solely on the
               baileys provider service, and the controller rejects every other
               provider with 422 — so hide the CTA for propriacloud inboxes
               instead of offering an action that cannot succeed. -->
          <div
            v-if="!isPropriacloud && connection !== 'open'"
            class="flex flex-col gap-1 items-center pt-4 mt-2 w-full border-t border-n-weak"
          >
            <p class="text-sm font-medium text-center text-n-slate-12">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_TITLE'
                )
              }}
            </p>
            <button
              v-if="!showImportDetails"
              type="button"
              :aria-expanded="showImportDetails"
              class="text-xs underline text-n-slate-11 hover:text-n-slate-12"
              @click="showImportDetails = true"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_SHOW_MORE'
                )
              }}
            </button>
            <template v-else>
              <p class="text-sm text-center text-n-slate-11">
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_DESC'
                  )
                }}
              </p>
              <a :href="extensionUrl" target="_blank" rel="noopener noreferrer">
                <Button
                  link
                  blue
                  :label="
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_INSTALL'
                    )
                  "
                />
              </a>
            </template>
          </div>
        </div>
      </div>
    </div>
  </woot-modal>
</template>
