/**
 * Die Abnahme der Runde R — der Vertrag aus docs/PROMPT_RUNDE_R.md § 8 als
 * Prüfstand.
 *
 * Der Betrieb hat gesagt, was die zwei ersten Reiter des Dashboards zeigen
 * sollen und was nicht mehr. Dieser Prüfstand startet die App gegen die
 * Attrappe (dieselben Fixtures wie bildschirme.mjs), meldet sich als
 * Betriebsleiter an, öffnet Lagermanagement und Ursachen — je mit Alle, einer
 * Sorte, einer Charge — und prüft Punkt für Punkt: Ist da, was da sein muss?
 * Ist weg, was weg sein muss? Er druckt eine Liste und endet rot, solange ein
 * Punkt fehlt.
 *
 * Er ist absichtlich **vor** dem Umbau geschrieben (Runde R, Phase 0) und
 * darum heute rot: Das ist die Liste, die die ausführende KI abarbeitet — und
 * der Beweis, dass sie es getan hat. Wer etwas baut, das hier nicht steht,
 * trägt es hier ein; ein Vertrag, der hinter dem Bau zurückbleibt, ist keiner.
 *
 *   node pruefstand/abnahme_r.mjs            # alle Punkte
 *   node pruefstand/abnahme_r.mjs lager      # nur die Punkte, deren Name „lager" enthält
 */
import { chromium } from 'playwright'
import { createServer } from 'vite'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { CHROMIUM, authAntwort, fixture, restAntwort, vergessen } from './attrappe.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))
const NUR = process.argv[2] ?? ''
const PORT = 5197

/* ---------- Der Vertrag ---------------------------------------------------- */
// Jeder Punkt: eine Kennung (L = Lagermanagement, U = Ursachen, N = Navigation),
// ein Satz, und eine Prüfung, die wirft, wenn der Punkt nicht erfüllt ist.
// Die Prüfungen laufen auf allen drei Filterständen (Alle, Sorte, Charge),
// wenn nichts anderes gesagt ist.

const sichtbar = async (p, wahl, was) => {
  if (!(await p.locator(wahl).count())) throw new Error(`${was} fehlt (${wahl})`)
}
const nichtDa = async (p, text, wo) => {
  const n = await p.locator(`text=${text}`).count()
  if (n) throw new Error(`„${text}" steht noch ${n}× auf ${wo}`)
}
const option = async (p, feld, praefix) => {
  const werte = await p.locator(`${feld} option[value^="${praefix}|"]`).evaluateAll(os => os.map(o => o.value))
  return werte
}

