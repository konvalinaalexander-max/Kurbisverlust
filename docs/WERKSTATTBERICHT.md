# Werkstattbericht — Runde M

*Erzeugt von `werkstatt/bericht.mjs` aus dem Lauf der vier Werkstätten. Nicht von Hand
ändern — die Fassung, die zählt, entsteht neu mit
`node werkstatt/lauf.mjs && node werkstatt/bericht.mjs`.
Datenbank: `demo`, Saat: 20260909 (alles Zufällige hängt daran; zweimal laufen ergibt dasselbe).*

## Was hier steht

29 Feststellungen und 23 Messreihen aus 15 Werkzeugen
in vier Werkstätten. Jede Feststellung hat eine **Grösse** — ohne Grösse ist eine Feststellung
eine Meinung, und eine Liste von Meinungen nimmt niemand ernst. Jede hat eine **Gegenrede**:
das beste Argument dagegen, aufgeschrieben von dem, der die Feststellung gemacht hat.

Nicht jede Feststellung ist ein Fehler. 12 sind ausdrücklich
„geprüft und in Ordnung" — sie stehen hier, weil ein Bericht, der nur Mängel nennt, nicht sagt,
wie weit nachgesehen wurde.

| Werkstatt | Die Frage | Feststellungen |
|---|---|---|
| **Phase 0 — Schärfe der vorhandenen Werkzeuge** | Sehen die Werkzeuge der letzten Runde überhaupt noch etwas? | 2 |
| **A — Rechenwerk** | Ist das der richtige Schätzer, und ist er ehrlich über sich selbst? | 7 |
| **B — Fundament** | Ist die Datenbank unter der Fachlogik gesund? | 6 |
| **C — Bauwerk** | Ist der Code so gebaut, wie ein Programm dieser Grösse gebaut sein sollte? | 7 |
| **D — Nutzen** | Löst dieses Programm die Probleme des Betriebs? | 7 |

| Klasse | Was das heisst | Anzahl |
|---|---|---|
| 3 — Bedeutung | Die Zahl steht da und meint etwas anderes, als der Leser denkt — oder sie ist falsch. | 5 |
| 2 — Kette | Erfassung, Rechnung und Anzeige passen nicht sauber zusammen; heute trägt es, morgen vielleicht nicht. | 8 |
| 1 — Technisch | Im Bestand nachgesehen und in Ordnung befunden, oder eine Kleinigkeit ohne Folge für eine Zahl. | 16 |

| Marke | Was zu tun ist | Anzahl |
|---|---|---|
| Reparatur | Etwas ist falsch und lässt sich richtigstellen, ohne die App zu erweitern. | 5 |
| Reduktion | Der Code wird kleiner, das Verhalten bleibt gleich — bewiesen, nicht behauptet. | 6 |
| Frage an den Betrieb | Zwei Antworten sind beide vertretbar; entscheiden muss der Betrieb. | 4 |
| Entscheidung des Betriebs | Es geht um den Ablauf in der Halle, nicht um den Code. | 2 |
| kein Fehler | Nachgesehen, in Ordnung. | 12 |

## Was geprüft wurde

| Werkstatt | Werkzeug | Feststellungen | Messreihen | Dauer | Selbstprobe |
|---|---|---|---|---|---|
| Phase 0 — Schärfe der vorhandenen Werkzeuge | `p0_stumpfheit` | 2 | 2 | 85.2 s | ok |
| A — Rechenwerk | `a1_schaetzer` | 1 | 1 | 761.4 s | ok |
| A — Rechenwerk | `a3_verhaeltnis` | 2 | 1 | 4.4 s | ok |
| A — Rechenwerk | `a4_fortpflanzung` | 1 | 1 | 0.7 s | ok |
| A — Rechenwerk | `a7_raender` | 3 | 2 | 0.2 s | ok |
| B — Fundament | `b1_totes` | 2 | 2 | 7.1 s | ok |
| B — Fundament | `b3_rechte` | 2 | 1 | 0.8 s | ok |
| B — Fundament | `b4_integritaet` | 1 | 1 | 33.6 s | ok |
| B — Fundament | `b5_zeit` | 1 | 2 | 7.4 s | ok |
| C — Bauwerk | `c1_vermessung` | 3 | 2 | 0.6 s | ok |
| C — Bauwerk | `c2_doppelgaenger` | 1 | 1 | 0.1 s | ok |
| C — Bauwerk | `c3_totholz` | 3 | 1 | 4.7 s | ok |
| D — Nutzen | `d1_antwortquote` | 1 | 2 | 2.5 s | ok |
| D — Nutzen | `d2_aufloesung` | 3 | 2 | 660 s | ok |
| D — Nutzen | `d4_messwert` | 3 | 2 | 35.5 s | ok |

Die Spalte **Selbstprobe** ist die wichtigste der Tabelle. Jedes Werkzeug bekommt einen Fall
vorgesetzt, in dem es anschlagen *muss*. Steht dort „ok", hat es seinen eigenen eingebauten
Fehler gefunden; steht dort „STUMPF" oder „ohne", sagt auch sein leeres Ergebnis nichts.

## Klasse 3 — Bedeutung

Die Zahl steht da und meint etwas anderes, als der Leser denkt — oder sie ist falsch.

### AUF-001 · Zwei Wege zur selben Unsicherheit kommen zu verschiedenen Antworten

*Reparatur · Sicherheit hoch · Aufwand mittel · `v_verlust_je_gruppe`*

**Grösse.** **3.8 Faktor zwischen den zwei Rechenwegen für dieselbe Unsicherheit** (200 Ziehungen, Demodaten)

**Was dasteht.** Für 2 von 6 Verlustursachen weicht die Streuung, die sich beim Durchrechnen der Kaskade mit gezogenen Koeffizienten ergibt, um mehr als das Doppelte von der fortgepflanzten Streuung der Auswertung ab — und zwar **auch dann, wenn der t-Faktor der Freiheitsgrade auf beiden Seiten herausgerechnet ist**: Schimmel/Fäulnis — Delta-Methode ±2521 kg, durchgerechnet ±9698 kg (Faktor 3.85); Nicht lagerbedingt — Delta-Methode ±380 kg, durchgerechnet ±189 kg (Faktor 0.50). Bei den übrigen Strömen stimmen die beiden Wege überein, sobald der t-Faktor draussen ist — dort steckt der ganze Unterschied in den Freiheitsgraden und ist als eigener Befund erfasst.

**Was dastehen müsste.** Die Auswertung leitet ihr Band mit der Delta-Methode her: Sie linearisiert die Kaskade um den Schätzwert und pflanzt die Varianzen mit den Ableitungen fort. Das ist ein anerkanntes Verfahren, aber es gilt nur, solange die Kaskade sich auf der Breite des Bands ungefähr wie eine Gerade verhält. Die Schimmelkurve tut das nicht: Sie ist `exp(a + k·ln t)`, und was hinter einer Exponentialfunktion liegt, kann eine Linearisierung nicht einfangen. Beide Zahlen gehören nebeneinander geprüft — und die Herleitung entscheidet, nicht die bequemere Zahl.

**Warum das zählt.** Das Band ist keine Verzierung. Es steht auf dem Bildschirm und beantwortet die Frage, wie ernst der Betrieb eine Zahl nehmen soll. Ist es um einen Faktor daneben, ist jede Aussage darüber, ob ein Unterschied zählt, um denselben Faktor daneben.

**Gegenrede.** **Wichtig für die Reihenfolge der Reparaturen:** Bei der Schimmelkurve zeigen die beiden Fehler in entgegengesetzte Richtungen und heben sich zum Teil auf. Der t-Faktor macht das Band 6.5-mal zu weit (Befund FPF-001), die Linearisierung macht die Streuung 3.9-mal zu eng — heraus kommt ein Band, das ungefähr stimmt, aus zwei falschen Gründen. **Wer nur die Freiheitsgrade richtigstellt, macht es schlimmer**: Aus zufällig ungefähr richtig würde selbstbewusst zu eng. Die beiden Reparaturen gehören zusammen oder gar nicht.

Im Übrigen ist die Ziehung nicht automatisch die richtigere. Sie unterstellt, dass die gezogenen Parameter normalverteilt sind und dass die Koeffizienten voneinander unabhängig sind — beides sind Annahmen. Insbesondere kann eine Ziehung, die weit in den Rand des Bands greift, Kurven erzeugen, die kein Kürbis je gelaufen ist. Dass die beiden Wege auseinandergehen, ist der Befund; welcher recht hat, ist die nächste Frage und braucht die Herleitung, nicht mehr Ziehungen.

<sub>Nachweis: werkstatt/d_nutzen/d2_aufloesung.mjs, Messreihe „Eichung"</sub>

---

### AUF-002 · Der Überblick sagt, welche Verlustursache die grösste ist — die Daten sagen es nicht

*Reparatur · Sicherheit hoch · Aufwand mittel · `src/pages/Ueberblick.tsx` · `v_verlust_ranking`*

**Grösse.** **70 % Sicherheit für die oberste Zeile des Überblicks (nötig wären 97,5 %)** (200 Ziehungen, Demodaten)

**Was dasteht.** Die Auswertung stellt `Schimmel/Fäulnis` (26265 kg) über `Verdunstung` (23610 kg) und malt sie als obersten Balken. Zieht man die Koeffizienten 200 Mal aus den Bändern, die dieselbe Auswertung ausweist, ist `Schimmel/Fäulnis` nur in 70 % der Ziehungen die grössere. Der Unterschied liegt zu 95 % zwischen -5710 und 14579 kg — das Vorzeichen wechselt. Zum Vergleich: **jeder andere** der zehn Vergleiche zwischen Verlustursachen kommt in 100 % der Ziehungen gleich heraus. Es ist ausgerechnet der Vergleich ganz oben, der nicht trägt.

**Was dastehen müsste.** Die Reihenfolge darf nicht als Reihenfolge auftreten, solange sie keine ist. Zwei kleine Mittel: Balken, deren Unterschied das Vorzeichen wechselt, bekommen dieselbe Farbe oder werden zu einer Gruppe zusammengefasst — „Schimmel und Verdunstung, zusammen rund die Hälfte; welche der beiden grösser ist, sagen die Daten nicht". Und die Kachel nennt die Zahl, die heute fehlt: wie viele Messungen es bräuchte, damit die Reihenfolge trägt.

**Warum das zählt.** Aus dieser einen Reihenfolge folgt eine Handlung, und es sind zwei verschiedene. Gewinnt die Verdunstung, geht es um Luftfeuchte und kürzere Lagerung; gewinnt der Schimmel, geht es um früheres Aussortieren. Das sind verschiedene Investitionen in verschiedene Anlagen. Ein Balkendiagramm, das diese Wahl trifft, wo die Daten sie nicht treffen, ist schlechter als eines, das schweigt — denn es sieht aus wie eine Antwort.

**Gegenrede.** Die Ziehung der Schimmelkurve ist ausgerechnet die, die in der Eichung von der Delta-Methode abweicht — sie ist also die unsicherste der sechs. Wäre die Delta-Methode im Recht, wäre der Vergleich entschieden. Dagegen spricht die Rechnung: `exp(a + k·ln t)` ist keine Gerade, und eine Linearisierung unterschätzt die Streuung dahinter systematisch. Wer diesen Befund entkräften will, muss zeigen, dass die Linearisierung über die Breite dieses Bandes trägt — nicht, dass sie bequemer ist.

<sub>Nachweis: werkstatt/d_nutzen/d2_aufloesung.mjs: 200 Ziehungen der sechs Koeffizientensichten aus ihren eigenen `unten`/`oben`-Spalten, volle Kaskade je Ziehung; Eichung siehe Messreihe darüber</sub>

---

### FPF-001 · Die Unsicherheitsbänder sind bei 5 von 5 Strömen rund 6.3-mal zu weit — der schlechteste Bestandteil bestimmt sie allein

*Reparatur · Sicherheit hoch · Aufwand klein · `v_verlust_je_gruppe`*

**Grösse.** **22775 kg zu breite Bänder über alle 5 Ströme zusammen (grösster einzeln: 13822 kg bei Schimmel/Fäulnis)** (116 von 365 Zeilen über alle Gruppen betroffen)

**Was dasteht.** Die Freiheitsgrade eines Bands entstehen als `LEAST(df_verdunstung, df_ausschuss, df_modell)`, und innerhalb jedes Bestandteils noch einmal als `min(df)` über die Sorten. Zweimal ein Minimum, und beide Male zieht der am schlechtesten belegte Summand das ganze Band auf. Alle 5 Ströme stehen deshalb auf df = 1 und t = 12.706. Zerlegt man die Varianz bis auf die einzelne Sorte und gewichtet jeden Freiheitsgrad mit seinem Varianzanteil, kommen 15 bis 38 heraus. Beim grössten Strom (`Schimmel/Fäulnis`, 26265 kg) trägt `Schimmelmodell` 100 % der Varianz und hat df 32 — den Freiheitsgrad setzt trotzdem ein Bestandteil mit df 1.

**Was dastehen müsste.** Die Freiheitsgrade einer Varianzsumme sind nicht das Minimum, sondern Satterthwaites Näherung: `df_eff = (Σvᵢ)² / Σ(vᵢ²/dfᵢ)`. Sie ist eine Zeile SQL, braucht nichts, was nicht schon dasteht, und ist nicht grosszügiger — wo der schwache Bestandteil die Varianz wirklich trägt, ergibt sie von selbst wieder df = 1. Nötig ist sie an **beiden** Stellen: über die drei Bestandteile und über die Sorten darin.

**Warum das zählt.** Ein zu weites Band ist keine gute Vorsicht. Es beantwortet die Frage „darf ich diesen Unterschied glauben?" mit Nein, wo die Antwort Ja wäre. Der Betrieb hat für diese Zahlen Arbeiterzeit bezahlt; ein Band, das ihren Wert um mehr als das Sechsfache kleinredet, macht einen Teil dieser Arbeit wertlos.

