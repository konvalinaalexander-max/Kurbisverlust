-- gespeichert: erg_modell
-- v_schimmel_modell, gespeichert für die App Erneuert mit auswertung_schritt().

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
   FROM v_schimmel_modell;
