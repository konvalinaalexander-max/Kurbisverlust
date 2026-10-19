# Zweitmeinung zu den Daten der Saison 2026

_Stand 19. Oktober 2026, über den Betriebsabzug vom 18. Oktober
(`rohdaten/`, `DURCHGANG.md`, `AUFFAELLIGKEITEN.md`, `MODELLSTAND.md`,
`RUECKMELDUNGEN.md`). Von der Runde am Programm geschrieben (Runde AS), nicht
vom Abzug — ersetzt die Zweitmeinung vom 12. Oktober. Jede Nummer sagt: was
ich sehe, was wohl passiert ist, wie sicher (sicher / wahrscheinlich /
unklar), was zu prüfen ist, und ob eine **Datenkorrektur** (Betrieb) oder eine
**Regel** (Programm) folgt. Jede Zahl ist an den Rohzeilen nachgerechnet;
geändert habe ich an den Daten nichts. Die Perigon-Dateien lagen diesmal
nicht vor — was zu Perigon steht, kommt aus den Lieferungen im Abzug und aus
der Perigon-Prüfung der Runde AS (`docs/ENTSCHEIDUNGEN.md`)._

Die Saison in Zahlen: 42 Chargen, 1756 Zeilen im Erntejournal (310 davon
Vervielfachungen „n Paletten gleich"), 72 Arbeiten (13 neu seit dem
12. Oktober, 8 offen), 422 Zettel, 116 Verdunstungswägungen (18 neu), 1133
Lieferungen (23 ohne Charge), 12 Sortierdateien, keine Kontrollpalette.
Auffälligkeiten: 75, davon 51 „Zettelgewicht" — gerechnet am 18. Oktober.
Durchgang: **107 Kandidaten** (83 am 12. Oktober). Die 24 neuen kommen aus
vier Arbeiten vom 13. bis 17. Oktober und einer Lieferung: Arbeit 1640 (14),
1631 (5), 1637 (3), 1641 (1), Lieferung 1637 (1).

## Was aus der Liste vom 12. Oktober wurde

| 12.10. | Was | Stand 18.10. | jetzt |
|---|---|---|---|
| 1.1 | Arbeit 1619 auf 1623 umhängen | offen | 2.1 |
| 1.2 | Lieferscheine 1626 vom 2.–22.9. | offen | 2.2 |
| 1.3 | Tiana anderer Produzenten in einer Arbeit | neu gelesen: nur Arbeit 1589 bleibt fremd; 1596 ist ein Doppel, 1597 und 1617 tragen ein falsches Datum | 2.3, 4, 5.2 |
| 1.4 | 1637 im Journal, Tara „Holz Palox" | Tara: Programm (0116, 45 kg); Journal offen | 3.2 |
| 1.5 | 1627 im Journal | offen; geliefert jetzt 1416 kg statt 168 kg | 3.1 |
| 2 | die stehen gelassene 36 | die Maske warnt seit Runde AO — trotzdem 14 neue in Arbeit 1640 | 1.1 |
| 3.1 | 1648, Arbeit 1605 schwerer | nichts zu tun, unverändert | 6 |
| 3.2 | Teilpaletten mit dem Gewicht der ganzen Palette | vier neue — und: unter 1 % je Tag zählen sie | 1.2, 1.3 |
| 3.3 | 1611 und 1635 schwerer | 1611 erklärt: Arbeit 1611 ist ein Doppel von 1612 | 5.1, 6 |
| 4.1 | 1624 als „Butterkin Demeter" | offen | 7.1 |
| 4.2 | Perigon-Nummer 198977 → 1650 | offen | 3.3 |
| 5 | acht offene Arbeiten, Arbeit 1595, Arbeit 1624 ohne Ablesung, Arbeit 1577 | alle unverändert offen | 8, 5.4 |
| 5 | „Oettli als Produzent" | Programm (Runde AS): neue Chargen lassen sich anlegen | 8 |

**Erledigt** seit dem 12. Oktober: die Gebinde „Migros Kiste U" (2,43 kg) und
„Plastik Palox" (35 kg) stehen in den Stammdaten (Abzug vom 13.10.); alle
Rückmeldungen zur Ware sind gekürzt. **Sonst kam aus der Liste nichts an:**
Das Erntejournal ist seit dem 10.10. unverändert, Perigon seit dem 12.10.
nicht neu eingelesen, die acht Arbeiten sind offen, Arbeit 1619 hängt an 1626.

