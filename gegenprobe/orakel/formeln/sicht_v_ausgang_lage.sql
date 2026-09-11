-- sicht: v_ausgang_lage
-- Je Quelle: wie viel eingelesen ist, bis wann, und wie viele Artikel noch auf ihre Bestätigung warten.

 SELECT code AS quelle,
    name,
    (( SELECT count(*) AS count
           FROM ausgang_zeile z
          WHERE z.quelle = q.code))::integer AS zeilen,
    ( SELECT min(z.datum) AS min
           FROM ausgang_zeile z
          WHERE z.quelle = q.code) AS von,
    ( SELECT max(z.datum) AS max
           FROM ausgang_zeile z
          WHERE z.quelle = q.code) AS bis,
    ( SELECT max(d.ts) AS max
           FROM ausgang_datei d
          WHERE d.quelle = q.code) AS zuletzt_geladen,
    (( SELECT count(*) AS count
           FROM ausgang_datei d
          WHERE d.quelle = q.code))::integer AS dateien,
    (( SELECT count(*) AS count
           FROM lieferung_import i
          WHERE i.quelle = q.code))::integer AS lieferungen,
    zahl(( SELECT COALESCE(sum(l.kg), 0::numeric) AS "coalesce"
           FROM lieferung_import i
             JOIN lieferung l ON l.id = i.lieferung_id
          WHERE i.quelle = q.code), 1, '10000000000000'::numeric)::numeric(14,1) AS kg,
    (( SELECT count(*) AS count
           FROM v_ausgang_artikel_vorschlag v
          WHERE NOT v.bestaetigt AND v.vorschlag_kuerbis AND (EXISTS ( SELECT 1
                   FROM ausgang_zeile z
                  WHERE z.quelle = q.code AND z.artikel_id = v.artikel_id AND z.artikel = v.artikel))))::integer AS artikel_offen
   FROM ausgang_quelle q;
