# Zweitmeinung zu den Daten der Saison 2026

_Stand 28. September 2026, über den Betriebsabzug vom selben Morgen
(`rohdaten/`, `DURCHGANG.md`, `AUFFAELLIGKEITEN.md`, `MODELLSTAND.md`).
Von der Runde am Programm geschrieben, nicht vom Abzug — die nächste
Zweitmeinung ersetzt diese. Jede Zeile sagt: was ich sehe, was ich
vermute, was zu prüfen ist. Geändert habe ich nichts; das entscheidet der
Betrieb._

Die Saison in Zahlen: 42 Chargen, 1629 Paletten im Erntejournal
(611 t Eingang), 28 Arbeiten, 587 Lieferungen (119 t), 27
Verdunstungswägungen, 12 Sortierdateien, keine Kontrollpalette.

## 1. Was die Rechnung am meisten verzerrt — in dieser Reihenfolge

### 1626 (Tiana): geliefert, bevor die erste Palette kam

Sechs Lieferungen vom 2. bis 17. September (5885 kg). Im Journal steht
die erste Palette dieser Charge am **23. September** (13 Paletten, 4863
kg netto). Was vor dem 23. geliefert wurde, kann aus diesem Eingang
nicht stammen. Zwei Möglichkeiten: Die Ernte dieser Charge vor dem 23.
fehlt im Journal — oder die sechs Lieferscheine tragen die falsche
Chargennummer (eine andere Tiana-Charge lieferte im September: 1613,
1632, 1650). **Prüfen:** Erntejournal 1626 vor dem 23.9.; sonst die
Lieferscheine 2.–17.9. Solange das offen ist, meldet das Dashboard für
1626 „Überzählung" (121 % des Eingangs geliefert) und rechnet die Charge
mit Verlust null.

### 1637 (Amoro): eine Sortierdatei zu einer Charge ohne Eingang

Die Sortierdatei vom 5. September (4522 Kürbisse) ist auf Charge 1637
gebucht. Von 1637 steht keine Palette im Journal, es gibt keine Arbeit
und keine Lieferung. Entweder fehlt die Ernte im Journal, oder die Datei
gehört zu einer der zwei Amoro-Chargen mit Eingang: 1625 (35 Paletten
seit dem 29. Juli) oder 1607 (19 Paletten vom 24./25. Juli). **Prüfen:** Was wurde am 5.9. sortiert? Die Zuordnung
lässt sich in der Warteschlange umhängen.

### Arbeit 1589 (26.9.): auf 1613 gebucht, gezählt wurden Paletten der 1632

Drei Zettel mit Eingangsdatum 15.9. — an dem Tag kam für 1613 nichts
(letzter Eingang 1.9.). Zwei der drei passen aber **genau** auf Paletten
der Charge 1632 vom 15.9.: 468 kg/36 Kisten (Palette 7659) und 505 kg/40
Kisten (Palette 7655). Beide sind Tiana, 1613 vom Schlag Slowgrow Uster,
1632 von Andi Ball. Die Arbeit gehört wohl auf 1632 — oder die Halle hat
an dem Tag Paletten der 1632 unter 1613 gewaschen. Die Verdunstungswägung
248 (468 → 455 kg) zählt dann für die falsche Charge. **Prüfen und
umbuchen** (Charge der Arbeit oder Zettel korrigieren).

### Teilpaletten: die Halle rechnet von Hand um — mal so, mal so

