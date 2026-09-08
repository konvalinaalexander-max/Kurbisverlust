-- =====================================================================
-- 0060 — Punktuell erfasst, vollständig gerechnet
-- Kürbis-Verlust-Tracking
--
-- WOZU DAS DA IST
--
-- Der Betrieb hat am 8. September klargestellt, was die App wissen kann und
-- was nicht: Vollständig sind nur der Wareneingang (Erntejournal) und der
-- Warenausgang (Lieferscheine). Was in der Halle passiert, wird punktuell
-- erfasst — vielleicht jede zehnte Arbeit. Aus Arbeiten kommen Raten,
-- nie Mengen. Bis 0059 teilte die Kaskade die Eingangsmasse trotzdem nach
-- den *gezählten* Arbeiten in „ausgelagert" und „im Lager" — eine Annahme,
-- die bei punktueller Erfassung schlicht falsch ist. Jetzt gilt:
--
--   im Lager = Eingang − das, was hinter den Lieferungen steckt.
--
-- Was hinter einer Lieferung steckt, rechnet die Kaskade rückwärts: die
-- gelieferte Masse geteilt durch den verkaufsfähigen Anteil bei dem Alter,
-- das die Ware am Liefertag hatte. Jeder Eingangstag einer Charge trägt
-- dazu seinen Anteil am Eingang bei — es gibt kein Zuerst-rein-zuerst-raus,
-- und die App weiss nicht, welche Palette gegangen ist.
--
-- Dazu, was die Halle wirklich hergibt (docs/ABLAUF.md, ABMACHUNGEN AB-23 ff.):
--   · Zwei Stationen: Sortiermaschine und Waschstrasse. „Waschen + Sortieren"
--     ist die Waschstrasse mit Sortieren am Band dahinter — derselbe Palox.
--   · Der Palox-Stand kann fallen (zwischendurch geleert). Der Arbeiter wird
--     nicht gefragt; die Menge dieser Arbeit ist dann unbekannt, nicht null.
--   · Am Ende jeder Arbeit nach dem Waschen wird gefragt, nach welchem System
--     die Kisten gefüllt werden: Kiste ab x kg, x Stück eines Kalibers, oder
--     anderes. Nur die ersten beiden sind rechenbar.
--   · Beim Waschen + Sortieren steht das Eingangsgewicht auf dem Zettel; es
--     wird abgelesen, damit der Palox eine Masse als Nenner hat.
--   · Fax gibt es nach beiden Wegen; gezählt werden Paletten als Gesamtzahl,
--     das Faule wird kistenweise gewogen, freiwillig die Tage seit dem Waschen.
--   · Beim Waschen aus Kaliber-Kisten steht das Sortierdatum auf der Kiste;
--     es wird je Kiste mitgezählt, „kein Datum" ist eine Antwort.
-- =====================================================================

-- ---------- 1. Zwei Stationen, ein Palox je Station ----------------------
-- Die Waschstrasse hat einen Palox — ob dahinter von Hand sortiert wird oder
-- nicht. Vor 0060 hatte „waschen_sortieren" einen eigenen Stand, und zwei
-- Ablesungen derselben Waage verzahnten sich zu falschen Differenzen.
create or replace function palox_station(p_station station) returns station
language sql immutable parallel safe as $$
  -- voll qualifiziert: die Funktion wird in Sichten eingebettet und muss auch
  -- mit leerem Suchpfad rechnen (Prüfblock „Suchpfad")
  select case when p_station = 'waschen_sortieren'::public.station then 'waschen'::public.station else p_station end
$$;
comment on function palox_station(station) is
  'Welcher Palox zu einer Station gehört: die Waschstrasse (waschen und '
  'waschen_sortieren) teilt sich einen, die Sortiermaschine hat ihren eigenen (0060).';
revoke all on function palox_station(station) from public;
grant execute on function palox_station(station) to authenticated;

create or replace function palox_letzter_stand(p_station station)
returns numeric language sql stable as $$
  select s.palox_stand_kg
    from public.schimmel_messung s
    join public.auftrag a on a.id = s.auftrag_id
   where s.palox_stand_kg is not null and s.gemessen
     and public.palox_station(a.station) = public.palox_station(p_station)
   order by s.ts desc, s.id desc limit 1;
$$;

-- Ist der Stand gefallen, wurde der Palox zwischendurch geleert — und wie
-- viel vorher noch dazukam, weiss niemand. Die Menge dieser Ablesung ist
-- dann unbekannt (NULL), nicht der neue Stand und nicht null.
create or replace view v_palox_stand with (security_invoker = true) as
select s.id, s.auftrag_id, s.ts, s.palox_stand_kg, s.kg,
       lag(s.palox_stand_kg) over w                                as vorher,
       case
         when s.palox_geleert then greatest(s.palox_stand_kg - palox_tara_kg(), 0)
         when lag(s.palox_stand_kg) over w is null then greatest(s.palox_stand_kg - palox_tara_kg(), 0)
         when s.palox_stand_kg < lag(s.palox_stand_kg) over w then null
         else s.palox_stand_kg - lag(s.palox_stand_kg) over w
       end                                                          as differenz,
       (s.palox_geleert
        or (lag(s.palox_stand_kg) over w is not null
            and s.palox_stand_kg < lag(s.palox_stand_kg) over w))   as zwischendurch_geleert,
       palox_station(a.station)                                     as station
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
 where s.palox_stand_kg is not null and s.gemessen
window w as (partition by palox_station(a.station) order by s.ts, s.id)
 order by palox_station(a.station), s.ts, s.id;
comment on view v_palox_stand is
  'Die Waagenstände je Palox der Reihe nach (Sortiermaschine, Waschstrasse). '
  'differenz ist die Menge seit der letzten Ablesung; ist der Stand gefallen, '
  'ist sie unbekannt (NULL) — der Palox wurde geleert, ohne dass jemand die '
  'Menge davor kennt (0060).';

-- Eine Arbeit mit einer unbekannten Ablesung hat eine unbekannte Menge: ein
-- Teil ihres Faulen ist nirgends gemessen. Sie fällt aus der Schimmelkurve —
-- lieber ein Punkt weniger als ein zu kleiner.
create or replace view v_schimmel_menge with (security_invoker = true) as
select s.auftrag_id,
       sum(case when s.palox_stand_kg is null then s.kg else p.differenz end)::numeric as kg,
       count(*)::int as n_ablesungen
  from schimmel_messung s
  left join v_palox_stand p on p.id = s.id
 where s.gemessen
 group by s.auftrag_id
having bool_and(s.palox_stand_kg is null or p.differenz is not null);
comment on view v_schimmel_menge is
  'Faules je Arbeit. Palox-Ablesungen werden als Differenz gerechnet, '
  'Kistenwägungen als Netto. Eine Arbeit, bei der eine Ablesung unbekannt '
  'ist (Stand gefallen), hat hier keine Zeile: ihre Menge ist unbekannt (0060).';

-- ---------- 2. Was die Masken neu wissen wollen -------------------------
-- Das Kistensystem nach dem Waschen: Kiste ab x kg, x Stück eines Kalibers,
-- oder etwas anderes. Beim Waschen, Waschen + Sortieren und Fax gefragt.
alter table auftrag add column if not exists kistensystem text
  check (kistensystem in ('kiste_ab', 'stueck', 'anderes'));
alter table auftrag add column if not exists soll_kg_pro_kiste numeric(6,2)
  check (soll_kg_pro_kiste > 0);
alter table auftrag add column if not exists stueck_je_kiste int
  check (stueck_je_kiste > 0);
comment on column auftrag.kistensystem is
  'Wie die Kisten nach dem Waschen gefüllt werden: kiste_ab (bis zum Sollgewicht '
  'soll_kg_pro_kiste), stueck (stueck_je_kiste Kürbisse eines Kalibers) oder '
  'anderes. Nur die ersten beiden sind rechenbar — bei „anderes" wird keine '
  'fertige Palette verlangt (0060).';
-- Fax: die Palettenzahl als Gesamtzahl am Ende, und wie lange die Ware seit
-- dem Waschen stand (freiwillig).
alter table auftrag add column if not exists paletten_gesamt int
  check (paletten_gesamt >= 0);
alter table auftrag add column if not exists tage_seit_waschen int
  check (tage_seit_waschen >= 0);
comment on column auftrag.paletten_gesamt is
  'Fax: wie viele Paletten gemacht wurden, als Gesamtzahl am Ende eingetragen. '
  'Die Masse folgt aus der gemessenen Nettomasse einer fertigen Palette (0060).';
comment on column auftrag.tage_seit_waschen is
  'Fax, freiwillig: wie lange die Ware seit dem Waschen stand (Tage).';

-- Waschen + Sortieren: das Eingangsgewicht steht auf dem Zettel der Palette.
alter table auftrag_palette add column if not exists brutto_zettel_kg numeric(8,2)
  check (brutto_zettel_kg > 0);
comment on column auftrag_palette.brutto_zettel_kg is
  'Bruttogewicht vom Palettenzettel (Eingangsgewicht), beim Waschen + Sortieren '
  'abgelesen. Damit hat der Palox dieser Arbeit einen Nenner. Das Netto findet '
  'die Auswertung über die Palette im Wareneingang (gleiche Charge, gleiches '
  'Datum, gleiches Brutto), sonst über die mittlere Tara der Charge (0060).';

-- Waschen aus Kaliber-Kisten: das Sortierdatum steht auf der Kiste. Es wird
-- mitgezählt — je Kaliber und Datum ein Zähler; „kein Datum auf der Kiste"
-- ist eine Antwort, keine Lücke.
alter table auftrag_gebinde add column if not exists sortierdatum date;
alter table auftrag_gebinde add column if not exists datum_fehlt boolean not null default false;
alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_auftrag_id_kaliber_idx_key;
alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_eindeutig;
alter table auftrag_gebinde add constraint auftrag_gebinde_eindeutig
  unique nulls not distinct (auftrag_id, kaliber_idx, sortierdatum);
comment on column auftrag_gebinde.sortierdatum is
  'Beim Waschen: das Sortierdatum, das die Arbeiter beim Sortieren auf die Kiste '
  'schreiben. NULL beim Sortieren (dort gibt es noch keins) oder wenn keins auf '
  'der Kiste steht — dann sagt datum_fehlt, dass gefragt wurde (0060).';

-- Ältere Wasch-Arbeiten hatten das Sortierdatum als Antwort am Abschluss.
update auftrag_gebinde g
   set sortierdatum = x.datum
  from (select distinct on (auftrag_id) auftrag_id, wert::date as datum
          from auftrag_angabe
         where schluessel = 'sortierdatum' and wert ~ '^\d{4}-\d{2}-\d{2}$'
         order by auftrag_id, ts desc) x
 where x.auftrag_id = g.auftrag_id and g.sortierdatum is null;

-- Fertige Palette bei Stück-Kisten: welches Kaliber, damit sich das Gewicht
-- mit der Erwartung aus der Sortier-CSV vergleichen lässt.
alter table ausgang_wiegung add column if not exists kaliber_idx int;
comment on column ausgang_wiegung.kaliber_idx is
  'Bei Stück-Kisten: das Kaliber der gewogenen Palette (Index in den Bändern der '
  'Fassung; −2 = eigenes Kaliber der Arbeit). Daraus die Erwartung je Kiste aus '
  'der Sortier-CSV (0060).';

-- Ältere Arbeiten, die ausdrücklich als „Kiste ab x kg" liefen, bekommen das
-- Kistensystem nachgetragen — das ist keine Annahme, die Fassung sagt es.
update auftrag a
   set kistensystem = 'kiste_ab', soll_kg_pro_kiste = s.soll_kg_pro_kiste
  from sortierschema s
 where s.id = a.sortierschema_id and s.art = 'kiste' and s.soll_kg_pro_kiste > 0
   and a.kistensystem is null;

-- ---------- 3. Die Masse je gezählter Palette: Zettel dazu ---------------
-- Reihenfolge der Quellen: gewogen · Zettel (über den Wareneingang gefunden
-- oder mit der mittleren Tara der Charge) · Palette · Tagesmittel · Chargenmittel.
create or replace view v_auftrag_palette_masse with (security_invoker = true) as
with wiegung as materialized (
  select vw.id,
         zahl(vw.brutto_damals_kg - coalesce(vw.kisten, 0) * g.tara_kg_pro_kiste
              - coalesce(g.tara_kg_palette, 0), 2, 1e8)::numeric(10,2) as netto_damals_kg,
         vw.eingangsdatum
    from verdunstung_wiegung vw
    left join gebinde g on g.art = vw.gebindeart
), datum_mittel as materialized (
  select charge_nr, eingangsdatum, avg(netto_kg) as netto_mittel
    from v_palette group by charge_nr, eingangsdatum
), charge_mittel as materialized (
  select charge_nr, avg(netto_kg) as netto_mittel,
         avg(brutto_kg - netto_kg) filter (where netto_kg is not null) as tara_mittel
    from v_palette group by charge_nr
), charge_datum as materialized (
  select charge_nr, eingangsdatum_mittel from v_charge_rueckgrat
), zettel as materialized (
  -- Das Brutto vom Zettel: dieselbe Palette im Wareneingang (Charge, Datum,
  -- Brutto) hat ein Netto; sonst Brutto minus mittlere Tara der Charge.
  select ap.id,
         coalesce(pe.netto_kg,
                  zahl(ap.brutto_zettel_kg - cm.tara_mittel, 2, 1e8)::numeric(10,2)) as netto_kg,
         (pe.id is not null) as exakt
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join lateral (
      select p.id, p.netto_kg from v_palette p
       where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum
         and p.brutto_kg = ap.brutto_zettel_kg and p.netto_kg is not null
       order by p.id limit 1) pe on true
    left join charge_mittel cm on cm.charge_nr = a.charge_nr
   where ap.brutto_zettel_kg is not null
)
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(w.netto_damals_kg, z.netto_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel) as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) as eingangsdatum,
       case when w.netto_damals_kg is not null then 'gewogen'
            when z.netto_kg is not null and z.exakt then 'zettel'
            when z.netto_kg is not null then 'zettel-charge-tara'
            when p.netto_kg is not null then 'palette'
            when d.netto_mittel is not null then 'datum-mittel'
            when cm.netto_mittel is not null then 'charge-mittel'
            else 'unbekannt' end::text                                                 as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join wiegung w on w.id = ap.wiegung_id
  left join zettel z on z.id = ap.id
  left join v_palette p on p.id = ap.palette_id
  left join datum_mittel d on d.charge_nr = a.charge_nr and d.eingangsdatum = ap.eingangsdatum
  left join charge_mittel cm on cm.charge_nr = a.charge_nr
  left join charge_datum cd on cd.charge_nr = a.charge_nr;
