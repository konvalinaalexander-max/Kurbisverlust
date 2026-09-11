-- sicht: v_datenqualitaet
-- Zähler zur Vollständigkeit der Erfassung. Seit 0061 zählen beim Waschen die gezählten Paletten (Kisten mit Sortierdatum) mit; die Lagerkontrolle zählt als Verdunstungsmessung, ohne Faul-Angabe.

 WITH arbeiten AS (
         SELECT a.id,
            a.weg,
            a.station,
            a.charge_nr,
            a.start_ts,
            a.ende_ts,
            a.geplante_paletten,
            a.status,
            a.eroeffnet_von,
            a.durchsatz_kg,
            a.bemerkung,
            a.abgebrochen_ts,
            a.abbruch_grund,
            a.kaeufer,
            a.sortierschema_id,
            a.kaliber_idx,
            a.ist_fax,
            a.kaliber_von_g,
            a.kaliber_bis_g,
            a.kistensystem,
            a.soll_kg_pro_kiste,
            a.stueck_je_kiste,
            a.paletten_gesamt,
            a.tage_seit_waschen
           FROM auftrag a
          WHERE a.abgebrochen_ts IS NULL
        ), fertig AS (
         SELECT arbeiten.id,
            arbeiten.weg,
            arbeiten.station,
            arbeiten.charge_nr,
            arbeiten.start_ts,
            arbeiten.ende_ts,
            arbeiten.geplante_paletten,
            arbeiten.status,
            arbeiten.eroeffnet_von,
            arbeiten.durchsatz_kg,
            arbeiten.bemerkung,
            arbeiten.abgebrochen_ts,
            arbeiten.abbruch_grund,
            arbeiten.kaeufer,
            arbeiten.sortierschema_id,
            arbeiten.kaliber_idx,
            arbeiten.ist_fax,
            arbeiten.kaliber_von_g,
            arbeiten.kaliber_bis_g,
            arbeiten.kistensystem,
            arbeiten.soll_kg_pro_kiste,
            arbeiten.stueck_je_kiste,
            arbeiten.paletten_gesamt,
            arbeiten.tage_seit_waschen
           FROM arbeiten
          WHERE arbeiten.status = 'abgeschlossen'::auftrag_status
        )
 SELECT (( SELECT count(*) AS count
           FROM auftrag_palette ap
             JOIN arbeiten a ON a.id = ap.auftrag_id))::integer AS paletten_gezaehlt,
    (( SELECT count(*) AS count
           FROM auftrag_palette ap
             JOIN arbeiten a ON a.id = ap.auftrag_id
          WHERE ap.eingangsdatum IS NOT NULL))::integer AS paletten_mit_datum,
    (( SELECT count(*) AS count
           FROM fertig
          WHERE NOT fertig.ist_fax))::integer AS arbeiten_fertig,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE NOT f.ist_fax AND (EXISTS ( SELECT 1
                   FROM schimmel_messung s
                  WHERE s.auftrag_id = f.id AND s.palox_stand_kg IS NOT NULL))))::integer AS arbeiten_mit_ablesung,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE NOT f.ist_fax AND (( SELECT count(*) AS count
                   FROM schimmel_messung s
                  WHERE s.auftrag_id = f.id AND s.palox_stand_kg IS NOT NULL)) >= 2))::integer AS arbeiten_mit_zwei_ablesungen,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE NOT f.ist_fax AND (EXISTS ( SELECT 1
                   FROM auftrag_angabe g
                  WHERE g.auftrag_id = f.id AND g.schluessel = 'eine_charge'::text))))::integer AS arbeiten_mit_antwort,
    (( SELECT count(*) AS count
           FROM ausschuss_messung m
             JOIN arbeiten a ON a.id = m.auftrag_id
          WHERE m.gemessen))::integer AS ausschuss_messungen,
    (( SELECT count(*) AS count
           FROM ausschuss_messung m
             JOIN arbeiten a ON a.id = m.auftrag_id
          WHERE m.gemessen AND m.brutto_kg IS NOT NULL))::integer AS ausschuss_gewogen,
    (( SELECT count(*) AS count
           FROM verdunstung_wiegung w
          WHERE w.auftrag_id IS NULL AND w.gemessen))::integer AS lagerkontrollen,
    (( SELECT count(*) AS count
           FROM sortier_lauf))::integer AS sortierlaeufe,
    (( SELECT count(*) AS count
           FROM sortier_lauf
          WHERE sortier_lauf.auftrag_id IS NOT NULL))::integer AS sortierlaeufe_zugeordnet,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE f.station = 'sortieren'::station))::integer AS sortier_arbeiten,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE f.station = 'sortieren'::station AND (EXISTS ( SELECT 1
                   FROM auftrag_gebinde g
                  WHERE g.auftrag_id = f.id AND g.anzahl > 0))))::integer AS sortier_arbeiten_mit_kisten,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE f.station = 'waschen'::station AND NOT f.ist_fax))::integer AS wasch_arbeiten,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE f.station = 'waschen'::station AND NOT f.ist_fax AND (f.kaliber_idx IS NOT NULL OR f.kaliber_von_g IS NOT NULL) AND ((EXISTS ( SELECT 1
                   FROM auftrag_gebinde g
                  WHERE g.auftrag_id = f.id AND g.anzahl > 0)) OR (EXISTS ( SELECT 1
                   FROM auftrag_palette p
                  WHERE p.auftrag_id = f.id AND p.kisten > 0)))))::integer AS wasch_arbeiten_mit_kisten,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE f.ist_fax))::integer AS fax_arbeiten,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE f.ist_fax AND (f.paletten_gesamt > 0 OR (EXISTS ( SELECT 1
                   FROM auftrag_gebinde g
                  WHERE g.auftrag_id = f.id AND g.anzahl > 0)))))::integer AS fax_arbeiten_mit_kisten,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE f.ist_fax AND (EXISTS ( SELECT 1
                   FROM schimmel_messung s
                  WHERE s.auftrag_id = f.id AND s.gemessen))))::integer AS fax_arbeiten_mit_faulem,
    (( SELECT count(*) AS count
           FROM auftrag_palette ap
             JOIN arbeiten a ON a.id = ap.auftrag_id
          WHERE a.station = 'waschen_sortieren'::station))::integer AS ws_paletten_gezaehlt,
    (( SELECT count(*) AS count
           FROM auftrag_palette ap
             JOIN arbeiten a ON a.id = ap.auftrag_id
          WHERE a.station = 'waschen_sortieren'::station AND ap.brutto_zettel_kg IS NOT NULL))::integer AS ws_paletten_mit_zettelgewicht,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE f.ist_fax OR (f.station = ANY (ARRAY['waschen'::station, 'waschen_sortieren'::station]))))::integer AS arbeiten_nach_waschen,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE (f.ist_fax OR (f.station = ANY (ARRAY['waschen'::station, 'waschen_sortieren'::station]))) AND f.kistensystem IS NOT NULL))::integer AS arbeiten_mit_kistensystem,
    ((( SELECT COALESCE(sum(g.anzahl), 0::bigint) AS "coalesce"
           FROM auftrag_gebinde g
             JOIN arbeiten a ON a.id = g.auftrag_id
          WHERE a.station = 'waschen'::station AND NOT a.ist_fax)) + (( SELECT COALESCE(sum(p.kisten), 0::bigint) AS "coalesce"
           FROM auftrag_palette p
             JOIN arbeiten a ON a.id = p.auftrag_id
          WHERE a.station = 'waschen'::station AND NOT a.ist_fax)))::integer AS wasch_kisten_gezaehlt,
    ((( SELECT COALESCE(sum(g.anzahl), 0::bigint) AS "coalesce"
           FROM auftrag_gebinde g
             JOIN arbeiten a ON a.id = g.auftrag_id
          WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND (g.sortierdatum IS NOT NULL OR g.datum_fehlt))) + (( SELECT COALESCE(sum(p.kisten), 0::bigint) AS "coalesce"
           FROM auftrag_palette p
             JOIN arbeiten a ON a.id = p.auftrag_id
          WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND p.sortierdatum IS NOT NULL)))::integer AS wasch_kisten_mit_sortierdatum,
    (( SELECT count(*) AS count
           FROM fertig f
          WHERE NOT f.ist_fax AND (EXISTS ( SELECT 1
                   FROM v_palox_stand p
                  WHERE p.auftrag_id = f.id AND p.differenz IS NULL))))::integer AS arbeiten_mit_palox_unbekannt;
