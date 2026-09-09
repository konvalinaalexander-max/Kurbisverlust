# Hypothesenbuch — der Stand nach dem Lauf

Zu jeder der fünfzig Vermutungen aus `pruefwerk/hypothesen.md` die Antwort:
**bestätigt**, **widerlegt** oder **nicht entscheidbar, weil …**. Keine bleibt
offen. Wo eine Vermutung zu einer Feststellung geführt hat, steht deren Kennung
dabei; die Feststellungen selbst stehen mit Grösse, Belegstelle und Gegenrede in
`docs/PRUEFBERICHT.md`.

*(Der Auftrag nennt als Ablage `pruefwerk/befunde/hypothesen_stand.md`. Dort
liegen die Ergebnisse eines Laufs, die bei jedem Lauf neu entstehen und deshalb
nicht im Bestand geführt werden. Diese Datei ist ein Urteil, kein Ergebnis —
sie gehört in den Bestand und steht deswegen eine Ebene höher.)*

## Herkunft und Beschriftung

**H01 — bestätigt (SZE-002, LNN-005).** Fehlt die Tara einer Gebindeart, ist
`v_palette.netto_kg` NULL. Schlimmer als vermutet: Es wird nicht nur eine
Palette übersprungen, sondern die ganze Charge fällt aus der Bilanz — 2000 kg
brutto ergeben einen Eingang von 0 kg, 0 Chargen, und `v_plausibilitaet` meldet
nichts. Fehlt dagegen nur bei *einzelnen* Paletten die Gebindeart, bekommen sie
das Mittel der übrigen und gehen mit der Marke **gemessen** in den Eingang ein.

**H02 — bestätigt (HER-001).** `ausgang_kg` enthält `vorlauf_kg`, die Angabe des
Betriebs über die Zeit vor dem Erfassungsbeginn. In der Demosaison sind das
5000 von 115 836 kg, also 4,3 % einer Zahl, die die Marke **gemessen** trägt —
während die Seite selbst erklärt, „gemessen" heisse „jede Lieferung auf einem
Lieferschein".

**H03 — bestätigt, ohne eigene Feststellung.** Gepoolte Koeffizienten
(`basis = 'alle Sorten (…)'`) stehen im Rechenweg jeder Karte und werden bei
weniger als drei Messungen zusätzlich als „dünne Datenlage" ausgewiesen. Das ist
die Auskunft, die H03 verlangt; sie steht nur nicht in der Kopfzahl. Für sich
genommen ist das vertretbar — die Kopfzahl kann nicht jede Herkunft tragen.
Gemeinsam mit H02 und LNN-005 ergibt sich daraus aber die Frage, was die Marke
**gemessen** überhaupt noch behauptet. Diese Frage steht im Bericht.

**H04 — bestätigt, und schwerer als vermutet (SZE-006).** `coalesce(k.im_haus_
heute_kg, b.eingang_kg)` ist für den Fall gedacht, dass es zu einer Charge gar
keine Kaskadenzeile gibt. Sie greift aber auch, wenn es Zeilen gibt und nur die
Portion `lager` fehlt — und das ist der genaue Gegenfall: Es liegt nichts mehr.
Eine vollständig ausgelieferte Charge über 950 kg meldet 950 kg „noch im Haus",
und die Bilanz geht um dieselben 950 kg nicht auf. Am Saisonende wird das der
Normalfall.

**H05 — bestätigt, mit Einschränkung.** Auf der Chargen-Seite steht die
Näherung sogar da — allerdings als roher Datenbankwert in Klammern
(`zettel-charge-tara`). Auf dem Überblick steht sie nirgends. Siehe H48.

## Bezugsgrössen

**H06 — bestätigt und beziffert (BEZ-004).** 16,12 % des Eingangs gegen 25,13 %
von (Eingang − Ausgang) — neun Prozentpunkte. Beide Zahlen taugen nicht als
Handlungszahl; die dritte Lesart, getrennt nach Portion, schon: 13,07 % an der
ausgelieferten Ware, 18,01 % an der liegenden. Vorgelegt, nicht entschieden.

**H07 — widerlegt.** Der Balken enthält nur Verlust- und Kanalströme, nicht die
Lieferungen. Der grösste Zeilenanteil der Demosaison liegt bei 29,2 %; über
100 % kommt keine Zeile. Die Deckelung `Math.min(…, 100)` wirkt ausserdem auf
die Breite, nicht auf die Beschriftung — das trägt heute, ist aber eine Falle
für später und im Bericht unter BEZ-001 verwandter Art vermerkt.

