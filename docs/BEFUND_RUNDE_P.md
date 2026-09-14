# Befund Runde P — gemessen, nicht behauptet

Gebaut ist, was in `docs/DESIGN_RUNDE_P.md` steht; warum es so gebaut ist,
steht im Abschnitt „Runde P" von `docs/ENTSCHEIDUNGEN.md`. Hier stehen die
Messungen: **Befehl, Ausgabe, Zahl.** Wo eine Zahl fehlt, steht, dass sie
fehlt und warum.

Alle Demo-Zahlen dieses Berichts sind am **14. September 2026** gegen die
lokale Demo-Datenbank gemessen (`heute()` = 2026-09-14, Saisonende
2027-03-31, Schema 71), in einem Stand. Die Demo hat **kein** festes
„heute": Sie altert mit dem Kalender, und ihre Zahlen bewegen sich darum von
Tag zu Tag ein wenig — der verkaufsfähige Anteil fiel zwischen dem 13. und
dem 14. September von 76.9 % auf 76.8 %. Was **nicht** wandert, ist die
Identität zwischen Prognose und Bilanz bei Horizont 0, und die ist der
eigentliche Prüfstein.

## 1. Was gemessen wurde

### 1.1 Die Datenbank-Suite: 7 von 7

```
./supabase/test/run.sh 'postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432'
```

```
── 1. Migrationen und Fachlogik ──────────────────────────────
   Stand: Migration 71 — Datenbank, App und Migrationen einig
   Fingerabdruck aus den Migrationen: 2770 Objekte
── 2. setup.sql als ein Query (wie der Supabase-Editor) ──────
   Fertig. Die Datenbank steht: 42 Chargen, 11 Sorten, 28 Tabellen, 67 Auswertungen.
   Meldungen im Editor: keine (nur die Fertig-Zeile)
   deckungsgleich mit den Migrationen: alle 2770 Objekte
   Grösse: 635 KB von höchstens 1000 KB
── 3. setup.sql ein zweites Mal ──────────────────────────────
   läuft durch, Daten unversehrt (42 Chargen), Schema unverändert
── 3b. Aktualisierung von einem alten Stand ──────────────────
   Daten erhalten, Auswertung rufbar, Schema wie frisch eingerichtet
── 4. Demo-Daten, genau wie im SQL-Editor (ohne Login!) ──────
   Demo-Saison steht: 844 Paletten in 36 Chargen, 308 Arbeiten (davon 160 Fax),
   32 Sortierläufe, 186 Lieferungen. Eingang 323.3 t.
── 4b. Aktualisierung mit Paletten, die schwerer geworden sind ─
   läuft durch, Rate ≥ 0 (kleinste 0.000470), drei Auffälligkeiten nennen den Grund
── 6b. Lückenscanner: keine Lücke zwischen Maske und Auswertung ─
── 7. setup.sql gegen die Migrationen abgleichen ─────────────
   aktuell
——— alle Prüfungen bestanden ———
```

### 1.2 Block 0071: vorher rot, nachher grün

Der Prüfblock wurde **vor** der Migration geschrieben. Er hält fest, was die
Runde verspricht: Bei Horizont 0 ist jede Prognosezahl die Zahl von heute,
`v_wohin` geht ohne Rest auf, und `v_naechste_charge` liest die Prognose.
Nachgestellt: alle Migrationen **ausser** 0071 einspielen, dann denselben
Block laufen lassen.

```
for f in supabase/migrations/*.sql; do case $(basename $f) in 0071_*) continue;; esac
  psql "$U" -v ON_ERROR_STOP=1 -q -f "$f"; done
psql "$U" -v ON_ERROR_STOP=1 -f block0071.sql

ERROR:  relation "v_prognose" does not exist
LINE 1: select count(*)               from v_prognose where gruppe =...
QUERY:  select count(*)               from v_prognose where gruppe = 'charge' and h = 0
CONTEXT:  PL/pgSQL function inline_code_block line 9 at SQL statement
```

