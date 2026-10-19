/**
 * Runde AQ: „Wie viel haben wir von welchem Artikel noch übrig? … mit einer
 * Grafik, nach Artikeln sortiert, noch im Lager, also Eingang, Ausgang, noch
 * im Lager. Und dann vielleicht schon auch noch mit Tabelle."
 *
 * Die Übersicht zählt je Artikelgruppe × Label die Chargen zusammen. Sie
 * erfindet nichts: Eingang, ausgelagert, geliefert, Lager und Verkaufsfähiges
 * sind die Zahlen der Chargen (erg_charge), die Grössen dieselben Teile wie die
 * Tabelle in Kisten (artikel_lager_charge). Ein unbekanntes Verkaufsfähiges
 * wird nie 0 — es zählt als Lücke.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { OFFEN, klasseVon, uebersichtszeilen } from '../src/auswertung/artikel.ts'
import type { ArtikelLagerCharge, Bestand, ChargeLabel, SorteGruppe } from '../src/auswertung/daten.ts'

const charge = (nr: number, sorte: string, eingang: number, ausgelagert: number, geliefert: number, vf: number | null) =>
  ({ charge_nr: nr, sorte, eingang_kg: eingang, ausgelagert_kg: ausgelagert, geliefert_kg: geliefert,
     lager_kg: eingang - ausgelagert, verkaufsfaehig_lager_kg: vf } as unknown as Bestand)
const bestand = [
  charge(1, 'Kaori Kuri', 1000, 600, 500, 300),
  charge(2, 'Amoro', 500, 0, 0, null),          // liegt, Verkaufsfähiges unbekannt
  charge(3, 'Tiana', 2000, 2000, 1800, null),   // ausgeliefert, nichts mehr im Lager
]
const labelVon = new Map<number, ChargeLabel>([
  [1, { charge_nr: 1, label: 'D' } as ChargeLabel], [2, { charge_nr: 2, label: 'D' } as ChargeLabel], [3, { charge_nr: 3, label: 'K' } as ChargeLabel]])
const gruppeVon = new Map<string, SorteGruppe>([
  ['Kaori Kuri', { sorte: 'Kaori Kuri', artikelgruppe: 'Knirps' } as SorteGruppe],
  ['Amoro', { sorte: 'Amoro', artikelgruppe: 'Knirps' } as SorteGruppe],
  ['Tiana', { sorte: 'Tiana', artikelgruppe: 'Butternut' } as SorteGruppe]])
const teil = (nr: number, groesse: string, kg: number) => ({ charge_nr: nr, groesse, kg } as ArtikelLagerCharge)
const teile = [teil(1, 'klein', 200), teil(1, 'gross', 90), teil(1, 'ohne Verteilung', 10), teil(9, 'klein', 999), teil(1, 'klein', 0)]

test('Übersicht: je Artikelgruppe × Label die Chargen zusammengezählt, nach der Reihenfolge des Verkaufs', () => {
  const z = uebersichtszeilen(bestand, labelVon, gruppeVon, teile, OFFEN)
  assert.deepEqual(z.map(x => `${x.gruppe}|${x.label}`), ['Knirps|D', 'Butternut|K'])
  const [knirps, butternut] = z
  assert.equal(knirps.n, 2); assert.equal(knirps.eingang, 1500); assert.equal(knirps.ausgelagert, 600)
  assert.equal(knirps.geliefert, 500); assert.equal(knirps.lager, 900)
  assert.equal(butternut.geliefert, 1800); assert.equal(butternut.lager, 0)
  for (const x of z) assert.equal(x.ausgelagert + x.lager, x.eingang, 'der Balken ist so lang wie der Eingang')
})

test('Übersicht: ein unbekanntes Verkaufsfähiges wird nicht 0, sondern eine Lücke — nur bei Chargen, die liegen', () => {
  const [knirps, butternut] = uebersichtszeilen(bestand, labelVon, gruppeVon, teile, OFFEN)
  assert.equal(knirps.vf, 300); assert.equal(knirps.luecke, 1)
  assert.equal(butternut.vf, 0); assert.equal(butternut.luecke, 0, 'nichts im Lager, also keine Lücke')
})

test('Übersicht: die Grössen aus denselben Teilen wie die Tabelle — fremde Chargen und 0 kg zählen nicht', () => {
  const [knirps] = uebersichtszeilen(bestand, labelVon, gruppeVon, teile, OFFEN)
  assert.equal(knirps.klassen.get('klein'), 200)
  assert.equal(knirps.klassen.get('gross'), 90)
  assert.equal(knirps.klassen.get(klasseVon('ohne Verteilung')), 10)
})

test('Übersicht: die Wahl oben filtert nach Artikel und Label', () => {
  assert.deepEqual(uebersichtszeilen(bestand, labelVon, gruppeVon, teile, { ...OFFEN, label: 'K' }).map(x => x.gruppe), ['Butternut'])
  assert.deepEqual(uebersichtszeilen(bestand, labelVon, gruppeVon, teile, { ...OFFEN, gruppe: 'Knirps' }).map(x => x.label), ['D'])
  assert.deepEqual(uebersichtszeilen(bestand, labelVon, gruppeVon, teile, { ...OFFEN, gruppe: 'Kabocha' }), [])
})

// Runde AS: „Schaut doch, dass da hier die gleichen Farben verwendet werden" —
// der Balken teilt das Lager wie im Lagermanagement nach Charge, und die eine
// Tabelle darunter trägt den Wochenregler.
test('Übersicht: der Rest des Lagers wie die Kaskade ihn teilt — Lager = verkaufsfähig + Rest', () => {
  // Charge 1: 400 kg im Lager, 300 verkaufsfähig — die Kaskade teilt die übrigen 100.
  const rest = new Map([[1, { kanal: 20, faul: 50, verdunstet: 25, fax: 5 }], [2, { kanal: 1, faul: 1, verdunstet: 1, fax: 0 }]])
  const [knirps] = uebersichtszeilen(bestand, labelVon, gruppeVon, teile, OFFEN, { rest })
  assert.deepEqual(knirps.rest, { kanal: 20, faul: 50, verdunstet: 25, fax: 5, offen: 500 },
    'Charge 2 kennt ihr Verkaufsfähiges nicht: ihre 500 kg sind offen, nicht geteilt')
  const r = knirps.rest
  assert.equal(knirps.vf + r.kanal + r.faul + r.verdunstet + r.fax + r.offen, knirps.lager)
  assert.deepEqual(knirps.chargen, [1, 2])
})

test('Übersicht: ohne Teilung der Kaskade ist der Rest offen, nicht null', () => {
  const [knirps] = uebersichtszeilen(bestand, labelVon, gruppeVon, teile, OFFEN)
  assert.equal(knirps.rest.kanal + knirps.rest.faul + knirps.rest.verdunstet + knirps.rest.fax, 0)
  assert.equal(knirps.rest.offen, 100 + 500)
})

test('Übersicht: die Grössen am Stichtag der Tabelle getrennt von heute', () => {
  const spaeter = [teil(1, 'klein', 150), teil(1, 'gross', 60), teil(1, 'unter 600 g', 20)]
  const [knirps] = uebersichtszeilen(bestand, labelVon, gruppeVon, teile, OFFEN, { spaeter })
  assert.equal(knirps.klassen.get('klein'), 200, 'der Balken bleibt heute')
  assert.equal(knirps.klassenSpaeter.get('klein'), 150)
  assert.equal(knirps.klassenSpaeter.get('ausserhalb'), 20)
  const [ohne] = uebersichtszeilen(bestand, labelVon, gruppeVon, teile, OFFEN)
  assert.deepEqual([...ohne.klassenSpaeter], [...ohne.klassen], 'ohne Stichtag dieselben Teile')
})

/* ---------- Runde AS: Kundengruppen, Planmengen, reicht es? ---------------- */
import { kundenGruppe, nochZuLiefern, planFuer, type KundePlan } from '../src/auswertung/artikel.ts'

