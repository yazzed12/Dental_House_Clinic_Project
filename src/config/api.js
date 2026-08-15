const rawBase = import.meta.env?.VITE_API_URL || 'http://localhost:8000';

export const API_BASE_URL = rawBase.replace(/\/+$/, '');
export const API_URL = `${API_BASE_URL}/api`;
