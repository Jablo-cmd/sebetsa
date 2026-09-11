import { createClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/database.types';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing Supabase configuration. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY (see .env.example).',
  );
}

const AUTH_STORAGE_KEY = 'sebetsa-auth';
const PERSIST_PREFERENCE_KEY = 'sebetsa-auth-persist';

/**
 * Supabase writes the session to this storage adapter synchronously during
 * sign-in. Resolving the backing store per-call (instead of fixing it once
 * at client construction) is what lets "Remember me" toggle between
 * localStorage (survives browser restarts) and sessionStorage (cleared when
 * the tab closes) without recreating the client on every login.
 */
function resolveStorage(): Storage {
  return window.localStorage.getItem(PERSIST_PREFERENCE_KEY) === 'session'
    ? window.sessionStorage
    : window.localStorage;
}

/** Call before signInWithPassword so the resulting session lands in the right store. */
export function setAuthPersistence(remember: boolean): void {
  window.localStorage.setItem(PERSIST_PREFERENCE_KEY, remember ? 'local' : 'session');
}

const authStorage = {
  getItem: (key: string) => resolveStorage().getItem(key),
  setItem: (key: string, value: string) => resolveStorage().setItem(key, value),
  removeItem: (key: string) => {
    window.localStorage.removeItem(key);
    window.sessionStorage.removeItem(key);
  },
};

export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: authStorage,
    storageKey: AUTH_STORAGE_KEY,
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
});
