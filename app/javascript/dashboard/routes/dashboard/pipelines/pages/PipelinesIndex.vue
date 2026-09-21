<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import DealDetailModal from '../components/DealDetailModal.vue';

const { t } = useI18n();
const store = useStore();

const pipelines = useMapGetter('pipelines/getPipelines');
const selectedPipeline = useMapGetter('pipelines/getSelectedPipeline');
const deals = useMapGetter('pipelines/getDeals');
const uiFlags = useMapGetter('pipelines/getUIFlags');
const agents = useMapGetter('agents/getAgents');
const contacts = useMapGetter('contacts/getContacts');

const viewMode = ref('kanban');
const searchQuery = ref('');
const showDealForm = ref(false);
const showSettings = ref(false);
const showPipelineForm = ref(false);
const newPipelineName = ref('');
const createBlankPipeline = ref(false);
const draggingDealId = ref(null);
const selectedDeal = ref(null);
const showDealDetail = ref(false);
const settingsName = ref('');
const stageDrafts = ref([]);

const form = reactive({
  title: '',
  value: 0,
  currency: 'BRL',
  expected_revenue: 0,
  probability: 0,
  priority_stars: 0,
  pipeline_stage_id: null,
  contact_id: null,
  assignee_id: null,
  expected_close_date: '',
  notes: '',
  campaign_source: '',
  status: 'open',
});

const stages = computed(() =>
  [...(selectedPipeline.value?.stages || [])].sort(
    (a, b) => a.position - b.position
  )
);

const normalizedQuery = computed(() => searchQuery.value.trim().toLowerCase());

const filteredDeals = computed(() => {
  if (!normalizedQuery.value) return deals.value;
  return deals.value.filter(deal => {
    const haystack = [
      deal.title,
      deal.contact?.name,
      deal.contact?.phone_number,
      deal.assignee?.name,
      deal.campaign_source,
    ]
      .filter(Boolean)
      .join(' ')
      .toLowerCase();
    return haystack.includes(normalizedQuery.value);
  });
});

const dealsForStage = stageId =>
  filteredDeals.value.filter(deal => deal.pipeline_stage_id === stageId);

const stageTotal = stageId =>
  dealsForStage(stageId).reduce(
    (total, deal) => total + (Number(deal.value) || 0),
    0
  );

const formatMoney = (value, currency = 'BRL') => {
  try {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: currency || 'BRL',
      maximumFractionDigits: 0,
    }).format(Number(value) || 0);
  } catch {
    return `${currency || 'BRL'} ${Number(value) || 0}`;
  }
};

const analytics = computed(() => {
  const openDeals = deals.value.filter(deal => deal.status === 'open');
  const value = openDeals.reduce(
    (sum, deal) => sum + (Number(deal.value) || 0),
    0
  );
  const weighted = openDeals.reduce((sum, deal) => {
    const expected = Number(deal.expected_revenue) || 0;
    if (expected > 0) return sum + expected;
    return sum + (Number(deal.value) || 0) * ((Number(deal.probability) || 0) / 100);
  }, 0);
  const count = openDeals.length;
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime() / 1000;
  const won = deals.value.filter(
    deal => deal.status === 'won' && Number(deal.updated_at) >= monthStart
  ).length;
  const lost = deals.value.filter(
    deal => deal.status === 'lost' && Number(deal.updated_at) >= monthStart
  ).length;

  return {
    count,
    value,
    weighted,
    avg: count ? value / count : 0,
    won,
    lost,
    currency: openDeals[0]?.currency || deals.value[0]?.currency || 'BRL',
  };
});

