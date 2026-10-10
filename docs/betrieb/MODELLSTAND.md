# Stand der Modelle

_Abzug vom 2026-10-10. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 10.10.2026, 02:00 (7 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 10.10.2026, 12:38 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Amoro | 0.003 | 0.0025 | 0.0035 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0023 | 0.0016 | 0.003 | 13 | Wiegungen dieser Sorte |
| Kaori Kuri | 0.0031 | 0.0021 | 0.0041 | 8 | Wiegungen dieser Sorte, zum Gesamtwert gezogen |
| Butterkin | 0.003 | 0.0025 | 0.0035 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Orangita | 0.003 | 0.0025 | 0.0035 | 5 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Bolp 5110 | 0.003 | 0.0025 | 0.0035 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.003 | 0.0025 | 0.0035 | 7 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Lekor | 0.003 | 0.0025 | 0.0035 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Fictor | 0.003 | 0.0025 | 0.0035 | 5 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0029 | 0.0023 | 0.0035 | 34 | Wiegungen dieser Sorte |
| Ker Madec | 0.003 | 0.0025 | 0.0035 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Amoro | 0.0164 | 0.0019 | 0.031 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0164 | 0.0019 | 0.031 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0347 | 0.022 | 0.0474 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Butterkin | 0.0033 | 0 | 0.0202 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Orangita | 0.0164 | 0.0019 | 0.031 | 3 | alle Sorten (zu wenige eigene Chargen) |
| Bolp 5110 | 0.0164 | 0.0019 | 0.031 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0629 | 0.0616 | 0.0643 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0164 | 0.0019 | 0.031 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Fictor | 0.0164 | 0.0019 | 0.031 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0028 | 0.0008 | 0.0048 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0164 | 0.0019 | 0.031 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0649 | 0.0107 | 0.1192 | 3 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0112 | 0 | 0.0656 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0649 | 0.0107 | 0.1192 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.1111 | 0.0441 | 0.1781 | 3 | eigene Messungen, zum Gesamtwert gezogen |
| Amoro | 0.0649 | 0.0107 | 0.1192 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0376 | 0 | 0.0803 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0649 | 0.0107 | 0.1192 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0086 | 0 | 0.0174 | 6 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0649 | 0.0107 | 0.1192 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0405 | 0.0109 | 0.0701 | 12 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0649 | 0.0107 | 0.1192 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0209 | 0 | 0.0686 | 5 | 3 | 2026-09-23 | 2026-10-08 | true |
| Amoro | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Amoro | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0906 | 0.0606 | 0.1207 | 23 | 14 | 2026-09-21 | 2026-10-08 | true |
| Butterkin | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0209 | 0 | 0.0686 | 5 | 3 | 2026-09-23 | 2026-10-08 | true |
| Butterkin | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Butterkin | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0906 | 0.0606 | 0.1207 | 23 | 14 | 2026-09-21 | 2026-10-08 | true |
| Fictor | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0209 | 0 | 0.0686 | 5 | 3 | 2026-09-23 | 2026-10-08 | true |
| Fictor | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Fictor | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0906 | 0.0606 | 0.1207 | 23 | 14 | 2026-09-21 | 2026-10-08 | true |
| Kaori Kuri | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0209 | 0 | 0.0686 | 5 | 3 | 2026-09-23 | 2026-10-08 | true |
| Kaori Kuri | waschen | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.1096 | 0.0101 | 0.2091 | 5 | 2 | 2026-09-24 | 2026-10-07 | false |
| Kaori Kuri | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0962 | 0.0644 | 0.128 | 5 | 3 | 2026-09-21 | 2026-10-08 | false |
| Ker Madec | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0209 | 0 | 0.0686 | 5 | 3 | 2026-09-23 | 2026-10-08 | true |
| Ker Madec | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Ker Madec | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0906 | 0.0606 | 0.1207 | 23 | 14 | 2026-09-21 | 2026-10-08 | true |
| Lekor | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0209 | 0 | 0.0686 | 5 | 3 | 2026-09-23 | 2026-10-08 | true |
| Lekor | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Lekor | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0906 | 0.0606 | 0.1207 | 23 | 14 | 2026-09-21 | 2026-10-08 | true |
| Mieluna | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0209 | 0 | 0.0686 | 5 | 3 | 2026-09-23 | 2026-10-08 | true |
| Mieluna | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Mieluna | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0779 | 0.0091 | 0.1467 | 3 | 2 | 2026-10-01 | 2026-10-05 | false |
| Orange Summer | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0209 | 0 | 0.0686 | 5 | 3 | 2026-09-23 | 2026-10-08 | true |
| Orange Summer | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Orange Summer | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0906 | 0.0606 | 0.1207 | 23 | 14 | 2026-09-21 | 2026-10-08 | true |
| Orangita | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0209 | 0 | 0.0686 | 5 | 3 | 2026-09-23 | 2026-10-08 | true |
| Orangita | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Orangita | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0688 | 0 | 0.3172 | 3 | 1 | 2026-09-23 | 2026-09-29 | false |
| Tiana | sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0054 | 0 | 0.0132 | 3 | 2 | 2026-09-30 | 2026-10-08 | false |
| Tiana | waschen | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.069 | 0 | 0.2281 | 3 | 2 | 2026-09-25 | 2026-10-05 | false |
| Tiana | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0652 | 0.0404 | 0.0901 | 8 | 5 | 2026-09-23 | 2026-10-08 | false |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 266 | 224 | 41 | 40 | 40 | 41 | 34 | 24 | 0 | 12 | 0 | 5 | 0 | 12 | 11 | 0 | 0 | 0 | 111 | 111 | 36 | 36 | 1429 | 468 | 1 | 224 | 224 | 29 | 0 | 12 | 0 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-10 | 639713.52 | 30 | 154494.7 | 154494.7 | 0 | 0 | 0 | 772 | 2026-09-29 | 0 | 154326.68 | 192370.49 | 104658.28 | 16105.22 | 271106.16 | 54435.25 | 50223.05 | 0 | 0 | 11921.95 | 0 | 104247.81 | 385444.4 | 350563.49 | 22958.94 | 452058.89 | 37367.32 | 4716 | 0 | 0 | true | 0.16 | 0 | 0.2415 | Bis heute (10.10.2026): 639.7 t Eingang = 154.3 t ausgeliefert + 104.7 t Verlust (Verdunstung 54.4 t, Faules 50.2 t, Fax 0.0 t) + 385.4 t noch im Haus (davon 350.6 t verkaufsfähig, 34.9 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. 4716 kg Überzählung. |

