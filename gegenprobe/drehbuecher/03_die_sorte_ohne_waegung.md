# 03 Die Sorte ohne Wägung

**Wer:** der Betriebsleiter, Vorarbeiter Tomasz, Zählerin Ildikó
**Wann:** die ersten Wochen mit der App — vom ersten Eingang bis zum ersten Fax-Tag
**Ausgangslage:** eine frisch eingerichtete App. Die Stammdaten stehen (Sorten
mit Kaliberbändern, Gebinde mit Tara, Käufer, Sortierschemata, Mitarbeiter);
Beobachtungen gibt es keine. Genau so beginnt jede Saison auf dem Betrieb, und
genau so hat die App am ersten Tag ausgesehen.

Dieses Drehbuch stellt die Frage, die der Betriebsleiter in Runde P gestellt
hat, an den ungünstigsten Fall: **„Wie viel von dem, was noch im Haus ist, ist
verkaufsfähig?"** — gefragt an eine Sorte, an der noch nichts gemessen wurde.
Die richtige Antwort ist dann nicht 100 % und nicht 0 %, sondern **„das weiss
ich noch nicht"**. Die falsche Antwort wäre eine Zahl, und eine Zahl sieht auf
dem Bildschirm immer gleich überzeugend aus, egal woher sie kommt.

Der Bogen der sechs Szenen ist der Bogen einer Saison: Aus „nichts gemessen"
wird Messung für Messung „gemessen", und der Anteil erscheint erst, wenn die
Kaskade vollständig ist — nicht früher, aber auch nicht später.

> **Achtung beim Spielen.** S1 leert die Beobachtungstabellen: Die Szene
> beginnt in einer leeren App, und eine Kopie der Demo ist nicht leer. **Jede**
> Szene weigert sich darum, auf einer Datenbank zu laufen, deren Name nicht mit
> `drehbuch` oder `probe` beginnt. `spieler.mjs 03` legt von selbst
> `drehbuch_03` aus der Demo an; `--db demo` bricht ab, statt die Demo
> auszuräumen.
>
> Die Wache steht in jeder Szene und nicht nur in S1, und das ist keine
> Vorsicht auf Vorrat: Der Spieler führt nach einer gescheiterten Szene die
> nächste trotzdem aus (er will den ganzen Befund, nicht den ersten Fehler).
> Mit der Wache allein in S1 hat genau das beim Bauen dieser Runde zwei
> Chargen in die Demo geschrieben.

## Szenen

### S1 Der erste Tag — zehn Paletten, und sonst nichts
**Wirklichkeit.** Mitte August kommt der erste Anhänger vom Feld: zehn Paletten
Kaori Kuri vom Schlag „Drehbuch", je 32 Kisten, je 520 kg brutto auf der
Brückenwaage. Niemand hat an diesem Tag etwas gewogen, sortiert, gewaschen oder
abgepackt — es ist der erste Tag.
**In der App.** Wareneingang → Charge 9803 anlegen (Schlag, Sorte, Saison) →
zehn Paletten mit Eingangsdatum, Brutto, Kisten und Gebindeart.
**Gespeichert.** `charge` (eine Zeile), `palette` (zehn Zeilen). Netto je
Palette = 520 − 32 × 1.5 − 25 = **447 kg**, zusammen **4 470 kg**.
**Sichtbar.** Überblick: Eingang 4 470 kg, Ausgeliefert 0, Im Lager 4 470 kg —
und bei „Davon verkaufsfähig" **keine Zahl**, sondern der Hinweis, dass noch
nichts gemessen ist.
**Erwartung.** `erg_prognose.verkaufsfaehig_anteil` ist **NULL**, und alle fünf
Kennzeichen (`r_bekannt`, `f_bekannt`, `sockel_bekannt`, `kanal_bekannt`,
`fax_bekannt`) sind false. Die Massenspalte `verkaufsfaehig_kg` steht auf dem
vollen Lagerbestand — sie ist die **obere Schranke**, nicht die Schätzung, und
darum darf der Bildschirm sie nicht als Prozentzahl verkaufen.

