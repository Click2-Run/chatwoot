// Two-axis status resolver for the propriacloud whatsapp-api provider.
//
// FAITHFUL PORT of propriacloud.git/apps/minha/app/components/whatsapp/instance-tags.ts
//   tag definitions (connectionTags, pairTags, readyTags, listStatusTags)
//   resolvers       (resolveConnectionTag, resolvePairTag, resolveReadyTag)
//
// Source-of-truth fields read from inbox.provider_connection (set by
// refresh_status_from_api! against /api/v1/instances/status):
//   connection_state ∈ { connected, connecting, disconnected }
//   pair_state       ∈ { paired, pairing, unpaired }
//   is_paired        boolean
//   is_connected     boolean
//
// Action button is intentionally minimal — minha's UX uses a single
// primary "Conectar" / "Desemparelhar" button next to two badges, and
// pairing flows live in a dedicated authentication tab (here: the
// LinkDeviceModal). When connected-but-unpaired we surface "Emparelhar"
// since Chatwoot's inbox settings doesn't have a separate auth tab.

import { computed } from 'vue';

// ---------------------------------------------------------------------------
// connectionTags — straight port from instance-tags.ts:55
// ---------------------------------------------------------------------------
export const connectionTags = {
  connected: {
    labelKey: 'INBOX_MGMT.PROPRIACLOUD_STATUS.CONNECTED', // "Conectada"
    chipClass: 'text-green-700 bg-green-50 border-green-200',
    dotClass: 'bg-green-500',
  },
  connecting: {
    labelKey: 'INBOX_MGMT.PROPRIACLOUD_STATUS.CONNECTING', // "Conectando"
    chipClass: 'text-amber-700 bg-amber-50 border-amber-200',
    dotClass: 'bg-amber-500 animate-pulse',
  },
  disconnected: {
    labelKey: 'INBOX_MGMT.PROPRIACLOUD_STATUS.DISCONNECTED', // "Desconectada"
    chipClass: 'text-red-700 bg-red-50 border-red-200',
    dotClass: 'bg-red-500',
  },
};

// ---------------------------------------------------------------------------
// pairTags — straight port from instance-tags.ts:64
// ---------------------------------------------------------------------------
export const pairTags = {
  paired: {
    labelKey: 'INBOX_MGMT.PROPRIACLOUD_STATUS.PAIRED', // "Emparelhada"
    chipClass: 'text-green-700 bg-green-50 border-green-200',
    dotClass: 'bg-green-500',
  },
  pairing: {
    labelKey: 'INBOX_MGMT.PROPRIACLOUD_STATUS.PAIRING', // "Emparelhando"
    chipClass: 'text-amber-700 bg-amber-50 border-amber-200',
    dotClass: 'bg-amber-500 animate-pulse',
  },
  unpaired: {
    labelKey: 'INBOX_MGMT.PROPRIACLOUD_STATUS.UNPAIRED', // "Desemparelhada"
    chipClass: 'text-red-700 bg-red-50 border-red-200',
    dotClass: 'bg-red-500',
  },
};

// ---------------------------------------------------------------------------
// readyTags — straight port from instance-tags.ts:80, used as the single
// chip on conversation headers / list rows where space is tight.
// ---------------------------------------------------------------------------
export const readyTags = {
  ready: {
    labelKey: 'INBOX_MGMT.PROPRIACLOUD_STATUS.READY', // "Pronta"
    chipClass: 'text-green-700 bg-green-50 border-green-200',
    dotClass: 'bg-green-500',
  },
  connected: {
    labelKey: 'INBOX_MGMT.PROPRIACLOUD_STATUS.CONNECTED', // "Conectada" (warning — not paired)
    chipClass: 'text-amber-700 bg-amber-50 border-amber-200',
    dotClass: 'bg-amber-500',
  },
  disconnected: {
    labelKey: 'INBOX_MGMT.PROPRIACLOUD_STATUS.DISCONNECTED', // "Desconectada"
    chipClass: 'text-red-700 bg-red-50 border-red-200',
    dotClass: 'bg-red-500',
  },
};

