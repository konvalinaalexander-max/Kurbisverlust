# Auftrag Runde N: Gegenprobe, Wirklichkeit, Erscheinungsbild

## 0. In einem Satz

Prüfe die ganze App **mit Werkzeugen, die ihr nicht gehören** — einer
zweiten Rechnung, einer bösen Saison, Drehbüchern aus der Halle —, repariere,
was sie finden, mit einer roten Prüfung vor jeder Reparatur, und gib der
Oberfläche dann das Erscheinungsbild einer teuren Software: gleiche
Struktur, gleiche Reiter, gleiche Grafiken, gleiche Zahlen — neue Klasse.

## 1. Wer hier spricht, und was schon getan ist

Eine erste KI hat diese Runde **geplant und angelegt**, nicht ausgeführt.
Du führst aus. Was du vorfindest:

- `docs/PLAN_RUNDE_N.md` — der Plan: Anlass, Bestand, zehn erste Befunde
  (N-01 … N-10), sechs Phasen mit Toren, was nicht passiert. **Lies ihn ganz.**
- `gegenprobe/` — die neuen Werkzeuge, mit `README.md`. Das Orakel rechnet
  und ist gegen die Demo grün; die Achsenregeln kennen den Betriebsfall; die
  böse Saison liegt geladen bereit (`boese_saison.sql`); zwei Drehbücher
  sind geschrieben und gespielt. Was Gerüst ist, steht im Plan (§1).
- `src/design/tokens.css`, `src/design/bewegung.css`, `docs/DESIGN_RUNDE_N.md`
  — das Erscheinungsbild, Zeichen für Zeichen und Bildschirm für Bildschirm
  festgelegt. Noch nicht eingebunden.
- `gegenprobe/orakel/formeln/` — jedes Rechenobjekt, wie PostgreSQL es am
  11. September hielt. Dein erster Befehl ist der Abzug erneut; `git diff`
  muss leer sein.

Der Betrieb (Kürbis-Hof, Schweiz) hat zwei Dinge gesagt, die du wörtlich
ernst nimmst:

> „Bei Faulen bei Ursachen ist das Diagramm komplett verzerrt, weil es bis
> irgendwie minus tausend Tage geht auf der x-Achse. Und das sind alle Punkte
> auf einer Linie ganz rechts draussen."

> „Wenn man eine Palette wiegt, muss man ja wissen, welcher Gebindetyp und
> wie viele Gebinde. Nach dem Sortieren stehen die Kisten auf neuen Paletten
> — Eingangsgewicht und Eingangsdatum sind dann nicht mehr brauchbar, aber
> es ist trotzdem eine Palette."

Das erste ist reproduziert (böse Saison B1, Drehbuch 02, K7 rot). Das zweite
ist Drehbuch 01, Szene S6 — sie geht heute nicht, und die Datenbank verlangt
ein Brutto „damals", das es nicht gibt.

## 2. Die Haltung

### 2.1 Nichts, was der Prüfling gebaut hat, ist ein Beweis
Die Prüfstände, das Prüfwerk und die Werkstätten laufen weiter — sie halten
Zusagen. Aber in dieser Runde zählt als Beweis nur, was `gegenprobe/` zeigt:
eine Rechnung, die nichts aus `src/` importiert und keine Funktion der
Datenbank ruft; eine Regel, die an Zahlen geprüft wird, bevor etwas
gezeichnet ist; ein Drehbuch, das aus der Halle kommt. Wenn du ein neues
Werkzeug brauchst, bau es dort, nach denselben Regeln (`gegenprobe/README.md`).

### 2.2 Rot zuerst
Keine Reparatur ohne eine Prüfung, die **vorher rot** ist und **nachher
grün** — und nichts anderes wird dabei rot. Die roten Prüfungen von heute:
K7 auf der bösen Saison, Drehbuch 02 S2, Drehbuch 01 S6, und (nach Phase 1)
I5/I6 auf „Palox: Faules im Lager". Sie sind der Zweck des Plans, nicht ein
Mangel daran. **Ein Test wird nie abgeschaltet, abgeschwächt oder
übersprungen, um grün zu werden.**

