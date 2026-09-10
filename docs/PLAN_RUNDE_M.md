# Was Runde M repariert hat, und was offen bleibt

`docs/WERKSTATTBERICHT.md` sagt, was die Werkstätten gefunden haben; er
entsteht bei jedem Lauf neu. Diese Datei sagt, was davon **gemacht** ist,
was **liegen bleibt** und warum — und welche Fragen an den Betrieb gehen.
Sie ist von Hand geschrieben.

## Die Regel, an der jede Zeile gemessen wird

Unverändert seit Runde L: **Die App wird nicht komplizierter.** Kein neuer
Bildschirm, keine neue Maske, keine neue Frage an den Arbeiter. Was hier
steht, ist Reparatur — und in zwei Fällen sogar *weniger* Code als vorher.

Vier Sorten Arbeit, sauber getrennt:

**Reparatur** — etwas ist nachweislich falsch, und es gibt genau eine
richtige Antwort. Wird gemacht.

**Reduktion** — der Code wird kleiner, das Verhalten bleibt gleich. Bewiesen,
nicht behauptet: Der Beweis ist ein Lauf mit entferntem Code, bei dem `tsc`
und alle Tests grün bleiben.

**Frage an den Betrieb** — zwei Antworten sind vertretbar, und die Wahl
gehört nicht dem Programmierer. Wird vorgelegt, nicht entschieden.

**Kein Fehler** — nachgesehen und in Ordnung. Steht ausdrücklich im Bericht,
denn eine Liste, die nur Mängel nennt, sagt nicht, wie weit nachgesehen
wurde.

## Was in dieser Runde repariert wurde

### 0067 — Der Tag des Arbeiters

| Was | Grösse | Woran man es sieht |
|---|---|---|
| `betriebstag()` statt `::date` an fünf Stellen; die Zone steht als Einstellung in der Datenbank | Saisonverlust 52 119.38 → 52 099.70 kg; ein verschobener Lagertag; auf der Rate einer einzelnen Wägung bis 14.4 % | Prüfung in `pruefung.sql`: keine Sicht giesst einen Zeitpunkt selbst auf ein Datum |
| `heute()` in `lib/format.ts` statt `new Date().toISOString().slice(0,10)` an fünf Stellen | Zwischen Mitternacht und 02:00 Ortszeit bot die Maske **gestern** an | `test/format.test.ts` durchsucht `src/` nach dem alten Muster |
| Vier `NOT VALID`-Zusagen bestätigt, fünf überflüssige Indexe gestrichen | 0 Verstösse; 120 kB, bei jedem Schreibvorgang mitgepflegt | Fingerabdruck in `run.sh` |

### 0068 — Was die Gegenrede übrig gelassen hat

Aus 110 Verdachten blieben nach dem Nachmessen und dem Gegenlesen drei
stehen. **Zwölf sind an der Gegenrede zerbrochen** — fast immer nach
demselben Muster: Die Rohzahlen reproduzierten sich exakt, der Satz darüber
nicht.

| Was | Grösse | Woran man es sieht |
|---|---|---|
| Neu rechnen nur für den Betriebsleiter (ohne Anmeldung weiter offen, für die Prüfstände) | Ein Lauf sperrt jede gespeicherte Ansicht; ein paralleler Leser wartete **2 897 ms** statt 1.34 ms | Prüffall in beide Richtungen: Arbeiter abgewiesen, Betriebsleiter durch |
| `erg_punkte` ist eine Kopie von `mv_schimmel_punkte` statt einer zweiten Rechnung | **103 ms von 3 017 ms** (3.4 %) und 120 kB je Neurechnen | `pg_get_viewdef('erg_punkte')` nennt `mv_schimmel_punkte`; Inhalt mit `except` in beide Richtungen |
| `zahl()` hält den **gerundeten** Wert gegen die Grenze | Fenster 0.005 kg breit bei 10¹² kg — Faktor drei Millionen von jeder Zahl dieses Betriebs entfernt | Zwei Prüffälle direkt an der Grenze |

### 0069 — Die Zeilenregeln gelten wieder

| Was | Grösse | Woran man es sieht |
|---|---|---|
| Fünf Sichten bekommen `with (security_invoker = true)` zurück, das 0067 gelöscht hatte | Mit verengter Leseregel: Arbeiter sieht in `auftrag` **0 Zeilen**, durch `v_auftrag_masse` **308** | Neue Zusicherung: **jede** Sicht in `public` hat die Klausel |

## Die Lehre dieser Runde: was ein Vergleich zweier Wege nicht findet

Der Abgleich in `supabase/test/run.sh` ist die schärfste Prüfung, die dieses
Projekt hat: Er baut die Datenbank einmal aus den Migrationen und einmal aus
`setup.sql` und vergleicht alle 2 636 Objekte. Er hat den Fehler aus 0067
nicht gefunden — weil **beide Wege denselben Fehler hatten**.

