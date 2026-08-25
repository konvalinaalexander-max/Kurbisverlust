# Statistische Überprüfung — Befunde und was daraus wurde

Diese Datei hält fest, was die Überprüfung nach `docs/PROMPT_STATISTIK_REVIEW.md`
ergeben hat: je Verdachtspunkt ein Befund, die Rechnung oder Simulation dahinter,
und was geändert wurde. Sortiert nach Auswirkung auf das Ergebnis, nicht nach
statistischer Eleganz.

## Wie gemessen wurde

`supabase/test/simulation/` erzeugt Saisons, deren wahre Koeffizienten wir
selbst gesetzt haben (Verdunstung 0.06 % je Tag, Verderb λ = 1.07e-5, k = 1.6,
3 % zu klein, 1.5 % zu gross). Die Simulation baut die Welt so, wie sie ist —
Paletten unterscheiden sich in ihrer Anfälligkeit, die Verarbeitungsreihenfolge
kann am Zustand hängen. Das Modell sieht davon nur, was ein Arbeiter erfasst
hätte. Danach steht fest:

* **Verzerrung** — liegt die Schätzung systematisch daneben?
* **Überdeckung** — enthält der ausgewiesene 95-%-Bereich den wahren Wert
  tatsächlich in 95 % der Saisons?

```
./supabase/test/simulation/matrix.sh 25     # alle Lagen, 25 Saisons je Lage
./supabase/test/simulation/lauf.sh 25 0.50 1 12 24   # eine Lage einzeln
```

`matrix.sh` setzt die Datenbank zuerst zurück. Ohne das rechnet die Auswertung
über alles, was sonst noch in der Datenbank liegt, und meldet Verzerrungen von
tausend Prozent, die nichts über das Modell aussagen — beim Schreiben dieser
Datei einmal passiert.

## Die drei Befunde, die wirklich zählten

### 1. Die Schimmelkurve wurde flach fortgeschrieben (Punkt 8, 6)

**Bestätigt, und es war der grösste Fehler im ganzen Modell.**

Für Lagerdauern ohne Messung schrieb `v_schimmel_kurve` den letzten bekannten
Wert fort. Derselbe Datenstand, Wahrheit daneben gestellt:

| Lagertage | Wahrheit | Treppenfunktion | Modell (jetzt) |
|---|---|---|---|
| 30 | 0.25 % | 0.23 % | 0.25 % |
| 90 | 1.42 % | 1.19 % | 1.52 % |
| 150 | 3.19 % | **2.03 %** | 3.48 % |
| 210 | 5.41 % | **2.03 %** | 5.97 % |

Ab 120 Tagen lief die Treppe flach — und genau dort lag die Masse: mitten in
der Saison 341.8 t Lagerbestand mit 167–201 Tagen Alter, jenseits der längsten
je gemessenen Lagerdauer (113 Tage). Die halbe Ernte bekam den Schimmelanteil
kurz gelagerter Ware.

Ersetzt durch ein angepasstes Verderbsmodell `F(t) = 1 − exp(−λ·t^k)`
(Weibull-Form, im Log-Raum eine gewichtete lineare Regression). Spec §9 verlangt
ausdrücklich, rechts-zensierte Ware zu projizieren; flach fortschreiben war
keine Projektion, sondern eine Weigerung.

Zur Frage nach Kaplan-Meier oder Turnbull: Beide brauchen den Zeitpunkt, zu dem
eine *einzelne* Einheit verdirbt. Erfasst wird aber ein Massenanteil je Arbeit,
also intervallzensierte aggregierte Mengen ohne Einzelverläufe. Eine
parametrische Anpassung an genau diese Anteile nutzt die vorhandene Information
vollständig; eine Survival-Schätzung hätte hier keine Datengrundlage.

→ `0017_schimmelmodell.sql`

### 2. Die drei Szenarien waren kein Konfidenzintervall (Punkt 1, 9)

**Bestätigt — und der Nachweis ist so eindeutig, wie er nur sein kann.**

„unten" setzte *alle* Koeffizienten gleichzeitig an die untere Grenze. Für
Ströme weiter unten in der Kaskade stimmte dabei nicht einmal die Richtung:
Weniger Verdunstung und weniger Schimmel heisst *mehr* Masse, die überhaupt bis
zum Sortierband kommt — also mehr Ausschuss. Gemessen:

