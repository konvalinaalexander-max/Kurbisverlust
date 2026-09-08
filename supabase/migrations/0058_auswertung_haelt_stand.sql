-- =====================================================================
-- 0058 — Eine einzelne unmögliche Zahl darf die Auswertung nicht sprengen
-- Kürbis-Verlust-Tracking
--
-- WAS PASSIERT IST
--
-- Nach 0056 und 0057 stand im Überblick weiterhin „numeric field
-- overflow", jetzt mit Namen: v_hochrechnung. Die Diagnose auf der
-- Betriebsdatenbank zeigte: Stand 0057, Verdunstungsrate in Ordnung
-- (0.000470 … 0.000475), Auswertung rechnet durch — aber v_saisonbilanz
-- und v_marge_buch scheitern. Es sind also nicht mehr die Rohdaten,
-- sondern die Sichten, die daraus Hochrechnung, Bereiche und Bilanz
-- machen.
--
-- Der Grund ist ein Bauprinzip, das sich als falsch erwiesen hat: Diese
-- Sichten casten berechnete Grössen hart auf numeric(14,2),
-- numeric(12,6) oder numeric(10,4). Ein solcher Cast ist eine
-- *Behauptung* über den Wertebereich. Trifft sie nicht zu — weil eine
-- Messung fehlt, ein Nenner winzig ist oder eine Varianz aus wenigen
-- Punkten gross wird —, dann bricht die ganze Sicht ab. Nicht die eine
-- Zahl fehlt, sondern der ganze Bildschirm bleibt leer. Das ist die
-- schlechteste aller Ausfallarten: Der Betriebsleiter sieht nichts und
-- kann nichts tun.
--
-- Zwei Beispiele, beide realistisch:
--   · luecke_anteil = (Eingang − Verlust − Ausgang − …) / Eingang, hart
--     auf numeric(10,4) (also unter 10^6). Ist der Wareneingang noch
--     nicht eingelesen, der Warenausgang aber schon, wird das Verhältnis
--     beliebig gross — und die Bilanz bricht ab, statt zu sagen, dass
--     der Eingang fehlt.
--   · kg_unten/kg_oben = Wert ± t · Streuung. Die Streuung kommt aus
--     einer Varianz; bei wenigen Messpunkten kann sie sehr gross werden.
--     Der Mittelwert ist dann noch brauchbar, der Bereich nicht — aber
--     abbrechen darf deswegen nichts.
--
-- WAS SICH ÄNDERT
--
-- 1. `zahl(wert, stellen, grenze)` rundet wie bisher, gibt aber NULL
--    statt eines Fehlers, wenn der Wert ausserhalb dessen liegt, was die
--    Spalte tragen kann. NULL heisst im ganzen Projekt „unbekannt", und
--    genau das ist es: Die Zahl ist nicht ermittelbar. Die App zeigt
--    dafür „—", der Rest des Bildschirms steht.
-- 2. Jeder Koeffizient in der Hochrechnung ist ein *Anteil* und wird auf
--    0 … 1 geklammert, jede Masse auf ≥ 0. Das ist keine Notbremse,
--    sondern die Physik: Ein Anteil über 1 oder eine negative Masse gibt
--    es nicht. Bisher war nur der Sockel a₀ ungeklammert.
-- 3. Die Plausibilität meldet den Fall, der hinter dem häufigsten
--    Verhältnis-Ausreisser steckt: Es sind Lieferungen erfasst, aber
--    (fast) kein Wareneingang. Dann fehlt das Erntejournal, und die
--    Bilanz kann gar nicht aufgehen.
--
-- Die Spaltentypen bleiben unverändert; nichts muss neu gebaut werden.
-- =====================================================================

create or replace function zahl(p_wert numeric, p_stellen int default 2,
                                p_grenze numeric default 1e11)
returns numeric language sql immutable parallel safe set search_path = public
as $$
  select case when p_wert is not null and abs(p_wert) < p_grenze
              then round(p_wert, p_stellen) end
