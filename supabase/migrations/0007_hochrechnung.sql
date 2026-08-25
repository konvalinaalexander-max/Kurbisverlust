-- =====================================================================
-- 0007 — Auswertung, Teil 3: Hochrechnung, Ranking, Massenbilanz
--
-- Verlust = Koeffizient × bekannte Größe, stratifiziert nach Sorte und
-- Lagerdauer, Ergebnis als Bereich (Spec §9). Jede Charge wird in zwei
-- Portionen zerlegt:
--   * ausgelagert — schon verarbeitet, Lagerdauer beobachtet
--   * im Lager    — rechts-zensiert, bis zum Stichtag projiziert
-- Genau das ist die Antwort auf „mitten in der Saison auswertbar".
-- =====================================================================

create view v_hochrechnung_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung where schluessel = 'saison_ende'),
                  current_date) as bis
), ausgang as (
  -- Was hat das Lager verlassen? Nur die erste Station zählt: Waschen auf
  -- Weg 1 ist ein zweiter Griff an bereits sortierte Ware, keine neue Auslagerung.
  select charge_nr,
         sum(eingang_netto_kg)                                              as kg,
         sum(eingang_netto_kg * lagertage) / nullif(sum(eingang_netto_kg), 0) as lagertage,
         sum(eingang_netto_kg) filter (where weg = 'hand')                  as kg_hand
    from v_auftrag_masse
   where station in ('sortieren', 'waschen_sortieren')
     and eingang_netto_kg is not null
   group by charge_nr
)
select r.charge_nr, r.schlag, r.sorte, r.eingang_netto_kg as eingang_kg,
       r.n_paletten, r.eingangsdatum_mittel,
       coalesce(a.kg, 0)::numeric                                    as ausgelagert_kg,
       a.lagertage                                                   as alter_ausgelagert,
       greatest(r.eingang_netto_kg - coalesce(a.kg, 0), 0)::numeric   as lager_kg,
       (s.bis - r.eingangsdatum_mittel)::numeric                     as alter_lager,
       (current_date - r.eingangsdatum_mittel)::numeric              as alter_lager_heute,
       coalesce(a.kg_hand / nullif(a.kg, 0), 0)                      as weg2_anteil,
       s.bis                                                         as stichtag
  from v_charge_rueckgrat r
  cross join stichtag s
  left join ausgang a on a.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;

-- ---------- Die Kaskade, je Charge und Szenario ---------------------------
create view v_kaskade with (security_invoker = true) as
with sz(szenario) as (values ('unten'), ('mittel'), ('oben')),
koeff as (
  select b.*, sz.szenario,
         -- Ein Koeffizient außerhalb des Plausiblen ist ein Rechenartefakt
         -- der kleinen Stichprobe, kein Messergebnis — daher gekappt.
         least(greatest(case sz.szenario when 'unten' then kv.unten
                                         when 'oben'  then kv.oben
                                         else kv.mittel end, 0), 0.05) as r,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(case sz.szenario when 'unten' then ka.unten
                                         when 'oben'  then ka.oben
                                         else ka.mittel end, 0), 1) as a_klein,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(case sz.szenario when 'unten' then kn.unten
                                         when 'oben'  then kn.oben
                                         else kn.mittel end, 0), 1) as a_gross,
         kn.n as gross_n, kn.basis as gross_basis
    from v_hochrechnung_basis b
    cross join sz
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
),
koeff_norm as (
  -- Im oberen Szenario können die Obergrenzen von „zu klein" und „zu gross"
  -- zusammen über 100 % liegen. Beide dann proportional herunterskalieren:
  -- das erhält ihr Verhältnis und lässt keine negative Restmasse entstehen.
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  -- Beide Portionen in einer Form, damit die Kaskade nur einmal dasteht.
  select k.*, t.portion, t.m0, t.alter_tage,
         schimmelanteil(t.alter_tage, k.szenario) as f
    from koeff_norm k
    cross join lateral (values
        ('ausgelagert', k.ausgelagert_kg, coalesce(k.alter_ausgelagert, 0)),
        ('lager',       k.lager_kg,       greatest(k.alter_lager, 0))
      ) as t(portion, m0, alter_tage)
   where t.m0 > 0
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))::numeric              as m1,
         (t.m0 * power(1 - t.r, t.alter_tage) * (1 - t.f))::numeric  as m2
    from teile t
)
select k.*,
       k.m0 - k.m1                                    as verdunstung_kg,
       k.m1 - k.m2                                    as schimmel_kg,
       k.m2 * k.a_klein_n                             as klein_kg,
       k.m2 * k.a_gross_n                             as nebenkanal_kg,
       k.m2 * (1 - k.a_klein_n - k.a_gross_n)         as verkaufsfaehig_kg
  from kaskade k;

