-- sicht: v_hochrechnung_basis
-- Je Charge, alles bis heute: Eingang und geliefert (gemessen), ausgelagert (Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus ausgelagert, in Eingangskilo), verlust_heute_kg (Verdunstung + Schimmel + Sockel + Fax am Abgepackten), im_haus_heute_kg (Eingangsmasse, die noch liegt, nach Verdunstung und Verderb). Keine Prognose. 0064: Jede Stromsumme ist NULL, solange ihr Koeffizient keine Messung hat — leer ist nicht null; die Kennzeichen daneben sagen, welche. Ohne Messung ist im_haus_heute_kg die Eingangsmasse, die noch liegt, und damit eine obere Schranke. Fehlt zu einer Charge jede Kaskadenzeile, liegt noch alles; fehlt nur die Portion „lager", liegt nichts mehr — bisher hiess beides „alles".

 WITH je_charge AS (
         SELECT mv_kaskade.charge_nr,
            sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text) AS ausgelagert_kg,
            sum(mv_kaskade.m0 * mv_kaskade.alter_tage) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric) AS alter_ausgelagert,
            sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS lager_kg,
            sum(mv_kaskade.m0 * mv_kaskade.alter_tage) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS alter_lager,
            sum(mv_kaskade.verkaufsfaehig_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS verkaufsfaehig_lager_kg,
            sum(mv_kaskade.geliefert_kg) AS geliefert_kg,
            sum(mv_kaskade.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(mv_kaskade.n_lieferungen)::integer AS n_lieferungen,
            min(mv_kaskade.kohorte) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric) AS rest_von,
            max(mv_kaskade.kohorte) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric) AS rest_bis,
            count(*) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric)::integer AS n_rest_kohorten,
            sum(mv_kaskade.m0 * (mv_kaskade.kohorte - '2000-01-01'::date)::numeric) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS rest_tage_seit_epoche,
                CASE
                    WHEN bool_and(mv_kaskade.r_bekannt) THEN COALESCE(sum(mv_kaskade.verdunstung_kg), 0::numeric)
                    ELSE NULL::numeric
                END AS verdunstung_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.f_bekannt) THEN COALESCE(sum(mv_kaskade.schimmel_kg), 0::numeric)
                    ELSE NULL::numeric
                END AS schimmel_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a0_bekannt) THEN COALESCE(sum(mv_kaskade.sockel_kg), 0::numeric)
                    ELSE NULL::numeric
                END AS sockel_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) THEN COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS kanal_ausgelagert_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_fax_bekannt) THEN COALESCE(sum(mv_kaskade.fax_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS fax_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_fax_bekannt) THEN COALESCE(sum(mv_kaskade.fax_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS fax_erwartet_kg,
            sum(mv_kaskade.m2) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS im_haus_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) THEN COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS kanal_im_haus_kg,
            bool_and(mv_kaskade.r_bekannt AND mv_kaskade.f_bekannt AND mv_kaskade.a0_bekannt AND mv_kaskade.a_fax_bekannt AND mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) AS verlust_bekannt,
            bool_and(mv_kaskade.r_bekannt) AS verdunstung_bekannt,
            bool_and(mv_kaskade.f_bekannt) AS schimmel_bekannt,
            bool_and(mv_kaskade.a0_bekannt) AS sockel_nachgewiesen,
            bool_and(mv_kaskade.a_fax_bekannt) AS fax_bekannt,
            bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) AS kanal_bekannt,
            max(mv_kaskade.a0_var) AS a0_var,
            count(*) > 0 AS gerechnet,
            count(*) FILTER (WHERE mv_kaskade.portion = 'lager'::text) > 0 AS hat_lager
           FROM mv_kaskade
          GROUP BY mv_kaskade.charge_nr
        )
 SELECT b.charge_nr,
    b.schlag,
    b.sorte,
    b.eingang_kg,
    b.n_paletten,
    b.eingangsdatum_mittel,
    zahl(COALESCE(k.ausgelagert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgelagert_kg,
    zahl(k.alter_ausgelagert, 1, '100000'::numeric)::numeric(8,1) AS alter_ausgelagert,
    zahl(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.lager_kg, 0::numeric)
        END, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(COALESCE(k.alter_lager, (b.stichtag - b.eingangsdatum_mittel)::numeric), 1, '100000'::numeric)::numeric(8,1) AS alter_lager,
    zahl((heute() - x.rest_datum)::double precision, 1, '100000'::numeric)::numeric(8,1) AS alter_lager_heute,
    b.weg2_anteil,
    b.stichtag,
    b.n_paletten_mit_netto,
    zahl(COALESCE(k.ueberzaehlung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ueberzaehlung_kg,
    b.sortiert_kg,
    b.gewaschen_kg,
    b.wartet_kg,
    b.anteil_gewaschen,
    b.alter_band,
    b.am_band_kg,
    x.rest_datum AS eingangsdatum_rest,
    COALESCE(k.n_lieferungen, 0) > 0 AS rest_alter_aus_zaehlung,
    b.eingang_von,
    b.eingang_bis,
    b.n_eingangstage,
    COALESCE(k.rest_von, b.eingang_von) AS rest_von,
    COALESCE(k.rest_bis, b.eingang_bis) AS rest_bis,
    round(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.lager_kg, 0::numeric)
        END / NULLIF(b.eingang_kg / NULLIF(b.n_paletten, 0)::numeric, 0::numeric))::integer AS n_rest_paletten,
    COALESCE(k.n_rest_kohorten, b.n_eingangstage) AS n_rest_kohorten,
    heute() - COALESCE(k.rest_bis, b.eingang_bis) AS alter_lager_von,
    heute() - COALESCE(k.rest_von, b.eingang_von) AS alter_lager_bis,
    zahl(COALESCE(k.geliefert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS geliefert_kg,
    zahl(k.verkaufsfaehig_lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_lager_kg,
    COALESCE(k.n_lieferungen, 0) AS n_lieferungen,
    zahl(k.verdunstung_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_heute_kg,
    zahl(k.schimmel_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_heute_kg,
    zahl(k.sockel_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS sockel_heute_kg,
    zahl(k.fax_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_heute_kg,
    zahl(k.verdunstung_heute_kg + k.schimmel_heute_kg + k.sockel_heute_kg + k.fax_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_heute_kg,
    zahl(k.kanal_ausgelagert_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(k.fax_erwartet_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_erwartet_kg,
    zahl(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.im_haus_heute_kg, 0::numeric)
        END, 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_heute_kg,
    zahl(k.kanal_im_haus_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_im_haus_kg,
    COALESCE(k.verlust_bekannt, false) AS verlust_bekannt,
    COALESCE(k.verdunstung_bekannt, false) AS verdunstung_bekannt,
    COALESCE(k.schimmel_bekannt, false) AS schimmel_bekannt,
    COALESCE(k.sockel_nachgewiesen, false) AS sockel_nachgewiesen,
    COALESCE(k.fax_bekannt, false) AS fax_bekannt,
    COALESCE(k.kanal_bekannt, false) AS kanal_bekannt,
    zahl(COALESCE(k.lager_kg, 0::numeric) * 1.96 * sqrt(GREATEST(COALESCE(k.a0_var, 0::numeric), 0::numeric)), 2, '1000000000000'::numeric)::numeric(14,2) AS sockel_oben_kg,
    heute() AS heute
   FROM v_kaskade_basis b
     LEFT JOIN je_charge k ON k.charge_nr = b.charge_nr
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN k.rest_tage_seit_epoche IS NOT NULL THEN '2000-01-01'::date + round(k.rest_tage_seit_epoche)::integer
                    ELSE b.eingangsdatum_mittel
                END AS rest_datum) x
  WHERE b.eingang_kg IS NOT NULL;
