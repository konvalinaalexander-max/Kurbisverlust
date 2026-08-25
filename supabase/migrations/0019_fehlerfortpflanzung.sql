-- =====================================================================
-- 0019 — Ein Bereich, der wirklich ein Bereich ist
--
-- Bisher wurden drei Szenarien gerechnet: „unten" setzte *alle* Koeffizienten
-- gleichzeitig an ihre untere Grenze, „oben" alle an die obere. Das
-- unterstellt, dass sich alle Messfehler im Gleichtakt bewegen — und für
-- Ströme weiter unten in der Kaskade stimmt nicht einmal die Richtung.
--
-- Der Harness zeigt es unmissverständlich (25 Saisons, 50 % im Lager):
--
--   Ausschuss zu klein   Bereichsbreite −2.3 %   Überdeckung 0 %
--
-- Eine *negative* Breite: kg_unten lag über kg_oben. Der Grund ist zwingend.
-- Weniger Verdunstung und weniger Schimmel heisst mehr Masse, die überhaupt
-- bis zum Sortierband kommt. Im Szenario „unten" sind r und f klein, also ist
-- die Masse gross — und der Ausschuss daraus grösser als im Szenario „oben".
-- Die Grenzen tauschen die Plätze. Das war nie ein Konfidenzintervall; es sah
-- nur aus wie eins.
--
-- ---------- Statt dessen: Fehlerfortpflanzung ----------------------------
-- Für jeden Strom wird ausgerechnet, wie stark er auf jeden Koeffizienten
-- reagiert (die Ableitung), und die Fehler werden entsprechend ihrer
-- tatsächlichen Abhängigkeit zusammengesetzt:
--
--   m1 = m0·(1−r)^t        D := ∂m1/∂r = −m0·t·(1−r)^(t−1)
--   m2 = m1·(1−f)
--
--   Verdunstung   V = m0−m1     ∂V/∂r = −D
--   Schimmel      S = m1·f      ∂S/∂r = D·f          ∂S/∂f = m1
--   Ausschuss     K = m2·a      ∂K/∂r = D·(1−f)·a    ∂K/∂f = −m1·a   ∂K/∂a = m2
--
-- Damit wandert der Fehler von r automatisch in Schimmel und Ausschuss
-- weiter, statt dort als unabhängig behandelt zu werden.
--
-- Zusammengesetzt wird nach der wahren Korrelationsstruktur:
--
--   * Der Schimmelkoeffizient stammt aus *einem* Modell mit zwei Parametern
--     (Achse A, Steigung k). Über alle Chargen hinweg ist es derselbe Fehler,
--     nicht 42 unabhängige. Also werden erst die Ableitungen summiert und
--     dann einmal mit der 2×2-Kovarianz des Modells multipliziert.
--   * r und die Kaliber-Anteile sind je Sorte geschätzt, aber alle Sorten
--     hängen über die Bündelung am selben Gesamtwert. Der eigene Anteil geht
--     quadratisch ein (unabhängig), der gemeinsame linear (identisch).
--
-- Das Ergebnis ist ein Bereich, dessen Grenzen in der richtigen Reihenfolge
-- stehen und der aussagt, was er behauptet.
--
-- Nebeneffekt: mv_kaskade hat nur noch ein Drittel der Zeilen, weil die drei
-- Szenarien wegfallen. Das Neuberechnen wird entsprechend schneller.
-- =====================================================================

