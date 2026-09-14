# Befund Runde Q — die Erfassung ist scharf

Stand: 14.09.2026. Der Auftrag aus `docs/PROMPT_RUNDE_Q.md` ist durchgearbeitet.
Was hier nicht steht, ist nicht gebaut — und was verschoben wurde, steht mit
Grund in Abschnitt 9.

Diese Runde hat einen anderen Charakter als alle vorherigen: Danach wird an der
**Erfassung** nichts mehr geändert. Die Auswertung darf weiterlernen; was in
der Halle nicht gemessen wurde, ist für diese Saison weg.

---

## 1. Grundlinie (Phase 0)

Alles war vorher grün:

| Prüfstand | Ergebnis vorher |
|---|---|
| `npm run pruefen` | typecheck, 96 Tests, Build — grün |
| `supabase/test/run.sh` | alle sieben Stufen bestanden |
| `npm run gegenprobe --db demo` | 52 Fälle, 52 bestanden |
| `pruefstand/bildschirme.mjs` | 188 Aufnahmen, keine Konsolenfehler |

Die Bilder „vorher" liegen lokal in `pruefstand/bilder_vorher_q` (62 MB, nicht
eingecheckt — der Vergleich steht als Text in Abschnitt 8).

---

## 2. Rot zuerst (Phase 1)

Prüfblock **0072** in `supabase/test/pruefung.sql`, geschrieben **vor** jeder
Änderung am Produktivcode, auf einer frischen Datenbank mit 0000–0071:

```
psql:supabase/test/pruefung.sql:4282: ERROR:  0072 (a1): 2 Ablesung(en)
rechnen gegen eine fremde Arbeit — Ablesung 625 (Arbeit 1320): vorher
310.00 statt ; Ablesung 21 (Arbeit 2100): vorher 165.00 statt
```

Rot aus dem richtigen Grund. Der volle Wortlaut steht in
`docs/rot_runde_q/0072_rot.txt`.

**Bemerkenswert:** Die Prüfung fängt nicht nur die zwei Arbeiten, die sie
selbst anlegt, sondern auch **Arbeit 2100 aus dem bestehenden Prüfdatensatz**.
Der Fehler ist keine Konstruktion — er steckt in Daten, die seit Runden dort
liegen und bei jedem Lauf mitgerechnet wurden.

---

## 3. Die zwei Funde, die den Aufwand gerechtfertigt haben

### 3.1 Der Palox rechnete über die Arbeitsgrenze — an zwei Stellen

Gemeldet war eine: „wenn ich bei sortieren palox zu beginn ablese rechnet es
minus 445? warum - es sind 45 kg". Die erste Ablesung einer Arbeit wurde als
Menge verbucht, obwohl sie nur der Stand ist, bei dem die Arbeit beginnt.

Beim Suchen fand sich derselbe Denkfehler ein zweites Mal, und dort war er
gefährlicher. `v_palox_stand` bildete das Fenster über die **Station**, nicht
über die Arbeit:

| Fall | vorher | warum das schlimm ist |
|---|---|---|
| Startstand **fällt** gegenüber der letzten Arbeit | Arbeit fiel aus der Rechnung | zufällig richtig |
| Startstand **steigt** | Differenz zur letzten Arbeit derselben Station wurde dieser Arbeit als Faules gebucht | **fremde Kilo, still, ohne Befund** |

Die Regel des Betriebs stand längst da — „arbeitsschritte werden nie über nacht
pausiert … deswegen soll nie von der letzten arbeit der palox wert irgendwie
übernommen werden" — nur nicht in der Sicht.

**Was daraus wurde:** Die erste Ablesung ist ein Startstand und ergibt 0 kg.
Zwei Ablesungen sind Pflicht; mit einer einzigen hat die Arbeit **keine**
Faul-Menge statt einer erfundenen. Fällt der Stand, fragt die Maske
(„Ja, geleert" / „Nein, vertippt"), statt stillschweigend `kg: 0` zu schreiben.

**Wirkung auf die Beispieldaten** — ausdrücklich eine Aussage über die Demo,
nicht über den Betrieb:

