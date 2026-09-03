-- =====================================================================
-- 0036 — Die Kette: was erfasst wird, kommt an — und was fehlt, ist unbekannt
--
-- Gefunden beim Rückwärtsgehen von jeder Dashboard-Zahl bis zur Rohzeile.
-- Sechs Befunde, alle am laufenden System nachgemessen, alle hier behoben.
--
-- ---------- 1. Ohne Wägung stand die Verdunstung auf 0 kg — mit Bereich ---
-- v_koeff_verdunstung lieferte coalesce(mittel, 0): Gab es in der ganzen
-- Datenbank keine einzige Palettenwägung, hiess der Koeffizient 0, und die
-- Kaskade rechnete damit weiter. Im Ranking stand dann
--
--   Verdunstung   0.00 kg   Bereich 0.00 – 0.00 kg
--
-- Das ist eine Zahl, die aussieht wie gemessen, und sie sagt das Gegenteil
-- der Wahrheit: „kein Verlust" statt „nicht gemessen". Dasselbe bei Ausschuss
-- und Nebenkanal ohne Sortier-CSV und ohne Handmessung. Leer ist nicht null —
-- die Regel galt für Tara und Messwerte, für die Koeffizienten galt sie nicht.
--
-- Jetzt bleibt ein Koeffizient ohne Messung NULL. Die Kaskade rechnet die
-- Masse weiter, als würde nichts abgezogen (etwas Besseres gibt es nicht),
-- aber der Strom selbst ist NULL und das Ranking sagt „nicht gemessen".
--
-- ---------- 2. Messungen ohne Nenner verschwanden spurlos -----------------
-- Ein Auftrag mit 80 kg Schimmel, bei dem niemand Paletten gezählt hat, und
-- ein Waschgang mit 112 kg Schimmel ohne verarbeitete Menge: beide erzeugen
-- keinen Punkt im Verderbsmodell, und keine Ansicht meldete es.
--
--   erfasst 242 kg  →  angekommen 50 kg
--
-- Das ist die Fehlerart, die in diesem Projekt schon zweimal vorkam (Schimmel
-- #2 vor 0024). v_plausibilitaet listet solche Arbeiten jetzt auf, mit dem
-- Rat, was nachzutragen ist. Ebenso Palettenwägungen, die nicht verwertbar
-- sind (Tara fehlt, Datum verkehrt), ohne dass sichtbar Faules der Grund war.
--
-- ---------- 3. Die Palox-Waage zeigt brutto, und der Behälter wiegt 45 kg --
-- Vom Betrieb bestätigt (2. September). Bei der Differenz zweier Stände kürzt
-- sich das Leergewicht weg. Nach dem Leeren und bei der ersten Ablesung einer
-- Station galt aber der volle Stand als Menge — samt Behälter. Jedes Leeren
-- buchte 45 kg Schimmel, die keiner war. Die Tara steht jetzt als Einstellung
-- (palox_tara_kg) und wird dort abgezogen, wo der Stand selbst die Menge ist.
--
-- Dazu die Regel aus docs/Datenarchitektur: gespeichert wird, was beobachtet
-- wurde — der Waagenstand. Die Menge ist Ableitung. Wo ein Stand erfasst ist,
-- rechnet die Auswertung ab jetzt mit der aus den Ständen abgeleiteten Menge
-- (v_schimmel_menge), nicht mit dem Kilo-Wert, den die App damals daraus
-- gebildet hat. Ändert sich die Tara, ändert sich die Menge mit — der Stand
-- bleibt, wie er abgelesen wurde.
--
-- ---------- 4. Der Lagerbestand bekam das Alter der ganzen Charge ----------
-- alter_lager = Stichtag − massegewichtetes Eingangsdatum aller Paletten der
-- Charge. Die noch liegenden Paletten sind aber nicht „alle": Wird zuerst
-- verarbeitet, was zuletzt kam (gestapeltes Lager — der Betrieb hat gesagt,
-- man kommt nicht an jede Palette), sind die übrigen die ältesten. In der
-- Demo-Saison lagen die restlichen Paletten drei bis sechs Tage neben dem
-- Chargenmittel. Bei k = 1.6 sind fünf Tage auf 180 rund 4.5 % Verderb —
-- systematisch, nicht zufällig. Die Eingangsdaten der gezählten Paletten
-- sind bekannt (Pflichtfeld). Also wird das Alter jetzt aus den *nicht
-- gezählten* Paletten gebildet; erst wenn keine Zählung ein Datum trägt,
-- gilt wieder das Chargenmittel.
--
-- ---------- 5. Der Restbestand war zu klein, die Lücke zu gross ----------
-- v_saisonbilanz rechnete den Restbestand als „verkaufsfähig" der liegenden
-- Ware — also nach Abzug von zu klein und zu gross, die aber erst beim
-- Verarbeiten aussortiert werden und heute noch physisch im Lager liegen.
-- In der Demo fehlten so 12.5 t im Bestand, und die Lücke enthielt sie als
-- „unerklärt". Der Restbestand ist jetzt die Masse nach Verdunstung und
-- Verderb (m2), ohne die Aufteilung, die noch gar nicht stattgefunden hat.
--
-- ---------- 6. Die Kistenzahl der Überfüllung war fest verdrahtet ---------
-- v_marge_buch teilte die Weg-2-Masse durch 8.0, die Kennzahl je Palette las
-- aber die Einstellung soll_kg_pro_kiste. Stellt der Betriebsleiter 9 ein,
-- ergab das −15 t „Überschuss" aus 21 739 Kisten, die es nie gab. Jetzt
-- liest beides dieselbe Einstellung.
--
-- Was ausserdem auffiel und mitgeht: v_koeff_ueberfuellung lieferte double
-- precision, und round(sd, 3) scheiterte im SQL-Editor (Regel aus 0014);
-- v_saisonbilanz gab ungerundete numerics mit 190 Nachkommastellen aus.
-- =====================================================================

-- ---------- 3. Palox-Tara als Einstellung ---------------------------------
insert into einstellung (schluessel, wert, bemerkung) values
  ('palox_tara_kg', '45'::jsonb,
   'Leergewicht des Palox (Sammelbehälter für Faules). Die Waage zeigt brutto; '
   'bei der ersten Ablesung einer Station und nach dem Leeren wird die Tara '
   'vom Stand abgezogen. Bei der Differenz zweier Stände kürzt sie sich weg.')
on conflict (schluessel) do nothing;

create or replace function palox_tara_kg()
returns numeric language sql stable as $$
  select coalesce((select (wert #>> '{}')::numeric from public.einstellung
                    where schluessel = 'palox_tara_kg'), 0);
$$;
revoke execute on function palox_tara_kg() from public;
grant execute on function palox_tara_kg() to authenticated;

create or replace view v_palox_stand with (security_invoker = true) as
select s.id, s.auftrag_id, s.ts, s.palox_stand_kg, s.kg,
       lag(s.palox_stand_kg) over w                                as vorher,
       -- Der Stand selbst ist die Menge, wenn davor nichts (Bekanntes) im
       -- Behälter war: erste Ablesung, gemeldetes Leeren, gefallener Stand.
       -- Dann steckt das Leergewicht im Stand und muss heraus.
       greatest(case
         when s.palox_geleert then s.palox_stand_kg - palox_tara_kg()
         when lag(s.palox_stand_kg) over w is null then s.palox_stand_kg - palox_tara_kg()
         when s.palox_stand_kg < lag(s.palox_stand_kg) over w
              then s.palox_stand_kg - palox_tara_kg()
         else s.palox_stand_kg - lag(s.palox_stand_kg) over w
       end, 0)                                                      as differenz,
       (s.palox_geleert
        or (lag(s.palox_stand_kg) over w is not null
            and s.palox_stand_kg < lag(s.palox_stand_kg) over w))   as zwischendurch_geleert,
       a.station
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
 where s.palox_stand_kg is not null and s.gemessen
window w as (partition by a.station order by s.ts, s.id)
 order by a.station, s.ts, s.id;

comment on view v_palox_stand is
  'Die Waagenstände je Station der Reihe nach, mit der daraus abgeleiteten '
  'Menge. Wo der Stand selbst die Menge ist (erste Ablesung, geleert), wird '
  'die Palox-Tara abgezogen — die Waage zeigt brutto.';

-- Die Menge je Arbeit: aus den Ständen abgeleitet, wo es Stände gibt; sonst
-- der direkt erfasste Kilo-Wert (Waage ohne Behälter, oder Erfassung vor 0027).
create or replace view v_schimmel_menge with (security_invoker = true) as
select s.auftrag_id, sum(coalesce(p.differenz, s.kg))::numeric as kg,
       count(*)::int as n_ablesungen
  from schimmel_messung s
  left join v_palox_stand p on p.id = s.id
 where s.gemessen
 group by s.auftrag_id;

comment on view v_schimmel_menge is
  'Faules je Arbeit. Wo der Waagenstand erfasst ist, gilt die daraus '
  'abgeleitete Menge (mit Tara), nicht der damals gespeicherte Kilo-Wert.';

grant select on v_palox_stand, v_schimmel_menge to authenticated;

-- ---------- Die Leser der Schimmelmenge umhängen --------------------------
create or replace view v_schimmel_beobachtung with (security_invoker = true) as
select am.auftrag_id, am.charge_nr, am.sorte, am.schlag, am.weg, am.station,
       am.start_ts, am.lagertage, am.masse_quelle,
       s.kg                                                        as schimmel_kg,
       am.eingang_netto_kg                                         as eingang_kg,
       (am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage))::numeric(12,2)
                                                                   as basis_jetzt_kg,
       (s.kg / nullif(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage), 0))
                                                                   as anteil,
       anteil_plausibel(
         (s.kg / nullif(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage), 0))::numeric
       )                                                           as plausibel
  from v_auftrag_masse am
  join v_schimmel_menge s on s.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
 where am.eingang_netto_kg is not null
   and am.lagertage is not null;

