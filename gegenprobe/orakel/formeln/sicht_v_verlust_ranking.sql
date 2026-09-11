-- sicht: v_verlust_ranking
-- Alle Ströme der Kaskade für eine Gruppe, absteigend nach Masse — nicht nur Verlust: buch sagt, was es ist (verlust = echter Verlust, marge = anderer Kanal, feld = nicht lagerbedingt). Nur für Diagnose und SQL-Editor; die App liest erg_verlust. Wer über alle Zeilen summiert, summiert Äpfel und Birnen.

 SELECT strom,
    buch,
    kg,
    kg_unten,
    kg_oben,
    kg_beobachtet,
    kg_projiziert,
    kg_extrapoliert,
    kg_erwartet,
    koeff_n_min,
    streuung_kg,
    df
   FROM verlust_ranking() verlust_ranking(strom, buch, kg, kg_unten, kg_oben, kg_beobachtet, kg_projiziert, kg_extrapoliert, kg_erwartet, koeff_n_min, streuung_kg, df);
