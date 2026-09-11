-- =====================================================================
-- 0070 — Die Zeit läuft vorwärts, und eine Palette ohne echtes Zettelgewicht
--        rechnet nicht mit
--
-- Der Betrieb hat gemeldet: Auf „Ursachen → Palox: Faules im Lager" reichte
-- die x-Achse bis minus tausend Tage, und alle echten Messungen sassen als
-- ein Strich ganz rechts. Ursache war ein Zettel mit dem Jahr 2029 statt
-- 2026: aus dem Eingangsdatum in der Zukunft wurden negative Lagertage, und
-- die Auswertung hielt den Punkt für plausibel. Gespeichert ist der Zettel
-- richtig so (er ist eine Beobachtung, kein Fehler des Programms) — falsch war,
-- was die Auswertung daraus machte. Diese Migration stellt das an der Wurzel ab.
--
-- WAS SICH ÄNDERT
--
--   1. Ein Schimmelpunkt mit negativen Lagertagen ist nie plausibel.
--      `v_schimmel_beobachtung` prüfte bisher nur den Anteil (ist er zwischen
--      0 und 0.5?), nie das Vorzeichen der Zeit. Jetzt: plausibel nur, wenn
--      auch die Lagertage ≥ 0 sind. Ebenso im Wasch-Zweig von
--      `v_schimmel_punkte`. Der Punkt bleibt in der Sicht (Beobachtung),
--      trägt aber plausibel = false und fällt aus Kurve, Treppe und Kaskade.
--
--   2. Eine Wägung ohne Gewichtsverlust ist keine Verdunstungsmessung.
--      `v_verdunstung_messung` verlangte bisher nur, dass die Palette nicht
--      schwerer geworden ist (≤ 1 % mehr). Wer eine sortierte Palette wiegt,
--      kennt ihr Eingangsgewicht aber gar nicht (die Kisten stammen aus
--      mehreren Eingangspaletten) — trägt er das heutige Gewicht auch als
--      „damals" ein, entsteht eine Rate von exakt null, die als verwendbar in
--      die Sorte einfliesst und deren Verdunstungsrate nach unten zieht.
--      Jetzt: eine Wägung, bei der das Nettogewicht auf das Gramm genau gleich
--      geblieben ist (netto jetzt = netto damals, Rate exakt null), ist nicht
--      verwendbar — zwei echte Wägungen treffen sich nicht auf das Gramm, das
--      ist ein kopiertes Eingangsgewicht. Eine kleine Zunahme durch
--      Waagenrauschen bleibt dagegen verwendbar (0056). Das ist die Datenbank-Seite der
--      Entscheidung des Betriebs, sortierte Paletten gar nicht erst als
--      Lagerkontrolle zu wiegen (Frage 57 in docs/FRAGEN.md).
--
--   3. Zwei neue Auffälligkeiten in `v_plausibilitaet`:
--      · „Zetteldatum Zukunft" — ein Eingangsdatum nach heute (das falsche
--        Jahr). Der Betriebsleiter sieht es unter Messungen und korrigiert es.
--      · „Palettengewicht" — eine Eingangspalette über 2 000 kg brutto; das
--        gibt es nicht, es ist ein Zahlendreher.
--      Dazu ein eigener Grund im Wägungs-Zweig für die Palette ohne
--      Gewichtsverlust (das kopierte Eingangsgewicht).
--
-- WAS DIESE MIGRATION NICHT ANFASST — UND WARUM, MIT ZAHL
--
--   Der Sortier-Eingang (`mv_sortier_eingang`) mittelt die Eingangsdaten der
--   sortierten Paletten einer Charge; eine Palette mit falschem Jahr zieht
--   diesen Mittelwert mit, und dann bekommt auch ein späterer, sauberer
--   Waschgang derselben Charge falsche Lagertage. Und `mv_auftrag_masse`
--   rechnet die Lagertage noch mit dem UTC-Tag (`start_ts::date`) statt mit
--   dem Betriebstag — 0067 hat diesen Punkt gemessen und bewusst liegen
--   lassen: beides sind **gespeicherte** Sichten, und `drop materialized view
--   … cascade` nimmt 51 weitere Objekte mit, praktisch das ganze Rechenwerk.
--   Von 309 Arbeiten der Demosaison fallen bei fünf UTC-Tag und Betriebstag
--   auseinander, und die ganze Auswertung danach ergibt dieselben Zahlen bis
--   auf den Rappen. Der falsche Zettel wird jetzt als Auffälligkeit gemeldet
--   und aus der Statistik gehalten (Punkt 1); die verbleibende Wirkung ist,
--   dass die **angezeigten** Lagertage eines mitbetroffenen Waschgangs
--   daneben liegen, bis der Betriebsleiter das Jahr berichtigt — dann rechnet
--   sich alles richtig. Der 51-Objekt-Umbau steht als offener Punkt in
--   docs/GEGENPROBE_BEFUND.md (N-03, N-04).
--
-- Ausgeschrieben, nicht umgeformt: dieselben vier Sichten stehen hier
-- vollständig mit `create or replace view` (verdichten.mjs übernimmt die
-- zuletzt geschriebene Fassung nach setup.sql). Jede trägt
-- `with (security_invoker = true)` — sonst gälte die Zeilenregel der Tabellen
-- darunter beim Lesen durch sie nicht (0069).
-- =====================================================================