Derselbe Block gegen die Datenbank **mit** 0071:

```
NOTICE:  OK  0071 (61 Prognosezeilen je Charge, 61 Zerlegungszeilen —
         Horizont 0 = heute, beide Identitäten gehen auf)
——— 0071 Prognose und Zerlegung geprüft ———
```

Nebenbei zeigt derselbe Lauf, dass auch der **erweiterte** Block 0049 vorher
rot ist: `erg_verlauf` bekommt seine Spalte `gruppe` erst in 0071, und die
neue Zusage „genau eine Stützstelle auf heute()" bricht ohne sie ab
(`ERROR: column "gruppe" does not exist`).

### 1.3 Die zweite Rechnung: 52 von 52, auf beiden Datenbanken

```
npm run gegenprobe -- --db demo    → 52 Fälle, 52 bestanden, 0 fehlgeschlagen, 0 übersprungen
npm run gegenprobe -- --db boese   → 52 Fälle, 52 bestanden, 0 fehlgeschlagen, 0 übersprungen
```

Neu darin sind sieben von Hand gerechnete Prognose-Fälle im Orakel und vier
Vergleiche gegen die laufende Datenbank:

| | was verglichen wird |
|---|---|
| K8 | `v_prognose` je Gruppe und Horizont: alle Ströme, die Hülle, die exakte Zerlegung des Verlusts in Wasser und Fäulnis |
| K9 | die zwei Identitäten von `v_wohin` |
| K10 | `erg_verlauf` Woche für Woche unabhängig nachgerechnet |
| K11 | die Zwei-Wochen-Zahl je Charge und ihre Rangfolge |

Die letzten Zeilen des Laufs:

```
ok 46 - Prognose: der Stand bei Alter t ist die Kaskade, und die Ströme ergeben m0
ok 47 - Prognose: Horizont 0 ist heute — keine zweite Mathematik
ok 48 - Prognose: Wasser und Fäulnis ergeben exakt, was der Horizont kostet
ok 49 - Prognose: gesättigter Verderb macht die Fäulnis nicht negativ
ok 50 - Prognose: die Summe über zwei Kohorten — Alter massegewichtet am Horizont
ok 51 - Prognose: fehlt ein Koeffizient, bleibt der Anteil leer (leer ist nicht null)
ok 52 - Prognose: die Hülle schliesst den Mittelwert ein
```

### 1.4 Die Bildschirme

```
node pruefstand/beschriftung.mjs
  OK  Jede Zahl auf jeder Seite sagt, was sie ist:
      beschriftet, im Lexikon, mit Zusatz beim Verlust, mit Herkunft,
      Prozente mit Bezugsgrösse, keine Modellwörter, Kopfzahlen stimmen.

node gegenprobe/bildschirm/invarianten.mjs                       (Demo)
  9 Seiten geprüft, 7 Diagramme, 0 Verstösse, 3 Hinweise
PRUEFSTAND_DATEN=gegenprobe/bildschirm/daten node …/invarianten.mjs   (böse Saison)
  9 Seiten geprüft, 7 Diagramme, 0 Verstösse, 3 Hinweise

node pruefstand/bildschirme.mjs
  Fertig: 188 Aufnahmen in pruefstand/bilder, keine Konsolenfehler
```

Drei Bildschirme sind in dieser Runde dazugekommen, weil sie gefehlt haben:
`ueberblick-charge`, `ursachen-sorte` und `ursachen-charge`. Der Prüfstand
nahm die neuen Karten bisher nur für „alles zusammen" auf; die Gruppenwahl ist
aber genau das, was Runde P gebaut hat. Der Wähler nimmt dabei nicht blind die
erste Sorte oder Charge, sondern die erste mit **Ware im Haus** — sonst fehlt
die Prognosegrafik zu Recht, und das Bild zeigt sie nicht.

