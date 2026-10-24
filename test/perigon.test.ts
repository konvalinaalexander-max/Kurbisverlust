import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  PERIGON_ART, ART_FOLGE, aehnlicheNummer, aufgaben, filtern, FILTER_LEER, istOffen, jeSorte, lageInZahlen, nachArt,
  schnappschussText, spaltenZeichen, standVon,
} from '../src/auswertung/perigon.ts'
import { ART_NAME, ausZeile, ungereimtheiten, vonCharge, FALSCHE_SPALTEN } from '../src/auswertung/ungereimt.ts'
import type { ChargeSpur, PerigonBefund, PerigonVerlauf, UngereimtZeile } from '../src/auswertung/daten.ts'

// 0126 — der Betrieb: „mach einen neuen Reiter und behandle dort die
// Ungereimtheiten mit viel Detail, mit viel Rückverfolgbarkeit … dass man sie
// anklicken und dann auch mitverfolgen kann." Und: „alles, was du im PDF hast,
// dort in den Reiter — das mit 1719 etc."

const fall = (art: PerigonBefund['art'], x: Partial<PerigonBefund> = {}): PerigonBefund => ({
  schluessel: `${art}:A:${x.pos_id ?? 1}`, art, schwere: 'gelb', quelle: 'A', pos_id: 1, datum: '2026-10-09', kunde: 'K', artikel: 'Bio Kürbis roter Knirps Knospe',
  einheit: 'kg', menge: 100, gewicht_je_artikel: 0, preisgruppe: 'K', liefer_label: 'K', kg_position: 100, kg_zugeteilt: 0, kg_rechnung: 100,
  kg_ohne_charge: 100, kg: 100, nummern: null, nummer: null, lauf_nr: null, charge_nr: null, sorte: 'Kaori Kuri', n_zeilen: 1, satz: 'Satz', tun: 'Tun',
  wo: 'perigon', eingelesen: null, ...x,
})
const vermerkt = (schluessel: string, stand: PerigonVerlauf['stand'], x: Partial<PerigonVerlauf> = {}): PerigonVerlauf => ({
  schluessel, ebene: 'zeile', art: null, erst_gesehen: null, zuletzt_gesehen: null, weg_seit: null, schnappschuss: null,
  stand, notiz: null, vermerk_ts: null, vermerk_von: null, n_vermerke: 1, ...x,
})
const zeile = (art: UngereimtZeile['art'], x: Partial<UngereimtZeile> = {}): UngereimtZeile =>
  ({ art, charge_nr: 1630, sorte: 'Kaori Kuri', schlag: 'Rümlang', kg: 1897, n: 3, von: '2026-09-15', bis: '2026-10-20', mehr: null, ...x })
const spur = (charge_nr: number, x: Partial<ChargeSpur> = {}): ChargeSpur => ({
  charge_nr, schlag: 'Schlag', sorte: 'Kaori Kuri', artikelgruppe: 'Knirps', journal_paletten: 0, journal_kg: null, journal_von: null, journal_bis: null,
  paletten: 0, eingang_kg: null, weg: null, her: null, arbeiten: 0, arbeit_von: null, arbeit_bis: null, arbeit_liste: null,
  lieferscheine: 0, geliefert_kg: null, lief_von: null, lief_bis: null, nach_artikel: null, nachgeordnet: null, rest_paletten: null, ...x,
})

test('Jede Art sagt, was sie heisst, wo man sie in der Datei sieht, was die App macht, was zu tun ist und wo', () => {
  for (const art of ART_FOLGE) {
    const i = PERIGON_ART[art]
    assert.ok(i.name && i.heisst && i.datei && i.app && i.tun && i.spalten.length > 0, art)
  }
  assert.equal(ART_FOLGE.length, Object.keys(PERIGON_ART).length, 'jede Art steht in der Folge des Reiters')
  assert.equal(PERIGON_ART.menge_null.wo, 'perigon')
  assert.equal(PERIGON_ART.unbekannt.wo, 'stammdaten')
  assert.equal(PERIGON_ART.nachholen.wo, 'nichts')
  assert.equal(PERIGON_ART.mix.wo, 'firma')
})

test('Die Buchstaben der Spalten sind die der Datei (Q Menge, S je Charge, W Charge, AD Position, AE Gewicht)', () => {
  assert.equal(spaltenZeichen('AuftragsArtikelMenge'), 'Q')
  assert.equal(spaltenZeichen('AufPosBatchQuantity Charge'), 'S')
  assert.equal(spaltenZeichen('AuftragsChargeManuell'), 'W')
  assert.equal(spaltenZeichen('AufPosId'), 'AD')
  assert.equal(spaltenZeichen('GewichtProArtikel'), 'AE')
  assert.equal(spaltenZeichen('gibt es nicht'), null)
  assert.deepEqual(FALSCHE_SPALTEN.menge_null, PERIGON_ART.menge_null.spalten, 'das Fenster umrandet die Spalten der Art rot')
})

