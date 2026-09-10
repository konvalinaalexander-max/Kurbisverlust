> Nichts verändert, nichts committet. Gearbeitet auf einer eigenen Kopie
> `karte_doku` (`create database karte_doku template demo`).

## Kurzfassung

Die Doku ist inhaltlich besser als ihr Ruf: die grossen Zahlen der Auswertung
(323 268 kg Eingang, 52 119 kg Verlust, 16,12 %, 2633 Objekte, 11 201 Zeilen `src/`)
stimmen auf die Stelle. Was **nicht** stimmt, liegt an drei Stellen, und alle drei
sind systematisch:

1. **`ABMACHUNGEN.md` wächst nur, es wird nie widerrufen.** Fünf Zusagen vom
   1./2./3. September sind vom 8. September ausdrücklich aufgehoben — sie stehen
   unmarkiert weiter da, mit grünen Tests, die etwas anderes prüfen als die Zeile sagt.
2. **Die HTML-Quellen und ihre PDFs sind älter als der Code, den sie beschreiben.**
   Alle fünf PDFs tragen den Baustempel 9. Sept 19:00; drei kommen aus HTML, das bis zu
   **13 Migrationen** (617 kB SQL) alt ist. Der frische Dateistempel verdeckt das.
3. **Ein Prüfstand, der nicht durchfallen kann.** `pruefstand/bildschirme.mjs` zählt
   Fehler, druckt sie — und endet mit `process.exit(0)`. Drei Abmachungen hängen
   allein daran.

---

## 0. Wie gemessen wurde

| Was | Befehl |
|---|---|
| Objektzahlen | `psql -d karte_doku -Atc "select count(*) … pg_class … relkind in ('r','v','m','i')"` |
| Datenbank-Suite | `./supabase/test/run.sh 'postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432'` → Exit 0 |
| Modultests | `npm test` → 81/81 grün |
| Zeilen | `find src -name '*.ts' -o -name '*.tsx' \| xargs wc -l` |
| Beweisstellen der Abmachungen | Skript: jeden Rückstrich-Bezeichner und jedes Zitat der Spalte „Beweis" mit `grep -rlF` gegen `src supabase pruefstand test pruefwerk .github` |
| CI-Deckung | `grep -c "kette" .github/workflows/pruefung.yml` → **0** |
| Lückenscanner-Schärfe | drei Spalten in `karte_doku.auftrag` gepflanzt, `luecken.sh` dagegen laufen lassen |
| PDF-Seiten | `python3` über `/Type /Page` und `/Count` |
| Bündel | `ls -la dist/assets/` |

---

## 1. Die 48 Abmachungen — gibt es den genannten Test, läuft er, prüft er das?

47 Zeilen in der Haupttabelle plus AB-14 in der Tabelle „Noch offen" = 48. ✔

**Deckung, gemessen:**

| Klasse | Anzahl | Kennungen |
|---|---|---|
| Beweis existiert, ist ausführbar, läuft in der CI | 39 von 48 | — |
| **Kein einziger Beweis, den die CI ausführt** | **9 von 48 (19 %)** | AB-05, AB-06, AB-10, AB-14, AB-18, AB-35, AB-38, AB-42, AB-44 |
| Kein ausführbarer Test überhaupt | 3 | AB-18, AB-44 (AB-14 ist erklärt offen) |
| Einziger Test ist `bildschirme.mjs` (kann nicht rot werden) | 3 | AB-10, AB-38, AB-42 |
| Einziger Test ist `kette.mjs` (nicht in der CI) | 3 | AB-05, AB-06, AB-35 |
| **Zeile beschreibt Verhalten, das der Code so nicht mehr hat** | **5** | AB-02, AB-09, AB-12, AB-25, AB-27 |

Das widerlegt den Kopfsatz der Datei: *„Alles hängt in der CI
(`.github/workflows/pruefung.yml`)."* Die CI (67 Zeilen, drei Jobs) ruft `npm ci`,
`npm test`, `npm run build`, `run.sh`, `beschriftung.mjs`, `bildschirme.mjs` — **nicht**
`kette.mjs`, **nicht** `kette_pruefen.sh`, **nicht** `npm audit`, **nicht** das Prüfwerk,
**nicht** `simulation/matrix.sh`. 20 der 48 Zeilen nennen `kette` als Beweis.

### 1.1 Die fünf veralteten Zusagen (wertvollste Fundklasse)