const PUNKTE = [
  // ---- Navigation ----------------------------------------------------------
  { id: 'N-01', wo: 'lager', nur: 'gesamt', satz: 'Der Reiter heisst „Lagermanagement", nicht mehr „Überblick"',
    pruefe: async p => {
      await sichtbar(p, 'nav a:has-text("Lagermanagement")', 'Reiter Lagermanagement')
      if (await p.locator('nav a:has-text("Überblick")').count()) throw new Error('„Überblick" ist noch ein Reiter')
    } },
  { id: 'N-02', wo: 'lager', nur: 'gesamt', satz: 'Fünf Reiter: Lagermanagement, Ursachen, Chargen, Messungen, Betrieb',
    pruefe: async p => {
      for (const r of ['Lagermanagement', 'Ursachen', 'Chargen', 'Messungen', 'Betrieb']) await sichtbar(p, `nav a:has-text("${r}")`, `Reiter ${r}`)
    } },

  // ---- Lagermanagement ------------------------------------------------------
  { id: 'L-01', wo: 'lager', nur: 'gesamt', satz: 'Zuoberst der Filter Alle / Sorte / Charge — ohne Schlag',
    pruefe: async p => {
      await sichtbar(p, '#lager-filter', 'Filter')
      if (!(await option(p, '#lager-filter', 'sorte')).length) throw new Error('keine Sorte im Filter')
      if (!(await option(p, '#lager-filter', 'charge')).length) throw new Error('keine Charge im Filter')
      if ((await option(p, '#lager-filter', 'schlag')).length) throw new Error('Schlag steht noch im Filter')
    } },
  { id: 'L-02', wo: 'lager', satz: 'Vier Kennzahlen: Eingang, Ausgang, im Lager, davon verkaufsfähig',
    pruefe: async p => {
      for (const k of ['eingang', 'ausgang', 'lager', 'verkaufsfaehig']) await sichtbar(p, `#kz-${k}`, `Kennzahl ${k}`)
    } },
  { id: 'L-03', wo: 'lager', satz: '„Die Saison im Verlauf" bleibt — mit Heute-Marke, ohne Fax',
    pruefe: async p => {
      await sichtbar(p, '#lager-verlauf', 'Verlaufskarte')
      await nichtDa(p, 'Fax', 'Lagermanagement')
    } },
  { id: 'L-04', wo: 'lager', satz: 'Die Tabelle „Was ist noch im Haus": Zeilen, „verkaufsfähig heute", „in … Wochen"',
    pruefe: async p => {
      await sichtbar(p, '#lager-tabelle', 'Tabelle')
      await sichtbar(p, '#lager-tabelle thead', 'Tabellenkopf')
      if (!(await p.locator('#lager-tabelle tbody tr').count())) throw new Error('keine Zeile in der Tabelle')
      await sichtbar(p, '#lager-tabelle thead :text("verkaufsfähig heute")', 'Spaltengruppe „verkaufsfähig heute"')
      await sichtbar(p, '#lager-tabelle thead :text-matches("in \\\\d+ Wochen")', 'Spaltengruppe „in X Wochen"')
    } },
  { id: 'L-05', wo: 'lager', nur: 'gesamt', satz: 'Das Feld X: nach Eingabe von 8 steht „in 8 Wochen" im Tabellenkopf',
    pruefe: async p => {
      await sichtbar(p, '#lager-wochen', 'Feld X')
      await p.locator('#lager-wochen').fill('8')
      await p.locator('#lager-tabelle thead :text("in 8 Wochen")').waitFor({ timeout: 10000 })
    } },
  { id: 'L-06', wo: 'lager', satz: 'Die Glocke mit „heute" und „in X Wochen"',
    pruefe: async p => {
      await sichtbar(p, '#lager-glocke', 'Glocke')
      await sichtbar(p, '#glocke-heute', 'Knopf heute')
      await sichtbar(p, '#glocke-wochen', 'Feld Wochen')
    } },
  { id: 'L-07', wo: 'lager', satz: 'Nicht mehr auf Lagermanagement: „liegt seit", „gute Ware", „Wohin geht der Kürbis", „Verlust nach Ursache"',
    pruefe: async p => {
      for (const t of ['liegt seit', 'gute Ware', 'Wohin geht der Kürbis', 'Verlust nach Ursache']) await nichtDa(p, t, 'Lagermanagement')
    } },
  { id: 'L-08', wo: 'lager', nur: 'sorte', satz: 'Im Filter „Sorte" stehen die Chargen der Sorte als Zeilen — mit den Gramm der Bänder im Kopf',
    pruefe: async p => {
      if ((await p.locator('#lager-tabelle tbody tr').count()) < 1) throw new Error('keine Chargenzeile')
      await sichtbar(p, '#lager-tabelle thead :text-matches("\\\\d+\\\\s?[–-]\\\\s?\\\\d+ g")', 'Band in Gramm im Kopf')
    } },
  { id: 'L-09', wo: 'lager', nur: 'charge', satz: 'Im Filter „Charge" genau eine Zeile',
    pruefe: async p => {
      const n = await p.locator('#lager-tabelle tbody tr').count()
      if (n !== 1) throw new Error(`${n} Zeilen statt einer`)
    } },

  // ---- Ursachen ------------------------------------------------------------
  { id: 'U-01', wo: 'ursachen', nur: 'gesamt', satz: 'Zuoberst der Filter Alle / Sorte / Charge — ohne Schlag',
    pruefe: async p => {
      await sichtbar(p, '#uf', 'Filter')
      if ((await option(p, '#uf', 'schlag')).length) throw new Error('Schlag steht noch im Filter')
    } },
  { id: 'U-02', wo: 'ursachen', satz: '„Wohin ging der Kürbis": der Balken mit sechs Teilen',
    pruefe: async p => {
      await sichtbar(p, '#urs-wohin', 'Wohin-Karte')
      for (const t of ['verkaufsfähig', 'verkauft', 'verdunstet', 'Faules', 'zu klein', 'zu gross']) {
        if (!(await p.locator(`#urs-wohin :text("${t}")`).count())) throw new Error(`Teil „${t}" fehlt im Balken`)
      }
    } },
  { id: 'U-03', wo: 'ursachen', satz: '„Faules im Lager": Kalender oder liegt seit, die x-Achse wechselt',
    pruefe: async p => {
      await sichtbar(p, '#urs-palox', 'Palox-Karte')
      await sichtbar(p, '#palox-achse-kalender', 'Knopf Kalender')
      await sichtbar(p, '#palox-achse-liegt', 'Knopf liegt seit')
      const vorher = await p.locator('#urs-palox svg').first().innerText().catch(() => '')
      await p.locator('#palox-achse-kalender').click(); await p.waitForTimeout(300)
      const kalender = await p.locator('#urs-palox svg').first().innerText().catch(() => '')
      await p.locator('#palox-achse-liegt').click(); await p.waitForTimeout(300)
      const liegt = await p.locator('#urs-palox svg').first().innerText().catch(() => '')
      if (kalender === liegt) throw new Error('die Achse wechselt nicht')
      void vorher
    } },
  { id: 'U-04', wo: 'ursachen', satz: '„Verdunstung": Kalender oder liegt seit',
    pruefe: async p => {
      await sichtbar(p, '#urs-verdunstung', 'Verdunstungs-Karte')
      await sichtbar(p, '#verd-achse-kalender', 'Knopf Kalender')
      await sichtbar(p, '#verd-achse-liegt', 'Knopf liegt seit')
    } },
  { id: 'U-05', wo: 'ursachen', satz: '„Verschenkte Marge" in zwei Karten: Kiste ab, Stück',
    pruefe: async p => {
      await sichtbar(p, '#urs-marge-kiste', 'Marge Kiste ab')
      await sichtbar(p, '#urs-marge-stueck', 'Marge Stück')
      await nichtDa(p, 'Gewogen, aber nicht verkauft', 'Ursachen')
      await nichtDa(p, 'Überfüllung', 'Ursachen')
    } },
  { id: 'U-06', wo: 'ursachen', satz: 'Keine Prognose auf Ursachen: kein „Prognose", „in 14 Tagen", „Was wird aus der liegenden Ware", „Welche Charge zuerst", „Spielraum", „Fax"',
    pruefe: async p => {
      for (const t of ['Prognose', 'in 14 Tagen', 'Was wird aus der liegenden Ware', 'Welche Charge zuerst', 'Spielraum', 'Fax']) await nichtDa(p, t, 'Ursachen')
    } },
  { id: 'U-07', wo: 'ursachen', satz: 'Die Reihenfolge: Wohin, Faules, Verdunstung, Marge',
    pruefe: async p => {
      const y = async id => (await p.locator(`#${id}`).boundingBox())?.y ?? Infinity
      const ys = [await y('urs-wohin'), await y('urs-palox'), await y('urs-verdunstung'), await y('urs-marge-kiste')]
      for (let i = 1; i < ys.length; i++) if (!(ys[i] > ys[i - 1])) throw new Error(`Block ${i} steht nicht unter Block ${i - 1}`)
    } },

  // ---- Beide ---------------------------------------------------------------
  { id: 'B-01', wo: 'lager', satz: 'Keine Konsolenfehler auf Lagermanagement', pruefe: async (p, meldungen) => {
      if (meldungen.length) throw new Error(meldungen[0].slice(0, 160))
    } },
  { id: 'B-02', wo: 'ursachen', satz: 'Keine Konsolenfehler auf Ursachen', pruefe: async (p, meldungen) => {
      if (meldungen.length) throw new Error(meldungen[0].slice(0, 160))
    } },

  // ---- Design (docs/DESIGN_RUNDE_R.md § 6) -----------------------------------
  { id: 'D-01', wo: 'lager', nur: 'gesamt', satz: 'Jede Karte trägt eine Herkunftsmarke — oder ist eine Leer-Karte', pruefe: ohneHerkunft },
  { id: 'D-01', wo: 'ursachen', nur: 'gesamt', satz: 'Jede Karte trägt eine Herkunftsmarke — oder ist eine Leer-Karte', pruefe: ohneHerkunft },
  { id: 'D-02', wo: 'lager', nur: 'gesamt', satz: 'Die vier Kennzahlen sind Kennzahl-Kacheln (.kennzahl mit .gross-zahl und .unter)',
    pruefe: async p => {
      for (const k of ['eingang', 'ausgang', 'lager', 'verkaufsfaehig']) {
        if (!(await p.locator(`#kz-${k}.kennzahl .gross-zahl`).count())) throw new Error(`#kz-${k} ist keine Kennzahl-Kachel mit grosser Zahl`)
        if (!(await p.locator(`#kz-${k}.kennzahl .unter`).count())) throw new Error(`#kz-${k} hat keinen Untertitel`)
      }
    } },
  { id: 'D-03', wo: 'ursachen', nur: 'gesamt', satz: 'Die Achsen-Umschalter sind Segmente (role=tablist mit button[role=tab])',
    pruefe: async p => {
      for (const id of ['palox-achse-kalender', 'palox-achse-liegt', 'verd-achse-kalender', 'verd-achse-liegt']) {
        if (!(await p.locator(`.umschalter[role="tablist"] > button[role="tab"]#${id}`).count())) throw new Error(`#${id} ist kein Segmente-Knopf`)
      }
    } },
  { id: 'D-04', wo: 'lager', nur: 'gesamt', satz: 'Die Tabelle hat zwei Kopfzeilen mit Gruppen (th[colspan]) und eine haftende erste Spalte',
    pruefe: async p => {
      if ((await p.locator('#lager-tabelle thead tr').count()) !== 2) throw new Error('nicht zwei Kopfzeilen')
      if (!(await p.locator('#lager-tabelle thead tr:first-child th[colspan]').count())) throw new Error('keine Spaltengruppe (th[colspan]) in der ersten Kopfzeile')
      const pos = await p.locator('#lager-tabelle tbody tr:first-child td:first-child, #lager-tabelle tbody tr:first-child th:first-child').first().evaluate(el => getComputedStyle(el).position)
      if (pos !== 'sticky') throw new Error(`erste Spalte ist ${pos}, nicht sticky`)
    } },
  { id: 'D-05', wo: 'lager', nur: 'gesamt', satz: 'Liniendiagramme tragen data-x-einheit und eine Legende', pruefe: async p => await diagrammVertrag(p, ['#lager-verlauf']) },
  { id: 'D-05', wo: 'ursachen', nur: 'gesamt', satz: 'Liniendiagramme tragen data-x-einheit und eine Legende', pruefe: async p => await diagrammVertrag(p, ['#urs-palox', '#urs-verdunstung']) },
  { id: 'D-06', wo: 'lager', nur: 'gesamt', satz: 'Keine Inline-Farben oder -Schriftgrössen in den Karten', pruefe: inlineStile },
  { id: 'D-06', wo: 'ursachen', nur: 'gesamt', satz: 'Keine Inline-Farben oder -Schriftgrössen in den Karten', pruefe: inlineStile },
  { id: 'D-07', wo: 'lager', nur: 'gesamt', breite: 390, satz: 'Auf 390 px scrollt die Seite nicht waagrecht', pruefe: keinUeberlauf },
  { id: 'D-07', wo: 'ursachen', nur: 'gesamt', breite: 390, satz: 'Auf 390 px scrollt die Seite nicht waagrecht', pruefe: keinUeberlauf },
  { id: 'D-08', wo: 'lager', nur: 'gesamt', thema: 'dark', satz: 'Das dunkle Thema rendert ohne Konsolenfehler', pruefe: async (p, meldungen) => {
      if (meldungen.length) throw new Error(meldungen[0].slice(0, 160))
    } },
  { id: 'D-08', wo: 'ursachen', nur: 'gesamt', thema: 'dark', satz: 'Das dunkle Thema rendert ohne Konsolenfehler', pruefe: async (p, meldungen) => {
      if (meldungen.length) throw new Error(meldungen[0].slice(0, 160))
    } },
]

