« # Betriebsfragen-Karte — Runde M, Vorarbeit für Werkstatt D

**Stand:** 9. September 2026 · Datenbank `karte_fragen` (Kopie von `demo`, Schema 66) ·
Oberfläche gerendert aus dem Arbeitsstand des Zweigs `claude/new-session-vrnnyo`.

Diese Karte stellt zwei Listen nebeneinander — die **Entscheidungen**, die der Betrieb
im November trifft, und die **Zahlen**, die das Programm zeigt — und misst, wo eine
Verbindung besteht, wo sie fehlt und wo sie nur scheinbar besteht.

---

## 0. Wie gemessen wurde — jeder Befehl nachvollziehbar

| Werkzeug | Befehl | Was es liefert |
|---|---|---|
| Eigene Datenbankkopie | `psql -d postgres -c "create database karte_fragen template demo"` | unveränderter Stand 66 mit Demodaten |
| Zahlen-Ernte (eigener Aufbau) | `node <scratch>/kf_run/kf_ernte2.mjs` — Kopie von `pruefstand/beschriftung.mjs`, die statt der sechs Regeln **jede** geerntete Zahl mit Ansicht, Karte, Beschriftung und Einheit nach `kf_zahlen.json` schreibt; Wartezeit je Seite von 900 ms auf 3500 ms erhöht | 2 663 Zahlen über zwölf Ansichten |
| Begriffs-Ernte des Bestands | `ERNTE=1 node pruefstand/beschriftung.mjs` → `pruefstand/begriffe_gefunden.txt` | 42 verschiedene Beschriftungen an Massezahlen |
| Trennbarkeit der Vergleiche | `psql -f <scratch>/kf_paare.sql`, `kf_anteil.sql`, `kf_rang.sql`, `kf_rang2.sql`, `kf_bild.sql` | Paarweise Bandüberschneidung je Gruppenart |
| Ströme und Bänder | `psql -c "select … from v_verlust_je_gruppe where gruppe='gesamt'"` | sechs Ströme mit `kg_unten`/`kg_oben` |
| Erfassungsdichte | `select * from v_datenqualitaet`, `v_datenlage`, `v_fax_beobachtung` | Zähler je Absprache |
| Quelltext | `grep -rn … src/ supabase/migrations/` | Leser und Nichtleser einer Spalte |

Alle Kilo-Zahlen unten stammen aus der **lebenden** Kopie `karte_fragen` (Stichtag
09.09.). Die Bildschirmzahlen stammen aus den Attrappen-Fixtures unter
`pruefstand/daten/`, die einen Tag älter sind (Stichtag 08.09., Verlust 53,7 t statt
52,1 t). Wo beides vorkommt, steht die Quelle dabei.

---

## 1. Der Bestand in einem Bild

| | |
|---|---|
| Eingang | **323 268 kg** in 36 Chargen mit Eingang (42 Chargen angelegt), 844 Paletten |
| Ausgeliefert | **115 836 kg**, 187 Lieferungen (davon 5 000 kg Vorlauf ohne Lieferschein) |
| Verlust bis heute | **52 119 kg** = 16,1 % des Eingangs, Bereich **30 517 – 76 184 kg** (9,4 % – 23,6 %) |
| Noch im Haus | **154 545 kg**, davon verkaufsfähig 144 989 kg |
| Anderer Kanal, ausgelagert | 4 947 kg |
| Überzählung (mehr geliefert als eingelagert) | 4 180 kg |
| Bilanzrest | −0,01 kg |
| Ansichten des Betriebsleiters | 5 Routen (`/dashboard`, `/ursachen`, `/chargen`, `/messungen`, `/betrieb/:teil`), Betrieb mit 6 Unterreitern → **10 Bildschirme** |
| Zahlen darauf | **2 663**, davon 2 017 kg · 82 t · 470 % · 60 Tage · 34 Stück |

Das Verhältnis, an dem die ganze Runde hängt: der Verlust ist auf einen **Faktor 2,5**
genau bekannt (76 184 ÷ 30 517). Jede Entscheidung, die einen Unterschied kleiner als
diesen Faktor braucht, ist aus diesen Zahlen nicht zu treffen.

---

## 2. Links: die Entscheidungen des Betriebs

Formuliert als Entscheidung, nicht als Neugier. Quellen: `docs/FRAGEN.md` (52 Fragen),
`docs/ABLAUF.md`, `docs/UI-KONZEPT.md`, `docs/SPEC.md` — dazu, was ein Kürbisproduzent
im November tut, der 323 t eingelagert hat.

### 2.1 Diese Woche (Betriebsführung)