create or replace view v_ausschuss_beobachtung with (security_invoker = true) as
select 'maschine'::verarbeitungsweg as weg, lm.charge_nr, lm.sorte, lm.auftrag_id,
       lm.masse_kg                                  as basis_kg,
       lm.masse_klein_kg                            as klein_kg,
       lm.masse_nebenkanal_kg                       as gross_kg,
       true                                         as plausibel
  from v_sortier_lauf_masse lm
 where lm.masse_kg > 0
union all
select 'hand'::verarbeitungsweg, am.charge_nr, am.sorte, am.auftrag_id,
       n.basis, h.klein_kg, h.gross_kg,
       anteil_plausibel((h.klein_kg  / nullif(n.basis, 0))::numeric)
         and anteil_plausibel((coalesce(h.gross_kg, 0) / nullif(n.basis, 0))::numeric)
  from v_auftrag_masse am
  join (select auftrag_id,
               sum(kg) filter (where art = 'zu_klein')::numeric as klein_kg,
               sum(kg) filter (where art = 'zu_gross')::numeric as gross_kg
          from ausschuss_messung where gemessen group by auftrag_id) h
       on h.auftrag_id = am.auftrag_id
  left join v_schimmel_menge sm on sm.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
  cross join lateral (
        select greatest(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage)
                        - coalesce(sm.kg, 0), 0)::numeric(12,2) as basis
       ) n
 where am.weg = 'hand' and am.eingang_netto_kg is not null and am.lagertage is not null;

create or replace view v_schimmel_punkte with (security_invoker = true) as
with sortier_lauf_anteil as materialized (
  select b.charge_nr, b.start_ts, b.schimmel_kg, b.basis_jetzt_kg
    from v_schimmel_beobachtung b
   where b.station = 'sortieren' and b.plausibel and b.anteil is not null
)
select b.charge_nr, b.sorte, b.schlag, b.lagertage, b.schimmel_kg,
       b.basis_jetzt_kg, b.anteil, b.plausibel,
       'verarbeitung'::text as quelle, b.auftrag_id
  from v_schimmel_beobachtung b
 where b.station in ('sortieren', 'waschen_sortieren')
