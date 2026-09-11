# Plan Runde N — die Gegenprobe, die Wirklichkeit, das Erscheinungsbild

Dieser Plan ist von einer KI für eine andere geschrieben. Die erste hat die
Werkzeuge entworfen und angelegt (`gegenprobe/`, `src/design/`), die
Erwartungen aufgeschrieben und die ersten Befunde gemessen. Die zweite führt
aus: baut die Werkzeuge fertig, lässt sie laufen, repariert, gestaltet neu,
berichtet. Der Auftrag an sie steht in `docs/PROMPT_RUNDE_N.md`; hier steht
das **Warum** und das **Wie**, mit Toren zwischen den Phasen.

## 0. Der Anlass, in drei Sätzen

Der Betrieb hat gemeldet: *Bei Ursachen → Faules ist das Diagramm komplett
verzerrt, die x-Achse geht bis minus tausend Tage, alle Punkte sitzen als
ein Strich ganz rechts.* Zwölf Runden Prüfwerkzeuge haben das nicht
gesehen, weil sie alle mit **braven** Daten prüfen und alle mit den
**Begriffen des Prüflings** rechnen. Und der Betrieb hat gefragt, ob die
App die Praxis nach dem Sortieren überhaupt abbilden kann — die Kisten
stehen dann auf neuen Paletten, ohne Eingangsgewicht und ohne Eingangsdatum.

## 1. Was schon da ist (11. September)

| Teil | Stand | Datei(en) |
|---|---|---|
| Formelabzug aller 145 Rechenobjekte, deterministisch | fertig, gelaufen | `gegenprobe/orakel/formeln_holen.mjs`, `formeln/`, `MANIFEST.md` |
| Orakel: Masse, Verdunstung, Schrumpfung, Verderbsmodell, Kaskade | fertig, 24 Handfälle grün | `gegenprobe/orakel/{zahlen,masse,verdunstung,varianz,schimmel,kaskade}.ts` |
| Orakel gegen die Datenbank, K1–K4 + K7 | fertig; **demo: 6/6 grün, böse Saison: K7 rot** (gewollt) | `gegenprobe/orakel/gegen_db.test.ts`, `bilanz.ts` |
| Bilanz K6 (Saisonbilanz geschlossen) | Gerüst, wirft „noch nicht gebaut" | `bilanz.ts` |
| Achsenregeln A1–A6, `achsenBereich()` | fertig, 8 Fälle grün, der Betriebsfall als Test | `gegenprobe/bildschirm/achse.ts`, `achse.test.ts` |
| Die böse Saison, 12 Fälle B1–B12 mit Erwartungen E1–E14 | fertig, geladen, vermessen (unten) | `gegenprobe/bildschirm/boese_saison.sql` |
| Browser-Invarianten I1–I11 | läuft: Demo 3 Verstösse (N-11) + 2 Hinweise (Datumsachsen), böse Saison 7 Verstösse — darunter **I5/I6 auf „Palox: Faules im Lager"**, der Betriebsfall; Datumsachsen brauchen den SVG-Vertrag aus Phase 1 | `gegenprobe/bildschirm/invarianten.mjs` |
| Drehbuch-Format, Spieler | fertig | `gegenprobe/drehbuecher/FORMAT.md`, `spieler.mjs` |
| Drehbuch 01 (eine Charge ganz durch), 02 (der Zettel) | geschrieben, gespielt (unten) | `01_…md`, `02_…md` |
| Weitere Drehbücher 03–11 | angerissen | `WEITERE.md` |
| Designsystem: Zeichen, Bewegung | geschrieben, **nicht eingebunden** | `src/design/tokens.css`, `bewegung.css`, `docs/DESIGN_RUNDE_N.md` |
| Läufer | fertig | `npm run gegenprobe [-- --db name]` |

## 2. Was die neuen Werkzeuge schon gefunden haben

Gemessen, nicht vermutet. Jede Zeile hat eine Prüfung, die sie zeigt.

