# Stand der Modelle

_Abzug vom 2026-10-18. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Gerechnet: 18.10.2026, 02:00 (10 s) · Einstellungen: saison_aktuell = 2026 · betriebsmodus = "echt" · erfassung_scharf = false · verdunstung_rate_max_pro_tag = 0.01

**Zeitplan läuft** (*/1 * * * *) · letzter Lauf 18.10.2026, 10:53 · succeeded · 0 s · 1 row

Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?

## Verdunstung je Sorte (erg_koeff_verdunstung)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0.0027 | 0.002 | 0.0035 | 8 | Wiegungen dieser Sorte |
| Kaori Kuri | 0.0035 | 0.0026 | 0.0045 | 10 | Wiegungen dieser Sorte |
| Mieluna | 0.0021 | 0.0016 | 0.0027 | 28 | Wiegungen dieser Sorte |
| Amoro | 0.0028 | 0.0025 | 0.0031 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.0038 | 0.0035 | 0.0042 | 6 | Wiegungen dieser Sorte |
| Bolp 5110 | 0.0028 | 0.0025 | 0.0031 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0024 | 0.0022 | 0.0026 | 11 | Wiegungen dieser Sorte |
| Lekor | 0.0028 | 0.0025 | 0.0031 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |
| Fictor | 0.005 | 0.0023 | 0.0078 | 5 | Wiegungen dieser Sorte |
| Tiana | 0.0028 | 0.0024 | 0.0031 | 37 | Wiegungen dieser Sorte |
| Ker Madec | 0.0028 | 0.0025 | 0.0031 | 0 | Wiegungen aller Sorten (eigene: 0, gilt ab 3) |

## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0335 | 0.0195 | 0.0475 | 9 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0159 | 0.0073 | 0.0245 | 2 | alle Sorten (eigene: 2, gilt ab 3) |
| Amoro | 0.0159 | 0.0073 | 0.0245 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Butterkin | 0.0159 | 0.0073 | 0.0245 | 2 | alle Sorten (eigene: 2, gilt ab 3) |
| Bolp 5110 | 0.0159 | 0.0073 | 0.0245 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.0159 | 0.0073 | 0.0245 | 2 | alle Sorten (eigene: 2, gilt ab 3) |
| Lekor | 0.0159 | 0.0073 | 0.0245 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Fictor | 0.0159 | 0.0073 | 0.0245 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Tiana | 0.0028 | 0.0002 | 0.0054 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0159 | 0.0073 | 0.0245 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Anderer Kanal je Sorte (erg_koeff_nebenkanal)

| sorte | mittel | unten | oben | n | basis |
|---|---|---|---|---|---|
| Orangita | 0 | 0 | 0 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Kaori Kuri | 0.0078 | 0.0039 | 0.0118 | 8 | Sortierläufe/Handmessungen dieser Sorte |
| Mieluna | 0.0207 | 0 | 0.0462 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Amoro | 0.0625 | 0.0439 | 0.0811 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Butterkin | 0.1359 | 0 | 0.2886 | 3 | Sortierläufe/Handmessungen dieser Sorte |
| Bolp 5110 | 0.0625 | 0.0439 | 0.0811 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Orange Summer | 0.035 | 0 | 0.1159 | 5 | Sortierläufe/Handmessungen dieser Sorte |
| Lekor | 0.0625 | 0.0439 | 0.0811 | 1 | alle Sorten (eigene: 1, gilt ab 3) |
| Fictor | 0.0625 | 0.0439 | 0.0811 | 0 | alle Sorten (eigene: 0, gilt ab 3) |
| Tiana | 0.0384 | 0.0215 | 0.0553 | 13 | Sortierläufe/Handmessungen dieser Sorte |
| Ker Madec | 0.0625 | 0.0439 | 0.0811 | 1 | alle Sorten (eigene: 1, gilt ab 3) |

## Palox-Anteil je Sorte und Station (erg_palox_erwartung, 0107)

