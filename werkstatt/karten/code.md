« # Code-Karte — Runde M, Werkstatt C (Bauwerk)

**Stand der Messung:** 2026-09-09, Arbeitsstand nach Commit `9fe7bc0`
(„Runde M: Werkzeug B4"). `dist/` stammt vom 2026-09-09 19:21, die jüngste
Quelldatei vom 18:56 — **das gebaute Bündel ist aktuell**, alle Bündelzahlen
unten beziehen sich auf genau diesen Bau.

**Nichts wurde verändert.** `git status --short` zeigt nur
`werkstatt/d_nutzen/d4_messwert.mjs` — das ist die Datei einer anderen
Werkstatt, nicht meine. Alle Messwerkzeuge liegen im Kritzelverzeichnis
`/tmp/claude-0/-home-user-Kurbisverlust/6a3ce2bd-5cdd-5db2-b9aa-a2b322604348/scratchpad/`.

---

## 0. Wie gemessen wurde — und wie ich geprüft habe, dass das Messgerät nicht stumpf ist

Alle Zahlen kommen aus fünf selbstgebauten Werkzeugen in reinem Node, ohne neue
Abhängigkeit. Der Kern ist ein **JSX-bewusster Entkerner** (`lexer.mjs`):
er ersetzt Zeichenketten, Kommentare, Regex-Literale und JSX-Text durch
Leerzeichen und lässt Zeilennummern und Klammern stehen. Ohne ihn zählt jeder
Apostroph in einem deutschen JSX-Text („Retry deployment" in `App.tsx:37`) als
Zeichenkettenanfang und verschiebt jede Klammerbilanz.

| Werkzeug | Datei im Kritzelverzeichnis | Was es misst |
|---|---|---|
| Entkerner | `lexer.mjs` | Grundlage aller anderen |
| Dateivermessung | `vermessen2.mjs` → `vermessung.json` | Zeilen, Exporte, Funktionen, Längen, Tiefen, Hooks |
| Abhängigkeitsgraph | `graph.mjs`, `graph2.mjs` | jede `import`-Kante, auch mehrzeilig und `React.lazy` |
| Klonsucher | `klone.mjs`, `klonmass.mjs` | Tokenfenster mit SHA-1, ≥ 3 Vorkommen |
| Bündelzerleger | `buendel.mjs`, `gz.mjs` | VLQ-Dekoder der Quellkarten → Byte je Quellmodul |
| Totholz | `totholz2.mjs`, `werkzeugtot.mjs`, `i18n_tot.mjs`, `css.mjs` | Exporte, Übersetzungsschlüssel, CSS-Klassen |

### 0.1 Selbstproben

**Entkerner.** Prüfung: nach dem Entkernen muss jede Datei ausgeglichene
`{}`, `()`, `[]` haben. Erster Lauf: **33 von 91 Dateien unausgeglichen.**
Nach drei Reparaturen (JSX-Zustandsstapel, Regex-gegen-Division,
TS-Nichtnull `x! / y` gegen `!/re/.test()`): **0 von 91.**
Ohne diese Probe hätte ich die längste Funktion in `src/lib/warenausgang.ts`
mit 380 Zeilen angegeben — sie hat 57.
Befehl: `node pruefe_lexer.mjs` → `Dateien: 91 unausgeglichen: 0`.

**Klonsucher.** Drei erfundene Dateien mit demselben 6-Zeilen-Rumpf und
unterschiedlichen Namen. Ergebnis: `gepflanzter 3-fach-Klon gefunden? JA
(53 Fenster)`. Der Sucher kann also finden.

**Bündelzerleger.** Prüfung: Summe der zugeordneten Bytes ÷ Dateigrösse.
`auswertung` 99,2 %, `fremd` 99,8 %, `grundlage` 99,2 %, `index` 95,8 %.
Der Rest ist Bindegewebe ohne Quellzuordnung (Rolldown-Rahmen).

### 0.2 Was das Messgerät nachweislich **nicht** kann

Der Funktionsfinder erkennt nur `function X(...)` und
`const X = (...) => …`. **Methoden in Objektliteralen und eingebettete
Rückrufe sieht er nicht.** Deshalb steht bei `pruefstand/bildschirme.mjs`
„1 Funktion" — in Wirklichkeit ist das eine 130-Zeilen-Datentabelle mit
`tun: async p => {…}`-Einträgen. Als zweites Signal habe ich darum die
Pfeilfunktionen gezählt: **1784 im ganzen Projekt, 1025 davon in `src/`**.
Wo die Spalte „Funktionen" klein und die Datei gross ist, liegt der Code in
Datentabellen, nicht in Funktionen.

---

## 1. Die Dateitabelle

Sortiert nach Zeilen absteigend. Spalten:

- **Z** = Zeilen (`wc -l`-gleich)
- **Ex** = ausgeführte Exporte (`+nT` = zusätzlich n reine Typexporte)
- **Fn** = erkannte benannte Funktionen (siehe Einschränkung 0.2)
- **längste Funktion** = Zeilen, mit Startzeile
- **BT** = tiefste Blockverschachtelung (`{`)
- **ST** = tiefste *Steuer*verschachtelung (nur `if/for/while/switch/try/function`)
- **uS/uE** = `useState` / `useEffect`
- **←** = wie viele Module diese Datei importieren

### 1.1 `src/` — die Oberfläche (54 Dateien TS/TSX, 11 201 Zeilen; dazu `index.css`, 628 Zeilen)

| Datei | Z | Ex | Fn | längste Funktion | BT | ST | uS | uE | ← | Rolle in einem Satz |
|---|---|---|---|---|---|---|---|---|---|---|
| src/lib/i18n.ts | 1434 | 4+2T | 1 | uebersetze (3 Z, ab 1427) | 1 | 1 | 0 | 0 | 7 | Sechs Wörterbücher mit je 218 Schlüsseln für die Arbeiter-Oberfläche. |
| src/pages/Stammdaten.tsx | 815 | 1 | 24 | Kaliber (215 Z, ab 362) | 5 | 4 | 42 | 8 | 1 | Zehn Pflegemasken des Betriebsleiters (Gebinde, Kaliber, Benutzer, Vorlauf, Demo …) in einer Datei. |
| src/index.css | 628 | — | — | — | — | — | — | — | — | Das ganze Aussehen: 123 Klassen, 30 Farbvariablen, Druck- und Dunkelmodus. |
| src/auswertung/daten.ts | 556 | 11+35T | 22 | alles (80 Z, ab 252) | 4 | 4 | 4 | 1 | 7 | Lädt alle Auswertungssichten, hält sie im Speicher, liefert `useAuswertung()`. |
| src/pages/Ursachen.tsx | 527 | 1 | 24 | Ueberfuellungsblock (98 Z, ab 429) | 6 | 4 | 2 | 0 | 1 | Der Reiter „Ursachen": je Verlustart eine Karte mit Zahl, Band, Kurve, Tabelle. |
| src/components/Diagramm.tsx | 515 | 4+5T | 28 | Linien (259 Z, ab 100) | 7 | 5 | 8 | 0 | 3 | Linien, Glocke und Anteilsbalken von Hand als SVG, ohne Diagrammbibliothek. |
| src/lib/warenausgang.ts | 494 | 16+10T | 19 | zeilenLesen (57 Z, ab 162) | 4 | 3 | 0 | 0 | 1 | Liest die Perigon-Warenausgangsdatei, erkennt Neues gegen Bekanntes, baut Lieferungen. |
| src/betrieb/AusgangImport.tsx | 440 | 4 | 11 | DateiKarte (193 Z, ab 219) | 7 | 4 | 11 | 1 | 1 | Die Maske zum Hochladen dieser Datei, mit Vorschau vor dem Schreiben. |
| src/pages/NeueArbeit.tsx | 382 | 1 | 14 | NeueArbeit (339 Z, ab 44) | 6 | 3 | 15 | 2 | 1 | Der Anlegeweg einer Arbeit in sechs Schritten (Tätigkeit, Charge, Bänder, Kaliber, System, Prüfen). |
| src/pages/Ueberblick.tsx | 320 | 1 | 9 | Ueberblick (105 Z, ab 25) | 5 | 4 | 3 | 0 | 1 | Der erste Reiter: Eingang, Ausgang, Verlust, Bestand als Kaskade. |
| src/pages/Arbeit.tsx | 308 | 1 | 8 | Arbeit (273 Z, ab 36) | 6 | 4 | 7 | 1 | 1 | Die Schaltzentrale einer laufenden Arbeit — schaltet zwischen den neun Masken um. |
| src/arbeit/Abschluss.tsx | 292 | 1 | 8 | Abschluss (262 Z, ab 31) | 5 | 3 | 9 | 0 | 1 | Die Abschluss-Checkliste am Ende einer Arbeit. |
| src/arbeit/Zaehler.tsx | 282 | 1 | 19 | Zaehler (252 Z, ab 31) | 5 | 3 | 9 | 0 | 1 | Der Palettenzähler — der eine Bildschirm, den der Arbeiter am häufigsten sieht. |
| src/arbeit/Korrektur.tsx | 273 | 2 | 10 | Tabellenblock (75 Z, ab 113) | 7 | 3 | 8 | 1 | 2 | Tabellengetriebene Berichtigung erfasster Messungen; exportiert auch `Kontrollkorrektur` für den Betriebsleiter. |
| src/pages/CsvUpload.tsx | 261 | 1 | 6 | CsvUpload (205 Z, ab 24) | 5 | 4 | 6 | 2 | 1 | Sortier-CSVs hochladen und Chargen zuordnen. |
| src/pages/Messungen.tsx | 250 | 1 | 4 | Messungen (191 Z, ab 17) | 6 | 4 | 2 | 0 | 1 | Der Reiter „Messungen": Modellkoeffizienten, Bilanz, Vollexport. |
| src/pages/Lieferungen.tsx | 226 | 1 | 4 | Lieferungen (200 Z, ab 27) | 5 | 3 | 13 | 1 | 1 | Warenausgang von Hand erfassen — Gegenprobe zur Bilanz. |
| src/lib/import.ts | 220 | 4+3T | 13 | importErkennen (81 Z, ab 132) | 4 | 4 | 0 | 0 | 1 | Liest Palettendaten aus dem Erntejournal (fremdes Google-Sheet). |
| src/pages/Chargen.tsx | 208 | 1 | 4 | ChargeDetail (92 Z, ab 117) | 6 | 3 | 5 | 1 | 1 | Der Reiter „Chargen": eine Zeile je Charge, aufklappbar. |
| src/lib/xlsx.ts | 195 | 2+2T | 13 | blattLesen (33 Z, ab 132) | 4 | 4 | 0 | 0 | 2 | Ein Excel-Blatt ohne Bibliothek lesen (ZIP + XML mit Bordmitteln). |
| src/auswertung/Karten.tsx | 185 | 8 | 7 | Kurvenherkunft (32 Z, ab 97) | 5 | 5 | 0 | 0 | 4 | Die gemeinsamen Bausteine der fünf Betriebsleiter-Reiter (Reiterkopf, Kennzahl, Rechenweg, Probleme). |
| src/pages/Kontrolle.tsx | 180 | 1 | 4 | Kontrolle (150 Z, ab 31) | 5 | 3 | 13 | 1 | 1 | Lagerkontrolle: eine Palette zwischendurch nachwiegen. |
| src/arbeit/daten.ts | 174 | 6+5T | 5 | arbeitLaden (56 Z, ab 46) | 3 | 2 | 0 | 0 | 9 | Lädt und formt alles, was die neun Arbeiter-Masken brauchen; `stationsProfil` entscheidet, welche Maske erscheint. |
| src/pages/Anmelden.tsx | 149 | 1 | 5 | BetriebsleiterLogin (77 Z, ab 73) | 7 | 4 | 11 | 0 | 1 | Ein Feld für den Arbeiter, klein darunter der Betriebsleiter-Login. |
| src/components/DemoDaten.tsx | 143 | 1 | 3 | DemoDaten (125 Z, ab 19) | 4 | 3 | 5 | 1 | 2 | Demo-Saison laden und entfernen — nur der Betriebsleiter sieht das. |
| src/pages/Betrieb.tsx | 142 | 1 | 4 | Arbeiten (86 Z, ab 57) | 6 | 4 | 6 | 1 | 1 | Der fünfte Reiter, zugleich Verteiler auf fünf Unterseiten. |
| src/arbeit/AusschussMaske.tsx | 139 | 1 | 5 | AusschussMaske (120 Z, ab 20) | 6 | 2 | 7 | 1 | 2 | Zu klein / zu gross wiegen. |
| src/arbeit/FertigePaletteMaske.tsx | 139 | 1 | 2 | FertigePaletteMaske (116 Z, ab 24) | 5 | 2 | 8 | 1 | 2 | Eine fertige Palette erfassen. |
| src/App.tsx | 137 | 1 | 3 | App (106 Z, ab 22) | 5 | 2 | 0 | 0 | 1 | Rahmen, Navigation und die fünf `React.lazy`-Reiter des Betriebsleiters. |
| src/lib/csv.ts | 132 | 7+2T | 7 | reinigen (34 Z, ab 68) | 3 | 2 | 0 | 0 | 2 | Reinigung der Sortier-CSV (Trichter, Ausreisser, Masse). |
| src/arbeit/FauleMaske.tsx | 131 | 1 | 3 | FauleMaske (116 Z, ab 16) | 6 | 2 | 7 | 1 | 2 | Faules kistenweise wiegen (Fax-Weg). |
| src/pages/Start.tsx | 117 | 1 | 5 | Start (96 Z, ab 18) | 6 | 5 | 6 | 1 | 1 | Startseite des Arbeiters: was läuft, zwei Knöpfe. |
| src/pages/Warteschlange.tsx | 113 | 1 | 4 | Warteschlange (102 Z, ab 12) | 7 | 3 | 5 | 1 | 1 | Nicht eindeutig zuordenbare CSVs von Hand entscheiden. |
| src/arbeit/WiegenMaske.tsx | 112 | 1 | 2 | WiegenMaske (93 Z, ab 20) | 4 | 2 | 9 | 1 | 1 | Eine Palette wiegen und zählen. |
| src/lib/typen.ts | 106 | 0+18T | 0 | — | 1 | 0 | 0 | 0 | 18 | Die 18 gemeinsamen Datentypen; enthält keine ausgeführte Zeile. |
| src/arbeit/PaloxMaske.tsx | 100 | 1 | 2 | PaloxMaske (80 Z, ab 21) | 4 | 2 | 5 | 1 | 2 | Den Palox ablesen; die Differenz rechnet die App. |
| src/components/Bausteine.tsx | 98 | 9 | 9 | Rechenweg (14 Z, ab 46) | 4 | 2 | 0 | 0 | **28** | Hinweis, Karte, Marke, Lade, Herkunft — das meistgelesene Modul der App. |
| src/lib/dateiname.ts | 90 | 2+1T | 3 | dateinamenLesen (54 Z, ab 33) | 3 | 1 | 0 | 0 | 1 | Toleranter Parser der Maschinen-Dateinamen. |
| src/lib/masse.ts | 88 | 4+1T | 4 | nettoKg (12 Z, ab 22) | 2 | 2 | 0 | 0 | 9 | Netto = brutto − Kisten × Tara − Palettentara, eine Regel an einer Stelle. |
| src/sprache/SprachProvider.tsx | 80 | 3 | 5 | SprachProvider (32 Z, ab 28) | 3 | 3 | 2 | 1 | 16 | Sprachwahl, `t()`, Gebietsschema. |
| src/pages/Zugang.tsx | 77 | 1 | 2 | Zugang (68 Z, ab 10) | 4 | 3 | 3 | 1 | 1 | Der QR-Code zum Aufhängen — der einzige Nutzer von `qrcode`. |
| src/components/Schritte.tsx | 65 | 3 | 3 | Schritt (32 Z, ab 12) | 3 | 1 | 0 | 0 | 5 | Der Rahmen „eine Frage je Bildschirm". |
| src/components/Zeichen.tsx | 63 | 5 | 6 | Z (8 Z, ab 9) | 2 | 1 | 0 | 0 | 1 | Fünf Strichzeichen für die Navigation, statt einer Icon-Bibliothek. |
| src/auth/AuthProvider.tsx | 60 | 2 | 3 | AuthProvider (38 Z, ab 21) | 4 | 4 | 3 | 2 | 4 | Sitzung, Profil, Admin-Merkmal. |
| src/lib/db.ts | 54 | 4 | 4 | fehlerText (20 Z, ab 35) | 2 | 2 | 0 | 0 | 22 | Stammdaten-Zwischenspeicher, Fehlertexte, Chargentext. |
| src/lib/format.ts | 54 | 9 | 8 | zeitpunkt (7 Z, ab 31) | 2 | 1 | 0 | 0 | 12 | `kg`, `tonnen`, `zahl`, `prozent`, `datum` — alle in `de-CH`. |
| src/lib/konfiguration.ts | 50 | 1 | 2 | konfigurationPruefen (28 Z, ab 11) | 2 | 2 | 0 | 0 | 1 | Prüft URL und Schlüssel, bevor sonst etwas passiert. |
| src/components/ChargeFeld.tsx | 45 | 1 | 1 | ChargeFeld (31 Z, ab 15) | 4 | 1 | 0 | 0 | 2 | Chargennummer eintippen statt aus einer Liste wählen. |
| src/auswertung/tempo.ts | 33 | 1+1T | 2 | tempoJeTaetigkeit (25 Z, ab 9) | 3 | 2 | 0 | 0 | 1 | Dauer und Durchsatz je Tätigkeit, Median statt Mittel. |
| src/components/Kaskadenbild.tsx | 33 | 1 | 1 | Bilanzzeile (25 Z, ab 9) | 4 | 1 | 0 | 0 | 1 | Eine Bilanzzeile: Zahl, Balken, Herkunft. |
| src/lib/taetigkeit.ts | 33 | 2+1T | 1 | taetigkeitVon (5 Z, ab 29) | 1 | 1 | 0 | 0 | 6 | Die vier Tätigkeiten als Tabelle — die einzige Wahl des Arbeiters. |
| src/lib/rolle.ts | 24 | 3 | 4 | fuehrtLokal (6 Z, ab 9) | 2 | 2 | 0 | 0 | 2 | Vorarbeiter oder Zähler, im lokalen Speicher gemerkt. |
| src/main.tsx | 22 | 0 | 0 | — | 1 | 0 | 0 | 0 | 0 | Einstieg; zieht Schrift und Stil herein. |
| src/lib/version.ts | 19 | 2 | 1 | datenbankVeraltet (7 Z, ab 13) | 1 | 1 | 0 | 0 | 1 | Der Schemastand, den diese App voraussetzt (0057). |
| src/lib/supabase.ts | 16 | 3 | 2 | url (1 Z, ab 4) | 2 | 0 | 0 | 0 | **26** | Der eine Datenbankgriff; von 26 Modulen gelesen. |

### 1.2 Werkzeuge (30 `.mjs`, 8018 Zeilen) und Prüfstände

| Datei | Z | Ex | Fn | längste Funktion | BT | ST | Rolle in einem Satz |
|---|---|---|---|---|---|---|---|
| supabase/verdichten.mjs | 564 | 5 | 17 | verdichten (310 Z, ab 255) | 5 | 5 | Verdichtet 67 Migrationen zu `setup.sql` (1285 kB → 574 kB). |
| pruefstand/kette.mjs | 523 | 0 | 13 | restAntwort (91 Z, ab 43) | 6 | 6 | Fährt vier Arbeiten und eine Kontrolle durch die echten Masken im Browser. |
| werkstatt/b_fundament/b1_totes.mjs | 467 | 3 | 9 | laufen (201 Z, ab 214) | 4 | 3 | B1 — Nutzungsgraph der Datenbankobjekte. |
| werkstatt/b_fundament/b4_integritaet.mjs | 442 | 3 | 9 | laufen (176 Z, ab 230) | 4 | 3 | B4 — was die Datenbank wirklich garantiert. |
| werkstatt/d_nutzen/d2_aufloesung.mjs | 409 | 4 | 8 | laufen (163 Z, ab 216) | 5 | 4 | D2 — Entscheidungsauflösung. |
| pruefstand/beschriftung.mjs | 387 | 0 | 17 | ERNTEN (101 Z, ab 96) | 6 | 5 | Begriffs-Prüfstand: sagt jede Zahl, was sie ist? |
| pruefwerk/sonden/06_mutation.mjs | 355 | 4 | 8 | laufen (112 Z, ab 228) | 4 | 4 | Sonde 06 — Mutation. |
| supabase/test/run.sh | 346 | — | — | — | — | — | Datenbank-Suite in sieben Stufen. |
| werkstatt/umgebung.mjs | 345 | 31 | 20 | zufall (38 Z, ab 107) | 5 | 4 | Gemeinsame Grundlage der vier Werkstätten. |
| werkstatt/a_rechenwerk/a1_schaetzer.mjs | 330 | 3 | 5 | laufen (137 Z, ab 158) | 5 | 3 | A1 — Schätzer-Prüfstand mit bekannter Wahrheit. |
| pruefwerk/sonden/04_orakel.mjs | 324 | 6 | 10 | laufen (218 Z, ab 70) | 6 | 5 | Sonde 04 — Orakel. |
| pruefwerk/sonden/02_bezugsgroessen.mjs | 323 | 5 | 14 | laufen (126 Z, ab 131) | 5 | 4 | Sonde 02 — Bezugsgrössen. |
| werkstatt/b_fundament/b5_zeit.mjs | 320 | 2 | 6 | laufen (148 Z, ab 151) | 5 | 3 | B5 — die Zeit. |
| pruefwerk/sonden/08_leer_nicht_null.mjs | 314 | 3 | 4 | laufen (247 Z, ab 44) | 5 | 3 | Sonde 08 — leer ist nicht null. |
| pruefstand/bildschirme.mjs | 299 | 0 | (1) | Datentabelle, 51 Pfeilfunktionen | 6 | 5 | Rendert jede Seite im echten Browser, legt Bildschirmfotos ab. |
| test/warenausgang.test.ts | 297 | 0 | 4 | probe (4 Z, ab 19) | 2 | 1 | Modultests des Warenausgangs. |
| pruefwerk/sonden/07_szenarien.mjs | 291 | 3 | 6 | laufen (244 Z, ab 40) | 5 | 3 | Sonde 07 — Praxisszenarien. |
| pruefwerk/sonden/05_metamorph.mjs | 288 | 3 | 5 | laufen (221 Z, ab 28) | 5 | 3 | Sonde 05 — metamorphe Beziehungen. |
| pruefstand/kette_pruefen.sh | 287 | — | — | — | — | — | Kettenlauf gegen die Datenbank prüfen. |
| pruefwerk/sonden/01_herkunft.mjs | 253 | 4 | 6 | laufen (125 Z, ab 94) | 5 | 5 | Sonde 01 — Herkunft. |
| pruefwerk/sonden/10_annahmen.mjs | 234 | 5 | 9 | laufen (126 Z, ab 60) | 5 | 4 | Sonde 10 — Annahmen. |
| supabase/setup_bauen.mjs | 204 | 0 | 2 | kb (2 Z, ab 194) | 1 | 1 | Baut `setup.sql` aus den Migrationen. |
| pruefwerk/sonden/03_erfassung.mjs | 196 | 3 | 3 | laufen (149 Z, ab 35) | 4 | 3 | Sonde 03 — Erfassung. |
| pruefwerk/umgebung.mjs | 150 | 17 | 18 | frischesSchema (12 Z, ab 78) | 3 | 3 | Datenbank ansprechen, Befunde formen, Wegwerf-Datenbanken. |
| pruefwerk/sonden/09_einheiten.mjs | 145 | 3 | 3 | laufen (69 Z, ab 63) | 4 | 3 | Sonde 09 — Einheiten. |
| werkstatt/bericht.mjs | 144 | 0 | 7 | eintrag (16 Z, ab 47) | 2 | 1 | `befunde.json` → `docs/WERKSTATTBERICHT.md`. |
| pruefstand/attrappe.mjs | 140 | 9 | 9 | restAntwort (55 Z, ab 52) | 5 | 3 | Supabase-Attrappe für die Browser-Prüfstände. |
| werkstatt/lauf.mjs | 132 | 0 | 3 | holen (4 Z, ab 45) | 4 | 4 | Läufer der vier Werkstätten. |
| pruefstand/luecken.sh | 126 | — | — | — | — | — | Lückensuche. |
| pruefwerk/invarianten.mjs | 108 | 8 | 7 | zerlegung (17 Z, ab 39) | 2 | 2 | Fünf Regeln, die auf jeder Datenbank gelten müssen. |
| supabase/test/simulation/lauf.sh | 104 | — | — | — | — | — | Simulationslauf. |
| test/import.test.ts | 100 | 0 | 0 | — | 1 | 1 | Modultests des Journal-Imports. |
| test/csv.test.ts | 98 | 0 | 0 | — | 2 | 2 | Modultests der CSV-Reinigung. |
| pruefwerk/bericht.mjs | 96 | 0 | 5 | eintrag (16 Z, ab 30) | 2 | 1 | `befunde.json` → `docs/PRUEFBERICHT.md`. |
| pruefwerk/saison.mjs | 93 | 9 | 4 | geruest (22 Z, ab 27) | 2 | 1 | Kleine Saisons mit auf Papier ausrechenbarem Ergebnis. |
| pruefwerk/lauf.mjs | 84 | 0 | 2 | holen (4 Z, ab 29) | 3 | 3 | Läufer des Prüfwerks. |
| test/i18n.test.ts | 75 | 0 | 0 | — | 3 | 3 | Modultests der Wörterbücher. |
| pruefstand/postgrest.mjs | 58 | 2 | 2 | filtern (42 Z, ab 6) | 4 | 4 | Der Filter des Mini-PostgREST, von zwei Prüfständen geteilt. |
| test/konfiguration.test.ts | 55 | 0 | 2 | jwt (4 Z, ab 9) | 2 | 1 | Modultests der Zugangsprüfung. |
| supabase/test/simulation/matrix.sh | 51 | — | — | — | — | — | Simulationsmatrix. |
| pruefstand/daten_dumpen.sh | 49 | — | — | — | — | — | Prüfdaten wegschreiben. |
| test/oberflaeche.test.ts | 45 | 0 | 1 | dateien (6 Z, ab 10) | 3 | 3 | Modultests der Oberflächenregeln. |
| pruefstand/demo_bauen.sh | 44 | — | — | — | — | — | Demo-Datenbank bauen. |
| test/masse.test.ts | 33 | 0 | 0 | — | 2 | 1 | Modultests der Netto-Regel. |
| test/version.test.ts | 33 | 0 | 0 | — | 1 | 1 | Modultests des Schemastands. |
| supabase/setup_bauen.sh | 11 | — | — | — | — | — | Wrapper um `setup_bauen.mjs`. |

### 1.3 Verteilungen statt Durchschnitten

```
src/ (54 Dateien TS/TSX, 11 201 Zeilen)
  Zeilen je Datei     Min 16 · Median 137 · 75 % 250 · 90 % 440 · Max 1434 (Mittel 207)
  längste Funktion    Median 77 · 90 % 215 · Max 339 (NeueArbeit)
  Blocktiefe          Median 4 · Max 7 (5 Dateien)
  Steuertiefe         Median 3 · Max 5 (5 Dateien)
  Kommentaranteil     20,2 % (2393 Zeilen), Leerzeilen 6,7 % (747) → 8061 Codezeilen
  useState  234 · useEffect 32 · useMemo 16 · useRef 0 · useCallback (nur Arbeit.tsx)
  useState je Komponente  Median 0 · 75 % 4 · 90 % 7 · Max 15 (NeueArbeit, Stammdaten/Kaliber)
  Schnittstellen: 60 mit Feldern, Median 4 Felder, Max 218 (Woerterbuch)
```

Die zwanzig grössten Dateien tragen **7 083 Zeilen = 63 %** der Oberfläche.
Zu jeder der fünf grössten:

| Datei | Z | Ist die Grösse gerechtfertigt? |
|---|---|---|
| `lib/i18n.ts` | 1434 | **Ja.** 6 × 218 Schlüssel, jeder Block 227 Zeilen. Der Inhalt *ist* die Grösse. Der Angriffspunkt ist nicht die Zeilenzahl, sondern dass alle sechs Sprachen in **einem** Modul liegen (Abschnitt 5.3). |
| `pages/Stammdaten.tsx` | 815 | **Nein.** Zehn unabhängige Pflegemasken (`GebindeTara`, `PalettenImport`, `Kaliber` 215 Z, `Abgebrochene`, `Benutzer`, `Einstellungen`, `Vorlauf`, `Demo` …) mit **42 useState** in einer Datei; die Reiterliste in Zeile 12–18 ist die einzige Klammer. Der `Kaliber`-Block allein (215 Z, 15 useState) ist eine eigene Datei. |
| `auswertung/daten.ts` | 556 | **Ja, mit Vorbehalt.** 35 Typen + 11 Ladefunktionen + der Zwischenspeicher. Die Typen (≈ 190 Z) sind die Vertragsseite zur Datenbank; sie gehören zusammen. Auffällig: **23 der 46 Exporte importiert niemand** (Abschnitt 5.1). |
| `pages/Ursachen.tsx` | 527 | **Grenzfall.** Sechs Verlustkarten (`Verdunstung`, `Verderb`, `Sortierung`, `Ueberfuellungsblock` 98 Z, `Gewichtsverteilung`, `Fax`) mit sehr ähnlichem Aufbau, aber verschiedenen Zahlen. Sie ist zugleich der **Fehlerbehandlungs-Brennpunkt** der App: 43 `?.`, 42 `??`, 39 `!== null`, 24 `== null`, 15 × `? … : '—'`, 7 `!`-Behauptungen in 527 Zeilen — 170 Nullbehandlungen auf 384 Codezeilen. |
| `components/Diagramm.tsx` | 515 | **Ja.** Drei Diagrammarten von Hand in SVG, damit keine Diagrammbibliothek in die Halle muss (`Linien` allein 259 Z, Blocktiefe 7). 26 995 Zeichen Quelle ergeben 14 704 B im Bündel — eine Bibliothek wäre grösser. Der Preis ist die Verschachtelung. |

---

## 2. Der Abhängigkeitsgraph

**225 Importkanten** zwischen 54 Modulen, gemessen mit `graph.mjs`
(mehrzeilige Importe und `React.lazy` eingeschlossen).

### 2.1 Kreise

**Keine.** Tiefensuche über alle 225 Kanten: `KREISE: 0`.

### 2.2 Die Schichten, nach Kantengewicht

```
 55  pages    -> lib          10  pages -> arbeit        2  auswertung -> components
 27  arbeit   -> lib          10  pages -> auswertung    2  auth       -> lib
 25  pages    -> components    8  auswertung -> lib      2  components -> sprache
 12  arbeit   -> arbeit        7  arbeit -> sprache       2  pages      -> auth
 10  wurzel   -> pages         6  betrieb -> lib          1  betrieb    -> components
 10  arbeit   -> components    6  lib -> lib             1  pages      -> betrieb
  5  pages    -> pages         5  components -> lib      1  sprache    -> lib
```

**Kein Modul liest nach oben.** `lib/` importiert nur `lib/`, `components/`
nur `lib/` und `sprache/`. Der Graph ist gerichtet und flach.

### 2.3 Schichtverletzungen

| # | Kante | Befund |
|---|---|---|
| 1 | `src/pages/Messungen.tsx:7` → `../arbeit/Korrektur` (`Kontrollkorrektur`) | **Die einzige echte Verletzung.** Eine Betriebsleiter-Seite (im faul geladenen `auswertung`-Bündel) liest aus der Arbeiter-Schicht (im `grundlage`-Bündel, das der Arbeiter immer lädt). Die Folge ist *umgekehrt* zur üblichen: `Korrektur.tsx` steckt richtig im Arbeiterbündel, aber `Kontrollkorrektur` (Zeile 271–273) samt der Tabelle `KONTROLLE` (Zeile 253–270) — zusammen **33 Zeilen, ≈ 1 kB** — reist beim Arbeiter mit, obwohl nur der Betriebsleiter sie je sieht. |
| 2 | `src/pages/Betrieb.tsx` → 5 andere Seiten | `Stammdaten`, `CsvUpload`, `Lieferungen`, `Warteschlange`, `Zugang`. Keine Verletzung, aber die einzigen `pages -> pages`-Kanten: `Betrieb` ist ein Verteiler, kein Reiter. |
| 3 | `src/pages/Lieferungen.tsx` → `src/betrieb/AusgangImport.tsx` | Die einzige Datei in `src/betrieb/` (440 Z), von genau einer Seite gelesen. Ein Verzeichnis für eine Datei. |

**Gegenprobe.** Liest umgekehrt eine Arbeiter-Maske aus `pages/`,
`auswertung/` oder `betrieb/`?
`grep -rn "from '\.\./\(pages\|auswertung\|betrieb\)/" src/arbeit/` → **keine
Treffer.** Die Arbeiter-Schicht ist sauber.

### 2.4 Was in `src/lib/` liegt und nur einen Leser hat

| Modul | Z | einziger Leser | Gegenrede — wozu war es da? |
|---|---|---|---|
| `lib/warenausgang.ts` | 494 | `betrieb/AusgangImport.tsx` | Die Trennung von Regel und Maske ist Absicht: `warenausgang.ts` ist rein und wird von `test/warenausgang.test.ts` (297 Z Tests) allein geprüft. **Trägt.** |
| `lib/import.ts` | 220 | `pages/Stammdaten.tsx` | Dasselbe: `test/import.test.ts` (100 Z). **Trägt.** |
| `lib/xlsx.ts` | 195 | `AusgangImport` + `warenausgang.ts` | Zwei Leser, geprüft. **Trägt.** |
| `lib/dateiname.ts` | 90 | `pages/CsvUpload.tsx` | Geprüft in `test/csv.test.ts`. **Trägt.** |
| `lib/konfiguration.ts` | 50 | `lib/supabase.ts` | Geprüft in `test/konfiguration.test.ts`. **Trägt.** |
| `lib/version.ts` | 19 | `auswertung/daten.ts` | Geprüft in `test/version.test.ts`. **Trägt** fachlich — liegt aber im falschen Bündel (Abschnitt 5.4). |
| `auswertung/tempo.ts` | 33 | `pages/Betrieb.tsx` | Ungeprüft, einziger Leser, 33 Zeilen. Der schwächste Fall. |
| `components/Zeichen.tsx` | 63 | `App.tsx` | Fünf SVG-Zeichen, nur in der Navigation. Begründet im Kopfkommentar. **Trägt.** |
| `components/Kaskadenbild.tsx` | 33 | `auswertung/Karten.tsx` | 25-Zeilen-Komponente in eigener Datei. |

**Regel, die sich zeigt:** Jedes Einzelleser-Modul in `lib/` hat eine eigene
Testdatei — mit **einer** Ausnahme (`auswertung/tempo.ts`). Die Aufteilung ist
also nicht willkürlich, sondern die Naht zwischen „geprüft" und „gemalt".
Wer hier zusammenlegt, zerstört die Prüfbarkeit.

### 2.5 Die Naben

| Modul | wird gelesen von | Z |
|---|---|---|
| `components/Bausteine.tsx` | **28** | 98 |
| `lib/supabase.ts` | **26** | 16 |
| `lib/db.ts` | 22 | 54 |
| `lib/typen.ts` | 18 | 106 |
| `sprache/SprachProvider.tsx` | 16 | 80 |
| `lib/format.ts` | 12 | 54 |

Fünf Fremdpakete werden importiert: `react` (36×), `react-router-dom` (11×),
`@supabase/supabase-js` (2×), `react-dom/client` (1×), `qrcode` (1×).

---

## 3. Wiederholte Muster — maschinell gesucht

Verfahren: Quelle entkernen → Tokenstrom → Fenster von *N* Token → SHA-1 →
Fenster mit ≥ 3 nicht überlappenden Vorkommen. Zwei Modi: **wörtlich**
(Bezeichner bleiben) und **Form** (Bezeichner → `ID`, Zahlen → `NUM`).

### 3.1 Wie viel Code ist Klon?

| Bereich | Fenster | Codezeilen | in einem ≥ 3-fach-Klon | Anteil |
|---|---|---|---|---|
| `src/` ohne `i18n.ts`, wörtlich | 25 Token | 6 777 | **524** | **7,7 %** |
| `src/` ohne `i18n.ts`, wörtlich | 40 Token | 6 777 | 147 | 2,2 % |
| `src/` ohne `i18n.ts`, Form | 40 Token | 6 777 | 456 | 6,7 % |
| `pruefwerk` + `pruefstand` + `werkstatt`, wörtlich | 30 Token | 4 739 | **420** | **8,9 %** |

Die dichtesten Dateien (25 Token, wörtlich):
`arbeit/Korrektur.tsx` 87/205 (42 %) · `pages/Stammdaten.tsx` 55/501 ·
`arbeit/FauleMaske.tsx` 40/97 (41 %) · `arbeit/AusschussMaske.tsx` 39/101 ·
`arbeit/FertigePaletteMaske.tsx` 38/100 · `arbeit/Abschluss.tsx` 34/214.
Bei den Werkzeugen: `pruefstand/kette.mjs` **181/430 = 42 %** und
`pruefstand/bildschirme.mjs` **101/226 = 45 %**.

### 3.2 Die benannten Familien

| # | Muster | Vorkommen | Belegstellen | Gegenrede |
|---|---|---|---|---|
| **F1** | Zustandstrio `const [laeuft…] = useState(false)` / `const [fehler…] = useState<string\|null>(null)` / `const [abbruch…]` | **12× in 11 Dateien** | `arbeit/Abschluss.tsx:42`, `AusschussMaske:28`, `FauleMaske:24`, `Korrektur:115` und `:191`, `PaloxMaske:29`, `WiegenMaske:32`, `Zaehler:49`, `pages/Anmelden:35`, `Kontrolle:44`, `NeueArbeit:61`, `Stammdaten:120` | Ein `useSpeichern()`-Haken zöge drei Zeilen zusammen und macht `React`s Regeln undurchsichtiger. `useState(false)` allein steht **13×**, `useState<string\|null>(null)` für `fehler` **28×**. |
| **F2** | Kistenart-Auswahl: `<label>` + `<select>` + `gebinde.map(g => <option …>)` | **5×** | `AusschussMaske:88`, `FauleMaske:80`, `FertigePaletteMaske:88`, `WiegenMaske:88`, `pages/Kontrolle:160` | Buchstabengleich, inklusive `id="aus-art"`. **Gleiche `id` fünfmal** — auf einem Bildschirm mit zwei Masken bräche das `htmlFor`. Ein `<Kistenart>`-Baustein spart ≈ 25 Zeilen und behebt es. |
| **F3** | Gewichtseingabe `<input className="gross" type="number" inputMode="decimal" step="0.1">` | **4×** | `AusschussMaske:76`, `FauleMaske:68`, `FertigePaletteMaske:76`, `Zaehler:229` | Dieselben vier Attribute, dieselbe `id="aus-brutto"`. |
| **F4** | Ladewächter der Betriebsleiter-Reiter: `if (laedt && !daten) return <Rechnet/>` / `if (fehler) …` / `if (!daten) return null` | **4×** | `Ueberblick:30`, `Ursachen:39`, `Chargen:39`, `Messungen:24` | Steht **hinter** den Haken — bewusst, siehe der Kommentar in `Messungen.tsx:18–21`. Ein Wrapper wäre möglich, aber die drei Zeilen sind der ehrlichste Weg. 12 Zeilen. |
| **F5** | Importkopf der vier Masken (5 Zeilen buchstabengleich) | **4×** | `AusschussMaske:1–5`, `FauleMaske:1–5`, `FertigePaletteMaske:1–5`, `WiegenMaske:1–5` | Importe sind kein Klon im schlechten Sinn. Nur ein Symptom von F1–F3. |
| **F6** | Feldtabelle `{ name:'…', label:'…', typ:'…' }` in `Korrektur.tsx` | **11 Blöcke** | `Korrektur.tsx:22–92` und `:253–270` | **Absicht.** Das ist eine Datentabelle, kein kopierter Code — genau die Bauart, die die Datei kurz hält. Der Klonsucher sieht sie trotzdem; **nicht anfassen**. |
| **F7** | Klickfolge „Neue Arbeit anlegen" im Kettenprüfstand | **12×** | `pruefstand/kette.mjs:208, 272, 315, 327, 356, 361, 372, 420, 433, 441, 482, 490` | Drei Zeilen `getByRole(...).click()` + `#taet-…` + `#charge` je Fall. 36 Zeilen. Gegenrede: ein Prüfstand soll den Weg *zeigen*, nicht verstecken. Aber 12× ist über der Schwelle. |
| **F8** | Befund-Kopf `const B = (o) => raus.push(befund({ sonde:…, kuerzel:… }))` | **9× in 9 Sonden** | `01_herkunft:95`, `02:132`, `03:36`, `04:71`, `06:230`, `07:41`, `08:45`, `09:64`, `10:61` | Das ist das Protokoll des Läufers. **Gerechtfertigt.** |

### 3.3 Der Anfangsverdacht: `x?.bekannt ? … : '—'`

Gezählt, statt geraten (`platzhalter.mjs`, ganzes `src/`):

| Muster | Anzahl | Brennpunkt |
|---|---|---|
| `? … : '—'` (Gedankenstrich als Ausweichwert) | **33** | `Ursachen.tsx` 15 · `Messungen.tsx` 4 · `Karten.tsx` 3 |
| `?? '—'` / `\|\| '—'` | **15** | `Messungen.tsx` 5 |
| Ternär/Und auf `.bekannt` | **20** | `Ursachen.tsx` 15 · `Ueberblick.tsx` 3 |
| `!== null` / `!= null` als Bedingung | **134** | `Ursachen.tsx` 39 · `Messungen.tsx` 11 |
| `=== null` / `== null` als Bedingung | **152** | `Ursachen.tsx` 24 · `NeueArbeit.tsx` 18 |
| Text `'nicht gemessen'` | **8** | `Ursachen.tsx` 4 · `Karten.tsx` 3 |
| Optionalkette `?.` | **159** | `Ursachen.tsx` 43 |
| Nullish `??` | **305** | `Ursachen.tsx` 42 · `daten.ts` 24 |
| Nichtnull-Behauptung `x!` | **16** | `Ursachen.tsx` 7 |
| **Summe** | **842** | auf 8 061 Codezeilen = **eine Nullbehandlung je 9,6 Codezeilen** |

Die genaue Form `strom?.bekannt ? kg(x) : '—'` steht buchstäblich nur **2×**
(`Ursachen.tsx:337` und `:338`). Der Verdacht in der Aufgabenstellung war also
in seiner engen Fassung *falsch* — die **Familie** dahinter ist dafür fünfmal
grösser als vermutet. Ihre Ursache ist benannt und begründet: Migration 0064
(„null heisst nicht gemessen, nicht null Kilo") und 0066. Wer sie zusammenzieht,
muss zwei Dinge unterscheiden, die der Code heute unterscheidet: **unbekannt**
(`—`) und **gemessen und null** (`0 kg`). Ein Helfer, der beides gleich
behandelt, wäre ein neuer Rechenfehler.

### 3.4 Gleichnamige Helfer in mehreren Dateien (21 gefunden, 4 mit Substanz)

| Name | Orte | Befund |
|---|---|---|
| `heute()` | `pages/Lieferungen.tsx:25`, `sprache/SprachProvider.tsx:22` | **Buchstabengleich:** `() => new Date().toISOString().slice(0, 10)`. Und beide falsch: `toISOString()` liefert das **UTC**-Datum. In der Schweiz (UTC+1/+2) ist das zwischen 00:00 und 02:00 Ortszeit der Vortag. |
| `zahl()` | `lib/format.ts:15` (Zahl → Text), `lib/import.ts:214` (Text → Zahl), `lib/warenausgang.ts:118` (Zelle → Zahl) | Drei Funktionen, ein Name, drei Bedeutungen. Die letzten beiden sind **fast gleich** (beide behandeln den Schweizer Tausender-Apostroph), unterscheiden sich aber: `import.ts` entfernt Leerzeichen **im Inneren**, `warenausgang.ts` nur aussen. |
| `tonnen()` | `lib/format.ts:8`, `pages/Kontrolle.tsx:94` | Die lokale Fassung in `Kontrolle.tsx` benutzt `toLocaleString()` **ohne Ortsangabe** — Tausendertrennzeichen nach Browsereinstellung statt `de-CH` — und schreibt auch 300 kg als „0,3 t". |
| `speichern()` | 10 Dateien | Gleicher Name, verschiedene Rümpfe. Kein Klon, sondern Konvention. **In Ordnung.** |

---

## 4. Was der Arbeiter herunterlädt

`vite.config.ts` schneidet in vier Gruppen. Gemessen am Bau vom 2026-09-09
19:21 durch Zerlegen der Quellkarten (`buendel.mjs`, VLQ-Dekoder).

### 4.1 Der Kaltstart

```
  39 086 B roh    11 030 B gzip   index-CSp8Gj4Q.js
     716 B roh       428 B gzip   rolldown-runtime.js
 351 420 B roh    94 641 B gzip   grundlage-CxPUyYoQ.js
 245 510 B roh    78 889 B gzip   fremd-B_TL-OM8.js
   1 947 B roh       589 B gzip   fremd.css
  22 588 B roh     5 419 B gzip   index.css
───────────────────────────────────────────────
 661 267 B roh   190 996 B gzip
 + 48 256 B Schrift (inter-latin, schon komprimiert)
 = 239 252 B über die Leitung
```

**Was der Arbeiter *nicht* lädt:** `auswertung-CQviWg3O.js`, 190 595 B roh /
52 003 B gzip. `dist/index.html` lädt nur `index`, `grundlage`, `fremd` vor —
die fünf Betriebsleiter-Reiter hängen an `React.lazy` in `App.tsx:16–20`.
**Der Grobschnitt funktioniert.** 52 kB gzip bleiben liegen.

### 4.2 Der Feinschnitt funktioniert nicht

Der Kopfkommentar in `vite.config.ts` sagt:
*„fremd — React, Router, Supabase — ändert sich nur beim Aktualisieren."*
Gemessen liegt das anders:

| Paket | Bytes im Bündel | **liegt in** | sollte laut Absicht in |
|---|---|---|---|
| `react-dom` | 179 277 B | fremd | fremd ✓ |
| `react-router` | 38 905 B | fremd | fremd ✓ |
| `qrcode` + `dijkstrajs` | 23 384 B | fremd | fremd ✓ |
| **`@supabase/auth-js`** | **99 762 B** | **grundlage** | fremd ✗ |
| **`@supabase/realtime-js`** | **30 718 B** | **grundlage** | fremd ✗ |
| **`@supabase/phoenix`** | **25 696 B** | **grundlage** | fremd ✗ |
| **`@supabase/storage-js`** | **22 552 B** | **grundlage** | fremd ✗ |
| **`@supabase/postgrest-js`** | **16 344 B** | **grundlage** | fremd ✗ |
| **`@supabase/supabase-js`** | **10 635 B** | **grundlage** | fremd ✗ |
| **`react`** | **7 824 B** | **grundlage** | fremd ✗ |
| `iceberg-js`, `tslib`, `functions-js` | 8 819 B | grundlage | fremd ✗ |

**222 350 B Fremdcode — 63 % des `grundlage`-Bündels — liegen im falschen
Bündel.** Ich habe die drei Regeln gegen die echten Modulpfade geprüft
(`node -e`, alle drei Regexe gegen zehn Pfade): `node_modules/react/index.js`
trifft **nur** `fremd`, nicht `grundlage`. Rolldown ordnet es trotzdem
`grundlage` zu — die `groups`-Regeln sind ein Hinweis, keine Zusicherung, und
`priority: 10` auf `grundlage` kippt die Zuordnung.

**Folge, beziffert:** Jede Änderung an einer einzigen Zeile in `src/arbeit/`
oder `src/lib/i18n.ts` erzeugt einen neuen Hash für `grundlage` und wirft dem
Arbeiter **94 641 B gzip** aus dem Zwischenspeicher — davon **63 kB gzip
Fremdcode, der sich nicht geändert hat**. Der ganze Zweck der Gruppe `fremd`
ist damit für zwei Drittel der Bytes verfehlt.

### 4.3 Was der Arbeiter lädt und nie ausführen kann

Erreichbarkeit gemessen: Tiefensuche von `src/main.tsx` über **nur statische**
Importkanten → **30 Module**. 24 Module hängen ausschliesslich an `React.lazy`.
Der Arbeiter erreicht nie: `format.ts`, `version.ts`, `DemoDaten.tsx` — die
liegen trotzdem in `grundlage`.

| Was | Bytes roh | Bytes gzip (einzeln gemessen) | Beleg |
|---|---|---|---|
| `qrcode` + `dijkstrajs` | 23 377 | **8 709** | einziger Nutzer `src/pages/Zugang.tsx:2`, erreichbar nur über `Betrieb.tsx` (Betriebsleiter, `auswertung`-Bündel) |
| `@supabase/realtime-js` + `phoenix` + `functions-js` | 59 229 | **17 234** | `grep -rnoE "supabase\.(channel\|functions\|realtime)" src` → **0 Treffer** |
| `@supabase/storage-js` | 22 552 | **5 702** | genau **1** Aufruf: `src/pages/CsvUpload.tsx:88` (Betriebsleiter) |
| `iceberg-js` | 5 372 | **1 541** | 0 Aufrufe in `src/` |
| `components/DemoDaten.tsx` + `lib/format.ts` + `lib/version.ts` | 5 977 | **2 542** | alle 12 Leser von `format.ts`, der 1 Leser von `version.ts` und die 2 Leser von `DemoDaten` sind Betriebsleiter-Module |
| **Summe** | **116 507 B** | **35 728 B gzip** | **18,7 % der gzip-Bytes des Kaltstarts** |

Dazu die fünf Sprachen, die der Arbeiter nicht liest: `i18n.ts` liegt mit
**62 200 B roh / 20 301 B gzip** im Bündel; 78 % davon (55 123 B der 70 681 B
Quelle) sind die Blöcke `en/hu/ro/pl/pt`. Geschätzt **≈ 15 800 B gzip**
für Sprachen, von denen jeder Arbeiter höchstens eine braucht.

**Zusammen ≈ 51 500 B gzip von 190 996 B = 27 % des Kaltstarts.**
Bei 50 kB/s (mässiges Mobilfunknetz in einer Halle) sind das **≈ 1,0 Sekunde
Wartezeit an der Waage je Kaltstart**; bei 30 kB/s ≈ 1,7 Sekunden.
(Die Bandbreite ist angenommen, die Bytes sind gemessen.)

### 4.4 Nebenbefund: Quellkarten

`sourcemap: true` erzeugt **3 480 292 B** `.map`-Dateien, alle vier mit
`sourcesContent` — der **vollständige Quelltext von `src/`, öffentlich
abrufbar**. Der Browser lädt sie nur bei geöffneten Entwicklerwerkzeugen, sie
kosten den Arbeiter also nichts. Die Absicht steht im Kommentar
(`vite.config.ts`: „soll der Fehlerbericht die Zeile im Quelltext nennen"). Das
ist eine bewusste Entscheidung — hier nur festgehalten, damit sie es bleibt.

---

## 5. Totholz

### 5.1 Exporte, die niemand importiert

Gemessen über den Importgraphen (nicht über `grep`, damit gleichnamige Symbole
in verschiedenen Dateien nicht verwechselt werden), `test/` eingeschlossen.

**233 Exporte in `src/`. Davon werden 52 (22 %) von niemandem importiert.**
Alle 52 werden im eigenen File gebraucht — es ist also **kein toter Code,
sondern ein zu weit geöffnetes Fenster**: 52 überflüssige `export`-Schlüsselwörter.

| Datei | betroffene Exporte |
|---|---|
| `auswertung/daten.ts` | **23** — `auswertungLaden` + 22 Typen (`Verlustzeile`, `Wiegung`, `Modell`, `Kohorte`, `Kurve`, `Schema`, `Selektion`, `Marge` …) |
| `lib/warenausgang.ts` | 8 — `KEINE_WARE`, `PFLICHTSPALTEN`, `SPALTEN`, `Kopf`, `Kuerbisurteil`, `SpaltenName` … |
| `arbeit/daten.ts` | 6 — `FERTIGE_SOLL`, `WIEGEN_SOLL`, `Ablesung`, `AusschussZeile`, `Fassung`, `Palette` |
| `lib/import.ts` | 5 · `components/Diagramm.tsx` 3 · `betrieb/AusgangImport.tsx` 3 (`JOURNAL_INTERN`, `ZEITRAUM_AB`, das Wieder-Ausfuhr `export { zeilenSchluessel }` in Zeile 440) · `lib/typen.ts` 3 · übrige 1–2 |

**Gegenrede.** Bei den Typen ist der Export der billigste Weg, sie
dokumentierbar zu halten; `noUnusedLocals` in `tsconfig.app.json` würde einen
*nicht* exportierten und nur einmal benutzten Typ nicht anmahnen. Und bei
`auswertungLaden` ist der Export die Notausgangstür für ein künftiges Werkzeug.
Der reale Schaden ist trotzdem messbar: solange 52 Symbole exportiert sind,
kann **kein** Werkzeug — weder `tsc` noch Rolldowns Baumschnitt — sagen, ob sie
noch gebraucht werden. Das ist genau der Zustand, den diese Karte auflösen soll.

Zusätzlich **9 Exporte, die nur der Test benutzt** — die sind gerechtfertigt und
sollen bleiben: `fingerabdruck`, `schluessel` (warenausgang), `datumLesen`,
`gebindeNormalisieren`, `tabelleLesen` (import), `serieAlsDatum` (xlsx),
`reinigen`, `werteLesen` (csv), `jahrFuerMonat` (dateiname).

**Ganz tote Dateien: keine.** Jedes Modul ausser `main.tsx` (der Einstieg) hat
mindestens einen Leser.

**Ungenutzte Eigenschaften: keine.** 157 destrukturierte Komponenten-Props
geprüft, **0** werden im Rumpf nie gelesen. (`props.mjs`)

### 5.2 In den Werkzeugen

135 Exporte. Der erste Lauf meldete 76 ohne Leser — **falscher Alarm**:
44 davon sind `laufen` / `selbstprobe` / `lang`, das Protokoll, das
`pruefwerk/lauf.mjs:49` und `werkstatt/lauf.mjs:78` per `await import()`
dynamisch laden. Nach Korrektur:

- **13** nur im eigenen File gebraucht — `export` überflüssig:
  `invarianten.mjs` (`FINGERABDRUCK`, `erhaltung`, `rueckrechnung`, `unwissen`,
  `zerlegung` — alle nur aus `alle()` heraus gerufen), `04_orakel.mjs`
  (`fModell`, `kaskade`), `02_bezugsgroessen.mjs` (`lesarten`),
  `10_annahmen.mjs` (`annahmen`, `stichworte`), `06_mutation.mjs`
  (`MUTATIONEN`), `attrappe.mjs` (`ADMIN`), `saison.mjs` (`SCHLAG`).
- **3 nirgends gebraucht:** `werkstatt/umgebung.mjs` → `PRUEFWERK`,
  `erklaere`, `heuteSetzen`. **Vorsicht:** `werkstatt/` wird in dieser Runde
  gerade gebaut; diese drei sind vermutlich für noch ungeschriebene Werkzeuge
  gedacht. Vor Runde-Ende erneut messen.

### 5.3 Übersetzungsschlüssel — je Sprache einzeln

`src/lib/i18n.ts`, 70 681 B, 1434 Zeilen.

| Sprache | Zeilenbereich | Zeilen | Bytes | Schlüssel | fehlt ggü. `de` | zusätzlich |
|---|---|---|---|---|---|---|
| de | 27–280 | 254 | 11 842 | 218 | — | — |
| en | 285–511 | 227 | 11 047 | 218 | 0 | 0 |
| hu | 513–739 | 227 | 10 962 | 218 | 0 | 0 |
| ro | 741–967 | 227 | 11 162 | 218 | 0 | 0 |
| pl | 969–1195 | 227 | 10 827 | 218 | 0 | 0 |
| pt | 1197–1423 | 227 | 11 125 | 218 | 0 | 0 |

**Die sechs Wörterbücher sind vollständig deckungsgleich.** Kein fehlender,
kein überzähliger Schlüssel — der Compiler (`Record<TextId, string>`) erzwingt
das, und `test/i18n.test.ts` prüft es.

**Nie benutzte Schlüssel.** 13 Schlüssel werden nie als Literal `t('…')`
gerufen. Acht davon leben dynamisch und **müssen bleiben**:

- `sortieren`, `waschen`, `waschenSortieren`, `fax` — über
  `TAETIGKEITEN[].text` in `lib/taetigkeit.ts:23–26`, gerufen als `t(a.text)` in
  `NeueArbeit.tsx:198`, `Arbeit.tsx:95`, `Start.tsx:84`, `Chargen.tsx:195`,
  `Betrieb.tsx:125`, `NeueArbeit.tsx:358`.
- `sortierenErkl`, `waschenErkl`, `waschenSortierenErkl`, `faxErkl` — über
  die Tabelle `ERKL` in `NeueArbeit.tsx:17–20`, gerufen als `t(ERKL[a.id])`.

**Fünf sind wirklich tot**, in allen sechs Sprachen:

| Schlüssel | de-Zeile | Wozu er da war | Prüfung |
|---|---|---|---|
| `kaeufer` („Für welchen Käufer?") | 50 | Die Käuferabfrage beim Anlegen einer Arbeit — 0060 hat sie aus dem Anlegeweg genommen. | Die 3 Treffer im Code sind die Tabelle `kaeufer` und die Spalte `sortierschema.kaeufer`, kein `t()`. |
| `abschluss` („Fertig") | 57 | Reiterbeschriftung, ersetzt durch `abschlussErkl`/`abschlussErklWS`. | Alle Treffer sind der Ansichtsname `'abschluss'` in `Arbeit.tsx:21,196,292`. |
| `baender` („Bänder") | 97 | Schrittbeschriftung im Anlegeweg. | Alle Treffer sind die `SchrittId` `'baender'` in `NeueArbeit.tsx:14,81,84,216`. |
| `fehler` | 137 | Allgemeines Fehlerwort; die Masken zeigen heute den Text aus `fehlerText()` (66 Aufrufe). | Alle Treffer sind der Status `'fehler'` in `CsvUpload.tsx` und `AusgangImport.tsx`. |
| `abgebrochen` | 145 | Marke in der Arbeitsliste. | Alle Treffer sind Filterwerte in `Betrieb.tsx:61,80,109,111` und `Stammdaten.tsx:12,18,37` — deutsch fest verdrahtet, nicht übersetzt. |

**30 tote Zeilen, 758 B Quelle** (6 Sprachen × 5 Schlüssel). Klein — aber der
Weg dorthin ist der Befund: es gibt **kein Werkzeug**, das prüft, ob ein
Schlüssel noch gebraucht wird, und wegen der zwei dynamischen Tabellen kann ein
naiver Prüfer das auch nicht. Ein Prüfer müsste `TAETIGKEITEN[].text` und
`ERKL` als Weissliste kennen.

### 5.4 CSS-Klassen ohne Verwendung

`src/index.css`, 629 Zeilen / 31 021 B, **123 Klassen**, 30 Farbvariablen.
Geprüft gegen alle `className`-Literale **und** die 7 dynamischen
`className={\`…\`}`-Stellen sowie `index.html`.

**Alle 30 CSS-Variablen werden gelesen. 9 Klassen nicht:**

| Klasse | Zeile | Wozu sie da war |
|---|---|---|
| `.balken-zeile` | 331 | Rahmen der Verlust-Rangbalken; die Ränge zeichnet heute `Diagramm.tsx` als SVG. |
| `.balken-bereich` (+ `::before`, `::after`) | 341–346 | Der Unsicherheitsstrich am Balken — seit die Bänder im SVG stecken, ungenutzt. |
| `.stapel-zeile` (+ `.klickbar`, `:hover`) | 349–351 | Die gestapelten Anteilsbalken; heisst heute `.anteil-zeile` (`Diagramm.tsx:478`). |
| `.stapel-spur` | 352 | dito → `.anteil-spur`. |
| `.stapel-teil` | 353 | dito → `.anteil-teil`. |
| `.kaliber-spur` | 354 | Kaliberverteilung als Streifen; ersetzt durch die Glocke. |
| `.balken-fuellung.projiziert` | 337 | Schraffur für den hochgerechneten Teil eines Balkens. Mein erster Lauf hielt sie für lebendig — die Zeichenkette `projiziert` steht 13× im Code, aber **nie als Klassenname**, immer als Feld `kg_projiziert`. |
| `.dialog-hinter` | 415, 421 | Ein Modaldialog. Die App hat keinen; sie führt über Seiten. |
| `.dialog` | 422, 429 | dito. |

**23 Zeilen, 1 327 B Quelle** (4,3 % des Stylesheets, ≈ 1 kB roh im Bündel).
Das Stylesheet wird **nicht** durchgeschüttelt: alle 22 588 B `index.css`
gehen an jeden Arbeiter.

---

## 6. Was gemessen wurde und *in Ordnung* ist

Damit die nächsten Werkstätten nicht doppelt suchen:

- **Keine Importkreise** (0 von 225 Kanten).
- **Keine Schichtverletzung nach oben** — `lib/` und `components/` lesen nie
  aus `pages/`, `arbeit/` liest nie aus `pages/`, `auswertung/` oder `betrieb/`.
- **Keine ungenutzte Komponenten-Eigenschaft** (0 von 157).
- **Keine ungenutzte CSS-Variable** (0 von 30).
- **Keine tote Datei** (jedes Modul ausser dem Einstieg hat einen Leser).
- **Die Wörterbücher sind deckungsgleich** (6 × 218, 0 Abweichungen).
- **Der Grobschnitt des Bündels trägt**: die 190 595 B Auswertung erreichen den
  Arbeiter nicht.
- **Die Verschachtelung ist flach**: Steuertiefe Median 3, Max 5. Die
  Blocktiefe 7 in fünf Dateien kommt fast ganz aus verschachteltem JSX, nicht
  aus verschachtelter Logik.
- **`tsconfig.app.json`** hat `strict`, `noUnusedLocals`, `noUnusedParameters`,
  `noFallthroughCasesInSwitch` — deshalb gibt es keine ungenutzten lokalen
  Namen zu finden.

---

## 7. Reihenfolge für Werkstatt C, nach gemessener Grösse

| Rang | Sache | Grösse | Aufwand |
|---|---|---|---|
| 1 | Fremdcode aus `grundlage` in `fremd` bringen (Regeln in `vite.config.ts` greifen nicht) | 222 350 B roh / ≈ 63 kB gzip verlieren bei jeder Auslieferung den Zwischenspeicher | klein — Konfiguration + Nachmessen |
| 2 | `qrcode`, Supabase-Realtime/Storage/Functions, `iceberg-js`, `DemoDaten`, `format.ts`, `version.ts` aus dem Arbeiterpfad nehmen | 116 507 B roh / **35 728 B gzip** je Kaltstart | mittel |
| 3 | Sprachen einzeln laden | ≈ 48 500 B roh / **≈ 15 800 B gzip** | mittel |
| 4 | `Stammdaten.tsx` (815 Z, 42 useState) in seine zehn Masken zerlegen | 815 Zeilen, davon `Kaliber` 215 | mittel |
| 5 | F2/F3 zu `<Kistenart>` und `<Gewichtsfeld>` — behebt zugleich 5 doppelte `id="aus-art"` | ≈ 40 Zeilen, 1 Zugänglichkeitsfehler | klein |
| 6 | 52 überflüssige `export` in `src/` + 13 in den Werkzeugen zurücknehmen | 65 Symbole; macht künftiges Totholz überhaupt erst sichtbar | klein |
| 7 | `heute()` an 6 Stellen auf Ortszeit umstellen (gehört fachlich zu B5) | 6 Stellen, 1 Tag Lagerdauer je Fall | klein |
| 8 | 5 tote i18n-Schlüssel × 6 Sprachen, 9 tote CSS-Klassen | 30 + 23 Zeilen, 2 085 B | klein |
| 9 | F7 im Kettenprüfstand (12× dieselbe Klickfolge) | 36 Zeilen; `kette.mjs` ist zu 42 % Klon | klein |

**Für jeden dieser Punkte gilt Abschnitt 3.7 des Auftrags:** vorher/nachher
messen und Verhaltensgleichheit beweisen. Für Punkt 1–3 ist der Beweis leicht
(`pruefstand/bildschirme.mjs` rendert alle Seiten, `kette.mjs` fährt die Kette,
die Bündelgrössen sind mit `buendel.mjs` nachmessbar). Für Punkt 4–5 sind es
die Bildschirmfotos. Punkt 7 ändert Verhalten **absichtlich** — dort braucht es
statt eines Gleichheitsbeweises einen Prüfstand, der den Unterschied zeigt.
»