| | Arbeiten mit Faul-Menge | Summe |
|---|---|---|
| vorher | 132 | 10 705 kg |
| nachher | 128 | 8 159 kg |
| in den Demodaten erzeugt | — | 13 549 kg |

Die Differenz sind Arbeiten ohne Startablesung. Sie sind jetzt ehrlich
*unbekannt* statt falsch beziffert.

### 3.2 Die Beinahe-Falle: eine Kistenzahl, die 289 Zeilen verschwinden liess

`v_auftrag_palette_masse` endete mit `where ap.kisten is null`. Gemeint war
eine Abgrenzung gegen die Wasch-Paletten; sie hing nur an der falschen Spalte.
Sobald die Wäge-Maske die Kistenzahl auf die **Eingangs**palette schreibt —
genau das, was diese Runde bringt —, fällt jede solche Palette aus der Sicht.

Im Versuch nachgemessen (`update` + `refresh materialized view
mv_auftrag_masse`):

```
vorher:   289 Zeilen in v_auftrag_palette_masse
nachher:    0 Zeilen
Folge:     31 Sortierarbeiten mit n_paletten = 0 und Masse NULL
```

Kein Fehler, keine Warnung — die Masse wäre einfach weg gewesen. **0074**
grenzt jetzt nach der Station ab (`not (station = 'waschen' and not ist_fax)`),
nicht nach einer Spalte, die sich füllen darf.

Das ist die Sorte Fehler, gegen die diese Runde gebaut wurde: nicht der falsch
gerechnete Wert, sondern der stumme Ausfall.

---

## 4. Was gebaut ist

### Fünf Migrationen

| Nr | Was |
|---|---|
| **0072** | Das Schema: `auftrag.palox_unbekannt`, `auftrag.fertige_paletten_gesamt`, `auftrag_palette.gebindeart`, `ausgang_wiegung.voll`, `charge.ernte_abgeschlossen_ts`, die Tabellen `kontrollpalette` / `kontrollpalette_wiegung` / `erfassung_journal`, die Funktion `palox_stand_dieser_arbeit()`, der Journal-Auslöser über 17 Tabellen, der Demo-Schutz `demo_nur_im_beispielmodus()`, neun Einstellungen (u. a. `kisten_pro_palette` 36, `betriebsmodus` `echt`, `gebinde_lager` G2, `fax_tage_vorgabe` 4) |
| **0073** | Das Rechenwerk: `v_palox_stand` je Arbeit, `v_schimmel_menge` verlangt zwei Ablesungen, `v_auftrag_masse` + `alter_quelle` / `alter_spanne_tage` / `ernte_fertig`, `v_charge_erntespanne`, `v_kontrollpalette_rate`, `v_kontrollpalette_vorschlag`, `v_ausgang_voll`, `v_koeff_palette_netto` ohne halbvolle Paletten |
| **0074** | Die Beinahe-Falle aus 3.2 |
| **0075** | `v_verderb_lage`: je Sorte, worauf die gemeinsame Verderbskurve dort ruht. Baut die Schrumpfung ausdrücklich **nicht** (Abschnitt 9) |
| **0076** | `v_datenqualitaet` + drei Zähler (Kistenzahl auf der Eingangspalette, abgelesenes Alter) und die neu gebaute gespeicherte Fassung |

### Die Arbeiter-App

| Maske | Was sich ändert |
|---|---|
| **Palox** | Erste Ablesung heisst „Startstand" und zeigt keine Menge. Gefallener Stand fragt nach. Das Leergewicht steht nur noch als Hinweistext — es kürzt sich in der Differenz heraus |
| **Zähler, Sortieren / Waschen + Sortieren** | Kistenzahl und Gebindeart je Eingangspalette; beide bleiben stehen und sind mit 36 / G2 vorbelegt. Der Reiter „Kisten je Kaliber" ist weg |
| **Zähler, Waschen** | Gebindeart je Kaliber-Palette (sie wechselt mitten in der Arbeit) |
| **Palette wiegen** | Schreibt Kistenzahl und Gebindeart auf die Eingangspalette — damit ist der Weg über die Wägung nicht mehr die Lücke, durch die die Angabe verlorenging |
| **Fertige Palette** | Haken „Palette ist nicht voll": zählt für die Masse, nicht für kg je Kiste. Kürbisse je Kiste beim Stücksystem Pflicht, sonst freiwillig |
| **Abschluss** | Blockiert ohne zweite Palox-Ablesung; fragt „Palox geleert?"; nimmt die Zahl der fertigen Paletten gesamt; belegt die Fax-Tage aus der letzten Wascharbeit derselben Charge vor |
| **Kontrolle** | Zweiter Weg „Kontrollpalette": dieselbe Palette anlegen, wiederfinden, wiegen — mit der letzten Wägung vor Augen |
| **Start / Arbeit** | Schichtwechsel: Liste hält sich frisch, „Mitmachen" scheitert nicht mehr am doppelten Eintrag, „Ich bin nicht mehr dabei", Rolle je Person statt je Gerät |

