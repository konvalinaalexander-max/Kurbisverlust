/**
 * Der Kalendertag des Betrachters, nicht der Kalendertag von UTC.
 *
 * Diese Datei prüft eine einzige Sache, aber die kostet Kilogramm: Das
 * Programm bildete „heute" an fünf Stellen mit
 * `new Date().toISOString().slice(0, 10)`. Das ist der Tag **in UTC**. Die
 * Schweiz liegt eine Stunde davor, im Sommer zwei — zwischen Mitternacht und
 * zwei Uhr Ortszeit ist der UTC-Tag also noch der gestrige, und die Maske
 * bietet dem Arbeiter **gestern** als Vorgabe an.
 *
 * Aus dem Tag wird eine Lagerdauer, aus der Lagerdauer eine Verdunstungsrate.
 * Gemessen in Runde M: ein Tag Verschiebung bewegt den Saisonverlust um
 * 19.68 kg; bei der kürzesten Lagerung der Demosaison (acht Tage) verschiebt
 * er die Rate dieser Wägung um 14.4 %.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { tagVon } from '../src/lib/format.ts'

const ZONE = process.env.TZ

test('nimmt den Kalendertag des Betrachters, nicht den von UTC', () => {
  // Ohne feste Zone lässt sich der Fall nicht stellen; dann prüft dieser Test
  // nur, dass er überhaupt gelaufen ist. `npm test` setzt TZ nicht, deshalb
  // steht der scharfe Teil unter der Bedingung — und meldet sich, wenn er
  // ausfällt, statt stillschweigend durchzugehen.
  if (ZONE !== 'Europe/Zurich') {
    assert.ok(true, 'ohne TZ=Europe/Zurich nur Formprüfung')
    assert.match(tagVon(new Date(2026, 6, 16, 1, 30)), /^2026-07-16$/)
    return
  }

  // 16. Juli 2026, 01:30 in Zürich (Sommerzeit, UTC+2) ist in UTC noch der
  // 15. Juli, 23:30. Der Arbeiter steht am 16. in der Halle.
  const nachts = new Date(2026, 6, 16, 1, 30)
  assert.equal(tagVon(nachts), '2026-07-16', 'der Tag des Arbeiters')
  assert.equal(nachts.toISOString().slice(0, 10), '2026-07-15',
    'genau das rechnete das Programm vorher — der Tag in UTC, einen zurück')
})

test('führende Nullen bei Monat und Tag', () => {
  assert.equal(tagVon(new Date(2026, 0, 5, 12, 0)), '2026-01-05')
  assert.equal(tagVon(new Date(2026, 10, 30, 12, 0)), '2026-11-30')
})

test('kein toISOString in den Masken — das wäre wieder der UTC-Tag', async () => {
  const { readdirSync, readFileSync, statSync } = await import('node:fs')
  const { join } = await import('node:path')

  const dateien: string[] = []
  const sammeln = (v: string) => {
    for (const e of readdirSync(v)) {
      const p = join(v, e)
      if (statSync(p).isDirectory()) sammeln(p)
      else if (/\.tsx?$/.test(p)) dateien.push(p)
    }
  }
  sammeln('src')

  // Kommentare zuerst weg: `lib/format.ts` erklärt den Fehler in Worten und
  // enthält das Muster deshalb wörtlich. Ein Test, der die Erklärung des
  // Fehlers für den Fehler hält, ist unbrauchbar — und genau das tat die erste
  // Fassung dieses Tests.
  const ohneKommentare = (t: string) =>
    t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')

  const muster = /new Date\([^)]*\)\s*\.toISOString\(\)\s*\.slice\(\s*0\s*,\s*10\s*\)/
  const fundstellen = dateien.filter(d => muster.test(ohneKommentare(readFileSync(d, 'utf8'))))
  assert.deepEqual(fundstellen, [],
    'Diese Dateien bilden „heute" wieder in UTC. Stattdessen `heute()` aus lib/format.')
})
