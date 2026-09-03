# Prompt: die ganze Kette noch einmal durchdenken, prüfen und schärfen

Diesen Text in einer neuen Sitzung einfügen.

---

Dieses Projekt schätzt aus lückenhaften Stichproben, wo bei Lagerung und Verarbeitung
von Kürbissen Masse verloren geht. Es läuft, es ist statistisch überprüft, und es hat
bereits zwei gründliche Überarbeitungen hinter sich.

**Deine Aufgabe ist Feinschliff, nicht Neubau.** Wirf das Projekt nicht um. Nimm es als
das, was es ist — ein weit gediehenes Werkzeug mit dokumentierten Entscheidungen — und
denke die Kette vom Anfang bis zum Ende noch einmal unvoreingenommen durch. Wo etwas
nicht zusammenpasst, änderst du es. Wo es passt, lässt du es stehen und sagst warum.

Nimm dir dafür wirklich Zeit. Denke tief, rechne nach, teste, verwirf. Arbeite
selbstständig: Du musst nicht bei jedem Schritt fragen — sammle deine Fragen und stelle
sie gebündelt, wenn du wirklich nicht weiterkommst, und arbeite in der Zwischenzeit an
allem weiter, was ohne die Antworten geht.

## Zuerst lesen — und zwar vollständig

- `docs/SPEC.md` — die ursprüngliche fachliche Spezifikation
- `docs/ABLAUF.md` — der Ablauf auf dem Betrieb, mit markierten Annahmen
- `docs/ENTSCHEIDUNGEN.md` — jede bisherige Modellentscheidung mit Begründung
- `docs/STATISTIK_BEFUND.md` — zwei Runden statistischer Überprüfung, mit Messwerten
- `docs/DATENFLUSS.md` — was erfasst, gerechnet, angezeigt wird
- `supabase/migrations/` — 31 Migrationen, chronologisch, jede mit Begründung im Kopf
- `src/pages/`, `src/components/`, `src/lib/` — beide Oberflächen

Werkzeuge, die es schon gibt und die du benutzen sollst:

```
./supabase/test/run.sh                    # Datenbank: Migrationen, Fachlogik, Lasttest
./supabase/test/simulation/matrix.sh 20   # Verzerrung und Überdeckung über alle Lagen
./supabase/test/simulation/lauf.sh …      # eine einzelne Lage
npm run build                             # Frontend
```

## Die vier Denkschritte

Arbeite sie in dieser Reihenfolge ab. Jeder baut auf dem vorigen auf, und der vierte
schickt dich unter Umständen zurück zum ersten.

### 1. Was passiert tatsächlich auf dem Hof?

Nicht: welche Tabellen gibt es. Sondern: Was passiert physisch mit einem Kürbis, von der
Ernte bis zum Kunden? Welche Arbeitsschritte gibt es, was bedeutet jeder einzelne, wer
fasst die Ware an, in welchem Behälter liegt sie, wann wechselt sie den Behälter, und an
welcher Stelle verlässt Masse das System?

Schreibe diesen Ablauf für dich auf, bevor du irgendetwas anfasst. Jede Stelle, an der
das bestehende Modell etwas über den Ablauf *annimmt*, gehört ausdrücklich markiert.
`docs/ABLAUF.md` hat damit angefangen — prüfe jede dort genannte Annahme neu, statt sie
zu übernehmen.

### 2. Was will der Betriebsleiter wissen?

Nicht: was lässt sich rechnen. Sondern: Welche Fragen stellt sich jemand, der diesen
Betrieb führt, und welche davon geben die Daten her?

Denke breit. Beispiele, die vermutlich zählen — die Liste ist nicht vollständig und
nicht verbindlich:

- Welche Ursache kostet mich am meisten? (das ist die Kernfrage, Spec §9)
- Welche Sorte hält sich am besten, welche am schlechtesten?
- Ab wann kippt eine Charge — wie lange kann ich sie noch liegen lassen?
- Welche Charge sollte ich als nächstes verarbeiten?
- Was hat mich das gekostet, in Kilo und in Franken?
- Was wäre anders, wenn ich früher verarbeitet hätte?
- Wo fehlen mir Messungen, und was würde eine zusätzliche bringen?

Sortiere: Welche Fragen tragen die Daten heute? Welche könnten sie tragen, wenn eine
Kleinigkeit mehr erfasst würde? Welche gehen grundsätzlich nicht, und warum?

