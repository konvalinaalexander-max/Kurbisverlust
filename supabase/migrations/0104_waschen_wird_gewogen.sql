-- =====================================================================
-- 0104 — Beim Waschen wird die Palette am Anfang der Strasse gewogen
--
-- Der Betrieb, 29. September, nachts: Beim reinen Waschen hat die Palette
-- kein bekanntes Gewicht — Kisten aus dem Zwischenlager; wir wissen, wie
-- schwer die Kürbisse sind, aber nicht, wie viele in einer Kiste liegen.
-- „Pure mystery." Darum wird dort ab jetzt jede Palette am Anfang der
-- Waschstrasse gewogen: Die App lässt sie ohne Gewicht nicht zählen, und
-- die Auftragsleitenden bekommen es beim Anlegen der Arbeit gesagt. Den
-- Schwund (Verdunstung) kennt man dieser Palette trotzdem nicht — ihr
-- Gewicht bei der Ernte gab es nie —, aber der Palox-Zuwachs des Waschgangs
-- hat damit einen gemessenen Nenner.
--
-- Bis hier kam die Masse hinein beim Waschen nur über Umwege: fertige
-- Paletten gewogen (Masse heraus, ohne das Faule) oder Kisten mal ein
-- gelerntes Kistengewicht des Bandes (0092). Beides bleibt als Ersatz
-- stehen für Arbeiten ohne Wägung — jetzt an zweiter Stelle.
--
--   · auftrag_palette.brutto_gewogen_kg: das Brutto der Palette mit Kisten,
--     von der Waage am Anfang der Strasse.
--   · v_auftrag_wasch_gewogen: je Wasch-Arbeit die Masse hinein aus den
--     gewogenen Paletten (Brutto − Kisten × Kistentara − Palettentara).
--     Sind nicht alle gewogen, rechnen die übrigen mit dem Mittel je Kiste
--     der gewogenen — und die Quelle sagt „teils".
--   · v_auftrag_masse nimmt diese Masse vor allen Ersätzen
--     (masse_quelle „gewogen_strasse" / „gewogen_strasse_teils").
--   · v_koeff_gebinde lernt das Kistengewicht des Bandes auch daraus:
--     Masse hinein durch Kisten hinein — direkter als Masse heraus.
--   · Plausibilität „Waage": eine gewogene Wasch-Palette mit weniger als 4
--     oder mehr als 30 kg je Kiste, oder leichter als ihre Tara — Waage,
--     Kistenzahl oder Gebinde? Und „Kistengewicht" schweigt, wenn die
--     Paletten der Arbeit gewogen sind: beim Band, weil das Kistengewicht
--     aus der Waage gelernt wird; beim eigenen Kaliber (Zusatz 0054)
--     ausdrücklich, dort gibt es kein Band zum Lernen.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Die Spalte
-- ---------------------------------------------------------------------
alter table auftrag_palette add column if not exists brutto_gewogen_kg numeric;
do $$
begin
  alter table auftrag_palette add constraint auftrag_palette_brutto_gewogen_positiv
    check (brutto_gewogen_kg is null or brutto_gewogen_kg > 0);
exception when duplicate_object then null;
end $$;
comment on column auftrag_palette.brutto_gewogen_kg is
  'Waschen (0104): Brutto der Palette mit Kisten, gewogen am Anfang der Waschstrasse — Pflicht in der App. '
  'Netto = Brutto − Kisten × Kistentara − Palettentara (gebinde).';

-- ---------------------------------------------------------------------
-- 2. Je Wasch-Arbeit die Masse hinein aus der Waage
-- ---------------------------------------------------------------------
create or replace view v_auftrag_wasch_gewogen with (security_invoker = true) as
with p as (
  select ap.auftrag_id, ap.id, ap.kisten,
         case when ap.brutto_gewogen_kg is not null
               and g.tara_kg_pro_kiste is not null and g.tara_kg_palette is not null
               and ap.brutto_gewogen_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette > 0
              then ap.brutto_gewogen_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette
         end as netto_kg
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join gebinde g on g.art = ap.gebindeart
   where a.station = 'waschen' and not a.ist_fax and ap.kisten is not null and ap.kisten > 0
)
select auftrag_id,
       count(*)::int                                          as n_paletten,
       count(netto_kg)::int                                   as n_gewogen,
       coalesce(sum(kisten) filter (where netto_kg is not null), 0)::int as kisten_gewogen,
       coalesce(sum(kisten) filter (where netto_kg is null), 0)::int     as kisten_ungewogen,
       -- Die ungewogenen Paletten rechnen mit dem Mittel je Kiste der gewogenen.
       zahl(sum(netto_kg)
            + coalesce(sum(kisten) filter (where netto_kg is null), 0)
              * (sum(netto_kg) / nullif(sum(kisten) filter (where netto_kg is not null), 0)),
            2, 10000000000)::numeric(12,2)                    as kg,
       zahl(sum(netto_kg) / nullif(sum(kisten) filter (where netto_kg is not null), 0), 3, 10000000)::numeric(10,3)
                                                              as kg_je_kiste,
       case when count(netto_kg) = count(*) then 'gewogen_strasse' else 'gewogen_strasse_teils' end as quelle
  from p
 group by auftrag_id
having count(netto_kg) > 0;
comment on view v_auftrag_wasch_gewogen is
  'Waschen (0104): die Masse hinein aus den am Anfang der Strasse gewogenen Paletten — Brutto minus Kisten × '
  'Kistentara minus Palettentara. Nicht gewogene Paletten rechnen mit dem Mittel je Kiste der gewogenen (quelle „teils").';
grant select on v_auftrag_wasch_gewogen to authenticated;

-- ---------------------------------------------------------------------
-- 3. Die Masse der Arbeit: die Waage vor jedem Ersatz
-- ---------------------------------------------------------------------
create or replace view v_auftrag_masse with (security_invoker = true) as
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten,
       -- 0104: die Waage am Anfang der Waschstrasse geht vor jedem Ersatz.
       coalesce(m.eingang_netto_kg, wg.kg, fpg.kg, wp.kg, gb.kg, fp.kg) as eingang_netto_kg,
       case when m.masse_quelle <> 'fehlt' then m.masse_quelle
            when wg.kg is not null then wg.quelle
            when fpg.kg is not null then 'fertige_paletten'
            when wp.kg is not null then 'wasch_paletten'
            when gb.kg is not null then 'gebinde'
            when fp.kg is not null then 'fax_paletten'
            else 'fehlt' end as masse_quelle,
       zahl(coalesce(m.lagertage,
         case when m.station = 'waschen'
              then (betriebstag(m.start_ts) - date '2000-01-01')::numeric
                   - coalesce(se.tage_seit_epoche, (r.eingangsdatum_mittel - date '2000-01-01')::numeric)
              else null end), 1, 1000000000)::numeric(10,1) as lagertage,
       a.ist_fax,
       wp.zwischenlager_tage,
       case
         when m.lagertage is not null                then 'gemessen'
         when m.station <> 'waschen'                 then null
         when se.tage_seit_epoche is not null        then 'sortiermittel'
         when r.eingangsdatum_mittel is not null     then 'chargenmittel'
         else null
       end as alter_quelle,
       case when m.lagertage is not null then null else es.streuung_tage end as alter_spanne_tage,
       coalesce(es.ernte_fertig, false) as ernte_fertig
  from mv_auftrag_masse m
  join auftrag a on a.id = m.auftrag_id
  left join mv_sortier_eingang se on se.charge_nr = m.charge_nr
  left join v_charge_rueckgrat r on r.charge_nr = m.charge_nr
  left join v_charge_erntespanne es on es.charge_nr = m.charge_nr
  left join v_auftrag_wasch_paletten wp on wp.auftrag_id = m.auftrag_id
  left join v_auftrag_wasch_gewogen wg on wg.auftrag_id = m.auftrag_id
  left join (select auftrag_id, sum(kg) as kg from v_auftrag_gebinde_masse group by auftrag_id) gb
         on gb.auftrag_id = m.auftrag_id
  -- 0079: Beim Waschen die Masse, die herauskam — als eigene Sicht daneben,
  -- nicht als Unterabfrage hier drin. Warum das wichtig ist, steht bei
  -- v_auftrag_fertige_masse: Eine Unterabfrage in der Spaltenliste nimmt dem
  -- Planer die Möglichkeit, diese Sicht in ihre acht Leser hineinzufalten.
  left join v_auftrag_fertige_masse fpg on fpg.auftrag_id = m.auftrag_id
  left join lateral (
        select zahl(a.paletten_gesamt::numeric * p.netto_kg, 2, 10000000000)::numeric(12,2) as kg
          from v_koeff_palette_netto p
         where a.ist_fax and a.paletten_gesamt > 0 and p.sorte = m.sorte
           and (p.kistensystem = a.kistensystem
                or p.kistensystem is null and a.kistensystem is distinct from 'anderes')
         order by (p.kistensystem = a.kistensystem) desc nulls last
         limit 1) fp on true;

-- ---------------------------------------------------------------------
-- 4. Das Kistengewicht des Bandes: auch aus der Waage am Anfang
-- ---------------------------------------------------------------------
create or replace view v_koeff_gebinde with (security_invoker = true) as
with gezaehlt as (
  select auftrag_id, kaliber_idx, sum(anzahl)::int as anzahl
    from auftrag_gebinde group by auftrag_id, kaliber_idx
), je_arbeit as (
  -- Der Weg bis 0092: gezählte Kisten am Sortierlauf, die Masse aus der CSV.
  select a.id as auftrag_id, c.sorte, g.kaliber_idx, g.anzahl,
         sum(sg.anzahl::bigint * sg.gewicht_g) / 1000.0 as kg
    from gezaehlt g
    join auftrag a on a.id = g.auftrag_id and a.abgebrochen_ts is null
    join charge c on c.nr = a.charge_nr
    join sortier_lauf l on l.auftrag_id = a.id
    join sortier_gewicht sg on sg.lauf_id = l.id and sg.klasse = 'kaliber' and sg.kaliber_idx = g.kaliber_idx
   where a.station in ('sortieren', 'waschen_sortieren') and g.anzahl > 0
   group by a.id, c.sorte, g.kaliber_idx, g.anzahl
), band as (
  select distinct s.sorte, i.idx as kaliber_idx,
         (s.kaliber_baender -> i.idx ->> 0)::int as von,
         (s.kaliber_baender -> i.idx ->> 1)::int as bis
    from sortierschema s
    cross join lateral generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) i(idx)
   where s.art = 'kaliber' and s.kaliber_baender is not null
), je_wasch as (
  -- 0092: Wasch-Arbeiten, die hinein gezählt und heraus gewogen haben.
  -- Nur die EIGENEN gewogenen Paletten der Arbeit — nicht der Sortenwert,
  -- sonst drehte sich die Rechnung im Kreis.
  select a.id as auftrag_id, c.sorte,
         coalesce(a.kaliber_idx, e.kaliber_idx) as kaliber_idx,
         sum(ap.kisten)::int as anzahl,
         a.fertige_paletten_gesamt::numeric * eig.netto_kg as kg
    from auftrag a
    join charge c on c.nr = a.charge_nr
    join auftrag_palette ap on ap.auftrag_id = a.id and ap.kisten is not null
    join (select v.auftrag_id, avg(v.netto_kg) as netto_kg
            from v_ausgang_voll v
           where coalesce(v.voll, true) and v.netto_kg > 0
           group by v.auftrag_id) eig on eig.auftrag_id = a.id
    left join lateral (
      select b.kaliber_idx from band b
       where a.kaliber_idx is null and b.sorte = c.sorte and b.von = a.kaliber_von_g and b.bis = a.kaliber_bis_g
       order by b.kaliber_idx limit 1) e on true
   where a.station = 'waschen' and not a.ist_fax and a.abgebrochen_ts is null
     and coalesce(a.fertige_paletten_gesamt, 0) > 0
   group by a.id, c.sorte, coalesce(a.kaliber_idx, e.kaliber_idx), a.fertige_paletten_gesamt, eig.netto_kg
  having sum(ap.kisten) > 0 and coalesce(a.kaliber_idx, e.kaliber_idx) is not null
), je_wasch_gewogen as (
  -- 0104: Masse hinein durch Kisten hinein — die Waage am Anfang der
  -- Waschstrasse. Direkter als die Masse heraus (der fehlen Faules und
  -- Ausschuss des Waschgangs).
  select a.id as auftrag_id, c.sorte,
         coalesce(a.kaliber_idx, e.kaliber_idx) as kaliber_idx,
         wg.kisten_gewogen::int as anzahl,
         wg.kg_je_kiste * wg.kisten_gewogen as kg
    from v_auftrag_wasch_gewogen wg
    join auftrag a on a.id = wg.auftrag_id and a.abgebrochen_ts is null
    join charge c on c.nr = a.charge_nr
    left join lateral (
      select b.kaliber_idx from band b
       where a.kaliber_idx is null and b.sorte = c.sorte and b.von = a.kaliber_von_g and b.bis = a.kaliber_bis_g
       order by b.kaliber_idx limit 1) e on true
   where wg.kisten_gewogen > 0 and coalesce(a.kaliber_idx, e.kaliber_idx) is not null
), s as (
  select q.sorte, q.kaliber_idx, count(*)::int as n,
         sum(q.kg) / nullif(sum(q.anzahl), 0)::numeric as kg_je_gebinde,
         stddev_samp(q.kg / q.anzahl::numeric) as sd
    from (select sorte, kaliber_idx, anzahl, kg from je_arbeit
          union all
          select sorte, kaliber_idx, anzahl, kg from je_wasch
          union all
          select sorte, kaliber_idx, anzahl, kg from je_wasch_gewogen) q
   group by q.sorte, q.kaliber_idx
  union all
  -- Sollgewicht-Kisten (kaliber_idx −1): das Kistengewicht der Sorte aus den
  -- gewogenen fertigen Paletten „Kiste ab x kg" — wie seit 0060.
  select k.sorte, -1, count(*)::int,
         sum(k.netto_kg) / nullif(sum(k.kisten), 0)::numeric,
         stddev_samp(k.kg_pro_kiste)
    from v_ausgang_kennzahl k
   where k.soll_kg_pro_kiste is not null or k.kistensystem = 'kiste_ab'
   group by k.sorte
)
select sorte, kaliber_idx, n,
       zahl(kg_je_gebinde, 3, 10000000)::numeric(10,3) as kg_je_gebinde,
       zahl(sd, 3, 10000000)::numeric(10,3) as sd,
       zahl(case when sd is null or n < 2 then kg_je_gebinde::double precision
                 else greatest(kg_je_gebinde::double precision - (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision), 0::double precision) end,
            3, 10000000)::numeric(10,3) as unten,
       zahl(case when sd is null or n < 2 then kg_je_gebinde::double precision
                 else kg_je_gebinde::double precision + (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision) end,
            3, 10000000)::numeric(10,3) as oben
  from s
 where kg_je_gebinde is not null;

