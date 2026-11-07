# Zweitmeinung zu den Daten der Saison 2026

_Stand 7. November 2026, über den Betriebsabzug vom 7. November
(`rohdaten/`, `DURCHGANG.md`, `AUFFAELLIGKEITEN.md`) und die zwei neusten
Perigon-Dateien und das Erntejournal, die der Betrieb am selben Tag schickte.
Von der Runde am Programm geschrieben (Runde BJ), nicht vom Abzug — ersetzt
die Zweitmeinung vom 19. Oktober. Jede Nummer sagt: was ich sehe, was wohl
passiert ist, wie sicher (eindeutig / wahrscheinlich / unklar), was zu prüfen
ist, und ob eine **Datenkorrektur** (Betrieb) oder eine **Regel** (Programm)
folgt. Jede Zahl ist an den Rohzeilen nachgerechnet; an den Daten geändert
habe ich nur, was der Betrieb freigab (Nr. 1). Ohne Namen: Chargen und
Arbeiten stehen mit ihrer Nummer._

Die Saison in Zahlen: 44 Chargen, 1970 Zeilen im Erntejournal (310 davon
Vervielfachungen „n Paletten gleich"), 130 Arbeiten, 683 Zettel, 267
Verdunstungswägungen, 1593 Lieferungen. Auffälligkeiten: **111** — 71
„Zettelgewicht", 12 „Überzählung", 11 „Wägung", 10 „Verdunstung", 5
„Zetteldatum", je eine „Palox geleert" und „Palette fraglich". Durchgang:
**154 Kandidaten**.

Der Grundsatz des Betriebs für diese Runde: „Die Daten, die verwendbar sind,
trotzdem nehmen, die nicht verwendbaren ignorieren — aber nicht den ganzen
Arbeitsschritt vernachlässigen." Keine der 111 Auffälligkeiten lässt eine
Arbeit ganz wegfallen.

| Gruppe | Fälle |
|---|---|
| Erledigt sich mit den drei grossen Korrekturen (Nr. 1) | 12 |
| Erledigt das Programm mit den Regeln der Runde BJ (Nr. 11) | 34 |
| Der Betrieb prüft kurz — die App rechnet bis dahin schon mit dem wahrscheinlichen Wert (Nr. 2–8) | 45 |
| Keine sichere Erklärung — die App nutzt, was verwendbar ist (Nr. 9) | 20 |

## Für den Betrieb, nach Wichtigkeit

**1. Die drei grossen Korrekturen — 12 Fälle.** Eindeutig.
- Ünique stand in Perigon in kg mit „Gewicht je Artikel" 10. Die App zählte
  deshalb das Zehnfache, rund 110 t zu viel Ausgang (Schritt 1, 0131). Folgt:
  **Regel** (eingebaut); im Perigon-Stamm das Gewicht auf 1 setzen.
- Mix-Kisten gingen ganz auf die genannte Butterkin-Charge. Jetzt wird nach
  dem Rezept verteilt (0131). Folgt: **Regel** (eingebaut).
- Die 34 Paletten vom 31.08. unter 1623 gehören zu 1626 (Etiketten, Zettel der
  Arbeit 1619). In der App umgebucht, mit Beleg. Damit entfallen die 8 Fälle
  der Arbeit 1619. Folgt: **Datenkorrektur** im Erntejournal (Betrieb).
- Danach: setup.sql einspielen, beide Perigon-Dateien neu einlesen, „Neu
  rechnen".

**2. Zettel und Journal 1–3 Tage auseinander — 10 Fälle.** Wahrscheinlich.
Die Palette steht im Journal mit demselben Gewicht (und denselben Kisten),
aber an einem Nachbartag: Arbeit 1602 (1627: viermal 22.09. auf dem Zettel,
23.09. im Journal), 1585 (1650: 08.09. / 11.09.), 1617 (1632: 11.09. / 12.09.
und 14.09. / 15.09.), 1623 (1616: 30.07. / 31.07.), 1635 (1631: 22.09. /
21.09.), 1693 (1628: 04.09. / 03.09.). Viermal dasselbe falsche Datum
abzulesen, ist unwahrscheinlich — eher trägt das Journal ein anderes Datum als
der Zettel. Prüfen: welches Datum stimmt. Folgt: **Datenkorrektur** (Journal
oder Zettel). Die Auffälligkeit bleibt streng; ihr Satz nennt jetzt beide
Daten (0135).

**3. Eine Ziffer im Datum — 12 Fälle.** Eindeutig bis wahrscheinlich. Alle
Gewichte stehen genau an einem Datum, das nur in einer Ziffer abweicht:
Arbeit 1597 (1611: 08.09. statt 18.09.), 1694 (1606: 24.08. statt 24.07.),
1609 (1638, Palox: 15.09. statt 10.09.), 1669 (1719, Palox: 21.10. statt
22.10.). Folgt: **Datenkorrektur** — in der Auffälligkeit mit einem Klick
(„Eine Ziffer im Datum").

**4. Gewicht vertippt — 16 Fälle.** Wahrscheinlich. Drei Zahlendreher (Arbeit
1622: 534 statt 543 kg; 1674: 432 statt 423 kg; 1685: 470 statt 407 kg) und
13 Zettel 1–6 kg neben der nächsten Palette desselben Tages (Arbeiten 1577,
1584, 1596, 1640, 1664, 1665, 1671, 1687, 1691, 1693). Für die Menge
unerheblich. Folgt: **Datenkorrektur** nur bei den Zahlendrehern.

**5. Palette einer anderen Charge — 3 Fälle.** Wahrscheinlich. Arbeit 1589
ist auf 1613 gebucht, ihre Zettel passen zu Paletten von 1632 (beide Tiana).
Prüfen: welche Charge lief. Bis dahin zählt der Ausschuss dieser Arbeit für die
Sorte, nicht sicher für die Charge. Folgt: **Datenkorrektur** (Charge der
Arbeit).

**6. Schwerer als beim Eingang — 7 Wägungen.** Wahrscheinlich: umgepackt oder
eine andere Palette mit altem Zettel. Arbeit 1605 (1648: drei Paletten je
+58 bis +65 kg — schwerer als jede Palette, die von 1648 je kam), 1611 (1611:
Zettel 442 kg passt zu keiner Palette des Tages), 1616, 1631, 1674. Prüfen:
werden Paletten nach dem Sortieren umgepackt und bekommen den alten Zettel?
Die Wägung zählt für die Menge der Arbeit, nicht für die Verdunstung. Folgt:
**Datenkorrektur** nur, wo der Zettel bekannt ist.

**7. Gewogen = Zettel — 2 Wägungen.** Wahrscheinlich: das Zettelgewicht als
Wägung übernommen (Arbeit 1652: 449 = 449 kg; 1669: 304 = 304 kg). Zählt
nicht in die Verdunstung. Folgt: **Regel** — die Wiegemaske sagt es schon
beim Eintippen.

**8. Ohne Palette gewogen — 1 Fall.** Wahrscheinlich. Arbeit 1584: 44 kg
brutto in 2 Kisten „mit Palette" ergibt 16 kg netto; ohne Palette wären es
41 kg. Folgt: **Datenkorrektur** — in der Auffälligkeit mit einem Klick „mit
Palette" abwählen.

**9. Keine sichere Erklärung — 20 Fälle.** Unklar. Teilpaletten mit
ungewöhnlichem Gewicht je Kiste (Arbeiten 1603, 1616, 1631, 1637), Zettel
ohne passende Palette (1611, 1616, 1640, 1658), eine Charge, die am Tag des
Zettels nichts hatte (1694), zu schnell leichter geworden (1603, 1626), und
die Wägungen aus Nr. 6. Was verwendbar ist, zählt: die Menge aus Zettel minus
Tara; nur die Verdunstung lässt die Wägung aus. Prüfen: die Zettel in der
Halle, wenn sie noch da sind.

**10. Offene Arbeiten seit September.** Eindeutig. Arbeiten 1578, 1583, 1593,
1596 und 1611 sind offen und haben nur eine Start-Ablesung. Folgt:
**Datenkorrektur** — in der Halle abschliessen oder abbrechen. Die App meldet
jetzt jede Arbeit, die länger als drei Tage offen ist („Arbeit offen", 0135).

**11. Für Perigon (die App ändert das nicht).** Position 134343: Knospe-Ware
von 1624 unter einem Demeter-Artikel. Lieferung 1637 vor dem Eingang,
vermutlich eine falsch getippte Charge. Folgt: **Datenkorrektur** in Perigon.

## Was das Programm jetzt selbst erledigt (Runde BJ)

| Regel | Fälle | Seit |
|---|---|---|
| Teilpalette, gewogen mit dem Zettel der ganzen Palette: anteilig gerechnet, zählt in die Verdunstung | 10 Wägungen | 0135 |
| Rest einer Palette, neu gewogen und angeschrieben: keine Auffälligkeit | 9 | 0135 |
| Palox über die Anzahl zugeordnet, nicht über das Gewicht (im Journal paarweise gleich) | 5 | 0135 |
| Datum zu spät umgestellt: die Erklärung liest die Reihenfolge der Eingaben | 2 | Runde BJ, Schritt 5 |
| Doppelt gespeichert (gleicher Zettel, gleiche Wägung innert Sekunden): zählt einmal | 1 | 0135 |
| Palox zwischendurch geleert: zählt als „mindestens" | 1 | 0132 |
| Raten aus wenigen Arbeiten: Charge → Sorte → alle Kürbisse gewichtet | 7 | 0132 |
| Überzählung getrennt: Datenfehler oder Rate, die nicht passt; in der Spanne keine Meldung | — | 0134 |

Eine fremde Charge schlägt die Erklärung nur noch vor, wenn die eigene Charge
die Palette innert ±3 Tagen nicht hat.

## Der Durchgang (154 Kandidaten)

| Prüfung | Kandidaten | Was dazu oben steht |
|---|---|---|
| Teilpalette mit vollem Zettel | 41 | Regel 0135 (anteilig); 10 davon waren Auffälligkeiten |
| Zettelgewicht | 28 | Nr. 2–5, 9 |
| Zettel Kistenzahl | 22 | die stehen gelassene Vorbelegung; die Maske warnt seit Runde AO |
| Zetteldatum ohne Palette | 21 | Nr. 3, 9 |
| Arbeit offen | 8 | Nr. 10 |
| Teilpalette von Hand umgerechnet | 7 | Rest einer Palette (Regel 0135) |
| Schwerer geworden | 7 | Nr. 6 |
| Zettel doppelt | 4 | einer ist doppelt gespeichert (Regel 0135); die anderen sind zwei Zettel mit gleichem Gewicht |
| Arbeitsdauer, Doppelte Palette, Eingangsdatum springt zurück | 9 | keine Folge für die Rechnung |
| Lieferung über Eingang, vor Eingang, ohne Charge | 6 | Nr. 1, 11; die Überzählung sagt seit 0134, welche sie ist |
| Verdunstung zu hoch | 1 | Nr. 9 |

Die Kandidaten des Durchgangs sind dieselben Zettel und Wägungen wie die
Auffälligkeiten, nur ohne die Deutung. Einzeln nachgerechnet habe ich in dieser
Runde die 111 Auffälligkeiten; die Kandidaten nur, wo sie dazu gehören.
