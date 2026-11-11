# Stand der Modelle

_Abzug vom 2026-11-11. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 11.11.2026, 09:17 (29 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 11.11.2026, 12:55 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0022 | 0.002 | 0.0025 | 12 | 12 Wiegungen dieser Sorte (zählen 80 %), dazu alle Sorten wie 3 Wiegungen |
| Kaori Kuri | 0.0023 | 0.0019 | 0.0027 | 70 | 70 Wiegungen dieser Sorte (zählen 96 %), dazu alle Sorten wie 3 Wiegungen |
| Mieluna | 0.0016 | 0.0015 | 0.0018 | 57 | 57 Wiegungen dieser Sorte (zählen 95 %), dazu alle Sorten wie 3 Wiegungen |
| Amoro | 0.0032 | 0.0006 | 0.0058 | 6 | 6 Wiegungen dieser Sorte (zählen 67 %), dazu alle Sorten wie 3 Wiegungen |
| Butterkin | 0.0028 | 0.0022 | 0.0033 | 18 | 18 Wiegungen dieser Sorte (zählen 86 %), dazu alle Sorten wie 3 Wiegungen |
| Bolp 5110 | 0.0023 | 0.0021 | 0.0024 | 0 | Wiegungen aller Sorten (diese Sorte hat keine) |
| Orange Summer | 0.0023 | 0.0022 | 0.0025 | 26 | 26 Wiegungen dieser Sorte (zählen 90 %), dazu alle Sorten wie 3 Wiegungen |
| Lekor | 0.0022 | 0.0014 | 0.0029 | 6 | 6 Wiegungen dieser Sorte (zählen 67 %), dazu alle Sorten wie 3 Wiegungen |
| Fictor | 0.004 | 0.0025 | 0.0055 | 5 | 5 Wiegungen dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Wiegungen |
| Tiana | 0.0023 | 0.0021 | 0.0026 | 51 | 51 Wiegungen dieser Sorte (zählen 94 %), dazu alle Sorten wie 3 Wiegungen |
| Ker Madec | 0.0023 | 0.0021 | 0.0024 | 0 | Wiegungen aller Sorten (diese Sorte hat keine) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0184 | 0.0106 | 0.0262 | 25 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0027 | 0 | 0.0186 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0128 | 0.0076 | 0.0179 | 2 | alle Sorten (eigene: 2, gilt ab 3) |
| Butterkin | 0.0029 | 0 | 0.0069 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0128 | 0.0076 | 0.0179 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.041 | 0 | 0.0861 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0503 | 0.017 | 0.0836 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0128 | 0.0076 | 0.0179 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Tiana | 0.0047 | 0 | 0.0123 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0128 | 0.0076 | 0.0179 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.001 | 0 | 0.0037 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0075 | 0.0024 | 0.0127 | 22 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.033 | 0.0065 | 0.0595 | 12 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0653 | 0.0508 | 0.0797 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.1421 | 0.0962 | 0.188 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0653 | 0.0508 | 0.0797 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0281 | 0 | 0.0774 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0656 | 0.0221 | 0.1091 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0653 | 0.0508 | 0.0797 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Tiana | 0.0362 | 0.0211 | 0.0512 | 20 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0653 | 0.0508 | 0.0797 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen | mittel | lager_mittel | anstieg_je_woche | vorwissen | anteil_sorte | anteil_alle | sd_arbeit | grund_roh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle | Arbeiten aller Sorten | 0.0201 | 0.0018 | 0.0384 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0201 | 41.1 | 0 | 3 | 0 | 0.0201 | 0.0272 | 0.0201 |
| Amoro | waschen | alle | Arbeiten aller Sorten | 0.089 | 0.0701 | 0.1079 | 37 | 10 | 2026-09-24 | 2026-11-03 | true | 0.089 | 46.6 | 0 | 3 | 0 | 0.089 | 0.0586 | 0.089 |
| Amoro | waschen_sortieren | sorte | 1 Arbeit dieser Sorte (zählt 25 %), dazu alle Sorten wie 3 Arbeiten | 0.0866 | 0 | 0.1873 | 1 | 1 | 2026-11-04 | 2026-11-04 | false | 0.107 | 13 | 0 | 3 | 0.107 | 0.0798 | 0.0633 | 0.0866 |
| Butterkin | sortieren | sorte | 1 Arbeit dieser Sorte (zählt 25 %), dazu alle Sorten wie 3 Arbeiten | 0.0207 | 0 | 0.064 | 1 | 1 | 2026-10-17 | 2026-10-17 | false | 0.0224 | 49.3 | 0 | 3 | 0.0224 | 0.0201 | 0.0272 | 0.0207 |
| Butterkin | waschen | sorte | 8 Arbeiten dieser Sorte (zählen 73 %), dazu alle Sorten wie 3 Arbeiten | 0.1134 | 0.074 | 0.1528 | 8 | 2 | 2026-09-26 | 2026-10-30 | false | 0.1226 | 44.7 | 0 | 3 | 0.1226 | 0.089 | 0.0586 | 0.1134 |
| Butterkin | waschen_sortieren | sorte | 4 Arbeiten dieser Sorte (zählen 57 %), dazu alle Sorten wie 3 Arbeiten | 0.0892 | 0.0306 | 0.1478 | 4 | 1 | 2026-09-22 | 2026-10-30 | false | 0.0962 | 34.4 | 0 | 3 | 0.0962 | 0.0798 | 0.0633 | 0.0892 |
| Fictor | sortieren | alle | Arbeiten aller Sorten | 0.0201 | 0.0018 | 0.0384 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0201 | 41.1 | 0 | 3 | 0 | 0.0201 | 0.0272 | 0.0201 |
| Fictor | waschen | alle | Arbeiten aller Sorten | 0.089 | 0.0701 | 0.1079 | 37 | 10 | 2026-09-24 | 2026-11-03 | true | 0.089 | 46.6 | 0 | 3 | 0 | 0.089 | 0.0586 | 0.089 |
| Fictor | waschen_sortieren | sorte | 1 Arbeit dieser Sorte (zählt 25 %), dazu alle Sorten wie 3 Arbeiten | 0.148 | 0.0472 | 0.2487 | 1 | 1 | 2026-10-01 | 2026-10-01 | false | 0.3524 | 9 | 0 | 3 | 0.3524 | 0.0798 | 0.0633 | 0.148 |
| Kaori Kuri | sortieren | sorte | 2 Arbeiten dieser Sorte (zählen 40 %), dazu alle Sorten wie 3 Arbeiten | 0.0347 | 0.001 | 0.0685 | 2 | 1 | 2026-09-23 | 2026-09-24 | false | 0.0567 | 41.4 | 0 | 3 | 0.0567 | 0.0201 | 0.0272 | 0.0347 |
| Kaori Kuri | waschen | sorte | 9 Arbeiten dieser Sorte (zählen 75 %), dazu alle Sorten wie 3 Arbeiten | 0.0903 | 0.0531 | 0.1276 | 9 | 3 | 2026-09-24 | 2026-10-30 | false | 0.0908 | 45.4 | 0 | 3 | 0.0908 | 0.089 | 0.0586 | 0.0903 |
| Kaori Kuri | waschen_sortieren | sorte | 14 Arbeiten dieser Sorte (zählen 82 %), dazu alle Sorten wie 3 Arbeiten | 0.075 | 0.0424 | 0.1075 | 14 | 4 | 2026-09-21 | 2026-10-28 | false | 0.0739 | 31.4 | 0 | 3 | 0.0739 | 0.0798 | 0.0633 | 0.075 |
| Ker Madec | sortieren | alle | Arbeiten aller Sorten | 0.0201 | 0.0018 | 0.0384 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0201 | 41.1 | 0 | 3 | 0 | 0.0201 | 0.0272 | 0.0201 |
| Ker Madec | waschen | alle | Arbeiten aller Sorten | 0.089 | 0.0701 | 0.1079 | 37 | 10 | 2026-09-24 | 2026-11-03 | true | 0.089 | 46.6 | 0 | 3 | 0 | 0.089 | 0.0586 | 0.089 |
| Ker Madec | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0798 | 0.0638 | 0.0958 | 60 | 17 | 2026-09-21 | 2026-11-04 | true | 0.0798 | 31.4 | 0 | 3 | 0 | 0.0798 | 0.0633 | 0.0798 |
| Lekor | sortieren | sorte | 2 Arbeiten dieser Sorte (zählen 40 %), dazu alle Sorten wie 3 Arbeiten | 0.0322 | 0 | 0.066 | 2 | 1 | 2026-10-10 | 2026-11-02 | false | 0.0504 | 76.9 | 0 | 3 | 0.0504 | 0.0201 | 0.0272 | 0.0322 |
| Lekor | waschen | sorte | 5 Arbeiten dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Arbeiten | 0.0971 | 0.0481 | 0.1461 | 5 | 1 | 2026-10-01 | 2026-10-30 | false | 0.102 | 85.9 | 0 | 3 | 0.102 | 0.089 | 0.0586 | 0.0971 |
| Lekor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0798 | 0.0638 | 0.0958 | 60 | 17 | 2026-09-21 | 2026-11-04 | true | 0.0798 | 31.4 | 0 | 3 | 0 | 0.0798 | 0.0633 | 0.0798 |
| Mieluna | sortieren | alle | Arbeiten aller Sorten | 0.0201 | 0.0018 | 0.0384 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0201 | 41.1 | 0 | 3 | 0 | 0.0201 | 0.0272 | 0.0201 |
| Mieluna | waschen | alle | Arbeiten aller Sorten | 0.089 | 0.0701 | 0.1079 | 37 | 10 | 2026-09-24 | 2026-11-03 | true | 0.089 | 46.6 | 0 | 3 | 0 | 0.089 | 0.0586 | 0.089 |
| Mieluna | waschen_sortieren | sorte | 12 Arbeiten dieser Sorte (zählen 80 %), dazu alle Sorten wie 3 Arbeiten | 0.0646 | 0.0295 | 0.0997 | 12 | 2 | 2026-10-01 | 2026-11-02 | false | 0.0608 | 30.8 | 0 | 3 | 0.0608 | 0.0798 | 0.0633 | 0.0646 |
| Orange Summer | sortieren | sorte | 1 Arbeit dieser Sorte (zählt 25 %), dazu alle Sorten wie 3 Arbeiten | 0.0158 | 0 | 0.059 | 1 | 1 | 2026-10-17 | 2026-10-17 | false | 0.0028 | 60 | 0 | 3 | 0.0028 | 0.0201 | 0.0272 | 0.0158 |
| Orange Summer | waschen | sorte | 3 Arbeiten dieser Sorte (zählen 50 %), dazu alle Sorten wie 3 Arbeiten | 0.0832 | 0.0216 | 0.1447 | 3 | 1 | 2026-10-17 | 2026-10-31 | false | 0.0774 | 67.3 | 0 | 3 | 0.0774 | 0.089 | 0.0586 | 0.0832 |
| Orange Summer | waschen_sortieren | sorte | 5 Arbeiten dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Arbeiten | 0.0726 | 0.0197 | 0.1256 | 5 | 1 | 2026-10-05 | 2026-10-28 | false | 0.0683 | 59.9 | 0 | 3 | 0.0683 | 0.0798 | 0.0633 | 0.0726 |
| Orangita | sortieren | alle | Arbeiten aller Sorten | 0.0201 | 0.0018 | 0.0384 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.0201 | 41.1 | 0 | 3 | 0 | 0.0201 | 0.0272 | 0.0201 |
| Orangita | waschen | alle | Arbeiten aller Sorten | 0.089 | 0.0701 | 0.1079 | 37 | 10 | 2026-09-24 | 2026-11-03 | true | 0.089 | 46.6 | 0 | 3 | 0 | 0.089 | 0.0586 | 0.089 |
| Orangita | waschen_sortieren | sorte | 8 Arbeiten dieser Sorte (zählen 73 %), dazu alle Sorten wie 3 Arbeiten | 0.117 | 0.0745 | 0.1595 | 8 | 2 | 2026-09-23 | 2026-10-29 | false | 0.131 | 45.7 | 0 | 3 | 0.131 | 0.0798 | 0.0633 | 0.117 |
| Tiana | sortieren | sorte | 5 Arbeiten dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Arbeiten | 0.0124 | 0 | 0.0351 | 5 | 2 | 2026-09-30 | 2026-11-02 | false | 0.0077 | 30.6 | 0 | 3 | 0.0077 | 0.0201 | 0.0272 | 0.0124 |
| Tiana | waschen | sorte | 12 Arbeiten dieser Sorte (zählen 80 %), dazu alle Sorten wie 3 Arbeiten | 0.0734 | 0.0409 | 0.1059 | 12 | 3 | 2026-09-25 | 2026-11-03 | false | 0.0695 | 35.8 | 0 | 3 | 0.0695 | 0.089 | 0.0586 | 0.0734 |
| Tiana | waschen_sortieren | sorte | 15 Arbeiten dieser Sorte (zählen 83 %), dazu alle Sorten wie 3 Arbeiten | 0.0667 | 0.0352 | 0.0982 | 15 | 5 | 2026-09-23 | 2026-11-04 | false | 0.0641 | 18.5 | 0 | 3 | 0.0641 | 0.0798 | 0.0633 | 0.0667 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 683 | 550 | 122 | 117 | 117 | 122 | 106 | 52 | 0 | 19 | 5 | 11 | 0 | 41 | 40 | 0 | 0 | 0 | 296 | 296 | 111 | 111 | 4559 | 1354 | 1 | 550 | 550 | 81 | 12 | 19 | 5 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | verschenkt_kg | leer_weg_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-11 | 728344.14 | 36 | 345661.4 | 345661.4 | 0 | 0 | 0 | 1942 | 2026-11-08 | 0 | 345661.34 | 438020.51 | 128369.26 | 35058.06 | 235940.22 | 69385.48 | 58983.8 | 0 | 0 | 18512.59 | 0 | 77302.86 | 264105.61 | 237033.31 | 8559.73 | 304517.07 | 62499.36 | 14193.68 | 0 | 0 | true | 0.25 | 4401.36 | 0 | 0 | 0.4746 | Bis heute (11.11.2026): 728.3 t Eingang = 350.1 t ausgeliefert + 128.4 t Verlust (Verdunstung 69.4 t, Faules 59.0 t, Fax 0.0 t) + 264.1 t noch im Haus (davon 237.0 t verkaufsfähig, 27.1 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. Im Ausgeliefert sind 4401 kg verschenkt: in den Kisten über dem Sollgewicht mitgegeben (gewogen), nicht verrechnet. 14194 kg Überzählung. |

