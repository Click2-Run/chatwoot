// Two-axis status resolver for the propriacloud whatsapp-api provider,
// modelled directly on propriacloud.git/apps/minha/app/components/whatsapp/instance-tags.ts
// and the documented state matrix at /api/v1/instances/status.
//
// State matrix (Web mode, waba=false):
//   connection_state | pair_state | meaning                         | next action
//   ---------------- | ---------- | ------------------------------- | ------------
//   connected        | paired     | ready (Conectada e emparelhada) | Desemparelhar
//   connected        | pairing    | awaiting QR/phone confirmation  | (in progress)
//   connected        | unpaired   | online but not paired           | Emparelhar
//   connecting       | any        | bringing the websocket up       | (in progress)
//   disconnected     | paired     | session paired but offline      | Conectar (reconnect-only)
//   disconnected     | unpaired   | not paired, not connected       | Emparelhar

import { computed } from 'vue';

// Legacy provider_connection.connection (open/close/connecting/reconnecting)
// → API connection_state vocabulary so resolver works against pre-refresh
// records that haven't been hit by refresh_status_from_api! yet.
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

function deriveStatus(t, flags) {
  const { isReady, isConnecting, isPairing, isConnected, isPaired } = flags;
  if (isReady) {
    return {
      key: 'ready',
      label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.READY'),
      dotClass: 'bg-green-500',
      chipClass: 'text-green-700 bg-green-50 border-green-200',
    };
  }
  if (isConnecting || isPairing) {
    return {
      key: 'connecting',
      label: isPairing
        ? t('INBOX_MGMT.PROPRIACLOUD_STATUS.PAIRING')
        : t('INBOX_MGMT.PROPRIACLOUD_STATUS.CONNECTING'),
      dotClass: 'bg-amber-500 animate-pulse',
      chipClass: 'text-amber-700 bg-amber-50 border-amber-200',
    };
  }
  if (isConnected && !isPaired) {
    return {
      key: 'connected_unpaired',
      label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.CONNECTED_UNPAIRED'),
      dotClass: 'bg-amber-500',
      chipClass: 'text-amber-700 bg-amber-50 border-amber-200',
    };
  }
  if (isPaired && !isConnected) {
    return {
      key: 'paired_offline',
      label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.PAIRED_OFFLINE'),
      dotClass: 'bg-amber-500',
      chipClass: 'text-amber-700 bg-amber-50 border-amber-200',
    };
  }
  return {
    key: 'disconnected',
    label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.DISCONNECTED'),
    dotClass: 'bg-red-500',
    chipClass: 'text-red-700 bg-red-50 border-red-200',
  };
}

function deriveAction(t, flags) {
  const { isReady, isConnecting, isPairing, isConnected, isPaired } = flags;
  if (isPairing || isConnecting) {
    return {
      kind: 'in_progress',
      label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.IN_PROGRESS'),
      disabled: true,
    };
  }
  if (isReady) {
    return {
      kind: 'unpair',
      label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.DISCONNECT'),
      disabled: false,
    };
  }
  if (isPaired && !isConnected) {
    return {
      kind: 'connect',
      label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.CONNECT'),
      disabled: false,
    };
  }
  return {
    kind: 'pair',
    label: t('INBOX_MGMT.PROPRIACLOUD_STATUS.PAIR'),
    disabled: false,
  };
}

// Pure resolver — works against any inbox-shaped object and a t() fn.
// Used both from Vue 3 setup() (via usePropriacloudStatus composable)
// and from Vue 2 options-API computed properties.
export function resolvePropriacloudStatus(inbox, t = key => key) {
  const isPropriacloud =
    inbox?.channel_type === 'Channel::Whatsapp' &&
    inbox?.provider === 'propriacloud';
  const pc = inbox?.provider_connection || {};
  const connectionState =
    pc.connection_state || mapLegacyConnection(pc.connection);
  const pairState = pc.pair_state || legacyPairState(pc);
  const error = pc.error || null;

  const isConnected = connectionState === 'connected';
  const isConnecting = connectionState === 'connecting';
  const isPaired = pairState === 'paired';
  const isPairing = pairState === 'pairing';
  const isReady = isConnected && isPaired;
  const flags = { isReady, isConnecting, isPairing, isConnected, isPaired };

  return {
    isPropriacloud,
    connectionState,
    pairState,
    error,
    isConnected,
    isConnecting,
    isPaired,
    isPairing,
    isReady,
    status: deriveStatus(t, flags),
    action: deriveAction(t, flags),
  };
}

export function usePropriacloudStatus(inboxRef, options = {}) {
  const t = options.t || (key => key);
  const resolved = computed(() => resolvePropriacloudStatus(inboxRef.value, t));
  return {
    isPropriacloud: computed(() => resolved.value.isPropriacloud),
    connectionState: computed(() => resolved.value.connectionState),
    pairState: computed(() => resolved.value.pairState),
    error: computed(() => resolved.value.error),
    isConnected: computed(() => resolved.value.isConnected),
    isConnecting: computed(() => resolved.value.isConnecting),
    isPaired: computed(() => resolved.value.isPaired),
    isPairing: computed(() => resolved.value.isPairing),
    isReady: computed(() => resolved.value.isReady),
    status: computed(() => resolved.value.status),
    action: computed(() => resolved.value.action),
  };
}
