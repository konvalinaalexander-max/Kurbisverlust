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
import { anpassen, anteilNachModell, treppe, type Punkt } from './schimmel.ts'
import { bandGeordnet, stroemeSummieren, zeitLaeuftVorwaerts } from './bilanz.ts'
import { vergleiche } from './vergleich.ts'
import { band, deckt, deltaVarianz, schimmelSigma } from './band.ts'

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

const K = { r: 0.001, a0: 0.02, f: 0.05, aKlein: 0.03, aGross: 0.01, aFax: 0.02 }

test('Verkaufsanteil und Ströme summieren sich zu m0', () => {
  const anteil = verkaufsfaehigAnteil(K, 100)
  assert.ok(nahe(anteil, Math.pow(0.999, 100) * 0.98 * 0.95 * 0.96 * 0.98))
  const s = stroeme(1000, 'ausgelagert', K, 100)
  assert.ok(summeStimmt(s))
  assert.ok(nahe(s.verkaufsfaehigKg, 1000 * anteil))
  assert.ok(nahe(s.verdunstungKg, 1000 * (1 - Math.pow(0.999, 100))))
  assert.ok(nahe(s.sockelKg, s.m1 * 0.02))
})

test('Entsorgt: nach der Verdunstung ist alles Schimmel', () => {
  const s = stroeme(100, 'entsorgt', K, 10)
  assert.ok(summeStimmt(s))
  assert.equal(s.verkaufsfaehigKg, 0); assert.equal(s.sockelKg, 0)
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

/* ---------- schimmel -------------------------------------------------------- */

const weibull = (t: number, lambda: number, k: number) => 1 - Math.exp(-lambda * Math.pow(t, k))

test('Fit findet λ und k aus exakten Weibull-Punkten wieder', () => {
  const punkte: Punkt[] = [10, 20, 40, 80, 120].map((t, i) => ({ chargeNr: i + 1, t, f: weibull(t, 0.001, 1.2), w: 1000 + i, mitSockel: false }))
  const m = anpassen(punkte)
  assert.equal(m.n, 5); assert.equal(m.cChargen, 5)
  assert.ok(nahe(m.k, 1.2, 1e-9))
  assert.ok(nahe(m.lambda, 0.001, 1e-9))
  assert.ok(nahe(m.smearing, 1, 1e-9))
  assert.ok(m.varAchse != null && m.varAchse < 1e-18)
  assert.equal(m.brauchbar, true)
  assert.equal(m.sockel, 0)
  assert.ok(nahe(anteilNachModell(m, 40), weibull(40, 0.001, 1.2), 1e-9))
  assert.ok(nahe(anteilNachModell(m, 40, 'oben'), weibull(40, 0.001, 1.2), 1e-6))   // ohne Streuung kein Band
})

test('Sockel: Verarbeitungspunkte mit Grundaussortierung 5 % — das Gitter findet sie', () => {
  const a0 = 0.05
  // Ein Prozent Rauschen, sonst ist das Minimum der Fehlerquadrate exakt null und
  // der Nachweis (SSE ohne Sockel ÷ kleinste SSE) hat keinen Nenner — wie in SQL: nullif(min_sse, 0).
  const punkte: Punkt[] = [
    ...[10, 20, 40, 80, 120].map((t, i) => ({ chargeNr: i + 1, t, f: (a0 + (1 - a0) * weibull(t, 0.001, 1.2)) * (1 + 0.01 * Math.sin(i + 1)), w: 1000, mitSockel: true })),
    ...[15, 60].map((t, i) => ({ chargeNr: 10 + i, t, f: weibull(t, 0.001, 1.2) * (1 + 0.01 * Math.cos(i + 1)), w: 800, mitSockel: false })),
  ]
  const m = anpassen(punkte)
  assert.ok(Math.abs(m.sockel - a0) <= 0.0025 + 1e-12, `Sockel ${m.sockel}`)
  assert.ok(nahe(m.k, 1.2, 2e-2))
  assert.ok(m.sockelNachweis != null && m.sockelNachweis > (m.sockelSchwelle ?? 0), `Nachweis ${m.sockelNachweis} ≤ Schwelle ${m.sockelSchwelle}`)
  assert.equal(m.brauchbar, true)
})

test('Zu wenig Verschiedenheit in der Lagerdauer → nicht brauchbar', () => {
  const punkte: Punkt[] = [30, 32, 35].map((t, i) => ({ chargeNr: i + 1, t, f: weibull(t, 0.001, 1.2) * (1 + i * 0.01), w: 1000, mitSockel: false }))
  const m = anpassen(punkte)
  assert.equal(m.brauchbar, false)      // t_max 35 ≤ 1.5 × 30
})

test('Treppe: monoton, Klasse ohne Punkt erbt die vorige', () => {
  const t = treppe([{ t: 10, schimmelKg: 2, basisKg: 100 }, { t: 20, schimmelKg: 3, basisKg: 100 }, { t: 100, schimmelKg: 1, basisKg: 100 }])
  assert.equal(t[0].anteilMono, 0.02)
  assert.equal(t[1].anteilMono, 0.03)
  assert.equal(t[2].anteilMono, 0.03)   // 31–60: kein Punkt
  assert.equal(t[4].anteilMono, 0.03)   // 91–120: 0.01 gemessen, aber Kürbisse werden nicht wieder gesund
})

/* ---------- bilanz und vergleich -------------------------------------------- */

test('K2 fängt eine Zeile, deren Ströme nicht zu m0 summieren', () => {
  const gut = { charge_nr: 1, portion: 'lager', kohorte: '2026-09-01', m0: '100', verdunstung_kg: '10', sockel_kg: '0', schimmel_kg: '5', klein_kg: '3', nebenkanal_kg: '1', fax_kg: '1', verkaufsfaehig_kg: '80' }
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

test('Schimmel-Sigma: die Ableitung df/dη = (1−f)·exp(η) darf nicht fehlen (AUF-001)', () => {
  // η = 0 → f = 1 − e^-1 = 0.6321, df/dη = 0.3679
  assert.ok(nahe(schimmelSigma(0, 0.1), 0.036788, 1e-5))  // 0.3679 · 0.1
  // Wer nur σ(η) durchreicht (0.1), unterschätzt σ(f) hier nicht — aber bei
  // grossem η wird die Ableitung klein und der Unterschied gross:
  assert.ok(schimmelSigma(2, 0.5) < 0.5)   // f nahe 1, df/dη klein → σ(f) < σ(η)
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
