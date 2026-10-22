import { test } from 'node:test'
import assert from 'node:assert/strict'
import { durchgang, ROHTABELLEN } from '../pruefstand/durchgang_pruefungen.mjs'

const HEUTE = '2026-09-28'
const leer = () => Object.fromEntries(Object.keys(ROHTABELLEN).map(n => [n, []]))
const gebinde = [{ art: 'G2', tara_kg_pro_kiste: 1.5, tara_kg_palette: 25 }]
const arten = (erg: { befunde: { pruefung: string }[] }) => erg.befunde.map(b => b.pruefung)

test('eine Teilpalette: 18 von 36 Kisten gewogen, der Zettel gilt für die ganze Palette', () => {
  const d = { ...leer(), gebinde,
    palette: [{ id: 1, charge_nr: 1613, eingangsdatum: '2026-08-01', brutto_kg: 400, kisten: 36, gebindeart: 'G2' }],
    auftrag: [{ id: 10, weg: 'hand', station: 'waschen_sortieren', charge_nr: 1613, start_ts: '2026-09-10T08:00:00Z', ende_ts: '2026-09-10T12:00:00Z', status: 'abgeschlossen' }],
    verdunstung_wiegung: [{ id: 5, auftrag_id: 10, charge_nr: 1613, palette_id: 1, eingangsdatum: '2026-08-01', brutto_damals_kg: 400, brutto_jetzt_kg: 200, kisten: 18, gebindeart: 'G2', wiege_ts: '2026-09-10T09:00:00Z' }],
  }
  const erg = durchgang(d, HEUTE)
  const t = erg.befunde.find(b => b.pruefung === 'Teilpalette')
  assert.ok(t, 'die Teilpalette wird nicht erkannt')
  assert.equal(t!.schwere, 'hoch')
  assert.equal(t!.werte.netto_damals_ganz_kg, 348)
  assert.equal(t!.werte.netto_damals_anteilig_kg, 174)
  // Und sie wird nicht zusätzlich als „Verdunstung zu hoch" gemeldet.
  assert.ok(!arten(erg).includes('Verdunstung zu hoch'))
})

test('mehr Kisten gewogen als am Eingang ist auch eine Teilpalette-Meldung', () => {
  const d = { ...leer(), gebinde,
    palette: [{ id: 1, charge_nr: 1613, eingangsdatum: '2026-08-01', brutto_kg: 400, kisten: 30, gebindeart: 'G2' }],
    verdunstung_wiegung: [{ id: 5, auftrag_id: null, charge_nr: 1613, palette_id: 1, eingangsdatum: '2026-08-01', brutto_damals_kg: 400, brutto_jetzt_kg: 390, kisten: 36, gebindeart: 'G2', wiege_ts: '2026-09-10T09:00:00Z' }],
  }
  const t = durchgang(d, HEUTE).befunde.find(b => b.pruefung === 'Teilpalette')
  assert.match(t!.warum, /Mehr Kisten gewogen/)
})

test('Verdunstung zu hoch ohne erkennbare Teilpalette; schwerer geworden', () => {
  const d = { ...leer(), gebinde,
    verdunstung_wiegung: [
      { id: 1, charge_nr: 1613, palette_id: null, eingangsdatum: '2026-08-01', brutto_damals_kg: 400, brutto_jetzt_kg: 200, kisten: 18, gebindeart: 'G2', wiege_ts: '2026-09-10T09:00:00Z' },
      { id: 2, charge_nr: 1613, palette_id: null, eingangsdatum: '2026-08-01', brutto_damals_kg: 400, brutto_jetzt_kg: 430, kisten: 36, gebindeart: 'G2', wiege_ts: '2026-09-10T09:00:00Z' },
      { id: 3, charge_nr: 1613, palette_id: null, eingangsdatum: '2026-08-01', brutto_damals_kg: 400, brutto_jetzt_kg: 392, kisten: 36, gebindeart: 'G2', wiege_ts: '2026-09-10T09:00:00Z' },
    ],
  }
  const a = arten(durchgang(d, HEUTE))
  assert.deepEqual(a.filter(x => x === 'Verdunstung zu hoch').length, 1)
  assert.deepEqual(a.filter(x => x === 'Schwerer geworden').length, 1)
})

