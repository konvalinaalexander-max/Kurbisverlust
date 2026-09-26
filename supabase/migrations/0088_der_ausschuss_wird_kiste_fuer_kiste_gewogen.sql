-- =====================================================================
-- 0088 — Der Ausschuss wird Kiste für Kiste gewogen
--
-- Der Betrieb: „sie werden wahrscheinlich in G2-Kisten sein … die Kisten
-- werden nacheinander auf eine Waage gestellt … sie werden nie auf
-- Paletten stehen, sondern halt nur einzelne Kisten".
--
-- Damit ist die Frage aus 0083 („steht eine Palette drunter?") für den
-- Ausschuss beantwortet — ein für alle Mal mit Nein. Die Spalte bleibt
-- (alte Zeilen tragen sie, und der Betriebsleiter kann sie in der
-- Korrektur setzen), aber ihr Standard wird Nein: Wer eine Zeile ohne
-- Angabe schreibt, meint einzelne Kisten.
--
-- Die Maske lässt die Kisten nacheinander eintippen und schreibt EINE
-- Zeile je Art: Kistenzahl, die Summe der Bruttos, und in der Bemerkung
-- die einzelnen Gewichte. Warum eine Zeile und nicht eine je Kiste: kg ist
-- ganzzahlig, und der Auslöser rundet je Zeile. Drei Kisten zu 10.5 kg
-- netto wären als drei Zeilen 33 kg, als eine Zeile 32 — die Summe wird
-- einmal gerundet, nicht dreimal.
-- =====================================================================

alter table ausschuss_messung alter column mit_palette set default false;
comment on column ausschuss_messung.mit_palette is
  'Stand der Ausschuss beim Wiegen auf einer Palette? Seit 0088 ist die Antwort '
  'im Betrieb immer Nein — Ausschuss wird Kiste für Kiste gewogen; der Standard '
  'ist darum false. Alte Zeilen (vor 0083 immer mit Palette gerechnet) tragen '
  'noch true, wo es nicht eindeutig zu deuten war.';
comment on column ausschuss_messung.bemerkung is
  'Freier Text. Seit 0088 stehen hier bei einer Wägung Kiste für Kiste die '
  'einzelnen Bruttogewichte („3 Kisten einzeln gewogen: 12 · 13.5 · 11 kg") — '
  'die Zeile selbst trägt die Summe.';

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 88 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
