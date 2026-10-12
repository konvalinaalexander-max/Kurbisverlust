-- 0111 — Palox: Grundausschuss und Anstieg; jeder Anteil schlicht
--
-- WARUM
--
-- Der Betrieb am 12. Oktober, nach drei Wochen echter Arbeiten:
--
--   „Palox funktioniert anders. Primär ist Palox einfach Aussortieren von
--   Hagelschaden, von falsch geschnittenen Stielen — die Anzahl Mängel, die
--   einfach auftreten. Sagen wir, eine Sorte hat einen grundlegenden
--   Ausschuss von 10 %, und im Dezember sind es vielleicht 15 %. Diesen
--   Anstieg möchte ich erfasst haben. Aber die Mathematik muss wiedergeben,
--   dass es primär ein Aussortieren von nicht verkaufsfähiger Ware ist."
--
-- Und zur Verdunstung: „Überall dort, wo wir Gewicht damals, Gewicht jetzt
-- und die Anzahl Tage dazwischen haben, daraus die Rate rechnen. Die
-- Mathematik simpel halten."
--
-- Bis 0110 nahm die Kaskade für jede Sorte und Station EINEN Palox-Anteil —
-- das Mittel der letzten vier Wochen — gleich für frische wie für zehn
-- Wochen alte Ware; ein Zuwachs stand erst nach vier Wochen Messtagen fest
-- (auf den Betriebsdaten: noch für keine Station). Die Rate je Sorte für
-- Verdunstung, zu klein, zu gross und Fax wurde per empirischem Bayes zum
-- Wert aller Sorten gezogen — eine Sorte mit 34 Wägungen aus zwei Chargen
-- stand trotzdem beim Gesamtwert, und niemand konnte es nachrechnen.
--
-- WAS 0111 TUT
--
-- 1. Jeder Anteil je Sorte ist das massegewichtete Mittel der eigenen
--    Messungen, ab drei (anteil_mindest_messungen); sonst das Mittel aller
--    Sorten, und es heisst so („aller Sorten"). Kein Zug, kein tau².
--    Die Verdunstung kommt wie bisher nur aus Paaren Gewicht damals /
--    Gewicht jetzt / Tage (auf den Betriebsdaten: 84 verwendbare Wägungen,
--    alle beim Waschen + Sortieren).
-- 2. Der Palox-Anteil je Station ist eine Gerade über die Lagerdauer:
--      Anteil(t) = Grundausschuss der Sorte + Anstieg der Station × t / 7
--    Der Anstieg wird innerhalb der Sorten gemessen (jede Sorte um ihre
--    eigene Mitte), damit eine Sorte mit viel Grünem nicht als Anstieg
--    zählt; er gilt ab fünf Arbeiten und drei Wochen Spanne der Lager-
--    dauern innerhalb einer Sorte und ist nie negativ. Der Grundausschuss
--    ist das Mittel der Sorte, um den Anstieg auf null Tage zurückgelegt.
-- 3. Die Kaskade nimmt jeden Stationswert beim Alter seiner Portion —
--    Liegendes beim heutigen Alter, Ausgeliefertes beim Alter am Liefertag;
--    wo die Charge selbst gemessen ist, gilt ihre Messung ohne Anstieg.
--    Prognose und Verlauf schreiben von dort mit dem Anstieg fort.
-- 4. v_prognose trennt zu klein und zu gross; lager_kaliber() zeigt
--    Unterkaliber (zu klein) und Überkaliber (zu gross) neben den Bändern,
--    und die Bänder sind das Verkaufsfähige — dieselbe Zahl wie überall.
--    Was seit der Sortierung unter das kleinste Band geschrumpft ist, zählt
--    im kleinsten Band (geschrumpft_kg sagt, wie viel).
-- 5. v_lauf_vergleich stellt Sortierläufe derselben Charge nebeneinander
--    (AB-113) — Gegenprobe der Verdunstung, nicht Teil der Rate.
--
-- WAS BEWUSST NICHT
--
-- Der Strom bleibt EINER („Schimmel/Fäulnis", angezeigt als „Palox-
-- Ausschuss"); Grundausschuss und Anstieg werden je Station und Sorte
-- gezeigt, nicht als zwei Ströme durch alle Bilanzen getragen (0106: „Der
-- Betrieb liest nicht mehr zwei Ströme, wo er einen Palox sieht"). Die
-- Rate bleibt geometrisch ((1 − r)^Tage): bei 0,3 % je Tag liegt sie nach
-- 60 Tagen 0,6 Punkte neben einer Geraden, und alles Gespeicherte rechnet
-- schon so. Die Läufe derselben Charge gehen nicht in die Rate ein — es sind
-- andere Kürbisse; ob sie dürfen, entscheidet der Betrieb, sobald es Paare
-- gibt. Keine Tabelle, keine Spalte einer Tabelle wird gelöscht.
-- =====================================================================
-- 1. Ein Anteil je Sorte: das Mittel der eigenen Messungen — oder aller
-- =====================================================================
-- Ab wie vielen eigenen Messungen eine Sorte ihren eigenen Wert hat. Drei,
-- wie beim Palox (palox_mindest_arbeiten): zwei Messungen sind ein Paar,
-- drei zeigen, ob eine davon ausreisst.
create or replace function anteil_mindest_messungen() returns int
language sql immutable as $$ select 3 $$;
comment on function anteil_mindest_messungen() is
  'Ab so vielen eigenen Messungen (Wägungen, Sortierläufe, Handmessungen) gilt der Wert der Sorte; darunter der Wert aller Sorten (0111).';
revoke all on function anteil_mindest_messungen() from public;
grant execute on function anteil_mindest_messungen() to authenticated;

-- Die Verdunstung je Sorte. Spalten und Namen wie bisher, damit alles, was
-- darauf rechnet, stehen bleiben kann; nur die Rechnung ist eine andere:
--   n ≥ 3 eigene Wägungen  → b = 1, das massegewichtete Mittel der Sorte
--   sonst                  → b = 0, das Mittel aller Sorten (geliehen)
-- tau2 bleibt leer: es gibt keinen Zug zum Gesamtwert mehr. varianz ist die
-- Unsicherheit des Mittels (Streuung der Messungen / (n − 1)), df = n − 1
-- der Ebene, die gilt.
create or replace view v_koeff_verdunstung_geschaetzt with (security_invoker = true) as
with roh as materialized (
  select art, sorte, charge_nr, anteil, gewicht
    from v_koeff_roh_verdunstung
   where anteil is not null and gewicht > 0
), mitte as (
  select art, sorte,
         count(*)::int                         as n,
         count(distinct charge_nr)::int        as c_chargen,
         sum(gewicht)                          as sw,
         sum(anteil * gewicht) / sum(gewicht)  as mittel
    from roh
   group by grouping sets ((art, sorte), (art))
), ebene as (
  select m.art, m.sorte, m.n, m.c_chargen, m.mittel,
         case when m.n > 1
              then (select sum(r.gewicht * power(r.anteil - m.mittel, 2)) from roh r
                     where r.art = m.art and (m.sorte is null or r.sorte = m.sorte))
                   / m.sw / (m.n - 1) end      as varianz
    from mitte m
), gitter as (
  select a.art, sk.sorte from (select distinct art from roh) a cross join sorte_kaliber sk
  union all
  select a.art, null::text from (select distinct art from roh) a
)
select gi.art, gi.sorte,
       coalesce(v.n, 0)                                        as n,
       coalesce(v.c_chargen, 0)                                as c_chargen,
       v.mittel                                                as mittel_roh,
       v.varianz                                               as varianz_roh,
       g.mittel                                                as mittel_gesamt,
       null::numeric                                           as tau2,
       b.gewicht                                               as b,
       case when b.gewicht = 1 then coalesce(v.mittel, g.mittel) else g.mittel end as mittel,
       case when b.gewicht = 1 then coalesce(v.varianz, 0) else coalesce(g.varianz, 0) end as varianz,
       greatest(case when b.gewicht = 1 then coalesce(v.n, 0) else g.n end - 1, 1) as df,
       g.n                                                     as n_gesamt,
       b.gewicht * coalesce(v.varianz, 0)                      as varianz_eigen,
       1 - b.gewicht                                           as gewicht_gesamt,
       coalesce(g.varianz, 0)                                  as varianz_gesamt
  from gitter gi
  join ebene g on g.art = gi.art and g.sorte is null
  left join ebene v on v.art = gi.art and v.sorte is not distinct from gi.sorte
 cross join lateral (
   select case when gi.sorte is null then 1.0
               when coalesce(v.n, 0) >= anteil_mindest_messungen() then 1.0
               else 0.0 end::numeric as gewicht) b;
comment on view v_koeff_verdunstung_geschaetzt is
  'Die Verdunstungsrate je Sorte (0111): das massegewichtete Mittel der verwendbaren Wägungen der Sorte, ab anteil_mindest_messungen() Wägungen; sonst das Mittel aller Sorten (b = 0, geliehen). Bis 0110 wurde der Sortenwert per empirischem Bayes zum Gesamtwert gezogen; tau2 bleibt deshalb leer. varianz = Unsicherheit des Mittels, df = n − 1 der geltenden Ebene.';

-- Dieselbe Regel für zu klein, zu gross und Fax (die Formel hinter der
-- Planungsgrenze aus 0109; v_koeff_kaliber_geschaetzt liest sie unverändert).
create or replace view v_koeff_kaliber_geschaetzt_formel with (security_invoker = true) as
with roh as materialized (
  select art, sorte, charge_nr, anteil, gewicht
    from v_koeff_roh_kaliber
   where anteil is not null and gewicht > 0
), mitte as (
  select art, sorte,
         count(*)::int                         as n,
         count(distinct charge_nr)::int        as c_chargen,
         sum(gewicht)                          as sw,
         sum(anteil * gewicht) / sum(gewicht)  as mittel
    from roh
   group by grouping sets ((art, sorte), (art))
), ebene as (
  select m.art, m.sorte, m.n, m.c_chargen, m.mittel,
         case when m.n > 1
              then (select sum(r.gewicht * power(r.anteil - m.mittel, 2)) from roh r
                     where r.art = m.art and (m.sorte is null or r.sorte = m.sorte))
                   / m.sw / (m.n - 1) end      as varianz
    from mitte m
), gitter as (
  select a.art, sk.sorte from (select distinct art from roh) a cross join sorte_kaliber sk
  union all
  select a.art, null::text from (select distinct art from roh) a
)
select gi.art, gi.sorte,
       coalesce(v.n, 0)                                        as n,
       coalesce(v.c_chargen, 0)                                as c_chargen,
       v.mittel                                                as mittel_roh,
       v.varianz                                               as varianz_roh,
       g.mittel                                                as mittel_gesamt,
       null::numeric                                           as tau2,
       b.gewicht                                               as b,
       case when b.gewicht = 1 then coalesce(v.mittel, g.mittel) else g.mittel end as mittel,
       case when b.gewicht = 1 then coalesce(v.varianz, 0) else coalesce(g.varianz, 0) end as varianz,
       greatest(case when b.gewicht = 1 then coalesce(v.n, 0) else g.n end - 1, 1) as df,
       g.n                                                     as n_gesamt,
       b.gewicht * coalesce(v.varianz, 0)                      as varianz_eigen,
       1 - b.gewicht                                           as gewicht_gesamt,
       coalesce(g.varianz, 0)                                  as varianz_gesamt
  from gitter gi
  join ebene g on g.art = gi.art and g.sorte is null
  left join ebene v on v.art = gi.art and v.sorte is not distinct from gi.sorte
 cross join lateral (
   select case when gi.sorte is null then 1.0
               when coalesce(v.n, 0) >= anteil_mindest_messungen() then 1.0
               else 0.0 end::numeric as gewicht) b;
comment on view v_koeff_kaliber_geschaetzt_formel is
  'Die Formel hinter v_koeff_kaliber_geschaetzt (Planungsgrenze 0109): zu klein (ausschuss), zu gross (nebenkanal) und Fax je Sorte — seit 0111 das massegewichtete Mittel der eigenen Messungen ab anteil_mindest_messungen(), sonst das Mittel aller Sorten (b = 0). Kein Zug zum Gesamtwert mehr; tau2 bleibt leer.';

-- Die Basis-Texte sagen, welche Ebene gilt — mit der Regel von heute.
create or replace view v_koeff_verdunstung with (security_invoker = true) as
select sk.sorte,
       case when k.mittel < 0 then 0 else k.mittel end as mittel,
       case when coalesce(k.varianz, 0) = 0 then case when k.mittel < 0 then 0 else k.mittel end
            else greatest(k.mittel - k.t * sqrt(k.varianz), 0) end::double precision as unten,
       case when coalesce(k.varianz, 0) = 0 then case when k.mittel < 0 then 0 else k.mittel end
            else greatest(k.mittel + k.t * sqrt(k.varianz), 0) end::double precision as oben,
       coalesce(k.n, 0) as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Wiegung vorhanden'
            when k.b = 1 then 'Wiegungen dieser Sorte'
            else format('Wiegungen aller Sorten (eigene: %s, gilt ab %s)', coalesce(k.n, 0), anteil_mindest_messungen())
       end as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_verdunstung_geschaetzt g
     where g.art = 'verdunstung' and g.sorte is not distinct from sk.sorte) k on true;
comment on view v_koeff_verdunstung is
  'Die Verdunstungsrate je Tag je Sorte, wie die Kaskade sie nimmt (0111): Mittel der eigenen Wägungen ab drei, sonst aller Sorten; nie negativ, das Band ± t · √varianz. basis sagt die Ebene („dieser Sorte" / „aller Sorten").';

create or replace view v_koeff_ausschuss with (security_invoker = true) as
select sk.sorte, k.mittel,
       case when coalesce(k.varianz, 0) = 0 then k.mittel
            else greatest(k.mittel - k.t * sqrt(k.varianz), 0) end::double precision as unten,
       case when coalesce(k.varianz, 0) = 0 then k.mittel
            else least(k.mittel + k.t * sqrt(k.varianz), 1) end::double precision as oben,
       coalesce(k.n, 0) as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Messung vorhanden'
            when k.b = 1 then 'Sortierläufe/Handmessungen dieser Sorte'
            else format('alle Sorten (eigene: %s, gilt ab %s)', coalesce(k.n, 0), anteil_mindest_messungen())
       end as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'ausschuss' and g.sorte is not distinct from sk.sorte) k on true;

create or replace view v_koeff_nebenkanal with (security_invoker = true) as
select sk.sorte, k.mittel,
       case when coalesce(k.varianz, 0) = 0 then k.mittel
            else greatest(k.mittel - k.t * sqrt(k.varianz), 0) end::double precision as unten,
       case when coalesce(k.varianz, 0) = 0 then k.mittel
            else least(k.mittel + k.t * sqrt(k.varianz), 1) end::double precision as oben,
       coalesce(k.n, 0) as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Messung vorhanden'
            when k.b = 1 then 'Sortierläufe/Handmessungen dieser Sorte'
            else format('alle Sorten (eigene: %s, gilt ab %s)', coalesce(k.n, 0), anteil_mindest_messungen())
       end as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'nebenkanal' and g.sorte is not distinct from sk.sorte) k on true;

