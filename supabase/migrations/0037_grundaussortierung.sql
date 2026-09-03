-- =====================================================================
-- 0037 — Der Palox ist ein Kompost-Behälter, und zu Kleine gehen an die Tiere
--
-- Zwei Rückmeldungen des Betriebs vom 2. September, beide ändern die
-- Rechnung, nicht nur die Maske.
--
-- ---------- 1. Nicht alles im Palox ist faul ------------------------------
-- Darin landen auch Erde, Blätter und optisch Ausgeschiedenes: Hagelnarben,
-- falsch geschnittene Stiele. Das kommt so vom Feld und wäre am ersten
-- Lagertag genauso da wie am hundertsten. Bisher las das Modell den ganzen
-- Inhalt als zeitabhängigen Verderb und passte die Kurve daran an.
--
-- Was ein zeitunabhängiger Sockel mit der Kurve macht, sagt die Simulation
-- (25 Saisons, 50 % im Lager, 2 % Sockel, Modell ohne Sockel):
--
--   Schimmel/Fäulnis   Verzerrung +40 %   Überdeckung 0–8 %
--
-- Der Sockel sitzt bei kurzen Lagerdauern, wo die Kurve flach ist — dort
-- hebt er den gemessenen Anteil relativ am stärksten. Die Anpassung macht
-- daraus eine flachere Kurve mit höherem Fuss, und die Hochrechnung auf lange
-- Lagerdauern trägt beides mit.
--
-- Der gemessene Anteil ist nicht F(t), sondern
--
--   Anteil(t) = a₀ + (1 − a₀) · F(t)
--
-- mit a₀ als Grundaussortierung. a₀ ist aus den Daten schätzbar, sobald
-- Messungen über verschieden lange Lagerdauern vorliegen: bei kurzer Lagerdauer
-- geht F gegen null, der beobachtete Anteil also gegen a₀.
--
-- Geschätzt wird a₀ über ein Gitter (0 bis 10 % in Schritten von 0.25 %): Für
-- jeden Kandidaten werden die Verarbeitungs-Punkte um a₀ bereinigt, die
-- Weibull-Gerade angepasst und der gewichtete Fehler im Anteilsraum über
-- *alle* Punkte gebildet — auch die, die nach der Bereinigung unter null
-- fallen und aus der Log-Anpassung herausfallen. Das einfachere Modell
-- gewinnt: kein Sockel, solange das Modell ohne Sockel nicht nach einem
-- F-Test nachweisbar schlechter passt als das beste mit Sockel; erst dann der
-- kleinste Sockel, der höchstens 1 % schlechter ist als der beste. Warum so
-- streng, steht gemessen bei der Schwelle unten.
--
-- Lagerkontrollen tragen keinen Sockel: Wer eine Palette aufmacht, zählt
-- Faules, keine Erde. Sie liefern F(t) direkt. Die Waschen-Punkte tragen ihn:
-- 1 − f₂ = (1 − a₀)(1 − F(t₂)), dieselbe Form — beim Waschen wird nichts
-- Zeitunabhängiges mehr aussortiert, das ist beim Sortieren passiert.
--
-- Im Dashboard ist die Grundaussortierung ein eigener Strom in einem eigenen
-- Buch („feld"): physisch weg, aber kein Lagerverlust. Der Betrieb hat
-- ausdrücklich gesagt, ihn interessiert, was *während der Lagerung* passiert.
--
-- ---------- 2. Zu Kleine gehen an die Tiere ------------------------------
-- Damit sind sie kein physischer Verlust, sondern ein anderer Kanal — wie die
-- zu Grossen. Sie wandern aus Buch A (Verlust) nach Buch B (anderer Kanal /
-- Marge). Das verschiebt einen ganzen Balken im Ranking; die Hauptursache
-- wird nur noch zwischen Verdunstung und Schimmel entschieden.
--
-- Die Massenkaskade ist damit:
--
--   Eingang ─Verdunstung→ M1 ─Sockel a₀→ ─Schimmel F→ M2 ─klein/gross→ verkaufsfähig
--
--   G = M1·a₀              (feld:    nicht lagerbedingt)
--   S = M1·(1−a₀)·F        (verlust: Schimmel/Fäulnis)
--   M2 = M1·(1−a₀)·(1−F)
--   K = M2·a_klein         (marge:   zu klein, Tierfutter)
--   N = M2·a_gross         (marge:   zu gross, anderer Kanal)
--
-- Der Fehler von a₀ kommt aus dem Profil: alle Gitterwerte, deren Fehler
-- nach einem F-Test mit einem Freiheitsgrad nicht schlechter sind als der
-- beste. Er geht als globaler Parameter in die Fortpflanzung ein (∂G/∂a₀ =
-- M1, ∂S/∂a₀ = −M1·F, …), ohne Kovarianz zu λ und k — eine bewusste
-- Vereinfachung, in ENTSCHEIDUNGEN.md vermerkt.
-- =====================================================================

-- ---------- Das Verderbsmodell mit Sockel ---------------------------------
-- Das Gitter macht das Modell rund vierzigmal so teuer wie bisher. Und es wird
-- an vielen Stellen gelesen — schimmelanteil() je Charge in der Massenbilanz,
-- dreimal je Zeile in der Kurvenanzeige. Beim Lasttest kostete das 73 Sekunden
-- (Regel aus 0015: was in einer Funktion steckt, sieht billig aus und ist es
-- nicht). Deshalb wird das Modell einmal gerechnet und gespeichert:
-- v_schimmel_modell_rechnen rechnet, mv_schimmel_modell hält das Ergebnis,
-- v_schimmel_modell zeigt darauf — für alle Leser derselbe Name wie bisher.
drop view if exists v_schimmel_modell cascade;
drop materialized view if exists mv_schimmel_modell cascade;
drop view if exists v_schimmel_modell_rechnen cascade;

create view v_schimmel_modell_rechnen with (security_invoker = true) as
with roh as (
  select b.charge_nr, b.lagertage::numeric as t, b.anteil::numeric as f,
         b.basis_jetzt_kg::numeric as w,
         -- Verarbeitungs-Punkte enthalten den Sockel, Lagerkontrollen nicht.
         (b.quelle = 'verarbeitung') as mit_sockel
    from mv_schimmel_punkte b
   where b.plausibel and b.anteil > 0 and b.anteil < 1 and b.lagertage > 0
     and b.quelle in ('verarbeitung', 'lager')
), chargen as (
  select count(distinct charge_nr)::int as c from roh
), gitter as (
  select (i * 0.0025)::numeric as a0 from generate_series(0, 40) i
), kand as (
  select g.a0, r.charge_nr, r.t, r.f, r.w, r.mit_sockel, ln(r.t) as x,
         case when r.mit_sockel then (r.f - g.a0) / (1 - g.a0) else r.f end as fs
    from gitter g cross join roh r
), fit as (
  select a0, count(*)::int as n, count(distinct charge_nr)::int as c_chargen,
         sum(w) as sw, sum(w * x) as swx, sum(w * y) as swy,
         sum(w * x * x) as swxx, sum(w * x * y) as swxy
    from (select a0, charge_nr, w, x, ln(-ln(1 - fs)) as y
            from kand where fs > 0 and fs < 1) q
   group by a0
), param as (
  select f.*,
         case when f.sw * f.swxx - f.swx * f.swx <> 0
              then (f.sw * f.swxy - f.swx * f.swy) / (f.sw * f.swxx - f.swx * f.swx) end as k
    from fit f
), param2 as (
  select p.*, case when p.k is not null then (p.swy - p.k * p.swx) / p.sw end as ln_lambda
    from param p
), smear as (
  select p.a0,
         sum(k.w * exp(ln(-ln(1 - k.fs)) - (p.ln_lambda + p.k * k.x))) / nullif(sum(k.w), 0) as s
    from param2 p join kand k on k.a0 = p.a0
   where k.fs > 0 and k.fs < 1 and p.k is not null
   group by p.a0
), guete as (
  -- Der Fehler im Anteilsraum, über alle Punkte — damit Kandidaten mit
  -- verschieden vielen anpassbaren Punkten vergleichbar bleiben.
  select p.a0, p.n, p.c_chargen, p.k, p.ln_lambda, s.s as smearing,
         sum(k.w * power(k.f
             - (case when k.mit_sockel then p.a0 else 0 end
                + (1 - case when k.mit_sockel then p.a0 else 0 end)
                  * (1 - exp(-exp(least(greatest(
                        p.ln_lambda + ln(greatest(s.s, 0.01)) + p.k * k.x, -40), 3))))), 2)) as sse
    from param2 p
    join smear s on s.a0 = p.a0
    join kand k on k.a0 = p.a0
   where p.k is not null and p.k > 0 and p.n >= 3
   group by p.a0, p.n, p.c_chargen, p.k, p.ln_lambda, s.s
), schwelle as (
  -- Ab wann ist ein Sockel belegt? Wenn das Modell ohne Sockel nach dem
  -- F-Test (1 Freiheitsgrad, Freiheitsgrade nach Chargen — Messungen aus
  -- derselben Charge sind keine unabhängigen Ziehungen) nachweisbar
  -- schlechter passt als das beste mit Sockel. Sonst gilt: kein Sockel.
  --
  -- Der Grund für die Strenge ist gemessen: Wird Schlechtes zuerst
  -- verarbeitet, sehen die frühen Messungen genauso aus wie ein Sockel —
  -- hoch bei kurzer Lagerdauer. Ein Sockel, der bei jeder kleinen
  -- Verbesserung zugreift, erfand dort 3–4 t Grundaussortierung aus dem
  -- Nichts und drückte den Schimmel um 13 % (Saisonende, Selektion). Erst
  -- ein belegter Sockel darf die Kurve verschieben.
  --
  -- Die Kehrseite ist ebenfalls gemessen (je 25 Saisons, 12 Wägungen,
  -- Verhältnis Fehler ohne Sockel / bester Fehler, Median und Quartile):
  --
  --   echter Sockel 2 %, Saisonmitte     1.58  (1.49–1.68)   gesetzt in 52 %
  --   echter Sockel 2 %, Saisonende      1.36  (1.31–1.44)   gesetzt in  4 %
  --   kein Sockel, Selektion, Saisonende 1.32  (1.25–1.48)   gesetzt in 12 %
  --   Schwelle bei 12 Chargen            1.57
  --
  -- Ein echter Sockel am Saisonende und eine Selektion ohne Sockel sehen
  -- im Fehler gleich aus. Keine Schwelle trennt die beiden; sie verschiebt
  -- nur, in welcher Lage die Zahl danebenliegt. Gewählt ist die Seite, die
  -- nichts erfindet: Wo der Sockel nicht belegt ist, bleibt er 0, und der
  -- Bereich sagt, wie gross er sein könnte. Trennen können das nur
  -- Lagerkontrollen (sie tragen keinen Sockel) oder eine direkte Messung
  -- beim Leeren des Palox — beides steht in FRAGEN.md.
  select 1 + power(t_quantil_95(greatest(c.c - 3, 1)), 2) / greatest(c.c - 3, 1) as faktor
    from chargen c
), wahl as (
  -- Das einfachere Modell gewinnt: kein Sockel, solange er nicht belegt ist;
  -- sonst der kleinste Sockel, der höchstens 1 % schlechter ist als der beste.
  select g.* from guete g
   where g.sse <= (select min(sse) from guete) * 1.01
     and (select sse from guete where a0 = 0) > (select min(sse) from guete) * (select faktor from schwelle)
   order by g.a0 limit 1
), gewaehlt as (
  select coalesce((select a0 from wahl), 0::numeric) as a0,
         coalesce((select sse from wahl), (select sse from guete where a0 = 0)) as sse,
         coalesce((select n from wahl), (select n from guete where a0 = 0)) as n_wahl
), grenzen as (
  -- Profil-Bereich: alle Sockel, die nach dem F-Test nicht nachweisbar
  -- schlechter sind als der gewählte. Mit n statt Chargen als Freiheitsgrade
  -- war der Bereich zu eng (Überdeckung 72 % statt 95 %).
  select coalesce(min(g.a0), w.a0) as a0_unten, coalesce(max(g.a0), w.a0) as a0_oben
    from gewaehlt w
    left join guete g on g.sse <= w.sse * (select faktor from schwelle)
   group by w.a0
), punkte as (
  select k.charge_nr, k.x, ln(-ln(1 - k.fs)) as y, k.w, k.t
    from kand k, gewaehlt g
   where k.a0 = g.a0 and k.fs > 0 and k.fs < 1
), summen as (
  select count(*)::int as n, count(distinct charge_nr)::int as c_chargen,
         min(t) as t_min, max(t) as t_max,
         sum(w) as sw, sum(w * x) as swx, sum(w * y) as swy,
         sum(w * x * x) as swxx, sum(w * x * y) as swxy
    from punkte
), fit2 as (
  select s.*,
         case when s.sw * s.swxx - s.swx * s.swx <> 0
              then (s.sw * s.swxy - s.swx * s.swy) / (s.sw * s.swxx - s.swx * s.swx) end as k,
         s.swx / nullif(s.sw, 0) as x_mittel
    from summen s
), mit_achse as (
  select f.*, case when f.k is not null then (f.swy - f.k * f.swx) / f.sw end as ln_lambda
    from fit2 f
), rest as (
  select m.*,
         (select sum(p.w * power(p.x - m.x_mittel, 2)) from punkte p)              as sxx,
         (select sum(p.w * power(p.y - (m.ln_lambda + m.k * p.x), 2)) from punkte p) as sse,
         (select sum(p.w * exp(p.y - (m.ln_lambda + m.k * p.x))) / nullif(sum(p.w), 0)
            from punkte p)                                                        as smearing
    from mit_achse m
), gruppen as (
  select r.*, g.saa, g.skk, g.sak
    from rest r
    cross join lateral (
      select sum(power(c.ga, 2)) as saa, sum(power(c.gk, 2)) as skk,
             sum(c.ga * c.gk)    as sak
        from (select p.charge_nr,
                     sum(p.w * (p.y - (r.ln_lambda + r.k * p.x)))                      as ga,
                     sum(p.w * (p.x - r.x_mittel) * (p.y - (r.ln_lambda + r.k * p.x))) as gk
                from punkte p group by p.charge_nr) c
    ) g
)
select n, c_chargen, t_min, t_max, k, ln_lambda, exp(ln_lambda) as lambda,
       x_mittel, sxx, smearing,
       ln_lambda + ln(greatest(smearing, 0.01))                      as ln_lambda_korrigiert,
       case when n > 2 then sse / (n - 2) * n / nullif(sw, 0) end    as sigma2,
       case when c_chargen > 1
            then saa / power(sw, 2) * c_chargen::numeric / (c_chargen - 1) end  as var_achse,
       case when c_chargen > 1 and sxx <> 0
            then skk / power(sxx, 2) * c_chargen::numeric / (c_chargen - 1) end as var_k,
       case when c_chargen > 1 and sxx <> 0
            then sak / (sw * sxx) * c_chargen::numeric / (c_chargen - 1) end    as kov_achse_k,
       t_quantil_95(c_chargen - 1)                                              as t_faktor,
       (n >= 3 and c_chargen >= 3 and k is not null and k > 0
        and t_max > t_min * 1.5)                                                as brauchbar,
       -- Selektionsversatz, an den bereinigten Punkten
       ( select case when count(*) filter (where p.mit_sockel = false) >= 5
                     then greatest(
                       abs(sum(p.w * p.e) filter (where not p.mit_sockel)
                             / nullif(sum(p.w) filter (where not p.mit_sockel), 0)
                         - sum(p.w * p.e) filter (where p.mit_sockel)
                             / nullif(sum(p.w) filter (where p.mit_sockel), 0))
                       - 1.96 * stddev_samp(p.e) filter (where not p.mit_sockel)
                                / sqrt(count(*) filter (where not p.mit_sockel)), 0)::numeric
                end
           from (select k.mit_sockel, k.w,
                        ln(-ln(1 - k.fs)) - (gruppen.ln_lambda + gruppen.k * k.x) as e
                   from kand k, gewaehlt g
                  where k.a0 = g.a0 and k.fs > 0 and k.fs < 1) p) as selektions_versatz,
       -- Der Sockel und sein Bereich
       (select a0 from gewaehlt)                                          as sockel,
       (select a0_unten from grenzen)                                    as sockel_unten,
       (select a0_oben from grenzen)                                     as sockel_oben,
       -- Wie sehr verlangen die Daten einen Sockel? Fehler ohne Sockel geteilt
       -- durch den besten Fehler mit Sockel. 1 = gar nicht.
       ((select sse from guete where a0 = 0) / nullif((select min(sse) from guete), 0))::numeric(10,3)
                                                                          as sockel_nachweis,
       (select faktor from schwelle)::numeric(10,3)                       as sockel_schwelle,
       -- Varianz aus dem Profil-Bereich, für die Fehlerfortpflanzung
       power(((select a0_oben from grenzen) - (select a0_unten from grenzen))
             / 2.0 / nullif(t_quantil_95(c_chargen - 1), 0), 2)             as sockel_var
  from gruppen;

create materialized view mv_schimmel_modell as
select * from v_schimmel_modell_rechnen;

create view v_schimmel_modell with (security_invoker = true) as
select * from mv_schimmel_modell;

comment on view v_schimmel_modell is
  'Verderbsmodell F(t) = 1 − exp(−λ·S·t^k), chargen-robust gefehlert, mit '
  'Grundaussortierung a₀ (sockel): Verarbeitungs-Punkte sind a₀ + (1−a₀)·F(t), '
  'Lagerkontrollen F(t). sockel_unten/oben ist der Profil-Bereich; '
  'selektions_versatz der Unterschied zwischen zufällig gegriffener und '
  'nach Aussehen ausgewählter Ware. Gespeichert; auswertung_aktualisieren() '
  'rechnet neu.';

grant select on mv_schimmel_modell, v_schimmel_modell_rechnen to authenticated;

-- Neu rechnen: das Modell liest die Punkte, die Kaskade das Modell.
create or replace function auswertung_aktualisieren()
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v_start timestamptz := clock_timestamp();
begin
  refresh materialized view mv_sortier_lauf_masse;
  refresh materialized view mv_sortier_eingang;
  refresh materialized view mv_auftrag_masse;
  refresh materialized view mv_schimmel_punkte;
  refresh materialized view mv_schimmel_modell;
  refresh materialized view mv_kaskade;
  refresh materialized view mv_kaliber_verteilung;

  update auswertung_stand
     set berechnet_ts = now(),
         dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
   where id = 1;

  return now();
end $$;
revoke execute on function auswertung_aktualisieren() from public;
grant execute on function auswertung_aktualisieren() to authenticated;

-- Der Sockel als Zahl, für Ansichten, die ihn brauchen.
create or replace function sockel_anteil()
returns numeric language sql stable as $$
  select coalesce((select case when brauchbar then sockel else 0 end from public.v_schimmel_modell), 0);
$$;
revoke execute on function sockel_anteil() from public;
grant execute on function sockel_anteil() to authenticated;

-- schimmelanteil() liefert F(t) — reinen Verderb, ohne Sockel.
create or replace function schimmelanteil(p_lagertage numeric, p_szenario text default 'mittel')
returns numeric language sql stable as $$
  with m as (select * from public.v_schimmel_modell),
  u as (select m.*, ln(greatest(p_lagertage, 1)) - m.x_mittel as u from m)
  select coalesce(
    (select least(greatest(1 - exp(-exp(least(greatest(
       u.ln_lambda_korrigiert + u.k * ln(greatest(p_lagertage, 1))
       + case p_szenario when 'unten' then -1 when 'oben' then 1 else 0 end
         * u.t_faktor * sqrt(greatest(
             u.var_achse + power(u.u, 2) * u.var_k + 2 * u.u * u.kov_achse_k, 0))
       , -40), 3))), 0), 1)
       from u where u.brauchbar and u.var_achse is not null),
    (select least(greatest(coalesce(
       case p_szenario when 'unten' then coalesce(k.unten, k.anteil_mono)
                       when 'oben'  then coalesce(k.oben,  k.anteil_mono)
                       else k.anteil_mono end, 0), 0), 1)
       from public.v_schimmel_kurve k
      where k.von <= p_lagertage and k.n > 0
      order by k.von desc limit 1),
    0)::numeric;
$$;

-- ---------- Die abhängigen Ansichten, die am Modell hingen ---------------
create or replace view v_selektionsverdacht with (security_invoker = true) as
with rest as (
  select p.quelle, p.basis_jetzt_kg::numeric as w,
         ln(-ln(1 - x.fs)) - (m.ln_lambda + m.k * ln(p.lagertage::numeric)) as e
    from mv_schimmel_punkte p cross join v_schimmel_modell m
    cross join lateral (
      select case when p.quelle = 'verarbeitung'
                  then (p.anteil::numeric - m.sockel) / (1 - m.sockel)
                  else p.anteil::numeric end as fs) x
   where m.brauchbar and p.plausibel
     and x.fs > 0 and x.fs < 1 and p.lagertage > 0
), je_quelle as (
  select quelle, count(*)::int as n, sum(w * e) / nullif(sum(w), 0) as mittel
    from rest group by quelle
)
select (select n from je_quelle where quelle = 'verarbeitung')      as n_verarbeitung,
       (select n from je_quelle where quelle = 'lager')             as n_lager,
       (select mittel from je_quelle where quelle = 'verarbeitung') as rest_verarbeitung,
       (select mittel from je_quelle where quelle = 'lager')        as rest_lager,
       (select mittel from je_quelle where quelle = 'lager')
         - (select mittel from je_quelle where quelle = 'verarbeitung') as unterschied,
       case
         when (select n from je_quelle where quelle = 'lager') is null
           then 'keine Lagerkontrollen — Selektion nicht prüfbar'
         when (select n from je_quelle where quelle = 'lager') < 5
           then 'zu wenige Lagerkontrollen für eine Aussage'
         when abs((select mittel from je_quelle where quelle = 'lager')
                  - (select mittel from je_quelle where quelle = 'verarbeitung')) > 0.2
           then 'verarbeitete und zufällig gegriffene Paletten sagen Verschiedenes — '
                || 'es wird nach Aussehen ausgewählt. Bei gleichem Alter sind die '
                || 'verarbeiteten fauler, dafür bleibt am Ende die robustere Ware '
                || 'liegen: der Verlauf wird zu flach und die Hochrechnung auf lange '
                || 'Lagerdauern zu niedrig. Mehr Lagerkontrollen beheben das.'
         else 'beide Quellen sagen dasselbe — kein Hinweis auf Selektion'
       end                                                          as befund;

create or replace view v_schlag_effekt with (security_invoker = true) as
with punkte as (
  select p.schlag, p.charge_nr, p.basis_jetzt_kg::numeric as w,
         ln(-ln(1 - x.fs)) - (m.ln_lambda + m.k * ln(p.lagertage::numeric)) as e
    from mv_schimmel_punkte p cross join v_schimmel_modell m
    cross join lateral (
      select case when p.quelle = 'verarbeitung'
                  then (p.anteil::numeric - m.sockel) / (1 - m.sockel)
                  else p.anteil::numeric end as fs) x
   where m.brauchbar and p.plausibel and x.fs > 0 and x.fs < 1 and p.lagertage > 0
), je_schlag as (
  select schlag, count(*)::int as n, count(distinct charge_nr)::int as c,
         sum(w) as sw, sum(w * e) / nullif(sum(w), 0) as mittel
    from punkte group by schlag
), streuung as (
  select count(*)::int                                                  as n_schlaege,
         sum(sw * power(mittel, 2)) / nullif(sum(sw), 0)                as beobachtet,
         (select sum(w * power(e, 2)) / nullif(sum(w), 0) from punkte)
           / nullif(avg(n), 0)                                          as erwartet_durch_zufall
    from je_schlag where n >= 2
)
select n_schlaege, beobachtet, erwartet_durch_zufall,
       greatest(beobachtet - erwartet_durch_zufall, 0)                  as tau2_schlag,
       case
         when n_schlaege is null or n_schlaege < 3
           then 'zu wenige Schläge mit Messungen'
         when greatest(beobachtet - erwartet_durch_zufall, 0) <= 0
           then 'die Unterschiede zwischen Schlägen sind nicht grösser als '
                || 'Stichprobenrauschen — eine eigene Schlag-Schätzung brächte nichts'
         when beobachtet > 2 * erwartet_durch_zufall
           then 'die Schläge unterscheiden sich deutlich — eine eigene '
                || 'Schlag-Stratifizierung wäre begründet'
         else 'schwacher Hinweis auf Schlag-Unterschiede, für eine eigene '
              || 'Schätzung reicht es noch nicht'
       end                                                              as befund
  from streuung;

create or replace view v_schimmel_kurve_anzeige with (security_invoker = true) as
select k.von, k.bis,
       case when k.bis > 9999 then k.von || '+ Tage'
            else k.von || '–' || k.bis || ' Tage' end       as altersklasse,
       k.n                                                  as messungen,
       (k.anteil)::numeric(10,4)                            as gemessen,
       (schimmelanteil((k.von + least(k.bis, k.von + 60)) / 2.0))::numeric(10,4) as verwendet,
       (schimmelanteil((k.von + least(k.bis, k.von + 60)) / 2.0, 'unten'))::numeric(10,4) as unten,
       (schimmelanteil((k.von + least(k.bis, k.von + 60)) / 2.0, 'oben'))::numeric(10,4)  as oben,
       case when not (select brauchbar from v_schimmel_modell)
                 then 'Modell noch nicht anpassbar — es gilt die Treppenfunktion'
            when k.von > (select t_max from v_schimmel_modell)
                 then 'über die längste gemessene Lagerdauer hinaus — hochgerechnet, '
                      || 'daher der breitere Bereich'
            when k.n = 0 then 'keine eigene Messung — aus dem Verlauf interpoliert'
            else 'durch Messungen dieser Altersklasse gestützt' end
       || case when (select sockel from v_schimmel_modell) > 0
               then format('; „gemessen" enthält den Sockel von %s %% (Erde, Hagel, Schnitt), '
                           || '„verwendet" ist der reine Verderb',
                           round((select sockel from v_schimmel_modell) * 100, 2))
               else '' end                                   as erlaeuterung
  from v_schimmel_kurve k
 order by k.von;

-- v_naechste_charge hing per cascade am Modell; sie rechnet mit reinem F(t)
-- und braucht keine Änderung — nur den Wiederaufbau.
create or replace view v_naechste_charge with (security_invoker = true) as
with modell as materialized (
  select * from v_schimmel_modell
),
bestand as (
  select b.charge_nr, b.sorte, b.schlag, b.lager_kg,
         greatest(b.alter_lager_heute, 0)                      as alter_tage,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05)      as r
    from v_hochrechnung_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
   where b.lager_kg > 0
),
mit_f as (
  select b.*,
         b.lager_kg * power(1 - b.r, greatest(b.alter_tage, 0)) as masse_jetzt_kg,
         case when m.brauchbar then least(greatest(
           1 - exp(-exp(least(greatest(
             m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage, 1))
           , -40), 3))), 0), 0.99) end                          as f_jetzt,
         case when m.brauchbar then least(greatest(
           1 - exp(-exp(least(greatest(
             m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage + 14, 1))
           , -40), 3))), 0), 0.99) end                          as f_dann,
         (m.brauchbar and b.alter_tage > m.t_max)               as hochgerechnet,
         m.brauchbar                                            as modell_gilt
    from bestand b cross join modell m
)
select charge_nr, sorte, schlag,
       lager_kg::numeric(14,2),
       round(alter_tage)::int                                   as alter_tage,
       masse_jetzt_kg::numeric(14,2),
       (masse_jetzt_kg * (1 - power(1 - r, 14)))::numeric(12,1) as verdunstung_14_kg,
       (case when modell_gilt
             then masse_jetzt_kg * (f_dann - f_jetzt) / nullif(1 - f_jetzt, 0)
             else null end)::numeric(12,1)                      as schimmel_14_kg,
       (masse_jetzt_kg * (1 - power(1 - r, 14))
        + coalesce(masse_jetzt_kg * (f_dann - f_jetzt) / nullif(1 - f_jetzt, 0), 0)
       )::numeric(12,1)                                         as verlust_14_kg,
       hochgerechnet, modell_gilt
  from mit_f
 order by verlust_14_kg desc nulls last;

