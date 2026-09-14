-- =====================================================================
-- 0077 — Die Kontrollpalette kennt ihren Eingang
--
-- Die Kontrollpalette (0072) ist eine markierte Palette, die stehen bleibt
-- und immer wieder gewogen wird. Ihre erste Wägung war bisher ihr erster
-- Messpunkt. Dabei steht auf dem Zettel an der Palette schon ein früherer:
-- das Eingangsdatum und das Bruttogewicht beim Wareneingang. Wer die
-- Palette anlegt, hat den Zettel vor Augen — zwei Angaben, die nichts
-- kosten und den Weg vom Eingang bis zur ersten Wägung mitzählen lassen.
--
-- Beide sind freiwillig: Ein Zettel kann fehlen oder unlesbar sein, und
-- „leer ist nicht null" — dann beginnt die Kurve eben bei der ersten
-- Wägung. Die Auswertung (v_kontrollpalette_rate) nimmt den Eingang als
-- Punkt dazu, sobald sie ihn kennt; das ist Sache des Rechenwerks, nicht
-- dieser Migration.
--
-- Nur Spalten dazu, nichts weg, nichts umgedeutet — die Erfassung ist
-- scharf, und das hier ist die einzige Art Änderung, die dann noch erlaubt
-- ist (docs/DATENERHEBUNG.md, Abschnitt 4).
-- =====================================================================

alter table kontrollpalette
  add column if not exists eingangsdatum     date,
  add column if not exists brutto_eingang_kg numeric(8,2)
    check (brutto_eingang_kg is null or brutto_eingang_kg > 0);

comment on column kontrollpalette.eingangsdatum is
  'Das Eingangsdatum vom Zettel an der Palette — freiwillig beim Anlegen (0077).';
comment on column kontrollpalette.brutto_eingang_kg is
  'Das Bruttogewicht beim Wareneingang vom Zettel, mit denselben Kisten wie '
  'die Wägungen — freiwillig; fehlt es, beginnt die Kurve bei der ersten Wägung (0077).';

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 77 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