set client_min_messages = warning;

create or replace view v_verdunstung_messung with (security_invoker = true) as
 SELECT w.id,
    w.charge_nr,
    c.sorte,
    c.schlag,
    w.palette_id,
    w.eingangsdatum,
    w.wiege_ts,
    w.sichtbar_schimmel,
    w.erfasser,
    w.auftrag_id,
    n.netto_damals_kg,
    n.netto_jetzt_kg,
    betriebstag(w.wiege_ts) - w.eingangsdatum AS lagertage,
    zahl(
        CASE
            WHEN n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (betriebstag(w.wiege_ts) - w.eingangsdatum) > 0 THEN 1::numeric - power(n.netto_jetzt_kg / n.netto_damals_kg, 1.0 / (betriebstag(w.wiege_ts) - w.eingangsdatum)::numeric)
            ELSE NULL::numeric
        END, 6, '10000'::numeric)::numeric(10,6) AS rate_pro_tag,
    w.gemessen AND NOT w.sichtbar_schimmel AND n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (betriebstag(w.wiege_ts) - w.eingangsdatum) > 0 AND n.netto_jetzt_kg <= (n.netto_damals_kg * 1.01) AND n.netto_jetzt_kg <> n.netto_damals_kg AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AS verwendbar
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_damals_kg,
            w.brutto_jetzt_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_jetzt_kg) n;

create or replace view v_schimmel_beobachtung with (security_invoker = true) as
 SELECT am.auftrag_id,
    am.charge_nr,
    am.sorte,
    am.schlag,
    am.weg,
    am.station,
    am.start_ts,
    am.lagertage,
    am.masse_quelle,
    s.kg AS schimmel_kg,
    am.eingang_netto_kg AS eingang_kg,
    zahl(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 2, '10000000000'::numeric)::numeric(12,2) AS basis_jetzt_kg,
    s.kg / NULLIF(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 0::numeric) AS anteil,
    anteil_plausibel(s.kg / NULLIF(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 0::numeric)) AND am.lagertage >= 0::numeric AS plausibel,
    am.ist_fax
   FROM v_auftrag_masse am
     JOIN v_schimmel_menge s ON s.auftrag_id = am.auftrag_id
     LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = am.sorte
     CROSS JOIN LATERAL ( SELECT LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            GREATEST(am.lagertage, 0::numeric) AS tage) x
  WHERE am.eingang_netto_kg IS NOT NULL AND am.lagertage IS NOT NULL;

create or replace view v_schimmel_punkte with (security_invoker = true) as
 WITH sortier_lauf_anteil AS MATERIALIZED (
         SELECT b.charge_nr,
            b.start_ts,
            b.schimmel_kg,
            b.basis_jetzt_kg
           FROM v_schimmel_beobachtung b
          WHERE b.station = 'sortieren'::station AND b.plausibel AND b.anteil IS NOT NULL
        ), gemischt AS (
         SELECT v_auftrag_angabe.auftrag_id
           FROM v_auftrag_angabe
          WHERE v_auftrag_angabe.schluessel = 'eine_charge'::text AND v_auftrag_angabe.wert = 'false'::text
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lagertage,
    b.schimmel_kg,
    b.basis_jetzt_kg,
    b.anteil,
    b.plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    b.auftrag_id
   FROM v_schimmel_beobachtung b
     LEFT JOIN gemischt g ON g.auftrag_id = b.auftrag_id
  WHERE b.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])