| sorte | station | ebene | quelle | anteil | unten | oben | n_arbeiten | n_chargen | seit | bis | geliehen | mittel | lager_mittel | anstieg_je_woche |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Amoro | sortieren | alle | Arbeiten aller Sorten | 0.0228 | 0 | 0.0472 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0228 | 37.6 |  |
| Amoro | waschen | alle | Arbeiten aller Sorten | 0.0915 | 0.0592 | 0.1237 | 22 | 9 | 2026-09-24 | 2026-10-17 | true | 0.0915 | 38.8 | 0 |
| Amoro | waschen_sortieren | alle | Arbeiten aller Sorten | 0.083 | 0.0556 | 0.1104 | 31 | 15 | 2026-09-21 | 2026-10-16 | true | 0.083 | 26.4 | 0 |
| Butterkin | sortieren | alle | Arbeiten aller Sorten | 0.0228 | 0 | 0.0472 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0228 | 37.6 |  |
| Butterkin | waschen | sorte | Arbeiten dieser Sorte | 0.147 | 0.0421 | 0.2518 | 5 | 2 | 2026-09-26 | 2026-10-13 | false | 0.147 | 38 | 0 |
| Butterkin | waschen_sortieren | alle | Arbeiten aller Sorten | 0.083 | 0.0556 | 0.1104 | 31 | 15 | 2026-09-21 | 2026-10-16 | true | 0.083 | 26.4 | 0 |
| Fictor | sortieren | alle | Arbeiten aller Sorten | 0.0228 | 0 | 0.0472 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0228 | 37.6 |  |
| Fictor | waschen | alle | Arbeiten aller Sorten | 0.0915 | 0.0592 | 0.1237 | 22 | 9 | 2026-09-24 | 2026-10-17 | true | 0.0915 | 38.8 | 0 |
| Fictor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.083 | 0.0556 | 0.1104 | 31 | 15 | 2026-09-21 | 2026-10-16 | true | 0.083 | 26.4 | 0 |
| Kaori Kuri | sortieren | alle | Arbeiten aller Sorten | 0.0228 | 0 | 0.0472 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0228 | 37.6 |  |
| Kaori Kuri | waschen | sorte | Arbeiten dieser Sorte | 0.0973 | 0.0245 | 0.1701 | 7 | 2 | 2026-09-24 | 2026-10-16 | false | 0.0973 | 50.3 | 0 |
| Kaori Kuri | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0838 | 0.0477 | 0.1199 | 7 | 3 | 2026-09-21 | 2026-10-16 | false | 0.0838 | 27.7 | 0 |
| Ker Madec | sortieren | alle | Arbeiten aller Sorten | 0.0228 | 0 | 0.0472 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0228 | 37.6 |  |
| Ker Madec | waschen | alle | Arbeiten aller Sorten | 0.0915 | 0.0592 | 0.1237 | 22 | 9 | 2026-09-24 | 2026-10-17 | true | 0.0915 | 38.8 | 0 |
| Ker Madec | waschen_sortieren | alle | Arbeiten aller Sorten | 0.083 | 0.0556 | 0.1104 | 31 | 15 | 2026-09-21 | 2026-10-16 | true | 0.083 | 26.4 | 0 |
| Lekor | sortieren | alle | Arbeiten aller Sorten | 0.0228 | 0 | 0.0472 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0228 | 37.6 |  |
| Lekor | waschen | alle | Arbeiten aller Sorten | 0.0915 | 0.0592 | 0.1237 | 22 | 9 | 2026-09-24 | 2026-10-17 | true | 0.0915 | 38.8 | 0 |
| Lekor | waschen_sortieren | alle | Arbeiten aller Sorten | 0.083 | 0.0556 | 0.1104 | 31 | 15 | 2026-09-21 | 2026-10-16 | true | 0.083 | 26.4 | 0 |
| Mieluna | sortieren | alle | Arbeiten aller Sorten | 0.0228 | 0 | 0.0472 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0228 | 37.6 |  |
| Mieluna | waschen | alle | Arbeiten aller Sorten | 0.0915 | 0.0592 | 0.1237 | 22 | 9 | 2026-09-24 | 2026-10-17 | true | 0.0915 | 38.8 | 0 |
| Mieluna | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0516 | 0.0143 | 0.0889 | 5 | 2 | 2026-10-01 | 2026-10-15 | false | 0.0516 | 27.1 | 0 |
| Orange Summer | sortieren | alle | Arbeiten aller Sorten | 0.0228 | 0 | 0.0472 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0228 | 37.6 |  |
| Orange Summer | waschen | alle | Arbeiten aller Sorten | 0.0915 | 0.0592 | 0.1237 | 22 | 9 | 2026-09-24 | 2026-10-17 | true | 0.0915 | 38.8 | 0 |
| Orange Summer | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.054 | 0.0063 | 0.1018 | 3 | 1 | 2026-10-05 | 2026-10-10 | false | 0.054 | 49.4 | 0 |
| Orangita | sortieren | alle | Arbeiten aller Sorten | 0.0228 | 0 | 0.0472 | 9 | 6 | 2026-09-23 | 2026-10-17 | true | 0.0228 | 37.6 |  |
| Orangita | waschen | alle | Arbeiten aller Sorten | 0.0915 | 0.0592 | 0.1237 | 22 | 9 | 2026-09-24 | 2026-10-17 | true | 0.0915 | 38.8 | 0 |
| Orangita | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.1348 | 0.0035 | 0.2661 | 5 | 2 | 2026-09-23 | 2026-10-12 | false | 0.1348 | 38.9 | 0 |
| Tiana | sortieren | sorte | Arbeiten dieser Sorte | 0.0069 | 0 | 0.0139 | 4 | 2 | 2026-09-30 | 2026-10-09 | false | 0.0069 | 22.7 |  |
| Tiana | waschen | sorte | Arbeiten dieser Sorte | 0.0563 | 0.0214 | 0.0912 | 8 | 3 | 2026-09-25 | 2026-10-16 | false | 0.0563 | 27 | 0 |
| Tiana | waschen_sortieren | sorte | Arbeiten dieser Sorte | 0.0642 | 0.0427 | 0.0857 | 9 | 5 | 2026-09-23 | 2026-10-12 | false | 0.0642 | 19.2 | 0 |