| # | Zeile behauptet | Was der Code tut | Beleg | Wer widerruft |
|---|---|---|---|---|
| **AB-02** | „Ohne Ablesung kein Abschluss." | Der Abschluss ist nur bei Sortieren und Waschen + Sortieren gesperrt: `paloxPflicht: !fax && a.station !== 'waschen'` (`src/arbeit/daten.ts:155`); bei Waschen und Fax gibt es den Knopf `#palox-ohne` (`Abschluss.tsx:129-130`) | `Abschluss.tsx:72` | AB-28 („Beim Waschen ist die Ablesung freiwillig") — ohne Verweis auf AB-02 |
| **AB-09** | „Die Lagerkontrolle hält fest, wie die Palette gegriffen wurde." | `Kontrolle.tsx:25-26`: „Nicht mehr gefragt wird ‚davon faul' und ‚wie gegriffen'." Die Spalte `verdunstung_wiegung.auswahl` steht seit 0061 auf der Ausnahmeliste in `luecken.sh:70` | `pruefung.sql:1735` prüft nur, dass die **Datenbank** den Wert hält | AB-36 |
| **AB-12** | „Am Waschbecken werden **Kisten** gezählt." | Gezählt wird die **Palette**: `auftrag_palette.sortierdatum` + `.kisten`. Eine Tabelle mit `kist` im Namen gibt es nicht (`information_schema.tables` → 0 Treffer) | `auftrag_palette`-Spalten | AB-33 |
| **AB-25** | „**Kein Käufer mehr.**" | `kaeufer`-Tabelle mit 4 Zeilen; `Stammdaten.tsx:384-436` legt Käufer an und schreibt `sortierschema.kaeufer` (3 von 25 Fassungen); `Betrieb.tsx:125` zeigt `a.kaeufer`; **210 von 309** Demo-Arbeiten tragen einen Käufer, gesetzt von `0052_demo_saison.sql:157/244/257` | `psql -Atc "select count(*) filter (where kaeufer is not null) from auftrag"` → 210 | — (die Zeile selbst nennt `luecken.sh` „als begründete Ausnahme") |
| **AB-27** | „Beim Waschen trägt jede gezählte **Kiste** ihr Sortierdatum." | Das Sortierdatum hängt an der Palette. Ausserdem nennt die Zeile die Kennungen `#kistendatum` und `#kein-datum` — **beide existieren nirgends**; die echten heissen `#sortierdatum` und `#kein-sortierdatum` (`kette.mjs:457/462`) | `grep -F '#kistendatum' pruefstand/kette.mjs` → 0 | AB-33 |

**Gegenrede.** Man kann sagen: die Liste ist ein *Protokoll* der Absprachen, kein
Zustandsbericht — eine alte Zeile darf stehenbleiben. Dagegen steht der eigene
Kopfsatz der Datei: *„Eine Zeile ohne grünen Test gilt als offen"*, und der Anhang:
*„Wer eine neue Abmachung umsetzt, trägt sie hier ein und nennt den Test."* Die
Datei ist als lebende Deckungsliste gebaut, nicht als Archiv. Und der Beweis von
AB-09 ist grün, obwohl die Zusage nicht mehr eingehalten wird — genau der Fall,
gegen den die Datei geschrieben wurde.

### 1.2 Einzelbefunde je Kennung (nur die auffälligen)

| Kennung | Befund |
|---|---|
| AB-02 | Zitat „Palox …" im Beweis ist keine auffindbare Zeichenkette (0 Treffer). |
| AB-10 | Beweis = Frontend-Verweis + `bildschirme.mjs`. **Kein wirksamer Test.** |
| AB-13 | 8 Teilzusagen; „ab 1. Juli 2026" und „Journal L nicht" leben nur in `AusgangImport.tsx:28-30, 231-232` (`ZEITRAUM_AB`, `JOURNAL_INTERN`) und werden von **keinem** der 28 Tests in `test/warenausgang.test.ts` berührt (`grep ZEITRAUM_AB test/` → 0). |
| AB-18 | Beweis ist ausschliesslich „Überblick (…), Ursachen (…); `ENTSCHEIDUNGEN.md` Runde E" — **ein Dokumentverweis, kein Test.** |
| AB-20 | Alle Bezeichner vorhanden (`v_verdunstung_messung.verwendbar` ✔). Die genannte Auffälligkeit „Wägung" tritt in der Demosaison **nie** auf; `run.sh` Stufe 4b erzeugt sie eigens („drei Auffälligkeiten nennen den Grund"). |
| AB-31 | `erg_verlauf.prognose` existiert ✔ (Matview, nicht in `information_schema.columns` — wer dort nachsieht, findet sie nicht). |
| AB-32 | „gemessen 33 s statt 1.1 s" ist unbelegt im Bestand; `run.sh` misst heute Schritt 1 = 125 ms, alle fünf zusammen 2 838 ms, Dashboard 26,8 ms. |
| AB-36 | `v_kontrolle_vorschlag.informationswert` existiert ✔. |
| AB-39 | `beschriftung.mjs` läuft in der CI und **endet mit Exit 1** bei Beanstandungen ✔ — der schärfste der Prüfstände. Die Zahl „2667 Zahlen" ist ein Laufergebnis, nicht im Code fixiert; 12 Ansichten ✔ (`SEITEN`-Liste, Zeilen 60–79). |
| AB-44 | Beweise: `npm audit --omit=dev` (heute: 0 Schwachstellen ✔, aber **in keiner CI und keinem Skript**), `npm run pruefen` mit **„76 Tests"** — es sind **81** (14+9+12+8+5+2+3+28), `.gitignore` fängt `src/**/*.js` ✔ (Zeilen 23–26). |
| AB-45 | `run.sh` Stufe 2 vergleicht 2633 Objekte ✔ und misst **560 KB** — die Zeile sagt „1000 KB"-Grenze ✔, `PROMPT_RUNDE_M` sagt 574 kB. Beide richtig (KiB vs. kB), aber nirgends steht welche Einheit. |
| AB-46 | Nachgemessen: **0** Sichten ohne Beschreibung, **0** Funktionen mit PUBLIC-Recht ✔. |
| AB-47 | Nachgemessen: `kg_beobachtet + kg_projiziert = kg` auf **allen 366 Zeilen** von `erg_verlust` ✔ (0 Abweichungen). Die genannte Art „Tara fehlt" sitzt nicht in `v_plausibilitaet`, sondern in `v_plausibilitaet_0064_zusatz` — Sonde 10 findet sie trotzdem, weil sie über alle Teil-Sichten sucht. |

