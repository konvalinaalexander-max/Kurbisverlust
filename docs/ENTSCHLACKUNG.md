# Entschlackung — was das Programm schwer macht, und was davon weg kann

Stand 29. September 2026 (Runde AI). Der Betrieb: „Ich habe das Gefühl, unsere
Software ist extrem bloated und unnötig kompliziert. Ich staune, wie lange
alles lädt, wie lange du brauchst zum Arbeiten. Gibt es Lösungen, das zu
kürzen, so dass die Mathematik noch stimmt?" Und: „Das Tool soll primär ein
Lagermanagement-Tool werden. Der Chargen-Unterreiter ist das Kernstück."

Die ehrliche Antwort: Ja, es ist zu viel geworden — nicht in der Mathematik,
sondern drumherum. Hier die Zahlen, die Ursachen, und ein Plan in drei
Stufen: was ohne Rückfrage geht, was der Betrieb entscheiden muss, was
bleiben soll.

## 1. Die Zahlen

| Was | Umfang | Bemerkung |
|---|---|---|
| App (`src/`) | 19 400 Zeilen, 77 Dateien, 16 Seiten | Bündel 5 MB, davon Grundlage 465 KB, Auswertung 240 KB |
| Datenbank-Rechenwerk (`setup.sql`) | 17 200 Zeilen, 79 Sichten, 26 gespeicherte Ansichten, 90 Funktionen | aus 105 Migrationen (41 000 Zeilen) verdichtet |
| Ein Lauf der Auswertung | Demo 8 s, Betrieb 690 s | 45 gespeicherte Ansichten werden jedes Mal komplett neu geschrieben |
| Prüfstände je Runde | Volltest 10 min, Kette 5 min, Abnahme 3 min, Bildschirme 40 min (264 Aufnahmen) | rund eine Stunde, bevor etwas gepusht wird |
| Dokumentation | 21 000 Zeilen, ENTSCHEIDUNGEN allein 5 350 | jede Runde schreibt, was war und warum |
| Öffnen des Dashboards | 33 Anfragen auf einmal (`alles()`), jede Seite lädt alles | auch die Halle-Seiten laden das Rechenwerk mit |

## 2. Woher das kommt

1. **Die Auswertung rechnet alles, immer.** 45 gespeicherte Ansichten in fünf
   Schritten, jede von Grund auf, auch wenn sich nur eine Palette geändert
   hat. Mit der Demo Sekunden, mit der Saison Minuten — und der Konvoi vom
   28. September war die Folge. Seit 0103 schreibt jeder Lauf auf, welche
   Ansicht wie lange braucht (`auswertung_laufzeit`): Nach dem ersten Lauf
   auf Stand 103 steht fest, wo die 690 Sekunden sind. Erfahrungsgemäss sind
   es zwei, drei Ansichten (Kaskade, Hochrechnung, Plausibilität), nicht 45.
2. **Das Verderbsmodell ist ein Forschungsinstrument.** F(t) = 1 − exp(−λ·t^k),
   im Logarithmus angepasst, mit Smearing, Sockel mit Nachweis, Band aus
   Kovarianzen, Selektionsverdacht, Treppenfunktion als Ersatz — rund 900
   Zeilen SQL und ein Dutzend Prüfblöcke. Der Betrieb will aber wissen: Wie
   viel geht an der Station in den Palox, und steigt es? Das sind zwei
   Zahlen je Station (seit 0105 da). Das Modell braucht die Kaskade heute
   noch, um Verderb für liegende Ware zu rechnen; mit den Stationswerten
   lässt es sich ersetzen: erwarteter Palox-Anteil auf dem Weg, den die Ware
   noch nimmt.
3. **Das Dashboard lädt alles auf einmal.** `alles()` holt 33 Ergebnisse,
   bevor irgendeine Seite etwas zeigt; Lagermanagement braucht davon acht.
   Die Halle-Seiten laden nichts davon — aber das Bündel, das sie mitbringen.
4. **Jede Runde hinterlässt Schichten.** 105 Migrationen, die der Verdichter
   auf 17 000 Zeilen bringt; Sichten, die keine Seite mehr liest (z. B.
   `v_schimmel_kurve_anzeige`, `erg_fax_wartezeit` seit dem Einfrieren des Fax,
   die alten Marge-Sichten vor 0097); Prüfblöcke, die längst überschriebene
   Regeln absichern und bei jeder Regeländerung angepasst werden müssen (in
   Runde AG/AH: 0061, 0095, 0100, 0102).
