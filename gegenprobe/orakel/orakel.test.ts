/**
 * Das Orakel prüft sich selbst an Fällen, die **von Hand** gerechnet sind.
 * Kein Fall hier stammt aus der Datenbank — sonst bewiese der Test nur, dass
 * das Orakel abschreibt. Jede Zahl hat ihren Rechenweg im Kommentar.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { anteilPlausibel, nahe, runden, tQuantil95, tageZwischen, zahl } from './zahlen.ts'
import { kohorten, netto, rueckgrat, type Palette, type Tara } from './masse.ts'
import { messung, rohwerte, type Waegung } from './verdunstung.ts'
import { schrumpfung } from './varianz.ts'
import { gedeckelt, m0Zurueck, normieren, stroeme, summeStimmt, verkaufsfaehigAnteil } from './kaskade.ts'
import { erwartung, paloxF, paloxFNach, stationswert, weg, type Punkt } from './schimmel.ts'
import { bandGeordnet, stroemeSummieren, zeitLaeuftVorwaerts } from './bilanz.ts'
import { vergleiche } from './vergleich.ts'
import { band, deckt, deltaVarianz } from './band.ts'
import { huelle, standBei, standNachTagen, summeStimmtPrognose, summieren, verlustAb,
         zerlegungStimmt, type LagerPortion, type Raender } from './prognose.ts'

const G2: Tara = { kistenKg: 1.5, paletteKg: 25 }
const GEBINDE = new Map<string, Tara>([['G2', G2], ['IFCO 6416', { kistenKg: 1.68, paletteKg: 25 }]])

/* ---------- zahlen ---------------------------------------------------------- */

test('t-Quantil: Ränder der Tafel', () => {
  assert.equal(tQuantil95(0), 12.706)
  assert.equal(tQuantil95(1), 12.706)
  assert.equal(tQuantil95(2), 4.303)
  assert.equal(tQuantil95(29), 2.045)
  assert.equal(tQuantil95(30), 1.960)
  assert.equal(tQuantil95(null), 12.706)
})

test('anteil_plausibel: 0 … 0.5, nichts sonst', () => {
  assert.equal(anteilPlausibel(0), true)
  assert.equal(anteilPlausibel(0.5), true)
  assert.equal(anteilPlausibel(0.5001), false)
  assert.equal(anteilPlausibel(-0.01), false)
  assert.equal(anteilPlausibel(null), false)
  assert.equal(anteilPlausibel(NaN), false)
})

test('runden wie PostgreSQL: halb weg von null', () => {
  assert.equal(runden(2.5, 0), 3)
  assert.equal(runden(-2.5, 0), -3)      // JavaScript sagt −2
  assert.equal(runden(2.675, 2), 2.68)   // JavaScript toFixed sagt 2.67
  assert.equal(runden(1.005, 2), 1.01)
})

test('zahl(): der gerundete Wert wird gegen die Grenze gehalten (0068)', () => {
  assert.equal(zahl(99999999999.996, 2, 1e11), null)   // rundet auf 1e11 → weg
  assert.equal(zahl(99999999999.994, 2, 1e11), 99999999999.99)
  assert.equal(zahl(null), null)
  assert.equal(zahl(Infinity), null)
})

test('tageZwischen zählt Kalendertage, auch über Monats- und Jahresgrenzen', () => {
  assert.equal(tageZwischen('2026-02-27', '2026-03-02'), 3)
  assert.equal(tageZwischen('2026-12-31', '2027-01-01'), 1)
  assert.equal(tageZwischen('2029-01-15', '2026-04-20'), -1001)   // der Zettel mit dem falschen Jahr
})

/* ---------- masse ----------------------------------------------------------- */

test('netto: brutto − kisten × kistentara − palettentara, oder unbekannt', () => {
  assert.equal(netto(500, 30, G2), 500 - 45 - 25)
  assert.equal(netto(500, null, G2), null)              // keine Kistenzahl ist nicht „null Kisten"
  assert.equal(netto(500, 30, { kistenKg: 1.5, paletteKg: null }), null)
  assert.equal(netto(500, 30, { kistenKg: 1.5, paletteKg: null }, false), 455)   // Palox: ohne Palette
  assert.equal(netto(null, 30, G2), null)
})