test('Eingang: Gewicht je Kiste und Kistenzahl ausser Rahmen; ein Paar gleicher Zettel ist kein Kandidat', () => {
  const d = { ...leer(), gebinde,
    palette: [
      { id: 1, charge_nr: 1, eingangsdatum: '2026-08-01', brutto_kg: 4000, kisten: 36, gebindeart: 'G2' },   // 110 kg je Kiste
      { id: 2, charge_nr: 1, eingangsdatum: '2026-08-01', brutto_kg: 400, kisten: 360, gebindeart: 'G2' },   // 360 Kisten
      { id: 3, charge_nr: 1, eingangsdatum: '2026-08-02', brutto_kg: 400, kisten: 36, gebindeart: 'G2' },
      { id: 4, charge_nr: 1, eingangsdatum: '2026-08-02', brutto_kg: 400, kisten: 36, gebindeart: 'G2' },
    ],
  }
  const a = arten(durchgang(d, HEUTE))
  assert.ok(a.includes('Eingang Gewicht je Kiste'))
  assert.ok(a.includes('Eingang Kisten'))
  // Regel geändert (Runde AC), also der Test mit ihr: zwei gleiche Zettel an
  // einem Tag sind Zufall (Saison 2026: 750 Paare, 590 erwartet) — erst ein
  // Tag mit deutlich mehr Paaren, als der Zufall erklärt, ist ein Kandidat.
  assert.equal(a.filter(x => x === 'Doppelte Palette').length, 0)
})

test('Doppelte Palette: acht identische Zettel an einem Tag sind Abschreiben; Vervielfachungen des Journals zählen nicht', () => {
  const d = { ...leer(), gebinde,
    palette: [
      ...Array.from({ length: 8 }, (_, i) => ({ id: i + 1, charge_nr: 1, eingangsdatum: '2026-08-01', brutto_kg: 400, kisten: 36, gebindeart: 'G2', extern_id: `journal:${i}` })),
      // „3 Paletten à 384 kg" im Journal: eine Zeile, drei Paletten (#2, #3)
      { id: 21, charge_nr: 2, eingangsdatum: '2026-08-01', brutto_kg: 384, kisten: 32, gebindeart: 'G2', extern_id: '2|2026-08-01|384' },
      { id: 22, charge_nr: 2, eingangsdatum: '2026-08-01', brutto_kg: 384, kisten: 32, gebindeart: 'G2', extern_id: '2|2026-08-01|384#2' },
      { id: 23, charge_nr: 2, eingangsdatum: '2026-08-01', brutto_kg: 384, kisten: 32, gebindeart: 'G2', extern_id: '2|2026-08-01|384#3' },
    ],
  }
  const erg = durchgang(d, HEUTE)
  const dp = erg.befunde.filter(b => b.pruefung === 'Doppelte Palette')
  assert.equal(dp.length, 1)
  assert.equal(dp[0].wo, 'Charge 1 · 2026-08-01')
  assert.equal(dp[0].werte.paare_gleich, 28)
  assert.match(erg.hinweise.join(' '), /2 Paletten sind Vervielfachungen/)
})

