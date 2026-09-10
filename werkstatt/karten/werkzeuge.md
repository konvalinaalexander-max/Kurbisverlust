> **Stand der Messung.** Alle Zahlen sind am Arbeitsstand `b749212` gemessen, Arbeitsbaum sauber (`git status --short` leer). Datenbanken: eigene Kopien `karte_werkzeuge` (aus `demo`), `karte_pruefung`, `karte_67`, `karte_runsh` — nach der Messung wieder gelöscht. Im Projekt wurde nichts verändert.
>
> Parallel liegt in diesem Arbeitsbaum bereits `werkstatt/` (4397 Zeilen, elf Werkzeuge, darunter `werkstatt/phase0/p0_stumpfheit.mjs`). Diese Karte ist das statische Gegenstück dazu: nicht „schlägt das Werkzeug bei einem gepflanzten Fehler an", sondern „welche Objekte fasst es überhaupt an, und woran ist es festgebunden".

---

# 0. Der wichtigste Befund zuerst: das Netz ist heute zerrissen

`supabase/test/pruefung.sql` **läuft am aktuellen Stand nicht durch.**

```
psql -d <frisch aus supabase/migrations/*.sql> -f supabase/test/pruefung.sql
→ psql:supabase/test/pruefung.sql:1854: ERROR:
  Alter der verarbeiteten Ware erwartet 15, ist -187.0
```

Der Abbruch ist **nicht** von Tageszeit oder Zeitzone abhängig, wie der Kommentar über der Stelle annimmt. Er ist strukturell:

| Stelle | Inhalt |
|---|---|
| `pruefung.sql:118` | setzt `heute_test = '2027-03-31'`, gilt bis Zeile 2792 |
| `pruefung.sql:1791` | schreibt `auftrag.start_ts = now()` (echter Kalender) |
| `pruefung.sql:1795` | schreibt `auftrag_palette.eingangsdatum = heute() - 10/-20` (Testkalender) |
| `0067`, Zeile 242/250 | `v_verarbeitung_alter` rechnet `avg(betriebstag(a.start_ts) - ap.eingangsdatum)` |
| ⇒ | `betriebstag(now())` = 2026‑09‑10 minus 2027‑03‑21/‑11 = −192/−182 → **−187**, erwartet 15 |

**Gemessene Folgekette:**

| Was ausfällt | Zahl |
|---|---|
| Behauptungen in `pruefung.sql`, die nie ausgeführt werden | **281 von 530** (53 %) |
| `do $$`-Blöcke, die nie erreicht werden | 19 von 57 |
| Stufen von `run.sh`, die nie erreicht werden | **6 von 10** (2, 3, 3b, 4, 4b, 5, 6, 6b, 7 — alles nach Stufe 1) |
| CI-Auftrag „Schema, Logik und RLS" | **rot**; gemessen: `./supabase/test/run.sh 'postgresql://…/karte_runsh'` → `rc=3` nach **32,3 s** |
| `pruefstand/luecken.sh` in der CI (nur über run.sh Stufe 6b) | läuft nicht mehr |
| Sonde 06 (Mutation) | testet **0 von 15** Verstellungen — sie prüft in Zeile 240 `pruefungLaeuft(ziel)` als Grundlinie, bekommt den Fehler, meldet „Die Prüfung schlägt schon ohne Verstellung an" und **kehrt sofort zurück** (`return raus`, Zeile 251) |

**Gegenrede.** Man könnte sagen: das ist ein Zwischenstand einer laufenden Runde, `0067` wurde vor Minuten committet, und die nächste Reparatur zieht es nach. Dagegen steht: der Commit trägt die Nachricht „zwei eingelöste Zusagen" und validiert vier Bedingungen (`alter table … validate constraint`) — er gibt sich als abgeschlossen aus. Und die Struktur des Fehlers zeigt genau die Krankheit, die diese Karte kartiert: **das schärfste Werkzeug des Projekts (Sonde 06) hängt an einem anderen Werkzeug (`pruefung.sql`) und verliert seine ganze Schärfe, sobald jenes rot wird — ohne dass irgendwo „ich kann nichts mehr finden" steht.** Es steht nur ein Befund der Klasse 1 dort, unter fünfzehn nicht gelaufenen Prüfungen.

**Zweiter Befund gleicher Art, sofort daneben:** `demo` steht auf `schema_stand() = 66`, die Migrationen auf **67**.

```
for d in demo demo64 demo65 demo66; do psql -d $d -qtAc "select schema_stand()"; done
→ 66 | 64 | 65 | 66
psql -d demo -qtAc "select count(*) from pg_proc … where proname in ('betriebstag','betriebszone')"  →  0
```

Die Sonden 01, 02, 03, 09, 10 und `invarianten.mjs` lesen `demo` (Vorgabe `--db demo`) und messen damit ein Schema, das es im Bestand nicht mehr gibt. Die Sonden 04, 05, 07, 08 bauen sich über `frischesSchema()` selbst ein Schema **67**. Ein einziger Lauf `node pruefwerk/lauf.mjs` misst also **zwei verschiedene Schemafassungen gleichzeitig**, und nichts sagt es.

---

# 1. Bestand: was es gibt, wie gross, wie lange, wo es läuft

`wc -l` über alle Werkzeugdateien; Laufzeiten selbst gemessen.

| Werkzeug | Zeilen | Braucht | gemessene Laufzeit | CI |
|---|---:|---|---|---|
| `supabase/test/pruefung.sql` | 3648 | psql, frisches Schema | 29,7 s (bis Abbruch) | **ja** (über run.sh) |
| `supabase/test/run.sh` | 346 | psql, eigene DB (löscht `public`) | 32,3 s bis rc=3; vollständig früher ~mehrere Min. | **ja** |
| `supabase/test/fingerabdruck.sql` | 81 | psql | < 1 s, 2633 Zeilen | **ja** (in run.sh) |
| `supabase/test/last.sql` | 97 | psql | Teil von Stufe 6 | **ja** |
| `supabase/test/stub_supabase.sql` | 37 | psql | < 1 s | **ja** |
| `supabase/test/simulation/` (4 Dateien) | 439 | psql, eigene DB | 9 Lagen × N Saisons, Minuten bis Stunden | **nein** |
| `pruefstand/luecken.sh` | 126 | psql + `src/` | **0,84 s** | ja, nur über run.sh Stufe 6b |
| `pruefstand/kette.mjs` | 523 | Playwright + Vite + Fixtures | Minuten | **nein** |
| `pruefstand/kette_pruefen.sh` | 287 | psql + `setup.sql` + `kette_erfasst.json` | Minuten | **nein** |
| `pruefstand/bildschirme.mjs` | 318 | Playwright + Vite + Fixtures | > 5 Min (180 Aufnahmen) | **ja** |
| `pruefstand/beschriftung.mjs` | 387 | dito | Minuten | **ja** |
| `pruefstand/attrappe.mjs` + `postgrest.mjs` | 198 | — (Bibliothek) | — | ja (mittelbar) |
| `pruefstand/daten_dumpen.sh` / `demo_bauen.sh` | 93 | psql | Sekunden | **ja** |
| `pruefwerk/` (10 Sonden + 5 Module) | 3254 | psql, `demo`, viele Wegwerf-DBs | 01: 6,2 s · 03: 0,72 s · 04: 0,08 s · 09: **18,1 s** · 06: „lang" | **nein** |
| `test/*.test.ts` (9 Dateien) | 807 | node | **0,84 s**, `# tests 84 # pass 84` | **ja** |
| `npm run build` (tsc -b + vite) | — | node | — | **ja** |

**Umfang gesamt:** Werkzeuge 10 892 Zeilen gegen Produkt 35 556 Zeilen (`src/` 11 235 + `supabase/migrations/` 24 321) = **Verhältnis 0,30**.

**Documentationsabweichung, gemessen:** `docs/PROMPT_RUNDE_M.md:22` und `:576` sagen „81 Modultests", `docs/ABMACHUNGEN.md:57` sagt „76 Tests", `docs/PROMPT_PRUEFWERK.md:468` sagt „76 Tests". Gemessen: **84**. Und der Kopfkommentar von `pruefwerk/sonden/09_einheiten.mjs` behauptet, `pruefstand/beschriftung.mjs` sei „Teil von `npm run pruefen`" — `package.json` sagt `pruefen = typecheck && test && build`; beschriftung.mjs ist **nicht** darin.

---

# 2. Abdeckungsmatrix — Datenbankobjekte × Werkzeuge

Gemessen mit einem Wortgrenzen-Abgleich aller 261 Objektnamen (28 Tabellen, 63 Sichten, 38 gespeicherte Sichten, 39 Funktionsnamen/42 Funktionen, 93 Indexe) gegen den Volltext jedes Werkzeugs:

```
psql -d karte_werkzeuge -tAc "select c.relkind::text||'|'||c.relname from pg_class c
  join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
  and c.relkind in ('r','v','m','i')" > objekte.txt
node matrix.mjs objekte.txt   # (Skript im Scratchpad, RegExp mit Wortgrenzen je Werkzeuggruppe)
```

## 2.1 Namentliche Abdeckung

| Objektart | gesamt | `pruefung.sql` | `run.sh` | `simulation` | `luecken.sh` | Sonden 01–10 (max. eine) | in `src/` |
|---|---:|---:|---:|---:|---:|---:|---:|
| Tabelle | 28 | **28** | 10 | 13 | 11 | 13 (Sonde 03) | 25 |
| Sicht (`v_*`) | 63 | **57** | 5 | 3 | 0 | 7 (Sonde 07) | 10 |
| Gespeicherte Sicht | 38 | 9 | 0 | 0 | 0 | 3 (Sonden 05/08) | 30 |
| Funktion | 39 | 25 | 4 | 3 | 1 | 3 (Sonde 06) | 19 |
| Index | 93 | 0 | 0 | 0 | 0 | 0 | 0 |

Sonden einzeln, Zahl der namentlich berührten Objekte:

| | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Sichten | 1 | 1 | 2 | 1 | **5** | 1 | **7** | 3 | 0 | 1 |
| Gesp. Sichten | 1 | 1 | 1 | 1 | 3 | 2 | 1 | 3 | 0 | 0 |
| Funktionen | 1 | 1 | 0 | 0 | 2 | 3 | 1 | 1 | 0 | 1 |

**Wichtige Einschränkung dieser Matrix:** ein Name-Treffer heisst „das Werkzeug spricht das Objekt an", nicht „es prüft es". Umgekehrt gilt: Sonde 09 nennt **kein** Objekt namentlich und prüft trotzdem 401 Spalten über 129 Objekte — sie geht über den Katalog. `fingerabdruck.sql` nennt ebenfalls kein Objekt und deckt strukturell **alle** ab. Die Matrix zeigt also, wer **gezielt** hinsieht, nicht wer irgendwie darübergeht.

## 2.2 Die weissen Flecken — von *keinem* Werkzeug namentlich angefasst

### a) Sichten (6 von 63)

| Sicht | in `src/`? | Bemerkung |
|---|---|---|
| `v_koeff_roh_verdunstung` | nein | Zwischenstufe der Verdunstungsschätzung |
| `v_koeff_verdunstung_geschaetzt` | nein | dito |
| `v_koeff_unsicherheit` | nein | **die Quelle jedes ausgewiesenen Bandes** |
| `v_schimmel_modell_rechnen` | nein | die Anpassung des Verderbsmodells |
| `v_plausibilitaet_0054_zusatz` | nein | Auffälligkeitszweig |
| `v_plausibilitaet_0064_zusatz` | nein | Auffälligkeitszweig |

Drei davon (`v_koeff_*`, `v_schimmel_modell_rechnen`) sind genau die Stufen, an denen aus Messungen **Schätzer** werden. Sonde 04 (das Orakel) prüft die Kaskade — aber sie liest `r`, `f`, `a0`, `a_klein_n`, `a_gross_n`, `a_fax` **aus `mv_kaskade` heraus** (Zeile 76–81) und rechnet nur nach, ob die Ströme daraus richtig kombiniert werden. Ein Fehler in der Schätzung der Koeffizienten selbst kommt durch jede der zehn Sonden ungehindert durch.

### b) Gespeicherte Sichten (3 von 38 nirgends genannt, 29 von 38 ohne jede Behauptung)

Nirgends genannt, auch nicht in `src/`: `mv_hochrechnung`, `mv_schimmel_punkte`, `mv_sortier_eingang`.

Ohne Behauptung in `pruefung.sql` (29 von 38): `erg_ausgang, erg_ausschuss, erg_datenlage, erg_datenqualitaet, erg_durchsatz, erg_fax, erg_gebinde, erg_gewichte, erg_kaliber, erg_koeff_ausschuss, erg_koeff_nebenkanal, erg_koeff_ueberfuellung, erg_koeff_verdunstung, erg_kohorte, erg_kurve, erg_lieferung, erg_marge, erg_massenbilanz, erg_modell, erg_naechste_charge, erg_plausibilitaet, erg_punkte, erg_selektion, erg_verarbeitung_alter, erg_wiegung, mv_hochrechnung, mv_schimmel_modell, mv_schimmel_punkte, mv_sortier_eingang`.

**Gegenrede:** Sonde 01/1b vergleicht jede `erg_*`-Sicht generisch mit ihrer Quellsicht, das deckt 29 davon ab. Aber: es deckt nur die Frage „stimmt die Kopie mit dem Original überein", nie „ist das Original richtig". Und der Vergleich lässt eine still fallen (§4.1).

### c) Funktionen (14 von 39 nirgends genannt)

| Funktion | Art | wird von wem gebraucht | messbar ausgeführt bei `pruefung.sql`? |
|---|---|---|---|
| `korrekturfenster()` | sql, immutable | **10 RLS-Regeln auf 5 Erfassungstabellen** | **nein** |
| `ist_beteiligt(bigint)` | security definer | RLS `auftrag.auftrag_aendern` | **nein** |
| `palox_station(text)` | sql | Sicht `v_palox_stand` | **nein** |
| `anteil_plausibel(...)` | sql | 4 Sichten (`v_schimmel_punkte`, `v_ausschuss_beobachtung`, `v_schimmel_beobachtung`, `v_fax_beobachtung`) | ja |
| `ist_admin()`, `ist_aktiv()` | security definer | RLS überall | ja |
| `handle_new_user`, `rolle_schuetzen`, `auftrag_ende_setzen`, `auftrag_schema_setzen`, `ausschuss_netto_setzen`, `schimmel_netto_setzen`, `auswertung_veraltet` | Auslöser (plpgsql) | Trigger | ja (mittelbar) |
| `lauf_neu_klassieren` | plpgsql | Umklassierung | ja |

Ausführung gemessen mit:
```
alter database karte_pruefung set track_functions='all';
… Migrationen … ; select pg_stat_reset(); psql -f supabase/test/pruefung.sql
select proname from pg_proc … where oid not in (select funcid from pg_stat_user_functions)
```
→ 35 von 42 Funktionen wurden ausgeführt; nicht ausgeführt: `ausgang_uebernehmen, auswertung_wenn_veraltet, demo_daten_entfernen, ist_beteiligt, klassiere, korrekturfenster, palox_station, sortierschema_festlegen, sortierschema_fuer`. **Vorbehalt:** `klassiere` steht in dieser Liste, obwohl `pruefung.sql:55–62` acht Behauptungen darüber macht — SQL-Funktionen werden vom Planer eingebettet und dann nicht gezählt. Die Liste ist also eine **obere** Schranke des Ungeprüften; die Schnittmenge „weder genannt noch gezählt" (`ist_beteiligt`, `korrekturfenster`, `palox_station`) ist die belastbare.

**Der schärfste Fleck davon:** `korrekturfenster()` gibt `interval '12 hours'` zurück und ist die einzige Stelle, an der steht, wie lange ein Arbeiter eine Messung berichtigen darf. Sie hängt an zehn Regeln (`auftrag_palette_korrigieren`, `…_zuruecknehmen`, `schimmel_messung_*`, `ausschuss_messung_*`, `verdunstung_wiegung_*`, `ausgang_*`). **Kein Werkzeug erwähnt sie, keine Behauptung prüft sie, kein Prüfstand fährt die Grenze an.** Weder ein Fall, der innerhalb der 12 Stunden durchkommen muss, noch einer, der nach 13 Stunden abprallen muss.

### d) Indexe (93 von 93 nirgends namentlich)

Kein Werkzeug nennt einen Index. Aber: `fingerabdruck.sql` liest `pg_indexes.indexdef` und erzeugt **93 INDEX-Zeilen**, die zwischen Migrationsbau, `setup.sql`-Bau und Aktualisierungspfad verglichen werden. Was damit **nicht** geprüft wird: ob ein Index je benutzt wird.

Gemessen auf einem vollen `pruefung.sql`-Lauf:
```
select count(*) filter (where idx_scan>0), count(*) from pg_stat_user_indexes where schemaname='public'
→ 26 | 88
```
**26 von 88 verfolgten Indexen wurden während des ganzen Datenbanktests je gebraucht.** Nie berührt u. a.: alle 12 `erg_*`-Indexe (`erg_charge_pk`, `erg_verlauf_pk`, `erg_verlust_pk`, …), `mv_kaskade_pk`, `mv_kaskade_charge`, `mv_hochrechnung_charge`, `lieferung_charge`, `lieferung_datum`, `lieferung_sorte`, `ausgang_zeile_*` (5 Stück), `auftrag_status_start_ts_idx`. **Vorbehalt (wie im Auftrag verlangt):** `idx_scan = 0` auf einem Testlauf heisst „der Test hat ihn nicht gebraucht", nicht „der Betrieb braucht ihn nicht" — die richtige Messung ist ein Dashboard-Lauf plus Import auf der Demogrösse. Was die Zahl hier belegt, ist bescheidener und trotzdem hart: **62 Indexe kosten bei jedem Schreiben in `pruefung.sql` Zeit und bringen dort nie etwas.**

### e) Tabellen und Spalten

Alle 28 Tabellen kommen in `pruefung.sql` vor. Auf Spaltenebene wird es dünner:

| Werkzeug | Tabellen im Blick | Spalten im Blick | von 266 Spalten der 28 Tabellen |
|---|---:|---:|---|
| `pruefstand/luecken.sh` (`TABELLEN=`) | 11 | 126 | 47 % — abzüglich **37 namentlicher Ausnahmen** |
| Sonde 03 (`ERFASSUNG=`) | 13 | 152 | 57 % — abzüglich Regex `VERWALTUNG` (9 Namen) |
| `fingerabdruck.sql` | 28 + 63 Sichten | **1096 SPALTE-Zeilen** | strukturell vollständig für Tabellen und Sichten |

**Loch im Fingerabdruck, gemessen:** `fingerabdruck.sql` liest Rechte aus `information_schema.role_table_grants`. Materialisierte Sichten stehen dort nicht:
```
select count(*) from information_schema.role_table_grants where table_schema='public' and table_name like 'erg\_%'  → 0
select count(*) from pg_class … where relkind='m' and relacl is not null                                            → 38
```
Der Fingerabdruck enthält **892 RECHT-Zeilen und nicht eine einzige für die 38 gespeicherten Sichten**, obwohl alle 38 eine Rechteliste tragen. Ein `grant select on erg_charge to authenticated`, das beim Verdichten nach `setup.sql` verlorengeht oder zu weit gefasst wird, ist für die Zusage „nicht zu unterscheiden von frisch eingerichtet" unsichtbar. Aus demselben Grund fehlen auch die Spalten der 38 gespeicherten Sichten in den 1096 SPALTE-Zeilen (`information_schema.columns` kennt sie nicht) — die sind allerdings über die md5 der Definition mitabgedeckt, die Rechte nicht.

Aufbau des Fingerabdrucks, gemessen (`psql -f supabase/test/fingerabdruck.sql | awk '{print $1}' | sort | uniq -c`):

| SPALTE | RECHT | BESCHREIBUNG | BEDINGUNG | INDEX | REGEL | ANSICHT | FUNKTION | GESPEICHERT | AUSLOESER |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1096 | 892 | 176 | 131 | 93 | 78 | 63 | 42 | 38 | 23 |

