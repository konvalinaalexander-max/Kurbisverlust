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

- **Vorarbeiter** — wer eine Arbeit eröffnet. Er kennt Charge, Käufer und
  Sortierart, liest den Palox ab, wiegt den Ausschuss, beantwortet die Fragen
  und schliesst ab. Er sieht die **Checkliste**.
- **Zähler** — wer einer Arbeit beitritt. Er sieht **einen Zähler** und sonst
  nichts: Paletten mit dem Datum vom Zettel, oder Kisten je Kaliber.

Die Rolle hängt an der Arbeit, nicht an der Person: Eröffner = Vorarbeiter,
Beitretende = Zähler. Ein Tipp auf „Ich führe diese Arbeit" holt die
Vorarbeiter-Ansicht auf jedes Handy — für den Fall, dass das erste ausfällt.
Gespeichert wird die Rolle nicht; sie ist keine Messung.

### Der Weg des Vorarbeiters

1. **Start** — „Läuft gerade" mit den offenen Arbeiten, darunter zwei Knöpfe:
   *Neue Arbeit starten* und *Palette kontrollieren*.
2. **Assistent** — je Schritt eine Frage: Was macht ihr? · Welche Charge? ·
   Für wen? · dann je Tätigkeit (0051): Sortieren fragt *welche Kaliber*
   (die Maschine kennt nur Bänder — „wie zuletzt: übernehmen / anpassen");
   Waschen fragt *welches Kaliber*; Waschen + Sortieren fragt Kiste oder
   Kaliber und dann das Sollgewicht bzw. die Bänder; Fax fragt, was für
   Kisten es sind (Kaliber-Kisten oder nach Sollgewicht) · Alles richtig?
   Schritte, die für die Tätigkeit nicht gelten, gibt es nicht.
3. **Als erstes: Palox ablesen** — die Ablesung steht direkt nach dem Start
   (AB-02). „Später" ist möglich, aber die Checkliste lässt den Punkt offen.
4. **Checkliste** — jeder Punkt mit Zustand (erledigt / offen / freiwillig):
   Palox zu Beginn · Ausschuss-Paletten leer? · Zählen (mit Stand) ·
   Zu klein / zu gross wiegen · Fertige Palette wiegen · Arbeit abschliessen.
   Beim Fax (0051): kein Palox, kein Ausschuss — dafür *Faules wiegen*
   (kistenweise, mit Kistenart) und *Kisten gemacht* (je Kaliber, „+ 1
   Palette").
5. **Abschluss-Assistent** — Palox jetzt ablesen (Fax: Faules wiegen) ·
   Ausschuss: alles von dieser Arbeit? · (Waschen, Fax: sind Kisten gezählt?
   Ohne Kisten keine Menge — eine Kilo-Zahl wird nirgends mehr getippt) ·
   Alles aus einer Charge? · Zusammenfassung → *Ja, fertig*. Was fehlt,
   steht als Satz am Knopf.

### Der Weg des Zählers

Start → Arbeit antippen → **Mitmachen** → der Zähler. Datum vom Zettel oben
(bleibt stehen), „+" gross in Daumenreichweite, darunter „Rückgängig". Jede
Speicherung bestätigt sich mit einem kurzen „✓ gespeichert". Beim Waschen +
Sortieren steht ein zweiter, kleinerer Knopf „Palette wiegen" — der einzige
Umweg, den ein Zähler je sieht.

## Die Betriebsleiter-Seite

Fünf Reiter, je mit einem Satz darüber, was er beantwortet:

| Reiter | Beantwortet | Woraus |
|---|---|---|
| **Überblick** | Was kam herein, was ging hinaus, was ist verloren — und woran? | Vier Zahlen (Eingang und Ausgang gemessen, Verlust und Bestand Modell); Hauptursachen gesamt oder je Sorte, Schlag, Charge (gestapelte Balken, Tonnen oder Anteil, Klick öffnet die Gruppe); Noch im Haus je Gruppe mit „liegt seit"; Kaliber je Sorte; Saison im Verlauf. Keine Vorhersagen, keine Ratschläge — was nicht gewusst werden kann, steht nicht da (AB-18) |
| **Ursachen** | Vier Ursachen, jede in der Tiefe: je Sorte, je Charge, die Messungen dahinter | Verderb (Kurve, Punkte, je Charge gemessen gegen Modell); Verdunstung (kumulierter Verlust über der Lagerdauer, Sortenlinie, Raten je Sorte); Sortierung (zu klein, zu gross, Kaliber, Gewichtsverteilung, Überfüllung); Faul beim Abpacken (Rate je Sorte und Charge). Filter Sorte und Schlag, auch aus dem Überblick heraus |
| **Chargen** | Wo steht welche Charge? | Eingang, im Lager, sortiert, ausgeliefert, „liegt seit" als Spanne (kein FIFO), Verlust; Aufklappen zeigt die Eingangstage (gekommen, gezählt, noch da), die Arbeiten und Lieferungen der Charge |
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
