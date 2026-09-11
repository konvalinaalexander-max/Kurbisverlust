# Was ich von dir brauche, bevor ich Runde N anfange

Ich habe den Auftrag (`docs/PROMPT_RUNDE_N.md`) und den Plan
(`docs/PLAN_RUNDE_N.md`) gelesen. Das Meiste darin kann ich **ohne dich**
machen: Phase 0 bis 3 (lesen, die Werkzeuge fertig bauen, die Mathematik gegen
eine bekannte Wahrheit messen, die böse Saison durch die Oberfläche jagen)
brauchen keine Entscheidung von dir — das ist Messung. Und fast jede Reparatur
in Phase 4 hat genau eine richtige Antwort (negative Lagertage sind nie
plausibel, der Zeitzonen-Fehler in `mv_auftrag_masse`, die Achse ab null) —
die baue ich einfach.

Es bleiben **drei Weggabelungen**, bei denen deine Antwort ändert, was ich
baue. Nur die stehen hier.

---

## 1. Wie weit soll ich in einem Zug gehen?

Der Plan hat drei grosse Blöcke, und der letzte ist mit Abstand der grösste:

| Block | Was | Aufwand |
|---|---|---|
| **A — Der Fehler** | Die verzerrte Achse (bis −1000 Tage) an der Wurzel und im Diagramm reparieren, dazu die anderen kleinen Reparaturen | überschaubar |
| **B — Die Mathematik** | Prüfen, ob die Formeln die **richtigen** sind (nicht nur richtig gerechnet); die Unsicherheitsbänder | mittel |
| **C — Das Aussehen** | Das ganze neue Erscheinungsbild, Bildschirm für Bildschirm | gross (der Löwenanteil) |

**Meine Frage:** Soll ich alles drei in einem Zug machen und am Ende einen
grossen Stand abliefern? Oder erst A (der Fehler, den du gemeldet hast) fertig
und dir zeigen, dann B, dann C? Ich neige zu **A, dann B, dann C in getrennten
Schritten** — dann siehst du den behobenen Fehler früh und das Aussehen zuletzt.

> Antwort:

---

## 2. Die sortierte Palette bei der Lagerkontrolle

Das ist der Punkt, den ich **nicht selbst erfinden kann**, weil er von eurem
Ablauf abhängt (im Plan N-07, in `docs/FRAGEN.md` Frage 57).

Nach dem Sortieren stehen die Kürbisse auf neuen Paletten: Kaliber, Kistenzahl
und Sortierdatum kennt ihr, das Eingangsgewicht und das Eingangsdatum nicht
mehr. Die App verlangt bei „Palette kontrollieren" aber beides. Heute geht das
nur, indem jemand etwas einträgt, das er nicht weiss — und daraus wird eine
falsche Verdunstungsrate.

**Meine Frage:** Wiegt ihr sortierte Paletten überhaupt noch einmal nach? Wenn
ja — wollt ihr daraus nur wissen, **wie viel faul** ist, oder auch, **wie viel
noch da** ist? Danach richtet sich, ob ich einen dritten Weg in die Maske baue
(„Palette ohne Zettel — nach dem Sortieren") und was er speichert. Sagst du
nichts, **lasse ich es weg** und melde nur den falschen Fall als Auffälligkeit.

> Antwort:

---

## 3. Das Aussehen: erst ein Musterbildschirm, oder gleich alle?

Das neue Erscheinungsbild („edle, teure Software") ist Geschmack, und es
berührt jeden Bildschirm. Wenn ich die Richtung an fünfzehn Bildschirmen falsch
treffe, ist viel Arbeit umsonst.

**Meine Frage:** Soll ich **einen** Bildschirm (etwa den Überblick) komplett
neu machen und dir zeigen, bevor ich den Rest angehe? Oder gleich alle nach der
Vorlage (`docs/DESIGN_RUNDE_N.md`) durchziehen? Ich neige zu **erst ein Muster
zur Abnahme** — dann stelle ich nicht fünfzehn Bildschirme auf einen Geschmack
um, den du vielleicht anders willst.

> Antwort:

---

## Was ich ohne deine Antwort einfach so mache (kein Handlungsbedarf)

Damit du siehst, was ich **nicht** frage, weil es eine klare Vorgabe hat:

- **Zetteldatum in der Zukunft** (Frage 59): Ich lasse es speichern und **warne**
  nur („liegt in der Zukunft — Jahr prüfen"). Das ist die Linie des Programms:
  es zeigt, es hindert nicht. Sag Bescheid, wenn du lieber sperrst.
- **Der 2029-Zettel bleibt 2029**, bis du ihn korrigierst. Ich repariere nur,
  was die Auswertung daraus macht.
- **Die Unsicherheitsbänder** rühre ich nur an, wenn Phase 2 mit Zahlen zeigt,
  dass sie nachweislich zu weit oder zu eng sind — nicht auf Verdacht.
- **Die Grenze für „unmögliche Palette"** (Auffälligkeit) setze ich bei über
  2 000 kg oder unter 50 kg brutto; das lässt sich später leicht ändern.
- **Sortierte Paletten als Ding im Bestand** (Frage 58) baue ich **nicht** —
  das wäre eine neue Tabelle und ein neuer Bildschirm, und der Plan sagt: die
  App nicht komplizierter machen. Falls ihr das wirklich braucht, ist es eine
  eigene Runde.

Sobald du 1 bis 3 beantwortet hast, starte ich.
