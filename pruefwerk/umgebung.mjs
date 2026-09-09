/**
 * Was alle Sonden brauchen: eine Datenbank ansprechen, Befunde formen,
 * Wegwerf-Datenbanken bauen.
 *
 * Das Prüfwerk ist **nicht Teil der App**. Es importiert nichts aus src/, es
 * steht in keinem Build, und die App weiss nichts von ihm. Es liest den Code
 * und die Datenbank wie ein Aussenstehender — genau das ist der Punkt: Ein
 * Werkzeug, das dieselben Bausteine benutzt wie das Geprüfte, prüft dieselbe
 * Annahme zweimal.
 */
import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const HIER = dirname(fileURLToPath(import.meta.url))
export const WURZEL = join(HIER, '..')

const SOCKET = process.env.PG_SOCKET ?? '/tmp/pgsock'
const PORT = process.env.PG_PORT ?? '55432'
export const url = (db) => `postgresql://postgres@/${db}?host=${SOCKET}&port=${PORT}`

/**
 * Eine Abfrage, Zeilen als Objekte. Kein Treiber, kein npm — psql und JSON.
 *
 * Der Alias heisst absichtlich `pw_zeile` und nicht `t`: `json_agg(t)` aggregiert
 * die *Spalte* t, sobald die Abfrage eine hat, und liefert dann still eine Liste
 * von Zahlen statt von Zeilen. Genau das ist hier einmal passiert.
 */
export function frage(db, sql) {
  const roh = execFileSync('psql', [url(db), '-qtAX', '-v', 'ON_ERROR_STOP=1', '-c',
    `select coalesce(json_agg(pw_zeile), '[]'::json)::text from (${sql}) pw_zeile`],
    { encoding: 'utf8', maxBuffer: 512 * 1024 * 1024 })
  return JSON.parse(roh.trim() || '[]')
}

/** Eine einzelne Zahl oder ein einzelner Wert. */
export function wert(db, sql) {
  const r = frage(db, sql)
  if (!r.length) return null
  return Object.values(r[0])[0]
}

/** Anweisungen ausführen, ohne Ergebnis. Wirft mit der Postgres-Meldung. */
export function tue(db, sql, { still = true } = {}) {
  try {
    return execFileSync('psql', [url(db), '-qtAX', '-v', 'ON_ERROR_STOP=1', '-c',
      (still ? 'set client_min_messages = warning; ' : '') + sql],
      { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
  } catch (e) {
    const text = (e.stderr ?? '') + (e.stdout ?? '')
    throw new Error(text.split('\n').filter(z => /error|fehler/i.test(z)).slice(0, 3).join(' | ') || e.message)
  }
}

/** Datei einspielen. */
export function spiele(db, datei) {
  try {
    execFileSync('psql', [url(db), '-qX', '-v', 'ON_ERROR_STOP=1', '-f', datei],
      { encoding: 'utf8', stdio: ['ignore', 'ignore', 'pipe'], maxBuffer: 64 * 1024 * 1024 })
  } catch (e) {
    throw new Error(`${datei}: ${String(e.stderr ?? e.message).split('\n').filter(z => /error/i.test(z))[0] ?? ''}`)
  }
}

/**
 * Eine leere Datenbank mit dem heutigen Schema — ohne Demodaten.
 * Für Papierfälle (Sonde 04, 07) und Zufallssaisons (Sonde 05): Dort soll
 * genau das drin sein, was der Fall vorschreibt, und sonst nichts.
 */
export function datenbank(db) {
  execFileSync('psql', [url('postgres'), '-qtAX', '-c',
    `select 1 from pg_database where datname = '${db}'`], { encoding: 'utf8' }).trim()
    || execFileSync('psql', [url('postgres'), '-qX', '-c', `create database ${db}`], { encoding: 'utf8' })
  return db
}

export function frischesSchema(db) {
  datenbank(db)
  tue(db, `drop schema if exists public cascade; create schema public;
           drop schema if exists auth cascade; drop schema if exists storage cascade;`)
  spiele(db, join(WURZEL, 'supabase/test/stub_supabase.sql'))
  for (const f of readdirSync(join(WURZEL, 'supabase/migrations')).filter(f => f.endsWith('.sql')).sort())
    spiele(db, join(WURZEL, 'supabase/migrations', f))
  tue(db, `insert into auth.users (id, email, raw_user_meta_data) values
             ('11111111-1111-1111-1111-111111111111', 'chef@hof.test', '{"name":"Chef"}');
           update profil set rolle = 'admin', aktiv = true;`)
  return db
}

/** Alles neu rechnen — wie die App es täte. */
export function rechne(db) { tue(db, 'select auswertung_aktualisieren()') }

/* ---------- Befunde ------------------------------------------------------ */

let laufendeNummer = new Map()
/**
 * Ein Befund. `groesse` ist Pflicht: Ohne Grösse ist es eine Meinung, keine
 * Feststellung — und eine Liste von Meinungen nimmt niemand ernst.
 */
export function befund({ sonde, kuerzel, klasse, ort, titel, steht_da, muesste, warum,
                         beleg, groesse, sicherheit = 'mittel', gegenrede, marke,
                         aufwand = 'klein' }) {
  const n = (laufendeNummer.get(kuerzel) ?? 0) + 1
  laufendeNummer.set(kuerzel, n)
  return {
    id: `${kuerzel}-${String(n).padStart(3, '0')}`,
    sonde, klasse, ort, titel, steht_da, muesste, warum, beleg,
    groesse, sicherheit, gegenrede, marke, aufwand, stand: 'offen',
  }
}
export function nummernZuruecksetzen() { laufendeNummer = new Map() }

/* ---------- Quelltext lesen ---------------------------------------------- */

export function lies(pfad) { return readFileSync(join(WURZEL, pfad), 'utf8') }

export function dateien(verzeichnis, muster = /\.(ts|tsx)$/) {
  const raus = []
  const gehe = (d) => {
    for (const e of readdirSync(join(WURZEL, d), { withFileTypes: true })) {
      const p = `${d}/${e.name}`
      if (e.isDirectory()) gehe(p)
      else if (muster.test(e.name)) raus.push(p)
    }
  }
  gehe(verzeichnis)
  return raus.sort()
}

/** Zeilennummer einer Fundstelle. */
export function zeileVon(text, index) { return text.slice(0, index).split('\n').length }

export function schreibe(pfad, inhalt) {
  const ziel = join(WURZEL, pfad)
  mkdirSync(dirname(ziel), { recursive: true })
  writeFileSync(ziel, inhalt)
}

/**
 * Eine Wegwerf-Kopie einer bestehenden Datenbank. Schneller als das Schema neu
 * aufzubauen, und — wichtiger — die Kopie enthält dieselben Daten, sodass ein
 * Befund auf ihr auch für das Original gilt.
 */
export function kopie(von, nach) {
  execFileSync('psql', [url('postgres'), '-qX', '-c', `drop database if exists ${nach}`,
    '-c', `create database ${nach} template ${von}`],
    { encoding: 'utf8', stdio: ['ignore', 'ignore', 'pipe'] })
  return nach
}
