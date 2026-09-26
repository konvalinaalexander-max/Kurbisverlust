-- =====================================================================
-- 0090 — Die Auffälligkeiten sagen, was sie meinen — und die Zettelpalette
--        rechnet mit ihren Kisten
--
-- Der Betrieb hat die Auffälligkeiten seiner Messungen durchgelesen und an
-- drei Stellen widersprochen — zu Recht:
--
-- 1. „Zettelgewicht": Eine gezählte Palette mit 235 kg vom Zettel und 18
--    Kisten G2, die im Wareneingang nicht steht, wurde mit der MITTLEREN
--    Tara der Charge gerechnet, obwohl ihre eigene Tara dasteht: 18 × 1.5 kg
--    Kiste + 25 kg Palette. Jetzt rechnet v_auftrag_palette_masse in dieser
--    Reihenfolge: gewogen → im Wareneingang gefunden → Zettel minus die
--    gezählten Kisten und ihre Tara (neu, masse_quelle 'zettel-kisten') →
--    Zettel minus mittlere Tara der Charge → Tagesmittel → Chargenmittel.
--    Die Auffälligkeit sagt, welcher Fall gilt.
--
-- 2. „Überzählung" (Charge 1625): „160 kg mehr ausgeliefert, als je als
--    Eingang erfasst wurde (9'549 kg Eingang, 6'348 kg geliefert)" — der
--    Betrieb: „der Ausgang ist ja kleiner als der Eingang. Warum sagst du,
--    wir sind 160 kg zu viel geliefert worden?" Der Satz war falsch. Gemeint
--    ist: Die Lieferungen brauchen nach der gerechneten Ausbeute mehr
--    Eingang, als erfasst ist. Jetzt steht genau das da — mit der Ausbeute
--    in Prozent und der dritten Möglichkeit, die der alte Rat verschwieg:
--    dass die Charge besser ist als das Modell.
--
-- 3. „Palox geleert": Der Rat kennt jetzt den Knopf aus 0084.
-- =====================================================================

-- ---------- 1. Die Zettelpalette rechnet mit ihren Kisten ----------------
create or replace view v_auftrag_palette_masse with (security_invoker = true) as
with wiegung as materialized (
  select vw.id,
         zahl(vw.brutto_damals_kg - vw.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000)::numeric(10,2) as netto_damals_kg,
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
  select ap.id,
         coalesce(pe.netto_kg,
                  -- 0090: kein Treffer im Wareneingang, aber Kisten und Gebinde
                  -- gezählt — dann die eigene Tara, nicht die mittlere.
                  case when pe.id is null and ap.kisten is not null
                        and g.tara_kg_pro_kiste is not null and g.tara_kg_palette is not null
                        and ap.brutto_zettel_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette > 0
                       then zahl(ap.brutto_zettel_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000)::numeric(10,2)
                  end,
                  zahl(ap.brutto_zettel_kg - cm.tara_mittel, 2, 100000000)::numeric(10,2)) as netto_kg,
         (pe.id is not null) as exakt,
         (pe.id is null and ap.kisten is not null
          and g.tara_kg_pro_kiste is not null and g.tara_kg_palette is not null
          and ap.brutto_zettel_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette > 0) as kisten_tara
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join lateral (
      select p.id, p.netto_kg
        from v_palette p
       where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum
         and p.brutto_kg = ap.brutto_zettel_kg and p.netto_kg is not null
       order by p.id limit 1) pe on true
    left join gebinde g on g.art = ap.gebindeart
    left join charge_mittel cm on cm.charge_nr = a.charge_nr
   where ap.brutto_zettel_kg is not null
)
select ap.id,
       ap.auftrag_id,
       a.charge_nr,
       a.start_ts,
       coalesce(w.netto_damals_kg, z.netto_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel) as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) as eingangsdatum,
       case
         when w.netto_damals_kg is not null       then 'gewogen'
         when z.netto_kg is not null and z.exakt  then 'zettel'
         when z.netto_kg is not null and z.kisten_tara then 'zettel-kisten'
         when z.netto_kg is not null              then 'zettel-charge-tara'
         when p.netto_kg is not null              then 'palette'
         when d.netto_mittel is not null          then 'datum-mittel'
         when cm.netto_mittel is not null         then 'charge-mittel'
         else 'unbekannt'
       end as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join wiegung w on w.id = ap.wiegung_id
  left join zettel z on z.id = ap.id
  left join v_palette p on p.id = ap.palette_id
  left join datum_mittel d on d.charge_nr = a.charge_nr and d.eingangsdatum = ap.eingangsdatum
  left join charge_mittel cm on cm.charge_nr = a.charge_nr
  left join charge_datum cd on cd.charge_nr = a.charge_nr
 where not (a.station = 'waschen' and not a.ist_fax);