**Gegenrede.** Drei ernsthafte Einwände. **Erstens** ist ein zu weites Band die sichere Seite: Wer zu wenig behauptet, führt niemanden in die Irre. **Zweitens** ist Satterthwaite selbst eine Näherung und setzt voraus, dass die Bestandteile unabhängig sind — sie stammen hier teils aus denselben Wägungen; für die Sorten untereinander ist die Annahme gut, für Verdunstung gegen Schimmel weniger. **Drittens** löst die Korrektur das eigentliche Problem nicht: 41 verwendbare Wägungen bleiben 41. Trotzdem ist `min` hier nicht die vorsichtige, sondern die falsche Wahl — sie verwechselt „Freiheitsgrade einer Summe" mit „Freiheitsgrade des schwächsten Summanden". Und für den grössten Strom gilt zusätzlich: Die Delta-Methode unterschätzt die Streuung dort um Faktor 3.9 (Befund AUF-001), die beiden Fehler heben sich zum Teil auf. **Wer nur die Freiheitsgrade richtigstellt, macht das Schimmelband schlechter, nicht besser.**

<sub>Nachweis: werkstatt/a_rechenwerk/a4_fortpflanzung.mjs: Varianz aus der laufenden Sicht bis auf die einzelne Sorte zerlegt, Summe je Zeile gegen `streuung_kg` geprüft, Satterthwaite danebengerechnet</sub>

---

### SCH-001 · Eine Sorte, die sich den Koeffizienten einer anderen leiht, bekommt kein breiteres Band

*Reparatur · Sicherheit hoch · Aufwand klein · `v_koeff_verdunstung` · Spalte `unten/oben`*

**Grösse.** **12 von 14 Sorten mit geliehenem Koeffizienten** (Demosaison, v_koeff_verdunstung)

**Was dasteht.** In der Demosaison haben 2 von 14 Sorten eigene Verdunstungswägungen; die übrigen 12 bekommen den Wert „Wiegungen aller Sorten" — **mit demselben Band wie der gepoolte Wert**. Das Band bildet nur die Streuung der Wägungen ab, nicht die zusätzliche Unsicherheit darüber, ob die fremde Sorte sich überhaupt gleich verhält. In der Simulation liegt die Überdeckung des gepoolten Werts bei 90 %.

**Was dastehen müsste.** Ein geliehener Koeffizient trägt zwei Unsicherheiten: die der Messung und die der Übertragung. Das Band müsste beide enthalten — oder die Zahl müsste sagen, dass sie geliehen ist. Die Spalte `basis` sagt es bereits; auf dem Bildschirm steht es nicht.

**Warum das zählt.** Der Betriebsleiter vergleicht Sorten miteinander. Zwölf seiner vierzehn Sorten tragen dieselbe geliehene Zahl mit demselben Band — jeder Unterschied, den er zwischen ihnen sieht, kommt allein aus der Lagerdauer, nicht aus der Sorte. Das ist genau die Verwechslung, die zu einer falschen Sortenwahl führt.

**Gegenrede.** Pooling ist die richtige Antwort auf eine dünne Stichprobe — die Alternative wäre, für zwölf Sorten gar nichts zu sagen. Der Einwand richtet sich nicht gegen das Pooling, sondern gegen das Band und gegen das Schweigen darüber auf dem Bildschirm.

<sub>Nachweis: v_koeff_verdunstung in der Demosaison (Spalte `basis`) + werkstatt/a_rechenwerk/a1_schaetzer.mjs</sub>

---

### STU-001 · 1 Prüfstand/Prüfstände laufen mit einem hineingelegten Fehler genauso durch wie ohne

*Reparatur · Sicherheit hoch · Aufwand mittel · `pruefstand/kette.mjs`*

**Grösse.** **1 von 2 geprüften Prüfständen winken den hineingelegten Fehler durch** (Wegwerfkopie der Demodatenbank)

**Was dasteht.** In eine Wegwerfkopie der Demodatenbank wurde eine Kaskadenformel, die ein anderes Ergebnis liefert gelegt. `pruefstand/kette.mjs` läuft ohne den Fehler durch — und mit ihm ebenfalls. Bei `kette.mjs` ist der gelegte Fehler fünf Prozent auf **jede** gerundete Zahl der Auswertung: `zahl()` steht in fast jeder Sicht des Rechenwerks. Wer diese Änderung nicht bemerkt, bemerkt keine.

**Was dastehen müsste.** Der Prüfstand prüft heute den **Schreibweg**: dass die Maske das schreibt, was in die Tabelle gehört. Das ist richtig und reicht nicht. Er müsste zusätzlich mindestens eine gerechnete Zahl je Tätigkeit gegen einen von Hand ausgerechneten Wert halten — nicht die ganze Auswertung, sondern einen Anker je Kette. Das Prüfwerk hat dafür schon ein Werkzeug (`pruefwerk/` Sonde 04, das unabhängig geschriebene Orakel); hier fehlt nur der Griff darauf.

**Warum das zählt.** Ein Prüfstand, der einen Fehler nicht sieht, ist nicht neutral — er ist ein Versprechen, das nicht eingelöst wird. `kette.mjs` wird in `README.md` als die Prüfung beschrieben, die „die Kette in beide Richtungen" geht. Wer das liest und danach eine Formel ändert, hält ein grünes Ergebnis für eine Aussage über die Formel. Es ist keine.

**Gegenrede.** Der Prüfstand ist für den Schreibweg gebaut, nicht für die Rechnung — dafür gibt es das Prüfwerk mit seinem eigenen Orakel, und das **hat** die Mutation gesehen. Wer beides von `kette.mjs` verlangt, baut die Sonde ein zweites Mal. Dagegen steht: Die beiden laufen nicht zusammen — `run.sh` ruft die Kette, das Prüfwerk läuft von Hand. Solange das so ist, ist die grüne Kette die Zahl, die jemand sieht.

<sub>Nachweis: werkstatt/phase0/p0_stumpfheit.mjs: Fehler in eine Kopie gelegt, Prüfstand zweimal ausgeführt (ohne und mit), Rückgabewerte verglichen</sub>

## Klasse 2 — Kette

Erfassung, Rechnung und Anzeige passen nicht sauber zusammen; heute trägt es, morgen vielleicht nicht.

### ANTW-001 · Der Reiter **Ursachen** antwortet auf 80.6 % seiner Felder, die übrigen auf 98.5 % bis 90.7 %

*Frage an den Betrieb · Sicherheit hoch · Aufwand mittel · `erg_punkte, erg_kurve, erg_modell, erg_ausschuss, erg_fax, erg_ueberfuellung, erg_selektion`*

