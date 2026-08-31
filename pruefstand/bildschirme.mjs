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

const fixture = name => {
  try { return JSON.parse(readFileSync(join(DATEN, `${name}.json`), 'utf8')) }
  catch { return null }
}

/* ---------- Mini-PostgREST: eq/in/is/like/not-Filter, order, limit ------- */
function filtern(zeilen, params) {
  let erg = [...zeilen]
  for (const [k, roh] of params.entries()) {
    if (['select', 'order', 'limit', 'offset', 'on_conflict', 'columns'].includes(k)) continue
    for (const v of params.getAll(k)) {
      if (v.startsWith('eq.')) {
        const w = v.slice(3)
        erg = erg.filter(z => String(z[k]) === w)
      } else if (v.startsWith('in.(')) {
        const werte = v.slice(4, -1).split(',').map(s => s.replace(/^"|"$/g, ''))
        erg = erg.filter(z => werte.includes(String(z[k])))
      } else if (v === 'is.null') {
        erg = erg.filter(z => z[k] === null || z[k] === undefined)
      } else if (v === 'not.is.null') {
        erg = erg.filter(z => z[k] !== null && z[k] !== undefined)
      } else if (v.startsWith('like.')) {
        const muster = new RegExp('^' + v.slice(5).replace(/[.+?^${}()|[\]\\]/g, '\\$&')
          .replace(/%/g, '.*').replace(/\*/g, '.*') + '$')
        erg = erg.filter(z => muster.test(String(z[k] ?? '')))
      }
    }
  }
  const order = params.get('order')
  if (order) {
    const [spalte, ...rest] = order.split('.')
    const absteigend = rest.includes('desc')
    erg.sort((a, b) => {
      const x = a[spalte], y = b[spalte]
      if (x === y) return 0
      if (x === null) return 1
      if (y === null) return -1
      return (x < y ? -1 : 1) * (absteigend ? -1 : 1)
    })
  }
  const limit = params.get('limit')
  if (limit) erg = erg.slice(0, Number(limit))
  return erg
}

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
  { name: 'auftraege', wer: 'arbeiter', pfad: '/auftraege' },
  { name: 'auftrag-neu', wer: 'arbeiter', pfad: '/auftraege',
    tun: async p => { await p.getByRole('button', { name: /Neue Arbeit/ }).click() } },
  { name: 'auftrag-detail', wer: 'arbeiter', pfad: '/auftraege/OFFEN' },
  { name: 'auftrag-wiegen', wer: 'arbeiter', pfad: '/auftraege/OFFEN',
    tun: async p => {
      await p.getByRole('button', { name: '+', exact: true }).click()
      await p.getByRole('button', { name: /wiegen/i }).first().click()
    } },
  { name: 'auftrag-faule', wer: 'arbeiter', pfad: '/auftraege/OFFEN',
    tun: async p => { await p.getByRole('link', { name: 'Faule' }).click() } },
  { name: 'auftrag-abschluss', wer: 'arbeiter', pfad: '/auftraege/OFFEN',
    tun: async p => { await p.getByRole('link', { name: 'Fertig', exact: true }).click() } },
  { name: 'kontrolle', wer: 'arbeiter', pfad: '/kontrolle' },
  { name: 'dashboard-1', wer: 'admin', pfad: '/dashboard' },
  { name: 'dashboard-2', wer: 'admin', pfad: '/dashboard',
    tun: async p => { await p.getByRole('tab', { name: 'Aufschlüsselung' }).click() } },
  { name: 'dashboard-3', wer: 'admin', pfad: '/dashboard',
    tun: async p => { await p.getByRole('tab', { name: 'Rohdaten' }).click() } },
  { name: 'csv', wer: 'admin', pfad: '/csv' },
  { name: 'warteschlange', wer: 'admin', pfad: '/warteschlange' },
  { name: 'lieferungen', wer: 'admin', pfad: '/lieferungen' },
  { name: 'stammdaten-gebinde', wer: 'admin', pfad: '/stammdaten' },
  { name: 'stammdaten-import', wer: 'admin', pfad: '/stammdaten',
    tun: async p => { await p.getByRole('link', { name: 'Paletten-Import' }).click() } },
  { name: 'stammdaten-chargen', wer: 'admin', pfad: '/stammdaten',
    tun: async p => { await p.getByRole('link', { name: 'Chargen' }).click() } },
  { name: 'stammdaten-abgebrochen', wer: 'admin', pfad: '/stammdaten',
    tun: async p => { await p.getByRole('link', { name: 'Abgebrochene Arbeiten' }).click() } },
  { name: 'stammdaten-benutzer', wer: 'admin', pfad: '/stammdaten',
    tun: async p => { await p.getByRole('link', { name: 'Benutzer' }).click() } },
  { name: 'stammdaten-demo', wer: 'admin', pfad: '/stammdaten',
    tun: async p => { await p.getByRole('link', { name: 'Demo-Daten' }).click() } },
  { name: 'zugang', wer: 'admin', pfad: '/zugang' },
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

// Die offene Arbeit hat die höchste Auftrags-ID im Fixture.
const auftraege = fixture('auftrag') ?? []
const offene = auftraege.filter(a => a.status === 'offen' && !a.abgebrochen_ts)
const OFFEN_ID = offene.length ? Math.max(...offene.map(a => a.id)) : 1

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
      await seite.addInitScript(({ wer, frisch }) => {
        if (frisch) { localStorage.clear(); return }
        localStorage.setItem('sprache', 'de')
        localStorage.setItem('sprache_tag', new Date().toISOString().slice(0, 10))
        if (wer) localStorage.setItem('pruefstand_wer', wer)
      }, { wer: schirm.wer, frisch: schirm.frisch ?? false })

      const pfad = schirm.pfad.replace('OFFEN', String(OFFEN_ID))
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
        const feld = seite.getByLabel('Dein Name')
        if (await feld.isVisible().catch(() => false)) {
          await feld.fill('Tomasz')
          await seite.getByRole('button', { name: /Los geht/ }).click()
          await seite.waitForLoadState('networkidle')
          await seite.goto(`http://localhost:5199${pfad}`, { waitUntil: 'networkidle' })
        }
      }

      try { await schirm.tun?.(seite) } catch (f) { meldungen.push(`Klickweg: ${f}`) }
      await seite.waitForLoadState('networkidle').catch(() => {})
      await seite.waitForTimeout(250)

      const datei = join(BILDER, `${schirm.name}--${geraet.name}-${thema}.png`)
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