test('Offen ist, was nicht nur Auskunft ist und weder erledigt noch „kein Fehler" heisst', () => {
  assert.equal(istOffen('rot', 'offen'), true)
  assert.equal(istOffen('gelb', 'in_abklaerung'), true)
  assert.equal(istOffen('gelb', 'erledigt'), false)
  assert.equal(istOffen('rot', 'kein_fehler'), false)
  assert.equal(istOffen('info', 'offen'), false)
  const v = new Map([['x', vermerkt('x', 'erledigt')]])
  assert.equal(standVon(v, 'x'), 'erledigt')
  assert.equal(standVon(v, 'y'), 'offen', 'ohne Vermerk ist ein Fall offen')
})

test('Je Art: das Schwerste und Grösste zuerst, mit den offenen Fällen und der Masse (eine Abweichung nach unten zählt wie nach oben)', () => {
  const faelle = [
    fall('mix', { pos_id: 1, kg: 288 }), fall('mix', { pos_id: 2, kg: 300 }),
    fall('menge_null', { pos_id: 3, schwere: 'rot', kg: 1722 }),
    fall('masse_abweichung', { pos_id: 4, kg: -45 }),
    fall('ohne_gewicht', { pos_id: 5, kg: null }),
  ]
  const v = new Map([['mix:A:2', vermerkt('mix:A:2', 'kein_fehler')]])
  const g = nachArt(faelle, v)
  assert.deepEqual(g.map(x => x.art), ['menge_null', 'mix', 'masse_abweichung', 'ohne_gewicht'])
  const mix = g.find(x => x.art === 'mix')!
  assert.equal(mix.offen, 1, 'der als „kein Fehler" vermerkte zählt nicht als offen')
  assert.equal(mix.kg, 588)
  assert.deepEqual(mix.faelle.map(f => f.pos_id), [2, 1], 'innerhalb der Art die grössten zuerst')
  assert.equal(g.find(x => x.art === 'masse_abweichung')!.kg, 45)
  assert.equal(g.find(x => x.art === 'ohne_gewicht')!.kg, null, 'ohne Masse bleibt sie unbekannt, nie 0')
})

test('Filtern nach Stand, Art, Sorte, Charge (auch die genannte Nummer) und Suche', () => {
  const faelle = [
    fall('menge_null', { pos_id: 134747, nummern: '1648, 1719', kunde: 'Nordmarkt' }),
    fall('zu_viel', { pos_id: 134779, nummern: '1620', charge_nr: 1620, sorte: 'Orangita' }),
    fall('nachholen', { pos_id: 9, schwere: 'info' }),
  ]
  const v = new Map([['zu_viel:A:134779', vermerkt('zu_viel:A:134779', 'erledigt')]])
  assert.deepEqual(filtern(faelle, v, FILTER_LEER).map(f => f.pos_id), [134747], 'offen: weder erledigt noch Auskunft')
  assert.deepEqual(filtern(faelle, v, { ...FILTER_LEER, stand: 'erledigt' }).map(f => f.pos_id), [134779])
  assert.equal(filtern(faelle, v, { ...FILTER_LEER, stand: 'alle' }).length, 3)
  assert.deepEqual(filtern(faelle, v, { ...FILTER_LEER, stand: 'alle', charge: 1719 }).map(f => f.pos_id), [134747], 'die genannte Nummer zählt wie die Charge')
  assert.deepEqual(filtern(faelle, v, { ...FILTER_LEER, stand: 'alle', sorte: 'Orangita' }).map(f => f.pos_id), [134779])
  assert.deepEqual(filtern(faelle, v, { ...FILTER_LEER, stand: 'alle', suche: 'nordm' }).map(f => f.pos_id), [134747])
  assert.deepEqual(filtern(faelle, v, { ...FILTER_LEER, stand: 'alle', suche: '134779' }).map(f => f.pos_id), [134779], 'die Position aus der Datei findet ihren Fall')
})

