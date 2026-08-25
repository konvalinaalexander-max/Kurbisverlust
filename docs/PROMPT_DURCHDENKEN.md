# Prompt: das Projekt noch einmal von vorne durchdenken

Diesen Text in einer neuen Sitzung einfügen.

---

Dieses Projekt schätzt, wo im Lager und in der Verarbeitung Kürbis-Masse
verloren geht. Es läuft, es ist statistisch überprüft, und die Zahlen tragen.
Trotzdem will ich es noch einmal von vorne durchdacht haben — nicht die Formeln,
sondern die Frage davor: **Passt das, was die Software abbildet, überhaupt zu
dem, was auf dem Betrieb wirklich passiert?**

Du bist nicht der Statistiker aus der letzten Runde. Du bist jemand, der
Abläufe versteht, Daten modelliert und Oberflächen baut — und der neu dazukommt.
Deine Aufgabe ist nicht, das Bestehende zu verteidigen. Sie ist, drei Fragen
sauber zu beantworten und daraus das fertige Produkt zu machen.

## Zuerst lesen

- `docs/SPEC.md` — die fachliche Spezifikation
- `docs/DATENFLUSS.md` — was erfasst, gerechnet, angezeigt wird
- `docs/ENTSCHEIDUNGEN.md` — bisherige Entscheidungen mit Begründung
- `docs/STATISTIK_BEFUND.md` — die letzte Überprüfung, ihre Befunde und Grenzen
- `supabase/migrations/` — das Schema in seiner Entstehung
- `src/pages/` — beide Oberflächen

`./supabase/test/run.sh` prüft die Datenbankseite, `npm run build` die App,
`./supabase/test/simulation/matrix.sh` misst Verzerrung und Überdeckung.

## Die drei Fragen

### 1. Was passiert tatsächlich auf dem Betrieb?

Schreib zuerst den echten Ablauf auf — **unabhängig davon, was heute gemessen
wird**. Von der Ernte bis zum Kunden. Nicht: „welche Tabellen gibt es". Sondern:
Was passiert physisch mit einem Kürbis, wer fasst ihn an, in welchem Behälter
liegt er, wann wechselt er den Behälter, und an welcher Stelle verlässt Masse
das System?

Die Spezifikation beschreibt zwei Wege (Maschine und Hand). Prüfe, ob das
Modell die Wirklichkeit trifft, und stell die unbequemen Fragen:

- **Identität.** Wann ist eine Palette dieselbe Palette? Nach dem Waschen
  entstehen neue Paletten aus alten — die Software weiss davon fast nichts.
  Was geht dabei verloren, das man später bräuchte?
- **Der Palox.** Faules wird gesammelt. Sammelt ein Palox über mehrere
  Arbeiten, über mehrere Tage, über mehrere Chargen? Was steht auf ihm drauf?
  Wann wird er geleert und von wem? Heute wird sein Inhalt *einer* Arbeit
  zugeschlagen — wenn das nicht stimmt, sitzt der Schimmel am falschen Alter.
- **Die Ränder.** Was passiert mit Ware, die weder verkauft noch Verlust ist:
  Hofladen, Direktverkauf, Tierfutter, Kompost, Eigenbedarf, Retouren,
  Reklamationen? Jeder dieser Wege ist Masse, die das System verlässt, ohne
  dass jemand sie bucht.
- **Zeit.** Was passiert zwischen zwei Saisons? Wann beginnt eine neue? Was
  wird mit Restbeständen der alten?
- **Menschen.** Wer entscheidet, welche Palette als nächstes drankommt, und
  wonach? (Die letzte Überprüfung hat gezeigt: Wenn nach Aussehen ausgewählt
  wird, verzerrt das die Schimmelkurve. Frag nach, wie es tatsächlich läuft.)

Wo das Modell etwas über den Ablauf *annimmt*, was niemand geprüft hat, schreib
es als Annahme hin. Annahmen sind erlaubt — unmarkierte Annahmen nicht.

### 2. Lässt sich das korrekt in der Datenbank hinterlegen?

Nimm den echten Ablauf aus Frage 1 und halte das Schema daneben. Gesucht sind
die Stellen, an denen die Datenbank den Arbeiter zwingt, etwas Falsches oder
Ungenaues einzutragen, weil es kein Feld für die Wahrheit gibt.

