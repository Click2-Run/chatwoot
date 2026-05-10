<script setup>
import { computed, watch } from 'vue';
import { useStore } from 'vuex';

// Tiny status pill that surfaces the propriacloud instance's
// connection state inline in the conversation header (next to the
// InboxName). Reads from inbox.provider_connection — the same field
// the Inbox Settings panel uses — so the live tail webhook updates
// it automatically. Renders nothing for non-propriacloud channels.
//
// Visual taxonomy mirrors propriacloud.git's connectionTags + pairTags
// (apps/minha/app/components/whatsapp/instance-tags.ts):
//   open / paired.success  → green   "Conectada"
//   connecting             → amber   "Conectando"
//   reconnecting           → amber+pulse "Reconectando"
//   close + error          → red     "Desconectada" + tooltip
const props = defineProps({
  inbox: { type: Object, required: true },
});

const isPropriacloud = computed(
  () =>
    props.inbox?.channel_type === 'Channel::Whatsapp' &&
    props.inbox?.provider === 'propriacloud'
);

// Reconcile the cached provider_connection with API truth whenever
// the conversation header surfaces a propriacloud inbox. Backend
// rate-limits to 1/30s per channel, so opening multiple conversations
// on the same inbox in rapid succession only hits the upstream once.
const store = useStore();
const triggerRefresh = inboxId => {
  if (!inboxId) return;
  store.dispatch('inboxes/refreshProviderStatus', inboxId);
};
watch(
  () => [isPropriacloud.value, props.inbox?.id],
  ([isPC, id]) => {
    if (isPC) triggerRefresh(id);
  },
  { immediate: true }
);

const connection = computed(() => props.inbox?.provider_connection?.connection);
const error = computed(() => props.inbox?.provider_connection?.error);

const variant = computed(() => {
  if (connection.value === 'open') return 'connected';
  if (connection.value === 'connecting') return 'connecting';
  if (connection.value === 'reconnecting') return 'reconnecting';
  return 'disconnected';
});

const i18nKey = computed(() => {
  switch (variant.value) {
    case 'connected':
      return 'INBOX_MGMT.PROPRIACLOUD_STATUS.CONNECTED';
    case 'connecting':
      return 'INBOX_MGMT.PROPRIACLOUD_STATUS.CONNECTING';
    case 'reconnecting':
      return 'INBOX_MGMT.PROPRIACLOUD_STATUS.RECONNECTING';
    default:
      return 'INBOX_MGMT.PROPRIACLOUD_STATUS.DISCONNECTED';
  }
});

const dotClass = computed(() => {
  switch (variant.value) {
    case 'connected':
      return 'bg-green-500';
    case 'connecting':
      return 'bg-amber-500';
    case 'reconnecting':
      return 'bg-amber-500 animate-pulse';
    default:
      return 'bg-red-500';
  }
});

const containerClass = computed(() => {
  switch (variant.value) {
    case 'connected':
      return 'text-green-700 bg-green-50 border-green-200';
    case 'connecting':
    case 'reconnecting':
      return 'text-amber-700 bg-amber-50 border-amber-200';
    default:
      return 'text-red-700 bg-red-50 border-red-200';
  }
});
</script>

<template>
  <span
    v-if="isPropriacloud"
    :title="error || ''"
    class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xxs font-medium border rounded-full"
    :class="containerClass"
  >
    <span class="w-1.5 h-1.5 rounded-full" :class="dotClass" />
    {{ $t(i18nKey) }}
  </span>
</template>
