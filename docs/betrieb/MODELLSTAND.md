# Stand der Modelle

_Abzug vom 2026-10-07. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 07.10.2026, 02:00 (7 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 07.10.2026, 13:07 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0031 | 0.0025 | 0.0037 | 5 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0031 | 0.0025 | 0.0037 | 7 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Bolp 5110 | 0.0031 | 0.0025 | 0.0037 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.0031 | 0.0025 | 0.0037 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Amoro | 0.0031 | 0.0025 | 0.0037 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0022 | 0.0012 | 0.0032 | 13 | Wiegungen dieser Sorte |
| Lekor | 0.0031 | 0.0025 | 0.0037 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0031 | 0.0025 | 0.0037 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Fictor | 0.0031 | 0.0025 | 0.0037 | 5 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0031 | 0.0022 | 0.0039 | 23 | Wiegungen dieser Sorte |
| Ker Madec | 0.0031 | 0.0025 | 0.0037 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0166 | 0.0018 | 0.0313 | 3 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.063 | 0.0624 | 0.0637 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0166 | 0.0018 | 0.0313 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.0033 | 0 | 0.0202 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0166 | 0.0018 | 0.0313 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0166 | 0.0018 | 0.0313 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Lekor | 0.0166 | 0.0018 | 0.0313 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0357 | 0.0199 | 0.0516 | 6 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0166 | 0.0018 | 0.0313 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0028 | 0.0008 | 0.0048 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0166 | 0.0018 | 0.0313 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0675 | 0.0116 | 0.1233 | 3 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0113 | 0 | 0.0662 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0675 | 0.0116 | 0.1233 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.1118 | 0.043 | 0.1806 | 3 | eigene Messungen, zum Gesamtwert gezogen |
| Amoro | 0.0675 | 0.0116 | 0.1233 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0377 | 0 | 0.0804 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0675 | 0.0116 | 0.1233 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0091 | 0.0004 | 0.0178 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0675 | 0.0116 | 0.1233 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0436 | 0.0071 | 0.0801 | 10 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0675 | 0.0116 | 0.1233 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Amoro | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0948 | 0.0436 | 0.146 | 9 | 7 | 2026-09-24 | 2026-10-05 | true |
| Amoro | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0978 | 0.0621 | 0.1336 | 19 | 12 | 2026-09-21 | 2026-10-06 | true |
| Butterkin | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Butterkin | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0948 | 0.0436 | 0.146 | 9 | 7 | 2026-09-24 | 2026-10-05 | true |
| Butterkin | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0978 | 0.0621 | 0.1336 | 19 | 12 | 2026-09-21 | 2026-10-06 | true |
| Fictor | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Fictor | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0948 | 0.0436 | 0.146 | 9 | 7 | 2026-09-24 | 2026-10-05 | true |
| Fictor | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0978 | 0.0621 | 0.1336 | 19 | 12 | 2026-09-21 | 2026-10-06 | true |
| Kaori Kuri | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Kaori Kuri | waschen | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0885 | 0 | 0.268 | 3 | 2 | 2026-09-24 | 2026-09-30 | false |
| Kaori Kuri | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0902 | 0.0088 | 0.1715 | 3 | 2 | 2026-09-21 | 2026-10-06 | false |
| Ker Madec | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Ker Madec | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0948 | 0.0436 | 0.146 | 9 | 7 | 2026-09-24 | 2026-10-05 | true |
| Ker Madec | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0978 | 0.0621 | 0.1336 | 19 | 12 | 2026-09-21 | 2026-10-06 | true |
| Lekor | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Lekor | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0948 | 0.0436 | 0.146 | 9 | 7 | 2026-09-24 | 2026-10-05 | true |
| Lekor | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0978 | 0.0621 | 0.1336 | 19 | 12 | 2026-09-21 | 2026-10-06 | true |
| Mieluna | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Mieluna | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0948 | 0.0436 | 0.146 | 9 | 7 | 2026-09-24 | 2026-10-05 | true |
| Mieluna | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0778 | 0.009 | 0.1466 | 3 | 2 | 2026-10-01 | 2026-10-05 | false |
| Orange Summer | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Orange Summer | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0948 | 0.0436 | 0.146 | 9 | 7 | 2026-09-24 | 2026-10-05 | true |
| Orange Summer | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0978 | 0.0621 | 0.1336 | 19 | 12 | 2026-09-21 | 2026-10-06 | true |
| Orangita | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Orangita | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0948 | 0.0436 | 0.146 | 9 | 7 | 2026-09-24 | 2026-10-05 | true |
| Orangita | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0691 | 0 | 0.3184 | 3 | 1 | 2026-09-23 | 2026-09-29 | false |
| Tiana | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Tiana | waschen | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.069 | 0 | 0.2281 | 3 | 2 | 2026-09-25 | 2026-10-05 | false |
| Tiana | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.079 | 0.0506 | 0.1074 | 6 | 4 | 2026-09-23 | 2026-10-06 | false |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 199 | 162 | 34 | 33 | 33 | 34 | 29 | 21 | 0 | 12 | 0 | 4 | 0 | 10 | 9 | 0 | 0 | 0 | 90 | 90 | 30 | 30 | 1249 | 360 | 1 | 162 | 162 | 24 | 0 | 12 | 0 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-07 | 639713.52 | 30 | 154494.7 | 154494.7 | 0 | 0 | 0 | 772 | 2026-09-29 | 0 | 154326.68 | 194138.06 | 107372.05 | 11047.58 | 294440.33 | 52355.05 | 55017 | 0 | 0 | 12260.08 | 0 | 109248.62 | 383256.65 | 347500.58 | 23496.07 | 450817.34 | 22457.84 | 5242.03 | 0 | 0 | true | 0.17 | 0 | 0.2415 | Bis heute (07.10.2026): 639.7 t Eingang = 154.3 t ausgeliefert + 107.4 t Verlust (Verdunstung 52.4 t, Faules 55.0 t, Fax 0.0 t) + 383.3 t noch im Haus (davon 347.5 t verkaufsfähig, 35.8 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. 5242 kg Überzählung. |

