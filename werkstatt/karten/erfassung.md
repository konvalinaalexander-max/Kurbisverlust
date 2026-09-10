> **Alle Zahlen sind gemessen, nicht geschätzt** — ausser den Zeitkonstanten in
> Abschnitt 7, die ausdrücklich als Modellannahmen ausgewiesen sind. Zu jeder
> Zahl steht der Befehl. Gearbeitet wurde auf einer eigenen Kopie
> `karte_erfassung` (`create database karte_erfassung template demo`), am
> Projekt wurde **nichts verändert**.

---

# 0. Werkzeuge und Befehle

| Werkzeug | Was es misst | Aufruf |
|---|---|---|
| `scratchpad/felder.mjs` | alle `<input>/<select>/<textarea>` in `src/`, mit ID, Typ und der `<label htmlFor>`-Beschriftung, aufgelöst über `t('…')` gegen den deutschen i18n-Block | `node felder.mjs` |
| `scratchpad/i18n.mjs` | extrahiert die 218 deutschen Schlüssel aus `src/lib/i18n.ts` (Zeilen 27–280) | `node i18n.mjs` |
| `scratchpad/i18n_tot.mjs` | welche Schlüssel keine Maske verwendet | `node i18n_tot.mjs` |
| `scratchpad/schreiber.mjs` | parst jeden `.from('t').insert/update/upsert({…})`-Aufruf in `src/` und liest die Objektschlüssel der ersten Ebene — die **wirklich geschriebenen Spalten**, nicht nur Namenstreffer | `node schreiber.mjs` |
| `scratchpad/leser2.mjs` | Leser je Spalte aus drei Quellen: `pg_depend` auf Spaltenebene (`refobjsubid`), `pg_proc.prosrc`, `src/**` | `node leser2.mjs` |
| `scratchpad/zeit.mjs`, `zeit2.mjs` | Sekunden je Maske (Felder und Netzrunden gemessen, Konstanten offengelegt) | `node zeit.mjs` |
| `scratchpad/scanner_blind2.sh` | wie viele Spalten der Namenstest von `pruefstand/luecken.sh` durchwinkt | `bash scanner_blind2.sh` |
| psql-Experimente | „was passiert, wenn das Feld leer bleibt" — jeweils in `begin; … rollback;` | siehe Abschnitt 6 |

Der **Spaltenleser** ist der Kern und verdient eine Erklärung: PostgreSQL
speichert die Abhängigkeiten einer Sicht **spaltengenau** (`pg_depend.refobjsubid`
= `attnum`). Damit lässt sich exakt und ohne Textsuche beantworten, welche
Sicht welche Spalte liest:

```sql
select b.relname, b.attname, string_agg(distinct rw.relname, ', ')
from (…basis…) b
left join pg_depend d on d.refobjid=b.oid and d.refobjsubid=b.attnum
                     and d.classid='pg_rewrite'::regclass
left join pg_rewrite r on r.oid=d.objid
left join pg_class rw on rw.oid=r.ev_class and rw.relname <> b.relname
group by 1,2;
```

**Selbstprobe des Spaltenlesers:** `sortierschema.verlust_unter` und `.kanal_ab`
haben laut `pg_depend` **null** Sichtenleser. Das war ein Fehlalarm — beide
werden von der Funktion `kuerbis_klasse()` und von `src/auswertung/daten.ts:511`
gelesen. Genau daran habe ich gemerkt, dass die Sichtenabhängigkeit allein nicht
reicht, und Funktionen und Frontend dazugenommen. Ein Werkzeug, das nur eine
Quelle kennt, hätte hier zwei Spalten fälschlich für tot erklärt.

---

# 1. Der Bestand in Zahlen

```
node scratchpad/felder.mjs | awk -F' \\| ' '{split($1,a,"/"); print a[1]}' | sort | uniq -c
```

| Ort | Eingabeelemente |
|---|---|
| `src/pages/` (Betriebsleiter + Anmeldung + Neue Arbeit) | 51 |
| `src/arbeit/` (Arbeitermasken) | 30 |
| `src/betrieb/` (Ausgang-Import) | 4 |
| `src/components/`, `src/lib/` | 2 |
| **gesamt** | **87** |

Dazu die **dynamischen** Felder der Korrekturmaske (`src/arbeit/Korrektur.tsx`),
die als 3 statische Elemente gezählt werden, in Wirklichkeit aber
**43 verschiedene Spalten** editierbar machen (8 an `auftrag` + 35 in sieben
Tabellenblöcken; gezählt aus `TABELLEN`/`AUFTRAG_FELDER`, ohne `nurLesen`).

Beschriftungen: alle 30 Arbeiterfelder sind über `t('…')` beschriftet, alle
51 Betriebsleiterfelder fest deutsch — bewusst so (Korrektur.tsx:19f.).
**0 von 218** deutschen i18n-Schlüsseln sind unbenutzt
(`node scratchpad/i18n_tot.mjs`: 206 direkt über `t('…')`, 12 nur indirekt über
`TAETIGKEITEN.text` und die `ERKL`-Tabelle).

Datenbestand `demo` (Kopie `karte_erfassung`):
854 `auftrag_palette`, 585 `schimmel_messung`, 128 `ausgang_wiegung`,
41 `verdunstung_wiegung` (davon 24 Lagerkontrollen ohne Arbeit),
34 `ausschuss_messung`, 208 `auftrag_gebinde`, 309 `auftrag`, 187 `lieferung`;
844 Wareneingangspaletten mit 323 268 kg netto (`erg_bilanz`).

---

# 2. Die Karte: jedes Eingabefeld

Legende: **P/M** = Pflicht in der Maske · **NN** = `not null` in der Tabelle ·
**Leer** = was geschieht, wenn das Feld leer bleibt.

## 2.1 `src/pages/NeueArbeit.tsx` — Arbeit eröffnen (Assistent, 4–5 Bildschirme)

| Feld (id) | Beschriftung (de) | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `taet-*` (Wahl) | Sortieren / Waschen / Waschen + Sortieren / Fax | `auftrag.weg`, `.station`, `.ist_fax` | ja (Wahl springt zu Schritt 2) | ja / ja / ja | `ist_fax` false | `mv_auftrag_masse`, `v_durchsatz`, `v_verarbeitung_alter`, `v_palox_stand`, `v_koeff_gebinde`, `v_auftrag_wasch_paletten`, `stationsProfil()` | unmöglich — ohne Wahl kein Weiter |
| `charge` | Charge (getippt, `datalist` als Vorschlag) | `auftrag.charge_nr` | ja (`chargeBekannt`) | ja, FK auf `charge` | — | 15 Sichten | unmöglich; unbekannte Nummer wird rot gemeldet, Weiter bleibt gesperrt |
| `grenze-0` | Zu klein unter (g) | `sortierschema.verlust_unter` (über RPC `sortierschema_festlegen`) | ja, wenn Bänder angepasst | nein | „wie zuletzt" aus der geltenden Fassung | `kuerbis_klasse()`, `daten.ts:511` (Diagramm-Grenzen) | Vorschlag „wie zuletzt" wird übernommen |
| `grenze-1..n` | bis (g) / Zu gross ab (g) | `sortierschema.kaliber_baender`, `.kanal_ab` | ja (`aufsteigend()`) | nein | wie zuletzt | `v_auftrag_wasch_paletten`, `v_kaliber_verteilung`, `kuerbis_klasse()` | wie zuletzt |
| `kaliber-*` (Wahl) | Welches Kaliber wird gewaschen? | `auftrag.kaliber_idx` | ja (nur Waschen) | nein | — | `v_auftrag_wasch_paletten`, `v_ausgang_kennzahl`, `v_plausibilitaet` | **`v_plausibilitaet`-Zweig „Kaliber fehlt"**: die gezählten Kisten lassen sich keiner Masse zuordnen |
| `kaliber-von` / `kaliber-bis` | von (g) / bis (g) — eigenes Kaliber | `auftrag.kaliber_von_g`, `.kaliber_bis_g` | ja, wenn „anderes Kaliber" | nein (CHECK: beide oder keins) | — | `v_auftrag_wasch_paletten` (Bandsuche), `v_plausibilitaet_0054_zusatz` | s. o. |
| `soll` | kg je Kiste | `auftrag.soll_kg_pro_kiste` **und** `sortierschema.soll_kg_pro_kiste` | ja bei „Kiste ab x kg" | nein (CHECK > 0) | Einstellung `soll_kg_pro_kiste` = 8 | `v_ausgang_kennzahl.ueberfuellung_*`, `v_koeff_ueberfuellung` | keine Überfüllung berechenbar |
| `stueck` | Kürbisse je Kiste | `auftrag.stueck_je_kiste` | ja bei „x Stück je Kiste" | nein (CHECK > 0) | — | `v_ausgang_kennzahl.erwartet_kg_pro_kiste` | Erwartungswert je Kiste fehlt |
| (Wahl) | Kistensystem: Kiste ab / Stück / anderes | `auftrag.kistensystem` | ja, wo gefragt | nein (CHECK in 3 Werten) | — | `v_auftrag_masse`, `v_ausgang_kennzahl`, `v_fax_beobachtung` | `hatAusgang=false` → **keine fertige Palette wird verlangt**; Überfüllung und Fax-Palettenmasse entfallen |
| — (nicht gefragt) | Käufer | `auftrag.kaeufer` | — | nein | Maske schreibt **hart `null`** (NeueArbeit.tsx:171) | `v_datenqualitaet`, `v_fax_beobachtung` | immer leer, seit 0060 gewollt |