| Ausschuss zu klein | Bereichsbreite | Überdeckung |
|---|---|---|
| drei Szenarien | **−2.3 %** | 0 % |
| Fehlerfortpflanzung (jetzt) | +5.3 % | 100 % |

Eine *negative* Breite: `kg_unten` lag über `kg_oben`. Die erste Zeile ist am
damaligen Stand gemessen und lässt sich nicht wiederholen — dieser Code ist weg.

Ersetzt durch Fehlerfortpflanzung über die Kaskade. Für jeden Strom wird die
Ableitung nach jedem Koeffizienten mitgeführt:

```
m1 = m0·(1−r)^t        D := ∂m1/∂r = −m0·t·(1−r)^(t−1)
Verdunstung V = m0−m1     ∂V/∂r = −D
Schimmel    S = m1·f      ∂S/∂r = D·f          ∂S/∂f = m1
Ausschuss   K = m2·a      ∂K/∂r = D·(1−f)·a    ∂K/∂f = −m1·a    ∂K/∂a = m2
```

Damit wandert der Fehler von `r` automatisch in Schimmel und Ausschuss weiter
— Punkt 9 ist damit miterledigt, ohne eigene Massnahme. Zusammengesetzt wird
nach der tatsächlichen Korrelation: der Schimmelkoeffizient stammt aus *einem*
Modell für alle Chargen, also werden erst die Ableitungen summiert und dann
einmal mit der 2×2-Kovarianz multipliziert; die Sorten-Koeffizienten gehen mit
ihrem eigenen Anteil quadratisch und mit dem gemeinsamen Gesamtwert linear ein.

Nebeneffekt: `mv_kaskade` hat nur noch ein Drittel der Zeilen. Das Neuberechnen
fiel von 827 ms auf 226 ms.

→ `0019_fehlerfortpflanzung.sql`, `0023_ranking_mit_filter.sql`

### 3. Messungen aus derselben Charge sind keine unabhängigen Messungen (Punkt 3, 2, 10)

**Bestätigt, und um mehr als eine Grössenordnung.**

Der Fehler wurde als `sd/√n` gerechnet, mit n = Zahl der Messungen. Gemessen an
denselben Daten, Chargen als Gruppen:

| | naiv | chargen-robust | Faktor |
|---|---|---|---|
| Standardfehler der Steigung k | 0.0016 | 0.0509 | **31×** |
| Standardfehler der Achse | 0.0202 | 0.0241 | 1.2× |

Die Steigung bestimmt genau das, was jenseits des gemessenen Bereichs passiert.
Bei den Kaliber-Koeffizienten war es genauso krass:

| Sorte | Messungen | Chargen |
|---|---|---|
| Kaori Kuri | 51 | 2 |
| Tiana | 36 | **1** |
| Fictor | 35 | **1** |

Mit n = 51 kam ein Bereich von 0.8 % Breite heraus. Bei Tiana ist es *eine*
Charge — daraus lässt sich die Streuung zwischen Chargen überhaupt nicht
schätzen.

Ersetzt durch einen chargen-robusten Sandwich-Schätzer (gewichtete Residuen je
Charge aufsummieren, die Streuung *dieser Summen* ist der Fehler) und die
t-Verteilung mit C−1 Freiheitsgraden statt 1.96 — bei zwölf Gruppen ist die
Normalverteilung eine Behauptung, keine Näherung (Punkt 2).

Punkt 10 — massegewichteter Mittelwert, ungewichtete Streuung — fällt damit
weg: beides folgt jetzt derselben Gewichtung.

→ `0017`, `0018_koeffizienten_gepoolt.sql`

## Was sonst noch bestätigt wurde

### Punkt 4 — Verdunstung massenungewichtet: bestätigt, Wirkung gering

`avg(rate_pro_tag)` behandelte eine 400-kg-Palette wie eine 900-kg-Palette.
Jetzt massegewichtet. Auf den Testdaten ändert das fast nichts (0.000589 vs.
0.000589) — die Palettenmassen streuen zu wenig. Richtig ist es trotzdem, und
bei ungleichen Gebinden würde es zählen.

Die zweite Hälfte des Punktes — die Rate wird als über die Zeit konstant
angenommen, real ist der Wasserverlust am Anfang höher — ist **nicht behoben**.
Mit einer Handvoll Wägungen je Saison, jede an *einem* Zeitpunkt, lässt sich
kein zeitlicher Verlauf der Verdunstungsrate schätzen. Das steht unter
„ehrliche Grenzen".

