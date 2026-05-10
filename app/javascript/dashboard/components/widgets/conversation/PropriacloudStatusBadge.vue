<script setup>
import { computed, watch, toRef } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { usePropriacloudStatus } from 'dashboard/composables/usePropriacloudStatus';

// Inline status pill rendered next to the InboxName on every
// conversation header. Only shows for propriacloud channels.
// Status taxonomy + label/color logic is centralized in
// usePropriacloudStatus so badge + Settings panel render the same
// thing. See app/javascript/dashboard/composables/usePropriacloudStatus.js.
const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
const inboxRef = toRef(props, 'inbox');
const { isPropriacloud, status, error } = usePropriacloudStatus(inboxRef, {
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
    :class="status.chipClass"
  >
    <span class="w-1.5 h-1.5 rounded-full" :class="status.dotClass" />
    {{ status.label }}
  </span>
</template>
