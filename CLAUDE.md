# Für die nächste Runde am Programm

Dieses Repository ist die Kürbis-Verlust-App eines Schweizer Betriebs
(Supabase/Postgres, React, TypeScript). Wer daran arbeitet — Mensch oder
Werkzeug — beginnt so:

## 1. Zuerst lesen: was die Halle sagt, was die Auswertung findet

`docs/betrieb/` wird täglich vom Betriebsabzug geschrieben
(`.github/workflows/betrieb_abzug.yml`, `pruefstand/betrieb_abzug.mjs`).

1. **`docs/betrieb/RUECKMELDUNGEN.md`** — Rückmeldungen *zur App* sind
   Aufgaben: jede eine Zeile im Plan der Runde, mit dem Satz aus der Halle
   als Warum. Rückmeldungen *zur Ware* sind Befunde für den Betriebsleiter,
   keine Aufgaben — und sie stehen **erst dann** im Dashboard, wenn jemand
   sie gelesen, verstanden und gekürzt hat (0094). Das ist Arbeit der
   Runde: jede Nr. unter „noch nicht gekürzt" lesen, den Sinn auf das
   Wesentliche bringen („Hagelschaden", nicht die halbe Geschichte),
   prüfen, ob Charge und Arbeit stimmen, und einen Eintrag in
   **`docs/betrieb/kurzfassungen.json`** schreiben (`id`, `kurz`, bei
   Bedarf `charge_nr`, `art`, `auftrag_id`). Der Abzug spielt die Datei ein,
   sobald sie gepusht ist. Was der Betriebsleiter selbst gekürzt hat, bleibt
   — `ueberschreiben: true` nur, wenn er es gesagt hat. „Nur Aufnahme, kein
   Transkript" kann hier niemand hören: stehen lassen, der Betriebsleiter
   hört und kürzt. Transkripte sind ungeprüfte Spracherkennung, oft
   Hochdeutsch mit Mundart: den Sinn nehmen, nicht die Worte.
2. **`docs/betrieb/AUFFAELLIGKEITEN.md`** — je Art fragen: Wo im Ablauf oder
   in der Maske entsteht das? Ist es ein Datenfehler, der dem Betrieb gehört
   (fehlende Palette im Erntejournal, falsches Zetteldatum) — dann sagen,
   nicht reparieren. Oder eine Stelle, an der die App etwas erfinden,
   verschlucken oder unverständlich sagen konnte — dann ist es eine Aufgabe.
   Häuft sich eine Art, ist das die erste Aufgabe der Runde.
3. **`docs/betrieb/MODELLSTAND.md`** gegen **`docs/SAISONBEGLEITUNG.md`** —
   passen Verdunstung, Verderbskurve, Ausschussanteile, Ausbeute zu dem,
   was die Saison zeigen sollte? Wenn nicht: erst die Daten, dann die
   Annahme, zuletzt die Mathematik ändern — und jede Änderung in
   `docs/ENTSCHEIDUNGEN.md` begründen.
4. **`docs/HERLEITUNG.md`** — woher jede gerechnete Zahl ihre Eingaben
   nimmt und was gilt, wenn eine fehlt. Wer eine Kette ändert, ändert die
   Datei mit.
5. **`docs/betrieb/DURCHGANG.md`** und **`docs/betrieb/rohdaten/`** — der
   Plausibilitätsdurchgang über *alle* Rohdaten (`pruefstand/durchgang.mjs`,
   Regeln in `durchgang_pruefungen.mjs`): Teilpaletten, Gewicht je Kiste,
   doppelte Zeilen, Zeitfolgen, Lieferungen über dem Eingang, Zahlendreher.
   Jede Zeile ist ein Kandidat. Die Runde nimmt die Rohzeilen dazu, rechnet
   nach und schreibt **`docs/betrieb/ZWEITMEINUNG.md`** (datiert, ersetzt
   die vorige): zu jedem Kandidaten, was wohl passiert ist, wie sicher, was
   zu prüfen ist, ob eine Datenkorrektur (Betrieb) oder eine Regel
   (Programm) folgt — nach Wichtigkeit, mit Nummern, damit der
   Betriebsleiter es abarbeiten kann. Häuft sich eine Ursache, wird die
   Regel die erste Aufgabe. Ein Muster, das der Durchgang nicht kannte
   (Runde AC: Teilpalette von Hand, Zettel auf fremder Charge), bekommt
   seine Prüfung und ihren Test. Eine Grenze in `GRENZEN` ändert man nur
   mit Begründung in `docs/ENTSCHEIDUNGEN.md`.

## 2. Regeln, die immer gelten

- **Leer ist nicht null.** Eine fehlende Messung wird nie zu 0; ein
  Koeffizient ohne Messung ist unbekannt; jede Zahl sagt, woher sie kommt.
- **Nie eine Tabelle oder Spalte löschen.** Umdeuten, ergänzen, stehen
  lassen — nie wegnehmen.
- **Nie einen Test schwächen, um grün zu werden.** Ändert sich eine Regel,
  ändert sich der Test mit der Regel und sagt es im Kommentar.
- **Jede Migration hat einen Prüfblock** in `supabase/test/pruefung.sql`,
  und jede Behauptung darin wird gegengeprüft, indem man den geprüften Code
  absichtlich kaputtmacht (Mutation) und sieht, dass der Block anschlägt.
- **Keine neue Abhängigkeit** in `package.json`; keine Modellnamen von
  Werkzeugen im Quelltext, in Kommentaren, Commits oder Dokumenten.
- **Betriebsdaten bleiben draussen.** Kundennamen und Preise (die
  Warenausgangs-Dateien) werden gelesen, nie eingecheckt. Aufnahmen bleiben
  im Bucket; ihr Transkript darf in `docs/betrieb/`.
- **Deutsch, wie im Betrieb.** Commits sagen *warum*, nicht nur *was*;
  Masken sagen, was fehlt, statt zu erklären; Zahlen tragen ihre Einheit
  und ihre Herkunft (`pruefstand/beschriftung.mjs` prüft das).

## 3. Was vor jedem Push grün sein muss

Seit Runde AJ (29. September, Entscheid des Betriebs, `docs/ENTSCHLACKUNG.md`
§ 4) in zwei Stufen: schnell vor jedem Push, voll einmal am Tag.

**Vor jedem Push** (Minuten):

```
npx tsc -b && npm test
./supabase/setup_bauen.sh              # nach jeder Migration
psql '<url>' -f supabase/migrations/<neu>.sql && die Prüfblöcke der Runde mit ihren Mutationen
node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh '<url>'
node pruefstand/beschriftung.mjs
```

**Einmal am Tag, oder vor einem Push, der Bildschirme oder das Rechenwerk
breit ändert** (eine Stunde):

```
./supabase/test/run.sh '<url>'         # alle Prüfblöcke, setup.sql, Fingerabdruck, Lasttest
node pruefstand/bildschirme.mjs        # nach ./pruefstand/daten_dumpen.sh
node pruefstand/abnahme_r.mjs
```

Ist die volle Stufe rot, wird nichts weiter gepusht, bis sie grün ist.

Dazu: Abmachungen in `docs/ABMACHUNGEN.md` (AB-nn, mit dem Test, der sie
hält), Entscheidungen in `docs/ENTSCHEIDUNGEN.md` (eine Runde, ein
Abschnitt, mit „Was bewusst nicht gemacht wurde"), README nachziehen,
`SCHEMA_ERWARTET` in `src/lib/version.ts` = `schema_stand()`.
