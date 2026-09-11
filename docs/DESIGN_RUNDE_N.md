# Runde N — das Erscheinungsbild: gleiche Struktur, neue Klasse

Der Auftrag des Betriebs, wörtlich: *„ein modernes, elegantes UI … gleiche
Struktur bitte, gleiche Reiter, gleiche Grafiken, gleiche Infos … aber ein
viel professionelleres Auftreten, moderner, schöner … edle, professionelle,
teure Software … ein bisschen Animationen, die Sachen poppen langsam auf oder
verschwinden."*

Diese Datei sagt, **was** das heisst — Zeichen für Zeichen, Bildschirm für
Bildschirm — damit die ausführende Runde baut und nicht rät. Die Zeichen
liegen schon in `src/design/tokens.css` und `src/design/bewegung.css`
(noch nicht eingebunden).

## 1. Was bleibt, was geht

| Bleibt | Geht |
|---|---|
| Alle Reiter, Routen, Karten, Diagramme, Tabellen, Zahlen und Sätze | Emoji als Zeichen (🎃 im Kopf, 📦 auf den Tätigkeitskarten, ⚠︎ in Hinweisen) |
| Die sieben Strom-Farben (Bedeutung, geprüft) | Das kühle Grau (#f4f5f7) — es wirkt wie ein Verwaltungsformular |
| Inter Variable | 170 inline `style={{…}}` in den Seiten — jede davon ist ein Stil ohne Namen |
| Das Zwei-Apps-Prinzip (Halle / Büro), 44-px-Ziele, Dunkelmodus | Der Spinner als einzige Ladeanzeige |
| `Karte`, `Kennzahl`, `Zahlen`, `Marke`, `Herkunft`, `Aufklapp`, `Rechenweg` als Bausteine | Die riesige ungebrochene Tabelle unter Betrieb → Arbeiten |
| Die Diagramm-Bibliothek von Hand (kein Chart-Paket) | Die Legendenknöpfe als graue Rechtecke; Tooltips ohne Kante |

Die Regel für alles Weitere: **Ein Bildschirm nach der Runde zeigt dieselben
Wörter und Zahlen an derselben Stelle wie vorher.** Der Bildschirm-Prüfstand
(`pruefstand/bildschirme.mjs`) macht davor und danach ein Bild; die
Begriffs-Prüfung (`pruefstand/beschriftung.mjs`) muss danach dieselben
Begriffe finden. Was sich ändert, ist Fläche, Schrift, Abstand, Tiefe,
Zeichen und Bewegung.

## 2. Die Zeichen (tokens.css)

**Flächen.** Ein warmes, sehr helles Neutral (`--grund #f7f6f3`) statt kühlem
Grau, Karten weiss, drei Flächenstufen für Kopf, Feld und Druck. Tiefe kommt
aus einer 1-px-Kontur (`--kontur`, als box-shadow, damit nichts springt) und
einem sehr flachen Schatten — nicht aus Rahmen. Hover hebt eine Karte eine
Stufe (`--tiefe-2`), nur wo sie klickbar ist.

**Schrift.** Eine Familie, sieben Grössen in 1.2-Schritten (`--s-0` … `--s-7`),
drei Gewichte (440 / 540 / 640). Titel und grosse Zahlen leicht enger
gesetzt (−.012 em). Zahlen überall in Tabellenziffern; Kennzahlen mit
`tnum` **und** `cv05`. Basis 16 px statt 15.5 — auf dem Handy in der Halle
zählt jedes halbe Pixel.

**Akzent.** Kürbis eine Spur satter (`#c8500a`), ein Fokusring in derselben
Farbe mit 28 % Deckung — sichtbar, nicht laut. Die Zustandsfarben etwas
tiefer, ihre Flächen etwas wärmer.

**Abstand.** 4er-Raster, `--a-1` (4 px) bis `--a-12` (48 px). Innenabstand
einer Karte `--a-5`/`--a-6`, Abstand zwischen Karten `--a-4`, zwischen
Abschnitten `--a-8`.

**Rundung.** 6 / 12 / 18 px — Chip, Karte, Dialog. Knöpfe wie Karten (12 px),
in der Halle die Hauptknöpfe 14 px.

**Dunkelmodus.** Vollständig, gleichwertig, mit einem korrigierten Grün für
„verkaufsfähig" (`#2e9e3a` statt `#008300`, das auf dunklem Grund 2.9:1 hat).

## 3. Die Bewegung (bewegung.css)

Fünf Bewegungen, jede mit einem Sinn; vier Dauern (120 / 200 / 320 / 480 ms),
eine Kurvenfamilie; alles aus bei `prefers-reduced-motion`. Details in der
Datei. Das Mass: **Man merkt, dass sich etwas bewegt hat, nicht, dass es sich
bewegt.** Nichts hüpft, nichts dreht sich, nichts wartet auf eine Animation,
bevor es bedienbar ist.

Was in React dazu gebaut wird (Phase 5, klein):

- `useZaehler(wert, dauer)` — eine Zahl läuft von 0 (oder vom alten Wert)
  zum neuen; nur beim ersten Erscheinen und nach „Neu rechnen"; `aria-live`
  bekommt den Endwert sofort.
- `useEintritt()` — gibt einer Liste von Karten `--i` für die Staffelung
  (`style={{ '--i': i }}`), höchstens 12 Stufen, danach 0.
- Im `Linien`-Diagramm: `pathLength="1"` an jeder Linie und die Klassen
  `linie`, `marker`, `balken`, `band`; sonst nichts. Die Animation ist CSS.
- Ein `Skelett`-Baustein, der die Form der kommenden Karte zeigt (drei
  Zeilen, eine Zahl), statt des Spinners — der Spinner bleibt für „Neu rechnen".

## 4. Die Zeichen statt Emoji (Zeichen.tsx)

`src/components/Zeichen.tsx` hat fünf SVG-Linienzeichen (Liste, Balken, Uhr,
Regler, Lupe). Runde N ergänzt, alle 24 × 24, 1.75 px Strich, rund gekappt,
`currentColor`:

| Zeichen | Wo |
|---|---|
| `ZKuerbis` (Kürbis, drei Bögen und Stiel) | Kopf (statt 🎃), Favicon (`index.html`, als data-URI) |
| `ZPalette`, `ZKiste`, `ZWaage`, `ZWasser`, `ZSieb` | Tätigkeitskarten im Assistenten (statt 📦 🧺 ⚖️ 💧) |
| `ZHaken`, `ZKreuz`, `ZWarnung`, `ZInfo` | Marken, Hinweise, Checkliste (statt ✓ ✗ ⚠︎ ℹ︎) |
| `ZPfeilRechts`, `ZZurueck`, `ZPlus`, `ZMinus`, `ZRueckgaengig` | Assistent, Zähler |
| `ZKalender`, `ZLupe` (da), `ZFilter` | Filterleiste in Ursachen und Chargen |
| `ZLinie`, `ZGlocke`, `ZBalken` (da) | Diagramm-Werkzeuge (Tabelle zeigen, Zoom zurück) |

Regel: Kein Zeichen ohne Text daneben — ausser in einer Leiste, wo der Text
als `aria-label` steht.

## 5. Bildschirm für Bildschirm

### Rahmen (App.tsx, Karten.tsx `Reiterkopf`)
- Kopf 56 px, weiss, Kontur unten; Marke: `ZKuerbis` in einem 30-px-Quadrat mit Kürbisfläche, daneben „Kürbis-Verlust" in 540.
- Reiter: dieselben fünf, Schrift `--s-1` 540, aktiver Reiter mit 2-px-Linie in Kürbis, die beim Wechsel **gleitet** (eine absolut positionierte Linie, `transition: transform var(--d-mittel)`), statt zu springen.
- `Reiterkopf`: Titel `--s-4`, darunter Zweck in `--text-leise`; rechts der Stand („gerechnet vor 12 min") als Chip und der Knopf „Neu rechnen" als sekundärer Knopf. Beim Rechnen: der Fortschritt (`Rechnet`) als schmale Leiste unter dem Kopf, kein Dialog.

### Überblick (Ueberblick.tsx)
- Die vier Kennzahlen oben als eine Reihe gleich hoher Karten (Grid `repeat(auto-fit, minmax(220px, 1fr))`), Zahl `--s-6`, Titel darüber in `--s-1` leise, darunter die Herkunfts-Marke. Zahlen zählen beim Erscheinen.
- Der Verlauf (drei Linien, Prognose) bleibt; Linien zeichnen sich, das Band blendet danach ein. Die heute-Marke als gestrichelte Linie mit Beschriftung oben statt unten.
- „Verlust nach Ursache" (100-%-Balken): Teile wachsen von links, Beschriftung erscheint nach dem Wachsen. Die Legende als Reihe von Chips mit Farbpunkt.
- Die Kaliber-Glocke: die Fläche unter der Kurve blendet ein, die Kalibergrenzen als leise senkrechte Linien mit Beschriftung oben.
- Bestand ausklappbar: `Aufklapp` bekommt ein drehendes Chevron (`ZPfeilRechts`, 90°) und der Inhalt gleitet auf (Höhe über `grid-template-rows: 0fr → 1fr`).

### Ursachen (Ursachen.tsx)
- Die Filterleiste (Gruppe, Sorte, Charge, Zeitraum) wird **sticky** unter den Reitern, weiss, Kontur unten, Felder als Chips mit `ZFilter`.
- Jede Ursache ist eine Karte mit Titelzeile, Kennzahlen als `Zahlen`-Reihe, dann Diagramm, dann Text, dann `Aufklapp` je Charge. Reihenfolge bleibt.
- **Das Palox-Diagramm nimmt `achsenBereich(lagertage, 'tage')`** und zeigt unter dem Diagramm einen Satz für jede ausgeschlossene Messung („1 Messung ausserhalb: −1051 Tage, Charge 9802 — Eingangsdatum prüfen") mit Sprung zu Messungen. Das gilt für **jedes** `Linien`-Diagramm: `xEinheit`/`yEinheit` als neue Props, Vorgabe `'frei'`.
- Die Tabellen „je Charge": Spaltenköpfe in `--s-0` Versalien mit 0.04 em Spationierung, Zeilen 40 px, Zebrastreifen weg, stattdessen `--rand-leise` als Linie; die Abweichungsspalte mit Farbpunkt (grün/rot) statt farbigem Text.

### Chargen (Chargen.tsx)
- Die gedrängten, umbrechenden Spalten: feste Mindestbreiten je Spaltenart (Zahl 96 px, Datum 104 px, Text 160 px), Tabelle in `overflow-x: auto`-Rahmen mit Schatten an den Kanten, wenn sie rollt (`mask-image`-Trick oder zwei Verläufe).
- Eine Charge-Zeile klickbar → gleitet auf (wie Aufklapp) und zeigt Eingang → Ausgang → Arbeiten als drei Spalten mit Pfeilen dazwischen (`ZPfeilRechts` leise).
- Herkunfts-Marken (`gemessen` / `gerechnet` / `prognose`) als kleine Chips mit Punkt statt Text in Klammern.

### Messungen (Messungen.tsx)
- Auffälligkeiten als Liste von Karten mit linker Farbkante (rot/gelb/blau), Titel, Satz, „Korrigieren →" als Textknopf rechts.
- Die Wägungstabelle wie Chargen; „verwendbar" als Häkchen/Kreuz-Zeichen mit Tooltip-Grund (die Gründe liefert `v_plausibilitaet`; das Orakel kennt sie als `gruende`).

### Betrieb (Betrieb.tsx, Lieferungen, Stammdaten, Zugang, Warteschlange, Arbeiten)
- Unterreiter als Segment-Steuerung (eine Zeile Chips, aktiver gefüllt).
- **Arbeiten: nach Tag gruppiert** (Datumszeile als Trenner, neueste oben), je Tag eine Tabelle, standardmässig die letzten 14 Tage, „ältere zeigen" lädt 14 weitere. Kein Bildschirm mit 300 Zeilen mehr.
- Stammdaten: Formulare in zwei Spalten ab 800 px, Feldtitel über dem Feld, Hilfetext unter dem Feld in `--s-0`.
- Warteschlange (Sortierdateien): Zustand als Chip (zugeordnet / offen / verworfen), die Zuordnung als Dialog mit `--tiefe-3`.

### Arbeiter-App (Start, NeueArbeit, Arbeit, Zähler, Abschluss, Kontrolle)
- Start: „Läuft gerade" als Karten mit grosser Tätigkeitsangabe (`--s-3`), Charge als Chip, Teilnehmer als Kreise mit Initialen; darunter die zwei Hauptknöpfe 60 px, voll breit, Kürbis und Weiss.
- Assistent: die Fortschrittszeile „Schritt 2 von 5" als fünf Striche, gefüllt bis zum aktuellen; `Wahl`-Karten mit SVG-Zeichen links (32 px), Titel `--s-3`, Satz darunter; gewählt = Kürbisfläche + Kontur in Kürbis + Häkchen rechts oben, das sich setzt (`haken`).
- Schrittwechsel: `wechsel-hin` / `wechsel-her` — das Alte geht nach oben, das Neue kommt von unten.
- Zähler: Stand `--s-7`, `zaehler-stand.neu` rückt beim Zählen; „+"-Knopf 84 px bleibt; „Rückgängig" als sekundärer Knopf mit `ZRueckgaengig`. Die Palettenliste darunter als Zeilen mit Datum-Chip, neueste oben, neue Zeile tritt ein.
- Bestätigung („gespeichert"): ein grüner Chip mit Häkchen unter dem Knopf, tritt ein, verschwindet nach 2 s — statt Toast unten.
- Abschluss: Zusammenfassung als Karte mit Zeilen „Was · Wert · Herkunft", Hauptknopf „Ja, fertig" 60 px; was fehlt, steht als roter Satz **am** Knopf (bleibt).
- Kontrolle (Palette wiegen): das Netto rechnet sich beim Tippen, die Zahl zählt; fehlt Tara/Kisten, steht der Satz aus `taraFehlt()` als gelber Hinweis. **Neu (aus Drehbuch 01, S6): die dritte Wahl „Palette ohne Zettel (nach dem Sortieren)"** — falls der Betrieb sie will (Frage 57).

### Anmelden, Sprache
- Anmeldekarte 560 px, Marke gross oben, zwei Knöpfe (Betriebsleiter / Arbeiter) als Karten; die Sprachwahl als Reihe von Chips mit Landes-Kürzel — kein Flaggen-Emoji.

## 6. Der visuelle Beweis

Kein Bildschirm gilt als fertig ohne:

1. `node pruefstand/bildschirme.mjs <name>` vorher und nachher, beide Bilder
   im Bericht (hell, dunkel, Handy, Rechner).
2. `node pruefstand/beschriftung.mjs` findet dieselben Begriffe.
3. `node gegenprobe/bildschirm/invarianten.mjs` grün auf Demo **und** böser Saison.
4. Kontrast: jede Text-/Grund-Kombination ≥ 4.5:1 (Fliesstext) bzw. ≥ 3:1
   (grosse Zahlen) — gemessen, nicht geschätzt (ein kleines Skript über die
   Zeichen in tokens.css, Teil von `invarianten.mjs` oder eigenes).
5. `npm run pruefen` grün; Bündelgrösse `auswertung` und `index` nicht mehr
   als 5 % über dem Stand davor (`vite build` schreibt sie).

## 7. Was ausdrücklich nicht passiert

- Kein Chart-, Icon-, Animations- oder CSS-Paket. Null neue Abhängigkeiten.
- Keine neue Seite, kein neuer Reiter, kein neuer Begriff.
- Keine Bewegung länger als 480 ms; keine, die die Bedienung verzögert.
- Keine Farbe, die etwas bedeutet, ohne Text daneben.
- Kein Bildschirm, der auf 390 px waagrecht rollt (I2), keine Schrift unter 12.5 px.
