import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  PERIGON_ART, ART_FOLGE, aehnlicheNummer, fallKurz, gegenueber, istOffen, jeSorte, labelDerGruppe,
  labelImNamen, MENGEN_ARTEN, nachrechnen, schnappschussText, spaltenZeichen, standVon, zuteilung,
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

// Runde BF: nachArt, filtern, aufgaben, lageInZahlen, sachenNachArt und sachenFiltern gibt es nicht mehr —
// der Reiter ordnet Fälle (alles zu einer Charge, alle Zeilen einer Art), nicht Zeilen je Art, und „Wo zu
// tun" ist kein Filter mehr. Was ihre Tests sicherten, prüft test/faelle.test.ts an den Fällen weiter:
// Abweichung nach unten wie nach oben, unbekannt bleibt unbekannt, die grössten zuerst, Filter nach Stand,
// Art, Charge (auch die genannte Nummer), Sorte und Suche, Auskunft ist keine Aufgabe.
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

// Runde BD — der Betrieb zum Reiter: „er überfordert gerade noch", und zu einem
// Fall: „das versteh ich nicht — wie kommst du auf 768?" Die Liste sagt je Fall
// nur noch das Eine, das nicht passt; das Fenster rechnet Zeile für Zeile nach.

test('Runde BD: 768 kg sind drei gleiche Zeilen à 256 kg — das Fenster rechnet es Zeile für Zeile nach', () => {
  const f = fall('zu_viel', { menge: 256, kg_position: 256, kg_zugeteilt: 768, kg_rechnung: 256, kg: 512, nummern: '1620', charge_nr: 1620, n_zeilen: 3 })
  const z = { charge_extern: '1620', batch_menge: 256, kg_charge: 256 }
  const r = nachrechnen(f, [z, z, z])!
  assert.deepEqual(r.zeilen.map(x => [x.nr, x.charge, x.kg, x.gleichWie]), [[1, '1620', 256, null], [2, '1620', 256, 1], [3, '1620', 256, 1]])
  assert.equal(r.zugeteiltKg, 768)
  assert.equal(r.positionKg, 256)
  assert.deepEqual(r.unterschied, { kg: 512, wort: 'zu viel' })
  // Runde BG: der Satz fängt beim Lieferschein an — „die Position steht 3-mal in der Datei" verstand der Betrieb nicht.
  // Die Regel hat sich gedreht, der Test mit ihr; geprüft werden weiter Charge, Menge je Zeile, Summe und Unterschied.
  assert.match(r.satz, /^Auf dem Lieferschein stehen 256 kg\. Perigon schreibt dazu 3-mal dieselbe Charge 1620 mit 256 kg — zusammen 768 kg, 512 kg mehr als geliefert\.$/)
  assert.doesNotMatch(r.satz, /× AE/, 'bei kg-Artikeln ist die Menge das Kilo — kein „S × AE"')
  // zwei verschiedene Chargen: kein „gleich wie", der Satz zählt die Zeilen
  const r2 = nachrechnen({ ...f, kg_zugeteilt: 400, kg: 144 }, [{ charge_extern: '1620', batch_menge: 200, kg_charge: 200 }, { charge_extern: '1621', batch_menge: 200, kg_charge: 200 }])!
  assert.deepEqual(r2.zeilen.map(x => x.gleichWie), [null, null])
  assert.match(r2.satz, /Perigon teilt den 2 Chargenzeilen zusammen 400 kg zu — 144 kg mehr als geliefert/)
  // eine einzige Zeile mit S > Q (wie 134056: 965 gegen 918 kg) — kein „Die 1 Zeilen"
  const r1 = nachrechnen({ ...f, kg_position: 918, kg_zugeteilt: 965, kg: 47, nummern: '1625', charge_nr: 1625, n_zeilen: 1 },
    [{ charge_extern: '1625', batch_menge: 965, kg_charge: 965 }])!
  assert.equal(r1.satz, 'Auf dem Lieferschein stehen 918 kg. Perigon teilt der Charge 1625 aber 965 kg zu — 47 kg mehr als geliefert.')
  assert.deepEqual(r1.unterschied, { kg: 47, wort: 'zu viel' })
})