UNION ALL
 SELECT a.charge_nr,
    a.sorte,
    a.schlag,
    a.lagertage,
    s.kg AS schimmel_kg,
    a.eingang_netto_kg + s.kg AS basis_jetzt_kg,
    k.f2 AS anteil,
    anteil_plausibel(k.f2) AND a.lagertage >= 0::numeric AS plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    a.auftrag_id
   FROM v_auftrag_masse a
     JOIN v_schimmel_menge s ON s.auftrag_id = a.auftrag_id
     LEFT JOIN gemischt g ON g.auftrag_id = a.auftrag_id
     LEFT JOIN LATERAL ( SELECT sum(sl.schimmel_kg) / NULLIF(sum(sl.basis_jetzt_kg), 0::numeric) AS f1
           FROM sortier_lauf_anteil sl
          WHERE sl.charge_nr = a.charge_nr AND sl.start_ts <= a.start_ts) sa ON true
     CROSS JOIN LATERAL ( SELECT s.kg / NULLIF(a.eingang_netto_kg + s.kg, 0::numeric) AS g) x
     CROSS JOIN LATERAL ( SELECT 1::numeric - (1::numeric - LEAST(GREATEST(COALESCE(sa.f1, 0::numeric), 0::numeric), 0.99)) * (1::numeric - LEAST(GREATEST(COALESCE(x.g, 0::numeric), 0::numeric), 0.99)) AS f2) k
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.lagertage IS NOT NULL AND a.eingang_netto_kg IS NOT NULL AND a.eingang_netto_kg > 0::numeric
UNION ALL
 SELECT w.charge_nr,
    w.sorte,
    w.schlag,
    w.lagertage,
    v.faul_kg AS schimmel_kg,
    w.netto_jetzt_kg AS basis_jetzt_kg,
    v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric) AS anteil,
    anteil_plausibel(v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric)) AS plausibel,
    'lager'::text AS quelle,
    NULL::bigint AS auftrag_id
   FROM v_verdunstung_messung w
     JOIN verdunstung_wiegung v ON v.id = w.id
  WHERE v.faul_kg IS NOT NULL AND v.gemessen AND w.netto_jetzt_kg > 0::numeric AND w.lagertage > 0;

create or replace view v_plausibilitaet with (security_invoker = true) as
 SELECT 'Schimmel'::text AS art,
    b.auftrag_id,
    b.charge_nr,
    b.sorte,
    b.start_ts,
    format('%s kg Schimmel auf %s kg Ware — das wären %s %%'::text, round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100::numeric)) AS befund,
    'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text AS rat
   FROM v_schimmel_beobachtung b
  WHERE b.anteil IS NOT NULL AND NOT b.plausibel AND NOT b.ist_fax AND b.lagertage >= 0::numeric
UNION ALL
 SELECT 'Fax'::text AS art,
    f.auftrag_id,
    f.charge_nr,
    f.sorte,
    f.start_ts,
    format('%s kg Faules bei %s (%s kg) — das wären %s %%'::text, round(f.faul_kg),
        CASE
            WHEN f.paletten_gesamt > 0 THEN f.paletten_gesamt || ' Paletten'::text
            ELSE f.kisten || ' Kisten'::text
        END, round(f.masse_kg), round(f.anteil * 100::numeric)) AS befund,
    'Entweder die Palettenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'::text AS rat
   FROM v_fax_beobachtung f
  WHERE f.anteil IS NOT NULL AND NOT f.plausibel
UNION ALL
 SELECT 'Ausschuss'::text AS art,
    a.auftrag_id,
    a.charge_nr,
    a.sorte,
    NULL::timestamp with time zone AS start_ts,
    format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse'::text, round(COALESCE(a.klein_kg, 0::numeric)), round(COALESCE(a.gross_kg, 0::numeric)), round(a.basis_kg)) AS befund,
    'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'::text AS rat
   FROM v_ausschuss_beobachtung a
  WHERE a.weg = 'hand'::verarbeitungsweg AND NOT a.plausibel