### Der Betriebsleiter

* **Stammdaten → Chargen:** Haken „Die Ernte ist eingebracht" (Q9).
* **Messungen → Wie vollständig wird erfasst?** zwei neue Zeilen:
  Kistenzahl auf der Eingangspalette, Alter vom Zettel abgelesen.
* **Ursachen → Faules im Lager:** Fussnote unter der Kurve, welche Punkte ein
  abgelesenes und welche ein geschätztes Alter haben.
* **Betrieb → Arbeiten:** Erinnerung an die Sicherung.
* **Stammdaten → Demo-Daten:** im Echtmodus nur noch der Hinweis, keine Knöpfe.

### Der Schutz der Erfassung

1. **`erfassung_journal`** — jede Änderung an einer von 17 Erfassungstabellen
   mit Vorher, Nachher, Person und Zeit. Eine gelöschte Messung ist damit
   gelöscht *und* aufgehoben.
2. **`supabase/test/keine_zerstoerung.sh`** — liest jede Migration, bevor sie
   läuft, und weist `drop table`, `drop column`, `truncate` und `delete` ohne
   `where` ab. Drei begründete Altfälle stehen namentlich auf der
   Ausnahmeliste. Läuft als **erste** Stufe von `run.sh`.
3. **Zwei Datenbanken** — echt und Beispiel getrennt; welche vorliegt, sagt
   `einstellung.betriebsmodus`, nicht der Build. Im Echtmodus weist ein
   Auslöser das Anlegen von Demodaten ab, auch von Hand im SQL-Editor.

---

## 5. Bestehende Prüfungen, die rot wurden — und warum

Keine davon wurde abgeschwächt.

