import { test } from 'node:test'
import assert from 'node:assert/strict'
import { faelleBilden, fallStand, fallOffen, fallFortschritt, faelleFiltern, FALL_FILTER_LEER, geschichte, rueckrechnung, wieSicher,
         zeitleiste, bilanz, type KaskadeZeile } from '../src/auswertung/faelle.ts'
import { ausZeile } from '../src/auswertung/ungereimt.ts'
import type { ChargeSpur, PerigonBefund, PerigonVerlauf, UngereimtZeile, VermerkStand } from '../src/auswertung/daten.ts'

// Runde BF — der Betrieb, 24. Oktober: „Information Overload … damit ich Fall
// für Fall angenehm abarbeiten kann. Den Fall verstehe, sehe, was passiert
// ist … wenn du sagst, so viel ist Eingang, so viel ist Ausgang, das kann
// nicht sein … dann gib kurz an, warum: Verdunstung, Palox, aussortieren."
// Ein Fall ist eine Frage an den Chef; die Zahlen unten sind die echten von
// Charge 1630 (Kaori Kuri) und 1626 (Tiana) aus dem Abzug vom 24. Oktober.

const sache = (art: UngereimtZeile['art'], x: Partial<UngereimtZeile> = {}) =>
  ausZeile({ art, charge_nr: 1626, sorte: 'Tiana', schlag: 'Agasul Rüegg', kg: 0, n: 1, von: null, bis: null, mehr: null, ...x }, [])

const befund = (art: PerigonBefund['art'], pos: number, x: Partial<PerigonBefund> = {}): PerigonBefund => ({
  schluessel: `${art}:A:${pos}`, art, schwere: 'gelb', quelle: 'A', pos_id: pos, datum: '2026-10-09', kunde: 'Kunde', artikel: 'Bio Kürbis Mix',
  einheit: 'kg', menge: 10, gewicht_je_artikel: 0, preisgruppe: 'K', liefer_label: 'K', kg_position: 10, kg_zugeteilt: 10, kg_rechnung: 10,
  kg_ohne_charge: 0, kg: 10, nummern: null, nummer: null, lauf_nr: null, charge_nr: null, sorte: null, n_zeilen: 1, satz: 'Satz', tun: 'tun',
  wo: 'perigon', eingelesen: null, ...x })

const verlauf = (x: Record<string, VermerkStand>) =>
  new Map(Object.entries(x).map(([schluessel, stand]) => [schluessel, { schluessel, stand } as PerigonVerlauf]))

// Charge 1626, wie sie am 24. Oktober dastand: verkauft vor dem Eingang, mehr verkauft als möglich, Zettel passen zu 1623
const vor1626 = sache('vor_eingang', { kg: 7156, n: 7, von: '2026-09-02', bis: '2026-09-22', mehr: { erster_eingang: '2026-09-23' } })
const ueber1626 = sache('ueberzaehlung', { kg: 3182, n: 21, mehr: { geliefert_kg: 7491, eingang_kg: 4863, ausgelagert_kg: 8045 } })
const vorschlag1626 = sache('vorschlag', { kg: 2136, n: 6, mehr: { von_charge_nr: 1623, auftrag_id: 1619, grund: '6 von 8 Zetteln der Arbeit 1619 (Charge 1626) ohne eigene Palette passen aufs Kilo zu Paletten von Charge 1623', paletten: [1, 2] } })
const ueber1630 = ausZeile({ art: 'ueberzaehlung', charge_nr: 1630, sorte: 'Kaori Kuri', schlag: 'Feld Ost', kg: 1897, n: 92, von: null, bis: null,
  mehr: { geliefert_kg: 15735, eingang_kg: 19318, ausgelagert_kg: 21215 } }, [])
const ohneCharge = ausZeile({ art: 'ohne_charge', charge_nr: null, sorte: 'Tiana', schlag: null, kg: 20, n: 3, von: '2026-09-01', bis: '2026-10-01',
  mehr: { kg_vor_eingang: 0, kg_ohne_ziel: 0, verteilt_auf: [] } }, [])
const doppelt = ausZeile({ art: 'stammdaten', charge_nr: 1649, sorte: 'Butterkin', schlag: 'Sauter', kg: null, n: 2, von: null, bis: null,
  mehr: { pruefung: 'perigon_doppelt', perigon_nr: 198976, chargen_nr: [1649, 1650], zeilen_mit_nummer: 3, chargen: [], verwandte: [] } }, [])

