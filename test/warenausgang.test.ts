import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { xlsxLesen, serieAlsDatum } from '../src/lib/xlsx.ts'
import {
  kopfLesen, zeilenLesen, zeilenSchluessel, fingerabdruck, istKuerbis,
  befund, abgleichen, lieferungenBauen, quelleVorschlag, schluessel, chargeAufloeser,
} from '../src/lib/warenausgang.ts'

const HIER = dirname(fileURLToPath(import.meta.url))
const PROBE = join(HIER, 'daten', 'warenausgang-probe.xlsx')
// Die Chargen der eigenen Ernte; alles andere ist eine fremde Chargennummer.
const REGISTRY = new Map([[1613, 'Tiana'], [1614, 'Kaori Kuri'], [1615, 'Ker Madec'],
                         [1617, 'Orangita'], [1626, 'Tiana']])
const chargeVon = (e: string) => (REGISTRY.has(Number(e)) ? Number(e) : null)

async function probe(quelle = 'probe') {
  const blaetter = await xlsxLesen(readFileSync(PROBE))
  return zeilenLesen(blaetter[0], quelle)
}

/* ---------- Der Leser ----------------------------------------------------- */

test('liest eine .xlsx ohne Bibliothek: Texte, Zahlen, Daten', async () => {
  const blaetter = await xlsxLesen(readFileSync(PROBE))
  assert.equal(blaetter.length, 1)
  assert.equal(blaetter[0].name, 'Tabelle S. 1')
  const kopf = blaetter[0].zeilen[0]
  assert.equal(kopf[0], 'AuftragsErfasser')
  assert.equal(kopf[31], 'TotalGewicht')
  const erste = blaetter[0].zeilen[1]
  assert.equal(erste[1], 'A')                       // geteilter Text
  assert.equal(erste[16], 160)                      // Zahl
  assert.ok(erste[5] instanceof Date)               // Datum als Datum, nicht als Zahl
  assert.equal((erste[5] as Date).toISOString().slice(0, 10), '2026-09-01')
})

test('eine leere Zelle verschluckt den Wert der nächsten nicht', async () => {
  // Genau dieser Fehler stand einmal drin: `<c r="D2" s="1"/>` hat einen
  // Schrägstrich vor dem `>`, und ein gieriges Muster las bis zum `</c>` der
  // *nächsten* Zelle. Die Spalten waren dann um eins verschoben — ohne Fehler.
  const blaetter = await xlsxLesen(readFileSync(PROBE))
  const z = blaetter[0].zeilen[1]
  assert.equal(z[3], null, 'AuftragsReferenz ist leer')
  assert.equal(z[4], null, 'AuftragsRuestDatum ist leer')
  assert.ok(z[5] instanceof Date, 'AuftragsLieferDatum trägt das Datum')
})

test('Excel-Tagesnummern werden zum richtigen Datum', () => {
  assert.equal(serieAlsDatum(46271).toISOString().slice(0, 10), '2026-09-06')
  assert.equal(serieAlsDatum(45658).toISOString().slice(0, 10), '2025-01-01')
})

/* ---------- Kopf und Zeilen ---------------------------------------------- */

test('erkennt den Kopf auch bei anderer Schreibweise', () => {
  const kopf = kopfLesen([['AuftragsLieferDatum', 'auftragsartikelmengesoll', 'AufPosId',
                           'AuftragsArtId', 'AuftragsArtikel', 'AuftragsArtikelMenge',
                           'AufPosBatchQuantity  Charge', 'AuftragsChargeManuell',
                           'GewichtProArtikel', 'AuftragsLieferant']])
  assert.ok(kopf)
  assert.equal(kopf.zeile, 0)
  assert.deepEqual(kopf.fehlend, [], 'alle Pflichtspalten gefunden')
  assert.equal(kopf.index.pos_id, 2)
})

test('meldet fehlende Pflichtspalten, statt still zu raten', () => {
  const kopf = kopfLesen([['AuftragsLieferDatum', 'AuftragsLieferant', 'AuftragsArtId',
                           'AuftragsArtikel', 'AuftragsArtikelMenge', 'AuftragsJournal']])
  assert.ok(kopf)
  assert.ok(kopf.fehlend.includes('pos_id'))
  assert.ok(kopf.fehlend.includes('gewicht_je_artikel'))
})

test('ohne erkennbaren Kopf kommt keine einzige Zeile durch', () => {
  const e = zeilenLesen({ name: 'x', zeilen: [['a', 'b'], [1, 2]] }, 'q')
  assert.equal(e.kopf, null)
  assert.equal(e.zeilen.length, 0)
})

