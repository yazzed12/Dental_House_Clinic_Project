const AUTH_PROVIDERS = new Set(['legacy', 'supabase']);

export function readRuntimeConfig(env = import.meta.env) {
  const authProvider = (env?.VITE_AUTH_PROVIDER || 'legacy').trim().toLowerCase();
  const dataTransport = (env?.VITE_DATA_TRANSPORT || 'fastapi').trim().toLowerCase();
  if (!AUTH_PROVIDERS.has(authProvider)) {
    throw new Error(
      `Invalid VITE_AUTH_PROVIDER "${authProvider}". Expected legacy or supabase.`,
    );
  }
  if (dataTransport !== 'fastapi') {
    throw new Error(
      'S2 permits only VITE_DATA_TRANSPORT=fastapi; Data API migration is not enabled.',
    );
  }

  return {
    authProvider,
    dataTransport,
    supabaseUrl: (env?.VITE_SUPABASE_URL || '').trim(),
    supabasePublishableKey: (env?.VITE_SUPABASE_PUBLISHABLE_KEY || '').trim(),
  };
}

export function validateSupabaseBrowserConfig(config) {
  const missing = [];
  if (!config.supabaseUrl) missing.push('VITE_SUPABASE_URL');
  if (!config.supabasePublishableKey) {
    missing.push('VITE_SUPABASE_PUBLISHABLE_KEY');
  }
  if (missing.length) {
    throw new Error(`Missing Supabase browser configuration: ${missing.join(', ')}`);
  }

  let parsed;
  try {
    parsed = new URL(config.supabaseUrl);
  } catch {
    throw new Error('VITE_SUPABASE_URL must be a valid absolute HTTPS URL.');
  }
  if (parsed.protocol !== 'https:') {
    throw new Error('VITE_SUPABASE_URL must use HTTPS.');
  }
  return config;
}