comment on view v_auftrag_palette_masse is
  'Netto je gezählter Palette. Quellen der Reihe nach: gewogen, Brutto vom Zettel '
  '(über den Wareneingang gefunden oder mit der mittleren Tara der Charge), die '
  'bekannte Palette, das Tagesmittel, das Chargenmittel (0060).';

-- ---------- 4. Fertige Palette: Soll aus der Arbeit, Erwartung bei Stück ---
-- Das Sollgewicht steht jetzt an der Arbeit (kistensystem = kiste_ab); ältere
-- Arbeiten haben es in der Fassung. Bei Stück-Kisten gibt es kein Soll, aber
-- eine Erwartung: Stück × mittleres Gewicht des Kalibers aus der Sortier-CSV.
-- Die Erwartung ist keine verschenkte Marge — sie sagt nur, wo im Band die
-- Ware liegt.
create or replace view v_ausgang_kennzahl with (security_invoker = true) as
with band_mittel as (
  -- Mittleres Stückgewicht je Sorte und Kaliber aus allen Sortierläufen
  select c.sorte, sg.kaliber_idx,
         sum(sg.anzahl::bigint * sg.gewicht_g)::numeric / nullif(sum(sg.anzahl), 0) as gramm
    from sortier_gewicht sg
    join sortier_lauf l on l.id = sg.lauf_id
    join charge c on c.nr = l.charge_nr
   where sg.klasse = 'kaliber' and sg.kaliber_idx is not null
   group by c.sorte, sg.kaliber_idx
)
select w.id, w.auftrag_id, w.charge_nr, c.sorte, c.schlag, w.ts, w.brutto_kg, w.kisten,
       w.gebindeart, w.kuerbisse_pro_kiste, n.netto_kg,
       zahl(n.netto_kg / w.kisten, 3, 1e7)::numeric(10,3)                          as kg_pro_kiste,
       zahl(n.netto_kg / nullif(w.kisten * w.kuerbisse_pro_kiste, 0), 3, 1e7)::numeric(10,3) as kg_pro_kuerbis,
       s.soll::numeric                                                              as soll_kg_pro_kiste,
       zahl(case when s.soll is not null then n.netto_kg / w.kisten - s.soll end, 3, 1e7)::numeric(10,3)
                                                                                    as ueberfuellung_je_kiste,
       zahl(case when s.soll is not null then n.netto_kg - w.kisten * s.soll end, 2, 1e8)::numeric(10,2)
                                                                                    as ueberfuellung_kg,
       -- neu (0060)
       coalesce(a.kistensystem, case when ss.art = 'kiste' then 'kiste_ab' end)::text as kistensystem,
       w.kaliber_idx,
       e.stueck                                                                     as stueck_je_kiste,
       zahl(e.stueck * bm.gramm / 1000.0, 3, 1e7)::numeric(10,3)                    as erwartet_kg_pro_kiste,
       zahl(n.netto_kg / w.kisten - e.stueck * bm.gramm / 1000.0, 3, 1e7)::numeric(10,3)
                                                                                    as abweichung_je_kiste,
       zahl(bm.gramm, 0, 1e6)::numeric(8,0)                                         as band_mittel_g
  from ausgang_wiegung w
  join auftrag a on a.id = w.auftrag_id
  join charge c on c.nr = w.charge_nr
  left join gebinde g on g.art = w.gebindeart
  left join sortierschema ss on ss.id = a.sortierschema_id
  cross join lateral (
    select zahl(w.brutto_kg - w.kisten * g.tara_kg_pro_kiste - coalesce(g.tara_kg_palette, 0), 2, 1e8)::numeric(10,2) as netto_kg) n
  cross join lateral (
    select case when a.kistensystem = 'kiste_ab' then a.soll_kg_pro_kiste
                when a.kistensystem is null and ss.art = 'kiste' then ss.soll_kg_pro_kiste end as soll) s
  cross join lateral (
    select case when a.kistensystem = 'stueck' then coalesce(w.kuerbisse_pro_kiste, a.stueck_je_kiste) end as stueck) e
  left join band_mittel bm on bm.sorte = c.sorte
        and bm.kaliber_idx = case when w.kaliber_idx = -2 then null else coalesce(w.kaliber_idx, a.kaliber_idx) end
 where w.gemessen and a.abgebrochen_ts is null and n.netto_kg > 0;
comment on view v_ausgang_kennzahl is
  'Je fertiger Palette: Kilo je Kiste, der Überschuss über das Sollgewicht (nur '
  'Kiste ab x kg — sonst NULL) und bei Stück-Kisten die Erwartung je Kiste aus '
  'dem mittleren Stückgewicht des Kalibers in der Sortier-CSV (0060).';

-- Wie schwer ist eine fertige Palette netto? Je Sorte und Kistensystem aus
-- den gewogenen fertigen Paletten — der Nenner der Fax-Arbeit.
create or replace view v_koeff_palette_netto with (security_invoker = true) as
select k.sorte, k.kistensystem,
       count(*)::int                                            as n,
       zahl(avg(k.netto_kg), 2, 1e8)::numeric(10,2)             as netto_kg,
       zahl(stddev_samp(k.netto_kg), 2, 1e8)::numeric(10,2)     as sd,
       zahl(avg(k.kisten), 1, 1e6)::numeric(8,1)                as kisten
  from v_ausgang_kennzahl k
 group by grouping sets ((k.sorte, k.kistensystem), (k.sorte));
comment on view v_koeff_palette_netto is
  'Nettomasse einer fertigen Palette je Sorte und Kistensystem (kistensystem NULL: '
  'alle Systeme der Sorte). Daraus die Masse einer Fax-Arbeit: Paletten × Netto (0060).';
grant select on v_koeff_palette_netto to authenticated;

-- ---------- 5. Kisten je Kaliber: über die Sortierdaten summiert ----------
create or replace view v_auftrag_gebinde_masse with (security_invoker = true) as
with band as (
  select distinct s.sorte, i.idx as kaliber_idx,
         (s.kaliber_baender -> i.idx ->> 0)::int as von,
         (s.kaliber_baender -> i.idx ->> 1)::int as bis
    from sortierschema s
    cross join lateral generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) as i(idx)
   where s.art = 'kaliber' and s.kaliber_baender is not null
), gezaehlt as (
  select auftrag_id, kaliber_idx, sum(anzahl)::int as anzahl
    from auftrag_gebinde group by auftrag_id, kaliber_idx
)
select a.id as auftrag_id, g.kaliber_idx, g.anzahl,
       zahl(g.anzahl * k.kg_je_gebinde, 2, 1e10)::numeric(12,2) as kg,
       zahl(g.anzahl * k.unten, 2, 1e10)::numeric(12,2)         as kg_unten,
       zahl(g.anzahl * k.oben, 2, 1e10)::numeric(12,2)          as kg_oben,
       k.n                                                      as n_messungen
  from auftrag a
  join charge c on c.nr = a.charge_nr
  join gezaehlt g on g.auftrag_id = a.id
  left join lateral (
    select b.kaliber_idx from band b
     where g.kaliber_idx = -2 and b.sorte = c.sorte
       and b.von = a.kaliber_von_g and b.bis = a.kaliber_bis_g
     order by b.kaliber_idx limit 1
  ) e on true
  left join v_koeff_gebinde k
         on k.sorte = c.sorte
        and k.kaliber_idx = case when g.kaliber_idx = -2 then e.kaliber_idx else g.kaliber_idx end
 where a.station = 'waschen' and a.abgebrochen_ts is null;

