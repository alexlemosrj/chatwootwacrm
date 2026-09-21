import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import PipelinesAPI from '../../api/pipelines';
import DealsAPI from '../../api/deals';
import CrmActivitiesAPI from '../../api/crmActivities';
import CrmEventsAPI from '../../api/crmEvents';

export const state = {
  records: [],
  deals: [],
  selectedPipelineId: null,
  activitiesByDeal: {},
  eventsByDeal: {},
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
    _state.deals.filter(d => d.pipeline_stage_id === stageId),
  getActivitiesForDeal: _state => dealId =>
    _state.activitiesByDeal[dealId] || [],
  getEventsForDeal: _state => dealId => _state.eventsByDeal[dealId] || [],
};

export const actions = {
  async get({ commit, dispatch }) {
    commit(types.SET_PIPELINE_UI_FLAG, { isFetching: true });
    try {
      const response = await PipelinesAPI.get();
      const pipelines = response.data.payload || [];
      commit(types.SET_PIPELINES, pipelines);

      if (pipelines.length) {
        const firstId = pipelines[0].id;
        commit(types.SET_SELECTED_PIPELINE_ID, firstId);
        await dispatch('getDeals', firstId);
      } else {
        commit(types.SET_SELECTED_PIPELINE_ID, null);
        commit(types.SET_DEALS, []);
      }
    } finally {
      commit(types.SET_PIPELINE_UI_FLAG, { isFetching: false });
    }
  },

  async selectPipeline({ commit, dispatch }, id) {
    commit(types.SET_SELECTED_PIPELINE_ID, id);
    await dispatch('getDeals', id);
  },

  async create({ commit }, payload) {
    commit(types.SET_PIPELINE_UI_FLAG, { isCreating: true });
    try {
      const response = await PipelinesAPI.create({ pipeline: payload });
      commit(types.ADD_PIPELINE, response.data);
      return response.data;
    } finally {
      commit(types.SET_PIPELINE_UI_FLAG, { isCreating: false });
    }
  },

  async update({ commit }, { id, ...updateObj }) {
    const response = await PipelinesAPI.update(id, { pipeline: updateObj });
    commit(types.EDIT_PIPELINE, response.data);
    return response.data;
  },

  async delete({ commit }, id) {
    await PipelinesAPI.delete(id);
    commit(types.DELETE_PIPELINE, id);
  },

  async getDeals({ commit }, pipelineId) {
    commit(types.SET_PIPELINE_UI_FLAG, { isFetchingDeals: true });
    try {
      const response = await DealsAPI.get({ pipeline_id: pipelineId });
      commit(types.SET_DEALS, response.data.payload || []);
    } finally {
      commit(types.SET_PIPELINE_UI_FLAG, { isFetchingDeals: false });
    }
  },

  async createDeal({ commit }, deal) {
    const response = await DealsAPI.create({ deal });
    commit(types.ADD_DEAL, response.data);
    return response.data;
  },

  async updateDeal({ commit }, { id, ...updateObj }) {
    const response = await DealsAPI.update(id, { deal: updateObj });
    commit(types.EDIT_DEAL, response.data);
    return response.data;
  },

  async deleteDeal({ commit }, id) {
    await DealsAPI.delete(id);
    commit(types.DELETE_DEAL, id);
  },

  async moveDeal({ commit, state: _state }, { dealId, stageId }) {
    const previous = _state.deals.find(d => d.id === dealId);
    if (!previous) return;

    commit(types.EDIT_DEAL, {
      ...previous,
      pipeline_stage_id: stageId,
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

  async createStage({ commit, getters: g }, payload) {
    const pipeline = g.getSelectedPipeline;
    const response = await PipelinesAPI.createStage(pipeline.id, payload);
    commit(types.EDIT_PIPELINE, {
      ...pipeline,
      stages: [...(pipeline.stages || []), response.data],
    });
    return response.data;
  },

  async updateStage({ commit, getters: g }, { id, ...payload }) {
    const pipeline = g.getSelectedPipeline;
    const response = await PipelinesAPI.updateStage(pipeline.id, id, payload);
    commit(types.EDIT_PIPELINE, {
      ...pipeline,
      stages: (pipeline.stages || []).map(stage =>
        stage.id === id ? response.data : stage
      ),
    });
    return response.data;
  },

  async reorderStages({ commit, getters: g }, stages) {
    const pipeline = g.getSelectedPipeline;
    const response = await PipelinesAPI.reorderStages(pipeline.id, stages);
    commit(types.EDIT_PIPELINE, {
      ...pipeline,
      stages: response.data.payload || response.data,
    });
  },

  async deleteStage({ commit, getters: g }, stageId) {
    const pipeline = g.getSelectedPipeline;
    await PipelinesAPI.deleteStage(pipeline.id, stageId);
    commit(types.EDIT_PIPELINE, {
      ...pipeline,
      stages: (pipeline.stages || []).filter(stage => stage.id !== stageId),
    });
  },

  async fetchContactDeals(_, contactId) {
    const response = await DealsAPI.get({ contact_id: contactId });
    return response.data.payload || [];
  },

  async fetchDealActivities({ commit }, dealId) {
    const response = await CrmActivitiesAPI.get({ deal_id: dealId });
    const records = response.data.payload || [];
    commit(types.SET_CRM_ACTIVITIES_FOR_DEAL, { dealId, records });
    return records;
  },

  async createActivity({ dispatch }, activity) {
    const response = await CrmActivitiesAPI.create({ crm_activity: activity });
    if (activity.deal_id)
      await dispatch('fetchDealActivities', activity.deal_id);
    return response.data;
  },

  async updateActivity({ dispatch }, { id, dealId, ...activity }) {
    const response = await CrmActivitiesAPI.update(id, {
      crm_activity: activity,
    });
    if (dealId) await dispatch('fetchDealActivities', dealId);
    return response.data;
  },

  async deleteActivity({ dispatch }, { id, dealId }) {
    await CrmActivitiesAPI.delete(id);
    if (dealId) await dispatch('fetchDealActivities', dealId);
  },

  async fetchDealEvents({ commit }, dealId) {
    const response = await CrmEventsAPI.get({ deal_id: dealId });
    const records = response.data.payload || [];
    commit(types.SET_CRM_EVENTS_FOR_DEAL, { dealId, records });
    return records;
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
    const index = _state.deals.findIndex(deal => deal.id === data.id);
    if (index !== -1) _state.deals[index] = data;
  },
  [types.DELETE_DEAL](_state, id) {
    _state.deals = _state.deals.filter(
      deal => deal.id !== Number(id) && deal.id !== id
    );
  },
  [types.SET_CRM_ACTIVITIES_FOR_DEAL](_state, { dealId, records }) {
    _state.activitiesByDeal = {
      ..._state.activitiesByDeal,
      [dealId]: records,
    };
  },
  [types.SET_CRM_EVENTS_FOR_DEAL](_state, { dealId, records }) {
    _state.eventsByDeal = {
      ..._state.eventsByDeal,
      [dealId]: records,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