**Was das Programm seither tat** (Runde AS, wirkt nach `setup.sql` und „Neu
rechnen"): Holz Palox 45 kg und Plastik Palox 35 kg Tara, eine Palox ist ein
Gebinde ohne Palette darunter; ein Zettel ohne Treffer im Erntejournal rechnet
je Kiste (Tara je Kiste der Charge × gezählte Kisten, eine Palette ohne
Gewicht Netto je Kiste × Kisten), nicht mehr mit dem Mittel ganzer Paletten;
Hagelschaden je Charge als Anteil; ein Kästchen „benutzen", mit dem der
Betriebsleiter eine Palox- oder Verdunstungsmessung aus der Rechnung nimmt;
das Zetteldatum ist beim Sortieren zu Beginn Pflicht.

## 1. Teilpaletten — Halle, Maske und Rechnung meinen Verschiedenes

42 der 107 Kandidaten: 29 „Teilpalette mit vollem Zettel", 7 „Zettel
Kistenzahl", 6 „Teilpalette von Hand umgerechnet". Dahinter stecken zwei
verschiedene Dinge: 25 ganze Paletten mit der stehen gelassenen Kistenzahl
(1.1), und 9 echte Teilpaletten, die die Halle so schreibt, wie die Maske es
seit Runde AO sagt — das Gewicht vom Zettel der ganzen Palette, dazu die
gezählten Kisten („fehlen Kisten, stimmt …"). Die Rechnung aber nimmt das
ganze Gewicht (1.2).

### 1.1 Arbeit 1640 (17.10., Sortieren 1646 Butterkin): 36 statt 40 Kisten

13 Zettel vom 3.9. in zwei Minuten (10:41–10:43), alle mit 36 Kisten. Am 3.9.
kamen von 1646 genau 13 Paletten, **alle mit 40 Kisten**; elf Zettel treffen
sie aufs Kilo, zwei sind verlesen (4.4). Dazu Zettel 3361 (491 kg vom 20.8.,
Palette 6750 hat 40). In einem Zug eingetippt, wohl vom Papier; die Kistenzahl bleibt
von Zettel zu Zettel stehen und war zu Beginn die Vorgabe 36. Die Maske zeigt
in diesem Fall „40 übernehmen" — bei neun Sekunden je Zettel liest das
niemand. Dieselbe Ursache wie am 12.10. (dort § 2) bei elf älteren Zetteln:
Arbeit 1623/1616 fünfmal, 1607/1648 und 1616/1635 je zweimal, 1569/1650 und
1576/1632 je einmal.
**Sicher:** sicher (13 von 13 Paletten des Tages mit 40 Kisten).
**Rechnung:** Wo Datum und Gewicht eine Palette treffen, nimmt sie deren Netto
— die Masse von Arbeit 1640 stimmt auf 11 kg. **Folgt:** keine Korrektur;
eine **Regel** (Programm, P1): die Kisten aus dem Treffer vorbelegen.

### 1.2 Echte Teilpaletten mit dem Gewicht der ganzen Palette — unter 1 % je Tag zählen sie

| Wägung | Arbeit | Charge | Zettel | gewogen | zählt mit | anteilig |
|---|---|---|---|---|---|---|
| 334 | 1631 (13.10.) | 1623 Mieluna | 447 kg, 26 Kisten, Datum 13.8. (4.3) | 317 kg | 0,68 % je Tag | 0,11 % |
| 340 | 1631 (13.10.) | 1623 Mieluna | 432 kg, 28 von 36 (Palette 7047) | 323 kg | 0,77 % | 0,15 % |
| 247 | 1588 (26.9.) | 1617 Orangita | 581 kg, 56 von 60 (Palette 6943) | 514 kg | 0,48 % | 0,23 % |
| 310 | 1619 (8.10.) | 1626, wohl 1623 (2.1) | 427 kg, 28 Kisten (1623: 36) | 323 kg | 0,89 % | 0,15 % |

„Anteilig" heisst: Netto der ganzen Palette × gewogene Kisten ÷ Kisten der
Palette — so passt jede zu ihrer Sorte. Die Rechnung nimmt eine Wägung erst
über 1 % je Tag heraus; darunter zählt sie, wie gerechnet. Kleiner: Zettel
3334 (1635, Arbeit 1637, 31 von 32 Kisten) zählt mit 0,22 statt 0,13 %;
Zettel 2985 (1632, Arbeit 1576, 28 von 36, nicht gewogen) zählt in der Masse
als ganze Palette.
**Was das macht** (nachgerechnet, dieselben n und Mittel wie
`MODELLSTAND.md`): Mieluna 0,21 → 0,18 % je Tag (n 28 → 26)
ohne 334 und 340; Orangita 0,27 → 0,24 % (n 8 → 7) ohne 247; Tiana 0,28 →
0,27 % ohne 310 und die vier doppelten Wägungen aus Arbeit 1611 (5.1). Alles
bleibt im Band der Saisonbegleitung (0,03–0,3 %), aber Mieluna steht um ein
Sechstel zu hoch.
**Dazu die Masse:** Für die Arbeit zählt das ganze Zettelgewicht minus die Tara
der gewogenen Kisten — auch bei den Teilpaletten über 1 % (1.3). Arbeit 1584:
1628 statt 1379 kg (+18 %), Palox-Anteil 5,8 statt 6,8 %; Arbeit 1637: 816
statt 680 kg (+20 %), 2,3 statt 2,8 %; Arbeit 1631: 2552 statt 2344 kg
(+9 %), 3,1 statt 3,4 %.
**Sicher:** sicher für die Rechnung; wahrscheinlich, dass es Teilpaletten
sind (bei 247 ist auch „56 vertippt" möglich, dann gilt 0,48 %).
**Prüfen:** nichts in der Halle — gezählt ist richtig gezählt. **Folgt:**
Datenkorrektur bis zur Regel: bei den vier Wägungen das Kästchen „benutzen"
(0116) abwählen; eine **Regel** (Programm, P1): Teilpaletten anteilig rechnen.

### 1.3 Teilpaletten über 1 % je Tag — zählen nicht in die Verdunstung

- **1651, Arbeit 1584** (Wägung 244, Zettel 3024): 16 von 36 Kisten, 473 →
  200 kg; anteilig 0,70 % je Tag. (12.10.: 3.2)
- **1632, Arbeit 1600** (Wägung 252, Zettel 3085): 28 von 36, 460 → 355 kg;
  anteilig 0,17 % — passt. (12.10.: 3.2)
- **1635, Arbeit 1626** (Wägung 330, Zettel 3293): 32 von 36, 521 → 341 kg;
  anteilig 0,83 %. (12.10.: 3.2)
- **1635, Arbeit 1637** (Wägung 351, Zettel 3335, neu): 519 kg, 27 Kisten,
  Datum wohl 27.8. statt 7.9. (4.3); anteilig 0,59 %.
- **1623, Arbeit 1603** (Wägung 265, Zettel 3101): 89 kg für 4 Kisten, 58 →
  38 kg netto; unverändert unklar.

**1635 fällt auf:** auch anteilig 0,6–0,8 % je Tag, und
Wägung 328 (Arbeit 1626, ganze Palette vom 7.9. mit 32 Kisten wie im Eingang)
verliert 0,61 % und zählt — fast das Doppelte von Kaori Kuri (0,35 %).
**Vermutung:** Bei 1635 wird vor der Waage Faules aus den Kisten genommen;
dann misst die Wägung Fäulnis mit. **Sicher:** unklar. **Prüfen:** Wird bei
1635 vor dem Wägen verlesen? **Folgt:** für die fünf nichts; bei Ja Wägung 328
nicht benutzen.

### 1.4 Teilpalette von Hand umgerechnet (6, unverändert)

Zettel 2950, 2958, 3000, 3025, 3029 (21.–24.9.) und 3131 (5.10.): 235 kg für
18 von 36 Kisten und ähnlich — der Dreisatz der Halle. Seit dem 5.10. keiner
mehr; die Halle schreibt seither das ganze Zettelgewicht (1.2). Die Rechnung
nimmt Kisten × Tara und die ganze Palettentara, gut genug. **Sicher:** sicher.
**Folgt:** nichts.

## 2. Zettel und Lieferungen auf der falschen Charge

### 2.1 Arbeit 1619 (8.10., Waschen + Sortieren, gebucht auf 1626 Tiana): die Paletten waren 1623 Mieluna

Unverändert seit dem 12.10. Acht Zettel vom 31.8.; an dem Tag kam für 1626
nichts (ihre Paletten sind vom 23.9., IFCO 6416). Fünf Zettel treffen
1623-Paletten vom 31.8. genau (428, 434, 430, 437, 437 kg, je 36 Kisten) —
1623 hat aber nur eine 437-kg-Palette, und die Zettel 3227 und 3228 sind
gleich bis aufs Kilo, auch gewogen (437 → 415 kg): dieselbe Palette zweimal?
Die acht Wägungen 308–315 zählen bei Tiana; Wägung 310 ist eine Teilpalette
(1.2). **Sicher:** wahrscheinlich (gleicher Produzent Agasul Rüegg, fünf
genaue Treffer). **Prüfen:** Was lag am 8.10. an der Waschstrasse? Waren es
sieben oder acht Paletten? **Folgt:** Datenkorrektur — Arbeit 1619 auf 1623
umhängen (Messungen → Arbeiten → „Messungen korrigieren", Feld „Charge"),
einen der beiden 437-kg-Zettel löschen, falls doppelt.

### 2.2 1626 Tiana: geliefert, bevor die erste Palette kam

Unverändert: 7 Lieferungen vom 2. bis 22.9. (7156 kg), die erste Palette am
23.9.; insgesamt 7444 kg geliefert gegen 4863 kg Netto-Eingang (153 %), die
Auffälligkeit „Überzählung" sagt 3112 kg. Im Abzug tragen die Lieferungen von
1623 und 1626 dieselbe Sorte (Butternut als Tiana) — der Artikel trennt sie
nicht. 1623 Mieluna (Eingang 28. und 31.8., 20 116 kg netto) ist bis heute zu
32 % geliefert. **Vermutung:** Die Lieferscheine vom 2.–22.9. gehören 1623.
**Sicher:** wahrscheinlich. **Prüfen:** Lieferscheine 2.–22.9. mit Charge
1626. **Folgt:** Datenkorrektur in Perigon.

### 2.3 Tiana anderer Produzenten — die Tabelle vom 12.10., neu gelesen

| Arbeit | gebucht auf | 12.10. | heute |
|---|---|---|---|
| 1589 (26.9.) | 1613 | → 1632: 468 und 505 kg vom 15.9. | bleibt: 1613 hatte am 15.9. nichts, 1632 beide genau, auch die Kisten (36, 40) — wahrscheinlich |
| 1596 (30.9.) | 1611 | → 1632: 471 kg vom 14.9. | ein Doppel des ersten Zettels von Arbeit 1617 (5.2) — sicher |
| 1597 (30.9.) | 1611 | → 1649: 502 kg vom 8.9. | Datum 08.09. statt 18.09. (4.2) — wahrscheinlich |
| 1617 (8.10.) | 1632 | → 1650: 466 kg vom 11.9. | die eigene Palette vom 12.9. mit dem Datum 11.9. (4.1) — wahrscheinlich |
| 1585 (24.9.) | 1650 | → 1649: 456 kg vom 8.9. | unklar: 1649 vom 8.9., oder die eigene 456-kg-Palette vom 11.9. mit stehen gebliebenem Datum |

Das Mischen im Lager ist seltener, als die Zweitmeinung vom 12.10. meinte;
häufiger bleibt das Datum stehen (4). Seit die Maske die fremde Charge nennt
(12.10.), kam kein neuer Fall dazu. **Folgt:** keine Korrektur einzelner
Zettel; eine **Regel** (Programm, P2): der Durchgang findet solche Zettel heute
gar nicht.

## 3. Eingang fehlt, oder Lieferungen passen nicht dazu

### 3.1 1627 Fictor: gearbeitet und geliefert, nie eingegangen

Arbeit 1602 (1.10.) mit fünf Zetteln vom 22.9. (2138 kg brutto); geliefert
jetzt **1416 kg** (23.9. 168 kg, 2.10. 1168 kg, 5.10. 80 kg). Im Erntejournal
keine Palette. Die fünf Wägungen dieser Arbeit sind die einzigen von Fictor —
daher 0,50 % je Tag, die höchste Rate der Saison (Wägung 257: 380 kg mit 33
Kisten, 0,94 %). **Sicher:** wahrscheinlich (Arbeit, Rückmeldung „Viele
grüne", Lieferungen danach). **Prüfen:** Erntejournal 1627 vom 22.9.
**Folgt:** Datenkorrektur (Journal nachtragen). Bis dahin rechnet 1627 ohne
Eingang.

### 3.2 1637 Amoro und 1638 Kaori Kuri (ein Produzent): Paloxen

- **1637:** keine Palette im Journal, aber eine Sortierdatei vom 5.9. (4522
  Kürbisse), neu eine Lieferung vom 6.10. (176 kg) und die Rückmeldung Nr. 5
  „ein Palox Amoro und Kaori Kuri gemischt". Die vier Paloxen in Arbeit 1609
  tragen den 15.9. (313, 300, 298, 312 kg) — an dem Tag kam für 1638 nichts.
  **Vermutung:** 1637 ist als Paloxen eingelagert, ohne Wareneingang.
  **Sicher:** wahrscheinlich. **Folgt:** Datenkorrektur (Journal 1637).
- **1638, Journal vom 10.9.:** 18 Holz-Paloxen in Gruppen gleicher Gewichte
  (4 × 318, 4 × 315, 4 × 300, 4 × 313, 2 × 319 kg) — der Kandidat „Doppelte
  Palette". Die sechs Palox-Zettel vom 10.9. in Arbeit 1613 wiegen 298, 306,
  160, 315, 316 und 304 kg; nur 315 steht im Journal. **Vermutung:** Im Journal
  stehen Mittel von je vier zusammen gewogenen Paloxen, auf den Zetteln die
  einzelnen. Die Summe stimmt dann, nur der Treffer nicht. **Sicher:**
  wahrscheinlich. **Folgt:** nichts nötig; wer will, trägt die Einzelgewichte
  ins Journal.
- **Tara:** Mit 0116 wiegt eine Holz-Palox 45 kg, ohne Palette. Die 18
  Paloxen zählen dann 4812 kg netto statt der 7421 kg, die bis jetzt aus dem
  Mittel der G2-Paletten hochgerechnet sind: **Eingang 1638 von 13 193 auf
  10 584 kg** (die Runde rechnete auf der Kopie 656,5 → 653,9 t für die ganze
  Saison). Ein Palox-Zettel wie 313 kg zählt 268 kg statt 234 kg. „Gebinde ohne
  Tara" und „Tara fehlt" fallen weg; die zehn „Zettelgewicht" von 1638 (286 kg
  je „Kiste") bleiben — sie sind ein Fehler des Durchgangs (P4).
- **Hagel** (Rückmeldung Nr. 5): Seit 0116 lässt sich Hagel je Charge setzen.
  Die eine Palox steckt schon in der Palox-Messung von Arbeit 1609 — für 1638
  nur setzen, wenn mehr als diese Palox betroffen ist.

### 3.3 Lieferungen ohne Charge: 23, davon 4 doppelt

23 Lieferungen (3072 kg, 5.9.–14.10.). **Vier davon** (15.9.: 216, 168 und
56 kg; 29.9.: 80 kg; zusammen 520 kg) sind die Doppel, die Runde AR fand: Jede
hat einen Zwilling mit Charge (1625, 1623, 1624, 1632), später eingelesen.
**Sicher:** sicher. **Folgt:** Beim nächsten Einlesen der Perigon-Dateien
(nach `setup.sql`) verschwinden sie von selbst.
**Übrig: 19** (2552 kg), davon 14 Tiana mit 2516 kg — wohl die Perigon-Nummer
198977, die das Programm nicht kennt (die Perigon-Prüfung der Runde AS fand
auf der Kopie 11 Positionen darunter). Vermutung vom 12.10.: 198977 ist 1650
Tiana (Rümlang Sauter). Mit allen 2,5 t wären aber 93 % des Netto-Eingangs
von 1650 (9048 kg) geliefert — möglich, aber knapp. **Sicher:** unklar.
**Prüfen:** Planungsdatei. **Folgt:** Datenkorrektur — im SQL-Editor
`update charge set perigon_nr = 198977 where nr = 1650;`, wenn die Datei es
bestätigt, danach Perigon neu einlesen.

### 3.4 1624 Butterkin (Agasul Rüegg): alles geliefert

16 817 kg geliefert gegen 16 789 kg Netto-Eingang (100 %), ohne eine einzige
Arbeit an dieser Charge in der App — knapp unter der Grenze des Durchgangs
(102 %); die
Auffälligkeit „Überzählung" sagt 8050 kg zu wenig Eingang. Die grossen Posten:
1.–5.9. 8,4 t, 16.9. 2,5 t, 18.–21.9. 4,2 t. Andere Butterkin-Chargen sind
kaum geliefert (1612 Slowgrow Uster 53 %, 1646 34 %, 1649 4 %). Zusammen mit
1626 (2.2) sind das 11,2 der 12,4 t Überzählung der Saison. **Vermutung:**
Lieferscheine einer anderen Butterkin-Charge stehen auf 1624, oder dem Journal
von 1624 (49 Paletten, 19.–28.8.) fehlt Eingang. **Sicher:** unklar.
**Prüfen:** Lieferscheine 1.–21.9. mit Charge 1624. **Folgt:**
Datenkorrektur in Perigon oder im Journal.

## 4. Das Datum vom Zettel davor bleibt stehen

Das Zetteldatum bleibt mit Absicht für die nächste Palette stehen — die
Paletten kommen zu Dutzenden vom selben Tag. Kommt eine von einem anderen Tag
dazwischen, bleibt das alte Datum. Rund 20 Zettel der Saison; in der Masse
macht es kaum etwas (gleiches Gewicht, gleiches Netto), im Alter schon — und
seit 0116 trägt das Alter beim Sortieren die Rückrechnung der Grösse auf den
Eingangstag. „Zu Beginn Pflicht" (Runde AS) hilft gegen das fehlende Datum,
nicht gegen das stehen gebliebene.

### 4.1 1632, Arbeiten 1617 und 1620 (8.–10.10.): 11.9. statt 12.9.

53 Zettel tragen den 11.9., am 11.9. kamen 44 Paletten; vom 12.9. (12
Paletten) gibt es keinen einzigen Zettel. Die neun überzähligen Gewichte (466,
471, 474, 476, 3 × 478, 479, 483 kg) sind bis auf eine 478 genau die Paletten
vom 12.9. — darunter Zettel 3193 (466 kg), den die Zweitmeinung vom 12.10.
1650 zuschrieb. **Sicher:** wahrscheinlich. **Folgt:** nichts zu korrigieren
(ein Tag); eine **Regel** (Programm, P5).

### 4.2 1611, Arbeit 1597 (30.9.): 08.09. statt 18.09.

Zettel 3076 und 3077: 490 und 502 kg vom 8.9. — 1611 kam ab dem 17.9.; beide
Gewichte gibt es am 18.9. mit IFCO 6416 und 36 Kisten, genau wie auf dem
Zettel, und die Zettel davor tragen den 18.9. Die „1" fehlt. Die Zuordnung zu
1649 Butterkin vom 12.10. ist damit hinfällig (dort G2 mit 40 Kisten).
**Sicher:** wahrscheinlich. **Folgt:** Datenkorrektur nach Belieben (Datum
18.9.; zehn Tage Alter).

### 4.3 Neu seit dem 12. Oktober

- **1623, Arbeit 1631, Zettel 3303:** 447 kg vom 13.8. — 1623 kam am 28. und
  31.8., 447 kg mit 36 Kisten gibt es an beiden Tagen; „13" ist der Tag der
  Arbeit. Gewogen mit 26 Kisten (1.2). **Sicher:** wahrscheinlich.
  **Folgt:** Datenkorrektur — Datum 28.8. oder 31.8.
- **1635, Arbeit 1637, Zettel 3335:** 519 kg vom 7.9. (das Datum des Zettels
  davor) — am 7.9. kam nichts über 470 kg; 519 kg mit 36 Kisten gibt es am 27.8.
  (Palette 6955). **Sicher:** wahrscheinlich. **Folgt:** Datenkorrektur —
  Datum 27.8.
- **1646, Arbeit 1640, Zettel 3367:** 380 kg mit 32 Kisten vom 27.8. (das Datum
  davor) — genau so am 20.8. (Palette 6737). **Sicher:** wahrscheinlich.
  **Folgt:** nichts.
- **1631, Arbeit 1635 (15.10.):** neun Zettel vom 22.9.; darunter zweimal
  425 kg (gibt es am 22.9. nicht, am 21.9. dreimal), zweimal 435 kg (die
  beiden vom 22.9. sind schon in Arbeit 1608 gezählt; der 21.9. hat zwei) und
  zweimal 436 kg (eine am 22.9., eine am 21.9.). Wohl fünf Paletten vom 21.9.
  Die Auffälligkeit „2 Paletten mit 425 kg vom 22.09." ist dieselbe Sache.
  **Sicher:** wahrscheinlich. **Folgt:** nichts (ein Tag).

### 4.4 Gewicht verlesen: Arbeit 1640, 440 und 477 kg vom 3.9.

Am 3.9. kamen von 1646 dreizehn Paletten, alle in dieser Arbeit; zwei davon
ohne Zettel: 446 und 472 kg. Zwei Zettel ohne Palette: 440 und 477 kg.
**Vermutung:** 446 als 440 und 472 als 477 gelesen. **Sicher:** wahrscheinlich.
**Folgt:** nichts (440 kg mit 36 Kisten gibt dasselbe Netto wie 446 kg mit
40; bei 477 sind es 11 kg).

## 5. Doppelt gezählt

### 5.1 Arbeit 1611 (offen) ist der erste Anlauf von Arbeit 1612

Beide am 6.10., Charge 1611, begonnen um 17:31 und 17:36. Dieselben fünf
Zettel vom 18.9., dieselben Wägungen: 487 → 469, 476 → 460, 481 → 462,
493 → 476 kg in beiden; die erste Palette in 1611 mit 442 → 474 kg, in 1612
mit 492 → 474 kg. Die 442 war vertippt; die Arbeit wurde neu begonnen und die
erste offen gelassen. Das erklärt „Schwerer geworden" bei Wägung 291
(12.10.: 3.3). Die vier gleichen Wägungen zählen doppelt bei Tiana — offene
Arbeiten zählen in der Verdunstung, nur abgebrochene nicht. **Sicher:**
sicher. **Folgt:** Datenkorrektur — Arbeit 1611 **abbrechen**, nicht
abschliessen.

### 5.2 Zettel 3177 in Arbeit 1596 ist der erste Zettel von Arbeit 1617

Arbeit 1596 (1611, Sortieren) begann am 30.9. um 07:24 mit einer Ablesung
(50 kg), drei Minuten vor Arbeit 1597 derselben Charge — ein Fehlstart, der
offen blieb. Am 8.10. um 09:55 kam in diese offene Arbeit ein Zettel: 471 kg
vom 14.9., 36 Kisten. Eine Minute später beginnt Arbeit 1617 (1632), und ihr
erster Zettel 3178 ist derselbe. **Sicher:** sicher. **Folgt:**
Datenkorrektur — Arbeit 1596 abbrechen; der Zettel geht mit.

### 5.3 Arbeit 1641 (17.10., Sortieren 1648): 393 kg zweimal

Zettel 3398 und 3399, beide 393 kg vom 18.8., sechs Sekunden nacheinander;
1648 hat am 18.8. eine 393-kg-Palette. 22 Zettel in gut drei Minuten —
nachgetragen. **Sicher:** wahrscheinlich. **Folgt:** Datenkorrektur — einen
löschen (320 kg Masse zu viel).

### 5.4 Mehr Zettel als Paletten, über die Arbeiten hinweg

Diese sieht der Durchgang heute nicht oder nur halb (P3):
- **1630, Arbeit 1577:** 530 kg vom 13.8. zweimal (40 und 32 Kisten), eine
  Palette (unverändert seit 12.10.).
- **1648:** 515 kg vom 18.8. in Arbeit 1607 (5.10.) und 1641 (17.10.), eine
  Palette.
- **1611:** 475 kg vom 22.9. dreimal (Arbeit 1597 zweimal, 1625 einmal), zwei
  Paletten.
- **1617, Arbeit 1595 (offen):** 583 kg vom 26.8. zweimal, eine Palette.

**Sicher:** unklar — ein anderes Gewicht verlesen, oder dieselbe Palette zweimal
gezählt. **Prüfen:** die Zettel. **Folgt:** Datenkorrektur nach Prüfung.

## 6. Wägungen, die schwerer wurden (6)

- **1648, Arbeit 1605** (Wägungen 268–270): 58–65 kg schwerer; unverändert
  (12.10.: 3.1). **Folgt:** nichts.
- **1611, Arbeit 1611** (Wägung 291): erklärt (5.1).
- **1635, Arbeit 1616** (Wägung 302): 428 → 433 kg; mit 32 statt 36 Kisten (wie
  im Eingang) ebenso 5 kg mehr. Waagenrauschen oder vertippt. **Folgt:**
  nichts.
- **1623, Arbeit 1631** (Wägung 335, neu): 444 → 464 kg, ganze Palette vom
  28.8.; die fünf anderen ganzen Paletten dieser Arbeit verloren 22–25 kg.
  **Vermutung:** vertippt (um 420 kg). **Sicher:** wahrscheinlich. **Folgt:**
  nichts — sie zählt nicht.

## 7. Verkauf und Labels

### 7.1 1624 Butterkin einmal als „Butterkin Demeter" verkauft

Unverändert (12.10.: 4.1); die Perigon-Prüfung der Runde AS fand auf der
Kopie dieselbe Demeter-Zeile mit Knospe-Label. **Prüfen:** Lieferschein dieser
Position. **Folgt:** Datenkorrektur in Perigon, falls der Artikel falsch war.

### 7.2 Kaori Kuri als Mandarin

Zwei Lieferungen tragen den Artikel Mandarin (im Abzug Sorte Orangita), die
Charge ist aber Kaori Kuri: 1619 am 27.8. (39,6 kg) und 1651 am 10.10. (40 kg).
**Sicher:** die Zeilen stehen so; welche Seite falsch ist, ist unklar.
**Folgt:** Datenkorrektur in Perigon (Artikel oder Charge).

## 8. Kleineres

- **Acht Arbeiten offen**, dieselben wie am 12.10. Einzeln:
  1578 (1638, 23.9.: nur eine Ablesung, eine Minute vor Arbeit 1579 einer
  anderen Charge) — abbrechen; 1583 (1630, Waschen: Zettel und drei fertige
  Paletten vom 25.9., keine Schlussablesung) — abschliessen, das Faule bleibt
  unbekannt; 1590 (1612, Waschen: alles da) — abschliessen; 1591 (1612,
  Waschen: Ablesungen 133, 250, 383 kg, die nächste Arbeit beginnt bei 250) —
  Endstand klären, abschliessen; 1593 (1650, 28.9.: nur eine Ablesung) —
  abbrechen, wenn nichts mehr lief; 1595 (1617: zweite Ablesung gleich der
  ersten, 239 kg, und 583 kg zweimal, 5.4) — abschliessen, Faules unbekannt;
  1596 und 1611 abbrechen (5.1, 5.2). **Folgt:** Datenkorrektur.
- **Arbeitsdauer** (1580, 1597, 1617, 1620): über Nacht offen, am nächsten
  Tag geschlossen (1597: letzter Zettel 30.9. 11:28, Ende 1.10. 11:51). Der
  Durchsatz je Stunde stimmt nicht, sonst nichts.
- **Doppelte Palette 1649 vom 8.9.:** 46 Paletten, 30 gleiche Paare gegen 13
  vom Zufall; zwei Drittel liegen zwischen 434 und 449 kg — so eng gibt es mehr
  Paare, als die Prüfung annimmt. **Sicher:** unklar. **Folgt:** nichts.
- **1635, Arbeit 1616, Zettel 3174:** 200 kg für 24 Kisten (5,8 kg je Kiste
  netto, die Charge hat 11,8), gewogen 195 kg, zählt mit 0,12 % je Tag.
  **Sicher:** unklar (halbvolle Kisten?). Prüfen, sonst nichts.
- **Arbeit 1624** (1630, Waschen, 12.10.) hat weiterhin keine
  Palox-Ablesung — ihr Faules ist unbekannt, nicht 0.
- **Sortierdateien:** Im Abzug ist der letzte Lauf vom 10.9., keiner einer
  Arbeit zugeordnet. Seit 0116 kommen zu klein und zu gross aus diesen Dateien
  — die Dateien seit Mitte September einlesen.
- **Rückmeldung zur App Nr. 9** („Migros Kisten U 2,43 kg, Plastikpaloxen
  35 kg, Oettli als Produzent"): Die beiden Gebinde stehen seit dem 13.10. in
  den Stammdaten. Oettli: Seit Runde AS legt das Einlesen des Erntejournals eine
  neue Charge selbst an, wenn Nummer, Schlag und Sorte im Journal stehen —
  1719 (Oettli) und 1763 (Trüb); sonst legt sie der Betriebsleiter unter
  Stammdaten → Chargen an.

## Reihenfolge für den Betriebsleiter

1. Arbeiten 1611, 1596 und 1578 abbrechen, 1590 abschliessen (5.1, 5.2, 8) —
   sicher, fünf Minuten.
2. Arbeit 1619 auf 1623 umhängen (2.1); Lieferscheine 1626 vom 2.–22.9. (2.2).
3. Nach `setup.sql` (0116) und „Neu rechnen": bei den Wägungen 334, 340, 247
   und 310 „benutzen" abwählen (1.2); beide Perigon-Dateien neu einlesen — die vier
   doppelten Lieferungen verschwinden (3.3).
4. Erntejournal: 1627 vom 22.9. und 1637 nachtragen (3.1, 3.2).
5. 1624: Lieferscheine 1.–21.9. und die Demeter-Zeile (3.4, 7.1); 198977 in
   der Planungsdatei (3.3).
6. Die übrigen offenen Arbeiten (8); die Sortierdateien seit Mitte September;
   die Daten der Zettel 3303 und 3335 (4.3).

## Für das Programm

Vorschläge, nach Gewicht. Nichts davon ist in dieser Runde gebaut; eine
Grenze in `GRENZEN` ändert sich nur mit Begründung in `docs/ENTSCHEIDUNGEN.md`.

- **P1. Eine Bedeutung für die Teilpalette** (1.1–1.3, 34 Kandidaten). Die
  Maske sagt bei weniger Kisten „fehlen Kisten, stimmt …", die Halle schreibt
  das ganze Zettelgewicht mit den gezählten Kisten. Die Rechnung nimmt bei einem
  Treffer das Netto der ganzen Palette (`v_auftrag_palette_masse`) und bei einer
  Wägung das ganze Zettelgewicht minus die Tara der gewogenen Kisten
  (`v_wiegung_kennzahl`). Vorschlag in zwei Schritten: (a) Maske — die Kisten
  aus dem Treffer im Wareneingang vorbelegen statt die Zahl des Zettels davor;
  eine kleinere Zahl ausdrücklich als Teilpalette bestätigen lassen und so
  speichern. (b) Rechnung — eine bestätigte Teilpalette anteilig (Netto der
  Palette × Kisten ÷ Kisten der Palette), für die Masse und für das Netto
  damals der Wägung. Erst (a), dann (b): sonst würden die 25 stehen gelassenen
  36er zu Teilpaletten, und ihnen fehlten 10 % Masse. Testfälle: Wägungen 334,
  340, 247, 310 (zählen mit 0,48–0,89 % statt 0,11–0,23 %), Arbeit 1584 (+18 %
  Masse). Und der Satz des Durchgangs „… zählt so nicht" stimmt nur über 1 %.
- **P2. Durchgang 4b datumsgenau und über den Produzenten** (2.3, 4). Heute
  gilt ein Zettel als gefunden, wenn Gewicht und Kisten an *irgendeinem* Tag
  der eigenen Charge vorkommen — bei 1611 (177 Paletten) und 1632 (209) fast
  immer. Darum meldet „Zettel auf fremde Charge" die ganze Saison keinen
  Kandidaten, und „Zettel Kistenzahl" nennt bei Arbeit 1589 eine 1613-Palette
  vom 24.8., wo am 15.9. eine 1632-Palette genau passt. Vorschlag: suchen mit
  Charge + Datum + Gewicht; ohne Treffer zwei Fragen in einem Kandidaten —
  Gewicht und Kisten genau an einem anderen Tag derselben Charge („Datum vom
  Zettel davor?", 13 Zettel, 7 davon sieht der Durchgang heute gar nicht), und
  am selben Tag bei einer Charge derselben Sorte oder desselben Produzenten
  (`schlag`) („fremde Charge?", 10 Zettel, fünf davon Arbeit 1619 → 1623).
  Passt beides (3193, 3026), stehen beide da. Testfälle: 1619 (Mieluna und
  Tiana, ein Produzent), 1617 (11./12.9.).
- **P3. Mehr Zettel als Paletten, über alle Arbeiten einer Charge** (5). Die
  Prüfung „Zettel doppelt" zählt nur in einer Arbeit und gegen alle Tage — sie
  fand 2. Je Charge, Datum und Gewicht über alle Arbeiten sind es 16 Fälle mit
  19 Zetteln zu viel, darunter 1611/1612 und 1632 vom 11.9. Dazu eine Prüfung
  „Arbeit doppelt": zwei Arbeiten derselben Charge am selben Tag mit gleichen
  Zetteln oder gleichen Wägungen — Schwere hoch, weil die Wägungen doppelt in
  die Rate gehen.
- **P4. Palox im Durchgang als eigenes Gebinde** (3.2). Eine Palox ist eine
  „Kiste" mit 300 kg; „Zettelgewicht" vergleicht sie mit dem G2-Mittel der
  Charge (11,5 kg je Kiste) — zehn der 15 „Zettelgewicht" sind das. Nach 0116
  (Tara 45 kg) meldet der nächste Abzug dazu 18 neue „Eingang Gewicht je
  Kiste" (273 kg je Kiste; am Abzug vom 18.10. nachgerechnet: 107 → 124
  Kandidaten). Vorschlag: ein Gebinde ohne Palettentara mit einer Kiste ist
  eine Palox; Gewicht je Palox gegen eine eigene Grenze (neuer Eintrag in
  `GRENZEN`; die Saison zeigt 160–319 kg brutto) und Palox-Zettel nur gegen
  Paloxen derselben Charge — mit Test.
- **P5. In der Maske das Datum wie die Kisten** (4). Bei „anderer Tag" (Gewicht
  und Kisten genau an einem anderen Tag derselben Charge) ein Knopf „Datum
  übernehmen (12.09.)", wie „40 übernehmen" bei den Kisten.
- **P6. Eine offene Arbeit, wenn die nächste beginnt** (5.1, 5.2, 8). 1578,
  1596 und 1611 sind Fehlstarts, die offen blieben; 1596 nahm acht Tage später
  einen Zettel auf, der in 1617 gehörte. Beginnt auf einem Gerät eine Arbeit,
  während eine andere offen ist: fragen, ob die offene abgebrochen werden soll.
  Und eine Frage an den Betrieb: Wägungen offener Arbeiten zählen in der
  Verdunstung, die Stationswerte nicht — so gewollt?
- **P7. Ende = letzter Eintrag** (8, klein). Wird eine Arbeit erst am nächsten
  Tag abgeschlossen, die Zeit des letzten Eintrags als Ende vorschlagen.
