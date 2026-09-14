# Befund Runde Q — Zwischenstand

Stand: 14.09.2026. Die Phasen 0 bis 3 des Auftrags sind abgeschlossen, Phase 4
(Arbeiter-App) ist angefangen. Was hier nicht steht, ist nicht gebaut.

---

## 1. Grundlinie (Phase 0)

Alles war vorher grün:

| Prüfstand | Ergebnis vorher |
|---|---|
| `npm run pruefen` | typecheck, 96 Tests, Build — grün |
| `supabase/test/run.sh` | alle sieben Stufen bestanden |
| `npm run gegenprobe --db demo` | 52 Fälle, 52 bestanden |
| `pruefstand/bildschirme.mjs` | 188 Aufnahmen, keine Konsolenfehler |

Die Bilder „vorher" liegen lokal in `pruefstand/bilder_vorher_q` (62 MB, nicht
eingecheckt — der Vergleich steht als Text hier).

---

## 2. Rot zuerst (Phase 1)

Prüfblock **0072** in `supabase/test/pruefung.sql`, geschrieben **vor** jeder
Änderung am Produktivcode, auf einer frischen Datenbank mit 0000–0071:

```
psql:supabase/test/pruefung.sql:4282: ERROR:  0072 (a1): 2 Ablesung(en)
rechnen gegen eine fremde Arbeit — Ablesung 625 (Arbeit 1320): vorher
310.00 statt ; Ablesung 21 (Arbeit 2100): vorher 165.00 statt
```

Rot aus dem richtigen Grund. Der volle Wortlaut steht in
`docs/rot_runde_q/0072_rot.txt`.

**Bemerkenswert:** Die Prüfung fängt nicht nur die zwei Arbeiten, die sie
selbst anlegt, sondern auch **Arbeit 2100 aus dem bestehenden Prüfdatensatz**.
Der Fehler ist keine Konstruktion — er steckt in Daten, die seit Runden dort
liegen und bei jedem Lauf mitgerechnet wurden.

---

## 3. Was gebaut ist

### Q1–Q4 · Der Palox (Migration 0072 + 0073)

Der gemeldete `−445`-Fehler saß an **zwei** Stellen, nicht an einer:

| Ort | Was falsch war |
|---|---|
| `PaloxMaske.tsx` | holte über `palox_letzter_stand(station)` den Stand einer **fremden Arbeit** und zog ihn ab |
| `v_palox_stand` | fensterte mit `partition by palox_station(a.station)` — dasselbe, in der Datenbank |

Die zweite ist die gefährlichere. Fällt der Anfangsstand, wird die Differenz
NULL und die Arbeit fällt aus der Rechnung — zufällig richtig. **Steigt** er,
weil zwischen zwei Arbeiten jemand etwas hineingeworfen hat, werden die
fremden Kilo stillschweigend dieser Arbeit als Fäulnis angelastet. Das sieht
niemand.

Gebaut:

- `v_palox_stand` fenstert über `s.auftrag_id`. Erste Ablesung einer Arbeit →
  `differenz = 0` (Nullpunkt), nicht `stand − tara`.
- **Die Tara kommt in der Sicht nicht mehr vor.** Sie kürzt sich in der
  Differenz heraus. `palox_tara_kg()` bleibt bestehen und steht nur noch als
  Hinweistext in der Maske. (Nebenbefund: sie stand bereits richtig auf 45 —
  der Auftrag behauptete 0, das war falsch.)
- `v_schimmel_menge` verlangt **zwei** Palox-Ablesungen. Eine einzige ist ein
  Startstand, kein Messwert; die Menge bleibt unbekannt statt 0.
- Neue Spalte `auftrag.palox_unbekannt`. Gesetzt, wenn der Stand fällt oder
  der Abschluss danach fragt. Die Ablesungen bleiben erhalten.
- `palox_stand_dieser_arbeit(auftrag_id)` — die Funktion, die die Maske ruft.
- `PaloxMaske.tsx` neu: Startstand wird als solcher angezeigt, ein gefallener
  Stand **fragt** („Ja, geleert" / „Nein, vertippt") statt zu schweigen und
  eine Null zu schreiben.

### Was das an Zahlen verschiebt

Gemessen an den Beispieldaten — **keine Aussage über den Betrieb**, nur über
die Grössenordnung der Änderung:

| | alte Formel | neue Formel |
|---|---|---|
| Arbeiten mit bekannter Palox-Menge | 132 | 128 |
| Summe | 10 705 kg | 8 159 kg |
| was die Beispieldaten meinten | 13 549 kg | 13 549 kg |

Beide Formeln verlieren Masse gegenüber dem, was gemeint war — die neue mehr.
Der Unterschied sind Arbeiten, bei denen die **Anfangsablesung fehlt**. Die
alte Formel füllte sie aus der Vorarbeit auf; die neue sagt „unbekannt". Das
ist genau die Änderung, um die es geht — und die Beispieldaten zeigen jetzt,
was eine vergessene Anfangsablesung kostet.

