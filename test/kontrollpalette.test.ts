import { test } from 'node:test'
import assert from 'node:assert/strict'
import { ABSTAND_VORGABE, SCHOCKFENSTER_TAGE, faelligkeit, tageZwischen } from '../src/lib/kontrollpalette.ts'

const tag = (iso: string) => new Date(`${iso}T12:00:00`)

test('tageZwischen zählt Kalendertage, nicht Stunden', () => {
  assert.equal(tageZwischen('2026-10-01T23:30:00', '2026-10-02T00:30:00'), 1)
  assert.equal(tageZwischen('2026-10-01T00:30:00', '2026-10-01T23:30:00'), 0)
  assert.equal(tageZwischen('2026-10-01', '2026-11-01'), 31)
})

test('in den ersten vier Wochen gilt der enge Abstand', () => {
  // Der Betrieb vermutet am Anfang einen Schock beim Einlagern. Wäre der
  // Abstand überall gleich, liesse er sich nicht von einer konstanten Rate
  // trennen.
  const f = faelligkeit('2026-10-01', null, ABSTAND_VORGABE, tag('2026-10-20'))
  assert.equal(f.sollAbstand, 14)
  assert.equal(f.nieGewogen, true)
  assert.equal(f.ueberfaellig, true, '19 Tage ohne Wägung sind bei Abstand 14 überfällig')
})

test('nach vier Wochen wird seltener gewogen', () => {
  const f = faelligkeit('2026-10-01', '2026-11-10', ABSTAND_VORGABE, tag('2026-11-25'))
  assert.equal(f.sollAbstand, 30)
  assert.equal(f.tageSeit, 15)
  assert.equal(f.ueberfaellig, false, '15 Tage sind bei Abstand 30 noch nicht fällig')
})

test('der Umschaltpunkt liegt bei vier Wochen, nicht davor', () => {
  const knapp = faelligkeit('2026-10-01', null, ABSTAND_VORGABE,
    tag(`2026-10-${String(1 + SCHOCKFENSTER_TAGE - 1).padStart(2, '0')}`))
  assert.equal(knapp.sollAbstand, 14)
  const drueber = faelligkeit('2026-10-01', null, ABSTAND_VORGABE, tag('2026-10-29'))
  assert.equal(drueber.sollAbstand, 30)
})

test('nie gewogen heisst: die Uhr läuft ab dem Anlegen', () => {
  const f = faelligkeit('2026-10-01', null, ABSTAND_VORGABE, tag('2026-10-08'))
  assert.equal(f.tageSeit, 7)
  assert.equal(f.ueberfaellig, false)
})

test('eigene Abstände aus den Einstellungen schlagen die Vorgabe', () => {
  const f = faelligkeit('2026-10-01', '2026-10-05', { anfang: 7, spaeter: 21 }, tag('2026-10-13'))
  assert.equal(f.sollAbstand, 7)
  assert.equal(f.ueberfaellig, true)
})
