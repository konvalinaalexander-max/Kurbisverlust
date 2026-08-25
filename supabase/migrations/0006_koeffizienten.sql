-- =====================================================================
-- 0006 — Auswertung, Teil 2: die Koeffizienten aus den Stichproben
--
-- Jeder Koeffizient kommt als (mittel, unten, oben, n, basis) — die
-- Unsicherheit wird mitgeführt, nicht weggerundet (Spec §9). `basis` sagt,
-- woraus der Wert stammt, und ist die Grundlage des aufklappbaren
-- Rechenwegs auf Ebene 3 des Dashboards.
--
-- Modell der Massenkaskade (in dieser Reihenfolge angewandt):
--   Eingang  --Verdunstung-->  M1  --Schimmel-->  M2  --Ausschuss/Nebenkanal-->  verkaufsfähig
-- Jeder Anteil bezieht sich auf die Masse, die in seinen Schritt hineingeht.
-- Nur so lassen sich die Ströme addieren, ohne Basen zu vermischen.
-- =====================================================================

-- ---------- Verdunstung ---------------------------------------------------
-- Wasserverlust läuft multiplikativ, nicht linear: aus dem Gewichtsverhältnis
-- wird eine Tagesrate r mit  netto_jetzt = netto_damals · (1−r)^Lagertage.
-- Vorteil gegenüber „Prozent pro Tag mal Tage": die Hochrechnung kann auch
-- über lange Lagerdauern nie mehr als die vorhandene Masse verbrauchen.
create view v_verdunstung_messung with (security_invoker = true) as
select w.id, w.charge_nr, c.sorte, c.schlag, w.palette_id, w.eingangsdatum,
       w.wiege_ts, w.sichtbar_schimmel, w.erfasser, w.auftrag_id,
       n.netto_damals_kg, n.netto_jetzt_kg,
       (w.wiege_ts::date - w.eingangsdatum) as lagertage,
       case when n.netto_damals_kg > 0 and n.netto_jetzt_kg > 0
             and (w.wiege_ts::date - w.eingangsdatum) > 0
            then 1 - power(n.netto_jetzt_kg / n.netto_damals_kg,
                           1.0 / (w.wiege_ts::date - w.eingangsdatum))
       end::numeric(10,6) as rate_pro_tag,
       -- Sichtbar verschimmelte Paletten mischen Fäulnis in die Verdunstung.
       -- Sie bleiben sichtbar, zählen aber nicht in den Koeffizienten.
       (w.gemessen and not w.sichtbar_schimmel
        and n.netto_damals_kg > 0 and n.netto_jetzt_kg > 0
        and (w.wiege_ts::date - w.eingangsdatum) > 0) as verwendbar
  from verdunstung_wiegung w
  join charge c on c.nr = w.charge_nr
  left join gebinde g on g.art = w.gebindeart
  cross join lateral (
        select w.brutto_damals_kg - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                                  - coalesce(g.tara_kg_palette, 0) as netto_damals_kg,
               w.brutto_jetzt_kg  - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                                  - coalesce(g.tara_kg_palette, 0) as netto_jetzt_kg
       ) n;

-- Je Sorte und über alles. Das Intervall ist der 95-%-Bereich für den
-- Mittelwert (normale Näherung, ab n ≥ 2).
create view v_verdunstung_stichprobe with (security_invoker = true) as
with roh as (select * from v_verdunstung_messung where verwendbar)
select grp.sorte, s.n, s.mittel, s.sd,
       case when s.n >= 2 then s.mittel - 1.96 * s.sd / sqrt(s.n) end as unten,
       case when s.n >= 2 then s.mittel + 1.96 * s.sd / sqrt(s.n) end as oben
  from (select sorte from roh group by sorte union all select null) grp
  cross join lateral (
        select count(*)::int as n, avg(rate_pro_tag) as mittel, stddev_samp(rate_pro_tag) as sd
          from roh where grp.sorte is null or roh.sorte = grp.sorte
       ) s;