union all
select a.charge_nr, a.sorte, a.schlag, a.lagertage,
       s.kg                                                      as schimmel_kg,
       (a.eingang_netto_kg + s.kg)                               as basis_jetzt_kg,
       k.f2                                                      as anteil,
       anteil_plausibel(k.f2)                                    as plausibel,
       'verarbeitung', a.auftrag_id
  from v_auftrag_masse a
  join v_schimmel_menge s on s.auftrag_id = a.auftrag_id
  left join lateral (
    select sum(sl.schimmel_kg) / nullif(sum(sl.basis_jetzt_kg), 0) as f1
      from sortier_lauf_anteil sl
     where sl.charge_nr = a.charge_nr and sl.start_ts <= a.start_ts
  ) sa on true
  cross join lateral (
    select s.kg / nullif(a.eingang_netto_kg + s.kg, 0)            as g
  ) x
  cross join lateral (
    select 1 - (1 - least(greatest(coalesce(sa.f1, 0), 0), 0.99))
             * (1 - least(greatest(coalesce(x.g, 0), 0), 0.99))   as f2
  ) k
 where a.station = 'waschen' and a.lagertage is not null
   and a.eingang_netto_kg is not null and a.eingang_netto_kg > 0
union all
select w.charge_nr, w.sorte, w.schlag, w.lagertage,
       v.faul_kg, w.netto_jetzt_kg,
       v.faul_kg / nullif(w.netto_jetzt_kg, 0),
       anteil_plausibel(v.faul_kg / nullif(w.netto_jetzt_kg, 0)),
       'lager', null::bigint
  from v_verdunstung_messung w
  join verdunstung_wiegung v on v.id = w.id
 where v.faul_kg is not null and v.gemessen
   and w.netto_jetzt_kg > 0 and w.lagertage > 0;

-- ---------- 1. Ein Koeffizient ohne Messung ist NULL, nicht 0 --------------
create or replace view v_koeff_verdunstung with (security_invoker = true) as
select sk.sorte,
       k.mittel::numeric                                               as mittel,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                         as unten,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else k.mittel + k.t * sqrt(k.varianz)
        end)::double precision                                         as oben,
       coalesce(k.n, 0)                                                as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Wiegung vorhanden'
            when k.b >= 0.67        then 'Wiegungen dieser Sorte'
            when k.b >= 0.33        then 'Wiegungen dieser Sorte, zum Gesamtwert gezogen'
            else 'Wiegungen aller Sorten (zu wenige eigene Chargen)' end as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_verdunstung_geschaetzt g
     where g.art = 'verdunstung' and g.sorte is not distinct from sk.sorte
  ) k on true;

create or replace view v_koeff_ausschuss with (security_invoker = true) as
select sk.sorte,
       k.mittel::numeric                                                    as mittel,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                              as unten,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else least(k.mittel + k.t * sqrt(k.varianz), 1)
        end)::double precision                                              as oben,
       coalesce(k.n, 0)                                                     as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Messung vorhanden'
            when k.b >= 0.67     then 'Sortierläufe/Handmessungen dieser Sorte'
            when k.b >= 0.33     then 'eigene Messungen, zum Gesamtwert gezogen'
            else 'alle Sorten (zu wenige eigene Chargen)' end               as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'ausschuss' and g.sorte is not distinct from sk.sorte
  ) k on true;

create or replace view v_koeff_nebenkanal with (security_invoker = true) as
select sk.sorte,
       k.mittel::numeric                                                    as mittel,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                              as unten,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else least(k.mittel + k.t * sqrt(k.varianz), 1)
        end)::double precision                                              as oben,
       coalesce(k.n, 0)                                                     as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Messung vorhanden'
            when k.b >= 0.67     then 'Sortierläufe/Handmessungen dieser Sorte'
            when k.b >= 0.33     then 'eigene Messungen, zum Gesamtwert gezogen'
            else 'alle Sorten (zu wenige eigene Chargen)' end               as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'nebenkanal' and g.sorte is not distinct from sk.sorte
  ) k on true;

-- Ausgabespalten numeric, damit round() im SQL-Editor funktioniert (0014).
-- Den Typ einer Ansichtsspalte ändert kein "create or replace" — sie muss weg,
-- samt v_marge_buch, die daran hängt und unten ohnehin neu entsteht.
drop view if exists v_koeff_ueberfuellung cascade;
create view v_koeff_ueberfuellung with (security_invoker = true) as
with roh as (
  select m.wert, m.n_kisten, (m.wert / nullif(m.n_kisten, 0))::numeric as je_kiste
    from marge_messung m
    join auftrag a on a.id = m.auftrag_id
   where m.art = 'ueberfuellung' and m.gemessen and m.n_kisten > 0
     and a.abgebrochen_ts is null
  union all
  select k.ueberfuellung_kg, k.kisten, k.ueberfuellung_je_kiste
    from v_ausgang_kennzahl k
), s as (
  select count(*)::int as n,
         sum(wert) / nullif(sum(n_kisten), 0) as kg_pro_kiste,
         stddev_samp(je_kiste)                as sd
    from roh
)
select n, kg_pro_kiste::numeric(10,3) as kg_pro_kiste, sd::numeric(10,3) as sd,
       (case when sd is null or n < 2 then kg_pro_kiste
             else greatest(kg_pro_kiste - 1.96 * sd / sqrt(n), 0) end)::numeric(10,3) as unten,
       (case when sd is null or n < 2 then kg_pro_kiste
             else kg_pro_kiste + 1.96 * sd / sqrt(n) end)::numeric(10,3)              as oben
  from s;

