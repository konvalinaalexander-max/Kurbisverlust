-- 0113 — Demeter, wenn je als Demeter geliefert; das Lager je Charge und Artikel
--
-- WARUM
--
-- Der Betrieb am 12. Oktober, nach dem Einspielen von 0112: „Lager nach
-- Artikel … 0 Kilo Demeter und 0 Kilogramm Knospe … alle Label unbekannt.
-- Ich glaube, das könntest du eigentlich herausfinden: … wir haben einen
-- Artikel verkauft als Demeter … und es kommt von dieser Charge. Dann kannst
-- du daraus schliessen, diese Charge ist ein Demeter-Feld. … Das Demeter kann
-- ja auch Knospe sein, aber es ist dann ein Demeter-Feld. … Knospe ist
-- einfach alles bei uns, das nicht Demeter ist."
--
-- Auf den Daten des Betriebs (gelesen am 12. Oktober) kannte 0112 das Label
-- von 26 der 42 Chargen — 16 Chargen sind noch nie verkauft worden. Und die
-- Mehrheit der Zeilen entschied: Eine Demeter-Charge, die öfter als Knospe
-- verkauft wurde, wäre Knospe geworden.
--
-- 1. Das Label je Charge (v_charge_label) folgt jetzt der Regel des
--    Betriebs: die Stammdaten vor allem; sonst Demeter, sobald Perigon die
--    Charge einmal als Demeter geliefert hat (LiefPrsGrpName D — oder, wo
--    das fehlt, als Demeter verkauft); sonst Knospe, wenn Perigon sie als
--    Knospe kennt; sonst wie die anderen Chargen desselben Produzenten
--    (Schlag: ein Betrieb, der eine Charge als Demeter geliefert hat, ist
--    ein Demeter-Betrieb); sonst
--    Knospe, angenommen — und es heisst so. Eine Zeile, die als Demeter
--    verkauft, aber als Knospe geliefert wurde, macht die Charge nicht zu
--    Demeter: Sie steht als Widerspruch da (n_widerspruch), zum Prüfen.
-- 2. artikel_einordnen kennt die Preisgruppen, wie Perigon sie schreibt:
--    CH-K, KAdR, Kz sind Knospe. Bis 0112 waren es nur K und KZ — CH-K blieb
--    unbekannt, und die lose als Knospe verkauften Kürbisse fehlten im Filter
--    „nur Knospe".
-- 3. artikel_lager_charge(h): dasselbe Verkaufsfähige je Artikel, aber je
--    Charge — damit ein Klick auf „Knirps klein · Demeter" zeigt, aus welchen
--    Chargen die Zahl besteht. artikel_lager(h) zählt jetzt daraus zusammen:
--    eine Rechnung, zwei Sichten.
-- 4. Der Anstieg des Palox-Anteils gilt erst, wenn er sicher ist (Abschnitt 4).

-- =====================================================================
-- 1. Preisgruppen: CH-K, KAdR, Kz sind Knospe
-- =====================================================================
create or replace function artikel_einordnen(p_artikel text, p_preisgruppe text default null)
returns table (gruppe text, groesse text, label text)
language sql immutable set search_path = public as $$
  select case when a ~ '(knirps|potimarron|hokkaido|kuri)' then 'Knirps'
              when a ~ 'butternu' then 'Butternut'
              when a ~ '(butterkin|muskat|muscat)' then 'Butterkin/Muskat'
              when a ~ '(kobocha|kabocha)' then 'Kabocha'
              when a ~ 'mandarin' then 'Mandarin'
              when a ~ '\mmix\M' then 'Mix'
              when a ~ 'k(ü|u|ue)rb' then 'andere'
         end,
         case when a ~ '(gross|\mgros\M|\mgr\.)' then 'gross'
              when a ~ '(klein|\mkl\.)' then 'klein'
              else 'lose' end,
         -- Die Preisgruppe des Auftrags zuerst: D, DU (Demeter); K, KZ, CH-K,
         -- KAdR (Knospe). Andere (SG …) sagen nichts — dann der Name.
         case when upper(coalesce(p_preisgruppe, '')) like 'D%' then 'D'
              when upper(coalesce(p_preisgruppe, '')) ~ '^(K|CH-K)' then 'K'
              when a ~ '(demeter|\mdem\M)' then 'D'
              when a ~ 'knospe' then 'K'
         end
    from (select lower(coalesce(p_artikel, '')) as a) t
$$;
comment on function artikel_einordnen(text, text) is
  'Ein Verkaufsartikel aus Perigon eingeordnet: Artikelgruppe, Grösse (gross, klein, lose) und Label (D/K, aus der Preisgruppe — D…: Demeter; K…, CH-K: Knospe —, sonst aus dem Namen) — 0112, Preisgruppen seit 0113.';
