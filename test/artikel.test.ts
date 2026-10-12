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