-- ---------- 4. Das Alter der noch liegenden Paletten ----------------------
create or replace view v_hochrechnung_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung
                    where schluessel = 'saison_ende'), current_date) as bis
), je_station as (
  select charge_nr,
         sum(eingang_netto_kg) filter (where station = 'sortieren')          as sortiert_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen')            as gewaschen_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren')  as hand_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren'
                                         and weg = 'hand')                   as kg_hand,
         sum(eingang_netto_kg * lagertage) filter (
             where station in ('waschen', 'waschen_sortieren') and lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (
               where station in ('waschen', 'waschen_sortieren') and lagertage is not null), 0)
                                                                             as alter_ende,
         sum(eingang_netto_kg * lagertage) filter (where lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (where lagertage is not null), 0)
                                                                             as alter_irgendwas,
         sum(eingang_netto_kg * lagertage) filter (
             where station in ('sortieren', 'waschen_sortieren') and lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (
               where station in ('sortieren', 'waschen_sortieren') and lagertage is not null), 0)
                                                                             as alter_band,
         sum(eingang_netto_kg) filter (where station in ('sortieren', 'waschen_sortieren'))
                                                                             as am_band_kg
    from v_auftrag_masse
   where eingang_netto_kg is not null
   group by charge_nr
), anteil as (
  select s.*,
         least(coalesce(s.gewaschen_kg, 0) / nullif(s.sortiert_kg, 0), 1)     as anteil_gewaschen
    from je_station s
), gezaehlt as (
  -- Welche Paletten haben das Lager verlassen? Je Charge und Eingangsdatum,
  -- soweit die Zählung ein Datum trägt (vom Zettel, von der Wägung oder von
  -- der Palette selbst).
  select a.charge_nr,
         coalesce(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum) as eingangsdatum,
         count(*)::numeric                                             as n
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join palette p on p.id = ap.palette_id
    left join verdunstung_wiegung w on w.id = ap.wiegung_id
   where a.abgebrochen_ts is null
     and a.station in ('sortieren', 'waschen_sortieren')
   group by a.charge_nr, coalesce(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum)
), je_datum as (
  select p.charge_nr, p.eingangsdatum, count(*)::numeric as n, avg(p.netto_kg) as netto
    from v_palette p group by p.charge_nr, p.eingangsdatum
), charge_netto as (
  select charge_nr, avg(netto_kg) as netto from v_palette group by charge_nr
), rest_alter as (
  -- Das Eingangsdatum der *übrigen* Paletten, massegewichtet. Zählungen ohne
  -- Datum lassen sich keinem Tag abziehen; trägt gar keine ein Datum, bleibt
  -- es beim Chargenmittel.
  select d.charge_nr,
         sum(greatest(d.n - coalesce(g.n, 0), 0) * coalesce(d.netto, cn.netto, 1)
             * (d.eingangsdatum - date '2000-01-01'))
           / nullif(sum(greatest(d.n - coalesce(g.n, 0), 0) * coalesce(d.netto, cn.netto, 1)), 0)
                                                     as tage_seit_epoche,
         coalesce(sum(g.n) filter (where g.eingangsdatum is not null), 0) as n_gezaehlt_mit_datum
    from je_datum d
    join charge_netto cn on cn.charge_nr = d.charge_nr
    left join gezaehlt g on g.charge_nr = d.charge_nr and g.eingangsdatum = d.eingangsdatum
   group by d.charge_nr
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       (coalesce(a.hand_kg, 0)
        + coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0))       as ausgelagert_kg,
       coalesce(a.alter_ende, a.alter_irgendwas)                              as alter_ausgelagert,
       greatest(r.eingang_netto_kg
                - coalesce(a.hand_kg, 0)
                - coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0), 0)
                                                                              as lager_kg,
       -- Alter des Bestands bis zum Stichtag: aus den Paletten, die noch da
       -- sind — nicht aus allen, die je kamen.
       (s.bis - x.rest_datum)::numeric                                        as alter_lager,
       (current_date - x.rest_datum)::numeric                                 as alter_lager_heute,
       coalesce(a.kg_hand / nullif(coalesce(a.hand_kg, 0)
                                   + coalesce(a.sortiert_kg, 0), 0), 0)       as weg2_anteil,
       s.bis                                                                  as stichtag,
       r.n_paletten_mit_netto,
       greatest(coalesce(a.hand_kg, 0) + coalesce(a.sortiert_kg, 0)
                - r.eingang_netto_kg, 0)                                      as ueberzaehlung_kg,
       coalesce(a.sortiert_kg, 0)                                             as sortiert_kg,
       coalesce(a.gewaschen_kg, 0)                                            as gewaschen_kg,
       (coalesce(a.sortiert_kg, 0) * (1 - coalesce(a.anteil_gewaschen, 0)))    as wartet_kg,
       coalesce(a.anteil_gewaschen, 0)                                        as anteil_gewaschen,
       a.alter_band,
       coalesce(a.am_band_kg, 0)                                              as am_band_kg,
       x.rest_datum                                                           as eingangsdatum_rest,
       (ra.n_gezaehlt_mit_datum > 0 and ra.tage_seit_epoche is not null)      as rest_alter_aus_zaehlung
  from v_charge_rueckgrat r
  cross join stichtag s
  left join anteil a on a.charge_nr = r.charge_nr
  left join rest_alter ra on ra.charge_nr = r.charge_nr
  cross join lateral (
    select case when ra.n_gezaehlt_mit_datum > 0 and ra.tage_seit_epoche is not null
                then date '2000-01-01' + round(ra.tage_seit_epoche)::int
                else r.eingangsdatum_mittel end as rest_datum
  ) x
 where r.eingang_netto_kg is not null;

comment on view v_hochrechnung_basis is
  'ausgelagert_kg ist die Masse, die den letzten Verarbeitungsschritt hinter '
  'sich hat — auf Weg 1 also erst nach dem Waschen. alter_lager läuft ab dem '
  'Eingangsdatum der noch liegenden Paletten (eingangsdatum_rest), nicht ab '
  'dem Mittel der ganzen Charge. ueberzaehlung_kg > 0 heisst: mehr ausgelagert '
  'als je eingelagert, also Paletten doppelt gezählt.';

