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
import { ARTIKEL_KLASSEN, OFFEN, UNIQUE, alsArtikel, alsUnique, klasseVon, uebersichtszeilen, wahlGeordnet, zeigtUnique, type Wahl } from '../src/auswertung/artikel.ts'
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
const teil = (nr: number, groesse: string, kg: number, artikelgruppe: string | null = null) => ({ charge_nr: nr, groesse, kg, artikelgruppe } as ArtikelLagerCharge)
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

// 0124: „lose" ist zweierlei — eine Artikelgruppe ohne Gewichte ist ein Artikel ohne Grösse;
// eine Sorte ohne Artikelgruppe ist offen (als was sie verkauft wird, weiss niemand).
test('0124: lose mit Artikelgruppe ist ein Artikel, lose ohne Artikelgruppe ist „Artikelgruppe offen" — eine obere Schranke', () => {
  assert.equal(klasseVon('lose', 'Spaghetti'), 'lose')
  assert.equal(klasseVon('lose', null), 'gruppe')
  assert.equal(klasseVon('lose'), 'gruppe')
  assert.equal(klasseVon('dazwischen', 'Knirps'), 'ausserhalb')
  const mitGruppe = alsArtikel(teil(1, 'lose', 100, 'Spaghetti'), new Map([[1, { kanal: 0, faul: 0, verdunstet: 0, fax: 0, marge: 0.05 }]]))
  assert.deepEqual(mitGruppe, { kg: 100, ueberfuellung: 0, offen: false }, 'lose geht nicht in Kisten mit Soll — keine Überfüllung')
  const ohneGruppe = alsArtikel(teil(1, 'lose', 100), new Map([[1, { kanal: 0, faul: 0, verdunstet: 0, fax: 0, marge: 0.05 }]]))
  assert.deepEqual(ohneGruppe, { kg: 100, ueberfuellung: 0, offen: true })
  const [knirps] = uebersichtszeilen(bestand, labelVon, gruppeVon, [...teile, teil(1, 'lose', 5)], OFFEN)
  assert.equal(knirps.klassen.get('gruppe'), 5)
  assert.equal(knirps.vfHoechstens, true, 'die offene Gruppe macht das Verkaufsfähige zur oberen Schranke')
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
  // 0123: dazu die Überfüllung — ohne gewogene Marge (rest ohne marge) wird nichts abgezogen.
  assert.deepEqual(knirps.rest, { kanal: 20, faul: 50, verdunstet: 25, fax: 5, offen: 500, ueberfuellung: 0 },
    'Charge 2 kennt ihr Verkaufsfähiges nicht: ihre 500 kg sind offen, nicht geteilt')
  const r = knirps.rest
  assert.equal(knirps.vf + r.kanal + r.faul + r.verdunstet + r.fax + r.offen, knirps.lager)
  assert.deepEqual(knirps.chargen, [1, 2])
})

