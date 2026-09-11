-- sicht: v_palox_stand
-- Die Waagenstände je Palox der Reihe nach (Sortiermaschine, Waschstrasse). differenz ist die Menge seit der letzten Ablesung; ist der Stand gefallen, ist sie unbekannt (NULL) — der Palox wurde geleert, ohne dass jemand die Menge davor kennt (0060).

 SELECT s.id,
    s.auftrag_id,
    s.ts,
    s.palox_stand_kg,
    s.kg,
    lag(s.palox_stand_kg) OVER w AS vorher,
        CASE
            WHEN s.palox_geleert THEN GREATEST(s.palox_stand_kg - palox_tara_kg(), 0::numeric)
            WHEN lag(s.palox_stand_kg) OVER w IS NULL THEN GREATEST(s.palox_stand_kg - palox_tara_kg(), 0::numeric)
            WHEN s.palox_stand_kg < lag(s.palox_stand_kg) OVER w THEN NULL::numeric
            ELSE s.palox_stand_kg - lag(s.palox_stand_kg) OVER w
        END AS differenz,
    s.palox_geleert OR lag(s.palox_stand_kg) OVER w IS NOT NULL AND s.palox_stand_kg < lag(s.palox_stand_kg) OVER w AS zwischendurch_geleert,
    palox_station(a.station) AS station
   FROM schimmel_messung s
     JOIN auftrag a ON a.id = s.auftrag_id
  WHERE s.palox_stand_kg IS NOT NULL AND s.gemessen
  WINDOW w AS (PARTITION BY (palox_station(a.station)) ORDER BY s.ts, s.id)
  ORDER BY (palox_station(a.station)), s.ts, s.id;