-- ---------- Die Kaskade mit Sockel, und zu klein im anderen Buch -----------
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
         (m.brauchbar or (select count(*) from kurve) > 0)              as f_bekannt,
         -- Der Sockel: nur mit tragfähigem Modell geschätzt; sonst 0 und
         -- unbekannt (die Treppe enthält ihn dann ununterscheidbar).
         case when m.brauchbar then coalesce(m.sockel, 0) else 0 end    as a0,
         m.brauchbar                                                    as a0_bekannt,
         case when m.brauchbar then coalesce(m.sockel_var, 0) else 0 end as a0_var
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
       k.m0, k.m1, (k.m1 * (1 - k.a0) * (1 - k.f)) as m2,
       k.r, k.f, k.a0, k.a_klein_n, k.a_gross_n,
       k.u, k.d_m1_r, k.d_f_eta, k.modell_gilt, k.f_extrapoliert,
       k.r_n, k.r_basis, k.klein_n, k.klein_basis, k.gross_n, k.gross_basis, k.f_n,
       k.r_bekannt, k.f_bekannt, k.a_klein_bekannt, k.a_gross_bekannt, k.a0_bekannt, k.a0_var,
       (k.m0 - k.m1)                                                     as verdunstung_kg,
       (k.m1 * k.a0)                                                     as sockel_kg,
       (k.m1 * (1 - k.a0) * k.f)                                         as schimmel_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * k.a_klein_n)                     as klein_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * k.a_gross_n)                     as nebenkanal_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * (1 - k.a_klein_n - k.a_gross_n)) as verkaufsfaehig_kg
  from kaskade k;

