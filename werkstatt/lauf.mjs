#!/usr/bin/env node
/**
 * Der Läufer der vier Werkstätten.
 *
 *   node werkstatt/lauf.mjs                    alle vier Werkstätten
 *   node werkstatt/lauf.mjs --nur a            nur Werkstatt A
 *   node werkstatt/lauf.mjs --nur a1 b3        nur diese Werkzeuge
 *   node werkstatt/lauf.mjs --schnell          ohne die langen Läufe
 *   node werkstatt/lauf.mjs --db demo          welche Datenbank die Demodaten hat
 *   node werkstatt/lauf.mjs --saat 4711        Saat für alles Zufällige
 *
 * Ergebnis: werkstatt/befunde/befunde.json und ein Stand auf der Konsole.
 * Den Bericht schreibt bericht.mjs.
 *
 * Die zwei Eigenschaften, die das Prüfwerk gelehrt hat, gelten hier genauso:
 *
 *   Wiederholbar — zweimal laufen ergibt dasselbe. Alles Zufällige hängt an
 *   `--saat`, nichts an der Uhr. Ein Befund, der beim zweiten Lauf
 *   verschwindet, ist ein Fehler in der Werkstatt, nicht im Programm.
 *
 *   Selbstprüfend — jedes Werkzeug hat einen Fall, in dem es anschlagen
 *   *muss*. Findet es ihn nicht, meldet der Läufer STUMPF und geht mit
 *   Rückgabewert 2. Genau daran ist in Runde L die Mutationssonde unbemerkt
 *   blind geworden; ein Werkzeug ohne Selbstprobe zählt nicht.
 */
import { readdirSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { nummernZuruecksetzen, schreibe } from './umgebung.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))

const WERKSTAETTEN = [
  { kuerzel: 'a', verzeichnis: 'a_rechenwerk', name: 'A — Rechenwerk',
    frage: 'Ist das der richtige Schätzer, und ist er ehrlich über sich selbst?' },
  { kuerzel: 'b', verzeichnis: 'b_fundament', name: 'B — Fundament',
    frage: 'Ist die Datenbank unter der Fachlogik gesund?' },
  { kuerzel: 'c', verzeichnis: 'c_bauwerk', name: 'C — Bauwerk',
    frage: 'Ist der Code so gebaut, wie ein Programm dieser Grösse gebaut sein sollte?' },
  { kuerzel: 'd', verzeichnis: 'd_nutzen', name: 'D — Nutzen',
    frage: 'Löst dieses Programm die Probleme des Betriebs?' },
]

const argv = process.argv.slice(2)
const holen = (name, sonst = null) => {
  const i = argv.indexOf(name)
  return i >= 0 ? (argv[i + 1] ?? true) : sonst
}
const nur = argv.includes('--nur')
  ? argv.slice(argv.indexOf('--nur') + 1).filter(a => !a.startsWith('--')).map(s => s.toLowerCase())
  : null
const schnell = argv.includes('--schnell')
const db = holen('--db', 'demo')
const saat = Number(holen('--saat', '20260909'))

const umgebung = { db, schnell, saat }
const alle = []
const messungen = []
const stand = []

const passt = (kuerzel, werkzeug) => !nur
  || nur.includes(kuerzel)
  || nur.some(n => werkzeug.toLowerCase().startsWith(n))

console.log(`Werkstatt — Datenbank "${db}", Saat ${saat}${schnell ? ', schnell' : ''}\n`)

for (const w of WERKSTAETTEN) {
  const verz = join(HIER, w.verzeichnis)
  if (!existsSync(verz)) continue
  const werkzeuge = readdirSync(verz).filter(f => f.endsWith('.mjs')).sort()
    .filter(f => passt(w.kuerzel, f))
  if (!werkzeuge.length) continue

  console.log(`── Werkstatt ${w.name} ${'─'.repeat(Math.max(0, 52 - w.name.length))}`)
  console.log(`   ${w.frage}\n`)

  for (const datei of werkzeuge) {
    const modul = await import(join(verz, datei))
    const name = datei.replace(/\.mjs$/, '')
    if (schnell && modul.lang) { console.log(`  ⏭  ${name} — übersprungen (--schnell)`); continue }
    nummernZuruecksetzen()
    const t0 = process.hrtime.bigint()
    let ergebnis = [], fehler = null
    try {
      ergebnis = (await modul.laufen(umgebung)) ?? []
    } catch (e) {
      fehler = e.message
    }
    const befunde = ergebnis.filter(x => x && x.art !== 'messung')
    const eigeneMessungen = ergebnis.filter(x => x && x.art === 'messung')

    let selbst = 'ohne'
    if (modul.selbstprobe) {
      try { selbst = (await modul.selbstprobe(umgebung)) ? 'ok' : 'STUMPF' }
      catch (e) { selbst = 'Fehler: ' + e.message }
    }

    const s = (Number(process.hrtime.bigint() - t0) / 1e9).toFixed(1)
    if (fehler) console.log(`  ✗  ${name} — abgebrochen nach ${s}s: ${fehler}`)
    else console.log(`  ${befunde.length ? '!' : '·'}  ${name} — ${befunde.length} Befunde`
                   + `${eigeneMessungen.length ? `, ${eigeneMessungen.length} Messungen` : ''}`
                   + `, ${s}s, Selbstprobe: ${selbst}`)
    if (selbst === 'STUMPF') console.log(`     ⚠ Dieses Werkzeug findet seinen eigenen eingebauten Fehler nicht.`)
    if (selbst === 'ohne') console.log(`     ⚠ Dieses Werkzeug hat keine Selbstprobe — sein Schweigen sagt nichts.`)

    alle.push(...befunde)
    messungen.push(...eigeneMessungen)
    stand.push({ werkstatt: w.name, werkzeug: name, befunde: befunde.length,
                 messungen: eigeneMessungen.length, sekunden: Number(s),
                 selbstprobe: selbst, fehler })
  }
  console.log()
}

alle.sort((a, b) => (b.klasse ?? 0) - (a.klasse ?? 0) || String(a.id).localeCompare(String(b.id)))
schreibe('werkstatt/befunde/befunde.json',
  JSON.stringify({ stand, befunde: alle, messungen, saat, db }, null, 2) + '\n')

const jeKlasse = alle.reduce((m, b) => (m[b.klasse] = (m[b.klasse] ?? 0) + 1, m), {})
const jeMarke = alle.reduce((m, b) => (m[b.marke] = (m[b.marke] ?? 0) + 1, m), {})
console.log(`${alle.length} Befunde — Klasse 3: ${jeKlasse[3] ?? 0}, Klasse 2: ${jeKlasse[2] ?? 0}, `
          + `Klasse 1: ${jeKlasse[1] ?? 0}`)
console.log(`Marken — ${Object.entries(jeMarke).map(([k, v]) => `${k}: ${v}`).join(', ') || 'keine'}`)
console.log(`${messungen.length} Messungen`)
console.log('werkstatt/befunde/befunde.json geschrieben')

const stumpf = stand.filter(s => s.selbstprobe === 'STUMPF' || s.selbstprobe === 'ohne')
if (stumpf.length) {
  console.log(`\nWARNUNG: ${stumpf.length} Werkzeug(e) ohne belegte Schärfe: `
            + stumpf.map(s => s.werkzeug).join(', '))
  process.exit(2)
}