Die drei Hinweise sind dieselben wie in Runde O: Datumsachsen, deren
Beschriftungen das Prüfgerüst nicht als Zahlen lesen kann (`27.05`, `13.09.`).
Kein Verstoss, keine neue Toleranz.

Die Kopfzahlen-Gegenprobe im Begriffs-Prüfstand vergleicht seit dieser Runde
vier Zahlen gegen `erg_bilanz` statt zwei: Eingang, Ausgeliefert, **Im Lager**
und **verkaufsfähig**.

### 1.5 Die Halle

```
node pruefstand/kette.mjs                → 50 Schreibanfragen, alle Schritte ✓
./pruefstand/kette_pruefen.sh …          ——— Kette in beide Richtungen geprüft ———
node gegenprobe/drehbuecher/spieler.mjs 03  → 6 Prüfungen, 0 nicht ok
npm run pruefen                          → tsc grün, 96 Tests, Build grün
git diff package.json                    → leer
```

### 1.6 Die Formeln sind nicht gewandert

```
node gegenprobe/orakel/formeln_holen.mjs
  154 Objekte nach gegenprobe/orakel/formeln geschrieben (155 Dateien)
git status --porcelain gegenprobe/orakel/formeln/   → leer
```

Der Abzug am Ende der Runde ist **byteweise** derselbe wie der nach der
Migration. Die Differenz zum Anfang der Runde ist genau die Objektliste von
0071: neu sind `v_prognose`/`erg_prognose`, `v_wohin`/`erg_wohin`,
`v_fax_wartezeit`/`erg_fax_wartezeit`, `erg_koeff_fax`, `mv_koeff_rand`,
`v_lieferung_charge_tag`; geändert sind `auswertung_schritt`, `schema_stand`,
`erg_verlauf`, `erg_ueberfuellung`, `v_lieferung_kohorte`, `v_marge_buch`,
`v_naechste_charge`, `v_plausibilitaet`, `v_ueberfuellung_verkauf`,
`v_verarbeitung_alter`, `v_verdunstung_messung`.

## 2. Die neuen Sichten mit ihren Demo-Zahlen

### 2.1 `v_prognose` — was aus der liegenden Ware wird

Die Kaskade bei `alter_tage + h`, je Gruppe (gesamt, Sorte, Schlag, Charge)
und je Horizont von heute bis zum Saisonende in Wochenschritten (7, 14 und 28
Tage immer dabei). Gesamt, am 14.09.2026:

| Horizont | Datum | Im Lager | gute Ware | verkaufsfähig | Anteil | Kanal | Fax erwartet | verdunstet | faul |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 14.09.26 | 188 444.66 | 154 321.74 | 144 761.13 | **76.8 %** | 7 185.42 | 2 375.19 | 15 929.54 | 18 193.38 |
| 14 | 28.09.26 | 188 444.66 | 151 607.22 | 142 213.90 | 75.5 % | 7 060.38 | 2 332.94 | 17 126.63 | 19 710.81 |
| 28 | 12.10.26 | 188 444.66 | 148 914.78 | 139 687.40 | 74.1 % | 6 936.33 | 2 291.04 | 18 315.31 | 21 214.57 |
| 198 | 31.03.27 | 188 444.66 | 118 475.94 | 111 126.25 | **59.0 %** | 5 531.38 | 1 818.32 | 32 100.53 | 37 868.18 |

`lager_kg` ist über alle Horizonte dieselbe Zahl — das ist der Nenner, und
was liegt, liegt. Die Rate je Tag steht daneben: **182.3 kg** verkaufsfähige
Ware gehen der liegenden Ware zurzeit pro Tag verloren, davon 110.4 kg als
Fäulnis und 71.9 kg als Wasser.

Bei Horizont 0 ist die Zeile identisch mit `erg_bilanz`:

