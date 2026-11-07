import { test } from 'node:test'
import assert from 'node:assert/strict'
import { leerSatz, ratenText, ueberzaehlungSatz } from '../src/auswertung/bedarf.ts'
import { ausZeile } from '../src/auswertung/ungereimt.ts'
import type { ChargeBedarf, UngereimtZeile } from '../src/auswertung/daten.ts'

// 0134 — der Betrieb am 7. November: „sicher ein Datenfehler", wenn mehr
// geliefert als hereingekommen ist; „die Rate passt nicht zur Charge", und das
// nur, wenn die Lieferungen ausserhalb der Spanne liegen. Ist eine Charge am
// Lager leer, „gilt Eingang minus geliefert als echter Verlust, und damit
// prüft die App ihre Raten".

const b = (x: Partial<ChargeBedarf> = {}): ChargeBedarf => ({
  charge_nr: 1630, sorte: 'Kaori Kuri', schlag: 'Feld Ost', eingang_kg: 10000, geliefert_kg: 8000, n_lieferungen: 12,
  bedarf_kg: 9000, bedarf_min_kg: 8600, bedarf_max_kg: 9500, ueberzaehlung_kg: 0, hagel: false,
  r: 0.0005, r_unten: 0.00045, r_oben: 0.00055, r_basis: 'Wiegungen dieser Sorte', f: 0.08, f_unten: 0.05, f_oben: 0.11,
  art: null, ueber_kg: null, melden: false, leer_am: null, leer: false,
  echt_verlust_kg: null, echt_anteil: null, gerechnet_anteil: null, gerechnet_unten: null, gerechnet_oben: null,
  urteil: null, weg_kg: null, n_nach_leer: 0, kg_nach_leer: null, erste_nach_leer: null, ...x,
})

test('Überzählung: Datenfehler, Rate, Spanne — und nichts, wenn es aufgeht', () => {
  assert.equal(ueberzaehlungSatz(b()), null, 'ohne Art kein Satz')
  assert.equal(ueberzaehlungSatz(undefined), null)
  const df = ueberzaehlungSatz(b({ art: 'datenfehler', geliefert_kg: 10520, ueber_kg: 520 }))!
  assert.equal(df.ton, 'warnung')
  assert.match(df.marke, /^520 kg mehr geliefert als hereinkam$/)
  assert.match(df.satz, /Geliefert 10.520 kg, hereingekommen 10.000 kg — das erklärt keine Rate: sicher ein Datenfehler\./)
  const ra = ueberzaehlungSatz(b({ art: 'rate', geliefert_kg: 9500, bedarf_kg: 10700, bedarf_min_kg: 10200, ueber_kg: 700 }))!
  assert.equal(ra.ton, 'warnung')
  assert.equal(ra.marke, 'Rate passt nicht zur Charge')
  assert.match(ra.satz, /brauchen mit den Raten 10.700 kg Eingang, auch günstig gerechnet noch 10.200 kg — hereingekommen sind 10.000 kg/)
  assert.match(ra.satz, /Verdunstung 0\.05 % je Tag, Palox 8 %/, 'nennt die Raten, mit denen gerechnet ist')
  const sp = ueberzaehlungSatz(b({ art: 'spanne', bedarf_kg: 10100, bedarf_min_kg: 9800, bedarf_max_kg: 10500, ueber_kg: 100 }))!
  assert.equal(sp.ton, 'leise', 'die Spanne ist eine Auskunft, keine Meldung')
  assert.match(sp.satz, /innerhalb der Spanne der Raten \(9.800 kg bis 10.500 kg\); die App meldet das nicht/)
  const tag = ueberzaehlungSatz(b({ art: 'spanne', bedarf_kg: 9900, ueberzaehlung_kg: 120, ueber_kg: 120 }))!
  assert.match(tag.satz, /^Ein Eingangstag ist mit den Raten um 120 kg überzogen, die ganze Charge nicht/)
})

test('Raten ohne Messung sagen es, statt 0 zu schreiben', () => {
  assert.equal(ratenText({ r: null, f: null }), 'ohne gemessene Verdunstung, ohne Palox-Rate')
})

