/* global axios */
import ApiClient from './ApiClient';

class DealsAPI extends ApiClient {
  constructor() {
    super('deals', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new DealsAPI();
