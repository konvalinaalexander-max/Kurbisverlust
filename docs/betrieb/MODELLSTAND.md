# Stand der Modelle

_Abzug vom 2026-10-13. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 13.10.2026, 11:03 (8 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 13.10.2026, 13:51 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0027 | 0.002 | 0.0035 | 8 | Wiegungen dieser Sorte |
| Kaori Kuri | 0.0037 | 0.0027 | 0.0047 | 9 | Wiegungen dieser Sorte |
| Mieluna | 0.0024 | 0.0016 | 0.0032 | 14 | Wiegungen dieser Sorte |
| Amoro | 0.0029 | 0.0027 | 0.0032 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.0038 | 0.0035 | 0.0042 | 6 | Wiegungen dieser Sorte |
| Bolp 5110 | 0.0029 | 0.0027 | 0.0032 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0024 | 0.0022 | 0.0026 | 11 | Wiegungen dieser Sorte |
| Lekor | 0.0029 | 0.0027 | 0.0032 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Fictor | 0.005 | 0.0023 | 0.0078 | 5 | Wiegungen dieser Sorte |
| Tiana | 0.0028 | 0.0024 | 0.0031 | 37 | Wiegungen dieser Sorte |
| Ker Madec | 0.0029 | 0.0027 | 0.0032 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0347 | 0.0201 | 0.0493 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0162 | 0.0072 | 0.0253 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Amoro | 0.0162 | 0.0072 | 0.0253 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Butterkin | 0.0162 | 0.0072 | 0.0253 | 2 | alle Sorten (eigene: 2, gilt ab 3) |
| Bolp 5110 | 0.0162 | 0.0072 | 0.0253 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0162 | 0.0072 | 0.0253 | 2 | alle Sorten (eigene: 2, gilt ab 3) |
| Lekor | 0.0162 | 0.0072 | 0.0253 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Fictor | 0.0162 | 0.0072 | 0.0253 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Tiana | 0.0028 | 0.0002 | 0.0054 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0162 | 0.0072 | 0.0253 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0081 | 0.0039 | 0.0123 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0364 | 0 | 0.0868 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0647 | 0.0454 | 0.0841 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.1359 | 0 | 0.2886 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0647 | 0.0454 | 0.0841 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.035 | 0 | 0.1159 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0647 | 0.0454 | 0.0841 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Fictor | 0.0647 | 0.0454 | 0.0841 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Tiana | 0.0384 | 0.0215 | 0.0553 | 13 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0647 | 0.0454 | 0.0841 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen | mittel | lager_mittel | anstieg_je_woche |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle | Arbeiten aller Sorten | 0.0252 | 0 | 0.0581 | 7 | 4 | 2026-09-23 | 2026-10-10 | true | 0.0252 | 33.1 |  |
| Amoro | waschen | alle | Arbeiten aller Sorten | 0.11 | 0.0673 | 0.1527 | 15 | 8 | 2026-09-24 | 2026-10-13 | true | 0.11 | 36.9 | 0 |
| Amoro | waschen_sortieren | alle | Arbeiten aller Sorten | 0.092 | 0.0614 | 0.1226 | 28 | 15 | 2026-09-21 | 2026-10-12 | true | 0.092 | 25 | 0 |
| Butterkin | sortieren | alle | Arbeiten aller Sorten | 0.0252 | 0 | 0.0581 | 7 | 4 | 2026-09-23 | 2026-10-10 | true | 0.0252 | 33.1 |  |
| Butterkin | waschen | sorte | Arbeiten dieser Sorte | 0.1463 | 0 | 0.3045 | 4 | 2 | 2026-09-26 | 2026-10-13 | false | 0.1463 | 37.8 | 0 |
| Butterkin | waschen_sortieren | alle | Arbeiten aller Sorten | 0.092 | 0.0614 | 0.1226 | 28 | 15 | 2026-09-21 | 2026-10-12 | true | 0.092 | 25 | 0 |
| Fictor | sortieren | alle | Arbeiten aller Sorten | 0.0252 | 0 | 0.0581 | 7 | 4 | 2026-09-23 | 2026-10-10 | true | 0.0252 | 33.1 |  |
| Fictor | waschen | alle | Arbeiten aller Sorten | 0.11 | 0.0673 | 0.1527 | 15 | 8 | 2026-09-24 | 2026-10-13 | true | 0.11 | 36.9 | 0 |
| Fictor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.092 | 0.0614 | 0.1226 | 28 | 15 | 2026-09-21 | 2026-10-12 | true | 0.092 | 25 | 0 |
| Kaori Kuri | sortieren | alle | Arbeiten aller Sorten | 0.0252 | 0 | 0.0581 | 7 | 4 | 2026-09-23 | 2026-10-10 | true | 0.0252 | 33.1 |  |
| Kaori Kuri | waschen | sorte | Arbeiten dieser Sorte | 0.1161 | 0.0327 | 0.1995 | 6 | 2 | 2026-09-24 | 2026-10-12 | false | 0.1161 | 45.2 | 0 |
| Kaori Kuri | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.091 | 0.0563 | 0.1258 | 6 | 3 | 2026-09-21 | 2026-10-12 | false | 0.091 | 26.3 | 0 |
| Ker Madec | sortieren | alle | Arbeiten aller Sorten | 0.0252 | 0 | 0.0581 | 7 | 4 | 2026-09-23 | 2026-10-10 | true | 0.0252 | 33.1 |  |
| Ker Madec | waschen | alle | Arbeiten aller Sorten | 0.11 | 0.0673 | 0.1527 | 15 | 8 | 2026-09-24 | 2026-10-13 | true | 0.11 | 36.9 | 0 |
| Ker Madec | waschen_sortieren | alle | Arbeiten aller Sorten | 0.092 | 0.0614 | 0.1226 | 28 | 15 | 2026-09-21 | 2026-10-12 | true | 0.092 | 25 | 0 |
| Lekor | sortieren | alle | Arbeiten aller Sorten | 0.0252 | 0 | 0.0581 | 7 | 4 | 2026-09-23 | 2026-10-10 | true | 0.0252 | 33.1 |  |
| Lekor | waschen | alle | Arbeiten aller Sorten | 0.11 | 0.0673 | 0.1527 | 15 | 8 | 2026-09-24 | 2026-10-13 | true | 0.11 | 36.9 | 0 |
| Lekor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.092 | 0.0614 | 0.1226 | 28 | 15 | 2026-09-21 | 2026-10-12 | true | 0.092 | 25 | 0 |
| Mieluna | sortieren | alle | Arbeiten aller Sorten | 0.0252 | 0 | 0.0581 | 7 | 4 | 2026-09-23 | 2026-10-10 | true | 0.0252 | 33.1 |  |
| Mieluna | waschen | alle | Arbeiten aller Sorten | 0.11 | 0.0673 | 0.1527 | 15 | 8 | 2026-09-24 | 2026-10-13 | true | 0.11 | 36.9 | 0 |
| Mieluna | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.078 | 0.0092 | 0.1468 | 3 | 2 | 2026-10-01 | 2026-10-05 | false | 0.078 | 18.2 | 0 |
| Orange Summer | sortieren | alle | Arbeiten aller Sorten | 0.0252 | 0 | 0.0581 | 7 | 4 | 2026-09-23 | 2026-10-10 | true | 0.0252 | 33.1 |  |
| Orange Summer | waschen | alle | Arbeiten aller Sorten | 0.11 | 0.0673 | 0.1527 | 15 | 8 | 2026-09-24 | 2026-10-13 | true | 0.11 | 36.9 | 0 |
| Orange Summer | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.054 | 0.0063 | 0.1018 | 3 | 1 | 2026-10-05 | 2026-10-10 | false | 0.054 | 49.4 | 0 |
| Orangita | sortieren | alle | Arbeiten aller Sorten | 0.0252 | 0 | 0.0581 | 7 | 4 | 2026-09-23 | 2026-10-10 | true | 0.0252 | 33.1 |  |
| Orangita | waschen | alle | Arbeiten aller Sorten | 0.11 | 0.0673 | 0.1527 | 15 | 8 | 2026-09-24 | 2026-10-13 | true | 0.11 | 36.9 | 0 |
| Orangita | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.1348 | 0.0035 | 0.2661 | 5 | 2 | 2026-09-23 | 2026-10-12 | false | 0.1348 | 38.9 | 0 |
| Tiana | sortieren | sorte | Arbeiten dieser Sorte | 0.0069 | 0 | 0.0139 | 4 | 2 | 2026-09-30 | 2026-10-09 | false | 0.0069 | 22.7 |  |
| Tiana | waschen | sorte | Arbeiten dieser Sorte | 0.0695 | 0 | 0.1533 | 4 | 3 | 2026-09-25 | 2026-10-12 | false | 0.0695 | 22.9 | 0 |
| Tiana | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0642 | 0.0427 | 0.0857 | 9 | 5 | 2026-09-23 | 2026-10-12 | false | 0.0642 | 19.2 | 0 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 334 | 283 | 52 | 50 | 50 | 52 | 42 | 26 | 0 | 12 | 0 | 7 | 0 | 16 | 15 | 0 | 0 | 0 | 125 | 125 | 45 | 45 | 1753 | 540 | 1 | 283 | 283 | 36 | 0 | 12 | 0 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-13 | 656518.64 | 31 | 209718.2 | 209718.2 | 0 | 0 | 0 | 1131 | 2026-10-13 | 0 | 208126.15 | 267667.02 | 114605.61 | 35528.94 | 252613.69 | 60365.64 | 54239.96 | 0 | 0 | 16965.64 | 0 | 110800.23 | 345018.55 | 307423.44 | 20629.48 | 400083.3 | 51491.19 | 11231.87 | 0 | 0 | true | 0.2 | 0 | 0.3194 | Bis heute (13.10.2026): 656.5 t Eingang = 208.1 t ausgeliefert + 114.6 t Verlust (Verdunstung 60.4 t, Faules 54.2 t, Fax 0.0 t) + 345.0 t noch im Haus (davon 307.4 t verkaufsfähig, 37.6 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. 11232 kg Überzählung. |

