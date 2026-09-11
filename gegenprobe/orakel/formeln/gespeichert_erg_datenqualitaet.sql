-- gespeichert: erg_datenqualitaet
-- v_datenqualitaet, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT paletten_gezaehlt,
    paletten_mit_datum,
    arbeiten_fertig,
    arbeiten_mit_ablesung,
    arbeiten_mit_zwei_ablesungen,
    arbeiten_mit_antwort,
    ausschuss_messungen,
    ausschuss_gewogen,
    lagerkontrollen,
    sortierlaeufe,
    sortierlaeufe_zugeordnet,
    sortier_arbeiten,
    sortier_arbeiten_mit_kisten,
    wasch_arbeiten,
    wasch_arbeiten_mit_kisten,
    fax_arbeiten,
    fax_arbeiten_mit_kisten,
    fax_arbeiten_mit_faulem,
    ws_paletten_gezaehlt,
    ws_paletten_mit_zettelgewicht,
    arbeiten_nach_waschen,
    arbeiten_mit_kistensystem,
    wasch_kisten_gezaehlt,
    wasch_kisten_mit_sortierdatum,
    arbeiten_mit_palox_unbekannt
   FROM v_datenqualitaet;