create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, portion);
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);

create or replace view v_kaskade with (security_invoker = true) as
select * from mv_kaskade;

create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg, k.f_extrapoliert, k.u,
       s.strom, s.buch,
       (case when s.bekannt then s.kg end)::numeric(14,2)  as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       (case when s.bekannt then s.koeffizient end)::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel,
       s.d_r                        as d_r,
       s.d_f * k.d_f_eta            as d_eta,
       s.d_a                        as d_a,
       s.d_a0                       as d_a0,
       s.koeff_art                  as koeff_art,
       s.bekannt                    as koeff_bekannt
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung', 'verlust', k.m0 - k.m1, k.m0, k.r, k.r_n, k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen',
     -k.d_m1_r, 0::numeric, 0::numeric, 0::numeric, null::text, k.r_bekannt),
    ('Nicht lagerbedingt', 'feld', k.m1 * k.a0, k.m1, k.a0, k.f_n,
     'Grundaussortierung a₀ aus dem Verderbsmodell: was bei Lagerdauer null schon im Palox läge',
     'Masse nach Verdunstung × a₀ — Erde, Hagelnarben, Schnittfehler; kein Lagerverlust',
     k.d_m1_r * k.a0, 0::numeric, 0::numeric, k.m1, null::text, k.a0_bekannt),
    ('Schimmel/Fäulnis', 'verlust', k.m1 * (1 - k.a0) * k.f, k.m1 * (1 - k.a0), k.f, k.f_n,
     'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen',
     'Masse nach Verdunstung und Sockel × Schimmelanteil bei dieser Lagerdauer',
     k.d_m1_r * (1 - k.a0) * k.f, k.m1 * (1 - k.a0), 0::numeric, -k.m1 * k.f, null::text, k.f_bekannt),
    ('Zu klein (Tierfutter)', 'marge', k.m1 * (1 - k.a0) * (1 - k.f) * k.a_klein_n, k.m2,
     k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust',
     k.d_m1_r * (1 - k.a0) * (1 - k.f) * k.a_klein_n, -k.m1 * (1 - k.a0) * k.a_klein_n, k.m2,
     -k.m1 * (1 - k.f) * k.a_klein_n, 'ausschuss', k.a_klein_bekannt),
    ('Nebenkanal zu gross', 'marge', k.m1 * (1 - k.a0) * (1 - k.f) * k.a_gross_n, k.m2,
     k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal',
     k.d_m1_r * (1 - k.a0) * (1 - k.f) * k.a_gross_n, -k.m1 * (1 - k.a0) * k.a_gross_n, k.m2,
     -k.m1 * (1 - k.f) * k.a_gross_n, 'nebenkanal', k.a_gross_bekannt),
    ('Verkaufsfähig', 'bilanz', k.verkaufsfaehig_kg, k.m2, null::numeric, null::int,
     null::text, 'Rest der Kaskade', 0::numeric, 0::numeric, 0::numeric, 0::numeric, null::text, true)
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel,
         d_r, d_f, d_a, d_a0, koeff_art, bekannt);

