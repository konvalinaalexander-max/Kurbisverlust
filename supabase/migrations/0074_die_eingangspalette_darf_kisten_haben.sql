-- =====================================================================
-- 0074 — Die Eingangspalette darf eine Kistenzahl haben
--
-- Der Betrieb hat den Weg zur Masse je Kaliberband selbst gefunden:
--
--   „du siehst ja dann anzahl paletten - mit anzahl kisten und total vom
--    brutto gewicht - dann weisst du wieviel sortiert worden ist"
--
-- Dafür muss der Zähler beim Sortieren die Kistenzahl je Eingangspalette
-- erfassen. Genau das hätte die Auswertung stillgelegt.
--
-- WAS PASSIERT WÄRE
--
-- v_auftrag_palette_masse endet seit 0064 mit `where ap.kisten is null`.
-- Das war damals die Trennung zwischen zwei Welten: Eingangspaletten
-- (ohne Kisten) rechnet diese Sicht, Kaliber-Paletten beim Waschen (mit
-- Kisten) rechnet v_auftrag_wasch_paletten. Die Kistenzahl war das
-- Unterscheidungsmerkmal — weil sie zufällig nur auf der einen Seite
-- vorkam.
--
-- Schreibt der Zähler künftig Kisten auf Eingangspaletten, kippt diese
-- Trennung. Nachgemessen an den Beispieldaten:
--
--   vorher:   289 Zeilen für Sortierarbeiten in v_auftrag_palette_masse
--   nachher:    0 Zeilen
--             31 Sortierarbeiten mit n_paletten = 0 und Masse NULL
--
-- Kein Fehler, keine Warnung. Die Arbeiten wären einfach verschwunden —
-- und ausgerechnet die Änderung, die ihre Masse GENAUER machen soll,
-- hätte sie gelöscht.
--
-- WAS STATTDESSEN GILT
--
-- Getrennt wird nach der STATION, nicht nach einer Spalte, die zufällig
-- leer ist. v_auftrag_wasch_paletten filtert ohnehin schon selbst auf
-- `station = 'waschen' and not ist_fax` — diese Sicht nimmt genau den
-- Rest. Damit ist die Trennung ausgesprochen statt geraten, und sie hält
-- auch, wenn später eine weitere Spalte hinzukommt.
-- =====================================================================
set client_min_messages = warning;

create or replace view v_auftrag_palette_masse with (security_invoker = true) as
with wiegung as materialized (
  select vw.id,
         zahl(vw.brutto_damals_kg - vw.kisten * g.tara_kg_pro_kiste
              - g.tara_kg_palette, 2, 1e8)::numeric(10,2) as netto_damals_kg,
         vw.eingangsdatum
    from verdunstung_wiegung vw
    left join gebinde g on g.art = vw.gebindeart
), datum_mittel as materialized (
  select charge_nr, eingangsdatum, avg(netto_kg) as netto_mittel
    from v_palette group by charge_nr, eingangsdatum
), charge_mittel as materialized (
  select charge_nr, avg(netto_kg) as netto_mittel,
         avg(brutto_kg - netto_kg) filter (where netto_kg is not null) as tara_mittel
    from v_palette group by charge_nr
), charge_datum as materialized (
  select charge_nr, eingangsdatum_mittel from v_charge_rueckgrat
), zettel as materialized (
  select ap.id,
         coalesce(pe.netto_kg,
                  zahl(ap.brutto_zettel_kg - cm.tara_mittel, 2, 1e8)::numeric(10,2)) as netto_kg,
         (pe.id is not null) as exakt
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join lateral (
      select p.id, p.netto_kg from v_palette p
       where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum
         and p.brutto_kg = ap.brutto_zettel_kg and p.netto_kg is not null
       order by p.id limit 1) pe on true
    left join charge_mittel cm on cm.charge_nr = a.charge_nr
   where ap.brutto_zettel_kg is not null
)
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(w.netto_damals_kg, z.netto_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel) as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) as eingangsdatum,
       case when w.netto_damals_kg is not null then 'gewogen'
            when z.netto_kg is not null and z.exakt then 'zettel'
            when z.netto_kg is not null then 'zettel-charge-tara'
            when p.netto_kg is not null then 'palette'
            when d.netto_mittel is not null then 'datum-mittel'
            when cm.netto_mittel is not null then 'charge-mittel'
            else 'unbekannt' end::text                                                 as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join wiegung w on w.id = ap.wiegung_id
  left join zettel z on z.id = ap.id
  left join v_palette p on p.id = ap.palette_id
  left join datum_mittel d on d.charge_nr = a.charge_nr and d.eingangsdatum = ap.eingangsdatum
  left join charge_mittel cm on cm.charge_nr = a.charge_nr
  left join charge_datum cd on cd.charge_nr = a.charge_nr
 where not (a.station = 'waschen' and not a.ist_fax);
comment on view v_auftrag_palette_masse is
  'Netto je gezählter Eingangspalette: gewogen, vom Zettel, aus dem Wareneingang, '
  'oder das Mittel des Eingangstags / der Charge; masse_quelle sagt, welcher Weg es '
  'war. Beim Waschen gezählte Kaliber-Paletten stehen nicht hier — ihre Masse '
  'rechnet v_auftrag_wasch_paletten (0061). Getrennt wird seit 0074 nach der '
  'STATION statt nach „hat eine Kistenzahl": seit der Zähler beim Sortieren die '
  'Kisten je Eingangspalette erfasst, wäre das alte Merkmal die Löschtaste für '
  'jede Sortierarbeit gewesen.';

-- =====================================================================
-- Der Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 74 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