| Nr | Befund | Woher | Schwere |
|---|---|---|---|
| N-01 | **Negative Lagertage sind plausibel.** `v_schimmel_beobachtung` prüft mit `anteil_plausibel()` nur den Anteil; das Vorzeichen der Zeit prüft niemand. Ein Zettel mit dem Jahr 2029 ergibt einen Punkt bei −1053 Tagen, plausibel, in Kurve, Treppe und Kaskade. | K7 auf der bösen Saison; Drehbuch 02 S2 (rot) | hoch — das ist der Betriebsfall |
| N-02 | **Das Diagramm gibt einem einzelnen Punkt die ganze Achse.** `Linien` nimmt `Math.min(...xs)` als Achsenanfang; keine Einheit, keine Robustheit. Betroffen ist nicht nur „Palox: Faules im Lager", sondern jedes Diagramm mit Lagertagen — auf der bösen Saison zeigt Messungen → „Wird das Älteste zuerst verarbeitet?" eine x-Achse ab −1500 (I5) mit einem Punkt bei −1059, der sie bestimmt (I6). | `achse.test.ts` „Der Fall vom Betrieb"; I5/I6 auf der bösen Saison | hoch |
| N-03 | **Der falsche Zettel vergiftet die Wäsche.** `mv_sortier_eingang` mittelt die Eingangsdaten der sortierten Paletten; mit der 2029-Palette bekommt der spätere Wasch-Auftrag −137.7 Lagertage. | K7: „Arbeit 313 (waschen)" | mittel |
| N-04 | **`mv_auftrag_masse` rechnet Lagertage mit `a.start_ts::date`** (UTC-Tag), nicht mit `betriebstag()`. 0067 hat fünf Stellen umgestellt, diese nicht; `b5_zeit` prüfte nur `v_verdunstung_messung`. | Formelabzug, `grep '::date' gegenprobe/orakel/formeln` | mittel — Arbeiten nach 22:00 Ortszeit bekommen einen Tag zu wenig |
| N-05 | **Keine Auffälligkeit für eine unmögliche Palette.** 99 999 kg brutto (B7) läuft ohne Satz durch; die Charge hat 100 369 kg Eingang. | böse Saison, `erg_plausibilitaet` leer für 9906 | mittel |
| N-06 | **Faules über der Basis kommt bis ins Diagramm.** B5 (214 %) ist richtig `plausibel = false`, aber die Ursachen-Seite zeichnet alle Punkte mit `quelle = 'verarbeitung'`, ohne Filter. Zu prüfen mit I5 (y bis 214 %). | böse Saison; `Ursachen.tsx` Zeile ~168 | mittel |
| N-07 | **Die Lagerkontrolle an einer sortierten Palette geht nicht.** Die Maske verlangt Zettel-Datum und Zettel-Brutto; nach dem Sortieren gibt es beides nicht. Der Umweg (Sortierdatum als Eingang) macht eine Rate aus 8 statt 38 Tagen. | Drehbuch 01 S6 | hoch für den Betrieb — Frage 57 |
| N-08 | **Die Wäsche nach dem Sortieren hat keine Masse**, wenn für das Kaliber nie mitgezählt wurde („Kistengewicht unbekannt"). Richtig nach „leer ist nicht null" — aber der Betriebsleiter sieht nur „fehlt". | böse Saison B9, `v_auftrag_masse` 313 | niedrig — Beschriftung |
| N-11 | **Die Marke ist auf dem Handy abgeschnitten.** `span.name` im Kopf („Kürbis kontrollieren") läuft auf 390 px in die Ellipse — auf Start, Neu und Kontrolle. | I7 auf Demo und böser Saison | niedrig — Phase 5 (Kopf) |
| N-12 | **Zu prüfen:** Messungen → „Wird das Älteste zuerst verarbeitet?" trägt Lagertage auf der **y**-Achse; auf der bösen Saison bestimmt dort der Punkt bei −1059 die Achse (I6). Dasselbe Mittel wie N-02 (`achsenBereich`, Einheit `'tage'`). | I6 auf der bösen Saison | mit N-02 |
| N-13 | **Ein Punkt ausserhalb des Rahmens wird stumm weggeschnitten.** Ursachen → „Verdunstung" zeichnet die nicht verwendbare Wägung B2 (Rate −0.14 %/Tag → −5.4 %) unter die Null; der Rahmen schneidet sie ab, niemand sieht sie. Entweder nur verwendbare Wägungen zeichnen (und die anderen als Satz nennen) oder die y-Achse bis zum Minimum öffnen. | I4 auf der bösen Saison | niedrig |
| N-09 | **Kein Fehler:** Lieferung vor dem Eingang (B6) → alter_tage 0, K3/K4 halten. Doppelte Lieferung (B3) → Überzählung 1696 kg, K1 hält, Auffälligkeit da. Halb eins (B8) → 1 Lagertag. Am selben Tag (B12) → keine Rate, kein Absturz. Schwerer geworden (B2) → nicht verwendbar. | böse Saison | — |
| N-10 | **Kein Fehler:** Orakel und Datenbank stimmen auf Demo und böser Saison in allen 6 Vergleichen überein — Rückgrat, Kohorten, Verdunstung je Wägung, Schrumpfung (4 Arten × alle Sorten), Verderbsmodell (24 Kenngrössen, Kurve an 43 Stellen), Kaskade (jede Zeile, jeder Strom). | `gegen_db.test.ts` | — die Formeln werden so gerechnet, wie sie dastehen |

Aus Runde M bleiben offen (docs/WERKSTATTBERICHT.md): FPF-001 (Band 6.3× zu
weit durch `min(df)`), AUF-001 (Delta-Methode unterschätzt σ des Schimmels
3.9×), STU-001 (kette.mjs winkt 5 % durch). Runde N nimmt FPF-001/AUF-001
in Phase 2 mit dem Orakel als Massstab wieder auf.

## 3. Die Phasen und ihre Tore

Ein Tor ist ein Befehl, dessen Ausgang entscheidet. Kein Tor, kein Weitergehen.

### Phase 0 — Lesen und Grundlinie (½ Tag)
- Lesen: `docs/PROMPT_RUNDE_N.md`, diesen Plan, `gegenprobe/README.md`, `docs/DESIGN_RUNDE_N.md`, `docs/PLAN_RUNDE_M.md`, `docs/ENTSCHEIDUNGEN.md` (Runden L, M), `docs/ABLAUF.md`, `docs/UI-KONZEPT.md`.
- Grundlinie: `npm run pruefen`, `supabase/test/run.sh`, `npm run gegenprobe -- --db demo`, `node pruefstand/bildschirme.mjs` (Bilder als „vorher" aufheben).
- Formeldrift: `node gegenprobe/orakel/formeln_holen.mjs && git diff --stat gegenprobe/orakel/formeln` — muss leer sein. Ist es das nicht, hat sich seit dem Abzug eine Formel bewegt: erst verstehen, dann weiter.
- **Tor 0:** alles grün, Drift leer.

### Phase 1 — Die Werkzeuge fertig bauen (1 Tag)
1. `bilanz.ts` K6: Spalten von `erg_massenbilanz` zuordnen; Eingang = geliefert (alle Bücher) + Verlust + im Haus je Gruppe; in `gegen_db.test.ts` aufnehmen.
2. `invarianten.mjs` I3–I6: Jedes `Linien`-Diagramm bekommt `xEinheit`/`yEinheit` (Vorgabe `'frei'`) und schreibt sie als `data-x-einheit`/`data-y-einheit` ans SVG; der Prüfstand liest sie statt zu raten. Dazu Klassen `linie`, `marker`, `balken`, `band` an den SVG-Elementen (braucht Phase 5 sowieso).
3. Ein Orakel für die **Unsicherheitsbänder** (`orakel/band.ts`): die Varianz einer Summe von Strömen als Delta-Methode mit **voller** Kovarianz über r, f (η), a, a0 — der Massstab, an dem FPF-001 und AUF-001 gemessen werden. Handfall: zwei Ströme mit bekannter Kovarianz.
4. Drehbücher 03, 05, 07, 09 ausschreiben (die anderen, wenn Zeit bleibt).
5. Jedes neue Werkzeug mit **Selbstprobe**: ein eingebauter Fall, in dem es anschlagen muss (wie `achse.test.ts` „Der Fall vom Betrieb").
- **Tor 1:** `npm run gegenprobe -- --db demo` grün bis auf K6 (falls es echt rot ist: Befund, nicht Tor). `node gegenprobe/bildschirm/invarianten.mjs` läuft auf Demo mit 0 Verstössen — oder jeder Verstoss ist ein eingetragener Befund.

### Phase 2 — Die Mathematik befragen (1 Tag)
Das Orakel bestätigt, dass die Formeln gerechnet werden, wie sie dastehen. Jetzt die andere Frage: **sind es die richtigen Formeln?** Für jede der fünf Rechnungen:
- Ein synthetischer Datensatz mit **bekannter Wahrheit** (Weibull mit λ, k, a0; Verdunstung mit r je Sorte; Kaskade mit gesetzten Strömen), erzeugt in TypeScript, in eine Prüf-Datenbank geladen (wie `boese_saison.sql`, aber `wahre_saison.sql`, generiert), durchgerechnet — und die Schätzung gegen die Wahrheit gehalten. Verzerrung und Bandüberdeckung (liegt die Wahrheit in 95 % der Bänder?) als Zahl.
- Konkrete Fragen mit Antwort ja/nein: (a) Überdeckt das Band der Kaskade die Wahrheit in ≥ 90 % der Fälle? (FPF-001/AUF-001) (b) Ist die Sockel-Wahl bei a0 = 0 unverzerrt (findet sie nicht systematisch 0.0025)? (c) Ist tau² bei drei Sorten mit je zwei Chargen brauchbar oder immer 0? (d) Bleibt die Rate mit 5 % Deckel bei einer vergifteten Sorte (Drehbuch 04) im Band?
- **Tor 2:** eine Tabelle Rechnung × Frage × Antwort × Zahl in `docs/GEGENPROBE_BEFUND.md`. Jede Nein-Antwort ist ein Befund mit Vorschlag, keiner wird still repariert.

### Phase 3 — Die böse Saison durch die Oberfläche (½ Tag)
- `PRUEFSTAND_DATEN=gegenprobe/bildschirm/daten node gegenprobe/bildschirm/invarianten.mjs` — **muss rot sein**: mindestens I5/I6 auf „Palox: Faules im Lager" (x-Achse), vermutlich I5 auf der y-Achse (214 %), vielleicht I1 irgendwo. Ist er grün, sind die Regeln blind — zurück zu Phase 1.
- Bilder aller Seiten mit der bösen Saison (`PRUEFSTAND_DATEN=… node pruefstand/bildschirme.mjs`) in den Bericht.
- **Tor 3:** die Liste der Verstösse, jeder einem Befund N-xx zugeordnet.

### Phase 4 — Reparieren, jede mit roter Prüfung zuerst (1–2 Tage)
Reihenfolge nach Schwere. Für jede: die Prüfung, die heute rot ist, benennen; reparieren; sie wird grün; nichts anderes wird rot.

| Reparatur | Rote Prüfung vorher | Wo |
|---|---|---|
| N-01 Negative Lagertage nie plausibel; `v_plausibilitaet` sagt „Eingangsdatum liegt nach der Arbeit — Jahr prüfen" | K7 böse, Drehbuch 02 S2 | Migration 0070: `v_schimmel_beobachtung` (`plausibel := anteil_plausibel(…) and lagertage >= 0`), `v_verdunstung_messung`-Text, `v_plausibilitaet` |
| N-03 `mv_sortier_eingang` lässt Paletten mit Eingangsdatum > Arbeitstag aus der Mittelung | K7 „Arbeit 313" | 0070 |
| N-04 `betriebstag(a.start_ts)` in `mv_auftrag_masse`; `b5_zeit` prüft **alle** Sichten auf `_ts::date` | neue Zusicherung in `pruefung.sql`: kein `::date` auf einem timestamptz in irgendeiner Sicht | 0070, `werkstatt/b_fundament/b5_zeit.mjs` |
| N-02 `Linien` nimmt `achsenBereich(werte, einheit)`; ausgeschlossene Punkte als Satz unter dem Diagramm mit Sprung zu Messungen; Props `xEinheit`/`yEinheit` an **allen** Aufrufen (Lagertage, %, kg, Datum) | I5/I6 böse; neuer Modultest `test/diagramm.test.ts` für die reine Bereichsfunktion (Import aus `src/lib/achse.ts` — `gegenprobe/bildschirm/achse.ts` wird dorthin **kopiert**, nicht importiert: das Orakel bleibt unabhängig) | `Diagramm.tsx`, `Ursachen.tsx`, `Ueberblick.tsx`, `Chargen.tsx`, `Messungen.tsx` |
| N-06 Ursachen zeichnet nur plausible Punkte; unplausible als Satz „n Messungen nicht plausibel (Charge …)" | I5 y-Achse böse | `Ursachen.tsx` |
| N-05 Auffälligkeit „Palette schwerer als 2 000 kg / leichter als 50 kg" | Drehbuch B7-Prüfung (neu in 03 oder als K8 in `bilanz.ts`) | 0070 `v_plausibilitaet` |
| N-08 Text „Kistengewicht unbekannt — beim Sortieren dieses Kalibers einmal mitzählen" statt „fehlt" | Begriffs-Prüfstand | `Chargen.tsx`, i18n |
| Zähler-Maske: Datum nach heute → Hinweis „liegt in der Zukunft — Jahr prüfen", speichern erlaubt | Bildschirm-Szene `zaehler-zukunft` | `src/arbeit/Zaehler.tsx` |
| FPF-001/AUF-001 nach Phase 2, **nur** wenn das Orakel die bessere Formel bestätigt | Bandüberdeckung < 90 % | 0070 oder 0071, `v_verlust_je_gruppe` |

N-07 (Lagerkontrolle ohne Zettel) ist **keine Reparatur** — es ist ein neuer
Weg in der Maske und damit Frage 57 an den Betrieb. Vorbereiten (Entwurf
in `docs/DESIGN_RUNDE_N.md` §5 Kontrolle), nicht bauen, bis die Antwort da ist.

- **Tor 4:** `npm run pruefen`, `run.sh`, `npm run gegenprobe -- --db demo` **und** `-- --db boese` grün (böse: K7 grün, weil repariert), Drehbücher 01 und 02 alle Prüfungen ok, `invarianten.mjs` auf Demo und böser Saison 0 Verstösse, `setup.sql` neu gebaut (`supabase/setup_bauen.sh`), `SCHEMA_ERWARTET` hoch.

### Phase 5 — Das Erscheinungsbild (2 Tage)
Genau nach `docs/DESIGN_RUNDE_N.md`. Reihenfolge: Zeichen einbinden
(`tokens.css` vor `index.css`, Werte dort ersetzen) → Rahmen und Reiter →
Überblick → Ursachen → Chargen → Messungen → Betrieb (mit Tagesgruppierung
der Arbeiten) → Arbeiter-App (Start, Assistent, Zähler, Abschluss,
Kontrolle) → Anmelden → Zeichen statt Emoji → Bewegung (`bewegung.css`,
`useZaehler`, `useEintritt`, SVG-Klassen) → Skelett statt Spinner.
Je Bildschirm: Bild vorher, Bild nachher, Begriffs-Prüfstand, Invarianten.
Die 170 inline-Stile werden zu benannten Klassen — jede Klasse ein Wort,
das sagt, was es ist (`.kennzahl-reihe`, `.filterleiste`, `.tag-trenner`).
- **Tor 5:** alle Bilder im Bericht (hell/dunkel × Handy/Rechner × jede Seite), `beschriftung.mjs` findet dieselben Begriffe, `invarianten.mjs` grün auf beiden Datensätzen, Kontrastmessung ≥ 4.5:1, Bündel ≤ +5 %, `npm run pruefen` grün, keine neue Abhängigkeit (`git diff package.json` zeigt nur das Skript).

### Phase 6 — Bericht, Entscheidungen, Fragen (½ Tag)
- `docs/GEGENPROBE_BEFUND.md`: Befunde N-01 …, je mit Werkzeug, Zahl, Reparatur oder Frage, Prüfung, die es hält. Tabelle „Kein Fehler" ausdrücklich.
- `docs/ENTSCHEIDUNGEN.md`: Abschnitt „Runde N" — warum die Achse die Einheit kennt, warum negative Zeit nie plausibel ist, warum der Formelabzug im Repository liegt, warum das Orakel nichts aus `src/` importiert, was am Erscheinungsbild bewusst gleich blieb.
- `docs/FRAGEN.md`: Frage 57 (Lagerkontrolle ohne Zettel), 58 (sortierte Palette als Ding im Bestand), 59 (Zukunftsdatum sperren oder nur warnen?); `docs/fragen.html` und PDF neu bauen (`docs/pdf_bauen.mjs`).
- `README.md`: Abschnitt Gegenprobe in der Werkzeugliste; „Wenn etwas klemmt": „Diagramm bis −1000 Tage".
- **Tor 6:** Commit, Push auf `claude/new-session-vrnnyo`, keine PR.

## 4. Was nicht passiert

- Kein Werkzeug aus `pruefwerk/`, `werkstatt/`, `pruefstand/` wird als Beweis zitiert, ohne dass die Gegenprobe dasselbe unabhängig zeigt. Sie laufen weiter (sie halten Zusagen), aber sie sind nicht der Massstab dieser Runde.
- Keine Tabelle, keine Spalte wird gelöscht; keine Migration ändert gespeicherte Beobachtungen (die 2029-Zettel bleiben 2029, bis der Betriebsleiter sie korrigiert).
- Kein neuer Bildschirm, kein neuer Reiter, keine neue Frage an den Arbeiter — ausser der Betrieb beantwortet Frage 57 mit ja, und dann in einer eigenen Runde.
- Kein Test wird abgeschaltet, abgeschwächt oder mit `skip` versehen, um grün zu werden. Übersprungen wird nur, was keine Datenbank hat, und das wird gezählt.
- Keine neue Abhängigkeit in `package.json`.
- Kein Modellbezeichner in Code, Kommentaren, Commits.
