// Runde BG: die Auffälligkeiten Fall für Fall (src/auswertung/auffaellig.ts).
// Der Betrieb, 25. Oktober: „bitte ordne die chronologisch … die obersten
// sollen die neuesten sein … Lösungsvorschläge … die ich dann auch
// akzeptieren kann oder nicht." Die Muster unten sind die der echten Daten
// vom 25. Oktober, mit erfundenen Nummern: Zettel einen Tag zu früh datiert
// (alle Gewichte am Tag danach), Zettel einer Nachbarcharge, eine Ziffer im
// Datum, Teilpalette, Palox mit geschätztem Gewicht im Wareneingang, ein
// Gewicht ein Kilo daneben — und die Fälle, in denen die App nichts
// vorschlagen darf, weil sie raten müsste.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  artVorschlag, betroffeneZettel, bezugTeile, chatZeile, eineZifferAnders, fallKennung, istZahlendreher, istZettelFall,
  nachTag, neuZuerst, nichtMehrDa, nummernFolge, passtStand, standVon, tagIn, tagText, vermerkeJeFall, zettelDeutung,
  type AuffVermerk, type WarePalette, type Zettel, type ZettelLage,
} from '../src/auswertung/auffaellig.ts'
import type { Befund } from '../src/auswertung/daten.ts'

const befund = (x: Partial<Befund> & Pick<Befund, 'art' | 'bezug'>): Befund =>
  ({ auftrag_id: 900, charge_nr: 5001, sorte: 'Muskat', start_ts: '2026-10-01T11:00:00Z', befund: '', rat: '', ...x })
const zettel = (id: number, eingangsdatum: string, kg: number, kisten = 36, gebindeart = 'G2', auftrag_id = 900): Zettel =>
  ({ id, auftrag_id, eingangsdatum, brutto_zettel_kg: kg, kisten, gebindeart })
const palette = (eingangsdatum: string, kg: number, kisten = 36, charge_nr = 5001): WarePalette =>
  ({ charge_nr, eingangsdatum, brutto_kg: kg, kisten, gebindeart: 'G2' })
const lage = (x: Partial<ZettelLage>): ZettelLage => ({ zettel: [], eigen: [], fremd: [], andere: [], arbeitTag: '2026-10-01', ...x })

/* ---------- Folge, Nummern, Tage, Stand -------------------------------- */

test('die neuesten zuoberst — ohne Tag ganz unten, gleich alt nach Art und Bezug', () => {
  const bs = [
    befund({ art: 'Zettelgewicht', bezug: 'zettel:1:400.00', start_ts: '2026-09-01T08:00:00Z' }),
    befund({ art: 'Kistengewicht', bezug: 'gebinde:3:2', start_ts: '2026-10-20T08:00:00Z' }),
    befund({ art: 'Überzählung', bezug: 'charge:5001', start_ts: null }),
    befund({ art: 'Ohne Nenner', bezug: 'auftrag:2', start_ts: '2026-10-20T08:00:00Z' }),
  ]
  assert.deepEqual(neuZuerst(bs).map(fallKennung),
    ['Kistengewicht|gebinde:3:2', 'Ohne Nenner|auftrag:2', 'Zettelgewicht|zettel:1:400.00', 'Überzählung|charge:5001'])
  // Nummern: die älteste zuerst, damit eine höhere Nummer eine jüngere ist; ohne Tag am Ende
  assert.deepEqual(nummernFolge(bs),
    ['Zettelgewicht|zettel:1:400.00', 'Kistengewicht|gebinde:3:2', 'Ohne Nenner|auftrag:2', 'Überzählung|charge:5001'])
  assert.deepEqual(nachTag(neuZuerst(bs)).map(g => [g.tag, g.befunde.length]), [['2026-10-20', 2], ['2026-09-01', 1], [null, 1]])
})

test('der Tag einer Arbeit ist der Zürcher Tag, nicht der UTC-Tag', () => {
  assert.equal(tagIn('2026-09-22T22:30:00Z'), '2026-09-23', 'halb eins in der Nacht in Zürich')
  assert.equal(tagIn('2026-09-22'), '2026-09-22')
  assert.equal(tagIn(null), null)
  assert.equal(tagText('2026-09-03'), '03.09.2026')
})

