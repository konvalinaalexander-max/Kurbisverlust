# Auffälligkeiten der Messungen

_Abzug vom 2026-09-28. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Was die Auswertung nicht in die Rechnung nimmt, weil es nicht zu seinem Nenner passt. Für die nächste Runde: Wo entsteht das im Ablauf oder in der Maske? Was ist ein Datenfehler, der dem Betrieb gehört? Was könnte die App besser abfangen?

## Nach Art (31)

| Art | Anzahl |
|---|---|
| Zettelgewicht | 12 |
| Ausschuss | 6 |
| Überzählung | 3 |
| Ohne Nenner | 2 |
| Kistengewicht | 2 |
| Palox geleert | 1 |
| Wägung | 1 |
| Zetteldatum | 1 |
| Tara fehlt | 1 |
| Palette fraglich | 1 |
| Verdunstung | 1 |

## Einzeln

- **Ohne Nenner** · Charge 1612 — Slowgrow Uster · Butterkin · Waschen · 28.09.2026, 07:33 · läuft · Charge 1612 — Slowgrow Uster · Butterkin · Arbeit 1591
  - 250 kg Faules erfasst, aber keine Kiste gezählt und keine Menge eingetragen — die Messung hat keinen Nenner und fliesst nirgends ein
  - _Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich selbst) oder die verarbeitete Menge in kg nachtragen._
- **Kistengewicht** · Charge 1612 — Slowgrow Uster · Butterkin · Waschen · 28.09.2026, 07:33 · läuft · Charge 1612 — Slowgrow Uster · Butterkin · Arbeit 1591
  - 3 Paletten mit 96 Kisten gezählt, aber für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt, die Menge dieser Arbeit damit auch
  - _Bei der nächsten Wasch-Arbeit dieses Kalibers die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen — dann kennt die App das Kistengewicht des Bandes, rückwirkend auch für diese Arbeit._
- **Ohne Nenner** · Charge 1612 — Slowgrow Uster · Butterkin · Waschen · 26.09.2026, 09:23 · läuft · Charge 1612 — Slowgrow Uster · Butterkin · Arbeit 1590
  - 173 kg Faules erfasst, aber keine Kiste gezählt und keine Menge eingetragen — die Messung hat keinen Nenner und fliesst nirgends ein
  - _Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich selbst) oder die verarbeitete Menge in kg nachtragen._
- **Kistengewicht** · Charge 1612 — Slowgrow Uster · Butterkin · Waschen · 26.09.2026, 09:23 · läuft · Charge 1612 — Slowgrow Uster · Butterkin · Arbeit 1590
  - 2 Paletten mit 58 Kisten gezählt, aber für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt, die Menge dieser Arbeit damit auch
  - _Bei der nächsten Wasch-Arbeit dieses Kalibers die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen — dann kennt die App das Kistengewicht des Bandes, rückwirkend auch für diese Arbeit._
- **Zetteldatum** · Charge 1613 — Slowgrow Uster · Tiana · Waschen + Sortieren · 26.09.2026, 08:06 · fertig · Charge 1613 — Slowgrow Uster · Tiana · Arbeit 1589
  - 2 Palette(n) mit Zetteldatum 15.09.2026 gezählt, aber an dem Tag kam keine Palette dieser Charge
  - _Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang._
- **Zettelgewicht** · Charge 1613 — Slowgrow Uster · Tiana · Waschen + Sortieren · 26.09.2026, 08:06 · fertig · Charge 1613 — Slowgrow Uster · Tiana · Arbeit 1589
  - 1 Palette(n) mit 175.00 kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)
  - _Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal)._
- **Zettelgewicht** · Charge 1613 — Slowgrow Uster · Tiana · Waschen + Sortieren · 26.09.2026, 08:06 · fertig · Charge 1613 — Slowgrow Uster · Tiana · Arbeit 1589
  - 1 Palette(n) mit 468.00 kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)
  - _Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal)._
- **Zettelgewicht** · Charge 1613 — Slowgrow Uster · Tiana · Waschen + Sortieren · 26.09.2026, 08:06 · fertig · Charge 1613 — Slowgrow Uster · Tiana · Arbeit 1589
  - 1 Palette(n) mit 505.00 kg vom Zettel und Eingangsdatum 15.09.2026 gezählt. Eine Palette dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — gerechnet wird deshalb mit der mittleren Tara der Charge, nicht mit ihrer eigenen.
  - _Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang._
- **Zettelgewicht** · Charge 1650 — Rümlang Sauter · Tiana · Waschen + Sortieren · 24.09.2026, 15:25 · fertig · Charge 1650 — Rümlang Sauter · Tiana · Arbeit 1585
  - 1 Palette(n) mit 221.00 kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)
  - _Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal)._
- **Zettelgewicht** · Charge 1650 — Rümlang Sauter · Tiana · Waschen + Sortieren · 24.09.2026, 15:25 · fertig · Charge 1650 — Rümlang Sauter · Tiana · Arbeit 1585
  - 1 Palette(n) mit 232.00 kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)
  - _Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal)._