Nicht im Fingerabdruck: Sequenzen, Erweiterungen, `alter default privileges`, Tabellenstatistikziele, Speicherparameter.

## 2.3 Rechte und RLS — die grösste zusammenhängende weisse Fläche

```
select count(*) from pg_policies where schemaname='public'                 → 78
select array_to_string(roles,','), count(*) … group by 1                   → authenticated | 78
grep -c "set local role\|set role" supabase/test/pruefung.sql              → 2 (Zeile 622 und 654)
für jede der 78 Policies: grep -qF "<policyname>" supabase/test/pruefung.sql → 0 Treffer
```

* **78 Regeln, 0 davon namentlich in irgendeinem Werkzeug.**
* **Ein einziger Block** in 3648 Zeilen läuft als `authenticated` (Zeilen 622–654, **0,9 % der Datei**). Er versucht vier Schreibvorgänge: `insert into charge` (muss scheitern), `update profil set rolle` (muss scheitern), `insert into schimmel_messung` (muss gelingen), `insert into sortier_lauf` (muss scheitern). Damit bekommen höchstens vier bis sechs der 78 Regeln je einen Fall.
* **Alles andere in `pruefung.sql` läuft als `postgres` — Superuser, RLS abgeschaltet.** Wer die Zusagen dort liest, liest Zusagen über eine Datenbank ohne Zugriffsschutz.
* Die Rolle `anon` (nicht angemeldet) wird von **keinem** Werkzeug angenommen. `pruefung.sql:1419` liest nur `pg_roles.rolconfig` für `anon` — das ist eine Schema-, keine Verhaltensprüfung.
* **Auch die Bildschirm-Prüfstände können RLS nicht sehen.** `pruefstand/attrappe.mjs` beantwortet jede REST-Anfrage aus den JSON-Abzügen, die `daten_dumpen.sh` als `postgres` gezogen hat. Die Attrappe kennt keine Rollen: `authAntwort()` gibt für `wer: 'arbeiter'` eine formal gültige, aber ausgedachte Sitzung aus, und `restAntwort()` filtert danach **nicht**. Ein Arbeiter sieht im Prüfstand daher jede Zeile — auch die, die ihm die echte Datenbank verweigern würde. Umgekehrt: eine Regel, die versehentlich zu eng ist und dem Arbeiter seine eigenen Messungen verbirgt, fällt im Prüfstand nie auf.

Verteilung der Regeln nach Befehl (zur Grösse des Ungeprüften): SELECT 28, ALL 14, UPDATE 13, INSERT 12, DELETE 11.

---

# 3. `pruefung.sql` im Einzelnen

```
grep -cE '^[[:space:]]*assert[[:space:]]' supabase/test/pruefung.sql   → 530
grep -c '^do \$\$' supabase/test/pruefung.sql                          → 57
wc -l                                                                  → 3648
```

**530 Behauptungen in 57 `do`-Blöcken, 3648 Zeilen.** Alle 530 stehen in Blöcken; es gibt keine freistehende.

Zuordnung: für jedes Objekt wurde gezählt, in wie vielen `do`-Blöcken sein Name vorkommt und wie viele `assert` in diesen Blöcken stehen. Die Zahl überschätzt (ein Block mit 40 asserts erbt alle 40 an jedes darin genannte Objekt), aber die **Null** ist belastbar.

## 3.1 Objekte mit den meisten Behauptungen um sich herum

| asserts im Block | Objekt | Blöcke |
|---:|---|---:|
| 358 | `auswertung_aktualisieren()` | 26 |
| 296 | `auftrag` | 21 |
| 283 | `charge` | 16 |
| 269 | `lieferung` | 12 |
| 216 | `auftrag_palette` | 12 |
| 196 | `v_auftrag_masse` | 10 |
| 195 | `v_plausibilitaet` | 15 |
| 186 | `v_hochrechnung_basis` | 7 |
| 177 | `v_verlust_ranking` | 11 |
| 174 | `v_hochrechnung` | 8 |
| 154 | `v_saisonbilanz` | 12 |
| 154 | `heute()` | 5 |
| 141 | `v_koeff_gebinde` | 5 |
| 108 | `erg_verlust` | 3 |
| 102 | `erg_charge` | 4 |

## 3.2 Objekte, die in keinem einzigen assert-Block vorkommen

* **Sichten (6 von 63):** die sechs aus §2.2a.
* **Gespeicherte Sichten (29 von 38):** die Liste aus §2.2b. Nur `erg_bilanz`, `erg_charge`, `erg_verlust`, `erg_verlauf`, `erg_ueberfuellung`, `mv_kaskade`, `mv_auftrag_masse`, `mv_kaliber`, `mv_sortier_lauf_masse` tragen Behauptungen.
* **Funktionen (14 von 39):** die Liste aus §2.2c.
* **Tabellen: 0 von 28.** Jede Tabelle wird in mindestens einem assert-Block berührt.

## 3.3 Was `pruefung.sql` per Bauart nicht finden kann

| Fehlerklasse | Warum sie durchkommt |
|---|---|
| Rechtefehler | 0,9 % der Datei läuft als `authenticated`, 99,1 % als Superuser |
| Leistungsfehler | keine einzige Zeitmessung; Tempo steckt in `run.sh` Stufe 5/6, hinter dem Abbruch |
| Nebenläufigkeit | ein einziger `psql`-Prozess, eine Sitzung |
| Zeitzonenfehler | `heute_test` friert `heute()` ein; `betriebstag()`/`betriebszone()` (0067) haben **null** Behauptungen (`grep -c betriebszone supabase/test/pruefung.sql` → 0) |
| Falscher Schätzer | prüft Rechenwege gegen von Hand gesetzte Erwartungen, nie gegen eine bekannte Wahrheit über viele Ziehungen (das tut nur `simulation/`) |
| Fehler nur bei grossen Datenmengen | die Fixtur ist eine Mini-Saison; die dreifache Saison steckt in `last.sql`/Stufe 6 |
| Anzeigefehler | kennt keine Oberfläche |

---

# 4. Die zehn Sonden — Regel aus dem Quelltext, nicht aus dem Kommentar

Für jede: was der Code tatsächlich prüft, welche Fehlerklasse per Bauart durchkommt, und wie stark die Selbstprobe ist.

Stärke der Selbstprobe, maschinell gemessen (`grep` im Rumpf ab `export async function selbstprobe`):

```
01  ruft laufen(): JA   baut Welt: JA
02  ruft laufen(): NEIN baut Welt: NEIN
03  ruft laufen(): JA   baut Welt: NEIN
04  ruft laufen(): JA   baut Welt: JA
05  ruft laufen(): NEIN baut Welt: JA
06  ruft laufen(): NEIN baut Welt: JA
07  ruft laufen(): NEIN baut Welt: NEIN
08  ruft laufen(): NEIN baut Welt: NEIN
09  ruft laufen(): JA   baut Welt: JA
10  ruft laufen(): NEIN baut Welt: NEIN
```

**4 von 10 Selbstproben führen die Sonde aus, die sie prüfen sollen. 6 prüfen etwas anderes** — bei 02 und 10 nur den Textleser, bei 05, 07 und 08 nur den Massstab, bei 06 nur den Fingerabdruck. Eine Sonde, deren `laufen()` durch eine Umbenennung nichts mehr findet, meldet in diesen sechs Fällen „Selbstprobe: ok".

## Sonde 01 — Herkunft (253 Zeilen)

**Regel (Quelltext).** Vier Prüfungen:
1a. `verlangt()` liest per Textleser mit Klammerzählung jedes `.from('literal')` in `src/` und daraus `.select('a, b')`, `.insert({a:…})`, `.update({…})`; jede so gefundene Spalte muss in `pg_attribute` für `relkind in ('r','v','m','p')` existieren.
1b. Für jede `relname like 'erg\_%'` mit `relkind='m'`: Quelle über `regexp_replace(pg_get_viewdef(…), '(?s).*\sFROM\s+([a-z0-9_]+).*', '\1')` bestimmen; wenn sie mit `v_` beginnt, md5 über `to_jsonb(t)::text` beider Seiten vergleichen.
1c. `relkind='m' and not relispopulated`.
1d. Regex `/titel="Ausgeliefert"[\s\S]{0,240}?art="gemessen"/` auf `src/pages/Ueberblick.tsx` **und** `v_saisonbilanz.vorlauf_kg > 0`.

**Gemessene Leistung von 1a:**
```
.from('literal') in src/            → 91
.from( mit Variable/Template        →  6 echte (+2 Fehltreffer Array.from)
.select('*')                        → 26   (bewusst übersprungen)
.select mit eingebetteter Beziehung →  2   (bewusst übersprungen)
gelesene Verlangen                  → 174 (101 liest, 66 schreibt, 7 ändert) über 24 Tabellen/Sichten
```

**Was durchkommt.**
* Die **sechs dynamischen `.from()`** sind unsichtbar: `src/auswertung/daten.ts:277` und `:287` (der ganze Dashboard-Lader, der jede `erg_*`-Sicht über eine Variable holt), `src/arbeit/Korrektur.tsx:120, :135, :143` (die Korrekturmaske **liest, ändert und löscht** über einen Variablen-Tabellennamen), `src/betrieb/AusgangImport.tsx:55`. Von der ganzen Korrekturmaske sieht Sonde 01 nichts — und Sonde 03 und `luecken.sh` erben diese Blindheit, weil beide `verlangt()` bzw. denselben Textansatz benutzen.
* **26 × `select('*')`** heisst: die Spalten, von denen diese Lesevorgänge abhängen, werden nie gegen das Schema geprüft.
* **1b lässt still fallen.** Gemessen an Schema 67:
  ```
  29 der 30 erg_-Sichten liefern eine v_-Quelle
   1 nicht:  erg_verlauf -> s      (Unterabfrage-Alias)
  ```
  `if (!p.quelle || !p.quelle.startsWith('v_')) continue` — **ohne Zähler, ohne Meldung.** Die Sonde meldet „0 Sichten weichen ab" über 30 Sichten und hat 29 verglichen. `erg_verlauf` ist die Quelle der Verlaufsgrafik.