```
erg_bilanz:    lager_kg 188 444.66 · verkaufsfaehig_heute_kg 144 761.12 · im_haus_heute_kg 154 321.72
erg_prognose:  lager_kg 188 444.66 · verkaufsfaehig_kg      144 761.13 · gute_ware_kg     154 321.74
```

Der Rappen Unterschied ist die Rundung von `numeric(14,2)` über 36 Chargen;
Block 0071 lässt dafür 2 Rappen zu.

Je Sorte am Saisonende — die Rangfolge, die der Betriebsleiter braucht:

| Sorte | Im Lager | heute | in 4 Wochen | am 31.03. |
|---|---|---|---|---|
| Lekor | 3 917 | 67.1 % | 64.7 % | **51.2 %** |
| Orangita | 329 | 74.5 % | 71.9 % | 56.8 % |
| Kaori Kuri | 11 371 | 75.8 % | 73.1 % | 57.8 % |
| Butterkin | 28 663 | 77.4 % | 74.5 % | 58.1 % |
| Tiana | 120 999 | 77.1 % | 74.5 % | **59.6 %** |

### 2.2 `v_wohin` — wohin der Kürbis geht

Der ganze Eingang aufgeteilt, gesamt:

```
Eingang            323 268.00        im Lager            188 444.66
Überzählung          4 178.45          davon verkaufsfähig 144 761.12
ausgeliefert       115 759.06          Kanal                 7 185.41
anderer Kanal        4 952.32          Fax erwartet          2 375.17
  davon zu klein     2 842.40          faul                 18 193.35
  davon zu gross     2 109.92          verdunstet           15 929.55
verdunstet (weg)     7 845.86
faul (weg)           8 025.13        rest_kg                   −0.06
Fax                  2 419.48        lager_rest_kg             +0.06
```

Beide Identitäten gehen auf: über alle 61 Gruppenzeilen bleibt weniger als
ein Zehntelkilo stehen, und das ist die Rundung.

### 2.3 `v_fax_wartezeit` — der Zusammenhang, der gefehlt hat

| Wartezeit | Arbeiten | abgepackt | Faules | Anteil | Bereich |
|---|---|---|---|---|---|
| 0–1 Tage | 43 | 23 587.6 kg | 314 kg | 1.31 % | 1.13 – 1.49 % |
| 2–3 Tage | 98 | 81 952.5 kg | 1 964 kg | 2.34 % | 2.17 – 2.51 % |
| unbekannt | 18 | 14 168.8 kg | 316 kg | 2.18 % | 1.72 – 2.65 % |

Die Bereiche von „0–1 Tage" und „2–3 Tage" überschneiden sich nicht. Keine
neue Frage an den Arbeiter — die Angabe gibt es seit 0060, sie wurde nur nie
ausgewertet. Daraus wurde Frage 60 in `docs/FRAGEN.md`.

### 2.4 Eine Zwei-Wochen-Zahl statt zweier

`v_naechste_charge` rechnet nicht mehr selbst, sondern liest die Prognose.
Für Charge 1632 (Tiana, 29 300 kg, 178 Lagertage):

| | zwei Wochen länger liegen |
|---|---|
| alte, eigene Formel (bis 0070) | 466 kg |
| Kaskade (ab 0071) | **386.2 kg** |

Beide Zahlen standen vorher im selben Programm, 20 % auseinander. Jetzt gibt
es nur noch die zweite.

### 2.5 Spielraum statt „verschenkter Marge"

| Sorte | System | je Kiste | Soll | Lage im Band | Spielraum / verschenkt |
|---|---|---|---|---|---|
| Tiana | Kiste ab 8 kg | 8.481 kg | 8.00 | — | 1 190.5 kg verschenkt |
| Mieluna | Kiste ab 8 kg | 8.367 kg | 8.00 | — | 301.5 kg verschenkt |
| Orangita | Stück | 11.211 kg | — | 58 % | 2 314.6 kg Spielraum |
| Ker Madec | Stück | 10.953 kg | — | 79 % | 1 179.7 kg Spielraum |
| Kaori Kuri | Stück | 11.479 kg | — | 10 % | 1 059.9 kg Spielraum |