create or replace view v_koeff_fax with (security_invoker = true) as
with schalter as (
  select coalesce((select (wert #>> '{}')::boolean from einstellung where schluessel = 'fax_eingefroren'), false) as eingefroren
)
select sk.sorte,
       case when s.eingefroren then 0::numeric else k.mittel end as mittel,
       case when s.eingefroren then 0::double precision
            when coalesce(k.varianz, 0) = 0 then k.mittel::double precision
            else greatest(k.mittel - k.t * sqrt(k.varianz), 0)::double precision end as unten,
       case when s.eingefroren then 0::double precision
            when coalesce(k.varianz, 0) = 0 then k.mittel::double precision
            else least(k.mittel + k.t * sqrt(k.varianz), 1)::double precision end as oben,
       case when s.eingefroren then 0 else coalesce(k.n, 0) end as n,
       case when s.eingefroren then 'eingefroren (Runde R): Fax wird nicht erfasst, erwarteter Anteil 0 durch Entscheid'
            when coalesce(k.n_gesamt, 0) = 0 then 'keine Fax-Arbeit mit gewogenem Faulem'
            when k.b = 1 then 'Fax-Arbeiten dieser Sorte'
            else format('alle Sorten (eigene: %s, gilt ab %s)', coalesce(k.n, 0), anteil_mindest_messungen())
       end as basis
  from sorte_kaliber sk
 cross join schalter s
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'fax' and g.sorte is not distinct from sk.sorte) k on true;

comment on view v_koeff_ausschuss is
  'Zu klein je Sorte (Anteil der Masse unter dem kleinsten Band) mit Bereich, Zahl der Messungen und Bezugsgrösse — seit 0111 das Mittel der eigenen Sortierläufe und Handmessungen ab drei, sonst aller Sorten.';
comment on view v_koeff_nebenkanal is
  'Zu gross je Sorte (Anteil der Masse über dem grössten Band, Nebenkanal) mit Bereich, Zahl der Messungen und Bezugsgrösse — seit 0111 das Mittel der eigenen Messungen ab drei, sonst aller Sorten. Kein Verlust: ein anderer Kanal.';
comment on view v_koeff_unsicherheit is
  'Je Koeffizient und Sorte: der eigene Fehleranteil (b = 1: der Wert der Sorte gilt) oder der Fehler des Gesamtwerts (b = 0: geliehen, 0111). Getrennt, weil der Gesamtwert für alle Sorten derselbe ist und seine Fehler sich nicht wegmitteln.';

-- =====================================================================
-- 2. Wegräumen, was am Palox-Anteil hängt
-- =====================================================================
-- Die Kaskade rechnet den Anteil jetzt für das Alter jeder Portion; dafür
-- wird sie neu angelegt, und mit ihr alles, was auf ihr steht (25 Sichten,
-- unten in derselben Reihenfolge wieder aufgebaut — unverändert bis auf
-- v_prognose, die zu klein und zu gross getrennt ausweist). Keine Tabelle,
-- keine Spalte einer Tabelle.
drop materialized view if exists mv_kaskade cascade;
drop materialized view if exists erg_palox_erwartung cascade;
drop view if exists v_palox_erwartung cascade;
drop view if exists v_palox_station cascade;
-- verdichter: bleibt
-- palox_station_kennzahl() bekommt neue Spalten (Anstieg über die
-- Lagerdauer); „create" legt sie nicht über die alte Fassung. Mit cascade,
-- weil in setup.sql die Ansichten darauf beim Aktualisieren noch stehen —
-- Teil B baut sie ohnehin neu.
drop function if exists palox_station_kennzahl(date, date) cascade;

-- =====================================================================
-- 3. Der Palox-Anteil: Grundausschuss + Anstieg je Woche Lagerdauer
-- =====================================================================
-- Die vier Wochen Messtage aus 0105 gelten nicht mehr: Der Anstieg hängt
-- an der Lagerdauer der Ware, nicht am Kalender der Messungen.
drop function if exists palox_trend_mindest_tage();

-- Wie weit die Lagerdauern innerhalb einer Sorte auseinanderliegen müssen,
-- bevor die Station einen Anstieg ausweist: drei Wochen. Bis 0110 waren es
-- vier Wochen Messtage — gemessen am Kalender, nicht am Alter der Ware.
create or replace function palox_anstieg_mindest_tage() returns int
language sql immutable as $$ select 21 $$;
comment on function palox_anstieg_mindest_tage() is
  'So viele Tage müssen die Lagerdauern innerhalb einer Sorte mindestens auseinanderliegen, bevor eine Station ihren Anstieg je Woche ausweist (0111).';
revoke all on function palox_anstieg_mindest_tage() from public;
grant execute on function palox_anstieg_mindest_tage() to authenticated;

-- Wann ein gemessener Anstieg gilt: ab fünf Arbeiten in Sorten mit zwei
-- Arbeiten und drei Wochen Spanne der Lagerdauern; gilt er, ist er nie
-- negativ (weniger Faules mit der Zeit ist Streuung, kein Heilen). Eine
-- eigene Funktion, damit die Regel an einer Stelle steht und für sich
-- geprüft werden kann. Nennt public, weil PostgreSQL 17 beim Auffrischen
-- nur pg_catalog sucht (0110).
create or replace function palox_anstieg(p_roh numeric, p_n_paar int, p_spanne int) returns numeric
language sql immutable as $$
  select case when p_roh is not null and p_n_paar >= 5 and p_spanne >= public.palox_anstieg_mindest_tage()
              then greatest(p_roh, 0) end
$$;
comment on function palox_anstieg(numeric, integer, integer) is
  'Der Anstieg je Woche, der gilt (0111): leer unter fünf Arbeiten in Sorten mit zwei Arbeiten oder unter palox_anstieg_mindest_tage() Spanne, sonst der gemessene, nie unter 0.';
revoke all on function palox_anstieg(numeric, integer, integer) from public;
grant execute on function palox_anstieg(numeric, integer, integer) to authenticated;

-- Die Kennzahl je Station. Die Spalten bis zuwachs_text bleiben, was sie
-- waren — bis auf zuwachs_je_woche: Das ist jetzt der Anstieg des Anteils
-- je Woche LAGERDAUER, nicht je Kalenderwoche, und nie negativ (die Kaskade
-- und die Prognose schreiben damit fort). Gerechnet wird er innerhalb der
-- Sorten: Jede Sorte wird um ihre eigene Mitte gelegt (Lagerdauer und
-- Anteil), dann eine gemeinsame Gerade. So zählt eine Sorte, die von Anfang
-- an viel aussortiert (Fictor: Grünes), nicht als Anstieg, nur weil sie
-- früh verarbeitet wurde. Punkte einer Sorte mit nur einer Arbeit an der
-- Station tragen zur Steigung nichts bei.
--   anstieg_roh       die Steigung, wie sie gemessen ist (auch negativ)
--   anstieg_unten/oben  ± t · Standardfehler (Gewichte = Masse, auf Mittel 1)
--   n_paar            Arbeiten in Sorten mit mindestens zwei Arbeiten
--   spanne_tage       die grösste Spanne der Lagerdauern innerhalb einer Sorte
--   lager_von/bis     die Lagerdauern aller Arbeiten der Station
--   lager_mittel      ihre mittlere Lagerdauer, nach Masse gewichtet
--   grund             der Grundausschuss der Station über alle Sorten:
--                     anteil_mittel − zuwachs_je_woche × lager_mittel / 7
create function palox_station_kennzahl(p_bis date, p_ab date default null)
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
  )
  select f.station, f.n_arbeiten, f.n_chargen, f.seit, f.bis, f.tage,
         zahl(f.anteil_mittel, 5, 1)::numeric(10,5), zahl(f.anteil_median::numeric, 5, 1)::numeric(10,5),
         zahl(f.anteil_4w, 5, 1)::numeric(10,5), f.n_4w,
         zahl(palox_anstieg(f.b_tag * 7, f.n_paar, f.spanne_tage), 5, 1)::numeric(10,5) as zuwachs_je_woche,
         case when f.bekannt and f.b_tag >= 0 then null
              when f.bekannt then format('kein Anstieg messbar (gemessen %s Punkte je Woche)',
                                         replace(replace(to_char(f.b_tag * 700, 'FM990.0'), '.', ','), '-', '−'))
              when f.n_paar < 5 then format('Anstieg erst ab fünf Arbeiten in Sorten mit mindestens zwei Arbeiten (%s bis jetzt)', f.n_paar)
              else format('Anstieg erst, wenn die Lagerdauern einer Sorte %s Tage auseinanderliegen (bis jetzt %s)',
                          palox_anstieg_mindest_tage(), f.spanne_tage) end as zuwachs_text,
         zahl(f.b_tag * 7, 5, 1)::numeric(10,5) as anstieg_roh,
         zahl((f.b_tag - t_quantil_95(f.df) * f.se_tag) * 7, 5, 1)::numeric(10,5) as anstieg_unten,
         zahl((f.b_tag + t_quantil_95(f.df) * f.se_tag) * 7, 5, 1)::numeric(10,5) as anstieg_oben,
         f.n_paar, f.spanne_tage, f.lager_von, f.lager_bis,
         zahl(f.lager_mittel, 1, 100000)::numeric(10,1) as lager_mittel,
         zahl(greatest(f.anteil_mittel - coalesce(palox_anstieg(f.b_tag * 7, f.n_paar, f.spanne_tage), 0) * f.lager_mittel / 7.0, 0), 5, 1)::numeric(10,5) as grund
    from fertig f
   order by case f.station when 'waschen_sortieren' then 1 when 'waschen' then 2 else 3 end;
end $$;
comment on function palox_station_kennzahl(date, date) is
  'Die Kennzahl je Station (0105, Anstieg seit 0111): Mittel, Median, letzte vier Wochen, und der Anstieg des Palox-Anteils je Woche Lagerdauer — innerhalb der Sorten gerechnet, nie negativ, bekannt ab fünf Arbeiten in Sorten mit zwei Arbeiten und drei Wochen Spanne der Lagerdauern.';
revoke all on function palox_station_kennzahl(date, date) from public;
grant execute on function palox_station_kennzahl(date, date) to authenticated;

create view v_palox_station with (security_invoker = true) as
select * from palox_station_kennzahl(heute());
comment on view v_palox_station is
  'Die Kennzahl je Station bis heute (0105) — unter dem Diagramm „Palox-Ausschuss". zuwachs_je_woche ist seit 0111 der Anstieg je Woche Lagerdauer.';
grant select on v_palox_station to authenticated;

-- Die Erwartung je Sorte und Station: der Grundausschuss. Das ist der
-- Anteil, den die Station bei frischer Ware aussortiert (Hagel, Schnitt,
-- Grünes) — das massegewichtete Mittel der Sorte, um den Anstieg der
-- Station auf null Lagertage zurückgelegt:
--   anteil = Mittel − Anstieg je Woche × mittlere Lagerdauer / 7
-- Ohne bekannten Anstieg ist anteil das Mittel selbst. Eine Sorte braucht
-- palox_mindest_arbeiten() eigene Arbeiten an der Station, sonst gilt der
-- Wert aller Sorten (geliehen). Die Vier-Wochen-Fenster sind weg: Wie alt
-- die Ware war, sagt jetzt die Lagerdauer, nicht der Kalender.
create view v_palox_erwartung with (security_invoker = true) as
with punkte as materialized (
  select e.sorte, e.station, e.charge_nr, e.messtag, e.lagertage::numeric as t,
         e.basis_jetzt_kg as w, e.anteil_station as y
    from v_schimmel_punkte e
   where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
     and e.lagertage is not null
     and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
     and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
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
comment on view v_palox_erwartung is
  'Je Sorte und Station der Grundausschuss (0111): der Palox-Anteil bei frischer Ware — Mittel der plausiblen Punkte der Sorte (massegewichtet), um den Anstieg der Station (v_palox_station.zuwachs_je_woche) auf null Lagertage zurückgelegt. Ab palox_mindest_arbeiten() Arbeiten der Sorte, sonst aller Sorten (geliehen). Für Ware mit t Lagertagen gilt anteil + anstieg_je_woche · t / 7. mittel/lager_mittel: wie gemessen. unten/oben: ± t · sd/√n.';
grant select on v_palox_erwartung to authenticated;

create materialized view erg_palox_erwartung as
select * from v_palox_erwartung
with no data;
comment on materialized view erg_palox_erwartung is
  'v_palox_erwartung, gespeichert (0107): der Grundausschuss je Sorte und Station mit dem Anstieg der Station (0111) — das Dashboard und der Betriebsabzug lesen diese Fassung. Schritt 3.';
grant select on erg_palox_erwartung to authenticated;

-- =====================================================================
-- 4. Die Kaskade — jeder Stationswert beim Alter seiner Portion
-- =====================================================================
-- Unverändert wie in 0106 bis auf drei Stellen: je_station sagt, ob der
-- Wert die eigene Messung der Charge ist (eigen); teile schreibt jeden
-- Stationswert um den Anstieg der Station über die Lagerdauer der Portion
-- fort (nach), ausser bei eigener Messung (b = 0); und b_ws/b_s/b_w sind
-- dieser Anstieg — damit Prognose und Verlauf von genau hier aus weiter-
-- und zurückschreiben.
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
            'entsorgt'::text,
            e.kohorte,
            e.masse_kg,
            COALESCE(e.alter_tage, 0::numeric) AS "coalesce",
            NULL::numeric AS "numeric",
            e.n_lieferungen
           FROM koeff_norm k
             JOIN entsorgt_lief e ON e.charge_nr = k.charge_nr
        UNION ALL
         SELECT k.charge_nr,
            'lager'::text,
            c.eingangsdatum,
            NULL::numeric AS "numeric",
            GREATEST((k.stichtag - c.eingangsdatum)::numeric, 0::numeric) AS "greatest",
            c.eingang_kg,
            0
           FROM koeff_norm k
             JOIN kohorten c ON c.charge_nr = k.charge_nr
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
            k.a_klein_n,
            k.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            w.p_hand,
            w.p_wasch,
            w.weg_quelle,
            nach.f_ws,
            nach.f_s,
            nach.g_w,
            palox_f(w.p_hand, w.p_wasch, nach.f_ws, nach.f_s, nach.g_w) AS f_roh,
            palox_f_nach(w.p_hand, w.p_wasch, ws.unten, s.unten, wa.unten, b.b_ws, b.b_s, b.b_w, t.alter_tage) AS f_unten_roh,
            palox_f_nach(w.p_hand, w.p_wasch, ws.oben, s.oben, wa.oben, b.b_ws, b.b_s, b.b_w, t.alter_tage) AS f_oben_roh,
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
                        CASE WHEN ws.eigen THEN 0::numeric ELSE zws.zuwachs_je_woche END AS b_ws,
                        CASE WHEN s.eigen THEN 0::numeric ELSE zs.zuwachs_je_woche END AS b_s,
                        CASE WHEN wa.eigen THEN 0::numeric ELSE zw.zuwachs_je_woche END AS b_w) b
             CROSS JOIN LATERAL ( SELECT
                        CASE WHEN ws.f IS NULL THEN NULL::numeric ELSE LEAST(GREATEST(ws.f + COALESCE(b.b_ws, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric) END AS f_ws,
                        CASE WHEN s.f IS NULL THEN NULL::numeric ELSE LEAST(GREATEST(s.f + COALESCE(b.b_s, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric) END AS f_s,
                        CASE WHEN wa.f IS NULL THEN NULL::numeric ELSE LEAST(GREATEST(wa.f + COALESCE(b.b_w, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric) END AS g_w) nach
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
    verkaufsfaehig_anteil
   FROM kaskade
with no data;
create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, portion, COALESCE(kohorte, '1900-01-01'::date));
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);
comment on materialized view mv_kaskade is
  'Die Massenkaskade je Charge, Eingangstag und Portion. Drei Portionen: „ausgelagert" ist die Eingangsmasse hinter den verkauften und in den Nebenkanal gegangenen Lieferungen, „entsorgt" die hinter dem Kompost (0065 — nur um die Verdunstung zurückgerechnet, weil entsorgte Ware selbst das Faule ist), „lager" der Rest, der noch liegt. Je Portion die Ströme Verdunstung, Palox-Ausschuss, zu klein, zu gross, Fax und verkaufsfähig. f ist der Palox-Anteil über den Weg der Charge (palox_f: p_hand, p_wasch, f_ws, f_s, g_w). Seit 0111 gilt jeder Stationswert für das Alter der Portion: Grundausschuss der Sorte (v_palox_erwartung) + Anstieg der Station je Woche Lagerdauer (v_palox_station) × alter_tage / 7; für Ausgelagertes mit eigener Messung gilt diese, ohne Anstieg. f_quelle sagt, woher; f_geliehen: aus allen Sorten. b_ws/b_s/b_w ist der Anstieg, mit dem Prognose und Verlauf fortschreiben (0 bei eigener Messung), zuwachs_bekannt sagt, ob sie es dürfen.';
grant select on mv_kaskade to authenticated;


-- =====================================================================
-- 5. Was auf der Kaskade steht — wieder aufgebaut
-- =====================================================================
-- Die Formeln sind abgedruckt, wie PostgreSQL sie nach 0110 hält
-- (pg_get_viewdef), in der Reihenfolge der Abhängigkeit. Geändert sind
-- zwei: v_prognose — zu klein (klein_kg) und zu gross (gross_kg) stehen
-- einzeln neben kanal_kg, für Unter- und Überkaliber unter „Was ist noch im
-- Haus" (erg_prognose nimmt alle Spalten); und erg_verlauf — eine gelieferte
-- Portion zählt ab ihrem Liefertag mit ihrem genauen Alter, wie in der
-- Kaskade, nicht mit dem auf ganze Tage gerundeten. Sonst sagten Verlauf und
-- Saisonbilanz bei „im Haus" heute Verschiedenes: auf den Betriebsdaten vom
-- 12. Oktober 4.3 kg (6.4 kg mit dem Anstieg je Lagerwoche), die Gegenprobe
-- erlaubt 0.5 kg. Der Liefertag selbst bleibt der gerundete Tag.

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
         SELECT 'sorte'::text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text,
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
        ), je_woche AS (
         SELECT w_1.woche,
            w_1.bis,
            p.charge_nr,
            p.m0 * (1::numeric - power(1::numeric - p.r, x.t::numeric)) AS verdunstung_kg,
            p.m0 * power(1::numeric - p.r, x.t::numeric) * f.f AS schimmel_kg,
                CASE
                    WHEN p.liefertag IS NOT NULL AND p.liefertag <= w_1.bis THEN p.fax_kg
                    ELSE 0::numeric
                END AS fax_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0
                    ELSE 0::numeric
                END AS lager_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - f.f)
                    ELSE 0::numeric
                END AS gute_ware_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - f.f) * (p.a_klein_n + p.a_gross_n)
                    ELSE 0::numeric
                END AS kanal_lager_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - f.f) * (1::numeric - p.a_klein_n - p.a_gross_n) * p.a_fax
                    ELSE 0::numeric
                END AS fax_lager_kg,
                CASE
                    WHEN p.liefertag IS NOT NULL AND p.liefertag <= w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - f.f) * (p.a_klein_n + p.a_gross_n)
                    ELSE 0::numeric
                END AS aussortiert_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - f.f) * (1::numeric - p.a_klein_n - p.a_gross_n) * (1::numeric - p.a_fax)
                    ELSE 0::numeric
                END AS verkaufsfaehig_kg
           FROM wochen w_1
             JOIN portionen p ON p.kohorte <= w_1.bis
             CROSS JOIN tag d_1
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.liefertag IS NOT NULL AND p.liefertag <= w_1.bis THEN p.alter_tage
                            ELSE GREATEST(LEAST(w_1.bis, COALESCE(p.liefertag, w_1.bis)) - p.kohorte, 0)::numeric
                        END AS t) x
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.zuwachs_bekannt THEN COALESCE(palox_f_nach(p.p_hand, p.p_wasch, p.f_ws, p.f_s, p.g_w, p.b_ws, p.b_s, p.b_w, (LEAST(w_1.bis, COALESCE(p.liefertag, w_1.bis)) - COALESCE(p.liefertag, d_1.heute))::numeric), p.f)
                            ELSE p.f
                        END AS f) f
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
  'Je Woche und Gruppe (gesamt, Sorte, Schlag, Charge): Eingang und Ausgang kumuliert (gemessen), im Lager (Eingangsware, die noch nicht hinter einer Lieferung steckt) und davon verkaufsfähig (gerechnet) — ab heute als Prognose bis zum Saisonende (prognose = true). Der Verlust ist der Abstand zwischen im Lager und verkaufsfähig; seine Teile stehen weiter als eigene Spalten (0071). Seit 0106 ohne Sockel: das Faule ist der Palox-Anteil der Stationen, mit dem Zuwachs je Woche zurück und voraus verschoben, wo die Kennzahl ihn ausweist.';
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
            sum(mv_kaskade.n_lieferungen)::integer AS n_lieferungen,
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
    COALESCE(k.n_lieferungen, 0) > 0 AS rest_alter_aus_zaehlung,
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
    COALESCE(k.n_lieferungen, 0) AS n_lieferungen,
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
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN k.rest_tage_seit_epoche IS NOT NULL THEN '2000-01-01'::date + round(k.rest_tage_seit_epoche)::integer
                    ELSE b.eingangsdatum_mittel
                END AS rest_datum) x
  WHERE b.eingang_kg IS NOT NULL;