* **1b bricht die ganze Sonde ab, wenn eine gespeicherte Sicht ungefüllt ist** — und genau das ist der Fall, den 1c melden soll, das aber erst danach kommt. Beleg aus dem abgelegten Lauf `pruefwerk/befunde/befunde.json` (22:24): `01_herkunft` mit `fehler: ERROR: materialized view "erg_kurve" has not been populated`. Alle vier Prüfungen fallen dann aus; der Läufer schreibt „abgebrochen" statt „1c: eine Sicht ist ungefüllt".
* 1d ist an einen **deutschen Anzeigetext** und ein **Attributformat** gebunden (§6).

**Aktueller Lauf gegen Schema 67:** 0 Befunde, 6,2 s.

## Sonde 02 — Bezugsgrössen (323 Zeilen)

**Regel.** Findet jedes `prozent(` in `src/**/*.{ts,tsx}`, zerlegt das erste Argument mit `/^(?:(.*?)\s*\?\s*)?(.+?)\s*\/\s*(.+?)(?:\s*:\s*null)?$/s` in Wache/Zähler/Nenner, holt eine Beschriftung aus ±400 Zeichen Umfeld über `titel|unter|xTitel|yTitel` oder `>Text<`. Dann: 2b jeder ungeschützte Nenner ist ein Befund; 2c Beschriftung mit `/(des|vom|am|der)\s+Eingang(s|smasse)?/` bei nicht-„eingang"-Nenner; 2e Zähler, dessen Stamm ein `%_bekannt` in `information_schema.columns` hat, ohne „bekannt" in ±500 Zeichen; 2d rechnet vier Lesarten der Verlustquote aus.

**Gemessen (aktuell):**
```
31 prozent(-Stellen:  11 bewacht · 15 fertiger Anteil · 5 "Form unbekannt"
 7 Stellen ohne erkannte Beschriftung
```

**Was durchkommt.**
* **5 Stellen „Form unbekannt"** erzeugen **keinen Befund** — sie landen nur in `pruefwerk/befunde/bezugsgroessen.md`. Der Kopfkommentar behauptet ausdrücklich das Gegenteil („wird als ‚Form unbekannt' gemeldet statt stillschweigend übergangen"). Gemeldet wird es in einer Datei, nicht im Lauf.
* **7 Stellen ohne Beschriftung** überspringen 2c und 2e stumm (`if (!a.beschriftung || !a.nenner) continue`).
* **Jede Prozentzahl, die nicht durch `prozent(` geht, ist unsichtbar.** Grobmessung: `grep` nach `%`-Literalen in `src/` ausserhalb von `prozent(` findet 28 weitere Stellen — ob davon welche eine Zahl formatieren, hat die Sonde nie geprüft (Schätzung, kein Befund).
* Der Ort des Befunds 2d ist mit `zeile: 66` fest verdrahtet.
* 2e entscheidet über ein **Textfenster von ±500 Zeichen**: steht die `_bekannt`-Prüfung 501 Zeichen entfernt, gibt es einen Fehlalarm; steht das Wort „bekannt" zufällig in einem Kommentar in der Nähe, gibt es einen Fehlbefund in die andere Richtung.
* **Selbstprobe prüft nur `stellen()` an drei erfundenen Zeilen.** Wenn 2b/2c/2e nie mehr anschlagen könnten, sagt sie trotzdem „ok".

## Sonde 03 — Erfassung (196 Zeilen)

**Regel.** `ERFASSUNG` = 13 fest genannte Tabellen (152 Spalten von 266). 3a: Spalte gilt als tot, wenn `\bspalte\b` in **keinem** Text von (alle Sicht-/Funktionsdefinitionen + `src/**` + `supabase/**` ohne `migrations/`) vorkommt; Ausnahme `VERWALTUNG` (9 Namen). 3b: Spalte ist „weich", wenn nicht `attnotnull`, ohne Vorgabe, nicht Verwaltung, **und** über `verlangt()` als geschrieben erkannt; die gefährliche Teilmenge sind die, die eine Sicht als `COALESCE(alias.spalte, 0)` liest, wobei `alias` im selben Text an die Tabelle gebunden sein muss. 3c: `erg_charge.ueberzaehlung_kg > 0` ohne passende Art in `v_plausibilitaet`.

**Gemessen (Schema 67):** 1 Befund — „31 Felder verlangt die Maske, die Datenbank lässt sie leer", 0,72 s. 3a und 3c schweigen.

**Was durchkommt.**
* 3a sucht **Wortvorkommen**. Eine Spalte, die nur über `select('*')` mitkommt (26 Stellen) und im Frontend über einen berechneten Namen angesprochen wird, gilt als lebendig, obwohl niemand sie liest — und umgekehrt. Die Gegenrede steht im Befundtext selbst.
* 3b erbt die Blindheit von `verlangt()`: die 66 erkannten Schreibungen decken die Korrekturmaske (`update`/`delete` über Variable) nicht ab.
* **Die Selbstprobe hat eine eingebaute Zeitbombe:** `return Number(s.n) === 1 && r.length > 0`. Sie verlangt, dass die Sonde **mindestens einen Befund liefert**. Heute sind es genau 1. Wird der 31‑Felder-Befund repariert, meldet der Läufer für 03 **„STUMPF"** und beendet sich mit `exit 2` — obwohl die Sonde in Ordnung ist. Eine Selbstprobe, die verlangt, dass das Programm fehlerhaft bleibt.

## Sonde 04 — Orakel (324 Zeilen)

**Regel.** Ein zweites Rechenwerk in JavaScript, aus `docs/ABLAUF.md` nachgebaut. Es liest je Zeile von `mv_kaskade` (`where m0 > 0`) die Grössen `m0, r, alter_tage, a0, f, a_klein_n, a_gross_n, a_fax` und vergleicht neun Ströme mit `d = |soll−ist| / max(|soll|,1) > 1e-6`. Dazu: 4b verkaufsfähiger Anteil und `m0 = geliefert / anteil` (Schwelle 1e‑4), 4c Zahl der Portionen mit rohem Anteil < 0,25, 4d `∂m1/∂r` und `∂f/∂η` gegen zentrale Differenzenquotienten (h = 1e‑7, Schwelle 1e‑4), 4e `f` gegen `1 − exp(−exp(lnλ' + k·ln max(t,1)))`, 4f `alter_tage > t_max` ohne `f_extrapoliert`, 4g Abstand zu den drei Schutzgrenzen.

**Gemessen (Schema 67):** 1 Befund (Klasse 1, 4g): kleinster verkaufsfähiger Anteil 0,671, Abstand zum Boden **0,42**; grösste Rate weit unter dem Deckel; grösster Sockel 0. 0,08 s.