-- v_koeff_gebinde: die gezählten Kisten je Kaliber summiert (mehrere
-- Sortierdaten je Kaliber sind seit 0060 möglich); Kisten ohne Kaliber (−1)
-- aus den fertigen Paletten der Arbeiten mit Sollgewicht.
create or replace view v_koeff_gebinde with (security_invoker = true) as
with gezaehlt as (
  select auftrag_id, kaliber_idx, sum(anzahl)::int as anzahl
    from auftrag_gebinde group by auftrag_id, kaliber_idx
), je_arbeit as (
  select a.id as auftrag_id, c.sorte, g.kaliber_idx, g.anzahl,
         (sum(sg.anzahl::bigint * sg.gewicht_g) / 1000.0)::numeric as kg
    from gezaehlt g
    join auftrag a       on a.id = g.auftrag_id and a.abgebrochen_ts is null
    join charge c        on c.nr = a.charge_nr
    join sortier_lauf l  on l.auftrag_id = a.id
    join sortier_gewicht sg on sg.lauf_id = l.id
                           and sg.klasse = 'kaliber'
                           and sg.kaliber_idx = g.kaliber_idx
   where a.station in ('sortieren', 'waschen_sortieren') and g.anzahl > 0
   group by a.id, c.sorte, g.kaliber_idx, g.anzahl
), s as (
  select sorte, kaliber_idx, count(*)::int as n,
         sum(kg) / nullif(sum(anzahl), 0)   as kg_je_gebinde,
         stddev_samp(kg / anzahl)           as sd
    from je_arbeit group by sorte, kaliber_idx
  union all
  select k.sorte, -1, count(*)::int,
         sum(k.netto_kg) / nullif(sum(k.kisten), 0),
         stddev_samp(k.kg_pro_kiste)
    from v_ausgang_kennzahl k
   where k.soll_kg_pro_kiste is not null or k.kistensystem = 'kiste_ab'
   group by k.sorte
)
select sorte, kaliber_idx, n,
       zahl(kg_je_gebinde, 3, 1e7)::numeric(10,3)                       as kg_je_gebinde,
       zahl(sd, 3, 1e7)::numeric(10,3)                                  as sd,
       zahl(case when sd is null or n < 2 then kg_je_gebinde
                 else greatest(kg_je_gebinde - t_quantil_95(n - 1) * sd / sqrt(n), 0)
            end, 3, 1e7)::numeric(10,3)                                 as unten,
       zahl(case when sd is null or n < 2 then kg_je_gebinde
                 else kg_je_gebinde + t_quantil_95(n - 1) * sd / sqrt(n)
            end, 3, 1e7)::numeric(10,3)                                 as oben
  from s where kg_je_gebinde is not null;

-- ---------- 6. Die Masse je Arbeit: Fax aus der Palettenzahl -------------
create or replace view v_auftrag_masse with (security_invoker = true) as
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten,
       coalesce(m.eingang_netto_kg, gb.kg, fp.kg)::numeric               as eingang_netto_kg,
       (case when m.masse_quelle <> 'fehlt' then m.masse_quelle
             when gb.kg is not null         then 'gebinde'
             when fp.kg is not null         then 'fax_paletten'
             else 'fehlt' end)::text                                    as masse_quelle,
       zahl(coalesce(m.lagertage,
         case when m.station = 'waschen'
              then (m.start_ts::date - date '2000-01-01')::numeric
                   - coalesce(se.tage_seit_epoche,
                              (r.eingangsdatum_mittel - date '2000-01-01')::numeric)
              else null end), 1, 1e9)::numeric(10,1)                    as lagertage,
       a.ist_fax
  from mv_auftrag_masse m
  join auftrag a on a.id = m.auftrag_id
  left join mv_sortier_eingang se on se.charge_nr = m.charge_nr
  left join v_charge_rueckgrat r  on r.charge_nr  = m.charge_nr
  left join (select auftrag_id, sum(kg) as kg from v_auftrag_gebinde_masse group by auftrag_id) gb
         on gb.auftrag_id = m.auftrag_id
  -- Fax (0060): Paletten × Nettomasse einer fertigen Palette derselben Sorte
  -- (gleiches Kistensystem, sonst alle Systeme der Sorte). Ohne gewogene
  -- fertige Palette bleibt die Masse unbekannt — nicht null.
  left join lateral (
    select zahl(a.paletten_gesamt * p.netto_kg, 2, 1e10)::numeric(12,2) as kg
      from v_koeff_palette_netto p
     where a.ist_fax and a.paletten_gesamt > 0 and p.sorte = m.sorte
       and (p.kistensystem = a.kistensystem or (p.kistensystem is null and a.kistensystem is distinct from 'anderes'))
     order by (p.kistensystem = a.kistensystem) desc nulls last limit 1
  ) fp on true;
comment on view v_auftrag_masse is
  'Masse je Arbeit aus vier Quellen: gewogene Paletten (oder Zettel), '
  'eingetippter Durchsatz, gezählte Kisten mal gemessenem Kistengewicht, beim '
  'Fax die Palettenzahl mal gemessener Palettenmasse (0060). ist_fax: kein Waschgang.';

-- ---------- 7. Die Kohorten: der Eingang je Tag, nicht das Zählen --------
-- Wie viel von einer Charge an welchem Tag kam, ist vollständig bekannt. Wie
-- viel davon noch liegt, weiss die App nicht aus dem Zählen — dazu wird zu
-- selten gezählt. Der Anteil eines Eingangstags am Bestand ist deshalb sein
-- Anteil am Eingang; n_verarbeitet und n_rest bleiben als das, was sie sind:
-- in der App gezählte Paletten, keine Mengen.
create or replace view v_charge_kohorte with (security_invoker = true) as
with gezaehlt as (
  select a.charge_nr,
         coalesce(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum) as eingangsdatum,
         count(*)::int                                                 as n
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join palette p on p.id = ap.palette_id
    left join verdunstung_wiegung w on w.id = ap.wiegung_id
   where a.abgebrochen_ts is null
     and a.station in ('sortieren', 'waschen_sortieren')
   group by a.charge_nr, coalesce(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum)
), je_datum as (
  select p.charge_nr, p.eingangsdatum, count(*)::int as n,
         avg(p.netto_kg) as netto_mittel
    from v_palette p group by p.charge_nr, p.eingangsdatum
), charge_netto as (
  select charge_nr, avg(netto_kg) as netto from v_palette group by charge_nr
)
select d.charge_nr, d.eingangsdatum,
       d.n                                                          as n_paletten,
       coalesce(g.n, 0)                                             as n_verarbeitet,
       greatest(d.n - coalesce(g.n, 0), 0)                          as n_rest,
       zahl(coalesce(d.netto_mittel, cn.netto), 2, 1e8)::numeric(10,2) as netto_je_palette,
       zahl(greatest(d.n - coalesce(g.n, 0), 0)
            * coalesce(d.netto_mittel, cn.netto), 2, 1e10)::numeric(12,2) as rest_kg,
       (current_date - d.eingangsdatum)                             as alter_heute,
       -- neu (0060): der Eingang dieses Tags
       zahl(d.n * coalesce(d.netto_mittel, cn.netto), 2, 1e10)::numeric(12,2) as eingang_kg
  from je_datum d
  join charge_netto cn on cn.charge_nr = d.charge_nr
  left join gezaehlt g on g.charge_nr = d.charge_nr and g.eingangsdatum = d.eingangsdatum;
comment on view v_charge_kohorte is
  'Je Charge und Eingangstag: wie viele Paletten kamen (eingang_kg), wie viele '
  'davon in der App mit diesem Zetteldatum gezählt wurden (n_verarbeitet — '
  'punktuell, keine Menge). Die Kaskade verteilt den Bestand nach eingang_kg (0060).';

create or replace view v_kohorte_anteil with (security_invoker = true) as
select charge_nr, eingangsdatum, n_rest, rest_kg,
       zahl(eingang_kg / nullif(sum(eingang_kg) over (partition by charge_nr), 0), 6, 1e4)::numeric(10,6) as anteil
  from v_charge_kohorte
 where eingang_kg > 0;
comment on view v_kohorte_anteil is
  'Der Anteil jedes Eingangstags am Eingang der Charge — und damit am Bestand '
  'und an jeder Lieferung: es gibt kein Zuerst-rein-zuerst-raus, und die App '
  'weiss nicht, welche Palette gegangen ist (0060).';

