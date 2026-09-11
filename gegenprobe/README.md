# Gegenprobe — die zweite, unabhängige Rechnung

Runde N prüft die App nicht mit den Werkzeugen, die die App gebaut hat. Die
Prüfstände, das Prüfwerk und die Werkstätten der Runden L und M messen alle
**dasselbe System mit dessen eigenen Begriffen**: Sie lesen die Sichten, die
sie prüfen, und rechnen mit den Funktionen, die sie prüfen. Was dort falsch
ist, ist auf beiden Seiten falsch und fällt nicht auf.

Die Gegenprobe rechnet jede Zahl **ein zweites Mal, in einer anderen Sprache,
aus den Rohzeilen** — und vergleicht. Sie spielt die Wirklichkeit gegen die
Datenbank durch, Szene für Szene. Und sie legt der Oberfläche Daten vor, die
so böse sind wie ein echter Herbst.

## Die drei Teile

| Ordner | Frage | Was drin ist |
|---|---|---|
| `orakel/` | **Rechnet die Datenbank richtig?** | Sieben TypeScript-Module, die Masse, Verdunstung, Schrumpfung, Verderbsmodell, Kaskade und Bilanz **aus den Rohtabellen** neu rechnen — ohne eine Zeile aus `src/` oder eine Funktion aus der Datenbank. `orakel.test.ts` prüft sie an Fällen, die von Hand gerechnet sind; `gegen_db.test.ts` hält sie gegen jede Zeile der Datenbank. `formeln/` ist der Abzug aller 145 Rechenobjekte, wie PostgreSQL sie heute hält (`formeln_holen.mjs`) — `git diff` zeigt, ob sich eine Formel bewegt hat. |
| `bildschirm/` | **Kann die Oberfläche etwas Falsches zeigen?** | `achse.ts`: die Regeln A1–A6, die jede Achse erfüllen muss, und `achsenBereich()`, der Bereich, den ein Diagramm nehmen sollte — an dem Fall entwickelt, der auf dem Betrieb passiert ist (x-Achse bis −1000 Tage). `boese_saison.sql`: zwölf Fälle, wie sie ein echter Herbst liefert (Zettel mit dem Jahr 2029, doppelte Lieferung, 99 999 kg, Faules über der Basis, …), jeder mit Erwartung. `invarianten.mjs`: der Browser-Prüfstand, der elf Regeln auf jeder Seite misst. |
| `drehbuecher/` | **Bildet die App die Praxis ab?** | Ein Tag auf dem Betrieb, Szene für Szene: Wirklichkeit · in der App · gespeichert · sichtbar · Prüfung. `01` folgt einer Charge durch alle Stationen — und findet die Szene, die heute nicht geht (Lagerkontrolle an einer sortierten Palette). `02` ist der Zettel mit dem falschen Jahr. `spieler.mjs` führt die SQL-Szenen gegen eine Kopie der Demo aus. |

## Laufen lassen

```
npm run gegenprobe                    # Orakel-Selbstprüfung + Achsenregeln (ohne Datenbank)
npm run gegenprobe -- --db demo       # dazu das Orakel gegen die Datenbank „demo"
npm run gegenprobe -- --db boese      # gegen die böse Saison (Phase 3: muss erst rot sein)
node gegenprobe/drehbuecher/spieler.mjs 01
PRUEFSTAND_DATEN=gegenprobe/bildschirm/daten node gegenprobe/bildschirm/invarianten.mjs
```

Die lokale Datenbank wie in `supabase/test/run.sh`: Socket `/tmp/pgsock`,
Port 55432, Datenbank `demo` aus `pruefstand/demo_bauen.sh`. Die böse Saison:

```
psql "postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432" -c "create database boese template demo"
psql "postgresql://postgres@/boese?host=/tmp/pgsock&port=55432" -v ON_ERROR_STOP=1 -f gegenprobe/bildschirm/boese_saison.sql
psql "postgresql://postgres@/boese?host=/tmp/pgsock&port=55432" -c "select auswertung_aktualisieren()"
./pruefstand/daten_dumpen.sh "postgresql://postgres@/boese?host=/tmp/pgsock&port=55432" gegenprobe/bildschirm/daten
```

