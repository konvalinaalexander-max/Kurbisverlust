# Auftrag: Prüfwerk bauen, das System durchleuchten, die Befunde abarbeiten

## 0. In einem Satz

Baue ein eigenständiges Analysewerkzeug, das dieses System vollständig
durchleuchtet, lass es laufen, mach dir aus dem, was es findet, einen Plan —
und arbeite den Plan ab, **ohne die App komplizierter zu machen**.

## 1. Der Auftrag in drei Phasen

| Phase | Ergebnis | Fertig, wenn |
|---|---|---|
| **I — Bauen** | `pruefwerk/`, zehn Sonden, maschinenlesbare Befunde | jede Sonde läuft, der Läufer aggregiert, der Bericht steht |
| **II — Verstehen** | `docs/PRUEFBERICHT.md` + ein Plan | jeder Befund hat Beleg, Grösse und Urteil; der Plan ist begründet sortiert |
| **III — Abarbeiten** | Reparaturen mit Tests, Doku nachgezogen | das Prüfwerk läuft erneut und der Befund ist weg — ohne dass ein neuer entstand |

Fang **nicht** mit dem Reparieren an. Die erste Reparatur kommt, wenn das
Prüfwerk steht und der Plan geschrieben ist. Wer sofort losflickt, repariert
die drei Dinge, die ihm zuerst aufgefallen sind, und übersieht die dreissig
dahinter.

## 2. Die Haltung

### 2.1 Drei Fehlerklassen — nur eine ist die Beute

| Klasse | Beispiel | Wer findet sie sonst |
|---|---|---|
| 1 — technisch | Absturz, falscher Typ, verlorene Zeile | tsc, Tests, Prüfstände |
| 2 — Kette | ein erfasstes Feld liest niemand; eine ausgewertete Spalte füllt keine Maske | Lückenscanner, Kette |
| **3 — Bedeutung** | **die Zahl ist korrekt gerechnet und meint das Falsche** | **niemand** |

Klasse 1 und 2 hat das Projekt im Griff — sieben Prüfstände, alle grün.
Genau deshalb sind sie nicht deine Aufgabe. **Deine Beute ist Klasse 3**, und
die findet man nicht durch Ausführen, sondern durch Verstehen.

Eine grüne Testsuite beweist, dass das Programm tut, was es tut. Sie beweist
nicht, dass es das Richtige tut — sie ist vom selben Kopf geschrieben wie der
Code und prüft dieselbe Annahme zweimal.

### 2.2 Die Liste des Betriebs ist Kalibrierung, nicht Auftrag

In Abschnitt 9 stehen zwei Befunde, die der Betrieb selbst gefunden hat. Sie
zeigen die **Tiefe**, die erwartet wird — nicht den **Umfang**. Wer nur sie
abarbeitet, hat den Auftrag verfehlt. Die eigentliche Leistung ist, die
zwanzig zu finden, die noch niemand gesehen hat.

Deshalb sind die schärfsten Sonden in Abschnitt 5 **erzeugend**, nicht
prüfend: Sie stellen Fragen, die niemand vorher formuliert hat, und finden
damit Dinge, die auf keiner Liste stehen.

### 2.3 Das Hypothesenbuch — bevor du das Werkzeug baust

Lies zuerst (Abschnitt 4.1) und schreib dann `pruefwerk/hypothesen.md`:
**mindestens vierzig** Sätze der Form

> *Wenn ⟨Umstand⟩, dann wäre ⟨Zahl⟩ falsch, und man würde es merken an
> ⟨Beobachtung⟩ — geprüft von Sonde ⟨n⟩.*

Vierzig ist keine Zierde. Wer nur zehn schreibt, hat nicht verstanden, wie
viele Stellen ein System dieser Grösse hat. Verteile sie über alle zehn
Sonden; wo eine Sonde keine Hypothese abbekommt, prüfst du entweder das
Falsche oder du hast nicht genau genug gelesen.

Danach: Jede Hypothese wird von einer Sonde beantwortet — bestätigt, widerlegt
oder „nicht entscheidbar, weil ⟨Grund⟩". Keine bleibt offen liegen.

### 2.4 Gegenlesen, bevor du etwas Befund nennst