const PALETTEN: Palette[] = [
  { id: 1, chargeNr: 1, eingangsdatum: '2026-09-01', bruttoKg: 500, kisten: 30, gebindeart: 'G2' },        // netto 430
  { id: 2, chargeNr: 1, eingangsdatum: '2026-09-01', bruttoKg: 520, kisten: 30, gebindeart: 'G2' },        // netto 450
  { id: 3, chargeNr: 1, eingangsdatum: '2026-09-03', bruttoKg: 480, kisten: 28, gebindeart: null },        // kein Netto
]

test('Rückgrat: Paletten ohne Netto bekommen das Mittel der anderen — ausgewiesen, nicht versteckt', () => {
  const r = rueckgrat(PALETTEN, GEBINDE).get(1)!
  assert.equal(r.nPaletten, 3)
  assert.equal(r.nMitNetto, 2)
  assert.equal(r.eingangGemessenKg, 880)
  assert.equal(r.eingangKg, 880 / 2 * 3)   // 1320
})

test('Kohorten: der Tag ohne Netto erbt das Chargenmittel; die Anteile summieren sich zu 1', () => {
  const k = kohorten(PALETTEN, GEBINDE)
  assert.equal(k.length, 2)
  assert.equal(k[0].eingangKg, 880)            // 2 × 440
  assert.equal(k[1].eingangKg, 440)            // 1 × Chargenmittel 440
  assert.ok(nahe(k[0].anteil, 0.666667, 0, 5e-7))
  assert.ok(nahe(k[1].anteil, 0.333333, 0, 5e-7))
  assert.ok(nahe((k[0].anteil ?? 0) + (k[1].anteil ?? 0), 1, 0, 1e-6))
})

/* ---------- verdunstung ----------------------------------------------------- */

const WAEGUNG: Waegung = { id: 7, chargeNr: 1, sorte: 'Orangita', eingangsdatum: '2026-09-01', wiegeTag: '2026-09-21',
  bruttoDamalsKg: 500, bruttoJetztKg: 480, kisten: 30, gebindeart: 'G2', sichtbarSchimmel: false, gemessen: true, abgebrochen: false }

test('Rate je Tag: 1 − (jetzt/damals)^(1/Tage), auf sechs Stellen', () => {
  const m = messung(WAEGUNG, GEBINDE)
  assert.equal(m.nettoDamalsKg, 430)
  assert.equal(m.nettoJetztKg, 410)
  assert.equal(m.lagertage, 20)
  assert.equal(m.ratePreTag, runden(1 - Math.pow(410 / 430, 1 / 20), 6))   // ≈ 0.002379
  assert.ok(nahe(m.ratePreTag, 0.002379, 0, 5e-7))
  assert.equal(m.verwendbar, true)
})

test('Nicht verwendbar: Zettel im falschen Jahr, schwerer geworden, ohne Kisten', () => {
  const falschesJahr = messung({ ...WAEGUNG, eingangsdatum: '2029-09-01' }, GEBINDE)
  assert.equal(falschesJahr.verwendbar, false)
  assert.equal(falschesJahr.lagertage, -1076)
  assert.ok(falschesJahr.gruende.some(g => g.includes('vor dem Eingang')))
  assert.equal(falschesJahr.ratePreTag, null)                       // keine Rate aus negativen Tagen

  const schwerer = messung({ ...WAEGUNG, bruttoJetztKg: 506 }, GEBINDE)   // netto 436 > 430 × 1.01 = 434.3
  assert.equal(schwerer.verwendbar, false)
  assert.ok(schwerer.ratePreTag !== null && schwerer.ratePreTag < 0)      // die Rate steht, aber sie zählt nicht

  const ohneKisten = messung({ ...WAEGUNG, kisten: null }, GEBINDE)
  assert.equal(ohneKisten.verwendbar, false)
  assert.equal(ohneKisten.nettoJetztKg, null)
  assert.equal(rohwerte([falschesJahr, schwerer, ohneKisten]).length, 0)
})

/* ---------- varianz (Schrumpfung) ------------------------------------------- */

