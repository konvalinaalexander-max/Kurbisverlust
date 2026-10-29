# Stand der Modelle

_Abzug vom 2026-10-29. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 28.10.2026, 09:30 (15 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 29.10.2026, 11:55 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0025 | 0.0018 | 0.0033 | 9 | Wiegungen dieser Sorte |
| Fictor | 0.005 | 0.0023 | 0.0078 | 5 | Wiegungen dieser Sorte |
| Kaori Kuri | 0.0028 | 0.0021 | 0.0034 | 39 | Wiegungen dieser Sorte |
| Orange Summer | 0.0023 | 0.0022 | 0.0025 | 24 | Wiegungen dieser Sorte |
| Bolp 5110 | 0.0025 | 0.0023 | 0.0027 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.0032 | 0.0025 | 0.0038 | 10 | Wiegungen dieser Sorte |
| Amoro | 0.0025 | 0.0023 | 0.0027 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Lekor | 0.0025 | 0.0023 | 0.0027 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Mieluna | 0.0019 | 0.0015 | 0.0023 | 52 | Wiegungen dieser Sorte |
| Tiana | 0.0025 | 0.0022 | 0.0028 | 49 | Wiegungen dieser Sorte |
| Ker Madec | 0.0025 | 0.0023 | 0.0027 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 6 | Sortierläufe/Handmessungen dieser Sorte |
| Butterkin | 0.0029 | 0 | 0.0069 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0129 | 0.0076 | 0.0182 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Lekor | 0.0129 | 0.0076 | 0.0182 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Orange Summer | 0.0392 | 0 | 0.0856 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0129 | 0.0076 | 0.0182 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Amoro | 0.0129 | 0.0076 | 0.0182 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Mieluna | 0.0026 | 0 | 0.0184 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Tiana | 0.0047 | 0 | 0.0123 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0227 | 0.0143 | 0.0312 | 21 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0129 | 0.0076 | 0.0182 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0011 | 0 | 0.0043 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0093 | 0.0032 | 0.0154 | 18 | Sortierläufe/Handmessungen dieser Sorte |
| Orange Summer | 0.0272 | 0 | 0.0759 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0692 | 0.0535 | 0.0849 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.1443 | 0.0839 | 0.2047 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0692 | 0.0535 | 0.0849 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Lekor | 0.0692 | 0.0535 | 0.0849 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Mieluna | 0.0339 | 0.0048 | 0.063 | 11 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0692 | 0.0535 | 0.0849 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Tiana | 0.0365 | 0.0211 | 0.0519 | 19 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0692 | 0.0535 | 0.0849 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen | mittel | lager_mittel | anstieg_je_woche |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle | Arbeiten aller Sorten | 0.0225 | 0 | 0.0461 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0225 | 37.7 |  |
| Amoro | waschen | alle | Arbeiten aller Sorten | 0.0877 | 0.0638 | 0.1116 | 30 | 9 | 2026-09-24 | 2026-10-28 | true | 0.0877 | 43.2 | 0 |
| Amoro | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0757 | 0.0581 | 0.0934 | 54 | 16 | 2026-09-21 | 2026-10-28 | true | 0.0757 | 30.8 | 0 |
| Butterkin | sortieren | alle | Arbeiten aller Sorten | 0.0225 | 0 | 0.0461 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0225 | 37.7 |  |
| Butterkin | waschen | sorte | Arbeiten dieser Sorte | 0.1289 | 0.0537 | 0.2041 | 7 | 2 | 2026-09-26 | 2026-10-22 | false | 0.1289 | 42.6 | 0 |
| Butterkin | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0757 | 0.0581 | 0.0934 | 54 | 16 | 2026-09-21 | 2026-10-28 | true | 0.0757 | 30.8 | 0 |
| Fictor | sortieren | alle | Arbeiten aller Sorten | 0.0225 | 0 | 0.0461 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0225 | 37.7 |  |
| Fictor | waschen | alle | Arbeiten aller Sorten | 0.0877 | 0.0638 | 0.1116 | 30 | 9 | 2026-09-24 | 2026-10-28 | true | 0.0877 | 43.2 | 0 |
| Fictor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0757 | 0.0581 | 0.0934 | 54 | 16 | 2026-09-21 | 2026-10-28 | true | 0.0757 | 30.8 | 0 |
| Kaori Kuri | sortieren | alle | Arbeiten aller Sorten | 0.0225 | 0 | 0.0461 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0225 | 37.7 |  |
| Kaori Kuri | waschen | sorte | Arbeiten dieser Sorte | 0.0973 | 0.0245 | 0.1701 | 7 | 2 | 2026-09-24 | 2026-10-16 | false | 0.0973 | 50.3 | 0 |
| Kaori Kuri | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0733 | 0.0436 | 0.103 | 14 | 4 | 2026-09-21 | 2026-10-28 | false | 0.0733 | 31.2 | 0 |
| Ker Madec | sortieren | alle | Arbeiten aller Sorten | 0.0225 | 0 | 0.0461 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0225 | 37.7 |  |
| Ker Madec | waschen | alle | Arbeiten aller Sorten | 0.0877 | 0.0638 | 0.1116 | 30 | 9 | 2026-09-24 | 2026-10-28 | true | 0.0877 | 43.2 | 0 |
| Ker Madec | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0757 | 0.0581 | 0.0934 | 54 | 16 | 2026-09-21 | 2026-10-28 | true | 0.0757 | 30.8 | 0 |
| Lekor | sortieren | alle | Arbeiten aller Sorten | 0.0225 | 0 | 0.0461 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0225 | 37.7 |  |
| Lekor | waschen | sorte | Arbeiten dieser Sorte | 0.1075 | 0.0744 | 0.1405 | 3 | 1 | 2026-10-01 | 2026-10-22 | false | 0.1075 | 76.9 | 0 |
| Lekor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0757 | 0.0581 | 0.0934 | 54 | 16 | 2026-09-21 | 2026-10-28 | true | 0.0757 | 30.8 | 0 |
| Mieluna | sortieren | alle | Arbeiten aller Sorten | 0.0225 | 0 | 0.0461 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0225 | 37.7 |  |
| Mieluna | waschen | alle | Arbeiten aller Sorten | 0.0877 | 0.0638 | 0.1116 | 30 | 9 | 2026-09-24 | 2026-10-28 | true | 0.0877 | 43.2 | 0 |
| Mieluna | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0548 | 0.0352 | 0.0744 | 11 | 2 | 2026-10-01 | 2026-10-28 | false | 0.0548 | 29.8 | 0 |
| Orange Summer | sortieren | alle | Arbeiten aller Sorten | 0.0225 | 0 | 0.0461 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0225 | 37.7 |  |
| Orange Summer | waschen | alle | Arbeiten aller Sorten | 0.0877 | 0.0638 | 0.1116 | 30 | 9 | 2026-09-24 | 2026-10-28 | true | 0.0877 | 43.2 | 0 |
| Orange Summer | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0654 | 0.0248 | 0.106 | 5 | 1 | 2026-10-05 | 2026-10-28 | false | 0.0654 | 60.4 | 0 |
| Orangita | sortieren | alle | Arbeiten aller Sorten | 0.0225 | 0 | 0.0461 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0225 | 37.7 |  |
| Orangita | waschen | alle | Arbeiten aller Sorten | 0.0877 | 0.0638 | 0.1116 | 30 | 9 | 2026-09-24 | 2026-10-28 | true | 0.0877 | 43.2 | 0 |
| Orangita | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.1186 | 0.0228 | 0.2144 | 7 | 2 | 2026-09-23 | 2026-10-24 | false | 0.1186 | 43 | 0 |
| Tiana | sortieren | sorte | Arbeiten dieser Sorte | 0.0069 | 0 | 0.0138 | 4 | 2 | 2026-09-30 | 2026-10-09 | false | 0.0069 | 22.7 |  |
| Tiana | waschen | sorte | Arbeiten dieser Sorte | 0.0616 | 0.038 | 0.0853 | 11 | 3 | 2026-09-25 | 2026-10-28 | false | 0.0616 | 33.2 | 0 |
| Tiana | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0626 | 0.0479 | 0.0773 | 14 | 5 | 2026-09-23 | 2026-10-28 | false | 0.0626 | 17.2 | 0 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 548 | 439 | 100 | 95 | 95 | 100 | 85 | 47 | 0 | 19 | 5 | 9 | 0 | 34 | 33 | 0 | 0 | 0 | 232 | 232 | 91 | 91 | 3762 | 1354 | 1 | 439 | 439 | 66 | 12 | 19 | 5 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-28 | 696473.3 | 36 | 331639.4 | 331639.4 | 0 | 0 | 0 | 1502 | 2026-10-28 | 0 | 331639.32 | 440344.19 | 165635.72 | 73888.36 | 257383.2 | 71673.42 | 93962.32 | 0 | 0 | 18010.91 | 0 | 79794.6 | 259392.8 | 231535.5 | 9846.38 | 311018.95 | 50016.1 | 54890.11 | 0 | 0 | true | -5304.43 | -0.0076 | 0.4762 | Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — bei einigen Chargen rund 54890 kg zu viel. Fast immer fehlt der Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine Lieferung ist der falschen Charge zugeordnet. |