Für jeden Fund schreibst du **zuerst die Gegenrede**: Warum könnte es doch
richtig sein? Welche Absicht steckt vielleicht dahinter, die ich übersehe?
Erst wenn die Gegenrede nicht trägt, ist es ein Befund. Das kostet Minuten
und spart einen Bericht voller Fehlalarme, den niemand ernst nimmt.

## 3. Die eiserne Regel: die App wird nicht komplizierter

Der Betrieb hat das ausdrücklich gesagt, und es ist die wichtigste Grenze
dieser Runde. Ein Arbeiter mit kalten Händen an einem alten Handy und ein
Betriebsleiter, der einmal am Tag draufschaut — für die ist das gebaut.

**Jede** vorgeschlagene Änderung bekommt genau eine von zwei Marken:

- **Reparatur** — eine Zahl war falsch, eine Beschriftung log, eine Masse
  wurde doppelt gezählt, eine Näherung war unsichtbar. Wird gebaut.
- **Erweiterung** — die App könnte etwas Neues. Wird **nicht** gebaut, sondern
  aufgeschrieben und dem Betrieb vorgelegt.

Ein neues Eingabefeld, ein neuer Bildschirm, eine neue Kennzahl, ein neuer
Reiter sind im Zweifel Erweiterung. Auch in der Betriebsleiter-Oberfläche: Ein
Befund heilt man lieber, indem man eine irreführende Zahl **richtigstellt oder
entfernt**, als indem man drei erklärende danebenstellt.

Harte Grenzen, an denen ich das nachmesse:

- Die Zahl der Eingabefelder in den Arbeiter-Masken darf **nicht steigen** —
  es sei denn, du begründest für jedes einzelne in **Kilo**, was es rettet,
  und der Betrieb hat zugestimmt.
- Keine neue Abhängigkeit im Auslieferungsstand (`dependencies` in
  `package.json` bleibt, wie sie ist).
- Das Prüfwerk selbst ist **nicht Teil der App**: eigenes Verzeichnis, nicht
  im Build, nicht im Bündel, kein Import aus `src/` in die App zurück.
- Weniger ist ein gültiges Ergebnis. Wenn eine Zahl mehr verwirrt als sie
  nützt, ist ihr Entfernen eine Reparatur.

## 4. Phase I — Das Prüfwerk bauen

### 4.1 Vorher lesen, vollständig

1. `docs/ABLAUF.md` — **was auf dem Betrieb wirklich passiert.** Der Massstab
   für alles. Am Ende die Tabelle „Annahmen, die im Modell stecken": rund
   zwanzig Zeilen, jede ein Prüfauftrag.
2. `docs/ABMACHUNGEN.md` — 46 nummerierte Abmachungen mit Datum und dem
   Test, der jede beweist (AB-14 ist die einzige noch offene).
3. `docs/FRAGEN.md` — was der Betrieb **nicht** beantwortet hat. Achte
   besonders darauf, ob eine offene Frage im Code inzwischen still
   beantwortet wurde.
4. `docs/DATENFLUSS.md` — die Landkarte: welche Zahl erfasst wird, was
   daraus gerechnet wird, wo sie beim Betriebsleiter auftaucht. Der
   schnellste Überblick über die ganze Kette.
5. `docs/ENTSCHEIDUNGEN.md` (warum etwas so ist, je Runde ein Abschnitt),
   `docs/STATISTIK_BEFUND.md` (was gemessen wurde und wie gut es trifft),
   `docs/UI-KONZEPT.md` (die zwei Rollen).
6. `supabase/setup.sql`, **Teil B** — dort steht jede Ansicht und jede
   rechnende Funktion genau einmal, in ausgerechneter Reihenfolge. Das ist der
   heutige Stand; die Migrationen darunter sind die Geschichte.
7. `src/arbeit/` (Masken des Arbeiters), `src/pages/` (Seiten des
   Betriebsleiters), `src/auswertung/daten.ts` (was die App lädt).

Die Dokumente sind auf dem Stand von Runde K (9. September 2026, Schema 0063)
und wurden davor auf falsche Datumsangaben, falsche Dateinamen und veraltete
Zahlen durchgesehen. Findest du trotzdem eine Stelle, an der die Doku etwas
anderes behauptet als der Code tut, ist **das ein Befund** — und einer der
wertvollsten, weil daran das Orakel (5.1) hängt.

