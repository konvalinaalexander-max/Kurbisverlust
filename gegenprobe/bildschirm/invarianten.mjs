/**
 * Der Bildschirm-Prüfstand der Gegenprobe: Er schaut nicht, ob eine Seite
 * „gut aussieht" — er misst Regeln, die auf **jeder** Seite gelten, und die
 * ein Screenshot-Vergleich nie findet, weil das Bild vom Betrieb nie im
 * Vergleich lag.
 *
 * Die Regeln (I1–I11):
 *   I1  Kein NaN, undefined, Infinity, null oder „—%" als Text auf der Seite.
 *   I2  Kein waagrechtes Rollen der Seite (scrollWidth ≤ innerWidth).
 *   I3  Jedes Diagramm: mindestens zwei Achsenstriche, gleichmässig, jede
 *       Beschriftung nur einmal (A6 aus achse.ts).
 *   I4  Jedes Diagramm: alle Marker liegen im Zeichenrahmen.
 *   I5  Jedes Diagramm mit Lagertagen: Achse beginnt nicht unter 0; mit
 *       Prozent: endet nicht über 105 (A4).
 *   I6  Jedes Diagramm: kein Alleinherrscher — die Marker füllen mindestens
 *       30 % der Achse, und ohne den äussersten bleibt mehr als ein Drittel (A3, A5).
 *   I7  Kein Text abgeschnitten: kein Element mit overflow hidden, dessen
 *       scrollWidth den clientWidth um mehr als 2 px übersteigt.
 *   I8  Arbeiter-App: jedes Bedienelement ≥ 44 px hoch.
 *   I9  Keine Konsolenfehler, keine unbeantworteten Netzanfragen.
 *   I10 Keine leere Karte (.karte ohne Text und ohne SVG).
 *   I11 Kein Zahlenwert ohne Beschriftung in Reichweite (jede .zahl / .gross-zahl
 *       hat in der Karte ein Titel-Element) — grob; die feine Prüfung ist
 *       pruefstand/beschriftung.mjs.
 *
 * Datenquelle: die Attrappe (pruefstand/attrappe.mjs) mit den JSON-Antworten
 * aus PRUEFSTAND_DATEN — für die böse Saison:
 *   PRUEFSTAND_DATEN=gegenprobe/bildschirm/daten node gegenprobe/bildschirm/invarianten.mjs
 * Ohne die Variable läuft er auf der Demo (pruefstand/daten) und muss dort
 * ebenfalls grün sein — sonst ist die Regel falsch, nicht die Seite.
 *
 * Ergebnis: gegenprobe/bildschirm/befund.json (je Seite, je Regel) und ein
 * Satz je Verstoss auf der Konsole. Exit 1 bei Verstössen — und **Exit 2, wenn
 * keine einzige Seite geprüft wurde**, denn ein leerer Lauf ist kein grüner.
 *
 * STAND: Gerüst. Die Regeln I1, I2, I7, I8, I9, I10 sind fertig. I3–I6 lesen
 * die SVG-Striche über die Beschriftungstexte zurück — und lesen dabei heute
 * auch Legenden, Bezugslinien, Datumsachsen und die „heute"-Marke als Striche:
 * Auf der Demo sind 16 der 19 Verstösse solche Lesefehler. Der Vertrag mit
 * dem Diagramm (Phase 1 in docs/PLAN_RUNDE_N.md) macht daraus Messungen:
 * `data-x-einheit`/`data-y-einheit` am SVG, `class="strich"` an jeder
 * Achsenbeschriftung, `class="marker"` an jedem Datenpunkt. Bis dahin gilt:
 * I3–I6 sind Hinweise, I1/I2/I7–I10 sind Befunde.
 */