-- ---------- 8. Die Lieferungen je Charge und Eingangstag -----------------
-- Verkaufte Lieferungen sind der zweite vollständige Messwert. Jede wird auf
-- die Eingangstage ihrer Charge verteilt (Eingangsanteil); eine Lieferung
-- ohne Charge auf die Chargen der Sorte (Eingangsanteil). Das Alter am
-- Liefertag ist der Abstand zum Eingangstag.
create or replace view v_lieferung_kohorte with (security_invoker = true) as
with lief as (
  select l.id, l.datum, l.buch, l.masse_kg, c.charge_nr, c.anteil
    from v_lieferung_masse l
    cross join lateral (
      select l.charge_nr as charge_nr, 1::numeric as anteil where l.charge_nr is not null
      union all
      select r.charge_nr, r.eingang_netto_kg / sum(r.eingang_netto_kg) over ()
        from v_charge_rueckgrat r
       where l.charge_nr is null and r.sorte = l.sorte and r.eingang_netto_kg > 0
    ) c
   where l.masse_kg is not null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge')
  union all
  -- Der Vorlauf (AB-07): was vor dem Erfassungsbeginn schon ausgeliefert war.
  -- Ohne Datum gilt der Erfassungsbeginn aus den Einstellungen, sonst der
  -- letzte Eingangstag der Charge.
  select -cv.charge_nr, coalesce(
           (select nullif(wert #>> '{}', '')::date from einstellung where schluessel = 'erfassungsbeginn'),
           r.letzter_eingang),
         'verkauf', cv.ausgang_vor_app_kg, cv.charge_nr, 1
    from charge_vorlauf cv
    join v_charge_rueckgrat r on r.charge_nr = cv.charge_nr
   where cv.ausgang_vor_app_kg > 0
)
select f.charge_nr, k.eingangsdatum as kohorte, f.buch,
       zahl(sum(f.masse_kg * f.anteil * k.anteil), 2, 1e12)::numeric(14,2)      as masse_kg,
       zahl(sum(f.masse_kg * f.anteil * k.anteil * greatest(f.datum - k.eingangsdatum, 0))
            / nullif(sum(f.masse_kg * f.anteil * k.anteil), 0), 1, 1e5)::numeric(8,1) as alter_tage,
       count(distinct f.id)::int                                                as n_lieferungen,
       min(f.datum)                                                             as von,
       max(f.datum)                                                             as bis
  from lief f
  join v_kohorte_anteil k on k.charge_nr = f.charge_nr
 group by f.charge_nr, k.eingangsdatum, f.buch;
comment on view v_lieferung_kohorte is
  'Gelieferte Masse je Charge, Eingangstag und Buch (verkauf, marge), mit dem '
  'massegewichteten Alter am Liefertag. Grundlage der Rückrechnung in der '
  'Kaskade: was hinter einer Lieferung an Eingangsmasse steckt (0060).';
grant select on v_lieferung_kohorte to authenticated;

-- ---------- 9. Die Kaskade: „ausgelagert" kommt aus den Lieferungen ------
-- Die Basis der Kaskade heisst jetzt v_kaskade_basis: der Eingang je Charge
-- und, als Gegenproben, was aus Arbeiten bekannt ist (am Band, sortiert,
-- gewaschen). v_hochrechnung_basis ist ab jetzt das *Ergebnis*: was
-- ausgelagert ist und was liegt, aus den Lieferungen zurückgerechnet.
drop materialized view if exists mv_kaskade cascade;
drop view if exists v_hochrechnung_basis cascade;
drop view if exists v_kaskade_basis cascade;

create view v_kaskade_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung
                    where schluessel = 'saison_ende'), current_date) as bis
), je_station as (
  select charge_nr,
         sum(eingang_netto_kg) filter (where station = 'sortieren')          as sortiert_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen' and not ist_fax) as gewaschen_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren')  as hand_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren'
                                         and weg = 'hand')                   as kg_hand,
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
), kohorte as (
  select k.charge_nr,
         min(k.eingangsdatum)                                     as eingang_von,
         max(k.eingangsdatum)                                     as eingang_bis,
         count(*)::int                                            as n_eingangstage
    from v_charge_kohorte k
   group by k.charge_nr
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg                                                     as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       s.bis                                                                  as stichtag,
       r.n_paletten_mit_netto,
       -- Gegenproben aus den (punktuell) erfassten Arbeiten — keine Mengen
       -- für Überblick oder Ursachen, nur für Modell-gegen-CSV.
       coalesce(a.sortiert_kg, 0)                                             as sortiert_kg,
       coalesce(a.gewaschen_kg, 0)                                            as gewaschen_kg,
       coalesce(a.hand_kg, 0)                                                 as hand_kg,
       (coalesce(a.sortiert_kg, 0) * (1 - coalesce(a.anteil_gewaschen, 0)))    as wartet_kg,
       coalesce(a.anteil_gewaschen, 0)                                        as anteil_gewaschen,
       coalesce(a.kg_hand / nullif(coalesce(a.hand_kg, 0)
                                   + coalesce(a.sortiert_kg, 0), 0), 0)       as weg2_anteil,
       a.alter_band,
       coalesce(a.am_band_kg, 0)                                              as am_band_kg,
       k.eingang_von, k.eingang_bis, k.n_eingangstage
  from v_charge_rueckgrat r
  cross join stichtag s
  left join anteil a on a.charge_nr = r.charge_nr
  left join kohorte k on k.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;
comment on view v_kaskade_basis is
  'Eingang je Charge (vollständig, aus dem Erntejournal) und die Gegenproben aus '
  'den erfassten Arbeiten. Was ausgelagert ist und was liegt, steht hier nicht '
  'mehr — das rechnet die Kaskade aus den Lieferungen (v_hochrechnung_basis, 0060).';
grant select on v_kaskade_basis to authenticated;

create materialized view mv_kaskade as
with modell as materialized (
  select * from v_schimmel_modell
),
kurve as materialized (
  select von, anteil_mono, n from v_schimmel_kurve where n > 0
),
kohorten as materialized (
  select k.charge_nr, k.eingangsdatum, k.anteil, b.eingang_kg * k.anteil as eingang_kg
    from v_kohorte_anteil k
    join v_kaskade_basis b on b.charge_nr = k.charge_nr
),
lieferungen as materialized (
  select charge_nr, kohorte, masse_kg, alter_tage, n_lieferungen
    from v_lieferung_kohorte where buch = 'verkauf'
),
koeff as (
  select b.charge_nr, b.sorte, b.schlag, b.eingang_kg, b.stichtag,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05) as r,
         (kv.mittel is not null)                          as r_bekannt,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(coalesce(ka.mittel, 0), 0), 1)    as a_klein,
         (ka.mittel is not null)                          as a_klein_bekannt,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(coalesce(kn.mittel, 0), 0), 1)    as a_gross,
         (kn.mittel is not null)                          as a_gross_bekannt,
         kn.n as gross_n, kn.basis as gross_basis,
         least(greatest(coalesce(kf.mittel, 0), 0), 1)    as a_fax,
         (kf.mittel is not null)                          as a_fax_bekannt,
         kf.n as fax_n, kf.basis as fax_basis
    from v_kaskade_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
    left join v_koeff_fax         kf on kf.sorte = b.sorte
   where b.eingang_kg > 0
),
koeff_norm as (
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
-- Die Portionen je Eingangstag: das Ausgelagerte mit dem Alter am Liefertag
-- (die Masse dahinter wird unten zurückgerechnet), der Bestand mit dem Alter
-- bis zum Stichtag.
roh as (
  select k.charge_nr, 'ausgelagert'::text as portion, l.kohorte,
         l.masse_kg::numeric as geliefert_kg, coalesce(l.alter_tage, 0)::numeric as alter_tage,
         null::numeric as eingang_kohorte_kg, l.n_lieferungen
    from koeff_norm k
    join lieferungen l on l.charge_nr = k.charge_nr
  union all
  select k.charge_nr, 'lager', c.eingangsdatum,
         null, greatest((k.stichtag - c.eingangsdatum)::numeric, 0), c.eingang_kg, 0
    from koeff_norm k
    join kohorten c on c.charge_nr = k.charge_nr
),
teile as (
  select k.*, t.portion, t.kohorte, t.geliefert_kg, t.alter_tage, t.eingang_kohorte_kg, t.n_lieferungen,
         ln(greatest(t.alter_tage, 1)) - coalesce(m.x_mittel, 0)        as u,
         case when m.brauchbar then
           m.ln_lambda_korrigiert + m.k * ln(greatest(t.alter_tage, 1))
         end                                                            as eta,
         m.brauchbar                                                    as modell_gilt,
         (m.brauchbar and t.alter_tage > m.t_max)                       as f_extrapoliert,
         case when m.brauchbar then m.c_chargen else s.n end            as f_n,
         s.anteil_mono                                                  as f_treppe,
         (m.brauchbar or (select count(*) from kurve) > 0)              as f_bekannt,
         case when m.brauchbar then coalesce(m.sockel, 0) else 0 end    as a0,
         m.brauchbar                                                    as a0_bekannt,
         case when m.brauchbar then coalesce(m.sockel_var, 0) else 0 end as a0_var
    from koeff_norm k
    join roh t on t.charge_nr = k.charge_nr
    cross join modell m
    left join lateral (
        select c.anteil_mono, c.n from kurve c
         where c.von <= t.alter_tage order by c.von desc limit 1
       ) s on true
),
mit_f as (
  select t.*,
         case when t.modell_gilt
              then least(greatest(1 - exp(-exp(least(greatest(t.eta, -40), 3))), 0), 1)
              else least(greatest(coalesce(t.f_treppe, 0), 0), 1) end   as f
    from teile t
),
-- Der verkaufsfähige Anteil bei diesem Alter: durch ihn wird die Lieferung
-- geteilt. Unter einem Viertel wird nicht mehr geteilt — ein Modell, das
-- drei Viertel Verlust behauptet, ist kein Nenner, sondern ein Befund.
anteil as (
  select x.*,
         greatest(power(1 - x.r, x.alter_tage) * (1 - x.a0) * (1 - x.f)
                  * (1 - x.a_klein_n - x.a_gross_n) * (1 - x.a_fax), 0.25) as verkaufsfaehig_anteil
    from mit_f x
),
ausgelagert as (
  select a.*, a.geliefert_kg / a.verkaufsfaehig_anteil as m0, 0::numeric as ueberzaehlung_kg
    from anteil a where a.portion = 'ausgelagert'
),
-- Im Lager: der Eingang des Tags minus das, was hinter den Lieferungen
-- steckt. Nie negativ — was darüber hinausgeht, ist Überzählung: mehr
-- geliefert, als je hereinkam (meist fehlt Wareneingang).
lager as (
  select a.*,
         greatest(a.eingang_kohorte_kg - coalesce(x.m0, 0), 0) as m0,
         greatest(coalesce(x.m0, 0) - a.eingang_kohorte_kg, 0) as ueberzaehlung_kg
    from anteil a
    left join (select charge_nr, kohorte, sum(m0) as m0 from ausgelagert group by 1, 2) x
           on x.charge_nr = a.charge_nr and x.kohorte = a.kohorte
   where a.portion = 'lager'
),
alle as (
  select * from ausgelagert
  union all
  select * from lager
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))                          as m1,
         (-t.m0 * t.alter_tage * power(1 - t.r, greatest(t.alter_tage - 1, 0))) as d_m1_r,
         case when t.modell_gilt
              then (1 - t.f) * exp(least(greatest(t.eta, -40), 3))
              else 0 end                                                as d_f_eta
    from alle t
   where t.m0 > 0 or t.ueberzaehlung_kg > 0
)
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage, k.eingang_kg,
       k.m0, k.m1, (k.m1 * (1 - k.a0) * (1 - k.f)) as m2,
       k.r, k.f, k.a0, k.a_klein_n, k.a_gross_n, k.a_fax,
       k.u, k.d_m1_r, k.d_f_eta, k.modell_gilt, k.f_extrapoliert,
       k.r_n, k.r_basis, k.klein_n, k.klein_basis, k.gross_n, k.gross_basis, k.f_n,
       k.fax_n, k.fax_basis,
       k.r_bekannt, k.f_bekannt, k.a_klein_bekannt, k.a_gross_bekannt, k.a0_bekannt, k.a0_var,
       k.a_fax_bekannt,
       (k.m0 - k.m1)                                                     as verdunstung_kg,
       (k.m1 * k.a0)                                                     as sockel_kg,
       (k.m1 * (1 - k.a0) * k.f)                                         as schimmel_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * k.a_klein_n)                     as klein_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * k.a_gross_n)                     as nebenkanal_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * (1 - k.a_klein_n - k.a_gross_n) * k.a_fax)
                                                                         as fax_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * (1 - k.a_klein_n - k.a_gross_n) * (1 - k.a_fax))
                                                                         as verkaufsfaehig_kg,
       k.kohorte,
       -- neu (0060): die Lieferung hinter der Portion, die Überzählung, der Nenner
       k.geliefert_kg, k.ueberzaehlung_kg, k.n_lieferungen, k.verkaufsfaehig_anteil
  from kaskade k with no data;

