#!/usr/bin/env node
/**
 * Die Schwarzprobe: Was passiert, wenn die Zugangsdaten falsch sind?
 *
 * Gemeldet aus dem Betrieb, beim ersten Versuch mit dem Demo-Knopf: „wenn ich
 * auf demo klicke - ist der screen einfach schwarz und ich komm da auch nicht
 * mehr raus". Ursache war nicht die Demo, sondern eine Zeile, die es seit dem
 * ersten Tag gibt: createClient() wird beim Laden des Moduls aufgerufen und
 * wirft bei einer Adresse ohne `https://`. Eine Ausnahme dort bringt das ganze
 * Bündel zu Fall — React zeichnet nie, übrig bleibt die leere Seite.
 *
 * Diese Probe fährt genau das nach, mit der gebauten App und einem echten
 * Browser. Sie stellt drei Fragen, und alle drei müssen stimmen:
 *
 *   1. Steht überhaupt etwas auf der Seite?     (nicht schwarz)
 *   2. Sagt sie, was falsch ist?                (die Meldung, nicht ein Absturz)
 *   3. Kommt man wieder heraus?                 (Knopf „Demo verlassen")
 *
 * Aufruf (baut selbst, mit absichtlich kaputten Demo-Werten):
 *   node pruefstand/schwarzprobe.mjs
 */
import { chromium } from 'playwright'
import { execFileSync } from 'node:child_process'
import { createServer } from 'node:http'
import { readFileSync, existsSync } from 'node:fs'
import { join, extname, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const WURZEL = join(dirname(fileURLToPath(import.meta.url)), '..')
const DIST = join(WURZEL, 'dist')
const HAFEN = 5288
const TYP = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
              '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.json': 'application/json' }

/* Tippfehler, die ein Mensch beim Abschreiben wirklich macht. `erwartet` sagt,
   was richtig wäre — und das ist nicht überall dasselbe:

     'meldung' — beide Werte sind da, aber einer taugt nicht. Die App muss in
                 den Demo-Modus gehen, erklären, was falsch ist, und einen
                 Ausgang anbieten.
     'normal'  — es fehlt ein Wert ganz. Dann gibt es gar keine Demo (der
                 Knopf erscheint nie), und die App gehört in den Echtbetrieb,
                 ohne jeden Hinweis auf eine Demo. */
const FAELLE = [
  { name: 'Adresse ohne https://', erwartet: 'meldung',
    url: 'qmhxkfyowwvsumcwssxe.supabase.co', key: 'eyJprobe' },
  { name: 'Adresse und Schlüssel vertauscht', erwartet: 'meldung',
    url: 'eyJprobe', key: 'https://qmhxkfyowwvsumcwssxe.supabase.co' },
  { name: 'die Dashboard-Adresse statt der Datenbank', erwartet: 'meldung',
    url: 'https://supabase.com/dashboard/project/qmhxkfyowwvsumcwssxe', key: 'eyJprobe' },
  { name: 'Schlüssel leer — gar keine Demo, also Echtbetrieb', erwartet: 'normal',
    url: 'https://qmhxkfyowwvsumcwssxe.supabase.co', key: '' },
]

let fehlgeschlagen = 0
console.log('\n── Schwarzprobe: falsche Zugangsdaten dürfen die App nicht töten ──\n')

for (const fall of FAELLE) {
  execFileSync('npx', ['vite', 'build'], {
    cwd: WURZEL, stdio: 'ignore',
    env: { ...process.env,
           VITE_SUPABASE_URL: 'http://localhost:5199', VITE_SUPABASE_ANON_KEY: 'eyJprobe',
           VITE_DEMO_SUPABASE_URL: fall.url, VITE_DEMO_SUPABASE_ANON_KEY: fall.key },
  })

  const server = createServer((req, res) => {
    const pfad = decodeURIComponent(req.url.split('?')[0])
    let datei = join(DIST, pfad)
    if (!existsSync(datei) || pfad === '/') datei = join(DIST, 'index.html')
    res.writeHead(200, { 'content-type': TYP[extname(datei)] ?? 'application/octet-stream' })
    res.end(readFileSync(datei))
  })
  await new Promise(r => server.listen(HAFEN, r))

  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' })
  const seite = await browser.newPage()
  await seite.goto(`http://localhost:${HAFEN}/`)
  await seite.evaluate(() => localStorage.setItem('demo_modus', '1'))
  await seite.reload({ waitUntil: 'networkidle' })
  await seite.waitForTimeout(800)

  const text = (await seite.locator('body').innerText()).trim()
  const ausgang = await seite.getByRole('button', { name: /Demo verlassen/ }).count() > 0

  // Und der zweite Weg hinaus: ?demo=aus muss den Merkzettel löschen, auch
  // wenn die Seite gar nichts zeichnen könnte.
  await seite.goto(`http://localhost:${HAFEN}/?demo=aus`)
  const merkzettel = await seite.evaluate(() => localStorage.getItem('demo_modus'))

  await browser.close()
  await new Promise(r => server.close(r))

  // Gemeinsam für alle Fälle: nie schwarz, und der Notausgang wirkt immer.
  const maengel = []
  if (!text.length) maengel.push('die Seite bleibt leer — schwarzer Bildschirm')
  if (merkzettel !== null) maengel.push('?demo=aus löscht den Merkzettel nicht')

  if (fall.erwartet === 'meldung') {
    if (text.length && !/stimmen nicht|Zugangsdaten|nicht richtig/i.test(text)) {
      maengel.push(`keine erklärende Meldung: „${text.slice(0, 80)}…"`)
    }
    if (!ausgang) maengel.push('kein Knopf „Demo verlassen" — der Besucher sitzt fest')
  } else {
    if (/Demo/i.test(text)) maengel.push('spricht von einer Demo, die es ohne zweiten Wert nicht gibt')
  }

  if (maengel.length) {
    fehlgeschlagen++
    console.log(`  ✗ ${fall.name}`)
    for (const m of maengel) console.log(`      ${m}`)
  } else {
    console.log(`  ok  ${fall.name}`)
  }
}

console.log()
if (fehlgeschlagen) {
  console.log(`  ${fehlgeschlagen} von ${FAELLE.length} Fällen enden im Nichts.`)
  console.log('  Eine App, die bei einem Tippfehler schwarz bleibt, lässt den')
  console.log('  Menschen ohne Weg zurück — das ist schlimmer als ein Fehler.\n')
  process.exit(1)
}
console.log(`  OK  ${FAELLE.length} falsche Zugangsdaten, viermal eine Meldung und ein Ausgang.\n`)