comment on view v_hochrechnung_basis is
  'Je Charge, alles bis heute: Eingang und geliefert (gemessen), ausgelagert (Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus ausgelagert, in Eingangskilo), verlust_heute_kg (Verdunstung + Faules + Fax am Abgepackten), im_haus_heute_kg (Eingangsmasse, die noch liegt, nach Verdunstung und Verderb, plus hinter den Lieferungen Aussortiertes, 0101). Keine Prognose. 0064: Jede Stromsumme ist NULL, solange ihr Koeffizient keine Messung hat. Seit 0106 ohne Sockel; faul_anteil und faul_quelle sagen, womit das Liegende rechnet und woher es kommt.';
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
            l.a_klein_n,
            l.a_gross_n,
            l.a_fax,
            l.r_bekannt,
            l.f_bekannt,
            l.a_klein_bekannt,
            l.a_gross_bekannt,
            l.a_fax_bekannt,
            l.f_geliehen,
            l.r_unten,
            l.r_oben,
            l.klein_unten,
            l.klein_oben,
            l.gross_unten,
            l.gross_oben,
            l.fax_unten,
            l.fax_oben,
            l.wa,
            l.wa_unten,
            l.wa_oben,
            h.h,
            (l.alter_tage + h.h::numeric)::integer AS t,
                CASE
                    WHEN l.zuwachs_bekannt THEN COALESCE(palox_f_nach(l.p_hand, l.p_wasch, l.f_ws, l.f_s, l.g_w, l.b_ws, l.b_s, l.b_w, h.h::numeric), l.f)
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
            b.basis * (1::numeric - p.f) * (1::numeric - p.wh) AS verlust_wasser,
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
        ), gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text,
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
select * from v_prognose
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
    format(('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette '::text || 'dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — gerechnet '::text) || 'wird deshalb mit der mittleren Tara der Charge, nicht mit ihrer eigenen.'::text, count(*), ap.brutto_zettel_kg, to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
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
         SELECT 'sorte'::text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text,
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
  WHERE NOT w.verwendbar AND NOT w.sichtbar_schimmel AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
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
            WHEN bool_and(ap.kisten IS NOT NULL AND ap.gebindeart IS NOT NULL) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            ELSE 'gerechnet wird mit der mittleren Tara der Charge; stehen Kisten und Gebinde an der Palette, mit deren Tara'::text
        END) AS befund,
    'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal).'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
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
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette. 0066: „Ausschuss-Tara" rechnet nur nach, wo Kistenzahl und hinterlegte Tara da sind; fehlt eine, steht die Lücke als „Ausschuss ohne Tara" daneben. 0087: die Nachrechnung zieht die Palette nur ab, wenn sie mitgewogen wurde, und klemmt nichts auf null.';
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
         SELECT 'sorte'::text,
            erg_charge.sorte,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'schlag'::text,
            erg_charge.schlag,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'charge'::text,
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
-- erg_bilanz, erg_marge, erg_massenbilanz, erg_naechste_charge und
-- erg_plausibilitaet baut die Schleife aus 0106 (select * aus ihrer Sicht).
-- „drop … cascade" oben hat sie mitgerissen; hier baut dieselbe Schleife sie
-- wieder — nicht ausgeschriebenes SQL. Ausgeschrieben stünden sie in
-- setup.sql zweimal, einmal aus der Schleife von 0106 und einmal von hier,
-- und das zweite „create" bräche auf einer leeren Datenbank ab: Der
-- Verdichter kennt Namen aus einer Schleife nur über die Angabe darüber.
-- Die Spalten sind dieselben wie die ihrer Sicht (geprüft auf dem Stand
-- nach 0111), es entsteht also genau das, was ausgeschrieben stand.
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
-- 6. Was ist noch im Haus: Unterkaliber, die Bänder, Überkaliber
-- =====================================================================
-- Bis 0110 verteilte lager_kaliber() nur das Verkaufsfähige auf die Bänder,
-- und was seit der Sortierung unter das kleinste Band geschrumpft war,
-- stand als „unter Kaliber" (gelb) mitten darin. Der Betrieb las das als
-- Unterkaliber und fragte nach dem Überkaliber (12. Oktober). Jetzt je
-- Gruppe drei Arten Zeilen (klasse):
--   'unter'   kaliber_idx −1: zu klein (klein_kg aus der Prognose: Masse
--             nach Palox × gemessener Anteil zu klein der Sorte)
--   'kaliber' kaliber_idx 0…n: das Verkaufsfähige in seinen Bändern
--             (ohne Sortier-CSV: eine Zeile ohne Band, kaliber_idx leer)
--   'ueber'   kaliber_idx −2: zu gross (gross_kg aus der Prognose)
-- Die Bänder summieren auf verkaufsfaehig_kg — dieselbe Zahl wie die Kachel
-- „davon verkaufsfähig", der Verlauf und die Chargen; eine Zahl, eine
-- Rechnung. Was seit der Sortierung unter das kleinste Band geschrumpft ist,
-- zählt im kleinsten Band: Ein sortierter Kürbis bleibt in seiner Kiste,
-- und für die liegende Ware steckt das Zu-klein im gemessenen Anteil der
-- Sorte. Wie viel es ist, sagt geschrumpft_kg (ein Teil des kleinsten
-- Bandes, zur Auskunft). Unbekannt bleibt unbekannt: Ist zu klein oder zu
-- gross nicht gemessen, sind klein_kg/gross_kg und die Zeilen leer; ohne
-- Sortier-CSV ist geschrumpft_kg leer, nicht 0.
drop view if exists v_lager_kaliber;
drop function if exists lager_kaliber(integer);
create function lager_kaliber(p_h integer)
returns table(gruppe text, schluessel text, sorte text, h integer, datum date, kaliber_idx integer,
              band_von integer, band_bis integer, kg numeric, anteil numeric, basis text, n_kuerbis integer,
              verkaufsfaehig_kg numeric, lager_kg numeric, n_chargen integer,
              klasse text, klein_kg numeric, gross_kg numeric, geschrumpft_kg numeric)