test('Gebinde ohne Tara: ein Holz-Palox mit 318 kg ist keine 291-kg-Kiste, sondern ein fehlendes Leergewicht', () => {
  const d = { ...leer(), gebinde: [...gebinde, { art: 'Holz Palox', tara_kg_pro_kiste: null, tara_kg_palette: null }],
    palette: [
      { id: 1, charge_nr: 1638, eingangsdatum: '2026-09-10', brutto_kg: 318, kisten: 1, gebindeart: 'Holz Palox' },
      { id: 2, charge_nr: 1638, eingangsdatum: '2026-09-10', brutto_kg: 315, kisten: 1, gebindeart: 'Holz Palox' },
      { id: 3, charge_nr: 1638, eingangsdatum: '2026-09-10', brutto_kg: 500, kisten: 36, gebindeart: 'Fantasiekiste' },   // unbekannte Art: auch ohne Tara
    ],
  }
  const erg = durchgang(d, HEUTE)
  assert.ok(!arten(erg).includes('Eingang Gewicht je Kiste'))
  const g = erg.befunde.filter(b => b.pruefung === 'Gebinde ohne Tara')
  assert.equal(g.length, 2)
  assert.equal(g.find(b => b.wo === 'Gebindeart Holz Palox')!.werte.paletten, 2)
})

test('Palox mit Tara: 311 kg brutto sind 276 kg in einem Palox, keine 276-kg-Kiste — 31 kg sind vertippt; ins Kistenmittel zählt er nicht', () => {
  // Regel geändert (22. Oktober): Seit die Paloxe ihre Tara haben (Runde AS),
  // mass sie die Kistengrenze 4–30 kg — 100 Meldungen im Abzug, alle Palox.
  // Ein Palox hat jetzt seinen eigenen Rahmen (50–1000 kg netto).
  const d = { ...leer(), gebinde: [...gebinde, { art: 'Plastik Palox', tara_kg_pro_kiste: 35, tara_kg_palette: 0 }, { art: 'Holz Palox', tara_kg_pro_kiste: 45, tara_kg_palette: 0 }],
    palette: [
      { id: 1, charge_nr: 1719, eingangsdatum: '2026-10-22', brutto_kg: 311, kisten: 1, gebindeart: 'Plastik Palox' },
      { id: 2, charge_nr: 1637, eingangsdatum: '2026-10-22', brutto_kg: 304, kisten: 1, gebindeart: 'Holz Palox' },
      { id: 3, charge_nr: 1719, eingangsdatum: '2026-10-22', brutto_kg: 31, kisten: 1, gebindeart: 'Plastik Palox' },   // 311 ohne die 1
      // dieselbe Charge auch in G2: 470 kg auf 36 Kisten, 11.4 kg je Kiste
      { id: 4, charge_nr: 1637, eingangsdatum: '2026-10-21', brutto_kg: 470, kisten: 36, gebindeart: 'G2' },
    ],
    auftrag: [{ id: 1, station: 'sortieren', charge_nr: 1637, start_ts: '2026-10-22T08:00:00Z', ende_ts: '2026-10-22T09:00:00Z', status: 'abgeschlossen' }],
    auftrag_palette: [{ id: 1, auftrag_id: 1, palette_id: null, brutto_zettel_kg: 470, kisten: 36, gebindeart: 'G2', eingangsdatum: '2026-10-21' }],
  }
  const erg = durchgang(d, '2026-10-22')
  const g = erg.befunde.filter(b => b.pruefung === 'Eingang Gewicht je Kiste')
  assert.equal(g.length, 1)
  assert.equal(g[0].wo, 'Palette 3 · Charge 1719 · 2026-10-22')
  assert.match(g[0].warum, /je Palox — ausserhalb von 50–1000 kg/)
  // Der Holz-Palox (259 kg netto) zieht das Kistenmittel von 1637 nicht hoch:
  // der G2-Zettel trifft es genau.
  assert.ok(!arten(erg).includes('Zettelgewicht'))
})

