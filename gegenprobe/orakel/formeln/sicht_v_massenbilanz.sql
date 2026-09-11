-- sicht: v_massenbilanz
-- Die Probe aufs Exempel je Charge: Was das Modell am Band erwartet (modell_am_band_kg) gegen das, was die Sortier-Datei gewogen hat (csv_gemessen_kg). abweichung_anteil nahe 0 heisst, die Koeffizienten treffen die Wirklichkeit; systematisch positiv heisst, die Verluste sind überschätzt. Nur für Chargen mit Sortier-Datei aussagekräftig.

 WITH csv_anteil AS MATERIALIZED (
         SELECT am.charge_nr,
            COALESCE(sum(am.eingang_netto_kg) FILTER (WHERE (EXISTS ( SELECT 1
                   FROM sortier_lauf l
                  WHERE l.auftrag_id = am.auftrag_id))) / NULLIF(sum(am.eingang_netto_kg), 0::numeric), 0::numeric) AS anteil_mit_csv
           FROM v_auftrag_masse am
          WHERE (am.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND am.eingang_netto_kg IS NOT NULL
          GROUP BY am.charge_nr
        ), gemessen AS MATERIALIZED (
         SELECT v_sortier_lauf_masse.charge_nr,
            sum(v_sortier_lauf_masse.masse_kg) AS gemessen_kg
           FROM v_sortier_lauf_masse
          GROUP BY v_sortier_lauf_masse.charge_nr
        ), rest AS MATERIALIZED (
         SELECT v_kaskade.charge_nr,
            sum(v_kaskade.m2) FILTER (WHERE v_kaskade.portion = 'lager'::text) AS restbestand_kg
           FROM v_kaskade
          GROUP BY v_kaskade.charge_nr
        ), modell AS MATERIALIZED (
         SELECT b_1.charge_nr,
            b_1.am_band_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), COALESCE(b_1.alter_band, 0::numeric)) * (1::numeric - sockel_anteil()) * (1::numeric - schimmelanteil(COALESCE(b_1.alter_band, 0::numeric))) * q.anteil_mit_csv AS am_band_modell_kg
           FROM v_kaskade_basis b_1
             LEFT JOIN csv_anteil q ON q.charge_nr = b_1.charge_nr
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b_1.sorte
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.eingang_kg,
    b.ausgelagert_kg,
    b.lager_kg,
    b.n_paletten,
    b.alter_ausgelagert,
    b.alter_lager,
    b.stichtag,
    zahl(m.am_band_modell_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS modell_am_band_kg,
    c.gemessen_kg AS csv_gemessen_kg,
    zahl(c.gemessen_kg - m.am_band_modell_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS abweichung_kg,
        CASE
            WHEN m.am_band_modell_kg > 0::numeric THEN zahl((c.gemessen_kg - m.am_band_modell_kg) / m.am_band_modell_kg, 4, '1000000'::numeric)::numeric(10,4)
            ELSE NULL::numeric
        END AS abweichung_anteil,
    zahl(r.restbestand_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS restbestand_kg,
    kb.alter_band
   FROM erg_charge b
     JOIN v_kaskade_basis kb ON kb.charge_nr = b.charge_nr
     LEFT JOIN modell m ON m.charge_nr = b.charge_nr
     LEFT JOIN gemessen c ON c.charge_nr = b.charge_nr
     LEFT JOIN rest r ON r.charge_nr = b.charge_nr;