test('Schrumpfung, von Hand: zwei Sorten mit klar getrennten Mitteln bleiben fast bei sich', () => {
  // A: Chargen 1, 2 mit Anteil 0.10, 0.12 (Gewicht 1)   → sw = 2, mittel 0.11
  //    var_A = Σ_c (swa_c − mittel·sw_c)² / sw² · c/(c−1) = (0.01² + 0.01²) / 4 · 2 = 0.0001
  //    (der Nenner ist das Gewicht der **Ebene**, nicht der Charge — das ist die Varianz des Mittels)
  // B: Chargen 3, 4 mit Anteil 0.50, 0.52               → mittel 0.51, var 0.0001
  // gesamt: sw = 4, mittel 0.31, var = (0.21² + 0.19² + 0.19² + 0.21²) / 16 · 4/3 = 0.1604/16 · 4/3 = 0.01336667
  // tau² = Σ_s sw_s (mittel_s − 0.31)² / Σ sw_s − ⌀ var_s = (2·0.2² + 2·0.2²)/4 − 0.0001 = 0.04 − 0.0001 = 0.0399
  // b_A = 0.0399 / (0.0399 + 0.0001) = 0.9975
  // mittel_A = 0.9975·0.11 + 0.0025·0.31 = 0.1105
  // varianz_A = 0.9975·0.0001 + 0.0025²·0.01336667 = 0.00009975 + 0.0000000835417 = 0.0000998335417
  // df_A = max(round(0.9975·2 + 0.0025·4) − 1, 1) = round(2.005) − 1 = 1  → t = 12.706
  const s = schrumpfung([
    { sorte: 'A', chargeNr: 1, anteil: 0.10, gewicht: 1 }, { sorte: 'A', chargeNr: 2, anteil: 0.12, gewicht: 1 },
    { sorte: 'B', chargeNr: 3, anteil: 0.50, gewicht: 1 }, { sorte: 'B', chargeNr: 4, anteil: 0.52, gewicht: 1 },
  ], ['A', 'B', 'C'])
  const a = s.find(z => z.sorte === 'A')!, c = s.find(z => z.sorte === 'C')!, g = s.find(z => z.sorte === null)!
  assert.ok(nahe(a.varianzRoh, 0.0001))
  assert.ok(nahe(g.mittel, 0.31))
  assert.ok(nahe(g.varianz, 0.1604 / 16 * 4 / 3))
  assert.ok(nahe(a.tau2, 0.0399))
  assert.ok(nahe(a.b, 0.9975))
  assert.ok(nahe(a.mittel, 0.1105))
  assert.ok(nahe(a.varianz, 0.0000998335417, 1e-8))
  assert.equal(a.df, 1)
  assert.ok(nahe(a.unten, 0.1105 - 12.706 * Math.sqrt(0.0000998335417), 1e-6))
  // Sorte ohne Beobachtung: b = 0, sie trägt den Gesamtwert und dessen Streuung
  assert.equal(c.b, 0); assert.ok(nahe(c.mittel, 0.31)); assert.ok(nahe(c.varianz, g.varianz))
})

test('Schrumpfung: streuen die Chargen innerhalb der Sorten stärker als die Sorten untereinander, gilt nur der Gesamtwert (tau² = 0)', () => {
  // A: 0.1, 0.5 (mittel 0.3, var_A = (0.2² + 0.2²)/4·2 = 0.04);  B: 0.3, 0.7 (mittel 0.5, var 0.04)
  // zwischen: (2·0.1² + 2·0.1²)/4 = 0.01;  innen ⌀ 0.04  →  tau² = max(0.01 − 0.04, 0) = 0
  const s = schrumpfung([
    { sorte: 'A', chargeNr: 1, anteil: 0.1, gewicht: 1 }, { sorte: 'A', chargeNr: 2, anteil: 0.5, gewicht: 1 },
    { sorte: 'B', chargeNr: 3, anteil: 0.3, gewicht: 1 }, { sorte: 'B', chargeNr: 4, anteil: 0.7, gewicht: 1 },
  ], ['A', 'B'])
  const a = s.find(z => z.sorte === 'A')!
  assert.equal(a.tau2, 0)
  assert.equal(a.b, 0)
  assert.ok(nahe(a.mittel, 0.4))
})

/* ---------- kaskade --------------------------------------------------------- */

const K = { r: 0.001, f: 0.05, aKlein: 0.03, aGross: 0.01, aFax: 0.02 }

test('Verkaufsanteil und Ströme summieren sich zu m0', () => {
  const anteil = verkaufsfaehigAnteil(K, 100)
  assert.ok(nahe(anteil, Math.pow(0.999, 100) * 0.95 * 0.96 * 0.98))   // Verdunstung · (1 − f) · (1 − klein − gross) · (1 − Fax)
  const s = stroeme(1000, 'ausgelagert', K, 100)
  assert.ok(summeStimmt(s))
  assert.ok(nahe(s.verkaufsfaehigKg, 1000 * anteil))
  assert.ok(nahe(s.verdunstungKg, 1000 * (1 - Math.pow(0.999, 100))))
  assert.ok(nahe(s.schimmelKg, s.m1 * 0.05))
})

