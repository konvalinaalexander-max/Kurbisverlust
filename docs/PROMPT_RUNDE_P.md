# Auftrag Runde P: Was liegt, und was davon verkauft sich

## 0. In einem Satz

Richte Datenbank und Betriebsleiter-Seiten auf die zwei Fragen aus, die der
Betrieb wirklich stellt — *wie viel kam rein, ging raus, liegt noch, und wie
viel davon ist verkaufsfähig (heute und in x Wochen, in Prozent)* und *wohin
ging der Kürbis, was war am schlimmsten* —, mit **einer** Formel (der Kaskade
an einem späteren Tag), mit Prüfungen, die vorher rot sind, und ohne dass
eine Zahl auf dem Bildschirm etwas anderes sagt als die Datenbank.

## 1. Wer hier spricht, und was schon getan ist

Eine erste KI hat diese Runde **geplant und vorgerechnet**, nicht ausgeführt.
Du führst aus. Was du vorfindest:

- `docs/PLAN_RUNDE_P.md` — der Plan: Begriffe und Nenner mit den Zahlen der
  Demo, jede neue Sicht Spalte für Spalte, jede Karte, jede Prüfung, die
  Tore. **Lies ihn ganz, bevor du eine Zeile schreibst.**
- `docs/entwurf_runde_p/v_prognose.sql` und `v_wohin.sql` — die zwei Sichten,
  an denen alles hängt, **gegen die Demo gerechnet**: `v_prognose` stimmt bei
  Horizont 0 auf den Rappen mit `erg_charge` und `erg_bilanz` überein (187 775
  kg im Lager, 144 074 kg verkaufsfähig, 153 568 kg gute Ware, 7 144 kg Kanal,
  2 350 kg Fax erwartet, 15 887 / 18 320 kg Verdunstung / Faules an der
  liegenden Ware); `v_wohin` erfüllt seine zwei Identitäten auf allen 61
  Gruppenzeilen mit |Rest| ≤ 0.03 kg. Übernimm sie **wörtlich** in die
  Migration und ergänze, was der Plan dazu verlangt (Band, Rate je Tag,
  Primärschlüssel). Weichst du ab, sag im Bericht, wo und warum, und die
  Zahlen oben müssen weiter stimmen.
- `docs/DESIGN_RUNDE_O.md` — der gebaute Stand der Oberfläche (Bausteine,
  Zeichen, Bewegung, Diagramm-Vertrag). Du baust darauf, nicht daneben.
- `docs/STARTFRAGEN_RUNDE_P.md` — drei Weggabelungen mit Voreinstellung. Ist
  eine Antwort eingetragen, gilt sie; sonst gilt die Voreinstellung. **Warte
  nicht.**

Der Betrieb (Kürbis-Hof, Schweiz) hat gesagt, was er will — im Plan §0
wörtlich. Zwei Sätze davon sind der Massstab für jede Karte:

> „Ich hab noch 400 Tonnen — aber die App sagt mir, nur 65 % davon sind noch
> verkaufbar."

> „Was war am schlimmsten, was ist das grösste Problem, wo geht mein Kürbis
> hin."

## 2. Die Haltung

### 2.1 Eine Formel
Jede Zahl über die Zukunft ist `mv_kaskade` an einem späteren Tag ausgewertet.
Nicht „so ähnlich", nicht „bedingt auf die gute Masse", nicht mit anderer
Klammer. Bei Horizont 0 muss jede Prognosezahl die Zahl von heute sein — das
ist die erste Prüfung, und sie ist heute rot, weil die Sicht fehlt.
`v_naechste_charge` wird auf dieselbe Formel gestellt; danach gibt es im
ganzen Programm nur **eine** Zwei-Wochen-Zahl je Charge.

### 2.2 Rot zuerst
Block 0071 in `supabase/test/pruefung.sql` wird **vor** der Migration
geschrieben und laufen gelassen — er muss rot sein. Dann die Migration; dann
grün; nichts anderes wird rot. Dasselbe für K8–K11 im Orakel und für die
zwei neuen Spalten der Simulationsmatrix. **Ein Test wird nie abgeschaltet,
abgeschwächt oder übersprungen, um grün zu werden.**

### 2.3 Der Nenner steht dabei
„Im Lager" ist Eingangsware, die nicht ausgeliefert ist. Der verkaufsfähige
Anteil bezieht sich darauf — heute und über jeden Horizont, mit demselben
Nenner. „Des Eingangs" gilt für die Saisonbilanz. Der Begriffs-Prüfstand
(`pruefstand/beschriftung.mjs`) erzwingt das; wer eine neue Beschriftung
braucht, trägt sie ins Lexikon ein, mit Bedeutung und Spalte.

