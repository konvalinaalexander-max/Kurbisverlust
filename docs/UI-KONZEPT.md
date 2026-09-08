# Die Oberfläche: zwei Apps in einer

Kürbis-Verlust hat zwei Nutzergruppen, die sich nichts zu sagen haben. Der
Arbeiter in der Halle soll messen, ohne zu verstehen, wofür. Der Betriebsleiter
am Rechner soll verstehen, ohne selbst zu messen. Diese Datei hält fest, wie
die Oberfläche das trennt — und woran sich jede Maske messen lassen muss.

## Leitlinien, an denen gemessen wird

| Regel | Woher | Was sie hier heisst |
|---|---|---|
| Ein Bildschirm, eine Frage | NN/g, *Wizards: Definition and Design Recommendations* — feste Reihenfolge, Schritt sichtbar, Erwartung setzen | Assistent beim Eröffnen und beim Abschliessen: „Schritt 2 von 5", eine Frage, ein Hauptknopf |
| Fehler verhindern, nicht melden | Nielsen, Heuristik 5; NN/g *4 Principles to Reduce Cognitive Load in Forms* | Datum bleibt für die nächste Palette stehen; unbekannte Charge sperrt das Starten; Zahlenfelder rufen die Zifferntastatur |
| Rückgängig statt Nachfrage | Nielsen, Heuristik 3 | „+" zählt sofort, „Rückgängig" nimmt die letzte Palette zurück — keine Sicherheitsfrage vor jedem Tipp |
| Ziele mindestens 44 pt / 48 dp, für Handschuhe grösser | Apple HIG 44 pt, Material 48 dp, WCAG 2.5.5 (AAA) 44 px | Hauptknöpfe 56–72 px, der Zähler 84 px, Abstände zwischen Zielen ≥ 8 px |
| Wiedererkennen statt erinnern | Nielsen, Heuristik 6 | Vier Tätigkeiten als Karten mit Bild und einem Satz; die Checkliste zeigt, was erledigt ist |
| Frontline-Apps: wenig Text, kein Fachwort, Offline-Toleranz | Resco/Wednesday-Studien zu Frontline-Apps | Keine Rechnung, kein „Weg 1", kein Modell in der Arbeiter-App; jede Speicherung bestätigt sich sichtbar |

Quellen: <https://www.nngroup.com/articles/wizards/>,
<https://www.nngroup.com/articles/4-principles-reduce-cognitive-load/>,
<https://www.nngroup.com/articles/usability-heuristics-complex-applications/>,
<https://wcag22aa.org/new-criteria/target-size/>,
<https://www.resco.net/blog/mobile-platform-ux-ui/>.

## Die Arbeiter-App

### Zwei Rollen, keine Konten

Die Halle kennt zwei Arten von Beteiligten, und die App unterscheidet sie ohne
Verwaltung:

- **Vorarbeiter** — wer eine Arbeit eröffnet. Er kennt Charge, Bänder und
  Kistensystem, liest den Palox ab, wiegt fertige Paletten und das Faule,
  beantwortet die Fragen und schliesst ab. Er sieht die **Checkliste**.
- **Zähler** — wer einer Arbeit beitritt. Er sieht **einen Zähler** und sonst
  nichts: Paletten mit Datum (und beim Waschen + Sortieren dem Gewicht) vom
  Zettel, Kisten je Kaliber mit Sortierdatum, oder beim Fax die Palettenzahl.

Die Rolle hängt an der Arbeit, nicht an der Person: Eröffner = Vorarbeiter,
Beitretende = Zähler. Ein Tipp auf „Ich führe diese Arbeit" holt die
Vorarbeiter-Ansicht auf jedes Handy — für den Fall, dass das erste ausfällt.
Gespeichert wird die Rolle nicht; sie ist keine Messung.

### Der Weg des Vorarbeiters

1. **Start** — „Läuft gerade" mit den offenen Arbeiten, darunter zwei Knöpfe:
   *Neue Arbeit starten* und *Palette kontrollieren*.