create unique index if not exists mv_kaskade_pk
  on mv_kaskade (charge_nr, portion, coalesce(kohorte, date '1900-01-01'));
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);
grant select on mv_kaskade to authenticated;

create view v_kaskade with (security_invoker = true) as
select * from mv_kaskade;
comment on view v_kaskade is
  'Die Massenkaskade je Charge, Portion und Eingangstag. „ausgelagert" ist die '
  'Eingangsmasse hinter den verkauften Lieferungen (zurückgerechnet über den '
  'verkaufsfähigen Anteil beim Alter am Liefertag); „lager" der Rest des '
  'Eingangstags. Keine Arbeit muss gezählt worden sein (0060).';
grant select on v_kaskade to authenticated;

-- Das Ergebnis je Charge — die Sicht, die die App als „Bestand" lädt.
create view v_hochrechnung_basis with (security_invoker = true) as
with je_charge as (
  select charge_nr,
         sum(m0) filter (where portion = 'ausgelagert')                       as ausgelagert_kg,
         sum(m0 * alter_tage) filter (where portion = 'ausgelagert')
           / nullif(sum(m0) filter (where portion = 'ausgelagert'), 0)        as alter_ausgelagert,
         sum(m0) filter (where portion = 'lager')                             as lager_kg,
         sum(m0 * alter_tage) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as alter_lager,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager')              as verkaufsfaehig_lager_kg,
         sum(geliefert_kg)                                                    as geliefert_kg,
         sum(ueberzaehlung_kg)                                                as ueberzaehlung_kg,
         sum(n_lieferungen)::int                                              as n_lieferungen,
         min(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_von,
         max(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_bis,
         count(*) filter (where portion = 'lager' and m0 > 0)::int            as n_rest_kohorten,
         sum(m0 * (kohorte - date '2000-01-01')) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as rest_tage_seit_epoche
    from mv_kaskade
   group by charge_nr
)
select b.charge_nr, b.schlag, b.sorte,
       b.eingang_kg,
       b.n_paletten,
       b.eingangsdatum_mittel,
       zahl(coalesce(k.ausgelagert_kg, 0), 2, 1e12)::numeric(14,2)             as ausgelagert_kg,
       zahl(k.alter_ausgelagert, 1, 1e5)::numeric(8,1)                         as alter_ausgelagert,
       zahl(coalesce(k.lager_kg, b.eingang_kg), 2, 1e12)::numeric(14,2)         as lager_kg,
       zahl(coalesce(k.alter_lager, (b.stichtag - b.eingangsdatum_mittel)), 1, 1e5)::numeric(8,1)
                                                                              as alter_lager,
       zahl((current_date - x.rest_datum), 1, 1e5)::numeric(8,1)               as alter_lager_heute,
       b.weg2_anteil,
       b.stichtag,
       b.n_paletten_mit_netto,
       zahl(coalesce(k.ueberzaehlung_kg, 0), 2, 1e12)::numeric(14,2)           as ueberzaehlung_kg,
       b.sortiert_kg, b.gewaschen_kg, b.wartet_kg, b.anteil_gewaschen, b.alter_band, b.am_band_kg,
       x.rest_datum                                                           as eingangsdatum_rest,
       (coalesce(k.n_lieferungen, 0) > 0)                                     as rest_alter_aus_zaehlung,
       b.eingang_von, b.eingang_bis, b.n_eingangstage,
       coalesce(k.rest_von, b.eingang_von)                                    as rest_von,
       coalesce(k.rest_bis, b.eingang_bis)                                    as rest_bis,
       -- geschätzt: Bestand geteilt durch die mittlere Palette der Charge
       round(coalesce(k.lager_kg, b.eingang_kg)
             / nullif(b.eingang_kg / nullif(b.n_paletten, 0), 0))::int        as n_rest_paletten,
       coalesce(k.n_rest_kohorten, b.n_eingangstage)                          as n_rest_kohorten,
       (current_date - coalesce(k.rest_bis, b.eingang_bis))::int              as alter_lager_von,
       (current_date - coalesce(k.rest_von, b.eingang_von))::int              as alter_lager_bis,
       -- neu (0060)
       zahl(coalesce(k.geliefert_kg, 0), 2, 1e12)::numeric(14,2)              as geliefert_kg,
       zahl(k.verkaufsfaehig_lager_kg, 2, 1e12)::numeric(14,2)                 as verkaufsfaehig_lager_kg,
       coalesce(k.n_lieferungen, 0)                                           as n_lieferungen
  from v_kaskade_basis b
  left join je_charge k on k.charge_nr = b.charge_nr
  cross join lateral (
    select case when k.rest_tage_seit_epoche is not null
                then date '2000-01-01' + round(k.rest_tage_seit_epoche)::int
                else b.eingangsdatum_mittel end as rest_datum
  ) x
 where b.eingang_kg is not null;
comment on view v_hochrechnung_basis is
  'Je Charge: Eingang (gemessen), geliefert (gemessen), ausgelagert (die '
  'Eingangsmasse hinter den Lieferungen, zurückgerechnet), im Lager (Eingang '
  'minus ausgelagert), dazu das Alter als Spanne über die Eingangstage. Keine '
  'Zahl hier stammt aus einer gezählten Arbeit (0060). rest_alter_aus_zaehlung '
  'heisst jetzt: der Bestand ist über Lieferungen bestimmt, nicht nur vermutet.';
grant select on v_hochrechnung_basis to authenticated;

-- ---------- 10. Die Ströme: unverändert seit 0058, neu gebaut ----------------
-- Ein Strom je Charge, Portion und Eingangstag. Seit die Kaskade je
-- Eingangstag rechnet, hat sie rund zwanzigmal mehr Zeilen als früher — und
-- die Ströme daraus rechnet niemand bei jedem Aufruf neu: gespeichert, mit
-- der Kaskade erneuert (auswertung_aktualisieren). Der Lasttest fand sonst
-- 2 Sekunden je Aufruf von verlust_ranking().
drop materialized view if exists mv_hochrechnung cascade;
create materialized view mv_hochrechnung as
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
         d_r, d_f, d_a, d_a0, koeff_art, bekannt)
with no data;
create index if not exists mv_hochrechnung_charge on mv_hochrechnung (charge_nr, buch);
grant select on mv_hochrechnung to authenticated;

create view v_hochrechnung with (security_invoker = true) as
select * from mv_hochrechnung;
comment on view v_hochrechnung is
  'Ein Strom je Charge, Portion und Eingangstag. kg ist NULL, wenn der '
  'Koeffizient dahinter nie gemessen wurde — koeff_bekannt sagt es. Jeder '
  'Koeffizient ist ein Anteil (0 … 1), jede Masse nie negativ (0058). Die '
  'Portionen kommen seit 0060 aus den Lieferungen, nicht aus gezählten Arbeiten.';
grant select on v_hochrechnung to authenticated;

-- ---------- 10b. verlust_ranking: auch je Charge --------------------------
-- Überblick und Ursachen sollen sich nach Gesamt, Sorte, Schlag *und* Charge
-- aufteilen lassen — mit fortgepflanztem Bereich, nicht nur mit der Summe.
-- Die Sicht auf die Funktion hängt an deren Signatur; v_saisonbilanz und
-- v_marge_buch entstehen unten neu, deshalb kann sie hier weg.
drop view if exists v_verlust_ranking;
drop function if exists verlust_ranking(text, text, numeric);
create or replace function verlust_ranking(
  p_sorte          text    default null,
  p_schlag         text    default null,
  p_min_lagertage  numeric default null,
  p_charge         int     default null)
returns table (
  strom text, buch text, kg numeric, kg_unten numeric, kg_oben numeric,
  kg_beobachtet numeric, kg_projiziert numeric, kg_extrapoliert numeric,
  koeff_n_min int, streuung_kg numeric, df int)
language sql stable set search_path = public as $$
with zeilen as materialized (
  select * from v_hochrechnung
   where buch in ('verlust', 'marge', 'feld')
     and (p_sorte is null or sorte = p_sorte)
     and (p_schlag is null or schlag = p_schlag)
     and (p_charge is null or charge_nr = p_charge)
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
  'Alle Ströme mit fortgepflanztem 95-%-Bereich, wahlweise nach Sorte, Schlag '
  'oder Charge gefiltert (0060). Ein unmessbar breiter Bereich steht als NULL '
  'da und reisst die Sicht nicht mit (0058).';
revoke all on function verlust_ranking(text, text, numeric, int) from public;
grant execute on function verlust_ranking(text, text, numeric, int) to authenticated;

-- Der JIT übersetzt bei grossen Plänen erst und rechnet dann — bei dieser
-- Funktion kostete das Übersetzen im Lasttest zwei Sekunden, das Rechnen
-- eine halbe. Für sie gilt: nicht übersetzen.
alter function verlust_ranking(text, text, numeric, int) set jit = off;

create or replace view v_verlust_ranking with (security_invoker = true) as
select * from verlust_ranking();
comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall. kg ist NULL, '
  'wenn der Koeffizient hinter dem Strom nie gemessen wurde — dann ist der '
  'Strom unbekannt, nicht null.';
grant select on v_verlust_ranking to authenticated;

-- ---------- 11. Die Saisonbilanz: geschlossen per Konstruktion, mit Gegenproben
-- Weil das Ausgelagerte aus den Lieferungen zurückgerechnet ist, geht die
-- Rechnung Eingang = Verlust + Kanal + Verkauf + Bestand von selbst auf. Was
-- sie prüfen kann, sind die Ränder: mehr geliefert als hereingekommen
-- (Überzählung), an die Tiere Geliefertes gegen den gerechneten Kanal,
-- entsorgtes Faules gegen den gerechneten Schimmel.
create view v_saisonbilanz with (security_invoker = true) as
with eingang as (
  select sum(eingang_kg)              as kg,
         sum(lager_kg)                as im_lager_kg,
         sum(wartet_kg)               as wartet_kg,
         sum(ueberzaehlung_kg)        as ueberzaehlung_kg,
         sum(verkaufsfaehig_lager_kg) as rest_kg
    from v_hochrechnung_basis
), verlust as (
  select sum(kg)       filter (where buch in ('verlust', 'feld')) as kg,
         sum(kg_unten) filter (where buch in ('verlust', 'feld')) as kg_unten,
         sum(kg_oben)  filter (where buch in ('verlust', 'feld')) as kg_oben,
         sum(kg)       filter (where buch = 'verlust')            as lager_kg,
         sum(kg)       filter (where buch = 'feld')               as feld_kg,
         sum(kg)       filter (where buch = 'marge')              as kanal_kg,
         bool_and(kg is not null) filter (where buch = 'verlust') as bekannt
    from v_verlust_ranking where buch in ('verlust', 'feld', 'marge')
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
), luecke as (
  select e.kg - coalesce(v.kg, 0) - coalesce(v.kanal_kg, 0) - a.verkauf_kg - vl.kg
         - coalesce(e.rest_kg, 0) + coalesce(e.ueberzaehlung_kg, 0) as kg
    from eingang e cross join verlust v cross join ausgang a cross join vorlauf vl
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
       zahl(e.rest_kg)::numeric(14,2)                      as restbestand_modell_kg,
       zahl(e.im_lager_kg)::numeric(14,2) as im_lager_kg, zahl(e.wartet_kg)::numeric(14,2) as wartet_kg,
       zahl(l.kg)::numeric(14,2)                           as luecke_kg,
       zahl(case when e.kg > 0 then l.kg / e.kg end, 4, 1e5)::numeric(10,4) as luecke_anteil,
       zahl(case when e.kg > 0 then (a.kg + vl.kg) / e.kg end, 4, 1e5)::numeric(10,4) as ausgang_deckung,
       case
         when coalesce(e.kg, 0) <= 0
           then 'Es ist kein Wareneingang erfasst. Ohne das Erntejournal gibt es '
                || 'nichts, worauf sich Verlust und Bestand beziehen könnten.'
         when coalesce(e.ueberzaehlung_kg, 0) > 0.05 * e.kg
           then format('Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — '
                       || 'bei einigen Chargen rund %s kg zu viel. Fast immer fehlt der '
                       || 'Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine '
                       || 'Lieferung ist der falschen Charge zugeordnet.',
                       round(e.ueberzaehlung_kg))
         when a.n_lieferungen = 0 and vl.kg = 0
           then 'Kein Warenausgang erfasst — dann liegt rechnerisch noch alles im Haus, '
                || 'und der Verlust wird für die ganze Eingangsmasse bis zum Stichtag gerechnet. '
                || 'Sobald die Lieferscheine eingelesen sind, teilt sich die Ware in '
                || 'ausgeliefert und liegend.'
         when not coalesce(v.bekannt, false)
           then 'Ein Verluststrom ist noch nicht gemessen — die Ursachen sind erst '
                || 'vollständig, wenn jeder Koeffizient mindestens eine Messung hat.'
         else format('Die Rechnung geht auf: %s t Eingang = %s t Verlust + %s t anderer Kanal '
                     || '+ %s t verkauft + %s t verkaufsfähig im Haus. Das Ausgelagerte ist '
                     || 'aus den Lieferungen zurückgerechnet, deshalb schliesst sie von selbst; '
                     || 'geprüft wird an den Rändern: %s',
                     round(e.kg / 1000.0, 1), round(coalesce(v.kg, 0) / 1000.0, 1),
                     round(coalesce(v.kanal_kg, 0) / 1000.0, 1),
                     round((a.verkauf_kg + vl.kg) / 1000.0, 1), round(coalesce(e.rest_kg, 0) / 1000.0, 1),
                     concat_ws(' ',
                       case when a.marge_kg > 0
                            then format('An die Tiere und in den Nebenkanal geliefert: %s kg, gerechnet: %s kg.',
                                        round(a.marge_kg), round(coalesce(v.kanal_kg, 0))) end,
                       case when a.entsorgt_kg > 0
                            then format('Entsorgt: %s kg, gerechneter Schimmel: %s kg.',
                                        round(a.entsorgt_kg), round(coalesce(v.lager_kg, 0))) end,
                       case when coalesce(e.ueberzaehlung_kg, 0) > 0
                            then format('%s kg Überzählung.', round(e.ueberzaehlung_kg)) end,
                       case when a.marge_kg = 0 and a.entsorgt_kg = 0 and coalesce(e.ueberzaehlung_kg, 0) = 0
                            then 'keine Überzählung; Tierfutter und Entsorgung stehen auf keinem Lieferschein.' end))
       end                                                 as befund,
       zahl(v.lager_kg)::numeric(14,2)                     as lagerverlust_kg,
       zahl(v.feld_kg)::numeric(14,2)                      as feld_kg,
       zahl(f.kg)::numeric(14,2)                           as fax_kg,
       f.n                                                 as n_fax,
       zahl(null::numeric)::numeric(14,2)                  as gewaschen_offen_kg,
       -- neu (0060)
       zahl(v.kanal_kg)::numeric(14,2)                     as kanal_modell_kg,
       zahl(e.ueberzaehlung_kg)::numeric(14,2)             as ueberzaehlung_kg
  from eingang e cross join verlust v cross join ausgang a cross join vorlauf vl
       cross join fax f cross join luecke l;
comment on view v_saisonbilanz is
  'Eingang = Verlust + anderer Kanal + verkauft + verkaufsfähig im Haus. Seit 0060 '
  'geht sie per Konstruktion auf (das Ausgelagerte kommt aus den Lieferungen); '
  'Gegenproben sind Überzählung, gelieferter Kanal und Entsorgung. '
  'gewaschen_offen_kg gibt es nicht mehr: gewaschene, nicht gelieferte Ware liegt.';
grant select on v_saisonbilanz to authenticated;

-- ---------- 12. Kein echter Verlust: Kanal und Überfüllung ----------------
-- Die Überfüllung wird auf die *gelieferten* Kisten hochgerechnet: verkaufte
-- Masse der Sorte × Anteil der gewogenen fertigen Paletten, die als „Kiste ab
-- x kg" liefen, geteilt durch das, was so eine Kiste wiegt. Vorher stand hier
-- der Hand-Anteil aus gezählten Arbeiten — eine Menge, die niemand kannte.
create view v_marge_buch with (security_invoker = true) as
with kiste_je_sorte as (
  select k.sorte,
         sum(k.netto_kg) filter (where k.kistensystem = 'kiste_ab') / nullif(sum(k.netto_kg), 0) as anteil_kiste_ab,
         avg(k.kg_pro_kiste) filter (where k.kistensystem = 'kiste_ab')                          as kg_je_kiste
    from v_ausgang_kennzahl k
   group by k.sorte
), verkauft as (
  select coalesce(l.sorte, c.sorte) as sorte, sum(l.masse_kg) as kg
    from v_lieferung_masse l
    left join charge c on c.nr = l.charge_nr
   where l.buch = 'verkauf' and l.masse_kg is not null
   group by coalesce(l.sorte, c.sorte)
), kisten as materialized (
  select sum(v.kg * coalesce(k.anteil_kiste_ab, 0) / nullif(k.kg_je_kiste, 0)) as anzahl,
         sum(v.kg * coalesce(k.anteil_kiste_ab, 0))                            as kisten_kg,
         sum(v.kg)                                                             as verkauft_kg
    from verkauft v
    left join kiste_je_sorte k on k.sorte = v.sorte
)
select r.strom as posten, r.kg, r.kg_unten, r.kg_oben,
       case r.strom
         when 'Nebenkanal zu gross' then 'Ware über der oberen Kalibergrenze geht in einen anderen Verkaufskanal — nicht weg, nur nicht zum besten Preis'
         when 'Zu klein (Tierfutter)' then 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'
         else '' end::text                                       as erlaeuterung
  from v_verlust_ranking r where r.buch = 'marge'
union all
select 'Überfüllung der Kisten',
       zahl(u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       zahl(u.unten * v.anzahl)::numeric(14,2),
       zahl(u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf '
              || '%s Kisten: die %s t von %s t verkaufter Ware, die nach den gewogenen '
              || 'fertigen Paletten als „Kiste ab x kg" gepackt wurden. Kisten nach Stück '
              || 'haben kein Sollgewicht und damit keine Überfüllung.',
              u.n, round(u.kg_pro_kiste, 3), round(coalesce(v.anzahl, 0)),
              round(coalesce(v.kisten_kg, 0) / 1000.0, 1), round(coalesce(v.verkauft_kg, 0) / 1000.0, 1))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;
comment on view v_marge_buch is
  'Kein echter Verlust: Ware, die den Betrieb über einen anderen Kanal verlässt, '
  'und die verschenkte Marge aus überfüllten Kisten — hochgerechnet auf die '
  'verkaufte Masse, nicht auf gezählte Arbeiten (0060).';
grant select on v_marge_buch to authenticated;

-- ---------- 13. Modell gegen CSV: die Gegenprobe bleibt arbeitsbezogen -----
create view v_massenbilanz with (security_invoker = true) as
with csv_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (where exists (
                    select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
                  / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
    from v_auftrag_masse am
   where am.station in ('sortieren', 'waschen_sortieren') and am.eingang_netto_kg is not null
   group by am.charge_nr
), gemessen as materialized (
  select charge_nr, sum(masse_kg) as gemessen_kg from v_sortier_lauf_masse group by charge_nr
), rest as materialized (
  select charge_nr, sum(m2) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade group by charge_nr
), modell as materialized (
  select b.charge_nr,
         b.am_band_kg
         * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05), coalesce(b.alter_band, 0))
         * (1 - sockel_anteil()) * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
         * q.anteil_mit_csv                                   as am_band_modell_kg
    from v_kaskade_basis b
    left join csv_anteil q on q.charge_nr = b.charge_nr
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
)
select b.charge_nr, b.sorte, b.schlag, b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       zahl(m.am_band_modell_kg, 2, 1e12)::numeric(14,2)                       as modell_am_band_kg,
       c.gemessen_kg                                                           as csv_gemessen_kg,
       zahl(c.gemessen_kg - m.am_band_modell_kg, 2, 1e12)::numeric(14,2)       as abweichung_kg,
       case when m.am_band_modell_kg > 0
            then zahl((c.gemessen_kg - m.am_band_modell_kg) / m.am_band_modell_kg, 4, 1e6)::numeric(10,4)
       end                                                                     as abweichung_anteil,
       zahl(r.restbestand_kg, 2, 1e12)::numeric(14,2)                          as restbestand_kg,
       kb.alter_band
  from v_hochrechnung_basis b
  join v_kaskade_basis kb on kb.charge_nr = b.charge_nr
  left join modell m on m.charge_nr = b.charge_nr
  left join gemessen c on c.charge_nr = b.charge_nr
  left join rest r on r.charge_nr = b.charge_nr;
comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band — die '
  'eine Gegenprobe, die an gezählten Arbeiten hängt (und nur dort gilt). '
  'ausgelagert_kg und lager_kg stammen aus den Lieferungen (0060).';
grant select on v_massenbilanz to authenticated;

-- ---------- 14. Was kostet Warten — je Eingangstag, wie bisher ------------
create view v_naechste_charge with (security_invoker = true) as
with modell as materialized (
  select * from v_schimmel_modell
), kohorten as materialized (
  select charge_nr, eingangsdatum, anteil from v_kohorte_anteil
), bestand as (
  select b.charge_nr, b.sorte, b.schlag, b.lager_kg,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05) as r,
         t.m0, t.alter_tage
    from v_hochrechnung_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    cross join lateral (
      select b.lager_kg * c.anteil as m0,
             greatest((current_date - c.eingangsdatum)::numeric, 0) as alter_tage
        from kohorten c where c.charge_nr = b.charge_nr
      union all
      select b.lager_kg, greatest(b.alter_lager_heute, 0)
       where not exists (select 1 from kohorten c where c.charge_nr = b.charge_nr)
    ) t
   where b.lager_kg > 0
), mit_f as (
  select b.*,
         b.m0 * power(1 - b.r, b.alter_tage) as masse_jetzt_kg,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage, 1)), -40), 3))), 0), 0.99) end as f_jetzt,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage + 14, 1)), -40), 3))), 0), 0.99) end as f_dann,
         (m.brauchbar and b.alter_tage > m.t_max) as hochgerechnet,
         m.brauchbar as modell_gilt
    from bestand b cross join modell m
), je_charge as (
  select charge_nr, sorte, schlag, lager_kg, modell_gilt,
         bool_or(hochgerechnet)                                        as hochgerechnet,
         sum(masse_jetzt_kg)                                           as masse_jetzt_kg,
         sum(masse_jetzt_kg * alter_tage) / nullif(sum(masse_jetzt_kg), 0) as alter_tage,
         min(alter_tage) as alter_von, max(alter_tage) as alter_bis,
         count(*)::int as n_kohorten,
         sum(masse_jetzt_kg * (1 - power(1 - r, 14)))                  as verdunstung_14_kg,
         case when modell_gilt
              then sum(masse_jetzt_kg * (f_dann - f_jetzt) / nullif(1 - f_jetzt, 0)) end as schimmel_14_kg
    from mit_f
   group by charge_nr, sorte, schlag, lager_kg, modell_gilt
)
select charge_nr, sorte, schlag,
       zahl(lager_kg, 2, 1e12)::numeric(14,2)                               as lager_kg,
       round(alter_tage)::int                                               as alter_tage,
       zahl(masse_jetzt_kg, 2, 1e12)::numeric(14,2)                         as masse_jetzt_kg,
       zahl(verdunstung_14_kg, 1, 1e11)::numeric(12,1)                      as verdunstung_14_kg,
       zahl(schimmel_14_kg, 1, 1e11)::numeric(12,1)                         as schimmel_14_kg,
       zahl(verdunstung_14_kg + coalesce(schimmel_14_kg, 0), 1, 1e11)::numeric(12,1) as verlust_14_kg,
       hochgerechnet, modell_gilt,
       round(alter_von)::int as alter_von, round(alter_bis)::int as alter_bis, n_kohorten
  from je_charge
 order by zahl(verdunstung_14_kg + coalesce(schimmel_14_kg, 0), 1, 1e11)::numeric(12,1) desc nulls last;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag '
  'gerechnet und je Charge summiert; der Bestand kommt aus den Lieferungen (0060).';
