-- sicht: v_naechste_charge
-- Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Gerechnet aus v_prognose (Horizont 14 gegen Horizont 0) — dieselbe Formel wie die Kaskade, damit es im ganzen Programm nur eine Zwei-Wochen-Zahl gibt. prognose_verlust_14_kg ist, was an **verkaufsfähiger** Ware verloren geht, und verdunstung_14_kg + schimmel_14_kg ergeben es auf den Rappen: die Zerlegung ist multiplikativ exakt und beide Teile sind nie negativ (0071).

 SELECT p0.schluessel::integer AS charge_nr,
    b.sorte,
    b.schlag,
    p0.lager_kg,
    p0.alter_tage,
    p0.gute_ware_kg AS masse_jetzt_kg,
    zahl(p14.verlust_wasser_kg, 1, '100000000000'::numeric)::numeric(12,1) AS verdunstung_14_kg,
        CASE
            WHEN p0.modell_gilt THEN zahl(p14.verlust_faeulnis_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1) AS schimmel_14_kg,
        CASE
            WHEN p0.modell_gilt THEN zahl(p14.verlust_verkaufsfaehig_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1) AS prognose_verlust_14_kg,
    p0.hochgerechnet,
    p0.modell_gilt,
    p0.alter_von,
    p0.alter_bis,
    p0.n_kohorten
   FROM erg_prognose p0
     JOIN erg_prognose p14 ON p14.gruppe = 'charge'::text AND p14.schluessel = p0.schluessel AND p14.h = 14
     JOIN v_kaskade_basis b ON b.charge_nr = p0.schluessel::integer
  WHERE p0.gruppe = 'charge'::text AND p0.h = 0 AND p0.lager_kg > 0::numeric
  ORDER BY (
        CASE
            WHEN p0.modell_gilt THEN zahl(p14.verlust_verkaufsfaehig_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1)) DESC NULLS LAST;
