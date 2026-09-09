# Hypothesenbuch — was schiefgehen könnte, bevor das Werkzeug läuft

Geschrieben nach dem Lesen von `ABLAUF.md`, `ABMACHUNGEN.md`, `FRAGEN.md`,
`DATENFLUSS.md`, `ENTSCHEIDUNGEN.md`, `setup.sql` (Teil B) und den Masken —
**vor** dem ersten Lauf des Prüfwerks. Der Sinn: eigene Vermutungen aufstellen,
statt eine fremde Liste abzuhaken. Jede Zeile ist ein Satz der Form

> Wenn ⟨Umstand⟩, dann wäre ⟨Zahl⟩ falsch, und man merkt es an ⟨Beobachtung⟩.

Am Ende jeder Zeile steht die Sonde, die sie beantwortet. Keine bleibt offen:
bestätigt, widerlegt oder „nicht entscheidbar, weil …" — nachgetragen in
`pruefwerk/befunde/hypothesen_stand.md`.

---

## Herkunft und Beschriftung (Sonde 01)

**H01** Wenn die Gebinde-Tara einer Kistenart fehlt, ist `v_palette.netto_kg`
NULL, und `sum(netto_kg)` überspringt die Palette. Dann ist „Eingang" kleiner
als die Wirklichkeit — trägt aber die Marke **gemessen**, als wäre die Liste
vollständig. Merkbar an: Eingang einer Charge < Summe der Bruttos minus
plausibler Tara. → 01, 08

**H02** „Ausgeliefert" enthält `vorlauf_kg` — die grobe Angabe des Betriebs,
was vor dem Erfassungsbeginn schon rausging. Das ist eine **Schätzung**, keine
Lieferschein-Messung, trägt aber dieselbe Marke wie die Lieferscheine.
Merkbar an: die Abstammung von `vorlauf_kg` endet in `charge_vorlauf`, einer
Eingabetabelle ohne Beleg. → 01

**H03** „Verlust bis heute" enthält Ströme, deren Koeffizient aus **anderen
Sorten** gepoolt ist (`basis = 'alle Sorten (zu wenige eigene Chargen)'`). Die
Zahl ist dann eine Übertragung, nicht eine Messung dieser Charge — auf dem
Überblick steht davon nichts. → 01, 09

**H04** „Noch im Haus" ist `coalesce(k.im_haus_heute_kg, b.eingang_kg)`: Fehlt
die Kaskadenzeile ganz, wird **der volle Eingang** als „noch im Haus"
ausgegeben und mit der Marke *gerechnet* versehen. Richtig wäre „unbekannt".
Merkbar an: Charge ohne Kaskade zeigt im Haus = Eingang, Verlust = leer. → 01, 08

**H05** Eine Zahl, deren Abstammung eine Näherung enthält
(`zettel-charge-tara`, mittlere Palettenmasse, gepoolter Koeffizient), trägt
auf dem Bildschirm nichts davon. → 01

## Bezugsgrössen (Sonde 02)

**H06** „Verlust — X % des Eingangs" beantwortet eine andere Frage als die, die
der Betriebsleiter stellt. Der Nenner enthält Ware, die längst verkauft ist und
an der niemand mehr etwas ändern kann. → 02 *(Befund des Betriebs, Kalibrierung)*

**H07** Der Anteilsbalken normiert je Zeile auf deren Eingang. Eine Charge mit
Überzählung kann Ströme haben, die zusammen **über 100 %** ihres Eingangs
ergeben. Wird das gedeckelt, abgeschnitten oder läuft der Balken über? → 02

**H08** Zwei Chargen mit derselben gelieferten Masse bekommen verschiedene
„Eingangsmasse dahinter", weil `verkaufsfaehig_anteil` von den Koeffizienten
abhängt. Eine Charge **ohne jede Messung** hat alle Koeffizienten 0, also
Anteil 1, also m0 = geliefert — und damit **null Verlust an verkaufter Ware**.
Eine gut gemessene Charge sieht dadurch schlechter aus. → 02, 04

**H09** Der Verdunstungs-Koeffizient ist eine **Tagesrate**. Steht er irgendwo
als Prozent ohne „je Tag", liest ihn jeder um den Faktor Lagerdauer falsch. → 02, 09

**H10** In der Kaliber-Tabelle steht „Anteil der Stück" neben „Gewogene Masse".
Stückanteil und Massenanteil sind verschieden; nebeneinander verwechselt man
sie. Ist der Unterschied benannt? → 02, 09

## Erfassung → Auswertung (Sonde 03)

