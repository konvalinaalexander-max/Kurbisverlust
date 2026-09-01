# Was auf dem Betrieb wirklich passiert

Diese Datei beschreibt den Ablauf, **unabhängig davon, was gemessen wird**.
Sie ist der Massstab, an dem sich Datenmodell und Oberflächen messen lassen
müssen. Wo das Modell etwas annimmt, das niemand geprüft hat, steht es als
Annahme da — unmarkierte Annahmen sind der Anfang jedes stillen Fehlers.

## Was der Betrieb bestätigt hat (1. September)

Diese Punkte sind keine Annahmen mehr.

| Punkt | Stand |
|---|---|
| Charge = **Schlag × Sorte** | bestätigt; Schlag ist die benannte Herkunft, nicht „Feld" |
| **Die Saison läuft bereits** | Ein Teil der Ernte liegt schon, ein Teil ist schon ausgeliefert — ohne App-Erfassung. Es braucht einen **Erfassungsbeginn** und je Charge eine grobe Angabe, was vorher schon rausging. |
| Weg 1: Paletten werden **nie** gewogen | bestätigt, über den ganzen Weg nicht. Verdunstung ist damit **nur** auf Weg 2 und über die Lagerkontrolle messbar. |
| Vor dem Sortierband wird Faules aussortiert | bestätigt |
| Eingangsdatum beim Zählen | soll **immer Pflicht** sein, auf beiden Wegen — damit der Palox-Inhalt einem Alter zugeordnet werden kann |
| Chargennummer **eintippen** statt aus einer Liste wählen | gewünscht, geht schneller |
| **Sortierdatum auf die Kaliber-Kiste schreiben** | machbar, der Betrieb spricht mit den Mitarbeitern. Beim Waschen wird danach gefragt, mit der Möglichkeit zu überspringen. |
| Die 8-kg-Kiste gilt **nur für eine Sorte** | Andere Sorten werden nach Kategorien sortiert (zu klein / Bänder / zu gross). Das Schema gehört je Sorte hinterlegt und beim Auftragsstart bestätigt, mit der Möglichkeit, es vor Ort zu ändern. |
| Ausschuss soll **gewogen** werden | auf Palette stellen, Kistenzahl und Gewicht erfassen — statt Schätzung nach Augenmass |
| Fast alles gehört **an den Abschluss** | Während der Arbeit nur zählen (und gelegentlich wiegen); alles andere als geführter Ablauf beim Abschliessen |

### Der Palox: Stand bei Beginn **und** bei Abschluss

Vom Betrieb vorgeschlagen und deutlich besser als die bisherige Kette: Wer den Auftrag
eröffnet, liest den Palox-Stand ab; wer ihn abschliesst, ebenso. Die Differenz ist die Menge
**dieser** Arbeit — ohne Abhängigkeit von der Ablesung der vorigen. Ein vergessenes Ablesen
verdirbt dann nur eine Arbeit statt einer ganzen Kette.

**Voraussetzung, noch ungeprüft:** dass zwischen beiden Ablesungen niemand anders in denselben
Behälter wirft. Laufen zwei Gruppen parallel an einer Station, bräuchte es eine
Behälter-Kennung.

### „War alles aus einer Charge?"

Beim Abschliessen wird gefragt. Bei **Nein** fliesst die Messung nicht ins Verderbsmodell ein —
das Alter wäre geraten. Sie zählt weiter in der Massenbilanz, und die Nachfrage „war es
wenigstens dieselbe Sorte?" hält fest, was sich noch verwerten lässt.

Auch bei **Ja** enthält der Palox Faules aus Paletten verschiedener Eingangsdaten. Die App
rechnet deshalb nicht mit dem Durchschnittsalter, sondern vergleicht den gemessenen Anteil mit
dem, was das Modell über die **tatsächliche Altersverteilung** der gezählten Paletten erwarten
würde. Weil der Verderb mit der Zeit beschleunigt, ist beides nicht dasselbe: Wer mit dem
Durchschnittsalter rechnet, unterschätzt systematisch.

### „Fax" — ein Arbeitsschritt, den das Modell nicht kannte