---

## 2. Die 21 Annahmen in ABLAUF.md (Zeilen 417–437)

21 Zeilen, vierspaltig ✔. Sonde 10 bewacht die vierte Spalte, aber nur teilweise:
sie prüft **genannte Auffälligkeiten** (`Auffälligkeit „…"`) und **genannte Dateien**
(`*.ts|mjs|sql|md`). **Zeiger auf Bildschirme prüft sie nicht** — und genau dort
liegen die zwei Fehler.

| # | Annahme (gekürzt) | Wo es auffiele (Spalte 4) | Nachgemessen |
|---|---|---|---|
| 1 | Alle Paletten unter gleichen Bedingungen | nirgends, bewusst | ✔ begründet |
| 2 | Verdunstungsrate über die Zeit konstant | Ursachen → Verdunstung, Punkte über Lagerdauer | ✔ `Ursachen.tsx:169-171` |
| 3 | Palette hat bei Wägung dieselbe Kistenzahl | nirgends; S7 beziffert 11 % | ✔ |
| 4 | Alles Sortierte wird später gewaschen | **„Betrieb → Tempo: ‚wartet' zeigt, was sortiert ist und noch nicht gewaschen"** | **✗ Diese Zahl gibt es nicht.** `grep -rn wartet src` findet nur die Typfelder `gegenprobe_wartet_kg` / `wartet_kg` — kein Bildschirm rendert sie. Die Karte „Arbeit und Tempo" (`Betrieb.tsx:87`) zeigt Dauer, Masse, kg/h. **AB-18 verbietet die Zahl sogar ausdrücklich** („keine Menge, die nur aus Arbeiten stammt — ‚sortiert', ‚gewaschen', ‚wartet aufs Waschen'"). Die Annahme ist damit unbewacht. |
| 5 | Palox gehört zu der Arbeit | Auffälligkeit „Palox geleert" | ✔ existiert, tritt 5× auf |
| 6 | Waschgang gehört zu den Sortierläufen davor | nirgends | ✔ begründet |
| 7 | Dubletten-Regel entfernt Maschinen-Doppel | `test/csv.test.ts`; **„Messungen → Kaliber zeigt die Verteilung vor und nach der Bereinigung"** | Datei ✔ (14 Tests). Bildschirm **✗**: `Messungen.tsx` zeigt „Kistengewicht je Kaliber", **nicht** den Reinigungs-Trichter — der steht auf **Betrieb → Sortier-CSV** (`CsvUpload.tsx:102,154`). Falscher Reiter genannt. |
| 8 | Palox-Waage zeigt brutto, 45 kg | Auffälligkeit „Schimmel" | ✔ existiert, 2× |
| 9 | Kaliber-Kiste bleibt dieselbe Kiste | Auffälligkeit „Kistengewicht" | ✔ existiert, 3× |
| 10 | Alle Kisten eines Kalibers gleich schwer | Messungen → Kistengewichte, Bereich daneben | ✔ `Messungen.tsx:129-133` mit Spalte „Bereich" |
| 11 | Überfüllung gilt für alle verkauften Kisten | Ursachen → Überfüllung nennt gewogene Paletten | ✔ `Ursachen.tsx:453` |
| 12 | Sockel gilt für alle Verarbeitungsmessungen | Messungen → Sockel: Nachweis gegen Schwelle | ✔ `Messungen.tsx:151` |
| 13 | Sockel ist zeitunabhängig | nirgends, bewusst | ✔ |
| 14 | Auswahl nach Aussehen sieht aus wie Sockel | Messungen → Selektionsverdacht | ✔ `Messungen.tsx:155` (`erg_selektion`) |
| 15 | Kistensystem gilt für alle Kisten der Arbeit | nirgends | ✔ |
| 16 | Bestand je Eingangstag, kein FIFO | nirgends, bewusst | ✔ |
| 17 | Verkaufsfähiger Anteil, Boden 25 % | Auffälligkeit „Überzählung" (0064); Boden unbewacht, kleinster Anteil 0,671 | ✔ Art existiert (in `v_plausibilitaet_0054_zusatz`), tritt 9× auf |
| 18 | Gefallener Palox-Stand heisst geleert | Auffälligkeit „Palox geleert" | ✔ |
| 19 | Zettelgewicht bekommt mittlere Charge-Tara | Auffälligkeit „Zettelgewicht" | Art existiert in der Definition ✔, **tritt in der Demosaison nie auf** (0×; was auftritt heisst „Zetteldatum", 1×) |
| 20 | Fassung des Sortierschemas beim Start | nirgends | ✔ |
| 21 | „Alles aus einer Charge" stimmt | nirgends ausser der Frage | ✔ |