Lies mit dem Bleistift: Erfassungsmatrix (Feld → Spalte → Leser → Verhalten
bei leer) und Zahlenmatrix (Bildschirmzahl → Quelle → Einheit → Nenner →
gemessen/gerechnet). Beide werden später von Sonden **maschinell** erzeugt —
deine Handfassung ist die Gegenprobe dazu. Wo Hand und Maschine
auseinandergehen, hat eine von beiden etwas übersehen, und das ist
interessant.

### 4.2 Wo das Prüfwerk lebt

```
pruefwerk/                     ← nicht Teil der App
  lauf.mjs                     ← Einstieg: node pruefwerk/lauf.mjs [--nur 04] [--schnell]
  hypothesen.md                ← Abschnitt 2.3
  sonden/
    01_lineage.mjs             02_bezugsgroessen.mjs   03_erfassung.mjs
    04_orakel.mjs              05_metamorph.mjs        06_mutation.mjs
    07_szenarien.mjs           08_leer_nicht_null.mjs  09_begriffe.mjs
    10_annahmen.mjs
  fixtures/                    ← Papierfälle und Störfälle als SQL
  befunde/befunde.json         ← maschinenlesbar, stabile Kennungen
  bericht.mjs                  ← erzeugt docs/PRUEFBERICHT.md
```

Regeln für das Werkzeug selbst:

- Reines Node, keine neue Abhängigkeit ausser dem, was schon da ist
  (Playwright ist vorhanden).
- Jede Sonde ist eine Datei mit derselben Schnittstelle:
  `export async function laufen(umgebung) → Befund[]`.
- Der Läufer kann einzeln, alles, schnell oder gründlich; er schreibt
  Zwischenstände, damit ein langer Lauf nicht alles verliert.
- **Wiederholbar:** Zweimal laufen ergibt dieselben Befunde mit denselben
  Kennungen. Ein Befund, der beim zweiten Lauf verschwindet, ist ein Fehler im
  Prüfwerk.
- **Selbstprüfend:** Jede Sonde hat mindestens einen eingebauten Fall, bei dem
  sie anschlagen *muss* (ein absichtlich falscher Datensatz). Schlägt sie
  dort nicht an, meldet sich der Läufer — eine Sonde, die nichts findet und
  auch nichts finden *kann*, ist schlimmer als keine.

### 4.3 Das Befundformat

```json
{
  "id": "BZG-004",
  "sonde": "02_bezugsgroessen",
  "klasse": 3,
  "ort": { "datei": "src/pages/Ueberblick.tsx", "zeile": 87, "sicht": "erg_bilanz" },
  "titel": "Verlust in Prozent des Eingangs statt der liegenden Ware",
  "steht_da": "prozent(verlust_heute_kg / eingang_kg) — „des Eingangs\"",
  "muesste": "…",
  "warum": "…",
  "beleg": "pruefwerk/fixtures/…sql + Abfrage, ausführbar",
  "groesse": { "wert": 4.2, "einheit": "Prozentpunkte", "basis": "Demodaten" },
  "sicherheit": "hoch | mittel | Verdacht",
  "gegenrede": "…",
  "marke": "Reparatur | Erweiterung | Entscheidung des Betriebs",
  "aufwand": "klein | mittel | gross",
  "stand": "offen | behoben | verworfen"
}
```

**Ohne `groesse` ist es kein Befund, sondern eine Meinung.** Wenn du die
Grösse nicht ausrechnen kannst, ist genau das der erste Befund: Die Zahl ist
nicht überprüfbar.

## 5. Die vier scharfen Waffen

Sonden 1–3 und 8–10 sind Fleissarbeit: Sie zählen auf, was da ist, und
vergleichen es mit dem, was dastehen müsste. Nötig, aber sie finden nur, wonach
du gesucht hast.

Die vier hier finden, wonach niemand gesucht hat. Bau sie zuerst und bau sie
gut.

### 5.1 Sonde 04 — Das unabhängige Orakel

