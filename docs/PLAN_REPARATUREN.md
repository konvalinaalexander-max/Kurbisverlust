# Was repariert wird, in welcher Reihenfolge — Runde L

Der Prüfbericht (`docs/PRUEFBERICHT.md`) sagt, was gefunden wurde. Diese Datei
sagt, was davon gemacht wird, in welcher Reihenfolge und woran man erkennt, dass
es gemacht ist. Sie ist von Hand geschrieben; der Bericht entsteht bei jedem
Lauf neu.

## Die Regel, an der jede Zeile gemessen wird

**Die App wird nicht komplizierter.** Kein neuer Bildschirm, keine neue Maske,
keine neue Frage an den Arbeiter, kein neuer Knopf für den Betriebsleiter. Was
hier steht, ist Reparatur: eine Zahl, die etwas anderes behauptet, als sie ist,
sagt hinterher, was sie ist. In fünf von zehn Fällen heisst das sogar *weniger*
Anzeige — eine Null verschwindet und ein „—" tritt an ihre Stelle.

Drei Sorten Arbeit, sauber getrennt:

**Reparatur** — etwas ist nachweislich falsch, und es gibt genau eine richtige
Antwort. Wird gemacht.

**Frage an den Betrieb** — zwei Antworten sind vertretbar, und die Wahl gehört
nicht dem Programmierer. Wird vorgelegt, nicht entschieden.

**Entscheidung des Betriebs** — es geht um den Ablauf in der Halle, nicht um
Code. Wird beschrieben und beziffert, damit der Betrieb entscheiden kann.

## Reihenfolge

Nicht nach Schwere sortiert, sondern nach Abhängigkeit: Was die Grundlage
anderer Zahlen ist, kommt zuerst. Wer den Eingang repariert, während er noch
die Verlustquoten anfasst, prüft am Ende zwei Änderungen an einer Zahl und weiss
nicht, welche gewirkt hat.

### Stufe 1 — Der Eingang, denn er ist der Nenner von allem

| # | Feststellung | Was gemacht wird | Woran man es sieht |
|---|---|---|---|
| 1.1 | **LNN-004** Fehlende Kistenzahl wird als null Kisten gerechnet | `v_palette.netto_kg`: `coalesce(p.kisten, 0)` fällt weg. Ohne Kistenzahl gibt es kein Netto. | Ein Prüffall: Palette mit `kisten = null` → `netto_kg` ist NULL, nicht 980. |
| 1.2 | **SZE-002** Gebindeart ohne Tara lässt die ganze Charge verschwinden | Eine Auffälligkeit „Tara fehlt" mit Charge, Gebindeart und den betroffenen Kilo brutto. Die Rechnung bleibt, wie sie ist — Unbekanntes bleibt unbekannt. | `v_plausibilitaet` meldet die Art; der Prüffall S2 zeigt sie. |
| 1.3 | **LNN-005** Eingang trägt „gemessen", enthält aber hochgerechnete Paletten | Die Herkunftsmarke des Eingangs richtet sich nach `n_paletten_mit_netto`: alle → gemessen, sonst „gemessen, teils hochgerechnet" mit der Zahl. | Prüffall: drei Paletten, eine ohne Gebindeart → die Marke sagt es. |
| 1.4 | **LNN-006** Die Masken rechnen ein Netto ohne Palettentara | `tara_kg_palette ?? 0` fällt an allen fünf Stellen weg; fehlt eine der beiden Taras, zeigt die Maske „—" und sagt, welche fehlt. | Modultest über die Netto-Funktion, an allen fünf Stellen dieselbe. |
| 1.5 | **ERF-001** Sechs Felder, aus deren Lücke eine Sicht eine Null macht | `not null` dort, wo die Zeile ohne das Feld nicht rechenbar ist (`lieferung.kg` zuerst); wo eine Lücke zulässig bleibt, wird sie in der Sicht als unbekannt geführt statt als 0. | Der Prüfstand versucht, eine Zeile ohne das Feld einzufügen, und muss abgewiesen werden. |

### Stufe 2 — Unwissen bleibt Unwissen

