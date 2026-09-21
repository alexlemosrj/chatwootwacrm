<!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';

const props = defineProps({
  deal: {
    type: Object,
    default: null,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  open: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'updated']);

const store = useStore();
const { t } = useI18n();

const form = reactive({});
const activities = ref([]);
const events = ref([]);
const activityForm = reactive({
  title: '',
  activity_type: 'followup',
  due_at: '',
});
const saving = ref(false);
const activitySaving = ref(false);

const orderedStages = computed(() =>
  [...props.stages].sort((a, b) => a.position - b.position)
);

const loadSideData = async () => {
  if (!props.deal?.id) return;
  const [loadedActivities, loadedEvents] = await Promise.all([
    store.dispatch('pipelines/fetchDealActivities', props.deal.id),
    store.dispatch('pipelines/fetchDealEvents', props.deal.id),
  ]);
  activities.value = loadedActivities;
  events.value = loadedEvents;
};

const resetForm = () => {
  Object.keys(form).forEach(key => delete form[key]);
  if (!props.deal) return;

  Object.assign(form, {
    id: props.deal.id,
    title: props.deal.title || '',
    value: Number(props.deal.value) || 0,
    currency: props.deal.currency || 'BRL',
    expected_revenue: Number(props.deal.expected_revenue) || 0,
    probability: Number(props.deal.probability) || 0,
    priority_stars: Number(props.deal.priority_stars) || 0,
    expected_close_date: props.deal.expected_close_date || '',
    status: props.deal.status || 'open',
    pipeline_stage_id: props.deal.pipeline_stage_id,
    assignee_id: props.deal.assignee_id || null,
    notes: props.deal.notes || '',
    campaign_source: props.deal.campaign_source || '',
  });
};

watch(
  () => [props.open, props.deal?.id],
  async ([open]) => {
    if (!open || !props.deal) return;
    resetForm();
    await loadSideData();
  },
  { immediate: true }
);

const save = async () => {
  if (!form.id || !form.title?.trim()) return;
  saving.value = true;
  try {
    await store.dispatch('pipelines/updateDeal', {
      id: form.id,
      title: form.title.trim(),
      value: Number(form.value) || 0,
      currency: form.currency || 'BRL',
      expected_revenue: Number(form.expected_revenue) || 0,
      probability: Number(form.probability) || 0,
      priority_stars: Number(form.priority_stars) || 0,
      expected_close_date: form.expected_close_date || null,
      status: form.status,
      pipeline_stage_id: form.pipeline_stage_id,
      assignee_id: form.assignee_id || null,
      notes: form.notes || '',
      campaign_source: form.campaign_source || '',
    });
    await loadSideData();
    emit('updated');
    useAlert('Oportunidade atualizada.');
  } catch (error) {
    useAlert(error?.response?.data?.message || error.message || 'Erro ao salvar oportunidade.');
  } finally {
    saving.value = false;
  }
};

const moveToStage = async stageId => {
  if (stageId === form.pipeline_stage_id) return;
  form.pipeline_stage_id = stageId;
  await save();
};

const setStatus = async status => {
  form.status = form.status === status ? 'open' : status;
  await save();
};

const addActivity = async () => {
  if (!activityForm.title.trim()) return;
  activitySaving.value = true;
  try {
    await store.dispatch('pipelines/createActivity', {
      deal_id: props.deal.id,
      contact_id: props.deal.contact_id || null,
      assignee_id: form.assignee_id || null,
      title: activityForm.title.trim(),
      activity_type: activityForm.activity_type,
      due_at: activityForm.due_at || null,
      status: 'planned',
    });
    activityForm.title = '';
    activityForm.due_at = '';
    await loadSideData();
  } finally {
    activitySaving.value = false;
  }
};

const completeActivity = async activity => {
  await store.dispatch('pipelines/updateActivity', {
    id: activity.id,
    dealId: props.deal.id,
    status: activity.status === 'completed' ? 'planned' : 'completed',
  });
  await loadSideData();
};

const activityStateClass = activity => {
  if (activity.status === 'completed') return 'text-n-teal-11';
  if (!activity.due_at) return 'text-n-slate-11';
  const due = new Date(activity.due_at).getTime();
  return due < Date.now() ? 'text-n-ruby-11' : 'text-n-amber-11';
};

const formatDate = value => {
  if (!value) return '—';
  return new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value));
};

