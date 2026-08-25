# Was hinein geht, was herauskommt

Eine Landkarte des ganzen Systems: welche Zahl erfasst wird, was daraus
gerechnet wird, und wo sie beim Betriebsleiter wieder auftaucht.

Zum Ausprobieren: `supabase/demo_daten.sql` legt eine erfundene, aber
stimmige Saison an (461 t Eingang, 10 Chargen, 22 Arbeiten).
`supabase/demo_daten_entfernen.sql` räumt sie restlos wieder weg.

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
| Palette zählen | Sortieren, Waschen + Sortieren | Anzahl, optional Datum vom Zettel |
| Palette wiegen | Waschen + Sortieren (Frage bei jedem Zählen) | Eingangsdatum, Eingangsgewicht, Gewicht jetzt, Kisten, Kistenart, optional Kürbisse je Kiste |
| Faule | überall | kg (ganzzahlig) |
| Zu klein / zu gross | Waschen + Sortieren | kg |
| Fertige Palette | Waschen, Waschen + Sortieren | Gewicht, Kisten, Kistenart, optional Kürbisse je Kiste |
| Verarbeitete Menge | Waschen | kg (beim Abschluss) |

Dazu automatisch: wer, wann, welche Charge, welche Station — Startzeit vom
Server, nicht vom Handy.

### Vom Betriebsleiter

| Erfassung | Ergebnis |
|---|---|
| Sortier-CSV hochladen | Einzelgewicht jedes Kürbisses, gereinigt und klassiert |
| Gebinde-Tara | macht aus Brutto ein Netto |
| Stichtag der Hochrechnung | wie weit die Projektion reicht |

---

## 2. Was daraus gerechnet wird

Vier Koeffizienten aus Stichproben, angewandt auf das für jede Charge bekannte
Rückgrat. Jeder trägt seine Unsicherheit und seine Herkunft mit.

| Koeffizient | Aus welcher Messung | Formel |
|---|---|---|
| **Verdunstung** je Tag | Palettenwägungen | `r = 1 − (netto_jetzt / netto_damals)^(1/Lagertage)` |
| **Schimmel** je Lagerdauer | Faule ÷ Masse am Verarbeitungstag | kumulative Kurve über Altersklassen |
| **Ausschuss zu klein** | Sortier-CSV (Massenanteil unter der Sortengrenze) oder Handmessung | Anteil an der Masse am Band |
| **Nebenkanal zu gross** | Sortier-CSV (ab 2000 g) oder Handmessung | Anteil an der Masse am Band |
| **Überfüllung** je Kiste | fertige Palette | `(Brutto − Palette − Kisten × Tara) / Kisten − 8 kg` |

Je Sorte, sobald die eigene Stichprobe trägt (n ≥ 3), sonst aus allen Sorten
zusammen. Welcher Fall gilt, steht an jeder Zahl.

### Die Massenkaskade

Jede Charge zerfällt in zwei Portionen — **ausgelagert** (verarbeitet,
Lagerdauer beobachtet) und **im Lager** (rechts-zensiert, bis zum Stichtag
projiziert). Auf beide läuft dieselbe Rechnung:

```
Eingang ──Verdunstung──▶ M1 ──Schimmel──▶ M2 ──Ausschuss/Nebenkanal──▶ verkaufsfähig
```

Jeder Anteil bezieht sich auf die Masse, die in *seinen* Schritt hineingeht —
nur so addieren sich die Ströme genau zur Portion, ohne Basen zu vermischen.

Jede Zahl entsteht dreimal: mit dem unteren, dem mittleren und dem oberen Wert
des Koeffizienten. Daraus wird der ausgewiesene Bereich.

---

## 3. Wie es beim Betriebsleiter ankommt

### Ebene 1 — Überblick

Eingang, Verlust gesamt, Hauptursache. Darunter die Ursachen als Balken,
absteigend sortiert. Voller Balken = beobachtet, schraffiert = hochgerechnet,
Strich darüber = Unsicherheitsbereich.

Beruht ein Strom auf weniger als drei Messungen, steht **dünne Datenlage**
daneben und darunter ein Kasten: *diese Rangfolge kann sich noch drehen.*

Ganz oben, falls vorhanden: unplausible Messungen mit Diagnose
(*„4500 kg Schimmel auf 5144 kg Ware — das wären 87 %"*). Sie zählen nicht mit,
verschwinden aber nicht.

### Ebene 2 — Aufschlüsselung

Filter nach Sorte, Schlag und Lagerdauer. Dann:

- **Buch A — physischer Verlust:** Verdunstung, Schimmel, Ausschuss zu klein.
- **Buch B — verschenkte Marge:** Nebenkanal, Überfüllung. Kein Verlust, die
  Ware ist verkauft — nur nicht zum besten Preis. Wird nie mit Buch A vermischt.

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

- **Warenausgang** wird nicht erfasst. Die Bilanz vergleicht deshalb Modell
  gegen CSV, nicht Eingang gegen Verkauf.
- **Preise** fehlen. Buch B rechnet in Kilogramm, nicht in Franken.
- **Restbestand am Stichtag** ist eine Projektion, kein Inventar.
- Bei **einer einzigen Messung** gibt es keinen Bereich — dann steht der
  Punktwert dreimal da, und `koeff_n` sagt warum.