**Ergebnis: 19 von 21 Zeigern tragen, 2 zeigen ins Leere (#4, #7).** Sonde 10 kann
das nicht sehen, weil sie nur Auffälligkeitsnamen und Dateipfade prüft.

---

## 3. Jede Zahl nachgemessen

### 3.1 Stimmt (zur Absicherung, damit man weiss wie weit nachgesehen wurde)

| Behauptung | Wo | Gemessen |
|---|---|---|
| 11 201 Zeilen TypeScript in `src/` | PROMPT, C1 | **11 201** ✔ (574 619 Bytes, 55 Dateien) |
| i18n.ts 1434 · Stammdaten 815 · daten.ts 556 · Ursachen 527 · Diagramm 515 | PROMPT C1 | alle fünf exakt ✔ |
| 28 Tabellen, 63 Ansichten, 38 gespeicherte, 42 Funktionen, 93 Indexe | PROMPT | alle exakt ✔ (dazu 22 Auslöser, 78 RLS-Regeln) |
| 2633 Objekte im Fingerabdruck | PROMPT, AB-45 | **2633** ✔ (`run.sh` Stufe 2, beide Wege deckungsgleich) |
| 67 Migrationen, Stand 0066 | PROMPT | ✔ |
| 81 Modultests | PROMPT | **81** ✔ (14+9+12+8+5+2+3+28) |
| 323 268 kg Eingang · 844 Paletten · 187 Lieferungen · 42 Chargen | PROMPT, README | alle ✔ (309 Arbeiten, 36 Chargen mit Paletten, 11 Sorten, 161 Fax, 32 Sortierläufe, 24 Lagerkontrollen) |
| Verlust 52 119 kg = 16,12 % des Eingangs | PRUEFBERICHT BEZ-001 | ✔ (52 119,38 / 323 268,00) |
| 25,1 % · 13,1 % · 18,0 % | PRUEFBERICHT, FRAGEN 51 | ✔ (207 432 / 138 950 / 188 498 kg, Überzählung 4 179,88 kg erklärt die Differenz) |
| Bilanzrest unter 1 kg | AB-41 | **−0,01 kg** ✔ |
| 9 Chargen mit Überzählung, grösste 36,6 % | PLAN_REPARATUREN | ✔ exakt (Charge 1635: 2 261,07 von 6 184,20 kg) |
| 366 Zeilen `erg_verlust`, `kg_beobachtet + kg_projiziert = kg` | PLAN 6.1 | **366** ✔, 0 Abweichungen |
| Bündel 351 / 245 / 190 / 39 kB | PROMPT C5 | ✔ (351 420 / 245 510 / 190 595 / 39 086 Bytes) |
| Vier `not valid`-Bedingungen | PROMPT B4 | ✔ (`auftrag_kaliber_nur_waschen`, `auftrag_fax_nur_waschen`, `auftrag_palette_datum_pflicht`, `lieferung_hat_menge`) |
| Zeitzone `Etc/UTC` | PROMPT B5 | ✔ |
| 8 Papierfälle in Sonde 07, Selbstprobe bricht mit Exit 2 ab | ENTSCHEIDUNGEN Runde L | ✔ (`lauf.mjs:81-83`) |
| 52 Fragen in FRAGEN.md, Teil 1 = 1–25, Teil 2 = 26–50 | FRAGEN.md | ✔ |

### 3.2 Stimmt nicht mehr

| Behauptung | Wo | Gemessen | Abweichung |
|---|---|---|---|
| „**76 Tests**" | ABMACHUNGEN AB-44 | 81 | +5 |
| „**2613 Objekte**, jede Spalte" | README:728 **und** `programm.html` | 2633 | −20 |
| „setup.sql (rund **14 000 Zeilen**)" | `programm.html` | 10 625 | +32 % zu hoch |
| „**62 Auswertungen**" in der Fertig-Zeile | README:161 | Die Zeile sagt heute **63** | −1 |
| „Mutationssonde … rund **13 Minuten**" | README:788 | PRUEFBERICHT misst **1049,1 s = 17,5 min** | −26 % |
| „**27 Tests**" für den Warenausgang | README:707 | 28 `test(`-Aufrufe | −1 |
| „**33 Seiten**" (Das-Programm-erklaert.pdf) | README:653 | **38** Seiten (`/Count 38`) | −5 |
| „Überfüllung **je Käufer**" | README:704 | AB-37 hat den Käufer aus der Überfüllung entfernt; `erg_ueberfuellung` gruppiert nach Kistensystem | Widerspruch |
| „**├ 56 Sichten**, ├ **7 gespeicherte**, ├ **34 Funktionen**, └ **80 Zugriffsregeln**" (Architekturkasten) | `programm.html` | 63 / 38 / 42 / 78 | −7 / **−31** / −8 / +2 |
| „Rund **60 Sichten**, **acht** davon gespeichert" | `programm.html` §2.5 | 63 / 38 | **Faktor 4,75 bei den gespeicherten** |
| „zusammen — statt **1 116 kB** … **529 kB**" | `programm.html` | Migrationen heute 1 279,6 KiB, setup.sql 560,8 KiB | +15 % / +6 % |
| „damals **63 Migrationen**" | `programm.html` | 67 (als historische Aussage vertretbar, aber nicht markiert) | −4 |
| „**2633 Objekte**" und „**2613 Objekte**" im **selben** Dokument | `programm.html` | Das Dokument widerspricht sich selbst | — |
| „In Runde I −4 274 kg; nach 0062 sind es **−0,05 kg**" | DATENFLUSS §4 | heute **−0,01 kg** | Kleinigkeit, aber messbar |
| „In der Demo-Saison: **−4,5 %, −1,2 %, +3,8 %**" | DATENFLUSS §4 (Selbstkontrolle) | 25 Zeilen in `erg_massenbilanz`: Mittel **+11,0 %**, Spanne **−5,1 % bis +49,2 %**, **7 von 25** über ±20 % | **Die drei genannten Zahlen sind die drei kleinsten.** Der Satz darüber („Streuung um 0 → die Koeffizienten treffen") ist mit den heutigen Zahlen nicht haltbar. |
| „**Hauptknöpfe 56–72 px**" | UI-KONZEPT | gemessen 60 px (`button.gross`, `.haupt-unten button`) und 64 px (`.start-knoepfe`, `.schritt-…`) | Spanne zu weit |
| „Ziele **mindestens 44 pt / 48 dp**" (WCAG 2.5.5 AAA) | UI-KONZEPT, Leitlinientabelle | drei Klassen darunter: `button.klein` **32 px** (`index.css:256`), `.kopf button` **34 px** (:157), `.umschalter button` **38 px** (:267) | 6–12 px zu klein, 12 Verwendungsstellen |
| „**Fünf Reiter**" | UI-KONZEPT | Die Tabelle darunter hat **sechs** Zeilen (Messungen steht zweimal) | Zählfehler in der eigenen Tabelle |
| „Zähler **84 px**" | UI-KONZEPT | `.zaehler-plus min-height: 84px` ✔ | — |
| Zwei Fragen „**Nummer 51 und 52**" | PROMPT §9, FRAGEN.md | In `fragen.html` (und damit im PDF, das der Betrieb liest) heissen sie **21 und 22** | Zitierfalle |