test('liest die Probedatei: Menge mal Gewicht ist die Masse', async () => {
  const { zeilen, uebersprungen } = await probe()
  assert.equal(uebersprungen, 1, 'die Zeile ohne Positions-Id wird gezählt, nicht verschwiegen')
  const erste = zeilen[0]
  assert.equal(erste.pos_id, 5001)
  assert.equal(erste.charge_extern, '1613')
  assert.equal(erste.kg_position, 240, '160 Stück à 1.5 kg')
  assert.equal(erste.kg_charge, 150, '100 Stück à 1.5 kg')
  assert.equal(erste.kunde, 'Grosshandel Zürich')
  assert.equal(erste.gebindeart, 'G2')
})

test('nimmt das Rüstdatum, wenn das Lieferdatum fehlt', async () => {
  const { zeilen } = await probe()
  const z = zeilen.find(x => x.pos_id === 5008)!
  assert.equal(z.datum, '2026-09-06')
})

test('zwei gleiche Zeilen bleiben zwei Zeilen (Laufnummer)', async () => {
  const { zeilen } = await probe()
  const doppelt = zeilen.filter(z => z.pos_id === 5004)
  assert.equal(doppelt.length, 2)
  assert.deepEqual(doppelt.map(z => z.lauf_nr), [1, 2])
  assert.notEqual(zeilenSchluessel(doppelt[0]), zeilenSchluessel(doppelt[1]))
})

/* ---------- Kürbis oder nicht --------------------------------------------- */

test('erkennt Kürbis am Artikel, nicht am Zufall', async () => {
  const { zeilen } = await probe()
  const karotte = zeilen.find(z => z.artikel_id === 'karod')!
  const kuerbis = zeilen.find(z => z.artikel_id === 'kürbbu')!
  assert.equal(istKuerbis(karotte), 'vorschlag_nein')
  assert.equal(istKuerbis(kuerbis), 'vorschlag_ja')
})

test('eine Verrechnung ist keine Ware, auch wenn Kürbis draufsteht', async () => {
  const { zeilen } = await probe()
  const buchung = zeilen.find(z => z.artikel_id === 'kürbver')!
  assert.equal(istKuerbis(buchung), 'vorschlag_nein')
})

test('die bestätigte Zuordnung schlägt die Regel — in beide Richtungen', async () => {
  const { zeilen } = await probe()
  const karotte = zeilen.find(z => z.artikel_id === 'karod')!
  const kuerbis = zeilen.find(z => z.artikel_id === 'kürbbu')!
  const bestaetigt = new Map([
    ['karod|Bio-Karotten Demeter', true],
    ['kürbbu|Bio Kürbis Butternut', false],
  ])
  assert.equal(istKuerbis(karotte, bestaetigt), 'ja')
  assert.equal(istKuerbis(kuerbis, bestaetigt), 'nein')
})

/* ---------- Befund -------------------------------------------------------- */

test('zählt die Positionsmasse je Position einmal, nicht je Chargenzeile', async () => {
  const { zeilen } = await probe()
  const b = befund(zeilen)
  // 5001 ist über zwei Chargen verteilt: 240 kg, nicht 480.
  assert.equal(b.positionen, 6, 'sechs Kürbis-Positionen (ohne Karotte und Verrechnung)')
  assert.equal(b.kg_position, 240 + 80 + 200 + 9.5 - 300 + 22)
  assert.equal(b.kg_charge, 150 + 90 + 80 + 9.5 + 9.5 + 22)
  assert.equal(b.von, '2026-09-01')
  assert.equal(b.bis, '2026-09-06')
})

test('führt jede Charge mit ihrer Masse auf', async () => {
  const { zeilen } = await probe()
  const b = befund(zeilen)
  const m = new Map(b.chargen.map(c => [c.charge_extern, c.kg]))
  assert.equal(m.get('1613'), 150)
  assert.equal(m.get('1626'), 90)
  assert.equal(m.get('1615'), 80)
  assert.equal(m.get('1614'), 19, 'die doppelte Zeile zählt zweimal — so steht sie in der Datei')
  assert.equal(m.get('199001'), undefined, 'eine Kandidatenzeile ohne Menge trägt nichts bei')
})