-- Effektiver Koeffizient je Sorte: eigene Stichprobe, sobald sie belastbar
-- ist (n ≥ 3), sonst der Gesamtwert. Die Spalte `basis` macht das sichtbar.
create view v_koeff_verdunstung with (security_invoker = true) as
-- Bei n = 1 gibt es keinen Streubereich. Dann gilt der Punktwert für alle
-- drei Szenarien — der Bereich ist noch nicht bestimmbar, und `n` sagt das.
-- Eine erfundene Spanne wäre schlimmer als eine sichtbar fehlende.
select sk.sorte,
       coalesce(js.mittel, ge.mittel)                              as mittel,
       coalesce(js.unten,  ge.unten,  js.mittel, ge.mittel)        as unten,
       coalesce(js.oben,   ge.oben,   js.mittel, ge.mittel)        as oben,
       coalesce(js.n, ge.n, 0)                                     as n,
       case when js.sorte is not null then 'Wiegungen dieser Sorte'
            when ge.n > 0            then 'Wiegungen aller Sorten (zu wenige eigene)'
            else 'keine Wiegung vorhanden' end                     as basis
  from sorte_kaliber sk
  left join v_verdunstung_stichprobe js on js.sorte = sk.sorte and js.n >= 3
  left join v_verdunstung_stichprobe ge on ge.sorte is null;

-- ---------- Schimmel / Fäulnis -------------------------------------------
-- Beobachtung je Auftrag: welcher Anteil der Masse, die an diesem Tag aus dem
-- Lager kam, war faul. Der Nenner ist die *heutige* Masse — also die
-- Eingangsmasse abzüglich der bis dahin verdunsteten Menge. Sonst würde der
-- Schimmelanteil mit der Lagerdauer allein durch die Verdunstung steigen.
create view v_schimmel_beobachtung with (security_invoker = true) as
select am.auftrag_id, am.charge_nr, am.sorte, am.schlag, am.weg, am.station,
       am.start_ts, am.lagertage, am.masse_quelle,
       s.kg                                                        as schimmel_kg,
       am.eingang_netto_kg                                         as eingang_kg,
       (am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage))::numeric(12,2)
                                                                   as basis_jetzt_kg,
       (s.kg / nullif(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage), 0))
                                                                   as anteil
  from v_auftrag_masse am
  join (select auftrag_id, sum(kg)::numeric as kg
          from schimmel_messung where gemessen group by auftrag_id) s
       on s.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
 where am.eingang_netto_kg is not null
   and am.lagertage is not null;

comment on view v_schimmel_beobachtung is
  'Bekannte kleine Verzerrung: der Palox wird heute gewogen, die faulen '
  'Kürbisse haben also selbst schon Wasser verloren. Der wahre Anteil liegt '
  'geringfügig höher als hier ausgewiesen.';

-- Altersklassen der Lagerdauer. Der Schimmelanteil ist *kumulativ*: ein
-- Auftrag nach 90 Tagen zeigt alles, was bis dahin verdorben ist.
create view v_schimmel_kurve with (security_invoker = true) as
with klassen(von, bis) as (
  values (0, 14), (15, 30), (31, 60), (61, 90), (91, 120), (121, 180), (181, 100000)
), je_klasse as (
  select k.von, k.bis,
         count(b.auftrag_id)::int as n,
         -- massegewichtet: eine große Palette wiegt schwerer als eine kleine
         sum(b.schimmel_kg) / nullif(sum(b.basis_jetzt_kg), 0) as anteil,
         stddev_samp(b.anteil)                                 as sd
    from klassen k
    left join v_schimmel_beobachtung b
           on b.lagertage >= k.von and b.lagertage <= k.bis and b.anteil is not null
   group by k.von, k.bis
)
select von, bis, n, anteil, sd,
       -- Kumulativ heißt: der Anteil kann mit dem Alter nicht sinken. Bei
       -- wenigen Stichproben tut er das trotzdem; das laufende Maximum
       -- glättet solche Ausreißer nach unten weg (isotone Korrektur).
       max(anteil) over (order by von rows between unbounded preceding and current row) as anteil_mono,
       case when n >= 2 then greatest(anteil - 1.96 * sd / sqrt(n), 0) end as unten,
       case when n >= 2 then least(anteil + 1.96 * sd / sqrt(n), 1) end    as oben
  from je_klasse;

