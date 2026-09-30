# Stand der Modelle

_Abzug vom 2026-09-30. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 30.09.2026, 06:48 (4 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 30.09.2026, 12:31 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0035 | 0.0031 | 0.0039 | 5 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0035 | 0.0031 | 0.0039 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Amoro | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.0035 | 0.0031 | 0.0039 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Bolp 5110 | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Lekor | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Fictor | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0035 | 0.003 | 0.004 | 12 | Wiegungen dieser Sorte |
| Ker Madec | 0.0035 | 0.0031 | 0.0039 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |

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
| Orangita | 0.0718 | 0.0091 | 0.1345 | 2 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.009 | 0 | 0.022 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0718 | 0.0091 | 0.1345 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Amoro | 0.0718 | 0.0091 | 0.1345 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.1135 | 0.0415 | 0.1854 | 3 | eigene Messungen, zum Gesamtwert gezogen |
| Bolp 5110 | 0.0718 | 0.0091 | 0.1345 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0072 | 0 | 0.0208 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0718 | 0.0091 | 0.1345 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Fictor | 0.0718 | 0.0091 | 0.1345 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0442 | 0 | 0.0893 | 7 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0718 | 0.0091 | 0.1345 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle_saison | Arbeiten aller Sorten, ganze Saison | 0.0596 | 0 | 0.607 | 2 | 1 | 2026-09-23 | 2026-09-24 | true |
| Amoro | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.098 | 0 | 0.2099 | 4 | 2 | 2026-09-24 | 2026-09-28 | true |
| Amoro | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0916 | 0.0548 | 0.1284 | 9 | 6 | 2026-09-21 | 2026-09-26 | true |
| Butterkin | sortieren | alle_saison | Arbeiten aller Sorten, ganze Saison | 0.0596 | 0 | 0.607 | 2 | 1 | 2026-09-23 | 2026-09-24 | true |
| Butterkin | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.098 | 0 | 0.2099 | 4 | 2 | 2026-09-24 | 2026-09-28 | true |
| Butterkin | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0916 | 0.0548 | 0.1284 | 9 | 6 | 2026-09-21 | 2026-09-26 | true |
| Kaori Kuri | sortieren | alle_saison | Arbeiten aller Sorten, ganze Saison | 0.0596 | 0 | 0.607 | 2 | 1 | 2026-09-23 | 2026-09-24 | true |
| Kaori Kuri | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.098 | 0 | 0.2099 | 4 | 2 | 2026-09-24 | 2026-09-28 | true |
| Kaori Kuri | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0916 | 0.0548 | 0.1284 | 9 | 6 | 2026-09-21 | 2026-09-26 | true |
| Ker Madec | sortieren | alle_saison | Arbeiten aller Sorten, ganze Saison | 0.0596 | 0 | 0.607 | 2 | 1 | 2026-09-23 | 2026-09-24 | true |
| Ker Madec | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.098 | 0 | 0.2099 | 4 | 2 | 2026-09-24 | 2026-09-28 | true |
| Ker Madec | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0916 | 0.0548 | 0.1284 | 9 | 6 | 2026-09-21 | 2026-09-26 | true |
| Lekor | sortieren | alle_saison | Arbeiten aller Sorten, ganze Saison | 0.0596 | 0 | 0.607 | 2 | 1 | 2026-09-23 | 2026-09-24 | true |
| Lekor | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.098 | 0 | 0.2099 | 4 | 2 | 2026-09-24 | 2026-09-28 | true |
| Lekor | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0916 | 0.0548 | 0.1284 | 9 | 6 | 2026-09-21 | 2026-09-26 | true |
| Mieluna | sortieren | alle_saison | Arbeiten aller Sorten, ganze Saison | 0.0596 | 0 | 0.607 | 2 | 1 | 2026-09-23 | 2026-09-24 | true |
| Mieluna | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.098 | 0 | 0.2099 | 4 | 2 | 2026-09-24 | 2026-09-28 | true |
| Mieluna | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0916 | 0.0548 | 0.1284 | 9 | 6 | 2026-09-21 | 2026-09-26 | true |
| Orange Summer | sortieren | alle_saison | Arbeiten aller Sorten, ganze Saison | 0.0596 | 0 | 0.607 | 2 | 1 | 2026-09-23 | 2026-09-24 | true |
| Orange Summer | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.098 | 0 | 0.2099 | 4 | 2 | 2026-09-24 | 2026-09-28 | true |
| Orange Summer | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0916 | 0.0548 | 0.1284 | 9 | 6 | 2026-09-21 | 2026-09-26 | true |
| Orangita | sortieren | alle_saison | Arbeiten aller Sorten, ganze Saison | 0.0596 | 0 | 0.607 | 2 | 1 | 2026-09-23 | 2026-09-24 | true |
| Orangita | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.098 | 0 | 0.2099 | 4 | 2 | 2026-09-24 | 2026-09-28 | true |
| Orangita | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0916 | 0.0548 | 0.1284 | 9 | 6 | 2026-09-21 | 2026-09-26 | true |
| Tiana | sortieren | alle_saison | Arbeiten aller Sorten, ganze Saison | 0.0596 | 0 | 0.607 | 2 | 1 | 2026-09-23 | 2026-09-24 | true |
| Tiana | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.098 | 0 | 0.2099 | 4 | 2 | 2026-09-24 | 2026-09-28 | true |
| Tiana | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0812 | 0.0314 | 0.131 | 4 | 3 | 2026-09-23 | 2026-09-26 | false |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 103 | 80 | 19 | 18 | 18 | 19 | 14 | 8 | 0 | 12 | 0 | 2 | 0 | 6 | 5 | 0 | 0 | 0 | 44 | 44 | 17 | 17 | 769 | 180 | 1 | 80 | 80 | 13 | 0 | 12 | 0 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-30 | 618649.36 | 29 | 154494.7 | 154494.7 | 0 | 0 | 0 | 772 | 2026-09-29 | 0 | 154326.66 | 197630.52 | 107837.78 | 26831.01 | 237088.35 | 49899.36 | 57938.42 | 0 | 0 | 12476.72 | 0 | 125422.67 | 362368.11 | 326704.27 | 23187.1 | 426902.02 | 9910.12 | 5883.34 | 0 | 0 | true | 0.15 | 0 | 0.2497 | Bis heute (30.09.2026): 618.6 t Eingang = 154.3 t ausgeliefert + 107.8 t Verlust (Verdunstung 49.9 t, Faules 57.9 t, Fax 0.0 t) + 362.4 t noch im Haus (davon 326.7 t verkaufsfähig, 35.7 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. 5883 kg Überzählung. |

