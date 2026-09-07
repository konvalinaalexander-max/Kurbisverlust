# Auftrag: den Warenausgang-Import fertig bauen

Du übernimmst eine vorbereitete Arbeit. Lies zuerst
[`docs/WARENAUSGANG_BEFUND.md`](WARENAUSGANG_BEFUND.md) — dort steht, was in den
Dateien des Betriebs tatsächlich drinsteht, an den echten Dateien gemessen.
Diese Seite sagt, was schon gebaut und geprüft ist, was du noch bauen sollst und
welche Entscheidungen dabei schon gefallen sind.

## Worum es geht

Der Betrieb zieht aus seinem Warenwirtschaftssystem (Perigon) zwei
Excel-Dateien — für jede seiner zwei Firmen eine — und lädt sie in der App hoch.
**Immer die ganze Datei, nie nur die neuen Zeilen.** Die App erkennt selbst, was
sie schon hat, was neu ist und was im Perigon nachträglich korrigiert wurde, und
schreibt daraus Lieferungen. Damit schliesst sich die Massenbilanz gegen echte
Zahlen statt gegen von Hand getippte.

Wörtlich gewünscht: „wenn ich dann in der webapp einfach immer das aktuelle
sheet vom pc hochladen könnte — und die webapp erkennt gleich welche relevant
sind … und dann halt erkennen bis wo hat es die daten schon und welche sind neu
— und das dann halt runter ziehen und in die datenbank laden."

## Was schon fertig und geprüft ist

| Stück | Ort | Zustand |
|---|---|---|
| **XLSX-Leser ohne Abhängigkeit** | `src/lib/xlsx.ts` | Zelle für Zelle gegen einen unabhängigen Leser geprüft: 396 096 Zellen der drei echten Dateien, null Abweichungen. 420 ms für die grösste Datei. |
| **Regeln des Imports** | `src/lib/warenausgang.ts` | Kopf erkennen, Zeilen lesen, Kürbis erkennen, Masse rechnen, Schlüssel und Fingerabdruck, Abgleich, Lieferungen bauen. Reine Funktionen. |
| **Tests** | `test/warenausgang.test.ts` | 27 Tests, alle grün (`npm test`). |
| **Prüfdatei** | `test/daten/warenausgang-probe.xlsx` | Erfunden, gleiche Form, enthält jeden Fall, an dem der Import schon einmal falsch lag. Gebaut von `probe_bauen.py`. |
| **Schema** | `supabase/migrations/0050_warenausgang_import.sql` | Quelle, Datei, Rohzeilen, Artikel-Zuordnung, `lieferung.quelle` und `lieferung.extern_id`, drei Sichten. |
| **DB-Tests** | `supabase/test/pruefung.sql`, Block 0050 | Wiederholung folgenlos, Masse kommt einmal an, Zuordnung wird bestätigt statt geraten. |

Zwei Fehler haben diese Prüfungen schon gefunden, beide der Art, die still
falsch rechnet:

- Ein gieriges Muster im XLSX-Leser liess eine leere Zelle den Wert der nächsten
  verschlucken — alle Spalten dahinter um eins verschoben, ohne Fehlermeldung.
- `lieferungenBauen` liess zwei Rücknahmen (negative Menge) einfach weg. Die
  Bilanz lag um 3.9 t daneben. Jetzt kommen sie getrennt zurück und müssen
  angezeigt werden.

## Was du bauen sollst

### 1. Der Import-Bildschirm

Unter **Betrieb → Warenausgang** (dort liegt heute `Lieferungen.tsx`) oder als
eigener Unterreiter „Import". Der Ablauf ist ein Assistent nach denselben Regeln
wie in [`docs/UI-KONZEPT.md`](UI-KONZEPT.md): ein Bildschirm, eine Frage.

1. **Dateien wählen.** Beide auf einmal (`multiple`). Der Betrieb lädt immer
   beide — wenn nur eine kommt, sag das freundlich und lass es zu.