const vorZeilen = [1, 2, 3].map(i => befund('vor_eingang', 900 + i, { schwere: 'rot', charge_nr: 1626, sorte: 'Tiana', kg: 1000 * i, nummer: '1626' }))
const mix = [1, 2, 3, 4].map(i => befund('mix', 800 + i, { charge_nr: i < 4 ? 1630 : 1614, nummer: i < 4 ? '1630' : '1614', nummern: i < 4 ? '1630' : '1614', kg: 100 * i, datum: `2026-10-0${i}` }))
const keineNr = befund('keine_nummer', 700, { kg: 7, sorte: 'Tiana' })

test('Alles zu einer Charge ist ein Fall: vor dem Eingang, mehr als möglich, Paletten wohl von 1623 — die Perigon-Zeilen „vor dem Eingang" sind seine Belege', () => {
  const f = faelleBilden([...vorZeilen, ...mix, keineNr], [vor1626, ueber1626, vorschlag1626, ueber1630, ohneCharge, doppelt])
  const c1626 = f.find(x => x.id === 'charge:1626')!
  assert.equal(c1626.typ, 'charge')
  assert.equal(c1626.thema, 'menge')
  assert.deepEqual(c1626.sachen.map(u => u.art), ['vor_eingang', 'ueberzaehlung', 'vorschlag'], 'die rote, grösste zuerst')
  assert.equal(c1626.befunde.length, 3, 'die drei Zeilen vor dem Eingang gehören zur Charge')
  assert.ok(!f.some(x => x.id === 'art:vor_eingang'), 'und stehen nicht noch einmal als eigener Fall da')
  assert.equal(c1626.kg, 7156, 'betrifft: das Grösste, nicht die Summe — die Sachen überschneiden sich')
  assert.equal(c1626.schwere, 'rot')
  assert.match(c1626.unter, /^7.2 t vor dem Eingang verkauft · 3.2 t mehr verkauft, als möglich · Paletten wohl von 1623$/, 'erzählt in der Folge der Dinge')
  assert.equal(c1626.teile.length, 6, 'drei Sachen und die drei Zeilen tragen den Stand')
})

test('Alle Perigon-Zeilen einer Art sind ein Fall; Lieferscheine ohne Charge je Sorte sind Auskunft, das Register ein eigener Fall', () => {
  const f = faelleBilden([...vorZeilen, ...mix, keineNr], [ueber1630, ohneCharge, doppelt])
  const m = f.find(x => x.id === 'art:mix')!
  assert.equal(m.befunde.length, 4)
  assert.equal(m.thema, 'artikel')
  assert.equal(m.kg, 1000)
  assert.match(m.unter, /4 Lieferscheine · 1\.10\.–4\.10\./)
  const k = f.find(x => x.id === 'art:keine_nummer')!
  assert.equal(k.thema, 'datei')
  assert.match(k.unter, /09\.10\.2026 · Kunde · Position 700/, 'eine einzige Position: ihr Tag, Kunde und Position')
  // ohne eine Sache „vor dem Eingang" der Charge bleiben die Zeilen ein eigener Fall
  assert.ok(f.some(x => x.id === 'art:vor_eingang'))
  const o = f.find(x => x.id === 'ohne_charge:Tiana:')!
  assert.equal(o.typ, 'auskunft')
  assert.equal(o.schwere, 'info')
  assert.equal(o.teile.length, 0)
  assert.equal(f.find(x => x.id === 'stammdaten:1649:perigon_doppelt')?.typ, 'register')
  // die Folge: Mengen, Datei, Artikel, Register, Auskunft
  assert.deepEqual([...new Set(f.map(x => x.thema))], ['menge', 'datei', 'artikel', 'register', 'auskunft'])
})

