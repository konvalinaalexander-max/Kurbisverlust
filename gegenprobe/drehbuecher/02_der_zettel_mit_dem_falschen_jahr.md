# 02 Der Zettel mit dem falschen Jahr

**Wer:** Zähler Ildikó, der Betriebsleiter
**Wann:** Tag −45 (Eingang), Sortieren am Tag −1
**Ausgangslage:** frische Kopie der Demo; Charge 9802 (Kaori Kuri) gibt es noch nicht.

Das ist der Fall vom Betrieb, wörtlich: Auf dem Reiter *Ursachen* ging die
x-Achse von „Palox: Faules im Lager" bis −1000 Tage, und alle Messungen sassen
als ein Strich ganz rechts. Ursache: ein Zettel mit dem Jahr 2029 statt 2026,
so eingetippt, so gespeichert — **richtig so**, denn gespeichert wird, was
beobachtet wurde. Falsch war, was danach geschah: Die Auswertung hat aus
−1051 Lagertagen einen plausiblen Punkt gemacht, und das Diagramm hat ihm
die ganze Achse gegeben.

## Szenen

### S1 Sortieren — Ildikó tippt 2029
**Wirklichkeit.** Eine Palette, Zettel „15.7." — das Jahr steht klein
daneben, Ildikó wählt im Datumsfeld 2029. Der Palox am Ende: 12 kg.
**In der App.** Zähler → Palette → Datum → speichern. Kein Hinweis, kein Halt.
**Gespeichert.** `auftrag_palette.eingangsdatum` = 2029-xx-xx — so, wie getippt.
**Erwartung an die Runde (Maske).** Ein Eingangsdatum **nach heute** ist unmöglich. Die Maske sagt es sofort („liegt in der Zukunft — Jahr prüfen") und speichert trotzdem, wenn der Zähler besteht: Beobachtung vor Bequemlichkeit, aber nie ohne Hinweis. Prüfen: Bildschirm-Prüfstand, Szene `zaehler-zukunft` (Phase 5).

```sql szene S1
insert into charge (nr, schlag, sorte, saison) values (9802, 'Drehbuch', 'Kaori Kuri', extract(year from heute())::int);
insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
values (9802, heute() - 45, 500, 30, 'G2', 'drehbuch-02-1');
insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, eroeffnet_von)
values ('maschine', 'sortieren', 9802, (heute() - 1)::timestamp + interval '8 hours', (heute() - 1)::timestamp + interval '10 hours',
        'abgeschlossen', 'DREHBUCH 02 S1', (select id from profil where rolle = 'admin' order by erstellt_ts limit 1));
insert into auftrag_palette (auftrag_id, eingangsdatum, ts)
select id, (heute() - 45 + interval '3 years')::date, start_ts + interval '10 minutes' from auftrag where bemerkung = 'DREHBUCH 02 S1';
insert into schimmel_messung (auftrag_id, kg, ts) select id, 12, ende_ts from auftrag where bemerkung = 'DREHBUCH 02 S1';
insert into auftrag_angabe (auftrag_id, schluessel, wert) select id, 'eine_charge', 'true' from auftrag where bemerkung = 'DREHBUCH 02 S1';
select auswertung_aktualisieren();
```
```sql pruefung S1
select ap.eingangsdatum > heute() as ok, ap.eingangsdatum
  from auftrag_palette ap join auftrag a on a.id = ap.auftrag_id where a.bemerkung = 'DREHBUCH 02 S1'
```
**Urteil:** _(trägt die Runde ein)_

### S2 Die Auswertung — der Punkt darf nicht plausibel sein
**Wirklichkeit.** Nichts; die Datenbank rechnet.
**Sichtbar heute.** `v_schimmel_punkte`: ein Punkt mit lagertage ≈ −1051, anteil 12/430 ≈ 2.8 %, **plausibel = true**. Er geht in die Kurve, in die Treppe, in die Kaskade.
**Erwartung.** Negative Lagertage sind nie plausibel — `anteil_plausibel` prüft den Anteil, aber niemand prüft das Vorzeichen der Zeit. Der Punkt bleibt in der Sicht (Beobachtung), trägt aber plausibel = false und steht in `v_plausibilitaet` als „Eingangsdatum nach der Arbeit".
**Reparatur (Phase 4).** In `v_schimmel_beobachtung` (und damit in beiden Verarbeitungs-Zweigen von `v_schimmel_punkte`): `plausibel := anteil_plausibel(…) and am.lagertage >= 0`. Dazu eine Zeile in `v_plausibilitaet`. Diese Prüfung ist **rot, bis das geschehen ist** — so muss es sein.

```sql pruefung S2
select not exists (select 1 from v_schimmel_punkte p where p.charge_nr = 9802 and p.lagertage < 0 and p.plausibel) as ok,
       (select min(lagertage) from v_schimmel_punkte where charge_nr = 9802) as kleinste_lagertage,
       (select bool_or(plausibel) from v_schimmel_punkte where charge_nr = 9802 and lagertage < 0) as negativ_und_plausibel
```
**Urteil:** _(trägt die Runde ein)_

### S3 Das Diagramm — die Achse gehört den Messungen, nicht dem Zettel
**Wirklichkeit.** Der Betriebsleiter öffnet Ursachen → Palox: Faules im Lager.
**Sichtbar heute.** x-Achse von −1051 bis 195, alle echten Punkte als Strich rechts.
**Erwartung.** x-Achse ab 0 (Lagertage können nicht negativ sein), Daten füllen die Achse; unter dem Diagramm: „1 Messung ausserhalb (−1051 Tage, Charge 9802) — Eingangsdatum prüfen". Regeln A4 und A5 aus `gegenprobe/bildschirm/achse.ts`; gemessen von `invarianten.mjs` auf der bösen Saison (Phase 3).
**Zwei Schichten, beide nötig.** Die Datenschicht (S2) hält den Punkt aus der Rechnung; die Diagrammschicht hält jeden künftigen Ausreisser aus der Achse — auch einen, den keine Plausibilitätsregel kennt (900 Tage aus dem Vorjahr, 2500 % aus einer falschen Bezugsmasse).

_Keine SQL-Prüfung: diese Szene misst der Bildschirm-Prüfstand._
**Urteil:** _(trägt die Runde ein)_

### S4 Die Korrektur — der Betriebsleiter setzt das Jahr richtig
**Wirklichkeit.** Er sieht die Auffälligkeit, öffnet die Arbeit, ändert das Datum auf 2026.
**In der App.** Messungen → Auffälligkeit → Korrigieren → Datum der Palette → speichern (AB-38: die Beobachtung wird geändert, nicht das Abgeleitete).
**Gespeichert.** `auftrag_palette.eingangsdatum` = Tag −45.
**Sichtbar.** Der Punkt liegt bei 44 Lagertagen, plausibel, in der Kurve; die Auffälligkeit ist weg.

```sql szene S4
update auftrag_palette set eingangsdatum = heute() - 45
 where auftrag_id = (select id from auftrag where bemerkung = 'DREHBUCH 02 S1');
select auswertung_aktualisieren();
```
```sql pruefung S4
select p.lagertage = 44 and p.plausibel as ok, p.lagertage, round(p.anteil, 4) as anteil
  from v_schimmel_punkte p join auftrag a on a.id = p.auftrag_id where a.bemerkung = 'DREHBUCH 02 S1'
```
**Urteil:** _(trägt die Runde ein)_