Nach dem Waschen steht die Ware nochmals ein bis zwei Tage, dann wird für die Bestellungen
abgepackt. Dabei wird **nochmals Faules aussortiert** — zu klein und zu gross spielen dort keine
Rolle mehr.

Entscheidend: Dieser Schimmel kommt **nicht von der Lagerdauer**, sondern von der mechanischen
Beanspruchung beim Waschen. Er darf deshalb nicht in die Verderbskurve einfliessen, sondern
bekommt einen eigenen Strom — *Schäden nach dem Waschen*, bezogen auf die gewaschene Menge statt
auf die Zeit. Die Massnahme dagegen ist eine andere (sanfter waschen, kürzer stehen lassen), und
solange beides in einem Balken steckt, weiss niemand, welche hilft.

### Was der Betriebsleiter aus der Sortier-CSV erfahren will

Nicht nur den Kaliber-Anteil, sondern die **Gewichtsverteilung**: Balken in wählbarer Breite
(25/50/100 g), die Kaliber-Grenzen darübergelegt, mehrere Verteilungen nebeneinander — nach
Sorte, nach **Schlag**, nach Charge. Damit lässt sich sehen, ob eine Verteilung glockenförmig
oder zweigipflig ist, wo ihr Schwerpunkt relativ zu den Grenzen liegt, und ob sich Schläge
unterscheiden. Das ist eine Aussage über den Anbau, nicht über das Lager.

### Braucht die Sortier-CSV ein Datum?

Nötig ist **nur die Chargennummer**. Ohne Datum funktionieren die Gewichtsverteilung und ein
Ausschussanteil über die Saison. Das Datum bringt zusätzlich zweierlei: eine Gegenprobe
(gezählte gegen gewogene Masse desselben Tages) und eine Zeitachse für den Ausschuss — Kürbisse
werden mit der Lagerdauer leichter, also rutschen mit der Zeit mehr unter die Verlustgrenze.
Niemand soll ein Datum tippen: Die App nimmt den Dateinamen, sonst den Zeitstempel der Datei,
sonst geht es auch ohne. *Achtung:* Werden zwanzig Dateien am Saisonende auf einmal kopiert, ist
der Zeitstempel das Kopierdatum und wertlos.

## Der Weg eines Kürbisses

```
Feld (Schlag)
   │  geerntet, gestaffelt über Tage und Wochen
   ▼
Wareneingang ──────────── Palette: Charge, Datum, Brutto, Kisten, Gebinde
   │                      (Erntejournal-App, eigenes Repo)
   ▼
┌─ LAGER ─────────────── eine Halle, gleiche Bedingungen für alle
│      │
│      ├── Weg 2 (Hand) ──── Waschen + Sortieren in einem Schritt ──► raus
│      │
│      └── Weg 1 (Maschine) ─ Sortieren ─┐
│                                        │
└────────────────────────────────────────┘   zurück in dieselbe Halle,
       Kaliber-Kisten, Wochen bis Monate     die Original-Palette gibt es nicht mehr
                    │
                    ▼
              Waschen ──► raus
```

Der entscheidende Punkt, den das Modell bis 0024 nicht kannte: **Weg 1 hat
zwei Lagerabschnitte.** Zwischen Sortieren und Waschen steht die Ware wieder in
derselben Halle — in Kaliber-Kisten statt auf der Original-Palette, aber am
selben Ort, unter denselben Bedingungen, und sie verdunstet und verdirbt
weiter. Der Betrieb bestätigt: **alles, was sortiert wurde, wird später
gewaschen.**

## Wo Masse verschwindet, und wer es merkt

