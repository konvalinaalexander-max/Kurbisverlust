-- sicht: v_wohin
-- Wohin ging der Kürbis — je Gruppe (gesamt, Sorte, Schlag, Charge) der ganze Eingang aufgeteilt: ausgeliefert, anderer Kanal, verdunstet und faul an der ausgelieferten Ware, Faules beim Abpacken, und was noch liegt (davon verkaufsfähig, Kanal, Fax erwartet, faul, verdunstet). rest_kg und lager_rest_kg sind die zwei Identitäten: beide haben den Erwartungswert null, und eine doppelt gezählte Portion bleibt darin stehen (0071).

 WITH gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'sorte'::text,
            erg_charge.sorte,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'schlag'::text,
            erg_charge.schlag,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'charge'::text,
            erg_charge.charge_nr::text AS charge_nr,
            erg_charge.charge_nr
           FROM erg_charge
        ), charge AS (
         SELECT g.gruppe,
            g.schluessel,
            count(*)::integer AS n_chargen,
            sum(c_1.eingang_kg) AS eingang_kg,
            sum(c_1.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(c_1.geliefert_kg) AS geliefert_kg,
            sum(c_1.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            sum(c_1.fax_heute_kg) AS fax_kg,
            sum(c_1.im_haus_heute_kg) AS lager_gute_ware_kg,
            sum(c_1.verkaufsfaehig_lager_kg) AS lager_verkaufsfaehig_kg,
            sum(c_1.kanal_im_haus_kg) AS lager_kanal_kg,
            sum(c_1.fax_erwartet_kg) AS lager_fax_kg,
            sum(c_1.lager_kg) AS lager_kg,
            bool_and(c_1.verlust_bekannt) AS vollstaendig
           FROM gruppen g
             JOIN erg_charge c_1 ON c_1.charge_nr = g.charge_nr
          GROUP BY g.gruppe, g.schluessel
        ), stroeme AS (
         SELECT erg_verlust.gruppe,
            erg_verlust.schluessel,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Verdunstung'::text) AS verdunstet_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Verdunstung'::text) AS lager_verdunstet_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Schimmel/Fäulnis'::text) AS faul_roh_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Schimmel/Fäulnis'::text) AS lager_faul_roh_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Nicht lagerbedingt'::text) AS sockel_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Nicht lagerbedingt'::text) AS lager_sockel_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Zu klein (Tierfutter)'::text) AS klein_ausgelagert_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Nebenkanal zu gross'::text) AS gross_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Zu klein (Tierfutter)'::text) AS lager_klein_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Nebenkanal zu gross'::text) AS lager_gross_kg
           FROM erg_verlust
          GROUP BY erg_verlust.gruppe, erg_verlust.schluessel
        )
 SELECT c.gruppe,
    c.schluessel,
    c.n_chargen,
    zahl(c.eingang_kg)::numeric(14,2) AS eingang_kg,
    zahl(c.ueberzaehlung_kg)::numeric(14,2) AS ueberzaehlung_kg,
    zahl(c.geliefert_kg)::numeric(14,2) AS geliefert_kg,
    zahl(c.kanal_ausgelagert_kg)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(s.klein_ausgelagert_kg)::numeric(14,2) AS klein_ausgelagert_kg,
    zahl(s.gross_ausgelagert_kg)::numeric(14,2) AS gross_ausgelagert_kg,
    zahl(s.verdunstet_ausgelagert_kg)::numeric(14,2) AS verdunstet_ausgelagert_kg,
    zahl(s.faul_roh_ausgelagert_kg + COALESCE(s.sockel_ausgelagert_kg, 0::numeric))::numeric(14,2) AS faul_ausgelagert_kg,
    zahl(s.sockel_ausgelagert_kg)::numeric(14,2) AS sockel_ausgelagert_kg,
    zahl(c.fax_kg)::numeric(14,2) AS fax_kg,
    zahl(c.lager_kg)::numeric(14,2) AS lager_kg,
    zahl(c.lager_gute_ware_kg)::numeric(14,2) AS lager_gute_ware_kg,
    zahl(c.lager_verkaufsfaehig_kg)::numeric(14,2) AS lager_verkaufsfaehig_kg,
    zahl(c.lager_kanal_kg)::numeric(14,2) AS lager_kanal_kg,
    zahl(s.lager_klein_kg)::numeric(14,2) AS lager_klein_kg,
    zahl(s.lager_gross_kg)::numeric(14,2) AS lager_gross_kg,
    zahl(c.lager_fax_kg)::numeric(14,2) AS lager_fax_kg,
    zahl(s.lager_faul_roh_kg + COALESCE(s.lager_sockel_kg, 0::numeric))::numeric(14,2) AS lager_faul_kg,
    zahl(s.lager_sockel_kg)::numeric(14,2) AS lager_sockel_kg,
    zahl(s.lager_verdunstet_kg)::numeric(14,2) AS lager_verdunstet_kg,
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.kanal_ausgelagert_kg - s.verdunstet_ausgelagert_kg - s.faul_roh_ausgelagert_kg - COALESCE(s.sockel_ausgelagert_kg, 0::numeric) - c.fax_kg - c.lager_kg)::numeric(14,2) AS rest_kg,
    zahl(c.lager_kg - c.lager_verkaufsfaehig_kg - c.lager_kanal_kg - c.lager_fax_kg - s.lager_faul_roh_kg - COALESCE(s.lager_sockel_kg, 0::numeric) - s.lager_verdunstet_kg)::numeric(14,2) AS lager_rest_kg,
    c.vollstaendig
   FROM charge c
     LEFT JOIN stroeme s ON s.gruppe = c.gruppe AND s.schluessel = c.schluessel;
