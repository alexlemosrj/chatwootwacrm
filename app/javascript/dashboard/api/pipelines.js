/* global axios */
import ApiClient from './ApiClient';

class PipelinesAPI extends ApiClient {
  constructor() {
    super('pipelines', { accountScoped: true });
  }

  getStages(pipelineId) {
    return axios.get(`${this.url}/${pipelineId}/pipeline_stages`);
  }

  createStage(pipelineId, data) {
    return axios.post(`${this.url}/${pipelineId}/pipeline_stages`, {
      pipeline_stage: data,
    });
  }

  updateStage(pipelineId, stageId, data) {
    return axios.patch(`${this.url}/${pipelineId}/pipeline_stages/${stageId}`, {
      pipeline_stage: data,
    });
  }

  deleteStage(pipelineId, stageId) {
    return axios.delete(`${this.url}/${pipelineId}/pipeline_stages/${stageId}`);
  }
}

export default new PipelinesAPI();