revoke all on function artikel_einordnen(text, text) from public;
grant execute on function artikel_einordnen(text, text) to authenticated;

-- =====================================================================
-- 2. Das Label je Charge: einmal Demeter, Demeter
-- =====================================================================
-- Spalten wie in 0112 (charge_nr, label, quelle, gemischt, n_d, n_k), dazu
-- n_widerspruch. quelle: Stammdaten · Perigon · Produzent · angenommen.
create or replace view v_charge_label with (security_invoker = true) as
with zeile as (
  -- Jede Perigon-Zeile, die eine Lieferung der Charge wurde: wie Perigon die
  -- Charge geliefert hat (LiefPrsGrpName) und als was sie verkauft wurde.
  select l.charge_nr,
         case when upper(coalesce(z.liefer_label, '')) like 'D%' then 'D'
              when upper(coalesce(z.liefer_label, '')) ~ '^(K|CH-K)' then 'K' end as geliefert,
         e.label as verkauft
    from lieferung l
    join lieferung_import li on li.lieferung_id = l.id
    join ausgang_zeile z on z.id = li.zeile_id
   cross join lateral artikel_einordnen(z.artikel, z.preisgruppe) e
   where l.charge_nr is not null
), perigon as (
  select charge_nr,
         count(*) filter (where coalesce(geliefert, verkauft) = 'D')::int as n_d,
         count(*) filter (where coalesce(geliefert, verkauft) = 'K')::int as n_k,
         count(*) filter (where geliefert = 'K' and verkauft = 'D')::int as n_widerspruch
    from zeile
   group by charge_nr
), eigen as (
  select c.nr as charge_nr, c.schlag,
         coalesce(c.label, case when p.n_d > 0 then 'D' when p.n_k > 0 then 'K' end) as label,
         case when c.label is not null then 'Stammdaten'
              when p.n_d > 0 or p.n_k > 0 then 'Perigon' end as quelle,
         p.n_d, p.n_k, p.n_widerspruch
    from charge c
    left join perigon p on p.charge_nr = c.nr
), produzent as (
  -- Ein Betrieb ist Demeter oder Knospe, nicht jede Charge für sich: Was ein
  -- Produzent je als Demeter geliefert hat, gilt für seine anderen Chargen.
  select schlag, case when bool_or(label = 'D') then 'D' else 'K' end as label
    from eigen
   where label is not null and nullif(trim(schlag), '') is not null
   group by schlag
)
select e.charge_nr,
       coalesce(e.label, pr.label, 'K') as label,
       coalesce(e.quelle, case when pr.label is not null then 'Produzent' else 'angenommen' end) as quelle,
       coalesce(e.n_d, 0) > 0 and coalesce(e.n_k, 0) > 0 as gemischt,
       coalesce(e.n_d, 0) as n_d,
       coalesce(e.n_k, 0) as n_k,
       coalesce(e.n_widerspruch, 0) as n_widerspruch
  from eigen e
  left join produzent pr on pr.schlag = e.schlag;
comment on view v_charge_label is
  'Je Charge Demeter (D) oder Knospe (K) — seit 0113 nach der Regel des Betriebs: Stammdaten; sonst D, sobald Perigon sie einmal als Demeter geliefert (oder, ohne Lieferlabel, verkauft) hat; sonst K aus Perigon; sonst wie die anderen Chargen desselben Schlags (Produzent); sonst K, angenommen („Knospe ist alles, das nicht Demeter ist"). gemischt: beide geliefert; n_widerspruch: als Demeter verkauft, aber als Knospe geliefert — zum Prüfen.';
grant select on v_charge_label to authenticated;

-- =====================================================================
-- 3. Das Lager je Charge und Artikel — eine Rechnung, zwei Sichten
-- =====================================================================
-- Die Teile ungerundet, je Charge (wie bis 0112 im Innern von artikel_lager):
-- das Verkaufsfähige der Prognose, nach der Gewichtsverteilung der
-- Sortier-CSV auf die Artikelkaliber geteilt.
create or replace function artikel_lager_teile(p_h integer)
returns table (charge_nr int, sorte text, artikelgruppe text, label text, groesse text,
               kg numeric, g_mittel numeric, h int, datum date)
