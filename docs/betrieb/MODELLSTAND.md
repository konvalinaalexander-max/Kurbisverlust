# Stand der Modelle

_Abzug vom 2026-09-29. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 29.09.2026, 08:51 · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/10 * * * *) · letzter Lauf 29.09.2026, 12:40 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0035 | 0.0031 | 0.0039 | 5 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Bolp 5110 | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.0035 | 0.0031 | 0.0039 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Amoro | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Lekor | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0035 | 0.0031 | 0.0039 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Fictor | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0035 | 0.003 | 0.004 | 12 | Wiegungen dieser Sorte |
| Ker Madec | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0159 | 0.0003 | 0.0314 | 2 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0159 | 0.0003 | 0.0314 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Bolp 5110 | 0.0159 | 0.0003 | 0.0314 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.0033 | 0 | 0.0202 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0159 | 0.0003 | 0.0314 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0159 | 0.0003 | 0.0314 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Lekor | 0.0159 | 0.0003 | 0.0314 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0353 | 0.017 | 0.0535 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0159 | 0.0003 | 0.0314 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0028 | 0.0008 | 0.0048 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0159 | 0.0003 | 0.0314 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0718 | 0.0091 | 0.1345 | 2 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0072 | 0 | 0.0208 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0718 | 0.0091 | 0.1345 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.1135 | 0.0415 | 0.1854 | 3 | eigene Messungen, zum Gesamtwert gezogen |
| Amoro | 0.0718 | 0.0091 | 0.1345 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0718 | 0.0091 | 0.1345 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Lekor | 0.0718 | 0.0091 | 0.1345 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.009 | 0 | 0.022 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0718 | 0.0091 | 0.1345 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0442 | 0 | 0.0893 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0718 | 0.0091 | 0.1345 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Verderbsmodell (erg_modell)

| n | c_chargen | t_min | t_max | k | ln_lambda | lambda | x_mittel | sxx | smearing | ln_lambda_korrigiert | sigma2 | var_achse | var_k | kov_achse_k | t_faktor | brauchbar | selektions_versatz | sockel | sockel_unten | sockel_oben | sockel_nachweis | sockel_schwelle | sockel_var |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 12 | 5 | 8 | 46 | -0.4948 | -1.1422 | 0.3191 | 3.3735 | 7768.811 | 1.5285 | -0.7179 | 1.4461 | 0.0172 | 0.0217 | 0.0126 | 2.776 | false |  | 0 | 0 | 0 |  | 10.258 | 0 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 103 | 80 | 19 | 18 | 18 | 19 | 14 | 8 | 0 | 12 | 0 | 2 | 0 | 6 | 5 | 0 | 0 | 0 | 44 | 44 | 17 | 17 | 769 | 180 | 1 | 80 | 80 | 13 | 0 | 12 | 0 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | sockel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-29 | 614061.36 | 29 | 154494.7 | 154494.7 | 0 | 0 | 0 | 772 | 2026-09-29 | 0 | 154326.71 | 200620.32 | 114104.33 | 107797.36 | 120411.18 | 48107.37 | 65996.94 | 0 | 0 | 0 | 12476.73 | 0 | 123055.97 | 351499.79 | 316539.44 | 22483.68 | 419310.5 | 9910.12 | 5869.56 | 0 | 0 | true | 0.09 | 0 | 0.2516 | Bis heute (29.09.2026): 614.1 t Eingang = 154.3 t ausgeliefert + 114.1 t Verlust (Verdunstung 48.1 t, Faules 66.0 t, Fax 0.0 t) + 351.5 t noch im Haus (davon 316.5 t verkaufsfähig, 35.0 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. 5870 kg Überzählung. |

