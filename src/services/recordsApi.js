import { apiRequest } from './httpClient.js';

export const listRecords = () => apiRequest('/records');