test('Runde AS: die Kundengruppe — gesetzt vor dem Namen; Migros, Coop (auch RVZ), sonst Kleinkunden', () => {
  const gesetzt = new Map([['Hofladen Muster', 'Grosshandel']])
  assert.equal(kundenGruppe('Hofladen Muster', gesetzt), 'Grosshandel')
  assert.equal(kundenGruppe('Migros Prüfstadt', gesetzt), 'Migros')
  assert.equal(kundenGruppe('Coop Genossenschaft', gesetzt), 'Coop')
  assert.equal(kundenGruppe('RVZ Prüfstadt', gesetzt), 'Coop')
  assert.equal(kundenGruppe('RZV Musterdorf', gesetzt), 'Coop')
  assert.equal(kundenGruppe('Scoop Bar', gesetzt), 'Kleinkunden', 'nicht jedes „coop" im Wort ist Coop')
})

const w = (gruppe: string, groesse: 'beide' | 'klein' | 'gross', label: 'beide' | 'D' | 'K') => ({ gruppe, groesse, label })
const plan = (kunde: string, label: string, kg: number, gruppe = 'Knirps', groesse = ''): KundePlan =>
  ({ saison: 2026, kunde, artikelgruppe: gruppe, groesse, label, kg })

test('Runde AS: der Plan gilt genau für seine Wahl; ohne Plan das ganze Vorjahr; bei beiden Labels zählen die Pläne je Label zusammen', () => {
  const vorjahr = (l: 'beide' | 'D' | 'K') => ({ beide: 1000, D: 600, K: 300 })[l]   // 100 kg ohne Label
  assert.deepEqual(planFuer('A', 2026, w('Knirps', 'beide', 'D'), [plan('A', 'D', 800)], vorjahr), { kg: 800, eigen: true })
  assert.deepEqual(planFuer('A', 2026, w('Knirps', 'beide', 'K'), [plan('A', 'D', 800)], vorjahr), { kg: 300, eigen: false })
  assert.deepEqual(planFuer('A', 2026, w('Knirps', 'beide', 'beide'), [plan('A', 'D', 800)], vorjahr), { kg: 800 + 300 + 100, eigen: 'teils' })
  assert.deepEqual(planFuer('A', 2026, w('Knirps', 'beide', 'beide'), [plan('A', 'D', 800), plan('A', 'K', 200)], vorjahr), { kg: 1100, eigen: true })
  assert.deepEqual(planFuer('A', 2026, w('Knirps', 'beide', 'beide'), [plan('A', '', 1500)], vorjahr), { kg: 1500, eigen: true })
  assert.deepEqual(planFuer('A', 2026, w('Knirps', 'klein', 'D'), [plan('A', 'D', 800)], vorjahr), { kg: 600, eigen: false }, 'ein Plan für beide Grössen gilt nicht für klein allein')
  assert.deepEqual(planFuer('A', 2027, w('Knirps', 'beide', 'D'), [plan('A', 'D', 800)], vorjahr), { kg: 600, eigen: false }, 'ein Plan gilt nur für seine Saison')
})

