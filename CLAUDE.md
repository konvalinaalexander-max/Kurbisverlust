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
   keine Aufgaben — sie stehen im Dashboard an den Messungen.
   Transkripte sind ungeprüfte Spracherkennung, oft Hochdeutsch mit
   Mundart: den Sinn nehmen, nicht die Worte.
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

```
npx tsc -b && npm test
./supabase/setup_bauen.sh              # nach jeder Migration
./supabase/test/run.sh '<url>'         # Migrationen, setup.sql, Fingerabdruck, Lasttest
node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh '<url>'
node pruefstand/bildschirme.mjs        # nach ./pruefstand/daten_dumpen.sh
node pruefstand/beschriftung.mjs
node pruefstand/abnahme_r.mjs
```

Dazu: Abmachungen in `docs/ABMACHUNGEN.md` (AB-nn, mit dem Test, der sie
hält), Entscheidungen in `docs/ENTSCHEIDUNGEN.md` (eine Runde, ein
Abschnitt, mit „Was bewusst nicht gemacht wurde"), README nachziehen,
`SCHEMA_ERWARTET` in `src/lib/version.ts` = `schema_stand()`.