Bei „Kiste ab x kg" ist der Überschuss echt verschenkt (bezahlt wird das
Soll). Bei Stück-Kisten wird je Stück bezahlt; dort ist es ein Spielraum, und
die Lage im Band sagt, wie gross er ist. Daraus wurde Frage 61.

## 3. Die Simulation: wie gut die Prognose trifft

```
URL='postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432' \
  ./supabase/test/simulation/matrix.sh 15
```

Neun Lagen, je 15 simulierte Saisons. Die zwei neuen Spalten vergleichen den
**verkaufsfähigen Anteil**, den die App 28 bzw. 56 Tage im Voraus nennt, mit
dem Anteil, der in der simulierten Welt tatsächlich eintritt:

| Lage | Wahrheit 28 d | geschätzt | Verzerrung 28 d | Verzerrung 56 d |
|---|---|---|---|---|
| Saisonende, 25 % im Lager | 79.3 % | 79.5 % | +0.26 pp | +0.29 pp |
| Mitten in der Saison, 50 % im Lager | 79.3 % | 79.7 % | +0.35 pp | +0.39 pp |
| Saisonende, Schlechtes zuerst verarbeitet | 80.4 % | 80.5 % | +0.17 pp | +0.39 pp |
| Mitten in der Saison, Schlechtes zuerst | 80.4 % | 79.9 % | −0.51 pp | −0.43 pp |
| … mit 12 Lagerkontrollen je Saison | 80.4 % | 80.1 % | −0.35 pp | −0.24 pp |
| … mit 24 Lagerkontrollen je Saison | 80.4 % | 79.8 % | −0.68 pp | −0.61 pp |
| Knappe Stichprobe: nur 4 Palettenwägungen | 79.3 % | 80.1 % | +0.77 pp | +0.86 pp |
| Mitten in der Saison, 2 % Sockel im Palox | 77.8 % | 78.6 % | +0.88 pp | +1.20 pp |
| Saisonende, 2 % Sockel im Palox | 77.7 % | 78.7 % | +1.02 pp | **+1.54 pp** |

Das Tor war ±3 Prozentpunkte. Die grösste Verzerrung ist **1.54 pp**, und sie
steht — wie erwartet — in der Sockel-Lage: Wo ein Teil des Faulen schon vom
Feld kommt, schreibt das Modell ihn der Lagerdauer zu und rechnet die Zukunft
etwas zu freundlich. Das ist dieselbe bekannte Schwäche, die die
Sockel-Spalte seit Runde C misst; sie ist hier beziffert und nicht weggeredet.

**Die Überdeckung der Hülle konnte nicht gemessen werden, und das muss man
wissen:** Sie steht in allen neun Lagen auf 0 %. Der Grund ist nicht eine zu
enge Hülle, sondern eine fehlende Stufe in der simulierten Welt — dort gibt
es **keine einzige Fax-Arbeit** (`select count(*) filter (where ist_fax) from
auftrag` → 0 von 705). Damit ist `a_fax` unbekannt, `vollstaendig` false, und
`verkaufsfaehig_unten_kg`/`oben_kg` bleiben leer, wie „leer ist nicht null"
es verlangt. Der Harness misst dann eine Überdeckung von null, weil er nichts
zu messen hat.

Das ist eine **offene Lücke**, keine erledigte Prüfung: Die Hülle ist durch
das Orakel abgesichert (Fall 52: sie schliesst den Mittelwert ein) und durch
K8 gegen die Datenbank, aber ihre Überdeckung in der Wirklichkeit ist
unbelegt. Sie zu belegen hiesse, dem Simulations-Harness einen Fax-Schritt
beizubringen; das ist eine eigene Runde und steht unten unter „Was offen
bleibt".

## 4. Tempo