const metricCards = computed(() => [
  {
    label: t('PIPELINES.ANALYTICS.COUNT'),
    value: analytics.value.count,
    icon: 'i-lucide-briefcase-business',
  },
  {
    label: t('PIPELINES.ANALYTICS.VALUE'),
    value: formatMoney(analytics.value.value, analytics.value.currency),
    icon: 'i-lucide-wallet',
  },
  {
    label: t('PIPELINES.ANALYTICS.AVG'),
    value: formatMoney(analytics.value.avg, analytics.value.currency),
    icon: 'i-lucide-chart-column',
  },
  {
    label: t('PIPELINES.ANALYTICS.WEIGHTED'),
    value: formatMoney(analytics.value.weighted, analytics.value.currency),
    icon: 'i-lucide-chart-no-axes-combined',
  },
  {
    label: t('PIPELINES.ANALYTICS.WON'),
    value: analytics.value.won,
    icon: 'i-lucide-trophy',
  },
  {
    label: t('PIPELINES.ANALYTICS.LOST'),
    value: analytics.value.lost,
    icon: 'i-lucide-circle-x',
  },
]);

const selectedStageName = deal =>
  stages.value.find(stage => stage.id === deal.pipeline_stage_id)?.name || '—';

const resetDealForm = stageId => {
  Object.assign(form, {
    title: '',
    value: 0,
    currency: 'BRL',
    expected_revenue: 0,
    probability:
      stages.value.find(stage => stage.id === stageId)?.default_probability || 0,
    priority_stars: 0,
    pipeline_stage_id: stageId || stages.value[0]?.id || null,
    contact_id: null,
    assignee_id: null,
    expected_close_date: '',
    notes: '',
    campaign_source: '',
    status: 'open',
  });
};

const load = async () => {
  await Promise.all([
    store.dispatch('agents/get'),
    store.dispatch('contacts/get', { page: 1 }),
  ]);
  await store.dispatch('pipelines/get');
};

onMounted(load);

watch(
  () => selectedPipeline.value?.id,
  () => {
    searchQuery.value = '';
  }
);

watch(showSettings, open => {
  if (!open || !selectedPipeline.value) return;
  settingsName.value = selectedPipeline.value.name;
  stageDrafts.value = stages.value.map(stage => ({ ...stage }));
});

const selectPipeline = async id => {
  await store.dispatch('pipelines/selectPipeline', Number(id));
};

const createPipeline = async () => {
  const name = newPipelineName.value.trim();
  if (!name) return;

  try {
    const pipeline = await store.dispatch('pipelines/create', {
      name,
      with_default_stages: !createBlankPipeline.value,
    });
    newPipelineName.value = '';
    createBlankPipeline.value = false;
    showPipelineForm.value = false;
    await store.dispatch('pipelines/get');
    await store.dispatch('pipelines/selectPipeline', pipeline.id);
    useAlert(t('PIPELINES.CREATED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error.message ||
        t('PIPELINES.ERRORS.CREATE_PIPELINE')
    );
  }
};

const openCreateDeal = stageId => {
  resetDealForm(stageId);
  showDealForm.value = true;
};

const createDeal = async () => {
  if (!form.title.trim() || !form.pipeline_stage_id) return;

  try {
    const created = await store.dispatch('pipelines/createDeal', {
      title: form.title.trim(),
      value: Number(form.value) || 0,
      currency: form.currency || 'BRL',
      expected_revenue: Number(form.expected_revenue) || 0,
      probability: Number(form.probability) || 0,
      priority_stars: Number(form.priority_stars) || 0,
      pipeline_id: selectedPipeline.value.id,
      pipeline_stage_id: form.pipeline_stage_id,
      contact_id: form.contact_id || null,
      assignee_id: form.assignee_id || null,
      expected_close_date: form.expected_close_date || null,
      notes: form.notes || '',
      campaign_source: form.campaign_source || '',
      status: form.status,
    });
    showDealForm.value = false;
    selectedDeal.value = created;
    showDealDetail.value = true;
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error.message ||
        t('PIPELINES.ERRORS.SAVE_DEAL')
    );
  }
};

const openDeal = deal => {
  selectedDeal.value = deal;
  showDealDetail.value = true;
};