test('Entsorgt: nach der Verdunstung ist alles Schimmel', () => {
  const s = stroeme(100, 'entsorgt', K, 10)
  assert.ok(summeStimmt(s))
  assert.equal(s.verkaufsfaehigKg, 0); assert.equal(s.kleinKg, 0)
  assert.ok(nahe(s.schimmelKg, 100 * Math.pow(0.999, 10)))
})

test('m0 zurück aus dem Gelieferten, mit Deckel 0.25', () => {
  assert.ok(nahe(m0Zurueck(100, 'ausgelagert', K, 100), 100 / verkaufsfaehigAnteil(K, 100)))
  const faul = { ...K, f: 0.9 }
  assert.equal(gedeckelt(faul, 100), true)
  assert.equal(m0Zurueck(100, 'ausgelagert', faul, 100), 400)
  assert.equal(gedeckelt(K, 100), false)
})

test('zu klein + zu gross über 1 werden gemeinsam gestaucht', () => {
  const n = normieren(0.7, 0.6)
  assert.ok(nahe(n.aKleinN, 0.7 / 1.3)); assert.ok(nahe(n.aGrossN, 0.6 / 1.3))
  assert.deepEqual(normieren(0.3, 0.1), { aKleinN: 0.3, aGrossN: 0.1 })
})

/* ---------- stationswerte (0106) ------------------------------------------- */

const P = (sorte: string, station: Punkt['station'], chargeNr: number, messtag: string, w: number, y: number): Punkt =>
  ({ sorte, station, chargeNr, messtag, w, y })

test('Stationswert: nach Masse gewichtet, Band ± t·sd/√n über die Arbeiten, Chargen gezählt', () => {
  // 1000 kg mit 4 %, 3000 kg mit 2 %, 2000 kg mit 3 %: (40 + 60 + 60) / 6000 = 2.667 % — nicht das Mittel 3 %
  const s = stationswert([P('Tiana', 'waschen_sortieren', 1, '2026-09-20', 1000, 0.04),
                          P('Tiana', 'waschen_sortieren', 2, '2026-09-21', 3000, 0.02),
                          P('Tiana', 'waschen_sortieren', 1, '2026-09-22', 2000, 0.03)])
  assert.ok(nahe(s.anteil!, 160 / 6000, 1e-12))
  assert.equal(s.nArbeiten, 3); assert.equal(s.nChargen, 2)
  // sd der drei Anteile = 0.01, t(2) = 4.303 → halb = 4.303 · 0.01 / √3
  const halb = tQuantil95(2) * 0.01 / Math.sqrt(3)
  assert.ok(nahe(s.unten!, 160 / 6000 - halb, 1e-9)); assert.ok(nahe(s.oben!, 160 / 6000 + halb, 1e-9))
  assert.equal(stationswert([]).anteil, null)
  const eine = stationswert([P('Tiana', 'sortieren', 1, '2026-09-20', 500, 0.03)])
  assert.equal(eine.unten, 0.03); assert.equal(eine.oben, 0.03)   // eine Arbeit hat kein Band
})

