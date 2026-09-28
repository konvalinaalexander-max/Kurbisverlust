# Stand der Modelle

_Abzug vom 2026-09-28. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 28.09.2026, 11:36 · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan eingetragen, rechnet aber nicht** (*/10 * * * *) · letzter Lauf nie. Die App rechnet beim Öffnen selbst. In Supabase `cron.job_run_details` ansehen.

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0037 | 0.0034 | 0.0039 | 2 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0037 | 0.0034 | 0.0039 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0037 | 0.0034 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Amoro | 0.0037 | 0.0034 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.0037 | 0.0034 | 0.0039 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Bolp 5110 | 0.0037 | 0.0034 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0037 | 0.0034 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Lekor | 0.0037 | 0.0034 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Fictor | 0.0037 | 0.0034 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0036 | 0.0034 | 0.0039 | 12 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Ker Madec | 0.0037 | 0.0034 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0159 | 0.0003 | 0.0314 | 2 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0353 | 0.017 | 0.0535 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0159 | 0.0003 | 0.0314 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Amoro | 0.0159 | 0.0003 | 0.0314 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.0033 | 0 | 0.0202 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0159 | 0.0003 | 0.0314 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0159 | 0.0003 | 0.0314 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Lekor | 0.0159 | 0.0003 | 0.0314 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Fictor | 0.0159 | 0.0003 | 0.0314 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0028 | 0.0008 | 0.0048 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0159 | 0.0003 | 0.0314 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0725 | 0.0039 | 0.1411 | 2 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0089 | 0 | 0.0567 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0725 | 0.0039 | 0.1411 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Amoro | 0.0725 | 0.0039 | 0.1411 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.1132 | 0.0288 | 0.1977 | 2 | eigene Messungen, zum Gesamtwert gezogen |
| Bolp 5110 | 0.0725 | 0.0039 | 0.1411 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0072 | 0 | 0.0208 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0725 | 0.0039 | 0.1411 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Fictor | 0.0725 | 0.0039 | 0.1411 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0394 | 0 | 0.089 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0725 | 0.0039 | 0.1411 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Verderbsmodell (erg_modell)

| n | c_chargen | t_min | t_max | k | ln_lambda | lambda | x_mittel | sxx | smearing | ln_lambda_korrigiert | sigma2 | var_achse | var_k | kov_achse_k | t_faktor | brauchbar | selektions_versatz | sockel | sockel_unten | sockel_oben | sockel_nachweis | sockel_schwelle | sockel_var |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 12 | 5 | 8 | 46 | -0.4914 | -1.1489 | 0.317 | 3.3728 | 7752.826 | 1.5269 | -0.7257 | 1.443 | 0.0171 | 0.0216 | 0.0125 | 2.776 | false |  | 0 | 0 | 0 |  | 10.258 | 0 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 104 | 77 | 19 | 18 | 18 | 19 | 14 | 8 | 0 | 12 | 0 | 2 | 0 | 6 | 5 | 0 | 0 | 0 | 41 | 41 | 17 | 17 | 881 | 180 | 1 | 77 | 77 | 13 | 0 | 12 | 0 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | sockel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-28 | 614061.36 | 29 | 119101.3 | 119101.3 | 0 | 0 | 0 | 587 | 2026-09-21 | 0 | 119101.31 | 153479.12 |  | 110167.25 | 117931.47 | 49408.09 | 64641.32 |  | 0 | 0 | 9710.81 | 0 | 123846.19 | 375087.58 | 350801.82 | 24285.83 | 464469.95 | 9910.12 | 3887.82 | 0 | 0 | false |  |  | 0.194 | Ein Verluststrom ist noch nicht gemessen — die Ursachen sind erst vollständig, wenn jeder Koeffizient mindestens eine Messung hat. |

