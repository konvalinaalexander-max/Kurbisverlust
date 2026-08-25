import { createClient } from '@supabase/supabase-js'
import { konfigurationPruefen } from './konfiguration'

const url = (import.meta.env.VITE_SUPABASE_URL as string | undefined)?.trim()
const anonKey = (import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined)?.trim()

export const istKonfiguriert = Boolean(url && anonKey)
export const konfigurationsProblem = konfigurationPruefen(url, anonKey)

// Ohne Konfiguration bleibt die App bedienbar genug, um den Hinweis anzuzeigen,
// statt beim Start mit einer weißen Seite abzustürzen.
export const supabase = createClient(
  url ?? 'https://nicht-konfiguriert.supabase.co',
  anonKey ?? 'nicht-konfiguriert',
  { auth: { persistSession: true, autoRefreshToken: true } },
)
