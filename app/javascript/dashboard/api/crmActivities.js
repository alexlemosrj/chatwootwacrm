/* global axios */
import ApiClient from './ApiClient';

class CrmActivitiesAPI extends ApiClient {
  constructor() {
    super('crm_activities', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new CrmActivitiesAPI();
