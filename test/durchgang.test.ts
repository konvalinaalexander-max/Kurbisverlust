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

test('Eingang: Gewicht je Kiste und Kistenzahl ausser Rahmen; doppelte Palette', () => {
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
  assert.equal(a.filter(x => x === 'Doppelte Palette').length, 1)
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
