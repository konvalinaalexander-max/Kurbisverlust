import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { SCHEMA_ERWARTET, datenbankVeraltet } from '../src/lib/version.ts'

const MIGRATIONEN = join(import.meta.dirname, '..', 'supabase', 'migrations')

test('SCHEMA_ERWARTET ist die Nummer der jüngsten Migration', () => {
  const dateien = readdirSync(MIGRATIONEN).filter(f => /^\d{4}_.*\.sql$/.test(f)).sort()
  const hoechste = Number(dateien[dateien.length - 1].slice(0, 4))
  assert.equal(SCHEMA_ERWARTET, hoechste,
    `src/lib/version.ts erwartet ${SCHEMA_ERWARTET}, die höchste Migration ist ${hoechste} — nachziehen`)
})

test('schema_stand() in der jüngsten Migration nennt dieselbe Nummer', () => {
  const dateien = readdirSync(MIGRATIONEN).filter(f => /^\d{4}_.*\.sql$/.test(f)).sort()
  // Die jüngste Migration, die schema_stand() setzt, muss die jüngste überhaupt sein.
  const mitStand = dateien.filter(f => /create or replace function schema_stand\(\)/.test(readFileSync(join(MIGRATIONEN, f), 'utf8')))
  assert.ok(mitStand.length > 0, 'keine Migration setzt schema_stand()')
  const letzte = mitStand[mitStand.length - 1]
  assert.equal(letzte, dateien[dateien.length - 1],
    `die jüngste Migration ${dateien[dateien.length - 1]} setzt schema_stand() nicht (zuletzt in ${letzte})`)
  const quelle = readFileSync(join(MIGRATIONEN, letzte), 'utf8')
  const genannt = Number(quelle.match(/schema_stand\(\) returns int[\s\S]*?as \$\$ select (\d+) \$\$/)?.[1])
  assert.equal(genannt, SCHEMA_ERWARTET, `schema_stand() liefert ${genannt}, die App erwartet ${SCHEMA_ERWARTET}`)
})

test('die Meldung nennt beide Stände und den Weg heraus', () => {
  const m = datenbankVeraltet(53)
  assert.match(m, /0053/); assert.match(m, /0057|00\d\d/); assert.match(m, /setup\.sql/)
  assert.match(datenbankVeraltet(null), /älter als Migration 0057/)
})
