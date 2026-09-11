-- sicht: v_hochrechnung
-- Die Kaskade auseinandergelegt: eine Zeile je Charge, Portion und Strom, mit dem verwendeten Koeffizienten, seiner Herkunft (koeff_art), der Zahl der Messungen dahinter (koeff_n) und der Formel. koeff_bekannt = false heisst: geschätzt, nicht gemessen.

 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    portion_kg,
    f_extrapoliert,
    u,
    strom,
    buch,
    kg,
    basis_kg,
    koeffizient,
    koeff_n,
    koeff_basis,
    formel,
    d_r,
    d_eta,
    d_a,
    d_a0,
    koeff_art,
    koeff_bekannt,
    kohorte
   FROM mv_hochrechnung;
