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

## 2. Faules im Lager (erg_modell, erg_punkte)

| Frage | Erwartung | Wenn nicht |
|---|---|---|
| Kurve F(t) = 1 − exp(−λ·t^k) | k zwischen 1 und 2.5 (beschleunigend), λ so, dass F(100 Tage) im einstelligen Prozentbereich liegt | k < 1 (abflachend): die späten Messungen fehlen oder die frühen sind zu hoch — Palox-Ablesungen prüfen (geleert ohne Ablesung?). λ sehr gross: Sockel a₀ prüfen |
| Sockel a₀ | nur, wenn die Daten ihn belegen (`sockel_nachweis`), meist 0–3 % | Nachweis ohne plausiblen Grund (Erde, Hagelnarben, Schnittfehler): die frühen Arbeiten ansehen — was landet am ersten Tag im Palox? |
| Ein Modell für alle Sorten | die Punkte der Sorten liegen um dieselbe Kurve | Eine Sorte liegt durchgehend darüber oder darunter: erst zählen, ob sie genug Punkte hat (> 15 Messungen, > 3 Chargen); dann ein Modell je Sorte erwägen — als eigene Migration mit Prüfblock, nie still |
| Kommentare zur Ware | „Hagelschaden", „viel Faules" am Punkt (0091) erklären Ausreisser | Ein Ausreisser ohne Kommentar: die Arbeit öffnen (Klick auf den Punkt), die Palox-Ablesungen ansehen |

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
| Waschen aus Kisten | „fertige_paletten" (drei gewogen) oder „wasch_paletten" mit bekanntem Kistengewicht | „Kistengewicht unbekannt": seit 0092 lernt die App das Kistengewicht eines Bandes aus Wasch-Arbeiten, die ihre fertigen Paletten gewogen haben — eine solche Arbeit je Sorte und Band genügt |
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
