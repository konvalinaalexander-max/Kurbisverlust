-- 0128 — Jede Auffälligkeit ist ein Fall: ein fester Bezug, eine feste Nummer,
--         ein Vermerk, und ein Vorschlag, der sich mit einem Klick übernehmen lässt
--
-- WARUM
--
-- Der Betrieb, 25. Oktober, zu Messungen → Auffälligkeiten: „Bitte ordne die
-- chronologisch, die neuesten oben … wenn ich eine Auffälligkeit öffne, mit
-- besserem UI, damit ich besser nachvollziehen kann, was eigentlich Sache ist.
-- Und dann mir Lösungsvorschläge anbieten, die ich akzeptieren kann oder
-- nicht … dass du alle spezifische Fallnummer [vergibst], damit ich dir auch
-- im Chat sagen kann, wie ich mit diesen Fallnummern umgehen möchte …
-- Aktuell habe ich inzwischen 90 Auffälligkeiten und die reihen sich einfach
-- an, unchronologisch und unangenehm."
--
-- Bis hier hatte eine Auffälligkeit keinen Namen, an dem man sie festhalten
-- kann: v_plausibilitaet gab Art, Arbeit, Charge und einen Satz — welcher
-- Zettel, welche Wägung, welche Ablesung gemeint war, stand nur im Satz, und
-- der Satz enthält bei manchen Arten Modellwerte, die sich mit jedem Rechnen
-- ändern. Darum:
--
-- 1. bezug — jede der 25 Prüfungen sagt, woran sie hängt: „zettel:<Arbeit>:
--    <Gewicht>[:<Datum>]", „zetteldatum:<Arbeit>:<Datum>", „verdunstung_
--    wiegung:<id>", „schimmel_messung:<id>", „ausschuss_messung:<id>",
--    „auftrag_palette:<id>", „gebinde:<Arbeit>:<Kaliber>", „charge:<Nr>",
--    „lieferung:<id>", „palette:<id>", „auftrag:<Arbeit>[:<Station>]". Art und
--    Bezug zusammen sind die Kennung des Falls. erg_plausibilitaet wird darum
--    neu angelegt (sie hält select * fest) und ist leer, bis der nächste Lauf
--    sie füllt; ihr Schlüssel nimmt den Bezug mit.
-- 2. Ausschuss (Hand) hatte keinen Tag (start_ts leer) — jetzt der Beginn der
--    Arbeit, wie bei den anderen Arten einer Arbeit. Sonst sortiert die Liste
--    ihn nirgends ein.
-- 3. auffaelligkeit_nr / auffaelligkeit_nummern() — wie 0127 für Perigon: je
--    Fall eine Nummer, beim ersten Zeigen vergeben (die App nennt sie vom
--    ältesten zum neuesten, damit eine höhere Nummer eine jüngere Auffälligkeit
--    ist), nie geändert, nie neu vergeben. Vergeben tut nur der Betriebsleiter.
-- 4. auffaelligkeit_vermerk — der Stand je Fall: offen, in Abklärung, so
--    lassen (stimmt so, oder eine Regel folgt), korrigiert. Nur anhängen; der
--    Verlauf ist die Spur, mit Notiz, wer und wann, und dem Fall, wie er war.
-- 5. auffaelligkeit_korrigieren() — ein Vorschlag mit einem Klick: ändert
--    genau ein Feld an genau den genannten Zeilen, und nur, wenn dort noch
--    steht, was die App gesehen hat (sonst Fehler statt still Überschreiben).
--    Erlaubt sind die Felder, für die die App einen Vorschlag aus den Daten
--    rechnet: Zetteldatum und Zettelgewicht einer gezählten Palette, „mit
--    Palette" einer Ausschuss-Wägung. Nicht „nach dem Leeren" einer
--    Palox-Ablesung: was vor dem Leeren dazukam, bleibt unbekannt.
--    Was vorher dastand, steht im Vermerk. Neu gerechnet wird über den
--    gewohnten Weg (auswertung_anfordern, von der App gleich danach gerufen;
--    sonst nachts, denn die Änderung macht die Auswertung veraltet).
-- 6. Nebenbei gefunden: messung_ausschluss („benutzen" an/ab, 0116) machte
--    die Auswertung nicht veraltet — „ab heute Nacht" stimmte nur, wenn
--    zufällig sonst etwas geändert wurde. Jetzt hängt der Trigger dort wie an
--    den anderen Messtabellen.

-- =====================================================================
-- 1.–2. Die Prüfungen mit Bezug; erg_plausibilitaet neu
-- =====================================================================
drop view if exists v_plausibilitaet cascade;
drop view if exists v_plausibilitaet_0054_zusatz cascade;
drop view if exists v_plausibilitaet_0064_zusatz cascade;

create view v_plausibilitaet_0064_zusatz with (security_invoker = true) as
 SELECT 'Tara fehlt'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    min(p.eingangsdatum)::timestamp with time zone AS start_ts,
    format('%s von %s Paletten der Charge haben kein Nettogewicht (%s kg brutto): %s. %s'::text, count(*), r.n_paletten, round(sum(p.brutto_kg)),
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'die Gebindeart steht nicht auf der Palette'::text
            WHEN bool_or(g.art IS NULL) THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN bool_or(g.tara_kg_pro_kiste IS NULL) THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN bool_or(g.tara_kg_palette IS NULL) THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END,
        CASE
            WHEN r.n_paletten_mit_netto = 0 THEN 'Damit hat die Charge gar keinen Eingang — sie fehlt in der ganzen Bilanz.'::text
            ELSE format('Für sie rechnet der Eingang mit dem Mittel der übrigen: %s der %s kg '::text || 'Eingang sind hochgerechnet, nicht gewogen.'::text, round(r.eingang_netto_kg - r.eingang_netto_gemessen_kg), round(r.eingang_netto_kg))
        END) AS befund,
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'Gebindeart am Wareneingang nachtragen.'::text
            WHEN bool_or(g.art IS NULL) OR bool_or(g.tara_kg_pro_kiste IS NULL) OR bool_or(g.tara_kg_palette IS NULL) THEN 'Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. '::text || 'Die Zahlen rechnen sich danach von selbst neu.'::text
            ELSE 'Kistenzahl der Palette im Wareneingang nachtragen.'::text
        END AS rat,
    'charge:'::text || p.charge_nr AS bezug
   FROM palette p
     LEFT JOIN gebinde g ON g.art = p.gebindeart
     JOIN charge c ON c.nr = p.charge_nr
     JOIN v_charge_rueckgrat r ON r.charge_nr = p.charge_nr
  WHERE (p.brutto_kg - p.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) IS NULL
  GROUP BY p.charge_nr, c.sorte, r.n_paletten, r.n_paletten_mit_netto, r.eingang_netto_kg, r.eingang_netto_gemessen_kg
UNION ALL
 SELECT 'Überzählung'::text AS art,
    NULL::bigint AS auftrag_id,
    h.charge_nr,
    h.sorte,
    h.eingangsdatum_mittel::timestamp with time zone AS start_ts,
    format('Die Lieferungen dieser Charge (%s kg) brauchen nach der gerechneten Ausbeute (%s %% verkaufsfähig) %s kg Eingang — erfasst sind %s kg, also %s kg zu wenig. Geliefert wurde nicht mehr als eingelagert; es wurde mehr geliefert, als die Rechnung aus diesem Eingang erwartet.'::text, round(h.geliefert_kg), round(100::numeric * h.geliefert_kg / NULLIF(h.eingang_kg + h.ueberzaehlung_kg, 0::numeric)), round(h.eingang_kg + h.ueberzaehlung_kg), round(h.eingang_kg), round(h.ueberzaehlung_kg)) AS befund,
    'Drei Möglichkeiten: Im Erntejournal fehlt eine Palette dieser Charge; ein Lieferschein ist auf die falsche Chargennummer gebucht; oder diese Charge hat weniger Verlust als das Modell annimmt — dann ist „Im Lager" für sie zu klein gerechnet. Die ersten zwei lassen sich nachtragen.'::text AS rat,
    'charge:'::text || h.charge_nr AS bezug
   FROM v_hochrechnung_basis h
  WHERE h.ueberzaehlung_kg > 0::numeric
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — %s, nicht mit der Palette selbst.'::text, count(*), ap.brutto_zettel_kg, to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text),
        CASE
            WHEN bool_and(m.masse_quelle = 'gewogen'::text) THEN 'gerechnet wird mit der Wägung der Palette'::text
            WHEN bool_and(m.masse_quelle = 'zettel-kisten'::text) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            WHEN bool_and(m.masse_quelle = ANY (ARRAY['zettel-kisten'::text, 'zettel-kisten-charge'::text, 'gewogen'::text])) THEN 'gerechnet wird mit den gezählten Kisten und der Tara je Kiste der Charge (Zettel − Kisten × Tara je Kiste)'::text
            ELSE 'gerechnet wird mit der mittleren Tara ganzer Paletten der Charge — an der Zählung fehlt die Kistenzahl'::text
        END) AS befund,
    'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'::text AS rat,
    (((('zettel:'::text || ap.auftrag_id) || ':'::text) || ap.brutto_zettel_kg) || ':'::text) || ap.eingangsdatum AS bezug
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.id = ap.id
  WHERE ap.brutto_zettel_kg IS NOT NULL AND ap.eingangsdatum IS NOT NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg)) AND NOT (EXISTS ( SELECT 1
           FROM v_palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg AND p.eingangsdatum = ap.eingangsdatum AND p.netto_kg IS NOT NULL))
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
    'Standen die Kisten direkt auf der Waage? Dann in der Korrektur „mit Palette" abwählen — das Netto rechnet sich von selbst neu.'::text AS rat,
    'ausschuss_messung:'::text || m.id AS bezug
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.gemessen AND m.mit_palette AND m.brutto_kg IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND m.brutto_kg < (2::numeric * g.tara_kg_palette) AND a.abgebrochen_ts IS NULL
UNION ALL
 SELECT 'Verdunstung'::text AS art,
    m.auftrag_id,
    m.charge_nr,
    m.sorte,
    m.wiege_ts AS start_ts,
    format('%s %% je Tag: %s kg → %s kg in %s Tagen — so schnell verdunstet kein Kürbis (Grenze %s %% je Tag)'::text, round(m.rate_pro_tag * 100::numeric, 2), round(m.netto_damals_kg), round(m.netto_jetzt_kg), m.lagertage, round(verdunstung_rate_max() * 100::numeric, 2)) AS befund,
    'Zettelgewicht, Kisten und Gebinde dieser Wägung prüfen — oder es ist eine andere Palette. Bis zur Korrektur zählt sie nicht in die Rate.'::text AS rat,
    'verdunstung_wiegung:'::text || m.id AS bezug
   FROM v_verdunstung_messung m
  WHERE m.grund ~~ 'zu schnell%'::text;