$$;
comment on function zahl(numeric, int, numeric) is
  'Rundet auf p_stellen und gibt NULL, wenn der Wert nicht in die Zielspalte '
  'passt (0058). Eine einzelne unmögliche Zahl macht damit eine Spalte '
  'unbekannt, statt die ganze Sicht abbrechen zu lassen.';
revoke all on function zahl(numeric, int, numeric) from public;
grant execute on function zahl(numeric, int, numeric) to anon, authenticated;

-- Manche Zwischenwerte sind Gleitkomma (Koeffizienten-Grenzen, Anteile).
-- Ohne diese Fassung müsste an jeder Aufrufstelle ein Cast stehen, und genau
-- der wird beim nächsten Umbau vergessen.
create or replace function zahl(p_wert double precision, p_stellen int default 2,
                                p_grenze numeric default 1e11)
returns numeric language sql immutable parallel safe set search_path = public
as $$ select zahl(p_wert::numeric, p_stellen, p_grenze) $$;
revoke all on function zahl(double precision, int, numeric) from public;
grant execute on function zahl(double precision, int, numeric) to anon, authenticated;

-- ---------- 1. Die Hochrechnung: Anteile sind Anteile ---------------------
create or replace view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage,
       k.eingang_kg, zahl(c.m0)::numeric(14,2) as portion_kg, k.f_extrapoliert, k.u,
       s.strom, s.buch,
       (case when s.bekannt then zahl(s.kg) end)::numeric(14,2)  as kg,
       zahl(s.basis_kg)::numeric(14,2)    as basis_kg,
       (case when s.bekannt then zahl(s.koeffizient, 6, 1e5) end)::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel,
       s.d_r                        as d_r,
       s.d_f * k.d_f_eta            as d_eta,
       s.d_a                        as d_a,
       s.d_a0                       as d_a0,
       s.koeff_art                  as koeff_art,
       s.bekannt                    as koeff_bekannt,
       k.kohorte
  from v_kaskade k
  -- 0058: Ein Koeffizient ist ein Anteil (0 … 1), eine Masse ist nie
  -- negativ. Bisher galt das für r, f, zu klein und zu gross, nicht aber
  -- für den Sockel a₀ und nicht für die Massen selbst.
  cross join lateral (
    select greatest(k.m0, 0)                    as m0,
           greatest(k.m1, 0)                    as m1,
           greatest(k.m2, 0)                    as m2,
           greatest(k.verkaufsfaehig_kg, 0)     as verkaufsfaehig_kg,
           least(greatest(k.r, 0), 1)           as r,
           least(greatest(k.f, 0), 1)           as f,
           least(greatest(k.a0, 0), 1)          as a0,
           least(greatest(k.a_klein_n, 0), 1)   as a_klein_n,
           least(greatest(k.a_gross_n, 0), 1)   as a_gross_n,
           least(greatest(k.a_fax, 0), 1)       as a_fax
  ) c
  cross join lateral (values
    ('Verdunstung', 'verlust', c.m0 - c.m1, c.m0, c.r, k.r_n, k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen',
     -k.d_m1_r, 0::numeric, 0::numeric, 0::numeric, null::text, k.r_bekannt),
    ('Nicht lagerbedingt', 'feld', c.m1 * c.a0, c.m1, c.a0, k.f_n,
     'Grundaussortierung a₀ aus dem Verderbsmodell: was bei Lagerdauer null schon im Palox läge',
     'Masse nach Verdunstung × a₀ — Erde, Hagelnarben, Schnittfehler; kein Lagerverlust',
     k.d_m1_r * c.a0, 0::numeric, 0::numeric, c.m1, null::text, k.a0_bekannt),
    ('Schimmel/Fäulnis', 'verlust', c.m1 * (1 - c.a0) * c.f, c.m1 * (1 - c.a0), c.f, k.f_n,
     'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen',
     'Masse nach Verdunstung und Sockel × Schimmelanteil bei dieser Lagerdauer',
     k.d_m1_r * (1 - c.a0) * c.f, c.m1 * (1 - c.a0), 0::numeric, -c.m1 * c.f, null::text, k.f_bekannt),
    ('Zu klein (Tierfutter)', 'marge', c.m1 * (1 - c.a0) * (1 - c.f) * c.a_klein_n, c.m2,
     c.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust',
     k.d_m1_r * (1 - c.a0) * (1 - c.f) * c.a_klein_n, -c.m1 * (1 - c.a0) * c.a_klein_n, c.m2,
     -c.m1 * (1 - c.f) * c.a_klein_n, 'ausschuss', k.a_klein_bekannt),
    ('Nebenkanal zu gross', 'marge', c.m1 * (1 - c.a0) * (1 - c.f) * c.a_gross_n, c.m2,
     c.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal',
     k.d_m1_r * (1 - c.a0) * (1 - c.f) * c.a_gross_n, -c.m1 * (1 - c.a0) * c.a_gross_n, c.m2,
     -c.m1 * (1 - c.f) * c.a_gross_n, 'nebenkanal', k.a_gross_bekannt),
    ('Faul beim Abpacken (Fax)', 'verlust',
     c.m1 * (1 - c.a0) * (1 - c.f) * (1 - c.a_klein_n - c.a_gross_n) * c.a_fax,
     c.m2 * (1 - c.a_klein_n - c.a_gross_n),
     c.a_fax, k.fax_n, k.fax_basis,
     'Verkaufsfähige Masse × Anteil Faules, das beim Etikettieren aussortiert wird — vom Waschen und Stehen, nicht von der Lagerdauer',
     k.d_m1_r * (1 - c.a0) * (1 - c.f) * (1 - c.a_klein_n - c.a_gross_n) * c.a_fax,
     -c.m1 * (1 - c.a0) * (1 - c.a_klein_n - c.a_gross_n) * c.a_fax,
     c.m2 * (1 - c.a_klein_n - c.a_gross_n),
     -c.m1 * (1 - c.f) * (1 - c.a_klein_n - c.a_gross_n) * c.a_fax,
     'fax', k.a_fax_bekannt),
    ('Verkaufsfähig', 'bilanz', c.verkaufsfaehig_kg, c.m2, null::numeric, null::int,
     null::text, 'Rest der Kaskade', 0::numeric, 0::numeric, 0::numeric, 0::numeric, null::text, true)
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel,
         d_r, d_f, d_a, d_a0, koeff_art, bekannt);
