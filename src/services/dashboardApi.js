import { API_BASE_URL } from '../config/api.js';
import { apiRequest } from './httpClient.js';
import { readRuntimeConfig } from '../config/runtime.js';
import { getAiAuthHeaders } from './reportApi.js';

export function createDashboardService({
  provider = readRuntimeConfig().authProvider,
  supabaseClient,
  request = apiRequest,
} = {}) {
  const requestWithCurrentSession = async path => request(path, {
    headers: await getAiAuthHeaders({ provider, supabaseClient }),
  });
  return {
    getDashboard: () => requestWithCurrentSession('/dashboard'),
    getAuditLogs: () => requestWithCurrentSession(`${API_BASE_URL}/logs`),
  };
}

const dashboardService = createDashboardService();
export const getDashboard = dashboardService.getDashboard;
export const getAuditLogs = dashboardService.getAuditLogs;