-- ---------- Ströme in Langform: die Datenquelle des Dashboards -------------
create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.szenario, k.portion, k.alter_tage,
       k.eingang_kg, k.m0 as portion_kg, s.strom, s.buch, s.kg, s.basis_kg,
       s.koeffizient, s.koeff_n, s.koeff_basis, s.formel
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung',      'verlust', k.verdunstung_kg, k.m0, k.r,       k.r_n,     k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'),
    ('Schimmel/Fäulnis', 'verlust', k.schimmel_kg,    k.m1, k.f,       schimmel_n(k.alter_tage), 'Schimmelkurve nach Lagerdauer',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer'),
    ('Ausschuss zu klein','verlust', k.klein_kg,      k.m2, k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze'),
    ('Nebenkanal zu gross','marge',  k.nebenkanal_kg, k.m2, k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'),
    ('Verkaufsfähig',    'bilanz',  k.verkaufsfaehig_kg, k.m2, null::numeric, null::int, null::text,
     'Rest der Kaskade')
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel);

-- ---------- Ebene 1: die Ursachen, rangiert ------------------------------
create view v_verlust_ranking with (security_invoker = true) as
select strom, buch,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       sum(kg) filter (where szenario = 'mittel' and portion = 'ausgelagert') as kg_beobachtet,
       sum(kg) filter (where szenario = 'mittel' and portion = 'lager')       as kg_projiziert,
       min(koeff_n)                                                          as koeff_n_min
  from v_hochrechnung
 where buch = 'verlust'
 group by strom, buch
 order by 3 desc nulls last;

-- ---------- Buch B: verschenkte Marge ------------------------------------
-- Weg 1 (Nebenkanal-Überschuss) und Weg 2 (Überfüllung) sind zwei völlig
-- verschiedene Wege, Ware zu verschenken. Sie stehen bewusst nebeneinander
-- und werden nie in das Verlust-Buch gemischt (Spec §2).
create view v_marge_buch with (security_invoker = true) as
select 'Nebenkanal zu gross'::text as posten,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from v_hochrechnung where buch = 'marge'
union all
select 'Überfüllung der 8-kg-Kisten',
       u.kg_pro_kiste * v.kisten, u.unten * v.kisten, u.oben * v.kisten,
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.kisten))
  from v_koeff_ueberfuellung u
  cross join lateral (
        -- Kistenzahl aus der verkaufsfähigen Weg-2-Masse (Fixpreis ab 8 kg)
        select sum(h.kg * b.weg2_anteil) / 8.0 as kisten
          from v_hochrechnung h
          join v_hochrechnung_basis b on b.charge_nr = h.charge_nr
         where h.strom = 'Verkaufsfähig' and h.szenario = 'mittel'
       ) v
 where u.n > 0;

-- ---------- Massenbilanz als Kontrolle ------------------------------------
-- Der eigentliche Test ist nicht, ob die Kaskade in sich aufgeht (das tut sie
-- per Konstruktion), sondern ob sie die *gemessene* Wirklichkeit trifft: die
-- modellierte Masse am Sortierband gegen die tatsächlich gewogene CSV-Masse.
create view v_massenbilanz with (security_invoker = true) as
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       m.modell_kg                                     as modell_am_band_kg,
       c.gemessen_kg                                   as csv_gemessen_kg,
       (c.gemessen_kg - m.modell_kg)                   as abweichung_kg,
       case when m.modell_kg > 0
            then (c.gemessen_kg - m.modell_kg) / m.modell_kg end as abweichung_anteil,
       h.restbestand_kg
  from v_hochrechnung_basis b
  left join lateral (
        select sum(k.m2) as modell_kg from v_kaskade k
         where k.charge_nr = b.charge_nr and k.szenario = 'mittel' and k.portion = 'ausgelagert'
       ) m on true
  left join lateral (
        select sum(lm.masse_kg) as gemessen_kg
          from v_sortier_lauf_masse lm where lm.charge_nr = b.charge_nr
       ) c on true
  left join lateral (
        select sum(k.verkaufsfaehig_kg) as restbestand_kg from v_kaskade k
         where k.charge_nr = b.charge_nr and k.szenario = 'mittel' and k.portion = 'lager'
       ) h on true;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

-- ---------- Datenlage: was fehlt noch? ------------------------------------
-- Die Stichproben sollen die Kandidaten trennen (Spec §9). Diese View zeigt,
-- wo eine weitere Messung am meisten bringt.
create view v_datenlage with (security_invoker = true) as
select r.charge_nr, r.sorte, r.schlag, r.n_paletten,
       -- Paletten ohne hinterlegte Gebinde-Tara haben kein Netto und fehlen
       -- damit still in der Eingangsmasse. Die Lücke muss sichtbar sein.
       r.n_paletten_mit_netto, r.eingang_netto_kg as eingang_kg,
       (select count(*) from verdunstung_wiegung w where w.charge_nr = r.charge_nr) as n_wiegungen,
       (select count(*) from auftrag a join schimmel_messung s on s.auftrag_id = a.id
         where a.charge_nr = r.charge_nr)                                           as n_schimmel,
       (select count(*) from sortier_lauf l where l.charge_nr = r.charge_nr)        as n_sortierlaeufe,
       (select count(*) from auftrag a where a.charge_nr = r.charge_nr)             as n_auftraege
  from v_charge_rueckgrat r;
