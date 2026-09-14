# Runde Q — Befund und Fragen

> **Die aktuelle Fragenliste steht auf Seite 1–2 von
> `docs/Das-ganze-Werkzeug.pdf` (26 Fragen).** Diese Datei hält die Befunde fest,
> auf denen sie beruhen.

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

---

## Nachtrag — der Palettenbegriff, am Code geprüft

Rückmeldung: „*es gibt keine kaliberkisten — also doch, aber sie stehen auf
paletten, und wenn man waschen geht, wird das ganze palette gewaschen*",
dazu „*kein FIFO betrifft alle drei Übergänge*" und „*auch bei waschen und
sortieren gibts dann fax*".

**Das Rechenwerk bildet das bereits richtig ab. Falsch war das Diagramm im
PDF und meine Wortwahl — beides ist jetzt korrigiert.** Der Nachweis:

| Behauptung | Wo im Code | Stimmt? |
|---|---|---|
| Beim Waschen werden **Paletten** gezählt, nicht Kisten | `Zaehler.tsx` Gestalt (c): `#wasch-plus` „+ 1 Palette", je Palette `#kisten-palette`; schreibt `auftrag_palette(sortierdatum, kisten)` **ohne** `eingangsdatum` | ja |
| Die Kaliber-Palette hat **kein** Eingangsdatum/-gewicht | ebenda — die Spalten bleiben leer | ja |
| Die **Charge** bleibt bekannt | `auftrag.charge_nr` | ja |
| Masse der Wascharbeit = Kisten × gemessenes Kistengewicht | `v_auftrag_wasch_paletten` | ja |
| Zeit im **Zwischenlager** getrennt geführt | ebenda: `zwischenlager_tage` aus `sortierdatum`, kistengewichtet | ja |
| **Alter seit Ernte** ohne FIFO-Annahme | `v_auftrag_masse`: `lagertage = betriebstag(start_ts) − mv_sortier_eingang.tage_seit_epoche`, und das ist das **massegewichtete mittlere Eingangsdatum der sortierten Ware dieser Charge** | ja |
| Verderb beim Waschen **verkettet**, nicht doppelt | `v_schimmel_punkte`, 2. Zweig: `f₂ = 1 − (1−f₁)(1−g)` | ja |
| Keine doppelte Verdunstung beim Waschen | derselbe Zweig nimmt `basis = masse + faules`, **nicht** `· (1−r)^t` | ja |
| Bei W+S werden fertige Kisten gewogen | `stationsProfil`: `hatAusgang` bei `waschen_sortieren`, wenn rechenbar | ja |

### F8 · Fax nach Waschen + Sortieren bekommt keinen Vorschlag  ▪ Fehler (neu)

`src/arbeit/Abschluss.tsx:62-70` sucht die letzte Wascharbeit so:

```js
.eq('station', 'waschen')
```

Eine Arbeit mit `station = 'waschen_sortieren'` wird damit **nie gefunden**.
Wer von Hand wäscht und sortiert und danach abpackt, bekommt „Tage seit dem
Waschen" also nie vorbelegt — obwohl die App es genauso gut wüsste. Richtig
wäre `station in ('waschen','waschen_sortieren')`.

### F9 · Das mittlere Eingangsdatum schaut in die Zukunft  ▪ kleiner Fehler (neu)

`mv_sortier_eingang` mittelt über **alle** Sortier-Arbeiten einer Charge —
auch über solche, die **nach** der Wascharbeit stattfanden. Wird eine Charge
im September und noch einmal im November sortiert, verschiebt der
November-Lauf rückwirkend das Alter jeder Oktober-Wascharbeit. Richtig wäre
ein Mittel über die Sortier-Arbeiten **bis zum Tag der Wascharbeit** — so wie
es der verkettete Schimmelanteil `f₁` bereits macht (`sl.start_ts <=
a.start_ts`).

### Zusatzfragen

**21.** Passiert es in der Praxis, dass **dieselbe Charge zweimal sortiert**
wird, mit Wochen dazwischen? Davon hängt ab, wie schwer F9 wiegt.

**22.** Steht auf dem Zettel der Kaliber-Palette ausser dem Sortierdatum noch
etwas — Kaliber, Kistenzahl, Gewicht? Ein **gewogenes** Kaliber-Palettengewicht
wäre die sauberste Grösse überhaupt: es machte die ganze Brücke über
„Kisten × Kistengewicht" überflüssig.

