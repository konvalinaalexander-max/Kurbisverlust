#!/usr/bin/env node
/**
 * Der Läufer der Gegenprobe: alle *.test.ts unter gegenprobe/, mit dem
 * Testläufer von Node — und einem Zähler, der übersprungene Fälle laut macht.
 *
 *   node gegenprobe/lauf.mjs              # ohne Datenbank: Orakel-Selbstprüfung, Achsenregeln
 *   node gegenprobe/lauf.mjs --db demo    # dazu das Orakel gegen die Datenbank
 *
 * Exit 0 nur, wenn nichts fehlgeschlagen ist **und** — mit --db — nichts
 * übersprungen wurde. Ohne --db ist Überspringen erwartet, wird aber gezählt.
 */
import { spawnSync } from 'node:child_process'
import { readdirSync, statSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HIER = dirname(fileURLToPath(import.meta.url))
const argv = process.argv.slice(2)
const db = argv.includes('--db') ? argv[argv.indexOf('--db') + 1] : null

const dateien = []
const suchen = d => { for (const n of readdirSync(d)) { const p = join(d, n); if (statSync(p).isDirectory()) { if (n !== 'formeln' && n !== 'daten') suchen(p) } else if (n.endsWith('.test.ts')) dateien.push(p) } }
suchen(HIER)
dateien.sort()

const umgebung = { ...process.env }
if (db) umgebung.GEGENPROBE_DBNAME = db
else umgebung.GEGENPROBE_DB = 'postgresql://niemand@/keine?host=/nirgends&port=1'   // erzwingt „nicht erreichbar" — ohne --db keine Datenbank

const lauf = spawnSync(process.execPath, ['--test', '--test-reporter=tap', ...dateien], { env: umgebung, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
const tap = lauf.stdout
process.stdout.write(tap.split('\n').filter(z => /^(not ok|ok|# (tests|pass|fail|skipped))/.test(z)).join('\n') + '\n')
const zahl = name => Number((tap.match(new RegExp(`^# ${name} (\\d+)`, 'm')) ?? [0, 0])[1])
const tests = zahl('tests'), pass = zahl('pass'), fail = zahl('fail'), skipped = zahl('skipped')
if (fail) process.stdout.write(tap.split('\n').filter(z => /^\s+(error|expected|actual|Datenbank|K[1-6] )/.test(z) || /≠/.test(z)).slice(0, 60).join('\n') + '\n')
console.log(`\nGegenprobe: ${tests} Fälle, ${pass} bestanden, ${fail} fehlgeschlagen, ${skipped} übersprungen${db ? ` (Datenbank ${db})` : ' (ohne Datenbank — Vergleiche übersprungen, nicht bestanden)'}`)
process.exit(fail ? 1 : (db && skipped) ? 3 : 0)