comment on view v_hochrechnung is
  'Ein Strom je Charge, Portion und (im Lager) Eingangstag. kg ist NULL, wenn '
  'der Koeffizient dahinter nie gemessen wurde — koeff_bekannt sagt es. Jeder '
  'Koeffizient ist ein Anteil (0 … 1), jede Masse ist nie negativ (0058).';
grant select on v_hochrechnung to authenticated;

-- ---------- 2. Die Bereiche: eine grosse Streuung bricht nichts ab --------
-- Der Mittelwert bleibt brauchbar, auch wenn der Bereich aus wenigen
-- Messpunkten sehr breit wird. Bisher riss der Bereich die ganze Sicht mit.
create or replace function verlust_ranking(
  p_sorte          text    default null,
  p_schlag         text    default null,
  p_min_lagertage  numeric default null)
returns table (
  strom text, buch text, kg numeric, kg_unten numeric, kg_oben numeric,
  kg_beobachtet numeric, kg_projiziert numeric, kg_extrapoliert numeric,
  koeff_n_min int, streuung_kg numeric, df int)
-- Der feste Suchpfad stammt aus 0042: die Funktion muss auch mit leerem
-- search_path rechnen. Ein „create or replace" ohne diese Zeile verlöre ihn.
language sql stable set search_path = public as $$
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
       case when s.bekannt then zahl(s.kg) end,
       -- 0058: zahl() statt hartem Cast. Ist die Streuung so gross, dass der
       -- Bereich nicht mehr darstellbar ist, steht dort „unbekannt" — die
       -- Zahl selbst und alle anderen Ströme bleiben lesbar.
       case when s.bekannt then zahl(greatest(s.kg - g.t * g.streuung - zu.zuschlag, 0)) end,
       case when s.bekannt then zahl(s.kg + g.t * g.streuung + zu.zuschlag) end,
       case when s.bekannt then zahl(s.kg_beobachtet) end,
       case when s.bekannt then zahl(s.kg_projiziert) end,
       case when s.bekannt then zahl(s.kg_extrapoliert) end,
       s.koeff_n_min,
       case when s.bekannt then zahl(g.streuung) end, g.df
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
comment on function verlust_ranking is
  'Alle Ströme mit fortgepflanztem 95-%-Bereich, wahlweise gefiltert. Ein '
  'Bereich, der aus wenigen Messpunkten unermesslich breit wird, steht als '
  'NULL da und reisst die Sicht nicht mehr mit (0058).';

