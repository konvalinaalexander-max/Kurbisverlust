# Stand der Modelle

_Abzug vom 2026-11-14. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 14.11.2026, 09:29 (23 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 14.11.2026, 12:32 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Amoro | 0.003 | 0.0011 | 0.0049 | 9 | 9 Wiegungen dieser Sorte (zählen 75 %), dazu alle Sorten wie 3 Wiegungen |
| Mieluna | 0.0015 | 0.0013 | 0.0016 | 74 | 74 Wiegungen dieser Sorte (zählen 96 %), dazu alle Sorten wie 3 Wiegungen |
| Kaori Kuri | 0.0023 | 0.0019 | 0.0026 | 75 | 75 Wiegungen dieser Sorte (zählen 96 %), dazu alle Sorten wie 3 Wiegungen |
| Butterkin | 0.0024 | 0.002 | 0.0028 | 28 | 28 Wiegungen dieser Sorte (zählen 90 %), dazu alle Sorten wie 3 Wiegungen |
| Orangita | 0.0022 | 0.002 | 0.0024 | 12 | 12 Wiegungen dieser Sorte (zählen 80 %), dazu alle Sorten wie 3 Wiegungen |
| Bolp 5110 | 0.0021 | 0.002 | 0.0023 | 0 | Wiegungen aller Sorten (diese Sorte hat keine) |
| Orange Summer | 0.0023 | 0.0022 | 0.0025 | 28 | 28 Wiegungen dieser Sorte (zählen 90 %), dazu alle Sorten wie 3 Wiegungen |
| Lekor | 0.0021 | 0.0013 | 0.0029 | 6 | 6 Wiegungen dieser Sorte (zählen 67 %), dazu alle Sorten wie 3 Wiegungen |
| Fictor | 0.004 | 0.0025 | 0.0054 | 5 | 5 Wiegungen dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Wiegungen |
| Tiana | 0.0023 | 0.002 | 0.0025 | 56 | 56 Wiegungen dieser Sorte (zählen 95 %), dazu alle Sorten wie 3 Wiegungen |
| Ker Madec | 0.0021 | 0.002 | 0.0023 | 0 | Wiegungen aller Sorten (diese Sorte hat keine) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Butterkin | 0.003 | 0.0005 | 0.0054 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0261 | 0 | 0.1374 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0025 | 0 | 0.0117 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0126 | 0.0078 | 0.0175 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Kaori Kuri | 0.0179 | 0.0104 | 0.0253 | 27 | Sortierläufe/Handmessungen dieser Sorte |
| Orange Summer | 0.0395 | 0.0044 | 0.0746 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0502 | 0.0169 | 0.0836 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0126 | 0.0078 | 0.0175 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Tiana | 0.0047 | 0 | 0.0123 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0126 | 0.0078 | 0.0175 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Amoro | 0.0632 | 0.0498 | 0.0766 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Mieluna | 0.0323 | 0.0125 | 0.052 | 16 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0073 | 0.0024 | 0.0122 | 24 | Sortierläufe/Handmessungen dieser Sorte |
| Butterkin | 0.1391 | 0.0946 | 0.1835 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Orangita | 0.001 | 0 | 0.0037 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0632 | 0.0498 | 0.0766 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0274 | 0 | 0.071 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0656 | 0.022 | 0.1091 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0632 | 0.0498 | 0.0766 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Tiana | 0.0357 | 0.0215 | 0.0498 | 22 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0632 | 0.0498 | 0.0766 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen | mittel | lager_mittel | anstieg_je_woche | vorwissen | anteil_sorte | anteil_alle | sd_arbeit | grund_roh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle | Arbeiten aller Sorten | 0.02 | 0.0018 | 0.0383 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.02 | 41.1 | 0 | 3 | 0 | 0.02 | 0.0271 | 0.02 |
| Amoro | waschen | alle | Arbeiten aller Sorten | 0.0941 | 0.076 | 0.1122 | 42 | 10 | 2026-09-24 | 2026-11-13 | true | 0.0941 | 49.7 | 0 | 3 | 0 | 0.0941 | 0.0599 | 0.0941 |
| Amoro | waschen_sortieren | sorte | 2 Arbeiten dieser Sorte (zählen 40 %), dazu alle Sorten wie 3 Arbeiten | 0.1012 | 0.014 | 0.1885 | 2 | 1 | 2026-11-04 | 2026-11-12 | false | 0.1287 | 15.7 | 0 | 3 | 0.1287 | 0.0829 | 0.0703 | 0.1012 |
| Butterkin | sortieren | sorte | 1 Arbeit dieser Sorte (zählt 25 %), dazu alle Sorten wie 3 Arbeiten | 0.0205 | 0 | 0.0637 | 1 | 1 | 2026-10-17 | 2026-10-17 | false | 0.022 | 49.3 | 0 | 3 | 0.022 | 0.02 | 0.0271 | 0.0205 |
| Butterkin | waschen | sorte | 10 Arbeiten dieser Sorte (zählen 77 %), dazu alle Sorten wie 3 Arbeiten | 0.1297 | 0.0936 | 0.1659 | 10 | 2 | 2026-09-26 | 2026-11-12 | false | 0.1404 | 51.4 | 0 | 3 | 0.1404 | 0.0941 | 0.0599 | 0.1297 |
| Butterkin | waschen_sortieren | sorte | 6 Arbeiten dieser Sorte (zählen 67 %), dazu alle Sorten wie 3 Arbeiten | 0.0762 | 0.0222 | 0.1302 | 6 | 1 | 2026-09-22 | 2026-11-12 | false | 0.0728 | 45.3 | 0 | 3 | 0.0728 | 0.0829 | 0.0703 | 0.0762 |
| Fictor | sortieren | alle | Arbeiten aller Sorten | 0.02 | 0.0018 | 0.0383 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.02 | 41.1 | 0 | 3 | 0 | 0.02 | 0.0271 | 0.02 |
| Fictor | waschen | alle | Arbeiten aller Sorten | 0.0941 | 0.076 | 0.1122 | 42 | 10 | 2026-09-24 | 2026-11-13 | true | 0.0941 | 49.7 | 0 | 3 | 0 | 0.0941 | 0.0599 | 0.0941 |
| Fictor | waschen_sortieren | sorte | 1 Arbeit dieser Sorte (zählt 25 %), dazu alle Sorten wie 3 Arbeiten | 0.1503 | 0.0384 | 0.2621 | 1 | 1 | 2026-10-01 | 2026-10-01 | false | 0.3523 | 9 | 0 | 3 | 0.3523 | 0.0829 | 0.0703 | 0.1503 |
| Kaori Kuri | sortieren | sorte | 2 Arbeiten dieser Sorte (zählen 40 %), dazu alle Sorten wie 3 Arbeiten | 0.0347 | 0.001 | 0.0683 | 2 | 1 | 2026-09-23 | 2026-09-24 | false | 0.0566 | 41.4 | 0 | 3 | 0.0566 | 0.02 | 0.0271 | 0.0347 |
| Kaori Kuri | waschen | sorte | 9 Arbeiten dieser Sorte (zählen 75 %), dazu alle Sorten wie 3 Arbeiten | 0.0916 | 0.0536 | 0.1296 | 9 | 3 | 2026-09-24 | 2026-10-30 | false | 0.0908 | 45.4 | 0 | 3 | 0.0908 | 0.0941 | 0.0599 | 0.0916 |
| Kaori Kuri | waschen_sortieren | sorte | 14 Arbeiten dieser Sorte (zählen 82 %), dazu alle Sorten wie 3 Arbeiten | 0.0754 | 0.0392 | 0.1115 | 14 | 4 | 2026-09-21 | 2026-10-28 | false | 0.0738 | 31.5 | 0 | 3 | 0.0738 | 0.0829 | 0.0703 | 0.0754 |
| Ker Madec | sortieren | alle | Arbeiten aller Sorten | 0.02 | 0.0018 | 0.0383 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.02 | 41.1 | 0 | 3 | 0 | 0.02 | 0.0271 | 0.02 |
| Ker Madec | waschen | alle | Arbeiten aller Sorten | 0.0941 | 0.076 | 0.1122 | 42 | 10 | 2026-09-24 | 2026-11-13 | true | 0.0941 | 49.7 | 0 | 3 | 0 | 0.0941 | 0.0599 | 0.0941 |
| Ker Madec | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0829 | 0.0665 | 0.0994 | 70 | 17 | 2026-09-21 | 2026-11-13 | true | 0.0829 | 34.8 | 0 | 3 | 0 | 0.0829 | 0.0703 | 0.0829 |
| Lekor | sortieren | sorte | 2 Arbeiten dieser Sorte (zählen 40 %), dazu alle Sorten wie 3 Arbeiten | 0.0321 | 0 | 0.0658 | 2 | 1 | 2026-10-10 | 2026-11-02 | false | 0.0503 | 77 | 0 | 3 | 0.0503 | 0.02 | 0.0271 | 0.0321 |
| Lekor | waschen | sorte | 5 Arbeiten dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Arbeiten | 0.099 | 0.049 | 0.1491 | 5 | 1 | 2026-10-01 | 2026-10-30 | false | 0.102 | 85.9 | 0 | 3 | 0.102 | 0.0941 | 0.0599 | 0.099 |
| Lekor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0829 | 0.0665 | 0.0994 | 70 | 17 | 2026-09-21 | 2026-11-13 | true | 0.0829 | 34.8 | 0 | 3 | 0 | 0.0829 | 0.0703 | 0.0829 |
| Mieluna | sortieren | alle | Arbeiten aller Sorten | 0.02 | 0.0018 | 0.0383 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.02 | 41.1 | 0 | 3 | 0 | 0.02 | 0.0271 | 0.02 |
| Mieluna | waschen | alle | Arbeiten aller Sorten | 0.0941 | 0.076 | 0.1122 | 42 | 10 | 2026-09-24 | 2026-11-13 | true | 0.0941 | 49.7 | 0 | 3 | 0 | 0.0941 | 0.0599 | 0.0941 |
| Mieluna | waschen_sortieren | sorte | 16 Arbeiten dieser Sorte (zählen 84 %), dazu alle Sorten wie 3 Arbeiten | 0.0708 | 0.0369 | 0.1047 | 16 | 2 | 2026-10-01 | 2026-11-13 | false | 0.0686 | 36.1 | 0 | 3 | 0.0686 | 0.0829 | 0.0703 | 0.0708 |
| Orange Summer | sortieren | sorte | 1 Arbeit dieser Sorte (zählt 25 %), dazu alle Sorten wie 3 Arbeiten | 0.0157 | 0 | 0.0589 | 1 | 1 | 2026-10-17 | 2026-10-17 | false | 0.0028 | 60 | 0 | 3 | 0.0028 | 0.02 | 0.0271 | 0.0157 |
| Orange Summer | waschen | sorte | 4 Arbeiten dieser Sorte (zählen 57 %), dazu alle Sorten wie 3 Arbeiten | 0.0884 | 0.033 | 0.1437 | 4 | 1 | 2026-10-17 | 2026-11-13 | false | 0.0841 | 73 | 0 | 3 | 0.0841 | 0.0941 | 0.0599 | 0.0884 |
| Orange Summer | waschen_sortieren | sorte | 6 Arbeiten dieser Sorte (zählen 67 %), dazu alle Sorten wie 3 Arbeiten | 0.0835 | 0.0294 | 0.1375 | 6 | 1 | 2026-10-05 | 2026-11-13 | false | 0.0838 | 61.8 | 0 | 3 | 0.0838 | 0.0829 | 0.0703 | 0.0835 |
| Orangita | sortieren | alle | Arbeiten aller Sorten | 0.02 | 0.0018 | 0.0383 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.02 | 41.1 | 0 | 3 | 0 | 0.02 | 0.0271 | 0.02 |
| Orangita | waschen | alle | Arbeiten aller Sorten | 0.0941 | 0.076 | 0.1122 | 42 | 10 | 2026-09-24 | 2026-11-13 | true | 0.0941 | 49.7 | 0 | 3 | 0 | 0.0941 | 0.0599 | 0.0941 |
| Orangita | waschen_sortieren | sorte | 8 Arbeiten dieser Sorte (zählen 73 %), dazu alle Sorten wie 3 Arbeiten | 0.1178 | 0.0705 | 0.165 | 8 | 2 | 2026-09-23 | 2026-10-29 | false | 0.1308 | 45.7 | 0 | 3 | 0.1308 | 0.0829 | 0.0703 | 0.1178 |
| Tiana | sortieren | sorte | 5 Arbeiten dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Arbeiten | 0.0123 | 0 | 0.035 | 5 | 2 | 2026-09-30 | 2026-11-02 | false | 0.0077 | 30.6 | 0 | 3 | 0.0077 | 0.02 | 0.0271 | 0.0123 |
| Tiana | waschen | sorte | 14 Arbeiten dieser Sorte (zählen 82 %), dazu alle Sorten wie 3 Arbeiten | 0.0745 | 0.0438 | 0.1053 | 14 | 3 | 2026-09-25 | 2026-11-13 | false | 0.0703 | 39.3 | 0 | 3 | 0.0703 | 0.0941 | 0.0599 | 0.0745 |
| Tiana | waschen_sortieren | sorte | 17 Arbeiten dieser Sorte (zählen 85 %), dazu alle Sorten wie 3 Arbeiten | 0.0736 | 0.0407 | 0.1065 | 17 | 5 | 2026-09-23 | 2026-11-12 | false | 0.0719 | 21.1 | 0 | 3 | 0.0719 | 0.0829 | 0.0703 | 0.0736 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 743 | 592 | 140 | 134 | 134 | 140 | 123 | 61 | 0 | 19 | 5 | 11 | 0 | 47 | 46 | 0 | 0 | 0 | 338 | 338 | 129 | 129 | 5215 | 1426 | 1 | 592 | 592 | 93 | 12 | 19 | 5 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | verschenkt_kg | leer_weg_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-14 | 739206.14 | 37 | 363530.2 | 363530.2 | 0 | 0 | 0 | 2086 | 2026-11-13 | 0 | 363464.04 | 460967.48 | 128578.29 | 37059.42 | 236747.85 | 67185.19 | 61393.14 | 0 | 0 | 19429.24 | 0 | 79956.1 | 253313.09 | 225330.21 | 8553.62 | 289253.62 | 59103.14 | 11015.18 | 0 | 0 | true | 0.23 | 4865.67 | 0 | 0 | 0.4918 | Bis heute (14.11.2026): 739.2 t Eingang = 368.3 t ausgeliefert + 128.6 t Verlust (Verdunstung 67.2 t, Faules 61.4 t, Fax 0.0 t) + 253.3 t noch im Haus (davon 225.3 t verkaufsfähig, 28.0 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. Im Ausgeliefert sind 4866 kg verschenkt: in den Kisten über dem Sollgewicht mitgegeben (gewogen), nicht verrechnet. 11015 kg Überzählung. |

