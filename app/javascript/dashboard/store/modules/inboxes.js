import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import * as types from '../mutation-types';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import InboxesAPI from '../../api/inboxes';
import WebChannel from '../../api/channel/webChannel';
import FBChannel from '../../api/channel/fbChannel';
import TwilioChannel from '../../api/channel/twilioChannel';
import WhatsappChannel from '../../api/channel/whatsappChannel';
import { throwErrorMessage } from '../utils/api';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import camelcaseKeys from 'camelcase-keys';
import { ACCOUNT_EVENTS } from '../../helper/AnalyticsHelper/events';
import { channelActions, buildInboxData } from './inboxes/channelActions';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isFetchingItem: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
    isUpdatingIMAP: false,
    isUpdatingSMTP: false,
  },
};

export const getters = {
  getInboxes($state) {
    return $state.records;
  },
  getAllInboxes($state) {
    return camelcaseKeys($state.records, { deep: true });
  },
  getWhatsAppTemplates: $state => inboxId => {
    const [inbox] = $state.records.filter(
      record => record.id === Number(inboxId)
    );

    const {
      message_templates: whatsAppMessageTemplates,
      additional_attributes: additionalAttributes,
    } = inbox || {};

    const { message_templates: apiInboxMessageTemplates } =
      additionalAttributes || {};
    const messagesTemplates =
      whatsAppMessageTemplates || apiInboxMessageTemplates;

    return messagesTemplates;
  },
  getFilteredWhatsAppTemplates: $state => inboxId => {
    const [inbox] = $state.records.filter(
      record => record.id === Number(inboxId)
    );

    const {
      message_templates: whatsAppMessageTemplates,
      additional_attributes: additionalAttributes,
    } = inbox || {};

    const { message_templates: apiInboxMessageTemplates } =
      additionalAttributes || {};
    const templates = whatsAppMessageTemplates || apiInboxMessageTemplates;

    if (!templates || !Array.isArray(templates)) {
      return [];
    }

    return templates.filter(template => {
      // Ensure template has required properties
      if (!template || !template.status || !template.components) {
        return false;
      }

      // Only show approved templates
      if (template.status.toLowerCase() !== 'approved') {
        return false;
      }

      // Filter out authentication templates
      if (template.category === 'AUTHENTICATION') {
        return false;
      }

      // Filter out CSAT templates (customer_satisfaction_survey and its versions)
      if (
        template.name &&
        template.name.startsWith('customer_satisfaction_survey')
      ) {
        return false;
      }

      // Filter out interactive templates (LIST, PRODUCT, CATALOG), location templates, and call permission templates
      const hasUnsupportedComponents = template.components.some(
        component =>
          ['LIST', 'PRODUCT', 'CATALOG', 'CALL_PERMISSION_REQUEST'].includes(
            component.type
          ) ||
          (component.type === 'HEADER' && component.format === 'LOCATION')
      );

      if (hasUnsupportedComponents) {
        return false;
      }

      return true;
    });
  },
  getNewConversationInboxes($state) {
    return $state.records.filter(inbox => {
      const { channel_type: channelType, phone_number: phoneNumber = '' } =
        inbox;

      const isEmailChannel = channelType === INBOX_TYPES.EMAIL;
      const isSmsChannel =
        channelType === INBOX_TYPES.TWILIO &&
        phoneNumber.startsWith('whatsapp');
      return isEmailChannel || isSmsChannel;
    });
  },
  getInbox: $state => inboxId => {
    const [inbox] = $state.records.filter(
      record => record.id === Number(inboxId)
    );
    return inbox || {};
  },
  getInboxById: $state => inboxId => {
    const [inbox] = $state.records.filter(
      record => record.id === Number(inboxId)
    );
    return camelcaseKeys(inbox || {}, { deep: true });
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getWebsiteInboxes($state) {
    return $state.records.filter(item => item.channel_type === INBOX_TYPES.WEB);
  },
  getTwilioInboxes($state) {
    return $state.records.filter(
      item => item.channel_type === INBOX_TYPES.TWILIO
    );
  },
  getSMSInboxes($state) {
    return $state.records.filter(
      item =>
        item.channel_type === INBOX_TYPES.SMS ||
        (item.channel_type === INBOX_TYPES.TWILIO && item.medium === 'sms')
    );
  },
  getWhatsAppInboxes($state) {
    return $state.records.filter(
      item => item.channel_type === INBOX_TYPES.WHATSAPP
    );
  },
  dialogFlowEnabledInboxes($state) {
    return $state.records.filter(
      item => item.channel_type !== INBOX_TYPES.EMAIL
    );
  },
  getFacebookInboxByInstagramId: $state => instagramId => {
    return $state.records.find(
      item =>
        item.instagram_id === instagramId &&
        item.channel_type === INBOX_TYPES.FB
    );
  },
  getInstagramInboxByInstagramId: $state => instagramId => {
    return $state.records.find(
      item =>
        item.instagram_id === instagramId &&
        item.channel_type === INBOX_TYPES.INSTAGRAM
    );
  },
  getTiktokInboxByBusinessId: $state => businessId => {
    return $state.records.find(
      item =>
        item.business_id === businessId &&
        item.channel_type === INBOX_TYPES.TIKTOK
    );
  },
};

const sendAnalyticsEvent = channelType => {
  AnalyticsHelper.track(ACCOUNT_EVENTS.ADDED_AN_INBOX, {
    channelType,
  });
};

export const actions = {
  revalidate: async ({ commit }, { newKey }) => {
    try {
      const isExistingKeyValid = await InboxesAPI.validateCacheKey(newKey);
      if (!isExistingKeyValid) {
        const response = await InboxesAPI.refetchAndCommit(newKey);
        commit(types.default.SET_INBOXES, response.data.payload);
      }
    } catch (error) {
      // Ignore error
    }
  },
  get: async ({ commit }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isFetching: true });
    try {
      const response = await InboxesAPI.get(true);
      commit(types.default.SET_INBOXES_UI_FLAG, { isFetching: false });
      commit(types.default.SET_INBOXES, response.data.payload);
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isFetching: false });
    }
  },
  createChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await WebChannel.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      const { channel = {} } = params;
      sendAnalyticsEvent(channel.type);
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      return throwErrorMessage(error);
    }
  },
  createWebsiteChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await WebChannel.create(buildInboxData(params));
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('website');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      return throwErrorMessage(error);
    }
  },
  createTwilioChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await TwilioChannel.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('twilio');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw error;
    }
  },
  createFBChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await FBChannel.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('facebook');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw new Error(error);
    }
  },
  createWhatsAppEmbeddedSignup: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await WhatsappChannel.createEmbeddedSignup(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('whatsapp');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw error;
    }
  },
  ...channelActions,
  // TODO: Extract other create channel methods to separate files to reduce file size
  // - createChannel
  // - createWebsiteChannel
  // - createTwilioChannel
  // - createFBChannel
  updateInbox: async ({ commit }, { id, formData = true, ...inboxParams }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: true });
    try {
      const response = await InboxesAPI.update(
        id,
        formData ? buildInboxData(inboxParams) : inboxParams
      );
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
      throwErrorMessage(error);
    }
  },
  convertProvider: async (
    { commit },
    { inboxId, provider, providerConfig }
  ) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: true });
    try {
      const response = await InboxesAPI.convertProvider(inboxId, {
        provider,
        providerConfig,
      });
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
      return throwErrorMessage(error);
    }
  },
  updateInboxIMAP: async ({ commit }, { id, ...inboxParams }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: true });
    try {
      const response = await InboxesAPI.update(id, inboxParams);
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: false });
      throwErrorMessage(error);
    }
  },
  updateInboxSMTP: async ({ commit }, { id, ...inboxParams }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: true });
    try {
      const response = await InboxesAPI.update(id, inboxParams);
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: false });
      throwErrorMessage(error);
    }
  },
  delete: async ({ commit }, inboxId) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isDeleting: true });
    try {
      await InboxesAPI.delete(inboxId);
      commit(types.default.DELETE_INBOXES, inboxId);
      commit(types.default.SET_INBOXES_UI_FLAG, { isDeleting: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isDeleting: false });
      throw new Error(error);
    }
  },
  reauthorizeFacebookPage: async ({ commit }, params) => {
    try {
      const response = await FBChannel.reauthorizeFacebookPage(params);
      commit(types.default.EDIT_INBOXES, response.data);
    } catch (error) {
      throw new Error(error.message);
    }
  },
  deleteInboxAvatar: async (_, inboxId) => {
    try {
      await InboxesAPI.deleteInboxAvatar(inboxId);
    } catch (error) {
      throw new Error(error);
    }
  },
  syncTemplates: async (_, inboxId) => {
    try {
      await InboxesAPI.syncTemplates(inboxId);
    } catch (error) {
      throw new Error(error);
    }
  },
  createCSATTemplate: async (_, { inboxId, template }) => {
    const response = await InboxesAPI.createCSATTemplate(inboxId, template);
    return response.data;
  },
  getCSATTemplateStatus: async (_, { inboxId }) => {
    const response = await InboxesAPI.getCSATTemplateStatus(inboxId);
    return response.data;
  },
  analyzeCSATTemplateUtility: async (_, { inboxId, template }) => {
    const response = await InboxesAPI.analyzeCSATTemplateUtility(
      inboxId,
      template
    );
    return response.data;
  },
  resetSecret: async ({ commit }, inboxId) => {
    try {
      const response = await InboxesAPI.resetSecret(inboxId);
      commit(types.default.EDIT_INBOXES, response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      return null;
    }
  },
  linkCSATTemplate: async (_, { inboxId, template }) => {
    const response = await InboxesAPI.linkCSATTemplate(inboxId, template);
    return response.data;
  },
  getAvailableCSATTemplates: async (_, { inboxId }) => {
    const response = await InboxesAPI.getAvailableCSATTemplates(inboxId);
    return response.data;
  },
  // Optional second arg can be either a plain inboxId (legacy callers)
  // or { inboxId, fetch_qr } so the propriacloud phone-code flow can
  // ensure the instance is connecting WITHOUT triggering a QR pull —
  // pulling a QR counts as a pair attempt and burns the WhatsApp
  // rate-limit budget that the phone-code request needs.
  setupChannelProvider: async (_, payload) => {
    const inboxId = typeof payload === 'object' ? payload.inboxId : payload;
    const params =
      typeof payload === 'object' && 'fetch_qr' in payload
        ? { fetch_qr: payload.fetch_qr }
        : {};
    try {
      await InboxesAPI.setupChannelProvider(inboxId, params);
    } catch (error) {
      // Backend now returns 422 with a friendly { error, code } payload.
      // Surface that string as a plain Error so the modal can render
      // it cleanly instead of leaking raw axios shape (status code, etc.).
      const data = error?.response?.data || {};
      const friendly =
        data.error || 'Could not start pairing. Please try again in a moment.';
      throw new Error(friendly);
    }
  },
  disconnectChannelProvider: async (_, inboxId) => {
    try {
      await InboxesAPI.disconnectChannelProvider(inboxId);
    } catch (error) {
      throwErrorMessage(error);
    }
  },
  pairQrcode: async ({ dispatch }, inboxId) => {
    try {
      const response = await InboxesAPI.pairQrcode(inboxId);
      return response.data;
    } catch (error) {
      const data = error?.response?.data || {};
      const friendly =
        data.error || 'Could not generate a QR code. Please try again.';
      // "client already logged in" / "already paired" from the API
      // means our local Vuex inbox snapshot is stale (the device IS
      // paired but the UI thinks it isn't, so Emparelhar was clickable).
      // Force a status refresh so the chip flips to "Emparelhada" and
      // the button row reflects truth on the very next render.
      if (/already logged in|already paired|already.*pair/i.test(friendly)) {
        dispatch('refreshProviderStatus', inboxId);
      }
      const wrapped = new Error(friendly);
      wrapped.code = data.code;
      wrapped.cooldownSeconds = data.cooldown_seconds;
      wrapped.lockedUntil = data.locked_until;
      throw wrapped;
    }
  },
  pairPhoneCode: async ({ dispatch }, { inboxId, phone }) => {
    try {
      const response = await InboxesAPI.pairPhoneCode(inboxId, phone);
      return response.data;
    } catch (error) {
      // Backend maps known errors to a friendly
      // { error, code, cooldown_seconds, locked_until } payload.
      // Re-throw a plain Error whose .message is the user-safe text and
      // attach the structured fields on the error object so the modal
      // can render a countdown without leaking the raw axios shape.
      const data = error?.response?.data || {};
      const friendly =
        data.error ||
        'Could not request a pairing code. Please try again in a moment.';
      // Same defense as pairQrcode: "already logged in" means the
      // device IS paired and our cache is wrong — force a refresh.
      if (/already logged in|already paired|already.*pair/i.test(friendly)) {
        dispatch('refreshProviderStatus', inboxId);
      }
      const wrapped = new Error(friendly);
      wrapped.code = data.code;
      wrapped.cooldownSeconds = data.cooldown_seconds;
      wrapped.lockedUntil = data.locked_until;
      throw wrapped;
    }
  },
  // Lightweight Conectar — just brings the websocket up against an
  // existing instance. Distinct from setupChannelProvider (which would
  // also re-create the instance + re-register the webhook). Faithful
  // port of propriacloud.git/apps/minha::connectInstance.
  connectOnly: async (_, inboxId) => {
    try {
      await InboxesAPI.connectOnly(inboxId);
    } catch (error) {
      const friendly =
        error?.response?.data?.error ||
        'Could not connect the WhatsApp instance. Please try again.';
      throw new Error(friendly);
    }
  },
  // Graceful disconnect — keeps pair, just brings the websocket down.
  // Reverse with connectOnly.
  disconnectOnly: async (_, inboxId) => {
    try {
      await InboxesAPI.disconnectOnly(inboxId);
    } catch (error) {
      const friendly =
        error?.response?.data?.error ||
        'Could not disconnect the WhatsApp instance. Please try again.';
      throw new Error(friendly);
    }
  },
  // Unpair the device link but keep the instance. User must pair again
  // afterwards via QR or phone code.
  unpairOnly: async (_, inboxId) => {
    try {
      await InboxesAPI.unpairOnly(inboxId);
    } catch (error) {
      const friendly =
        error?.response?.data?.error ||
        'Could not unpair the WhatsApp device. Please try again.';
      throw new Error(friendly);
    }
  },
  // Pull the connected WhatsApp device's profile picture from the
  // propriacloud API and attach it to the inbox as the channel image
  // (Imagem do Canal). Async on the backend — returns immediately;
  // the avatar appears once Sidekiq finishes the download. The caller
  // is expected to refetch the inbox a few seconds later to see the
  // updated avatar_url.
  syncAvatarFromProvider: async (_, inboxId) => {
    try {
      const response = await InboxesAPI.syncAvatarFromProvider(inboxId);
      return response.data;
    } catch (error) {
      const friendly =
        error?.response?.data?.error ||
        'Could not sync the inbox avatar from WhatsApp. Please try again.';
      throw new Error(friendly);
    }
  },
  refreshProviderStatus: async (context, inboxId) => {
    try {
      const response = await InboxesAPI.refreshProviderStatus(inboxId);
      const { provider_connection: providerConnection } = response.data || {};
      if (!providerConnection) return null;
      const cached = context.state.records.find(i => i.id === inboxId);
      if (cached) {
        context.commit(types.default.SET_INBOXES_ITEM, {
          ...cached,
          provider_connection: providerConnection,
        });
      }
      return response.data;
    } catch (error) {
      // Refresh is best-effort — never block the UI on a backend hiccup.
      // eslint-disable-next-line no-console
      console.warn('refreshProviderStatus failed', error);
      return null;
    }
  },
};

export const mutations = {
  [types.default.SET_INBOXES_UI_FLAG]($state, uiFlag) {
    $state.uiFlags = { ...$state.uiFlags, ...uiFlag };
  },
  [types.default.SET_INBOXES]: MutationHelpers.set,
  [types.default.SET_INBOXES_ITEM]: MutationHelpers.setSingleRecord,
  [types.default.ADD_INBOXES]: MutationHelpers.create,
  [types.default.EDIT_INBOXES]: MutationHelpers.update,
  [types.default.DELETE_INBOXES]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