-- ---------- 3. Die Saisonbilanz: Verhältnisse laufen nicht mehr über -----
-- luecke_anteil und ausgang_deckung sind Verhältnisse zum Eingang. Ist der
-- Wareneingang noch nicht (vollständig) eingelesen, der Warenausgang aber
-- schon, werden sie beliebig gross — und die ganze Bilanz brach ab, statt zu
-- sagen, dass der Eingang fehlt. Genau dafür ist der Befund da.
create or replace view v_saisonbilanz with (security_invoker = true) as
with eingang as (
  select sum(eingang_kg) as kg, sum(lager_kg) as im_lager_kg, sum(wartet_kg) as wartet_kg
    from v_hochrechnung_basis
), verlust as (
  select sum(kg) as kg, sum(kg_unten) as kg_unten, sum(kg_oben) as kg_oben,
         sum(kg) filter (where buch = 'verlust') as lager_kg,
         sum(kg) filter (where buch = 'feld')    as feld_kg,
         bool_and(kg is not null) filter (where buch = 'verlust') as bekannt
    from v_verlust_ranking where buch in ('verlust', 'feld')
), rest as (
  select sum(m2) as kg from v_kaskade where portion = 'lager'
), vorlauf as (
  select coalesce(sum(ausgang_vor_app_kg), 0) as kg from charge_vorlauf
), ausgang as (
  select coalesce(sum(masse_kg), 0)                                as kg,
         coalesce(sum(masse_kg) filter (where buch = 'verkauf'), 0) as verkauf_kg,
         coalesce(sum(masse_kg) filter (where buch = 'marge'), 0)   as marge_kg,
         coalesce(sum(masse_kg) filter (where buch = 'verlust'), 0) as entsorgt_kg,
         coalesce(sum(masse_fehler_kg), 0)                          as fehler_kg,
         count(*)::int                                             as n_lieferungen
    from v_lieferung_masse
), fax as (
  select coalesce(sum(masse_kg), 0) as kg, count(*)::int as n
    from v_fax_beobachtung where status = 'abgeschlossen' and masse_kg is not null
), gewaschen as (
  select coalesce(sum(verkaufsfaehig_kg), 0) as kg from v_kaskade where portion = 'ausgelagert'
), offen as (
  select case when f.n > 0 then greatest(g.kg - f.kg, 0) end as kg, f.kg as fax_kg, f.n as fax_n
    from fax f cross join gewaschen g
)
select zahl(e.kg)::numeric(14,2)                           as eingang_kg,
       zahl(v.kg)::numeric(14,2)                           as verlust_modell_kg,
       zahl(v.kg_unten)::numeric(14,2)                     as verlust_unten_kg,
       zahl(v.kg_oben)::numeric(14,2)                      as verlust_oben_kg,
       zahl(a.kg + vl.kg)::numeric(14,2)                   as ausgang_kg,
       zahl(a.verkauf_kg)::numeric(14,2) as verkauf_kg, zahl(a.marge_kg)::numeric(14,2) as marge_kg,
       zahl(a.entsorgt_kg)::numeric(14,2) as entsorgt_kg,
       zahl(a.fehler_kg)::numeric(14,2)                    as ausgang_fehler_kg,
       a.n_lieferungen,
       zahl(vl.kg)::numeric(14,2)                          as vorlauf_kg,
       zahl(r.kg)::numeric(14,2)                           as restbestand_modell_kg,
       zahl(e.im_lager_kg)::numeric(14,2) as im_lager_kg, zahl(e.wartet_kg)::numeric(14,2) as wartet_kg,
       zahl(e.kg - v.kg - a.kg - vl.kg - r.kg - coalesce(o.kg, 0))::numeric(14,2)  as luecke_kg,
       zahl(case when e.kg > 0 then (e.kg - v.kg - a.kg - vl.kg - r.kg - coalesce(o.kg, 0)) / e.kg end,
            4, 1e5)::numeric(10,4)                         as luecke_anteil,
       zahl(case when e.kg > 0 then (a.kg + vl.kg) / e.kg end, 4, 1e5)::numeric(10,4) as ausgang_deckung,
       case
         -- 0058: Der häufigste Grund für ein unmögliches Verhältnis steht
         -- zuerst — es fehlt der Wareneingang, nicht das Modell.
         when coalesce(e.kg, 0) <= 0
           then 'Es ist kein Wareneingang erfasst. Ohne das Erntejournal gibt es '
                || 'nichts, worauf sich Verlust und Bestand beziehen könnten.'
         when a.n_lieferungen > 0 and (a.kg + vl.kg) > e.kg * 3
           then 'Es ist weit mehr ausgeliefert als eingelagert. Fast immer fehlt '
                || 'der Wareneingang (Erntejournal noch nicht eingelesen) oder er '
                || 'deckt nur einen Teil der Saison ab.'
         when not coalesce(v.bekannt, false)
           then 'Ein Verluststrom ist noch nicht gemessen — die Bilanz kann erst '
                || 'schliessen, wenn jeder Koeffizient mindestens eine Messung hat.'
                || case when a.n_lieferungen = 0 and vl.kg = 0
                        then ' Kein Warenausgang erfasst — der Restbestand ist eine '
                             || 'Hochrechnung, kein Inventar.'
                        else '' end
         when a.n_lieferungen = 0 and vl.kg = 0
           then 'Kein Warenausgang erfasst — die Bilanz kann nichts prüfen. '
                || 'Der Restbestand ist eine Hochrechnung, kein Inventar.'
         when (a.kg + vl.kg) / nullif(e.kg, 0) < 0.2
           then 'Erst ein Bruchteil des Ausgangs ist erfasst — die Lücke sagt '
                || 'bislang mehr über die Erfassung als über das Modell.'
         when abs(e.kg - v.kg - a.kg - vl.kg - r.kg - coalesce(o.kg, 0)) / nullif(e.kg, 0) < 0.05
           then 'Die Bilanz geht auf: Eingang, Verlust, Ausgang und Bestand '
                || 'passen auf wenige Prozent zusammen.'
         when (e.kg - v.kg - a.kg - vl.kg - r.kg - coalesce(o.kg, 0)) > 0
           then 'Es fehlt Masse: mehr eingelagert, als sich durch Verlust, '
                || 'Ausgang und Bestand erklären lässt. Entweder ist ein '
                || 'Abgang nicht erfasst, oder ein Verlust wird unterschätzt.'
                || case when o.kg is null then ' Gewaschene Ware, die noch auf eine Bestellung wartet, '
                        || 'sieht die Bilanz erst, wenn das Fax erfasst wird.' else '' end
         else 'Es ist zu viel Masse da: mehr ausgeliefert und übrig, als je '
              || 'eingelagert wurde. Meist doppelt gezählte Paletten oder '
              || 'fehlende Tara im Wareneingang.'
       end                                                 as befund,
       zahl(v.lager_kg)::numeric(14,2)                     as lagerverlust_kg,
       zahl(v.feld_kg)::numeric(14,2)                      as feld_kg,
       zahl(o.fax_kg)::numeric(14,2)                       as fax_kg,
       o.fax_n                                             as n_fax,
       zahl(o.kg)::numeric(14,2)                           as gewaschen_offen_kg
  from eingang e cross join verlust v cross join rest r
       cross join ausgang a cross join vorlauf vl cross join offen o;