### 2.4 Leer ist nicht null
Eine Sorte ohne Verdunstungsmessung hat keinen verkaufsfähigen Anteil — nicht
100 %, nicht 0 %. NULL, mit dem Kennzeichen daneben, welcher Koeffizient
fehlt. Das neue Drehbuch „die Sorte ohne Wägung" spielt genau das.

### 2.5 Die App wird nicht komplizierter
Kein neuer Reiter, keine neue Frage an den Arbeiter. Die Vorbelegung „Tage
seit dem Waschen" fragt nichts; sie schlägt vor. Der Überblick bekommt
**weniger** Karten als heute (zwei werden eine), Ursachen bekommt **eine**
Grafik oben und die Kurven eingeklappt.

### 2.6 Die Faulheitsfalle
Nicht als Ergebnis zählt: „Die Sicht ist gebaut und liefert Zahlen." Zählt:
die rote Prüfung vorher, die grüne nachher; K8–K11; die Matrix-Spalten mit
Verzerrung und Überdeckung; die Bilder jeder Karte je Gruppe; der
Begriffs-Prüfstand mit den neuen Kopfzahlen; und ein Bericht, in dem jede
Demo-Zahl von §2 des Plans wieder vorkommt — vorher, nachher, und wo sie auf
dem Bildschirm steht. Ebenso wenig zählt ein Diagramm, dessen Stützstellen
nicht exakt die sechs Horizonte aus `erg_prognose` treffen.

## 3. Der Auftrag, Phase für Phase

Die Tore stehen im Plan (§6). Hier die Kurzform; der Plan gilt.

| Phase | Tust du | Tor |
|---|---|---|
| 0 Lesen, Grundlinie | Plan, Entwürfe, Design O lesen; alle Prüfbefehle (§5) auf dem heutigen Stand; Bilder „vorher"; Formelabzug, `git diff` leer | alles grün, Drift leer |
| 1 Die Zahlen | Block 0071 **rot**; Migration 0071 aus den Entwürfen (`v_prognose`, `v_wohin`, `erg_verlauf` v2, `v_naechste_charge` neu, `v_fax_wartezeit`, Lage im Band / Spielraum, Bänder, Rate je Tag); `verdichter`, `auswertung_schritt`, `setup.sql`, `SCHEMA_ERWARTET`; Orakel `prognose.ts` + K8–K11; Simulation mit `vf_anteil_28/56`; Daten neu dumpen | `run.sh` 7/7, Gegenprobe demo **und** boese grün, Matrix im Tor, Drift = 0071 |
| 2 Überblick, Chargen | vier Kopfzahlen; Verlauf je Gruppe mit Im Lager und Verkaufsfähig; „Wohin geht der Kürbis" (Balken, Rangfolge, je Tag); „Was ist noch im Haus"; Chargen-Spalten; Lexikon; Kopfzahlen-Gegenprobe | Begriffe 0, Invarianten 0, Bilder sauber, Kopfzahlen = `erg_bilanz` |
| 3 Ursachen | Kopfzahlen der Auswahl; `Stapel`-Diagramm in Prozent; fünf Blöcke mit Zahlen zuerst, Kurven zu; Fax nach Wartezeit; Spielraum | wie Tor 2, Stapel lesbar für `invarianten.mjs` |
| 4 Halle | Vorbelegung „Tage seit dem Waschen"; das neue Drehbuch „die Sorte ohne Wägung"; `kette.mjs` | Drehbuch ok, Kette ok |
| 5 Bericht | `docs/BEFUND_RUNDE_P.md`, `docs/DESIGN_RUNDE_P.md`, `ENTSCHEIDUNGEN.md` Runde P, `FRAGEN.md` 60–62 + PDF, README | Commit, Push |

## 4. Die festen Regeln (unverändert seit Runde L)

- Entwickeln und pushen **nur** auf `claude/new-session-vrnnyo`
  (`git push -u origin claude/new-session-vrnnyo`, bei Netzfehlern 2/4/8/16 s
  Abstand). **Nie** einen Pull Request anlegen.
- Commits mit `git -c user.name="Alexander Konvalina" -c user.email="konvalina.alexander@gmail.com"`;
  Nachrichten auf Deutsch, ein Satz, der sagt, was sich für den Betrieb
  ändert; die Anhänge (Co-Authored-By, Claude-Session), die das Werkzeug
  vorgibt.
- Alles auf Deutsch: Code, Namen, Kommentare, Dokumente, Commits.
- **Kein Modellbezeichner** in Code, Kommentaren, Commits, Dokumenten.
- Die echten Excel-Dateien in `/root/.claude/uploads/` enthalten Kundennamen
  und Preise: lokal lesen ja, ins Repository **nie**.
- Nie eine Tabelle oder Spalte löschen; nie datierte Stammdaten überschreiben;
  Sichten und Funktionen mit `create or replace view … with (security_invoker = true)`.
