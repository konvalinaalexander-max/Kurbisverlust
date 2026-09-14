# Runde P — was liegt, und was davon verkauft sich

Der Betrieb hat in Runde P nicht nach einer Funktion gefragt, sondern nach
zwei Antworten:

> *„Wieviel Kürbis kam rein und raus — und wieviel von dem, das noch im Haus
> ist, ist verkaufsfähig?"*

> *„Was war am schlimmsten, was ist das grösste Problem, wo geht mein Kürbis
> hin?"*

Und dazu die Zeitfrage, die ihn im Oktober beschäftigt, wenn der letzte
Kürbis vom Feld kommt:

> *„Ich hab noch 400 Tonnen — aber die App sagt mir, nur 65 % davon sind noch
> verkaufbar."*

Diese Datei beschreibt, **was gebaut ist** — nicht, was geplant war. Der Plan
steht in `docs/PLAN_RUNDE_P.md`, die Messungen im `docs/BEFUND_RUNDE_P.md`.
Die Bilder aller Bildschirme entstehen mit `node pruefstand/bildschirme.mjs`
in `pruefstand/bilder/`.

## 1. Die Regel: eine Formel, ein Nenner

**Eine Formel.** Jede Zahl über die Zukunft ist die Kaskade (`mv_kaskade`,
Portion „lager") an einem späteren Tag ausgewertet — dieselben Faktoren,
dieselben Klammern. Bei Horizont 0 steht deshalb auf den Rappen die Zahl von
heute. Das ist keine Absichtserklärung, sondern Block 0071 von
`supabase/test/pruefung.sql`, und es hat eine alte Zweitrechnung gekostet:
`v_naechste_charge` hatte für Charge 1632 „466 kg in zwei Wochen" gesagt, wo
die Kaskade 388 kg sagt. Ab jetzt gibt es im ganzen Programm **eine**
Zwei-Wochen-Zahl je Charge.

**Ein Nenner.** „Im Lager" ist Eingangsware, die nicht ausgeliefert ist. Der
verkaufsfähige Anteil bezieht sich darauf — heute und über jeden Horizont, mit
demselben Nenner. Er ändert sich über die Zeit nicht: Was liegt, liegt. Was
sich ändert, ist die Zusammensetzung.

**Prozent, nicht Tonnen.** Der Betrieb weiss nicht, wie die Verkaufssaison
weitergeht — also sagt die App nicht „im März sind noch x Tonnen da", sondern
„von dem, was dann noch liegt, sind y % verkaufsfähig". Die Prognose ist eine
Aussage über die **Qualität** der liegenden Ware, nicht über ihre Menge.

**Leer ist nicht null.** Fehlt ein Koeffizient, bleibt der Anteil leer und die
Masse ist eine obere Schranke. Der Bildschirm sagt dann „höchstens" und
nennt, welche Messung fehlt. `gegenprobe/drehbuecher/03_die_sorte_ohne_waegung.md`
spielt das über sechs Szenen durch.

## 2. Die Zeitachse: August bis März

Die Ernte läuft von August bis Oktober, der Verkauf von August bis März. Die
Prognose reicht darum bis zum Saisonende (`stichtag()`, Vorgabe 31. März), in
Wochenschritten, mit 7, 14 und 28 Tagen immer dabei — und nie weiter als ein
Jahr, nie kürzer als vier Wochen: „in zwei Wochen" muss auch am 20. März noch
dastehen.

Die Schwierigkeit des Betriebsleiters ist nicht die Menge, sondern die
Reihenfolge. Er hat im Oktober alles im Haus und muss entscheiden, was wann
raus soll. Dafür braucht er zwei Zahlen nebeneinander: **wie viel** liegt, und
**wie schnell** es schlechter wird. Beides steht jetzt in derselben Tabelle,
und die Chargen-Liste lässt sich nach „In 4 Wochen" sortieren — oben steht
dann, was am wenigsten übersteht, und das ist die Charge, die zuerst raus
sollte.

## 3. Die zu Kleinen sind nicht mit der Zeit klein geworden

Der Betrieb hat darauf bestanden, und er hat recht: Ein Kürbis unter 600 g war
schon auf dem Feld zu klein. „Zu klein" und „zu gross" gehören nicht in die
Prognose, denn sie wachsen nicht mit der Lagerdauer.

Sie verschwinden trotzdem nicht aus dem Bild — sie stehen als eigenes Band da,
das über die Zeit **flach** bleibt. Genau daran liest man den Unterschied ab:
Zwei Bänder wachsen (faul, verdunstet), zwei bleiben gleich (zu klein/zu
gross, Fax erwartet). Was mit der Zeit passiert, ist der Abstand zwischen
oben und unten, und der ist nun ohne Erklärung sichtbar.

## 4. Überblick — vier Zahlen, dann der Verlauf

**Die vier Kopfzahlen** heissen jetzt Eingang · Ausgeliefert · Im Lager ·
Davon verkaufsfähig. „Verlust bis heute" ist keine Kopfzahl mehr: Der Verlust
ist der Abstand zwischen „Im Lager" und „Davon verkaufsfähig", und in dieser
Form liest ihn der Betriebsleiter, ohne dass ihn jemand definieren muss.
Unter „Im Lager" steht als Nebenzeile „im Haus gesamt" (die gute Ware nach
Verdunstung und Fäulnis, vor den Kanälen), unter „Davon verkaufsfähig" der
Weg nach vorn: *in 4 Wochen 74 % · am 31.03. **59 %***.

Fehlt ein Koeffizient, trägt die vierte Karte ein kleines **„höchstens"** vor
der Tonnenzahl, zeigt keinen Prozentsatz und sagt darunter, warum.

**Der Verlauf** zeigt je Woche vier Linien statt der alten drei: Eingang
(kumuliert), Ausgeliefert, Im Lager und Davon verkaufsfähig. Ab heute ist alles
gestrichelt — das ist die Prognose. Der Verlust ist keine Linie mehr.

**Gruppenwahl schon hier.** Alle · Sorte · Schlag · Charge gilt für den
Verlauf, für „Wohin geht der Kürbis?" und für „Was ist noch im Haus?" — eine
Wahl, drei Karten. Vorher musste man dafür auf den Reiter *Ursachen*
wechseln.

**„Wohin geht der Kürbis?"** ist die zweite Frage des Betriebs, als eine
Karte. Ein 100-%-Balken teilt den ganzen Eingang in zehn Teile (ausgeliefert,
anderer Kanal, verdunstet und faul an der ausgelieferten Ware, Fax, und was
liegt: verkaufsfähig, Kanal, Fax erwartet, faul, verdunstet). Daneben zwei
Ranglisten — *was am meisten kostet* in Tonnen und *wen es anteilig am
schlimmsten trifft* in Prozent —, und darunter ein Satz: „An der liegenden
Ware gehen zurzeit rund 182 kg je Tag verkaufsfähige Ware verloren."

Die Karte rechnet nicht selbst: `v_wohin` teilt den Eingang auf und lässt
zwei Identitäten stehen (`rest_kg`, `lager_rest_kg`). Beide haben den
Erwartungswert null; eine doppelt gezählte Portion bliebe darin sichtbar,
statt unauffällig in einer Summe zu verschwinden.

## 5. Ursachen — eine Grafik oben, die Kurven eingeklappt

Der Reiter war überladen: zwei grosse Diagramme über Lagertage gleich am
Anfang, und der Betriebsleiter musste die Modellkurve lesen, bevor er eine
Zahl sah. Jetzt steht oben eine Zeile mit fünf Zahlen für die gewählte
Auswahl — Im Lager · Verkaufsfähig heute · In 4 Wochen · Verkaufsfähig je Tag
· Verlust bis heute —, darunter **eine** Grafik, und erst dahinter die
Ursachen im Einzelnen.

**„Was wird aus der liegenden Ware?"** ist ein gestapeltes Flächendiagramm in
Prozent, von heute bis zum Saisonende. 100 % ist die liegende Eingangsware,
die fünf Bänder sind verkaufsfähig, zu klein/zu gross, Fax erwartet, faul,
verdunstet. Unten das Gute — da schaut man zuerst hin.

Die fünf Ursachen-Blöcke (Faules im Lager, Verdunstung, Sortierung, Faules
beim Abpacken, Überfüllung) beginnen jetzt alle mit Zahlen; die
Messpunkt-Diagramme und Modellkurven stehen darunter unter *Messungen und
Kurve*, zugeklappt. Wer sie will, klappt sie auf; wer nur die Zahl will, muss
nicht daran vorbei.

**Faules beim Abpacken** war „faul dargestellt" (das Wort ist vom Betrieb) —
ein Anteil ohne Zusammenhang. Er hat jetzt einen: die **Wartezeit**. Die
Angabe „Tage seit dem Waschen" gibt es seit Migration 0060, sie wurde nur nie
ausgewertet. In der Demo sagt sie deutlich, was der Betrieb vermutet hat:

| Wartezeit | Arbeiten | Faules | Bereich |
|---|---|---|---|
| 0–1 Tage | 43 | 1.31 % | 1.13 – 1.49 % |
| 2–3 Tage | 98 | 2.34 % | 2.17 – 2.51 % |
| unbekannt | 18 | 2.18 % | 1.72 – 2.65 % |

Die Bereiche überschneiden sich nicht. Zwei Tage Warten kosten rund einen
Prozentpunkt der abgepackten Ware. Das ist keine neue Frage an den Arbeiter
gewesen — nur eine Auswertung der Antwort, die er längst gibt.

**Überfüllung** heisst bei Stück-Kisten jetzt **Spielraum**, nicht
„verschenkte Marge". Bezahlt wird je Stück; jedes Gramm über der Unterkante
des Kalibers geht unbezahlt mit. Niemand sortiert auf die Kante, also ist das
kein Fehler, sondern ein Spielraum — und die neue Spalte „Lage im Band" sagt,
wo im Kaliberband die Ware tatsächlich liegt.

## 6. Chargen — sortierbar nach dem, was zuerst raus sollte

Die Tabelle hat sechs neue oder geänderte Spalten: Im Lager · Verkaufsfähig
heute (kg und %) · In 4 Wochen · Liegt seit · Verlust bis heute · Zwei Wochen
länger. Vier Spaltenköpfe sortieren. Anteile werden „am schlimmsten zuerst"
sortiert, und Zeilen ohne Anteil (keine Messung) stehen hinten statt vorn —
eine fehlende Zahl ist kein schlechter Wert.

## 7. Halle — ein Feld weniger zu tippen

In der Arbeiter-App ändert sich genau eine Sache, und sie fragt nichts Neues:
Beim Fax-Abschluss ist **„Tage seit dem Waschen" vorbelegt**, aus der letzten
abgeschlossenen Wasch-Arbeit derselben Charge. Der Hinweis darunter sagt, dass
es ein Vorschlag ist; wer ihn überschreibt, sieht den Hinweis nicht mehr.

Vorgeschlagen wird nur, was Sinn ergibt: nichts aus der Zukunft, und nichts,
was länger als zwei Wochen zurückliegt. Die Grenze ist gemessen, nicht
geraten — in der ganzen Demo-Saison steht die Zahl auf 1, 2 oder 3 Tagen. Eine
Wasch-Arbeit von vor fünf Monaten ist nicht die, aus der die Paletten auf dem
Tisch kommen; dann bleibt das Feld leer, und leer ist besser als falsch.

## 8. Was es gekostet hat

| | vorher | nachher |
|---|---|---|
| Neue Abhängigkeiten | — | keine |
| Gelöschte Tabellen oder Spalten | — | keine |
| Neue Fragen an den Arbeiter | — | keine |
| Karten auf dem Überblick | 6 | 5 (zwei wurden eine) |
| Grosse Diagramme oben auf *Ursachen* | 2 | 1 |
| Auswertung neu rechnen (dreifache Saison) | 19 550 ms | 10 735 ms |

Dass die Auswertung trotz vier neuer gespeicherter Ergebnisse schneller
wurde, ist kein Zufall, sondern vier gemessene Eingriffe; sie stehen im
Befund (§ *Tempo*) und als Kommentar an der Stelle im SQL, an der sie wirken.
