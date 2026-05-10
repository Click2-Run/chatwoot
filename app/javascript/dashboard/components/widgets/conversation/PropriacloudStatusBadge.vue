<script setup>
import { computed, watch, toRef } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { usePropriacloudStatus } from 'dashboard/composables/usePropriacloudStatus';

// Compact single chip rendered next to the InboxName on every
// conversation header. Uses the `ready` taxonomy from
// propriacloud.git/apps/minha/instance-tags.ts (resolveReadyTag) which
// collapses connection × pair into 3 states tuned for tight space:
//   ready        (green)  — connected + paired
//   connected    (warning) — connected but not yet paired
//   disconnected (red)    — anything else
// The full two-axis breakdown (connection + pair badges) is shown on
// the Inbox Settings panel.
const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
const inboxRef = toRef(props, 'inbox');
const { isPropriacloud, ready, error } = usePropriacloudStatus(inboxRef, {
  t,
});

// Reconcile the cached provider_connection with the upstream API on
// inbox open. Backend rate-limits to 1/30s/channel so rapid navigation
// across conversations on the same inbox only hits the upstream once.
const store = useStore();
watch(
  () => [isPropriacloud.value, props.inbox?.id],
  ([isPC, id]) => {
    if (isPC && id) store.dispatch('inboxes/refreshProviderStatus', id);
  },
  { immediate: true }
);

const tooltip = computed(() => error.value || '');
</script>

<template>
  <span
    v-if="isPropriacloud"
    :title="tooltip"
    class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xxs font-medium border rounded-full"
    :class="ready.chipClass"
  >
    <span class="w-1.5 h-1.5 rounded-full" :class="ready.dotClass" />
    {{ ready.label }}
  </span>
</template>