Der Lasttest fährt die dreifache Saisongrösse (5 040 Paletten, 840 Arbeiten,
300 Sortierläufe mit 255 300 Gewichtsstufen, Eingang 4 336 t).

| | vor Runde P | nach Runde P |
|---|---|---|
| Auswertung ganz neu rechnen | 19 550 ms | **10 735 ms** |
| Schritt 1 | | 573 ms |
| Schritt 2 | | 3 414 ms |
| Schritt 3 | | 1 869 ms |
| Schritt 4 (Grenze 6 000 ms) | 9 907 ms | **3 927 ms** |
| Schritt 5 | | 1 000 ms |
| alle 34 gespeicherten Ansichten lesen | | 30.9 ms |

Vier neue gespeicherte Ergebnisse sind dazugekommen und es ist trotzdem
schneller. Die Ursachen sind einzeln gemessen und stehen als Kommentar an der
Stelle im SQL, an der sie wirken:

1. **`heute()` einmal statt 56 700-mal.** Die Funktion trägt `set
   search_path`; Postgres kann sie darum nicht in die Abfrage einsetzen, und
   jeder Aufruf kostet 47 µs. In der ersten Fassung stand sie je Portion und
   Horizont — 2.7 s allein dafür.
2. **`betriebstag()` aus der Verbundbedingung.** In `v_verarbeitung_alter`
   stand sie in einem Join und wurde je Paar ausgerechnet: 3 963 ms → 69 ms.
3. **`power()` faktorisiert.** (1−r)^(alter+h) ist das Produkt zweier
   vorgerechneter Faktoren — rund neuntausend Aufrufe statt einer halben
   Million.
4. **JIT aus.** Die Prognose steht auf einem Plan mit rund viertausend
   Knoten; LLVM braucht zum Übersetzen länger als Postgres zum Rechnen
   (gemessen 49 s mit, 1.3 s ohne). `auswertung_schritt()` und die
   Prüfstände setzen `jit = off`. Das ändert keine einzige Zahl.

## 5. Was die Prüfungen gefunden haben

Vier Sachen, die ohne die neuen Prüfungen niemand gesehen hätte.

**Der Verlauf zählte den Eingang falsch.** `erg_verlauf` las den Eingang aus
`v_palette` und liess damit Paletten ohne Nettogewicht weg, die die
Saisonbilanz seit 0064 hochrechnet. Auf der bösen Saison fehlten **430 kg**
(432 237 statt 432 667), und die Kurve „im Haus" fing zu tief an. Gefunden hat
das K10 der Gegenprobe, die den Verlauf Woche für Woche unabhängig
nachrechnet — nicht das Auge.

**Die Marge hing daran, wann zuletzt gerechnet wurde.** `v_marge_buch` las die
**gespeicherte** Überfüllung (`erg_ueberfuellung`) statt der Sicht. Damit riss
jedes Neubauen der Matrix die Marge mit. Jetzt liest sie die Sicht.

**Ein echter Zyklus in der Datenbank.** `v_prognose` braucht die Ränder der
Koeffizienten. Liest sie diese aus `erg_koeff_*`, hängt die Schleife, die
`erg_koeff_*` füllt, an einer Sicht, die aus `erg_koeff_*` liest —
`setup.sql` liess sich nicht mehr topologisch sortieren. Das war kein
Werkzeugfehler, sondern ein Kreis im Objektgraphen, und er ist strukturell
gelöst: `mv_koeff_rand` steht ausserhalb der Schleife und wird in Schritt 2
gefüllt.

**Die Kopfzahl zeigte eine obere Schranke wie eine Schätzung.** Fehlt ein
Koeffizient, ist „Davon verkaufsfähig" höchstens so gross wie angezeigt — die
Datenbank wusste das seit 0064, der Bildschirm sagte es nicht. Gefunden hat
das nicht ein Test, sondern das neue Drehbuch *Die Sorte ohne Wägung*, das
eine leere App Szene für Szene füllt und nach jeder Messung fragt, was die
App jetzt behauptet. Die Karte sagt seither **„höchstens"**.

