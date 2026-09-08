/**
 * Der Begriffs-Prüfstand: Sagt jede Zahl, was sie ist?
 *
 * Der Betriebsleiter am 9. September: „auf der Webseite hast du immer noch so
 * komische Angaben wie einfach einen Verlust, der nicht klar ist." Genau das
 * prüft dieses Werkzeug — und zwar nicht am Quelltext, sondern an dem, was ein
 * Mensch auf dem Bildschirm liest.
 *
 * Ablauf: Jede Seite des Betriebsleiters wird in einem echten Browser mit den
 * echten Demo-Daten gerendert (Attrappe wie beim Bildschirm-Prüfstand). Dann
 * erntet der Prüfstand im Dokument jede Zahl mit Einheit samt ihrer
 * Beschriftung — Kennzahl-Titel, Spaltenkopf, Begriff einer Liste, Text davor
 * — und prüft sie gegen sechs Regeln:
 *
 *   R1  Jede Zahl mit Einheit hat überhaupt eine Beschriftung.
 *   R2  Jede Beschriftung einer Masse steht im Begriffslexikon
 *       (pruefstand/begriffe.json) — mit Bedeutung und Herkunftsspalte.
 *       Ein neuer Name muss dort eingetragen werden, sonst schlägt der
 *       Prüfstand an: So kann niemand still einen unklaren Begriff einführen.
 *       Passt mehr als ein Eintrag, gewinnt der längste: „Gewogene Masse ·
 *       zu klein" ist eine gewogene Masse, kein hochgerechneter Kanal.
 *   R3  „Verlust" nie ohne Zusatz: bis heute · echter · kein echter ·
 *       erwartet · Prognose · in 14 Tagen. „Verlust" allein ist mehrdeutig.
 *   R4  Jede gerechnete Grösse trägt in ihrer Karte die Herkunftsmarke, die
 *       zu ihr gehört — nicht irgendeine. Ein Begriff, der je nach Karte
 *       gemessen oder gerechnet sein kann („Verdunstet" ist in der
 *       Wägungstabelle die Differenz zweier Wägungen, in der Bilanz die
 *       Hochrechnung daraus), steht im Lexikon als „gemessen|gerechnet";
 *       dann muss die Karte sagen, welches von beiden hier gilt.
 *   R5  Jede Prozentzahl nennt ihre Bezugsgrösse in Beschriftung, Untertitel
 *       oder Kartentext („von", „des Eingangs", „je Kiste", „Anteil …").
 *   R6  Verbotene Wörter: „Buch A", „Buch B" (Modellsprache), „NaN",
 *       „undefined", „Infinity", „[object" (kaputte Zahlen), und auf den
 *       Auswertungsseiten „Käufer" (seit 0060 keine Grösse mehr).
 *
 * Dazu die Gegenprobe in Zahlen: Die Kopfzahlen des Überblicks werden aus den
 * Fixtures unabhängig nachgerechnet und mit dem verglichen, was auf dem
 * Bildschirm steht. Eine richtige Beschriftung an einer falschen Zahl wäre
 * schlimmer als gar keine.
 *
 *   node pruefstand/beschriftung.mjs           # alle Seiten
 *   node pruefstand/beschriftung.mjs ursachen  # nur Seiten mit „ursachen"
 *   ERNTE=1 node pruefstand/beschriftung.mjs   # gefundene Begriffe auflisten
 */