test('Je Sorte, wie im Bericht: zu viel unter der einen Nummer, nie ein Lieferschein unter der anderen — „von dort kam die Ware wohl"', () => {
  const sachen = ungereimtheiten([zeile('ueberzaehlung', { charge_nr: 1630, kg: 1897, mehr: { eingang_kg: 19318, geliefert_kg: 15735, ausgelagert_kg: 21215 } }),
    zeile('ohne_charge', { charge_nr: null, sorte: 'Kaori Kuri', kg: 4127, n: 6, mehr: { kg_vor_eingang: 0, kg_ohne_ziel: 0, verteilt_auf: [] } })])
  const sp = [spur(1630, { journal_paletten: 54, journal_kg: 19318, lieferscheine: 85, geliefert_kg: 15735, rest_paletten: 0 }),
              spur(1719, { schlag: 'Oettli', journal_paletten: 62, journal_kg: 17381, rest_paletten: 60 }),
              spur(1628, { journal_paletten: 50, journal_kg: 18600, rest_paletten: 48 }),
              spur(1651, { journal_paletten: 9, journal_kg: 3400, lieferscheine: 3, geliefert_kg: 2200, rest_paletten: 2 }),
              spur(1620, { sorte: 'Orangita', journal_paletten: 5, lieferscheine: 3 })]
  const chargen = [{ nr: 1630, sorte: 'Kaori Kuri', perigon_nr: 198969 }, { nr: 1628, sorte: 'Kaori Kuri', perigon_nr: 198970 },
                   { nr: 1719, sorte: 'Kaori Kuri', perigon_nr: 199156 }, { nr: 1651, sorte: 'Kaori Kuri', perigon_nr: 198975 }]
  const faelle = [fall('menge_null', { nummern: '1648, 1719', kg: 1722, schwere: 'rot' })]
  const [s, ...rest] = jeSorte(sp, sachen, faelle, chargen)
  assert.equal(rest.length, 0, 'Orangita hat nichts — sie steht nicht da')
  assert.equal(s.sorte, 'Kaori Kuri')
  assert.equal(s.schwere, 'rot')
  assert.deepEqual(s.chargen.map(c => c.charge_nr), [1628, 1630, 1651, 1719])
  assert.deepEqual(s.nieGeliefert, [1628, 1719])
  assert.match(s.bild[0], /^1 Charge verkauft mehr, als sie hergeben kann \(1630 1\.9 t\)\./)
  assert.ok(s.bild.some(b => /2 Chargen haben Eingang, aber noch nie einen Lieferschein \(1628, 1719; laut App ≈ 108 Paletten\) — von dort kam die Ware wohl\./.test(b)), s.bild.join(' | '))
  assert.ok(s.bild.some(b => /4\.1 t gingen ohne Charge hinaus/.test(b)))
  assert.ok(s.bild.some(b => /1 Perigon-Zeile stimmt nicht \(Charge ohne Menge \(Spalte S = 0\)\)/.test(b)))
  assert.deepEqual(s.aehnlich.length, 1, 'nur aufeinanderfolgende Nummern: 198969 und 198970')
  assert.match(s.aehnlich[0], /1630 \(198969\) und 1628 \(198970\) folgen aufeinander/)
  // Geht die Sorte auf, sind verwechselbare Nummern keine Erklärung — kein Hinweis.
  const ruhig = jeSorte(sp, [], [fall('label_name')], chargen)
  assert.deepEqual(ruhig[0].aehnlich, [])
  assert.deepEqual(ruhig[0].bild.filter(b => b.includes('nie einen Lieferschein')), [], 'ohne Überzählung ist „nie ein Lieferschein" kein Befund')
})

test('Verwechselbar sind aufeinanderfolgende Perigon-Nummern — nicht jedes Paar, das sich in einer Stelle unterscheidet', () => {
  assert.equal(aehnlicheNummer(198969, 198970), true)
  assert.equal(aehnlicheNummer(198970, 198969), true)
  assert.equal(aehnlicheNummer(198945, 198965), false)
  assert.equal(aehnlicheNummer(198969, 198969), false)
})

test('Was zu tun ist: je Ort das Grösste zuerst; erledigt, „kein Fehler" und Auskunft stehen nicht da', () => {
  const sachen = ungereimtheiten([zeile('ueberzaehlung', { charge_nr: 1630, kg: 1897 }), zeile('ohne_eingang', { charge_nr: 1627, kg: 1416 }),
    zeile('umgebucht', { charge_nr: 1627, kg: 2012, mehr: { von_charge_nr: 1625, auftrag_id: 1602 } })])
  const faelle = [fall('menge_null', { pos_id: 1, kg: 1722, schwere: 'rot' }), fall('rest', { pos_id: 2, kg: 15 }), fall('mix', { pos_id: 3, wo: 'firma', kg: 288 }),
                  fall('unbekannt', { pos_id: 4, wo: 'stammdaten', kg: 110 }), fall('nachholen', { pos_id: 5, wo: 'nichts', schwere: 'info' })]
  const v = new Map([['rest:A:2', vermerkt('rest:A:2', 'erledigt')]])
  const a = aufgaben(faelle, sachen, v)
  assert.deepEqual(a.map(x => x.wo), ['perigon', 'halle', 'journal', 'stammdaten', 'firma'])
  assert.deepEqual(a[0].eintraege.map(e => e.schluessel), ['menge_null:A:1'], 'der erledigte Rest steht nicht mehr da')
  assert.match(a[1].eintraege[0].titel, /1630 .* hat mehr verkauft/)
  assert.equal(a[2].eintraege.length, 1, 'die Umbuchung ist Auskunft, nur die Charge ohne Eingang steht beim Journal')
  assert.equal(a.find(x => x.wo === 'nichts'), undefined, 'was die App selbst nachholt, ist keine Aufgabe')
})