test('Eingangsdatum springt zurück: 02.10. nach 22.10. ist eine Ziffer — 03.07. zwischen 31.07. und 03.08. auch; ein Tag Nachtrag ist keiner', () => {
  const p = (id: number, charge_nr: number, eingangsdatum: string) => ({ id, charge_nr, eingangsdatum, brutto_kg: 470, kisten: 36, gebindeart: 'G2' })
  const d = { ...leer(), gebinde,
    palette: [
      p(1, 1719, '2026-10-22'), p(2, 1719, '2026-10-22'), p(3, 1719, '2026-10-02'), p(4, 1719, '2026-10-02'), p(5, 1719, '2026-10-02'),
      p(10, 1616, '2026-07-31'), p(11, 1616, '2026-07-03'), p(12, 1616, '2026-07-03'), p(13, 1616, '2026-08-03'),
      p(20, 1630, '2026-09-10'), p(21, 1630, '2026-09-09'), p(22, 1630, '2026-09-11'),   // gestern nachgetragen: normal
      p(30, 1631, '2026-09-20'), p(31, 1631, '2026-08-28'), p(32, 1631, '2026-09-21'),   // drei Wochen, mehr als eine Ziffer
      p(40, 1650, '2026-10-22'), p(41, 1650, '2026-10-12'), p(42, 1650, '2026-10-02'),   // ein Lauf mit zwei Daten: einmal gemeldet
    ],
  }
  const erg = durchgang(d, '2026-10-22')
  const z = erg.befunde.filter(b => b.pruefung === 'Eingangsdatum springt zurück')
  assert.equal(z.length, 4)
  const oe = z.find(b => b.wo.startsWith('Charge 1719'))!
  assert.equal(oe.wo, 'Charge 1719 · Palette 3–5')
  assert.equal(oe.werte.paletten, 3)
  assert.equal(oe.werte.tage_zurueck, 20)
  assert.equal(oe.werte.wohl, '2026-10-22')
  // Text geändert (22. Oktober): Die 50 Oettli-Paloxe vom 02.10. waren vom
  // Papier nachgetragen, das Datum stimmte. Die Meldung nennt jetzt beides.
  assert.match(oe.warum, /3 Paletten mit Eingang 2026-10-02, erfasst nach Paletten vom 2026-10-22 — 20 Tage früher\. Vom Papier nachgetragen\? Dann stimmt es\. Sonst wohl vertippt \(eine Ziffer Unterschied zum 2026-10-22\):/)
  assert.match(oe.warum, /Jetzt vom Sheet holen/)
  const sg = z.find(b => b.wo.startsWith('Charge 1616'))!
  assert.equal(sg.wo, 'Charge 1616 · Palette 11–12')
  assert.equal(sg.werte.wohl, '2026-08-03')
  const ohne = z.find(b => b.wo.startsWith('Charge 1631'))!
  assert.equal(ohne.wo, 'Charge 1631 · Palette 31')
  assert.equal(ohne.werte.wohl, null)
  assert.doesNotMatch(ohne.warum, /vertippt/)
  assert.match(ohne.warum, /Vom Papier nachgetragen\? Dann stimmt es\. Sonst im Journal berichtigen/)
  const zwei = z.filter(b => b.wo.startsWith('Charge 1650'))
  assert.equal(zwei.length, 1)
  assert.equal(zwei[0].wo, 'Charge 1650 · Palette 41–42')
  assert.equal(zwei[0].werte.eingang, '2026-10-02, 2026-10-12')
  assert.equal(zwei[0].werte.wohl, null)
})