### Punkt 5 — harte Schwelle statt Teilbündelung: bestätigt

„eigene Sorte ab n ≥ 3, sonst global" sprang: bei n = 2 galt der globale Wert
voll, bei n = 3 der eigene voll. Ersetzt durch empirisches Bayes mit
B = τ²/(τ² + Fehler²). Viele verlässliche eigene Messungen → der eigene Wert
zählt; wenige oder aus nur einer Charge → der Gesamtwert trägt. Kein Sprung.

Beim Umbau ist mir dabei selbst ein Fehler unterlaufen, den die Simulation
sofort gefunden hat: Sorten *ohne jede* Messung fielen aus der Schätzung heraus
und bekamen den Koeffizienten 0 — also „kein Verlust". In der Simulation hat das
37 % der Verdunstung verschluckt. Jede Sorte des Stammdatensatzes bekommt jetzt
eine Zeile; `pruefung.sql` prüft es.

### Punkt 12 — fehlende Tara verzerrt nach unten: bestätigt, 10 % an einer Charge

`sum()` überspringt NULL. Fehlt die Gebindeart, ist die Tara NULL, also auch
das Nettogewicht — die Palette verschwindet aus der Summe. An einer Charge mit
44 Paletten, bei der 4 keine Gebindeart haben:

| | kg |
|---|---|
| so gerechnet | 34 494 |
| hochgerechnet | 37 943 |
| **Fehlbetrag** | **10.0 %** |

Zehn Prozent auf der Bezugsgrösse verschieben jede Verlustquote um zehn
Prozent — mehr als die meisten Unterschiede, die hier rangiert werden sollen.
Behoben durch Hochrechnung innerhalb der Charge.

→ `0021_fehlende_tara_und_ueberzaehlung.sql`

### Punkt 14 — Doppelzählung: bestätigt als Möglichkeit, jetzt sichtbar

`lager_kg = greatest(eingang − ausgelagert, 0)` kappte still auf 0. Der Betrag,
um den gekappt wurde, wird jetzt als `ueberzaehlung_kg` mitgeführt — er ist die
einzige Spur, die eine Doppelzählung im System hinterlässt. Verhindern lässt
sie sich damit nicht, nur bemerken.

### Punkt 7 — Selektionsverzerrung: bestätigt, und sie ist strukturell

Der Verdacht war richtig, und er ist der einzige Punkt, der sich **nicht
wegrechnen lässt**. Wer schlecht aussieht, kommt zuerst dran. Anfällige
Paletten werden also bei kurzer Lagerdauer gemessen, robuste erst spät — der
gemessene Verlauf wird flacher als der wahre. Alter und Anfälligkeit sind durch
die Verarbeitungsreihenfolge vermengt, und keine Statistik trennt, was die
Daten nicht trennen.

Was hilft, steht unter „die fehlende Messung".

## Was sich nicht entscheiden liess

### Punkt 11 — die Dubletten-Regel: unentscheidbar, aber jetzt prüfbar

Die Regel verwirft 12–28 % aller CSV-Zeilen. Ob sie richtig liegt, lässt sich
aus der Gewichtsverteilung selbst beantworten: Für unabhängige Kürbisse ist die
Wahrscheinlichkeit zweier gleicher Nachbarn Σpᵢ², die Summe der quadrierten
Anteile je Gewichtsstufe. `v_dubletten_pruefung` rechnet beides aus den
tatsächlich eingelesenen Dateien und sagt, welcher Anteil der verworfenen
Zeilen auch bei echten Kürbissen aufgetreten wäre.

**Im Repository liegt keine einzige echte CSV**, und die Testdaten haben sechs
verschiedene Gewichte — daran lässt sich nichts messen. Die Ansicht sagt das
auch so. Die Prüfung an einer handgezählten Palette (Spec §13) steht weiter aus
und bleibt der einzige harte Beleg.

### Punkt 13 — Stratifizierung nach Schlag: unentscheidbar mit simulierten Daten

Jede Charge ist genau eine Kombination aus Schlag und Sorte (42 Chargen, 42
Kombinationen). Der Schlag ist damit in der Charge verschachtelt — und die
chargen-robuste Fehlerrechnung hat die Streuung zwischen Schlägen bereits im
Bereich drin. Eine eigene Schlag-Schätzung würde die *Punktschätzung* ändern,
nicht die Ehrlichkeit des Bereichs.