2. **Assistent** — je Schritt eine Frage: Was macht ihr? · Welche Charge? ·
   dann je Tätigkeit: Sortieren fragt *welche Kaliber* (die Maschine kennt
   nur Bänder — „wie zuletzt: übernehmen / anpassen"); Waschen fragt
   *welches Kaliber*; Waschen + Sortieren fragt die Bänder · dann das
   **Kistensystem** (0060): Kiste ab x kg · x Stück je Kaliber · anderes —
   kein Käufer mehr · Alles richtig? Schritte, die für die Tätigkeit nicht
   gelten, gibt es nicht.
3. **Als erstes: Palox ablesen** — die Ablesung steht direkt nach dem Start
   (AB-02) beim Sortieren und beim Waschen + Sortieren. Beim Waschen ist sie
   freiwillig (AB-28). „Später" ist möglich, aber die Checkliste lässt den
   Punkt offen.
4. **Checkliste** — jeder Punkt mit Zustand (erledigt / offen / freiwillig):
   Palox zu Beginn · Zählen (mit Stand) · Fertige Palette wiegen (wo das
   Kistensystem rechenbar ist) · Arbeit abschliessen. Beim Fax: kein Palox —
   dafür *Faules wiegen* (kistenweise, mit Kistenart) und *Paletten gesamt*.
   Zu klein / zu gross wird nicht mehr gewogen (AB-26).
5. **Abschluss-Assistent** — Palox jetzt ablesen (Fax: Faules wiegen) ·
   (Fax: Paletten gesamt, Tage seit dem Waschen) · (Waschen: sind Kisten
   gezählt? Ohne Kisten keine Menge — eine Kilo-Zahl wird nirgends getippt) ·
   Fertige Palette gewogen? · Alles aus einer Charge? · Zusammenfassung →
   *Ja, fertig*. Was fehlt, steht als Satz am Knopf.

### Der Weg des Zählers

Start → Arbeit antippen → **Mitmachen** → der Zähler. Datum vom Zettel oben
(bleibt stehen; der „+"-Knopf zeigt, welches Datum er speichert), beim
Waschen + Sortieren dazu das **Gewicht vom Zettel** (Pflicht, je Palette
neu — Gewichte unterscheiden sich, das Datum nicht), „+" gross in
Daumenreichweite, darunter „Rückgängig". Jede Speicherung bestätigt sich mit
einem kurzen „✓ gespeichert". Beim Waschen + Sortieren steht ein zweiter,
kleinerer Knopf „Palette wiegen" — das Zettelgewicht ist dort schon
eingetragen. Beim Waschen trägt jede Kiste ihr **Sortierdatum** („kein
Datum" ist eine Antwort); beim Fax zählt der Zähler die Paletten gesamt.

## Die Betriebsleiter-Seite

Fünf Reiter, je mit einem Satz darüber, was er beantwortet:

| Reiter | Beantwortet | Woraus |
|---|---|---|
| **Überblick** | Was kam herein, was ging hinaus, was ist verloren — und woran? | Vier Zahlen (Eingang und Ausgeliefert gemessen; Verlust und Noch im Haus gerechnet — das Ausgelagerte aus den Lieferungen, AB-23); „Woran fehlt die Ware?" gesamt oder je Sorte, Schlag, Charge (gestapelte Balken: Palox, Verdunstung, zu klein, zu gross, dazu die Überfüllung; Klick öffnet die Gruppe); „Was ist noch im Haus?" je Gruppe mit verkaufsfähigem Anteil und „liegt seit"; Kaliber je Sorte; Saison im Verlauf mit dem Abstand der Kurven. Keine Vorhersagen, keine Ratschläge — was nicht gewusst werden kann, steht nicht da (AB-18) |
| **Ursachen** | Echter Verlust und kein echter Verlust, jede Ursache in der Tiefe: je Sorte, je Charge, die Messungen dahinter | *Echter Verlust:* Palox — Verderb im Lager (Kurve, Punkte, je Charge gemessen gegen Modell, das Faule je Charge) und Palox beim Abpacken (Fax, mit Tagen seit dem Waschen); Verdunstung (kumulierter Verlust über der Lagerdauer, Raten je Sorte). *Kein echter Verlust:* Sortierung (zu klein, zu gross, Kaliber, Gewichtsverteilung), Überfüllung aus den gewogenen fertigen Paletten, Stück-Kisten gegen die Erwartung aus der CSV. Nie „Buch A/B" (AB-30). Filter Sorte, Schlag und Charge, auch aus dem Überblick heraus |
| **Chargen** | Wo steht welche Charge? | Eingang, ausgeliefert, im Haus (davon verkaufsfähig), „liegt seit" als Spanne (kein FIFO), Verlust, Messungen; Aufklappen zeigt die Eingangstage (Paletten, Eingang, in der App gezählt), die Arbeiten und Lieferungen der Charge |
| **Messungen** | Was weiss die Auswertung — und was nicht? | Datenqualität, fehlende Messungen, Lagerkontrollen, Koeffizienten, Modell |
| **Betrieb** | Was ist heute los, und wie pflege ich die Grundlagen? | Arbeiten (mit „Arbeit und Tempo" je Tätigkeit), Warenausgang (Excel einlesen, Lieferungen), Sortier-CSV, Stammdaten, Zugang |
| **Messungen** (dazu) | Geht die Rechnung auf? | Die Bilanz Eingang = Verlust + Ausgang + Bestand steht hier, weil sie das Modell prüft, nicht den Betrieb |

Jede Zahl trägt ihren Rechenweg; jede Grafik ihre Messpunkte. Was nicht
gemessen ist, steht als „nicht gemessen", nie als 0.

### Was die neuen Erfassungspunkte hergeben

| Seit | Erfasst | Neu daraus |
|---|---|---|
| 0041 | Kisten je Kaliber gezählt, am Sortieren und am Waschbecken | Kistengewicht je Kaliber (gemessen, mit Bereich) |
| 0041 | Datum vom Zettel, Pflicht | Alter der verarbeiteten Ware gegen das Alter im Lager — wird das Älteste zuerst verarbeitet? |
| 0043 | Sortierart je Arbeit, Käufer | Überfüllung je Käufer und Sorte |
| 0044 | Ausschuss gewogen oder geschätzt | Anteil gewogener Messungen (Datenqualität) |
| 0045 | Wie die Kontrollpalette gegriffen wurde | Lagerkontrollen nach Auswahlart |
| 0036 | Palox-Stand je Ablesung | Ablesungen je Arbeit (fehlt eine, sitzt Schimmel am falschen Alter) |
| 0001 | Sortier-CSV als Histogramm | Gewichtsverteilung je Sorte, Schlag, Charge mit Kalibergrenzen (vom Betrieb gewünscht, ABLAUF.md) |
| 0028/0047 | Lieferungen, Vorlauf | Eingang und Ausgang über die Saison |
| 0039 | Start und Ende je Arbeit | Durchsatz je Arbeit und Station; im Überblick „Arbeit und Tempo" je Tätigkeit |
| 0051 | Fax: Kisten gezählt, Faules gewogen | Strom „Faul beim Abpacken" mit Koeffizient je Sorte; der dritte Lagerabschnitt in der Bilanz |
| 0051 | Zetteldatum je gezählter Palette, je Eingangstag verrechnet | Bestand und Alter je Eingangstag statt eines Mittels; Zetteldaten ohne Palette fallen auf |
| 0054 | Eigenes Kaliber am Waschbecken (von–bis), wenn das Etikett keines der Bänder nennt | Kisten zum eigenen Band zählen; Kistengewicht über die Bandgrenzen gefunden oder ehrlich unbekannt |
| 0055 | Warenausgang aus dem Perigon-Excel: Datei, Rohzeilen, Lieferungen in einem Aufruf | Ausgeliefert je Charge (gemessen); damit „Noch im Haus" = Eingang − Ausgang − Modell; Bilanz gegen echte Zahlen |
| 0056 | Wägung, bei der die Palette schwerer wurde als beim Eingang (über 1 %) | Zählt nicht in die Verdunstungsrate; steht unter Auffälligkeiten mit Grund und Rat. Die Rate je Sorte ist nie negativ, die Basis für den Schimmelanteil nie über dem Eingang |
| 0057 | Stand der Datenbank (`schema_stand()`) | Die App vergleicht ihn mit `SCHEMA_ERWARTET` und verlangt bei Abweichung `setup.sql` — statt an alten Formeln zu scheitern. `supabase/diagnose.sql` für den SQL-Editor |
| 0058 | Eine Zahl, die nicht in ihre Spalte passt | Wird unbekannt („—") statt die ganze Sicht abzubrechen. Anteile sind auf 0 … 1 geklammert, Massen nie negativ; die Bilanz nennt einen fehlenden Wareneingang beim Namen |
| 0059 | Eine Sicht, die sich nicht lesen lässt | Die App lädt jede für sich — nur ihre Zahlen fehlen, der Bildschirm steht. Oben nennt eine Karte die betroffenen Sichten und den Grund |
| 0060 | Verkaufte Lieferungen je Charge und Eingangstag | „Ausgelagert" und „noch im Haus" aus Eingang und Ausgang statt aus gezählten Paletten (AB-23); Überzählung als Befund, wenn hinter den Lieferungen mehr steckt als je einlagert wurde |
| 0060 | Gewicht vom Zettel je gezählter Palette (Waschen + Sortieren) | Die Masse der Handlinie ohne zweite Wägung; ein Zettelgewicht ohne Palette im Wareneingang fällt auf (AB-26) |
| 0060 | Kistensystem je Arbeit, fertige Paletten mit Kaliber | Überfüllung aus dem Soll an der Arbeit; bei Stück-Kisten die Erwartung aus der CSV (Information, keine Marge); die Palettenmasse je Sorte und Kistensystem als Nenner des Fax (AB-24, AB-25) |
| 0060 | Fax: Paletten gesamt, Tage seit dem Waschen | Fax-Masse aus Paletten × Palettenmasse; der Waschschaden gegen das Liegen nach dem Waschen |
| 0060 | Sortierdatum je gezählter Kiste beim Waschen | Kisten je Kaliber über die Sortierdaten summiert; „kein Datum" ist eine Antwort (AB-27) |
| 0060 | Palox je Station (Waschstrasse, Sortiermaschine), gefallener Stand | Eine Arbeit mit geleertem Palox hat keine Menge — nie eine negative (AB-28) |
| 0060 | Kontrolle mit Vorschlag, Eingangsdatum und -gewicht | Drei Chargen, bei denen eine Kontrolle am meisten bringt; mehrere Paletten hintereinander (AB-29) |