### Das Drehbuch selbst

```
node gegenprobe/drehbuecher/spieler.mjs 03
S1 ok  lager_kg=4470  verkaufsfaehig_anteil=null
S2 ok  eingang=4470 geliefert=1200 lager=3270  verkaufsfaehig_anteil=null
S3 ok  lagertage=30 rate_pro_tag=0.000602      verkaufsfaehig_anteil=null
S4 ok  r,f,kanal bekannt · sockel,fax fehlen   verkaufsfaehig_anteil=null
S5 ok  sockel_bekannt=true modell_gilt=true    verkaufsfaehig_anteil=null
S6 ok  anteil_heute=0.8287  anteil_saisonende=0.5398  Hülle 6714.9 … 7088.8
6 Prüfungen, 0 nicht ok
```

Über fünf Szenen hinweg blieb der Anteil leer — und das war jedes Mal die
richtige Antwort, nicht ein fehlendes Feature. Er erschien erst, als alle fünf
Stufen der Kaskade eine gemessene Zahl hatten.

## 6. Die Bildschirme: was weg ist, was neu ist

**Überblick.** Die Kopfzahl „Verlust bis heute" ist weg; an ihrer Stelle
stehen „Im Lager" und „Davon verkaufsfähig". Der Verlauf hat vier Linien statt
drei und reicht bis zum Saisonende. Die Karten „Woran fehlt es" und „Wem fehlt
anteilig am meisten" sind zu **einer** geworden: *Wohin geht der Kürbis?* mit
Balken, zwei Ranglisten und der Rate je Tag. Die Gruppenwahl (alle · Sorte ·
Schlag · Charge) gilt jetzt schon hier.

**Ursachen.** Statt zweier grosser Lagertage-Diagramme oben steht eine Zeile
mit fünf Zahlen und **eine** Grafik: *Was wird aus der liegenden Ware?* als
gestapelte Prozentflächen bis zum Saisonende. Die Messpunkt-Diagramme und
Modellkurven sind in Aufklapper *Messungen und Kurve* gewandert. Neu: die
Fax-Wartezeit und die Spalten Lage im Band / Spielraum.

**Chargen.** Sechs neue oder geänderte Spalten, vier davon sortierbar. Nach
„In 4 Wochen" sortiert steht oben, was am wenigsten übersteht.

**Halle.** Genau eine Änderung, und sie fragt nichts Neues: „Tage seit dem
Waschen" ist beim Fax-Abschluss vorbelegt.

Die Bilder liegen in `pruefstand/bilder/` (188 Aufnahmen: jede Seite als Handy
und Rechner, hell und dunkel). Die neuen Karten sind darin je Gruppe zu sehen —
`ueberblick`, `ueberblick-sorte`, `ueberblick-charge`, `ursachen`,
`ursachen-sorte`, `ursachen-charge`, `chargen`, `chargen-offen` —, die neue
Halle-Maske als `arbeit-fax-tage`.

Zwei Dinge, die man erst auf dem Bild sieht. Bei Charge 1601 (1.2 t im Lager)
steht oben *889 kg · 77 %*, daneben *74 % in 4 Wochen* und *−1 kg je Tag*, und
darunter das Stapeldiagramm für genau diese Charge — dieselbe Rechnung wie für
die ganze Saison, nur auf einer Charge. Und der Fax-Block sagt für sie
„nicht gemessen / keine Wägung", während die Wartezeit-Tabelle darunter die
Saisonzahlen zeigt: Der Anteil dieser Charge ist unbekannt, die Erfahrung des
Hauses ist es nicht.

## 7. Wo vom Plan abgewichen wurde