comment on view v_saisonbilanz is
  'Die Gegenprobe: Eingang = Verlust + Ausgang + Restbestand + gewaschene Ware, '
  'die noch auf eine Bestellung wartet. Eine Zahl, die nicht darstellbar ist, '
  'steht als NULL da und bricht die Bilanz nicht mehr ab (0058).';
grant select on v_saisonbilanz to authenticated;

-- ---------- 4. Buch B: die Hochrechnung auf Kisten ------------------------
create or replace view v_marge_buch with (security_invoker = true) as
with soll as (
  select coalesce((select (wert #>> '{}')::numeric from public.einstellung
                    where schluessel = 'soll_kg_pro_kiste'), 8) as kg
), kiste_je_sorte as (
  select distinct on (s.sorte) s.sorte, s.soll_kg_pro_kiste as kg
    from sortierschema s
   where s.art = 'kiste' and s.soll_kg_pro_kiste > 0 and s.gilt_ab <= current_date
   order by s.sorte, s.gilt_ab desc, (s.kaeufer is null) desc, s.id desc
), kiste_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (where ss.art = 'kiste'), 0)
           / nullif(sum(am.eingang_netto_kg), 0) as anteil
    from v_auftrag_masse am
    join auftrag a on a.id = am.auftrag_id
    left join sortierschema ss on ss.id = a.sortierschema_id
   where am.weg = 'hand' and am.eingang_netto_kg is not null
   group by am.charge_nr
), kisten as materialized (
  -- 0058: Das Sollgewicht je Kiste ist der Nenner. Ist es nicht gesetzt oder
  -- unsinnig klein, wäre die Kistenzahl beliebig gross; dann gibt es sie
  -- nicht (NULL), und die Überfüllung steht als unbekannt da.
  select sum(k.verkaufsfaehig_kg * b.weg2_anteil * coalesce(ka.anteil, 0)
             / n.soll)                                           as anzahl,
         sum(k.verkaufsfaehig_kg * b.weg2_anteil)                    as weg2_kg,
         sum(k.verkaufsfaehig_kg * b.weg2_anteil * coalesce(ka.anteil, 0)) as kisten_kg
    from v_kaskade k
    join v_hochrechnung_basis b on b.charge_nr = k.charge_nr
    left join kiste_je_sorte ks on ks.sorte = k.sorte
    left join kiste_anteil ka on ka.charge_nr = k.charge_nr
    cross join soll s
    cross join lateral (select nullif(greatest(coalesce(ks.kg, s.kg), 0.1), 0.1) as soll) n
)
select r.strom as posten, r.kg, r.kg_unten, r.kg_oben,
       case r.strom
         when 'Nebenkanal zu gross' then 'Ware über 2000 g geht in einen anderen Verkaufskanal'
         when 'Zu klein (Tierfutter)' then 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'
         else '' end::text                                       as erlaeuterung
  from v_verlust_ranking r where r.buch = 'marge'
union all
select 'Überfüllung der Kisten',
       zahl((u.kg_pro_kiste * v.anzahl)::numeric)::numeric(14,2),
       zahl((u.unten * v.anzahl)::numeric)::numeric(14,2),
       zahl((u.oben  * v.anzahl)::numeric)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf '
              || '%s Kisten. Gerechnet wird nur über die %s t von %s t Weg-2-Ware, die '
              || 'als „Kiste ab x kg" sortiert wurde — nach Kaliber sortierte Ware hat '
              || 'kein Sollgewicht je Kiste und damit keine Überfüllung.',
              u.n, round(u.kg_pro_kiste, 3), round(coalesce(v.anzahl, 0)),
              round(coalesce(v.kisten_kg, 0) / 1000.0, 1), round(coalesce(v.weg2_kg, 0) / 1000.0, 1))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;
comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb über einen anderen Kanal verlässt, plus die '
  'verschenkte Marge aus überfüllten Kisten. Ohne brauchbares Sollgewicht je '
  'Kiste bleibt die Überfüllung unbekannt statt unmöglich gross (0058).';
grant select on v_marge_buch to authenticated;

-- ---------- 5. Stand der Datenbank ---------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 58 $$;