// 22. Oktober: Arbeit 1602 lief auf 1627 (Rüegg · Fictor, ohne Eingang); ihre
// fünf Zettel sind aufs Kilo die IFCO-Paletten, die das Journal als 1625
// (Rüegg · Amoro) führt — andere Sorte, andere Kistenzahl, ein Tag daneben.
test('Arbeit auf fremder Charge: fünf Zettel passen aufs Kilo zu einer anderen Charge — Sorte, Kisten und ein Tag dürfen abweichen', () => {
  const pal = (id: number, charge_nr: number, kg: number, tag = '2026-09-23', kisten = 32) =>
    ({ id, charge_nr, eingangsdatum: tag, brutto_kg: kg, kisten, gebindeart: 'G2' })
  const zettel = (id: number, auftrag_id: number, kg: number, tag = '2026-09-22', kisten = 36) =>
    ({ id, auftrag_id, palette_id: null, brutto_zettel_kg: kg, kisten, gebindeart: 'G2', eingangsdatum: tag })
  const arbeit = (id: number, charge_nr: number) =>
    ({ id, station: 'waschen_sortieren', charge_nr, start_ts: '2026-10-01T13:00:00Z', ende_ts: '2026-10-01T14:00:00Z', status: 'abgeschlossen' })
  const d = { ...leer(), gebinde,
    charge: [{ nr: 1625, schlag: 'Agasul Rüegg', sorte: 'Amoro' }, { nr: 1627, schlag: 'Agasul Rüegg', sorte: 'Fictor' },
             { nr: 1630, schlag: 'Feld Ost', sorte: 'Kaori Kuri' }, { nr: 1631, schlag: 'Feld Ost', sorte: 'Mieluna' }],
    palette: [
      pal(1, 1625, 448), pal(2, 1625, 433), pal(3, 1625, 444), pal(4, 1625, 433), pal(5, 1625, 380), pal(6, 1625, 340),
      pal(10, 1630, 400, '2026-09-01'), pal(11, 1631, 401, '2026-09-01'), pal(12, 1631, 402, '2026-09-01'),
      pal(20, 1631, 500, '2026-08-01'), pal(21, 1631, 501, '2026-08-01'),
      pal(30, 1630, 448), pal(31, 1630, 433),   // 1630 hat selbst Paletten mit 448 und 433 kg
    ],
    auftrag: [arbeit(1602, 1627), arbeit(2, 1630), arbeit(3, 1630), arbeit(4, 1630), arbeit(5, 1627), arbeit(6, 1630), arbeit(7, 1630)],
    auftrag_palette: [
      zettel(1, 1602, 380), zettel(2, 1602, 448), zettel(3, 1602, 433), zettel(4, 1602, 444), zettel(5, 1602, 433),
      // nur 1 von 3 passt woandershin: kein Kandidat
      zettel(10, 2, 401, '2026-09-01'), zettel(11, 2, 777, '2026-09-01'), zettel(12, 2, 778, '2026-09-01'),
      // passt aufs Kilo, aber zwei Monate daneben: kein Kandidat
      zettel(20, 3, 500, '2026-10-01'), zettel(21, 3, 501, '2026-10-01'),
      // die Zettel haben ihre eigene Palette: kein Kandidat
      zettel(30, 4, 400, '2026-09-01'), zettel(31, 4, 400, '2026-09-01'),
      // zweimal 340 kg, aber 1625 hat nur eine Palette mit 340 kg: eine Palette zählt einmal
      zettel(40, 5, 340), zettel(41, 5, 340),
      // 2 von 5 passen zu 1631 — unter 80 %: kein Kandidat
      zettel(50, 6, 401, '2026-09-01'), zettel(51, 6, 402, '2026-09-01'), zettel(52, 6, 777, '2026-09-01'), zettel(53, 6, 778, '2026-09-01'), zettel(54, 6, 779, '2026-09-01'),
      // 448 und 433 kg hat 1630 selbst — dass 1625 sie auch hat, macht die Arbeit nicht fremd
      zettel(60, 7, 448), zettel(61, 7, 433),
    ],
  }
  const erg = durchgang(d, '2026-10-22')
  const f = erg.befunde.filter(b => b.pruefung === 'Arbeit auf fremder Charge')
  assert.equal(f.length, 1)
  assert.match(f[0].wo, /Arbeit 1602/)
  assert.equal(f[0].werte.charge, 1625)
  assert.equal(f[0].werte.passen, 5)
  assert.equal(f[0].werte.ohne_eigene_palette, 5)
  assert.equal(f[0].werte.gleiche_kisten, 0)
  assert.match(f[0].warum, /5 von 5 Zetteln ohne Palette in Charge 1627 \(Agasul Rüegg · Fictor\) passen aufs Kilo zu Paletten von Charge 1625 \(Agasul Rüegg · Amoro\), Eingang 2026-09-23\./)
  assert.doesNotMatch(f[0].warum, /auch in der Kistenzahl/)
})