drop materialized view if exists mv_kaskade cascade;

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
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(coalesce(ka.mittel, 0), 0), 1)    as a_klein,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(coalesce(kn.mittel, 0), 0), 1)    as a_gross,
         kn.n as gross_n, kn.basis as gross_basis
    from v_hochrechnung_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
),
koeff_norm as (
  -- Zusammen dürfen die beiden Kaliber-Anteile nicht über 1 liegen. Der Fall
  -- tritt nur bei widersprüchlichen Messungen auf; die Ableitungen unten
  -- rechnen mit dem unnormierten Koeffizienten, was dann geringfügig zu
  -- gross ist — auf der sicheren Seite.
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  select k.*, t.portion, t.m0, t.alter_tage,
         -- η = ln λ + k·ln t, zentriert um den Schwerpunkt der Messungen
         ln(greatest(t.alter_tage, 1)) - coalesce(m.x_mittel, 0)        as u,
         case when m.brauchbar then
           m.ln_lambda_korrigiert + m.k * ln(greatest(t.alter_tage, 1))
         end                                                            as eta,
         m.brauchbar                                                    as modell_gilt,
         (m.brauchbar and t.alter_tage > m.t_max)                       as f_extrapoliert,
         case when m.brauchbar then m.c_chargen else s.n end            as f_n,
         s.anteil_mono                                                  as f_treppe
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
         -- ∂m1/∂r, negativ: mehr Verdunstungsrate → weniger Masse
         (-t.m0 * t.alter_tage * power(1 - t.r, greatest(t.alter_tage - 1, 0))) as d_m1_r,
         -- ∂f/∂η = (1−f)·e^η. Ohne Modell ist die Treppe eine Konstante,
         -- also keine Ableitung — dann steht der Fehler auf 0 und n sagt,
         -- dass es keine Aussage ist.
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

-- ---------- Die Ströme mit ihren Ableitungen ------------------------------
create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg, k.f_extrapoliert, k.u,
       s.strom, s.buch,
       s.kg::numeric(14,2)          as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       s.koeffizient::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel,
       -- Empfindlichkeit dieses Stroms gegenüber jedem Koeffizienten
       s.d_r                        as d_r,
       s.d_f * k.d_f_eta            as d_eta,
       s.d_a                        as d_a,
       s.koeff_art                  as koeff_art
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung', 'verlust', k.m0 - k.m1, k.m0, k.r, k.r_n, k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen',
     -k.d_m1_r, 0::numeric, 0::numeric, null::text),
    ('Schimmel/Fäulnis', 'verlust', k.m1 * k.f, k.m1, k.f, k.f_n,
     'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer',
     k.d_m1_r * k.f, k.m1, 0::numeric, null::text),
    ('Ausschuss zu klein', 'verlust', k.m1 * (1 - k.f) * k.a_klein_n, k.m2,
     k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze',
     k.d_m1_r * (1 - k.f) * k.a_klein_n, -k.m1 * k.a_klein_n, k.m2, 'ausschuss'),
    ('Nebenkanal zu gross', 'marge', k.m1 * (1 - k.f) * k.a_gross_n, k.m2,
     k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal',
     k.d_m1_r * (1 - k.f) * k.a_gross_n, -k.m1 * k.a_gross_n, k.m2, 'nebenkanal'),
    ('Verkaufsfähig', 'bilanz', k.verkaufsfaehig_kg, k.m2, null::numeric, null::int,
     null::text, 'Rest der Kaskade', 0::numeric, 0::numeric, 0::numeric, null::text)
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel,
         d_r, d_f, d_a, koeff_art);

