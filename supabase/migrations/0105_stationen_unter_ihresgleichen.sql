-- =====================================================================
-- 0105 — Stationen unter ihresgleichen
--
-- Der Betrieb, 29. September, nachts: „Vergleiche die Arbeitsschritte
-- untereinander, nicht das Datum vom Waschen mit dem vom Waschen + Sortieren.
-- Es geht darum zu erkennen, wie viel die Wasch- und Sortierstation nicht
-- überlebt — klare Werte: bei Waschen + Sortieren gehen so viel Prozent
-- raus, bei nur Waschen so viel. Dazu eine Kennzahl darunter, und der
-- Zuwachs seit Messbeginn, sobald es vier Wochen Messungen gibt."
--
-- Was hier geschieht — ohne das Verderbsmodell anzufassen (das bleibt für
-- die Kaskade stehen, bis die Kennzahlen je Station vier Wochen Daten haben
-- und der Betrieb den Wechsel entscheidet, docs/ENTSCHLACKUNG.md):
--   · Jeder Palox-Punkt sagt, welches Auge ihn gesehen hat (station), und
--     trägt neben dem aufgelaufenen Anteil des Modells seinen eigenen Anteil
--     (anteil_station): beim Waschen der Wasch-Palox allein durch die Masse
--     hinein — nichts vom Sortieren dazugerechnet; plausibel_station urteilt
--     über diesen eigenen Anteil, nicht über den aufgelaufenen.
--   · palox_station_kennzahl(bis): je Station, wie viel im Mittel in den
--     Palox geht (massegewichtet, dazu der Median), seit wann, wie viele
--     Arbeiten und Chargen, und der Zuwachs je Woche seit Messbeginn — als
--     massegewichtete Gerade über den Messtag, aber erst ab vier Wochen und
--     fünf Arbeiten; vorher sagt zuwachs_text, was fehlt.
--   · v_palox_station: dieselbe Kennzahl bis heute — das liest das Dashboard
--     unter dem Diagramm, in dem sich die Punkte je Station umschalten und
--     die Chargen mit Linien verbinden lassen.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Jeder Punkt kennt sein Auge
-- ---------------------------------------------------------------------
create or replace view v_schimmel_punkte with (security_invoker = true) as
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
    b.plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    b.auftrag_id,
    betriebstag(b.start_ts) AS messtag,
    b.station::text AS station,
    b.anteil AS anteil_station,
    b.plausibel AS plausibel_station
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
    anteil_plausibel(k.f2) AND a.lagertage >= 0::numeric AS plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    a.auftrag_id,
    betriebstag(a.start_ts) AS messtag,
    'waschen'::text AS station,
    x.g AS anteil_station,
    -- plausibel nach dem eigenen Anteil: 45 % am Band und 10 % beim Waschen
    -- machen den Wasch-Punkt nicht unplausibel (Fehlersuche Runde AI).
    anteil_plausibel(x.g) AND a.lagertage >= 0::numeric AS plausibel_station
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
    anteil_plausibel(v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric)) AS plausibel,
    'lager'::text AS quelle,
    NULL::bigint AS auftrag_id,
    betriebstag(w.wiege_ts) AS messtag,
    'lager'::text AS station,
    v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric) AS anteil_station,
    anteil_plausibel(v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric)) AS plausibel_station
   FROM v_verdunstung_messung w
     JOIN verdunstung_wiegung v ON v.id = w.id
  WHERE v.faul_kg IS NOT NULL AND v.gemessen AND w.netto_jetzt_kg > 0::numeric AND w.lagertage > 0;