language sql stable security definer set search_path = public as $$
with fassung as (
  -- Die Bänder je Sorte: die jüngste gültige Fassung.
  select distinct on (s.sorte) s.sorte, s.kaliber_baender
    from sortierschema s
   where s.art = 'kaliber' and s.gilt_ab <= heute()
   order by s.sorte, s.gilt_ab desc, s.id desc
), band as (
  select f.sorte, (x.ordinality - 1)::int as kaliber_idx,
         (x.b ->> 0)::int as band_von, (x.b ->> 1)::int as band_bis,
         x.ordinality = jsonb_array_length(f.kaliber_baender) as letztes
    from fassung f
   cross join lateral jsonb_array_elements(f.kaliber_baender) with ordinality as x(b, ordinality)
), schwellen as (
  -- Je Sorte die Bandgrenzen als sortierte Schwellen: von_0, von_1, …, bis_n.
  select b.sorte,
         array_agg(b.band_von::numeric order by b.kaliber_idx)
           || (select max(x.band_bis)::numeric from band x where x.sorte = b.sorte and x.letztes) as grenzen,
         count(*)::int as n_baender
    from band b
   group by b.sorte
), verteilung_roh as (
  -- Massenanteile je Band. Bucket 0 = unter dem kleinsten Band
  -- (kaliber_idx −1); Bucket n+1 (genau auf der Obergrenze) gehört zum
  -- obersten Band — Klasse „kaliber" heisst, die Maschine hat ihn im Band
  -- gesehen, und schrumpfende Ware wächst nicht darüber hinaus.
  select w.basis, w.schluessel, w.sorte,
         case when sw.grenzen is null then null
              else least(width_bucket(w.g::numeric, sw.grenzen), sw.n_baender) - 1 end as kaliber_idx,
         sum(w.anzahl * w.g)  as masse_g,
         sum(w.anzahl)        as n_kuerbis
    from kuerbis_stichtag(p_h) w
    left join schwellen sw on sw.sorte = w.sorte
   group by w.basis, w.schluessel, w.sorte,
            case when sw.grenzen is null then null
                 else least(width_bucket(w.g::numeric, sw.grenzen), sw.n_baender) - 1 end
), verteilung_band as (
  -- Unter dem kleinsten Band (Bucket −1) zählt im kleinsten Band (0); der
  -- Anteil darunter bleibt als Auskunft stehen.
  select v.basis, v.schluessel, v.sorte,
         case when v.kaliber_idx is null then null else greatest(v.kaliber_idx, 0) end as kaliber_idx,
         sum(v.masse_g)                                             as masse_g,
         coalesce(sum(v.masse_g) filter (where v.kaliber_idx = -1), 0) as masse_darunter_g,
         sum(v.n_kuerbis)                                           as n_kuerbis
    from verteilung_roh v
   group by v.basis, v.schluessel, v.sorte,
            case when v.kaliber_idx is null then null else greatest(v.kaliber_idx, 0) end
), verteilung as (
  select v.basis, v.schluessel, v.sorte, v.kaliber_idx, b.band_von, b.band_bis,
         v.masse_g / nullif(sum(v.masse_g) over w, 0)          as anteil,
         sum(v.masse_darunter_g) over w / nullif(sum(v.masse_g) over w, 0) as anteil_darunter,
         sum(v.n_kuerbis) over w                               as n_kuerbis
    from verteilung_band v
    left join band b on b.sorte = v.sorte and b.kaliber_idx = v.kaliber_idx
  window w as (partition by v.basis, v.schluessel)
), prognose as (
  select p.schluessel::int as charge_nr, c.sorte, c.schlag, p.h, p.datum, q.basis, q.schluessel as q_schluessel,
         p.verkaufsfaehig_kg, p.lager_kg,
         case when p.kanal_bekannt then p.klein_kg end as klein_kg,
         case when p.kanal_bekannt then p.gross_kg end as gross_kg
    from erg_prognose p
    join charge c on c.nr = p.schluessel::int
    join lager_schluessel() q on q.charge_nr = c.nr
   where p.gruppe = 'charge' and p.h = p_h
), je_band as (
  select p.charge_nr, p.sorte, p.h, p.datum, p.basis,
         v.kaliber_idx, v.band_von, v.band_bis,
         case when p.basis = 'keine' then null else v.anteil end              as anteil,
         case when p.basis = 'keine' then p.verkaufsfaehig_kg
              else p.verkaufsfaehig_kg * v.anteil end                         as kg,
         v.n_kuerbis, v.anteil_darunter
    from prognose p
    left join verteilung v on v.basis = p.basis and v.schluessel = p.q_schluessel
), je_charge as (
  -- Je Charge, was unter das kleinste Band geschrumpft ist — ein Teil des
  -- kleinsten Bandes, zur Auskunft (ohne CSV: unbekannt).
  select p.*,
         case when p.basis = 'keine' then null
              else p.verkaufsfaehig_kg * coalesce((select max(b.anteil_darunter) from je_band b
                                                    where b.charge_nr = p.charge_nr), 0) end as geschrumpft_kg,
         (select max(b.n_kuerbis) from je_band b where b.charge_nr = p.charge_nr) as n_kuerbis
    from prognose p
), zeilen_charge as (
  -- Die Bänder: das Verkaufsfähige …
  select b.charge_nr, b.sorte, b.h, b.datum, 'kaliber'::text as klasse,
         case when b.basis = 'keine' then null else b.kaliber_idx end as kaliber_idx,
         b.band_von, b.band_bis, b.kg, b.anteil, b.basis
    from je_band b
  union all
  -- … Unterkaliber: zu klein …
  select c.charge_nr, c.sorte, c.h, c.datum, 'unter', -1, null, null,
         c.klein_kg, null, c.basis
    from je_charge c
  union all
  -- … Überkaliber: zu gross.
  select c.charge_nr, c.sorte, c.h, c.datum, 'ueber', -2, null, null,
         c.gross_kg, null, c.basis
    from je_charge c
), zeilen as (
  select 'charge'::text as gruppe, z.charge_nr::text as schluessel, z.sorte, z.h, z.datum,
         z.kaliber_idx, z.band_von, z.band_bis, z.kg, z.anteil, z.basis, c.n_kuerbis,
         c.verkaufsfaehig_kg,
         c.lager_kg, 1 as n_chargen, z.klasse, c.klein_kg, c.gross_kg, c.geschrumpft_kg
    from zeilen_charge z
    join je_charge c on c.charge_nr = z.charge_nr
  union all
  select 'sorte', s.sorte, s.sorte, s.h, s.datum,
         s.kaliber_idx, s.band_von, s.band_bis, s.kg, s.anteil, s.basis, s.n_kuerbis,
         s.verkaufsfaehig_kg, s.lager_kg, s.n_chargen, s.klasse, s.klein_kg, s.gross_kg, s.geschrumpft_kg
    from (
      select z.sorte, z.h, max(z.datum) as datum, z.kaliber_idx, z.band_von, z.band_bis, z.klasse,
             sum(z.kg) as kg,
             null::numeric as anteil,
             case when count(distinct z.basis) = 1 then min(z.basis) else 'gemischt' end as basis,
             (select max(c2.n_kuerbis) from je_charge c2 where c2.sorte = z.sorte) as n_kuerbis,
             (select sum(c2.verkaufsfaehig_kg) from je_charge c2 where c2.sorte = z.sorte) as verkaufsfaehig_kg,
             (select sum(c2.lager_kg) from je_charge c2 where c2.sorte = z.sorte) as lager_kg,
             (select count(*) from je_charge c2 where c2.sorte = z.sorte)::int as n_chargen,
             (select sum(c2.klein_kg) from je_charge c2 where c2.sorte = z.sorte) as klein_kg,
             (select sum(c2.gross_kg) from je_charge c2 where c2.sorte = z.sorte) as gross_kg,
             (select sum(c2.geschrumpft_kg) from je_charge c2 where c2.sorte = z.sorte) as geschrumpft_kg
        from zeilen_charge z
       group by z.sorte, z.h, z.kaliber_idx, z.band_von, z.band_bis, z.klasse
    ) s
)
select gruppe, schluessel, sorte, h, datum,
       kaliber_idx, band_von, band_bis,
       zahl(kg, 2, 1e12)::numeric(14,2)                     as kg,
       -- anteil: Anteil des Bandes am Verkaufsfähigen (die Bänder zusammen 1).
       -- zu klein/zu gross haben keinen — sie sind nicht verkaufsfähig.
       zahl(case when basis = 'keine' or klasse <> 'kaliber' then null
                 else kg / nullif(verkaufsfaehig_kg, 0) end, 4, 1)::numeric(6,4) as anteil,
       basis,
       n_kuerbis::int                                       as n_kuerbis,
       zahl(verkaufsfaehig_kg, 2, 1e12)::numeric(14,2)      as verkaufsfaehig_kg,
       zahl(lager_kg, 2, 1e12)::numeric(14,2)               as lager_kg,
       n_chargen::int                                       as n_chargen,
       klasse,
       zahl(klein_kg, 2, 1e12)::numeric(14,2)               as klein_kg,
       zahl(gross_kg, 2, 1e12)::numeric(14,2)               as gross_kg,
       zahl(geschrumpft_kg, 2, 1e12)::numeric(14,2)         as geschrumpft_kg
  from zeilen
