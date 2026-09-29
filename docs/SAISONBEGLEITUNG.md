# Saisonbegleitung — die Fragen an jede Runde

Der Betrieb: „dass du im Verlauf der Saison auch immer mal wieder die
Datenbank anschaust: Was passiert da? Wie funktionieren meine Modelle mit
den aktuellen Daten? Kommt das, wie ich es erwartet habe — oder ganz
anders? Und wenn es anders kommt, muss ich meine Rechnungen ändern?"

Diese Datei ist die Liste dazu. Sie wird mit `docs/betrieb/MODELLSTAND.md`
(täglicher Abzug) gelesen; die Zahlen dort, die Erwartung hier. Weicht
etwas ab, gilt die Reihenfolge: **erst die Daten prüfen** (Auffälligkeiten,
Tara, Datum), **dann die Annahme** (ist das Modell für diesen Fall
gedacht?), **zuletzt die Mathematik** — und jede Änderung steht in
`docs/ENTSCHEIDUNGEN.md` mit dem Grund.

## 1. Verdunstung (erg_koeff_verdunstung)

| Frage | Erwartung | Wenn nicht |
|---|---|---|
| Rate je Tag, je Sorte | 0.03–0.3 % je Tag im Herbst; im Winter (kalt, feucht) eher am unteren Rand | Über 0.5 %: Wägungen ansehen — Zettelgewicht, Kisten, Gebinde; eine Wägung über der Grenze `verdunstung_rate_max_pro_tag` zählt ohnehin nicht (0089). Unter 0.02 %: wurde dieselbe Palette wirklich zweimal gewogen, oder das Eingangsgewicht abgeschrieben? |
| Basis | „Wiegungen dieser Sorte" für die Hauptsorten spätestens ab Oktober | Steht eine Hauptsorte auf „Wiegungen aller Sorten": Kontrollpaletten dieser Sorte wiegen (Startbildschirm → Kontrolle schlägt sie vor) |
| Bereich (unten–oben) | schmaler als das Mittel selbst | Breiter: zu wenige Chargen — mehr Kontrollpaletten, nicht am Modell drehen |
| Verlauf über die Saison | Punkte im Bild *Ursachen → Verdunstung* nach Lagerdauer flach oder leicht fallend | Sichtbarer Knick im Winter: ein Befund, kein zweites Modell (AB-Regel seit Runde R). Erst wenn der Knick in zwei Saisons steht, eine Rate je Jahreszeit erwägen |

## 2. Faules im Lager (erg_punkte, v_palox_erwartung, v_palox_station)

