# Runde Q — Befund und Fragen

Grundlage: die Rückmeldung vom 14.09. („Palox rechnet minus 445", „verschenkte
Marge braucht keine Verkaufsdatei", „Was wird aus der liegenden Ware ist
grafischer Horror", „weniger Themenblöcke, dafür richtig gut").

Alles unten ist **am Code nachgeprüft**, nicht vermutet. Dateiangaben dabei.

---

## Teil 1 — Was ich gefunden habe

### F1 · Der Palox zeigt bei gefallenem Stand gar nichts  ▪ Fehler

`src/arbeit/PaloxMaske.tsx:44-45`

```js
const gefallen = n !== null && vorher !== null && n < vorher
const menge = … : gefallen ? null : n - vorher
```

Ist der Stand gefallen, ist `menge = null` — und die ganze Ergebniszeile wird
nicht gerendert. Im Browser nachgestellt (Stand zuletzt 350, getippt 45):

```
getippt 45   →  Waage zeigt (kg)   [45]   [Eintragen]        ← nichts sonst
getippt 400  →  50 kg (400 − 350)
getippt 360  →  10 kg (360 − 350)
```

Der Arbeiter bekommt **keine Rückmeldung, keinen Hinweis, keine Erklärung**.
Genau das ist „ich versteh nicht was du da machst".

### F2 · `palox_geleert` wird von keiner Maske je auf `true` gesetzt  ▪ Fehler

`src/arbeit/PaloxMaske.tsx:52-53` schreibt in **beiden** Zweigen fest
`palox_geleert: false`. Die Spalte gibt es seit 0060, die Datenbank behandelt
sie korrekt (`v_palox_stand`: `WHEN s.palox_geleert THEN GREATEST(stand −
palox_tara_kg(), 0)`) — aber über die Oberfläche ist dieser Weg
**nicht erreichbar**. Der Fall „Palox geleert, Waage zeigt jetzt die Tara"
kann gar nicht erfasst werden.

**Damit hat der Betrieb recht:** Bei leerem Palox und Tara 45 muss
`45 − 45 = 0 kg` herauskommen, und ab dann zählt jede weitere Ablesung gegen
45. Die Datenbank kann das. Die Maske löst es nie aus.

### F3 · Bei gefallenem Stand wird `kg: 0` gespeichert  ▪ Fehler

`PaloxMaske.tsx:53` — `kg: Math.round(Math.max(menge ?? 0, 0))`. Aus
„unbekannt" wird beim Speichern eine **gemessene Null**. Das ist genau der
Übergang, den 0064 überall sonst abgestellt hat. (Die Auswertung rettet sich,
weil `v_palox_stand` die Differenz unabhängig neu rechnet — aber die Spalte
`kg` in der Rohzeile ist dann falsch.)

### F4 · Die Überfüllung hängt an der Verkaufsdatei, obwohl die Messung allein steht  ▪ Entwurfsfehler

`v_ueberfuellung_verkauf` ist ein **FULL JOIN** aus `verkauft` × `gewogen`
über (Gruppe, Sorte, Charge, Kistensystem, Soll, Stück, Kaliber).
`verschenkt_kg` verlangt `v.kisten_verkauft IS NOT NULL`.

Folge: Ohne Verkaufsdatei steht die **Messung** — „Soll 8.0, gewogen 8.48,
+0.48 je Kiste aus 28 Wägungen" — zwar da, aber unter „Gewogen, aber nicht
verkauft" eingeklappt, und die Karte wirkt wie ein Fehler. In der Demo:
2 Systeme mit Verkaufsbezug, **17 ohne**.

Der Betrieb hat recht: Die Messung ist die Hauptzahl und braucht niemanden.
Die Hochrechnung auf Kilo ist die zweite Zahl und braucht die Datei.

### F5 · Die Gebindeart fällt aus dem Mittel heraus  ▪ Lücke

`v_ausgang_kennzahl` führt `gebindeart` je Wägung mit —
`v_ueberfuellung_verkauf` gruppiert aber **ohne sie**. Zwei verschiedene
IFCO-Typen mit demselben Sollgewicht landen im selben Durchschnitt. Genau der
Fall „8 kg in IFCO xxx" gegen „8 kg in IFCO yyy".

### F6 · Zwei Kopfzahlen, von denen die eine in der anderen steckt  ▪ Benennung

