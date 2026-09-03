# Prompt: statistische Überprüfung und Überarbeitung

Diesen Text in einer neuen Session einfügen. Er ist bewusst lang — die
Verdachtsliste erspart dem Prüfer das Wiederfinden bekannter Schwächen, ohne
ihn darauf festzulegen.

---

Du bist Datenwissenschaftler mit Schwerpunkt angewandte Statistik und
Messfehlerrechnung. Dieses Projekt schätzt aus lückenhaften Stichproben, wo im
Lager und in der Verarbeitung Kürbis-Masse verloren geht. Es läuft technisch,
aber ich weiß nicht, ob die Zahlen, die es ausgibt, statistisch tragen.

**Deine Aufgabe:** Finde heraus, wo das Modell falsch, irreführend oder
unbelegt ist, und behebe es. Nicht die Technik prüfen — die Statistik.

## Zuerst lesen

- `docs/SPEC.md` — die fachliche Spezifikation, besonders §9 (Statistik-Ansatz)
- `docs/DATENFLUSS.md` — was erfasst wird, was gerechnet wird, was angezeigt wird
- `docs/ENTSCHEIDUNGEN.md` — bisherige Modellentscheidungen mit Begründung
- `supabase/migrations/0006`, `0007`, `0011`, `0014` — die Koeffizienten und
  die Hochrechnung
- `supabase/test/pruefung.sql` — was heute geprüft wird
- `supabase/demo_daten.sql`, `supabase/test/last.sql` — Testdatensätze

Mit `./supabase/test/run.sh` läuft alles gegen ein lokales Postgres.

## Arbeitsweise: erst nachweisen, dann urteilen

Behaupte keine Schwäche, die du nicht gezeigt hast, und keine Verbesserung, die
du nicht gemessen hast. Das wichtigste Werkzeug dafür:

**Simulation mit bekannter Wahrheit.** Erzeuge synthetische Saisons, in denen
du die wahren Koeffizienten selbst gesetzt hast — Verdunstungsrate,
Schimmelverlauf, Ausschussanteil. Lass die Pipeline darüber laufen und prüfe:

1. **Trifft sie?** Liegt die Schätzung systematisch daneben (Verzerrung)?
2. **Deckt der Bereich?** Wenn das Modell einen Bereich ausgibt, der 95 %
   heißen soll: Enthält er über viele simulierte Saisons hinweg tatsächlich in
   95 % der Fälle den wahren Wert? Miss die Überdeckung, rate sie nicht.
3. **Wann bricht es?** Bei wie wenigen Messungen wird die Aussage wertlos?
   Ab wann kippt die Rangfolge der Ursachen?

Simuliere dabei auch **ungünstige, aber realistische** Fälle: Messungen fallen
nicht zufällig an (der Betrieb verarbeitet zuerst, was schlecht aussieht),
einzelne Sorten haben gar keine Stichprobe, Tara fehlt bei einem Teil der
Paletten.

## Konkreter Verdacht — jeden Punkt prüfen, keinem glauben

Diese Liste stammt vom Erbauer des Modells. Sie ist weder vollständig noch
zwingend richtig. Widerlege, was nicht stimmt.

### Zur Unsicherheit

1. **Die drei Szenarien sind kein Konfidenzintervall.** „unten/mittel/oben"
   setzt *alle* Koeffizienten gleichzeitig an ihre Grenze. Das unterstellt
   perfekt korrelierte Fehler — für die Summe zu breit, und zugleich zu schmal,
   weil die Unsicherheit der bekannten Größen (Palettenmassen, Tara,
   Palettenzählung) gar nicht eingeht. Angezeigt wird es aber wie ein
   Konfidenzintervall. Prüfe die Überdeckung und ersetze das Verfahren, wenn es
   nicht trägt (Fehlerfortpflanzung oder Monte-Carlo über die Kaskade).
2. **Normalapproximation bei n = 2 oder 3.** `mittel ± 1.96·sd/√n` ist bei
   diesen Stichprobengrößen nicht gerechtfertigt. Bei n = 1 fällt der Bereich
   ganz weg und der Punktwert steht dreimal da — die Hochrechnung wirkt dann
   sicherer als sie ist.
3. **Der Bereich ignoriert, wie viel Masse hinter einer Charge steht.** Eine
   Charge ohne jede Messung bekommt den Gesamtkoeffizienten mit derselben
   scheinbaren Sicherheit wie eine mit zehn Messungen.

### Zu den einzelnen Koeffizienten

4. **Verdunstung ist massenungewichtet.** `avg(rate_pro_tag)` behandelt eine
   400-kg-Palette wie eine 900-kg-Palette. Und die Rate wird als über die Zeit
   konstant angenommen — real ist der Wasserverlust am Anfang höher.
5. **Harte Schwelle statt Teilbündelung.** „eigene Sorte ab n ≥ 3, sonst global"
   springt. Eine hierarchische Schätzung (partial pooling / empirisches Bayes)
   wäre hier der Standard und würde kleine Stichproben angemessen zur Mitte
   ziehen, statt sie voll durchschlagen zu lassen.
6. **Die Schimmelkurve ist keine Überlebensanalyse.** Spec §9 verlangt
   ausdrücklich Hazard-Analyse mit Rechtszensierung. Gebaut ist: kumulativer
   Anteil je Altersklasse, massegewichtet, danach isoton nach oben geglättet.
   Zensierung wird nirgends behandelt. Prüfe, ob eine echte Survival-Schätzung
   (Kaplan-Meier auf Masse, Turnbull bei Intervallzensierung) machbar ist und
   besser trifft.