const chargen = [{ nr: 1613, sorte: 'Tiana' }, { nr: 1632, sorte: 'Tiana' }, { nr: 1651, sorte: 'Kaori Kuri' }]
const arbeit = (id: number, charge: number) => ({ id, weg: 'hand', station: 'waschen_sortieren', charge_nr: charge, start_ts: '2026-09-24T08:00:00Z', ende_ts: '2026-09-24T12:00:00Z', status: 'abgeschlossen' })

test('Teilpalette von Hand umgerechnet: 235 kg für 18 Kisten ist 470 kg × 18/36', () => {
  const d = { ...leer(), gebinde, charge: chargen,
    palette: [{ id: 7384, charge_nr: 1651, eingangsdatum: '2026-09-08', brutto_kg: 470, kisten: 36, gebindeart: 'G2' }],
    auftrag: [arbeit(1569, 1651)],
    auftrag_palette: [{ id: 2950, auftrag_id: 1569, palette_id: null, eingangsdatum: '2026-09-08', brutto_zettel_kg: 235, kisten: 18, gebindeart: 'G2' }],
  }
  const t = durchgang(d, HEUTE).befunde.find(b => b.pruefung === 'Teilpalette von Hand umgerechnet')
  assert.ok(t, 'der Dreisatz wird nicht erkannt')
  assert.equal(t!.werte.palette, 7384)
  assert.equal(t!.werte.dreisatz_kg, 235)
})

test('Teilpalette mit vollem Zettel: 473 kg für 16 von 36 Kisten — mit Wägung „hoch", und die Wägung gilt nicht als Verdunstung', () => {
  const d = { ...leer(), gebinde, charge: chargen,
    palette: [{ id: 7225, charge_nr: 1651, eingangsdatum: '2026-09-03', brutto_kg: 473, kisten: 36, gebindeart: 'G2' }],
    auftrag: [arbeit(1584, 1651)],
    auftrag_palette: [{ id: 3024, auftrag_id: 1584, palette_id: null, eingangsdatum: '2026-09-03', brutto_zettel_kg: 473, kisten: 16, gebindeart: 'G2', wiegung_id: 244 }],
    verdunstung_wiegung: [{ id: 244, auftrag_id: 1584, charge_nr: 1651, palette_id: null, eingangsdatum: '2026-09-03', brutto_damals_kg: 473, brutto_jetzt_kg: 200, kisten: 16, gebindeart: 'G2', wiege_ts: '2026-09-24T13:22:00Z' }],
  }
  const erg = durchgang(d, HEUTE)
  const t = erg.befunde.find(b => b.pruefung === 'Teilpalette mit vollem Zettel')
  assert.ok(t); assert.equal(t!.schwere, 'hoch'); assert.equal(t!.werte.anteilig_kg, 210.2)
  assert.ok(!arten(erg).includes('Verdunstung zu hoch'), 'die Wägung wird doppelt gemeldet')
})