comment on view v_plausibilitaet_0064_zusatz is
  'Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die Paletten fehlen im Eingang), eine Charge mit mehr Ausgang als Eingang, und ein Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag. 0128: dazu je Auffälligkeit ihr Bezug.';
grant select on v_plausibilitaet_0064_zusatz to authenticated;

create view v_plausibilitaet_0054_zusatz with (security_invoker = true) as
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber für ein Band mit diesen Grenzen hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, a.kaliber_von_g, a.kaliber_bis_g) AS befund,
    'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) oder die fertigen Paletten wiegen (drei reichen).'::text AS rat,
    (('gebinde:'::text || g.auftrag_id) || ':'::text) || g.kaliber_idx AS bezug
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx = '-2'::integer AND NOT (EXISTS ( SELECT 1
           FROM v_auftrag_wasch_gewogen wg
          WHERE wg.auftrag_id = g.auftrag_id AND wg.quelle = 'gewogen_strasse'::text))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    wp.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '::text || 'die Menge dieser Arbeit damit auch'::text, wp.n_paletten, wp.kisten,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN format('für das Band %s–%s g hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen'::text, a.kaliber_von_g, a.kaliber_bis_g)
            ELSE 'für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen'::text
        END) AS befund,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen.'::text
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — dann kennt die App das Kistengewicht des Bandes, rückwirkend auch für diese Arbeit; oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat,
    'waschpaletten:'::text || wp.auftrag_id AS bezug
   FROM v_auftrag_wasch_paletten wp
     JOIN auftrag a ON a.id = wp.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE wp.kg IS NULL AND wp.kisten > 0 AND NOT (EXISTS ( SELECT 1
           FROM v_auftrag_wasch_gewogen wg
          WHERE wg.auftrag_id = wp.auftrag_id AND wg.quelle = 'gewogen_strasse'::text))
