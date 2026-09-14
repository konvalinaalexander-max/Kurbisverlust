# Design Runde R: Lagermanagement und Ursachen — verbindlich, Block für Block

Dieses Dokument ist Teil des Auftrags `docs/PROMPT_RUNDE_R.md` und **verbindlich**:
Es legt fest, wie die zwei Reiter aussehen, wie jeder Block aufgebaut ist, was
er sagt, und wie er sich bedienen lässt. Die ausführende KI hat hier keinen
Gestaltungsspielraum — sie hat Handwerksspielraum (wie sie es sauber baut).
Wo etwas nicht festgelegt ist, gilt `docs/DESIGN_RUNDE_O.md` (das gebaute
Designsystem) und dann die Regel: **weglassen**. Jede Abweichung steht mit
Grund in `docs/BEFUND_RUNDE_R.md` § 3; eine stille Abweichung ist ein Fehler.

## 0. Der Massstab

Der Betriebsleiter steht mit dem Handy in der Halle oder sitzt abends am
Laptop. Er will in zehn Sekunden wissen: *Was liegt, was davon verkauft sich,
in welchem Kaliber, und wie sieht das in ein paar Wochen aus?* Und am
Saisonende: *Wohin ist mein Kürbis gegangen, wann und wo hat es angefangen zu
faulen, was verschenkt die Waage?* Alles andere ist Ballast.

Drei Sätze, die jede Entscheidung entscheiden:
1. **Zahlen zuerst, Erklärung auf Wunsch.** Die Zahl steht gross, ihr Nenner
   und ihre Herkunft klein daneben; das „Warum" liegt zu, hinter „Wie diese
   Zahlen entstehen".
2. **Weniger, dafür richtig.** Jeder Reiter hat vier bis fünf Blöcke, nicht
   mehr. Ein Block, der eine Frage des Betriebs nicht beantwortet, kommt weg.
3. **Nichts wird behauptet, was nicht gemessen oder gerechnet ist.** Leer ist
   ein Strich mit Grund, nie eine Null. Prognose ist gestrichelt und trägt das
   Wort. Was aus der Sorte statt aus der Charge stammt, sagt es.

