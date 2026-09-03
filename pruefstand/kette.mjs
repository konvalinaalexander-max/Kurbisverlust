/**
 * Die Kette in beide Richtungen: Über die Masken der App wird eine komplette
 * Arbeit erfasst — neue Arbeit mit Käufer, Paletten zählen und eine wiegen,
 * Palox ablesen, zu klein und zu gross, Abschluss mit den Fragen. Jede
 * Schreibanfrage, die die App dabei an Supabase schickt, wird mitgeschnitten.
 *
 * Der zweite Teil (kette_pruefen.sh) spielt genau diese Anfragen in eine
 * echte Postgres ein und prüft, ob jeder eingegebene Wert in der Auswertung
 * ankommt. Das fängt, was der Bildschirm-Prüfstand nicht fangen kann: eine
 * Spalte, die die App schreibt und die Datenbank nicht kennt — der Prüfstand
 * nimmt jedes POST entgegen, Postgres nicht.
 *
 *   node pruefstand/kette.mjs          →  pruefstand/kette_erfasst.json
 */
import { chromium } from 'playwright'
import { createServer } from 'vite'
import { readFileSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { filtern } from './postgrest.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))
const DATEN = join(HIER, 'daten')
const fixture = name => {
  try { return JSON.parse(readFileSync(join(DATEN, `${name}.json`), 'utf8')) } catch { return null }
}

/* ---------- Ein Mini-PostgREST mit Gedächtnis ---------------------------- */
// Was die App schreibt, liest sie kurz darauf wieder — die neue Arbeit, die
// gezählten Paletten. Also merken wir uns Einfügungen und liefern sie mit.
const eingefuegt = {}          // tabelle → Zeilen
const protokoll = []           // jede Schreibanfrage der Reihe nach
let naechsteId = 90001

async function restAntwort(route) {
  const url = new URL(route.request().url())
  const name = url.pathname.replace(/^.*\/rest\/v1\//, '')
  const methode = route.request().method()
  const kopf = route.request().headers()
  const einzeln = (kopf['accept'] ?? '').includes('pgrst.object')

  if (name.startsWith('rpc/')) {
    const fn = name.slice(4)
    if (fn === 'auswertung_aktualisieren') return route.fulfill({ json: new Date().toISOString() })
    if (fn === 'palox_letzter_stand') {
      const body = JSON.parse(route.request().postData() ?? '{}')
      const staende = fixture('rpc_palox_letzter_stand') ?? {}
      return route.fulfill({ json: staende[body.p_station] ?? null })
    }
    return route.fulfill({ json: fixture(`rpc_${fn}`) ?? null })
  }

  if (methode === 'POST' || methode === 'PATCH') {
    let body = null
    try { body = JSON.parse(route.request().postData() ?? 'null') } catch { body = null }
    const zeilen = Array.isArray(body) ? body : [body]
    const antwort = zeilen.map(z => {
      const zeile = { id: naechsteId++, ts: new Date().toISOString(), ...z }
      return zeile
    })
    protokoll.push({ methode, tabelle: name, prefer: kopf['prefer'] ?? '',
                     filter: Object.fromEntries(url.searchParams), zeilen: antwort })
    if (methode === 'POST') {
      eingefuegt[name] = [...(eingefuegt[name] ?? []), ...antwort]
    } else {
      // PATCH: die Zeile im Gedächtnis anpassen
      const id = url.searchParams.get('id')?.replace('eq.', '')
      eingefuegt[name] = (eingefuegt[name] ?? []).map(z =>
        String(z.id) === id ? { ...z, ...zeilen[0] } : z)
    }
    return route.fulfill({ status: 201, json: einzeln ? antwort[0] : antwort })
  }
  if (methode === 'DELETE') {
    protokoll.push({ methode, tabelle: name, filter: Object.fromEntries(url.searchParams) })
    return route.fulfill({ status: 204, body: '' })
  }

  // Die App liest Angaben über die Sicht v_auftrag_angabe, schreibt aber in
  // die Tabelle auftrag_angabe. Damit die Kette den frisch geschriebenen Wert
  // sofort wiedersieht, spiegeln wir die Einfügungen (jüngste je Schlüssel).
  let extra = eingefuegt[name] ?? []
  if (name === 'v_auftrag_angabe') {
    const roh = eingefuegt['auftrag_angabe'] ?? []
    const letzte = new Map()
    for (const z of roh) letzte.set(`${z.auftrag_id}|${z.schluessel}`, z)
    extra = [...extra, ...letzte.values()]
  }
  const alle = [...(fixture(name) ?? []), ...extra]
  const erg = filtern(alle, url.searchParams)
  if (methode === 'HEAD') {
    return route.fulfill({ status: 200, headers: {
      'content-range': `0-${Math.max(erg.length - 1, 0)}/${erg.length}` }, body: '' })
  }
  return route.fulfill({ json: einzeln ? (erg[0] ?? null) : erg })
}

const ARBEITER = '22222222-2222-2222-2222-222222222222'
const jwt = (id, name) => {
  const teil = o => Buffer.from(JSON.stringify(o)).toString('base64url')
  return `${teil({ alg: 'none' })}.${teil({ sub: id, role: 'authenticated',
    exp: Math.floor(Date.now() / 1000) + 86400, user_metadata: { name } })}.x`
}
const sitzung = {
  access_token: jwt(ARBEITER, 'Tomasz'), token_type: 'bearer', expires_in: 86400,
  expires_at: Math.floor(Date.now() / 1000) + 86400, refresh_token: 'pruefstand',
  user: { id: ARBEITER, aud: 'authenticated', role: 'authenticated', is_anonymous: true,
          user_metadata: { name: 'Tomasz' }, app_metadata: {}, created_at: '2026-09-01T08:00:00Z' },
}
async function authAntwort(route) {
  const url = new URL(route.request().url())
  if (url.pathname.endsWith('/user')) return route.fulfill({ json: sitzung.user })
  if (url.pathname.endsWith('/logout')) return route.fulfill({ status: 204, body: '' })
  return route.fulfill({ json: sitzung })
}

/* ---------- Der Weg durch die App ----------------------------------------- */
const vite = await createServer({ root: join(HIER, '..'), server: { port: 5198, strictPort: true }, logLevel: 'silent' })
await vite.listen()
const browser = await chromium.launch({ executablePath: process.env.PRUEFSTAND_CHROMIUM ?? '/opt/pw-browsers/chromium' })
const kontext = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'de-CH' })
const seite = await kontext.newPage()
const konsole = []
seite.on('console', m => { if (m.type() === 'error') konsole.push(m.text()) })
seite.on('pageerror', f => konsole.push(String(f)))
if (process.env.KETTE_DEBUG) {
  seite.on('request', r => { if (r.url().includes('/rest/v1/')) console.log('   →', r.method(), r.url().replace(/^.*\/rest\/v1\//, ''), r.postData() ?? '') })
  seite.on('console', m => console.log('   konsole:', m.type(), m.text()))
}
await seite.route('**/rest/v1/**', r => restAntwort(r).catch(f => { konsole.push(String(f)); r.abort() }))
await seite.route('**/auth/v1/**', r => authAntwort(r).catch(() => r.abort()))
await seite.addInitScript(() => {
  localStorage.setItem('sprache', 'de')
  localStorage.setItem('sprache_tag', new Date().toISOString().slice(0, 10))
  localStorage.setItem('pruefstand_wer', 'arbeiter')
})

/** Wartet, bis die App eine bestimmte Schreibanfrage abgeschickt hat — die
 *  kommt nach dem Klick mit einem Augenblick Verzögerung, und networkidle
 *  meldet sich schon vorher. */
async function warteAuf(tabelle, methode = 'POST', anzahl = 1) {
  for (let i = 0; i < 100; i++) {
    if (protokoll.filter(p => p.tabelle === tabelle && p.methode === methode).length >= anzahl) return
    await seite.waitForTimeout(100)
  }
  throw new Error(`${methode} ${tabelle} (${anzahl}×) kam nicht`)
}

const schritt = async (name, fn) => {
  try { await fn(); console.log(`  ✓ ${name}`) }
  catch (f) {
    console.log(`  ✗ ${name}: ${f}`)
    console.log('  bisher geschrieben:', protokoll.map(p => `${p.methode} ${p.tabelle}`).join(', ') || '—')
    for (const k of konsole) console.log('  Konsole:', k)
    await seite.screenshot({ path: join(HIER, 'bilder', 'kette-fehler.png'), fullPage: true })
    await browser.close(); await vite.close(); process.exit(1)
  }
}

await seite.goto('http://localhost:5198/auftraege', { waitUntil: 'networkidle' })
const feld = seite.getByLabel('Dein Name')
if (await feld.isVisible().catch(() => false)) {
  await feld.fill('Tomasz')
  await seite.getByRole('button', { name: /Los geht/ }).click()
  await seite.waitForLoadState('networkidle')
}

let auftragId = null
await schritt('Neue Arbeit: Waschen + Sortieren, Charge 1613, neuer Käufer Coop', async () => {
  await seite.getByRole('button', { name: /Neue Arbeit/ }).click()
  await seite.getByRole('button', { name: 'Waschen + Sortieren' }).click()
  await seite.locator('#charge').fill('1613')
  await seite.locator('#kaeufer').selectOption('__neu__')
  await seite.getByPlaceholder('Name des Käufers').fill('Coop')
  // AB-01: Waschen + Sortieren fragt jetzt, wie sortiert wird.
  await seite.getByRole('button', { name: 'Kiste ab x kg' }).click()
  await seite.getByRole('button', { name: 'Starten' }).click()
  await warteAuf('auftrag'); await warteAuf('auftrag_teilnehmer')
  const a = protokoll.find(p => p.tabelle === 'auftrag' && p.methode === 'POST')
  if (!a) throw new Error('kein POST auftrag')
  auftragId = a.zeilen[0].id
})

await seite.goto(`http://localhost:5198/auftraege/${auftragId}`, { waitUntil: 'networkidle' })

await schritt('AB-05: Ausschuss-Paletten sind leer (Startfrage)', async () => {
  await seite.getByRole('button', { name: 'Ja', exact: true }).click()
  await warteAuf('auftrag_angabe', 'POST', 1)
})

await schritt('Zwei Paletten nur zählen, mit Datum vom Zettel', async () => {
  await seite.locator('#zettel').fill('2026-09-01')
  for (let i = 0; i < 2; i++) {
    await seite.getByRole('button', { name: '+', exact: true }).click()
    await seite.getByRole('button', { name: 'Nur zählen' }).click()
    await warteAuf('auftrag_palette', 'POST', i + 1)
  }
})

await schritt('Eine Palette wiegen: 950 → 900 kg, 40 Kisten G2, 6 je Kiste', async () => {
  await seite.getByRole('button', { name: '+', exact: true }).click()
  await seite.getByRole('button', { name: /wiegen/i }).first().click()
  await seite.locator('#w-datum').fill('2026-09-01')
  await seite.locator('#w-damals').fill('950')
  await seite.locator('#w-jetzt').fill('900')
  await seite.locator('#w-kisten').fill('40')
  await seite.locator('#w-art').selectOption('G2')
  await seite.locator('#w-pro').fill('6')
  await seite.getByRole('button', { name: 'Eintragen' }).click()
  await warteAuf('verdunstung_wiegung'); await warteAuf('auftrag_palette', 'POST', 3)
})

await schritt('AB-02: ohne Palox-Ablesung ist der Abschluss gesperrt', async () => {
  await seite.getByRole('link', { name: 'Fertig', exact: true }).click()
  await seite.getByRole('button', { name: 'Ja, alles aus einer Charge' }).click()
  const fertig = seite.getByRole('button', { name: /Arbeit fertig/ })
  if (!(await fertig.isDisabled())) throw new Error('Abschluss trotz fehlender Palox-Ablesung möglich')
  // zurück zur Faule-Maske für die eigentliche Ablesung
  await seite.getByRole('link', { name: 'Faule' }).click()
})

await schritt('Palox: Waage zeigt 165 (Tara 45 → 120 kg)', async () => {
  await seite.getByRole('link', { name: 'Faule' }).click()
  await seite.locator('#palox').fill('165')
  const vorschau = await seite.locator('text=/\\d+ kg/').first().textContent()
  if (!/120 kg/.test(vorschau ?? '')) throw new Error(`Vorschau zeigt „${vorschau}" statt 120 kg`)
  await seite.getByRole('button', { name: 'Eintragen' }).click()
  await warteAuf('schimmel_messung')
})

await schritt('Zu klein wiegen (Brutto 100, 4 Kisten G2 → netto), zu gross schätzen 15 kg', async () => {
  await seite.getByRole('link', { name: 'Klein / gross' }).click()
  // Wiegen: Brutto und Kisten, das Netto rechnet die Datenbank.
  await seite.locator('#aus-brutto').fill('100')
  await seite.locator('#aus-kisten').fill('4')
  await seite.locator('#aus-art').selectOption('G2')
  await seite.getByRole('button', { name: 'Eintragen' }).click()
  await warteAuf('ausschuss_messung', 'POST', 1)
  // Zu gross: Schätzung, wenn nicht gewogen werden kann.
  await seite.getByRole('button', { name: 'Zu gross' }).click()
  await seite.getByRole('button', { name: 'Schätzen', exact: true }).click()
  await seite.locator('#aus-schaetz').fill('15')
  await seite.getByRole('button', { name: 'Eintragen' }).click()
  await warteAuf('ausschuss_messung', 'POST', 2)
})

await schritt('Abschluss: eine Charge, Ausschuss von dieser Arbeit → fertig', async () => {
  await seite.getByRole('link', { name: 'Fertig', exact: true }).click()
  await seite.getByRole('button', { name: 'Ja, alles aus einer Charge' }).click()
  // AB-05: die zweite Ausschuss-Frage im Abschluss
  await seite.getByRole('button', { name: 'Ja', exact: true }).click()
  await seite.getByRole('button', { name: /Arbeit fertig/ }).click()
  await seite.getByRole('button', { name: /Ja, fertig/ }).click()
  await warteAuf('auftrag', 'PATCH')
})

// ---------- Zweiter Durchlauf: Sortieren an der Maschine (AB-01, AB-06) ----
// Der andere Pfad: Sortierart wählen, Chargennummer eintippen, Paletten mit
// Datum zählen, Palox ablesen, abschliessen. Keine Ausschuss-Fragen (Maschine).
let sortierId = null
await schritt('Sortieren: Charge 1613 eingetippt, Kaliber gewählt', async () => {
  await seite.goto('http://localhost:5198/auftraege', { waitUntil: 'networkidle' })
  await seite.getByRole('button', { name: /Neue Arbeit/ }).click()
  await seite.getByRole('button', { name: /^[^ ]+ Sortieren$/ }).click()
  await seite.locator('#charge').fill('1613')                 // AB-06: eintippen
  await seite.getByRole('button', { name: 'Kaliber (nach Grösse)' }).click()  // AB-01
  await seite.getByRole('button', { name: 'Starten' }).click()
  await warteAuf('auftrag', 'POST', 2)
  const posts = protokoll.filter(p => p.tabelle === 'auftrag' && p.methode === 'POST')
  sortierId = posts[posts.length - 1].zeilen[0].id
  await warteAuf('auftrag_teilnehmer', 'POST', 2)
})

await seite.goto(`http://localhost:5198/auftraege/${sortierId}`, { waitUntil: 'networkidle' })

await schritt('Sortieren: eine Palette zählen, Palox ablesen, abschliessen', async () => {
  await seite.locator('#zettel').fill('2026-09-05')
  // Ohne Wiegen zählt „+" direkt (keine Frage wie bei Waschen + Sortieren).
  await seite.getByRole('button', { name: '+', exact: true }).click()
  await warteAuf('auftrag_palette', 'POST', 3)
  await seite.getByRole('link', { name: 'Faule' }).click()
  await seite.locator('#palox').fill('60')                    // erste Ablesung: 60 − 45 = 15
  await seite.getByRole('button', { name: 'Eintragen' }).click()
  await warteAuf('schimmel_messung', 'POST', 2)
  await seite.getByRole('link', { name: 'Fertig', exact: true }).click()
  await seite.getByRole('button', { name: 'Ja, alles aus einer Charge' }).click()
  await seite.getByRole('button', { name: /Arbeit fertig/ }).click()
  await seite.getByRole('button', { name: /Ja, fertig/ }).click()
  await warteAuf('auftrag', 'PATCH', 2)
})

await browser.close(); await vite.close()
if (konsole.length) { console.log('  Konsolenfehler:'); for (const k of konsole) console.log('   ', k) }
writeFileSync(join(HIER, 'kette_erfasst.json'), JSON.stringify(protokoll, null, 2))
console.log(`Mitgeschnitten: ${protokoll.length} Schreibanfragen → pruefstand/kette_erfasst.json`)
process.exit(konsole.length ? 1 : 0)