Ob sie sich lohnt, entscheidet `v_schlag_effekt` an den Daten: dieselbe
Momentenschätzung wie bei der Sorten-Bündelung, angewandt auf Schläge. In der
Simulation hat der Schlag per Konstruktion keinen Effekt, dort misst der Test
nur meinen Generator. Auf echten Daten ist er aussagekräftig.

→ `0022_pruefbare_annahmen.sql`

### Punkt 15 — der Schimmel-Palox über mehrere Arbeiten: bestätigt, nicht behoben

Sammelt der Palox über mehrere Arbeiten und wird einer einzigen zugeordnet,
sitzt der ganze Betrag am falschen Alter. Die chargen-robuste Fehlerrechnung
fängt das teilweise auf, weil solche Ausreisser die Streuung zwischen Chargen
erhöhen und damit den Bereich verbreitern. Sauber lösen lässt es sich nur durch
Erfassung: der Palox müsste beim Leeren gewogen und dem Zeitraum zugeordnet
werden, nicht einer Arbeit. Das ist eine Änderung am Ablauf im Betrieb, keine
am Modell — deshalb hier nur benannt.

## Punkt 16 — was die Massenbilanz beweisen kann, und was nicht

**Sie ist keine Bilanz.** Verglichen wird das Modell gegen die Sortier-CSV, und
nur für den Anteil der Charge, der überhaupt eine CSV hat. Was sie zeigt:

* Ob die Koeffizienten die Masse treffen, die tatsächlich über das Band lief.
  Eine systematische Abweichung heisst: die Kaskade rechnet falsch.

Was sie **nicht** zeigt:

* Ob die Verluste stimmen. Die CSV wiegt, was *ankommt*, nicht was verschwand.
* Ob der Restbestand stimmt. Der ist eine Projektion, kein Inventar — niemand
  hat nachgezählt.
* Irgendetwas über Chargen ohne CSV.

Der Warenausgang wird nicht erfasst. Solange das so ist, bleibt die letzte
Kontrolle — eingelagert minus verkauft minus weggeworfen = 0 — unmöglich.

## Ehrliche Grenzen: welche Zahlen nicht tragen

| Grösse | Status |
|---|---|
| Verdunstung, Ausschuss, Nebenkanal | belastbar, Bereiche halten, was sie versprechen |
| Schimmel bei zufälliger Verarbeitungsreihenfolge | belastbar |
| **Schimmel, wenn nach Aussehen ausgewählt wird** | **systematisch zu niedrig, solange keine Lagerkontrollen erfasst werden** |
| Schimmel vor der dritten gemessenen Charge | Treppenfunktion, jenseits der letzten Messung zu niedrig — das Dashboard sagt es |
| Zeitlicher Verlauf der Verdunstungsrate | nicht schätzbar; angenommen wird eine konstante Tagesrate |
| Restbestand im Lager | Projektion, kein Inventar |
| Massenbilanz | Kontrolle der Koeffizienten, keine Bilanz |
| Anteil der Ware jenseits der längsten gemessenen Lagerdauer | wird als `kg_extrapoliert` ausgewiesen — bei halb vollem Lager waren das 80 % des Schimmelbetrags |
| Dubletten-Regel | unbelegt bis zur Handzählung einer Palette |

## Die fehlende Messung, die am meisten bringt

**Ab und zu eine zufällig gegriffene Palette im Lager aufmachen und notieren,
wie viel davon faul ist.**

Nicht die, die schlecht aussieht — irgendeine. Genau das ist der Punkt: Es ist
die einzige Schimmelmessung, deren Palette nicht danach ausgewählt wurde, wie
sie aussieht.

*Aufwand:* keiner, der über das Bestehende hinausgeht. Paletten werden ohnehin
gelegentlich gewogen. Ist beim Wiegen „Faules sichtbar" angekreuzt, erscheint
ein Feld „Davon faul (kg)". Ein Wert mehr auf einer Maske, die es schon gibt.

*Wirkung*, gemessen im schwierigsten Fall (mitten in der Saison, Schlechtes
zuerst verarbeitet, 25 Saisons je Zeile):