Block „Faules im Lager": *Faules bis heute* **26.2 t** und *Vermutet noch im
Lager* **18.2 t**. Das zweite ist kein anderer Posten — es ist der
**Teil des ersten**, der an der liegenden Ware hängt (`kg_projiziert`);
8.0 t sind an schon ausgelieferter Ware (`kg_beobachtet`). Die Nebeneinander-
stellung legt nahe, es seien zwei Dinge.

### F7 · Nebenbefund: UTC-Tag statt Betriebstag

`mv_auftrag_masse` rechnet `lagertage` mit `a.start_ts::date` — dem UTC-Tag.
0067 hat fünf andere Stellen auf `betriebstag()` umgestellt und diese
übersehen. Wirkung: bis zu ein Tag Fehler in der Lagerdauer jedes Messpunkts.

---

## Teil 2 — Was ich bestätigen kann (kein Fehler)

### Das Eingangsdatum beim Zählen ist tragend — bitte behalten

`mv_auftrag_masse`:

```sql
lagertage = Σ((start_ts::date − m.eingangsdatum) · netto_kg) / Σ netto_kg
```

Ohne Eingangsdatum gibt es **kein Alter der Arbeit**, ohne Alter **keinen
Punkt auf der Verderbskurve**, ohne Punkte **kein Modell**. Es ist die eine
Angabe, aus der die ganze Zeitachse entsteht.

### Die Kisten je Kaliber beim Sortieren sind ebenfalls tragend