## Datenqualität (erg_datenqualitaet)

| paletten_gezaehlt | paletten_mit_datum | arbeiten_fertig | arbeiten_mit_ablesung | arbeiten_mit_zwei_ablesungen | arbeiten_mit_antwort | ausschuss_messungen | ausschuss_gewogen | lagerkontrollen | sortierlaeufe | sortierlaeufe_zugeordnet | sortier_arbeiten | sortier_arbeiten_mit_kisten | wasch_arbeiten | wasch_arbeiten_mit_kisten | fax_arbeiten | fax_arbeiten_mit_kisten | fax_arbeiten_mit_faulem | ws_paletten_gezaehlt | ws_paletten_mit_zettelgewicht | arbeiten_nach_waschen | arbeiten_mit_kistensystem | wasch_kisten_gezaehlt | wasch_kisten_mit_sortierdatum | arbeiten_mit_palox_unbekannt | eingangspaletten | eingangspaletten_mit_kisten | arbeiten_alter_gemessen | sammel_lesungen | lesungen_mit_sortiertag | lesungen_sortiertag_bezeugt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 422 | 348 | 64 | 62 | 62 | 64 | 47 | 27 | 0 | 12 | 0 | 9 | 0 | 23 | 22 | 0 | 0 | 0 | 141 | 141 | 55 | 55 | 2569 | 1044 | 1 | 348 | 348 | 41 | 0 | 12 | 0 |

## Bilanz (erg_bilanz)

| heute | eingang_kg | n_chargen | ausgang_kg | verkauf_kg | marge_kg | entsorgt_kg | ausgang_fehler_kg | n_lieferungen | letzte_lieferung | vorlauf_kg | geliefert_kg | ausgelagert_kg | verlust_heute_kg | verlust_unten_kg | verlust_oben_kg | verdunstung_heute_kg | schimmel_heute_kg | fax_heute_kg | fax_erwartet_kg | kanal_ausgelagert_kg | kanal_unten_kg | kanal_oben_kg | im_haus_heute_kg | verkaufsfaehig_heute_kg | kanal_im_haus_kg | lager_kg | gegenprobe_wartet_kg | ueberzaehlung_kg | fax_durchsatz_kg | n_fax_arbeiten | verlust_bekannt | bilanz_rest_kg | bilanz_rest_anteil | ausgang_deckung | befund |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-18 | 656518.64 | 31 | 209732.8 | 209732.8 | 0 | 0 | 0 | 1133 | 2026-10-14 | 0 | 208140.75 | 270798.04 | 119411.14 | 38192.78 | 240861.98 | 64078.47 | 55332.7 | 0 | 0 | 16639.6 | 0 | 106060.75 | 341384.14 | 305586.57 | 19157.98 | 398138 | 59382.72 | 12417.6 | 0 | 0 | true | 0.21 | 0 | 0.3195 | Bis heute (18.10.2026): 656.5 t Eingang = 208.1 t ausgeliefert + 119.4 t Verlust (Verdunstung 64.1 t, Faules 55.3 t, Fax 0.0 t) + 341.4 t noch im Haus (davon 305.6 t verkaufsfähig, 35.8 t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum Saisonende steht in der Grafik, nicht in diesen Zahlen. 12418 kg Überzählung. |

