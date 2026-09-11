-- sicht: v_palette
-- Jede Eingangspalette mit ihrem Nettogewicht: brutto − Kisten × Kistentara − Palettentara. netto_kg ist NULL, sobald eine der drei Angaben fehlt (0064) — eine fehlende Kistenzahl heisst nicht „null Kisten". Wie viele Paletten einer Charge ein Netto haben, steht als n_paletten_mit_netto in v_kaskade_basis.

 SELECT p.id,
    p.charge_nr,
    p.eingangsdatum,
    p.brutto_kg,
    p.kisten,
    p.gebindeart,
    p.brutto_kg - p.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_kg
   FROM palette p
     LEFT JOIN gebinde g ON g.art = p.gebindeart;