**Die Idee.** Schreib die Massenkaskade **ein zweites Mal**, in JavaScript, aus
den Rohzeilen — und zwar **aus der Prosa**, nicht aus dem SQL. Quelle sind
`docs/ABLAUF.md`, `docs/ENTSCHEIDUNGEN.md` und die Spaltenbeschreibungen in der
Datenbank: also das, was das Programm zu tun **behauptet**. Dann lass beide
auf denselben Daten laufen und vergleiche jede Zwischengrösse je Charge, je
Eingangstag, je Portion.

**Warum das die stärkste Waffe ist.** Eine Abweichung heisst: Entweder rechnet
das SQL etwas anderes, als die Doku sagt — oder die Doku beschreibt etwas
anderes, als gemeint war. **Beides ist ein Befund erster Güte**, und beide
findet man auf keinem anderen Weg. Das ist die maschinelle Fassung der Frage
„Versteht das Programm wirklich, was im Betrieb passiert?".

**Die eiserne Disziplin dabei:** Es ist **verboten**, das Orakel
nachzujustieren, bis es mit dem SQL übereinstimmt. Jede Abweichung wird
einzeln entschieden, und die Entscheidung wird aufgeschrieben: *Welche Seite
hatte recht, und woran erkennt man das?* Wer das Orakel dem SQL anpasst, hat
sich das Werkzeug zerstört, ohne dass es jemand merkt.

**Umfang:** m0 → m1 → m2 → die sechs Ströme, die Aufteilung in `ausgelagert`
und `lager`, die Rückrechnung `m0 = geliefert ÷ verkaufsfähiger Anteil`, die
Kohortenverteilung nach Eingangsanteil, die Alterung bis `heute()`. Dazu die
Aggregate je Charge und die Saisonbilanz.

### 5.2 Sonde 05 — Metamorphe Beziehungen

**Die Idee.** Es gibt Aussagen, die **unabhängig von den Daten** gelten müssen.
Man braucht kein bekanntes richtiges Ergebnis, um sie zu prüfen — nur zwei
Läufe. Erzeuge Zufallssaisons (viele, mit festem Startwert, damit es
wiederholbar bleibt) und prüfe:

| Beziehung | Muss gelten |
|---|---|
| **Skalierung** | Alle Massen mal zehn → alle Kilo mal zehn, alle Prozente unverändert |
| **Erhaltung** | Je Portion: Verdunstung + Sockel + Schimmel + klein + Nebenkanal + Fax + verkaufsfähig = m0, auf den Rundungsrest genau |
| **Zerlegung** | Summe über Sorten = Summe über Schläge = Summe über Chargen = Gesamt |
| **Monotonie in der Zeit** | Längere Lagerdauer → nie weniger Verdunstung, nie weniger Verderb |
| **Monotonie in der Rate** | Grösseres r → nie weniger Verdunstung |
| **Zeitpfeil** | Dieselben Daten mit `heute()` einen Tag später: „bis heute" wird nie kleiner |
| **Idempotenz** | Auswertung zweimal rechnen → identische Zahlen |
| **Unwissen bleibt Unwissen** | Koeffizient ohne Messung → Ergebnis leer, **nie 0**; und die Zahl, die ihn enthält, ist als unvollständig markiert |
| **Verschiebung** | Eine Palette einen Tag früher eingelagert → Alter steigt um genau einen Tag, sonst ändert sich nichts |
| **Nullfall** | Keine Lieferungen → alles liegt im Haus; Eingang = im Haus + Verlust bis heute |
| **Doppelung** | Dieselbe Sortier-CSV zweimal eingelesen → keine Zahl ändert sich |
| **Reihenfolge** | Dieselben Zeilen in anderer Einfügereihenfolge → identisches Ergebnis |

Jede verletzte Beziehung ist ein Befund mit sofort ausrechenbarer Grösse. Und
die Liste ist nicht abschliessend: **Leite selbst weitere ab.** Jede Formel im
Modell hat Eigenschaften, die man ausnutzen kann.

### 5.3 Sonde 06 — Mutation: wie stark sind die Tests wirklich?

**Die Idee.** Ändere den Code absichtlich falsch und sieh nach, ob irgendein
Test anschlägt. Was unbemerkt durchgeht, ist **ungeprüftes Gebiet** — und
ungeprüftes Gebiet ist genau dort, wo Klasse-3-Fehler wohnen.