- `setup.sql` nach jeder Migration neu bauen (`supabase/setup_bauen.sh`),
  `SCHEMA_ERWARTET` in `src/lib/version.ts` und `schema_stand()` gleich (71).
- Jede Migration mit Block in `supabase/test/pruefung.sql`; Fingerabdruck in `run.sh`.
- Lokale Datenbank: Socket `/tmp/pgsock`, Port 55432; Start
  `setsid su postgres -c '/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgdata -o "-k /tmp/pgsock -p 55432 -c listen_addresses=" -l /tmp/pg.log start'`;
  nach einem Neustart des Containers braucht die Datenbank eine halbe Minute
  (`pg_isready` abwarten); fehlt `/tmp/pgdata`, `pruefstand/demo_bauen.sh`.
  `run.sh` mit URL `postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432`
  (die Datenbank `postgres` ist Schmierpapier; `demo` und `boese` sind die
  Prüfdaten).
- `npm test` ist `node --test test/*.test.ts` — kein vitest. Keine neue
  Abhängigkeit in `package.json`.
- Die Prüfstände laufen auf festen Ports (5197 Begriffe, 5198 Invarianten,
  5199 Bilder) — sie dürfen gleichzeitig laufen, aber nie zwei desselben.

## 5. Abnahme

Die Runde ist fertig, wenn alles hier zutrifft — und **nichts davon behauptet,
sondern jedes mit Befehl und Ausgabe im Bericht steht**:

1. `supabase/test/run.sh …`: 7/7; Block 0071 war vor der Migration rot (Ausgabe im Bericht) und ist grün.
2. `npm run gegenprobe -- --db demo` und `-- --db boese`: 0 fehlgeschlagen, 0 übersprungen; K8–K11 dabei.
3. `supabase/test/simulation/matrix.sh 15`: die Spalten `vf_anteil_28` und `vf_anteil_56` mit Verzerrung ≤ 3 Prozentpunkte und Überdeckung ≥ 85 % in den Lagen ohne Sockel; die Sockel-Lage steht mit Zahl im Bericht, nicht als Ausrede.
4. `node pruefstand/beschriftung.mjs`: 0 Beanstandungen; die Kopfzahlen-Gegenprobe prüft Eingang, Ausgeliefert, **Im Lager**, **verkaufsfähig** gegen `erg_bilanz`.
5. `invarianten.mjs` auf Demo und böser Saison: 0 Verstösse, auch für das Stapeldiagramm.
6. `node pruefstand/bildschirme.mjs`: kein Überlauf, keine Konsolenfehler; Bilder jeder neuen Karte je Gruppe (Gesamt, eine Sorte, eine Charge) im Bericht, hell und dunkel, Handy und Rechner.
7. `node gegenprobe/drehbuecher/spieler.mjs NN` (das neue Drehbuch „die Sorte ohne Wägung", nächste freie Nummer): ok — ihr verkaufsfähiger Anteil ist unbekannt, kein erfundener.
8. `npm run pruefen` grün; `git diff package.json` leer.
9. Formelabzug am Ende erneut; die Differenz zum Anfang ist **genau** die Objektliste von 0071.
10. Die Demo-Zahlen aus Plan §2 stehen im Bericht mit ihrer Stelle auf dem Bildschirm (Kopfzahl, Balken, Tabelle) — und bei h = 0 sind sie identisch mit vorher.

## 6. Bericht

`docs/BEFUND_RUNDE_P.md`, in dieser Ordnung: (1) Was gemessen wurde, mit
Befehlen und Ausgaben (rot vorher, grün nachher). (2) Die neuen Sichten,
Spalte für Spalte, mit den Demo-Zahlen. (3) Die Simulation: Verzerrung und
Überdeckung der Prognose in Prozent, je Lage. (4) Die Bildschirme: was
weg ist, was neu ist, Bilder. (5) Wo du vom Plan abgewichen bist und warum.
(6) Was offen bleibt. Dazu `docs/DESIGN_RUNDE_P.md` (gebaut, nicht geplant),
der Abschnitt „Runde P" in `docs/ENTSCHEIDUNGEN.md`, die Fragen 60–62 in
`docs/FRAGEN.md` (mit `docs/fragen.html` und `docs/Offene-Fragen.pdf` neu
gebaut, `docs/pdf_bauen.mjs`), und im `README.md` die Reiter-Beschreibung.

Der letzte Absatz des Berichts ist für den Betriebsleiter: drei Sätze — was
er jetzt oben sieht (Im Lager, davon verkaufsfähig, in 4 Wochen), was der
Balken „Wohin geht der Kürbis" ihm am Saisonende sagt, und die eine
Erkenntnis aus dem Fax (Abpacken am Tag nach dem Waschen), wenn die Daten sie
tragen.
