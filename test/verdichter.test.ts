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

test('eine Schleife ist überholt, wenn jeder ihrer Namen später neu gebaut oder endgültig weggeräumt wird (0106)', () => {
  // 0061/0068 bauten erg_modell aus v_schimmel_modell. 0105 baut erg_punkte
  // neu, 0106 räumt das Modell weg und baut den Rest der Schleife neu —
  // keine einzelne spätere Anweisung deckt alle Namen der alten Schleife.
  // Bliebe sie stehen, baute setup.sql erg_modell aus einer Sicht, die es
  // nicht mehr gibt, und bräche ab.
  const liste = [
    'create view v_quelle as select 1 as a;',
    'create view v_modell as select 2 as b;',
    `-- verdichter: baut erg_punkte erg_modell erg_rest
     do $$ begin
       execute 'create materialized view erg_punkte as select * from v_quelle';
       execute 'create materialized view erg_modell as select * from v_modell';
       execute 'create materialized view erg_rest as select * from v_quelle';
     end $$;`,
    `-- verdichter: baut erg_punkte
     do $$ begin
       execute 'create materialized view erg_punkte as select *, 1 as station from v_quelle';
     end $$;`,
    'drop materialized view if exists erg_modell cascade;',
    'drop view if exists v_modell cascade;',
    `-- verdichter: baut erg_rest
     do $$ begin
       execute 'create materialized view erg_rest as select * from v_quelle';
     end $$;`,
  ]
  const text = teilB(verdichten(liste))
  assert.ok(!text.includes('erg_modell as select * from v_modell'),
    'Die alte Schleife steht noch in setup.sql — sie baute erg_modell aus einer Sicht, die es nicht mehr gibt')
  assert.ok(text.includes('1 as station from v_quelle'), 'die jüngere Fassung von erg_punkte fehlt')
  assert.ok(text.includes("erg_rest as select * from v_quelle"), 'erg_rest muss die spätere Anweisung bauen')
  assert.ok(!text.includes('create view v_modell'), 'v_modell ist weggeräumt und darf nicht mehr gebaut werden')
})

test('eine PL/pgSQL-Funktion, die eine Ansicht als Rückgabetyp nennt, wandert mit nach Teil B (0109)', () => {
  // Die Planungsgrenzen aus 0109: v_x liest v_x_zaun(), und die gibt
  // „setof v_x_formel" zurück. Den Rumpf löst Postgres erst beim Aufruf auf,
  // den Kopf aber beim Anlegen — stünde die Funktion in Teil A, gäbe es den
  // Typ v_x_formel dort noch nicht, und setup.sql bräche auf einer frischen
  // Datenbank ab.
  const liste = [
    'create view v_x as select 1 as a;',
    'create function f_liest() returns bigint language plpgsql as $$ begin return (select count(*) from v_x); end $$;',
    'create or replace view v_x_formel with (security_invoker = true) as select 1 as a;',
    `create or replace function v_x_zaun() returns setof v_x_formel
     language plpgsql stable set search_path = public set jit = off as $$
     begin return query select * from v_x_formel; end $$;`,
    'revoke all on function v_x_zaun() from public;',
    'create or replace view v_x with (security_invoker = true) as select * from v_x_zaun();',
    'create view v_oben as select * from v_x;',
  ]
  const v = verdichten(liste)
  const a = v.teilA.join('\n'), b = teilB(v)
  const formel = b.indexOf('create or replace view v_x_formel')
  const zaun = b.indexOf('create or replace function v_x_zaun')
  const sicht = b.indexOf('create or replace view v_x with')
  const oben = b.indexOf('create view v_oben')
  assert.ok(!a.includes('function v_x_zaun'), 'v_x_zaun() steht in Teil A — dort gibt es v_x_formel noch nicht')
  assert.ok(formel >= 0 && zaun > formel, 'die Grenze muss hinter ihrer Formel stehen')
  assert.ok(sicht > zaun, 'die Sicht muss hinter der Grenze stehen, die sie liest')
  assert.ok(oben > sicht, 'was die Sicht liest, steht dahinter')
  // Die Gegenprobe: Wer eine Ansicht nur im Rumpf liest, bleibt, wo er ist.
  assert.ok(a.includes('function f_liest'), 'f_liest() liest v_x nur im Rumpf und gehört nach Teil A')
})