test('Runde AS: noch zu liefern — Plan weniger geliefert, nie unter null, über alle Kunden mit Vorjahr, Lieferung oder Plan', () => {
  const tag = (kunde: string, saison: number, kg: number, label: string | null = 'D', groesse = 'klein') =>
    ({ kunde, saison, gruppe: 'Knirps', groesse, label, kg })
  const kunden = [tag('A', 2025, 1000), tag('A', 2026, 400),          // Plan = Vorjahr 1000 → noch 600
                  tag('B', 2025, 200), tag('B', 2026, 500),           // schon mehr als im Vorjahr → 0, nicht −300
                  tag('C', 2025, 300, 'K')]                           // anderes Label — zählt bei Demeter nicht
  const r = nochZuLiefern(kunden, [plan('N', 'D', 250)], 2026, w('Knirps', 'beide', 'D'))
  assert.equal(r.kg, 600 + 0 + 250)
  assert.deepEqual([...r.jeKunde.keys()].sort(), ['A', 'B', 'N'])
  assert.deepEqual(r.jeKunde.get('B'), { plan: 200, eigen: false, geliefert: 500, offen: 0 })
  assert.equal(nochZuLiefern(kunden, [], 2026, w('Knirps', 'beide', 'beide')).kg, 600 + 0 + 300)
  assert.equal(nochZuLiefern(kunden, [], 2026, w('Knirps', 'beide', 'D'), new Set(['A'])).kg, 600, 'nur die Kunden einer Gruppe')
})

/* ---------- Runde AT: Reihenfolge der Gruppen, Plan einer ganzen Gruppe ----- */
import { gruppenFolge, type GruppePlan } from '../src/auswertung/artikel.ts'

