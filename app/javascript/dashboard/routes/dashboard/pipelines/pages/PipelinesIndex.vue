<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Draggable from 'vuedraggable';

const { t } = useI18n();
const store = useStore();

const pipelines = useMapGetter('pipelines/getPipelines');
const selectedPipeline = useMapGetter('pipelines/getSelectedPipeline');
const deals = useMapGetter('pipelines/getDeals');
const uiFlags = useMapGetter('pipelines/getUIFlags');
const agents = useMapGetter('agents/getAgents');

const showDealForm = ref(false);
const showSettings = ref(false);
const editingDeal = ref(null);
const defaultStageId = ref(null);
const newPipelineName = ref('');

const form = reactive({
  title: '',
  value: 0,
  currency: 'USD',
  pipeline_stage_id: null,
  contact_id: null,
  assignee_id: null,
  expected_close_date: '',
  notes: '',
  status: 'open',
});

const stages = computed(() =>
  [...(selectedPipeline.value?.stages || [])].sort(
    (a, b) => a.position - b.position
  )
);

const stageWeights = [0.1, 0.3, 0.5, 0.7, 1.0];

const formatMoney = (value, currency = 'USD') => {
  try {
    return new Intl.NumberFormat(undefined, {
      style: 'currency',
      currency,
      maximumFractionDigits: 0,
    }).format(Number(value) || 0);
  } catch {
    return `${currency} ${Number(value) || 0}`;
  }
};

const dealsForStage = stageId =>
  deals.value.filter(
    d => d.pipeline_stage_id === stageId || d.stage_id === stageId
  );

const stageTotal = stageId =>
  dealsForStage(stageId).reduce((sum, d) => sum + (Number(d.value) || 0), 0);

const analytics = computed(() => {
  const openDeals = deals.value.filter(d => d.status === 'open');
  const value = openDeals.reduce((s, d) => s + (Number(d.value) || 0), 0);
  const count = openDeals.length;
  const avg = count ? value / count : 0;
  let weighted = 0;
  stages.value.forEach((stage, idx) => {
    const w = stageWeights[Math.min(idx, stageWeights.length - 1)];
    weighted += dealsForStage(stage.id)
      .filter(d => d.status === 'open')
      .reduce((s, d) => s + (Number(d.value) || 0) * w, 0);
  });
  const now = new Date();
  const monthStart =
    new Date(now.getFullYear(), now.getMonth(), 1).getTime() / 1000;
  const won = deals.value.filter(
    d => d.status === 'won' && d.updated_at >= monthStart
  ).length;
  const lost = deals.value.filter(
    d => d.status === 'lost' && d.updated_at >= monthStart
  ).length;
  const currency = openDeals[0]?.currency || 'USD';
  return { count, value, avg, weighted, won, lost, currency };
});

onMounted(async () => {
  await store.dispatch('agents/get');
  await store.dispatch('pipelines/get');
});

watch(selectedPipeline, p => {
  if (p?.stages?.length && !form.pipeline_stage_id) {
    form.pipeline_stage_id = p.stages[0].id;
  }
});

const selectPipeline = id => store.dispatch('pipelines/selectPipeline', id);

const createPipeline = async () => {
  const name = newPipelineName.value.trim();
  if (!name) return;
  try {
    const pipeline = await store.dispatch('pipelines/create', { name });
    newPipelineName.value = '';
    await store.dispatch('pipelines/selectPipeline', pipeline.id);
    useAlert(t('PIPELINES.NEW_PIPELINE'));
  } catch (e) {
    useAlert(e.message || 'Error');
  }
};

const openCreateDeal = stageId => {
  editingDeal.value = null;
  Object.assign(form, {
    title: '',
    value: 0,
    currency: 'USD',
    pipeline_stage_id: stageId || stages.value[0]?.id,
    contact_id: null,
    assignee_id: null,
    expected_close_date: '',
    notes: '',
    status: 'open',
  });
  defaultStageId.value = stageId;
  showDealForm.value = true;
};

const openEditDeal = deal => {
  editingDeal.value = deal;
  Object.assign(form, {
    title: deal.title,
    value: deal.value,
    currency: deal.currency || 'USD',
    pipeline_stage_id: deal.pipeline_stage_id || deal.stage_id,
    contact_id: deal.contact_id,
    assignee_id: deal.assignee_id,
    expected_close_date: deal.expected_close_date || '',
    notes: deal.notes || '',
    status: deal.status || 'open',
  });
  showDealForm.value = true;
};

