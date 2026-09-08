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

test('keine Arbeiter-Maske schreibt mehr einen Käufer oder eine Ausschuss-Messung', () => {
  // Die Masken des Arbeiters: src/arbeit und die Arbeiter-Seiten. Der
  // Betriebsleiter darf alte Fassungen je Käufer weiter pflegen und lesen.
  const masken = alle.filter(d => /\/src\/arbeit\//.test(d.p) || /\/src\/pages\/(Start|NeueArbeit|Arbeit|Kontrolle)\.tsx$/.test(d.p))
  const schreibt: string[] = []
  for (const d of masken) {
    if (/from\('ausschuss_messung'\)\s*\.\s*(insert|upsert)/s.test(d.text)) schreibt.push(d.p.replace(SRC, 'src'))
    for (const m of d.text.matchAll(/\bkaeufer:\s*(\S+)/g)) {
      const wert = m[1].replace(/[,;)]+$/, '')
      if (wert !== 'null' && wert !== 'string') schreibt.push(`${d.p.replace(SRC, 'src')} (${m[0]})`)
    }
  }
  assert.deepEqual(schreibt, [])
})