Der Auslöser `auftrag_schema_setzen` füllt `sortierschema_id` nach, wenn die
Maske keine Fassung mitgibt (309 von 309 Arbeiten haben eine).

## 2.2 `src/arbeit/Zaehler.tsx` — der Zähler

### a) Eingangspaletten (Sortieren, Waschen + Sortieren) — 530 Zeilen

| Feld (id) | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `zettel` | **Datum vom Zettel** | `auftrag_palette.eingangsdatum` | **ja** (`disabled … \|\| zettel === ''`) | **nein** | `localStorage['zettel_<id>']` — bleibt für die nächste Palette stehen | `v_auftrag_palette_masse`, `v_charge_kohorte`, `v_verarbeitung_alter`, `v_datenqualitaet`, `v_plausibilitaet` (Zweig „Zetteldatum") | Über die Maske unmöglich. Direkt in der Tabelle: die Masse fällt von `datum-mittel` auf `charge-mittel` zurück (Abschnitt 6.4) |
| `zettel-brutto` | **Gewicht vom Zettel (kg)** | `auftrag_palette.brutto_zettel_kg` | ja, nur bei `waschen_sortieren` (`bruttoOk`) | nein (CHECK > 0) | leer, je Palette neu | `v_auftrag_palette_masse` (Zweig `zettel` / `zettel-charge-tara`), `v_plausibilitaet` (Zweig „Zettelgewicht") | beim Sortieren wird `null` geschrieben — die Masse kommt dann aus dem Tagesmittel |
| Knopf `zaehlen-plus` | „+ 1 Palette hingestellt" | erzeugt die Zeile | — | — | — | — | — |
| Knopf `zaehlen-minus` | „↶ Rückgängig" | löscht die letzte Zeile **und die zugehörige `verdunstung_wiegung`** (Zaehler.tsx:105) | — | — | — | — | — |

### b) Kaliber-Paletten aus dem Zwischenlager (Waschen) — 324 Zeilen

| Feld (id) | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `sortierdatum` | **Sortierdatum vom Zettel** | `auftrag_palette.sortierdatum` | **ja** (oder Häkchen) | nein | `localStorage['sortierdatum_<id>']` | `v_auftrag_wasch_paletten.zwischenlager_tage` + `.n_mit_sortierdatum`, `v_datenqualitaet.wasch_kisten_mit_sortierdatum` | Häkchen „kein Sortierdatum" schreibt `null`; die Palette zählt weiter, nur der Zwischenlagertag fehlt |
| `kein-sortierdatum` | „kein Sortierdatum auf dem Zettel" | — (nur Steuerung) | — | — | aus | — | — |
| `kisten-palette` | **Kisten auf der Palette** | `auftrag_palette.kisten` | **ja** (`Number.isInteger && > 0`) | nein (CHECK NULL oder > 0) | `localStorage`, sonst Einstellung `kisten_pro_palette` = **32** | `v_auftrag_wasch_paletten.kisten` → `kg = kisten × v_koeff_gebinde.kg_je_gebinde` → **die ganze Masse dieser Arbeit** | über die Maske unmöglich |

**Gemessen:** 234 von 324 Zeilen (72 %) tragen genau die Vorgabe 32
(`select kisten, count(*) from auftrag_palette where kisten is not null group by 1 order by 2 desc`).
Summe 8 912 Kisten, Mittel 27,5.

### c) Kisten je Kaliber (Sortieren) — der teuerste Knopf im Programm

| Feld | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `kiste-plus-<i>` / `−` | Kaliber 1..n · „x–y g" | `auftrag_gebinde.anzahl` (upsert je Tipp) | nein | ja, Vorgabe **0** | 0 | `v_auftrag_gebinde_masse`, `v_koeff_gebinde`, `v_fax_beobachtung`, `v_plausibilitaet` (Zweig „Kistengewicht") | `anzahl = 0` → `v_koeff_gebinde` überspringt (`g.anzahl > 0`) |
| — (immer `null`) | — | `auftrag_gebinde.sortierdatum` | — | nein | Maske schreibt hart `null` | `v_datenqualitaet` | 207 von 208 Zeilen `null` |
| — (immer `false`) | — | `auftrag_gebinde.datum_fehlt` | — | ja, Vorgabe false | Maske schreibt hart `false` | `v_datenqualitaet` | **0 von 208** je `true` |

**Es gibt kein Eingabefeld — nur `−` und `+`.** Die Zahl steht als
`<span className="stand">` (Zaehler.tsx:270), nicht als `<input>`.

**Gemessen:**
`select sum(anzahl), count(*), max(anzahl) from auftrag_gebinde`
→ **16 254 Tipper**, **208 gespeicherte Zahlen**, grösste Einzelzahl **435**.
Das sind **78,1 Tipper je gespeicherter Zahl**.
`v_koeff_gebinde` aggregiert ohnehin **je Arbeit und Band** — die
Informationsmenge dieser 16 254 Tipper sind exakt 208 ganze Zahlen.

### d) Palettenzahl (Fax)

| Feld (id) | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `paletten-gesamt` | **Paletten gemacht (gesamt)** | `auftrag.paletten_gesamt` | ja im Abschluss (`palettenOk`) | nein (CHECK ≥ 0) | bestehender Wert | `v_auftrag_masse` (Zweig `fax_paletten`), `v_fax_beobachtung`, `v_datenqualitaet` | `v_plausibilitaet`-Zweig **„Ohne Nenner"**: das gewogene Faule fliesst nirgends ein |

Hier gibt es − / **Zifferneingabe** / + — dieselbe Datei, 120 Zeilen über dem
Kaliberzähler, der diese Zifferneingabe nicht hat.

## 2.3 `src/arbeit/PaloxMaske.tsx` — Palox ablesen (281 Zeilen)

| Feld (id) | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `palox` | **Waage zeigt (kg)** | `schimmel_messung.palox_stand_kg` | **ja** (`n === null \|\| n < 0` sperrt) | nein (CHECK ≥ 0) | leer | `v_palox_stand.differenz` → `v_schimmel_menge` → **50 % des Saisonverlusts**; `v_plausibilitaet` (Zweige „Palox", „Palox geleert") | unmöglich |
| — (abgeleitet, JS) | — | `schimmel_messung.kg` | — | **ja** | `Math.round(max(menge,0))` in der Maske | **für Palox-Zeilen von niemandem** — `v_schimmel_menge` rechnet `p.differenz` neu (siehe 9.4) | — |
| — (hart `false`) | — | `schimmel_messung.palox_geleert` | — | ja, Vorgabe false | Maske schreibt hart `false` | `v_palox_stand` | 13 von 585 Zeilen sind `true`, keine davon aus einer Maske |
| Knopf `palox-unveraendert` | „Stand unverändert" | `kg = 0`, `palox_stand_kg = vorher` | — | — | — | wie oben | ist eine Messung, kein Auslassen |

## 2.4 `src/arbeit/FauleMaske.tsx` — Faules wiegen, Fax (298 Zeilen)

| Feld (id) | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `faul-brutto` | **Gewicht (kg)** | `schimmel_messung.brutto_kg` | **ja** (`netto === null` sperrt) | nein | leer | **nur der Auslöser `schimmel_netto_setzen`** — 0 Sichten, 0 weitere Funktionen | unmöglich |
| `faul-kisten` | **Anzahl Kisten** | `schimmel_messung.kisten` | ja | nein | **„1"**, wird nach dem Speichern auf „1" zurückgesetzt | **nur der Auslöser** | direkt gesetzt: Auslöser setzt `gemessen = false`, `kg` behält den mitgeschickten Wert → die Zeile verschwindet still aus `v_schimmel_menge` |
| `faul-art` | **Art der Kiste** | `schimmel_messung.gebindeart` | ja (Liste, nie leer) | nein, FK auf `gebinde` | `gebinde[0].art` (alphabetisch = **G2**) | **nur der Auslöser** | wie oben |
| `faul-palette` | „auf Palette gewogen" | `schimmel_messung.mit_palette` | nein | ja, Vorgabe false | aus | **nur der Auslöser** | **0 von 298** je angehakt |
| — (abgeleitet) | — | `schimmel_messung.kg` | — | ja | Auslöser: `greatest(round(brutto − kisten×tara − [palette]), 0)` | `v_schimmel_menge`, `v_palox_stand` | — |
| Knopf `faul-nichts` | „Nichts Faules" | `kg = 0`, `bemerkung = 'Nichts Faules'` | — | — | — | `bemerkung`: **niemand** | — |

## 2.5 `src/arbeit/WiegenMaske.tsx` — Eingangspalette wiegen (17 Zeilen)

| Feld (id) | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `w-datum` | **Datum auf der Palette** | `verdunstung_wiegung.eingangsdatum` **und** `auftrag_palette.eingangsdatum` | **ja** (`vollstaendig`) | **ja** / nein | Zettel-Datum aus `localStorage` | `v_verdunstung_messung.lagertage`, `v_wiegung_kennzahl`, `v_charge_kohorte` | unmöglich |
| `w-damals` | **Gewicht beim Eingang (kg)** | `verdunstung_wiegung.brutto_damals_kg` (+ `auftrag_palette.brutto_zettel_kg`, nur W+S) | **ja** | **ja** | Zettelgewicht aus dem Zähler | `v_verdunstung_messung.netto_damals_kg` → **Verdunstungsrate** (45 % des Verlusts) | unmöglich |
| `w-jetzt` | **Gewicht jetzt (kg)** | `verdunstung_wiegung.brutto_jetzt_kg` | **ja** | **ja** | leer | dito | unmöglich |
| `w-kisten` | **Anzahl Kisten** | `verdunstung_wiegung.kisten` | **ja** | **nein** | leer | `v_verdunstung_messung`, `v_wiegung_kennzahl`, `v_auftrag_palette_masse` | **Maske und Tabelle uneinig.** Direkt gesetzt: Netto wird NULL, die Zeile bleibt in `v_verdunstung_messung`, fällt aber aus `v_koeff_roh_verdunstung` — und **`v_plausibilitaet` schweigt** (Abschnitt 6.2) |
| `w-art` | **Art der Kiste** | `verdunstung_wiegung.gebindeart` | ja (Liste) | nein, FK | `gebinde[0].art` = G2 | dito | dito |
| `w-pro` | Kürbisse in einer Kiste **(freiwillig)** | `verdunstung_wiegung.kuerbisse_pro_kiste` | nein | nein (CHECK > 0) | leer | `v_wiegung_kennzahl.kg_pro_kuerbis` → `erg_wiegung` → **eine Spalte in einer Tabelle** auf `pages/Messungen.tsx:193` | Spalte zeigt „—". 17 von 41 Zeilen gefüllt |
| — | — | `verdunstung_wiegung.charge_nr` | Kontext | **ja**, FK | `d.auftrag.charge_nr` | `v_datenlage`, `v_kontrolle_vorschlag`, … | — |

## 2.6 `src/arbeit/AusschussMaske.tsx` — zu klein / zu gross (34 Zeilen)

| Feld (id) | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `aus-zu_klein` / `aus-zu_gross` | „Zu klein" / „Zu gross" | `ausschuss_messung.art` | ja (Wahl, vorbelegt) | **ja** | `zu_klein` | `v_ausschuss_beobachtung`, `v_plausibilitaet` | vorbelegt — **stille Fehlerquelle**: wer die Wahl übersieht, bucht auf „zu klein" |
| `aus-brutto` | **Gewicht (kg)** | `ausschuss_messung.brutto_kg` | **ja** | nein | leer | Auslöser `ausschuss_netto_setzen`, `v_datenqualitaet`, `v_plausibilitaet` (2 Zweige) | unmöglich |
| `aus-kisten` | **Anzahl Kisten** | `ausschuss_messung.kisten` | **ja** | nein | leer (wird nach Speichern geleert) | Auslöser, `v_plausibilitaet` | Zweig **„Ausschuss ohne Tara"** meldet „die Kistenzahl fehlt" |
| `aus-art` | **Art der Kiste** | `ausschuss_messung.gebindeart` | ja (Liste) | nein, FK | G2 | Auslöser, `v_plausibilitaet` | Zweig „Ausschuss ohne Tara" |
| — (abgeleitet) | — | `ausschuss_messung.kg` | — | **ja** (CHECK ≥ 0) | Auslöser: `brutto − kisten×tara_kiste − tara_palette` (Palettentara **immer**, ohne Häkchen) | `v_ausschuss_beobachtung`, `v_plausibilitaet` | — |
| Knopf `aus-nichts` | „Nichts zu klein oder zu gross" | zwei Zeilen mit `kg = 0` und `bemerkung` | — | — | — | `bemerkung`: **niemand** | — |

## 2.7 `src/arbeit/FertigePaletteMaske.tsx` — fertige Palette (128 Zeilen)

| Feld (id) | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `a-brutto` | **Gewicht (kg)** | `ausgang_wiegung.brutto_kg` | **ja** | **ja** (CHECK > 0) | leer | `v_ausgang_kennzahl` → `erg_ausgang`, `v_koeff_ueberfuellung`, `v_koeff_gebinde` (Kanal −1) | unmöglich |
| `a-kisten` | **Anzahl Kisten** | `ausgang_wiegung.kisten` | **ja** | **ja** (CHECK > 0) | leer | dito | unmöglich |
| `a-art` | **Art der Kiste** | `ausgang_wiegung.gebindeart` | ja (Liste) | **nein**, FK | G2 | `v_ausgang_kennzahl` | **Maske und Tabelle uneinig.** Direkt leer gelassen: die Zeile **verschwindet lautlos** aus `v_ausgang_kennzahl` und wird von keiner Prüfung gemeldet (Abschnitt 6.1) |
| `a-kaliber` | Kaliber der Palette | `ausgang_wiegung.kaliber_idx` | ja bei „Stück" und > 1 Band (`kaliberOk`) | nein | `a.kaliber_idx`, sonst `−2` bei eigenem Kaliber | `v_ausgang_kennzahl.erwartet_kg_pro_kiste`, `.band_mittel_g` | Erwartungswert fällt weg; 94 von 128 gefüllt |
| `a-pro` | Kürbisse in einer Kiste (bei „Kiste ab": **freiwillig**) | `ausgang_wiegung.kuerbisse_pro_kiste` | nein | nein (CHECK > 0) | `a.stueck_je_kiste` | `v_ausgang_kennzahl.kg_pro_kuerbis`, `.stueck_je_kiste` | fällt zurück auf `a.stueck_je_kiste`; 126 von 128 gefüllt |

## 2.8 `src/arbeit/Abschluss.tsx` — der geführte Abschluss (3–6 Bildschirme)

| Feld (id) | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `ab-paletten` | **Paletten gemacht (gesamt)** | `auftrag.paletten_gesamt` | **ja** (Fax) | nein | bestehender Wert | s. 2.2 d | Weiter gesperrt |
| `ab-tage` | Tage seit dem Waschen **(freiwillig)** | `auftrag.tage_seit_waschen` | nein | nein (CHECK ≥ 0) | bestehender Wert | `v_fax_beobachtung`, `v_datenqualitaet` | 142 von 309 gefüllt |
| `charge-ja` / `charge-nein` | „Alles aus einer Charge?" | `auftrag_angabe(schluessel='eine_charge')` | **ja** (im `fehlt`-Block) | `schluessel`/`wert` ja | — | `v_schimmel_punkte` (nur `wert='false'` → Quelle `verarbeitung_gemischt`), `v_datenqualitaet` | Abschluss gesperrt. **Gemessen: 304 von 304 Antworten sind `true`; die Quelle `verarbeitung_gemischt` hat 0 Zeilen** |
| `sorte-ja` / `sorte-nein` | „Alles die gleiche Sorte?" | `auftrag_angabe(schluessel='gleiche_sorte')` | ja, wenn oben „nein" | ja | — | **niemand** — 0 Sichten, 0 Funktionen, 0 Frontend | ein Bildschirm ohne Wirkung |
| Knopf `arbeit-fertig` → `ja-fertig` | „Fertig" → „Ja, fertig" | `auftrag.status='abgeschlossen'`; `ende_ts` setzt der Auslöser | — | ja | `offen` | `mv_auftrag_masse`, `v_durchsatz`, … | — |
| Knopf `ja-abbrechen` | „Ja, abbrechen" | RPC `auftrag_abbrechen(id, **null**)` | — | — | Grund **immer `null`** | `auftrag.abbruch_grund` → `v_datenqualitaet` | der Abbruchgrund ist über keine Maske erreichbar |

## 2.9 `src/pages/Kontrolle.tsx` — Lagerkontrolle (24 Zeilen)

Felder wie 2.5, ohne `kuerbisse_pro_kiste`, plus die Chargenwahl aus
`v_kontrolle_vorschlag` (drei Vorschläge + „andere"). `auftrag_id` bleibt `null`
— genau daran erkennt `Kontrollkorrektur` diese Zeilen.
Die Maske bleibt nach dem Speichern für die nächste Palette stehen; Charge und
Kistenart bleiben, Datum/Gewichte/Kisten werden **sofort** geleert
(Kontrolle.tsx:70–76) — bewusst gegen den Verlust schneller Folgeeingaben.

## 2.10 `src/pages/Lieferungen.tsx` — Warenausgang von Hand (187 Zeilen)

| Feld (id) | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| `l-datum` | Datum | `lieferung.datum` | ja | ja | heute | `v_lieferung_masse`, `v_verkauf_lieferung`, `v_kohorte_anteil` | vorbelegt |
| `l-charge` | Charge (wenn bekannt) | `lieferung.charge_nr` | nein | nein, FK | „— keine —" | dito | Zuordnung nur über die Sorte; 177 von 187 gefüllt |
| `l-sorte` | Sorte | `lieferung.sorte` | ja, wenn keine Charge (CHECK `lieferung_zuordnung`) | nein, FK | — | dito | Fehlermeldung „Sorte oder Charge angeben" |
| `l-einheit` | Einheit (kg / Kisten) | steuert `kg` vs. `kisten` | ja | — | `kg` | — | — |
| `l-menge` | Kilo / Anzahl Kisten | `lieferung.kg` **oder** `.kisten` | ja (`n > 0`) | nein, CHECK `lieferung_menge` **und** `lieferung_hat_menge` (NOT VALID) | leer | `v_lieferung_masse.masse_kg` | Fehlermeldung „Menge fehlt" |
| `l-ziel` | Wohin | `lieferung.ziel` | ja | ja, FK | `verkauf` | `v_lieferung_masse.buch`, `erg_bilanz` | — |
| `l-kunde` | Kunde (freiwillig) | `lieferung.kunde` | nein | nein | leer | `v_lieferung_masse` (nur durchgereicht) | — |
| — (nie gefragt) | — | `lieferung.gebindeart` | — | nein, FK | nie geschrieben | `v_lieferung_masse` (Umrechnung Kisten → kg) | **160 von 187 Zeilen gefüllt — alle aus dem Ausgang-Import, keine aus der Maske** |

## 2.11 `src/pages/Stammdaten.tsx` — Betriebsleiter

| Feld | Beschriftung | Tabelle.Spalte | P/M | NN | Vorgabe | Wer liest | Leer |
|---|---|---|---|---|---|---|---|
| (je Gebindeart) | Tara je Kiste (kg) | `gebinde.tara_kg_pro_kiste` | nein | nein | vorhandener Wert | **7 Sichten** — ohne sie kein Netto irgendwo | Netto NULL in `v_palette`, `v_verdunstung_messung`, `v_wiegung_kennzahl`, `v_auftrag_palette_masse`; Auslöser setzen `gemessen=false` |
| (je Gebindeart) | Tara der Palette (kg) | `gebinde.tara_kg_palette` | nein | nein | vorhandener Wert | dito — **ausser `v_ausgang_kennzahl`, das `coalesce(…, 0)` rechnet** (9.2) | s. 9.2 |
| `csv` | Veröffentlichte CSV-Adresse | `einstellung('journal_csv_url')` | nein | ja | letzter Wert | nur die Maske selbst | — |
| `einfuegen` | Eingefügte Zeilen | → `palette` (Wareneingang), `gebinde` | — | — | — | alles | — |
| `f-sorte`…`f-bem` (8 Felder) | Sorte, Käufer, gilt ab, Art, zu klein unter, Bänder, zu gross ab, Soll je Kiste, Bemerkung | `sortierschema.*` | teils (Prüfung in `fassungAnlegen`) | `sorte`/`gilt_ab`/`art` ja | heute, „kaliber" | `kuerbis_klasse()`, `sortierschema_fuer()`, `v_auftrag_wasch_paletten`, Diagramm | Fehlermeldung |
| `k-name` | Neuer Käufer | `kaeufer.code`, `.name` | ja | ja | — | nur `Stammdaten.tsx` (Anzeige) und `f-kaeufer` | — |
| (je Einstellung) | *Schlüsselname* | `einstellung.wert` (**roher JSON-Text**) | nein | ja | JSON-Text des aktuellen Werts | `heute()`, `stichtag()`, `palox_tara_kg()`, `auftrag_zuordnen()`, `PaloxMaske`, `Zaehler`, `NeueArbeit` | `JSON.parse`-Fehler wird gemeldet; **kein Typ- oder Wertebereichstest** |
| `v-beginn` | Erfassungsbeginn | `einstellung('erfassungsbeginn')` | nein | ja | leer | `stichtag()`, `erg_bilanz` | ist heute `null` |
| (je Charge) | Vorher ausgeliefert (kg) | `charge_vorlauf.ausgang_vor_app_kg` | nein | ja | leer | `erg_bilanz.vorlauf_kg` | leeres Feld **löscht** die Zeile |

## 2.12 `src/pages/CsvUpload.tsx`, `src/betrieb/AusgangImport.tsx`, `src/pages/Anmelden.tsx`

| Feld | Beschriftung | Ziel | Bemerkung |
|---|---|---|---|
| `ov`, `mg`, Häkchen | Overflow ab (g), Mindestgewicht (g), Dubletten zusammenfassen | `sortier_lauf.reinigung` (JSON) über RPC `csv_lauf_speichern` | Vorgabe aus `einstellung('reinigung_standard')` |
| Datei, Charge, Zeitpunkt | — | `sortier_lauf.*`, `sortier_gewicht` | Zeitpunkt aus Dateiname / Dateizeit / von Hand |
| `q-*` (Artikel → Sorte) | — | `ausgang_artikel.ist_kuerbis`, `.sorte` | Zuordnung der Excel-Artikel |
| `name` | Dein Name | `profil.name` (Anmeldung) | — |
| `bl-name`, `bl-email`, `bl-pw` | Name, E-Mail, Passwort | Supabase-Auth | — |

---

# 3. Felder, die erfasst werden und die **niemand** liest

Kriterium: 0 Sichten (`pg_depend` spaltengenau) **und** 0 Funktionen
(`pg_proc.prosrc`) **und** 0 Stellen in `src/` ausser der schreibenden.

| Spalte | Maske | Zeit an der Waage | Belegstelle |
|---|---|---|---|
| `auftrag_angabe(schluessel='gleiche_sorte')` | Abschluss, ganzer Bildschirm mit zwei Wahlkarten | 1 Bildschirm + 1 Tipp, wenn „nicht eine Charge" | `Abschluss.tsx:100` schreibt; `pg_get_viewdef … like '%gleiche_sorte%'` → 0 Treffer, `pg_proc … like` → 0, `grep -rl gleiche_sorte src/` → nur `Abschluss.tsx` |
| `schimmel_messung.mit_palette` | Häkchen „auf Palette gewogen" (Fax) | 1 Ziel je Kiste, 298× | nur `schimmel_netto_setzen`; `count(*) filter (where mit_palette)` = **0 von 585** |
| `schimmel_messung.brutto_kg`, `.kisten`, `.gebindeart` | Faules wiegen: 3 der 4 Felder | 298× | 0 Sichten. Nur der Auslöser liest sie, **einmalig beim Einfügen**. Danach ist das Rohgewicht unerreichbar — deshalb 9.3 |
| `schimmel_messung.bemerkung` | Knopf „Nichts Faules" schreibt den Text | — | 0 Sichten, 0 Funktionen; nur `FauleMaske.tsx:116` zeigt ihn in derselben Maske wieder an |
| `ausschuss_messung.bemerkung` | Knopf „Nichts zu klein oder zu gross" | — | dito |
| `auftrag_gebinde.datum_fehlt` | Maske schreibt hart `false` | — | nur `v_datenqualitaet`; **0 von 208** je `true` |
| `auftrag_gebinde.sortierdatum` | Maske schreibt hart `null` | — | nur `v_datenqualitaet`; 1 von 208 gefüllt (Demogenerator) |
| `schimmel_messung.teilgewicht` | keine | — | **0 Leser überall.** `not null default false`, 0 von 585 `true` |
| `verdunstung_wiegung.auswahl` | keine (seit 0061) | — | **0 Leser überall**, trägt noch einen CHECK auf drei Werte |
| `verdunstung_wiegung.bemerkung` | nur Korrektur | — | 0 Sichten; 24 von 41 gefüllt (Demogenerator) |
| `ausgang_wiegung.bemerkung` | keine | — | 0 Sichten, 0 von 128 gefüllt |

Halbtot, weil nur eine Abdeckungszahl daran hängt:

| Spalte | einziger Weg in eine Anzeige | gemessen |
|---|---|---|
| `auftrag_palette.sortierdatum` | `v_datenqualitaet.wasch_kisten_mit_sortierdatum` → ein Balken auf `Messungen.tsx:223`. Die **fachliche** Ableitung `v_auftrag_wasch_paletten.zwischenlager_tage` und `n_mit_sortierdatum` hat **null** nachgelagerte Leser (`pg_depend`-Abfrage auf `v_auftrag_masse.zwischenlager_tage` → leer; `grep -rn zwischenlager src/` → leer) | 324 Pflichteingaben je Saison für einen Balken |
| `verdunstung_wiegung.kuerbisse_pro_kiste` | `v_wiegung_kennzahl.kg_pro_kuerbis` → `erg_wiegung` → **eine Tabellenspalte** auf `Messungen.tsx:193` | 17 von 41 gefüllt |

---

# 4. Spalten, die die Auswertung liest und die **keine Maske** füllt

| Spalte | Wer liest | Füllstand in `demo` | Folge |
|---|---|---|---|
| `verdunstung_wiegung.faul_kg` | `v_schimmel_punkte`, dritter UNION-Zweig (`quelle='lager'`), komplett | **0 von 41** | `select quelle, count(*) from v_schimmel_punkte group by 1` → nur `verarbeitung` (142). Der Zweig ist **strukturell leer**; die Lagerkontrolle kann seit 0061 keinen Schimmelpunkt mehr liefern |
| `auftrag_palette.palette_id` | `v_auftrag_palette_masse` (Zweig `palette`), `v_charge_kohorte`, `v_plausibilitaet` | **0 von 854** | der Zweig `masse_quelle='palette'` hat 0 Zeilen; die exakte Zuordnung Zählung ↔ Wareneingang läuft über die Notlösung „Datum + Gewicht raten" (`zettel`-CTE) |
| `verdunstung_wiegung.palette_id` | `v_verdunstung_messung` | **0 von 41** | dito |
| `auftrag.durchsatz_kg` | `mv_auftrag_masse` als Rückfall für `eingang_netto_kg`, `masse_quelle='durchsatz'` | **0 von 309** | `select masse_quelle, count(*) from mv_auftrag_masse group by 1` → nur `fehlt` (257) und `paletten` (51). Zweig tot |
| `auftrag.geplante_paletten` | `v_datenqualitaet` | **0 von 309** | seit 0012 tot |
| `auftrag.abbruch_grund` | `v_datenqualitaet` | 1 von 309, aus dem Generator | `Abschluss.tsx:115` übergibt hart `p_grund: null` |
| `auftrag.bemerkung` | `v_datenqualitaet` | 309 von 309, alle aus dem Generator | keine Maske schreibt sie |
| `auftrag.kaeufer` | `v_datenqualitaet`, `v_fax_beobachtung` | 210 von 309, alle aus dem Generator | `NeueArbeit.tsx:171` schreibt hart `null` |
| `schimmel_messung.palox_geleert` | `v_palox_stand` (erster CASE-Zweig) | 13 von 585, alle aus dem Generator | die Maske schreibt immer `false` — der Zweig ist im Betrieb unerreichbar |
| `verdunstung_wiegung.sichtbar_schimmel` | `v_verdunstung_messung.verwendbar`, `v_wiegung_kennzahl`, `Ursachen.tsx:213` (`filter(w => !w.sichtbar_schimmel …)`) | **0 von 41 `true`** | seit 0061 fragt keine Maske mehr danach; nur die Korrekturmaske kann es setzen. Der Filter schliesst nie etwas aus |
| `auftrag_angabe(schluessel='ausschuss_leer'/'ausschuss_von_auftrag')` | niemand | 17 + 17 Zeilen, nur aus `demo_daten_laden` | Altschlüssel |
| `lieferung.gebindeart` | `v_lieferung_masse` | 160 von 187, alle aus dem Import | die Handmaske fragt nicht danach — eine Handlieferung in Kisten wird über das Chargenmittel umgerechnet statt über die Gebindeart |

---

# 5. Wo Maske und Tabelle sich uneinig sind

**Maske verlangt, Tabelle nicht** (die Reihenfolge zählt: hier hält nur die
Oberfläche die Daten sauber; jeder andere Weg in die Datenbank — Korrekturmaske,
Import, SQL-Editor, künftige Maske — reisst das Loch auf):

| Spalte | Maske verlangt | Tabelle | Was ohne die Maske geschieht (gemessen, Abschnitt 6) |
|---|---|---|---|
| `auftrag_palette.eingangsdatum` | ja, Knopf gesperrt | `null ok` | Masse fällt vom Tagesmittel auf das Chargenmittel |
| `auftrag_palette.kisten` (Waschen) | ja, `> 0` und ganzzahlig | `null ok` | die Zeile wandert in den falschen Sichtenzweig (`v_auftrag_palette_masse` filtert `where ap.kisten is null`) |
| `verdunstung_wiegung.kisten` | ja | `null ok` | Netto NULL → aus `v_koeff_roh_verdunstung` heraus, **ohne Meldung** |
| `verdunstung_wiegung.gebindeart` | ja (Klappliste ohne Leereintrag) | `null ok` | dito |
| `ausgang_wiegung.gebindeart` | ja | `null ok` | Zeile **verschwindet lautlos** aus `v_ausgang_kennzahl` |
| `ausschuss_messung.brutto_kg`, `.kisten`, `.gebindeart` | ja | `null ok` | `gemessen=false`, aber `v_plausibilitaet` meldet es (Zweig „Ausschuss ohne Tara") — hier ist das Netz dicht |
| `auftrag.paletten_gesamt` (Fax) | ja im Abschluss | `null ok` | `v_plausibilitaet`-Zweig „Ohne Nenner" meldet es |
| `auftrag.kaliber_idx` / `kaliber_von_g` (Waschen) | ja | `null ok` | `v_plausibilitaet`-Zweig „Kaliber fehlt" meldet es |
| `auftrag_angabe(eine_charge)` | ja, Abschluss gesperrt | keine Regel | Abschluss über SQL ohne Antwort möglich |

**Tabelle verlangt, Maske nicht** — keine gefunden. Jede `not null`-Spalte
ohne Vorgabe wird von der zuständigen Maske gefüllt.

**Bedingungen, die nur für Neues gelten** (`NOT VALID`) — sie **werden** bei
neuen Zeilen geprüft, das ist ein verbreitetes Missverständnis:

```
begin; insert into auftrag_palette(auftrag_id, erfasser) select id, eroeffnet_von from auftrag limit 1; rollback;
→ ERROR: violates check constraint "auftrag_palette_datum_pflicht"
begin; insert into lieferung(datum, sorte, ziel, erfasser) …; rollback;
→ ERROR: violates check constraint "lieferung_hat_menge"
```

Und der Bestand erfüllt alle vier: `auftrag_kaliber_nur_waschen` 0,
`auftrag_fax_nur_waschen` 0, `auftrag_palette_datum_pflicht` 0,
`lieferung_hat_menge` 0 Verletzungen. Sie gehören validiert.

---

# 6. Was geschieht, wenn ein Feld leer bleibt — die Experimente

Alle in `begin; … rollback;` auf `karte_erfassung`. Grundlinie:
`select count(*) from v_plausibilitaet` = **22**.

### 6.1 Fertige Palette ohne Kistenart

```sql
insert into ausgang_wiegung(auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, erfasser)
select w.auftrag_id, w.charge_nr, 500, 30, null, w.erfasser from ausgang_wiegung w limit 1;
```
| | vorher | nachher |
|---|---|---|
| `ausgang_wiegung` | 128 | **129** |
| `v_ausgang_kennzahl` | 128 | **128** |
| `v_plausibilitaet` | 22 | **22** |

Ursache: `v_ausgang_kennzahl` filtert `where w.gemessen and … and n.netto_kg > 0`;
ohne Gebindeart ist `netto_kg` NULL, `NULL > 0` ist NULL, die Zeile fällt weg.
`ausgang_wiegung.gemessen` bleibt `true` (kein Auslöser auf dieser Tabelle).
**Eine gewogene Palette verschwindet spurlos.**

### 6.2 Verdunstungswägung ohne Kistenzahl

| | Grundlinie | ohne `kisten` |
|---|---|---|
| `verdunstung_wiegung` | 41 | **42** |
| `v_verdunstung_messung` | 41 | 42 |
| `v_wiegung_kennzahl` | 41 | 42 |
| `v_koeff_roh_verdunstung` | 41 | **41** |
| `v_plausibilitaet` | 22 | **22** |

Die Zeile bleibt sichtbar, trägt aber nicht bei — und niemand sagt es.
Die Ursache ist eine Dreiwertigkeitslücke, siehe 9.1.

### 6.3 Faules mit Brutto, ohne Kistenzahl

```sql
insert into schimmel_messung(auftrag_id, kg, brutto_kg, kisten, gebindeart, erfasser) …
→ id 586: kg=0, gemessen=f, brutto_kg=300.00, kisten=NULL
```
`v_plausibilitaet` bleibt bei 22. Der Auslöser setzt `gemessen=false`, **lässt
`kg` aber auf dem mitgeschickten Wert stehen** — für einen Betriebsleiter, der
in der Korrekturmaske die Kistenzahl leert, steht dort danach eine Zahl, die
nirgends mehr zählt.

### 6.4 Wie viel hängt am Zetteldatum?

```sql
select masse_quelle, count(*), round(sum(netto_kg)) from v_auftrag_palette_masse group by 1;
```
| Quelle | Paletten | kg |
|---|---|---|
| `datum-mittel` (nur über `eingangsdatum`) | 298 | **109 975** |
| `zettel` (über `brutto_zettel_kg`) | 214 | 84 686 |
| `gewogen` | 17 | 6 609 |
| `charge-mittel` (Rückfall) | 1 | 398 |

Wenn das Datum falsch ist, fällt die Palette auf `charge-mittel`. Der Preis
dafür ist **gemessen klein**:

```sql
with d as (select charge_nr, eingangsdatum, avg(netto_kg) tag from v_palette group by 1,2),
     c as (select charge_nr, avg(netto_kg) charge from v_palette group by 1)
select count(*), round(avg(abs(d.tag-c.charge)),1), round(max(abs(d.tag-c.charge)),1) from d join c using (charge_nr);
→ 86 Paare · 4.1 kg mittlere Abweichung · 32.5 kg grösste · 1.1 %
```

**Gegenrede, und sie trägt:** Das Datum ist nicht nur für die Masse da.
`auftrag_palette.eingangsdatum` speist auch `v_charge_kohorte` und
`v_verarbeitung_alter` — also die **Lagertage**, und die tragen die
Verdunstung. Der Massenanteil des Feldes ist 1,1 %; sein Alterungsanteil ist
das Ganze. Für die Zeitkarte bedeutet das: das Datumsfeld bleibt, das
Zettelgewicht beim reinen Sortieren wäre die entbehrlichere Frage.

---

# 7. Was jede Maske einen Arbeiter kostet

**Gemessen:** Feldzahl je Maskenvariante (aus dem Quelltext), Ziffernzahl je
Feld (aus den Demodaten, `avg(length(…))`), Netzrunden je Bedienschritt (aus
den `supabase`-Aufrufen im jeweiligen Pfad gezählt).
**Angenommen** (offen und austauschbar, `scratchpad/zeit.mjs`, KLM-nah):
0,5 s je getippte Ziffer · 1,0 s je Tippziel ≥ 48 px · 4,0 s natives
Datumsfeld · 2,5 s Klappliste · 1,2 s Vorbereitung je neuer Frage ·
Netz 80 ms (gut) / 600 ms (schlecht) Umlaufzeit; parallele Aufrufe = eine Runde.

### Gemessene Ziffernlängen

```sql
select round(avg(length(trim(trailing '.' from trim(trailing '0' from brutto_kg::text)))),2) from ausgang_wiegung;
```
| Feld | Ø Zeichen | n |
|---|---|---|
| Palox-Stand | 2,93 | 281 |
| Faules Brutto | 3,22 | 298 |
| Ausschuss Brutto | 3,90 | 31 |
| Fertige Palette Brutto | 4,09 | 128 |
| Zettelgewicht | 4,79 | 231 |
| Eingangsgewicht (Wägung) | 4,90 | 41 |
| Gewicht jetzt | 3,98 | 41 |
| Kisten (Waschen) | 1,91 | 324 |
| Kisten (Fax) | 1,00 | 298 |
| Chargennummer | 4,00 | 42 |

### Netzrunden je Bedienschritt

`arbeitLaden()` (`src/arbeit/daten.ts:47`) feuert **9 parallele** Abfragen —
`stammdaten()` ist modulweit gepuffert (`lib/db.ts:5`), `einstellung()` ist es
**nicht** — und danach **1 sequenzielle** für `sortierschema` (309 von 309
Arbeiten haben eine). Also **10 Leseanfragen je Neuladen**, dazu die
Schreibanfrage.

| Maske | Felder | HTTP-Anfragen je Speichern | s (gut) | s (schlecht) | n/Saison | Std (gut) | Std (schlecht) |
|---|---|---|---|---|---|---|---|
| **Zähler · Kiste je Kaliber** | 1 Knopf | **11** | **1,2** | **2,8** | **16 254** | **5,60** | **12,64** |
| Faules wiegen (Fax) | 5 | 11 | 14,1 | 15,7 | 298 | 1,17 | 1,30 |
| Fertige Palette wiegen | 6 | 12 | 19,8 | 21,3 | 128 | 0,70 | 0,76 |
| Palox ablesen | 2 | 13 | 5,5 | 8,1 | 281 | 0,43 | 0,64 |
| Eingangspalette (W+S) | 3 | 11 | 6,6 | 8,1 | 241 | 0,44 | 0,54 |
| Kaliberpalette (Waschen) | 3 | 11 | 2,1 | 3,7 | 324 | 0,19 | 0,33 |
| Eingangspalette (Sortieren) | 2 | 11 | 2,0 | 3,5 | 289 | 0,16 | 0,28 |
| Palette wiegen (Verdunstung) | 7 | 12 | 25,9 | 28,0 | 41 | 0,29 | 0,32 |
| Zu klein / zu gross | 5 | 11 | 14,6 | 16,1 | 34 | 0,14 | 0,15 |
| Palettenzahl (Fax) | 1 | 11 | 1,2 | 2,8 | 160 | 0,06 | 0,12 |
| Lagerkontrolle | 7 | 1 | 24,7 | 25,2 | 24 | 0,16 | 0,17 |
| **Summe Masken** | | | | | | **9,3** | **17,2** |

| Assistent | Bildschirme | Runden | s (gut) | s (schlecht) | n | Std (gut) | Std (schlecht) |
|---|---|---|---|---|---|---|---|
| Neue Arbeit · Fax | 4 | 9 | 13,9 | 18,6 | 161 | 0,62 | 0,83 |
| Neue Arbeit · Waschen | 5 | 10 | 18,9 | 24,1 | 96 | 0,50 | 0,64 |
| Neue Arbeit · Sortieren | 4 | 9 | 13,9 | 18,6 | 31 | 0,12 | 0,16 |
| Neue Arbeit · W+S | 4 | 10 | 15,5 | 20,7 | 21 | 0,09 | 0,12 |
| Abschluss · Fax | 4 | 9 | 13,2 | 17,9 | 161 | 0,59 | 0,80 |
| Abschluss · Waschen | 5 | 9 | 16,4 | 21,1 | 96 | 0,44 | 0,56 |
| Abschluss · Sortieren | 3 | 7 | 11,8 | 15,5 | 31 | 0,10 | 0,13 |
| Abschluss · W+S | 6 | 10 | 18,7 | 23,9 | 21 | 0,11 | 0,14 |
| **Summe Assistenten** | | | | | | **2,58** | **3,39** |

**Saison gesamt: 11,9 Stunden bei gutem Netz, 20,6 bei schlechtem.**
Davon **47 % bzw. 61 % allein auf dem Kaliber-Plusknopf.**

### Netzlast der Saison

| Vorgang | n | Anfragen je Mal | Summe |
|---|---|---|---|
| **Kaliberkisten „+"** | 16 254 | 11 | **178 794** |
| Kaliberpalette Waschen | 324 | 11 | 3 564 |
| Palox-Ablesung | 281 | 13 | 3 653 |
| Faules Fax | 298 | 11 | 3 278 |
| Eingangspalette Sortieren | 289 | 11 | 3 179 |
| Eingangspalette W+S | 241 | 11 | 2 651 |
| Neue Arbeit / Abschluss | 309 / 309 | 9 / 9 | 5 562 |
| Fax Palettenzahl | 160 | 11 | 1 760 |
| Fertige Palette | 128 | 12 | 1 536 |
| Zu klein / gross | 34 | 11 | 374 |
| Wägungen + Kontrollen | 41 | 12 / 1 | 228 |
| **Summe** | | | **204 579** — davon **87,4 %** der eine Knopf |

Die Datenbankzeit ist dabei ohne Bedeutung: alle zehn Abfragen von
`arbeitLaden` zusammen brauchen **1,0 ms** (`explain (analyze, timing off)` je
Abfrage, Summe 1,005 ms). Die Kosten sind ausschliesslich Umlaufzeiten.

### Was der Arbeiter herunterlädt

`gzip -c9` auf `dist/assets/`: `fremd` 78,6 kB + `grundlage` 94,1 kB +
`index` 11,0 kB + Laufzeit 0,5 kB + CSS 6,0 kB = **190,2 kB**.
Die Auswertung (51,6 kB) bleibt draussen — der Zuschnitt aus `vite.config.ts`
hält. Aber `src/lib/i18n.ts` (70 681 Bytes roh, 20 % von `grundlage` roh) liegt
vollständig in `grundlage`: **jeder Arbeiter lädt alle sechs Sprachen**.

### Kein Netz, kein Zählen

`grep -rn "serviceWorker\|navigator.onLine\|indexedDB" src/` → **0 Treffer**.
`localStorage` nur für Zettel-Datum, Kistenzahl, Rolle und Sprache
(9 Vorkommen in 5 Dateien). Es gibt keine Warteschlange, keinen optimistischen
Zähler und keine Wiederholung: `paletteZaehlen` bricht bei `laeuft` **stumm**
ab (`Zaehler.tsx:71`), und die Plusknöpfe sind während der Runde gesperrt.
Bei 2,8 s je Tipp und 524 Tippern je Sortierschicht ist ein Doppeltipp, der
verlorengeht, kein Randfall.

---

# 8. Was `pruefstand/luecken.sh` prüft — und was nicht

Der Scanner lief auf meiner Kopie:
```
bash pruefstand/luecken.sh 'postgresql://postgres@/karte_erfassung?host=/tmp/pgsock&port=55432'
→ OK  Keine Lücke: jede Erfassungsspalte hat ihre Maske, jede
      ausgewertete Tabelle wird beschrieben.
```
**Er meldet nichts, während diese Karte 11 tote Spalten, 12 nur von der
Auswertung gelesene Spalten und einen Bildschirm ohne Wirkung findet.**

Was er tut, und was er nicht tut:

| | Scanner | Diese Karte |
|---|---|---|
| Tabellen | 11 fest verdrahtete | zusätzlich `lieferung`, `gebinde`, `einstellung`, `charge`, `palette`, `profil`, `auftrag_teilnehmer` |
| Vorwärts (Spalte → Maske) | Namenstest: `grep -rE "(^\|[^a-z_])$c[[:space:]]*[:,}]"` über **ganz `src/`**, ohne Bezug zur Tabelle | Parser über die Schreib-Nutzlast je `.from('t').insert/update/upsert({…})` |
| geprüfte Spalten | **52** (nach Abzug der Ausnahmen), alle bestanden — `bash scratchpad/scanner_blind2.sh` | 145 Spalten in 14 Tabellen |
| Rückwärts | nur **auf Tabellenebene**: „liest irgendeine Sicht aus dieser Tabelle?" | **auf Spaltenebene** über `pg_depend.refobjsubid` + `pg_proc` + `src/` |
| Ausnahmen | **40 Namen auf 37 Zeilen**, jede mit Begründung, aber keine wird je nachgeprüft | jede Ausnahme gemessen: `teilgewicht` und `auswahl` haben **0 Leser überall** — die Begründung „von keiner heutigen Maske genutzt" ist wahr, aber unvollständig; sie gehören weg, nicht in eine Liste |
| Pflicht/`not null` | nie verglichen | Abschnitt 5 |
| Vorgabewerte | nie betrachtet | Abschnitt 2 |
| „was passiert bei leer" | nie ausprobiert | Abschnitt 6, mit Rollback-Experimenten |
| Zeitkosten | nie | Abschnitt 7 |
| Bildschirme ohne Wirkung (`gleiche_sorte`) | unsichtbar, weil er nur Spalten prüft, nicht **Werte** in einer Schlüssel/Wert-Tabelle | Abschnitt 3 |
| Erreichbarkeit von Sichtenzweigen | nie | Abschnitt 4 (`faul_kg`, `durchsatz_kg`, `palette_id`, `palox_geleert`) |

**Der wichtigste blinde Fleck:** `auftrag_angabe` ist eine Schlüssel/Wert-Tabelle.
Der Scanner prüft die Spalten `schluessel` und `wert` — und ist zufrieden.
Dass unter `schluessel` vier verschiedene Fragen stecken, von denen zwei
(`ausschuss_leer`, `ausschuss_von_auftrag`) niemand mehr schreibt und eine
(`gleiche_sorte`) niemand liest, kann er nicht sehen. Wer Schlüssel/Wert-
Tabellen hat, braucht einen Scanner, der die **Werte** aufzählt.

---

# 9. Weitere Befunde aus der Kartierung — je mit Gegenrede

## 9.1 `verwendbar` ist NULL, nicht false — eine Prüfmeldung, die nie erscheint

`v_verdunstung_messung.verwendbar` ist eine `AND`-Kette über
`netto_damals_kg > 0 AND netto_jetzt_kg > 0 AND …`. Fehlt die Tara oder die
Kistenzahl, sind beide Nettos NULL, und **`verwendbar` ist NULL**:

```sql
select 'NOT verwendbar ist ' || coalesce((not verwendbar)::text,'NULL') from v_verdunstung_messung order by id desc limit 1;
→ NOT verwendbar ist NULL
```

`v_plausibilitaet` filtert `WHERE NOT w.verwendbar AND NOT w.sichtbar_schimmel
AND EXISTS(… v.gemessen)`. `NOT NULL` ist NULL, also nie wahr. Der
CASE-Zweig, der genau diesen Fall benennt —
`WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'für die
Gebindeart fehlt die Tara'` — ist **beweisbar unerreichbar**: damit
`verwendbar` FALSE statt NULL wird, müsste `gemessen` false oder
`sichtbar_schimmel` true sein, und beides schliesst die WHERE-Bedingung aus.

**Gegenprobe (die Sonde funktioniert, nur nicht hier):**
| Fall | `v_plausibilitaet` |
|---|---|
| Grundlinie | 22 |
| Palette wiegt jetzt 50 % **mehr** | **23** — „sie wiegt jetzt 246 kg mehr als beim Eingang" |
| dieselbe Palette **ohne Gebindeart** | **22** — Schweigen |

**Gegenrede:** Es gibt einen zweiten Zweig, „Wägung" in
`v_plausibilitaet_0064_zusatz`, der auf `v_palette` losgeht — aber der prüft
den Wareneingang, nicht die Verdunstungswägungen. Und
`v_datenqualitaet.lagerkontrollen` zählt nur, es prüft nicht. Die Gegenrede
trägt nicht. **Werkstatt A und B.**

## 9.2 Ein einziges `coalesce(tara_kg_palette, 0)` in 63 Sichten

```sql
select viewname, … from pg_views where … like '%tara_kg_palette%';
```
| Sicht | Formel |
|---|---|
| `v_palette` | `− g.tara_kg_palette` |
| `v_verdunstung_messung`, `v_wiegung_kennzahl`, `v_auftrag_palette_masse` | `− g.tara_kg_palette` |
| `v_plausibilitaet`, `…_0064_zusatz` | `− g.tara_kg_palette` (und melden, wenn NULL) |
| **`v_ausgang_kennzahl`** | **`− COALESCE(g.tara_kg_palette, 0)`** |

Überall sonst bedeutet eine fehlende Palettentara „unbekannt" — das war der
Grundsatz von 0064 und steht wörtlich in `src/lib/masse.ts:1–15`. In
`v_ausgang_kennzahl` bedeutet sie **0**. Heute tragen alle vier Gebindearten
25,000 kg, also 0 betroffene Zeilen. Käme eine Art ohne Palettentara dazu,
wäre jede fertige Palette **25 kg zu schwer**: bei 13,00 kg brutto je Kiste und
32 Kisten sind das 6,0 % Überfüllung aus dem Nichts, und die Überfüllung ist
genau die Grösse, die diese Sicht ausrechnet.

**Gegenrede:** Die fertige Palette wird vielleicht ohne Palette gewogen, wie
der Palox. Dann wäre 0 richtig. Aber dann müsste die Maske es fragen — sie tut
es nicht, sie rechnet `nettoKg(b, n, tara)` mit `mitPalette = true` und
**sperrt** das Speichern, wenn die Palettentara fehlt. Maske und Sicht sind
sich also uneinig, welche der beiden Regeln gilt. **Werkstatt A.**

## 9.3 Tara-Änderung: 30 von 31 Ausschusszeilen werden gemeldet, 0 von 298 Fax-Zeilen

```sql
begin; update gebinde set tara_kg_pro_kiste = tara_kg_pro_kiste + 0.5;
       select art, count(*) from v_plausibilitaet group by 1; rollback;
```
| Art | vorher | nachher |
|---|---|---|
| gesamt | 22 | **52** |
| **Ausschuss-Tara** | 0 | **30** von 31 möglichen |
| (kein Zweig für Faules) | — | **0** von 298 möglichen |

Für `ausschuss_messung` gibt es zwei Prüfzweige („Ausschuss-Tara",
„Ausschuss ohne Tara"), die genau diesen Fall abfangen. Für
`schimmel_messung` — **zehnmal so viele Zeilen, 2 611 kg Faules** — gibt es
keinen. Und weil das Rohgewicht (`brutto_kg`, `kisten`, `gebindeart`) von
**keiner Sicht** gelesen wird (Abschnitt 3), gibt es auch keinen Weg, es je
wieder nachzurechnen: das Netto ist beim Einfügen eingefroren.

**Gegenrede:** Der Palox-Teil von `schimmel_messung` wird tatsächlich
nachgerechnet (`v_schimmel_menge` nimmt `p.differenz`) — die Tabelle ist also
nicht durchweg eingefroren. Aber genau das macht es schlimmer: **dieselbe
Spalte `kg` hat zwei Bedeutungen**, je nachdem ob `palox_stand_kg` gesetzt ist.
Für 281 Zeilen ist sie Zierrat, für 298 Zeilen die Wahrheit. **Werkstatt A und B.**

## 9.4 Die Zahl, die der Arbeiter bestätigt, ist nicht die, mit der gerechnet wird

```sql
select count(*) filter (where s.kg::numeric is distinct from p.differenz),
       round(sum(abs(s.kg::numeric - p.differenz)),1), round(max(abs(s.kg::numeric - p.differenz)),1)
from schimmel_messung s join v_palox_stand p on p.id=s.id where s.palox_stand_kg is not null;
→ 8 von 281 Zeilen · 1 577 kg Summe · 626 kg grösste Einzelabweichung
```
Beispiel Zeile 580: gespeichert **4 500 kg**, gerechnet **3 874 kg**.
Die Maske rechnet `n − vorher` mit einem `vorher`, das sie beim **Öffnen** über
`rpc('palox_letzter_stand')` geholt hat; `v_palox_stand` rechnet mit
`lag(palox_stand_kg) OVER (PARTITION BY palox_station(station) ORDER BY ts, id)`.
Zwischen Öffnen und Speichern kann sich das Fenster verschoben haben.

**Gegenrede, und sie trägt ein Stück weit:** In der Demosaison sind die
Ablesungen vom Generator zeitlich verschachtelt eingefügt worden; im echten
Betrieb kommen sie der Reihe nach, und dann stimmen beide überein. Es bleibt
aber, dass die Maske eine Vorschau zeigt, die die Datenbank später überschreibt,
ohne dass irgendwo ein Abgleich stattfindet — und dass die
**Plausibilitätswarnung der Maske** (`verdaechtig = jePalette > 120`,
`PaloxMaske.tsx:47`) auf dieser möglicherweise falschen Zahl beruht. Die
Schwelle 120 kg je Palette steht als feste Zahl im Frontend, nicht in
`einstellung`, nicht in der Datenbank. **Werkstatt A und D.**

## 9.5 Ein Datenqualitäts-Balken, der nie grün werden kann

`pages/Messungen.tsx:212`: „Datum vom Zettel bei gezählten Paletten (AB-11)" —
`erg_datenqualitaet`: **527 von 851 = 62 %**, rot (die Schwelle ist 80 %), mit
dem Hinweis „ohne Datum kein Alter der Ware".

```sql
select case when a.station='waschen' and not a.ist_fax then 'Waschen (Kaliberpalette)' else 'Eingangspalette' end,
       count(*), count(ap.eingangsdatum), count(ap.sortierdatum)
from auftrag_palette ap join auftrag a on a.id=ap.auftrag_id where a.abgebrochen_ts is null group by 1;
```
| Art | gezählt | mit `eingangsdatum` | mit `sortierdatum` |
|---|---|---|---|
| Waschen (Kaliberpalette) | 324 | **0** | 324 |
| Eingangspalette | 527 | **527** | 0 |

Der Zähler von `paletten_mit_datum` fragt nur nach `eingangsdatum`
(`v_datenqualitaet`, Zeile 62). Die 324 Waschen-Paletten **können** keines
haben — die Maske schreibt es nicht und die Ware hat es nicht. Die erfüllbare
Quote ist 527/527 = **100 %**; angezeigt werden dauerhaft 62 % in Rot.
**38 Prozentpunkte falscher Alarm**, auf der einen Seite, die dem
Betriebsleiter sagen soll, wo er nachhaken muss.

**Gegenrede:** Der Balken darunter („Waschen: Sortierdatum je gezählter
Palette", 8 918/8 918 = 100 %) deckt die Waschen-Seite ab, es fehlt also keine
Information. Aber er zählt **Kisten**, der obere zählt **Paletten**, und der
obere zieht die Waschen-Paletten trotzdem in seinen Nenner. Die Gegenrede
erklärt, wie es entstanden ist; sie macht den roten Balken nicht richtig.
**Werkstatt D.**

## 9.6 Zeitzone: das Datum aus der Uhr kann einen Tag zu früh sein

Die Datenbank läuft auf `Etc/UTC` (`show timezone`). Alle Datumsfelder der
Masken sind `<input type="date">` und schreiben eine reine Zeichenkette — die
sind sauber. Betroffen sind die Stellen, an denen ein `timestamptz` zu einem
`date` wird: `v_verdunstung_messung` (`w.wiege_ts::date − w.eingangsdatum`),
`v_auftrag_wasch_paletten` (`a.start_ts::date − ap.sortierdatum`),
`v_auftrag_masse.lagertage`, `v_verarbeitung_alter`.

| Ortszeit (Europe/Zurich) | Datum in UTC | Verschiebung |
|---|---|---|
| 15.01. 22:00 | 15.01. | 0 |
| 15.01. 23:30 | 15.01. | 0 |
| **16.01. 00:30** | **15.01.** | **−1 Tag** |
| 15.07. 23:30 | 15.07. | 0 |
| **16.07. 00:30** | **15.07.** | **−1 Tag** |

Das Fenster ist 1 h im Winter, **2 h im Sommer** (in der Erntesaison also 2 h).
Grössenordnung: Verdunstungsrate **0,0005 /Tag** (`erg_koeff_verdunstung`,
Mittel über die Sorten), Saisoneingang **323 268 kg** → ein systematisch um
einen Tag zu kurzer Lagerzeitraum entspricht **162 kg** Verdunstung, die nicht
verbucht wird; je Palette (383 kg netto) sind es 0,19 kg.

**Gegenrede:** Nachtschichten in einem Kürbisbetrieb sind selten; das Fenster
ist zwei Stunden von 24. Und die Verschiebung geht immer in dieselbe Richtung,
also ist sie im Zweifel als Vorzeichen erkennbar. Trotzdem: `heute()` fällt auf
`current_date` zurück, das ebenfalls die Sitzungszeitzone nimmt, und
`stichtag()` hängt daran. **Werkstatt B (B5).**

## 9.7 Die Klappliste „Art der Kiste", 498-mal gefragt, 1 Antwort

```sql
select 'schimmel', gebindeart, count(*) from schimmel_messung where gebindeart is not null group by 1,2
union all select 'ausgang', gebindeart, count(*) from ausgang_wiegung group by 1,2
union all select 'verdunstung', … union all select 'ausschuss', …;
```
| Maske | Gebindeart | n |
|---|---|---|
| Faules wiegen | G2 | 298 |
| Fertige Palette | G2 | 128 |
| Palette wiegen | G2 | 41 |
| Zu klein / gross | G2 | 31 |
| **gesamt** | **nur G2** | **498** |

Vier Masken fragen die Kistenart **je Messung**. In 498 von 498 Messungen ist
die Antwort die Vorbelegung (`s.gebinde[0]?.art`, alphabetisch erster Eintrag).
Kosten: 2,5 s × 498 = **21 Minuten** je Saison für null Information.

**Gegenrede, und sie ist ernst zu nehmen:** Die Stammdaten führen drei
IFCO-Typen mit abweichender Tara (1,360 / 1,680 / 2,000 statt 1,500 kg). Es
kann sein, dass der Demogenerator einfach immer G2 nimmt und der echte Betrieb
mischt — dann ist die Frage richtig. **Das ist eine Frage an den Betrieb, keine
Behauptung** (gehört nach `docs/FRAGEN.md`). Sie liesse sich auch anders
lösen: die Kistenart einmal je Arbeit fragen statt je Messung, wie es das
Kistensystem schon vormacht. **Werkstatt D.**

## 9.8 Die Korrekturmaske ist ein Tabelleneditor mit 43 Spalten

`src/arbeit/Korrektur.tsx` macht 43 Spalten in 8 Tabellen direkt editierbar,
mit `typ: 'text'` für `gebindeart` (freies Textfeld, nur durch den Fremdschlüssel
gehalten) und `kistensystem` (freies Textfeld, nur durch einen CHECK gehalten).
`zuWert('', f)` macht aus einem geleerten Feld **`null`** — auch bei Spalten,
die die Maske sonst verlangt. Damit ist die Korrekturmaske der Weg, auf dem
alle in Abschnitt 5 gelisteten Uneinigkeiten in der Praxis entstehen können.

**Gegenrede:** Sie ist ausdrücklich für den Betriebsleiter gebaut, RLS-geschützt
(`ist_admin()`), und ein Rohdateneditor ist genau das, was man will, wenn eine
Messung berichtigt werden muss. Der Fehler liegt nicht in ihr, sondern darin,
dass die Datenbank die Regeln nicht kennt, die die Erfassungsmasken befolgen.
**Werkstatt B.**

---

# 10. Was diese Karte den vier Werkstätten übergibt

| Werkstatt | Übergabe |
|---|---|
| **A — Rechenwerk** | 9.1 (Dreiwertigkeit in `verwendbar`), 9.2 (das eine `coalesce`), 9.3 (eingefrorenes Fax-Netto), 9.4 (Maskenvorschau ≠ Rechnung, 626 kg), 6.4 (1,1 % Massenanteil des Zetteldatums), 4 (vier tote Sichtenzweige, die A nicht mitprüfen muss) |
| **B — Fundament** | 5 (neun Maske/Tabelle-Uneinigkeiten als `not null`- und CHECK-Kandidaten), die vier NOT-VALID-Bedingungen mit 0 Verletzungen, 9.6 (Zeitzone, 162 kg/Tag), 3 (11 Spalten löschbar), 9.8 |
| **C — Bauwerk** | 3 (11 tote Spalten, 2 davon mit CHECK), 4 (12 nur gelesene Spalten und die zugehörigen Sichtenzweige), 8 (`luecken.sh` gehört ersetzt), 0 unbenutzte i18n-Schlüssel (hier gibt es **nichts** zu holen), i18n 70,7 kB im Arbeiterbündel |
| **D — Nutzen** | 7 (11,9–20,6 Std./Saison, davon 47–61 % ein Knopf; 204 579 HTTP-Anfragen, 87 % ein Knopf), 9.5 (dauerhaft roter Balken), 9.7 (498× dieselbe Antwort), `gleiche_sorte` (ein Bildschirm ohne Wirkung), kein Offlinepuffer |