### 2.3 Beobachtung bleibt Beobachtung
Der Zettel mit dem Jahr 2029 bleibt 2029 in der Datenbank, bis der
Betriebsleiter ihn korrigiert. Repariert wird, was die Auswertung und das
Diagramm **daraus machen**. „Leer ist nicht null" gilt: kein Kilo aus einer
Lücke, keine Rate aus null Tagen, kein Punkt aus negativer Zeit.

### 2.4 Die App wird nicht komplizierter
Kein neuer Bildschirm, kein neuer Reiter, keine neue Frage an den Arbeiter.
Der dritte Weg der Lagerkontrolle (Drehbuch 01 S6) ist **Frage 57 an den
Betrieb** — entwerfen ja, bauen erst nach der Antwort.

### 2.5 Die Faulheitsfalle
Nicht als Ergebnis zählt: „Ich habe das Orakel laufen lassen, es ist grün."
Das wusste die erste KI schon. Zählt: die Antworten der Phase 2 (sind es die
**richtigen** Formeln — Zahl je Frage), die Verstossliste der Phase 3, jede
Reparatur mit ihrer roten Prüfung, jedes Bild vorher/nachher der Phase 5.
Ebenso wenig zählt ein „schöneres" Bild ohne Beweis, dass dieselben Begriffe
und Zahlen an derselben Stelle stehen.

## 3. Der Auftrag, Phase für Phase

Die Tore stehen im Plan (§3). Hier die Kurzform; der Plan gilt.

| Phase | Tust du | Tor |
|---|---|---|
| 0 Lesen, Grundlinie | Dokumente lesen; `npm run pruefen`, `supabase/test/run.sh`, `npm run gegenprobe -- --db demo`, Bilder „vorher"; Formelabzug, `git diff` leer | alles grün, Drift leer |
| 1 Werkzeuge fertig | K6 bauen; `Linien` bekommt `xEinheit`/`yEinheit` + SVG-Klassen, `invarianten.mjs` liest sie; Orakel für Bänder (`band.ts`); Drehbücher 03/05/07/09; Selbstprobe je Werkzeug | Gegenprobe demo grün, Invarianten demo 0 Verstösse |
| 2 Mathematik befragen | synthetische Saison mit bekannter Wahrheit; Verzerrung und Bandüberdeckung je Rechnung; vier Fragen (a)–(d) mit Zahl | Tabelle in `docs/GEGENPROBE_BEFUND.md` |
| 3 Böse Saison durchs UI | `PRUEFSTAND_DATEN=gegenprobe/bildschirm/daten node gegenprobe/bildschirm/invarianten.mjs` — **muss rot sein**; Bilder | Verstossliste, je einem Befund zugeordnet |
| 4 Reparieren | N-01, N-03, N-04 (Migration 0070), N-02 + N-06 (`Diagramm.tsx`, `Ursachen.tsx`, alle Aufrufe), N-05, N-08, Zähler-Hinweis; FPF-001/AUF-001 nur nach Phase 2 | alles grün auf demo **und** boese; Drehbücher 01/02 ok; `setup.sql` gebaut; `SCHEMA_ERWARTET` |
| 5 Erscheinungsbild | `docs/DESIGN_RUNDE_N.md` §5, Bildschirm für Bildschirm, Bild vorher/nachher; Zeichen statt Emoji; Bewegung; Skelett; inline-Stile zu Klassen | Bilder komplett, Begriffe gleich, Invarianten grün, Kontrast gemessen, Bündel ≤ +5 %, keine Abhängigkeit |
| 6 Bericht | `docs/GEGENPROBE_BEFUND.md`, `ENTSCHEIDUNGEN.md` Runde N, `FRAGEN.md` 57–59 + PDF, README | Commit, Push |

## 4. Die festen Regeln (unverändert seit Runde L)