Mutationen auf `supabase/migrations/*.sql` (auf einer Kopie, nie im Original):

- `+` ↔ `-`, `*` ↔ `/`, `<` ↔ `<=`, `>` ↔ `>=`
- ein `filter (where …)` entfernen
- `coalesce(x, 0)` → `x` und umgekehrt
- `1 - f` → `f`
- `greatest(x, 0)` → `x`
- eine Konstante um 10 % verschieben (Deckel, Schwellen, Tara)
- zwei gleichtypige Spalten vertauschen
- ein `where`-Prädikat negieren

Und auf `src/`: Vorzeichen, Faktor 1000, Zähler und Nenner tauschen.

Nach jeder Mutation: `npm run pruefen` **und** die Datenbank-Suite. Zähle
**überlebende Mutanten** — jeder ist ein Loch. Das Ergebnis ist eine Landkarte
der ungeprüften Flächen, und die ist wertvoller als jede
Zeilenabdeckungszahl. Nimm die zwanzig überlebenden Mutanten mit der grössten
Wirkung und schau dort **von Hand** nach, ob dort auch ein echter Fehler sitzt.

Lauf lange — starte diese Sonde als Erstes im Hintergrund und lies weiter,
während sie arbeitet.

### 5.4 Sonde 01 — Herkunft: was eine Zahl über sich behauptet

**Die Idee.** Jede Zahl auf dem Bildschirm trägt eine Beschriftung, und die
Beschriftung ist eine **Behauptung**: „gemessen", „gerechnet", „% des
Eingangs", „bis heute", „Verlust". Prüfe die Behauptung **maschinell** gegen
die tatsächliche Herkunft.

Bau dazu aus den Ansichtsdefinitionen der Datenbank (`pg_depend`, Textanalyse
der Definitionen) den **Abstammungsbaum** jedes angezeigten Feldes bis zu den
Grundtabellen. Dann:

- „gemessen" darf in seiner Abstammung **keine** Koeffizienten-Sicht haben und
  keine Sicht, die ein Modell auswertet;
- „bis heute" darf keine Zeile enthalten, deren Datum in der Zukunft liegt;
- „% von X" muss tatsächlich durch X teilen — vergleiche Beschriftung und
  Formel, nicht Beschriftung und Absicht;
- „Verlust" darf keinen Strom des Buchs `marge` enthalten;
- eine Zahl, deren Abstammung eine Näherung enthält (mittlere Tara, mittlere
  Palettenmasse, gepoolter Koeffizient), muss das an sich tragen.

Der bestehende Begriffs-Prüfstand (`pruefstand/beschriftung.mjs`) liest die
Bildschirme bereits. Nimm ihn als Ausgangspunkt und **erweitere ihn um die
Herkunft** — bisher prüft er, ob ein Name im Lexikon steht, nicht, ob er
stimmt.

## 6. Die übrigen sechs Sonden

**02 — Bezugsgrössen.** Sammle jeden Prozentwert der App: Ort, Zähler, Nenner,
Beschriftung. Prüfe jeden gegen die Frage, die er beantworten soll. Rechne, wo
ein anderer Nenner vertretbar wäre, **beide** Werte aus und stelle sie
nebeneinander.

**03 — Erfassungsmatrix.** Für jedes Eingabefeld jeder Maske: Wo landet der
Wert? Wer liest ihn? Was passiert, wenn er fehlt? **Und: reicht er, um die
Grösse zu bilden, die daraus gemacht wird — oder fehlt ein Feld, das die
Formel braucht?** Die letzte Frage hat diese Runde ausgelöst.

**07 — Praxisszenarien.** Fälle aus `ABLAUF.md`, als ausführbare Fixtures mit
**von Hand ausgerechnetem** Sollergebnis. Mindestens: Palette umgestapelt ·
Gebinde ohne Tara · zwei Paletten mit identischem Brutto · Charge halb erfasst
· Lieferung vor Erfassungsbeginn · Lieferung ohne Wareneingang · Palox geleert
· Palox unter Leergewicht · CSV doppelt · Koeffizient ohne Messung · gemischte
Charge · Sortierschema mitten in der Arbeit gewechselt · Restbestand über das
Saisonende. Für jeden: Was zeigt die App, und ist das ehrlich?