```sql szene S1
do $$ begin
  if current_database() !~ '^(drehbuch|probe)' then
    raise exception 'Drehbuch 03 leert die Beobachtungen und läuft nur auf einer Spielkopie (Name beginnt mit drehbuch oder probe) — hier: %', current_database();
  end if;
end $$;
set client_min_messages = warning;
truncate charge, lieferung, verdunstung_wiegung, schimmel_messung, sortier_lauf,
         ausschuss_messung, charge_vorlauf, ausgang_datei, lieferung_import cascade;
insert into charge (nr, schlag, sorte, saison) values (9803, 'Drehbuch', 'Kaori Kuri', extract(year from heute())::int);
insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
select 9803, heute() - 30, 520, 32, 'G2', 'drehbuch-03-' || g from generate_series(1, 10) g;
select auswertung_aktualisieren();
```
```sql pruefung S1
select p.lager_kg = 4470 and p.verkaufsfaehig_anteil is null
       and not (p.r_bekannt or p.f_bekannt or p.sockel_bekannt or p.kanal_bekannt or p.fax_bekannt)
       and not p.vollstaendig
       and p.verkaufsfaehig_kg = p.lager_kg                          as ok,
       p.lager_kg, p.verkaufsfaehig_kg, p.verkaufsfaehig_anteil,
       (select eingang_kg from erg_bilanz)                           as eingang_kg
  from erg_prognose p where p.gruppe = 'gesamt' and p.h = 0
```
**Urteil: geht, aber.** Die Datenbank hat die Szene sauber getragen — Anteil
NULL, alle fünf Kennzeichen false, `verkaufsfaehig_kg` gleich `lager_kg`. Auf
dem Bildschirm stand die Kopfzahl „Davon verkaufsfähig" aber als **4.5 t** da,
ohne Vorbehalt: richtige Masse, falscher Eindruck, denn sie ist die obere
Schranke und nicht die Schätzung. Der Prozentsatz fehlte korrekt, und der
Hinweis darunter sagte auch, warum. Runde P setzt darum in `Ueberblick.tsx` ein
kleines **„höchstens"** vor die Masse, solange der Anteil unbekannt ist — genau
wie die Nachbarkarte es bei „im Haus gesamt" schon tat.

