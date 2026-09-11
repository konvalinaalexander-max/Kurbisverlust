-- sicht: v_koeff_unsicherheit
-- Je Koeffizient und Sorte: der eigene Fehleranteil, das Gewicht auf dem gemeinsamen Gesamtwert und dessen Fehler. Getrennt, weil der Gesamtwert für alle Sorten derselbe ist und seine Fehler sich nicht wegmitteln.

 SELECT v_koeff_verdunstung_geschaetzt.art,
    v_koeff_verdunstung_geschaetzt.sorte,
    v_koeff_verdunstung_geschaetzt.b,
    v_koeff_verdunstung_geschaetzt.varianz_eigen,
    v_koeff_verdunstung_geschaetzt.gewicht_gesamt,
    v_koeff_verdunstung_geschaetzt.varianz_gesamt,
    v_koeff_verdunstung_geschaetzt.df
   FROM v_koeff_verdunstung_geschaetzt
UNION ALL
 SELECT v_koeff_kaliber_geschaetzt.art,
    v_koeff_kaliber_geschaetzt.sorte,
    v_koeff_kaliber_geschaetzt.b,
    v_koeff_kaliber_geschaetzt.varianz_eigen,
    v_koeff_kaliber_geschaetzt.gewicht_gesamt,
    v_koeff_kaliber_geschaetzt.varianz_gesamt,
    v_koeff_kaliber_geschaetzt.df
   FROM v_koeff_kaliber_geschaetzt;