**H08 — bestätigt, ohne Schaden.** Eine Charge ohne jede Messung hat Anteil 1,
und damit ist die Eingangsmasse hinter einer Lieferung genau die Lieferung. Das
ist richtig so: Ohne Messung ist keine Ausbeute bekannt, und 1 ist die einzige
Annahme, die nichts hinzuerfindet. Der Papierfall (S1) rechnet genau so und geht
auf 2850 / 950 / 1900 kg auf.

**H09 — widerlegt.** Die Tabelle unter Ursachen → Verdunstung hat die Spalten
„je Tag" und „nach 100 Tagen" nebeneinander; die Tagesrate steht mit drei
Nachkommastellen. Nachgesehen, in Ordnung.

**H10 — widerlegt.** „Anteil der Stück" heisst so, und die Massenzeilen heissen
„Gewogene Masse". Der Begriffs-Prüfstand aus Runde I hält beides fest.

## Erfassung → Auswertung

**H11 — bestätigt (ERF-001).** Sechs Felder verlangt die Maske und die Tabelle
lässt sie leer — darunter `auftrag_palette.kisten`, das genau in die
Netto-Formel eingeht, und `lieferung.kg`.

**H12, H13, H15 — widerlegt.** `verdunstung_wiegung.kuerbisse_pro_kiste` wird
von `v_ausgang_kennzahl` und `v_wiegung_kennzahl` gelesen,
`auftrag.tage_seit_waschen` von `v_fax_beobachtung` und `v_datenqualitaet`,
`bemerkung` in den Korrekturmasken. Sonde 03 hat alle 13 Erfassungstabellen
durchsucht und **keine** Spalte gefunden, die nirgends gelesen wird.

**H14 — widerlegt.** `sichtbar_schimmel` wird von `v_verdunstung_messung`,
`v_plausibilitaet` und der Korrekturmaske gelesen und dort auch gesetzt. Der
Filter ist nicht tot.

**H16 — widerlegt.** Fehlt das Kistengewicht, meldet `v_plausibilitaet` die Art
„Ohne Nenner" — in der Demosaison einmal, mit 7 kg. Die Auffälligkeit tut genau,
was H16 verlangt.

**H17 — widerlegt.** `v_schimmel_modell_rechnen` trennt über `quelle` in
`verarbeitung` und `lager` und zieht den Sockel nur bei `verarbeitung` ab
(`case when mit_sockel then (f − a0)/(1 − a0)`). Die Trennung ist da und ist die
richtige.

## Mathematik der Kaskade

**H18 — widerlegt, mit Beleg.** Die Messung, an die F(t) angepasst wird, ist
bereits sockelbereinigt: `fs = (f − a0)/(1 − a0)` für Verarbeitungsmessungen.
Die Kaskade rechnet `m1·a0 + m1·(1−a0)·f`, zusammen also `m1·(a0 + (1−a0)·f)` —
genau die Grösse, die gemessen wurde. Kein Doppelzählen.

**H19 — nicht entscheidbar auf den Demodaten, und das ist die Auskunft.** Der
Deckel `greatest(…, 0.25)` greift nirgends: Der kleinste verkaufsfähige Anteil
liegt bei 0,671 (bei 198 Lagertagen). Die Invariante „Rückrechnung" prüft die
Gleichung `verkaufsfaehig_kg = geliefert_kg` bei jedem Lauf und hält. Was
geschähe, wenn der Deckel greift, prüft Sonde 04 mit — die Feststellung bleibt
aus, weil der Fall nicht eintritt. Er kann eintreten, wenn eine Sorte deutlich
schlechter hält; dann fällt es der Invariante auf.

**H20 — nicht entscheidbar ohne den Betrieb.** Der Fax-Koeffizient wird als
*Faules ÷ Masse der Fax-Arbeit* gemessen und auf `m2·(1−klein−gross)`
angewandt. Beide Male ist die Bezugsmasse „was zum Abpacken kam". Das passt,
solange die Masse der Fax-Arbeit tatsächlich die abgepackte Masse ist und nicht
die Eingangsmasse dahinter. Aus dem Code allein ist das nicht zu entscheiden;
die Frage steht im Bericht unter den Fragen an den Betrieb.

**H21 — widerlegt.** Beide Wege messen nach dem Palox. Der Ausschuss aus der
Sortier-CSV wie die Handmessung beim Waschen + Sortieren beziehen sich auf die
Masse, die die Maschine verlassen hat.

