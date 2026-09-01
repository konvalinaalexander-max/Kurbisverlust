/**
 * Baut docs/Kuerbis-Verlust-Tracking.pdf aus docs/erklaerung.html.
 *
 *   node docs/erklaerung_bauen.mjs
 *
 * Warum ein Browser und kein PDF-Werkzeug: Das Dokument ist als HTML mit
 * Druck-Layout geschrieben — Seitenumbrüche, Tabellen, das Prozessbild als SVG.
 * Chromium setzt das mit richtiger Silbentrennung und Blocksatz, was eine
 * Zeichen-für-Zeichen-Bibliothek nicht kann.
 *
 * Die Schrift (Inter) wird beim Bauen aus node_modules eingebettet, damit die
 * PDF überall gleich aussieht — auch dort, wo Inter nicht installiert ist.
 */
import { chromium } from 'playwright'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const HIER = dirname(fileURLToPath(import.meta.url))
const SCHRIFT = join(HIER, '..', 'node_modules', '@fontsource-variable', 'inter',
                     'files', 'inter-latin-wght-normal.woff2')

const html = readFileSync(join(HIER, 'erklaerung.html'), 'utf8')
  .replace('INTER_BASE64', readFileSync(SCHRIFT).toString('base64'))
const tmp = join(HIER, '.erklaerung-gebaut.html')
writeFileSync(tmp, html)

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM ?? '/opt/pw-browsers/chromium',
})
const seite = await browser.newPage()
await seite.goto(`file://${tmp}`, { waitUntil: 'networkidle' })
await seite.emulateMedia({ media: 'print' })
await seite.pdf({
  path: join(HIER, 'Kuerbis-Verlust-Tracking.pdf'),
  format: 'A4', printBackground: true,
  margin: { top: '16mm', bottom: '17mm', left: '15mm', right: '15mm' },
  displayHeaderFooter: true,
  headerTemplate: '<div></div>',
  footerTemplate: `<div style="width:100%;font-family:sans-serif;font-size:7.5pt;color:#888;
    padding:0 15mm;display:flex;justify-content:space-between">
    <span>Kürbis-Verlust-Tracking — Prozess, Datenerhebung, Mathematik</span>
    <span class="pageNumber"></span></div>`,
})
await browser.close()
unlinkSync(tmp)
console.log('docs/Kuerbis-Verlust-Tracking.pdf gebaut')
process.exit(0)