**08 — Leer ist nicht null.** Finde jede Stelle, an der `coalesce(…, 0)`,
`?? 0`, `|| 0` oder ein `left join` aus fehlendem Wissen eine Null macht, die
wie eine gemessene Null aussieht. Für jede: richtig oder verschwiegen?

**09 — Begriffe.** Bedeutet jedes Wort auf dem Bildschirm im Betrieb dasselbe
wie im Code? Der Zwei-Leser-Test, maschinell unterstützt: einmal als
Betriebsleiter lesen, der nur die Wörter sieht, einmal als Autor des Modells.
Wo die Lesarten auseinandergehen, ist ein Befund — **auch wenn die Zahl
stimmt**.

**10 — Annahmen.** Die rund zwanzig Zeilen aus `ABLAUF.md`, einzeln: Gilt sie
im Code noch? Wie gross ist der Fehler in Kilo, wenn sie nicht stimmt? Weiss
der Betriebsleiter davon, wenn er die betroffene Zahl ansieht? Wo eine Annahme
maschinell prüfbar ist, prüfe sie maschinell.

## 7. Phase II — Verstehen und Planen

Wenn das Prüfwerk gelaufen ist:

1. **Jeden Befund gegenlesen** (2.4). Was die Gegenrede übersteht, bleibt.
2. **Grösse ausrechnen** — in Kilo oder Prozentpunkten, auf den Demodaten und,
   wo es etwas ändert, auf einer halb verkauften Saison.
3. **Marke setzen** — Reparatur, Erweiterung oder Entscheidung des Betriebs.
4. **`docs/PRUEFBERICHT.md` schreiben.** Nach Wirkung sortiert, nicht nach
   Fundreihenfolge. Und mit einem Abschnitt, der ausdrücklich sagt, **was
   geprüft und für richtig befunden** wurde — eine Liste, die nur Mängel
   enthält, sagt nichts über die Abdeckung.
5. **Den Plan schreiben.** Reihenfolge nach `Wirkung × Sicherheit ÷ Risiko`,
   mit Abhängigkeiten (was muss vor was?) und mit einer ausdrücklichen Liste
   dessen, was auf eine Antwort des Betriebs wartet und deshalb **jetzt nicht**
   gebaut wird.
6. **Die Fragen an den Betrieb** — höchstens eine Seite, jede mit beiden
   ausgerechneten Zahlen und einer Empfehlung mit Begründung. Nicht „was
   möchten Sie?", sondern „so sieht es aus, ich würde X, weil Y —
   einverstanden?".

Und eine Selbstauskunft, die ich ernst nehme: **Welche Sonde hat wie viel
gefunden?** Eine Sonde ohne Fund ist entweder ein Beweis für Qualität oder ein
schwaches Werkzeug. Sag, welches von beidem, und woran du es festmachst.

## 8. Phase III — Abarbeiten

Nach dem Plan, von oben nach unten. Für jede Reparatur:

1. Erst der **Test, der ohne die Reparatur fehlschlägt** — sonst ist es keine
   Reparatur, sondern eine Behauptung.
2. Dann die Änderung, so klein wie möglich. Betrifft sie die Datenbank, wird
   sie eine Migration; `setup.sql` wird neu gebaut.
3. Dann das **ganze** Prüfwerk erneut: Der Befund muss weg sein und **kein
   neuer** entstanden.
4. Dann die Doku: `ABLAUF.md`, wo sich eine Annahme geändert hat,
   `ABMACHUNGEN.md` um eine neue Zusage, `ENTSCHEIDUNGEN.md` mit einem
   Abschnitt für diese Runde.

Nach jedem grösseren Block committen. Am Ende alle Prüfstände grün, und das
Prüfwerk als Teil des Bestands — es soll nächste Runde wieder laufen.

## 9. Kalibrierung: zwei Befunde, die der Betrieb selbst gefunden hat

Nicht dein Auftrag. Dein **Massstab** für die Tiefe.

### Befund A — Das Gewicht vom Zettel ohne Kisten

