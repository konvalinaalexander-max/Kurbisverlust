# Stand der Modelle

_Abzug vom 2026-10-31. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 31.10.2026, 02:00 (16 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 31.10.2026, 11:25 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Fictor | 0.005 | 0.0023 | 0.0078 | 5 | Wiegungen dieser Sorte |
| Orange Summer | 0.0023 | 0.0022 | 0.0025 | 24 | Wiegungen dieser Sorte |
| Mieluna | 0.0019 | 0.0015 | 0.0023 | 52 | Wiegungen dieser Sorte |
| Tiana | 0.0025 | 0.0022 | 0.0028 | 49 | Wiegungen dieser Sorte |
| Kaori Kuri | 0.0024 | 0.002 | 0.0028 | 62 | Wiegungen dieser Sorte |
| Orangita | 0.0027 | 0.0019 | 0.0034 | 11 | Wiegungen dieser Sorte |
| Ker Madec | 0.0024 | 0.0022 | 0.0026 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Amoro | 0.0024 | 0.0022 | 0.0026 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Lekor | 0.0023 | 0.0008 | 0.0039 | 6 | Wiegungen dieser Sorte |
| Bolp 5110 | 0.0024 | 0.0022 | 0.0026 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.0027 | 0.0022 | 0.0033 | 15 | Wiegungen dieser Sorte |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Butterkin | 0.0029 | 0 | 0.0069 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Orange Summer | 0.0392 | 0 | 0.0856 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0026 | 0 | 0.0184 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Tiana | 0.0047 | 0 | 0.0123 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Orangita | 0 | 0 | 0 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0193 | 0.0111 | 0.0275 | 23 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0123 | 0.0073 | 0.0173 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Fictor | 0.0123 | 0.0073 | 0.0173 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Lekor | 0.0514 | 0.0008 | 0.102 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0123 | 0.0073 | 0.0173 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Amoro | 0.0123 | 0.0073 | 0.0173 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orange Summer | 0.0272 | 0 | 0.0759 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0339 | 0.0048 | 0.063 | 11 | Sortierläufe/Handmessungen dieser Sorte |
| Tiana | 0.0365 | 0.0211 | 0.0519 | 19 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0079 | 0.0023 | 0.0134 | 20 | Sortierläufe/Handmessungen dieser Sorte |
| Orangita | 0.0009 | 0 | 0.0036 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.066 | 0.0511 | 0.0809 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Ker Madec | 0.066 | 0.0511 | 0.0809 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Lekor | 0.0671 | 0.001 | 0.1332 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.066 | 0.0511 | 0.0809 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.1407 | 0.0929 | 0.1885 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.066 | 0.0511 | 0.0809 | 0 | alle Sorten (eigene: 0, gilt ab 3) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen | mittel | lager_mittel | anstieg_je_woche |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle | Arbeiten aller Sorten | 0.0223 | 0 | 0.0456 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0223 | 37.8 |  |
| Amoro | waschen | alle | Arbeiten aller Sorten | 0.0867 | 0.0668 | 0.1066 | 35 | 10 | 2026-09-24 | 2026-10-30 | true | 0.0867 | 45.7 | 0 |
| Amoro | waschen_sortieren | alle | Arbeiten aller Sorten | 0.076 | 0.0591 | 0.093 | 57 | 16 | 2026-09-21 | 2026-10-30 | true | 0.076 | 31.9 | 0 |
| Butterkin | sortieren | alle | Arbeiten aller Sorten | 0.0223 | 0 | 0.0456 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0223 | 37.8 |  |
| Butterkin | waschen | sorte | Arbeiten dieser Sorte | 0.1226 | 0.0564 | 0.1888 | 8 | 2 | 2026-09-26 | 2026-10-30 | false | 0.1226 | 44.7 | 0 |
| Butterkin | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0841 | 0.0509 | 0.1172 | 4 | 1 | 2026-09-22 | 2026-10-30 | false | 0.0841 | 36.5 | 0 |
| Fictor | sortieren | alle | Arbeiten aller Sorten | 0.0223 | 0 | 0.0456 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0223 | 37.8 |  |
| Fictor | waschen | alle | Arbeiten aller Sorten | 0.0867 | 0.0668 | 0.1066 | 35 | 10 | 2026-09-24 | 2026-10-30 | true | 0.0867 | 45.7 | 0 |
| Fictor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.076 | 0.0591 | 0.093 | 57 | 16 | 2026-09-21 | 2026-10-30 | true | 0.076 | 31.9 | 0 |
| Kaori Kuri | sortieren | alle | Arbeiten aller Sorten | 0.0223 | 0 | 0.0456 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0223 | 37.8 |  |
| Kaori Kuri | waschen | sorte | Arbeiten dieser Sorte | 0.0908 | 0.0349 | 0.1466 | 9 | 3 | 2026-09-24 | 2026-10-30 | false | 0.0908 | 45.4 | 0 |
| Kaori Kuri | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0725 | 0.0428 | 0.1021 | 14 | 4 | 2026-09-21 | 2026-10-28 | false | 0.0725 | 31.3 | 0 |
| Ker Madec | sortieren | alle | Arbeiten aller Sorten | 0.0223 | 0 | 0.0456 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0223 | 37.8 |  |
| Ker Madec | waschen | alle | Arbeiten aller Sorten | 0.0867 | 0.0668 | 0.1066 | 35 | 10 | 2026-09-24 | 2026-10-30 | true | 0.0867 | 45.7 | 0 |
| Ker Madec | waschen_sortieren | alle | Arbeiten aller Sorten | 0.076 | 0.0591 | 0.093 | 57 | 16 | 2026-09-21 | 2026-10-30 | true | 0.076 | 31.9 | 0 |
| Lekor | sortieren | alle | Arbeiten aller Sorten | 0.0223 | 0 | 0.0456 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0223 | 37.8 |  |
| Lekor | waschen | sorte | Arbeiten dieser Sorte | 0.102 | 0.0833 | 0.1207 | 5 | 1 | 2026-10-01 | 2026-10-30 | false | 0.102 | 85.3 | 0 |
| Lekor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.076 | 0.0591 | 0.093 | 57 | 16 | 2026-09-21 | 2026-10-30 | true | 0.076 | 31.9 | 0 |
| Mieluna | sortieren | alle | Arbeiten aller Sorten | 0.0223 | 0 | 0.0456 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0223 | 37.8 |  |
| Mieluna | waschen | alle | Arbeiten aller Sorten | 0.0867 | 0.0668 | 0.1066 | 35 | 10 | 2026-09-24 | 2026-10-30 | true | 0.0867 | 45.7 | 0 |
| Mieluna | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0548 | 0.0352 | 0.0744 | 11 | 2 | 2026-10-01 | 2026-10-28 | false | 0.0548 | 29.8 | 0 |
| Orange Summer | sortieren | alle | Arbeiten aller Sorten | 0.0223 | 0 | 0.0456 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0223 | 37.8 |  |
| Orange Summer | waschen | alle | Arbeiten aller Sorten | 0.0867 | 0.0668 | 0.1066 | 35 | 10 | 2026-09-24 | 2026-10-30 | true | 0.0867 | 45.7 | 0 |
| Orange Summer | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0654 | 0.0248 | 0.106 | 5 | 1 | 2026-10-05 | 2026-10-28 | false | 0.0654 | 60.4 | 0 |
| Orangita | sortieren | alle | Arbeiten aller Sorten | 0.0223 | 0 | 0.0456 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0223 | 37.8 |  |
| Orangita | waschen | alle | Arbeiten aller Sorten | 0.0867 | 0.0668 | 0.1066 | 35 | 10 | 2026-09-24 | 2026-10-30 | true | 0.0867 | 45.7 | 0 |
| Orangita | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.1243 | 0.0435 | 0.2051 | 8 | 2 | 2026-09-23 | 2026-10-29 | false | 0.1243 | 46.5 | 0 |
| Tiana | sortieren | sorte | Arbeiten dieser Sorte | 0.0069 | 0 | 0.0138 | 4 | 2 | 2026-09-30 | 2026-10-09 | false | 0.0069 | 22.7 |  |
| Tiana | waschen | sorte | Arbeiten dieser Sorte | 0.0616 | 0.038 | 0.0853 | 11 | 3 | 2026-09-25 | 2026-10-28 | false | 0.0616 | 33.2 | 0 |
| Tiana | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0626 | 0.0479 | 0.0773 | 14 | 5 | 2026-09-23 | 2026-10-28 | false | 0.0626 | 17.2 | 0 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 601 | 477 | 112 | 107 | 107 | 112 | 97 | 49 | 0 | 19 | 5 | 9 | 0 | 39 | 38 | 0 | 0 | 0 | 270 | 270 | 103 | 103 | 4263 | 1354 | 1 | 477 | 477 | 73 | 12 | 19 | 5 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-31 | 696473.3 | 36 | 331639.4 | 331639.4 | 0 | 0 | 0 | 1502 | 2026-10-28 | 0 | 331639.32 | 419542.97 | 151315.33 | 66135.24 | 236495.46 | 68341.14 | 82974.21 | 0 | 0 | 18280 | 0 | 78351.65 | 260183.65 | 231915.85 | 9987.78 | 323403.21 | 47196.36 | 46473.15 | 0 | 0 | true | -191.85 | -0.0003 | 0.4762 | Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — bei einigen Chargen rund 46473 kg zu viel. Fast immer fehlt der Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine Lieferung ist der falschen Charge zugeordnet. |

