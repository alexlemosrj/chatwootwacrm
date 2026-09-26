import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ContactDeals from '../ContactDeals.vue';
import pipelines from 'dashboard/store/modules/pipelines';
import DealsAPI from 'dashboard/api/deals';
import PipelinesAPI from 'dashboard/api/pipelines';

vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: { value: 1 } }),
}));
vi.mock('dashboard/api/deals');
vi.mock('dashboard/api/pipelines');

describe('ContactDeals conversation contract', () => {
  it.each([7, '7', null])(
    'sends sidebar display id %s explicitly through the real pipeline store',
    async conversationDisplayId => {
      DealsAPI.get.mockResolvedValue({ data: { payload: [] } });
      DealsAPI.create.mockResolvedValue({ data: { id: 90, status: 'open' } });
      PipelinesAPI.get.mockResolvedValue({
        data: { payload: [{ id: 2, stages: [{ id: 3 }] }] },
      });
      const store = createStore({
        modules: {
          pipelines: { ...pipelines, state: structuredClone(pipelines.state) },
        },
      });
      const wrapper = mount(ContactDeals, {
        props: { contactId: 5, conversationDisplayId },
        global: {
          plugins: [store],
        },
      });
      await flushPromises();
      await wrapper.findAll('button')[0].trigger('click');
      await flushPromises();

      const { deal } = DealsAPI.create.mock.calls[0][0];
      expect(deal.conversation_display_id).toBe(
        conversationDisplayId === null ? null : 7
      );
      expect(deal).not.toHaveProperty('conversation_id');
      expect(deal).toMatchObject({
        contact_id: 5,
        pipeline_id: 2,
        pipeline_stage_id: 3,
      });
      expect(DealsAPI.get).toHaveBeenCalledWith({ contact_id: 5 });
      wrapper.unmount();
    }
  );
});
