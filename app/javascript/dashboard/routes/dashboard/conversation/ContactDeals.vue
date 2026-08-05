<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
  conversationId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountId } = useAccount();

const deals = ref([]);
const loading = ref(false);

const load = async () => {
  if (!props.contactId) return;
  loading.value = true;
  try {
    deals.value = await store.dispatch(
      'pipelines/fetchContactDeals',
      props.contactId
    );
  } finally {
    loading.value = false;
  }
};

watch(() => props.contactId, load, { immediate: true });

const formatMoney = (value, currency = 'USD') => {
  try {
    return new Intl.NumberFormat(undefined, {
      style: 'currency',
      currency,
      maximumFractionDigits: 0,
    }).format(Number(value) || 0);
  } catch {
    return `${Number(value) || 0}`;
  }
};

const createDeal = async () => {
  await store.dispatch('pipelines/get');
  const pipeline = store.getters['pipelines/getSelectedPipeline'];
  if (!pipeline?.stages?.length) return;
  await store.dispatch('pipelines/createDeal', {
    title: `Deal — contact #${props.contactId}`,
    pipeline_id: pipeline.id,
    pipeline_stage_id: pipeline.stages[0].id,
    contact_id: Number(props.contactId),
    conversation_id: props.conversationId
      ? Number(props.conversationId)
      : null,
    value: 0,
    currency: 'USD',
    status: 'open',
  });
  await load();
};

const openBoard = () => {
  router.push({
    name: 'pipelines_index',
    params: { accountId: accountId.value },
  });
};

const hasDeals = computed(() => deals.value.length > 0);
</script>

<template>
  <div class="flex flex-col gap-2 px-1 py-2">
    <div v-if="loading" class="text-xs text-n-slate-11">…</div>
    <div v-else-if="!hasDeals" class="text-xs text-n-slate-11">
      {{ t('PIPELINES.CONTACT_SIDEBAR.EMPTY') }}
    </div>
    <button
      v-for="deal in deals"
      :key="deal.id"
      type="button"
      class="rounded-md border border-n-weak bg-n-solid-1 p-2 text-left text-xs hover:border-n-brand"
      @click="openBoard"
    >
      <div class="font-medium">{{ deal.title }}</div>
      <div class="text-n-slate-11">
        {{ formatMoney(deal.value, deal.currency) }} · {{ deal.status }}
      </div>
    </button>
    <div class="flex gap-2">
      <button
        type="button"
        class="rounded bg-n-brand px-2 py-1 text-xs text-white"
        @click="createDeal"
      >
        {{ t('PIPELINES.CONTACT_SIDEBAR.CREATE') }}
      </button>
      <button
        type="button"
        class="rounded border border-n-weak px-2 py-1 text-xs"
        @click="openBoard"
      >
        {{ t('PIPELINES.CONTACT_SIDEBAR.OPEN_BOARD') }}
      </button>
    </div>
  </div>
</template>