test('Erwartung: vier Wochen der Sorte ab drei Arbeiten, sonst Saison, sonst alle Sorten — geliehen', () => {
  const heute = '2026-09-29'
  const punkte = [
    // Tiana von Hand: drei junge Arbeiten (in vier Wochen) und eine alte
    P('Tiana', 'waschen_sortieren', 1, '2026-09-25', 1000, 0.04), P('Tiana', 'waschen_sortieren', 2, '2026-09-20', 1000, 0.02),
    P('Tiana', 'waschen_sortieren', 3, '2026-09-10', 1000, 0.03), P('Tiana', 'waschen_sortieren', 4, '2026-06-01', 1000, 0.10),
    // Kaori am Band: zwei Arbeiten — zu wenig für die Sorte, auch in der Saison; dazu eine Tiana-Bandarbeit
    P('Kaori Kuri', 'sortieren', 5, '2026-09-27', 500, 0.05), P('Kaori Kuri', 'sortieren', 6, '2026-08-01', 500, 0.01),
    P('Tiana', 'sortieren', 7, '2026-08-15', 800, 0.02),
  ]
  const e = erwartung(punkte, ['Tiana', 'Kaori Kuri', 'Bolp 5110'], heute)
  const finde = (sorte: string, station: string) => e.find(x => x.sorte === sorte && x.station === station)
  const tw = finde('Tiana', 'waschen_sortieren')!
  assert.equal(tw.ebene, 'sorte_4w'); assert.equal(tw.nArbeiten, 3); assert.equal(tw.geliehen, false)
  assert.ok(nahe(tw.anteil!, 0.03, 1e-12))                       // die alte Arbeit vom Juni zählt nicht
  const ks = finde('Kaori Kuri', 'sortieren')!
  assert.equal(ks.ebene, 'alle_saison'); assert.equal(ks.nArbeiten, 3); assert.equal(ks.geliehen, true)
  assert.ok(nahe(ks.anteil!, (25 + 5 + 16) / 1800, 1e-12))       // 500·0.05 + 500·0.01 + 800·0.02 über 1800 kg
  const bw = finde('Bolp 5110', 'waschen_sortieren')!
  assert.equal(bw.ebene, 'alle_4w'); assert.equal(bw.nArbeiten, 3)      // die drei jungen Handarbeiten aller Sorten
  assert.equal(finde('Bolp 5110', 'waschen'), undefined)          // nirgends ein Waschpunkt: kein Wert
  assert.equal(e.length, 6)                                       // drei Sorten × zwei Stationen mit Punkten
})

test('palox_f: die Zusammensetzung über den Weg — und NULL, sobald eine Station auf dem Weg keinen Wert hat', () => {
  assert.equal(paloxF(1, 0, 0.05, null, null), 0.05)                              // nur von Hand
  assert.equal(paloxF(0, 0, null, 0.02, null), 0.02)                              // Band, ungewaschen
  assert.ok(nahe(paloxF(0, 1, null, 0.02, 0.05)!, 0.02 + 0.98 * 0.05, 1e-12))     // Band, dann gewaschen
  assert.ok(nahe(paloxF(0.25, 1, 0.04, 0.02, 0.05)!, 0.25 * 0.04 + 0.75 * (0.02 + 0.98 * 0.05), 1e-12))
  assert.equal(paloxF(null, 1, 0.04, 0.02, 0.05), null)                           // ohne Weg
  assert.equal(paloxF(0.5, 1, null, 0.02, 0.05), null)                            // Hand auf dem Weg, kein Handwert
  assert.equal(paloxF(0, 1, null, 0.02, null), null)                              // gewaschen, kein Waschwert
  assert.equal(paloxF(1, 0, 1.5, null, null), 1)                                  // nie über 1
})

test('palox_f_nach: jede Station um ihren Zuwachs je Woche fortgeschrieben, nie unter 0', () => {
  assert.ok(nahe(paloxFNach(0, 1, 0.02, 0.02, 0.05, 0.01, 0.01, 0.01, 14)!, 0.04 + 0.96 * 0.07, 1e-12))
  assert.equal(paloxFNach(0, 1, null, 0.02, 0.05, null, -0.1, null, 70), paloxF(0, 1, null, 0, 0.05))
  assert.equal(paloxFNach(1, 0, 0.05, null, null, null, null, null, 28), 0.05)   // ohne Zuwachs steht die Station still
})

test('Weg: eigene Arbeiten, sonst die der Sorte, sonst alle; gewaschen, sobald die Sorte gewaschen wird', () => {
  const a = (chargeNr: number, sorte: string, station: string, kg: number) => ({ chargeNr, sorte, station, kg, istFax: false })
  const arbeiten = [a(1, 'Tiana', 'waschen_sortieren', 3000), a(2, 'Kaori', 'sortieren', 2000), a(2, 'Kaori', 'waschen', 500), a(3, 'Kaori', 'sortieren', 1000)]
  const w = weg(arbeiten, [1, 2, 3, 4, 5, 6].map(nr => ({ chargeNr: nr, sorte: nr === 1 || nr === 5 ? 'Tiana' : nr === 6 ? 'Bolp' : 'Kaori' })))
  assert.deepEqual(w.get(1), { pHand: 1, pWasch: 0, quelle: 'eigenen Arbeiten' })       // Tiana: nur von Hand, nie gewaschen
  assert.deepEqual(w.get(2), { pHand: 0, pWasch: 1, quelle: 'eigenen Arbeiten' })
  assert.deepEqual(w.get(3), { pHand: 0, pWasch: 1, quelle: 'eigenen Arbeiten' })       // die Sorte wird gewaschen
  assert.deepEqual(w.get(4), { pHand: 0, pWasch: 1, quelle: 'Arbeiten der Sorte' })
  assert.deepEqual(w.get(5), { pHand: 1, pWasch: 0, quelle: 'Arbeiten der Sorte' })
  assert.deepEqual(w.get(6), { pHand: 0.5, pWasch: 1, quelle: 'Arbeiten aller Sorten' }) // alle: 3000 von Hand, 3000 Band, gewaschen
  assert.deepEqual(weg([], [{ chargeNr: 9, sorte: 'X' }]).get(9), { pHand: null, pWasch: null, quelle: null })
  // Fax-Arbeiten sind kein Waschen
  assert.deepEqual(weg([{ ...a(7, 'Bolp', 'waschen', 100), istFax: true }, a(7, 'Bolp', 'sortieren', 100)], [{ chargeNr: 7, sorte: 'Bolp' }]).get(7),
                   { pHand: 0, pWasch: 0, quelle: 'eigenen Arbeiten' })
})