| # | Feststellung | Was gemacht wird | Woran man es sieht |
|---|---|---|---|
| 2.1 | **LNN-001** 16 Spalten geben ungemessene Ströme als 0,00 kg aus | In `v_hochrechnung_basis` bekommt jede Stromsumme ihr Kennzeichen: ist der Koeffizient unbekannt, ist die Summe NULL. `erg_verlust` macht es bereits so — dieselbe Regel, dieselbe Stelle. | Der Papierfall ohne Messungen: `verlust_heute_kg` ist NULL, nicht 0. Sonde 08 findet nichts mehr. |
| 2.2 | **BEZ-002, BEZ-003** Prozentzahl aus einem ungemessenen Verlust | Fällt mit 2.1 von selbst weg: aus NULL macht `prozent()` bereits „—". Zusätzlich prüft die Oberfläche das Kennzeichen, damit es auch ohne 2.1 stimmt. | Bildschirm-Prüfstand auf einer Saison ohne Messungen: „—", nicht „0,0 %". |
| 2.3 | **SZE-001** „Verlust bis heute: 0 kg" ohne jede Messung | Dasselbe wie 2.1 und 2.2, aus der Sicht des Betriebs beschrieben. Keine eigene Arbeit. | Der Papierfall in Sonde 07. |

### Stufe 3 — Ware, die zweimal oder gar nicht zählt

| # | Feststellung | Was gemacht wird | Woran man es sieht |
|---|---|---|---|
| 3.1 | **SZE-004 / MET-001** Kompost verlässt den Betrieb und liegt weiter im Lager | `v_lieferung_kohorte` nimmt alle drei Bücher. Entsorgtes altert nicht weiter und steht nicht mehr im Bestand — genau das, was 0062 für `marge` schon getan hat. | Prüffall S5: 500 kg Kompost → Bestand sinkt um 500 kg, Bilanzrest bleibt 0. |
| 3.2 | **SZE-006** Vollständig ausgelieferte Charge liegt angeblich noch im Haus | `coalesce(k.im_haus_heute_kg, b.eingang_kg)` unterscheidet künftig „keine Kaskadenzeile" von „keine liegende Portion". Dasselbe für `lager_kg`. | Prüffall S8: alles ausgeliefert → „noch im Haus" 0 kg, Bilanzrest 0 kg. |
| 3.3 | **ERF-002** 4180 kg mehr geliefert als erfasst, ohne Auffälligkeit | Eine Auffälligkeit „Überzählung" mit Charge, Kilo und Sprung zur Korrektur. Die Rechnung ändert sich nicht — sie ist richtig, sie schweigt nur. | `v_plausibilitaet` meldet die neun Chargen der Demosaison. |
| 3.4 | **SZE-003** Zettelgewicht passt zur Charge, aber nicht zum Tag | Die Auffälligkeit „Zettelgewicht" prüft dieselbe Bedingung wie die Massenrechnung, nicht eine schwächere. | Prüffall S4: die Auffälligkeit feuert. |

### Stufe 4 — Was die Zahl über sich selbst sagt

| # | Feststellung | Was gemacht wird | Woran man es sieht |
|---|---|---|---|
| 4.1 | **HER-001** „Ausgeliefert" trägt „gemessen" und enthält den Vorlauf | Wie 1.3: Die Marke sagt, dass ein Teil geschätzt ist, und nennt die Kilo. Der Untertitel tut es bereits — die Marke zieht nach. | Bildschirm-Prüfstand: Marke und Untertitel widersprechen sich nicht mehr. |
| 4.2 | **BEZ-001** „Anteil am Eingang" über einem Nenner, der nicht der Eingang sein muss | Die Beschriftung kommt vom Aufrufer, wie die Zahl auch. | Übersetzer-Prüfung; die Zeile ist zwei Zeichen lang. |
| 4.3 | **H48** `masse_quelle` steht roh in Klammern | Deutsche Worte statt Datenbankwerte („vom Zettel", „aus der mittleren Tara der Charge"). | Begriffs-Prüfstand aus Runde I. |

### Stufe 5 — Das Netz, das die Reparaturen hält

