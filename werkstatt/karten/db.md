# Datenbank-Karte — Rechenschicht Schema 0066

Alles unten ist **gemessen**, nicht gelesen. Jede Zahl trägt den Befehl, mit dem sie
entstanden ist. Wo ich schätze, steht „Schätzung" daneben.

## 0. Wie und worin gemessen

```
export PGHOST=/tmp/pgsock PGPORT=55432 PGUSER=postgres
create database karte_db    template demo     -- Arbeitskopie, Messungen
create database karte_gross template demo     -- danach 1x → 3x → 10x vervielfacht
create database karte_loesch template demo    -- Löschversuch
```

Am Projekt wurde **nichts** verändert; alle Schreibversuche liefen in diesen drei Kopien.
Die Kopien stehen noch da (`karte_db` 25 MB — enthält am Ende 40 gelöschte
`schimmel_messung`-Zeilen aus dem Mischzustands-Versuch; `karte_gross` 57 MB = zehnfache
Saison; `karte_loesch` 23 MB = eine Arbeit endgültig gelöscht). Alle Kennzahlen im Text
sind auf der **unveränderten `demo`** gegengeprüft (Abschnitt 9.4).

Arbeitsordner mit allen Rohmessungen und den 140 abgezogenen Objektdefinitionen:
`/tmp/claude-0/-home-user-Kurbisverlust/6a3ce2bd-5cdd-5db2-b9aa-a2b322604348/scratchpad/k/`

Postgres 16.13, Zeitzone der Datenbank `Etc/UTC`, `jit` in `demo` **an** (s. 8.5).

---

## 1. Bestandsaufnahme in Zahlen

| Was | Anzahl | Befehl |
|---|--:|---|
| Tabellen | 28 | `select relkind, count(*) from pg_class … group by 1` |
| Ansichten (`v`) | 63 | ebenda |
| gespeicherte Ansichten (`m`) | 38 | ebenda |
| Funktionen | 42 (39 Namen, 3 Überladungen) | `pg_proc` |
| Indexe | 93 | `pg_class relkind='i'` |
| Sequenzen | 15 | `pg_class relkind='S'` |
| Aufzählungstypen | 7 | `pg_enum` |
| Auslöser (nicht intern) | 22 | `pg_trigger where not tgisinternal` |
| RLS-Regeln | 78 | `pg_policy` |
| Fremdschlüssel | 59 | `pg_constraint contype='f'` |
| Prüfbedingungen | 37, davon **4 `not valid`** | `pg_constraint contype='c'` |
| Fingerabdruck-Objekte | 2633 | `psql -d demo -f supabase/test/fingerabdruck.sql \| grep -c .` |
| Spalten in Tabellen | 266 | `pg_attribute` |
| Spalten in Ansichten+gesp. | **1412** | `pg_attribute` |
| Zeilen SQL in allen 101 Sicht-/Matview-Definitionen | 4258 | `pg_get_viewdef` je Objekt, `wc -l` |
| Zeilen SQL in allen 39 Funktionen | 2104 | `pg_get_functiondef`, `wc -l` |
| Datenbankgrösse `demo` | 23 MB (Tabellen 1040 kB, gesp. Sichten 2496 kB, Indexe 2032 kB) | `pg_total_relation_size` |
| `setup.sql` | 574 231 B, 10 625 Zeilen; **Teil B ab Zeile 4894** (54 %) | `wc` |
| Migrationen | 67 Dateien, 23 930 Zeilen, 1.4 MB | `wc -l supabase/migrations/*.sql` |

**Teil-B-Inhalt** (`awk 'NR>4894' supabase/setup.sql | grep -cE '^create …'`):
63 `create view`, 12 `create materialized view`, 3 `create function`.
Die restlichen **26 gespeicherten Ansichten** entstehen nicht als Quelltext, sondern in
einer `do $$`-Schleife über eine Namensliste (`setup.sql:9251–9291`) — ihre Namen stehen
nur in dieser Liste. Das ist beim Suchen im Quelltext eine Falle.

---

## 2. Die 28 Tabellen

Zeilen aus `demo` (`select count(*)` je Tabelle, erzeugt über `pg_class`).
Spalten/NOTNULL/Regeln/FK/Checks/Indexe/Auslöser aus dem Katalog.
**Alle 28 Tabellen haben RLS aktiv** (`relrowsecurity = t`), keine mit `force`.

| Tabelle | Zeilen | Sp. | davon NOT NULL | RLS-Regeln | FK raus | FK rein | Checks | Indexe | Auslöser | Grösse |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| `auftrag` | 309 | 24 | 8 | 4 | 4 | 9 | 9 | 4 | 3 | 176 kB |
| `auftrag_angabe` | 338 | 6 | 6 | 4 | 2 | 0 | 0 | 2 | 1 | 112 kB |
| `auftrag_gebinde` | 208 | 8 | 7 | 4 | 2 | 0 | 2 | 2 | 1 | 80 kB |
| `auftrag_palette` | 854 | 10 | 4 | 4 | 4 | 0 | 3 | 4 | 1 | 280 kB |
| `auftrag_teilnehmer` | 483 | 5 | 4 | 4 | 2 | 0 | 0 | 2 | 0 | 136 kB |
| `ausgang_artikel` | 11 | 7 | 4 | 2 | 2 | 0 | 0 | 1 | 0 | 32 kB |
| `ausgang_datei` | **0** | 14 | 11 | 2 | 2 | 1 | 0 | 2 | 0 | 24 kB |
| `ausgang_quelle` | 1 | 7 | 4 | 2 | 1 | 3 | 0 | 1 | 0 | 32 kB |
| `ausgang_wiegung` | 128 | 12 | 8 | 4 | 4 | 0 | 3 | 2 | 1 | 80 kB |
| `ausgang_zeile` | 160 | 28 | 11 | 2 | 3 | 1 | 0 | 5 | 0 | 160 kB |
| `ausgang_ziel` | 5 | 4 | 4 | 1 | 0 | 1 | 1 | 1 | 0 | 32 kB |
| `ausschuss_messung` | 34 | 11 | 7 | 4 | 3 | 0 | 1 | 3 | 2 | 64 kB |
| `auswertung_stand` | 1 | 4 | 2 | 1 | 0 | 0 | 1 | 1 | 0 | 56 kB |
| `charge` | 42 | 5 | 4 | 2 | 1 | 7 | 0 | 3 | **0** | 64 kB |
| `charge_vorlauf` | 1 | 5 | 4 | 2 | 2 | 0 | 1 | 1 | 1 | 32 kB |
| `einstellung` | 8 | 3 | 2 | 2 | 0 | 0 | 0 | 1 | 1 | 32 kB |
| `gebinde` | 4 | 4 | 1 | 2 | 0 | 6 | 0 | 1 | 1 | 32 kB |
| `kaeufer` | 4 | 6 | 4 | 3 | 1 | 2 | 0 | 1 | 0 | 32 kB |
| `lieferung` | 187 | 12 | 5 | 4 | 5 | 1 | 5 | 4 | 1 | 120 kB |
| `lieferung_import` | 160 | 5 | 4 | 2 | 3 | 0 | 0 | 3 | 0 | 96 kB |
| `palette` | 844 | 9 | 6 | 2 | 2 | 2 | 0 | 4 | 1 | 312 kB |
| `profil` | 3 | 6 | 6 | 3 | 1 | 18 | 0 | 1 | 1 | 32 kB |
| `schimmel_messung` | 585 | 14 | 9 | 4 | 3 | 0 | 2 | 3 | 2 | 216 kB |
| `sorte_kaliber` | 11 | 4 | 4 | 2 | 0 | 4 | 1 | 1 | 1 | 32 kB |
| `sortier_gewicht` | 5668 | 5 | 4 | 2 | 1 | 0 | 1 | 2 | 1 | 576 kB |
| `sortier_lauf` | 32 | 18 | 11 | 2 | 4 | 1 | 0 | 5 | 1 | 128 kB |
| `sortierschema` | 25 | 12 | 5 | 4 | 3 | 2 | 4 | 3 | 1 | 64 kB |
| `verdunstung_wiegung` | 41 | 18 | 10 | 4 | 5 | 1 | 3 | 3 | 1 | 64 kB |

Auffällig: `charge` hat als einzige rechnungsrelevante Tabelle **keinen Auslöser**
(s. 7.3). `ausgang_datei` ist leer — der Datei-Upload-Weg wurde in der Demo nie benutzt.

### 2.1 Nullbare Spalten, die in der ganzen Demosaison leer bleiben

`select count(*), count(<spalte>) from <tabelle>` für alle 107 nullbaren Spalten:
**15 sind zu 100 % leer**, 47 sind zu 100 % gefüllt (Kandidaten für `not null`).

| immer leer | Zeilen | Bedeutung |
|---|--:|---|
| `auftrag_palette.palette_id` | 854 | **Fremdschlüssel auf die physische Palette — nie gesetzt** |
| `verdunstung_wiegung.palette_id` | 41 | dito |
| `auftrag.durchsatz_kg` | 309 | Zweig `masse_quelle='durchsatz'` nie erreicht |
| `auftrag.geplante_paletten` | 309 | nur in `src/lib/typen.ts`, nirgends geschrieben/angezeigt |
| `auftrag.kaliber_von_g`, `.kaliber_bis_g` | 309 | eigenes Kaliber (0054) in der Demo nie benutzt |
| `verdunstung_wiegung.faul_kg`, `.auswahl` | 41 | |
| `sortier_lauf.roh_datei_ref` | 32 | Verweis auf die Rohdatei im Storage |
| `ausgang_zeile.datei_id`, `.erloes`, `.geaendert_ts` | 160 | |
| `auftrag_teilnehmer.verlassen_ts` | 483 | niemand hat je eine Arbeit verlassen |
| `ausschuss_messung.bemerkung`, `ausgang_wiegung.bemerkung` | 34/128 | |

### 2.2 Die vier `not valid`-Bedingungen — geprüft

```sql
select count(*) from auftrag where not ((not ist_fax) or (station='waschen'));   -- 0
select count(*) from auftrag where not ((kaliber_idx is null) or (station='waschen')); -- 0
select count(*) from auftrag_palette where not (eingangsdatum is not null or …); -- 0
select count(*) from lieferung where not (kg is not null or kisten is not null); -- 0
begin; alter table … validate constraint …; rollback;   -- alle vier ohne Fehler
```