async function ohneHerkunft(p) {
  const karten = await p.locator('main .karte, .inhalt .karte, .karte').evaluateAll(els => els
    .filter(el => !el.closest('.filterleiste'))
    .map(el => ({ titel: el.querySelector('h2')?.textContent?.trim() ?? '(ohne Titel)',
                  herkunft: !!el.querySelector('.herkunft'), leer: !!el.querySelector('.leer') })))
  const fehlt = karten.filter(k => !k.herkunft && !k.leer).map(k => k.titel)
  if (fehlt.length) throw new Error(`ohne Herkunftsmarke: ${fehlt.join(' · ')}`)
}
async function diagrammVertrag(p, karten) {
  for (const k of karten) {
    if (!(await p.locator(`${k} svg[data-x-einheit]`).count())) throw new Error(`${k}: kein SVG mit data-x-einheit`)
    if (!(await p.locator(`${k} .legende`).count())) throw new Error(`${k}: keine Legende`)
  }
}
async function inlineStile(p) {
  const n = await p.locator('.karte [style*="color"], .karte [style*="font-size"], .kennzahl [style*="color"], .kennzahl [style*="font-size"]').count()
  if (n) throw new Error(`${n} Elemente mit Inline-Farbe oder -Schriftgrösse`)
}
async function keinUeberlauf(p) {
  const b = await p.evaluate(() => ({ scroll: document.documentElement.scrollWidth, sicht: document.documentElement.clientWidth }))
  if (b.scroll > b.sicht + 1) throw new Error(`Seite ist ${b.scroll} px breit bei ${b.sicht} px Sicht`)
}

