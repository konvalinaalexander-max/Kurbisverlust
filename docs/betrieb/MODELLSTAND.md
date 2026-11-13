# Stand der Modelle

_Abzug vom 2026-11-13. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 12.11.2026, 16:15 (28 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 13.11.2026, 13:16 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0022 | 0.002 | 0.0024 | 12 | 12 Wiegungen dieser Sorte (zählen 80 %), dazu alle Sorten wie 3 Wiegungen |
| Orange Summer | 0.0023 | 0.0022 | 0.0025 | 26 | 26 Wiegungen dieser Sorte (zählen 90 %), dazu alle Sorten wie 3 Wiegungen |
| Bolp 5110 | 0.0022 | 0.002 | 0.0023 | 0 | Wiegungen aller Sorten (diese Sorte hat keine) |
| Butterkin | 0.0024 | 0.002 | 0.0028 | 28 | 28 Wiegungen dieser Sorte (zählen 90 %), dazu alle Sorten wie 3 Wiegungen |
| Amoro | 0.003 | 0.0011 | 0.0049 | 9 | 9 Wiegungen dieser Sorte (zählen 75 %), dazu alle Sorten wie 3 Wiegungen |
| Mieluna | 0.0015 | 0.0013 | 0.0016 | 72 | 72 Wiegungen dieser Sorte (zählen 96 %), dazu alle Sorten wie 3 Wiegungen |
| Lekor | 0.0021 | 0.0013 | 0.0029 | 6 | 6 Wiegungen dieser Sorte (zählen 67 %), dazu alle Sorten wie 3 Wiegungen |
| Kaori Kuri | 0.0023 | 0.0019 | 0.0027 | 70 | 70 Wiegungen dieser Sorte (zählen 96 %), dazu alle Sorten wie 3 Wiegungen |
| Fictor | 0.004 | 0.0025 | 0.0054 | 5 | 5 Wiegungen dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Wiegungen |
| Tiana | 0.0023 | 0.002 | 0.0025 | 56 | 56 Wiegungen dieser Sorte (zählen 95 %), dazu alle Sorten wie 3 Wiegungen |
| Ker Madec | 0.0022 | 0.002 | 0.0023 | 0 | Wiegungen aller Sorten (diese Sorte hat keine) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0184 | 0.0106 | 0.0262 | 25 | Sortierläufe/Handmessungen dieser Sorte |
| Orange Summer | 0.0409 | 0 | 0.086 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0127 | 0.0078 | 0.0177 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.003 | 0.0005 | 0.0054 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0261 | 0 | 0.1374 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0502 | 0.0169 | 0.0836 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0025 | 0 | 0.0117 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0127 | 0.0078 | 0.0177 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Tiana | 0.0047 | 0 | 0.0123 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0127 | 0.0078 | 0.0177 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.001 | 0 | 0.0037 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Orange Summer | 0.0281 | 0 | 0.0773 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0637 | 0.05 | 0.0774 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.1391 | 0.0946 | 0.1835 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0637 | 0.05 | 0.0774 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Mieluna | 0.0314 | 0.0108 | 0.052 | 15 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0656 | 0.0221 | 0.1091 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0075 | 0.0024 | 0.0127 | 22 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0637 | 0.05 | 0.0774 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Tiana | 0.0357 | 0.0215 | 0.0498 | 22 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0637 | 0.05 | 0.0774 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen | mittel | lager_mittel | anstieg_je_woche | vorwissen | anteil_sorte | anteil_alle | sd_arbeit | grund_roh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle | Arbeiten aller Sorten | 0.02 | 0.0018 | 0.0383 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.02 | 41.1 | 0 | 3 | 0 | 0.02 | 0.0272 | 0.02 |
| Amoro | waschen | alle | Arbeiten aller Sorten | 0.0947 | 0.0757 | 0.1136 | 40 | 10 | 2026-09-24 | 2026-11-12 | true | 0.0947 | 48.6 | 0 | 3 | 0 | 0.0947 | 0.0611 | 0.0947 |
| Amoro | waschen_sortieren | sorte | 2 Arbeiten dieser Sorte (zählen 40 %), dazu alle Sorten wie 3 Arbeiten | 0.1003 | 0.0213 | 0.1793 | 2 | 1 | 2026-11-04 | 2026-11-12 | false | 0.1287 | 15.7 | 0 | 3 | 0.1287 | 0.0814 | 0.0636 | 0.1003 |
| Butterkin | sortieren | sorte | 1 Arbeit dieser Sorte (zählt 25 %), dazu alle Sorten wie 3 Arbeiten | 0.0205 | 0 | 0.0638 | 1 | 1 | 2026-10-17 | 2026-10-17 | false | 0.022 | 49.3 | 0 | 3 | 0.022 | 0.02 | 0.0272 | 0.0205 |
| Butterkin | waschen | sorte | 10 Arbeiten dieser Sorte (zählen 77 %), dazu alle Sorten wie 3 Arbeiten | 0.1299 | 0.0929 | 0.1668 | 10 | 2 | 2026-09-26 | 2026-11-12 | false | 0.1404 | 51.4 | 0 | 3 | 0.1404 | 0.0947 | 0.0611 | 0.1299 |
| Butterkin | waschen_sortieren | sorte | 6 Arbeiten dieser Sorte (zählen 67 %), dazu alle Sorten wie 3 Arbeiten | 0.0757 | 0.0268 | 0.1246 | 6 | 1 | 2026-09-22 | 2026-11-12 | false | 0.0729 | 45.3 | 0 | 3 | 0.0729 | 0.0814 | 0.0636 | 0.0757 |
| Fictor | sortieren | alle | Arbeiten aller Sorten | 0.02 | 0.0018 | 0.0383 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.02 | 41.1 | 0 | 3 | 0 | 0.02 | 0.0272 | 0.02 |
| Fictor | waschen | alle | Arbeiten aller Sorten | 0.0947 | 0.0757 | 0.1136 | 40 | 10 | 2026-09-24 | 2026-11-12 | true | 0.0947 | 48.6 | 0 | 3 | 0 | 0.0947 | 0.0611 | 0.0947 |
| Fictor | waschen_sortieren | sorte | 1 Arbeit dieser Sorte (zählt 25 %), dazu alle Sorten wie 3 Arbeiten | 0.1491 | 0.0479 | 0.2503 | 1 | 1 | 2026-10-01 | 2026-10-01 | false | 0.3523 | 9 | 0 | 3 | 0.3523 | 0.0814 | 0.0636 | 0.1491 |
| Kaori Kuri | sortieren | sorte | 2 Arbeiten dieser Sorte (zählen 40 %), dazu alle Sorten wie 3 Arbeiten | 0.0347 | 0.001 | 0.0685 | 2 | 1 | 2026-09-23 | 2026-09-24 | false | 0.0567 | 41.4 | 0 | 3 | 0.0567 | 0.02 | 0.0272 | 0.0347 |
| Kaori Kuri | waschen | sorte | 9 Arbeiten dieser Sorte (zählen 75 %), dazu alle Sorten wie 3 Arbeiten | 0.0917 | 0.0529 | 0.1306 | 9 | 3 | 2026-09-24 | 2026-10-30 | false | 0.0908 | 45.4 | 0 | 3 | 0.0908 | 0.0947 | 0.0611 | 0.0917 |
| Kaori Kuri | waschen_sortieren | sorte | 14 Arbeiten dieser Sorte (zählen 82 %), dazu alle Sorten wie 3 Arbeiten | 0.0752 | 0.0425 | 0.1079 | 14 | 4 | 2026-09-21 | 2026-10-28 | false | 0.0739 | 31.4 | 0 | 3 | 0.0739 | 0.0814 | 0.0636 | 0.0752 |
| Ker Madec | sortieren | alle | Arbeiten aller Sorten | 0.02 | 0.0018 | 0.0383 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.02 | 41.1 | 0 | 3 | 0 | 0.02 | 0.0272 | 0.02 |
| Ker Madec | waschen | alle | Arbeiten aller Sorten | 0.0947 | 0.0757 | 0.1136 | 40 | 10 | 2026-09-24 | 2026-11-12 | true | 0.0947 | 48.6 | 0 | 3 | 0 | 0.0947 | 0.0611 | 0.0947 |
| Ker Madec | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0814 | 0.0663 | 0.0965 | 68 | 17 | 2026-09-21 | 2026-11-12 | true | 0.0814 | 34.3 | 0 | 3 | 0 | 0.0814 | 0.0636 | 0.0814 |
| Lekor | sortieren | sorte | 2 Arbeiten dieser Sorte (zählen 40 %), dazu alle Sorten wie 3 Arbeiten | 0.0321 | 0 | 0.0659 | 2 | 1 | 2026-10-10 | 2026-11-02 | false | 0.0503 | 77 | 0 | 3 | 0.0503 | 0.02 | 0.0272 | 0.0321 |
| Lekor | waschen | sorte | 5 Arbeiten dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Arbeiten | 0.0992 | 0.0481 | 0.1504 | 5 | 1 | 2026-10-01 | 2026-10-30 | false | 0.102 | 85.9 | 0 | 3 | 0.102 | 0.0947 | 0.0611 | 0.0992 |
| Lekor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0814 | 0.0663 | 0.0965 | 68 | 17 | 2026-09-21 | 2026-11-12 | true | 0.0814 | 34.3 | 0 | 3 | 0 | 0.0814 | 0.0636 | 0.0814 |
| Mieluna | sortieren | alle | Arbeiten aller Sorten | 0.02 | 0.0018 | 0.0383 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.02 | 41.1 | 0 | 3 | 0 | 0.02 | 0.0272 | 0.02 |
| Mieluna | waschen | alle | Arbeiten aller Sorten | 0.0947 | 0.0757 | 0.1136 | 40 | 10 | 2026-09-24 | 2026-11-12 | true | 0.0947 | 48.6 | 0 | 3 | 0 | 0.0947 | 0.0611 | 0.0947 |
| Mieluna | waschen_sortieren | sorte | 15 Arbeiten dieser Sorte (zählen 83 %), dazu alle Sorten wie 3 Arbeiten | 0.0703 | 0.0387 | 0.102 | 15 | 2 | 2026-10-01 | 2026-11-12 | false | 0.0681 | 35.5 | 0 | 3 | 0.0681 | 0.0814 | 0.0636 | 0.0703 |
| Orange Summer | sortieren | sorte | 1 Arbeit dieser Sorte (zählt 25 %), dazu alle Sorten wie 3 Arbeiten | 0.0157 | 0 | 0.059 | 1 | 1 | 2026-10-17 | 2026-10-17 | false | 0.0028 | 60 | 0 | 3 | 0.0028 | 0.02 | 0.0272 | 0.0157 |
| Orange Summer | waschen | sorte | 3 Arbeiten dieser Sorte (zählen 50 %), dazu alle Sorten wie 3 Arbeiten | 0.086 | 0.0219 | 0.1502 | 3 | 1 | 2026-10-17 | 2026-10-31 | false | 0.0774 | 67.3 | 0 | 3 | 0.0774 | 0.0947 | 0.0611 | 0.086 |
| Orange Summer | waschen_sortieren | sorte | 5 Arbeiten dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Arbeiten | 0.0732 | 0.02 | 0.1264 | 5 | 1 | 2026-10-05 | 2026-10-28 | false | 0.0683 | 59.9 | 0 | 3 | 0.0683 | 0.0814 | 0.0636 | 0.0732 |
| Orangita | sortieren | alle | Arbeiten aller Sorten | 0.02 | 0.0018 | 0.0383 | 11 | 6 | 2026-09-23 | 2026-11-02 | true | 0.02 | 41.1 | 0 | 3 | 0 | 0.02 | 0.0272 | 0.02 |
| Orangita | waschen | alle | Arbeiten aller Sorten | 0.0947 | 0.0757 | 0.1136 | 40 | 10 | 2026-09-24 | 2026-11-12 | true | 0.0947 | 48.6 | 0 | 3 | 0 | 0.0947 | 0.0611 | 0.0947 |
| Orangita | waschen_sortieren | sorte | 8 Arbeiten dieser Sorte (zählen 73 %), dazu alle Sorten wie 3 Arbeiten | 0.1174 | 0.0746 | 0.1601 | 8 | 2 | 2026-09-23 | 2026-10-29 | false | 0.1308 | 45.7 | 0 | 3 | 0.1308 | 0.0814 | 0.0636 | 0.1174 |
| Tiana | sortieren | sorte | 5 Arbeiten dieser Sorte (zählen 63 %), dazu alle Sorten wie 3 Arbeiten | 0.0123 | 0 | 0.0351 | 5 | 2 | 2026-09-30 | 2026-11-02 | false | 0.0077 | 30.6 | 0 | 3 | 0.0077 | 0.02 | 0.0272 | 0.0123 |
| Tiana | waschen | sorte | 13 Arbeiten dieser Sorte (zählen 81 %), dazu alle Sorten wie 3 Arbeiten | 0.075 | 0.0425 | 0.1076 | 13 | 3 | 2026-09-25 | 2026-11-12 | false | 0.0705 | 37.9 | 0 | 3 | 0.0705 | 0.0947 | 0.0611 | 0.075 |
| Tiana | waschen_sortieren | sorte | 17 Arbeiten dieser Sorte (zählen 85 %), dazu alle Sorten wie 3 Arbeiten | 0.0733 | 0.0436 | 0.1031 | 17 | 5 | 2026-09-23 | 2026-11-12 | false | 0.0719 | 21.1 | 0 | 3 | 0.0719 | 0.0814 | 0.0636 | 0.0733 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 726 | 583 | 133 | 128 | 128 | 133 | 116 | 60 | 0 | 19 | 5 | 11 | 0 | 44 | 43 | 0 | 0 | 0 | 329 | 329 | 122 | 122 | 4927 | 1354 | 1 | 583 | 583 | 89 | 12 | 19 | 5 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | verschenkt_kg | leer_weg_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-12 | 728344.14 | 36 | 351537.3 | 351537.3 | 0 | 0 | 0 | 2001 | 2026-11-11 | 0 | 351537.23 | 445347.91 | 126719.99 | 36635.14 | 231050.35 | 66429.31 | 60290.63 | 0 | 0 | 19062.55 | 0 | 80169.37 | 257222.83 | 229366.92 | 8793.36 | 294642.97 | 61064.36 | 11646.97 | 0 | 0 | true | 0.19 | 4510.87 | 0 | 0 | 0.4827 | Bis heute (12.11.2026): 728.3 t Eingang = 356.0 t ausgeliefert + 126.7 t Verlust (Verdunstung 66.4 t, Faules 60.3 t, Fax 0.0 t) + 257.2 t noch im Haus (davon 229.4 t verkaufsfähig, 27.9 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. Im Ausgeliefert sind 4511 kg verschenkt: in den Kisten über dem Sollgewicht mitgegeben (gewogen), nicht verrechnet. 11647 kg Überzählung. |