| Lagerkontrollen je Saison | Verzerrung Schimmel | Überdeckung |
|---|---|---|
| 0 | −12.9 % | 8 % |
| 12 | −5.3 % | 72 % |
| **24** | **+3.7 %** | **100 %** |

Zwei Paletten im Monat genügen, um die grösste verbliebene Fehlerquelle
praktisch zu schliessen.

Solange keine erfasst sind, kann die Selektionsverzerrung nicht einmal geprüft
werden — `v_selektionsverdacht` sagt genau das. Sind welche da, vergleicht die
Ansicht beide Quellen und meldet, ob sie dasselbe sagen.

→ `0020_lagerkontrolle.sql`

## Wo das Modell jetzt steht

`./supabase/test/simulation/matrix.sh 25`, Stand dieser Überarbeitung. Ein
Bereich, der 95 % heissen soll, muss in rund 95 % der Saisons treffen.

| Lage | Strom | Verzerrung | Überdeckung |
|---|---|---|---|
| Saisonende, 25 % im Lager | Verdunstung | −1.6 % | 96 % |
| | Schimmel/Fäulnis | −2.7 % | 92 % |
| | Ausschuss zu klein | +0.1 % | 100 % |
| Mitten in der Saison, 50 % im Lager | Verdunstung | −1.6 % | 96 % |
| | Schimmel/Fäulnis | +1.3 % | 100 % |
| | Ausschuss zu klein | 0.0 % | 100 % |
| Saisonende, Schlechtes zuerst | Verdunstung | −2.5 % | 100 % |
| | Schimmel/Fäulnis | +1.5 % | 100 % |
| | Ausschuss zu klein | +0.1 % | 100 % |
| **Mitten in der Saison, Schlechtes zuerst** | Verdunstung | −0.4 % | 96 % |
| | **Schimmel/Fäulnis** | **−12.9 %** | **8 %** |
| | Ausschuss zu klein | +0.3 % | 100 % |
| Dieselbe Lage, 24 Lagerkontrollen | Schimmel/Fäulnis | +3.7 % | 100 % |
| Knappe Stichprobe: 4 Wägungen | Verdunstung | −3.0 % | 96 % |
| | Schimmel/Fäulnis | +0.9 % | 100 % |

Zum Vergleich der Ausgangszustand, mit dem diese Überprüfung begann:

| Lage | Verzerrung Schimmel | Überdeckung |
|---|---|---|
| Saisonende, 25 % im Lager | −6.2 % | 70 % |
| Mitten in der Saison, 50 % im Lager | −46.3 % | 0 % |

Zwei Dinge sind an dieser Tabelle abzulesen. Erstens: Der einzige verbliebene
Ausreisser ist die Selektionsverzerrung, und dagegen hilft keine Rechnung,
sondern die Messung oben. Zweitens: Wo die Überdeckung 100 % statt 95 % ist,
sind die Bereiche eher zu breit als zu eng — bei der Verdunstung deutlich, weil
zwölf Wägungen aus wenigen Chargen nun einmal wenig sind. Das ist die richtige
Seite, um daneben zu liegen: Die Rangfolge der Ursachen bleibt stabil, und
niemand hält eine Zahl für sicherer, als sie ist.

### Bricht die Rangfolge?

Das ist die eigentliche Frage — Spec §9 will Ursachen rangieren, nicht kg-genau
bilanzieren. `lauf.sh` misst es jetzt mit: Nennt die Auswertung dieselbe
Hauptursache wie die Wahrheit, und steht die ganze Reihenfolge richtig?

| Lage | Hauptursache getroffen | Rangfolge ganz richtig |
|---|---|---|
| Mitten in der Saison, Schlechtes zuerst, 12 Wägungen | 100 % | 100 % |
| Dieselbe Lage, nur 4 Wägungen | 100 % | 100 % |
| Dieselbe Lage, nur 2 Wägungen | 100 % | 100 % |
| **Mitten in der Saison, zufällige Reihenfolge** | **100 %** | **76 %** |

Die Hauptursache steht: Verdunstung ist mit rund 48 t so weit vor Schimmel
(19 t) und Ausschuss (18.5 t), dass kein gemessener Fehler daran rüttelt — auch
nicht mit zwei Wägungen für die ganze Saison.

