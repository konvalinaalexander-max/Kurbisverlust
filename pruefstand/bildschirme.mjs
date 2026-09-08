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
// 0057: die Attrappe nennt denselben Stand, den die App erwartet
const SCHEMA_STAND = Number(readFileSync(join(HIER, '..', 'src', 'lib', 'version.ts'), 'utf8').match(/SCHEMA_ERWARTET = (\d+)/)[1])
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

import { filtern, seite } from './postgrest.mjs'

// Was ein Klickweg schreibt, liest die App gleich darauf wieder — der
// Abschluss-Assistent lässt erst weiter, wenn die Messung da ist. Ohne
// Gedächtnis bliebe er auf dem Schritt stehen. Je Bildschirm frisch (unten).
let geschrieben = {}
let naechsteId = 90001

async function restAntwort(route) {
  const url = new URL(route.request().url())
  const name = url.pathname.replace(/^.*\/rest\/v1\//, '')
  const methode = route.request().method()

  if (name.startsWith('rpc/')) {
    const fn = name.slice(4)
    if (fn === 'auswertung_aktualisieren') {
      return route.fulfill({ json: new Date().toISOString() })
    }
    if (fn === 'auswertung_schritt') {
      const body = JSON.parse(route.request().postData() ?? '{}')
      const i = Number(body.p_schritt ?? 1)
      return route.fulfill({ json: { schritt: i, schritte: 5, titel: ['Rohdaten', 'Arbeiten', 'Kaskade', 'Ergebnis', 'Befunde'][i - 1], dauer_ms: 1, fertig: i === 5 } })
    }
    if (fn === 'schema_stand') return route.fulfill({ json: SCHEMA_STAND })
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

  // Schreiben: gemerkt, damit die App das Geschriebene wiederfindet.
  if (methode !== 'GET' && methode !== 'HEAD') {
    const body = route.request().postData()
    let echo = []
    try { echo = JSON.parse(body ?? 'null') } catch { /* leer lassen */ }
    if (echo === null) echo = []
    if (!Array.isArray(echo)) echo = [echo]
    echo = echo.map(z => ({ id: naechsteId++, ts: new Date().toISOString(), ...z }))
    if (methode === 'POST') geschrieben[name] = [...(geschrieben[name] ?? []), ...echo]
    const einzeln = (route.request().headers()['accept'] ?? '').includes('pgrst.object')
    return route.fulfill({ status: 201, json: einzeln ? (echo[0] ?? {}) : echo })
  }

  const fest = fixture(name)
  const dazu = geschrieben[name] ?? []
  if (fest === null && dazu.length === 0) {
    console.warn(`  ! kein Fixture für ${name} — leere Antwort`)
    return route.fulfill({ json: [] })
  }
  const erg = seite(filtern([...(fest ?? []), ...dazu], url.searchParams), route.request().headers())

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
  // Der Assistent des Vorarbeiters, Schritt für Schritt (0060: kein Käufer, Kistensystem)
  { name: 'neu-was', wer: 'arbeiter', pfad: '/neu' },
  { name: 'neu-charge', wer: 'arbeiter', pfad: '/neu',
    tun: async p => { await p.locator('#taet-waschen_sortieren').click(); await p.locator('#charge').fill('1613') } },
  { name: 'neu-system', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await p.locator('#taet-waschen_sortieren').click(); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
    } },
  { name: 'neu-soll', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await p.locator('#taet-waschen_sortieren').click(); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click(); await p.locator('#system-kiste_ab').click()
    } },
  { name: 'neu-stueck', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await p.locator('#taet-waschen_sortieren').click(); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click(); await p.locator('#system-stueck').click()
    } },
  { name: 'neu-baender', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await p.locator('#taet-sortieren').click(); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
      await p.locator('#baender-anpassen').click()
    } },
  { name: 'neu-fax', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await p.locator('#taet-fax').click(); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
    } },
  // Waschen (0054): die Bänder der Sorte wählen — oder ein eigenes Kaliber tippen
  { name: 'neu-kaliber', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await p.locator('#taet-waschen').click(); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
      await p.locator('#kaliber-0').waitFor()
    } },
  { name: 'neu-kaliber-eigen', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await p.locator('#taet-waschen').click(); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
      await p.locator('#kaliber-eigen').click()
      await p.locator('#kaliber-von').fill('700'); await p.locator('#kaliber-bis').fill('900')
    } },
  { name: 'neu-pruefen', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await p.locator('#taet-waschen_sortieren').click(); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
      await p.locator('#system-kiste_ab').click(); await p.getByRole('button', { name: T('weiter') }).click()
    } },
  // Die Arbeit: der Zähler sieht den Zähler, der Vorarbeiter die Checkliste
  { name: 'arbeit-zaehler', wer: 'arbeiter', pfad: '/arbeit/OFFEN' },
  { name: 'arbeit-wiegen', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.locator('#zettel').fill('2026-09-01'); await p.locator('#zettel-brutto').fill('950'); await p.locator('#zum-wiegen').click() } },
  { name: 'arbeit-kisten', wer: 'arbeiter', pfad: '/arbeit/OFFENKISTEN' },
  // Waschen (0061): Paletten aus dem Zwischenlager — Sortierdatum und Kisten je Palette
  { name: 'arbeit-wasch-paletten', wer: 'arbeiter', pfad: '/arbeit/OFFENWASCHEN' },
  { name: 'arbeit-liste', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click() } },
  { name: 'arbeit-palox', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-palox').click() } },
  { name: 'arbeit-ausgang', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-ausgang').click() } },
  // Zu klein / zu gross je Palette, am Ende der Waschstrasse mit Sortieren (0061)
  { name: 'arbeit-ausschuss', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-ausschuss').click() } },
  { name: 'arbeit-abschluss', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-abschluss').click() } },
  { name: 'arbeit-abschluss-pruefen', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => {
      await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-abschluss').click()
      await p.locator('#palox').fill('165'); await p.locator('#palox-eintragen').click()
      // Danach je Station (0061): die Wiege-Erinnerung, zu klein / zu gross,
      // die fertigen Paletten — und zuletzt die Chargenfrage. Jeder Schritt
      // wird genommen, wie er kommt; keiner ist auf jeder Station da.
      for (let i = 0; i < 5; i++) {
        await p.locator('#aus-nichts, #charge-ja, .haupt-unten button').first().waitFor()
        if (await p.locator('#charge-ja').count()) break
        if (await p.locator('#aus-nichts').count()) { await p.locator('#aus-nichts').click(); await p.waitForTimeout(300) }
        await p.locator('.haupt-unten button:not([disabled])').first().click()
        await p.waitForTimeout(300)
      }
      await p.locator('#charge-ja').click(); await p.getByRole('button', { name: T('weiter') }).click()
    } },
  // Fax (0051, 0060): Paletten als Gesamtzahl, Faules wiegen
  { name: 'arbeit-fax-liste', wer: 'arbeiter', pfad: '/arbeit/OFFENFAX',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click() } },
  { name: 'arbeit-fax-paletten', wer: 'arbeiter', pfad: '/arbeit/OFFENFAX' },
  { name: 'arbeit-fax-faule', wer: 'arbeiter', pfad: '/arbeit/OFFENFAX',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-faule').click() } },
  { name: 'kontrolle', wer: 'arbeiter', pfad: '/kontrolle' },
  // Die Korrektur (Runde H): der Betriebsleiter berichtigt die Messungen einer Arbeit
  { name: 'arbeit-korrektur', wer: 'admin', pfad: '/arbeit/FERTIG?korrigieren=1' },
  // Betriebsleiter: fünf Reiter
  { name: 'ueberblick', wer: 'admin', pfad: '/dashboard' },
  { name: 'ueberblick-sorte', wer: 'admin', pfad: '/dashboard',
    tun: async p => { await p.getByRole('tab', { name: 'je Sorte' }).first().click() } },
  { name: 'ursachen', wer: 'admin', pfad: '/ursachen' },
  { name: 'chargen', wer: 'admin', pfad: '/chargen' },
  { name: 'chargen-offen', wer: 'admin', pfad: '/chargen',
    tun: async p => { await p.locator('tbody tr').first().click() } },
  { name: 'messungen', wer: 'admin', pfad: '/messungen' },
  { name: 'betrieb-arbeiten', wer: 'admin', pfad: '/betrieb/arbeiten' },
  { name: 'betrieb-lieferungen', wer: 'admin', pfad: '/betrieb/lieferungen' },
  // Warenausgang einlesen (0055): die Probedatei wählen, Befund und Abgleich lesen
  { name: 'betrieb-import', wer: 'admin', pfad: '/betrieb/lieferungen',
    tun: async p => {
      await p.locator('#ausgang-dateien input[type=file]').setInputFiles('test/daten/warenausgang-probe.xlsx')
      await p.getByText('Bis wo hat es die Daten schon?').waitFor()
    } },
  { name: 'betrieb-csv', wer: 'admin', pfad: '/betrieb/csv' },
  { name: 'betrieb-warteschlange', wer: 'admin', pfad: '/betrieb/warteschlange' },
  { name: 'betrieb-stammdaten', wer: 'admin', pfad: '/betrieb/stammdaten' },
  // Die Demo-Karte im geladenen Zustand: neu laden und entfernen (0052).
  { name: 'betrieb-demo', wer: 'admin', pfad: '/betrieb/stammdaten',
    tun: async p => { await p.getByRole('link', { name: 'Demo-Daten' }).click() } },
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

// Die offene Arbeit hat die höchste Auftrags-ID im Fixture — ohne Fax, denn
// dort gibt es weder Palox noch Ausschuss (0051), die Klickwege würden fehlen.
const auftraege = fixture('auftrag') ?? []
const offene = auftraege.filter(a => a.status === 'offen' && !a.abgebrochen_ts)
// Die Waschstrasse mit Sortieren (waschen_sortieren) hat alle Masken: Zettel mit
// Gewicht, Wiegen, Palox, fertige Palette — Waschen aus Kisten hat keine
// Paletten, Fax keinen Palox.
const ohneFax = offene.filter(a => !a.ist_fax)
const hand = ohneFax.filter(a => a.station === 'waschen_sortieren')
const OFFEN_ID = hand.length ? Math.max(...hand.map(a => a.id))
  : ohneFax.length ? Math.max(...ohneFax.map(a => a.id)) : offene.length ? Math.max(...offene.map(a => a.id)) : 1
// Die Kisten-Maske gibt es seit 0061 nur noch beim Sortieren: dort werden die
// gefüllten Kaliber-Kisten gezählt. Beim Waschen sind es Paletten mit
// Sortierdatum und Kistenzahl, an der Waschstrasse geht die Ware direkt raus.
const mitKisten = offene.filter(a => a.station === 'sortieren' && !a.ist_fax)
const OFFEN_KISTEN_ID = mitKisten.length ? Math.max(...mitKisten.map(a => a.id)) : OFFEN_ID
// Waschen aus dem Zwischenlager: der Palettenzähler mit Sortierdatum (0061)
const waschen = offene.filter(a => a.station === 'waschen' && !a.ist_fax)
const OFFEN_WASCHEN_ID = waschen.length ? Math.max(...waschen.map(a => a.id)) : OFFEN_ID
// Eine fertige Arbeit für die Korrektur-Ansicht des Betriebsleiters (Runde H)
const fertige = auftraege.filter(a => a.status === 'abgeschlossen' && !a.abgebrochen_ts && !a.ist_fax)
const FERTIG_ID = fertige.length ? Math.max(...fertige.map(a => a.id)) : OFFEN_ID
const faxOffen = offene.filter(a => a.ist_fax)
const OFFEN_FAX_ID = faxOffen.length ? Math.max(...faxOffen.map(a => a.id)) : OFFEN_ID

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
      geschrieben = {}          // jeder Bildschirm beginnt bei den Fixtures
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
                              .replace('OFFENWASCHEN', String(OFFEN_WASCHEN_ID))
                              .replace('OFFENFAX', String(OFFEN_FAX_ID))
                              .replace('FERTIG', String(FERTIG_ID))
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