test('Die Lage in Zahlen: herein, hinaus, ohne Charge, noch da — leer bleibt leer', () => {
  const l = lageInZahlen([spur(1630, { journal_paletten: 54, journal_kg: 19318, lieferscheine: 85, geliefert_kg: 15735, rest_paletten: -0.4 }),
                          spur(1719, { journal_paletten: 62, journal_kg: 17381, rest_paletten: 60.2 }), spur(1627, { lieferscheine: 3, geliefert_kg: 1416 })],
    ungereimtheiten([zeile('ohne_charge', { charge_nr: null, kg: 4127, mehr: {} })]))
  assert.equal(l.hereinKg, 36699)
  assert.equal(l.hereinPaletten, 116)
  assert.equal(l.chargenMitEingang, 2)
  assert.equal(l.hinausKg, 17151)
  assert.equal(l.lieferscheine, 88)
  assert.equal(l.ohneChargeKg, 4127)
  assert.equal(l.nochPaletten, 60, 'eine Charge unter null zählt als leer, nicht als minus')
  assert.equal(lageInZahlen([], []).hereinKg, null)
})

test('Ein verschwundener Fall erzählt aus dem Schnappschuss, was er war', () => {
  assert.equal(schnappschussText({ art: 'keine_nummer', datum: '2026-10-09', artikel: 'Bio Kürbis oranger Knirps', kg: 7 }),
    'Position ohne Chargennummer — 09.10.2026 · Bio Kürbis oranger Knirps · 7 kg')
  assert.equal(schnappschussText({ art: 'ueberzaehlung', titel: 'Charge 1630 hat mehr verkauft' }), 'Charge 1630 hat mehr verkauft')
  assert.equal(schnappschussText(null), '')
})

test('0126: die Sachen je Charge kennen die neuen Arten — Rest wie „Teil ohne Charge", vor dem Eingang bei der Charge, Mix aus dem Reiter', () => {
  assert.equal(ART_NAME.vor_eingang, 'Verkauft vor dem Eingang', 'wo eine Sache je Charge gleich heisst, gilt ihr Name')
  assert.equal(ART_NAME.menge_null, 'Charge ohne Menge (Spalte S = 0)')
  const liste = ungereimtheiten([zeile('vor_eingang', { charge_nr: 1626, kg: 7156, mehr: { erster_eingang: '2026-09-23' } })],
    [fall('rest', { pos_id: 1, kg: 600 }), fall('vor_eingang', { pos_id: 2, charge_nr: 1626, kg: 1827 }), fall('mix', { pos_id: 3, charge_nr: 1624, kg: 288 }),
     fall('nachholen', { pos_id: 4, charge_nr: 1650, kg: 300 })])
  assert.equal(liste.filter(u => u.art === 'vor_eingang').length, 1, 'die Zeile vor dem Eingang gehört zur Sache der Charge')
  assert.equal(liste.find(u => u.art === 'vor_eingang')!.zeilen.length, 1)
  assert.equal(liste.find(u => u.art === 'rest')!.schwere, 'rot', 'ab 500 kg rot, wie „Teil ohne Charge"')
  const mix = liste.find(u => u.art === 'mix')!
  assert.match(mix.titel, /1 Perigon-Zeile: Kürbis Mix auf einer Charge/)
  assert.equal(mix.was, PERIGON_ART.mix.heisst)
  assert.equal(liste.find(u => u.art === 'nachholen')!.schwere, 'info')
  assert.deepEqual(vonCharge(liste, 1624).map(u => u.art), ['mix'])
  assert.equal(ausZeile(zeile('vor_eingang', { charge_nr: 1626, mehr: { erster_eingang: '2026-09-23' } }), [fall('vor_eingang', { charge_nr: 1626 })]).zeilen.length, 1)
})