const refreshDeals = async () => {
  if (!selectedPipeline.value?.id) return;
  await store.dispatch('pipelines/getDeals', selectedPipeline.value.id);
  if (selectedDeal.value?.id) {
    selectedDeal.value =
      deals.value.find(deal => deal.id === selectedDeal.value.id) ||
      selectedDeal.value;
  }
};

const onDragStart = dealId => {
  draggingDealId.value = dealId;
};

const onDrop = async stageId => {
  const dealId = draggingDealId.value;
  draggingDealId.value = null;
  if (!dealId) return;

  const deal = deals.value.find(item => item.id === dealId);
  if (!deal || deal.pipeline_stage_id === stageId) return;

  try {
    await store.dispatch('pipelines/moveDeal', { dealId, stageId });
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error.message ||
        t('PIPELINES.ERRORS.MOVE_DEAL')
    );
  }
};

const savePipelineName = async () => {
  const name = settingsName.value.trim();
  if (!name) return;
  await store.dispatch('pipelines/update', {
    id: selectedPipeline.value.id,
    name,
  });
};

const addStage = async () => {
  const created = await store.dispatch('pipelines/createStage', {
    name: t('PIPELINES.SETTINGS_PANEL.NEW_STAGE_NAME'),
    color: '#64748b',
    position: stageDrafts.value.length,
    default_probability: 0,
  });
  stageDrafts.value.push({ ...created });
};

const saveStage = async stage => {
  await store.dispatch('pipelines/updateStage', {
    id: stage.id,
    name: stage.name,
    color: stage.color,
    position: stage.position,
    default_probability: Number(stage.default_probability) || 0,
    is_won: !!stage.is_won,
    is_lost: !!stage.is_lost,
  });
};

const deleteStage = async stage => {
  try {
    await store.dispatch('pipelines/deleteStage', stage.id);
    stageDrafts.value = stageDrafts.value.filter(item => item.id !== stage.id);
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        error.message ||
        t('PIPELINES.ERRORS.DELETE_STAGE')
    );
  }
};

const moveStage = async (index, direction) => {
  const target = direction === 'up' ? index - 1 : index + 1;
  if (target < 0 || target >= stageDrafts.value.length) return;

  const reordered = [...stageDrafts.value];
  [reordered[index], reordered[target]] = [reordered[target], reordered[index]];
  reordered.forEach((stage, position) => {
    stage.position = position;
  });
  stageDrafts.value = reordered;

  await store.dispatch(
    'pipelines/reorderStages',
    reordered.map(stage => ({ id: stage.id, position: stage.position }))
  );
};

const deletePipeline = async () => {
  try {
    await store.dispatch('pipelines/delete', selectedPipeline.value.id);
    showSettings.value = false;
    await store.dispatch('pipelines/get');
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        error.message ||
        'Não foi possível excluir o funil.'
    );
  }
};

const statusLabel = status => {
  const labels = {
    open: t('PIPELINES.STATUS.OPEN'),
    won: t('PIPELINES.STATUS.WON'),
    lost: t('PIPELINES.STATUS.LOST'),
  };
  return labels[status] || status;
};

const statusClass = status => ({
  'bg-n-slate-3 text-n-slate-11': status === 'open',
  'bg-n-teal-3 text-n-teal-11': status === 'won',
  'bg-n-ruby-3 text-n-ruby-11': status === 'lost',
});
</script>