test('der Stand ist der jüngste Vermerk; was nicht mehr in den Daten steht, bleibt im Verlauf', () => {
  const v: AuffVermerk[] = [
    { id: 1, fall: 'Zetteldatum|zetteldatum:9:2026-09-22', stand: 'in_abklaerung', notiz: null, schnappschuss: null, wer: null, ts: '2026-10-25T08:00:00Z' },
    { id: 2, fall: 'Zetteldatum|zetteldatum:9:2026-09-22', stand: 'korrigiert', notiz: null, schnappschuss: { vorher: '2026-09-22' }, wer: null, ts: '2026-10-25T09:00:00Z' },
    { id: 3, fall: 'Kistengewicht|gebinde:3:2', stand: 'so_lassen', notiz: 'heilt von selbst', schnappschuss: null, wer: null, ts: '2026-10-25T07:00:00Z' },
  ]
  const m = vermerkeJeFall(v)
  assert.equal(standVon('Zetteldatum|zetteldatum:9:2026-09-22', m), 'korrigiert')
  assert.equal(standVon('Kistengewicht|gebinde:3:2', m), 'so_lassen')
  assert.equal(standVon('Wägung|verdunstung_wiegung:4', m), 'offen')
  assert.deepEqual(nichtMehrDa(m, new Set(['Kistengewicht|gebinde:3:2'])).map(x => x.id), [2])
  assert.ok(passtStand('so_lassen', 'erledigt') && passtStand('korrigiert', 'erledigt') && !passtStand('offen', 'erledigt'))
  assert.ok(passtStand('in_abklaerung', 'alle') && !passtStand('in_abklaerung', 'offen'))
})

test('für den Chat: Nummer, Art, Charge, Arbeit, Tag', () => {
  assert.equal(chatZeile(befund({ art: 'Zetteldatum', bezug: 'zetteldatum:900:2026-09-22', start_ts: '2026-10-01T06:00:00Z' }), 12),
    'Auffälligkeit 12 — Zetteldatum, Charge 5001, Arbeit 900 (01.10.2026)')
})

/* ---------- Bezug und Zettel ------------------------------------------- */