-- Die gespeicherte Fassung für die App neu, damit sie die zwei Spalten trägt
-- (wie 0079: leer angelegt, gefüllt vom Zeitplan oder von „Neu rechnen").
-- verdichter: baut erg_punkte
do $$
begin
  execute 'drop materialized view if exists erg_punkte cascade';
  execute 'create materialized view erg_punkte as select * from v_schimmel_punkte with no data';
  execute 'grant select on erg_punkte to authenticated';
  execute $q$create index if not exists erg_punkte_charge      on erg_punkte (charge_nr)$q$;
  execute $q$create index if not exists erg_punkte_charge on erg_punkte (charge_nr)$q$;
  execute format('comment on materialized view erg_punkte is %L',
                 'v_schimmel_punkte mit dem Messtag (0079) und seit 0105 mit Station und eigenem Anteil, '
                 'gespeichert für die App. Erneuert mit auswertung_schritt().');
end $$;
-- Dieselbe Beschreibung noch einmal als eigene Anweisung: Der Verdichter
-- ordnet Beschreibungen hinter die Bauer ein, und die älteren (0068, 0079)
-- stünden sonst in setup.sql nach diesem Block — mit dem alten Text.
comment on materialized view erg_punkte is
  'v_schimmel_punkte mit dem Messtag (0079) und seit 0105 mit Station und eigenem Anteil, '
  'gespeichert für die App. Erneuert mit auswertung_schritt().';


-- ---------------------------------------------------------------------
-- 2. Die Kennzahl je Station
-- ---------------------------------------------------------------------
create or replace function palox_trend_mindest_tage() returns int
language sql immutable set search_path = public as $$ select 28 $$;
revoke all on function palox_trend_mindest_tage() from public;
grant execute on function palox_trend_mindest_tage() to authenticated;

create or replace function palox_station_kennzahl(p_bis date, p_ab date default null)
returns table (
  station text, n_arbeiten int, n_chargen int, seit date, bis date, tage int,
  anteil_mittel numeric, anteil_median numeric, anteil_4w numeric, n_4w int,
  zuwachs_je_woche numeric, zuwachs_text text)
language plpgsql stable set search_path = public as $$
#variable_conflict use_column
begin
  return query
  with p as (
    select e.station, e.charge_nr, e.auftrag_id, e.messtag, e.basis_jetzt_kg as w, e.anteil_station as y
      from erg_punkte e
     where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
       and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
       and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
       and e.messtag <= p_bis and (p_ab is null or e.messtag >= p_ab)
  ), q as (
    -- t: Tage seit dem ersten Messtag dieser Station — die Achse der Geraden
    select p.*, (p.messtag - min(p.messtag) over (partition by p.station))::numeric as t from p
  ), je as (
    select station,
           count(*)::int as n_arbeiten, count(distinct charge_nr)::int as n_chargen,
           min(messtag) as seit, max(messtag) as bis, (max(messtag) - min(messtag))::int as tage,
           sum(w * y) / nullif(sum(w), 0) as anteil_mittel,
           percentile_cont(0.5) within group (order by y) as anteil_median,
           sum(w * y) filter (where messtag > p_bis - 28) / nullif(sum(w) filter (where messtag > p_bis - 28), 0) as anteil_4w,
           count(*) filter (where messtag > p_bis - 28)::int as n_4w,
           -- massegewichtete Gerade y = a + b · t: b in Anteil je Tag
           (sum(w * t * y) * sum(w) - sum(w * t) * sum(w * y))
           / nullif(sum(w * t * t) * sum(w) - power(sum(w * t), 2), 0) as b_je_tag
      from q
     group by station
  )
  select station, n_arbeiten, n_chargen, seit, bis, tage,
         zahl(anteil_mittel, 5, 1)::numeric(10,5), zahl(anteil_median, 5, 1)::numeric(10,5),
         zahl(anteil_4w, 5, 1)::numeric(10,5), n_4w,
         case when tage >= palox_trend_mindest_tage() and n_arbeiten >= 5
              then zahl(b_je_tag * 7, 5, 1)::numeric(10,5) end as zuwachs_je_woche,
         case when tage >= palox_trend_mindest_tage() and n_arbeiten >= 5 then null
              when n_arbeiten < 5 then format('Zuwachs erst ab fünf Arbeiten (%s bis jetzt)', n_arbeiten)
              else format('Zuwachs erst nach vier Wochen Messungen (seit %s, %s Tage)', to_char(seit, 'DD.MM.'), tage) end as zuwachs_text
    from je
   order by case je.station when 'waschen_sortieren' then 1 when 'waschen' then 2 else 3 end;
end $$;
comment on function palox_station_kennzahl(date, date) is
  'Je Station (0105): wie viel im Mittel in den Palox geht (massegewichtet, Median), seit wann, wie viele Arbeiten und '
  'Chargen, die letzten vier Wochen, und der Zuwachs je Woche seit Messbeginn (massegewichtete Gerade über den Messtag) — '
  'erst ab vier Wochen und fünf Arbeiten, vorher sagt zuwachs_text, was fehlt. Nur Punkte, deren eigener Anteil plausibel '
  'ist; p_ab grenzt das Fenster nach unten ab (Prüfstand).';
revoke all on function palox_station_kennzahl(date, date) from public;
grant execute on function palox_station_kennzahl(date, date) to authenticated;

create or replace view v_palox_station with (security_invoker = true) as
  select * from palox_station_kennzahl(heute());
comment on view v_palox_station is 'Die Kennzahl je Station bis heute (0105) — unter dem Diagramm „Faules im Lager".';
grant select on v_palox_station to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 105 $$;
