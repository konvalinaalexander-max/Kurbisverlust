import { test } from 'node:test'
import assert from 'node:assert/strict'
import { ART_NAME, ausZeile, spanneKurz, spurText, ungereimtheiten, vonCharge, FALSCHE_SPALTEN } from '../src/auswertung/ungereimt.ts'
import type { ChargeSpur, PerigonPruefung, UngereimtZeile } from '../src/auswertung/daten.ts'

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

// 0122 — der Betrieb, 23. Oktober: „Aktuell ist noch nicht ganz klar, was jetzt
// von welcher Charge war … was hast du schon umgebucht, was noch nicht, was
// würdest du wie umbuchen." Jede Sache sagt ihren Stand und, wo es einen gibt,
// einen Vorschlag; darunter steht der Weg der Ware je beteiligter Charge.

const kandidat = (charge_nr: number, x: Record<string, unknown> = {}) => ({ charge_nr, schlag: 'Oettli', sorte: 'Kaori Kuri', rest_paletten: 60,
  eingang_kg: 17381, geliefert_kg: 613, eingang_von: '2026-10-02', gleicher_schlag: false, gleiche_sorte: true, ...x })

test('Mehr verkauft als möglich: Stand „noch nicht umgebucht", Vorschlag nennt die Charge, von der es wohl kam', () => {
  const u = ausZeile(zeile('ueberzaehlung', { charge_nr: 1630, sorte: 'Kaori Kuri', kg: 1897, mehr: { eingang_kg: 19318, geliefert_kg: 15735, ausgelagert_kg: 21215,
    kandidaten: [kandidat(1719), kandidat(1628, { schlag: 'Agasul Baumann', rest_paletten: 48 }), kandidat(1598, { schlag: 'Illnau Bruno' })] } }), [])
  assert.match(u.stand, /^Noch nicht umgebucht/)
  assert.match(u.vorschlag, /^Am ehesten von 1719 \(Oettli · Kaori Kuri\) — dieselbe Sorte; dort stehen laut App noch ≈ 60 Paletten, verkauft ist erst 613 kg von 17\.4 t\./)
  assert.match(u.vorschlag, /Sonst 1628 \(Agasul Baumann · Kaori Kuri\), 1598 \(Illnau Bruno · Kaori Kuri\)\./)
  assert.match(u.vorschlag, /Zählen: Fehlen dort Paletten für etwa 1.897 kg/)
  assert.deepEqual(u.beteiligt, [1630, 1719, 1628], 'die Charge selbst und die zwei ersten Kandidaten zeigen ihren Weg')
  assert.deepEqual(vonCharge([u], 1719), [], 'ein Kandidat hat nichts falsch gemacht — die Sache steht nicht bei ihm')
  assert.match(ausZeile(zeile('ohne_eingang', { mehr: { kandidaten: [kandidat(99126, { geliefert_kg: 0, eingang_kg: 2600 })] } }), []).vorschlag,
    /von 2\.6 t ist noch nichts verkauft\./, 'nicht „erst 0 kg"')
  const ohne = ausZeile(zeile('ohne_eingang', { mehr: { kandidaten: null } }), [])
  assert.match(ohne.vorschlag, /Keine andere Charge desselben Artikels/)
})

test('Umgebucht sagt „schon umgebucht" und von wem; ein Vorschlag sagt „noch nicht" und was die App täte', () => {
  const mehr = { von_charge_nr: 1625, auftrag_id: 1602, grund: '5 von 5 Zetteln passen', paletten: [7964, 7965], von_betriebsleiter: true }
  const um = ausZeile(zeile('umgebucht', { kg: 2012, n: 6, mehr }), [])
  assert.match(um.stand, /^Schon umgebucht — vom Betriebsleiter bestätigt\. Die 6 Paletten zählen bei 1627; im Erntejournal stehen sie weiter unter 1625\./)
  assert.deepEqual(um.beteiligt, [1625, 1627])
  assert.match(ausZeile(zeile('umgebucht', { kg: 2012, n: 6, mehr: { ...mehr, von_betriebsleiter: false } }), []).stand, /von der App, weil der Beleg reicht/)
  const vor = ausZeile(zeile('vorschlag', { charge_nr: 1626, kg: 2136, n: 6, mehr: { ...mehr, von_charge_nr: 1623 } }), [])
  assert.match(vor.stand, /^Noch nicht umgebucht — die 6 Paletten zählen weiter bei 1623\./)
  assert.match(vor.vorschlag, /Die 6 Paletten \(2.136 kg\) von 1623 zu 1626 umbuchen, wenn beim Nachzählen bei 1623 so viele fehlen\./)
})