test('der Bezug sagt, welche Zettel gemeint sind', () => {
  assert.deepEqual(bezugTeile('zettel:900:448.00:2026-09-22'), { typ: 'zettel', id: 900, kg: 448, tag: '2026-09-22' })
  assert.deepEqual(bezugTeile('zettel:900:140.00'), { typ: 'zettel', id: 900, kg: 140, tag: null })
  assert.deepEqual(bezugTeile('zetteldatum:900:2026-08-13'), { typ: 'zetteldatum', id: 900, kg: null, tag: '2026-08-13' })
  const z = [zettel(1, '2026-09-22', 448), zettel(2, '2026-09-23', 448), zettel(3, '2026-09-22', 433)]
  assert.deepEqual(betroffeneZettel(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:448.00:2026-09-22' }), z).map(x => x.id), [1])
  assert.deepEqual(betroffeneZettel(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:448.00' }), z).map(x => x.id), [1, 2])
  assert.deepEqual(betroffeneZettel(befund({ art: 'Zetteldatum', bezug: 'zetteldatum:900:2026-09-22' }), z).map(x => x.id), [1, 3])
  assert.ok(istZettelFall(befund({ art: 'Zetteldatum', bezug: 'zetteldatum:900:2026-09-22' })))
  assert.ok(!istZettelFall(befund({ art: 'Zetteldatum Zukunft', bezug: 'auftrag:900' })))
  assert.ok(istZahlendreher(342, 432) && !istZahlendreher(342, 342) && !istZahlendreher(342, 4320))
  assert.ok(eineZifferAnders('2026-09-08', '2026-09-18') && !eineZifferAnders('2026-09-08', '2026-10-18'))
})

/* ---------- Muster und Vorschlag --------------------------------------- */

test('alle Zettel einen Tag zu früh: Datum vertippt, eindeutig, für alle Zettel des Tages', () => {
  // wie Charge 1627: fünf Zettel vom 22.9., die Charge kam nur am 23.9., jedes Gewicht steht dort genau so
  const zs = [zettel(1, '2026-09-22', 448), zettel(2, '2026-09-22', 433), zettel(3, '2026-09-22', 433), zettel(4, '2026-09-22', 380, 33)]
  const l = lage({ zettel: zs, eigen: [palette('2026-09-23', 448), palette('2026-09-23', 433), palette('2026-09-23', 433), palette('2026-09-23', 380, 33)] })
  const d = zettelDeutung(befund({ art: 'Zetteldatum', bezug: 'zetteldatum:900:2026-09-22' }), l)
  assert.equal(d.muster, 'datum')
  assert.equal(d.vorschlag?.art, 'korrigieren')
  assert.equal(d.vorschlag?.sicher, 'eindeutig')
  assert.equal(d.vorschlag?.was, 'zetteldatum')
  assert.deepEqual([d.vorschlag?.vorher, d.vorschlag?.nachher], ['2026-09-22', '2026-09-23'])
  assert.deepEqual(d.vorschlag?.ids, [1, 2, 3, 4])
  assert.match(d.vorschlag!.titel, /22\.09\.2026 → 23\.09\.2026 an allen 4 Zetteln/)
  assert.match(d.vorschlag!.warum.join(' '), /Alle 4 Gewichte stehen bei Charge 5001 am 23\.09\.2026/)
  // Über ein einzelnes Zettelgewicht kommt man zum selben Vorschlag — für die ganze Gruppe
  const e = zettelDeutung(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:448.00:2026-09-22' }), l)
  assert.deepEqual([e.muster, e.vorschlag?.ids, e.vorschlag?.nachher], ['datum', [1, 2, 3, 4], '2026-09-23'])
})

test('ein Tag ist nur Vorschlag, solange die Palette frei ist — ist sie belegt, zählt sie nicht', () => {
  const zs = [zettel(1, '2026-09-22', 448), zettel(2, '2026-09-22', 433)]
  const eigen = [palette('2026-09-23', 448), palette('2026-09-23', 433)]
  const andere = [zettel(50, '2026-09-23', 448, 36, 'G2', 901), zettel(51, '2026-09-23', 433, 36, 'G2', 901)]
  const d = zettelDeutung(befund({ art: 'Zetteldatum', bezug: 'zetteldatum:900:2026-09-22' }), lage({ zettel: zs, eigen, andere }))
  assert.notEqual(d.vorschlag?.art, 'korrigieren', 'beide Paletten hat schon eine andere Arbeit gezählt')
  assert.equal(d.muster, 'doppelt', 'und das sagt die App: wohl doppelt erfasst')
  assert.match(d.vorschlag!.titel, /Arbeit 901/)
})

test('kein Tag nach dem Arbeitstag: eine Palette kann nicht verarbeitet werden, bevor sie kommt', () => {
  const zs = [zettel(1, '2026-09-15', 468)]
  const d = zettelDeutung(befund({ art: 'Zetteldatum', bezug: 'zetteldatum:900:2026-09-15' }),
    lage({ zettel: zs, eigen: [palette('2026-10-02', 468), palette('2026-08-24', 505)], arbeitTag: '2026-09-26' }))
  assert.notEqual(d.vorschlag?.nachher, '2026-10-02')
})

test('die Zettel gehören zu einer Nachbarcharge: kein Klick, der Weg in die Korrektur', () => {
  // wie Charge 1626: acht Zettel vom 31.8., die Charge kam erst am 23.9.; am 31.8. stehen die Gewichte bei 1623
  const zs = [zettel(1, '2026-08-31', 437), zettel(2, '2026-08-31', 434), zettel(3, '2026-08-31', 428), zettel(4, '2026-08-31', 432)]
  const fremd = [palette('2026-08-31', 437, 36, 5000), palette('2026-08-31', 434, 36, 5000), palette('2026-08-31', 428, 36, 5000), palette('2026-08-31', 444, 36, 4990)]
  const d = zettelDeutung(befund({ art: 'Zetteldatum', bezug: 'zetteldatum:900:2026-08-31' }),
    lage({ zettel: zs, eigen: [palette('2026-09-23', 470)], fremd }))
  assert.equal(d.muster, 'fremde_charge')
  assert.equal(d.vorschlag?.art, 'von_hand')
  assert.match(d.vorschlag!.titel, /Charge 5000/)
  assert.match(d.vorschlag!.warum.join(' '), /3 der 4 Gewichte vom 31\.08\.2026 stehen genau so bei Charge 5000/)
  // Ein einzelnes Zettelgewicht dieses Tages sagt dasselbe wie der ganze Tag
  const e = zettelDeutung(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:432.00' }), lage({ zettel: zs, eigen: [palette('2026-09-23', 470)], fremd }))
  assert.deepEqual([e.muster, e.vorschlag?.titel], ['fremde_charge', 'Gehören die Zettel zu Charge 5000?'])
})

test('eine Ziffer im Datum: 08.09 statt 18.09 — wahrscheinlich, mit dem Hinweis', () => {
  const zs = [zettel(1, '2026-09-08', 490), zettel(2, '2026-09-08', 502)]
  const d = zettelDeutung(befund({ art: 'Zetteldatum', bezug: 'zetteldatum:900:2026-09-08' }),
    lage({ zettel: zs, eigen: [palette('2026-09-18', 490), palette('2026-09-19', 490), palette('2026-09-18', 502)], fremd: [palette('2026-09-08', 502, 36, 5002)] }))
  assert.equal(d.muster, 'datum')
  assert.equal(d.vorschlag?.nachher, '2026-09-18')
  assert.equal(d.vorschlag?.sicher, 'wahrscheinlich', 'eine andere Charge hat eines der Gewichte am getippten Tag')
  assert.match(d.vorschlag!.warum.join(' '), /in einer Ziffer/)
  assert.match(d.vorschlag!.warum.join(' '), /Charge 5002/)
})

test('dasselbe Gewicht an mehreren Tagen: die App rät nicht', () => {
  const d = zettelDeutung(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:447.00:2026-08-13' }),
    lage({ zettel: [zettel(1, '2026-08-13', 447)], eigen: [palette('2026-08-28', 447), palette('2026-08-31', 447)] }))
  assert.equal(d.muster, 'mehrdeutig')
  assert.equal(d.vorschlag?.art, 'von_hand')
  assert.match(d.vorschlag!.warum[0], /28\.08\.2026, 31\.08\.2026/)
})

test('stimmen die anderen Zettel des Tages, stimmt der Tag — dann ist das Gewicht fraglich', () => {
  // wie Arbeit 1640: am 27.8. passen die übrigen Zettel genau; 380 kg kam nur am 20.8. — wohl Zufall
  const zs = [zettel(1, '2026-08-27', 380, 32), zettel(2, '2026-08-27', 417), zettel(3, '2026-08-27', 418)]
  const d = zettelDeutung(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:380.00:2026-08-27' }),
    lage({ zettel: zs, eigen: [palette('2026-08-27', 417), palette('2026-08-27', 418), palette('2026-08-20', 380, 32)] }))
  assert.equal(d.muster, 'ohne_kandidat')
  assert.notEqual(d.vorschlag?.art, 'korrigieren')
  assert.match(d.vorschlag!.warum[0], /der Tag stimmt also/)
  assert.match(d.vorschlag!.warum[0], /wohl Zufall/)
})

test('ein Kilo daneben, gleiche Kisten, und keine andere Palette frei: Gewicht vertippt', () => {
  const zs = [zettel(1, '2026-08-20', 534, 60)]
  const andere = [zettel(60, '2026-08-20', 536, 60, 'G2', 901)]
  const eigen = [palette('2026-08-20', 535, 60), palette('2026-08-20', 536, 60), palette('2026-08-20', 541, 60)]
  const d = zettelDeutung(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:534.00' }), lage({ zettel: zs, eigen, andere }))
  assert.equal(d.muster, 'tippfehler')
  assert.deepEqual([d.vorschlag?.was, d.vorschlag?.vorher, d.vorschlag?.nachher, d.vorschlag?.ids], ['zettelgewicht', '534', '535', [1]])
  assert.equal(d.vorschlag?.sicher, 'wahrscheinlich', 'ein vertipptes Gewicht ist nie eindeutig')
  // ohne den anderen Zettel sind zwei Paletten frei: dann nicht
  const e = zettelDeutung(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:534.00' }), lage({ zettel: zs, eigen }))
  assert.equal(e.muster, 'mehrdeutig')
  assert.match(e.vorschlag!.warum.join(' '), /535 kg, 536 kg/)
})

test('Zahlendreher am selben Tag: 342 statt 432', () => {
  const d = zettelDeutung(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:342.00' }),
    lage({ zettel: [zettel(1, '2026-08-27', 342, 32)], eigen: [palette('2026-08-27', 432, 32), palette('2026-08-27', 466, 32)] }))
  assert.equal(d.muster, 'zahlendreher')
  assert.equal(d.vorschlag?.nachher, '432')
})

test('weniger Kisten als eine volle Palette: Teilpalette, so lassen', () => {
  const d = zettelDeutung(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:235.00' }),
    lage({ zettel: [zettel(1, '2026-09-08', 235, 18)], eigen: [palette('2026-09-08', 466), palette('2026-09-08', 470), palette('2026-09-08', 472)] }))
  assert.equal(d.muster, 'teilpalette')
  assert.equal(d.vorschlag?.art, 'so_lassen')
  assert.match(d.vorschlag!.warum[0], /18 Kisten; eine volle Palette dieser Charge hat 36/)
})

test('ein Palox: im Wareneingang steht ein geschätztes Gewicht — so lassen', () => {
  const d = zettelDeutung(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:304.00' }),
    lage({ zettel: [zettel(1, '2026-09-10', 304, 1, 'Holz Palox')], eigen: [palette('2026-09-10', 300, 1), palette('2026-09-10', 315, 1)] }))
  assert.equal(d.muster, 'palox')
  assert.equal(d.vorschlag?.art, 'so_lassen')
})

test('nichts in der Nähe: sagen, was am Tag kam, nichts vorschlagen', () => {
  const d = zettelDeutung(befund({ art: 'Zettelgewicht', bezug: 'zettel:900:442.00' }),
    lage({ zettel: [zettel(1, '2026-09-18', 442)], eigen: [palette('2026-09-18', 460), palette('2026-09-18', 463)] }))
  assert.equal(d.muster, 'ohne_kandidat')
  assert.equal(d.vorschlag?.art, 'von_hand')
  assert.match(d.vorschlag!.warum[0], /am nächsten: 460 kg, 463 kg/)
})

test('die übrigen Arten: ein Klick nur, wo der Befund selbst sagt, was zu tun ist', () => {
  const p = artVorschlag(befund({ art: 'Palette fraglich', bezug: 'ausschuss_messung:222' }))
  assert.deepEqual([p?.art, p?.was, p?.ids, p?.vorher, p?.nachher], ['korrigieren', 'mit_palette', [222], 'true', 'false'])
  assert.equal(artVorschlag(befund({ art: 'Kistengewicht', bezug: 'gebinde:3:2' }))?.art, 'so_lassen')
  assert.equal(artVorschlag(befund({ art: 'Wägung', bezug: 'verdunstung_wiegung:369' }))?.art, 'so_lassen')
  assert.equal(artVorschlag(befund({ art: 'Palox geleert', bezug: 'schimmel_messung:2894' }))?.art, 'so_lassen', '„nach dem Leeren" setzt die App nicht: das Faule bliebe unbekannt')
  assert.equal(artVorschlag(befund({ art: 'Ohne Nenner', bezug: 'auftrag:1644' }))?.wo, 'arbeit')
  assert.equal(artVorschlag(befund({ art: 'Überzählung', bezug: 'charge:1627', auftrag_id: null }))?.wo, 'perigon')
  // wie der Rat der Prüfung: ein vordatierter Lieferschein ist in Ordnung
  assert.equal(artVorschlag(befund({ art: 'Lieferung in der Zukunft', bezug: 'lieferung:201', auftrag_id: null }))?.art, 'so_lassen')
})

test('ein Zettel ohne Gewicht: die App sagt, an welchen Tagen die Charge kam, und rät nicht', () => {
  const z = { ...zettel(1, '2026-04-11', 0), brutto_zettel_kg: null }
  const d = zettelDeutung(befund({ art: 'Zetteldatum', bezug: 'zetteldatum:900:2026-04-11' }),
    lage({ zettel: [z], eigen: [palette('2026-04-07', 480), palette('2026-04-14', 470)], arbeitTag: '2026-05-25' }))
  assert.equal(d.muster, 'ohne_kandidat')
  assert.match(d.vorschlag!.warum[0], /kein Gewicht.*an 2 Tagen: 07\.04\.2026, 14\.04\.2026/)
  // kam die Charge nur an einem Tag, ist das der Vorschlag — „wahrscheinlich", ohne Gewicht zur Bestätigung
  const e = zettelDeutung(befund({ art: 'Zetteldatum', bezug: 'zetteldatum:900:2026-04-11' }),
    lage({ zettel: [z], eigen: [palette('2026-04-14', 470)], arbeitTag: '2026-05-25' }))
  assert.deepEqual([e.muster, e.vorschlag?.nachher, e.vorschlag?.sicher], ['datum', '2026-04-14', 'wahrscheinlich'])
  assert.match(e.vorschlag!.warum[0], /kein Gewicht, an dem es sich bestätigen liesse/)
})
