# Stand der Modelle

_Abzug vom 2026-11-08. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 07.11.2026, 12:03 (17 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 08.11.2026, 12:19 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0027 | 0.0019 | 0.0034 | 11 | Wiegungen dieser Sorte |
| Kaori Kuri | 0.0023 | 0.0019 | 0.0027 | 71 | Wiegungen dieser Sorte |
| Mieluna | 0.0019 | 0.0015 | 0.0022 | 56 | Wiegungen dieser Sorte |
| Amoro | 0.0037 | 0 | 0.008 | 6 | Wiegungen dieser Sorte |
| Butterkin | 0.0027 | 0.0022 | 0.0033 | 15 | Wiegungen dieser Sorte |
| Bolp 5110 | 0.0024 | 0.0022 | 0.0026 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0023 | 0.0022 | 0.0025 | 24 | Wiegungen dieser Sorte |
| Lekor | 0.0023 | 0.0008 | 0.0039 | 6 | Wiegungen dieser Sorte |
| Fictor | 0.005 | 0.0023 | 0.0078 | 5 | Wiegungen dieser Sorte |
| Tiana | 0.0024 | 0.0021 | 0.0028 | 52 | Wiegungen dieser Sorte |
| Ker Madec | 0.0024 | 0.0022 | 0.0026 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0183 | 0.0104 | 0.0261 | 25 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0026 | 0 | 0.0184 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0127 | 0.0076 | 0.0178 | 2 | alle Sorten (eigene: 2, gilt ab 3) |
| Butterkin | 0.0029 | 0 | 0.0069 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0127 | 0.0076 | 0.0178 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0392 | 0 | 0.0856 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0502 | 0.0169 | 0.0836 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0127 | 0.0076 | 0.0178 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Tiana | 0.0047 | 0 | 0.0123 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0127 | 0.0076 | 0.0178 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0009 | 0 | 0.0036 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0074 | 0.0023 | 0.0126 | 22 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0324 | 0.006 | 0.0587 | 12 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0645 | 0.0501 | 0.0789 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.1407 | 0.0929 | 0.1885 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0645 | 0.0501 | 0.0789 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0272 | 0 | 0.0759 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0656 | 0.022 | 0.1091 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0645 | 0.0501 | 0.0789 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Tiana | 0.0359 | 0.0209 | 0.0508 | 20 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0645 | 0.0501 | 0.0789 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen | mittel | lager_mittel | anstieg_je_woche |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle | Arbeiten aller Sorten | 0.0202 | 0.0018 | 0.0385 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0202 | 41 | 0 |
| Amoro | waschen | alle | Arbeiten aller Sorten | 0.089 | 0.0701 | 0.1079 | 37 | 10 | 2026-09-24 | 2026-11-03 | true | 0.089 | 46.6 | 0 |
| Amoro | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0771 | 0.061 | 0.0933 | 60 | 17 | 2026-09-21 | 2026-11-04 | true | 0.0771 | 32 | 0 |
| Butterkin | sortieren | alle | Arbeiten aller Sorten | 0.0202 | 0.0018 | 0.0385 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0202 | 41 | 0 |
| Butterkin | waschen | sorte | Arbeiten dieser Sorte | 0.1226 | 0.0564 | 0.1888 | 8 | 2 | 2026-09-26 | 2026-10-30 | false | 0.1226 | 44.7 | 0 |
| Butterkin | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0841 | 0.0509 | 0.1172 | 4 | 1 | 2026-09-22 | 2026-10-30 | false | 0.0841 | 36.5 | 0 |
| Fictor | sortieren | alle | Arbeiten aller Sorten | 0.0202 | 0.0018 | 0.0385 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0202 | 41 | 0 |
| Fictor | waschen | alle | Arbeiten aller Sorten | 0.089 | 0.0701 | 0.1079 | 37 | 10 | 2026-09-24 | 2026-11-03 | true | 0.089 | 46.6 | 0 |
| Fictor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0771 | 0.061 | 0.0933 | 60 | 17 | 2026-09-21 | 2026-11-04 | true | 0.0771 | 32 | 0 |
| Kaori Kuri | sortieren | alle | Arbeiten aller Sorten | 0.0202 | 0.0018 | 0.0385 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0202 | 41 | 0 |
| Kaori Kuri | waschen | sorte | Arbeiten dieser Sorte | 0.0908 | 0.0349 | 0.1466 | 9 | 3 | 2026-09-24 | 2026-10-30 | false | 0.0908 | 45.4 | 0 |
| Kaori Kuri | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0722 | 0.0425 | 0.1019 | 14 | 4 | 2026-09-21 | 2026-10-28 | false | 0.0722 | 31.3 | 0 |
| Ker Madec | sortieren | alle | Arbeiten aller Sorten | 0.0202 | 0.0018 | 0.0385 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0202 | 41 | 0 |
| Ker Madec | waschen | alle | Arbeiten aller Sorten | 0.089 | 0.0701 | 0.1079 | 37 | 10 | 2026-09-24 | 2026-11-03 | true | 0.089 | 46.6 | 0 |
| Ker Madec | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0771 | 0.061 | 0.0933 | 60 | 17 | 2026-09-21 | 2026-11-04 | true | 0.0771 | 32 | 0 |
| Lekor | sortieren | alle | Arbeiten aller Sorten | 0.0202 | 0.0018 | 0.0385 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0202 | 41 | 0 |
| Lekor | waschen | sorte | Arbeiten dieser Sorte | 0.102 | 0.0833 | 0.1207 | 5 | 1 | 2026-10-01 | 2026-10-30 | false | 0.102 | 85.9 | 0 |
| Lekor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0771 | 0.061 | 0.0933 | 60 | 17 | 2026-09-21 | 2026-11-04 | true | 0.0771 | 32 | 0 |
| Mieluna | sortieren | alle | Arbeiten aller Sorten | 0.0202 | 0.0018 | 0.0385 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0202 | 41 | 0 |
| Mieluna | waschen | alle | Arbeiten aller Sorten | 0.089 | 0.0701 | 0.1079 | 37 | 10 | 2026-09-24 | 2026-11-03 | true | 0.089 | 46.6 | 0 |
| Mieluna | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0597 | 0.0396 | 0.0798 | 12 | 2 | 2026-10-01 | 2026-11-02 | false | 0.0597 | 31.1 | 0 |
| Orange Summer | sortieren | alle | Arbeiten aller Sorten | 0.0202 | 0.0018 | 0.0385 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0202 | 41 | 0 |
| Orange Summer | waschen | sorte | Arbeiten dieser Sorte | 0.0774 | 0 | 0.1656 | 3 | 1 | 2026-10-17 | 2026-10-31 | false | 0.0774 | 67.3 | 0 |
| Orange Summer | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0654 | 0.0248 | 0.106 | 5 | 1 | 2026-10-05 | 2026-10-28 | false | 0.0654 | 60.4 | 0 |
| Orangita | sortieren | alle | Arbeiten aller Sorten | 0.0202 | 0.0018 | 0.0385 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0202 | 41 | 0 |
| Orangita | waschen | alle | Arbeiten aller Sorten | 0.089 | 0.0701 | 0.1079 | 37 | 10 | 2026-09-24 | 2026-11-03 | true | 0.089 | 46.6 | 0 |
| Orangita | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.1243 | 0.0435 | 0.2051 | 8 | 2 | 2026-09-23 | 2026-10-29 | false | 0.1243 | 46.5 | 0 |
| Tiana | sortieren | sorte | Arbeiten dieser Sorte | 0.0077 | 0.0029 | 0.0126 | 5 | 2 | 2026-09-30 | 2026-11-02 | false | 0.0077 | 30.6 | 0 |
| Tiana | waschen | sorte | Arbeiten dieser Sorte | 0.0695 | 0.0464 | 0.0926 | 12 | 3 | 2026-09-25 | 2026-11-03 | false | 0.0695 | 35.8 | 0 |
| Tiana | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0626 | 0.049 | 0.0762 | 15 | 5 | 2026-09-23 | 2026-11-04 | false | 0.0626 | 18.9 | 0 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 683 | 550 | 122 | 117 | 117 | 122 | 106 | 52 | 0 | 19 | 5 | 11 | 0 | 41 | 40 | 0 | 0 | 0 | 296 | 296 | 111 | 111 | 4559 | 1354 | 1 | 550 | 550 | 81 | 12 | 19 | 5 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-07 | 728344.14 | 36 | 426212.1 | 426212.1 | 0 | 0 | 0 | 1593 | 2026-11-05 | 0 | 426212.01 | 561924.79 | 202583.26 | 40024.57 | 365142.07 | 92699.4 | 109883.86 | 0 | 0 | 20837.21 | 0 | 83155.4 | 265930.62 | 235150.13 | 9943.28 | 322006.59 | 62499.36 | 155587.5 | 0 | 0 | true | -10794.25 | -0.0148 | 0.5852 | Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — bei einigen Chargen rund 155588 kg zu viel. Fast immer fehlt der Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine Lieferung ist der falschen Charge zugeordnet. |