| Stelle | Was passiert | Wird es erfasst? |
|---|---|---|
| Lager, laufend | Wasserverlust | über gelegentliche Palettenwägungen |
| Lager, laufend | Kürbisse verderben | erst beim Verarbeiten sichtbar |
| Vor dem Sortierband | Faules aussortiert → Palox | ja, Palox-Waage |
| Sortierband | zu klein → weg, zu gross → anderer Kanal | ja, aus der CSV |
| Zweiter Lagerabschnitt | Wasserverlust und Verderb gehen weiter | seit 0024 |
| Vor dem Waschbecken | Faules nochmals aussortiert (**Schimmel #2**) | seit 0024 |
| Kisten füllen | 8-kg-Kisten wiegen real 8.1–8.5 kg | ja, fertige Paletten |
| Warenausgang | Ware verlässt den Betrieb | seit 0028 |

## Die Behälter, und wann Identität verloren geht

- **Palette** — die Erfassungseinheit beim Wareneingang. Eine Palette gehört zu
  genau einer Charge und hat ihr eigenes Eingangsdatum.
- **Kaliber-Kiste** — entsteht beim Sortieren. Ab hier **löst sich die Palette
  auf**: Die Kürbisse einer Palette landen je nach Gewicht in verschiedenen
  Kisten, und eine Kiste sammelt aus vielen Paletten. Die Charge bleibt bekannt,
  das Eingangsdatum der einzelnen Palette nicht mehr.
- **Palox** — der Sammelbehälter für Faules. Er steht auf einer Waage und läuft
  über mehrere Arbeiten weiter; der Zuwachs zwischen zwei Ablesungen ist die
  Menge einer Arbeit. Der Stand wird **je Station** geführt — Sortierband,
  Waschbecken und Hand-Linie sind verschiedene Arbeitsplätze mit je eigenem
  Behälter. Wird der Palox geleert und wieder befüllt, meldet es der Arbeiter
  mit einem Häkchen; als Prüfgrösse zeigt die Maske die Menge je gezählter
  Palette und warnt, wenn sie unplausibel gross wird (meist: eine Ablesung
  wurde vergessen).

  **Annahme, ungeprüft:** je Station genau ein Palox. Arbeiten zwei Teams an
  derselben Station parallel, bräuchte es eine Behälter-Kennung.

**Annahme, ungeprüft:** Beim Waschen wird die Charge des Waschgangs der Charge
des Sortierlaufs gleichgesetzt, und welcher Sortierlauf zu welchem Waschgang
gehört, wird über die Reihenfolge geschlossen (was vorher sortiert wurde, kann
vorher gewaschen worden sein). Ein ausdrücklicher Verweis vom Waschgang auf den
Sortierlauf wird nirgends erfasst. In der Simulation kostet diese Annäherung
rund 2 % beim Schimmel — genug, um sie zu nennen, zu wenig, um dem Arbeiter
ein Feld mehr zuzumuten.

## Wie die Ware das Zwischenlager verlässt

Der Betrieb hat klargestellt: **kein First-in-first-out.** Aus den
Kaliber-Kisten wird ziemlich zufällig entnommen — an jedem Waschtag hat jede
Kiste im Pool dieselbe Chance. Ein Prozess ohne Gedächtnis; der
Simulations-Harness bildet ihn seit dieser Runde mit exponentialverteilten
Wartezeiten ab. Unter genau dieser Entnahme ist der Mittelwert über die
vorherigen Sortierläufe einer Charge der richtige Erwartungswert für den
Zustand der gewaschenen Ware — nachgemessen, nicht nur argumentiert
(`docs/STATISTIK_BEFUND.md`).

## Wer entscheidet, was als nächstes drankommt

Das ist keine Nebensache, sondern die grösste verbliebene Fehlerquelle. Wird
verarbeitet, was schlecht aussieht, dann werden anfällige Paletten früh
gemessen und robuste spät — der gemessene Verderbsverlauf wird flacher als der
wahre, und die Hochrechnung auf lange Lagerdauern zu niedrig.

Aus Verarbeitungsmessungen allein lässt sich das nicht heilen: Alter und
Anfälligkeit sind durch die Reihenfolge vermengt. Was hilft, ist eine Messung,
deren Auswahl nicht am Zustand hängt — gelegentlich eine **zufällig gegriffene
Palette im Lager** aufmachen und notieren, wie viel faul ist. Dafür gibt es
seit dieser Runde einen eigenen Einstieg auf dem Startbildschirm des
Arbeiters („Palette kontrollieren"), ohne laufende Arbeit. „Davon faul" ist
dort Pflicht, und 0 ist eine echte Antwort — ein leeres Feld wäre „nicht
nachgesehen". Details und Wirkung: `docs/STATISTIK_BEFUND.md`.

## Was den Betrieb sonst noch verlässt

Neben dem Verkauf gibt es Wege, auf denen Ware ohne Lieferschein geht:
Hofladen, Tierfutter, Kompost, Eigenbedarf. Jeder davon ist Masse, die aus der
Bilanz verschwindet — und **fehlende Masse sieht in einer Bilanz immer aus wie
Verlust**. Seit 0028 hat jede Lieferung ein Ziel, und das Ziel entscheidet, in
welches Buch sie fällt: Kompost ist echter Verlust, Tierfutter ist ein anderer
Kanal, Hofladen ist Verkauf.

**Offen:** Welche dieser Wege es auf dem Betrieb tatsächlich gibt und wie viel
darüber geht, ist noch nicht beantwortet. Die Ziele sind angelegt und lassen
sich in `ausgang_ziel` ergänzen, ohne dass etwas umgebaut werden muss.

## Was wir vom Warenausgang brauchen — und was nicht

**Nicht** die Gewichte einzelner Paletten. Die kennt der Betrieb gar nicht, und
für das Ziel — Ursachen rangieren — braucht es sie auch nicht.

Genug ist, was ohnehin auf dem Lieferschein steht, weil danach verrechnet wird:
**Datum, Sorte, und entweder Kilo oder Kistenzahl.** Kisten werden über das
gemessene Kilo je Kiste umgerechnet, und die zusätzliche Unsicherheit steht je
Zeile dabei, statt verschwiegen zu werden.

Selbst eine grobe Monatssumme je Sorte wäre ein grosser Gewinn: Erst mit dem
Ausgang hört der Restbestand auf, eine reine Projektion zu sein, und die Lücke
in der Bilanz wird zur einzigen Zahl, die misst, was das Modell **nicht** sieht.

**Offen:** In welcher Einheit der Lieferschein die Menge führt. Die Maske nimmt
beides, die Antwort ändert nichts am Aufbau — nur daran, wie genau die Bilanz
schliesst.

## Was zwischen zwei Saisons passiert

Der Stichtag steht in den Einstellungen (`saison_ende`). Bis dahin wird alles
projiziert, was noch im Haus ist. Was danach mit Restbeständen geschieht, ist
im Modell nicht abgebildet — es kennt nur „bis zum Stichtag gelagert".

**Offen und bisher nicht gefragt:** Ob Restbestände in die neue Saison
übernommen werden, und ob sie dann noch derselben Charge zugerechnet bleiben.

## Annahmen, die im Modell stecken

Jede einzelne ist eine Stelle, an der die Rechnung von der Wirklichkeit
abweichen kann, ohne dass es jemand merkt.

| Annahme | Warum sie drinsteht | Was passiert, wenn sie nicht stimmt |
|---|---|---|
| Alle Paletten einer Charge liegen unter gleichen Bedingungen | eine Halle (Spec §1) | Streuung zwischen Lagerplätzen landet im Fehler, nicht im Modell |
| Die Verdunstungsrate ist über die Zeit konstant | eine Wägung je Palette gibt keinen Verlauf her | früher Wasserverlust wird unter-, später überschätzt |
| Alles Sortierte wird später gewaschen | vom Betrieb bestätigt | Ware, die ungewaschen rausgeht, altert in der Rechnung zu lange |
| Der Palox gehört zu der Arbeit, an deren Ende er abgelesen wird | Waage, Differenzbildung | sammelt er über Arbeiten hinweg unbemerkt, sitzt Schimmel am falschen Alter |
| Ein Waschgang gehört zu den Sortierläufen derselben Charge davor | kein erfasster Verweis | bei stark gemischten Chargen wandert Schimmel #2 ans falsche Alter |
| Die Dubletten-Regel entfernt Maschinen-Doppel, keine echten Kürbisse | Nachbar-Gleichheit 12–28 % gegen < 0.2 % Zufall | alle CSV-gestützten Massen sind entsprechend daneben |
| Kaliber-Grenzen gelten über die ganze Saison | Stammdaten | Umstellungen mitten in der Saison verfälschen den Ausschussanteil |