Die letzte Zeile ist der ehrliche Teil. Dort liegen Schimmel und Ausschuss
**3 % auseinander**, und in einem Viertel der Saisons vertauscht die Auswertung
sie. Das ist kein Modellfehler: Zwei Grössen, die sich um 3 % unterscheiden,
lassen sich mit dieser Datengrundlage nicht auseinanderhalten. Wichtig ist, dass
die Auswertung das auch zeigt. Nachgemessen an denselben 25 Saisons:

| | Läufe |
|---|---|
| Rangfolge vertauscht | 6 |
| Bereiche überlappen sich | 25 |
| **vertauscht *und* Bereiche überlappen** | **6 von 6** |

Es gab keinen einzigen Fall, in dem die Auswertung zwei Ströme vertauschte,
ohne dass die Bereiche das angezeigt hätten. Das Dashboard schreibt deshalb
ausdrücklich hin, wenn zwei benachbarte Ströme sich nicht auseinanderhalten
lassen — wer nur auf die Balkenlänge schaut, liest sonst einen Unterschied,
den es nicht gibt.

Aus derselben Zeile folgt auch, wofür sich der Aufwand *nicht* lohnt: Mehr
Palettenwägungen machen die Verdunstung genauer, an der Reihenfolge von Platz 2
und 3 ändern sie nichts. Wer die auseinanderhalten will, braucht
Lagerkontrollen (Schimmel) und mehr Sortier-CSVs (Ausschuss) — nicht mehr
Wägungen.

---

# Zweite Runde: der Ablauf, nicht die Statistik

Die erste Runde hat die Rechnung in Ordnung gebracht. Die zweite hat gefragt,
ob das Gerechnete überhaupt zu dem passt, was auf dem Betrieb passiert. Das
Prozessbild steht in `docs/ABLAUF.md`.

## Der grösste Fehler war kein Rechenfehler

**Weg 1 hat zwei Lagerabschnitte, das Modell kannte nur einen.** Spec §3
beschreibt Lager → Sortieren → **Lager** → Waschen. Zwischen den beiden
Schritten liegen Wochen; die Ware steht in Kaliber-Kisten wieder in derselben
Halle und verdunstet und verdirbt weiter. Im Modell endete die Uhr beim
Sortieren.

Zwei Folgen, beide am laufenden System nachgewiesen:

**Schimmel #2 verschwand spurlos.** Spec §3 nennt die zweite Aussortierung vor
dem Waschbecken ausdrücklich „zeitaufgelöst". Der Arbeiter trug sie ein, die
Datenbank speicherte sie, und das Modell warf sie weg — ein Wasch-Auftrag mit
900 kg Schimmel erzeugte **null** Zeilen in der Auswertung. Grund: Die
Lagerdauer kam aus den gezählten Paletten, und beim Waschen gibt es keine zu
zählen, weil die Original-Paletten sich beim Sortieren auflösen.

**Die Demo-Saison enthielt keinen einzigen Waschgang.** Der ganze zweite
Abschnitt war nie durchgespielt worden — nicht in der Demo, nicht in den Tests,
nicht in der Simulation. Der Simulations-Harness erzeugt ihn jetzt.

Gemessen an einer Simulation, die den zweistufigen Ablauf erzeugt (25 Saisons):

| | vor 0024 | nach 0024–0031 |
|---|---|---|
| Verdunstung | −15.3 %, Überdeckung 64 % | **+1.2 %, 100 %** |
| Schimmel/Fäulnis | −22.9 %, 8 % | **+2.1 %, 96 %** |
| Ausschuss zu klein | +2.3 %, 40 % | **−0.2 %, 100 %** |

Der Weg dorthin ging über zwei falsche Abzweigungen, die beide der Messung
auffielen:

* Den Palox am Waschbecken als Gesamtwert zu lesen statt als Zuwachs:
  −16.4 %. Er enthält nur, was **seit dem Sortieren** dazugekommen ist.
* Ihn über Kilo zu ergänzen: +15.3 %. Der Durchsatz am Waschbecken ist schon
  um Verdunstung, Schimmel und Ausschuss vermindert und taugt nicht als
  Bezugsmasse. Richtig ist die bedingte Überlebensrate:
  `1 − F(t₂) = (1 − F(t₁))·(1 − g)` mit `g = Schimmel₂/(Durchsatz + Schimmel₂)`.