<template>
  <div class="flex h-full min-h-0 w-full flex-col overflow-hidden bg-n-background">
    <header class="shrink-0 border-b border-n-weak px-5 py-4">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold text-n-slate-12">
            {{ t('PIPELINES.TITLE') }}
          </h1>
          <p class="mt-1 text-sm text-n-slate-10">
            CRM de oportunidades integrado aos contatos e conversas do Chatwoot.
          </p>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <button
            class="inline-flex h-9 items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2"
            @click="showPipelineForm = !showPipelineForm"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('PIPELINES.NEW_PIPELINE') }}
          </button>
          <button
            class="inline-flex h-9 items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2"
            @click="showSettings = true"
          >
            <span class="i-lucide-settings-2 size-4" />
            {{ t('PIPELINES.SETTINGS') }}
          </button>
          <button
            class="inline-flex h-9 items-center gap-2 rounded-lg bg-n-brand px-3 text-sm font-medium text-white"
            :disabled="!stages.length"
            @click="openCreateDeal()"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('PIPELINES.ADD_DEAL') }}
          </button>
        </div>
      </div>

      <div class="mt-4 flex flex-wrap items-center gap-3">
        <select
          class="h-9 min-w-52 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm font-medium text-n-slate-12"
          :value="selectedPipeline?.id"
          @change="selectPipeline($event.target.value)"
        >
          <option v-for="pipeline in pipelines" :key="pipeline.id" :value="pipeline.id">
            {{ pipeline.name }}
          </option>
        </select>

        <div v-if="showPipelineForm" class="flex flex-wrap items-center gap-2">
          <input
            v-model="newPipelineName"
            class="h-9 w-52 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12"
            :placeholder="t('PIPELINES.PIPELINE_NAME')"
            @keyup.enter="createPipeline"
          />
          <label class="flex items-center gap-2 text-xs text-n-slate-11">
            <input v-model="createBlankPipeline" type="checkbox" />
            {{ t('PIPELINES.SETTINGS_PANEL.BLANK_PIPELINE') }}
          </label>
          <button
            class="h-9 rounded-lg bg-n-brand px-3 text-sm font-medium text-white"
            @click="createPipeline"
          >
            {{ t('PIPELINES.FORM.SAVE') }}
          </button>
        </div>

        <div class="relative ml-auto min-w-56 flex-1 sm:max-w-80">
          <span
            class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 i-lucide-search text-n-slate-9"
          />
          <input
            v-model="searchQuery"
            class="h-9 w-full rounded-lg border border-n-weak bg-n-solid-1 pl-9 pr-3 text-sm text-n-slate-12"
            :placeholder="t('PIPELINES.SEARCH')"
          />
        </div>

        <div class="flex overflow-hidden rounded-lg border border-n-weak">
          <button
            class="flex h-9 items-center gap-1.5 px-3 text-xs font-medium"
            :class="
              viewMode === 'kanban'
                ? 'bg-n-brand text-white'
                : 'bg-n-solid-1 text-n-slate-11'
            "
            @click="viewMode = 'kanban'"
          >
            <span class="i-lucide-columns-3 size-4" />
            {{ t('PIPELINES.KANBAN_VIEW') }}
          </button>
          <button
            class="flex h-9 items-center gap-1.5 px-3 text-xs font-medium"
            :class="
              viewMode === 'table'
                ? 'bg-n-brand text-white'
                : 'bg-n-solid-1 text-n-slate-11'
            "
            @click="viewMode = 'table'"
          >
            <span class="i-lucide-table-2 size-4" />
            {{ t('PIPELINES.TABLE_VIEW') }}
          </button>
        </div>
      </div>
    </header>

    <div class="grid shrink-0 grid-cols-2 gap-2 border-b border-n-weak p-4 sm:grid-cols-3 xl:grid-cols-6">
      <div
        v-for="card in metricCards"
        :key="card.label"
        class="rounded-xl border border-n-weak bg-n-solid-2 p-3"
      >
        <div class="flex items-center gap-2 text-xs font-medium text-n-slate-10">
          <span class="size-4 text-n-brand" :class="card.icon" />
          <span class="truncate">{{ card.label }}</span>
        </div>
        <div class="mt-2 truncate text-lg font-semibold text-n-slate-12">
          {{ card.value }}
        </div>
      </div>
    </div>

    <main class="min-h-0 flex-1 overflow-hidden">
      <div
        v-if="uiFlags.isFetching || uiFlags.isFetchingDeals"
        class="flex h-full items-center justify-center text-sm text-n-slate-10"
      >
        Carregando CRM…
      </div>

      <div
        v-else-if="viewMode === 'kanban'"
        class="flex h-full min-w-0 gap-3 overflow-x-auto overflow-y-hidden p-4"
      >
        <section
          v-for="stage in stages"
          :key="stage.id"
          class="flex w-[310px] shrink-0 flex-col overflow-hidden rounded-xl border border-n-weak bg-n-solid-2"
          @dragover.prevent
          @drop="onDrop(stage.id)"
        >
          <header class="border-b border-n-weak p-3">
            <div class="flex items-center justify-between gap-2">
              <div class="flex min-w-0 items-center gap-2">
                <span
                  class="size-2.5 shrink-0 rounded-full"
                  :style="{ backgroundColor: stage.color }"
                />
                <h2 class="truncate text-sm font-semibold text-n-slate-12">
                  {{ stage.name }}
                </h2>
              </div>
              <span class="rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-10">
                {{ dealsForStage(stage.id).length }}
              </span>
            </div>
            <p class="mt-1 text-xs font-medium text-n-slate-10">
              {{ formatMoney(stageTotal(stage.id), analytics.currency) }}
            </p>
          </header>

          <div class="min-h-0 flex-1 space-y-2 overflow-y-auto p-2">
            <button
              v-for="deal in dealsForStage(stage.id)"
              :key="deal.id"
              draggable="true"
              class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-left shadow-sm transition hover:border-n-brand hover:shadow"
              @dragstart="onDragStart(deal.id)"
              @click="openDeal(deal)"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="min-w-0">
                  <h3 class="truncate text-sm font-semibold text-n-slate-12">
                    {{ deal.title }}
                  </h3>
                  <p class="mt-0.5 truncate text-xs text-n-slate-10">
                    {{ deal.contact?.name || 'Sem contato vinculado' }}
                  </p>
                </div>
                <span
                  class="shrink-0 rounded-md px-1.5 py-0.5 text-[10px] font-medium"
                  :class="statusClass(deal.status)"
                >
                  {{ statusLabel(deal.status) }}
                </span>
              </div>

              <div class="mt-3 flex items-center justify-between gap-2">
                <span class="text-sm font-semibold text-n-slate-12">
                  {{ formatMoney(deal.value, deal.currency) }}
                </span>
                <span class="text-xs text-n-amber-10">
                  {{ '★'.repeat(Number(deal.priority_stars) || 0) }}
                </span>
              </div>

              <div class="mt-2 flex items-center justify-between gap-2 text-[11px] text-n-slate-10">
                <span>{{ Number(deal.probability) || 0 }}%</span>
                <span class="truncate">{{ deal.assignee?.name || 'Sem responsável' }}</span>
              </div>
            </button>

            <button
              class="flex h-20 w-full items-center justify-center rounded-lg border border-dashed border-n-weak text-xs font-medium text-n-slate-10 hover:border-n-brand hover:text-n-brand"
              @click="openCreateDeal(stage.id)"
            >
              + {{ t('PIPELINES.ADD_DEAL') }}
            </button>
          </div>
        </section>

        <div
          v-if="!stages.length"
          class="flex h-full min-w-full items-center justify-center text-sm text-n-slate-10"
        >
          Este funil ainda não possui etapas. Abra as configurações para adicionar a primeira.
        </div>
      </div>

      <div v-else class="h-full overflow-auto p-4">
        <div class="overflow-hidden rounded-xl border border-n-weak">
          <table class="w-full min-w-[980px] border-collapse text-left text-sm">
            <thead class="bg-n-solid-2 text-xs uppercase tracking-wide text-n-slate-10">
              <tr>
                <th class="px-4 py-3">Oportunidade</th>
                <th class="px-4 py-3">Contato</th>
                <th class="px-4 py-3">Etapa</th>
                <th class="px-4 py-3">Valor</th>
                <th class="px-4 py-3">Prob.</th>
                <th class="px-4 py-3">Responsável</th>
                <th class="px-4 py-3">Fechamento</th>
                <th class="px-4 py-3">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak bg-n-solid-1">
              <tr
                v-for="deal in filteredDeals"
                :key="deal.id"
                class="cursor-pointer hover:bg-n-alpha-1"
                @click="openDeal(deal)"
              >
                <td class="px-4 py-3 font-medium text-n-slate-12">
                  {{ deal.title }}
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ deal.contact?.name || '—' }}
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ selectedStageName(deal) }}
                </td>
                <td class="px-4 py-3 font-medium text-n-slate-12">
                  {{ formatMoney(deal.value, deal.currency) }}
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ Number(deal.probability) || 0 }}%
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ deal.assignee?.name || '—' }}
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ deal.expected_close_date || '—' }}
                </td>
                <td class="px-4 py-3">
                  <span
                    class="rounded-md px-2 py-1 text-xs font-medium"
                    :class="statusClass(deal.status)"
                  >
                    {{ statusLabel(deal.status) }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </main>

    <div
      v-if="showDealForm"
      class="fixed inset-0 z-[65] flex items-center justify-center bg-black/40 p-4"
      @click.self="showDealForm = false"
    >
      <section class="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-xl bg-n-background shadow-2xl">
        <header class="flex items-center justify-between border-b border-n-weak p-4">
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ t('PIPELINES.ADD_DEAL') }}
          </h2>
          <button class="size-8 rounded-lg hover:bg-n-alpha-2" @click="showDealForm = false">
            <span class="i-lucide-x size-4" />
          </button>
        </header>

        <div class="grid gap-4 p-5 sm:grid-cols-2">
          <label class="flex flex-col gap-1.5 sm:col-span-2">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.TITLE') }}</span>
            <input v-model="form.title" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm" />
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.VALUE') }}</span>
            <input v-model.number="form.value" type="number" min="0" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm" />
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.EXPECTED_REVENUE') }}</span>
            <input v-model.number="form.expected_revenue" type="number" min="0" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm" />
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.STAGE') }}</span>
            <select v-model.number="form.pipeline_stage_id" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm">
              <option v-for="stage in stages" :key="stage.id" :value="stage.id">
                {{ stage.name }}
              </option>
            </select>
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.PROBABILITY') }} (%)</span>
            <input v-model.number="form.probability" type="number" min="0" max="100" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm" />
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.CONTACT') }}</span>
            <select v-model.number="form.contact_id" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm">
              <option :value="null">Sem contato</option>
              <option v-for="contact in contacts" :key="contact.id" :value="contact.id">
                {{ contact.name || contact.email || contact.phone_number || `#${contact.id}` }}
              </option>
            </select>
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.ASSIGNEE') }}</span>
            <select v-model.number="form.assignee_id" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm">
              <option :value="null">Sem responsável</option>
              <option v-for="agent in agents" :key="agent.id" :value="agent.id">
                {{ agent.name }}
              </option>
            </select>
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.CLOSE_DATE') }}</span>
            <input v-model="form.expected_close_date" type="date" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm" />
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.PRIORITY') }}</span>
            <select v-model.number="form.priority_stars" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm">
              <option :value="0">—</option>
              <option :value="1">★</option>
              <option :value="2">★★</option>
              <option :value="3">★★★</option>
            </select>
          </label>

          <label class="flex flex-col gap-1.5 sm:col-span-2">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.SOURCE') }}</span>
            <input v-model="form.campaign_source" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm" />
          </label>

          <label class="flex flex-col gap-1.5 sm:col-span-2">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.NOTES') }}</span>
            <textarea v-model="form.notes" rows="4" class="rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm" />
          </label>
        </div>

        <footer class="flex justify-end gap-2 border-t border-n-weak p-4">
          <button class="h-9 rounded-lg border border-n-weak px-3 text-sm" @click="showDealForm = false">
            {{ t('PIPELINES.FORM.CANCEL') }}
          </button>
          <button class="h-9 rounded-lg bg-n-brand px-4 text-sm font-medium text-white" @click="createDeal">
            {{ t('PIPELINES.FORM.SAVE') }}
          </button>
        </footer>
      </section>
    </div>

    <div
      v-if="showSettings && selectedPipeline"
      class="fixed inset-0 z-[65] flex items-center justify-center bg-black/40 p-4"
      @click.self="showSettings = false"
    >
      <section class="max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-xl bg-n-background shadow-2xl">
        <header class="flex items-center justify-between border-b border-n-weak p-4">
          <div>
            <h2 class="text-lg font-semibold text-n-slate-12">
              {{ t('PIPELINES.SETTINGS') }}
            </h2>
            <p class="text-xs text-n-slate-10">Personalize o funil, suas etapas, cores e probabilidades.</p>
          </div>
          <button class="size-8 rounded-lg hover:bg-n-alpha-2" @click="showSettings = false">
            <span class="i-lucide-x size-4" />
          </button>
        </header>

        <div class="space-y-5 p-5">
          <div class="flex flex-wrap items-end gap-2">
            <label class="flex min-w-64 flex-1 flex-col gap-1.5">
              <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.SETTINGS_PANEL.RENAME') }}</span>
              <input v-model="settingsName" class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm" />
            </label>
            <button class="h-10 rounded-lg border border-n-brand px-4 text-sm font-medium text-n-brand" @click="savePipelineName">
              {{ t('PIPELINES.FORM.SAVE') }}
            </button>
          </div>

          <div>
            <div class="mb-2 flex items-center justify-between">
              <h3 class="font-semibold text-n-slate-12">{{ t('PIPELINES.SETTINGS_PANEL.STAGES') }}</h3>
              <button class="h-8 rounded-lg border border-n-weak px-3 text-xs font-medium" @click="addStage">
                + {{ t('PIPELINES.SETTINGS_PANEL.ADD_STAGE') }}
              </button>
            </div>

            <div class="space-y-2">
              <div
                v-for="(stage, index) in stageDrafts"
                :key="stage.id"
                class="grid gap-2 rounded-lg border border-n-weak bg-n-solid-2 p-3 md:grid-cols-[auto_1fr_110px_90px_auto]"
              >
                <div class="flex items-center gap-1">
                  <button class="size-7 rounded border border-n-weak" :disabled="index === 0" @click="moveStage(index, 'up')">↑</button>
                  <button class="size-7 rounded border border-n-weak" :disabled="index === stageDrafts.length - 1" @click="moveStage(index, 'down')">↓</button>
                </div>
                <input v-model="stage.name" class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm" />
                <input v-model="stage.color" type="color" class="h-9 w-full rounded-lg border border-n-weak bg-n-solid-1 p-1" />
                <input v-model.number="stage.default_probability" type="number" min="0" max="100" class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-sm" />
                <div class="flex items-center justify-end gap-1">
                  <button class="size-8 rounded border border-n-weak text-n-brand" @click="saveStage(stage)">
                    <span class="i-lucide-check size-4" />
                  </button>
                  <button class="size-8 rounded border border-n-weak text-n-ruby-11" @click="deleteStage(stage)">
                    <span class="i-lucide-trash-2 size-4" />
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div class="border-t border-n-weak pt-4">
            <button class="rounded-lg border border-n-ruby-7 px-3 py-2 text-sm font-medium text-n-ruby-11" @click="deletePipeline">
              {{ t('PIPELINES.SETTINGS_PANEL.DELETE_PIPELINE') }}
            </button>
          </div>
        </div>
      </section>
    </div>

    <DealDetailModal
      :open="showDealDetail"
      :deal="selectedDeal"
      :stages="stages"
      @close="showDealDetail = false"
      @updated="refreshDeals"
    />
  </div>
</template>