**H22 — bestätigt als korrekt (Sonde 04).** Das unabhängige Rechenwerk hat für
alle 156 Portionen `m0 = geliefert ÷ Anteil` und daraus rückwärts wieder die
Lieferung erhalten; die grösste Abweichung liegt unter 10⁻⁶ relativ. Es hebt
sich exakt auf.

**H23 — widerlegt und beziffert.** Das massegewichtete Mittelalter statt der
Einzelalter kostet **0,4 kg auf 109 425 kg** (0,0004 %). Grund: Bei einer
Tagesrate um 0,05 % ist `(1−r)^t` über die auftretende Altersspanne praktisch
linear, und dort ist der Mittelwert exakt. Bei einer zehnmal höheren Rate wäre
das anders — die Zahl gilt für diesen Betrieb, nicht allgemein.

## Metamorphe Prüfungen

**H24 bis H28, H31, H32 — geprüft, alle halten.** Erhaltung, Zerlegung, Bilanz,
Idempotenz und Zeitpfeil laufen bei jedem Lauf über die Demodaten und über jeden
Störfall. Der Bilanzrest liegt bei −0,01 kg auf 323 t.

**H29 — bestätigt (LNN-001, SZE-001).** Genau so, wie im Hypothesenbuch
vermutet: `coalesce(kv.mittel, 0)` macht aus dem fehlenden Koeffizienten eine
Null, und 16 Spalten in zwei Sichten geben sie als 0,00 kg aus, während
`erg_verlust` dieselben Ströme korrekt als NULL führt.

**H30 — widerlegt.** Die Dubletten-Regel des Warenausgang-Imports ist durch
Modultests abgedeckt; ein zweites Einlesen derselben Datei ändert keine Zahl.

## Mutation

**H33 bis H37 — geprüft, siehe MUT-001.** Von dreizehn gezielten Verstellungen
in der Rechenschicht wird ein Teil von `pruefung.sql` oder von den Invarianten
gefangen, ein Teil ändert auf den Demodaten keine einzige Zahl. Die genaue
Aufteilung steht im Bericht. Der wichtigste Nebenbefund: Verstellungen am Sockel
a₀ und am Deckel bei 25 % sind auf den Demodaten **wirkungslos**, weil dort
a₀ = 0 ist und der Deckel nie greift. Beide Stellen sind damit ungeprüft, ohne
dass es einer Prüfung anzusehen wäre.

## Praxisfälle

**H38 — widerlegt.** Zwei Paletten derselben Charge mit identischem Brutto: Das
Eingangsdatum entscheidet, und es ist Pflicht. Der Fall geht auf.

**H39 — bestätigt (SZE-003).** Ein Zettelgewicht, das zur Charge passt, aber
nicht zum Tag, fällt auf die mittlere Tara zurück, ohne dass die Auffälligkeit
„Zettelgewicht" feuert: Die Auffälligkeit prüft Charge und Brutto, die
Massenrechnung zusätzlich Datum und bekanntes Netto.

**H40 — bestätigt (SZE-004, MET-001).** Eine Lieferung ins Buch `verlust`
(Kompost) zählt in `ausgang_kg`, wird aber von `v_lieferung_kohorte` nicht in
die Kaskade genommen. 500 kg sind gleichzeitig ausgeliefert und auf Lager. Es
ist derselbe Fehlertyp, den 0062 für `marge` behoben hat — für `verlust` blieb
er stehen.

**H41 — bestätigt (ERF-002).** Neun Chargen der Demosaison liefern zusammen
4180 kg mehr aus, als für sie je als Eingang erfasst wurde; bei einer Charge
sind es 36,6 % ihres Eingangs. Die Kaskade fängt das als `ueberzaehlung_kg` ab,
damit die Bilanz aufgeht — gemeldet wird es unter Auffälligkeiten nicht.

**H42 — widerlegt.** Ein gefallener Palox-Stand erzeugt die Auffälligkeit „Palox
geleert" (fünfmal in der Demosaison) und keine Zahl. Genau richtig.

**H43 — widerlegt.** `stichtag() = greatest(saison_ende, heute())` kann nicht in
der Vergangenheit liegen, und die Kaskade nimmt zusätzlich
`greatest(stichtag − eingangsdatum, 0)`. Doppelt gesichert.

## Leer ist nicht null

**H44 — bestätigt und gezählt (LNN-001, LNN-003, LNN-004, ERF-001).** Die
Wurzel sind die `coalesce(…, 0)` in der Koeffizientenschicht; dazu kommen 19
Stellen in der Oberfläche, an denen aus einer fehlenden Masse eine Null wird,
und sechs Felder, deren Lücke eine Sicht in eine Null verwandelt.