const eventTitle = event => {
  const labels = {
    deal_created: 'Oportunidade criada',
    deal_updated: 'Oportunidade atualizada',
    stage_changed: 'Etapa alterada',
    status_changed: 'Status alterado',
    assignment_changed: 'Responsável alterado',
    activity_created: 'Atividade criada',
    activity_updated: 'Atividade atualizada',
    activity_deleted: 'Atividade removida',
  };
  return labels[event.event_type] || event.event_type;
};
</script>

<template>
  <div
    v-if="open && deal"
    class="fixed inset-0 z-[70] flex items-stretch justify-end bg-black/40"
    @click.self="emit('close')"
  >
    <section
      class="flex h-full w-full max-w-6xl flex-col bg-n-background shadow-2xl lg:flex-row"
    >
      <div class="flex min-w-0 flex-1 flex-col overflow-y-auto border-r border-n-weak">
        <header class="sticky top-0 z-10 border-b border-n-weak bg-n-background/95 p-4 backdrop-blur">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p class="text-xs font-medium uppercase tracking-wide text-n-slate-10">
                CRM · #{{ deal.id }}
              </p>
              <h2 class="text-xl font-semibold text-n-slate-12">
                {{ form.title }}
              </h2>
            </div>
            <div class="flex items-center gap-2">
              <button
                class="rounded-lg border border-n-teal-7 px-3 py-2 text-sm font-medium text-n-teal-11 hover:bg-n-teal-3"
                :class="{ 'bg-n-teal-3': form.status === 'won' }"
                @click="setStatus('won')"
              >
                ✓ {{ t('PIPELINES.STATUS.WON') }}
              </button>
              <button
                class="rounded-lg border border-n-ruby-7 px-3 py-2 text-sm font-medium text-n-ruby-11 hover:bg-n-ruby-3"
                :class="{ 'bg-n-ruby-3': form.status === 'lost' }"
                @click="setStatus('lost')"
              >
                ✕ {{ t('PIPELINES.STATUS.LOST') }}
              </button>
              <button
                class="flex size-9 items-center justify-center rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
                @click="emit('close')"
              >
                <span class="i-lucide-x size-4" />
              </button>
            </div>
          </div>

          <div class="mt-4 flex min-w-0 gap-1 overflow-x-auto">
            <button
              v-for="stage in orderedStages"
              :key="stage.id"
              class="relative min-w-28 flex-1 rounded-md border px-3 py-2 text-xs font-medium transition-colors"
              :class="
                stage.id === form.pipeline_stage_id
                  ? 'border-n-brand bg-n-brand/10 text-n-brand'
                  : 'border-n-weak bg-n-solid-1 text-n-slate-11 hover:border-n-strong'
              "
              @click="moveToStage(stage.id)"
            >
              <span
                class="mr-1.5 inline-block size-2 rounded-full"
                :style="{ backgroundColor: stage.color }"
              />
              {{ stage.name }}
            </button>
          </div>
        </header>

        <div class="grid gap-5 p-5 md:grid-cols-2">
          <label class="flex flex-col gap-1.5 md:col-span-2">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.TITLE') }}</span>
            <input
              v-model="form.title"
              class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            />
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.VALUE') }}</span>
            <input
              v-model.number="form.value"
              type="number"
              min="0"
              step="0.01"
              class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            />
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.EXPECTED_REVENUE') }}</span>
            <input
              v-model.number="form.expected_revenue"
              type="number"
              min="0"
              step="0.01"
              class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            />
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.PROBABILITY') }} (%)</span>
            <input
              v-model.number="form.probability"
              type="number"
              min="0"
              max="100"
              class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            />
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.CLOSE_DATE') }}</span>
            <input
              v-model="form.expected_close_date"
              type="date"
              class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            />
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.PRIORITY') }}</span>
            <select
              v-model.number="form.priority_stars"
              class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            >
              <option :value="0">—</option>
              <option :value="1">★</option>
              <option :value="2">★★</option>
              <option :value="3">★★★</option>
            </select>
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.SOURCE') }}</span>
            <input
              v-model="form.campaign_source"
              class="h-10 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            />
          </label>

          <label class="flex flex-col gap-1.5 md:col-span-2">
            <span class="text-xs font-medium text-n-slate-11">{{ t('PIPELINES.FORM.NOTES') }}</span>
            <textarea
              v-model="form.notes"
              rows="5"
              class="rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            />
          </label>
        </div>

        <div class="mt-auto flex justify-end border-t border-n-weak p-4">
          <button
            class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
            :disabled="saving"
            @click="save"
          >
            {{ saving ? '…' : t('PIPELINES.FORM.SAVE') }}
          </button>
        </div>
      </div>

      <aside class="flex w-full shrink-0 flex-col overflow-y-auto bg-n-solid-2 lg:w-[380px]">
        <div class="border-b border-n-weak p-4">
          <h3 class="font-semibold text-n-slate-12">{{ t('PIPELINES.ACTIVITIES.TITLE') }}</h3>
          <div class="mt-3 grid gap-2">
            <input
              v-model="activityForm.title"
              placeholder="Ex: Retornar contato"
              class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            />
            <div class="grid grid-cols-2 gap-2">
              <select
                v-model="activityForm.activity_type"
                class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-sm text-n-slate-12"
              >
                <option value="followup">Follow-up</option>
                <option value="call">Ligação</option>
                <option value="whatsapp">WhatsApp</option>
                <option value="meeting">Reunião</option>
                <option value="task">Tarefa</option>
                <option value="email">E-mail</option>
              </select>
              <input
                v-model="activityForm.due_at"
                type="datetime-local"
                class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-xs text-n-slate-12"
              />
            </div>
            <button
              class="h-9 rounded-lg border border-n-brand px-3 text-sm font-medium text-n-brand hover:bg-n-brand/10"
              :disabled="activitySaving"
              @click="addActivity"
            >
              + {{ t('PIPELINES.ACTIVITIES.ADD') }}
            </button>
          </div>
        </div>

        <div class="border-b border-n-weak p-4">
          <div v-if="!activities.length" class="text-xs text-n-slate-10">
            Nenhuma atividade registrada.
          </div>
          <button
            v-for="activity in activities"
            :key="activity.id"
            class="mb-2 flex w-full items-start gap-3 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-left hover:border-n-strong"
            @click="completeActivity(activity)"
          >
            <span
              class="mt-0.5 size-4 shrink-0 rounded-full border"
              :class="
                activity.status === 'completed'
                  ? 'border-n-teal-8 bg-n-teal-9'
                  : 'border-n-slate-7'
              "
            />
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                {{ activity.title }}
              </span>
              <span class="mt-1 block text-xs" :class="activityStateClass(activity)">
                {{ activity.activity_type }} · {{ formatDate(activity.due_at) }}
              </span>
            </span>
          </button>
        </div>

        <div class="p-4">
          <h3 class="mb-3 font-semibold text-n-slate-12">{{ t('PIPELINES.HISTORY.TITLE') }}</h3>
          <div v-if="!events.length" class="text-xs text-n-slate-10">
            Nenhum evento registrado.
          </div>
          <div
            v-for="event in events"
            :key="event.id"
            class="relative border-l border-n-weak pb-4 pl-4 last:pb-0"
          >
            <span class="absolute -left-1 top-1 size-2 rounded-full bg-n-brand" />
            <p class="text-sm font-medium text-n-slate-12">
              {{ eventTitle(event) }}
            </p>
            <p class="mt-0.5 text-xs text-n-slate-10">
              {{ event.actor?.name || 'Sistema' }} · {{ formatDate(event.created_at * 1000) }}
            </p>
          </div>
        </div>
      </aside>
    </section>
  </div>
</template>