| Nr | Entscheidung | Woher |
|---|---|---|
| **E1** | Welche Charge kommt als nächstes dran — soll ich X vor Y verarbeiten? | ABLAUF „Wer entscheidet, was als nächstes drankommt"; UI-KONZEPT Reiter Chargen |
| **E2** | Soll ich einen Bestand jetzt zum tieferen Preis verkaufen oder liegen lassen? | folgt aus E1; SPEC §0 („Ursachen rangieren") |
| **E3** | Soll ich heute mehr Ware waschen als bestellt ist, um sie aus dem Lager zu bekommen? | ABLAUF, zweiter Lagerabschnitt |
| **E4** | Lohnt es, den Fax näher ans Waschen zu legen (heute 1–3 Tage danach)? | ABLAUF „Fax", FRAGEN 48 |
| **E5** | Muss ich eine bestimmte Charge aufmachen und durchsehen, weil sie zu kippen droht? | ABLAUF, Verderbskurve |

### 2.2 Diese Saison (Anlage und Aufwand)

| Nr | Entscheidung | Woher |
|---|---|---|
| **E6** | Soll ich die Luftfeuchte/Temperatur in der Halle ändern? | FRAGEN 42, ABLAUF („temperiert, mit Klimacomputer") |
| **E7** | Soll ich die Lagerdauer grundsätzlich verkürzen (früher verkaufen, weniger einlagern)? | FRAGEN 48 |
| **E8** | Soll ich beim Waschen strenger oder lockerer aussortieren? | ABLAUF, Palox |
| **E9** | Soll ich eine Waage ans Kistenfüllen stellen? | FRAGEN 20, 50 |
| **E10** | Soll ich das Kaliberband beim Abnehmer enger verhandeln? | SPEC §3, Überblick-Karte „Wie gross sind die Kürbisse?" |
| **E11** | Soll ich mehr messen — und wovon? Wo zahlt sich Arbeiterzeit aus? | PROMPT_RUNDE_M D4 |
| **E12** | Soll ich eine Messung streichen, weil sie nichts entscheidet? | dito |
| **E13** | Soll ich das Sortierdatum wirklich auf jede Kiste schreiben lassen? | FRAGEN 18 (zugesagt) |

### 2.3 Nächstes Jahr (Anbau und Verträge)

| Nr | Entscheidung | Woher |
|---|---|---|
| **E14** | Welche Sorte baue ich mehr an, welche weniger? | UI-KONZEPT Überblick „je Sorte" |
| **E15** | Mit welchem Schlag/Bewirtschafter arbeite ich weiter? | SPEC §1, Überblick „je Schlag" |
| **E16** | Soll ich früher oder später ernten (Kaliberschwerpunkt)? | ABLAUF „Gewichtsverteilung … nach Schlag" |
| **E17** | Ist dieses Jahr besser oder schlechter als letztes? | eigener Verstand; jeder Betriebsvergleich |
| **E18** | Lohnt sich ein Abnehmer für „zu gross"? | FRAGEN 36 |
| **E19** | Lohnt sich ein Kanal für „zu klein" jenseits Tierfutter? | FRAGEN 35 |

### 2.4 Die Zahl, die im Gespräch genannt wird

| Nr | Entscheidung | Woher |
|---|---|---|
| **E20** | Welche Prozentzahl nenne ich, wenn mich jemand nach meinem Lagerverlust fragt? | FRAGEN 51 (offen) |
| **E21** | Rangiere ich die Ursachen in Kilo oder in Franken? | FRAGEN 49 (offen) |
| **E22** | Glaube ich dem Unterschied zwischen zwei Zahlen, die nebeneinanderstehen? | PROMPT_RUNDE_M D2 |

### 2.5 Erfassung und Vertrauen

| Nr | Entscheidung | Woher |
|---|---|---|
| **E23** | Muss ich in der Halle nachhaken, weil eine Absprache nicht eingehalten wird? | Messungen → „Wie vollständig wird erfasst?" |
| **E24** | Muss ich eine Messung korrigieren, die falsch aussieht? | AB-38, AB-42 |
| **E25** | Darf ich der Zahl „noch im Haus" trauen, wenn ich Ware für einen Kunden zusagen will? | UI-KONZEPT Überblick |
| **E26** | Ist eine Charge schon aufgebraucht, obwohl die Lieferungen mehr verlangen? | Überzählung, 0064 |
| **E27** | Wird bei uns nach Aussehen ausgewählt (und ist damit die ganze Kurve zu flach)? | ABLAUF „die grösste verbliebene Fehlerquelle" |
| **E28** | Wird zwischen Eingang und Wägung umgestapelt? | FRAGEN 52 (offen) |
| **E29** | Gilt die 8-kg-Kiste nur für eine Sorte? | FRAGEN 2 (offen) |
| **E30** | Welche Abgänge neben dem Lieferschein gibt es, und wie gross sind sie? | FRAGEN 45 (offen) |

**Messung zu den Quellen:** In `docs/FRAGEN.md` selbst tragen **4 von 52** Fragen (9, 18,
25, 49) eine eingetragene Antwort; die übrigen 48 verweisen auf `ABLAUF.md` oder sind
offen (`python3` über die Blockstruktur der Datei). *Gegenrede:* Der Kopf der Datei sagt
ausdrücklich, dass beantwortete Fragen als Tatsache nach `ABLAUF.md` wandern — die 48
sind also nicht 48 offene Fragen. Der Kopf selbst nennt **elf** noch offene Stränge
(Preise, Massnahmen je Ergebnis, übrige Abgänge, Perigon-Vorlage, Fragen 2, 5, 51, 52
und die zweiten Hälften von 1, 14, 25). Der Befund bleibt trotzdem stehen: **wer nur
`FRAGEN.md` liest, kann nicht erkennen, welche Frage beantwortet ist.**

---

## 3. Rechts: was das Programm zeigt

### 3.1 Die Ernte

`node kf_ernte2.mjs` → `kf_zahlen.json`:

| Ansicht | Zahlen | Anmerkung |
|---|---:|---|
| `ueberblick` (gesamt) | 70 | vier Kopfzahlen, Balken „Alle Chargen", Kaliber-Kurztabelle |
| `ueberblick-sorte` | 88 | zehn Balkenzeilen |
| `ueberblick-charge` | 248 | 36 Balkenzeilen |
| `ueberblick-imhaus` | 70 | aufgeklappte Tabelle, 9 Sorten × 6 Spalten |
| `ursachen` | 310 | fünf Ursachenblöcke mit Tabellen |
| `ursachen-aufgeklappt` | 310 | identisch — das Aufklappen bringt keine neue Zahl |
| `chargen` | 189 | 36 Zeilen × 6 Zahlenspalten |
| `chargen-offen` | 235 | eine aufgeklappte Charge: Eingangstage, Lieferungen, Arbeiten |
| `messungen` | 377 | grösste Zahlendichte aller Ansichten |
| `messungen-aufgeklappt` | 377 | identisch |
| `betrieb-arbeiten` | 200 | 196 davon sind „Bewegte Masse" je Arbeit |
| `betrieb-lieferungen` | 189 | 177 davon „Angabe auf dem Lieferschein" |
| **Summe** | **2 663** | 109 verschiedene Beschriftungen, 266 verschiedene (Ansicht · Karte · Beschriftung) |

Nicht mitgezählt: alles, was nur im Schwebefenster einer Grafik steht (Verlauf, Glocke,
Verdunstungskurve, Anteilsbalken-Segmente). Das ist eine Untergrenze.

### 3.2 Wie viele dieser Zahlen sagen, wie sicher sie sind

`node -e` über `kf_zahlen.json`, Muster `±` im Wert, `±|Bereich` im Untertitel oder
Spaltenkopf `Bereich`:

| | Zahlen | mit Unsicherheit | Anteil |
|---|---:|---:|---:|
| gesamt | 2 663 | **80** | **3,0 %** |
| `ursachen` | 310 | 33 | 10,6 % |
| `betrieb-lieferungen` | 189 | 10 | 5,3 % |
| `ueberblick` (je Ansicht) | 70–248 | 1 | 0,4–1,4 % |
| `chargen` + `chargen-offen` | 424 | **0** | **0 %** |
| `messungen` + `messungen-aufgeklappt` | 754 | **0** | **0 %** |
| `betrieb-arbeiten` | 200 | 0 | 0 % |

Zehn Beschriftungen tragen überhaupt je einen Bereich: *Verlust bis heute · Faules bis
heute · Verdunstet bis heute · Zu klein · Zu gross · Faules beim Abpacken · Bereich je
Tag · Bereich · Verschenkt · Masse der Lieferung.*

Das heisst: **auf den beiden Ansichten, auf denen der Betriebsleiter Chargen
gegeneinander abwägt (Chargen) und dem Modell auf die Finger schaut (Messungen), trägt
keine einzige von 1 178 Zahlen eine Unsicherheit.** Darunter „Verlust bis heute" je
Charge, „Prognose: 14 Tage länger liegen", „Abweichung Modell ↔ CSV", „Gemessener
Anteil ↔ Modell-Anteil".

### 3.3 Das Zahleninventar je Karte (Kurzfassung)

| Ansicht · Karte | Beschriftungen | Anzahl |
|---|---|---:|
| Überblick · Kopfzeile | Eingang · Ausgeliefert · Verlust bis TT.MM. · Noch im Haus | 4 |
| Überblick · „Die Saison im Verlauf" | 4 Linien (nur Schwebefenster) | 0 geerntet |
| Überblick · „Was vom Eingang bis heute fehlt" | je Zeile ein Prozentwert + „N Chargen · X t Eingang" | 1 / 10 / 36 |
| Überblick · „Was ist noch im Haus?" | Eingang · Ausgeliefert · Verlust bis heute · Noch im Haus · davon verkaufsfähig · Liegt seit | 54 |
| Überblick · „Wie gross sind die Kürbisse?" | Anteil der Stück · Gewogene Masse · Stück, je Kaliberklasse | 10 + Glocke |
| Ursachen · Kopf | Eingang · Ausgeliefert · Verlust bis heute · Noch im Haus | 4 |
| Ursachen · Palox | Faules bis heute · Vermutet noch im Lager · (davon nicht lagerbedingt) · Kurve · je Charge: Messungen, Lagertage, Faules im Palox, Gemessener Anteil, Modell-Anteil, Abweichung | 3 + 32×6 |
| Ursachen · Verdunstung | Verdunstet bis heute · Vermutet vom aktuellen Lager · An der ausgelieferten Ware · je Sorte: je Tag, nach 100 Tagen, Bereich je Tag, gewogene Paletten | 3 + 6×4 |
| Ursachen · Sortierung | Zu klein · Zu gross · Durchschnitt der Sorte · je Sorte (4 Spalten) · je Charge (6 Spalten, 15 Zeilen) · Glocke | 2 + 30 + 90 |
| Ursachen · Fax | **eine** Zahl + Fliesstext | 1 |
| Ursachen · Überfüllung | Verschenkt bis heute · Gewogene Paletten · (Nicht gerechnet) · Tabelle „Kiste ab x kg" (7 Spalten) · Tabelle „Stück je Kiste" (8 Spalten) · „Gewogen, aber nicht verkauft" (17 Zeilen) | 3 + 14 + 34 |
| Chargen | 36 Zeilen × Eingang, Ausgeliefert, Verlust bis heute, Noch im Haus, verkaufsfähig, liegt seit, Prognose 14 Tage, Messungen | 189 |
| Chargen aufgeklappt | Paletten · Eingang · Ausgeliefert/dahinter · Verlust · Modell/CSV · Eingangstage · Lieferungen · Arbeiten | +46 |
| Messungen | Auffälligkeiten · 12 Erfassungsbalken · „Wo fehlen Messungen" (20 Zeilen) · Bilanz · Ältestes zuerst · Durchsatz · vier Koeffizienten · Kistengewicht je Kaliber · Verderbsmodell (5 Zeilen) · Kurvenherkunft · Massenbilanz je Charge (36 × 6) · Wägungen (40 × 7) | 377 |
| Betrieb · Arbeiten | Arbeit und Tempo (7 Spalten × Tätigkeit) · Arbeitsliste (200 Zeilen-Zahlen) | 200 |
| Betrieb · Warenausgang | Masse in der Datei · Lieferungen · Masse aller Lieferungen · Zeilentabelle | 189 |

---

## 4. Die Fragenmatrix

Legende: **✓** = beantwortet · **~** = Zahl vorhanden, Entscheidung aber nicht tragfähig
(gemessen in Abschnitt 6) · **✗** = das Programm sagt dazu nichts.

| Nr | Entscheidung | Zahl(en), die sie beantworten | Ort | Urteil |
|---|---|---|---|---|
| E1 | Charge X vor Y? | „Prognose: 14 Tage länger liegen", „liegt seit", „Noch im Haus" | Chargen | **~** korreliert zu 0,9992 mit dem Bestand (§6.4) |
| E2 | jetzt verkaufen oder liegen lassen? | dieselbe Prognose in kg; **kein** Preis | Chargen | **~/✗** ohne Franken keine Abwägung (E21) |
| E3 | mehr waschen als bestellt? | „wartet" (sortiert, noch nicht gewaschen) in `erg_charge.wartet_kg` | nirgends auf dem Bildschirm | **✗** |
| E4 | Fax näher ans Waschen? | `tage_seit_waschen` — in 142 von 161 Arbeiten erfasst | **nirgends** | **✗** (§5.1) |
| E5 | Charge aufmachen und durchsehen? | „Je Charge: gemessen gegen Modell", Abweichung in Punkten | Ursachen → Palox | **~** 1 von 33 Chargen liegt >2 Pkt. über der Kurve, ohne Bereich |
| E6 | Luftfeuchte ändern? | — | — | **✗** 0 Spalten im Schema für Temperatur/Feuchte/Klima |
| E7 | Lagerdauer verkürzen? | Verdunstungskurve `1−(1−r)^t`, Verderbskurve F(t) | Ursachen | **~** konstante Rate ⇒ es gibt keinen „Punkt, ab dem es teuer wird" |
| E8 | strenger/lockerer aussortieren? | Palox-Anteil je Charge; Sockel a₀ | Ursachen, Messungen | **~** a₀ steht auf 0 (Bereich 0–2 463 kg) |
| E9 | Waage ans Kistenfüllen? | „Zu viel je Kiste +0,48 kg", „Verschenkt 1 526 kg", `sd_je_kiste` | Ursachen → Überfüllung | **✓** (Streuung `sd_je_kiste` allerdings nur in der DB, nicht auf dem Schirm) |
| E10 | engeres Kaliberband? | Glocke, Schwerpunkt, Anteil je Klasse, „Gewogen je Stück ↔ Bandmittel" | Überblick, Ursachen | **~** nur für 44 % der Masse (§5.3) |
| E11 | wovon mehr messen? | „Wie vollständig wird erfasst?" (12 Balken), „Wo fehlen Messungen?" (20 Zeilen), Kontrollvorschlag (3 Chargen) | Messungen | **~** sagt, wo **Lücken** sind, nicht, was eine Messung **bringt** |
| E12 | welche Messung streichen? | — | — | **✗** kein Werkzeug |
| E13 | Sortierdatum auf jede Kiste? | „Waschen: Sortierdatum je gezählter Palette 8 918 von 8 918" | Messungen | **✓** (100 % — die Absprache trägt) |
| E14 | welche Sorte mehr anbauen? | Balken „je Sorte" (Anteil), „Was ist noch im Haus" je Sorte (kg), Ausschussanteil je Sorte | Überblick, Ursachen | **~** 8 von 45 Sortenpaaren trennbar (§6.2) |
| E15 | welcher Schlag? | Balken „je Schlag" | Überblick | **~** **2 von 91** Paaren trennbar, Rang 1 von keinem (§6.2) |
| E16 | früher/später ernten? | Gewichtsverteilung je Schlag | **nicht in der Oberfläche** (Spalte `v_gewichtsverteilung.schlag` existiert) | **✗** (§5.4) |
| E17 | dieses Jahr gegen letztes? | `charge.saison` existiert; keine Ansicht vergleicht Saisons | — | **✗** (§5.5) |
| E18 | Abnehmer für „zu gross"? | „Zu gross — Nebenkanal 4 790 kg [1 902–7 678]" | Ursachen | **~** Band 4-fach |
| E19 | anderer Kanal für „zu klein"? | „Zu klein — an die Tiere 7 350 kg [4 926–9 773]" | Ursachen | **~** |
| E20 | welche Prozentzahl nenne ich? | „16,1 % des Eingangs" | Überblick | **~** drei weitere vertretbare Nenner, keiner sichtbar (§5.6) |
| E21 | Kilo oder Franken? | keine Franken-Zahl; `ausgang_zeile.erloes` importiert, **0 Leser** | — | **✗** (§5.7) |
| E22 | darf ich dem Unterschied glauben? | Bereiche an 6 Kennzahlen; sonst nichts | Ursachen | **✗** — genau das misst niemand (§6) |
| E23 | in der Halle nachhaken? | 12 Balken „Wie vollständig wird erfasst?" | Messungen | **✓** — der klarste Treffer der ganzen Karte |
| E24 | Messung korrigieren? | Auffälligkeiten mit „korrigieren", 22 Befunde in 7 Arten | Messungen | **✓** |
| E25 | darf ich „noch im Haus" zusagen? | 154 545 kg, davon verkaufsfähig 144 989 kg | Überblick | **~** ohne Band; der Verlust darin hat ±22 t |
| E26 | Charge schon aufgebraucht? | „Überzählung 4 180 kg", 9 Befunde | Überblick, Messungen | **✓** |
| E27 | wird nach Aussehen ausgewählt? | „Auswahl der gemessenen Paletten: **keine Lagerkontrollen — Selektion nicht prüfbar**" | Messungen | **✗** und widersprüchlich (§5.2) |
| E28 | wird umgestapelt? | Frage 52 offen; Schaden beziffert (≈ 11 % auf der Tagesrate) | `ABLAUF.md`, nicht in der App | **✗** |
| E29 | 8-kg-Kiste nur für eine Sorte? | Überfüllung rechnet sie heute für **zwei** Sorten | Ursachen | **✗** — 301,5 kg von 1 526 kg hängen daran (§5.8) |
| E30 | übrige Abgänge? | `ausgang_ziel` angelegt, „an Tiere und Nebenkanal 2 949 kg" | Überblick | **~** die Ziele existieren, die Mengen sind nicht erfasst |

**Bilanz der Matrix:** von 30 Entscheidungen sind **5 sauber beantwortet** (E9, E13,
E23, E24, E26), **16 halb** (Zahl da, Entscheidung nicht tragfähig) und **9 gar nicht**
(E3, E4, E6, E12, E16, E17, E21, E27, E28 — E29 dazu).

---

## 5. Fragen ohne Antwort — der Betrieb will es wissen, das Programm sagt nichts

### 5.1 Der Hebel, den niemand sieht: Tage zwischen Waschen und Fax

`tage_seit_waschen` wird beim Abschluss jeder Fax-Arbeit gefragt (freiwillig, 0060) und
ist in **142 von 161** Fax-Arbeiten (88 %) gefüllt. Gelesen wird die Spalte von
**keiner Sicht, keiner Seite und keiner Rechnung** — `grep -rn "tage_seit_waschen"
src/ supabase/migrations/` findet nur Schreibstellen (`Abschluss.tsx`, `Korrektur.tsx`,
`typen.ts`) und die Demodaten.

Was in der Spalte steckt (massegewichtet, `v_fax_beobachtung`):

| Tage seit dem Waschen | Arbeiten | Durchsatz | Anteil faul |
|---:|---:|---:|---:|
| 1 | 43 | 23 901 kg | **1,314 %** |
| 2 | 55 | 39 831 kg | 1,880 % |
| 3 | 44 | 44 935 kg | **2,722 %** |
| gesamt | 142 | 123 199 kg | 2,114 % |

**Grösse:** Würde jede Fax-Arbeit einen Tag nach dem Waschen laufen statt im heutigen
Gemisch, fielen **985 kg je Saison** weniger Faules an — **41 % des ganzen
Fax-Stroms** (2 419 kg). Das ist die einzige Massnahme dieser Karte, die (a) in der
Hand des Betriebs liegt, (b) nichts kostet und (c) deren Wirkung schon gemessen ist.
Der Betrieb kann sie heute nicht sehen.

*Gegenrede:* Die Reihenfolge könnte umgekehrt sein — vielleicht lässt man gerade die
schlechtere Ware länger stehen. Dagegen spricht, dass die Bestellung den Fax-Tag
bestimmt, nicht der Zustand. Trotzdem gehört an eine solche Kurve ein Bereich, und die
Frage „liegt es am Stehen oder an der Ware" gehört dem Betrieb gestellt.

### 5.2 Die grösste bekannte Fehlerquelle ist unprüfbar geworden — und die Seite widerspricht sich

`ABLAUF.md` nennt „wer entscheidet, was als nächstes drankommt" ausdrücklich *die
grösste verbliebene Fehlerquelle*. Der Prüfstand dafür ist `v_selektionsverdacht`. Er
sagt heute:

```
n_verarbeitung | 140
n_lager        | (leer)
befund         | keine Lagerkontrollen — Selektion nicht prüfbar
```

Gemessen: `select quelle, count(*) from v_schimmel_punkte group by 1` →
**142 aus `verarbeitung`, 0 aus `lager`.** Der Grund steht in `Kontrolle.tsx`: seit
AB-36 fragt die Kontrolle „davon faul" nicht mehr. Die Spalten `verdunstung_wiegung.faul_kg`
und `.auswahl` existieren noch, sind in **0 von 41** Zeilen gefüllt.

Auf **derselben Seite** (`/messungen`) stehen gleichzeitig:

- „Lagerkontrollen: **24** gewogene Paletten" (Karte *Wie vollständig wird erfasst?*),
- „**keine Lagerkontrollen** — Selektion nicht prüfbar" (Karte *Das Verderbsmodell*),
- und der Rat „Dagegen hilft nur eine Handvoll zufällig gegriffener Lagerpaletten je
  Saison … **Zwölf je Saison genügen**."

Der Betrieb hat 24 gemacht — das Doppelte des Empfohlenen — und bekommt gesagt, es
seien keine, und er solle zwölf machen.

**Grösse:** 24 Wägungen · geschätzt 8 Minuten je Wägung (Stapler, Waage, Tippen) ≈
**3,2 Stunden Arbeiterzeit**, die für die Frage, für die sie empfohlen wurden, nichts
beitragen. Laut `STATISTIK_BEFUND.md` (vierte Runde) ist der Preis nicht die
Erkennungsrate, sondern die Ehrlichkeit des Bereichs: mit Lagerkontrollen enthält das
Band die Wahrheit in **96–100 %** der Saisons, ohne in **0–44 %**. Das trifft den
grössten Strom (Schimmel, 26 170 kg).

*Gegenrede:* AB-36 kam vom Betrieb selbst („die Palette wird gewogen, nicht
ausgepackt"). Die Wägung ohne Faul-Zählung ist für die **Verdunstung** weiterhin voll
wertvoll (24 von 41 Punkten der Kurve). Der Befund ist also nicht „AB-36 war falsch",
sondern: **die App rät weiter zu einer Messung mit einer Wirkung, die sie seit AB-36
nicht mehr hat, und meldet 24 und 0 für dieselbe Sache.**

### 5.3 56 % der Masse hat keine Kaliberverteilung — und niemand sagt es

`select round(sum(eingang_kg) filter (where n_sortierlaeufe=0)) from v_datenlage` →
**180 897 kg = 56,0 %** des Eingangs ohne Sortier-CSV.

| Sorte | Eingang | Anteil | Kürbisse in der CSV |
|---|---:|---:|---:|
| **Tiana** | 155 999 kg | **48,3 %** | **0** |
| Butterkin | 52 627 kg | 16,3 % | 25 290 |
| Kaori Kuri | 38 385 kg | 11,9 % | 31 643 |
| **Mieluna** | 24 898 kg | **7,7 %** | **0** |
| Amoro … Fictor | 51 359 kg | 15,8 % | 39 391 |

Die Karte „Wie gross sind die Kürbisse?" (Überblick) und die Glocke (Ursachen) füllen
ihre Auswahlliste aus `daten.kaliber`. Sorten ohne CSV erscheinen **gar nicht** — kein
„—", kein „nicht gemessen". Der Betriebsleiter wählt aus einer Liste, in der seine
grösste Sorte fehlt, und erfährt nirgends, warum.

Zusätzlich: 27 von 42 Chargen (84 381 kg = 26,1 % des Eingangs) haben **keine einzige
Palettenwägung**; 9 Chargen keine Schimmelmessung.

### 5.4 Der Schlag-Vergleich, den der Betrieb ausdrücklich verlangt hat, fehlt

`ABLAUF.md`: *„Nicht nur den Kaliber-Anteil, sondern die Gewichtsverteilung … mehrere
Verteilungen nebeneinander — nach Sorte, nach **Schlag**, nach Charge."*

- Die Datenbank liefert es: `v_gewichtsverteilung(sorte, schlag, charge_nr, stufe_g, n)`.
- Der Code kann es nicht: `kaliberJe(zeilen, nach: 'sorte' | 'charge')` — Schlag fehlt
  im Typ (`src/auswertung/daten.ts:523`).
- Die Oberfläche zeigt immer **eine** Verteilung, nie zwei nebeneinander
  (`Ueberblick.tsx:288–301`, `Ursachen.tsx` `Gewichtsverteilung`).

Was verloren geht, gemessen über `v_gewichtsverteilung` (24 Schlag×Sorte-Gruppen mit
über 500 Stück):

| Sorte | Schlag mit leichtestem Schwerpunkt | schwerstem | Spanne |
|---|---|---|---:|
| Kaori Kuri | Rümlang Sauter 1 016 g | Daniel Böhler 1 164 g | **148 g (14,6 %)** |
| Butterkin | Rümlang Sauter 1 169 g | Gossau Eberhard 1 225 g | 56 g (4,8 %) |
| Amoro | Klaus Böhler 1 206 g | Agasul Rüegg 1 415 g | **209 g (17,3 %)** |
| Orangita | Slowgrow Uster 545 g | Gossau Eberhard 589 g | 44 g (8,1 %) |

148 g bei Kaori Kuri sind bei Kaliberbändern von 500 g Breite fast ein Drittel eines
Bands — der Unterschied, der über E16 (früher/später ernten) und E15 (mit welchem
Schlag weiterarbeiten) entscheidet.

### 5.5 Kein Jahresvergleich

`charge.saison` existiert (Wert 2026), `einstellung.saison_aktuell = 2026`. Es gibt
**keine** Ansicht, keine Achse, keinen Filter, der zwei Saisons nebeneinanderstellt
(`grep -rniE "saison|vorjahr" src/` → nur Demodaten-Texte, Dateinamen-Logik und
Typdeklarationen). Der Betriebsleiter kann „16,1 %" mit nichts vergleichen — auch nicht
mit sich selbst im Vorjahr. Das ist die natürlichste aller Betriebsfragen (E17).

*Gegenrede:* Es gibt erst eine Saison; ein Vergleich wäre heute leer. Richtig — aber
dann gehört die Zahl mit ihrer Bezugsgrösse so gebaut, dass sie nächstes Jahr
vergleichbar ist, und das hängt an E20/Frage 51, die offen ist.

### 5.6 Die Prozentzahl (Frage 51) ist unbeantwortet und nur eine von vier steht da

Aus `v_saisonbilanz` und `v_verlust_je_gruppe`, Stand 09.09.:

| Bezugsgrösse | Zahl | steht auf dem Bildschirm |
|---|---:|---|
| an allem, was hereinkam | **16,1 %** | ja, Überblick + Ursachen |
| an dem, was noch nicht ausgeliefert ist | 25,2 % | nein |
| an der ausgelieferten Ware (Nachrechnung) | 13,1 % | nein |
| an der liegenden Ware (daran lässt sich noch etwas ändern) | 18,0 % | nein |

Spanne 13,1 – 25,2 %, also **12,1 Prozentpunkte** bei genau derselben Kilozahl. Solange
E20 offen ist, ist jeder Betriebs- oder Jahresvergleich Glückssache.

### 5.7 Franken sind importiert und werden nie gelesen

`ausgang_zeile.erloes numeric(14,2)` wird aus dem Perigon-Excel gefüllt
(`src/lib/warenausgang.ts:51` bildet `AuftragsErloesTotExkl` darauf ab) und in
`ausgang_uebernehmen` geschrieben (0055, 0061). **Keine Sicht liest die Spalte** — im
Demobestand sind 0 von 160 Zeilen gefüllt, im Echtbetrieb wären sie es. Frage 49
(Rangfolge in Kilo oder Franken) steht seit dem 2. September offen, obwohl die Leitung
gelegt ist.

**Grösse:** 1 Spalte, 0 Leser. Warum es zählt: in Kilo gewinnt heute Schimmel knapp vor
Verdunstung; auf der Maschinen-Linie (Preis je Stück im Kaliber) kostet Verdunstung
erst etwas, wenn ein Kürbis ein Band tiefer rutscht — die Rangfolge kann in Franken
kippen.

### 5.8 Zwei Sorten rechnen mit der 8-kg-Kiste, obwohl der Betrieb sagt: eine

`v_ueberfuellung_verkauf` (gruppe='sorte', kistensystem='kiste_ab'):

| Sorte | Soll | gewogen | zu viel | Wägungen | verkaufte Kisten | verschenkt |
|---|---:|---:|---:|---:|---:|---:|
| Tiana | 8,00 kg | 8,481 kg | +0,481 kg | 28 | 2 546 | 1 224,7 kg |
| Mieluna | 8,00 kg | 8,367 kg | +0,367 kg | 4 | 821 | 301,5 ± 168,9 kg |

`ABLAUF.md`: *„Die 8-kg-Kiste gilt nur für eine Sorte."* Frage 2 in `FRAGEN.md` ist
genau das und offen. **Grösse: 301,5 kg = 19,8 % der ausgewiesenen verschenkten Marge
(1 526 kg) hängen an einer unbeantworteten Frage**, gestützt auf 4 Wägungen mit einem
Fehler von ±169 kg (56 % der Zahl selbst).

### 5.9 Weitere Löcher, kurz

| Was fehlt | Grösse |
|---|---|
| „Wie viel ist sortiert und wartet aufs Waschen?" — `erg_charge.wartet_kg` wird gerechnet (`gegenprobe_wartet_kg` = 11 469 kg) und **nirgends angezeigt**; `ABLAUF.md` nennt „Betrieb → Tempo: wartet" als Ort, dort steht es nicht | 11 469 kg unsichtbar |
| Kein Ranking nach **Kilo** — nur nach Anteil (§6.5) | Spearman 0,35 zwischen beiden Ranglisten |
| Kein Werkzeug für E11/E12 („was bringt eine Messung je Minute") | 0 Zahlen |
| `sd_je_kiste` (Streuung der Kistenfüllung) — die Zahl, die E9 entscheidet („Waage oder anderer Zielwert", Frage 50) — steht in der Sicht, nicht auf dem Schirm | 1 Spalte |

---

## 6. Zahlen ohne Frage — und Zahlen, die eine Frage nur scheinbar beantworten

### 6.1 Die Rangfolge der Ursachen — das Ziel des ganzen Programms — ist oben nicht entscheidbar

`SPEC.md §0`: *„Es geht ums **Rangieren der Ursachen**."* Gemessen aus
`v_verlust_je_gruppe where gruppe='gesamt'`:

| Strom | kg | Bereich | Anteil am Eingang |
|---|---:|---|---:|
| Schimmel/Fäulnis | **26 170** | 9 917 – 42 423 | 8,10 % |
| Verdunstung | **23 530** | 18 899 – 28 162 | 7,28 % |
| Zu klein (Tierfutter) | 7 350 | 4 926 – 9 773 | 2,27 % |
| Nebenkanal zu gross | 4 790 | 1 902 – 7 678 | 1,48 % |
| Faul beim Abpacken (Fax) | 2 419 | 1 701 – 3 137 | 0,75 % |
| Nicht lagerbedingt (Sockel) | 0 | 0 – 2 463 | 0,00 % |

Paarweise Trennbarkeit (Bänder überschneiden sich ja/nein), `kf_rang.sql`:

| Paar | Unterschied | mittlere Bandbreite | Verhältnis | Urteil |
|---|---:|---:|---:|---|
| **Schimmel ↔ Verdunstung** | **2 640 kg** | **20 884 kg** | **0,13** | **nicht trennbar** |
| Schimmel ↔ Zu klein | 18 821 | 18 677 | 1,01 | trennbar |
| Verdunstung ↔ Zu klein | 16 181 | 7 055 | 2,29 | trennbar |
| Zu klein ↔ Zu gross | 2 559 | 5 312 | 0,48 | nicht trennbar |
| Zu gross ↔ Fax | 2 371 | 3 606 | 0,66 | nicht trennbar |
| Zu gross ↔ Sockel | 4 790 | 4 120 | 1,16 | nicht trennbar |
| Fax ↔ Sockel | 2 419 | 1 949 | 1,24 | nicht trennbar |
| übrige 8 Paare | | | 1,4–4,0 | trennbar |

**5 von 15 Paaren (33 %) sind nicht entscheidbar — darunter das oberste.** Der
Überblick stellt die sechs Ströme als farbige Segmente eines Balkens nebeneinander; die
Bandbreite steht nur im Schwebefenster eines einzelnen Segments und nur, wenn
`bereichBekannt` gilt (`Ueberblick.tsx:186`). Wer den Balken ansieht, liest „Faules ist
das Grösste" — und diese Aussage trägt nicht.

### 6.2 Die vier Reiter des Überblicks: wie viele Vergleiche jeder entscheiden kann

Der Balken zeigt alle sechs Ströme; verglichen habe ich genau das, was dasteht
(`kf_bild.sql`, Bänder aus `kg_unten`/`kg_oben`):

| Reiter | Zeilen | mögliche Paare | trennbar | Anteil | Rang 1 trennbar ab Rang |
|---|---:|---:|---:|---:|---:|
| Gesamt | 1 | 0 | — | — | — |
| **je Sorte** | 10 | 45 | **8** | 17,8 % | 2 |
| **je Schlag** | 14 | 91 | **2** | **2,2 %** | **nie** |
| **je Charge** | 36 | 630 | **103** | 16,3 % | 8 |

Der Reiter **„je Schlag"** — der Reiter für E15, eine Entscheidung über Verträge und
Anbaupartner — kann von 91 Vergleichen **zwei** entscheiden, und der Spitzenreiter
(Rümlang Sauter) ist von **keinem** der dreizehn anderen Schläge unterscheidbar:

| Schlag | Eingang | Anteil (Balken) | Bereich |
|---|---:|---:|---|
| Rümlang Sauter | 27 092 kg | 18,00 % | 15,14 – 20,86 |
| Russikon BundB | 10 186 kg | 17,28 % | 15,55 – 19,02 |
| … | | | |
| Illnau Gross | 2 991 kg | 13,24 % | 11,81 – 14,67 |

Zum Vergleich, nur echter Verlust ohne Kanal (`kf_anteil.sql`): je Sorte 9 von 45
trennbar, je Schlag 9 von 91, je Charge 194 von 630.

**Und:** Der Prozentwert rechts an jedem Balken (`anteil-wert`, `Diagramm.tsx:493`)
trägt **keinen Bereich** — weder im Text noch im Schwebefenster. Genau nach dieser Zahl
ist die Liste sortiert.

### 6.3 „Je Sorte: die Rate" — sechs Zeilen, drei davon dieselbe Zahl

`select mittel, count(*) from v_koeff_verdunstung group by 1`:

| Rate je Tag | Sorten | Grundlage |
|---:|---:|---|
| 0,05179 % | **8** | *Wiegungen aller Sorten (zu wenige eigene Chargen)* |
| 0,06172 % | 1 (Butterkin) | 7 eigene Wägungen |
| 0,05140 % | 1 (Mieluna) | 6 eigene |
| 0,04606 % | 1 (Tiana) | 25 eigene |

Paarweise über alle 11 Sorten (`kf_paare.sql`):

| Koeffizient | Paare | **identisch** | überlappend | trennbar |
|---|---:|---:|---:|---:|
| **Verdunstung** | 55 | **28** | 24 | **3** |
| Zu klein | 55 | 3 | 30 | 22 |
| Zu gross | 55 | 6 | 32 | 17 |
| Fax | 55 | 3 | 43 | 9 |

Nur 3 von 11 Sorten haben eine eigene Verdunstungsrate; die Tabelle auf dem Schirm
zeigt 6 Zeilen (die mit n>0), von denen 3 die geliehene Zahl tragen — grau gesetzt und
mit dem Untertitel „Grau: zu wenige eigene Messungen". Das ist ehrlich gemacht. Der
Befund liegt darunter: **28 von 55 Sortenvergleichen sind buchstäblich derselbe Wert
gegen sich selbst**, und fünf Sorten kommen im Bild überhaupt nicht vor (41 Wägungen
verteilen sich auf 6 Sorten, davon 25 auf Tiana).

### 6.4 „Prognose: 14 Tage länger liegen" ist eine Bestandsliste

Die einzige Spalte im Programm, die nach Dringlichkeit aussieht (Chargen, E1).
`v_naechste_charge`, 27 Chargen mit Bestand:

- Korrelation der Prognose mit `lager_kg`: **r = 0,9992**
- Rangkorrelation mit dem Bestandsrang: **0,9963**, 18 von 27 Rängen identisch
- Relative Rate über alle Chargen: **1,583 % – 1,745 %** — Spannweite **0,162
  Prozentpunkte**

| Charge | Sorte | Bestand | Alter | Verlust in 14 Tagen |
|---:|---|---:|---:|---:|
| 1624 | Butterkin | 1 123 kg | 191 d | 1,745 % |
| 1649 | Butterkin | 19 468 kg | 168 d | 1,742 % |
| 1631 | Mieluna | 11 588 kg | 162 d | 1,638 % |
| 1613 | Tiana | 14 073 kg | 189 d | 1,596 % |
| 1647 | Tiana | 5 603 kg | 162 d | 1,583 % |

Zwischen 162 und 191 Lagertagen ändert sich die 14-Tage-Rate innerhalb einer Sorte um
**0,003 Prozentpunkte**. Was die Spalte trennt, ist die Sorte (Butterkin 1,74 %,
Kaori Kuri 1,65 %, Tiana 1,59 %) und der Bestand — **nicht das Alter**, obwohl das
Alter der ganze Zweck der Verderbskurve ist.

Für E1 heisst das: die Spalte sagt „nimm die grösste Charge zuerst". Das hätte der
Betriebsleiter auch ohne App gewusst.

*Gegenrede:* Das ist mathematisch korrekt — in 14 Tagen verliert eine grosse Charge
mehr Kilo als eine kleine, und in Kilo zu rechnen ist richtig, weil Kilo das ist, was
zählt. Der Befund ist deshalb nicht „falsch gerechnet", sondern: **die Spalte
beantwortet nicht die Frage, unter der sie steht.** Was E1 bräuchte, ist die relative
Rate (die Spannweite von 0,16 Punkten sagt: es gibt kaum eine) oder der Abstand zu
einer Schwelle.

### 6.5 Nach Anteil ranken, nach Kilo entscheiden

Der Überblick sortiert nach Anteil und schreibt selbst dazu: *„So sieht man, wem
anteilig am meisten fehlt — nicht, wer am grössten ist."* Ehrlich. Nur gibt es
nirgends eine Liste nach Kilo.

| Sorte | Verlust+Kanal in kg | Anteil | Rang nach Anteil | Rang nach Kilo |
|---|---:|---:|---:|---:|
| Lekor | 2 847 | 28,9 % | **1** | 6 |
| Tiana | **31 740** | 20,3 % | 2 | **1** |
| Ker Madec | 665 | 20,3 % | **3** | 9 |
| Mieluna | 5 028 | 20,2 % | 4 | 4 |
| Kaori Kuri | 7 516 | 19,6 % | 5 | 3 |
| Butterkin | 9 713 | 18,5 % | 6 | 2 |
| Fictor | 472 | 18,3 % | 7 | 10 |
| Amoro | 2 866 | 18,1 % | 8 | 5 |
| Orange Summer | 2 605 | 17,9 % | 9 | 7 |
| Orangita | 808 | 15,3 % | 10 | 8 |

Spearman **0,35** — die beiden Ranglisten haben fast nichts miteinander zu tun. Die
oberste Zeile, an der das Auge zuerst hängenbleibt, gehört einer Sorte mit 3,0 % der
Ernte und 2,8 t Verlust; die Sorte mit 31,7 t steht darunter. Die Kilozahl je Sorte
findet sich nur in der **zugeklappten** Tabelle „Was ist noch im Haus?" — dort sortiert
nach Restbestand und **nur für Sorten mit Bestand** (9 Chargen mit 3 509 kg Verlust
fallen heraus).

### 6.6 Zwei Zahlen, die sich widersprechen

| Was | Überblick | Ursachen | Verhältnis |
|---|---|---|---|
| Zahl der Lieferungen hinter 115,8 t | „186 Lieferungen ab Lieferschein" | „**731** Lieferungen" | **×3,93** |
| Herkunft von „Ausgeliefert 115,8 t" | *gerechnet* (weil `vorlauf_kg > 0`) | *gemessen* (fest verdrahtet) | widersprüchlich |

Zu den 731: `erg_charge.n_lieferungen` entsteht aus
`sum(n_lieferungen)` über die Eingangstags-Kohorten (0060, Zeile 768) — es zählt also
**Lieferung × Eingangstag**, nicht Lieferungen. Charge 1611 hat 8 Lieferungen und 10
Eingangstage und meldet 80. In der Datenbank stehen 187 Lieferungen; die Summe der
Chargenzahlen ist 731. Auf `/ursachen` steht darum unter „Ausgeliefert": *731
Lieferungen*.

Zur Herkunft: `Ueberblick.tsx:71–77` setzt bei `vorlauf_kg > 0` die Marke *gerechnet*
mit der richtigen Begründung („enthält die Angabe des Betriebs über die Zeit vor dem
Erfassungsbeginn"). `Ursachen.tsx` setzt für dieselbe Summe *gemessen*. Der
Begriffs-Prüfstand fängt das nicht: R4 prüft, ob **eine** zulässige Marke dasteht, nicht
ob sie über die Ansichten hinweg dieselbe ist.

### 6.7 Zahlen, an denen keine Entscheidung hängt

Kandidaten, geerntet und geprüft, ob eine der 30 Entscheidungen darauf zurückgreift:

| Zahl | Ort | Häufigkeit | Entscheidung? |
|---|---|---:|---|
| **Rückrechnung (Smearing) ×1,048** | Messungen → Verderbsmodell | 1 | keine — Modellinnenleben |
| **Nachweis ×1,000 bei Schwelle ×1,128** (Sockel) | Messungen | 1 | keine — der Betrieb kann daran nichts drehen |
| **Form der Kurve k = 1,22** | Messungen | 1 | keine unmittelbare |
| **kg/Kürbis** in der Wägungstabelle | Messungen | 40 | keine gefunden |
| **Bandmittel (CSV) in g** neben „Gewogen je Stück" | Ursachen → Überfüllung | ≤10 | grenzwertig (E10) |
| **„Bewegte Masse" je Arbeit**, 196 Zeilen | Betrieb → Arbeiten | 196 | Kontrolle der Erfassung (E23), nicht mehr |
| **„Angabe auf dem Lieferschein"**, 177 Zeilen | Betrieb → Warenausgang | 177 | Kontrolle des Imports (E24) |
| **„Noch im Lager" = 0 kg** in der Massenbilanz je Charge | Messungen | 36 | doppelt zu „Noch im Haus" auf Chargen |
| **Koeffizientenzeile für Bolp 5110** | Ursachen (je Sorte) | 4 | Sorte mit **0 kg Eingang** in dieser Saison |
| **„Gewogen, aber nicht verkauft" (17 Kistensysteme)** | Ursachen → Überfüllung | 34 | Datenpflege, keine Betriebsentscheidung |
| **bilanz_rest −0,01 kg** | Messungen → Bilanz | 1 | Selbstprobe des Modells (richtig so, aber keine Betriebsfrage) |

**Grössenordnung des Ballasts:** Von 2 663 Zahlen entfallen **573** (21,5 %) auf die
beiden Betriebs-Listen (Arbeiten 200, Warenausgang 189) und die Wägungs-/Arbeitslisten
unter Messungen (184) — Listen, die der Erfassungskontrolle dienen (E23/E24) und keiner
Betriebsentscheidung. Weitere ~40 sind Modellinnenleben. Das ist keine Empfehlung zum
Löschen: Kontrolllisten sind nötig. Es ist die Messung dafür, dass die **Zahlen für die
Entscheidungen E1–E22 in der Minderheit sind.**

---

## 7. Die Handlungsprobe: was der Betrieb täte, wenn dieser Strom gewinnt

Für jeden Strom: Angenommen, er ist der grösste — was folgt, und liefert das Programm,
was diese Handlung braucht?

### 7.1 Verdunstung — 23 530 kg [18 899–28 162], 7,28 %

| | |
|---|---|
| **Handlung** | Luftfeuchte hoch, Temperatur runter; Lagerdauer verkürzen; früher verkaufen |
| **Was dafür nötig wäre** | Der Verlauf über die Lagerdauer und der Punkt, ab dem es teuer wird; Zusammenhang Rate ↔ Klima; die Rate je Sorte |
| **Was das Programm liefert** | Ursachen → Verdunstung: 41 gewogene Paletten als Punkte über der Lagerdauer, gestrichelte Erwartung `1−(1−r)^t` mit Band, Tabelle je Sorte |
| **Was fehlt** | **(a)** Es gibt keinen „Punkt, ab dem es teuer wird" — das Modell nimmt eine über die Saison **konstante** Rate an (`ABLAUF.md`, Annahmentabelle). Die Kurve ist praktisch eine Gerade; jeder Lagertag kostet gleich viel. Damit kann das Programm E7 („Lagerdauer verkürzen — ab wann lohnt es?") nicht beantworten, sondern nur „immer ein bisschen". **(b)** **0 Spalten** im Schema tragen Temperatur, Feuchte oder Klima. Die Wirkung der Massnahme aus E6 ist im Programm nicht abbildbar — auch nicht rückwirkend. **(c)** 8 von 11 Sorten teilen eine Rate. |
| **Urteil** | Der Strom ist gemessen, die Handlung ist **nicht gestützt**. |

### 7.2 Schimmel/Fäulnis im Lager — 26 170 kg [9 917–42 423], 8,10 %

| | |
|---|---|
| **Handlung** | Früher aussortieren; die gefährdete Charge zuerst verarbeiten; strenger sortieren |
| **Was dafür nötig wäre** | Welche Charge zuerst kippt; ab welchem Alter es steil wird; ob die Auswahl der Messungen verzerrt ist |
| **Was das Programm liefert** | Kurve `F(t)=1−exp(−λt^k)`, k = 1,22, 140 Messungen aus 33 Chargen über 8–195 Tage; Punkte je Messung; Tabelle „Je Charge: gemessen gegen Modell"; „Prognose 14 Tage" auf Chargen |
| **Was fehlt / trägt nicht** | **(a)** Die Prognose ist eine Bestandsliste (§6.4). **(b)** Von 33 Chargen weicht **1** um mehr als +2 Punkte vom Modell ab (5 nach unten) — und die Abweichung trägt keinen Bereich. **(c)** Die Selektionsfrage ist unprüfbar (§5.2). **(d)** Die Altersklassen, in denen der Bestand liegt, sind die dünnsten: |
| | |

`select … from v_charge_kohorte` gegen `v_schimmel_kurve_anzeige`:

| Altersklasse | Bestand heute | Messungen | gemessener Anteil | Modellwert | Modell ÷ gemessen |
|---|---:|---:|---:|---:|---:|
| 0–14 Tage | 0 | 4 | 0,46 % | 0,22 % | 0,5 |
| 15–30 | 0 | 6 | 0,77 % | 0,90 % | 1,2 |
| 31–60 | 0 | 36 | 1,77 % | 2,11 % | 1,2 |
| 61–90 | 0 | 41 | 3,58 % | 3,87 % | 1,1 |
| 91–120 | 0 | 22 | 3,30 % | 5,77 % | 1,7 |
| **121–180** | **86 953 kg (70,6 %)** | 25 | 7,23 % | 8,76 % | 1,2 |
| **181+** | **36 243 kg (29,4 %)** | **4** | **3,03 %** | **12,94 %** | **4,3** |

**100 % des heutigen Lagers liegt in den beiden Altersklassen, die zusammen 29 von 140
Messungen tragen.** In der ältesten, auf die 29,4 % des Bestands entfallen, rechnet das
Modell mit dem **4,3-fachen** dessen, was die vier Messungen dort zeigen. Der grösste
Strom des Rankings ruht auf dem dünnsten Teil der Kurve.

*Gegenrede:* Vier Messungen bei 181+ Tagen sind eine sehr kleine Stichprobe; ihr
Mittelwert von 3,03 % ist selbst kaum belastbar, und die Kurve ist gerade dafür da, aus
allen 140 Punkten zu schliessen statt aus vieren. Es kann auch Selektion sein: was so
lange liegt, ist vielleicht die robustere Ware. Genau deshalb ist der Befund kein
„Modell falsch", sondern: **das Programm sagt dem Betriebsleiter nicht, dass sein
ganzes heutiges Lager im am wenigsten gestützten Teil der Kurve steht.**

| **Urteil** | Der Strom ist die Nummer 1 — nicht unterscheidbar von Nummer 2 — und die Handlung ist nur schwach gestützt. |

### 7.3 Nicht lagerbedingt (Sockel a₀) — 0 kg [0–2 463]

| | |
|---|---|
| **Handlung** | Nichts im Lager. Erntehandhabung, Hagelschutz, Schnittführung — Gespräch mit dem Bewirtschafter des Schlags |
| **Was dafür nötig wäre** | Der Sockel je **Schlag**, nicht gesamt |
| **Was das Programm liefert** | Eine Zahl: 0,0 %. Nachweis ×1,000 bei Schwelle ×1,128 (Messungen) |
| **Was fehlt** | Der Sockel wird nur gesamt geschätzt, nie je Schlag. „Nicht nachweisbar" und „null" sehen im Balken identisch aus — die Zeile „davon nicht lagerbedingt" erscheint auf Ursachen gar nicht, weil sie nur bei `feld.mittel > 0` gerendert wird (`Ursachen.tsx`). Der Betriebsleiter sieht die Zahl 0 nirgends, nur ihr Fehlen. |
| **Grösse** | Obergrenze 2 463 kg = **4,7 % des Gesamtverlusts**, unsichtbar |
| **Urteil** | Handlung nicht gestützt; **und der Strom ist auf dem Schirm gar nicht vorhanden.** |

### 7.4 Zu klein (Tierfutter) — 7 350 kg [4 926–9 773], 2,27 %

| | |
|---|---|
| **Handlung** | Kaliberuntergrenze neu verhandeln; anders anbauen/ernten; besseren Kanal als Tierfutter suchen (E19) |
| **Was dafür nötig wäre** | Die Gewichtsverteilung mit der Grenze darüber, je Sorte **und je Schlag**; wie viel Masse knapp unter der Grenze liegt |
| **Was das Programm liefert** | Glocke mit Kalibergrenzen, Anteil je Klasse, „Gewogene Masse zu klein"; Ausschussanteil je Sorte (8 von 11 mit eigener Messung) und je Charge |
| **Was fehlt** | 56 % der Masse ohne CSV (§5.3); keine Schlag-Gruppierung (§5.4); keine Verteilungen nebeneinander; kein Preis (E21) |
| **Urteil** | Die Handlung ist für 44 % der Masse gestützt, für 56 % gar nicht — und das steht nirgends. |

### 7.5 Nebenkanal zu gross — 4 790 kg [1 902–7 678], 1,48 %

| | |
|---|---|
| **Handlung** | Abnehmer suchen oder Obergrenze verhandeln (E18) |
| **Was dafür nötig wäre** | Menge, Preisdifferenz, Verteilung über der Obergrenze |
| **Was das Programm liefert** | Zahl mit Band (Faktor 4,0), Glocke-Klasse „zu gross" |
| **Was fehlt** | Preisdifferenz (E21); und der Strom ist von Fax **und** vom Sockel nicht trennbar (§6.1) |
| **Ersparnis-Befund** | Bei 1,5 % des Eingangs und einem Band von Faktor 4 lohnt sich **keine** genauere Messung: die Handlung („gibt es einen Abnehmer?") hängt nicht an der Kilozahl, sondern an einer Ja/Nein-Antwort des Marktes. **Das ist eine Ersparnis, kein Mangel** — dieser Strom muss nicht genauer werden. |

### 7.6 Faul beim Abpacken (Fax) — 2 419 kg [1 701–3 137], 0,75 %

| | |
|---|---|
| **Handlung** | Sanfter waschen; kürzer stehen lassen zwischen Waschen und Fax |
| **Was dafür nötig wäre** | Der Faulanteil über den Tagen seit dem Waschen; getrennt nach „Waschschaden" und „Stehen" |
| **Was das Programm liefert** | **Eine einzige Zahl** und einen Fliesstext (Ursachen → Fax, 1 geerntete Zahl) |
| **Was fehlt** | Die Kurve über `tage_seit_waschen` — deren Daten seit 0060 in 142 von 161 Arbeiten vorliegen und 1,314 % → 2,722 % zeigen (§5.1) |
| **Grösse** | 985 kg je Saison, 41 % des Stroms, ohne einen Handgriff mehr in der Halle |
| **Urteil** | Der **kleinste** Strom trägt den **handfestesten** Hebel — und ist der einzige, dessen Karte nur eine Zahl zeigt. |

### 7.7 Zusammenfassung der Handlungsprobe

| Strom | kg | Handlung gestützt? | Was die Handlung bräuchte |
|---|---:|---|---|
| Schimmel | 26 170 | teilweise | Dringlichkeitsmass statt Bestandsliste; Lagerkontrolle mit Faul-Zählung |
| Verdunstung | 23 530 | nein | Klimadaten; nichtkonstante Rate; Rate je Sorte |
| Zu klein | 7 350 | halb (44 % der Masse) | CSV-Abdeckung; Glocke je Schlag |
| Zu gross | 4 790 | nein — **muss auch nicht** | Marktantwort, keine Messung |
| Fax | 2 419 | **nein, obwohl die Daten da sind** | eine Kurve über `tage_seit_waschen` |
| Sockel | 0 | nein | Sockel je Schlag; Angabe beim Leeren des Palox (Frage 5) |

---

## 8. Die Vergleiche: was die Oberfläche nebeneinanderstellt

| Vergleich, den der Betriebsleiter anstellt | Stellt die Oberfläche das nebeneinander? | Wo | Entscheidbar? |
|---|---|---|---|
| Ursache A gegen Ursache B | **ja** — sechs Farbsegmente in einem Balken | Überblick | 10 von 15 Paaren; **die obersten zwei nicht** |
| Sorte A gegen Sorte B (Verlust) | **ja** — zehn Balkenzeilen, sortiert | Überblick, Reiter „je Sorte" | 8 von 45 |
| Schlag gegen Schlag | **ja** — vierzehn Balkenzeilen | Überblick, Reiter „je Schlag" | **2 von 91** |
| Charge X gegen Charge Y (Verlust) | **ja** — 36 Balkenzeilen | Überblick, Reiter „je Charge" | 103 von 630 |
| Charge X gegen Charge Y (Bestand, Alter) | **ja** — Tabelle | Chargen | ohne Bereich, nicht prüfbar |
| Sorte gegen Sorte (Verdunstungsrate) | **ja** — Tabelle + Punktreihen im selben Bild | Ursachen → Verdunstung | 3 von 55; 28 identisch |
| Sorte gegen Sorte (zu klein / zu gross) | **ja** — Tabelle mit Bereich | Ursachen → Sortierung | 22 bzw. 17 von 55 |
| Charge gegen ihre Sorte | **ja** — letzte Spalte „Sorte: zu klein · zu gross" | Ursachen → Sortierung | ohne Bereich je Charge |
| Charge gegen das Modell (Faules) | **ja** — „Gemessener Anteil ↔ Modell-Anteil ↔ Abweichung", ab ±2 Punkte eingefärbt | Ursachen → Palox | 6 von 33 über der Schwelle, ohne Bereich |
| Modell gegen CSV je Charge | **ja** — „Abweichung Modell ↔ CSV", ab 10 % markiert | Messungen | 25 Zeilen mit Zahl |
| Gemessen gegen Modell je Altersklasse | **nein** — `v_schimmel_kurve_anzeige.gemessen` existiert, gezeichnet wird nur `verwendet` | — | §7.2 |
| Verteilung Sorte A gegen Sorte B | **nein** — ein Auswahlfeld, eine Glocke | Überblick, Ursachen | — |
| Verteilung Schlag gegen Schlag | **nein** — Gruppierung im Code nicht vorgesehen | — | §5.4 |
| Dieses Jahr gegen letztes | **nein** — kein Saisonvergleich existiert | — | §5.5 |
| Kiste-ab-System gegen Stück-System | **ja** — zwei Tabellen untereinander | Ursachen → Überfüllung | keine gemeinsame Grösse |
| Tätigkeit gegen Tätigkeit (Tempo) | **ja** — „Arbeit und Tempo", kg/h und kg je Person·h | Betrieb → Arbeiten | ohne Bereich |
| Alter der verarbeiteten Ware gegen Durchschnitt | **ja** — Punktwolke „Wird das Älteste zuerst verarbeitet?" | Messungen | ja, mit Mittelwert |
| Verlust in Kilo, Sorte gegen Sorte | **nur zugeklappt und nach Bestand sortiert** | Überblick → „Was ist noch im Haus?" | §6.5 |
| Franken gegen Franken | **nein** | — | §5.7 |

**Zusammengefasst:** Die Oberfläche stellt **14 Vergleichsarten** nebeneinander. Bei
**keiner einzigen** steht neben dem Unterschied, ob er grösser ist als die Unsicherheit.
Über alle Balkenvergleiche hinweg (766 Paare) sind **113 (14,8 %)** entscheidbar.

---

## 9. Erfassungsdichte — was der Betrieb bezahlt hat

`select * from v_datenqualitaet`, Stand 09.09.:

| Absprache | erfüllt | von | Anteil |
|---|---:|---:|---:|
| Palox abgelesen (mindestens einmal) | 145 | 145 | 100 % |
| Palox zu Beginn **und** am Ende | 135 | 145 | 93 % |
| „Alles aus einer Charge?" beantwortet | 144 | 145 | 99 % |
| Kisten am Sortieren gezählt | 31 | 31 | 100 % |
| Waschen: Paletten gezählt | 94 | 95 | 99 % |
| Fax: Paletten gezählt | 160 | 160 | 100 % |
| Fax: Faules gewogen | 160 | 160 | 100 % |
| W+S: Zettelgewicht je Palette | 231 | 238 | 97 % |
| Kistensystem beantwortet | 272 | 274 | 99 % |
| Waschen: Sortierdatum je Palette | 8 918 | 8 918 | 100 % |
| Sortier-CSV zugeordnet | 31 | 32 | 97 % |
| **Datum vom Zettel bei gezählten Paletten** | **527** | **851** | **62 %** |

Die Halle hält elf von zwölf Absprachen nahezu vollständig ein. Die eine Ausnahme (62 %)
ist genau die, an der jede Lagerdauer hängt.

**Erfasste Messungen insgesamt:** 585 Palox-Ablesungen · 854 gezählte Paletten ·
8 918 gezählte Kisten · 128 gewogene fertige Paletten · 41 Palettenwägungen (davon 24
Lagerkontrollen) · 34 Ausschusswägungen · 32 Sortier-CSVs mit 5 668 gewogenen Kürbissen ·
160 Fax-Faules-Wägungen.

**Arbeiterzeit — Schätzung, nicht gemessen** (Annahmen: Palox-Ablesung 1 min,
Palettenzählung 0,5 min, Kiste 3 s, fertige Palette 4 min, Palettenwägung 8 min,
Ausschusswägung 5 min, CSV 3 min, Fax-Faules 5 min):

| Messart | Zeit | Was sie trägt |
|---|---:|---|
| Fax: Faules wiegen | ≈ 13,3 h | den kleinsten Strom (2,4 t) — **und den einzigen klaren Hebel** |
| Kisten zählen (Waschen) | ≈ 7,4 h | den Nenner des Palox am Waschbecken |
| Palettenzählung mit Datum | ≈ 7,1 h | Alter der verarbeiteten Ware |
| Palox ablesen | ≈ 9,8 h | den grössten Strom (26,2 t) |
| Fertige Paletten wiegen | ≈ 8,5 h | Überfüllung (1,5 t) und Palettenmasse |
| Palettenwägungen | ≈ 5,5 h | Verdunstung (23,5 t) — **41 Stück für den zweitgrössten Strom** |
| Ausschuss wiegen | ≈ 2,8 h | zu klein/zu gross dort, wo es keine CSV gibt |
| Sortier-CSV | ≈ 1,6 h | Kaliber, Ausschuss, Gegenprobe für 44 % der Masse |
| **Summe** | **≈ 56 h** | |

Auffällig: Der Strom mit 23,5 t (Verdunstung) ruht auf **41** Messungen und 5,5 h; der
Strom mit 2,4 t (Fax) auf **160** Messungen und 13,3 h. Ob das falsch herum ist, kann
diese Karte nicht entscheiden — dafür braucht es das Werkzeug aus D4 (Unsicherheit je
Minute). Aber es ist die richtige erste Frage an dieses Werkzeug.

---

## 10. Was daraus für Werkstatt D folgt — sortiert nach Wirkung

| # | Was | Grösse | Marke |
|---|---|---|---|
| 1 | Kurve „Faulanteil über Tage seit dem Waschen" — die Daten liegen seit 0060 da | **985 kg/Saison**, 41 % des Fax-Stroms | Reparatur (eine Karte, kein neues Feld) |
| 2 | Neben jeden Vergleich, den die Oberfläche sortiert, die Unterscheidbarkeit | 766 Paare, 113 entscheidbar | Reparatur |
| 3 | Widerspruch Lagerkontrolle: 24 gegen „keine" auf einer Seite; Rat, der nicht wirkt | 3,2 h Arbeiterzeit, Überdeckung 0–44 % statt 96–100 % | Reparatur + Frage an den Betrieb |
| 4 | „731 Lieferungen" | ×3,93 | Reparatur |
| 5 | Herkunftsmarke „Ausgeliefert": gerechnet ↔ gemessen | 1 Zahl, 2 Ansichten, 115,8 t | Reparatur |
| 6 | Reiter „je Schlag" kann nichts entscheiden | 89 von 91 Vergleichen | Entscheidung: entfernen oder mit Bereich versehen |
| 7 | „Prognose 14 Tage" ist eine Bestandsliste | r = 0,9992 | Reparatur oder Umbenennung |
| 8 | Sorten ohne CSV fehlen stumm in der Glocke | 180 897 kg = 56,0 % | Reparatur (eine Zeile „nicht gemessen") |
| 9 | Glocke je Schlag | Spalte da, Spannweite bis 209 g | Reparatur |
| 10 | Frage 51 (Bezugsgrösse) und Frage 49 (Franken) entscheiden | 12,1 Prozentpunkte bzw. 1 Spalte ohne Leser | Frage an den Betrieb |
| 11 | Frage 2 (8-kg-Kiste) entscheiden | 301,5 kg = 19,8 % der Marge-Zahl | Frage an den Betrieb |
| 12 | „Gemessen gegen Modell je Altersklasse" sichtbar machen | 29,4 % des Bestands, Modell ÷ gemessen = 4,3 | Reparatur oder Werkstatt A |

---

## 11. Die ehrliche Antwort auf die Leitfrage

*Löst dieses Programm das Problem, für das es gebaut wurde?*

**Zur Hälfte, und die messbare Hälfte ist nicht die, für die es gebaut wurde.**

Woran ich das festmache:

- Es misst **hervorragend, ob gemessen wird**: elf von zwölf Absprachen über 93 %,
  22 Auffälligkeiten in 7 Arten, Bilanzrest −0,01 kg auf 323 t. Die Entscheidungen
  E23/E24/E26 sind sauber beantwortet. Das ist ein echtes Ergebnis.
- Es soll aber **Ursachen rangieren** (SPEC §0). Die Rangfolge steht da — und die
  obersten zwei Plätze sind bei 2 640 kg Unterschied und 20 884 kg Bandbreite nicht
  entscheidbar. **Die Kernaussage des Programms trägt nicht, und nirgends steht, dass
  sie nicht trägt.**
- Von 766 Vergleichen, die die Oberfläche nebeneinanderstellt, sind **113 (14,8 %)**
  entscheidbar; 3,0 % der 2 663 Zahlen sagen, wie sicher sie sind.
- Die eine Massnahme, die heute ohne zusätzlichen Handgriff **985 kg** rettete, steckt
  in einer Spalte, die 142-mal befüllt und **null**-mal gelesen wird.

Was es kosten würde, das zu ändern: die Punkte 1, 4, 5, 8 und 12 aus §10 sind je eine
Karte oder eine Zeile — kein neuer Bildschirm, kein neues Feld in der Arbeiter-Maske.
Punkt 2 ist der einzige echte Neubau, und er ist genau das Werkzeug, das Abschnitt D2
des Auftrags verlangt.

»
