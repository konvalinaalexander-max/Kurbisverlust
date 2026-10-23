# Stand der Modelle

_Abzug vom 2026-10-23. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 23.10.2026, 09:24 (14 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 23.10.2026, 11:23 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0025 | 0.0018 | 0.0033 | 9 | Wiegungen dieser Sorte |
| Kaori Kuri | 0.0044 | 0.0032 | 0.0055 | 18 | Wiegungen dieser Sorte |
| Mieluna | 0.0018 | 0.0015 | 0.0022 | 42 | Wiegungen dieser Sorte |
| Amoro | 0.0027 | 0.0024 | 0.003 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.0038 | 0.0035 | 0.0042 | 6 | Wiegungen dieser Sorte |
| Bolp 5110 | 0.0027 | 0.0024 | 0.003 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0024 | 0.0022 | 0.0027 | 17 | Wiegungen dieser Sorte |
| Lekor | 0.0027 | 0.0024 | 0.003 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Fictor | 0.005 | 0.0023 | 0.0078 | 5 | Wiegungen dieser Sorte |
| Tiana | 0.0026 | 0.0022 | 0.0029 | 44 | Wiegungen dieser Sorte |
| Ker Madec | 0.0027 | 0.0024 | 0.003 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0263 | 0.0162 | 0.0364 | 15 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0026 | 0 | 0.0184 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.013 | 0.007 | 0.019 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Butterkin | 0.0029 | 0 | 0.0069 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.013 | 0.007 | 0.019 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0466 | 0 | 0.1203 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.013 | 0.007 | 0.019 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Fictor | 0.013 | 0.007 | 0.019 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Tiana | 0.0034 | 0.0006 | 0.0062 | 6 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.013 | 0.007 | 0.019 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0012 | 0 | 0.0052 | 6 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0107 | 0.0028 | 0.0186 | 13 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0271 | 0 | 0.0612 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0729 | 0.0555 | 0.0902 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.1468 | 0.074 | 0.2197 | 4 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0729 | 0.0555 | 0.0902 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0316 | 0 | 0.0919 | 6 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0729 | 0.0555 | 0.0902 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Fictor | 0.0729 | 0.0555 | 0.0902 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Tiana | 0.037 | 0.0211 | 0.0529 | 18 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0729 | 0.0555 | 0.0902 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen | mittel | lager_mittel | anstieg_je_woche |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Amoro | waschen | alle | Arbeiten aller Sorten | 0.0916 | 0.0642 | 0.1189 | 26 | 9 | 2026-09-24 | 2026-10-22 | true | 0.0916 | 42 | 0 |
| Amoro | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0747 | 0.0538 | 0.0955 | 42 | 15 | 2026-09-21 | 2026-10-22 | true | 0.0747 | 28.9 | 0 |
| Butterkin | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Butterkin | waschen | sorte | Arbeiten dieser Sorte | 0.1289 | 0.0537 | 0.2041 | 7 | 2 | 2026-09-26 | 2026-10-22 | false | 0.1289 | 42.6 | 0 |
| Butterkin | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0747 | 0.0538 | 0.0955 | 42 | 15 | 2026-09-21 | 2026-10-22 | true | 0.0747 | 28.9 | 0 |
| Fictor | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Fictor | waschen | alle | Arbeiten aller Sorten | 0.0916 | 0.0642 | 0.1189 | 26 | 9 | 2026-09-24 | 2026-10-22 | true | 0.0916 | 42 | 0 |
| Fictor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0747 | 0.0538 | 0.0955 | 42 | 15 | 2026-09-21 | 2026-10-22 | true | 0.0747 | 28.9 | 0 |
| Kaori Kuri | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Kaori Kuri | waschen | sorte | Arbeiten dieser Sorte | 0.0973 | 0.0245 | 0.1701 | 7 | 2 | 2026-09-24 | 2026-10-16 | false | 0.0973 | 50.3 | 0 |
| Kaori Kuri | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.072 | 0.0487 | 0.0953 | 10 | 3 | 2026-09-21 | 2026-10-22 | false | 0.072 | 33.6 | 0 |
| Ker Madec | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Ker Madec | waschen | alle | Arbeiten aller Sorten | 0.0916 | 0.0642 | 0.1189 | 26 | 9 | 2026-09-24 | 2026-10-22 | true | 0.0916 | 42 | 0 |
| Ker Madec | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0747 | 0.0538 | 0.0955 | 42 | 15 | 2026-09-21 | 2026-10-22 | true | 0.0747 | 28.9 | 0 |
| Lekor | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Lekor | waschen | sorte | Arbeiten dieser Sorte | 0.1075 | 0.0744 | 0.1405 | 3 | 1 | 2026-10-01 | 2026-10-22 | false | 0.1075 | 76.9 | 0 |
| Lekor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.0747 | 0.0538 | 0.0955 | 42 | 15 | 2026-09-21 | 2026-10-22 | true | 0.0747 | 28.9 | 0 |
| Mieluna | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Mieluna | waschen | alle | Arbeiten aller Sorten | 0.0916 | 0.0642 | 0.1189 | 26 | 9 | 2026-09-24 | 2026-10-22 | true | 0.0916 | 42 | 0 |
| Mieluna | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0474 | 0.0264 | 0.0683 | 8 | 2 | 2026-10-01 | 2026-10-21 | false | 0.0474 | 28 | 0 |
| Orange Summer | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Orange Summer | waschen | alle | Arbeiten aller Sorten | 0.0916 | 0.0642 | 0.1189 | 26 | 9 | 2026-09-24 | 2026-10-22 | true | 0.0916 | 42 | 0 |
| Orange Summer | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0491 | 0.022 | 0.0763 | 4 | 1 | 2026-10-05 | 2026-10-21 | false | 0.0491 | 54.1 | 0 |
| Orangita | sortieren | alle | Arbeiten aller Sorten | 0.0229 | 0 | 0.0478 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0229 | 37.6 |  |
| Orangita | waschen | alle | Arbeiten aller Sorten | 0.0916 | 0.0642 | 0.1189 | 26 | 9 | 2026-09-24 | 2026-10-22 | true | 0.0916 | 42 | 0 |
| Orangita | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.1311 | 0.0297 | 0.2324 | 6 | 2 | 2026-09-23 | 2026-10-22 | false | 0.1311 | 41 | 0 |
| Tiana | sortieren | sorte | Arbeiten dieser Sorte | 0.0069 | 0 | 0.0139 | 4 | 2 | 2026-09-30 | 2026-10-09 | false | 0.0069 | 22.7 |  |
| Tiana | waschen | sorte | Arbeiten dieser Sorte | 0.0563 | 0.0214 | 0.0912 | 8 | 3 | 2026-09-25 | 2026-10-16 | false | 0.0563 | 27 | 0 |
| Tiana | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.065 | 0.0489 | 0.081 | 12 | 5 | 2026-09-23 | 2026-10-22 | false | 0.065 | 18.5 | 0 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 480 | 387 | 82 | 77 | 77 | 82 | 63 | 35 | 0 | 19 | 5 | 9 | 0 | 30 | 29 | 0 | 0 | 0 | 180 | 180 | 73 | 73 | 3214 | 1354 | 1 | 387 | 387 | 52 | 2 | 19 | 5 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-23 | 696473.3 | 36 | 243205.6 | 243205.6 | 0 | 0 | 0 | 1317 | 2026-10-21 | 0 | 243205.59 | 313694.76 | 157973.52 | 51000.28 | 264946.64 | 71431 | 86542.5 | 0 | 0 | 15587.34 | 0 | 77017.88 | 312701.16 | 285518.14 | 11595.71 | 400018.59 | 55467.1 | 17240.32 | 0 | 0 | true | -166.65 | -0.0002 | 0.3492 | Bis heute (23.10.2026): 696.5 t Eingang = 243.2 t ausgeliefert + 158.0 t Verlust (Verdunstung 71.4 t, Faules 86.5 t, Fax 0.0 t) + 312.7 t noch im Haus (davon 285.5 t verkaufsfähig, 27.2 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. 17240 kg Überzählung. |