## Drei Regeln, die für alles hier gelten

1. **Kein Import aus `src/`, kein Aufruf einer Datenbankfunktion im Orakel.**
   Sobald das Orakel den Prüfling benutzt, erbt es dessen Fehler. Die eine
   Ausnahme ist `vergleich.ts`, das Zeilen liest — nie rechnet.
2. **Ein übersprungener Vergleich ist kein bestandener.** Fehlt die
   Datenbank, meldet der Läufer die Zahl der übersprungenen Fälle laut, und
   der Bericht führt sie als „nicht geprüft".
3. **Jede Erwartung steht, bevor die Reparatur da ist.** Die Prüfungen S2 in
   Drehbuch 02 und die Regeln A4/A5 auf der bösen Saison sind heute **rot**.
   Das ist ihr Zweck: Sie werden grün, wenn die Reparatur richtig ist — und
   nur dann.

## Stand beim Abzug (11. September)

- `npm run gegenprobe -- --db demo`: **38 Fälle, 38 bestanden, 0 übersprungen** —
  24 Handfälle des Orakels, 8 Achsenregeln, 6 Vergleiche gegen die Datenbank:
  Rückgrat/Kohorten (Masse), Verdunstung je Wägung, Schrumpfung (vier Arten,
  alle Sorten), Verderbsmodell (24 Kenngrössen und die Kurve an 43 Stellen),
  Kaskade (jede Zeile, jeder Strom) mit K1–K4, und die Zeit (K7). Die
  Demo-Saison rechnet also so, wie die Formeln es sagen. Ob die Formeln das
  Richtige sagen, ist die Frage von Phase 2.
- `-- --db boese`: 5 von 6 — **K7 rot**, wie gewollt: zwei Palox-Punkte mit
  −139 und −1053 Lagertagen sind plausibel, drei Arbeiten haben negative
  Lagertage (darunter die Wäsche nach dem Sortieren, die den falschen Zettel
  über `mv_sortier_eingang` erbt).
- Drehbuch 01: 7 von 8 Prüfungen ok; **S6 rot** (Lagerkontrolle an einer
  sortierten Palette: die Lüge „heutiges Gewicht = damaliges" gilt als
  verwendbar). Drehbuch 02: 2 von 3; **S2 rot** (der Zettel von 2029 ist
  plausibel). Beide bleiben rot, bis Phase 4 repariert.
- `invarianten.mjs` auf der Demo: 9 Seiten, 6 Diagramme, **3 Verstösse** —
  die Marke „Kürbis kontrollieren" ist auf dem Handy abgeschnitten (I7, auf
  Start, Neu, Kontrolle) — und 2 Hinweise: zwei Datumsachsen, die das Gerüst
  noch nicht lesen kann (Phase 1: das Diagramm nennt seine Einheit selbst).
  Auf der bösen Saison **7 Verstösse**: dieselben drei, dazu „Palox: Faules im
  Lager" mit x-Achse ab −1000 und einem Punkt bei −1053, der sie bestimmt
  (I5, I6 — der Betriebsfall, gemessen), Messungen → „Wird das Älteste zuerst
  verarbeitet?" mit demselben Punkt auf der y-Achse (I6), und in „Verdunstung"
  ein Marker ausserhalb des Rahmens (I4): die nicht verwendbare Wägung mit
  negativer Rate liegt unter der Null und wird stumm weggeschnitten.
- Beim Abzug der Formeln gefunden, nicht gesucht: `mv_auftrag_masse` rechnet
  Lagertage mit `a.start_ts::date` — dem UTC-Tag. 0067 hat fünf Stellen auf
  `betriebstag()` umgestellt und diese nicht (siehe `docs/PLAN_RUNDE_N.md`).
