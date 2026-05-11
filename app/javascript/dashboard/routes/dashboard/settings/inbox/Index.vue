<script setup>
import { computed, ref, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@scmmishra/pico-search';
import Avatar from 'next/avatar/Avatar.vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import {
  useMapGetter,
  useStoreGetters,
  useStore,
} from 'dashboard/composables/store';
import ChannelName from './components/ChannelName.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { resolvePropriacloudStatus } from 'dashboard/composables/usePropriacloudStatus';
import { usePropriacloudLiveStream } from 'dashboard/composables/usePropriacloudLiveStream';
import { ref as vueRef, watch } from 'vue';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

const showDeletePopup = ref(false);
const selectedInbox = ref({});
const searchQuery = ref('');

const inboxes = useMapGetter('inboxes/getInboxes');

const inboxesList = computed(() => {
  return inboxes.value?.slice().sort((a, b) => a.name.localeCompare(b.name));
});

const filteredInboxesList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return inboxesList.value;
  return picoSearch(inboxesList.value, query, ['name', 'channel_type']);
});

const uiFlags = computed(() => getters['inboxes/getUIFlags'].value);

const deleteConfirmText = computed(
  () => `${t('INBOX_MGMT.DELETE.CONFIRM.YES')} ${selectedInbox.value.name}`
);

const deleteRejectText = computed(
  () => `${t('INBOX_MGMT.DELETE.CONFIRM.NO')} ${selectedInbox.value.name}`
);

const confirmDeleteMessage = computed(
  () => `${t('INBOX_MGMT.DELETE.CONFIRM.MESSAGE')} ${selectedInbox.value.name}?`
);
const confirmPlaceHolderText = computed(
  () =>
    `${t('INBOX_MGMT.DELETE.CONFIRM.PLACE_HOLDER', {
      inboxName: selectedInbox.value.name,
    })}`
);

const deleteInbox = async ({ id }) => {
  try {
    await store.dispatch('inboxes/delete', id);
    useAlert(t('INBOX_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.DELETE.API.ERROR_MESSAGE'));
  }
};
const closeDelete = () => {
  showDeletePopup.value = false;
  selectedInbox.value = {};
};

const confirmDeletion = () => {
  deleteInbox(selectedInbox.value);
  closeDelete();
};
const openDelete = inbox => {
  showDeletePopup.value = true;
  selectedInbox.value = inbox;
};

// Resolved propriacloud status per inbox (cached by inbox id so we
// don't re-resolve on every re-render). `null` for non-propriacloud
// inboxes — the template gates rendering on `.isPropriacloud`.
const propriacloudFor = inbox => resolvePropriacloudStatus(inbox, t);

// Live updates for propriacloud inboxes in the list. One
// `usePropriacloudLiveStream` per propriacloud inbox — opens an SSE
// connection to /audit_stream + polls as fallback. Backend
// rate-limits refreshes (60s hard / 5s soft per channel) so spam is
// impossible even with many open inboxes. The composable tears down
// automatically on unmount.
const accountId = computed(() => getters.getCurrentAccountId.value);
const liveStreams = vueRef(new Map()); // inboxId → { stop }

const ensureLiveStreams = () => {
  const seen = new Set();
  (inboxesList.value || [])
    .filter(i => i?.provider === 'propriacloud')
    .forEach(inbox => {
      seen.add(inbox.id);
      if (liveStreams.value.has(inbox.id)) return;
      const inboxRef = computed(
        () => (inboxes.value || []).find(i => i?.id === inbox.id) || null
      );
      const handle = usePropriacloudLiveStream(inboxRef, {
        store,
        accountId: accountId.value,
        pollIntervalMs: 15000,
      });
      liveStreams.value.set(inbox.id, handle);
    });
  // Tear down streams for inboxes no longer in the list (deleted /
  // converted to another provider).
  [...liveStreams.value.keys()].forEach(id => {
    if (!seen.has(id)) {
      liveStreams.value.get(id).stop();
      liveStreams.value.delete(id);
    }
  });
};

watch(inboxesList, ensureLiveStreams, { immediate: true });
onBeforeUnmount(() => {
  liveStreams.value.forEach(h => h.stop());
  liveStreams.value.clear();
});
</script>

