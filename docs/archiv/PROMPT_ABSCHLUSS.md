# Prompt: das ganze Projekt aus der Vogelperspektive ansehen — und endlich fertig machen

Diesen Text in einer neuen Sitzung einfügen.

---

Dieses Projekt schätzt aus bewusst lückenhaften Stichproben, **wo** bei Lagerung
und Verarbeitung von Kürbissen Masse verloren geht und **welche Ursache
dominiert**. Es ist über mehrere Runden gewachsen: eine statistische Prüfung des
Modells, eine Neugestaltung der Oberfläche, eine Runde, die die Erfassung an die
Absprachen des Betriebs angeglichen hat. Es läuft, es ist getestet, es ist dicht
dokumentiert.

**Jetzt sollst du es abschliessen.** Nicht eine weitere Teilprüfung — den
Abschluss. Ich will am Ende ein fertiges Produkt: eine App, die ein
landwirtschaftlicher Betrieb in der Halle benutzt, mit einer Oberfläche, die
modern und ruhig aussieht und keine Formatierungsfehler hat, mit einem Backend
und einer Mathematik, die zusammenpassen, und ohne Ballast, den niemand mehr
braucht.

Du bekommst dafür einen weiten Rahmen. Wie du vorgehst, entscheidest du. Schöpf
deine Intelligenz aus. Aber halte dich an die Reihenfolge unten: **erst
verstehen, dann aufräumen, dann fertig bauen.**

## Setz dich mit allem auseinander, was da ist

Bevor du irgendetwas änderst, verschaff dir einen echten Überblick — aus der
Vogelperspektive, nicht Datei für Datei.

- **Der ganze bisherige Verlauf.** Der Chat, in dem dieses Projekt und die
  letzten Runden entstanden sind, gehört dazu. Lies, was besprochen, entschieden
  und offengelassen wurde. Vieles von dem, was ich wirklich will, steht dort und
  nicht im Code.
- **Die Dokumente**, alle: `docs/SPEC.md`, `docs/ABLAUF.md`, `docs/DATENFLUSS.md`,
  `docs/ENTSCHEIDUNGEN.md`, `docs/STATISTIK_BEFUND.md`, `docs/ABMACHUNGEN.md`,
  `docs/FRAGEN.md`, `README.md`. Auch die früheren Prompt-Dateien
  (`docs/PROMPT_*.md`) — sie zeigen, was in jeder Runde das Ziel war.
- **Der Code**: `supabase/migrations/` (das Schema in seiner Entstehung, bis
  0047), `supabase/setup.sql` (die zusammengefügte Fassung), `src/` (beide
  Oberflächen, Arbeiter und Betriebsleiter), `pruefstand/` und `supabase/test/`
  (die ganze Prüfmaschinerie).
- **Die Werkzeuge**, die es schon gibt — und was sie kosten:
  - `./supabase/test/run.sh` — sieben Stufen plus Lückenscanner
  - `./supabase/test/simulation/matrix.sh` — Verzerrung und Überdeckung
  - `node pruefstand/bildschirme.mjs` — jede Seite im echten Browser
  - `node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh` — die Kette
    über die echten Masken, in beide Richtungen
  - `./pruefstand/luecken.sh` — kein Loch zwischen Maske und Auswertung
  - `npm test`, `npx tsc --noEmit`, `npm run build`

**Führe sie aus, lies sie nicht nur.** Setz eine lokale Postgres auf, spiel
`setup.sql` ein, lade die Demo, render die Bildschirme, sieh dir die Bilder an.
Die schwersten Fehler dieses Projekts waren unsichtbar, solange niemand
hingeschaut hat.

Schreib mir am Ende dieses ersten Durchgangs **kurz**, wie du das Projekt
vorgefunden hast: was trägt, was wackelt, was zu viel ist.

## Dann: was ist zu viel? Was braucht es nicht mehr?

Das Projekt ist über viele Runden gewachsen, und Wachstum hinterlässt Ballast.
Geh es mit der Frage durch, was **weg** kann, ohne dass etwas verloren geht:

- Prüfungen, Skripte oder Views, die sich überschneiden oder nichts mehr
  absichern.
- Tote Pfade: Tabellen, die niemand mehr schreibt (der Lückenscanner kennt
  `marge_messung` als so einen Fall — geh dem nach), Spalten, die keine Maske
  füllt, Funktionen, die niemand ruft.
- Dokumente, die sich widersprechen oder überholt sind. Elf Prompt-Dateien
  brauchen am Ende vielleicht niemand mehr.
- Doppelte oder umständliche Stellen im Frontend.

Wegwerfen ist eine Änderung wie jede andere: **erst belegen, dass es wirklich
ungenutzt ist, dann entfernen, dann prüfen, dass alles grün bleibt.** Nichts
löschen, worin Daten stehen. Was du entfernst, begründest du kurz in
`ENTSCHEIDUNGEN.md`.

## Dann: mach es fertig — so, wie es ein fertiges Produkt verlangt