| # | Feststellung | Was gemacht wird | Woran man es sieht |
|---|---|---|---|
| 5.1 | **MUT-002** Drei von dreizehn Verstellungen bleiben unbemerkt | Zu jeder eine Behauptung in `pruefung.sql` mit einer Zahl, die auf Papier nachrechenbar ist. | Sonde 06 meldet null Überlebende. |
| 5.2 | **MUT-001** Drei Verstellungen wirken auf den Demodaten nicht | Ein Papierfall, der den Sockel a₀ und den Deckel bei 25 % ansteuert — nicht in den Demodaten, sondern im Prüfwerk, wo er hingehört. | Sonde 06 meldet null wirkungslose Verstellungen. |
| 5.3 | **ANN-001** Zu keiner Annahme steht, wo ihr Bruch auffiele | Eine vierte Spalte in der Annahmentabelle. Sonde 10 bewacht sie danach: Jede Zeile nennt eine Stelle, und die Stelle existiert. | Sonde 10 findet nichts mehr. |
| 5.4 | **LNN-003** 19 Stellen mit `?? 0` auf einer Masse | Die Liste wird durchgegangen; jede Stelle bekommt entweder ein „—" oder einen Satz, warum die Null dort beobachtet ist. | Die Liste in Sonde 08 wird kürzer; der Rest steht mit Begründung im Code. |

### Stufe 6 — Die Nachlese: dieselbe Frage, umgekehrtes Vorzeichen

Beim Nachprüfen der Stufen 1 bis 5 kamen drei Stellen dazu, die die erste
Runde übersehen hatte. Zwei davon stehen andersherum als alles davor: Dort
steht NULL, wo eine Null **beobachtet** ist.

| # | Feststellung | Was gemacht wird | Woran man es sieht |
|---|---|---|---|
| 6.1 | Die vier Teilbeträge eines Stroms sind NULL, wenn ihre Portion keine Zeile hat — die Oberfläche machte daraus mit `?? 0` „0 kg", auch bei einem ungemessenen Strom | `v_verlust_je_gruppe`: `coalesce(…, 0)` **innerhalb** des `bekannt`-Zweigs. Gemessener Strom → alle vier sind Zahlen; ungemessener → alle vier NULL. Der Rechenweg schreibt dann „nicht gemessen". | `pruefung.sql`: beide Richtungen, dazu `kg_beobachtet + kg_projiziert = kg` auf allen 366 Zeilen. |
| 6.2 | `ausschuss_netto_setzen` und `schimmel_netto_setzen` speichern das **Brutto als Netto**, wenn Kistenzahl oder Tara fehlen — und markieren es als gemessen | Beide Auslöser rechnen ohne `coalesce`. Kommt kein Netto heraus, bleibt die eingetragene Zahl stehen und `gemessen` wird false; die Auswertung liest nur Gemessenes. Keine Bedingung auf der Tabelle: Die Zeile ist eine Beobachtung, nur keine Nettomasse. | `pruefung.sql`: dieselbe Wägung einmal vollständig (gerechnet, gemessen) und einmal ohne Tara (unverändert, nicht gemessen). |
| 6.3 | Die Auffälligkeit „Ausschuss-Tara" meldet „die Tara wurde geändert", wo in Wahrheit die Tara fehlt | Die Prüfung rechnet nur nach, wo sich etwas nachrechnen lässt (`greatest(null, 0)` ist 0 — das Netto muss ausdrücklich vorher geprüft werden). Die Lücke steht als eigene Art daneben: „Ausschuss ohne Tara". | `pruefung.sql`: ohne Tara feuert genau die neue Art und nicht die alte. |

## Stand am Ende von Runde L

| Stufe | Wo es steht | Stand |
|---|---|---|
| 1 Eingang | Migration 0064, `src/lib/masse.ts` | erledigt |
| 2 Unwissen bleibt Unwissen | Migration 0064, Überblick und Ursachen | erledigt |
| 3 Doppelzählung | Migration 0065 (dritte Portion), 0064 (Bestand nach Auslieferung) | erledigt |
| 4 Beschriftung | `Ueberblick.tsx`, `Karten.tsx`, `masse.ts` | erledigt |
| 5 Das Netz | `pruefung.sql` (Mutationsschutz), `docs/ABLAUF.md` (vierte Spalte), Sonde 08 | erledigt |
| 6 Nachlese | Migration 0066, `daten.ts`, `Karten.tsx` | erledigt |
| BEZ-004 Bezugsgrösse | Frage 1 unten | offen, gehört dem Betrieb |
| SZE-005 Umgestapelte Palette | Frage 2 unten | offen, gehört dem Betrieb |

