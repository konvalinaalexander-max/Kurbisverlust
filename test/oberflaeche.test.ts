// AB-30: Die Wörter des Modells bleiben im Modell. „Buch A" und „Buch B" sind
// Buchhaltung; der Betriebsleiter liest „echter Verlust" und „kein echter
// Verlust". Und der Käufer wird seit 0060 nicht mehr gefragt — es gibt keine
// Maske mehr, die ihn schreibt.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

function dateien(pfad: string): string[] {
  return readdirSync(pfad).flatMap(n => {
    const p = join(pfad, n)
    return statSync(p).isDirectory() ? dateien(p) : /\.(tsx?|css)$/.test(n) ? [p] : []
  })
}
const SRC = join(process.cwd(), 'src')
const alle = dateien(SRC).map(p => ({ p, text: readFileSync(p, 'utf8') }))

test('„Buch A" und „Buch B" stehen in keiner Oberfläche und keinem Text', () => {
  const treffer = alle.filter(d => /Buch [AB]\b/.test(d.text)).map(d => d.p.replace(SRC, 'src'))
  assert.deepEqual(treffer, [])
})

test('keine Arbeiter-Maske schreibt mehr einen Käufer; Ausschuss nur gewogen je Palette (0061)', () => {
  // Die Masken des Arbeiters: src/arbeit und die Arbeiter-Seiten. Der
  // Betriebsleiter darf alte Fassungen je Käufer weiter pflegen und lesen.
  // Zu klein / zu gross schreibt genau eine Maske — die am Ende des Waschens
  // + Sortierens, Palette für Palette mit Brutto (oder „nichts", 0 kg); eine
  // geschätzte Kilozahl gibt es nirgends mehr.
  const masken = alle.filter(d => /\/src\/arbeit\//.test(d.p) || /\/src\/pages\/(Start|NeueArbeit|Arbeit|Kontrolle)\.tsx$/.test(d.p))
  const schreibt: string[] = []
  for (const d of masken) {
    if (/from\('ausschuss_messung'\)\s*\.\s*(insert|upsert)/s.test(d.text) && !/\/src\/arbeit\/AusschussMaske\.tsx$/.test(d.p)) schreibt.push(d.p.replace(SRC, 'src'))
    for (const m of d.text.matchAll(/\bkaeufer:\s*(\S+)/g)) {
      const wert = m[1].replace(/[,;)]+$/, '')
      if (wert !== 'null' && wert !== 'string') schreibt.push(`${d.p.replace(SRC, 'src')} (${m[0]})`)
    }
  }
  assert.deepEqual(schreibt, [])
  const maske = alle.find(d => /\/src\/arbeit\/AusschussMaske\.tsx$/.test(d.p))
  assert.ok(maske, 'AusschussMaske.tsx fehlt')
  const inserts = [...maske.text.matchAll(/from\('ausschuss_messung'\)\.insert\(([^]*?)\)\s*$/gm)].map(m => m[1])
  assert.ok(inserts.length >= 2, 'Die Maske schreibt gewogen und „nichts"')
  for (const i of inserts) assert.ok(/brutto_kg: b/.test(i) || /kg: 0/.test(i), `Ausschuss ohne Brutto und nicht 0: ${i}`)
})