test('Über den Produzenten zugeordnet: Auskunft mit Grund; der Knopf trägt die Nummer ein, solange sie fehlt', () => {
  const grund = 'Die Nummer 198977 steht an keiner Charge. Perigon nennt als Produzent Sauter — das ist Rümlang Sauter —, und Rümlang Sauter hat genau eine Charge mit Butternut: 1650.'
  const u = ausZeile(zeile('nachgeordnet', { charge_nr: 1650, sorte: 'Tiana', schlag: 'Rümlang Sauter', kg: 1650, n: 11,
    mehr: { nummern: ['198977'], produzent: 'Sauter', grund, perigon_nr: 198976 } }), [])
  assert.equal(u.schwere, 'info')
  assert.match(u.titel, /^11 Lieferscheine mit der Nummer 198977 zählt die App bei Charge 1650 \(Rümlang Sauter · Tiana\)/)
  assert.equal(u.was, grund)
  assert.match(u.stand, /noch nicht fest/)
  assert.match(u.vorschlag, /Bei 1650 steht heute die Perigon-Nr\. 198976, Perigon schreibt 198977/)
  assert.deepEqual(u.perigonSetzen, { charge_nr: 1650, perigon_nr: 198977 })
  const zwei = ausZeile(zeile('nachgeordnet', { charge_nr: 1650, mehr: { nummern: ['198977', '198978'], grund } }), [])
  assert.equal(zwei.perigonSetzen, undefined, 'zwei Nummern — welche gilt, entscheidet der Betriebsleiter')
  assert.equal(ART_NAME.nachgeordnet, 'Über den Produzenten zugeordnet')
})

test('Chargenregister: dieselbe Perigon-Nummer an zwei Chargen — bei beiden sichtbar, mit Vorschlag aus der verwandten Nummer', () => {
  const mehr = { pruefung: 'perigon_doppelt', perigon_nr: 198976, chargen_nr: [1649, 1650], zeilen_mit_nummer: 0,
    chargen: [{ charge_nr: 1649, schlag: 'Rümlang Sauter', sorte: 'Butterkin' }, { charge_nr: 1650, schlag: 'Rümlang Sauter', sorte: 'Tiana' }],
    verwandte: [{ nummer: '198977', n: 11, produzent: 'Sauter', gruppe: 'Butternut', charge_nr: 1650 }] }
  const u = ausZeile(zeile('stammdaten', { charge_nr: 1649, sorte: 'Butterkin', schlag: 'Rümlang Sauter', kg: null, n: 2, mehr }), [])
  assert.equal(u.schwere, 'gelb', 'die Nummer kommt in keiner Datei vor — es fehlt (noch) keine Ware')
  assert.equal(u.titel, 'Perigon-Nr. 198976 steht an 2 Chargen: 1649 und 1650')
  assert.match(u.was, /1649 \(Rümlang Sauter · Butterkin\) und 1650 \(Rümlang Sauter · Tiana\) dieselbe Perigon-Nummer 198976/)
  assert.match(u.was, /kommt 198976 nicht vor\. Dafür stehen dort Nummern, die an keiner Charge stehen, aber dazu passen: 198977 \(11 Zeilen, Produzent Sauter, Butternut — die App zählt sie bei 1650\)/)
  assert.match(u.vorschlag, /^Wohl hat 1650 die Nummer 198977: .* Dann bei 1650 198977 eintragen; 1649 behält 198976\./)
  assert.deepEqual(u.perigonSetzen, { charge_nr: 1650, perigon_nr: 198977 })
  assert.match(u.stand, /ändert nur der Betriebsleiter/)
  assert.deepEqual(vonCharge([u], 1650).length, 1, 'die zweite Charge sieht die Sache auch')
  assert.equal(ausZeile(zeile('stammdaten', { charge_nr: 1649, mehr: { ...mehr, zeilen_mit_nummer: 4 } }), []).schwere, 'rot',
    'stehen Lieferscheine mit der Nummer da, zählen sie bei keiner Charge')
  const ohneTreffer = ausZeile(zeile('stammdaten', { charge_nr: 1649, mehr: { ...mehr, verwandte: null } }), [])
  assert.equal(ohneTreffer.vorschlag, '')
  assert.equal(ohneTreffer.perigonSetzen, undefined)
})

test('Chargenregister: ohne Perigon-Nummer und ein Schlag unter zwei Namen', () => {
  const ohne = ausZeile(zeile('stammdaten', { charge_nr: 1763, sorte: 'Amoro', schlag: 'Trüeb', kg: null, n: 1,
    mehr: { pruefung: 'ohne_perigon_nr', chargen_nr: [1763], paletten: 3, lieferscheine: 0 } }), [])
  assert.match(ohne.titel, /Charge 1763 \(Trüeb · Amoro\) hat keine Perigon-Nummer/)
  assert.match(ohne.was, /hat 3 Paletten, aber im Register keine Perigon-Nummer/)
  const zwei = ausZeile(zeile('stammdaten', { charge_nr: 1764, kg: null, n: 1, mehr: { pruefung: 'schlag_zweimal', chargen_nr: [1764], name: 'Trüb', gemeint: 'Trüeb' } }), [])
  assert.equal(zwei.titel, 'Schlag „Trüb" ist „Trüeb"')
  assert.match(zwei.was, /es gibt nur einen/)
  assert.match(zwei.vorschlag, /„Trüb" in „Trüeb" ändern/)
})