**Was durchkommt.**
* **Der Schätzer.** Das Orakel nimmt `r`, `f`, `a0`, `a_klein_n`, `a_gross_n`, `a_fax` als gegeben aus der Datenbank. Ein Fehler in `v_koeff_verdunstung`, `v_koeff_unsicherheit`, `v_schimmel_modell_rechnen` (alles weisse Flecken, §2.2a) wandert unbemerkt durch die geprüfte Kaskade.
* **Portionen mit `m0 = 0`** werden gar nicht gelesen.
* **Zirkularitätsrisiko.** Das Orakel wurde nach `docs/ABLAUF.md` gebaut. Ob `ABLAUF.md` je nachträglich an den Code angepasst wurde, lässt sich hier nicht entscheiden (§8) — genau die Falle, die der Auftrag verbietet („Ein Orakel nachjustieren, bis es mit dem Code übereinstimmt").
* Der Vergleich ist **relativ zu `max(|soll|,1)`**: bei einem Strom von 0,5 kg entspricht die Schwelle 1e‑6 kg absolut, bei 100 000 kg 0,1 kg. Für die Bilanzgrössen ist das eng, für Kleinströme ungewöhnlich streng — kein Fehler, aber eine ungleichmässige Empfindlichkeit.
* **Die Selbstprobe ist die stärkste im Bestand:** sie ersetzt `mv_kaskade` auf einer Kopie durch eine Tabelle mit `klein_kg = m1 * a_klein_n` und verlangt, dass `laufen()` das findet.

## Sonde 05 — Metamorph (288 Zeilen)

**Regel.** Acht Prüfungen auf einer Kopie `pw_meta`: 1 Erhaltung (`|m0 − Σ7| > greatest(m0·1e-6, 0.01)`, `limit 5`), 2 Rückrechnung (`|verkaufsfaehig_kg − geliefert_kg| > greatest(geliefert·1e-4, 0.05)`), 3 Zerlegung über `erg_verlust`, Gruppen `gesamt/sorte/schlag/charge`, Schwelle `greatest(|kg|·1e-4, 0.5)`, 4 Unwissen als 0 im Verlust, 5 `|bilanz_rest_kg| > max(eingang·1e-5, 1)`, 6 **Textprüfung** der Definition von `v_lieferung_kohorte` auf `'verlust'` im `buch`-Filter, 7 Idempotenz über md5 von `erg_charge`, 8 Zeitpfeil: `heute_test` sieben Tage vorstellen, drei Felder dürfen nicht kleiner werden.

**Was durchkommt.**
* **Die Selbstprobe ruft `laufen()` nicht auf.** Sie legt eine Tabelle `pw_probe` an und führt **eine im Selbstprobenrumpf noch einmal ausgeschriebene Kopie** der Erhaltungsabfrage aus. Wäre in `laufen()` `mv_kaskade` in `mv_kaskade_neu` umbenannt oder die Abfrage kaputt, liefe `laufen()` auf einen Fehler oder auf leer — die Selbstprobe sagt trotzdem „ok". Das ist genau der Bauplan, an dem Runde L gescheitert ist, nur eine Ebene höher.
* Die Selbstprobe legt zusätzlich eine Sicht `v_kaskade` an, die danach von niemandem gelesen wird — toter Code in einem Prüfwerkzeug.
* Prüfung 6 hängt an **zwei Regexen auf den Text der Sichtdefinition** (`buch\s*=\s*ANY\s*\(ARRAY\[…'verlust'` bzw. `buch\s+in\s*\(…'verlust'`). Wird derselbe Filter als `buch <> 'verlust'` oder über eine Hilfstabelle geschrieben, meldet die Sonde einen Fehler, den es nicht gibt — oder übersieht einen, den es gibt.
* Prüfung 8 verstellt `heute_test` und **setzt es nicht zurück**; die Kopie `pw_meta` bleibt sieben Tage in der Zukunft stehen. Für eine Wegwerf-Datenbank folgenlos, aber jede spätere Messung auf `pw_meta` misst etwas anderes als angenommen.
* `limit 5` / `limit 20` in den Abfragen: die **Zahl** der Verletzungen wird nie vollständig gemessen, nur die Grösse der schlimmsten.

## Sonde 06 — Mutation (355 Zeilen, `lang = true`)

**Regel.** 15 Verstellungen als `{alt, neu}`-Textpaare. Für jede: Migrationen in ein Wegwerf-Verzeichnis kopieren, **die letzte Migration suchen, die `alt` enthält**, dort `replaceAll(alt, neu)`, Schema bauen, Demodaten aus `demo` per `pg_dump --data-only` einspielen (mit `session_replication_role = replica`), `auswertung_aktualisieren()`, dann: `pruefung.sql` läuft? → gefangen; Invariante (ohne „Unwissen") verletzt? → gefangen; Fingerabdruck über `['erg_charge','v_saisonbilanz','mv_kaskade']` unverändert? → ohne Wirkung; sonst → überlebt.

**Gemessen: alle 15 Ankertexte kommen noch vor.**
```
sockel-auf-m0 … im-haus-alles   → 0065_entsorgtes_verlaesst_das_lager.sql  (13 Stück)
teilbetrag-null, netto-erfinden → 0066_kein_kilo_aus_einer_luecke.sql       (2 Stück)
15 Verstellungen: 15 finden ihren Anker, 0 nicht mehr
```
Die Reparatur aus Runde L („die Sonde sucht die Migration selbst") **hält also**. Aber:

**Was durchkommt.**
* **Heute testet sie null von fünfzehn**, weil die Grundlinie `pruefungLaeuft()` rot ist (§0).
* **Die Suche schützt nur gegen den halben Fehler.** Sie findet die letzte Migration, die den Text *enthält*. Sie erkennt **nicht**, wenn eine spätere Migration dasselbe Objekt neu schreibt, ohne den Text zu enthalten — dann wird 0065 verstellt und 0067 überschreibt es, und das Ergebnis heisst „ohne Wirkung" statt „nicht mehr prüfbar". Der Kopfkommentar sagt das ausdrücklich; es bleibt trotzdem eine stille Entwertung. Konkret jetzt relevant: **0067 schreibt `v_verdunstung_messung`, `v_wiegung_kennzahl`, `v_auftrag_masse`, `v_auftrag_wasch_paletten`, `v_verarbeitung_alter`, `heute()`, `betriebstag()`, `betriebszone()` neu — und keine der 15 Verstellungen zielt auf eine dieser acht Stellen.** Die gesamte Logik von 0067 hat null Mutationsabdeckung.
* **Der Fingerabdruck deckt 3 von 101 Sichten ab.** Eine Verstellung, die nur `v_plausibilitaet`, `erg_verlauf`, `erg_gewichte`, `v_datenqualitaet` oder eine der übrigen 98 verändert, kommt als „ohne Wirkung" heraus — die freundlichste aller Antworten für den gefährlichsten Fall.
* Verstellungen, die „ohne Wirkung" heissen, bekommen einen Befund der **Klasse 2**; solche, die sich nicht bauen lassen (`'Stelle nicht gefunden'`), einen der **Klasse 1 mit `marke: 'kein Fehler'`**. Ein Anker, der verschwindet, wird also als Nicht-Fehler abgelegt.
* Die Selbstprobe prüft nur, dass der **Fingerabdruck sich ändert** — nicht, dass `laufen()` daraus „überlebt" oder „gefangen" macht.

## Sonde 07 — Szenarien (291 Zeilen)

**Regel.** Acht Papierfälle S1–S8 auf frisch gebauten Schemata (`frischesSchema` → Migrationen → Schema 67), jeder mit von Hand ausrechenbarem Sollwert; danach `invarianten.alle()` auf sechs davon (S1, S2, S3, S5, S7, S8), Regel „Unwissen" ausgenommen, „Bilanz" bei S8 ausgenommen. Am Ende `raus.filter(b => b.klasse > 0)` — S2 wird immer erzeugt und nur über `klasse: 0` unterdrückt.

**Was durchkommt.**
* **Kein Störfall zur Zeit.** Kein Fall spielt eine Erfassung um 23:30 Ortszeit, keiner wechselt die Zeitzone, keiner überschreitet eine Sommerzeitgrenze. `HEUTE = '2026-09-01'` ist fest verdrahtet, `heute_test` wird gesetzt — die ganze Klasse der Kalenderfehler, die 0067 behandelt, ist konstruktiv ausgeschlossen.
* **Kein Störfall zur Nebenläufigkeit, zu Rechten, zu Datenmenge.**
* **Selbstprobe ruft `laufen()` nicht auf**: sie baut nur `papierfall('pw_probe7')` und vergleicht Eingang und „im Haus". Bricht die Erkennung in S3–S8, meldet sie „ok".
* Die Sollwerte sind Literale im Code (`richtig = 960`, `> 1899`, `haus8 > 1`, `2850`) — jede Änderung an der Tara-Rechnung des Gerüsts macht sie still falsch statt rot.

## Sonde 08 — Leer ist nicht null (314 Zeilen)

**Regel.** 8a: Welt ohne Messung (`papierfall`), Massstab `erg_verlust.bekannt`; **`SICHTEN = ['v_saisonbilanz','erg_charge']`** und **`ZUORDNUNG` = 8 von Hand zugeordnete Spalten**; jede dieser Spalten, die eine Zahl statt NULL liefert, obwohl alle zugehörigen Ströme unbekannt sind, ist ein Treffer. 8b: Regex `/(…_kg|verlust|verdunstung|schimmel|sockel|fax|kanal|masse|netto|brutto)…\s*(\?\?|\|\|)\s*0\b/` über `src/`; ein Kommentar in den drei Zeilen darüber gilt als Begründung. 8c: drei Paletten mit fehlender Kistenzahl / Gebindeart; dazu `/tara_kg_palette\s*\?\?\s*0/` in `src/`.

**Was durchkommt.**
* **Nur 2 von 101 Sichten und 8 von 1091 Zahlenspalten** stehen im Blick von 8a. Jede andere Sicht darf eine ungemessene Null ausweisen, ohne dass es auffällt.
* Die Zuordnung ist von Hand — das ist im Kommentar begründet und richtig, macht sie aber zu **acht Namensbindungen**, die bei jeder Umbenennung still leerlaufen (`if (!spalten.includes(z.spalte)) continue`).
* 8b zählt Kommentare, liest sie nicht (steht so im Befundtext).
* **Selbstprobe ruft `laufen()` nicht auf**: sie prüft nur, dass `erg_verlust` in der Welt ohne Messung `bekannt = false` und `kg is null` liefert. Der ganze Vergleichsteil (`SICHTEN`, `ZUORDNUNG`) ist von der Selbstprobe nicht gedeckt.

## Sonde 09 — Einheiten (145 Zeilen)

**Regel.** Fünf Namensregeln über alle Zahlenspalten aller Tabellen, Sichten und gespeicherten Sichten: `…_anteil` in [0,1]; `…_kg ≥ −0,01`; `…_tage|^alter_|_lagertage ≥ 0`; `^n_|^anzahl ≥ 0`; `…_g` nicht in (0,20). Drei namentliche Ausnahmen (`d_m1_r`, `d_f_eta`, `u`), dazu die Wortgruppe `MIT_VORZEICHEN`.

**Gemessene Abdeckung (Schema 67):**
```
Zahlenspalten in Tabellen/Sichten/gesp. Sichten:            1091
davon mit einer Namensendung, die eine Regel auslöst:        421
  wegen Vorzeichen-Wortgruppe übersprungen:                   20
  tatsächlich geprüft:                                       401   (36,8 %)
OHNE jedes Namensmuster, also nie geprüft:                    670   (61,4 %)
```
Lauf gegen Schema 67: 1 Befund (Klasse 1, „geprüft und in Ordnung: 401 geprüfte Spalten"), **18,1 s** — die teuerste Sonde, weil sie 401 Einzelabfragen stellt.

**Was durchkommt.**
* **670 Zahlenspalten (61,4 %) haben keinen Namen, an dem die Sonde eine Erwartung festmachen kann.** Darunter alles, was `_pro_kiste`, `_stand`, `_wert`, `_idx`, `_nr`, `_id`, `_faktor`, `_lambda`, `_k`, `_quantil` heisst.
* `try { … } catch { continue }` überspringt jede Spalte, deren Abfrage fehlschlägt (ungefüllte gespeicherte Sicht) — **ohne Zähler**. Die Meldung „401 geprüfte Spalten" enthält also möglicherweise weniger, als sie sagt; welcher Anteil, weiss die Sonde nicht.
* Die `…_g`-Regel greift nur nach unten (`> 0 and < 20`). Eine Grammspalte, in der Tonnen stehen, fällt nicht auf.
* Die Sonde prüft **Werte**, nie **Formeln** — ein Anteil hoch Tage bleibt unbemerkt, solange das Ergebnis in [0,1] landet.
* Selbstprobe ist stark: sie legt `v_pw_probe` mit `13.07 as verlust_anteil` und `-5 as schimmel_kg` an und verlangt beide Befunde aus `laufen()`.

## Sonde 10 — Annahmen (234 Zeilen)

**Regel.** Liest die Tabelle unter `| Annahme |` aus `docs/ABLAUF.md`; baut Stichworte (alles in Rückstrichen + grossgeschriebene Wörter ≥ 6 Zeichen, max. 8); sucht sie in einem Korpus aus `pruefung.sql`, `run.sh`, `pruefstand/**/*.{mjs,sh}`, **`src/**/*.test.ts`**, `pruefwerk/**/*.mjs` und den Arten von `v_plausibilitaet`; verwirft Stichworte, die in mehr als einem Viertel der Dateien vorkommen. Dann: gibt es die vierte Spalte („auffiele|bewacht|Wache" im Kopf)? Wenn ja: leere Zellen und unbegründete „nirgends" melden; jede in der Spalte genannte `Auffälligkeit „X"` muss in `v_plausibilitaet` existieren, jede genannte Datei muss existieren.

**Gemessene Bindungsfehler.**
```
find src -name '*.test.ts' | wc -l   → 0
find test -name '*.test.ts' | wc -l  → 9
```
**`dateien('src', /\.test\.ts$/)` liefert null Dateien.** Die Sonde glaubt, die Modultests zu durchsuchen, und durchsucht nichts — die 807 Zeilen Modultests in `test/` liegen ausserhalb ihres Korpus. Eine Annahme, die ausschliesslich von einem Modultest bewacht wird, gilt für Sonde 10 als **unbewacht**. Der Fehler ist seit Bau der Sonde da und wird von der Selbstprobe nicht berührt (die prüft nur `annahmen()` und `stichworte()` an zwei erfundenen Zeilen).

Die vierte Spalte existiert inzwischen (`docs/ABLAUF.md:415`: `| Annahme | Warum sie drinsteht | Was passiert, wenn sie nicht stimmt | Wo es auffiele |`), der Zweig „Spalte fehlt" ist also tot; der Zweig „Wache erfunden" ist aktiv und wertvoll.

**Was durchkommt.** Alles, was die Annahmentabelle nicht nennt. Und alles, was sie nennt, aber nur mit einem Wort, das häufiger als in einem Viertel der Dateien vorkommt (dann wird es verworfen).

## `pruefwerk/invarianten.mjs` (108 Zeilen) — das gemeinsame Netz

Fünf Regeln, von den Sonden 05, 06 und 07 benutzt: Erhaltung, Rückrechnung, Zerlegung, Bilanz, Unwissen. Sie hängen an **7 fest verdrahteten Objekten** (`mv_kaskade`, `erg_verlust`, `v_saisonbilanz`, `erg_charge`) und rund 30 Spaltennamen. Toleranzen: 1e‑6/0,01 · 1e‑4/0,05 · 1e‑4/0,5 · 1e‑5/1. Alle Abfragen tragen `limit 20` bzw. `limit 5`.

Gemessen: `inv.alle('karte_werkzeuge')` (Schema 66) und `inv.alle('karte_67')` (Schema 67) → **alle Regeln halten**, je ~215 ms.

**Was durchkommt.** Alles, was die Bilanz nicht stört: eine Masse, die zwischen zwei Verlustarten verschoben wird, summiert sich weiterhin zu `m0`. Genau dafür gibt es Sonde 04 — die aber die Koeffizienten als gegeben nimmt.

---

# 5. Abdeckungsmatrix — `src/` × Werkzeuge

`src/` = 54 Dateien, 11 235 Zeilen (`find src -name '*.ts' -o -name '*.tsx' | xargs wc -l`).

| Werkzeug | Was es von `src/` anfasst | Art |
|---|---|---|
| `test/*.test.ts` | **11 Module, alle in `src/lib/`** | ausgeführt |
| `pruefstand/bildschirme.mjs` | 45 Bildschirme über 18 Pfade, 2 Geräte × 2 Themen = 180 Aufnahmen | gerendert |
| `pruefstand/beschriftung.mjs` | 12 Ansichten über 6 Pfade, nur Betriebsleiter | gerendert + geerntet |
| `pruefstand/kette.mjs` | 5 Durchläufe der Arbeitermasken | geklickt |
| Sonden 01, 02, 03, 08 | **alle 54 Dateien** | als Text gelesen |
| `pruefstand/luecken.sh` | alle Dateien per `grep -r` | als Text gelesen |
| `run.sh` | genau 2 Dateien: `src/lib/version.ts`, `src/auswertung/daten.ts` (+ `src/pages/*.tsx`) | als Text gelesen |
| `npm run build` (tsc) | alle | typgeprüft |

## 5.1 Was kein Modultest anfasst

**43 Dateien, 8438 von 11 289 Zeilen (74,7 %) haben keinen Modultest.** Nach Verzeichnis:

| Verzeichnis | Dateien | Zeilen | mit Modultest |
|---|---:|---:|---|
| `src/lib` | 15 | 3040 | 11 Dateien (2851 Zeilen) |
| `src/pages` | 15 | 4076 | **0** |
| `src/arbeit` | 9 | 1642 | **0** |
| `src/components` | 7 | 962 | **0** |
| `src/auswertung` | 3 | 775 | **0** |
| `src/betrieb` | 1 | 440 | **0** |
| `src/auth`, `src/sprache`, `src/` (App/main) | 4 | 300 | **0** |

Die zwanzig grössten Dateien ohne Modultest, mit ihrem einzigen anderen Netz:

| Datei | Zeilen | anderes Netz |
|---|---:|---|
| `src/pages/Stammdaten.tsx` | 816 | 3 Bildschirme (`betrieb-stammdaten`, `-demo`, `-schemata`) |
| `src/auswertung/daten.ts` | 558 | `run.sh` Stufe 5 (nur die `erg_`-Namen per Regex) + jeder Betriebsleiter-Bildschirm |
| `src/pages/Ursachen.tsx` | 528 | 1 Bildschirm + 2 Beschriftungsansichten |
| `src/components/Diagramm.tsx` | 516 | mittelbar über jede Seite, die zeichnet |
| `src/betrieb/AusgangImport.tsx` | 441 | 1 Bildschirm (`betrieb-import`) |
| `src/pages/NeueArbeit.tsx` | 384 | 8 Bildschirme + `kette.mjs` |
| `src/pages/Ueberblick.tsx` | 321 | 2 Bildschirme + 4 Beschriftungsansichten + Sonden 01/08 (Regex) |
| `src/pages/Arbeit.tsx` | 309 | 12 Bildschirme + `kette.mjs` |
| `src/arbeit/Abschluss.tsx` | 293 | `arbeit-abschluss*` + `kette.mjs` |
| `src/arbeit/Zaehler.tsx` | 283 | `arbeit-zaehler`, `arbeit-kisten` |
| `src/arbeit/Korrektur.tsx` | 274 | 1 Bildschirm (`arbeit-korrektur`), **kein Klickweg**, für Sonde 01/03 unsichtbar (§4.1) |
| `src/pages/CsvUpload.tsx` | 262 | `betrieb-csv` |
| `src/pages/Messungen.tsx` | 251 | 1 Bildschirm + 2 Beschriftungsansichten |
| `src/pages/Lieferungen.tsx` | 227 | `betrieb-lieferungen` |
| `src/pages/Chargen.tsx` | 209 | 2 Bildschirme + 2 Beschriftungsansichten |
| `src/auswertung/Karten.tsx` | 186 | mittelbar |
| `src/pages/Kontrolle.tsx` | 181 | 1 Bildschirm + `kette.mjs` fünfter Durchlauf |
| `src/pages/Anmelden.tsx` | 150 | `anmelden` |
| `src/components/DemoDaten.tsx` | 144 | `betrieb-demo` |
| `src/pages/Betrieb.tsx` | 143 | 7 Bildschirme |

## 5.2 Routen ohne Prüfstand

`src/App.tsx` hat 18 `<Route>`; `bildschirme.mjs` fährt 18 Pfade an, `beschriftung.mjs` 6.

* **`/auftraege/:id` → `AlteArbeit`** (`src/App.tsx:129`) wird von **keinem** Prüfstand geöffnet.
* **`NurAdmin`** (`src/App.tsx:134`) — der Zweig, den ein Arbeiter sieht, wenn er `/dashboard`, `/ursachen`, `/chargen`, `/messungen` oder `/betrieb/*` aufruft — wird nie gerendert: alle fünf Bildschirme laufen mit `wer: 'admin'`. Fünf Routen, ein ungeprüfter Zweig, und er ist die einzige Stelle im Frontend, an der Rollentrennung sichtbar wird.
* Verteilung der 45 Bildschirme: 25 als Arbeiter, 16 als Betriebsleiter, 2 ohne Anmeldung.

---

# 6. Wo ein Werkzeug an einen Namen, ein Muster oder einen Pfad gebunden ist

Das ist die Frage, an der Runde L gescheitert ist. Hier die vollständige, einzeln aufgezählte Liste. **Gesamtzahl: 78 Element-IDs + 15 deutsche Anzeigetexte + 10 CSS-Wähler + 15 Migrations-Ankertexte + 22 Datei-/Verzeichnispfade + 7 Quelltext-Regexe + 8 Katalog-Namensmuster + 19 feste Datenbanknamen + 12 feste Erwartungszahlen = 186 einzelne Bindungen.** Sortiert nach dem, was passiert, wenn sie bricht.

## 6.1 Bricht **still** — das Werkzeug meldet weiter „in Ordnung"

| # | Werkzeug | Bindung | Was bei Bruch passiert |
|---|---|---|---|
| B1 | `beschriftung.mjs:104–190` | 10 CSS-Wähler: `.kennzahl`, `.zahlenzeile > div`, `.gross-zahl`, `.wert`, `.titel`, `.unter`, `.karte`, `.karte-kopf h2`, `.anteil-zeile`, `.anteil-name strong`, `.anteil-wert`, `.leise`, `.bilanzzeile` | **Ernte fällt auf 0, der Prüfstand druckt „OK Jede Zahl auf jeder Seite sagt, was sie ist" und beendet mit 0.** Es gibt **keine Mindestmenge**: `if (alleFehler.length === 0) { … process.exit(0) }`. Das ist die L‑Blindheit, unrepariert, in der CI. |
| B2 | `beschriftung.mjs:108` | `ZAHL = /(-?\d[…]*)\s*(t\b|kg\b|%|Stück\b|Tage\b|Tagen\b)/` | Eine Zahl in „Kisten", „g", „CHF" wird nicht geerntet und damit nie geprüft |
| B3 | `beschriftung.mjs:55` | `begriffe.json` — **25 Begriffe, 49 Muster** gegen 42 Zeilen in `begriffe_gefunden.txt` | Ein neuer Begriff schlägt an (gewollt); ein **entfernter** Begriff schlägt nie an |
| B4 | `01_herkunft.mjs:154` | `regexp_replace(viewdef, '(?s).*\sFROM\s+([a-z0-9_]+).*')` + `if (!quelle.startsWith('v_')) continue` | **Gemessen: 1 von 30 (`erg_verlauf`) wird still übersprungen**, ohne Zähler |
| B5 | `01_herkunft.mjs:189` | `lies('src/pages/Ueberblick.tsx')` + `/titel="Ausgeliefert"[\s\S]{0,240}?art="gemessen"/` | Datei verschoben → Ausnahme; Text/Attributform geändert oder Abstand > 240 Zeichen → **Regel schweigt** |
| B6 | `08_leer_nicht_null.mjs:234` | `/n_paletten_mit_netto/.test(lies('src/pages/Ueberblick.tsx'))` | dito |
| B7 | `08_leer_nicht_null.mjs:264` | `/tara_kg_palette\s*\?\?\s*0/` | `?? 0` in `?? undefined ?? 0` oder über eine Hilfsfunktion → Regel schweigt |
| B8 | `08_leer_nicht_null.mjs:29–41` | `ZUORDNUNG`: 8 Spaltennamen, `SICHTEN`: 2 Sichtnamen | `if (!spalten.includes(z.spalte)) continue` — still |
| B9 | `10_annahmen.mjs:82` | **`dateien('src', /\.test\.ts$/)`** | **Bereits gebrochen: 0 statt 9 Dateien** |
| B10 | `10_annahmen.mjs:34` | `/^\|\s*Annahme\s*\|/` in `docs/ABLAUF.md` | Kopfzeile umbenannt → `annahmen()` gibt `[]`, Sonde meldet einen Befund (laut) |
| B11 | `10_annahmen.mjs:92` | `relname like 'v\_plausibilitaet%'` + `/'([^']+)'::text AS art\b/` | Ein Auffälligkeitszweig, der anders formatiert ist, gilt als nicht vorhanden → Fehlbefund „erfundene Wache" |
| B12 | `02_bezugsgroessen.mjs:36` | Funktionsname `prozent(` | Eine Prozentzahl über einen anderen Helfer ist unsichtbar |
| B13 | `02_bezugsgroessen.mjs:88` | Eigenschaftsnamen `titel|unter|xTitel|yTitel` und `>Text<` | **7 von 31 Stellen haben schon heute keine erkannte Beschriftung** → 2c/2e schweigen dort |
| B14 | `02_bezugsgroessen.mjs:183` | `column_name like '%\_bekannt'`, Ausschluss `koeff_bekannt` | Eine neue Kennzeichenspalte mit anderem Suffix wird nie gesucht |
| B15 | `02_bezugsgroessen.mjs:150` | `GANZER_EINGANG = /(des|vom|am|der)\s+Eingang(s|smasse)?/i` | Deutsch fest verdrahtet; die App hat sechs Sprachen |
| B16 | `09_einheiten.mjs:51–62` | 5 Namensmuster + 3 namentliche Ausnahmen + `MIT_VORZEICHEN` | **Gemessen: 670 von 1091 Spalten (61,4 %) lösen keine Regel aus** |
| B17 | `09_einheiten.mjs:97` | `catch { continue }` | Spalten, deren Abfrage scheitert, werden **ohne Zähler** übersprungen |
| B18 | `03_erfassung.mjs:27` | `ERFASSUNG` = 13 Tabellennamen | Eine neue Erfassungstabelle wird nie geprüft |
| B19 | `03_erfassung.mjs:32` | `VERWALTUNG` = 9 Spaltennamen | dito, umgekehrt |
| B20 | `luecken.sh:26` | `TABELLEN` = 11 Tabellennamen (von 28) | Neue Erfassungstabelle bleibt aussen vor |
| B21 | `luecken.sh:34–70` | **37 namentliche `AUSNAHME`-Einträge** | Eine Spalte, die einmal als Ausnahme eingetragen ist, wird nie wieder geprüft — auch wenn sie später doch getippt werden soll |
| B22 | `luecken.sh:85, 109` | `grep -rqF "'$c'"` bzw. `grep -rqF "'$t'"` | Der Test „wird geschrieben" ist in Wahrheit „der Name kommt irgendwo in einer Zeichenkette vor" — auch beim reinen **Lesen**. Falsche Entwarnung, nie falscher Alarm |
| B23 | `run.sh:257` | ``grep -ohE "\berg_[a-z_]+" src/auswertung/daten.ts src/pages/*.tsx`` | **Heute vollständig (30/30 gefunden, keine `erg_`-Nennung ausserhalb des Suchpfads).** Aber: `src/pages/*.tsx` ist nicht rekursiv, `src/components/`, `src/arbeit/`, `src/betrieb/` sind nicht dabei. Zieht eine Karte in eine Komponente um, verschwindet ihre Sicht aus der Tempoprüfung, ohne dass etwas rot wird |
| B24 | `06_mutation.mjs:205` | `SICHTEN_FA = ['erg_charge','v_saisonbilanz','mv_kaskade']` | **3 von 101 Sichten**; alles andere heisst „ohne Wirkung" |
| B25 | `attrappe.mjs:99` | `fehlendeFixtures` → `console.warn`, kein Fehlercode | Eine Tabelle ohne Fixture liefert `[]`; die Seite rendert leer und gilt als in Ordnung |
| B26 | `postgrest.mjs:6` | Nachbau von PostgREST: nur `eq/in/is/not.is/like`, `order`, `limit`, `offset`, `range` | Jeder andere Filter (`gt`, `lt`, `or`, `cs`, `fts`, `select` mit Einbettung) wird **ignoriert** — die Attrappe liefert ungefiltert, die Seite sieht mehr Zeilen als in Wirklichkeit, und kein Prüfstand merkt es |
| B27 | `bildschirme.mjs` gesamt | 180 Aufnahmen werden geschrieben und **mit nichts verglichen** | Es gibt keine Referenzbilder. Geprüft werden nur `scrollWidth − clientWidth > 1` und Konsolenfehler. Eine Seite darf falsche, fehlende oder unsinnige Zahlen zeigen |

## 6.2 Bricht **laut** — akzeptabel

| # | Werkzeug | Bindung | Wirkung |
|---|---|---|---|
| B28–B42 | `06_mutation.mjs:45–96` | **15 Ankertexte** in den Migrationen | Nicht gefunden → Befund „liess sich nicht prüfen" (Klasse 1, `marke: 'kein Fehler'`) — halblaut |
| B43 | `run.sh:34`, `attrappe.mjs:37`, `kette.mjs:30` | `/SCHEMA_ERWARTET = (\d+)/` in `src/lib/version.ts` | `attrappe.mjs` und `kette.mjs` greifen mit `[1]` direkt zu → **TypeError**, wenn die Zeile fehlt. Laut. |
| B44 | `run.sh:31` | `schema_stand()` = höchste Migrationsnummer | rot, gewollt |
| B45–B56 | `run.sh` | 12 feste Zahlen: `42` Chargen · `2` Paletten · `9` Sollgewicht · `0` Verwaiste · `3` Auffälligkeiten · `1000000` Byte · `6000/3000/2000/12000` ms · `> 0` Hinweiszeilen | rot, gewollt — aber `42` und `3` binden an die Demodaten, nicht an eine Regel |
| B57–B60 | `run.sh:48–229` | Textmuster in der Ausgabe: `Fertig.*Chargen`, `Auswertung berechnet`, `Demo-Saison steht`, `marge_messung enthält 1 Zeile` | Wird die Meldung umformuliert, wird der Test rot (laut) |
| B61 | `run.sh:135` | Migrationen `0000`–`0015` als Aktualisierungs-Ausgangspunkt, fest aufgezählt | Der Pfad prüft **einen** alten Stand von 67; die 51 dazwischen liegenden Stände sind ungeprüft |
| B62–B76 | `kette.mjs` | **78 Element-IDs** (`#taet-waschen_sortieren`, `#charge`, `#k-damals`, …) und **15 deutsche Texte** (`'Weiter'`, `'Dein Name'`, `'3 Paletten mit 96 Kisten'`, …) | `schritt()` fängt, druckt, macht einen Screenshot und `process.exit(1)` — **laut**. Das ist das sauberste Werkzeug im Bestand |
| B77 | `kette_pruefen.sh:27` | `supabase/setup.sql` statt der Migrationen | Prüft einen **anderen Bauweg** als alle anderen Werkzeuge — bewusst, aber eine eigene Bindung |
| B78 | `07_szenarien.mjs`, `saison.mjs` | `HEUTE = '2026-09-01'`, `CHARGE = 9001`, `SORTE = 'Prüfkürbis'`, Sollwerte `2850`, `960`, `1899`, `950` | laut |
| B79–B97 | `pruefwerk` gesamt | **19 feste Datenbanknamen**: `pw_meta`, `pw_mutation`, `pw_leer`, `pw_s1`–`pw_s8`, `pw_lnn_tara`, `pw_probe7`, `pw_*_probe` | Zwei gleichzeitige Läufe (oder ein Lauf neben einer Werkstatt-Sitzung) treten sich gegenseitig auf die Datenbank. Kein Sperr- oder Zufallsnamensschutz |
| B98 | `umgebung.mjs:19` | `PG_SOCKET ?? '/tmp/pgsock'`, `PG_PORT ?? '55432'` | — |
| B99 | `run.sh:12`, `kette_pruefen.sh:16` | Vorgabe-URL `host=/tmp` | **Widerspricht** `/tmp/pgsock` in `daten_dumpen.sh`, `demo_bauen.sh`, `luecken.sh`, `umgebung.mjs`. Wer ohne Argument aufruft, landet auf einem anderen Cluster |
| B100 | `bildschirme.mjs:60` | Namensfilter als erstes Argument statt Datenbank-URL | War schon einmal eine stille Blindheit; ist seit Runde M repariert (`process.exit(1)` bei leerem Filter) — **ein Muster, dem die anderen Werkzeuge folgen sollten** |

## 6.3 Bindungen an Doku statt an Code

| # | Werkzeug | Bindung |
|---|---|---|
| B101 | Sonde 04 | Die Formeln stammen aus `docs/ABLAUF.md`. Wird das Dokument dem Code angepasst, ist das Orakel entwertet und niemand merkt es |
| B102 | Sonde 10 | Die Annahmentabelle in `docs/ABLAUF.md` ist die einzige Quelle dessen, was geprüft werden soll |
| B103 | `docs/ABMACHUNGEN.md` | 48 Zusagen, deren Beweis als **Freitext** danebensteht; nichts prüft, dass der genannte Beweis existiert oder anschlägt (Sonde 10 tut das nur für `ABLAUF.md`) |

---

# 7. Was in der CI läuft und was nur von Hand

`.github/workflows/pruefung.yml`, drei Aufträge:

| Auftrag | Schritte | Werkzeuge |
|---|---|---|
| **app** | `npm ci`, `npm test`, `npm run build` | 84 Modultests, `tsc -b`, Vite-Build |
| **datenbank** | `./supabase/test/run.sh` | `pruefung.sql` (530 asserts), `fingerabdruck.sql`, `setup.sql` ×4, `demo_daten.sql`, `last.sql`, `luecken.sh`, `setup_bauen.sh` |
| **bildschirme** | `demo_bauen.sh`, `daten_dumpen.sh`, `beschriftung.mjs`, `bildschirme.mjs` | Playwright, Attrappe, 180 Aufnahmen, 12 Begriffsansichten |

**Nur von Hand — nichts davon schützt einen Zweig oder eine Zusammenführung:**

| Werkzeug | Zeilen | Warum es nicht in der CI ist (soweit dokumentiert) |
|---|---:|---|
| `pruefstand/kette.mjs` | 523 | nicht genannt; braucht Playwright, ist aber im `bildschirme`-Auftrag ohnehin da |
| `pruefstand/kette_pruefen.sh` | 287 | braucht zusätzlich Postgres **und** Playwright im selben Auftrag |
| `pruefwerk/` (10 Sonden) | 3254 | `README.md:787`: „Läuft von Hand, nicht in run.sh" — begründet mit Laufzeit |
| `supabase/test/simulation/` | 439 | Minuten bis Stunden |
| `npm run typecheck` einzeln | — | mittelbar über `npm run build` |
| `npm audit --omit=dev` | — | in `AB-44` als Beweis genannt, läuft nirgends automatisch |

**Gemessene Folge für die Zusagen.** `docs/ABMACHUNGEN.md` behauptet in der Einleitung: „Alles hängt in der CI (`.github/workflows/pruefung.yml`)." Auszählung der 48 Zeilen nach ihrer Beweis-Spalte:

| | Zahl |
|---|---:|
| Beweis läuft in der CI (`pruefung.sql`, `run.sh`, `luecken.sh`, `beschriftung.mjs`, `bildschirme.mjs`, Modultests) | 39 |
| Beweis läuft **nur ausserhalb** der CI (`kette.mjs`, `kette_pruefen.sh`) | **3** — AB‑05, AB‑06, AB‑35 |
| Beweis ist kein ausführbares Werkzeug (Verweis auf Quelltext, „im Frontend", `npm audit`, leer) | **6** — AB‑10, AB‑14, AB‑18, AB‑38, AB‑42, AB‑44 |

Neun von 48 Zusagen (19 %) haben keinen Wächter, der bei einer Zusammenführung anspringt. AB‑14 hat **überhaupt keinen** Beweistext.

Und seit dem aktuellen Stand: die 39 CI-gedeckten Zusagen laufen zu einem grossen Teil hinter dem Abbruch in `pruefung.sql:1798` (§0) — von den 530 Behauptungen werden 281 nicht mehr ausgeführt.

---

# 8. Systematische Blindstellen, quer über alle Werkzeuge

| # | Blindstelle | Grösse |
|---|---|---|
| 1 | **Rechte und Rollen.** 78 Regeln, 1 Rollenblock (0,9 % von `pruefung.sql`), 0 Regeln namentlich, `anon` nie angenommen, die Attrappe kennt keine Rollen. `korrekturfenster()` (12 h, 10 Regeln) völlig ungeprüft | 78 Regeln, ≤ 6 mit einem Fall |
| 2 | **Der Schätzer selbst.** Alle Sonden nehmen `r`, `f`, `a₀`, `a_klein`, `a_gross`, `a_fax` und die Bänder als gegeben; nur `simulation/` misst gegen eine bekannte Wahrheit — und läuft nicht in der CI und nicht je Koeffizient | 3 Schätzsichten ohne jede Behauptung |
| 3 | **Die Zeit.** `betriebstag`, `betriebszone`, `heute` (0067) haben 0 Behauptungen. Kein Werkzeug spielt 22:00/23:30/00:30 Ortszeit durch, keines wechselt Sommer/Winter. Die eine Stelle, die beide Kalender mischt, ist der aktuelle Testabbruch | 0 Behauptungen zu 3 neuen Funktionen |
| 4 | **Nebenläufigkeit.** Kein Werkzeug öffnet zwei Sitzungen. Sperren, verlorene Aktualisierungen, halb erneuerte gespeicherte Sichten sind konstruktiv unerreichbar | 0 Werkzeuge |
| 5 | **Bildinhalt.** 180 Aufnahmen, 0 Vergleiche. Geprüft wird Überlauf und Konsole | 341 PNG auf der Platte, 0 Referenzen |
| 6 | **Selbstproben, die nichts über die Sonde sagen.** 6 von 10 führen `laufen()` nicht aus | 6 von 10 |
| 7 | **Stilles Überspringen.** `continue` ohne Zähler an mindestens 6 Stellen (01/1b, 02 ×2, 08, 09 ×2) | 6 gemessene Stellen |
| 8 | **Zwei Schemafassungen in einem Lauf.** `demo` = 66, Migrationen = 67 | 5 Sonden auf 66, 4 auf 67 |
| 9 | **Ein Werkzeug hängt am anderen.** `pruefung.sql` rot ⇒ `run.sh` Stufen 2–7 aus ⇒ `luecken.sh` in der CI aus ⇒ Sonde 06 testet 0 von 15 | Kaskade über 4 Werkzeuge |
| 10 | **Die Korrekturmaske.** `src/arbeit/Korrektur.tsx` schreibt und löscht über einen Variablen-Tabellennamen: unsichtbar für Sonde 01, Sonde 03 und `luecken.sh`; kein Klickweg in `kette.mjs`; kein Modultest; ein Bildschirm ohne Inhaltsprüfung | 274 Zeilen, 3 Schreibpfade |

---

# 9. Die Befehle, mit denen gemessen wurde

```bash
export PGHOST=/tmp/pgsock PGPORT=55432 PGUSER=postgres
psql -d postgres -c "create database karte_werkzeuge template demo"

# Objektzahlen
psql -d karte_werkzeuge -tAc "select 'sichten',count(*) from pg_class c join pg_namespace n
  on n.oid=c.relnamespace where n.nspname='public' and c.relkind='v' union all …"

# Abdeckungsmatrix (Skript im Scratchpad)
psql -d karte_werkzeuge -tAc "select c.relkind::text||'|'||c.relname from pg_class c … " > objekte.txt
node matrix.mjs objekte.txt > matrix.json      # Wortgrenzen-RegExp je Werkzeuggruppe
node asserts.mjs objekte.txt                   # do-Blöcke, asserts, Zuordnung

# assert-Zählung
grep -cE '^[[:space:]]*assert[[:space:]]' supabase/test/pruefung.sql        # 530
grep -c '^do \$\$' supabase/test/pruefung.sql                              # 57
awk 'NR<1854' supabase/test/pruefung.sql | grep -cE '^\s*assert\s'         # 249

# Funktionsausführung
psql -d postgres -c "create database karte_pruefung"
psql -d postgres -c "alter database karte_pruefung set track_functions='all'"
psql -d karte_pruefung -f supabase/test/stub_supabase.sql
for f in supabase/migrations/*.sql; do psql -d karte_pruefung -f "$f"; done
psql -d karte_pruefung -c "select pg_stat_reset()"
psql -d karte_pruefung -f supabase/test/pruefung.sql          # rc=3, 29716 ms
psql -d karte_pruefung -tAc "select proname from pg_proc p … where p.oid not in
  (select funcid from pg_stat_user_functions)"

# Indexnutzung
psql -d karte_pruefung -tAc "select count(*) filter (where idx_scan>0), count(*)
  from pg_stat_user_indexes where schemaname='public'"      # 26 | 88

# Fingerabdruck-Löcher
psql -d karte_werkzeuge -f supabase/test/fingerabdruck.sql | awk '{print $1}' | sort | uniq -c
psql -d karte_werkzeuge -tAc "select count(*) from information_schema.role_table_grants
  where table_schema='public' and table_name like 'erg\_%'"  # 0
psql -d karte_werkzeuge -tAc "select count(*) from pg_class c … where relkind='m'
  and relacl is not null"                                    # 38

# Sonden 01/03/04/09 gegen Schema 67 (keine Datei geschrieben)
node -e "import('…/01_herkunft.mjs').then(m=>m.laufen({db:'karte_67'}))"

# Mutationsanker
node -e "import('…/06_mutation.mjs').then(({MUTATIONEN})=>…)"   # 15/15 gefunden

# Sonde 09 Abdeckung
node karte_09.mjs                                              # 401 von 1091

# Selbstprobenstruktur
node -e "…grep 'laufen(' im Rumpf ab 'export async function selbstprobe'…"

# run.sh vollständig
psql -d postgres -c "create database karte_runsh"
time ./supabase/test/run.sh 'postgresql://postgres@/karte_runsh?host=/tmp/pgsock&port=55432'
# → rc=3, real 0m32.302s

# Modultests
node --test test/*.test.ts        # # tests 84  # pass 84  # fail 0

# Aufräumen
psql -d postgres -c "drop database karte_werkzeuge" -c "drop database karte_pruefung" \
  -c "drop database karte_67" -c "drop database karte_runsh"
```