grant select on v_naechste_charge to authenticated;

-- ---------- 15. Fax: Paletten gezählt, Tage seit dem Waschen -------------
create or replace view v_fax_beobachtung with (security_invoker = true) as
select a.id as auftrag_id, a.charge_nr, c.sorte, c.schlag, a.kaeufer,
       a.start_ts, a.ende_ts, a.status, a.abgebrochen_ts,
       m.eingang_netto_kg                                            as masse_kg,
       m.masse_quelle,
       coalesce(g.kisten, 0)                                         as kisten,
       coalesce(s.kg, 0)                                             as faul_kg,
       (s.auftrag_id is not null)                                    as faul_erfasst,
       zahl(coalesce(s.kg, 0) / nullif(m.eingang_netto_kg + coalesce(s.kg, 0), 0), 5, 1e5)::numeric(10,5)
                                                                     as anteil,
       anteil_plausibel(coalesce(s.kg, 0) / nullif(m.eingang_netto_kg + coalesce(s.kg, 0), 0))
                                                                     as plausibel,
       -- neu (0060)
       a.paletten_gesamt, a.tage_seit_waschen, a.kistensystem
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_auftrag_masse m on m.auftrag_id = a.id
  left join v_schimmel_menge s on s.auftrag_id = a.id
  left join (select auftrag_id, sum(anzahl)::int as kisten from auftrag_gebinde group by auftrag_id) g
         on g.auftrag_id = a.id
 where a.ist_fax and a.abgebrochen_ts is null;
