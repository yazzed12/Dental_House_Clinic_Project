import { API_URL } from '../config/api.js';

export class HttpError extends Error {
  constructor(message, { status, data, url } = {}) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.data = data;
    this.url = url;
  }
}

export function legacyAuthHeaders(storage = globalThis.localStorage) {
  const token = storage?.getItem('clinic_token');
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function parseResponse(response) {
  if (response.status === 204) return null;
  const contentType = response.headers?.get?.('content-type') || '';
  if (contentType.includes('application/json')) return response.json();
  const text = await response.text();
  return text || null;
}

export async function apiRequest(path, {
  body,
  headers,
  auth = true,
  fetchImpl = globalThis.fetch,
  ...options
} = {}) {
  const url = /^https?:\/\//.test(path) ? path : `${API_URL}${path}`;
  const requestHeaders = {
    ...(auth ? legacyAuthHeaders() : {}),
    ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
    ...headers,
  };
  const response = await fetchImpl(url, {
    ...options,
    headers: requestHeaders,
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  const data = await parseResponse(response);
  if (!response.ok) {
    const detail = typeof data === 'object' && data?.detail;
    throw new HttpError(detail || `Request failed (${response.status}).`, {
      status: response.status,
      data,
      url,
    });
  }
  return data;
}

export async function apiBlobRequest(path, {
  headers,
  fetchImpl = globalThis.fetch,
  ...options
} = {}) {
  const url = /^https?:\/\//.test(path) ? path : `${API_URL}${path}`;
  const response = await fetchImpl(url, {
    ...options,
    headers: { ...legacyAuthHeaders(), ...headers },
  });
  if (!response.ok) {
    throw new HttpError(`Request failed (${response.status}).`, {
      status: response.status,
      url,
    });
  }
  return { blob: await response.blob(), headers: response.headers };
}