Aus 24 Befunden (18 mit Folgen für eine Zahl) sind die geblieben, die keine
Reparatur sind: die beiden Fragen an den Betrieb, drei „geprüft und in
Ordnung"-Notizen, und die zwei Mutationsbefunde, die sagen, wo das Netz noch
Löcher hat. Die Liste der Stellen mit `?? 0` auf einer Masse ist von 19 über
14 auf 7 gefallen; die sieben, die bleiben, sind Sortierschlüssel und Summen
über bereits gefilterte Listen — jede mit einem Satz darüber, warum die Null
dort beobachtet ist. Sonde 08 prüft seither nicht mehr, ob es solche Stellen
gibt, sondern ob eine ohne Begründung dasteht.

## Was nicht gemacht wird, und warum

**BEZ-004 — „Verlust in Prozent, wovon?"** Nicht entschieden. Der Unterschied
ist beziffert (16,1 % gegen 25,1 %, und die saubere Trennung 13,1 % / 18,0 %);
die Wahl gehört dem Betrieb. Die Frage steht unten.

**SZE-005 — die umgestapelte Palette.** Elf Prozent zu hohe Tagesrate, wenn
zwischen Eingang und Wägung umgestapelt wird. Das ist keine Codefrage: Entweder
wird beim Wiegen die Kistenzahl neu gefragt (eine Frage mehr für den Arbeiter),
oder der Betrieb sagt, dass nicht umgestapelt wird. Beides ist vertretbar,
beides kostet etwas. Vorgelegt, nicht entschieden.

**Alles, was die App erweitert.** Keine neue Auswertung, keine neue Grafik, kein
neuer Bildschirm, keine neue Kennzahl. Wo eine Feststellung nur mit einer
Erweiterung zu beheben wäre, steht sie unter „Frage an den Betrieb" — nicht
unter „Reparatur".

## Die Fragen an den Betrieb

Kurz, ohne Fachsprache, jede mit der Zahl daneben, die an ihr hängt.

**1. Verlust in Prozent — wovon?** Heute steht „16,1 % des Eingangs". Gemeint
sein kann auch: „von dem, was noch nicht draussen ist" — das wären 25,1 %. Wir
raten zu einer dritten Form, weil die beiden ersten je eine Frage beantworten
und die zweite dabei zwei Bestände mischt: **an der ausgelieferten Ware 13,1 %,
an der liegenden Ware 18,0 %.** Die erste ist die Nachrechnung, die zweite die
Zahl, an der sich etwas ändern lässt. Sollen beide stehen, oder eine — und
welche?

**2. Wird zwischen Eingang und Wägung umgestapelt?** Wenn eine Palette beim
Wiegen fünf Kisten weniger hat als beim Eingang, zählt das Gewicht der fünf
Kisten als verdunstetes Wasser. Bei 30 Kisten sind das rund elf Prozent zu viel
auf der Tagesrate — und die Rate geht potenziert in jede Verdunstungszahl der
Sorte ein. Zwei Wege: beim Wiegen die Kistenzahl neu fragen (eine Frage mehr),
oder festhalten, dass nicht umgestapelt wird.

**3. Was ist die Masse einer Fax-Arbeit?** Das Faule beim Abpacken wird als
Anteil dieser Masse gemessen und danach auf die verkaufsfähige Ware angewandt.
Beide Male soll dasselbe gemeint sein: was zum Abpacken kam. Stimmt das — oder
zählt bei der Fax-Arbeit die Eingangsware dahinter?

**4. Soll Entsorgtes als Verlust gelten oder nur als Abgang?** Heute steht es im
Ausgang und bleibt gleichzeitig im Bestand; das ist in jedem Fall falsch. Die
Reparatur nimmt es aus dem Bestand. Offen bleibt, ob es zusätzlich unter den
Verlustursachen erscheinen soll — dann wäre es sichtbar, aber es wäre eine
Ursache mehr auf einer Seite, die bewusst kurz ist.

**5. Die neun Chargen mit Überzählung.** Bei einer davon sind 36,6 % mehr
ausgeliefert worden, als je als Eingang erfasst wurde. Das ist mit grosser
Wahrscheinlichkeit eine fehlende Palette im Erntejournal oder eine Lieferung auf
der falschen Chargennummer. Soll die App das als Auffälligkeit melden (dann
sieht der Betrieb es und kann es korrigieren), oder ist bekannt, woher es kommt?