comment on view v_fax_beobachtung is
  'Je Fax-Arbeit: die Masse (Paletten × gemessene Palettenmasse, oder gezählte '
  'Kisten), das gewogene Faule und sein Anteil an dem, was durch die Hände ging. '
  'Dazu die Tage seit dem Waschen, wenn der Vorarbeiter sie kannte (0060).';

-- ---------- 16. Palette kontrollieren: was die App am liebsten hätte -------
-- Die Chargen mit dem grössten Bestand und den wenigsten Kontrollen. Der
-- Arbeiter darf jede andere nehmen — die Vorschläge sind nur die Reihenfolge,
-- in der die Messung am meisten bringt.
create or replace view v_kontrolle_vorschlag with (security_invoker = true) as
select b.charge_nr, b.sorte, b.schlag, b.lager_kg,
       b.alter_lager_von, b.alter_lager_bis, b.eingang_von, b.eingang_bis,
       coalesce(k.n, 0)                                  as n_kontrollen,
       k.zuletzt
  from v_hochrechnung_basis b
  left join (select charge_nr, count(*)::int as n, max(wiege_ts)::date as zuletzt
               from verdunstung_wiegung
              where auftrag_id is null and gemessen
              group by charge_nr) k on k.charge_nr = b.charge_nr
 where b.lager_kg > 0
 order by coalesce(k.n, 0), b.lager_kg desc
 limit 3;
comment on view v_kontrolle_vorschlag is
  'Drei Vorschläge für die Lagerkontrolle: die Chargen mit dem meisten Bestand '
  'und den wenigsten Kontrollen. Wer eine andere Palette greift, trägt ihre '
  'Charge selbst ein (0060).';
grant select on v_kontrolle_vorschlag to authenticated;

-- ---------- 17. Datenqualität: die neuen Absprachen zählen -----------------
create or replace view v_datenqualitaet with (security_invoker = true) as
with arbeiten as (select a.* from auftrag a where a.abgebrochen_ts is null),
     fertig as (select * from arbeiten where status = 'abgeschlossen')
select
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id)::int as paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where ap.eingangsdatum is not null)::int                                             as paletten_mit_datum,
  (select count(*) from fertig where not ist_fax)::int                                    as arbeiten_fertig,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null))::int                     as arbeiten_mit_ablesung,
  (select count(*) from fertig f where not f.ist_fax and (select count(*) from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null) >= 2)::int                as arbeiten_mit_zwei_ablesungen,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from auftrag_angabe g
    where g.auftrag_id = f.id and g.schluessel = 'eine_charge'))::int                     as arbeiten_mit_antwort,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen)::int                                                                as ausschuss_messungen,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen and m.brutto_kg is not null)::int                                    as ausschuss_gewogen,
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.faul_kg is not null and w.gemessen)::int             as lagerkontrollen,
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.faul_kg is not null and w.gemessen
      and w.auswahl = 'erreichbar_zufaellig')::int                                        as lagerkontrollen_zufaellig,
  (select count(*) from sortier_lauf)::int                                                as sortierlaeufe,
  (select count(*) from sortier_lauf where auftrag_id is not null)::int                   as sortierlaeufe_zugeordnet,
  (select count(*) from fertig f where f.station = 'sortieren')::int                      as sortier_arbeiten,
  (select count(*) from fertig f where f.station = 'sortieren' and exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int              as sortier_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax)::int      as wasch_arbeiten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax
    and (f.kaliber_idx is not null or f.kaliber_von_g is not null)
    and exists (select 1 from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int
                                                                                          as wasch_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax)::int                                    as fax_arbeiten,
  (select count(*) from fertig f where f.ist_fax and (f.paletten_gesamt > 0 or exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)))::int             as fax_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax and exists (select 1
    from schimmel_messung s where s.auftrag_id = f.id and s.gemessen))::int               as fax_arbeiten_mit_faulem,
  -- neu (0060)
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren')::int                                           as ws_paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren' and ap.brutto_zettel_kg is not null)::int       as ws_paletten_mit_zettelgewicht,
  (select count(*) from fertig f where f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))::int
                                                                                          as arbeiten_nach_waschen,
  (select count(*) from fertig f where (f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))
    and f.kistensystem is not null)::int                                                  as arbeiten_mit_kistensystem,
  (select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
    where a.station = 'waschen' and not a.ist_fax)::int                                   as wasch_kisten_gezaehlt,
  (select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
    where a.station = 'waschen' and not a.ist_fax and (g.sortierdatum is not null or g.datum_fehlt))::int
                                                                                          as wasch_kisten_mit_sortierdatum,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from v_palox_stand p
    where p.auftrag_id = f.id and p.differenz is null))::int                              as arbeiten_mit_palox_unbekannt;
comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung. Seit 0060 auch: Zettelgewicht beim '
  'Waschen + Sortieren, Kistensystem nach dem Waschen, Sortierdatum je Kiste, '
  'Fax-Paletten, und Arbeiten mit unbekannter Palox-Menge (Stand gefallen).';

-- ---------- 18. Plausibilität: Fax-Paletten, Zettelgewicht, gefallener Palox
create or replace view v_plausibilitaet with (security_invoker = true) as
select 'Schimmel'::text as art, b.auftrag_id, b.charge_nr, b.sorte, b.start_ts,
       format('%s kg Schimmel auf %s kg Ware — das wären %s %%',
              round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100)) as befund,
       'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text as rat
  from v_schimmel_beobachtung b
 where b.anteil is not null and not b.plausibel and not b.ist_fax
union all
select 'Fax', f.auftrag_id, f.charge_nr, f.sorte, f.start_ts,
       format('%s kg Faules bei %s (%s kg) — das wären %s %%',
              round(f.faul_kg),
              case when f.paletten_gesamt > 0 then f.paletten_gesamt || ' Paletten' else f.kisten || ' Kisten' end,
              round(f.masse_kg), round(f.anteil * 100)),
       'Entweder die Palettenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'
  from v_fax_beobachtung f
 where f.anteil is not null and not f.plausibel
union all
select 'Ausschuss', a.auftrag_id, a.charge_nr, a.sorte, null::timestamptz,
       format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse',
              round(coalesce(a.klein_kg, 0)), round(coalesce(a.gross_kg, 0)), round(a.basis_kg)),
       'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'
  from v_ausschuss_beobachtung a
 where a.weg = 'hand' and not a.plausibel