**23.** Wird beim **Waschen** je der Palox abgelesen? Er ist dort freiwillig
(`paloxPflicht: false`). Wenn das Faule an der Waschstrasse regelmässig
anfällt, wäre es der wertvollste zusätzliche Punkt für die Verderbskurve —
weil er das **höchste** Alter misst.

---

## Nachtrag 2 — zwei Korrekturen vom Betrieb, beide belegt

### F10 · Die Massenkette nach dem Sortieren steht auf einer Zählung, die es nicht gibt  ▪ Fehler

Rückmeldung: „*Kisten je Kaliber werden nicht gezählt — das kann das CSV nicht,
weil es nicht weiss wie viele Kürbisse pro Kiste, und niemand wird händisch
die Kisten zählen und in der App eintragen.*"

Damit fällt `v_koeff_gebinde` (CSV-Masse je Band ÷ gezählte Kisten) weg — und
mit ihr die einzige Brücke von „Kisten" zurück zu „Kilo". In der Demo gemessen:

| Woher die Masse kommt | Arbeiten | Masse | hängt daran? |
|---|---|---|---|
| Waschen: Kisten × kg je Kiste | **94** | 101 408 kg | **ja** |
| Fax: gezählte Kisten | 107 | 73 608 kg | **ja** |
| Fax: Paletten × Palettenmasse | 53 | 46 171 kg | nein |
| Sortieren / W+S: Eingangspaletten | 51 | 200 465 kg | nein |

**201 von 305 Arbeiten und 175 t von 421 t verlieren ihre Masse.** Drei
Auswege stehen in Kapitel 3.7 des PDF; Weg (b) — die CSV-Masse nach
Palettenzahl verteilen — kostet keine einzige neue Handlung in der Halle,
weil die Paletten beim Waschen ohnehin gezählt werden. Entscheidung: Frage 5.

### Kalibergrenzen: „unter 600 g" war falsch

Hinterlegt ist je Sorte etwas anderes:

| zu klein unter | Sorten |
|---|---|
| 300 g | Orangita |
| 500 g | Butterkin, Mieluna, Tiana |
| 600 g | Amoro, Bolp 5110, Fictor, Kaori Kuri, Ker Madec, Orange Summer |
| 700 g | Lekor |

Und: für **8 von 11 Sorten** ist die heute geltende Fassung „Kiste ab 8 kg",
nicht Kaliber — dort klassiert die Sortier-CSV gar nicht nach Kaliber, und
„zu klein / zu gross" kann nur aus Handwägungen kommen. Ob das so gewollt ist,
ist offen (Frage 14).

### „Zu klein" ist ein Erntefehler, kein Naturgesetz

Rückmeldung: „*sie existieren — die Arbeiter sollten sie nicht ernten, aber
sie tuns eben doch manchmal.*" Für die Rechnung ändert das nichts (zu klein
wächst nicht mit der Lagerdauer). Für die Darstellung ändert es alles: Die
Zahl ist **vermeidbar** und gehört je Schlag und je Erntewoche vor die
Erntemannschaft, nicht nur in die Verlustrangliste. In der Demo reicht die
Spanne je Schlag von rund 1 % bis 10 % — bei derselben Sorte (Frage 15).

---

## Die Antworten (14.09.2026) — verbindlich festgehalten