const saveDeal = async () => {
  const payload = {
    title: form.title,
    value: Number(form.value) || 0,
    currency: form.currency,
    pipeline_id: selectedPipeline.value.id,
    pipeline_stage_id: form.pipeline_stage_id,
    contact_id: form.contact_id || null,
    assignee_id: form.assignee_id || null,
    expected_close_date: form.expected_close_date || null,
    notes: form.notes,
    status: form.status,
  };
  try {
    if (editingDeal.value) {
      await store.dispatch('pipelines/updateDeal', {
        id: editingDeal.value.id,
        ...payload,
      });
    } else {
      await store.dispatch('pipelines/createDeal', payload);
    }
    showDealForm.value = false;
  } catch (e) {
    useAlert(e.message || 'Error saving deal');
  }
};

const deleteDeal = async () => {
  if (!editingDeal.value) return;
  await store.dispatch('pipelines/deleteDeal', editingDeal.value.id);
  showDealForm.value = false;
};

const onDealDrop = async (stageId, event) => {
  const dealId = Number(event.item?.dataset?.dealId);
  if (!dealId) return;
  try {
    await store.dispatch('pipelines/moveDeal', { dealId, stageId });
  } catch (e) {
    useAlert(e.message || 'Error moving deal');
    await store.dispatch('pipelines/getDeals', selectedPipeline.value.id);
  }
};

const settingsName = ref('');
watch(showSettings, open => {
  if (open) settingsName.value = selectedPipeline.value?.name || '';
});

const savePipelineName = async () => {
  await store.dispatch('pipelines/update', {
    id: selectedPipeline.value.id,
    name: settingsName.value,
  });
};

const addStage = async () => {
  await store.dispatch('pipelines/createStage', {
    name: 'New stage',
    color: '#64748b',
    position: stages.value.length,
  });
};

const saveStage = async stage => {
  await store.dispatch('pipelines/updateStage', {
    id: stage.id,
    name: stage.name,
    color: stage.color,
    position: stage.position,
  });
};

const removeStage = async stageId => {
  try {
    await store.dispatch('pipelines/deleteStage', stageId);
  } catch (e) {
    useAlert(e?.response?.data?.error || e.message || 'Cannot delete stage');
  }
};

const deletePipeline = async () => {
  await store.dispatch('pipelines/delete', selectedPipeline.value.id);
  showSettings.value = false;
  await store.dispatch('pipelines/get');
};
</script>