UNION ALL
 SELECT 'Lieferung in der Zukunft'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    l.datum::timestamp with time zone AS start_ts,
    format('Lieferschein über %s kg mit Datum %s — das liegt nach heute (%s). '::text || 'Die Menge zählt erst ab diesem Tag in Ausgang und Bestand.'::text, round(l.masse_kg), to_char(l.datum::timestamp with time zone, 'DD.MM.YYYY'::text), to_char(heute()::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Stimmt das Datum? Ein vordatierter Lieferschein ist in Ordnung — die Zahl '::text || 'erscheint von selbst, sobald der Tag da ist. Ein Zahlendreher gehört korrigiert.'::text AS rat,
    'lieferung:'::text || l.id AS bezug
   FROM v_lieferung_masse l
  WHERE l.datum > heute() AND l.masse_kg IS NOT NULL AND l.masse_kg > 0::numeric
UNION ALL
 SELECT v_plausibilitaet_0064_zusatz.art,
    v_plausibilitaet_0064_zusatz.auftrag_id,
    v_plausibilitaet_0064_zusatz.charge_nr,
    v_plausibilitaet_0064_zusatz.sorte,
    v_plausibilitaet_0064_zusatz.start_ts,
    v_plausibilitaet_0064_zusatz.befund,
    v_plausibilitaet_0064_zusatz.rat,
    v_plausibilitaet_0064_zusatz.bezug
   FROM v_plausibilitaet_0064_zusatz;
comment on view v_plausibilitaet_0054_zusatz is
  'Zusatzprüfungen zu v_plausibilitaet, die seit 0054 dazugekommen sind — je Auffälligkeit Art, betroffene Arbeit, Befund und Rat. Wird von v_plausibilitaet mitgelesen; einzeln braucht sie niemand. 0128: dazu je Auffälligkeit ihr Bezug.';
grant select on v_plausibilitaet_0054_zusatz to authenticated;

create view v_plausibilitaet with (security_invoker = true) as
 SELECT 'Schimmel'::text AS art,
    b.auftrag_id,
    b.charge_nr,
    b.sorte,
    b.start_ts,
    format('%s kg Schimmel auf %s kg Ware — das wären %s %%'::text, round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100::numeric)) AS befund,
    'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text AS rat,
    (('auftrag:'::text || b.auftrag_id) || ':'::text) || COALESCE(b.station::text, '-'::text) AS bezug
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
    'Entweder die Palettenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'::text AS rat,
    'auftrag:'::text || f.auftrag_id AS bezug
   FROM v_fax_beobachtung f
  WHERE f.anteil IS NOT NULL AND NOT f.plausibel
UNION ALL
 SELECT 'Ausschuss'::text AS art,
    a.auftrag_id,
    a.charge_nr,
    a.sorte,
    ( SELECT x.start_ts
           FROM auftrag x
          WHERE x.id = a.auftrag_id) AS start_ts,
    format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse'::text, round(COALESCE(a.klein_kg, 0::numeric)), round(COALESCE(a.gross_kg, 0::numeric)), round(a.basis_kg)) AS befund,
    'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'::text AS rat,
    'auftrag:'::text || a.auftrag_id AS bezug
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
        END AS rat,
    'auftrag:'::text || a.id AS bezug
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
    'Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '::text || 'Sonst ist der Stand vertippt.'::text AS rat,
    'schimmel_messung:'::text || s.id AS bezug
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
    'Nichts zu korrigieren. Beim nächsten Mal in der Checkliste „Palox leeren" drücken: vor dem Leeren ablesen, danach die leere Box — dann bleibt die Menge bekannt.'::text AS rat,
    'schimmel_messung:'::text || p.id AS bezug
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
        END AS rat,
    'verdunstung_wiegung:'::text || w.id AS bezug
   FROM v_verdunstung_messung w
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
  WHERE NOT w.verwendbar AND NOT w.sichtbar_schimmel AND COALESCE(w.grund, ''::text) !~~ 'zu schnell%'::text AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
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
            ELSE format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, g.kaliber_idx + 1)
        END AS befund,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN 'Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '::text || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'::text
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — daraus kennt die App das Kistengewicht des Bandes, rückwirkend für alle Waschgänge dieser Sorte, auch für diesen. Oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat,
    (('gebinde:'::text || g.auftrag_id) || ':'::text) || g.kaliber_idx AS bezug
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx <> '-2'::integer
UNION ALL
 SELECT 'Waage'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
        CASE
            WHEN w.netto_kg <= 0::numeric THEN format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — leichter als ihre Kisten und die Palette (Tara %s kg)'::text, ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(ap.kisten::numeric * g.tara_kg_pro_kiste + g.tara_kg_palette, 1))
            ELSE format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — %s kg je Kiste'::text, ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(w.netto_kg / ap.kisten::numeric, 1))
        END AS befund,
    'Waage, Kistenzahl oder Gebinde prüfen und im Korrekturfenster der Arbeit berichtigen — bis dahin rechnet die Masse dieser Palette mit.'::text AS rat,
    'auftrag_palette:'::text || ap.id AS bezug
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = ap.gebindeart
     CROSS JOIN LATERAL ( SELECT ap.brutto_gewogen_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_kg) w
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL AND ap.brutto_gewogen_kg IS NOT NULL AND ap.kisten IS NOT NULL AND ap.kisten > 0 AND g.tara_kg_pro_kiste IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND (w.netto_kg <= 0::numeric OR (w.netto_kg / ap.kisten::numeric) < 4::numeric OR (w.netto_kg / ap.kisten::numeric) > 30::numeric)
UNION ALL
 SELECT 'Kaliber fehlt'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen'::text AS befund,
    'Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '::text || 'Stammdaten → Sortierschemata.'::text AS rat,
    'auftrag:'::text || a.id AS bezug
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
        END, m.brutto_kg, round(n.roh)) AS befund,
    'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '::text || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'::text AS rat,
    'ausschuss_messung:'::text || m.id AS bezug
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
     CROSS JOIN LATERAL ( SELECT m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste -
                CASE
                    WHEN m.mit_palette THEN g.tara_kg_palette
                    ELSE 0::numeric
                END AS roh) n
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND n.roh IS NOT NULL AND m.kg::numeric <> round(n.roh)
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
    'Die gespeicherten Kilo bleiben, wie sie sind — geprüft werden können sie erst, '::text || 'wenn Gebindeart, Tara und Kistenzahl beisammen sind.'::text AS rat,
    'ausschuss_messung:'::text || m.id AS bezug
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
    'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat,
    (('zetteldatum:'::text || ap.auftrag_id) || ':'::text) || ap.eingangsdatum AS bezug
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
    format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — %s'::text, count(*), ap.brutto_zettel_kg,
        CASE
            WHEN bool_and(m.masse_quelle = 'gewogen'::text) THEN 'gerechnet wird mit der Wägung der Palette'::text
            WHEN bool_and(m.masse_quelle = 'zettel-kisten'::text) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            WHEN bool_and(m.masse_quelle = ANY (ARRAY['zettel-kisten'::text, 'zettel-kisten-charge'::text, 'gewogen'::text])) THEN 'gerechnet wird mit den gezählten Kisten und der Tara je Kiste der Charge (Zettel − Kisten × Tara je Kiste)'::text
            ELSE 'gerechnet wird mit der mittleren Tara ganzer Paletten der Charge — an der Zählung fehlt die Kistenzahl'::text
        END) AS befund,
    'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal).'::text AS rat,
    (('zettel:'::text || ap.auftrag_id) || ':'::text) || ap.brutto_zettel_kg AS bezug
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.id = ap.id
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
    'Wareneingang der Charge nachtragen (Erntejournal) — oder die Lieferung gehört zu einer anderen Charge.'::text AS rat,
    'charge:'::text || l.charge_nr AS bezug
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
    v_plausibilitaet_0054_zusatz.rat,
    v_plausibilitaet_0054_zusatz.bezug
   FROM v_plausibilitaet_0054_zusatz