| Frage | Erwartung | Wenn nicht |
|---|---|---|
| Palox-Anteil je Sorte und Station (0106) | je Sorte ein eigener Wert, sobald drei Arbeiten da sind („Arbeiten dieser Sorte"); geliehene Werte (alle Sorten) nur bei Sorten, die selten drankommen | Eine Sorte mit vielen Arbeiten und trotzdem geliehen: die Punkte sind unplausibel (über 90 %) oder ohne Nenner — Auffälligkeiten ansehen |
| Der Weg der Charge (v_charge_weg) | Tiana, Mieluna: von Hand (p_hand = 1); Kaori Kuri, Butterkin: Band, dann Waschstrasse (p_hand = 0, p_wasch = 1) | Eine Bandsorte mit p_wasch = 0 über Wochen: die Wasch-Arbeiten werden nicht erfasst — die Vorarbeiter briefen (AB-118) |
| Kommentare zur Ware | „Hagelschaden", „viel Faules" am Punkt (0091) erklären Ausreisser | Ein Ausreisser ohne Kommentar: die Arbeit öffnen (Klick auf den Punkt), die Palox-Ablesungen ansehen |
| Zwei Augen | Band-Punkte (Sortieren) liegen unter den Wasch-Punkten derselben Charge: Das Band legt nur eklig Faules in den Palox, das Waschen auch Ästhetik und Schäden (Betrieb, 29. 9.) | Wasch-Punkte weit über Band-Punkten gleicher Lagertage: nicht als Verderb lesen. Die Kontrollpaletten (`quelle = lager`) sind das neutrale Auge — mehr davon. Merkposten Runde AG: Kurve nur aus Band und Kontrollpaletten, der Wasch-Palox als eigener Strom |
| Ab Dezember | „plötzlich faul", ein klarer Anstieg (Betrieb, gehört) | Steigt die Kurve im Dezember, muss der Anstieg auch in den Kontrollpaletten stehen — sonst ist es das Auge, nicht die Ware |
| Kennzahl je Station (0105) | Waschen + Sortieren einstellig bis knapp zweistellig (Ästhetik und Schäden dabei), Sortiermaschine unter 2 % (nur eklig Faules), nur Waschen dazwischen; Zuwachs je Woche nahe null im Herbst | Zuwachs deutlich über null vor Dezember: erst die Chargen ansehen (Linien einschalten — ist es eine Charge mit Hagel?), dann die Kontrollpaletten. Zuwachs erst nach vier Wochen und fünf Arbeiten sichtbar — vorher steht, was fehlt |

## 3. Zu klein / zu gross, anderer Kanal (erg_koeff_ausschuss, erg_koeff_nebenkanal)

| Frage | Erwartung | Wenn nicht |
|---|---|---|
| Anteil je Sorte | aus den Sortierläufen (CSV) stabil; zu klein 3–15 %, zu gross 0–10 %, je nach Sorte und Bändern | Sprünge zwischen Läufen: wurde das Sortierschema geändert (neue Fassung)? Die Klassierung folgt der Fassung des Auftrags (0051) |
| Handlinie (Waschen + Sortieren) | Kiste für Kiste gewogen (0088), Anteile ähnlich wie am Band | 0 kg zu klein bei allen Arbeiten: der Fehler aus 0083 ist behoben — bleibt es bei 0, wird nichts gewogen (Rückmeldung zur App?) |
| Bezugsmasse | jede Arbeit hat einen Nenner (gezählte Paletten mit Zettelgewicht) | Auffälligkeit „Ausschuss" mit winziger Bezugsmasse: Paletten der Arbeit fehlen — Korrektur |

## 4. Die Masse der Arbeiten (masse_quelle)

| Frage | Erwartung | Wenn nicht |
|---|---|---|
| Sortieren, Waschen + Sortieren | „zettel" oder „gewogen" | „zettel-charge-tara" häufig: Paletten fehlen im Erntejournal (Abgleich läuft täglich, 0090) — oder Zetteldatum/-gewicht vertippt |
| Waschen aus Kisten | seit 0104 „gewogen_strasse": jede Palette am Anfang der Strasse gewogen; ältere Arbeiten „fertige_paletten" (drei gewogen) oder „wasch_paletten" mit gelerntem Kistengewicht | „wasch_paletten" oder „fertige_paletten" bei einer Arbeit nach dem 29. 9.: die Strasse hat nicht gewogen — Auftragsleitende ansprechen. Auffälligkeit „Waage": Kistenzahl, Gebinde, Waage prüfen, im Korrekturfenster berichtigen. „Kistengewicht unbekannt" nur noch bei ungewogenen Arbeiten |
| Fax | eingefroren (Entscheid des Betriebs, 0078) | — |

## 5. Ausbeute und Bilanz (erg_bilanz, erg_charge)

| Frage | Erwartung | Wenn nicht |
|---|---|---|
| Verkaufsfähiger Anteil | 60–80 % je nach Sorte und Alter; „Überzählung" 0 | Überzählung > 0: Eingang fehlt, Lieferschein falsch gebucht, oder die Charge ist besser als das Modell (0090 sagt es so) |
| Im Lager vs. Halle | „Im Lager" ist Eingangsmasse hinter noch nicht gelieferter Ware — nicht das Gewicht in der Halle | Liegt in der Halle sichtbar viel weniger: die Ausbeute der Sorte ist zu hoch gerechnet (Charge 1625, Runde V) |
| Massenbilanz | Modell und CSV nah beieinander (< 10 %) | Weiter auseinander: welcher Koeffizient steht auf „aller Sorten"? |

## 6. Datenqualität (erg_datenqualitaet)

| Frage | Erwartung |
|---|---|
| Paletten ohne Netto | wenige; sie rechnen mit dem Mittel der übrigen |
| Arbeiten ohne Palox-Ablesung | sinkend seit Runde T (Pflichtfrage) |
| Lesungen ohne Sortiertag | 0 — sonst rechnet die Verdunstung ohne sie (AB-73) |

## 7. Was die Rückmeldungen sagen

Aus `docs/betrieb/RUECKMELDUNGEN.md`: Jede Rückmeldung zur App wird zur
Aufgabe oder bekommt einen Satz in `docs/ENTSCHEIDUNGEN.md`, warum nicht.
Rückmeldungen zur Ware sind Befunde — sie werden nicht „abgearbeitet".