test('Zettel Kistenzahl (36 statt 34), Zettel doppelt (zwei Zettel, eine Palette), Zettel auf fremder Charge derselben Sorte', () => {
  const d = { ...leer(), gebinde, charge: chargen,
    palette: [
      { id: 1, charge_nr: 1651, eingangsdatum: '2026-09-11', brutto_kg: 445, kisten: 34, gebindeart: 'G2' },
      { id: 2, charge_nr: 1651, eingangsdatum: '2026-09-11', brutto_kg: 530, kisten: 40, gebindeart: 'G2' },
      { id: 7659, charge_nr: 1632, eingangsdatum: '2026-09-15', brutto_kg: 468, kisten: 36, gebindeart: 'G2' },
      { id: 9, charge_nr: 1613, eingangsdatum: '2026-08-14', brutto_kg: 543, kisten: 40, gebindeart: 'G2' },
    ],
    auftrag: [arbeit(1569, 1651), arbeit(1589, 1613)],
    auftrag_palette: [
      { id: 2947, auftrag_id: 1569, palette_id: null, eingangsdatum: '2026-09-11', brutto_zettel_kg: 445, kisten: 36, gebindeart: 'G2' },
      { id: 2972, auftrag_id: 1569, palette_id: null, eingangsdatum: '2026-09-11', brutto_zettel_kg: 530, kisten: 40, gebindeart: 'G2' },
      { id: 2973, auftrag_id: 1569, palette_id: null, eingangsdatum: '2026-09-11', brutto_zettel_kg: 530, kisten: 40, gebindeart: 'G2' },
      { id: 3043, auftrag_id: 1589, palette_id: null, eingangsdatum: '2026-09-15', brutto_zettel_kg: 468, kisten: 36, gebindeart: 'G2' },
    ],
  }
  const erg = durchgang(d, HEUTE)
  const a = arten(erg)
  assert.ok(a.includes('Zettel Kistenzahl'))
  assert.equal(erg.befunde.find(b => b.pruefung === 'Zettel doppelt')!.werte.paletten_im_journal, 1)
  const f = erg.befunde.find(b => b.pruefung === 'Zettel auf fremde Charge')
  assert.ok(f, 'die fremde Charge wird nicht gefunden'); assert.equal(f!.schwere, 'hoch'); assert.match(f!.werte.passt_auf, /Palette 7659 \(Charge 1632\)/)
})

test('Lieferung vor Eingang, Sortierlauf ohne Eingang (mit den Chargen derselben Sorte), Lieferung ohne Charge, Arbeit offen', () => {
  const d = { ...leer(), gebinde, charge: [{ nr: 1626, sorte: 'Tiana' }, { nr: 1637, sorte: 'Amoro' }, { nr: 1625, sorte: 'Amoro' }],
    palette: [
      { id: 1, charge_nr: 1626, eingangsdatum: '2026-09-23', brutto_kg: 4000, kisten: 36, gebindeart: 'G2' },
      { id: 2, charge_nr: 1625, eingangsdatum: '2026-07-29', brutto_kg: 400, kisten: 36, gebindeart: 'G2' },
    ],
    lieferung: [
      { id: 1, datum: '2026-09-02', charge_nr: 1626, kg: 1467 }, { id: 2, datum: '2026-09-17', charge_nr: 1626, kg: 539 },
      { id: 3, datum: '2026-09-24', charge_nr: 1626, kg: 100 },
      { id: 4, datum: '2026-09-19', charge_nr: null, kg: 40 }, { id: 5, datum: '2026-09-21', charge_nr: null, kg: 176 },
    ],
    sortier_lauf: [{ id: 173, charge_nr: 1637, auftrag_id: null, datei_zeit: '2026-09-05T04:24:00Z', n_gueltig: 4522, sortiertag: '2026-09-05' }],
    auftrag: [
      { id: 1566, weg: 'hand', station: 'waschen', charge_nr: 1625, start_ts: '2026-09-21T07:40:00Z', status: 'offen' },
      { id: 1591, weg: 'maschine', station: 'waschen', charge_nr: 1625, start_ts: '2026-09-28T05:33:00Z', status: 'offen' },   // heute begonnen: kein Kandidat
    ],
  }
  const erg = durchgang(d, HEUTE)
  const v = erg.befunde.find(b => b.pruefung === 'Lieferung vor Eingang')
  assert.ok(v); assert.equal(v!.werte.lieferungen, 2); assert.equal(v!.werte.kg, 2006); assert.equal(v!.werte.erster_eingang, '2026-09-23')
  const sl = erg.befunde.find(b => b.pruefung === 'Sortierlauf ohne Eingang')
  assert.ok(sl); assert.equal(sl!.werte.chargen_derselben_sorte_mit_eingang, '1625')
  const oc = erg.befunde.find(b => b.pruefung === 'Lieferung ohne Charge')
  assert.ok(oc); assert.equal(oc!.werte.lieferungen, 2); assert.equal(oc!.werte.kg, 216)
  const offen = erg.befunde.filter(b => b.pruefung === 'Arbeit offen')
  assert.equal(offen.length, 1); assert.equal(offen[0].werte.tage_offen, 7)
})

