# Prompt: den vereinbarten Ablauf wirklich bauen — und beweisen, dass keine Lücke bleibt

Diesen Text in einer neuen Sitzung einfügen.

---

Dieses Projekt schätzt aus lückenhaften Stichproben, **wo** bei Lagerung und Verarbeitung von
Kürbissen Masse verloren geht und **welche Ursache dominiert**. Die Rechnung dahinter ist in
vier Runden geprüft und belegt. Die **Erfassung** ist es nicht.

**Dein Auftrag: Was mit dem Betrieb abgemacht wurde, muss die App auch fragen, speichern und
verrechnen — und du musst es beweisen können.**

Bei einer Durchsicht am 3. September ist aufgefallen, dass eine ganze Reihe bestätigter
Absprachen zwar in `docs/ABLAUF.md` steht, aber nie in die Masken gekommen ist. Die Dokumente
wurden zum Protokoll der Absicht, die App blieb dahinter zurück. Genau diese Art von Lücke
sollst du schliessen — und danach unmöglich machen.

Die Prüfstände dieses Projekts testen bisher, ob die App das Richtige **rechnet**. Sie testen
nicht, ob sie das **fragt**, was besprochen wurde. Das ist die Lücke hinter der Lücke.

## Zuerst lesen, und zwar vollständig

- `docs/ABLAUF.md` — was auf dem Betrieb passiert und was der Betrieb bestätigt hat.
  Die Abschnitte „Was sonst bestätigt wurde" und „Was der Betrieb bestätigt hat (1. September)"
  sind deine Arbeitsliste.
- `docs/FRAGEN.md` — was offen ist und was inzwischen beantwortet wurde
- `docs/ENTSCHEIDUNGEN.md` — jede Modellentscheidung mit Begründung
- `docs/STATISTIK_BEFUND.md` — was die Messungen ergeben haben
- `docs/SPEC.md`, `docs/Datenarchitektur.pdf` (bzw. `docs/architektur.html`)
- `README.md`, Abschnitt „Tests"

## Die Regeln, nach denen hier gearbeitet wird

1. **Gespeichert wird, was beobachtet wurde — nie, was gefolgert wurde.** Der Waagenstand wird
   gespeichert, die Menge ist Ableitung. Die gezählte Kiste wird gespeichert, ihr Gewicht ist
   Ableitung.
2. **Leer ist nicht null.** Eine fehlende Messung ist NULL oder gar keine Zeile. Eine Null ist
   eine Aussage über die Welt, eine Lücke ist keine.
3. **Kontext muss datiert sein.** Regeln, nach denen gearbeitet wurde (Sortierschema, Tara,
   Sollgewichte), werden nie überschrieben — es kommt eine neue Fassung dazu, und jede Arbeit
   hält fest, nach welcher Fassung sie lief.
4. **Nichts glauben, was nicht gemessen ist.** Behauptest du, etwas sei besser, zeig die Zahl
   vorher und nachher.
5. **Keine erfundenen Zahlen.** Lieber „nicht gemessen" im Dashboard als ein plausibler Wert
   ohne Grundlage.
6. **Kosten bleiben bei null.** Supabase-Gratisstufe, 8-Sekunden-Grenze je Abfrage; der
   Lasttest in `run.sh` prüft das.

## Bevor du anfängst: zwei Fragen stellen

Diese beiden blockieren Punkt 1 und 2 der Arbeitsliste. Stelle sie **sofort**, arbeite in der
Zwischenzeit an allem weiter, was ohne die Antworten geht.

1. **Beim Waschen, wenn die Charge als „Kiste ab x kg" sortiert wurde:** Stehen dort Kisten
   **ohne** Kaliber, also alle gleich? Dann braucht die Kisten-Maske beim Waschen den Fall
   „eine Sorte Kisten, kein Kaliber" statt einer Kaliberauswahl.
2. **Beim Sortieren an der Maschine:** Kann dieselbe Sorte für denselben Käufer am selben Tag
   einmal nach Kaliber und einmal als Kiste laufen? Falls ja, muss der Eindeutigkeits-Index
   über `sortierschema` um `art` erweitert werden.

Alle weiteren Fragen sammelst du und stellst sie gebündelt am Schluss.

## Die Arbeitsliste — jede Zeile ist eine bestätigte Absprache, die fehlt

