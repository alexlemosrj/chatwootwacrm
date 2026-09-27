/* global axios */
import ApiClient from './ApiClient';

class CrmEventsAPI extends ApiClient {
  constructor() {
    super('crm_events', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new CrmEventsAPI();
