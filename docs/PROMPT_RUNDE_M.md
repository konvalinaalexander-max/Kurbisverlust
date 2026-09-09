# Auftrag Runde M: Vier Werkstätten bauen, das System zerlegen, es kleiner und richtiger zurückgeben

## 0. In einem Satz

Bau **vier neue Analysewerkstätten** — für die Mathematik, für die Datenbank,
für den Bauzustand des Codes und für die Frage, ob dieses Programm die Probleme
des Betriebs überhaupt löst —, lass sie auf das ganze System los, und arbeite
ab, was sie finden: **richtiger, kleiner, klarer — nicht mehr.**

## 1. Wo du anfängst — was schon da ist

Elf Runden (A–K) haben das Programm gebaut. Runde L hat ein Analysewerkzeug
gebaut, das **Prüfwerk** (`pruefwerk/`, zehn Sonden), damit die Datenbank gegen
sich selbst befragt und drei Migrationen daraus abgeleitet (0064, 0065, 0066).
Der Bestand heute:

| | |
|---|---|
| Datenbank | Schema-Fassung **0066**, 67 Migrationen, 28 Tabellen, 63 Ansichten, 38 gespeicherte Ansichten, 42 Funktionen, 93 Indexe — **2633 Objekte** im Fingerabdruck |
| `setup.sql` | 574 kB, verdichtet aus 1285 kB Migrationen, Grenze des SQL-Editors 1000 kB |
| Oberfläche | **11 201 Zeilen** TypeScript/TSX in `src/` |
| Prüfstände | 7 Stück (`supabase/test/run.sh`, `pruefstand/*`), dazu 81 Modultests |
| Prüfwerk | 10 Sonden, 4661 Zeilen, letzter Lauf **8 Feststellungen** (4 davon „geprüft und in Ordnung", 2 Fragen an den Betrieb) |

**Lies das zuerst, vollständig, bevor du eine Zeile schreibst:**

1. `docs/PROMPT_PRUEFWERK.md` — der Auftrag der letzten Runde. Du sollst ihn
   **nicht** wiederholen.
2. `docs/PRUEFBERICHT.md` — was zuletzt gefunden wurde und was übrig blieb.
3. `docs/PLAN_REPARATUREN.md` — was repariert wurde, in sechs Stufen, und was
   bewusst offen blieb.
4. `pruefwerk/hypothesen_stand.md` — fünfzig Vermutungen mit Urteil, dazu die
   Tabelle, was aus jeder geworden ist.
5. `docs/ENTSCHEIDUNGEN.md`, Abschnitt **Runde L** — warum 0064, 0065 und 0066
   so aussehen, wie sie aussehen.
6. `docs/ABLAUF.md` — was auf dem Betrieb wirklich passiert, mit der Tabelle
   „Annahmen, die im Modell stecken" (21 Zeilen, vierspaltig).
7. `docs/ABMACHUNGEN.md` — 48 Zusagen, jede mit dem Test, der sie beweist.
8. `docs/FRAGEN.md` und `docs/STATISTIK_BEFUND.md` — was der Betrieb nicht
   beantwortet hat, und wie gut das Modell nachweislich trifft.

### 1.1 Das Prüfwerk ist ab jetzt Ausgangspunkt, nicht Ergebnis

Es einfach noch einmal laufen zu lassen ist **kein Auftrag und kein Ergebnis**.
Es wurde für die Frage gebaut *„bedeutet diese Zahl, was dasteht?"* und hat sie
beantwortet. Diese Runde stellt vier andere Fragen, und die brauchen andere
Werkzeuge.

Zwei Dinge nimmst du trotzdem mit:

- **Die Sonden können stumpf werden.** In Runde L war die Mutationssonde
  unbemerkt blind geworden: Neun von dreizehn Verstellungen zeigten nach zwei
  Migrationen auf Formeln, die es so nicht mehr gab, und die Sonde meldete
  „nichts gefunden" statt „ich kann nichts mehr finden". Das ist die
  gefährlichste Sorte Fehler, die ein Prüfwerkzeug haben kann. **Phase 0 dieser
  Runde ist deshalb: jede der zehn Sonden auf Stumpfheit prüfen** (Abschnitt 4).
- **Die Selbstprobe ist Pflicht.** Jedes Werkzeug, das du baust, bekommt einen
  eingebauten Fall, in dem es anschlagen **muss**. Findet es ihn nicht, sagt
  auch sein leeres Ergebnis nichts, und der Läufer meldet das laut.

## 2. Die vier Jagdgebiete

Das ist die eigentliche Neuerung dieser Runde. Runde L hat gefragt: *meint die
Zahl, was dasteht?* Diese Runde fragt vier andere Fragen, und für jede baust du
eine eigene Werkstatt mit eigenen Werkzeugen.

| Werkstatt | Die Frage | Warum sie bisher niemand gestellt hat |
|---|---|---|
| **A — Rechenwerk** | Ist die **Mathematik** richtig — nicht nur in sich stimmig, sondern der richtige Schätzer für diese Frage? | Die bisherigen Prüfungen zeigen, dass die Formel *so gerechnet wird, wie sie dasteht*. Ob sie die richtige Formel ist, prüft keine davon. |
| **B — Fundament** | Ist die **Datenbank** gesund — Schema, Rechte, Integrität, Pläne, Zeit, tote Masse? | Geprüft wird die Fachlogik. Das Fundament darunter hat seit Runde A niemand vermessen. |
| **C — Bauwerk** | Ist der **Code** so gebaut, wie ein Programm dieser Grösse gebaut sein sollte — oder ist er über zwölf Runden fett geworden? | Elf Runden Anbau. Niemand hat je gemessen, was davon doppelt, tot, zu gross oder am falschen Ort ist. |
| **D — Nutzen** | Löst dieses Programm **die Probleme des Betriebs**? Beantwortet es die Fragen, für die es gebaut wurde? | Das ist die einzige Frage, die wirklich zählt — und die einzige, für die es noch kein einziges Werkzeug gibt. |

Werkstatt **D ist die wichtigste**. Ein Programm, das jede Zahl richtig rechnet
und dem Betriebsleiter trotzdem keine Entscheidung ermöglicht, hat sein Ziel
verfehlt — und das merkt keine Testsuite der Welt.

## 3. Die Haltung

### 3.1 Werkzeugpflicht: keine Behauptung ohne Messgerät

Diese Runde besteht auf einem Grundsatz, und ich messe daran, ob sie etwas wert
war:

> **Jede Aussage über das System muss von einem Werkzeug kommen, das sie misst,
> nicht von einem Blick in den Code.**

Ein Mensch, der eine Datei liest und sagt „die ist zu lang", hat eine Meinung.
Ein Werkzeug, das alle 11 201 Zeilen vermisst, die Verteilung zeigt, den
Ausreisser benennt und beziffert, was seine Aufteilung spart, hat einen Befund.
Der Unterschied ist der ganze Auftrag.

Das gilt auch — und besonders — für Werkstatt D. „Ich habe mir den Überblick
angesehen und finde ihn verständlich" ist wertlos. Bau ein Werkzeug, das die
Frage messbar macht.

### 3.2 Die Faulheitsfalle — was ausdrücklich nicht zählt

Ich habe eine genaue Vorstellung davon, wie diese Runde schiefgehen kann. Das
Folgende ist **kein** Ergebnis, und wenn es im Bericht steht, ist die Runde
gescheitert:

- ❌ Die bestehenden Prüfstände und das Prüfwerk laufen lassen und melden, dass
  alles grün ist. Das ist der Anfang von Phase 0, nicht das Ergebnis.
- ❌ „Geprüft, sieht gut aus" — ohne Zahl, ohne Messung, ohne Werkzeug.
- ❌ Ein Werkzeug bauen, das nichts finden **kann** (keine Selbstprobe, zu
  weiche Regel, zu enger Suchraum), und sein Schweigen als Qualität ausgeben.
- ❌ Bei den ersten zehn Funden aufhören, weil es „reicht".
- ❌ Etwas als „ausserhalb des Umfangs" abtun, ohne vorher zu **messen**, wie
  gross es ist. Erst beziffern, dann verwerfen — mit der Zahl daneben.
- ❌ Den Bericht mit den Funden der letzten Runde füllen. Was in
  `docs/PRUEFBERICHT.md` steht, zählt nicht mit.
- ❌ Ein Orakel oder ein Modell nachjustieren, bis es mit dem Code
  übereinstimmt. Wer das tut, zerstört sein Werkzeug, ohne dass es jemand merkt.
- ❌ Refaktorieren, ohne Verhaltensgleichheit zu beweisen. „Sieht gleich aus"
  ist kein Beweis; die gerenderten Bildschirme und die Auswertungszahlen
  vorher/nachher sind einer.
- ❌ Aufhören, weil ein Werkzeug lange läuft. Lange Läufe gehören in den
  Hintergrund, und du arbeitest weiter.

### 3.3 Erst die Gegenrede, dann der Befund

Für jeden Fund schreibst du **zuerst** auf, warum er vielleicht doch richtig
ist: Welche Absicht steckt dahinter, die ich übersehe? Welcher Betriebsgrund?
Erst wenn die Gegenrede nicht trägt, ist es ein Befund. Das kostet Minuten und
spart einen Bericht, den niemand ernst nimmt.

Das gilt doppelt für Werkstatt C. Code, der umständlich aussieht, ist manchmal
umständlich, weil ein Sonderfall es verlangt — und dann ist die „Vereinfachung"
ein neuer Fehler. **Jede Stelle, die du für Ballast hältst, muss du erst
erklären können**, bevor du sie anfasst.

### 3.4 Grösse oder es ist eine Meinung

Jeder Befund trägt eine Zahl mit Einheit: Kilo, Prozentpunkte, Millisekunden,
Zeilen, Kilobyte, Anzahl betroffener Chargen, Minuten Arbeiterzeit. Kannst du
die Grösse nicht ausrechnen, ist **genau das** der erste Befund: die Sache ist
nicht überprüfbar.

## 4. Phase 0 — Die vorhandenen Werkzeuge auf Stumpfheit prüfen

Bevor du etwas Neues baust: Prüfe, ob die zehn Sonden und die sieben Prüfstände
überhaupt noch etwas finden können. Das ist schnell erledigt und verhindert,
dass du dich auf ein blindes Netz verlässt.

Für **jede** der zehn Sonden und **jeden** der sieben Prüfstände:

1. Pflanze einen Fehler ein, den sie fangen **muss** (auf einer Kopie, nie im
   Original).
2. Lauf sie. Schlägt sie an?
3. Wenn nicht: **Das ist Befund Nummer eins dieser Runde**, mit der Angabe,
   seit wann sie blind ist und was sie in der Zwischenzeit durchgelassen hat.

Ergebnis von Phase 0: eine Tabelle mit zehn plus sieben Zeilen, jede mit
gepflanztem Fehler, Reaktion und Urteil. Dazu ein Satz zu der Frage: **Wie
verhindert man, dass ein Prüfwerkzeug unbemerkt stumpf wird?** In Runde L war
die Antwort „die Sonde sucht die zu verstellende Migration selbst, statt sie zu
kennen". Es gibt sicher mehr solcher Stellen.

## 5. Phase I — Die vier Werkstätten bauen

```
werkstatt/                       ← nicht Teil der App, wie pruefwerk/
  lauf.mjs                       ← Einstieg, wie pruefwerk/lauf.mjs
  a_rechenwerk/                  ← Mathematik
  b_fundament/                   ← Datenbank
  c_bauwerk/                     ← Code
  d_nutzen/                      ← löst es das Problem?
  befunde/befunde.json
  bericht.mjs                    ← erzeugt docs/WERKSTATTBERICHT.md
```

Dieselben Regeln wie beim Prüfwerk: reines Node, **keine neue Abhängigkeit**
(Playwright ist da), jedes Werkzeug mit Selbstprobe, wiederholbar mit stabilen
Kennungen, teure Läufe im Hintergrund.

Was unten steht, ist die **Mindestausstattung**, nicht die Obergrenze. Wo dir
beim Bauen ein besseres Werkzeug einfällt, bau es und sag warum.

---

### 5.A Werkstatt A — Rechenwerk

Die Frage: **Ist das der richtige Schätzer, und ist er ehrlich über sich
selbst?** Nicht „rechnet das SQL, was dasteht" — das hat Runde L geprüft.

**A1 — Schätzer-Prüfstand mit bekannter Wahrheit.**
Für **jeden** geschätzten Koeffizienten einzeln — Verdunstungsrate `r`,
Verderbskurve `f`, Sockel `a₀`, `a_klein`, `a_gross`, `a_fax`, Überfüllung:
Erzeuge Welten mit gesetzter Wahrheit, lass das Modell schätzen und miss
**Verzerrung** (liegt der Schätzer systematisch daneben?) und **Überdeckung**
(enthält das ausgewiesene 95-%-Band den wahren Wert wirklich in 95 % der
Fälle?). Und zwar über eine **Reihe von Stichprobengrössen** — bei n = 1, 2, 3,
5, 10, 30 Messungen. Der Betrieb misst punktuell; ein Schätzer, der erst ab
n = 30 trägt, trägt hier nie.
`supabase/test/simulation/` gibt es bereits — es misst über die ganze Saison,
nicht je Schätzer und nicht über n. Bau darauf auf, aber bau es schärfer.

**A2 — Was die Klammern kosten.**
Das Modell klammert an vielen Stellen: `greatest(x, 0)`, der Boden des
verkaufsfähigen Anteils bei 0.25, der Deckel der Rate bei 0.05, `least(…, 1)`,
`greatest(a_klein + a_gross, 1)` in der Normierung. **Jede Klammer verschiebt
den Erwartungswert**, sobald die Wahrheit in ihre Nähe kommt. Miss für jede:
Ab welchem wahren Wert greift sie, und wie gross ist die Verzerrung dann?
Sonde 04g misst heute nur den *Abstand* zur Grenze auf den Demodaten
(kleinster verkaufsfähiger Anteil 0.671 bei einem Boden von 0.250). Das sagt
nichts darüber, was passiert, wenn eine echte Charge schlecht ist.

**A3 — Der Verhältnis-Schätzer.**
Das Herzstück der Kaskade ist `m0 = geliefert ÷ verkaufsfähiger Anteil`. Der
Nenner ist selbst geschätzt und unsicher. Für solche Verhältnisse gilt
`E[X/Y] ≠ E[X]/E[Y]` — die Verzerrung wächst mit der Unsicherheit des Nenners
und ist immer **nach oben** gerichtet. Wie gross ist sie hier, bei der heutigen
Streuung der Koeffizienten? Rechne es aus, simuliere es, und entscheide mit
Belegen, ob es zählt. Wenn ja: Was wäre die Korrektur, und ist sie ihren Preis
wert? Wenn nein: Sag, ab welcher Unsicherheit sie zählen würde.

**A4 — Wie die Fehler addiert werden.**
Die Bänder entstehen, indem Varianzen addiert werden — das setzt
**Unabhängigkeit** voraus. Sind `r`, `f` und `a₀` unabhängig? Sie werden aus
teils denselben Wägungen und denselben Chargen geschätzt. Simuliere korrelierte
Wahrheiten und miss, wie weit die echte Überdeckung dann von den behaupteten
95 % abweicht. Ein Band, das 95 % heisst und in 70 % trifft, ist schlimmer als
gar kein Band, weil es Sicherheit vortäuscht.
Prüfe im selben Zug die Freiheitsgrade (`c_chargen − 1`) und das t-Quantil:
Zählt dort die richtige Zahl unabhängiger Beobachtungen — oder Chargen, die
sich Koeffizienten teilen?

**A5 — Rückverwandlung aus dem Logarithmus.**
Die Verderbskurve wird logarithmisch geschätzt und zurückverwandelt
(`ln_lambda`, `smearing`, `ln_lambda_korrigiert`). Die Rückverwandlung eines
Mittelwerts aus dem Log-Raum ist **nicht** der Mittelwert im Originalraum. Es
gibt eine Korrektur, und im Code steht eine. Prüfe an synthetischen Daten mit
gesetztem λ, ob sie die richtige ist und ob sie bei kleinen n trägt.

**A6 — Numerik und Rundung.**
Jede Zwischengrösse ist `numeric(14,2)`. Über 844 Paletten, 61 Gruppen und
sieben Stufen der Kaskade summieren sich Rundungen. Miss den Gesamtdrift gegen
eine Rechnung in voller Genauigkeit — auf der Demosaison und auf der
dreifachen. Wo Differenzen grosser Zahlen gebildet werden (Bilanzrest!), such
nach Auslöschung. Prüfe die Überlaufgrenzen von `zahl(x, stellen, grenze)`:
Bei welcher Saisongrösse fällt die erste Zahl heraus?

**A7 — Ränder und Ausartungen.**
Systematisch, nicht stichprobenartig: t = 0 · r = 0 · r am Deckel · a = 1 ·
f = 1 · m0 = 0 · eine einzige Palette · eine einzige Lieferung · alles
ausgeliefert · nichts gemessen · alle Koeffizienten unbekannt · zwei Chargen
mit identischen Daten · eine Charge, die vor dem Erfassungsbeginn komplett weg
war. Für jeden: Was kommt heraus, ist es endlich, ist es ehrlich?

**A8 — Einheitenalgebra.**
Prüfe **symbolisch**, nicht an Werten: Jede Formel bekommt Einheiten (kg, Tage,
1, kg/Tag, kg/Kiste), und die Werkstatt rechnet sie durch. Ein Anteil mal ein
Anteil ist ein Anteil; kg durch kg ist 1; ein Anteil hoch Tage ist verdächtig,
wenn er nicht dimensionslos gemeint war. Sonde 09 prüft heute nur, ob **Werte**
in ihrem Bereich liegen — nicht, ob die **Formel** dimensionsrichtig ist.

---

### 5.B Werkstatt B — Fundament

Die Frage: **Ist die Datenbank unter der Fachlogik gesund?**

**B1 — Was ist tot?**
Für jede der 63 Ansichten, 38 gespeicherten Ansichten, 42 Funktionen und
93 Indexe: Liest sie irgendjemand? Die App, eine andere Ansicht, ein Test, ein
Prüfstand? Bau den vollständigen Nutzungsgraphen (`pg_depend`, Textanalyse,
Frontend-Scan) und nenne, was in keinem Pfad vorkommt. Für Indexe zusätzlich:
Wie oft wurde er in einem echten Lauf benutzt (`pg_stat_user_indexes`, nach
einem vollständigen Dashboard-Lauf und einem Import)? Ein nie benutzter Index
kostet bei jedem Schreiben und bringt nie etwas.
**Vorsicht:** `idx_scan = 0` auf einer frischen Kopie heisst „noch nie
gebraucht", nicht „nutzlos". Miss richtig, bevor du urteilst.

**B2 — Was die Datenbank wirklich tut.**
`explain (analyze, buffers)` für **jede** Ansicht, die das Dashboard lädt, und
für jeden Schreibweg der Arbeiter-Masken — bei einfacher **und** bei dreifacher
Saisongrösse. Flagge: sequenzielle Scans auf grossen Tabellen, Sortierungen,
die auf die Platte auslagern, verschachtelte Schleifen über viele Zeilen,
Fehlschätzungen des Planers um mehr als Faktor 10. `run.sh` misst heute nur die
Gesamtzeit; sie sagt nicht, welcher Schritt sie kostet und ob er bei zehnfacher
Grösse umkippt.

**B3 — Rechte, vollständig durchgespielt.**
Für jede Tabelle, jede Ansicht, jede Funktion: Was kann ein Nichtangemeldeter,
was ein Arbeiter, was ein Betriebsleiter — **gemessen**, indem du es als diese
Rolle versuchst, nicht indem du die Regel liest. Jede RLS-Regel bekommt einen
Fall, der durchkommen muss, und einen, der abprallen muss. Dazu: Funktionen mit
`security definer` und ihr Suchpfad; Rechte, die eine spätere Migration still
wieder aufgemacht hat.

**B4 — Integrität.**
Die vier Bedingungen `auftrag_kaliber_nur_waschen`, `auftrag_fax_nur_waschen`,
`auftrag_palette_datum_pflicht` und `lieferung_hat_menge` stehen als **`not
valid`** in der Datenbank: Sie gelten für Neues, aber niemand hat je geprüft,
ob der Bestand sie erfüllt. Prüfe es — auf den Demodaten und, wenn möglich, auf
den echten. Erfüllen sie sie, gehören sie validiert. Erfüllen sie sie nicht,
ist das ein Befund mit Anzahl.
Dazu: verwaiste Zeilen an jedem Fremdschlüssel; Spalten, die als nullable
deklariert sind und in Wirklichkeit immer gefüllt werden (und umgekehrt);
`on delete`-Verhalten an jedem Fremdschlüssel — was passiert, wenn der
Betriebsleiter eine Arbeit löscht?

**B5 — Die Zeit.**
Die Datenbank läuft auf **`Etc/UTC`**. Der Betrieb liegt in der Schweiz
(UTC+1, im Sommer UTC+2). `heute()` fällt auf `current_date` zurück, und
`current_date` ist der Tag **in der Zeitzone der Sitzung**. Ein Arbeiter, der
um 23:30 Ortszeit etwas erfasst, schreibt einen Zeitstempel, der in UTC bereits
zum nächsten Tag gehört — oder eben nicht, je nach Jahreszeit.
Geh **jeden** Ort durch, an dem ein `timestamptz` zu einem `date` wird, an dem
`current_date` steht, an dem Tage subtrahiert werden. Bau einen Prüfstand, der
dieselbe Erfassung um 22:00, 23:30 und 00:30 Ortszeit durchspielt, im Winter
und im Sommer, und die entstehenden Lagertage vergleicht. **Ein Tag Unterschied
in der Lagerdauer ist ein Tag zu viel Verdunstung an jeder Palette.**

**B6 — Der Weg von unten.**
Spiel alle 67 Migrationen von Null durch und miss die Zeit. Prüfe: Gibt es
Migrationen, die vollständig von späteren ersetzt sind und nur noch Zeit
kosten? Gibt es welche, die auf einer Datenbank mit echten Daten anders wirken
als auf einer leeren? Der Aktualisierungspfad (Stufe 3b in `run.sh`) prüft
einen alten Stand — welchen, und ist das der älteste, den es im Feld gibt?

**B7 — Zwei gleichzeitig.**
Zwei Arbeiter erfassen gleichzeitig an derselben Arbeit. Der Betriebsleiter
lässt die Auswertung neu rechnen, während ein Arbeiter speichert. Ein Import
läuft, während jemand das Dashboard lädt. Was passiert — Sperren, verlorene
Aktualisierungen, halb erneuerte gespeicherte Ansichten? Bau es nach, miss es.

---

### 5.C Werkstatt C — Bauwerk

Die Frage: **Ist der Code so gebaut, wie ein Programm dieser Grösse gebaut sein
sollte?** 11 201 Zeilen Oberfläche, gewachsen über zwölf Runden. Kein Mensch
hat je vermessen, was davon doppelt, tot, zu gross oder am falschen Ort ist.

Das Ziel dieser Werkstatt ist **Reduktion**. Nicht Umbau um des Umbaus willen —
sondern: dieselbe Leistung mit weniger Code, klarer geschnitten, näher an dem,
was das Projekt sonst schon tut.

**C1 — Vermessung.**
Alle Dateien in `src/`, `supabase/` und den Prüfständen: Zeilen, Funktionen je
Datei, Länge der längsten Funktion, tiefste Verschachtelung, Anzahl Zustände in
einer Komponente, Anzahl Eigenschaften einer Schnittstelle. Als Verteilung,
nicht als Durchschnitt — der Durchschnitt versteckt die Ausreisser. Nenne die
zwanzig grössten und sag zu jedem, **ob** die Grösse gerechtfertigt ist.
Ausgangslage: `src/lib/i18n.ts` 1434 Zeilen (sechs Sprachen, vermutlich
gerechtfertigt), `src/pages/Stammdaten.tsx` 815, `src/auswertung/daten.ts` 556,
`src/pages/Ursachen.tsx` 527, `src/components/Diagramm.tsx` 515.

**C2 — Doppelgänger.**
Suche wiederholte Abschnitte **maschinell**, über Token, nicht über Text — in
`src/` und getrennt davon in den SQL-Ansichten. Für jeden Fund: Wie oft, wie
lang, und würde ein gemeinsamer Helfer es kürzer **und klarer** machen? Der
zweite Teil ist wichtig: Drei Zeilen an vier Stellen zusammenzuziehen kann
schlechter sein als sie stehenzulassen.
Ein konkreter Verdacht zum Anfangen: Muster wie
`strom?.bekannt ? <>{kg(x)}</> : '—'` und
`bekannt && wert !== null ? … : 'nicht gemessen'` stehen inzwischen an vielen
Stellen. Zähl sie, statt zu raten.

**C3 — Totholz.**
Ausgeführte Symbole, die niemand einliest. Übersetzungsschlüssel, die keine
Maske verwendet — in **allen sechs** Sprachen einzeln. CSS-Klassen ohne
Verwendung. Eigenschaften, die eine Komponente entgegennimmt und nie liest.
Spalten, die eine Ansicht ausgibt und die niemand liest. Zweige, die nie
erreicht werden können. Für jeden: sicher entfernbar, und warum.

**C4 — Der Abhängigkeitsgraph.**
Wer liest wen? Gibt es Kreise? Liest eine Seite des Betriebsleiters aus den
Arbeiter-Masken oder umgekehrt? Liegt etwas in `lib/`, das nur ein einziger
Ort braucht — oder in einer Seite, das drei Orte brauchen? Zeichne den Graphen,
zeig die Schichtverletzungen.

**C5 — Was beim Arbeiter ankommt.**
Das Bündel ist heute in vier Teile geschnitten (`grundlage` 351 kB, `fremd`
245 kB, `auswertung` 190 kB, `index` 39 kB). Miss, **was der Arbeiter
herunterlädt**, der nur eine Kiste zählen will, auf einem alten Handy in einer
Halle mit schlechtem Empfang. Lädt er Auswertungscode mit, den er nie sieht?
Diagramm-Code? Den Excel-Leser? Jedes Kilobyte hier ist Wartezeit an der Waage.

**C6 — Die SQL-Seite.**
Dieselben Fragen an die 63 Ansichten: Wie tief ist der Ansichtenstapel? Gibt es
Ansichten, die es nur gibt, weil eine frühere Runde sie brauchte und die
inzwischen einen einzigen Leser haben? Rechnet eine Ansicht dieselbe
Zwischengrösse zum zweiten Mal, die eine darunter schon hat? Ist `zahl(...)`
an 93 Stellen ein Muster oder ein Ritual?

**C7 — Der Vorschlag, mit Beweis.**
Jede Reduktion, die du vorschlägst, kommt mit: gemessene Grösse vorher/nachher
(Zeilen, Bytes, Bündel), **und dem Beweis der Verhaltensgleichheit** —
dieselben Bildschirme, dieselben Zahlen, alle Prüfstände grün. Ohne diesen
Beweis wird nicht angefasst.

---

### 5.D Werkstatt D — Nutzen

Die wichtigste. Die Frage: **Löst dieses Programm das Problem, für das es
gebaut wurde?**

Der Betrieb verliert Kürbisse im Lager und will wissen, wo und warum. Er hat
dafür Arbeiterzeit investiert (jede Wägung kostet Minuten in der Halle) und
bekommt dafür Zahlen. **Steht das in einem vernünftigen Verhältnis?**

**D1 — Die Fragenmatrix.**
Stell zwei Listen nebeneinander:
*Links*: jede Frage, die der Betrieb tatsächlich hat — aus `docs/FRAGEN.md`,
aus `docs/ABLAUF.md`, aus `docs/UI-KONZEPT.md`, aus dem, was ein
Kürbisproduzent im November wissen will.
*Rechts*: jede Zahl, die das Programm zeigt — der Begriffs-Prüfstand erntet
sie bereits (rund 2600 Zahlen über zwölf Ansichten).
Dann verbinde. Und nenne die beiden Enden, an denen nichts ankommt:
- **Fragen ohne Antwort** — der Betrieb will es wissen, das Programm sagt
  nichts.
- **Zahlen ohne Frage** — das Programm zeigt es, aber keine Entscheidung hängt
  daran. Das ist Ballast auf dem Bildschirm, und Ballast auf dem Bildschirm
  kostet Aufmerksamkeit, die woanders fehlt.

**D2 — Entscheidungsauflösung.** *(Das schärfste Werkzeug dieser Werkstatt.)*
Der Betriebsleiter trifft Entscheidungen durch **Vergleiche**: Ist Sorte A
schlechter als Sorte B? Ist Schlag 3 auffällig? Ist dieses Jahr schlechter als
letztes? Soll Charge X vor Charge Y? Lohnt sich früher waschen?
Für jeden dieser Vergleiche: **Ist der Unterschied grösser als die Unsicherheit
der beiden Zahlen?** Wenn nicht, kann das Programm die Frage **nicht
beantworten** — und tut trotzdem so, indem es zwei verschiedene Zahlen
nebeneinanderstellt.
Bau das als Werkzeug: für jedes Paar, das die Oberfläche nebeneinanderstellt,
das Verhältnis von Unterschied zu Unsicherheit. Sortiere nach
Unterscheidbarkeit. Das Ergebnis sagt dem Betrieb, **welchen seiner Vergleiche
er glauben darf** — und das hat ihm noch nie jemand gesagt.

**D3 — Die Handlungsprobe.**
Für jeden der sechs Verluststöme: Angenommen, er ist der grösste — **was
täte der Betrieb dann?** Und: Liefert das Programm, was für diese Handlung
nötig ist?
Beispiel: Wenn Verdunstung gewinnt, ist die Massnahme Luftfeuchte oder kürzere
Lagerung — dafür braucht es den Verlauf über die Lagerdauer und den Punkt, ab
dem es teuer wird. Zeigt das Programm den? Wenn Schimmel gewinnt, ist die
Massnahme früher aussortieren — dafür braucht es, welche Charge zuerst kippt.
Ein Strom, dessen Kenntnis zu keiner Handlung führt, muss nicht auf Kilo genau
gemessen werden. Das ist eine **Ersparnis**, kein Mangel — und sie gehört
benannt.

**D4 — Was eine Messung bringt.**
Der Betrieb bezahlt jede Messung mit Arbeiterzeit. Rechne aus, **wie viel
Unsicherheit jede Messart wegnimmt, je Minute Arbeiterzeit**: eine
Lagerkontroll-Wägung, eine Palox-Ablesung, eine Fax-Wägung, eine
Ausschuss-Wägung, ein Sortierlauf mit CSV, eine gewogene fertige Palette.
Dann die Rangliste. Sie sagt dem Betrieb, wovon er **mehr** machen soll und
was er **weglassen** kann, ohne dass es weh tut. Nach meiner Kenntnis ist das
die nützlichste einzelne Zahl, die diese Runde hervorbringen kann.

**D5 — Was die Datenlage hergibt.**
Bei der heutigen Erfassungsdichte — punktuell, vielleicht fünfzehn Waschgänge
in einer Saison: Welche Aussagen sind belastbar, welche nicht? Wo behauptet die
Oberfläche mehr, als die Daten hergeben? Wo behauptet sie **weniger**, als sie
könnte (auch das ist ein Mangel: verschenkte Auskunft)?
Miss es, indem du die Datenmenge herunterskalierst und zusiehst, ab wann welche
Aussage kippt.

**D6 — Die Sechzig-Sekunden-Probe.**
Öffne den Überblick mit den Demodaten. Was schliesst jemand daraus in sechzig
Sekunden — und stimmt das? Nimm die drei Sätze, die ein Leser mitnimmt, und
prüfe jeden gegen die Rohdaten. Das kannst du maschinell stützen: Der
Bildschirm-Prüfstand rendert bereits; ernte die grössten Zahlen, die
auffälligsten Farben, die obersten Zeilen — das ist es, was hängenbleibt — und
prüfe **diese** auf Richtigkeit und Wichtigkeit.

## 6. Phase II — Bericht und Plan

1. **Jeden Befund gegenlesen.** Was die Gegenrede übersteht, bleibt.
2. **Grösse ausrechnen**, in der Einheit, die zur Sache passt.
3. **Marke setzen:** *Reparatur* (wird gebaut) · *Reduktion* (Code wird kleiner,
   Verhalten gleich) · *Frage an den Betrieb* (zwei Antworten vertretbar) ·
   *Entscheidung des Betriebs* (Ablauf in der Halle) · *kein Fehler* (geprüft,
   in Ordnung — gehört in den Bericht, sonst weiss niemand, wie weit du
   nachgesehen hast).
4. **`docs/WERKSTATTBERICHT.md`** — nach Wirkung sortiert, in einfachem
   Deutsch, mit einem eigenen Abschnitt je Werkstatt und einer ehrlichen
   Selbstauskunft: Welches Werkzeug hat wie viel gefunden, und wo hat eines
   nichts gefunden, weil es nichts gibt — und wo, weil es zu schwach war?
5. **Der Plan** — Reihenfolge nach `Wirkung × Sicherheit ÷ Risiko`, mit
   Abhängigkeiten und einer ausdrücklichen Liste dessen, was **nicht** gemacht
   wird und warum.
6. **Die Fragen an den Betrieb** — höchstens eine Seite, jede mit beiden
   ausgerechneten Zahlen und einer Empfehlung mit Begründung. In
   `docs/FRAGEN.md` **und** in `docs/fragen.html` (daraus entsteht das PDF, das
   der Betrieb wirklich liest).

## 7. Phase III — Abarbeiten

Nach dem Plan, von oben nach unten. Für jede Änderung:

1. **Erst der Test, der ohne sie fehlschlägt.** Bei einer *Reduktion* ist der
   Test der Beweis der Verhaltensgleichheit: dieselben Zahlen, dieselben
   Bildschirme, vorher und nachher.
2. Dann die Änderung, so klein wie möglich. Betrifft sie die Datenbank, wird
   sie eine Migration (0067 aufwärts), `setup.sql` wird neu gebaut, `run.sh`
   vergleicht beide Wege objektweise.
3. Dann **alles** noch einmal: Prüfwerk, Werkstätten, Prüfstände. Der Befund
   muss weg sein und **kein neuer** entstanden.
4. Dann die Doku: `ABLAUF.md`, wo sich eine Annahme geändert hat,
   `ABMACHUNGEN.md` um eine neue Zusage mit ihrem Test, `ENTSCHEIDUNGEN.md` mit
   einem Abschnitt für Runde M, `README.md`, `docs/programm.html` und die PDFs.

Nach jedem grösseren Block committen und pushen. Die Werkstätten bleiben im
Bestand — sie sollen nächste Runde wieder laufen.

## 8. Die eiserne Regel: die App wird nicht komplizierter

Sie gilt weiter, unverändert, und sie ist die wichtigste Grenze:

- **Kein neues Eingabefeld** in den Arbeiter-Masken — es sei denn, du
  begründest in **Kilo**, was es rettet, und der Betrieb hat zugestimmt.
- **Kein neuer Bildschirm, keine neue Kennzahl, kein neuer Reiter.** Wo ein
  Befund heilbar ist, indem man eine irreführende Zahl richtigstellt oder
  **entfernt**, ist das die bessere Lösung als drei erklärende danebenzustellen.
- **Keine neue Abhängigkeit** im Auslieferungsstand (`dependencies` in
  `package.json` bleibt, wie sie ist). Werkzeuge dürfen nichts nachziehen.
- Die Werkstätten sind **nicht Teil der App**: eigenes Verzeichnis, nicht im
  Build, nicht im Bündel, kein Rückimport in `src/`.
- **Weniger ist ein gültiges Ergebnis** — und diese Runde ausdrücklich ein
  erwünschtes.

Ein Zusatz für diese Runde: **Der Code darf nicht wachsen.** Wenn `src/` am
Ende mehr Zeilen hat als die 11 201 zu Beginn, will ich dafür eine Begründung
je zusätzlicher hundert Zeilen sehen. Werkzeuge unter `werkstatt/` zählen nicht
mit — die dürfen so gross werden, wie sie müssen.

## 9. Startverdacht — unbestätigt, und ausdrücklich nicht der Umfang

Das ist **Kalibrierung für die Tiefe, nicht die Arbeitsliste**. Wer nur diese
Punkte abarbeitet, hat den Auftrag verfehlt: Die Leistung besteht darin, die
zwanzig zu finden, die hier nicht stehen.

**Mathematik**
- Der Sockel a₀ ist in der Demosaison **überall 0** — nicht, weil er null ist,
  sondern weil der Nachweis-Test ihn zurückhält. „Nicht nachweisbar" und „null"
  sehen in jeder Summe gleich aus. `STATISTIK_BEFUND.md` sagt, dass ein echter
  Sockel am Saisonende **nie** erkannt wird (Schimmel dann +48 %). Was heisst
  das für die Zahl, die der Betrieb im November liest?
- Vier von fünfzehn Verstellungen in der Mutationssonde ändern auf den
  Demodaten **keine einzige Zahl** — zwei davon hängen an a₀, zwei an
  Schutzgrenzen, die nie erreicht werden. Ungeprüftes Gebiet.
- Die Koeffizienten werden über Sorten hinweg gepoolt, wenn eine Sorte zu wenig
  Messungen hat. Wonach gewichtet — nach Masse, nach Anzahl, gar nicht? Und
  merkt der Betriebsleiter, dass die Zahl seiner Sorte aus einer anderen kommt?

**Datenbank**
- **Zeitzone `Etc/UTC`** bei einem Betrieb in der Schweiz. Siehe B5.
- Vier `not valid`-Bedingungen, nie validiert. Siehe B4.
- 93 Indexe. Wie viele werden in einem echten Tag je benutzt?

**Code**
- `src/pages/Stammdaten.tsx`, 815 Zeilen, eine Seite. Was steckt da drin?
- Sechs Sprachen à 1434 Zeilen `i18n.ts` — wie viele Schlüssel sind in mindestens
  einer Sprache tot?
- Der Arbeiter lädt möglicherweise Auswertungs- und Diagrammcode mit, den er
  nie zu sehen bekommt.

**Nutzen**
- Der Betrieb hat in Runde L zwei Fragen bekommen und **noch nicht
  beantwortet** (Bezugsgrösse des Verlusts; Umstapeln zwischen Eingang und
  Wägung). Beide stehen in `docs/FRAGEN.md` als Nummer 51 und 52. Was kostet
  es, dass sie offen sind — und kann das Programm inzwischen selbst eine
  Antwort **nahelegen**, statt nur zu fragen?
- Die Auffälligkeiten (`v_plausibilitaet`, inzwischen rund fünfzehn Arten)
  stehen alle unter *Messungen*. Sieht sie dort jemand? Welche davon ist je
  aufgetreten, welche noch nie — und ist eine, die nie auftritt, ein gutes
  Zeichen oder eine tote Regel?

## 10. Werkzeuge und Umgebung

```bash
npm run pruefen                     # Typen, 81 Tests, Build — ohne Datenbank
./supabase/test/run.sh 'postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432'
node pruefwerk/lauf.mjs --schnell   # neun Sonden ohne die Mutationssonde
node pruefwerk/lauf.mjs             # alle zehn (~20 Minuten)
node pruefwerk/bericht.mjs          # docs/PRUEFBERICHT.md neu schreiben
node pruefstand/bildschirme.mjs     # jede Seite im echten Browser
node pruefstand/beschriftung.mjs    # sagt jede Zahl, was sie ist?
node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh '<url>'
./pruefstand/luecken.sh '<url>'     # Maske ↔ Auswertung, beide Richtungen
./supabase/test/simulation/matrix.sh 25   # Simulationsmatrix, neun Lagen
./supabase/setup_bauen.sh           # nach jeder Änderung an migrations/
node docs/pdf_bauen.mjs             # die fünf PDFs neu
```

Postgres starten, falls sie nicht läuft:

```bash
mkdir -p /tmp/pgsock
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgdata -l /tmp/pg.log \
  -o '-k /tmp/pgsock -p 55432 -c listen_addresses=' start"
```

Vorhandene Datenbanken: `demo` (aktueller Stand mit Demodaten, 844 Paletten,
187 Lieferungen), `demo64`/`demo65`/`demo66` (Zwischenstände), `postgres` (wird
von `run.sh` überschrieben). **Bau dir eigene Kopien** (`create database x
template demo`) — die Demodaten werden nicht verbogen.

**Arbeite parallel.** Alles, was länger als zwei Minuten läuft, startest du im
Hintergrund und arbeitest weiter. Die Mutationssonde braucht allein siebzehn
Minuten; Werkstatt A wird mit vielen Simulationen ähnlich lange laufen. Vor
einem Fortschrittsbalken zu warten ist verschwendete Zeit.

## 11. Feste Regeln

- Entwickeln und pushen **nur** auf `claude/new-session-vrnnyo`
  (`git push -u origin claude/new-session-vrnnyo`, bei Netzfehlern mit 2/4/8/16
  Sekunden erneut). **Keinen Pull Request** ohne ausdrückliche Bitte.
- Die echten Excel-Dateien unter `/root/.claude/uploads/` enthalten Kundennamen
  und Preise: lesen ja, **committen nie**.
- Keine Modellbezeichnung in Code, Commits, Kommentaren oder Dokumenten.
- Commits mit
  `git -c user.name="Alexander Konvalina" -c user.email="konvalina.alexander@gmail.com"`
  und dem Anhang:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  Claude-Session: <Session-Link>
  ```
- **Keinen Test abschalten, überspringen oder aufweichen**, um grün zu werden.
  Ein Test, der stört, hat entweder recht oder gehört mit Begründung korrigiert.
- Nichts löschen, worin Daten liegen: Ansichten, Funktionen, Oberflächen ja —
  **Tabellen und Spalten nein**.
- Datierte Stammdaten nie überschreiben, sondern fortschreiben.
- Kommentare erklären **warum**, nicht was. Deutsch, wie der übrige Code.

## 12. Woran ich messe, ob die Runde etwas wert war

Harte Kriterien. Ich zähle nach.

1. **Phase 0 ist erledigt:** Alle zehn Sonden und alle sieben Prüfstände haben
   einen gepflanzten Fehler vorgesetzt bekommen; die Tabelle steht im Bericht.
2. **Vier Werkstätten stehen**, jede mit mindestens fünf eigenständigen
   Werkzeugen, jedes mit Selbstprobe. Ein Werkzeug ohne Selbstprobe zählt nicht.
3. **Mindestens 25 eigene Feststellungen**, die weder in `PRUEFBERICHT.md` noch
   in Abschnitt 9 dieses Auftrags stehen. Davon:
   - mindestens **8 aus Werkstatt A oder B** — die Runde darf nicht in
     Kosmetik enden;
   - mindestens **5 aus Werkstatt C**, jede mit gemessener Reduktion;
   - mindestens **5 aus Werkstatt D**, davon die Fragenmatrix und die
     Entscheidungsauflösung vollständig.
4. **Jede Feststellung hat eine Grösse mit Einheit.**
5. **Der Code ist nicht gewachsen.** `src/` mit Zeilen und Bytes vorher/nachher,
   Bündelgrössen vorher/nachher, jede Zunahme begründet.
6. **Jede Reparatur und jede Reduktion ist durch einen Test festgehalten**, der
   ohne sie fehlschlägt. Bei Reduktionen zusätzlich der Beweis der
   Verhaltensgleichheit.
7. **Die App ist danach nicht komplizierter** — nicht mehr Felder, nicht mehr
   Bildschirme, nicht mehr Abhängigkeiten.
8. **Alles grün am Ende:** `run.sh` über alle Stufen, `npm run pruefen`, alle
   Prüfstände, das Prüfwerk, die neuen Werkstätten.
9. **Der Bericht ist in einfachem Deutsch** und beantwortet vier Fragen: Was
   hast du gesucht? Wo hast du geschaut? Was gefunden, mit welcher Grösse? Was
   muss **ich** entscheiden?

**Und der Satz, auf den es ankommt.** Am Ende will ich von dir eine ehrliche
Antwort auf die Frage aus Werkstatt D lesen:

> *Löst dieses Programm das Problem, für das es gebaut wurde — und woran machst
> du das fest?*

Wenn die Antwort ja lautet, will ich die Messung sehen, auf der sie beruht.
Wenn sie nein lautet oder nur teilweise, will ich wissen, woran es liegt und
was es kosten würde, das zu ändern. **Was ich nicht will, ist „alles in
Ordnung".** Ein System dieser Grösse, über zwölf Runden gewachsen, hat Stellen,
an denen die Rechnung von der Wirklichkeit abweicht und an denen der Code mehr
Platz braucht, als die Sache verdient. Wenn du keine findest, hast du entweder
nicht tief genug gegraben — oder du kannst mir genau und überprüfbar sagen,
warum es diesmal nicht mehr gab.