language sql stable security definer set search_path = public as $$
with prognose as (
  select p.schluessel::int as charge_nr, c.sorte, p.h, p.datum, p.verkaufsfaehig_kg,
         q.basis, q.schluessel as q_schluessel
    from erg_prognose p
    join charge c on c.nr = p.schluessel::int
    left join lager_schluessel() q on q.charge_nr = c.nr
   where p.gruppe = 'charge' and p.h = p_h and p.verkaufsfaehig_kg > 0
), zuordnung as (
  select p.*, g.artikelgruppe, l.label
    from prognose p
    left join v_sorte_artikelgruppe g on g.sorte = p.sorte
    left join v_charge_label l on l.charge_nr = p.charge_nr
), verteilung as (
  select w.basis, w.schluessel, w.sorte, w.anzahl, w.g::numeric as g
    from kuerbis_stichtag(p_h) w
   where exists (select 1 from zuordnung z where z.basis = w.basis and z.q_schluessel = w.schluessel)
), mit_klasse as (
  select v.basis, v.schluessel,
         coalesce(k.groesse, case when ak.n = 0 then 'lose'
                                  when v.g < ak.min_von then 'darunter'
                                  when v.g >= ak.max_bis then 'darueber'
                                  else 'dazwischen' end) as groesse,
         v.anzahl, v.g
    from verteilung v
    left join v_sorte_artikelgruppe sg on sg.sorte = v.sorte
    left join lateral (select count(*) as n, min(a.von_g) as min_von, max(a.bis_g) as max_bis
                         from artikel_kaliber a where a.gruppe = sg.artikelgruppe) ak on true
    left join artikel_kaliber k on k.gruppe = sg.artikelgruppe and v.g >= k.von_g and v.g < k.bis_g
), anteile as (
  select m.basis, m.schluessel, m.groesse,
         sum(m.anzahl * m.g) / nullif(sum(sum(m.anzahl * m.g)) over (partition by m.basis, m.schluessel), 0) as anteil,
         sum(m.anzahl * m.g) / nullif(sum(m.anzahl), 0) as g_mittel
    from mit_klasse m
   group by m.basis, m.schluessel, m.groesse
)
select z.charge_nr, z.sorte, z.artikelgruppe, z.label,
       coalesce(a.groesse, 'ohne Verteilung') as groesse,
       case when a.anteil is null then z.verkaufsfaehig_kg else z.verkaufsfaehig_kg * a.anteil end as kg,
       a.g_mittel, z.h, z.datum
  from zuordnung z
  left join anteile a on a.basis = z.basis and a.schluessel = z.q_schluessel
$$;
comment on function artikel_lager_teile(integer) is
  'Die ungerundeten Teile hinter artikel_lager und artikel_lager_charge: je Charge das Verkaufsfähige in h Tagen, nach den Artikelkalibern ihrer Gruppe geteilt (0113; bis 0112 im Innern von artikel_lager).';
revoke all on function artikel_lager_teile(integer) from public;

create or replace function artikel_lager_charge(p_h integer)
returns table (charge_nr int, sorte text, artikelgruppe text, label text, groesse text,
               von_g int, bis_g int, stueck_je_kiste int,
               kg numeric, stueck numeric, kisten numeric, g_mittel numeric, h int, datum date)
language sql stable security definer set search_path = public as $$
  select t.charge_nr, t.sorte, t.artikelgruppe, t.label, t.groesse, k.von_g, k.bis_g, k.stueck_je_kiste,
         zahl(t.kg, 2, 1e12)::numeric(14,2),
         zahl(t.kg * 1000 / nullif(t.g_mittel, 0), 0, 1e12)::numeric(14,0),
         zahl(t.kg * 1000 / nullif(t.g_mittel, 0) / nullif(k.stueck_je_kiste, 0), 0, 1e12)::numeric(14,0),
         zahl(t.g_mittel, 0, 1e6)::numeric(10,0),
         t.h, t.datum
    from artikel_lager_teile(p_h) t
    left join artikel_kaliber k on k.gruppe = t.artikelgruppe and k.groesse = t.groesse
$$;
comment on function artikel_lager_charge(integer) is
  'Das Verkaufsfähige in h Tagen je Charge und Artikel (Gruppe, Label, Grösse) — dieselben Teile wie artikel_lager(h), nur nicht zusammengezählt: woraus „Knirps klein · Demeter" besteht (0113).';
revoke all on function artikel_lager_charge(integer) from public;
grant execute on function artikel_lager_charge(integer) to authenticated;

create or replace function artikel_lager(p_h integer)
returns table (artikelgruppe text, label text, groesse text, von_g int, bis_g int, stueck_je_kiste int,
               kg numeric, stueck numeric, kisten numeric, g_mittel numeric,
               n_chargen int, chargen int[], h int, datum date)
