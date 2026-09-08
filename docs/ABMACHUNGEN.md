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
| AB-15 | Fax ist kein Waschgang: Etikettieren und Abpacken nach Bestellung. Erfasst werden die gemachten Kisten (je Kaliber, „+ 1 Palette") und das Faule, kistenweise gewogen (Brutto, Kistenart, mit/ohne Palette). Kein Palox, kein zu klein/zu gross, keine Kilo-Frage. Das Faule ist ein eigener Strom („Faul beim Abpacken"), nicht Teil der Verderbskurve. | 7. Sept | `pruefung.sql` Block 0051 (Netto per Auslöser, nicht gewaschen, eigener Strom, kein Modellpunkt); `kette.mjs` dritter Durchlauf + `kette_pruefen.sh` |
| AB-16 | Die Maschine sortiert immer nach Kaliber: Beim Eröffnen wird gefragt, *welche* Bänder heute eingestellt sind („wie zuletzt — übernehmen / anpassen"). Von Hand: Kiste ab x kg (welches x) oder Kaliber (welche Bänder). Eine Änderung ist eine neue, datierte Fassung; nichts wird überschrieben. | 7. Sept | `pruefung.sql` Block 0051 (`sortierschema_festlegen`: gleich → gleiche Fassung, anders → neue ab heute, lückenhaft → abgelehnt); `kette.mjs` (Bänder angepasst, Sollgewicht übernommen) |
| AB-13 | Import der Perigon-Warenausgangsdatei: immer die ganze Datei, die App erkennt neu / geändert / unverändert / verschwunden; Rohzeilen bleiben (Prüfsumme, Fingerabdruck); Lieferungen entstehen je Position und Charge; ab 1. Juli 2026, Journal L nicht, beide Firmen eine Halle, sechsstellige Nummern über `charge.perigon_nr`. Artikel werden bestätigt, nicht geraten. | 7. Sept | `test/warenausgang.test.ts`; `pruefung.sql` Blöcke 0050 und 0055 (einmal, zweimal, korrigiert, zurückgemeldet, nur der Betriebsleiter); Bildschirm-Prüfstand `betrieb-import` mit der Probedatei |
| AB-18 | Die Erfassung in der Halle ist punktuell — nicht jede Arbeit wird dokumentiert, vielleicht nur fünfzehn Waschgänge in einer Saison. Vollständig sind nur zwei Listen: der Wareneingang (Erntejournal) und der Warenausgang (Lieferscheine). Aus den Arbeiten kommen Raten, keine Mengen. Überblick und Ursachen behaupten deshalb keine Menge, die nur aus Arbeiten stammt („sortiert", „gewaschen", „wartet aufs Waschen"), und keine Vorhersage („was kostet Warten"). | 7. Sept | Überblick (Eingang, Ausgang gemessen; Verlust, Bestand Modell), Ursachen (vier Ursachen, je Sorte und Charge); `ENTSCHEIDUNGEN.md` Runde E |
| AB-19 | Am Waschbecken wählt der Vorarbeiter das Kaliber aus den Bändern der Sorte (Vorgabe §6 oder der Sortierlauf der Charge) — oder gibt ein eigenes Band ein, wenn das Etikett etwas anderes nennt. Das Kistengewicht zum eigenen Band ist nur bekannt, wenn beim Sortieren genau dieses Band gezählt wurde; sonst sagt es die Plausibilität. | 7. Sept | `pruefung.sql` Block 0054; `kette.mjs` vierter Durchlauf + `kette_pruefen.sh`; Bildschirme `neu-kaliber`, `neu-kaliber-eigen` |
| AB-17 | Es gibt kein FIFO. Eingang und Ausgang einer Charge verteilen sich über Wochen; der Bestand wird je Eingangstag geführt (Paletten des Tages minus gezählte Paletten mit diesem Zetteldatum) und die Kaskade rechnet je Eingangstag mit seinem Alter. „Liegt seit" ist eine Spanne. | 7. Sept | `pruefung.sql` Block 0051 (drei Kohorten, jüngste zuerst verarbeitet, Summe = Bestand, Spanne, `v_naechste_charge` je Kohorte); `v_charge_kohorte` |
| AB-20 | Eine Palette wird im Lager nicht schwerer. Wiegt sie beim Nachwiegen mehr als 1 % über dem Eingangsnetto, ist die Wägung ein Fehler (Tara, Kistenzahl, Zahlendreher): sie bleibt gespeichert, zählt nicht in die Verdunstungsrate und steht mit Grund unter Auffälligkeiten. Die Rate je Sorte ist nie negativ. | 7. Sept | `pruefung.sql` Block 0056; `run.sh` Stufe 4b (Aktualisierung mit schwereren Paletten); `v_verdunstung_messung.verwendbar`, `v_koeff_verdunstung`, `v_plausibilitaet` „Wägung" |
| AB-21 | Eine einzelne Zahl, die nicht darstellbar ist, macht eine Spalte unbekannt — nie einen ganzen Bildschirm leer. Jeder Koeffizient in der Hochrechnung ist ein Anteil (0 … 1), jede Masse nie negativ. Die Bilanz sagt im Klartext, wenn der Wareneingang fehlt, statt am Verhältnis Ausgang/Eingang abzubrechen. | 8. Sept | `pruefung.sql` Block 0058 (Helfer, Klammerung, alle vier Sichten mit `select *`); `zahl()`, `v_hochrechnung`, `verlust_ranking()`, `v_saisonbilanz`, `v_marge_buch` |
| AB-22 | Kein harter Zahlencast auf eine berechnete Grösse. Jeder der 93 Casts in den Auswertungssichten läuft durch `zahl()`; passt ein Wert nicht, ist er unbekannt statt ein Abbruch. Und die App lädt jede Sicht für sich: scheitert eine, fehlen nur ihre Zahlen, der Rest des Bildschirms steht — mit einer Liste, welche es waren. | 8. Sept | `pruefung.sql` Block 0059 (Zählprüfung über alle Sichten, dazu jede Dashboard-Sicht mit `select *`); `src/auswertung/daten.ts` sammelt `probleme`, `Probleme`-Karte auf allen vier Reitern |

Noch offen (in `FRAGEN.md`, keine App-Änderung ohne Antwort):

| Kennung | Absprache / Frage | Stand |
|---|---|---|
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