**H45 — widerlegt für die Massen, bestätigt als Frage.** Die `greatest(…, 0)`
an den Massen stehen an genau zwei Stellen (`m0` der liegenden Portion und die
Überzählung), und beide führen die abgeschnittene Menge als `ueberzaehlung_kg`
weiter — sie verschwindet also nicht, sie bekommt einen Namen. Die Verstellung
`ueberzaehlung-ungebremst` wird von der Bilanz-Invariante gefangen. Offen bleibt
nur, dass die Überzählung nirgends als Auffälligkeit erscheint (H41).

## Begriffe

**H46 — widerlegt.** „Ausgeliefert" und „Ausgelagert" stehen auf verschiedenen
Seiten und werden dort erklärt („Ausgeliefert / dahinter an Eingang" auf der
Chargen-Seite, „Ausgelagert … kommt aus der Kaskade" unter Messungen).

**H47 — widerlegt.** Beide Stellen sagen dasselbe: Der Strom heisst „Faul beim
Abpacken (Fax)" und wird unter den Palox-Ursachen geführt.

**H48 — bestätigt.** `masse_quelle` erscheint auf der Chargen-Seite roh in
Klammern (`zettel-charge-tara`, `kisten-x-kistengewicht`). Das ist Technik im
Klartext — klein, aber es widerspricht der Regel aus Runde I, dass jede Zahl in
der Sprache des Betriebs sagt, was sie ist. Im Bericht als Kleinigkeit geführt.

## Annahmen

**H49 — bestätigt (ANN-001).** Die 21 Zeilen der Annahmentabelle nennen, was
angenommen wird und was passiert, wenn es nicht stimmt — aber zu keiner steht,
wo ihr Bruch auffiele. Eine maschinelle Zuordnung über Stichworte ist versucht
und verworfen worden: Sie findet zu 20 der 21 Zeilen irgendeinen Treffer, bei 16
davon in mehr als drei Dateien gleichzeitig. Das ist Zufall, kein Beleg.

**H50 — bestätigt und beziffert (SZE-005).** Fünf Kisten weniger beim Wiegen als
beim Eingang — dieselbe Tara wird zweimal abgezogen — ergeben eine um rund
11 % zu hohe Tagesrate. Die Rate geht potenziert in jede Verdunstungszahl der
Sorte ein.

## Was aus den bestätigten Vermutungen geworden ist

Dieses Buch ist der Stand **vor** den Reparaturen — es hält fest, was gefragt
und was gefunden wurde. Was daraus geworden ist, steht hier, damit niemand die
Liste für den heutigen Zustand hält:

| Vermutungen | Reparatur | Wo |
|---|---|---|
| H01, H02, H09, H10 (Tara und Kistenzahl am Eingang) | Ohne Kistenzahl und ohne hinterlegte Tara gibt es kein Netto; die Lücke steht als Auffälligkeit da | Migration 0064, `src/lib/masse.ts` |
| H11 bis H16 (ungemessene Ströme als 0,00 kg) | Je Strom ein eigenes Kennzeichen; ohne Messung NULL statt 0 | Migration 0064 |
| H21, H22 (Kompost zählt zweimal) | Dritte Portion „entsorgt": entsorgte Ware altert nicht weiter und liegt nicht mehr im Lager | Migration 0065 |
| H23 (vollständig ausgelieferte Charge) | „Keine Kaskadenzeile" wird von „keine liegende Portion" unterschieden | Migration 0064 |
| H31, H48 (Beschriftung, `masse_quelle`) | Herkunftsmarke nach `n_paletten_mit_netto`; deutsche Worte statt Datenbankwerten | `Ueberblick.tsx`, `masse.ts` |
| H49 (Annahmen ohne Fundort) | Vierte Spalte „Wo es auffiele" für alle 21 Zeilen, von Sonde 10 bewacht | `docs/ABLAUF.md` |
| H36 bis H40 (Netz aus Tests) | Mutationsschutz in `pruefung.sql`; die Sonde sucht die zu verstellende Migration selbst, statt sie zu kennen | `supabase/test/pruefung.sql`, Sonde 06 |
| — (in der Nachlese dazugekommen) | Vier Teilbeträge, zwei Auslöser mit erfundenem Netto, eine Auffälligkeit mit falscher Auskunft | Migration 0066 |
| H43 bis H45 (Bezugsgrösse) | **nicht repariert** — die Wahl gehört dem Betrieb, Frage 1 in `docs/PLAN_REPARATUREN.md` |
| H50 (umgestapelte Palette) | **nicht repariert** — Frage an die Halle, Frage 2 ebenda |