const spur = (x: Partial<ChargeSpur> = {}): ChargeSpur => ({ charge_nr: 1626, schlag: 'Agasul Rüegg', sorte: 'Tiana', artikelgruppe: 'Butternut',
  journal_paletten: 12, journal_kg: 4863, journal_von: '2026-08-28', journal_bis: '2026-08-31', paletten: 12, eingang_kg: 4863,
  weg: null, her: null, arbeiten: 3, arbeit_von: '2026-09-02', arbeit_bis: '2026-09-22',
  arbeit_liste: [{ id: 1, datum: '2026-09-02', station: 'waschen', zettel: 4 }, { id: 2, datum: '2026-09-10', station: 'sortieren', zettel: 3 }, { id: 3, datum: '2026-09-22', station: 'waschen', zettel: 2 }],
  lieferscheine: 21, geliefert_kg: 7444, lief_von: '2026-09-02', lief_bis: '2026-09-22', nach_artikel: [{ gruppe: 'Butternut', kg: 7444 }],
  nachgeordnet: null, rest_paletten: 0.4, ...x })

test('Der Weg der Ware: herein, bearbeitet, hinaus und noch da — in kurzen Zeilen', () => {
  const t = spurText(spur())
  assert.equal(t.charge, '1626 · Agasul Rüegg · Tiana')
  assert.deepEqual(t.herein, ['12 Paletten · 4.9 t', '28.8.–31.8.'])
  assert.deepEqual(t.bearbeitet, ['2× Waschen, 1× Sortieren', '2.9.–22.9.'])
  assert.deepEqual(t.hinaus, ['21 Lieferscheine · 7.4 t', '2.9.–22.9.'])
  assert.equal(t.noch, '≈ 0 Paletten')
  assert.equal(t.ohneEingang, false)
})

test('Der Weg der Ware: umgebucht und vorgeschlagen beim Eingang, fremder Artikel und Produzent beim Ausgang, Lücken als Lücken', () => {
  const t = spurText(spur({ charge_nr: 1625, journal_paletten: 6, paletten: 0,
    weg: [{ charge_nr: 1627, stand: 'angewandt', paletten: 6, kg: 2012 }], her: [{ charge_nr: 1611, stand: 'vorschlag', paletten: 1, kg: 400 }],
    nach_artikel: [{ gruppe: 'Butternut', kg: 900 }, { gruppe: 'Mix', kg: 300 }, { gruppe: 'Kabocha', kg: 120 }],
    nachgeordnet: [{ weg: 'produzent', n: 11, kg: 1650 }], rest_paletten: null }))
  assert.ok(t.herein.includes('→ 6 Paletten zu 1627 umgebucht'))
  assert.ok(t.herein.includes('← 1 Palette von 1611 wohl hierher (nicht umgebucht)'))
  assert.ok(t.herein.includes('die App zählt 0 Paletten'))
  assert.ok(t.hinaus.includes('davon als Kabocha 120 kg'), 'Mix ist gemischt, nicht fremd')
  assert.ok(t.hinaus.includes('11 davon über den Produzenten zugeordnet'))
  assert.equal(t.noch, 'unbekannt', 'ohne Rechnung ist der Rest unbekannt, nicht 0')
  const leer = spurText(spur({ journal_paletten: 0, paletten: 0, journal_kg: null, journal_von: null, journal_bis: null, arbeiten: 0, arbeit_liste: null, lieferscheine: 0, geliefert_kg: null }))
  assert.deepEqual(leer.herein, ['keine Palette im Journal'])
  assert.deepEqual(leer.bearbeitet, ['keine Arbeit'])
  assert.deepEqual(leer.hinaus, ['kein Lieferschein'])
  assert.equal(leer.ohneEingang, false, 'nichts herein und nichts hinaus ist keine Ungereimtheit')
  assert.equal(spurText(spur({ journal_paletten: 0, paletten: 0 })).ohneEingang, true, 'verkauft ohne Eingang ist es')
  assert.ok(spurText(spur({ nach_artikel: [{ gruppe: 'andere', kg: 50 }] })).hinaus.includes('davon als anderer Artikel 50 kg'))
  // 0124: eine Lieferung ohne Perigon-Zeile (von Hand erfasst) ist ein eigener Teil, kein fremder Artikel
  const hand = spurText(spur({ nach_artikel: [{ gruppe: 'Butternut', kg: 7000 }, { gruppe: 'ohne Perigon-Zeile', kg: 444 }] })).hinaus
  assert.ok(hand.includes('444 kg davon ohne Perigon-Zeile (von Hand erfasst)'), hand.join(' | '))
  assert.ok(!hand.some(h => h.startsWith('davon als')), 'nicht als fremder Artikel genannt')
  assert.equal(spanneKurz('2026-10-02', '2026-10-02'), '2.10.')
  assert.equal(spanneKurz(null, null), '')
})

