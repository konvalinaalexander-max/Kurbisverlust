# 01 Eine Charge ganz durch — sortieren, umpalettieren, waschen, liefern

**Wer:** Vorarbeiter Tomasz, Zähler Ildikó, der Betriebsleiter am Abend
**Wann:** Tag −40 (Eingang) bis heute
**Ausgangslage:** eine frische Kopie der Demo-Datenbank; die Charge 9801
(Orangita, Schlag „Drehbuch") gibt es noch nicht. Sortierschema für Orangita
mit drei Kaliberbändern ist in der Demo hinterlegt.

Dieses Drehbuch ist das wichtigste: Es folgt einer Charge durch **jede**
Station und stellt an jeder die Frage, die der Betrieb gestellt hat — *was
weiss die App über eine Palette, nachdem sortiert wurde?* Die Antwort heute:
weniger, als der Arbeiter vor sich hat.

## Szenen

### S1 Der Wareneingang — sechs Paletten vom Feld
**Wirklichkeit.** Am Tag −40 kommen sechs Paletten Orangita vom Schlag. Jede
trägt einen Zettel: Datum, Charge, Brutto von der Hofwaage, 30 Kisten G2. Die
Zettel werden abends ins Erntejournal getippt; die App bekommt sie als
Wareneingang (Tabelle `palette`).
**In der App.** Keine — der Wareneingang kommt aus dem Journal.
**Gespeichert.** Sechs Zeilen `palette` mit eingangsdatum, brutto_kg 500, kisten 30, gebindeart G2.
**Sichtbar.** Chargen-Reiter: 9801, Eingang 2 580 kg (6 × (500 − 30 × 1.5 − 25)), 6 Paletten, alle mit Netto.

```sql szene S1
insert into charge (nr, schlag, sorte, saison) values (9801, 'Drehbuch', 'Orangita', extract(year from heute())::int);
insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
select 9801, heute() - 40, 500, 30, 'G2', 'drehbuch-01-' || i from generate_series(1, 6) i;
```
```sql pruefung S1
select eingang_netto_kg = 2580 and n_paletten = 6 and n_paletten_mit_netto = 6 as ok,
       eingang_netto_kg, n_paletten from v_charge_rueckgrat where charge_nr = 9801
```
**Urteil:** _(trägt die Runde ein)_

### S2 Lagerkontrolle am Tag −20 — eine Palette nachwiegen
**Wirklichkeit.** Tomasz nimmt Palette 3 aus dem Lager, stellt sie auf die
Waage: 494 kg brutto. Kein sichtbarer Schimmel. Er hat den Zettel: 500 kg am
Tag −40, 30 Kisten.
**In der App.** Start → *Palette kontrollieren* → Charge 9801 → Zettel-Datum,
Zettel-Brutto, Kisten, Gebindeart → Brutto jetzt 494 → *Speichern*.
**Gespeichert.** Eine Zeile `verdunstung_wiegung` (brutto_damals 500, brutto_jetzt 494, kisten 30, G2, gemessen).
**Sichtbar.** Ursachen → Verdunstung: eine Messung, 20 Lagertage, Rate 1 − (424/430)^(1/20) ≈ 0.000702 je Tag, verwendbar.

```sql szene S2
insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, gemessen, wiege_ts, bemerkung)
values (9801, heute() - 40, 500, 494, 30, 'G2', true, (heute() - 20)::timestamp + interval '10 hours', 'DREHBUCH 01 S2');
```
```sql pruefung S2
select m.verwendbar and m.lagertage = 20 and abs(m.rate_pro_tag - 0.000702) < 0.000002 as ok, m.lagertage, m.rate_pro_tag
  from v_verdunstung_messung m join verdunstung_wiegung w on w.id = m.id where w.bemerkung = 'DREHBUCH 01 S2'
```
**Urteil:** _(trägt die Runde ein)_

### S3 Sortieren am Tag −10 — die ganze Charge über die Maschine
**Wirklichkeit.** Alle sechs Paletten gehen über die Sortiermaschine. Ildikó
zählt jede Palette mit dem Datum vom Zettel. Der Palox wird zu Beginn
abgelesen (leer, 45 kg) und am Ende (105 kg): 60 kg Faules. Hinten kommen
160 Kisten heraus, nach Kaliber: 40 klein, 90 mittel, 30 gross. Die
Sortiermaschine schreibt ihre CSV.
**In der App.** Neue Arbeit → Sortieren → Charge 9801 → Kaliber wie zuletzt →
Palox ablesen → Zähler: sechs Paletten mit Datum → Kisten je Kaliber →
Abschluss: Palox ablesen, alles aus einer Charge, fertig.
**Gespeichert.** `auftrag` (sortieren), 6 × `auftrag_palette` (eingangsdatum), 2 × `schimmel_messung` (Palox-Stand 45 und 105 kg → 60 kg), 3 × `auftrag_gebinde`, `auftrag_angabe` eine_charge.
**Sichtbar.** Ursachen → Palox: ein Punkt bei 30 Lagertagen, Anteil 60 / (2580 · (1−r)^30) ≈ 2.4 %, plausibel.

```sql szene S3
insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, eroeffnet_von)
values ('maschine', 'sortieren', 9801, (heute() - 10)::timestamp + interval '8 hours', (heute() - 10)::timestamp + interval '12 hours',
        'abgeschlossen', 'DREHBUCH 01 S3', (select id from profil where rolle = 'admin' order by erstellt_ts limit 1));
insert into auftrag_palette (auftrag_id, eingangsdatum, ts)
select a.id, heute() - 40, a.start_ts + make_interval(mins => i * 15) from auftrag a, generate_series(1, 6) i where a.bemerkung = 'DREHBUCH 01 S3';
-- Zwei Ablesungen: der Palox leer zu Beginn (45 kg = Tara, „geleert" — sonst gilt
-- der gefallene Stand gegenüber der letzten Arbeit als unbekannt, 0060) und voll am
-- Ende (105 kg). Die Menge ist die Differenz (v_palox_stand); eine einzelne Ablesung hätte keine.
insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert, ts)
select id, 0, 45, true, start_ts from auftrag where bemerkung = 'DREHBUCH 01 S3';
insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts)
select id, 0, 105, ende_ts from auftrag where bemerkung = 'DREHBUCH 01 S3';
insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl, sortierdatum)
select id, k.idx, k.n, heute() - 10 from auftrag, (values (0, 40), (1, 90), (2, 30)) k(idx, n) where bemerkung = 'DREHBUCH 01 S3';
insert into auftrag_angabe (auftrag_id, schluessel, wert) select id, 'eine_charge', 'true' from auftrag where bemerkung = 'DREHBUCH 01 S3';
select auswertung_aktualisieren();   -- wie die App nach dem Abschluss: die Masse je Arbeit ist eine gespeicherte Sicht
```
```sql pruefung S3
select p.lagertage = 30 and p.plausibel and p.anteil between 0.02 and 0.03 and p.quelle = 'verarbeitung' as ok,
       p.lagertage, round(p.anteil, 4) as anteil, p.basis_jetzt_kg
  from v_schimmel_punkte p join auftrag a on a.id = p.auftrag_id where a.bemerkung = 'DREHBUCH 01 S3'
```
**Urteil:** _(trägt die Runde ein)_

### S4 Umpalettieren — die Kisten stehen jetzt auf neuen Paletten
**Wirklichkeit.** Hinter der Maschine stapelt Tomasz die 160 Kisten auf
fünf neue Paletten: zwei mit je 32 Kisten mittel, eine mit 26 Kisten mittel,
eine mit 40 klein, eine mit 30 gross. Jede neue Palette bekommt einen Zettel:
Charge, Kaliber, Kistenzahl, **Sortierdatum**. Ein Eingangsgewicht hat sie
nicht — die Kisten stammen aus sechs Eingangspaletten, gemischt. Ein
Eingangsdatum hat sie auch nicht, nur das der Charge (hier: alle am Tag −40,
in der Praxis oft eine Spanne).
**In der App.** Nichts. Die App kennt sortierte Paletten nicht als Paletten,
nur als Summe der Kisten je Kaliber (`auftrag_gebinde`).
**Gespeichert.** Nichts Neues.
**Sichtbar.** Chargen → 9801: sortiert 2 580 kg; „im Haus" nach Kaskade. Wie viele Paletten welchen Kalibers stehen, sieht niemand.
**Frage an die Runde.** Braucht die App die sortierte Palette als Ding? Für
die Verlustrechnung nicht (die Kaskade rechnet in Eingangskilo). Für die
Lagerkontrolle (S6) und für die Frage „was steht noch da?" vielleicht. Das ist
eine Frage an den Betrieb, keine Entscheidung des Programmierers (docs/FRAGEN.md).

```sql pruefung S4
select sum(anzahl) = 160 as ok, sum(anzahl) as kisten, count(*) as kaliber
  from auftrag_gebinde g join auftrag a on a.id = g.auftrag_id where a.bemerkung = 'DREHBUCH 01 S3'
```
**Urteil:** _(trägt die Runde ein)_

### S5 Waschen am Tag −3 — drei sortierte Paletten Kaliber mittel
**Wirklichkeit.** Ein Kunde will mittleres Kaliber. Tomasz holt drei der
neuen Paletten (32 + 32 + 26 Kisten mittel, Sortierdatum Tag −10). Waschen,
Kontrolle am Band: 8 kg Faules in den Palox. Hinten: drei fertige Paletten
mit je 30 Kisten, gewogen (brutto 478, 481, 476 kg, IFCO 6416, 6 Kürbisse je Kiste).
**In der App.** Neue Arbeit → Waschen → Charge 9801 → Kaliber mittel → Kistensystem „Kiste ab 8 kg" → Zähler: drei Paletten mit Sortierdatum und Kistenzahl → Palox (freiwillig) → fertige Paletten wiegen (3 von 3) → Abschluss.
**Gespeichert.** `auftrag` (waschen, kaliber_idx 1, kiste_ab 8), 3 × `auftrag_palette` (sortierdatum, kisten), `schimmel_messung` (8 kg), 3 × `ausgang_wiegung`.
**Sichtbar.** Chargen → 9801: gewaschen ≈ 90 Kisten × Kistengewicht; Herkunft „aus den gewaschenen Paletten"; Lagertage der Wäsche aus dem Sortier-Eingang (Tag −40 → −3 = 37).

```sql szene S5
insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, kaliber_idx, kistensystem, soll_kg_pro_kiste, eroeffnet_von)
values ('hand', 'waschen', 9801, (heute() - 3)::timestamp + interval '7 hours', (heute() - 3)::timestamp + interval '10 hours',
        'abgeschlossen', 'DREHBUCH 01 S5', 1, 'kiste_ab', 8, (select id from profil where rolle = 'admin' order by erstellt_ts limit 1));
insert into auftrag_palette (auftrag_id, sortierdatum, kisten, ts)
select a.id, heute() - 10, k.n, a.start_ts + make_interval(mins => k.i * 20) from auftrag a, (values (1, 32), (2, 32), (3, 26)) k(i, n) where a.bemerkung = 'DREHBUCH 01 S5';
insert into schimmel_messung (auftrag_id, kg, ts) select id, 8, ende_ts from auftrag where bemerkung = 'DREHBUCH 01 S5';
insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, kuerbisse_pro_kiste, gemessen, ts, kaliber_idx)
select a.id, 9801, k.b, 30, 'IFCO 6416', 6, true, a.ende_ts, 1 from auftrag a, (values (478), (481), (476)) k(b) where a.bemerkung = 'DREHBUCH 01 S5';
insert into auftrag_angabe (auftrag_id, schluessel, wert) select id, 'eine_charge', 'true' from auftrag where bemerkung = 'DREHBUCH 01 S5';
select auswertung_aktualisieren();
```
```sql pruefung S5
select m.eingang_netto_kg is not null and m.eingang_netto_kg > 0 and m.lagertage is not null and m.lagertage > 0 as ok,
       m.eingang_netto_kg, m.masse_quelle, m.lagertage
  from v_auftrag_masse m join auftrag a on a.id = m.auftrag_id where a.bemerkung = 'DREHBUCH 01 S5'
```
**Urteil:** _(trägt die Runde ein)_

### S6 Lagerkontrolle an einer sortierten Palette — die Szene, die heute nicht geht
**Wirklichkeit.** Am Tag −2 will der Betriebsleiter wissen, wie die sortierte
Ware liegt. Tomasz nimmt die Palette „40 Kisten klein, sortiert Tag −10",
wiegt sie: 331 kg brutto, 2 kg sichtbar faul in einer Kiste. Er weiss:
Charge 9801, Kaliber klein, 40 Kisten G2, Sortierdatum. Er weiss **nicht**:
was diese Kisten beim Eingang wogen (sechs Zettel, gemischt) und welchen
Eingangstag sie haben (hier zufällig einen; in der Praxis eine Spanne).
**In der App.** *Palette kontrollieren* verlangt Zettel-Datum und
Zettel-Brutto — und die Tabelle `verdunstung_wiegung` verlangt beides ebenso
(`brutto_damals_kg not null`). Beides gibt es nicht. Tomasz kann: (a)
abbrechen, (b) das Sortierdatum als Eingangsdatum und **das heutige Brutto
auch als damaliges** eintippen — die naheliegende Lüge, wenn ein Feld
ausgefüllt sein muss. Sie ergibt eine Rate von exakt 0 über 8 Tage, die als
**verwendbar** in die Sorte einfliesst und deren Verdunstungsrate nach unten
zieht; und einen Schimmel-Punkt mit 8 statt 38 Lagertagen.
**Erwartung an die Runde.** Ein dritter Weg: *Palette ohne Zettel (nach dem
Sortieren)* — speichert Sortierdatum, Kisten, Gebindeart, Brutto jetzt,
Faules; erzeugt **keine** Rate (kein „damals"), aber einen Schimmel-Punkt
(Lagertage = Alter der **Charge**, Quelle „lager") und einen Bestandsbeleg.
Bis dahin muss die Datenbank wenigstens eine Wägung mit `netto_jetzt =
netto_damals` am selben Tag wie das „Eingangsdatum" + wenige Tage als das
erkennen, was sie ist: kein Messwert. Prüfung heute: was mit (b) geschieht.
Sie ist **rot**, bis es den dritten Weg gibt oder die Sicht die Lüge erkennt.

```sql szene S6
insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, gemessen, wiege_ts, faul_kg, bemerkung)
values (9801, heute() - 10, 331, 331, 40, 'G2', true, (heute() - 2)::timestamp + interval '9 hours', 2, 'DREHBUCH 01 S6 ohne Zettel');
```
```sql pruefung S6
select not m.verwendbar as ok,
       m.verwendbar, m.rate_pro_tag, m.lagertage,
       (select count(*) from v_schimmel_punkte p where p.charge_nr = 9801 and p.quelle = 'lager') as lagerpunkte,
       (select min(p.lagertage) from v_schimmel_punkte p where p.charge_nr = 9801 and p.quelle = 'lager') as lagertage_des_punkts
  from v_verdunstung_messung m join verdunstung_wiegung w on w.id = m.id where w.bemerkung = 'DREHBUCH 01 S6 ohne Zettel'
```
_Anmerkung: Der Lagerpunkt bekommt hier 8 Lagertage (Sortierdatum als
„Eingang"), richtig wären 38 (Tag −40 bis −2). Das ist genau der Fehler, den
der dritte Weg vermeiden muss: Lagertage einer sortierten Palette = Alter der
**Charge**, nicht Alter der Palette._
**Urteil:** _(trägt die Runde ein)_

### S7 Liefern am Tag −1 — 1 200 kg an den Kunden
**Wirklichkeit.** Die drei gewaschenen Paletten gehen weg: 90 Kisten, 1 200 kg auf dem Lieferschein.
**In der App.** Betrieb → Warenausgang (Import) oder Lieferung von Hand.
**Gespeichert.** `lieferung` (verkauf, 1 200 kg, 90 Kisten).
**Sichtbar.** Überblick: geliefert 1 200 kg; Kaskade: ausgelagert m0 = 1 200 / verkaufsfaehig_anteil(39 Tage) > 1 200; im Lager: 2 580 − m0.

```sql szene S7
insert into lieferung (datum, charge_nr, sorte, kg, kisten, gebindeart, ziel, kunde, bemerkung)
values (heute() - 1, 9801, 'Orangita', 1200, 90, 'IFCO 6416', 'verkauf', 'Drehbuch-Kunde', 'DREHBUCH 01 S7');
select auswertung_aktualisieren();
```
```sql pruefung S7
select count(*) filter (where portion = 'ausgelagert') = 1
       and abs(sum(m0) - 2580) < 0.05
       and min(geliefert_kg) filter (where portion = 'ausgelagert') = 1200
       and max(ueberzaehlung_kg) = 0 as ok,
       round(sum(m0), 2) as summe_m0, round(sum(m0) filter (where portion = 'ausgelagert'), 2) as m0_ausgelagert,
       round(sum(m0) filter (where portion = 'lager'), 2) as m0_lager
  from mv_kaskade where charge_nr = 9801
```
**Urteil:** _(trägt die Runde ein)_

### S8 Der Betriebsleiter am Abend
**Wirklichkeit.** Er will drei Zahlen: Was kam rein, was ging raus, was liegt noch — und was davon ist schon verloren.
**In der App.** Chargen → 9801.
**Sichtbar.** Eingang 2 580 kg · geliefert 1 200 kg · ausgelagert (Eingangskilo hinter der Lieferung) > 1 200 · Lager = Eingang − ausgelagert · Verlust bis heute > 0 (Verdunstung 40 Tage + Palox-Kurve).

```sql pruefung S8
select eingang_kg = 2580 and ausgelagert_kg > 1200 and abs(lager_kg - (eingang_kg - ausgelagert_kg)) < 0.05 as ok,
       eingang_kg, ausgelagert_kg, lager_kg
  from erg_charge where charge_nr = 9801
```
**Urteil:** _(trägt die Runde ein)_
