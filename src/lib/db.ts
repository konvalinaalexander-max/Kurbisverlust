import { supabase } from './supabase'
import type { Charge, Gebinde, SorteKaliber } from './typen'

/** Stammdaten ändern sich während einer Sitzung praktisch nie. */
let stammCache: { chargen: Charge[]; kaliber: SorteKaliber[]; gebinde: Gebinde[] } | null = null

export async function stammdaten(neu = false) {
  if (stammCache && !neu) return stammCache
  const [c, k, g] = await Promise.all([
    supabase.from('charge').select('*').order('nr'),
    supabase.from('sorte_kaliber').select('*').order('sorte'),
    supabase.from('gebinde').select('*').order('art'),
  ])
  if (c.error) throw c.error
  if (k.error) throw k.error
  if (g.error) throw g.error
  stammCache = {
    chargen: (c.data ?? []) as Charge[],
    kaliber: (k.data ?? []) as SorteKaliber[],
    gebinde: (g.data ?? []) as Gebinde[],
  }
  return stammCache
}

export async function einstellung<T>(schluessel: string, ersatz: T): Promise<T> {
  const { data } = await supabase.from('einstellung').select('wert').eq('schluessel', schluessel).maybeSingle()
  return (data?.wert as T) ?? ersatz
}

export function chargeText(c: Charge | undefined): string {
  return c ? `${c.nr} — ${c.schlag} · ${c.sorte}` : '—'
}

/** Supabase-Fehler so aufbereiten, dass sie in der Halle etwas aussagen. */
export function fehlerText(fehler: unknown): string {
  const f = fehler as { message?: string; code?: string; details?: string } | null
  if (!f) return 'Unbekannter Fehler'
  if (f.code === '42501' || f.message?.includes('row-level security')) {
    return 'Dafür fehlt die Berechtigung — das darf nur der Betriebsleiter.'
  }
  if (f.code === '23505') return 'Dieser Eintrag existiert bereits.'
  // PGRST202: Die App ruft etwas, das die Datenbank nicht kennt. Im Betrieb
  // heisst das fast immer dasselbe — die Datenbank wurde eingerichtet, als es
  // das noch nicht gab, und ist seither nicht aktualisiert worden. Die rohe
  // Meldung ("Could not find the function … in the schema cache") sagt einem
  // Betriebsleiter nichts; sie hat einmal für Ratlosigkeit gesorgt, obwohl der
  // Weg heraus drei Klicks lang ist.
  if (f.code === 'PGRST202' || f.message?.includes('schema cache')) {
    return 'Die Datenbank ist älter als die App und kennt einen Teil der Auswertung noch nicht. '
      + 'Das behebt Schritt 3 im README: setup.sql nochmal im Supabase-SQL-Editor ausführen — '
      + 'dieselbe Datei wie beim Einrichten, die Daten bleiben dabei stehen. Danach hier F5.'
  }
  return f.message ?? 'Unbekannter Fehler'
}