language sql stable security definer set search_path = public as $$
select j.artikelgruppe, j.label, j.groesse, k.von_g, k.bis_g, k.stueck_je_kiste,
       zahl(sum(j.kg), 2, 1e12)::numeric(14,2),
       zahl(sum(j.kg * 1000 / nullif(j.g_mittel, 0)), 0, 1e12)::numeric(14,0),
       zahl(sum(j.kg * 1000 / nullif(j.g_mittel, 0)) / nullif(max(k.stueck_je_kiste), 0), 0, 1e12)::numeric(14,0),
       zahl(sum(j.kg) * 1000 / nullif(sum(j.kg * 1000 / nullif(j.g_mittel, 0)), 0), 0, 1e6)::numeric(10,0),
       count(distinct j.charge_nr)::int, array_agg(distinct j.charge_nr order by j.charge_nr),
       max(j.h)::int, max(j.datum)
  from artikel_lager_teile(p_h) j
  left join artikel_kaliber k on k.gruppe = j.artikelgruppe and k.groesse = j.groesse
 group by j.artikelgruppe, j.label, j.groesse, k.von_g, k.bis_g, k.stueck_je_kiste
$$;
comment on function artikel_lager(integer) is
  'Das Verkaufsfähige in h Tagen je Artikelgruppe, Label (D/K) und Grösse (klein, gross, stueck; darunter/darueber: in keinem Artikelkaliber; lose: Gruppe ohne Kaliber; ohne Verteilung: keine Sortier-CSV) — dieselbe Masse wie lager_kaliber(h), nach den Artikelkalibern geteilt; Stück = kg ÷ mittleres Gewicht der Klasse (0112). Seit 0113 aus artikel_lager_teile, wie artikel_lager_charge.';
revoke all on function artikel_lager(integer) from public;
grant execute on function artikel_lager(integer) to authenticated;

-- =====================================================================
-- 4. Der Anstieg gilt erst, wenn er sicher ist
-- =====================================================================
-- Der Betrieb am 12. Oktober: „bei nur Waschen hast du 2 % plus 1,6 Punkte
-- pro Woche … wie du auf diese 2 % kommst, macht null Sinn" — und: „das ist
-- ein genereller Ausschuss von einer x-Prozentzahl, weil einfach Hagelschaden
-- dabei ist oder andere Mängel, und dann wird dieser x-Wert mit der Zeit
-- grösser, weil Faules dazukommt. Aber selbst wenn du heute erntest, heute
-- ins Lager tust und morgen sortierst, wirst du einen Ausschuss haben."
-- Die 2 % waren das Mittel (10,5 % bei 36 Tagen Lagerdauer), um einen
-- Anstieg auf null Tage zurückgerechnet, dessen Bereich von −2,5 bis +5,8 %
-- je Woche reicht: Ob das Waschen mit der Zeit mehr aussortiert, ist noch
-- nicht zu sehen. Bis es sicher ist (untere Grenze des 95-%-Bereichs über
-- 0), gilt der Anstieg als 0 und der Grundausschuss ist das gemessene Mittel
-- — für frische wie für lange gelagerte Ware. Wird er sicher, kommt er dazu.
-- Die Regel ist eine eigene Funktion mit vier Werten; die mit dreien (die
-- Mindestzahl Arbeiten und die Spanne, 0111) bleibt und wird hier benutzt.
create or replace function palox_anstieg(p_roh numeric, p_n_paar int, p_spanne int, p_unten numeric) returns numeric
language sql immutable as $$
  select case when public.palox_anstieg(p_roh, p_n_paar, p_spanne) is null then null
              when p_roh > 0 and p_unten > 0 then p_roh
              else 0 end
$$;
comment on function palox_anstieg(numeric, integer, integer, numeric) is
  'Der Anstieg je Woche, der gilt (seit 0113): leer wie palox_anstieg(roh, n, spanne); sonst der gemessene, wenn er positiv und sicher ist (untere Grenze des 95-%-Bereichs über 0), sonst 0.';
revoke all on function palox_anstieg(numeric, integer, integer, numeric) from public;
grant execute on function palox_anstieg(numeric, integer, integer, numeric) to authenticated;

-- Die Kennzahl je Station: wie in 0111, der Anstieg nach der Regel oben.
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

comment on function palox_station_kennzahl(date, date) is
  'Die Kennzahl je Station (0105, Anstieg seit 0111): Mittel, Median, letzte vier Wochen, und der Anstieg des Palox-Anteils je Woche Lagerdauer — innerhalb der Sorten gerechnet, nie negativ, bekannt ab fünf Arbeiten in Sorten mit zwei Arbeiten und drei Wochen Spanne der Lagerdauern; seit 0113 gilt er erst, wenn er sicher ist (sonst 0, der Grundausschuss ist dann das Mittel).';
revoke all on function palox_station_kennzahl(date, date) from public;
grant execute on function palox_station_kennzahl(date, date) to authenticated;

-- =====================================================================
-- 5. Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 113 $$;