| Prüfung | Warum rot | Was geschah |
|---|---|---|
| „Schimmel #2 erzeugt 0 Punkte statt 1" | Der Testfall hatte **eine** Ablesung; die neue Regel verlangt zwei | Die **Testdaten** bekamen eine zweite Ablesung. Die Behauptung blieb, wie sie war |
| Palox-Block je Station | Die Prüfung kodierte die alte Regel („Waschstrasse gemeinsam") und brach mit „more than one row returned by a subquery" | Der Block ist für die neue Regel neu geschrieben — jede Behauptung, deren Absicht die Regel überlebt, steht weiter da |
| „Diese Funktionen stehen jedem offen" | Die neuen Auslöserfunktionen hatten PUBLIC-Rechte | `revoke all from public`, `grant execute to authenticated` |
| Bildschirm-Prüfstand | Der Demo-Schutz weist Beispieldaten im Echtmodus ab — und der Prüfstand lädt genau die | Richtiges Verhalten. Der Prüfstand läuft jetzt im Beispielmodus, und eine neue Prüfung hält fest, dass der Schutz im Echtmodus greift |
| Fingerabdruck Migrationen ↔ setup.sql (zweimal) | `v_datenqualitaet` enthält `select a.*`, und Postgres friert den Stern beim Anlegen ein. 0073 hat die Sicht deshalb neu angelegt; 0076 musste zusätzlich die **gespeicherte** Fassung `erg_datenqualitaet` neu bauen, weil dort derselbe Stern steckt | `create or replace view` (0073) und ein `do`-Block mit Verdichter-Marke (0076). Der zweite Anlauf war nötig, weil der Verdichter ein einzelnes `drop` nach Teil A und das `create` nach Teil B sortiert — im `do`-Block bleiben sie zusammen |
| Lückenscanner | `auftrag.fertige_paletten_gesamt` war in der Datenbank und in keiner Maske | Das Feld steht jetzt im Abschluss |
| Lasttest „Auswertung neu rechnen" | 12 049 ms gegen eine Grenze von 12 000 ms | Nicht die Grenze wurde verschoben: `v_charge_erntespanne` schlug je Palette in einer Sicht nach (`cross join lateral`). Direkt verknüpft statt fünftausendmal nachgeschlagen → 11 893 ms |

---

## 6. Die drei Fehler im Warenausgang-Import

Beim Lesen des Importwegs gefunden, alle drei nachgemessen und behoben:

| | Was war | Folge |
|---|---|---|
| **D1** | Die Meldung nach dem Import behauptete eine Zahl, die sie nicht kannte | Sagt jetzt, was sie weiss |
| **D2** | `extern_id` enthielt Kistenzahl und Gebinde. Eine korrigierte Zeile bekam damit eine neue Kennung | Dieselbe Palette wurde ein zweites Mal importiert. Der Kern ist jetzt `chargeNr\|datum\|brutto` |
| **D3** | Der `upsert` schrieb `null` über gemessene Werte, wenn die neue Zeile das Feld nicht hatte | Nullen werden vor dem Schreiben entfernt — „leer ist nicht null" gilt auch beim Import |

---

## 7. Q17: was die Änderungen an Handgriffen kosten

Gezählt sind Eingabefelder und Knopfdrücke in den Masken, nicht gestoppte
Zeiten. Im Dauerbetrieb („die zwanzigste Palette derselben Arbeit") bleiben
Datum, Kistenzahl und Gebinde stehen:

| Tätigkeit | vorher | nachher |
|---|---|---|
| Sortieren, je Eingangspalette | Brutto tippen + „+" = **2** | Brutto tippen + „+" = **2** (Kisten und Gebinde kleben, vorbelegt 36 / G2) |
| Waschen, je Kaliber-Palette | „+" = **1** | „+" = **1** (Gebinde klebt) |
| Waschen, Kisten je Kaliber | **1 Tipp je Kiste** — bei 120 Kisten 120 Tipps | **0** — der Reiter ist weg |
| Fertige Palette wiegen | Brutto, Kisten, Art, Eintragen = **4** | dieselben **4**; der Haken „nicht voll" nur bei der letzten |
| Palox je Ablesung | Zahl + Eintragen = **2** | dieselben **2**; bei gefallenem Stand eine Rückfrage mehr |
| Schichtwechsel: dazukommen | Karte antippen + Mitmachen = **2** | dieselben **2**, aber ohne rote Meldung bei einem zweiten Gerät |
| Schichtwechsel: gehen | *nicht möglich* | „Ich bin nicht mehr dabei" + bestätigen = **2** |

Unterm Strich: Die einzige Stelle mit grossen Zahlen war der Kaliber-Reiter,
und der ist weg — er hat eine Messung vorgetäuscht, die nie stattfand. Alles
Neue kostet einen Griff **je Arbeit**, nicht je Palette.

---

## 8. Stand der Prüfstände

| Prüfstand | Ergebnis |
|---|---|
| `supabase/test/run.sh` | alle Stufen bestanden |
| `npm run pruefen` (tsc, Tests, Build) | typecheck grün, **102 Tests**, Build grün |
| `npm run gegenprobe -- --db demo` | **52 Fälle, 52 bestanden** |
| `pruefstand/bildschirme.mjs` | 188 Aufnahmen, keine Konsolenfehler — dazu zwei **neue** Ansichten im Prüfstand: `kontrolle-palette` und `betrieb-chargen` |
| `supabase/test/keine_zerstoerung.sh` | neu, läuft als erste Stufe (77 Migrationen, 3 begründete Altfälle) |
| `test/kontrollpalette.test.ts` | neu, 6 Fälle |

Der Bildschirmvergleich vorher ↔ nachher: 188 Ansichten, gleich viele wie
vorher, keine neuen Konsolenfehler. Zwei Ansichten sind neu in den Prüfstand
gekommen, weil es sie vorher nicht gab: **`kontrolle-palette`** (der zweite Weg
auf dem Kontroll-Bildschirm) und **`betrieb-chargen`** (der Haken „Die Ernte ist
eingebracht"). Beide rendern auf Handy und Bildschirm, hell und dunkel, ohne
Konsolenfehler.

Vier Datenquellen haben in der Demo noch keinen Inhalt (`v_ausgang_voll`,
`kontrollpalette`, `kontrollpalette_wiegung`, `v_kontrollpalette_vorschlag`) —
die Masken stehen, die Listen sind leer und sagen das auch („Noch keine
Kontrollpalette angelegt"). Echte Zeilen entstehen ab der ersten Kontrolle in
der Halle; das steht in Abschnitt 9.

---

## 9. Was ausdrücklich verschoben ist

**Nicht vergessen, sondern später — mit Grund.**

| Was | Warum jetzt nicht |
|---|---|
| **Die Schrumpfung des Verderbs je Sorte** (● ◐ ○) | Der einzige offene Punkt, der die **Kaskade** bewegt; alles andere dieser Runde sind Masken. Zusammen geändert wüsste nachher niemand, welches von beidem eine Abweichung verursacht hat. Und solange es nur **eine** Kurve für alles gibt, wäre ein ◐ ein Zeichen, das lügt — deshalb steht überall ○. Erster Akt der nächsten Runde: die Prüfung, dass die Schrumpfung bei null eigenen Messpunkten auf den Rappen dieselben Zahlen liefert wie heute |
| **`alter_spanne_tage` als Fehlerbalken in der Verderbskurve** | Dafür müssten die einzelnen Punkte ihre Altersquelle mitführen; `v_schimmel_punkte` tut das nicht, und sie umzubauen heisst die Kaskade anfassen. Bis dahin sagt eine **Fussnote** unter der Kurve, welche Punkte abgelesen und welche geschätzt sind, und Messungen zeigt, wie oft welches zutrifft |
| **Beispieldaten für die Kontrollpalette** | Die Demo-Saison kennt sie noch nicht; die Masken sind darum in den Aufnahmen leer. Echte Daten entstehen ab der ersten Kontrolle in der Halle — die Demo nachzurüsten ändert nichts an der Erfassung |
| **AB-14, die direkte Messung beim Leeren des Palox** | Offene Frage an den Betrieb (`FRAGEN.md`). Entscheidet, ob der nicht lagerbedingte Sockel am Saisonende erkennbar wird |

Dazu die **fünf Dinge, die der Auftrag selbst verschoben hat** (Lager-Management
je Kaliber, Kalibermigration, Überfüllung in Franken, FIFO statt proportionaler
Entnahme, die Verdunstungskurve statt einer festen Rate). Keine Entscheidung
dieser Runde macht eines davon später unmöglich — im Gegenteil:

| Verschoben | Was diese Runde dafür gelegt hat |
|---|---|
| Lager-Management je Kaliber | Die Eingangspalette trägt Kistenzahl und Gebindeart; damit gibt es zum ersten Mal eine Masse je Kaliberband aus gemessenen Grössen (0074, 0076) |
| Kalibermigration | `v_kontrollpalette_rate` misst die Verdunstung **über die Zeit** an derselben Palette — die Voraussetzung dafür, dass „rutscht unter die Bandkante" mehr als eine Vermutung wird |
| Überfüllung in Franken | „Nicht volle" Paletten zählen nicht mehr in kg je Kiste; der Koeffizient, an dem die Marge hängt, ist damit sauber (0073) |
| FIFO statt proportionaler Entnahme | `alter_quelle` und `alter_spanne_tage` trennen gemessenes von geschätztem Alter — ohne diese Trennung wäre nicht prüfbar, ob FIFO die Zahlen verbessert oder nur verschiebt |
| Verdunstungskurve statt fester Rate | Die Kontrollpalette ist die Datenquelle dafür; die ersten Messpunkte entstehen ab der ersten Kontrolle in der Halle |

---

## 10. Der Abschlusslauf


| Was | Ergebnis |
|---|---|
| `supabase/test/keine_zerstoerung.sh` | keine zerstörende Anweisung ausserhalb der Ausnahmeliste |
| `setup.sql` als **ein** Query im Editor | keine Meldung ausser der Fertig-Zeile; **683 KB** von 1000 KB |
| Fingerabdruck Migrationen ↔ setup.sql | **3019 Objekte auf beiden Wegen, kein Unterschied** |
| Aktualisierung von einem alten Stand | Daten erhalten, Auswertung rufbar, Schema wie frisch eingerichtet |
| Demo-Daten wie im SQL-Editor | 844 Paletten, 48 Arbeiten, Fax, Lieferungen, Sonderfälle |
| Tempo der Auswertung | Schritte 333 / 2102 / 949 / 1711 / 403 ms; Dashboard **32.5 ms** |
| Lasttest (5040 Paletten, 840 Arbeiten, 255 300 Gewichtsstufen) | Auswertung neu rechnen **11 558 ms** (Grenze 12 000); Dashboard unter Last **34.3 ms** |
| `npm test` | **102 Fälle, 102 bestanden** |
| `npm run gegenprobe -- --db demo` | **52 Fälle, 52 bestanden** |
| `pruefstand/bildschirme.mjs` | 188 Aufnahmen, keine Konsolenfehler; dazu die zwei neu aufgenommenen Ansichten `kontrolle-palette` und `betrieb-chargen` mit je 4 Aufnahmen, ebenfalls ohne Konsolenfehler |
| Lückenscanner | keine Lücke zwischen Maske und Auswertung |
| `node docs/pdf_bauen.mjs` | `Die-Arbeiter-App.pdf`, 23 Seiten (20 + der Nachtrag) |

```
——— alle Prüfungen bestanden ———
```

Der Lasttest lief vor der Behebung aus Abschnitt 5 auf 12 049 ms und damit über
die Grenze. Die Grenze wurde nicht verschoben; die Sicht wurde schneller.

---

## 11. Was der Betrieb als Erstes sehen wird

1. **Der Palox zeigt „Startstand"** statt einer Menge, wenn er zu Beginn
   abgelesen wird. Das ist die gemeldete Zahl, und sie ist weg.
2. **Der Kaliber-Reiter im Zähler ist verschwunden.** Das ist Absicht.
3. **Beim Zählen einer Eingangspalette stehen zwei Felder mehr** — Kistenzahl
   und Kistenart —, beide vorbelegt und beide bleiben stehen. Im Dauerbetrieb
   kostet das keinen zusätzlichen Griff.
4. **Der Abschluss geht nicht weiter ohne zweite Palox-Ablesung.** Das ist der
   Preis dafür, dass keine Arbeit mehr fremde Kilo bekommt.
5. **Auf dem Kontroll-Bildschirm steht ein zweiter Weg:** die Kontrollpalette.
6. **Auf der Betriebsseite steht eine Erinnerung an die Sicherung.**
7. **Auf der Beispiel-Webseite lassen sich Demo-Daten laden, auf der echten
   nicht** — dort steht statt der Knöpfe ein Hinweis.

---

## 12. Was jetzt zu tun ist, bevor die erste echte Palette gezählt wird

1. `supabase/setup.sql` in **beide** Projekte einspielen (echt und Beispiel).
2. Im Echt-Projekt prüfen, dass `einstellung.betriebsmodus` auf `echt` steht
   (Vorgabe), im Beispiel-Projekt auf `beispiel` setzen.
3. Die App **zweimal** veröffentlichen, je Projekt einmal — `VITE_SUPABASE_URL`
   und `VITE_SUPABASE_ANON_KEY` werden beim Bauen eingebacken. Der Weg steht im
   README unter „Zwei Webseiten".
4. Die Leergewichte der Gebinde prüfen (Betrieb → Stammdaten → Gebinde). Ohne
   sie hat keine Palette ein Netto — „leer ist nicht null".
5. Falls 32 statt 36 Kisten je Palette gelten: Einstellung
   `kisten_pro_palette` anpassen.
6. Den QR-Code mit der **Echt**-Adresse in der Halle aufhängen.
