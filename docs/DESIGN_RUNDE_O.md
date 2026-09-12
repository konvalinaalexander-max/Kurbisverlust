# Runde O — das Erscheinungsbild, diesmal ganz

Runde N hatte den Auftrag „modern, elegant, professionell, sanfte Animationen"
nur zur Hälfte erfüllt: Zeichen (Farben, Schrift, Abstände) und SVG-Symbole
waren da, aber die Bildschirme selbst blieben, wie sie waren — 302 inline
`style={{…}}`, kein Skelett beim Laden, keine Bewegung, die man spürt, Tooltips,
die unter der Legende verschwanden, und die Ursachen-Grafiken endeten dort, wo
die letzte Messung lag. Der Betrieb hat das gesehen und gesagt, was er will:

> *„ein modernes Design mit sanften, aber spürbaren Animationen … eine UI mit
> null Bugs … mit den visuellen Darstellungen der Daten interagieren können …
> muss nicht an die alte App erinnern, von den Funktionen ident … so, dass ich
> es meinem Chef geben kann und der direkt damit arbeiten kann … nicht zu viel
> Text … wie zeig ich ihm am effizientesten, was genau los ist."*

Diese Datei beschreibt, **was gebaut ist** — nicht, was geplant war. Die
Bilder aller Bildschirme (Handy und Rechner, hell und dunkel) entstehen mit
`node pruefstand/bildschirme.mjs` in `pruefstand/bilder/`.

## 1. Die Regel: Funktionen gleich, Bildschirme neu

Jede Maske der Halle und jede Karte des Büros zeigt dieselben Zahlen aus
denselben Sichten wie vorher; die Prüfstände beweisen es:

| Prüfung | Ergebnis nach Runde O |
|---|---|
| `pruefstand/beschriftung.mjs` (jede Zahl beschriftet, im Lexikon, mit Herkunft, Kopfzahlen gegen `erg_bilanz`) | 12 Seiten, 2 494 Zahlen, 0 Beanstandungen |
| `gegenprobe/bildschirm/invarianten.mjs` (Demo **und** böse Saison, I1–I11) | 9 Seiten × 2 Breiten, 0 Verstösse |
| `pruefstand/bildschirme.mjs` (Überlauf, Konsolenfehler, 43 Bildschirme × 2 Geräte × 2 Themen) | 172 Aufnahmen, keine Konsolenfehler, kein Überlauf |
| `npm run pruefen` (tsc, 90 Tests, Build) | grün |
| `supabase/test/run.sh` (7 Stufen, unverändertes Schema 70) | alle Prüfungen bestanden |

Neue Abhängigkeiten: keine. Die Diagramme bleiben handgeschrieben (SVG),
die Bewegung ist CSS, der einzige Hook ist `useZaehler`.

## 2. Das Büro — das Dashboard des Chefs