/* ---------- bilanz und vergleich -------------------------------------------- */

test('K2 fängt eine Zeile, deren Ströme nicht zu m0 summieren', () => {
  const gut = { charge_nr: 1, portion: 'lager', kohorte: '2026-09-01', m0: '100', verdunstung_kg: '10', schimmel_kg: '5', klein_kg: '3', nebenkanal_kg: '1', fax_kg: '1', verkaufsfaehig_kg: '80' }
  assert.deepEqual(stroemeSummieren([gut]), [])
  const v = stroemeSummieren([{ ...gut, verkaufsfaehig_kg: '79' }])
  assert.equal(v.length, 1); assert.equal(v[0].regel, 'K2')
})

test('K5 fängt ein Band, das keins ist', () => {
  assert.deepEqual(bandGeordnet([{ u: 1, m: 2, o: 3 }], 'u', 'm', 'o', () => 'x'), [])
  assert.equal(bandGeordnet([{ u: 3, m: 2, o: 1 }], 'u', 'm', 'o', () => 'x').length, 1)
  assert.equal(bandGeordnet([{ u: null, m: 2, o: 3 }], 'u', 'm', 'o', () => 'x').length, 1)
})

test('Delta-Methode: die volle Kovarianz zählt, nicht nur die Diagonale', () => {
  // Ableitungen [2, 3], Kov [[1, 0.5], [0.5, 4]]
  // Var = 2·2·1 + 2·3·0.5 + 3·2·0.5 + 3·3·4 = 4 + 3 + 3 + 36 = 46
  assert.ok(nahe(deltaVarianz([2, 3], [[1, 0.5], [0.5, 4]]), 46))
  // Nur Diagonale (Kovarianz ignoriert) = 4 + 36 = 40 — hier zu klein
  assert.ok(nahe(deltaVarianz([2, 3], [[1, 0], [0, 4]]), 40))
  // Negative Kovarianz kann die Streuung senken
  assert.ok(nahe(deltaVarianz([2, 3], [[1, -0.5], [-0.5, 4]]), 34))
  // Var ist nie negativ
  assert.equal(deltaVarianz([1, -1], [[1, 0.9], [0.9, 1]]) >= 0, true)
})

test('Band: mittel ± t·√Var; Überdeckung', () => {
  const b = band(10, [1], [[4]], 2)   // sigma = 2, t = 2
  assert.ok(nahe(b.sigma, 2)); assert.ok(nahe(b.unten, 6)); assert.ok(nahe(b.oben, 14))
  assert.equal(deckt(b.unten, b.oben, 7), true)
  assert.equal(deckt(b.unten, b.oben, 5), false)
})

test('K7 fängt den Zettel mit dem falschen Jahr — plausibel und negativ zugleich', () => {
  const punkte = [{ charge_nr: 9901, quelle: 'verarbeitung', lagertage: '-1053.0', plausibel: true },
                  { charge_nr: 9901, quelle: 'lager', lagertage: '-1054', plausibel: false },
                  { charge_nr: 1613, quelle: 'verarbeitung', lagertage: '44.0', plausibel: true }]
  // Eine Arbeit mit negativen Lagertagen ist nur dann ein Verstoss, wenn ihre
  // Charge NICHT als Auffälligkeit gemeldet ist: 9902 ist gemeldet (kein
  // Verstoss), 9903 nicht (Verstoss).
  const arbeiten = [{ auftrag_id: 313, station: 'waschen', charge_nr: 9902, lagertage: '-137.7' },
                    { auftrag_id: 314, station: 'sortieren', charge_nr: 9903, lagertage: '-9.0' }]
  const v = zeitLaeuftVorwaerts(punkte, arbeiten, new Set(['9902']))
  assert.deepEqual(v.map(x => x.wo), ['Punkt Charge 9901 (verarbeitung)', 'Arbeit 314 (sortieren, Charge 9903)'])
})