Beim Waschen + Sortieren fragt der Zähler (`src/arbeit/Zaehler.tsx`) je
Eingangspalette nach *Datum vom Zettel* und *Gewicht vom Zettel* und schreibt
`auftrag_palette.brutto_zettel_kg`. Nach **Kistenzahl** und **Gebindeart**
fragt er nicht. Das Netto ist aber

```
netto = Zettelgewicht − Palettengewicht − Kistenzahl × Kistengewicht(Gebindeart)
```

Die Wiegemaske (`src/arbeit/WiegenMaske.tsx`) fragt beides und rechnet genau
so. Die Zählmaske daneben nicht.

Das Backend behilft sich: `v_auftrag_palette_masse` sucht im Wareneingang eine
Palette mit gleicher Charge, gleichem Eingangsdatum **und** gleichem Brutto und
nimmt deren Netto (`masse_quelle = 'zettel'`); findet es keine, zieht es die
**mittlere Tara der Charge** ab (`'zettel-charge-tara'`).

Zu klären, bis zum Ende: Trägt die Näherung — wie viele Kilo daneben, wenn
eine Palette zwei Kisten weniger hat? Ist sie sichtbar? Die Auffälligkeit
„Zettelgewicht" prüft nur, ob *irgendeine* Palette der Charge dieses Gewicht
hat — ohne Datum, ohne bekanntes Netto. **Verdacht:** Fällt ein Fall
dazwischen, wird genähert, ohne dass es jemand erfährt. Und: An welche Palette
knüpft es an, wenn zwei dasselbe Gewicht haben?

### Befund B — Verlust in Prozent: Prozent wovon?

Überall steht „X % des Eingangs". Der Einwand des Betriebs:

> Will ich Prozent vom Eingangsgewicht wissen, oder lieber Prozent von
> Eingang − Ausgang, also von dem, was noch da ist? Denn was verkauft wurde,
> da wurde im Verkaufsschritt das Faule ja ohnehin schon aussortiert —
> vielleicht sogar, bevor es die App gab.

Der Einwand trifft das Muster, nicht eine Zahl. Die Kaskade rechnet zur
verkauften Ware die Eingangsmasse zurück (`m0 = geliefert ÷ verkaufsfähiger
Anteil`) und legt ihr denselben Verlust auf wie der liegenden. Das ist eine
**Modellannahme, keine Messung** — an dieser Ware hat niemand gewogen. Für
Ware vor dem Erfassungsbeginn ist es reine Rückrechnung. Und es ist eine Zahl,
an der der Betriebsleiter **nichts mehr ändern kann**, während der Verlust an
der liegenden Ware genau die Zahl ist, für die er morgens aufsteht.

Zu klären: beide Kennzahlen ausrechnen, den Unterschied beziffern, prüfen ob
die Trennung `portion ∈ {ausgelagert, lager}` dafür trägt — und **nicht selbst
entscheiden**, sondern vorlegen. Es kann gut sein, dass beide gehören: die eine
als Saisonbilanz, die andere als Handlungszahl.

## 10. Startverdacht — unbestätigt, unvollständig

Beim Lesen bin ich hier hängengeblieben. **Verdacht, nicht Befund**; manches
löst sich vermutlich auf. Prüfen ja — aber wer nur diese Liste abarbeitet, hat
den Auftrag nicht verstanden.

- `verkaufsfaehig_anteil` ist nach unten auf **0.25** geklammert. Was heisst
  das für eine wirklich schlechte Charge? Wird der Deckel je erreicht, und
  merkt es jemand?
- Die Verdunstungsrate kommt aus `brutto_damals` und `brutto_jetzt` — beide
  mit **derselben** Kistenzahl und Gebindeart. Umgestapelt = falsche Rate.
- `masse_quelle` unterscheidet sechs Stufen je Palette; auf dem Bildschirm
  erscheint nur die gröbere Quelle je Arbeit, als roher Datenbankwert in
  Klammern.
- Der Palox-Sockel a₀ wird nur gesetzt, wenn ein Test ihn belegt — sonst 0.
  „Nicht nachweisbar" und „null" sehen in der Summe gleich aus.
- Die Überfüllung je Kiste wird an gewogenen fertigen Paletten gemessen und
  auf alle verkauften Kisten der Sorte hochgerechnet.
- `a_klein_n = a_klein / max(a_klein + a_gross, 1)` — wann greift die
  Normierung, und was bedeutet sie dann?
