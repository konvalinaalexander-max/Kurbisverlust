-- =====================================================================
-- 0076 — Was die App von der Eingangspalette weiss
--
-- Seit Runde Q trägt die Wäge-Maske Kistenzahl und Gebindeart auf die
-- Eingangspalette (`auftrag_palette.kisten`, `.gebindeart`). Daran hängt
-- der ganze Rechenweg, den der Betrieb selbst gefunden hat:
--
--   „du siehst ja dann anzahl paletten - mit anzahl kisten und total vom
--    brutto gewicht - dann weisst du wieviel sortiert worden ist"
--
-- Ohne die Kistenzahl gibt es kein Netto (die Tara hängt am Gebinde) und
-- damit keine Masse für diese Palette — „leer ist nicht null", die Masse
-- fehlt einfach. Das ist richtig so, aber es muss sichtbar sein: sonst
-- sinkt die erfasste Menge, und niemand weiss warum.
--
-- Diese Migration zählt beides und nichts sonst. Sie ändert keine Zahl der
-- Auswertung — sie sagt nur, worauf sie ruht.
--
-- Dazu ein dritter Zähler: wie oft das Alter der Ware vom Zettel
-- ABGELESEN ist und nicht geschätzt. Eine geschätzte Zahl darf auf dem
-- Bildschirm nicht aussehen wie eine gemessene (AB-50) — und wie oft
-- welches zutrifft, soll man nachsehen können.
--
-- Der Rumpf von v_datenqualitaet steht hier vollständig, weil `create or
-- replace view` genau das verlangt; neu sind allein die drei letzten
-- Spalten. Angehängt, nicht eingeschoben: `create or replace` darf
-- Spalten nur am Ende ergänzen.
-- =====================================================================

create or replace view v_datenqualitaet with (security_invoker = true) as
with arbeiten as (select a.* from auftrag a where a.abgebrochen_ts is null),
     fertig as (select * from arbeiten where status = 'abgeschlossen')
select
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id)::int as paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where ap.eingangsdatum is not null)::int                                             as paletten_mit_datum,
  (select count(*) from fertig where not ist_fax)::int                                    as arbeiten_fertig,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null))::int                     as arbeiten_mit_ablesung,
  (select count(*) from fertig f where not f.ist_fax and (select count(*) from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null) >= 2)::int                as arbeiten_mit_zwei_ablesungen,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from auftrag_angabe g
    where g.auftrag_id = f.id and g.schluessel = 'eine_charge'))::int                     as arbeiten_mit_antwort,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen)::int                                                                as ausschuss_messungen,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen and m.brutto_kg is not null)::int                                    as ausschuss_gewogen,
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.gemessen)::int                                       as lagerkontrollen,
  (select count(*) from sortier_lauf)::int                                                as sortierlaeufe,
  (select count(*) from sortier_lauf where auftrag_id is not null)::int                   as sortierlaeufe_zugeordnet,
  (select count(*) from fertig f where f.station = 'sortieren')::int                      as sortier_arbeiten,
  (select count(*) from fertig f where f.station = 'sortieren' and exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int              as sortier_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax)::int      as wasch_arbeiten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax
    and (f.kaliber_idx is not null or f.kaliber_von_g is not null)
    and (exists (select 1 from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)
         or exists (select 1 from auftrag_palette p where p.auftrag_id = f.id and p.kisten > 0)))::int
                                                                                          as wasch_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax)::int                                    as fax_arbeiten,
  (select count(*) from fertig f where f.ist_fax and (f.paletten_gesamt > 0 or exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)))::int             as fax_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax and exists (select 1
    from schimmel_messung s where s.auftrag_id = f.id and s.gemessen))::int               as fax_arbeiten_mit_faulem,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren')::int                                           as ws_paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren' and ap.brutto_zettel_kg is not null)::int       as ws_paletten_mit_zettelgewicht,
  (select count(*) from fertig f where f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))::int
                                                                                          as arbeiten_nach_waschen,
  (select count(*) from fertig f where (f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))
    and f.kistensystem is not null)::int                                                  as arbeiten_mit_kistensystem,
  ((select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
     where a.station = 'waschen' and not a.ist_fax)
   + (select coalesce(sum(p.kisten), 0) from auftrag_palette p join arbeiten a on a.id = p.auftrag_id
       where a.station = 'waschen' and not a.ist_fax))::int                               as wasch_kisten_gezaehlt,
  ((select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
     where a.station = 'waschen' and not a.ist_fax and (g.sortierdatum is not null or g.datum_fehlt))
   + (select coalesce(sum(p.kisten), 0) from auftrag_palette p join arbeiten a on a.id = p.auftrag_id
       where a.station = 'waschen' and not a.ist_fax and p.sortierdatum is not null))::int
                                                                                          as wasch_kisten_mit_sortierdatum,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from v_palox_stand p
    where p.auftrag_id = f.id and p.differenz is null))::int                              as arbeiten_mit_palox_unbekannt,
  -- 0076: Die Eingangspalette — dort, wo eine gezählt wird (Sortieren und
  -- Waschen + Sortieren; beim Waschen kommt die Ware aus dem Zwischenlager
  -- und hat keine Eingangspalette).
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where not a.ist_fax and a.station in ('sortieren', 'waschen_sortieren'))::int         as eingangspaletten,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where not a.ist_fax and a.station in ('sortieren', 'waschen_sortieren')
      and ap.kisten is not null and ap.kisten > 0)::int                                   as eingangspaletten_mit_kisten,
  -- 0076: Wie oft ist das Alter der Ware ABGELESEN und nicht geschätzt?
  -- Gemessen ist es, wo der Arbeiter das Eingangsdatum von jedem Zettel
  -- tippt (Sortieren, Waschen + Sortieren). Beim Waschen kommt die Palette
  -- aus dem Zwischenlager und trägt kein Eingangsdatum mehr — dort steht
  -- eine Schätzung (0073, alter_quelle). Der Betriebsleiter soll sehen,
  -- wie viel von der Verderbskurve auf abgelesenen Daten ruht.
  -- Gelesen wird mv_auftrag_masse, nicht v_auftrag_masse: dieselbe Regel
  -- (`lagertage is not null` heisst gemessen), aber ohne den zweiten Lauf
  -- über die Sicht, der im Lasttest Zeit kostet.
  (select count(*) from mv_auftrag_masse m join fertig f on f.id = m.auftrag_id
    where not f.ist_fax and m.lagertage is not null)::int                                 as arbeiten_alter_gemessen;

comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung. Seit 0061 zählen beim Waschen die '
  'gezählten Paletten (Kisten mit Sortierdatum) mit; die Lagerkontrolle zählt '
  'als Verdunstungsmessung, ohne Faul-Angabe. Seit 0073 neu angelegt, weil '
  '`select a.*` die Spaltenliste einfriert (0072 gab auftrag zwei Spalten). '
  'Seit 0076 zusätzlich die Kistenzahl auf der Eingangspalette — ohne sie hat '
  'die Palette kein Netto und fehlt in der Masse (AB-49).';

-- ---------------------------------------------------------------------
-- Die gespeicherte Fassung muss mitkommen
-- ---------------------------------------------------------------------
-- erg_datenqualitaet ist ein `create materialized view … as select * from
-- v_datenqualitaet` (0065). Der Stern ist dort beim Anlegen eingefroren:
-- Die drei neuen Spalten der Sicht kämen über die Migrationen NICHT in der
-- gespeicherten Fassung an, über setup.sql (Teil B legt alles frisch an)
-- schon. Genau diesen Unterschied findet der Fingerabdruck-Vergleich in
-- supabase/test/run.sh — er hat ihn beim ersten Lauf dieser Migration auch
-- gefunden. Also neu bauen, mit demselben Wortlaut wie 0065, damit beide
-- Wege wieder Zeichen für Zeichen dieselbe Datenbank ergeben.
--
-- `with no data`: gefüllt wird beim nächsten Lauf von auswertung_schritt(),
-- nicht hier. setup.sql darf keine Zwischenstände rechnen (AB-32).
-- Als EIN Block, nicht als vier Anweisungen: Der Verdichter sortiert
-- einzelne `drop` nach Teil A und einzelne `create` nach Teil B — das
-- Wegräumen und das Anlegen wären dann weit voneinander getrennt, und das
-- Anlegen liefe hinter der Schleife aus 0065/0068, die die gespeicherte
-- Fassung schon gebaut hat („relation erg_datenqualitaet already exists").
-- In einem `do`-Block bleiben sie zusammen. Der Kommentar darüber sagt dem
-- Verdichter, welches Objekt hier entsteht — der Name steht im Text, nicht
-- im SQL-Baum.
-- verdichter: baut erg_datenqualitaet
do $$
begin
  execute 'drop materialized view if exists erg_datenqualitaet cascade';
  execute 'create materialized view erg_datenqualitaet as select * from v_datenqualitaet with no data';
  execute 'grant select on erg_datenqualitaet to authenticated';
  execute format('comment on materialized view erg_datenqualitaet is %L',
                 'v_datenqualitaet, gespeichert für die App Erneuert mit auswertung_schritt().');
end $$;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 76 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
