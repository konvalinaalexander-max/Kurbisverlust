#!/usr/bin/env node
/**
 * Der Läufer des Prüfwerks.
 *
 *   node pruefwerk/lauf.mjs                 alle Sonden
 *   node pruefwerk/lauf.mjs --nur 04 05     nur diese
 *   node pruefwerk/lauf.mjs --schnell       ohne die langen (06 Mutation)
 *   node pruefwerk/lauf.mjs --db demo       welche Datenbank die Demodaten hat
 *
 * Ergebnis: pruefwerk/befunde/befunde.json (maschinenlesbar, stabile Kennungen)
 * und ein kurzer Stand auf der Konsole. Den Bericht schreibt bericht.mjs.
 *
 * Zwei Eigenschaften, ohne die ein Prüfwerk nichts wert ist:
 *
 *   Wiederholbar — zweimal laufen ergibt dieselben Befunde mit denselben
 *   Kennungen. Ein Befund, der beim zweiten Lauf verschwindet, ist ein Fehler
 *   im Prüfwerk, nicht im Programm.
 *
 *   Selbstprüfend — jede Sonde hat einen eingebauten Fall, bei dem sie
 *   anschlagen *muss*. Schlägt sie dort nicht an, meldet sich der Läufer.
 *   Eine Sonde, die nichts findet und auch nichts finden *kann*, ist
 *   schlimmer als keine: Sie erzeugt Zuversicht ohne Grund.
 */
import { readdirSync } from 'node:fs'
import { join } from 'node:path'
import { HIER, nummernZuruecksetzen, schreibe } from './umgebung.mjs'

const argv = process.argv.slice(2)
const holen = (name, sonst = null) => {
  const i = argv.indexOf(name)
  return i >= 0 ? (argv[i + 1] ?? true) : sonst
}
const nur = argv.includes('--nur')
  ? argv.slice(argv.indexOf('--nur') + 1).filter(a => !a.startsWith('--'))
  : null
const schnell = argv.includes('--schnell')
const db = holen('--db', 'demo')

const sonden = readdirSync(join(HIER, 'sonden')).filter(f => f.endsWith('.mjs')).sort()
  .filter(f => !nur || nur.some(n => f.startsWith(n)))

const umgebung = { db, schnell }
const alle = []
const stand = []

console.log(`Prüfwerk — ${sonden.length} Sonden, Datenbank "${db}"${schnell ? ', schnell' : ''}\n`)

for (const datei of sonden) {
  const modul = await import(join(HIER, 'sonden', datei))
  const name = datei.replace(/\.mjs$/, '')
  if (schnell && modul.lang) { console.log(`  ⏭  ${name} — übersprungen (--schnell)`); continue }
  nummernZuruecksetzen()
  const start = Date.now()
  let befunde = [], fehler = null
  try {
    befunde = (await modul.laufen(umgebung)) ?? []
  } catch (e) {
    fehler = e.message
  }
  // Selbstprüfung: findet die Sonde ihren eingebauten Fehler?
  let selbst = 'ohne'
  if (modul.selbstprobe) {
    try { selbst = (await modul.selbstprobe(umgebung)) ? 'ok' : 'STUMPF' }
    catch (e) { selbst = 'Fehler: ' + e.message }
  }
  const s = ((Date.now() - start) / 1000).toFixed(1)
  if (fehler) console.log(`  ✗  ${name} — abgebrochen nach ${s}s: ${fehler}`)
  else console.log(`  ${befunde.length ? '!' : '·'}  ${name} — ${befunde.length} Befunde, ${s}s, Selbstprobe: ${selbst}`)
  if (selbst === 'STUMPF') console.log(`     ⚠ Diese Sonde findet ihren eigenen eingebauten Fehler nicht.`)
  alle.push(...befunde)
  stand.push({ sonde: name, befunde: befunde.length, sekunden: Number(s), selbstprobe: selbst, fehler })
}

alle.sort((a, b) => (b.klasse ?? 0) - (a.klasse ?? 0) || String(a.id).localeCompare(String(b.id)))
schreibe('pruefwerk/befunde/befunde.json', JSON.stringify({ stand, befunde: alle }, null, 2) + '\n')

const jeKlasse = alle.reduce((m, b) => (m[b.klasse] = (m[b.klasse] ?? 0) + 1, m), {})
console.log(`\n${alle.length} Befunde — Klasse 3 (Bedeutung): ${jeKlasse[3] ?? 0}, `
          + `Klasse 2 (Kette): ${jeKlasse[2] ?? 0}, Klasse 1 (technisch): ${jeKlasse[1] ?? 0}`)
console.log('pruefwerk/befunde/befunde.json geschrieben')
if (stand.some(s => s.selbstprobe === 'STUMPF')) {
  console.log('\nWARNUNG: mindestens eine Sonde ist stumpf.')
  process.exit(2)
}
