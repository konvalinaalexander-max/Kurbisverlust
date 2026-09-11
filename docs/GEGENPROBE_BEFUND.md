# Gegenprobe — der Befund der Runde N

Diese Runde hat die App **mit Werkzeugen geprüft, die ihr nicht gehören**: einer
zweiten Rechnung aus den Rohtabellen (`gegenprobe/orakel/`), einer bösen Saison
mit zwölf Fällen wie aus einem echten Herbst (`gegenprobe/bildschirm/`),
Drehbüchern, die einen Tag in der Halle Szene für Szene gegen die Datenbank
spielen (`gegenprobe/drehbuecher/`), und der Simulationsmatrix, die Saisons mit
selbst gesetzter Wahrheit rechnet (`supabase/test/simulation/`). Was sie fanden,
steht hier — mit Zahl, und mit der Prüfung, die es jetzt hält.

## 1. Was gemessen wurde, mit Befehl

```
node gegenprobe/lauf.mjs --db demo          # Orakel gegen die Demo: 41/41
node gegenprobe/lauf.mjs --db boese         # gegen die böse Saison: 41/41
node gegenprobe/drehbuecher/spieler.mjs 01  # eine Charge ganz durch: 8/8
node gegenprobe/drehbuecher/spieler.mjs 02  # der Zettel von 2029: 3/3
node gegenprobe/bildschirm/invarianten.mjs                      # Demo:  0 Achsen-Verstösse
PRUEFSTAND_DATEN=gegenprobe/bildschirm/daten node …/invarianten.mjs   # böse: 0 Achsen-Verstösse
supabase/test/simulation/matrix.sh 15       # Verzerrung und Überdeckung, neun Lagen
supabase/test/run.sh …                      # DB-Suite 7/7, setup.sql deckungsgleich
npm run pruefen                             # tsc + 90 Tests + Build
```

## 2. Was repariert wurde

### N-01 — Negative Lagertage sind nie plausibel *(der gemeldete Fehler)*
Ein Zettel mit dem Jahr 2029 ergab negative Lagertage, die als plausibel galten
und die x-Achse eines Diagramms bis −1000 zogen. `v_schimmel_beobachtung` prüfte
nur den Anteil, nie das Vorzeichen der Zeit. **Reparatur (0070):** plausibel nur
bei `lagertage >= 0`, im Wasch-Zweig von `v_schimmel_punkte` ebenso. Der Punkt
bleibt gespeichert (Beobachtung), fällt aber aus Kurve, Treppe und Kaskade.
**Prüfung:** K7 auf der bösen Saison (grün), Drehbuch 02 S2 (grün), Block in
`pruefung.sql`.

### N-02 — Das Diagramm folgt den Daten, nicht einem Ausreisser *(der gemeldete Fehler, Diagramm-Seite)*
`Linien` nahm `Math.min(...alleX)` als Achsenanfang — ein einzelner Punkt riss
die Achse an sich. **Reparatur:** `src/lib/achse.ts` kennt die Einheit
(Lagertage nie < 0, Prozent 0…100) und wirft einen Alleinherrscher aus der
Achse; er steht als Satz unter dem Bild. Betrifft **jedes** Diagramm mit
Lagertagen, nicht nur den Palox. **Prüfung:** `test/diagramm.test.ts` (6 Fälle),
`invarianten.mjs` findet auf Demo **und** böser Saison keinen Achsen-Verstoss.