### 3. Wie kommt man an diese Informationen?

Für jede Frage aus Schritt 2: Welche Messung führt darauf? Wo im Ablauf ist der
**beste Messpunkt** — die Stelle, an der die Zahl am genauesten, am billigsten und am
zuverlässigsten anfällt?

Beachte dabei: Eine Messung ist nur so gut wie die Stelle, an der sie entsteht. Eine
Zahl, die der Arbeiter schätzen muss, ist schlechter als eine, die eine Waage liefert.
Eine Zahl, die er im Kopf ausrechnen muss, ist schlechter als eine, die er abliest.

### 4. Passt das zur Praxis?

Jetzt der Realitätsabgleich. Für jeden Messpunkt aus Schritt 3:

- Kann der Arbeiter das an dieser Stelle überhaupt wissen?
- Hat er die Hände frei? Steht dort eine Waage? Ist der Behälter noch identifizierbar?
- Wie oft geht es schief, und merkt es dann jemand?
- Was kostet es ihn an Zeit und Aufmerksamkeit?

**Die härteste Randbedingung im Projekt:** Jede unnötige Schwierigkeit führt dazu, dass
gar nicht erfasst wird — und schlecht erfasste Daten sind schlimmer als fehlende, weil
man ihnen glaubt. Ein Feld mehr auf einer Maske ist eine Entscheidung, keine Kleinigkeit.

Wo Schritt 4 einen Messpunkt aus Schritt 3 kippt, geh zurück und suche einen anderen.

## Was der Betrieb korrigiert hat — das ist verbindlich

Zwei Dinge sind in der letzten Sitzung ausdrücklich richtiggestellt worden. Beide sind
im Code noch nicht sauber gelöst:

**Der Palox steht auf einer Waage.** Der Arbeiter liest den Stand ab, die Software
bildet die Differenz zum letzten Mal. Das Problem: Die Software weiss nicht, wie viel
Zeit und wie viele Arbeiten seit der letzten Ablesung vergangen sind, und sie merkt
nicht, wenn der Palox zwischendurch geleert wurde. Eine Differenz, die zwei Arbeiten
umfasst, wird einer einzigen zugeschlagen. Überlege, was zusätzlich erfasst oder
abgeleitet werden muss, damit die Menge der richtigen Arbeit zufällt — der Betrieb hat
angedeutet, dass sich die Palettenzahl der Arbeit dabei als Prüfgrösse nutzen liesse.

**Es gibt kein First-in-first-out.** Nach dem Sortieren kommt die Ware wieder ins Lager
und wird von dort **ziemlich zufällig** wieder herausgenommen — nicht in der
Reihenfolge, in der sie hineinkam. Ein FIFO-Ansatz war bereits gebaut und wurde nach
Messung wieder entfernt (`docs/STATISTIK_BEFUND.md`); die jetzige Notlösung mittelt über
alle vorherigen Sortierläufe derselben Charge. Prüfe, ob das unter zufälliger Entnahme
das Richtige ist, und ob es besser geht, ohne dem Arbeiter Arbeit aufzubürden.

## Fragen, die noch offen sind

Diese sind dem Betrieb gestellt, aber noch nicht beantwortet. **Rate nicht.** Baue so,
dass beide Antworten funktionieren, und stelle die Fragen am Ende gebündelt — knapp,
konkret, mit dem, was davon abhängt.

1. Steht an der Sortiermaschine eine Palettenwaage? (Wenn ja, wäre das die beste
   Verdunstungsquelle überhaupt — heute wird dort nie gewogen.)
2. Kann der Arbeiter beim Waschen die verarbeitete Menge in Kilo angeben, oder zählt er
   eher Kisten?
3. Was passiert physisch mit „zu klein"? Weggeworfen, Kompost, Tierfutter? Wenn es
   Ertrag bringt, ist es kein Totalverlust und gehört ins andere Buch.
4. Was ist „zu gross" für ein Kanal, und was bringt er?
5. Werden die Kaliber-Kisten so gewaschen, wie sie sind, oder wird umgepackt?
6. Gibt es auf dem Maschinen-Weg auch fertig gepackte Paletten, oder wird nach Stück
   verkauft?
7. Kann eine Charge am selben Tag über beide Linien laufen?
8. Wird beim Waschen nach Charge getrennt gearbeitet, oder laufen mehrere Chargen
   gemischt durchs Becken?
