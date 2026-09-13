-- sicht: v_verarbeitung_alter
-- Je Arbeit mit gezählten, datierten Paletten: mittleres Alter der verarbeiteten Ware gegen das mittlere Alter aller Paletten der Charge an dem Tag. differenz > 0: älter als der Durchschnitt verarbeitet.

 WITH tage AS MATERIALIZED (
         SELECT a.id,
            a.charge_nr,
            a.station,
            a.weg,
            betriebstag(a.start_ts) AS tag
           FROM auftrag a
          WHERE a.abgebrochen_ts IS NULL
        ), gezaehlt AS (
         SELECT t_1.id AS auftrag_id,
            count(*)::integer AS n_paletten,
            zahl(avg(t_1.tag - ap.eingangsdatum), 1, '1000000000'::numeric)::numeric(10,1) AS alter_verarbeitet
           FROM tage t_1
             JOIN auftrag_palette ap ON ap.auftrag_id = t_1.id
          WHERE ap.eingangsdatum IS NOT NULL
          GROUP BY t_1.id
        ), charge_am_tag AS (
         SELECT t_1.id AS auftrag_id,
            zahl(avg(t_1.tag - p.eingangsdatum), 1, '1000000000'::numeric)::numeric(10,1) AS alter_charge
           FROM tage t_1
             JOIN palette p ON p.charge_nr = t_1.charge_nr AND p.eingangsdatum <= t_1.tag
          GROUP BY t_1.id
        )
 SELECT t.id AS auftrag_id,
    t.charge_nr,
    c.sorte,
    c.schlag,
    t.station,
    t.weg,
    t.tag,
    g.n_paletten,
    g.alter_verarbeitet,
    l.alter_charge,
    zahl(g.alter_verarbeitet - l.alter_charge, 1, '1000000000'::numeric)::numeric(10,1) AS differenz
   FROM tage t
     JOIN charge c ON c.nr = t.charge_nr
     JOIN gezaehlt g ON g.auftrag_id = t.id
     LEFT JOIN charge_am_tag l ON l.auftrag_id = t.id
  WHERE t.station <> 'waschen'::station;