test('Der Stand eines Falls: erledigt erst, wenn alle Teile erledigt sind; in Abklärung, sobald einer es ist', () => {
  const [m] = faelleBilden(mix, [])
  assert.equal(fallStand(m, verlauf({})), 'offen')
  assert.equal(fallStand(m, verlauf({ 'mix:A:801': 'in_abklaerung' })), 'in_abklaerung')
  assert.equal(fallStand(m, verlauf({ 'mix:A:801': 'erledigt', 'mix:A:802': 'kein_fehler' })), 'offen', 'zwei von vier erledigt ist nicht erledigt')
  assert.deepEqual(fallFortschritt(m, verlauf({ 'mix:A:801': 'erledigt', 'mix:A:802': 'kein_fehler' })), { fertig: 2, von: 4 })
  const alle = Object.fromEntries(mix.map(b => [b.schluessel, 'kein_fehler' as VermerkStand]))
  assert.equal(fallStand(m, verlauf(alle)), 'kein_fehler')
  assert.equal(fallStand(m, verlauf({ ...alle, 'mix:A:804': 'erledigt' })), 'erledigt')
  assert.equal(fallOffen(m, verlauf(alle)), false)
  const [auskunft] = faelleBilden([], [ohneCharge])
  assert.equal(fallOffen(auskunft, verlauf({})), false, 'Auskunft ist nie offen')
})

test('Filtern: Stand, Art (auch in den Teilen), Charge (auch die genannte Nummer), Sorte und Suche über Kunde, Artikel, Position', () => {
  const f = faelleBilden([...vorZeilen, ...mix, keineNr], [vor1626, ueber1626, ueber1630, ohneCharge, doppelt])
  const v = verlauf({})
  const ids = (x: Partial<typeof FALL_FILTER_LEER>) => faelleFiltern(f, v, { ...FALL_FILTER_LEER, ...x }).map(y => y.id)
  assert.ok(!ids({}).includes('ohne_charge:Tiana:'), 'offen zeigt keine Auskunft')
  assert.ok(ids({ stand: 'alle' }).includes('ohne_charge:Tiana:'))
  assert.deepEqual(ids({ art: 'ueberzaehlung' }), ['charge:1626', 'charge:1630'])
  assert.deepEqual(ids({ charge: 1614 }), ['art:mix'], 'die Nummer auf einer Mix-Zeile')
  assert.deepEqual(ids({ sorte: 'Tiana' }), ['charge:1626', 'art:keine_nummer'])
  assert.deepEqual(ids({ suche: '804' }), ['art:mix'], 'die Position einer Zeile im Fall')
})

test('Was bei 1626 passiert ist, in Sätzen: herein, hinaus, was nicht aufgeht, was das für die Zahlen heisst — kein Vorschlag', () => {
  const spur = new Map([[1626, { charge_nr: 1626, schlag: 'Agasul Rüegg', sorte: 'Tiana', artikelgruppe: 'Butternut', journal_paletten: 12, journal_kg: 4863,
    journal_von: '2026-09-23', journal_bis: '2026-09-23', paletten: 12, eingang_kg: 4863, weg: null, her: null, arbeiten: 1, arbeit_von: null, arbeit_bis: null,
    arbeit_liste: null, lieferscheine: 21, geliefert_kg: 7491, lief_von: '2026-09-02', lief_bis: '2026-10-14', nach_artikel: null, nachgeordnet: null, rest_paletten: 0 } as ChargeSpur]])
  const [c] = faelleBilden(vorZeilen, [vor1626, ueber1626, vorschlag1626])
  const g = geschichte(c, spur)
  assert.match(g.herein!, /12 Paletten mit 4.9 t laut Erntejournal \(23\.9\.\)/)
  assert.match(g.hinaus!, /21 Lieferscheine mit 7.5 t unter der Nummer 1626 laut Perigon \(2\.9\.–14\.10\.\)/)
  assert.match(g.punkte[0].text, /7 Lieferscheine mit 7.2 t sind älter als die erste Palette \(23\.09\.2026\)/)
  assert.match(g.punkte[1].text, /Für 7.5 t auf den Lieferscheinen braucht es 8 t Eingang.*Verdunstung, Faules, Aussortiertes.*Hereingekommen sind 4.9 t — es fehlen 3.2 t/)
  assert.match(g.punkte[2].text, /passen aufs Kilo zu Paletten von Charge 1623/)
  assert.deepEqual(g.punkte.map(p => p.schwere), ['rot', 'rot', 'gelb'], 'jeder Satz trägt die Schwere seiner Sache')
  assert.match(g.folge!, /von keinem Lager ab/)
  assert.ok(!g.punkte.some(p => /Am ehesten|Zählen:|umbuchen/i.test(p.text)), 'Vermutungen und Vorschläge stehen nicht in der Geschichte')
})

