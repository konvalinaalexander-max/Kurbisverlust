-- =====================================================================
-- 0012 — Wiegen gehört ans Zählen, nicht in einen eigenen Reiter
--
-- Es ist dieselbe Person, die die Paletten zählt und sie wiegt. Statt eines
-- getrennten Reiters fragt die App künftig bei jeder gezählten Palette, ob
-- sie auch gewogen wurde. Daraus folgen zwei Änderungen am Datenmodell:
--
--   1. Zählung und Wägung müssen verbunden sein (wiegung_id) — bisher standen
--      sie unverbunden nebeneinander, obwohl sie dieselbe Palette meinen.
--   2. Die Palette wird nicht mehr aus einer Liste gesucht. Bei hunderten
--      Paletten, von denen viele gleich schwer sind, ist das nicht bedienbar
--      und lädt zum Vergreifen ein. Der Arbeiter tippt stattdessen ab, was
--      auf dem Zettel steht: Eingangsdatum und Eingangsgewicht. Beide Felder
--      gibt es in verdunstung_wiegung bereits; palette_id bleibt einfach leer.
--
-- Der Gewinn ist größer als nur die Bedienung: Eine gewogene Palette liefert
-- ihr Eingangsgewicht *exakt* mit. Bisher musste die Auswertung die Masse
-- hinter einer gezählten Palette über Mittelwerte schätzen.
-- =====================================================================

alter table auftrag_palette
  add column if not exists wiegung_id bigint references verdunstung_wiegung(id) on delete set null;

comment on column auftrag_palette.wiegung_id is
  'Verweist auf die Wägung derselben Palette, falls sie beim Zählen gewogen wurde. '
  'Dann ist ihr Eingangsgewicht bekannt statt geschätzt.';

create index if not exists auftrag_palette_wiegung on auftrag_palette (wiegung_id);

-- Wie viele Kürbisse in einer Kiste liegen. Freiwillig, aber die einzige
-- Angabe, die aus dem Palettengewicht ein Durchschnittsgewicht je Kürbis
-- macht — auf der Hand-Linie gibt es keine Sortier-CSV, die das liefert.
alter table verdunstung_wiegung
  add column if not exists kuerbisse_pro_kiste int check (kuerbisse_pro_kiste > 0);

-- ---------- Masse hinter einer gezählten Palette --------------------------
-- Neue oberste Stufe: die tatsächlich gewogene Palette. Der Rest der Leiter
-- bleibt unverändert, damit auch nur gezählte Paletten weiterhin zählen.
create or replace view v_auftrag_palette_masse with (security_invoker = true) as
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(w.netto_damals_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel)   as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum,
                cm.eingangsdatum_mittel)                                          as eingangsdatum,
       case when w.netto_damals_kg is not null then 'gewogen'
            when p.netto_kg        is not null then 'palette'
            when d.netto_mittel    is not null then 'datum-mittel'
            when cm.netto_mittel   is not null then 'charge-mittel'
            else 'unbekannt' end                                                  as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join lateral (
        -- Eingangs-Netto aus der Wägung: genau die Palette, exakt ihr Gewicht
        select (vw.brutto_damals_kg
                - coalesce(vw.kisten, 0) * g.tara_kg_pro_kiste
                - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_damals_kg,
               vw.eingangsdatum
          from verdunstung_wiegung vw
          left join gebinde g on g.art = vw.gebindeart
         where vw.id = ap.wiegung_id
       ) w on true
  left join v_palette p on p.id = ap.palette_id
  left join lateral (
        select avg(x.netto_kg) as netto_mittel
          from v_palette x
         where x.charge_nr = a.charge_nr and x.eingangsdatum = ap.eingangsdatum
       ) d on true
  left join lateral (
        select avg(x.netto_kg) as netto_mittel, r.eingangsdatum_mittel
          from v_palette x, v_charge_rueckgrat r
         where x.charge_nr = a.charge_nr and r.charge_nr = a.charge_nr
         group by r.eingangsdatum_mittel
       ) cm on true;

-- ---------- Was eine gewogene Palette verrät ------------------------------
-- Beantwortet die Frage „wie schwer ist ein einzelner Kürbis im Schnitt?",
-- für die es auf der Hand-Linie sonst keine Quelle gibt.
create view v_wiegung_kennzahl with (security_invoker = true) as
select w.id, w.auftrag_id, w.charge_nr, c.sorte, c.schlag,
       w.eingangsdatum, w.wiege_ts, w.kisten, w.gebindeart,
       w.sichtbar_schimmel, w.kuerbisse_pro_kiste,
       (w.wiege_ts::date - w.eingangsdatum)                              as lagertage,
       n.netto_damals_kg, n.netto_jetzt_kg,
       (n.netto_jetzt_kg / nullif(w.kisten, 0))::numeric(10,3)           as kg_pro_kiste,
       (n.netto_jetzt_kg / nullif(w.kisten * w.kuerbisse_pro_kiste, 0))::numeric(10,3)
                                                                         as kg_pro_kuerbis,
       (n.netto_damals_kg - n.netto_jetzt_kg)::numeric(10,2)             as verlust_kg
  from verdunstung_wiegung w
  join charge c on c.nr = w.charge_nr
  left join gebinde g on g.art = w.gebindeart
  cross join lateral (
        select (w.brutto_damals_kg - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_damals_kg,
               (w.brutto_jetzt_kg  - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_jetzt_kg
       ) n
 where w.gemessen;

comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, Gewichtsverlust, kg je Kiste '
  'und — falls die Kürbisse je Kiste erfasst wurden — kg je Kürbis.';

grant select on v_wiegung_kennzahl to authenticated;