Jetzt hast du freie Hand. Bring das Projekt in den Zustand, in dem ich es
ausliefern würde. Wo es nötig ist, fasst du an:

- **Die Oberfläche.** Sie soll modern und ruhig aussehen und **keine
  Formatierungsfehler** haben — auf dem Handy des Arbeiters (schmal, gross,
  berührungstauglich) und auf dem Desktop des Betriebsleiters (dicht, aber
  aufgeräumt), in hell und dunkel, in allen sechs Sprachen. Der
  Bildschirm-Prüfstand rendert 88+ Screenshots und meldet Konsolenfehler und
  wagrechtes Überlaufen — nutz ihn als dein Auge, aber sieh dir die Bilder auch
  wirklich an. „Schön" heisst hier: eine Akzentfarbe, klare Hierarchie, ruhige
  Tabellen, nichts Verrutschtes, nichts Abgeschnittenes.
- **Das Backend und die Mathematik.** Wo Erfassung, Rechnung und Anzeige nicht
  sauber zusammenpassen, richtest du es. Aber das Modell ist in vier Runden
  gemessen und belegt — wenn du daran gehst, dann mit demselben Massstab: zeig an
  der Simulation die Zahl vorher und nachher, sonst lass es. Eine Verbesserung,
  die man nicht messen kann, ist keine.
- **Die Statistik.** Wenn dir an den Bereichen, der Überdeckung oder der
  Fehlerfortpflanzung etwas auffällt, das nachweisbar besser geht, mach es —
  wieder mit der Matrix als Beweis.

Was das Modell nicht neu erfinden heisst: Die Massenkaskade, das Verderbsmodell
(Weibull, chargen-robust), der Palox-Sockel und die drei Bücher (Lagerverlust,
Feld, Marge) sind das Ergebnis gemessener Entscheidungen. Bau sie nur um, wenn
die Messung dich dazu zwingt.

## Die Regeln, die immer gelten

1. **Gespeichert wird, was beobachtet wurde — nie, was gefolgert wurde.** Der
   Waagenstand wird gespeichert, die Menge ist Ableitung.
2. **Leer ist nicht null.** Eine fehlende Messung ist NULL oder gar keine Zeile.
3. **Nichts glauben, was nicht gemessen ist.** Behauptest du, etwas sei besser,
   zeig die Zahl vorher und nachher.
4. **Kosten bleiben bei null.** Supabase-Gratisstufe, 8-Sekunden-Grenze je
   Abfrage; der Lasttest in `run.sh` prüft das.
5. **Keine Prüfung abschalten, um grün zu werden.** Nichts schönen, keine Lücke
   mit einem plausiblen Wert füllen.

## Arbeite selbstständig

Frag nicht bei jedem Schritt. Sammle die Fragen, die wirklich nur der Betrieb
beantworten kann (in `FRAGEN.md` stehen die offenen, darunter der Perigon-Import
und die direkte Sockel-Messung beim Leeren des Palox), und stelle sie **gebündelt
am Schluss** — arbeite in der Zwischenzeit an allem weiter, was ohne die
Antworten geht. Geh in kleinen, je geprüften Schritten vor; nicht am Ende alles
auf einmal.

## Was am Ende dastehen muss

- Alle Suiten grün, mit ausgegebenem Ergebnis: `./supabase/test/run.sh`,
  `npm test`, `npx tsc --noEmit`, `npm run build`,
  `node pruefstand/bildschirme.mjs`,
  `node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh`.
- Die Simulationsmatrix vorher/nachher, mit dem Nachweis, dass sich an
  Verzerrung und Überdeckung nichts verschlechtert hat (`matrix.sh 25`).
- `supabase/setup.sql` neu gebaut (`./supabase/setup_bauen.sh`) und auf einer
  **bestehenden** Datenbank getestet, nicht nur auf einer leeren.
- Die Oberfläche in allen Ansichten ohne Konsolenfehler und ohne Überlauf, in
  hell und dunkel.
- Die Dokumente auf dem Stand des fertigen Produkts — und um das erleichtert,
  was niemand mehr braucht.
- Alles committet und gepusht.
- Ein Schlussbericht im Chat, für jemanden ohne Statistikkenntnisse: **wie du
  das Projekt vorgefunden hast · was du entfernt hast und warum · was du fertig
  gebaut oder verbessert hast · was geprüft ist und wie · was offen bleibt.**

## Umgebung, damit du keine Zeit verlierst

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

./supabase/setup_bauen.sh        # nach jeder Änderung an supabase/migrations/
```

**Eine Falle, damit du nicht hineintappst:** Der Rumpf einer SQL-Funktion wird
beim Einsetzen mit dem Suchpfad der aufrufenden Sitzung aufgelöst. Nenne in
Funktionsrümpfen Tabellen **und Typen** immer mit `public.` davor, oder setz der
Funktion einen festen Suchpfad. `psql` hat `public` im Pfad, der SQL-Editor des
Anbieters nicht — deshalb lief ein Fehler dieser Art monatelang durch jeden
lokalen Testlauf und schlug erst beim Betrieb zu.
