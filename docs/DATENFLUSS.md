# Was hinein geht, was herauskommt

Eine Landkarte des ganzen Systems: welche Zahl erfasst wird, was daraus
gerechnet wird, und wo sie beim Betriebsleiter wieder auftaucht.

Zum Ausprobieren: der Knopf „Demo-Daten" unter Stammdaten (oder auf der
leeren Auswertung) legt eine erfundene, aber stimmige Saison an (461 t
Eingang, 10 Chargen, 29 Arbeiten) und räumt sie restlos wieder weg.

---

## 1. Was erfasst wird

### Aus dem Erntejournal — automatisch, je Palette

| Feld | Woher |
|---|---|
| Charge (über Schlag × Sorte) | Google Sheet |
| Eingangsdatum | Google Sheet |
| Bruttogewicht, Kistenzahl, Gebindeart | Google Sheet |

→ **Netto** = Brutto − Palettentara − Kisten × Kistentara.
Das ist das *Rückgrat*: für jede Charge sicher bekannt, ohne dass jemand messen muss.

### Vom Arbeiter — je Arbeit

| Erfassung | Wo | Felder |
|---|---|---|
| Neue Arbeit | Start | Tätigkeit, Charge, Käufer (bestimmt das Sortierschema; neue Käufer legt der Arbeiter selbst an) |
| Palette zählen | Sortieren, Waschen + Sortieren | Anzahl, Datum vom Zettel |
| Palette wiegen | Waschen + Sortieren (Frage bei jedem Zählen) | Eingangsdatum, Eingangsgewicht, Gewicht jetzt, Kisten, Kistenart, optional Kürbisse je Kiste |
| Palette kontrollieren | ohne Arbeit, vom Startbildschirm | wie Wiegen, dazu Pflichtfeld „davon faul" (0 ist eine Antwort) |
| Faule | überall | Stand der Palox-Waage (brutto); die Menge leitet die Datenbank ab, mit Behälter-Tara aus den Einstellungen; Häkchen „war zwischendurch leer" |
| Zu klein / zu gross | Waschen + Sortieren | kg |
| Fertige Palette | Waschen, Waschen + Sortieren | Gewicht, Kisten, Kistenart, optional Kürbisse je Kiste |
| Abschluss | überall | „War alles aus einer Charge?", bei Nein „wenigstens dieselbe Sorte?"; beim Waschen: Sortierdatum von der Kiste; verarbeitete Menge (Waschen) |

Dazu automatisch: wer, wann, welche Charge, welche Station, welche Fassung des
Sortierschemas — Start- und Endzeit vom Server, nicht vom Handy. Die
Antworten aus dem Abschluss sind Messwerte (`auftrag_angabe`): „nicht alles
aus einer Charge" nimmt die Messung aus dem Zeitmodell, nicht aus der Bilanz.

### Vom Betriebsleiter

| Erfassung | Ergebnis |
|---|---|
| Sortier-CSV hochladen | Einzelgewicht jedes Kürbisses, gereinigt und nach der Fassung des Auftrags klassiert |
| Sortierschemata | je Sorte und Käufer, datiert — nie überschrieben, nur neue Fassungen |
| Gebinde-Tara, Palox-Tara | machen aus Brutto ein Netto |
| Warenausgang | Lieferschein: Datum, Sorte, Kilo oder Kisten, Ziel |
| Stichtag der Hochrechnung | wie weit die Projektion reicht |

---

## 2. Was daraus gerechnet wird

Vier Koeffizienten aus Stichproben, angewandt auf das für jede Charge bekannte
Rückgrat. Jeder trägt seine Unsicherheit und seine Herkunft mit.

| Koeffizient | Aus welcher Messung | Formel |
|---|---|---|
| **Verdunstung** je Tag | Palettenwägungen | `r = 1 − (netto_jetzt / netto_damals)^(1/Lagertage)` |
| **Sockel a₀** (nicht lagerbedingt) | dieselben Palox-Messungen, über verschieden lange Lagerdauern | `Anteil(t) = a₀ + (1 − a₀)·F(t)`; nur gesetzt, wenn die Daten ihn belegen |
| **Schimmel** F(t) | Faule ÷ Masse am Verarbeitungstag, Lagerkontrollen | `F(t) = 1 − exp(−λ·t^k)`, chargen-robust gefehlert |
| **Zu klein** | Sortier-CSV (unter der Grenze der Fassung) oder Handmessung | Anteil an der Masse am Band |
| **Zu gross** | Sortier-CSV (ab der Grenze der Fassung) oder Handmessung | Anteil an der Masse am Band |
| **Überfüllung** je Kiste | fertige Palette | `(Brutto − Palette − Kisten × Tara) / Kisten − Soll`, Soll aus der Fassung oder der Einstellung |

Je Sorte, zum Gesamtwert gezogen, soweit die eigene Stichprobe nicht trägt
(empirisches Bayes). Welcher Fall gilt, steht an jeder Zahl. Ohne einzige
Messung ist ein Koeffizient unbekannt — nicht null.

### Die Massenkaskade

Jede Charge zerfällt in zwei Portionen — **ausgelagert** (verarbeitet,
Lagerdauer beobachtet) und **im Lager** (rechts-zensiert, bis zum Stichtag
projiziert). Auf beide läuft dieselbe Rechnung:

```
Eingang ──Verdunstung──▶ M1 ──Sockel──▶ ──Schimmel──▶ M2 ──zu klein / zu gross──▶ verkaufsfähig
```

Jeder Anteil bezieht sich auf die Masse, die in *seinen* Schritt hineingeht —
nur so addieren sich die Ströme genau zur Portion, ohne Basen zu vermischen.

Der Bereich entsteht aus Fehlerfortpflanzung: für jeden Strom die
Empfindlichkeit gegenüber jedem Koeffizienten, zusammengesetzt nach der
tatsächlichen Korrelation. Das Alter der noch liegenden Ware kommt aus den
Paletten, die noch da sind — nicht aus dem Mittel der ganzen Charge.

---

## 3. Wie es beim Betriebsleiter ankommt

### Ebene 1 — Überblick

Eingang, Verlust gesamt, Hauptursache. Darunter die Ursachen als Balken,
absteigend sortiert. Voller Balken = beobachtet, schraffiert = hochgerechnet,
Strich darüber = Unsicherheitsbereich.

Beruht ein Strom auf weniger als drei Messungen, steht **dünne Datenlage**
daneben und darunter ein Kasten: *diese Rangfolge kann sich noch drehen.*

Ganz oben, falls vorhanden: unplausible Messungen mit Diagnose
(*„4500 kg Schimmel auf 5144 kg Ware — das wären 87 %"*), Messungen ohne
Nenner (*„80 kg Faules erfasst, aber keine Palette gezählt"*), Wägungen ohne
verwertbare Tara. Sie zählen nicht mit, verschwinden aber nicht — und sagen,
was nachzutragen ist. Ein Strom ohne einzige Messung steht als „nicht
gemessen" da, nicht als 0.

### Ebene 2 — Aufschlüsselung

Filter nach Sorte, Schlag und Lagerdauer. Dann:

- **Buch A — Lagerverlust:** Verdunstung, Schimmel.
- **Nicht lagerbedingt:** die Grundaussortierung vom Feld (Erde, Hagelnarben,
  Schnittfehler). Physisch weg, aber kein Lagerverlust — steht für sich.
- **Buch B — anderer Kanal, verschenkte Marge:** zu klein (an die Tiere), zu
  gross (Nebenkanal), Überfüllung. Die Ware verlässt den Betrieb — nur nicht
  zum besten Preis. Wird nie mit Buch A vermischt.

An jedem Strom ein aufklappbarer **Rechenweg**: Formel, Bezugsmasse,
Koeffizient samt Herkunft, Ergebnis, Bereich, beobachtet gegen projiziert.

### Ebene 3 — hinter die Blackbox

| Ansicht | Beantwortet |
|---|---|
| **Die vier Koeffizienten** | Worauf beruht die Rechnung? Wert, Anzahl Messungen, Herkunft |
| **Schimmelkurve** | Je Altersklasse: gemessen, verwendet, und *warum* sie abweichen |
| **Kaliber-Verteilung** | Wie verteilt sich eine Sorte über die Bänder? (Erlös, nicht Verlust) |
| **Massenbilanz** | Trifft das Modell die Wirklichkeit? Modell am Band gegen gewogene CSV |
| **Gewogene Paletten** | Netto damals/jetzt, Verlust, kg je Kiste, kg je Kürbis |
| **Wo fehlen Messungen** | Größte Chargen ohne Stichprobe — dort bringt Messen am meisten |
| **Hochrechnung je Charge** | Jede Zeile einzeln, mit CSV-Export |

Dazu jederzeit der direkte Weg: Supabase → Table Editor / SQL. Alle
Ausgabespalten sind `numeric`, `select round(kg,1) from v_verlust_ranking`
funktioniert also ohne Umweg.

---

## 4. Die Selbstkontrolle

Das Modell prüft sich an der Wirklichkeit: Es sagt voraus, wie viel Masse am
Sortierband ankommen müsste; die CSV hat sie gewogen.

Verglichen wird nur, was auch wirklich über das Band lief — geht eine Charge
teils von Hand, wird das Modell auf den CSV-Anteil heruntergerechnet. Ohne das
zeigte die Bilanz dauerhaft ein Defizit, ohne dass etwas falsch wäre.

- Streuung um 0 → die Koeffizienten treffen.
- Systematisch in eine Richtung → ein Koeffizient ist schief.

In der Demo-Saison: −4.5 %, −1.2 %, +3.8 %.

---

## 5. Was das System nicht weiß

- **Warenausgang** wird von Hand erfasst; der Import aus Perigon wartet auf
  die Vorlage. Die Saisonbilanz (Eingang = Verlust + Ausgang + Bestand) sagt,
  wie weit der Ausgang gedeckt ist, bevor sie eine Lücke ausweist.
- **Preise** fehlen. Buch B rechnet in Kilogramm, nicht in Franken.
- **Restbestand am Stichtag** ist eine Projektion, kein Inventar.
- Bei **einer einzigen Charge** gibt es keinen Bereich — dann steht der
  Punktwert allein da, und `koeff_n` sagt warum.
- **Die verarbeitete Menge am Waschbecken (Weg 1)** ist die einzige Zahl, die
  ein Arbeiter schätzen statt ablesen muss. Fehlt sie, meldet die Auswertung
  die Schimmelmessung als „ohne Nenner".