### N-03/N-06 — Nur plausible Punkte im Bild
Ursachen zeichnete alle Palox-Punkte, auch den Zettel von 2029 und Anteile über
der halben Masse. **Reparatur:** nur plausible Punkte, mit Zähl-Hinweis und
Sprung zu Messungen. Die Verdunstung zeigt nur echte Verlust-Wägungen (eine
schwerer gewordene Palette steht nicht als negativer Punkt auf dem „verloren"-Bild).

### N-05 / sortierte Palette — die Datenbank-Korrektheit, die der Betrieb verlangt hat
Entscheidung des Betriebs: sortierte Paletten werden **nicht** als
Lagerkontrolle gewogen — das Gewicht nach dem Sortieren kennt niemand.
**Reparatur (0070):** Eine Wägung, deren Netto auf das Gramm gleich geblieben
ist (Rate exakt null — ein kopiertes Eingangsgewicht), ist nicht verwendbar;
eine kleine Zunahme durch Waagenrauschen bleibt es (0056). Dazu zwei neue
Auffälligkeiten: ein Eingangsdatum in der Zukunft und eine Palette über 2000 kg.
**Prüfung:** Drehbuch 01 S6 (grün), böse Saison, `pruefung.sql`.

### N-09 — Zukunftsdatum: warnen, nicht sperren
Der Zähler warnt bei einem Eingangsdatum in der Zukunft (alle sechs Sprachen),
speichert aber trotzdem — die Beobachtung bleibt, die Auffälligkeit meldet sie.
Das ist die Linie des Programms (Frage 59).

## 3. Was mit Messung zurückgestellt wurde

### N-03b/N-04 — Betriebstag und Sortier-Eingang hinter dem 51-Objekt-Cascade
`mv_auftrag_masse` rechnet die Lagertage noch mit dem UTC-Tag statt dem
Betriebstag, und `mv_sortier_eingang` mittelt die Eingangsdaten der sortierten
Paletten (ein falsches Jahr zieht den Mittelwert mit). Beide sind **gespeicherte**
Sichten; `drop … cascade` nähme 51 weitere Objekte mit, praktisch das ganze
Rechenwerk. 0067 hat genau das gemessen: von 309 Arbeiten fallen bei fünf
UTC-Tag und Betriebstag auseinander, und die ganze Auswertung ergibt danach
dieselben Zahlen bis auf den Rappen. Der falsche Zettel wird jetzt als
Auffälligkeit gemeldet (N-01) und aus der Statistik gehalten; die verbleibende
Wirkung ist, dass die **angezeigten** Lagertage eines mitbetroffenen Waschgangs
daneben liegen, bis der Betriebsleiter das Jahr berichtigt. K7 auf der bösen
Saison ist deshalb so gefasst: kein plausibler Punkt mit negativer Zeit (hart),
und jede Arbeit mit negativer Zeit ist als Auffälligkeit sichtbar.

## 4. Ist es die richtige Mathematik? (Phase 2, mit Zahl)

Die Simulationsmatrix rechnet Saisons, deren wahre Koeffizienten wir gesetzt
haben, und stellt Schätzung gegen Wahrheit. **Rangfolge der Ursachen: in allen
neun Lagen zu 100 % richtig getroffen.** Verzerrung und Überdeckung je Strom
(Auszug, 15 Saisons je Lage):

| Lage | Verdunstung | Schimmel | zu klein | Nebenkanal | Überdeckung Schimmel |
|---|---|---|---|---|---|
| Saisonende, 25 % im Lager | +2.5 % | −1.3 % | 0.0 % | −0.1 % | 93 % |
| Mitten, 50 % im Lager | +2.0 % | −1.0 % | 0.0 % | +0.4 % | 87 % |
| Schlechtes zuerst (Auswahl) | −1.2 % | +0.5 %…+10 % | +0.2 % | +0.1 % | 87–100 % |
| Knappe Stichprobe (4 Wägungen) | +2.9 % | −0.8 % | −0.1 % | +0.3 % | 100 % |
| **2 % Sockel im Palox** | −3.8 % | **+21.2 %** | +0.5 % | +0.3 % | **47 %** |

Die vier Fragen der Phase 2:

- **(a) Halten die Bänder (Überdeckung ≥ 90 %)?** Für Verdunstung, Ausschuss,
  Nebenkanal und die Rate durchweg ja (93–100 %) — eher konservativ, die Bänder
  sind breit (FPF-001 aus Runde M: `min(df)` macht sie zu weit). **Nein** für
  den Schimmel, wenn ein **echter Palox-Sockel** vorliegt: dort mischt das
  Modell Sockel und Schimmel, der Schimmel wird um 21 % zu hoch geschätzt und
  das Band überdeckt nur zu 47 % (**N-14**, siehe unten).
- **(b) Ist die Sockel-Wahl bei a0 = 0 unverzerrt?** Ja. Bei wahrem Sockel 0
  setzt das Modell in **0 %** der Läufe einen Sockel — keine falschen Positiven.
  (Bei kleinem echtem Sockel unterschätzt es ihn dagegen, siehe N-14.)
- **(c) Trägt die Schrumpfung bei wenig Daten?** Ja. „Knappe Stichprobe: nur 4
  Wägungen" → Verdunstung +2.9 % Verzerrung, Band entsprechend breit (90 %),
  Überdeckung 100 %.
- **(d) Bleibt die Rate im Band?** Ja, `r_wahr_mittel` überdeckt 93–100 % in
  allen Lagen.

### N-14 — Schimmel und Palox-Sockel lassen sich mit wenig Daten nicht sauber trennen
**Belegt, nicht repariert.** Liegt ein echter Grund-Aussortierungssockel im
Palox (Erde, Hagelnarben — nicht lagerbedingt), schreibt das Modell einen Teil
davon dem Schimmel zu: Verzerrung +21 %, Bandüberdeckung 47 % statt 95 %. Der
Sockel-Schätzer (`v_schimmel_modell`, Runde H/M) mildert das, löst es aber bei
wenigen Chargen nicht. Eine bessere Trennung hängt am Verderbsmodell, das hinter
demselben 51-Objekt-Cascade sitzt wie N-04, und ist ein eigener, statistisch
schwerer Schritt — sie gehört in eine eigene Runde, nicht in diese. Das Band
wird deshalb **nicht** neu gerechnet: es zu verengen ohne die Trennung zu
verbessern würde die Überdeckung nur weiter senken. `gegenprobe/orakel/band.ts`
(Delta-Methode mit voller Kovarianz) ist der Massstab, an dem eine künftige
Runde das misst.

## 5. Kein Fehler — nachgesehen und in Ordnung

- **Das Orakel und die Datenbank stimmen überein**, Zeile für Zeile, auf Demo
  und böser Saison: Masse (Rückgrat, Kohorten), Verdunstung je Wägung,
  Schrumpfung (vier Arten × alle Sorten), Verderbsmodell (24 Kenngrössen und
  die Kurve an 43 Stellen), Kaskade (jede Zeile, jeder Strom) samt den
  Invarianten K1–K7. Die Formeln werden also so gerechnet, wie sie dastehen.
- **Doppelte Lieferung** (böse B3): Überzählung 1696 kg ausgewiesen, K1 hält,
  Auffälligkeit da. **Lieferung vor dem Eingang** (B6): alter_tage 0, K3/K4
  halten. **Nachts um halb eins** (B8): 1 Lagertag (Betriebstag). **Am selben
  Tag** (B12): keine Rate aus null Tagen, kein Absturz. **Schwerer geworden**
  (B2): nicht verwendbar, gemeldet, Rate ≥ 0.
- **Die Hauptursache wird in jeder Lage richtig erkannt** (100 %) — der
  Betriebsleiter bekommt die richtige Reihenfolge, an der eine Entscheidung hängt.

## 6. Das Erscheinungsbild

Siehe `docs/DESIGN_RUNDE_N.md` und die Bilder in `pruefstand/bilder/`. Kern:
ein warmes, sehr helles Neutral statt kühlem Grau, Karten mit feiner Kontur und
flacher Tiefe statt harter Rahmen, ruhige Bewegung (Eintritt, Zahl läuft hoch,
Linie zeichnet sich), Zeichen statt Emoji. Struktur, Reiter, Grafiken und Zahlen
bleiben, wo sie waren — nur das Auftreten ist neu. Begriffs-Prüfstand und
Invarianten grün, keine neue Abhängigkeit.

## 7. Für den Betriebsleiter

Der Fehler, den du gemeldet hast, ist weg: Ein Zettel mit dem falschen Jahr
verzieht kein Diagramm mehr und rechnet nicht mit — er wird stattdessen unter
Messungen als „Zetteldatum Zukunft" gemeldet, du korrigierst das Jahr, und alles
rechnet sich richtig. Sortierte Paletten wiegst du nicht mehr als
Lagerkontrolle; tut es doch jemand mit einem erfundenen Gewicht, zählt die
Wägung nicht. Und die App sieht jetzt aus wie ein Werkzeug, für das man Geld
ausgibt. Was du entscheiden musst, steht in `docs/FRAGEN.md` (Fragen 57–59, zwei
davon sind mit dieser Runde schon entschieden).