Eine dritte Abzweigung habe ich gebaut und wieder entfernt: Waschgänge den
Sortierläufen nach dem Prinzip „was zuerst sortiert wurde, wird zuerst
gewaschen" zuzuordnen, statt über alle Sortierläufe davor zu mitteln. Es klingt
richtiger und ist es vermutlich auch — aber gemessen hat es dort, wo es helfen
sollte, nichts gebracht und anderswo geschadet (Saisonende: +2.2 % → +7.5 %,
Überdeckung 100 % → 50 %). Eine Verbesserung, die man nicht messen kann, ist
keine.

## Die Selektionsverzerrung lässt sich nicht wegrechnen — nur aufdecken

In der Simulation, mitten in der Saison, „Schlechtes zuerst verarbeitet":

| | mittlere Anfälligkeit |
|---|---|
| verarbeitete Paletten | **1.52** |
| noch im Lager stehende | **0.80** |

Fast Faktor zwei. Das Modell lernt an der einen Hälfte und rechnet damit die
andere hoch: **+13.6 % Verzerrung, Überdeckung 20 %**.

Ich habe versucht, das zu korrigieren, und es hat nicht funktioniert:

| | Verzerrung Schimmel |
|---|---|
| ohne Lagerkontrollen, ohne Korrektur | +13.3 % |
| mit Lagerkontrollen, ohne Korrektur | +14.3 % |
| mit Lagerkontrollen **und** Niveau-Korrektur | −15.2 % |

Der Versatz dreht das Vorzeichen, ohne den Betrag zu verkleinern. Der Grund ist
lehrreich: Die Selektion verbiegt nicht die **Höhe** der Kurve, sondern ihre
**Steigung** — anfällige Paletten werden früh gemessen, robuste spät, und die
angepasste Steigung k fiel von wahren 1.6 auf 1.14. Einen falschen Anstieg
repariert kein Niveau-Versatz. Die Korrektur ist deshalb wieder entfernt worden.

Auch der naheliegende Gedanke, die Lagerkontrollen stärker zu gewichten, trägt
nicht: Die Anpassung gewichtet mit der Masse hinter jeder Messung, und eine
Lagerkontrolle steht für 800 kg gegen 20 t je Verarbeitungsauftrag. Zwei Dutzend
Kontrollen sind damit unter einem Prozent des Gewichts.

**Was stattdessen geschieht:** Der gemessene Unterschied zwischen beiden Quellen
geht in den *Bereich* ein, nicht in den Wert. Bereinigt um sein eigenes
Rauschen, damit er nur feuert, wenn er belegt ist.

| Lage | Verzerrung | Bereichsbreite | Überdeckung |
|---|---|---|---|
| mit Selektion, 24 Kontrollen | +13.7 % | 98 % | **100 %** |
| ohne Selektion, 24 Kontrollen | +3.9 % | 23 % | 90 % |

Damit ist die Rolle der Lagerkontrollen eine andere, als ich in der ersten Runde
geschrieben habe: **Sie reparieren die Zahl nicht — sie decken auf, dass man ihr
nicht trauen darf.** Ohne sie steht dieselbe falsche Zahl da, nur mit einem
engen Bereich und ohne Warnung. Das ist der schlechtere Zustand.

## Was jetzt zusätzlich erfasst wird

**Der Palox-Stand statt der Differenz.** Der Palox steht auf einer Waage und
läuft über mehrere Arbeiten. Der Arbeiter sollte bisher selbst abziehen, was
letztes Mal draufstand — Kopfrechnen an der Maschine, und ein Fehler ist
hinterher nicht mehr erkennbar. Jetzt trägt er den Stand ein, die Software zieht
ab und zeigt ihm das Ergebnis. Beide Zahlen bleiben erhalten: der Stand als
Beleg, die Differenz als Messwert. Fällt der Stand, war der Palox zwischendurch
leer — das erkennt die Software und sagt es, statt eine negative Menge zu buchen.

**Der Warenausgang.** Spec §9 sieht die Gegenprobe „Eingang = Verlust + Ausgang
+ Restbestand" vor; gebaut war sie nie. Ohne sie ist der Restbestand eine
Hochrechnung, die niemand nachgezählt hat. Es genügt, was auf dem Lieferschein
steht: Datum, Sorte, und entweder Kilo oder Kistenzahl — Palettengewichte kennt
der Betrieb gar nicht und braucht es auch nicht. Kisten werden über das
gemessene Kilo je Kiste umgerechnet, mit ausgewiesener Unsicherheit je Zeile.