- Entwickeln und pushen **nur** auf `claude/new-session-vrnnyo`
  (`git push -u origin claude/new-session-vrnnyo`, bei Netzfehlern 2/4/8/16 s
  Abstand). **Nie** einen Pull Request anlegen.
- Commits mit `git -c user.name="Alexander Konvalina" -c user.email="konvalina.alexander@gmail.com"`;
  Nachrichten auf Deutsch, ein Satz, der sagt, was sich für den Betrieb ändert.
- Alles auf Deutsch: Code, Namen, Kommentare, Dokumente, Commits.
- **Kein Modellbezeichner** in Code, Kommentaren, Commits, Dokumenten.
- Die echten Excel-Dateien in `/root/.claude/uploads/` enthalten Kundennamen
  und Preise: lokal lesen ja, ins Repository **nie**.
- Nie eine Tabelle oder Spalte löschen; nie datierte Stammdaten überschreiben;
  Sichten und Funktionen mit `create or replace view … with (security_invoker = true)`.
- `setup.sql` nach jeder Migration neu bauen (`supabase/setup_bauen.sh`),
  `SCHEMA_ERWARTET` in `src/lib/version.ts` und `schema_stand()` gleich.
- Jede Migration mit Block in `supabase/test/pruefung.sql`; Fingerabdruck in `run.sh`.
- Lokale Datenbank: Socket `/tmp/pgsock`, Port 55432; Start
  `setsid su postgres -c '/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgdata -o "-k /tmp/pgsock -p 55432 -c listen_addresses=" -l /tmp/pg.log start'`;
  `run.sh` mit URL `postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432`.
- `npm test` ist `node --test test/*.test.ts` — kein vitest.

## 5. Abnahme

Die Runde ist fertig, wenn alles hier zutrifft — und **nichts davon behauptet,
sondern jedes mit Befehl und Ausgabe im Bericht steht**:

1. `npm run gegenprobe -- --db demo` und `-- --db boese`: 0 fehlgeschlagen, 0 übersprungen.
2. `node gegenprobe/drehbuecher/spieler.mjs 01` und `02`: alle Prüfungen ok (S6 in 01 darf „ok" nur sein, wenn die Sicht die Lüge erkennt **oder** der dritte Weg nach Antwort auf Frage 57 gebaut ist; sonst bleibt sie rot und steht so im Bericht).
3. `invarianten.mjs` auf Demo und böser Saison: 0 Verstösse; auf der bösen Saison **vor** Phase 4 mindestens I5/I6 rot (im Bericht als Beweis, dass die Regeln sehen).
4. `docs/GEGENPROBE_BEFUND.md` mit den Antworten der Phase 2 als Zahlen.
5. Bilder aller Seiten vorher/nachher; Begriffs-Prüfstand gleich; Kontrast gemessen.
6. `npm run pruefen`, `supabase/test/run.sh` 7/7, `setup.sql` neu, `SCHEMA_ERWARTET` = `schema_stand()`.
7. `git diff package.json` zeigt nur das Skript `gegenprobe`.
8. Formelabzug am Ende erneut; die Differenz zum Anfang ist **genau** die Liste der Migrationen dieser Runde.

## 6. Bericht

`docs/GEGENPROBE_BEFUND.md`, in dieser Ordnung: (1) Was gemessen wurde, mit
Befehlen. (2) Befunde N-01 … mit Werkzeug, Zahl, Reparatur oder Frage, und
der Prüfung, die es jetzt hält. (3) **Kein Fehler** — was nachgesehen und in
Ordnung ist. (4) Die Antworten der Phase 2. (5) Das Erscheinungsbild:
Bilder, Kontrast, Bündel. (6) Was offen bleibt und warum. Dazu der Abschnitt
„Runde N" in `docs/ENTSCHEIDUNGEN.md` und die Fragen 57–59 in `docs/FRAGEN.md`
(mit `docs/fragen.html` und `docs/Offene-Fragen.pdf` neu gebaut).

Der letzte Absatz des Berichts ist für den Betriebsleiter: drei Sätze, was
er jetzt anders sieht, und was er entscheiden muss.
