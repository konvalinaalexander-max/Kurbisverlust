-- sicht: v_schimmel_modell
-- Verderbsmodell F(t) = 1 − exp(−λ·S·t^k), chargen-robust gefehlert, mit Grundaussortierung a₀ (sockel): Verarbeitungs-Punkte sind a₀ + (1−a₀)·F(t), Lagerkontrollen F(t). sockel_unten/oben ist der Profil-Bereich; selektions_versatz der Unterschied zwischen zufällig gegriffener und nach Aussehen ausgewählter Ware. Gespeichert; auswertung_aktualisieren() rechnet neu.

 SELECT n,
    c_chargen,
    t_min,
    t_max,
    k,
    ln_lambda,
    lambda,
    x_mittel,
    sxx,
    smearing,
    ln_lambda_korrigiert,
    sigma2,
    var_achse,
    var_k,
    kov_achse_k,
    t_faktor,
    brauchbar,
    selektions_versatz,
    sockel,
    sockel_unten,
    sockel_oben,
    sockel_nachweis,
    sockel_schwelle,
    sockel_var
   FROM mv_schimmel_modell;