Jede Lieferung hat ein **Ziel**, und das Ziel entscheidet über das Buch: Kompost
ist echter Verlust, Tierfutter ein anderer Kanal, Hofladen ist Verkauf. Ohne
diese Unterscheidung verschwindet Masse aus der Bilanz — und fehlende Masse
sieht in einer Bilanz immer aus wie Verlust.

## Fehlende Tara und Doppelzählung, nachgemessen

Nicht neu gefunden, aber jetzt beziffert: An einer Charge mit 44 Paletten, bei
der 4 keine Gebindeart haben, war die Eingangsmasse **10 % zu klein** — und
damit jede Verlustquote 10 % zu gross. Wird jetzt innerhalb der Charge
hochgerechnet, mit `eingang_netto_gemessen_kg` als Beleg daneben.

## Wo das Modell nach der zweiten Runde steht

`./supabase/test/simulation/matrix.sh 20`, in der zweistufigen Welt (Weg 1 mit
beiden Lagerabschnitten). Ein Bereich, der 95 % heissen soll, muss in rund 95 %
der Saisons treffen.

| Lage | Strom | Verzerrung | Bereich | Überdeckung |
|---|---|---|---|---|
| Saisonende, 25 % im Lager | Schimmel | +2.2 % | 17 % | 100 % |
| | Verdunstung | −0.8 % | 51 % | 95 % |
| | Ausschuss | 0.0 % | 7 % | 100 % |
| Mitten in der Saison, 50 % im Lager | Schimmel | +1.9 % | 24 % | 95 % |
| | Verdunstung | −1.3 % | 39 % | 95 % |
| Saisonende, Schlechtes zuerst | Schimmel | +4.0 % | 18 % | 100 % |
| **Mitten in der Saison, Schlechtes zuerst** | **Schimmel** | **+11.0 %** | 22 % | **35 %** |
| dieselbe Lage, 12 Lagerkontrollen | Schimmel | +11.2 % | 83 % | **100 %** |
| dieselbe Lage, 24 Lagerkontrollen | Schimmel | +11.7 % | 104 % | **100 %** |
| Knappe Stichprobe: 4 Wägungen | Verdunstung | +4.4 % | 82 % | 80 % |
| | Schimmel | +1.4 % | 32 % | 95 % |

Die vierte Zeile ist der ehrliche Rest: Wird stark nach Aussehen ausgewählt und
liegt gleichzeitig die halbe Ernte noch im Lager, ist der Schimmel um rund 11 %
zu hoch — und ohne Lagerkontrollen weiss niemand davon. Die beiden Zeilen
darunter zeigen, was die Kontrollen leisten: Die Zahl bleibt dieselbe, aber der
Bereich sagt endlich, dass sie unsicher ist.

Die letzte Zeile ist die andere Grenze: Mit vier Palettenwägungen für eine ganze
Saison wird der Verdunstungsbereich 82 % breit, und selbst dann trifft er nur in
80 % der Fälle. Verdunstung ist der grösste Posten — ein Dutzend Wägungen über
verschiedene Chargen sind das Minimum, unter dem die Zahl nichts mehr taugt.

## Ehrliche Grenzen, Stand jetzt

| Grösse | Status |
|---|---|
| Verdunstung, Ausschuss, Nebenkanal | belastbar, Bereiche halten |
| Schimmel bei zufälliger Verarbeitungsreihenfolge | belastbar |
| **Schimmel, wenn nach Aussehen ausgewählt wird** | **rund 10 % zu hoch; mit Lagerkontrollen sagt es der Bereich, ohne sie merkt es niemand** |
| Verdunstung mit weniger als ~10 Wägungen | Bereich über 80 % breit, Überdeckung fällt unter 90 % |
| Zeitlicher Verlauf der Verdunstungsrate | nicht schätzbar; angenommen wird eine konstante Tagesrate |
| Restbestand im Lager | Projektion; mit erfasstem Warenausgang wird die Lücke prüfbar |
| Massenbilanz gegen die CSV | prüft die Koeffizienten am Tag des Sortierens, nicht die Verluste |
| Zuordnung Waschgang → Sortierlauf | über die Charge und die Reihenfolge geschlossen, nicht erfasst |
| Dubletten-Regel | unbelegt bis zur Handzählung einer Palette |