-- Schimmelanteil bei gegebener Lagerdauer. Ist die Altersklasse leer, gilt
-- der letzte belegte Wert darunter (Treppenfunktion, nach oben fortgeschrieben).
create or replace function schimmelanteil(p_lagertage numeric, p_szenario text default 'mittel')
returns numeric language sql stable as $$
  select coalesce((
    select case p_szenario
             when 'unten' then coalesce(k.unten, k.anteil_mono)
             when 'oben'  then coalesce(k.oben,  k.anteil_mono)
             else k.anteil_mono end
      from v_schimmel_kurve k
     where k.von <= p_lagertage and k.n > 0
     order by k.von desc
     limit 1
  ), 0)::numeric;
$$;

-- ---------- Ausschuss zu klein & Nebenkanal zu gross ----------------------
-- Weg 1: direkt aus der Sortier-CSV (Massenanteil im selben Strom, gleiche
-- Basis, gleicher Moment). Weg 2: aus den Handmessungen, Basis = verarbeitete
-- Masse nach Verdunstung und abzüglich des ausgelesenen Schimmels.
create view v_ausschuss_beobachtung with (security_invoker = true) as
-- masse_kg ist die Gesamtmasse des Laufs, inklusive der zu kleinen und der
-- zu großen Kürbisse — genau die Masse, die über das Band gelaufen ist.
select 'maschine'::verarbeitungsweg as weg, lm.charge_nr, lm.sorte, lm.auftrag_id,
       lm.masse_kg                                  as basis_kg,
       lm.masse_klein_kg                            as klein_kg,
       lm.masse_nebenkanal_kg                       as gross_kg
  from v_sortier_lauf_masse lm
 where lm.masse_kg > 0
union all
select 'hand'::verarbeitungsweg, am.charge_nr, am.sorte, am.auftrag_id,
       (am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage)
        - coalesce(sm.kg, 0))::numeric(12,2),
       h.klein_kg, h.gross_kg
  from v_auftrag_masse am
  join (select auftrag_id,
               sum(kg) filter (where art = 'zu_klein')::numeric as klein_kg,
               sum(kg) filter (where art = 'zu_gross')::numeric as gross_kg
          from ausschuss_messung where gemessen group by auftrag_id) h
       on h.auftrag_id = am.auftrag_id
  left join (select auftrag_id, sum(kg)::numeric as kg from schimmel_messung
              where gemessen group by auftrag_id) sm on sm.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
 where am.weg = 'hand' and am.eingang_netto_kg is not null and am.lagertage is not null;

