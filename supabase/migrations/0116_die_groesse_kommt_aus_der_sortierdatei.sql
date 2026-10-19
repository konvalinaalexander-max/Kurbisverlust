-- 0116 — Die Grösse kommt aus der Sortierdatei; Hagel, Ausreisser, Kunden und Pläne
--
-- WARUM
--
-- Die lange Nachricht des Betriebs vom 19. Oktober (Runde AS):
--
-- 1. „Zu klein und zu gross … primär solltest du die Information aus den
--    Sortier-CSVs nehmen … beim Waschen und Sortieren werden sicher viele
--    Kürbisse dabei sein, die unter das Limit fallen oder darüber, und sie
--    werden von Auge nicht erkannt." Bis hier war zu klein / zu gross je
--    Sorte EIN Anteil, das gleichgewichtete Mittel aus Sortierläufen und
--    Handmessungen, gleich für jedes Alter der Ware. Jetzt: Jeder Sortierlauf
--    wird auf den Eingangstag zurückgerechnet — jeder Kürbis um die gemessene
--    Verdunstung der Sorte über das Alter der Ware beim Sortieren (aus den
--    Zetteldaten der Arbeit, sonst aus den Paletten, die schon da waren). Das
--    ergibt je Charge (sonst je Sorte) die Gewichtsverteilung beim Eingang
--    (mv_kaliber_eingang). Für jede Portion der Kaskade, für jeden Horizont
--    der Prognose und jede Woche des Verlaufs wird sie um die Verdunstung bis
--    zu ihrem Alter geschrumpft und gegen die Grenzen der gültigen Fassung
--    gelegt: was darunter fällt, ist zu klein, was darüber, zu gross. Die
--    Handmessungen gelten nur noch, wo es für die Sorte keine Sortierdatei
--    gibt.
-- 2. Hagelschaden je Charge (charge.hagel_anteil): „wenn 20 % Hagelschaden,
--    dann ist 20 % vom Wareneingang nicht mehr verfügbar … schau, dass du das
--    nicht doppelt zählst." Der Hagel kommt beim Waschen und Sortieren in den
--    Palox. Er erhöht darum den Palox-Anteil dort, wo noch keine Messung der
--    Charge ihn schon enthält: im Lager immer, im Ausgelagerten nur ohne
--    eigene Messung — f = 1 − (1 − f) · (1 − Hagel). 100 % heisst: nichts
--    davon ist verkaufsfähig. Eine Charge mit Hagel zählt nicht in die
--    geteilten Palox-Anteile der Sorte und der Station; sonst trüge jede
--    andere Charge ihren Hagel mit.
-- 3. Ausreisser von Hand ausschliessen (messung_ausschluss): „ein Feld zum
--    Anklicken, benutzen oder nicht benutzen … damit ich Ausreisser
--    rausnehmen kann" — für Palox-Messungen (eine Arbeit, eine
--    Kontrollwägung) und Verdunstungs-Wägungen. Ausgeschlossen heisst: steht
--    im Bild, zählt in keine Rate, ab der nächsten Rechnung.
-- 4. Kundengruppen (kunde_gruppe) und Planmengen (kunde_plan) für das
--    Lagermanagement nach Artikel — „Coop als Ganzes", und „wir möchten mit
--    Planmengen arbeiten, Demeter und Knospe getrennt".
-- 5. Die ganze Perigon-Zeile an jeder Position (ausgang_position.roh), damit
--    die App sie zeigen kann: „eine Replika der Excel-Zeile, alle Spalten".
--    Gefüllt beim nächsten Einlesen der Dateien.
-- 6. Holz-Palox 45 kg und Plastik-Palox 35 kg Tara, eine Palox ein Gebinde.
--    Bis hier hatte „Holz Palox" keine Tara: Die Zettel solcher Paletten
--    rechneten mit der mittleren Tara der Charge — der von G2-Paletten mit 36
--    Kisten (79 kg) für eine einzelne Palox. „Schau, dass du das auf die
--    Kiste anpasst": Wo eine Tara fehlt, gilt jetzt die Tara je Kiste der
--    Charge mal die gezählten Kisten, und eine Palette ohne Gewicht nimmt das
--    Netto je Kiste mal ihre Kisten — nie mehr ein ganzes Paletten-Mittel für
--    eine halbe Palette. Die Auffälligkeiten sagen, welche Regel gerechnet hat.
-- 7. Weitere Prüfungen der Perigon-Dateien (v_perigon_pruefung) — „solche
--    Infos, dass du das Perigon durchscannst, hervorragend. Das darfst du
--    gerne erweitern."
--
-- Was danach im Betrieb zu tun ist: setup.sql einspielen, beide
-- Perigon-Dateien neu einlesen (für die ganze Zeile), einmal „Neu rechnen".

-- =====================================================================
-- 1. Gebinde: Holz-Palox und Plastik-Palox
-- =====================================================================
-- Der Betrieb: „Holzpalox 45 Kilo Tara, Plastikpalox 35 Kilo Tara." Eine
-- Palox ist ihr eigenes Gebinde mit Füssen — eine Palox, eine „Kiste",
-- keine Palette darunter (wie 0112 für Plastik-Palox). Hier gesetzt, auch
-- wenn die Zeile schon steht: Die Zahl kommt vom Betrieb.
insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette, bemerkung)
values ('Holz Palox', 45.0, 0, 'Betrieb, 19.10.2026 (0116): eine Palox = ein Gebinde, Tara 45 kg, keine Palette'),
       ('Plastik Palox', 35.0, 0, 'Betrieb, 19.10.2026 (0116): eine Palox = ein Gebinde, Tara 35 kg, keine Palette')
on conflict (art) do update
  set tara_kg_pro_kiste = excluded.tara_kg_pro_kiste, tara_kg_palette = excluded.tara_kg_palette,
      bemerkung = excluded.bemerkung
  where gebinde.tara_kg_pro_kiste is distinct from excluded.tara_kg_pro_kiste
     or gebinde.tara_kg_palette is distinct from excluded.tara_kg_palette;

-- =====================================================================
-- 2. Tabellen und Spalten
-- =====================================================================
-- 2a. Hagelschaden je Charge
alter table charge add column if not exists hagel_anteil numeric(5,4);
alter table charge add column if not exists hagel_ts timestamptz;
do $$ begin
  alter table charge add constraint charge_hagel_anteil check (hagel_anteil > 0 and hagel_anteil <= 1);
exception when duplicate_object then null; end $$;
comment on column charge.hagel_anteil is
  'Hagelschaden der Charge als Anteil des Eingangs (0116), vom Betriebsleiter unter Chargen gesetzt; leer = kein Hagel. Er kommt beim Waschen und Sortieren in den Palox: f = 1 − (1 − f) · (1 − Hagel) für alles, was noch liegt, und für Ausgelagertes ohne eigene Messung. 1 = nichts verkaufsfähig.';
comment on column charge.hagel_ts is 'Wann der Hagelschaden zuletzt gesetzt wurde (0116).';

-- 2b. Von Hand ausgeschlossene Messungen
create table if not exists messung_ausschluss (
  art       text   not null check (art in ('palox', 'palox_lager', 'verdunstung')),
  bezug_id  bigint not null,
  grund     text,
  erfasser  uuid references profil(id) on delete set null default auth.uid(),
  ts        timestamptz not null default now(),
  primary key (art, bezug_id)
);
comment on table messung_ausschluss is
  'Messungen, die der Betriebsleiter von Hand aus der Rechnung nimmt (0116): palox — der Palox-Anteil einer Arbeit (bezug_id = auftrag.id); palox_lager — das Faule einer Kontrollwägung (bezug_id = verdunstung_wiegung.id); verdunstung — eine Verdunstungs-Wägung (bezug_id = verdunstung_wiegung.id). Die Messung bleibt im Bild und zählt in keine Rate; ab der nächsten Rechnung. Löschen der Zeile nimmt sie wieder auf.';
alter table messung_ausschluss enable row level security;
drop policy if exists messung_ausschluss_lesen on messung_ausschluss;
drop policy if exists messung_ausschluss_admin on messung_ausschluss;
create policy messung_ausschluss_lesen on messung_ausschluss for select to authenticated using (true);
create policy messung_ausschluss_admin on messung_ausschluss for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on messung_ausschluss to authenticated;

-- 2c. Kundengruppen
create table if not exists kunde_gruppe (
  kunde     text primary key check (btrim(kunde) <> ''),
  gruppe    text not null check (btrim(gruppe) <> ''),
  erfasser  uuid references profil(id) on delete set null default auth.uid(),
  ts        timestamptz not null default now()
);
comment on table kunde_gruppe is
  'Zu welcher Gruppe ein Perigon-Kunde (AuftragsLieferant) gehört (0116), vom Betriebsleiter gesetzt. Ohne Eintrag ordnet die App nach dem Namen: Migros, Coop (auch RVZ/RZV), sonst Kleinkunden.';
alter table kunde_gruppe enable row level security;
drop policy if exists kunde_gruppe_lesen on kunde_gruppe;
drop policy if exists kunde_gruppe_admin on kunde_gruppe;
create policy kunde_gruppe_lesen on kunde_gruppe for select to authenticated using (true);
create policy kunde_gruppe_admin on kunde_gruppe for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on kunde_gruppe to authenticated;

