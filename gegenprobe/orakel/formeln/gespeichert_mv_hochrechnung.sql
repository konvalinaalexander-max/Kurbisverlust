-- gespeichert: mv_hochrechnung
-- v_hochrechnung, gespeichert. Inhaltlich gleich; erneuert von auswertung_schritt(3).

 SELECT k.charge_nr,
    k.sorte,
    k.schlag,
    k.portion,
    k.alter_tage,
    k.eingang_kg,
    zahl(c.m0)::numeric(14,2) AS portion_kg,
    k.f_extrapoliert,
    k.u,
    s.strom,
    s.buch,
        CASE
            WHEN s.bekannt THEN zahl(s.kg)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
        CASE
            WHEN s.bekannt THEN zahl(s.koeffizient, 6, '100000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,6) AS koeffizient,
    s.koeff_n,
    s.koeff_basis,
    s.formel,
    s.d_r,
    s.d_f * k.d_f_eta AS d_eta,
    s.d_a,
    s.d_a0,
    s.koeff_art,
    s.bekannt AS koeff_bekannt,
    k.kohorte
   FROM v_kaskade k
     CROSS JOIN LATERAL ( SELECT GREATEST(k.m0, 0::numeric) AS m0,
            GREATEST(k.m1, 0::numeric) AS m1,
            GREATEST(k.m2, 0::numeric) AS m2,
            GREATEST(k.verkaufsfaehig_kg, 0::numeric) AS verkaufsfaehig_kg,
            LEAST(GREATEST(k.r, 0::numeric), 1::numeric) AS r,
            LEAST(GREATEST(k.f, 0::numeric), 1::numeric) AS f,
            LEAST(GREATEST(k.a0, 0::numeric), 1::numeric) AS a0,
            LEAST(GREATEST(k.a_klein_n, 0::numeric), 1::numeric) AS a_klein_n,
            LEAST(GREATEST(k.a_gross_n, 0::numeric), 1::numeric) AS a_gross_n,
            LEAST(GREATEST(k.a_fax, 0::numeric), 1::numeric) AS a_fax) c
     CROSS JOIN LATERAL ( VALUES ('Verdunstung'::text,'verlust'::text,c.m0 - c.m1,c.m0,c.r,k.r_n,k.r_basis,'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'::text,- k.d_m1_r,0::numeric,0::numeric,0::numeric,NULL::text,k.r_bekannt), ('Nicht lagerbedingt'::text,'feld'::text,c.m1 * c.a0,c.m1,c.a0,k.f_n,'Grundaussortierung a₀ aus dem Verderbsmodell: was bei Lagerdauer null schon im Palox läge'::text,'Masse nach Verdunstung × a₀ — Erde, Hagelnarben, Schnittfehler; kein Lagerverlust'::text,k.d_m1_r * c.a0,0::numeric,0::numeric,c.m1,NULL::text,k.a0_bekannt), ('Schimmel/Fäulnis'::text,'verlust'::text,c.m1 * (1::numeric - c.a0) * c.f,c.m1 * (1::numeric - c.a0),c.f,k.f_n,'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen'::text,'Masse nach Verdunstung und Sockel × Schimmelanteil bei dieser Lagerdauer'::text,k.d_m1_r * (1::numeric - c.a0) * c.f,c.m1 * (1::numeric - c.a0),0::numeric,(- c.m1) * c.f,NULL::text,k.f_bekannt), ('Zu klein (Tierfutter)'::text,'marge'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_klein_n,c.m2,c.a_klein_n,k.klein_n,k.klein_basis,'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_klein_n,(- c.m1) * (1::numeric - c.a0) * c.a_klein_n,c.m2,(- c.m1) * (1::numeric - c.f) * c.a_klein_n,'ausschuss'::text,k.a_klein_bekannt), ('Nebenkanal zu gross'::text,'marge'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_gross_n,c.m2,c.a_gross_n,k.gross_n,k.gross_basis,'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_gross_n,(- c.m1) * (1::numeric - c.a0) * c.a_gross_n,c.m2,(- c.m1) * (1::numeric - c.f) * c.a_gross_n,'nebenkanal'::text,k.a_gross_bekannt), ('Faul beim Abpacken (Fax)'::text,'verlust'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),c.a_fax,k.fax_n,k.fax_basis,'Verkaufsfähige Masse × Anteil Faules, das beim Etikettieren aussortiert wird — vom Waschen und Stehen, nicht von der Lagerdauer'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,(- c.m1) * (1::numeric - c.a0) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),(- c.m1) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,'fax'::text,k.a_fax_bekannt), ('Verkaufsfähig'::text,'bilanz'::text,c.verkaufsfaehig_kg,c.m2,NULL::numeric,NULL::integer,NULL::text,'Rest der Kaskade'::text,0::numeric,0::numeric,0::numeric,0::numeric,NULL::text,true)) s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel, d_r, d_f, d_a, d_a0, koeff_art, bekannt);