test('listet jeden Artikel mit seinem Urteil auf', async () => {
  const { zeilen } = await probe()
  const b = befund(zeilen)
  const karotte = b.artikel.find(a => a.artikel_id === 'karod')!
  assert.equal(karotte.urteil, 'vorschlag_nein')
  assert.ok(b.artikel.some(a => a.artikel_id === 'kürbver' && a.urteil === 'vorschlag_nein'))
  assert.ok(b.artikel.every(a => a.zeilen > 0))
})

/* ---------- Abgleich ------------------------------------------------------ */

test('dieselbe Datei zweimal: nichts ist neu', async () => {
  const { zeilen } = await probe()
  const bekannt = zeilen.map(z => ({ schluessel: zeilenSchluessel(z), fingerabdruck: z.fingerabdruck }))
  const a = abgleichen(zeilen, bekannt)
  assert.equal(a.neu.length, 0)
  assert.equal(a.geaendert.length, 0)
  assert.equal(a.unveraendert, zeilen.length)
  assert.equal(a.verschwunden.length, 0)
})

test('eine geänderte Menge fällt auf, eine neue Zeile auch', async () => {
  const { zeilen } = await probe()
  const bekannt = zeilen.slice(1).map(z => ({ schluessel: zeilenSchluessel(z), fingerabdruck: z.fingerabdruck }))
  bekannt[0] = { ...bekannt[0], fingerabdruck: 'alt' }
  const a = abgleichen(zeilen, bekannt)
  assert.equal(a.neu.length, 1, 'die erste Zeile kannte die Datenbank noch nicht')
  assert.equal(a.geaendert.length, 1, 'die zweite hat sich geändert')
  assert.equal(a.unveraendert, zeilen.length - 2)
})

test('was in der Datei fehlt, wird gemeldet statt vergessen', async () => {
  const { zeilen } = await probe()
  const bekannt = zeilen.map(z => ({ schluessel: zeilenSchluessel(z), fingerabdruck: z.fingerabdruck }))
  bekannt.push({ schluessel: 'probe|9999||1', fingerabdruck: 'x' })
  const a = abgleichen(zeilen, bekannt)
  assert.deepEqual(a.verschwunden, ['probe|9999||1'])
})

test('der Fingerabdruck ändert sich mit jedem Feld', () => {
  const a = fingerabdruck(['2026-09-01', 'A', 'Coop', 160])
  assert.equal(a, fingerabdruck(['2026-09-01', 'A', 'Coop', 160]))
  assert.notEqual(a, fingerabdruck(['2026-09-01', 'A', 'Coop', 161]))
  assert.notEqual(a, fingerabdruck(['2026-09-02', 'A', 'Coop', 160]))
  // Ohne Trenner wären ['ab','c'] und ['a','bc'] dasselbe.
  assert.notEqual(fingerabdruck(['ab', 'c']), fingerabdruck(['a', 'bc']))
})

/* ---------- Lieferungen --------------------------------------------------- */

test('aus einer Position werden Lieferungen, deren Summe die Position ist', async () => {
  const { zeilen } = await probe()
  const kuerbis = zeilen.filter(z => istKuerbis(z).endsWith('ja'))
  const { lieferungen, ruecknahmen } = lieferungenBauen(kuerbis, chargeVon, () => null)
  const summe = lieferungen.reduce((s, l) => s + l.kg, 0)
  const zurueck = ruecknahmen.reduce((s, l) => s + l.kg, 0)
  const positionen = new Map(kuerbis.map(z => [z.pos_id, z.kg_position]))
  const soll = [...positionen.values()].reduce((a, b) => a + b, 0)
  assert.equal(summe - zurueck, soll, 'kein Kilo erfunden, keines verloren')
})

test('die Rücknahme verschwindet nicht, sie steht getrennt', async () => {
  const { zeilen } = await probe()
  const { ruecknahmen } = lieferungenBauen(zeilen.filter(z => istKuerbis(z).endsWith('ja')), chargeVon, () => null)
  assert.equal(ruecknahmen.length, 1)
  assert.equal(ruecknahmen[0].kg, 300)
  assert.match(ruecknahmen[0].bemerkung, /Rücknahme/)
})

test('eine Position ohne Chargenbezug wird trotzdem geliefert', async () => {
  const { zeilen } = await probe()
  const { lieferungen } = lieferungenBauen(zeilen.filter(z => istKuerbis(z).endsWith('ja')), chargeVon, () => null)
  const ohne = lieferungen.filter(l => l.bemerkung === 'ohne Chargenbezug')
  assert.ok(ohne.some(l => l.kg === 200), 'die 200 kg ohne Charge zählen in die Bilanz')
  assert.ok(ohne.every(l => l.charge_nr === null))
})