UNION ALL
 SELECT 'Ohne Nenner'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein'::text, concat_ws(' und '::text,
        CASE
            WHEN COALESCE(s.kg, 0::numeric) > 0::numeric THEN round(s.kg) || ' kg Faules'::text
            ELSE NULL::text
        END,
        CASE
            WHEN COALESCE(x.kg, 0::numeric) > 0::numeric THEN round(x.kg) || ' kg zu klein/gross'::text
            ELSE NULL::text
        END),
        CASE
            WHEN a.ist_fax THEN 'keine Palette gezählt oder noch keine fertige Palette dieser Sorte gewogen'::text
            WHEN a.station = 'waschen'::station THEN 'keine Kiste gezählt und keine Menge eingetragen'::text
            WHEN a.station = 'waschen_sortieren'::station THEN 'keine Palette mit Gewicht vom Zettel gezählt'::text
            ELSE 'keine Palette gezählt'::text
        END) AS befund,
        CASE
            WHEN a.ist_fax THEN ('Die Palettenzahl am Ende der Fax-Arbeit eintragen. Fehlt die Palettenmasse, '::text || 'beim Waschen oder Waschen + Sortieren eine fertige Palette wiegen — sie '::text) || 'gilt dann für alle Fax-Arbeiten der Sorte.'::text
            WHEN a.station = 'waschen'::station THEN 'Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich '::text || 'selbst) oder die verarbeitete Menge in kg nachtragen.'::text
            WHEN a.station = 'waschen_sortieren'::station THEN 'Die Paletten mit Datum und Gewicht vom Zettel am Auftrag nachtragen.'::text
            ELSE 'Die gezählten Paletten am Auftrag nachtragen.'::text
        END AS rat
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_schimmel_menge s ON s.auftrag_id = a.id
     LEFT JOIN ( SELECT ausschuss_messung.auftrag_id,
            sum(ausschuss_messung.kg)::numeric AS kg
           FROM ausschuss_messung
          WHERE ausschuss_messung.gemessen
          GROUP BY ausschuss_messung.auftrag_id) x ON x.auftrag_id = a.id
     LEFT JOIN v_auftrag_masse m ON m.auftrag_id = a.id
  WHERE a.abgebrochen_ts IS NULL AND (COALESCE(s.kg, 0::numeric) > 0::numeric OR COALESCE(x.kg, 0::numeric) > 0::numeric) AND COALESCE(m.eingang_netto_kg, 0::numeric) <= 0::numeric
UNION ALL
 SELECT 'Palox'::text AS art,
    s.auftrag_id,
    a.charge_nr,
    c.sorte,
    s.ts AS start_ts,
    format('Waagenstand %s kg liegt unter dem Leergewicht des Palox (%s kg)'::text, s.palox_stand_kg, palox_tara_kg()) AS befund,
    'Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '::text || 'Sonst ist der Stand vertippt.'::text AS rat
   FROM schimmel_messung s
     JOIN auftrag a ON a.id = s.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE s.gemessen AND a.abgebrochen_ts IS NULL AND s.palox_stand_kg IS NOT NULL AND s.palox_stand_kg < palox_tara_kg()
UNION ALL
 SELECT 'Palox geleert'::text AS art,
    p.auftrag_id,
    a.charge_nr,
    c.sorte,
    p.ts AS start_ts,
    format('Der Waagenstand fiel von %s auf %s kg — der Palox wurde zwischendurch geleert. '::text || 'Wie viel davor noch dazukam, weiss niemand; das Faule dieser Arbeit ist unbekannt.'::text, p.vorher, p.palox_stand_kg) AS befund,
    'Nichts zu korrigieren. Wird der Palox vor dem Leeren einmal abgelesen, bleibt die Menge bekannt.'::text AS rat
   FROM v_palox_stand p
     JOIN auftrag a ON a.id = p.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE p.differenz IS NULL AND a.abgebrochen_ts IS NULL