| # | Frage | Antwort | Folge |
|---|---|---|---|
| 1 | Palox gefallen: annehmen oder fragen? | **Fragen.** Bei „ja" die Daten **nicht verwenden** — wir wissen nicht, wie voll er vor dem Leeren war. Dem Arbeiter muss man das nicht erklären. | Menge unbekannt, nicht 0 |
| 2 | Waage tariert? | **Nein — 45 kg bei leer**, an beiden Stationen. Beide Ablesungen minus 45. | kürzt sich in der Differenz weg |
| 3 | Palox über Nacht? | **Irrelevant** — Arbeitsvorgänge werden nie über Nacht pausiert, immer vor Feierabend abgeschlossen. Aber: dazwischen passieren undokumentierte Vorgänge. **Der Stand der letzten Arbeit darf nie übernommen werden.** | **Grundlegende Änderung:** Menge = Ablesung am Ende − Ablesung am Anfang **derselben Arbeit** |
| 4 | Eingangsdatum abgelesen oder geraten? | **Abgelesen** — steht genau auf dem Zettel. | bleibt tragend |
| 5 | Kistenzählung: welche Brücke? | Kisten je Kaliber werden **nie** gezählt. Relevanz war unklar. | **Neuer Nenner:** Anzahl fertiger Paletten (eine Zahl je Wascharbeit). Kistenzählung entfällt ersatzlos |
| 6 | Weitere Palox? | Zwei stationäre (Sortieren, Waschen). **Beim Fax nicht** — dort Kisten, einzeln gewogen, danach in einen Palox ausserhalb der Halle. | Fax-Maske: erst Kistenzahl, dann je Kiste wiegen |
| 7 | Kaliber-Palette wiegen? | **Könnte, machen wir aber nicht.** Auf dem Zettel: Chargennummer + Sortierdatum. | → Lösung über die fertigen Paletten |
| 8 | Palox beim Waschen? | Zweifel, weil der Nenner fehlt. | Nenner ist gelöst → **Pflicht statt freiwillig**; es sind die Punkte mit dem höchsten Alter |
| 9 | Charge mehrfach sortiert? | **Ja, immer wieder** — bis sie aufgebraucht ist. Und gleichzeitig wird für Waschen+Sortieren entnommen. | Chargenmittelwert wäre viel zu grob → Zuordnung über das Sortierdatum (94 % Treffer) |
| 10 | Gebinde in den Schlüssel? | **Ja, unbedingt** — bei beiden Kistensystemen muss das Gebinde gefragt werden. | Schlüssel: Sorte × Gebinde × System |
| 11 | Sollgewicht in der Verkaufsdatei? | Sollte drinstehen; genauere Erklärung folgt. | offen |
| 12 | Hauptzahl bei Stück-Kisten? | Kaliber ist von Kürbis zu Kürbis anders. **Beide Verkaufsarten kommen bei allen Sorten vor.** | Die Art gehört zur Arbeit, nicht zur Sorte — Frage 14 war falsch gestellt |
| 13 | Marge in Franken? | — | offen |
| 14 | Kalibergrenzen? | siehe 12 | — |
| 15 | Zu klein je Schlag? | **Ja**, aber in einem weiteren Reiter. | Reiter 3 |
| 16 | Regler tagesgenau? | **Tagesgenau.** | |
| 17 | Nur Datum oder auch Bestand? | **Datum und erwarteter Lagerbestand.** | |
| 18 | Woher kommt der erwartete Bestand? | **Mittelmass** — alle Chargen gehen anteilig gleich raus. Der Rechner ist noch genauer zu überlegen. | drei Rückfragen in Kapitel 10.2 des PDF |
| 19 | Gruppierung? | **Sehr benutzerfreundlich.** | |
| 21 | Balken je Zeile? | **Ja.** | |
| 22 | Stapelgrafik? | **Einfach verständlich** — es soll sich als Praxiswerkzeug eignen. | gestrichen, drei Grafiken bleiben |
| 23 | Seitenstruktur? | **Neu planen.** Drei Reiter nach Wichtigkeit: 1 Lager-Management (Tagesgeschäft) · 2 Rückblick (welcher Verlust wann und wie) · 3 Extra-Fakten. | Teil II des PDF |
| 26 | Palox sofort reparieren? | **Ja.** | |

### Was am Rechenwerk dadurch besser wird

| War | Ist |
|---|---|
| Faul-Menge über Arbeiten hinweg abgeleitet | **gemessen** — zwei Ablesungen in derselben Arbeit |
| Alter beim Waschen = Chargenmittel über die Saison | **abgelesen** in beiden Teilen (Sortierdatum + Eingangsdatum der passenden Sortierarbeit); 305 von 323 Paletten (94 %) treffen exakt |
| Masse der Wascharbeit über zwei Zwischenschritte | **gemessen** — fertige Paletten × gewogenes Palettennetto |
| kg je Kiste quer über Gebinde gemittelt | je Sorte × Gebinde × System getrennt |

Damit sind F9 (Blick in die Zukunft) und F10 (Massenkette ohne Zählung) beide
gelöst, und F1–F3 (Palox) sind entscheidungsreif.