Der Betrieb hat es vorausgesagt („18 Kisten, 200 kg, Zettel 400 kg"). In
den Daten steht es in zwei Formen:

| Form | Zettel | So im Journal | Folge |
|---|---|---|---|
| **Dreisatz von Hand** (5×): 235 kg für 18 Kisten | 2950, 2958, 3000, 3025, 3029 | 470 kg × 18/36 | Die App findet die Palette nicht, rechnet Kisten × Tara. Netto etwa 6 % zu tief (die Palettentara wird ganz abgezogen). Verträglich. |
| **Voller Zettel, weniger Kisten** (5×): 473 kg für 16 Kisten | 3024 (mit Wägung 244), 3041 (Wägung 247), 2986 (Wägung 233), 2973, 2985 | Palette 473 kg/36 Kisten | Anfangsgewicht bis doppelt zu hoch. Wägung 244 ergibt „4.8 % je Tag" (ausgeschlossen); 247 und 233 sind knapp unter der Grenze und **zählen in die Verdunstungsrate** — zu hoch. |

**Prüfen (drei Zettel):** 3024 (1651, Arbeit 1584): 16 Kisten der
Palette 7225 — anteilig 210 kg. 3041 (1617, Arbeit 1588): 56 von 60
Kisten der Palette 6943 — anteilig 542 kg. 2986 (1632, Arbeit 1576): 36
von 40 Kisten der Palette 7656 — anteilig 459 kg, oder die Kistenzahl ist
vertippt. Nach der Korrektur rechnet sich die Verdunstung neu.

**Für die Halle, bis die App es kann:** Bei einer Teilpalette das
Zettelgewicht im Dreisatz umrechnen (Zettel × gezählte Kisten ÷ Kisten
der Palette) — so, wie es meistens schon gemacht wird. Nie den vollen
Zettel zu weniger Kisten schreiben.

**Für die App (erste Aufgabe der nächsten Runde):** Die Maske fragt bei
einer Palette „Kisten davon" — der Zettel bleibt der ganze Zettel, die
App rechnet anteilig, findet die Palette im Journal und rechnet die
Verdunstung mit dem richtigen Anfangsgewicht. Bis dahin sagt der
Durchgang zu jedem Zettel ohne Palette, welche Form es ist.

### 1638 (Kaori Kuri): 18 Holz-Paloxen ohne Leergewicht

18 Paletten vom 10.9. sind Holz-Paloxen (300–319 kg brutto, „1 Kiste").
Die Stammdaten kennen für „Holz Palox" keine Tara. Der Eingang dieser
Charge ist zu 7.4 von 13.2 t **geschätzt** (mit dem Mittel der übrigen
Paletten), nicht gewogen. **Prüfen:** Unter Betrieb → Stammdaten die
Tara des Holz-Palox eintragen (das leere Palox wiegen; es zählt als eine
Kiste mit seinem Leergewicht, Palettentara 0). Danach rechnet sich 1638
von selbst neu. Auffällig dazu: die 18 Paloxen haben nur fünf
verschiedene Gewichte (4 × 318, 4 × 315, 4 × 300, 4 × 313, 2 × 319) —
gewogen sieht anders aus. Abgeschrieben, oder je vier gleich beladen?

### 13 Lieferungen ohne Charge (1660 kg, 15.–21. September)

Orangita, Butterkin, Kaori Kuri, Tiana — jede ohne Chargennummer. Sie
fehlen in jeder Chargenbilanz und im „Wohin" je Sorte. **Prüfen:** Unter
Betrieb → Warenausgang die Charge nachtragen.

### Sieben Arbeiten stehen offen — zwei davon auf Chargen ohne Eingang

| Arbeit | Charge | Seit | Vermutung |
|---|---|---|---|
| 1570, 1571 | 1599, 1604 (Orangita, Illnau) | 21.9., 14:59 und 15:06 | Sieben Minuten nacheinander begonnen, je eine Ablesung, keine Palette dieser Chargen im Journal: versehentlich begonnen oder Probe. **Abbrechen.** |
| 1566 | 1649 | 21.9. | Sieben Tage offen; 1567 an derselben Charge wurde anderthalb Stunden später begonnen und abgeschlossen. **Abbrechen oder abschliessen.** |
| 1568 | 1613 | 21.9. | Waschen, vier Paletten gezählt, nie abgeschlossen. **Abschliessen** — sonst fehlt die Arbeit in der Rechnung. |
| 1578 | 1638 | 23.9. | Eine Ablesung, sonst nichts. |
| 1583 | 1630 | 24.9. | Drei Paletten gezählt. |
| 1590 | 1612 | 26.9. | 173 kg Faules abgelesen, zwei Paletten mit 58 Kisten — Menge ohne Nenner, solange nicht abgeschlossen. |

Eine offene Arbeit rechnet nirgends mit. Wer sie schliesst, gibt der
Rechnung die Menge zurück.

### Kleineres, mit Nummer

- **Zettel doppelt** — Arbeit 1577 (1630, Sortieren 23.9.): zweimal 530
  kg, einmal mit 40 Kisten, einmal mit 32. Im Journal gibt es die
  530-kg-Palette einmal (40 Kisten). Der zweite Zettel (2973) ist wohl
  dieselbe Palette, vertippt.
- **Kistenzahl** — Zettel 2947 (1650): 445 kg mit 36 Kisten, die
  Palette hat 34. Zettel 3044 (1589): 505 kg/40 — die 505-kg-Palette der
  1613 hat 36 Kisten und kam am 24.8.; die der 1632 hat 40 und kam am
  15.9. (siehe oben: falsche Charge).
- **1649 am 8.9.** — 46 Paletten, 30 Paare gleicher Gewichte, wo der
  Zufall etwa 13 erwarten liesse (viermal 434, viermal 448 …). Wurden die
  Zettel abgeschrieben statt gewogen? Kein Fehler in der Bilanz, aber die
  Streuung je Palette ist dann keine.
- **Palette 6904** (1617, 25.8.): 65 Kisten, 630 kg. Sieht echt aus —
  die anderen zwölf Paletten des Tages haben 60 Kisten und 571–592 kg,
  das Gewicht je Kiste passt. Der Durchgang meldete es vorher als
  „gibt es nicht"; er lässt jetzt bis 66 Kisten zu.
- **Arbeit 1580** (1617): 20 Stunden — über Nacht offen geblieben,
  Durchsatz je Stunde stimmt nicht. Nur eine Notiz.
- **Wägung 241** (1651): Zettel 498 kg — die Charge hat keine
  498-kg-Palette (schwerste 493). Vertippt (489?), oder eine Palette
  einer anderen Charge.

## 2. Die Modelle gegen die Saison (`docs/SAISONBEGLEITUNG.md`)

| Grösse | Stand | Erwartet | Urteil |
|---|---|---|---|
| Verdunstung je Tag | 0.37 % (alle Sorten gemeinsam, 26 Wägungen; keine Sorte hat genug eigene) | 0.03–0.3 % im Herbst | Am oberen Rand. Drei der Wägungen sind Teilpaletten mit vollem Zettel (oben) und drücken die Rate nach oben. Nach der Korrektur nachsehen; **kein Grund, das Modell zu ändern**. Frisch geerntete, warme Kürbisse verlieren in den ersten Wochen am meisten. |
| Verderbsmodell | nicht brauchbar (11 Punkte, 5 Chargen, k = −0.5) | k zwischen 1 und 2.5 (beschleunigend) | Ein negatives k heisst: die frühen Messungen sind zu hoch oder die späten fehlen — der Leitfaden sagt, dann die Palox-Ablesungen ansehen. Mit elf Punkten aus den ersten drei Wochen ist es vor allem: zu früh. **Keine Kontrollpalette angelegt.** Je eine je Hauptsorte (Tiana, Butterkin, Kaori Kuri) anlegen und alle zwei Wochen wiegen — das ist der Weg zur Verderbskurve. |
| Zu klein / zu gross | Kaori Kuri 3.5 %, Tiana 0.3 %, Butterkin 0.3 %; Rest aus allen Sorten (1.6 %) | zu klein 3–15 %, zu gross 0–10 % (aus den Sortierläufen) | **Unter der Erwartung — und an der Handlinie ist „zu klein" immer 0 kg** (alle sechs Ausschuss-Auffälligkeiten: „0 kg zu klein / 22 … 154 kg zu gross"). Der Leitfaden nennt genau das: bleibt es bei 0, wird nichts gewogen. Frage an die Halle: Wo bleiben die Kleinen beim Waschen + Sortieren? |
| Anderer Kanal | Butterkin 11 %, Orangita 7 % (aus allen), Tiana 4 % | keine Erwartung im Leitfaden | Dünn (zwei bis drei Messungen je Sorte). Nur beobachten. |
| Ausbeute / Überzählung | 1614: 85 % des Eingangs geliefert, 1619: 86 %, 1626: 121 % | 60–80 % verkaufsfähig, Überzählung 0 | 1626 ist der Journalfehler oben. 1614 und 1619 (Kaori Kuri): entweder fehlen Paletten im Journal, oder die Chargen sind besser als das Modell (74–77 %) — bei einer Sorte mit 3.5 % Ausschuss aus fünf Messungen ist das Modell noch grob. Beobachten. |
| Bilanz | 611 t Eingang, 119 t geliefert (19.5 %), 372 t „im Haus" gerechnet, 461 t Eingangsmasse hinter noch nicht gelieferter Ware | — | „Ein Verluststrom ist noch nicht gemessen": es gibt keine Kontrollpalette und keine Fax-Arbeit. Das Dashboard sagt es selbst. |
| Sortierdateien | 12, keine einer Arbeit zugeordnet | jede einer Arbeit | Frage an den Betrieb: ist das so gewollt? Ohne Zuordnung kennt die App zu keiner Maschinen-Arbeit ihre Kaliberverteilung aus der Datei. |

## 3. Was der Durchgang gelernt hat (Runde AC)

Der erste Durchgang über echte Daten hatte 546 Kandidaten; 518 davon
waren „Doppelte Palette" — und fast alle davon Zufall: bei 60 Paletten
eines Tages zwischen 460 und 500 kg *müssen* Gewichte zusammenfallen
(750 Paare in der Saison, rund 590 erwartet der Zufall). Ein Paar ist
darum kein Kandidat mehr; ein Tag mit deutlich mehr Paaren als erwartet
ist einer (1638 am 10.9., 1649 am 8.9.). Vervielfachungen des Journals
(„5 Paletten à 384 kg", eine Zeile) zählen nicht. Die 18 „Gewicht je
Kiste"-Kandidaten waren Paloxen ohne Tara — jetzt ein Kandidat je
Gebinde. Neu erkennt der Durchgang die Teilpalette von Hand (Dreisatz)
und mit vollem Zettel, die vertippte Kistenzahl, den doppelten Zettel,
den Zettel auf der fremden Charge derselben Sorte, Lieferungen vor dem
ersten Eingang, Sortierläufe ohne Eingang, Lieferungen ohne Charge und
Arbeiten, die offen bleiben. Heute: 35 Kandidaten, jeder mit Nummer.

## 4. Was ich nicht beurteilen kann

- Ob die Ernte der 1626 vor dem 23.9. und die der 1637 wirklich fehlen
  oder nie stattfand — das weiss nur das Journal auf Papier.
- Kundennamen und Preise sehe ich nicht (bleiben draussen), Aufnahmen
  höre ich nicht. Rückmeldungen aus der Halle: bis heute keine.
- Ob die 13 Lieferungen ohne Charge zu einer oder vielen Chargen gehören.