Das ist kein Versehen, sondern die Bauart: Ein Vergleich findet nur, was die
Wege trennt, nie das, was sie teilen. Für Eigenschaften, die immer gelten
müssen, braucht es eine Zusicherung, die ohne Vergleich auskommt.

Dieselbe Lehre in klein, dreimal in dieser Runde:

* Der **Bildschirm-Prüfstand** kannte nur `process.exit(0)` — er konnte nicht
  scheitern (Runde M, Phase 0).
* Ein **Teillauf** der Werkstätten überschrieb den Bestand des vollen Laufs,
  und der Bericht daraus sah vollständig aus.
* `a7_raender` hat eine Formel für sich gerechnet und dabei ihre Eingabe
  selbst erfunden — Ergebnis war ein Befund über einen negativen Faktor, den
  es in der Sicht nicht geben kann. Seither prüft es zuerst an echten Zeilen,
  ob sein Nachbau dieselben Zahlen ergibt.

Jedes Werkzeug in `werkstatt/` hat deshalb eine **Selbstprobe**: einen Fall,
in dem es anschlagen *muss*. `werkstatt/lauf.mjs` geht mit Rückgabewert 2,
wenn auch nur eines sie nicht besteht oder keine hat.

## Was liegen bleibt, mit Zahl

**Die Freiheitsgrade der Unsicherheitsbänder** (`FPF-001`). Sie entstehen als
`LEAST(...)` über drei Bestandteile und noch einmal als `min(df)` über die
Sorten darin. Zweimal ein Minimum — der am schlechtesten belegte Summand
zieht das ganze Band auf. Alle fünf Ströme stehen auf df = 1 und t = 12.706;
Satterthwaite ergibt 15 bis 38. Die Bänder sind dadurch rund **6.3-mal zu
weit**, zusammen **22 775 kg**.

Es wird trotzdem **nicht** repariert, und das ist der interessante Teil:
Beim grössten Strom (Schimmel/Fäulnis) unterschätzt die Delta-Methode die
Streuung um Faktor **3.9**. Die beiden Fehler heben sich zum Teil auf. **Wer
nur die Freiheitsgrade richtigstellt, macht das Schimmelband schlechter, nicht
besser** — es wäre dann selbstbewusst zu eng statt vorsichtig zu weit. Beides
gehört in eine Migration, mit einer Prüfung, die beide Seiten festhält.

**`mv_auftrag_masse` enthält dieselbe Zeitzonen-Verwechslung** wie die fünf
Sichten aus 0067, ist aber eine gespeicherte Sicht: `drop materialized view …
cascade` nimmt **51 Objekte** mit. Nachgemessen, bevor das als „später"
abgetan wird: 5 von 309 Arbeiten haben einen Startzeitpunkt, dessen UTC-Tag
und Schweizer Tag auseinanderfallen; in der Betriebszone neu gefüllt und
alles nachgerechnet ergibt **dieselben vier Zahlen bis auf den Rappen**. Der
Umbau bewegt heute nichts.

## Was nicht gemacht wird, und warum

**Keine Anzeige für den Boden bei 0.25.** Er kann bei den gemessenen
Verdunstungsraten (0.046 % bis 0.062 % je Tag) nicht greifen — er läge bei
6.9 Jahren Lagerdauer. Eine Anzeige dafür wäre ein Fall, den nie jemand
sieht, in einer App, die nicht komplizierter werden soll.

**Keine gemeinsame Funktion für die gefundenen Klone.** `c1_vermessung`
findet Stellen mit gleicher Form; gleiche Form ist nicht gleiche Bedeutung.
Zwei Bildschirme mit je einer Tabelle und einer Filterzeile sehen gleich aus,
weil eine Tabelle mit Filterzeile so aussieht. Der Bericht nennt deshalb eine
Zahl und keine Anweisung.

**Keine Betriebsleiterrolle in der Datenbank.** Dass jeder Angemeldete alle
Auswertungstabellen lesen darf, ist eine Frage an den Betrieb (siehe unten) —
und ein Teil dieser Tabellen ist für die Arbeiter-App nötig. Wer hier etwas
wegnimmt, muss Tabelle für Tabelle entscheiden, sonst steht der Zähler am
Montag vor einer leeren Maske.

## Die Fragen an den Betrieb

Sie stehen ausführlich in `docs/FRAGEN.md` und `docs/fragen.html`. Kurz:

1. **Darf jeder Angemeldete alle Auswertungen sehen?** Heute ja — auch der
   Zähler, wenn er die Adresse kennt. Die Oberfläche zeigt ihm die Seiten
   nicht, die Datenbank gibt sie heraus.
2. **Der Reiter „Ursachen" antwortet auf 80.6 % seiner Felder**, die übrigen
   vier auf 90.7 % bis 98.5 %. Fehlt dort eine Messung, die der Betrieb
   machen könnte — oder gehören die Spalten weg?