`v_koeff_gebinde`: **CSV-Masse je Kaliberband ÷ gezählte Kisten = kg je
Kiste**. Das ist der einzige Weg, von „Kisten" zurück zu „Kilo" zu kommen.
`v_auftrag_gebinde_masse` benutzt es, um einer **Wascharbeit überhaupt eine
Masse zu geben** („kg ist NULL, solange das Kaliber nie am Sortieren gezählt
wurde — dann fehlt der Nenner weiterhin"). Ohne die Zählung hat der ganze
Weg 1 nach dem Sortieren keine Bezugsmasse.

### Die Verdunstung wird beim Palox-Nenner abgezogen — ja, das ist mitgedacht

`v_schimmel_beobachtung`:

```sql
basis_jetzt_kg = eingang_netto_kg · (1 − r)^lagertage
anteil         = schimmel_kg / basis_jetzt_kg
```

Also **nicht** das Eingangsgewicht, sondern das Eingangsgewicht abzüglich der
erwarteten Verdunstung bis zum Tag der Arbeit, mit der gedeckelten Rate der
Sorte. Der Anteil ist „Faules je Kilo, das an diesem Tag noch da war".

### Die Kalibermitte ist längst gemessen — aus 96 291 einzeln gewogenen Kürbissen

Die Frage „Kaliber 1100–1600, wiegen die 1200 oder 1700?" beantwortet die
Sortier-CSV direkt und viel genauer als eine Palettenwägung:

| Sorte | Band | Stück | Ø | Lage im Band |
|---|---|---|---|---|
| Amoro | 1100–1600 g | 5 134 | **1 329 g** | 46 % |
| Amoro | 1600–2000 g | 1 719 | 1 757 g | 39 % |
| Butterkin | 1200–1800 g | 12 175 | 1 423 g | 37 % |
| Kaori Kuri | 600–1100 g | 12 806 | 876 g | 55 % |
| Kaori Kuri | 1600–2000 g | 3 399 | **1 644 g** | **11 %** |

Kaori Kuri im obersten Band liegt fast auf der Unterkante — genau die Art
Aussage, die gesucht war. Die Zahl steht heute schon in der Datenbank
(`band_mittel_g`), aber zweifach eingeklappt unter „Stück je Kiste".

---

## Teil 3 — Wie die App danach aussehen könnte

**Grundsatz: vier Themenblöcke statt neunzehn Karten.** Jeder beantwortet
eine Frage, die der Betrieb wirklich stellt, und beantwortet sie ganz.

### Block 1 · Der Lagerrechner  *(ersetzt: Stapelgrafik, „Was ist noch im Haus", Chargen-Reiter, „Welche Charge zuerst")*

```
┌──────────────────────────────────────────────────────────────────────┐
│  Stichtag:  [ heute ] [ +2 Wo ] [ +4 Wo ] [ Saisonende ]             │
│             ◄──────────●──────────────────────────►   12.10.2026     │
├──────────────────────────────────────────────────────────────────────┤
│ Sorte / Charge   Schlag     liegt seit  Im Lager  verkaufsfähig      │
│                                                    12.10.   Anteil    │
│ ▼ Tiana                                  62.4 t    46.1 t    73.9 %  │
│     1632         Andi Ball  174–180 d    29.3 t    21.8 t    74.4 %  │
│     1641         Rüti       151–158 d    18.7 t    14.2 t    75.9 %  │
│     1655         Weid        92– 99 d    14.4 t    11.5 t    79.9 %  │
│ ▶ Kaori Kuri                             41.2 t    30.8 t    74.8 %  │
│ ▶ Butterkin                              38.9 t    28.1 t    72.2 %  │
└──────────────────────────────────────────────────────────────────────┘
```

Ein Regler oben, eine Tabelle darunter, alles rechnet mit. Keine Grafik, die
man entziffern muss. Standardsortierung: **schlechtester Anteil zuerst** —
das ist die Charge, die zuerst raus sollte. Je Zeile aufklappbar: die
Aufteilung (faul · verdunstet · zu klein/gross · Fax) und die Hülle.

Die Daten liegen vollständig vor (`erg_prognose`, Gruppe `charge` und `sorte`,
je Wochenschritt) — es braucht keine neue Mathematik, nur eine andere
Darstellung.

### Block 2 · Wohin geht der Kürbis  *(bleibt, wird der einzige Ort für Anteile)*

Der 100-%-Balken über den ganzen Eingang plus die zwei Ranglisten. Neu darin:
die **verschenkte Marge als eigener, absoluter Posten**.

### Block 3 · Kisten und Kaliber  *(neu gebaut, strikt zweigeteilt)*

**3a — Kisten nach Gewicht („ab 8 kg"):** Was kostet uns das Überfüllen?

| Sorte | Gebinde | Soll | Ø gewogen | Abweichung | Wägungen | verkaufte Kisten | verschenkt |
|---|---|---|---|---|---|---|---|
| Tiana | IFCO xxx | 8.0 | 8.48 | **+0.48** | 28 (896 Kisten) | 2 475 | **1 191 kg** |

Linke Hälfte = Messung, steht immer. Rechte Hälfte = Hochrechnung, braucht die
Verkaufsdatei; fehlt sie, steht dort „—" und ein Satz, was fehlt — die Karte
sieht dann nicht nach Fehler aus.

**3b — Kisten nach Stück („6 Stück je Kiste"):** Wo im Band liegt die Ware?

| Sorte | Kaliber | aus der Sortier-CSV | aus gewogenen Paletten | Lage im Band |
|---|---|---|---|---|
| Amoro | 1100–1600 g | 1 329 g (5 134 Stück) | 1 272 g (4 Paletten) | `1100 ▓▓▓▓▓●▓▓▓▓▓▓ 1600` |

Zwei unabhängige Quellen nebeneinander — sie prüfen sich gegenseitig.

### Block 4 · Stimmen die Zahlen  *(= heutiger Reiter „Messungen")*

Auffälligkeiten, Vollständigkeit, Koeffizienten, Modell, Bilanz — **und
sämtliche Streubilder und Kurven**. Sie sind Beleg, nicht Antwort.

---

## Teil 4 — Zwanzig Fragen

### Palox

**1.** Wenn der Stand unter dem letzten liegt: soll die App das **still als
„geleert" deuten** (und `Stand − Tara` rechnen), oder **einmal nachfragen**
(„Palox wurde geleert — richtig?"), weil ein gefallener Stand auch ein
Tippfehler sein kann?

**2.** Zeigt die Waage bei leerem Palox **45 kg an**, oder ist sie auf null
tariert? Und ist die Tara an beiden Stationen gleich?

**3.** Wenn der Palox abends halb voll stehen bleibt und morgens eine
**andere Charge** anfängt: wem gehört das Faule darin? Heute zählt es zur
neuen Arbeit. Soll die App verlangen, dass vor einem Chargenwechsel geleert
wird — oder ist das in der Praxis unrealistisch?

### Die Halle

**4.** Das **Eingangsdatum** beim Zählen ist tragend (siehe oben) und bleibt.
Aber: wird es in der Praxis wirklich vom Zettel abgelesen, oder geraten? Wäre
„nur Monat" oder „Kalenderwoche" ehrlicher?

**5.** Die **Kisten je Kaliber** beim Sortieren sind ebenfalls tragend.
Werden sie tatsächlich gezählt? Wenn nicht, hat der ganze Weg 1 nach dem
Sortieren keine Bezugsmasse — dann müssten wir eine andere Brücke bauen
(z. B. Kisten je Palette × Paletten).

**6.** Gibt es ausser Sortieren / Waschen / Waschen+Sortieren / Fax noch eine
Station, an der ein Palox steht?

### Kisten und Kaliber

**7.** Soll der Schlüssel für „Ø kg je Kiste" **Sorte × Gebinde × Soll** sein
(heute ohne Gebinde)? Also getrennte Durchschnitte je IFCO-Typ?

**8.** Wie erkennt die **Verkaufsdatei** das Sollgewicht — steht „8 kg" im
Artikelnamen, oder muss der Betriebsleiter je Artikel einmal sagen „das ist
eine 8-kg-Kiste in IFCO xxx"?

**9.** Bei „x Stück je Kiste": welche Zahl ist die **Hauptzahl** — die aus
der Sortier-CSV (zehntausende Kürbisse, aber vor dem Waschen) oder die aus
den gewogenen Paletten (wenige, aber die Ware, die tatsächlich rausgeht)?

**10.** Soll die **verschenkte Marge** auch in **Franken** stehen, oder
bewusst nur in Kilo? (Die Preise stehen in der Verkaufsdatei.)

**11.** Gehört der **Spielraum** bei Stück-Kisten überhaupt in die Übersicht,
oder ist er reine Information für den Anbau — also nur in Block 3?

### Der Lagerrechner

**12.** **Datumsregler: tagesgenau oder in Wochenschritten?** Tagesgenau
bräuchte eine Zwischenrechnung, wöchentlich ist sofort da.

**13.** Gibt er **nur ein Datum** ein — oder auch einen **erwarteten
Lagerbestand** („am 1.12. habe ich noch 120 t")?

**14.** *(Die wichtigste Frage.)* Wenn er einen erwarteten Bestand eingibt:
**woher kommen die 120 t?** Das ändert das Ergebnis stark:
  **(a)** anteilig aus allen Chargen (wie heute gerechnet),
  **(b)** die ältesten zuerst verkauft → der Rest ist jünger und besser,
  **(c)** er sagt je Charge selbst, was er verkaufen will.

**15.** Soll die Tabelle **nach Sorte gruppiert** sein (Sortenzeile mit Summe,
Chargen aufklappbar) oder flach mit einem Sortenfilter?

**16.** Welche Spalten müssen unbedingt rein? Vorschlag: Charge · Schlag ·
liegt seit · Im Lager · verkaufsfähig am Stichtag · Anteil. Und als
aufklappbare Zeile: faul · verdunstet · zu klein/gross · Fax. Fehlt etwas —
Eingangsdatum? Paletten? Letzte Lieferung?

**17.** Soll je Zeile ein kleiner Balken **heute → Stichtag** stehen (damit
man die Verschlechterung sieht, ohne ein Diagramm zu lesen)?

### Aufbau

**18.** **„Faules bis heute 26.2 t" und „Vermutet noch im Lager 18.2 t"** —
das zweite steckt im ersten. Vorschlag: *eine* Zahl „Faules insgesamt
26.2 t", darunter „an ausgelieferter Ware 8.0 t · noch im Lager 18.2 t".
Einverstanden?

**19.** Sollen **Überblick, Ursachen und Chargen zu zwei Seiten
verschmelzen** — etwa „Lager" (Rechner + Bestand) und „Ursachen" (wohin geht
der Kürbis + Kisten/Kaliber)? Oder sollen die fünf Reiter bleiben und nur
ihr Inhalt neu?

**20.** Die **Stapelgrafik** („Was wird aus der liegenden Ware") ersatzlos
streichen? Und die **Streubilder und Modellkurven** vollständig nach
„Messungen" verschieben — oder sollen sie bei ihrer Ursache eingeklappt
bleiben?

---

*Keine Änderung am Code, bis diese Fragen beantwortet sind.*