- **Zettelgewicht** · Charge 1650 — Rümlang Sauter · Tiana · Waschen + Sortieren · 24.09.2026, 15:25 · fertig · Charge 1650 — Rümlang Sauter · Tiana · Arbeit 1585
  - 1 Palette(n) mit 456.00 kg vom Zettel und Eingangsdatum 08.09.2026 gezählt. Eine Palette dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — gerechnet wird deshalb mit der mittleren Tara der Charge, nicht mit ihrer eigenen.
  - _Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang._
- **Wägung** · Charge 1651 — Rümlang Sauter · Kaori Kuri · Waschen + Sortieren · 24.09.2026, 13:36 · fertig · Charge 1651 — Rümlang Sauter · Kaori Kuri · Arbeit 1584
  - Palette gewogen, aber sie ist nicht verwertbar — sie zählt nicht in die Verdunstungsrate
  - _Eingangsdatum und Gewichte der Wägung prüfen._
- **Verdunstung** · Charge 1651 — Rümlang Sauter · Kaori Kuri · Waschen + Sortieren · 24.09.2026, 13:36 · fertig · Charge 1651 — Rümlang Sauter · Kaori Kuri · Arbeit 1584
  - 4.80 % je Tag: 424 kg → 151 kg in 21 Tagen — so schnell verdunstet kein Kürbis (Grenze 1.00 % je Tag)
  - _Zettelgewicht, Kisten und Gebinde dieser Wägung prüfen — oder es ist eine andere Palette. Bis zur Korrektur zählt sie nicht in die Rate._
- **Zettelgewicht** · Charge 1651 — Rümlang Sauter · Kaori Kuri · Waschen + Sortieren · 24.09.2026, 13:36 · fertig · Charge 1651 — Rümlang Sauter · Kaori Kuri · Arbeit 1584
  - 1 Palette(n) mit 498.00 kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)
  - _Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal)._
- **Palette fraglich** · Charge 1651 — Rümlang Sauter · Kaori Kuri · Waschen + Sortieren · 24.09.2026, 13:36 · fertig · Charge 1651 — Rümlang Sauter · Kaori Kuri · Arbeit 1584
  - Zu gross: 44.00 kg brutto in 2 Kiste(n) G2, mit Palette gewogen — davon bleiben 16 kg netto. Eine leere Palette wiegt allein 25.000 kg.
  - _Standen die Kisten direkt auf der Waage? Dann in der Korrektur „mit Palette" abwählen — das Netto rechnet sich von selbst neu._
- **Zettelgewicht** · Charge 1632 — Andi Ball · Tiana · Waschen + Sortieren · 23.09.2026, 16:15 · fertig · Charge 1632 — Andi Ball · Tiana · Arbeit 1579
  - 1 Palette(n) mit 258.00 kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)
  - _Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal)._
- **Zettelgewicht** · Charge 1630 — Rümlang Keller · Kaori Kuri · Sortieren · 23.09.2026, 13:32 · fertig · Charge 1630 — Rümlang Keller · Kaori Kuri · Arbeit 1577
  - 1 Palette(n) mit 429.00 kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)
  - _Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal)._
- **Überzählung** · Charge 1626 — Agasul Rüegg · Tiana
  - Die Lieferungen dieser Charge (5911 kg) brauchen nach der gerechneten Ausbeute (87 % verkaufsfähig) 6806 kg Eingang — erfasst sind 4863 kg, also 1943 kg zu wenig. Geliefert wurde nicht mehr als eingelagert; es wurde mehr geliefert, als die Rechnung aus diesem Eingang erwartet.
  - _Drei Möglichkeiten: Im Erntejournal fehlt eine Palette dieser Charge; ein Lieferschein ist auf die falsche Chargennummer gebucht; oder diese Charge hat weniger Verlust als das Modell annimmt — dann ist „Im Lager" für sie zu klein gerechnet. Die ersten zwei lassen sich nachtragen._
- **Zettelgewicht** · Charge 1651 — Rümlang Sauter · Kaori Kuri · Waschen + Sortieren · 22.09.2026, 07:36 · fertig · Charge 1651 — Rümlang Sauter · Kaori Kuri · Arbeit 1573
  - 1 Palette(n) mit 237.00 kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)
  - _Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal)._
- **Zettelgewicht** · Charge 1651 — Rümlang Sauter · Kaori Kuri · Waschen + Sortieren · 22.09.2026, 07:36 · fertig · Charge 1651 — Rümlang Sauter · Kaori Kuri · Arbeit 1573
  - 1 Palette(n) mit 288.00 kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)
  - _Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal)._
