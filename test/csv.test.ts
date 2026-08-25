import { test } from 'node:test'
import assert from 'node:assert/strict'
import { csvReinigen, reinigen, werteLesen, trichter, masseKg, REINIGUNG_STANDARD } from '../src/lib/csv.ts'
import { dateinamenLesen, jahrFuerMonat } from '../src/lib/dateiname.ts'

const CHARGEN = [1598, 1613, 1614, 1651]

test('liest eine Zahl je Zeile, ignoriert Leerzeilen', () => {
  const { werte, unlesbar } = werteLesen('600\n800\n\n1000\r\n')
  assert.deepEqual(werte, [600, 800, 1000])
  assert.equal(unlesbar, 0)
})

test('zählt unlesbare Zeilen, statt sie stillschweigend zu verlieren', () => {
  const { werte, unlesbar } = werteLesen('600\nGewicht\n800')
  assert.deepEqual(werte, [600, 800])
  assert.equal(unlesbar, 1)
})

test('verwirft Overflow-Werte ab 60000 (16-Bit-Unterlauf)', () => {
  const e = reinigen([600, 65534, 65400, 800])
  assert.equal(e.n_overflow, 2)
  assert.equal(e.n_gueltig, 2)
})

test('verwirft Werte unter 100 g', () => {
  const e = reinigen([600, 98, 2, 800])
  assert.equal(e.n_klein, 2)
  assert.equal(e.n_gueltig, 2)
})

test('fasst direkte Dubletten zusammen, auch Dreier', () => {
  const e = reinigen([600, 600, 800, 900, 900, 900])
  assert.equal(e.n_dubletten, 3)
  assert.deepEqual(e.histogramm, [[600, 1], [800, 1], [900, 1]])
})

test('gleiche Werte an nicht benachbarten Stellen bleiben erhalten', () => {
  // Zwei verschiedene Kürbisse dürfen zufällig gleich schwer sein — nur der
  // Doppel-Trigger der Maschine liefert sie direkt hintereinander.
  const e = reinigen([600, 800, 600])
  assert.equal(e.n_dubletten, 0)
  assert.deepEqual(e.histogramm, [[600, 2], [800, 1]])
})

test('Dubletten-Regel lässt sich abschalten', () => {
  const e = reinigen([600, 600], { ...REINIGUNG_STANDARD, dubletten_zusammenfassen: false })
  assert.equal(e.n_dubletten, 0)
  assert.deepEqual(e.histogramm, [[600, 2]])
})

test('der Trichter geht immer auf', () => {
  const e = csvReinigen(['600', '600', '65534', '50', '900', '900', '900', '1200'].join('\n'))
  assert.equal(e.n_roh - e.n_overflow - e.n_klein - e.n_dubletten, e.n_gueltig)
  assert.match(trichter(e), /8 gelesen.*3 Kürbisse/)
})

test('das Histogramm verliert keine Masse', () => {
  const e = reinigen([600, 800, 1200])
  assert.equal(masseKg(e.histogramm), 2.6)
})

test('erkennt den Standard-Dateinamen', () => {
  const r = dateinamenLesen('1614-25-08-11-10.csv', CHARGEN, 2026)
  assert.equal(r.chargeNr, 1614)
  assert.equal(r.quelle, 'dateiname')
  assert.equal(r.zeit?.getFullYear(), 2026)
  assert.equal(r.zeit?.getMonth(), 7)
  assert.equal(r.zeit?.getDate(), 25)
  assert.equal(r.zeit?.getHours(), 11)
})

test('toleriert andere Trenner und Pfade', () => {
  for (const name of ['1614_25_08_11_10', '1614 25.08 11.10', 'C:\\daten\\1614/25/08/11/10.CSV']) {
    const r = dateinamenLesen(name, CHARGEN, 2026)
    assert.equal(r.chargeNr, 1614, name)
    assert.equal(r.zeit?.getDate(), 25, name)
  }
})

test('nimmt nur Nummern, die es wirklich gibt', () => {
  const r = dateinamenLesen('9999-25-08-11-10', CHARGEN, 2026)
  assert.equal(r.chargeNr, null)
  assert.match(r.hinweis!, /Keine bekannte Chargennummer/)
})

test('fällt auf den Zeitstempel der Datei zurück', () => {
  const r = dateinamenLesen('1614.csv', CHARGEN, 2026, Date.UTC(2026, 7, 25, 9, 0))
  assert.equal(r.chargeNr, 1614)
  assert.equal(r.quelle, 'lastModified')
})

test('ein Januar-Lauf gehört zur Saison des Vorjahres', () => {
  assert.equal(jahrFuerMonat(8, 2026), 2026)
  assert.equal(jahrFuerMonat(1, 2026), 2027)
  const r = dateinamenLesen('1613-15-01-08-30', CHARGEN, 2026)
  assert.equal(r.zeit?.getFullYear(), 2027)
})