// 22. Oktober: „wie viel ist noch hier, im Lager, Anzahl Paletten, auch ohne
// Verdunstung und ohne Palox, und dann wie viel ist verkaufsfähig" — im Lager
// war die liegende Eingangsmasse ohne das Verdunstete und das Faule.
// 23. Oktober, die Regel hat sich geändert und der Test mit ihr: „Im Lager will
// ich, was wirklich steht — Paletten, bevor wir etwas in den Palox schmeissen …
// und vor der Verdunstung." Im Lager ist die liegende Eingangsmasse ohne Abzug;
// Verdunstetes und Faules stehen als Teil davon im Balken.
// Runde AZ: `imLagerHoechstens` (seit dem 23. Oktober immer false) und
// `RestTeile.bekannt` (las niemand) sind weg — die Form, nicht die Regel.
test('Übersicht: im Lager die Eingangsmasse der Paletten, die noch stehen — ohne Abzug; Paletten zusammengezählt', () => {
  const mitPal = bestand.map(b => ({ ...b, n_rest_paletten: b.charge_nr === 1 ? 1 : b.charge_nr === 2 ? 2 : 0 }) as Bestand)
  const rest = new Map([[1, { kanal: 20, faul: 50, verdunstet: 25, fax: 5 }]])
  const [knirps] = uebersichtszeilen(mitPal, labelVon, gruppeVon, teile, OFFEN, { rest })
  // Charge 1: 400, Charge 2: 500 — wie sie eingingen, auch ohne Teilung der Kaskade
  assert.equal(knirps.imLager, 400 + 500, 'die Eingangsmasse hängt an keiner Rate — kein „höchstens"')
  assert.equal(knirps.paletten, 3)
  const r = knirps.rest
  assert.equal(knirps.vf + r.kanal + r.fax + r.faul + r.verdunstet + r.offen, knirps.imLager,
    'im Lager = verkaufsfähig + zu klein/zu gross + Faules (Palox, beim Abpacken) + Verdunstetes + offen')
  assert.equal(knirps.imLager, knirps.lager, 'der Lager-Teil des Balkens ist die liegende Eingangsmasse')
  const [nur1] = uebersichtszeilen(mitPal.filter(b => b.charge_nr === 1), labelVon, gruppeVon, teile, OFFEN, { rest })
  assert.equal(nur1.imLager, 400)
  // Charge 3 hat nichts mehr im Lager — und ohne Zahl bleibt die Palettenzahl leer, nicht 0
  const [, butternut] = uebersichtszeilen(bestand, labelVon, gruppeVon, teile, OFFEN)
  assert.equal(butternut.paletten, null)
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

// 0121 — „was mit Hagelschaden ist … das wird anders verkauft, Unique, wie ein
// eigener Artikel, nur Knospe — eine dritte Kategorie: gross, klein, unique."
// Bis 0136 hiess dieser Test „Unique geht in die Knospe-Zeile der Artikelgruppe, auch von einer Demeter-Charge".
// 0137 — der Betrieb, 9. November: „Ünique zählt nicht als Unterkategorie der anderen Artikel … Ünique soll eine
// Zeile sein und keine Spalte." Die Regel hat sich geändert, der Test mit ihr: eine Hagel-Charge zählt nur noch im
// Ünique-Artikel, nie im Artikel ihrer Sorte — auch nicht in dessen Knospe-Zeile.
test('0137: Ünique ist eine eigene Zeile — die Hagel-Charge zählt nicht mehr bei Knirps, auch nicht als Spalte', () => {
  const rest = new Map([[1, { kanal: 0, faul: 50, verdunstet: 25, fax: 0, unique: 300 }]])
  const hagel = new Set([1])
  const zeilen = uebersichtszeilen(bestand, labelVon, gruppeVon, teile, OFFEN, { rest, hagel })
  assert.deepEqual(zeilen.map(z => `${z.gruppe}|${z.label}`), ['Knirps|D', 'Butternut|K', `${UNIQUE}|null`])
  const knirps = zeilen.find(z => z.gruppe === 'Knirps')!
  const u = zeilen.find(z => z.gruppe === UNIQUE)!
  assert.equal(knirps.n, 1, 'nur Amoro — die Hagel-Charge 1 ist nicht mehr dabei')
  assert.equal(knirps.eingang, 500); assert.equal(knirps.imLager, 500)
  assert.equal(knirps.klassen.get('unique'), undefined, 'keine Spalte Ünique in der Knirps-Zeile')
  assert.equal(knirps.klassen.get('klein'), undefined, 'die Teile der Hagel-Charge zählen nicht bei Knirps')
  assert.ok(!zeilen.some(z => z.gruppe === 'Knirps' && z.label === 'K'), 'keine Knospe-Zeile nur für die Hagelware')
  // die Ünique-Zeile: Eingang, ausgeliefert und Lager der Hagel-Chargen; verkaufsfähig, was sie als Ünique hergeben
  assert.equal(u.n, 1); assert.equal(u.eingang, 1000); assert.equal(u.geliefert, 500); assert.equal(u.imLager, 400)
  assert.equal(u.klassen.get('unique'), 300)
  assert.equal(u.rest.faul + u.rest.verdunstet, 75)
  assert.equal(u.rest.offen, 400 - 300 - 75, 'was im Lager steht und nicht geteilt ist, steht als offen da — nie 0 statt unbekannt')
  assert.equal(u.ausgelagert + u.lager, u.eingang, 'der Balken ist so lang wie der Eingang')
})

test('0137: Ünique gehört zu „alle Artikel" und zu Ünique — nicht zu Knirps, nicht zu einer Grösse, nicht zu Demeter allein', () => {
  const rest = new Map([[1, { kanal: 0, faul: 50, verdunstet: 25, fax: 0, unique: 300 }]])
  const hagel = new Set([1])
  const mit = (w: Wahl) => uebersichtszeilen(bestand, labelVon, gruppeVon, teile, w, { rest, hagel }).map(z => z.gruppe)
  assert.deepEqual(mit({ ...OFFEN, gruppe: UNIQUE }), [UNIQUE])
  assert.deepEqual(mit({ ...OFFEN, gruppe: 'Knirps' }), ['Knirps'])
  assert.ok(!mit({ ...OFFEN, groesse: 'klein' }).includes(UNIQUE), 'Ünique hat keine Grösse')
  assert.ok(!mit({ ...OFFEN, label: 'D' }).includes(UNIQUE), 'Ünique geht als Knospe')
  assert.ok(mit({ ...OFFEN, label: 'K' }).includes(UNIQUE))
  // ohne Hagel-Chargen gibt es keine Ünique-Zeile
  assert.ok(!uebersichtszeilen(bestand, labelVon, gruppeVon, teile, OFFEN, { rest }).some(z => z.gruppe === UNIQUE))
  // Ünique gewählt: Grösse und Label fallen weg
  assert.deepEqual(wahlGeordnet({ gruppe: UNIQUE, groesse: 'klein', label: 'D' }), { gruppe: UNIQUE, groesse: 'beide', label: 'beide' })
  assert.deepEqual(wahlGeordnet({ gruppe: 'Knirps', groesse: 'klein', label: 'D' }), { gruppe: 'Knirps', groesse: 'klein', label: 'D' })
  assert.equal(zeigtUnique({ ...OFFEN, gruppe: 'Knirps' }), false)
})

// Das Beispiel des Betriebs, 9. November: „wir wollen 50 Tonnen Knirps liefern, haben schon 20 t geliefert, also
// sind 30 t noch offen — im Lager hab ich 10 t normale Knirpse und 20 t Hagelware. Du sagst mir jetzt, ich hab
// genug — aber nein!"
test('0137: 50 t Knirps geplant, 20 t geliefert, 10 t Knirps und 20 t Hagelware im Lager — es fehlen 20 t, nicht „reicht"', () => {
  const b = [charge(10, 'Amoro', 30000, 20000, 20000, 10000), charge(11, 'Kaori Kuri', 25000, 0, 0, 20000)]
  const lv = new Map<number, ChargeLabel>([[10, { charge_nr: 10, label: 'D' } as ChargeLabel], [11, { charge_nr: 11, label: 'D' } as ChargeLabel]])
  const tl = [{ charge_nr: 10, groesse: 'klein', kg: 10000, artikelgruppe: 'Knirps', label: 'D' } as ArtikelLagerCharge]
  const rest = new Map([[11, { kanal: 0, faul: 3000, verdunstet: 2000, fax: 0, unique: 20000, marge: 0 }]])
  const knirps: Wahl = { gruppe: 'Knirps', groesse: 'beide', label: 'beide' }
  const z = uebersichtszeilen(b, lv, gruppeVon, tl, knirps, { rest, hagel: new Set([11]) })
  assert.equal(z.length, 1)
  const vf = ARTIKEL_KLASSEN.reduce((a, kl) => a + (z[0].klassen.get(kl) ?? 0), 0)
  assert.equal(vf, 10000, 'verkaufsfähig Knirps sind die 10 t normale Ware — die 20 t Hagelware zählen nicht')
  // der Plan: 50 t für den Kunden, 20 t geliefert; dazu eine Ünique-Lieferung, die nicht als Knirps zählt
  const kunden = [{ kunde: 'Kunde K', saison: 2026, gruppe: 'Knirps', groesse: 'lose', label: 'D', kg: 20000 },
                  { kunde: 'Kunde K', saison: 2026, gruppe: UNIQUE, groesse: 'lose', label: 'K', kg: 5000 }]
  const plaene = [{ saison: 2026, kunde: 'Kunde K', artikelgruppe: 'Knirps', groesse: '', label: '', kg: 50000 }]
  const noch = nochZuLiefern(kunden, plaene, 2026, knirps).kg
  assert.equal(noch, 30000)
  assert.equal(noch - vf, 20000, 'es fehlen 20 t')
  // der Ünique-Artikel für sich: seine Lieferungen und sein Plan
  const uw: Wahl = { gruppe: UNIQUE, groesse: 'beide', label: 'beide' }
  assert.equal(nochZuLiefern(kunden, [{ saison: 2026, kunde: 'Kunde K', artikelgruppe: UNIQUE, groesse: '', label: '', kg: 12000 }], 2026, uw).kg, 7000)
  const u = uebersichtszeilen(b, lv, gruppeVon, tl, uw, { rest, hagel: new Set([11]) })
  assert.deepEqual(u.map(x => [x.gruppe, x.klassen.get('unique')]), [[UNIQUE, 20000]])
})

// 0137: was eine Hagel-Charge als Ünique hergibt — ohne die Überfüllung wie jeder Artikel; nicht gewogen ist höchstens.
test('0137: alsUnique — das Verkaufsfähige der Hagel-Charge ohne Überfüllung; unbekannt bleibt unbekannt', () => {
  const b = charge(11, 'Kaori Kuri', 1000, 0, 0, 600)
  assert.deepEqual(alsUnique(b, new Map([[11, { kanal: 0, faul: 0, verdunstet: 0, fax: 0, unique: 600, marge: 0.2 }]])), { kg: 500, ueberfuellung: 100, offen: false })
  assert.deepEqual(alsUnique(b, new Map([[11, { kanal: 0, faul: 0, verdunstet: 0, fax: 0, unique: 600, marge: null }]])), { kg: 600, ueberfuellung: 0, offen: true })
  assert.equal(alsUnique(charge(12, 'Kaori Kuri', 1000, 0, 0, null)), null, 'ohne Verkaufsfähiges: unbekannt, nicht 0')
  assert.deepEqual(alsUnique(charge(13, 'Kaori Kuri', 1000, 1000, 900, null)), { kg: 0, ueberfuellung: 0, offen: false }, 'nichts im Lager')
})

// 0123 — „verkaufsfähig … minus allem: innerhalb der Artikelgewichte, verschenkte
// Marge abgezogen." Je Charge die Überfüllung a/(1+a) auf dem Teil, der als
// Artikel geht; nicht gewogen heisst höchstens, nicht null.
test('0123: verkaufsfähig ohne Überfüllung — nur auf dem Teil, der als Artikel geht; nicht gewogen ist höchstens', () => {
  const t = (charge_nr: number, groesse: string, kg: number) =>
    ({ charge_nr, sorte: 'Amoro', artikelgruppe: 'Knirps', label: 'D', groesse, kg, stueck: null, g_mittel: null, h: 0, datum: '2026-10-23',
       von_g: null, bis_g: null, stueck_je_kiste: null, kisten: null } as unknown as ArtikelLagerCharge)
  const gewogen = new Map([[1, { kanal: 0, faul: 0, verdunstet: 0, fax: 0, marge: 0.05 }]])
  assert.deepEqual(alsArtikel(t(1, 'klein', 210), gewogen), { kg: 200, ueberfuellung: 10, offen: false })
  assert.deepEqual(alsArtikel(t(1, 'darueber', 50), gewogen), { kg: 50, ueberfuellung: 0, offen: false }, 'was in keinen Artikel passt, geht nicht in Kisten mit Soll')
  const ungewogen = new Map([[1, { kanal: 0, faul: 0, verdunstet: 0, fax: 0, marge: null }]])
  assert.deepEqual(alsArtikel(t(1, 'klein', 210), ungewogen), { kg: 210, ueberfuellung: 0, offen: true })
  assert.equal(alsArtikel(t(1, 'ohne Verteilung', 100), gewogen).offen, true, 'ohne Sortier-CSV ist die Grösse offen')
})

// Runde BA — der Betrieb: „pro Sorte … wie sind die Sortiergrössen bei der
// Sortiermaschine, und wie ist Artikel klein und gross definiert; und dann
// weisst du, was zwar nicht im Palox landet, aber nicht in den Artikeln
// verkauft wird." Die Gramm dazwischen, aus Fassung und Artikelgewichten.
import { grammOhneArtikel, grammText } from '../src/auswertung/artikel.ts'

test('Runde BA: grammOhneArtikel — die Lücken zwischen dem, was die Maschine durchlässt, und den Artikelgewichten', () => {
  const knirps = [{ von_g: 600, bis_g: 1100 }, { von_g: 1100, bis_g: 1600 }]
  const fassung = { verlust_unter: 600, kanal_ab: 2000, kaliber_baender: [[600, 1100], [1100, 1600], [1600, 2000]] as [number, number][] }
  assert.deepEqual(grammOhneArtikel(fassung, knirps), [[1600, 2000]], 'über dem grössten Artikel, unter „zu gross"')
  assert.equal(grammText(grammOhneArtikel(fassung, knirps)), '1600–2000 g')
  const mitLuecke = [{ von_g: 700, bis_g: 1100 }, { von_g: 1200, bis_g: 2000 }]
  assert.deepEqual(grammOhneArtikel(fassung, mitLuecke), [[600, 700], [1100, 1200]], 'darunter und dazwischen')
  assert.deepEqual(grammOhneArtikel(fassung, [{ von_g: 500, bis_g: 2500 }]), [], 'die Artikel decken alles — nichts dazwischen')
  assert.equal(grammText([]), '—')
  assert.deepEqual(grammOhneArtikel(fassung, []), [[600, 2000]], 'ohne Artikelgewichte ist das ganze Fenster die Lücke')
  assert.equal(grammOhneArtikel(null, knirps), null, 'ohne Fassung nicht zu sagen')
  assert.equal(grammText(null), 'keine Fassung der Sortiermaschine')
  assert.deepEqual(grammOhneArtikel({ verlust_unter: null, kanal_ab: null, kaliber_baender: [[600, 1100], [1100, 1600]] }, knirps), [],
    'ohne Grenzen gilt das Fenster der Bänder')
  assert.equal(grammOhneArtikel({ verlust_unter: null, kanal_ab: null, kaliber_baender: null }, knirps), null, 'Kisten-Fassung ohne Bänder: kein Fenster')
})

/* ---------- Runde BJ: woher die Planzahl kommt ---------- */
import { planTeile, teileSumme } from '../src/auswertung/artikel.ts'

// Der Betrieb, 7. November: „einen Weg finden, damit man schnell erkennt, woher die Zahl kommt — ob selbst
// eingetragen oder Planmenge vom Verkauf vom Vorjahr". selbst + vorjahr ist immer der Plan.
test('Runde BJ: die Teile einer Planzahl — selbst eingetragen (mit Tag), aus dem Vorjahr, oder beides', () => {
  const vorjahr = (l: 'beide' | 'D' | 'K') => ({ beide: 1000, D: 600, K: 300 })[l]
  const p = (kunde: string, label: string, kg: number, ts: string | null): KundePlan => ({ ...plan(kunde, label, kg), ts })
  const am = '2026-10-22T08:00:00Z'
  assert.deepEqual(planTeile('A', 2026, w('Knirps', 'beide', 'D'), [p('A', 'D', 800, am)], vorjahr), { selbst: 800, vorjahr: 0, ts: am })
  assert.deepEqual(planTeile('A', 2026, w('Knirps', 'beide', 'K'), [p('A', 'D', 800, am)], vorjahr), { selbst: 0, vorjahr: 300, ts: null })
  assert.deepEqual(planTeile('A', 2026, w('Knirps', 'beide', 'beide'), [p('A', 'D', 800, am)], vorjahr), { selbst: 800, vorjahr: 300 + 100, ts: am })
  const faelle: [ReturnType<typeof w>, KundePlan[]][] = [
    [w('Knirps', 'beide', 'beide'), [p('A', 'D', 800, null)]], [w('Knirps', 'beide', 'beide'), [p('A', 'D', 800, null), p('A', 'K', 200, am)]],
    [w('Knirps', 'beide', 'D'), []], [w('Knirps', 'klein', 'D'), [p('A', 'D', 800, null)]]]
  for (const [wahl, pl] of faelle) {
    const t = planTeile('A', 2026, wahl, pl, vorjahr), f = planFuer('A', 2026, wahl, pl, vorjahr)
    assert.equal(t.selbst + t.vorjahr, f.kg, 'die Teile ergeben den Plan')
    assert.equal(t.selbst > 0, f.eigen !== false, 'selbst eingetragen heisst eigen')
  }
  assert.deepEqual(teileSumme([{ selbst: 5000, vorjahr: 0, ts: '2026-10-22T08:00:00Z' }, { selbst: 0, vorjahr: 37200, ts: null },
                               { selbst: 0, vorjahr: 1000, ts: '2026-09-01T08:00:00Z' }]),
                   { selbst: 5000, vorjahr: 38200, ts: '2026-10-22T08:00:00Z' }, 'der jüngste Tag eines Eintrags')
})

test('Runde BJ: noch zu liefern trägt die Teile je Kunde und je Gruppe — ein Gruppenplan ist ganz selbst eingetragen', () => {
  const tag = (kunde: string, saison: number, kg: number) => ({ kunde, saison, gruppe: 'Knirps', groesse: 'klein', label: 'D', kg })
  const kunden = [tag('A', 2025, 1000), tag('A', 2026, 400), tag('B', 2025, 500), tag('B', 2026, 100)]
  const von = () => 'Gruppe'
  const ohne = nochZuLiefern(kunden, [plan('A', 'D', 700)], 2026, w('Knirps', 'beide', 'D'), undefined, { von, plaene: [] })
  assert.deepEqual(ohne.teile.kunde.get('A'), { selbst: 700, vorjahr: 0, ts: null })
  assert.deepEqual(ohne.teile.kunde.get('B'), { selbst: 0, vorjahr: 500, ts: null })
  assert.deepEqual(ohne.teile.gruppe.get('Gruppe'), { selbst: 700, vorjahr: 500, ts: null }, 'ohne Gruppenplan: die Teile der Kunden zusammen')
  const gp: GruppePlan = { saison: 2026, gruppe: 'Gruppe', artikelgruppe: 'Knirps', groesse: '', label: 'D', kg: 5000, ts: '2026-10-22T08:00:00Z' }
  const mit = nochZuLiefern(kunden, [], 2026, w('Knirps', 'beide', 'D'), undefined, { von, plaene: [gp] })
  assert.deepEqual(mit.teile.gruppe.get('Gruppe'), { selbst: 5000, vorjahr: 0, ts: '2026-10-22T08:00:00Z' })
})