- Wo erzwingt das Schema eine Zuordnung, die es in Wirklichkeit nicht gibt?
- Wo ist „nicht gemessen" nicht von „gemessen und null" zu unterscheiden?
- Wo geht Information verloren, die man später bräuchte, und wo speichern wir
  Information, die nie jemand liest?
- Was ist der **kleinste** Satz an Angaben, mit dem sich die Massenbilanz
  wirklich schliessen lässt — Eingang minus Ausgang minus Verlust gleich
  Lagerbestand?

Ein Punkt ist dabei schon geklärt und muss umgesetzt werden, siehe unten:
**der Warenausgang fehlt vollständig.**

Ändere das Schema, wo es nötig ist — als neue Migrationen, mit Prüfabfragen in
`supabase/test/pruefung.sql`. Aber ändere es nicht aus Ordnungsliebe: Jede
Änderung muss eine Frage beantworten, die der Betriebsleiter tatsächlich hat.

### 3. Was sieht der Arbeiter, und was sieht der Betriebsleiter?

Zwei Oberflächen, zwei völlig verschiedene Aufgaben.

**Der Arbeiter** kommt per QR-Code herein, tippt seinen Namen, fertig — kein
Konto, kein Passwort. Er spricht vielleicht Deutsch, Englisch, Ungarisch,
Rumänisch, Polnisch oder Portugiesisch. Er steht an der Maschine, hat
schmutzige Hände und wenig Geduld.

> Jede unnötige Schwierigkeit führt dazu, dass es nicht gemacht wird.

Das ist die härteste Randbedingung im ganzen Projekt. Ein Feld mehr kostet
Erfassungsdisziplin, und schlecht erfasste Daten sind schlimmer als fehlende,
weil man ihnen glaubt. Frag bei jedem Eingabefeld: Muss der Mensch das wissen,
oder kann die Software es herleiten? Kann Tippen durch Auswählen ersetzt
werden? Was passiert, wenn er sich vertippt — merkt er es, kann er es
zurücknehmen? Erklärender Text gehört **nie** in die Arbeiter-Ansicht.

**Der Betriebsleiter** will zwei Dinge, und die widersprechen sich nur
scheinbar.

*Erstens:* auf einen Blick verstehen, wo die Masse bleibt. Klar, ruhig,
visuell. Eine Grafik, die die Kaskade zeigt — was kommt herein, was geht wo
verloren, was bleibt verkaufsfähig. Er soll in zehn Sekunden wissen, welche
Ursache die grösste ist und ob sich das gegenüber letzter Woche geändert hat.

*Zweitens:* sich in den Daten verlieren dürfen. Wenn er wissen will, warum da
19 Tonnen stehen, muss er sich durchklicken können bis zu den einzelnen
Messungen, aus denen die 19 Tonnen entstanden sind.

Und das ist der Punkt, auf den es mir am meisten ankommt:

> **Du bist keine Blackbox.** Es darf nie eine Zahl geben, bei der nicht
> erkennbar ist, wie du darauf gekommen bist.

Jede angezeigte Grösse braucht einen Weg zurück: aus welchen Messungen, mit
welcher Rechnung, mit welcher Unsicherheit, und wie viel davon ist gemessen
und wie viel hochgerechnet. Wo die Daten eine Aussage nicht hergeben, soll dort
stehen, dass sie es nicht hergeben — nicht eine Zahl, die so aussieht wie die
anderen.

Überleg dabei neu, was der Betriebsleiter überhaupt wissen *will*. Nicht nur,
was sich rechnen lässt. Ein paar Fragen, die er vermutlich hat und auf die
heute keine Antwort steht:

- Welche Sorte hält sich am besten, welche am schlechtesten?
- Ab wann kippt eine Charge — wie lange kann ich sie noch liegen lassen?
- Welche Charge sollte ich als nächstes verarbeiten?
- Was hat mich das gekostet — in Kilo, und wenn ich einen Preis hinterlege,
  in Franken?
- Was wäre anders, wenn ich früher verarbeitet hätte?

Prüfe, welche davon die Daten hergeben. Bau die, die tragen. Sag klar, welche
nicht gehen und was dafür fehlen würde.

## Was schon geklärt ist — nicht neu aufrollen