import { chromium } from 'playwright'
import { createServer } from 'vite'
import { writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { pruefeAchse } from './achse.ts'

const HIER = dirname(fileURLToPath(import.meta.url))
const WURZEL = join(HIER, '..', '..')
if (process.env.PRUEFSTAND_DATEN && !process.env.PRUEFSTAND_DATEN.startsWith('/')) {
  process.env.PRUEFSTAND_DATEN = join(WURZEL, process.env.PRUEFSTAND_DATEN)
}
const { CHROMIUM, authAntwort, restAntwort, vergessen, fehlendeFixtures } = await import(pathToFileURL(join(WURZEL, 'pruefstand', 'attrappe.mjs')).href)

/* ---------- Die Seiten ------------------------------------------------------ */
// Betriebsleiter-Seiten mit allen Diagrammen; Arbeiter-Seiten für I8.
const SEITEN = [
  { name: 'ueberblick', wer: 'admin', pfad: '/dashboard' },
  { name: 'ursachen', wer: 'admin', pfad: '/ursachen' },
  { name: 'chargen', wer: 'admin', pfad: '/chargen' },
  { name: 'messungen', wer: 'admin', pfad: '/messungen' },
  { name: 'betrieb', wer: 'admin', pfad: '/betrieb' },
  { name: 'betrieb-arbeiten', wer: 'admin', pfad: '/betrieb/arbeiten' },
  { name: 'start', wer: 'arbeiter', pfad: '/', arbeiter: true },
  { name: 'neu', wer: 'arbeiter', pfad: '/neu', arbeiter: true },
  { name: 'kontrolle', wer: 'arbeiter', pfad: '/kontrolle', arbeiter: true },
]
const BREITEN = [{ name: 'handy', b: 390, h: 844, mobil: true }, { name: 'rechner', b: 1280, h: 900, mobil: false }]

/* ---------- Was im Browser gemessen wird ---------------------------------- */
const IM_BROWSER = () => {
  const text = document.body.innerText
  // „null" ist auf Deutsch ein Wort („Lagerdauer null") — als Fehler zählt es nur
  // als ganzer Inhalt einer Zelle oder Kennzahl, wo eine Zahl stehen müsste.
  const schlecht = text.match(/\bNaN\b|\bundefined\b|\bInfinity\b|∞|—\s?%|NaN\s?%/g) ?? []
  for (const z of document.querySelectorAll('td, .zahl, .gross-zahl, .kennzahl-wert')) {
    if (/^(null|undefined|NaN)$/.test(z.textContent.trim())) schlecht.push(`Zelle „${z.textContent.trim()}"`)
  }
  const rollen = document.documentElement.scrollWidth - window.innerWidth
  const abgeschnitten = [...document.querySelectorAll('*')].filter(e => {
    const s = getComputedStyle(e)
    return (s.overflow === 'hidden' || s.textOverflow === 'ellipsis') && e.scrollWidth > e.clientWidth + 2 && e.textContent.trim().length > 0
  }).map(e => `${e.tagName.toLowerCase()}.${[...e.classList].join('.')}: „${e.textContent.trim().slice(0, 40)}"`)
  const klein = [...document.querySelectorAll('button, a[href], input, select, [role=button]')].filter(e => {
    const r = e.getBoundingClientRect()
    return r.width > 0 && r.height > 0 && r.height < 44 && !e.closest('.kopf') && !e.closest('.navleiste') && !e.closest('.legende')
  }).map(e => `${e.tagName.toLowerCase()} „${(e.textContent || e.getAttribute('aria-label') || '').trim().slice(0, 30)}" ${Math.round(e.getBoundingClientRect().height)} px`)
  const leereKarten = [...document.querySelectorAll('.karte')].filter(k => k.textContent.trim().length === 0 && !k.querySelector('svg')).length
  // Diagramme: Striche und Marker zurücklesen. Striche = <text> unter dem Rahmen (y-Achse links, x-Achse unten).
  // Nur die Diagramm-SVGs selbst (Vertrag: data-x-einheit) — nicht die Zeichen
  // in den Werkzeugknöpfen darunter, die auch in .diagramm stehen.
  const diagramme = [...document.querySelectorAll('.diagramm svg[data-x-einheit]')].map(svg => {
    const vb = svg.getAttribute('viewBox').split(' ').map(Number)
    const B = vb[2], H = vb[3]
    // Die App schreibt das typografische Minus (U+2212): „−1000" — für die Rechnung ein Bindestrich.
    const texte = [...svg.querySelectorAll('text')].map(t => ({ el: t, x: Number(t.getAttribute('x')), y: Number(t.getAttribute('y')), s: t.textContent.trim().replace(/\u2212/g, '-') }))
    const istZahl = s => /^-?[\d.,’']+\s*[a-zA-Z%]*$/.test(s)
    // Striche erkennt man am Anker (Diagramm.tsx): x-Striche stehen mittig unter
    // dem Rahmen, y-Striche rechtsbündig links davon. Bezugslinien, Kalibergrenzen
    // und Titel haben andere Anker oder andere Orte.
    const anker = t => t.el.getAttribute('text-anchor') ?? t.el.getAttribute('textAnchor') ?? ''
    const xStriche = texte.filter(t => anker(t) === 'middle' && t.y > H - 40 && istZahl(t.s))
    const yStriche = texte.filter(t => anker(t) === 'end' && t.x < 60 && istZahl(t.s))
    const zahl = s => Number(s.replace(/[’']/g, '').replace(',', '.').replace(/[^\d.-]/g, ''))
    const marker = [...svg.querySelectorAll('circle')].filter(c => Number(c.getAttribute('r')) <= 4.5).map(c => ({ cx: Number(c.getAttribute('cx')), cy: Number(c.getAttribute('cy')) }))
    const titel = svg.closest('.karte')?.querySelector('h2, h3')?.textContent.trim() ?? '?'
    const achsentitel = texte.filter(t => !istZahl(t.s)).map(t => t.s)
    return { titel, B, H, xStriche: xStriche.map(t => ({ px: t.x, wert: zahl(t.s), text: t.s })), yStriche: yStriche.map(t => ({ px: t.y, wert: zahl(t.s), text: t.s })), marker, achsentitel }
  })
  return { schlecht, rollen, abgeschnitten, klein, leereKarten, diagramme }
}

/**
 * Aus Strichen und Markern die Achse im Datenraum rekonstruieren (linear) und
 * A1, A3–A6 prüfen. A2 (Punkt ausserhalb) wird in Pixeln gegen den Rahmen
 * geprüft, nicht gegen die Striche: der erste Strich liegt oft rechts vom
 * Achsenanfang (Diagramm.tsx filtert Striche auf den Bereich), und der Rahmen
 * ist, was der Betrachter sieht. Eine Achse, deren Beschriftungen nicht
 * monoton lesbar sind (Datum „1.9." „1.10."), wird übersprungen und als
 * Hinweis gezählt — bis das Diagramm seine Einheit selbst nennt (Phase 1).
 */
const L = 56, R = 16, U = 36
function achsenPruefen(d) {
  const befunde = [], hinweise = []
  const draussen = d.marker.filter(m => m.cx < L - 0.5 || m.cx > d.B - R + 0.5 || m.cy < -0.5 || m.cy > d.H - U + 0.5)
  if (draussen.length) befunde.push({ regel: 'I4', text: `${d.titel}: ${draussen.length} Marker ausserhalb des Rahmens` })
  for (const [name, striche, px, richtung] of [['x', d.xStriche, m => m.cx, 1], ['y', d.yStriche, m => m.cy, -1]]) {
    if (striche.length < 2) { befunde.push({ regel: 'I3', text: `${d.titel}: ${name}-Achse hat ${striche.length} Strich(e)` }); continue }
    const geordnet = [...striche].sort((p, q) => p.px - q.px)
    const monoton = geordnet.every((s, i) => i === 0 || Math.sign(s.wert - geordnet[i - 1].wert) === richtung)
    if (!monoton || geordnet.some(s => !Number.isFinite(s.wert))) { hinweise.push(`${d.titel} (${name}): Beschriftungen nicht als Zahlen lesbar (${geordnet.map(s => s.text).join(' ')}) — Datum?`); continue }
    const a = geordnet[0], b = geordnet[geordnet.length - 1]
    if (a.px === b.px) continue
    const wertVonPx = p => a.wert + (p - a.px) * (b.wert - a.wert) / (b.px - a.px)
    const werte = d.marker.map(m => wertVonPx(px(m)))
    const titel = d.achsentitel.join(' ')
    const einheit = name === 'x' && /lagertage|\btage\b/i.test(titel) ? 'tage'
                  : /%/.test(striche[0].text) ? 'prozent' : 'frei'
    const achse = { von: Math.min(a.wert, b.wert), bis: Math.max(a.wert, b.wert), ticks: geordnet.map(s => s.wert).sort((p, q) => p - q) }
    for (const f of pruefeAchse(achse, werte, { einheit, format: s => String(s), mindestFuellung: 0.3 })) {
      if (f.regel === 'A2') continue   // in Pixeln oben geprüft
      const regel = { A1: 'I3', A3: 'I6', A4: 'I5', A5: 'I6', A6: 'I3' }[f.regel]
      befunde.push({ regel, text: `${d.titel} (${name}): ${f.text}` })
    }
  }
  return { befunde, hinweise }
}

/* ---------- Lauf ------------------------------------------------------------ */
const vite = await createServer({ root: WURZEL, server: { port: 5198, strictPort: true }, logLevel: 'silent' })
await vite.listen()
// Die Arbeiter-Masken nennen Knöpfe über ihren Text-Schlüssel (wie bildschirme.mjs).
const { WOERTERBUCH } = await vite.ssrLoadModule('/src/lib/i18n.ts')
const T = id => WOERTERBUCH?.de?.[id] ?? WOERTERBUCH?.[id]?.de ?? id
const browser = await chromium.launch({ executablePath: CHROMIUM })
const befund = []
let geprueft = 0

for (const breite of BREITEN) {
  const ctx = await browser.newContext({ viewport: { width: breite.b, height: breite.h }, isMobile: breite.mobil, hasTouch: breite.mobil, deviceScaleFactor: 1, locale: 'de-CH' })
  for (const seite of SEITEN) {
    if (seite.arbeiter && !breite.mobil) continue
    if (!seite.arbeiter && breite.mobil) continue
    vergessen()
    const blatt = await ctx.newPage()
    const konsole = []
    blatt.on('console', m => { if (m.type() === 'error') konsole.push(m.text().slice(0, 160)) })
    blatt.on('pageerror', e => konsole.push(String(e).slice(0, 160)))
    await blatt.route(/\/auth\/v1\//, r => authAntwort(r, seite.wer))
    await blatt.route(/\/rest\/v1\//, r => restAntwort(r))
    await blatt.addInitScript(({ wer }) => {
      localStorage.setItem('sprache', 'de')
      localStorage.setItem('sprache_tag', new Date().toISOString().slice(0, 10))
      localStorage.setItem('pruefstand_wer', wer)
    }, { wer: seite.wer })
    const url = `http://localhost:5198${seite.pfad}`
    await blatt.goto(url, { waitUntil: 'networkidle' })
    // Anmelden, falls der Login-Schirm steht — derselbe Weg wie pruefstand/bildschirme.mjs
    if (seite.wer === 'admin') {
      const login = blatt.getByRole('button', { name: 'Betriebsleiter' })
      if (await login.isVisible().catch(() => false)) {
        await login.click()
        await blatt.getByLabel('E-Mail').fill('chef@hof.test')
        await blatt.getByLabel('Passwort').fill('pruefstand')
        await blatt.getByRole('button', { name: 'Anmelden', exact: true }).click()
        await blatt.waitForLoadState('networkidle')
        await blatt.goto(url, { waitUntil: 'networkidle' })
      }
    } else {
      const feld = blatt.getByLabel(T('deinName'))
      if (await feld.isVisible().catch(() => false)) {
        await feld.fill('Tomasz')
        await blatt.getByRole('button', { name: T('losGehts') }).click()
        await blatt.waitForLoadState('networkidle')
        await blatt.goto(url, { waitUntil: 'networkidle' })
      }
    }
    await blatt.waitForTimeout(900)
    const m = await blatt.evaluate(IM_BROWSER)
    const verstoesse = []
    if (m.schlecht.length) verstoesse.push({ regel: 'I1', text: `Text enthält ${[...new Set(m.schlecht)].join(', ')}` })
    if (m.rollen > 1) verstoesse.push({ regel: 'I2', text: `Seite rollt waagrecht um ${m.rollen} px` })
    const hinweise = []
    for (const d of m.diagramme) { const a = achsenPruefen(d); verstoesse.push(...a.befunde); hinweise.push(...a.hinweise) }
    for (const t of m.abgeschnitten.slice(0, 5)) verstoesse.push({ regel: 'I7', text: `abgeschnitten: ${t}` })
    if (seite.arbeiter) for (const k of m.klein.slice(0, 8)) verstoesse.push({ regel: 'I8', text: `zu klein: ${k}` })
    for (const k of konsole.slice(0, 3)) verstoesse.push({ regel: 'I9', text: `Konsole: ${k}` })
    if (m.leereKarten) verstoesse.push({ regel: 'I10', text: `${m.leereKarten} leere Karte(n)` })
    befund.push({ seite: seite.name, breite: breite.name, diagramme: m.diagramme.length, verstoesse, hinweise })
    geprueft++
    await blatt.close()
  }
  await ctx.close()
}
await browser.close()
await vite.close()

writeFileSync(join(HIER, 'befund.json'), JSON.stringify({ daten: process.env.PRUEFSTAND_DATEN ?? 'pruefstand/daten', fehlendeFixtures: [...fehlendeFixtures], befund }, null, 2))
const alle = befund.flatMap(b => b.verstoesse.map(v => `${b.seite}@${b.breite} ${v.regel}: ${v.text}`))
for (const z of alle) console.log(z)
const hinweise = befund.flatMap(b => b.hinweise.map(h => `${b.seite}@${b.breite} Hinweis: ${h}`))
for (const h of hinweise) console.log(h)
console.log(`${geprueft} Seiten geprüft, ${befund.reduce((s, b) => s + b.diagramme, 0)} Diagramme, ${alle.length} Verstösse, ${hinweise.length} Hinweise (Achsen, die das Gerüst nicht lesen kann)` + (fehlendeFixtures.size ? `, ${fehlendeFixtures.size} fehlende Fixtures: ${[...fehlendeFixtures].join(', ')}` : ''))
process.exit(geprueft === 0 ? 2 : alle.length ? 1 : 0)