// ---------------------------------------------------------------------------
// resolveConnectionTag — port of instance-tags.ts:107
// ---------------------------------------------------------------------------
export function resolveConnectionTag(connectionState) {
  if (connectionState === 'connected') return 'connected';
  if (connectionState === 'connecting') return 'connecting';
  return 'disconnected';
}

// ---------------------------------------------------------------------------
// resolvePairTag — port of instance-tags.ts:114
// ---------------------------------------------------------------------------
export function resolvePairTag(pairState, isPaired) {
  if (isPaired) return 'paired';
  if (pairState === 'pairing') return 'pairing';
  return 'unpaired';
}

// ---------------------------------------------------------------------------
// resolveReadyTag — port of instance-tags.ts:124
// ---------------------------------------------------------------------------
export function resolveReadyTag(isReady, isWebSocketConnected) {
  if (isReady) return 'ready';
  if (isWebSocketConnected) return 'connected';
  return 'disconnected';
}

// ---------------------------------------------------------------------------
// Legacy fallbacks — keep resolver useful against pre-refresh inboxes
// whose provider_connection only carries the old `connection` field.
// ---------------------------------------------------------------------------
function mapLegacyConnection(connection) {
  if (connection === 'open') return 'connected';
  if (connection === 'connecting' || connection === 'reconnecting')
    return 'connecting';
  return 'disconnected';
}

function legacyPairState(pc) {
  if (pc.is_paired === true) return 'paired';
  if (pc.is_paired === false) return 'unpaired';
  if (pc.connection === 'open') return 'paired';
  return 'unpaired';
}

// ---------------------------------------------------------------------------
// Inbox → state extraction. Reads the new fields written by
// refresh_status_from_api! and falls back to the legacy `connection`
// vocabulary so pre-refresh inboxes still render meaningfully.
// ---------------------------------------------------------------------------
function extractState(inbox) {
  const pc = inbox?.provider_connection || {};
  const connectionState =
    pc.connection_state || mapLegacyConnection(pc.connection);
  const pairState = pc.pair_state || legacyPairState(pc);
  const isWebSocketConnected = connectionState === 'connected';
  const isPaired = pc.is_paired === true || pairState === 'paired';
  const isPairing = pairState === 'pairing';
  const isReady = isWebSocketConnected && isPaired;
  return {
    connectionState,
    pairState,
    isWebSocketConnected,
    isPaired,
    isPairing,
    isReady,
  };
}

// ---------------------------------------------------------------------------
// Action derivation — returns an ARRAY of buttons to render side-by-side,
// each with its own kind + variant + optional confirm payload. The two
// axes (connection / pair) are independent, so most states surface two
// buttons (one per axis) instead of a single primary action. Destructive
// actions carry a `confirm` block that the UI uses to prompt the user.
//
// State matrix:
//   connected + paired       → [Desconectar (confirm), Desemparelhar (confirm)]
//   connected + unpaired     → [Desconectar (confirm), Emparelhar]
//   disconnected + paired    → [Conectar, Desemparelhar (confirm)]
//   disconnected + unpaired  → [Conectar, Emparelhar]
//   connecting / pairing     → [] (in progress, nothing actionable)
// ---------------------------------------------------------------------------
const KIND_CONNECT = 'connect';
const KIND_DISCONNECT = 'disconnect';
const KIND_PAIR = 'pair';
const KIND_UNPAIR = 'unpair';

function actionConnect(t) {
  return {
    kind: KIND_CONNECT,
    label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.CONNECT'),
    variant: 'primary',
    disabled: false,
  };
}