comment on view v_auftrag_palette_masse is
  'Je gezählter Palette einer Arbeit ihr Netto und woher es stammt (masse_quelle): '
  'gewogen · zettel (im Wareneingang gefunden) · zettel-kisten (Zettel minus die gezählten '
  'Kisten und ihre Tara, 0090) · zettel-charge-tara · palette · datum-mittel · charge-mittel.';
grant select on v_auftrag_palette_masse to authenticated;

-- ---------- 2. Die Texte der Auffälligkeiten -----------------------------
-- Die Sicht als Ganzes neu, wie in 0087; geändert sind zwei Sätze
-- („Zettelgewicht", „Palox geleert").
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
            ELSE format(('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber wurde beim '::text || 'Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt'::text), g.anzahl, (g.kaliber_idx + 1))
        END AS befund,
        CASE
            WHEN (g.kaliber_idx = '-1'::integer) THEN ('Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '::text || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'::text)
            ELSE ('Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '::text || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.'::text)
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
    format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — %s'::text,
           count(*), ap.brutto_zettel_kg,
           CASE WHEN bool_and(ap.kisten IS NOT NULL AND ap.gebindeart IS NOT NULL)
                THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
                ELSE 'gerechnet wird mit der mittleren Tara der Charge; stehen Kisten und Gebinde an der Palette, mit deren Tara'::text END) AS befund,
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

-- Der Zusatz von 0064 als Ganzes neu, wie in 0083/0089; geändert ist der
-- Satz „Überzählung".
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
    format('Die Lieferungen dieser Charge (%s kg) brauchen nach der gerechneten Ausbeute (%s %% verkaufsfähig) %s kg Eingang — erfasst sind %s kg, also %s kg zu wenig. Geliefert wurde nicht mehr als eingelagert; es wurde mehr geliefert, als die Rechnung aus diesem Eingang erwartet.'::text,
           round(h.geliefert_kg),
           round((100)::numeric * h.geliefert_kg / NULLIF(h.eingang_kg + h.ueberzaehlung_kg, (0)::numeric)),
           round(h.eingang_kg + h.ueberzaehlung_kg), round(h.eingang_kg), round(h.ueberzaehlung_kg)) AS befund,
    'Drei Möglichkeiten: Im Erntejournal fehlt eine Palette dieser Charge; ein Lieferschein ist auf die falsche Chargennummer gebucht; oder diese Charge hat weniger Verlust als das Modell annimmt — dann ist „Im Lager" für sie zu klein gerechnet. Die ersten zwei lassen sich nachtragen.'::text AS rat
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
    format('%s %% je Tag: %s kg → %s kg in %s Tagen — so schnell verdunstet kein Kürbis (Grenze %s %% je Tag)'::text, round((m.rate_pro_tag * (100)::numeric), 2), round(m.netto_damals_kg), round(m.netto_jetzt_kg), m.lagertage, round((verdunstung_rate_max() * (100)::numeric), 2)) AS befund,
    'Zettelgewicht, Kisten und Gebinde dieser Wägung prüfen — oder es ist eine andere Palette. Bis zur Korrektur zählt sie nicht in die Rate.'::text AS rat
   FROM v_verdunstung_messung m
  WHERE (m.grund ~~ 'zu schnell%'::text);
grant select on v_plausibilitaet_0064_zusatz to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 90 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
