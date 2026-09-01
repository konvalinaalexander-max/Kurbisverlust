/**
 * Baut ein Dokument aus docs/<name>.html zu docs/<Ausgabename>.pdf.
 *
 *   node docs/dokument_bauen.mjs erklaerung Kuerbis-Verlust-Tracking
 *   node docs/dokument_bauen.mjs ablauf     Ablauf-Betrieb-und-App
 *   node docs/dokument_bauen.mjs fragen     Offene-Fragen
 *
 * Warum ein Browser und kein PDF-Werkzeug: Die Dokumente sind als HTML mit
 * Druck-Layout geschrieben — Seitenumbrüche, Tabellen, Bilder als SVG.
 * Chromium setzt das mit Silbentrennung und Blocksatz, was eine
 * Zeichen-für-Zeichen-Bibliothek nicht kann.
 *
 * Stil und Schrift werden beim Bauen eingesetzt: der Stil aus dokument.css
 * (ein Ort für alle Dokumente), die Schrift aus node_modules — damit die PDF
 * überall gleich aussieht, auch wo Inter nicht installiert ist.
 */
import { chromium } from 'playwright'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const HIER = dirname(fileURLToPath(import.meta.url))
const [name, ausgabe] = process.argv.slice(2)
if (!name || !ausgabe) {
  console.error('Aufruf: node docs/dokument_bauen.mjs <quelle-ohne-endung> <Ausgabename>')
  process.exit(1)
}

const schrift = readFileSync(join(HIER, '..', 'node_modules', '@fontsource-variable', 'inter',
                                  'files', 'inter-latin-wght-normal.woff2')).toString('base64')
const stil = readFileSync(join(HIER, 'dokument.css'), 'utf8').replace('INTER_BASE64', schrift)
const html = readFileSync(join(HIER, `${name}.html`), 'utf8')
  .replace('<!--STIL-->', `<style>${stil}</style>`)

const tmp = join(HIER, `.${name}-gebaut.html`)
writeFileSync(tmp, html)

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM ?? '/opt/pw-browsers/chromium',
})
const seite = await browser.newPage()
await seite.goto(`file://${tmp}`, { waitUntil: 'networkidle' })
await seite.emulateMedia({ media: 'print' })
await seite.pdf({
  path: join(HIER, `${ausgabe}.pdf`),
  format: 'A4', printBackground: true,
  margin: { top: '16mm', bottom: '17mm', left: '15mm', right: '15mm' },
  displayHeaderFooter: true,
  headerTemplate: '<div></div>',
  footerTemplate: `<div style="width:100%;font-family:sans-serif;font-size:7.5pt;color:#888;
    padding:0 15mm;display:flex;justify-content:space-between">
    <span>${ausgabe.replace(/-/g, ' ')} — Kürbis-Verlust-Tracking</span>
    <span class="pageNumber"></span></div>`,
})
await browser.close()
unlinkSync(tmp)
console.log(`docs/${ausgabe}.pdf gebaut`)
process.exit(0)
