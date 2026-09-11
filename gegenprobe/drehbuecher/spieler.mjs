#!/usr/bin/env node
/**
 * Der Spieler: führt die SQL-Szenen eines Drehbuchs gegen eine Datenbank aus
 * und prüft nach jeder Szene, was das Drehbuch erwartet.
 *
 * Er liest aus `NN_*.md` alle Blöcke der Form
 *   ```sql szene S1      … wird ausgeführt (mit ON_ERROR_STOP)
 *   ```sql pruefung S1   … muss genau eine Zeile mit Spalte ok = true liefern;
 *                          weitere Spalten werden im Bericht gezeigt
 * in der Reihenfolge, in der sie im Drehbuch stehen.
 *
 * Ohne --db legt er eine Kopie der Demo an (drehbuch_NN, template demo) und
 * spielt dort — so bleibt die Demo unberührt und jeder Lauf beginnt gleich.
 *
 * Ausgabe: je Szene eine Zeile — ok / FEHLT (Prüfung liefert nicht ok) /
 * BRICHT (Szene wirft einen Fehler) — und gegenprobe/drehbuecher/befund_NN.json.
 * Exit 1, sobald eine Szene nicht ok ist; Exit 2, wenn das Drehbuch keine
 * einzige Szene hat.
 */
import { execFileSync } from 'node:child_process'
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HIER = dirname(fileURLToPath(import.meta.url))
const argv = process.argv.slice(2)
const nummer = argv.find(a => /^\d\d$/.test(a))
if (!nummer) { console.error('Aufruf: node gegenprobe/drehbuecher/spieler.mjs NN [--db name]'); process.exit(2) }
const SOCKET = process.env.PGSOCKET ?? '/tmp/pgsock', PORT = process.env.PGPORT ?? '55432'
const url = db => `postgresql://postgres@/${db}?host=${SOCKET}&port=${PORT}`
const psql = (db, sql) => execFileSync('psql', [url(db), '-qtAX', '-v', 'ON_ERROR_STOP=1', '-c', sql], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })

const datei = readdirSync(HIER).find(f => f.startsWith(`${nummer}_`) && f.endsWith('.md'))
if (!datei) { console.error(`Kein Drehbuch ${nummer}_*.md`); process.exit(2) }
const text = readFileSync(join(HIER, datei), 'utf8')

// Blöcke in Reihenfolge einsammeln
const bloecke = []
const re = /```sql (szene|pruefung) (S\d+)\n([\s\S]*?)```/g
let m
while ((m = re.exec(text))) bloecke.push({ art: m[1], szene: m[2], sql: m[3].trim() })
if (bloecke.length === 0) { console.error(datei + ': keine \x60\x60\x60sql szene/pruefung-Blöcke'); process.exit(2) }

let db = argv.includes('--db') ? argv[argv.indexOf('--db') + 1] : null
if (!db) {
  db = `drehbuch_${nummer}`
  psql('postgres', `drop database if exists ${db}`)
  psql('postgres', `create database ${db} template demo`)
  console.log(`Kopie der Demo als ${db}`)
}

// auth.uid() kommt aus der Sitzung (stub_supabase.sql: request.jwt.claim.sub). Die
// Vorgabewerte erfasser/eroeffnet_von brauchen sie — wie in der App die Anmeldung.
const ALS_BETRIEBSLEITER = "select set_config('request.jwt.claim.sub', (select id::text from profil where rolle = 'admin' order by erstellt_ts limit 1), false);\n"

const befund = []
let schlecht = 0
for (const b of bloecke) {
  if (b.art === 'szene') {
    try { psql(db, ALS_BETRIEBSLEITER + b.sql); befund.push({ szene: b.szene, art: 'szene', ergebnis: 'ok' }) }
    catch (e) {
      const fehler = String(e.stderr ?? e.message).split('\n').find(z => /ERROR/.test(z)) ?? String(e.message)
      befund.push({ szene: b.szene, art: 'szene', ergebnis: 'BRICHT', fehler }); schlecht++
      console.log(`${b.szene} szene    BRICHT  ${fehler}`)
      continue
    }
  } else {
    let zeilen
    try { zeilen = JSON.parse(psql(db, `select coalesce(json_agg(z), '[]'::json)::text from (${b.sql}) z`)) }
    catch (e) {
      const fehler = String(e.stderr ?? e.message).split('\n').find(z => /ERROR/.test(z)) ?? String(e.message)
      befund.push({ szene: b.szene, art: 'pruefung', ergebnis: 'BRICHT', fehler }); schlecht++
      console.log(`${b.szene} prüfung  BRICHT  ${fehler}`)
      continue
    }
    const ok = zeilen.length === 1 && zeilen[0].ok === true
    befund.push({ szene: b.szene, art: 'pruefung', ergebnis: ok ? 'ok' : 'FEHLT', zeilen })
    if (!ok) schlecht++
    const rest = zeilen[0] ? Object.entries(zeilen[0]).filter(([k]) => k !== 'ok').map(([k, v]) => `${k}=${v}`).join(' ') : 'keine Zeile'
    console.log(`${b.szene} prüfung  ${ok ? 'ok     ' : 'FEHLT  '} ${rest}`)
  }
}
writeFileSync(join(HIER, `befund_${nummer}.json`), JSON.stringify({ drehbuch: datei, db, befund }, null, 2))
console.log(`${bloecke.filter(b => b.art === 'pruefung').length} Prüfungen, ${schlecht} nicht ok`)
process.exit(schlecht ? 1 : 0)