2. **Herkunft bestätigen.** Je Datei zeigt die App ihren Vorschlag aus dem
   Dateinamen (`quelleVorschlag`) und die bekannten Quellen aus
   `ausgang_quelle`. Der Betriebsleiter bestätigt oder legt eine neue an. Das
   ist die eine Angabe, die die App nicht raten darf: an ihr hängt die
   Eindeutigkeit der Positionsnummern.
3. **Befund zeigen, bevor etwas geschrieben wird.** `befund()` liefert alles:
   Zeilen, Kürbiszeilen, Positionen, Zeitraum, Positionsmasse, Masse mit und
   ohne Chargenbezug, Chargen, Artikel, Journale. Dazu `abgleichen()` gegen die
   schon bekannten Zeilen (aus `ausgang_zeile`, Schlüssel und Fingerabdruck):
   **neu / geändert / unverändert / verschwunden**. Genau diese vier Zahlen
   beantworten die Frage „bis wo hat es die Daten schon".
4. **Unbestätigte Artikel klären.** Alles, was `vorschlag_kuerbis` ist und noch
   keinen Eintrag in `ausgang_artikel` hat, kommt als Liste mit zwei Knöpfen
   („Kürbis" / „kein Kürbis") und einer Sortenauswahl, die den beobachteten
   Vorschlag (`vorschlag_sorte`, mit `vorschlag_belege` als Beleg) vorschlägt.
   Das ist Arbeit von einmal rund 57 Artikeln, danach nur noch bei neuen.
5. **Übernehmen.** Schreibt `ausgang_datei`, `ausgang_zeile` (Upsert auf den
   Schlüssel, `geaendert_ts` bei Änderung) und die Lieferungen (Upsert auf
   `extern_id`). Danach `v_ausgang_pruef` lesen und das Ergebnis zeigen: leer
   heisst, jedes Kilo der Datei ist genau einmal angekommen.
6. **Rücknahmen anzeigen.** `lieferungenBauen` gibt sie getrennt zurück. Sie
   gehören auf den Bildschirm, mit der Bemerkung, dass sie **nicht** übernommen
   wurden und von Hand zu behandeln sind (oder — deine Entscheidung, wenn du es
   sauber lösen kannst — als eigenes `ausgang_ziel`).

Alles Rechnen passiert im Browser, bevor geschrieben wird. Das ist Absicht: der
Betriebsleiter sieht, was passieren wird, und kann abbrechen.

### 2. Die Artikel-Zuordnung pflegen

Ein eigener Bildschirm (Betrieb → Stammdaten → Artikel oder ein Unterreiter des
Imports): die Liste aus `v_ausgang_artikel_vorschlag`, sortiert nach Masse,
mit Bestätigung und Sorte. Wer hier nichts tut, blockiert den Import nicht —
unbestätigte Artikel zählen nach Vorschlag, sind aber als Vorschlag markiert.

### 3. Die Zahlen sichtbar machen

Sobald der Import läuft, hat der Betriebsleiter zum ersten Mal echte
Ausgangszahlen. Zeig sie dort, wo sie hingehören:

- **Überblick**, Karte „Geht die Rechnung auf?": Die Lücke wird jetzt echt.
- **Chargen**: Je Charge steht bereits eine Lieferungsliste — sie füllt sich.
- **Messungen → Datenqualität**: eine Zeile „Warenausgang eingelesen bis …"
  aus `v_ausgang_lage`, mit den offenen Artikeln als Handlung.
- Prüfen, ob `v_saisonverlauf` und `v_saisonbilanz` mit den echten Mengen noch
  stimmen (sie lesen `lieferung`, sollten also von allein richtig sein).

### 4. Der Prüfstand

- `pruefstand/daten_dumpen.sh` um die neuen Sichten ergänzen.
- Ein Bildschirm-Eintrag für den Import in `pruefstand/bildschirme.mjs`.
- `run.sh` bleibt, wie es ist — der 0050-Block läuft schon mit.
- Erwäge einen Kettentest: Probedatei hochladen, übernehmen, `v_ausgang_pruef`
  muss leer sein. Das wäre der Beweis, dass die Kette auch über den Browser hält.

