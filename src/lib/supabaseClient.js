import { createClient } from '@supabase/supabase-js';
import { readRuntimeConfig, validateSupabaseBrowserConfig } from '../config/runtime.js';

let browserClient;

export function getSupabaseClient(config = readRuntimeConfig()) {
  if (browserClient) return browserClient;

  validateSupabaseBrowserConfig(config);
  browserClient = createClient(
    config.supabaseUrl,
    config.supabasePublishableKey,
    {
      auth: {
        autoRefreshToken: true,
        detectSessionInUrl: true,
        persistSession: true,
      },
    },
  );
  return browserClient;
}

export function resetSupabaseClientForTests() {
  browserClient = undefined;
}