-- ---------- Die Zusammenfassung mit fortgepflanztem Fehler ----------------
create view v_verlust_ranking with (security_invoker = true) as
with zeilen as materialized (
  select * from v_hochrechnung where buch in ('verlust', 'marge')
),
-- Je Strom und Sorte die Ableitungen aufsummieren. Innerhalb einer Sorte ist
-- es derselbe geschätzte Koeffizient, die Ableitungen addieren sich also.
je_sorte as (
  select z.strom, z.buch, z.sorte, max(z.koeff_art) as koeff_art,
         sum(z.d_r) as g_r, sum(z.d_a) as g_a
    from zeilen z group by z.strom, z.buch, z.sorte
),
-- Der Schimmelkoeffizient ist *ein* Modell für alle Sorten und Chargen.
je_strom_modell as (
  select z.strom, z.buch,
         sum(z.d_eta)       as g_achse,
         sum(z.d_eta * z.u) as g_steigung
    from zeilen z group by z.strom, z.buch
),
varianz_r as (
  -- Eigener Anteil quadratisch (unabhängig je Sorte), gemeinsamer Anteil
  -- linear (für alle Sorten derselbe Gesamtwert).
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
  -- Quadratische Form mit der 2×2-Kovarianz des Verderbsmodells
  select m.strom, m.buch,
         power(m.g_achse, 2) * coalesce(sm.var_achse, 0)
         + 2 * m.g_achse * m.g_steigung * coalesce(sm.kov_achse_k, 0)
         + power(m.g_steigung, 2) * coalesce(sm.var_k, 0)       as varianz,
         coalesce(sm.c_chargen - 1, 1)                          as df
    from je_strom_modell m cross join v_schimmel_modell sm
),
summe as (
  select z.strom, z.buch,
         sum(z.kg)                                                as kg,
         sum(z.kg) filter (where z.portion = 'ausgelagert')       as kg_beobachtet,
         sum(z.kg) filter (where z.portion = 'lager')             as kg_projiziert,
         sum(z.kg) filter (where z.f_extrapoliert)                as kg_extrapoliert,
         min(z.koeff_n)                                           as koeff_n_min
    from zeilen z group by z.strom, z.buch
)
select s.strom, s.buch, s.kg,
       greatest(s.kg - g.t * g.streuung, 0)::numeric(14,2)   as kg_unten,
       (s.kg + g.t * g.streuung)::numeric(14,2)              as kg_oben,
       s.kg_beobachtet, s.kg_projiziert, s.kg_extrapoliert, s.koeff_n_min,
       g.streuung::numeric(14,2)                             as streuung_kg,
       g.df                                                  as df
  from summe s
  left join varianz_r vr on vr.strom = s.strom and vr.buch = s.buch
  left join varianz_a va on va.strom = s.strom and va.buch = s.buch
  left join varianz_f vf on vf.strom = s.strom and vf.buch = s.buch
  cross join lateral (
    select sqrt(greatest(coalesce(vr.varianz, 0) + coalesce(va.varianz, 0)
                         + coalesce(vf.varianz, 0), 0))       as streuung,
           least(coalesce(vr.df, 999), coalesce(va.df, 999),
                 coalesce(vf.df, 999))                        as df
  ) g0
  cross join lateral (select g0.streuung, g0.df, t_quantil_95(g0.df) as t) g
 order by s.kg desc nulls last;

comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall: die '
  'Empfindlichkeit jedes Stroms gegenüber jedem Koeffizienten mal dessen '
  'Fehler, zusammengesetzt nach der tatsächlichen Korrelation. Nicht drei '
  'Szenarien — die standen bei nachgelagerten Strömen in der falschen '
  'Reihenfolge.';

-- ---------- Marge-Buch ----------------------------------------------------
create view v_marge_buch with (security_invoker = true) as
with kisten as materialized (
  select sum(k.verkaufsfaehig_kg * b.weg2_anteil) / 8.0 as anzahl
    from v_kaskade k join v_hochrechnung_basis b on b.charge_nr = k.charge_nr
)
select r.strom as posten, r.kg, r.kg_unten::numeric as kg_unten,
       r.kg_oben::numeric as kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from v_verlust_ranking r where r.buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       (u.unten * v.anzahl)::numeric(14,2),
       (u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.anzahl))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;

-- ---------- Massenbilanz --------------------------------------------------
create view v_massenbilanz with (security_invoker = true) as
with modell as materialized (
  select charge_nr,
         sum(m2) filter (where portion = 'ausgelagert') as modell_kg,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade group by charge_nr
), csv_anteil as materialized (
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
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       (m.modell_kg * q.anteil_mit_csv)::numeric(14,2)      as modell_am_band_kg,
       c.gemessen_kg                                        as csv_gemessen_kg,
       (c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)::numeric(14,2) as abweichung_kg,
       case when m.modell_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)
                  / (m.modell_kg * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       m.restbestand_kg::numeric(14,2)                      as restbestand_kg
  from v_hochrechnung_basis b
  left join modell m     on m.charge_nr = b.charge_nr
  left join csv_anteil q on q.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

grant select on v_kaskade, v_hochrechnung, v_verlust_ranking,
               v_marge_buch, v_massenbilanz to authenticated;