UNION ALL
 SELECT 'Wägung'::text AS art,
    w.auftrag_id,
    w.charge_nr,
    w.sorte,
    w.wiege_ts AS start_ts,
    ('Palette gewogen, aber '::text ||
        CASE
            WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'für die Gebindeart fehlt die Tara'::text
            WHEN w.lagertage <= 0 THEN 'das Wiegedatum liegt nicht nach dem Eingangsdatum'::text
            WHEN w.netto_damals_kg <= 0::numeric OR w.netto_jetzt_kg <= 0::numeric THEN 'das Netto ist null oder negativ'::text
            WHEN w.netto_jetzt_kg > (w.netto_damals_kg * 1.01) THEN format('sie wiegt jetzt %s kg mehr als beim Eingang, und im Lager wird keine Palette schwerer'::text, round(w.netto_jetzt_kg - w.netto_damals_kg))
            WHEN w.netto_jetzt_kg = w.netto_damals_kg THEN 'sie hat kein Gramm verloren — sehr wahrscheinlich wurde das Eingangsgewicht kopiert (etwa bei einer sortierten Palette, deren Zettelgewicht es nicht gibt)'::text
            ELSE 'sie ist nicht verwertbar'::text
        END) || ' — sie zählt nicht in die Verdunstungsrate'::text AS befund,
        CASE
            WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'Unter Stammdaten → Gebinde die Tara nachtragen.'::text
            WHEN w.netto_jetzt_kg > (w.netto_damals_kg * 1.01) THEN 'Gebindeart, Kistenzahl und beide Gewichte prüfen — meist stimmt die Tara nicht oder eine Zahl ist verdreht.'::text
            ELSE 'Eingangsdatum und Gewichte der Wägung prüfen.'::text
        END AS rat
   FROM v_verdunstung_messung w
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
  WHERE NOT w.verwendbar AND NOT w.sichtbar_schimmel AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
           FROM verdunstung_wiegung v
          WHERE v.id = w.id AND v.gemessen))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN format('%s Kisten nach Sollgewicht gezählt, aber für diese Sorte wurde noch '::text || 'nie eine fertige Palette gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl)
            ELSE format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber wurde beim '::text || 'Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt'::text, g.anzahl, g.kaliber_idx + 1)
        END AS befund,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN 'Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '::text || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'::text
            ELSE 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '::text || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.'::text
        END AS rat
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx <> '-2'::integer
UNION ALL
 SELECT 'Kaliber fehlt'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen'::text AS befund,
    'Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '::text || 'Stammdaten → Sortierschemata.'::text AS rat
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.kaliber_idx IS NULL AND a.kaliber_von_g IS NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM auftrag_gebinde g
          WHERE g.auftrag_id = a.id AND g.anzahl > 0))
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
        END, m.brutto_kg, GREATEST(round(n.roh), 0::numeric)) AS befund,
    'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '::text || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
     CROSS JOIN LATERAL ( SELECT m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS roh) n
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND n.roh IS NOT NULL AND m.kg::numeric <> GREATEST(round(n.roh), 0::numeric)
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
            WHEN m.gebindeart IS NULL THEN 'an der Wägung steht keine Gebindeart'::text
            WHEN g.art IS NULL THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN g.tara_kg_pro_kiste IS NULL THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN g.tara_kg_palette IS NULL THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END) AS befund,
    'Die gespeicherten Kilo bleiben, wie sie sind — geprüft werden können sie erst, '::text || 'wenn Gebindeart, Tara und Kistenzahl beisammen sind.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND (m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) IS NULL
UNION ALL
 SELECT 'Zetteldatum'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Zetteldatum %s gezählt, aber an dem Tag kam keine Palette dieser Charge'::text, count(*), to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.eingangsdatum IS NOT NULL AND ap.palette_id IS NULL AND ap.wiegung_id IS NULL AND a.abgebrochen_ts IS NULL AND NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.eingangsdatum = ap.eingangsdatum))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.eingangsdatum
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette '::text || 'dieser Charge dieses Gewicht — gerechnet wird mit der mittleren Tara der Charge'::text, count(*), ap.brutto_zettel_kg) AS befund,
    'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.brutto_zettel_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg
UNION ALL
 SELECT 'Lieferung ohne Eingang'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    min(l.datum)::timestamp with time zone AS start_ts,
    format('%s Lieferung(en) mit %s kg an Charge %s, aber im Wareneingang steht keine Palette dieser Charge'::text, count(*), round(sum(l.masse_kg)), l.charge_nr) AS befund,
    'Wareneingang der Charge nachtragen (Erntejournal) — oder die Lieferung gehört zu einer anderen Charge.'::text AS rat
   FROM v_lieferung_masse l
  WHERE l.buch = 'verkauf'::text AND l.charge_nr IS NOT NULL AND l.masse_kg > 0::numeric AND NOT (EXISTS ( SELECT 1
           FROM v_kohorte_anteil k
          WHERE k.charge_nr = l.charge_nr))
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
    format('%s Palette(n) mit Eingangsdatum %s gezählt — das liegt in der Zukunft, sehr wahrscheinlich ein falsches Jahr'::text, count(*), to_char(max(ap.eingangsdatum)::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung korrigieren (Jahr prüfen). Die Beobachtung bleibt gespeichert, bis sie berichtigt ist; solange rechnet die Auswertung sie nicht mit.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.eingangsdatum > heute() AND a.abgebrochen_ts IS NULL
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts
UNION ALL
 SELECT 'Palettengewicht'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    p.eingangsdatum::timestamp with time zone AS start_ts,
    format('Eine Palette mit %s kg brutto — für eine Palette Kürbisse ist das unmöglich'::text, round(p.brutto_kg)) AS befund,
    'Bruttogewicht im Wareneingang prüfen — sehr wahrscheinlich ein Zahlendreher.'::text AS rat
   FROM palette p
     JOIN charge c ON c.nr = p.charge_nr
  WHERE p.brutto_kg > 2000::numeric;


create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 70 $$;