## 1. Das Gerüst (beide Reiter)

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Seitenleiste (≥1024 px) │  Reiterkopf: Titel · ein Satz Zweck   [Stand · Neu rechnen]
│  Lagermanagement        │  ┌─ Filterleiste (haftend) ────────────────────────────┐
│  Ursachen               │  │ ⌕ Ansicht [ alle Chargen ▾ ]  (Chip: Tiana)  n Chargen│
│  Chargen                │  └──────────────────────────────────────────────────────┘
│  Messungen              │  Block 1 (Karte / Kennzahl-Reihe)
│  Betrieb                │  Block 2 (Karte)
│                         │  …
└──────────────────────────────────────────────────────────────────────────┘
```

- **Reiterkopf** wie heute (`Reiterkopf`): Titel, ein Satz Zweck, rechts der
  Stand-Chip und „Neu rechnen". Titel und Zweck sind festgelegt (§ 2, § 3).
- **Filterleiste** (`.filterleiste.haftend`): ein `<select>` mit `alle
  Chargen`, `optgroup Sorte`, `optgroup Charge` — **kein Schlag**. Rechts vom
  Feld der aktive Filter als Chip (`.aktiv-filter`), dann ein Satz
  „n Chargen · m mit Ware im Haus", dann „alle zeigen". Sie haftet beim
  Scrollen unter der Navigation (gibt es), damit der Filter nie aus dem Blick
  gerät. Die Wahl steht in der URL; beim Reiterwechsel wird sie mitgenommen
  (dieselben Suchparameter an den Link).
- **Karten** (`Karte`): Titel (`h2`, `--s-3`), Untertitel ein Satz
  (`.karte-unter`), rechts oben die Aktion (Umschalter, Feld). Innen zuerst
  die Zahlen, dann das Bild, dann Tabelle/Aufklapper, zuletzt die Fussnote
  (`.hilfe`) und die zugeklappte Erklärung (`Erklaerung`). Nie zwei Bilder in
  einer Karte. Nie eine Karte ohne Herkunftsmarke an ihrer Hauptzahl.
- **Breite:** Inhalt bis `--inhalt-breite` (1180 px). Karten stehen
  untereinander in voller Breite — **kein** Zwei-Spalten-Raster für Karten;
  nur Kennzahlen stehen als Reihe (`.kennzahl-reihe`, 4 → 2 → 1 Kacheln je
  nach Breite) und die zwei Marge-Karten nebeneinander ab 900 px
  (`.zwei-spalten`, links Kiste ab 3fr, rechts Stück 2fr).
- **Handy (390 px):** alles eine Spalte; Tabellen in `.rollbar` mit
  haftender erster Spalte; Diagramme 240 px hoch; Umschalter brechen unter
  den Titel (macht `.karte-kopf` schon). Die Seite scrollt **nie** waagrecht
  (Abnahme D-07).
- **Dunkel:** nur Tokens (`var(--…)`), keine Hex-Farbe im TSX. Beide Themen
  werden in `bildschirme.mjs` aufgenommen.
- **Bewegung:** was `DESIGN_RUNDE_O` hat (Zähler laufen, Linien zeichnen,
  Balken wachsen gestaffelt), sonst nichts Neues. `prefers-reduced-motion`
  schaltet alles ab.

### 1.1 Zahlen und Worte

| Was | So | Nie so |
|---|---|---|
| Masse ≥ 1 t | `tonnen()`: „23.4 t" | „23 440 kg", „23.44 t" |
| Masse < 1 t | `kg(w, 0)`: „640 kg" | „0.6 t" |
| Anteil | `prozent(a, 0)`: „76 %" — mit Nenner im Untertitel | „76.3 %", „0.76" |
| Gramm | „1 260 g", Band „600–1100 g" (Halbgeviertstrich, kein Leerzeichen um den Strich) | „600 - 1100g" |
| Datum | `datum()`: „12. Okt", im Tooltip „12. Okt 2026" | ISO-Daten auf dem Bildschirm |
| Unbekannt | „—" mit `title` (Grund) und, wo Platz ist, ein Satz in `.leise` | „0", leere Zelle ohne Grund |
| Herkunft | `Herkunft art="gemessen | gerechnet | prognose"` direkt an der Zahl | Herkunft nur in der Fussnote |
| Basis | Chip `.marke` „aus der Sorte" / „eigene Messung" / „wie Mittelmass" | Unmarkiert |

Sprache: Deutsch, Schweizer Schreibung (ss), kurze Sätze, keine Fachwörter
des Rechenwerks („Kaskade", „Koeffizient", „Portion") auf dem Bildschirm —
dafür „die Rechnung", „die Rate", „die Ware". Titel sind Fragen oder
Nominalphrasen, wie festgelegt; Untertitel höchstens ein Satz; Fussnoten
höchstens zwei Zeilen.

### 1.2 Der Farbvertrag

Farbe ist Bedeutung. Eine Sache hat auf allen Reitern dieselbe Farbe.

| Bedeutung | Token | Wo |
|---|---|---|
| verkauft (ausgeliefert, gute Ware draussen) | `--strom-rest` | Kennzahl Ausgang, Balken U1, Verlauf L2 |
| im Lager und verkaufsfähig | `hell(--strom-rest)` (42 % auf Fläche, wie heute `hell()`) | Kennzahl verkaufsfähig (Kante `ton-gruen`), Balken U1, Verlauf L2 |
| im Lager gesamt | `--kuerbis` | Kennzahl Im Lager (`ton-kuerbis`), Verlauf L2 |
| verdunstet | `--strom-verdunstung` | U1, U3, Verlauf |
| Faules (Lager, Feld, Abpacken) | `--strom-schimmel` | U1, U2 |
| zu klein | `--strom-ausschuss` | U1 |
| zu gross | `--strom-nebenkanal` | U1 |
| Rest der Zählung | `--text-ganz-leise` | U1, nur wenn > 0.5 kg |
| Modell (Kurve, Band) | `--text-leise`, gestrichelt; Band 12 % Deckung | U2, U3 |
| Prognose (ab heute) | dieselbe Reihenfarbe, gestrichelt | L2 |
| Kaliberbänder (Glocke, Zonen) | abwechselnd `--flaeche-2` / transparent, Grenzlinie `--rand` | L4, Tabelle L3 (Kopfzeile) |
| „unter Kaliber" | `--gelb` | L3, L4 |

**Sorten und Chargen als Reihen** (U2, U3) bekommen eine eigene, feste
Palette — nicht die Stromfarben, sonst sieht „Tiana" aus wie „Verdunstung".
Neu in `src/design/tokens.css`, hell und dunkel, in dieser Reihenfolge:

```
--reihe-1: #3b6fd1;  --reihe-2: #d9740f;  --reihe-3: #2f9e6b;  --reihe-4: #b84fa8;
--reihe-5: #c9a800;  --reihe-6: #17a2b8;  --reihe-7: #a0522d;  --reihe-8: #6b6b6b;
--reihe-9: #7e57c2;  --reihe-10: #e0568c;
dunkel: --reihe-1: #7ea1ea; --reihe-2: #f0a054; --reihe-3: #5ec99a; --reihe-4: #d98acb;
        --reihe-5: #e5c94a; --reihe-6: #5ccbe0; --reihe-7: #c98a6b; --reihe-8: #a6a6a6;
        --reihe-9: #a98be0; --reihe-10: #f08ab1;
