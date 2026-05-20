// Real-time provider_connection updates for propriacloud inboxes.
//
// Tries the SSE proxy first (`GET /api/v1/accounts/:id/inboxes/:id/audit_stream`),
// falls back to a 10-15s poll if SSE is disabled upstream
// (AUDIT_SSE_ENABLED=false on whatsapp-api → 404/503) or the connection
// drops repeatedly. Either way, dispatches `inboxes/refreshProviderStatus`
// on every event so the Vuex inbox snapshot stays fresh and the UI
// re-renders without manual refresh.
//
// Usage (in any setup() / mounted() context that has access to a Vuex
// store and a reactive inbox ref):
//
//     const inboxRef = computed(() => store.getters['inboxes/getInbox'](id));
//     const { stop } = usePropriacloudLiveStream(inboxRef, { store, accountId });
//     onUnmounted(stop);
//
// Stops on unmount. Re-evaluates on every inbox change — if the watched
// inbox flips from propriacloud to another provider (e.g. convert_provider)
// the stream tears down automatically.

import { watch, onBeforeUnmount, isRef } from 'vue';

const POLL_INTERVAL_MS = 10000;
const SSE_BACKOFF_MS = 5000;
const SSE_MAX_BACKOFF_MS = 60000;

// Used to gate noisy console warnings — log once per session per inbox.
const warnedNoSse = new Set();

export function usePropriacloudLiveStream(inboxRef, options = {}) {
  const { store, accountId, pollIntervalMs = POLL_INTERVAL_MS } = options;
  if (!store) throw new Error('usePropriacloudLiveStream requires { store }');

  let eventSource = null;
  let pollId = null;
  let backoffMs = SSE_BACKOFF_MS;
  let active = false;
  let currentInboxId = null;

  const inboxOf = () => (isRef(inboxRef) ? inboxRef.value : inboxRef);

  const dispatchRefresh = () => {
    const inbox = inboxOf();
    if (!inbox?.id || inbox.provider !== 'propriacloud') return;
    store.dispatch('inboxes/refreshProviderStatus', inbox.id);
  };

  const startPoll = () => {
    if (pollId) return;
    pollId = setInterval(dispatchRefresh, pollIntervalMs);
  };
  const stopPoll = () => {
    if (pollId) {
      clearInterval(pollId);
      pollId = null;
    }
  };

  const closeStream = () => {
    if (eventSource) {
      try {
        eventSource.close();
      } catch (e) {
        // ignore — already closed
      }
      eventSource = null;
    }
  };

  const startSse = inbox => {
    if (!accountId) return false;
    if (
      typeof window === 'undefined' ||
      typeof window.EventSource === 'undefined'
    )
      return false;

    const url = `/api/v1/accounts/${accountId}/inboxes/${inbox.id}/audit_stream`;
    try {
      eventSource = new EventSource(url, { withCredentials: true });
    } catch (e) {
      return false;
    }

    let firstByteSeen = false;

    eventSource.addEventListener('open', () => {
      firstByteSeen = true;
      backoffMs = SSE_BACKOFF_MS; // reset on successful (re)connect
      stopPoll();
    });

    // Treat ANY message arriving from upstream as "something changed,
    // refresh." The audit stream carries connection/audit/heartbeat
    // events — a heartbeat is harmless to refresh on (rate-limited
    // backend will short-circuit) and saves us from parsing event
    // shapes that may evolve.
    const onAny = () => dispatchRefresh();
    eventSource.addEventListener('audit', onAny);
    eventSource.addEventListener('connection', onAny);
    eventSource.addEventListener('message', onAny); // default channel

    eventSource.addEventListener('error', () => {
      closeStream();
      // If we never received a single byte, upstream is probably 404
      // (AUDIT_SSE_ENABLED=false) — give up trying SSE for this inbox
      // and let the poll handle it. Warn ONCE per inbox per session.
      if (!firstByteSeen) {
        if (!warnedNoSse.has(inbox.id)) {
          warnedNoSse.add(inbox.id);
          // eslint-disable-next-line no-console
          console.info(
            `[propriacloud] audit_stream unavailable for inbox=${inbox.id} (upstream AUDIT_SSE_ENABLED likely false); falling back to polling.`
          );
        }
        startPoll();
        return;
      }
      // We had a working stream; assume transient — exponential backoff
      // then retry, but keep the poll going as the safety net in the
      // meantime so the UI stays warm.
      startPoll();
      setTimeout(() => {
        if (active && inboxOf()?.id === inbox.id) startSse(inboxOf());
      }, backoffMs);
      backoffMs = Math.min(backoffMs * 2, SSE_MAX_BACKOFF_MS);
    });

    return true;
  };

  const start = () => {
    if (active) return;
    const inbox = inboxOf();
    if (!inbox?.id || inbox.provider !== 'propriacloud') return;
    active = true;
    currentInboxId = inbox.id;

    // Always start the poll immediately so the page never sits stale
    // while we wait to see whether SSE is going to work. The poll
    // shuts off on the SSE `open` event and turns back on if the
    // stream errors out.
    startPoll();
    startSse(inbox);
  };

  const stop = () => {
    active = false;
    currentInboxId = null;
    closeStream();
    stopPoll();
  };

  // Tear down + re-start when the watched inbox changes (provider flip,
  // navigation between two propriacloud inboxes, etc.).
  watch(
    () => {
      const inbox = inboxOf();
      return [inbox?.id, inbox?.provider];
    },
    ([newId, newProvider]) => {
      if (newProvider !== 'propriacloud' || !newId) {
        stop();
        return;
      }
      if (newId !== currentInboxId) {
        stop();
        start();
      } else if (!active) {
        start();
      }
    },
    { immediate: true }
  );

  onBeforeUnmount(stop);

  return { stop };
}
