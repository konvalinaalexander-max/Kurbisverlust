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

Zwei Rollen, keine Konten (`UI-KONZEPT.md`): Wer eine Arbeit eröffnet, ist ihr
**Vorarbeiter** und sieht die Checkliste; wer beitritt, ist **Zähler** und sieht
einen Zähler.

| Erfassung | Wer, wo | Felder |
|---|---|---|
| Neue Arbeit | Vorarbeiter, Assistent (eine Frage je Bildschirm) | Tätigkeit, Charge (eingetippt), Käufer (bestimmt das Sortierschema; neue Käufer legt er selbst an), Sortierart (Kiste ab x kg / Kaliber, AB-01); beim Waschen: welches Kaliber gewaschen wird |
| Palox ablesen | Vorarbeiter, direkt nach dem Start und im Abschluss-Assistenten (AB-02) | Stand der Palox-Waage (brutto); die Menge leitet die Datenbank ab, mit Behälter-Tara aus den Einstellungen; Häkchen „Palox wurde geleert"; im Abschluss auch „Stand unverändert" (= 0 kg dazu) |
| Ausschuss-Paletten leer? | Vorarbeiter, Checkliste (AB-05) | Ja / Nein — eine vergessene Antwort holt der Abschluss nach |
| Palette zählen | Zähler: Sortieren, Waschen + Sortieren | „+ 1 Palette" mit Datum vom Zettel (**Pflicht**, bleibt für die nächste Palette stehen), „Rückgängig" |
| Kisten zählen | Zähler: Sortieren (gefüllte, je Kaliber), Waschen (geleerte, Kaliber der Arbeit) | Anzahl |
| Palette wiegen | Zähler, Waschen + Sortieren (eigener Knopf) | Eingangsdatum, Eingangsgewicht, Gewicht jetzt, Kisten, Kistenart, optional Kürbisse je Kiste, Faules sichtbar |
| Palette kontrollieren | ohne Arbeit, vom Startbildschirm | wie Wiegen, dazu Pflichtfeld „davon faul" (0 ist eine Antwort) und wie die Palette gegriffen wurde (AB-09) |
| Zu klein / zu gross | Vorarbeiter, Waschen + Sortieren (AB-03) | gewogen: Brutto, Kisten, Kistenart (Netto rechnet die Datenbank); geschätzt nur als Notweg, sichtbar als solcher |
| Fertige Palette | Vorarbeiter, Waschen, Waschen + Sortieren | Gewicht, Kisten, Kistenart, optional Kürbisse je Kiste |
| Abschluss | Vorarbeiter, Assistent (AB-04) | Palox jetzt ablesen · Ausschuss: alles von dieser Arbeit? · „War alles aus einer Charge?", bei Nein „wenigstens dieselbe Sorte?" · beim Waschen: Sortierdatum von der Kiste, verarbeitete Menge nur, wenn keine Kisten gezählt wurden · Zusammenfassung mit „Fehlt noch" |

Dazu automatisch: wer, wann, welche Charge, welche Station, welche Fassung des
Sortierschemas — Start- und Endzeit vom Server, nicht vom Handy. Die
Antworten aus dem Abschluss sind Messwerte (`auftrag_angabe`): „nicht alles
aus einer Charge" nimmt die Messung aus dem Zeitmodell, nicht aus der Bilanz.

Die Masse einer Arbeit hat drei Quellen, in dieser Reihenfolge: **gewogene
Paletten**, **eingetippter Durchsatz**, **gezählte Kisten mal gemessenem
Kistengewicht**. Was eine Kaliber-Kiste wiegt, wird nicht geschätzt, sondern am
Sortieren gemessen: dort steht die Masse je Kaliber in der CSV und die
gefüllten Kisten werden gezählt. Ohne diese Messung bleibt die Menge am
Waschbecken unbekannt — nicht null.

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

Fünf Reiter, je mit einem Satz darüber, was er beantwortet.

### Überblick — wie viel, woran, was tun?

Eingang, Lagerverlust (mit Anteil), Hauptursache, noch im Haus, ausgeliefert.
Darunter die Massenkaskade, „Was jetzt zu tun ist" (Absprachen, die der
Auswertung fehlen — etwa Arbeiten ohne Palox-Ablesung), „Was kostet Warten?"
(welche Charge zuerst), die ersten Auffälligkeiten, die Saison im Verlauf
(Eingang und Ausgang kumuliert), die Bilanz und die Ursachen als Balken.
Ein Strom ohne einzige Messung steht als „nicht gemessen" da, nicht als 0.

### Ursachen — warum, und wie sicher?

Filter nach Sorte, Schlag und Lagerdauer. Dann:

- **Buch A — Lagerverlust:** Verdunstung, Schimmel, je mit Balken, Bereich und
  aufklappbarem **Rechenweg** (Formel, Bezugsmasse, Koeffizient samt Herkunft,
  Ergebnis, Bereich, beobachtet gegen projiziert).
- **Verderb mit der Lagerdauer:** die Messpunkte nach Herkunft (Palox,
  Lagerkontrolle) und die verwendete Kurve mit Bereich.
- **Nicht lagerbedingt:** der Sockel vom Feld — oder warum er nicht belegt ist.
- **Verdunstung:** jede gewogene Palette als Rate je Tag; Sorten im Vergleich.
- **Buch B — anderer Kanal, verschenkte Marge:** zu klein, zu gross,
  Überfüllung — und die Überfüllung je Käufer und Sorte.
- **Kaliber-Verteilung** und die **Gewichtsverteilung** aus der Sortier-CSV
  mit den Kalibergrenzen, nach Sorte, Schlag oder Charge, in 25/50/100 g.

### Chargen — wo steht welche?

Eine Zeile je Charge: Eingang, im Lager (liegt seit), wartet aufs Waschen,
verarbeitet, Verlust in 14 Tagen, Messungen, Modell gegen CSV. Aufgeklappt:
die Arbeiten (mit Alter der verarbeiteten Ware) und Lieferungen der Charge.

### Messungen — was weiss die Auswertung nicht?

| Ansicht | Beantwortet |
|---|---|
| **Wie vollständig wird erfasst?** | Je Absprache (AB-…) ein Balken: datierte Paletten, Palox-Ablesungen, Abschlussfragen, gewogener Ausschuss, zugeordnete CSVs, gezählte Kisten, Lagerkontrollen |
| **Auffälligkeiten** | Messungen, die nicht in die Rechnung eingehen, mit Rat und Sprung zur Arbeit |
| **Wo fehlen Messungen** | Grösste Chargen ohne Stichprobe — dort bringt Messen am meisten |
| **Wird das Älteste zuerst verarbeitet?** | Alter der verarbeiteten Paletten gegen die Charge, je Arbeit |
| **Durchsatz je Arbeit** | Dauer, Masse, Kilo je Stunde, je Station |
| **Die vier Koeffizienten**, **Kistengewicht je Kaliber** | Worauf beruht die Rechnung? Wert, Anzahl Messungen, Herkunft |
| **Das Verderbsmodell** | k, gemessener Bereich, Sockel mit Nachweis, Selektionsverdacht, Herkunft der Punkte |
| **Massenbilanz je Charge** | Trifft das Modell die Wirklichkeit? Modell am Band gegen gewogene CSV, mit CSV-Export |
| **Gewogene Paletten** | Netto damals/jetzt, Verlust, kg je Kiste, kg je Kürbis |

### Betrieb — was läuft, und die Grundlagen

Arbeiten (alle, mit Durchsatz), Warenausgang, Sortier-CSV, Warteschlange,
Stammdaten, Zugang.

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