- **Palox geleert** · Charge 1650 — Rümlang Sauter · Tiana · Waschen + Sortieren · 21.09.2026, 14:05 · fertig · Charge 1650 — Rümlang Sauter · Tiana · Arbeit 1569
  - Der Waagenstand fiel von 229.00 auf 55.00 kg — der Palox wurde zwischendurch geleert. Wie viel davor noch dazukam, weiss niemand; das Faule dieser Arbeit ist unbekannt.
  - _Nichts zu korrigieren. Beim nächsten Mal in der Checkliste „Palox leeren" drücken: vor dem Leeren ablesen, danach die leere Box — dann bleibt die Menge bekannt._
- **Zettelgewicht** · Charge 1650 — Rümlang Sauter · Tiana · Waschen + Sortieren · 21.09.2026, 14:05 · fertig · Charge 1650 — Rümlang Sauter · Tiana · Arbeit 1569
  - 1 Palette(n) mit 235.00 kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)
  - _Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal)._
- **Tara fehlt** · Charge 1638 — Klaus Böhler · Kaori Kuri
  - 18 von 32 Paletten der Charge haben kein Nettogewicht (5622 kg brutto): für die Gebindeart ist kein Kistengewicht hinterlegt. Für sie rechnet der Eingang mit dem Mittel der übrigen: 7421 der 13193 kg Eingang sind hochgerechnet, nicht gewogen.
  - _Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. Die Zahlen rechnen sich danach von selbst neu._
- **Überzählung** · Charge 1619 — Gossau Eberhard · Kaori Kuri
  - Die Lieferungen dieser Charge (3684 kg) brauchen nach der gerechneten Ausbeute (77 % verkaufsfähig) 4757 kg Eingang — erfasst sind 4281 kg, also 476 kg zu wenig. Geliefert wurde nicht mehr als eingelagert; es wurde mehr geliefert, als die Rechnung aus diesem Eingang erwartet.
  - _Drei Möglichkeiten: Im Erntejournal fehlt eine Palette dieser Charge; ein Lieferschein ist auf die falsche Chargennummer gebucht; oder diese Charge hat weniger Verlust als das Modell annimmt — dann ist „Im Lager" für sie zu klein gerechnet. Die ersten zwei lassen sich nachtragen._
- **Überzählung** · Charge 1614 — Slowgrow Uster · Kaori Kuri
  - Die Lieferungen dieser Charge (8540 kg) brauchen nach der gerechneten Ausbeute (74 % verkaufsfähig) 11527 kg Eingang — erfasst sind 10057 kg, also 1469 kg zu wenig. Geliefert wurde nicht mehr als eingelagert; es wurde mehr geliefert, als die Rechnung aus diesem Eingang erwartet.
  - _Drei Möglichkeiten: Im Erntejournal fehlt eine Palette dieser Charge; ein Lieferschein ist auf die falsche Chargennummer gebucht; oder diese Charge hat weniger Verlust als das Modell annimmt — dann ist „Im Lager" für sie zu klein gerechnet. Die ersten zwei lassen sich nachtragen._
- **Ausschuss** · Charge 1613 — Slowgrow Uster · Tiana · Waschen + Sortieren · 26.09.2026, 08:06 · fertig · Charge 1613 — Slowgrow Uster · Tiana · Arbeit 1589
  - 0 kg zu klein / 22 kg zu gross bei 838 kg Bezugsmasse
  - _Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht._
- **Ausschuss** · Charge 1632 — Andi Ball · Tiana · Waschen + Sortieren · 23.09.2026, 16:15 · fertig · Charge 1632 — Andi Ball · Tiana · Arbeit 1579
  - 0 kg zu klein / 103 kg zu gross bei 920 kg Bezugsmasse
  - _Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht._
- **Ausschuss** · Charge 1632 — Andi Ball · Tiana · Waschen + Sortieren · 23.09.2026, 07:22 · fertig · Charge 1632 — Andi Ball · Tiana · Arbeit 1576
  - 0 kg zu klein / 110 kg zu gross bei 1753 kg Bezugsmasse
  - _Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht._
- **Ausschuss** · Charge 1651 — Rümlang Sauter · Kaori Kuri · Waschen + Sortieren · 24.09.2026, 13:36 · fertig · Charge 1651 — Rümlang Sauter · Kaori Kuri · Arbeit 1584
  - 0 kg zu klein / 16 kg zu gross bei 1414 kg Bezugsmasse
  - _Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht._
- **Ausschuss** · Charge 1650 — Rümlang Sauter · Tiana · Waschen + Sortieren · 24.09.2026, 15:25 · fertig · Charge 1650 — Rümlang Sauter · Tiana · Arbeit 1585
  - 0 kg zu klein / 122 kg zu gross bei 1358 kg Bezugsmasse
  - _Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht._
- **Ausschuss** · Charge 1649 — Rümlang Sauter · Butterkin · Waschen + Sortieren · 22.09.2026, 13:48 · fertig · Charge 1649 — Rümlang Sauter · Butterkin · Arbeit 1574
  - 0 kg zu klein / 154 kg zu gross bei 2153 kg Bezugsmasse
  - _Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht._