### 3.3 Nicht nachprüfbar (und das ist selbst ein Befund)

- `WARENAUSGANG_BEFUND.md` misst alles an drei Excel-Dateien vom 6. Sept, die
  bewusst nicht im Repo liegen (`/root/.claude/uploads/…` ist heute leer, nur ein
  Sitzungsordner). **26 Zahlen** dieser Datei (5 649 / 6 496 Zeilen, 649,6 t / 315,8 t,
  102 / 13 / 335 / 481 / 312 / 493 / 16 / 11 / 137 / 57 / 373 / 44 / 232 von 236 …)
  sind damit nicht reproduzierbar. Die Ersatzdatei `test/daten/warenausgang-probe.xlsx`
  (6,4 kB, gebaut von `probe_bauen.py`) existiert ✔, prüft aber die *Form*, nicht diese Zahlen.
- `STATISTIK_BEFUND.md` (948 Zeilen, 49 kB) ruht vollständig auf
  `supabase/test/simulation/matrix.sh`. Dieses Skript wird von **keinem** automatischen
  Pfad aufgerufen: nicht in `.github/workflows/pruefung.yml`, nicht in `run.sh`, nicht in
  `package.json` (`grep -rn "simulation\|matrix.sh"` → 0 Treffer ausserhalb von `docs/`).
  Vier der 21 Annahmen (#12, #13, #14 und die Sockel-Zeile) zeigen darauf.

---

## 4. Doku sagt A, Code tut B — die vollständige Liste

Über Abschnitt 1.1 hinaus:

| # | Doku | Code | Grösse |
|---|---|---|---|
| **4.1** | ABMACHUNGEN-Kopf: „Alles hängt in der CI." | `kette.mjs`, `kette_pruefen.sh`, `npm audit`, `pruefwerk/`, `simulation/` laufen in keiner CI-Zeile | **9 von 48 Zusagen (19 %)** ohne CI-Beweis |
| **4.2** | CI-Schritt heisst „Jeder Bildschirm ohne Konsolenfehler und ohne Überlauf" | `bildschirme.mjs:298-299` zählt `fehler`, druckt sie und ruft **`process.exit(0)`** | 24 Bildschirme × 4 Varianten = **96 Aufnahmen**, deren Befunde die CI nie rot machen; 3 Abmachungen hängen allein daran |
| **4.3** | ABLAUF #4 verweist auf „Betrieb → Tempo: ‚wartet'" | Diese Zahl existiert im UI nicht; AB-18 verbietet sie | 1 unbewachte Annahme |
| **4.4** | ABLAUF #7 verweist auf „Messungen → Kaliber … vor und nach der Bereinigung" | Der Trichter steht auf Betrieb → Sortier-CSV | falscher Reiter |
| **4.5** | `Messungen.tsx` zeigt dem Betriebsleiter zu jedem Datenqualitäts-Balken eine Abmachungs-Kennung | **4 von 10 sind falsch**: Zeile 218 und 223 sagen AB-31 (= „alles bis heute"), gemeint ist AB-33; Zeile 221 sagt AB-25, gemeint AB-26; Zeile 222 sagt AB-26, gemeint AB-25 — **AB-25 und AB-26 sind vertauscht** | 4 von 10 Zeigern, direkt vor dem Nutzer |
| **4.6** | PRUEFBERICHT BEZ-001 verankert bei `src/pages/Ueberblick.tsx:66` | Dort steht der **Eingang**-Wert; „% des Eingangs" steht auf **Zeile 79** (`befunde.json` → `{"zeile": 66}`) | 13 Zeilen daneben, im automatisch erzeugten Bericht |
| **4.7** | PRUEFBERICHT LNN-001: „alle **7** Stellen mit `?? 0` an einer Masse sind begründet" | Der Suchausdruck in `08_leer_nicht_null.mjs:137` verlangt `_kg` (mit Unterstrich) im Bezeichner. `.kg`, `kg_unten`, `kg_oben`, `kg_verkauft`, `kg_pro_h` fallen durch. Übersehen: `daten.ts:415` (`z.kg`, `z.kg_unten`, `z.kg_oben`), `Stammdaten.tsx:303` (`z.kg`), `Ursachen.tsx:521` (`u.kg_verkauft`), `Ueberblick.tsx:180` (`eingang`), `PaloxMaske.tsx:53` (`menge`), `Ursachen.tsx:297` (4× `mittel`) | **mindestens 8 weitere Massenstellen**, die Zahl 7 ist ein Artefakt des Suchausdrucks. Insgesamt 67 `?? 0` in `src/`. |
| **4.8** | SPEC.md ist laut README:878 „Fachliche Spezifikation"; laut Kopf „die vollständige Übergabe" | Zuletzt bei Commit 80c4c71 (Runde F, 0048) angefasst. §2 nennt **fünf Ströme und zwei Bücher**; die Datenbank hat **sechs Ströme** (Verdunstung, Schimmel/Fäulnis, Nicht lagerbedingt, Zu klein (Tierfutter), Nebenkanal zu gross, Faul beim Abpacken) und **drei Bücher** (`feld`, `marge`, `verlust`). §2 nennt „Ausschuss zu klein = Verlust (total)" — seit dem 2. Sept ist es kein Verlust mehr (Tierfutter). §2 nennt „Restware am Saisonende" — AB-31 rechnet bis heute. | 4 substanzielle Widersprüche in dem Dokument, das als Einstieg beworben wird |
| **4.9** | DATENFLUSS §3: „`select round(kg,1) from v_verlust_ranking` funktioniert ohne Umweg" | `v_verlust_ranking` existiert ✔ (dazu die Funktion `verlust_ranking`) | ✔ stimmt |
| **4.10** | AB-25 „Kein Käufer mehr" | `0052_demo_saison.sql` verteilt weiter Coop/Migros auf **210 von 309** Arbeiten und legt käuferabhängige Sortierschemata an. Jeder Screenshot, jede Prüfstands-Attrappe und jede Doku-Zahl stammt aus dieser Saison; `Betrieb.tsx:125` zeigt „· Coop" | 210 Arbeiten, 3 Schemafassungen, 4 Käufer |
| **4.11** | i18n-Schlüssel `kaeufer: 'Für welchen Käufer?'` | Kein `t('kaeufer')` im Bestand. Ebenso tot: `abschluss`, `baender`, `fehler`, `abgebrochen` | **5 Schlüssel × 6 Sprachen = 30 tote Zeilen** in `i18n.ts` (von 218 Schlüsseln; 205 direkt über `t('…')`, 8 über die dynamischen Tabellen `taet.text` / `ERKL[a.id]`) |
| **4.12** | ENTSCHEIDUNGEN Runde L: Selbstprobe „meldet ‚STUMPF' und **bricht ab**" | `lauf.mjs` lässt erst alle zehn Sonden laufen und beendet danach mit Exit 2 (`lauf.mjs:81-83`) — kein Abbruch, sondern ein Nachtrag | Formulierung, keine Wirkung |
| **4.13** | Alle fünf PDFs tragen den Baustempel 9. Sept 19:00 | `architektur.html` ist vom **3. Sept 10:03** — seither kamen die Migrationen 0054–0066 dazu (**13 Stück, 617 478 Bytes SQL**). `erklaerung.html` und `ablauf.html` sind vom **8. Sept 21:52** — ohne 0063–0066 (183 089 Bytes). Weder „Überzählung" noch „entsorgt" noch „Leer ist nicht null" kommen in `erklaerung.html` vor (je 0 Treffer) | **Datenarchitektur.pdf beschreibt ein Schema, das 13 Migrationen zurückliegt**, und Kuerbis-Verlust-Tracking.pdf („die vollständige Offenlegung inklusive der Mathematik") kennt die dritte Kaskadenportion nicht |

---

## 5. Was im Code passiert und in keinem Dokument steht

Gemessen: jeden der **171** Namen (28 Tabellen + 63 Sichten + 38 Matviews + 42 Funktionen)
gegen `docs/*.md docs/*.html README.md` gegrept.

**57 von 171 Objekten (33 %) kommen in keinem Dokument vor.**

| Gruppe | Anzahl | Beispiele |
|---|---|---|
| Gespeicherte Ansichten (`erg_*`) — die Schicht, aus der die App **ausschliesslich** liest | 21 von 38 | `erg_charge`, `erg_modell`, `erg_kurve`, `erg_punkte`, `erg_selektion`, `erg_koeff_verdunstung`, `erg_massenbilanz`, `erg_durchsatz`, `erg_wiegung`, `erg_plausibilitaet` … |
| Sichten | 17 | `v_koeff_unsicherheit`, `v_koeff_roh_verdunstung`, `v_koeff_verdunstung_geschaetzt`, `v_schimmel_modell_rechnen`, `v_gewichtsverteilung`, `v_datenqualitaet`, `v_verkauf_lieferung` … |
| Funktionen | 18 | `t_quantil_95`, `sockel_anteil`, `anteil_plausibel`, `korrekturfenster`, `ist_beteiligt`, `auswertung_veraltet`, `auswertung_wenn_veraltet`, `palox_letzter_stand`, `rolle_schuetzen`, `handle_new_user` |

Dazu Muster und Verhalten, das nirgends beschrieben ist:

1. **Das „Zusatz-Sicht"-Muster.** `v_plausibilitaet` wird nicht ersetzt, sondern von
   späteren Migrationen per Union um `v_plausibilitaet_0054_zusatz` und
   `v_plausibilitaet_0064_zusatz` erweitert. Wer `v_plausibilitaet` liest, sieht mehr
   Arten, als in ihrer eigenen Definition stehen (14 in der Basis, **17 insgesamt**,
   darunter „Überzählung", „Lieferung in der Zukunft", „Tara fehlt"). Kein Dokument
   erwähnt das Muster; ABMACHUNGEN AB-47 nennt „Tara fehlt" als Art von
   `v_plausibilitaet`, was nur wegen des Unions stimmt.
2. **`mv_kaskade.eingang_kg` ist nicht die Masse dieser Zeile,** sondern die
   Eingangsmasse der **ganzen Charge**, auf jeder Portion und jeder Kohorte wiederholt.
   `sum(eingang_kg)` über die Sicht ergibt **645 375 kg** statt 323 268 kg — **+99,6 %**.
   Die Sichtbeschreibung warnt vor den Strömen („wer die Ströme summiert, muss es
   lesen"), nicht vor dieser Spalte. Genau diese Sicht steht in AB-23 und DATENFLUSS §2
   als Herzstück, und README/DATENFLUSS laden ausdrücklich zum direkten `select` im
   SQL-Editor ein.
3. **Keine einzige Spaltenbeschreibung.** `col_description` über alle Sichten und
   Matviews: **0 von 1412 Spalten**. AB-46 fordert Beschreibungen nur auf Sichtebene
   (dort ✔ erfüllt); für den beworbenen Weg „Supabase → Table Editor / SQL" bedeutet
   das: 1412 Spalten ohne Auskunft.
4. **Neun Arten von Auffälligkeiten treten in der Demosaison nie auf.** Von 17 Arten
   feuern 7 (Überzählung 9×, Palox geleert 5×, Kistengewicht 3×, Schimmel 2×, Ohne
   Nenner 1×, Zetteldatum 1×, Lieferung in der Zukunft 1× — zusammen 22 Zeilen).
   Nie: Ausschuss, Ausschuss ohne Tara, Ausschuss-Tara, Fax, Kaliber fehlt, Lieferung
   ohne Eingang, Palox, Tara fehlt, Wägung, Zettelgewicht. Kein Dokument sagt, welche
   Arten es überhaupt gibt.
5. **`erg_datenqualitaet`** trägt 26 Zähler, von denen `Messungen.tsx` zehn zeigt.
   Nirgends steht, was die übrigen 16 messen.
6. **Der Lückenscanner prüft nur 52 Spalten** in 11 Tabellen — die anderen 17 Tabellen
   sind gar nicht in `TABELLEN`. Das steht in keinem Dokument, auch nicht im Anhang von
   ABMACHUNGEN, der ihn als beidseitige Vollständigkeitsprüfung beschreibt.

---

## 6. Die Werkzeuge selbst — was sie messen können und was nicht

Das gehört in diese Karte, weil sechs Doku-Behauptungen daran hängen.

| Werkzeug | Kann es rot werden? | Gepflanzter Fehler | Reaktion |
|---|---|---|---|
| `pruefstand/luecken.sh` | ja (Exit ≠ 0) | drei Spalten in `karte_doku.auftrag`: `testspalte_xyz`, `sorte`, `lagertage` | **nur 1 von 3 gefunden.** Der Beweis „wird geschrieben" ist `grep -rqE "(^\|[^a-z_])$c[[:space:]]*[:,}]"` bzw. `grep -rqF "'$c'"` über `src/` — ein blosses Vorkommen des Namens, auch in einer `.select()`-Zeichenkette oder einem TypeScript-Feld, gilt als Schreibnachweis. Jede neue Spalte, die wie ein vorhandener Bezeichner heisst (`sorte`, `kisten`, `datum`, `lagertage`), rutscht durch. Heute nutzt das keine Spalte aus (52/52 haben echte Schreibstellen) — die Regel ist die Lücke, nicht der Bestand. |
| `pruefstand/bildschirme.mjs` | **nein** — `process.exit(0)` in Zeile 299 | — | Zählt Überlauf und Konsolenfehler in `fehler`, druckt „✗ …" und endet trotzdem mit 0. Die Schlusszeile nennt Überlauf-Treffer irreführend „Seiten mit Konsolenfehlern". |
| `pruefstand/beschriftung.mjs` | ja, Exit 1 | — | scharf, in der CI |
| `pruefstand/kette.mjs` | ja, Exit 1 (`schritt()` bricht sofort ab, Zeile 193) | — | scharf, **aber nicht in der CI** |
| `supabase/test/run.sh` | ja | — | 9 Stufen (1, 2, 3, 3b, 4, 4b, 5, 6, 6b, 7), Exit 0 im Lauf von heute |
| `pruefwerk/lauf.mjs` | ja, Exit 2 bei STUMPF | — | scharf, **nicht in der CI** |
| `supabase/test/simulation/matrix.sh` | ja | — | **wird von nichts automatisch aufgerufen** |
| `pruefwerk/sonden/08` (8b) | ja | — | Suchausdruck zu eng, siehe 4.7 |
| `pruefwerk/sonden/10` | ja | — | prüft Auffälligkeitsnamen und Dateipfade, **nicht** Bildschirmzeiger — deshalb bleiben ABLAUF #4 und #7 unentdeckt |

**Frischer Lauf von `run.sh` (heute):** Fingerabdruck 2633 = 2633, setup.sql 560 KB von
1000 KB, Schritte 125 / 1065 / 669 / 692 / 287 ms, 30 Dashboard-Ansichten in 26,794 ms;
dreifache Saison: Neurechnen 5129 ms, Dashboard 25,100 ms. Alle Stufen bestanden.
Die „30 gespeicherten Dashboard-Ansichten" sind genau die 30 `erg_*`-Matviews, die
`src/` liest — die übrigen 8 (`mv_*`) sind Zwischenstufen, kein Totholz. ✔

---

## 7. Was die nächsten Werkstätten hieraus mitnehmen sollten

- **A (Rechenwerk):** `erg_massenbilanz` widerlegt DATENFLUSS §4 (Mittel +11,0 %, bis
  +49,2 %). Das ist der schärfste vorhandene Aussentest des Modells, und er sagt heute
  etwas anderes als die Doku. `mv_kaskade.eingang_kg` als Fallgrube.
- **B (Fundament):** 1412 Spalten ohne Beschreibung; das Zusatz-Sicht-Muster;
  vier `not valid`-Bedingungen; `Etc/UTC`; 10 von 17 Auffälligkeitsarten nie geprüft
  auf echten Daten.
- **C (Bauwerk):** 30 tote i18n-Zeilen; 3 Bedienziele unter 44 px; 67 Stellen `?? 0`,
  davon 7 begründet und mindestens 8 unerkannt; 57 von 171 Datenbankobjekten ohne
  Dokument.
- **D (Nutzen):** Der Betriebsleiter bekommt auf dem Messungen-Bildschirm **4 von 10**
  Abmachungs-Kennungen falsch angezeigt; die zwei offenen Fragen tragen im PDF andere
  Nummern (21/22) als im Repo (51/52); die PDFs, die er wirklich liest, sind bis zu
  13 Migrationen alt.