-- ---------------------------------------------------------------------
-- 5. Plausibilität: „Waage", und „Kistengewicht" schweigt bei gewogenen Paletten
-- ---------------------------------------------------------------------
create or replace view v_plausibilitaet with (security_invoker = true) as
 SELECT 'Schimmel'::text AS art,
    b.auftrag_id,
    b.charge_nr,
    b.sorte,
    b.start_ts,
    format('%s kg Schimmel auf %s kg Ware — das wären %s %%'::text, round(b.schimmel_kg), round(b.basis_jetzt_kg), round((b.anteil * (100)::numeric))) AS befund,
    'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text AS rat
   FROM v_schimmel_beobachtung b
  WHERE ((b.anteil IS NOT NULL) AND (NOT b.plausibel) AND (NOT b.ist_fax) AND (b.lagertage >= (0)::numeric))
UNION ALL
 SELECT 'Fax'::text AS art,
    f.auftrag_id,
    f.charge_nr,
    f.sorte,
    f.start_ts,
    format('%s kg Faules bei %s (%s kg) — das wären %s %%'::text, round(f.faul_kg),
        CASE
            WHEN (f.paletten_gesamt > 0) THEN (f.paletten_gesamt || ' Paletten'::text)
            ELSE (f.kisten || ' Kisten'::text)
        END, round(f.masse_kg), round((f.anteil * (100)::numeric))) AS befund,
    'Entweder die Palettenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'::text AS rat
   FROM v_fax_beobachtung f
  WHERE ((f.anteil IS NOT NULL) AND (NOT f.plausibel))
UNION ALL
 SELECT 'Ausschuss'::text AS art,
    a.auftrag_id,
    a.charge_nr,
    a.sorte,
    NULL::timestamp with time zone AS start_ts,
    format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse'::text, round(COALESCE(a.klein_kg, (0)::numeric)), round(COALESCE(a.gross_kg, (0)::numeric)), round(a.basis_kg)) AS befund,
    'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'::text AS rat
   FROM v_ausschuss_beobachtung a
  WHERE ((a.weg = 'hand'::verarbeitungsweg) AND (NOT a.plausibel))
UNION ALL
 SELECT 'Ohne Nenner'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein'::text, concat_ws(' und '::text,
        CASE
            WHEN (COALESCE(s.kg, (0)::numeric) > (0)::numeric) THEN (round(s.kg) || ' kg Faules'::text)
            ELSE NULL::text
        END,
        CASE
            WHEN (COALESCE(x.kg, (0)::numeric) > (0)::numeric) THEN (round(x.kg) || ' kg zu klein/gross'::text)
            ELSE NULL::text
        END),
        CASE
            WHEN a.ist_fax THEN 'keine Palette gezählt oder noch keine fertige Palette dieser Sorte gewogen'::text
            WHEN (a.station = 'waschen'::station) THEN 'keine Kiste gezählt und keine Menge eingetragen'::text
            WHEN (a.station = 'waschen_sortieren'::station) THEN 'keine Palette mit Gewicht vom Zettel gezählt'::text
            ELSE 'keine Palette gezählt'::text
        END) AS befund,
        CASE
            WHEN a.ist_fax THEN (('Die Palettenzahl am Ende der Fax-Arbeit eintragen. Fehlt die Palettenmasse, '::text || 'beim Waschen oder Waschen + Sortieren eine fertige Palette wiegen — sie '::text) || 'gilt dann für alle Fax-Arbeiten der Sorte.'::text)
            WHEN (a.station = 'waschen'::station) THEN ('Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich '::text || 'selbst) oder die verarbeitete Menge in kg nachtragen.'::text)
            WHEN (a.station = 'waschen_sortieren'::station) THEN 'Die Paletten mit Datum und Gewicht vom Zettel am Auftrag nachtragen.'::text
            ELSE 'Die gezählten Paletten am Auftrag nachtragen.'::text
        END AS rat
   FROM ((((auftrag a
     JOIN charge c ON ((c.nr = a.charge_nr)))
     LEFT JOIN v_schimmel_menge s ON ((s.auftrag_id = a.id)))
     LEFT JOIN ( SELECT ausschuss_messung.auftrag_id,
            (sum(ausschuss_messung.kg))::numeric AS kg
           FROM ausschuss_messung
          WHERE ausschuss_messung.gemessen
          GROUP BY ausschuss_messung.auftrag_id) x ON ((x.auftrag_id = a.id)))
     LEFT JOIN v_auftrag_masse m ON ((m.auftrag_id = a.id)))
  WHERE ((a.abgebrochen_ts IS NULL) AND ((COALESCE(s.kg, (0)::numeric) > (0)::numeric) OR (COALESCE(x.kg, (0)::numeric) > (0)::numeric)) AND (COALESCE(m.eingang_netto_kg, (0)::numeric) <= (0)::numeric))