**Der Horizont endet am Saisonende, nicht bei 84 Tagen.** Der Entwurf rechnete
mit sechs festen Horizonten (0/7/14/28/56/84). Der Betrieb hat die Zeitachse
danach klargestellt: Ernte August bis Oktober, Verkauf August bis März, „viel
weiter als März soll das nicht reichen". Also Wochenschritte bis `stichtag()`,
nie weiter als ein Jahr, nie kürzer als vier Wochen. Die Karten treffen genau
die Stützstellen, die `erg_prognose` liefert.

**`erg_prognose` hat eine eigene Rand-Matrix bekommen.** Der Entwurf las die
Ränder aus `erg_koeff_*`; das ergibt den Zyklus aus §5. `mv_koeff_rand` ist
neu und stand nicht im Plan.

**Die Zahlen des Entwurfs weichen leicht ab.** Der Entwurf nennt für
Horizont 0 lager 187 775.36 und verkaufsfähig 144 073.82; gemessen wird heute
188 444.66 und 144 943.81. Die Ursache ist nicht die Formel, sondern der
Stand: Der Entwurf lief gegen eine Auswertung, die am 11.09. gerechnet worden
war, die heutige Messung gegen eine vom 13.09. Was gleich bleiben muss und
gleich bleibt, ist die **Identität** mit `erg_bilanz` — und die prüft Block
0071 bei jedem Lauf neu.

## 8. Was offen bleibt

1. **Die Überdeckung der Prognose-Hülle ist unbelegt** (§3). Der
   Simulations-Harness kennt keinen Fax-Schritt, also bleibt die Hülle dort
   leer. Bis das nachgeholt ist, gilt die Hülle als „innen konsistent"
   (Orakel, K8), nicht als „in der Wirklichkeit geprüft".
2. **Der Sockel bleibt die Schwachstelle des Modells.** In der Sockel-Lage
   fehlt die Prognose um 1.0 bis 1.5 Prozentpunkte nach oben. Das ist im Tor,
   aber es ist eine Richtung, kein Rauschen.
3. **Drei Fragen an den Betrieb** (`docs/FRAGEN.md` 60–62): die Wartezeit vor
   dem Abpacken, die Lage im Kaliberband, und ob beim Sortieren die Kisten je
   Kaliber wirklich mitgezählt werden. Alle drei ändern, was der Betrieb tun
   kann — keine ändert, was die App rechnet.
4. **`pruefstand/daten` enthält alte Abzüge.** Der Ordner ist nicht im
   Repository (er entsteht aus `daten_dumpen.sh`), sammelt aber lokal Dateien
   früherer Runden an. Harmlos, aber verwirrend; das Aufräumen gehört in die
   nächste Runde, die den Prüfstand anfasst.

## 9. Für den Betriebsleiter

Die App sagt jetzt, was Sie gefragt haben: Von den **188 Tonnen**, die noch im
Haus liegen, sind heute **77 % verkaufsfähig**, in vier Wochen 74 % — und wenn
alles liegen bliebe bis Ende März, **59 %**. Jeden Tag gehen rund **182 kg**
verkaufsfähige Ware verloren: 110 kg als Fäulnis, 72 kg als Wasser. Lekor
steht am schlechtesten da (51 % Ende März), Tiana am besten (60 %) — und die
Chargenliste lässt sich so sortieren, dass oben steht, was zuerst raus sollte.

Die zweite Frage — wo der Kürbis hingeht — beantwortet eine einzige Karte:
116 Tonnen sind ausgeliefert, 5 Tonnen gingen in den Nebenkanal, 16 Tonnen
sind unterwegs verdunstet und 26 Tonnen verdorben, und 188 Tonnen liegen
noch.

Und eine Sache können Sie ab morgen ändern, ohne etwas zu kaufen: Ware, die
ein bis zwei Tage länger auf das Abpacken wartet, verliert **einen
Prozentpunkt mehr** — rund 900 kg in dieser Saison. Warum sie wartet, weiss
nur Ihre Halle; die Frage steht in `docs/FRAGEN.md`.