UNION ALL
 SELECT 'Zetteldatum Zukunft'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Eingangsdatum %s gezählt — das liegt in der Zukunft, sehr wahrscheinlich ein falsches Jahr'::text, count(*), to_char(max(ap.eingangsdatum)::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung korrigieren (Jahr prüfen). Die Beobachtung bleibt gespeichert, bis sie berichtigt ist; solange rechnet die Auswertung sie nicht mit.'::text AS rat,
    'auftrag:'::text || ap.auftrag_id AS bezug
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
    'Bruttogewicht im Wareneingang prüfen — sehr wahrscheinlich ein Zahlendreher.'::text AS rat,
    'palette:'::text || p.id AS bezug
   FROM palette p
     JOIN charge c ON c.nr = p.charge_nr
  WHERE p.brutto_kg > 2000::numeric;
comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette. 0066: „Ausschuss-Tara" rechnet nur nach, wo Kistenzahl und hinterlegte Tara da sind; fehlt eine, steht die Lücke als „Ausschuss ohne Tara" daneben. 0087: die Nachrechnung zieht die Palette nur ab, wenn sie mitgewogen wurde, und klemmt nichts auf null. 0114: eine zu schnell leichter gewordene Wägung steht nur als „Verdunstung" da, nicht noch einmal als „Wägung". 0128: bezug — woran die Auffälligkeit hängt (Zettel, Wägung, Ablesung, Charge …); Art und Bezug sind die Kennung des Falls, unter der Nummer und Vermerk stehen. Ausschuss (Hand) trägt den Beginn der Arbeit als Tag.';
grant select on v_plausibilitaet to authenticated;

