-- sicht: v_kaskade_basis
-- Eingang je Charge (vollständig, aus dem Erntejournal) und die Gegenproben aus den erfassten Arbeiten. stichtag ist seit 0061 heute(): die Ware im Haus altert bis heute, nicht bis zum Saisonende; saison_ende ist nur der Horizont der Prognose.

 WITH stichtag AS (
         SELECT heute() AS bis
        ), je_station AS (
         SELECT v_auftrag_masse.charge_nr,
            sum(v_auftrag_masse.eingang_netto_kg) FILTER (WHERE v_auftrag_masse.station = 'sortieren'::station) AS sortiert_kg,
            sum(v_auftrag_masse.eingang_netto_kg) FILTER (WHERE v_auftrag_masse.station = 'waschen'::station AND NOT v_auftrag_masse.ist_fax) AS gewaschen_kg,
            sum(v_auftrag_masse.eingang_netto_kg) FILTER (WHERE v_auftrag_masse.station = 'waschen_sortieren'::station) AS hand_kg,
            sum(v_auftrag_masse.eingang_netto_kg) FILTER (WHERE v_auftrag_masse.station = 'waschen_sortieren'::station AND v_auftrag_masse.weg = 'hand'::verarbeitungsweg) AS kg_hand,
            sum(v_auftrag_masse.eingang_netto_kg * v_auftrag_masse.lagertage) FILTER (WHERE (v_auftrag_masse.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND v_auftrag_masse.lagertage IS NOT NULL) / NULLIF(sum(v_auftrag_masse.eingang_netto_kg) FILTER (WHERE (v_auftrag_masse.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND v_auftrag_masse.lagertage IS NOT NULL), 0::numeric) AS alter_band,
            sum(v_auftrag_masse.eingang_netto_kg) FILTER (WHERE v_auftrag_masse.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AS am_band_kg
           FROM v_auftrag_masse
          WHERE v_auftrag_masse.eingang_netto_kg IS NOT NULL
          GROUP BY v_auftrag_masse.charge_nr
        ), anteil AS (
         SELECT s_1.charge_nr,
            s_1.sortiert_kg,
            s_1.gewaschen_kg,
            s_1.hand_kg,
            s_1.kg_hand,
            s_1.alter_band,
            s_1.am_band_kg,
            LEAST(COALESCE(s_1.gewaschen_kg, 0::numeric) / NULLIF(s_1.sortiert_kg, 0::numeric), 1::numeric) AS anteil_gewaschen
           FROM je_station s_1
        ), kohorte AS (
         SELECT k_1.charge_nr,
            min(k_1.eingangsdatum) AS eingang_von,
            max(k_1.eingangsdatum) AS eingang_bis,
            count(*)::integer AS n_eingangstage
           FROM v_charge_kohorte k_1
          GROUP BY k_1.charge_nr
        )
 SELECT r.charge_nr,
    r.schlag,
    r.sorte,
    r.eingang_netto_kg AS eingang_kg,
    r.n_paletten,
    r.eingangsdatum_mittel,
    s.bis AS stichtag,
    r.n_paletten_mit_netto,
    COALESCE(a.sortiert_kg, 0::numeric) AS sortiert_kg,
    COALESCE(a.gewaschen_kg, 0::numeric) AS gewaschen_kg,
    COALESCE(a.hand_kg, 0::numeric) AS hand_kg,
    COALESCE(a.sortiert_kg, 0::numeric) * (1::numeric - COALESCE(a.anteil_gewaschen, 0::numeric)) AS wartet_kg,
    COALESCE(a.anteil_gewaschen, 0::numeric) AS anteil_gewaschen,
    COALESCE(a.kg_hand / NULLIF(COALESCE(a.hand_kg, 0::numeric) + COALESCE(a.sortiert_kg, 0::numeric), 0::numeric), 0::numeric) AS weg2_anteil,
    a.alter_band,
    COALESCE(a.am_band_kg, 0::numeric) AS am_band_kg,
    k.eingang_von,
    k.eingang_bis,
    k.n_eingangstage,
    heute() AS heute,
    stichtag() AS saison_ende
   FROM v_charge_rueckgrat r
     CROSS JOIN stichtag s
     LEFT JOIN anteil a ON a.charge_nr = r.charge_nr
     LEFT JOIN kohorte k ON k.charge_nr = r.charge_nr
  WHERE r.eingang_netto_kg IS NOT NULL;
