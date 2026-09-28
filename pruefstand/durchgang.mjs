#!/usr/bin/env node
/**
 * Der Plausibilitätsdurchgang über Rohdaten-JSON (Runde AA).
 *
 *   node pruefstand/durchgang.mjs                     # docs/betrieb/rohdaten → Markdown auf stdout
 *   node pruefstand/durchgang.mjs pruefstand/daten     # die Demo-Fixtures
 *   node pruefstand/durchgang.mjs <ordner> --schreiben # nach docs/betrieb/DURCHGANG.md
 *
 * Die Regeln stehen in durchgang_pruefungen.mjs; das hier lädt und schreibt nur.
 */
import { readFileSync, existsSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ROHTABELLEN, durchgang, alsMarkdown } from './durchgang_pruefungen.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))
const args = process.argv.slice(2).filter(a => !a.startsWith('--'))
const ordner = args[0] ?? join(HIER, '..', 'docs', 'betrieb', 'rohdaten')
const schreiben = process.argv.includes('--schreiben')
const heute = process.env.DURCHGANG_HEUTE ?? new Date().toISOString().slice(0, 10)

const d = {}
for (const n of Object.keys(ROHTABELLEN)) {
  const f = join(ordner, `${n}.json`)
  if (existsSync(f)) d[n] = JSON.parse(readFileSync(f, 'utf8'))
}
if (!Object.keys(d).length) {
  console.error(`Keine Rohdaten in ${ordner} — zuerst den Betriebsabzug laufen lassen (oder pruefstand/daten_dumpen.sh für die Demo).`)
  process.exit(2)
}
const erg = durchgang(d, heute)
const md = alsMarkdown(erg, heute, ordner.replace(join(HIER, '..') + '/', ''))
if (schreiben) {
  const ziel = join(HIER, '..', 'docs', 'betrieb', 'DURCHGANG.md')
  writeFileSync(ziel, md)
  console.log(`Durchgang: ${erg.befunde.length} Kandidaten → docs/betrieb/DURCHGANG.md`)
} else {
  process.stdout.write(md)
}