test('Runde BD: Stück × Gewicht je Artikel; ohne Gewicht bleibt die Masse unbekannt, nie 0', () => {
  const f = fall('rest', { einheit: 'Stück', menge: 100, gewicht_je_artikel: 1.5, kg_position: 150, kg_zugeteilt: 90, kg: 60 })
  const r = nachrechnen(f, [{ charge_extern: '1630', batch_menge: 60, kg_charge: null }])!
  assert.equal(r.zeilen[0].kg, 90, '60 Stück × 1.5 kg')
  // Runde BG: auch hier zuerst der Lieferschein, dann die Zuteilung (Regel und Test gemeinsam geändert)
  assert.equal(r.satz, 'Auf dem Lieferschein stehen 150 kg. Perigon teilt der Charge 1630 nur 90 kg zu — für 60 kg steht keine Charge.')
  assert.deepEqual(r.unterschied, { kg: 60, wort: 'ohne Charge' })
  const o = nachrechnen(fall('ohne_gewicht', { einheit: 'Stück', menge: 40, gewicht_je_artikel: null, kg_position: null, kg_zugeteilt: null, kg: null }),
    [{ charge_extern: '1630', batch_menge: 40, kg_charge: null }])!
  assert.equal(o.zeilen[0].kg, null, 'Stück ohne Gewicht: unbekannt')
  assert.equal(o.zugeteiltKg, null)
  assert.deepEqual(o.unterschied, { kg: null, wort: 'Masse unbekannt' })
  assert.equal(fallKurz(fall('zu_viel', { kg_zugeteilt: null, kg_position: 256 })), 'unbekannt statt 256 kg', 'leer heisst unbekannt, nicht 0 kg')
})

