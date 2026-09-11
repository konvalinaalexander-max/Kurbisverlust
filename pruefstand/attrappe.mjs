/**
 * Die Supabase-Attrappe der Prüfstände.
 *
 * Kein laufendes Supabase: Playwright fängt jede Anfrage an /rest/v1 und
 * /auth/v1 ab und antwortet aus den JSON-Dateien in pruefstand/daten/, die
 * daten_dumpen.sh aus der lokalen Demo-Datenbank gezogen hat. Die App sieht
 * echte Datenformen und echte Zahlen — nur eben ohne Netz.
 *
 * Was ein Klickweg schreibt, liest die App gleich darauf wieder (der
 * Abschluss-Assistent lässt erst weiter, wenn die Messung da ist). Deshalb
 * merkt sich die Attrappe Einfügungen. `vergessen()` setzt dieses Gedächtnis
 * zurück — je Bildschirm einmal, sonst schleppt der nächste die Messungen des
 * vorigen mit.
 *
 * Zwei Prüfstände teilen sie sich: bildschirme.mjs (rendert und fotografiert)
 * und beschriftung.mjs (liest jede Zahl mitsamt ihrer Beschriftung).
 */
import { existsSync, readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { filtern, seite } from './postgrest.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))
// Die Antworten kommen aus pruefstand/daten — oder aus einem anderen Ordner,
// wenn PRUEFSTAND_DATEN gesetzt ist (Runde N: die böse Saison aus
// gegenprobe/bildschirm/daten, ohne die Demo-Fixtures zu überschreiben).
const DATEN = process.env.PRUEFSTAND_DATEN ?? join(HIER, 'daten')
// 0057: die Attrappe nennt denselben Stand, den die App erwartet
/**
 * Welcher Chromium gestartet wird. Auf dieser Maschine liegt er entpackt unter
 * /opt/pw-browsers; in der CI installiert ihn Playwright selbst und findet ihn
 * von allein — dann darf kein Pfad gesetzt sein, sonst startet gar nichts.
 * Deshalb: Umgebungsvariable, sonst der lokale Pfad wenn es ihn gibt, sonst
 * undefined und Playwright sucht.
 */
export const CHROMIUM = process.env.PRUEFSTAND_CHROMIUM
  || (existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined)

export const SCHEMA_STAND = Number(
  readFileSync(join(HIER, '..', 'src', 'lib', 'version.ts'), 'utf8').match(/SCHEMA_ERWARTET = (\d+)/)[1])

export const fixture = name => {
  try { return JSON.parse(readFileSync(join(DATEN, `${name}.json`), 'utf8')) }
  catch { return null }
}

let geschrieben = {}
let naechsteId = 90001
/** Vor jedem Bildschirm: das Gedächtnis leeren, damit nur die Fixtures gelten. */
export function vergessen() { geschrieben = {} }

/** Welche Tabellen ein Lauf angefragt hat, ohne dass es ein Fixture gab. */
export const fehlendeFixtures = new Set()

export async function restAntwort(route) {
  const url = new URL(route.request().url())
  const name = url.pathname.replace(/^.*\/rest\/v1\//, '')
  const methode = route.request().method()

  if (name.startsWith('rpc/')) {
    const fn = name.slice(4)
    if (fn === 'auswertung_aktualisieren') return route.fulfill({ json: new Date().toISOString() })
    if (fn === 'auswertung_schritt') {
      const body = JSON.parse(route.request().postData() ?? '{}')
      const i = Number(body.p_schritt ?? 1)
      return route.fulfill({ json: {
        schritt: i, schritte: 5,
        titel: ['Rohdaten', 'Arbeiten', 'Kaskade', 'Ergebnis', 'Befunde'][i - 1],
        dauer_ms: 1, fertig: i === 5 } })
    }
    if (fn === 'schema_stand') return route.fulfill({ json: SCHEMA_STAND })
    if (fn === 'palox_letzter_stand') {
      const body = JSON.parse(route.request().postData() ?? '{}')
      const staende = fixture('rpc_palox_letzter_stand') ?? {}
      return route.fulfill({ json: staende[body.p_station] ?? null })
    }
    if (fn === 'demo_daten_laden') return route.fulfill({ json: 'Demo-Saison steht.' })
    if (fn === 'demo_daten_entfernen') return route.fulfill({ json: 'Demo-Daten entfernt.' })
    return route.fulfill({ json: fixture(`rpc_${fn}`) ?? null })
  }

  // Schreiben: gemerkt, damit die App das Geschriebene wiederfindet.
  if (methode !== 'GET' && methode !== 'HEAD') {
    let echo = []
    try { echo = JSON.parse(route.request().postData() ?? 'null') } catch { /* leer lassen */ }
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
    fehlendeFixtures.add(name)
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
const jwt = (id, name) => {
  const teil = o => Buffer.from(JSON.stringify(o)).toString('base64url')
  return `${teil({ alg: 'none' })}.${teil({
    sub: id, role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 86400,
    user_metadata: { name },
  })}.x`
}
const sitzung = (id, name, anonym) => ({
  access_token: jwt(id, name),
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
export const ADMIN = '11111111-1111-1111-1111-111111111111'
export const ARBEITER = '22222222-2222-2222-2222-222222222222'

export async function authAntwort(route, wer) {
  const url = new URL(route.request().url())
  const s = wer === 'arbeiter'
    ? sitzung(ARBEITER, 'Tomasz', true)
    : sitzung(ADMIN, 'Alexander', false)
  if (url.pathname.endsWith('/token') || url.pathname.endsWith('/signup')) return route.fulfill({ json: s })
  if (url.pathname.endsWith('/user')) return route.fulfill({ json: s.user })
  if (url.pathname.endsWith('/logout')) return route.fulfill({ status: 204, body: '' })
  return route.fulfill({ json: {} })
}
