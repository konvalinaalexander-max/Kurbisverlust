/**
 * Die fünf PDFs aus den fünf HTML-Dateien bauen.
 *
 * Bisher stand dieser Schritt nirgends: Wer die Dokumente änderte, musste
 * wissen, wie sie ins PDF kommen — und wer es nicht wusste, liess die PDFs
 * veralten. Jetzt ist es ein Befehl:
 *
 *   node docs/pdf_bauen.mjs            # alle fünf
 *   node docs/pdf_bauen.mjs programm   # nur die, deren Dateiname passt
 *
 * Die Schrift wird als Base64 in das Stylesheet gesetzt, damit das PDF ohne
 * Netz und ohne installierte Schrift überall gleich aussieht. Chromium druckt
 * die Datei mit dem @page-Format aus dokument.css (A4, eigene Ränder).
 */
import { chromium } from 'playwright'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { CHROMIUM } from '../pruefstand/attrappe.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))
const NUR = process.argv[2] ?? ''

// Welches HTML wird zu welchem PDF. Die Namen sind die, auf die README und
// docs/*.md verweisen — sie dürfen sich nicht ändern.
const DOKUMENTE = [
  { html: 'programm.html',    pdf: 'Das-Programm-erklaert.pdf' },
  { html: 'ablauf.html',      pdf: 'Ablauf-Betrieb-und-App.pdf' },
  { html: 'architektur.html', pdf: 'Datenarchitektur.pdf' },
  { html: 'fragen.html',      pdf: 'Offene-Fragen.pdf' },
  { html: 'erklaerung.html',  pdf: 'Kuerbis-Verlust-Tracking.pdf' },
]

const schrift = readFileSync(
  join(HIER, '..', 'node_modules', '@fontsource-variable', 'inter', 'files', 'inter-latin-wght-normal.woff2'),
).toString('base64')
const stil = readFileSync(join(HIER, 'dokument.css'), 'utf8').replace('INTER_BASE64', schrift)

const browser = await chromium.launch({ executablePath: CHROMIUM })
let fehler = 0
for (const d of DOKUMENTE) {
  if (NUR && !d.html.includes(NUR) && !d.pdf.includes(NUR)) continue
  const html = readFileSync(join(HIER, d.html), 'utf8').replace('<!--STIL-->', `<style>${stil}</style>`)
  const tmp = join(HIER, `.bau-${d.html}`)
  writeFileSync(tmp, html)
  const blatt = await browser.newPage({ viewport: { width: 794, height: 1123 } })
  const konsole = []
  blatt.on('pageerror', f => konsole.push(String(f)))
  await blatt.goto(`file://${tmp}`, { waitUntil: 'networkidle' })
  await blatt.emulateMedia({ media: 'print' })
  // Ein waagerechter Überlauf heisst im PDF: abgeschnittene Tabelle.
  const ueberlauf = await blatt.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  await blatt.pdf({ path: join(HIER, d.pdf), format: 'A4', printBackground: true, preferCSSPageSize: true })
  const seiten = Math.max(1, Math.round(await blatt.evaluate(() => document.documentElement.scrollHeight) / 1123))
  await blatt.close()
  unlinkSync(tmp)
  const schlecht = ueberlauf > 1 || konsole.length > 0
  if (schlecht) fehler++
  console.log(`  ${schlecht ? '✗' : '✓'} ${d.pdf} — rund ${seiten} Seiten`
    + (ueberlauf > 1 ? `, ${ueberlauf} px Überlauf` : '')
    + (konsole.length ? `, ${konsole.length} Fehler: ${konsole[0]}` : ''))
}
await browser.close()
process.exit(fehler ? 1 : 0)
