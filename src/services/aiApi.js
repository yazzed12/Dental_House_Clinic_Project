import { apiRequest } from './httpClient.js';

export const sendAiChat = (messages) => apiRequest('/ai/chat', { method: 'POST', body: { messages } });
