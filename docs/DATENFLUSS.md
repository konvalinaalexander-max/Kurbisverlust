# Was hinein geht, was herauskommt

Eine Landkarte des ganzen Systems: welche Zahl erfasst wird, was daraus
gerechnet wird, und wo sie beim Betriebsleiter wieder auftaucht.

Zum Ausprobieren: der Knopf „Demo-Daten" unter Stammdaten (oder auf der
leeren Auswertung) legt eine erfundene, aber stimmige Saison an (323 t
Eingang, 844 Paletten in 36 Chargen, 309 Arbeiten, 187 Lieferungen) und
räumt sie restlos wieder weg.

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
| Eingangspalette zählen | Zähler: Sortieren, Waschen + Sortieren | „+ 1 Palette" mit Datum vom Zettel (**Pflicht**, bleibt für die nächste Palette stehen, der Knopf zeigt es) und beim Waschen + Sortieren dem **Gewicht vom Zettel** (Pflicht, je Palette neu, AB-26), „Rückgängig" |
| Kaliber-Palette zählen | Zähler: Waschen | „+ 1 Palette" mit **Sortierdatum vom Zettel** („kein Datum" ist eine Antwort) und den **Kisten darauf** (vorbelegt, änderbar) — die Menge der Wasch-Arbeit (AB-33) |
| Kisten zählen | Zähler: Sortieren (die gefüllten, je Kaliberband) | Anzahl |
| Zu klein / zu gross wiegen | Vorarbeiter: Waschen + Sortieren, am Ende | Je Palette: Art, Brutto, Kisten, Kistenart; das Netto rechnet die Datenbank. „Nichts zu klein oder zu gross" ist eine Messung mit 0 kg (AB-34) |
| Paletten gesamt | Zähler und Vorarbeiter: Fax | Die Palettenzahl der ganzen Arbeit („+ 1"), im Abschluss dazu freiwillig die Tage seit dem Waschen (AB-24) |
| Palette wiegen | Zähler, Waschen + Sortieren (eigener Knopf) | Eingangsdatum, Eingangsgewicht, Gewicht jetzt, Kisten, Kistenart, optional Kürbisse je Kiste. **Mindestens drei** vor der Waschmaschine — erinnert, nicht erzwungen (AB-34) |
| Palette kontrollieren | ohne Arbeit, vom Startbildschirm | Die App schlägt die drei Chargen vor, bei denen eine Wägung am meisten bringt (Bestand heute × Tage seit der letzten Wägung, AB-36); Eingangsdatum und Eingangsgewicht vom Zettel, Gewicht jetzt, Kisten, Kistenart. Nicht mehr gefragt: „davon faul" und „wie gegriffen" — die Palette wird gewogen, nicht ausgepackt; mehrere Paletten nacheinander |
| Fertige Paletten | Vorarbeiter, Waschen, Waschen + Sortieren, wo das Kistensystem rechenbar ist | Gewicht, Kisten, Kistenart, bei Stück-Kisten das Kaliber und Kürbisse je Kiste. **Drei** — beim Waschen verlangt, beim Waschen + Sortieren erinnert (AB-35). Kiste ab x kg → Überfüllung gegen das Soll der Arbeit; Stück-Kisten → Erwartung aus der CSV, Information (AB-25) |
| Faules wiegen | Vorarbeiter, Fax | Brutto, Kisten, Kistenart, mit/ohne Palette — der Fax-Strom |
| Abschluss | Vorarbeiter, Assistent (AB-04) | Palox jetzt ablesen (Fax: Faules, Paletten gesamt, Tage seit dem Waschen) · Waschen + Sortieren: die Wiege-Erinnerung, dann zu klein / zu gross je Palette · beim Waschen: sind Paletten gezählt? · Fertige Paletten gewogen (drei)? · „War alles aus einer Charge?", bei Nein „wenigstens dieselbe Sorte?" · Zusammenfassung mit „Fehlt noch" und den Erinnerungen. Am Band kommt der Ausschuss weiter aus der Sortier-CSV (AB-26, AB-34) |

Dazu automatisch: wer, wann, welche Charge, welche Station, welche Fassung des
Sortierschemas — Start- und Endzeit vom Server, nicht vom Handy. Die
Antworten aus dem Abschluss sind Messwerte (`auftrag_angabe`): „nicht alles
aus einer Charge" nimmt die Messung aus dem Zeitmodell, nicht aus der Bilanz.

Die Masse einer Arbeit hat vier Quellen, in dieser Reihenfolge: **gewogene
Paletten** und **Gewichte vom Zettel** (Waschen + Sortieren: das Netto folgt
der Palette im Wareneingang oder der mittleren Tara der Charge), **Paletten
aus dem Wareneingang** (Sortieren: gezählte Paletten mit ihrem Zetteldatum),
**gezählte Paletten mal Kisten mal gemessenem Kistengewicht** (Waschen) und beim Fax
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
| Warenausgang | Lieferschein: Datum, Sorte, Kilo oder Kisten, Ziel — dazu die **verkauften Kisten** je Zeile, aus denen die verschenkte Marge folgt (AB-37) |
| Saisonende | wie weit die Prognose hinter der Heute-Marke reicht; die Kennzahlen selbst gelten bis heute (AB-31) |
| Messungen korrigieren | von einer Auffälligkeit aus: jede Messung einer Arbeit ändern oder löschen; geändert wird die Beobachtung, nicht das Abgeleitete (AB-38) |

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

Alle vier Zahlen gelten **bis heute** (AB-31): Eingang und Ausgeliefert
(gemessen), Verlust bis heute und Noch im Haus (gerechnet, davon
verkaufsfähig — vorsichtig gerechnet). Der Verlauf zeigt drei Linien (Eingang,
Ausgang, Verlust) mit der Heute-Marke in der Mitte; ab dort läuft die
Prognose gestrichelt weiter und geht in keine Kennzahl ein. „Woran fehlt die
Ware?" — je Gruppe ein **100-%-Balken**, dessen Teile beim Überfahren Anteil
und Tonnen nennen. „Was ist noch im Haus?" steht ausklappbar je Gruppe, mit
„liegt seit". Die Kaliberverteilung als Glocke, daneben eine Kurztabelle
(Kaliber, Anteil, Kilo). Ein Strom ohne einzige Messung steht als „nicht
gemessen" da, nicht als 0.

### Ursachen — warum, und wie sicher?

Ein leiser Filter oben (Sorte, Charge). Jeder Block nennt **zuerst die Zahl**,
dann die Kurve dahinter — ohne „Buch A/B" (AB-30):

- **Echter Verlust — Palox:** „vermuteter Verderb aktuell noch im Lager:
  X kg (x %)", darunter die Kurve mit den Messpunkten und die Chargen.
- **Echter Verlust — Verdunstung:** die vermutete Verdunstung des heutigen
  Lagers, darunter die Kurve mit Erwartungsband und jede gewogene Palette als
  Punkt, dazu der aufklappbare **Rechenweg** (Formel, Bezugsmasse,
  Koeffizient samt Herkunft, Ergebnis, Bereich).
- **Kein echter Verlust — Sortierung:** die Zahlen zuerst, der
  Sortendurchschnitt gross; beim Sortenfilter die Chargen-Tabelle; die
  Gewichtsverteilung als Glocke, ausklappbar.
- **Kein echter Verlust — Fax:** eine Zahl.
- **Überfüllung** als eigener Block, getrennt nach Kistensystem: „Kiste ab
  x kg" nennt Soll, gemessenes Gewicht je Kiste, den Überschuss, die
  **verkauften Kisten aus den Verkaufsdateien** und daraus das Verschenkte —
  nur, wo beides gemessen ist. „x Stück je Kaliber" nennt Durchschnittsgewicht
  und verkaufte Stück, aber keine Marge (AB-37). Kein Käufer, nirgends.

### Chargen — wo steht welche?

Eine Zeile je Charge: Eingang, ausgeliefert, im Haus (davon verkaufsfähig),
„liegt seit" als Spanne, Verlust bis heute, die nächsten 14 Tage als einzige
Prognose der Seite, Messungen. Aufgeklappt in dieser Reihenfolge: **Eingang**
(die Eingangstage), **Ausgang** (die Lieferungen), **Arbeiten**.
Fehlermeldungen stehen nicht hier, sondern unter Messungen — dort lassen sie
sich beheben (AB-38).

### Messungen — was weiss die Auswertung nicht?

| Ansicht | Beantwortet |
|---|---|
| **Wie vollständig wird erfasst?** | Je Absprache (AB-…) ein Balken: datierte Paletten, Palox-Ablesungen, Abschlussfragen, gewogener Ausschuss, zugeordnete CSVs, gezählte Kisten, Lagerkontrollen |
| **Auffälligkeiten** | Messungen, die nicht in die Rechnung eingehen, mit Rat und „korrigieren": öffnet die Messungen der Arbeit zum Ändern oder Löschen (AB-38) |
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

### Die zweite Gegenprobe: geht die Bilanz auf?

Eingang + Überzählung = verkauft + Verlust bis heute + anderer Kanal
+ noch im Haus. Sie geht von selbst auf, weil das Ausgelagerte aus den
Lieferungen zurückgerechnet ist — was übrig bleibt, ist Rundung. Genau darum
ist sie ein Test: Solange in der Kaskade ein Kilo doppelt oder zu früh zählte,
blieb ein Rest stehen. In Runde I waren das −4 274 kg; nach 0062 sind es
−0.05 kg, und ein Test in `pruefung.sql` hält es dort.

Was *nicht* aufgeht, heisst **Überzählung**: hinter den Lieferungen steckt mehr
Eingangsware, als je eingelagert wurde. Das ist ein Datenfehler — meist fehlt
Wareneingang —, kein Verlust, und steht darum als eigene Zeile.

### Die dritte Gegenprobe: sagt jede Zahl, was sie ist?

`pruefstand/beschriftung.mjs` rendert die zwölf Ansichten des Betriebsleiters
und liest jede Zahl so, wie ein Mensch sie liest — mit der Beschriftung
daneben. Jede Masse braucht einen Namen, jeder Name einen Eintrag im
Begriffslexikon mit Bedeutung und Herkunftsspalte, jede gerechnete Grösse ihre
Herkunftsmarke, jede Prozentzahl ihre Bezugsgrösse. Dazu die Gegenprobe der
vier Kopfzahlen gegen `erg_bilanz`: eine richtige Beschriftung an einer
falschen Zahl wäre schlimmer als gar keine.

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
