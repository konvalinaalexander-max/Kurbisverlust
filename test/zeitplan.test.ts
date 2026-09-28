import { test } from 'node:test'
import assert from 'node:assert/strict'
import { istAktuell, rechnetGerade, taktMinuten, zeitplanZustand, RECHNEN_HOECHSTENS_MIN, TAKTE_OHNE_LAUF } from '../src/lib/zeitplan.ts'

const JETZT = new Date('2026-09-28T09:02:00Z')
const vor = (min: number) => new Date(JETZT.getTime() - min * 60000).toISOString()
const eingetragen = { aktiv: true, takt: '*/10 * * * *', letzterStart: null as string | null, letzterStatus: null as string | null }

test('der Takt „alle N Minuten" wird gelesen, alles andere nicht', () => {
  assert.equal(taktMinuten('*/10 * * * *'), 10)
  assert.equal(taktMinuten('*/5 * * * *'), 5)
  assert.equal(taktMinuten('0 * * * *'), null)
  assert.equal(taktMinuten(null), null)
})

test('kein Zeitplan eingetragen: fehlt', () => {
  assert.equal(zeitplanZustand({ ...eingetragen, aktiv: false }, JETZT), 'fehlt')
})

test('eingetragen, aber noch nie gelaufen: rechnet nicht — der Fall vom 28. September', () => {
  // Eingespielt 08:09 UTC, um 09:02 kein einziger Lauf verzeichnet. Die App
  // sagte „neu bis …" und wartete auf etwas, das nicht kam.
  assert.equal(zeitplanZustand(eingetragen, JETZT), 'rechnet_nicht')
})

test('vor fünf Minuten gelaufen: läuft', () => {
  assert.equal(zeitplanZustand({ ...eingetragen, letzterStart: vor(5), letzterStatus: 'succeeded' }, JETZT), 'laeuft')
})

test('gerade am Rechnen (Status running): läuft', () => {
  assert.equal(zeitplanZustand({ ...eingetragen, letzterStart: vor(1), letzterStatus: 'running' }, JETZT), 'laeuft')
})

test('drei Takte ohne Lauf sind noch geduldet, danach rechnet er nicht', () => {
  assert.equal(zeitplanZustand({ ...eingetragen, letzterStart: vor(TAKTE_OHNE_LAUF * 10), letzterStatus: 'succeeded' }, JETZT), 'laeuft')
  assert.equal(zeitplanZustand({ ...eingetragen, letzterStart: vor(TAKTE_OHNE_LAUF * 10 + 1), letzterStatus: 'succeeded' }, JETZT), 'rechnet_nicht')
})

test('der letzte Lauf ist fehlgeschlagen: rechnet nicht, auch wenn er frisch ist', () => {
  assert.equal(zeitplanZustand({ ...eingetragen, letzterStart: vor(2), letzterStatus: 'failed' }, JETZT), 'rechnet_nicht')
})

test('ein unbekannter Takt gilt als stündlich', () => {
  const stuendlich = { ...eingetragen, takt: '17 * * * *', letzterStatus: 'succeeded' }
  assert.equal(zeitplanZustand({ ...stuendlich, letzterStart: vor(150) }, JETZT), 'laeuft')
  assert.equal(zeitplanZustand({ ...stuendlich, letzterStart: vor(181) }, JETZT), 'rechnet_nicht')
})

test('ein unlesbarer Zeitpunkt ist kein Lauf', () => {
  assert.equal(zeitplanZustand({ ...eingetragen, letzterStart: 'gestern', letzterStatus: 'succeeded' }, JETZT), 'rechnet_nicht')
})

test('aktuell heisst: seit der letzten Rechnung nichts Neues erfasst — auch wenn sie eine Stunde her ist', () => {
  // Der Fall vom 28. September: gerechnet 10:09, zuletzt erfasst 10:07, Chip „Stand vor 1 h".
  assert.equal(istAktuell('2026-09-28T08:09:20Z', '2026-09-28T08:07:44Z'), true)
  assert.equal(istAktuell('2026-09-28T08:09:20Z', '2026-09-28T09:30:00Z'), false)
  assert.equal(istAktuell('2026-09-28T08:09:20Z', '2026-09-28T08:09:20Z'), true)
  assert.equal(istAktuell(null, '2026-09-28T08:07:44Z'), false, 'nie gerechnet ist nie aktuell')
  assert.equal(istAktuell('2026-09-28T08:09:20Z', null), true)
  assert.equal(istAktuell('Unsinn', '2026-09-28T08:07:44Z'), false)
})

test('ein abgebrochener Lauf hinterlässt rechnet_seit — älter als die Zeitgrenze ist es kein Rechnen', () => {
  assert.equal(rechnetGerade(vor(2), JETZT), true)
  assert.equal(rechnetGerade(vor(RECHNEN_HOECHSTENS_MIN), JETZT), true)
  assert.equal(rechnetGerade(vor(RECHNEN_HOECHSTENS_MIN + 1), JETZT), false)
  assert.equal(rechnetGerade(null, JETZT), false)
  assert.equal(rechnetGerade('gestern', JETZT), false)
})
