import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import PipelinesAPI from '../../api/pipelines';
import DealsAPI from '../../api/deals';

export const state = {
  records: [],
  deals: [],
  selectedPipelineId: null,
  uiFlags: {
    isFetching: false,
    isFetchingDeals: false,
    isCreating: false,
    isUpdating: false,
  },
};

export const getters = {
  getPipelines: _state => _state.records,
  getSelectedPipeline: _state =>
    _state.records.find(p => p.id === _state.selectedPipelineId) ||
    _state.records[0] ||
    null,
  getDeals: _state => _state.deals,
  getUIFlags: _state => _state.uiFlags,
  getDealsByStage: _state => stageId =>
    _state.deals.filter(
      d => d.pipeline_stage_id === stageId || d.stage_id === stageId
    ),
};

export const actions = {
  get: async function getPipelines({ commit, dispatch }) {
    commit(types.SET_PIPELINE_UI_FLAG, { isFetching: true });
    try {
      const response = await PipelinesAPI.get();
      const pipelines = response.data.payload || [];
      commit(types.SET_PIPELINES, pipelines);
      if (pipelines.length) {
        commit(types.SET_SELECTED_PIPELINE_ID, pipelines[0].id);
        await dispatch('getDeals', pipelines[0].id);
      }
    } finally {
      commit(types.SET_PIPELINE_UI_FLAG, { isFetching: false });
    }
  },

  selectPipeline: async function selectPipeline({ commit, dispatch }, id) {
    commit(types.SET_SELECTED_PIPELINE_ID, id);
    await dispatch('getDeals', id);
  },

  create: async function createPipeline({ commit }, { name }) {
    commit(types.SET_PIPELINE_UI_FLAG, { isCreating: true });
    try {
      const response = await PipelinesAPI.create({ pipeline: { name } });
      commit(types.ADD_PIPELINE, response.data);
      return response.data;
    } finally {
      commit(types.SET_PIPELINE_UI_FLAG, { isCreating: false });
    }
  },

  update: async function updatePipeline({ commit }, { id, ...updateObj }) {
    const response = await PipelinesAPI.update(id, { pipeline: updateObj });
    commit(types.EDIT_PIPELINE, response.data);
    return response.data;
  },

  delete: async function deletePipeline({ commit }, id) {
    await PipelinesAPI.delete(id);
    commit(types.DELETE_PIPELINE, id);
  },

  getDeals: async function getDeals({ commit }, pipelineId) {
    commit(types.SET_PIPELINE_UI_FLAG, { isFetchingDeals: true });
    try {
      const response = await DealsAPI.get({ pipeline_id: pipelineId });
      commit(types.SET_DEALS, response.data.payload || []);
    } finally {
      commit(types.SET_PIPELINE_UI_FLAG, { isFetchingDeals: false });
    }
  },

  createDeal: async function createDeal({ commit }, deal) {
    const response = await DealsAPI.create({ deal });
    commit(types.ADD_DEAL, response.data);
    return response.data;
  },

  updateDeal: async function updateDeal({ commit }, { id, ...updateObj }) {
    const response = await DealsAPI.update(id, { deal: updateObj });
    commit(types.EDIT_DEAL, response.data);
    return response.data;
  },

  deleteDeal: async function deleteDeal({ commit }, id) {
    await DealsAPI.delete(id);
    commit(types.DELETE_DEAL, id);
  },

  moveDeal: async function moveDeal({ commit, state: _state }, { dealId, stageId }) {
    const previous = _state.deals.find(d => d.id === dealId);
    if (!previous) return;
    commit(types.EDIT_DEAL, {
      ...previous,
      pipeline_stage_id: stageId,
      stage_id: stageId,
    });
    try {
      const response = await DealsAPI.update(dealId, {
        deal: { pipeline_stage_id: stageId },
      });
      commit(types.EDIT_DEAL, response.data);
    } catch (error) {
      commit(types.EDIT_DEAL, previous);
      throw error;
    }
  },

  createStage: async function createStage({ commit, getters: g }, payload) {
    const pipeline = g.getSelectedPipeline;
    const response = await PipelinesAPI.createStage(pipeline.id, payload);
    commit(types.EDIT_PIPELINE, {
      ...pipeline,
      stages: [...(pipeline.stages || []), response.data],
    });
  },

  updateStage: async function updateStage(
    { commit, getters: g },
    { id, ...payload }
  ) {
    const pipeline = g.getSelectedPipeline;
    const response = await PipelinesAPI.updateStage(pipeline.id, id, payload);
    commit(types.EDIT_PIPELINE, {
      ...pipeline,
      stages: (pipeline.stages || []).map(s =>
        s.id === id ? response.data : s
      ),
    });
  },

  deleteStage: async function deleteStage({ commit, getters: g }, stageId) {
    const pipeline = g.getSelectedPipeline;
    await PipelinesAPI.deleteStage(pipeline.id, stageId);
    commit(types.EDIT_PIPELINE, {
      ...pipeline,
      stages: (pipeline.stages || []).filter(s => s.id !== stageId),
    });
  },

  fetchContactDeals: async function fetchContactDeals(_, contactId) {
    const response = await DealsAPI.get({ contact_id: contactId });
    return response.data.payload || [];
  },
};

export const mutations = {
  [types.SET_PIPELINE_UI_FLAG](_state, flag) {
    _state.uiFlags = { ..._state.uiFlags, ...flag };
  },
  [types.SET_PIPELINES]: MutationHelpers.set,
  [types.ADD_PIPELINE]: MutationHelpers.create,
  [types.EDIT_PIPELINE]: MutationHelpers.update,
  [types.DELETE_PIPELINE]: MutationHelpers.destroy,
  [types.SET_SELECTED_PIPELINE_ID](_state, id) {
    _state.selectedPipelineId = id;
  },
  [types.SET_DEALS](_state, data) {
    _state.deals = data;
  },
  [types.ADD_DEAL](_state, data) {
    _state.deals.push(data);
  },
  [types.EDIT_DEAL](_state, data) {
    const index = _state.deals.findIndex(d => d.id === data.id);
    if (index !== -1) {
      _state.deals[index] = data;
    }
  },
  [types.DELETE_DEAL](_state, id) {
    _state.deals = _state.deals.filter(d => d.id !== Number(id) && d.id !== id);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
