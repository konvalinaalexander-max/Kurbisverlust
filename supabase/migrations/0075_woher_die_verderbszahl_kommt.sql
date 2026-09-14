-- =====================================================================
-- 0075 — Woher die Verderbszahl kommt
--
-- Bei der Verdunstung sieht man einer Zahl an, worauf sie beruht: genug
-- eigene Wägungen, zum Mittel gezogen, oder geliehenes Mittel. Beim
-- Verderb nicht — dort rechnet die App mit EINER Kurve F(t) für alles:
-- eine Sorte, alle Chargen, die ganze Saison. Das steht nirgends.
--
-- Diese Migration macht das sichtbar, und zwar ehrlich: sie sagt je
-- Sorte, auf wie vielen eigenen Messpunkten aus wie vielen Chargen die
-- gemeinsame Kurve dort ruht.
--
-- WAS SIE AUSDRÜCKLICH NICHT TUT
--
-- Sie baut die Schrumpfung nicht. Der Auftrag sah vor, den Verderb wie
-- die Verdunstung je Sorte zu schrumpfen und mit ● ◐ ○ zu kennzeichnen.
-- Das ist der einzige offene Punkt, der die Kaskade bewegt — alles
-- andere dieser Runde sind Masken. Beides in einem Lauf hiesse: Zahlen
-- und Bildschirme ändern sich gleichzeitig, und wenn danach etwas falsch
-- aussieht, kann niemand sagen, welches von beidem es war. Die
-- Schrumpfung bekommt eine eigene Runde, und als ersten Akt die Prüfung,
-- dass sie bei null eigenen Messpunkten auf den Rappen dieselben Zahlen
-- liefert wie heute.
--
-- Solange sie fehlt, erscheint je Sorte NUR das Zeichen ○ — „es gilt die
-- gemeinsame Kurve". Ein ◐ auf einer Sorte, deren Zahl in Wirklichkeit zu
-- hundert Prozent das Gesamtmittel ist, wäre ein Zeichen, das lügt. Das
-- wäre schlimmer als gar keins.
--
-- Der Nebeneffekt ist der eigentliche Gewinn: der Betriebsleiter sieht,
-- welche Sorte wie weit von einer eigenen Kurve entfernt ist — und das
-- ist genau die Auskunft, die er braucht, um zu entscheiden, wo die fünf
-- Kontrollpaletten hingehören.
-- =====================================================================
set client_min_messages = warning;

create or replace view v_verderb_lage with (security_invoker = true) as
select p.sorte,
       count(*) filter (where p.plausibel)::int                      as n_punkte,
       count(distinct p.charge_nr) filter (where p.plausibel)::int    as n_chargen,
       zahl(min(p.lagertage) filter (where p.plausibel), 0, 100000)::int as jung_tage,
       zahl(max(p.lagertage) filter (where p.plausibel), 0, 100000)::int as alt_tage,
       -- Solange es keine Schrumpfung gibt, ruht jede Sorte auf der
       -- gemeinsamen Kurve. Die Spalte heisst schon so, wie sie später
       -- heissen wird — nur ihr Wert ist heute immer derselbe.
       'mittel'::text                                                as quelle
  from v_schimmel_punkte p
 group by p.sorte;

comment on view v_verderb_lage is
  'Je Sorte: auf wie vielen eigenen Verderbs-Messpunkten aus wie vielen Chargen '
  'die gemeinsame Kurve dort ruht, und über welche Spanne an Lagertagen sie '
  'reichen. quelle ist heute immer „mittel" — es gibt nur eine Kurve für alles. '
  'Die Spalte trägt den Namen schon, damit die Schrumpfung später nur ihren Wert '
  'ändert und keine Sicht (0075).';
grant select on v_verderb_lage to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 75 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