-- ---------- Die Kaskade: Ströme ohne Koeffizient bleiben NULL --------------
-- Der cascade nimmt mit, was direkt an mv_kaskade hängt. v_verlust_ranking
-- liest über eine SQL-Funktion und ist damit für Postgres keine Abhängigkeit
-- — sie bleibt stehen und muss ausdrücklich weg, samt ihren Lesern.
drop materialized view if exists mv_kaskade cascade;
drop view if exists v_saisonbilanz;
drop view if exists v_marge_buch;
drop view if exists v_massenbilanz;
drop view if exists v_verlust_ranking;

create materialized view mv_kaskade as
with modell as materialized (
  select * from v_schimmel_modell
),
kurve as materialized (
  select von, anteil_mono, n from v_schimmel_kurve where n > 0
),
koeff as (
  select b.*,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05) as r,
         (kv.mittel is not null)                          as r_bekannt,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(coalesce(ka.mittel, 0), 0), 1)    as a_klein,
         (ka.mittel is not null)                          as a_klein_bekannt,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(coalesce(kn.mittel, 0), 0), 1)    as a_gross,
         (kn.mittel is not null)                          as a_gross_bekannt,
         kn.n as gross_n, kn.basis as gross_basis
    from v_hochrechnung_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
),
koeff_norm as (
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  select k.*, t.portion, t.m0, t.alter_tage,
         ln(greatest(t.alter_tage, 1)) - coalesce(m.x_mittel, 0)        as u,
         case when m.brauchbar then
           m.ln_lambda_korrigiert + m.k * ln(greatest(t.alter_tage, 1))
         end                                                            as eta,
         m.brauchbar                                                    as modell_gilt,
         (m.brauchbar and t.alter_tage > m.t_max)                       as f_extrapoliert,
         case when m.brauchbar then m.c_chargen else s.n end            as f_n,
         s.anteil_mono                                                  as f_treppe,
         -- Bekannt heisst: es gibt überhaupt eine Schimmelmessung. Dann ist
         -- eine Null für Lagerdauern unterhalb der jüngsten Messung ein
         -- Schluss, keine Lücke.
         (m.brauchbar or (select count(*) from kurve) > 0)              as f_bekannt
    from koeff_norm k
    cross join modell m
    cross join lateral (values
        ('ausgelagert', k.ausgelagert_kg, coalesce(k.alter_ausgelagert, 0)),
        ('lager',       k.lager_kg,       greatest(k.alter_lager, 0))
      ) as t(portion, m0, alter_tage)
    left join lateral (
        select c.anteil_mono, c.n from kurve c
         where c.von <= t.alter_tage order by c.von desc limit 1
       ) s on true
   where t.m0 > 0
),
mit_f as (
  select t.*,
         case when t.modell_gilt
              then least(greatest(1 - exp(-exp(least(greatest(t.eta, -40), 3))), 0), 1)
              else least(greatest(coalesce(t.f_treppe, 0), 0), 1) end   as f
    from teile t
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))                          as m1,
         (-t.m0 * t.alter_tage * power(1 - t.r, greatest(t.alter_tage - 1, 0))) as d_m1_r,
         case when t.modell_gilt
              then (1 - t.f) * exp(least(greatest(t.eta, -40), 3))
              else 0 end                                                as d_f_eta
    from mit_f t
)
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage, k.eingang_kg,
       k.m0, k.m1, (k.m1 * (1 - k.f)) as m2,
       k.r, k.f, k.a_klein_n, k.a_gross_n,
       k.u, k.d_m1_r, k.d_f_eta, k.modell_gilt, k.f_extrapoliert,
       k.r_n, k.r_basis, k.klein_n, k.klein_basis, k.gross_n, k.gross_basis, k.f_n,
       k.r_bekannt, k.f_bekannt, k.a_klein_bekannt, k.a_gross_bekannt,
       (k.m0 - k.m1)                                          as verdunstung_kg,
       (k.m1 * k.f)                                           as schimmel_kg,
       (k.m1 * (1 - k.f) * k.a_klein_n)                       as klein_kg,
       (k.m1 * (1 - k.f) * k.a_gross_n)                       as nebenkanal_kg,
       (k.m1 * (1 - k.f) * (1 - k.a_klein_n - k.a_gross_n))   as verkaufsfaehig_kg
  from kaskade k;

create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, portion);
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);

create or replace view v_kaskade with (security_invoker = true) as
select * from mv_kaskade;

create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg, k.f_extrapoliert, k.u,
       s.strom, s.buch,
       -- Ein Strom ohne Koeffizient ist unbekannt — nicht 0. Die Masse läuft
       -- in der Kaskade ungemindert weiter; was das bedeutet, steht in
       -- koeff_basis.
       (case when s.bekannt then s.kg end)::numeric(14,2)  as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       (case when s.bekannt then s.koeffizient end)::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel,
       s.d_r                        as d_r,
       s.d_f * k.d_f_eta            as d_eta,
       s.d_a                        as d_a,
       s.koeff_art                  as koeff_art,
       s.bekannt                    as koeff_bekannt
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung', 'verlust', k.m0 - k.m1, k.m0, k.r, k.r_n, k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen',
     -k.d_m1_r, 0::numeric, 0::numeric, null::text, k.r_bekannt),
    ('Schimmel/Fäulnis', 'verlust', k.m1 * k.f, k.m1, k.f, k.f_n,
     'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer',
     k.d_m1_r * k.f, k.m1, 0::numeric, null::text, k.f_bekannt),
    ('Ausschuss zu klein', 'verlust', k.m1 * (1 - k.f) * k.a_klein_n, k.m2,
     k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze',
     k.d_m1_r * (1 - k.f) * k.a_klein_n, -k.m1 * k.a_klein_n, k.m2, 'ausschuss', k.a_klein_bekannt),
    ('Nebenkanal zu gross', 'marge', k.m1 * (1 - k.f) * k.a_gross_n, k.m2,
     k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal',
     k.d_m1_r * (1 - k.f) * k.a_gross_n, -k.m1 * k.a_gross_n, k.m2, 'nebenkanal', k.a_gross_bekannt),
    ('Verkaufsfähig', 'bilanz', k.verkaufsfaehig_kg, k.m2, null::numeric, null::int,
     null::text, 'Rest der Kaskade', 0::numeric, 0::numeric, 0::numeric, null::text, true)
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel,
         d_r, d_f, d_a, koeff_art, bekannt);

