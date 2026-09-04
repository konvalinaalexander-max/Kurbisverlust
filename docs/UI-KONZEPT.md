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
   Für wen? · Wie sortiert ihr? (oder: Welches Kaliber?) · Alles richtig?
   Schritte, die für die Tätigkeit nicht gelten, gibt es nicht.
3. **Als erstes: Palox ablesen** — die Ablesung steht direkt nach dem Start
   (AB-02). „Später" ist möglich, aber die Checkliste lässt den Punkt offen.
4. **Checkliste** — jeder Punkt mit Zustand (erledigt / offen / freiwillig):
   Palox zu Beginn · Ausschuss-Paletten leer? · Zählen (mit Stand) ·
   Zu klein / zu gross wiegen · Fertige Palette wiegen · Arbeit abschliessen.
5. **Abschluss-Assistent** — Palox jetzt ablesen · Ausschuss: alles von dieser
   Arbeit? · Alles aus einer Charge? · (Waschen: Menge, Sortierdatum) ·
   Zusammenfassung → *Ja, fertig*. Was fehlt, steht als Satz am Knopf.

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
| **Überblick** | Wie viel verliere ich, woran, und was tue ich als nächstes? | Kennzahlen, Kaskade, Bilanz, nächste Chargen, Auffälligkeiten |
| **Ursachen** | Warum? Wie sicher ist das? | Je Strom Balken mit Bereich und Rechenweg; Verderbskurve mit Messpunkten; Verdunstung; Sorten; Sockel; Buch B; Kaliber und Gewichtsverteilung |
| **Chargen** | Wo steht welche Charge? | Eingang, im Lager, sortiert, ausgeliefert, Alter, Verlust; Aufklappen zeigt die Arbeiten und Messungen der Charge |
| **Messungen** | Was weiss die Auswertung — und was nicht? | Datenqualität, fehlende Messungen, Lagerkontrollen, Koeffizienten, Modell |
| **Betrieb** | Was ist heute los, und wie pflege ich die Grundlagen? | Arbeiten, Warenausgang, Sortier-CSV, Stammdaten, Zugang |

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
| 0039 | Start und Ende je Arbeit | Durchsatz je Arbeit und Station |
