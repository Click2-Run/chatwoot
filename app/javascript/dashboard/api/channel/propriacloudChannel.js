/* global axios */
import ApiClient from '../ApiClient';

// Propria.Cloud Embedded Signup — bridge to minha.propria.cloud orchestrator.
// Counterpart server: app/controllers/api/v1/accounts/propriacloud/authorizations_controller.rb
class PropriacloudChannel extends ApiClient {
  constructor() {
    super('propriacloud', { accountScoped: true });
  }

  // POST /api/v1/accounts/{id}/propriacloud/authorization
  // Returns { success, session_id, minha_session_id, signup_url, instance_id }
  startEmbeddedSignup({
    tenantKey,
    inboxName,
    phoneNumber,
    markAsRead,
    prefill,
  } = {}) {
    return axios.post(`${this.baseUrl()}/propriacloud/authorization`, {
      tenant_key: tenantKey,
      inbox_name: inboxName,
      phone_number: phoneNumber,
      mark_as_read: markAsRead ?? true,
      prefill: prefill ?? {},
    });
  }
}

export default new PropriacloudChannel();
