# Plausibilitätsdurchgang

_Stand 2026-09-28 · Quelle docs/betrieb/rohdaten (Betriebsabzug) · von `pruefstand/durchgang.mjs` geschrieben; nicht von Hand ändern._

Jede Zeile ist ein **Kandidat**, kein Urteil: eine Zahl, die so nicht sein kann oder nicht sein sollte, mit dem Grund. Die Runde am Programm liest sie, prüft die Rohzeilen und schreibt die Zweitmeinung; der Betrieb entscheidet.

## Tabellen

| Tabelle | Zeilen |
|---|---|
| charge | 42 |
| palette | 1638 |
| auftrag | 29 |
| auftrag_palette | 104 |
| auftrag_gebinde | 0 |
| schimmel_messung | 50 |
| ausschuss_messung | 16 |
| verdunstung_wiegung | 27 |
| ausgang_wiegung | 29 |
| kontrollpalette | 0 |
| kontrollpalette_wiegung | 0 |
| lieferung | 587 |
| sortier_lauf | 12 |
| gebinde | 6 |
| auswertung_stand | 1 |

_310 Paletten sind Vervielfachungen einer Journalzeile („n Paletten gleich", extern_id …#n) — keine Kandidaten._

## Nach Prüfung (35)

| Prüfung | Anzahl |
|---|---|
| Arbeit offen | 7 |
| Teilpalette von Hand umgerechnet | 5 |
| Teilpalette mit vollem Zettel | 5 |
| Zetteldatum ohne Palette | 3 |
| Doppelte Palette | 2 |
| Zettel Kistenzahl | 2 |
| Arbeit ohne Eingang | 2 |
| Gebinde ohne Tara | 1 |
| Zettelgewicht | 1 |
| Zettel auf fremde Charge | 1 |
| Zettel doppelt | 1 |
| Arbeitsdauer | 1 |
| Lieferung über Eingang | 1 |
| Lieferung vor Eingang | 1 |
| Sortierlauf ohne Eingang | 1 |
| Lieferung ohne Charge | 1 |

## Schwere hoch (9)

- **Arbeit ohne Eingang** · Arbeit 1570 (waschen_sortieren, Charge 1599, 2026-09-21)
  - Eine Arbeit an einer Charge, von der keine Palette im Erntejournal steht.
  - _charge_nr = 1599_
- **Arbeit ohne Eingang** · Arbeit 1571 (waschen_sortieren, Charge 1604, 2026-09-21)
  - Eine Arbeit an einer Charge, von der keine Palette im Erntejournal steht.
  - _charge_nr = 1604_
- **Lieferung über Eingang** · Charge 1626
  - Mehr ausgeliefert als eingegangen (5885 gegen 4862.8 kg netto). Eingang fehlt im Journal, oder Lieferungen tragen die falsche Charge.
  - _geliefert_kg = 5885 · eingang_netto_kg = 4862.8_
- **Lieferung vor Eingang** · Charge 1626
  - 6 Lieferungen (5885 kg) vom 2026-09-02 bis 2026-09-17, aber die erste Palette dieser Charge kam laut Journal erst am 2026-09-23 — im Journal fehlt der frühere Eingang, oder die Lieferscheine tragen die falsche Charge.
  - _lieferungen = 6 · kg = 5885 · von = 2026-09-02 · bis = 2026-09-17 · erster_eingang = 2026-09-23_
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
- **Zettel auf fremde Charge** · Zettel 3043 · Arbeit 1589 (waschen_sortieren, Charge 1613, 2026-09-26) · 2026-09-15
  - In Charge 1613 gibt es diese Palette nicht — in Charge 1632 (gleiche Sorte) aber genau: 468 kg, 36 Kisten, 2026-09-15. Die Arbeit ist wohl auf die falsche Charge gebucht, oder die Halle hat Paletten der anderen Charge verarbeitet.
  - _zettel_kg = 468 · kisten = 36 · zetteldatum = 2026-09-15 · charge_der_arbeit = 1613 · passt_auf = Palette 7659 (Charge 1632)_

## Schwere mittel (16)

- **Gebinde ohne Tara** · Gebindeart Holz Palox
  - 18 Paletten (5622 kg brutto) in einem Gebinde, dessen Leergewicht die Stammdaten nicht kennen — ihr Netto ist geschätzt, nicht gewogen. Unter Betrieb → Stammdaten die Tara eintragen; ein Palox zählt als eine „Kiste" mit seinem eigenen Leergewicht.
  - _paletten = 18 · brutto_kg = 5622 · chargen = 1638_
- **Lieferung ohne Charge** · Lieferungen
  - 13 Lieferungen ohne Chargennummer — sie fehlen in jeder Chargenbilanz und im „Wohin" je Sorte. Unter Betrieb → Warenausgang die Charge nachtragen.
  - _lieferungen = 13 · kg = 1660 · von = 2026-09-15 · bis = 2026-09-21_
- **Teilpalette mit vollem Zettel** · Zettel 2973 · Arbeit 1577 (sortieren, Charge 1630, 2026-09-23) · 2026-08-13
  - 32 von 40 Kisten der Palette 6567, aber das Zettelgewicht der ganzen Palette (530 kg). Anteilig wären es 424 kg — oder die Kistenzahl ist vertippt.
  - _zettel_kg = 530 · kisten_zettel = 32 · palette = 6567 · kisten_palette = 40 · anteilig_kg = 424_
- **Teilpalette mit vollem Zettel** · Zettel 2985 · Arbeit 1576 (waschen_sortieren, Charge 1632, 2026-09-23) · 2026-09-15
  - 28 von 36 Kisten der Palette 7618, aber das Zettelgewicht der ganzen Palette (466 kg). Anteilig wären es 362.4 kg — oder die Kistenzahl ist vertippt.
  - _zettel_kg = 466 · kisten_zettel = 28 · palette = 7618 · kisten_palette = 36 · anteilig_kg = 362.4_
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
- **Zettel doppelt** · Arbeit 1577 (sortieren, Charge 1630, 2026-09-23) · 530 kg
  - 2 Zettel mit 530 kg in dieser Arbeit, aber die Charge hat nur 1 Palette(n) mit diesem Gewicht — dieselbe Palette zweimal gezählt?
  - _zettel = 2 · paletten_im_journal = 1_
- **Zettel Kistenzahl** · Zettel 2947 · Arbeit 1569 (waschen_sortieren, Charge 1650, 2026-09-21) · 2026-09-11
  - Gleiches Gewicht wie Palette 7482 (2026-09-11), aber 36 statt 34 Kisten — Kistenzahl vertippt?
  - _zettel_kg = 445 · kisten_zettel = 36 · palette = 7482 · kisten_palette = 34_
- **Zettel Kistenzahl** · Zettel 3044 · Arbeit 1589 (waschen_sortieren, Charge 1613, 2026-09-26) · 2026-09-15
  - Gleiches Gewicht wie Palette 6764 (2026-08-24), aber 40 statt 36 Kisten — Kistenzahl vertippt?
  - _zettel_kg = 505 · kisten_zettel = 40 · palette = 6764 · kisten_palette = 36_
- **Zetteldatum ohne Palette** · Zettel 3042 · Arbeit 1589 (waschen_sortieren, Charge 1613, 2026-09-26)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-15 · tage_der_charge = 2026-08-14, 2026-08-19, 2026-08-24, 2026-08-26, 2026-08-27, 2026-08-29, 2026-09-01_
- **Zetteldatum ohne Palette** · Zettel 3043 · Arbeit 1589 (waschen_sortieren, Charge 1613, 2026-09-26)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-15 · tage_der_charge = 2026-08-14, 2026-08-19, 2026-08-24, 2026-08-26, 2026-08-27, 2026-08-29, 2026-09-01_
- **Zetteldatum ohne Palette** · Zettel 3044 · Arbeit 1589 (waschen_sortieren, Charge 1613, 2026-09-26)
  - An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.
  - _zetteldatum = 2026-09-15 · tage_der_charge = 2026-08-14, 2026-08-19, 2026-08-24, 2026-08-26, 2026-08-27, 2026-08-29, 2026-09-01_
- **Zettelgewicht** · Zettel 3024 · Arbeit 1584 (waschen_sortieren, Charge 1651, 2026-09-24) · 2026-09-03
  - 26.5 kg je Kiste laut Zettel gegen 10.9 kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.
  - _zettel_brutto_kg = 473 · kisten_angenommen = 16 · netto_je_kiste_kg = 26.5 · charge_mittel_je_kiste_kg = 10.9_

## Schwere niedrig (10)

- **Arbeit offen** · Arbeit 1566 (waschen_sortieren, Charge 1649, 2026-09-21)
  - Seit 7 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 7_
- **Arbeit offen** · Arbeit 1568 (waschen, Charge 1613, 2026-09-21)
  - Seit 7 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 7_
- **Arbeit offen** · Arbeit 1570 (waschen_sortieren, Charge 1599, 2026-09-21)
  - Seit 7 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 7_
- **Arbeit offen** · Arbeit 1571 (waschen_sortieren, Charge 1604, 2026-09-21)
  - Seit 7 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 7_
- **Arbeit offen** · Arbeit 1578 (waschen_sortieren, Charge 1638, 2026-09-23)
  - Seit 5 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 5_
- **Arbeit offen** · Arbeit 1583 (waschen, Charge 1630, 2026-09-24)
  - Seit 4 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 4_
- **Arbeit offen** · Arbeit 1590 (waschen, Charge 1612, 2026-09-26)
  - Seit 2 Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).
  - _tage_offen = 2_
