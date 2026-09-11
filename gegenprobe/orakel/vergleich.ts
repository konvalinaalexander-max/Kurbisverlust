/**
 * Der Vergleich: Zeilen der Datenbank gegen Zeilen des Orakels, Spalte für
 * Spalte, mit Toleranz — und ein Bericht, der sagt, **wo** es abweicht,
 * nicht nur **dass**.
 *
 * Toleranzen sind eine Entscheidung, keine Bequemlichkeit:
 *   · 1e-9 relativ für Formeln, die beide Seiten aus denselben Eingaben rechnen
 *   · 5e-7 absolut, wo die Datenbank mit zahl(…, 6) rundet
 *   · 0.005 absolut, wo sie mit zahl(…, 2) rundet
 * Wer eine Toleranz weiter fasst, schreibt daneben, warum.
 */
import { execFileSync } from 'node:child_process'
import { nahe } from './zahlen.ts'

export interface Abweichung { schluessel: string; spalte: string; db: unknown; orakel: unknown }

export interface Spalte { db: string; orakel: string; rel?: number; abs?: number }

/** Zwei Listen über einen Schlüssel paaren und Spalten vergleichen. Fehlende Partner sind auch Abweichungen. */
export function vergleiche<A extends Record<string, unknown>, B extends Record<string, unknown>>(
  dbZeilen: A[], orakelZeilen: B[], schluessel: { db: (a: A) => string; orakel: (b: B) => string }, spalten: Spalte[],
): Abweichung[] {
  const o = new Map(orakelZeilen.map(b => [schluessel.orakel(b), b]))
  const gesehen = new Set<string>()
  const ab: Abweichung[] = []
  for (const a of dbZeilen) {
    const k = schluessel.db(a)
    gesehen.add(k)
    const b = o.get(k)
    if (!b) { ab.push({ schluessel: k, spalte: '*', db: 'Zeile', orakel: 'fehlt' }); continue }
    for (const s of spalten) {
      const x = a[s.db] == null ? null : Number(a[s.db]), y = b[s.orakel] == null ? null : Number(b[s.orakel])
      if (!nahe(x, y, s.rel ?? 1e-9, s.abs ?? 1e-9)) ab.push({ schluessel: k, spalte: s.db, db: a[s.db], orakel: b[s.orakel] })
    }
  }
  for (const [k] of o) if (!gesehen.has(k)) ab.push({ schluessel: k, spalte: '*', db: 'fehlt', orakel: 'Zeile' })
  return ab
}

export function bericht(name: string, ab: Abweichung[], n: number): string {
  if (ab.length === 0) return `${name}: ${n} Zeilen, keine Abweichung`
  const kopf = `${name}: ${ab.length} Abweichung(en) in ${n} Zeilen`
  const zeilen = ab.slice(0, 12).map(a => `  ${a.schluessel} · ${a.spalte}: Datenbank ${String(a.db)} ≠ Orakel ${String(a.orakel)}`)
  return [kopf, ...zeilen, ab.length > 12 ? `  … und ${ab.length - 12} weitere` : ''].filter(Boolean).join('\n')
}

/* ---------- Die Datenbank lesen, ohne Treiber: psql als JSON ---------------- */

export const DB_URL = process.env.GEGENPROBE_DB
  ?? `postgresql://postgres@/${process.env.GEGENPROBE_DBNAME ?? 'demo'}?host=${process.env.PGSOCKET ?? '/tmp/pgsock'}&port=${process.env.PGPORT ?? '55432'}`

let erreichbar: boolean | null = null
export function dbErreichbar(): boolean {
  if (erreichbar != null) return erreichbar
  try { execFileSync('psql', [DB_URL, '-qtAX', '-c', 'select 1'], { stdio: ['ignore', 'pipe', 'ignore'] }); erreichbar = true }
  catch { erreichbar = false }
  return erreichbar
}

/** Eine Abfrage, Ergebnis als Objektliste. Zahlen kommen als Zahl, wenn numeric — psql gibt sie als Text, wir wandeln. */
export function frage<T = Record<string, unknown>>(sql: string): T[] {
  const aus = execFileSync('psql', [DB_URL, '-qtAX', '-v', 'ON_ERROR_STOP=1', '-c',
    `select coalesce(json_agg(z), '[]'::json)::text from (${sql}) z`], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 })
  return JSON.parse(aus) as T[]
}