7. **Selektionsverzerrung beim Schimmel.** Welche Paletten mit welchem Alter
   verarbeitet werden, ist nicht zufällig. Der beobachtete Schimmelanteil bei
   Alter X ist bedingt auf „wurde bei Alter X verarbeitet", nicht auf „lag X
   Tage". Das ist vermutlich die größte Fehlerquelle im ganzen Modell. Quantifiziere sie.
8. **Extrapolation über den beobachteten Bereich hinaus.** Für Lagerdauern
   ohne Messung wird der letzte bekannte Wert fortgeschrieben. Für Ware, die
   bis zum Saisonende liegt, unterschätzt das den Schimmel vermutlich deutlich.
9. **Verkettete Fehler.** Der Schimmelanteil wird auf die um die geschätzte
   Verdunstung reduzierte Masse bezogen. Fehler in r wandern also in den
   Schimmelkoeffizienten. Die Szenarien behandeln beide als unabhängig.
10. **Gewichteter Mittelwert, ungewichtete Streuung.** In `v_koeff_ausschuss`
    und `v_koeff_nebenkanal` wird der Mittelwert massegewichtet gebildet, die
    Standardabweichung aber ungewichtet. Das passt nicht zusammen.

### Zur Datengrundlage

11. **Die Dubletten-Regel ist unbelegt.** Sie verwirft 12–28 % aller CSV-Zeilen
    auf Basis einer Plausibilitätsüberlegung. Ist sie falsch, sind alle
    CSV-gestützten Massen entsprechend daneben. Spec §13 sieht eine Prüfung an
    einer handgezählten Palette vor; sie steht aus. Schätze zusätzlich ab, wie
    viele echte Nachbar-Gleichheiten die Regel fälschlich entfernt.
12. **Fehlende Tara verzerrt nach unten.** `sum()` überspringt NULL, die
    Eingangsmasse einer Charge wird also stillschweigend zu klein — und damit
    jeder Verlust in Prozent zu groß. In der Oberfläche wird gewarnt, die Zahl
    selbst bleibt verzerrt.
13. **Nur nach Sorte stratifiziert.** Spec §9 nennt Sorte, Schlag *und*
    Lagerdauer. Der Schlag dürfte für Fäulnis stark relevant sein (nasses Feld).
    Prüfe, ob die Daten das hergeben.
14. **Doppelzählung möglich.** Läuft eine Charge mehrfach über das Sortierband,
    können Paletten mehrfach gezählt werden. Die ausgelagerte Masse würde die
    Eingangsmasse übersteigen; der Lagerbestand wird dann still auf 0 gekappt.
15. **Der Schimmel-Palox sammelt womöglich über mehrere Arbeiten**, wird aber
    einer einzigen zugeordnet.
16. **Die Massenbilanz ist keine Bilanz.** Der Warenausgang wird nicht erfasst;
    verglichen wird nur Modell gegen Sortier-CSV, und nur für den CSV-Anteil.
    Der Restbestand ist eine Projektion, kein Inventar. Sag klar, was diese
    Kontrolle beweisen kann und was nicht.

## Was ich von dir will

1. **Ein Befund je Punkt** — bestätigt, widerlegt oder unentscheidbar, jeweils
   mit der Rechnung oder Simulation, die dazu geführt hat. Ordne nach
   Auswirkung auf das Ergebnis, nicht nach statistischer Eleganz.
2. **Die Korrekturen umgesetzt**, als neue Migrationen, mit Prüfabfragen in
   `supabase/test/pruefung.sql`. Bestehende Ansichten dürfen sich ändern, aber
   nicht stillschweigend: Wenn eine Zahl danach anders ist, weise nach, warum
   die neue richtiger ist.
3. **Ein Simulations-Harness im Repo**, mit dem sich Verzerrung und Überdeckung
   jederzeit nachmessen lassen — nicht nur einmalig für diese Überprüfung.
4. **Eine ehrliche Grenze.** Wo die Daten eine Aussage nicht hergeben, soll das
   Dashboard das sagen, statt eine Zahl zu zeigen. Sag mir, welche der heute
   angezeigten Größen nach deiner Prüfung nicht belastbar sind.
5. **Wenn eine Messung fehlt, die alles besser machen würde**, sag es: was
   genau, wie oft, mit welchem Aufwand — und wie viel enger die Aussage dadurch
   würde. Erfassung darf sich ändern, wenn es der Sache dient; sie muss am
   Handy des Arbeiters aber einfach bleiben.

## Regeln

- **Das Ziel ist Ursachen rangieren, nicht kg-genau bilanzieren** (Spec §9).
  Eine Verbesserung, die die Rangfolge nicht sicherer macht, ist keine.
- Die zwei Bücher bleiben getrennt: physischer Verlust und verschenkte Marge
  werden nie vermischt.
- Alles muss auf der Supabase-Gratis-Stufe laufen. Das Dashboard liest
  gespeicherte Ansichten; Rechenzeit gehört ins Neuberechnen, nicht ins
  Anschauen. `./supabase/test/run.sh` prüft das mit einem Lasttest — es muss
  grün bleiben.
- Erklärender Text gehört ins Betriebsleiter-UI, nie in die Arbeiter-Ansicht.
- Schreibe wie bisher: deutsche Bezeichner, Kommentare erklären das *Warum*.