```

Die Zuordnung Sorte → Farbe ist **alphabetisch stabil** über die Sitzung
(Tiana bleibt Tiana, egal welche Sorten eingeblendet sind); mehr als zehn
Reihen wiederholen die Palette mit gestrichelter Linie. Im Filter „Sorte"
sind die Reihen Chargen: `--reihe-n` nach Chargennummer aufsteigend.

## 2. Lagermanagement — Aufbau und Verhalten

**Reiterkopf:** Titel „Lagermanagement". Zweck: „Was liegt, wovon, in welchem
Kaliber — heute und in ein paar Wochen." Pfad `/dashboard`.

```
[Filterleiste]
┌ Kennzahl-Reihe (4 Kacheln) ────────────────────────────────────────────────┐
│ EINGANG        │ AUSGANG         │ IM LAGER  ▌      │ DAVON VERKAUFSFÄHIG ▌ │
│ 412.6 t gemessen│ 218.1 t gemessen│ 188.9 t gerechnet│ 150.8 t · 80 % gerechnet│
│ 1 233 Paletten ·│ 610 Lieferungen ·│ Eingangsware, die│ von dem, was im Lager  │
│ 42 Chargen      │ + 7.3 t anderer  │ nicht ausgeliefert│ liegt · Mini-Balken    │
│                 │ Kanal            │ ist · 36 Chargen │ [██████░░]             │
└────────────────────────────────────────────────────────────────────────────┘
┌ Karte: Die Saison im Verlauf ─────────────────────── [Als Tabelle] ────────┐
│ (Linien: Eingang kum. · Ausgang kum. · im Lager · verkaufsfähig; heute |)   │
│ Legende (Knöpfe) · Fuss: „ab heute gestrichelt: so ginge es weiter"        │
└────────────────────────────────────────────────────────────────────────────┘
┌ Karte: Was ist noch im Haus? ────────────────── in [ 4 ] Wochen · 12. Okt ─┐
│ ┌ rollbar ─────────────────────────────────────────────────────────────┐   │
│ │ Sorte       im Lager │ verkaufsfähig heute            │ in 4 Wochen   │   │
│ │                      │ K1  K2  K3  K4  unter  gesamt  │ K1 K2 K3 K4 … │   │
│ │ Butterkin    58.1 t  │ 0.3 11.3 11.5 0.3   –   23.4 t │ …             │   │
│ │  (600–1200 g …)      │                       (40 %)   │               │   │
│ └──────────────────────────────────────────────────────────────────────┘   │
│ Fussnote (ein Satz) · ▸ Wie diese Zahlen entstehen                          │
└────────────────────────────────────────────────────────────────────────────┘
┌ Karte: Wie schwer sind die Kürbisse? ─────── [ heute | in 4 Wochen ] ──────┐
│ (Glocke, Bänder als Zonen, Schwerpunkt-Marke)                               │
│ 4 238 gewogen · eigene Messung · Schwerpunkt 1 180 g · K1 33 % · K2 58 % …  │
└────────────────────────────────────────────────────────────────────────────┘
```

### L1 — Vier Kennzahlen (`.kennzahl-reihe`, Ids `#kz-eingang`, `#kz-ausgang`, `#kz-lager`, `#kz-verkaufsfaehig`)

Baustein `Kennzahl`. Titel in Versalien (macht der Baustein), die Zahl in
`--s-6`, die Herkunftsmarke direkt an der Zahl, der Untertitel eine Zeile,
höchstens zwei.

| Kachel | Zahl | Herkunft | Untertitel | Kante |
|---|---|---|---|---|
| Eingang | `erg_wohin.eingang_kg` | gemessen (gerechnet, wenn Paletten ohne Netto — Text wie heute) | „n Paletten · m Chargen" | keine |
| Ausgang | `erg_wohin.geliefert_kg` | gemessen | „n Lieferungen · + x t anderer Kanal (zu klein / zu gross)" | keine |
| Im Lager | `erg_prognose.lager_kg` (h 0) | gerechnet | „Eingangsware, die nicht ausgeliefert ist · m Chargen" | `ton-kuerbis` |
| Davon verkaufsfähig | `erg_prognose.verkaufsfaehig_kg` (h 0) + „· 80 %" in `.55em` | gerechnet | „von dem, was im Lager liegt" + Mini-Anteilsbalken (verkaufsfähig / verdunstet / faul / zu klein+gross am Lager, `.mini-anteile`) | `ton-gruen` |

Ist `verkaufsfaehig_anteil` null: die Prozentzahl fehlt, davor steht klein
„höchstens", der Untertitel sagt „der Anteil ist unbekannt, solange eine
Rate nicht gemessen ist". Kein Link, kein Knopf in den Kacheln. Handy: zwei
Kacheln je Zeile, Zahl `1.9rem` (macht das CSS).

### L2 — „Die Saison im Verlauf" (`#lager-verlauf`)

`Karte titel="Die Saison im Verlauf" unter="Je Woche für {Auswahl}: was hereinkam, was hinausging, was liegt — und wie viel davon verkaufsfähig ist."`
Baustein `Linien`, Höhe 300 (Handy 240), `xEinheit 'datum'`, `yEinheit 'kg'`,
`yFormat = tonnen`, Heute-Marke (`heute={{ x: heuteTag, text: 'heute', rechts: 'so ginge es weiter' }}`).