**H11** Der Zähler fragt beim Waschen + Sortieren nach dem Gewicht vom Zettel,
aber **nicht nach Kisten und Gebindeart** — beides bräuchte die Netto-Formel.
→ 03 *(Befund des Betriebs, Kalibrierung)*

**H12** `verdunstung_wiegung.kuerbisse_pro_kiste` ist freiwillig. Liest es
irgendjemand? Wenn nein, ist es ein Feld, das Arbeitszeit kostet und nichts
trägt. → 03

**H13** `auftrag.tage_seit_waschen` (Fax, freiwillig) — dasselbe. → 03

**H14** `verdunstung_wiegung.sichtbar_schimmel` filtert `verwendbar`. Seit
Runde H fragt die Maske „Faules sichtbar" **nicht mehr**. Wird die Spalte noch
irgendwo gesetzt? Wenn nie, ist der Filter tot und verschimmelte Paletten
gehen in die Verdunstungsrate ein. → 03, 08

**H15** `bemerkung` an `schimmel_messung` und `ausschuss_messung`: geschrieben,
aber gelesen? → 03

**H16** Beim Waschen ist die Masse `Kisten × gemessenes Kistengewicht`. Fehlt
das Kistengewicht der Sorte, ist die Masse unbekannt. Wird die Arbeit dann
**still ohne Nenner** gerechnet, oder fällt sie auf? → 03, 08

**H17** Die Lagerkontrolle und die Verarbeitungswägung schreiben in dieselbe
Tabelle. Wenn die Auswertung sie nicht sauber trennt (`quelle`), fliesst eine
zufällig gegriffene Palette in dieselbe Kurve wie eine ausgewählte — genau die
Vermengung, gegen die die Kontrolle erfunden wurde. → 03, 04

## Das Orakel: rechnet das SQL, was die Doku sagt? (Sonde 04)

**H18** Die Doku sagt `Anteil(t) = a₀ + (1−a₀)·F(t)`. Die Kaskade rechnet
`sockel = m1·a₀` und `schimmel = m1·(1−a₀)·f`. Zusammen `m1·(a₀+(1−a₀)f)` —
stimmt. Aber die **Messung**, an der F(t) angepasst wird, ist der ganze
Palox-Inhalt. Wird beim Anpassen a₀ herausgerechnet, oder steckt es doppelt
drin? → 04

**H19** Für `portion = 'ausgelagert'` muss gelten: `verkaufsfaehig_kg =
geliefert_kg` — denn m0 wurde genau so zurückgerechnet. Greift aber der Deckel
`greatest(…, 0.25)`, stimmt die Gleichung **nicht mehr**, und die Differenz
taucht nirgends auf. → 04, 05

**H20** Der Fax-Koeffizient wird gemessen als *Faules ÷ Masse der Fax-Arbeit*.
Angewandt wird er auf `m2·(1−klein−gross)`. Sind das dieselben Bezugsmassen?
Wenn die Fax-Arbeit ihre Masse aus `Paletten × mittlere Palettenmasse` schätzt,
ist der Nenner der Messung eine Schätzung — der Koeffizient erbt deren Fehler. → 04

**H21** Der Ausschuss-Koeffizient kommt aus der Sortier-CSV, also von **nach**
dem Palox (Faules ist schon raus). Angewandt wird er auf m2, also auch nach
Schimmel. Konsistent — aber gilt das auch für die **Handmessung** beim Waschen
+ Sortieren, die vor dem Waschen genommen wird? → 04

**H22** Die Verdunstung wird auf `m0` der Portion `ausgelagert` angewandt, und
`m0` wurde durch Division durch einen Anteil gewonnen, der `(1−r)^t` schon
enthält. Rechnerisch hebt sich das auf. Prüfen, dass es sich **exakt** aufhebt
und nicht nur ungefähr. → 04, 05

**H23** `alter_tage` der Portion `ausgelagert` ist massegewichtet über die
Bücher. Die Doku sagt „Alter am Liefertag". Bei mehreren Lieferungen aus einer
Kohorte ist der Mittelwert nicht dasselbe wie die Summe der Einzelalterungen,
weil der Verderb beschleunigt. Wie gross ist der Unterschied? → 04

## Metamorphe Beziehungen (Sonde 05)

**H24** Alle Massen mal zehn → alle Kilo mal zehn, alle Prozente unverändert.
Bricht das, hängt irgendwo eine absolute Schwelle in einer Formel. → 05

**H25** Je Portion muss gelten: Verdunstung + Sockel + Schimmel + klein +
Nebenkanal + Fax + verkaufsfähig = m0. → 05

**H26** Summe über Sorten = Summe über Schläge = Summe über Chargen = Gesamt,
in `erg_verlust`. → 05

**H27** `auswertung_aktualisieren()` zweimal → identische Zahlen. → 05