5. **Der Prüfstand ist auf Sicherheit gebaut, nicht auf Tempo.** Alle
   Bildschirme, alle Blöcke, alle Mutationen, bei jeder Runde — eine Stunde.
   Das hat Fehler gefunden (die Zwischenlager-Tage um 22 Uhr, der leere
   Nenner beim Waschen), aber es ist der grösste Teil der Zeit, „die du
   brauchst".

## 3. Der Plan

### Stufe 1 — ohne Rückfrage, in der nächsten Runde

- **Die langsamen Ansichten finden und beschleunigen** (aus
  `auswertung_laufzeit` nach dem ersten Lauf auf Stand 103+). Ziel: ein Lauf
  unter 60 s mit der Saison des Betriebs. Was nichts ändert, wird nicht neu
  gerechnet (Ansichten aus Stammdaten wie `erg_gebinde`, `erg_kaliber` nur bei
  Bedarf).
- **Je Seite laden, was die Seite braucht.** Lagermanagement: acht Ergebnisse
  statt 33. Die Halle-Seiten ohne das Auswertungs-Bündel (schon getrennt,
  aber die Grundlage ist zu gross).
- **Tote Sichten weg** (Rechenwerk darf weg, Tabellen nie): eine Liste je
  Sicht, welche Seite oder welcher Prüfblock sie liest; was niemand liest,
  verschwindet mit seinem Prüfblock — als eigene Migration, sichtbar.
- **Prüfstand in zwei Stufen:** schnell (Typen, Tests, Kette, Prüfblöcke der
  Runde) bei jedem Push; voll (alle Blöcke, alle Bildschirme) einmal am Tag
  im Betriebsabzug, nicht vor jedem Push. Das ist eine Änderung an
  `CLAUDE.md` — sie steht unten als Vorschlag, entschieden vom Betrieb.

### Stufe 2 — der Betrieb entscheidet

- **Die Kaskade auf die Stationswerte stellen.** Verderb liegender Ware =
  erwarteter Palox-Anteil der nächsten Station (Mittel der letzten vier
  Wochen, je Sorte, wo genug da ist) statt F(t). Damit fallen weg: das
  Modell, Sockel, Smearing, Selektionsverdacht, Treppenfunktion, die
  Verderbskurve in der Grafik, ein Dutzend Prüfblöcke und AB-Einträge. Was
  bleibt: die Punkte je Station, die Linien je Charge, zwei Kennzahlen je
  Station. Die Verlustzahlen ändern sich dabei — leicht, in beide Richtungen.
  Vorschlag: nach vier Wochen Stationsdaten (Ende Oktober), mit einem
  Vorher-nachher-Bild.
- **Was das Dashboard zeigt.** Sechzehn Seiten und Unterreiter; das
  Kernstück soll das Lagermanagement mit dem Chargen-Unterreiter sein.
  Vorschlag: Lagermanagement (mit Chargen) vorn und ausgebaut; Ursachen und
  Messungen als zweite Ebene; Betrieb wie heute; die Seiten Marge,
  Ausstehend, Verlust prüfen, ob sie in den Chargen-Reiter passen statt
  eigene Reiter zu sein.
- **Die Dokumentation einfrieren.** ENTSCHEIDUNGEN wird Archiv (nichts mehr
  ändern, nur anhängen — kurz), HERLEITUNG und ABMACHUNGEN bleiben die
  lebenden Dokumente, README wird auf das gekürzt, was ein Nutzer braucht.

### Stufe 3 — was bleibt

- Die Regeln: leer ist nicht null; jede Zahl sagt, woher sie kommt; nie eine
  Tabelle löschen; kein Test wird schwächer, um grün zu werden.
- Die Mathematik der Verdunstung (klar, gemessen, je Sorte mit ehrlichem
  Zug) und die Massen-Kette (Zettel, Waage, Tara).
- Der Betriebsabzug und die Zweitmeinung über die Rohdaten.

## 4. Vorschlag für CLAUDE.md, Abschnitt 3 (zur Entscheidung)

Vor jedem Push: `npx tsc -b && npm test`, `./supabase/setup_bauen.sh`,
`node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh`, die
Prüfblöcke der Runde mit ihren Mutationen, `node pruefstand/beschriftung.mjs`.
Einmal täglich (Betriebsabzug) oder vor einer Runde, die Bildschirme ändert:
`./supabase/test/run.sh` komplett, `node pruefstand/bildschirme.mjs`,
`node pruefstand/abnahme_r.mjs`.
