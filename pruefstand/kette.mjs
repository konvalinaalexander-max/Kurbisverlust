/**
 * Die Kette in beide Richtungen: Über die Masken der App werden vier Arbeiten
 * und eine Lagerkontrolle erfasst — Waschen + Sortieren mit Kistensystem,
 * Paletten mit Datum und Gewicht vom Zettel zählen und eine wiegen (die
 * Erinnerung an drei), Palox ablesen, fertige Palette, zu klein / zu gross je
 * Palette am Ende, Abschluss mit den Fragen; Sortieren mit angepassten Bändern
 * und gezählten Kisten; Fax mit Palettenzahl und gewogenem Faulem; Waschen mit
 * eigenem Kaliber, Kaliber-Paletten mit Sortierdatum und Kisten, drei fertige
 * Paletten; die Lagerkontrolle mit Vorschlag, ohne Faul-Frage (0061). Jede
 * Schreibanfrage, die die App dabei an Supabase schickt, wird mitgeschnitten.
 *
 * Fax (0051, 0060) fuhr die Kette bis Runde R als dritten und sechsten
 * Durchlauf. Seit Runde R ist die Tätigkeit eingefroren — der Betrieb hat den
 * Nenner in Frage gestellt und das Faule an der Fax aus der Erfassung
 * genommen. Die Kette prüft jetzt das Gegenteil: dass die Fax **nicht mehr
 * angeboten** wird. Die Datenbank behält alles; die Prüfblöcke dazu stehen
 * weiter in pruefung.sql, wo die Fax-Arbeiten direkt in SQL entstehen.
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
import { filtern, seite as blaettern } from './postgrest.mjs'
import { CHROMIUM } from './attrappe.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))
// 0057: die Attrappe nennt denselben Stand, den die App erwartet
const SCHEMA_STAND = Number(readFileSync(join(HIER, '..', 'src', 'lib', 'version.ts'), 'utf8').match(/SCHEMA_ERWARTET = (\d+)/)[1])
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
    if (fn === 'schema_stand') return route.fulfill({ json: SCHEMA_STAND })
    if (fn === 'palox_stand_dieser_arbeit') {
      // Wie die echte Funktion (0072): der letzte Stand DERSELBEN Arbeit —
      // nie über die Arbeitsgrenze hinweg. Vor der ersten Ablesung: null,
      // und die Maske zeigt „Startstand", keine Menge.
      const body = JSON.parse(route.request().postData() ?? '{}')
      const eigene = (eingefuegt['schimmel_messung'] ?? [])
        .filter(m => m.auftrag_id === body.p_auftrag_id && m.palox_stand_kg != null && m.gemessen !== false)
      return route.fulfill({ json: eigene.length ? eigene[eigene.length - 1].palox_stand_kg : null })
    }
    if (fn === 'sortierschema_festlegen') {
      // Die Fassung legt die Datenbank fest (0051). Hier bekommt sie eine
      // Fake-Id; kette_pruefen.sh ruft die echte Funktion mit denselben
      // Argumenten und bildet die Id ab — wie bei jeder Einfügung.
      const body = JSON.parse(route.request().postData() ?? '{}')
      const id = naechsteId++
      protokoll.push({ methode: 'RPC', tabelle: 'sortierschema_festlegen', args: body, zeilen: [{ id }] })
      return route.fulfill({ json: id })
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
      // Upsert (Prefer: resolution=merge-duplicates) hält wie Postgres genau
      // eine Zeile je Konfliktschlüssel — sonst zählt der Kisten-Zähler
      // immer vom ersten Stand weiter.
      const schluessel = (url.searchParams.get('on_conflict') ?? '').split(',').map(k => k.trim()).filter(Boolean)
      const mischen = /merge-duplicates/.test(kopf['prefer'] ?? '') && schluessel.length
      let bestand = eingefuegt[name] ?? []
      if (mischen) {
        for (const neu of antwort) {
          const gleich = z => schluessel.every(k => String(z[k]) === String(neu[k]))
          const alt = bestand.find(gleich)
          if (alt) { neu.id = alt.id; bestand = bestand.filter(z => !gleich(z)) }
        }
      }
      eingefuegt[name] = [...bestand, ...antwort]
    } else {
      // PATCH: die Zeile im Gedächtnis anpassen
      const id = url.searchParams.get('id')?.replace('eq.', '')
      // Wie der Auslöser in 0039: Wer eine Arbeit abschliesst, schickt kein
      // Ende mit — das setzt der Server. Ohne diese Zeile hätte hier keine
      // abgeschlossene Arbeit ein `ende_ts`, und alles, was darauf baut
      // (Runde P: „Tage seit dem Waschen" vorbelegen), liefe im Prüfstand
      // ins Leere, ohne dass es auffiele.
      const auslöser = name === 'auftrag' && zeilen[0]?.status === 'abgeschlossen'
        ? { ende_ts: new Date().toISOString() } : {}
      eingefuegt[name] = (eingefuegt[name] ?? []).map(z =>
        String(z.id) === id ? { ...z, ...zeilen[0], ...auslöser } : z)
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
  const erg = blaettern(filtern(alle, url.searchParams), route.request().headers())
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
const browser = await chromium.launch({ executablePath: CHROMIUM })
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

await seite.goto('http://localhost:5198/', { waitUntil: 'networkidle' })
const feld = seite.getByLabel('Dein Name')
if (await feld.isVisible().catch(() => false)) {
  await feld.fill('Tomasz')
  await seite.getByRole('button', { name: /Los geht/ }).click()
  await seite.waitForLoadState('networkidle')
}

// ---------- Erster Durchlauf: Waschen + Sortieren (Vorarbeiter) -------------
let auftragId = null
await schritt('Assistent: Waschen + Sortieren, Charge 1613, Kiste ab 8 kg (kein Käufer mehr, 0060)', async () => {
  await seite.getByRole('button', { name: /Neue Arbeit/ }).click()
  await seite.locator('#taet-waschen_sortieren').click()
  await seite.locator('#charge').fill('1613')                 // AB-06: eintippen
  await seite.getByRole('button', { name: 'Weiter' }).click()
  if (await seite.locator('#kaeufer-keiner').count() > 0) throw new Error('Nach dem Käufer wird nicht mehr gefragt (0060)')
  await seite.locator('#system-kiste_ab').click()            // Kistensystem (0060)
  await seite.locator('#soll').waitFor()                      // Sollgewicht — wie zuletzt
  await seite.getByRole('button', { name: 'Weiter' }).click()
  await seite.getByRole('button', { name: 'Starten' }).click()
  await warteAuf('auftrag'); await warteAuf('auftrag_teilnehmer')
  const a = protokoll.find(p => p.tabelle === 'auftrag' && p.methode === 'POST')
  if (!a) throw new Error('kein POST auftrag')
  auftragId = a.zeilen[0].id
  if (a.zeilen[0].kistensystem !== 'kiste_ab' || Number(a.zeilen[0].soll_kg_pro_kiste) !== 8) throw new Error('Kistensystem nicht an der Arbeit')
})

await schritt('Nach dem Start steht der Palox als erstes — „Später" führt zur Checkliste', async () => {
  await seite.locator('#palox').waitFor()
  await seite.locator('#palox-spaeter').click()
  await seite.locator('#check-abschluss').waitFor()
  await seite.locator('#check-ausschuss').waitFor()      // zu klein / zu gross am Ende, je Palette (0061)
  if (await seite.locator('#leer-ja').count() > 0) throw new Error('Die Ausschuss-Frage gibt es nicht mehr (0060)')
})

await schritt('AB-02: ohne Ablesung kommt der Abschluss nicht an der Palox-Frage vorbei', async () => {
  await seite.locator('#check-abschluss').click()
  await seite.locator('#palox').waitFor()
  if (await seite.locator('#palox-unveraendert').count() > 0) throw new Error('„Stand unverändert" ohne Ablesung')
  if (await seite.locator('#palox-ohne').count() > 0) throw new Error('An der Waschstrasse mit Sortieren ist der Palox Pflicht')
  if (await seite.getByRole('button', { name: 'Weiter' }).count() > 0) throw new Error('„Weiter" ohne Ablesung')
  await seite.getByRole('button', { name: /Zurück/ }).click()
  await seite.locator('#check-abschluss').waitFor()
})

await schritt('Zähler: zwei Paletten mit Datum und Gewicht vom Zettel (950 kg), „+" zählt sofort', async () => {
  await seite.locator('#check-zaehlen').click()
  await seite.locator('#zettel').fill('2026-09-01')
  if (!(await seite.locator('#zaehlen-plus').isDisabled())) throw new Error('Ohne Gewicht vom Zettel darf „+" nicht gehen (0060)')
  for (let i = 0; i < 2; i++) {
    await seite.locator('#zettel-brutto').fill('950')
    await seite.locator('#zaehlen-plus').click()
    await warteAuf('auftrag_palette', 'POST', i + 1)
    // Die App leert das Gewicht nach dem Zählen — jede Palette wird neu getippt (0060)
    await seite.waitForFunction(() => document.querySelector('#zettel-brutto')?.value === '')
  }
  const p = protokoll.filter(x => x.tabelle === 'auftrag_palette')
  if (Number(p[0].zeilen[0].brutto_zettel_kg) !== 950) throw new Error('Das Zettelgewicht kommt nicht mit')
})

await schritt('Eine Palette wiegen: Zettel 950 → 900 kg, 40 Kisten G2, 6 je Kiste', async () => {
  await seite.locator('#zettel-brutto').fill('950')
  await seite.locator('#zum-wiegen').click()
  const vorbelegt = await seite.locator('#w-damals').inputValue()
  if (vorbelegt !== '950') throw new Error(`Das Eingangsgewicht muss aus dem Zähler vorbelegt sein, ist „${vorbelegt}"`)
  await seite.locator('#w-datum').fill('2026-09-01')
  await seite.locator('#w-jetzt').fill('900')
  await seite.locator('#w-kisten').fill('40')
  await seite.locator('#w-art').selectOption('G2')
  await seite.locator('#w-pro').fill('6')
  await seite.getByRole('button', { name: 'Eintragen' }).click()
  await warteAuf('verdunstung_wiegung'); await warteAuf('auftrag_palette', 'POST', 3)
})

await schritt('Palox zu Beginn: Waage zeigt 165 — ein Startstand, keine Menge (0072)', async () => {
  await seite.getByRole('button', { name: /Was zu tun ist/ }).click()
  await seite.locator('#check-palox').click()
  await seite.locator('#palox').fill('165')
  // Seit 0072 rechnet die Maske nicht mehr gegen die Tara: die erste
  // Ablesung einer Arbeit ist ihr Anfang, die Menge folgt am Ende (S₂ − S₁).
  await seite.locator('.netto-zeile strong', { hasText: /Startstand/ }).waitFor()
  if (await seite.locator('.netto-zeile strong', { hasText: /\d+ kg/ }).count() > 0) throw new Error('Die erste Ablesung darf keine Menge zeigen (0072)')
  if (await seite.locator('input[type=checkbox]').count() > 0) throw new Error('Das Häkchen „Palox geleert" gibt es nicht mehr (0060)')
  await seite.locator('#palox-eintragen').click()
  await warteAuf('schimmel_messung')
  await seite.locator('#check-abschluss').waitFor()
})

await schritt('Fertige Palette wiegen: 32 Kisten G2, 345 kg brutto → 8.5 kg je Kiste', async () => {
  await seite.locator('#check-ausgang').click()
  await seite.locator('#a-brutto').fill('345')
  await seite.locator('#a-kisten').fill('32')
  await seite.locator('#a-art').selectOption('G2')
  await seite.locator('#a-eintragen').click()
  await warteAuf('ausgang_wiegung')
  await seite.getByRole('button', { name: /Zurück/ }).click()
})

await schritt('Geführter Abschluss: Palox am Ende 285 (→ 120 kg), Erinnerung (1 von 3 gewogen), zu klein 60 kg brutto (4 G2 → 29 kg), fertige Palette erinnert, eine Charge → fertig', async () => {
  await seite.locator('#check-abschluss').click()
  // 0072: „Palox zwischendurch geleert?" — nein (kein PATCH: der Auftrag steht schon auf nein)
  await seite.locator('#geleert-nein').click()
  // AB-02 / 0072: die zweite Ablesung derselben Arbeit ergibt die Menge — 285 − 165 = 120.
  await seite.locator('#palox').fill('285')
  const palox = await seite.locator('.netto-zeile strong', { hasText: /\d+ kg/ }).first().textContent()
  if (!/^120 kg/.test(palox ?? '')) throw new Error(`Palox-Vorschau zeigt „${palox}" statt 120 kg (285 − 165)`)
  await seite.locator('#palox-eintragen').click()
  await warteAuf('schimmel_messung', 'POST', 2)
  // Runde H: nur eine von drei Paletten gewogen — gesagt, nicht erzwungen
  await seite.getByText('1 von 3 gewogen').first().waitFor()
  await seite.getByRole('button', { name: 'Trotzdem weiter' }).click()
  // zu klein / zu gross: Palette für Palette, Brutto + Kisten + Kistenart
  if (await seite.getByRole('button', { name: 'Weiter' }).count() > 0) throw new Error('Ohne Ausschuss-Messung darf es nicht weitergehen')
  await seite.locator('#aus-zu_klein').click()
  await seite.locator('#aus-brutto').fill('60')
  await seite.locator('#aus-kisten').fill('4')
  await seite.locator('#aus-art').selectOption('G2')
  const vorschau = await seite.locator('text=/\\d+ kg netto/').first().textContent()
  if (!/29 kg/.test(vorschau ?? '')) throw new Error(`Ausschuss-Vorschau zeigt „${vorschau}" statt 29 kg`)
  await seite.locator('#aus-eintragen').click()
  await warteAuf('ausschuss_messung')
  const m = protokoll.find(x => x.tabelle === 'ausschuss_messung').zeilen[0]
  if (m.art !== 'zu_klein' || Number(m.brutto_kg) !== 60 || m.kisten !== 4 || m.kg !== 29) throw new Error('Ausschuss je Palette kommt nicht mit')
  await seite.getByRole('button', { name: 'Weiter' }).click()
  await seite.getByRole('button', { name: 'Trotzdem weiter' }).click()   // fertige Palette: eine von drei gewogen
  await seite.locator('#charge-ja').click()
  await seite.getByRole('button', { name: 'Weiter' }).click()
  await seite.locator('#arbeit-fertig').click()
  await seite.locator('#ja-fertig').click()
  await warteAuf('auftrag', 'PATCH', 2)                       // palox_unbekannt = nein, dann der Abschluss
})

// ---------- Zweiter Durchlauf: Sortieren an der Maschine (AB-01, AB-06) ----
// Der andere Pfad: Chargennummer eintippen, Bänder anpassen, Palox direkt
// nach dem Start, Paletten mit Datum zählen, Kisten je Kaliber zählen,
// abschliessen.
await schritt('Assistent: Sortieren, Charge 1613 eingetippt, Bänder angepasst (0051)', async () => {
  await seite.goto('http://localhost:5198/', { waitUntil: 'networkidle' })
  await seite.getByRole('button', { name: /Neue Arbeit/ }).click()
  await seite.locator('#taet-sortieren').click()
  await seite.locator('#charge').fill('1613')
  await seite.getByRole('button', { name: 'Weiter' }).click()
  // Die Maschine kennt nur Bänder: „wie zuletzt" steht vorbelegt, „Anpassen"
  // macht die Grenzen tippbar — die zweite Grenze wird von 800 auf 900 gesetzt.
  await seite.locator('#baender-uebernehmen').waitFor()
  await seite.locator('#baender-anpassen').click()
  await seite.locator('#grenze-1').fill('900')
  await seite.getByRole('button', { name: 'Weiter' }).click()
  await seite.getByRole('button', { name: 'Starten' }).click()
  await warteAuf('auftrag', 'POST', 2)
  await warteAuf('auftrag_teilnehmer', 'POST', 2)
})

await schritt('Sortieren: Palox direkt nach dem Start (60, dann 75 am Ende → 15 kg), eine Palette mit Zettelgewicht, abschliessen', async () => {
  await seite.locator('#palox').fill('60')                    // Startstand dieser Arbeit (0072), keine Menge
  await seite.locator('#palox-eintragen').click()
  await warteAuf('schimmel_messung', 'POST', 3)
  await seite.locator('#check-zaehlen').click()
  await seite.locator('#zettel').fill('2026-09-05')
  // 0072: auch beim Sortieren steht das Zettelgewicht — „anzahl paletten mit
  // total vom brutto gewicht - dann weisst du wieviel sortiert worden ist".
  await seite.locator('#zettel-brutto').fill('940')
  await seite.locator('#zaehlen-plus').click()                // ohne Wiegen zählt „+" direkt
  await warteAuf('auftrag_palette', 'POST', 4)
  // Kisten je Kaliber werden seit Runde Q nicht mehr gezählt (ENTSCHEIDUNGEN
  // „Kisten je Kaliber zählen: gestrichen") — die Masse je Band kommt aus
  // Zettelgewicht und Verkaufsdatei.
  if (await seite.getByRole('tab', { name: 'Kisten' }).count() > 0) throw new Error('Kisten je Kaliber werden nicht mehr gezählt (Runde Q)')
  await seite.getByRole('button', { name: /Was zu tun ist/ }).click()
  await seite.locator('#check-abschluss').click()
  await seite.locator('#geleert-nein').click()
  await seite.locator('#palox').fill('75')                    // 75 − 60 = 15 kg Faules dieser Arbeit
  await seite.locator('#palox-eintragen').click()
  await warteAuf('schimmel_messung', 'POST', 4)
  await seite.locator('#charge-ja').click()
  await seite.getByRole('button', { name: 'Weiter' }).click()
  await seite.locator('#arbeit-fertig').click()
  await seite.locator('#ja-fertig').click()
  await warteAuf('auftrag', 'PATCH', 4)
})

// ---------- Dritter Durchlauf: entfällt — die Fax ist eingefroren (Runde R) --
// Hier lief bis Runde R der Fax-Durchlauf (Paletten gesamt, Faules kistenweise,
// Tage seit dem Waschen). Was davon in der Datenbank steht, bleibt dort und
// wird in pruefung.sql weiter geprüft; die Oberfläche bietet es nicht mehr an.
await schritt('Fax wird nicht mehr angeboten — die Tätigkeit ist eingefroren (Runde R)', async () => {
  await seite.goto('http://localhost:5198/', { waitUntil: 'networkidle' })
  await seite.getByRole('button', { name: /Neue Arbeit/ }).click()
  await seite.locator('#taet-waschen').waitFor()
  if (await seite.locator('#taet-fax').count() > 0) throw new Error('Die Fax steht noch zur Wahl — sie ist eingefroren (taetigkeit.ts, angeboten: false)')
  const wahl = await seite.locator('[id^=taet-]').count()
  if (wahl !== 3) throw new Error(`Drei Tätigkeiten erwartet (Sortieren, Waschen, Waschen + Sortieren), es stehen ${wahl} da`)
})

// ---------- Vierter Durchlauf: Waschen mit eigenem Kaliber (0054, 0061) ----
// Das Etikett nennt ein Band, das die Fassung nicht kennt: 700–900 g. Gezählt
// werden die Kaliber-Paletten aus dem Zwischenlager mit dem Sortierdatum vom
// Zettel und den Kisten darauf; eine ohne Datum. Stück-Kisten (6 je Kiste),
// drei fertige Paletten (verlangt); der Palox ist freiwillig.
await schritt('Assistent: Waschen, Charge 1613, eigenes Kaliber 700–900 g, 6 Stück je Kiste', async () => {
  await seite.goto('http://localhost:5198/', { waitUntil: 'networkidle' })
  await seite.getByRole('button', { name: /Neue Arbeit/ }).click()
  await seite.locator('#taet-waschen').click()
  await seite.locator('#charge').fill('1613')
  await seite.getByRole('button', { name: 'Weiter' }).click()
  await seite.locator('#kaliber-0').waitFor()            // die Bänder der Sorte stehen zur Wahl
  await seite.locator('#kaliber-eigen').click()
  await seite.locator('#kaliber-von').fill('700')
  await seite.locator('#kaliber-bis').fill('900')
  await seite.getByRole('button', { name: 'Weiter' }).click()
  await seite.locator('#system-stueck').click()
  await seite.locator('#stueck').fill('6')
  await seite.getByRole('button', { name: 'Weiter' }).click()
  await seite.getByRole('button', { name: 'Starten' }).click()
  await warteAuf('auftrag', 'POST', 3)
  await warteAuf('auftrag_teilnehmer', 'POST', 3)
})

await schritt('Waschen: Palox freiwillig, Paletten mit Sortierdatum (2 × 32 Kisten) und ohne Datum (1), drei fertige Paletten, abschliessen', async () => {
  await seite.locator('#check-abschluss').waitFor()      // kein Palox-Zwang nach dem Start
  await seite.locator('#check-zaehlen').click()
  if (await seite.locator('#kiste-plus-eigen').count() > 0) throw new Error('Beim Waschen werden Paletten gezählt, keine Kisten je Kaliber (0061)')
  if (!(await seite.locator('#wasch-plus').isDisabled())) throw new Error('Ohne Sortierdatum darf keine Palette gezählt werden')
  // 0072: „teilweise sinds 32 und teilweise 36" — die Einstellung belegt 36
  // vor, gefragt wird je Palette. Hier stehen 32 auf der Palette.
  const kisten = await seite.locator('#kisten-palette').inputValue()
  if (kisten !== '36') throw new Error(`Kisten je Palette müssen aus der Einstellung vorbelegt sein (36), ist „${kisten}"`)
  await seite.locator('#kisten-palette').fill('32')
  await seite.locator('#sortierdatum').fill('2026-09-03')
  for (let i = 1; i <= 2; i++) {
    await seite.locator('#wasch-plus').click()
    await warteAuf('auftrag_palette', 'POST', 4 + i)
  }
  await seite.locator('#kein-sortierdatum').check()
  await seite.locator('#wasch-plus').click()
  await warteAuf('auftrag_palette', 'POST', 7)
  const g = protokoll.filter(x => x.tabelle === 'auftrag_palette').map(x => x.zeilen[0])
  if (g[4].sortierdatum !== '2026-09-03' || g[4].kisten !== 32 || g[6].sortierdatum !== null || g[6].kisten !== 32) throw new Error('Sortierdatum und Kisten je Palette kommen nicht mit')
  if (g[4].eingangsdatum !== undefined) throw new Error('Eine Kaliber-Palette hat kein Eingangsdatum')
  await seite.getByText('Paletten · 96 Kisten').first().waitFor()
  await seite.getByRole('button', { name: /Was zu tun ist/ }).click()
  await seite.locator('#check-ausgang').click()
  const pro = await seite.locator('#a-pro').inputValue()
  if (pro !== '6') throw new Error(`Stück je Kiste muss aus der Arbeit vorbelegt sein, ist „${pro}"`)
  for (let i = 1; i <= 3; i++) {                              // drei fertige Paletten (Runde H)
    // Die Maske leert die Felder erst nach dem Nachladen — vorher nicht tippen
    await seite.waitForFunction(() => document.querySelector('#a-brutto')?.value === '')
    await seite.locator('#a-brutto').fill('400')
    await seite.locator('#a-kisten').fill('32')
    await seite.locator('#a-art').selectOption('G2')
    await seite.locator('#a-eintragen').click()
    await warteAuf('ausgang_wiegung', 'POST', 1 + i)
  }
  await seite.getByRole('button', { name: /Zurück/ }).click()
  await seite.locator('#check-abschluss').click()
  await seite.locator('#palox-ohne').click()                     // freiwillig beim Waschen (0060)
  await seite.getByText('3 Paletten mit 96 Kisten').first().waitFor()
  await seite.getByRole('button', { name: 'Weiter' }).click()   // Paletten: drei gezählt
  await seite.getByText('3 fertige Paletten gewogen').first().waitFor()
  // Runde R/0079: Wie viele Paletten insgesamt fertig wurden, ist der Nenner
  // des Waschens. Drei davon sind gewogen, fünf wurden es — daraus kennt die
  // Auswertung die Masse, die herauskam, ohne ein Kistengewicht für das eigene
  // Kaliber zu brauchen. Ohne Palox-Ablesung ist das Feld freiwillig; hier wird
  // es trotzdem gefüllt, damit der neue Weg im Prüfstand wirklich läuft.
  await seite.locator('#fertige-gesamt').fill('5')
  await seite.getByRole('button', { name: 'Weiter' }).click()   // fertige Paletten: drei gewogen, fünf gesamt
  await seite.locator('#charge-ja').click()
  await seite.getByRole('button', { name: 'Weiter' }).click()
  await seite.locator('#arbeit-fertig').click()
  await seite.locator('#ja-fertig').click()
  await warteAuf('auftrag', 'PATCH', 5)
})

// ---------- Fünfter Durchlauf: Palette kontrollieren (0061) ----------------
// Die App schlägt Chargen vor; der Arbeiter nimmt eine andere, trägt Datum
// und Gewicht vom Zettel ein — und die Maske bleibt für die nächste Palette.
// Nicht mehr gefragt: „davon faul" und „wie gegriffen" (Runde H).
await schritt('Kontrolle: andere Charge, Zettel 950 → 905 kg, ohne Faul-Frage — zweimal hintereinander', async () => {
  await seite.goto('http://localhost:5198/kontrolle', { waitUntil: 'networkidle' })
  if (await seite.locator('#vorschlag-andere').count() > 0) await seite.locator('#vorschlag-andere').click()
  await seite.locator('#k-charge').fill('1613')
  if (await seite.locator('#k-faul').count() > 0) throw new Error('„Davon faul" wird nicht mehr gefragt (0061)')
  if (await seite.locator('#k-auswahl').count() > 0) throw new Error('„Wie gegriffen" wird nicht mehr gefragt (0061)')
  for (let i = 1; i <= 2; i++) {
    await seite.locator('#k-datum').fill('2026-09-02')
    await seite.locator('#k-damals').fill('950')
    await seite.locator('#k-jetzt').fill('905')
    await seite.locator('#k-kisten').fill('40')
    await seite.locator('#k-art').selectOption('G2')
    await seite.locator('#k-eintragen').click()
    await warteAuf('verdunstung_wiegung', 'POST', 1 + i)
  }
  const w = protokoll.filter(x => x.tabelle === 'verdunstung_wiegung').map(x => x.zeilen[0])
  if (w[2].charge_nr !== 1613 || 'faul_kg' in w[2] || 'auswahl' in w[2]) throw new Error('Die Kontrolle bleibt nicht auf der Charge stehen — oder schreibt noch faul/auswahl')
})

// ---------- Sechster Durchlauf: entfällt (Fax, siehe oben) ----------------


await browser.close(); await vite.close()
if (konsole.length) { console.log('  Konsolenfehler:'); for (const k of konsole) console.log('   ', k) }
writeFileSync(join(HIER, 'kette_erfasst.json'), JSON.stringify(protokoll, null, 2))
console.log(`Mitgeschnitten: ${protokoll.length} Schreibanfragen → pruefstand/kette_erfasst.json`)
process.exit(konsole.length ? 1 : 0)
