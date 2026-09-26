-- =====================================================================
-- 0092 — Das Kistengewicht je Band kommt von der Waage, nicht vom Zählen
--
-- Gefunden beim Prüfen der Herleitungen (docs/HERLEITUNG.md): Die Masse
-- einer Wasch-Arbeit aus Kisten ist Kisten × Kistengewicht des Bandes, und
-- das Kistengewicht kam aus v_koeff_gebinde — aus Sortierläufen, bei denen
-- die gefüllten Kisten je Band GEZÄHLT wurden. Seit Runde Q zählt das
-- niemand mehr („niemand wird händisch die kisten zählen"). Die Quelle war
-- versiegt, die Auffälligkeit „Kistengewicht unbekannt" stand bei jedem
-- Waschgang ohne gewogene fertige Paletten — und ihr Rat („beim nächsten
-- Sortierlauf zählen") war nicht mehr befolgbar. Der Betrieb sah sie
-- „fast zehnmal".
--
-- Die Waage weiss es besser: Eine Wasch-Arbeit, die ihre Kaliber-Paletten
-- gezählt (Kisten hinein) UND ihre fertigen Paletten gewogen hat (Masse
-- heraus), misst das Kistengewicht des Bandes selbst — Masse heraus ÷
-- Kisten hinein. Das Faule und der Ausschuss des Waschgangs fehlen in der
-- Masse heraus; das Kistengewicht ist darum eher etwas zu klein, nie zu
-- gross. Eine solche Arbeit je Sorte und Band genügt; jede weitere macht
-- die Zahl sicherer. Und sie gilt rückwirkend, denn es ist eine Sicht.
--
-- Der alte Weg (gezählte Kisten am Sortierlauf) bleibt daneben stehen —
-- was einmal gezählt wurde, zählt weiter.
-- =====================================================================

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
), s as (
  select q.sorte, q.kaliber_idx, count(*)::int as n,
         sum(q.kg) / nullif(sum(q.anzahl), 0)::numeric as kg_je_gebinde,
         stddev_samp(q.kg / q.anzahl::numeric) as sd
    from (select sorte, kaliber_idx, anzahl, kg from je_arbeit
          union all
          select sorte, kaliber_idx, anzahl, kg from je_wasch) q
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
comment on view v_koeff_gebinde is
  'Das Kistengewicht je Sorte und Kaliberband: aus Wasch-Arbeiten, die hinein '
  'gezählt und heraus gewogen haben (0092), und aus Sortierläufen mit gezählten '
  'Kisten (0060). kaliber_idx −1: Sollgewicht-Kisten aus gewogenen fertigen Paletten.';
grant select on v_koeff_gebinde to authenticated;

-- ---------- Die Auffälligkeit sagt, was jetzt hilft ----------------------
-- Die Sicht als Ganzes neu, wie in 0087/0090; geändert ist der Zweig
-- „Kistengewicht": Befund und Rat nennen die Waage, nicht mehr das Zählen.
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
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen. Daraus kennt die App das Kistengewicht des Bandes — rückwirkend für alle Waschgänge dieser Sorte, auch für diesen.'::text
        END AS rat
   FROM ((v_auftrag_gebinde_masse g
     JOIN auftrag a ON ((a.id = g.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((g.kg IS NULL) AND (g.anzahl > 0) AND (g.kaliber_idx <> '-2'::integer))
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
grant select on v_plausibilitaet to authenticated;

-- Der Zusatz von 0054 (Kaliber-Paletten beim Waschen, eigenes Kaliber) als
-- Ganzes neu, wie in 0065; geändert sind Befund und Rat: die Waage, nicht
-- das Zählen.
create or replace view v_plausibilitaet_0054_zusatz with (security_invoker = true) as
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber für ein Band mit diesen Grenzen hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, a.kaliber_von_g, a.kaliber_bis_g) AS befund,
    'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen.'::text AS rat
   FROM ((v_auftrag_gebinde_masse g
     JOIN auftrag a ON ((a.id = g.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((g.kg IS NULL) AND (g.anzahl > 0) AND (g.kaliber_idx = '-2'::integer))
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
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen — dann kennt die App das Kistengewicht des Bandes, rückwirkend auch für diese Arbeit.'::text
        END AS rat
   FROM ((v_auftrag_wasch_paletten wp
     JOIN auftrag a ON ((a.id = wp.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((wp.kg IS NULL) AND (wp.kisten > 0))
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
grant select on v_plausibilitaet_0054_zusatz to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 92 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