test('Runde BD: S = 0 — die Chargen genannt, die Position ohne Charge; ohne Menge zählt sie nirgends', () => {
  const r = nachrechnen(fall('menge_null', { nummern: '1630, 1635', kg_position: 1722 }),
    [{ charge_extern: '1630', batch_menge: 0, kg_charge: 0 }, { charge_extern: '1635', batch_menge: 0, kg_charge: 0 }])!
  assert.match(r.satz, /nennt die Chargen 1630, 1635, aber in Spalte S steht überall 0\. Die 1'722 kg der Position haben darum keine Charge/)
  assert.deepEqual(r.unterschied, { kg: 1722, wort: 'ohne Charge' })
  const leer = nachrechnen(fall('menge_null', { menge: 0, kg_position: 0 }), [{ charge_extern: '1630', batch_menge: 0, kg_charge: 0 }])!
  assert.match(leer.satz, /hat auch keine Menge — sie zählt nirgends/)
  assert.equal(nachrechnen(fall('mix'), []), null, 'wo nichts zu rechnen ist, kein Rechenblock')
  assert.equal(nachrechnen(fall('zu_viel', { satz: 'aus der Datenbank' }), []).satz, 'aus der Datenbank', 'ohne Zeilen der Satz der Datenbank')
  for (const a of MENGEN_ARTEN) assert.ok(nachrechnen(fall(a), [])?.satz, a)
})

test('Runde BD: wo nichts zu rechnen ist, stehen die Angaben gegeneinander — mit der Spalte der Datei', () => {
  const l = gegenueber(fall('label_name', { artikel: 'Bio Kürbis Butterkin Dem', preisgruppe: 'K' }))!
  assert.deepEqual(l.map(a => [a.was, a.spalte, a.wert, a.heisst]), [['Artikel', 'I', 'Bio Kürbis Butterkin Dem', 'im Namen Demeter'], ['Preisgruppe', 'K', 'K', 'Knospe']])
  const d = gegenueber(fall('demeter_knospe', { preisgruppe: 'D', liefer_label: 'K' }))!
  assert.deepEqual(d.map(a => a.heisst), ['verkauft als Demeter', 'geliefert als Knospe'])
  assert.equal(gegenueber(fall('mix', { nummer: '99128', charge_nr: 99128, sorte: 'Fictor' }))![1].heisst, 'Charge 99128 · Fictor')
  assert.equal(gegenueber(fall('unbekannt', { nummer: '991977' }))![0].wert, '991977')
  assert.equal(gegenueber(fall('zu_viel')), null)
  assert.equal(labelImNamen('Bio Kürbis Mix OS'), null)
  assert.equal(labelDerGruppe('CH-K'), 'Knospe')
  assert.equal(labelDerGruppe('SG'), null, 'eine andere Preisgruppe sagt nichts')
})

test('Runde BD: die Liste sagt je Fall das Eine, das nicht passt', () => {
  assert.equal(fallKurz(fall('zu_viel', { kg_zugeteilt: 768, kg_position: 256 })), '768 kg statt 256 kg')
  assert.equal(fallKurz(fall('label_name', { artikel: 'Bio Kürbis Kaori Kuri Dem', preisgruppe: 'K' })), 'Name Demeter, Preisgruppe K')
  assert.equal(fallKurz(fall('vor_eingang', { satz: 'Geliefert am 20.08.2026, aber die Charge 99129 kam laut Erntejournal erst am 28.08.2026 an (8 Tage später) — …' })), '8 Tage vor dem Eingang')
  assert.equal(fallKurz(fall('vor_eingang', { satz: '…' })), 'vor dem Eingang')
  for (const a of ART_FOLGE) assert.ok(fallKurz(fall(a)), a)
})

// Runde BG — der Betrieb: „Chargenzeile mehr als die Position checke ich noch immer nicht … Zeile 1, 2, 3 und
// dann gleich wie Zeile 1, aber ich weiss nicht, was du meinst." Das Bild „Lieferschein und Chargen" stapelt die
// Chargenzeilen gegen die gelieferte Menge; woran es wohl liegt, sagt die Datei selbst.

test('Runde BG: drei gleiche Zeilen à 256 kg gegen 256 kg geliefert — gestapelt, zwei ganz darüber, „gleich"', () => {
  const f = fall('zu_viel', { menge: 256, kg_position: 256, kg_zugeteilt: 768, kg_rechnung: 256, kg: 512, nummern: '1620', charge_nr: 1620, n_zeilen: 3 })
  const z = { charge_extern: '1620', batch_menge: 256, kg_charge: 256 }
  const b = zuteilung(nachrechnen(f, [z, z, z])!, 'zu_viel')
  assert.deepEqual(b.zeilen.map(x => [x.ab, x.innen, x.drueber]), [[0, 256, 0], [256, 0, 256], [512, 0, 256]])
  assert.equal(b.skala, 768)
  assert.equal(b.muster, 'gleich')
  assert.match(b.woran!, /^Die 3 Zeilen sind gleich — dieselbe Charge, dieselbe Menge\. Geliefert wurde einmal/)
})

test('Runde BG: eine einzige Zeile über der Position — mit gleichen Gebinden heisst das: nur das Gewicht wurde geändert', () => {
  const f = fall('zu_viel', { kg_position: 918, kg_zugeteilt: 965, kg: 47, nummern: '1625', charge_nr: 1625, n_zeilen: 1 })
  const r = nachrechnen(f, [{ charge_extern: '1625', batch_menge: 965, kg_charge: 965 }])!
  const b = zuteilung(r, 'zu_viel', { position: 96, zeile: 96 })
  assert.deepEqual(b.zeilen.map(x => [x.ab, x.innen, x.drueber]), [[0, 918, 47]])
  assert.equal(b.muster, 'eine')
  assert.match(b.woran!, /Gebinde stimmt überein \(96 auf dem Lieferschein und bei der Charge\) — wohl wurde nachträglich nur das Gewicht der Position geändert/)
  assert.match(zuteilung(r, 'zu_viel', { position: 96, zeile: 90 }).woran!, /Auch die Gebinde weichen ab: 96 auf dem Lieferschein, 90 bei der Charge/)
  assert.equal(zuteilung(r, 'zu_viel').woran, 'Es ist eine einzige Charge, ihr ist aber mehr zugeteilt, als geliefert wurde.', 'ohne Gebinde keine Vermutung dazu')
})

test('Runde BG: mehrere Chargen, teils wiederholt, der Rest ohne Charge, und unbekannte Kilo bleiben unbekannt', () => {
  const f = fall('zu_viel', { kg_position: 256, kg_zugeteilt: 400, kg: 144 })
  const m = zuteilung(nachrechnen(f, [{ charge_extern: '1620', batch_menge: 200, kg_charge: 200 }, { charge_extern: '1621', batch_menge: 200, kg_charge: 200 }])!, 'zu_viel')
  assert.equal(m.muster, 'mehrere')
  assert.deepEqual(m.zeilen.map(x => [x.ab, x.innen, x.drueber]), [[0, 200, 0], [200, 56, 144]], 'gefüllt in der Folge der Zeilen, bis die Lieferung voll ist')
  const t = zuteilung(nachrechnen({ ...f, kg_zugeteilt: 400 }, [{ charge_extern: '1620', batch_menge: 100, kg_charge: 100 },
    { charge_extern: '1620', batch_menge: 100, kg_charge: 100 }, { charge_extern: '1621', batch_menge: 200, kg_charge: 200 }])!, 'zu_viel')
  assert.equal(t.muster, 'teils_gleich')
  assert.match(t.woran!, /^Eine Zeile wiederholt eine Zeile davor/)
  const rest = zuteilung(nachrechnen(fall('rest', { kg_position: 150, kg_zugeteilt: 90, kg: 60 }), [{ charge_extern: '1630', batch_menge: 90, kg_charge: 90 }])!, 'rest')
  assert.equal(rest.muster, 'rest')
  assert.equal(rest.skala, 150)
  assert.deepEqual(rest.zeilen.map(x => [x.ab, x.innen, x.drueber]), [[0, 90, 0]])
  const o = zuteilung(nachrechnen(fall('ohne_gewicht', { einheit: 'Stück', menge: 40, gewicht_je_artikel: null, kg_position: null, kg_zugeteilt: null, kg: null }),
    [{ charge_extern: '1630', batch_menge: 40, kg_charge: null }])!, 'ohne_gewicht')
  assert.equal(o.skala, null, 'ohne Kilo kein Massstab — nie 0')
  assert.deepEqual(o.zeilen.map(x => [x.ab, x.innen, x.drueber]), [[null, null, null]])
  assert.equal(o.muster, 'sonst')
  assert.equal(o.woran, null)
})