import { chromium } from 'playwright'
import { createServer } from 'vite'
import { readFileSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { CHROMIUM, authAntwort, fixture, restAntwort, vergessen } from './attrappe.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))
const NUR = process.argv[2] ?? ''
const ERNTE = process.env.ERNTE === '1'
const LEXIKON = JSON.parse(readFileSync(join(HIER, 'begriffe.json'), 'utf8'))

/* ---------- Die Seiten des Betriebsleiters ------------------------------- */
// Jede Ansicht, die Zahlen zeigt — auch die, die erst ein Klick öffnet.
const SEITEN = [
  { name: 'ueberblick', pfad: '/dashboard' },
  { name: 'ueberblick-sorte', pfad: '/dashboard',
    tun: async p => { await reiter(p, 'je Sorte'); } },
  { name: 'ueberblick-charge', pfad: '/dashboard',
    tun: async p => { await reiter(p, 'je Charge'); } },
  { name: 'ueberblick-imhaus', pfad: '/dashboard',
    tun: async p => { await aufklappen(p) } },
  { name: 'ursachen', pfad: '/ursachen' },
  { name: 'ursachen-aufgeklappt', pfad: '/ursachen', tun: async p => { await aufklappen(p) } },
  { name: 'chargen', pfad: '/chargen' },
  { name: 'chargen-offen', pfad: '/chargen',
    tun: async p => {
      const zeile = p.locator('tbody tr').first()
      await zeile.waitFor({ state: 'visible', timeout: 60000 })
      await zeile.click(); await p.waitForTimeout(400)
    } },
  { name: 'messungen', pfad: '/messungen' },
  { name: 'messungen-aufgeklappt', pfad: '/messungen', tun: async p => { await aufklappen(p) } },
  { name: 'betrieb-arbeiten', pfad: '/betrieb/arbeiten' },
  { name: 'betrieb-lieferungen', pfad: '/betrieb/lieferungen' },
]
const reiter = async (p, name) => {
  const r = p.getByRole('tab', { name }).first()
  await r.waitFor({ state: 'visible', timeout: 60000 })
  await r.click()
  await p.waitForTimeout(400)
}
/** Alles aufklappen, was zu ist — die Zahlen darin gehören genauso geprüft. */
const aufklappen = async p => {
  await p.evaluate(() => document.querySelectorAll('details').forEach(d => { d.open = true }))
  await p.waitForTimeout(500)
}

/* ---------- Die Ernte im Dokument ---------------------------------------- */
// Läuft im Browser: jede Zahl mit Einheit, mit ihrer Beschriftung und dem,
// was in ihrer Umgebung steht.
const ERNTEN = () => {
  const raus = []
  const text = e => (e?.textContent ?? '').replace(/\s+/g, ' ').trim()
  // Eine Zahl mit Einheit: 12.3 t · 450 kg · 12 % · 6 Stück · 128 Tage
  const ZAHL = /(-?\d[\d'’.,  ]*)\s*(t\b|kg\b|%|Stück\b|Tage\b|Tagen\b)/
  const karteVon = e => e.closest('.karte, .zahlenzeile, details') ?? document.body
  const titelVon = k => text(k.querySelector('.karte-kopf h2, summary, h2, h3')).slice(0, 120)
  // Was ein Mensch zu einer Zahl mitliest, ist die ganze Karte — auch wenn die
  // Zahl in einem aufgeklappten Block darin steht. Die Erklärung „Ausgelagert
  // ist gerechnet" steht oben in der Karte, die Tabelle unten darin.
  const umfeldVon = e => text(e.closest('.karte') ?? karteVon(e)).slice(0, 1800)

  // 1. Kennzahlen und Zahlenzeilen: Titel steht daneben
  for (const e of document.querySelectorAll('.kennzahl, .zahlenzeile > div')) {
    const wert = text(e.querySelector('.gross-zahl, .wert'))
    if (!ZAHL.test(wert)) continue
    raus.push({ art: 'kennzahl', beschriftung: text(e.querySelector('.titel')),
                wert, unter: text(e.querySelector('.unter')),
                karte: titelVon(karteVon(e)), karteText: umfeldVon(e) })
  }
  // 2. Tabellenzellen. Ein Mensch liest eine Zelle über zwei Wege: den
  //    Spaltenkopf und die erste Zelle ihrer Zeile. Bei einer Matrix
  //    (Kaliberklassen mal Kennzahl) sagt erst beides zusammen, was dasteht;
  //    bei einer Merkmal-Wert-Tabelle ohne Kopfzeile sagt es die Zeile allein.
  //    Zellen, in denen eine ganze Tabelle steckt (die aufgeklappte Charge),
  //    sind Behälter, keine Zahlen — die Zahlen darin werden für sich geerntet.
  for (const tab of document.querySelectorAll('table')) {
    const koepfe = [...tab.querySelectorAll('thead th, tr:first-child th')].map(text)
    // Eine Liste (mit thead) beschriftet ihre Zahlen über die Spalte: jede
    // Zeile ist ein Ding, die Spalte sagt, welche Grösse. Eine kleine Matrix
    // ohne thead (Kennzahl mal Klasse) beschriftet über beides — der Mensch
    // liest „Gewogene Masse, zu klein". Genau so wird geerntet.
    const matrix = !tab.querySelector('thead')
    for (const zeile of tab.querySelectorAll('tbody tr, tr')) {
      const zellen = [...zeile.children]
      const erste = text(zellen[0])
      const zeilenkopf = zellen.length > 1 && erste && !ZAHL.test(erste) && erste.length <= 60 ? erste : ''
      zellen.forEach((z, i) => {
        if (z.querySelector('table')) return
        const w = text(z)
        if (!ZAHL.test(w) || w.length > 160) return
        const kopf = (koepfe[i] ?? '').trim()
        // Normalfall: der Spaltenkopf benennt die Zahl. Zwei Ausnahmen, in
        // denen ein Mensch die Zeile liest: die Tabelle hat gar keinen Kopf
        // (Merkmal — Wert), oder der Spaltenkopf ist selber ein Wert
        // (Kaliberklasse „600–1100 g") und sagt nur, von welcher Gruppe die
        // Rede ist. Dann steht die Bedeutung links.
        const beschriftung = i === 0 ? kopf
          : !kopf ? zeilenkopf
          : matrix && zeilenkopf && zeilenkopf !== kopf ? `${zeilenkopf} · ${kopf}`
          : kopf
        raus.push({ art: 'tabelle', beschriftung, wert: w, unter: '',
                    karte: titelVon(karteVon(tab)), karteText: umfeldVon(tab) })
      })
    }
  }
  // 3. Begriffslisten (dt/dd) — die Zusammenfassungen und Rechenwege
  for (const dl of document.querySelectorAll('dl')) {
    const kinder = [...dl.children]
    kinder.forEach((k, i) => {
      if (k.tagName !== 'DD') return
      const w = text(k)
      if (!ZAHL.test(w)) return
      const dt = kinder.slice(0, i).reverse().find(x => x.tagName === 'DT')
      raus.push({ art: 'liste', beschriftung: text(dt), wert: w, unter: '',
                  karte: titelVon(karteVon(dl)), karteText: umfeldVon(dl) })
    })
  }
  // 4. Anteilsbalken: die Zeile heisst nach ihrer Gruppe (Sorte, Charge,
  //    „Alle Chargen") — das ist keine Beschriftung einer Masse, sondern
  //    sagt nur, wovon die Rede ist. Die Masse daneben trägt ihr Wort direkt
  //    bei sich („15.8 t Eingang"). Also wird genau dieses Wort geerntet,
  //    nicht der Gruppenname: geprüft wird, was ein Mensch neben der Zahl liest.
  for (const e of document.querySelectorAll('.anteil-zeile')) {
    const gruppe = text(e.querySelector('.anteil-name strong'))
    const karte = titelVon(karteVon(e))
    const karteText = umfeldVon(e)
    for (const teil of text(e.querySelector('.anteil-name .leise')).split('·')) {
      const t = teil.trim()
      if (!ZAHL.test(t)) continue
      // „15.8 t Eingang" → Beschriftung „Eingang"; „4 Chargen" → „Chargen"
      const rest = t.replace(ZAHL, ' ').replace(/\s+/g, ' ').trim()
      const wort = t.match(ZAHL)
      raus.push({ art: 'gruppenzeile', beschriftung: rest || gruppe,
                  wert: `${wort[1].trim()} ${wort[2]}`, unter: gruppe, karte, karteText })
    }
    const anteil = text(e.querySelector('.anteil-wert'))
    if (ZAHL.test(anteil))
      raus.push({ art: 'gruppenzeile', beschriftung: gruppe, wert: anteil, unter: '', karte, karteText })
  }
  // 4b. Bilanzzeilen: eigene Beschriftung im Baustein
  for (const e of document.querySelectorAll('.bilanzzeile')) {
    const w = text(e)
    if (!ZAHL.test(w)) continue
    raus.push({ art: 'balken', beschriftung: text(e.querySelector('.titel, .name, strong')),
                wert: w, unter: '', karte: titelVon(karteVon(e)),
                karteText: umfeldVon(e) })
  }
  // 5. Der ganze sichtbare Text — für die verbotenen Wörter
  return { zahlen: raus, seitentext: text(document.body) }
}

/* ---------- Die Regeln ---------------------------------------------------- */
const ZUSATZ = ['bis heute', 'bis ', 'echter', 'kein echter', 'erwartet', 'erwartung',
                'prognose', 'in 14 tagen', 'nächste', 'je ', 'davon', 'seit']
const BEZUG = ['von ', 'des eingangs', 'vom eingang', 'je ', 'anteil', 'der ware', 'aller',
               'des lagers', 'im lager', 'im haus', 'gemessen an', 'bezogen auf', 'am eingang',
               '100 %', 'des bestands']
const VERBOTEN = [
  ['Buch A', 'Modellsprache — der Betriebsleiter liest „echter Verlust"'],
  ['Buch B', 'Modellsprache — der Betriebsleiter liest „kein echter Verlust"'],
  ['NaN', 'kaputte Zahl'],
  ['undefined', 'kaputte Zahl'],
  ['Infinity', 'kaputte Zahl'],
  ['[object', 'kaputtes Objekt im Text'],
]
const norm = t => (t ?? '').toLowerCase().replace(/\s+/g, ' ').trim()
const istMasse = w => /\b(t|kg)\b/.test(w)
const istProzent = w => /%/.test(w)

function pruefen(seite, ernte) {
  const fehler = []
  const melde = (regel, was, wo) => fehler.push({ seite: seite.name, regel, was, wo })

  for (const z of ernte.zahlen) {
    const b = norm(z.beschriftung)
    const umfeld = norm(`${z.beschriftung} ${z.unter} ${z.karte} ${z.karteText}`)

    // R1 — überhaupt beschriftet
    if (b === '') { melde('R1 ohne Beschriftung', z.wert, z.karte || seite.pfad); continue }

    if (istMasse(z.wert)) {
      // R2 — im Lexikon
      // Der längste passende Begriff gewinnt: „Gewogene Masse · zu klein"
      // ist eine gewogene Masse, kein hochgerechneter Kanal. Wer nur den
      // ersten Treffer nimmt, hängt der Zahl die falsche Herkunft an.
      let eintrag = null, laenge = -1
      for (const e of LEXIKON.begriffe)
        for (const m of e.muster) {
          const n = norm(m)
          if (b.includes(n) && n.length > laenge) { eintrag = e; laenge = n.length }
        }
      if (!eintrag) melde('R2 unbekannter Begriff', `„${z.beschriftung}" → ${z.wert}`, z.karte)

      // R3 — „Verlust" nie nackt
      if (b.includes('verlust') && !ZUSATZ.some(x => b.includes(x)) && !ZUSATZ.some(x => norm(z.unter).includes(x)))
        melde('R3 Verlust ohne Zusatz', `„${z.beschriftung}" → ${z.wert}`, z.karte)

      // R4 — gerechnete Masse mit Herkunft. Wo ein Begriff nur eine Herkunft
      // haben kann, muss genau diese dastehen; wo er beides sein kann
      // („Verdunstet" ist im Bilanzblock gerechnet, in der Wägungstabelle
      // gewogen), muss die Karte sagen, welche von beiden hier gilt.
      if (eintrag && eintrag.art !== 'gemessen') {
        const erlaubt = eintrag.art.split('|')
        const genannt = ['gemessen', 'gerechnet', 'prognose'].filter(a => umfeld.includes(a))
        if (!genannt.some(a => erlaubt.includes(a)))
          melde('R4 gerechnet ohne Herkunft',
                `„${z.beschriftung}" → ${z.wert} — die Karte müsste ${erlaubt.join(' oder ')} sagen`
                + (genannt.length ? `, sagt aber ${genannt.join('/')}` : ''), z.karte)
      }
    }

    // R5 — Prozent mit Bezug
    if (istProzent(z.wert) && !BEZUG.some(x => umfeld.includes(x)))
      melde('R5 Prozent ohne Bezug', `„${z.beschriftung}" → ${z.wert}`, z.karte)
  }

  // R6 — verbotene Wörter, mit dem Satz drumherum: ohne Fundstelle kann
  // niemand etwas reparieren.
  for (const [wort, grund] of VERBOTEN) {
    const i = ernte.seitentext.indexOf(wort)
    if (i < 0) continue
    const stelle = ernte.seitentext.slice(Math.max(0, i - 90), i + wort.length + 50).trim()
    melde('R6 verbotenes Wort', `„${wort}" — ${grund}: …${stelle}…`, seite.name)
  }
  if (/^\/(dashboard|ursachen|chargen)/.test(seite.pfad) && /Käufer/.test(ernte.seitentext))
    melde('R6 verbotenes Wort', '„Käufer" — seit 0060 keine Grösse der Auswertung', seite.name)

  return fehler
}

/* ---------- Die Gegenprobe: stimmen die Kopfzahlen? ---------------------- */
// Unabhängig aus den Fixtures gerechnet — dieselben Zeilen, die die App bekommt.
function sollzahlen() {
  const bilanz = (fixture('erg_bilanz') ?? [])[0]
  if (!bilanz) return null
  const z = x => Number(x ?? 0)
  return {
    eingang: z(bilanz.eingang_kg),
    geliefert: z(bilanz.geliefert_kg),
    verlust: z(bilanz.verlust_heute_kg),
    imHaus: z(bilanz.im_haus_heute_kg),
  }
}
const tonnen = kg => `${(Math.round(kg / 100) / 10).toLocaleString('de-CH')} t`

/* ---------- Ablauf -------------------------------------------------------- */
const vite = await createServer({ root: join(HIER, '..'), server: { port: 5197, strictPort: true }, logLevel: 'silent' })
await vite.listen()
const browser = await chromium.launch({ executablePath: CHROMIUM })

const alleFehler = []
const alleBegriffe = new Map()   // Beschriftung → Beispielwert (für ERNTE=1)

for (const seite of SEITEN) {
  if (NUR && !seite.name.includes(NUR)) continue
  const kontext = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'de-CH' })
  const blatt = await kontext.newPage()
  vergessen()
  const konsole = []
  blatt.on('console', m => { if (m.type() === 'error') konsole.push(m.text()) })
  blatt.on('pageerror', f => konsole.push(String(f)))
  await blatt.route('**/rest/v1/**', r => restAntwort(r).catch(() => r.abort()))
  await blatt.route('**/auth/v1/**', r => authAntwort(r, 'admin').catch(() => r.abort()))
  await blatt.route('**/storage/v1/**', r => r.fulfill({ json: {} }))
  await blatt.addInitScript(() => {
    localStorage.setItem('sprache', 'de')
    localStorage.setItem('sprache_tag', new Date().toISOString().slice(0, 10))
    localStorage.setItem('pruefstand_wer', 'admin')
  })

  await blatt.goto(`http://localhost:5197${seite.pfad}`, { waitUntil: 'networkidle' })
  // Anmelden, falls der Login-Schirm steht — die Auswertung sieht nur der Betriebsleiter
  const login = blatt.getByRole('button', { name: 'Betriebsleiter' })
  if (await login.isVisible().catch(() => false)) {
    await login.click()
    await blatt.getByLabel('E-Mail').fill('chef@hof.test')
    await blatt.getByLabel('Passwort').fill('pruefstand')
    await blatt.getByRole('button', { name: 'Anmelden', exact: true }).click()
    await blatt.waitForLoadState('networkidle')
    await blatt.goto(`http://localhost:5197${seite.pfad}`, { waitUntil: 'networkidle' })
  }
  await blatt.waitForTimeout(900)
  try { await seite.tun?.(blatt) } catch (f) { konsole.push(`Klickweg: ${f}`) }
  await blatt.waitForTimeout(300)

  const ernte = await blatt.evaluate(ERNTEN)
  for (const z of ernte.zahlen) if (istMasse(z.wert) && z.beschriftung)
    alleBegriffe.set(z.beschriftung.trim(), `${z.art}\t${z.karte || '—'}\t${z.wert} · ${seite.name}`)

  const fehler = pruefen(seite, ernte)
  for (const k of konsole) fehler.push({ seite: seite.name, regel: 'Konsole', was: k, wo: seite.pfad })
  alleFehler.push(...fehler)
  console.log(`  ${fehler.length ? '✗' : '✓'} ${seite.name}: ${ernte.zahlen.length} Zahlen geerntet${fehler.length ? `, ${fehler.length} Beanstandungen` : ''}`)

  // Die Gegenprobe nur dort, wo die Kopfzahlen stehen
  if (seite.name === 'ueberblick') {
    const soll = sollzahlen()
    if (soll) {
      const kopf = ernte.zahlen.filter(z => z.art === 'kennzahl')
      for (const [titelTeil, wert] of [['eingang', soll.eingang], ['ausgeliefert', soll.geliefert],
                                       ['verlust', soll.verlust], ['im haus', soll.imHaus]]) {
        const gefunden = kopf.find(z => norm(z.beschriftung).includes(titelTeil))
        if (!gefunden) { alleFehler.push({ seite: seite.name, regel: 'Gegenprobe', was: `Kopfzahl „${titelTeil}" fehlt`, wo: 'Überblick' }); continue }
        const erwartet = tonnen(wert)
        if (!gefunden.wert.includes(erwartet.replace(' t', ''))) {
          alleFehler.push({ seite: seite.name, regel: 'Gegenprobe',
                            was: `„${gefunden.beschriftung}" zeigt ${gefunden.wert}, aus erg_bilanz folgt ${erwartet}`, wo: 'Überblick' })
        }
      }
    }
  }
  await kontext.close()
}

await browser.close(); await vite.close()

if (ERNTE) {
  const liste = [...alleBegriffe.entries()].sort((a, b) => a[0].localeCompare(b[0], 'de'))
  writeFileSync(join(HIER, 'begriffe_gefunden.txt'),
    ['Beschriftung\tHerkunft im Dokument\tKarte\tBeispiel', ...liste.map(([b, w]) => `${b}\t${w}`)].join('\n'))
  console.log(`\nErnte: ${liste.length} verschiedene Beschriftungen an Massezahlen → pruefstand/begriffe_gefunden.txt`)
}

console.log('\n── Begriffs-Prüfstand ─────────────────────────────────────────')
if (alleFehler.length === 0) {
  console.log('  OK  Jede Zahl auf jeder Seite sagt, was sie ist:')
  console.log('      beschriftet, im Lexikon, mit Zusatz beim Verlust, mit Herkunft,')
  console.log('      Prozente mit Bezugsgrösse, keine Modellwörter, Kopfzahlen stimmen.')
  console.log('───────────────────────────────────────────────────────────────')
  process.exit(0)
}
const nachRegel = new Map()
for (const f of alleFehler) nachRegel.set(f.regel, [...(nachRegel.get(f.regel) ?? []), f])
for (const [regel, liste] of [...nachRegel.entries()].sort()) {
  console.log(`\n  ${regel} — ${liste.length}×`)
  for (const f of liste.slice(0, 25)) console.log(`    · ${f.seite}: ${f.was}${f.wo ? `   [${f.wo}]` : ''}`)
  if (liste.length > 25) console.log(`    … und ${liste.length - 25} weitere`)
}
console.log(`\n  ${alleFehler.length} Beanstandungen.`)
console.log('───────────────────────────────────────────────────────────────')
process.exit(1)