### Q5, Q6, Q9 · Der Gebindewechsel

- `auftrag_palette.gebindeart` — ohne sie ist beim Waschen keine Tara bestimmt.
- `auftrag.fertige_paletten_gesamt` — die Zahl, ohne die „3 rein, 4 raus" nicht
  rechenbar ist. **Nicht Pflicht** (der Betrieb: „die fertigen paletten werden
  eher nicht gezählt"); vorbelegt mit den gewogenen, überspringbar. Leer
  bleibt leer.
- `ausgang_wiegung.voll` — die letzte Palette ist oft nicht voll und darf den
  Koeffizienten kg-je-Kiste nicht nach unten ziehen.

### Q11 · Die Kontrollpalette

- Tabellen `kontrollpalette` und `kontrollpalette_wiegung` mit Zeilenregeln.
  Löschen einer Kontrollpalette nur durch den Admin — beenden heisst
  `beendet_ts` setzen.
- `v_kontrollpalette_rate`: je zwei aufeinanderfolgende Wägungen eine Rate
  **für den Zeitraum dazwischen**, mit `verwendbar` (kein sichtbarer Schimmel,
  mindestens sieben Tage Abstand, nicht schwerer geworden).
- `v_kontrollpalette_vorschlag`: die Chargen nach Eingangsmasse geordnet, mit
  der Angabe, ob schon eine darauf steht. Die fünf obersten sind der Vorschlag.
- **Nicht** in die Kaskade eingebaut. Erst erheben, dann entscheiden.

### Q12 · Das Alter sagt, woher es kommt

- `v_auftrag_masse` bekommt `alter_quelle` (`gemessen` · `sortiermittel` ·
  `chargenmittel`), `alter_spanne_tage` und `ernte_fertig`.
  `zwischenlager_tage` gab es schon.
- Neue Sicht `v_charge_erntespanne`: über wie viele Tage sich die Ernte einer
  Charge zieht und wie stark die Masse darüber streut (massegewichtete
  Standardabweichung). **Die App rechnet das selbst** — dafür braucht es kein
  Erntejournal von Hand.
- `charge.ernte_abgeschlossen_ts` und `einstellung('ernte_abgeschlossen')`:
  ab dann steht das mittlere Eingangsdatum fest.
- Als zusätzliche Spalten **am Ende** angehängt, damit `create or replace` die
  acht darüberliegenden Sichten nicht anfasst. **Keine bestehende Zahl ändert
  sich** — es kommt nur dazu, was man ihr bisher nicht ansah.

### Q15 · Die Erfassung wird unlöschbar

- `erfassung_journal` mit Auslöser auf **17 Tabellen**. Bei einem `delete`
  steht die ganze alte Zeile als `jsonb` darin. Niemand hat `update` oder
  `delete` auf dem Journal — auch der Admin nicht.
- Löschen einer Messzeile einer **abgeschlossenen** Arbeit: nur noch Admin
  (`arbeit_offen()` in den Zeilenregeln von `schimmel_messung`,
  `ausschuss_messung`, `ausgang_wiegung`).

### Q14 · Echtmodus und Beispielmodus

- `einstellung('betriebsmodus')`, Vorgabe `echt`.
- **Auslöser** `demo_nur_im_beispielmodus()` auf `palette` und `sortier_lauf`:
  eine Datenbank im Echtmodus nimmt keine Beispieldaten an — auch nicht über
  einen Umweg von Hand. Der Prüfstand belegt das ausdrücklich, statt den
  Schutz zu umgehen.

### Q20, Q21 · Aus den Antworten des Betriebs

- `kisten_pro_palette` von 32 auf **36** (nur dort, wo noch der ausgelieferte
  Vorgabewert stand — ein selbst gesetzter Wert wird nie überschrieben).
- Neue Einstellungen: `gebinde_lager` (G2), `fax_tage_vorgabe` (4),
  `kontrollpalette_tage_anfang` (14), `kontrollpalette_tage_spaeter` (30),
  `erfassung_scharf`, `letzte_sicherung`.

---

## 4. Bestehende Prüfungen, die rot wurden — und warum

Drei Stellen kodierten die alte Regel. Keine wurde abgeschwächt; die Zusagen
stehen unverändert, die **Annahmen** darunter sind ersetzt.

| Stelle | Was sie behauptete | Warum das nicht mehr gilt |
|---|---|---|
| „Schimmel #2", eine Palox-Ablesung | 165 brutto − 45 Tara = 120 kg | Eine Ablesung ist ein Startstand. Die Prüfung schreibt jetzt zwei (45 → 165) und erwartet dieselben 120 kg. |
| „Palox-Waage je Station" | „die Differenz läuft über beide Stationsnamen hinweg (195 − 165)" | Der Betrieb hat das widerrufen. Der Block prüft jetzt, dass eine neue Arbeit die Menge der Vorarbeit **nicht** verändert. |
| „Nach dem Leeren gilt der Stand ohne Behälter als Menge" | war eine Folgerung | Wie viel beim Leeren herausging, weiss niemand. Jetzt: unbekannt. |

Dazu zwei Funde, die der Prüfstand selbst gemacht hat:

- **`v_datenqualitaet` enthält `select a.* from auftrag a`.** Postgres friert
  den Stern beim Anlegen ein. 0072 gab `auftrag` zwei Spalten — damit ergab
  der Weg über die Migrationen eine **andere Datenbank** als der über
  `setup.sql`. Der Fingerabdruck-Vergleich hat das gefunden; 0073 legt die
  Sicht mit `create or replace` neu an (kein `cascade`, damit die gespeicherte
  Fassung stehen bleibt).
- **Der Lückenscanner** meldete `auftrag.fertige_paletten_gesamt` als Spalte
  ohne Maske — richtig, solange der Abschluss sie nicht schrieb. Jetzt tut er
  es, und der Scanner ist wieder grün.

Und eine Änderung an den Beispieldaten: `demo_daten_laden()` modellierte das
Leeren des Palox als „läuft über, wird zurückgesetzt" **während** einer Arbeit.
Das ist jetzt getrennt — geleert wird in der Regel **zwischen** zwei Arbeiten
(kostet keine Messung), und jede 23. Arbeit wird mittendrin geleert (kostet
eine, und setzt `palox_unbekannt`).

---

## 5. Stand der Prüfstände

| Prüfstand | Ergebnis nachher |
|---|---|
| `npm run typecheck` | grün |
| `npm test` | 96 Tests, 0 Fehler |
| `npm run build` | grün |
| `supabase/test/run.sh` | **alle Prüfungen bestanden** (inkl. Block 0072, Fingerabdruck deckungsgleich, Lückenscanner ohne Lücke) |
| `npm run gegenprobe --db demo` | 52 Fälle, 52 bestanden, 0 übersprungen |
| `setup.sql` | 671 KB von höchstens 1000 KB |

---

## 6. Was noch nicht geht

Ehrlich, Punkt für Punkt:

| Nr. | Offen | Stand |
|---|---|---|
| **Q5** | Gebindeart bei den Kaliber-Paletten **in der Maske** | Spalte und Zeilenregeln stehen, `Zaehler.tsx` fragt noch nicht danach |
| **Q8** | Kistenzähler je Kaliber aus der Oberfläche nehmen | noch nicht angefasst |
| **Q9** | „Diese Palette ist nicht voll" in `FertigePaletteMaske.tsx` | Spalte `voll` steht, das Häkchen fehlt |
| **Q10** | Fax-Vorschlag auf beide Stationen + 4-Tage-Vorgabe | noch nicht angefasst |
| **Q11** | Kontrollpalette **in der Arbeiter-App** (`Kontrolle.tsx`) und die Karte beim Betriebsleiter | Datenmodell und Sichten stehen, die Masken fehlen |
| **Q13** | Verderb mit Schrumpfung und den Zeichen ● ◐ ○ | noch nicht angefasst |
| **Q14** | `build:echt` / `build:beispiel`, das Band im Beispielmodus | Datenbankseite steht, die Bauskripte und das Band fehlen |
| **Q15b** | `keine_zerstoerung.sh` | noch nicht geschrieben |
| **Q15d** | Sicherungs-Abschnitt in der Doku, `letzte_sicherung` auf der Betrieb-Seite | Einstellung steht, die Anzeige fehlt |
| **Q16** | Kistenzahl aus dem Erntejournal beim Import | noch nicht angefasst |
| **Q18** | Zettelgewicht auch beim Sortieren zur Pflicht | noch nicht angefasst — **das ist die wichtigste offene Stelle**, weil daran die Masse je Kaliberband hängt |
| **Q22** | Einer laufenden Arbeit beitreten (Schichtwechsel) | noch geprüft, nicht geändert |

Die vier Durchgänge durch die Tätigkeiten (Tor 4) sind noch nicht gemacht, die
Bilder „nachher" noch nicht aufgenommen, und die Schrittzahlen aus Q17 noch
nicht gezählt.

---

## 7. Was dem Betrieb auffallen wird

- **Am Palox:** die App zeigt beim ersten Ablesen „Startstand — am Ende noch
  einmal ablesen" statt einer Zahl. Und wenn der Stand fällt, fragt sie, statt
  nichts anzuzeigen. Das ist schneller als vorher, nicht langsamer.
- **In der Auswertung:** es wird weniger Faules ausgewiesen als bisher — nicht
  weil weniger fault, sondern weil Arbeiten ohne Anfangsablesung jetzt ehrlich
  als „unbekannt" gelten statt aus der Vorarbeit aufgefüllt zu werden.
- **Beim Einspielen:** eine Datenbank im Echtmodus nimmt keine Beispieldaten
  mehr an und sagt das mit einem klaren Satz.