test('eine fremde Chargennummer wird nicht zur eigenen Charge erfunden', async () => {
  const { zeilen } = await probe()
  const { lieferungen } = lieferungenBauen(zeilen.filter(z => istKuerbis(z).endsWith('ja')), chargeVon, () => null)
  const fremd = lieferungen.filter(l => l.bemerkung.startsWith('Charge '))
  assert.ok(fremd.every(l => l.charge_nr === null))
})

test('jede Lieferung trägt eine eindeutige Kennung — sonst doppelt sie beim nächsten Mal', async () => {
  const { zeilen } = await probe()
  const { lieferungen } = lieferungenBauen(zeilen.filter(z => istKuerbis(z).endsWith('ja')), chargeVon, () => null)
  const ids = new Set(lieferungen.map(l => l.extern_id))
  assert.equal(ids.size, lieferungen.length)
})

test('die Sorte kommt aus der Zuordnung, nicht aus dem Artikelnamen', async () => {
  const { zeilen } = await probe()
  const sorteVon = (z: { charge_extern: string; artikel_id: string }) =>
    REGISTRY.get(Number(z.charge_extern)) ?? (z.artikel_id.startsWith('kürbbu') ? 'Tiana' : null)
  const { lieferungen } = lieferungenBauen(zeilen.filter(z => istKuerbis(z).endsWith('ja')), chargeVon, sorteVon)
  assert.ok(lieferungen.some(l => l.charge_nr === 1613 && l.sorte === 'Tiana'))
  assert.ok(lieferungen.some(l => l.charge_nr === null && l.sorte === null))
})

/* ---------- Kleinkram ----------------------------------------------------- */

test('schlägt eine Herkunft aus dem Dateinamen vor', () => {
  assert.equal(quelleVorschlag('Imhofbio__AbgleichRückverfolgbarkeit_SeitAnfangJahr_Gemüse.xlsx'), 'imhofbio')
  assert.equal(quelleVorschlag('Imhof_BioProdukte__AbgleichRückverfolgbarkeit_SeitAnfangJahr_Gemüse.xlsx'),
               'imhof-bioprodukte')
  assert.equal(quelleVorschlag('   .xlsx'), 'unbekannt')
})

test('Kopfnamen werden ohne Schreibweise verglichen', () => {
  assert.equal(schluessel('AuftragsArtikelMengeSoll'), schluessel('auftragsartikelmengesoll'))
  assert.equal(schluessel('AufPosBatchQuantity Charge'), schluessel('aufposbatchquantitycharge'))
})

/* ---------- Die Perigon-Nummer (0051) ------------------------------------- */

test('sechsstellige Perigon-Nummern werden über charge.perigon_nr aufgelöst', () => {
  const chargen = [
    { nr: 1613, sorte: 'Tiana', perigon_nr: 198923 },
    { nr: 1649, sorte: 'Butterkin', perigon_nr: 198976 },
    { nr: 1650, sorte: 'Tiana', perigon_nr: 198976 },
    { nr: 1614, sorte: 'Kaori Kuri', perigon_nr: null },
  ]
  const artikel = (z: { artikel: string }) => (/butterkin/i.test(z.artikel) ? 'Butterkin' : /butternut/i.test(z.artikel) ? 'Tiana' : null)
  const loese = chargeAufloeser(chargen, artikel)
  assert.equal(loese('1613'), 1613, 'die eigene Nummer bleibt die eigene')
  assert.equal(loese('198923'), 1613, 'die Perigon-Nummer führt zur eigenen Charge')
  assert.equal(loese('Lot 198923'), 1613, 'Buchstaben um die Nummer stören nicht')
  assert.equal(loese('1614'), 1614, 'auch ohne Perigon-Nummer')
  assert.equal(loese('199999'), null, 'eine fremde Nummer bleibt ohne Bezug')
  assert.equal(loese(''), null)
  // Die doppelte Nummer: der Artikel entscheidet, sonst nichts.
  assert.equal(loese('198976'), null, 'ohne Artikel ist die doppelte Nummer nicht zu entscheiden')
  assert.equal(loese('198976', { artikel_id: 'kuerbk', artikel: 'Bio Kürbis Muscat/Butterkin Dem gross' }), 1649)
  assert.equal(loese('198976', { artikel_id: 'kuerbu', artikel: 'Bio Kürbis Butternut Dem klein' }), 1650)
  assert.equal(loese('198976', { artikel_id: 'div', artikel: 'Bio Kürbis Mix' }), null, 'passt der Artikel zu keiner, bleibt es offen')
})
