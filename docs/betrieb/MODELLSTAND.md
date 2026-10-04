# Stand der Modelle

_Abzug vom 2026-10-04. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 02.10.2026, 02:00 (6 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 04.10.2026, 12:36 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0035 | 0.0029 | 0.0042 | 5 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0035 | 0.0029 | 0.0042 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Bolp 5110 | 0.0035 | 0.0029 | 0.0042 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.0035 | 0.0029 | 0.0042 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Amoro | 0.0035 | 0.0029 | 0.0042 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0035 | 0.0029 | 0.0042 | 3 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Lekor | 0.0035 | 0.0029 | 0.0042 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0035 | 0.0029 | 0.0042 | 6 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Fictor | 0.0035 | 0.0029 | 0.0042 | 5 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0034 | 0.0029 | 0.0039 | 14 | Wiegungen dieser Sorte |
| Ker Madec | 0.0035 | 0.0029 | 0.0042 | 0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.016 | 0.001 | 0.0309 | 3 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.016 | 0.001 | 0.0309 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Bolp 5110 | 0.016 | 0.001 | 0.0309 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.0033 | 0 | 0.0202 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.016 | 0.001 | 0.0309 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.016 | 0.001 | 0.0309 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Lekor | 0.016 | 0.001 | 0.0309 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.0353 | 0.017 | 0.0535 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.016 | 0.001 | 0.0309 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0028 | 0.0008 | 0.0048 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.016 | 0.001 | 0.0309 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0708 | 0.0101 | 0.1316 | 3 | alle Sorten (zu wenige eigene Chargen) |
| Orange Summer | 0.0072 | 0 | 0.0208 | 2 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0708 | 0.0101 | 0.1316 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Butterkin | 0.113 | 0.0413 | 0.1847 | 3 | eigene Messungen, zum Gesamtwert gezogen |
| Amoro | 0.0708 | 0.0101 | 0.1316 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Mieluna | 0.0708 | 0.0101 | 0.1316 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Lekor | 0.0708 | 0.0101 | 0.1316 | 1 | alle Sorten (zu wenige eigene Chargen) |
| Kaori Kuri | 0.009 | 0 | 0.022 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Fictor | 0.0708 | 0.0101 | 0.1316 | 0 | alle Sorten (zu wenige eigene Chargen) |
| Tiana | 0.0458 | 0 | 0.0949 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0708 | 0.0101 | 0.1316 | 1 | alle Sorten (zu wenige eigene Chargen) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0386 | 0 | 0.1607 | 3 | 2 | 2026-09-23 | 2026-09-30 | true |
| Amoro | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1098 | 0.0551 | 0.1645 | 8 | 6 | 2026-09-24 | 2026-10-01 | true |
| Amoro | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.106 | 0.0518 | 0.1603 | 13 | 8 | 2026-09-21 | 2026-10-01 | true |
| Butterkin | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0386 | 0 | 0.1607 | 3 | 2 | 2026-09-23 | 2026-09-30 | true |
| Butterkin | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1098 | 0.0551 | 0.1645 | 8 | 6 | 2026-09-24 | 2026-10-01 | true |
| Butterkin | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.106 | 0.0518 | 0.1603 | 13 | 8 | 2026-09-21 | 2026-10-01 | true |
| Fictor | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0386 | 0 | 0.1607 | 3 | 2 | 2026-09-23 | 2026-09-30 | true |
| Fictor | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1098 | 0.0551 | 0.1645 | 8 | 6 | 2026-09-24 | 2026-10-01 | true |
| Fictor | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.106 | 0.0518 | 0.1603 | 13 | 8 | 2026-09-21 | 2026-10-01 | true |
| Kaori Kuri | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0386 | 0 | 0.1607 | 3 | 2 | 2026-09-23 | 2026-09-30 | true |
| Kaori Kuri | waschen | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0885 | 0 | 0.268 | 3 | 2 | 2026-09-24 | 2026-09-30 | false |
| Kaori Kuri | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.106 | 0.0518 | 0.1603 | 13 | 8 | 2026-09-21 | 2026-10-01 | true |
| Ker Madec | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0386 | 0 | 0.1607 | 3 | 2 | 2026-09-23 | 2026-09-30 | true |
| Ker Madec | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1098 | 0.0551 | 0.1645 | 8 | 6 | 2026-09-24 | 2026-10-01 | true |
| Ker Madec | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.106 | 0.0518 | 0.1603 | 13 | 8 | 2026-09-21 | 2026-10-01 | true |
| Lekor | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0386 | 0 | 0.1607 | 3 | 2 | 2026-09-23 | 2026-09-30 | true |
| Lekor | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1098 | 0.0551 | 0.1645 | 8 | 6 | 2026-09-24 | 2026-10-01 | true |
| Lekor | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.106 | 0.0518 | 0.1603 | 13 | 8 | 2026-09-21 | 2026-10-01 | true |
| Mieluna | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0386 | 0 | 0.1607 | 3 | 2 | 2026-09-23 | 2026-09-30 | true |
| Mieluna | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1098 | 0.0551 | 0.1645 | 8 | 6 | 2026-09-24 | 2026-10-01 | true |
| Mieluna | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.106 | 0.0518 | 0.1603 | 13 | 8 | 2026-09-21 | 2026-10-01 | true |
| Orange Summer | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0386 | 0 | 0.1607 | 3 | 2 | 2026-09-23 | 2026-09-30 | true |
| Orange Summer | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1098 | 0.0551 | 0.1645 | 8 | 6 | 2026-09-24 | 2026-10-01 | true |
| Orange Summer | waschen_sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.106 | 0.0518 | 0.1603 | 13 | 8 | 2026-09-21 | 2026-10-01 | true |
| Orangita | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0386 | 0 | 0.1607 | 3 | 2 | 2026-09-23 | 2026-09-30 | true |
| Orangita | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1098 | 0.0551 | 0.1645 | 8 | 6 | 2026-09-24 | 2026-10-01 | true |
| Orangita | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0701 | 0 | 0.3226 | 3 | 1 | 2026-09-23 | 2026-09-29 | false |
| Tiana | sortieren | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.0386 | 0 | 0.1607 | 3 | 2 | 2026-09-23 | 2026-09-30 | true |
| Tiana | waschen | alle_4w | Arbeiten aller Sorten, letzte vier Wochen | 0.1098 | 0.0551 | 0.1645 | 8 | 6 | 2026-09-24 | 2026-10-01 | true |
| Tiana | waschen_sortieren | sorte_4w | Arbeiten dieser Sorte, letzte vier Wochen | 0.0761 | 0.0402 | 0.1119 | 5 | 3 | 2026-09-23 | 2026-10-01 | false |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 145 | 113 | 26 | 25 | 25 | 26 | 20 | 12 | 0 | 12 | 0 | 3 | 0 | 9 | 8 | 0 | 0 | 0 | 56 | 56 | 23 | 23 | 1069 | 180 | 1 | 113 | 113 | 17 | 0 | 12 | 0 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-02 | 639713.52 | 30 | 154494.7 | 154494.7 | 0 | 0 | 0 | 772 | 2026-09-29 | 0 | 154326.68 | 197532.52 | 115718.98 | 16305.06 | 316323.6 | 52709.97 | 63009.04 | 0 | 0 | 12510.41 | 0 | 128631.66 | 375506.4 | 339147.31 | 23848.72 | 448019.56 | 18424.84 | 5838.7 | 0 | 0 | true | 0.16 | 0 | 0.2415 | Bis heute (02.10.2026): 639.7 t Eingang = 154.3 t ausgeliefert + 115.7 t Verlust (Verdunstung 52.7 t, Faules 63.0 t, Fax 0.0 t) + 375.5 t noch im Haus (davon 339.1 t verkaufsfähig, 36.4 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. 5839 kg Überzählung. |

