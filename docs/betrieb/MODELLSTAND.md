# Stand der Modelle

_Abzug vom 2026-10-22. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 22.10.2026, 11:26 (14 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 22.10.2026, 11:26 · succeeded · 13.8 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0025 | 0.0018 | 0.0033 | 9 | Wiegungen dieser Sorte |
| Kaori Kuri | 0.0043 | 0.0031 | 0.0056 | 17 | Wiegungen dieser Sorte |
| Mieluna | 0.0018 | 0.0015 | 0.0022 | 42 | Wiegungen dieser Sorte |
| Amoro | 0.0027 | 0.0024 | 0.003 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.0038 | 0.0035 | 0.0042 | 6 | Wiegungen dieser Sorte |
| Bolp 5110 | 0.0027 | 0.0024 | 0.003 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0024 | 0.0022 | 0.0027 | 17 | Wiegungen dieser Sorte |
| Lekor | 0.0027 | 0.0024 | 0.003 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Fictor | 0.005 | 0.0023 | 0.0078 | 5 | Wiegungen dieser Sorte |
| Tiana | 0.0026 | 0.0023 | 0.003 | 42 | Wiegungen dieser Sorte |
| Ker Madec | 0.0027 | 0.0024 | 0.003 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0266 | 0.016 | 0.0371 | 14 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0026 | 0 | 0.0184 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.013 | 0.0069 | 0.0191 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Butterkin | 0.0029 | 0 | 0.0069 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.013 | 0.0069 | 0.0191 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0466 | 0 | 0.1203 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.013 | 0.0069 | 0.0191 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Fictor | 0.013 | 0.0069 | 0.0191 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Tiana | 0.0034 | 0.0006 | 0.0062 | 6 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.013 | 0.0069 | 0.0191 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0012 | 0 | 0.0052 | 6 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0107 | 0.0028 | 0.0186 | 13 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0271 | 0 | 0.0612 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0731 | 0.0556 | 0.0906 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.1468 | 0.074 | 0.2197 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0731 | 0.0556 | 0.0906 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0316 | 0 | 0.0919 | 6 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0731 | 0.0556 | 0.0906 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Fictor | 0.0731 | 0.0556 | 0.0906 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Tiana | 0.0372 | 0.0206 | 0.0537 | 17 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0731 | 0.0556 | 0.0906 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen | mittel | lager_mittel | anstieg_je_woche |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Amoro | waschen | alle | Arbeiten aller Sorten | 0.0912 | 0.0602 | 0.1223 | 23 | 9 | 2026-09-24 | 2026-10-19 | true | 0.0912 | 39.3 | 0 |
| Amoro | waschen_sortieren | alle | Arbeiten aller Sorten | 0.075 | 0.0532 | 0.0968 | 40 | 15 | 2026-09-21 | 2026-10-22 | true | 0.075 | 29 | 0 |
| Butterkin | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Butterkin | waschen | sorte | Arbeiten dieser Sorte | 0.1372 | 0.0494 | 0.2249 | 6 | 2 | 2026-09-26 | 2026-10-19 | false | 0.1372 | 40.3 | 0 |
| Butterkin | waschen_sortieren | alle | Arbeiten aller Sorten | 0.075 | 0.0532 | 0.0968 | 40 | 15 | 2026-09-21 | 2026-10-22 | true | 0.075 | 29 | 0 |
| Fictor | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Fictor | waschen | alle | Arbeiten aller Sorten | 0.0912 | 0.0602 | 0.1223 | 23 | 9 | 2026-09-24 | 2026-10-19 | true | 0.0912 | 39.3 | 0 |
| Fictor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.075 | 0.0532 | 0.0968 | 40 | 15 | 2026-09-21 | 2026-10-22 | true | 0.075 | 29 | 0 |
| Kaori Kuri | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Kaori Kuri | waschen | sorte | Arbeiten dieser Sorte | 0.0973 | 0.0245 | 0.1701 | 7 | 2 | 2026-09-24 | 2026-10-16 | false | 0.0973 | 50.3 | 0 |
| Kaori Kuri | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0714 | 0.045 | 0.0978 | 9 | 3 | 2026-09-21 | 2026-10-21 | false | 0.0714 | 32.3 | 0 |
| Ker Madec | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Ker Madec | waschen | alle | Arbeiten aller Sorten | 0.0912 | 0.0602 | 0.1223 | 23 | 9 | 2026-09-24 | 2026-10-19 | true | 0.0912 | 39.3 | 0 |
| Ker Madec | waschen_sortieren | alle | Arbeiten aller Sorten | 0.075 | 0.0532 | 0.0968 | 40 | 15 | 2026-09-21 | 2026-10-22 | true | 0.075 | 29 | 0 |
| Lekor | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Lekor | waschen | alle | Arbeiten aller Sorten | 0.0912 | 0.0602 | 0.1223 | 23 | 9 | 2026-09-24 | 2026-10-19 | true | 0.0912 | 39.3 | 0 |
| Lekor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.075 | 0.0532 | 0.0968 | 40 | 15 | 2026-09-21 | 2026-10-22 | true | 0.075 | 29 | 0 |
| Mieluna | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Mieluna | waschen | alle | Arbeiten aller Sorten | 0.0912 | 0.0602 | 0.1223 | 23 | 9 | 2026-09-24 | 2026-10-19 | true | 0.0912 | 39.3 | 0 |
| Mieluna | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0474 | 0.0264 | 0.0683 | 8 | 2 | 2026-10-01 | 2026-10-21 | false | 0.0474 | 28 | 0 |
| Orange Summer | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Orange Summer | waschen | alle | Arbeiten aller Sorten | 0.0912 | 0.0602 | 0.1223 | 23 | 9 | 2026-09-24 | 2026-10-19 | true | 0.0912 | 39.3 | 0 |
| Orange Summer | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0491 | 0.022 | 0.0763 | 4 | 1 | 2026-10-05 | 2026-10-21 | false | 0.0491 | 54.1 | 0 |
| Orangita | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Orangita | waschen | alle | Arbeiten aller Sorten | 0.0912 | 0.0602 | 0.1223 | 23 | 9 | 2026-09-24 | 2026-10-19 | true | 0.0912 | 39.3 | 0 |
| Orangita | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.1311 | 0.0297 | 0.2324 | 6 | 2 | 2026-09-23 | 2026-10-22 | false | 0.1311 | 41 | 0 |
| Tiana | sortieren | sorte | Arbeiten dieser Sorte | 0.0069 | 0 | 0.0139 | 4 | 2 | 2026-09-30 | 2026-10-09 | false | 0.0069 | 22.7 |  |
| Tiana | waschen | sorte | Arbeiten dieser Sorte | 0.0563 | 0.0214 | 0.0912 | 8 | 3 | 2026-09-25 | 2026-10-16 | false | 0.0563 | 27 | 0 |
| Tiana | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0658 | 0.0485 | 0.0832 | 11 | 5 | 2026-09-23 | 2026-10-21 | false | 0.0658 | 19.3 | 0 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 466 | 383 | 76 | 72 | 72 | 76 | 61 | 33 | 0 | 19 | 5 | 9 | 0 | 26 | 25 | 0 | 0 | 0 | 176 | 176 | 67 | 67 | 2879 | 1354 | 1 | 383 | 383 | 50 | 2 | 19 | 5 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-22 | 688197.58 | 34 | 243205.6 | 243205.6 | 0 | 0 | 0 | 1317 | 2026-10-21 | 0 | 241789.53 | 315179.21 | 157318.28 | 45846.82 | 268789.7 | 70662.42 | 86655.88 | 0 | 0 | 15392.64 | 0 | 76771.12 | 307927.53 | 281019.29 | 11515.6 | 390895.18 | 56509.72 | 17877.08 | 0 | 0 | true | -960.68 | -0.0014 | 0.3534 | Bis heute (22.10.2026): 688.2 t Eingang = 241.8 t ausgeliefert + 157.3 t Verlust (Verdunstung 70.7 t, Faules 86.7 t, Fax 0.0 t) + 307.9 t noch im Haus (davon 281.0 t verkaufsfähig, 26.9 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. 17877 kg Überzählung. |

