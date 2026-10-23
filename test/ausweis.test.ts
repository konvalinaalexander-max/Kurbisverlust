import { test } from 'node:test'
import assert from 'node:assert/strict'
import { schritte, summiere } from '../src/auswertung/ausweis.ts'
import type { LagerAusweis } from '../src/auswertung/daten.ts'

// 0121 — der Betrieb: „wie viele Kilo im Lager sind, als Paletten … und daneben
// davon verkaufsfähig: minus Verdunstung (mit Lagerdauer und täglicher Rate),
// minus Palox, minus zu klein, zu gross … und vielleicht minus verschenkte Marge."

const a = (nr: number, x: Partial<LagerAusweis> = {}): LagerAusweis => ({
  charge_nr: nr, sorte: 'Amoro', schlag: 'S', paletten: 5, eingang_kg: 2000, alter_tage: 50,
  verdunstet_kg: 100, verdunstet_je_tag_kg: 2, faul_kg: 150, unique_kg: 0, hagel_anteil: null,
  zu_klein_kg: 40, zu_gross_kg: 60, fax_kg: 0, verkaufsfaehig_kg: 1650,
  marge_anteil: 0.05, marge_quelle: 'gewogen', marge_kg: 78.57, verrechenbar_kg: 1571.43, hagel_bis_heute_kg: 0,
  r_bekannt: true, f_bekannt: true, kanal_bekannt: true, fax_bekannt: true,
  keinen_artikel_kg: 0, groesse_offen_kg: 0, ueberfuellung_kg: 78.57, verkaufbar_kg: 1571.43, verkaufbar_offen: null,
  gruppe_offen_kg: 0, ...x })

test('summiere: die Kette geht auf; Paletten zusammengezählt; die Rate je Tag aus Lagerdauer und Verdunstung', () => {
  const s = summiere([a(1), a(2, { eingang_kg: 1000, paletten: 2, verdunstet_kg: 40, faul_kg: 60, zu_klein_kg: 20, zu_gross_kg: 30, verkaufsfaehig_kg: 850, alter_tage: 20, marge_kg: 40 })])
  assert.equal(s.paletten, 7)
  assert.equal(s.eingang, 3000)
  assert.equal(s.eingang, s.verdunstet + s.faul + s.unique + s.klein + s.gross + s.fax + s.verkaufsfaehig)
  assert.equal(Math.round(s.alterTage!), 40, 'Alter nach Masse gewichtet: (50·2000 + 20·1000) / 3000')
  assert.equal(s.rateJeTag!.toFixed(5), (140 / 3000 / 40).toFixed(5))
})

// Runde AZ: `marge`/`margeBekannt` (0121) las seit 0123 niemand mehr und sind
// weg — „ohne Marge keine Marge" heisst jetzt: eine nicht gewogene Charge
// zieht keine Überfüllung ab und steht als offen da (nie 0).
test('Leer ist nicht null: eine Charge ohne Rate fehlt in den Abzügen und wird gezählt; ohne Marge keine Marge', () => {
  const s = summiere([a(1), a(2, { verkaufsfaehig_kg: null, faul_kg: null }),
                      a(3, { marge_anteil: null, marge_kg: null, ueberfuellung_kg: null, verkaufbar_kg: 1650, verkaufbar_offen: 'Überfüllung nicht gewogen' })])
  assert.equal(s.luecken, 1)
  assert.equal(s.verkaufsfaehig, 3300)
  assert.equal(s.ueberfuellung, 78.57, 'nur die gewogene Charge')
  assert.equal(s.offen.get('Überfüllung nicht gewogen'), 1)
  assert.equal(schritte(s).some(x => x.name === 'verrechenbar'), false)
  // Ein Ausweis, dessen verkaufbar_kg leer ist, obwohl die Sortiermaschine eine Zahl hat, ist eine Lücke — keine 0.
  assert.equal(summiere([a(4, { verkaufbar_kg: null })]).luecken, 1)
})