function actionDisconnect(t) {
  return {
    kind: KIND_DISCONNECT,
    label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.DISCONNECT_ACTION'),
    variant: 'destructive',
    disabled: false,
    confirm: {
      title: t('INBOX_MGMT.PROPRIACLOUD_STATUS.DISCONNECT_CONFIRM_TITLE'),
      message: t('INBOX_MGMT.PROPRIACLOUD_STATUS.DISCONNECT_CONFIRM_MESSAGE'),
      ok: t('INBOX_MGMT.PROPRIACLOUD_STATUS.DISCONNECT_ACTION'),
    },
  };
}

function actionPair(t) {
  return {
    kind: KIND_PAIR,
    label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.PAIR'),
    variant: 'primary',
    disabled: false,
  };
}

function actionUnpair(t) {
  return {
    kind: KIND_UNPAIR,
    label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.UNPAIR_ACTION'),
    variant: 'destructive',
    disabled: false,
    confirm: {
      title: t('INBOX_MGMT.PROPRIACLOUD_STATUS.UNPAIR_CONFIRM_TITLE'),
      message: t('INBOX_MGMT.PROPRIACLOUD_STATUS.UNPAIR_CONFIRM_MESSAGE'),
      ok: t('INBOX_MGMT.PROPRIACLOUD_STATUS.UNPAIR_ACTION'),
    },
  };
}

function deriveActions(t, state) {
  const { isWebSocketConnected, isPaired, isPairing, connectionState } = state;
  if (connectionState === 'connecting' || isPairing) return [];

  const result = [];
  result.push(isWebSocketConnected ? actionDisconnect(t) : actionConnect(t));
  result.push(isPaired ? actionUnpair(t) : actionPair(t));
  return result;
}

// ---------------------------------------------------------------------------
// Tag → chip view-model with i18n applied. Shape matches what the
// templates render: { label, chipClass, dotClass }.
// ---------------------------------------------------------------------------
function tagView(tagDict, key, t) {
  const def = tagDict[key];
  return {
    key,
    label: t(def.labelKey),
    chipClass: def.chipClass,
    dotClass: def.dotClass,
  };
}

// ---------------------------------------------------------------------------
// Pure resolver — works against any inbox-shaped object and a t() fn.
// Returns:
//   isPropriacloud — gate so non-propriacloud inboxes render nothing
//   connection / pair / ready — chip view-models for each tag set
//   action — { kind, label, disabled } for the primary button
//   raw flags for callers that need finer control
// ---------------------------------------------------------------------------
export function resolvePropriacloudStatus(inbox, t = key => key) {
  const isPropriacloud =
    inbox?.channel_type === 'Channel::Whatsapp' &&
    inbox?.provider === 'propriacloud';
  const state = extractState(inbox);
  const error = inbox?.provider_connection?.error || null;

  const connectionKey = resolveConnectionTag(state.connectionState);
  const pairKey = resolvePairTag(state.pairState, state.isPaired);
  const readyKey = resolveReadyTag(state.isReady, state.isWebSocketConnected);

  return {
    isPropriacloud,
    error,
    state,
    connection: tagView(connectionTags, connectionKey, t),
    pair: tagView(pairTags, pairKey, t),
    ready: tagView(readyTags, readyKey, t),
    actions: deriveActions(t, state),
  };
}

// ---------------------------------------------------------------------------
// Vue 3 setup() composable wrapping the pure resolver in computed refs.
// ---------------------------------------------------------------------------
export function usePropriacloudStatus(inboxRef, options = {}) {
  const t = options.t || (key => key);
  const resolved = computed(() => resolvePropriacloudStatus(inboxRef.value, t));
  return {
    isPropriacloud: computed(() => resolved.value.isPropriacloud),
    state: computed(() => resolved.value.state),
    error: computed(() => resolved.value.error),
    connection: computed(() => resolved.value.connection),
    pair: computed(() => resolved.value.pair),
    ready: computed(() => resolved.value.ready),
    actions: computed(() => resolved.value.actions),
  };
}
