-- sicht: v_kaliber_verteilung
-- Wie sich die sortierte Ware je Charge auf die Kaliberbänder verteilt: Stückzahl und Masse je Band, dazu die Klassen "zu klein" und "Nebenkanal". Gewogen aus den Sortierläufen.

 SELECT charge_nr,
    sorte,
    klasse,
    kaliber_idx,
    band_von,
    band_bis,
    n_kuerbis,
    masse_kg
   FROM mv_kaliber_verteilung;