// 0123 — die Regel hat sich geändert, der Test mit ihr: Die Kette endet nicht
// mehr beim Verkaufsfähigen der Sortiermaschine mit „davon Überfüllung …
// verrechenbar", sondern bei dem, was als Artikel verkauft werden kann; die
// Überfüllung ist ein Abzug, Unique ein „davon". Der Betrieb, 23. Oktober:
// „verkaufsfähig … minus allem: innerhalb der Artikelgewichte, verschenkte
// Marge abgezogen, Palox, Verdunstung."
test('schritte: Unique nur, wo Hagel ist; die Reihenfolge wie im Lager', () => {
  const ohne = schritte(summiere([a(1)]))
  assert.deepEqual(ohne.map(x => x.name), ['im Lager, wie eingegangen', 'verdunstet', 'Faules im Palox', 'zu klein', 'zu gross', 'Überfüllung', 'verkaufsfähig'])
  const mit = schritte(summiere([a(1, { unique_kg: 300, verkaufsfaehig_kg: 1350, ueberfuellung_kg: 64.29, verkaufbar_kg: 1585.71 })]))
  assert.ok(mit.some(x => x.name === 'davon Unique (Hagel)' && x.kg === 300 && x.art === 'davon'))
  assert.match(mit.find(x => x.name === 'verdunstet')!.wie!, /50 Tage gelagert, rund 0\.1 % je Tag/)
})

test('0123 — die Kette geht auf bis zu dem, was als Artikel verkauft werden kann', () => {
  // 2000 − 100 verdunstet − 150 faul − 40 zu klein − 60 zu gross − 120 passt in keinen Artikel
  // − Überfüllung 5 % auf 1530 (72.86) = 1457.14 verkaufbar
  const s = summiere([a(1, { keinen_artikel_kg: 120, ueberfuellung_kg: 72.86, verkaufbar_kg: 1457.14 })])
  const st = schritte(s)
  assert.deepEqual(st.map(x => x.name), ['im Lager, wie eingegangen', 'verdunstet', 'Faules im Palox', 'zu klein', 'zu gross',
    'passt in keinen Artikel', 'Überfüllung', 'verkaufsfähig'])
  const ab = st.filter(x => x.art === 'weg' || x.art === 'aussortiert').reduce((t, x) => t + x.kg, 0)
  assert.equal(Math.round((s.eingang - ab) * 100) / 100, st.find(x => x.art === 'ergebnis')!.kg, 'Eingang − alles Abgezogene = verkaufsfähig')
  assert.equal(s.verkaufbar, 1457.14)
  assert.equal(s.verkaufsfaehig, 1650, 'das Verkaufsfähige der Sortiermaschine bleibt daneben stehen')
})

test('0123 — Leer ist nicht null: nicht gewogene Überfüllung und Grösse ohne Sortier-CSV werden genannt, je Grund gezählt', () => {
  const s = summiere([
    a(1),
    a(2, { marge_anteil: null, marge_kg: null, ueberfuellung_kg: null, verkaufbar_kg: 1650, verkaufbar_offen: 'Überfüllung nicht gewogen' }),
    a(3, { groesse_offen_kg: 1650, marge_anteil: null, marge_kg: null, ueberfuellung_kg: null, verkaufbar_kg: 1650,
           verkaufbar_offen: 'Überfüllung nicht gewogen, Grösse offen (keine Sortier-CSV)' }),
  ])
  assert.equal(s.offen.get('Überfüllung nicht gewogen'), 2)
  assert.equal(s.offen.get('Grösse offen (keine Sortier-CSV)'), 1)
  assert.equal(s.ueberfuellung, 78.57, 'nur die gewogene Charge zieht Überfüllung ab — die anderen nicht mit 0, sondern als offen')
  assert.ok(schritte(s).some(x => x.name === 'davon Grösse offen' && x.kg === 1650))
})

test('0124 — eine Sorte ohne Artikelgruppe ist offen, nicht „passt in keinen Artikel": nicht abgezogen, als „davon" genannt', () => {
  const s = summiere([a(1), a(2, { gruppe_offen_kg: 438, verkaufbar_kg: 1571.43, verkaufbar_offen: 'Artikelgruppe fehlt (Stammdaten → Sorten)' })])
  assert.equal(s.gruppeOffen, 438)
  assert.equal(s.keinenArtikel, 0, 'die offene Gruppe zählt nicht als passt in keinen Artikel')
  assert.equal(s.offen.get('Artikelgruppe fehlt (Stammdaten → Sorten)'), 1)
  assert.ok(schritte(s).some(x => x.art === 'davon' && x.name === 'davon Artikelgruppe offen' && x.kg === 438))
})

test('0124 — Hagel 100 %: die Datenbank lässt Faules, Unique und Verkaufbares leer; die Charge ist eine Lücke, nie 0', () => {
  const s = summiere([a(1), a(2, { faul_kg: null, unique_kg: null, verkaufbar_kg: null, hagel_anteil: 1,
                                   verkaufbar_offen: 'Hagel 100 %: Unique und Faules nicht trennbar' })])
  assert.equal(s.luecken, 1)
  assert.equal(s.verkaufbar, 1571.43, 'nur die messbare Charge steht in der Summe')
  assert.equal(s.faul, 150)
})
