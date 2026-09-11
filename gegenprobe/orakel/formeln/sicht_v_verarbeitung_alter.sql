-- sicht: v_verarbeitung_alter
-- Je Arbeit mit gezählten, datierten Paletten: mittleres Alter der verarbeiteten Ware gegen das mittlere Alter aller Paletten der Charge an dem Tag. differenz > 0: älter als der Durchschnitt verarbeitet.

 WITH gezaehlt AS (
         SELECT ap.auftrag_id,
            count(*)::integer AS n_paletten,
            zahl(avg(betriebstag(a_1.start_ts) - ap.eingangsdatum), 1, '1000000000'::numeric)::numeric(10,1) AS alter_verarbeitet
           FROM auftrag_palette ap
             JOIN auftrag a_1 ON a_1.id = ap.auftrag_id
          WHERE ap.eingangsdatum IS NOT NULL AND a_1.abgebrochen_ts IS NULL
          GROUP BY ap.auftrag_id
        ), charge_am_tag AS (
         SELECT a_1.id AS auftrag_id,
            zahl(avg(betriebstag(a_1.start_ts) - p.eingangsdatum), 1, '1000000000'::numeric)::numeric(10,1) AS alter_charge
           FROM auftrag a_1
             JOIN palette p ON p.charge_nr = a_1.charge_nr AND p.eingangsdatum <= betriebstag(a_1.start_ts)
          WHERE a_1.abgebrochen_ts IS NULL
          GROUP BY a_1.id
        )
 SELECT a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    c.schlag,
    a.station,
    a.weg,
    betriebstag(a.start_ts) AS tag,
    g.n_paletten,
    g.alter_verarbeitet,
    l.alter_charge,
    zahl(g.alter_verarbeitet - l.alter_charge, 1, '1000000000'::numeric)::numeric(10,1) AS differenz
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gezaehlt g ON g.auftrag_id = a.id
     LEFT JOIN charge_am_tag l ON l.auftrag_id = a.id
  WHERE a.abgebrochen_ts IS NULL AND a.station <> 'waschen'::station;
