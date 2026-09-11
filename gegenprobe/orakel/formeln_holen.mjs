#!/usr/bin/env node
/**
 * Holt jedes Rechenobjekt aus dem Katalog der laufenden Datenbank in eine
 * Datei — Sichten, gespeicherte Sichten, Funktionen — so, wie PostgreSQL sie
 * heute wirklich hält (`pg_get_viewdef`, `pg_get_functiondef`), nicht so, wie
 * eine Migration sie einmal geschrieben hat.
 *
 * Wozu: Das Orakel in diesem Verzeichnis ist eine zweite, unabhängige
 * Rechnung derselben Zahlen. Wer sie schreibt, braucht die geltende Formel
 * an einer Stelle, und wer sie später prüft, muss sehen, ob sich die Formel
 * seither bewegt hat. Beides leistet dieser Abzug: Er ist deterministisch
 * (sortiert, ohne Zeitstempel), also zeigt `git diff` genau die Objekte, die
 * sich geändert haben.
 *
 *   node gegenprobe/orakel/formeln_holen.mjs                 # Datenbank „demo"
 *   node gegenprobe/orakel/formeln_holen.mjs --db probe_x    # eine andere
 *
 * Ergebnis: gegenprobe/orakel/formeln/<art>_<name>.sql und MANIFEST.md.
 */
import { execFileSync } from 'node:child_process'
import { mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHash } from 'node:crypto'

const HIER = dirname(fileURLToPath(import.meta.url))
const ZIEL = join(HIER, 'formeln')
const argv = process.argv.slice(2)
const db = argv.includes('--db') ? argv[argv.indexOf('--db') + 1] : 'demo'
const SOCKET = process.env.PGSOCKET ?? '/tmp/pgsock'
const PORT = process.env.PGPORT ?? '55432'
const url = `postgresql://postgres@/${db}?host=${SOCKET}&port=${PORT}`

const frage = (sql) => JSON.parse(execFileSync('psql', [url, '-qtAX', '-v', 'ON_ERROR_STOP=1', '-c',
  `select coalesce(json_agg(z), '[]'::json)::text from (${sql}) z`], { encoding: 'utf8' }))

const sichten = frage(`
  select c.relname as name, case c.relkind when 'v' then 'sicht' else 'gespeichert' end as art,
         pg_get_viewdef(c.oid, true) as text,
         coalesce(obj_description(c.oid, 'pg_class'), '') as beschreibung
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('v', 'm')
   order by c.relname`)
const funktionen = frage(`
  select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as name, 'funktion' as art,
         pg_get_functiondef(p.oid) as text,
         coalesce(obj_description(p.oid, 'pg_proc'), '') as beschreibung
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
   order by p.proname, p.oid`)

rmSync(ZIEL, { recursive: true, force: true })
mkdirSync(ZIEL, { recursive: true })

// Dateiname: Art + Name. Bei Funktionen steht der Name ohne Signatur; ist er
// mehrfach vergeben (Überladung), unterscheidet ein kurzer Hash der Signatur.
const kurzname = (o) => o.art === 'funktion' ? o.name.replace(/\(.*$/, '') : o.name
const haeufig = new Map()
for (const o of funktionen) haeufig.set(kurzname(o), (haeufig.get(kurzname(o)) ?? 0) + 1)
const dateiname = (o) => {
  const basis = `${o.art}_${kurzname(o)}`
  if (o.art === 'funktion' && haeufig.get(kurzname(o)) > 1) {
    return `${basis}_${createHash('sha256').update(o.name).digest('hex').slice(0, 6)}.sql`
  }
  return `${basis}.sql`
}

const zeilen = []
for (const o of [...sichten, ...funktionen]) {
  const datei = dateiname(o)
  const kopf = `-- ${o.art}: ${o.name}\n${o.beschreibung ? `-- ${o.beschreibung.replace(/\n/g, '\n-- ')}\n` : ''}\n`
  const inhalt = kopf + o.text.trimEnd() + '\n'
  writeFileSync(join(ZIEL, datei), inhalt)
  zeilen.push({ art: o.art, name: o.name, datei, zeilen: o.text.split('\n').length,
                hash: createHash('sha256').update(o.text).digest('hex').slice(0, 12) })
}

const manifest = [
  '# Die Rechenobjekte, wie die Datenbank sie heute hält',
  '',
  `Abgezogen aus der Datenbank \`${db}\` mit \`node gegenprobe/orakel/formeln_holen.mjs\`.`,
  'Nicht von Hand ändern — der nächste Abzug überschreibt alles. Wer wissen will, ob sich',
  'eine Formel seit dem letzten Abzug bewegt hat, zieht neu ab und sieht es im `git diff`.',
  '',
  `${sichten.filter(s => s.art === 'sicht').length} Sichten, ${sichten.filter(s => s.art === 'gespeichert').length} gespeicherte Sichten, ${funktionen.length} Funktionen.`,
  '',
  '| Art | Name | Datei | Zeilen | Prüfsumme |',
  '|---|---|---|---|---|',
  ...zeilen.map(z => `| ${z.art} | \`${z.name}\` | \`${z.datei}\` | ${z.zeilen} | \`${z.hash}\` |`),
  '',
].join('\n')
writeFileSync(join(ZIEL, 'MANIFEST.md'), manifest)
console.log(`${zeilen.length} Objekte nach ${ZIEL} geschrieben (${readdirSync(ZIEL).length} Dateien)`)
