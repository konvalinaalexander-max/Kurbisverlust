# Plausibilitätsdurchgang

_Stand 2026-10-10 · Quelle docs/betrieb/rohdaten (Betriebsabzug) · von `pruefstand/durchgang.mjs` geschrieben; nicht von Hand ändern._

Jede Zeile ist ein **Kandidat**, kein Urteil: eine Zahl, die so nicht sein kann oder nicht sein sollte, mit dem Grund. Die Runde am Programm liest sie, prüft die Rohzeilen und schreibt die Zweitmeinung; der Betrieb entscheidet.

## Tabellen

| Tabelle | Zeilen |
|---|---|
| charge | 42 |
| palette | 1756 |
| auftrag | 53 |
| auftrag_palette | 317 |
| auftrag_gebinde | 0 |
| schimmel_messung | 115 |
| ausschuss_messung | 37 |
| verdunstung_wiegung | 92 |
| ausgang_wiegung | 69 |
| kontrollpalette | 0 |
| kontrollpalette_wiegung | 0 |
| lieferung | 772 |
| sortier_lauf | 12 |
| gebinde | 6 |
| auswertung_stand | 1 |

_310 Paletten sind Vervielfachungen einer Journalzeile („n Paletten gleich", extern_id …#n) — keine Kandidaten._

## Nach Prüfung (82)

| Prüfung | Anzahl |
|---|---|
| Zetteldatum ohne Palette | 18 |
| Zettelgewicht | 13 |
| Teilpalette mit vollem Zettel | 11 |
| Arbeit offen | 8 |
| Zettel Kistenzahl | 6 |
| Teilpalette von Hand umgerechnet | 6 |
| Schwerer geworden | 5 |
| Arbeitsdauer | 4 |
| Doppelte Palette | 2 |
| Gebinde ohne Tara | 1 |
| Zettel doppelt | 1 |
| Verdunstung zu hoch | 1 |
| Lieferung über Eingang | 1 |
| Lieferung ohne Eingang | 1 |
| Arbeit ohne Eingang | 1 |
| Lieferung vor Eingang | 1 |
| Sortierlauf ohne Eingang | 1 |
| Lieferung ohne Charge | 1 |

## Schwere hoch (9)

- **Arbeit ohne Eingang** · Arbeit 1602 (waschen_sortieren, Charge 1627, 2026-10-01)
  - Eine Arbeit an einer Charge, von der keine Palette im Erntejournal steht.
  - _charge_nr = 1627_
- **Lieferung ohne Eingang** · Charge 1627
  - Lieferungen für eine Charge, von der keine Palette im Erntejournal steht — Journal unvollständig oder falsche Chargennummer auf dem Lieferschein.
  - _geliefert_kg = 168_
- **Lieferung über Eingang** · Charge 1626
  - Mehr ausgeliefert als eingegangen (7444 gegen 4862.8 kg netto). Eingang fehlt im Journal, oder Lieferungen tragen die falsche Charge.
  - _geliefert_kg = 7444 · eingang_netto_kg = 4862.8_
- **Lieferung vor Eingang** · Charge 1626
  - 7 Lieferungen (7156 kg) vom 2026-09-02 bis 2026-09-22, aber die erste Palette dieser Charge kam laut Journal erst am 2026-09-23 — im Journal fehlt der frühere Eingang, oder die Lieferscheine tragen die falsche Charge.
  - _lieferungen = 7 · kg = 7156 · von = 2026-09-02 · bis = 2026-09-22 · erster_eingang = 2026-09-23_
- **Sortierlauf ohne Eingang** · Sortierlauf 173 · Charge 1637 · 2026-09-05
  - Eine Sortierdatei mit 4522 Kürbissen zu einer Charge, von der keine Palette im Journal steht — der Eingang fehlt, oder die Datei gehört zu einer anderen Charge dieser Sorte (1607, 1625).
  - _n_gueltig = 4522 · charge_nr = 1637 · chargen_derselben_sorte_mit_eingang = 1607, 1625_
- **Teilpalette mit vollem Zettel** · Zettel 2986 · Arbeit 1576 (waschen_sortieren, Charge 1632, 2026-09-23) · 2026-09-15
  - 36 von 40 Kisten der Palette 7656, aber das Zettelgewicht der ganzen Palette (510 kg). Anteilig wären es 459 kg — oder die Kistenzahl ist vertippt. Die Verdunstungswägung dazu rechnet mit zu viel Anfangsgewicht und zählt so nicht.
  - _zettel_kg = 510 · kisten_zettel = 36 · palette = 7656 · kisten_palette = 40 · anteilig_kg = 459_
- **Teilpalette mit vollem Zettel** · Zettel 3024 · Arbeit 1584 (waschen_sortieren, Charge 1651, 2026-09-24) · 2026-09-03
  - 16 von 36 Kisten der Palette 7225, aber das Zettelgewicht der ganzen Palette (473 kg). Anteilig wären es 210.2 kg — oder die Kistenzahl ist vertippt. Die Verdunstungswägung dazu rechnet mit zu viel Anfangsgewicht und zählt so nicht.
  - _zettel_kg = 473 · kisten_zettel = 16 · palette = 7225 · kisten_palette = 36 · anteilig_kg = 210.2_
- **Teilpalette mit vollem Zettel** · Zettel 3041 · Arbeit 1588 (waschen_sortieren, Charge 1617, 2026-09-26) · 2026-08-26
  - 56 von 60 Kisten der Palette 6943, aber das Zettelgewicht der ganzen Palette (581 kg). Anteilig wären es 542.3 kg — oder die Kistenzahl ist vertippt. Die Verdunstungswägung dazu rechnet mit zu viel Anfangsgewicht und zählt so nicht.
  - _zettel_kg = 581 · kisten_zettel = 56 · palette = 6943 · kisten_palette = 60 · anteilig_kg = 542.3_
- **Teilpalette mit vollem Zettel** · Zettel 3085 · Arbeit 1600 (waschen_sortieren, Charge 1632, 2026-10-01) · 2026-09-14
  - 28 von 36 Kisten der Palette 7613, aber das Zettelgewicht der ganzen Palette (460 kg). Anteilig wären es 357.8 kg — oder die Kistenzahl ist vertippt. Die Verdunstungswägung dazu rechnet mit zu viel Anfangsgewicht und zählt so nicht.
  - _zettel_kg = 460 · kisten_zettel = 28 · palette = 7613 · kisten_palette = 36 · anteilig_kg = 357.8_

## Schwere mittel (59)

- **Gebinde ohne Tara** · Gebindeart Holz Palox
  - 18 Paletten (5622 kg brutto) in einem Gebinde, dessen Leergewicht die Stammdaten nicht kennen — ihr Netto ist geschätzt, nicht gewogen. Unter Betrieb → Stammdaten die Tara eintragen; ein Palox zählt als eine „Kiste" mit seinem eigenen Leergewicht.
  - _paletten = 18 · brutto_kg = 5622 · chargen = 1638_
- **Lieferung ohne Charge** · Lieferungen
  - 16 Lieferungen ohne Chargennummer — sie fehlen in jeder Chargenbilanz und im „Wohin" je Sorte. Unter Betrieb → Warenausgang die Charge nachtragen.
  - _lieferungen = 16 · kg = 2684 · von = 2026-09-05 · bis = 2026-09-29_
- **Schwerer geworden** · Wägung 268 · Arbeit 1605 (waschen_sortieren, Charge 1648, 2026-10-05) · Charge 1648
  - Die Palette ist schwerer geworden — Zettel und Waage vertauscht, oder eine andere Palette gewogen.
  - _netto_damals_kg = 340 · netto_jetzt_kg = 405 · tage = 48_
- **Schwerer geworden** · Wägung 269 · Arbeit 1605 (waschen_sortieren, Charge 1648, 2026-10-05) · Charge 1648
  - Die Palette ist schwerer geworden — Zettel und Waage vertauscht, oder eine andere Palette gewogen.
  - _netto_damals_kg = 339 · netto_jetzt_kg = 398 · tage = 48_
- **Schwerer geworden** · Wägung 270 · Arbeit 1605 (waschen_sortieren, Charge 1648, 2026-10-05) · Charge 1648
  - Die Palette ist schwerer geworden — Zettel und Waage vertauscht, oder eine andere Palette gewogen.
  - _netto_damals_kg = 342 · netto_jetzt_kg = 400 · tage = 48_
- **Schwerer geworden** · Wägung 291 · Arbeit 1611 (waschen_sortieren, Charge 1611, 2026-10-06) · Charge 1611
  - Die Palette ist schwerer geworden — Zettel und Waage vertauscht, oder eine andere Palette gewogen.
  - _netto_damals_kg = 356.5 · netto_jetzt_kg = 388.5 · tage = 18_
- **Schwerer geworden** · Wägung 302 · Arbeit 1616 (waschen_sortieren, Charge 1635, 2026-10-08) · Charge 1635
  - Die Palette ist schwerer geworden — Zettel und Waage vertauscht, oder eine andere Palette gewogen.
  - _netto_damals_kg = 349 · netto_jetzt_kg = 354 · tage = 31_
- **Teilpalette mit vollem Zettel** · Zettel 2973 · Arbeit 1577 (sortieren, Charge 1630, 2026-09-23) · 2026-08-13
  - 32 von 40 Kisten der Palette 6567, aber das Zettelgewicht der ganzen Palette (530 kg). Anteilig wären es 424 kg — oder die Kistenzahl ist vertippt.
  - _zettel_kg = 530 · kisten_zettel = 32 · palette = 6567 · kisten_palette = 40 · anteilig_kg = 424_
- **Teilpalette mit vollem Zettel** · Zettel 2985 · Arbeit 1576 (waschen_sortieren, Charge 1632, 2026-09-23) · 2026-09-15
  - 28 von 36 Kisten der Palette 7618, aber das Zettelgewicht der ganzen Palette (466 kg). Anteilig wären es 362.4 kg — oder die Kistenzahl ist vertippt.
  - _zettel_kg = 466 · kisten_zettel = 28 · palette = 7618 · kisten_palette = 36 · anteilig_kg = 362.4_
- **Teilpalette mit vollem Zettel** · Zettel 3264 · Arbeit 1623 (sortieren, Charge 1616, 2026-10-10) · 2026-07-30
  - 36 von 40 Kisten der Palette 6482, aber das Zettelgewicht der ganzen Palette (485 kg). Anteilig wären es 436.5 kg — oder die Kistenzahl ist vertippt.
  - _zettel_kg = 485 · kisten_zettel = 36 · palette = 6482 · kisten_palette = 40 · anteilig_kg = 436.5_
- **Teilpalette mit vollem Zettel** · Zettel 3265 · Arbeit 1623 (sortieren, Charge 1616, 2026-10-10) · 2026-07-30
  - 36 von 40 Kisten der Palette 6481, aber das Zettelgewicht der ganzen Palette (483 kg). Anteilig wären es 434.7 kg — oder die Kistenzahl ist vertippt.
  - _zettel_kg = 483 · kisten_zettel = 36 · palette = 6481 · kisten_palette = 40 · anteilig_kg = 434.7_
- **Teilpalette mit vollem Zettel** · Zettel 3279 · Arbeit 1623 (sortieren, Charge 1616, 2026-10-10) · 2026-07-30
  - 36 von 40 Kisten der Palette 6466, aber das Zettelgewicht der ganzen Palette (488 kg). Anteilig wären es 439.2 kg — oder die Kistenzahl ist vertippt.
  - _zettel_kg = 488 · kisten_zettel = 36 · palette = 6466 · kisten_palette = 40 · anteilig_kg = 439.2_
- **Teilpalette mit vollem Zettel** · Zettel 3282 · Arbeit 1623 (sortieren, Charge 1616, 2026-10-10) · 2026-07-30
  - 36 von 40 Kisten der Palette 6465, aber das Zettelgewicht der ganzen Palette (482 kg). Anteilig wären es 433.8 kg — oder die Kistenzahl ist vertippt.
  - _zettel_kg = 482 · kisten_zettel = 36 · palette = 6465 · kisten_palette = 40 · anteilig_kg = 433.8_
- **Teilpalette mit vollem Zettel** · Zettel 3284 · Arbeit 1623 (sortieren, Charge 1616, 2026-10-10) · 2026-07-27
  - 36 von 40 Kisten der Palette 6420, aber das Zettelgewicht der ganzen Palette (480 kg). Anteilig wären es 432 kg — oder die Kistenzahl ist vertippt.
  - _zettel_kg = 480 · kisten_zettel = 36 · palette = 6420 · kisten_palette = 40 · anteilig_kg = 432_
- **Teilpalette von Hand umgerechnet** · Zettel 2950 · Arbeit 1569 (waschen_sortieren, Charge 1650, 2026-09-21) · 2026-09-08
  - 235 kg für 18 Kisten ist 470 kg × 18/36 — eine Teilpalette, von Hand im Dreisatz umgerechnet (Palette 7384 oder 6 weitere). Die App findet die Palette so nicht und rechnet mit Kisten × Tara; die Verdunstung dieser Palette bleibt ohne Bezug.
  - _zettel_kg = 235 · kisten_zettel = 18 · palette = 7384 · palette_kg = 470 · kisten_palette = 36 · dreisatz_kg = 235 · moegliche_paletten = 7_
- **Teilpalette von Hand umgerechnet** · Zettel 2958 · Arbeit 1573 (waschen_sortieren, Charge 1651, 2026-09-22) · 2026-09-03
  - 237 kg für 18 Kisten ist 473 kg × 18/36 — eine Teilpalette, von Hand im Dreisatz umgerechnet (Palette 7225 oder 5 weitere). Die App findet die Palette so nicht und rechnet mit Kisten × Tara; die Verdunstung dieser Palette bleibt ohne Bezug.
  - _zettel_kg = 237 · kisten_zettel = 18 · palette = 7225 · palette_kg = 473 · kisten_palette = 36 · dreisatz_kg = 236.5 · moegliche_paletten = 6_
- **Teilpalette von Hand umgerechnet** · Zettel 3000 · Arbeit 1579 (waschen_sortieren, Charge 1632, 2026-09-23) · 2026-09-15
  - 258 kg für 19 Kisten ist 487 kg × 19/36 — eine Teilpalette, von Hand im Dreisatz umgerechnet (Palette 7631 oder 8 weitere). Die App findet die Palette so nicht und rechnet mit Kisten × Tara; die Verdunstung dieser Palette bleibt ohne Bezug.
  - _zettel_kg = 258 · kisten_zettel = 19 · palette = 7631 · palette_kg = 487 · kisten_palette = 36 · dreisatz_kg = 257 · moegliche_paletten = 9_
- **Teilpalette von Hand umgerechnet** · Zettel 3025 · Arbeit 1585 (waschen_sortieren, Charge 1650, 2026-09-24) · 2026-09-08
  - 232 kg für 18 Kisten ist 466 kg × 18/36 — eine Teilpalette, von Hand im Dreisatz umgerechnet (Palette 7386 oder 2 weitere). Die App findet die Palette so nicht und rechnet mit Kisten × Tara; die Verdunstung dieser Palette bleibt ohne Bezug.
  - _zettel_kg = 232 · kisten_zettel = 18 · palette = 7386 · palette_kg = 466 · kisten_palette = 36 · dreisatz_kg = 233 · moegliche_paletten = 3_
- **Teilpalette von Hand umgerechnet** · Zettel 3029 · Arbeit 1585 (waschen_sortieren, Charge 1650, 2026-09-24) · 2026-09-08
  - 221 kg für 17 Kisten ist 470 kg × 17/36 — eine Teilpalette, von Hand im Dreisatz umgerechnet (Palette 7384 oder 5 weitere). Die App findet die Palette so nicht und rechnet mit Kisten × Tara; die Verdunstung dieser Palette bleibt ohne Bezug.
  - _zettel_kg = 221 · kisten_zettel = 17 · palette = 7384 · palette_kg = 470 · kisten_palette = 36 · dreisatz_kg = 221.9 · moegliche_paletten = 6_
- **Teilpalette von Hand umgerechnet** · Zettel 3131 · Arbeit 1608 (waschen_sortieren, Charge 1631, 2026-10-05) · 2026-09-22
  - 140 kg für 12 Kisten ist 419 kg × 12/36 — eine Teilpalette, von Hand im Dreisatz umgerechnet (Palette 7945 oder 2 weitere). Die App findet die Palette so nicht und rechnet mit Kisten × Tara; die Verdunstung dieser Palette bleibt ohne Bezug.
  - _zettel_kg = 140 · kisten_zettel = 12 · palette = 7945 · palette_kg = 419 · kisten_palette = 36 · dreisatz_kg = 139.7 · moegliche_paletten = 3_
- **Verdunstung zu hoch** · Wägung 265 · Arbeit 1603 (waschen_sortieren, Charge 1623, 2026-10-01) · Charge 1623
  - 1.2 % je Tag ist keine Verdunstung. Keine Teilpalette erkennbar (keine Eingangskisten bekannt oder gleich viele) — Kisten gewechselt, Zahlendreher, oder doch eine halbe Palette ohne Verknüpfung zum Eingang?
  - _netto_damals_kg = 58 · netto_jetzt_kg = 38 · tage = 34 · rate_je_tag = 0.012_
- **Zettel doppelt** · Arbeit 1577 (sortieren, Charge 1630, 2026-09-23) · 530 kg
  - 2 Zettel mit 530 kg in dieser Arbeit, aber die Charge hat nur 1 Palette(n) mit diesem Gewicht — dieselbe Palette zweimal gezählt?
  - _zettel = 2 · paletten_im_journal = 1_
- **Zettel Kistenzahl** · Zettel 2947 · Arbeit 1569 (waschen_sortieren, Charge 1650, 2026-09-21) · 2026-09-11
  - Gleiches Gewicht wie Palette 7482 (2026-09-11), aber 36 statt 34 Kisten — Kistenzahl vertippt?
  - _zettel_kg = 445 · kisten_zettel = 36 · palette = 7482 · kisten_palette = 34_
- **Zettel Kistenzahl** · Zettel 3044 · Arbeit 1589 (waschen_sortieren, Charge 1613, 2026-09-26) · 2026-09-15
  - Gleiches Gewicht wie Palette 6764 (2026-08-24), aber 40 statt 36 Kisten — Kistenzahl vertippt?
  - _zettel_kg = 505 · kisten_zettel = 40 · palette = 6764 · kisten_palette = 36_
- **Zettel Kistenzahl** · Zettel 3118 · Arbeit 1607 (waschen_sortieren, Charge 1648, 2026-10-05) · 2026-08-18
  - Gleiches Gewicht wie Palette 6673 (2026-08-18), aber 36 statt 32 Kisten — Kistenzahl vertippt?
  - _zettel_kg = 411 · kisten_zettel = 36 · palette = 6673 · kisten_palette = 32_
- **Zettel Kistenzahl** · Zettel 3119 · Arbeit 1607 (waschen_sortieren, Charge 1648, 2026-10-05) · 2026-08-18
  - Gleiches Gewicht wie Palette 6669 (2026-08-18), aber 36 statt 32 Kisten — Kistenzahl vertippt?
  - _zettel_kg = 415 · kisten_zettel = 36 · palette = 6669 · kisten_palette = 32_
- **Zettel Kistenzahl** · Zettel 3173 · Arbeit 1616 (waschen_sortieren, Charge 1635, 2026-10-08) · 2026-09-07
  - Gleiches Gewicht wie Palette 7308 (2026-09-07), aber 36 statt 32 Kisten — Kistenzahl vertippt?
  - _zettel_kg = 428 · kisten_zettel = 36 · palette = 7308 · kisten_palette = 32_
- **Zettel Kistenzahl** · Zettel 3176 · Arbeit 1616 (waschen_sortieren, Charge 1635, 2026-10-08) · 2026-09-07
  - Gleiches Gewicht wie Palette 7309 (2026-09-07), aber 36 statt 32 Kisten — Kistenzahl vertippt?
  - _zettel_kg = 443 · kisten_zettel = 36 · palette = 7309 · kisten_palette = 32_
- **Zetteldatum ohne Palette** · Zettel 3042 · Arbeit 1589 (waschen_sortieren, Charge 1613, 2026-09-26)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-15 · tage_der_charge = 2026-08-14, 2026-08-19, 2026-08-24, 2026-08-26, 2026-08-27, 2026-08-29, 2026-09-01, 2026-09-29, 2026-10-02_
- **Zetteldatum ohne Palette** · Zettel 3043 · Arbeit 1589 (waschen_sortieren, Charge 1613, 2026-09-26)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-15 · tage_der_charge = 2026-08-14, 2026-08-19, 2026-08-24, 2026-08-26, 2026-08-27, 2026-08-29, 2026-09-01, 2026-09-29, 2026-10-02_
- **Zetteldatum ohne Palette** · Zettel 3044 · Arbeit 1589 (waschen_sortieren, Charge 1613, 2026-09-26)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-15 · tage_der_charge = 2026-08-14, 2026-08-19, 2026-08-24, 2026-08-26, 2026-08-27, 2026-08-29, 2026-09-01, 2026-09-29, 2026-10-02_
- **Zetteldatum ohne Palette** · Zettel 3076 · Arbeit 1597 (sortieren, Charge 1611, 2026-09-30)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-08 · tage_der_charge = 2026-09-17, 2026-09-18, 2026-09-19, 2026-09-21, 2026-09-22_
- **Zetteldatum ohne Palette** · Zettel 3077 · Arbeit 1597 (sortieren, Charge 1611, 2026-09-30)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-08 · tage_der_charge = 2026-09-17, 2026-09-18, 2026-09-19, 2026-09-21, 2026-09-22_
- **Zetteldatum ohne Palette** · Zettel 3132 · Arbeit 1609 (waschen_sortieren, Charge 1638, 2026-10-06)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-15 · tage_der_charge = 2026-08-20, 2026-08-25, 2026-09-10_
- **Zetteldatum ohne Palette** · Zettel 3133 · Arbeit 1609 (waschen_sortieren, Charge 1638, 2026-10-06)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-15 · tage_der_charge = 2026-08-20, 2026-08-25, 2026-09-10_
- **Zetteldatum ohne Palette** · Zettel 3134 · Arbeit 1609 (waschen_sortieren, Charge 1638, 2026-10-06)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-15 · tage_der_charge = 2026-08-20, 2026-08-25, 2026-09-10_
- **Zetteldatum ohne Palette** · Zettel 3135 · Arbeit 1609 (waschen_sortieren, Charge 1638, 2026-10-06)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-15 · tage_der_charge = 2026-08-20, 2026-08-25, 2026-09-10_
- **Zetteldatum ohne Palette** · Zettel 3177 · Arbeit 1596 (sortieren, Charge 1611, 2026-09-30)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-14 · tage_der_charge = 2026-09-17, 2026-09-18, 2026-09-19, 2026-09-21, 2026-09-22_
- **Zetteldatum ohne Palette** · Zettel 3221 · Arbeit 1619 (waschen_sortieren, Charge 1626, 2026-10-08)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-08-31 · tage_der_charge = 2026-09-23_
- **Zetteldatum ohne Palette** · Zettel 3222 · Arbeit 1619 (waschen_sortieren, Charge 1626, 2026-10-08)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-08-31 · tage_der_charge = 2026-09-23_
- **Zetteldatum ohne Palette** · Zettel 3223 · Arbeit 1619 (waschen_sortieren, Charge 1626, 2026-10-08)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-08-31 · tage_der_charge = 2026-09-23_
- **Zetteldatum ohne Palette** · Zettel 3224 · Arbeit 1619 (waschen_sortieren, Charge 1626, 2026-10-08)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-08-31 · tage_der_charge = 2026-09-23_
- **Zetteldatum ohne Palette** · Zettel 3225 · Arbeit 1619 (waschen_sortieren, Charge 1626, 2026-10-08)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-08-31 · tage_der_charge = 2026-09-23_
- **Zetteldatum ohne Palette** · Zettel 3226 · Arbeit 1619 (waschen_sortieren, Charge 1626, 2026-10-08)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-08-31 · tage_der_charge = 2026-09-23_
- **Zetteldatum ohne Palette** · Zettel 3227 · Arbeit 1619 (waschen_sortieren, Charge 1626, 2026-10-08)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-08-31 · tage_der_charge = 2026-09-23_
- **Zetteldatum ohne Palette** · Zettel 3228 · Arbeit 1619 (waschen_sortieren, Charge 1626, 2026-10-08)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-08-31 · tage_der_charge = 2026-09-23_
- **Zettelgewicht** · Zettel 3024 · Arbeit 1584 (waschen_sortieren, Charge 1651, 2026-09-24) · 2026-09-03
  - 26.5 kg je Kiste laut Zettel gegen 10.9 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 473 · kisten_angenommen = 16 · netto_je_kiste_kg = 26.5 · charge_mittel_je_kiste_kg = 10.9_
- **Zettelgewicht** · Zettel 3101 · Arbeit 1603 (waschen_sortieren, Charge 1623, 2026-10-01) · 2026-08-28
  - 14.5 kg je Kiste laut Zettel gegen 9.9 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 89 · kisten_angenommen = 4 · netto_je_kiste_kg = 14.5 · charge_mittel_je_kiste_kg = 9.9_
- **Zettelgewicht** · Zettel 3132 · Arbeit 1609 (waschen_sortieren, Charge 1638, 2026-10-06) · 2026-09-15
  - 286.5 kg je Kiste laut Zettel gegen 11.5 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 313 · kisten_angenommen = 1 · netto_je_kiste_kg = 286.5 · charge_mittel_je_kiste_kg = 11.5_
- **Zettelgewicht** · Zettel 3133 · Arbeit 1609 (waschen_sortieren, Charge 1638, 2026-10-06) · 2026-09-15
  - 273.5 kg je Kiste laut Zettel gegen 11.5 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 300 · kisten_angenommen = 1 · netto_je_kiste_kg = 273.5 · charge_mittel_je_kiste_kg = 11.5_
- **Zettelgewicht** · Zettel 3134 · Arbeit 1609 (waschen_sortieren, Charge 1638, 2026-10-06) · 2026-09-15
  - 271.5 kg je Kiste laut Zettel gegen 11.5 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 298 · kisten_angenommen = 1 · netto_je_kiste_kg = 271.5 · charge_mittel_je_kiste_kg = 11.5_
- **Zettelgewicht** · Zettel 3135 · Arbeit 1609 (waschen_sortieren, Charge 1638, 2026-10-06) · 2026-09-15
  - 285.5 kg je Kiste laut Zettel gegen 11.5 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 312 · kisten_angenommen = 1 · netto_je_kiste_kg = 285.5 · charge_mittel_je_kiste_kg = 11.5_
- **Zettelgewicht** · Zettel 3162 · Arbeit 1613 (waschen_sortieren, Charge 1638, 2026-10-07) · 2026-09-10
  - 271.5 kg je Kiste laut Zettel gegen 11.5 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 298 · kisten_angenommen = 1 · netto_je_kiste_kg = 271.5 · charge_mittel_je_kiste_kg = 11.5_
- **Zettelgewicht** · Zettel 3163 · Arbeit 1613 (waschen_sortieren, Charge 1638, 2026-10-07) · 2026-09-10
  - 279.5 kg je Kiste laut Zettel gegen 11.5 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 306 · kisten_angenommen = 1 · netto_je_kiste_kg = 279.5 · charge_mittel_je_kiste_kg = 11.5_
- **Zettelgewicht** · Zettel 3164 · Arbeit 1613 (waschen_sortieren, Charge 1638, 2026-10-07) · 2026-09-10
  - 133.5 kg je Kiste laut Zettel gegen 11.5 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 160 · kisten_angenommen = 1 · netto_je_kiste_kg = 133.5 · charge_mittel_je_kiste_kg = 11.5_
- **Zettelgewicht** · Zettel 3165 · Arbeit 1613 (waschen_sortieren, Charge 1638, 2026-10-07) · 2026-09-10
  - 288.5 kg je Kiste laut Zettel gegen 11.5 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 315 · kisten_angenommen = 1 · netto_je_kiste_kg = 288.5 · charge_mittel_je_kiste_kg = 11.5_
- **Zettelgewicht** · Zettel 3166 · Arbeit 1613 (waschen_sortieren, Charge 1638, 2026-10-07) · 2026-09-10
  - 289.5 kg je Kiste laut Zettel gegen 11.5 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 316 · kisten_angenommen = 1 · netto_je_kiste_kg = 289.5 · charge_mittel_je_kiste_kg = 11.5_
- **Zettelgewicht** · Zettel 3167 · Arbeit 1613 (waschen_sortieren, Charge 1638, 2026-10-07) · 2026-09-10
  - 277.5 kg je Kiste laut Zettel gegen 11.5 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 304 · kisten_angenommen = 1 · netto_je_kiste_kg = 277.5 · charge_mittel_je_kiste_kg = 11.5_
- **Zettelgewicht** · Zettel 3174 · Arbeit 1616 (waschen_sortieren, Charge 1635, 2026-10-08) · 2026-09-07
  - 5.8 kg je Kiste laut Zettel gegen 11.8 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 200 · kisten_angenommen = 24 · netto_je_kiste_kg = 5.8 · charge_mittel_je_kiste_kg = 11.8_

## Schwere niedrig (14)

- **Arbeit offen** · Arbeit 1578 (waschen_sortieren, Charge 1638, 2026-09-23)
  - Seit 17 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 17_
- **Arbeit offen** · Arbeit 1583 (waschen, Charge 1630, 2026-09-24)
  - Seit 16 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 16_
- **Arbeit offen** · Arbeit 1590 (waschen, Charge 1612, 2026-09-26)
  - Seit 14 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 14_
- **Arbeit offen** · Arbeit 1591 (waschen, Charge 1612, 2026-09-28)
  - Seit 12 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 12_
- **Arbeit offen** · Arbeit 1593 (waschen_sortieren, Charge 1650, 2026-09-28)
  - Seit 12 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 12_
- **Arbeit offen** · Arbeit 1595 (waschen_sortieren, Charge 1617, 2026-09-29)
  - Seit 11 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 11_
- **Arbeit offen** · Arbeit 1596 (sortieren, Charge 1611, 2026-09-30)
  - Seit 10 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 10_
- **Arbeit offen** · Arbeit 1611 (waschen_sortieren, Charge 1611, 2026-10-06)
  - Seit 4 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 4_
- **Arbeitsdauer** · Arbeit 1580 (waschen_sortieren, Charge 1617, 2026-09-23)
  - 20.3 Stunden — wohl über Nacht offen geblieben und erst am nächsten Tag abgeschlossen; der Durchsatz je Stunde stimmt dann nicht.
  - _stunden = 20.3_
- **Arbeitsdauer** · Arbeit 1597 (sortieren, Charge 1611, 2026-09-30)
  - 28.4 Stunden — wohl über Nacht offen geblieben und erst am nächsten Tag abgeschlossen; der Durchsatz je Stunde stimmt dann nicht.
  - _stunden = 28.4_
- **Arbeitsdauer** · Arbeit 1617 (sortieren, Charge 1632, 2026-10-08)
  - 27.3 Stunden — wohl über Nacht offen geblieben und erst am nächsten Tag abgeschlossen; der Durchsatz je Stunde stimmt dann nicht.
  - _stunden = 27.3_
- **Arbeitsdauer** · Arbeit 1620 (sortieren, Charge 1632, 2026-10-09)
  - 19.9 Stunden — wohl über Nacht offen geblieben und erst am nächsten Tag abgeschlossen; der Durchsatz je Stunde stimmt dann nicht.
  - _stunden = 19.9_
- **Doppelte Palette** · Charge 1638 · 2026-09-10
  - 18 Paletten an einem Tag, davon 25 Paare mit gleichem Gewicht und gleicher Kistenzahl — der Zufall erklärt etwa 7.7. Abgeschrieben statt gewogen, oder Zeilen doppelt erfasst? (4×318 kg/1, 4×315 kg/1, 4×300 kg/1, 4×313 kg/1, 2×319 kg/1)
  - _paletten = 18 · paare_gleich = 25 · paare_durch_zufall = 7.7 · gleich = 4×318 kg/1, 4×315 kg/1, 4×300 kg/1, 4×313 kg/1, 2×319 kg/1_
- **Doppelte Palette** · Charge 1649 · 2026-09-08
  - 46 Paletten an einem Tag, davon 30 Paare mit gleichem Gewicht und gleicher Kistenzahl — der Zufall erklärt etwa 13. Abgeschrieben statt gewogen, oder Zeilen doppelt erfasst? (3×435 kg/36, 4×434 kg/36, 3×445 kg/36, 3×438 kg/36, 4×448 kg/36, 3×446 kg/36, 3×449 kg/36, 3×437 kg/36)
  - _paletten = 46 · paare_gleich = 30 · paare_durch_zufall = 13 · gleich = 3×435 kg/36, 4×434 kg/36, 3×445 kg/36, 3×438 kg/36, 4×448 kg/36, 3×446 kg/36, 3×449 kg/36, 3×437 kg/36_