## Entscheidungen, die schon gefallen sind

| Entscheidung | Warum |
|---|---|
| Die Rohzeilen bleiben in `ausgang_zeile` | Ohne sie lässt sich beim nächsten Hochladen nicht sagen, was neu ist. Die Datei enthält jedes Mal alles. |
| Schlüssel = Quelle + Position + Charge + Laufnummer | `AufPosId` allein ist nicht eindeutig (102 Positionen mit mehreren Chargen), Position + Charge auch nicht ganz (13 doppelte Zeilen). |
| Fingerabdruck über die Inhaltsfelder | Erkennt eine im Perigon korrigierte Zeile als Änderung statt als zweite Lieferung. FNV-1a statt SHA-256, weil er für zwölftausend Zeilen je Datei synchron laufen muss. |
| Masse = Menge × Gewicht je Artikel | An 5 320 Zeilen gegen `TotalGewicht` geprüft, null Abweichungen. |
| Positionsmasse je Position **einmal** zählen | Eine über drei Chargen verteilte Lieferung steht dreimal in der Datei. |
| Chargenzeilen auf die Positionsmasse deckeln, Rest als „ohne Chargenbezug" | 805 Positionen sind nur teilweise, 27 über zugeordnet. So bleibt die Summe gleich der gelieferten Masse. |
| Kürbis wird bestätigt, nicht geraten | Die Regel fängt auch „Kürbisverrechnung" und „Arbeit Kürbisernte". Bis zur Bestätigung ist alles als Vorschlag gekennzeichnet. |
| Sortenvorschlag aus der Charge | Wo eine Zeile eine eigene Chargennummer trägt, ist die Sorte der Charge die Sorte des Artikels — beobachtet, nicht ausgedacht. |
| Rücknahmen getrennt | `lieferung.kg` lässt nur positive Mengen zu, und eine zurückgegangene Palette ist trotzdem eine Bewegung. |
| Der Browser rechnet, die Datenbank prüft nach | Eine Ableitung, ein Test. `v_ausgang_pruef` fängt, wenn beide auseinanderlaufen. |

## Was der Betrieb noch entscheiden muss

Diese vier Fragen stehen ausführlich im Befund. Bau so, dass jede Antwort ohne
Umbau möglich bleibt, und frag sie in der App nicht ab — sie gehören in ein
Gespräch:

1. Was mit den sechsstelligen Perigon-Chargennummern geschehen soll (Vorschlag:
   ohne Chargenbezug in die Bilanz).
2. Ob der Import bis 2024 zurück einlesen soll (Vorschlag: ja, aber nur die
   laufende Saison in die Bilanz).
3. Ob alles in den Dateien vorher in unserer Halle lag — die eine Firma handelt
   Kürbis von acht Produzenten.
4. Wie interne Umbuchungen zwischen den zwei Firmen zählen (Vorschlag: eigenes
   Ziel „intern", nicht als Verkauf).

## Wie du prüfst, dass es hält

```bash
npm test                                   # 70 Tests, davon 27 zum Import
npx tsc --noEmit && npm run build
./supabase/test/run.sh 'postgresql://…'    # enthält den 0050-Block
node pruefstand/bildschirme.mjs            # keine Konsolenfehler, kein Überlauf
```

Und die Probe, die zählt: dieselbe Datei zweimal hochladen. Beim zweiten Mal
muss die App sagen „nichts Neues", und `v_ausgang_pruef` muss leer bleiben.

## Grenzen, die du nicht verschieben sollst

- Keine Tabellen-Bibliothek. Der Leser ist geprüft und kostet nichts.
- Die echten Dateien gehören nicht ins Repository: Kundennamen und Preise.
  Zum Testen ist die erfundene Probedatei da.
- Nichts raten, wo etwas gemessen werden kann. Ein Vorschlag heisst Vorschlag,
  bis ihn jemand bestätigt.
- Keine Zeile still weglassen. Was der Import nicht übernimmt, gehört auf den
  Bildschirm — mit Grund.