test('vergleiche: Toleranz je Spalte, fehlende Partner auf beiden Seiten', () => {
  const ab = vergleiche(
    [{ id: 1, x: '1.0000001' }, { id: 2, x: '5' }],
    [{ id: 1, x: 1.0000002 }, { id: 3, x: 5 }],
    { db: a => String(a.id), orakel: b => String(b.id) },
    [{ db: 'x', orakel: 'x', rel: 1e-6 }],
  )
  assert.deepEqual(ab.map(a => `${a.schluessel}:${a.spalte}`), ['2:*', '3:*'])
})

/* ---------- prognose: von Hand, zwei Kohorten ------------------------------ */

// Zwei Kohorten derselben Charge, alles glatt gewählt, damit man mitrechnen
// kann. r = 0.001 je Tag, 4 % zu klein, 1 % zu gross, 2 % Fax.
const P_ALT: LagerPortion = { chargeNr: 1, kohorte: '2026-08-01', alterTage: 100, m0: 10000,
                              r: 0.001, aKleinN: 0.04, aGrossN: 0.01, aFax: 0.02 }
const P_JUNG: LagerPortion = { ...P_ALT, kohorte: '2026-09-10', alterTage: 30, m0: 5000 }

test('Prognose: der Stand bei Alter t ist die Kaskade, und die Ströme ergeben m0', () => {
  // F(100) sei 0.10. m1 = 10000 · 0.999^100 = 9048.33…
  const m1 = 10000 * Math.pow(0.999, 100)
  assert.ok(nahe(m1, 9048.33, 1e-2, 1e-2))
  const s = standBei(P_ALT, 0.10)
  assert.ok(nahe(s.m1, m1, 1e-12))
  assert.ok(nahe(s.m2, m1 * 0.90, 1e-12))              // 10 % faul
  assert.ok(nahe(s.faulKg, m1 * 0.10, 1e-12))
  assert.ok(nahe(s.kanalKg, m1 * 0.90 * 0.05, 1e-12))  // 4 % + 1 %
  assert.ok(nahe(s.faxKg, m1 * 0.90 * 0.95 * 0.02, 1e-12))
  assert.ok(nahe(s.verkaufsfaehigKg, m1 * 0.90 * 0.95 * 0.98, 1e-12))
  assert.equal(summeStimmtPrognose({ ...s, lagerKg: P_ALT.m0 }), true)
})

test('Prognose: Horizont 0 ist heute — keine zweite Mathematik', () => {
  const heute = standBei(P_ALT, 0.10)
  const inNullTagen = standNachTagen(P_ALT, 0, 0.10)
  assert.deepEqual(inNullTagen, heute)
  const v = verlustAb(P_ALT, 0, 0.10, 0.10)
  assert.deepEqual(v, { wasserKg: 0, faeulnisKg: 0, verkaufsfaehigKg: 0 })
})

test('Prognose: Wasser und Fäulnis ergeben exakt, was der Horizont kostet', () => {
  // In 28 Tagen steigt F von 0.10 auf 0.13.
  const vf0 = standBei(P_ALT, 0.10).verkaufsfaehigKg
  const vfH = standNachTagen(P_ALT, 28, 0.13).verkaufsfaehigKg
  const v = verlustAb(P_ALT, 28, 0.10, 0.13)
  assert.equal(zerlegungStimmt(vf0, vfH, v), true)
  // Von Hand: B = 10000 · 1 · 0.95 · 0.98 = 9310; Basis = B · 0.999^100.
  const basis = 9310 * Math.pow(0.999, 100)
  assert.ok(nahe(v.wasserKg, basis * 0.90 * (1 - Math.pow(0.999, 28)), 1e-12))
  assert.ok(nahe(v.faeulnisKg, basis * Math.pow(0.999, 28) * 0.03, 1e-12))
  assert.ok(v.wasserKg > 0 && v.faeulnisKg > 0)
})