test('Was bei vielen Zeilen einer Art passiert ist: wie viele, wann, wie viel, welche Nummern am häufigsten, und wie die App damit rechnet', () => {
  const [m] = faelleBilden(mix, [])
  const g = geschichte(m, new Map())
  assert.match(g.punkte[0].text, /^4 Lieferscheine vom 1\.10\.–4\.10\., zusammen 1 t, verkaufen einen „Kürbis Mix", gebucht auf eine einzige Charge — am häufigsten 1630 \(3-mal\), 1614 \(1-mal\)\.$/)
  assert.match(g.folge!, /von dieser einen Charge abgezogen/)
  const [k] = faelleBilden([keineNr], [])
  assert.deepEqual(geschichte(k, new Map()).punkte.map(p => p.text), ['Satz'], 'eine Position erzählt ihren eigenen Satz')
})

// Die Kaskade von 1630, wie mv_kaskade sie am 24. Oktober rechnete (eine Kohorte).
const k1630: KaskadeZeile = { m0: 21215.23, m1: 16948.66, m2: 15903.6, alter_tage: 51.8, r: 0.00433, f: 0.0617, a_klein_n: 0.0065, a_gross_n: 0.0041,
  a_fax: 0, hagel: 0, verdunstung_kg: 4266.58, schimmel_kg: 1045.05, klein_kg: 103.48, nebenkanal_kg: 65.35, fax_kg: 0, geliefert_kg: 15734.78,
  r_basis: 'Wiegungen dieser Sorte', f_quelle: 'Sortieren: eigene Messung (2 Arbeiten)', klein_basis: 'Sortierläufe dieser Sorte', gross_basis: 'Sortierläufe dieser Sorte' }

test('1630 rückwärts gerechnet: Lieferscheine + zu klein + zu gross + Faules + Verdunstung = der Eingang, den es brauchte — wie die Kaskade, nicht neu', () => {
  const r = rueckrechnung([k1630], 19318)!
  assert.deepEqual(r.schritte.map(s => s.strom), ['ausschuss', 'nebenkanal', 'schimmel', 'verdunstung'])
  const summe = r.geliefertKg + r.schritte.reduce((a, s) => a + s.kg, 0)
  assert.ok(Math.abs(summe - r.gebrauchtKg) < 0.1, `die Schritte ergeben ${summe}, gebraucht ${r.gebrauchtKg}`)
  assert.ok(Math.abs(r.fehltKg! - 1897.23) < 0.01)
  const v = r.schritte.find(s => s.strom === 'verdunstung')!
  assert.ok(Math.abs(v.anteil! - 0.2011) < 0.001, `Verdunstung ${v.anteil}`)
  assert.match(v.wie, /0.43 % je Tag, im Mittel 52 Tage gelagert/)
  assert.equal(v.woher, 'Wiegungen dieser Sorte')
  const faul = r.schritte.find(s => s.strom === 'schimmel')!
  assert.ok(Math.abs(faul.anteil! - 0.0617) < 0.0005, 'Faules vom Rest nach der Verdunstung')
  assert.ok(Math.abs(r.verlustAnteil - 0.2583) < 0.001)
  assert.ok(Math.abs(r.erlaubtAnteil! - 0.1855) < 0.001, 'höchstens 18.5 % Verlust, damit es aufgeht')
  assert.equal(r.ohneVerlustZuViel, false)
  assert.match(wieSicher(r), /Ohne Verlust ginge es auf.*höchstens 18.5 % verlieren — gerechnet sind 25.8 %, am meisten verdunstet \(4.267 kg\)\./)
})

test('Wo schon ohne Verlust mehr hinausging als herein, liegt es nicht an der Rechnung — das sagt der Satz; mehrere Kohorten zählen zusammen', () => {
  const a = { ...k1630, m0: 5000, m1: 4900, m2: 4800, alter_tage: 10, verdunstung_kg: 100, schimmel_kg: 100, klein_kg: 50, nebenkanal_kg: 50, geliefert_kg: 4700 }
  const b = { ...a, alter_tage: 30, m0: 3045, m1: 3000, m2: 2900, verdunstung_kg: 45, schimmel_kg: 100, klein_kg: 50, nebenkanal_kg: 59, geliefert_kg: 2791 }
  const r = rueckrechnung([a, b], 4863)!
  assert.equal(r.gebrauchtKg, 8045)
  assert.equal(r.geliefertKg, 7491)
  assert.equal(r.ohneVerlustZuViel, true)
  assert.equal(r.erlaubtAnteil, null)
  assert.match(wieSicher(r), /schon ohne jeden Verlust nicht auf: hinaus 7.5 t, herein 4.9 t/)
  assert.match(r.schritte.find(s => s.strom === 'verdunstung')!.wie, /im Mittel 18 Tage/, 'die Lagerdauer mit der Masse gewichtet')
  assert.equal(rueckrechnung([], 100), null, 'ohne Kaskade keine Rückrechnung — nichts erfunden')
  assert.equal(rueckrechnung([k1630], null)!.fehltKg, null, 'ohne Eingang kein Unterschied')
})

test('Die Zeitleiste: die Lieferscheine vor und nach der ersten Palette, mit dem Tag dazwischen', () => {
  const z = zeitleiste([{ datum: '2026-09-02', kg: 1000 }, { datum: '2026-09-22', kg: 2000 }, { datum: '2026-10-14', kg: 500 }], '2026-09-23')!
  assert.equal(z.von, '2026-09-02')
  assert.equal(z.bis, '2026-10-14')
  assert.deepEqual(z.punkte.map(p => p.vor), [true, true, false])
  assert.equal(z.vorKg, 3000)
  assert.equal(z.nachKg, 500)
  assert.equal(zeitleiste([], '2026-09-23'), null)
})

test('Das Bild herein / hinaus nimmt die Zahlen der Datenbank — nie erfundene', () => {
  const [c] = faelleBilden([], [ueber1630])
  assert.deepEqual(bilanz(c), { eingangKg: 19318, geliefertKg: 15735, gebrauchtKg: 21215 })
  const ohne = faelleBilden([], [sache('ohne_eingang', { charge_nr: 1627, kg: 1416, n: 3 })])[0]
  assert.deepEqual(bilanz(ohne), { eingangKg: 0, geliefertKg: 1416, gebrauchtKg: null })
  assert.equal(bilanz(faelleBilden([], [vorschlag1626])[0]), null)
})

// Was bis Runde BE test/perigon.test.ts an nachArt, filtern, aufgaben und sachenFiltern prüfte, gilt
// hier für die Fälle weiter: Abweichung nach unten zählt wie nach oben, ohne Masse bleibt sie unbekannt,
// die grössten zuerst, Auskunft ist keine Aufgabe, gefiltert wird nach Stand, Sorte, Kunde und Position.
test('Je Art: eine Abweichung nach unten zählt wie nach oben, ohne Masse bleibt unbekannt, die grössten zuerst; was die App nachholt, ist Auskunft', () => {
  const f = faelleBilden([befund('masse_abweichung', 1, { kg: -45 }), befund('masse_abweichung', 2, { kg: 60 }), befund('ohne_gewicht', 3, { kg: null }),
                          befund('nachholen', 4, { schwere: 'info' })], [])
  const m = f.find(x => x.id === 'art:masse_abweichung')!
  assert.equal(m.kg, 105)
  assert.deepEqual(m.befunde.map(b => b.pos_id), [2, 1])
  assert.equal(f.find(x => x.id === 'art:ohne_gewicht')!.kg, null, 'ohne Masse bleibt sie unbekannt, nie 0')
  const n = f.find(x => x.id === 'art:nachholen')!
  assert.equal(n.thema, 'auskunft')
  assert.equal(fallOffen(n, verlauf({})), false)
  const v = verlauf({ 'masse_abweichung:A:1': 'erledigt', 'masse_abweichung:A:2': 'erledigt' })
  const ids = (x: Partial<typeof FALL_FILTER_LEER>) => faelleFiltern(f, v, { ...FALL_FILTER_LEER, ...x }).map(y => y.id)
  assert.deepEqual(ids({}), ['art:ohne_gewicht'])
  assert.deepEqual(ids({ stand: 'erledigt' }), ['art:masse_abweichung'])
  assert.equal(ids({ stand: 'alle' }).length, 3)
  assert.deepEqual(faelleFiltern(faelleBilden([befund('menge_null', 134747, { kunde: 'Nordmarkt', nummern: '1648, 1719' })], []), new Map(),
    { ...FALL_FILTER_LEER, suche: 'nordm' }).map(y => y.id), ['art:menge_null'], 'der Kunde einer Position findet den Fall')
})
