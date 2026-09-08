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
| Neue Arbeit | Vorarbeiter, Assistent (eine Frage je Bildschirm) | Tätigkeit, Charge (eingetippt), Bänder der Maschine bzw. Kaliber am Becken (AB-16, AB-19), **Kistensystem** (Kiste ab x kg mit Soll · x Stück je Kaliber · anderes, AB-25). Kein Käufer mehr (0060) |
| Palox ablesen | Vorarbeiter, direkt nach dem Start und im Abschluss-Assistenten (AB-02); beim Waschen freiwillig (AB-28) | Stand der Palox-Waage (brutto); die Menge leitet die Datenbank ab, mit Behälter-Tara aus den Einstellungen; ein gefallener Stand heisst geleert — die Menge ist dann unbekannt, kein Häkchen; im Abschluss auch „Stand unverändert" (= 0 kg dazu) |
| Palette zählen | Zähler: Sortieren, Waschen + Sortieren | „+ 1 Palette" mit Datum vom Zettel (**Pflicht**, bleibt für die nächste Palette stehen, der Knopf zeigt es) und beim Waschen + Sortieren dem **Gewicht vom Zettel** (Pflicht, je Palette neu, AB-26), „Rückgängig" |
| Kisten zählen | Zähler: Sortieren (gefüllte, je Kaliber), Waschen (geleerte, Kaliber der Arbeit, je Kiste mit **Sortierdatum** — „kein Datum" ist eine Antwort, AB-27) | Anzahl |
| Paletten gesamt | Zähler und Vorarbeiter: Fax | Die Palettenzahl der ganzen Arbeit („+ 1"), im Abschluss dazu freiwillig die Tage seit dem Waschen (AB-24) |
| Palette wiegen | Zähler, Waschen + Sortieren (eigener Knopf) | Eingangsdatum, Eingangsgewicht, Gewicht jetzt, Kisten, Kistenart, optional Kürbisse je Kiste, Faules sichtbar |
| Palette kontrollieren | ohne Arbeit, vom Startbildschirm | Die App schlägt drei Chargen vor (AB-29); Eingangsdatum und Eingangsgewicht vom Zettel, Gewicht jetzt, Kisten, Kistenart, Pflichtfeld „davon faul" (0 ist eine Antwort) und wie die Palette gegriffen wurde (AB-09); mehrere Paletten nacheinander |
| Fertige Palette | Vorarbeiter, Waschen, Waschen + Sortieren, wo das Kistensystem rechenbar ist | Gewicht, Kisten, Kistenart, bei Stück-Kisten das Kaliber und Kürbisse je Kiste. Kiste ab x kg → Überfüllung gegen das Soll der Arbeit; Stück-Kisten → Erwartung aus der CSV, Information (AB-25) |
| Faules wiegen | Vorarbeiter, Fax | Brutto, Kisten, Kistenart, mit/ohne Palette — der Fax-Strom |
| Abschluss | Vorarbeiter, Assistent (AB-04) | Palox jetzt ablesen (Fax: Faules, Paletten gesamt, Tage seit dem Waschen) · beim Waschen: sind Kisten gezählt? · Fertige Palette gewogen? · „War alles aus einer Charge?", bei Nein „wenigstens dieselbe Sorte?" · Zusammenfassung mit „Fehlt noch". Zu klein / zu gross wird nicht mehr gewogen — der Anteil kommt aus der Sortier-CSV (AB-26) |

Dazu automatisch: wer, wann, welche Charge, welche Station, welche Fassung des
Sortierschemas — Start- und Endzeit vom Server, nicht vom Handy. Die
Antworten aus dem Abschluss sind Messwerte (`auftrag_angabe`): „nicht alles
aus einer Charge" nimmt die Messung aus dem Zeitmodell, nicht aus der Bilanz.

Die Masse einer Arbeit hat vier Quellen, in dieser Reihenfolge: **gewogene
Paletten** und **Gewichte vom Zettel** (Waschen + Sortieren: das Netto folgt
der Palette im Wareneingang oder der mittleren Tara der Charge), **Paletten
aus dem Wareneingang** (Sortieren: gezählte Paletten mit ihrem Zetteldatum),
**gezählte Kisten mal gemessenem Kistengewicht** (Waschen) und beim Fax
**Paletten mal gemessene Palettenmasse**. Was eine Kaliber-Kiste wiegt, wird
nicht geschätzt, sondern am Sortieren gemessen: dort steht die Masse je
Kaliber in der CSV und die gefüllten Kisten werden gezählt. Ohne diese
Messung bleibt die Menge am Waschbecken unbekannt — nicht null. Und keine
dieser Massen ist eine Menge der Charge: sie ist der Nenner der Arbeit
(AB-23).

### Vom Betriebsleiter

| Erfassung | Ergebnis |
|---|---|
| Sortier-CSV hochladen | Einzelgewicht jedes Kürbisses, gereinigt und nach der Fassung des Auftrags klassiert |
| Sortierschemata | je Sorte, datiert — nie überschrieben, nur neue Fassungen (der Arbeiter passt die Bänder beim Start an, AB-16) |
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

Jede Charge zerfällt je Eingangstag in zwei Portionen — **ausgelagert** (die
Eingangsmasse hinter den verkauften Lieferungen: geliefert ÷ verkaufsfähiger
Anteil beim Alter am Liefertag, nach Eingangsanteil auf die Eingangstage
verteilt) und **im Lager** (Eingang minus Ausgelagert, bis zum Stichtag
projiziert). Kein Zählen bestimmt eine Menge — die Halle wird punktuell
erfasst (AB-23). Auf beide Portionen läuft dieselbe Rechnung:

```
Eingang ──Verdunstung──▶ M1 ──Sockel──▶ ──Schimmel──▶ M2 ──zu klein / zu gross──▶ ──Fax──▶ verkaufsfähig
```

Steckt hinter den Lieferungen einer Charge mehr Eingangsmasse, als je
eingelagert wurde, ist das eine **Überzählung** — fast immer ein fehlender
Wareneingang oder eine falsch zugeordnete Lieferung — und steht als Befund
in der Bilanz.

Jeder Anteil bezieht sich auf die Masse, die in *seinen* Schritt hineingeht —
nur so addieren sich die Ströme genau zur Portion, ohne Basen zu vermischen.

Der Bereich entsteht aus Fehlerfortpflanzung: für jeden Strom die
Empfindlichkeit gegenüber jedem Koeffizienten, zusammengesetzt nach der
tatsächlichen Korrelation. Das Alter der noch liegenden Ware kommt je
Eingangstag aus dem Eingangsanteil des Tags — nicht aus dem Mittel der ganzen
Charge, und nicht aus gezählten Paletten.

---

## 3. Wie es beim Betriebsleiter ankommt

Fünf Reiter, je mit einem Satz darüber, was er beantwortet.

### Überblick — wie viel, woran, was tun?

Eingang und Ausgeliefert (gemessen), Verlust und Noch im Haus (gerechnet,
davon verkaufsfähig). „Woran fehlt die Ware?" — Palox, Verdunstung, zu
klein, zu gross und die Überfüllung, gesamt oder je Sorte, Schlag, Charge
(gestapelte Balken, Klick öffnet die Gruppe). „Was ist noch im Haus?" je
Gruppe mit „liegt seit". Kaliber je Sorte. Die Saison im Verlauf (Eingang und
Ausgang kumuliert, dazwischen der Abstand). Ein Strom ohne einzige Messung
steht als „nicht gemessen" da, nicht als 0.

### Ursachen — warum, und wie sicher?

Filter nach Sorte, Schlag und Charge. Dann, ohne „Buch A/B" (AB-30):

- **Echter Verlust — Palox:** Verderb im Lager (die Kurve mit ihren Punkten
  nach Herkunft, je Charge gemessen gegen Modell, das Faule je Charge) und
  Palox beim Abpacken (Fax: Rate je Sorte und Charge, Tage seit dem Waschen).
- **Echter Verlust — Verdunstung:** jede gewogene Palette als Punkt über der
  Lagerdauer, die Rate je Sorte, mit aufklappbarem **Rechenweg** (Formel,
  Bezugsmasse, Koeffizient samt Herkunft, Ergebnis, Bereich, beobachtet gegen
  projiziert).
- **Kein echter Verlust — Sortierung:** zu klein, zu gross,
  Kaliber-Verteilung und die Gewichtsverteilung aus der Sortier-CSV mit den
  Kalibergrenzen, nach Sorte, Schlag oder Charge, in 25/50/100 g.
- **Kein echter Verlust — Überfüllung:** aus den gewogenen fertigen Paletten
  gegen das Soll der Arbeit, auf die verkaufte Masse hochgerechnet; bei
  Stück-Kisten die Abweichung von der Erwartung aus der CSV (Information).

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

- **Warenausgang** kommt aus dem Perigon-Excel (0055); von Hand bleibt
  möglich. Ohne Lieferungen liegt rechnerisch noch alles im Haus — die Bilanz
  sagt es. Mit Lieferungen ist der Bestand Eingang minus Ausgelagert, und
  Überzählung heisst: hier fehlt Wareneingang.
- **Preise** fehlen. Die verschenkte Marge rechnet in Kilogramm, nicht in
  Franken.
- **Restbestand am Stichtag** ist Eingang minus Ausgelagert, projiziert bis
  zum Stichtag — kein Inventar, und kein Zählen in der Halle.
- Bei **einer einzigen Charge** gibt es keinen Bereich — dann steht der
  Punktwert allein da, und `koeff_n` sagt warum.
- **Die verarbeitete Menge am Waschbecken (Weg 1)** ist die einzige Zahl, die
  ein Arbeiter schätzen statt ablesen muss. Fehlt sie, meldet die Auswertung
  die Schimmelmessung als „ohne Nenner".