**Grösse.** **80.6 % Antwortquote auf Ursachen, gegen 93.9 % über alle fünf Reiter (30'787 Felder)** (Demosaison)

**Was dasteht.** Über alle fünf Reiter stehen 30'787 Zahlenfelder; in 28'912 davon steht ein Wert, das sind 93.9 %. Sie verteilen sich sehr ungleich: Überblick 97.8 %, Ursachen 80.6 %, Chargen 98.5 %, Messungen 97.3 %, Betrieb 90.7 %. Auf **Ursachen** haben 24 Spalten in einem Teil der Zeilen keinen Wert und 3 in keiner einzigen (`erg_modell.selektions_versatz`, `erg_selektion.rest_lager`, `erg_selektion.unterschied`).

**Was dastehen müsste.** Das ist keine Reparatur am Code. Je Spalte gibt es drei mögliche Antworten, und „lassen wie es ist" ist keine davon: Entweder fehlt eine Messung, die der Betrieb machen könnte — dann gehört sie in `docs/FRAGEN.md`. Oder sie ist für diesen Betrieb nicht vorgesehen — dann gehört die Spalte weg, samt der Stelle, die sie anzeigt. Oder sie füllt sich erst im Lauf der Saison — dann gehört ein Satz daneben, der das sagt.

**Warum das zählt.** Ein Strich ist die richtige Anzeige für Unbekanntes, und er ist teuer: Der Betriebsleiter sieht ihn und weiss nicht, ob die Messung fehlt, ob sie noch kommt oder ob die Spalte für seinen Betrieb nie etwas zeigen wird. Beim dritten Strich hört er auf, dort hinzuschauen — und übersieht den vierten, hinter dem etwas steckt. Ausgerechnet **Ursachen** ist der Reiter, auf dem der Betriebsleiter nachsieht, wenn er wissen will, woran die Ware fehlt.

**Gegenrede.** Drei Einwände. **Erstens** ist die Demosaison nicht der Betrieb: Sie ist gebaut, um die Rechenwege zu zeigen, nicht um jede Messung einmal vorzuführen. **Zweitens** ist ein niedriger Wert nicht automatisch schlecht — der Reiter Ursachen zeigt je Sorte und je Charge, und eine Sorte ohne eigene Wägung *soll* dort einen Strich haben statt einer geliehenen Zahl ohne Kennzeichnung. **Drittens** wiegt dieses Werkzeug jedes Feld gleich: Eine selten gelesene Diagnosespalte des Modells zählt so viel wie die Verlustzahl selbst. Die Quote ist deshalb ein Wegweiser zum Durchsehen, keine Note.

<sub>Nachweis: werkstatt/d_nutzen/d1_antwortquote.mjs: `count(spalte)` gegen `count(*)` über alle 30 gespeicherten Ansichten der fünf Reiter</sub>

---

### ERT-001 · Die Rangfolge der Messungen nach Ertrag gibt es — sie stand nur nirgends

*Entscheidung des Betriebs · Sicherheit mittel · Aufwand klein · `docs/ABLAUF.md`*

**Grösse.** **39 Arbeitsstunden je Saison, deren Ertrag bisher unbeziffert war** (7 Messarten, Demodaten, Minuten geschätzt)

**Was dasteht.** Der Betrieb erfasst 1051 Messungen in 7 Arten und wendet dafür nach der Annahme dieses Werkzeugs rund 39 Arbeitsstunden je Saison auf. Was jede davon einbringt, hat bisher niemand ausgerechnet. Gemessen: **Palox-Ablesung** — 2 Ströme verstummen ohne sie, **Lagerkontroll-Wägung** — 1 Ströme verstummen ohne sie, **Schimmel-Kistenwägung** — 1 Ströme verstummen ohne sie. Am wenigsten bringt **Palette mit Zettelgewicht zählen** mit -0.2 kg je Minute.

**Was dastehen müsste.** Diese Tabelle gehört dem Betrieb, nicht diesem Bericht. Zwei Dinge folgen daraus: Der Betrieb kann entscheiden, **wovon er mehr macht** — und, was schwerer wiegt, wovon er in der Erntezeit weniger machen darf, ohne dass eine Auskunft verlorengeht. Vorher muss er allerdings die Minutenspalte korrigieren: Die Zahlen dort sind geschätzt, und die Rangfolge hängt an ihnen.

**Warum das zählt.** In der Erntezeit ist Arbeiterzeit die knappste Grösse des Betriebs. Eine Messung, die in dieser Zeit gemacht wird und nichts einbringt, ist nicht neutral — sie geht auf Kosten einer anderen. Ohne diese Tabelle wird nach Gefühl entschieden, und das Gefühl folgt meist dem Aufwand, nicht dem Ertrag.

**Gegenrede.** Zwei Einwände, beide ernst. **Erstens** misst dieses Verfahren den Ertrag der Messart als Ganzes, nicht den der nächsten einzelnen Messung. Der Grenzertrag fällt, und zwar ungefähr mit der Wurzel: Die einundvierzigste Wägung bringt weniger als die erste. Wer aus dieser Tabelle „doppelt so viele Wägungen, halb so breites Band" liest, irrt. **Zweitens** stehen und fallen die Minutenzahlen mit einer Schätzung, die niemand aus dem Betrieb bestätigt hat — deshalb ist dieser Befund als Entscheidung des Betriebs markiert und nicht als Reparatur.

<sub>Nachweis: werkstatt/d_nutzen/d4_messwert.mjs: je Messart eine Kopie der Demodatenbank, alle Zeilen dieser Art gelöscht, `auswertung_aktualisieren()`, Bandbreiten vorher/nachher</sub>

---

### ERT-002 · Die ertragreichste Messung ist zugleich eine der seltensten: Ausschuss-Wägung

*Entscheidung des Betriebs · Sicherheit mittel · Aufwand klein · `docs/ABLAUF.md`*

**Grösse.** **378 kg Bandbreite je einzelner Ausschuss-Wägung** (34 Erfassungen, Demodaten)

**Was dasteht.** `Ausschuss-Wägung` wird 34 Mal erfasst — rund 1.7 Arbeitsstunden in der ganzen Saison — und nimmt 12867 kg Bandbreite weg, also 378 kg je einzelner Wägung. Am anderen Ende steht `Palette mit Zettelgewicht zählen` mit 231 Erfassungen (3.9 Arbeitsstunden) und -0.2 kg je Erfassung. Zwischen den beiden liegt Faktor 2197.

**Was dastehen müsste.** Das ist keine Programmänderung, sondern eine Frage an die Halle: Lässt sich von `Ausschuss-Wägung` mehr machen, ohne dass anderes liegenbleibt? Die Antwort kennt nur der Betrieb. Was das Programm dazu beitragen kann, ist der Hinweis an der richtigen Stelle — die Maske, die eine solche Wägung anbietet, könnte sagen, was sie wert ist.

**Warum das zählt.** Wer nicht weiss, welche Messung was einbringt, verteilt seine Zeit nach Aufwand statt nach Ertrag. Genau das ist hier passiert: Die aufwendigste Messart bindet 15 Stunden, die ertragreichste unter zwei.

**Gegenrede.** Der hohe Ertrag je Messung kann gerade **daher** kommen, dass es so wenige gibt: Die ersten Messungen einer Art bringen immer am meisten, und der Grenzertrag fällt ungefähr mit der Wurzel. Verdoppelte man die Zahl, bliebe vermutlich weniger als die Hälfte des Ertrags je Stück übrig. Die Rangfolge kippt dadurch aber nicht — dafür ist der Abstand zu gross.

<sub>Nachweis: werkstatt/d_nutzen/d4_messwert.mjs, Messreihe „Was jede Messart an Unsicherheit wegnimmt"</sub>

---

### ERT-003 · 1 Messart(en) kosten Arbeiterzeit, ohne eine Zahl der Auswertung messbar zu ändern

*Frage an den Betrieb · Sicherheit hoch · Aufwand klein · `docs/ABLAUF.md`*

**Grösse.** **3.9 Arbeitsstunden je Saison ohne messbare Wirkung auf eine Zahl** (Demodaten)

**Was dasteht.** **Palette mit Zettelgewicht zählen**: 231 Erfassungen, rund 3.9 Arbeitsstunden je Saison. Ohne sie ändert sich der Saisonverlust um 13 kg von 52301 kg, und die Summe der Bänder um -40 kg von 28247 kg — beides unter einem halben Prozent. Kein Strom verstummt.

**Was dastehen müsste.** Zwei Möglichkeiten, und nur der Betrieb kennt die richtige. Entweder die Messung dient etwas anderem als der Verlustrechnung — Rückverfolgbarkeit, Abrechnung, Kontrolle des Arbeitsablaufs. Dann gehört dieser Zweck aufgeschrieben, damit sie nicht eines Tages als nutzlos gestrichen wird. Oder sie ist für die Verlustrechnung gedacht und **kommt dort nicht an** — dann ist nicht die Messung das Problem, sondern die Rechnung, die sie nicht liest.

**Warum das zählt.** Die zweite Möglichkeit ist die gefährlichere: Wer etwas erfasst, das nirgends ankommt, erfasst es irgendwann schlampig — und niemand merkt es, weil es ohnehin nirgends ankommt. Bei der Palette mit Zettelgewicht wäre das besonders bitter, weil dieselbe Zahl an anderer Stelle sehr wohl gebraucht wird.

**Gegenrede.** Auf den Demodaten, und das ist eine ernste Einschränkung. Eine Messart kann genau dann nichts beitragen, wenn eine andere dasselbe schon sagt — in einer Saison, in der die andere fehlt, wäre sie die einzige Quelle. Ausserdem misst dieses Werkzeug nur die Wirkung auf die Verlustrechnung; eine Zahl, die im Arbeitsablauf gebraucht wird, taucht hier gar nicht auf. Bevor irgendetwas weggelassen wird, gehört dieselbe Messung auf echten Daten mehrerer Saisons wiederholt.

<sub>Nachweis: werkstatt/d_nutzen/d4_messwert.mjs, beide Messreihen dieser Werkstatt</sub>

---

### FORM-001 · 22 Stellen im Frontend haben dieselbe Form wie eine andere (zusammen rund 1601 Zeilen)

*Reduktion · Sicherheit hoch · Aufwand mittel · `src/lib/i18n.ts:285`*

**Grösse.** **1601 Zeilen, die in 22 Paaren ein zweites Mal dastehen (die längere Hälfte je Paar nicht mitgezählt)** (src/ und test/)

**Was dasteht.** Der längste Fall steht in `src/lib/i18n.ts:285` und noch einmal in `src/lib/i18n.ts:513` — 3516 Wortmarken lang, also nicht zwei ähnliche Zeilen, sondern ein zusammenhängender Handgriff. Verglichen wurden Gerüste, nicht Zeichen: Bezeichner, Zahlen und Zeichenketten sind ersetzt, damit zwei Stellen auch dann gleich heissen, wenn keine Variable gleich heisst. Insgesamt 22 Paare ab 100 Marken, 72 ab 60.

**Was dastehen müsste.** Wo zwei Stellen aus demselben Grund gleich sind, gehört der Handgriff einmal in eine Funktion und zweimal aufgerufen. Wo sie zufällig gleich sind — zwei Tabellen mit gleichem Aufbau und verschiedener Bedeutung —, bleiben sie besser getrennt. Diese Entscheidung fällt je Paar, nicht pauschal; die Messreihe darüber nennt alle.

**Warum das zählt.** Ein Klon ist keine doppelte Sicherheit, sondern eine halbe: Wer eine Zahl in der einen Fassung richtigstellt und die andere übersieht, hat zwei Anzeigen, die dasselbe heissen und verschieden sind. Genau so ist die zweite Schimmelrechnung entstanden.

**Gegenrede.** Gleiche Form ist nicht gleiche Bedeutung. Zwei Bildschirme, die je eine Tabelle mit Filterzeile zeigen, haben dieselbe Form, weil eine Tabelle mit Filterzeile nun einmal so aussieht — daraus eine gemeinsame Funktion zu schnitzen, macht beide Seiten schwerer zu lesen und die gemeinsame Funktion zu einem Ding mit sieben Schaltern. Der Befund nennt deshalb eine Zahl und keine Anweisung. Und: Die Zeilenzahl ist die obere Schranke des Ersparten, nicht das Ersparte — jede Zusammenlegung kostet ihrerseits einen Funktionskopf und eine Aufrufstelle.

<sub>Nachweis: werkstatt/c_bauwerk/c1_vermessung.mjs: Wortmarken normalisiert, Fenster ab 60 Marken, Treffer beidseitig verlängert, enthaltene Treffer entfernt</sub>

---

### FORM-002 · 14 Ansichten enthalten ein Stück SQL, das anderswo genauso steht

*Reduktion · Sicherheit mittel · Aufwand mittel · `v_koeff_kaliber_geschaetzt`*

**Grösse.** **14 Stellenpaare ab 120 Wortmarken (längstes 929)** (Demodaten)

**Was dasteht.** Der längste Fall verbindet `v_koeff_kaliber_geschaetzt` und `v_koeff_verdunstung_geschaetzt` über 929 Wortmarken. C2 sieht das nicht: Die beiden Ansichten sind als Ganzes verschieden, gleich ist nur ein Stück darin. Verglichen wurde das Gerüst der von PostgreSQL zurückgegebenen Definition, nicht der Quelltext der Migration — Formatierung spielt damit keine Rolle.

**Was dastehen müsste.** Ein Stück Rechnung, das in zwei Ansichten gleich dasteht, gehört in eine eigene Ansicht, die beide lesen. Dann steht die Formel einmal da und ändert sich einmal.

**Warum das zählt.** Bei SQL wiegt das schwerer als im Frontend: Eine Formel, die an zwei Stellen steht und an einer geändert wird, ergibt zwei Zahlen, die beide plausibel aussehen. Im Frontend fällt so etwas beim Ansehen auf, in einer Ansicht nicht.

**Gegenrede.** Eine gemeinsame Zwischenansicht ist nicht gratis: Sie ist ein weiteres Objekt in einer Kette, die schon neunzig Objekte lang ist, und der Planer muss sie jedes Mal mit auflösen. Wo das gleiche Stück ein `join` auf dieselbe Stammtabelle ist, ist es zudem eher eine Selbstverständlichkeit als eine Doppelung. Die Zahl ist deshalb eine Liste zum Durchsehen, keine Aufgabenliste.

<sub>Nachweis: werkstatt/c_bauwerk/c1_vermessung.mjs: `pg_get_viewdef` aller Ansichten in Wortmarken zerlegt, Fenster ab 120 Marken</sub>

---

### INT-001 · Eine doppelt abgetippte Zeile verschiebt die Bilanz um bis zu 1888 kg, und niemand sagt etwas

*Frage an den Betrieb · Sicherheit hoch · Aufwand mittel · Tabelle `verdunstung_wiegung, schimmel_messung, ausschuss_messung, ausgang_wiegung, lieferung, auftrag_palette`*

**Grösse.** **1888.14 kg Bilanzverschiebung aus einer einzigen doppelten Zeile** (lieferung, schwerste Zeile der Demodaten)

**Was dasteht.** In 6 von 6 Messtabellen kann dieselbe Beobachtung ein zweites Mal erfasst werden, ohne dass ein eindeutiger Schlüssel es verhindert oder die Plausibilitätssicht es meldet. Nachgemessen auf je einer Kopie der Demodatenbank: eine einzige zusätzliche Zeile in `lieferung` verschiebt die Saisonbilanz um 1888.14 kg — sie bewegt ausgang, verlust_heute, verdunstung_heute, schimmel_heute, im_haus_heute.

**Was dastehen müsste.** Zwei Wege, und die Wahl gehört dem Betrieb. **Verhindern**: ein eindeutiger Schlüssel über die Spalten, die eine Beobachtung ausmachen — sauber, aber er verbietet auch die legitime Wiederholung. **Melden**: ein Zweig in `v_plausibilitaet`, der wortgleiche Zeilen derselben Tabelle nebeneinanderstellt und fragt „zweimal erfasst oder zweimal gemessen?". Das ist der Weg, den dieses Programm sonst überall geht: beobachten und fragen, statt zu folgern und zu verbieten.

**Warum das zählt.** Am Zettel abtippen passiert in der Halle, unter Zeitdruck, oft von zwei Leuten nacheinander. Eine Doppelung ist kein seltener Sonderfall, sondern der wahrscheinlichste Erfassungsfehler überhaupt — und der einzige aus dieser Familie, den das Programm derzeit nirgends sieht.

**Gegenrede.** Drei Einwände, und alle drei sind ernst zu nehmen. **Erstens** ist eine zweite Wägung derselben Palette kein Fehler, sondern genau das, wofür die Verdunstungsmessung gebaut ist — ein eindeutiger Schlüssel wäre dort schädlich. **Zweitens** ist selbst die grösste gemessene Verschiebung (1888 kg) gegen 323 t Eingang klein; sie fällt in keiner Anzeige auf, verzerrt aber auch nichts, was eine Entscheidung trägt. **Drittens** ist die Gefahr nicht überall gleich: schimmel_messung (als Palox-Ablesung) bewegt sich gar nicht, weil dort ein Füllstand und nicht eine Menge erfasst wird — zwei gleiche Füllstände ergeben die Differenz null. Das ist keine Absicht, aber es wirkt. Deshalb steht hier eine Frage und keine Reparaturanweisung.

<sub>Nachweis: werkstatt/b_fundament/b4_integritaet.mjs: je Fall eine Kopie der Demodatenbank, die schwerste Zeile wortgleich verdoppelt, `auswertung_aktualisieren()`, Saisonbilanz vorher/nachher; Messreihe „Was eine doppelt erfasste Zeile in Kilogramm bewegt"</sub>

---

### TOT-001 · 30 Suchindexe wurden an einem vollständigen Arbeitstag kein einziges Mal benutzt

*Reduktion · Sicherheit mittel · Aufwand klein · Tabelle `erg_gewichte, auftrag, mv_hochrechnung, sortier_lauf, mv_schimmel_punkte, erg_verlauf, ausschuss_messung, mv_sortier_lauf_masse, mv_auftrag_masse, erg_punkte, verdunstung_wiegung, lieferung, sortierschema, lieferung_import, ausgang_zeile, erg_ueberfuellung, charge, erg_ausgang, erg_lieferung, erg_kohorte, mv_kaskade, erg_wiegung, erg_fax, erg_verarbeitung_alter, erg_durchsatz`*

**Grösse.** **30 ungenutzte Suchindexe** (88 Indexe, gemessen über einen vollständigen Arbeitstag auf den Demodaten)

**Was dasteht.** `erg_gewichte_sorte`, `auftrag_charge_nr_start_ts_idx`, `mv_hochrechnung_charge`, `sortier_lauf_auftrag`, `mv_schimmel_punkte_charge`, `mv_schimmel_punkte_quelle`, `erg_verlauf_woche`, `ausschuss_messung_auftrag_id_art_idx`, `sortier_lauf_zuordnung_idx`, `mv_sortier_lauf_masse_charge`, `mv_auftrag_masse_charge`, `mv_auftrag_masse_station` … und 18 weitere. Zusammen 528 kB. Gemessen nach `pg_stat_reset()`, einer vollständigen Neuberechnung der Auswertung, 35 geladenen Ansichten und sieben gezielten Abfragen.

**Was dastehen müsste.** Ein Index, den keine Abfrage benutzt, gehört weg — oder es fehlt die Abfrage, für die er gebaut wurde. Beides ist eine Antwort; der heutige Zustand ist keine.

**Warum das zählt.** Ein Index kostet bei **jedem** Schreiben Zeit und bringt nur beim Lesen etwas. Der Arbeiter an der Waage, der auf „Speichern" drückt, bezahlt ihn; der Betriebsleiter, für den er gedacht war, benutzt ihn nicht.

**Gegenrede.** Die Demosaison ist eine Saison; ein Index kann für einen Fall gebaut sein, den sie nicht enthält (eine bestimmte Suche des Betriebsleiters, ein Import bestimmter Grösse). Und bei 844 Paletten wählt der Planer oft den sequenziellen Weg, weil die Tabelle klein ist — bei zehnfacher Menge könnte derselbe Index gebraucht werden. Vor dem Entfernen gehört deshalb der Lasttest dazu, nicht nur dieser Lauf.

<sub>Nachweis: werkstatt/b_fundament/b1_totes.mjs → Messreihe „Indexe nach einem vollständigen Arbeitstag"</sub>

## Klasse 1 — Technisch

Im Bestand nachgesehen und in Ordnung befunden, oder eine Kleinigkeit ohne Folge für eine Zahl.

### AUF-003 · Geprüft: 638 von 781 Vergleichen halten der Ziehung stand

*kein Fehler · Sicherheit mittel · Aufwand klein · `v_verlust_je_gruppe`*

**Grösse.** **638 von 781 Vergleichen tragen** (200 Ziehungen, Demodaten)

**Was dasteht.** 638 Paarvergleiche kommen in mindestens 97,5 % der 200 Ziehungen mit demselben Vorzeichen heraus. Der deutlichste ist „Schimmel/Fäulnis gegen Zu klein (Tierfutter)" (Verlustursache).

**Was dastehen müsste.** —

**Warum das zählt.** Ein Bericht, der nur sagt, was nicht trägt, sagt nichts darüber, wie weit nachgesehen wurde. Diese Zeile ist die Gegenprobe: Das Verfahren erklärt nicht alles für unentscheidbar, es unterscheidet.

<sub>Nachweis: werkstatt/d_nutzen/d2_aufloesung.mjs, Messreihe „Welche Vergleiche der Überblick trägt"</sub>

---

### DOP-001 · Geprüft und in Ordnung: keine zwei der 145 Objekte sind dieselbe Rechnung

*kein Fehler · Sicherheit hoch · Aufwand klein · `public`*

**Grösse.** **145 Objekte verglichen, kein Zwillingspaar** (Demodaten)

**Was dasteht.** 145 Ansichten, gespeicherte Ansichten und Funktionen, paarweise über ihre normalisierte Definition verglichen — kein Paar ist zeichengleich.

**Was dastehen müsste.** —

**Warum das zählt.** Zwei gleiche Rechnungen laufen auseinander, sobald jemand eine davon anfasst. Dass es keine gibt, ist eine Auskunft und keine Selbstverständlichkeit.

<sub>Nachweis: werkstatt/c_bauwerk/c2_doppelgaenger.mjs</sub>

---

### FORM-003 · 15 Funktionen sind sechs Blöcke oder tiefer geschachtelt

*Reduktion · Sicherheit hoch · Aufwand mittel · `src/pages/NeueArbeit.tsx:24`*

**Grösse.** **15 Funktionen mit Tiefe ≥ 6 von 195** (src/ und test/)

**Was dasteht.** `grenzenVon` in src/pages/NeueArbeit.tsx:24 (360 Zeilen, Tiefe 6); `Arbeit` in src/pages/Arbeit.tsx:36 (273 Zeilen, Tiefe 6); `Linien` in src/components/Diagramm.tsx:100 (259 Zeilen, Tiefe 7); `Messungen` in src/pages/Messungen.tsx:17 (235 Zeilen, Tiefe 6); `DateiKarte` in src/betrieb/AusgangImport.tsx:219 (193 Zeilen, Tiefe 6) und 10 weitere.

**Was dastehen müsste.** Die inneren Blöcke gehören in eigene Funktionen mit sprechendem Namen. Das macht den Code nicht kürzer — es macht ihn lesbar, und darum geht es.

**Warum das zählt.** Ab Tiefe vier hält niemand mehr alle Fälle gleichzeitig im Kopf. Genau dort entstehen die Fehler, die kein Test findet, weil niemand den Fall erdenkt, den der sechste Block behandelt.

**Gegenrede.** Tiefe entsteht auch aus JSX: Ein Bildschirm mit Karte, Tabelle, Zeile und Zelle ist vier Ebenen tief, bevor eine einzige Bedingung darin steht — und das ist kein Mangel, sondern die Form des Dokuments. Der Zähler unterscheidet das nicht. Wer die Liste durchgeht, muss also je Fall entscheiden, ob die Tiefe aus Logik oder aus Auszeichnung kommt.

<sub>Nachweis: werkstatt/c_bauwerk/c1_vermessung.mjs: geschweifte Klammern ausserhalb von Zeichenketten gezählt, je Funktion</sub>

---

### HOLZ-001 · Geprüft und in Ordnung: alle 218 Texte werden irgendwo angezeigt

*kein Fehler · Sicherheit hoch · Aufwand klein · `src/lib/i18n.ts`*

**Grösse.** **218 Textschlüssel, alle mit Abnehmer** (1435 Zeilen geprüft)

**Was dasteht.** `src/lib/i18n.ts` führt 218 Schlüssel in sechs Sprachen, 1435 Zeilen. Kein einziger Schlüssel fehlt im übrigen Quelltext — auch keiner der Schlüssel, die nur mittelbar über Tabellen wie `Record<string, TextId>` abgerufen werden.

**Was dastehen müsste.** —

**Warum das zählt.** Die grösste Datei des Programms ist auch die, in der Totholz am billigsten entsteht: Ein Text, der nicht mehr gebraucht wird, kostet weiterhin sechs Zeilen und wird bei jeder Sprachänderung mitgeschleppt. Dass hier nichts liegt, ist ein Befund und keine Selbstverständlichkeit.

<sub>Nachweis: werkstatt/c_bauwerk/c3_totholz.mjs, Messreihe „Was im Quelltext niemand mehr anspricht"</sub>

---

### HOLZ-002 · 34 Exporte werden von keiner anderen Datei eingeführt

*Reduktion · Sicherheit mittel · Aufwand klein · `src/arbeit/daten.ts`*

**Grösse.** **34 Exporte ohne Abnehmer — sie sparen keine einzige Zeile, sie verkleinern nur die Fläche, auf die der nächste Leser achten muss** (von 232 Exporten insgesamt, bewiesen: tsc und Testsuite grün)

**Was dasteht.** `AusschussZeile` (interface, src/arbeit/daten.ts), `FERTIGE_SOLL` (const, src/arbeit/daten.ts), `WIEGEN_SOLL` (const, src/arbeit/daten.ts), `NaechsteCharge` (interface, src/auswertung/daten.ts), `FaxBeobachtung` (interface, src/auswertung/daten.ts), `AusschussBeobachtung` (interface, src/auswertung/daten.ts), `Selektion` (interface, src/auswertung/daten.ts), `Wiegung` (interface, src/auswertung/daten.ts), `Kaliberzeile` (interface, src/auswertung/daten.ts), `LieferungKurz` (interface, src/auswertung/daten.ts), `Gewichtsstufe` (interface, src/auswertung/daten.ts), `VerarbeitungAlter` (interface, src/auswertung/daten.ts), `AusgangKennzahl` (interface, src/auswertung/daten.ts), `Verlaufswoche` (interface, src/auswertung/daten.ts), `Verlustzeile` (interface, src/auswertung/daten.ts), `KoeffGebinde` (interface, src/auswertung/daten.ts), `KoeffZeile` (interface, src/auswertung/daten.ts), `Schema` (interface, src/auswertung/daten.ts), `auswertungLaden` (function, src/auswertung/daten.ts), `Kaliberklasse` (interface, src/auswertung/daten.ts), `KaliberGruppe` (interface, src/auswertung/daten.ts), `Glockendaten` (interface, src/auswertung/daten.ts), `ZEITRAUM_AB` (const, src/betrieb/AusgangImport.tsx), `JOURNAL_INTERN` (const, src/betrieb/AusgangImport.tsx), `DateinameErgebnis` (interface, src/lib/dateiname.ts), `ChargeRef` (interface, src/lib/import.ts), `RohPalette` (interface, src/lib/import.ts), `fuehrtLokal` (function, src/lib/rolle.ts), `Taetigkeit` (interface, src/lib/taetigkeit.ts), `AuftragStatus` (type, src/lib/typen.ts), `SpaltenName` (type, src/lib/warenausgang.ts), `PFLICHTSPALTEN` (const, src/lib/warenausgang.ts), `KEINE_WARE` (const, src/lib/warenausgang.ts), `Kuerbisurteil` (type, src/lib/warenausgang.ts).

**Was dastehen müsste.** Wo der Name nur in seiner eigenen Datei gebraucht wird, kann `export` weg — dann sieht jeder Leser sofort, dass er nichts anderswo kaputt macht, wenn er ihn ändert. Wo er gar nicht gebraucht wird, kann er ganz weg.

**Warum das zählt.** Ein `export` ist ein Versprechen an den Rest des Programms. Ein Versprechen, das niemand einlöst, macht jede spätere Änderung an dieser Stelle vorsichtiger, als sie sein müsste.

**Gegenrede.** Der Ertrag ist klein und leicht zu überschätzen: **keine einzige Zeile** fällt weg, nur ein Schlüsselwort. Wer daraus eine Reduktion des Codes macht, rechnet sich etwas schön. Und ein Export kann absichtlich dastehen, damit ein künftiger Test ihn greifen kann — dann gehört ein Wort daneben, warum. Der Wert liegt allein darin, dass jeder dieser Namen heute wie eine Zusage an das ganze Programm aussieht und keine ist.

<sub>Nachweis: werkstatt/c_bauwerk/c3_totholz.mjs: Wortsuche über src und test, danach in einer Wegwerfkopie das `export` gestrichen — tsc und Testsuite anschliessend grün</sub>

---

### HOLZ-003 · 8 Klassen im Stylesheet stehen in keinem Element

*Reduktion · Sicherheit niedrig · Aufwand mittel · `src/index.css`*

**Grösse.** **8 Klassen ohne nachweisbaren Träger** (Wortsuche, ohne Beweis)

**Was dasteht.** `.balken-zeile`, `.balken-bereich`, `.stapel-zeile`, `.stapel-spur`, `.stapel-teil`, `.kaliber-spur`, `.dialog-hinter`, `.dialog`.

**Was dastehen müsste.** Vor dem Streichen gegenprüfen — und zwar mit dem Bildschirm-Prüfstand, nicht mit dem Auge: die Seiten vorher und nachher rendern und die Bilder vergleichen. `tsc` sieht kein CSS und kann hier nichts beweisen.

**Warum das zählt.** Ein Stylesheet, in dem die Hälfte nichts tut, verleitet dazu, beim nächsten Umbau eine vorhandene Klasse zu benutzen, die anders aussieht als ihr Name verspricht.

**Gegenrede.** Die Suche kennt keine zusammengesetzten Klassennamen (`className={`karte ${eng ? "schmal" : ""}`}`) und keine, die aus einer Tabelle kommen. Sie überschätzt das Totholz deshalb sicher — darum steht hier „Sicherheit niedrig" und ausdrücklich kein Beweis. Diese Zahl ist eine Suchliste, keine Streichliste.

<sub>Nachweis: werkstatt/c_bauwerk/c3_totholz.mjs: Klassennamen aus den Stylesheets gegen alle .ts/.tsx</sub>

---

### RAND-001 · Geprüft: der Boden von 0.25 kann bei den gemessenen Verdunstungsraten nicht greifen (er läge bei 6.9 Jahren Lagerdauer)

*kein Fehler · Sicherheit hoch · Aufwand klein · `mv_kaskade`*

**Grösse.** **2518 Lagertage bis zum Boden bei der höchsten gemessenen Rate (0.062 % je Tag); die längste Charge liegt 199 Tage** (Demodaten)

**Was dasteht.** Der verkaufsfähige Anteil ist `GREATEST(…, 0.25)`; greift der Boden, ist der Eingang nicht mehr die Rückrechnung, sondern fest das Vierfache des Gelieferten. Gemessen liegen die Verdunstungsraten zwischen 0.046 % und 0.062 % je Tag. Bei der höchsten davon und den übrigen Faktoren der heutigen Saison greift der Boden erst nach 2518 Lagertagen — 6.9 Jahre. Die längste Charge liegt 199 Tage, und der kleinste vorkommende Anteil ist 0.67, also fast das Dreifache des Bodens. In 171 Zeilen hat er kein einziges Mal gegriffen.

**Was dastehen müsste.** —

**Warum das zählt.** Diese Feststellung ist ein Freispruch, und sie steht hier, weil ihr Gegenteil plausibel klang: Eine Formel mit `GREATEST(…, 0.25)` sieht nach einer Notbremse aus, und eine Notbremse, die anspricht, macht aus einer Schätzung eine feste Zahl. Die erste Fassung dieses Werkzeugs hat daraus eine Warnung geschrieben — anhand eines Gitters, dessen niedrigste Rate noch zwanzigmal über der gemessenen lag. Wer die Grösse einer Kante angibt, muss sagen, ob jemand an sie herankommt.

**Gegenrede.** Zwei Vorbehalte. **Erstens** hängt der Abstand an den gemessenen Raten, und die stammen aus 41 verwendbaren Wägungen über vierzehn Sorten — eine Sorte mit deutlich höherer Rate ist nicht ausgeschlossen, nur nicht gemessen. Bei 1 % je Tag läge die Kante bei 116 Tagen, also innerhalb einer Saison. **Zweitens** ist der Boden nicht folgenlos, nur nicht auf dem Weg, für den er gebaut wurde: Er fängt den negativen Faktor aus der Feststellung darunter ab und macht ihn unsichtbar.

<sub>Nachweis: werkstatt/a_rechenwerk/a7_raender.mjs: Ausdruck mit `pg_get_viewdef` aus `mv_kaskade` geholt, über 210 Gitterpunkte gerechnet und gegen die tatsächlich vorkommenden Raten gehalten</sub>

---

### RAND-002 · Geprüft und in Ordnung: „zu klein" und „zu gross" werden vor der Formel auf zusammen 1 normiert

*kein Fehler · Sicherheit hoch · Aufwand klein · `mv_kaskade`*

**Grösse.** **70 Gitterpunkte mit roher Summe über 100 %, keiner davon ergibt einen negativen Faktor** (Gitter)

**Was dasteht.** In `koeff` wird jeder der beiden Anteile für sich auf [0, 1] geklemmt — das allein liesse ihre Summe über 1 gehen, und der Faktor `(1 - a_klein_n - a_gross_n)` würde negativ. Eine Stufe später steht aber

    CROSS JOIN LATERAL (SELECT GREATEST(a_klein + a_gross, 1) AS f) n
    a_klein / n.f AS a_klein_n,  a_gross / n.f AS a_gross_n

Die Summe wird also auf höchstens 1 normiert, bevor sie in die Formel geht. Über das ganze Gitter — darunter 70 Punkte mit rohen Anteilen von zusammen bis zu 200 % — ist der Faktor nie negativ; der kleinste Wert ohne Boden ist 0.00e+0.

**Was dastehen müsste.** —

**Warum das zählt.** Diese Feststellung steht hier, weil ihr Gegenteil in der ersten Fassung dieses Werkzeugs als Befund geschrieben war, mit Grösse und Gegenrede. Der Grund war eine Zeile Nachbau: Das Gitter hat `a_klein_n` — die **normierte** Grösse — mit rohen Anteilen von 70 % und 60 % gefüttert, also der Formel eine Eingabe gegeben, die sie in der Sicht nie bekommt. Wer eine Formel für sich rechnet, muss sie mit dem füttern, was wirklich in sie hineingeht; sonst prüft er seinen eigenen Nachbau. Seither vergleicht dieses Werkzeug zuerst an vierzig echten Zeilen der laufenden Sicht, ob sein Nachbau dieselben Zahlen ergibt, und bricht ab, wenn nicht.

<sub>Nachweis: werkstatt/a_rechenwerk/a7_raender.mjs: Normierer mit `pg_get_viewdef` aus `mv_kaskade` geholt und im Gitter angewandt; Abgleich an 40 echten Zeilen, grösste Abweichung 1.1e-16</sub>

---

### RAND-003 · Geprüft und in Ordnung: über 210 Randwerte bleibt die Kaskade im Rahmen

*kein Fehler · Sicherheit hoch · Aufwand klein · `mv_kaskade`*

**Grösse.** **210 Gitterpunkte geprüft, keine Zusicherung verletzt** (Gitter)

**Was dasteht.** 210 Gitterpunkte von 0 bis 800 Lagertagen, Raten von 0 bis 5 % je Tag und Ausschussanteilen bis 100 %: Der verkaufsfähige Anteil bleibt überall in (0, 1], kein Zwischenwert wird NaN oder unendlich, und mehr Lagertage ergeben nie weniger Verdunstung. Was der Boden bei 0.25 abfängt, steht in den beiden Feststellungen darüber — hier geht es um die Zusicherungen, die auch mit Boden gelten müssen.

**Was dastehen müsste.** —

**Warum das zählt.** Diese drei Eigenschaften sind das, worauf sich jede Zahl darüber stützt. Bricht eine, ist nicht eine Zeile falsch, sondern jede, die durch dieselbe Formel läuft.

<sub>Nachweis: werkstatt/a_rechenwerk/a7_raender.mjs: 210 Gitterpunkte, Formel aus `pg_get_viewdef('mv_kaskade')`</sub>

---

### RECHT-001 · Geprüft und in Ordnung: alle 63 Sichten geben die Zeilenregeln weiter

*kein Fehler · Sicherheit hoch · Aufwand klein · `public`*

**Grösse.** **63 Sichten geprüft, keine ohne die Klausel** (Demodaten)

**Was dasteht.** Jede der 63 Sichten steht mit `security_invoker = true` da; beim Lesen durch sie gilt für jede Zeile, was für den gilt, der fragt.

**Was dastehen müsste.** —

**Warum das zählt.** Ohne die Klausel läuft eine Sicht mit den Rechten ihres Eigentümers, und die Zeilenregeln der Tabellen darunter gelten nicht mehr — lautlos.

<sub>Nachweis: werkstatt/b_fundament/b3_rechte.mjs: `pg_class.reloptions` aller Sichten</sub>

---

### RECHT-002 · Jeder Angemeldete darf alle 38 Auswertungstabellen lesen — auch der Zähler

*Frage an den Betrieb · Sicherheit hoch · Aufwand klein · `erg_*, mv_*`*

**Grösse.** **38 gespeicherte Ansichten, die jeder Angemeldete lesen darf (von 38)** (Katalog)

**Was dasteht.** 38 gespeicherte Ansichten (`erg_…`, `mv_…`) haben ein Leserecht für `authenticated`. Darin stehen Verlustquoten je Sorte, Margen je Käufer, Durchsatz je Arbeiter. Die Oberfläche zeigt diese Seiten nur dem Betriebsleiter (`istAdmin` in `src/App.tsx`), aber PostgREST kennt diese Grenze nicht — wer die Adresse und einen gültigen Anmeldeschlüssel hat, liest sie direkt. Gespeicherte Ansichten kennen zudem keine Zeilenregeln: Für sie gibt es `security_invoker` gar nicht.

**Was dastehen müsste.** Das ist keine Entscheidung des Programmierers. Entweder ist es gewollt — dann gehört der Satz „jeder Angemeldete kann alle Auswertungen sehen" in ABLAUF.md, damit niemand etwas anderes annimmt. Oder es ist nicht gewollt — dann tritt an die Stelle des `grant` an `authenticated` ein `grant` an eine Betriebsleiterrolle, und die Oberfläche ändert sich nicht, weil sie diese Seiten ohnehin nur ihm zeigt.

**Warum das zählt.** Der Betrieb beschäftigt Saisonkräfte. Ob eine davon die Marge je Käufer und den Durchsatz je Kollege sehen kann, ist eine Frage über den Betrieb, nicht über die Datenbank — und sie ist bisher nirgends beantwortet, sondern nur beiläufig entschieden.

**Gegenrede.** Ein Arbeiter braucht einen Anmeldeschlüssel und muss wissen, dass es PostgREST gibt — das ist kein Angriff, den man versehentlich ausführt. Und ein Teil dieser Tabellen ist für die Arbeiter-App nötig (Kaliberbänder, Gebindegewichte), lässt sich also nicht einfach wegnehmen. Wer hier etwas ändert, muss Tabelle für Tabelle entscheiden und die Arbeiter-App gegenprüfen — sonst steht der Zähler am Montag vor einer leeren Maske.

<sub>Nachweis: werkstatt/b_fundament/b3_rechte.mjs: `information_schema.role_table_grants` für `authenticated` über alle gespeicherten Ansichten</sub>

---

### STU-002 · Geprüft: alle 10 Sonden des Prüfwerks sind noch scharf

*kein Fehler · Sicherheit hoch · Aufwand klein · `pruefwerk/sonden`*

**Grösse.** **10 von 10 Sonden belegen ihre Schärfe** (Selbstprobe je Sonde)

**Was dasteht.** Jede der 10 Sonden bekommt einen Fall vorgesetzt, in dem sie anschlagen muss, und findet ihn. Ihr Schweigen im echten Lauf ist damit eine Aussage und nicht bloss Abwesenheit. Das war in Runde L nicht so: Die Mutationssonde zeigte auf Formeln, die zwei Migrationen später anders hiessen, änderte nichts mehr und meldete pflichtgemäss „keine überlebende Mutation".

**Was dastehen müsste.** —

**Warum das zählt.** Der Unterschied zwischen „hier ist nichts" und „ich sehe nichts mehr" ist der Unterschied zwischen einem Prüfwerk und einem Ritual. Er ist von aussen unsichtbar, und nur die Selbstprobe macht ihn sichtbar.

<sub>Nachweis: werkstatt/phase0/p0_stumpfheit.mjs: die Selbstprobe jeder Sonde ausgeführt</sub>

---

### TOT-002 · Geprüft und in Ordnung: jede Ansicht, jede Funktion und jede Tabelle hat einen Leser

*kein Fehler · Sicherheit hoch · Aufwand keiner · `alle Ansichten, Funktionen und Tabellen`*

**Grösse.** **173 Objekte, alle mit Leser** (vollständiger Nutzungsgraph der Datenbank)

**Was dasteht.** 63 Ansichten, 38 gespeicherte Ansichten, 44 Funktionen und 28 Tabellen — jedes einzelne wird angesprochen: von der Oberfläche, einer Prüfung, einem Prüfstand, einem Auslöser, einer Zugriffsregel, einer Prüfbedingung oder einer anderen Ansicht. 8 Ansichten und 3 Funktionen werden **nur mittelbar** gelesen — sie sind Zwischenstufen der Kette, kein Ballast.

**Was dastehen müsste.** So.

**Warum das zählt.** Nach zwölf Runden Anbau, in denen fast jede Migration Formeln neu geschrieben hat, ist das nicht selbstverständlich. Es gehört gemessen und aufgeschrieben, damit die nächste Runde nicht dieselbe Frage noch einmal stellt.

<sub>Nachweis: werkstatt/b_fundament/b1_totes.mjs → Nutzungsgraph aus pg_depend (Sicht→Tabelle und Sicht→Funktion), Auslöser aller Schemata, Zugriffsregeln, Prüfbedingungen, Vorgabewerte, dazu die Quelltextsuche über Oberfläche, Prüfungen, Prüfstände und Prüfwerk</sub>

---

### VHT-001 · Geprüft: die Division durch einen geschätzten Nenner verzerrt um 19 kg (0.006 %) — zu wenig, um etwas zu ändern

*kein Fehler · Sicherheit hoch · Aufwand klein · `mv_kaskade`*

**Grösse.** **19 kg zu viel geschätzter Eingang (0.006 % von 327 t)** (171 Kohortenzeilen, Demodaten)

**Was dasteht.** `m0 = geliefert_kg / verkaufsfaehig_anteil` teilt eine gewogene Zahl durch eine geschätzte. Weil `1/x` konvex ist, liegt der Erwartungswert des Quotienten über dem Quotienten der Erwartungswerte. Gerechnet über alle 171 Kohortenzeilen: 19 kg auf 327447 kg geschätzten Eingang, also 0.006 %. Am stärksten betroffen ist `Lekor` mit 4.9 kg — Wiegungen aller Sorten (zu wenige eigene Chargen).

**Was dastehen müsste.** — nichts. Die Zahl steht hier, weil „vernachlässigbar" eine Behauptung ist, solange niemand sie ausgerechnet hat. Jetzt ist sie ausgerechnet.

**Warum das zählt.** Der Unterschied zu einem gewöhnlichen Messfehler ist die Richtung. Ein zufälliger Fehler mittelt sich über 171 Kohorten weg; dieser nicht — er zeigt in jeder Zeile nach oben und addiert sich. Ein zu grosser Eingang bedeutet ausserdem einen zu grossen Verlust, denn der Verlust ist die Differenz zum Ausgang.

<sub>Nachweis: werkstatt/a_rechenwerk/a3_verhaeltnis.mjs: Log-Varianz je Zeile aus den Koeffizientenbändern, `exp(s²) − 1`; die Formel gegen 20 000 gezogene Nenner geprüft</sub>

---

### VHT-002 · Geprüft und in Ordnung: der Boden von 0.25 unter dem verkaufsfähigen Anteil greift nie

*kein Fehler · Sicherheit hoch · Aufwand klein · `mv_kaskade`*

**Grösse.** **0 Kohortenzeilen auf dem Boden (von 171)** (Demodaten)

**Was dasteht.** Die Kaskade legt mit `GREATEST(…, 0.25)` einen Boden unter den verkaufsfähigen Anteil, damit die Division nicht davonläuft. Ein Boden, der greift, macht aus der Schätzung eine Schranke. Gemessen über alle Kohortenzeilen: 0 liegen darauf. Der kleinste vorkommende Anteil ist 0.6700, der grösste 0.8841.

**Was dastehen müsste.** —

**Warum das zählt.** Ein Boden ist eine stille Annahme: „schlimmer als das wird es nicht". Greift er, steht auf dem Bildschirm eine Zahl, die nicht aus den Daten kommt, sondern aus dieser Annahme — und nichts sagt es. Dass er heute nie greift, ist deshalb eine Auskunft, die in den Bericht gehört.

<sub>Nachweis: werkstatt/a_rechenwerk/a3_verhaeltnis.mjs</sub>

---

### ZEIT-001 · Geprüft und in Ordnung: die Lagertage entstehen aus zwei Kalendertagen derselben Zone

*kein Fehler · Sicherheit hoch · Aufwand klein · `v_verdunstung_messung` · Spalte `lagertage`*

**Grösse.** **0 kg Unterschied im Saisonverlust zwischen UTC und Europe/Zurich (0 Lagertag verschoben)** (Demosaison in beiden Zonen gerechnet)

**Was dasteht.** `lagertage = betriebstag(wiege_ts) − eingangsdatum`. Links ein Zeitpunkt, ausdrücklich in der Betriebszone auf einen Kalendertag gebracht; rechts der Kalendertag vom Palettenzettel. Nachgerechnet an derselben Demosaison in beiden Zeitzonen: 0 Lagertag verschiebt sich, 0.00 kg Unterschied im Saisonverlust. Die Zone steht als Einstellung `zeitzone` in der Datenbank, mit Rückfall auf `Europe/Zurich` — sie hängt nicht mehr an der Sitzung.

**Was dastehen müsste.** —

**Warum das zählt.** Die Rate geht potenziert in jede Verdunstungszahl ein: Ein Lagertag Unterschied verschiebt sie im Median um 1.2 %, bei der kürzesten Lagerdauer der Demosaison um 14.4 %. Dass hier nichts mehr zu holen ist, ist deshalb eine Auskunft und keine Selbstverständlichkeit — vor 0067 waren es 19.68 kg.

**Gegenrede.** `mv_auftrag_masse` enthält dieselbe Verwechslung weiterhin — sie ist eine gespeicherte Sicht, und `drop materialized view … cascade` nimmt 51 Objekte mit. Nachgemessen: 5 von 309 Arbeiten haben einen Startzeitpunkt, dessen UTC-Tag und Schweizer Tag auseinanderfallen; in der Betriebszone neu gefüllt ergibt die Rechnung dieselben vier Zahlen bis auf den Rappen. Der Freispruch gilt also der Verdunstungsmessung, nicht der ganzen Datenbank.

<sub>Nachweis: werkstatt/b_fundament/b5_zeit.mjs: `pg_get_viewdef('v_verdunstung_messung')` auf einen eigenen Guss von `wiege_ts` durchsucht; dazu dieselbe Datenbank in zwei Zeitzonen gerechnet</sub>


## Messreihen

Zahlen, die für sich kein Mangel sind, aber die Grundlage der Feststellungen darüber —
und die Antwort auf die Frage, wie weit nachgesehen wurde.

### Die zehn Sonden des Prüfwerks an ihrem eingebauten Fehler

Jede Sonde bekommt einen Fall vorgesetzt, in dem sie anschlagen *muss*. Steht dort „ok", hat sie ihren eigenen eingebauten Fehler gefunden und ihr Schweigen im echten Lauf ist eine Aussage. Steht dort „STUMPF", ist es keine.

| Sonde | Selbstprobe |
|---|---|
| 01_herkunft | ok |
| 02_bezugsgroessen | ok |
| 03_erfassung | ok |
| 04_orakel | ok |
| 05_metamorph | ok |
| 06_mutation | ok |
| 07_szenarien | ok |
| 08_leer_nicht_null | ok |
| 09_einheiten | ok |
| 10_annahmen | ok |

---

### Können die Prüfstände überhaupt scheitern?

Ein Prüfstand, dessen Quelltext keinen einzigen Weg zu einem Rückgabewert ungleich null kennt, kann niemandem etwas melden — er mag „✗" auf den Bildschirm schreiben, aber in einer Kette wie `run.sh && kette && bildschirme` geht er stillschweigend durch. Die letzte Spalte ist die härtere Prüfung: ein Fehler wurde wirklich hineingelegt und der Prüfstand darauf losgelassen.

| Prüfstand | wofür | Rückgabewerte im Quelltext | kann scheitern | am hineingelegten Fehler |
|---|---|---|---|---|
| pruefstand/kette.mjs | Kette: Maske → Datenbank → Auswertung | 1 | ja | STUMPF (eine Kaskadenformel, die ein anderes Ergebnis liefert) |
| pruefstand/bildschirme.mjs | Bildschirme rendern, Konsolenfehler, Überlauf | 1 | ja | in dieser Runde nicht gelegt |
| pruefstand/beschriftung.mjs | Begriffe: sagt jede Zahl, was sie ist? | 0, 1 | ja | in dieser Runde nicht gelegt |
| pruefstand/luecken.sh | Lücken zwischen Masken und Auswertung | 1 · `set -e` (jeder Fehler bricht ab) | ja | ok (eine Erfassungsspalte, die keine Maske schreibt) |
| pruefstand/kette_pruefen.sh | Kette gegen die mitgeschnittenen Anfragen | `set -e` (jeder Fehler bricht ab) | ja | in dieser Runde nicht gelegt |
| pruefstand/demo_bauen.sh | Demodaten neu bauen | `set -e` (jeder Fehler bricht ab) | ja | in dieser Runde nicht gelegt |
| supabase/test/run.sh | Datenbanksuite in sieben Stufen | 1 · `set -e` (jeder Fehler bricht ab) | ja | in dieser Runde nicht gelegt |

---

### Güte jedes Koeffizienten über die Stichprobengrösse

20 erfundene Saisons je Stichprobengrösse, alle Grössen sehen dieselben Welten (paarweiser Aufbau). Verzerrung ist der mittlere relative Fehler — 0 heisst unverzerrt. Überdeckung ist der Anteil der Läufe, in denen der wahre Wert im ausgewiesenen 95-%-Band lag; sie sollte bei 95 % liegen.

| Koeffizient | Wägungen je Saison | Läufe | Verzerrung % | Streuung % | Überdeckung | ohne Schätzung |
|---|---|---|---|---|---|---|
| Verdunstungsrate r | 1 | 20 | -1.77 | 21.41 | 0 % | 0 |
| Verdunstungsrate r | 2 | 20 | -8.33 | 12.98 | 90 % | 0 |
| Verdunstungsrate r | 3 | 20 | -0.88 | 10.42 | 90 % | 0 |
| Verdunstungsrate r | 5 | 20 | -5.04 | 9.84 | 100 % | 0 |
| Verdunstungsrate r | 10 | 20 | -2.79 | 10.51 | 85 % | 0 |
| Verdunstungsrate r | 30 | 20 | -3.79 | 8.38 | 90 % | 0 |
| Verderbskurve bei 120 Tagen | 1 | 0 | — | — | — | — |
| Verderbskurve bei 120 Tagen | 2 | 0 | — | — | — | — |
| Verderbskurve bei 120 Tagen | 3 | 0 | — | — | — | — |
| Verderbskurve bei 120 Tagen | 5 | 0 | — | — | — | — |
| Verderbskurve bei 120 Tagen | 10 | 0 | — | — | — | — |
| Verderbskurve bei 120 Tagen | 30 | 0 | — | — | — | — |
| Anteil zu klein | 1 | 20 | 0.15 | 0.53 | 100 % | 0 |
| Anteil zu klein | 2 | 20 | 0.01 | 0.47 | 100 % | 0 |
| Anteil zu klein | 3 | 20 | 0.13 | 0.28 | 100 % | 0 |
| Anteil zu klein | 5 | 20 | 0.07 | 0.28 | 100 % | 0 |
| Anteil zu klein | 10 | 20 | 0.12 | 0.31 | 95 % | 0 |
| Anteil zu klein | 30 | 20 | 0.08 | 0.17 | 100 % | 0 |
| Anteil zu gross | 1 | 20 | 0.14 | 0.66 | 90 % | 0 |
| Anteil zu gross | 2 | 20 | -0.03 | 0.36 | 95 % | 0 |
| Anteil zu gross | 3 | 20 | 0.06 | 0.36 | 100 % | 0 |
| Anteil zu gross | 5 | 20 | 0.11 | 0.4 | 100 % | 0 |
| Anteil zu gross | 10 | 20 | 0.1 | 0.31 | 100 % | 0 |
| Anteil zu gross | 30 | 20 | 0.11 | 0.2 | 100 % | 0 |
| Sockel a₀ | 1 | 0 | — | — | — | — |
| Sockel a₀ | 2 | 0 | — | — | — | — |
| Sockel a₀ | 3 | 0 | — | — | — | — |
| Sockel a₀ | 5 | 0 | — | — | — | — |
| Sockel a₀ | 10 | 0 | — | — | — | — |
| Sockel a₀ | 30 | 0 | — | — | — | — |

---

### Die einseitige Verzerrung der geschätzten Eingangsmasse, je Sorte

Die Eingangsmasse entsteht als `geliefert ÷ verkaufsfähiger Anteil`. Weil der Nenner geschätzt ist und `1/x` sich krümmt, ist das Ergebnis im Mittel zu gross — nach Jensen, und zwar immer in dieselbe Richtung. Die Spalte „Streuung von ln(Anteil)" ist die Wurzel aus der Summe der fünf Koeffizientenbeiträge, jeder mit seiner Ableitung gewichtet; „Verzerrung" ist `exp(s²) − 1`. Die letzte Spalte zeigt, woran es liegt: Sorten mit geliehener Rate haben ein weiteres Band und damit eine grössere Verzerrung.

| Sorte | Kohorten | geschätzter Eingang (kg) | Streuung von ln(Anteil) | Verzerrung | zu viel (kg) | woher die Verdunstungsrate kommt |
|---|---|---|---|---|---|---|
| Lekor | 6 | 9881 | 0.0224 | 0.050 % | 4.9 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Amoro | 14 | 15818 | 0.0173 | 0.030 % | 4.7 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Mieluna | 11 | 24898 | 0.0111 | 0.012 % | 3.1 | Wiegungen dieser Sorte |
| Butterkin | 26 | 52627 | 0.0067 | 0.005 % | 2.3 | Wiegungen dieser Sorte |
| Tiana | 62 | 155999 | 0.0028 | 0.001 % | 1.3 | Wiegungen dieser Sorte |
| Kaori Kuri | 32 | 41182 | 0.0052 | 0.003 % | 1.0 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Orange Summer | 10 | 15276 | 0.0078 | 0.006 % | 0.9 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Orangita | 4 | 5534 | 0.0089 | 0.008 % | 0.4 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Ker Madec | 4 | 3657 | 0.0075 | 0.006 % | 0.2 | Wiegungen aller Sorten (zu wenige eigene Chargen) |
| Fictor | 2 | 2575 | 0.0071 | 0.005 % | 0.1 | Wiegungen aller Sorten (zu wenige eigene Chargen) |

---

### Freiheitsgrade der Verlustbänder: Minimum gegen Satterthwaite

Die Zeilen sind die sechs Ströme der Gesamtsaison. Die Varianz wird bis auf die einzelne Sorte zerlegt — je Sorte ein Bestandteil mit ihrem eigenen Freiheitsgrad, dazu der gepoolte Anteil und das Schimmelmodell. „df heute" ist das Minimum über alles, so wie `v_verlust_je_gruppe` es bildet; „df nach Satterthwaite" gewichtet jeden Freiheitsgrad mit dem Quadrat seines Varianzanteils. Die Spalte ganz rechts nennt den Bestandteil, der die Varianz trägt — er ist fast nie derselbe, der den Freiheitsgrad setzt. Die Varianzen stammen aus der laufenden Sicht, und ihre Summe wurde auf jeder Zeile gegen die veröffentlichte Streuung geprüft.

| Verlustursache | Wert (kg) | Streuung (kg) | Bestandteile | df heute (Minimum) | df nach Satterthwaite | t heute | t richtig | Band heute (± kg) | Band richtig (± kg) | grösster Bestandteil |
|---|---|---|---|---|---|---|---|---|---|---|
| Schimmel/Fäulnis | 26265 | 1286.2 | 5 | 1 | 32.0 | 12.706 | 1.960 | 16343 | 2521 | Schimmelmodell (100 %, df 32) |
| Verdunstung | 23610 | 365.3 | 4 | 1 | 21.7 | 12.706 | 2.074 | 4642 | 758 | Verdunstung, gepoolter Anteil (60 %, df 14) |
| Nebenkanal zu gross | 4787 | 227.2 | 13 | 1 | 33.5 | 12.706 | 1.960 | 2887 | 445 | Ausschuss/Fax/Nebenkanal, Amoro (34 %, df 16) |
| Zu klein (Tierfutter) | 7344 | 190.7 | 14 | 1 | 14.9 | 12.706 | 2.131 | 2423 | 406 | Ausschuss/Fax/Nebenkanal, Tiana (52 %, df 5) |
| Faul beim Abpacken (Fax) | 2426 | 56.8 | 14 | 1 | 38.4 | 12.706 | 1.960 | 722 | 111 | Ausschuss/Fax/Nebenkanal, Kaori Kuri (31 %, df 9) |

---

### Ab wann der Boden von 0.25 die Rechnung übernimmt

Der verkaufsfähige Anteil ist `GREATEST(…, 0.25)`; aus ihm entsteht der Eingang als `geliefert ÷ Anteil`. Solange der Boden nicht greift, ist das die Rückrechnung. Greift er, ist es keine Rückrechnung mehr, sondern eine feste Zahl: Der Eingang ist dann genau das Vierfache des Gelieferten, unabhängig davon, wie lange die Ware wirklich lag. Die Tabelle sagt, wie weit dieser Punkt entfernt ist. Gerechnet mit den übrigen Faktoren der heutigen Saison (Sockel 2 %, Schimmel 5 %, klein+gross 13.4 %, Fax 1 %). Die längste Charge liegt heute 199 Tage, und die gemessenen Raten liegen zwischen 0.046 % und 0.062 % je Tag. Die Spalte „kommt in den Daten vor" trennt das Beobachtete vom Durchgerechneten — ohne sie liest man die Zeile mit der höchsten Rate als Warnung, obwohl sie eine Rechenübung ist.

| Verdunstungsrate je Tag | kommt in den Daten vor | Boden greift ab | Abstand zur längsten Charge heute | Was der Eingang dann wäre |
|---|---|---|---|---|
| 0.046 % | ja | 2518 Tagen | 2319 Tage | 4 × geliefert, fest |
| 0.062 % | ja | 1881 Tagen | 1682 Tage | 4 × geliefert, fest |
| 0.100 % | nein | 1161 Tagen | 962 Tage | 4 × geliefert, fest |
| 0.500 % | nein | 232 Tagen | 33 Tage | 4 × geliefert, fest |
| 1.000 % | nein | 116 Tagen | -83 Tage | 4 × geliefert, fest |
| 2.000 % | nein | 58 Tagen | -141 Tage | 4 × geliefert, fest |
| 5.000 % | nein | 23 Tagen | -176 Tage | 4 × geliefert, fest |

---

### Der verkaufsfähige Anteil über ein Gitter aus Randwerten

210 Punkte, gerechnet mit der Formel, die `pg_get_viewdef` aus `mv_kaskade` zurückgibt — nicht mit einer nachgebauten. Gezeigt sind die Punkte, an denen der Boden greift oder der Anteil ohne ihn negativ würde; das sind die Stellen, an denen die Formel etwas anderes tut, als sie soll.

| Rate | Tage | zu klein + zu gross | Anteil mit Boden | ohne Boden | Eingang je 1000 kg geliefert |
|---|---|---|---|---|---|
| 0.0 % | 0 | 100 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 0 | 130 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 0 | 200 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 1 | 100 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 1 | 130 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 1 | 200 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 30 | 100 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 30 | 130 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 30 | 200 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 100 | 100 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 100 | 130 % | 0.2500 | 0.00e+0 | 4000 kg |
| 0.0 % | 100 | 200 % | 0.2500 | 0.00e+0 | 4000 kg |

---

### Objekte der Datenbank und wer sie liest

Vorsichtig gezählt: Ein Name, der irgendwo im Quelltext vorkommt — auch nur in einem Kommentar —, gilt als gelesen. Die Spalte „liest niemand" ist damit eine **untere** Schranke; in Wirklichkeit ist mehr tot.

| Art | gesamt | von aussen angesprochen | nur intern gelesen | liest niemand |
|---|---|---|---|---|
| Ansichten | 63 | 57 | 6 | 0 |
| gespeicherte Ansichten | 38 | 36 | 2 | 0 |
| Funktionen | 44 | 41 | 3 | 0 |
| Tabellen | 28 | 28 | 0 | 0 |

---

### Indexe nach einem vollständigen Arbeitstag

Auf einer Kopie der Datenbank wurde die Statistik zurückgesetzt, dann die ganze Auswertung neu gerechnet, dann 35 Ansichten geladen — genau die, die die App lädt — und sieben gezielte Abfragen gestellt, wie ein Arbeiter sie auslöst. Erst danach wurde abgelesen. Primärschlüssel und eindeutige Indexe bleiben auch bei null Zugriffen: Sie halten eine Bedingung, nicht eine Abfrage.

| Index | Tabelle | Zugriffe | Bytes | Art |
|---|---|---|---|---|
| sortier_gewicht_pkey | sortier_gewicht | 0 | 196608 | Primärschlüssel |
| auftrag_palette_pkey | auftrag_palette | 0 | 49152 | Primärschlüssel |
| palette_extern_id_key | palette | 0 | 49152 | eindeutig |
| erg_verlauf_pk | erg_verlauf | 0 | 40960 | eindeutig |
| auftrag_teilnehmer_aktiv | auftrag_teilnehmer | 0 | 40960 | eindeutig |
| palette_pkey | palette | 0 | 40960 | Primärschlüssel |
| erg_gewichte_sorte | erg_gewichte | 0 | 32768 | Suchindex |
| auftrag_teilnehmer_pkey | auftrag_teilnehmer | 0 | 32768 | Primärschlüssel |
| auftrag_charge_nr_start_ts_idx | auftrag | 0 | 32768 | Suchindex |
| mv_hochrechnung_charge | mv_hochrechnung | 0 | 32768 | Suchindex |
| sortier_lauf_auftrag | sortier_lauf | 0 | 16384 | Suchindex |
| mv_schimmel_punkte_charge | mv_schimmel_punkte | 0 | 16384 | Suchindex |
| mv_schimmel_punkte_quelle | mv_schimmel_punkte | 0 | 16384 | Suchindex |
| erg_verlauf_woche | erg_verlauf | 0 | 16384 | Suchindex |
| ausschuss_messung_auftrag_id_art_idx | ausschuss_messung | 0 | 16384 | Suchindex |
| sortier_lauf_roh_pruefsumme_key | sortier_lauf | 0 | 16384 | eindeutig |
| sortier_lauf_zuordnung_idx | sortier_lauf | 0 | 16384 | Suchindex |
| mv_sortier_lauf_masse_pk | mv_sortier_lauf_masse | 0 | 16384 | eindeutig |
| mv_sortier_lauf_masse_charge | mv_sortier_lauf_masse | 0 | 16384 | Suchindex |
| mv_auftrag_masse_charge | mv_auftrag_masse | 0 | 16384 | Suchindex |
| mv_auftrag_masse_station | mv_auftrag_masse | 0 | 16384 | Suchindex |
| erg_punkte_charge | erg_punkte | 0 | 16384 | Suchindex |
| verdunstung_auftrag | verdunstung_wiegung | 0 | 16384 | Suchindex |
| lieferung_sorte | lieferung | 0 | 16384 | Suchindex |
| auftrag_angabe_pkey | auftrag_angabe | 0 | 16384 | Primärschlüssel |
| auftrag_gebinde_pkey | auftrag_gebinde | 0 | 16384 | Primärschlüssel |
| ausgang_zeile_eindeutig | ausgang_zeile | 0 | 16384 | eindeutig |
| mv_kaliber_pk | mv_kaliber_verteilung | 0 | 16384 | eindeutig |
| kaeufer_pkey | kaeufer | 0 | 16384 | Primärschlüssel |
| sortierschema_suche | sortierschema | 0 | 16384 | Suchindex |
| charge_vorlauf_pkey | charge_vorlauf | 0 | 16384 | Primärschlüssel |
| ausgang_quelle_pkey | ausgang_quelle | 0 | 16384 | Primärschlüssel |
| lieferung_import_quelle | lieferung_import | 0 | 16384 | Suchindex |
| ausgang_zeile_artikel | ausgang_zeile | 0 | 16384 | Suchindex |
| ausgang_zeile_charge | ausgang_zeile | 0 | 16384 | Suchindex |
| ausgang_artikel_pkey | ausgang_artikel | 0 | 16384 | Primärschlüssel |
| lieferung_import_extern_id_key | lieferung_import | 0 | 16384 | eindeutig |
| erg_ueberfuellung_gruppe | erg_ueberfuellung | 0 | 16384 | Suchindex |
| charge_schlag_sorte_saison_key | charge | 0 | 16384 | eindeutig |
| charge_perigon | charge | 0 | 16384 | Suchindex |

---

### Die drei Schichten der Rechte

Gelesen aus dem Katalog der laufenden Datenbank, nicht aus den Migrationen — was am Ende gilt, steht dort und nirgends sonst.

| Schicht | Insgesamt | Wie erwartet | Anders | Was „anders" bedeutet |
|---|---|---|---|---|
| Tabellen mit Zeilenregeln | 28 | 28 | 0 | jede Tabelle hat Regeln |
| Sichten mit `security_invoker` | 63 | 63 | 0 | jede Sicht gibt die Frage an die Zeilenregeln weiter |
| Funktionen mit Eigentümerrechten | 12 | 12 | 0 | jede setzt ihren `search_path` fest |

---

### Was eine doppelt erfasste Zeile in Kilogramm bewegt

Auf einer Kopie der Demodatenbank wurde je Tabelle die **schwerste** vorhandene Zeile wortgleich ein zweites Mal angelegt und die ganze Auswertung neu gerechnet. Die Spalte „Verschiebung" ist der grösste Unterschied in der Saisonbilanz — also der schlimmste Fall eines einzelnen Tippfehlers, nicht der durchschnittliche. Zu lesen ist die Tabelle als Preisschild, nicht als Verbotsliste: eine zweite Wägung derselben Palette ist ausdrücklich erlaubt und erwünscht. Zeilen mit „nicht prüfbar" stehen hier, weil das Weglassen einer Zeile aus einer Messtabelle wie ein Ergebnis aussähe.

| Tabelle | Wenn zweimal erfasst wird | Verschiebung (kg) | welche Zahlen sich bewegen | eindeutiger Schlüssel | von der Plausibilitätssicht gemeldet |
|---|---|---|---|---|---|
| verdunstung_wiegung | dieselbe Palette am selben Tag noch einmal gewogen | 203.87 | verlust_heute, verdunstung_heute, schimmel_heute, im_haus_heute | keiner | nein |
| schimmel_messung (als Kistengewicht) | dieselbe Schimmelmenge zweimal am Auftrag erfasst | 17.21 | verlust_heute, verdunstung_heute, schimmel_heute, im_haus_heute | keiner | nein |
| schimmel_messung (als Palox-Ablesung) | dieselbe Schimmelmenge zweimal am Auftrag erfasst | 0.00 | keine | keiner | nein |
| ausschuss_messung | dieselbe Ausschusskiste zweimal am Auftrag erfasst | 99.13 | verlust_heute, verdunstung_heute, schimmel_heute, im_haus_heute | keiner | nein |
| ausgang_wiegung | dieselbe fertige Palette zweimal gewogen | 0.96 | ausgang, verlust_heute, verdunstung_heute, schimmel_heute, im_haus_heute | keiner | nein |
| lieferung | derselbe Lieferschein zweimal abgetippt | 1888.14 | ausgang, verlust_heute, verdunstung_heute, schimmel_heute, im_haus_heute | keiner | nein |
| auftrag_palette (mit Zettelgewicht) | dieselbe Eingangspalette zweimal am Auftrag gezählt | 23.14 | verlust_heute, verdunstung_heute, schimmel_heute, im_haus_heute | keiner | nein |
| auftrag_palette (nur gezählt) | dieselbe Eingangspalette zweimal am Auftrag gezählt | 5.62 | verlust_heute, verdunstung_heute, schimmel_heute, im_haus_heute | keiner | nein |

---

### Wo aus einem Zeitpunkt ein Kalendertag wird

Jede dieser Stellen wandelt einen absoluten Augenblick in einen Kalendertag um — oder umgekehrt. Das Ergebnis hängt an einer Zeitzone. Genannt wird sie an keiner einzigen.

| Ort | Art | Stelle | Sorte |
|---|---|---|---|
| mv_auftrag_masse | gespeichert | `a.start_ts::date` | Zeitpunkt → Kalendertag |
| v_charge_kohorte | Sicht | `CURRENT_DATE` | „jetzt" als Kalendertag |
| klassiere | Funktion | `current_date` | „jetzt" als Kalendertag |
| auftrag_schema_setzen | Funktion | `new.start_ts::date` | Zeitpunkt → Kalendertag |
| sortierschema_festlegen | Funktion | `current_date` | „jetzt" als Kalendertag |
| sortierschema_festlegen | Funktion | `current_date` | „jetzt" als Kalendertag |
| sortierschema_festlegen | Funktion | `current_date` | „jetzt" als Kalendertag |
| demo_daten_laden | Funktion | `l.start_ts::date` | Zeitpunkt → Kalendertag |
| demo_daten_laden | Funktion | `l.start_ts::date` | Zeitpunkt → Kalendertag |
| demo_daten_laden | Funktion | `current_date` | „jetzt" als Kalendertag |
| demo_daten_laden | Funktion | `current_date` | „jetzt" als Kalendertag |
| demo_daten_laden | Funktion | `current_date` | „jetzt" als Kalendertag |
| demo_daten_laden | Funktion | `current_date` | „jetzt" als Kalendertag |

---

### Dieselbe Datenbank, zwei Zeitzonen

Dieselben Zeilen, zweimal ausgewertet — geändert wurde **nur die Zeitzone der Datenbank**, keine einzige Zahl in den Daten. Was sich hier unterscheidet, hängt an einer Einstellung und nicht am Betrieb. Auf der Demosaison betrifft es eine einzige Wägung; ihr eine Lagertag verschiebt die ausgewiesene Verlustmasse der ganzen Saison.

| Grösse | UTC | Europe/Zurich | Unterschied |
|---|---|---|---|
| alle geprüften | — | — | keiner auf den Demodaten |

---

### Gleiche Formen im Frontend-Code

104903 Wortmarken in 63 Dateien. Verglichen werden nicht Zeichen, sondern Gerüste: Bezeichner, Zahlen und Zeichenketten sind durch Platzhalter ersetzt, Schlüsselwörter stehen. Ein Treffer ab 60 Marken zählt; er wird nach beiden Seiten verlängert, solange die Formen gleich bleiben, und Treffer innerhalb längerer fallen weg. Gefunden: 72 Paare.

| Länge (Wortmarken) | Stelle A | Stelle B | weitere Stellen | Zeilen A |
|---|---|---|---|---|
| 3516 | src/lib/i18n.ts:285 | src/lib/i18n.ts:513 | 3 | 913 |
| 877 | src/lib/i18n.ts:27 | src/lib/i18n.ts:1197 | 0 | 256 |
| 876 | src/lib/i18n.ts:27 | src/lib/i18n.ts:285 | 5 | 256 |
| 284 | src/arbeit/AusschussMaske.tsx:74 | src/arbeit/FertigePaletteMaske.tsx:74 | 0 | 20 |
| 265 | src/arbeit/WiegenMaske.tsx:73 | src/pages/Kontrolle.tsx:144 | 0 | 21 |
| 209 | src/arbeit/AusschussMaske.tsx:78 | src/arbeit/FauleMaske.tsx:70 | 3 | 16 |
| 174 | src/arbeit/AusschussMaske.tsx:122 | src/arbeit/FauleMaske.tsx:114 | 0 | 18 |
| 165 | src/arbeit/Korrektur.tsx:28 | src/arbeit/Korrektur.tsx:49 | 1 | 16 |
| 146 | src/pages/Arbeit.tsx:259 | src/pages/Arbeit.tsx:270 | 0 | 14 |
| 144 | src/pages/Ueberblick.tsx:306 | src/pages/Ursachen.tsx:384 | 0 | 4 |
| 142 | src/arbeit/Abschluss.tsx:246 | src/pages/Arbeit.tsx:133 | 0 | 4 |
| 139 | src/arbeit/Abschluss.tsx:132 | src/arbeit/Abschluss.tsx:153 | 0 | 20 |

---

### Die längsten Funktionen und Komponenten

195 Funktionen und Komponenten in 63 Dateien, zusammen 12105 Zeilen. Länge allein ist kein Mangel — eine Seite mit acht Abschnitten ist lang, weil sie acht Abschnitte hat. Die Spalte **Tiefe** ist die aussagekräftigere: Sie zählt geschachtelte Blöcke, und ab vier hat niemand mehr alle Fälle gleichzeitig im Kopf.

| Datei | Name | Zeilen | Tiefe | von–bis |
|---|---|---|---|---|
| src/pages/NeueArbeit.tsx | `grenzenVon` | 360 | 6 | 24–383 |
| src/arbeit/Zaehler.tsx | `ZETTEL` | 275 | 5 | 8–282 |
| src/pages/Arbeit.tsx | `Arbeit` | 273 | 6 | 36–308 |
| src/arbeit/Abschluss.tsx | `Abschluss` | 262 | 5 | 31–292 |
| src/components/Diagramm.tsx | `Linien` | 259 | 7 | 100–358 |
| src/pages/Messungen.tsx | `Messungen` | 235 | 6 | 17–251 |
| src/pages/Stammdaten.tsx | `Kaliber` | 215 | 5 | 362–576 |
| src/pages/CsvUpload.tsx | `CsvUpload` | 205 | 5 | 24–228 |
| src/pages/Lieferungen.tsx | `Lieferungen` | 200 | 3 | 27–226 |
| src/betrieb/AusgangImport.tsx | `DateiKarte` | 193 | 6 | 219–411 |
| src/pages/Stammdaten.tsx | `PalettenImport` | 167 | 5 | 116–282 |
| src/pages/Kontrolle.tsx | `Kontrolle` | 150 | 5 | 31–180 |

---

### Objekte mit zeichengleicher Definition

Von 145 Ansichten, gespeicherten Ansichten und Funktionen haben 0 eine Definition, die nach dem Wegräumen von Leerraum und dem eigenen Namen zeichengleich mit der eines anderen ist. Gemeldet wird nur Gleichheit, nicht Ähnlichkeit: Zwei Sichten, die zu 80 % übereinstimmen, unterscheiden sich womöglich genau dort, wo es darauf ankommt.

| Die Gleichen | Art | Zeilen SQL | wer liest welches |
|---|---|---|---|
| — | — | — | keine zwei Objekte sind zeichengleich |

---

### Was im Quelltext niemand mehr anspricht

Gesucht wurde grosszügig: Ein Text gilt schon dann als benutzt, wenn sein Schlüssel **irgendwo** im Quelltext als Wort vorkommt — nicht erst bei `t('schluessel')`. Das findet weniger Totholz, kann aber nie etwas Lebendiges vorschlagen: Die Oberfläche holt Texte auch über Tabellen wie `Record<string, TextId>` ab, und ein engeres Muster hätte genau die für tot erklärt. Die Spalte „Beweis" sagt, ob die Kandidaten in einer Wegwerfkopie des Quellbaums tatsächlich entfernt wurden und `tsc` samt Testsuite danach noch durchliefen.

| Art | gesucht in | gefunden | Beweis | Zeilen, die wegfielen |
|---|---|---|---|---|
| Texte in sechs Sprachen | 218 Schlüssel | 0 | nichts zu beweisen | — |
| Exporte ohne Einführung | 232 Exporte | 34 | `export` gestrichen, tsc und Testsuite grün | 0 (nur das Schlüsselwort) |
| Klassen im Stylesheet | 123 Klassen | 8 | kein Beweis möglich (tsc sieht CSS nicht) | — |

---

### Antwortquote je Reiter des Betriebsleiters

Ein „Zahlenfeld" ist eine Zeile mal eine Antwortspalte. Antwortspalten sind alle ausser Schlüsseln und Beschriftungen (`charge_nr`, `sorte`, `basis`, `n_…`); die zählen nicht, weil sie die Frage sind und nicht die Antwort. Gezählt mit `count(spalte)` gegen `count(*)` — nicht geschätzt. Die Zuordnung Ansicht → Reiter folgt der Tabelle in `docs/UI-KONZEPT.md`.

| Reiter | Was er beantwortet | Zahlenfelder | davon mit Wert | Quote | Spalten ganz ohne Wert | Spalten teils ohne Wert |
|---|---|---|---|---|---|---|
| **Überblick** | Was kam herein, was ging hinaus, was ist bis heute verloren — und woran? | 12206 | 11937 | 97.8 % | 0 | 5 |
| **Ursachen** | Echter Verlust und kein echter Verlust, jede Ursache in der Tiefe | 5093 | 4106 | 80.6 % | 3 | 24 |
| **Chargen** | Wo steht welche Charge? | 3956 | 3898 | 98.5 % | 0 | 5 |
| **Messungen** | Was weiss die Auswertung — und was nicht? | 4934 | 4801 | 97.3 % | 0 | 12 |
| **Betrieb** | Was ist heute los, und wie pflege ich die Grundlagen? | 4598 | 4170 | 90.7 % | 0 | 11 |

---

### Spalten, in denen heute in keiner Zeile ein Wert steht

Diese Spalten sind auf der Demosaison durchgehend leer. Das ist nicht automatisch ein Mangel — eine Spalte für eine Messung, die dieser Betrieb noch nicht macht, gehört leer zu sein. Es ist aber die Liste, die man durchgehen muss, um zu wissen, welche Hälfte des Bildschirms heute aus Strichen besteht.

| Reiter | Ansicht | Spalte | Typ | Zeilen |
|---|---|---|---|---|
| Ursachen | `erg_modell` | `selektions_versatz` | numeric | 1 |
| Ursachen | `erg_selektion` | `rest_lager` | numeric | 1 |
| Ursachen | `erg_selektion` | `unterschied` | numeric | 1 |

---

### Eichung: die Streuung dieses Werkzeugs neben dem Band, das die Auswertung ausweist

Bevor eine einzige Aussage über Vergleiche fällt, misst das Werkzeug sich selbst: Es zieht die Koeffizienten 200 Mal aus ihren eigenen Bändern, rechnet die volle Kaskade und stellt die entstandene Streuung neben die, die die Auswertung ausweist. Verglichen wird **zweimal**, und der Unterschied zwischen den letzten beiden Spalten ist der eigentliche Ertrag dieser Tabelle. „Gegen den Bildschirm" nimmt das Band, wie es dasteht — also samt dem t-Faktor der Freiheitsgrade. „Gegen 1.96 σ" nimmt nur die fortgepflanzte Streuung und lässt den t-Faktor weg. Liegt die letzte Spalte nahe 1 und die vorletzte weit darunter, rechnen beide Wege dieselbe Streuung aus und der ganze Unterschied steckt im t-Faktor — das ist kein Fehler dieses Werkzeugs, sondern der Befund von A4, hier auf einem völlig anderen Weg noch einmal bestätigt. Weicht auch die letzte Spalte ab, gehen die Rechenwege wirklich auseinander. Nachjustiert wird an keiner Seite etwas.

| Verlustursache | Wert (kg) | Delta-Streuung σ (kg) | t heute | Band auf dem Bildschirm (± kg) | Streuung dieses Werkzeugs (± kg) | gegen den Bildschirm | gegen 1.96 σ |
|---|---|---|---|---|---|---|---|
| Schimmel/Fäulnis | 26265 | 1286.2 | 12.706 | 16343 | 9698 | 0.59 | 3.85 |
| Verdunstung | 23610 | 365.3 | 12.706 | 4642 | 785 | 0.17 | 1.10 |
| Zu klein (Tierfutter) | 7344 | 190.7 | 12.706 | 2423 | 554 | 0.23 | 1.48 |
| Nebenkanal zu gross | 4787 | 227.2 | 12.706 | 2887 | 727 | 0.25 | 1.63 |
| Faul beim Abpacken (Fax) | 2426 | 56.8 | 12.706 | 722 | 154 | 0.21 | 1.38 |
| Nicht lagerbedingt | 0 | 193.8 | 12.706 | 1231 | 189 | 0.15 | 0.50 |

---

### Welche Vergleiche der Überblick trägt (200 Ziehungen)

Die Koeffizienten der Kaskade wurden aus ihren eigenen Bändern gezogen und die ganze Kaskade damit 200 Mal neu gerechnet. „A grösser in" ist der Anteil der Ziehungen, in denen die Reihenfolge so herauskam, wie sie heute auf dem Bildschirm steht. Unter 97,5 % heisst: Der Bildschirm zeigt eine Reihenfolge, für die die Daten nicht reichen. Aufgeführt sind die zehn knappsten Vergleiche je Art; die vollständige Liste steht in `werkstatt/befunde/befunde.json`. **Diese Tabelle gilt nur, soweit die Eichung darüber trägt** — wo das Verhältnis dort weit von 1 abweicht, sind auch diese Prozente um denselben Faktor daneben.

| Vergleich | A | B | A zeigt | B zeigt | A grösser in | Unterschied 95 % zwischen | Urteil |
|---|---|---|---|---|---|---|---|
| Verlustursache | Schimmel/Fäulnis | Verdunstung | 26264.63 | 23610.20 | 69.5 % | -5709.91 … 14579.46 | trägt nicht |
| Verlustursache | Schimmel/Fäulnis | Zu klein (Tierfutter) | 26264.63 | 7344.41 | 100.0 % | 10682.37 … 30444.34 | trägt |
| Verlustursache | Schimmel/Fäulnis | Nebenkanal zu gross | 26264.63 | 4787.01 | 100.0 % | 13313.55 … 33185.05 | trägt |
| Verlustursache | Schimmel/Fäulnis | Faul beim Abpacken (Fax) | 26264.63 | 2426.27 | 100.0 % | 15946.70 … 35184.82 | trägt |
| Verlustursache | Schimmel/Fäulnis | Nicht lagerbedingt | 26264.63 | 0.00 | 100.0 % | 18276.00 … 37671.59 | trägt |
| Verlustursache | Verdunstung | Zu klein (Tierfutter) | 23610.20 | 7344.41 | 100.0 % | 15438.69 … 17203.99 | trägt |
| Verlustursache | Verdunstung | Nebenkanal zu gross | 23610.20 | 4787.01 | 100.0 % | 17629.19 … 20022.25 | trägt |
| Verlustursache | Verdunstung | Faul beim Abpacken (Fax) | 23610.20 | 2426.27 | 100.0 % | 20335.63 … 22004.75 | trägt |
| Verlustursache | Verdunstung | Nicht lagerbedingt | 23610.20 | 0.00 | 100.0 % | 22630.37 … 24350.00 | trägt |
| Verlustursache | Zu klein (Tierfutter) | Nebenkanal zu gross | 7344.41 | 4787.01 | 100.0 % | 1720.42 … 3502.50 | trägt |
| Sorte | Ker Madec | Mieluna | 15.91 | 15.95 | 47.5 % | -0.89 … 0.80 | trägt nicht |
| Sorte | Mieluna | Tiana | 15.95 | 16.00 | 43.0 % | -0.52 … 0.38 | trägt nicht |
| Sorte | Ker Madec | Tiana | 15.91 | 16.00 | 39.0 % | -0.96 … 0.66 | trägt nicht |
| Sorte | Ker Madec | Orange Summer | 15.91 | 15.59 | 72.5 % | -0.71 … 1.37 | trägt nicht |
| Sorte | Orange Summer | Tiana | 15.59 | 16.00 | 23.0 % | -1.62 … 0.46 | trägt nicht |
| Sorte | Butterkin | Lekor | 17.27 | 17.71 | 21.0 % | -1.55 … 0.70 | trägt nicht |
| Sorte | Mieluna | Orange Summer | 15.95 | 15.59 | 80.5 % | -0.38 … 1.29 | trägt nicht |
| Sorte | Amoro | Orange Summer | 15.13 | 15.59 | 18.5 % | -1.35 … 0.37 | trägt nicht |
| Sorte | Butterkin | Kaori Kuri | 17.27 | 16.65 | 86.5 % | -0.54 … 1.63 | trägt nicht |
| Sorte | Amoro | Ker Madec | 15.13 | 15.91 | 11.0 % | -1.93 … 0.34 | trägt nicht |
| Schlag | Daniel Böhler | Slowgrow Uster | 16.79 | 16.76 | 59.0 % | -0.35 … 0.57 | trägt nicht |
| Schlag | Agasul Baumann | Russikon BundB | 17.10 | 17.29 | 38.5 % | -1.16 … 0.80 | trägt nicht |
| Schlag | Klaus Böhler | Slowgrow Uster | 16.69 | 16.76 | 37.5 % | -0.44 … 0.43 | trägt nicht |
| Schlag | Gossau Eberhard | Illnau Gross | 13.40 | 13.24 | 65.5 % | -0.55 … 0.87 | trägt nicht |
| Schlag | Andi Ball | Rümlang Keller | 16.28 | 16.10 | 77.5 % | -0.38 … 0.83 | trägt nicht |
| Schlag | Bonomo | Illnau Bruno | 14.38 | 14.13 | 83.0 % | -0.26 … 0.79 | trägt nicht |
| Schlag | Agasul Baumann | Daniel Böhler | 17.10 | 16.79 | 83.5 % | -0.31 … 0.86 | trägt nicht |
| Schlag | Agasul Baumann | Slowgrow Uster | 17.10 | 16.76 | 85.5 % | -0.36 … 1.01 | trägt nicht |
| Schlag | Daniel Böhler | Russikon BundB | 16.79 | 17.29 | 14.5 % | -1.23 … 0.43 | trägt nicht |
| Schlag | Klaus Böhler | Russikon BundB | 16.69 | 17.29 | 10.5 % | -1.31 … 0.22 | trägt nicht |
| Charge | 1631 | 1638 | 14.84 | 14.85 | 52.5 % | -0.58 … 0.57 | trägt nicht |
| Charge | 1634 | 1647 | 14.38 | 14.38 | 50.0 % | -0.96 … 0.96 | trägt nicht |
| Charge | 1625 | 1647 | 14.39 | 14.38 | 51.0 % | -0.85 … 0.85 | trägt nicht |
| Charge | 1607 | 1624 | 13.54 | 13.61 | 46.5 % | -1.15 … 1.21 | trägt nicht |
| Charge | 1613 | 1637 | 16.87 | 16.92 | 46.0 % | -1.14 … 0.99 | trägt nicht |
| Charge | 1628 | 1636 | 17.10 | 17.14 | 44.5 % | -0.92 … 0.71 | trägt nicht |
| Charge | 1650 | 1651 | 16.19 | 16.08 | 55.5 % | -0.90 … 1.42 | trägt nicht |
| Charge | 1626 | 1651 | 16.20 | 16.08 | 56.5 % | -0.90 … 1.43 | trägt nicht |
| Charge | 1605 | 1620 | 13.07 | 13.14 | 43.0 % | -1.00 … 0.78 | trägt nicht |
| Charge | 1611 | 1614 | 14.61 | 14.69 | 43.0 % | -0.87 … 0.72 | trägt nicht |

---

### Was jede Messart an Unsicherheit wegnimmt

Je Messart wurde auf einer Kopie der Demodatenbank **alles gelöscht, was diese Messart je erfasst hat**, die volle Auswertung neu gerechnet und die Summe der sechs Verlustbänder verglichen — und zwar **nur über die Ströme, die in beiden Läufen ein Band haben**. Fällt ein Strom ohne diese Messart ganz aus, verschwände sonst auch sein Band aus der Summe, und weniger Wissen käme als engeres Band heraus. „Nimmt weg" ist die Differenz über die gemeinsamen Ströme: um so viel enger sind die Bänder, weil es diese Messungen gibt. Die Spalte ganz rechts nennt die Ströme, über die das Programm ohne diese Messart **gar nichts** mehr sagen kann — das ist der höchste Ertrag und lässt sich nicht in Kilogramm ausdrücken, deshalb steht er getrennt. Die Minuten sind geschätzt und stehen als eigene Spalte da, damit der Betrieb sie korrigieren kann, ohne dass die übrigen Zahlen sich ändern.

| Messart | Anzahl | Minuten je Messung (Annahme) | verglichene Ströme | Bänder ohne sie (± kg) | Bänder mit ihr (± kg) | nimmt weg (kg) | je Messung (kg) | je Arbeiterminute (kg) | Ströme, die ohne sie verstummen |
|---|---|---|---|---|---|---|---|---|---|
| Palox-Ablesung | 281 | 1 | 4 | 10886 | 10673 | 212 | 0.8 | 0.8 | Nicht lagerbedingt, Schimmel/Fäulnis |
| Lagerkontroll-Wägung | 41 | 6 | 5 | 24641 | 23605 | 1035 | 25.3 | 4.2 | Verdunstung |
| Schimmel-Kistenwägung | 304 | 3 | 5 | 27581 | 27526 | 56 | 0.2 | 0.1 | Faul beim Abpacken (Fax) |
| Ausschuss-Wägung | 34 | 3 | 6 | 41115 | 28247 | 12867 | 378.5 | 126.2 | — |
| Sortierlauf (CSV) | 32 | 2 | 6 | 31145 | 28247 | 2898 | 90.6 | 45.3 | — |
| fertige Palette wiegen | 128 | 4 | 6 | 29013 | 28247 | 766 | 6.0 | 1.5 | — |
| Palette mit Zettelgewicht zählen | 231 | 1 | 6 | 28207 | 28247 | -40 | -0.2 | -0.2 | — |

---

### Was jede Messart am Ergebnis selbst verschiebt

Dieselben Läufe, andere Frage: Nicht wie **sicher** die Zahl wird, sondern wie sie sich **verschiebt**. Eine Messart, ohne die derselbe Verlust herauskäme, bestätigt nur; eine, die ihn merklich verschiebt, korrigiert eine Annahme — und ist damit auch dann wertvoll, wenn sie die Bänder nicht enger macht.

| Messart | Saisonverlust ohne sie (kg) | mit ihr (kg) | Unterschied (kg) |
|---|---|---|---|
| Palox-Ablesung | die Zahl verschwindet | 52301 | nicht vergleichbar |
| Lagerkontroll-Wägung | die Zahl verschwindet | 52301 | nicht vergleichbar |
| Schimmel-Kistenwägung | die Zahl verschwindet | 52301 | nicht vergleichbar |
| Ausschuss-Wägung | 52340 | 52301 | 39 |
| Sortierlauf (CSV) | 53155 | 52301 | 854 |
| fertige Palette wiegen | 52989 | 52301 | 688 |
| Palette mit Zettelgewicht zählen | 52314 | 52301 | 13 |

