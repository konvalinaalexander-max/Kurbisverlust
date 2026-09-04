/**
 * Der Bildschirm-Prüfstand: rendert jede Seite der App in einem echten Browser
 * und legt Screenshots ab — mobil und Desktop, hell und dunkel.
 *
 * Es gibt kein laufendes Supabase dabei. Stattdessen fängt Playwright jede
 * Netzwerk-Anfrage an /rest/v1 und /auth/v1 ab und antwortet aus den
 * JSON-Dateien in pruefstand/daten/, die daten_dumpen.sh aus der lokalen
 * Demo-Datenbank gezogen hat. Die App sieht also echte Datenformen und echte
 * Zahlen — nur eben ohne Netz.
 *
 * Warum der Aufwand: "npm run build läuft durch" sagt nichts darüber, ob eine
 * Tabelle aus dem Rahmen läuft oder eine Zahl als NaN dasteht. Das sieht man
 * nur auf dem gerenderten Bildschirm.
 *
 *   node pruefstand/bildschirme.mjs            # alle Seiten
 *   node pruefstand/bildschirme.mjs dashboard  # nur Namen mit "dashboard"
 */
import { chromium } from 'playwright'
import { createServer } from 'vite'
import { readFileSync, mkdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const HIER = dirname(fileURLToPath(import.meta.url))
const DATEN = join(HIER, 'daten')
const BILDER = join(HIER, 'bilder')
const NUR = process.argv[2] ?? ''
// Sprache der Arbeiter-Oberfläche. Ungarisch und Portugiesisch haben die
// längsten Wörter — was dort in den Rahmen passt, passt überall.
//   SPRACHE=hu node pruefstand/bildschirme.mjs auftrag
const SPRACHE = process.env.SPRACHE ?? 'de'
// Die Klickwege der Arbeiter-Masken nennen Reiter und Knöpfe über ihren
// Text-Schlüssel, nicht über das deutsche Wort — sonst liefe der Prüfstand in
// jeder anderen Sprache ins Leere. Das Wörterbuch kommt aus der App selbst,
// über den Vite-Server, sobald er steht (unten).
let T = id => id

const fixture = name => {
  try { return JSON.parse(readFileSync(join(DATEN, `${name}.json`), 'utf8')) }
  catch { return null }
}

import { filtern } from './postgrest.mjs'

async function restAntwort(route) {
  const url = new URL(route.request().url())
  const name = url.pathname.replace(/^.*\/rest\/v1\//, '')
  const methode = route.request().method()

  if (name.startsWith('rpc/')) {
    const fn = name.slice(4)
    if (fn === 'auswertung_aktualisieren') {
      return route.fulfill({ json: new Date().toISOString() })
    }
    if (fn === 'palox_letzter_stand') {
      const body = JSON.parse(route.request().postData() ?? '{}')
      const staende = fixture('rpc_palox_letzter_stand') ?? {}
      return route.fulfill({ json: staende[body.p_station] ?? null })
    }
    if (fn === 'demo_daten_laden') return route.fulfill({ json: 'Demo-Saison steht.' })
    if (fn === 'demo_daten_entfernen') return route.fulfill({ json: 'Demo-Daten entfernt.' })
    const daten = fixture(`rpc_${fn}`)
    return route.fulfill({ json: daten ?? null })
  }

  // Schreiben: die App liest danach ohnehin neu — Hauptsache kein Fehler.
  if (methode !== 'GET' && methode !== 'HEAD') {
    const body = route.request().postData()
    let echo = []
    try { echo = JSON.parse(body ?? '[]') } catch { /* leer lassen */ }
    if (!Array.isArray(echo)) echo = [{ id: 90001, ...echo }]
    const einzeln = (route.request().headers()['accept'] ?? '').includes('pgrst.object')
    return route.fulfill({ status: 201, json: einzeln ? (echo[0] ?? {}) : echo })
  }

  const zeilen = fixture(name)
  if (zeilen === null) {
    console.warn(`  ! kein Fixture für ${name} — leere Antwort`)
    return route.fulfill({ json: [] })
  }
  const erg = filtern(zeilen, url.searchParams)

  if (methode === 'HEAD') {
    return route.fulfill({ status: 200, headers: {
      'content-range': `0-${Math.max(erg.length - 1, 0)}/${erg.length}`,
    }, body: '' })
  }
  const einzeln = (route.request().headers()['accept'] ?? '').includes('pgrst.object')
  return route.fulfill({ json: einzeln ? (erg[0] ?? null) : erg })
}

/* ---------- Auth: eine ausgedachte, aber formal gültige Sitzung ---------- */
const jwt = (rolle, id, name) => {
  const teil = o => Buffer.from(JSON.stringify(o)).toString('base64url')
  return `${teil({ alg: 'none' })}.${teil({
    sub: id, role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 86400,
    user_metadata: { name },
  })}.x`
}
const sitzung = (id, name, anonym) => ({
  access_token: jwt('authenticated', id, name),
  token_type: 'bearer', expires_in: 86400,
  expires_at: Math.floor(Date.now() / 1000) + 86400,
  refresh_token: 'pruefstand',
  user: {
    id, aud: 'authenticated', role: 'authenticated',
    email: anonym ? undefined : 'chef@hof.test',
    is_anonymous: anonym, user_metadata: { name },
    app_metadata: {}, created_at: '2026-09-01T08:00:00Z',
  },
})
const ADMIN = '11111111-1111-1111-1111-111111111111'
const ARBEITER = '22222222-2222-2222-2222-222222222222'

async function authAntwort(route, wer) {
  const url = new URL(route.request().url())
  const s = wer === 'arbeiter'
    ? sitzung(ARBEITER, 'Tomasz', true)
    : sitzung(ADMIN, 'Alexander', false)
  if (url.pathname.endsWith('/token') || url.pathname.endsWith('/signup')) {
    return route.fulfill({ json: s })
  }
  if (url.pathname.endsWith('/user')) return route.fulfill({ json: s.user })
  if (url.pathname.endsWith('/logout')) return route.fulfill({ status: 204, body: '' })
  return route.fulfill({ json: {} })
}

/* ---------- Die Bildschirm-Liste ----------------------------------------- */
// Jeder Eintrag: Name, wer angemeldet ist, Pfad, und was vor dem Screenshot
// noch zu tun ist (Klicks, damit Reiter und Dialoge sichtbar werden).
const BILDSCHIRME = [
  { name: 'sprache', wer: null, pfad: '/', frisch: true },
  { name: 'anmelden', wer: null, pfad: '/' },
  { name: 'start', wer: 'arbeiter', pfad: '/' },
  // Der Assistent des Vorarbeiters, Schritt für Schritt
  { name: 'neu-was', wer: 'arbeiter', pfad: '/neu' },
  { name: 'neu-charge', wer: 'arbeiter', pfad: '/neu',
    tun: async p => { await p.locator('#taet-waschen_sortieren').click(); await p.locator('#charge').fill('1613') } },
  { name: 'neu-art', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await p.locator('#taet-waschen_sortieren').click(); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click(); await p.locator('#kaeufer-keiner').click()
    } },
  { name: 'neu-pruefen', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await p.locator('#taet-waschen_sortieren').click(); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click(); await p.locator('#kaeufer-keiner').click()
      await p.locator('#art-kiste').click()
    } },
  // Die Arbeit: der Zähler sieht den Zähler, der Vorarbeiter die Checkliste
  { name: 'arbeit-zaehler', wer: 'arbeiter', pfad: '/arbeit/OFFEN' },
  { name: 'arbeit-wiegen', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.locator('#zettel').fill('2026-09-01'); await p.locator('#zum-wiegen').click() } },
  { name: 'arbeit-kisten', wer: 'arbeiter', pfad: '/arbeit/OFFENKISTEN' },
  { name: 'arbeit-liste', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click() } },
  { name: 'arbeit-palox', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-palox').click() } },
  { name: 'arbeit-ausschuss', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-ausschuss').click() } },
  { name: 'arbeit-abschluss', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-abschluss').click() } },
  { name: 'arbeit-abschluss-pruefen', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => {
      await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-abschluss').click()
      await p.locator('#palox').fill('165'); await p.locator('#palox-eintragen').click()
      await p.locator('#ausschuss-von-ja').click()
      if (await p.locator('#ausschuss-leer-ja').count()) await p.locator('#ausschuss-leer-ja').click()
      await p.getByRole('button', { name: T('weiter') }).click()
      await p.locator('#charge-ja').click(); await p.getByRole('button', { name: T('weiter') }).click()
    } },
  { name: 'kontrolle', wer: 'arbeiter', pfad: '/kontrolle' },
  // Betriebsleiter: fünf Reiter
  { name: 'ueberblick', wer: 'admin', pfad: '/dashboard' },
  { name: 'ursachen', wer: 'admin', pfad: '/ursachen' },
  { name: 'chargen', wer: 'admin', pfad: '/chargen' },
  { name: 'chargen-offen', wer: 'admin', pfad: '/chargen',
    tun: async p => { await p.locator('tbody tr').first().click() } },
  { name: 'messungen', wer: 'admin', pfad: '/messungen' },
  { name: 'betrieb-arbeiten', wer: 'admin', pfad: '/betrieb/arbeiten' },
  { name: 'betrieb-lieferungen', wer: 'admin', pfad: '/betrieb/lieferungen' },
  { name: 'betrieb-csv', wer: 'admin', pfad: '/betrieb/csv' },
  { name: 'betrieb-warteschlange', wer: 'admin', pfad: '/betrieb/warteschlange' },
  { name: 'betrieb-stammdaten', wer: 'admin', pfad: '/betrieb/stammdaten' },
  { name: 'betrieb-schemata', wer: 'admin', pfad: '/betrieb/stammdaten',
    tun: async p => { await p.getByRole('link', { name: 'Sortierschemata' }).click() } },
  { name: 'betrieb-zugang', wer: 'admin', pfad: '/betrieb/zugang' },
]

const GERAETE = [
  { name: 'handy', breite: 390, hoehe: 844 },
  { name: 'desktop', breite: 1440, hoehe: 900 },
]
const THEMEN = ['light', 'dark']

/* ---------- Ablauf -------------------------------------------------------- */
const vite = await createServer({
  root: join(HIER, '..'),
  server: { port: 5199, strictPort: true },
  logLevel: 'silent',
})
await vite.listen()
const { WOERTERBUCH } = await vite.ssrLoadModule('/src/lib/i18n.ts')
T = id => WOERTERBUCH[SPRACHE]?.[id] ?? WOERTERBUCH.de[id]

// Die offene Arbeit hat die höchste Auftrags-ID im Fixture.
const auftraege = fixture('auftrag') ?? []
const offene = auftraege.filter(a => a.status === 'offen' && !a.abgebrochen_ts)
const OFFEN_ID = offene.length ? Math.max(...offene.map(a => a.id)) : 1
// Die Kisten-Maske gibt es nur dort, wo es Kaliber-Kisten gibt — auf der
// Hand-Linie (waschen_sortieren) geht die Ware direkt raus.
const mitKisten = offene.filter(a => a.station !== 'waschen_sortieren')
const OFFEN_KISTEN_ID = mitKisten.length ? Math.max(...mitKisten.map(a => a.id)) : OFFEN_ID

mkdirSync(BILDER, { recursive: true })
// In der Entwicklungsumgebung liegt ein fertiges Chromium unter /opt — dessen
// Version muss nicht zur Playwright-Version passen, für Screenshots genügt es.
const browser = await chromium.launch({
  executablePath: process.env.PRUEFSTAND_CHROMIUM ?? '/opt/pw-browsers/chromium',
})
let fehler = 0

for (const geraet of GERAETE) {
  for (const thema of THEMEN) {
    for (const schirm of BILDSCHIRME) {
      if (NUR && !schirm.name.includes(NUR)) continue
      const kontext = await browser.newContext({
        viewport: { width: geraet.breite, height: geraet.hoehe },
        colorScheme: thema,
        locale: 'de-CH',
      })
      const seite = await kontext.newPage()
      const meldungen = []
      seite.on('console', m => { if (m.type() === 'error') meldungen.push(m.text()) })
      seite.on('pageerror', f => meldungen.push(String(f)))

      await seite.route('**/rest/v1/**', r => restAntwort(r).catch(() => r.abort()))
      await seite.route('**/auth/v1/**', r => authAntwort(r, schirm.wer).catch(() => r.abort()))
      await seite.route('**/storage/v1/**', r => r.fulfill({ json: {} }))

      // Sprache + Anmeldung vorbereiten, bevor die App lädt
      await seite.addInitScript(({ wer, frisch, sprache }) => {
        if (frisch) { localStorage.clear(); return }
        localStorage.setItem('sprache', sprache)
        localStorage.setItem('sprache_tag', new Date().toISOString().slice(0, 10))
        if (wer) localStorage.setItem('pruefstand_wer', wer)
      }, { wer: schirm.wer, frisch: schirm.frisch ?? false, sprache: SPRACHE })

      const pfad = schirm.pfad.replace('OFFENKISTEN', String(OFFEN_KISTEN_ID))
                              .replace('OFFEN', String(OFFEN_ID))
      await seite.goto(`http://localhost:5199${pfad}`, { waitUntil: 'networkidle' })

      // Anmelden, falls die Seite jemanden braucht und der Login-Schirm steht
      if (schirm.wer === 'admin') {
        const login = seite.getByRole('button', { name: 'Betriebsleiter' })
        if (await login.isVisible().catch(() => false)) {
          await login.click()
          await seite.getByLabel('E-Mail').fill('chef@hof.test')
          await seite.getByLabel('Passwort').fill('pruefstand')
          await seite.getByRole('button', { name: 'Anmelden', exact: true }).click()
          await seite.waitForLoadState('networkidle')
          await seite.goto(`http://localhost:5199${pfad}`, { waitUntil: 'networkidle' })
        }
      } else if (schirm.wer === 'arbeiter') {
        const feld = seite.getByLabel(T('deinName'))
        if (await feld.isVisible().catch(() => false)) {
          await feld.fill('Tomasz')
          await seite.getByRole('button', { name: T('losGehts') }).click()
          await seite.waitForLoadState('networkidle')
          await seite.goto(`http://localhost:5199${pfad}`, { waitUntil: 'networkidle' })
        }
      }

      try { await schirm.tun?.(seite) } catch (f) { meldungen.push(`Klickweg: ${f}`) }
      await seite.waitForLoadState('networkidle').catch(() => {})
      await seite.waitForTimeout(250)

      const datei = join(BILDER, `${schirm.name}--${geraet.name}-${thema}${SPRACHE === 'de' ? '' : `-${SPRACHE}`}.png`)
      await seite.screenshot({ path: datei, fullPage: true })

      // Wagerechtes Überlaufen der ganzen Seite ist immer ein Fehler.
      const ueberlauf = await seite.evaluate(() =>
        document.documentElement.scrollWidth - document.documentElement.clientWidth)
      const zeile = [`${schirm.name} (${geraet.name}, ${thema})`]
      if (ueberlauf > 1) { fehler++; zeile.push(`ÜBERLAUF ${ueberlauf}px`) }
      if (meldungen.length) { fehler++; zeile.push(`KONSOLE: ${meldungen[0]}`) }
      if (zeile.length > 1) console.log('  ✗ ' + zeile.join(' — '))
      await kontext.close()
    }
  }
}

await browser.close()
await vite.close()
console.log(`Fertig: Screenshots in ${BILDER}${fehler ? ` — ${fehler} Seiten mit Konsolenfehlern` : ', keine Konsolenfehler'}`)
process.exit(0)