$$;
comment on function lager_kaliber(integer) is
  'Was in h Tagen noch im Haus ist, je Charge und je Sorte, nach Kaliber (0079, Unter-/Überkaliber seit 0111): klasse ''unter'' (kaliber_idx −1: zu klein), ''kaliber'' (die Bänder; ohne Sortier-CSV eine Zeile ohne Band), ''ueber'' (kaliber_idx −2: zu gross). verkaufsfaehig_kg = Summe der Bänder = Verkaufsfähiges der Prognose. geschrumpft_kg: der Teil des kleinsten Bandes, der seit der Sortierung darunter geschrumpft ist (zur Auskunft). anteil: Anteil des Bandes am Verkaufsfähigen.';
revoke all on function lager_kaliber(integer) from public;
grant execute on function lager_kaliber(integer) to authenticated;

create view v_lager_kaliber with (security_invoker = true) as
select * from lager_kaliber(0);
comment on view v_lager_kaliber is
  'lager_kaliber(0): das Lager nach Kaliber heute, mit Unter- und Überkaliber (0111) — zum Nachschauen im SQL-Editor. Der Bildschirm ruft lager_kaliber(0) und lager_kaliber(7·X) direkt; im Rechenwerk (auswertung_schritt) steht keine gespeicherte Fassung (0078).';