test('Leer bestätigt: echter Verlust gegen die Raten, je Urteil ein Satz', () => {
  assert.equal(leerSatz(b()), null, 'nicht leer: kein Satz')
  const leer = (x: Partial<ChargeBedarf>) => leerSatz(b({ leer: true, leer_am: '2026-11-06', echt_verlust_kg: 2000, echt_anteil: 0.2,
    gerechnet_anteil: 0.111, gerechnet_unten: 0.07, gerechnet_oben: 0.158, ...x }))!
  const passt = leer({ urteil: 'passt', echt_anteil: 0.12, echt_verlust_kg: 1200 })
  assert.equal(passt.ton, 'fertig')
  assert.match(passt.satz, /^Echter Verlust 1.200 kg = Eingang 10.000 kg − geliefert 8.000 kg \(12\.0 %\); die Raten rechneten 11\.1 % \(7\.0 % bis 15\.8 %\) — das passt\.$/)
  const mehr = leer({ urteil: 'mehr_weg' })
  assert.equal(mehr.ton, 'warnung')
  assert.match(mehr.satz, /Mehr verloren, als die Raten erwarten .* oder Ware ging ohne Lieferschein hinaus\./)
  assert.match(leer({ urteil: 'weniger_weg', echt_anteil: 0.05 }).satz, /verlor weniger als ihre Sorte/)
  assert.match(leer({ urteil: 'datenfehler', geliefert_kg: 10500 }).satz, /sicher ein Datenfehler/)
  assert.match(leer({ urteil: 'ohne_lieferung', geliefert_kg: 0, gerechnet_anteil: null }).satz, /Unter dieser Nummer ging nichts hinaus/)
  assert.equal(leer({ urteil: 'passt' }).nachher, null)
  const nach = leer({ urteil: 'passt', n_nach_leer: 2, kg_nach_leer: 700, erste_nach_leer: '2026-11-07' })
  assert.match(nach.nachher!, /^2 Lieferscheine mit 700 kg kamen nach dem 06\.11\.2026 \(zuerst am 07\.11\.2026\) — war die Charge da schon leer, gehört sie wohl einer anderen\.$/)
})

const zeile = (mehr: Record<string, unknown>): UngereimtZeile =>
  ({ art: 'ueberzaehlung', charge_nr: 1630, sorte: 'Kaori Kuri', schlag: 'Feld Ost', kg: 520, n: 12, von: null, bis: null, mehr })

test('Die Sache „mehr verkauft als möglich" sagt, welche sie ist', () => {
  const df = ausZeile(zeile({ art: 'datenfehler', geliefert_kg: 10520, eingang_kg: 10000, ausgelagert_kg: 11800 }), [])
  assert.match(df.titel, /hat mehr geliefert, als hereinkam$/)
  assert.match(df.was, /^Geliefert sind 10.520 kg, hereingekommen 10.000 kg — 520 kg mehr, als je da war\.$/)
  assert.match(df.warum, /sicher ein Datenfehler/)
  const ra = ausZeile(zeile({ art: 'rate', geliefert_kg: 9500, eingang_kg: 10000, ausgelagert_kg: 10520, bedarf_kg: 10520, bedarf_min_kg: 10200 }), [])
  assert.equal(ra.schwere, 'gelb', 'eine Rate, die nicht passt, ist kein sicherer Fehler')
  assert.match(ra.titel, /die Raten passen nicht zur Charge$/)
  assert.match(ra.was, /auch günstig gerechnet noch 10.200 kg — eingegangen sind 10.000 kg\. Es fehlen 520 kg\./)
  assert.match(ra.tun, /„Charge ist leer"/)
  const alt = ausZeile(zeile({ geliefert_kg: 9500, eingang_kg: 10000, ausgelagert_kg: 10520 }), [])
  assert.match(alt.titel, /hat mehr verkauft, als sie hergeben kann$/, 'eine Zeile ohne Art (vor 0134) erzählt wie bisher')
})