**Rahmen.** Eine feste Seitenleiste links (ab 1024 px): Marke, fünf Reiter
mit Strichzeichen, unten der Angemeldete mit Sprache und Abmelden. Auf dem
Handy wird daraus eine Reiterzeile unter dem Kopf, alle fünf nebeneinander,
ohne Wischen. Jede Seite beginnt mit einem `Seitenkopf`: Titel, ein Satz
Zweck, rechts der Stand-Chip („Stand vor 7 h · bis 11.09.") und „Neu rechnen".

**Überblick — vier Zahlen, dann der Rest.** Vier Kennzahl-Karten mit
Farbkante und laufender Zahl: Eingang, Ausgeliefert, Verlust bis heute (rot,
mit einem Mini-Anteilsbalken der drei Ursachen), Noch im Haus (grün). Jede
Zahl trägt ihre Herkunftsmarke (gemessen / gerechnet / Prognose) direkt bei
sich. Darunter zwei Spalten: links der Saisonverlauf (gefüllte Flächen für
Eingang und Ausgang, der Verlust dick, ab heute gestrichelt als Prognose),
rechts „Woran fehlt es" als kurze Tabelle mit Ursache, Tonnen, Anteil am
Eingang — und die eine Prognosezeile „zwei Wochen länger liegen". Dann die
100-%-Balken je Sorte/Schlag/Charge, der Bestand als Aufklapper, die
Kaliber-Glocke. Wie die Zahlen entstehen, steht in jeder Karte unter „Wie
diese Zahlen entstehen" — zu, bis man es will.

**Ursachen — die Kurve zeigt, wie es weitergeht.** Der Betrieb hatte recht:
Ein Diagramm über Lagertage, das an der letzten Messung endet, sagt nichts
über morgen, und „heute" ist auf einer Lagertage-Achse kein Punkt, weil jede
Charge an einem anderen Tag hereinkam. Deshalb:

- Die Modellkurve (Verderb F(t), Verdunstung 1−(1−r)^t) läuft mit ihrem Band
  60 Tage über die letzte Messung hinaus, ab dort gestrichelt; eine
  senkrechte Linie sagt „bis hier gemessen". Die Kurve ist dieselbe Formel
  wie in der Datenbank (`erg_kurve`), nur an mehr Stellen ausgewertet —
  keine neue Mathematik im Frontend.
- **Rauten** auf der Kurve sind die Chargen, die heute im Lager liegen, jede
  bei ihrem Lageralter, so gross wie ihre Masse. Ist eine Charge gewählt,
  steht ihr „heute · N Tage im Lager" als Linie und rechts davon „wie es
  weiterginge"; ohne Wahl liegt eine Zone „hier liegt die Ware heute
  (163–200 Tage)".
- „Welche Charge zuerst?" — eine Tabelle der ältesten Chargen mit Masse,
  Modellanteil heute und der Prognose für zwei Wochen; die Prognosezahlen
  kommen aus `erg_naechste_charge`, nicht aus dem Frontend.
- Über jedem Block drei Zahlen: bis heute, im Lager vermutet, Prognose zwei
  Wochen — jede mit Herkunftsmarke.

**Chargen** ist eine Tabelle mit Aufklapp-Zeilen (Eingang → Ausgang →
Arbeiten), die Legende der Herkunft steht oben in der Filterleiste.
**Messungen** beginnt mit den Auffälligkeiten als Karten mit Farbkante und
Sprung zur Korrektur. **Betrieb → Arbeiten** gruppiert nach Tag
(„Heute", „Gestern", Wochentag), zuerst 14 Tage, „Ältere zeigen" holt mehr.

## 3. Die Diagramme — interaktiv, korrekt, animiert

- Ein Zeiger über dem Diagramm zeigt alle Reihen der Stelle in einem
  Schwebefeld; das Feld weicht nach links, wenn es rechts nicht mehr Platz
  hat, und nach oben, wenn der Zeiger tief steht — es liegt jetzt als
  Geschwister des Rollbereichs im Diagramm, nicht mehr darin, und wird von
  der Legende nicht mehr verdeckt (der gemeldete Fehler).
- Ziehen mit der Maus vergrössert einen Ausschnitt, Mausrad zoomt,
  Doppelklick setzt zurück; auf dem Handy bleibt Wischen dem Scrollen
  vorbehalten (`touchAction: pan-y`, Zoom nur für `pointerType === 'mouse'`).
- Legendenknöpfe blenden Reihen aus; „Als Tabelle" zeigt dieselben Zahlen
  als Tabelle.
- Linien zeichnen sich beim Erscheinen (`pathLength`), Marker und Balken
  wachsen gestaffelt, Zahlen laufen zu ihrem Wert. Alles über
  `prefers-reduced-motion` abschaltbar.
- Der Vertrag mit den Prüfständen bleibt: `data-x-einheit`/`data-y-einheit`
  am SVG, `class="strich"` an jeder Achsenbeschriftung, `circle.marker`
  r ≤ 4.5, Rahmen B=720, L=56, R=16, O=16, U=36.

## 4. Die Halle — für jemanden, der die App nie gesehen hat

- **Start:** „Hallo Tomasz", darunter die laufenden Arbeiten als Karten mit
  Tätigkeits-Kachel, Charge, seit wann, wer dabei ist, ein Knopf „Mitmachen".
  Darunter zwei grosse Knöpfe: Neue Arbeit starten, Palette kontrollieren.
- **Assistent:** Fortschrittsbalken (Schritt 1 von 3), eine Frage pro
  Bildschirm, Wahlkarten mit Kachel und Erklärung, ein Haken auf der gewählten.
- **Arbeit:** oben die Kopfkarte (Kachel, Tätigkeit, Charge, Stand); der
  Zähler sieht die grosse Zahl und einen 84-px-Knopf „+ 1 Palette", der
  Vorarbeiter die Checkliste mit Haken/Ausrufezeichen/Punkt und einem
  Chevron je Zeile; der Abschluss ist der orange Punkt unten.
- **Masken:** Löschen ist ein Kreuz-Zeichen, Zurück ein Pfeil, Wiegen eine
  Waage; jedes Bedienelement ≥ 44 px (I8), auf dem Handy ≥ 60 px für die
  Hauptknöpfe.
- **Kopfzeile:** Marke, Sprache (Kürzel), Abmelden — unter 430 px nur als
  Zeichen, damit die Marke nie abgeschnitten wird.

## 5. Bausteine und Klassen (für die nächste Runde)

`src/components/Bausteine.tsx`: `Karte` (titel, unter, aktion), `Kennzahl`
(titel, wert, unter, ton), `Zahlen`, `Marke`, `Herkunft` (mit Wortabstand
davor — „9.9 t gemessen", nicht „9.9 tgemessen"), `Aufklapp`, `Erklaerung`,
`Rechenweg`, `Segmente` (der Schieber misst den aktiven Knopf, statt gleiche
Breiten anzunehmen), `Leer`, `Lade` (Skelett), `Avatar`.
`src/components/Zeichen.tsx`: alle Strichzeichen, `TaetZeichen`, `TaetKachel`.
`src/design/bewegung.ts`: `useZaehler(ziel, dauer)`, `staffel(i)`.
`src/index.css` ist nach Bereichen gegliedert (Rahmen, Seitenleiste, Kopf,
Karten, Kennzahlen, Knöpfe, Umschalter, Felder, Tabellen, Marken, Hinweise,
Aufklapper, Filterleiste, Befunde, Diagramme, Halle, Druck, Dialog, Helfer).

Inline-Stile sind aus den Seiten der Halle und des Überblicks verschwunden;
in den Betriebsseiten (Stammdaten, Ausgang-Import) stehen noch einige
Randabstände als `style` — sie sind harmlos, aber die nächste Runde darf sie
in Helferklassen (`.oben-0`, `.abstand-oben`, `.rechts-buendig`, …) überführen.

## 6. Was die Prüfstände dazugelernt haben

- `pruefstand/bildschirme.mjs` nennt bei einem Überlauf die drei Elemente,
  die hinausragen — der eine 20-px-Fehler dieser Runde (eine `auto`-Spalte im
  Grid der Halle, die eine Kopfzeile mit `nowrap` breiter machte) war damit in
  einer Minute gefunden. Die Wartezeit vor dem Bild ist 800 ms, damit Zähler
  und Linien fertig sind.
- `gegenprobe/bildschirm/invarianten.mjs` liest nur noch die Diagramm-SVGs
  (`svg[data-x-einheit]`), nicht mehr die Zeichen in den Werkzeugknöpfen.
- `pruefstand/begriffe.json`: neuer Begriff „Tempo" (kg je Stunde einer
  Tätigkeit, gemessen).