/* ---------- Ablauf --------------------------------------------------------- */
const vite = await createServer({ root: join(HIER, '..'), server: { port: PORT, strictPort: true }, logLevel: 'silent' })
await vite.listen()
const browser = await chromium.launch({ executablePath: CHROMIUM })

// Eine Sorte und eine Charge mit Ware im Haus, aus den Fixtures.
const bestand = (fixture('erg_charge') ?? []).filter(b => Number(b.lager_kg) > 0)
const SORTE = bestand[0]?.sorte ?? (fixture('erg_charge') ?? [])[0]?.sorte ?? ''
const CHARGE = bestand[0]?.charge_nr ?? (fixture('erg_charge') ?? [])[0]?.charge_nr ?? ''
const FILTER = [
  { name: 'gesamt', lager: '/dashboard', ursachen: '/ursachen' },
  { name: 'sorte', lager: `/dashboard?sorte=${encodeURIComponent(SORTE)}`, ursachen: `/ursachen?sorte=${encodeURIComponent(SORTE)}` },
  { name: 'charge', lager: `/dashboard?charge=${CHARGE}`, ursachen: `/ursachen?charge=${CHARGE}` },
]

async function seiteOeffnen(pfad, breite = 1280, thema = 'light') {
  const kontext = await browser.newContext({ viewport: { width: breite, height: 900 }, colorScheme: thema, locale: 'de-CH' })
  const seite = await kontext.newPage()
  vergessen()
  const meldungen = []
  seite.on('console', m => { if (m.type() === 'error') meldungen.push(m.text()) })
  seite.on('pageerror', f => meldungen.push(String(f)))
  await seite.route('**/rest/v1/**', r => restAntwort(r).catch(() => r.abort()))
  await seite.route('**/auth/v1/**', r => authAntwort(r, 'admin').catch(() => r.abort()))
  await seite.route('**/storage/v1/**', r => r.fulfill({ json: {} }))
  await seite.addInitScript(() => {
    localStorage.setItem('sprache', 'de')
    localStorage.setItem('sprache_tag', new Date().toISOString().slice(0, 10))
    localStorage.setItem('pruefstand_wer', 'admin')
  })
  await seite.goto(`http://localhost:${PORT}${pfad}`, { waitUntil: 'networkidle' })
  const login = seite.getByRole('button', { name: 'Betriebsleiter' })
  if (await login.isVisible().catch(() => false)) {
    await login.click()
    await seite.getByLabel('E-Mail').fill('chef@hof.test')
    await seite.getByLabel('Passwort').fill('pruefstand')
    await seite.getByRole('button', { name: 'Anmelden', exact: true }).click()
    await seite.waitForLoadState('networkidle')
    await seite.goto(`http://localhost:${PORT}${pfad}`, { waitUntil: 'networkidle' })
  }
  await seite.waitForLoadState('networkidle').catch(() => {})
  await seite.waitForTimeout(800)
  return { seite, kontext, meldungen }
}

