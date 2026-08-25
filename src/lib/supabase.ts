import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const istKonfiguriert = Boolean(url && anonKey)

// Ohne Konfiguration bleibt die App bedienbar genug, um den Hinweis anzuzeigen,
// statt beim Start mit einer weißen Seite abzustürzen.
export const supabase = createClient(
  url ?? 'https://nicht-konfiguriert.supabase.co',
  anonKey ?? 'nicht-konfiguriert',
  { auth: { persistSession: true, autoRefreshToken: true } },
)