test('Prognose: gesättigter Verderb macht die Fäulnis nicht negativ', () => {
  // F fällt nicht, aber eine Treppe kann zweimal denselben Wert liefern.
  // Dann ist der ganze Verlust Wasser — und nichts wird negativ.
  const v = verlustAb(P_ALT, 28, 0.42, 0.42)
  assert.equal(v.faeulnisKg, 0)
  assert.ok(v.wasserKg > 0)
  const vf0 = standBei(P_ALT, 0.42).verkaufsfaehigKg
  const vfH = standNachTagen(P_ALT, 28, 0.42).verkaufsfaehigKg
  assert.equal(zerlegungStimmt(vf0, vfH, v), true)
})

test('Prognose: die Summe über zwei Kohorten — Alter massegewichtet am Horizont', () => {
  const teil = (p: LagerPortion, h: number, fHeute: number, fDann: number) => ({
    p, t: p.alterTage + h,
    stand: standNachTagen(p, h, fDann),
    verlust: verlustAb(p, h, fHeute, fDann),
    huelle: { unten: 0, oben: 0 },
    bekannt: { r: true, f: true, kanal: true, fax: true },
    fGeliehen: false, zuwachsBekannt: true,
  })
  const z = summieren([teil(P_ALT, 28, 0.10, 0.13), teil(P_JUNG, 28, 0.02, 0.03)])
  assert.equal(z.lagerKg, 15000)
  assert.equal(z.nKohorten, 2)
  // (10000·128 + 5000·58) / 15000 = (1280000 + 290000) / 15000 = 104.666…
  assert.ok(nahe(z.alterTage, 1570000 / 15000, 1e-12))
  assert.equal(z.alterVon, 58)
  assert.equal(z.alterBis, 128)
  assert.equal(summeStimmtPrognose(z), true)
  assert.ok(nahe(z.verlustVerkaufsfaehigKg, z.verlustWasserKg + z.verlustFaeulnisKg, 1e-12))
  // Alle Koeffizienten bekannt → der Anteil steht da, und er ist genau
  // „verkaufsfähig durch Eingangsware" — der Nenner, der über die Zeit gleich
  // bleibt. Von Hand: 7126.6 + 4260.7 = 11387.3 von 15000 → 75.9 %.
  assert.ok(nahe(z.verkaufsfaehigKg, 11387.3, 1e-4, 0.1))
  assert.ok(nahe(z.verkaufsfaehigAnteil!, z.verkaufsfaehigKg / 15000, 1e-12))
  assert.ok(nahe(z.verkaufsfaehigAnteil!, 0.759, 1e-2, 1e-3))
})

test('Prognose: fehlt ein Koeffizient, bleibt der Anteil leer (leer ist nicht null)', () => {
  const teil = (bekannt: boolean) => ({
    p: P_ALT, t: 128,
    stand: standNachTagen(P_ALT, 28, 0.13),
    verlust: verlustAb(P_ALT, 28, 0.10, 0.13),
    huelle: { unten: 0, oben: 0 },
    bekannt: { r: true, f: true, kanal: bekannt, fax: true },
    fGeliehen: false, zuwachsBekannt: true,
  })
  assert.equal(summieren([teil(true)]).verkaufsfaehigAnteil != null, true)
  assert.equal(summieren([teil(false)]).verkaufsfaehigAnteil, null)
  assert.equal(summieren([teil(true), teil(false)]).vollstaendig, false)
})

test('Prognose: die Hülle schliesst den Mittelwert ein', () => {
  const g: Raender = { rUnten: 0.0005, rOben: 0.0015,
                       kleinUnten: 0.03, kleinOben: 0.05, grossUnten: 0.005, grossOben: 0.02,
                       faxUnten: 0.01, faxOben: 0.03 }
  const h = huelle(P_ALT, 28, 0.11, 0.16, g)
  const mitte = standNachTagen(P_ALT, 28, 0.13).verkaufsfaehigKg
  assert.ok(h.unten <= mitte && mitte <= h.oben,
    `Hülle ${h.unten.toFixed(1)} … ${h.oben.toFixed(1)} schliesst ${mitte.toFixed(1)} nicht ein`)
  // Die Normierung greift, wenn zu klein und zu gross zusammen über 1 gehen.
  const extrem = huelle(P_ALT, 0, 0, 0, { ...g, kleinOben: 0.8, grossOben: 0.6 })
  assert.ok(extrem.unten >= 0, 'die untere Kante darf nie negativ werden')
})
