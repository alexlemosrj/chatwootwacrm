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
const showPipelineForm = ref(false);
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

const metricCards = computed(() => {
  const { currency } = analytics.value;
  return [
    {
      key: 'count',
      label: t('PIPELINES.ANALYTICS.COUNT'),
      value: analytics.value.count,
      icon: 'i-lucide-briefcase',
      iconClass: 'bg-n-slate-3 text-n-slate-11',
    },
    {
      key: 'value',
      label: t('PIPELINES.ANALYTICS.VALUE'),
      value: formatMoney(analytics.value.value, currency),
      icon: 'i-lucide-wallet',
      iconClass: 'bg-n-solid-blue text-n-blue-11',
    },
    {
      key: 'avg',
      label: t('PIPELINES.ANALYTICS.AVG'),
      value: formatMoney(analytics.value.avg, currency),
      icon: 'i-lucide-chart-column',
      iconClass: 'bg-n-solid-iris text-n-iris-11',
    },
    {
      key: 'weighted',
      label: t('PIPELINES.ANALYTICS.WEIGHTED'),
      value: formatMoney(analytics.value.weighted, currency),
      icon: 'i-lucide-scale',
      iconClass: 'bg-n-amber-3 text-n-amber-11',
    },
    {
      key: 'won',
      label: t('PIPELINES.ANALYTICS.WON'),
      value: analytics.value.won,
      icon: 'i-lucide-trophy',
      iconClass: 'bg-n-teal-3 text-n-teal-11',
      valueClass: 'text-n-teal-11',
    },
    {
      key: 'lost',
      label: t('PIPELINES.ANALYTICS.LOST'),
      value: analytics.value.lost,
      icon: 'i-lucide-circle-x',
      iconClass: 'bg-n-ruby-3 text-n-ruby-11',
      valueClass: 'text-n-ruby-11',
    },
  ];
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
    showPipelineForm.value = false;
    await store.dispatch('pipelines/selectPipeline', pipeline.id);
    useAlert(t('PIPELINES.CREATED'));
  } catch (e) {
    useAlert(e.message || t('PIPELINES.ERRORS.CREATE_PIPELINE'));
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
    useAlert(e.message || t('PIPELINES.ERRORS.SAVE_DEAL'));
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
    useAlert(e.message || t('PIPELINES.ERRORS.MOVE_DEAL'));
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
    name: t('PIPELINES.SETTINGS_PANEL.NEW_STAGE_NAME'),
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
    useAlert(
      e?.response?.data?.error ||
        e.message ||
        t('PIPELINES.ERRORS.DELETE_STAGE')
    );
  }
};

const deletePipeline = async () => {
  await store.dispatch('pipelines/delete', selectedPipeline.value.id);
  showSettings.value = false;
  await store.dispatch('pipelines/get');
};
</script>