**H28** `heute()` einen Tag später → keine „bis heute"-Zahl wird kleiner. → 05

**H29** Koeffizient ohne Messung → Ergebnis **leer**, nie 0. **Verdacht:**
`mv_kaskade.verdunstung_kg` ist bei unbekanntem r schlicht 0 (weil
`coalesce(kv.mittel, 0)`), und `v_hochrechnung_basis` summiert diese 0 in
`verlust_heute_kg`. Die Kennzahl ist dann **zu klein statt leer** — `verlust_bekannt`
sagt es zwar, aber die Zahl selbst lügt. → 05, 08

**H30** Dieselbe Sortier-CSV zweimal eingelesen → keine Zahl ändert sich. → 05, 07

**H31** Zeilen in anderer Einfügereihenfolge → identisches Ergebnis. → 05

**H32** Eine Palette einen Tag früher eingelagert → Alter +1, sonst nichts. → 05

## Mutation: wie stark sind die Tests? (Sonde 06)

**H33** `1 - f` → `f` in der Kaskade fällt keinem Test auf. → 06

**H34** Der Deckel `0.25` auf `0.9` verschoben fällt keinem Test auf. → 06

**H35** `where datum <= heute()` bei den Lieferungen entfernt — das war ein
Rechenfehler aus Runde I; greift der Test, der ihn festhält? → 06

**H36** Vertauschen von `a_klein_n` und `a_gross_n` fällt keinem Test auf
(beide gehen in denselben Buch `marge`). → 06

**H37** `palox_tara_kg` um 10 % verschoben fällt keinem Test auf. → 06

## Praxisfälle (Sonde 07)

**H38** Zwei Paletten derselben Charge mit **identischem** Bruttogewicht: an
welche knüpft `v_auftrag_palette_masse` an, und ist das egal? → 07

**H39** Ein Zettelgewicht, zu dem es eine Palette gleichen Gewichts, aber
**anderen Eingangsdatums** gibt: die Massenrechnung fällt auf die mittlere Tara
zurück, die Auffälligkeit „Zettelgewicht" feuert aber **nicht** (sie prüft ohne
Datum). Genähert, ohne dass es jemand erfährt. → 07, 03

**H40** Eine Lieferung ins Buch `verlust` (Kompost) zählt in `ausgang_kg`, aber
`v_lieferung_kohorte` nimmt nur `verkauf` und `marge`. Dann verlässt die Ware
den Betrieb, verschwindet aber weder aus dem Bestand noch taucht sie als
Verlust auf. **Die Bilanzgleichung müsste das zeigen.** → 07, 05

**H41** Eine Charge, deren Wareneingang nur zur Hälfte erfasst ist: Überzählung
oder stille Verzerrung? → 07

**H42** Palox-Stand fällt (geleert) → Menge unbekannt. Wird sie unbekannt, oder
wird eine negative Menge zu 0? → 07, 08

**H43** Restbestand über das Saisonende hinaus: `stichtag()` liegt in der
Vergangenheit — was macht `(stichtag − eingangsdatum)` dann? → 07

## Leer ist nicht null (Sonde 08)

**H44** Jede `coalesce(…, 0)`-Stelle in der Kaskade macht aus Unwissen eine
gemessene Null. Wie viele davon sind richtig? → 08

**H45** `greatest(…, 0)` an den Massen versteckt negative Zwischenergebnisse —
ein Vorzeichenfehler würde still zu 0 statt aufzufallen. → 08

## Begriffe (Sonde 09)

**H46** „Ausgeliefert" (Lieferschein-Masse) und „Ausgelagert" (zurückgerechnete
Eingangsmasse) klingen im Betrieb gleich und sind verschieden. Stehen sie
irgendwo nebeneinander ohne Unterscheidung? → 09

**H47** Die Doku sagt, der Fax-Strom erscheine „als Palox (Faules) neben dem
Palox der Waschstrasse". Auf dem Bildschirm heisst er „Faul beim Abpacken
(Fax)". Eine der beiden Stellen ist veraltet. → 09, 10

**H48** `masse_quelle` erscheint auf der Chargen-Seite als roher
Datenbankwert in Klammern — englisch-technisch statt deutsch. → 09

## Annahmen (Sonde 10)

**H49** Jede der zwanzig Zeilen der Annahmen-Tabelle: Gilt sie im Code noch,
wie gross ist der Fehler in Kilo, und weiss der Betriebsleiter davon? → 10

**H50** Die neue Zeile „Eine Palette hat bei der Wägung dieselbe Kistenzahl wie
beim Eingang": Wie oft wird umgestapelt, und wie stark schlägt es durch? → 10, 07
