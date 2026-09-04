# Abmachungen mit dem Betrieb — und der Test, der jede beweist

Was der Betrieb festgelegt hat, muss die App fragen, speichern und verrechnen.
Diese Liste hält jede Absprache mit ihrer Kennung, ihrer Quelle und **dem Test
fest, der sie beweist**. Eine Zeile ohne grünen Test gilt als offen, egal wie
fertig der Code aussieht.

Die Tests laufen alle in `./supabase/test/run.sh` (Datenbank + Fachlogik) und
in den Prüfständen (`pruefstand/kette.mjs` für die Kette über die echten
Masken, `node pruefstand/luecken.mjs` für den Lückenscanner). Alles hängt in
der CI (`.github/workflows/pruefung.yml`).

| Kennung | Absprache | Quelle | Beweis |
|---|---|---|---|
| AB-01 | Beim Auftragsstart wird bestätigt, wie sortiert wird (Kiste ab x kg / Kaliber), vor Ort änderbar. Beide Arten dürfen je Sorte nebeneinander stehen. Nach Kaliber gibt es keine Überfüllung. | 1. Sept | `pruefung.sql` „AB-01 Sortierart geprüft"; `kette.mjs` (Art beim Eröffnen) |
| AB-02 | Der Palox wird bei Beginn und Abschluss abgelesen. Ohne Ablesung kein Abschluss. | 2. Sept | `pruefung.sql` „Palox …"; `kette.mjs` „ohne Ablesung kommt der Abschluss nicht an der Palox-Frage vorbei" — der Abschluss-Assistent beginnt mit der Ablesung |
| AB-03 | Der Ausschuss wird gewogen (Brutto, Kisten, Gebinde), Netto abgeleitet; Schätzung bleibt für Notfälle möglich. | 1. Sept | `pruefung.sql` „AB-03 Ausschuss geprüft"; `kette.mjs` (zu klein gewogen, zu gross geschätzt) |
| AB-04 | Was man vergessen kann, gehört an den Abschluss; der Abschluss erzwingt die Vollständigkeit. | 1. Sept | `kette.mjs` „Geführter Abschluss" (Assistent: Palox, Ausschuss, Charge, Zusammenfassung mit „Fehlt noch"); `pruefung.sql` (Angaben) |
| AB-05 | Zwei Ausschuss-Paletten-Fragen: „leer zu Beginn?" (Start) und „alles von dieser Arbeit?" (Abschluss). | 2. Sept | `kette_pruefen.sh` (beide Angaben kommen an); `kette.mjs` (Startfrage in der Checkliste, Abschlussfrage im Assistenten; eine vergessene Startfrage holt der Abschluss nach) |
| AB-06 | Die Chargennummer wird eingetippt, nicht aus einer Liste gewählt. | 1. Sept | `kette.mjs` (`#charge` im Assistenten, Schritt „Welche Charge?"); unbekannte Nummer blockiert „Weiter" |
| AB-07 | Erfassungsbeginn und Vorab-Ausgang je Charge; die Bilanz zählt den Vorlauf zum Ausgang. | 1. Sept | `pruefung.sql` „AB-07/08/09" (Vorlauf senkt Lücke um denselben Betrag) |
| AB-08 | Fax ist ein eigener Auftragstyp (fachlich ein Waschgang). | 2. Sept | `pruefung.sql` „AB-07/08/09" (ist_fax); `i18n.test.ts` (vierte Tätigkeit) |
| AB-09 | Die Lagerkontrolle hält fest, wie die Palette gegriffen wurde (zufällig erreichbar / Mitte-unten / gezielt). | 2. Sept | `pruefung.sql` „AB-07/08/09" (Auswahlart gehalten, Unsinn abgelehnt) |
| AB-10 | Hinweis in der Palox-Maske: Gewicht direkt von der Waage ablesen. | 2. Sept | im Frontend (`PaloxMaske`, `waageAblesenHinweis`); Bildschirm-Prüfstand `arbeit-palox` |
| AB-11 | Das Datum vom Palettenzettel ist Pflicht (Voraussetzung des Alters). | 1. Sept | `pruefung.sql` (Palette ohne Datum abgewiesen); `kette.mjs` (Zähler: „+" ohne Datum gesperrt; das Datum bleibt für die nächste Palette stehen) |
| AB-12 | Am Waschbecken werden Kisten gezählt; das Kistengewicht wird am Sortieren gemessen. | 3. Sept | `pruefung.sql` „Kisten am Waschbecken"; `v_koeff_gebinde` |

Noch offen (in `FRAGEN.md`, keine App-Änderung ohne Antwort):

| Kennung | Absprache / Frage | Stand |
|---|---|---|
| AB-13 | Import der Perigon-Warenausgangsdatei (Rohdatei ablegen, an Prüfsumme wiedererkennen, erneuter Import folgenlos). | wartet auf die Dateivorlage — der Betrieb liefert die Excel-Dateien nach |
| AB-14 | Direkte Messung beim Leeren des Palox (wie viel nicht faul). | offen; entscheidet, ob der Sockel am Saisonende erkennbar wird (`STATISTIK_BEFUND.md`) |

## Wie diese Datei ehrlich bleibt

Der Lückenscanner (`node pruefstand/luecken.mjs`, Teil von `run.sh`) prüft in
beide Richtungen, dass zwischen Maske und Auswertung nichts nur auf einer Seite
existiert:

- **Vorwärts:** Jede Spalte der Erfassungstabellen, die ein Arbeiter füllt,
  wird von der App geschrieben (oder steht mit Begründung auf der Ausnahmeliste
  im Scanner). Eine Spalte, die die Datenbank kennt und die App nie schreibt,
  ist genau die Lücke, die AB-02 und AB-07 waren.
- **Rückwärts:** Jede Erfassungstabelle, aus der die Auswertung liest, wird von
  der App auch geschrieben.

Wer eine neue Abmachung umsetzt, trägt sie hier ein und nennt den Test. Wer eine
Spalte anlegt, die niemand füllt, hört es beim nächsten `run.sh`.
