import { createClient } from '@supabase/supabase-js'
import { konfigurationPruefen, zugangBrauchbar } from './konfiguration'
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

/**
 * Ein Client, der immer entsteht — auch aus falschen Werten.
 *
 * Der Betrieb hat beim ersten Versuch einen schwarzen Bildschirm bekommen,
 * aus dem er nicht mehr herausfand. Ursache: createClient() wirft bei einer
 * Adresse ohne `https://`, und zwar hier, beim Auswerten des Moduls. Eine
 * Ausnahme an dieser Stelle bringt nicht eine Seite zu Fall, sondern das
 * ganze Bündel — main.tsx läuft nie, React zeichnet nie, und übrig bleibt
 * die leere Seite in der Hintergrundfarbe des Browsers.
 *
 * Also zwei Netze übereinander: Erst wird gefragt, ob die Werte taugen
 * (zugangBrauchbar), und falls nicht, nimmt der Client Platzhalter. Und weil
 * eine Prüfung nie alles kennt, was eine fremde Bibliothek ablehnt, liegt
 * darunter noch ein try/catch. Die App läuft dann mit einer Verbindung, die
 * ins Leere zeigt — genau das ist gewollt: Sie zeigt den Hinweis an, was zu
 * tun ist, statt schwarz zu bleiben.
 */
const ERSATZ_URL = 'https://nicht-konfiguriert.supabase.co'
const ERSATZ_KEY = 'nicht-konfiguriert'
const OPTIONEN = { auth: { persistSession: true, autoRefreshToken: true } }

function clientBauen() {
  if (zugangBrauchbar(url, anonKey)) {
    try {
      return createClient(url as string, anonKey as string, OPTIONEN)
    } catch { /* fällt unten auf den Platzhalter zurück */ }
  }
  return createClient(ERSATZ_URL, ERSATZ_KEY, OPTIONEN)
}

export const supabase = clientBauen()