<template>
  <SettingsLayout
    :no-records-found="!inboxesList.length"
    :no-records-message="$t('INBOX_MGMT.LIST.404')"
    :is-loading="uiFlags.isFetching"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('INBOX_MGMT.HEADER')"
        :description="$t('INBOX_MGMT.DESCRIPTION')"
        :link-text="$t('INBOX_MGMT.LEARN_MORE')"
        :search-placeholder="$t('INBOX_MGMT.SEARCH_PLACEHOLDER')"
        feature-name="inboxes"
      >
        <template v-if="inboxesList?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('INBOX_MGMT.COUNT', { n: inboxesList.length }) }}
          </span>
        </template>
        <template #actions>
          <router-link v-if="isAdmin" :to="{ name: 'settings_inbox_new' }">
            <Button :label="$t('SETTINGS.INBOXES.NEW_INBOX')" size="sm" />
          </router-link>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <span
        v-if="!filteredInboxesList.length && searchQuery"
        class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
      >
        {{ $t('INBOX_MGMT.NO_RESULTS') }}
      </span>
      <div v-else class="divide-y divide-n-weak border-t border-n-weak">
        <div
          v-for="inbox in filteredInboxesList"
          :key="inbox.id"
          class="flex justify-between flex-row items-start gap-4 py-4"
        >
          <div class="flex items-center gap-4">
            <div
              v-if="inbox.avatar_url"
              class="bg-n-alpha-3 rounded-xl size-10 ring ring-n-solid-1 border border-n-strong shadow-sm grid place-items-center"
            >
              <Avatar
                :src="inbox.avatar_url"
                :name="inbox.name"
                :size="24"
                rounded-full
              />
            </div>
            <div
              v-else
              class="size-10 justify-center bg-n-alpha-3 rounded-xl ring ring-n-solid-1 border border-n-strong shadow-sm grid place-items-center"
            >
              <ChannelIcon class="size-6 text-n-slate-10" :inbox="inbox" />
            </div>
            <div class="flex flex-col items-start gap-1">
              <span class="block text-heading-3 text-n-slate-12 capitalize">
                {{ inbox.name }}
              </span>
              <ChannelName
                :channel-type="inbox.channel_type"
                :medium="inbox.medium"
                class="text-body-main text-n-slate-11"
                :provider="inbox.provider"
              />
            </div>
          </div>
          <div class="flex gap-3 justify-end items-center">
            <!-- Propriacloud-only: live connection + pair chips, same
                 component as the Informações tab. Renders just before
                 the row actions so admins can scan the inbox list and
                 see at a glance which numbers are connected/paired
                 vs. need attention. -->
            <template v-if="propriacloudFor(inbox).isPropriacloud">
              <div class="flex items-center gap-1 flex-wrap">
                <span
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-xxs font-medium border rounded-full"
                  :class="propriacloudFor(inbox).connection.chipClass"
                >
                  <span
                    class="w-1.5 h-1.5 rounded-full"
                    :class="propriacloudFor(inbox).connection.dotClass"
                  />
                  {{ propriacloudFor(inbox).connection.label }}
                </span>
                <span
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-xxs font-medium border rounded-full"
                  :class="propriacloudFor(inbox).pair.chipClass"
                >
                  <span
                    class="w-1.5 h-1.5 rounded-full"
                    :class="propriacloudFor(inbox).pair.dotClass"
                  />
                  {{ propriacloudFor(inbox).pair.label }}
                </span>
              </div>
            </template>
            <router-link
              :to="{
                name: 'settings_inbox_show',
                params: { inboxId: inbox.id },
              }"
            >
              <Button
                v-if="isAdmin"
                v-tooltip.top="$t('INBOX_MGMT.SETTINGS')"
                icon="i-woot-settings"
                slate
                sm
              />
            </router-link>
            <Button
              v-if="isAdmin"
              v-tooltip.top="$t('INBOX_MGMT.DELETE.BUTTON_TEXT')"
              icon="i-woot-bin"
              slate
              sm
              class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
              @click="openDelete(inbox)"
            />
          </div>
        </div>
      </div>
    </template>

    <woot-confirm-delete-modal
      v-if="showDeletePopup"
      v-model:show="showDeletePopup"
      :title="$t('INBOX_MGMT.DELETE.CONFIRM.TITLE')"
      :message="confirmDeleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
      :confirm-value="selectedInbox.name"
      :confirm-place-holder-text="confirmPlaceHolderText"
      @on-confirm="confirmDeletion"
      @on-close="closeDelete"
    />
  </SettingsLayout>
</template>