- **Arbeitsdauer** · Arbeit 1580 (waschen_sortieren, Charge 1617, 2026-09-23)
  - 20.3 Stunden — wohl über Nacht offen geblieben und erst am nächsten Tag abgeschlossen; der Durchsatz je Stunde stimmt dann nicht.
  - _stunden = 20.3_
- **Doppelte Palette** · Charge 1638 · 2026-09-10
  - 18 Paletten an einem Tag, davon 25 Paare mit gleichem Gewicht und gleicher Kistenzahl — der Zufall erklärt etwa 7.7. Abgeschrieben statt gewogen, oder Zeilen doppelt erfasst? (4×318 kg/1, 4×315 kg/1, 4×300 kg/1, 4×313 kg/1, 2×319 kg/1)
  - _paletten = 18 · paare_gleich = 25 · paare_durch_zufall = 7.7 · gleich = 4×318 kg/1, 4×315 kg/1, 4×300 kg/1, 4×313 kg/1, 2×319 kg/1_
- **Doppelte Palette** · Charge 1649 · 2026-09-08
  - 46 Paletten an einem Tag, davon 30 Paare mit gleichem Gewicht und gleicher Kistenzahl — der Zufall erklärt etwa 13. Abgeschrieben statt gewogen, oder Zeilen doppelt erfasst? (3×435 kg/36, 4×434 kg/36, 3×445 kg/36, 3×438 kg/36, 4×448 kg/36, 3×446 kg/36, 3×449 kg/36, 3×437 kg/36)
  - _paletten = 46 · paare_gleich = 30 · paare_durch_zufall = 13 · gleich = 3×435 kg/36, 4×434 kg/36, 3×445 kg/36, 3×438 kg/36, 4×448 kg/36, 3×446 kg/36, 3×449 kg/36, 3×437 kg/36_

