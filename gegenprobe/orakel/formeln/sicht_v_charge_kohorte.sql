-- sicht: v_charge_kohorte
-- Je Charge und Eingangstag: wie viele Paletten kamen (eingang_kg), wie viele davon in der App mit diesem Zetteldatum gezählt wurden (n_verarbeitet — punktuell, keine Menge). Die Kaskade verteilt den Bestand nach eingang_kg (0060).

 WITH gezaehlt AS (
         SELECT a.charge_nr,
            COALESCE(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum) AS eingangsdatum,
            count(*)::integer AS n
           FROM auftrag_palette ap
             JOIN auftrag a ON a.id = ap.auftrag_id
             LEFT JOIN palette p ON p.id = ap.palette_id
             LEFT JOIN verdunstung_wiegung w ON w.id = ap.wiegung_id
          WHERE a.abgebrochen_ts IS NULL AND (a.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station]))
          GROUP BY a.charge_nr, (COALESCE(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum))
        ), je_datum AS (
         SELECT p.charge_nr,
            p.eingangsdatum,
            count(*)::integer AS n,
            avg(p.netto_kg) AS netto_mittel
           FROM v_palette p
          GROUP BY p.charge_nr, p.eingangsdatum
        ), charge_netto AS (
         SELECT v_palette.charge_nr,
            avg(v_palette.netto_kg) AS netto
           FROM v_palette
          GROUP BY v_palette.charge_nr
        )
 SELECT d.charge_nr,
    d.eingangsdatum,
    d.n AS n_paletten,
    COALESCE(g.n, 0) AS n_verarbeitet,
    GREATEST(d.n - COALESCE(g.n, 0), 0) AS n_rest,
    zahl(COALESCE(d.netto_mittel, cn.netto), 2, '100000000'::numeric)::numeric(10,2) AS netto_je_palette,
    zahl(GREATEST(d.n - COALESCE(g.n, 0), 0)::numeric * COALESCE(d.netto_mittel, cn.netto), 2, '10000000000'::numeric)::numeric(12,2) AS rest_kg,
    CURRENT_DATE - d.eingangsdatum AS alter_heute,
    zahl(d.n::numeric * COALESCE(d.netto_mittel, cn.netto), 2, '10000000000'::numeric)::numeric(12,2) AS eingang_kg
   FROM je_datum d
     JOIN charge_netto cn ON cn.charge_nr = d.charge_nr
     LEFT JOIN gezaehlt g ON g.charge_nr = d.charge_nr AND g.eingangsdatum = d.eingangsdatum;