-- 2d. Planmengen je Kunde
create table if not exists kunde_plan (
  id            bigint generated by default as identity primary key,
  saison        int  not null,
  kunde         text not null check (btrim(kunde) <> ''),
  artikelgruppe text not null default '',
  groesse       text not null default '' check (groesse in ('', 'klein', 'gross')),
  label         text not null default '' check (label in ('', 'D', 'K')),
  kg            numeric(12,1) not null check (kg >= 0),
  erfasser      uuid references profil(id) on delete set null default auth.uid(),
  ts            timestamptz not null default now(),
  unique (saison, kunde, artikelgruppe, groesse, label)
);
comment on table kunde_plan is
  'Die Planmenge eines Kunden für eine Saison (0116), in kg — je Artikelgruppe, Grösse und Label oder für alle ('''' = alle). Gilt genau für die Wahl, für die sie eingetragen ist; ohne Plan nimmt die App die ganze Vorjahressaison als Plan. Vom Betriebsleiter gesetzt.';
alter table kunde_plan enable row level security;
drop policy if exists kunde_plan_lesen on kunde_plan;
drop policy if exists kunde_plan_admin on kunde_plan;
create policy kunde_plan_lesen on kunde_plan for select to authenticated using (true);
create policy kunde_plan_admin on kunde_plan for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on kunde_plan to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- 2e. Die ganze Perigon-Zeile
alter table ausgang_position add column if not exists roh jsonb;
comment on column ausgang_position.roh is
  'Die Zeilen der Perigon-Datei zu dieser Position, je Zeile alle Spalten so, wie sie in der Datei stehen (Spaltenname → Wert) — 0116, für „die ganze Excel-Zeile" in der App. Leer, bis die Datei nach 0116 neu eingelesen ist.';

-- =====================================================================
-- 3. Eine Palette ohne eigenes Gewicht: auf ihre Kisten angepasst
-- =====================================================================
-- Der Betrieb: „dann sagst du, jetzt wird die Mitte genommen. Aber schau,
-- dass du das dann schon auf die Kiste anpasst … ich habe ein, zwei Fälle
-- gesehen, wo du es noch nicht so machst." Es waren die Holz-Palox-Paletten
-- der Charge 1638: ohne Tara des Gebindes rechnete der Zettel mit der
-- mittleren Tara der Charge — 79 kg, die Tara einer G2-Palette mit 36
-- Kisten, für eine einzelne Palox. Jetzt (nach dem Gebinde und der Tara je
-- Gebinde) die Tara je Kiste der Charge mal die gezählten Kisten; eine
-- Palette ohne Zettelgewicht das Netto je Kiste mal ihre Kisten.
create or replace view v_auftrag_palette_masse with (security_invoker = true) as
with wiegung as materialized (
  select vw.id,
         zahl(vw.brutto_damals_kg - vw.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000)::numeric(10,2) as netto_damals_kg,
         vw.eingangsdatum
    from verdunstung_wiegung vw
    left join gebinde g on g.art = vw.gebindeart
), datum_mittel as materialized (
  -- 0116: auch je Kiste — eine Palette ohne Gewicht nimmt das Mittel je Kiste
  -- mal ihre Kisten, nicht das Mittel ganzer Paletten.
  select charge_nr, eingangsdatum, avg(netto_kg) as netto_mittel,
         avg(netto_kg / kisten) filter (where netto_kg is not null and kisten > 0) as netto_je_kiste
    from v_palette group by charge_nr, eingangsdatum
), charge_mittel as materialized (
  select charge_nr, avg(netto_kg) as netto_mittel,
         avg(brutto_kg - netto_kg) filter (where netto_kg is not null) as tara_mittel,
         avg(netto_kg / kisten) filter (where netto_kg is not null and kisten > 0) as netto_je_kiste,
         avg((brutto_kg - netto_kg) / kisten) filter (where netto_kg is not null and kisten > 0) as tara_je_kiste
    from v_palette group by charge_nr
), charge_datum as materialized (
  select charge_nr, eingangsdatum_mittel from v_charge_rueckgrat
), zettel as materialized (
  select ap.id,
         coalesce(pe.netto_kg,

                  case when pe.id is null and ap.kisten is not null
                        and g.tara_kg_pro_kiste is not null and g.tara_kg_palette is not null
                        and ap.brutto_zettel_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette > 0
                       then zahl(ap.brutto_zettel_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000)::numeric(10,2)
                  end,
                  -- 0116: ohne Tara des Gebindes die Tara je Kiste der Charge mal die
                  -- gezählten Kisten („schau, dass du das auf die Kiste anpasst");
                  -- nur ohne Kistenzahl die mittlere Tara ganzer Paletten.
                  zahl(ap.brutto_zettel_kg - coalesce(ap.kisten::numeric * cm.tara_je_kiste, cm.tara_mittel), 2, 100000000)::numeric(10,2)) as netto_kg,
         (pe.id is not null) as exakt,
         (pe.id is null and ap.kisten is not null
          and g.tara_kg_pro_kiste is not null and g.tara_kg_palette is not null
          and ap.brutto_zettel_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette > 0) as kisten_tara,
         (pe.id is null and ap.kisten is not null and cm.tara_je_kiste is not null) as kisten_charge
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join lateral (
      select p.id, p.netto_kg
        from v_palette p
       where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum
         and p.brutto_kg = ap.brutto_zettel_kg and p.netto_kg is not null
       order by p.id limit 1) pe on true
    left join gebinde g on g.art = ap.gebindeart
    left join charge_mittel cm on cm.charge_nr = a.charge_nr
   where ap.brutto_zettel_kg is not null
)
select ap.id,
       ap.auftrag_id,
       a.charge_nr,
       a.start_ts,
       coalesce(w.netto_damals_kg, z.netto_kg, p.netto_kg,
                ap.kisten * d.netto_je_kiste, d.netto_mittel, ap.kisten * cm.netto_je_kiste, cm.netto_mittel) as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) as eingangsdatum,
       case
         when w.netto_damals_kg is not null       then 'gewogen'
         when z.netto_kg is not null and z.exakt  then 'zettel'
         when z.netto_kg is not null and z.kisten_tara then 'zettel-kisten'
         when z.netto_kg is not null and z.kisten_charge then 'zettel-kisten-charge'
         when z.netto_kg is not null              then 'zettel-charge-tara'
         when p.netto_kg is not null              then 'palette'
         when ap.kisten is not null and d.netto_je_kiste is not null then 'datum-je-kiste'
         when d.netto_mittel is not null          then 'datum-mittel'
         when ap.kisten is not null and cm.netto_je_kiste is not null then 'charge-je-kiste'
         when cm.netto_mittel is not null         then 'charge-mittel'
         else 'unbekannt'
       end as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join wiegung w on w.id = ap.wiegung_id
  left join zettel z on z.id = ap.id
  left join v_palette p on p.id = ap.palette_id
  left join datum_mittel d on d.charge_nr = a.charge_nr and d.eingangsdatum = ap.eingangsdatum
  left join charge_mittel cm on cm.charge_nr = a.charge_nr
  left join charge_datum cd on cd.charge_nr = a.charge_nr
 where not (a.station = 'waschen' and not a.ist_fax);

-- =====================================================================
-- 4. Von Hand ausgeschlossene Messungen, und der Hagel zählt nicht für andere
-- =====================================================================
-- Eine ausgeschlossene Verdunstungs-Wägung ist nicht verwendbar (Grund „von
-- Hand ausgeschlossen"), ein ausgeschlossener Palox-Punkt nicht plausibel —
-- beide stehen weiter im Bild, aber in keiner Rate.
create or replace view v_verdunstung_messung with (security_invoker = true) as
select b.id,
       b.charge_nr,
       b.sorte,
       b.schlag,
       b.palette_id,
       b.eingangsdatum,
       b.wiege_ts,
       b.sichtbar_schimmel,
       b.erfasser,
       b.auftrag_id,
       b.netto_damals_kg,
       b.netto_jetzt_kg,
       b.lagertage,
       r.rate_pro_tag,
       (u.grund is null)                                               as verwendbar,
       (r.rate_pro_tag is null or r.rate_pro_tag <= k.rate_max)       as plausibel,
       u.grund
  from (

    select w.id, w.charge_nr, c.sorte, c.schlag, w.palette_id, w.eingangsdatum, w.wiege_ts,
           w.sichtbar_schimmel, w.erfasser, w.auftrag_id, w.gemessen,
           (a.id is not null and a.abgebrochen_ts is not null)                              as abgebrochen,
           w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette as netto_damals_kg,
           w.brutto_jetzt_kg  - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette as netto_jetzt_kg,
           (betriebstag(w.wiege_ts) - w.eingangsdatum)                                       as lagertage
      from verdunstung_wiegung w
      join charge c on c.nr = w.charge_nr
      left join auftrag a on a.id = w.auftrag_id
      left join gebinde g on g.art = w.gebindeart
    offset 0
  ) b

  cross join (select verdunstung_rate_max() as rate_max) k
  cross join lateral (
    select zahl(case when b.netto_damals_kg > 0 and b.netto_jetzt_kg > 0 and b.lagertage > 0
                     then 1 - power(b.netto_jetzt_kg / b.netto_damals_kg, (1.0 / b.lagertage)::numeric)
                end, 6, 10000)::numeric(10,6) as rate_pro_tag
    offset 0
  ) r
  cross join lateral (

    select case
             -- 0116: der Betriebsleiter nimmt einen Ausreisser von Hand heraus (Ursachen → Verdunstung).
             when exists (select 1 from messung_ausschluss x where x.art = 'verdunstung' and x.bezug_id = b.id)
                                                                     then 'von Hand ausgeschlossen'
             when not b.gemessen                                     then 'nicht gemessen'
             when b.sichtbar_schimmel                                then 'Schimmel sichtbar — die Palette verlor mehr als Wasser'
             when b.abgebrochen                                      then 'Arbeit abgebrochen'
             when b.netto_damals_kg is null or b.netto_jetzt_kg is null then 'ohne Netto — die Tara des Gebindes fehlt'
             when b.netto_damals_kg <= 0 or b.netto_jetzt_kg <= 0    then 'Netto unter null — das Brutto ist kleiner als die Tara'
             when b.lagertage <= 0                                   then 'am Eingangstag gewogen — keine Lagerdauer'
             when b.netto_jetzt_kg > b.netto_damals_kg * 1.01        then 'schwerer geworden — Waagenrauschen oder ein kopiertes Eingangsgewicht'
             when b.netto_jetzt_kg = b.netto_damals_kg               then 'unverändert — dieselbe Zahl zweimal'
             when r.rate_pro_tag > k.rate_max
               then format('zu schnell — %s %% je Tag ist keine Verdunstung', round(r.rate_pro_tag * 100, 2))
           end as grund
  ) u;

create or replace view v_schimmel_punkte_formel with (security_invoker = true) as
 WITH sortier_lauf_anteil AS MATERIALIZED (
         SELECT b.charge_nr,
            b.start_ts,
            b.schimmel_kg,
            b.basis_jetzt_kg
           FROM v_schimmel_beobachtung b
          WHERE b.station = 'sortieren'::station AND b.plausibel AND b.anteil IS NOT NULL
        ), gemischt AS (
         SELECT v_auftrag_angabe.auftrag_id
           FROM v_auftrag_angabe
          WHERE v_auftrag_angabe.schluessel = 'eine_charge'::text AND v_auftrag_angabe.wert = 'false'::text
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lagertage,
    b.schimmel_kg,
    b.basis_jetzt_kg,
    b.anteil,
    b.plausibel AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox'::text AND x.bezug_id = b.auftrag_id)) AS plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    b.auftrag_id,
    betriebstag(b.start_ts) AS messtag,
    b.station::text AS station,
    b.anteil AS anteil_station,
    b.plausibel AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox'::text AND x.bezug_id = b.auftrag_id)) AS plausibel_station
   FROM v_schimmel_beobachtung b
     LEFT JOIN gemischt g ON g.auftrag_id = b.auftrag_id
  WHERE b.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])
UNION ALL
 SELECT a.charge_nr,
    a.sorte,
    a.schlag,
    a.lagertage,
    s.kg AS schimmel_kg,
    a.eingang_netto_kg + s.kg AS basis_jetzt_kg,
    k.f2 AS anteil,
    anteil_plausibel(k.f2) AND a.lagertage >= 0::numeric AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox'::text AND x.bezug_id = a.auftrag_id)) AS plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    a.auftrag_id,
    betriebstag(a.start_ts) AS messtag,
    'waschen'::text AS station,
    x.g AS anteil_station,
    anteil_plausibel(x.g) AND a.lagertage >= 0::numeric AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox'::text AND x.bezug_id = a.auftrag_id)) AS plausibel_station
   FROM v_auftrag_masse a
     JOIN v_schimmel_menge s ON s.auftrag_id = a.auftrag_id
     LEFT JOIN gemischt g ON g.auftrag_id = a.auftrag_id
     LEFT JOIN LATERAL ( SELECT sum(sl.schimmel_kg) / NULLIF(sum(sl.basis_jetzt_kg), 0::numeric) AS f1
           FROM sortier_lauf_anteil sl
          WHERE sl.charge_nr = a.charge_nr AND sl.start_ts <= a.start_ts) sa ON true
     CROSS JOIN LATERAL ( SELECT s.kg / NULLIF(a.eingang_netto_kg + s.kg, 0::numeric) AS g) x
     CROSS JOIN LATERAL ( SELECT 1::numeric - (1::numeric - LEAST(GREATEST(COALESCE(sa.f1, 0::numeric), 0::numeric), 0.99)) * (1::numeric - LEAST(GREATEST(COALESCE(x.g, 0::numeric), 0::numeric), 0.99)) AS f2) k
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.lagertage IS NOT NULL AND a.eingang_netto_kg IS NOT NULL AND a.eingang_netto_kg > 0::numeric
UNION ALL
 SELECT w.charge_nr,
    w.sorte,
    w.schlag,
    w.lagertage,
    v.faul_kg AS schimmel_kg,
    w.netto_jetzt_kg AS basis_jetzt_kg,
    v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric) AS anteil,
    anteil_plausibel(v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric)) AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox_lager'::text AND x.bezug_id = w.id)) AS plausibel,
    'lager'::text AS quelle,
    NULL::bigint AS auftrag_id,
    betriebstag(w.wiege_ts) AS messtag,
    'lager'::text AS station,
    v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric) AS anteil_station,
    anteil_plausibel(v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric)) AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox_lager'::text AND x.bezug_id = w.id)) AS plausibel_station
   FROM v_verdunstung_messung w
     JOIN verdunstung_wiegung v ON v.id = w.id
  WHERE v.faul_kg IS NOT NULL AND v.gemessen AND w.netto_jetzt_kg > 0::numeric AND w.lagertage > 0;

-- Die geteilten Palox-Anteile (je Sorte und Station, der Anstieg je Woche)
-- ohne Chargen mit Hagel; die eigene Messung einer Hagel-Charge gilt für sie.
create or replace view v_palox_erwartung with (security_invoker = true) as
with punkte as materialized (
  select e.sorte, e.station, e.charge_nr, e.messtag, e.lagertage::numeric as t,
         e.basis_jetzt_kg as w, e.anteil_station as y
    from v_schimmel_punkte e
   where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
     and e.lagertage is not null
     and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
     and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
     -- 0116: eine Charge mit Hagel trägt ihren Hagel nicht in den Anteil der Sorte.
     and not exists (select 1 from charge hc where hc.nr = e.charge_nr and hc.hagel_anteil > 0)
), anstieg as materialized (
  select k.station, k.zuwachs_je_woche as b from v_palox_station k
), sorten as (
  select distinct sorte from v_kaskade_basis
  union
  select distinct sorte from punkte
), stationen(station) as (
  values ('waschen_sortieren'), ('sortieren'), ('waschen')
), ebenen(rang, ebene, quelle) as (
  values (1, 'sorte', 'Arbeiten dieser Sorte'), (2, 'alle', 'Arbeiten aller Sorten')
), je_ebene as (
  select s.sorte, st.station, e.rang, e.ebene, e.quelle,
         count(p.y)::int                          as n_arbeiten,
         count(distinct p.charge_nr)::int         as n_chargen,
         min(p.messtag)                           as seit,
         max(p.messtag)                           as bis,
         sum(p.w * p.y) / nullif(sum(p.w), 0)     as mittel,
         sum(p.w * p.t) / nullif(sum(p.w), 0)     as lager_mittel,
         stddev_samp(p.y)                         as sd
    from sorten s
   cross join stationen st
   cross join ebenen e
    left join punkte p on p.station = st.station and (e.rang = 2 or p.sorte = s.sorte)
   group by s.sorte, st.station, e.rang, e.ebene, e.quelle
), gueltig as (
  select j.*, a.b,
         greatest(j.mittel - coalesce(a.b, 0) * j.lager_mittel / 7.0, 0) as grund
    from je_ebene j
    left join anstieg a on a.station = j.station
   where j.n_arbeiten >= case when j.rang = 2 then 1 else palox_mindest_arbeiten() end
)
select distinct on (sorte, station)
       sorte, station, ebene, quelle,
       zahl(grund, 5, 1)::numeric(10,5) as anteil,
       zahl(case when n_arbeiten >= 2 and sd is not null
                 then greatest(grund - t_quantil_95(n_arbeiten - 1) * sd / sqrt(n_arbeiten), 0)
                 else grund end, 5, 1)::numeric(10,5) as unten,
       zahl(case when n_arbeiten >= 2 and sd is not null
                 then least(grund + t_quantil_95(n_arbeiten - 1) * sd / sqrt(n_arbeiten), 1)
                 else grund end, 5, 1)::numeric(10,5) as oben,
       n_arbeiten, n_chargen, seit, bis,
       ebene = 'alle' as geliehen,
       zahl(mittel, 5, 1)::numeric(10,5) as mittel,
       zahl(lager_mittel, 1, 100000)::numeric(10,1) as lager_mittel,
       zahl(b, 5, 1)::numeric(10,5) as anstieg_je_woche
  from gueltig
 order by sorte, station, rang;

create or replace function palox_station_kennzahl(p_bis date, p_ab date default null)
returns table(station text, n_arbeiten int, n_chargen int, seit date, bis date, tage int,
              anteil_mittel numeric, anteil_median numeric, anteil_4w numeric, n_4w int,
              zuwachs_je_woche numeric, zuwachs_text text,
              anstieg_roh numeric, anstieg_unten numeric, anstieg_oben numeric,
              n_paar int, spanne_tage int, lager_von int, lager_bis int,
              lager_mittel numeric, grund numeric)
language plpgsql stable set search_path = public as $$
#variable_conflict use_column
begin
  return query
  with p as (
    select e.station, e.sorte, e.charge_nr, e.messtag, e.lagertage::numeric as t,
           e.basis_jetzt_kg as w, e.anteil_station as y
      from erg_punkte e
     where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
       and e.lagertage is not null
       and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
       and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
       and e.messtag <= p_bis and (p_ab is null or e.messtag >= p_ab)
       -- 0116: eine Charge mit Hagel trägt ihren Hagel nicht in den Anteil der Station.
       and not exists (select 1 from charge hc where hc.nr = e.charge_nr and hc.hagel_anteil > 0)
  ), s as (
    -- Je Sorte und Station die eigene Mitte: verglichen wird nur innerhalb der Sorte.
    select p.*,
           sum(p.w * p.t) over ws / sum(p.w) over ws as t_s,
           sum(p.w * p.y) over ws / sum(p.w) over ws as y_s,
           count(*) over ws                         as n_s,
           max(p.t) over ws - min(p.t) over ws      as spanne_s
      from p
    window ws as (partition by p.station, p.sorte)
  ), je as (
    select station,
           count(*)::int as n_arbeiten, count(distinct charge_nr)::int as n_chargen,
           min(messtag) as seit, max(messtag) as bis, (max(messtag) - min(messtag))::int as tage,
           sum(w * y) / nullif(sum(w), 0) as anteil_mittel,
           percentile_cont(0.5) within group (order by y) as anteil_median,
           sum(w * y) filter (where messtag > p_bis - 28) / nullif(sum(w) filter (where messtag > p_bis - 28), 0) as anteil_4w,
           count(*) filter (where messtag > p_bis - 28)::int as n_4w,
           count(*) filter (where n_s >= 2)::int as n_paar,
           count(distinct sorte) filter (where n_s >= 2)::int as n_sorten_paar,
           coalesce(max(spanne_s), 0)::int as spanne_tage,
           min(t)::int as lager_von, max(t)::int as lager_bis,
           sum(w * t) / nullif(sum(w), 0) as lager_mittel,
           avg(w) filter (where n_s >= 2) as w_mittel,
           sum(w * (t - t_s) * (y - y_s)) / nullif(sum(w * power(t - t_s, 2)), 0) as b_tag
      from s
     group by station
  ), streuung as (
    -- Wie weit die Arbeiten um ihre Geraden streuen (je Sorte eine eigene
    -- Höhe, eine gemeinsame Steigung): daraus der Standardfehler der Steigung.
    select s.station,
           sum(s.w / j.w_mittel * power((s.y - s.y_s) - j.b_tag * (s.t - s.t_s), 2)) as sse,
           sum(s.w / j.w_mittel * power(s.t - s.t_s, 2)) as sxx,
           j.n_paar - j.n_sorten_paar - 1 as df
      from s join je j on j.station = s.station
     where s.n_s >= 2 and j.b_tag is not null
     group by s.station, j.n_paar, j.n_sorten_paar
  ), fertig as (
    select j.*,
           case when st.df >= 1 and st.sxx > 0 then sqrt(st.sse / st.df / st.sxx) end as se_tag,
           st.df,
           palox_anstieg(j.b_tag * 7, j.n_paar, j.spanne_tage) is not null as bekannt
      from je j left join streuung st on st.station = j.station
  ), regel as (
    -- Seit 0113: Der Anstieg gilt erst, wenn er sicher ist — die untere
    -- Grenze seines 95-%-Bereichs liegt über 0. Sonst gilt 0, und der
    -- Grundausschuss ist das gemessene Mittel (der Betrieb: „du musst nicht
    -- denken, dass wenn ich es heute ins Lager tue und morgen verkaufe, dass
    -- ich null Ausschuss habe").
    select f.*,
           case when f.se_tag is not null then (f.b_tag - t_quantil_95(f.df) * f.se_tag) * 7 end as unten_woche,
           palox_anstieg(f.b_tag * 7, f.n_paar, f.spanne_tage,
                         case when f.se_tag is not null then (f.b_tag - t_quantil_95(f.df) * f.se_tag) * 7 end) as gilt
      from fertig f
  )
  select f.station, f.n_arbeiten, f.n_chargen, f.seit, f.bis, f.tage,
         zahl(f.anteil_mittel, 5, 1)::numeric(10,5), zahl(f.anteil_median::numeric, 5, 1)::numeric(10,5),
         zahl(f.anteil_4w, 5, 1)::numeric(10,5), f.n_4w,
         zahl(f.gilt, 5, 1)::numeric(10,5) as zuwachs_je_woche,
         case when f.gilt > 0 then null
              when f.bekannt and f.b_tag > 0 then format('Anstieg noch nicht sicher (gemessen +%s %% je Woche, Bereich %s bis +%s %%) — gilt als 0',
                                         replace(to_char(f.b_tag * 700, 'FM990.0'), '.', ','),
                                         replace(replace(to_char(coalesce(f.unten_woche * 100, -99.9), 'FM990.0'), '.', ','), '-', '−'),
                                         replace(to_char((f.b_tag + t_quantil_95(f.df) * coalesce(f.se_tag, 0)) * 700, 'FM990.0'), '.', ','))
              when f.bekannt then format('kein Anstieg (gemessen %s %% je Woche — gilt als 0)',
                                         replace(replace(to_char(f.b_tag * 700, 'FM990.0'), '.', ','), '-', '−'))
              when f.n_paar < 5 then format('Anstieg erst ab fünf Arbeiten in Sorten mit mindestens zwei Arbeiten (%s bis jetzt)', f.n_paar)
              else format('Anstieg erst, wenn die Lagerdauern einer Sorte %s Tage auseinanderliegen (bis jetzt %s)',
                          palox_anstieg_mindest_tage(), f.spanne_tage) end as zuwachs_text,
         zahl(f.b_tag * 7, 5, 1)::numeric(10,5) as anstieg_roh,
         zahl((f.b_tag - t_quantil_95(f.df) * f.se_tag) * 7, 5, 1)::numeric(10,5) as anstieg_unten,
         zahl((f.b_tag + t_quantil_95(f.df) * f.se_tag) * 7, 5, 1)::numeric(10,5) as anstieg_oben,
         f.n_paar, f.spanne_tage, f.lager_von, f.lager_bis,
         zahl(f.lager_mittel, 1, 100000)::numeric(10,1) as lager_mittel,
         zahl(greatest(f.anteil_mittel - coalesce(f.gilt, 0) * f.lager_mittel / 7.0, 0), 5, 1)::numeric(10,5) as grund
    from regel f
   order by case f.station when 'waschen_sortieren' then 1 when 'waschen' then 2 else 3 end;
end $$;

-- =====================================================================
-- 5. Die Kürbisgrösse aus der Sortierdatei, auf den Eingangstag zurück
-- =====================================================================
-- Der Betrieb: „anhand vom Sortier-CSV weisst du, wie Chargen ungefähr sind
-- … und dann weisst du auch, wie das sich verändert anhand von der
-- Verdunstungsrate … dann könntest du durch Verdunstungsrate und mit dem
-- Wissen, wie lange die schon gelagert sind, herausfinden, wie beim
-- Eingangstag die Aufteilung nach Gewicht war."
--
-- 5a. Die Grenzen, an denen die Sortiermaschine heute trennt: die gültige
--     Fassung je Sorte (ohne Käufer) — unter der ersten Bandgrenze ist zu
--     klein, über der letzten zu gross.
create or replace view v_kaliber_fassung with (security_invoker = true) as
select distinct on (s.sorte) s.sorte,
       (s.kaliber_baender -> 0 ->> 0)::int                                          as lo,
       (s.kaliber_baender -> (jsonb_array_length(s.kaliber_baender) - 1) ->> 1)::int as hi,
       s.gilt_ab
  from sortierschema s
 where s.art = 'kaliber' and s.kaeufer is null and s.gilt_ab <= heute()
   and s.kaliber_baender is not null and jsonb_array_length(s.kaliber_baender) > 0
 order by s.sorte, s.gilt_ab desc;
comment on view v_kaliber_fassung is
  'Die Grenzen der gültigen Fassung je Sorte (0116): lo = untere Grenze des ersten Bandes (darunter zu klein), hi = obere Grenze des letzten (darüber zu gross).';

-- 5b. Jeder Sortierlauf mit dem Alter seiner Ware beim Sortieren. Das Alter
--     kommt aus den Zetteldaten der Arbeit, zu der die Datei gehört (das
--     Eingangsdatum ist beim Sortieren Pflicht), nach Masse gewichtet; ist
--     die Datei keiner Arbeit zugeordnet, aus den Paletten der Charge, die
--     am Sortiertag schon da waren. Mit der Verdunstungsrate der Sorte (0 %
--     je Tag, solange keine gemessen ist).
create or replace view v_kaliber_lauf with (security_invoker = true) as
with lauf as (
  select l.id as lauf_id, l.charge_nr, c.sorte, l.sortiertag, l.auftrag_id
    from sortier_lauf l
    join charge c on c.nr = l.charge_nr
    left join auftrag a on a.id = l.auftrag_id
   where l.sortiertag is not null and (a.id is null or a.abgebrochen_ts is null)
     and exists (select 1 from sortier_gewicht g where g.lauf_id = l.id and g.anzahl > 0 and g.gewicht_g > 0)
), zettel as (
  select l.lauf_id,
         sum(coalesce(m.netto_kg, 1) * (l.sortiertag - m.eingangsdatum))::numeric / nullif(sum(coalesce(m.netto_kg, 1)), 0) as alter_tage,
         count(*)::int as n_paletten
    from lauf l
    join v_auftrag_palette_masse m on m.auftrag_id = l.auftrag_id
   where m.eingangsdatum is not null and m.eingangsdatum <= l.sortiertag
   group by l.lauf_id
), eingang as (
  select l.lauf_id,
         sum(coalesce(p.netto_kg, p.brutto_kg) * (l.sortiertag - p.eingangsdatum))::numeric
           / nullif(sum(coalesce(p.netto_kg, p.brutto_kg)), 0) as alter_tage,
         count(*)::int as n_paletten
    from lauf l
    join v_palette p on p.charge_nr = l.charge_nr and p.eingangsdatum <= l.sortiertag
   group by l.lauf_id
)
select l.lauf_id, l.charge_nr, l.sorte, l.sortiertag, l.auftrag_id,
       coalesce(z.alter_tage, e.alter_tage)                                   as alter_tage,
       case when z.alter_tage is not null then 'zettel'
            when e.alter_tage is not null then 'eingang' end                  as alter_quelle,
       coalesce(z.n_paletten, e.n_paletten)                                   as n_paletten,
       least(greatest(coalesce(kv.mittel, 0), 0), 0.05)::numeric              as r
  from lauf l
  left join zettel z on z.lauf_id = l.lauf_id
  left join eingang e on e.lauf_id = l.lauf_id
  left join v_koeff_verdunstung kv on kv.sorte = l.sorte;
comment on view v_kaliber_lauf is
  'Je Sortierlauf mit Gewichten (0116): das Alter der Ware beim Sortieren — aus den Zetteldaten der Arbeit (alter_quelle zettel), sonst aus den Paletten der Charge, die am Sortiertag schon da waren (eingang) —, und die Verdunstungsrate der Sorte, mit der jeder Kürbis auf den Eingangstag zurückgerechnet wird.';

-- 5c. Die Gewichtsverteilung beim Eingang, je Charge und je Sorte: jeder
--     Kürbis g / (1 − r)^Alter, auf ganze Gramm; anteil_bis ist der Anteil
--     der Masse (beim Eingang) aller Kürbisse bis zu diesem Gewicht.
create materialized view mv_kaliber_eingang as
with kuerbis as (
  select l.charge_nr, l.sorte,
         round(g.gewicht_g::numeric / power(1 - l.r, l.alter_tage), 0) as g0,
         g.anzahl,
         g.gewicht_g::numeric / power(1 - l.r, l.alter_tage) * g.anzahl / 1000.0 as masse_kg
    from v_kaliber_lauf l
    join sortier_gewicht g on g.lauf_id = l.lauf_id
   where l.alter_tage is not null and l.alter_tage >= 0 and g.anzahl > 0 and g.gewicht_g > 0
), je as (
  select 'charge'::text as ebene, charge_nr::text as schluessel, g0, sum(masse_kg) as masse_kg, sum(anzahl)::bigint as n_kuerbis
    from kuerbis group by charge_nr, g0
  union all
  select 'sorte', sorte, g0, sum(masse_kg), sum(anzahl)::bigint
    from kuerbis group by sorte, g0
)
select ebene, schluessel, g0, masse_kg, n_kuerbis,
       sum(masse_kg) over (partition by ebene, schluessel order by g0)
         / sum(masse_kg) over (partition by ebene, schluessel) as anteil_bis
  from je
with no data;
create unique index if not exists mv_kaliber_eingang_pk on mv_kaliber_eingang (ebene, schluessel, g0);
comment on materialized view mv_kaliber_eingang is
  'Die Gewichtsverteilung beim Eingang (0116), je Charge (ebene charge) und je Sorte (ebene sorte) aus den Sortierläufen, jeder Kürbis um die Verdunstung seiner Sorte über das Alter beim Sortieren zurückgerechnet (v_kaliber_lauf). anteil_bis: Anteil der Masse bis und mit g0 Gramm. Erneuert mit auswertung_schritt() vor der Kaskade.';

-- 5d. Je Charge, woher ihre Verteilung kommt: aus ihren eigenen Läufen,
--     sonst aus denen ihrer Sorte — und die Grenzen der gültigen Fassung.
--     Ohne beides gilt weiter der gemessene Anteil der Sorte (Sortierläufe
--     und Handmessungen, v_koeff_ausschuss / v_koeff_nebenkanal).
create materialized view mv_kaliber_quelle as
with laeufe as (
  select charge_nr, count(*)::int as n
    from v_kaliber_lauf where alter_tage is not null and alter_tage >= 0 group by charge_nr
), je_sorte as (
  select sorte, count(*)::int as n, count(distinct charge_nr)::int as c
    from v_kaliber_lauf where alter_tage is not null and alter_tage >= 0 group by sorte
)
select b.charge_nr, b.sorte, f.lo, f.hi,
       case when lc.n > 0 then 'charge' else 'sorte' end                      as ebene,
       case when lc.n > 0 then b.charge_nr::text else b.sorte end              as schluessel,
       coalesce(lc.n, ls.n)                                                     as n_laeufe,
       case when lc.n > 0
            then format('Sortierdatei der Charge (%s %s), auf den Eingangstag zurückgerechnet',
                        lc.n, case when lc.n = 1 then 'Lauf' else 'Läufe' end)
            else format('Sortierdateien der Sorte (%s %s aus %s %s), auf den Eingangstag zurückgerechnet',
                        ls.n, case when ls.n = 1 then 'Lauf' else 'Läufe' end,
                        ls.c, case when ls.c = 1 then 'Charge' else 'Chargen' end) end as basis
  from v_kaskade_basis b
  join v_kaliber_fassung f on f.sorte = b.sorte
  left join laeufe lc on lc.charge_nr = b.charge_nr
  left join je_sorte ls on ls.sorte = b.sorte
 where coalesce(lc.n, 0) > 0 or coalesce(ls.n, 0) > 0
with no data;
create unique index if not exists mv_kaliber_quelle_pk on mv_kaliber_quelle (charge_nr);
comment on materialized view mv_kaliber_quelle is
  'Je Charge, woher zu klein und zu gross kommen (0116): aus der Verteilung beim Eingang ihrer eigenen Sortierläufe (ebene charge), sonst der ihrer Sorte (ebene sorte), mit den Grenzen lo/hi der gültigen Fassung. Fehlt eine Charge hier, gilt der gemessene Anteil der Sorte.';

-- 5e. Zu klein und zu gross bei einem Alter: die Verteilung beim Eingang,
--     jeder Kürbis um q = (1 − r)^Alter geschrumpft, gegen die Grenzen. Ein
--     Kürbis von g0 Gramm ist dann g0 · q schwer: zu klein, wenn g0 < lo / q,
--     zu gross, wenn g0 > hi / q. Leer, wo es keine Verteilung gibt — nie 0.
create or replace function kaliber_anteil(p_ebene text, p_schluessel text, p_lo numeric, p_hi numeric, p_q numeric)
returns table (klein numeric, gross numeric)
language sql stable set search_path = public as $$
  select case when p_ebene is null or p_lo is null or coalesce(p_q, 0) <= 0 then null
              else coalesce((select k.anteil_bis from mv_kaliber_eingang k
                              where k.ebene = p_ebene and k.schluessel = p_schluessel and k.g0 < p_lo / p_q
                              order by k.g0 desc limit 1), 0) end,
         case when p_ebene is null or p_hi is null or coalesce(p_q, 0) <= 0 then null
              else 1 - coalesce((select k.anteil_bis from mv_kaliber_eingang k
                                  where k.ebene = p_ebene and k.schluessel = p_schluessel and k.g0 <= p_hi / p_q
                                  order by k.g0 desc limit 1), 0) end
$$;
comment on function kaliber_anteil(text, text, numeric, numeric, numeric) is
  'Massenanteil zu klein (unter lo) und zu gross (über hi) einer Verteilung beim Eingang (mv_kaliber_eingang), jeder Kürbis um den Faktor q = (1 − r)^Alter geschrumpft (0116). Leer ohne Verteilung.';
revoke all on function kaliber_anteil(text, text, numeric, numeric, numeric) from public;
grant execute on function kaliber_anteil(text, text, numeric, numeric, numeric) to authenticated;

-- 5f. Der Hagel auf dem Palox-Anteil: f = 1 − (1 − f) · (1 − Hagel). Ohne
--     Hagel bleibt f; 100 % Hagel macht f = 1, auch wenn f selbst unbekannt
--     ist; sonst bleibt ein unbekanntes f unbekannt.
create or replace function hagel_f(p_f numeric, p_hagel numeric) returns numeric
language sql immutable as $$
  select case when coalesce(p_hagel, 0) <= 0 then p_f
              when p_hagel >= 1 then 1::numeric
              when p_f is null then null
              else 1 - (1 - least(greatest(p_f, 0), 1)) * (1 - p_hagel) end
$$;
comment on function hagel_f(numeric, numeric) is
  'Der Palox-Anteil mit Hagelschaden (0116): 1 − (1 − f) · (1 − Hagel). Ohne Hagel f; 100 % Hagel 1.';
revoke all on function hagel_f(numeric, numeric) from public;
grant execute on function hagel_f(numeric, numeric) to authenticated;

-- =====================================================================
-- 6. Die Kaskade — zu klein / zu gross je Alter aus der Sortierdatei, Hagel
-- =====================================================================
-- Die Formeln sind abgedruckt, wie PostgreSQL sie nach 0115 hält
-- (pg_get_viewdef), in der Reihenfolge der Abhängigkeit. Geändert sind:
--   mv_kaskade — je Portion zu klein und zu gross beim Alter der Portion aus
--     der Verteilung beim Eingang (kaliber_anteil, sonst wie bisher der
--     Anteil der Sorte); der Hagel auf dem Palox-Anteil (hagel_f) für alles,
--     was liegt, und für Ausgelagertes ohne eigene Messung; zwei neue
--     Spalten hagel (der angewandte Hagel) und f_eigen (die Portion hat eine
--     eigene Messung der Charge).
--   v_prognose — zu klein und zu gross beim Alter am Horizont; der Hagel auf
--     dem fortgeschriebenen Palox-Anteil; was beim Eintrocknen über die
--     Kalibergrenze geht, zählt zum Verlust durch Wasser (die Zerlegung
--     Wasser + Fäulnis = Verlust an verkaufsfähiger Ware bleibt genau).
--   erg_verlauf — zu klein und zu gross beim Alter am Wochenende für das,
--     was noch liegt; der Hagel wie in der Prognose.
--   v_plausibilitaet_0064_zusatz und v_plausibilitaet — die Zettelgewicht-
--     Auffälligkeiten sagen, welche Regel gerechnet hat (Wägung, Kisten und
--     ihre Tara, Tara je Kiste der Charge, mittlere Tara), statt immer „die
--     mittlere Tara der Charge".
drop materialized view if exists mv_kaskade cascade;

-- ---------- mv_kaskade ----------
create materialized view mv_kaskade as
 WITH kohorten AS MATERIALIZED (
         SELECT k.charge_nr,
            k.eingangsdatum,
            k.anteil,
            b.eingang_kg * k.anteil AS eingang_kg
           FROM v_kohorte_anteil k
             JOIN v_kaskade_basis b ON b.charge_nr = k.charge_nr
        ), lieferungen AS MATERIALIZED (
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            sum(v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, 0::numeric)) / NULLIF(sum(v_lieferung_kohorte.masse_kg), 0::numeric) AS alter_tage,
            sum(v_lieferung_kohorte.n_lieferungen)::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE v_lieferung_kohorte.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), entsorgt_lief AS (
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            sum(v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, 0::numeric)) / NULLIF(sum(v_lieferung_kohorte.masse_kg), 0::numeric) AS alter_tage,
            sum(v_lieferung_kohorte.n_lieferungen)::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE v_lieferung_kohorte.buch = 'verlust'::text
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), koeff AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.eingang_kg,
            b.stichtag,
            LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            kv.mittel IS NOT NULL AS r_bekannt,
            kv.n AS r_n,
            kv.basis AS r_basis,
            LEAST(GREATEST(COALESCE(ka.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_klein,
            ka.mittel IS NOT NULL AS a_klein_bekannt,
            ka.n AS klein_n,
            ka.basis AS klein_basis,
            LEAST(GREATEST(COALESCE(kn.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_gross,
            kn.mittel IS NOT NULL AS a_gross_bekannt,
            kn.n AS gross_n,
            kn.basis AS gross_basis,
            LEAST(GREATEST(COALESCE(kf.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_fax,
            kf.mittel IS NOT NULL AS a_fax_bekannt,
            kf.n AS fax_n,
            kf.basis AS fax_basis
           FROM v_kaskade_basis b
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b.sorte
             LEFT JOIN v_koeff_ausschuss ka ON ka.sorte = b.sorte
             LEFT JOIN v_koeff_nebenkanal kn ON kn.sorte = b.sorte
             LEFT JOIN v_koeff_fax kf ON kf.sorte = b.sorte
          WHERE b.eingang_kg > 0::numeric
        ), koeff_norm AS (
         SELECT k.charge_nr,
            k.sorte,
            k.schlag,
            k.eingang_kg,
            k.stichtag,
            k.r,
            k.r_bekannt,
            k.r_n,
            k.r_basis,
            k.a_klein,
            k.a_klein_bekannt,
            k.klein_n,
            k.klein_basis,
            k.a_gross,
            k.a_gross_bekannt,
            k.gross_n,
            k.gross_basis,
            k.a_fax,
            k.a_fax_bekannt,
            k.fax_n,
            k.fax_basis,
            k.a_klein / n.f AS a_klein_n,
            k.a_gross / n.f AS a_gross_n
           FROM koeff k
             CROSS JOIN LATERAL ( SELECT GREATEST(COALESCE(k.a_klein, 0::numeric) + COALESCE(k.a_gross, 0::numeric), 1::numeric) AS f) n
        ), weg AS MATERIALIZED (
         SELECT v_charge_weg.charge_nr,
            v_charge_weg.p_hand,
            v_charge_weg.p_wasch,
            v_charge_weg.weg_quelle
           FROM v_charge_weg
        ), erwartung AS MATERIALIZED (
         SELECT v_palox_erwartung.sorte,
            v_palox_erwartung.station,
            v_palox_erwartung.anteil,
            v_palox_erwartung.unten,
            v_palox_erwartung.oben,
            v_palox_erwartung.n_arbeiten,
            v_palox_erwartung.geliehen,
            v_palox_erwartung.quelle
           FROM v_palox_erwartung
        ), eigen AS MATERIALIZED (
         SELECT v_charge_palox.charge_nr,
            v_charge_palox.station,
            v_charge_palox.anteil,
            v_charge_palox.n_arbeiten
           FROM v_charge_palox
        ), zuwachs AS MATERIALIZED (
         SELECT v_palox_station.station,
            v_palox_station.zuwachs_je_woche
           FROM v_palox_station
        ), je_station AS MATERIALIZED (
         SELECT k.charge_nr,
            p.portion,
            st.station,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.anteil
                    ELSE er.anteil
                END AS f,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.anteil
                    ELSE er.unten
                END AS unten,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.anteil
                    ELSE er.oben
                END AS oben,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.n_arbeiten
                    ELSE er.n_arbeiten
                END AS n,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN false
                    ELSE COALESCE(er.geliehen, false)
                END AS geliehen,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN format('eigene Messung (%s Arbeiten)'::text, ei.n_arbeiten)
                    ELSE er.quelle
                END AS quelle,
            p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL AS eigen
           FROM koeff k
             CROSS JOIN ( VALUES ('ausgelagert'::text), ('lager'::text)) p(portion)
             CROSS JOIN ( VALUES ('waschen_sortieren'::text), ('sortieren'::text), ('waschen'::text)) st(station)
             LEFT JOIN erwartung er ON er.sorte = k.sorte AND er.station = st.station
             LEFT JOIN eigen ei ON ei.charge_nr = k.charge_nr AND ei.station = st.station
        ), roh AS (
         SELECT k.charge_nr,
            'ausgelagert'::text AS portion,
            l.kohorte,
            l.masse_kg AS geliefert_kg,
            COALESCE(l.alter_tage, 0::numeric) AS alter_tage,
            NULL::numeric AS eingang_kohorte_kg,
            l.n_lieferungen
           FROM koeff_norm k
             JOIN lieferungen l ON l.charge_nr = k.charge_nr
        UNION ALL
         SELECT k.charge_nr,
            'entsorgt'::text AS text,
            e.kohorte,
            e.masse_kg,
            COALESCE(e.alter_tage, 0::numeric) AS "coalesce",
            NULL::numeric AS "numeric",
            e.n_lieferungen
           FROM koeff_norm k
             JOIN entsorgt_lief e ON e.charge_nr = k.charge_nr
        UNION ALL
         SELECT k.charge_nr,
            'lager'::text AS text,
            c.eingangsdatum,
            NULL::numeric AS "numeric",
            GREATEST((k.stichtag - c.eingangsdatum)::numeric, 0::numeric) AS "greatest",
            c.eingang_kg,
            0
           FROM koeff_norm k
             JOIN kohorten c ON c.charge_nr = k.charge_nr
        ), kal AS MATERIALIZED (
         SELECT q.charge_nr, q.ebene, q.schluessel, q.lo, q.hi, q.n_laeufe, q.basis
           FROM mv_kaliber_quelle q
        ), hagel AS MATERIALIZED (
         SELECT c.nr AS charge_nr, c.hagel_anteil AS h
           FROM charge c
          WHERE c.hagel_anteil > 0::numeric
        ), teile AS (
         SELECT k.charge_nr,
            k.sorte,
            k.schlag,
            k.eingang_kg,
            k.stichtag,
            k.r,
            k.r_bekannt,
            k.r_n,
            k.r_basis,
            k.a_klein,
            k.a_klein_bekannt OR ka.klein IS NOT NULL AS a_klein_bekannt,
            COALESCE(kq.n_laeufe, k.klein_n) AS klein_n,
            COALESCE(kq.basis, k.klein_basis) AS klein_basis,
            k.a_gross,
            k.a_gross_bekannt OR ka.gross IS NOT NULL AS a_gross_bekannt,
            COALESCE(kq.n_laeufe, k.gross_n) AS gross_n,
            COALESCE(kq.basis, k.gross_basis) AS gross_basis,
            k.a_fax,
            k.a_fax_bekannt,
            k.fax_n,
            k.fax_basis,
            COALESCE(ka.klein, k.a_klein_n) AS a_klein_n,
            COALESCE(ka.gross, k.a_gross_n) AS a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            hh.h AS hagel,
            COALESCE(ws.eigen, false) OR COALESCE(s.eigen, false) OR COALESCE(wa.eigen, false) AS f_eigen,
            w.p_hand,
            w.p_wasch,
            w.weg_quelle,
            nach.f_ws,
            nach.f_s,
            nach.g_w,
            hagel_f(palox_f(w.p_hand, w.p_wasch, nach.f_ws, nach.f_s, nach.g_w), hh.h) AS f_roh,
            hagel_f(palox_f_nach(w.p_hand, w.p_wasch, ws.unten, s.unten, wa.unten, b.b_ws, b.b_s, b.b_w, t.alter_tage), hh.h) AS f_unten_roh,
            hagel_f(palox_f_nach(w.p_hand, w.p_wasch, ws.oben, s.oben, wa.oben, b.b_ws, b.b_s, b.b_w, t.alter_tage), hh.h) AS f_oben_roh,
            LEAST(
                CASE
                    WHEN w.p_hand > 0::numeric THEN ws.n
                    ELSE NULL::integer
                END,
                CASE
                    WHEN w.p_hand < 1::numeric THEN s.n
                    ELSE NULL::integer
                END,
                CASE
                    WHEN w.p_hand < 1::numeric AND w.p_wasch > 0::numeric THEN wa.n
                    ELSE NULL::integer
                END) AS f_n,
            COALESCE(
                CASE
                    WHEN w.p_hand > 0::numeric THEN ws.geliehen
                    ELSE NULL::boolean
                END, false) OR COALESCE(
                CASE
                    WHEN w.p_hand < 1::numeric THEN s.geliehen
                    ELSE NULL::boolean
                END, false) OR COALESCE(
                CASE
                    WHEN w.p_hand < 1::numeric AND w.p_wasch > 0::numeric THEN wa.geliehen
                    ELSE NULL::boolean
                END, false) AS f_geliehen,
            concat_ws('; '::text,
                CASE
                    WHEN w.p_hand > 0::numeric THEN 'Waschen + Sortieren: '::text || COALESCE(ws.quelle, 'kein Wert'::text)
                    ELSE NULL::text
                END,
                CASE
                    WHEN w.p_hand < 1::numeric THEN 'Sortieren: '::text || COALESCE(s.quelle, 'kein Wert'::text)
                    ELSE NULL::text
                END,
                CASE
                    WHEN w.p_hand < 1::numeric AND w.p_wasch > 0::numeric THEN 'Waschen: '::text || COALESCE(wa.quelle, 'kein Wert'::text)
                    ELSE NULL::text
                END,
                CASE
                    WHEN w.weg_quelle IS NOT NULL THEN 'Weg nach '::text || w.weg_quelle
                    ELSE NULL::text
                END,
                CASE
                    WHEN hh.h > 0::numeric THEN format('Hagelschaden %s %%'::text, round(hh.h * 100::numeric))
                    ELSE NULL::text
                END) AS f_quelle,
            b.b_ws,
            b.b_s,
            b.b_w,
            (w.p_hand = 0::numeric OR b.b_ws IS NOT NULL) AND (w.p_hand = 1::numeric OR b.b_s IS NOT NULL) AND (w.p_hand = 1::numeric OR COALESCE(w.p_wasch, 0::numeric) = 0::numeric OR b.b_w IS NOT NULL) AS zuwachs_roh
           FROM koeff_norm k
             JOIN roh t ON t.charge_nr = k.charge_nr
             LEFT JOIN weg w ON w.charge_nr = k.charge_nr
             LEFT JOIN je_station ws ON ws.charge_nr = k.charge_nr AND ws.station = 'waschen_sortieren'::text AND ws.portion =
                CASE
                    WHEN t.portion = 'lager'::text THEN 'lager'::text
                    ELSE 'ausgelagert'::text
                END
             LEFT JOIN je_station s ON s.charge_nr = k.charge_nr AND s.station = 'sortieren'::text AND s.portion =
                CASE
                    WHEN t.portion = 'lager'::text THEN 'lager'::text
                    ELSE 'ausgelagert'::text
                END
             LEFT JOIN je_station wa ON wa.charge_nr = k.charge_nr AND wa.station = 'waschen'::text AND wa.portion =
                CASE
                    WHEN t.portion = 'lager'::text THEN 'lager'::text
                    ELSE 'ausgelagert'::text
                END
             LEFT JOIN zuwachs zws ON zws.station = 'waschen_sortieren'::text
             LEFT JOIN zuwachs zs ON zs.station = 'sortieren'::text
             LEFT JOIN zuwachs zw ON zw.station = 'waschen'::text
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN ws.eigen THEN 0::numeric
                            ELSE zws.zuwachs_je_woche
                        END AS b_ws,
                        CASE
                            WHEN s.eigen THEN 0::numeric
                            ELSE zs.zuwachs_je_woche
                        END AS b_s,
                        CASE
                            WHEN wa.eigen THEN 0::numeric
                            ELSE zw.zuwachs_je_woche
                        END AS b_w) b
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN ws.f IS NULL THEN NULL::numeric
                            ELSE LEAST(GREATEST(ws.f + COALESCE(b.b_ws, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric)
                        END AS f_ws,
                        CASE
                            WHEN s.f IS NULL THEN NULL::numeric
                            ELSE LEAST(GREATEST(s.f + COALESCE(b.b_s, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric)
                        END AS f_s,
                        CASE
                            WHEN wa.f IS NULL THEN NULL::numeric
                            ELSE LEAST(GREATEST(wa.f + COALESCE(b.b_w, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric)
                        END AS g_w) nach
             LEFT JOIN kal kq ON kq.charge_nr = k.charge_nr
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - k.r, t.alter_tage)) ka ON true
             LEFT JOIN hagel hg ON hg.charge_nr = k.charge_nr
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN hg.h IS NULL OR t.portion = 'entsorgt'::text THEN 0::numeric
                            WHEN t.portion = 'lager'::text THEN hg.h
                            WHEN COALESCE(ws.eigen, false) OR COALESCE(s.eigen, false) OR COALESCE(wa.eigen, false) THEN 0::numeric
                            ELSE hg.h
                        END AS h) hh
        ), mit_f AS (
         SELECT t.charge_nr,
            t.sorte,
            t.schlag,
            t.eingang_kg,
            t.stichtag,
            t.r,
            t.r_bekannt,
            t.r_n,
            t.r_basis,
            t.a_klein,
            t.a_klein_bekannt,
            t.klein_n,
            t.klein_basis,
            t.a_gross,
            t.a_gross_bekannt,
            t.gross_n,
            t.gross_basis,
            t.a_fax,
            t.a_fax_bekannt,
            t.fax_n,
            t.fax_basis,
            t.a_klein_n,
            t.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            t.hagel,
            t.f_eigen,
            t.p_hand,
            t.p_wasch,
            t.weg_quelle,
            t.f_ws,
            t.f_s,
            t.g_w,
            t.f_roh,
            t.f_unten_roh,
            t.f_oben_roh,
            t.f_n,
            t.f_geliehen,
            t.f_quelle,
            t.b_ws,
            t.b_s,
            t.b_w,
            t.zuwachs_roh,
            t.f_roh IS NOT NULL AS f_bekannt,
            COALESCE(t.f_roh, 0::numeric) AS f,
            COALESCE(t.f_unten_roh, t.f_roh, 0::numeric) AS f_unten,
            COALESCE(t.f_oben_roh, t.f_roh, 0::numeric) AS f_oben,
                CASE
                    WHEN t.f_roh IS NULL OR t.f_n IS NULL OR t.f_n < 2 THEN 0::numeric
                    ELSE (COALESCE(t.f_oben_roh, t.f_roh) - COALESCE(t.f_unten_roh, t.f_roh)) / (2::numeric * t_quantil_95(t.f_n - 1))
                END AS f_se,
            t.f_roh IS NOT NULL AND COALESCE(t.zuwachs_roh, false) AS zuwachs_bekannt
           FROM teile t
        ), anteil AS (
         SELECT x.charge_nr,
            x.sorte,
            x.schlag,
            x.eingang_kg,
            x.stichtag,
            x.r,
            x.r_bekannt,
            x.r_n,
            x.r_basis,
            x.a_klein,
            x.a_klein_bekannt,
            x.klein_n,
            x.klein_basis,
            x.a_gross,
            x.a_gross_bekannt,
            x.gross_n,
            x.gross_basis,
            x.a_fax,
            x.a_fax_bekannt,
            x.fax_n,
            x.fax_basis,
            x.a_klein_n,
            x.a_gross_n,
            x.portion,
            x.kohorte,
            x.geliefert_kg,
            x.alter_tage,
            x.eingang_kohorte_kg,
            x.n_lieferungen,
            x.hagel,
            x.f_eigen,
            x.p_hand,
            x.p_wasch,
            x.weg_quelle,
            x.f_ws,
            x.f_s,
            x.g_w,
            x.f_roh,
            x.f_unten_roh,
            x.f_oben_roh,
            x.f_n,
            x.f_geliehen,
            x.f_quelle,
            x.b_ws,
            x.b_s,
            x.b_w,
            x.zuwachs_roh,
            x.f_bekannt,
            x.f,
            x.f_unten,
            x.f_oben,
            x.f_se,
            x.zuwachs_bekannt,
            GREATEST(power(1::numeric - x.r, x.alter_tage) * (1::numeric - x.f) * (1::numeric - x.a_klein_n - x.a_gross_n) * (1::numeric - x.a_fax), 0.25) AS verkaufsfaehig_anteil,
            GREATEST(power(1::numeric - x.r, x.alter_tage), 0.25) AS verdunstungs_anteil
           FROM mit_f x
        ), ausgelagert AS (
         SELECT a.charge_nr,
            a.sorte,
            a.schlag,
            a.eingang_kg,
            a.stichtag,
            a.r,
            a.r_bekannt,
            a.r_n,
            a.r_basis,
            a.a_klein,
            a.a_klein_bekannt,
            a.klein_n,
            a.klein_basis,
            a.a_gross,
            a.a_gross_bekannt,
            a.gross_n,
            a.gross_basis,
            a.a_fax,
            a.a_fax_bekannt,
            a.fax_n,
            a.fax_basis,
            a.a_klein_n,
            a.a_gross_n,
            a.portion,
            a.kohorte,
            a.geliefert_kg,
            a.alter_tage,
            a.eingang_kohorte_kg,
            a.n_lieferungen,
            a.hagel,
            a.f_eigen,
            a.p_hand,
            a.p_wasch,
            a.weg_quelle,
            a.f_ws,
            a.f_s,
            a.g_w,
            a.f_roh,
            a.f_unten_roh,
            a.f_oben_roh,
            a.f_n,
            a.f_geliehen,
            a.f_quelle,
            a.b_ws,
            a.b_s,
            a.b_w,
            a.zuwachs_roh,
            a.f_bekannt,
            a.f,
            a.f_unten,
            a.f_oben,
            a.f_se,
            a.zuwachs_bekannt,
            a.verkaufsfaehig_anteil,
            a.verdunstungs_anteil,
                CASE
                    WHEN a.portion = 'entsorgt'::text THEN a.geliefert_kg / a.verdunstungs_anteil
                    ELSE a.geliefert_kg / a.verkaufsfaehig_anteil
                END AS m0,
            0::numeric AS ueberzaehlung_kg
           FROM anteil a
          WHERE a.portion = ANY (ARRAY['ausgelagert'::text, 'entsorgt'::text])
        ), lager AS (
         SELECT a.charge_nr,
            a.sorte,
            a.schlag,
            a.eingang_kg,
            a.stichtag,
            a.r,
            a.r_bekannt,
            a.r_n,
            a.r_basis,
            a.a_klein,
            a.a_klein_bekannt,
            a.klein_n,
            a.klein_basis,
            a.a_gross,
            a.a_gross_bekannt,
            a.gross_n,
            a.gross_basis,
            a.a_fax,
            a.a_fax_bekannt,
            a.fax_n,
            a.fax_basis,
            a.a_klein_n,
            a.a_gross_n,
            a.portion,
            a.kohorte,
            a.geliefert_kg,
            a.alter_tage,
            a.eingang_kohorte_kg,
            a.n_lieferungen,
            a.hagel,
            a.f_eigen,
            a.p_hand,
            a.p_wasch,
            a.weg_quelle,
            a.f_ws,
            a.f_s,
            a.g_w,
            a.f_roh,
            a.f_unten_roh,
            a.f_oben_roh,
            a.f_n,
            a.f_geliehen,
            a.f_quelle,
            a.b_ws,
            a.b_s,
            a.b_w,
            a.zuwachs_roh,
            a.f_bekannt,
            a.f,
            a.f_unten,
            a.f_oben,
            a.f_se,
            a.zuwachs_bekannt,
            a.verkaufsfaehig_anteil,
            a.verdunstungs_anteil,
            GREATEST(a.eingang_kohorte_kg - COALESCE(x.m0, 0::numeric), 0::numeric) AS m0,
            GREATEST(COALESCE(x.m0, 0::numeric) - a.eingang_kohorte_kg, 0::numeric) AS ueberzaehlung_kg
           FROM anteil a
             LEFT JOIN ( SELECT ausgelagert.charge_nr,
                    ausgelagert.kohorte,
                    sum(ausgelagert.m0) AS m0
                   FROM ausgelagert
                  GROUP BY ausgelagert.charge_nr, ausgelagert.kohorte) x ON x.charge_nr = a.charge_nr AND x.kohorte = a.kohorte
          WHERE a.portion = 'lager'::text
        ), alle AS (
         SELECT ausgelagert.charge_nr,
            ausgelagert.sorte,
            ausgelagert.schlag,
            ausgelagert.eingang_kg,
            ausgelagert.stichtag,
            ausgelagert.r,
            ausgelagert.r_bekannt,
            ausgelagert.r_n,
            ausgelagert.r_basis,
            ausgelagert.a_klein,
            ausgelagert.a_klein_bekannt,
            ausgelagert.klein_n,
            ausgelagert.klein_basis,
            ausgelagert.a_gross,
            ausgelagert.a_gross_bekannt,
            ausgelagert.gross_n,
            ausgelagert.gross_basis,
            ausgelagert.a_fax,
            ausgelagert.a_fax_bekannt,
            ausgelagert.fax_n,
            ausgelagert.fax_basis,
            ausgelagert.a_klein_n,
            ausgelagert.a_gross_n,
            ausgelagert.portion,
            ausgelagert.kohorte,
            ausgelagert.geliefert_kg,
            ausgelagert.alter_tage,
            ausgelagert.eingang_kohorte_kg,
            ausgelagert.n_lieferungen,
            ausgelagert.hagel,
            ausgelagert.f_eigen,
            ausgelagert.p_hand,
            ausgelagert.p_wasch,
            ausgelagert.weg_quelle,
            ausgelagert.f_ws,
            ausgelagert.f_s,
            ausgelagert.g_w,
            ausgelagert.f_roh,
            ausgelagert.f_unten_roh,
            ausgelagert.f_oben_roh,
            ausgelagert.f_n,
            ausgelagert.f_geliehen,
            ausgelagert.f_quelle,
            ausgelagert.b_ws,
            ausgelagert.b_s,
            ausgelagert.b_w,
            ausgelagert.zuwachs_roh,
            ausgelagert.f_bekannt,
            ausgelagert.f,
            ausgelagert.f_unten,
            ausgelagert.f_oben,
            ausgelagert.f_se,
            ausgelagert.zuwachs_bekannt,
            ausgelagert.verkaufsfaehig_anteil,
            ausgelagert.verdunstungs_anteil,
            ausgelagert.m0,
            ausgelagert.ueberzaehlung_kg
           FROM ausgelagert
        UNION ALL
         SELECT lager.charge_nr,
            lager.sorte,
            lager.schlag,
            lager.eingang_kg,
            lager.stichtag,
            lager.r,
            lager.r_bekannt,
            lager.r_n,
            lager.r_basis,
            lager.a_klein,
            lager.a_klein_bekannt,
            lager.klein_n,
            lager.klein_basis,
            lager.a_gross,
            lager.a_gross_bekannt,
            lager.gross_n,
            lager.gross_basis,
            lager.a_fax,
            lager.a_fax_bekannt,
            lager.fax_n,
            lager.fax_basis,
            lager.a_klein_n,
            lager.a_gross_n,
            lager.portion,
            lager.kohorte,
            lager.geliefert_kg,
            lager.alter_tage,
            lager.eingang_kohorte_kg,
            lager.n_lieferungen,
            lager.hagel,
            lager.f_eigen,
            lager.p_hand,
            lager.p_wasch,
            lager.weg_quelle,
            lager.f_ws,
            lager.f_s,
            lager.g_w,
            lager.f_roh,
            lager.f_unten_roh,
            lager.f_oben_roh,
            lager.f_n,
            lager.f_geliehen,
            lager.f_quelle,
            lager.b_ws,
            lager.b_s,
            lager.b_w,
            lager.zuwachs_roh,
            lager.f_bekannt,
            lager.f,
            lager.f_unten,
            lager.f_oben,
            lager.f_se,
            lager.zuwachs_bekannt,
            lager.verkaufsfaehig_anteil,
            lager.verdunstungs_anteil,
            lager.m0,
            lager.ueberzaehlung_kg
           FROM lager
        ), kaskade AS (
         SELECT t.charge_nr,
            t.sorte,
            t.schlag,
            t.eingang_kg,
            t.stichtag,
            t.r,
            t.r_bekannt,
            t.r_n,
            t.r_basis,
            t.a_klein,
            t.a_klein_bekannt,
            t.klein_n,
            t.klein_basis,
            t.a_gross,
            t.a_gross_bekannt,
            t.gross_n,
            t.gross_basis,
            t.a_fax,
            t.a_fax_bekannt,
            t.fax_n,
            t.fax_basis,
            t.a_klein_n,
            t.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            t.hagel,
            t.f_eigen,
            t.p_hand,
            t.p_wasch,
            t.weg_quelle,
            t.f_ws,
            t.f_s,
            t.g_w,
            t.f_roh,
            t.f_unten_roh,
            t.f_oben_roh,
            t.f_n,
            t.f_geliehen,
            t.f_quelle,
            t.b_ws,
            t.b_s,
            t.b_w,
            t.zuwachs_roh,
            t.f_bekannt,
            t.f,
            t.f_unten,
            t.f_oben,
            t.f_se,
            t.zuwachs_bekannt,
            t.verkaufsfaehig_anteil,
            t.verdunstungs_anteil,
            t.m0,
            t.ueberzaehlung_kg,
            t.m0 * power(1::numeric - t.r, t.alter_tage) AS m1,
            (- t.m0) * t.alter_tage * power(1::numeric - t.r, GREATEST(t.alter_tage - 1::numeric, 0::numeric)) AS d_m1_r
           FROM alle t
          WHERE t.m0 > 0::numeric OR t.ueberzaehlung_kg > 0::numeric
        )
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    m0,
    m1,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f)
        END AS m2,
    r,
    f,
    f_unten,
    f_oben,
    f_se,
    f_ws,
    f_s,
    g_w,
    p_hand,
    p_wasch,
    f_quelle,
    f_geliehen,
    b_ws,
    b_s,
    b_w,
    zuwachs_bekannt,
    a_klein_n,
    a_gross_n,
    a_fax,
    d_m1_r,
    r_n,
    r_basis,
    klein_n,
    klein_basis,
    gross_n,
    gross_basis,
    f_n,
    fax_n,
    fax_basis,
    r_bekannt,
    f_bekannt,
    a_klein_bekannt,
    a_gross_bekannt,
    a_fax_bekannt,
    m0 - m1 AS verdunstung_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN m1
            ELSE m1 * f
        END AS schimmel_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * a_klein_n
        END AS klein_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * a_gross_n
        END AS nebenkanal_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * (1::numeric - a_klein_n - a_gross_n) * a_fax
        END AS fax_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * (1::numeric - a_klein_n - a_gross_n) * (1::numeric - a_fax)
        END AS verkaufsfaehig_kg,
    kohorte,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE geliefert_kg
        END AS geliefert_kg,
    ueberzaehlung_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0
            ELSE n_lieferungen
        END AS n_lieferungen,
    verkaufsfaehig_anteil,
    hagel,
    f_eigen
   FROM kaskade
with no data;
create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, portion, COALESCE(kohorte, '1900-01-01'::date));
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);
comment on materialized view mv_kaskade is
  'Die Massenkaskade je Charge, Eingangstag und Portion. Drei Portionen: „ausgelagert" ist die Eingangsmasse hinter den verkauften und in den Nebenkanal gegangenen Lieferungen, „entsorgt" die hinter dem Kompost (0065 — nur um die Verdunstung zurückgerechnet, weil entsorgte Ware selbst das Faule ist), „lager" der Rest, der noch liegt. Je Portion die Ströme Verdunstung, Palox-Ausschuss, zu klein, zu gross, Fax und verkaufsfähig. f ist der Palox-Anteil über den Weg der Charge (palox_f: p_hand, p_wasch, f_ws, f_s, g_w). Seit 0111 gilt jeder Stationswert für das Alter der Portion: Grundausschuss der Sorte (v_palox_erwartung) + Anstieg der Station je Woche Lagerdauer (v_palox_station) × alter_tage / 7; für Ausgelagertes mit eigener Messung gilt diese, ohne Anstieg. f_quelle sagt, woher; f_geliehen: aus allen Sorten. b_ws/b_s/b_w ist der Anstieg, mit dem Prognose und Verlauf fortschreiben (0 bei eigener Messung), zuwachs_bekannt sagt, ob sie es dürfen.';
grant select on mv_kaskade to authenticated;


-- ---------- erg_verlauf ----------
create materialized view erg_verlauf as
 WITH tag AS MATERIALIZED (
         SELECT heute() AS heute,
            stichtag() AS stichtag
        ), wochen AS MATERIALIZED (
         SELECT w_1.w::date AS woche,
            (w_1.w + '6 days'::interval)::date AS bis
           FROM tag t,
            LATERAL generate_series(date_trunc('week'::text, COALESCE(( SELECT min(palette.eingangsdatum) AS min
                   FROM palette), t.heute)::timestamp with time zone)::date::timestamp with time zone, date_trunc('week'::text, GREATEST(t.stichtag, t.heute + 84)::timestamp with time zone)::date::timestamp with time zone, '7 days'::interval) w_1(w)
        UNION
         SELECT date_trunc('week'::text, t.heute::timestamp with time zone)::date AS date_trunc,
            t.heute
           FROM tag t
        ), gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text AS text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text AS text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text AS text,
            v_kaskade_basis.charge_nr::text AS charge_nr,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        ), portionen AS MATERIALIZED (
         SELECT k.charge_nr,
            k.portion,
            k.kohorte,
            k.m0,
            k.r,
            k.f,
            k.f_ws,
            k.f_s,
            k.g_w,
            k.p_hand,
            k.p_wasch,
            k.b_ws,
            k.b_s,
            k.b_w,
            k.zuwachs_bekannt,
            k.a_klein_n,
            k.a_gross_n,
            k.a_fax,
            k.hagel,
            k.alter_tage,
                CASE
                    WHEN k.portion = 'ausgelagert'::text THEN k.kohorte + round(k.alter_tage)::integer
                    ELSE NULL::date
                END AS liefertag,
                CASE
                    WHEN k.portion = 'ausgelagert'::text THEN k.fax_kg
                    ELSE 0::numeric
                END AS fax_kg
           FROM mv_kaskade k
          WHERE k.m0 > 0::numeric AND k.kohorte IS NOT NULL
        ), lieferanteil AS MATERIALIZED (
         SELECT w_1.bis,
            l.charge_nr,
            sum(l.masse_kg) FILTER (WHERE l.datum <= w_1.bis) / NULLIF(sum(l.masse_kg), 0::numeric) AS q
           FROM wochen w_1
             CROSS JOIN v_lieferung_charge_tag l
          WHERE l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])
          GROUP BY w_1.bis, l.charge_nr
        ), je_woche AS (
         SELECT w_1.woche,
            w_1.bis,
            p.charge_nr,
            q.q * (p.m0 - n.d) + (1::numeric - q.q) * (p.m0 - n.u) AS verdunstung_kg,
            q.q * n.d * f.d + (1::numeric - q.q) * n.u * f.u AS schimmel_kg,
            q.q * p.fax_kg AS fax_kg,
            (1::numeric - q.q) * p.m0 AS lager_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) AS gute_ware_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * ku.kn AS kanal_lager_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * (1::numeric - ku.kn) * p.a_fax AS fax_lager_kg,
            q.q * n.d * (1::numeric - f.d) * (p.a_klein_n + p.a_gross_n) AS aussortiert_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * (1::numeric - ku.kn) * (1::numeric - p.a_fax) AS verkaufsfaehig_kg
           FROM wochen w_1
             JOIN portionen p ON p.kohorte <= w_1.bis
             CROSS JOIN tag d_1
             LEFT JOIN lieferanteil la ON la.bis = w_1.bis AND la.charge_nr = p.charge_nr
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.liefertag IS NULL THEN 0::numeric
                            ELSE LEAST(GREATEST(COALESCE(la.q,
                            CASE
                                WHEN p.liefertag <= w_1.bis THEN 1::numeric
                                ELSE 0::numeric
                            END), 0::numeric), 1::numeric)
                        END AS q) q
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.liefertag IS NULL THEN GREATEST(w_1.bis - p.kohorte, 0)::numeric
                            ELSE LEAST(GREATEST(w_1.bis - p.kohorte, 0)::numeric, p.alter_tage)
                        END AS u) t
             CROSS JOIN LATERAL ( SELECT p.m0 * power(1::numeric - p.r, COALESCE(p.alter_tage, 0::numeric)) AS d,
                    p.m0 * power(1::numeric - p.r, t.u) AS u) n
             LEFT JOIN mv_kaliber_quelle kq ON kq.charge_nr = p.charge_nr
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - p.r, t.u)) kl ON true
             CROSS JOIN LATERAL ( SELECT COALESCE(kl.klein + kl.gross, p.a_klein_n + p.a_gross_n) AS kn) ku
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(p.p_hand, p.p_wasch, p.f_ws, p.f_s, p.g_w, p.b_ws, p.b_s, p.b_w, 0::numeric), p.hagel), p.f)
                            ELSE p.f
                        END AS d,
                        CASE
                            WHEN p.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(p.p_hand, p.p_wasch, p.f_ws, p.f_s, p.g_w, p.b_ws, p.b_s, p.b_w, (LEAST(w_1.bis, COALESCE(p.liefertag, w_1.bis)) - COALESCE(p.liefertag, d_1.heute))::numeric), p.hagel), p.f)
                            ELSE p.f
                        END AS u) f
        ), je_charge AS MATERIALIZED (
         SELECT je_woche.woche,
            je_woche.bis,
            je_woche.charge_nr,
            sum(je_woche.verdunstung_kg) AS verdunstung_kg,
            sum(je_woche.schimmel_kg) AS schimmel_kg,
            sum(je_woche.fax_kg) AS fax_kg,
            sum(je_woche.gute_ware_kg) AS im_haus_kg,
            sum(je_woche.lager_kg) AS lager_kg,
            sum(je_woche.kanal_lager_kg) AS kanal_kg,
            sum(je_woche.fax_lager_kg) AS fax_lager_kg,
            sum(je_woche.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(je_woche.aussortiert_kg) AS aussortiert_kg
           FROM je_woche
          GROUP BY je_woche.woche, je_woche.bis, je_woche.charge_nr
        ), verlust AS (
         SELECT j.woche,
            j.bis,
            g.gruppe,
            g.schluessel,
            sum(j.verdunstung_kg) AS verdunstung_kg,
            sum(j.schimmel_kg) AS schimmel_kg,
            sum(j.fax_kg) AS fax_kg,
            sum(j.im_haus_kg) AS im_haus_kg,
            sum(j.lager_kg) AS lager_kg,
            sum(j.kanal_kg) AS kanal_kg,
            sum(j.fax_lager_kg) AS fax_lager_kg,
            sum(j.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(j.aussortiert_kg) AS aussortiert_kg
           FROM je_charge j
             JOIN gruppen g ON g.charge_nr = j.charge_nr
          GROUP BY j.woche, j.bis, g.gruppe, g.schluessel
        ), eingang_charge AS MATERIALIZED (
         SELECT w_1.woche,
            w_1.bis,
            k.charge_nr,
            sum(k.eingang_kg) AS kg
           FROM wochen w_1
             JOIN v_charge_kohorte k ON k.eingangsdatum <= w_1.bis
          GROUP BY w_1.woche, w_1.bis, k.charge_nr
        ), eingang AS (
         SELECT e_1.woche,
            e_1.bis,
            g.gruppe,
            g.schluessel,
            sum(e_1.kg) AS kg
           FROM eingang_charge e_1
             JOIN gruppen g ON g.charge_nr = e_1.charge_nr
          GROUP BY e_1.woche, e_1.bis, g.gruppe, g.schluessel
        ), ausgang_charge AS MATERIALIZED (
         SELECT w_1.woche,
            w_1.bis,
            l.charge_nr,
            sum(l.masse_kg) AS kg
           FROM wochen w_1
             JOIN v_lieferung_charge_tag l ON l.datum <= w_1.bis
          GROUP BY w_1.woche, w_1.bis, l.charge_nr
        ), ausgang AS (
         SELECT a_1.woche,
            a_1.bis,
            g.gruppe,
            g.schluessel,
            sum(a_1.kg) AS kg
           FROM ausgang_charge a_1
             JOIN gruppen g ON g.charge_nr = a_1.charge_nr
          GROUP BY a_1.woche, a_1.bis, g.gruppe, g.schluessel
        ), liste AS (
         SELECT DISTINCT gruppen.gruppe,
            gruppen.schluessel
           FROM gruppen
        )
 SELECT w.woche,
    w.bis,
    w.bis > d.heute AS prognose,
    s.gruppe,
    s.schluessel,
    zahl(COALESCE(e.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS eingang_kum_kg,
    zahl(COALESCE(a.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgang_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_kum_kg,
    zahl(COALESCE(v.schimmel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_kum_kg,
    zahl(COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric) + COALESCE(v.schimmel_kg, 0::numeric) + COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_kum_kg,
    zahl(COALESCE(v.im_haus_kg, 0::numeric) + COALESCE(v.aussortiert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_kg,
    zahl(COALESCE(v.lager_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(COALESCE(v.verkaufsfaehig_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(COALESCE(v.kanal_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_kg,
    zahl(COALESCE(v.fax_lager_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_lager_kg,
    zahl(COALESCE(v.aussortiert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS aussortiert_kg
   FROM wochen w
     CROSS JOIN liste s
     CROSS JOIN tag d
     LEFT JOIN verlust v ON v.bis = w.bis AND v.gruppe = s.gruppe AND v.schluessel = s.schluessel
     LEFT JOIN eingang e ON e.bis = w.bis AND e.gruppe = s.gruppe AND e.schluessel = s.schluessel
     LEFT JOIN ausgang a ON a.bis = w.bis AND a.gruppe = s.gruppe AND a.schluessel = s.schluessel
with no data;
create index if not exists erg_verlauf_woche on erg_verlauf (woche);
create unique index if not exists erg_verlauf_pk on erg_verlauf (woche, bis, gruppe, schluessel);
create index if not exists erg_verlauf_gruppe on erg_verlauf (gruppe, schluessel, bis);
comment on materialized view erg_verlauf is
  'Je Woche und Gruppe (gesamt, Sorte, Schlag, Charge): Eingang und Ausgang kumuliert (gemessen), im Lager (Eingangsware, die noch nicht hinter einer Lieferung steckt) und davon verkaufsfähig (gerechnet) — ab heute als Prognose bis zum Saisonende (prognose = true). Der Verlust ist der Abstand zwischen im Lager und verkaufsfähig; seine Teile stehen weiter als eigene Spalten (0071). Seit 0106 ohne Sockel: das Faule ist der Palox-Anteil der Stationen, mit dem Zuwachs je Woche zurück und voraus verschoben, wo die Kennzahl ihn ausweist. Seit 0114 fällt „im Lager" mit den Lieferungen: je Woche der Teil, den die Lieferungen der Charge bis dahin ausmachen, nicht alles am mittleren Liefertag.';
grant select on erg_verlauf to authenticated;


-- ---------- v_hochrechnung_basis ----------
create view v_hochrechnung_basis with (security_invoker = true) as
 WITH je_charge AS (
         SELECT mv_kaskade.charge_nr,
            sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text) AS ausgelagert_kg,
            sum(mv_kaskade.m0 * mv_kaskade.alter_tage) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric) AS alter_ausgelagert,
            sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS lager_kg,
            sum(mv_kaskade.m0 * mv_kaskade.alter_tage) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS alter_lager,
            sum(mv_kaskade.verkaufsfaehig_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS verkaufsfaehig_lager_kg,
            sum(mv_kaskade.geliefert_kg) AS geliefert_kg,
            sum(mv_kaskade.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(mv_kaskade.n_lieferungen)::integer AS n_lieferung_kohorten,
            min(mv_kaskade.kohorte) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric) AS rest_von,
            max(mv_kaskade.kohorte) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric) AS rest_bis,
            count(*) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric)::integer AS n_rest_kohorten,
            sum(mv_kaskade.m0 * (mv_kaskade.kohorte - '2000-01-01'::date)::numeric) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS rest_tage_seit_epoche,
                CASE
                    WHEN bool_and(mv_kaskade.r_bekannt) THEN COALESCE(sum(mv_kaskade.verdunstung_kg), 0::numeric)
                    ELSE NULL::numeric
                END AS verdunstung_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.f_bekannt) THEN COALESCE(sum(mv_kaskade.schimmel_kg), 0::numeric)
                    ELSE NULL::numeric
                END AS schimmel_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) THEN COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS kanal_ausgelagert_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_fax_bekannt) THEN COALESCE(sum(mv_kaskade.fax_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS fax_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_fax_bekannt) THEN COALESCE(sum(mv_kaskade.fax_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS fax_erwartet_kg,
            COALESCE(sum(mv_kaskade.m2) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) + COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric) AS im_haus_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) THEN COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS kanal_im_haus_kg,
            bool_and(mv_kaskade.r_bekannt AND mv_kaskade.f_bekannt AND mv_kaskade.a_fax_bekannt AND mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) AS verlust_bekannt,
            bool_and(mv_kaskade.r_bekannt) AS verdunstung_bekannt,
            bool_and(mv_kaskade.f_bekannt) AS schimmel_bekannt,
            bool_and(mv_kaskade.a_fax_bekannt) AS fax_bekannt,
            bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) AS kanal_bekannt,
            sum(mv_kaskade.m1 * mv_kaskade.f) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m1) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS faul_anteil_lager,
            max(mv_kaskade.f_quelle) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS faul_quelle,
            count(*) > 0 AS gerechnet,
            count(*) FILTER (WHERE mv_kaskade.portion = 'lager'::text) > 0 AS hat_lager
           FROM mv_kaskade
          GROUP BY mv_kaskade.charge_nr
        )
 SELECT b.charge_nr,
    b.schlag,
    b.sorte,
    b.eingang_kg,
    b.n_paletten,
    b.eingangsdatum_mittel,
    zahl(COALESCE(k.ausgelagert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgelagert_kg,
    zahl(k.alter_ausgelagert, 1, '100000'::numeric)::numeric(8,1) AS alter_ausgelagert,
    zahl(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.lager_kg, 0::numeric)
        END, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(COALESCE(k.alter_lager, (b.stichtag - b.eingangsdatum_mittel)::numeric), 1, '100000'::numeric)::numeric(8,1) AS alter_lager,
    zahl((heute() - x.rest_datum)::double precision, 1, '100000'::numeric)::numeric(8,1) AS alter_lager_heute,
    b.weg2_anteil,
    b.stichtag,
    b.n_paletten_mit_netto,
    zahl(COALESCE(k.ueberzaehlung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ueberzaehlung_kg,
    b.sortiert_kg,
    b.gewaschen_kg,
    b.wartet_kg,
    b.anteil_gewaschen,
    b.alter_band,
    b.am_band_kg,
    x.rest_datum AS eingangsdatum_rest,
    COALESCE(k.n_lieferung_kohorten, 0) > 0 AS rest_alter_aus_zaehlung,
    b.eingang_von,
    b.eingang_bis,
    b.n_eingangstage,
    COALESCE(k.rest_von, b.eingang_von) AS rest_von,
    COALESCE(k.rest_bis, b.eingang_bis) AS rest_bis,
    round(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.lager_kg, 0::numeric)
        END / NULLIF(b.eingang_kg / NULLIF(b.n_paletten, 0)::numeric, 0::numeric))::integer AS n_rest_paletten,
    COALESCE(k.n_rest_kohorten, b.n_eingangstage) AS n_rest_kohorten,
    heute() - COALESCE(k.rest_bis, b.eingang_bis) AS alter_lager_von,
    heute() - COALESCE(k.rest_von, b.eingang_von) AS alter_lager_bis,
    zahl(COALESCE(k.geliefert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS geliefert_kg,
    zahl(k.verkaufsfaehig_lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_lager_kg,
    COALESCE(n.n_lieferungen, 0) AS n_lieferungen,
    zahl(k.verdunstung_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_heute_kg,
    zahl(k.schimmel_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_heute_kg,
    zahl(k.fax_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_heute_kg,
    zahl(k.verdunstung_heute_kg + k.schimmel_heute_kg + k.fax_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_heute_kg,
    zahl(k.kanal_ausgelagert_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(k.fax_erwartet_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_erwartet_kg,
    zahl(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.im_haus_heute_kg, 0::numeric)
        END, 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_heute_kg,
    zahl(k.kanal_im_haus_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_im_haus_kg,
    COALESCE(k.verlust_bekannt, false) AS verlust_bekannt,
    COALESCE(k.verdunstung_bekannt, false) AS verdunstung_bekannt,
    COALESCE(k.schimmel_bekannt, false) AS schimmel_bekannt,
    COALESCE(k.fax_bekannt, false) AS fax_bekannt,
    COALESCE(k.kanal_bekannt, false) AS kanal_bekannt,
    zahl(k.faul_anteil_lager, 4, 1::numeric)::numeric(6,4) AS faul_anteil,
    k.faul_quelle,
    heute() AS heute
   FROM v_kaskade_basis b
     LEFT JOIN je_charge k ON k.charge_nr = b.charge_nr
     LEFT JOIN ( SELECT v_lieferung_charge.charge_nr,
            count(DISTINCT v_lieferung_charge.id)::integer AS n_lieferungen
           FROM v_lieferung_charge
          WHERE (v_lieferung_charge.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])) AND v_lieferung_charge.id > 0
          GROUP BY v_lieferung_charge.charge_nr) n ON n.charge_nr = b.charge_nr
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN k.rest_tage_seit_epoche IS NOT NULL THEN '2000-01-01'::date + round(k.rest_tage_seit_epoche)::integer
                    ELSE b.eingangsdatum_mittel
                END AS rest_datum) x
  WHERE b.eingang_kg IS NOT NULL;
comment on view v_hochrechnung_basis is
  'Je Charge, alles bis heute: Eingang und geliefert (gemessen), ausgelagert (Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus ausgelagert, in Eingangskilo), verlust_heute_kg (Verdunstung + Faules + Fax am Abgepackten), im_haus_heute_kg (Eingangsmasse, die noch liegt, nach Verdunstung und Verderb, plus hinter den Lieferungen Aussortiertes, 0101). Keine Prognose. 0064: Jede Stromsumme ist NULL, solange ihr Koeffizient keine Messung hat. Seit 0106 ohne Sockel; faul_anteil und faul_quelle sagen, womit das Liegende rechnet und woher es kommt. Seit 0114 zählt n_lieferungen jeden Lieferschein, der von der Charge genommen hat, einmal (bis dahin einmal je Eingangstag; der Ausgang vor der App zählt in der Masse, nicht als Lieferschein).';
grant select on v_hochrechnung_basis to authenticated;


-- ---------- v_kaskade ----------
create view v_kaskade with (security_invoker = true) as
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    m0,
    m1,
    m2,
    r,
    f,
    f_unten,
    f_oben,
    f_se,
    f_ws,
    f_s,
    g_w,
    p_hand,
    p_wasch,
    f_quelle,
    f_geliehen,
    b_ws,
    b_s,
    b_w,
    zuwachs_bekannt,
    a_klein_n,
    a_gross_n,
    a_fax,
    d_m1_r,
    r_n,
    r_basis,
    klein_n,
    klein_basis,
    gross_n,
    gross_basis,
    f_n,
    fax_n,
    fax_basis,
    r_bekannt,
    f_bekannt,
    a_klein_bekannt,
    a_gross_bekannt,
    a_fax_bekannt,
    verdunstung_kg,
    schimmel_kg,
    klein_kg,
    nebenkanal_kg,
    fax_kg,
    verkaufsfaehig_kg,
    kohorte,
    geliefert_kg,
    ueberzaehlung_kg,
    n_lieferungen,
    verkaufsfaehig_anteil
   FROM mv_kaskade;
comment on view v_kaskade is
  'Der Massenfluss je Charge, Eingangstag und Portion: Was eingelagert wurde (eingang_kg) verteilt sich auf Verdunstung, Faules, zu klein, Nebenkanal, Fax und verkaufsfähige Ware. Die Ströme addieren sich zum Eingang. "Verlust" ist hier nur, was wirklich verloren ist: verdunstung_kg, schimmel_kg. klein_kg und nebenkanal_kg sind kein Verlust, sondern ein anderer Kanal. Seit 0106 ohne Sockel; f kommt aus den Stationswerten (f_quelle).';
grant select on v_kaskade to authenticated;


-- ---------- v_prognose ----------
create view v_prognose with (security_invoker = true) as
 WITH tag AS MATERIALIZED (
         SELECT heute() AS heute,
            stichtag() AS stichtag
        ), ende AS (
         SELECT GREATEST(LEAST(t.stichtag - t.heute, 400), 28) AS tage
           FROM tag t
        ), horizonte AS (
         SELECT g.h
           FROM ende e,
            LATERAL generate_series(0, e.tage, 7) g(h)
        UNION
         SELECT 7
        UNION
         SELECT 14
        UNION
         SELECT 28
        UNION
         SELECT ende.tage
           FROM ende
        ), grenzen AS (
         SELECT mv_koeff_rand.sorte,
            mv_koeff_rand.r_unten,
            mv_koeff_rand.r_oben,
            mv_koeff_rand.klein_unten,
            mv_koeff_rand.klein_oben,
            mv_koeff_rand.gross_unten,
            mv_koeff_rand.gross_oben,
            mv_koeff_rand.fax_unten,
            mv_koeff_rand.fax_oben
           FROM mv_koeff_rand
        ), lager AS MATERIALIZED (
         SELECT k.charge_nr,
            k.sorte,
            k.schlag,
            k.kohorte,
            k.alter_tage,
            k.m0,
            k.r,
            k.f,
            k.f_unten,
            k.f_oben,
            k.f_ws,
            k.f_s,
            k.g_w,
            k.p_hand,
            k.p_wasch,
            k.b_ws,
            k.b_s,
            k.b_w,
            k.zuwachs_bekannt,
            k.a_klein_n,
            k.a_gross_n,
            k.a_fax,
            k.hagel,
            k.r_bekannt,
            k.f_bekannt,
            k.a_klein_bekannt,
            k.a_gross_bekannt,
            k.a_fax_bekannt,
            k.f_geliehen,
            COALESCE(g.r_unten, 0::numeric) AS r_unten,
            COALESCE(g.r_oben, 0::numeric) AS r_oben,
            COALESCE(g.klein_unten, 0::numeric) AS klein_unten,
            COALESCE(g.klein_oben, 0::numeric) AS klein_oben,
            COALESCE(g.gross_unten, 0::numeric) AS gross_unten,
            COALESCE(g.gross_oben, 0::numeric) AS gross_oben,
            COALESCE(g.fax_unten, 0::numeric) AS fax_unten,
            COALESCE(g.fax_oben, 0::numeric) AS fax_oben,
            power(1::numeric - k.r, k.alter_tage) AS wa,
            power(1::numeric - GREATEST(COALESCE(g.r_unten, 0::numeric), 0::numeric), k.alter_tage) AS wa_unten,
            power(1::numeric - GREATEST(COALESCE(g.r_oben, 0::numeric), 0::numeric), k.alter_tage) AS wa_oben
           FROM mv_kaskade k
             LEFT JOIN grenzen g ON g.sorte = k.sorte
          WHERE k.portion = 'lager'::text AND k.m0 > 0::numeric AND k.alter_tage >= 0::numeric
        ), faktor_h AS MATERIALIZED (
         SELECT c.charge_nr,
            h.h,
            power(1::numeric - c.r, h.h::numeric) AS wh,
            power(1::numeric - GREATEST(c.r_unten, 0::numeric), h.h::numeric) AS wh_unten,
            power(1::numeric - GREATEST(c.r_oben, 0::numeric), h.h::numeric) AS wh_oben
           FROM ( SELECT DISTINCT lager.charge_nr,
                    lager.r,
                    lager.r_unten,
                    lager.r_oben
                   FROM lager) c
             CROSS JOIN horizonte h
        ), je_portion AS (
         SELECT l.charge_nr,
            l.sorte,
            l.schlag,
            l.kohorte,
            l.alter_tage,
            l.m0,
            l.r,
            l.f,
            l.f_unten,
            l.f_oben,
            l.f_ws,
            l.f_s,
            l.g_w,
            l.p_hand,
            l.p_wasch,
            l.b_ws,
            l.b_s,
            l.b_w,
            l.zuwachs_bekannt,
            COALESCE(kh.klein, l.a_klein_n) AS a_klein_n,
            COALESCE(kh.gross, l.a_gross_n) AS a_gross_n,
            l.a_klein_n AS a_klein_0,
            l.a_gross_n AS a_gross_0,
            l.a_fax,
            l.r_bekannt,
            l.f_bekannt,
            l.a_klein_bekannt,
            l.a_gross_bekannt,
            l.a_fax_bekannt,
            l.f_geliehen,
            l.r_unten,
            l.r_oben,
            COALESCE(kh.klein, l.klein_unten) AS klein_unten,
            COALESCE(kh.klein, l.klein_oben) AS klein_oben,
            COALESCE(kh.gross, l.gross_unten) AS gross_unten,
            COALESCE(kh.gross, l.gross_oben) AS gross_oben,
            l.fax_unten,
            l.fax_oben,
            l.wa,
            l.wa_unten,
            l.wa_oben,
            h.h,
            (l.alter_tage + h.h::numeric)::integer AS t,
                CASE
                    WHEN l.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(l.p_hand, l.p_wasch, l.f_ws, l.f_s, l.g_w, l.b_ws, l.b_s, l.b_w, h.h::numeric), l.hagel), l.f)
                    ELSE l.f
                END AS f_h,
            w.wh,
            w.wh_unten,
            w.wh_oben,
            d.heute + h.h AS datum
           FROM lager l
             CROSS JOIN horizonte h
             CROSS JOIN tag d
             JOIN faktor_h w ON w.charge_nr = l.charge_nr AND w.h = h.h
             LEFT JOIN mv_kaliber_quelle kq ON kq.charge_nr = l.charge_nr
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - l.r, l.alter_tage + h.h::numeric)) kh ON true
        ), mit_band AS (
         SELECT p.charge_nr,
            p.sorte,
            p.schlag,
            p.kohorte,
            p.alter_tage,
            p.m0,
            p.r,
            p.f,
            p.f_unten,
            p.f_oben,
            p.f_ws,
            p.f_s,
            p.g_w,
            p.p_hand,
            p.p_wasch,
            p.b_ws,
            p.b_s,
            p.b_w,
            p.zuwachs_bekannt,
            p.a_klein_n,
            p.a_gross_n,
            p.a_klein_0,
            p.a_gross_0,
            p.a_fax,
            p.r_bekannt,
            p.f_bekannt,
            p.a_klein_bekannt,
            p.a_gross_bekannt,
            p.a_fax_bekannt,
            p.f_geliehen,
            p.r_unten,
            p.r_oben,
            p.klein_unten,
            p.klein_oben,
            p.gross_unten,
            p.gross_oben,
            p.fax_unten,
            p.fax_oben,
            p.wa,
            p.wa_unten,
            p.wa_oben,
            p.h,
            p.t,
            p.f_h,
            p.wh,
            p.wh_unten,
            p.wh_oben,
            p.datum,
            LEAST(GREATEST(p.f_unten + (p.f_h - p.f), 0::numeric), 1::numeric) AS f_unten_h,
            LEAST(GREATEST(p.f_oben + (p.f_h - p.f), 0::numeric), 1::numeric) AS f_oben_h
           FROM je_portion p
        ), stroeme AS (
         SELECT p.charge_nr,
            p.h,
            p.datum,
            p.t,
            p.m0,
            p.m0 - x.m1 AS verdunstet_kg,
            x.m1 * p.f_h AS faul_kg,
            y.m2 - z.rest AS kanal_kg,
            y.m2 * p.a_klein_n AS klein_kg,
            y.m2 * p.a_gross_n AS gross_kg,
            z.rest * p.a_fax AS fax_kg,
            z.rest * (1::numeric - p.a_fax) AS verkaufsfaehig_kg,
            y.m2 AS gute_ware_kg,
            p.m0 * p.wa_oben * p.wh_oben * (1::numeric - p.f_oben_h) * (1::numeric - LEAST(p.klein_oben / GREATEST(p.klein_oben + p.gross_oben, 1::numeric) + p.gross_oben / GREATEST(p.klein_oben + p.gross_oben, 1::numeric), 1::numeric)) * (1::numeric - p.fax_oben) AS vf_unten,
            p.m0 * p.wa_unten * p.wh_unten * (1::numeric - p.f_unten_h) * (1::numeric - LEAST(p.klein_unten / GREATEST(p.klein_unten + p.gross_unten, 1::numeric) + p.gross_unten / GREATEST(p.klein_unten + p.gross_unten, 1::numeric), 1::numeric)) * (1::numeric - p.fax_unten) AS vf_oben,
            (1::numeric - p.f) * (b0.basis - b.basis * p.wh) AS verlust_wasser,
            b.basis * p.wh * GREATEST(p.f_h - p.f, 0::numeric) AS verlust_faeulnis,
            p.m0 * p.t::numeric AS m0_mal_t,
            p.r_bekannt,
            p.f_bekannt,
            p.a_klein_bekannt,
            p.a_gross_bekannt,
            p.a_fax_bekannt,
            p.f_geliehen,
            p.zuwachs_bekannt
           FROM mit_band p
             CROSS JOIN LATERAL ( SELECT p.m0 * p.wa * p.wh AS m1) x
             CROSS JOIN LATERAL ( SELECT x.m1 * (1::numeric - p.f_h) AS m2) y
             CROSS JOIN LATERAL ( SELECT y.m2 * (1::numeric - p.a_klein_n - p.a_gross_n) AS rest) z
             CROSS JOIN LATERAL ( SELECT p.m0 * (1::numeric - p.a_klein_n - p.a_gross_n) * (1::numeric - p.a_fax) * p.wa AS basis) b
             -- 0116: zu klein und zu gross ändern sich mit dem Alter. Was beim
             -- Eintrocknen unter die Grenze rutscht (oder über ihr wieder
             -- verkaufsfähig wird), gehört zum Wasser: Wasser = VF heute − VF am
             -- Horizont − Fäulnis, mit den Anteilen von heute (b0) und vom Horizont (b).
             CROSS JOIN LATERAL ( SELECT p.m0 * (1::numeric - p.a_klein_0 - p.a_gross_0) * (1::numeric - p.a_fax) * p.wa AS basis) b0
        ), gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text AS text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text AS text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text AS text,
            v_kaskade_basis.charge_nr::text AS charge_nr,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        ), je_charge AS MATERIALIZED (
         SELECT s_1.charge_nr,
            s_1.h,
            max(s_1.datum) AS datum,
            count(*)::integer AS n_kohorten,
            sum(s_1.m0) AS lager_kg,
            sum(s_1.verdunstet_kg) AS verdunstet_kg,
            sum(s_1.faul_kg) AS faul_kg,
            sum(s_1.kanal_kg) AS kanal_kg,
            sum(s_1.klein_kg) AS klein_kg,
            sum(s_1.gross_kg) AS gross_kg,
            sum(s_1.fax_kg) AS fax_kg,
            sum(s_1.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(s_1.gute_ware_kg) AS gute_ware_kg,
            sum(s_1.vf_unten) AS vf_unten_kg,
            sum(s_1.vf_oben) AS vf_oben_kg,
            sum(s_1.verlust_wasser) AS verlust_wasser_kg,
            sum(s_1.verlust_faeulnis) AS verlust_faeulnis_kg,
            sum(s_1.m0_mal_t) AS m0_mal_t,
            bool_and(s_1.r_bekannt) AS r_bekannt,
            bool_and(s_1.f_bekannt) AS f_bekannt,
            bool_and(s_1.a_klein_bekannt AND s_1.a_gross_bekannt) AS kanal_bekannt,
            bool_and(s_1.a_fax_bekannt) AS fax_bekannt,
            bool_or(s_1.f_geliehen) AS f_geliehen,
            bool_and(s_1.zuwachs_bekannt) AS zuwachs_bekannt,
            min(s_1.t) AS alter_von,
            max(s_1.t) AS alter_bis
           FROM stroeme s_1
          GROUP BY s_1.charge_nr, s_1.h
        ), summe AS MATERIALIZED (
         SELECT g.gruppe,
            g.schluessel,
            j.h,
            max(j.datum) AS datum,
            count(*)::integer AS n_chargen,
            sum(j.n_kohorten)::integer AS n_kohorten,
            sum(j.lager_kg) AS lager_kg,
            sum(j.verdunstet_kg) AS verdunstet_kg,
            sum(j.faul_kg) AS faul_kg,
            sum(j.kanal_kg) AS kanal_kg,
            sum(j.klein_kg) AS klein_kg,
            sum(j.gross_kg) AS gross_kg,
            sum(j.fax_kg) AS fax_kg,
            sum(j.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(j.gute_ware_kg) AS gute_ware_kg,
            sum(j.vf_unten_kg) AS vf_unten_kg,
            sum(j.vf_oben_kg) AS vf_oben_kg,
            sum(j.verlust_wasser_kg) AS verlust_wasser_kg,
            sum(j.verlust_faeulnis_kg) AS verlust_faeulnis_kg,
            bool_and(j.r_bekannt) AS r_bekannt,
            bool_and(j.f_bekannt) AS f_bekannt,
            bool_and(j.kanal_bekannt) AS kanal_bekannt,
            bool_and(j.fax_bekannt) AS fax_bekannt,
            bool_or(j.f_geliehen) AS f_geliehen,
            bool_and(j.zuwachs_bekannt) AS zuwachs_bekannt,
            sum(j.m0_mal_t) / NULLIF(sum(j.lager_kg), 0::numeric) AS alter_tage,
            min(j.alter_von) AS alter_von,
            max(j.alter_bis) AS alter_bis
           FROM je_charge j
             JOIN gruppen g ON g.charge_nr = j.charge_nr
          GROUP BY g.gruppe, g.schluessel, j.h
        ), rate AS (
         SELECT s0.gruppe,
            s0.schluessel,
            (s1.verlust_wasser_kg + s1.verlust_faeulnis_kg) / s1.h::numeric AS vf_je_tag_kg,
            s1.verlust_wasser_kg / s1.h::numeric AS verdunstet_je_tag_kg,
                CASE
                    WHEN s1.zuwachs_bekannt THEN s1.verlust_faeulnis_kg / s1.h::numeric
                    ELSE NULL::numeric
                END AS faul_je_tag_kg
           FROM summe s0
             JOIN LATERAL ( SELECT x.gruppe,
                    x.schluessel,
                    x.h,
                    x.datum,
                    x.n_chargen,
                    x.n_kohorten,
                    x.lager_kg,
                    x.verdunstet_kg,
                    x.faul_kg,
                    x.kanal_kg,
                    x.fax_kg,
                    x.verkaufsfaehig_kg,
                    x.gute_ware_kg,
                    x.vf_unten_kg,
                    x.vf_oben_kg,
                    x.verlust_wasser_kg,
                    x.verlust_faeulnis_kg,
                    x.r_bekannt,
                    x.f_bekannt,
                    x.kanal_bekannt,
                    x.fax_bekannt,
                    x.f_geliehen,
                    x.zuwachs_bekannt,
                    x.alter_tage,
                    x.alter_von,
                    x.alter_bis
                   FROM summe x
                  WHERE x.gruppe = s0.gruppe AND x.schluessel = s0.schluessel AND x.h > 0
                  ORDER BY x.h
                 LIMIT 1) s1 ON true
          WHERE s0.h = 0
        )
 SELECT s.gruppe,
    s.schluessel,
    s.h,
    s.datum,
    s.n_chargen,
    s.n_kohorten,
    zahl(s.lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(s.verdunstet_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstet_kg,
    zahl(s.faul_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS faul_kg,
    zahl(s.kanal_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_kg,
    zahl(s.fax_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kg,
    zahl(s.verkaufsfaehig_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(s.gute_ware_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS gute_ware_kg,
    zahl(s.verlust_wasser_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_wasser_kg,
    zahl(s.verlust_faeulnis_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_faeulnis_kg,
    zahl(s.verlust_wasser_kg + s.verlust_faeulnis_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_verkaufsfaehig_kg,
        CASE
            WHEN v.vollstaendig AND s.lager_kg > 0::numeric THEN zahl(s.verkaufsfaehig_kg / s.lager_kg, 4, 1::numeric)
            ELSE NULL::numeric
        END::numeric(6,4) AS verkaufsfaehig_anteil,
        CASE
            WHEN v.vollstaendig THEN zahl(s.vf_unten_kg, 2, '1000000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(14,2) AS verkaufsfaehig_unten_kg,
        CASE
            WHEN v.vollstaendig THEN zahl(s.vf_oben_kg, 2, '1000000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(14,2) AS verkaufsfaehig_oben_kg,
    zahl(r.vf_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS verkaufsfaehig_je_tag_kg,
    zahl(r.verdunstet_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS verdunstet_je_tag_kg,
    zahl(r.faul_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS faul_je_tag_kg,
    s.r_bekannt,
    s.f_bekannt,
    s.kanal_bekannt,
    s.fax_bekannt,
    v.vollstaendig,
    s.f_geliehen,
    s.zuwachs_bekannt,
    round(s.alter_tage)::integer AS alter_tage,
    s.alter_von,
    s.alter_bis,
    zahl(s.klein_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS klein_kg,
    zahl(s.gross_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS gross_kg
   FROM summe s
     CROSS JOIN LATERAL ( SELECT s.r_bekannt AND s.f_bekannt AND s.kanal_bekannt AND s.fax_bekannt AS vollstaendig) v
     LEFT JOIN rate r ON r.gruppe = s.gruppe AND r.schluessel = s.schluessel;
comment on view v_prognose is
  'Was aus der heute liegenden Ware wird, wenn sie liegen bleibt — je Gruppe (gesamt, Sorte, Schlag, Charge) und je Horizont h Tage, von heute bis zum Saisonende in Wochenschritten (7/14/28 immer dabei). Es ist die Kaskade (mv_kaskade, Portion „lager") bei alter_tage + h, mit denselben Formeln: bei h = 0 stehen deshalb genau die Zahlen von erg_charge. Der Palox-Anteil wächst je Station um ihren Anstieg je Woche Lagerdauer (0111) — nur wenn zuwachs_bekannt; sonst bleibt der Anteil von heute stehen und faul_je_tag_kg ist leer. kanal_kg = klein_kg + gross_kg (zu klein, zu gross; getrennt seit 0111). f_geliehen: ein Anteil aus allen Sorten. Der Nenner ist lager_kg, die Eingangsware, die noch nicht hinter einer Lieferung steckt; vollstaendig heisst: Verdunstung, Palox, Ausschuss und Fax gemessen.';
grant select on v_prognose to authenticated;


-- ---------- erg_charge ----------
create materialized view erg_charge as
 SELECT charge_nr,
    schlag,
    sorte,
    eingang_kg,
    n_paletten,
    eingangsdatum_mittel,
    ausgelagert_kg,
    alter_ausgelagert,
    lager_kg,
    alter_lager,
    alter_lager_heute,
    weg2_anteil,
    stichtag,
    n_paletten_mit_netto,
    ueberzaehlung_kg,
    sortiert_kg,
    gewaschen_kg,
    wartet_kg,
    anteil_gewaschen,
    alter_band,
    am_band_kg,
    eingangsdatum_rest,
    rest_alter_aus_zaehlung,
    eingang_von,
    eingang_bis,
    n_eingangstage,
    rest_von,
    rest_bis,
    n_rest_paletten,
    n_rest_kohorten,
    alter_lager_von,
    alter_lager_bis,
    geliefert_kg,
    verkaufsfaehig_lager_kg,
    n_lieferungen,
    verdunstung_heute_kg,
    schimmel_heute_kg,
    fax_heute_kg,
    verlust_heute_kg,
    kanal_ausgelagert_kg,
    fax_erwartet_kg,
    im_haus_heute_kg,
    kanal_im_haus_kg,
    verlust_bekannt,
    verdunstung_bekannt,
    schimmel_bekannt,
    fax_bekannt,
    kanal_bekannt,
    faul_anteil,
    faul_quelle,
    heute
   FROM v_hochrechnung_basis
with no data;
create unique index if not exists erg_charge_pk on erg_charge (charge_nr);
create index if not exists erg_charge_sorte on erg_charge (sorte);
comment on materialized view erg_charge is
  'v_hochrechnung_basis, gespeichert für die App (0062). Erneuert mit auswertung_schritt(). Seit 0101 zählt im_haus_heute_kg das hinter den Lieferungen Aussortierte mit (kanal_ausgelagert_kg: zu klein und zu gross, im Haus, nicht verkaufsfähig). Seit 0106 ohne Sockel, mit faul_anteil und faul_quelle.';
grant select on erg_charge to authenticated;


-- ---------- erg_prognose ----------
create materialized view erg_prognose as
 SELECT gruppe,
    schluessel,
    h,
    datum,
    n_chargen,
    n_kohorten,
    lager_kg,
    verdunstet_kg,
    faul_kg,
    kanal_kg,
    fax_kg,
    verkaufsfaehig_kg,
    gute_ware_kg,
    verlust_wasser_kg,
    verlust_faeulnis_kg,
    verlust_verkaufsfaehig_kg,
    verkaufsfaehig_anteil,
    verkaufsfaehig_unten_kg,
    verkaufsfaehig_oben_kg,
    verkaufsfaehig_je_tag_kg,
    verdunstet_je_tag_kg,
    faul_je_tag_kg,
    r_bekannt,
    f_bekannt,
    kanal_bekannt,
    fax_bekannt,
    vollstaendig,
    f_geliehen,
    zuwachs_bekannt,
    alter_tage,
    alter_von,
    alter_bis,
    klein_kg,
    gross_kg
   FROM v_prognose
with no data;
create unique index if not exists erg_prognose_pk on erg_prognose (gruppe, schluessel, h);
create index if not exists erg_prognose_gruppe on erg_prognose (gruppe, h);
comment on materialized view erg_prognose is
  'v_prognose, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';
grant select on erg_prognose to authenticated;


-- ---------- mv_hochrechnung ----------
create materialized view mv_hochrechnung as
 SELECT k.charge_nr,
    k.sorte,
    k.schlag,
    k.portion,
    k.alter_tage,
    k.eingang_kg,
    zahl(c.m0)::numeric(14,2) AS portion_kg,
    k.f_geliehen,
    k.f_n,
    k.f_se,
    s.strom,
    s.buch,
        CASE
            WHEN s.bekannt THEN zahl(s.kg)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
        CASE
            WHEN s.bekannt THEN zahl(s.koeffizient, 6, 100000::numeric)
            ELSE NULL::numeric
        END::numeric(12,6) AS koeffizient,
    s.koeff_n,
    s.koeff_basis,
    s.formel,
    s.d_r,
    s.d_f,
    s.d_a,
    s.koeff_art,
    s.bekannt AS koeff_bekannt,
    k.kohorte
   FROM v_kaskade k
     CROSS JOIN LATERAL ( SELECT GREATEST(k.m0, 0::numeric) AS m0,
            GREATEST(k.m1, 0::numeric) AS m1,
            GREATEST(k.m2, 0::numeric) AS m2,
            GREATEST(k.verkaufsfaehig_kg, 0::numeric) AS verkaufsfaehig_kg,
            LEAST(GREATEST(k.r, 0::numeric), 1::numeric) AS r,
            LEAST(GREATEST(k.f, 0::numeric), 1::numeric) AS f,
            LEAST(GREATEST(k.a_klein_n, 0::numeric), 1::numeric) AS a_klein_n,
            LEAST(GREATEST(k.a_gross_n, 0::numeric), 1::numeric) AS a_gross_n,
            LEAST(GREATEST(k.a_fax, 0::numeric), 1::numeric) AS a_fax) c
     CROSS JOIN LATERAL ( VALUES ('Verdunstung'::text,'verlust'::text,c.m0 - c.m1,c.m0,c.r,k.r_n,k.r_basis,'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'::text,- k.d_m1_r,0::numeric,0::numeric,NULL::text,k.r_bekannt), ('Schimmel/Fäulnis'::text,'verlust'::text,c.m1 * c.f,c.m1,c.f,k.f_n,k.f_quelle,'Masse nach Verdunstung × Palox-Anteil der Stationen auf dem Weg der Charge (0106)'::text,k.d_m1_r * c.f,c.m1,0::numeric,NULL::text,k.f_bekannt), ('Zu klein (Tierfutter)'::text,'marge'::text,c.m1 * (1::numeric - c.f) * c.a_klein_n,c.m2,c.a_klein_n,k.klein_n,k.klein_basis,'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust'::text,k.d_m1_r * (1::numeric - c.f) * c.a_klein_n,(- c.m1) * c.a_klein_n,c.m2,'ausschuss'::text,k.a_klein_bekannt), ('Nebenkanal zu gross'::text,'marge'::text,c.m1 * (1::numeric - c.f) * c.a_gross_n,c.m2,c.a_gross_n,k.gross_n,k.gross_basis,'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'::text,k.d_m1_r * (1::numeric - c.f) * c.a_gross_n,(- c.m1) * c.a_gross_n,c.m2,'nebenkanal'::text,k.a_gross_bekannt), ('Faul beim Abpacken (Fax)'::text,'verlust'::text,c.m1 * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),c.a_fax,k.fax_n,k.fax_basis,'Verkaufsfähige Masse × Anteil Faules, das beim Etikettieren aussortiert wird — vom Waschen und Stehen, nicht von der Lagerdauer'::text,k.d_m1_r * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,(- c.m1) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),'fax'::text,k.a_fax_bekannt), ('Verkaufsfähig'::text,'bilanz'::text,c.verkaufsfaehig_kg,c.m2,NULL::numeric,NULL::integer,NULL::text,'Rest der Kaskade'::text,0::numeric,0::numeric,0::numeric,NULL::text,true)) s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel, d_r, d_f, d_a, koeff_art, bekannt)
with no data;
create index if not exists mv_hochrechnung_charge on mv_hochrechnung (charge_nr, buch);
comment on materialized view mv_hochrechnung is
  'v_hochrechnung, gespeichert. Inhaltlich gleich; erneuert von auswertung_schritt(3).';
grant select on mv_hochrechnung to authenticated;


-- ---------- v_plausibilitaet_0064_zusatz ----------
create view v_plausibilitaet_0064_zusatz with (security_invoker = true) as
 SELECT 'Tara fehlt'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    min(p.eingangsdatum)::timestamp with time zone AS start_ts,
    format('%s von %s Paletten der Charge haben kein Nettogewicht (%s kg brutto): %s. %s'::text, count(*), r.n_paletten, round(sum(p.brutto_kg)),
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'die Gebindeart steht nicht auf der Palette'::text
            WHEN bool_or(g.art IS NULL) THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN bool_or(g.tara_kg_pro_kiste IS NULL) THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN bool_or(g.tara_kg_palette IS NULL) THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END,
        CASE
            WHEN r.n_paletten_mit_netto = 0 THEN 'Damit hat die Charge gar keinen Eingang — sie fehlt in der ganzen Bilanz.'::text
            ELSE format('Für sie rechnet der Eingang mit dem Mittel der übrigen: %s der %s kg '::text || 'Eingang sind hochgerechnet, nicht gewogen.'::text, round(r.eingang_netto_kg - r.eingang_netto_gemessen_kg), round(r.eingang_netto_kg))
        END) AS befund,
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'Gebindeart am Wareneingang nachtragen.'::text
            WHEN bool_or(g.art IS NULL) OR bool_or(g.tara_kg_pro_kiste IS NULL) OR bool_or(g.tara_kg_palette IS NULL) THEN 'Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. '::text || 'Die Zahlen rechnen sich danach von selbst neu.'::text
            ELSE 'Kistenzahl der Palette im Wareneingang nachtragen.'::text
        END AS rat
   FROM palette p
     LEFT JOIN gebinde g ON g.art = p.gebindeart
     JOIN charge c ON c.nr = p.charge_nr
     JOIN v_charge_rueckgrat r ON r.charge_nr = p.charge_nr
  WHERE (p.brutto_kg - p.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) IS NULL
  GROUP BY p.charge_nr, c.sorte, r.n_paletten, r.n_paletten_mit_netto, r.eingang_netto_kg, r.eingang_netto_gemessen_kg
UNION ALL
 SELECT 'Überzählung'::text AS art,
    NULL::bigint AS auftrag_id,
    h.charge_nr,
    h.sorte,
    h.eingangsdatum_mittel::timestamp with time zone AS start_ts,
    format('Die Lieferungen dieser Charge (%s kg) brauchen nach der gerechneten Ausbeute (%s %% verkaufsfähig) %s kg Eingang — erfasst sind %s kg, also %s kg zu wenig. Geliefert wurde nicht mehr als eingelagert; es wurde mehr geliefert, als die Rechnung aus diesem Eingang erwartet.'::text, round(h.geliefert_kg), round(100::numeric * h.geliefert_kg / NULLIF(h.eingang_kg + h.ueberzaehlung_kg, 0::numeric)), round(h.eingang_kg + h.ueberzaehlung_kg), round(h.eingang_kg), round(h.ueberzaehlung_kg)) AS befund,
    'Drei Möglichkeiten: Im Erntejournal fehlt eine Palette dieser Charge; ein Lieferschein ist auf die falsche Chargennummer gebucht; oder diese Charge hat weniger Verlust als das Modell annimmt — dann ist „Im Lager" für sie zu klein gerechnet. Die ersten zwei lassen sich nachtragen.'::text AS rat
   FROM v_hochrechnung_basis h
  WHERE h.ueberzaehlung_kg > 0::numeric
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — %s, nicht mit der Palette selbst.'::text, count(*), ap.brutto_zettel_kg, to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text),
        CASE
            WHEN bool_and(m.masse_quelle = 'gewogen'::text) THEN 'gerechnet wird mit der Wägung der Palette'::text
            WHEN bool_and(m.masse_quelle = 'zettel-kisten'::text) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            WHEN bool_and(m.masse_quelle = ANY (ARRAY['zettel-kisten'::text, 'zettel-kisten-charge'::text, 'gewogen'::text])) THEN 'gerechnet wird mit den gezählten Kisten und der Tara je Kiste der Charge (Zettel − Kisten × Tara je Kiste)'::text
            ELSE 'gerechnet wird mit der mittleren Tara ganzer Paletten der Charge — an der Zählung fehlt die Kistenzahl'::text
        END) AS befund,
    'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.id = ap.id
  WHERE ap.brutto_zettel_kg IS NOT NULL AND ap.eingangsdatum IS NOT NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg)) AND NOT (EXISTS ( SELECT 1
           FROM v_palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg AND p.eingangsdatum = ap.eingangsdatum AND p.netto_kg IS NOT NULL))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg, ap.eingangsdatum
UNION ALL
 SELECT 'Palette fraglich'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s: %s kg brutto in %s Kiste(n) %s, mit Palette gewogen — davon bleiben %s kg netto. Eine leere Palette wiegt allein %s kg.'::text,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'Zu klein'::text
            ELSE 'Zu gross'::text
        END, m.brutto_kg, m.kisten, m.gebindeart, m.kg, g.tara_kg_palette) AS befund,
    'Standen die Kisten direkt auf der Waage? Dann in der Korrektur „mit Palette" abwählen — das Netto rechnet sich von selbst neu.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.gemessen AND m.mit_palette AND m.brutto_kg IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND m.brutto_kg < (2::numeric * g.tara_kg_palette) AND a.abgebrochen_ts IS NULL
UNION ALL
 SELECT 'Verdunstung'::text AS art,
    m.auftrag_id,
    m.charge_nr,
    m.sorte,
    m.wiege_ts AS start_ts,
    format('%s %% je Tag: %s kg → %s kg in %s Tagen — so schnell verdunstet kein Kürbis (Grenze %s %% je Tag)'::text, round(m.rate_pro_tag * 100::numeric, 2), round(m.netto_damals_kg), round(m.netto_jetzt_kg), m.lagertage, round(verdunstung_rate_max() * 100::numeric, 2)) AS befund,
    'Zettelgewicht, Kisten und Gebinde dieser Wägung prüfen — oder es ist eine andere Palette. Bis zur Korrektur zählt sie nicht in die Rate.'::text AS rat
   FROM v_verdunstung_messung m
  WHERE m.grund ~~ 'zu schnell%'::text;
comment on view v_plausibilitaet_0064_zusatz is
  'Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die Paletten fehlen im Eingang), eine Charge mit mehr Ausgang als Eingang, und ein Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag.';
grant select on v_plausibilitaet_0064_zusatz to authenticated;


-- ---------- v_hochrechnung ----------
create view v_hochrechnung with (security_invoker = true) as
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    portion_kg,
    f_geliehen,
    f_n,
    f_se,
    strom,
    buch,
    kg,
    basis_kg,
    koeffizient,
    koeff_n,
    koeff_basis,
    formel,
    d_r,
    d_f,
    d_a,
    koeff_art,
    koeff_bekannt,
    kohorte
   FROM mv_hochrechnung;
comment on view v_hochrechnung is
  'Die Kaskade auseinandergelegt: eine Zeile je Charge, Portion und Strom, mit dem verwendeten Koeffizienten, seiner Herkunft (koeff_art, beim Faulen koeff_basis = f_quelle), der Zahl der Messungen dahinter (koeff_n) und der Formel. koeff_bekannt = false heisst: geschätzt, nicht gemessen. f_geliehen: der Palox-Anteil kommt aus den Arbeiten aller Sorten (0106).';
grant select on v_hochrechnung to authenticated;


-- ---------- v_kontrolle_vorschlag ----------
create view v_kontrolle_vorschlag with (security_invoker = true) as
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lager_kg,
    b.alter_lager_von,
    b.alter_lager_bis,
    b.eingang_von,
    b.eingang_bis,
    COALESCE(k.n_kontrollen, 0) AS n_kontrollen,
    k.zuletzt,
    b.im_haus_heute_kg,
    heute() - COALESCE(k.zuletzt, b.eingang_von) AS tage_seit_wiegung,
    zahl(b.im_haus_heute_kg * GREATEST(heute() - COALESCE(k.zuletzt, b.eingang_von), 1)::numeric, 0, '10000000000000'::numeric)::numeric(14,0) AS informationswert
   FROM erg_charge b
     LEFT JOIN ( SELECT verdunstung_wiegung.charge_nr,
            count(*) FILTER (WHERE verdunstung_wiegung.auftrag_id IS NULL)::integer AS n_kontrollen,
            max(verdunstung_wiegung.wiege_ts)::date AS zuletzt
           FROM verdunstung_wiegung
          WHERE verdunstung_wiegung.gemessen
          GROUP BY verdunstung_wiegung.charge_nr) k ON k.charge_nr = b.charge_nr
  WHERE b.im_haus_heute_kg > 0::numeric
  ORDER BY (zahl(b.im_haus_heute_kg * GREATEST(heute() - COALESCE(k.zuletzt, b.eingang_von), 1)::numeric, 0, '10000000000000'::numeric)::numeric(14,0)) DESC NULLS LAST, b.im_haus_heute_kg DESC
 LIMIT 3;
comment on view v_kontrolle_vorschlag is
  'Welche Charge als Nächstes kontrolliert werden sollte. informationswert gewichtet, wie viel noch im Haus liegt, wie lange die letzte Wiegung her ist und wie unsicher die Charge bisher ist — eine Reihenfolge, kein Befehl.';
grant select on v_kontrolle_vorschlag to authenticated;


-- ---------- v_massenbilanz ----------
create view v_massenbilanz with (security_invoker = true) as
 WITH csv_anteil AS MATERIALIZED (
         SELECT am.charge_nr,
            COALESCE(sum(am.eingang_netto_kg) FILTER (WHERE (EXISTS ( SELECT 1
                   FROM sortier_lauf l
                  WHERE l.auftrag_id = am.auftrag_id))) / NULLIF(sum(am.eingang_netto_kg), 0::numeric), 0::numeric) AS anteil_mit_csv
           FROM v_auftrag_masse am
          WHERE (am.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND am.eingang_netto_kg IS NOT NULL
          GROUP BY am.charge_nr
        ), gemessen AS MATERIALIZED (
         SELECT v_sortier_lauf_masse.charge_nr,
            sum(v_sortier_lauf_masse.masse_kg) AS gemessen_kg
           FROM v_sortier_lauf_masse
          GROUP BY v_sortier_lauf_masse.charge_nr
        ), rest AS MATERIALIZED (
         SELECT v_kaskade.charge_nr,
            sum(v_kaskade.m2) FILTER (WHERE v_kaskade.portion = 'lager'::text) AS restbestand_kg
           FROM v_kaskade
          GROUP BY v_kaskade.charge_nr
        ), modell AS MATERIALIZED (
         SELECT b_1.charge_nr,
            b_1.am_band_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), COALESCE(b_1.alter_band, 0::numeric)) * (1::numeric - COALESCE(ep.anteil, er.anteil)) * q.anteil_mit_csv AS am_band_modell_kg
           FROM v_kaskade_basis b_1
             LEFT JOIN csv_anteil q ON q.charge_nr = b_1.charge_nr
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b_1.sorte
             LEFT JOIN v_charge_palox ep ON ep.charge_nr = b_1.charge_nr AND ep.station = 'sortieren'::text
             LEFT JOIN v_palox_erwartung er ON er.sorte = b_1.sorte AND er.station = 'sortieren'::text
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.eingang_kg,
    b.ausgelagert_kg,
    b.lager_kg,
    b.n_paletten,
    b.alter_ausgelagert,
    b.alter_lager,
    b.stichtag,
    zahl(m.am_band_modell_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS modell_am_band_kg,
    c.gemessen_kg AS csv_gemessen_kg,
    zahl(c.gemessen_kg - m.am_band_modell_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS abweichung_kg,
        CASE
            WHEN m.am_band_modell_kg > 0::numeric THEN zahl((c.gemessen_kg - m.am_band_modell_kg) / m.am_band_modell_kg, 4, '1000000'::numeric)::numeric(10,4)
            ELSE NULL::numeric
        END AS abweichung_anteil,
    zahl(r.restbestand_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS restbestand_kg,
    kb.alter_band
   FROM erg_charge b
     JOIN v_kaskade_basis kb ON kb.charge_nr = b.charge_nr
     LEFT JOIN modell m ON m.charge_nr = b.charge_nr
     LEFT JOIN gemessen c ON c.charge_nr = b.charge_nr
     LEFT JOIN rest r ON r.charge_nr = b.charge_nr;
comment on view v_massenbilanz is
  'Die Probe aufs Exempel je Charge: Was die Kaskade am Band erwartet (modell_am_band_kg: Bandarbeiten nach Verdunstung und Palox-Anteil der Sortierstation, 0106) gegen das, was die Sortier-Datei gewogen hat (csv_gemessen_kg). abweichung_anteil nahe 0 heisst, die Koeffizienten treffen die Wirklichkeit; systematisch positiv heisst, die Verluste sind überschätzt. Nur für Chargen mit Sortier-Datei aussagekräftig.';
grant select on v_massenbilanz to authenticated;


-- ---------- v_naechste_charge ----------
create view v_naechste_charge with (security_invoker = true) as
 SELECT p0.schluessel::integer AS charge_nr,
    b.sorte,
    b.schlag,
    p0.lager_kg,
    p0.alter_tage,
    p0.gute_ware_kg AS masse_jetzt_kg,
    zahl(p14.verlust_wasser_kg, 1, '100000000000'::numeric)::numeric(12,1) AS verdunstung_14_kg,
        CASE
            WHEN p0.zuwachs_bekannt THEN zahl(p14.verlust_faeulnis_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1) AS schimmel_14_kg,
        CASE
            WHEN p0.zuwachs_bekannt THEN zahl(p14.verlust_verkaufsfaehig_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1) AS prognose_verlust_14_kg,
    p0.f_geliehen,
    p0.zuwachs_bekannt,
    p0.alter_von,
    p0.alter_bis,
    p0.n_kohorten
   FROM erg_prognose p0
     JOIN erg_prognose p14 ON p14.gruppe = 'charge'::text AND p14.schluessel = p0.schluessel AND p14.h = 14
     JOIN v_kaskade_basis b ON b.charge_nr = p0.schluessel::integer
  WHERE p0.gruppe = 'charge'::text AND p0.h = 0 AND p0.lager_kg > 0::numeric
  ORDER BY (
        CASE
            WHEN p0.zuwachs_bekannt THEN zahl(p14.verlust_verkaufsfaehig_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1)) DESC NULLS LAST;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Gerechnet aus v_prognose (Horizont 14 gegen Horizont 0) — dieselbe Formel wie die Kaskade, damit es im ganzen Programm nur eine Zwei-Wochen-Zahl gibt. prognose_verlust_14_kg ist, was an **verkaufsfähiger** Ware verloren geht, und verdunstung_14_kg + schimmel_14_kg ergeben es auf den Rappen. Seit 0106 leer, solange die Kennzahl je Station keinen Zuwachs ausweist (zuwachs_bekannt = false).';
grant select on v_naechste_charge to authenticated;


-- ---------- v_plausibilitaet_0054_zusatz ----------
create view v_plausibilitaet_0054_zusatz with (security_invoker = true) as
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber für ein Band mit diesen Grenzen hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, a.kaliber_von_g, a.kaliber_bis_g) AS befund,
    'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) oder die fertigen Paletten wiegen (drei reichen).'::text AS rat
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx = '-2'::integer AND NOT (EXISTS ( SELECT 1
           FROM v_auftrag_wasch_gewogen wg
          WHERE wg.auftrag_id = g.auftrag_id AND wg.quelle = 'gewogen_strasse'::text))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    wp.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '::text || 'die Menge dieser Arbeit damit auch'::text, wp.n_paletten, wp.kisten,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN format('für das Band %s–%s g hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen'::text, a.kaliber_von_g, a.kaliber_bis_g)
            ELSE 'für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen'::text
        END) AS befund,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen.'::text
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — dann kennt die App das Kistengewicht des Bandes, rückwirkend auch für diese Arbeit; oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat
   FROM v_auftrag_wasch_paletten wp
     JOIN auftrag a ON a.id = wp.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE wp.kg IS NULL AND wp.kisten > 0 AND NOT (EXISTS ( SELECT 1
           FROM v_auftrag_wasch_gewogen wg
          WHERE wg.auftrag_id = wp.auftrag_id AND wg.quelle = 'gewogen_strasse'::text))
UNION ALL
 SELECT 'Lieferung in der Zukunft'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    l.datum::timestamp with time zone AS start_ts,
    format('Lieferschein über %s kg mit Datum %s — das liegt nach heute (%s). '::text || 'Die Menge zählt erst ab diesem Tag in Ausgang und Bestand.'::text, round(l.masse_kg), to_char(l.datum::timestamp with time zone, 'DD.MM.YYYY'::text), to_char(heute()::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Stimmt das Datum? Ein vordatierter Lieferschein ist in Ordnung — die Zahl '::text || 'erscheint von selbst, sobald der Tag da ist. Ein Zahlendreher gehört korrigiert.'::text AS rat
   FROM v_lieferung_masse l
  WHERE l.datum > heute() AND l.masse_kg IS NOT NULL AND l.masse_kg > 0::numeric
UNION ALL
 SELECT v_plausibilitaet_0064_zusatz.art,
    v_plausibilitaet_0064_zusatz.auftrag_id,
    v_plausibilitaet_0064_zusatz.charge_nr,
    v_plausibilitaet_0064_zusatz.sorte,
    v_plausibilitaet_0064_zusatz.start_ts,
    v_plausibilitaet_0064_zusatz.befund,
    v_plausibilitaet_0064_zusatz.rat
   FROM v_plausibilitaet_0064_zusatz;
comment on view v_plausibilitaet_0054_zusatz is
  'Zusatzprüfungen zu v_plausibilitaet, die seit 0054 dazugekommen sind — je Auffälligkeit Art, betroffene Arbeit, Befund und Rat. Wird von v_plausibilitaet mitgelesen; einzeln braucht sie niemand.';
grant select on v_plausibilitaet_0054_zusatz to authenticated;


-- ---------- v_verlust_je_gruppe ----------
create view v_verlust_je_gruppe with (security_invoker = true) as
 WITH gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text AS text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text AS text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text AS text,
            v_kaskade_basis.charge_nr::text AS charge_nr,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        ), zeilen AS MATERIALIZED (
         SELECT g_1.gruppe,
            g_1.schluessel,
            h.charge_nr,
            h.sorte,
            h.portion,
            h.f_geliehen,
            h.f_n,
            h.f_se,
            h.strom,
            h.buch,
            h.kg,
            h.basis_kg,
            h.koeff_n,
            h.koeff_basis,
            h.formel,
            h.d_r,
            h.d_f,
            h.d_a,
            h.koeff_art,
            h.koeff_bekannt,
            h.strom = 'Faul beim Abpacken (Fax)'::text AND h.portion = 'lager'::text AS erwartet
           FROM mv_hochrechnung h
             JOIN gruppen g_1 ON g_1.charge_nr = h.charge_nr
          WHERE h.buch = ANY (ARRAY['verlust'::text, 'marge'::text])
        ), unsicherheit AS MATERIALIZED (
         SELECT v_koeff_unsicherheit.art,
            v_koeff_unsicherheit.sorte,
            v_koeff_unsicherheit.b,
            v_koeff_unsicherheit.varianz_eigen,
            v_koeff_unsicherheit.gewicht_gesamt,
            v_koeff_unsicherheit.varianz_gesamt,
            v_koeff_unsicherheit.df
           FROM v_koeff_unsicherheit
        ), eingang AS MATERIALIZED (
         SELECT g_1.gruppe,
            g_1.schluessel,
            sum(b.eingang_kg) AS eingang_kg,
            count(*)::integer AS n_chargen
           FROM gruppen g_1
             JOIN v_kaskade_basis b ON b.charge_nr = g_1.charge_nr
          GROUP BY g_1.gruppe, g_1.schluessel
        ), je_sorte AS MATERIALIZED (
         SELECT zeilen.gruppe,
            zeilen.schluessel,
            zeilen.strom,
            zeilen.buch,
            zeilen.sorte,
            max(zeilen.koeff_art) AS koeff_art,
            sum(zeilen.d_r) AS g_r,
            sum(zeilen.d_a) AS g_a
           FROM zeilen
          WHERE NOT zeilen.erwartet
          GROUP BY zeilen.gruppe, zeilen.schluessel, zeilen.strom, zeilen.buch, zeilen.sorte
        ), je_strom_f AS MATERIALIZED (
         SELECT zeilen.gruppe,
            zeilen.schluessel,
            zeilen.strom,
            zeilen.buch,
            sum(zeilen.d_f * zeilen.f_se) AS g_f,
            min(zeilen.f_n) AS f_n_min
           FROM zeilen
          WHERE NOT zeilen.erwartet
          GROUP BY zeilen.gruppe, zeilen.schluessel, zeilen.strom, zeilen.buch
        ), varianz_r AS MATERIALIZED (
         SELECT s_1.gruppe,
            s_1.schluessel,
            s_1.strom,
            s_1.buch,
            sum(power(s_1.g_r, 2::numeric) * COALESCE(u.varianz_eigen, 0::numeric)) + power(sum(s_1.g_r * COALESCE(u.gewicht_gesamt, 1::numeric)), 2::numeric) * max(COALESCE(u.varianz_gesamt, 0::numeric)) AS varianz,
            min(COALESCE(u.df, 1)) AS df
           FROM je_sorte s_1
             LEFT JOIN unsicherheit u ON u.art = 'verdunstung'::text AND NOT u.sorte IS DISTINCT FROM s_1.sorte
          GROUP BY s_1.gruppe, s_1.schluessel, s_1.strom, s_1.buch
        ), varianz_a AS MATERIALIZED (
         SELECT s_1.gruppe,
            s_1.schluessel,
            s_1.strom,
            s_1.buch,
            sum(power(s_1.g_a, 2::numeric) * COALESCE(u.varianz_eigen, 0::numeric)) + power(sum(s_1.g_a * COALESCE(u.gewicht_gesamt, 1::numeric)), 2::numeric) * max(COALESCE(u.varianz_gesamt, 0::numeric)) AS varianz,
            min(COALESCE(u.df, 1)) AS df
           FROM je_sorte s_1
             LEFT JOIN unsicherheit u ON u.art = s_1.koeff_art AND NOT u.sorte IS DISTINCT FROM s_1.sorte
          WHERE s_1.koeff_art IS NOT NULL
          GROUP BY s_1.gruppe, s_1.schluessel, s_1.strom, s_1.buch
        ), varianz_f AS MATERIALIZED (
         SELECT je_strom_f.gruppe,
            je_strom_f.schluessel,
            je_strom_f.strom,
            je_strom_f.buch,
            power(je_strom_f.g_f, 2::numeric) AS varianz,
            GREATEST(COALESCE(je_strom_f.f_n_min, 2) - 1, 1) AS df
           FROM je_strom_f
        ), summe AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            sum(z.kg) FILTER (WHERE NOT z.erwartet) AS kg,
            bool_and(z.koeff_bekannt) AS bekannt,
            sum(z.kg) FILTER (WHERE z.portion = 'ausgelagert'::text) AS kg_beobachtet,
            sum(z.kg) FILTER (WHERE z.portion = 'lager'::text AND NOT z.erwartet) AS kg_projiziert,
            sum(z.kg) FILTER (WHERE z.f_geliehen AND NOT z.erwartet) AS kg_extrapoliert,
            sum(z.kg) FILTER (WHERE z.erwartet) AS kg_erwartet,
            min(z.koeff_n) AS koeff_n_min,
            sum(z.basis_kg) AS basis_kg,
            max(z.koeff_basis) AS koeff_basis,
            max(z.koeff_art) AS koeff_art,
            max(z.formel) AS formel
           FROM zeilen z
          GROUP BY z.gruppe, z.schluessel, z.strom, z.buch
        )
 SELECT s.gruppe,
    s.schluessel,
    s.strom,
    s.buch,
        CASE
            WHEN s.bekannt THEN zahl(s.kg)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg,
        CASE
            WHEN s.bekannt THEN zahl(GREATEST(s.kg - g.t * g.streuung, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_unten,
        CASE
            WHEN s.bekannt THEN zahl(s.kg + g.t * g.streuung)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_oben,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_beobachtet, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_beobachtet,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_projiziert, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_projiziert,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_extrapoliert, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_extrapoliert,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_erwartet, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_erwartet,
    s.koeff_n_min,
        CASE
            WHEN s.bekannt THEN zahl(g.streuung)
            ELSE NULL::numeric
        END::numeric(14,2) AS streuung_kg,
    g.df,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
    s.koeff_basis,
    s.koeff_art,
    s.formel,
    s.bekannt,
    zahl(e.eingang_kg)::numeric(14,2) AS eingang_kg,
    e.n_chargen
   FROM summe s
     JOIN eingang e ON e.gruppe = s.gruppe AND e.schluessel = s.schluessel
     LEFT JOIN varianz_r vr ON vr.gruppe = s.gruppe AND vr.schluessel = s.schluessel AND vr.strom = s.strom AND vr.buch = s.buch
     LEFT JOIN varianz_a va ON va.gruppe = s.gruppe AND va.schluessel = s.schluessel AND va.strom = s.strom AND va.buch = s.buch
     LEFT JOIN varianz_f vf ON vf.gruppe = s.gruppe AND vf.schluessel = s.schluessel AND vf.strom = s.strom AND vf.buch = s.buch
     CROSS JOIN LATERAL ( SELECT sqrt(GREATEST(COALESCE(vr.varianz, 0::numeric) + COALESCE(va.varianz, 0::numeric) + COALESCE(vf.varianz, 0::numeric), 0::numeric)) AS streuung,
            LEAST(COALESCE(vr.df, 999), COALESCE(va.df, 999), COALESCE(vf.df, 999)) AS df) g0
     CROSS JOIN LATERAL ( SELECT g0.streuung,
            g0.df,
            t_quantil_95(g0.df) AS t) g;
comment on view v_verlust_je_gruppe is
  'Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, Charge). kg_beobachtet ist gemessen, kg_projiziert auf noch nicht Gemessenes übertragen, kg_extrapoliert seit 0106 mit einem aus allen Sorten geliehenen Palox-Anteil gerechnet — drei verschiedene Sicherheiten, darum drei Spalten. Ist der Strom gemessen (bekannt), sind alle vier Teilbeträge Zahlen und kg_beobachtet + kg_projiziert = kg. Das Band kg_unten/kg_oben kommt aus der Unsicherheit der Koeffizienten, beim Faulen aus dem Band des Stationswerts (f_se).';
grant select on v_verlust_je_gruppe to authenticated;


-- ---------- erg_verlust ----------
create materialized view erg_verlust as
 SELECT gruppe,
    schluessel,
    strom,
    buch,
    kg,
    kg_unten,
    kg_oben,
    kg_beobachtet,
    kg_projiziert,
    kg_extrapoliert,
    kg_erwartet,
    koeff_n_min,
    streuung_kg,
    df,
    basis_kg,
    koeff_basis,
    koeff_art,
    formel,
    bekannt,
    eingang_kg,
    n_chargen
   FROM v_verlust_je_gruppe
with no data;
create unique index if not exists erg_verlust_pk on erg_verlust (gruppe, schluessel, strom);
comment on materialized view erg_verlust is
  'v_verlust_je_gruppe, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';
grant select on erg_verlust to authenticated;


-- ---------- v_plausibilitaet ----------
create view v_plausibilitaet with (security_invoker = true) as
 SELECT 'Schimmel'::text AS art,
    b.auftrag_id,
    b.charge_nr,
    b.sorte,
    b.start_ts,
    format('%s kg Schimmel auf %s kg Ware — das wären %s %%'::text, round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100::numeric)) AS befund,
    'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text AS rat
   FROM v_schimmel_beobachtung b
  WHERE b.anteil IS NOT NULL AND NOT b.plausibel AND NOT b.ist_fax AND b.lagertage >= 0::numeric
UNION ALL
 SELECT 'Fax'::text AS art,
    f.auftrag_id,
    f.charge_nr,
    f.sorte,
    f.start_ts,
    format('%s kg Faules bei %s (%s kg) — das wären %s %%'::text, round(f.faul_kg),
        CASE
            WHEN f.paletten_gesamt > 0 THEN f.paletten_gesamt || ' Paletten'::text
            ELSE f.kisten || ' Kisten'::text
        END, round(f.masse_kg), round(f.anteil * 100::numeric)) AS befund,
    'Entweder die Palettenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'::text AS rat
   FROM v_fax_beobachtung f
  WHERE f.anteil IS NOT NULL AND NOT f.plausibel
UNION ALL
 SELECT 'Ausschuss'::text AS art,
    a.auftrag_id,
    a.charge_nr,
    a.sorte,
    NULL::timestamp with time zone AS start_ts,
    format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse'::text, round(COALESCE(a.klein_kg, 0::numeric)), round(COALESCE(a.gross_kg, 0::numeric)), round(a.basis_kg)) AS befund,
    'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'::text AS rat
   FROM v_ausschuss_beobachtung a
  WHERE a.weg = 'hand'::verarbeitungsweg AND NOT a.plausibel
UNION ALL
 SELECT 'Ohne Nenner'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein'::text, concat_ws(' und '::text,
        CASE
            WHEN COALESCE(s.kg, 0::numeric) > 0::numeric THEN round(s.kg) || ' kg Faules'::text
            ELSE NULL::text
        END,
        CASE
            WHEN COALESCE(x.kg, 0::numeric) > 0::numeric THEN round(x.kg) || ' kg zu klein/gross'::text
            ELSE NULL::text
        END),
        CASE
            WHEN a.ist_fax THEN 'keine Palette gezählt oder noch keine fertige Palette dieser Sorte gewogen'::text
            WHEN a.station = 'waschen'::station THEN 'keine Kiste gezählt und keine Menge eingetragen'::text
            WHEN a.station = 'waschen_sortieren'::station THEN 'keine Palette mit Gewicht vom Zettel gezählt'::text
            ELSE 'keine Palette gezählt'::text
        END) AS befund,
        CASE
            WHEN a.ist_fax THEN ('Die Palettenzahl am Ende der Fax-Arbeit eintragen. Fehlt die Palettenmasse, '::text || 'beim Waschen oder Waschen + Sortieren eine fertige Palette wiegen — sie '::text) || 'gilt dann für alle Fax-Arbeiten der Sorte.'::text
            WHEN a.station = 'waschen'::station THEN 'Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich '::text || 'selbst) oder die verarbeitete Menge in kg nachtragen.'::text
            WHEN a.station = 'waschen_sortieren'::station THEN 'Die Paletten mit Datum und Gewicht vom Zettel am Auftrag nachtragen.'::text
            ELSE 'Die gezählten Paletten am Auftrag nachtragen.'::text
        END AS rat
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_schimmel_menge s ON s.auftrag_id = a.id
     LEFT JOIN ( SELECT ausschuss_messung.auftrag_id,
            sum(ausschuss_messung.kg)::numeric AS kg
           FROM ausschuss_messung
          WHERE ausschuss_messung.gemessen
          GROUP BY ausschuss_messung.auftrag_id) x ON x.auftrag_id = a.id
     LEFT JOIN v_auftrag_masse m ON m.auftrag_id = a.id
  WHERE a.abgebrochen_ts IS NULL AND (COALESCE(s.kg, 0::numeric) > 0::numeric OR COALESCE(x.kg, 0::numeric) > 0::numeric) AND COALESCE(m.eingang_netto_kg, 0::numeric) <= 0::numeric
UNION ALL
 SELECT 'Palox'::text AS art,
    s.auftrag_id,
    a.charge_nr,
    c.sorte,
    s.ts AS start_ts,
    format('Waagenstand %s kg liegt unter dem Leergewicht des Palox (%s kg)'::text, s.palox_stand_kg, palox_tara_kg()) AS befund,
    'Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '::text || 'Sonst ist der Stand vertippt.'::text AS rat
   FROM schimmel_messung s
     JOIN auftrag a ON a.id = s.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE s.gemessen AND a.abgebrochen_ts IS NULL AND s.palox_stand_kg IS NOT NULL AND s.palox_stand_kg < palox_tara_kg()
UNION ALL
 SELECT 'Palox geleert'::text AS art,
    p.auftrag_id,
    a.charge_nr,
    c.sorte,
    p.ts AS start_ts,
    format('Der Waagenstand fiel von %s auf %s kg — der Palox wurde zwischendurch geleert. '::text || 'Wie viel davor noch dazukam, weiss niemand; das Faule dieser Arbeit ist unbekannt.'::text, p.vorher, p.palox_stand_kg) AS befund,
    'Nichts zu korrigieren. Beim nächsten Mal in der Checkliste „Palox leeren" drücken: vor dem Leeren ablesen, danach die leere Box — dann bleibt die Menge bekannt.'::text AS rat
   FROM v_palox_stand p
     JOIN auftrag a ON a.id = p.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE p.differenz IS NULL AND a.abgebrochen_ts IS NULL
UNION ALL
 SELECT 'Wägung'::text AS art,
    w.auftrag_id,
    w.charge_nr,
    w.sorte,
    w.wiege_ts AS start_ts,
    ('Palette gewogen, aber '::text ||
        CASE
            WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'für die Gebindeart fehlt die Tara'::text
            WHEN w.lagertage <= 0 THEN 'das Wiegedatum liegt nicht nach dem Eingangsdatum'::text
            WHEN w.netto_damals_kg <= 0::numeric OR w.netto_jetzt_kg <= 0::numeric THEN 'das Netto ist null oder negativ'::text
            WHEN w.netto_jetzt_kg > (w.netto_damals_kg * 1.01) THEN format('sie wiegt jetzt %s kg mehr als beim Eingang, und im Lager wird keine Palette schwerer'::text, round(w.netto_jetzt_kg - w.netto_damals_kg))
            WHEN w.netto_jetzt_kg = w.netto_damals_kg THEN 'sie hat kein Gramm verloren — sehr wahrscheinlich wurde das Eingangsgewicht kopiert (etwa bei einer sortierten Palette, deren Zettelgewicht es nicht gibt)'::text
            ELSE 'sie ist nicht verwertbar'::text
        END) || ' — sie zählt nicht in die Verdunstungsrate'::text AS befund,
        CASE
            WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'Unter Stammdaten → Gebinde die Tara nachtragen.'::text
            WHEN w.netto_jetzt_kg > (w.netto_damals_kg * 1.01) THEN 'Gebindeart, Kistenzahl und beide Gewichte prüfen — meist stimmt die Tara nicht oder eine Zahl ist verdreht.'::text
            ELSE 'Eingangsdatum und Gewichte der Wägung prüfen.'::text
        END AS rat
   FROM v_verdunstung_messung w
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
  WHERE NOT w.verwendbar AND NOT w.sichtbar_schimmel AND COALESCE(w.grund, ''::text) !~~ 'zu schnell%'::text AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
           FROM verdunstung_wiegung v
          WHERE v.id = w.id AND v.gemessen))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN format('%s Kisten nach Sollgewicht gezählt, aber für diese Sorte wurde noch '::text || 'nie eine fertige Palette gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl)
            ELSE format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, g.kaliber_idx + 1)
        END AS befund,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN 'Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '::text || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'::text
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — daraus kennt die App das Kistengewicht des Bandes, rückwirkend für alle Waschgänge dieser Sorte, auch für diesen. Oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx <> '-2'::integer
UNION ALL
 SELECT 'Waage'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
        CASE
            WHEN w.netto_kg <= 0::numeric THEN format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — leichter als ihre Kisten und die Palette (Tara %s kg)'::text, ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(ap.kisten::numeric * g.tara_kg_pro_kiste + g.tara_kg_palette, 1))
            ELSE format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — %s kg je Kiste'::text, ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(w.netto_kg / ap.kisten::numeric, 1))
        END AS befund,
    'Waage, Kistenzahl oder Gebinde prüfen und im Korrekturfenster der Arbeit berichtigen — bis dahin rechnet die Masse dieser Palette mit.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = ap.gebindeart
     CROSS JOIN LATERAL ( SELECT ap.brutto_gewogen_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_kg) w
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL AND ap.brutto_gewogen_kg IS NOT NULL AND ap.kisten IS NOT NULL AND ap.kisten > 0 AND g.tara_kg_pro_kiste IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND (w.netto_kg <= 0::numeric OR (w.netto_kg / ap.kisten::numeric) < 4::numeric OR (w.netto_kg / ap.kisten::numeric) > 30::numeric)
UNION ALL
 SELECT 'Kaliber fehlt'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen'::text AS befund,
    'Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '::text || 'Stammdaten → Sortierschemata.'::text AS rat
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.kaliber_idx IS NULL AND a.kaliber_von_g IS NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM auftrag_gebinde g
          WHERE g.auftrag_id = a.id AND g.anzahl > 0))
UNION ALL
 SELECT 'Ausschuss-Tara'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    m.ts AS start_ts,
    format('%s kg %s gespeichert — aus Brutto %s kg und heutiger Tara wären es %s kg'::text, m.kg,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'zu klein'::text
            ELSE 'zu gross'::text
        END, m.brutto_kg, round(n.roh)) AS befund,
    'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '::text || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
     CROSS JOIN LATERAL ( SELECT m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste -
                CASE
                    WHEN m.mit_palette THEN g.tara_kg_palette
                    ELSE 0::numeric
                END AS roh) n
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND n.roh IS NOT NULL AND m.kg::numeric <> round(n.roh)
UNION ALL
 SELECT 'Ausschuss ohne Tara'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    m.ts AS start_ts,
    format('%s kg %s mit %s kg brutto gespeichert — nachrechnen lässt sich das nicht: %s'::text, m.kg,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'zu klein'::text
            ELSE 'zu gross'::text
        END, m.brutto_kg,
        CASE
            WHEN m.gebindeart IS NULL THEN 'an der Wägung steht keine Gebindeart'::text
            WHEN g.art IS NULL THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN g.tara_kg_pro_kiste IS NULL THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN g.tara_kg_palette IS NULL THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END) AS befund,
    'Die gespeicherten Kilo bleiben, wie sie sind — geprüft werden können sie erst, '::text || 'wenn Gebindeart, Tara und Kistenzahl beisammen sind.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND (m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) IS NULL
UNION ALL
 SELECT 'Zetteldatum'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Zetteldatum %s gezählt, aber an dem Tag kam keine Palette dieser Charge'::text, count(*), to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.eingangsdatum IS NOT NULL AND ap.palette_id IS NULL AND ap.wiegung_id IS NULL AND a.abgebrochen_ts IS NULL AND NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.eingangsdatum = ap.eingangsdatum))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.eingangsdatum
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — %s'::text, count(*), ap.brutto_zettel_kg,
        CASE
            WHEN bool_and(m.masse_quelle = 'gewogen'::text) THEN 'gerechnet wird mit der Wägung der Palette'::text
            WHEN bool_and(m.masse_quelle = 'zettel-kisten'::text) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            WHEN bool_and(m.masse_quelle = ANY (ARRAY['zettel-kisten'::text, 'zettel-kisten-charge'::text, 'gewogen'::text])) THEN 'gerechnet wird mit den gezählten Kisten und der Tara je Kiste der Charge (Zettel − Kisten × Tara je Kiste)'::text
            ELSE 'gerechnet wird mit der mittleren Tara ganzer Paletten der Charge — an der Zählung fehlt die Kistenzahl'::text
        END) AS befund,
    'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal).'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.id = ap.id
  WHERE ap.brutto_zettel_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg
UNION ALL
 SELECT 'Lieferung ohne Eingang'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    min(l.datum)::timestamp with time zone AS start_ts,
    format('%s Lieferung(en) mit %s kg an Charge %s, aber im Wareneingang steht keine Palette dieser Charge'::text, count(*), round(sum(l.masse_kg)), l.charge_nr) AS befund,
    'Wareneingang der Charge nachtragen (Erntejournal) — oder die Lieferung gehört zu einer anderen Charge.'::text AS rat
   FROM v_lieferung_masse l
  WHERE l.buch = 'verkauf'::text AND l.charge_nr IS NOT NULL AND l.masse_kg > 0::numeric AND NOT (EXISTS ( SELECT 1
           FROM v_kohorte_anteil k
          WHERE k.charge_nr = l.charge_nr))
  GROUP BY l.charge_nr, l.sorte
UNION ALL
 SELECT v_plausibilitaet_0054_zusatz.art,
    v_plausibilitaet_0054_zusatz.auftrag_id,
    v_plausibilitaet_0054_zusatz.charge_nr,
    v_plausibilitaet_0054_zusatz.sorte,
    v_plausibilitaet_0054_zusatz.start_ts,
    v_plausibilitaet_0054_zusatz.befund,
    v_plausibilitaet_0054_zusatz.rat
   FROM v_plausibilitaet_0054_zusatz
UNION ALL
 SELECT 'Zetteldatum Zukunft'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Eingangsdatum %s gezählt — das liegt in der Zukunft, sehr wahrscheinlich ein falsches Jahr'::text, count(*), to_char(max(ap.eingangsdatum)::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung korrigieren (Jahr prüfen). Die Beobachtung bleibt gespeichert, bis sie berichtigt ist; solange rechnet die Auswertung sie nicht mit.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.eingangsdatum > heute() AND a.abgebrochen_ts IS NULL
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts
UNION ALL
 SELECT 'Palettengewicht'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    p.eingangsdatum::timestamp with time zone AS start_ts,
    format('Eine Palette mit %s kg brutto — für eine Palette Kürbisse ist das unmöglich'::text, round(p.brutto_kg)) AS befund,
    'Bruttogewicht im Wareneingang prüfen — sehr wahrscheinlich ein Zahlendreher.'::text AS rat
   FROM palette p
     JOIN charge c ON c.nr = p.charge_nr
  WHERE p.brutto_kg > 2000::numeric;
comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette. 0066: „Ausschuss-Tara" rechnet nur nach, wo Kistenzahl und hinterlegte Tara da sind; fehlt eine, steht die Lücke als „Ausschuss ohne Tara" daneben. 0087: die Nachrechnung zieht die Palette nur ab, wenn sie mitgewogen wurde, und klemmt nichts auf null. 0114: eine zu schnell leichter gewordene Wägung steht nur als „Verdunstung" da, nicht noch einmal als „Wägung".';
grant select on v_plausibilitaet to authenticated;


-- ---------- v_marge_buch ----------
create view v_marge_buch with (security_invoker = true) as
 WITH verkauf AS (
         SELECT sum(v_ueberfuellung_verkauf.verschenkt_kg) AS verschenkt_kg,
            sum(
                CASE
                    WHEN v_ueberfuellung_verkauf.verschenkt_kg IS NULL THEN NULL::numeric
                    ELSE GREATEST(v_ueberfuellung_verkauf.verschenkt_kg - COALESCE(v_ueberfuellung_verkauf.verschenkt_fehler_kg, 0::numeric), 0::numeric)
                END) AS verschenkt_unten_kg,
            sum(v_ueberfuellung_verkauf.verschenkt_kg + COALESCE(v_ueberfuellung_verkauf.verschenkt_fehler_kg, 0::numeric)) AS verschenkt_oben_kg,
            sum(v_ueberfuellung_verkauf.kisten_verkauft) FILTER (WHERE v_ueberfuellung_verkauf.n_wiegungen > 0) AS kisten_gerechnet,
            sum(v_ueberfuellung_verkauf.kisten_verkauft) FILTER (WHERE v_ueberfuellung_verkauf.n_wiegungen = 0) AS kisten_ungewogen,
            sum(v_ueberfuellung_verkauf.n_wiegungen) AS n_wiegungen,
            sum(v_ueberfuellung_verkauf.kisten_gewogen) AS kisten_gewogen,
            sum(v_ueberfuellung_verkauf.zuviel_je_kiste * v_ueberfuellung_verkauf.kisten_gewogen::numeric) / NULLIF(sum(v_ueberfuellung_verkauf.kisten_gewogen) FILTER (WHERE v_ueberfuellung_verkauf.zuviel_je_kiste IS NOT NULL), 0::numeric) AS zuviel_je_kiste,
            count(*) FILTER (WHERE v_ueberfuellung_verkauf.n_lieferungen > 0)::integer AS n_gruppen_verkauft
           FROM v_ueberfuellung_verkauf
          WHERE v_ueberfuellung_verkauf.gruppe = 'sorte'::text AND v_ueberfuellung_verkauf.kistensystem = 'kiste_ab'::text
        ), datei AS (
         SELECT count(*)::integer AS n
           FROM lieferung_import
        )
 SELECT r.strom AS posten,
    r.kg,
    r.kg_unten,
    r.kg_oben,
        CASE r.strom
            WHEN 'Nebenkanal zu gross'::text THEN 'Ware über der oberen Kalibergrenze geht in einen anderen Verkaufskanal — nicht weg, nur nicht zum besten Preis'::text
            WHEN 'Zu klein (Tierfutter)'::text THEN 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'::text
            ELSE ''::text
        END AS erlaeuterung,
    r.kg IS NOT NULL AS gemessen
   FROM erg_verlust r
  WHERE r.gruppe = 'gesamt'::text AND r.buch = 'marge'::text
UNION ALL
 SELECT 'Überfüllung der Kisten'::text AS posten,
    zahl(v.verschenkt_kg)::numeric(14,2) AS kg,
    zahl(v.verschenkt_unten_kg)::numeric(14,2) AS kg_unten,
    zahl(v.verschenkt_oben_kg)::numeric(14,2) AS kg_oben,
        CASE
            WHEN d.n = 0 THEN 'Keine Verkaufsdatei eingelesen — wie viele Kisten „ab x kg" verkauft wurden, weiss die App nicht. Nichts gerechnet.'::text
            WHEN COALESCE(v.n_wiegungen, 0::bigint) = 0 THEN format('%s Kisten „ab x kg" laut Verkaufsdatei verkauft, aber keine fertige Palette dieses Systems gewogen — nichts gerechnet.'::text, round(COALESCE(v.kisten_ungewogen, 0::numeric)))
            ELSE format(('%s gewogene Paletten (%s Kisten): im Schnitt %s kg je Kiste über dem Soll. '::text || 'Verkauft laut Verkaufsdatei: %s Kisten desselben Systems — daraus die Zahl. '::text) || '%s'::text, v.n_wiegungen, round(COALESCE(v.kisten_gewogen, 0::numeric)), round(COALESCE(v.zuviel_je_kiste, 0::numeric), 3), round(COALESCE(v.kisten_gerechnet, 0::numeric)),
            CASE
                WHEN COALESCE(v.kisten_ungewogen, 0::numeric) > 0::numeric THEN format('Weitere %s verkaufte Kisten haben kein gewogenes Gegenstück (Sorte oder Soll ohne Wägung) und sind nicht gerechnet.'::text, round(v.kisten_ungewogen))
                ELSE 'Kisten nach Stück haben kein Sollgewicht und damit keine Überfüllung.'::text
            END)
        END AS erlaeuterung,
    v.verschenkt_kg IS NOT NULL AS gemessen
   FROM verkauf v
     CROSS JOIN datei d;
comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb verlassen hat, ohne verkaufsfähig zu sein — zu klein, Nebenkanal, Überfüllung. Kein Verlust im Sinne von verdorben, sondern Masse in einem anderen Kanal. kg_unten und kg_oben spannen den Bereich auf, gemessen sagt, ob dahinter Messungen oder Schätzungen stehen.';
grant select on v_marge_buch to authenticated;


-- ---------- v_saisonbilanz ----------
create view v_saisonbilanz with (security_invoker = true) as
 WITH charge AS (
         SELECT sum(erg_charge.eingang_kg) AS eingang_kg,
            sum(erg_charge.ausgelagert_kg) AS ausgelagert_kg,
            sum(erg_charge.geliefert_kg) AS geliefert_kg,
            sum(erg_charge.lager_kg) AS lager_kg,
            sum(erg_charge.wartet_kg) AS wartet_kg,
            sum(erg_charge.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(erg_charge.verkaufsfaehig_lager_kg) AS verkaufsfaehig_heute_kg,
            sum(erg_charge.im_haus_heute_kg) AS im_haus_heute_kg,
            sum(erg_charge.kanal_im_haus_kg) AS kanal_im_haus_kg,
            sum(erg_charge.verlust_heute_kg) AS verlust_heute_kg,
            sum(erg_charge.verdunstung_heute_kg) AS verdunstung_heute_kg,
            sum(erg_charge.schimmel_heute_kg) AS schimmel_heute_kg,
            sum(erg_charge.fax_heute_kg) AS fax_heute_kg,
            sum(erg_charge.fax_erwartet_kg) AS fax_erwartet_kg,
            sum(erg_charge.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            bool_and(erg_charge.verlust_bekannt) AS bekannt,
            count(*)::integer AS n_chargen,
            max(erg_charge.heute) AS heute
           FROM erg_charge
        ), bereich AS (
         SELECT sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_oben_kg,
            sum(erg_verlust.kg) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_kg,
            sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = 'marge'::text) AS kanal_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = 'marge'::text) AS kanal_oben_kg
           FROM erg_verlust
          WHERE erg_verlust.gruppe = 'gesamt'::text
        ), vorlauf AS (
         SELECT COALESCE(sum(charge_vorlauf.ausgang_vor_app_kg), 0::numeric) AS kg
           FROM charge_vorlauf
        ), ausgang AS (
         SELECT COALESCE(sum(v_lieferung_masse.masse_kg), 0::numeric) AS kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'verkauf'::text), 0::numeric) AS verkauf_kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'marge'::text), 0::numeric) AS marge_kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'verlust'::text), 0::numeric) AS entsorgt_kg,
            COALESCE(sum(v_lieferung_masse.masse_fehler_kg), 0::double precision) AS fehler_kg,
            count(*)::integer AS n_lieferungen,
            max(v_lieferung_masse.datum) AS letzte_lieferung
           FROM v_lieferung_masse
          WHERE v_lieferung_masse.datum <= heute()
        ), fax AS (
         SELECT COALESCE(sum(v_fax_beobachtung.masse_kg), 0::numeric) AS kg,
            count(*)::integer AS n
           FROM v_fax_beobachtung
          WHERE v_fax_beobachtung.status = 'abgeschlossen'::auftrag_status AND v_fax_beobachtung.masse_kg IS NOT NULL
        )
 SELECT c.heute,
    zahl(c.eingang_kg)::numeric(14,2) AS eingang_kg,
    c.n_chargen,
    zahl(a.kg + vl.kg)::numeric(14,2) AS ausgang_kg,
    zahl(a.verkauf_kg)::numeric(14,2) AS verkauf_kg,
    zahl(a.marge_kg)::numeric(14,2) AS marge_kg,
    zahl(a.entsorgt_kg)::numeric(14,2) AS entsorgt_kg,
    zahl(a.fehler_kg)::numeric(14,2) AS ausgang_fehler_kg,
    a.n_lieferungen,
    a.letzte_lieferung,
    zahl(vl.kg)::numeric(14,2) AS vorlauf_kg,
    zahl(c.geliefert_kg)::numeric(14,2) AS geliefert_kg,
    zahl(c.ausgelagert_kg)::numeric(14,2) AS ausgelagert_kg,
    zahl(c.verlust_heute_kg)::numeric(14,2) AS verlust_heute_kg,
    zahl(b.verlust_unten_kg)::numeric(14,2) AS verlust_unten_kg,
    zahl(b.verlust_oben_kg)::numeric(14,2) AS verlust_oben_kg,
    zahl(c.verdunstung_heute_kg)::numeric(14,2) AS verdunstung_heute_kg,
    zahl(c.schimmel_heute_kg)::numeric(14,2) AS schimmel_heute_kg,
    zahl(c.fax_heute_kg)::numeric(14,2) AS fax_heute_kg,
    zahl(c.fax_erwartet_kg)::numeric(14,2) AS fax_erwartet_kg,
    zahl(c.kanal_ausgelagert_kg)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(b.kanal_unten_kg)::numeric(14,2) AS kanal_unten_kg,
    zahl(b.kanal_oben_kg)::numeric(14,2) AS kanal_oben_kg,
    zahl(c.im_haus_heute_kg)::numeric(14,2) AS im_haus_heute_kg,
    zahl(c.verkaufsfaehig_heute_kg)::numeric(14,2) AS verkaufsfaehig_heute_kg,
    zahl(c.kanal_im_haus_kg)::numeric(14,2) AS kanal_im_haus_kg,
    zahl(c.lager_kg)::numeric(14,2) AS lager_kg,
    zahl(c.wartet_kg)::numeric(14,2) AS gegenprobe_wartet_kg,
    zahl(c.ueberzaehlung_kg)::numeric(14,2) AS ueberzaehlung_kg,
    zahl(f.kg)::numeric(14,2) AS fax_durchsatz_kg,
    f.n AS n_fax_arbeiten,
    COALESCE(c.bekannt, false) AS verlust_bekannt,
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.im_haus_heute_kg)::numeric(14,2) AS bilanz_rest_kg,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.im_haus_heute_kg) / c.eingang_kg
            ELSE NULL::numeric
        END, 4, '100000'::numeric)::numeric(10,4) AS bilanz_rest_anteil,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (a.kg + vl.kg) / c.eingang_kg
            ELSE NULL::numeric
        END, 4, '100000'::numeric)::numeric(10,4) AS ausgang_deckung,
        CASE
            WHEN COALESCE(c.eingang_kg, 0::numeric) <= 0::numeric THEN 'Es ist kein Wareneingang erfasst. Ohne das Erntejournal gibt es '::text || 'nichts, worauf sich Verlust und Bestand beziehen könnten.'::text
            WHEN COALESCE(c.ueberzaehlung_kg, 0::numeric) > (0.05 * c.eingang_kg) THEN format((('Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — '::text || 'bei einigen Chargen rund %s kg zu viel. Fast immer fehlt der '::text) || 'Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine '::text) || 'Lieferung ist der falschen Charge zugeordnet.'::text, round(c.ueberzaehlung_kg))
            WHEN a.n_lieferungen = 0 AND vl.kg = 0::numeric THEN ('Kein Warenausgang erfasst — dann liegt rechnerisch noch alles im Haus, '::text || 'und der Verlust bis heute gilt für die ganze Eingangsmasse. Sobald die '::text) || 'Lieferscheine eingelesen sind, teilt sich die Ware in ausgeliefert und liegend.'::text
            WHEN NOT COALESCE(c.bekannt, false) THEN 'Ein Verluststrom ist noch nicht gemessen — die Ursachen sind erst '::text || 'vollständig, wenn jeder Koeffizient mindestens eine Messung hat.'::text
            ELSE format((('Bis heute (%s): %s t Eingang = %s t ausgeliefert + %s t Verlust '::text || '(Verdunstung %s t, Faules %s t, Fax %s t) '::text) || '+ %s t noch im Haus (davon %s t verkaufsfähig, %s t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum '::text) || 'Saisonende steht in der Grafik, nicht in diesen Zahlen.%s'::text, to_char(c.heute::timestamp with time zone, 'DD.MM.YYYY'::text), round(c.eingang_kg / 1000.0, 1), round(c.geliefert_kg / 1000.0, 1), round(c.verlust_heute_kg / 1000.0, 1), round(c.verdunstung_heute_kg / 1000.0, 1), round(c.schimmel_heute_kg / 1000.0, 1), round(c.fax_heute_kg / 1000.0, 1), round(c.im_haus_heute_kg / 1000.0, 1), round(c.verkaufsfaehig_heute_kg / 1000.0, 1), round((c.kanal_ausgelagert_kg + c.kanal_im_haus_kg) / 1000.0, 1), concat_ws(' '::text, '',
            CASE
                WHEN a.marge_kg > 0::numeric THEN format('An die Tiere und in den Nebenkanal geliefert: %s kg; hinter den Lieferungen aussortiert gerechnet: %s kg.'::text, round(a.marge_kg), round(c.kanal_ausgelagert_kg))
                ELSE NULL::text
            END,
            CASE
                WHEN a.entsorgt_kg > 0::numeric THEN format('Entsorgt: %s kg, gerechneter Schimmel: %s kg.'::text, round(a.entsorgt_kg), round(c.schimmel_heute_kg))
                ELSE NULL::text
            END,
            CASE
                WHEN COALESCE(c.ueberzaehlung_kg, 0::numeric) > 0::numeric THEN format('%s kg Überzählung.'::text, round(c.ueberzaehlung_kg))
                ELSE NULL::text
            END))
        END AS befund
   FROM charge c
     CROSS JOIN bereich b
     CROSS JOIN ausgang a
     CROSS JOIN vorlauf vl
     CROSS JOIN fax f;
comment on view v_saisonbilanz is
  'Die Saison bis heute in einer Zeile (erg_bilanz). Seit 0101: Eingang + Überzählung = ausgeliefert (Lieferscheine) + Verlust bis heute + im Haus — zu klein und zu gross sind Teil von im Haus (kanal_ausgelagert_kg aussortiert, kanal_im_haus_kg im Liegenden erwartet), nicht Ausgang. Seit 0106 ohne Sockel.';
grant select on v_saisonbilanz to authenticated;


-- ---------- v_wohin ----------
create view v_wohin with (security_invoker = true) as
 WITH gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'sorte'::text AS text,
            erg_charge.sorte,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'schlag'::text AS text,
            erg_charge.schlag,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'charge'::text AS text,
            erg_charge.charge_nr::text AS charge_nr,
            erg_charge.charge_nr
           FROM erg_charge
        ), charge AS (
         SELECT g.gruppe,
            g.schluessel,
            count(*)::integer AS n_chargen,
            sum(c_1.eingang_kg) AS eingang_kg,
            sum(c_1.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(c_1.geliefert_kg) AS geliefert_kg,
            sum(c_1.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            sum(c_1.fax_heute_kg) AS fax_kg,
            sum(c_1.im_haus_heute_kg) AS lager_gute_ware_kg,
            sum(c_1.verkaufsfaehig_lager_kg) AS lager_verkaufsfaehig_kg,
            sum(c_1.kanal_im_haus_kg) AS lager_kanal_kg,
            sum(c_1.fax_erwartet_kg) AS lager_fax_kg,
            sum(c_1.lager_kg) AS lager_kg,
            bool_and(c_1.verlust_bekannt) AS vollstaendig
           FROM gruppen g
             JOIN erg_charge c_1 ON c_1.charge_nr = g.charge_nr
          GROUP BY g.gruppe, g.schluessel
        ), stroeme AS (
         SELECT erg_verlust.gruppe,
            erg_verlust.schluessel,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Verdunstung'::text) AS verdunstet_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Verdunstung'::text) AS lager_verdunstet_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Schimmel/Fäulnis'::text) AS faul_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Schimmel/Fäulnis'::text) AS lager_faul_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Zu klein (Tierfutter)'::text) AS klein_ausgelagert_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Nebenkanal zu gross'::text) AS gross_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Zu klein (Tierfutter)'::text) AS lager_klein_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Nebenkanal zu gross'::text) AS lager_gross_kg
           FROM erg_verlust
          GROUP BY erg_verlust.gruppe, erg_verlust.schluessel
        )
 SELECT c.gruppe,
    c.schluessel,
    c.n_chargen,
    zahl(c.eingang_kg)::numeric(14,2) AS eingang_kg,
    zahl(c.ueberzaehlung_kg)::numeric(14,2) AS ueberzaehlung_kg,
    zahl(c.geliefert_kg)::numeric(14,2) AS geliefert_kg,
    zahl(c.kanal_ausgelagert_kg)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(s.klein_ausgelagert_kg)::numeric(14,2) AS klein_ausgelagert_kg,
    zahl(s.gross_ausgelagert_kg)::numeric(14,2) AS gross_ausgelagert_kg,
    zahl(s.verdunstet_ausgelagert_kg)::numeric(14,2) AS verdunstet_ausgelagert_kg,
    zahl(s.faul_ausgelagert_kg)::numeric(14,2) AS faul_ausgelagert_kg,
    zahl(c.fax_kg)::numeric(14,2) AS fax_kg,
    zahl(c.lager_kg)::numeric(14,2) AS lager_kg,
    zahl(c.lager_gute_ware_kg)::numeric(14,2) AS lager_gute_ware_kg,
    zahl(c.lager_verkaufsfaehig_kg)::numeric(14,2) AS lager_verkaufsfaehig_kg,
    zahl(c.lager_kanal_kg)::numeric(14,2) AS lager_kanal_kg,
    zahl(s.lager_klein_kg)::numeric(14,2) AS lager_klein_kg,
    zahl(s.lager_gross_kg)::numeric(14,2) AS lager_gross_kg,
    zahl(c.lager_fax_kg)::numeric(14,2) AS lager_fax_kg,
    zahl(s.lager_faul_kg)::numeric(14,2) AS lager_faul_kg,
    zahl(s.lager_verdunstet_kg)::numeric(14,2) AS lager_verdunstet_kg,
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.kanal_ausgelagert_kg - s.verdunstet_ausgelagert_kg - s.faul_ausgelagert_kg - c.fax_kg - c.lager_kg)::numeric(14,2) AS rest_kg,
    zahl(c.lager_kg - c.lager_verkaufsfaehig_kg - c.lager_kanal_kg - c.lager_fax_kg - s.lager_faul_kg - s.lager_verdunstet_kg)::numeric(14,2) AS lager_rest_kg,
    c.vollstaendig
   FROM charge c
     LEFT JOIN stroeme s ON s.gruppe = c.gruppe AND s.schluessel = c.schluessel;
comment on view v_wohin is
  'Wohin ging der Kürbis — je Gruppe (gesamt, Sorte, Schlag, Charge) der ganze Eingang aufgeteilt: ausgeliefert, anderer Kanal, verdunstet und faul an der ausgelieferten Ware, Faules beim Abpacken, und was noch liegt (davon verkaufsfähig, Kanal, Fax erwartet, faul, verdunstet). rest_kg und lager_rest_kg sind die zwei Identitäten: beide haben den Erwartungswert null, und eine doppelt gezählte Portion bliebe darin stehen. Seit 0106 ohne Sockel.';
grant select on v_wohin to authenticated;


-- ---------- erg_wohin ----------
create materialized view erg_wohin as
 SELECT gruppe,
    schluessel,
    n_chargen,
    eingang_kg,
    ueberzaehlung_kg,
    geliefert_kg,
    kanal_ausgelagert_kg,
    klein_ausgelagert_kg,
    gross_ausgelagert_kg,
    verdunstet_ausgelagert_kg,
    faul_ausgelagert_kg,
    fax_kg,
    lager_kg,
    lager_gute_ware_kg,
    lager_verkaufsfaehig_kg,
    lager_kanal_kg,
    lager_klein_kg,
    lager_gross_kg,
    lager_fax_kg,
    lager_faul_kg,
    lager_verdunstet_kg,
    rest_kg,
    lager_rest_kg,
    vollstaendig
   FROM v_wohin
with no data;
create unique index if not exists erg_wohin_pk on erg_wohin (gruppe, schluessel);
comment on materialized view erg_wohin is
  'v_wohin, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';
grant select on erg_wohin to authenticated;


-- ---------- die fünf gespeicherten Ergebnisse aus der Schleife ----------
-- Wie in 0111: „drop … cascade" oben hat sie mitgerissen; dieselbe Schleife
-- baut sie wieder.
-- verdichter: baut erg_bilanz erg_marge erg_massenbilanz erg_naechste_charge erg_plausibilitaet
do $$
declare
  paar text[];
  paare text[][] := array[
    ['erg_bilanz',          'v_saisonbilanz'],
    ['erg_marge',           'v_marge_buch'],
    ['erg_massenbilanz',    'v_massenbilanz'],
    ['erg_naechste_charge', 'v_naechste_charge'],
    ['erg_plausibilitaet',  'v_plausibilitaet']
  ];
begin
  foreach paar slice 1 in array paare loop
    execute format('drop materialized view if exists %I cascade', paar[1]);
    execute format('create materialized view %I as select * from %I with no data', paar[1], paar[2]);
    execute format('grant select on %I to authenticated', paar[1]);
    execute format('comment on materialized view %I is %L', paar[1],
                   format('%s, gespeichert für die App Erneuert mit auswertung_schritt().', paar[2]));
  end loop;
end $$;

-- =====================================================================
-- 7. Der Rechenschritt: die Verteilung vor der Kaskade
-- =====================================================================
CREATE OR REPLACE FUNCTION public.auswertung_schritt_intern(p_schritt integer, p_nebenlaeufig boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
  v_ausdruck text;
  v_eindeutig boolean;
  v_gefuellt boolean;
  v_seit timestamptz;
  v_t timestamptz;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- Je Aufruf eine Beratungssperre (0100): zwei Erneuerungen derselben
  -- Ansicht zur selben Sekunde gibt es nicht. Im Zeitplan-Weg hält der
  -- ganze Lauf sie (eine Transaktion); ein Schritt aus der App, der sie
  -- nicht bekommt, geht sofort mit „wartet".
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return jsonb_build_object('schritt', p_schritt, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                              'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true,
                              'rechnet_seit', (select rechnet_seit from auswertung_stand where id = 1));
  end if;
  -- Der App-Weg (fünf einzelne Aufrufe, je eine Transaktion) merkt sich in
  -- rechnet_seit, dass er läuft (0100). Der Zeitplan-Weg tut das nicht: Ein
  -- Update hier hielte die Zeile bis zum Ende des Laufs gesperrt, und jedes
  -- „Neu rechnen" bliebe daran hängen (0103).
  if p_schritt = 1 and not p_nebenlaeufig then
    update auswertung_stand
       set rechnet_seit = clock_timestamp()
     where id = 1 and (rechnet_seit is null or rechnet_seit < clock_timestamp() - interval '15 minutes')
    returning rechnet_seit into v_seit;
    if v_seit is null then
      select rechnet_seit into v_seit from auswertung_stand where id = 1;
      return jsonb_build_object('schritt', 1, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                                'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true, 'rechnet_seit', v_seit);
    end if;
  end if;
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'erg_punkte',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_fax', 'erg_koeff_ueberfuellung', 'mv_koeff_rand',
                       'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_fax_wartezeit', 'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      -- 0116: die Gewichtsverteilung beim Eingang vor der Kaskade, die sie liest.
      v_namen := array['erg_palox_erwartung', 'mv_kaliber_eingang', 'mv_kaliber_quelle', 'mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_prognose', 'erg_wohin', 'erg_verlauf', 'erg_bilanz',
                       'erg_marge', 'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage',
                       'erg_marge_wiegung', 'erg_marge_charge'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  if p_schritt = 1 then
    for v_name in
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
    delete from auswertung_laufzeit where ts < clock_timestamp() - interval '7 days';
  end if;

  foreach v_name in array v_namen loop
    v_t := clock_timestamp();
    v_eindeutig := false;
    if p_nebenlaeufig then
      select s.ausdruck into v_ausdruck from auswertung_schluessel() s where s.sicht = v_name;
      select c.relispopulated into v_gefuellt from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_name;
      if v_ausdruck is not null and coalesce(v_gefuellt, false) then
        begin
          if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indrelid
                          where c.relname = v_name and i.indisunique and i.indexprs is null and i.indpred is null) then
            execute format('create unique index %I on %I (%s) nulls not distinct', v_name || '_eindeutig', v_name, v_ausdruck);
          end if;
          v_eindeutig := true;
        exception when others then
          raise notice 'auswertung_schritt: % bekommt keinen eindeutigen Index (%) — wird normal erneuert', v_name, sqlerrm;
        end;
      end if;
    end if;
    if v_eindeutig then
      begin
        execute format('refresh materialized view concurrently %I', v_name);
      exception when others then
        raise notice 'auswertung_schritt: % nicht nebenläufig erneuert (%) — normal erneuert', v_name, sqlerrm;
        execute format('refresh materialized view %I', v_name);
      end;
    else
      execute format('refresh materialized view %I', v_name);
    end if;
    execute format('analyze %I', v_name);
    -- 0103: Wo die Minuten hingehen, sagt jeder Lauf selbst.
    insert into auswertung_laufzeit (schritt, sicht, nebenlaeufig, dauer_ms)
    values (p_schritt, v_name, v_eindeutig, (extract(epoch from clock_timestamp() - v_t) * 1000)::int);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),
           rechnet_seit = null,
           dauer_ms = case when p_nebenlaeufig then null else coalesce(dauer_ms, 0) end
                      + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif not p_nebenlaeufig then
    if p_schritt = 1 then
      update auswertung_stand
         set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
       where id = 1;
    else
      update auswertung_stand
         set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
       where id = 1;
    end if;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5, 'nebenlaeufig', p_nebenlaeufig, 'wartet', false);
end $function$;
comment on function auswertung_schritt_intern(integer, boolean) is
  'Ein Schritt des Neurechnens (0078), wahlweise nebenläufig (0095). Beratungssperre je Aufruf (0100); der App-Weg merkt '
  'sich rechnet_seit, der Zeitplan-Weg fasst auswertung_stand erst am Ende an; je Ansicht wird die Dauer notiert '
  '(auswertung_laufzeit, 0103). Schritt 3 rechnet seit 0107 auch erg_palox_erwartung, seit 0116 vor der Kaskade die Gewichtsverteilung beim Eingang (mv_kaliber_eingang, mv_kaliber_quelle). Nur für den Betriebsleiter oder ohne Anmeldung.';

-- =====================================================================
-- 8. Perigon: die ganze Zeile, die Positionen je Kunde, mehr Prüfungen
-- =====================================================================
-- 8a. Die ganze Zeile an der Position — „eine Replika der Excel-Zeile, alle
--     Spalten". Die App schickt sie mit (positionen[].roh); geschrieben bei
--     jedem Einlesen, auch für schon bekannte Positionen.
create or replace function ausgang_historie_uebernehmen(p_quelle text, p_positionen jsonb, p_lose jsonb default '[]'::jsonb)
returns jsonb language plpgsql security invoker set search_path = public as $fn$
declare
  v_pos  int := 0;
  v_lose int := 0;
  v_saisons jsonb;
begin
  if not ist_admin() then
    raise exception 'Den Warenausgang übernimmt nur der Betriebsleiter.';
  end if;
  if not exists (select 1 from ausgang_quelle where code = p_quelle) then
    raise exception 'Die Firma „%" ist noch nicht angelegt — zuerst den Warenausgang übernehmen.', p_quelle;
  end if;

  with eingang as (
    select * from jsonb_to_recordset(coalesce(p_positionen, '[]'::jsonb)) as x(
      pos_id bigint, datum date, journal text, kunde text, artikel_id text, artikel text,
      preisgruppe text, einheit text, menge numeric, gewicht_je_artikel numeric,
      gebindeart text, gebinde_menge numeric, roh jsonb)
  ), geschrieben as (
    insert into ausgang_position (quelle, pos_id, datum, saison, journal, kunde, artikel_id, artikel, preisgruppe,
                                  einheit, menge, gewicht_je_artikel, kg, gebindeart, gebinde_menge, roh)
    select p_quelle, e.pos_id, e.datum, saison_von(e.datum), e.journal, e.kunde, e.artikel_id, e.artikel,
           nullif(e.preisgruppe, ''), e.einheit, e.menge, e.gewicht_je_artikel,
           perigon_kg(coalesce(e.menge, 0), e.gewicht_je_artikel, e.einheit), nullif(e.gebindeart, ''),
           round(e.gebinde_menge)::int, e.roh
      from eingang e
     where e.pos_id is not null and e.datum is not null and e.artikel_id is not null and e.artikel is not null
    on conflict (quelle, pos_id) do update
      set datum = excluded.datum, saison = excluded.saison, journal = excluded.journal, kunde = excluded.kunde,
          artikel_id = excluded.artikel_id, artikel = excluded.artikel, preisgruppe = excluded.preisgruppe,
          einheit = excluded.einheit, menge = excluded.menge, gewicht_je_artikel = excluded.gewicht_je_artikel,
          kg = excluded.kg, gebindeart = excluded.gebindeart, gebinde_menge = excluded.gebinde_menge,
          -- 0116: die ganze Zeile; eine Datei ohne sie (ältere App) lässt die gespeicherte stehen.
          roh = coalesce(excluded.roh, ausgang_position.roh), ts = now()
    returning saison
  )
  select coalesce(jsonb_object_agg(s.saison::text, s.n), '{}'::jsonb), coalesce(sum(s.n), 0)::int
    into v_saisons, v_pos
    from (select saison, count(*)::int as n from geschrieben group by saison) s;

  -- Die Labels an die Zeilen der laufenden Saison (die Bilanz-Zeilen).
  with lose as (
    select * from jsonb_to_recordset(coalesce(p_lose, '[]'::jsonb)) as x(
      pos_id bigint, charge_extern text, lauf_nr int, liefer_label text, preisgruppe text)
  ), gesetzt as (
    update ausgang_zeile z
       set liefer_label = nullif(l.liefer_label, ''), preisgruppe = nullif(l.preisgruppe, '')
      from lose l
     where z.quelle = p_quelle and z.pos_id = l.pos_id
       and z.charge_extern = coalesce(l.charge_extern, '') and z.lauf_nr = coalesce(l.lauf_nr, 1)
       and (z.liefer_label is distinct from nullif(l.liefer_label, '')
            or z.preisgruppe is distinct from nullif(l.preisgruppe, ''))
    returning 1
  )
  select count(*) into v_lose from gesetzt;

  return jsonb_build_object('positionen', v_pos, 'je_saison', v_saisons, 'labels_gesetzt', v_lose);
end $fn$;
comment on function ausgang_historie_uebernehmen(text, jsonb, jsonb) is
  'Schreibt beim Einlesen der Perigon-Datei jede Position aller Saisons nach ausgang_position und die Labels (LiefPrsGrpName, Preisgruppe) an die Zeilen der laufenden Saison (0112). Die Masse nach perigon_kg (0115): bei kg-Artikeln ohne Gewicht je Artikel die Menge, bei Stück ohne Stückgewicht leer. Seit 0116 mit der ganzen Zeile der Datei (roh), für die Anzeige in der App. Nur der Betriebsleiter.';
revoke all on function ausgang_historie_uebernehmen(text, jsonb, jsonb) from public;
grant execute on function ausgang_historie_uebernehmen(text, jsonb, jsonb) to authenticated;

-- 8b. Die Positionen je Kunde, eingeordnet wie v_kunde_tag — für die Liste
--     „alle Verkäufe dieses Kunden" unter dem Kundendiagramm.
create or replace view v_kunde_position with (security_invoker = true) as
select v.quelle, v.pos_id, v.kunde, v.saison, v.datum, e.gruppe, e.groesse, e.label,
       v.artikel_id, v.artikel, v.preisgruppe, v.menge, v.einheit, v.kg, v.herkunft
  from v_verkauf_position v
  left join ausgang_artikel a on a.artikel_id = v.artikel_id and a.artikel = v.artikel
 cross join lateral artikel_einordnen(v.artikel, v.preisgruppe) e
 where coalesce(v.journal, '') <> 'L'
   and coalesce(a.ist_kuerbis, ist_kuerbis_vorschlag(v.artikel_id, v.artikel))
   and v.kunde is not null and v.kunde <> '';
comment on view v_kunde_position is
  'Jede Kürbis-Position je Kunde (0116), eingeordnet nach Artikelgruppe, Grösse und Label — dieselbe Auswahl wie v_kunde_tag, nur nicht zusammengezählt. Für die Liste der Lieferungen eines Kunden; die ganze Zeile steht in ausgang_position.roh.';
grant select on v_kunde_position to authenticated;

-- 8c. Was beim Durchsehen der Perigon-Dateien auffällt — je Zeile der
--     laufenden Saison, mit dem Satz, was zu tun ist. „Als Demeter verkauft,
--     als Knospe geliefert" stand schon je Charge da (0113); dazu kommen:
--     eine Charge, die Perigon nennt, die Lieferung aber nicht trägt; ein
--     Artikel, dessen Gruppe nicht zur Sorte der gelieferten Charge passt;
--     eine Lieferung vor dem ersten Eingang ihrer Charge.
create or replace view v_perigon_pruefung with (security_invoker = true) as
with zeile as (
  select z.id, z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_extern, z.kg_charge, z.liefer_label,
         l.id as lieferung_id, l.charge_nr, c.sorte, sk.artikelgruppe as gruppe_charge,
         e.gruppe as gruppe_artikel, e.label as label_verkauft,
         case when upper(coalesce(z.liefer_label, '')) like 'D%' then 'D'
              when upper(coalesce(z.liefer_label, '')) ~ '^(K|CH-K)' then 'K' end as label_geliefert
    from ausgang_zeile z
    join lieferung_import li on li.zeile_id = z.id
    join lieferung l on l.id = li.lieferung_id
    left join charge c on c.nr = l.charge_nr
    left join sorte_kaliber sk on sk.sorte = c.sorte
   cross join lateral artikel_einordnen(z.artikel, z.preisgruppe) e
)
select 'Charge nicht zugeordnet'::text as art, z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge as kg,
       format('Perigon nennt die Charge %s, die Lieferung hat keine — %s', z.charge_extern,
              case when exists (select 1 from charge x where x.nr::text = regexp_replace(z.charge_extern, '\D', '', 'g'))
                   then 'die Charge gibt es; die Datei unter Betrieb → Warenausgang neu einlesen'
                   when (select count(*) from charge x where x.perigon_nr::text = regexp_replace(z.charge_extern, '\D', '', 'g')) > 1
                   then 'die Perigon-Nummer steht an mehreren Chargen, und der Artikel sagt nicht, welche Sorte'
                   else 'die Nummer kennt die App nicht; unter Stammdaten → Chargen anlegen, dann neu einlesen' end) as befund
  from zeile z
 where z.charge_extern <> '' and z.charge_nr is null
union all
select 'Artikel passt nicht zur Sorte', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge,
       format('als %s verkauft, geliefert aus Charge %s (%s, geht als %s)', z.gruppe_artikel, z.charge_nr, z.sorte, z.gruppe_charge)
  from zeile z
 where z.gruppe_artikel is not null and z.gruppe_charge is not null
   and z.gruppe_artikel not in ('Mix', 'andere') and z.gruppe_artikel <> z.gruppe_charge
union all
select 'Als Demeter verkauft, als Knospe geliefert', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge,
       format('Preisgruppe Demeter, Lieferlabel %s (Charge %s)', z.liefer_label, z.charge_nr)
  from zeile z
 where z.label_verkauft = 'D' and z.label_geliefert = 'K'
union all
select 'Lieferung vor dem Eingang', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge,
       format('geliefert am %s, die Charge %s kam erst am %s', to_char(z.datum, 'DD.MM.YYYY'), z.charge_nr,
              to_char(e.erst, 'DD.MM.YYYY'))
  from zeile z
  join (select charge_nr, min(eingangsdatum) as erst from palette group by charge_nr) e on e.charge_nr = z.charge_nr
 where z.datum < e.erst;
comment on view v_perigon_pruefung is
  'Was beim Durchsehen der Perigon-Zeilen der laufenden Saison auffällt (0116), je Zeile mit dem Satz, was zu tun ist: Charge nicht zugeordnet, Artikel passt nicht zur Sorte der gelieferten Charge, als Demeter verkauft und als Knospe geliefert, Lieferung vor dem ersten Eingang.';
grant select on v_perigon_pruefung to authenticated;

-- =====================================================================
-- 10. Die Demo zeigt, was neu ist
-- =====================================================================
-- 0081 (b) verlangt, dass keine Sicht auf der Demo-Saison leer bleibt —
-- v_perigon_pruefung blieb es. Dazu bekommt die Demo, was die Runde neu
-- kann: einen Hagelschaden, einen ausgeschlossenen Ausreisser je Art,
-- eine Kundengruppe, einen Plan und eine Perigon-Zeile, deren Artikel nicht
-- zur Sorte ihrer Charge passt. Entfernen nimmt alles wieder mit. Die
-- Formeln sind die aus 0104, mit dem neuen Abschnitt 7 und den neuen
-- Zeilen im Entfernen.
create or replace function demo_daten_laden()
returns text language plpgsql security definer set search_path = public as $fn$
declare
  v_anker date := current_date - 215;
  -- Der Schnitt „was ist schon passiert" hing bisher an now(). Damit war die
  -- Saison nur *fast* reproduzierbar: lud man sie morgens und mittags, kamen
  -- verschieden viele Arbeiten heraus, weil ein Start von gestern abend beim
  -- einen Lauf noch vor der Grenze lag und beim anderen dahinter. Gemessen:
  -- 367 gegen 376 Arbeiten, zwei Läufe im Abstand von Minuten. Jetzt liegt
  -- die Grenze auf einer festen Stunde des Tages — zweimal laden am selben
  -- Tag gibt zweimal dieselbe Saison. Nur die laufenden Arbeiten am Schluss
  -- hängen weiter an now(), denn die sollen wirklich gerade laufen.
  v_jetzt timestamptz := current_date::timestamptz + interval '17 hours';
  v_wer   uuid := auth.uid();
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter laden.';
  end if;
  if exists (select 1 from palette where extern_id like 'demo-%') then
    raise exception E'Die Demo-Saison ist schon geladen.\nZum Neuladen zuerst entfernen.';
  end if;

  -- Im SQL-Editor gibt es keinen Login — dann tritt der Betriebsleiter ein.
  if v_wer is null then
    select id into v_wer from profil where rolle = 'admin' order by erstellt_ts limit 1;
  end if;
  if v_wer is null then select id into v_wer from profil order by erstellt_ts limit 1; end if;
  if v_wer is null then
    raise exception E'Es gibt noch kein Benutzerkonto.\nLege zuerst dein Betriebsleiter-Konto an (README, Schritt 7) und versuche es dann nochmal.';
  end if;
  perform set_config('request.jwt.claim.sub', v_wer::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_wer)::text, true);

  -- ---------- Stammdaten der Demo ----------------------------------------
  -- Bei Konflikt bleibt der bestehende Käufer, wie er ist — samt seiner
  -- (leeren) Bemerkung. Genau daran erkennt das Entfernen ihn als echten.
  insert into kaeufer (code, name, bemerkung) values
    ('nordmarkt', 'Nordmarkt Genossenschaft', 'DEMO'), ('talhof', 'Talhof Bio AG', 'DEMO'),
    ('gruenwerk', 'Grünwerk Handel', 'DEMO'), ('feldfrisch', 'Feldfrisch Ost', 'DEMO')
  on conflict (code) do nothing;
  -- Nordmarkt nimmt Butternut in der 8-kg-Kiste; Talhof will Kaori Kuri enger.
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'nordmarkt', v_anker + 20, 'kiste', 8, 'DEMO — Nordmarkt nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'nordmarkt' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'gruenwerk', v_anker + 25, 'kiste', 8, 'DEMO — Grünwerk nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'gruenwerk' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab, bemerkung)
  select 'Kaori Kuri', 'talhof', v_anker + 60, 'kaliber', 600, '[[600,1000],[1000,1400],[1400,2000]]'::jsonb, 2000,
         'DEMO — Talhof will Kaori Kuri in engeren Bändern (beim Eröffnen einer Arbeit geändert)'
   where not exists (select 1 from sortierschema where sorte = 'Kaori Kuri' and kaeufer = 'talhof' and art = 'kaliber');
  -- Ein Vorlauf: Charge 1611 lieferte schon 5 t, bevor die App lief.
  insert into charge_vorlauf (charge_nr, ausgang_vor_app_kg, bemerkung)
  values (1611, 5000, 'DEMO — vor dem Erfassungsbeginn ausgeliefert')
  on conflict (charge_nr) do nothing;

  -- ---------- Hilfstabellen ------------------------------------------------
  drop table if exists demo_charge; drop table if exists demo_pal; drop table if exists demo_lauf;
  create temp table demo_charge (
    nr int primary key, sorte text, weg text, kg numeric, kw int,
    anteil_verarbeitet numeric,      -- wie viel der Charge bis heute verarbeitet ist
    r numeric,                       -- Verdunstung je Tag
    lambda numeric, k numeric, sockel numeric,   -- Verderbskurve
    fax_anteil numeric, gramm int, sd int,       -- Faules beim Fax, Gewicht je Kürbis
    kg_kiste numeric, kaeufer text
  );
  -- Die ganze Anbauplanung, nicht nur ein Teil davon: jede Charge des
  -- Stammdatenregisters bekommt einen Eingang. Vorher blieben sechs ohne
  -- jede Zeile — im Dashboard standen sie als Chargen ohne Daten, und wer
  -- die Demo anschaute, hielt das für einen Fehler des Werkzeugs.
  insert into demo_charge (nr, kg, kw, anteil_verarbeitet) values
    (1598,  2200, 35, 1.00), (1599,  1400, 34, 0.85), (1601,  9800, 38, 0.25),
    (1603,  3100, 36, 1.00), (1604,  2600, 34, 0.90), (1605,  1200, 34, 1.00),
    (1606,   800, 33, 1.00), (1607,  1900, 34, 1.00), (1608,  6400, 36, 0.70),
    (1609, 12500, 35, 0.80), (1610,  4200, 37, 0.45), (1611, 38000, 37, 0.60),
    (1612, 16500, 35, 0.75), (1613, 24000, 35, 0.90), (1614,  3900, 34, 1.00),
    (1615,  3100, 34, 1.00), (1616,  8600, 34, 0.85), (1617,  2400, 35, 1.00),
    (1618,  4100, 34, 1.00), (1619,  1800, 34, 1.00), (1620,  2900, 35, 0.55),
    (1623,  9100, 36, 0.65), (1624,  7800, 35, 0.85), (1625,  2600, 34, 1.00),
    (1626,  4600, 39, 0.00), (1627,  2900, 39, 0.40), (1628, 11000, 34, 0.95),
    (1630, 10800, 34, 0.90), (1631, 14200, 39, 0.15), (1632, 35000, 37, 0.50),
    (1633, 22000, 38, 0.35), (1634,  6600, 36, 0.70), (1635,  5900, 36, 0.80),
    (1636, 17000, 36, 0.55), (1637,  5400, 36, 0.75), (1638,  4800, 36, 0.30),
    (1646,  7200, 34, 0.80), (1647,  8100, 39, 0.25), (1648,  9700, 34, 0.90),
    (1649, 20500, 38, 0.40), (1650,  2400, 39, 0.00), (1651,  3300, 35, 1.00);
  update demo_charge d set sorte = c.sorte from charge c where c.nr = d.nr;
  -- Butternut von Hand, alles andere über die Maschine. Sorteneigenschaften
  -- so, wie sie im Betrieb beobachtet werden: Hokkaido verdunstet schneller,
  -- Butternut hält länger, Mandarin ist klein.
  -- Mit WHERE, obwohl jede Zeile gemeint ist: Supabase lässt die API-Verbindung
  -- mit der Sicherung safeupdate laufen, die ein UPDATE ohne Bedingung abweist —
  -- auch in einer Funktion, auch auf einer Hilfstabelle.
  update demo_charge set
    weg    = case when sorte in ('Tiana', 'Mieluna') then 'hand' else 'maschine' end,
    r      = case sorte when 'Tiana' then 0.00045 when 'Mieluna' then 0.00050 when 'Butterkin' then 0.00060
                        when 'Orangita' then 0.00090 when 'Lekor' then 0.00065 else 0.00080 end,
    -- λ so, dass nach 150 Tagen rund 8 % (Butternut) bis 14 % (Mandarin) faul sind
    lambda = case sorte when 'Tiana' then 800 when 'Mieluna' then 720 when 'Butterkin' then 600
                        when 'Orangita' then 450 when 'Lekor' then 560 when 'Kaori Kuri' then 520 else 500 end,
    k      = case sorte when 'Tiana' then 1.5 when 'Orangita' then 1.9 else 1.7 end,
    sockel = case sorte when 'Orangita' then 0.006 else 0.004 end,
    fax_anteil = case sorte when 'Tiana' then 0.012 when 'Mieluna' then 0.015 when 'Orangita' then 0.030
                            when 'Butterkin' then 0.020 else 0.024 end,
    gramm  = case sorte when 'Orangita' then 560 when 'Butterkin' then 1250 when 'Lekor' then 1500
                        when 'Kaori Kuri' then 1100 when 'Amoro' then 1300 when 'Ker Madec' then 1000
                        when 'Fictor' then 1400 when 'Orange Summer' then 1200 when 'Bolp 5110' then 1200
                        when 'Tiana' then 1400 else 1200 end,
    sd     = case sorte when 'Orangita' then 170 when 'Tiana' then 420 when 'Lekor' then 420 else 320 end,
    kg_kiste = case sorte when 'Orangita' then 10.8 when 'Tiana' then 12.4 when 'Mieluna' then 12.0
                          when 'Butterkin' then 11.8 else 11.4 end,
    kaeufer = case nr % 4 when 0 then 'nordmarkt' when 1 then 'talhof' when 2 then 'gruenwerk' else 'feldfrisch' end
   where sorte is not null;
  -- Die zwei grossen Abnehmer teilen sich die frühen Chargen; die zwei
  -- kleineren nehmen, was später kommt — so steht es in der Verkaufsplanung.
  update demo_charge set kaeufer = case when nr % 2 = 0 then 'nordmarkt' else 'talhof' end
   where kw <= 35;

  create temp table demo_pal (
    id bigint, nr int, datum date, netto numeric, kisten int, verarbeitet boolean default false
  );
  create temp table demo_lauf (
    auftrag_id bigint, nr int, sorte text, start_ts timestamptz, masse_kg numeric, alter_tage numeric,
    art text, kaeufer text, baender jsonb, kg_je_kiste numeric,
    kisten int[]       -- gefüllte Kisten je Band (Index = Band)
  );

  -- ---------- 1. Wareneingang: je Charge in ihrer Erntewoche ---------------
  declare d record; v_n int; v_p int; v_tag date; v_kisten int; v_netto numeric; v_je_tag int;
          v_zufall numeric; v_art text; v_id bigint;
  begin
    for d in select * from demo_charge order by nr loop
      v_n := greatest(round(d.kg / (32 * d.kg_kiste))::int, 2);
      v_je_tag := case when v_n <= 6 then 4 when v_n <= 20 then 8 when v_n <= 60 then 14 else 22 end;
      v_tag := v_anker + (d.kw - 34) * 7 + (d.nr % 3);
      for v_p in 1 .. v_n loop
        -- Werktage: Samstag und Sonntag wird nicht geerntet
        if v_p > 1 and (v_p - 1) % v_je_tag = 0 then v_tag := v_tag + 1; end if;
        while extract(isodow from v_tag) >= 6 loop v_tag := v_tag + 1; end loop;
        v_zufall := (hashtext(format('pal-%s-%s', d.nr, v_p))::bigint & 2147483647)::numeric / 2147483647;
        v_kisten := 30 + (v_p * 7 + d.nr) % 5;
        v_netto  := round(v_kisten * d.kg_kiste * (0.94 + 0.12 * v_zufall), 1);
        -- Fremde Produzenten liefern teils in IFCO-Kisten
        v_art := case when d.nr in (1648, 1628, 1630, 1631) and v_p % 3 = 0 then 'IFCO 6416' else 'G2' end;
        insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
        values (d.nr, v_tag, v_netto + v_kisten * (case when v_art = 'G2' then 1.5 else 1.68 end) + 25,
                v_kisten, v_art, format('demo-%s-%s', d.nr, v_p))
        returning id into v_id;
        insert into demo_pal (id, nr, datum, netto, kisten) values (v_id, d.nr, v_tag, v_netto, v_kisten);
      end loop;
    end loop;
    raise notice 'Demo: Wareneingang angelegt (% Paletten)', (select count(*) from demo_pal);
  end;

  -- ---------- 2. Verarbeitung -----------------------------------------------
  -- Sortieren (Maschine) bzw. Waschen + Sortieren (Hand), in mehreren Läufen,
  -- ohne FIFO. Je Lauf: Paletten mit Datum vom Zettel, Palox zu Beginn und am
  -- Ende (Faules nach der Verderbskurve), CSV oder Wägungen, Kisten je Kaliber.
  declare d record; v_lauf int; v_n_laeufe int; v_n_pal int; v_verarbeitet int; v_ziel int;
          v_start timestamptz; v_auftrag bigint; v_masse numeric; v_tage numeric; v_f numeric;
          v_schimmel numeric; v_zufall numeric; v_schema bigint; v_art text; v_kaeufer text;
          v_baender jsonb; v_nb int; v_i int; v_hist jsonb; v_n int; v_gramm numeric;
          v_kisten int[]; v_kg_band numeric; v_klein numeric; v_gross numeric; v_x numeric;
          p record; v_pal_ids bigint[]; v_netto numeric; v_kisten_p int; v_brutto numeric;
          v_wiegung bigint; v_datum date; v_abstand int;
  begin
    for d in select * from demo_charge where anteil_verarbeitet > 0 order by nr loop
      select count(*) into v_n_pal from demo_pal where nr = d.nr;
      v_ziel := round(v_n_pal * d.anteil_verarbeitet)::int;
      if v_ziel = 0 then continue; end if;
      v_n_laeufe := greatest(ceil(v_ziel / 16.0)::int, 1);
      v_verarbeitet := 0;
      v_abstand := greatest(round(172.0 / v_n_laeufe)::int, 8);

      for v_lauf in 1 .. v_n_laeufe loop
        -- Wie viele Paletten dieser Lauf nimmt, und wann
        v_n := least(v_ziel - v_verarbeitet, 12 + (d.nr + v_lauf) % 8);
        exit when v_n <= 0;
        v_zufall := (hashtext(format('lauf-%s-%s', d.nr, v_lauf))::bigint & 2147483647)::numeric / 2147483647;
        -- Jede Charge kommt zu ihrer Zeit dran: die einen bald nach der Ernte,
        -- die anderen Wochen später — so bleibt bis heute etwas zu tun.
        v_start := (v_anker + (d.kw - 34) * 7 + 12 + (d.nr % 7) * 12 + (v_lauf - 1) * v_abstand + floor(v_zufall * 6)::int)::timestamptz
                   + interval '7 hours' + (d.nr % 3) * interval '30 minutes';
        while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
        exit when v_start > v_jetzt - interval '2 days';

        -- Kein FIFO: ungerade Läufe greifen die jüngsten Paletten, gerade die
        -- ältesten — je nachdem, an welchen Stapel man herankommt.
        select array_agg(id) into v_pal_ids from (
          select id from demo_pal where nr = d.nr and not verarbeitet
           order by case when v_lauf % 2 = 1 then datum end desc,
                    case when v_lauf % 2 = 0 then datum end asc, id
           limit v_n) s;
        update demo_pal set verarbeitet = true where id = any(v_pal_ids);
        select sum(netto), sum(netto * (v_start::date - datum)) / sum(netto)
          into v_masse, v_tage from demo_pal where id = any(v_pal_ids);
        v_verarbeitet := v_verarbeitet + v_n;

        -- Die Fassung: Maschine immer Kaliber; von Hand die 8-kg-Kiste — bis auf
        -- eine Charge, die Migros nach Kaliber will (dort bleibt das Kisten-
        -- gewicht beim Fax unbekannt, und die Auswertung sagt es).
        v_kaeufer := d.kaeufer;
        v_art := case when d.weg = 'maschine' then 'kaliber'
                      when d.nr = 1647 then 'kaliber' else 'kiste' end;
        v_schema := sortierschema_fuer(d.sorte, v_kaeufer, v_start::date, v_art);
        select kaliber_baender into v_baender from sortierschema where id = v_schema;
        if v_art = 'kaliber' and v_baender is null then
          select kaliber_baender into v_baender from sortierschema
           where sorte = d.sorte and art = 'kaliber' and kaeufer is null order by gilt_ab desc limit 1;
        end if;
        v_nb := coalesce(jsonb_array_length(v_baender), 0);

        -- 0060: das Kistensystem steht an der Arbeit — von Hand „Kiste ab 8 kg"
        -- oder Stück-Kisten eines Kalibers; die Sortiermaschine fragt nicht.
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaeufer, sortierschema_id, bemerkung,
                             geplante_paletten, kistensystem, soll_kg_pro_kiste, stueck_je_kiste)
        values (case when d.weg = 'maschine' then 'maschine' else 'hand' end::verarbeitungsweg,
                case when d.weg = 'maschine' then 'sortieren' else 'waschen_sortieren' end::station,
                d.nr, v_start,
                v_start + make_interval(mins => (240 + v_n * 14 + floor(v_zufall * 40)::int)),
                'abgeschlossen', v_kaeufer, v_schema, 'DEMO', v_n,
                case when d.weg = 'maschine' then null when v_art = 'kiste' then 'kiste_ab' else 'stueck' end,
                case when d.weg <> 'maschine' and v_art = 'kiste' then 8 end,
                case when d.weg <> 'maschine' and v_art = 'kaliber' then greatest(round(d.kg_kiste * 1000 / d.gramm)::int, 1) end)
        returning id into v_auftrag;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_auftrag, id from profil order by erstellt_ts limit (2 + (v_lauf % 2))
        on conflict do nothing;

        -- Paletten zählen — mit dem Datum vom Zettel; beim Waschen + Sortieren
        -- auch mit dem Gewicht vom Zettel (0060), damit der Palox einen Nenner hat.
        -- 0076: die Maske lässt die Palette aus der Liste greifen — dann steht
        -- sie mit ihrer Nummer da und die Masse ist exakt bekannt. Jede dritte
        -- Arbeit tippt stattdessen nur das Zetteldatum ab; dort bleibt die
        -- Masse ein Mittel. Beides kommt vor, und die Herkunftsspalte im
        -- Dashboard soll beides zeigen.
        -- 0072: in welchem Gebinde die Palette steht, wird gefragt — meistens
        -- G2, manchmal IFCO.
        insert into auftrag_palette (auftrag_id, palette_id, eingangsdatum, ts, brutto_zettel_kg, gebindeart)
        select v_auftrag,
               case when (d.nr + v_lauf) % 3 <> 0 then dp.id end,
               dp.datum, v_start + make_interval(mins => (10 + row_number() over (order by dp.id) * 12)::int),
               case when d.weg <> 'maschine' then (select pl.brutto_kg from palette pl where pl.id = dp.id) end,
               (select pl.gebindeart from palette pl where pl.id = dp.id)
          from demo_pal dp where dp.id = any(v_pal_ids);

        -- Verderb bis heute: Weibull je Sorte plus Sockel, mit Streuung je Lauf
        v_f := 1 - exp(-power(v_tage / d.lambda, d.k));
        v_schimmel := round(v_masse * power(1 - d.r, v_tage) * (d.sockel + v_f) * (0.8 + 0.4 * v_zufall));
        insert into schimmel_messung (auftrag_id, kg, ts) values (v_auftrag, greatest(v_schimmel, 1)::int, v_start + interval '5 hours');
        insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

        if d.weg = 'maschine' then
          -- ---- Die Sortier-CSV: was am Band ankommt, jeder Kürbis gewogen ----
          -- Masse am Band = Eingang − Verdunstung − Faules; das Gewicht je
          -- Kürbis ist mit der Lagerdauer entsprechend kleiner.
          v_x := v_masse * power(1 - d.r, v_tage) - v_schimmel;
          v_gramm := d.gramm * power(1 - d.r, v_tage);
          v_n := greatest(round(v_x * 1000 / v_gramm)::int, 50);
          -- Glockenförmig in 10-g-Stufen von −3σ bis +3σ, plus ein leichter
          -- zweiter Gipfel bei manchen Schlägen (ungleiche Reife).
          select jsonb_agg(jsonb_build_array(g, anz)) into v_hist from (
            select g, greatest(round(v_n * 10 * (
                     exp(-power((g - v_gramm) / d.sd, 2) / 2) / (d.sd * 2.5066)
                     + case when d.nr % 5 = 0 then 0.35 * exp(-power((g - v_gramm * 1.45) / (d.sd * 0.6), 2) / 2) / (d.sd * 0.6 * 2.5066) else 0 end
                   ))::int, 0) as anz
              from generate_series(greatest(round((v_gramm - 3 * d.sd) / 10) * 10, 100)::int,
                                   round((v_gramm + 3.5 * d.sd) / 10)::int * 10, 10) g) h
           where anz > 0;
          perform csv_lauf_speichern(
            d.nr, format('DEMO-%s-%s', d.nr, to_char(v_start, 'DD-MM-HH24-MI')),
            format('demo/sortierdateien/%s-%s.csv', d.nr, to_char(v_start, 'YYYYMMDD')),
            format('demo-pruefsumme-%s', v_auftrag),
            v_start + interval '90 minutes', 'dateiname',
            '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
            (v_n * 1.03)::int, 2 + v_lauf % 3, 5 + v_lauf % 7, (v_n * 0.02)::int, v_hist);

          -- Kisten je Kaliber gezählt: Masse des Bands durch das Kistengewicht
          v_kisten := array[]::int[];
          for v_i in 0 .. v_nb - 1 loop
            select coalesce(sum((e->>1)::numeric * (e->>0)::numeric), 0) / 1000 into v_kg_band
              from jsonb_array_elements(v_hist) e
             where (e->>0)::int >= (v_baender->v_i->>0)::int and (e->>0)::int < (v_baender->v_i->>1)::int;
            v_kisten := v_kisten || greatest(round(v_kg_band / (d.kg_kiste * (0.97 + 0.06 * v_zufall)))::int, 0);
          end loop;
          insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
          select v_auftrag, i - 1, v_kisten[i] from generate_series(1, v_nb) i where v_kisten[i] > 0
          on conflict (auftrag_id, kaliber_idx, sortierdatum) do nothing;
          insert into demo_lauf values (v_auftrag, d.nr, d.sorte, v_start, v_x, v_tage, 'kaliber', v_kaeufer, v_baender, d.kg_kiste, v_kisten);
        else
          -- ---- Von Hand: eine Palette gewogen, Ausschuss gewogen, fertige Palette ----
          select p2.* into p from demo_pal p2 where p2.id = v_pal_ids[1];
          v_wiegung := null;
          v_brutto := p.netto + p.kisten * 1.5 + 25;
          -- 0076: die gewogene Palette ist bekannt, nicht nur ihr Eingangstag.
          -- Jede vierte Wägung sagt ausserdem, wie viel davon faul war — der
          -- einzige Schimmelwert, dessen Palette nicht nach dem Aussehen
          -- ausgewählt wurde.
          insert into verdunstung_wiegung (auftrag_id, charge_nr, palette_id, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                           kisten, gebindeart, kuerbisse_pro_kiste, faul_kg, wiege_ts)
          values (v_auftrag, d.nr, p.id, p.datum, v_brutto,
                  round((p.netto * power(1 - d.r * (0.7 + 0.6 * v_zufall), v_start::date - p.datum) + p.kisten * 1.5 + 25) * 2) / 2.0,
                  p.kisten, 'G2', 4 + (d.nr % 3),
                  case when v_lauf % 4 = 0 then round(p.netto * (0.004 + 0.02 * v_zufall), 1) end,
                  v_start + interval '2 hours')
          returning id into v_wiegung;
          -- Die Wägung gehört zu der gezählten Palette mit demselben Zetteldatum —
          -- sonst zählte die Kohortenrechnung sie einem anderen Eingangstag zu.
          update auftrag_palette set wiegung_id = v_wiegung
           where id = (select min(id) from auftrag_palette
                        where auftrag_id = v_auftrag and eingangsdatum = p.datum);

          v_x := v_masse * power(1 - d.r, v_tage) - v_schimmel;
          v_klein := round(v_x * (0.025 + 0.02 * v_zufall));
          v_gross := round(v_x * (0.010 + 0.015 * (1 - v_zufall)));
          v_kisten_p := greatest(ceil(v_klein / 22.0), 1)::int;
          insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart, ts, bemerkung)
          values (v_auftrag, 'zu_klein', v_klein + v_kisten_p * 1.5 + 25, v_kisten_p, 'G2', v_start + interval '6 hours',
                  case when v_lauf % 6 = 0 then 'Viel Kleines in dieser Charge' end);
          if v_lauf % 3 = 0 then
            -- Einmal nicht gewogen, nur geschätzt — das zeigt die Datenqualität.
            insert into ausschuss_messung (auftrag_id, art, kg, ts) values (v_auftrag, 'zu_gross', v_gross::int, v_start + interval '6 hours');
          else
            v_kisten_p := greatest(ceil(v_gross / 22.0), 1)::int;
            insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart, ts)
            values (v_auftrag, 'zu_gross', v_gross + v_kisten_p * 1.5 + 25, v_kisten_p, 'G2', v_start + interval '6 hours');
          end if;
          insert into auftrag_angabe (auftrag_id, schluessel, wert)
          values (v_auftrag, 'ausschuss_leer', 'true'), (v_auftrag, 'ausschuss_von_auftrag', 'true');

          -- Fertige Paletten: bei „Kiste ab 8 kg" überfüllt (8.2–8.6), nach
          -- Kaliber ohne Soll — dort zählt nur das Kistengewicht.
          v_kg_band := case when v_art = 'kiste' then 8.15 + 0.45 * v_zufall else 11.5 + 1.5 * v_zufall end;
          for v_i in 1 .. 2 loop
            insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, kuerbisse_pro_kiste, ts)
            values (v_auftrag, d.nr, round((32 * (v_kg_band + 0.05 * v_i) + 32 * 1.5 + 25) * 2) / 2.0, 32, 'G2',
                    case when v_art = 'kiste' then 5 + (d.nr % 2) else null end,
                    v_start + make_interval(hours => 3 + v_i));
          end loop;
          -- Für das Fax: die Masse in Kisten (−1 = Kiste nach Soll, sonst Bänder gleich verteilt)
          v_kisten := array[]::int[];
          if v_art = 'kiste' then
            v_kisten := array[greatest(round((v_x - v_klein - v_gross) / v_kg_band)::int, 1)];
          else
            for v_i in 0 .. v_nb - 1 loop
              v_kisten := v_kisten || greatest(round((v_x - v_klein - v_gross) / v_nb / v_kg_band)::int, 0);
            end loop;
          end if;
          -- 0072: „die fertigen paletten werden eher nicht gezählt" — aber
          -- wenn doch, ist die Ausgangsmasse der Arbeit bekannt statt nur
          -- geschätzt. Zwei von drei Arbeiten zählen sie.
          if v_lauf % 3 <> 0 then
            update auftrag set fertige_paletten_gesamt =
                   greatest(ceil((v_x - v_klein - v_gross) / (32 * v_kg_band))::int, 1)
             where id = v_auftrag;
          end if;
          insert into demo_lauf values (v_auftrag, d.nr, d.sorte, v_start, v_x - v_klein - v_gross, v_tage, v_art, v_kaeufer, v_baender, v_kg_band, v_kisten);
        end if;
      end loop;
    end loop;
    raise notice 'Demo: Sortieren und Waschen + Sortieren angelegt (% Arbeiten)', (select count(*) from demo_lauf);
  end;

  -- ---------- 3. Waschen je Kaliber, Wochen später (Weg 1) ------------------
  -- Aus jedem Sortierlauf werden die Bänder nacheinander gewaschen: die
  -- gefüllten Kisten geleert, Palox abgelesen (Schimmel #2, klein), eine
  -- fertige Palette gewogen. Nicht jedes Band ist schon dran — was wartet,
  -- steht in der Auswertung als „wartet aufs Waschen".
  declare l record; v_i int; v_start timestamptz; v_neu bigint; v_zufall numeric; v_kg numeric; v_kisten int;
          v_anteil numeric; v_gewaschen int[]; v_zufall2 numeric;
          v_eigen boolean; v_ohne_pal boolean; v_von int; v_bis int;
  begin
    for l in select * from demo_lauf where art = 'kaliber' and exists (select 1 from auftrag a where a.id = demo_lauf.auftrag_id and a.station = 'sortieren') order by start_ts loop
      v_gewaschen := array[]::int[];
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_zufall := (hashtext(format('wasch-%s-%s-%s', l.nr, l.start_ts::date, v_i))::bigint & 2147483647)::numeric / 2147483647;
        -- Das letzte Band der späten Läufe wartet noch
        if l.kisten[v_i] = 0 or (v_i = array_length(l.kisten, 1) and l.start_ts > v_jetzt - interval '60 days') then
          v_gewaschen := v_gewaschen || 0; continue;
        end if;
        v_start := l.start_ts + make_interval(days => 6 + v_i * 5 + floor(v_zufall * 25)::int) + interval '1 hour';
        while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
        if v_start > v_jetzt - interval '1 day' then v_gewaschen := v_gewaschen || 0; continue; end if;
        v_kisten := l.kisten[v_i];
        -- 0054: manchmal nennt das Etikett kein Band der Fassung, sondern ein
        -- eigenes Kaliber — „ab 900 g" statt „Band 2". Dann steht die Grenze
        -- an der Arbeit und der Bandindex bleibt leer.
        v_eigen := (l.nr + v_i) % 13 = 0 and l.baender is not null
                   and jsonb_array_length(l.baender) > v_i - 1;
        if v_eigen then
          v_von := (l.baender->(v_i - 1)->>0)::int + 50;
          v_bis := (l.baender->(v_i - 1)->>1)::int - 50;
          if v_bis <= v_von then v_eigen := false; end if;
        end if;
        -- Auf Weg 1 sind die Eingangspaletten beim Waschen längst in
        -- Kaliberkisten aufgelöst. Meistens zählt der Vorarbeiter die
        -- Zwischenlager-Paletten; jede vierte Arbeit kann das nicht und gibt
        -- stattdessen die verarbeitete Menge an — sonst hätte der dort
        -- gemessene Schimmel keinen Nenner. Beim eigenen Kaliber ist das
        -- immer so: dort kennt niemand das Gewicht einer Kiste, weil dieses
        -- Band beim Sortieren nie gezählt wurde. Gemessen, bevor das hier
        -- stand: fünf Waschgänge meldeten „die Messung hat keinen Nenner" —
        -- richtig gerechnet, aber in einer Demo unnötig.
        v_ohne_pal := (l.nr + v_i + extract(day from l.start_ts)::int) % 4 = 0 or v_eigen;
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx, sortierschema_id, bemerkung,
                             kistensystem, stueck_je_kiste, kaliber_von_g, kaliber_bis_g, durchsatz_kg, geplante_paletten)
        values ('maschine', 'waschen', l.nr, v_start,
                v_start + make_interval(mins => 90 + v_kisten * 5 + floor(v_zufall * 30)::int),
                'abgeschlossen', case when v_eigen then null else v_i - 1 end,
                (select sortierschema_id from auftrag where id = l.auftrag_id), 'DEMO',
                'stueck', greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1),
                case when v_eigen then v_von end, case when v_eigen then v_bis end,
                case when v_ohne_pal then round(v_kisten * l.kg_je_kiste) end,
                case when v_ohne_pal then null else ceil(v_kisten / 32.0)::int end)
        returning id into v_neu;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_neu, id from profil order by erstellt_ts limit 2 on conflict do nothing;
        -- Q22, Schichtwechsel: an langen Waschgängen geht einer um vier Uhr
        -- und ein anderer übernimmt. Wer gegangen ist, steht mit seiner Zeit da.
        if v_kisten > 120 then
          update auftrag_teilnehmer set verlassen_ts = v_start + interval '4 hours'
           where auftrag_id = v_neu
             and profil_id = (select profil_id from auftrag_teilnehmer where auftrag_id = v_neu order by profil_id limit 1);
          insert into auftrag_teilnehmer (auftrag_id, profil_id, beigetreten_ts)
          select v_neu, id, v_start + interval '4 hours' from profil
           where id not in (select profil_id from auftrag_teilnehmer where auftrag_id = v_neu)
           order by erstellt_ts limit 1
          on conflict do nothing;
        end if;
        -- 0061: beim Waschen werden Paletten gezählt — das Sortierdatum vom
        -- Zettel und die Kisten je Palette (höchstens 32), so wie die Maske.
        if not v_ohne_pal then
          -- 0104: Seit Mitte August wiegt die Demo-Halle jede Wasch-Palette am
          -- Anfang der Strasse (die Regel des Betriebs vom 29. September; die
          -- Demo zeigt, was die App kann). Brutto = Palette + Kisten × (Tara +
          -- Kistengewicht der Charge, leicht streuend). Ältere Waschgänge
          -- bleiben ungewogen — für sie gelten die Ersätze.
          insert into auftrag_palette (auftrag_id, sortierdatum, kisten, gebindeart, brutto_gewogen_kg)
          select v_neu, l.start_ts::date, x.kisten, x.art,
                 case when v_start::date >= current_date - 45
                      then round(g.tara_kg_palette + x.kisten * (g.tara_kg_pro_kiste
                                 + l.kg_je_kiste * (0.96 + 0.08 * ((hashtext(format('waage-%s-%s', l.nr, s))::bigint & 2147483647)::numeric / 2147483647))), 1)
                 end
            from generate_series(1, ceil(v_kisten / 32.0)::int) s
            cross join lateral (select least(32, v_kisten - (s - 1) * 32) as kisten,
                                       case when s % 5 = 0 then 'IFCO 6416' else 'G2' end as art) x
            join gebinde g on g.art = x.art;
        end if;
        -- Schimmel #2: was seit dem Sortieren in der Kiste dazukam. Der Verderb
        -- geht in der Kiste weiter, nach derselben Kurve — bedingt auf das, was
        -- beim Sortieren noch gut war: (F(t_wasch) − F(t_sort)) / (1 − F(t_sort)).
        v_kg := v_kisten * l.kg_je_kiste;
        select d2.lambda, d2.k into v_anteil, v_zufall2 from demo_charge d2 where d2.nr = l.nr;
        v_anteil := greatest(
          ((1 - exp(-power((l.alter_tage + (v_start::date - l.start_ts::date)) / v_anteil, v_zufall2)))
           - (1 - exp(-power(l.alter_tage / v_anteil, v_zufall2))))
          / (exp(-power(l.alter_tage / v_anteil, v_zufall2))), 0.002);
        insert into schimmel_messung (auftrag_id, kg, ts)
        values (v_neu, greatest(round(v_kg * v_anteil * (0.75 + 0.5 * v_zufall)), 1)::int, v_start + interval '3 hours');
        insert into auftrag_angabe (auftrag_id, schluessel, wert)
        values (v_neu, 'eine_charge', 'true');
        -- Fertige Palette nach Kaliber: kein Soll, nur das Kistengewicht
        insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, ts, kaliber_idx, kuerbisse_pro_kiste, bemerkung)
        values (v_neu, l.nr, round((32 * l.kg_je_kiste * (0.96 + 0.08 * v_zufall) + 32 * 1.5 + 25) * 2) / 2.0, 32, 'G2',
                v_start + interval '2 hours', case when v_eigen then null else v_i - 1 end,
                greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1),
                case when v_eigen then format('Eigenes Kaliber %s–%s g', v_von, v_bis) end);
        -- Wie viele fertige Paletten am Ende dastanden. Ohne diese Zahl kennt
        -- die App nur die *gewogene* — die Ausgangsmasse wäre unbekannt.
        if (l.nr + v_i) % 3 <> 0 then
          update auftrag set fertige_paletten_gesamt = greatest(ceil(v_kisten / 32.0)::int, 1) where id = v_neu;
        end if;
        v_gewaschen := v_gewaschen || v_kisten;
      end loop;
      update demo_lauf set kisten = v_gewaschen where auftrag_id = l.auftrag_id;
    end loop;
    raise notice 'Demo: Waschgänge angelegt';
  end;

  -- ---------- 4. Fax und Lieferungen ----------------------------------------
  -- Nach dem Waschen steht die Ware in Kisten, bis eine Bestellung kommt. Das
  -- Fax macht daraus Paletten mit Etikett und sortiert dabei Faules aus —
  -- gewogen, kistenweise. Was gemacht wird, geht innert Tagen raus. Die
  -- Lieferungen einer Charge verteilen sich so über Wochen und verschränken
  -- sich mit denen anderer Chargen.
  declare l record; v_i int; v_start timestamptz; v_neu bigint; v_zufall numeric; v_kisten int; v_rest int;
          v_teil int; v_masse numeric; v_faul numeric; v_n_faul int; v_j int; v_kaeufer text; v_kunde text;
          v_lief numeric; v_schema bigint;
          -- 0061: die Verkaufsdatei zur Lieferung
          v_pos int := 0; v_lief_id bigint; v_lief_datum date; v_einheit text; v_inhalt int;
          v_gja numeric; v_menge numeric; v_stueck int; v_artikel text; v_artikel_id text;
  begin
    -- Die Warenwirtschaft der Demo: jede Lieferung steht auch als Zeile einer
    -- Verkaufsdatei da (Einheit, Gebindeinhalt, Kisten je Chargenzeile), so wie
    -- sie der Import aus dem Perigon anlegt. Daraus die verkauften Kisten.
    insert into ausgang_quelle (code, name, dateiname_muster, bemerkung)
    values ('DEMO', 'Demo-Warenwirtschaft', 'demo', 'DEMO') on conflict (code) do nothing;
    for l in select * from demo_lauf order by start_ts loop
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_rest := l.kisten[v_i];
        if v_rest <= 0 then continue; end if;
        v_j := 0;
        while v_rest > 0 loop
          v_j := v_j + 1;
          exit when v_j > 4;
          v_zufall := (hashtext(format('fax-%s-%s-%s-%s', l.nr, l.start_ts::date, v_i, v_j))::bigint & 2147483647)::numeric / 2147483647;
          -- Ein Teil der Ware wartet noch auf eine Bestellung
          if v_zufall < 0.12 then exit; end if;
          v_teil := least(v_rest, 32 * (1 + floor(v_zufall * 4)::int) + floor(v_zufall * 20)::int);
          v_start := l.start_ts + make_interval(days => 20 + v_i * 6 + v_j * 9 + floor(v_zufall * 12)::int) + interval '2 hours';
          while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
          exit when v_start > v_jetzt - interval '1 day';
          v_kaeufer := case when v_j % 3 = 0 then (case l.kaeufer when 'nordmarkt' then 'talhof' when 'talhof' then 'nordmarkt' when 'gruenwerk' then 'feldfrisch' else 'gruenwerk' end) else l.kaeufer end;
          v_schema := case when l.art = 'kiste' then sortierschema_fuer(l.sorte, l.kaeufer, v_start::date, 'kiste') else null end;
          -- 0060: die Palettenzahl als Gesamtzahl, die Tage seit dem Waschen, das
          -- Kistensystem. Jede zweite Fax-Arbeit zählt zusätzlich noch Kisten
          -- (der Weg vor 0060) — beide Wege müssen dieselbe Masse ergeben.
          insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, ende_ts, status, kaeufer, sortierschema_id, bemerkung,
                               kistensystem, soll_kg_pro_kiste, paletten_gesamt, tage_seit_waschen)
          values ('maschine', 'waschen', l.nr, true, v_start,
                  v_start + make_interval(mins => 40 + v_teil * 2 + floor(v_zufall * 25)::int),
                  'abgeschlossen', v_kaeufer, v_schema, 'DEMO',
                  case when l.art = 'kiste' then 'kiste_ab' else 'stueck' end,
                  case when l.art = 'kiste' then 8 end,
                  ceil(v_teil / 32.0)::int,
                  case when v_j % 3 = 0 then null else 1 + floor(v_zufall * 3)::int end)
          returning id into v_neu;
          insert into auftrag_teilnehmer (auftrag_id, profil_id)
          select v_neu, id from profil order by erstellt_ts limit 1 on conflict do nothing;
          if v_j % 2 = 1 then
            insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
            values (v_neu, case when l.art = 'kiste' then -1 else v_i - 1 end, v_teil);
          end if;
          insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_neu, 'eine_charge', 'true');
          -- Faules: kistenweise gewogen, 1–3 Kisten, Anteil je Sorte mit Streuung.
          -- Jede fünfte Fax-Arbeit hat nichts Faules — auch das ist eine Messung.
          v_masse := v_teil * l.kg_je_kiste;
          v_faul := round(v_masse * (select fax_anteil from demo_charge where nr = l.nr) * (0.4 + 1.2 * v_zufall), 1);
          if v_j % 5 = 0 or v_faul < 1 then
            insert into schimmel_messung (auftrag_id, kg, ts, bemerkung) values (v_neu, 0, v_start + interval '1 hour', 'Nichts Faules');
            v_faul := 0;
          else
            v_n_faul := least(greatest(ceil(v_faul / 9.0)::int, 1), 3);
            insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, mit_palette, ts)
            select v_neu, 0, round(v_faul / v_n_faul + 1.5 + (s - 1) * 0.5, 1), 1, 'G2', false,
                   v_start + make_interval(mins => 30 + s * 20)
              from generate_series(1, v_n_faul) s;
            select coalesce(sum(kg), 0) into v_faul from schimmel_messung where auftrag_id = v_neu;
          end if;
          -- Die Lieferung, wie die Verkaufsdatei sie führt (0061): Kisten × Inhalt,
          -- nominal — „Kiste ab 8 kg" steht mit 8 kg auf dem Lieferschein, die
          -- Stück-Kiste mit Stück × Nenngewicht. Was die Kiste wirklich wiegt,
          -- weiss nur die Waage (Überfüllung). 1–7 Tage nach dem Fax.
          v_lief_datum := (v_start + make_interval(days => 1 + floor(v_zufall * 6)::int))::date;
          v_kunde := case v_kaeufer when 'nordmarkt' then 'Nordmarkt Verteilzentrale' when 'talhof' then 'Talhof Bio AG'
                                    when 'gruenwerk' then 'Grünwerk Handel' else 'Feldfrisch Ost' end;
          v_pos := v_pos + 1;
          if l.art = 'kiste' then
            v_einheit := 'kg'; v_inhalt := 8; v_gja := 1;
            v_artikel := 'Bio Kürbis ' || l.sorte || ' lose'; v_artikel_id := 'kürb' || lower(left(l.sorte, 3));
          else
            v_stueck := greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1);
            v_einheit := 'Stk.'; v_inhalt := v_stueck;
            v_gja := round((select gramm from demo_charge where nr = l.nr) / 1000.0, 2);
            v_artikel := 'Bio Kürbis ' || l.sorte || ' Dem'; v_artikel_id := 'kürb' || lower(left(l.sorte, 3)) || 'd';
          end if;
          v_menge := v_teil * v_inhalt;
          v_lief := round(v_menge * v_gja, 1);
          insert into ausgang_artikel (artikel_id, artikel, ist_kuerbis, sorte, bemerkung)
          values (v_artikel_id, v_artikel, true, l.sorte, 'DEMO') on conflict (artikel_id, artikel) do nothing;
          insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, journal, auftragsnr,
                                     kunde, artikel_id, artikel, einheit, menge, gewicht_je_artikel, batch_menge,
                                     kg_position, kg_charge, gebindeart, gebinde_menge, gebinde_inhalt, batch_gebinde, produzent,
                                     erloes)
          values ('DEMO', v_pos, l.nr::text, 1, 'demo-' || v_pos, v_lief_datum, 'Lieferschein', 'LS-' || (100000 + v_pos),
                  v_kunde, v_artikel_id, v_artikel, v_einheit, v_menge, v_gja, v_menge,
                  v_lief, v_lief, 'IFCO', v_teil, v_inhalt, v_teil, 'Demo-Hof',
                  round(v_lief * (1.55 + 0.5 * v_zufall), 2))
          on conflict (quelle, pos_id, charge_extern, lauf_nr) do nothing;
          insert into lieferung (datum, charge_nr, sorte, kg, kisten, gebindeart, ziel, kunde, bemerkung)
          values (v_lief_datum, l.nr, l.sorte, v_lief, v_teil, 'G2', 'verkauf', v_kunde, 'DEMO')
          returning id into v_lief_id;
          insert into lieferung_import (lieferung_id, quelle, extern_id)
          values (v_lief_id, 'DEMO', format('DEMO:%s:%s:1', v_pos, l.nr));
          v_rest := v_rest - v_teil;
        end loop;
      end loop;
    end loop;
    -- Zu klein geht an die Tiere — als Lieferung mit Ziel Tierfutter, damit die
    -- Bilanz es sieht.
    insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
    select (a.start_ts + interval '3 days')::date, a.charge_nr, c.sorte, sum(m.kg), 'tierfutter', 'Hof Zürcher (Tiere)', 'DEMO'
      from ausschuss_messung m join auftrag a on a.id = m.auftrag_id join charge c on c.nr = a.charge_nr
     where a.bemerkung = 'DEMO' and m.art = 'zu_klein'
     group by a.id, a.start_ts, a.charge_nr, c.sorte;
    -- Und der Hofladen nimmt ab und zu ein paar Kisten
    insert into lieferung (datum, sorte, kisten, ziel, kunde, bemerkung)
    select (v_anker + 40 + i * 11)::date, case when i % 2 = 0 then 'Tiana' else 'Kaori Kuri' end, 6 + i % 5, 'hofladen', 'Hofladen', 'DEMO'
      from generate_series(1, 10) i;
    perform lieferung_import_zeilen_verbinden('DEMO');
    raise notice 'Demo: Fax und Lieferungen angelegt (mit Verkaufsdatei)';
  end;

  -- ---------- 4b. An jeder Station läuft nur eine Arbeit zugleich -----------
  -- Die Arbeiten sind je Charge entstanden; zwei Chargen können so am selben
  -- Tag zur selben Stunde stehen. Im Betrieb geht das nicht (ein Band, ein
  -- Palox je Station) — also rücken sie hintereinander, samt allem, was an
  -- ihnen hängt. Fax hat keinen Palox und läuft nebenher.
  declare v record; v_prev timestamptz; v_station text := ''; v_delta interval;
  begin
    for v in
      select id, palox_station(station)::text as station, start_ts, ende_ts from auftrag
       where bemerkung = 'DEMO' and not ist_fax and status = 'abgeschlossen' and abgebrochen_ts is null
       order by palox_station(station), start_ts, id
    loop
      if v.station <> v_station then v_station := v.station; v_prev := null; end if;
      if v_prev is not null and v.start_ts < v_prev + interval '20 minutes' then
        v_delta := (v_prev + interval '20 minutes') - v.start_ts;
        update auftrag set start_ts = start_ts + v_delta, ende_ts = ende_ts + v_delta where id = v.id;
        update auftrag_palette set ts = ts + v_delta where auftrag_id = v.id;
        update schimmel_messung set ts = ts + v_delta where auftrag_id = v.id;
        update ausschuss_messung set ts = ts + v_delta where auftrag_id = v.id;
        update ausgang_wiegung set ts = ts + v_delta where auftrag_id = v.id;
        update verdunstung_wiegung set wiege_ts = wiege_ts + v_delta where auftrag_id = v.id;
        update sortier_lauf set datei_zeit = datei_zeit + v_delta where auftrag_id = v.id;
        v.ende_ts := v.ende_ts + v_delta;
      end if;
      v_prev := v.ende_ts;
    end loop;
  end;

  -- ---------- 5. Palox-Ablesungen je Arbeit (AB-02) -------------------------
  -- Je Station läuft der Stand über die Arbeiten weiter: eine Ablesung zu
  -- Beginn (Stand unverändert) und eine am Ende. Geleert, wenn er sonst
  -- überliefe. Gespeichert wird der Stand, die Menge folgt daraus. Fax hat
  -- keinen Palox — dort ist das Faule gewogen.
  declare v record; v_stand numeric := 0; v_station text := ''; v_geleert boolean; v_i int := 0;
  begin
    for v in
      select s.id, s.auftrag_id, s.kg, palox_station(a.station)::text as station, a.start_ts, a.ende_ts
        from schimmel_messung s
        join auftrag a on a.id = s.auftrag_id
       where a.bemerkung = 'DEMO' and not a.ist_fax and s.palox_stand_kg is null and s.brutto_kg is null
       order by palox_station(a.station), a.start_ts, s.id
    loop
      v_i := v_i + 1;
      if v.station <> v_station then v_station := v.station; v_stand := palox_tara_kg(); end if;
      -- Zwischen zwei Arbeiten geleert, weil der Palox sonst überliefe. Das
      -- ist der Normalfall, und er kostet seit 0073 keine Messung mehr: die
      -- neue Arbeit beginnt einfach bei der leeren Box und liest ihren
      -- eigenen Anfang ab.
      if v_stand + v.kg > 800 then v_stand := palox_tara_kg(); end if;
      -- Jede 17. Arbeit hat die Ablesung zu Beginn vergessen — die Datenqualität zeigt es.
      if v_i % 17 <> 0 then
        insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert, ts)
        values (v.auftrag_id, 0, v_stand, false, v.start_ts + interval '10 minutes');
      end if;
      -- Jede 23. Arbeit wird MITTENDRIN geleert. Der Betrieb sagt, das kommt
      -- vor. Dann ist die Menge dieser Arbeit unbekannt — nicht null: wie
      -- viel beim Leeren herausging, weiss niemand (0073).
      v_geleert := v_i % 23 = 0;
      if v_geleert
        then v_stand := palox_tara_kg() + round(v.kg * 0.4);
        else v_stand := v_stand + v.kg;
      end if;
      update schimmel_messung
         set palox_stand_kg = v_stand, palox_geleert = v_geleert, ts = coalesce(v.ende_ts, v.start_ts + interval '5 hours') - interval '10 minutes'
       where id = v.id;
      if v_geleert then
        update auftrag set palox_unbekannt = true where id = v.auftrag_id;
      end if;
    end loop;
    raise notice 'Demo: Palox-Ablesungen nachgetragen';
  end;

  -- ---------- 6. Lagerkontrollen --------------------------------------------
  -- Gegriffene Paletten, wie sie der Bildschirm „Palette kontrollieren"
  -- erfasst: Eingangsdatum, Gewicht damals und jetzt, Kisten, Kistenart.
  -- Seit 0061 ohne „davon faul" und ohne Auswahlart — die Kontrolle ist eine
  -- Verdunstungsmessung, nichts weiter.
  declare p record; v_i int := 0; v_tag date; v_tage int; v_zufall numeric; d record;
  begin
    for p in select * from demo_pal where not verarbeitet
              order by (hashtext(format('kontrolle-%s-%s', nr, datum))::bigint & 2147483647), id loop
      v_i := v_i + 1;
      exit when v_i > 24;
      select * into d from demo_charge where nr = p.nr;
      v_zufall := (hashtext('kontr-' || v_i)::bigint & 2147483647)::numeric / 2147483647;
      v_tag := greatest(p.datum + 20, v_anker + 40 + v_i * 6);
      exit when v_tag >= current_date;
      v_tage := v_tag - p.datum;
      -- Wie die Palette gegriffen wurde, entscheidet, ob die Messung für die
      -- Selektionsprüfung taugt: zufällig erreichbar ist die ehrliche Vorgabe,
      -- Mitte-unten ist besser, gezielt („die sieht schlecht aus") ist für den
      -- Vergleich untauglich — und genau das soll die Demo zeigen.
      insert into verdunstung_wiegung (charge_nr, palette_id, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                       kisten, gebindeart, auswahl, faul_kg, wiege_ts, bemerkung)
      values (p.nr, p.id, p.datum, p.netto + p.kisten * 1.5 + 25,
              round((p.netto * power(1 - d.r * (0.8 + 0.4 * v_zufall), v_tage) + p.kisten * 1.5 + 25) * 2) / 2.0,
              p.kisten, 'G2',
              case v_i % 5 when 0 then 'gezielt' when 1 then 'mitte_unten' else 'erreichbar_zufaellig' end,
              case when v_i % 3 <> 0 then round(p.netto * (0.003 + 0.03 * v_zufall), 1) end,
              v_tag::timestamptz + interval '10 hours', 'DEMO-KONTROLLE');
    end loop;
    raise notice 'Demo: Lagerkontrollen angelegt';
  end;

  -- ---------- 6b. Kontrollpaletten: dieselbe Palette immer wieder ----------
  -- Die Lagerkontrolle (Bildschirm „Palette kontrollieren") lebt davon, dass
  -- eine gekennzeichnete Palette über Wochen immer wieder auf dieselbe Waage
  -- kommt. Zwei Wägungen derselben Palette ergeben eine Verdunstungsrate je
  -- Tag, ohne jede Annahme — der sauberste Wert, den der Betrieb hat.
  -- Ohne diesen Abschnitt blieb der ganze Bildschirm in der Demo leer.
  declare pk record; v_kp bigint; v_i int := 0; v_tag date; v_netto numeric;
          v_schimmel boolean; v_zufall numeric; v_j int; v_rate numeric;
  begin
    for pk in
      select dp.id, dp.nr, dp.datum, dp.netto, dp.kisten, dc.r, dc.sorte
        from demo_pal dp join demo_charge dc on dc.nr = dp.nr
       where not dp.verarbeitet
       order by dc.sorte, (hashtext(format('kp-%s-%s', dp.nr, dp.datum))::bigint & 2147483647)
    loop
      -- Je Sorte eine Kontrollpalette, höchstens zwölf.
      continue when exists (select 1 from kontrollpalette k join charge c on c.nr = k.charge_nr
                             where c.sorte = pk.sorte and k.bemerkung = 'DEMO');
      v_i := v_i + 1;
      exit when v_i > 12;
      v_tag := pk.datum + 14 + (pk.nr % 7);
      -- Zu spät angelegt lohnt sich nicht — aber das ist der Grund, diese
      -- Palette zu überspringen, nicht der Grund, aufzuhören.
      if v_tag >= current_date - 30 then v_i := v_i - 1; continue; end if;
      insert into kontrollpalette (charge_nr, palette_id, kennzeichen, standort, angelegt_ts, angelegt_von,
                                   eingangsdatum, brutto_eingang_kg, bemerkung)
      values (pk.nr, pk.id, format('K-%s-%s', pk.nr, chr(64 + v_i)),
              format('Halle %s, Reihe %s', 1 + v_i % 2, 1 + v_i % 6),
              v_tag::timestamptz + interval '9 hours', v_wer,
              pk.datum, round((pk.netto + pk.kisten * 1.5 + 25) * 2) / 2.0, 'DEMO')
      returning id into v_kp;
      -- Alle zwei bis drei Wochen gewogen, bis heute. Die Palette wird
      -- leichter, nie schwerer — und bei einer sieht man am Ende Schimmel,
      -- dann taugt das Paar nicht mehr für die Rate.
      v_j := 0;
      loop
        v_j := v_j + 1;
        v_tag := v_tag + 14 + ((hashtext(format('kpw-%s-%s-%s', pk.nr, pk.datum, v_j))::bigint & 7))::int;
        exit when v_tag >= current_date or v_j > 12;
        v_zufall := (hashtext(format('kpz-%s-%s-%s', pk.nr, pk.datum, v_j))::bigint & 2147483647)::numeric / 2147483647;
        v_netto := pk.netto * power(1 - pk.r * (0.85 + 0.3 * v_zufall), (v_tag - pk.datum));
        v_schimmel := v_i = 3 and v_tag > current_date - 45;
        insert into kontrollpalette_wiegung (kontrollpalette_id, brutto_kg, kisten, gebindeart,
                                             sichtbar_schimmel, erfasser, wiege_ts, ts, bemerkung)
        values (v_kp, round((v_netto + pk.kisten * 1.5 + 25) * 2) / 2.0, pk.kisten, 'G2',
                v_schimmel, v_wer, v_tag::timestamptz + interval '10 hours',
                v_tag::timestamptz + interval '10 hours',
                case when v_schimmel then 'Erste faule Stellen sichtbar'
                     when v_j = 1 then 'Erste Wägung nach dem Einlagern' end);
      end loop;
      -- Eine Kontrollpalette ist inzwischen verarbeitet — sie wird beendet,
      -- statt einfach zu verschwinden.
      if v_i = 5 then
        update kontrollpalette set beendet_ts = (current_date - 12)::timestamptz + interval '11 hours',
               beendet_grund = 'Palette verarbeitet'
         where id = v_kp;
      end if;
    end loop;
    raise notice 'Demo: Kontrollpaletten angelegt (% Stück, % Wägungen)',
      (select count(*) from kontrollpalette where bemerkung = 'DEMO'),
      (select count(*) from kontrollpalette_wiegung);
  end;

  -- ---------- 6c. Die Verkaufsdatei als Datei ------------------------------
  -- Die Zeilen der Warenwirtschaft kommen im Betrieb nicht einzeln, sondern
  -- als Excel-Datei: einmal im Monat hochgeladen, mit Prüfsumme und Zeitraum.
  -- Ohne diesen Abschnitt stand der Warenausgang-Import der Demo ohne eine
  -- einzige Datei da — als wäre die Ware aus dem Nichts gekommen.
  declare m record; v_datei bigint; v_n int; v_korr_monat date;
  begin
    -- Der Monat, dessen Datei ein zweites Mal hochgeladen wurde: der erste
    -- mit mindestens zwei Zeilen. Die Demo hängt am heutigen Datum; fällt
    -- die erste Lieferung ans Monatsende, hat der erste Monat nur eine
    -- Zeile — und eine Datei, die „2 geändert" sagt, während nur eine
    -- Zeile eine Änderungszeit trägt, wäre ein Fehler der Demo (0096).
    select date_trunc('month', datum)::date into v_korr_monat
      from ausgang_zeile where quelle = 'DEMO'
     group by 1 having count(*) >= 2 order by 1 limit 1;
    for m in
      select date_trunc('month', datum)::date as monat, min(datum) as von, max(datum) as bis,
             count(*)::int as n
        from ausgang_zeile where quelle = 'DEMO' group by 1 order by 1
    loop
      insert into ausgang_datei (quelle, dateiname, pruefsumme, n_zeilen, n_kuerbis, n_neu,
                                 n_geaendert, n_unveraendert, von_datum, bis_datum, bemerkung,
                                 hochgeladen_von, ts)
      values ('DEMO', format('Lieferungen_%s.xlsx', to_char(m.monat, 'YYYY-MM')),
              format('demo-datei-%s', to_char(m.monat, 'YYYYMM')),
              m.n + 4, m.n, m.n - (case when m.monat = v_korr_monat then 2 else 0 end),
              case when m.monat = v_korr_monat then 2 else 0 end,
              4, m.von, m.bis, 'DEMO', v_wer,
              (m.bis + 2)::timestamptz + interval '8 hours')
      returning id into v_datei;
      update ausgang_zeile set datei_id = v_datei
       where quelle = 'DEMO' and date_trunc('month', datum)::date = m.monat;
      -- Dieser Monat wurde ein zweites Mal hochgeladen, weil zwei Positionen
      -- in der Warenwirtschaft nachträglich korrigiert worden waren. Die Datei
      -- zählt sie als geändert, und die Zeilen tragen ihre Änderungszeit.
      if v_datei is not null and m.monat = v_korr_monat then
        update ausgang_zeile set geaendert_ts = (m.bis + 9)::timestamptz + interval '8 hours'
         where id in (select id from ausgang_zeile where datei_id = v_datei order by pos_id limit 2);
      end if;
    end loop;
    -- Zwei Abweichungen, wie sie wirklich vorkommen: einmal wurde eine
    -- Lieferung von Hand nachkorrigiert, einmal blieb eine Palette am Rampen-
    -- rand stehen. Der Abgleich „Datei gegen Lieferung" soll in der Demo nicht
    -- leer sein — sonst sieht niemand, dass es ihn gibt.
    -- Sortiert nach Datum, Charge und Menge, nicht nach der laufenden Nummer:
    -- die Nummer ist nach einem Neuaufbau eine andere, das Datum nicht.
    update lieferung set kg = round(kg * 0.94, 1)
     where id in (select l.id from lieferung l join lieferung_import i on i.lieferung_id = l.id
                   where l.bemerkung = 'DEMO' and l.kg > 400
                   order by l.datum, l.charge_nr, l.kg limit 1);
    update lieferung set kg = round(kg * 1.07, 1)
     where id in (select l.id from lieferung l join lieferung_import i on i.lieferung_id = l.id
                   where l.bemerkung = 'DEMO' and l.kg > 400
                   order by l.datum desc, l.charge_nr desc, l.kg desc limit 1);
    raise notice 'Demo: Verkaufsdateien angelegt (%)', (select count(*) from ausgang_datei where bemerkung = 'DEMO');
  end;

  -- ---------- 6d. Ernte abgeschlossen --------------------------------------
  -- Solange die Ernte einer Charge läuft, wandert ihr mittleres Eingangsdatum
  -- mit jeder Palette, und jede Altersangabe trägt den Zusatz „Ernte läuft
  -- noch". Für die früh geernteten Chargen hat der Betrieb längst gesagt, dass
  -- nichts mehr kommt — die späten stehen noch offen. Beides soll man sehen.
  update charge set ernte_abgeschlossen_ts = (
           select max(p.eingangsdatum) + 3 from palette p where p.charge_nr = charge.nr)::timestamptz + interval '18 hours'
   where nr in (select nr from demo_charge where kw <= 37)
     and ernte_abgeschlossen_ts is null
     and exists (select 1 from palette p where p.charge_nr = charge.nr and p.extern_id like 'demo-%');

  -- ---------- 7. Sonderfälle, wie sie in jeder Saison vorkommen -------------
  declare v_auftrag bigint; v_datum date; v_id bigint;
  begin
    -- (1) Eine abgebrochene Arbeit: falsche Charge gewählt
    insert into auftrag (weg, station, charge_nr, start_ts, bemerkung)
    values ('hand', 'waschen_sortieren', 1611, (v_anker + 63)::timestamptz + interval '9 hours', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, datum from demo_pal where nr = 1611 order by id limit 3;
    perform auftrag_abbrechen(v_auftrag, 'Falsche Charge gewählt');

    -- (2) Ein Zahlendreher beim Palox: 4500 statt 450 kg — die Rechnung lässt
    --     ihn aus, die Auffälligkeiten melden ihn ganz oben.
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
    values ('hand', 'waschen_sortieren', 1611, (v_anker + 70)::timestamptz + interval '8 hours',
            (v_anker + 70)::timestamptz + interval '15 hours', 'abgeschlossen', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, datum from demo_pal where nr = 1611 and not verarbeitet order by datum limit 6;
    update demo_pal set verarbeitet = true where id in (select id from demo_pal where nr = 1611 and not verarbeitet order by datum limit 6);
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 4500, 4545, (v_anker + 70)::timestamptz + interval '14 hours');
    insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

    -- (3) Ein Zetteldatum, das zu keiner Palette passt (12 und 21 vertauscht)
    select datum into v_datum from demo_pal where nr = 1613 order by datum limit 1;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select a.id, v_datum + 9 from auftrag a where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
     order by a.start_ts limit 1;

    -- (4) Ein Waschgang ohne gezählte Kisten: die Messung hat keinen Nenner
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx, bemerkung)
    values ('maschine', 'waschen', 1614, (v_anker + 95)::timestamptz + interval '8 hours',
            (v_anker + 95)::timestamptz + interval '11 hours', 'abgeschlossen', 1, 'DEMO')
    returning id into v_auftrag;
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 9, 300, (v_anker + 95)::timestamptz + interval '10 hours');

    -- (5) Eine Sortier-CSV, die keiner Arbeit zugeordnet ist (Warteschlange)
    perform csv_lauf_speichern(1619, 'DEMO-1619-ohne-arbeit', 'demo/sortierdateien/1619-ohne-arbeit.csv',
      'demo-pruefsumme-warteschlange',
      (v_anker + 130)::timestamptz + interval '13 hours', 'dateiname',
      '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
      420, 1, 3, 6,
      '[[800,40],[900,90],[1000,120],[1100,100],[1200,50],[1300,10]]'::jsonb);

    -- (6) Drei laufende Arbeiten von heute — damit die Masken nicht leer sind
    insert into auftrag (weg, station, charge_nr, start_ts, status, kaeufer, sortierschema_id, bemerkung,
                         kistensystem, soll_kg_pro_kiste)
    values ('hand', 'waschen_sortieren', 1631, now() - interval '2 hours', 'offen', 'nordmarkt',
            sortierschema_fuer('Mieluna', null, current_date, 'kiste'), 'DEMO', 'kiste_ab', 8)
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg)
    select v_auftrag, dp.datum, (select pl.brutto_kg from palette pl where pl.id = dp.id)
      from demo_pal dp where dp.nr = 1631 and not dp.verarbeitet order by dp.datum desc limit 3;
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 0, 45, now() - interval '110 minutes');

    insert into auftrag (weg, station, charge_nr, start_ts, status, kaliber_idx, bemerkung)
    select 'maschine', 'waschen', l.nr, now() - interval '90 minutes', 'offen', 0, 'DEMO'
      from demo_lauf l join auftrag a on a.id = l.auftrag_id
     where a.station = 'sortieren' and l.kisten[1] > 0 order by l.start_ts desc limit 1
    returning id into v_auftrag;
    if v_auftrag is not null then
      update auftrag set kistensystem = 'stueck', stueck_je_kiste = 6 where id = v_auftrag;
      insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl, sortierdatum) values (v_auftrag, 0, 6, current_date - 21);
    end if;

    insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, status, kaeufer, bemerkung)
    select 'maschine', 'waschen', l.nr, true, now() - interval '50 minutes', 'offen', 'talhof', 'DEMO'
      from demo_lauf l join auftrag a on a.id = l.auftrag_id
     where a.station = 'sortieren' order by l.start_ts limit 1
    returning id into v_auftrag;
    if v_auftrag is not null then
      update auftrag set kistensystem = 'stueck', stueck_je_kiste = 6 where id = v_auftrag;
      insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, ts)
      values (v_auftrag, 0, 8.5, 1, 'G2', now() - interval '20 minutes');
    end if;

    -- (7) Ein Palox, der zwischendurch geleert wurde, ohne dass jemand abgelesen
    --     hat: der Stand fällt von 410 auf 130. Die Menge dieser Arbeit ist
    --     unbekannt (0060) — die Auswertung sagt es, der Arbeiter wird nicht gefragt.
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, kistensystem, soll_kg_pro_kiste)
    values ('hand', 'waschen_sortieren', 1613, (v_anker + 118)::timestamptz + interval '8 hours',
            (v_anker + 118)::timestamptz + interval '14 hours', 'abgeschlossen', 'DEMO', 'kiste_ab', 8)
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg)
    select v_auftrag, dp.datum, (select pl.brutto_kg from palette pl where pl.id = dp.id)
      from demo_pal dp where dp.nr = 1613 and not dp.verarbeitet order by dp.datum limit 4;
    update demo_pal set verarbeitet = true where id in (select id from demo_pal where nr = 1613 and not verarbeitet order by datum limit 4);
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts)
    values (v_auftrag, 0, 410, (v_anker + 118)::timestamptz + interval '8 hours 10 minutes'),
           (v_auftrag, 0, 130, (v_anker + 118)::timestamptz + interval '13 hours 50 minutes');
    insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

    raise notice 'Demo: Sonderfälle und laufende Arbeiten angelegt';
  end;

  -- ---------- 8. Beteiligte an den laufenden Arbeiten ------------------------
  insert into auftrag_teilnehmer (auftrag_id, profil_id)
  select a.id, v_wer from auftrag a where a.bemerkung = 'DEMO' and a.status = 'offen'
  on conflict do nothing;

  -- ---------- 9. Rückmeldungen aus der Halle (0091, 0093, 0094) --------------
  -- Geschrieben, nicht gesprochen: Eine Aufnahme wäre eine Datei im Bucket,
  -- und die kann eine SQL-Funktion nicht anlegen. Jede Rückmeldung steht kurz
  -- nach dem Ende der Arbeit bei einer Person, die daran beteiligt war — die
  -- Arbeit aus Sonderfall 7 hat keine Beteiligten, dort ist es der
  -- Betriebsleiter selbst. Und sie steht an Arbeiten, an denen man sie im
  -- Dashboard auch findet.
  --
  -- 0094: Was die Halle sagt, ist die halbe Geschichte; was das Dashboard
  -- zeigt, ist die Kurzfassung, die jemand daraus gemacht hat — die Runde am
  -- Programm oder der Betriebsleiter. Drei der vier zur Ware sind gekürzt;
  -- die vierte ist noch nicht gelesen und steht darum noch nirgends.
  declare v_a1 bigint; v_a2 bigint; v_a3 bigint; v_a4 bigint;
  begin
    -- (1) Zur Ware, an der Sortier-Arbeit der Charge 1628 (Hagel auf dem
    --     hinteren Feld) mit dem meisten Faulen — fest an der Charge, denn die
    --     Demo hängt am Datum, und „die Arbeit mit dem meisten Faulen" wechselt
    --     sonst über Nacht die Charge (Runde AI, Prüfblock 0093 am 29. 9.).
    select a.id into v_a1
      from auftrag a join schimmel_messung s on s.auftrag_id = a.id
     where a.bemerkung = 'DEMO' and a.status = 'abgeschlossen' and a.station = 'sortieren' and a.charge_nr = 1628
     order by s.kg desc, a.id limit 1;
    -- (2) Zur Ware, an der Arbeit mit dem falschen Zetteldatum (Sonderfall 3):
    --     die Auffälligkeit zeigt die Kurzfassung mit an.
    select a.id into v_a2 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
     order by a.start_ts limit 1;
    -- (3) Zur Ware und (4) zur App, an der Arbeit, deren Palox zwischendurch
    --     geleert wurde (Sonderfall 7): beide Arten an einer Arbeit, wie es
    --     das Arbeitsfenster und Betrieb → Arbeiten zeigen.
    select a.id into v_a3 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
       and exists (select 1 from schimmel_messung s where s.auftrag_id = a.id and s.palox_stand_kg = 410)
     order by a.start_ts limit 1;
    -- (5) Zur Ware, noch nicht gelesen: an der ersten Wasch+Sortier-Arbeit
    --     der Charge 1636 — unter Betrieb → Arbeiten wartet sie auf ihre
    --     Kurzfassung, im Dashboard steht sie noch nicht.
    select a.id into v_a4 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1636 and a.station = 'waschen_sortieren' and a.status = 'abgeschlossen'
     order by a.start_ts limit 1;
    if v_a1 is null or v_a2 is null or v_a3 is null or v_a4 is null then
      raise exception 'Demo: die Arbeiten für die Rückmeldungen fehlen — die Saison oben hat sich geändert.';
    end if;
    insert into auftrag_rueckmeldung (auftrag_id, art, text, erfasser, ts, kurz, kurz_quelle, kurz_ts)
    select r.auftrag_id, r.art, r.text,
           coalesce((select t.profil_id from auftrag_teilnehmer t
                      where t.auftrag_id = r.auftrag_id order by t.profil_id limit 1), v_wer),
           coalesce(a.ende_ts, a.start_ts) + make_interval(mins => 3 * r.nr),
           r.kurz, r.quelle,
           case when r.kurz is not null then coalesce(a.ende_ts, a.start_ts) + make_interval(days => 1, hours => 8) end
      from (values
              (1, v_a1, 'ware',
               'Also am Anfang habe ich gedacht, das ist normal, aber dann waren so viele mit Dellen und Rissen, '
               'ich glaube das war der Hagel im Juli auf dem hinteren Feld, darum haben wir so viel weggeworfen.',
               'Hagelschaden', 'runde'),
              (2, v_a2, 'ware',
               'Der Zettel war nass, das Datum konnte man kaum lesen, ich habe 13. geschrieben, kann auch 31. gewesen sein.',
               'Zettel nass, Datum unsicher', 'betriebsleiter'),
              (3, v_a3, 'ware',
               'Sehr viel Faules, der Palox war randvoll — wir haben ihn zwischendurch geleert.',
               'Viel Faules, Palox zwischendurch geleert', 'runde'),
              (4, v_a3, 'app',
               'Wo trage ich ein, dass der Palox geleert wurde? Ich habe es nicht gefunden.',
               null, null),
              (5, v_a4, 'ware',
               'Die Kürbisse waren viel kleiner als sonst, fast alles K1, und ein paar mit weichen Stellen.',
               null, null)
           ) as r(nr, auftrag_id, art, text, kurz, quelle)
      join auftrag a on a.id = r.auftrag_id
     order by r.nr;
    raise notice 'Demo: Rückmeldungen aus der Halle angelegt (drei gekürzt, eine ungelesen, eine zur App)';
  end;

  -- ---------- 7. Runde AS (0116): Hagel, Ausreisser, Kunden, ein Plan ----
  -- Was die Runde neu kann, kommt in der Demo vor (0081 b): ein Hagelschaden
  -- an der Charge, deren Arbeit die Halle mit „Hagelschaden" gemeldet hat;
  -- der randvolle Palox als von Hand ausgeschlossener Ausreisser, dazu eine
  -- Verdunstungs-Wägung; zwei Kunden in einer Gruppe; ein Plan; und eine
  -- Perigon-Zeile, deren Artikel einer anderen Gruppe ist als die Sorte
  -- ihrer Charge.
  declare v_ch int; v_a bigint; v_w bigint; v_saison int; v_z bigint;
  begin
    select a.charge_nr into v_ch from auftrag_rueckmeldung r join auftrag a on a.id = r.auftrag_id
     where a.bemerkung = 'DEMO' and r.kurz = 'Hagelschaden' order by a.start_ts limit 1;
    update charge set hagel_anteil = 0.20, hagel_ts = v_jetzt where nr = v_ch;
    -- Der Ausreisser: die späte Sortier-Arbeit der Charge 1630, der höchste
    -- Palox-Anteil der Demo (rund 14 %) — ein Messpunkt, der sonst zählte.
    select a.id into v_a from auftrag a
     where a.bemerkung = 'DEMO' and a.station = 'sortieren' and a.charge_nr = 1630
     order by a.start_ts desc limit 1;
    if v_a is not null then
      insert into messung_ausschluss (art, bezug_id, grund, erfasser, ts)
      values ('palox', v_a, 'DEMO — Palox randvoll, viele zu kleine darin: nicht typisch', v_wer, v_jetzt)
      on conflict do nothing;
    end if;
    select w.id into v_w from verdunstung_wiegung w join auftrag a on a.id = w.auftrag_id
     where a.bemerkung = 'DEMO' and w.gemessen order by w.wiege_ts desc, w.id desc limit 1;
    if v_w is not null then
      insert into messung_ausschluss (art, bezug_id, grund, erfasser, ts)
      values ('verdunstung', v_w, 'DEMO — Ausreisser', v_wer, v_jetzt)
      on conflict do nothing;
    end if;
    insert into kunde_gruppe (kunde, gruppe, erfasser, ts)
    values ('Nordmarkt Verteilzentrale', 'Grosshandel', v_wer, v_jetzt), ('Feldfrisch Ost', 'Grosshandel', v_wer, v_jetzt)
    on conflict (kunde) do nothing;
    select saison_von(max(datum)) into v_saison from ausgang_zeile where quelle = 'DEMO';
    insert into kunde_plan (saison, kunde, artikelgruppe, groesse, label, kg, erfasser, ts)
    select v_saison, 'Talhof Bio AG', '', '', '', round(sum(kg_position) * 1.6, -2), v_wer, v_jetzt
      from ausgang_zeile where quelle = 'DEMO' and kunde = 'Talhof Bio AG'
    having sum(kg_position) > 0
    on conflict do nothing;
    -- Eine Perigon-Zeile als Mandarin verkauft, geliefert aus einer Knirps-Charge (Kaori Kuri).
    select z.id into v_z from ausgang_zeile z join charge c on c.nr::text = z.charge_extern
     where z.quelle = 'DEMO' and c.sorte = 'Kaori Kuri' order by z.datum desc, z.pos_id desc limit 1;
    insert into ausgang_artikel (artikel_id, artikel, ist_kuerbis, sorte, bemerkung)
    values ('kürbmand', 'Bio Kürbis Mandarin Dem', true, null, 'DEMO') on conflict (artikel_id, artikel) do nothing;
    update ausgang_zeile set artikel_id = 'kürbmand', artikel = 'Bio Kürbis Mandarin Dem' where id = v_z;
    raise notice 'Demo: Hagel an Charge %, Ausreisser ausgeschlossen, eine Kundengruppe, ein Plan, eine Perigon-Auffälligkeit (0116)', v_ch;
  end;

  drop table if exists demo_charge; drop table if exists demo_pal; drop table if exists demo_lauf;

  -- Die Auswertung wird hier absichtlich nicht neu gerechnet: Supabase gibt
  -- einem API-Aufruf acht Sekunden, und das Rechnen ist der teuerste Teil.
  -- Die App ruft auswertung_aktualisieren() gleich danach als eigenen
  -- Aufruf; demo_daten.sql tut dasselbe. Bis dahin steht die Auswertung als
  -- veraltet da — die Auslöser an den Tabellen haben das schon vermerkt.
  return (
    select format('Demo-Saison steht: %s Paletten in %s Chargen, %s Arbeiten (davon %s Fax), %s Sortierläufe, '
                  || '%s Lieferungen, %s Kontrollpaletten mit %s Wägungen, %s Verkaufsdateien, %s Rückmeldungen. '
                  || 'Eingang %s t. Jetzt in der App unter Lagermanagement anschauen.',
                  (select count(*) from palette where extern_id like 'demo-%'),
                  (select count(distinct charge_nr) from palette where extern_id like 'demo-%'),
                  (select count(*) from auftrag where bemerkung = 'DEMO'),
                  (select count(*) from auftrag where bemerkung = 'DEMO' and ist_fax),
                  (select count(*) from sortier_lauf where datei_name like 'DEMO-%'),
                  (select count(*) from lieferung where bemerkung = 'DEMO'),
                  (select count(*) from kontrollpalette where bemerkung = 'DEMO'),
                  (select count(*) from kontrollpalette_wiegung),
                  (select count(*) from ausgang_datei where bemerkung = 'DEMO'),
                  (select count(*) from auftrag_rueckmeldung r join auftrag a on a.id = r.auftrag_id where a.bemerkung = 'DEMO'),
                  (select round(sum(eingang_netto_kg) / 1000, 1) from v_charge_rueckgrat))
  );
end $fn$;

comment on function demo_daten_laden is
  'Legt die erfundene Demo-Saison an (Arbeiten mit bemerkung = ''DEMO'', Paletten mit extern_id ''demo-…'', Sortierdateien ''DEMO-…'', Lieferungen und Verkaufsdateien ''DEMO'', Kontrollpaletten mit bemerkung ''DEMO''; seit 0116 ein Hagelschaden, zwei ausgeschlossene Ausreisser, eine Kundengruppe und ein Plan). Echte Daten bleiben unberührt; im Echtmodus lässt sie sich gar nicht laden (0072). Deterministisch: zweimal laden gibt zweimal dieselbe Saison (0081).';
grant execute on function demo_daten_laden() to authenticated;

create or replace function demo_daten_entfernen()
returns text language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter entfernen.';
  end if;

  -- Zuerst der Erntestand: er wird an den Demo-Paletten erkannt.
  update charge set ernte_abgeschlossen_ts = null
   where ernte_abgeschlossen_ts is not null
     and nr in (select distinct charge_nr from palette where extern_id like 'demo-%');
  -- 0116: Hagel, Ausschlüsse, Kundengruppen und Pläne der Demo — vor den
  -- Arbeiten und Wägungen, an denen die Ausschlüsse hängen.
  update charge set hagel_anteil = null, hagel_ts = null
   where hagel_anteil is not null
     and nr in (select distinct charge_nr from palette where extern_id like 'demo-%');
  -- Auch wenn die Wägung oder Arbeit dazu schon weg ist: der Grund sagt DEMO.
  delete from messung_ausschluss
   where grund like 'DEMO %'
      or (art = 'palox' and bezug_id in (select id from auftrag where bemerkung = 'DEMO'))
      or (art in ('verdunstung', 'palox_lager')
          and bezug_id in (select id from verdunstung_wiegung
                            where auftrag_id in (select id from auftrag where bemerkung = 'DEMO')
                               or bemerkung = 'DEMO-KONTROLLE'));
  delete from kunde_gruppe where kunde in ('Nordmarkt Verteilzentrale', 'Feldfrisch Ost')
     and exists (select 1 from ausgang_zeile where quelle = 'DEMO');
  delete from kunde_plan where kunde in ('Nordmarkt Verteilzentrale', 'Talhof Bio AG', 'Grünwerk Handel', 'Feldfrisch Ost')
     and exists (select 1 from ausgang_zeile where quelle = 'DEMO');

  -- Die Kontrollpaletten vor den Paletten — sie zeigen mit palette_id darauf.
  delete from kontrollpalette_wiegung
   where kontrollpalette_id in (select id from kontrollpalette where bemerkung = 'DEMO');
  delete from kontrollpalette where bemerkung = 'DEMO';

  -- Reihenfolge ist wichtig: verdunstung_wiegung und sortier_lauf hängen mit
  -- "on delete set null" am Auftrag — würde man den Auftrag zuerst löschen,
  -- blieben ihre Zeilen verwaist zurück und zählten weiter mit.
  delete from verdunstung_wiegung
   where auftrag_id in (select id from auftrag where bemerkung = 'DEMO')
      or bemerkung = 'DEMO-KONTROLLE';
  delete from ausgang_wiegung
   where auftrag_id in (select id from auftrag where bemerkung = 'DEMO');
  delete from sortier_gewicht
   where lauf_id in (select id from sortier_lauf where datei_name like 'DEMO-%');
  delete from sortier_lauf where datei_name like 'DEMO-%';

  -- Der Rest hängt mit "on delete cascade" am Auftrag
  delete from lieferung where bemerkung = 'DEMO';      -- lieferung_import kaskadiert
  delete from ausgang_zeile where quelle = 'DEMO';
  delete from ausgang_datei where quelle = 'DEMO' and bemerkung = 'DEMO';
  delete from ausgang_artikel where bemerkung = 'DEMO';
  delete from ausgang_quelle where code = 'DEMO' and bemerkung = 'DEMO';
  delete from auftrag where bemerkung = 'DEMO';
  delete from charge_vorlauf where bemerkung like 'DEMO%';
  delete from palette where extern_id like 'demo-%';
  delete from sortierschema where bemerkung like 'DEMO%';
  -- Nur die von der Demo angelegten Käufer, und auch die nur, wenn nichts
  -- mehr an ihnen hängt. Ein Käufer, den der Betrieb selbst eingetragen hat,
  -- bleibt — auch wenn er zufällig denselben Code trägt.
  delete from kaeufer k where k.bemerkung = 'DEMO'
     and not exists (select 1 from auftrag a where a.kaeufer = k.code)
     and not exists (select 1 from sortierschema s where s.kaeufer = k.code);

  -- Kein Neurechnen hier — siehe demo_daten_laden(): eigener Aufruf danach.
  return (
    select format('Demo-Daten entfernt. Übrig: %s Paletten, %s Arbeiten, %s Sortierläufe, %s Kontrollpaletten.',
                  (select count(*) from palette),
                  (select count(*) from auftrag),
                  (select count(*) from sortier_lauf),
                  (select count(*) from kontrollpalette))
  );
end $fn$;

comment on function demo_daten_entfernen is
  'Löscht restlos alles, was demo_daten_laden() angelegt hat — samt Kontrollpaletten, Verkaufsdateien, dem Erntestand und (seit 0116) dem Hagel, den Ausschlüssen, Kundengruppen und Plänen der Demo. Echte Daten bleiben unberührt; erkannt wird die Demo an bemerkung = ''DEMO'', extern_id ''demo-…'' und datei_name ''DEMO-…'' (0081).';
grant execute on function demo_daten_entfernen() to authenticated;

-- Die Vorjahre der Demo (0115) mit der ganzen Zeile je Position (0116).
create or replace function demo_vorjahre_laden() returns text
language plpgsql security definer set search_path = public as $fn$
declare
  v_saison int;
  v_erste date;
  v_n int := 0;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter laden.';
  end if;
  if not exists (select 1 from ausgang_quelle where code = 'DEMO') then
    return 'Keine Demo-Verkaufsdatei — keine Vorjahre.';
  end if;
  -- Das Label der gelieferten Charge, wie Perigon es führt: jede vierte Knospe.
  update ausgang_zeile z
     set liefer_label = case when z.charge_extern ~ '^[0-9]+$' and z.charge_extern::int % 4 = 1 then 'K' else 'D' end,
         preisgruppe  = case when z.charge_extern ~ '^[0-9]+$' and z.charge_extern::int % 4 = 1 then 'K' else 'D' end
   where z.quelle = 'DEMO' and z.liefer_label is null;
  -- Die laufende Saison ist die der jüngsten Demo-Lieferung. Die Demo beginnt
  -- im Frühling davor — was vor ihrer ersten Lieferung liegt, kommt dazu.
  select saison_von(max(datum)), min(datum) into v_saison, v_erste from ausgang_zeile where quelle = 'DEMO';
  if v_saison is null then return 'Keine Demo-Lieferungen — keine Vorjahre.'; end if;
  delete from ausgang_position where quelle = 'DEMO' and saison < v_saison;
  -- Je Kunde und Vorjahr eine Lieferung je Woche, nach einer Glocke über
  -- die Saison (Höhepunkt im Oktober), Grösse je Kunde aus der laufenden Saison.
  insert into ausgang_position (quelle, pos_id, datum, saison, journal, kunde, artikel_id, artikel, preisgruppe,
                                einheit, menge, gewicht_je_artikel, kg, gebindeart, gebinde_menge)
  select 'DEMO', 900000000 + j.jahr * 100000 + k.nr * 1000 + w.woche,
         make_date(v_saison - j.jahr, 7, 1) + (w.woche * 7),
         v_saison - j.jahr, 'Lieferschein', k.kunde, k.artikel_id, k.artikel, 'D', 'kg',
         x.kg, 1, x.kg, 'IFCO', null
    from (select row_number() over (order by z.kunde)::int as nr, z.kunde,
                 min(z.artikel_id) as artikel_id, min(z.artikel) as artikel,
                 greatest(sum(z.kg_position) / greatest(count(distinct date_trunc('week', z.datum)), 1), 50) as je_woche
            from ausgang_zeile z where z.quelle = 'DEMO' and z.kunde is not null group by z.kunde) k
   cross join (values (1, 1.0), (2, 0.8)) j(jahr, faktor)
   cross join generate_series(0, 51) w(woche)
   cross join lateral (select round(k.je_woche * j.faktor * (0.6 + 0.08 * k.nr)
                                    * exp(-power((w.woche - 15) / 9.0, 2))
                                    * (0.8 + 0.4 * ((k.nr * 7 + w.woche * 13 + j.jahr * 5) % 10) / 10.0)) as kg) x
   where x.kg >= 20
     and make_date(v_saison - j.jahr, 7, 1) + (w.woche * 7) < v_erste
  on conflict (quelle, pos_id) do nothing;
  get diagnostics v_n = row_count;
  -- 0115: Wie beim Betrieb 2024/25 (Muscade, 12'322 Stück): ein Kunde bekam
  -- im Vorjahr auch Stück, für die Perigon kein Stückgewicht kennt. Sie
  -- stehen ohne kg da — nicht 0, nicht geschätzt.
  insert into ausgang_position (quelle, pos_id, datum, saison, journal, kunde, artikel_id, artikel, preisgruppe,
                                einheit, menge, gewicht_je_artikel, kg, gebindeart, gebinde_menge)
  select 'DEMO', 900000000 + 100000 + k.nr * 1000 + 500 + w.woche,
         make_date(v_saison - 1, 7, 1) + (w.woche * 7), v_saison - 1, 'Lieferschein', k.kunde,
         'kürbmudkl', 'Bio Kürbis Muscade Dem klein', 'D', 'Stk.', 40 + 20 * (w.woche % 3), 0,
         perigon_kg(40 + 20 * (w.woche % 3), 0, 'Stk.'), 'IFCO', null
    from (select row_number() over (order by z.kunde)::int as nr, z.kunde
            from ausgang_zeile z where z.quelle = 'DEMO' and z.kunde is not null group by z.kunde) k
   cross join generate_series(12, 18) w(woche)
   where k.nr = 1 and make_date(v_saison - 1, 7, 1) + (w.woche * 7) < v_erste
  on conflict (quelle, pos_id) do nothing;
  -- 0116: die ganze Zeile, wie sie in der Perigon-Datei stünde — damit das
  -- Lieferungs-Fenster auch in der Beispieldatenbank zeigt, was es kann.
  -- Ohne Erlös: Preise gehören nicht in die Demo.
  update ausgang_position p
     set roh = jsonb_build_array(jsonb_build_object(
           'AuftragsJournal', p.journal, 'AuftragsLieferDatum', to_char(p.datum, 'DD.MM.YYYY'),
           'AuftragsLieferant', p.kunde, 'AufPosId', p.pos_id, 'AuftragsArtId', p.artikel_id, 'AuftragsArtikel', p.artikel,
           'AuftragsArtikelMenge', p.menge, 'AuftragsArtikelEinheit', p.einheit, 'GewichtProArtikel', p.gewicht_je_artikel,
           'AuftragsChargeManuell', null, 'AufPosBatchQuantity Charge', null, 'AuftragsGebBez', p.gebindeart,
           'AuftragsGebindemenge', p.gebinde_menge, 'AuftragsPrsGrpBez', p.preisgruppe, 'LiefPrsGrpName', p.preisgruppe,
           'AuftragsErloesTotExkl', null))
   where p.quelle = 'DEMO' and p.roh is null;
  return format('Demo: %s Lieferungen in zwei Vorjahren, Labels an den Demo-Verkaufszeilen.', v_n);
end $fn$;
comment on function demo_vorjahre_laden() is
  'Ergänzt die Demo um das Perigon-Label je Verkaufszeile und zwei Vorjahre je Demo-Kunde (ausgang_position, quelle DEMO) — für Lager nach Artikel (0112); seit 0115 mit ein paar Stück ohne Stückgewicht im Vorjahr (kg leer), seit 0116 mit der ganzen Zeile (roh). Gleich nach demo_daten_laden() aufrufen; demo_daten_entfernen() räumt es mit der Demo-Firma weg.';
-- security definer: ohne das „revoke" könnte sie jeder rufen, auch ohne
-- Anmeldung (auth.uid() ist dann leer und die Sperre oben greift nicht).
revoke all on function demo_vorjahre_laden() from public;
grant execute on function demo_vorjahre_laden() to authenticated;

-- =====================================================================
-- 9. Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 116 $$;