<template>
  <div class="flex h-full flex-col bg-n-background p-4">
    <div class="mb-4 flex flex-wrap items-center gap-3">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ $t('PIPELINES.TITLE') }}
      </h1>
      <select
        class="rounded-md border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm"
        :value="selectedPipeline?.id"
        @change="selectPipeline(Number($event.target.value))"
      >
        <option v-for="p in pipelines" :key="p.id" :value="p.id">
          {{ p.name }}
        </option>
      </select>
      <div class="flex items-center gap-2">
        <input
          v-model="newPipelineName"
          class="rounded-md border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm"
          :placeholder="$t('PIPELINES.PIPELINE_NAME')"
        />
        <button
          class="rounded-md bg-n-brand px-3 py-1.5 text-sm text-white"
          @click="createPipeline"
        >
          {{ $t('PIPELINES.NEW_PIPELINE') }}
        </button>
      </div>
      <button
        class="ml-auto rounded-md border border-n-weak px-3 py-1.5 text-sm"
        @click="showSettings = true"
      >
        {{ $t('PIPELINES.SETTINGS') }}
      </button>
      <button
        class="rounded-md bg-n-brand px-3 py-1.5 text-sm text-white"
        @click="openCreateDeal()"
      >
        {{ $t('PIPELINES.ADD_DEAL') }}
      </button>
    </div>

    <div
      v-if="!uiFlags.isFetching"
      class="mb-4 grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6"
    >
      <div class="rounded-lg bg-n-solid-2 p-3">
        <div class="text-xs text-n-slate-11">
          {{ $t('PIPELINES.ANALYTICS.COUNT') }}
        </div>
        <div class="text-lg font-semibold">{{ analytics.count }}</div>
      </div>
      <div class="rounded-lg bg-n-solid-2 p-3">
        <div class="text-xs text-n-slate-11">
          {{ $t('PIPELINES.ANALYTICS.VALUE') }}
        </div>
        <div class="text-lg font-semibold">
          {{ formatMoney(analytics.value, analytics.currency) }}
        </div>
      </div>
      <div class="rounded-lg bg-n-solid-2 p-3">
        <div class="text-xs text-n-slate-11">
          {{ $t('PIPELINES.ANALYTICS.AVG') }}
        </div>
        <div class="text-lg font-semibold">
          {{ formatMoney(analytics.avg, analytics.currency) }}
        </div>
      </div>
      <div class="rounded-lg bg-n-solid-2 p-3">
        <div class="text-xs text-n-slate-11">
          {{ $t('PIPELINES.ANALYTICS.WEIGHTED') }}
        </div>
        <div class="text-lg font-semibold">
          {{ formatMoney(analytics.weighted, analytics.currency) }}
        </div>
      </div>
      <div class="rounded-lg bg-n-solid-2 p-3">
        <div class="text-xs text-n-slate-11">
          {{ $t('PIPELINES.ANALYTICS.WON') }}
        </div>
        <div class="text-lg font-semibold text-green-500">
          {{ analytics.won }}
        </div>
      </div>
      <div class="rounded-lg bg-n-solid-2 p-3">
        <div class="text-xs text-n-slate-11">
          {{ $t('PIPELINES.ANALYTICS.LOST') }}
        </div>
        <div class="text-lg font-semibold text-red-500">
          {{ analytics.lost }}
        </div>
      </div>
    </div>

    <div
      class="flex flex-1 gap-3 overflow-x-auto pb-4"
      :class="{ 'opacity-50': uiFlags.isFetching || uiFlags.isFetchingDeals }"
    >
      <div
        v-for="stage in stages"
        :key="stage.id"
        class="flex w-72 shrink-0 flex-col rounded-xl bg-n-solid-2"
      >
        <div
          class="flex items-center justify-between border-b border-n-weak px-3 py-2"
        >
          <div class="flex items-center gap-2">
            <span
              class="h-2.5 w-2.5 rounded-full"
              :style="{ backgroundColor: stage.color }"
            />
            <span class="text-sm font-medium">{{ stage.name }}</span>
            <span class="text-xs text-n-slate-11">
              ({{ dealsForStage(stage.id).length }})
            </span>
          </div>
          <span class="text-xs text-n-slate-11">
            {{ formatMoney(stageTotal(stage.id)) }}
          </span>
        </div>
        <Draggable
          class="flex min-h-[120px] flex-1 flex-col gap-2 p-2"
          :model-value="dealsForStage(stage.id)"
          :group="{ name: 'deals', pull: true, put: true }"
          item-key="id"
          :data-stage-id="stage.id"
          @update:model-value="() => {}"
          @change="
            evt =>
              evt.added &&
              onDealDrop(stage.id, {
                item: { dataset: { dealId: evt.added.element.id } },
              })
          "
        >
          <template #item="{ element }">
            <button
              type="button"
              class="rounded-lg border border-n-weak bg-n-solid-1 p-3 text-left shadow-sm transition hover:border-n-brand"
              :data-deal-id="element.id"
              @click="openEditDeal(element)"
            >
              <div class="text-sm font-medium text-n-slate-12">
                {{ element.title }}
              </div>
              <div class="mt-1 text-xs text-n-slate-11">
                {{ element.contact?.name || '—' }}
              </div>
              <div class="mt-2 flex items-center justify-between text-xs">
                <span class="font-semibold">
                  {{ formatMoney(element.value, element.currency) }}
                </span>
                <span
                  v-if="element.status !== 'open'"
                  class="rounded px-1.5 py-0.5 uppercase"
                  :class="
                    element.status === 'won'
                      ? 'bg-green-500/15 text-green-600'
                      : 'bg-red-500/15 text-red-600'
                  "
                >
                  {{ element.status }}
                </span>
              </div>
            </button>
          </template>
        </Draggable>
        <button
          class="m-2 rounded-md border border-dashed border-n-weak py-2 text-xs text-n-slate-11 hover:border-n-brand hover:text-n-brand"
          @click="openCreateDeal(stage.id)"
        >
          + {{ $t('PIPELINES.ADD_DEAL') }}
        </button>
      </div>
    </div>

    <!-- Deal form modal -->
    <div
      v-if="showDealForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      @click.self="showDealForm = false"
    >
      <div class="w-full max-w-md rounded-xl bg-n-solid-1 p-5 shadow-xl">
        <h2 class="mb-4 text-lg font-semibold">
          {{
            editingDeal ? $t('PIPELINES.EDIT_DEAL') : $t('PIPELINES.ADD_DEAL')
          }}
        </h2>
        <div class="flex flex-col gap-3">
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.TITLE') }}
            <input v-model="form.title" class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5" />
          </label>
          <div class="grid grid-cols-2 gap-2">
            <label class="text-xs">
              {{ $t('PIPELINES.FORM.VALUE') }}
              <input v-model.number="form.value" type="number" class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5" />
            </label>
            <label class="text-xs">
              {{ $t('PIPELINES.FORM.CURRENCY') }}
              <input v-model="form.currency" class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5" />
            </label>
          </div>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.STAGE') }}
            <select v-model="form.pipeline_stage_id" class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5">
              <option v-for="s in stages" :key="s.id" :value="s.id">{{ s.name }}</option>
            </select>
          </label>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.ASSIGNEE') }}
            <select v-model="form.assignee_id" class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5">
              <option :value="null">—</option>
              <option v-for="a in agents" :key="a.id" :value="a.id">{{ a.name }}</option>
            </select>
          </label>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.CONTACT') }}
            <input v-model.number="form.contact_id" type="number" class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5" />
          </label>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.CLOSE_DATE') }}
            <input v-model="form.expected_close_date" type="date" class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5" />
          </label>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.STATUS') }}
            <select v-model="form.status" class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5">
              <option value="open">{{ $t('PIPELINES.STATUS.OPEN') }}</option>
              <option value="won">{{ $t('PIPELINES.STATUS.WON') }}</option>
              <option value="lost">{{ $t('PIPELINES.STATUS.LOST') }}</option>
            </select>
          </label>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.NOTES') }}
            <textarea v-model="form.notes" rows="3" class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5" />
          </label>
        </div>
        <div class="mt-4 flex gap-2">
          <button class="rounded-md bg-n-brand px-3 py-1.5 text-sm text-white" @click="saveDeal">
            {{ $t('PIPELINES.FORM.SAVE') }}
          </button>
          <button class="rounded-md border border-n-weak px-3 py-1.5 text-sm" @click="showDealForm = false">
            {{ $t('PIPELINES.FORM.CANCEL') }}
          </button>
          <button
            v-if="editingDeal"
            class="ml-auto rounded-md px-3 py-1.5 text-sm text-red-500"
            @click="deleteDeal"
          >
            {{ $t('PIPELINES.FORM.DELETE') }}
          </button>
        </div>
      </div>
    </div>

    <!-- Settings modal -->
    <div
      v-if="showSettings"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      @click.self="showSettings = false"
    >
      <div class="w-full max-w-lg rounded-xl bg-n-solid-1 p-5 shadow-xl">
        <h2 class="mb-4 text-lg font-semibold">{{ $t('PIPELINES.SETTINGS') }}</h2>
        <label class="text-xs">
          {{ $t('PIPELINES.SETTINGS_PANEL.RENAME') }}
          <div class="mt-1 flex gap-2">
            <input v-model="settingsName" class="flex-1 rounded border border-n-weak bg-n-solid-2 px-2 py-1.5" />
            <button class="rounded bg-n-brand px-3 py-1.5 text-sm text-white" @click="savePipelineName">
              {{ $t('PIPELINES.SETTINGS_PANEL.SAVE_STAGE') }}
            </button>
          </div>
        </label>
        <div class="mt-4">
          <div class="mb-2 flex items-center justify-between">
            <span class="text-sm font-medium">{{ $t('PIPELINES.SETTINGS_PANEL.STAGES') }}</span>
            <button class="text-sm text-n-brand" @click="addStage">
              {{ $t('PIPELINES.SETTINGS_PANEL.ADD_STAGE') }}
            </button>
          </div>
          <div
            v-for="stage in stages"
            :key="stage.id"
            class="mb-2 flex items-center gap-2"
          >
            <input v-model="stage.color" type="color" class="h-8 w-8" />
            <input v-model="stage.name" class="flex-1 rounded border border-n-weak bg-n-solid-2 px-2 py-1" />
            <button class="text-xs text-n-brand" @click="saveStage(stage)">Save</button>
            <button class="text-xs text-red-500" @click="removeStage(stage.id)">×</button>
          </div>
        </div>
        <button class="mt-4 text-sm text-red-500" @click="deletePipeline">
          {{ $t('PIPELINES.SETTINGS_PANEL.DELETE_PIPELINE') }}
        </button>
      </div>
    </div>
  </div>
</template>
