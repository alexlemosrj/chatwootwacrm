import { frontendURL } from '../../../helper/URLHelper';
import PipelinesIndex from './pages/PipelinesIndex.vue';

const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/pipelines'),
    name: 'pipelines_index',
    meta,
    component: PipelinesIndex,
  },
];

export default { routes };
