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
