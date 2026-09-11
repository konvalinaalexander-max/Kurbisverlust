-- sicht: v_saisonbilanz
-- Eingang + Überzählung = ausgeliefert + Verlust bis heute + anderer Kanal am Ausgelagerten + noch im Haus (0062). Alles bis heute(); nichts davon ist Prognose. bilanz_rest_kg ist der Rest dieser Gleichung — Erwartungswert null; die Überzählung (Lieferungen, hinter denen kein Eingang steht) steht als eigene Spalte. fax_durchsatz_kg ist die am Fax abgepackte Masse, nicht das Faule dabei (fax_heute_kg).

 WITH charge AS (
         SELECT sum(erg_charge.eingang_kg) AS eingang_kg,
            sum(erg_charge.ausgelagert_kg) AS ausgelagert_kg,
            sum(erg_charge.geliefert_kg) AS geliefert_kg,
            sum(erg_charge.lager_kg) AS lager_kg,
            sum(erg_charge.wartet_kg) AS wartet_kg,
            sum(erg_charge.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(erg_charge.verkaufsfaehig_lager_kg) AS verkaufsfaehig_heute_kg,
            sum(erg_charge.im_haus_heute_kg) AS im_haus_heute_kg,
            sum(erg_charge.kanal_im_haus_kg) AS kanal_im_haus_kg,
            sum(erg_charge.verlust_heute_kg) AS verlust_heute_kg,
            sum(erg_charge.verdunstung_heute_kg) AS verdunstung_heute_kg,
            sum(erg_charge.schimmel_heute_kg) AS schimmel_heute_kg,
            sum(erg_charge.sockel_heute_kg) AS sockel_heute_kg,
            sum(erg_charge.fax_heute_kg) AS fax_heute_kg,
            sum(erg_charge.fax_erwartet_kg) AS fax_erwartet_kg,
            sum(erg_charge.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            bool_and(erg_charge.verlust_bekannt) AS bekannt,
            count(*)::integer AS n_chargen,
            max(erg_charge.heute) AS heute
           FROM erg_charge
        ), bereich AS (
         SELECT sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = ANY (ARRAY['verlust'::text, 'feld'::text])) AS verlust_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = ANY (ARRAY['verlust'::text, 'feld'::text])) AS verlust_oben_kg,
            sum(erg_verlust.kg) FILTER (WHERE erg_verlust.buch = ANY (ARRAY['verlust'::text, 'feld'::text])) AS verlust_kg,
            sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = 'marge'::text) AS kanal_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = 'marge'::text) AS kanal_oben_kg
           FROM erg_verlust
          WHERE erg_verlust.gruppe = 'gesamt'::text
        ), vorlauf AS (
         SELECT COALESCE(sum(charge_vorlauf.ausgang_vor_app_kg), 0::numeric) AS kg
           FROM charge_vorlauf
        ), ausgang AS (
         SELECT COALESCE(sum(v_lieferung_masse.masse_kg), 0::numeric) AS kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'verkauf'::text), 0::numeric) AS verkauf_kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'marge'::text), 0::numeric) AS marge_kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'verlust'::text), 0::numeric) AS entsorgt_kg,
            COALESCE(sum(v_lieferung_masse.masse_fehler_kg), 0::double precision) AS fehler_kg,
            count(*)::integer AS n_lieferungen,
            max(v_lieferung_masse.datum) AS letzte_lieferung
           FROM v_lieferung_masse
          WHERE v_lieferung_masse.datum <= heute()
        ), fax AS (
         SELECT COALESCE(sum(v_fax_beobachtung.masse_kg), 0::numeric) AS kg,
            count(*)::integer AS n
           FROM v_fax_beobachtung
          WHERE v_fax_beobachtung.status = 'abgeschlossen'::auftrag_status AND v_fax_beobachtung.masse_kg IS NOT NULL
        )
 SELECT c.heute,
    zahl(c.eingang_kg)::numeric(14,2) AS eingang_kg,
    c.n_chargen,
    zahl(a.kg + vl.kg)::numeric(14,2) AS ausgang_kg,
    zahl(a.verkauf_kg)::numeric(14,2) AS verkauf_kg,
    zahl(a.marge_kg)::numeric(14,2) AS marge_kg,
    zahl(a.entsorgt_kg)::numeric(14,2) AS entsorgt_kg,
    zahl(a.fehler_kg)::numeric(14,2) AS ausgang_fehler_kg,
    a.n_lieferungen,
    a.letzte_lieferung,
    zahl(vl.kg)::numeric(14,2) AS vorlauf_kg,
    zahl(c.geliefert_kg)::numeric(14,2) AS geliefert_kg,
    zahl(c.ausgelagert_kg)::numeric(14,2) AS ausgelagert_kg,
    zahl(c.verlust_heute_kg)::numeric(14,2) AS verlust_heute_kg,
    zahl(b.verlust_unten_kg)::numeric(14,2) AS verlust_unten_kg,
    zahl(b.verlust_oben_kg)::numeric(14,2) AS verlust_oben_kg,
    zahl(c.verdunstung_heute_kg)::numeric(14,2) AS verdunstung_heute_kg,
    zahl(c.schimmel_heute_kg)::numeric(14,2) AS schimmel_heute_kg,
    zahl(c.sockel_heute_kg)::numeric(14,2) AS sockel_heute_kg,
    zahl(c.fax_heute_kg)::numeric(14,2) AS fax_heute_kg,
    zahl(c.fax_erwartet_kg)::numeric(14,2) AS fax_erwartet_kg,
    zahl(c.kanal_ausgelagert_kg)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(b.kanal_unten_kg)::numeric(14,2) AS kanal_unten_kg,
    zahl(b.kanal_oben_kg)::numeric(14,2) AS kanal_oben_kg,
    zahl(c.im_haus_heute_kg)::numeric(14,2) AS im_haus_heute_kg,
    zahl(c.verkaufsfaehig_heute_kg)::numeric(14,2) AS verkaufsfaehig_heute_kg,
    zahl(c.kanal_im_haus_kg)::numeric(14,2) AS kanal_im_haus_kg,
    zahl(c.lager_kg)::numeric(14,2) AS lager_kg,
    zahl(c.wartet_kg)::numeric(14,2) AS gegenprobe_wartet_kg,
    zahl(c.ueberzaehlung_kg)::numeric(14,2) AS ueberzaehlung_kg,
    zahl(f.kg)::numeric(14,2) AS fax_durchsatz_kg,
    f.n AS n_fax_arbeiten,
    COALESCE(c.bekannt, false) AS verlust_bekannt,
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.kanal_ausgelagert_kg - c.im_haus_heute_kg)::numeric(14,2) AS bilanz_rest_kg,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.kanal_ausgelagert_kg - c.im_haus_heute_kg) / c.eingang_kg
            ELSE NULL::numeric
        END, 4, '100000'::numeric)::numeric(10,4) AS bilanz_rest_anteil,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (a.kg + vl.kg) / c.eingang_kg
            ELSE NULL::numeric
        END, 4, '100000'::numeric)::numeric(10,4) AS ausgang_deckung,
        CASE
            WHEN COALESCE(c.eingang_kg, 0::numeric) <= 0::numeric THEN 'Es ist kein Wareneingang erfasst. Ohne das Erntejournal gibt es '::text || 'nichts, worauf sich Verlust und Bestand beziehen könnten.'::text
            WHEN COALESCE(c.ueberzaehlung_kg, 0::numeric) > (0.05 * c.eingang_kg) THEN format((('Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — '::text || 'bei einigen Chargen rund %s kg zu viel. Fast immer fehlt der '::text) || 'Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine '::text) || 'Lieferung ist der falschen Charge zugeordnet.'::text, round(c.ueberzaehlung_kg))
            WHEN a.n_lieferungen = 0 AND vl.kg = 0::numeric THEN ('Kein Warenausgang erfasst — dann liegt rechnerisch noch alles im Haus, '::text || 'und der Verlust bis heute gilt für die ganze Eingangsmasse. Sobald die '::text) || 'Lieferscheine eingelesen sind, teilt sich die Ware in ausgeliefert und liegend.'::text
            WHEN NOT COALESCE(c.bekannt, false) THEN 'Ein Verluststrom ist noch nicht gemessen — die Ursachen sind erst '::text || 'vollständig, wenn jeder Koeffizient mindestens eine Messung hat.'::text
            ELSE format((('Bis heute (%s): %s t Eingang = %s t ausgeliefert + %s t Verlust '::text || '(Verdunstung %s t, Faules %s t, Fax %s t) + %s t anderer Kanal '::text) || '+ %s t noch im Haus (davon %s t verkaufsfähig). Die Prognose bis zum '::text) || 'Saisonende steht in der Grafik, nicht in diesen Zahlen.%s'::text, to_char(c.heute::timestamp with time zone, 'DD.MM.YYYY'::text), round(c.eingang_kg / 1000.0, 1), round(c.geliefert_kg / 1000.0, 1), round(c.verlust_heute_kg / 1000.0, 1), round(c.verdunstung_heute_kg / 1000.0, 1), round((c.schimmel_heute_kg + c.sockel_heute_kg) / 1000.0, 1), round(c.fax_heute_kg / 1000.0, 1), round(c.kanal_ausgelagert_kg / 1000.0, 1), round(c.im_haus_heute_kg / 1000.0, 1), round(c.verkaufsfaehig_heute_kg / 1000.0, 1), concat_ws(' '::text, '',
            CASE
                WHEN a.marge_kg > 0::numeric THEN format('An die Tiere und in den Nebenkanal geliefert: %s kg, gerechnet: %s kg.'::text, round(a.marge_kg), round(c.kanal_ausgelagert_kg))
                ELSE NULL::text
            END,
            CASE
                WHEN a.entsorgt_kg > 0::numeric THEN format('Entsorgt: %s kg, gerechneter Schimmel: %s kg.'::text, round(a.entsorgt_kg), round(c.schimmel_heute_kg))
                ELSE NULL::text
            END,
            CASE
                WHEN COALESCE(c.ueberzaehlung_kg, 0::numeric) > 0::numeric THEN format('%s kg Überzählung.'::text, round(c.ueberzaehlung_kg))
                ELSE NULL::text
            END))
        END AS befund
   FROM charge c
     CROSS JOIN bereich b
     CROSS JOIN ausgang a
     CROSS JOIN vorlauf vl
     CROSS JOIN fax f;