grant select on v_lager_kaliber to authenticated;

-- =====================================================================
-- 7. Dieselbe Charge an zwei Sortiertagen (AB-113)
-- =====================================================================
-- Seit Oktober trägt die Sortierdatei das Datum hinter der Charge
-- („1614_07_10_26"). Wird eine Charge zweimal sortiert, zeigt der Vergleich
-- der Läufe, wie viel ein Kürbis in der Zwischenzeit leichter geworden ist.
-- Je Lauf: Median, Quartile und Mittel des Gewichts je Kürbis (alle Klassen
-- ausser unklassiert); gegen den ersten Lauf der Charge der Abstand in Tagen
-- und die Rate je Tag — aus dem Median und aus dem Mittel. Das ist eine
-- Gegenprobe neben der Rate aus den Palettenwägungen, nicht ein Teil davon:
-- Es sind nicht dieselben Kürbisse (andere Paletten, das Faule vorher
-- heraus). Erst ab sieben Tagen Abstand steht eine Rate.
create view v_lauf_vergleich with (security_invoker = true) as
with lauf as (
  select l.id as lauf_id, l.charge_nr, c.sorte, l.sortiertag, l.sortiertag_quelle, l.datei_name
    from sortier_lauf l
    join charge c on c.nr = l.charge_nr
   where l.sortiertag is not null
), stueck as (
  select g.lauf_id, g.gewicht_g, sum(g.anzahl) as anzahl
    from sortier_gewicht g
   where g.klasse <> 'unklassiert' and g.anzahl > 0 and g.gewicht_g > 0
   group by g.lauf_id, g.gewicht_g
), kumuliert as (
  select s.lauf_id, s.gewicht_g, s.anzahl,
         sum(s.anzahl) over (partition by s.lauf_id order by s.gewicht_g) as bis_hier,
         sum(s.anzahl) over (partition by s.lauf_id) as gesamt
    from stueck s
), je_lauf as (
  select k.lauf_id,
         max(k.gesamt)::int                                                     as n_kuerbis,
         sum(k.anzahl * k.gewicht_g)::numeric / nullif(max(k.gesamt), 0)        as mittel_g,
         min(k.gewicht_g) filter (where k.bis_hier >= 0.25 * k.gesamt)          as q1_g,
         min(k.gewicht_g) filter (where k.bis_hier >= 0.50 * k.gesamt)          as median_g,
         min(k.gewicht_g) filter (where k.bis_hier >= 0.75 * k.gesamt)          as q3_g
    from kumuliert k
   group by k.lauf_id
), mit_erstem as (
  select l.*, j.n_kuerbis, j.mittel_g, j.q1_g, j.median_g, j.q3_g,
         first_value(l.lauf_id) over w   as erster_lauf_id,
         first_value(l.sortiertag) over w as erster_tag,
         first_value(j.median_g) over w  as erster_median_g,
         first_value(j.mittel_g) over w  as erster_mittel_g,
         count(*) over (partition by l.charge_nr) as n_laeufe
    from lauf l
    join je_lauf j on j.lauf_id = l.lauf_id
  window w as (partition by l.charge_nr order by l.sortiertag, l.lauf_id)
)
select m.charge_nr, m.sorte, m.lauf_id, m.datei_name, m.sortiertag, m.sortiertag_quelle, m.n_laeufe,
       m.n_kuerbis,
       zahl(m.mittel_g, 1, 100000)::numeric(8,1) as mittel_g,
       m.q1_g, m.median_g, m.q3_g,
       m.erster_lauf_id,
       (m.sortiertag - m.erster_tag)              as tage_seit_erstem,
       case when m.sortiertag - m.erster_tag >= 7 and m.erster_median_g > 0 and m.median_g > 0
            then zahl(1 - power(m.median_g::numeric / m.erster_median_g, 1.0 / (m.sortiertag - m.erster_tag)), 6, 1)
       end::numeric(10,6)                          as rate_median,
       case when m.sortiertag - m.erster_tag >= 7 and m.erster_mittel_g > 0 and m.mittel_g > 0
            then zahl(1 - power(m.mittel_g / m.erster_mittel_g, 1.0 / (m.sortiertag - m.erster_tag)), 6, 1)
       end::numeric(10,6)                          as rate_mittel,
       kv.mittel                                   as rate_wiegungen
  from mit_erstem m
  left join v_koeff_verdunstung kv on kv.sorte = m.sorte;
comment on view v_lauf_vergleich is
  'Sortierläufe derselben Charge nebeneinander (AB-113, 0111): je Lauf Median, Quartile und Mittel des Gewichts je Kürbis; gegen den ersten Lauf der Charge die Tage dazwischen und die Rate je Tag aus Median und Mittel (ab sieben Tagen), daneben die Rate aus den Palettenwägungen der Sorte. Gegenprobe, nicht Teil der Rate: Es sind andere Kürbisse.';
grant select on v_lauf_vergleich to authenticated;

-- =====================================================================
-- 8. Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 111 $$;
