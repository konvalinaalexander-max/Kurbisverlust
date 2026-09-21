/**
 * Der Verdichter darf die Reihenfolge nicht verdrehen.
 *
 * setup.sql entsteht nicht als Aneinanderreihung der Migrationen: Von jedem
 * Objekt bleibt nur die jüngste Anweisung, und die wandert in einen zweiten
 * Teil, der nach Abhängigkeiten geordnet ist. Bauen zwei Anweisungen
 * dasselbe Objekt — weil die eine die ganze Kaskade neu anlegt und die
 * andere hinterher eine einzelne Ansicht verbessert —, dann entscheidet
 * allein die Reihenfolge, welche Fassung am Ende dasteht.
 *
 * Genau da klaffte eine Lücke. `erg_punkte` wird von zwei angemeldeten
 * Anweisungen gebaut: von der Kaskaden-Schleife (0068) als billige Kopie
 * von mv_schimmel_punkte, und von 0079 noch einmal, damit sie den Messtag
 * trägt. Weil beide denselben Namen bauen, zog der Verdichter zwischen
 * ihnen keine Kante, und die Sortierung nahm, was zuerst fertig war: Die
 * Schleife wartet auf zwei Dutzend Ansichten, 0079 nur auf eine — also lief
 * 0079 zuerst und die Schleife überschrieb es danach. Die Datenbank aus
 * setup.sql hatte `erg_punkte` ohne `messtag`, die aus den Migrationen mit.
 * Der Ursachen-Bildschirm liest diese Spalte.
 *
 * Dieser Test stellt den Fall im Kleinen nach: eine „Schleife", die auf
 * etwas Langsames wartet, und eine spätere Anweisung, die schon bereit
 * wäre. Die spätere muss trotzdem hinten stehen.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { verdichten } from '../supabase/verdichten.mjs'

/** Teil B in der Reihenfolge, in der setup.sql ihn ausgibt. */
const teilB = (v: { bauen: string[]; anhang: string[] }) =>
  [...v.bauen, ...v.anhang].join('\n')

test('von zwei Bauanweisungen für dasselbe Objekt steht die jüngere hinten', () => {
  // Der Kniff, der den Fehler auslöst: Die Schleife wartet auf eine Kette
  // von Ansichten, die im Quelltext erst danach kommen. Die jüngere, für
  // sich genommen sofort baubare Anweisung wird dadurch als erste fertig —
  // und die Schleife überschreibt sie hinterher.
  const liste = [
    // Die Schleife: baut zwei Objekte, eines davon liest das Ende der Kette.
    `-- verdichter: baut erg_beides erg_ziel
     do $$ begin
       execute 'create materialized view erg_beides as select * from v_c';
       execute 'create materialized view erg_ziel as select 1 as alt';
     end $$;`,
    // Später im Quelltext, und auf nichts angewiesen: die bessere Fassung.
    `-- verdichter: baut erg_ziel
     do $$ begin
       execute 'create materialized view erg_ziel as select 1 as alt, 2 as neu';
     end $$;`,
    'create view v_a as select 1 as a;',
    'create view v_b as select * from v_a;',
    'create view v_c as select * from v_b;',
  ]
  const text = teilB(verdichten(liste))
  const alt = text.indexOf("create materialized view erg_ziel as select 1 as alt'")
  const neu = text.indexOf('create materialized view erg_ziel as select 1 as alt, 2 as neu')
  assert.ok(alt >= 0, 'die Schleife steht nicht in setup.sql')
  assert.ok(neu >= 0, 'die jüngere Fassung steht nicht in setup.sql')
  assert.ok(neu > alt,
    'Die jüngere Fassung von erg_ziel steht vor der älteren — die ältere '
    + 'überschreibt sie dann, und die neue Spalte fehlt in der Datenbank.')
})

test('die Reihenfolge nach Abhängigkeit bleibt erhalten', () => {
  // Die Gegenprobe: Die neue Kante darf die eigentliche Ordnung nicht
  // aushebeln. Was eine Ansicht liest, muss weiterhin vor ihr stehen.
  const liste = [
    'create view v_oben as select * from v_unten;',
    'create view v_unten as select 1 as a;',
  ]
  const text = teilB(verdichten(liste))
  assert.ok(text.indexOf('create view v_unten') < text.indexOf('create view v_oben'),
    'v_unten muss vor v_oben stehen — v_oben liest es')
})