### S2 Der Verkauf läuft — 1 200 kg gehen raus
**Wirklichkeit.** Zehn Tage später holt der erste Kunde 1 200 kg ab. Gemessen
wurde immer noch nichts: Der Lieferschein sagt, was das Haus verlassen hat,
nicht, wie gut der Rest ist.
**In der App.** Warenausgang → Lieferung (Datum, Charge, Kilo, Kunde).
**Gespeichert.** `lieferung` (eine Zeile, Ziel „verkauf").
**Sichtbar.** Überblick: Eingang 4 470, Ausgeliefert 1 200, Im Lager 3 270 —
drei Zahlen, die der Betriebsleiter sofort nachrechnen kann. „Davon
verkaufsfähig" bleibt leer.
**Erwartung.** Die **Bilanz** braucht keine Messung: Eingang minus
Ausgeliefert ist die liegende Ware, und diese drei Zahlen stimmen ab dem ersten
Tag. Der **Anteil** braucht sie sehr wohl und bleibt NULL. Das ist der
Unterschied, um den es in diesem Drehbuch geht. In `v_wohin` bleiben darum auch
die Stromspalten und der Rest leer — nicht null: Wie viel von der
ausgelieferten Ware unterwegs verdunstet ist, weiss an diesem Tag niemand.

```sql szene S2
do $$ begin if current_database() !~ '^(drehbuch|probe)' then
  raise exception 'Drehbuch 03 schreibt Beobachtungen und läuft nur auf einer Spielkopie (Name beginnt mit drehbuch oder probe) — hier: %', current_database();
end if; end $$;
insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
values (heute() - 5, 9803, 'Kaori Kuri', 1200, 'verkauf', 'Drehbuch-Kunde', 'DREHBUCH 03 S2');
select auswertung_aktualisieren();
```
```sql pruefung S2
select w.eingang_kg = 4470 and w.geliefert_kg = 1200 and w.lager_kg = 3270
       and p.verkaufsfaehig_anteil is null and not p.vollstaendig             as ok,
       w.eingang_kg, w.geliefert_kg, w.lager_kg, p.verkaufsfaehig_anteil
  from erg_wohin w
  join erg_prognose p on p.gruppe = w.gruppe and p.schluessel = w.schluessel and p.h = 0
 where w.gruppe = 'gesamt'
```
**Urteil: geht.** Eingang 4 470, Ausgeliefert 1 200, Im Lager 3 270 — drei
Zahlen ohne eine einzige Messung, und der Anteil blieb leer. Genau diese
Trennung wollte der Betriebsleiter: Die Bilanz ist Buchhaltung, der Anteil ist
Messung.

### S3 Die erste Lagerkontrolle — eine Palette nachwiegen
**Wirklichkeit.** Tomasz nimmt an Tag 30 eine der Eingangspaletten auf den
Hubwagen und fährt sie über die Waage: 512 kg brutto, kein sichtbarer Schimmel.
Der Zettel sagt 520 kg — acht Kilo Wasser in dreissig Tagen.
**In der App.** Lagerkontrolle → Charge → Palette wiegen (Brutto jetzt,
sichtbarer Schimmel ja/nein).
**Gespeichert.** `verdunstung_wiegung` (Brutto damals, Brutto jetzt, Kisten,
Gebindeart, Wiegezeitpunkt).
**Sichtbar.** Ursachen → Verdunstung: ein Punkt, eine Rate — 0.060 % je Tag.
**Erwartung.** `r_bekannt` wird **true**, die anderen vier bleiben false, und
der verkaufsfähige Anteil bleibt **leer**. Eine Messung macht einen
Koeffizienten bekannt, nicht die Kaskade. Wer aus einer Wägung eine Prozentzahl
für das ganze Lager macht, hat vier Unbekannte auf null gesetzt und es nicht
dazugesagt.

```sql szene S3
do $$ begin if current_database() !~ '^(drehbuch|probe)' then
  raise exception 'Drehbuch 03 schreibt Beobachtungen und läuft nur auf einer Spielkopie (Name beginnt mit drehbuch oder probe) — hier: %', current_database();
end if; end $$;
insert into verdunstung_wiegung (charge_nr, palette_id, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                 kisten, gebindeart, sichtbar_schimmel, gemessen, wiege_ts, bemerkung)
select 9803, p.id, p.eingangsdatum, p.brutto_kg, 512, p.kisten, p.gebindeart, false, true,
       heute()::timestamp + interval '9 hours', 'DREHBUCH 03 S3'
  from palette p where p.extern_id = 'drehbuch-03-1';
select auswertung_aktualisieren();
```
```sql pruefung S3
select m.verwendbar and m.lagertage = 30
       and p.r_bekannt and not p.f_bekannt and not p.sockel_bekannt
       and not p.kanal_bekannt and not p.fax_bekannt
       and p.verkaufsfaehig_anteil is null                                     as ok,
       m.lagertage, round(m.rate_pro_tag, 6) as rate_pro_tag, p.verkaufsfaehig_anteil
  from v_verdunstung_messung m
  cross join (select * from erg_prognose where gruppe = 'gesamt' and h = 0) p
 where m.charge_nr = 9803
```
**Urteil: geht.** 30 Lagertage, 0.060 % je Tag, `verwendbar = true`;
`r_bekannt` wurde true, die anderen vier blieben false, der Anteil blieb leer.
Eine Wägung macht einen Koeffizienten, keine Kaskade.

### S4 Der erste Sortierlauf — Palox abgelesen, Kaliber gezählt
**Wirklichkeit.** An Tag 28 nach dem Eingang laufen drei Paletten über die
Sortiermaschine. Tomasz kippt den Palox vor dem Beginn aus und liest ihn ab
(45 kg — die leere Kiste, die Tara), nach dem Ende steht er auf 93 kg: 48 kg
Faules aus dieser Arbeit. Die Maschine schreibt
1 000 Kürbisse in ihre Datei — 40 unter 600 g, 20 über 2 000 g, der Rest in den
drei Bändern.
**In der App.** Neue Arbeit → Sortieren → Charge 9803 → Sortierschema → Zähler:
drei Eingangspaletten → Palox bei Beginn ablesen („geleert?" ja) und bei
Abschluss → Sortierdatei hochladen → Abschluss („alles aus einer Charge": ja).
Das Häkchen „geleert" ist keine Förmlichkeit: Ohne es wäre der gefallene Stand
eine unbekannte Menge, und die ganze Arbeit fiele aus der Verderbskurve (0060).
**Gespeichert.** `auftrag`, 3 × `auftrag_palette`, 2 × `schimmel_messung`
(Palox-Stände), `sortier_lauf` + `sortier_gewicht`, `auftrag_angabe`.
**Sichtbar.** Ursachen → Palox: ein Punkt bei 28 Lagertagen. Chargen: die
Kaliberverteilung der Sorte.
**Erwartung.** Jetzt sind **drei** Koeffizienten bekannt: die Verdunstung aus
S3, der Fäulnisanteil aus der Treppe der Messpunkte und die beiden
Kaliber-Anteile aus der Sortierdatei. **Nicht** bekannt sind der Sockel a₀ —
er ist der Achsenabschnitt des Verderbsmodells und braucht mindestens drei
Chargen über eine gespreizte Lagerdauer — und der Fax-Anteil, für den es noch
keinen Fax-Tag gab. Der verkaufsfähige Anteil bleibt darum **leer**, obwohl
schon drei von fünf Zahlen dastehen. Das ist die Stelle, an der eine bequeme
Auswertung anfangen würde zu raten.

```sql szene S4
do $$ begin if current_database() !~ '^(drehbuch|probe)' then
  raise exception 'Drehbuch 03 schreibt Beobachtungen und läuft nur auf einer Spielkopie (Name beginnt mit drehbuch oder probe) — hier: %', current_database();
end if; end $$;
insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, sortierschema_id, bemerkung, eroeffnet_von)
select 'maschine', 'sortieren', 9803, (heute() - 2)::timestamp + interval '8 hours', (heute() - 2)::timestamp + interval '13 hours',
       'abgeschlossen', s.id, 'DREHBUCH 03 S4', (select id from profil where rolle = 'admin' order by erstellt_ts limit 1)
  from sortierschema s
 where s.sorte = 'Kaori Kuri' and s.art = 'kaliber' and s.kaeufer is null
 order by s.gilt_ab, s.id limit 1;
insert into auftrag_palette (auftrag_id, palette_id, eingangsdatum, ts)
select a.id, p.id, p.eingangsdatum, a.start_ts + interval '10 minutes'
  from auftrag a, palette p
 where a.bemerkung = 'DREHBUCH 03 S4' and p.extern_id in ('drehbuch-03-2', 'drehbuch-03-3', 'drehbuch-03-4');
insert into auftrag_angabe (auftrag_id, schluessel, wert)
select id, 'eine_charge', 'true' from auftrag where bemerkung = 'DREHBUCH 03 S4';
insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert, ts)
select id, 0, 45, true, start_ts from auftrag where bemerkung = 'DREHBUCH 03 S4'
union all
select id, 0, 93, false, ende_ts from auftrag where bemerkung = 'DREHBUCH 03 S4';
insert into sortier_lauf (charge_nr, datei_name, roh_pruefsumme, datei_zeit, datei_zeit_quelle, auftrag_id,
                          zuordnung, reinigung, n_roh, n_overflow, n_klein, n_dubletten, n_gueltig, sortierschema_id)
select 9803, 'DREHBUCH-03-9803', 'drehbuch-03-9803', a.ende_ts, 'dateiname', a.id, 'auto',
       '{"min_gramm": 100, "overflow_ab": 60000, "dubletten_zusammenfassen": true}'::jsonb,
       1000, 0, 0, 0, 1000, a.sortierschema_id
  from auftrag a where a.bemerkung = 'DREHBUCH 03 S4';
insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
select l.id, g.gewicht_g, g.anzahl, g.klasse, g.kaliber_idx
  from sortier_lauf l,
       (values (450, 40, 'verlust_klein'::kuerbis_klasse, null::int),
               (800, 500, 'kaliber'::kuerbis_klasse, 0),
               (1300, 380, 'kaliber'::kuerbis_klasse, 1),
               (1800, 60, 'kaliber'::kuerbis_klasse, 2),
               (2300, 20, 'nebenkanal'::kuerbis_klasse, null)) g(gewicht_g, anzahl, klasse, kaliber_idx)
 where l.datei_name = 'DREHBUCH-03-9803';
select auswertung_aktualisieren();
```
```sql pruefung S4
select p.r_bekannt and p.f_bekannt and p.kanal_bekannt
       and not p.sockel_bekannt and not p.fax_bekannt
       and not p.vollstaendig and p.verkaufsfaehig_anteil is null              as ok,
       p.r_bekannt, p.f_bekannt, p.kanal_bekannt, p.sockel_bekannt, p.fax_bekannt,
       (select round(anteil::numeric, 4) from v_schimmel_punkte where charge_nr = 9803) as palox_anteil
  from erg_prognose p where p.gruppe = 'gesamt' and p.h = 0
```
**Urteil: geht.** Palox 45 → 93 kg auf 1 341 kg Eingangsware: 3.6 % bei 28
Lagertagen, der erste Punkt der Verderbskurve. Drei von fünf Koeffizienten
bekannt, Anteil weiterhin leer. Festzuhalten ist, wie viel am Häkchen
**„Palox geleert"** hängt: Ohne es steht der Palox beim Beginn tiefer als beim
Ende der vorigen Arbeit, die Menge dieser Ablesung ist unbekannt, und die ganze
Arbeit fällt aus der Kurve (0060). Beim ersten Bauen dieses Drehbuchs war genau
das der Fehler — zwei von drei Sortierläufen verschwanden lautlos aus dem
Verderbsmodell. Die App fragt danach; die Frage ist keine Förmlichkeit.

### S5 Zwei weitere Chargen — jetzt trägt das Verderbsmodell
**Wirklichkeit.** September und Oktober: Zwei weitere Schläge kommen herein und
werden sortiert, der eine nach 55 Lagertagen, der andere nach 87. Der Palox
füllt sich sichtbar schneller, je länger die Ware lag — 6.9 % und 11.8 % gegen
die 3.6 % der jungen Charge.
**In der App.** Dieselben Masken wie in S1 und S4, zweimal.
**Gespeichert.** Zwei `charge`-Zeilen mit Paletten, zwei Sortier-Arbeiten mit
Palox-Ablesungen und Sortierdateien.
**Sichtbar.** Ursachen → Palox: drei Punkte, und dazu zum ersten Mal eine
Kurve. Messungen → Koeffizienten: der Sockel a₀ hat eine Zahl.
**Erwartung.** Das Verderbsmodell wird brauchbar (drei Punkte aus drei Chargen,
Lagerdauer von 28 bis 87 Tagen gespreizt) — `sockel_bekannt` und `modell_gilt`
werden true. Es fehlt nur noch der Fax-Anteil, und darum bleibt der
verkaufsfähige Anteil **immer noch leer**. Vier von fünf ist nicht vier
Fünftel: Eine Kaskade mit einer unbekannten Stufe hat kein Ergebnis, nur eine
obere Schranke.

```sql szene S5
do $$ begin if current_database() !~ '^(drehbuch|probe)' then
  raise exception 'Drehbuch 03 schreibt Beobachtungen und läuft nur auf einer Spielkopie (Name beginnt mit drehbuch oder probe) — hier: %', current_database();
end if; end $$;
insert into charge (nr, schlag, sorte, saison) values
  (9804, 'Drehbuch Süd',  'Kaori Kuri', extract(year from heute())::int),
  (9805, 'Drehbuch West', 'Kaori Kuri', extract(year from heute())::int);
insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
select c.nr, heute() - c.alter_tage, 520, 32, 'G2', 'drehbuch-03-' || c.nr || '-' || g
  from (values (9804, 60), (9805, 90)) c(nr, alter_tage), generate_series(1, 6) g;
insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, sortierschema_id, bemerkung, eroeffnet_von)
select 'maschine', 'sortieren', c.nr, (heute() - c.vor_tagen)::timestamp + interval '8 hours',
       (heute() - c.vor_tagen)::timestamp + interval '13 hours', 'abgeschlossen', s.id,
       'DREHBUCH 03 S5-' || c.nr, (select id from profil where rolle = 'admin' order by erstellt_ts limit 1)
  from (values (9804, 5), (9805, 3)) c(nr, vor_tagen),
       lateral (select id from sortierschema where sorte = 'Kaori Kuri' and art = 'kaliber' and kaeufer is null
                 order by gilt_ab, id limit 1) s;
insert into auftrag_palette (auftrag_id, palette_id, eingangsdatum, ts)
select a.id, p.id, p.eingangsdatum, a.start_ts + interval '10 minutes'
  from auftrag a join palette p on p.charge_nr = a.charge_nr
 where a.bemerkung like 'DREHBUCH 03 S5-%'
   and p.extern_id in ('drehbuch-03-9804-1', 'drehbuch-03-9804-2', 'drehbuch-03-9804-3',
                       'drehbuch-03-9805-1', 'drehbuch-03-9805-2', 'drehbuch-03-9805-3');
insert into auftrag_angabe (auftrag_id, schluessel, wert)
select id, 'eine_charge', 'true' from auftrag where bemerkung like 'DREHBUCH 03 S5-%';
insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert, ts)
select a.id, 0, 45, true, a.start_ts from auftrag a where a.bemerkung like 'DREHBUCH 03 S5-%'
union all
select a.id, 0, 45 + f.faul_kg, false, a.ende_ts
  from auftrag a join (values ('DREHBUCH 03 S5-9804', 90), ('DREHBUCH 03 S5-9805', 150)) f(bem, faul_kg)
    on f.bem = a.bemerkung;
insert into sortier_lauf (charge_nr, datei_name, roh_pruefsumme, datei_zeit, datei_zeit_quelle, auftrag_id,
                          zuordnung, reinigung, n_roh, n_overflow, n_klein, n_dubletten, n_gueltig, sortierschema_id)
select a.charge_nr, 'DREHBUCH-03-' || a.charge_nr, 'drehbuch-03-' || a.charge_nr, a.ende_ts, 'dateiname', a.id, 'auto',
       '{"min_gramm": 100, "overflow_ab": 60000, "dubletten_zusammenfassen": true}'::jsonb,
       1000, 0, 0, 0, 1000, a.sortierschema_id
  from auftrag a where a.bemerkung like 'DREHBUCH 03 S5-%';
insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
select l.id, g.gewicht_g, g.anzahl, g.klasse, g.kaliber_idx
  from sortier_lauf l,
       (values (450, 40, 'verlust_klein'::kuerbis_klasse, null::int),
               (800, 500, 'kaliber'::kuerbis_klasse, 0),
               (1300, 380, 'kaliber'::kuerbis_klasse, 1),
               (1800, 60, 'kaliber'::kuerbis_klasse, 2),
               (2300, 20, 'nebenkanal'::kuerbis_klasse, null)) g(gewicht_g, anzahl, klasse, kaliber_idx)
 where l.datei_name in ('DREHBUCH-03-9804', 'DREHBUCH-03-9805');
select auswertung_aktualisieren();
```
```sql pruefung S5
select p.sockel_bekannt and p.modell_gilt and not p.fax_bekannt
       and not p.vollstaendig and p.verkaufsfaehig_anteil is null              as ok,
       p.sockel_bekannt, p.modell_gilt, p.fax_bekannt, p.verkaufsfaehig_anteil,
       (select count(*) from v_schimmel_punkte where plausibel)                as palox_punkte
  from erg_prognose p where p.gruppe = 'gesamt' and p.h = 0
```
**Urteil: geht.** Drei Punkte aus drei Chargen (28, 55, 87 Lagertage; 3.6 %,
6.9 %, 11.8 %) machen das Verderbsmodell brauchbar — `modell_gilt` und
`sockel_bekannt` wurden true, der Sockel a₀ kam auf 0.0000, also „gemessen und
null", nicht „unbekannt". Der Anteil blieb trotzdem leer, weil der Fax-Anteil
fehlte. Vier von fünf ist eben nicht vier Fünftel.

### S6 Waschen und der erste Fax-Tag — jetzt steht die Zahl
**Wirklichkeit.** Anfang November wird zum ersten Mal gewaschen: drei sortierte
Paletten mittleres Kaliber, hinten kommen drei fertige Paletten heraus, alle
drei gewogen (478, 481, 476 kg brutto, IFCO 6416, 30 Kisten). Am nächsten Tag
werden sie etikettiert — der Fax-Tag. Dabei landen 14 kg im Ausschuss, gewogen,
nicht geschätzt.
**In der App.** Neue Arbeit → Waschen → Kistensystem „Kiste ab 8 kg" → fertige
Paletten wiegen. Dann: Neue Arbeit → Fax → Paletten gesamt → Faules wiegen →
„Tage seit dem Waschen" (die App schlägt 1 vor, aus der Wasch-Arbeit derselben
Charge).
**Gespeichert.** Zwei `auftrag`-Zeilen, `auftrag_palette`, `schimmel_messung`,
3 × `ausgang_wiegung`; am Fax-Auftrag `paletten_gesamt` und
`tage_seit_waschen`.
**Sichtbar.** Überblick: „Davon verkaufsfähig" hat zum ersten Mal eine Zahl,
mit Bereich daneben. Ursachen → Faules beim Abpacken: der Anteil nach
Wartezeit.
**Erwartung.** Alle fünf Koeffizienten sind bekannt, `vollstaendig` wird true,
und der Anteil erscheint — **echt zwischen 0 und 1**, nicht 1. Die Hülle
(`verkaufsfaehig_unten_kg` … `verkaufsfaehig_oben_kg`) schliesst die Masse ein,
und über den Horizont bis zum Saisonende fällt der Anteil, weil Wasser und
Fäulnis weiterlaufen. Das ist die Zahl, nach der der Betriebsleiter gefragt
hat — und sie steht erst da, seit sie verdient ist.

```sql szene S6
do $$ begin if current_database() !~ '^(drehbuch|probe)' then
  raise exception 'Drehbuch 03 schreibt Beobachtungen und läuft nur auf einer Spielkopie (Name beginnt mit drehbuch oder probe) — hier: %', current_database();
end if; end $$;
insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, kaliber_idx,
                     kistensystem, soll_kg_pro_kiste, eroeffnet_von)
values ('hand', 'waschen', 9803, (heute() - 1)::timestamp + interval '7 hours', (heute() - 1)::timestamp + interval '10 hours',
        'abgeschlossen', 'DREHBUCH 03 S6-waschen', 1, 'kiste_ab', 8,
        (select id from profil where rolle = 'admin' order by erstellt_ts limit 1));
insert into auftrag_palette (auftrag_id, sortierdatum, kisten, ts)
select a.id, heute() - 2, k.n, a.start_ts + make_interval(mins => k.i * 20)
  from auftrag a, (values (1, 32), (2, 32), (3, 26)) k(i, n) where a.bemerkung = 'DREHBUCH 03 S6-waschen';
insert into schimmel_messung (auftrag_id, kg, ts)
select id, 8, ende_ts from auftrag where bemerkung = 'DREHBUCH 03 S6-waschen';
insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, kuerbisse_pro_kiste, gemessen, ts, kaliber_idx)
select a.id, 9803, k.b, 30, 'IFCO 6416', 6, true, a.ende_ts, 1
  from auftrag a, (values (478), (481), (476)) k(b) where a.bemerkung = 'DREHBUCH 03 S6-waschen';
insert into auftrag_angabe (auftrag_id, schluessel, wert)
select id, 'eine_charge', 'true' from auftrag where bemerkung = 'DREHBUCH 03 S6-waschen';

insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, ist_fax,
                     kistensystem, soll_kg_pro_kiste, paletten_gesamt, tage_seit_waschen, eroeffnet_von)
values ('hand', 'waschen', 9803, heute()::timestamp + interval '7 hours', heute()::timestamp + interval '11 hours',
        'abgeschlossen', 'DREHBUCH 03 S6-fax', true, 'kiste_ab', 8, 3, 1,
        (select id from profil where rolle = 'admin' order by erstellt_ts limit 1));
insert into schimmel_messung (auftrag_id, kg, ts)
select id, 14, ende_ts from auftrag where bemerkung = 'DREHBUCH 03 S6-fax';
select auswertung_aktualisieren();
```
```sql pruefung S6
select p.vollstaendig and p.fax_bekannt
       and p.verkaufsfaehig_anteil is not null
       and p.verkaufsfaehig_anteil > 0 and p.verkaufsfaehig_anteil < 1
       and p.verkaufsfaehig_unten_kg <= p.verkaufsfaehig_kg
       and p.verkaufsfaehig_kg <= p.verkaufsfaehig_oben_kg
       and e.verkaufsfaehig_anteil < p.verkaufsfaehig_anteil                   as ok,
       p.verkaufsfaehig_anteil as anteil_heute, e.verkaufsfaehig_anteil as anteil_saisonende,
       e.h as tage_bis_saisonende, p.verkaufsfaehig_unten_kg, p.verkaufsfaehig_kg, p.verkaufsfaehig_oben_kg
  from erg_prognose p
  join lateral (select * from erg_prognose x where x.gruppe = p.gruppe and x.schluessel = p.schluessel
                 order by x.h desc limit 1) e on true
 where p.gruppe = 'gesamt' and p.h = 0
```
**Urteil: geht.** Mit dem ersten Fax-Tag (3 Paletten × 402.93 kg netto,
14 kg gewogenes Faules → a_fax = 1.15 %) wurde `vollstaendig` true, und der
Anteil erschien: **82.9 % heute**, 78.2 % in vier Wochen, **54.0 % am
31.03.2027**, mit der Hülle 6 714.9 … 7 088.8 kg um die 7 027.2 kg. Das ist die
Antwort auf die Frage des Betriebsleiters, und sie stand keinen Tag zu früh da.
Nebenbefund, ebenfalls richtig: Die Wasch-Arbeit selbst hat **keine** Masse
(`masse_quelle = 'fehlt'`), weil für dieses Kaliber beim Sortieren nie Kisten
mitgezählt wurden — ihre 8 kg Faules fliessen nirgends ein. Die App schweigt
darüber nicht, sondern meldet beides unter Messungen → Auffälligkeiten
(„Ohne Nenner", „Kistengewicht"). Lieber eine Messung weniger als eine
erfundene Bezugsmasse.

## Was dieses Drehbuch festhält

1. **Leer ist nicht null.** Über fünf Szenen hinweg stand bei „Davon
   verkaufsfähig" kein Prozentsatz — und das war jedes Mal die richtige
   Antwort, nicht ein fehlendes Feature.
2. **Die Bilanz kann, was das Modell nicht kann.** Eingang, Ausgeliefert und Im
   Lager stimmen ab dem ersten Tag. Nur der Anteil braucht Messungen. Die zwei
   Sorten von Zahl dürfen auf dem Bildschirm nicht gleich aussehen.
3. **Ein Koeffizient ist kein Ergebnis.** Nach der ersten Wägung, nach dem
   ersten Sortierlauf und selbst nach drei Sortierläufen blieb der Anteil leer.
   Er erschien erst, als alle fünf Stufen der Kaskade eine gemessene Zahl
   hatten.
4. **Wenn er erscheint, ist er echt.** 82.9 % heute, 54.0 % am Saisonende, mit
   Hülle — keine Rundung auf 100 %, kein Vorgabewert.
5. **Gefunden und behoben.** Die Kopfzahl zeigte die obere Schranke wie eine
   Schätzung; sie sagt jetzt „höchstens", solange ein Koeffizient fehlt.

Gespielt mit `node gegenprobe/drehbuecher/spieler.mjs 03` auf einer frischen
Kopie der Demo (`drehbuch_03`), heute = 2026-09-13, Saisonende 2027-03-31:
6 Prüfungen, 0 nicht ok.