<template>
  <div
    class="flex h-full min-h-0 w-full min-w-0 flex-col gap-4 overflow-hidden bg-n-background p-4"
  >
    <div class="flex shrink-0 flex-col gap-3">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ $t('PIPELINES.TITLE') }}
      </h1>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex min-w-0 flex-1 items-center gap-2">
          <div
            class="relative inline-flex w-full min-w-48 max-w-80 items-center"
          >
            <span
              class="pointer-events-none absolute size-4 -translate-y-1/2 i-lucide-git-fork start-2.5 top-1/2 text-n-brand"
            />
            <select
              class="h-9 w-full min-w-0 cursor-pointer appearance-none truncate rounded-lg border border-n-strong bg-n-solid-1 bg-none py-0 pl-9 pr-9 text-sm font-medium text-n-slate-12 outline-none transition-colors hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
              :value="selectedPipeline?.id"
              :aria-label="$t('PIPELINES.SELECT_PIPELINE')"
              @change="selectPipeline(Number($event.target.value))"
            >
              <option v-for="p in pipelines" :key="p.id" :value="p.id">
                {{ p.name }}
              </option>
            </select>
            <span
              class="pointer-events-none absolute size-4 -translate-y-1/2 i-lucide-chevron-down end-2.5 top-1/2 text-n-slate-11"
            />
          </div>
          <template v-if="showPipelineForm">
            <input
              v-model="newPipelineName"
              class="h-9 w-44 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
              :placeholder="$t('PIPELINES.PIPELINE_NAME')"
              @keyup.enter="createPipeline"
            />
            <button
              class="inline-flex h-9 items-center gap-1.5 rounded-lg bg-n-brand px-3 text-sm font-medium text-white outline-none transition-[filter] hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
              @click="createPipeline"
            >
              {{ $t('PIPELINES.FORM.SAVE') }}
            </button>
          </template>
        </div>
        <div class="flex shrink-0 flex-wrap items-center justify-end gap-2">
          <button
            class="inline-flex h-9 items-center gap-1.5 rounded-lg border border-n-strong bg-n-solid-1 px-3 text-sm font-medium text-n-slate-12 outline-none transition-colors hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
            @click="showPipelineForm = !showPipelineForm"
          >
            <span class="size-4 shrink-0 i-lucide-plus" />
            {{ $t('PIPELINES.NEW_PIPELINE') }}
          </button>
          <button
            class="inline-flex size-9 items-center justify-center rounded-lg border border-n-strong bg-n-solid-1 text-n-slate-11 outline-none transition-colors hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
            :title="$t('PIPELINES.SETTINGS')"
            :aria-label="$t('PIPELINES.SETTINGS')"
            @click="showSettings = true"
          >
            <span class="size-4 i-lucide-settings" />
          </button>
          <button
            class="inline-flex h-9 items-center gap-1.5 rounded-lg bg-n-brand px-3.5 text-sm font-medium text-white outline-none transition-[filter] hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
            @click="openCreateDeal()"
          >
            <span class="size-4 shrink-0 i-lucide-plus" />
            {{ $t('PIPELINES.ADD_DEAL') }}
          </button>
        </div>
      </div>
    </div>

    <div
      v-if="!uiFlags.isFetching"
      class="grid w-full min-w-0 shrink-0 grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6"
    >
      <div
        v-for="card in metricCards"
        :key="card.key"
        class="flex min-w-0 flex-col gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-3.5"
      >
        <div
          class="flex size-7 shrink-0 items-center justify-center rounded-md"
          :class="card.iconClass"
        >
          <span class="size-3.5" :class="card.icon" />
        </div>
        <div
          class="truncate text-[11px] font-medium uppercase tracking-wide text-n-slate-11"
          :title="card.label"
        >
          {{ card.label }}
        </div>
        <div
          class="truncate text-lg font-semibold tabular-nums text-n-slate-12"
          :class="card.valueClass"
        >
          {{ card.value }}
        </div>
      </div>
    </div>

    <div
      class="flex min-h-0 w-full min-w-0 flex-1 gap-4 overflow-x-auto overflow-y-hidden pb-2 [&::-webkit-scrollbar-thumb]:rounded-full [&::-webkit-scrollbar-thumb]:bg-n-slate-6 [&::-webkit-scrollbar-track]:bg-transparent [&::-webkit-scrollbar]:h-2"
      :class="{
        'opacity-50 pointer-events-none':
          uiFlags.isFetching || uiFlags.isFetchingDeals,
      }"
    >
      <div
        v-for="stage in stages"
        :key="stage.id"
        class="flex w-72 shrink-0 flex-col overflow-hidden rounded-xl border border-n-strong bg-n-solid-2"
      >
        <div
          class="h-1.5 w-full shrink-0"
          :style="{ backgroundColor: stage.color }"
          aria-hidden="true"
        />
        <div class="flex items-start justify-between gap-2 px-3 pb-2 pt-3">
          <div class="flex min-w-0 flex-col gap-0.5">
            <span class="truncate text-sm font-semibold text-n-slate-12">
              {{ stage.name }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-11">
              {{ formatMoney(stageTotal(stage.id), analytics.currency) }}
            </span>
          </div>
          <span
            class="inline-flex h-5 min-w-5 shrink-0 items-center justify-center rounded-full bg-n-solid-3 px-1.5 text-[11px] font-medium tabular-nums text-n-slate-11"
          >
            {{ dealsForStage(stage.id).length }}
          </span>
        </div>
        <Draggable
          class="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-2"
          :model-value="dealsForStage(stage.id)"
          :group="{ name: 'deals', pull: true, put: true }"
          item-key="id"
          :data-stage-id="stage.id"
          ghost-class="opacity-40"
          drag-class="shadow-lg"
          scroll
          bubble-scroll
          :scroll-sensitivity="120"
          :scroll-speed="18"
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
              class="w-full cursor-grab rounded-lg border border-n-weak bg-n-solid-1 p-3 text-left shadow-sm outline-none transition-colors hover:border-n-brand hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand active:cursor-grabbing"
              :data-deal-id="element.id"
              @click="openEditDeal(element)"
            >
              <div class="text-sm font-medium text-n-slate-12">
                {{ element.title }}
              </div>
              <div class="mt-1 text-xs text-n-slate-11">
                {{ element.contact?.name || '—' }}
              </div>
              <div class="mt-2 flex items-center justify-between gap-2 text-xs">
                <span class="font-semibold tabular-nums text-n-slate-12">
                  {{ formatMoney(element.value, element.currency) }}
                </span>
                <span
                  v-if="element.status !== 'open'"
                  class="rounded px-1.5 py-0.5 text-[10px] uppercase"
                  :class="
                    element.status === 'won'
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-ruby-3 text-n-ruby-11'
                  "
                >
                  {{
                    element.status === 'won'
                      ? $t('PIPELINES.STATUS.WON')
                      : $t('PIPELINES.STATUS.LOST')
                  }}
                </span>
              </div>
            </button>
          </template>
          <template #footer>
            <div
              v-if="!dealsForStage(stage.id).length"
              class="flex min-h-28 flex-1 items-center justify-center rounded-lg border border-dashed border-n-strong bg-n-alpha-1 px-3 py-6 text-center text-xs text-n-slate-11"
            >
              {{ $t('PIPELINES.DROP_HERE') }}
            </div>
          </template>
        </Draggable>
        <div class="p-2 pt-0">
          <button
            class="flex h-9 w-full items-center justify-center gap-1 rounded-lg border border-n-strong bg-n-solid-1 text-xs font-medium text-n-slate-11 outline-none transition-colors hover:border-n-brand hover:text-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
            @click="openCreateDeal(stage.id)"
          >
            <span class="size-3.5 shrink-0 i-lucide-plus" />
            {{ $t('PIPELINES.ADD_DEAL') }}
          </button>
        </div>
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
            <input
              v-model="form.title"
              class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5"
            />
          </label>
          <div class="grid grid-cols-2 gap-2">
            <label class="text-xs">
              {{ $t('PIPELINES.FORM.VALUE') }}
              <input
                v-model.number="form.value"
                type="number"
                class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5"
              />
            </label>
            <label class="text-xs">
              {{ $t('PIPELINES.FORM.CURRENCY') }}
              <input
                v-model="form.currency"
                class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5"
              />
            </label>
          </div>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.STAGE') }}
            <select
              v-model="form.pipeline_stage_id"
              class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5"
            >
              <option v-for="s in stages" :key="s.id" :value="s.id">
                {{ s.name }}
              </option>
            </select>
          </label>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.ASSIGNEE') }}
            <select
              v-model="form.assignee_id"
              class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5"
            >
              <option :value="null">—</option>
              <option v-for="a in agents" :key="a.id" :value="a.id">
                {{ a.name }}
              </option>
            </select>
          </label>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.CONTACT') }}
            <input
              v-model.number="form.contact_id"
              type="number"
              class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5"
            />
          </label>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.CLOSE_DATE') }}
            <input
              v-model="form.expected_close_date"
              type="date"
              class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5"
            />
          </label>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.STATUS') }}
            <select
              v-model="form.status"
              class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5"
            >
              <option value="open">{{ $t('PIPELINES.STATUS.OPEN') }}</option>
              <option value="won">{{ $t('PIPELINES.STATUS.WON') }}</option>
              <option value="lost">{{ $t('PIPELINES.STATUS.LOST') }}</option>
            </select>
          </label>
          <label class="text-xs">
            {{ $t('PIPELINES.FORM.NOTES') }}
            <textarea
              v-model="form.notes"
              rows="3"
              class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 px-2 py-1.5"
            />
          </label>
        </div>
        <div class="mt-4 flex gap-2">
          <button
            class="rounded-md bg-n-brand px-3 py-1.5 text-sm text-white"
            @click="saveDeal"
          >
            {{ $t('PIPELINES.FORM.SAVE') }}
          </button>
          <button
            class="rounded-md border border-n-weak px-3 py-1.5 text-sm"
            @click="showDealForm = false"
          >
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
        <h2 class="mb-4 text-lg font-semibold">
          {{ $t('PIPELINES.SETTINGS') }}
        </h2>
        <label class="text-xs">
          {{ $t('PIPELINES.SETTINGS_PANEL.RENAME') }}
          <div class="mt-1 flex gap-2">
            <input
              v-model="settingsName"
              class="flex-1 rounded border border-n-weak bg-n-solid-2 px-2 py-1.5"
            />
            <button
              class="rounded bg-n-brand px-3 py-1.5 text-sm text-white"
              @click="savePipelineName"
            >
              {{ $t('PIPELINES.SETTINGS_PANEL.SAVE_STAGE') }}
            </button>
          </div>
        </label>
        <div class="mt-4">
          <div class="mb-2 flex items-center justify-between">
            <span class="text-sm font-medium">{{
              $t('PIPELINES.SETTINGS_PANEL.STAGES')
            }}</span>
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
            <input
              v-model="stage.name"
              class="flex-1 rounded border border-n-weak bg-n-solid-2 px-2 py-1"
            />
            <button class="text-xs text-n-brand" @click="saveStage(stage)">
              {{ $t('PIPELINES.SETTINGS_PANEL.SAVE_STAGE') }}
            </button>
            <button
              class="text-xs text-n-ruby-11"
              :title="$t('PIPELINES.SETTINGS_PANEL.DELETE_STAGE')"
              :aria-label="$t('PIPELINES.SETTINGS_PANEL.DELETE_STAGE')"
              @click="removeStage(stage.id)"
            >
              <span class="size-3.5 i-lucide-trash-2" />
            </button>
          </div>
        </div>
        <button class="mt-4 text-sm text-red-500" @click="deletePipeline">
          {{ $t('PIPELINES.SETTINGS_PANEL.DELETE_PIPELINE') }}
        </button>
      </div>
    </div>
  </div>
</template>
