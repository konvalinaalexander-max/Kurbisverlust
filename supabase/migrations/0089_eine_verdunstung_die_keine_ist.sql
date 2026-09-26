-- =====================================================================
-- 0089 — Eine Verdunstung, die keine ist
--
-- Der Betrieb: „Kaori Kuri … hat eine tägliche Verdunstung von 4,8 %.
-- Kann ja natürlich nicht sein." Richtig — so schnell verdunstet kein
-- Kürbis. Eine Wägung mit dieser Rate ist ein falsches Zettelgewicht, eine
-- andere Palette oder falsche Kisten. Bis hierher zählte sie trotzdem in
-- die Rate der Sorte (v_koeff_roh_verdunstung nimmt alles, was
-- `verwendbar` ist), und `verwendbar` kannte nur die Fälle „schwerer
-- geworden", „unverändert", „Schimmel sichtbar", „abgebrochen".
--
-- Jetzt gibt es eine Grenze — eine Einstellung, keine Zahl im Code:
-- verdunstung_rate_max_pro_tag, Vorgabe 1 % je Tag (das Zehnfache dessen,
-- was die Wägungen im Herbst zeigen). Eine Wägung darüber ist nicht
-- plausibel: Sie zählt nicht in die Rate, steht grau im Bild und als
-- Auffälligkeit „Verdunstung" unter Messungen, mit dem Weg zur Korrektur.
--
-- Und jede Wägung sagt jetzt, WARUM sie nicht zählt (`grund`) — bisher
-- stand im Bild für alle dasselbe („die Palette wurde nicht leichter"),
-- auch wenn der Grund ein anderer war.
--
-- Dazu: erg_ausgang trägt `voll` — die Marge-Karte zeigt die Wägungen
-- hinter jeder Zeile und muss sagen können, welche nicht zählt (halbe
-- Palette).
-- =====================================================================

-- ---------- 1. Die Grenze als Einstellung -------------------------------
insert into einstellung (schluessel, wert, bemerkung) values
  ('verdunstung_rate_max_pro_tag', '0.01'::jsonb,
   'Höchste Verdunstung je Tag, die noch eine sein kann — als Anteil (0.01 = 1 % je Tag). '
   'Eine Wägung darüber ist keine Verdunstung, sondern ein falsches Zettelgewicht, eine andere '
   'Palette oder falsche Kisten: Sie zählt nicht in die Rate und steht unter Auffälligkeiten (0089).')
on conflict (schluessel) do nothing;

-- Ohne `set search_path`, mit ausgeschriebenem Schema — wie palox_tara_kg()
-- (0036): So kann der Planer die Funktion einbetten, statt sie je Zeile zu rufen.
create or replace function verdunstung_rate_max() returns numeric
language sql stable as $$
  select coalesce((select (wert #>> '{}')::numeric from public.einstellung
                    where schluessel = 'verdunstung_rate_max_pro_tag'), 0.01);
$$;
comment on function verdunstung_rate_max() is
  'Die Grenze aus der Einstellung verdunstung_rate_max_pro_tag (Vorgabe 0.01 = 1 % je Tag, 0089).';
-- Wie palox_tara_kg() (0036): nicht für Nichtangemeldete.
revoke execute on function verdunstung_rate_max() from public;
grant execute on function verdunstung_rate_max() to authenticated;

-- ---------- 2. Jede Wägung sagt, ob und warum sie zählt -----------------
-- Dieselben Spalten wie bisher (0069/0070), dazu `plausibel` und `grund`.
-- `verwendbar` ist jetzt genau: kein Grund dagegen.
--
-- Zur Form: Der Lasttest hat die erste Fassung dieser Sicht bei dreifacher
-- Saison mit +1.2 s erwischt. Der Planer setzt die Spalten einer flachen
-- Sicht an jeder Verwendungsstelle neu ein — die Rate stand in `plausibel`,
-- im Grund und in `rate_pro_tag`, und in jeder davon rechnete betriebstag()
-- von vorn. Darum die Stufen mit `offset 0`: einmal Netto und Lagertage,
-- einmal die Rate, einmal der Grund. So ist die Sicht schneller als die alte.
create or replace view v_verdunstung_messung with (security_invoker = true) as
select b.id,
       b.charge_nr,
       b.sorte,
       b.schlag,
       b.palette_id,
       b.eingangsdatum,
       b.wiege_ts,
       b.sichtbar_schimmel,
       b.erfasser,
       b.auftrag_id,
       b.netto_damals_kg,
       b.netto_jetzt_kg,
       b.lagertage,
       r.rate_pro_tag,
       (u.grund is null)                                               as verwendbar,
       (r.rate_pro_tag is null or r.rate_pro_tag <= k.rate_max)       as plausibel,
       u.grund
  from (
    -- Einmal je Zeile: Netto damals und jetzt, die Lagertage. Das `offset 0`
    -- hält den Block zusammen — sonst setzt der Planer jede Spalte an jeder
    -- Verwendungsstelle neu ein, und betriebstag() ist keine billige Funktion.
    select w.id, w.charge_nr, c.sorte, c.schlag, w.palette_id, w.eingangsdatum, w.wiege_ts,
           w.sichtbar_schimmel, w.erfasser, w.auftrag_id, w.gemessen,
           (a.id is not null and a.abgebrochen_ts is not null)                              as abgebrochen,
           w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette as netto_damals_kg,
           w.brutto_jetzt_kg  - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette as netto_jetzt_kg,
           (betriebstag(w.wiege_ts) - w.eingangsdatum)                                       as lagertage
      from verdunstung_wiegung w
      join charge c on c.nr = w.charge_nr
      left join auftrag a on a.id = w.auftrag_id
      left join gebinde g on g.art = w.gebindeart
    offset 0
  ) b
  -- Die Grenze einmal je Abfrage, nicht je Zeile.
  cross join (select verdunstung_rate_max() as rate_max) k
  cross join lateral (
    select zahl(case when b.netto_damals_kg > 0 and b.netto_jetzt_kg > 0 and b.lagertage > 0
                     then 1 - power(b.netto_jetzt_kg / b.netto_damals_kg, (1.0 / b.lagertage)::numeric)
                end, 6, 10000)::numeric(10,6) as rate_pro_tag
    offset 0
  ) r
  cross join lateral (
    -- Der erste Grund, der zutrifft — in der Reihenfolge, in der er sich
    -- beim Nachsehen aufklärt.
    select case
             when not b.gemessen                                     then 'nicht gemessen'
             when b.sichtbar_schimmel                                then 'Schimmel sichtbar — die Palette verlor mehr als Wasser'
             when b.abgebrochen                                      then 'Arbeit abgebrochen'
             when b.netto_damals_kg is null or b.netto_jetzt_kg is null then 'ohne Netto — die Tara des Gebindes fehlt'
             when b.netto_damals_kg <= 0 or b.netto_jetzt_kg <= 0    then 'Netto unter null — das Brutto ist kleiner als die Tara'
             when b.lagertage <= 0                                   then 'am Eingangstag gewogen — keine Lagerdauer'
             when b.netto_jetzt_kg > b.netto_damals_kg * 1.01        then 'schwerer geworden — Waagenrauschen oder ein kopiertes Eingangsgewicht'
             when b.netto_jetzt_kg = b.netto_damals_kg               then 'unverändert — dieselbe Zahl zweimal'
             when r.rate_pro_tag > k.rate_max
               then format('zu schnell — %s %% je Tag ist keine Verdunstung', round(r.rate_pro_tag * 100, 2))
           end as grund
  ) u;
comment on view v_verdunstung_messung is
  'Je Wägung derselben Palette: Netto damals und jetzt, Lagertage, die Tagesrate — '
  'und ob sie in die Rate der Sorte zählt (verwendbar). Seit 0089 sagt `grund`, '
  'warum nicht, und `plausibel`, ob die Rate unter der Grenze '
  'verdunstung_rate_max_pro_tag liegt: Was schneller schwindet, ist keine Verdunstung.';
grant select on v_verdunstung_messung to authenticated;

create or replace view v_wiegung_kennzahl with (security_invoker = true) as
select w.id,
       w.auftrag_id,
       w.charge_nr,
       c.sorte,
       c.schlag,
       w.eingangsdatum,
       w.wiege_ts,
       w.kisten,
       w.gebindeart,
       w.sichtbar_schimmel,
       w.kuerbisse_pro_kiste,
       (betriebstag(w.wiege_ts) - w.eingangsdatum)                                   as lagertage,
       n.netto_damals_kg,
       n.netto_jetzt_kg,
       zahl(n.netto_jetzt_kg / nullif(w.kisten, 0)::numeric, 3, 10000000)::numeric(10,3)                          as kg_pro_kiste,
       zahl(n.netto_jetzt_kg / nullif(w.kisten * w.kuerbisse_pro_kiste, 0)::numeric, 3, 10000000)::numeric(10,3)  as kg_pro_kuerbis,
       zahl(n.netto_damals_kg - n.netto_jetzt_kg, 2, 100000000)::numeric(10,2)                                     as verdunstung_kg,
       m.rate_pro_tag,
       m.verwendbar,
       m.plausibel,
       m.grund
  from verdunstung_wiegung w
  join charge c on c.nr = w.charge_nr
  left join auftrag a on a.id = w.auftrag_id
  left join gebinde g on g.art = w.gebindeart
  left join v_verdunstung_messung m on m.id = w.id
  cross join lateral (
    select zahl(w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000)::numeric(10,2) as netto_damals_kg,
           zahl(w.brutto_jetzt_kg  - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000)::numeric(10,2) as netto_jetzt_kg) n
 where w.gemessen and (a.id is null or a.abgebrochen_ts is null);
grant select on v_wiegung_kennzahl to authenticated;

-- Die gespeicherte Fassung neu, damit die zwei Spalten mitkommen — als
-- Bauanweisung mit Marke, wie in 0061/0079: So weiss der Verdichter, dass
-- dies die jüngste Fassung von erg_wiegung ist, und setup.sql baut sie
-- genau einmal.
-- verdichter: baut erg_wiegung
do $$
begin
  execute 'drop materialized view if exists erg_wiegung cascade';
  execute 'create materialized view erg_wiegung as select * from v_wiegung_kennzahl with no data';
  execute 'grant select on erg_wiegung to authenticated';
  execute format('comment on materialized view erg_wiegung is %L',
                 'Gespeichert: jede Wägung mit ihren Kennzahlen (v_wiegung_kennzahl), seit 0089 mit plausibel und grund. Schritt 4 des Rechenwerks.');
end $$;
create index if not exists erg_wiegung_ts on erg_wiegung (wiege_ts);
-- Die Beschreibung auch im Klartext (wie 0079): Der Verdichter zieht die
-- jüngste Klartext-Beschreibung nach — sonst stünde in setup.sql die von 0061.
comment on materialized view erg_wiegung is
  'Gespeichert: jede Wägung mit ihren Kennzahlen (v_wiegung_kennzahl), seit 0089 mit plausibel und grund. Schritt 4 des Rechenwerks.';

-- ---------- 3. Die fertigen Paletten tragen „voll" ----------------------
-- verdichter: baut erg_ausgang
do $$
begin
  execute 'drop materialized view if exists erg_ausgang cascade';
  execute 'create materialized view erg_ausgang as select * from v_ausgang_voll with no data';
  execute 'grant select on erg_ausgang to authenticated';
  execute format('comment on materialized view erg_ausgang is %L',
                 'Gespeichert: jede gewogene fertige Palette mit ihren Kennzahlen (v_ausgang_voll) — seit 0089 mit voll, damit die Marge-Karte sagen kann, welche Wägung nicht zählt.');
end $$;
create index if not exists erg_ausgang_ts on erg_ausgang (ts);
comment on materialized view erg_ausgang is
  'Gespeichert: jede gewogene fertige Palette mit ihren Kennzahlen (v_ausgang_voll) — seit 0089 mit voll, damit die Marge-Karte sagen kann, welche Wägung nicht zählt.';

-- ---------- 4. Die Auffälligkeit „Verdunstung" --------------------------
-- Der Zusatz von 0064 wird wie in 0083 als Ganzes neu gestellt, um einen
-- Zweig länger.
create or replace view v_plausibilitaet_0064_zusatz with (security_invoker = true) as
 SELECT 'Tara fehlt'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    (min(p.eingangsdatum))::timestamp with time zone AS start_ts,
    format('%s von %s Paletten der Charge haben kein Nettogewicht (%s kg brutto): %s. %s'::text, count(*), r.n_paletten, round(sum(p.brutto_kg)),
        CASE
            WHEN bool_or((p.gebindeart IS NULL)) THEN 'die Gebindeart steht nicht auf der Palette'::text
            WHEN bool_or((g.art IS NULL)) THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN bool_or((g.tara_kg_pro_kiste IS NULL)) THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN bool_or((g.tara_kg_palette IS NULL)) THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END,
        CASE
            WHEN (r.n_paletten_mit_netto = 0) THEN 'Damit hat die Charge gar keinen Eingang — sie fehlt in der ganzen Bilanz.'::text
            ELSE format(('Für sie rechnet der Eingang mit dem Mittel der übrigen: %s der %s kg '::text || 'Eingang sind hochgerechnet, nicht gewogen.'::text), round((r.eingang_netto_kg - r.eingang_netto_gemessen_kg)), round(r.eingang_netto_kg))
        END) AS befund,
        CASE
            WHEN bool_or((p.gebindeart IS NULL)) THEN 'Gebindeart am Wareneingang nachtragen.'::text
            WHEN (bool_or((g.art IS NULL)) OR bool_or((g.tara_kg_pro_kiste IS NULL)) OR bool_or((g.tara_kg_palette IS NULL))) THEN ('Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. '::text || 'Die Zahlen rechnen sich danach von selbst neu.'::text)
            ELSE 'Kistenzahl der Palette im Wareneingang nachtragen.'::text
        END AS rat
   FROM (((palette p
     LEFT JOIN gebinde g ON ((g.art = p.gebindeart)))
     JOIN charge c ON ((c.nr = p.charge_nr)))
     JOIN v_charge_rueckgrat r ON ((r.charge_nr = p.charge_nr)))
  WHERE (((p.brutto_kg - ((p.kisten)::numeric * g.tara_kg_pro_kiste)) - g.tara_kg_palette) IS NULL)
  GROUP BY p.charge_nr, c.sorte, r.n_paletten, r.n_paletten_mit_netto, r.eingang_netto_kg, r.eingang_netto_gemessen_kg
UNION ALL
 SELECT 'Überzählung'::text AS art,
    NULL::bigint AS auftrag_id,
    h.charge_nr,
    h.sorte,
    (h.eingangsdatum_mittel)::timestamp with time zone AS start_ts,
    format(('%s kg mehr ausgeliefert, als für diese Charge je als Eingang erfasst wurde '::text || '(%s kg Eingang, %s kg geliefert) — das sind %s %% des Eingangs'::text), round(h.ueberzaehlung_kg), round(h.eingang_kg), round(h.geliefert_kg), round((((100)::numeric * h.ueberzaehlung_kg) / NULLIF(h.eingang_kg, (0)::numeric)))) AS befund,
    (('Fehlt im Erntejournal eine Palette dieser Charge? Oder ist ein Lieferschein auf '::text || 'die falsche Chargennummer gebucht? Beides lässt sich nachtragen; bis dahin ist '::text) || 'die Verlustquote dieser Charge zu hoch, weil ihr Eingang zu klein ist.'::text) AS rat
   FROM v_hochrechnung_basis h
  WHERE (h.ueberzaehlung_kg > (0)::numeric)
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format((('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette '::text || 'dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — gerechnet '::text) || 'wird deshalb mit der mittleren Tara der Charge, nicht mit ihrer eigenen.'::text), count(*), ap.brutto_zettel_kg, to_char((ap.eingangsdatum)::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'::text AS rat
   FROM ((auftrag_palette ap
     JOIN auftrag a ON ((a.id = ap.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((ap.brutto_zettel_kg IS NOT NULL) AND (ap.eingangsdatum IS NOT NULL) AND (a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
           FROM palette p
          WHERE ((p.charge_nr = a.charge_nr) AND (p.brutto_kg = ap.brutto_zettel_kg)))) AND (NOT (EXISTS ( SELECT 1
           FROM v_palette p
          WHERE ((p.charge_nr = a.charge_nr) AND (p.brutto_kg = ap.brutto_zettel_kg) AND (p.eingangsdatum = ap.eingangsdatum) AND (p.netto_kg IS NOT NULL))))))
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
   FROM (((ausschuss_messung m
     JOIN auftrag a ON ((a.id = m.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
     JOIN gebinde g ON ((g.art = m.gebindeart)))
  WHERE (m.gemessen AND m.mit_palette AND (m.brutto_kg IS NOT NULL) AND (g.tara_kg_palette IS NOT NULL) AND (m.brutto_kg < ((2)::numeric * g.tara_kg_palette)) AND (a.abgebrochen_ts IS NULL))
UNION ALL
 SELECT 'Verdunstung'::text AS art,
    m.auftrag_id,
    m.charge_nr,
    m.sorte,
    m.wiege_ts AS start_ts,
    format('%s %% je Tag: %s kg → %s kg in %s Tagen — so schnell verdunstet kein Kürbis (Grenze %s %% je Tag)'::text,
           round(m.rate_pro_tag * 100, 2), round(m.netto_damals_kg), round(m.netto_jetzt_kg), m.lagertage,
           round(verdunstung_rate_max() * 100, 2)) AS befund,
    'Zettelgewicht, Kisten und Gebinde dieser Wägung prüfen — oder es ist eine andere Palette. Bis zur Korrektur zählt sie nicht in die Rate.'::text AS rat
   FROM v_verdunstung_messung m
  WHERE m.grund LIKE 'zu schnell%';
grant select on v_plausibilitaet_0064_zusatz to authenticated;

-- ---------- 5. Der Stand -------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 89 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
