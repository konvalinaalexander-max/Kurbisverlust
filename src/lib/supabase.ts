import { createClient } from '@supabase/supabase-js'
import { konfigurationPruefen } from './konfiguration'
import { demoAktiv, demoZugang } from './demo'

/**
 * Welche Datenbank diese Seite bedient, entscheidet sich hier — einmal, beim
 * Laden. Normalfall ist der Betrieb; steht der Merkzettel aus demo.ts, ist es
 * die Demo-Datenbank. Danach gibt es keinen Wechsel mehr: Der Client wird
 * genau einmal gebaut, und alles, was die App später tut, geht an ihn.
 */
const imDemo = demoAktiv()

const url = imDemo
  ? demoZugang?.url
  : (import.meta.env.VITE_SUPABASE_URL as string | undefined)?.trim()
const anonKey = imDemo
  ? demoZugang?.schluessel
  : (import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined)?.trim()

export const istKonfiguriert = Boolean(url && anonKey)
export const konfigurationsProblem = konfigurationPruefen(url, anonKey)

/** Läuft diese Seite gerade auf der Demo-Datenbank? */
export const imDemoModus = imDemo

// Ohne Konfiguration bleibt die App bedienbar genug, um den Hinweis anzuzeigen,
// statt beim Start mit einer weißen Seite abzustürzen.
export const supabase = createClient(
  url ?? 'https://nicht-konfiguriert.supabase.co',
  anonKey ?? 'nicht-konfiguriert',
  { auth: { persistSession: true, autoRefreshToken: true } },
)