comment on view v_hochrechnung is
  'Ein Strom je Charge und Portion. kg ist NULL, wenn der Koeffizient dahinter '
  'nie gemessen wurde — koeff_bekannt sagt es. Die Kaskade rechnet dann so, '
  'als würde nichts abgezogen; koeff_basis nennt den Grund.';

create or replace function verlust_ranking(
  p_sorte          text    default null,
  p_schlag         text    default null,
  p_min_lagertage  numeric default null)
returns table (
  strom text, buch text, kg numeric, kg_unten numeric, kg_oben numeric,
  kg_beobachtet numeric, kg_projiziert numeric, kg_extrapoliert numeric,
  koeff_n_min int, streuung_kg numeric, df int)
language sql stable as $$
with zeilen as materialized (
  select * from v_hochrechnung
   where buch in ('verlust', 'marge')
     and (p_sorte is null or sorte = p_sorte)
     and (p_schlag is null or schlag = p_schlag)
     and (p_min_lagertage is null or alter_tage >= p_min_lagertage)
),
je_sorte as (
  select z.strom, z.buch, z.sorte, max(z.koeff_art) as koeff_art,
         sum(z.d_r) as g_r, sum(z.d_a) as g_a
    from zeilen z group by z.strom, z.buch, z.sorte
),
je_strom_modell as (
  select z.strom, z.buch,
         sum(z.d_eta)       as g_achse,
         sum(z.d_eta * z.u) as g_steigung
    from zeilen z group by z.strom, z.buch
),
varianz_r as (
  select s.strom, s.buch,
         sum(power(s.g_r, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_r * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = 'verdunstung' and u.sorte is not distinct from s.sorte
   group by s.strom, s.buch
),
varianz_a as (
  select s.strom, s.buch,
         sum(power(s.g_a, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_a * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = s.koeff_art and u.sorte is not distinct from s.sorte
   where s.koeff_art is not null
   group by s.strom, s.buch
),
varianz_f as (
  select m.strom, m.buch,
         power(m.g_achse, 2) * coalesce(sm.var_achse, 0)
         + 2 * m.g_achse * m.g_steigung * coalesce(sm.kov_achse_k, 0)
         + power(m.g_steigung, 2) * coalesce(sm.var_k, 0)       as varianz,
         coalesce(sm.c_chargen - 1, 1)                          as df
    from je_strom_modell m cross join v_schimmel_modell sm
),
summe as (
  select z.strom, z.buch,
         -- sum() überspringt NULL: ein unbekannter Strom hat lauter NULL-Zeilen
         -- und bleibt damit von selbst NULL. bool_and hält es fest.
         sum(z.kg)                                                as kg,
         bool_and(z.koeff_bekannt)                                as bekannt,
         sum(z.kg) filter (where z.portion = 'ausgelagert')       as kg_beobachtet,
         sum(z.kg) filter (where z.portion = 'lager')             as kg_projiziert,
         sum(z.kg) filter (where z.f_extrapoliert)                as kg_extrapoliert,
         min(z.koeff_n)                                           as koeff_n_min
    from zeilen z group by z.strom, z.buch
)
select s.strom, s.buch,
       case when s.bekannt then s.kg end,
       -- greatest() ignoriert NULL und machte aus „unbekannt" eine 0.
       case when s.bekannt then greatest(s.kg - g.t * g.streuung - zu.zuschlag, 0)::numeric(14,2) end,
       case when s.bekannt then (s.kg + g.t * g.streuung + zu.zuschlag)::numeric(14,2) end,
       case when s.bekannt then s.kg_beobachtet end,
       case when s.bekannt then s.kg_projiziert end,
       case when s.bekannt then s.kg_extrapoliert end,
       s.koeff_n_min,
       case when s.bekannt then g.streuung::numeric(14,2) end, g.df
  from summe s
  left join varianz_r vr on vr.strom = s.strom and vr.buch = s.buch
  left join varianz_a va on va.strom = s.strom and va.buch = s.buch
  left join varianz_f vf on vf.strom = s.strom and vf.buch = s.buch
  cross join lateral (select coalesce(sm2.selektions_versatz, 0) as versatz
                       from v_schimmel_modell sm2) sel
  cross join lateral (
    select sqrt(greatest(coalesce(vr.varianz, 0) + coalesce(va.varianz, 0)
                         + coalesce(vf.varianz, 0), 0))       as streuung,
           least(coalesce(vr.df, 999), coalesce(va.df, 999),
                 coalesce(vf.df, 999))                        as df
  ) g0
  cross join lateral (select g0.streuung, g0.df, t_quantil_95(g0.df) as t) g
  cross join lateral (
    select case when s.strom = 'Schimmel/Fäulnis'
                then coalesce(s.kg_projiziert, 0) * abs(exp(sel.versatz) - 1)
                else 0 end                                    as zuschlag) zu
 order by s.kg desc nulls last;
$$;

create view v_verlust_ranking with (security_invoker = true) as
select * from verlust_ranking();

comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall. kg ist NULL, '
  'wenn der Koeffizient hinter dem Strom nie gemessen wurde — dann ist der '
  'Strom unbekannt, nicht null.';

-- ---------- 6. Kistenzahl aus der Einstellung, nicht aus 8.0 ---------------
create view v_marge_buch with (security_invoker = true) as
with soll as (
  select coalesce((select (wert #>> '{}')::numeric from einstellung
                    where schluessel = 'soll_kg_pro_kiste'), 8) as kg
), kisten as materialized (
  select sum(k.verkaufsfaehig_kg * b.weg2_anteil) / s.kg as anzahl
    from v_kaskade k join v_hochrechnung_basis b on b.charge_nr = k.charge_nr
    cross join soll s group by s.kg
)
select r.strom as posten, r.kg, r.kg_unten, r.kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from v_verlust_ranking r where r.buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       (u.unten * v.anzahl)::numeric(14,2),
       (u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten '
              || 'à %s kg (Weg 2 — Annahme: alle Weg-2-Ware geht in solche Kisten)',
              u.n, round(u.kg_pro_kiste, 3), round(v.anzahl), s.kg)
  from v_koeff_ueberfuellung u cross join kisten v cross join soll s
 where u.n > 0;

-- ---------- 5. Restbestand = noch im Haus, nach Verdunstung und Verderb ----
create view v_massenbilanz with (security_invoker = true) as
with csv_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (
             where exists (select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
           / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
    from v_auftrag_masse am
   where am.station in ('sortieren', 'waschen_sortieren')
     and am.eingang_netto_kg is not null
   group by am.charge_nr
), gemessen as materialized (
  select charge_nr, sum(masse_kg) as gemessen_kg from v_sortier_lauf_masse group by charge_nr
), rest as materialized (
  -- m2, nicht verkaufsfähig: zu klein und zu gross liegen noch im Lager, sie
  -- werden erst beim Verarbeiten aussortiert.
  select charge_nr, sum(m2) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade group by charge_nr
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       (b.am_band_kg
        * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05), coalesce(b.alter_band, 0))
        * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
        * q.anteil_mit_csv)::numeric(14,2)                   as modell_am_band_kg,
       c.gemessen_kg                                         as csv_gemessen_kg,
       (c.gemessen_kg
        - b.am_band_kg
          * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05), coalesce(b.alter_band, 0))
          * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
          * q.anteil_mit_csv)::numeric(14,2)                 as abweichung_kg,
       case when b.am_band_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg
                   - b.am_band_kg
                     * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05),
                             coalesce(b.alter_band, 0))
                     * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
                     * q.anteil_mit_csv)
                  / (b.am_band_kg
                     * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05),
                             coalesce(b.alter_band, 0))
                     * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
                     * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       r.restbestand_kg::numeric(14,2)                       as restbestand_kg,
       b.alter_band
  from v_hochrechnung_basis b
  left join csv_anteil q on q.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr
  left join rest r       on r.charge_nr = b.charge_nr
  left join v_koeff_verdunstung kv on kv.sorte = b.sorte;

comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. '
  'restbestand_kg ist die Masse, die nach Verdunstung und Verderb noch im '
  'Haus liegt — ohne die Aufteilung in zu klein/zu gross, die erst beim '
  'Verarbeiten stattfindet.';

create view v_saisonbilanz with (security_invoker = true) as
with eingang as (
  select sum(eingang_kg)          as kg,
         sum(lager_kg)            as im_lager_kg,
         sum(wartet_kg)           as wartet_kg
    from v_hochrechnung_basis
), verlust as (
  select sum(kg)                  as kg,
         sum(kg_unten)            as kg_unten,
         sum(kg_oben)             as kg_oben,
         bool_and(kg is not null) as bekannt
    from v_verlust_ranking where buch = 'verlust'
), rest as (
  select sum(m2)                  as kg
    from v_kaskade where portion = 'lager'
), ausgang as (
  select coalesce(sum(masse_kg), 0)                                as kg,
         coalesce(sum(masse_kg) filter (where buch = 'verkauf'), 0) as verkauf_kg,
         coalesce(sum(masse_kg) filter (where buch = 'marge'), 0)   as marge_kg,
         coalesce(sum(masse_kg) filter (where buch = 'verlust'), 0) as entsorgt_kg,
         coalesce(sum(masse_fehler_kg), 0)                          as fehler_kg,
         count(*)::int                                             as n_lieferungen
    from v_lieferung_masse
)
select e.kg::numeric(14,2)                                 as eingang_kg,
       v.kg::numeric(14,2)                                 as verlust_modell_kg,
       v.kg_unten::numeric(14,2)                           as verlust_unten_kg,
       v.kg_oben::numeric(14,2)                            as verlust_oben_kg,
       a.kg::numeric(14,2)                                 as ausgang_kg,
       a.verkauf_kg::numeric(14,2) as verkauf_kg, a.marge_kg::numeric(14,2) as marge_kg,
       a.entsorgt_kg::numeric(14,2) as entsorgt_kg,
       a.fehler_kg::numeric(14,2)                          as ausgang_fehler_kg,
       a.n_lieferungen,
       r.kg::numeric(14,2)                                 as restbestand_modell_kg,
       e.im_lager_kg::numeric(14,2) as im_lager_kg, e.wartet_kg::numeric(14,2) as wartet_kg,
       (e.kg - v.kg - a.kg - r.kg)::numeric(14,2)          as luecke_kg,
       (case when e.kg > 0 then (e.kg - v.kg - a.kg - r.kg) / e.kg end)::numeric(10,4)
                                                           as luecke_anteil,
       (case when e.kg > 0 then a.kg / e.kg end)::numeric(10,4) as ausgang_deckung,
       case
         when not coalesce(v.bekannt, false)
           then 'Ein Verluststrom ist noch nicht gemessen — die Bilanz kann erst '
                || 'schliessen, wenn jeder Koeffizient mindestens eine Messung hat.'
         when a.n_lieferungen = 0
           then 'Kein Warenausgang erfasst — die Bilanz kann nichts prüfen. '
                || 'Der Restbestand ist eine Hochrechnung, kein Inventar.'
         when a.kg / nullif(e.kg, 0) < 0.2
           then 'Erst ein Bruchteil des Ausgangs ist erfasst — die Lücke sagt '
                || 'bislang mehr über die Erfassung als über das Modell.'
         when abs(e.kg - v.kg - a.kg - r.kg) / nullif(e.kg, 0) < 0.05
           then 'Die Bilanz geht auf: Eingang, Verlust, Ausgang und Bestand '
                || 'passen auf wenige Prozent zusammen.'
         when (e.kg - v.kg - a.kg - r.kg) > 0
           then 'Es fehlt Masse: mehr eingelagert, als sich durch Verlust, '
                || 'Ausgang und Bestand erklären lässt. Entweder ist ein '
                || 'Abgang nicht erfasst, oder ein Verlust wird unterschätzt.'
         else 'Es ist zu viel Masse da: mehr ausgeliefert und übrig, als je '
              || 'eingelagert wurde. Meist doppelt gezählte Paletten oder '
              || 'fehlende Tara im Wareneingang.'
       end                                                 as befund
  from eingang e cross join verlust v cross join rest r cross join ausgang a;

comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand. '
  'Der Restbestand ist die Masse, die nach Verdunstung und Verderb noch im '
  'Haus liegt. luecke_kg misst, was das Modell nicht sieht — nur soweit der '
  'Ausgang erfasst ist (ausgang_deckung).';

-- ---------- 2. Was erfasst, aber nirgends angekommen ist ------------------
create or replace view v_plausibilitaet with (security_invoker = true) as
select 'Schimmel'::text as art, b.auftrag_id, b.charge_nr, b.sorte, b.start_ts,
       format('%s kg Schimmel auf %s kg Ware — das wären %s %%',
              round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100)) as befund,
       'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text as rat
  from v_schimmel_beobachtung b
 where b.anteil is not null and not b.plausibel
union all
select 'Ausschuss', a.auftrag_id, a.charge_nr, a.sorte, null::timestamptz,
       format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse',
              round(coalesce(a.klein_kg, 0)), round(coalesce(a.gross_kg, 0)), round(a.basis_kg)),
       'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'
  from v_ausschuss_beobachtung a
 where a.weg = 'hand' and not a.plausibel
union all
select 'Nicht ausgewertet', m.auftrag_id, a.charge_nr, c.sorte, m.ts,
       format('%s %s als marge_messung(nebenkanal) erfasst', m.wert, m.einheit),
       'Nebenkanal-Mengen gehören auf Weg 2 unter „zu gross"; auf Weg 1 kommen sie aus der CSV.'
  from marge_messung m
  join auftrag a on a.id = m.auftrag_id
  join charge c on c.nr = a.charge_nr
 where m.art = 'nebenkanal'
union all
-- Messungen ohne Nenner: Faules oder Ausschuss erfasst, aber nichts, worauf
-- sich die Menge beziehen liesse. Diese Arbeiten fliessen nirgends ein — und
-- bis hierher hat das niemand erfahren.
select 'Ohne Nenner', a.id, a.charge_nr, c.sorte, a.start_ts,
       format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein',
              concat_ws(' und ',
                case when coalesce(s.kg, 0) > 0 then round(s.kg) || ' kg Faules' end,
                case when coalesce(x.kg, 0) > 0 then round(x.kg) || ' kg zu klein/gross' end),
              case when a.station = 'waschen' then 'keine verarbeitete Menge eingetragen'
                   else 'keine Palette gezählt' end),
       case when a.station = 'waschen'
            then 'Die verarbeitete Menge (kg) am Auftrag nachtragen.'
            else 'Die gezählten Paletten am Auftrag nachtragen.' end
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_schimmel_menge s on s.auftrag_id = a.id
  left join (select auftrag_id, sum(kg)::numeric as kg from ausschuss_messung
              where gemessen group by auftrag_id) x on x.auftrag_id = a.id
  left join mv_auftrag_masse m on m.auftrag_id = a.id
 where a.abgebrochen_ts is null
   and (coalesce(s.kg, 0) > 0 or coalesce(x.kg, 0) > 0)
   and coalesce(m.eingang_netto_kg, 0) <= 0
union all
-- Ein Waagenstand unter dem Leergewicht des Behälters ist unmöglich: Entweder
-- wurde netto abgelesen (dann stimmt die Einstellung nicht) oder vertippt.
select 'Palox', s.auftrag_id, a.charge_nr, c.sorte, s.ts,
       format('Waagenstand %s kg liegt unter dem Leergewicht des Palox (%s kg)',
              s.palox_stand_kg, palox_tara_kg()),
       'Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '
       || 'Sonst ist der Stand vertippt.'
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
  join charge c on c.nr = a.charge_nr
 where s.gemessen and a.abgebrochen_ts is null
   and s.palox_stand_kg is not null and s.palox_stand_kg < palox_tara_kg()
union all
-- Wägungen, die nicht verwertbar sind, ohne dass sichtbar Faules der Grund war.
select 'Wägung', w.auftrag_id, w.charge_nr, w.sorte, w.wiege_ts,
       'Palette gewogen, aber '
       || case when w.netto_damals_kg is null or w.netto_jetzt_kg is null
                 then 'für die Gebindeart fehlt die Tara'
               when w.lagertage <= 0
                 then 'das Wiegedatum liegt nicht nach dem Eingangsdatum'
               when w.netto_damals_kg <= 0 or w.netto_jetzt_kg <= 0
                 then 'das Netto ist null oder negativ'
               else 'sie ist nicht verwertbar' end
       || ' — sie zählt nicht in die Verdunstungsrate',
       case when w.netto_damals_kg is null or w.netto_jetzt_kg is null
              then 'Unter Stammdaten → Gebinde die Tara nachtragen.'
            else 'Eingangsdatum und Gewichte der Wägung prüfen.' end
  from v_verdunstung_messung w
  left join auftrag a on a.id = w.auftrag_id
 where not w.verwendbar and not w.sichtbar_schimmel
   and (a.id is null or a.abgebrochen_ts is null)
   and exists (select 1 from verdunstung_wiegung v where v.id = w.id and v.gemessen);

comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, '
  'die sie gar nicht verwenden kann, weil ihnen der Nenner fehlt. Nicht '
  'ignorieren: fast immer ist etwas nachzutragen oder ein Tippfehler zu '
  'korrigieren.';

grant select on v_kaskade, v_hochrechnung, v_verlust_ranking, v_marge_buch,
               v_massenbilanz, v_saisonbilanz, v_plausibilitaet,
               v_hochrechnung_basis, v_koeff_ueberfuellung to authenticated;
grant execute on function verlust_ranking(text, text, numeric) to authenticated;