test('Runde AT: die Gruppen in der Reihenfolge des Betriebsleiters, die übrigen nach Menge, Kleinkunden zuletzt', () => {
  const g = [{ name: 'Kleinkunden', menge: 900 }, { name: 'Migros', menge: 500 }, { name: 'Coop', menge: 700 },
             { name: 'Gross', menge: 300 }, { name: 'Vierte', menge: 100 }]
  assert.deepEqual(gruppenFolge(g, []), ['Coop', 'Migros', 'Gross', 'Vierte', 'Kleinkunden'], 'ohne Rang: nach Menge, Kleinkunden zuletzt')
  assert.deepEqual(gruppenFolge(g, [{ gruppe: 'Gross', rang: 1 }, { gruppe: 'Coop', rang: 2 }, { gruppe: 'Migros', rang: 3 }, { gruppe: 'Vierte', rang: 4 }]),
                   ['Gross', 'Coop', 'Migros', 'Vierte', 'Kleinkunden'], 'die Folge des Betriebs')
  assert.deepEqual(gruppenFolge(g, [{ gruppe: 'Vierte', rang: 1 }]), ['Vierte', 'Coop', 'Migros', 'Gross', 'Kleinkunden'], 'nur eine gesetzt: sie zuerst')
  assert.deepEqual(gruppenFolge(g, [{ gruppe: 'Kleinkunden', rang: 1 }]), ['Kleinkunden', 'Coop', 'Migros', 'Gross', 'Vierte'], 'auch Kleinkunden lässt sich setzen')
})

test('Runde AT: ein Plan für die ganze Gruppe gilt als Ganzes — die Kundenpläne darin zählen dann nicht noch einmal', () => {
  const tag = (kunde: string, saison: number, kg: number) => ({ kunde, saison, gruppe: 'Knirps', groesse: 'klein', label: 'D', kg })
  const kunden = [tag('A', 2025, 1000), tag('A', 2026, 400), tag('B', 2025, 500), tag('B', 2026, 100), tag('C', 2025, 200)]
  const von = (k: string) => (k === 'C' ? 'Klein' : 'Gruppe')
  const gp = (gruppe: string, kg: number, label = 'D'): GruppePlan => ({ saison: 2026, gruppe, artikelgruppe: 'Knirps', groesse: '', label, kg })
  // ohne Gruppenplan: die Gruppe ist die Summe ihrer Kunden (A: 1000 − 400, B: 500 − 100)
  const ohne = nochZuLiefern(kunden, [], 2026, w('Knirps', 'beide', 'D'), undefined, { von, plaene: [] })
  assert.deepEqual(ohne.jeGruppe.get('Gruppe'), { plan: 1500, eigen: false, geliefert: 500, offen: 1000, gruppenplan: false })
  assert.equal(ohne.kg, 1000 + 200)
  // mit Gruppenplan 1200: noch 1200 − 500 = 700, auch wenn A einen eigenen Plan hat
  const mit = nochZuLiefern(kunden, [plan('A', 'D', 5000)], 2026, w('Knirps', 'beide', 'D'), undefined, { von, plaene: [gp('Gruppe', 1200)] })
  assert.deepEqual(mit.jeGruppe.get('Gruppe'), { plan: 1200, eigen: true, geliefert: 500, offen: 700, gruppenplan: true })
  assert.equal(mit.kg, 700 + 200, 'der Plan des Kunden A zählt nicht dazu')
  assert.equal(mit.jeKunde.get('A')?.plan, 5000, 'er steht aber beim Kunden')
  // geliefert über dem Gruppenplan: 0, nie darunter
  assert.equal(nochZuLiefern(kunden, [], 2026, w('Knirps', 'beide', 'D'), undefined, { von, plaene: [gp('Gruppe', 300)] }).jeGruppe.get('Gruppe')?.offen, 0)
  // ein Gruppenplan für ein anderes Label gilt hier nicht
  assert.equal(nochZuLiefern(kunden, [], 2026, w('Knirps', 'beide', 'D'), undefined, { von, plaene: [gp('Gruppe', 300, 'K')] }).jeGruppe.get('Gruppe')?.gruppenplan, false)
  // eine Gruppe nur mit Plan, noch ohne Kunden: sie steht da, mit ihrem ganzen Plan
  assert.equal(nochZuLiefern(kunden, [], 2026, w('Knirps', 'beide', 'D'), undefined, { von, plaene: [gp('Neu', 800)] }).jeGruppe.get('Neu')?.offen, 800)
})