union all
select 'Ohne Nenner', a.id, a.charge_nr, c.sorte, a.start_ts,
       format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein',
              concat_ws(' und ',
                case when coalesce(s.kg, 0) > 0 then round(s.kg) || ' kg Faules' end,
                case when coalesce(x.kg, 0) > 0 then round(x.kg) || ' kg zu klein/gross' end),
              case when a.ist_fax then 'keine Palette gezählt oder noch keine fertige Palette dieser Sorte gewogen'
                   when a.station = 'waschen' then 'keine Kiste gezählt und keine Menge eingetragen'
                   when a.station = 'waschen_sortieren' then 'keine Palette mit Gewicht vom Zettel gezählt'
                   else 'keine Palette gezählt' end),
       case when a.ist_fax
            then 'Die Palettenzahl am Ende der Fax-Arbeit eintragen. Fehlt die Palettenmasse, '
                 || 'beim Waschen oder Waschen + Sortieren eine fertige Palette wiegen — sie '
                 || 'gilt dann für alle Fax-Arbeiten der Sorte.'
            when a.station = 'waschen'
            then 'Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich '
                 || 'selbst) oder die verarbeitete Menge in kg nachtragen.'
            when a.station = 'waschen_sortieren'
            then 'Die Paletten mit Datum und Gewicht vom Zettel am Auftrag nachtragen.'
            else 'Die gezählten Paletten am Auftrag nachtragen.' end
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_schimmel_menge s on s.auftrag_id = a.id
  left join (select auftrag_id, sum(kg)::numeric as kg from ausschuss_messung
              where gemessen group by auftrag_id) x on x.auftrag_id = a.id
  left join v_auftrag_masse m on m.auftrag_id = a.id
 where a.abgebrochen_ts is null
   and (coalesce(s.kg, 0) > 0 or coalesce(x.kg, 0) > 0)
   and coalesce(m.eingang_netto_kg, 0) <= 0
union all
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
-- 0060: Der Stand ist gefallen — geleert, ohne dass jemand die Menge davor kennt.
-- Kein Fehler des Arbeiters; die Menge dieser Arbeit ist unbekannt.
select 'Palox geleert', p.auftrag_id, a.charge_nr, c.sorte, p.ts,
       format('Der Waagenstand fiel von %s auf %s kg — der Palox wurde zwischendurch geleert. '
              || 'Wie viel davor noch dazukam, weiss niemand; das Faule dieser Arbeit ist unbekannt.',
              p.vorher, p.palox_stand_kg),
       'Nichts zu korrigieren. Wird der Palox vor dem Leeren einmal abgelesen, bleibt die Menge bekannt.'
  from v_palox_stand p
  join auftrag a on a.id = p.auftrag_id
  join charge c on c.nr = a.charge_nr
 where p.differenz is null and a.abgebrochen_ts is null
union all
select 'Wägung', w.auftrag_id, w.charge_nr, w.sorte, w.wiege_ts,
       'Palette gewogen, aber '
       || case when w.netto_damals_kg is null or w.netto_jetzt_kg is null
                 then 'für die Gebindeart fehlt die Tara'
               when w.lagertage <= 0
                 then 'das Wiegedatum liegt nicht nach dem Eingangsdatum'
               when w.netto_damals_kg <= 0 or w.netto_jetzt_kg <= 0
                 then 'das Netto ist null oder negativ'
               when w.netto_jetzt_kg > w.netto_damals_kg * 1.01
                 then format('sie wiegt jetzt %s kg mehr als beim Eingang, und im Lager wird keine Palette schwerer',
                             round(w.netto_jetzt_kg - w.netto_damals_kg))
               else 'sie ist nicht verwertbar' end
       || ' — sie zählt nicht in die Verdunstungsrate',
       case when w.netto_damals_kg is null or w.netto_jetzt_kg is null
              then 'Unter Stammdaten → Gebinde die Tara nachtragen.'
            when w.netto_jetzt_kg > w.netto_damals_kg * 1.01
              then 'Gebindeart, Kistenzahl und beide Gewichte prüfen — meist stimmt die Tara nicht oder eine Zahl ist verdreht.'
            else 'Eingangsdatum und Gewichte der Wägung prüfen.' end
  from v_verdunstung_messung w
  left join auftrag a on a.id = w.auftrag_id
 where not w.verwendbar and not w.sichtbar_schimmel
   and (a.id is null or a.abgebrochen_ts is null)
   and exists (select 1 from verdunstung_wiegung v where v.id = w.id and v.gemessen)
union all
select 'Kistengewicht', g.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       case when g.kaliber_idx = -1
            then format('%s Kisten nach Sollgewicht gezählt, aber für diese Sorte wurde noch '
                        || 'nie eine fertige Palette gewogen — das Kistengewicht ist unbekannt', g.anzahl)
            else format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber wurde beim '
                        || 'Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt',
                        g.anzahl, g.kaliber_idx + 1) end,
       case when g.kaliber_idx = -1
            then 'Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '
                 || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'
            else 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '
                 || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.' end
  from v_auftrag_gebinde_masse g
  join auftrag a on a.id = g.auftrag_id
  join charge c on c.nr = a.charge_nr
 where g.kg is null and g.anzahl > 0 and g.kaliber_idx <> -2
union all
select 'Kaliber fehlt', a.id, a.charge_nr, c.sorte, a.start_ts,
       'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen',
       'Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '
       || 'Stammdaten → Sortierschemata.'
  from auftrag a
  join charge c on c.nr = a.charge_nr
 where a.station = 'waschen' and not a.ist_fax and a.kaliber_idx is null
   and a.kaliber_von_g is null and a.abgebrochen_ts is null
   and exists (select 1 from auftrag_gebinde g where g.auftrag_id = a.id and g.anzahl > 0)
union all
select 'Ausschuss-Tara', m.auftrag_id, a.charge_nr, c.sorte, m.ts,
       format('%s kg %s gespeichert — aus Brutto %s kg und heutiger Tara wären es %s kg',
              m.kg, case m.art when 'zu_klein' then 'zu klein' else 'zu gross' end,
              m.brutto_kg,
              greatest(round(m.brutto_kg - coalesce(m.kisten, 0) * coalesce(g.tara_kg_pro_kiste, 0)
                             - coalesce(g.tara_kg_palette, 0)), 0)),
       'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '
       || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'
  from ausschuss_messung m
  join auftrag a on a.id = m.auftrag_id
  join charge c on c.nr = a.charge_nr
  left join gebinde g on g.art = m.gebindeart
 where m.brutto_kg is not null and a.abgebrochen_ts is null
   and m.kg <> greatest(round(m.brutto_kg - coalesce(m.kisten, 0) * coalesce(g.tara_kg_pro_kiste, 0)
                              - coalesce(g.tara_kg_palette, 0)), 0)
union all
select 'Zetteldatum', ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Palette(n) mit Zetteldatum %s gezählt, aber an dem Tag kam keine Palette dieser Charge',
              count(*), to_char(ap.eingangsdatum, 'DD.MM.YYYY')),
       'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  join charge c on c.nr = a.charge_nr
 where ap.eingangsdatum is not null and ap.palette_id is null and ap.wiegung_id is null
   and a.abgebrochen_ts is null
   and not exists (select 1 from palette p where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum)
 group by ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.eingangsdatum
union all
-- 0060: Ein Zettelgewicht, das im Wareneingang keine Palette hat — vertippt, oder die Palette fehlt.
select 'Zettelgewicht', ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette '
              || 'dieser Charge dieses Gewicht — gerechnet wird mit der mittleren Tara der Charge',
              count(*), ap.brutto_zettel_kg),
       'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  join charge c on c.nr = a.charge_nr
 where ap.brutto_zettel_kg is not null and a.abgebrochen_ts is null
   and not exists (select 1 from palette p where p.charge_nr = a.charge_nr and p.brutto_kg = ap.brutto_zettel_kg)
 group by ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg
union all
-- 0060: Eine verkaufte Lieferung an eine Charge, die keinen Wareneingang hat,
-- kann die Kaskade nirgends zurückrechnen — sie fällt sonst still heraus.
select 'Lieferung ohne Eingang', null::bigint, l.charge_nr, l.sorte, min(l.datum)::timestamptz,
       format('%s Lieferung(en) mit %s kg an Charge %s, aber im Wareneingang steht keine Palette dieser Charge',
              count(*), round(sum(l.masse_kg)), l.charge_nr),
       'Wareneingang der Charge nachtragen (Erntejournal) — oder die Lieferung gehört zu einer anderen Charge.'
  from v_lieferung_masse l
 where l.buch = 'verkauf' and l.charge_nr is not null and l.masse_kg > 0
   and not exists (select 1 from v_kohorte_anteil k where k.charge_nr = l.charge_nr)
 group by l.charge_nr, l.sorte
union all
select art, auftrag_id, charge_nr, sorte, start_ts, befund, rat from v_plausibilitaet_0054_zusatz;

-- ---------- 18b. Neuberechnung: die Hochrechnung dazu, ohne JIT ---------
create or replace function auswertung_aktualisieren()
returns timestamptz language plpgsql security definer
set search_path = public set jit = off as $$
declare v_start timestamptz := clock_timestamp();
begin
  refresh materialized view mv_sortier_lauf_masse;
  refresh materialized view mv_kaliber_verteilung;
  refresh materialized view mv_sortier_eingang;
  refresh materialized view mv_auftrag_masse;
  refresh materialized view mv_schimmel_punkte;
  refresh materialized view mv_schimmel_modell;
  refresh materialized view mv_kaskade;
  refresh materialized view mv_hochrechnung;      -- 0060

  update auswertung_stand
     set berechnet_ts = now(),
         dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
   where id = 1;

  return now();
end $$;

-- ---------- 18c. Der JIT bremst diese Datenbank ----------------------------
-- Postgres übersetzt Ausdrücke einer Abfrage in Maschinencode, sobald der
-- Planer ihre Kosten über 100 000 schätzt. Die Sichten hier haben viele
-- Ausdrücke und wenige Zeilen: Das Übersetzen dauerte im Lasttest bis zu
-- einer Sekunde je Sicht (v_plausibilitaet 1.2 s statt 0.12 s), das Rechnen
-- fast nichts. PostgreSQL 19 schaltet den JIT aus demselben Grund
-- standardmässig ab. Hier als Einstellung der Datenbank — wo das nicht
-- erlaubt ist (fremd verwaltete Datenbank), bleibt es beim Hinweis; die
-- Sichten rechnen dann richtig, nur langsamer.
do $$
begin
  execute format('alter database %I set jit = off', current_database());
  raise notice 'JIT für die Datenbank % abgeschaltet (gilt ab der nächsten Verbindung).', current_database();
exception when others then
  raise notice 'JIT nicht abgeschaltet (%): die Auswertung rechnet richtig, nur langsamer.', sqlerrm;
end $$;

-- ---------- 19. Stand der Datenbank ---------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 60 $$;