UNION ALL
 SELECT 'Palox'::text AS art,
    s.auftrag_id,
    a.charge_nr,
    c.sorte,
    s.ts AS start_ts,
    format('Waagenstand %s kg liegt unter dem Leergewicht des Palox (%s kg)'::text, s.palox_stand_kg, palox_tara_kg()) AS befund,
    ('Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '::text || 'Sonst ist der Stand vertippt.'::text) AS rat
   FROM ((schimmel_messung s
     JOIN auftrag a ON ((a.id = s.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE (s.gemessen AND (a.abgebrochen_ts IS NULL) AND (s.palox_stand_kg IS NOT NULL) AND (s.palox_stand_kg < palox_tara_kg()))
UNION ALL
 SELECT 'Palox geleert'::text AS art,
    p.auftrag_id,
    a.charge_nr,
    c.sorte,
    p.ts AS start_ts,
    format(('Der Waagenstand fiel von %s auf %s kg — der Palox wurde zwischendurch geleert. '::text || 'Wie viel davor noch dazukam, weiss niemand; das Faule dieser Arbeit ist unbekannt.'::text), p.vorher, p.palox_stand_kg) AS befund,
    'Nichts zu korrigieren. Beim nächsten Mal in der Checkliste „Palox leeren" drücken: vor dem Leeren ablesen, danach die leere Box — dann bleibt die Menge bekannt.'::text AS rat
   FROM ((v_palox_stand p
     JOIN auftrag a ON ((a.id = p.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((p.differenz IS NULL) AND (a.abgebrochen_ts IS NULL))
UNION ALL
 SELECT 'Wägung'::text AS art,
    w.auftrag_id,
    w.charge_nr,
    w.sorte,
    w.wiege_ts AS start_ts,
    (('Palette gewogen, aber '::text ||
        CASE
            WHEN ((w.netto_damals_kg IS NULL) OR (w.netto_jetzt_kg IS NULL)) THEN 'für die Gebindeart fehlt die Tara'::text
            WHEN (w.lagertage <= 0) THEN 'das Wiegedatum liegt nicht nach dem Eingangsdatum'::text
            WHEN ((w.netto_damals_kg <= (0)::numeric) OR (w.netto_jetzt_kg <= (0)::numeric)) THEN 'das Netto ist null oder negativ'::text
            WHEN (w.netto_jetzt_kg > (w.netto_damals_kg * 1.01)) THEN format('sie wiegt jetzt %s kg mehr als beim Eingang, und im Lager wird keine Palette schwerer'::text, round((w.netto_jetzt_kg - w.netto_damals_kg)))
            WHEN (w.netto_jetzt_kg = w.netto_damals_kg) THEN 'sie hat kein Gramm verloren — sehr wahrscheinlich wurde das Eingangsgewicht kopiert (etwa bei einer sortierten Palette, deren Zettelgewicht es nicht gibt)'::text
            ELSE 'sie ist nicht verwertbar'::text
        END) || ' — sie zählt nicht in die Verdunstungsrate'::text) AS befund,
        CASE
            WHEN ((w.netto_damals_kg IS NULL) OR (w.netto_jetzt_kg IS NULL)) THEN 'Unter Stammdaten → Gebinde die Tara nachtragen.'::text
            WHEN (w.netto_jetzt_kg > (w.netto_damals_kg * 1.01)) THEN 'Gebindeart, Kistenzahl und beide Gewichte prüfen — meist stimmt die Tara nicht oder eine Zahl ist verdreht.'::text
            ELSE 'Eingangsdatum und Gewichte der Wägung prüfen.'::text
        END AS rat
   FROM (v_verdunstung_messung w
     LEFT JOIN auftrag a ON ((a.id = w.auftrag_id)))
  WHERE ((NOT w.verwendbar) AND (NOT w.sichtbar_schimmel) AND ((a.id IS NULL) OR (a.abgebrochen_ts IS NULL)) AND (EXISTS ( SELECT 1
           FROM verdunstung_wiegung v
          WHERE ((v.id = w.id) AND v.gemessen))))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
        CASE
            WHEN (g.kaliber_idx = '-1'::integer) THEN format(('%s Kisten nach Sollgewicht gezählt, aber für diese Sorte wurde noch '::text || 'nie eine fertige Palette gewogen — das Kistengewicht ist unbekannt'::text), g.anzahl)
            ELSE format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, (g.kaliber_idx + 1))
        END AS befund,
        CASE
            WHEN (g.kaliber_idx = '-1'::integer) THEN ('Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '::text || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'::text)
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — daraus kennt die App das Kistengewicht des Bandes, rückwirkend für alle Waschgänge dieser Sorte, auch für diesen. Oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat
   FROM ((v_auftrag_gebinde_masse g
     JOIN auftrag a ON ((a.id = g.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  -- 0104: Sind die Paletten dieser Arbeit am Anfang der Strasse gewogen, lernt
  -- v_koeff_gebinde das Kistengewicht des Bandes daraus, g.kg ist gesetzt, und
  -- dieser Befund entfällt von selbst — eine eigene Klausel wäre unerreichbar
  -- (die Mutation hat es gezeigt). Beim eigenen Kaliber (Zusatz 0054) gibt es
  -- kein Band zum Lernen; dort steht die Klausel ausdrücklich.
  WHERE ((g.kg IS NULL) AND (g.anzahl > 0) AND (g.kaliber_idx <> '-2'::integer))
UNION ALL
 SELECT 'Waage'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    CASE
        WHEN w.netto_kg <= 0 THEN format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — leichter als ihre Kisten und die Palette (Tara %s kg)', ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(ap.kisten::numeric * g.tara_kg_pro_kiste + g.tara_kg_palette, 1))
        ELSE format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — %s kg je Kiste', ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(w.netto_kg / ap.kisten::numeric, 1))
    END AS befund,
    'Waage, Kistenzahl oder Gebinde prüfen und im Korrekturfenster der Arbeit berichtigen — bis dahin rechnet die Masse dieser Palette mit.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = ap.gebindeart
     CROSS JOIN LATERAL (SELECT ap.brutto_gewogen_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_kg) w
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL
    AND ap.brutto_gewogen_kg IS NOT NULL AND ap.kisten IS NOT NULL AND ap.kisten > 0
    AND g.tara_kg_pro_kiste IS NOT NULL AND g.tara_kg_palette IS NOT NULL
    AND (w.netto_kg <= 0 OR w.netto_kg / ap.kisten::numeric < 4 OR w.netto_kg / ap.kisten::numeric > 30)
UNION ALL
 SELECT 'Kaliber fehlt'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen'::text AS befund,
    ('Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '::text || 'Stammdaten → Sortierschemata.'::text) AS rat
   FROM (auftrag a
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((a.station = 'waschen'::station) AND (NOT a.ist_fax) AND (a.kaliber_idx IS NULL) AND (a.kaliber_von_g IS NULL) AND (a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
           FROM auftrag_gebinde g
          WHERE ((g.auftrag_id = a.id) AND (g.anzahl > 0)))))
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
    ('Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '::text || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'::text) AS rat
   FROM ((((ausschuss_messung m
     JOIN auftrag a ON ((a.id = m.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
     LEFT JOIN gebinde g ON ((g.art = m.gebindeart)))
     CROSS JOIN LATERAL ( SELECT ((m.brutto_kg - ((m.kisten)::numeric * g.tara_kg_pro_kiste)) -
                CASE
                    WHEN m.mit_palette THEN g.tara_kg_palette
                    ELSE (0)::numeric
                END) AS roh) n)
  WHERE ((m.brutto_kg IS NOT NULL) AND (a.abgebrochen_ts IS NULL) AND (n.roh IS NOT NULL) AND ((m.kg)::numeric <> round(n.roh)))
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
            WHEN (m.gebindeart IS NULL) THEN 'an der Wägung steht keine Gebindeart'::text
            WHEN (g.art IS NULL) THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN (g.tara_kg_pro_kiste IS NULL) THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN (g.tara_kg_palette IS NULL) THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END) AS befund,
    ('Die gespeicherten Kilo bleiben, wie sie sind — geprüft werden können sie erst, '::text || 'wenn Gebindeart, Tara und Kistenzahl beisammen sind.'::text) AS rat
   FROM (((ausschuss_messung m
     JOIN auftrag a ON ((a.id = m.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
     LEFT JOIN gebinde g ON ((g.art = m.gebindeart)))
  WHERE ((m.brutto_kg IS NOT NULL) AND (a.abgebrochen_ts IS NULL) AND (((m.brutto_kg - ((m.kisten)::numeric * g.tara_kg_pro_kiste)) - g.tara_kg_palette) IS NULL))
UNION ALL
 SELECT 'Zetteldatum'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Zetteldatum %s gezählt, aber an dem Tag kam keine Palette dieser Charge'::text, count(*), to_char((ap.eingangsdatum)::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat
   FROM ((auftrag_palette ap
     JOIN auftrag a ON ((a.id = ap.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((ap.eingangsdatum IS NOT NULL) AND (ap.palette_id IS NULL) AND (ap.wiegung_id IS NULL) AND (a.abgebrochen_ts IS NULL) AND (NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE ((p.charge_nr = a.charge_nr) AND (p.eingangsdatum = ap.eingangsdatum))))))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.eingangsdatum
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — %s'::text, count(*), ap.brutto_zettel_kg,
        CASE
            WHEN bool_and(((ap.kisten IS NOT NULL) AND (ap.gebindeart IS NOT NULL))) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            ELSE 'gerechnet wird mit der mittleren Tara der Charge; stehen Kisten und Gebinde an der Palette, mit deren Tara'::text
        END) AS befund,
    'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal).'::text AS rat
   FROM ((auftrag_palette ap
     JOIN auftrag a ON ((a.id = ap.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((ap.brutto_zettel_kg IS NOT NULL) AND (a.abgebrochen_ts IS NULL) AND (NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE ((p.charge_nr = a.charge_nr) AND (p.brutto_kg = ap.brutto_zettel_kg))))))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg
UNION ALL
 SELECT 'Lieferung ohne Eingang'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    (min(l.datum))::timestamp with time zone AS start_ts,
    format('%s Lieferung(en) mit %s kg an Charge %s, aber im Wareneingang steht keine Palette dieser Charge'::text, count(*), round(sum(l.masse_kg)), l.charge_nr) AS befund,
    'Wareneingang der Charge nachtragen (Erntejournal) — oder die Lieferung gehört zu einer anderen Charge.'::text AS rat
   FROM v_lieferung_masse l
  WHERE ((l.buch = 'verkauf'::text) AND (l.charge_nr IS NOT NULL) AND (l.masse_kg > (0)::numeric) AND (NOT (EXISTS ( SELECT 1
           FROM v_kohorte_anteil k
          WHERE (k.charge_nr = l.charge_nr)))))
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
    format('%s Palette(n) mit Eingangsdatum %s gezählt — das liegt in der Zukunft, sehr wahrscheinlich ein falsches Jahr'::text, count(*), to_char((max(ap.eingangsdatum))::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung korrigieren (Jahr prüfen). Die Beobachtung bleibt gespeichert, bis sie berichtigt ist; solange rechnet die Auswertung sie nicht mit.'::text AS rat
   FROM ((auftrag_palette ap
     JOIN auftrag a ON ((a.id = ap.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((ap.eingangsdatum > heute()) AND (a.abgebrochen_ts IS NULL))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts
UNION ALL
 SELECT 'Palettengewicht'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    (p.eingangsdatum)::timestamp with time zone AS start_ts,
    format('Eine Palette mit %s kg brutto — für eine Palette Kürbisse ist das unmöglich'::text, round(p.brutto_kg)) AS befund,
    'Bruttogewicht im Wareneingang prüfen — sehr wahrscheinlich ein Zahlendreher.'::text AS rat
   FROM (palette p
     JOIN charge c ON ((c.nr = p.charge_nr)))
  WHERE (p.brutto_kg > (2000)::numeric);

-- Der Zusatz von 0054 (eigenes Kaliber) ebenso: gewogene Paletten sind bekannte Masse.
create or replace view v_plausibilitaet_0054_zusatz with (security_invoker = true) as
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber für ein Band mit diesen Grenzen hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, a.kaliber_von_g, a.kaliber_bis_g) AS befund,
    'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) oder die fertigen Paletten wiegen (drei reichen).'::text AS rat
   FROM ((v_auftrag_gebinde_masse g
     JOIN auftrag a ON ((a.id = g.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((g.kg IS NULL) AND (g.anzahl > 0) AND (g.kaliber_idx = '-2'::integer)
     AND NOT EXISTS (SELECT 1 FROM v_auftrag_wasch_gewogen wg WHERE wg.auftrag_id = g.auftrag_id AND wg.quelle = 'gewogen_strasse'))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    wp.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format(('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '::text || 'die Menge dieser Arbeit damit auch'::text), wp.n_paletten, wp.kisten,
        CASE
            WHEN (a.kaliber_von_g IS NOT NULL) THEN format('für das Band %s–%s g hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen'::text, a.kaliber_von_g, a.kaliber_bis_g)
            ELSE 'für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen'::text
        END) AS befund,
        CASE
            WHEN (a.kaliber_von_g IS NOT NULL) THEN 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen.'::text
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — dann kennt die App das Kistengewicht des Bandes, rückwirkend auch für diese Arbeit; oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat
   FROM ((v_auftrag_wasch_paletten wp
     JOIN auftrag a ON ((a.id = wp.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  -- 0104: sind die Paletten dieser Arbeit am Anfang der Strasse gewogen, ist ihre Masse bekannt — kein Befund.
  WHERE ((wp.kg IS NULL) AND (wp.kisten > 0)
     AND NOT EXISTS (SELECT 1 FROM v_auftrag_wasch_gewogen wg WHERE wg.auftrag_id = wp.auftrag_id AND wg.quelle = 'gewogen_strasse'))
UNION ALL
 SELECT 'Lieferung in der Zukunft'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    (l.datum)::timestamp with time zone AS start_ts,
    format(('Lieferschein über %s kg mit Datum %s — das liegt nach heute (%s). '::text || 'Die Menge zählt erst ab diesem Tag in Ausgang und Bestand.'::text), round(l.masse_kg), to_char((l.datum)::timestamp with time zone, 'DD.MM.YYYY'::text), to_char((heute())::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    ('Stimmt das Datum? Ein vordatierter Lieferschein ist in Ordnung — die Zahl '::text || 'erscheint von selbst, sobald der Tag da ist. Ein Zahlendreher gehört korrigiert.'::text) AS rat
   FROM v_lieferung_masse l
  WHERE ((l.datum > heute()) AND (l.masse_kg IS NOT NULL) AND (l.masse_kg > (0)::numeric))
UNION ALL
 SELECT v_plausibilitaet_0064_zusatz.art,
    v_plausibilitaet_0064_zusatz.auftrag_id,
    v_plausibilitaet_0064_zusatz.charge_nr,
    v_plausibilitaet_0064_zusatz.sorte,
    v_plausibilitaet_0064_zusatz.start_ts,
    v_plausibilitaet_0064_zusatz.befund,
    v_plausibilitaet_0064_zusatz.rat
   FROM v_plausibilitaet_0064_zusatz;

-- ---------------------------------------------------------------------
-- 6. Die Demo wiegt seit Mitte August — die Sicht darf auf der Demo nicht
--    leer bleiben (0081 b), und die Bildschirme zeigen, was die App kann.
--    Der Lader als Ganzes neu, wie in 0081, 0093, 0094, 0096.
-- ---------------------------------------------------------------------
create or replace function demo_daten_laden()
returns text language plpgsql security definer set search_path = public as $fn$
declare
  v_anker date := current_date - 215;
  -- Der Schnitt „was ist schon passiert" hing bisher an now(). Damit war die
  -- Saison nur *fast* reproduzierbar: lud man sie morgens und mittags, kamen
  -- verschieden viele Arbeiten heraus, weil ein Start von gestern abend beim
  -- einen Lauf noch vor der Grenze lag und beim anderen dahinter. Gemessen:
  -- 367 gegen 376 Arbeiten, zwei Läufe im Abstand von Minuten. Jetzt liegt
  -- die Grenze auf einer festen Stunde des Tages — zweimal laden am selben
  -- Tag gibt zweimal dieselbe Saison. Nur die laufenden Arbeiten am Schluss
  -- hängen weiter an now(), denn die sollen wirklich gerade laufen.
  v_jetzt timestamptz := current_date::timestamptz + interval '17 hours';
  v_wer   uuid := auth.uid();
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter laden.';
  end if;
  if exists (select 1 from palette where extern_id like 'demo-%') then
    raise exception E'Die Demo-Saison ist schon geladen.\nZum Neuladen zuerst entfernen.';
  end if;

  -- Im SQL-Editor gibt es keinen Login — dann tritt der Betriebsleiter ein.
  if v_wer is null then
    select id into v_wer from profil where rolle = 'admin' order by erstellt_ts limit 1;
  end if;
  if v_wer is null then select id into v_wer from profil order by erstellt_ts limit 1; end if;
  if v_wer is null then
    raise exception E'Es gibt noch kein Benutzerkonto.\nLege zuerst dein Betriebsleiter-Konto an (README, Schritt 7) und versuche es dann nochmal.';
  end if;
  perform set_config('request.jwt.claim.sub', v_wer::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_wer)::text, true);

  -- ---------- Stammdaten der Demo ----------------------------------------
  -- Bei Konflikt bleibt der bestehende Käufer, wie er ist — samt seiner
  -- (leeren) Bemerkung. Genau daran erkennt das Entfernen ihn als echten.
  insert into kaeufer (code, name, bemerkung) values
    ('nordmarkt', 'Nordmarkt Genossenschaft', 'DEMO'), ('talhof', 'Talhof Bio AG', 'DEMO'),
    ('gruenwerk', 'Grünwerk Handel', 'DEMO'), ('feldfrisch', 'Feldfrisch Ost', 'DEMO')
  on conflict (code) do nothing;
  -- Nordmarkt nimmt Butternut in der 8-kg-Kiste; Talhof will Kaori Kuri enger.
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'nordmarkt', v_anker + 20, 'kiste', 8, 'DEMO — Nordmarkt nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'nordmarkt' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'gruenwerk', v_anker + 25, 'kiste', 8, 'DEMO — Grünwerk nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'gruenwerk' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab, bemerkung)
  select 'Kaori Kuri', 'talhof', v_anker + 60, 'kaliber', 600, '[[600,1000],[1000,1400],[1400,2000]]'::jsonb, 2000,
         'DEMO — Talhof will Kaori Kuri in engeren Bändern (beim Eröffnen einer Arbeit geändert)'
   where not exists (select 1 from sortierschema where sorte = 'Kaori Kuri' and kaeufer = 'talhof' and art = 'kaliber');
  -- Ein Vorlauf: Charge 1611 lieferte schon 5 t, bevor die App lief.
  insert into charge_vorlauf (charge_nr, ausgang_vor_app_kg, bemerkung)
  values (1611, 5000, 'DEMO — vor dem Erfassungsbeginn ausgeliefert')
  on conflict (charge_nr) do nothing;

  -- ---------- Hilfstabellen ------------------------------------------------
  drop table if exists demo_charge; drop table if exists demo_pal; drop table if exists demo_lauf;
  create temp table demo_charge (
    nr int primary key, sorte text, weg text, kg numeric, kw int,
    anteil_verarbeitet numeric,      -- wie viel der Charge bis heute verarbeitet ist
    r numeric,                       -- Verdunstung je Tag
    lambda numeric, k numeric, sockel numeric,   -- Verderbskurve
    fax_anteil numeric, gramm int, sd int,       -- Faules beim Fax, Gewicht je Kürbis
    kg_kiste numeric, kaeufer text
  );
  -- Die ganze Anbauplanung, nicht nur ein Teil davon: jede Charge des
  -- Stammdatenregisters bekommt einen Eingang. Vorher blieben sechs ohne
  -- jede Zeile — im Dashboard standen sie als Chargen ohne Daten, und wer
  -- die Demo anschaute, hielt das für einen Fehler des Werkzeugs.
  insert into demo_charge (nr, kg, kw, anteil_verarbeitet) values
    (1598,  2200, 35, 1.00), (1599,  1400, 34, 0.85), (1601,  9800, 38, 0.25),
    (1603,  3100, 36, 1.00), (1604,  2600, 34, 0.90), (1605,  1200, 34, 1.00),
    (1606,   800, 33, 1.00), (1607,  1900, 34, 1.00), (1608,  6400, 36, 0.70),
    (1609, 12500, 35, 0.80), (1610,  4200, 37, 0.45), (1611, 38000, 37, 0.60),
    (1612, 16500, 35, 0.75), (1613, 24000, 35, 0.90), (1614,  3900, 34, 1.00),
    (1615,  3100, 34, 1.00), (1616,  8600, 34, 0.85), (1617,  2400, 35, 1.00),
    (1618,  4100, 34, 1.00), (1619,  1800, 34, 1.00), (1620,  2900, 35, 0.55),
    (1623,  9100, 36, 0.65), (1624,  7800, 35, 0.85), (1625,  2600, 34, 1.00),
    (1626,  4600, 39, 0.00), (1627,  2900, 39, 0.40), (1628, 11000, 34, 0.95),
    (1630, 10800, 34, 0.90), (1631, 14200, 39, 0.15), (1632, 35000, 37, 0.50),
    (1633, 22000, 38, 0.35), (1634,  6600, 36, 0.70), (1635,  5900, 36, 0.80),
    (1636, 17000, 36, 0.55), (1637,  5400, 36, 0.75), (1638,  4800, 36, 0.30),
    (1646,  7200, 34, 0.80), (1647,  8100, 39, 0.25), (1648,  9700, 34, 0.90),
    (1649, 20500, 38, 0.40), (1650,  2400, 39, 0.00), (1651,  3300, 35, 1.00);
  update demo_charge d set sorte = c.sorte from charge c where c.nr = d.nr;
  -- Butternut von Hand, alles andere über die Maschine. Sorteneigenschaften
  -- so, wie sie im Betrieb beobachtet werden: Hokkaido verdunstet schneller,
  -- Butternut hält länger, Mandarin ist klein.
  -- Mit WHERE, obwohl jede Zeile gemeint ist: Supabase lässt die API-Verbindung
  -- mit der Sicherung safeupdate laufen, die ein UPDATE ohne Bedingung abweist —
  -- auch in einer Funktion, auch auf einer Hilfstabelle.
  update demo_charge set
    weg    = case when sorte in ('Tiana', 'Mieluna') then 'hand' else 'maschine' end,
    r      = case sorte when 'Tiana' then 0.00045 when 'Mieluna' then 0.00050 when 'Butterkin' then 0.00060
                        when 'Orangita' then 0.00090 when 'Lekor' then 0.00065 else 0.00080 end,
    -- λ so, dass nach 150 Tagen rund 8 % (Butternut) bis 14 % (Mandarin) faul sind
    lambda = case sorte when 'Tiana' then 800 when 'Mieluna' then 720 when 'Butterkin' then 600
                        when 'Orangita' then 450 when 'Lekor' then 560 when 'Kaori Kuri' then 520 else 500 end,
    k      = case sorte when 'Tiana' then 1.5 when 'Orangita' then 1.9 else 1.7 end,
    sockel = case sorte when 'Orangita' then 0.006 else 0.004 end,
    fax_anteil = case sorte when 'Tiana' then 0.012 when 'Mieluna' then 0.015 when 'Orangita' then 0.030
                            when 'Butterkin' then 0.020 else 0.024 end,
    gramm  = case sorte when 'Orangita' then 560 when 'Butterkin' then 1250 when 'Lekor' then 1500
                        when 'Kaori Kuri' then 1100 when 'Amoro' then 1300 when 'Ker Madec' then 1000
                        when 'Fictor' then 1400 when 'Orange Summer' then 1200 when 'Bolp 5110' then 1200
                        when 'Tiana' then 1400 else 1200 end,
    sd     = case sorte when 'Orangita' then 170 when 'Tiana' then 420 when 'Lekor' then 420 else 320 end,
    kg_kiste = case sorte when 'Orangita' then 10.8 when 'Tiana' then 12.4 when 'Mieluna' then 12.0
                          when 'Butterkin' then 11.8 else 11.4 end,
    kaeufer = case nr % 4 when 0 then 'nordmarkt' when 1 then 'talhof' when 2 then 'gruenwerk' else 'feldfrisch' end
   where sorte is not null;
  -- Die zwei grossen Abnehmer teilen sich die frühen Chargen; die zwei
  -- kleineren nehmen, was später kommt — so steht es in der Verkaufsplanung.
  update demo_charge set kaeufer = case when nr % 2 = 0 then 'nordmarkt' else 'talhof' end
   where kw <= 35;

  create temp table demo_pal (
    id bigint, nr int, datum date, netto numeric, kisten int, verarbeitet boolean default false
  );
  create temp table demo_lauf (
    auftrag_id bigint, nr int, sorte text, start_ts timestamptz, masse_kg numeric, alter_tage numeric,
    art text, kaeufer text, baender jsonb, kg_je_kiste numeric,
    kisten int[]       -- gefüllte Kisten je Band (Index = Band)
  );

  -- ---------- 1. Wareneingang: je Charge in ihrer Erntewoche ---------------
  declare d record; v_n int; v_p int; v_tag date; v_kisten int; v_netto numeric; v_je_tag int;
          v_zufall numeric; v_art text; v_id bigint;
  begin
    for d in select * from demo_charge order by nr loop
      v_n := greatest(round(d.kg / (32 * d.kg_kiste))::int, 2);
      v_je_tag := case when v_n <= 6 then 4 when v_n <= 20 then 8 when v_n <= 60 then 14 else 22 end;
      v_tag := v_anker + (d.kw - 34) * 7 + (d.nr % 3);
      for v_p in 1 .. v_n loop
        -- Werktage: Samstag und Sonntag wird nicht geerntet
        if v_p > 1 and (v_p - 1) % v_je_tag = 0 then v_tag := v_tag + 1; end if;
        while extract(isodow from v_tag) >= 6 loop v_tag := v_tag + 1; end loop;
        v_zufall := (hashtext(format('pal-%s-%s', d.nr, v_p))::bigint & 2147483647)::numeric / 2147483647;
        v_kisten := 30 + (v_p * 7 + d.nr) % 5;
        v_netto  := round(v_kisten * d.kg_kiste * (0.94 + 0.12 * v_zufall), 1);
        -- Fremde Produzenten liefern teils in IFCO-Kisten
        v_art := case when d.nr in (1648, 1628, 1630, 1631) and v_p % 3 = 0 then 'IFCO 6416' else 'G2' end;
        insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
        values (d.nr, v_tag, v_netto + v_kisten * (case when v_art = 'G2' then 1.5 else 1.68 end) + 25,
                v_kisten, v_art, format('demo-%s-%s', d.nr, v_p))
        returning id into v_id;
        insert into demo_pal (id, nr, datum, netto, kisten) values (v_id, d.nr, v_tag, v_netto, v_kisten);
      end loop;
    end loop;
    raise notice 'Demo: Wareneingang angelegt (% Paletten)', (select count(*) from demo_pal);
  end;

  -- ---------- 2. Verarbeitung -----------------------------------------------
  -- Sortieren (Maschine) bzw. Waschen + Sortieren (Hand), in mehreren Läufen,
  -- ohne FIFO. Je Lauf: Paletten mit Datum vom Zettel, Palox zu Beginn und am
  -- Ende (Faules nach der Verderbskurve), CSV oder Wägungen, Kisten je Kaliber.
  declare d record; v_lauf int; v_n_laeufe int; v_n_pal int; v_verarbeitet int; v_ziel int;
          v_start timestamptz; v_auftrag bigint; v_masse numeric; v_tage numeric; v_f numeric;
          v_schimmel numeric; v_zufall numeric; v_schema bigint; v_art text; v_kaeufer text;
          v_baender jsonb; v_nb int; v_i int; v_hist jsonb; v_n int; v_gramm numeric;
          v_kisten int[]; v_kg_band numeric; v_klein numeric; v_gross numeric; v_x numeric;
          p record; v_pal_ids bigint[]; v_netto numeric; v_kisten_p int; v_brutto numeric;
          v_wiegung bigint; v_datum date; v_abstand int;
  begin
    for d in select * from demo_charge where anteil_verarbeitet > 0 order by nr loop
      select count(*) into v_n_pal from demo_pal where nr = d.nr;
      v_ziel := round(v_n_pal * d.anteil_verarbeitet)::int;
      if v_ziel = 0 then continue; end if;
      v_n_laeufe := greatest(ceil(v_ziel / 16.0)::int, 1);
      v_verarbeitet := 0;
      v_abstand := greatest(round(172.0 / v_n_laeufe)::int, 8);

      for v_lauf in 1 .. v_n_laeufe loop
        -- Wie viele Paletten dieser Lauf nimmt, und wann
        v_n := least(v_ziel - v_verarbeitet, 12 + (d.nr + v_lauf) % 8);
        exit when v_n <= 0;
        v_zufall := (hashtext(format('lauf-%s-%s', d.nr, v_lauf))::bigint & 2147483647)::numeric / 2147483647;
        -- Jede Charge kommt zu ihrer Zeit dran: die einen bald nach der Ernte,
        -- die anderen Wochen später — so bleibt bis heute etwas zu tun.
        v_start := (v_anker + (d.kw - 34) * 7 + 12 + (d.nr % 7) * 12 + (v_lauf - 1) * v_abstand + floor(v_zufall * 6)::int)::timestamptz
                   + interval '7 hours' + (d.nr % 3) * interval '30 minutes';
        while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
        exit when v_start > v_jetzt - interval '2 days';

        -- Kein FIFO: ungerade Läufe greifen die jüngsten Paletten, gerade die
        -- ältesten — je nachdem, an welchen Stapel man herankommt.
        select array_agg(id) into v_pal_ids from (
          select id from demo_pal where nr = d.nr and not verarbeitet
           order by case when v_lauf % 2 = 1 then datum end desc,
                    case when v_lauf % 2 = 0 then datum end asc, id
           limit v_n) s;
        update demo_pal set verarbeitet = true where id = any(v_pal_ids);
        select sum(netto), sum(netto * (v_start::date - datum)) / sum(netto)
          into v_masse, v_tage from demo_pal where id = any(v_pal_ids);
        v_verarbeitet := v_verarbeitet + v_n;

        -- Die Fassung: Maschine immer Kaliber; von Hand die 8-kg-Kiste — bis auf
        -- eine Charge, die Migros nach Kaliber will (dort bleibt das Kisten-
        -- gewicht beim Fax unbekannt, und die Auswertung sagt es).
        v_kaeufer := d.kaeufer;
        v_art := case when d.weg = 'maschine' then 'kaliber'
                      when d.nr = 1647 then 'kaliber' else 'kiste' end;
        v_schema := sortierschema_fuer(d.sorte, v_kaeufer, v_start::date, v_art);
        select kaliber_baender into v_baender from sortierschema where id = v_schema;
        if v_art = 'kaliber' and v_baender is null then
          select kaliber_baender into v_baender from sortierschema
           where sorte = d.sorte and art = 'kaliber' and kaeufer is null order by gilt_ab desc limit 1;
        end if;
        v_nb := coalesce(jsonb_array_length(v_baender), 0);

        -- 0060: das Kistensystem steht an der Arbeit — von Hand „Kiste ab 8 kg"
        -- oder Stück-Kisten eines Kalibers; die Sortiermaschine fragt nicht.
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaeufer, sortierschema_id, bemerkung,
                             geplante_paletten, kistensystem, soll_kg_pro_kiste, stueck_je_kiste)
        values (case when d.weg = 'maschine' then 'maschine' else 'hand' end::verarbeitungsweg,
                case when d.weg = 'maschine' then 'sortieren' else 'waschen_sortieren' end::station,
                d.nr, v_start,
                v_start + make_interval(mins => (240 + v_n * 14 + floor(v_zufall * 40)::int)),
                'abgeschlossen', v_kaeufer, v_schema, 'DEMO', v_n,
                case when d.weg = 'maschine' then null when v_art = 'kiste' then 'kiste_ab' else 'stueck' end,
                case when d.weg <> 'maschine' and v_art = 'kiste' then 8 end,
                case when d.weg <> 'maschine' and v_art = 'kaliber' then greatest(round(d.kg_kiste * 1000 / d.gramm)::int, 1) end)
        returning id into v_auftrag;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_auftrag, id from profil order by erstellt_ts limit (2 + (v_lauf % 2))
        on conflict do nothing;

        -- Paletten zählen — mit dem Datum vom Zettel; beim Waschen + Sortieren
        -- auch mit dem Gewicht vom Zettel (0060), damit der Palox einen Nenner hat.
        -- 0076: die Maske lässt die Palette aus der Liste greifen — dann steht
        -- sie mit ihrer Nummer da und die Masse ist exakt bekannt. Jede dritte
        -- Arbeit tippt stattdessen nur das Zetteldatum ab; dort bleibt die
        -- Masse ein Mittel. Beides kommt vor, und die Herkunftsspalte im
        -- Dashboard soll beides zeigen.
        -- 0072: in welchem Gebinde die Palette steht, wird gefragt — meistens
        -- G2, manchmal IFCO.
        insert into auftrag_palette (auftrag_id, palette_id, eingangsdatum, ts, brutto_zettel_kg, gebindeart)
        select v_auftrag,
               case when (d.nr + v_lauf) % 3 <> 0 then dp.id end,
               dp.datum, v_start + make_interval(mins => (10 + row_number() over (order by dp.id) * 12)::int),
               case when d.weg <> 'maschine' then (select pl.brutto_kg from palette pl where pl.id = dp.id) end,
               (select pl.gebindeart from palette pl where pl.id = dp.id)
          from demo_pal dp where dp.id = any(v_pal_ids);

        -- Verderb bis heute: Weibull je Sorte plus Sockel, mit Streuung je Lauf
        v_f := 1 - exp(-power(v_tage / d.lambda, d.k));
        v_schimmel := round(v_masse * power(1 - d.r, v_tage) * (d.sockel + v_f) * (0.8 + 0.4 * v_zufall));
        insert into schimmel_messung (auftrag_id, kg, ts) values (v_auftrag, greatest(v_schimmel, 1)::int, v_start + interval '5 hours');
        insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

        if d.weg = 'maschine' then
          -- ---- Die Sortier-CSV: was am Band ankommt, jeder Kürbis gewogen ----
          -- Masse am Band = Eingang − Verdunstung − Faules; das Gewicht je
          -- Kürbis ist mit der Lagerdauer entsprechend kleiner.
          v_x := v_masse * power(1 - d.r, v_tage) - v_schimmel;
          v_gramm := d.gramm * power(1 - d.r, v_tage);
          v_n := greatest(round(v_x * 1000 / v_gramm)::int, 50);
          -- Glockenförmig in 10-g-Stufen von −3σ bis +3σ, plus ein leichter
          -- zweiter Gipfel bei manchen Schlägen (ungleiche Reife).
          select jsonb_agg(jsonb_build_array(g, anz)) into v_hist from (
            select g, greatest(round(v_n * 10 * (
                     exp(-power((g - v_gramm) / d.sd, 2) / 2) / (d.sd * 2.5066)
                     + case when d.nr % 5 = 0 then 0.35 * exp(-power((g - v_gramm * 1.45) / (d.sd * 0.6), 2) / 2) / (d.sd * 0.6 * 2.5066) else 0 end
                   ))::int, 0) as anz
              from generate_series(greatest(round((v_gramm - 3 * d.sd) / 10) * 10, 100)::int,
                                   round((v_gramm + 3.5 * d.sd) / 10)::int * 10, 10) g) h
           where anz > 0;
          perform csv_lauf_speichern(
            d.nr, format('DEMO-%s-%s', d.nr, to_char(v_start, 'DD-MM-HH24-MI')),
            format('demo/sortierdateien/%s-%s.csv', d.nr, to_char(v_start, 'YYYYMMDD')),
            format('demo-pruefsumme-%s', v_auftrag),
            v_start + interval '90 minutes', 'dateiname',
            '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
            (v_n * 1.03)::int, 2 + v_lauf % 3, 5 + v_lauf % 7, (v_n * 0.02)::int, v_hist);

          -- Kisten je Kaliber gezählt: Masse des Bands durch das Kistengewicht
          v_kisten := array[]::int[];
          for v_i in 0 .. v_nb - 1 loop
            select coalesce(sum((e->>1)::numeric * (e->>0)::numeric), 0) / 1000 into v_kg_band
              from jsonb_array_elements(v_hist) e
             where (e->>0)::int >= (v_baender->v_i->>0)::int and (e->>0)::int < (v_baender->v_i->>1)::int;
            v_kisten := v_kisten || greatest(round(v_kg_band / (d.kg_kiste * (0.97 + 0.06 * v_zufall)))::int, 0);
          end loop;
          insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
          select v_auftrag, i - 1, v_kisten[i] from generate_series(1, v_nb) i where v_kisten[i] > 0
          on conflict (auftrag_id, kaliber_idx, sortierdatum) do nothing;
          insert into demo_lauf values (v_auftrag, d.nr, d.sorte, v_start, v_x, v_tage, 'kaliber', v_kaeufer, v_baender, d.kg_kiste, v_kisten);
        else
          -- ---- Von Hand: eine Palette gewogen, Ausschuss gewogen, fertige Palette ----
          select p2.* into p from demo_pal p2 where p2.id = v_pal_ids[1];
          v_wiegung := null;
          v_brutto := p.netto + p.kisten * 1.5 + 25;
          -- 0076: die gewogene Palette ist bekannt, nicht nur ihr Eingangstag.
          -- Jede vierte Wägung sagt ausserdem, wie viel davon faul war — der
          -- einzige Schimmelwert, dessen Palette nicht nach dem Aussehen
          -- ausgewählt wurde.
          insert into verdunstung_wiegung (auftrag_id, charge_nr, palette_id, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                           kisten, gebindeart, kuerbisse_pro_kiste, faul_kg, wiege_ts)
          values (v_auftrag, d.nr, p.id, p.datum, v_brutto,
                  round((p.netto * power(1 - d.r * (0.7 + 0.6 * v_zufall), v_start::date - p.datum) + p.kisten * 1.5 + 25) * 2) / 2.0,
                  p.kisten, 'G2', 4 + (d.nr % 3),
                  case when v_lauf % 4 = 0 then round(p.netto * (0.004 + 0.02 * v_zufall), 1) end,
                  v_start + interval '2 hours')
          returning id into v_wiegung;
          -- Die Wägung gehört zu der gezählten Palette mit demselben Zetteldatum —
          -- sonst zählte die Kohortenrechnung sie einem anderen Eingangstag zu.
          update auftrag_palette set wiegung_id = v_wiegung
           where id = (select min(id) from auftrag_palette
                        where auftrag_id = v_auftrag and eingangsdatum = p.datum);

          v_x := v_masse * power(1 - d.r, v_tage) - v_schimmel;
          v_klein := round(v_x * (0.025 + 0.02 * v_zufall));
          v_gross := round(v_x * (0.010 + 0.015 * (1 - v_zufall)));
          v_kisten_p := greatest(ceil(v_klein / 22.0), 1)::int;
          insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart, ts, bemerkung)
          values (v_auftrag, 'zu_klein', v_klein + v_kisten_p * 1.5 + 25, v_kisten_p, 'G2', v_start + interval '6 hours',
                  case when v_lauf % 6 = 0 then 'Viel Kleines in dieser Charge' end);
          if v_lauf % 3 = 0 then
            -- Einmal nicht gewogen, nur geschätzt — das zeigt die Datenqualität.
            insert into ausschuss_messung (auftrag_id, art, kg, ts) values (v_auftrag, 'zu_gross', v_gross::int, v_start + interval '6 hours');
          else
            v_kisten_p := greatest(ceil(v_gross / 22.0), 1)::int;
            insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart, ts)
            values (v_auftrag, 'zu_gross', v_gross + v_kisten_p * 1.5 + 25, v_kisten_p, 'G2', v_start + interval '6 hours');
          end if;
          insert into auftrag_angabe (auftrag_id, schluessel, wert)
          values (v_auftrag, 'ausschuss_leer', 'true'), (v_auftrag, 'ausschuss_von_auftrag', 'true');

          -- Fertige Paletten: bei „Kiste ab 8 kg" überfüllt (8.2–8.6), nach
          -- Kaliber ohne Soll — dort zählt nur das Kistengewicht.
          v_kg_band := case when v_art = 'kiste' then 8.15 + 0.45 * v_zufall else 11.5 + 1.5 * v_zufall end;
          for v_i in 1 .. 2 loop
            insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, kuerbisse_pro_kiste, ts)
            values (v_auftrag, d.nr, round((32 * (v_kg_band + 0.05 * v_i) + 32 * 1.5 + 25) * 2) / 2.0, 32, 'G2',
                    case when v_art = 'kiste' then 5 + (d.nr % 2) else null end,
                    v_start + make_interval(hours => 3 + v_i));
          end loop;
          -- Für das Fax: die Masse in Kisten (−1 = Kiste nach Soll, sonst Bänder gleich verteilt)
          v_kisten := array[]::int[];
          if v_art = 'kiste' then
            v_kisten := array[greatest(round((v_x - v_klein - v_gross) / v_kg_band)::int, 1)];
          else
            for v_i in 0 .. v_nb - 1 loop
              v_kisten := v_kisten || greatest(round((v_x - v_klein - v_gross) / v_nb / v_kg_band)::int, 0);
            end loop;
          end if;
          -- 0072: „die fertigen paletten werden eher nicht gezählt" — aber
          -- wenn doch, ist die Ausgangsmasse der Arbeit bekannt statt nur
          -- geschätzt. Zwei von drei Arbeiten zählen sie.
          if v_lauf % 3 <> 0 then
            update auftrag set fertige_paletten_gesamt =
                   greatest(ceil((v_x - v_klein - v_gross) / (32 * v_kg_band))::int, 1)
             where id = v_auftrag;
          end if;
          insert into demo_lauf values (v_auftrag, d.nr, d.sorte, v_start, v_x - v_klein - v_gross, v_tage, v_art, v_kaeufer, v_baender, v_kg_band, v_kisten);
        end if;
      end loop;
    end loop;
    raise notice 'Demo: Sortieren und Waschen + Sortieren angelegt (% Arbeiten)', (select count(*) from demo_lauf);
  end;

  -- ---------- 3. Waschen je Kaliber, Wochen später (Weg 1) ------------------
  -- Aus jedem Sortierlauf werden die Bänder nacheinander gewaschen: die
  -- gefüllten Kisten geleert, Palox abgelesen (Schimmel #2, klein), eine
  -- fertige Palette gewogen. Nicht jedes Band ist schon dran — was wartet,
  -- steht in der Auswertung als „wartet aufs Waschen".
  declare l record; v_i int; v_start timestamptz; v_neu bigint; v_zufall numeric; v_kg numeric; v_kisten int;
          v_anteil numeric; v_gewaschen int[]; v_zufall2 numeric;
          v_eigen boolean; v_ohne_pal boolean; v_von int; v_bis int;
  begin
    for l in select * from demo_lauf where art = 'kaliber' and exists (select 1 from auftrag a where a.id = demo_lauf.auftrag_id and a.station = 'sortieren') order by start_ts loop
      v_gewaschen := array[]::int[];
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_zufall := (hashtext(format('wasch-%s-%s-%s', l.nr, l.start_ts::date, v_i))::bigint & 2147483647)::numeric / 2147483647;
        -- Das letzte Band der späten Läufe wartet noch
        if l.kisten[v_i] = 0 or (v_i = array_length(l.kisten, 1) and l.start_ts > v_jetzt - interval '60 days') then
          v_gewaschen := v_gewaschen || 0; continue;
        end if;
        v_start := l.start_ts + make_interval(days => 6 + v_i * 5 + floor(v_zufall * 25)::int) + interval '1 hour';
        while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
        if v_start > v_jetzt - interval '1 day' then v_gewaschen := v_gewaschen || 0; continue; end if;
        v_kisten := l.kisten[v_i];
        -- 0054: manchmal nennt das Etikett kein Band der Fassung, sondern ein
        -- eigenes Kaliber — „ab 900 g" statt „Band 2". Dann steht die Grenze
        -- an der Arbeit und der Bandindex bleibt leer.
        v_eigen := (l.nr + v_i) % 13 = 0 and l.baender is not null
                   and jsonb_array_length(l.baender) > v_i - 1;
        if v_eigen then
          v_von := (l.baender->(v_i - 1)->>0)::int + 50;
          v_bis := (l.baender->(v_i - 1)->>1)::int - 50;
          if v_bis <= v_von then v_eigen := false; end if;
        end if;
        -- Auf Weg 1 sind die Eingangspaletten beim Waschen längst in
        -- Kaliberkisten aufgelöst. Meistens zählt der Vorarbeiter die
        -- Zwischenlager-Paletten; jede vierte Arbeit kann das nicht und gibt
        -- stattdessen die verarbeitete Menge an — sonst hätte der dort
        -- gemessene Schimmel keinen Nenner. Beim eigenen Kaliber ist das
        -- immer so: dort kennt niemand das Gewicht einer Kiste, weil dieses
        -- Band beim Sortieren nie gezählt wurde. Gemessen, bevor das hier
        -- stand: fünf Waschgänge meldeten „die Messung hat keinen Nenner" —
        -- richtig gerechnet, aber in einer Demo unnötig.
        v_ohne_pal := (l.nr + v_i + extract(day from l.start_ts)::int) % 4 = 0 or v_eigen;
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx, sortierschema_id, bemerkung,
                             kistensystem, stueck_je_kiste, kaliber_von_g, kaliber_bis_g, durchsatz_kg, geplante_paletten)
        values ('maschine', 'waschen', l.nr, v_start,
                v_start + make_interval(mins => 90 + v_kisten * 5 + floor(v_zufall * 30)::int),
                'abgeschlossen', case when v_eigen then null else v_i - 1 end,
                (select sortierschema_id from auftrag where id = l.auftrag_id), 'DEMO',
                'stueck', greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1),
                case when v_eigen then v_von end, case when v_eigen then v_bis end,
                case when v_ohne_pal then round(v_kisten * l.kg_je_kiste) end,
                case when v_ohne_pal then null else ceil(v_kisten / 32.0)::int end)
        returning id into v_neu;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_neu, id from profil order by erstellt_ts limit 2 on conflict do nothing;
        -- Q22, Schichtwechsel: an langen Waschgängen geht einer um vier Uhr
        -- und ein anderer übernimmt. Wer gegangen ist, steht mit seiner Zeit da.
        if v_kisten > 120 then
          update auftrag_teilnehmer set verlassen_ts = v_start + interval '4 hours'
           where auftrag_id = v_neu
             and profil_id = (select profil_id from auftrag_teilnehmer where auftrag_id = v_neu order by profil_id limit 1);
          insert into auftrag_teilnehmer (auftrag_id, profil_id, beigetreten_ts)
          select v_neu, id, v_start + interval '4 hours' from profil
           where id not in (select profil_id from auftrag_teilnehmer where auftrag_id = v_neu)
           order by erstellt_ts limit 1
          on conflict do nothing;
        end if;
        -- 0061: beim Waschen werden Paletten gezählt — das Sortierdatum vom
        -- Zettel und die Kisten je Palette (höchstens 32), so wie die Maske.
        if not v_ohne_pal then
          -- 0104: Seit Mitte August wiegt die Demo-Halle jede Wasch-Palette am
          -- Anfang der Strasse (die Regel des Betriebs vom 29. September; die
          -- Demo zeigt, was die App kann). Brutto = Palette + Kisten × (Tara +
          -- Kistengewicht der Charge, leicht streuend). Ältere Waschgänge
          -- bleiben ungewogen — für sie gelten die Ersätze.
          insert into auftrag_palette (auftrag_id, sortierdatum, kisten, gebindeart, brutto_gewogen_kg)
          select v_neu, l.start_ts::date, x.kisten, x.art,
                 case when v_start::date >= current_date - 45
                      then round(g.tara_kg_palette + x.kisten * (g.tara_kg_pro_kiste
                                 + l.kg_je_kiste * (0.96 + 0.08 * ((hashtext(format('waage-%s-%s', l.nr, s))::bigint & 2147483647)::numeric / 2147483647))), 1)
                 end
            from generate_series(1, ceil(v_kisten / 32.0)::int) s
            cross join lateral (select least(32, v_kisten - (s - 1) * 32) as kisten,
                                       case when s % 5 = 0 then 'IFCO 6416' else 'G2' end as art) x
            join gebinde g on g.art = x.art;
        end if;
        -- Schimmel #2: was seit dem Sortieren in der Kiste dazukam. Der Verderb
        -- geht in der Kiste weiter, nach derselben Kurve — bedingt auf das, was
        -- beim Sortieren noch gut war: (F(t_wasch) − F(t_sort)) / (1 − F(t_sort)).
        v_kg := v_kisten * l.kg_je_kiste;
        select d2.lambda, d2.k into v_anteil, v_zufall2 from demo_charge d2 where d2.nr = l.nr;
        v_anteil := greatest(
          ((1 - exp(-power((l.alter_tage + (v_start::date - l.start_ts::date)) / v_anteil, v_zufall2)))
           - (1 - exp(-power(l.alter_tage / v_anteil, v_zufall2))))
          / (exp(-power(l.alter_tage / v_anteil, v_zufall2))), 0.002);
        insert into schimmel_messung (auftrag_id, kg, ts)
        values (v_neu, greatest(round(v_kg * v_anteil * (0.75 + 0.5 * v_zufall)), 1)::int, v_start + interval '3 hours');
        insert into auftrag_angabe (auftrag_id, schluessel, wert)
        values (v_neu, 'eine_charge', 'true');
        -- Fertige Palette nach Kaliber: kein Soll, nur das Kistengewicht
        insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, ts, kaliber_idx, kuerbisse_pro_kiste, bemerkung)
        values (v_neu, l.nr, round((32 * l.kg_je_kiste * (0.96 + 0.08 * v_zufall) + 32 * 1.5 + 25) * 2) / 2.0, 32, 'G2',
                v_start + interval '2 hours', case when v_eigen then null else v_i - 1 end,
                greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1),
                case when v_eigen then format('Eigenes Kaliber %s–%s g', v_von, v_bis) end);
        -- Wie viele fertige Paletten am Ende dastanden. Ohne diese Zahl kennt
        -- die App nur die *gewogene* — die Ausgangsmasse wäre unbekannt.
        if (l.nr + v_i) % 3 <> 0 then
          update auftrag set fertige_paletten_gesamt = greatest(ceil(v_kisten / 32.0)::int, 1) where id = v_neu;
        end if;
        v_gewaschen := v_gewaschen || v_kisten;
      end loop;
      update demo_lauf set kisten = v_gewaschen where auftrag_id = l.auftrag_id;
    end loop;
    raise notice 'Demo: Waschgänge angelegt';
  end;

  -- ---------- 4. Fax und Lieferungen ----------------------------------------
  -- Nach dem Waschen steht die Ware in Kisten, bis eine Bestellung kommt. Das
  -- Fax macht daraus Paletten mit Etikett und sortiert dabei Faules aus —
  -- gewogen, kistenweise. Was gemacht wird, geht innert Tagen raus. Die
  -- Lieferungen einer Charge verteilen sich so über Wochen und verschränken
  -- sich mit denen anderer Chargen.
  declare l record; v_i int; v_start timestamptz; v_neu bigint; v_zufall numeric; v_kisten int; v_rest int;
          v_teil int; v_masse numeric; v_faul numeric; v_n_faul int; v_j int; v_kaeufer text; v_kunde text;
          v_lief numeric; v_schema bigint;
          -- 0061: die Verkaufsdatei zur Lieferung
          v_pos int := 0; v_lief_id bigint; v_lief_datum date; v_einheit text; v_inhalt int;
          v_gja numeric; v_menge numeric; v_stueck int; v_artikel text; v_artikel_id text;
  begin
    -- Die Warenwirtschaft der Demo: jede Lieferung steht auch als Zeile einer
    -- Verkaufsdatei da (Einheit, Gebindeinhalt, Kisten je Chargenzeile), so wie
    -- sie der Import aus dem Perigon anlegt. Daraus die verkauften Kisten.
    insert into ausgang_quelle (code, name, dateiname_muster, bemerkung)
    values ('DEMO', 'Demo-Warenwirtschaft', 'demo', 'DEMO') on conflict (code) do nothing;
    for l in select * from demo_lauf order by start_ts loop
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_rest := l.kisten[v_i];
        if v_rest <= 0 then continue; end if;
        v_j := 0;
        while v_rest > 0 loop
          v_j := v_j + 1;
          exit when v_j > 4;
          v_zufall := (hashtext(format('fax-%s-%s-%s-%s', l.nr, l.start_ts::date, v_i, v_j))::bigint & 2147483647)::numeric / 2147483647;
          -- Ein Teil der Ware wartet noch auf eine Bestellung
          if v_zufall < 0.12 then exit; end if;
          v_teil := least(v_rest, 32 * (1 + floor(v_zufall * 4)::int) + floor(v_zufall * 20)::int);
          v_start := l.start_ts + make_interval(days => 20 + v_i * 6 + v_j * 9 + floor(v_zufall * 12)::int) + interval '2 hours';
          while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
          exit when v_start > v_jetzt - interval '1 day';
          v_kaeufer := case when v_j % 3 = 0 then (case l.kaeufer when 'nordmarkt' then 'talhof' when 'talhof' then 'nordmarkt' when 'gruenwerk' then 'feldfrisch' else 'gruenwerk' end) else l.kaeufer end;
          v_schema := case when l.art = 'kiste' then sortierschema_fuer(l.sorte, l.kaeufer, v_start::date, 'kiste') else null end;
          -- 0060: die Palettenzahl als Gesamtzahl, die Tage seit dem Waschen, das
          -- Kistensystem. Jede zweite Fax-Arbeit zählt zusätzlich noch Kisten
          -- (der Weg vor 0060) — beide Wege müssen dieselbe Masse ergeben.
          insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, ende_ts, status, kaeufer, sortierschema_id, bemerkung,
                               kistensystem, soll_kg_pro_kiste, paletten_gesamt, tage_seit_waschen)
          values ('maschine', 'waschen', l.nr, true, v_start,
                  v_start + make_interval(mins => 40 + v_teil * 2 + floor(v_zufall * 25)::int),
                  'abgeschlossen', v_kaeufer, v_schema, 'DEMO',
                  case when l.art = 'kiste' then 'kiste_ab' else 'stueck' end,
                  case when l.art = 'kiste' then 8 end,
                  ceil(v_teil / 32.0)::int,
                  case when v_j % 3 = 0 then null else 1 + floor(v_zufall * 3)::int end)
          returning id into v_neu;
          insert into auftrag_teilnehmer (auftrag_id, profil_id)
          select v_neu, id from profil order by erstellt_ts limit 1 on conflict do nothing;
          if v_j % 2 = 1 then
            insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
            values (v_neu, case when l.art = 'kiste' then -1 else v_i - 1 end, v_teil);
          end if;
          insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_neu, 'eine_charge', 'true');
          -- Faules: kistenweise gewogen, 1–3 Kisten, Anteil je Sorte mit Streuung.
          -- Jede fünfte Fax-Arbeit hat nichts Faules — auch das ist eine Messung.
          v_masse := v_teil * l.kg_je_kiste;
          v_faul := round(v_masse * (select fax_anteil from demo_charge where nr = l.nr) * (0.4 + 1.2 * v_zufall), 1);
          if v_j % 5 = 0 or v_faul < 1 then
            insert into schimmel_messung (auftrag_id, kg, ts, bemerkung) values (v_neu, 0, v_start + interval '1 hour', 'Nichts Faules');
            v_faul := 0;
          else
            v_n_faul := least(greatest(ceil(v_faul / 9.0)::int, 1), 3);
            insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, mit_palette, ts)
            select v_neu, 0, round(v_faul / v_n_faul + 1.5 + (s - 1) * 0.5, 1), 1, 'G2', false,
                   v_start + make_interval(mins => 30 + s * 20)
              from generate_series(1, v_n_faul) s;
            select coalesce(sum(kg), 0) into v_faul from schimmel_messung where auftrag_id = v_neu;
          end if;
          -- Die Lieferung, wie die Verkaufsdatei sie führt (0061): Kisten × Inhalt,
          -- nominal — „Kiste ab 8 kg" steht mit 8 kg auf dem Lieferschein, die
          -- Stück-Kiste mit Stück × Nenngewicht. Was die Kiste wirklich wiegt,
          -- weiss nur die Waage (Überfüllung). 1–7 Tage nach dem Fax.
          v_lief_datum := (v_start + make_interval(days => 1 + floor(v_zufall * 6)::int))::date;
          v_kunde := case v_kaeufer when 'nordmarkt' then 'Nordmarkt Verteilzentrale' when 'talhof' then 'Talhof Bio AG'
                                    when 'gruenwerk' then 'Grünwerk Handel' else 'Feldfrisch Ost' end;
          v_pos := v_pos + 1;
          if l.art = 'kiste' then
            v_einheit := 'kg'; v_inhalt := 8; v_gja := 1;
            v_artikel := 'Bio Kürbis ' || l.sorte || ' lose'; v_artikel_id := 'kürb' || lower(left(l.sorte, 3));
          else
            v_stueck := greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1);
            v_einheit := 'Stk.'; v_inhalt := v_stueck;
            v_gja := round((select gramm from demo_charge where nr = l.nr) / 1000.0, 2);
            v_artikel := 'Bio Kürbis ' || l.sorte || ' Dem'; v_artikel_id := 'kürb' || lower(left(l.sorte, 3)) || 'd';
          end if;
          v_menge := v_teil * v_inhalt;
          v_lief := round(v_menge * v_gja, 1);
          insert into ausgang_artikel (artikel_id, artikel, ist_kuerbis, sorte, bemerkung)
          values (v_artikel_id, v_artikel, true, l.sorte, 'DEMO') on conflict (artikel_id, artikel) do nothing;
          insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, journal, auftragsnr,
                                     kunde, artikel_id, artikel, einheit, menge, gewicht_je_artikel, batch_menge,
                                     kg_position, kg_charge, gebindeart, gebinde_menge, gebinde_inhalt, batch_gebinde, produzent,
                                     erloes)
          values ('DEMO', v_pos, l.nr::text, 1, 'demo-' || v_pos, v_lief_datum, 'Lieferschein', 'LS-' || (100000 + v_pos),
                  v_kunde, v_artikel_id, v_artikel, v_einheit, v_menge, v_gja, v_menge,
                  v_lief, v_lief, 'IFCO', v_teil, v_inhalt, v_teil, 'Demo-Hof',
                  round(v_lief * (1.55 + 0.5 * v_zufall), 2))
          on conflict (quelle, pos_id, charge_extern, lauf_nr) do nothing;
          insert into lieferung (datum, charge_nr, sorte, kg, kisten, gebindeart, ziel, kunde, bemerkung)
          values (v_lief_datum, l.nr, l.sorte, v_lief, v_teil, 'G2', 'verkauf', v_kunde, 'DEMO')
          returning id into v_lief_id;
          insert into lieferung_import (lieferung_id, quelle, extern_id)
          values (v_lief_id, 'DEMO', format('DEMO:%s:%s:1', v_pos, l.nr));
          v_rest := v_rest - v_teil;
        end loop;
      end loop;
    end loop;
    -- Zu klein geht an die Tiere — als Lieferung mit Ziel Tierfutter, damit die
    -- Bilanz es sieht.
    insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
    select (a.start_ts + interval '3 days')::date, a.charge_nr, c.sorte, sum(m.kg), 'tierfutter', 'Hof Zürcher (Tiere)', 'DEMO'
      from ausschuss_messung m join auftrag a on a.id = m.auftrag_id join charge c on c.nr = a.charge_nr
     where a.bemerkung = 'DEMO' and m.art = 'zu_klein'
     group by a.id, a.start_ts, a.charge_nr, c.sorte;
    -- Und der Hofladen nimmt ab und zu ein paar Kisten
    insert into lieferung (datum, sorte, kisten, ziel, kunde, bemerkung)
    select (v_anker + 40 + i * 11)::date, case when i % 2 = 0 then 'Tiana' else 'Kaori Kuri' end, 6 + i % 5, 'hofladen', 'Hofladen', 'DEMO'
      from generate_series(1, 10) i;
    perform lieferung_import_zeilen_verbinden('DEMO');
    raise notice 'Demo: Fax und Lieferungen angelegt (mit Verkaufsdatei)';
  end;

  -- ---------- 4b. An jeder Station läuft nur eine Arbeit zugleich -----------
  -- Die Arbeiten sind je Charge entstanden; zwei Chargen können so am selben
  -- Tag zur selben Stunde stehen. Im Betrieb geht das nicht (ein Band, ein
  -- Palox je Station) — also rücken sie hintereinander, samt allem, was an
  -- ihnen hängt. Fax hat keinen Palox und läuft nebenher.
  declare v record; v_prev timestamptz; v_station text := ''; v_delta interval;
  begin
    for v in
      select id, palox_station(station)::text as station, start_ts, ende_ts from auftrag
       where bemerkung = 'DEMO' and not ist_fax and status = 'abgeschlossen' and abgebrochen_ts is null
       order by palox_station(station), start_ts, id
    loop
      if v.station <> v_station then v_station := v.station; v_prev := null; end if;
      if v_prev is not null and v.start_ts < v_prev + interval '20 minutes' then
        v_delta := (v_prev + interval '20 minutes') - v.start_ts;
        update auftrag set start_ts = start_ts + v_delta, ende_ts = ende_ts + v_delta where id = v.id;
        update auftrag_palette set ts = ts + v_delta where auftrag_id = v.id;
        update schimmel_messung set ts = ts + v_delta where auftrag_id = v.id;
        update ausschuss_messung set ts = ts + v_delta where auftrag_id = v.id;
        update ausgang_wiegung set ts = ts + v_delta where auftrag_id = v.id;
        update verdunstung_wiegung set wiege_ts = wiege_ts + v_delta where auftrag_id = v.id;
        update sortier_lauf set datei_zeit = datei_zeit + v_delta where auftrag_id = v.id;
        v.ende_ts := v.ende_ts + v_delta;
      end if;
      v_prev := v.ende_ts;
    end loop;
  end;

  -- ---------- 5. Palox-Ablesungen je Arbeit (AB-02) -------------------------
  -- Je Station läuft der Stand über die Arbeiten weiter: eine Ablesung zu
  -- Beginn (Stand unverändert) und eine am Ende. Geleert, wenn er sonst
  -- überliefe. Gespeichert wird der Stand, die Menge folgt daraus. Fax hat
  -- keinen Palox — dort ist das Faule gewogen.
  declare v record; v_stand numeric := 0; v_station text := ''; v_geleert boolean; v_i int := 0;
  begin
    for v in
      select s.id, s.auftrag_id, s.kg, palox_station(a.station)::text as station, a.start_ts, a.ende_ts
        from schimmel_messung s
        join auftrag a on a.id = s.auftrag_id
       where a.bemerkung = 'DEMO' and not a.ist_fax and s.palox_stand_kg is null and s.brutto_kg is null
       order by palox_station(a.station), a.start_ts, s.id
    loop
      v_i := v_i + 1;
      if v.station <> v_station then v_station := v.station; v_stand := palox_tara_kg(); end if;
      -- Zwischen zwei Arbeiten geleert, weil der Palox sonst überliefe. Das
      -- ist der Normalfall, und er kostet seit 0073 keine Messung mehr: die
      -- neue Arbeit beginnt einfach bei der leeren Box und liest ihren
      -- eigenen Anfang ab.
      if v_stand + v.kg > 800 then v_stand := palox_tara_kg(); end if;
      -- Jede 17. Arbeit hat die Ablesung zu Beginn vergessen — die Datenqualität zeigt es.
      if v_i % 17 <> 0 then
        insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert, ts)
        values (v.auftrag_id, 0, v_stand, false, v.start_ts + interval '10 minutes');
      end if;
      -- Jede 23. Arbeit wird MITTENDRIN geleert. Der Betrieb sagt, das kommt
      -- vor. Dann ist die Menge dieser Arbeit unbekannt — nicht null: wie
      -- viel beim Leeren herausging, weiss niemand (0073).
      v_geleert := v_i % 23 = 0;
      if v_geleert
        then v_stand := palox_tara_kg() + round(v.kg * 0.4);
        else v_stand := v_stand + v.kg;
      end if;
      update schimmel_messung
         set palox_stand_kg = v_stand, palox_geleert = v_geleert, ts = coalesce(v.ende_ts, v.start_ts + interval '5 hours') - interval '10 minutes'
       where id = v.id;
      if v_geleert then
        update auftrag set palox_unbekannt = true where id = v.auftrag_id;
      end if;
    end loop;
    raise notice 'Demo: Palox-Ablesungen nachgetragen';
  end;

  -- ---------- 6. Lagerkontrollen --------------------------------------------
  -- Gegriffene Paletten, wie sie der Bildschirm „Palette kontrollieren"
  -- erfasst: Eingangsdatum, Gewicht damals und jetzt, Kisten, Kistenart.
  -- Seit 0061 ohne „davon faul" und ohne Auswahlart — die Kontrolle ist eine
  -- Verdunstungsmessung, nichts weiter.
  declare p record; v_i int := 0; v_tag date; v_tage int; v_zufall numeric; d record;
  begin
    for p in select * from demo_pal where not verarbeitet
              order by (hashtext(format('kontrolle-%s-%s', nr, datum))::bigint & 2147483647), id loop
      v_i := v_i + 1;
      exit when v_i > 24;
      select * into d from demo_charge where nr = p.nr;
      v_zufall := (hashtext('kontr-' || v_i)::bigint & 2147483647)::numeric / 2147483647;
      v_tag := greatest(p.datum + 20, v_anker + 40 + v_i * 6);
      exit when v_tag >= current_date;
      v_tage := v_tag - p.datum;
      -- Wie die Palette gegriffen wurde, entscheidet, ob die Messung für die
      -- Selektionsprüfung taugt: zufällig erreichbar ist die ehrliche Vorgabe,
      -- Mitte-unten ist besser, gezielt („die sieht schlecht aus") ist für den
      -- Vergleich untauglich — und genau das soll die Demo zeigen.
      insert into verdunstung_wiegung (charge_nr, palette_id, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                       kisten, gebindeart, auswahl, faul_kg, wiege_ts, bemerkung)
      values (p.nr, p.id, p.datum, p.netto + p.kisten * 1.5 + 25,
              round((p.netto * power(1 - d.r * (0.8 + 0.4 * v_zufall), v_tage) + p.kisten * 1.5 + 25) * 2) / 2.0,
              p.kisten, 'G2',
              case v_i % 5 when 0 then 'gezielt' when 1 then 'mitte_unten' else 'erreichbar_zufaellig' end,
              case when v_i % 3 <> 0 then round(p.netto * (0.003 + 0.03 * v_zufall), 1) end,
              v_tag::timestamptz + interval '10 hours', 'DEMO-KONTROLLE');
    end loop;
    raise notice 'Demo: Lagerkontrollen angelegt';
  end;

  -- ---------- 6b. Kontrollpaletten: dieselbe Palette immer wieder ----------
  -- Die Lagerkontrolle (Bildschirm „Palette kontrollieren") lebt davon, dass
  -- eine gekennzeichnete Palette über Wochen immer wieder auf dieselbe Waage
  -- kommt. Zwei Wägungen derselben Palette ergeben eine Verdunstungsrate je
  -- Tag, ohne jede Annahme — der sauberste Wert, den der Betrieb hat.
  -- Ohne diesen Abschnitt blieb der ganze Bildschirm in der Demo leer.
  declare pk record; v_kp bigint; v_i int := 0; v_tag date; v_netto numeric;
          v_schimmel boolean; v_zufall numeric; v_j int; v_rate numeric;
  begin
    for pk in
      select dp.id, dp.nr, dp.datum, dp.netto, dp.kisten, dc.r, dc.sorte
        from demo_pal dp join demo_charge dc on dc.nr = dp.nr
       where not dp.verarbeitet
       order by dc.sorte, (hashtext(format('kp-%s-%s', dp.nr, dp.datum))::bigint & 2147483647)
    loop
      -- Je Sorte eine Kontrollpalette, höchstens zwölf.
      continue when exists (select 1 from kontrollpalette k join charge c on c.nr = k.charge_nr
                             where c.sorte = pk.sorte and k.bemerkung = 'DEMO');
      v_i := v_i + 1;
      exit when v_i > 12;
      v_tag := pk.datum + 14 + (pk.nr % 7);
      -- Zu spät angelegt lohnt sich nicht — aber das ist der Grund, diese
      -- Palette zu überspringen, nicht der Grund, aufzuhören.
      if v_tag >= current_date - 30 then v_i := v_i - 1; continue; end if;
      insert into kontrollpalette (charge_nr, palette_id, kennzeichen, standort, angelegt_ts, angelegt_von,
                                   eingangsdatum, brutto_eingang_kg, bemerkung)
      values (pk.nr, pk.id, format('K-%s-%s', pk.nr, chr(64 + v_i)),
              format('Halle %s, Reihe %s', 1 + v_i % 2, 1 + v_i % 6),
              v_tag::timestamptz + interval '9 hours', v_wer,
              pk.datum, round((pk.netto + pk.kisten * 1.5 + 25) * 2) / 2.0, 'DEMO')
      returning id into v_kp;
      -- Alle zwei bis drei Wochen gewogen, bis heute. Die Palette wird
      -- leichter, nie schwerer — und bei einer sieht man am Ende Schimmel,
      -- dann taugt das Paar nicht mehr für die Rate.
      v_j := 0;
      loop
        v_j := v_j + 1;
        v_tag := v_tag + 14 + ((hashtext(format('kpw-%s-%s-%s', pk.nr, pk.datum, v_j))::bigint & 7))::int;
        exit when v_tag >= current_date or v_j > 12;
        v_zufall := (hashtext(format('kpz-%s-%s-%s', pk.nr, pk.datum, v_j))::bigint & 2147483647)::numeric / 2147483647;
        v_netto := pk.netto * power(1 - pk.r * (0.85 + 0.3 * v_zufall), (v_tag - pk.datum));
        v_schimmel := v_i = 3 and v_tag > current_date - 45;
        insert into kontrollpalette_wiegung (kontrollpalette_id, brutto_kg, kisten, gebindeart,
                                             sichtbar_schimmel, erfasser, wiege_ts, ts, bemerkung)
        values (v_kp, round((v_netto + pk.kisten * 1.5 + 25) * 2) / 2.0, pk.kisten, 'G2',
                v_schimmel, v_wer, v_tag::timestamptz + interval '10 hours',
                v_tag::timestamptz + interval '10 hours',
                case when v_schimmel then 'Erste faule Stellen sichtbar'
                     when v_j = 1 then 'Erste Wägung nach dem Einlagern' end);
      end loop;
      -- Eine Kontrollpalette ist inzwischen verarbeitet — sie wird beendet,
      -- statt einfach zu verschwinden.
      if v_i = 5 then
        update kontrollpalette set beendet_ts = (current_date - 12)::timestamptz + interval '11 hours',
               beendet_grund = 'Palette verarbeitet'
         where id = v_kp;
      end if;
    end loop;
    raise notice 'Demo: Kontrollpaletten angelegt (% Stück, % Wägungen)',
      (select count(*) from kontrollpalette where bemerkung = 'DEMO'),
      (select count(*) from kontrollpalette_wiegung);
  end;

  -- ---------- 6c. Die Verkaufsdatei als Datei ------------------------------
  -- Die Zeilen der Warenwirtschaft kommen im Betrieb nicht einzeln, sondern
  -- als Excel-Datei: einmal im Monat hochgeladen, mit Prüfsumme und Zeitraum.
  -- Ohne diesen Abschnitt stand der Warenausgang-Import der Demo ohne eine
  -- einzige Datei da — als wäre die Ware aus dem Nichts gekommen.
  declare m record; v_datei bigint; v_n int; v_korr_monat date;
  begin
    -- Der Monat, dessen Datei ein zweites Mal hochgeladen wurde: der erste
    -- mit mindestens zwei Zeilen. Die Demo hängt am heutigen Datum; fällt
    -- die erste Lieferung ans Monatsende, hat der erste Monat nur eine
    -- Zeile — und eine Datei, die „2 geändert" sagt, während nur eine
    -- Zeile eine Änderungszeit trägt, wäre ein Fehler der Demo (0096).
    select date_trunc('month', datum)::date into v_korr_monat
      from ausgang_zeile where quelle = 'DEMO'
     group by 1 having count(*) >= 2 order by 1 limit 1;
    for m in
      select date_trunc('month', datum)::date as monat, min(datum) as von, max(datum) as bis,
             count(*)::int as n
        from ausgang_zeile where quelle = 'DEMO' group by 1 order by 1
    loop
      insert into ausgang_datei (quelle, dateiname, pruefsumme, n_zeilen, n_kuerbis, n_neu,
                                 n_geaendert, n_unveraendert, von_datum, bis_datum, bemerkung,
                                 hochgeladen_von, ts)
      values ('DEMO', format('Lieferungen_%s.xlsx', to_char(m.monat, 'YYYY-MM')),
              format('demo-datei-%s', to_char(m.monat, 'YYYYMM')),
              m.n + 4, m.n, m.n - (case when m.monat = v_korr_monat then 2 else 0 end),
              case when m.monat = v_korr_monat then 2 else 0 end,
              4, m.von, m.bis, 'DEMO', v_wer,
              (m.bis + 2)::timestamptz + interval '8 hours')
      returning id into v_datei;
      update ausgang_zeile set datei_id = v_datei
       where quelle = 'DEMO' and date_trunc('month', datum)::date = m.monat;
      -- Dieser Monat wurde ein zweites Mal hochgeladen, weil zwei Positionen
      -- in der Warenwirtschaft nachträglich korrigiert worden waren. Die Datei
      -- zählt sie als geändert, und die Zeilen tragen ihre Änderungszeit.
      if v_datei is not null and m.monat = v_korr_monat then
        update ausgang_zeile set geaendert_ts = (m.bis + 9)::timestamptz + interval '8 hours'
         where id in (select id from ausgang_zeile where datei_id = v_datei order by pos_id limit 2);
      end if;
    end loop;
    -- Zwei Abweichungen, wie sie wirklich vorkommen: einmal wurde eine
    -- Lieferung von Hand nachkorrigiert, einmal blieb eine Palette am Rampen-
    -- rand stehen. Der Abgleich „Datei gegen Lieferung" soll in der Demo nicht
    -- leer sein — sonst sieht niemand, dass es ihn gibt.
    -- Sortiert nach Datum, Charge und Menge, nicht nach der laufenden Nummer:
    -- die Nummer ist nach einem Neuaufbau eine andere, das Datum nicht.
    update lieferung set kg = round(kg * 0.94, 1)
     where id in (select l.id from lieferung l join lieferung_import i on i.lieferung_id = l.id
                   where l.bemerkung = 'DEMO' and l.kg > 400
                   order by l.datum, l.charge_nr, l.kg limit 1);
    update lieferung set kg = round(kg * 1.07, 1)
     where id in (select l.id from lieferung l join lieferung_import i on i.lieferung_id = l.id
                   where l.bemerkung = 'DEMO' and l.kg > 400
                   order by l.datum desc, l.charge_nr desc, l.kg desc limit 1);
    raise notice 'Demo: Verkaufsdateien angelegt (%)', (select count(*) from ausgang_datei where bemerkung = 'DEMO');
  end;

  -- ---------- 6d. Ernte abgeschlossen --------------------------------------
  -- Solange die Ernte einer Charge läuft, wandert ihr mittleres Eingangsdatum
  -- mit jeder Palette, und jede Altersangabe trägt den Zusatz „Ernte läuft
  -- noch". Für die früh geernteten Chargen hat der Betrieb längst gesagt, dass
  -- nichts mehr kommt — die späten stehen noch offen. Beides soll man sehen.
  update charge set ernte_abgeschlossen_ts = (
           select max(p.eingangsdatum) + 3 from palette p where p.charge_nr = charge.nr)::timestamptz + interval '18 hours'
   where nr in (select nr from demo_charge where kw <= 37)
     and ernte_abgeschlossen_ts is null
     and exists (select 1 from palette p where p.charge_nr = charge.nr and p.extern_id like 'demo-%');

  -- ---------- 7. Sonderfälle, wie sie in jeder Saison vorkommen -------------
  declare v_auftrag bigint; v_datum date; v_id bigint;
  begin
    -- (1) Eine abgebrochene Arbeit: falsche Charge gewählt
    insert into auftrag (weg, station, charge_nr, start_ts, bemerkung)
    values ('hand', 'waschen_sortieren', 1611, (v_anker + 63)::timestamptz + interval '9 hours', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, datum from demo_pal where nr = 1611 order by id limit 3;
    perform auftrag_abbrechen(v_auftrag, 'Falsche Charge gewählt');

    -- (2) Ein Zahlendreher beim Palox: 4500 statt 450 kg — die Rechnung lässt
    --     ihn aus, die Auffälligkeiten melden ihn ganz oben.
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
    values ('hand', 'waschen_sortieren', 1611, (v_anker + 70)::timestamptz + interval '8 hours',
            (v_anker + 70)::timestamptz + interval '15 hours', 'abgeschlossen', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, datum from demo_pal where nr = 1611 and not verarbeitet order by datum limit 6;
    update demo_pal set verarbeitet = true where id in (select id from demo_pal where nr = 1611 and not verarbeitet order by datum limit 6);
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 4500, 4545, (v_anker + 70)::timestamptz + interval '14 hours');
    insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

    -- (3) Ein Zetteldatum, das zu keiner Palette passt (12 und 21 vertauscht)
    select datum into v_datum from demo_pal where nr = 1613 order by datum limit 1;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select a.id, v_datum + 9 from auftrag a where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
     order by a.start_ts limit 1;

    -- (4) Ein Waschgang ohne gezählte Kisten: die Messung hat keinen Nenner
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx, bemerkung)
    values ('maschine', 'waschen', 1614, (v_anker + 95)::timestamptz + interval '8 hours',
            (v_anker + 95)::timestamptz + interval '11 hours', 'abgeschlossen', 1, 'DEMO')
    returning id into v_auftrag;
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 9, 300, (v_anker + 95)::timestamptz + interval '10 hours');

    -- (5) Eine Sortier-CSV, die keiner Arbeit zugeordnet ist (Warteschlange)
    perform csv_lauf_speichern(1619, 'DEMO-1619-ohne-arbeit', 'demo/sortierdateien/1619-ohne-arbeit.csv',
      'demo-pruefsumme-warteschlange',
      (v_anker + 130)::timestamptz + interval '13 hours', 'dateiname',
      '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
      420, 1, 3, 6,
      '[[800,40],[900,90],[1000,120],[1100,100],[1200,50],[1300,10]]'::jsonb);

    -- (6) Drei laufende Arbeiten von heute — damit die Masken nicht leer sind
    insert into auftrag (weg, station, charge_nr, start_ts, status, kaeufer, sortierschema_id, bemerkung,
                         kistensystem, soll_kg_pro_kiste)
    values ('hand', 'waschen_sortieren', 1631, now() - interval '2 hours', 'offen', 'nordmarkt',
            sortierschema_fuer('Mieluna', null, current_date, 'kiste'), 'DEMO', 'kiste_ab', 8)
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg)
    select v_auftrag, dp.datum, (select pl.brutto_kg from palette pl where pl.id = dp.id)
      from demo_pal dp where dp.nr = 1631 and not dp.verarbeitet order by dp.datum desc limit 3;
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 0, 45, now() - interval '110 minutes');

    insert into auftrag (weg, station, charge_nr, start_ts, status, kaliber_idx, bemerkung)
    select 'maschine', 'waschen', l.nr, now() - interval '90 minutes', 'offen', 0, 'DEMO'
      from demo_lauf l join auftrag a on a.id = l.auftrag_id
     where a.station = 'sortieren' and l.kisten[1] > 0 order by l.start_ts desc limit 1
    returning id into v_auftrag;
    if v_auftrag is not null then
      update auftrag set kistensystem = 'stueck', stueck_je_kiste = 6 where id = v_auftrag;
      insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl, sortierdatum) values (v_auftrag, 0, 6, current_date - 21);
    end if;

    insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, status, kaeufer, bemerkung)
    select 'maschine', 'waschen', l.nr, true, now() - interval '50 minutes', 'offen', 'talhof', 'DEMO'
      from demo_lauf l join auftrag a on a.id = l.auftrag_id
     where a.station = 'sortieren' order by l.start_ts limit 1
    returning id into v_auftrag;
    if v_auftrag is not null then
      update auftrag set kistensystem = 'stueck', stueck_je_kiste = 6 where id = v_auftrag;
      insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, ts)
      values (v_auftrag, 0, 8.5, 1, 'G2', now() - interval '20 minutes');
    end if;

    -- (7) Ein Palox, der zwischendurch geleert wurde, ohne dass jemand abgelesen
    --     hat: der Stand fällt von 410 auf 130. Die Menge dieser Arbeit ist
    --     unbekannt (0060) — die Auswertung sagt es, der Arbeiter wird nicht gefragt.
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, kistensystem, soll_kg_pro_kiste)
    values ('hand', 'waschen_sortieren', 1613, (v_anker + 118)::timestamptz + interval '8 hours',
            (v_anker + 118)::timestamptz + interval '14 hours', 'abgeschlossen', 'DEMO', 'kiste_ab', 8)
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg)
    select v_auftrag, dp.datum, (select pl.brutto_kg from palette pl where pl.id = dp.id)
      from demo_pal dp where dp.nr = 1613 and not dp.verarbeitet order by dp.datum limit 4;
    update demo_pal set verarbeitet = true where id in (select id from demo_pal where nr = 1613 and not verarbeitet order by datum limit 4);
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts)
    values (v_auftrag, 0, 410, (v_anker + 118)::timestamptz + interval '8 hours 10 minutes'),
           (v_auftrag, 0, 130, (v_anker + 118)::timestamptz + interval '13 hours 50 minutes');
    insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

    raise notice 'Demo: Sonderfälle und laufende Arbeiten angelegt';
  end;

  -- ---------- 8. Beteiligte an den laufenden Arbeiten ------------------------
  insert into auftrag_teilnehmer (auftrag_id, profil_id)
  select a.id, v_wer from auftrag a where a.bemerkung = 'DEMO' and a.status = 'offen'
  on conflict do nothing;

  -- ---------- 9. Rückmeldungen aus der Halle (0091, 0093, 0094) --------------
  -- Geschrieben, nicht gesprochen: Eine Aufnahme wäre eine Datei im Bucket,
  -- und die kann eine SQL-Funktion nicht anlegen. Jede Rückmeldung steht kurz
  -- nach dem Ende der Arbeit bei einer Person, die daran beteiligt war — die
  -- Arbeit aus Sonderfall 7 hat keine Beteiligten, dort ist es der
  -- Betriebsleiter selbst. Und sie steht an Arbeiten, an denen man sie im
  -- Dashboard auch findet.
  --
  -- 0094: Was die Halle sagt, ist die halbe Geschichte; was das Dashboard
  -- zeigt, ist die Kurzfassung, die jemand daraus gemacht hat — die Runde am
  -- Programm oder der Betriebsleiter. Drei der vier zur Ware sind gekürzt;
  -- die vierte ist noch nicht gelesen und steht darum noch nirgends.
  declare v_a1 bigint; v_a2 bigint; v_a3 bigint; v_a4 bigint;
  begin
    -- (1) Zur Ware, an der Sortier-Arbeit der Charge 1628 (Hagel auf dem
    --     hinteren Feld) mit dem meisten Faulen — fest an der Charge, denn die
    --     Demo hängt am Datum, und „die Arbeit mit dem meisten Faulen" wechselt
    --     sonst über Nacht die Charge (Runde AI, Prüfblock 0093 am 29. 9.).
    select a.id into v_a1
      from auftrag a join schimmel_messung s on s.auftrag_id = a.id
     where a.bemerkung = 'DEMO' and a.status = 'abgeschlossen' and a.station = 'sortieren' and a.charge_nr = 1628
     order by s.kg desc, a.id limit 1;
    -- (2) Zur Ware, an der Arbeit mit dem falschen Zetteldatum (Sonderfall 3):
    --     die Auffälligkeit zeigt die Kurzfassung mit an.
    select a.id into v_a2 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
     order by a.start_ts limit 1;
    -- (3) Zur Ware und (4) zur App, an der Arbeit, deren Palox zwischendurch
    --     geleert wurde (Sonderfall 7): beide Arten an einer Arbeit, wie es
    --     das Arbeitsfenster und Betrieb → Arbeiten zeigen.
    select a.id into v_a3 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
       and exists (select 1 from schimmel_messung s where s.auftrag_id = a.id and s.palox_stand_kg = 410)
     order by a.start_ts limit 1;
    -- (5) Zur Ware, noch nicht gelesen: an der ersten Wasch+Sortier-Arbeit
    --     der Charge 1636 — unter Betrieb → Arbeiten wartet sie auf ihre
    --     Kurzfassung, im Dashboard steht sie noch nicht.
    select a.id into v_a4 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1636 and a.station = 'waschen_sortieren' and a.status = 'abgeschlossen'
     order by a.start_ts limit 1;
    if v_a1 is null or v_a2 is null or v_a3 is null or v_a4 is null then
      raise exception 'Demo: die Arbeiten für die Rückmeldungen fehlen — die Saison oben hat sich geändert.';
    end if;
    insert into auftrag_rueckmeldung (auftrag_id, art, text, erfasser, ts, kurz, kurz_quelle, kurz_ts)
    select r.auftrag_id, r.art, r.text,
           coalesce((select t.profil_id from auftrag_teilnehmer t
                      where t.auftrag_id = r.auftrag_id order by t.profil_id limit 1), v_wer),
           coalesce(a.ende_ts, a.start_ts) + make_interval(mins => 3 * r.nr),
           r.kurz, r.quelle,
           case when r.kurz is not null then coalesce(a.ende_ts, a.start_ts) + make_interval(days => 1, hours => 8) end
      from (values
              (1, v_a1, 'ware',
               'Also am Anfang habe ich gedacht, das ist normal, aber dann waren so viele mit Dellen und Rissen, '
               'ich glaube das war der Hagel im Juli auf dem hinteren Feld, darum haben wir so viel weggeworfen.',
               'Hagelschaden', 'runde'),
              (2, v_a2, 'ware',
               'Der Zettel war nass, das Datum konnte man kaum lesen, ich habe 13. geschrieben, kann auch 31. gewesen sein.',
               'Zettel nass, Datum unsicher', 'betriebsleiter'),
              (3, v_a3, 'ware',
               'Sehr viel Faules, der Palox war randvoll — wir haben ihn zwischendurch geleert.',
               'Viel Faules, Palox zwischendurch geleert', 'runde'),
              (4, v_a3, 'app',
               'Wo trage ich ein, dass der Palox geleert wurde? Ich habe es nicht gefunden.',
               null, null),
              (5, v_a4, 'ware',
               'Die Kürbisse waren viel kleiner als sonst, fast alles K1, und ein paar mit weichen Stellen.',
               null, null)
           ) as r(nr, auftrag_id, art, text, kurz, quelle)
      join auftrag a on a.id = r.auftrag_id
     order by r.nr;
    raise notice 'Demo: Rückmeldungen aus der Halle angelegt (drei gekürzt, eine ungelesen, eine zur App)';
  end;

  drop table if exists demo_charge; drop table if exists demo_pal; drop table if exists demo_lauf;

  -- Die Auswertung wird hier absichtlich nicht neu gerechnet: Supabase gibt
  -- einem API-Aufruf acht Sekunden, und das Rechnen ist der teuerste Teil.
  -- Die App ruft auswertung_aktualisieren() gleich danach als eigenen
  -- Aufruf; demo_daten.sql tut dasselbe. Bis dahin steht die Auswertung als
  -- veraltet da — die Auslöser an den Tabellen haben das schon vermerkt.
  return (
    select format('Demo-Saison steht: %s Paletten in %s Chargen, %s Arbeiten (davon %s Fax), %s Sortierläufe, '
                  || '%s Lieferungen, %s Kontrollpaletten mit %s Wägungen, %s Verkaufsdateien, %s Rückmeldungen. '
                  || 'Eingang %s t. Jetzt in der App unter Lagermanagement anschauen.',
                  (select count(*) from palette where extern_id like 'demo-%'),
                  (select count(distinct charge_nr) from palette where extern_id like 'demo-%'),
                  (select count(*) from auftrag where bemerkung = 'DEMO'),
                  (select count(*) from auftrag where bemerkung = 'DEMO' and ist_fax),
                  (select count(*) from sortier_lauf where datei_name like 'DEMO-%'),
                  (select count(*) from lieferung where bemerkung = 'DEMO'),
                  (select count(*) from kontrollpalette where bemerkung = 'DEMO'),
                  (select count(*) from kontrollpalette_wiegung),
                  (select count(*) from ausgang_datei where bemerkung = 'DEMO'),
                  (select count(*) from auftrag_rueckmeldung r join auftrag a on a.id = r.auftrag_id where a.bemerkung = 'DEMO'),
                  (select round(sum(eingang_netto_kg) / 1000, 1) from v_charge_rueckgrat))
  );
end $fn$;


create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 104 $$;
