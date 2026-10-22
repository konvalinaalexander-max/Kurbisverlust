import { test } from 'node:test'
import assert from 'node:assert/strict'
import { ausZeile, ungereimtheiten, vonCharge, FALSCHE_SPALTEN } from '../src/auswertung/ungereimt.ts'
import type { PerigonPruefung, UngereimtZeile } from '../src/auswertung/daten.ts'

// 0121 — der Betrieb: „so etwas wie 1627 — das hat Ausgang, aber keinen
// Eingang — weis in der App auffällig darauf hin … so, dass ich als Laie die
// Problematik erkenne, zu meinem Chef gehen kann und sagen: schau, das macht
// keinen Sinn." Je Sache drei Sätze — was, warum, was tun —, das Schwerste zuerst.

const zeile = (art: UngereimtZeile['art'], x: Partial<UngereimtZeile> = {}): UngereimtZeile =>
  ({ art, charge_nr: 1627, sorte: 'Fictor', schlag: 'Agasul Rüegg', kg: 1416, n: 3, von: '2026-09-23', bis: '2026-10-05', mehr: null, ...x })
const pp = (art: string, charge_nr: number | null, kg: number | null): PerigonPruefung =>
  ({ art, quelle: 'A', pos_id: Math.round(Math.random() * 1e6), datum: '2026-10-09', kunde: null, artikel: 'Knirps', charge_nr, kg, befund: 'befund' })

test('Verkauft, nie eingegangen: rot, mit Charge, Kilo und den drei Sätzen', () => {
  const u = ausZeile(zeile('ohne_eingang'), [])
  assert.equal(u.schwere, 'rot')
  assert.equal(u.charge_nr, 1627)
  assert.equal(u.kg, 1416)
  assert.match(u.titel, /1627 \(Agasul Rüegg · Fictor\) hat verkauft, aber nie etwas bekommen/)
  assert.match(u.was, /3 Lieferscheine mit 1.416 kg/)
  assert.match(u.was, /keine einzige Palette/)
  assert.ok(u.warum.length > 0 && u.tun.length > 0)
})

test('Vor dem Eingang: die Perigon-Zeilen derselben Charge gehören dazu; ab 500 kg rot', () => {
  const zeilen = [pp('Lieferung vor dem Eingang', 1626, 400), pp('Lieferung vor dem Eingang', 1611, 10)]
  const u = ausZeile(zeile('vor_eingang', { charge_nr: 1626, kg: 7156, mehr: { erster_eingang: '2026-09-23' } }), zeilen)
  assert.equal(u.schwere, 'rot')
  assert.equal(u.zeilen.length, 1)
  assert.match(u.was, /23\.09\.2026/)
  assert.equal(ausZeile(zeile('vor_eingang', { charge_nr: 1637, kg: 176, mehr: { erster_eingang: '2026-10-22' } }), []).schwere, 'gelb')
})

test('Ohne Charge: verteilt auf die Chargen der Sorte; was vor dem Eingang liegt, wird gesagt', () => {
  const u = ausZeile(zeile('ohne_charge', { charge_nr: null, sorte: 'Tiana', kg: 2508, n: 13,
    mehr: { kg_vor_eingang: 600, kg_ohne_ziel: 0, verteilt_auf: [{ charge_nr: 1611, kg: 751 }, { charge_nr: 1626, kg: 1757 }] } }), [])
  assert.equal(u.schwere, 'rot', '600 kg auf Chargen, die noch nicht da waren')
  assert.match(u.titel, /13 Lieferscheine Tiana ohne Chargennummer/)
  assert.match(u.was, /2 Chargen dieser Sorte \(am meisten: 1626 1\.8 t, 1611 751 kg\)/)
  assert.match(u.was, /600 kg davon fallen auf Chargen, die damals noch gar nicht da waren/)
  const keine = ausZeile(zeile('ohne_charge', { charge_nr: null, sorte: 'Neu', kg: 50, n: 1, mehr: { kg_vor_eingang: 0, kg_ohne_ziel: 50, verteilt_auf: null } }), [])
  assert.match(keine.was, /Keine Charge dieser Sorte hat Eingang/)
})

test('Umgebucht ist Auskunft (info), Vorschlag ist gelb — beide kennen ihre Paletten und die Charge, von der sie kommen', () => {
  const mehr = { von_charge_nr: 1625, auftrag_id: 1602, grund: '5 von 5 Zetteln passen', paletten: [7964, 7965] }
  const um = ausZeile(zeile('umgebucht', { kg: 2012, n: 6, von: '2026-09-23', bis: '2026-09-23', mehr }), [])
  assert.equal(um.schwere, 'info')
  assert.deepEqual(um.paletten, [7964, 7965])
  assert.equal(um.von_charge_nr, 1625)
  assert.match(um.titel, /6 Paletten von Charge 1625 zählt die App bei Charge 1627/)
  const vor = ausZeile(zeile('vorschlag', { charge_nr: 1626, kg: 2136, n: 6, mehr: { ...mehr, von_charge_nr: 1623 } }), [])
  assert.equal(vor.schwere, 'gelb')
  assert.match(vor.warum, /bucht nichts um/)
})

test('Alles zusammen: das Schwerste und Grösste zuerst; Perigon-Zeilen je Art eine Sache, „vor dem Eingang" bei der Charge', () => {
  const liste = ungereimtheiten(
    [zeile('umgebucht', { kg: 2012, mehr: { von_charge_nr: 1625 } }), zeile('ueberzaehlung', { charge_nr: 1630, kg: 4508, mehr: { eingang_kg: 19318, geliefert_kg: 15735, ausgelagert_kg: 23826 } }),
     zeile('ohne_eingang')],
    [pp('Charge nicht zugeordnet', null, 300), pp('Charge nicht zugeordnet', null, 200), pp('Lieferung vor dem Eingang', 1637, 176)])
  assert.deepEqual(liste.map(u => u.art), ['ueberzaehlung', 'ohne_eingang', 'Charge nicht zugeordnet', 'umgebucht'])
  assert.equal(liste.find(u => u.art === 'Charge nicht zugeordnet')?.kg, 500)
  assert.equal(liste.filter(u => u.art === 'Lieferung vor dem Eingang').length, 0)
  assert.deepEqual(vonCharge(liste, 1625).map(u => u.art), ['umgebucht'], 'die Charge, von der umgebucht wurde, sieht die Umbuchung')
})

test('Die rot umrandeten Spalten heissen wie in der Datei', () => {
  assert.deepEqual(FALSCHE_SPALTEN['Charge nicht zugeordnet'], ['AuftragsChargeManuell'])
  assert.ok(FALSCHE_SPALTEN['Teil ohne Charge'].includes('AufPosBatchQuantity Charge'))
})
