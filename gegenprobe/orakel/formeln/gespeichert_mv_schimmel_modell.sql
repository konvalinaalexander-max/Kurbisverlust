-- gespeichert: mv_schimmel_modell
-- Das gerechnete Verderbsmodell, gespeichert — dieselben Grössen wie v_schimmel_modell_rechnen. sockel ist der Anteil, der schon beim Einlagern verdorben war und nicht dem Lager anzulasten ist. Erneuert von auswertung_schritt(2).

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
   FROM v_schimmel_modell_rechnen;