create view v_koeff_ausschuss with (security_invoker = true) as
with roh as (
  select sorte, klein_kg / nullif(basis_kg, 0) as anteil, basis_kg
    from v_ausschuss_beobachtung where klein_kg is not null and basis_kg > 0
), stich as (
  select grp.sorte, s.n, s.mittel, s.sd
    from (select sorte from roh group by sorte union all select null) grp
    cross join lateral (
      select count(*)::int as n,
             -- massegewichtet: ein großer Lauf zählt mehr als ein kleiner
             sum(anteil * basis_kg) / nullif(sum(basis_kg), 0) as mittel,
             stddev_samp(anteil) as sd
        from roh where grp.sorte is null or roh.sorte = grp.sorte) s
), eff as (
  select sk.sorte,
         coalesce(js.n, ge.n, 0)        as n,
         coalesce(js.mittel, ge.mittel) as mittel,
         coalesce(js.sd, ge.sd)         as sd,
         case when js.sorte is not null then 'Sortierläufe/Handmessungen dieser Sorte'
              when ge.n > 0             then 'alle Sorten (zu wenige eigene)'
              else 'keine Messung vorhanden' end as basis
    from sorte_kaliber sk
    left join stich js on js.sorte = sk.sorte and js.n >= 2
    left join stich ge on ge.sorte is null
)
select sorte, mittel,
       -- Ohne Streuung (n < 2) gibt es keinen Bereich: dann gilt der Punktwert
       -- für alle drei Szenarien. greatest()/least() würden NULL still zu 0
       -- bzw. 1 machen und damit einen Bereich vortäuschen, den es nicht gibt.
       case when sd is null or n < 2 then mittel
            else greatest(mittel - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then mittel
            else least(mittel + 1.96 * sd / sqrt(n), 1) end    as oben,
       n, basis
  from eff;

create view v_koeff_nebenkanal with (security_invoker = true) as
with roh as (
  select sorte, gross_kg / nullif(basis_kg, 0) as anteil, basis_kg
    from v_ausschuss_beobachtung where gross_kg is not null and basis_kg > 0
), stich as (
  select grp.sorte, s.n, s.mittel, s.sd
    from (select sorte from roh group by sorte union all select null) grp
    cross join lateral (
      select count(*)::int as n,
             -- massegewichtet: ein großer Lauf zählt mehr als ein kleiner
             sum(anteil * basis_kg) / nullif(sum(basis_kg), 0) as mittel,
             stddev_samp(anteil) as sd
        from roh where grp.sorte is null or roh.sorte = grp.sorte) s
), eff as (
  select sk.sorte,
         coalesce(js.n, ge.n, 0)        as n,
         coalesce(js.mittel, ge.mittel) as mittel,
         coalesce(js.sd, ge.sd)         as sd,
         case when js.sorte is not null then 'Sortierläufe/Handmessungen dieser Sorte'
              when ge.n > 0             then 'alle Sorten (zu wenige eigene)'
              else 'keine Messung vorhanden' end as basis
    from sorte_kaliber sk
    left join stich js on js.sorte = sk.sorte and js.n >= 2
    left join stich ge on ge.sorte is null
)
select sorte, mittel,
       -- Ohne Streuung (n < 2) gibt es keinen Bereich: dann gilt der Punktwert
       -- für alle drei Szenarien. greatest()/least() würden NULL still zu 0
       -- bzw. 1 machen und damit einen Bereich vortäuschen, den es nicht gibt.
       case when sd is null or n < 2 then mittel
            else greatest(mittel - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then mittel
            else least(mittel + 1.96 * sd / sqrt(n), 1) end    as oben,
       n, basis
  from eff;

-- ---------- Überfüllung (Buch B, Weg 2) -----------------------------------
-- Fixpreis je Kiste ab 8 kg, real 8.1–8.5 → der Überschuss ist verschenkte
-- Ware. Gemessen wird der Überschuss über n Kisten; hier auf eine Kiste
-- heruntergerechnet.
create view v_koeff_ueberfuellung with (security_invoker = true) as
with roh as (
  select wert, n_kisten, wert / nullif(n_kisten, 0) as je_kiste
    from marge_messung where art = 'ueberfuellung' and gemessen and n_kisten > 0
), s as (
  select count(*)::int as n,
         sum(wert) / nullif(sum(n_kisten), 0) as kg_pro_kiste,
         stddev_samp(je_kiste)                as sd
    from roh
)
select n, kg_pro_kiste, sd,
       case when sd is null or n < 2 then kg_pro_kiste
            else greatest(kg_pro_kiste - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then kg_pro_kiste
            else kg_pro_kiste + 1.96 * sd / sqrt(n) end              as oben
  from s;


-- Wie viele Beobachtungen stecken hinter dem Schimmelanteil für diese
-- Lagerdauer? Gehört in den aufklappbaren Rechenweg auf Ebene 3.
create or replace function schimmel_n(p_lagertage numeric)
returns int language sql stable as $$
  select coalesce((select k.n from v_schimmel_kurve k
                    where k.von <= p_lagertage and k.n > 0
                    order by k.von desc limit 1), 0);
$$;