**Die Statistik.** Die letzte Runde hat Verlaufsmodell, Fehlerfortpflanzung,
chargen-robuste Fehler und Teilbündelung eingeführt, jeweils mit gemessener
Verzerrung und Überdeckung (`docs/STATISTIK_BEFUND.md`). Bestehendes darf sich
ändern, aber nicht stillschweigend: Wenn eine Zahl danach anders ist, weise
nach, warum die neue richtiger ist — mit dem Harness, nicht mit einem Argument.
`matrix.sh` muss mindestens so gut bleiben, wie es ist.

**Zwei offene Punkte von dort, die du mitnehmen sollst:**

*Der Warenausgang fehlt.* Er ist in Spec §188 ausdrücklich als Gegenprobe
vorgesehen und nie gebaut worden. Der Betrieb weiss, welche Aufträge herausgehen,
kennt aber **nicht** die tatsächlichen Gewichte der einzelnen Paletten. Das ist
auch nicht nötig: Je Lieferung genügen Datum, Sorte und entweder Kilo oder
Anzahl Kisten — Zahlen, die ohnehin auf dem Lieferschein stehen, weil danach
verrechnet wird. Kisten lassen sich über das gemessene Kilo je Kiste umrechnen;
die zusätzliche Unsicherheit trägt die Fehlerfortpflanzung mit. Selbst eine
grobe Monatssumme je Sorte wäre ein Gewinn: Erst damit hört der Restbestand auf,
eine reine Projektion zu sein, und die Lücke in der Bilanz wird zur einzigen
Zahl, die misst, was das Modell übersieht. Überleg, wie das mit dem geringsten
Aufwand hereinkommt — es gibt bereits eine Google-Sheets-Anbindung.

*Die Dubletten-Regel* ist unbelegt und wird vom Betrieb später selbst geprüft
(Handzählung einer Palette, Spec §13). `v_dubletten_pruefung` rechnet sie aus,
sobald echte CSV-Dateien da sind. Nicht weiter verfolgen, nur nicht kaputt
machen.

## Frag, statt zu raten

Zum Ablauf auf dem Betrieb bin **ich** die einzige Quelle. Wenn du etwas nicht
weisst, erfinde es nicht und bau auch nicht vorsorglich für alle Fälle.

Sammle deine offenen Fragen und stell sie mir **gebündelt und konkret** —
lieber acht scharfe Fragen als vierzig vage. Zu jeder Frage: warum du sie
stellst und was davon abhängt. Alles, was ohne meine Antwort weitergehen kann,
machst du in der Zwischenzeit fertig.

## Was ich am Ende haben will

1. **Das Prozessbild** — der echte Ablauf, aufgeschrieben, mit den Stellen
   markiert, an denen das Modell etwas annimmt.
2. **Die Lücken** zwischen Ablauf, Datenbank und Oberfläche, sortiert danach,
   wie stark sie das Ergebnis verfälschen — nicht danach, wie leicht sie zu
   schliessen sind.
3. **Die Umsetzung**: neue Migrationen, geänderte Oberflächen, Prüfungen in
   `pruefung.sql`. Fertig, nicht als Vorschlag.
4. **Beide Ebenen im Betriebsleiter-UI**: die klare Übersicht mit Grafik, und
   darunter der Weg von jeder Zahl bis zu den Messungen, aus denen sie kommt.
5. **Die Fragenliste** an mich, gebündelt.

## Regeln

- **Ziel ist Ursachen rangieren, nicht kg-genau bilanzieren** (Spec §9). Eine
  Verbesserung, die die Rangfolge nicht sicherer macht, ist keine.
- Die zwei Bücher bleiben getrennt: physischer Verlust und verschenkte Marge
  werden nie vermischt.
- Alles läuft auf der Supabase- und Cloudflare-Gratis-Stufe. Das Dashboard
  liest gespeicherte Ansichten; Rechenzeit gehört ins Neuberechnen, nicht ins
  Anschauen. Der Lasttest in `run.sh` muss grün bleiben.
- Grafiken von Hand als SVG. Keine Diagramm-Bibliothek — das Bündel ist schon
  507 kB, und eine Abhängigkeit mehr ist eine Abhängigkeit, die in fünf Jahren
  nicht mehr baut.
- Sechs Sprachen im Arbeiter-UI, vollständig. `TextId` erzwingt das.
- Deutsche Bezeichner, Kommentare erklären das *Warum*, nicht das *Was*.
- Am Ende müssen `./supabase/test/run.sh` und `npm run build` grün sein und
  die Arbeit committet und gepusht.