9. In welcher Einheit steht die Menge auf dem Lieferschein — Kilo oder Kisten?
10. Welche Wege verlässt Kürbis sonst noch den Betrieb (Hofladen, Tierfutter, Kompost,
    Eigenbedarf)?

Ausserdem eine bekannte Lücke, die niemand gemeldet hat, sondern die beim Durchgehen
auffiel: Die empfohlene **Lagerkontrolle** — gelegentlich eine zufällig gegriffene
Palette im Lager aufmachen und den faulen Anteil notieren — kann die Datenbank
speichern, aber es gibt **keinen Bildschirm dafür**. Wiegen geht heute nur innerhalb
einer Arbeit. Das gehört gelöst; die Messung ist statistisch die wertvollste im ganzen
System (siehe `docs/STATISTIK_BEFUND.md`).

## Backend: freie Hand, aber begründet

Am Datenmodell, an den SQL-Ansichten, an der Mathematik hast du **freie Hand**. Der
Betriebsleiter versteht diesen Teil nicht und will ihn nicht verstehen müssen — er muss
schlicht stimmen.

Freie Hand heisst nicht beliebig. Es heisst: Ändere, was der Sache dient, und schreibe
in den Kopf jeder Migration, *warum*. Der bestehende Stil — deutsche Bezeichner,
Kommentare erklären das Warum und nicht das Was — wird fortgeführt.

Denk dabei besonders über diese Dinge nach:

- **Bildet die Mathematik ab, was physisch passiert?** Die Kaskade rechnet Verdunstung,
  dann Schimmel, dann Ausschuss. Stimmt diese Reihenfolge mit der Realität überein?
  Stimmen die Bezugsmassen? Wird irgendwo etwas doppelt oder gar nicht gezählt?
- **Sind die Unsicherheiten ehrlich?** Ein Bereich, der 95 % heissen soll, muss in rund
  95 % der Fälle treffen. Das ist messbar, und es wird gemessen.
- **Ist irgendwo eine Zahl, die aussieht wie eine Messung, aber eine Annahme ist?**
- **Was passiert bei dünner Datenlage?** Am Saisonanfang, bei einer Sorte ohne
  Stichprobe, bei einer Charge ohne CSV. Fällt das System dann auf etwas Ehrliches
  zurück oder erfindet es Sicherheit?

## Testen: nicht nur Code, sondern Mathematik

Das ist der Teil, bei dem du dir am meisten Zeit nehmen sollst.

**Der Code muss laufen** — `./supabase/test/run.sh` und `npm run build` müssen grün
sein, der Lasttest inbegriffen.

**Aber viel wichtiger: die Mathematik muss stimmen.** Dafür gibt es den
Simulations-Harness in `supabase/test/simulation/`. Er erzeugt synthetische Saisons,
deren wahre Koeffizienten du selbst setzt, lässt die ganze Pipeline darüber laufen und
misst zwei Dinge:

- **Verzerrung** — liegt die Schätzung systematisch daneben?
- **Überdeckung** — enthält der ausgewiesene 95-%-Bereich den wahren Wert wirklich in
  95 % der Fälle?

Nutze ihn hart. Erweitere ihn, wo er die Wirklichkeit noch nicht abbildet — er ist
zweimal erweitert worden, weil er einen Teil des Ablaufs nicht kannte, und beide Male
hat er danach echte Fehler gefunden. Fahre viele Lagen durch, nicht nur die bequemen:

- Saisonanfang, Saisonmitte, Saisonende
- zufällige Verarbeitungsreihenfolge und „Schlechtes zuerst"
- viele und sehr wenige Messungen
- Sorten ohne eigene Stichprobe, Chargen ohne CSV
- fehlende Tara, Tippfehler, abgebrochene Aufträge
- ein Betrieb, der beide Linien gleichzeitig fährt

**Die Regel, an der sich alles misst:** Behaupte keine Schwäche, die du nicht gezeigt
hast, und keine Verbesserung, die du nicht gemessen hast. Wenn eine Zahl nach deiner
Änderung anders ist, weise nach, warum die neue richtiger ist — mit dem Harness, nicht
mit einem Argument. Es ist ausdrücklich in Ordnung und sogar erwünscht, einen Ansatz zu
bauen, zu messen, dass er schadet, und ihn wieder wegzuwerfen. Das ist bereits dreimal
passiert und steht dokumentiert.