- Welche Fehlerart aus Sonde 07 fällt durch **keine** der bestehenden
  Auffälligkeiten?

## 11. Werkzeuge

```bash
npm run pruefen                     # Typen, 76 Tests, Build — ohne Datenbank
./supabase/test/run.sh 'postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432'
node pruefstand/bildschirme.mjs     # jede Seite im echten Browser
node pruefstand/beschriftung.mjs    # sagt jede Zahl, was sie ist?
node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh '<url>'
./pruefstand/luecken.sh '<url>'     # Maske ↔ Auswertung, beide Richtungen
./pruefstand/demo_bauen.sh          # Datenbank mit Demodaten
./pruefstand/daten_dumpen.sh        # Fixtures für die Bildschirm-Prüfstände
./supabase/test/simulation/matrix.sh 25   # Simulationsmatrix, neun Lagen
./supabase/setup_bauen.sh           # nach jeder Änderung an migrations/
```

Postgres starten, falls sie nicht läuft:

```bash
mkdir -p /tmp/pgsock
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgdata -l /tmp/pg.log \
  -o '-k /tmp/pgsock -p 55432 -c listen_addresses=' start"
```

**Arbeite parallel.** Die teuren Sonden (06 Mutation, 05 Metamorph mit vielen
Zufallssaisons) startest du als Hintergrundläufe und liest weiter, während sie
arbeiten. Es ist Verschwendung, vor einem Fortschrittsbalken zu warten. Für
M2/M3 baust du eigene kleine Datenbanken — die Demodaten werden nicht
verbogen.

## 12. Feste Regeln

- Entwickeln und pushen **nur** auf `claude/new-session-vrnnyo`
  (`git push -u origin claude/new-session-vrnnyo`, bei Netzfehlern mit 2/4/8/16
  Sekunden erneut). **Keinen Pull Request** ohne ausdrückliche Bitte.
- Die echten Excel-Dateien unter `/root/.claude/uploads/` enthalten Kundennamen
  und Preise: lesen ja, **committen nie**.
- Keine Modellbezeichnung in Code, Commits, Kommentaren oder Dokumenten.
- Commits mit
  `git -c user.name="Alexander Konvalina" -c user.email="konvalina.alexander@gmail.com"`
  und dem Anhang:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  Claude-Session: <Session-Link>
  ```
- **Keinen Test abschalten, überspringen oder aufweichen**, um grün zu werden.
  Ein Test, der stört, hat entweder recht oder gehört mit Begründung
  korrigiert.
- Nichts löschen, worin Daten liegen: Ansichten, Funktionen, Oberflächen ja —
  Tabellen und Spalten nein.
- Datierte Stammdaten nie überschreiben, sondern fortschreiben.
- Kommentare erklären **warum**, nicht was. Deutsch, wie der übrige Code.

## 13. Woran ich messe, ob die Runde etwas wert war

1. **Das Prüfwerk läuft und findet etwas.** Ein grüner Lauf beim ersten Mal
   heisst: Die Sonden sind zu schwach. Bau sie schärfer.
2. **Mindestens fünfzehn Befunde, die auf keiner Liste von mir standen.** Die
   beiden aus Abschnitt 9 zählen nicht mit.
3. **Jeder Befund hat eine Grösse in Kilo oder Prozentpunkten.**
4. **Die App ist danach nicht komplizierter** — nicht mehr Felder, nicht mehr
   Bildschirme, nicht mehr Abhängigkeiten. Wo etwas wegfiel, sag warum.
5. **Alles Reparierte ist durch einen Test festgehalten**, der ohne die
   Reparatur fehlschlägt.
6. **Der Bericht ist in einfachem Deutsch**: Was hast du gesucht, wo geschaut,
   was gefunden, was repariert, was bleibt offen — und was muss **ich**
   entscheiden.

**Schreib nicht „alles in Ordnung".** Ein System dieser Grösse, über elf Runden (A–K)
gewachsen, hat Stellen, an denen die Rechnung von der Wirklichkeit abweicht.
Wenn du keine findest, hast du entweder nicht tief genug gegraben — oder du
kannst mir genau und überprüfbar sagen, warum es diesmal nicht mehr gab.
