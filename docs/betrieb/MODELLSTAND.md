# Stand der Modelle

_Abzug vom 2026-10-08. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 08.10.2026, 02:00 (7 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 08.10.2026, 13:24 · succeeded · 0 s · 1 row

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
| Amoro | 0.067 | 0.0115 | 0.1226 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0377 | 0 | 0.0804 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.009 | 0.0007 | 0.0172 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Butterkin | 0.1117 | 0.0429 | 0.1805 | 3 | eigene Messungen, zum Gesamtwert gezogen |
| Orangita | 0.067 | 0.0115 | 0.1226 | 3 | alle Sorten (zu wenige eigene Chargen) |
| Bolp 5110 | 0.067 | 0.0115 | 0.1226 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0113 | 0 | 0.0662 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.067 | 0.0115 | 0.1226 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Fictor | 0.067 | 0.0115 | 0.1226 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0436 | 0.007 | 0.0801 | 10 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.067 | 0.0115 | 0.1226 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Amoro | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Amoro | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0988 | 0.0649 | 0.1326 | 20 | 12 | 2026-09-21 | 2026-10-07 | true |
| Butterkin | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Butterkin | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Butterkin | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0988 | 0.0649 | 0.1326 | 20 | 12 | 2026-09-21 | 2026-10-07 | true |
| Fictor | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Fictor | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Fictor | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0988 | 0.0649 | 0.1326 | 20 | 12 | 2026-09-21 | 2026-10-07 | true |
| Kaori Kuri | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Kaori Kuri | waschen | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.1096 | 0.0101 | 0.2091 | 5 | 2 | 2026-09-24 | 2026-10-07 | false |
| Kaori Kuri | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0979 | 0.0524 | 0.1433 | 4 | 2 | 2026-09-21 | 2026-10-07 | false |
| Ker Madec | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Ker Madec | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Ker Madec | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0988 | 0.0649 | 0.1326 | 20 | 12 | 2026-09-21 | 2026-10-07 | true |
| Lekor | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Lekor | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Lekor | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0988 | 0.0649 | 0.1326 | 20 | 12 | 2026-09-21 | 2026-10-07 | true |
| Mieluna | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Mieluna | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Mieluna | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0778 | 0.009 | 0.1466 | 3 | 2 | 2026-10-01 | 2026-10-05 | false |
| Orange Summer | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Orange Summer | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Orange Summer | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0988 | 0.0649 | 0.1326 | 20 | 12 | 2026-09-21 | 2026-10-07 | true |
| Orangita | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Orangita | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1025 | 0.0553 | 0.1496 | 11 | 7 | 2026-09-24 | 2026-10-07 | true |
| Orangita | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0691 | 0 | 0.3184 | 3 | 1 | 2026-09-23 | 2026-09-29 | false |
| Tiana | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0308 | 0 | 0.0982 | 4 | 3 | 2026-09-23 | 2026-10-06 | true |
| Tiana | waschen | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.069 | 0 | 0.2281 | 3 | 2 | 2026-09-25 | 2026-10-05 | false |
| Tiana | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.079 | 0.0506 | 0.1074 | 6 | 4 | 2026-09-23 | 2026-10-06 | false |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 210 | 168 | 37 | 36 | 36 | 37 | 30 | 22 | 0 | 12 | 0 | 4 | 0 | 12 | 11 | 0 | 0 | 0 | 96 | 96 | 33 | 33 | 1429 | 468 | 1 | 168 | 168 | 25 | 0 | 12 | 0 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-08 | 639713.52 | 30 | 154494.7 | 154494.7 | 0 | 0 | 0 | 772 | 2026-09-29 | 0 | 154326.68 | 194754.05 | 110090.44 | 11457.05 | 295644.82 | 53577.63 | 56512.84 | 0 | 0 | 12235.21 | 0 | 108622.2 | 380810.02 | 345254.46 | 23320.34 | 450473.09 | 21233.32 | 5513.78 | 0 | 0 | true | 0.16 | 0 | 0.2415 | Bis heute (08.10.2026): 639.7 t Eingang = 154.3 t ausgeliefert + 110.1 t Verlust (Verdunstung 53.6 t, Faules 56.5 t, Fax 0.0 t) + 380.8 t noch im Haus (davon 345.3 t verkaufsfähig, 35.6 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. 5514 kg Überzählung. |

