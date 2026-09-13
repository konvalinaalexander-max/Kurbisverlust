/**
 * Die Tätigkeiten und der Vorschlag „Tage seit dem Waschen" (Runde P).
 *
 * Der Vorschlag ist die einzige Stelle im Programm, an der die App eine Zahl
 * in ein Beobachtungsfeld schreibt, die niemand gemessen hat. Sie darf das,
 * weil sie sie aus einer anderen Beobachtung ableitet (dem Ende der
 * Wasch-Arbeit) und weil der Vorarbeiter sie überschreiben kann — aber genau
 * darum gehören die Grenzen in einen Test und nicht in eine Komponente.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { TAETIGKEITEN, taetigkeitVon, vorschlagTageSeitWaschen, VORSCHLAG_HOECHSTENS_TAGE }
  from '../src/lib/taetigkeit.ts'

test('Fax und Waschen teilen Weg und Station — die Markierung entscheidet', () => {
  assert.equal(taetigkeitVon('maschine', 'waschen', true)?.id, 'fax')
  assert.equal(taetigkeitVon('maschine', 'waschen', false)?.id, 'waschen')
  assert.equal(TAETIGKEITEN.filter(a => a.fax).length, 1)
})

test('Vorschlag: der übliche Fall — gewaschen vorgestern, heute abgepackt', () => {
  const heute = new Date('2026-11-05T09:00:00')
  assert.equal(vorschlagTageSeitWaschen('2026-11-03T16:30:00', heute), 2)
  assert.equal(vorschlagTageSeitWaschen('2026-11-04T16:30:00', heute), 1)
  // Am selben Tag gewaschen und abgepackt: null Tage ist eine Antwort, nicht „nichts".
  assert.equal(vorschlagTageSeitWaschen('2026-11-05T07:00:00', heute), 0)
})

test('Vorschlag: Kalendertage, nicht Stunden', () => {
  // 23:00 gewaschen, am nächsten Morgen um 07:00 abgepackt — acht Stunden,
  // aber ein Tag. Der Betrieb zählt in Tagen, und die Auswertung auch.
  const heute = new Date('2026-11-05T07:00:00')
  assert.equal(vorschlagTageSeitWaschen('2026-11-04T23:00:00', heute), 1)
})

test('Vorschlag: nichts ohne Wasch-Arbeit', () => {
  const heute = new Date('2026-11-05T09:00:00')
  assert.equal(vorschlagTageSeitWaschen(null, heute), null)
  assert.equal(vorschlagTageSeitWaschen(undefined, heute), null)
  assert.equal(vorschlagTageSeitWaschen('', heute), null)
  assert.equal(vorschlagTageSeitWaschen('kein Datum', heute), null)
})

test('Vorschlag: nichts aus der Zukunft', () => {
  // Ein Tippfehler im Datum soll sich nicht als negative Wartezeit
  // fortpflanzen (0070: die Zeit läuft vorwärts).
  const heute = new Date('2026-11-05T09:00:00')
  assert.equal(vorschlagTageSeitWaschen('2026-11-06T08:00:00', heute), null)
  assert.equal(vorschlagTageSeitWaschen('2029-11-04T08:00:00', heute), null)
})

test('Vorschlag: nichts, was zu lange her ist — leer schlägt falsch', () => {
  const heute = new Date('2026-11-05T09:00:00')
  assert.equal(VORSCHLAG_HOECHSTENS_TAGE, 14)
  // Genau an der Grenze wird noch vorgeschlagen …
  assert.equal(vorschlagTageSeitWaschen('2026-10-22T08:00:00', heute), 14)
  // … einen Tag darüber nicht mehr: Diese Wasch-Arbeit ist mit grosser
  // Wahrscheinlichkeit nicht die, aus der die Paletten auf dem Tisch kommen.
  assert.equal(vorschlagTageSeitWaschen('2026-10-21T08:00:00', heute), null)
  // Und schon gar nicht die Wäsche vom Frühjahr.
  assert.equal(vorschlagTageSeitWaschen('2026-04-23T08:00:00', heute), null)
})