const ergebnis = []
// Je Filter, Reiter, Breite und Thema eine Seite: die Designpunkte D-07 (390 px)
// und D-08 (dunkel) brauchen eigene Fenster, alle anderen teilen sich eins.
const FENSTER = [...new Set(PUNKTE.map(x => `${x.breite ?? 1280}|${x.thema ?? 'light'}`))].map(k => {
  const [b, t] = k.split('|'); return { breite: Number(b), thema: t }
})
for (const f of FILTER) {
  for (const wo of ['lager', 'ursachen']) {
    for (const fenster of FENSTER) {
    const punkte = PUNKTE.filter(x => x.wo === wo && (!x.nur || x.nur === f.name)
      && (x.breite ?? 1280) === fenster.breite && (x.thema ?? 'light') === fenster.thema
      && (!NUR || x.id.toLowerCase().includes(NUR) || x.satz.toLowerCase().includes(NUR)))
    if (!punkte.length) continue
    const { seite, kontext, meldungen } = await seiteOeffnen(f[wo], fenster.breite, fenster.thema)
    for (const punkt of punkte) {
      try {
        await punkt.pruefe(seite, meldungen)
        ergebnis.push({ ...punkt, filter: f.name, ok: true })
      } catch (fehler) {
        ergebnis.push({ ...punkt, filter: f.name, ok: false, befund: String(fehler.message ?? fehler).split('\n')[0] })
      }
    }
    await kontext.close()
    }
  }
}
await browser.close()
await vite.close()

/* ---------- Die Liste ------------------------------------------------------ */
const rot = ergebnis.filter(e => !e.ok)
console.log('\nAbnahme Runde R — der Vertrag aus docs/PROMPT_RUNDE_R.md § 8\n')
for (const e of ergebnis) {
  const fenster = e.breite || e.thema ? ` [${e.breite ?? 1280} px${e.thema === 'dark' ? ', dunkel' : ''}]` : ''
  console.log(`  ${e.ok ? '✓' : '✗'} ${e.id}  ${e.wo.padEnd(8)} ${e.filter.padEnd(6)} ${e.satz}${fenster}${e.ok ? '' : `\n        → ${e.befund}`}`)
}
console.log(`\n${ergebnis.length - rot.length} von ${ergebnis.length} Punkten erfüllt${rot.length ? ` — ${rot.length} offen` : ' — die Runde ist abgenommen'}.`)
process.exit(rot.length ? 1 : 0)