test('Zeitfolge und Datum: gewogen vor dem Eingang, Eingang in der Zukunft, Ende vor Anfang', () => {
  const d = { ...leer(), gebinde,
    palette: [{ id: 1, charge_nr: 1, eingangsdatum: '2027-01-01', brutto_kg: 400, kisten: 36, gebindeart: 'G2' }],
    verdunstung_wiegung: [{ id: 1, charge_nr: 1, palette_id: null, eingangsdatum: '2026-09-20', brutto_damals_kg: 400, brutto_jetzt_kg: 395, kisten: 36, gebindeart: 'G2', wiege_ts: '2026-09-10T09:00:00Z' }],
    auftrag: [{ id: 1, station: 'waschen', charge_nr: 1, start_ts: '2026-09-10T12:00:00Z', ende_ts: '2026-09-10T08:00:00Z', status: 'abgeschlossen' }],
  }
  const a = arten(durchgang(d, HEUTE))
  assert.equal(a.filter(x => x === 'Zeitfolge').length, 2)
  assert.ok(a.includes('Datum'))
})

test('Palox: Zahlendreher 4500 kg und fallender Stand ohne Leeren', () => {
  const d = { ...leer(), gebinde,
    auftrag: [{ id: 1, station: 'waschen_sortieren', charge_nr: 1, start_ts: '2026-09-10T08:00:00Z', ende_ts: '2026-09-10T12:00:00Z', status: 'abgeschlossen' }],
    auftrag_palette: [{ id: 1, auftrag_id: 1, eingangsdatum: '2026-08-01' }],
    schimmel_messung: [
      { id: 1, auftrag_id: 1, kg: 0, palox_stand_kg: 410, ts: '2026-09-10T08:10:00Z' },
      { id: 2, auftrag_id: 1, kg: 4500, palox_stand_kg: 130, ts: '2026-09-10T11:50:00Z' },
    ],
  }
  const a = arten(durchgang(d, HEUTE))
  assert.ok(a.includes('Zahlendreher Palox'))
  assert.ok(a.includes('Palox-Stand fällt'))
})

test('Lieferungen: über dem Eingang, ohne Eingang; Arbeit ohne Eingang', () => {
  const d = { ...leer(), gebinde,
    palette: [{ id: 1, charge_nr: 1625, eingangsdatum: '2026-08-01', brutto_kg: 400, kisten: 36, gebindeart: 'G2' }],  // netto 321
    lieferung: [{ id: 1, datum: '2026-09-01', charge_nr: 1625, kg: 480 }, { id: 2, datum: '2026-09-01', charge_nr: 1626, kg: 100 }],
    auftrag: [{ id: 1, station: 'waschen', charge_nr: 1626, start_ts: '2026-09-10T08:00:00Z', status: 'offen' }],
  }
  const a = arten(durchgang(d, HEUTE))
  assert.ok(a.includes('Lieferung über Eingang'))
  assert.ok(a.includes('Lieferung ohne Eingang'))
  assert.ok(a.includes('Arbeit ohne Eingang'))
})

test('ohne Befund bleibt der Durchgang leer — und fehlende Tabellen werden genannt', () => {
  const erg = durchgang({ gebinde, palette: [{ id: 1, charge_nr: 1, eingangsdatum: '2026-08-01', brutto_kg: 400, kisten: 36, gebindeart: 'G2' }] }, HEUTE)
  assert.equal(erg.befunde.length, 0)
  assert.ok(erg.fehlt.includes('lieferung'))
})