-- verdichter: baut erg_plausibilitaet
do $$
begin
  execute 'drop materialized view if exists erg_plausibilitaet cascade';
  execute 'create materialized view erg_plausibilitaet as select * from v_plausibilitaet with no data';
  execute 'grant select on erg_plausibilitaet to authenticated';
  execute $c$comment on materialized view erg_plausibilitaet is 'v_plausibilitaet, gespeichert für die App Erneuert mit auswertung_schritt().'$c$;
end $$;

create or replace function auswertung_schluessel()
 RETURNS TABLE(sicht text, ausdruck text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  values
    ('erg_ausgang',            'id'),
    ('erg_bilanz',             'heute'),
    ('erg_charge',             'charge_nr'),
    ('erg_datenlage',          'charge_nr'),
    ('erg_datenqualitaet',     'paletten_gezaehlt'),
    ('erg_durchsatz',          'auftrag_id'),
    ('erg_fax',                'auftrag_id'),
    ('erg_fax_wartezeit',      'gruppe, sorte, klasse'),
    ('erg_gebinde',            'sorte, kaliber_idx'),
    ('erg_gewichte',           'charge_nr, stufe_g'),
    ('erg_kaliber',            'charge_nr, klasse, kaliber_idx, band_von, band_bis'),
    ('erg_koeff_ausschuss',    'sorte'),
    ('erg_koeff_fax',          'sorte'),
    ('erg_koeff_nebenkanal',   'sorte'),
    ('erg_koeff_ueberfuellung','n'),
    ('erg_koeff_verdunstung',  'sorte'),
    ('erg_kohorte',            'charge_nr, eingangsdatum'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_palox_erwartung',    'sorte, station'),
    ('erg_plausibilitaet',     'art, bezug, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte')
$function$;

-- =====================================================================
-- 3. Die Nummer je Auffälligkeit
-- =====================================================================
create table if not exists auffaelligkeit_nr (
  fall text primary key check (char_length(fall) between 3 and 300),
  nr   int  not null generated by default as identity,
  ts   timestamptz not null default now()
);
create unique index if not exists auffaelligkeit_nr_nr on auffaelligkeit_nr (nr);
comment on table auffaelligkeit_nr is
  'Je Auffälligkeit (Kennung der App: <Art>|<Bezug> aus v_plausibilitaet) eine Nummer, die bleibt (0128). Vergeben von auffaelligkeit_nummern() in der Folge, in der die App die Fälle nennt (vom ältesten zum neuesten); nie neu vergeben, nie geändert, nie gelöscht.';
alter table auffaelligkeit_nr enable row level security;
drop policy if exists auffaelligkeit_nr_lesen on auffaelligkeit_nr;
create policy auffaelligkeit_nr_lesen on auffaelligkeit_nr for select to authenticated using (true);
revoke all on auffaelligkeit_nr from anon, public;
grant select on auffaelligkeit_nr to authenticated;

create or replace function auffaelligkeit_nummern(p_faelle text[]) returns table (fall text, nr int)
language plpgsql security definer set search_path = public as $$
begin
  if p_faelle is null or cardinality(p_faelle) = 0 then return; end if;
  -- Neue Nummern nur vom Betriebsleiter; wer sonst fragt, bekommt die bekannten.
  if auth.uid() is null or ist_admin() then
    insert into auffaelligkeit_nr (fall)
    select x.f from (
      select u.f, min(u.i) as i from unnest(p_faelle) with ordinality as u(f, i)
       where u.f is not null and char_length(u.f) between 3 and 300
       group by u.f
    ) x
     where not exists (select 1 from auffaelligkeit_nr n where n.fall = x.f)
     order by x.i
    on conflict on constraint auffaelligkeit_nr_pkey do nothing;
  end if;
  return query select n.fall, n.nr from auffaelligkeit_nr n where n.fall = any (p_faelle) order by n.nr;
end $$;
comment on function auffaelligkeit_nummern(text[]) is
  'Gibt jeder genannten Auffälligkeit ihre Nummer (0128); was noch keine hat, bekommt die nächste — in der Folge, in der die Fälle genannt sind. Neue Nummern nur für den Betriebsleiter; die Nummer eines Falls ändert sich nie.';
revoke all on function auffaelligkeit_nummern(text[]) from public;
grant execute on function auffaelligkeit_nummern(text[]) to authenticated;

-- =====================================================================
-- 4. Der Stand je Auffälligkeit
-- =====================================================================
create table if not exists auffaelligkeit_vermerk (
  id            bigserial primary key,
  fall          text not null check (char_length(fall) between 3 and 300),
  stand         text not null check (stand in ('offen', 'in_abklaerung', 'so_lassen', 'korrigiert')),
  notiz         text check (notiz is null or char_length(notiz) <= 2000),
  -- was der Fall war (Art, Charge, Satz) — und bei „korrigiert", was vorher und nachher dastand
  schnappschuss jsonb,
  wer           uuid references profil(id) on delete set null default auth.uid(),
  ts            timestamptz not null default now()
);
create index if not exists auffaelligkeit_vermerk_fall on auffaelligkeit_vermerk (fall, ts desc, id desc);
comment on table auffaelligkeit_vermerk is
  'Je Auffälligkeit, wie es steht (0128): offen, in_abklaerung (in der Halle nachgefragt), so_lassen (stimmt so, oder eine Regel folgt), korrigiert (ein Vorschlag übernommen — vorher und nachher im Schnappschuss). Nur anhängen: kein Ändern, kein Löschen; der Verlauf ist die Spur.';
alter table auffaelligkeit_vermerk enable row level security;
drop policy if exists auffaelligkeit_vermerk_lesen on auffaelligkeit_vermerk;
drop policy if exists auffaelligkeit_vermerk_anhaengen on auffaelligkeit_vermerk;
create policy auffaelligkeit_vermerk_lesen on auffaelligkeit_vermerk for select to authenticated using (true);
create policy auffaelligkeit_vermerk_anhaengen on auffaelligkeit_vermerk for insert to authenticated
  with check (ist_admin() and wer = auth.uid() and stand <> 'korrigiert');
revoke all on auffaelligkeit_vermerk from anon, public;
grant select, insert on auffaelligkeit_vermerk to authenticated;
grant usage on sequence auffaelligkeit_vermerk_id_seq to authenticated;

-- =====================================================================
-- 5. Ein Vorschlag mit einem Klick
-- =====================================================================
create or replace function auffaelligkeit_korrigieren(p_fall text, p_was text, p_ids bigint[], p_vorher text, p_nachher text,
                                                      p_notiz text default null, p_schnappschuss jsonb default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_n int; v_da int; v_id bigint;
begin
  if not coalesce(ist_admin(), false) then
    raise exception 'Vorschläge übernimmt nur der Betriebsleiter.' using errcode = '42501';
  end if;
  if p_fall is null or char_length(p_fall) not between 3 and 300 then
    raise exception 'Welche Auffälligkeit? (die Kennung fehlt)';
  end if;
  if p_ids is null or cardinality(p_ids) = 0 or p_nachher is null then
    raise exception 'Was soll geändert werden? (keine Zeile oder kein neuer Wert)';
  end if;
  v_n := (select count(distinct x) from unnest(p_ids) x);
  -- Nur, wo noch steht, was die App gesehen hat: sonst hat jemand anders inzwischen geändert.
  case p_was
    when 'zetteldatum' then
      select count(*) into v_da from auftrag_palette where id = any (p_ids) and eingangsdatum is not distinct from p_vorher::date;
      if v_da <> v_n then raise exception 'Das Zetteldatum steht nicht mehr so da (% von % Zeilen) — die Auffälligkeit neu laden.', v_da, v_n using errcode = '40001'; end if;
      update auftrag_palette set eingangsdatum = p_nachher::date where id = any (p_ids);
    when 'zettelgewicht' then
      select count(*) into v_da from auftrag_palette where id = any (p_ids) and brutto_zettel_kg is not distinct from p_vorher::numeric;
      if v_da <> v_n then raise exception 'Das Zettelgewicht steht nicht mehr so da (% von % Zeilen) — die Auffälligkeit neu laden.', v_da, v_n using errcode = '40001'; end if;
      if p_nachher::numeric <= 0 or p_nachher::numeric > 2000 then raise exception 'Ein Zettelgewicht von % kg gibt es nicht.', p_nachher; end if;
      update auftrag_palette set brutto_zettel_kg = p_nachher::numeric where id = any (p_ids);
    when 'mit_palette' then
      select count(*) into v_da from ausschuss_messung where id = any (p_ids) and mit_palette is not distinct from p_vorher::boolean;
      if v_da <> v_n then raise exception '„mit Palette" steht nicht mehr so da — die Auffälligkeit neu laden.' using errcode = '40001'; end if;
      update ausschuss_messung set mit_palette = p_nachher::boolean where id = any (p_ids);
    -- Bewusst nicht: „nach dem Leeren" an einer Palox-Ablesung. Was vor dem
    -- Leeren noch dazukam, weiss niemand; mit einem Klick würde aus einem
    -- unbekannten Faulen ein bekanntes, zu kleines.
    else
      raise exception 'Das ändert die App nicht mit einem Klick: % — im Korrekturfenster der Arbeit von Hand.', p_was;
  end case;
  insert into auffaelligkeit_vermerk (fall, stand, notiz, schnappschuss)
  values (p_fall, 'korrigiert', nullif(trim(p_notiz), ''),
          coalesce(p_schnappschuss, '{}'::jsonb) || jsonb_build_object('was', p_was, 'ids', to_jsonb(p_ids), 'vorher', p_vorher, 'nachher', p_nachher))
  returning id into v_id;
  return v_id;
end $$;
comment on function auffaelligkeit_korrigieren(text, text, bigint[], text, text, text, jsonb) is
  'Übernimmt einen Vorschlag zu einer Auffälligkeit (0128): ändert ein erlaubtes Feld (zetteldatum, zettelgewicht an auftrag_palette; mit_palette an ausschuss_messung) an den genannten Zeilen — nur, wo noch der Wert steht, den die App gesehen hat — und hängt einen Vermerk „korrigiert" mit vorher und nachher an. Nur der Betriebsleiter. Neu gerechnet wird über auswertung_anfordern().';
revoke all on function auffaelligkeit_korrigieren(text, text, bigint[], text, text, text, jsonb) from public, anon;
grant execute on function auffaelligkeit_korrigieren(text, text, bigint[], text, text, text, jsonb) to authenticated;

-- =====================================================================
-- 6. „benutzen" an/ab macht die Auswertung veraltet
-- =====================================================================
drop trigger if exists messung_ausschluss_veraltet on messung_ausschluss;
create trigger messung_ausschluss_veraltet after insert or update or delete on messung_ausschluss
  for each statement execute function auswertung_veraltet();

-- =====================================================================
-- Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 128 $$;