Reihenfolge nach Wirkung auf die Zahlen. Belege bei jeder Zeile, dass sie erledigt ist.

| # | Was abgemacht wurde | Quelle | Warum es die Zahlen trifft |
|---|---|---|---|
| 1 | **Sortierschema beim Auftragsstart bestätigen**, mit der Möglichkeit, es vor Ort zu ändern („Wie sortiert ihr? Kiste ab x kg / Kaliber") | ABLAUF, 1. Sept | Die CSV wird nach der gespeicherten Fassung klassiert. Stimmt sie nicht, wandert alles unter der Kaliber-Untergrenze fälschlich in „Zu klein (Tierfutter)" — ein ganzer Balken aus einer Regel, die an dem Tag nicht galt. Bei „Kaliber" darf **keine** Überfüllung gerechnet werden; heute wird eine erfunden. |
| 2 | **Palox ablesen bei Beginn und Abschluss** einer Arbeit | ABLAUF, 2. Sept | Darauf ruht die ganze Palox-Rechnung (ein Behälter je Station, keine Kennung, Menge = Differenz zweier Stände). Heute gibt es nur einen Reiter, den man öffnen kann oder auch nicht. Fehlt eine Ablesung, landet die Menge zweier Arbeiten auf einer. |
| 3 | **Ausschuss wiegen statt schätzen**: auf Palette stellen, **Kistenzahl und Gewicht** erfassen | ABLAUF, 1. Sept | `ausschuss_messung` hat heute nur `kg` nach Augenmass. Daraus kommen zwei Ströme in Buch B. |
| 4 | **Geführter Abschluss** statt Reiter: während der Arbeit nur zählen (und gelegentlich wiegen), alles andere beim Abschliessen | ABLAUF, 1. Sept | Was man vergessen kann, wird vergessen. Der Abschluss ist die Stelle, an der die Vollständigkeit erzwingbar ist. |
| 5 | Beim Start fragen: **„Sind die Paletten für zu gross und zu klein leer?"**, beim Eintragen: **„Alles von diesem Auftrag?"** | ABLAUF, 2. Sept | Ausschuss-Paletten sollen je Auftrag neu angefangen werden. Sonst trägt eine Arbeit den Ausschuss der vorigen mit. |
| 6 | **Chargennummer eintippen** statt aus einer Liste wählen | ABLAUF, 1. Sept | Ausdrücklich gewünscht, „geht schneller". Heute ist es eine Auswahlliste. |
| 7 | **Erfassungsbeginn** und je Charge eine grobe Angabe, **was vor der App schon rausging** | ABLAUF, 1. Sept | Die Saison lief bereits, als die App kam. Ohne diese Angabe behauptet die Massenbilanz eine Lücke, die keine ist. |
| 8 | **Fax als eigener Auftragstyp** (eigener Arbeitsgang nach Bestellung; tagsüber wird provisorisch vorgewaschen) | ABLAUF, 2. Sept | Heute gibt es drei Tätigkeiten, Fax ist keine. Diese Arbeiten werden falsch einsortiert oder gar nicht erfasst. |
| 9 | **Lagerkontrolle: festhalten, dass die Palette „eine zufällige unter den heute erreichbaren" war** | ABLAUF, 2. Sept | Das Lager ist gestapelt, man kommt nicht an jede Palette. Die Auswahl ist damit nicht frei von Verzerrung — aber sie ist wenigstens bekannt, wenn sie erfasst wird. |
| 10 | **Hinweis in der Palox-Maske: „Gewicht direkt von der Waage ablesen"** | ABLAUF, 2. Sept | Die Waage zeigt brutto. Wer im Kopf umrechnet, liefert eine gefolgerte Zahl. |
| 11 | **Import für Fremddateien** (Perigon-Warenausgang): Rohdatei unverändert ablegen, an einer Prüfsumme wiedererkennen, erneuter Import derselben Datei folgenlos | ABLAUF, 2. Sept | Wartet auf die Dateivorlage. Bau die Aufnahme so weit, wie es ohne die Vorlage geht, und sag, was fehlt. |

Findest du beim Lesen weitere Absprachen, die nicht in der App sind, gehören sie in dieselbe
Liste. Die Tabelle oben ist der Stand einer Durchsicht, kein Beweis für Vollständigkeit.

## Was du bauen sollst, damit so etwas nicht wieder passiert

Das ist der eigentliche Auftrag. Die elf Punkte sind Arbeit; das hier ist der Grund, warum es
danach hält.

### 1. `docs/ABMACHUNGEN.md` — die Absprachen als prüfbare Liste

Jede Absprache mit dem Betrieb bekommt eine feste Kennung (`AB-01`, `AB-02`, …), den Wortlaut,
das Datum, die Quelle — und **den Namen des Tests, der sie beweist**. Eine Zeile ohne Test gilt
als offen, egal wie fertig der Code aussieht. Trage die elf Punkte oben ein und alles, was du
sonst in `ABLAUF.md` und `FRAGEN.md` an bestätigten Absprachen findest.

### 2. Die Kette vollständig, für jede Tätigkeit

`pruefstand/kette.mjs` fährt heute **eine** Arbeit über die Masken und spielt die
mitgeschnittenen Schreibanfragen in eine echte Postgres ein (`pruefstand/kette_pruefen.sh`).
Das bleibt der richtige Ansatz — er ist nur zu schmal.

Erweitere ihn zu **je einem vollständigen Durchlauf pro Tätigkeit** (Sortieren, Waschen,
Waschen + Sortieren, Fax). In jedem Durchlauf wird **jedes** Eingabefeld ausgefüllt, das ein
Arbeiter ausfüllen kann. Danach prüfst du für **jeden einzelnen eingegebenen Wert**, dass er
in der Auswertung ankommt — mit Einheit, Bezugsmasse und Vorzeichen. Nicht stichprobenartig.

### 3. Ein Lückenscanner, der von selbst meckert

Von Hand geschriebene Tests finden nur, woran jemand gedacht hat. Bau deshalb eine Prüfung,
die die Lücke selbst sucht und bei jedem `run.sh` läuft:

- **Vorwärts:** Jede Spalte der Erfassungstabellen, die ein Arbeiter füllen soll, muss von
  mindestens einer mitgeschnittenen Schreibanfrage getroffen werden. Was nie getroffen wird,
  ist entweder überflüssig oder aus der App nicht erreichbar — beides meldet die Prüfung
  namentlich. Führe die wenigen echten Ausnahmen als ausdrückliche Liste mit Begründung,
  nicht als stilles Übergehen.
- **Rückwärts:** Jede Zahl, die das Dashboard zeigt, muss sich auf mindestens einen
  mitgeschnittenen Wert zurückführen lassen. Findet sich keiner, ist die Zahl entweder
  erfunden oder ihre Erfassung fehlt.
- **Beides zusammen** ist die Zusage, um die es geht: zwischen Maske und Auswertung steht
  nichts mehr, was nur in einer Richtung existiert.

### 4. Der Abschluss muss die Vollständigkeit erzwingen

Prüfe im Browser, dass eine Arbeit sich **nicht** abschliessen lässt, solange etwas
Vereinbartes fehlt (Palox-Ablesung, Ausschuss-Angaben, die Fragen aus Punkt 5). Ein Test, der
nur den glücklichen Weg abfährt, beweist nichts über den Alltag in der Halle.

### 5. Alles in `run.sh`

Neue Prüfungen, die man von Hand starten muss, werden nicht gestartet. `run.sh` muss alles
umfassen, und die CI (`.github/workflows/pruefung.yml`) muss es fahren.

## Was am Ende dastehen muss

- Alle Suiten grün, mit ausgegebenem Ergebnis: `./supabase/test/run.sh`, `npm test`,
  `npx tsc --noEmit`, `npm run build`, `node pruefstand/bildschirme.mjs`,
  `node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh`
- Die Simulationsmatrix **vorher und nachher** (`./supabase/test/simulation/matrix.sh 25`) mit
  dem Nachweis, dass sich an Verzerrung und Überdeckung nichts verschlechtert hat. Diese Runde
  ändert die Erfassung, nicht das Modell — die Zahlen müssen also stehen bleiben.
- `docs/ABMACHUNGEN.md` vollständig, jede Zeile mit ihrem Test
- `supabase/setup.sql` neu gebaut (`./supabase/setup_bauen.sh`) und auf einer **bestehenden**
  Datenbank getestet, nicht nur auf einer leeren
- `docs/ABLAUF.md`, `docs/ENTSCHEIDUNGEN.md`, `docs/FRAGEN.md`, `README.md` nachgezogen
- Demo-Saison so erweitert, dass die neuen Erfassungen darin vorkommen — sonst zeigen die
  Bildschirme leere Masken
- Alles committet und gepusht
- Ein Schlussbericht im Chat, für jemanden ohne Statistikkenntnisse, in vier Teilen:
  **Was gefehlt hat · Was jetzt erfasst wird · Was geprüft ist und wie · Was offen bleibt**

## Wie du arbeiten sollst

- **Führe den Code aus, lies ihn nicht nur.** Lokale Postgres aufsetzen, `setup.sql`
  einspielen, Demo laden, Bildschirme rendern, Bilder anschauen. Die schwersten Fehler dieses
  Projekts waren unsichtbar, solange niemand hingeschaut hat.
- **Erst die Messung, dann die Änderung.** Kannst du eine Lücke nicht sichtbar machen, bau
  zuerst das, was sie sichtbar macht.
- **Kleine Schritte, jeder geprüft.** Nach jedem Punkt der Arbeitsliste die Suiten laufen
  lassen, nicht am Schluss alles auf einmal.
- Arbeite selbstständig, frag nicht bei jedem Schritt — ausser bei den zwei Fragen ganz oben.

## Was du nicht tun sollst

- Keinen Test abschalten, überspringen oder aufweichen, damit etwas grün wird
- Keine Zahl schönen und keine Lücke mit einem plausiblen Wert füllen
- Keine stillen Annahmen: was du annimmst, kommt in die Annahmen-Tabelle in `ABLAUF.md`
- Nichts löschen, worin Daten stehen
- Das Modell nicht umbauen — diese Runde gilt der Erfassung. Fällt dir am Modell etwas auf,
  schreib es auf und lass es liegen.
- Keine Absprache als erledigt melden, für die es keinen Test gibt

## Werkzeuge und Umgebung

```bash
# Datenbank: sieben Stufen, inkl. Aktualisierung von altem Stand und Lasttest
./supabase/test/run.sh 'postgresql://…'

# Statistik: Saisons mit bekannter Wahrheit, misst Verzerrung und Überdeckung
./supabase/test/simulation/matrix.sh 25

# Bildschirme: jede Seite im echten Browser (Handy/Desktop, hell/dunkel)
./pruefstand/daten_dumpen.sh 'postgresql://…'   # Fixtures aus der Demo-Datenbank
node pruefstand/bildschirme.mjs

# Die Kette in beide Richtungen
node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh 'postgresql://…'

npm test && npx tsc --noEmit && npm run build
./supabase/setup_bauen.sh        # nach jeder Änderung an supabase/migrations/
```

```bash
# Postgres 16 ist da, muss aber als Benutzer "postgres" laufen (nicht als root)
mkdir -p /tmp/pgdata /tmp/pgsock && chown -R postgres:postgres /tmp/pgdata /tmp/pgsock
su postgres -c "/usr/lib/postgresql/16/bin/initdb -D /tmp/pgdata -U postgres --auth=trust -E UTF8 --locale=C"
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgdata -o '-k /tmp/pgsock -p 55432 -c listen_addresses=' -l /tmp/pg.log start"
URL='postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432'

# Chromium liegt fertig unter /opt/pw-browsers/chromium (kein playwright install nötig)
# Für den Bildschirm-Prüfstand braucht .env.local:
#   VITE_SUPABASE_URL=http://localhost:5199
#   VITE_SUPABASE_ANON_KEY=sb_publishable_pruefstand_000000000000
```

**Eine Falle aus der letzten Runde, damit du nicht hineintappst:** Der Rumpf einer SQL-Funktion
wird beim Einsetzen mit dem Suchpfad der aufrufenden Sitzung aufgelöst. Nenne in
Funktionsrümpfen Tabellen **und Typen** immer mit `public.` davor, oder setz der Funktion einen
festen Suchpfad. `psql` hat `public` im Pfad, der SQL-Editor des Anbieters nicht — deshalb lief
ein Fehler dieser Art monatelang durch jeden lokalen Testlauf und schlug erst beim Betrieb zu.