## Die Oberfläche: zwei Ebenen, keine Blackbox

**Der Arbeiter** kommt per QR-Code herein, tippt seinen Namen, fertig. Sechs Sprachen.
Schmutzige Hände, wenig Geduld. Erklärender Text gehört hier nie hin.

**Der Betriebsleiter** braucht zwei Dinge, die sich nur scheinbar widersprechen:

*Erstens* auf einen Blick verstehen, wo die Masse bleibt — klar, ruhig, visuell. In zehn
Sekunden wissen, welche Ursache die grösste ist.

*Zweitens* sich in den Daten verlieren dürfen. Wenn er wissen will, warum da 19 Tonnen
stehen, muss er sich durchklicken können bis zu den einzelnen Messungen, aus denen die
19 Tonnen entstanden sind.

> **Es darf nie eine Zahl geben, bei der nicht erkennbar ist, wie sie zustande kam.**

Jede angezeigte Grösse braucht einen Weg zurück: aus welchen Messungen, mit welcher
Rechnung, mit welcher Unsicherheit, wie viel davon gemessen und wie viel hochgerechnet.
Wo die Daten eine Aussage nicht hergeben, muss dort stehen, dass sie es nicht hergeben —
nicht eine Zahl, die aussieht wie die anderen.

## Randbedingungen, die bleiben

- **Ziel ist Ursachen rangieren, nicht kg-genau bilanzieren.** Eine Verbesserung, die die
  Rangfolge nicht sicherer macht, ist keine.
- Die zwei Bücher bleiben getrennt: physischer Verlust und verschenkte Marge werden nie
  vermischt.
- Alles läuft auf der Supabase- und Cloudflare-Gratis-Stufe. Das Dashboard liest
  gespeicherte Ansichten; Rechenzeit gehört ins Neuberechnen, nicht ins Anschauen. Der
  Lasttest muss grün bleiben.
- Grafiken von Hand als SVG. Keine Diagramm-Bibliothek.
- Sechs Sprachen im Arbeiter-UI, vollständig. `TextId` erzwingt das.
- Deutsche Bezeichner, Kommentare erklären das *Warum*.

## Was du am Ende lieferst

**Erst die Arbeit, dann die Erklärung.** Programmiere, teste, miss, verwirf, committe
und pushe die neue Fassung. Und *danach*, ganz zum Schluss, schreibst du hier im Chat
die Erklärung.

Diese Erklärung ist kein Änderungsprotokoll. Sie ist die Darstellung deines
**Verständnisses**, damit sich prüfen lässt, ob wir dasselbe sehen. Sie hat drei Teile:

### Teil 1 — Der Betrieb

Wie läuft es ab? Welche Arbeitsschritte gibt es und was bedeutet jeder? Was passiert mit
der Ware, Behälter für Behälter? An welcher Stelle verschwindet Masse? Welche
Informationen will der Betriebsleiter, und woher kommen sie? Schreibe das so, wie du es
verstanden hast — auch die Stellen, bei denen du dir nicht sicher bist, ausdrücklich als
solche markiert.

### Teil 2 — Die Oberfläche

Wie ist die App aufgebaut? Was sieht der Arbeiter, an welcher Stelle, und was gibt er
ein? Was sieht der Betriebsleiter, auf welcher Ebene? Wann wird welche Zahl abgefragt,
und warum genau dort?

### Teil 3 — Was dahinter steckt

Die Informatik, die Daten, die Mathematik. Und hier die wichtigste Anforderung an die
Sprache:

**Genau so tief wie die Wirklichkeit, aber verständlich für einen Laien.** Der Leser ist
klug und will alle Informationen — aber er ist kein Informatiker und kein Statistiker.
Vereinfache nicht die Sache, vereinfache die Sprache. Wenn du eine Weibull-Verteilung
anpasst, dann sag, was das ist und warum gerade die, und nicht „ein statistisches
Modell". Wenn ein Standardfehler chargen-robust geschätzt wird, dann erkläre, warum
zwölf Chargen nicht dasselbe sind wie dreihundert Messungen. Nimm dir Zeit dafür,
benutze Bilder und Vergleiche, und lass nichts weg, nur weil es kompliziert ist.

Am Ende der Erklärung: deine gebündelten offenen Fragen an den Betrieb.