**Alle vier gelten auf dem Bestand und liessen sich sofort validieren.**
(Echte Betriebsdaten konnte ich nicht prüfen — s. „was ich nicht prüfen konnte".)

---

## 3. Fremdschlüssel und `on delete` (59 Stück)

Verteilung (`pg_constraint.confdeltype`):
**43 × NO ACTION · 12 × CASCADE · 4 × SET NULL · 0 × RESTRICT**

Die einzigen nicht-neutralen:

| Kind → Elter | on delete |
|---|---|
| `auftrag_angabe`, `auftrag_gebinde`, `auftrag_palette`, `auftrag_teilnehmer`, `ausgang_wiegung`, `ausschuss_messung`, `schimmel_messung` → `auftrag` | **CASCADE** |
| `charge_vorlauf` → `charge` | CASCADE |
| `lieferung_import` → `lieferung` | CASCADE |
| `sortier_gewicht` → `sortier_lauf` | CASCADE |
| `profil` → `auth.users` | CASCADE |
| `auftrag_palette.wiegung_id` → `verdunstung_wiegung` | SET NULL |
| `ausgang_zeile.datei_id` → `ausgang_datei` | SET NULL |
| `lieferung_import.zeile_id` → `ausgang_zeile` | SET NULL |
| `sortier_lauf.auftrag_id`, `verdunstung_wiegung.auftrag_id` → `auftrag` | SET NULL |

### 3.1 Was passiert, wenn der Betriebsleiter eine Arbeit löscht — gemessen

In `karte_loesch`, `auftrag_endgueltig_loeschen(11)` (die massenstärkste Arbeit):

```
vorher:  19 gezählte Paletten, 1 Schimmelmessung, 1 Verdunstungswiegung, 2 Ausgangswiegungen
nachher: alle weg (7 Tabellen via CASCADE, 2 via ausdrücklichem delete in der Funktion)
Eingang    323 268 kg → 323 268 kg   (unverändert, kommt aus palette)
Verlust      52 119 kg →  52 574 kg   (+455 kg)
verwaiste Zeilen: verdunstung_wiegung ohne auftrag_id 23 → 24, sortier_lauf 0 → 1
```

**Ein Klick „endgültig löschen" verschiebt die Saisonbilanz um 455 kg und vernichtet
23 Messzeilen unwiderruflich.** Es gibt keinen Papierkorb und keine Rückfrage in der
Datenbank; die Funktion prüft nur `ist_admin()`.

---

## 4. Die 101 Ansichten und gespeicherten Ansichten

Spalten: **Ebenen** = längster Weg von einer Rohtabelle bis hierher (rekursiv über
`pg_depend`/`pg_rewrite`, s. 5). **SQL-Z.** = Zeilen in `pg_get_viewdef(…, true)`.
**wer liest** = `pg_depend` (andere Sicht), Textsuche in den 39 Funktionskörpern,
`grep` in `src/`, `test/`, `supabase/test/`, `pruefstand/`, `pruefwerk/`.
„**App**" heisst: das Frontend liest sie über `supabase.from(…)`.

| Name | Art | Sp. | Zeilen | SQL-Z. | Ebenen | baut auf | wer liest |
|---|---|--:|--:|--:|--:|---|---|
| `v_auftrag_angabe` | Sicht | 5 | 338 | 7 | 1 | auftrag_angabe | **App** · Sicht: v_schimmel_punkte · Test · Prüfstand |
| `v_auftrag_gebinde_masse` | Sicht | 7 | 110 | 36 | 3 | auftrag auftrag_gebinde charge sortierschema v_koeff_gebinde | Sicht: v_auftrag_masse, v_plausibilitaet, v_plausibilitaet_0054_zusatz · Test |
| `v_auftrag_masse` | Sicht | 15 | 308 | 39 | 5 | auftrag mv_auftrag_masse mv_sortier_eingang v_auftrag_gebinde_masse v_auftrag_wasch_paletten v_charge_rueckgrat v_koeff_palette_netto | **App** · Sicht: v_ausschuss_beobachtung, v_durchsatz, v_fax_beobachtung, v_kaskade_basis, v_massenbilanz, v_plausibilitaet, v_schimmel_beobachtung, v_schimmel_punkte · Test · Prüfstand |
| `v_auftrag_palette_masse` | Sicht | 7 | 530 | 61 | 3 | auftrag auftrag_palette gebinde v_charge_rueckgrat v_palette verdunstung_wiegung | Sicht: mv_auftrag_masse, mv_sortier_eingang · Test · Prüfstand |
| `v_auftrag_wasch_paletten` | Sicht | 7 | 94 | 27 | 3 | auftrag auftrag_palette charge sortierschema v_koeff_gebinde | Sicht: v_auftrag_masse, v_plausibilitaet_0054_zusatz · Test · Prüfstand |
| `v_ausgang_artikel_vorschlag` | Sicht | 13 | 11 | 52 | 1 | ausgang_artikel ausgang_zeile charge | Sicht: v_ausgang_lage, v_ausgang_pruef · Test · Prüfstand |
| `v_ausgang_kennzahl` | Sicht | 22 | 128 | 67 | 1 | auftrag ausgang_wiegung charge gebinde sortier_gewicht sortier_lauf sortierschema | **App** · Sicht: erg_ausgang, v_koeff_gebinde, v_koeff_palette_netto, v_koeff_ueberfuellung, v_lieferung_masse, v_ueberfuellung_verkauf · Test · Prüfstand |
| `v_ausgang_lage` | Sicht | 10 | 1 | 30 | 2 | ausgang_datei ausgang_quelle ausgang_zeile lieferung lieferung_import v_ausgang_artikel_vorschlag | **App** · Test · Prüfstand |
| `v_ausgang_pruef` | Sicht | 8 | 0 | 35 | 2 | ausgang_zeile lieferung lieferung_import v_ausgang_artikel_vorschlag | **App** · Test |
| `v_ausschuss_beobachtung` | Sicht | 8 | 49 | 30 | 6 | ausschuss_messung v_auftrag_masse v_koeff_verdunstung v_schimmel_menge v_sortier_lauf_masse | Sicht: erg_ausschuss, v_koeff_roh_kaliber, v_plausibilitaet · Test · Prüfstand |
| `v_charge_kohorte` | Sicht | 9 | 86 | 35 | 2 | auftrag auftrag_palette palette v_palette verdunstung_wiegung | Sicht: erg_kohorte, v_kaskade_basis, v_kohorte_anteil · Test |
| `v_charge_rueckgrat` | Sicht | 12 | 42 | 15 | 2 | charge v_palette | **App** · Sicht: erg_verlauf, v_auftrag_masse, v_auftrag_palette_masse, v_datenlage, v_kaskade_basis, v_lieferung_kohorte, v_plausibilitaet_0064_zusatz · Fn: demo_daten_laden · Test · Prüfstand |
| `v_datenlage` | Sicht | 10 | 42 | 20 | 3 | auftrag schimmel_messung sortier_lauf v_charge_rueckgrat verdunstung_wiegung | Sicht: erg_datenlage · Test |
| `v_datenqualitaet` | Sicht | 25 | 1 | 160 | 2 | auftrag auftrag_angabe auftrag_gebinde auftrag_palette ausschuss_messung schimmel_messung sortier_lauf v_palox_stand verdunstung_wiegung | Sicht: erg_datenqualitaet · Test · Prüfstand |
| `v_durchsatz` | Sicht | 14 | 305 | 23 | 6 | auftrag auftrag_teilnehmer v_auftrag_masse | Sicht: erg_durchsatz · Test |
| `v_fax_beobachtung` | Sicht | 19 | 161 | 28 | 6 | auftrag auftrag_gebinde charge v_auftrag_masse v_schimmel_menge | Sicht: erg_fax, v_koeff_roh_kaliber, v_plausibilitaet, v_saisonbilanz · Test · Prüfstand |
| `v_gewichtsverteilung` | Sicht | 5 | 1827 | 11 | 1 | auftrag charge sortier_gewicht sortier_lauf | Sicht: erg_gewichte · Test |
| `v_hochrechnung` | Sicht | 24 | 1197 | 25 | 15 | mv_hochrechnung | **App** (CSV-Export) · Test · Prüfstand |
| `v_hochrechnung_basis` | Sicht | 52 | 36 | 127 | 13 | mv_kaskade v_kaskade_basis | Sicht: erg_charge, v_plausibilitaet_0064_zusatz · Test · Prüfstand |
| `v_kaliber_verteilung` | Sicht | 8 | 119 | 9 | 2 | mv_kaliber_verteilung | Sicht: erg_kaliber · Test |
| `v_kaskade` | Sicht | 48 | 171 | 49 | 13 | mv_kaskade | Sicht: mv_hochrechnung, v_massenbilanz · Test · Prüfstand |
| `v_kaskade_basis` | Sicht | 21 | 36 | 57 | 6 | v_auftrag_masse v_charge_kohorte v_charge_rueckgrat | Sicht: mv_kaskade, v_hochrechnung_basis, v_massenbilanz, v_verlust_je_gruppe · Test |
| `v_koeff_ausschuss` | Sicht | 6 | 11 | 37 | 9 | sorte_kaliber v_koeff_kaliber_geschaetzt | Sicht: erg_koeff_ausschuss, mv_kaskade · Test |
| `v_koeff_fax` | Sicht | 6 | 11 | 37 | 9 | sorte_kaliber v_koeff_kaliber_geschaetzt | Sicht: mv_kaskade · Test · Prüfstand |
| `v_koeff_gebinde` | Sicht | 7 | 26 | 54 | 2 | auftrag auftrag_gebinde charge sortier_gewicht sortier_lauf v_ausgang_kennzahl | Sicht: erg_gebinde, v_auftrag_gebinde_masse, v_auftrag_wasch_paletten · Test · Prüfstand |
| `v_koeff_kaliber_geschaetzt` | Sicht | 16 | 36 | 106 | 8 | sorte_kaliber v_koeff_roh_kaliber | Sicht: v_koeff_ausschuss, v_koeff_fax, v_koeff_nebenkanal, v_koeff_unsicherheit · Test |
| `v_koeff_nebenkanal` | Sicht | 6 | 11 | 37 | 9 | sorte_kaliber v_koeff_kaliber_geschaetzt | Sicht: erg_koeff_nebenkanal, mv_kaskade · Test |
| `v_koeff_palette_netto` | Sicht | 6 | 21 | 8 | 2 | v_ausgang_kennzahl | Sicht: v_auftrag_masse · Test · Prüfstand |
| `v_koeff_roh_kaliber` | Sicht | 5 | 247 | 23 | 7 | v_ausschuss_beobachtung v_fax_beobachtung | Sicht: v_koeff_kaliber_geschaetzt · Test |
| `v_koeff_roh_verdunstung` | Sicht | 5 | 41 | 7 | 2 | v_verdunstung_messung | Sicht: v_koeff_verdunstung_geschaetzt |
| `v_koeff_ueberfuellung` | Sicht | 5 | 1 | 26 | 2 | v_ausgang_kennzahl | Sicht: erg_koeff_ueberfuellung · Test |
| `v_koeff_unsicherheit` | Sicht | 7 | 48 | 17 | 9 | v_koeff_kaliber_geschaetzt v_koeff_verdunstung_geschaetzt | Sicht: v_verlust_je_gruppe |
| `v_koeff_verdunstung` | Sicht | 6 | 11 | 48 | 4 | sorte_kaliber v_koeff_verdunstung_geschaetzt | Sicht: erg_koeff_verdunstung, mv_kaskade, v_ausschuss_beobachtung, v_massenbilanz, v_naechste_charge, v_schimmel_beobachtung · Test |
| `v_koeff_verdunstung_geschaetzt` | Sicht | 16 | 12 | 106 | 3 | sorte_kaliber v_koeff_roh_verdunstung | Sicht: v_koeff_unsicherheit, v_koeff_verdunstung |
| `v_kohorte_anteil` | Sicht | 5 | 86 | 7 | 3 | v_charge_kohorte | Sicht: mv_kaskade, v_lieferung_kohorte, v_naechste_charge, v_plausibilitaet · Test · Prüfstand |
| `v_kontrolle_vorschlag` | Sicht | 13 | 3 | 23 | 15 | erg_charge verdunstung_wiegung | **App** · Test · Prüfstand |
| `v_lieferung_kohorte` | Sicht | 8 | 117 | 41 | 4 | charge_vorlauf einstellung v_charge_rueckgrat v_kohorte_anteil v_lieferung_masse | Sicht: mv_kaskade · Test · Prüfstand |
| `v_lieferung_masse` | Sicht | 18 | 187 | 36 | 2 | ausgang_ziel lieferung v_ausgang_kennzahl | **App** · Sicht: erg_lieferung, erg_verlauf, v_lieferung_kohorte, v_plausibilitaet, v_plausibilitaet_0054_zusatz, v_saisonbilanz · Test · Prüfstand |
| `v_marge_buch` | Sicht | 6 | 3 | 49 | 17 | erg_ueberfuellung erg_verlust lieferung_import | Sicht: erg_marge · Test |
| `v_massenbilanz` | Sicht | 16 | 36 | 49 | 15 | erg_charge sortier_lauf v_auftrag_masse v_kaskade v_kaskade_basis v_koeff_verdunstung v_sortier_lauf_masse | Sicht: erg_massenbilanz · Test |
| `v_naechste_charge` | Sicht | 14 | 27 | 109 | 15 | erg_charge v_koeff_verdunstung v_kohorte_anteil v_schimmel_modell | Sicht: erg_naechste_charge · Test |
| `v_palette` | Sicht | 7 | 844 | 9 | 1 | gebinde palette | Sicht: erg_verlauf, v_auftrag_palette_masse, v_charge_kohorte, v_charge_rueckgrat, v_plausibilitaet_0064_zusatz · Test · Prüfstand |
| `v_palox_stand` | Sicht | 9 | 281 | 19 | 1 | auftrag schimmel_messung | Sicht: v_datenqualitaet, v_plausibilitaet, v_schimmel_menge · Test · Prüfstand |
| `v_plausibilitaet` | Sicht | 7 | 22 | **243** | 16 | 20 Quellen (s. Rohdaten) | Sicht: erg_plausibilitaet · Test · Prüfstand |
| `v_plausibilitaet_0054_zusatz` | Sicht | 7 | 10 | 49 | 15 | auftrag charge v_auftrag_gebinde_masse v_auftrag_wasch_paletten v_lieferung_masse v_plausibilitaet_0064_zusatz | Sicht: v_plausibilitaet |
| `v_plausibilitaet_0064_zusatz` | Sicht | 7 | 9 | 55 | 14 | auftrag auftrag_palette charge gebinde palette v_charge_rueckgrat v_hochrechnung_basis v_palette | Sicht: v_plausibilitaet_0054_zusatz |
| `v_saisonbilanz` | Sicht | 37 | 1 | 116 | 17 | charge_vorlauf erg_charge erg_verlust v_fax_beobachtung v_lieferung_masse | Sicht: erg_bilanz · Test · Prüfstand |
| `v_schimmel_beobachtung` | Sicht | 15 | 302 | 21 | 6 | v_auftrag_masse v_koeff_verdunstung v_schimmel_menge | Sicht: v_plausibilitaet, v_schimmel_punkte · Test |
| `v_schimmel_kurve` | Sicht | 8 | 7 | 27 | 9 | mv_schimmel_punkte | Sicht: erg_verlauf, mv_kaskade, v_schimmel_kurve_anzeige · Fn: schimmelanteil · Test |
| `v_schimmel_kurve_anzeige` | Sicht | 9 | 7 | 27 | 12 | v_schimmel_kurve v_schimmel_modell | Sicht: erg_kurve · Test |
| `v_schimmel_menge` | Sicht | 3 | 303 | 12 | 2 | schimmel_messung v_palox_stand | Sicht: v_ausschuss_beobachtung, v_fax_beobachtung, v_plausibilitaet, v_schimmel_beobachtung, v_schimmel_punkte · Test · Prüfstand |
| `v_schimmel_modell` | Sicht | 24 | 1 | 25 | 11 | mv_schimmel_modell | Sicht: erg_modell, erg_verlauf, mv_kaskade, v_naechste_charge, v_schimmel_kurve_anzeige, v_selektionsverdacht, v_verlust_je_gruppe · Fn: schimmelanteil, sockel_anteil · Test · Prüfstand |
| `v_schimmel_modell_rechnen` | Sicht | 24 | 1 | **298** | 9 | mv_schimmel_punkte | Sicht: mv_schimmel_modell |
| `v_schimmel_punkte` | Sicht | 10 | 142 | 65 | 7 | v_auftrag_angabe v_auftrag_masse v_schimmel_beobachtung v_schimmel_menge v_verdunstung_messung verdunstung_wiegung | Sicht: erg_punkte, mv_schimmel_punkte · Test · Prüfstand |
| `v_selektionsverdacht` | Sicht | 6 | 1 | 50 | 12 | mv_schimmel_punkte v_schimmel_modell | Sicht: erg_selektion · Test |
| `v_sortier_lauf_masse` | Sicht | 16 | 32 | 17 | 2 | mv_sortier_lauf_masse | Sicht: v_ausschuss_beobachtung, v_massenbilanz · Test |
| `v_ueberfuellung_verkauf` | Sicht | 27 | 114 | 104 | 2 | sortierschema v_ausgang_kennzahl v_verkauf_lieferung | Sicht: erg_ueberfuellung · Test |
| `v_verarbeitung_alter` | Sicht | 11 | 51 | 32 | 1 | auftrag auftrag_palette charge palette | Sicht: erg_verarbeitung_alter · Test |
| `v_verdunstung_messung` | Sicht | 15 | 41 | 25 | 1 | auftrag charge gebinde verdunstung_wiegung | Sicht: v_koeff_roh_verdunstung, v_plausibilitaet, v_schimmel_punkte · Test · Prüfstand |
| `v_verkauf_lieferung` | Sicht | 18 | 160 | 78 | 1 | ausgang_zeile charge lieferung lieferung_import sortierschema | Sicht: v_ueberfuellung_verkauf · Test · Prüfstand |
| `v_verlust_je_gruppe` | Sicht | 21 | 366 | **232** | 15 | mv_hochrechnung v_kaskade_basis v_koeff_unsicherheit v_schimmel_modell | Sicht: erg_verlust · Test |
| `v_verlust_ranking` | Sicht | 12 | 6 | 13 | 0 | *(Funktion `verlust_ranking()`)* | **nur Test/Prüfstand — in der App niemand** |
| `v_wiegung_kennzahl` | Sicht | 17 | 41 | 24 | 1 | auftrag charge gebinde verdunstung_wiegung | Sicht: erg_wiegung · Test · Prüfstand |
| `erg_ausgang` | gesp. | 22 | 128 | 23 | 2 | v_ausgang_kennzahl | **App** · Prüfstand |
| `erg_ausschuss` | gesp. | 8 | 49 | 9 | 7 | v_ausschuss_beobachtung | **App** · Prüfstand |
| `erg_bilanz` | gesp. | 37 | 1 | 38 | **18** | v_saisonbilanz | **App** · Test · Prüfstand |
| `erg_charge` | gesp. | 52 | 36 | 53 | 14 | v_hochrechnung_basis | **App** · Sicht: v_kontrolle_vorschlag, v_massenbilanz, v_naechste_charge, v_saisonbilanz · Test · Prüfstand |
| `erg_datenlage` | gesp. | 10 | 42 | 11 | 4 | v_datenlage | **App** · Prüfstand |
| `erg_datenqualitaet` | gesp. | 25 | 1 | 26 | 3 | v_datenqualitaet | **App** · Prüfstand |
| `erg_durchsatz` | gesp. | 14 | 305 | 15 | 7 | v_durchsatz | **App** · Prüfstand |
| `erg_fax` | gesp. | 19 | 161 | 20 | 7 | v_fax_beobachtung | **App** · Prüfstand |
| `erg_gebinde` | gesp. | 7 | 26 | 8 | 3 | v_koeff_gebinde | **App** · Prüfstand |
| `erg_gewichte` | gesp. | 5 | 1827 | 6 | 2 | v_gewichtsverteilung | **App** · Prüfstand |
| `erg_kaliber` | gesp. | 8 | 119 | 9 | 3 | v_kaliber_verteilung | **App** · Prüfstand |
| `erg_koeff_ausschuss` | gesp. | 6 | 11 | 7 | 10 | v_koeff_ausschuss | **App** · Prüfstand |
| `erg_koeff_nebenkanal` | gesp. | 6 | 11 | 7 | 10 | v_koeff_nebenkanal | **App** · Prüfstand |
| `erg_koeff_ueberfuellung` | gesp. | 5 | 1 | 6 | 3 | v_koeff_ueberfuellung | **App** · Prüfstand |
| `erg_koeff_verdunstung` | gesp. | 6 | 11 | 7 | 5 | v_koeff_verdunstung | **App** · Prüfstand |
| `erg_kohorte` | gesp. | 9 | 86 | 10 | 3 | v_charge_kohorte | **App** · Prüfstand |
| `erg_kurve` | gesp. | 9 | 7 | 10 | 13 | v_schimmel_kurve_anzeige | **App** · Prüfstand |
| `erg_lieferung` | gesp. | 18 | 187 | 19 | 3 | v_lieferung_masse | **App** · Prüfstand |
| `erg_marge` | gesp. | 6 | 3 | 7 | **18** | v_marge_buch | **App** · Prüfstand |
| `erg_massenbilanz` | gesp. | 16 | 36 | 17 | 16 | v_massenbilanz | **App** · Prüfstand |
| `erg_modell` | gesp. | 24 | 1 | 25 | 12 | v_schimmel_modell | **App** · Prüfstand |
| `erg_naechste_charge` | gesp. | 14 | 27 | 15 | 16 | v_naechste_charge | **App** · Prüfstand |
| `erg_plausibilitaet` | gesp. | 7 | 22 | 8 | 17 | v_plausibilitaet | **App** · Prüfstand |
| `erg_punkte` | gesp. | 10 | 142 | 11 | 8 | v_schimmel_punkte | **App** · Prüfstand |
| `erg_selektion` | gesp. | 6 | 1 | 7 | 13 | v_selektionsverdacht | **App** · Prüfstand |
| `erg_ueberfuellung` | gesp. | 27 | 114 | 28 | 3 | v_ueberfuellung_verkauf | **App** · Sicht: v_marge_buch · Test · Prüfstand |
| `erg_verarbeitung_alter` | gesp. | 11 | 51 | 12 | 2 | v_verarbeitung_alter | **App** · Prüfstand |
| `erg_verlauf` | gesp. | 12 | 649 | 158 | 13 | charge charge_vorlauf einstellung mv_kaskade palette v_charge_rueckgrat v_lieferung_masse v_palette v_schimmel_kurve v_schimmel_modell | **App** · Test · Prüfstand |
| `erg_verlust` | gesp. | 21 | 366 | 22 | 16 | v_verlust_je_gruppe | **App** · Sicht: v_marge_buch, v_saisonbilanz · Fn: verlust_ranking · Test · Prüfstand |
| `erg_wiegung` | gesp. | 17 | 41 | 18 | 2 | v_wiegung_kennzahl | **App** · Prüfstand |
| `mv_auftrag_masse` | gesp. | 13 | 308 | 22 | 4 | auftrag charge v_auftrag_palette_masse | Sicht: v_auftrag_masse · Test |
| `mv_hochrechnung` | gesp. | 24 | 1197 | 42 | 14 | v_kaskade | Sicht: v_hochrechnung, v_verlust_je_gruppe |
| `mv_kaliber_verteilung` | gesp. | 8 | 119 | 13 | 1 | charge sortier_gewicht sortier_lauf sortierschema | Sicht: v_kaliber_verteilung · Test |
| `mv_kaskade` | gesp. | 48 | 171 | **615** | 12 | v_kaskade_basis v_koeff_ausschuss v_koeff_fax v_koeff_nebenkanal v_koeff_verdunstung v_kohorte_anteil v_lieferung_kohorte v_schimmel_kurve v_schimmel_modell | Sicht: erg_verlauf, v_hochrechnung_basis, v_kaskade · Test · Prüfstand |
| `mv_schimmel_modell` | gesp. | 24 | 1 | 25 | 10 | v_schimmel_modell_rechnen | Sicht: v_schimmel_modell |
| `mv_schimmel_punkte` | gesp. | 10 | 142 | 11 | 8 | v_schimmel_punkte | Sicht: v_schimmel_kurve, v_schimmel_modell_rechnen, v_selektionsverdacht |
| `mv_sortier_eingang` | gesp. | 2 | 25 | 6 | 4 | auftrag v_auftrag_palette_masse | Sicht: v_auftrag_masse |
| `mv_sortier_lauf_masse` | gesp. | 16 | 32 | 20 | 1 | charge sortier_gewicht sortier_lauf | Sicht: v_sortier_lauf_masse |

### 4.1 Reine Durchreichen (37 Stück)

Objekte, deren Definition nur eine Spaltenliste + ein `FROM` ohne `where/join/group/case`
enthält (`grep -viE '(where|join|group by|having|union|case|order by|distinct|over)'`):

* **30 `erg_*`** über die gleichnamige `v_*`-Sicht — das ist das gewollte Muster aus 0061
  (Vertrag zur App, entkoppelt von der Formel).
* **5 `v_*` über eine `mv_*`**: `v_hochrechnung`, `v_kaliber_verteilung`, `v_kaskade`,
  `v_schimmel_modell`, `v_sortier_lauf_masse`.
* **2 `mv_*` über eine `v_*`**: `mv_schimmel_punkte`, `mv_schimmel_modell`.

### 4.2 Welcher Frontend-Bildschirm liest was

`grep -rnoE "\.(from|rpc)\('[a-z_0-9]+'" src/`

| Datei | liest / ruft |
|---|---|
| `src/auswertung/daten.ts` | **alle 30 `erg_*`**, `v_hochrechnung`, `sortierschema`, `auswertung_stand`, RPC `schema_stand`, `auswertung_schritt` |
| `src/arbeit/daten.ts` | auftrag, auftrag_gebinde, auftrag_palette, auftrag_teilnehmer, ausgang_wiegung, ausschuss_messung, schimmel_messung, sortierschema, `v_auftrag_angabe` |
| `src/pages/Stammdaten.tsx` | auftrag, charge_vorlauf, einstellung, gebinde, kaeufer, palette, profil, sortierschema, `v_charge_rueckgrat`, RPC `auftrag_endgueltig_loeschen` |
| `src/betrieb/AusgangImport.tsx` | ausgang_artikel, ausgang_quelle, charge, sorte_kaliber, `v_ausgang_lage`, `v_ausgang_pruef`, RPC `ausgang_uebernehmen` |
| `src/pages/Lieferungen.tsx` | ausgang_ziel, charge, lieferung, sorte_kaliber, `v_lieferung_masse` |
| `src/pages/Chargen.tsx` | auftrag, `erg_lieferung`, `v_auftrag_masse` |
| `src/pages/Kontrolle.tsx` | `v_kontrolle_vorschlag`, verdunstung_wiegung |
| `src/pages/Betrieb.tsx` | auftrag, `erg_durchsatz` |
| `src/arbeit/FertigePaletteMaske.tsx` | ausgang_wiegung, `v_ausgang_kennzahl` |
| `src/pages/Warteschlange.tsx` | auftrag, sortier_lauf, RPC `auftrag_zuordnen`, `auftrag_manuell_zuordnen` |
| `src/pages/CsvUpload.tsx` | sortier_lauf, Storage-Bucket `rohdaten`, RPC `csv_lauf_speichern` |
| `src/pages/NeueArbeit.tsx` | auftrag, auftrag_teilnehmer, sortier_lauf, sortierschema, RPC `sortierschema_festlegen` |
| `src/arbeit/Korrektur.tsx` | **dynamisch** über `t.tabelle`: schimmel_messung, verdunstung_wiegung, ausschuss_messung, ausgang_wiegung, auftrag_palette, auftrag_gebinde |
| `src/components/DemoDaten.tsx` | palette, RPC `demo_daten_entfernen`, `auswertung_aktualisieren` |
| `src/arbeit/{Zaehler,Abschluss,FauleMaske,PaloxMaske,AusschussMaske,WiegenMaske}.tsx` | die jeweiligen Erfassungstabellen, RPC `auftrag_abbrechen`, `palox_letzter_stand` |

Nur **9 Ansichten** liest die App live: `v_auftrag_angabe`, `v_auftrag_masse`,
`v_ausgang_kennzahl`, `v_ausgang_lage`, `v_ausgang_pruef`, `v_charge_rueckgrat`,
`v_hochrechnung`, `v_kontrolle_vorschlag`, `v_lieferung_masse` (+ `v_palox_stand`
mittelbar über die RPC). Alles andere kommt aus den 30 `erg_*`.

---

## 5. Die 42 Funktionen

| Funktion | liefert | Sprache/Art | Rechte | wer ruft |
|---|---|---|---|---|
| `anteil_plausibel(numeric)` | boolean | sql immutable, **kein search_path** | authenticated | 4 Sichten (ausschuss/fax/schimmel_beobachtung, schimmel_punkte) |
| `auftrag_abbrechen(bigint,text)` | void | plpgsql | authenticated | App, `demo_daten_laden` |
| `auftrag_ende_setzen()` | trigger | plpgsql | — | Auslöser `auftrag_ende` |
| `auftrag_endgueltig_loeschen(bigint)` | void | plpgsql, prüft `ist_admin()` | authenticated | App (Stammdaten) |
| `auftrag_manuell_zuordnen(bigint,bigint)` | void | plpgsql | authenticated | App (Warteschlange) |
| `auftrag_schema_setzen()` | trigger | plpgsql, **kein search_path** | — | Auslöser `auftrag_schema` (nutzt `new.start_ts::date`) |
| `auftrag_zuordnen(bigint)` | zuordnung_status | plpgsql | authenticated | App, `csv_lauf_speichern` |
| `ausgang_uebernehmen(5 Args)` | jsonb | plpgsql, prüft `ist_admin()` | authenticated | App (AusgangImport) |
| `ausschuss_netto_setzen()` | trigger | plpgsql, **kein search_path** | — | Auslöser |
| `auswertung_aktualisieren()` | timestamptz | plpgsql **definer**, `jit=off` | **authenticated, ungeprüft** | App, Tests, Prüfwerk |
| `auswertung_schritt(int)` | jsonb | plpgsql **definer**, `jit=off` | **authenticated, ungeprüft** | App (5×), `auswertung_aktualisieren` |
| `auswertung_veraltet()` | trigger | plpgsql definer | — | **17 Auslöser** |
| `auswertung_wenn_veraltet()` | boolean | plpgsql definer, `jit=off` | authenticated | **nur Tests — die App ruft sie nie** |
| `csv_lauf_speichern(12 Args)` | bigint | plpgsql | authenticated | App (CsvUpload) |
| `demo_daten_entfernen()` | text | plpgsql definer, prüft `ist_admin()` | authenticated | App, Tests |
| `demo_daten_laden()` | text | plpgsql definer, prüft `ist_admin()`, **709 Zeilen** | authenticated | Tests, Prüfstand |
| `handle_new_user()` | trigger | plpgsql definer | — | Auslöser auf `auth.users` |
| `heute()` | date | sql stable | authenticated | **8 Sichten, 21 Stellen** (s. 8) |
| `ist_admin()` | boolean | sql stable definer | authenticated | **49 RLS-Regeln** + 6 Funktionen |
| `ist_aktiv()` | boolean | sql stable definer | authenticated | **12 RLS-Regeln** |
| `ist_beteiligt(bigint)` | boolean | sql stable definer | authenticated | **1 RLS-Regel** (`auftrag_aendern`) |
| `klassiere(bigint,int)` / `klassiere(text,int)` | TABLE | sql stable, **kein search_path** | authenticated | `lauf_neu_klassieren` (nur die schema_id-Fassung) |
| `korrekturfenster()` | interval `12 hours` | sql immutable, **kein search_path** | authenticated | **10 RLS-Regeln** (`now() - korrekturfenster()`) |
| `lauf_neu_klassieren(bigint)` | int | plpgsql | authenticated | `csv_lauf_speichern`, `auftrag_manuell_zuordnen` |
| `lieferung_import_zeilen_verbinden(text)` | int | sql | authenticated | `ausgang_uebernehmen`, `demo_daten_laden` |
| `palox_letzter_stand(station)` | numeric | sql stable, **kein search_path** | authenticated | App (PaloxMaske) |
| `palox_station(station)` | station | sql immutable, **kein search_path** | authenticated | `v_palox_stand` |
| `palox_tara_kg()` | numeric | sql stable, **kein search_path** | authenticated | `v_palox_stand`, `v_plausibilitaet` |
| `rolle_schuetzen()` | trigger | plpgsql definer | — | Auslöser auf `profil` |
| `schema_stand()` | int (66) | sql immutable | **authenticated + anon** | App (Vorprüfung) |
| `schimmel_netto_setzen()` | trigger | plpgsql, **kein search_path** | — | Auslöser |
| `schimmelanteil(numeric,text)` | numeric | sql stable, **kein search_path** | authenticated | `v_massenbilanz`, `v_schimmel_kurve_anzeige` — **nicht** von `mv_kaskade` (s. 10.4) |
| `sockel_anteil()` | numeric | sql stable, **kein search_path** | authenticated | `v_massenbilanz` |
| `sortierschema_festlegen(6 Args)` | bigint | plpgsql definer, prüft `ist_aktiv()` | authenticated | App (NeueArbeit) |
| `sortierschema_fuer(text,text,date)` / `(…,text)` | bigint | sql stable, **kein search_path** | authenticated | `auftrag_schema_setzen`, `lauf_neu_klassieren`, `klassiere` |
| `stichtag()` | date | sql stable | authenticated | `v_kaskade_basis`, `erg_verlauf` |
| `t_quantil_95(int)` | numeric | sql immutable, **kein search_path** | authenticated | **8 Sichten** (alle Bänder) |
| `verlust_ranking(text,text,int)` | TABLE | sql stable | authenticated | nur `v_verlust_ranking` → **nur Test/Prüfstand** |
| `zahl(numeric,int,numeric)` / `zahl(float8,…)` | numeric | sql immutable | authenticated + **anon** | **163 Aufrufe** im Rechenwerk |

**14 Funktionen ohne festen `search_path`** (`proconfig is null`): alle davon
`security invoker`, drei davon Auslöserfunktionen (`auftrag_schema_setzen`,
`ausschuss_netto_setzen`, `schimmel_netto_setzen`). Alle acht `security definer`-Funktionen
haben `set search_path = public` — die scharfe Kante ist also zu.

---

## 6. Die Tiefe des Ansichtenstapels

Kanten aus `pg_depend`/`pg_rewrite` (289 Kanten zwischen 129 Objekten):

```sql
select distinct dep.relname, src.relname
  from pg_depend d
  join pg_rewrite r on r.oid=d.objid and d.classid='pg_rewrite'::regclass
  join pg_class dep on dep.oid=r.ev_class
  join pg_class src on src.oid=d.refobjid …
```

### 6.1 Der längste Pfad: **18 Kanten, 19 Objekte**

```
gebinde
 → v_palette
 → v_charge_rueckgrat
 → v_auftrag_palette_masse
 → mv_sortier_eingang
 → v_auftrag_masse
 → v_schimmel_beobachtung
 → v_schimmel_punkte
 → mv_schimmel_punkte
 → v_schimmel_modell_rechnen
 → mv_schimmel_modell
 → v_schimmel_modell
 → mv_kaskade
 → v_kaskade
 → mv_hochrechnung
 → v_verlust_je_gruppe
 → erg_verlust
 → v_saisonbilanz
 → erg_bilanz        ← die Zahl auf dem Bildschirm
```

Der gleichlange zweite Pfad endet in `erg_marge`.

### 6.2 Drei verschiedene Tiefen — nicht verwechseln

| Mass | Wert | Bedeutung |
|---|--:|---|
| **Bau-Tiefe** (alle Kanten) | max **18** | so viele Definitionen liegen zwischen Rohtabelle und Ergebnis |
| **Live-Tiefe** (gespeicherte Sichten als Blatt) | max **10** | `auftrag → v_ausgang_kennzahl → v_koeff_gebinde → v_auftrag_gebinde_masse → v_auftrag_masse → v_kaskade_basis → v_hochrechnung_basis → v_plausibilitaet_0064_zusatz → v_plausibilitaet_0054_zusatz → v_plausibilitaet → erg_plausibilitaet` — das rechnet ein einzelner `refresh` durch |
| **Speicher-Tiefe** (nur `m`-Stufen) | max **7** | `erg_bilanz` und `erg_marge` liegen 7 gespeicherte Stufen über der Rohtabelle |
| **Lese-Tiefe der App** | **1** | jede `erg_*` ist beim Lesen ein Seq Scan über eine Tabelle (0.04–0.24 ms) |

### 6.3 Was hinter einer einzelnen Bildschirmzahl steckt (transitive Hülle)

| Ziel | Tabellen | Sichten | gesp. Sichten | Objekte gesamt | Zeilen SQL |
|---|--:|--:|--:|--:|--:|
| `erg_marge` | 21 | 40 | 9 | **71** | 2794 |
| `erg_bilanz` | 19 | 39 | 9 | **68** | **2862** |
| `erg_plausibilitaet` | 19 | 38 | 6 | 64 | 2648 |
| `erg_verlust` | 19 | 37 | 7 | 64 | 2528 |
| `v_kontrolle_vorschlag` | 19 | 35 | 7 | 62 | 2369 |
| `erg_charge` | 19 | 35 | 6 | 61 | 2346 |

Die Saisonbilanz `erg_bilanz` hängt an **19 der 28 Tabellen**: auftrag, auftrag_angabe,
auftrag_gebinde, auftrag_palette, ausgang_wiegung, ausgang_ziel, ausschuss_messung,
charge, charge_vorlauf, einstellung, gebinde, lieferung, palette, schimmel_messung,
sorte_kaliber, sortier_gewicht, sortier_lauf, sortierschema, verdunstung_wiegung.

### 6.4 Die Neurechnungs-Reihenfolge ist topologisch korrekt

Ich habe für jede der 38 gespeicherten Ansichten die Menge ihrer gespeicherten
Vorgänger (durch die Sichten hindurch) gebildet und gegen die Reihenfolge in
`auswertung_schritt` geprüft: **0 Verletzungen.** Keine gespeicherte Ansicht wird
erneuert, bevor eine ihrer Quellen erneuert ist.

---

## 7. Was niemand liest

### 7.1 Ansichten

**Genau eine ist im Betrieb tot:**
`v_verlust_ranking` (12 Spalten, 6 Zeilen) und die Funktion `verlust_ranking(text,text,int)`
dahinter. Kein `pg_depend`-Konsument, keine Funktion, kein `supabase.from`/`.rpc` in `src/`.
Gelesen nur von `supabase/test/pruefung.sql`, `supabase/test/simulation/lauf.sh`,
`pruefstand/kette_pruefen.sh`.
*Gegenrede:* Sie war bis 0051 die Grundlage des Ursachen-Bildschirms; `src/pages/Ursachen.tsx`
(527 Zeilen) rechnet die Rangliste heute aus `erg_verlust` selbst. Sie könnte als
SQL-Werkzeug für den Betriebsleiter im SQL-Editor gedacht sein — dann fehlt der Hinweis darauf.

Von den `mv_*` liest **keine einzige** das Frontend, aber alle acht haben einen
Sicht-Konsumenten. Tot ist keine davon.

### 7.2 Funktionen

* `verlust_ranking(text,text,int)` — s. o.
* `auswertung_wenn_veraltet()` — nur `supabase/test/`, die App macht die
  Veraltet-Prüfung selbst in `daten.ts:259–262`. Sie ist `security definer` und
  `authenticated` darf sie ausführen.
* `klassiere(text,int)` (die Sorte-Fassung) — nur von `klassiere(bigint,int)` selbst
  aufgerufen? Nein: sie ruft `sortierschema_fuer(p_sorte, null, current_date)` und dann
  die schema_id-Fassung. Aufgerufen wird sie von **niemandem** im Rechenwerk; im
  Frontend steht kein `.rpc('klassiere')`. Faktisch ein Bequemlichkeits-Einstieg für
  den SQL-Editor.

### 7.3 Auslöser, die fehlen (das gefährlichere Gegenstück)

`auswertung_veraltet()` hängt an **17** Tabellen. **8 Tabellen, deren Inhalt in die
Rechnung eingeht, haben ihn nicht:**

`auftrag_teilnehmer` (483 Zeilen, geht in `v_durchsatz`) · `charge` (42) ·
`ausgang_artikel` (11) · `ausgang_datei` (0) · `ausgang_quelle` (1) ·
`ausgang_zeile` (160) · `ausgang_ziel` (5) · `lieferung_import` (160).

**Gemessener Nachweis** (in `karte_db`):

```
update charge set sorte='Butterkin' where nr=1611;   -- 101 Paletten
→ auswertung_stand.geaendert_ts unverändert, "gilt_als_veraltet = f"
→ nach erzwungenem Neurechnen: Verlust 52 119.4 kg → 51 917.0 kg  (−202.4 kg)
```

Der Bildschirm hätte 202 kg falsch angezeigt, bis irgendwer irgendwo anders etwas
schreibt. *Gegenrede:* `charge` ändert nur der Betriebsleiter, und er drückt danach
vermutlich „neu rechnen". Aber `ausgang_zeile` ändert der Import-Bildschirm, und der
läuft ohne Zutun.

### 7.4 Indexe

Verfahren: `pg_stat_reset()`, dann ein voller `auswertung_aktualisieren()`, dann ein
vollständiger Dashboard-Lauf (alle 30 `erg_*` + 10 Sichten + 20 Tabellen), dann
`pg_stat_user_indexes`.

* **93 Indexe, 2032 kB.**
* **62 hatten danach `idx_scan = 0`.** 28 davon sind `unique`/Primärschlüssel und
  erzwingen Eindeutigkeit — die zählen nicht als Ballast.
* **34 sind nicht-eindeutig und wurden nie benutzt: zusammen 592 kB.**

Die grössten davon: `erg_gewichte_sorte` (32 kB), `mv_hochrechnung_charge` (32 kB),
`auftrag_charge_nr_start_ts_idx` (32 kB), dazu 31 × 16 kB.
Die 22 nie benutzten Indexe **auf gespeicherten Ansichten** (`erg_*`/`mv_*`) sind
besonders auffällig: eine gespeicherte Ansicht wird ganz gelesen, nicht gesucht.

**Vollständig überdeckte Indexpaare** (Präfix-Test über `pg_get_indexdef` je Spalte):

| überflüssig | wird gedeckt von |
|---|---|
| `ausschuss_auftrag (auftrag_id,art) WHERE gemessen` | `ausschuss_messung_auftrag_id_art_idx (auftrag_id,art)` |
| `schimmel_auftrag (auftrag_id) WHERE gemessen` | `schimmel_messung_auftrag_id_idx (auftrag_id)` |
| `palette_charge_nr_eingangsdatum_idx` | `palette_charge_netto (charge_nr,eingangsdatum,gebindeart)` |
| `mv_kaskade_charge (charge_nr)` | `mv_kaskade_pk (charge_nr,portion,coalesce(kohorte,…))` |
| `auftrag_palette_auftrag_id_idx (auftrag_id)` | `auftrag_palette_sortierdatum (auftrag_id,sortierdatum)` |
| `auftrag_charge_nr_start_ts_idx (charge_nr,start_ts)` | (deckt seinerseits `auftrag_aktiv`, wurde aber nie benutzt) |

Zusammen **152 kB**. Zwei Tabellen tragen also für dieselbe Spaltenfolge zwei Indexe —
`ausschuss_messung` und `schimmel_messung` je einmal als Teilindex und einmal voll.

**8 eindeutige Indexe auf gespeicherten Ansichten** (160 kB: `erg_verlust_pk`,
`erg_verlauf_pk`, `erg_charge_pk`, `mv_kaskade_pk`, `mv_kaliber_pk`,
`mv_auftrag_masse_pk`, `mv_sortier_eingang_pk`, `mv_sortier_lauf_masse_pk`) haben nur
einen Zweck: `refresh materialized view concurrently`. `grep -rin concurrently supabase/`
findet **keine einzige Stelle**, die das benutzt.
*Gegenrede:* Sie dokumentieren den Schlüssel der Ansicht und sind die Voraussetzung,
falls man später auf `concurrently` umstellen will (was den 2.6-s-Sperrbalken beim
Neurechnen beseitigen würde). Das ist ein guter Grund — aber dann gehört ein Satz dazu.

### 7.5 Spalten

**Von 1412 Spalten der Ansichten nennt 27 kein Konsument** — nicht die abhängige Sicht,
nicht eine Funktion, nicht `src/`, nicht Test oder Prüfstand:

| Sicht | Spalten |
|---|---|
| `erg_charge` | `weg2_anteil`, `anteil_gewaschen`, `eingangsdatum_rest`, `rest_alter_aus_zaehlung` |
| `erg_modell` | `ln_lambda`, `sxx`, `sigma2`, `sockel_var` |
| `erg_selektion` | `rest_verarbeitung`, `rest_lager` |
| `v_hochrechnung` | `d_r`, `d_eta`, `d_a`, `d_a0` |
| `v_ausgang_artikel_vorschlag` | `zeilen_mit_charge`, `bestaetigte_sorte`, `vorschlag_belege` |
| `v_charge_rueckgrat` | `eingang_brutto_kg`, `erster_eingang` |
| `v_sortier_lauf_masse` | `n_kaliber`, `masse_kaliber_kg` |
| `erg_lieferung` | `kisten_n` |
| `erg_massenbilanz` | `alter_band` |
| `v_auftrag_gebinde_masse`, `v_auftrag_wasch_paletten` | `n_messungen` |
| `v_kaskade_basis` | `hand_kg` |
| `v_schimmel_menge` | `n_ablesungen` |

*Gegenrede:* `v_hochrechnung` geht als Ganzes in den CSV-Export
(`hochrechnungLaden()` → `select('*')`), also erreichen `d_r`/`d_eta`/`d_a`/`d_a0` doch
einen Menschen. Für die restlichen 23 ist mir kein Weg zum Auge bekannt.

Zusätzlich sind **5 `erg_*`-Spalten in der ganzen Demosaison zu 100 % NULL**:
`erg_selektion.unterschied/rest_lager/n_lager`, `erg_modell.selektions_versatz`,
`erg_fax.abgebrochen_ts`.

### 7.6 Beschreibungen

| Objektart | gesamt | mit `comment on` |
|---|--:|--:|
| Ansichten | 63 | **63** |
| gespeicherte Ansichten | 38 | **38** |
| Tabellen | 28 | 17 |
| Funktionen | 42 | 23 |
| Spalten von Tabellen | 266 | 35 |
| **Spalten von Ansichten** | **1412** | **0** |

Migration 0063 („jede Sicht sagt, was sie ist") ist vollständig durchgezogen — auf
Objektebene. Auf Spaltenebene gibt es keine einzige Beschreibung, und genau dort
entstehen die Missverständnisse (`alter_lager_von` vs. `alter_lager_bis` in
`v_hochrechnung_basis:94/95` sind vertauscht benannt — `von` = `heute() - k.rest_bis`).

---

## 8. Die Zeit — jede Stelle

Datenbank auf `Etc/UTC` (`select current_setting('TimeZone')` → `Etc/UTC`).
Betrieb in der Schweiz: Winter UTC+1, Sommer UTC+2.

### 8.1 Alle `timestamptz → date`-Umwandlungen im Rechenwerk

44 `::date`-Vorkommen insgesamt; davon 9 auf `fn_demo_daten_laden` und 4 auf
Text-/Einstellungsparsen. **Die 14, bei denen ein echter Zeitstempel zu einem Tag wird:**

| Stelle | Ausdruck | wovon die Zahl abhängt |
|---|---|---|
| `mv_auftrag_masse:17` | `a.start_ts::date - m.eingangsdatum` | **Lagertage je Arbeit** — Eingangsgrösse der Verdunstung |
| `v_auftrag_masse:21` | `(m.start_ts::date - '2000-01-01') - tage_seit_epoche` | Lagertage der Waschen-Arbeiten |
| `v_auftrag_wasch_paletten:15` | `a.start_ts::date - ap.sortierdatum` | Zwischenlagertage |
| `v_verarbeitung_alter:4,11,13,23` | `a.start_ts::date - eingangsdatum` | Alter bei Verarbeitung, Tagesachse |
| `v_verdunstung_messung:13,16,19` | `w.wiege_ts::date - w.eingangsdatum` | **Nenner der Verdunstungsrate `r`** |
| `v_wiegung_kennzahl:12` | `w.wiege_ts::date - w.eingangsdatum` | Lagertage in der Wiegungsliste |
| `v_kontrolle_vorschlag:17` | `max(wiege_ts)::date` | „zuletzt gewogen" |
| `fn_auftrag_schema_setzen:14` | `new.start_ts::date` | welches Sortierschema gilt |
| `fn_lauf_neu_klassieren:11` | `coalesce(datei_zeit, gelesen_ts)::date` | welches Sortierschema gilt |

**Nirgends steht ein `at time zone`.** (`grep -c "at time zone"` über alle 140
Definitionen: 0 echte Umrechnungen, nur Typnamen `timestamp with time zone`.)

### 8.2 `current_date`, `now()`, `heute()`, `stichtag()`

* `current_date`: 9 Stellen, davon **5 in `demo_daten_laden`**, dazu `heute()`,
  `klassiere(text,int)` und 3× `sortierschema_festlegen`.
* `now()`: 20 Stellen in 8 Funktionen; ausserdem **23 Spaltenvorgaben** `default now()`
  und **10 RLS-Regeln** `ts > now() - korrekturfenster()`.
  Diese Vergleiche sind `timestamptz` gegen `timestamptz` und damit **zeitzonensicher** —
  hier ist nichts zu holen.
* `heute()` → `coalesce(einstellung['heute_test'], current_date)`: **21 Stellen in
  11 Sichten** — `erg_verlauf` (4), `v_hochrechnung_basis` (4), `v_kaskade_basis` (2),
  `v_kontrolle_vorschlag` (3), `v_lieferung_kohorte`, `v_naechste_charge`,
  `v_plausibilitaet_0054_zusatz` (2), `v_saisonbilanz`, `v_ueberfuellung_verkauf`,
  `v_verkauf_lieferung`.
* `stichtag()` → `greatest(saison_ende, heute())`: 3 Stellen (`v_kaskade_basis`, `erg_verlauf`).

### 8.3 Wie oft der Tag in der Demosaison tatsächlich kippt

```sql
select count(*) filter (where X::date <> (X at time zone 'Europe/Zurich')::date), count(*) …
```

| Spalte | Zeilen | Tag kippt |
|---|--:|--:|
| `auftrag.start_ts` | 309 | **5** (1.6 %) |
| `auftrag.ende_ts` | 306 | **11** (3.6 %) |
| `auftrag_palette.ts` | 854 | **34** (4.0 %) |
| `schimmel_messung.ts` | 585 | **14** (2.4 %) |
| `ausgang_wiegung.ts` | 128 | **7** (5.5 %) |
| `verdunstung_wiegung.wiege_ts` | 41 | **1** (2.4 %) |
| `ausschuss_messung.ts`, `palette.erfasst_ts`, `sortier_lauf.datei_zeit` | 34/844/32 | 0 |

Die fünf betroffenen Arbeiten (alle `waschen`, alle zwischen 22:25 und 23:58 UTC,
also **00:25–01:58 Ortszeit**) haben zusammen 9070 kg Eingang. Bei r ≈ 0.00052/Tag
(gemessen in `erg_koeff_verdunstung`, Sortenmittel 0.00046–0.00062) sind das
**≈ 4.7 kg falsch gerechnete Verdunstung** — 0.0015 % des Eingangs.
Bei der Verdunstungsrate selbst: mittlere Lagertage 86.39 (UTC) gegen 86.41 (Zürich),
also **+0.02 Tage bzw. 0.023 % relativ** auf `r`.

**Das ist klein. Der Startverdacht trägt in dieser Richtung nicht.** Er trägt in der
anderen:

### 8.4 Der teure Teil der Zeitfrage: `heute()` friert ein

`heute()` steht in Sichten, die zu gespeicherten Ansichten materialisiert werden. Der
Wert wird also **beim Neurechnen festgehalten**, nicht beim Ansehen. Die App entscheidet
„veraltet" allein an `geaendert_ts > berechnet_ts` (`src/auswertung/daten.ts:260–262`) —
**der Tageswechsel steht in dieser Bedingung nicht.**

Gemessen (`karte_db`, `einstellung.heute_test` auf zwei aufeinanderfolgende Tage gesetzt,
dazwischen `auswertung_aktualisieren()`):

| | 08.09.2026 | 09.09.2026 | Unterschied |
|---|--:|--:|--:|
| Verlust bis heute | 51 923.7 kg | 52 119.4 kg | **+195.7 kg** |
| davon Verdunstung | 23 444.6 kg | 23 530.2 kg | +85.6 kg |
| davon Faules | 26 060.2 kg | 26 170.3 kg | +110.1 kg |
| noch im Haus | 154 741.0 kg | 154 545.4 kg | −195.6 kg |

**Ein Tag Stillstand = 196 kg, die die Bilanz nicht zeigt.** Ein ruhiges Wochenende sind
zwei Tage, also ~390 kg. Über die Winterpause, in der niemand etwas erfasst, wandert die
Zahl beliebig weit weg — ohne dass irgendwo „veraltet" steht. Der Bildschirm schreibt
dazu ehrlich das eingefrorene Datum („Bis heute (09.09.2026)"), aber niemand vergleicht
es mit dem Kalender.

Dazu kommt der **Mischzeitbezug in `v_kontrolle_vorschlag`**: Diese Sicht ist *nicht*
materialisiert und ruft `heute()` dreimal live auf, verrechnet es aber mit
`erg_charge.im_haus_heute_kg`, das beim letzten Neurechnen entstand
(`heute() - coalesce(k.zuletzt, b.eingang_von)` × `b.im_haus_heute_kg`).
Der „Informationswert" der nächsten Kontrolle mischt also zwei Tagesstände.

### 8.5 Der JIT — und dass `demo` ihn anhat

Migration 0060 (`supabase/setup.sql:4339`) tut
`execute format('alter database %I set jit = off', current_database())` mit
`exception when others then raise notice`.

```
select datname, setconfig from pg_db_role_setting …
  postgres {jit=off} · demo64 {jit=off} · demo65 {jit=off}
  demo → nichts · demo66 → nichts · karte_db → nichts   (show jit → on)
```

`create database … template …` überträgt Datenbankeinstellungen **nicht**. Die
Referenzdatenbank `demo`, gegen die Tests, Prüfstand und Prüfwerk laufen, hat JIT an;
die Datenbank, in der die Migrationen liefen, hat ihn aus.

Was das kostet (`karte_db`, je frisch, einzeln gemessen):

| | jit=on | jit=off | Faktor |
|---|--:|--:|--:|
| `refresh materialized view mv_kaskade` | **4267 ms** | 570 ms | 7.5 |
| `refresh materialized view erg_verlauf` | **2584 ms** | 211 ms | 12.3 |

Der Betriebsweg ist geschützt: `auswertung_schritt` und `auswertung_aktualisieren`
tragen `set jit = off` an der Funktion. Deshalb misst `auswertung_aktualisieren()`
2603 ms statt der ~8900 ms, die dieselben 38 `refresh` in einer normalen Sitzung kosten.
Ungeschützt sind: jedes von Hand abgesetzte `refresh materialized view`
(z. B. in `run.sh`, in den Migrationen 0016/0026/0037/0041), der erste Aufbau beim
Einspielen von `setup.sql` (die `alter database` wirkt erst ab der nächsten Verbindung),
und jeder Nachbau in einer Kopie.

**Eine gesetzte Schutzmassnahme ist unterwegs verloren gegangen:** 0060 schrieb
`alter function verlust_ranking(text, text, numeric, int) set jit = off;` — 0061 löschte
genau diese Signatur (`drop function if exists verlust_ranking(text,text,numeric,int)`)
und legte eine dreiargumentige an, **ohne** `jit=off`. Der heutige
`proconfig` ist `{search_path=public}`. Kosten heute: 1.9 ms mit JIT gegen 1.7 ms ohne —
also **0.2 ms, praktisch nichts**. Der Befund ist nicht die Zeit, sondern dass es
niemandem aufgefallen ist.

---

## 9. Was die Rechnung kostet

### 9.1 Neurechnen, fünf Schritte (`demo`, jit an der Funktion aus)

| Schritt | Titel | Objekte | Dauer |
|---|---|--:|--:|
| 1 | Rohdaten (+ `analyze` aller 28 Tabellen) | 10 | 130 ms |
| 2 | Arbeiten | 16 | **1150 ms** |
| 3 | Kaskade | 3 | 665 ms |
| 4 | Ergebnis | 7 | 661 ms |
| 5 | Befunde | 2 | 295 ms |
| | **gesamt** | **38** | **2603 ms** |

Teuerste Einzelrechnungen (`explain (analyze) select * from <Quellsicht>`):

| Quellsicht | Zeit | erzeugt | Zeilen |
|---|--:|---|--:|
| `v_schimmel_modell_rechnen` | **535 ms** | `mv_schimmel_modell` | **1** |
| `v_verlust_je_gruppe` | 156 ms | `erg_verlust` | 366 |
| `v_plausibilitaet` | 104 ms | `erg_plausibilitaet` | 22 |
| `v_massenbilanz` | 68 ms | `erg_massenbilanz` | 36 |
| `v_koeff_ausschuss` | 62 ms | `erg_koeff_ausschuss` | 11 |
| `v_koeff_nebenkanal` | 61 ms | `erg_koeff_nebenkanal` | 11 |
| `v_schimmel_punkte` | 57 ms | `erg_punkte` **und** `mv_schimmel_punkte` (zweimal!) | 142 |

**20 % der ganzen Neurechnung geht für eine Zeile mit 24 Spalten drauf**
(`mv_schimmel_modell`, das Schimmelmodell).

### 9.2 Was die App beim Lesen zahlt

Jede `erg_*` liest sich in 0.04–0.24 ms (Seq Scan über eine kleine Tabelle).
Die neun live gerechneten Sichten:

| Sicht | Zeit | Zeilen |
|---|--:|--:|
| `v_auftrag_masse` | **21.8 ms** | 308 |
| `v_ausgang_kennzahl` | 6.8 ms | 128 |
| `v_lieferung_masse` | 2.4 ms | 187 |
| `v_charge_rueckgrat` | 2.0 ms | 42 |
| `v_kontrolle_vorschlag` | 1.1 ms | 3 |
| `v_palox_stand` | 1.1 ms | 281 |
| `v_hochrechnung` | **0.3 ms** | 1197 |

`v_hochrechnung` ist seit 0061 nur noch `select * from mv_hochrechnung`. Der Kommentar
in `src/auswertung/daten.ts` sagt bis heute: *„eine Sicht, die live rechnet … Sie hing
bis Runde I am Laden jeder Seite und kostete auf jedem Reiter Zeit"*. Das stimmt nicht
mehr: 0.3 ms für 1197 Zeilen.

### 9.3 Nutzlast

`select octet_length(json_agg(t)::text) from <sicht> t` über alle 30 `erg_*`:

| Saison | Dashboard-Nutzlast | Neurechnen | grösste Einzelantwort |
|---|--:|--:|---|
| 1× (`demo`) | **1064 kB** in 30 Anfragen | 2603 ms | `erg_verlust` 188 kB, `erg_verlauf` 172 kB, `erg_gewichte` 159 kB |
| 3× (`karte_gross`) | 2750 kB | 5613 ms | |
| 10× (`karte_gross`) | **8652 kB** | **16 408 ms** | `erg_gewichte` 18 270 Zeilen |

Dazu `v_hochrechnung` für den CSV-Export: **2007 kB** in einem Zug (1197 Zeilen × 24 Spalten).

### 9.4 Verhalten bei Vervielfachung — gemessen, nicht geschätzt

`karte_gross` wurde aus `demo` erzeugt, indem die Saison mit Versatz auf `charge.nr`
(+10000·k) und auf allen `bigint`-Schlüsseln (+1e6·k) kopiert wurde
(Skript `dreifach.sql`/`zehnfach.sql`, Auslöser via `session_replication_role = replica` aus).

| | 1× | 3× | 10× |
|---|--:|--:|--:|
| Chargen / Paletten / Arbeiten | 42 / 844 / 309 | 126 / 2532 / 927 | 420 / 8440 / 3090 |
| Eingang | 323 268 kg | 969 804 kg | 3 232 680 kg |
| Schritt 1 | 130 ms | 305 ms | 690 ms |
| Schritt 2 | 1150 ms | 2216 ms | 6270 ms |
| Schritt 3 | 665 ms | 1419 ms | 4174 ms |
| Schritt 4 | 661 ms | 1486 ms | 4354 ms |
| Schritt 5 | 295 ms | 478 ms | 1327 ms |
| **gesamt** | **2603 ms** | **5613 ms** | **16 408 ms** |
| Faktor gegen 1× | 1.0 | 2.15 | **6.3** |

**Die Rechnung kippt nicht um** — 10-fache Daten kosten 6.3-fache Zeit, also klar
unterlinear. Das ist ein ehrliches Entwarnungssignal für Werkstatt B.
*Einschränkung:* Zehn kopierte Saisons sind nicht dasselbe wie eine zehnmal grössere
Saison; die Gruppierung je Charge bleibt gleich gross. Eine einzelne Riesencharge könnte
sich anders verhalten. Das habe ich nicht gebaut.

Was **nicht** entwarnt ist: 16.4 s Wartezeit im Browser und 8.6 MB JSON auf ein Handy.

### 9.5 Fünf Schritte sind fünf Transaktionen

`src/auswertung/daten.ts:240–248` ruft `rpc('auswertung_schritt', {p_schritt: i})` in
einer Schleife 1…5. Jeder Aufruf ist eine eigene Transaktion. `berechnet_ts` wird erst in
Schritt 5 gesetzt.

Gemessen (`karte_db`, 40 `schimmel_messung`-Zeilen gelöscht, dann nur Schritte 1–3):

```
vorher    Σ erg_charge.im_haus = 154 545 kg | erg_bilanz.im_haus = 154 545 kg
nach 1–3  Σ erg_charge.im_haus = 155 383 kg | erg_bilanz.im_haus = 154 545 kg  → 838 kg Widerspruch
nach 1–5  Σ erg_charge.im_haus = 155 383 kg | erg_bilanz.im_haus = 155 383 kg  → 0
```

Wird zwischendrin die Verbindung getrennt oder das Tablet gesperrt, zeigt der Reiter
„Bestand" 155 383 kg und der Reiter „Saisonbilanz" 154 545 kg — beide ohne Warnung.
*Gegenrede:* `berechnet_ts` bleibt alt, also rechnet der nächste Aufruf neu, und die
Schritt-Meldung an den Benutzer nennt den Fehler. Das repariert es beim nächsten Laden —
nicht in dem Moment, in dem jemand hinsieht.

---

## 10. Doppelte Arbeit im Rechenwerk

### 10.1 `erg_punkte` ist zeichengleich mit `mv_schimmel_punkte`

`diff <(pg_get_viewdef erg_punkte) <(pg_get_viewdef mv_schimmel_punkte)` → **identisch**.
Inhalt: `except` in beide Richtungen → 0/0 Zeilen Unterschied, je 142 Zeilen.
Beide werden in Schritt 2 erneuert; `v_schimmel_punkte` wird dabei **zweimal gerechnet**
(gemessen: `refresh erg_punkte` 89.7 ms, `refresh mv_schimmel_punkte` 110.1 ms).
Speicher 64 + 80 kB, dazu drei Indexe.
Als reine Sicht über `mv_schimmel_punkte` bliebe der Vertrag zur App erhalten und
**~90 ms (3.5 % der Neurechnung) und 64 kB** fielen weg.

### 10.2 Zwei weitere gleiche Paare

| Paar | Zeilen | Unterschied | Speicher |
|---|--:|--:|--:|
| `erg_kaliber` ↔ `mv_kaliber_verteilung` | 119 / 119 | 0 | 32 + 48 kB |
| `erg_modell` ↔ `mv_schimmel_modell` | 1 / 1 | 0 | 24 + 24 kB |

`erg_kaliber` = `v_kaliber_verteilung` = `mv_kaliber_verteilung`. Drei Namen, ein Inhalt,
zwei Kopien im Speicher.

### 10.3 Sichten, die von mehreren gespeicherten Ansichten materialisiert werden

`v_schimmel_modell` (3×: `erg_modell`, `erg_verlauf`, `mv_kaskade`) ·
`v_auftrag_palette_masse` (2×) · `v_koeff_ausschuss`, `v_koeff_nebenkanal`,
`v_koeff_verdunstung`, `v_lieferung_masse`, `v_schimmel_kurve`, `v_schimmel_punkte` (je 2×).
Jede dieser Sichten wird pro Neurechnung so oft ausgerechnet, wie sie materialisiert wird.

### 10.4 Die Schimmelkurve steht zweimal im Code

`schimmelanteil(lagertage, szenario)` (Funktion, `1 - exp(-exp(ln_lambda_korrigiert + k·ln t))`)
wird von `v_massenbilanz` und `v_schimmel_kurve_anzeige` benutzt.
`mv_kaskade` rechnet dieselbe Formel **ausgeschrieben** in seinen 615 Zeilen.
Numerischer Vergleich über alle Kaskadenportionen:

```sql
select round(f - schimmelanteil(alter_tage), 8) from mv_kaskade where portion='lager';
→ 0.00000000 durchgehend
```

Heute stimmen sie überein. Es gibt aber keinen Test, der das festhält, und wer die eine
ändert, ändert die andere nicht mit.

---

## 11. Rechte — gemessen, nicht gelesen

Alle 78 Regeln sind `permissive` und gelten für die Rolle `authenticated`.
14 × `all`, 12 × `insert`, 11 × `delete`, 28 × `select`, 13 × `update`.

### 11.1 Was die drei Rollen wirklich können

Gemessen mit `set local role …; set local request.jwt.claim.sub = …`:

| | Tabellen | Sichten | gesp. Sichten | Funktionen |
|---|--:|--:|--:|--:|
| `anon` (nicht angemeldet) | 0 | 0 | 0 | **3** (`schema_stand`, `zahl`×2) |
| `authenticated` (Arbeiter oder Chef) | **28** | **63** | **38** | **42** |

**Alle 28 `select`-Regeln haben `using (true)`.** RLS beschränkt in diesem Schema
ausschliesslich das Schreiben. Ein angemeldeter Arbeiter (Tomasz, `rolle='arbeiter'`)
liest gemessen:

```
liest lieferung:   187 Zeilen (Kunde, Menge, Ziel)
liest erg_marge:     3 Zeilen (Deckungsbeitrag)
liest erg_bilanz:    1 Zeile  (ganze Saisonbilanz)
```

*Gegenrede:* Auf einem Familienbetrieb mit drei Konten ist das kein Geheimnisproblem, und
Runde A hat sich bewusst gegen Leserechte-Bastelei entschieden (`0009_anonyme_arbeiter`,
`0035_nur_angemeldete`). Trotzdem: dass die 38 gespeicherten Ansichten **grundsätzlich**
keine RLS kennen können, sollte irgendwo stehen, damit niemand später eine
mandantenfähige Fassung darauf baut.

### 11.2 Schreibversuche als Arbeiter — Ergebnis

| Versuch | Ergebnis |
|---|---|
| `insert into lieferung` | **abgelehnt** (`new row violates row-level security policy`) |
| `update charge` | **0 Zeilen** (RLS filtert) |
| `update einstellung` | **0 Zeilen** |
| `delete from palette` | **0 Zeilen** |
| `demo_daten_entfernen()` | **abgelehnt** — „Demo-Daten darf nur der Betriebsleiter entfernen." |
| `auftrag_endgueltig_loeschen(60)` | **abgelehnt** |
| `sortierschema_festlegen(…)` | **abgelehnt** (nicht `ist_aktiv`? nein: greift korrekt) |
| `auswertung_schritt(1)` | **durchgelassen** |
| `auswertung_aktualisieren()` | **durchgelassen** |

Die Wächter sitzen also alle richtig — **ausser bei der Neurechnung**.
`auswertung_schritt` und `auswertung_aktualisieren` sind `security definer`, ohne jede
Prüfung, und `grant execute on all functions in schema public to authenticated`
(`setup.sql:9316`) gibt sie jedem. Kosten pro Aufruf: 2.6 s CPU auf der Demosaison,
16.4 s auf der zehnfachen, und `refresh materialized view` sperrt die Ansicht dabei
gegen Leser.
*Gegenrede:* Die App ruft sie aus dem Auswertungs-Bildschirm, und ein Arbeiter, der
Zahlen sehen darf, muss sie auch neu rechnen dürfen. Dann ist es kein Rechtefehler,
sondern ein fehlender Riegel gegen Wiederholung (kein Sperren, keine Mindestwartezeit,
keine Warteschlange).

### 11.3 `auth.uid()` im Stub ist enger als in Supabase

`supabase/test/stub_supabase.sql` definiert
`auth.uid() = nullif(current_setting('request.jwt.claim.sub', true),'')::uuid`.
Das echte Supabase liest **auch** `request.jwt.claims` als JSON. Alle 30 Stellen in
`supabase/test/pruefung.sql` setzen den alten Namen — Test und Stub sind untereinander
einig, aber der JSON-Weg wird von keinem Test berührt. Ich konnte das nicht gegen eine
echte Supabase gegenprüfen.

---

## 12. Fallstricke, die ich beim Kartieren gefunden habe

1. **`drop … cascade` in der Namensliste.** `setup.sql:9286` macht für jeden der 26
   Namen `drop materialized view if exists %I cascade`. Heute hat keiner dieser 26 einen
   Abhängigen — ich habe alle geprüft. Sobald jemand eine Sicht über z. B. `erg_bilanz`
   legt, verschwindet sie beim nächsten `setup.sql`-Lauf **wortlos**, und der
   Fingerabdruckvergleich in `run.sh` Stufe 4 fängt es nur, wenn die Sicht auch aus den
   Migrationen entsteht. Die fünf gespeicherten Ansichten mit Abhängigen — `erg_charge`
   (4), `erg_verlust` (2), `erg_ueberfuellung` (1), `mv_kaskade` (3), `mv_schimmel_punkte`
   (3) — stehen **nicht** in dieser Liste. Das ist heute Glück, nicht Konstruktion.
2. **26 von 38 Objektnamen stehen nicht im Quelltext**, sondern in einem Array. Wer
   `grep erg_bilanz supabase/setup.sql` macht, findet die Erzeugung nicht.
3. **`zahl()` und der `numeric(p,s)`-Guss sind an 97 von 115 Stellen genau aufeinander
   abgestimmt** (Grenze = 10^(p−s)) — das ist saubere Arbeit. Aber die Abstimmung hat
   eine Rundungskante:
   ```sql
   select zahl(99999.999996::numeric, 5, 100000::numeric);            -- 100000.00000
   select zahl(99999.999996::numeric, 5, 100000::numeric)::numeric(10,5);
   -- ERROR: numeric field overflow
   ```
   `zahl` prüft **vor** dem Runden (`abs(p_wert) < p_grenze`), rundet dann aber nach
   oben über die Grenze. Das Fenster ist 5·10^(−s−1) breit — bei `numeric(14,2)` und
   Grenze 1e12 also 0.005 kg unterhalb einer Billion. Unerreichbar, aber es ist die
   einzige Stelle, an der aus einem stillen NULL ein harter Abbruch wird.
4. **Kein `refresh … concurrently`.** Während der 2.6 s (bzw. 16.4 s) hält jeder
   `refresh` eine `AccessExclusiveLock` auf die Ansicht. Wer gleichzeitig den
   Auswertungsbildschirm öffnet, wartet.
5. **`auswertung_stand` hat keine Schreibregel**, nur `stand_lesen using(true)`.
   Geschrieben wird sie ausschliesslich aus `security definer`-Funktionen. Das ist
   richtig, sieht aber beim Lesen der Regeln nach einer Lücke aus.

---

## 13. Reproduktionsbefehle für die nächsten Werkstätten

```bash
export PGHOST=/tmp/pgsock PGPORT=55432 PGUSER=postgres

# Abhängigkeitskanten (289 Stück)
psql -d demo -F'|' -At -c "select distinct dep.relname, dep.relkind::text, src.relname, src.relkind::text
 from pg_depend d join pg_rewrite r on r.oid=d.objid and d.classid='pg_rewrite'::regclass
 join pg_class dep on dep.oid=r.ev_class join pg_class src on src.oid=d.refobjid
 join pg_namespace ns on ns.oid=src.relnamespace join pg_namespace nd on nd.oid=dep.relnamespace
 where d.refclassid='pg_class'::regclass and dep.oid<>src.oid and ns.nspname='public'
   and nd.nspname='public' and src.relkind in ('r','v','m')"

# Indexnutzung (erst nach echtem Lauf!)
psql -d X -c "select pg_stat_reset()"; psql -d X -c "select auswertung_aktualisieren()"
# … Dashboard-Lauf …
psql -d X -c "select relname, indexrelname, idx_scan from pg_stat_user_indexes where schemaname='public' and idx_scan=0"

# Zeitzonenkippen je Spalte
psql -d demo -c "select count(*) filter (where ts::date <> (ts at time zone 'Europe/Zurich')::date), count(*) from <tabelle>"

# Wirkung eines Tages
psql -d X -c "update einstellung set wert=to_jsonb('2026-09-08'::text) where schluessel='heute_test'"
psql -d X -c "select auswertung_aktualisieren()"; psql -d X -c "select * from erg_bilanz"

# Saison vervielfachen
psql -d karte_gross -f .../dreifach.sql     # k in 1..2  → 3x
psql -d karte_gross -f .../zehnfach.sql     # k in 3..9  → 10x
```
