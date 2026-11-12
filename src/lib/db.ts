import { supabase } from './supabase'
import type { Charge, Gebinde, SorteKaliber } from './typen'
import type { SchlagAlias } from './import'
import { alleSeiten, type Ordnung } from './seiten'

/** Eine Abfrage, auf die noch Filter kommen dürfen (`.eq`, `.gte`, …). */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Abfrage = any

/**
 * Alle Zeilen einer Tabelle oder Sicht (Runde BL) — nie nur die ersten
 * tausend, die die Schnittstelle je Anfrage gibt, und nie eine stille
 * Obergrenze. Die Regel steht in ./seiten.ts; hier nur der Anschluss an die
 * Datenbank. Wirft den Fehler der Datenbank, wie er ist.
 */
export function alleLesen<T extends object>(tabelle: string, opt: {
  spalten?: string; ordnung?: Ordnung[]; filter?: (q: Abfrage) => Abfrage
} = {}): Promise<T[]> {
  return alleSeiten<T>((von, bis, ordnung, zaehlen) => {
    let q: Abfrage = supabase.from(tabelle).select(opt.spalten ?? '*', zaehlen ? { count: 'exact' } : undefined)
    if (opt.filter) q = opt.filter(q)
    for (const [spalte, auf] of ordnung) q = q.order(spalte, { ascending: auf })
    return q.range(von, bis)
  }, opt.ordnung)
}

/** alleLesen in der Form einer einzelnen Anfrage ({ data, error }) — für Stellen, die mehrere Anfragen nebeneinander stellen. */
export function alsAntwort<T>(p: Promise<T[]>): Promise<{ data: T[] | null; error: { message: string; code?: string } | null }> {
  return p.then(data => ({ data, error: null }), (error: { message: string; code?: string }) => ({ data: null, error }))
}

/**
 * Eine lange Liste von Schlüsseln in Teilen abfragen (Runde BL): Die Liste
 * steht in der Adresse der Anfrage, und die hat eine Länge — bei einigen
 * hundert Nummern bricht sie. Jeder Teil wird ganz geholt (alleLesen).
 */
export async function inTeilen<S, T>(schluessel: S[], holen: (teil: S[]) => Promise<T[]>, jeTeil = 200): Promise<T[]> {
  const alle: T[] = []
  for (let i = 0; i < schluessel.length; i += jeTeil) alle.push(...await holen(schluessel.slice(i, i + jeTeil)))
  return alle
}

/**
 * Stammdaten ändern sich selten — aber nicht nie. Am 22. Oktober kamen Oettli
 * (1719) und Trüeb (1763) mit setup.sql dazu; ein Handy, auf dem die App seit
 * dem Vortag offen war, kannte sie nicht und hätte „Diese Charge gibt es
 * (noch) nicht" gesagt. Darum gilt das Gemerkte fünf Minuten; danach holt der
 * nächste Aufruf neu. Ohne Netz bleibt das Gemerkte — die Halle arbeitet
 * weiter, nur ohne die neueste Charge.
 */
const STAMM_HOECHSTENS_MS = 5 * 60 * 1000
let stammCache: { chargen: Charge[]; kaliber: SorteKaliber[]; gebinde: Gebinde[]; aliase: SchlagAlias[] } | null = null
let stammZeit = 0

export async function stammdaten(neu = false) {
  if (stammCache && !neu && Date.now() - stammZeit < STAMM_HOECHSTENS_MS) return stammCache
  try {
    const [c, k, g, a] = await Promise.all([
      supabase.from('charge').select('*').order('nr'),
      supabase.from('sorte_kaliber').select('*').order('sorte'),
      supabase.from('gebinde').select('*').order('art'),
      // 0122: wie ein Schlag anderswo heisst (Inauen = Oettli, Trüb = Trüeb).
      // Fehlt die Tabelle (setup.sql noch nicht eingespielt), gilt keine — die
      // Halle arbeitet trotzdem.
      supabase.from('schlag_alias').select('alias, schlag'),
    ])
    if (c.error) throw c.error
    if (k.error) throw k.error
    if (g.error) throw g.error
    stammCache = {
      chargen: (c.data ?? []) as Charge[],
      kaliber: (k.data ?? []) as SorteKaliber[],
      gebinde: (g.data ?? []) as Gebinde[],
      aliase: a.error ? [] : (a.data ?? []) as SchlagAlias[],
    }
    stammZeit = Date.now()
    return stammCache
  } catch (f) {
    if (stammCache && !neu) return stammCache
    throw f
  }
}

/**
 * Runde AS: Chargen anlegen, die das Erntejournal neu nennt (Oettli 1719,
 * Trüb 1763) — vor den Paletten, sonst hätten diese keine Charge. Was es schon
 * gibt, bleibt, wie es ist: angelegt wird nur, nie überschrieben.
 */
export async function chargenAnlegen(neu: { nr: number; schlag: string; sorte: string; saison: number }[]): Promise<number> {
  if (neu.length === 0) return 0
  const { error } = await supabase.from('charge')
    .upsert(neu.map(c => ({ nr: c.nr, schlag: c.schlag, sorte: c.sorte, saison: c.saison })), { onConflict: 'nr', ignoreDuplicates: true })
  if (error) throw error
  void stammdaten(true)
  return neu.length
}

/**
 * Eine Einstellung lesen — der Ersatz gilt, wenn es den Schlüssel nicht gibt
 * oder sein Wert leer ist. Runde AZ: Antwortet die Datenbank gar nicht
 * (Netz, Rechte), fliegt der Fehler, statt still der Ersatz zu gelten. Sonst
 * hielte das Leeren-Fenster eine scharfe Datenbank für eine Übung und die
 * Stammdaten zeigten ein leeres Feld, als wäre nichts gespeichert.
 */
export async function einstellung<T>(schluessel: string, ersatz: T): Promise<T> {
  const { data, error } = await supabase.from('einstellung').select('wert').eq('schluessel', schluessel).maybeSingle()
  if (error) throw error
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