| Reihe | Farbe | Stil | Quelle (`erg_verlauf`, Gruppe der Auswahl) |
|---|---|---|---|
| Eingang kumuliert | `--text-leise` | Fläche 8 %, dünn | `eingang_kum_kg` |
| Ausgang kumuliert | `--strom-rest` | Linie | `ausgang_kum_kg` |
| im Lager | `--kuerbis` | dick | `lager_kg` |
| verkaufsfähig | `hell(--strom-rest)` → auf dem Diagramm `--strom-rest` mit 60 % Deckung | Linie, `prognoseAb = heute` | `verkaufsfaehig_kg` |

Wochen mit `prognose = true` laufen gestrichelt (`prognoseAb`). Tooltip:
Woche („KW 41 · 5.–11. Okt"), dann vier Zeilen mit Chip, Name, Wert in t.
Legende als Knöpfe (blendet aus), „Als Tabelle" rechts im Fuss, Zoom nur
Maus. Fuss links: „ab heute gestrichelt: wenn die liegende Ware liegen
bleibt". Keine Fax-Reihe, keine Verlust-Reihe.

### L3 — „Was ist noch im Haus?" (`#lager-tabelle`) — das Herz

`Karte titel="Was ist noch im Haus?" unter="Je {Sorte | Charge}: was liegt, und wie viel davon in welchem Kaliber verkaufsfähig ist — heute und in X Wochen."`
Aktion rechts oben: `in [ 4 ] Wochen · 12. Okt` — das Feld `#lager-wochen`
(`input type=number`, min 1, max 28, step 1, Breite 4 Zeichen, `inputmode
numeric`), links davon das Wort „in", rechts „Wochen" und das Datum des
Horizonts in `.leise`. Pfeiltasten ändern X; Eingabe wird nach 300 ms
übernommen (Debounce); leer oder ausserhalb 1…28 → letzter gültiger Wert
bleibt, Feld bekommt `aria-invalid`.

**Die Tabelle** (`table.dicht` in `.rollbar`, erste Spalte `position: sticky;
left: 0; background: var(--flaeche)`):

```
thead, Zeile 1:  [Sorte|Charge] [im Lager] [verkaufsfähig heute  colspan=n+2] [in 4 Wochen · 12. Okt  colspan=n+2]
thead, Zeile 2:  [ ]            [ ]        [K1] [K2] [K3] [K4] [unter Kaliber] [gesamt]   [K1] … [gesamt]
```

- Kopfzeile 1 trägt die Gruppen, Kopfzeile 2 die Bänder. Im Filter „Alle"
  heissen sie „Kaliber 1 … Kaliber 4" (n = grösste Bandzahl aller Sorten); im
  Filter „Sorte"/„Charge" stehen die Gramm der Sorte („600–1100 g").
- Zellen: `td.zahl`, Wert in `tonnen()`/`kg()`; im Filter „Alle" darunter das
  Band der Sorte in `.leise`, `--s-0` („600–1100 g"). Leere Bänder einer Sorte
  mit weniger Bändern: leer (kein Strich, keine Null).
- „unter Kaliber": nur, wenn irgendeine Zeile > 0.5 kg hat; Zellenfarbe
  `--gelb`, `title` „liegt laut Rechnung noch als verkaufsfähig, ist aber
  unter das kleinste Band geschrumpft".
- „gesamt": fett, darunter in `.leise` der Anteil am Lager („40 %").
- **Basis:** `basis = 'sorte'` → hinter dem Zeilennamen ein Chip `.marke`
  „aus der Sorte" mit `title` („diese Charge hat keine Sortier-CSV — die
  Verteilung ist die der Sorte, n Kürbisse"); `basis = 'keine'` → die
  Bandzellen zeigen „—" mit `title` „keine Sortier-CSV für diese Sorte", die
  Gesamtspalte zeigt die Masse.
- Zeilen: Filter „Alle" → je Sorte, sortiert nach `lager_kg` absteigend; Filter
  „Sorte" → je Charge dieser Sorte (Name „Charge 1612", darunter Schlag in
  `.leise`); Filter „Charge" → eine Zeile. Nur `lager_kg > 0`. Eine Fusszeile
  „Summe" (`tfoot`, fett) im Filter „Alle" und „Sorte".
- Klick auf eine Zeile (`tr.klickbar`) setzt den Filter (Sorte → Charge). Die
  ganze Zeile ist Ziel, Fokus per Tastatur (`tabIndex=0`, Enter).
- Laden: bis die Spalten „in X Wochen" da sind, stehen die alten Zahlen mit
  `opacity: .45` (Klasse `.laedt` an den Zellen), kein Spinner, kein Springen
  der Spaltenbreiten (`min-width` je Zahlenspalte 5.5rem).
- Fehler beim Aufruf: eine Zeile `Hinweis art="warnung"` unter der Tabelle
  („Die Spalten ‚in X Wochen' konnten nicht geladen werden: …"), die Spalten
  bleiben leer mit „—".
- Fussnote (`.hilfe`, ein Satz): „Die Summe der Bänder ist die verkaufsfähige
  Masse der Rechnung; die Bänder kommen aus der Sortier-CSV, jeder Kürbis um
  die gemessene Verdunstung geschrumpft — fällt einer unter das kleinste Band,
  steht er in ‚unter Kaliber'."
- `Erklaerung` (zu): drei Sätze zu Kaskade, CSV, Basis — Text in
  `pruefstand/begriffe.json` anmelden.
- Leer (keine Ware): `Leer titel="Nichts im Lager"` mit einem Satz.

### L4 — „Wie schwer sind die Kürbisse?" (`#lager-glocke`)

`Karte titel="Wie schwer sind die Kürbisse?" unter="Die Gewichte der sortierten Kürbisse {der Sorte | der Charge | aller Sorten}, mit den Kalibergrenzen."`
Aktion rechts oben: `Segmente` (`#glocke-umschalter`) mit `[ heute | in X
Wochen ]` — der zweite Knopf trägt das X der Tabelle („in 4 Wochen"); dazu
das Feld `#glocke-wochen`, das **dasselbe** X ist wie `#lager-wochen` (ein
Zustand, zwei Felder). Knopf-Ids: `#glocke-heute` (der Segmente-Knopf
„heute"), `#glocke-wochen` (das Feld).

- Baustein `Glocke`, `breite = 50`, `hoehe = 200`, Bänder als `grenzen`
  (Beschriftung „600", „1100", …), `klassenfarbe`: unter dem kleinsten Band
  `--gelb`, im Band `--kuerbis`, über dem grössten `--strom-nebenkanal`;
  `mittel` = Schwerpunkt.
- Im Filter „Alle" wird **eine** Sorte gezeigt — die grösste nach `lager_kg`,
  mit einem kleinen `select` „Sorte: [Butterkin ▾]" links unter dem Titel
  (Id `#glocke-sorte`); Bänder sind je Sorte, eine Glocke über alle Sorten
  wäre eine Lüge.
- Darunter eine Zeile `.leise`: „4 238 gewogen · eigene Messung | aus der
  Sorte · Schwerpunkt 1 180 g · K1 33 % · K2 58 % · K3 9 % · unter 0.5 %" —
  die Prozente sind die Massenanteile derselben Rechnung wie in L3 (Prüfblock
  0079 (c) beweist die Gleichheit).
- Tooltip je Balken: „1 150–1 200 g · 312 Kürbisse · 7.4 %".
- Leer: `Leer titel="Keine Sortier-CSV"` „Sobald ein Sortierlauf eingelesen
  ist, steht hier die Glocke."

## 3. Ursachen — Aufbau und Verhalten

**Reiterkopf:** Titel „Ursachen". Zweck: „Wohin der Kürbis bis heute ging, wo
und wann das Faule und die Verdunstung entstanden — und was die Waage
verschenkt." Pfad `/ursachen`. **Kein Wort Prognose auf diesem Reiter.**

```
[Filterleiste]
┌ Karte: Wohin ging der Kürbis? ──────────────────────────────────────────────┐
│ Alle Chargen   [████ verkaufsfähig ██ verkauft ██ verdunstet █ Faules ▏▏]  100 %│
│ ── je Sorte ──                                                               │
│ Butterkin  [██████████████████░░]  Tiana  [██████░░░░░░]  … (klickbar)       │
│ Legende (6 Chips) · Fuss: „x kg mehr geliefert als eingelagert — Zählfehler" │
└──────────────────────────────────────────────────────────────────────────────┘
┌ Karte: Faules im Lager ───────────────────── [ Kalender | liegt seit ] ─────┐
│ (Punkte je Sorte/Charge; Kalender: bis heute | liegt seit: + Modellkurve)    │
│ Legende (Reihen) · Fuss: „Rechnung heute: 210 kg Faules je Tag an der Ware" │
└──────────────────────────────────────────────────────────────────────────────┘
┌ Karte: Verdunstung ───────────────────────── [ Kalender | liegt seit ] ─────┐
│ (Punkte je Sorte/Charge; liegt seit: + Erwartung je Sorte als Linie)         │
│ ▸ Je Sorte: die Rate (Tabelle)                                               │
└──────────────────────────────────────────────────────────────────────────────┘
┌ Karte: Kiste ab x kg ──────────────┐ ┌ Karte: x Kürbisse je Kiste ──────────┐
│ Tabelle je Sorte · Balken Ist/Soll │ │ Tabelle je Sorte/Kaliber · Lage im Band│
└────────────────────────────────────┘ └────────────────────────────────────────┘
```

### U1 — „Wohin ging der Kürbis?" (`#urs-wohin`)

`Karte titel="Wohin ging der Kürbis?" unter="Der ganze Eingang {der Auswahl}, aufgeteilt: was noch gut liegt, was verkauft ist, was verloren ging — bis heute."`
Baustein `Anteilsbalken`, `bezugName = 'am Eingang'`, Legende an. Sechs Teile
in dieser Reihenfolge und Farbe (§ 1.2): noch im Lager und verkaufsfähig ·
verkauft · verdunstet bis heute · Faules bis heute · zu klein · zu gross.
Ein siebter Teil „Rest der Zählung" (`--text-ganz-leise`) nur, wenn
`|rest| > 0.5 kg`.

- Oberste Zeile: die Auswahl selbst („Alle Chargen · 42 Chargen · 412.6 t
  Eingang"), rechts der **Verlustanteil** („12 % verloren") — Verlust =
  verdunstet + Faules, nicht zu klein/gross (das ist Kanal, kein Verlust —
  steht so im Tooltip der zwei grauen Teile).
- Darunter ein Trenner `.tag-trenner` „je Sorte" (Filter Alle) bzw. „je
  Charge" (Filter Sorte), dann die Zeilen, sortiert nach Verlustanteil
  absteigend, jede klickbar (setzt den Filter). Filter „Charge": nur die eine
  Zeile, kein Trenner.
- Tooltip je Segment: Name, Tonnen, „x % am Eingang"; beim Teil „Faules bis
  heute" zusätzlich: „davon x kg vom Feld (nicht lagerbedingt), y kg beim
  Abpacken gemessen" — nur die Teile > 0.
- Fussnoten: `ueberzaehlung_kg > 0` → „x kg mehr geliefert als eingelagert —
  ein Zählfehler beim Eingang, nicht Ware". Sonst nichts.
- `Erklaerung`: die zwei Identitäten in zwei Sätzen.

### U2 — „Faules im Lager" (`#urs-palox`)

`Karte titel="Faules im Lager" unter="Jede Messung am Palox: wie viel Faules die Ware hatte, als sie an die Maschine kam — nach Datum oder nach Lagerdauer."`
Aktion: `Segmente` `[ Kalender | liegt seit ]` — Knöpfe mit Ids
`#palox-achse-kalender`, `#palox-achse-liegt`; Vorgabe **Kalender**
(die neue Frage des Betriebs), gemerkt in `localStorage` (`urs.palox.achse`).
`Segmente` kennt heute nur eine Id am Rahmen: Der Baustein bekommt eine Id
je Knopf (drittes Element im Tupel `teile`, optional) — eine Erweiterung,
kein zweiter Umschalter. Dasselbe für L4 (`#glocke-heute`) und U3.

Baustein `Linien`, Höhe 300 (Handy 240), `yTitel "Faules je 100 kg Ware"`,
`yFormat = v => prozent(v, 0)`, `yEinheit 'prozent'`:

| Achse | x | Reihen | Zusätze |
|---|---|---|---|
| Kalender | `messtag` (`xEinheit 'datum'`, `xBis = heute`, Heute-Marke „heute") | eine Reihe je Sorte (Filter Alle) / je Charge (Filter Sorte) / eine (Charge): `marker`, keine Linie, `form 'kreis'`, Farbe `--reihe-n` | keine Modellkurve (die hat kein Datum) |
| liegt seit | `lagertage` (`xEinheit 'tage'`, `xVon 0`) | dieselben Reihen | Modellkurve `erg_kurve` gestrichelt `--text-leise` mit Band; je Charge mit Ware eine Raute „heute" auf der Kurve (`form 'raute'`, `groesse` nach Masse, Name „Charge 1612 · heute"); Zone „hier liegt die Ware heute" im Filter Alle |

- Tooltip je Punkt: Kopf „Charge 1612 · Tiana", Zeilen: „12. Okt 2026",
  „liegt seit 41 Tagen", „Faules 120 kg von 1 480 kg", „Quelle: Waschen +
  Sortieren" (`quelle`). Auf der Kalenderachse steht die Lagerdauer, auf der
  Lagerdauerachse das Datum — der Betrieb soll beides immer sehen.
- Markierung: Reihen aus Chargen mit eigenen Punkten heissen in der Legende
  „Tiana · eigene Messung"; die Modellkurve „Modell (alle Sorten)"; eine
  Raute ohne eigene Punkte trägt im Tooltip „wie Mittelmass — keine eigene
  Messung".
- Legende: Knöpfe, ausblendbar; bei mehr als zehn Reihen sind die kleinsten
  (nach Masse) vorab ausgeblendet (`ausgeblendet`), der Fuss sagt „n weitere
  Sorten ausgeblendet — in der Legende einblenden".
- Fuss links: „Rechnung heute: `faul_je_tag_kg` kg Faules je Tag an der
  liegenden Ware (aus dem Modell)". Kein Wort Prognose.
- Punkte mit `plausibel = false` (Ausreisser, 0069): hohl, grau, im Tooltip
  „nicht in der Rechnung: …". Nie weggelassen.
- Leer: `Leer titel="Noch keine Messung am Palox"` „Sobald eine Arbeit den
  Palox zweimal abgelesen hat, steht hier ihr Punkt."

### U3 — „Verdunstung" (`#urs-verdunstung`)

`Karte titel="Verdunstung" unter="Jede gewogene Palette: wie viel Wasser die Ware je Tag verlor — nach Datum oder nach Lagerdauer."`
Aktion `[ Kalender | liegt seit ]` (`#verd-achse-kalender`, `#verd-achse-liegt`),
Vorgabe Kalender, gemerkt (`urs.verd.achse`). `yTitel "Verdunstung je Tag"`,
`yFormat = v => prozent(v, 2)`.

| Achse | x | Reihen | Zusätze |
|---|---|---|---|
| Kalender | `wiege_ts` (Tag), `xBis = heute`, Heute-Marke | je Sorte / je Charge, Marker `kreis`, Farbe `--reihe-n` | — |
| liegt seit | `lagertage` | dieselben | je eingeblendeter Sorte ihre Erwartung als `waagrechte` (Rate aus `erg_koeff_verdunstung`, Text „Tiana: 0.052 % je Tag") mit Band als Zone |

- Nicht verwendbare Wägungen (`verwendbar = false`): hohle graue Punkte,
  Tooltip mit Grund („Palette wurde schwerer — Wägung verworfen"). Nie
  weggelassen.
- Tooltip: „Charge 1612 · Tiana", „12. Okt 2026 · liegt seit 41 Tagen",
  „950 kg → 905 kg", „0.11 % je Tag".
- Unter dem Diagramm der Aufklapper „Je Sorte: die Rate" (gibt es): n
  Wägungen, Rate, Band, Basis („eigene Wägungen" / „alle Sorten").
- Fuss: „Die Rechnung nimmt je Sorte eine Rate. Fallen die Punkte im Winter
  sichtbar ab, ist das ein Befund — kein zweites Modell."

### U4 — „Verschenkte Marge" (zwei Karten in `.zwei-spalten`)

**Links `#urs-marge-kiste`:** `Karte titel="Kiste ab x kg" unter="Was die Kiste über dem Soll hat, ist geschenkt — gemessen an den gewogenen vollen Paletten."`
- Tabelle (`table.dicht`): Sorte · Soll · Ist je Kiste ± sd · zu viel (kg und
  %) · Wägungen · Kisten · von–bis. Sortiert nach „zu viel %" absteigend. Zu
  viel > 5 % in `--strom-schimmel`-Text, < 0 in `--strom-rest`.
- Darunter ein Balkendiagramm (SVG, gleicher Rahmen wie `Linien`, keine neue
  Bibliothek): je Sorte ein waagrechter Balken „zu viel je Kiste" in kg ab
  der Nulllinie, Farbe `--kuerbis`, negativ `--strom-rest`; Beschriftung am
  Balkenende („+0.47 kg · 6 %"); Tooltip wie die Tabellenzeile. Höhe 32 px je
  Sorte.
- Fuss: „Mittel aus n gewogenen vollen Paletten seit dd. Mon — nicht auf
  verkaufte Kisten hochgerechnet."
- Leer: `Leer titel="Noch keine Kiste-ab-Palette gewogen"`.

**Rechts `#urs-marge-stueck`:** `Karte titel="x Kürbisse je Kiste" unter="Wie schwer der einzelne Kürbis wirklich ist, gegen die Mitte seines Kalibers."`
- Je Zeile (Sorte · Kaliber): links „Tiana · K2 · 9 je Kiste", rechts ein
  Band-Balken: das Band (`band_von`–`band_bis`) als Spur `--flaeche-2`, die
  Bandmitte als senkrechter Strich `--rand`, der gemessene Wert als Punkt
  (`--kuerbis`, 10 px) mit Beschriftung „1 260 g · −497 g"; liegt der Punkt
  ausserhalb des Bands, steht er am Rand mit Pfeil und die Zahl in
  `--strom-schimmel`.
- Tooltip: Band, Mitte, Gramm je Kürbis, Wägungen, Kisten.
- Fuss: „Mittel aus n Wägungen; die Bandmitte ist, was der Kunde bezahlt."
- Leer: `Leer titel="Noch keine Stück-Palette gewogen"`.

Auf 390 px stehen die zwei Karten untereinander (macht `.zwei-spalten`).

## 4. Interaktion — was sich wie verhält

| Element | Verhalten |
|---|---|
| Filter | Wechsel setzt URL-Parameter (`replace`), alle Blöcke rechnen sofort aus dem Datenstand; die zwei `rpc`-Aufrufe (0, 7·X) laufen neu; während des Ladens `.laedt` auf den betroffenen Zellen. |
| Feld X | Ein Zustand (`wochen`), zwei Felder (Tabelle, Glocke), URL-Parameter `?wochen=4` (damit ein Link „in 8 Wochen" zeigt). Debounce 300 ms, Pfeiltasten, Bereich 1…28, ungültig → `aria-invalid`, letzter Wert bleibt. |
| Umschalter Achse | Sofort, ohne Neuladen; gemerkt in `localStorage`; `Segmente` mit `role=tablist`/`tab`, Pfeiltasten wechseln. |
| Diagramme | Zeiger-Tooltip über alle Reihen (Maus und Touch: Tippen setzt den Zeiger), Legendenknöpfe, „Als Tabelle", Zoom mit Maus (Ziehen, Rad, Doppelklick zurück), auf Touch nur Scrollen. Bereits gebaut — nutzen, nicht neu bauen. |
| Balken (U1) | Segment-Tooltip; Zeile klickbar → Filter; Tastatur: Zeile `tabIndex=0`, Enter. |
| Tabelle (L3) | Zeile klickbar → Filter; `.rollbar` waagrecht auf schmalen Bildschirmen, erste Spalte haftet; Kopfzeilen haften nicht (zu viel Höhe auf dem Handy). |
| Laden der Seite | Wie heute: Skelett (`Lade`) beim ersten Laden, dann Zähler laufen. Ein `rpc`-Fehler blockiert nie die Seite — nur die betroffenen Spalten/Karte zeigen den Hinweis. |
| Fehler | Immer sichtbar (`Hinweis art="warnung"`) mit `fehlerText`, nie nur in der Konsole. |
| Tastatur | Jedes Bedienelement erreichbar (Tab), sichtbarer Fokusring (`--kuerbis-ring`, gibt es), keine Tastaturfallen. |
| Bewegung | Zähler und Linien wie in `DESIGN_RUNDE_O`; sonst keine Animation; `prefers-reduced-motion` respektiert. |

## 5. Verbote (damit es nicht zu viel wird)

- Keine neue Abhängigkeit, keine Diagrammbibliothek, kein CSS-Framework.
- Keine Torten, keine Tachos, keine 3-D-Effekte, keine zwei y-Achsen, keine
  Flächendiagramme mit mehr als einer Fläche, keine Farbverläufe als
  Bedeutung.
- Nicht mehr als **zehn** Reihen sichtbar zugleich; nicht mehr als **sieben**
  Teile in einem Anteilsbalken.
- Keine Hex-Farbe im TSX; keine Inline-Stile für Farbe oder Schrift (Helfer-
  klassen); keine Emojis in Karten; keine Icons ausser aus `Zeichen.tsx`.
- Kein Text unter einem Titel länger als zwei Zeilen; keine Erklärung
  ausserhalb `Erklaerung`.
- Keine Karte ohne Herkunftsmarke an der Hauptzahl; keine Prozentzahl ohne
  Nenner; keine Null für Unbekanntes.
- Keine Prognose auf Ursachen; keine „liegt seit"-Spalte auf Lagermanagement;
  kein Fax irgendwo im Dashboard.
- Keine neuen Reiter, keine Dialoge, keine Modals, keine Toasts.

## 6. Was die Abnahme davon prüft (Ergänzung zu § 8 des Auftrags)

`pruefstand/abnahme_r.mjs` prüft neben dem Inhalt diese Designpunkte:

| Punkt | Prüfung |
|---|---|
| D-01 | Jede Karte auf beiden Reitern (ausser Filterleiste) trägt mindestens eine `.herkunft`-Marke oder ist eine `Leer`-Karte |
| D-02 | Die vier Kennzahlen sind `.kennzahl` mit `.gross-zahl` und `.unter` |
| D-03 | Die Achsen-Umschalter sind `Segmente` (`.umschalter[role=tablist]` mit `button[role=tab]`) |
| D-04 | `#lager-tabelle` hat zwei Kopfzeilen, `th[colspan]` in der ersten, und die erste Spalte ist haftend (`position: sticky`) |
| D-05 | Jedes Liniendiagramm trägt `data-x-einheit` am SVG und eine `.legende` |
| D-06 | Kein `style="…color…"` und kein `style="…font-size…"` in den Karten der zwei Reiter |
| D-07 | Bei 390 px Breite scrollt die Seite nicht waagrecht (`scrollWidth ≤ 390`), auf beiden Reitern |
| D-08 | Beide Reiter rendern im dunklen Thema ohne Konsolenfehler |

Bilder: `bildschirme.mjs` nimmt `lager`, `lager-sorte`, `lager-charge`,
`lager-wochen`, `lager-glocke-wochen`, `ursachen`, `ursachen-sorte`,
`ursachen-charge`, `ursachen-kalender` auf — Handy und Desktop, hell und
dunkel. Der Bericht zeigt je Block das Desktop-Bild hell und das Handy-Bild
dunkel.