comment on view v_hochrechnung is
  'Ein Strom je Charge und Portion. Bücher: verlust (Lagerverlust: Verdunstung, '
  'Schimmel), feld (nicht lagerbedingt: Grundaussortierung), marge (anderer '
  'Kanal: zu klein, zu gross), bilanz (verkaufsfähig). kg ist NULL, wenn der '
  'Koeffizient dahinter nie gemessen wurde.';

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
   where buch in ('verlust', 'marge', 'feld')
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
         sum(z.d_eta * z.u) as g_steigung,
         sum(z.d_a0)        as g_a0
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
  -- Verderbsmodell (2×2) und Sockel (global, ohne Kovarianz zum Modell)
  select m.strom, m.buch,
         power(m.g_achse, 2) * coalesce(sm.var_achse, 0)
         + 2 * m.g_achse * m.g_steigung * coalesce(sm.kov_achse_k, 0)
         + power(m.g_steigung, 2) * coalesce(sm.var_k, 0)
         + power(m.g_a0, 2) * case when sm.brauchbar then coalesce(sm.sockel_var, 0) else 0 end
                                                                as varianz,
         coalesce(sm.c_chargen - 1, 1)                          as df
    from je_strom_modell m cross join v_schimmel_modell sm
),
summe as (
  select z.strom, z.buch,
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
  'Alle Ströme mit fortgepflanztem 95-%-Bereich. buch = verlust ist der '
  'Lagerverlust (Verdunstung, Schimmel), feld die Grundaussortierung, marge '
  'der andere Kanal (zu klein, zu gross). kg ist NULL, wenn der Koeffizient '
  'nie gemessen wurde.';

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
       case r.strom
         when 'Nebenkanal zu gross' then 'Ware über 2000 g geht in einen anderen Verkaufskanal'
         when 'Zu klein (Tierfutter)' then 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'
         else '' end::text                                       as erlaeuterung
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
  select charge_nr, sum(m2) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade group by charge_nr
), modell as materialized (
  -- Was am Band ankommt: nach Verdunstung, nach Sockel, nach Verderb.
  select b.charge_nr,
         b.am_band_kg
         * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05), coalesce(b.alter_band, 0))
         * (1 - sockel_anteil())
         * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
         * q.anteil_mit_csv                                        as am_band_modell_kg
    from v_hochrechnung_basis b
    left join csv_anteil q on q.charge_nr = b.charge_nr
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       m.am_band_modell_kg::numeric(14,2)                    as modell_am_band_kg,
       c.gemessen_kg                                         as csv_gemessen_kg,
       (c.gemessen_kg - m.am_band_modell_kg)::numeric(14,2)  as abweichung_kg,
       case when m.am_band_modell_kg > 0
            then ((c.gemessen_kg - m.am_band_modell_kg) / m.am_band_modell_kg)::numeric(10,4)
       end                                                   as abweichung_anteil,
       r.restbestand_kg::numeric(14,2)                       as restbestand_kg,
       b.alter_band
  from v_hochrechnung_basis b
  left join modell m     on m.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr
  left join rest r       on r.charge_nr = b.charge_nr;

comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. '
  'Das Modell zieht Verdunstung, Sockel und Verderb bis dahin ab. '
  'restbestand_kg ist die Masse, die nach Verdunstung und Verderb noch im '
  'Haus liegt.';

create view v_saisonbilanz with (security_invoker = true) as
with eingang as (
  select sum(eingang_kg)          as kg,
         sum(lager_kg)            as im_lager_kg,
         sum(wartet_kg)           as wartet_kg
    from v_hochrechnung_basis
), verlust as (
  -- Physisch weg ist beides: der Lagerverlust und die Grundaussortierung.
  select sum(kg)                                          as kg,
         sum(kg_unten)                                    as kg_unten,
         sum(kg_oben)                                     as kg_oben,
         sum(kg) filter (where buch = 'verlust')           as lager_kg,
         sum(kg) filter (where buch = 'feld')              as feld_kg,
         bool_and(kg is not null) filter (where buch = 'verlust') as bekannt
    from v_verlust_ranking where buch in ('verlust', 'feld')
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
       end                                                 as befund,
       v.lager_kg::numeric(14,2)                           as lagerverlust_kg,
       v.feld_kg::numeric(14,2)                            as feld_kg
  from eingang e cross join verlust v cross join rest r cross join ausgang a;

comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand. '
  'verlust_modell_kg ist alles, was physisch weg ist (Lagerverlust plus '
  'Grundaussortierung); lagerverlust_kg und feld_kg zerlegen es. Zu klein '
  'und zu gross sind kein Verlust: sie verlassen den Betrieb als Ausgang.';

grant select on v_schimmel_modell, v_selektionsverdacht, v_schlag_effekt,
               v_schimmel_kurve_anzeige, v_naechste_charge, v_kaskade,
               v_hochrechnung, v_verlust_ranking, v_marge_buch, v_massenbilanz,
               v_saisonbilanz to authenticated;
grant execute on function verlust_ranking(text, text, numeric),
                          schimmelanteil(numeric, text) to authenticated;
