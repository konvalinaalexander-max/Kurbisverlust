# Modell- und Umsetzungsentscheidungen

Was hier steht, geht über die Spezifikation hinaus oder weicht bewusst von ihr
ab. Jede Entscheidung mit Begründung, damit sie sich später überstimmen lässt.

## Abweichungen von der Spezifikation

### `sortier_gewicht` statt `sortier_kuerbis` — lauflängenkodiert

Spec §8 sieht *eine Zeile je Kürbis* vor. Gespeichert wird stattdessen
`(gewicht_g, anzahl)` je Lauf.

Das ist für jede Auswertung verlustfrei: Nach der Dubletten-Reinigung spielt
die Reihenfolge keine Rolle mehr, und das Gewicht hat ohnehin nur 2-g-Auflösung.
An einer realistischen Datei mit 11 370 Zeilen: 821 Histogrammzeilen statt
9 172 Einzelzeilen — **91 % weniger**, bei rund 200 Läufen je Saison der
Unterschied zwischen bequem und knapp auf der 500-MB-Gratis-Stufe.

Wer doch einmal pro Kürbis rechnen will, expandiert die Zeilen mit
`cross join generate_series(1, anzahl)` — die Sicht `v_sortier_kuerbis`, die das
vorhielt, las niemand und fiel in 0048.

### Rohwerte nur als Datei, nicht in der Datenbank

Die Rohdatei liegt unverändert im Storage-Bucket `rohdaten` (Spec §4). Die
Rohwerte zusätzlich als Tabellenzeilen zu halten, würde den Speicherbedarf
verdoppeln, ohne etwas zu ermöglichen: Eine Reinigung mit anderen Parametern
lässt sich durch erneutes Einlesen derselben Datei jederzeit wiederholen.

### `auftrag.durchsatz_kg` ist neu

Beim Waschen auf Weg 1 sind die Original-Paletten längst in Kaliber-Kisten
aufgelöst — es gibt nichts mehr zu zählen. Ohne eine Mengenangabe hätte der
dort ausgelesene *Schimmel #2* keinen Nenner und wäre nicht auswertbar, obwohl
Spec §3 ihn ausdrücklich als zeitaufgelöste Messung vorsieht.

### `ausschuss_messung` ist neu

Spec §10 lässt die Arbeiter auf Weg 2 „zu gross/klein" erfassen, §8 hat dafür
keine Tabelle. `marge_messung` blieb wie spezifiziert für das Marge-Buch;
*zu klein* ist echter Verlust und gehört nicht dorthin.

### Der Reinigungs-Trichter geht auf, das Beispiel in der Spec nicht

Spec §4 nennt: 11 370 → −5 → −11 → −3 204 → **8 161**. Nachgerechnet ergibt
das 8 150. Die Differenz von genau 11 legt nahe, dass die Werte unter 100 g
selbst Teil von Dubletten-Serien waren und damit doppelt gezählt wurden.

Hier wird jede Zeile **genau einer** Stufe zugeschlagen, in der Reihenfolge aus
§4. Damit gilt immer `n_roh − n_overflow − n_klein − n_dubletten = n_gueltig`,
und der angezeigte Trichter ist nachrechenbar.

## Statistische Entscheidungen

### Verdunstung multiplikativ statt linear

Aus einer Wägung wird eine Tagesrate `r` mit
`netto_jetzt = netto_damals · (1−r)^Lagertage`.

„Prozent pro Tag mal Tage" wäre einfacher, würde aber über eine lange
Lagerdauer mehr Masse verbrauchen, als vorhanden ist — bei 0.3 %/Tag über
250 Tage rechnerisch 75 % Verlust, tatsächlich sind es 53 %. Die
multiplikative Form kann das nicht.

### Schimmel als kumulative Kurve, isoton geglättet

Jede Messung ist eine Momentaufnahme: „Bei Lagerdauer *a* war Anteil *f* der
Masse faul." Das ist bereits kumulativ — alles, was bis dahin verdorben ist.
Deshalb keine Hazard-Rate je Intervall, sondern eine Kurve `F(a)` über
Altersklassen.

Bei wenigen Stichproben kann eine spätere Altersklasse zufällig unter einer
früheren liegen. Da verdorbene Ware nicht wieder gesund wird, erzwingt ein
laufendes Maximum die Monotonie. Ein Ausreißer nach unten wird so geglättet,
einer nach oben bleibt sichtbar — die vorsichtigere Richtung.

### Jeder Anteil auf die Masse bezogen, die in seinen Schritt hineingeht

Der Schimmelanteil wird auf die **heutige** Masse bezogen, also auf die
Eingangsmasse abzüglich der bis dahin verdunsteten Menge. Sonst stiege der
gemessene Schimmelanteil mit der Lagerdauer allein deshalb, weil der Nenner
schrumpft — und Verdunstung würde ein zweites Mal als Fäulnis verbucht.

Ebenso: Der Ausschussanteil aus der CSV bezieht sich auf die Masse am Band,
nicht auf den Eingang. Nur so addieren sich die Ströme genau zur Portion. Ein
Test prüft das für jede Charge und jede Portion.

### Kein Bereich ist besser als ein erfundener

Gibt es nichts zu streuen — eine einzige Charge —, steht der Punktwert dreimal
da und `koeff_n` sagt, worauf er beruht; das Dashboard markiert solche Zahlen
als *dünne Datenlage*.

Der naheliegende Ausdruck `greatest(mittel − 1.96·sd/√n, 0)` ist hier eine
Falle: `greatest` ignoriert NULL und liefert `0`. Aus „unbekannt" würde ein
Bereich von 0 bis 1 — eine erfundene Spanne, die aussieht wie eine gemessene.

### Der Bereich entsteht aus Fehlerfortpflanzung, nicht aus drei Szenarien

Bis 0019 wurde die Kaskade dreimal gerechnet: einmal mit allen Koeffizienten an
der unteren Grenze, einmal in der Mitte, einmal oben. Das unterstellt, dass sich
alle Messfehler im Gleichtakt bewegen — und für Ströme weiter unten in der
Kaskade stimmte nicht einmal die Richtung. Weniger Verdunstung und weniger
Schimmel heisst *mehr* Masse, die bis zum Sortierband kommt, also mehr
Ausschuss: `kg_unten` lag dort über `kg_oben`.

Statt dessen wird je Strom die Ableitung nach jedem Koeffizienten mitgeführt und
der Fehler nach der tatsächlichen Korrelation zusammengesetzt. Der Fehler der
Verdunstungsrate wandert dabei von selbst in Schimmel und Ausschuss weiter.

Der Bereich lässt sich damit **nicht mehr durch Summieren gefilterter Zeilen
gewinnen** — deshalb rechnet `verlust_ranking(sorte, schlag, min_lagertage)` die
gefilterte Ansicht in der Datenbank, statt sie im Browser aufzusummieren. Die
Statistik ein zweites Mal in TypeScript zu schreiben wäre die sicherste Art,
beide auseinanderlaufen zu lassen.

Nachweis und Zahlen: `docs/STATISTIK_BEFUND.md`.

### Chargen zählen, nicht Messungen

51 Sortierläufe aus zwei Chargen sind nicht 51 unabhängige Beobachtungen —
gleicher Schlag, gleiche Ernte, gleiche Sortiereinstellung. Der Fehler wird
deshalb chargen-robust geschätzt: die gewichteten Residuen werden je Charge
aufsummiert, und die Streuung *dieser Summen* ist der Fehler. An denselben Daten
war der naive Standardfehler der Verderbskurven-Steigung 31-fach zu klein.

Dazu die t-Verteilung mit C−1 Freiheitsgraden statt 1.96: Bei zwölf Gruppen ist
die Normalverteilung eine Behauptung, keine Näherung.

### Sorten werden zum Gesamtwert gezogen, statt umzuschalten

„eigene Sorte ab n ≥ 3, sonst global" sprang. Jetzt zieht empirisches Bayes den
Sortenwert mit dem Gewicht B = τ²/(τ² + Fehler²) zum Gesamtwert. Viele
verlässliche eigene Messungen → der eigene Wert zählt; wenige oder aus nur einer
Charge → der Gesamtwert trägt.

Wichtig dabei: Jede Sorte des Stammdatensatzes bekommt eine Zeile, auch die nie
gemessene. Fällt sie heraus, steht ihr Koeffizient auf 0 — also „kein Verlust",
was schlicht falsch ist. Beim Umbau ist genau das passiert und hat in der
Simulation 37 % der Verdunstung verschluckt; `pruefung.sql` prüft es jetzt.

### Unbekannte Tara bleibt NULL, niemals 0 — wird aber hochgerechnet

Fehlt das Leergewicht eines Gebindes, bleibt das Netto der Palette NULL. Eine
unbekannte Tara als 0 zu behandeln würde die Eingangsmasse systematisch zu hoch
ansetzen und damit *jeden* Verlust in Prozent zu niedrig. „Leer ≠ 0" (Spec §8)
gilt auch für Stammdaten.

Weil `sum()` NULL-Werte überspringt, ging eine solche Lücke aber in die andere
Richtung: Die Charge wurde leichter, als sie ist. An einer Charge mit 44
Paletten, bei der 4 keine Gebindeart haben, waren das **10 %**. `eingang_netto_kg`
rechnet deshalb auf alle Paletten der Charge hoch; `eingang_netto_gemessen_kg`
hält daneben fest, was wirklich gewogen wurde, und das Dashboard warnt sichtbar.

### Weg 1 endet beim Waschen, nicht beim Sortieren

Spec §3 beschreibt Weg 1 als Lager → Sortieren → **Lager** → Waschen. Das
Modell hat den zweiten Lagerabschnitt lange nicht gekannt: Sortierte Ware galt
als aus dem Haus, ihr Alter blieb beim Sortiertag stehen. Tatsächlich steht sie
in Kaliber-Kisten wieder in derselben Halle und verdunstet und verdirbt weiter.

Nachgemessen an einer Simulation, die den zweistufigen Ablauf erzeugt:

| | vorher | nachher |
|---|---|---|
| Verdunstung | −15.3 %, Überdeckung 64 % | +1.2 %, 100 % |
| Schimmel/Fäulnis | −22.9 %, 8 % | +2.1 %, 96 % |
| Ausschuss zu klein | +2.3 %, 40 % | −0.2 %, 100 % |

Aus dem Lager ist seither, was den *letzten* Schritt hinter sich hat. Was
sortiert ist und auf das Waschen wartet, bleibt Bestand und altert weiter.

Der zweite Abschnitt wird bewusst **nicht** als eigene Kaskadenstufe gerechnet:
Verdunstung und Schimmel sind kumulativ, es genügt also, das Endalter
einzusetzen. Der Ausschuss wird dadurch auf die etwas kleinere Masse am Ende
bezogen statt auf die beim Sortieren — ein Fehler in der Grössenordnung 0.1 %
des Stroms, gegen den sich eine zweite Stufe nicht lohnt.

### Der Palox am Waschbecken misst einen Zuwachs, keinen Gesamtwert

Auf Weg 1 wird zweimal Faules aussortiert. Im Palox am Waschbecken liegt aber
nur, was **seit dem Sortieren** dazugekommen ist — der erste Teil ist längst
entsorgt. Die Kurve F(t) ist dagegen kumulativ. Wer den zweiten Palox direkt
als F(t₂) liest, setzt einen deutlich zu kleinen Wert ein, und zwar bei den
längsten Lagerdauern, wo die Kurve am steilsten ist.

Umgerechnet wird über Anteile, nicht über Kilo:

```
g = Schimmel₂ / (Durchsatz + Schimmel₂)      Anteil der Überlebenden, die es nicht schafften
1 − F(t₂) = (1 − F(t₁)) · (1 − g)
```

Der naheliegende Weg — den ersten Betrag in Kilo dazurechnen — geht schief,
weil der Durchsatz am Waschbecken schon um Verdunstung, Schimmel und Ausschuss
vermindert ist und als Bezugsmasse nicht taugt. Gemessen hat dieser Ansatz
+15.3 % Verzerrung ergeben, genauso falsch wie vorher, nur andersherum.

F(t₁) zählt dabei nur Sortierläufe, die **vor** diesem Waschgang lagen. Ohne
diese Einschränkung fliesst der Zustand später sortierter, älterer Ware in
frühe Waschgänge ein: +7.5 % auf den Waschen-Punkten.

### Der Arbeiter liest ab, die Software rechnet

Der Palox steht auf einer Waage und läuft über mehrere Arbeiten weiter. Bisher
sollte der Arbeiter selbst die Differenz zum letzten Mal bilden. Das ist genau
die Sorte Schwierigkeit, an der Erfassung scheitert — und ein Rechenfehler ist
hinterher nicht mehr erkennbar, weil die Differenz aussieht wie jede andere Zahl.

Jetzt trägt er ein, was auf der Waage steht. Beide Zahlen bleiben erhalten: der
Stand als Beleg, die Differenz als Messwert. Fällt der Stand, wurde der Palox
zwischendurch geleert — die Software erkennt das und sagt es, statt eine
negative Menge zu buchen.

### Der Warenausgang braucht keine Palettengewichte

Spec §9 sieht die Gegenprobe „Eingang = Verlust + Ausgang + Restbestand" vor;
gebaut war sie nie. Der Betrieb kennt die Gewichte einzelner Paletten beim
Ausgang nicht — und braucht sie auch nicht zu kennen. Es genügt, was ohnehin
auf dem Lieferschein steht: Datum, Sorte, und entweder Kilo oder Kistenzahl.

Kisten werden über das gemessene Kilo je Kiste umgerechnet; `masse_fehler_kg`
weist aus, wie unsicher diese Umrechnung ist, statt sie zu verschweigen.

Jede Lieferung hat ein **Ziel**, und das Ziel entscheidet über das Buch:
Kompost ist echter Verlust, Tierfutter ein anderer Kanal, Hofladen ist Verkauf.
Ohne diese Unterscheidung verschwindet Masse aus der Bilanz — und fehlende
Masse sieht in einer Bilanz immer aus wie Verlust.

### Die Massenbilanz vergleicht denselben Zeitpunkt

`v_massenbilanz` stellt das Modell neben die Sortier-CSV. Seit die Kaskade auf
Weg 1 erst beim Waschen endet, hätte sie die Masse vom Ende des zweiten
Abschnitts mit einer Wägung vom Anfang verglichen — in der Prüffixtur 40 Tage
Unterschied und 8.2 % Abweichung, die niemandes Fehler war ausser dieser
Gegenüberstellung. Verglichen wird jetzt gegen die Vorhersage **für den Tag am
Band**.

### Zufällige Entnahme heisst gedächtnislos

Der Betrieb hat klargestellt, dass sortierte Ware das Zwischenlager **nicht**
in der Reihenfolge verlässt, in der sie hineinkam — es wird ziemlich zufällig
entnommen. Präzise heisst das: An jedem Waschtag hat jede Kiste im Pool
dieselbe Chance, dranzukommen. Ein Prozess ohne Gedächtnis, also
exponentialverteilte Wartezeiten. Der Harness simulierte vorher feste
Wartespannen (30–90 Tage) und prüfte damit eine geordnetere Welt, als es sie
gibt.

Unter der gedächtnislosen Entnahme wurde die Zuordnungsfrage neu gemessen —
welcher Sortierlauf-Zustand gehört zu einem Waschgang? Der Mittelwert über
alle vorherigen Sortierläufe der Charge (eingeführt in 0025, nachdem FIFO
messbar geschadet hatte) hält: Schimmel-Verzerrung −2.4 % bis −0.8 % in den
Zufallsbahnen, Überdeckung 90–100 %. Er ist unter zufälliger Entnahme auch
theoretisch der richtige Erwartungswert — die Messung bestätigt es.

### Der Palox-Stand gilt je Station

Sortierband, Waschbecken und Hand-Linie sind verschiedene Arbeitsplätze mit
je eigenem Sammelbehälter auf eigener Waage — niemand trägt einen Palox durch
die Halle. Der „letzte Stand" war bis 0032 global: Liefen zwei Linien
gleichzeitig, verzahnten sich ihre Ablesungen und jede Differenz war falsch.

Dazu zwei Dinge aus der Praxis: Ein **Geleert-Häkchen** deckt den Fall ab, in
dem der Palox geleert und über den alten Stand hinaus neu befüllt wurde — die
Zahlenreihe sieht dann harmlos aus und nur der Arbeiter weiss es. Und die vom
Betrieb angeregte **Prüfgrösse Palettenzahl**: Die Maske zeigt die Menge je
gezählter Palette und warnt ab 120 kg — meist heisst das, eine Ablesung wurde
vergessen und die Menge zweier Arbeiten liegt auf einer.

## Umsetzung

### Klassiert wird in der Datenbank, gereinigt im Browser

Die Dubletten-Regel braucht die Zeilenreihenfolge — die gibt es nur beim Lesen
der Datei. Danach genügt das Histogramm.

Die Klassierung dagegen hängt an den Kaliber-Grenzen, die sich ändern können.
In der Datenbank gibt es dafür genau eine Wahrheit, und
`lauf_neu_klassieren(id)` wendet geänderte Grenzen auf alte Läufe an.

### Ein offener Auftrag endet, wenn der nächste beginnt

Für die CSV-Zuordnung zählt zuerst, ob die Dateizeit in ein Auftragsintervall
fällt. Ein nicht abgeschlossener Auftrag endet dabei spätestens beim Start des
nächsten Auftrags derselben Charge (höchstens aber nach 24 Stunden) — sonst
zöge ein vergessener Abschluss alle späteren Dateien an sich.

Nur eindeutige Treffer werden gesetzt. Mehrere gleich plausible Aufträge
landen in der Warteschlange, statt dass geraten wird.

### Bootstrap des ersten Betriebsleiters

Ein Trigger verhindert, dass jemand die eigene Rolle hochsetzt. Er greift nur,
wenn `auth.uid()` gesetzt ist — bei direktem SQL-Zugriff (Supabase-SQL-Editor)
ist es NULL, und genau das ist der vorgesehene Weg für den ersten Admin.

Über PostgREST ist das kein Schlupfloch: Ohne Login gibt es keine Rechte auf
`profil`, mit Login ist `auth.uid()` immer gesetzt.

### Views mit `security_invoker`

Alle Auswerte-Views laufen als Aufrufer, damit die Row-Level-Security der
zugrunde liegenden Tabellen weiter gilt und eine View kein Umweg an ihr vorbei
wird.

## Anbindung an das Erntejournal (Google Sheet)

### Charge über Schlag + Sorte, keine Chargennummer im Sheet

Spec §0/§13 sah vor, die Wareneingang-App um eine Chargennummer-Spalte zu
ergänzen. Das Integrations-Handbuch der bestehenden App zeigt aber: Das Journal
führt Schlag und Sorte sauber und schreibgeschützt (beides kommt aus der
Anbauplanung, keine Freitexteingabe). Da die Charge genau `Schlag × Sorte` ist
(Registry §7), lässt sich die Chargennummer daraus eindeutig nachschlagen — die
Spalte im fremden Sheet ist unnötig, und der einzige geplante Eingriff in die
andere App entfällt. Eine vorhandene Chargennummer-Spalte hat trotzdem Vorrang.

Zeilen, deren Schlag/Sorte nicht in der Registry stehen, werden gemeldet statt
verschluckt — dasselbe Signal wie der Kontrollwert „Nicht zugeordnet" im Sheet.

### Tara-Werte aus der App übernommen, nicht geraten

Palettengewicht (25 kg) und die Kisten-Tara (G2 1,5 · IFCO 6410/6416/6424) sind
im Code der Erntejournal-App fest hinterlegt und werden hier per Migration 0010
gesetzt. Das erspart das Nachwiegen und garantiert, dass unser berechnetes Netto
mit Spalte I des Journals übereinstimmt. „Leer = G2" ist dort Konvention und wird
beim Import genauso aufgelöst.

### Lesen per veröffentlichter CSV, nicht per Service-Account im Browser

Die Erntejournal-App spricht das Sheet über einen Google-Service-Account an —
serverseitig auf Vercel. Ein solcher Schlüssel ist geheim und darf nicht in eine
reine Browser-App. Deshalb liest diese App das Sheet über dessen „Im Web
veröffentlichen"-CSV (keine Zugangsdaten, direkt aus dem Browser ladbar). Wer die
Daten strikt privat halten will, kann stattdessen den bestehenden Service-Account
der anderen App über einen kleinen Lese-Endpunkt anzapfen — bewusst nicht der
Standardweg, weil er beide Projekte koppelt.

## Befunde aus dem Code-Durchgang

### Ein Tippfehler konnte die ganze Rechnung umwerfen (behoben, 0011)

Gefunden durch gezieltes Einspeisen unplausibler Werte: 5000 kg Schimmel auf
einer 865-kg-Palette ergaben 578 % Schimmelanteil. Der Wert lief ungebremst
durch die Kaskade — `m2 = m1 · (1 − f)` mit f = 5.78 — und erzeugte **−4135 kg
„verkaufsfähige" Masse** und 5000 kg Verlust bei 865 kg Eingang. Das Ranking
zeigte Schimmel als überwältigende Hauptursache.

Drei Stellen waren ungeschützt: die Schimmelkurve (`anteil_mono` ohne Deckel),
`schimmelanteil()` (gab den Rohwert zurück) und die Bezugsmasse des Weg-2-
Ausschusses (konnte negativ werden, wenn der Schimmelwert die Masse überstieg).

Jetzt bleiben alle Anteile in [0, 1] und Bezugsmassen bei ≥ 0. Wichtiger noch:
Unplausible Messungen werden **nicht still verworfen**, sondern in
`v_plausibilitaet` mit Diagnose aufgelistet und im Dashboard ganz oben gezeigt.
Eine Zahl, die die Auswertung ausschließt, ist fast immer ein korrigierbarer
Tippfehler — sie kommentarlos zu ignorieren wäre die schlechtere Wahl.

Schwelle: über 90 % Massenanteil. Real nicht zu erwarten, praktisch immer ein
Zahlendreher.

### `profil.aktiv` war wirkungslos (behoben, 0011)

Die Spalte existierte, aber keine Erfassungs-Policy fragte sie ab — eine
deaktivierte Person konnte weiter Messungen schreiben. Die Insert-Policies
prüfen jetzt `ist_aktiv()`.

### Der Eröffner einer Arbeit stand nicht in der Teilnehmerliste (behoben)

Wer einen Auftrag eröffnete, wurde nicht in `auftrag_teilnehmer` eingetragen.
Folge: „Dabei: noch niemand" und ein Knopf zum Mitmachen bei der eigenen Arbeit.
Die App trägt den Eröffner jetzt direkt mit ein.

### Erfasst, aber nicht ausgewertet — bewusst geprüft

- `marge_messung.art = 'nebenkanal'`: Der Enum-Wert existierte, aber die
  Nebenkanal-Mengen kommen aus der Sortier-CSV bzw. aus
  `ausschuss_messung('zu_gross')`. Eine hier erfasste Zeile wäre spurlos
  verschwunden — sie tauchte deshalb in `v_plausibilitaet` als „Nicht
  ausgewertet" auf. Die App schrieb sie nie; seit 0048 gibt es die Tabelle
  nicht mehr.
- `auftrag.geplante_paletten` und `schimmel_messung.teilgewicht` fließen
  absichtlich nicht in die Rechnung: Ersteres ist eine Planungsangabe,
  Letzteres nur ein Vermerk, dass weitergewogen wurde (die Kilos summieren
  sich ohnehin korrekt).
- `auftrag_palette.palette_id` setzt die App nicht — der Arbeiter zählt
  Paletten, er sucht keine Datensätze heraus. Die Massenzuordnung läuft über
  die Fallback-Leiter (Datum → Chargenmittel), deren Genauigkeitsstufe in
  `masse_quelle` sichtbar bleibt.

## Oberfläche: zwei Zielgruppen, zwei Tonlagen

Die Arbeiter-Oberfläche ist auf das Nötigste reduziert und in sechs Sprachen
verfügbar (Deutsch, Englisch, Ungarisch, Rumänisch, Polnisch, Portugiesisch).
Beim ersten Öffnen an einem Tag erscheinen die Flaggen — die Handys werden
weitergereicht, und was gestern eingestellt war, sagt nichts darüber, wer das
Gerät heute in der Hand hat.

Fachbegriffe sind dort verschwunden: Statt „Weg 1 / Weg 2" wählt der Arbeiter
**Sortieren**, **Waschen** oder **Waschen + Sortieren** — das ist, was er tut.
Die Zuordnung auf `weg`/`station` passiert an einer Stelle (`src/lib/taetigkeit.ts`).

Nur „Sortieren" und „Waschen + Sortieren" anzubieten wäre zu wenig gewesen:
Das Waschen auf der Maschinen-Linie ist ein eigener Arbeitsgang, und genau dort
wird der zeitversetzte zweite Schimmel gemessen (Spec §3). Ohne diese Auswahl
gäbe es dafür keine Erfassung.

Erklärender Text steht ausschließlich im Betriebsleiter-Bereich — dort ist er
nötig, weil dort Entscheidungen getroffen werden.

## Wiegen gehört ans Zählen (0012)

Es ist dieselbe Person, die die Paletten zählt und sie wiegt. Ein eigener
Reiter „Wiegen" bedeutete: zählen, Reiter wechseln, die eben gezählte Palette
in einer Liste wiederfinden, wiegen, zurückwechseln. In der Halle passiert das
nicht — die Messung unterbleibt.

Jetzt fragt die App bei jeder gezählten Palette einmal: wiegen oder nur zählen?
Wer nicht wiegt, ist mit einem zweiten Tipp durch.

### Keine Palettenliste mehr

Die Palette wurde bisher aus einer Liste gesucht. Bei hunderten Paletten je
Charge, von denen viele auf das Kilo gleich schwer sind, ist das weder
bedienbar noch verwechslungssicher. Der Arbeiter tippt stattdessen ab, was auf
dem Zettel steht: Eingangsdatum und Eingangsgewicht. Das aktuelle Datum kennt
die App selbst.

Die Felder dafür gab es in `verdunstung_wiegung` bereits; `palette_id` bleibt
schlicht leer.

### Nebeneffekt: die Masse wird genauer statt geschätzt

`auftrag_palette.wiegung_id` verbindet Zählung und Wägung. Eine gewogene
Palette bringt ihr Eingangsgewicht damit **exakt** mit — die Fallback-Leiter in
`v_auftrag_palette_masse` hat eine neue oberste Stufe (`gewogen`), vor
Datums- und Chargenmittel. Damit verbessert jede Wägung nicht nur die
Verdunstungsrate, sondern auch die Bezugsmasse für Schimmel und Ausschuss.

Ohne die Verbindung wären Zählung und Wägung zwei unverbundene Zeilen über
dieselbe Palette gewesen — genau die Art von Phantom-Verknüpfung, nach der im
Durchgang zuvor gesucht wurde.

### Was an welcher Station anfällt

| Station | Paletten | Wiegen | Faule | Klein/gross | Menge |
|---|---|---|---|---|---|
| Sortieren (Maschine) | zählen | nein | ja | — | — |
| Waschen (Maschine) | — | — | ja | — | ja |
| Waschen + Sortieren (Hand) | zählen | Frage bei jeder | ja | ja | — |

Beim Sortieren an der Maschine wird nie gewogen — die Frage erscheint dort gar
nicht. Beim Waschen gibt es keine Paletten mehr (die Ware liegt in
Kaliber-Kisten), deshalb entfällt der Zähler; die verarbeitete Menge wird beim
Abschluss erfasst, damit der dort ausgelesene Schimmel einen Nenner hat.

### Durchschnittsgewicht eines Kürbisses

Aus einer gewogenen Palette folgt „kg je Kiste". Für das Gewicht eines
*einzelnen* Kürbisses fehlt eine Angabe, die nur der Arbeiter machen kann:
wie viele Kürbisse in einer Kiste liegen. Das Feld ist freiwillig
(`verdunstung_wiegung.kuerbisse_pro_kiste`); ohne Eintrag bleibt die Spalte
leer statt einen erfundenen Wert zu zeigen. `v_wiegung_kennzahl` führt beides.

Auf der Maschinen-Linie liefert die Sortier-CSV jedes Einzelgewicht ohnehin —
diese Angabe schließt die Lücke für die Hand-Linie.

### Entfernt: „Kisten" (Überfüllung)

Der Reiter maß den Überschuss der 8-kg-Kisten: Bezahlt wird ein Fixpreis ab
8 kg, real wiegen sie 8.1–8.5 kg, und die Differenz ist verschenkte Ware
(Spec §2, Buch B). Für den Arbeiter war unklar, was da gemessen wird, und die
Erfassung gehört fachlich eher zur Abpackung als zur Verarbeitung.

Tabelle und Auswertung bleiben unangetastet — nur die Erfassung im
Arbeiter-UI ist weg. Solange niemand misst, bleibt diese eine Zeile im
Marge-Buch leer; alles andere rechnet unverändert.

## Die fertige Palette (0013)

Nach dem Waschen wird in **neue** Paletten gepackt — die Ware landet nicht
wieder in derselben. Deshalb gab es dort bisher gar nichts zu erfassen, obwohl
genau hier die interessanteste Frage der Hand-Linie steckt:

```
Soll:  Palette + 32 Kisten × Tara + 32 × 8 kg
Ist:   Palette + 32 Kisten × Tara + 32 × x     →  x = ?

x = (Brutto − Palettentara − Kisten × Kistentara) / Kisten
```

Bezahlt wird ein Fixpreis je Kiste ab 8 kg. Jedes Kilo über x = 8 ist
verschenkte Ware und gehört ins **Marge-Buch**, nie ins Verlust-Buch — die Ware
ist verkauft, nur nicht bezahlt. Ein Test prüft genau das.

Das ist dieselbe Größe, die der frühere Reiter „Kisten" messen sollte. Er
scheiterte daran, dass niemand verstand, was da gemessen wird: Er fragte nach
einem Sammelgewicht mehrerer Kisten, ohne Bezug zu etwas, das am Band steht.
Die fertige Palette dagegen steht da, hat eine ablesbare Kistenzahl und kommt
auf die Waage.

`ausgang_wiegung` hält die Rohwerte (Brutto, Kisten, Gebindeart), nicht das
Ergebnis. `v_ausgang_kennzahl` rechnet daraus x, den Überschuss je Kiste und —
wenn die Kürbisse je Kiste erfasst wurden — das Gewicht eines einzelnen
Kürbisses. Die Soll-Grenze steht als Einstellung (`soll_kg_pro_kiste`), nicht
als Zahl im Code.

`v_koeff_ueberfuellung` las zunächst beide Quellen: die neuen Palettenwägungen
und ältere `marge_messung`-Zeilen, damit kein bereits erfasster Wert seine
Wirkung verlor. Seit 0048 liest sie nur noch die Wägungen — der Alt-Kanal ist
weg, und die Migration bricht ab, falls er doch Zeilen hält.

## Arbeiten abbrechen (0013)

Eine Arbeit wird mit der falschen Charge eröffnet, ein Handy fällt aus. Bisher
liess sich so ein Auftrag nicht loswerden — er zählte für immer mit.

**Abbrechen löscht nicht.** `auftrag.abgebrochen_ts` markiert die Arbeit; die
erfassten Zeilen bleiben als Spur stehen, zählen aber in keiner Auswertung mehr
mit. Aus der Liste des Arbeiters verschwindet sie, dem Betriebsleiter bleibt sie
sichtbar. Eine zugeordnete Sortier-CSV wandert zurück in die Warteschlange,
sonst hinge sie an einer Arbeit, die nicht mehr gilt.

### Warum nicht einfach löschen

`verdunstung_wiegung` und `sortier_lauf` hängen mit `on delete set null` am
Auftrag. Ein blosses `delete from auftrag` hätte deren Zeilen **verwaist**
zurückgelassen: Die Wägungen zählten weiter in die Verdunstungsrate — die
wichtigste Koeffizientenquelle überhaupt —, ohne dass irgendwo stünde, wozu sie
gehörten. Genau die Sorte Phantom-Daten, nach der im Durchgang zuvor gesucht
wurde.

`auftrag_endgueltig_loeschen()` (nur Betriebsleiter) räumt deshalb zuerst diese
beiden Tabellen auf und löscht dann den Auftrag. Ein Test weist nach, dass
danach keine verwaiste Wägung übrig bleibt.

### Filter an jeder Stelle

Abgebrochene Arbeiten aus `v_auftrag_masse` zu nehmen genügt nicht:
`v_verdunstung_messung` und `v_wiegung_kennzahl` lesen `verdunstung_wiegung`
direkt und brauchten einen eigenen Filter. Ohne ihn hätte eine abgebrochene
Arbeit die Verdunstungsrate weiter beeinflusst.

## Tempo: die Auswertung lief in Supabases Zeitlimit (0015)

Beim Öffnen der Auswertung brach Supabase ab:
`canceling statement due to statement timeout`. Gemessen an der Demo-Saison:

| Ansicht | vorher | nachher |
|---|--:|--:|
| `v_hochrechnung` | 2 553 ms | 77 ms |
| `v_verlust_ranking` | 2 441 ms | 72 ms |
| `v_marge_buch` | 3 895 ms | 98 ms |
| alle zwölf zusammen | > 9 000 ms | ~500 ms |

Supabase bricht nach 8 Sekunden ab, und das Dashboard holt ein Dutzend
Ansichten gleichzeitig.

Zwei Ursachen, beide dieselbe Sorte Fehler — **etwas Teures wurde pro Zeile
statt einmal gerechnet**:

1. `schimmelanteil()` sieht wie eine billige Nachschlagefunktion aus, fragt
   intern aber die ganze Kette `v_schimmel_kurve → v_schimmel_beobachtung →
   v_auftrag_masse` ab. In der Select-Liste von `v_kaskade` bedeutete das
   60 Aufrufe à 16 ms — mit der vollständigen Kette hinter jedem. Die Kurve
   liegt jetzt einmal in einer materialisierten CTE und wird angejoint.

2. `v_auftrag_palette_masse` holte Chargen- und Datumsmittel über seitliche
   Unterabfragen: für jede der 286 gezählten Paletten neu, inklusive einer
   Aggregation über alle 535 Eingangspaletten. Jetzt werden diese Mittel
   einmal gebildet und normal angejoint.

Dieselbe Falle steckt in jeder Funktion, die intern eine View abfragt: Sie
sieht am Aufrufort billig aus und ist es nicht.

### Nachgewiesen, dass sich die Zahlen nicht geändert haben

Eine Optimierung, die Ergebnisse verändert, ist ein Fehler. Verdunstung,
Massenbilanz und Marge-Buch kamen auf dieselben Werte. Nur der Schimmel wich
ab — 24.0 t gegen 18.8 t. Die Gegenprobe (Plausibilitäts-Schwelle kurz zurück
auf 90 %) ergab wieder exakt 24.0 t: Die Differenz stammt aus der
Schwellenänderung in 0014, nicht aus dem Umbau.

Nebenbei zeigt das, wofür die Plausibilitätsprüfung da ist: **Ein einziger
vertippter Wert** (4500 statt 450 kg) hatte die Schimmel-Schätzung der ganzen
Saison um 28 % aufgebläht.

### Tempo-Prüfung im Testlauf

Stufe 5 von `supabase/test/run.sh` lädt die Demo-Saison, misst alle zwölf
Dashboard-Ansichten und schlägt über 3 Sekunden fehl — großzügig gegenüber
langsamer CI-Hardware, aber weit unter den 8 Sekunden, bei denen Supabase
abbricht.

## Die Auswertung wird gespeichert, nicht bei jedem Hinschauen gerechnet (0016)

Nach 0015 lief die Auswertung mit der Demo-Saison in einer halben Sekunde —
aber ein Lasttest mit **5 040 Paletten, 840 Arbeiten und 255 300
Gewichtsstufen** (rund das Dreifache einer echten Saison) brauchte wieder
4.1 Sekunden. Auf Supabases geteilter CPU wäre das ein Abbruch, und mit jeder
weiteren Palette würde es schlimmer.

Das Feilen an einzelnen Abfragen war ein Verschieben des Symptoms. Die Ursache
liegt in der Bauart: Die Auswertung ist ein tiefer Baum, der bei jedem Lesen
von den Rohdaten aufwärts neu gerechnet wurde. `v_kaskade` steckt in drei
Dashboard-Ansichten — und wurde dreimal gerechnet.

Eine Saisonauswertung ist aber keine Live-Anzeige. Sie darf ein paar Minuten
alt sein. Vier teure Knoten liegen deshalb jetzt als materialisierte Ansichten
gespeichert:

| gespeichert | verdichtet |
|---|---|
| `mv_sortier_lauf_masse` | 255 300 Gewichtsstufen → 300 Zeilen |
| `mv_auftrag_masse` | 12 600 Palettenzählungen → 840 Zeilen |
| `mv_kaskade` | die Hochrechnung selbst |
| `mv_kaliber_verteilung` | wächst mit jeder CSV |

**Gemessen am Lasttest:**

| | vorher | nachher |
|---|--:|--:|
| Dashboard (zwölf Ansichten) | 4 120 ms | **203 ms** |
| Auswertung neu rechnen | — | 797 ms |

Entscheidend ist nicht der Faktor 20, sondern dass die Lesezeit jetzt von der
**Ergebnisgröße** abhängt statt von der Datenmenge. Zehnmal so viele Paletten
verlängern das Neuberechnen, nicht das Anschauen.

### Die gewohnten Namen bleiben

`v_sortier_lauf_masse`, `v_auftrag_masse`, `v_kaskade` und
`v_kaliber_verteilung` gibt es weiterhin — sie zeigen jetzt auf die
gespeicherten Daten. Damit sehen App, SQL-Editor und Prüfabfragen dasselbe;
es gibt weiterhin genau eine Wahrheit.

Kein `drop … cascade` nötig: Die Wrapper haben exakt dieselben Spalten und
Typen, also genügte ein Ersetzen — die gesamte Auswertung darüber blieb stehen.

### Was man dafür in Kauf nimmt

Nach einer Erfassung ist die Auswertung erst nach dem nächsten Rechnen aktuell.
Das ist sichtbar gemacht statt versteckt:

- `auswertung_stand` hält fest, wann zuletzt gerechnet wurde und wann zuletzt
  etwas erfasst wurde. Die Erfassungstabellen melden das selbst per Trigger —
  auf Anweisungsebene, damit ein Import mit 500 Paletten einen Aufruf auslöst
  und nicht 500.
- Das Dashboard zeigt den Stand und rechnet beim Öffnen selbst nach, wenn seit
  der letzten Rechnung etwas erfasst wurde. Unter einer Sekunde, also
  unmerklich. Dazu ein Knopf zum Erzwingen.

Die Prüfabfragen rechnen an denselben Stellen nach — sonst würden sie den Stand
von vorhin prüfen.

### Braucht es eine bezahlte Stufe?

Nein. Der Engpass war nie die Rechenleistung, sondern die Bauart. Bei
dreifacher Saisongröße liegt das Dashboard bei 203 ms und das Neuberechnen bei
0.8 s — auf einer Gratis-Instanz mit deutlich langsamerer CPU also
komfortabel innerhalb der 8-Sekunden-Grenze. Der Speicherbedarf (~250 000
Zeilen Sortiergewichte) liegt weit unter den 500 MB der Gratis-Stufe.

### Abgesichert

Stufe 6 von `supabase/test/run.sh` erzeugt den Lasttest, rechnet die Auswertung
und misst. Über 2 Sekunden fürs Dashboard oder 5 Sekunden fürs Neuberechnen
schlägt der Lauf fehl. Ohne diese Stufe würde die Zusage „skaliert" mit der
Zeit verrotten.

---

## Dieselbe Datei richtet ein und aktualisiert

### Das Problem

`setup.sql` begann mit einer Sperre: Existiert die Tabelle `charge` schon,
bricht das Skript ab — „Das Setup wurde bereits eingespielt". Gedacht war das
als Schutz vor dem versehentlichen zweiten Klick.

Der Schutz war eine Sackgasse. Eine einmal eingerichtete Datenbank konnte nie
wieder etwas Neues bekommen. Auf dem Hof lief eine Datenbank, die vor
Migration 0016 eingerichtet worden war; alles danach — das gespeicherte
Rechnen, das Schimmelmodell, die Fehlerfortpflanzung, der Warenausgang — ist
dort nie angekommen. Gemerkt hat es niemand, bis die App auf „Auswertung"
klickte und Supabase antwortete: *Could not find the function
public.auswertung_aktualisieren without parameters in the schema cache.*

Das ist die unangenehme Sorte Fehler: Er entsteht durch etwas, das gar nicht
passiert ist, und zeigt sich Monate später an einer ganz anderen Stelle.

### Die Entscheidung

Keine zweite Datei, kein Versionszähler, keine Migrations-Werkzeugkette.
Stattdessen läuft dieselbe `setup.sql` auf jeder Datenbank durch, egal auf
welchem Stand sie ist. `0000_aktualisierung.sql` räumt vorweg alles weg, was
sich ohnehin nur ausrechnet — Ansichten, gespeicherte Auswertungen,
Funktionen, Zugriffsregeln, Auslöser. Danach sieht die Datenbank für den Rest
des Skripts aus wie eine frische, und die Migrationen bauen das Rechenwerk
vollständig neu auf. Tabellen und ihr Inhalt werden nicht angefasst; die
Definitionen sind so geschrieben, dass sie eine schon vorhandene Tabelle,
einen schon vorhandenen Typ, einen schon vorhandenen Index einfach stehen
lassen.

Weil alles in einer Transaktion läuft, gibt es kein halb Aktualisiertes:
entweder ganz durch, oder die Datenbank steht unverändert da wie vorher.

### Warum die Sperre nicht bloss gelockert wurde

Naheliegend wäre gewesen, die Migrationen der Reihe nach nachzuspielen und
schon Vorhandenes zu überspringen. Der Versuch scheitert an den
Abhängigkeiten: Auf einer bestehenden Datenbank existieren an einer Stelle
mitten in der Historie mehr Ansichten als bei einer Neueinrichtung, und ein
`drop … cascade` reisst dann Dinge mit, die kein späterer Schritt wieder
aufbaut. Wegräumen und komplett neu bauen hat diese Stelle nicht.

### Abgesichert

Stufe 3 von `supabase/test/run.sh` lässt `setup.sql` ein zweites Mal laufen,
Stufe 3b richtet eine Datenbank auf dem Stand von 0015 ein, legt Daten und
eine von Hand geänderte Einstellung hinein und spielt dann die heutige
`setup.sql` darüber. Geprüft wird dreierlei: dass die Daten noch da sind, dass
`auswertung_aktualisieren()` rufbar ist — genau die Funktion aus der
Fehlermeldung — und dass das Schema **Objekt für Objekt** dem einer
Neueinrichtung gleicht. Letzteres über `supabase/test/fingerabdruck.sql`:
1412 Spalten, Ansichten, Funktionen, Indizes, Regeln, Auslöser, Bedingungen
und Rechte als sortierte Liste, zweimal gezogen, mit `diff` verglichen. „Ist
ohne Fehler durchgelaufen" wäre keine Zusage gewesen.

### Und der Schema-Cache

Zwischen Datenbank und App sitzt PostgREST und merkt sich, welche Funktionen
es gibt. Am Ende von `setup.sql` steht deshalb `notify pgrst, 'reload schema'`
— sonst kann die App eine gerade angelegte Funktion noch eine Weile für nicht
vorhanden halten und dieselbe Meldung zeigen wie vorher, obwohl alles da ist.

---

## Die Demo-Saison gehört in die App, nicht in eine Datei

Ein leeres Dashboard sagt nichts darüber, ob das Werkzeug taugt. Die
erfundene Saison gab es zwar schon, aber nur als SQL-Datei: auf GitHub
suchen, Rohtext kopieren, im SQL-Editor des Datenbank-Anbieters einfügen,
Run — und zum Aufräumen dasselbe nochmal mit einer zweiten Datei. Das ist
ein Umweg über ein Werkzeug, das mit der App nichts zu tun hat. Niemand
macht ihn zweimal freiwillig, und wer die App zum ersten Mal öffnet, macht
ihn gar nicht.

Jetzt sind es zwei Funktionen, `demo_daten_laden()` und
`demo_daten_entfernen()`, und zwei Knöpfe: unter Stammdaten → Demo-Daten,
und — solange noch gar nichts erfasst ist — direkt auf der leeren
Auswertung, dort wo die Leere auffällt.

Die Saison selbst steht **nur noch an einer Stelle**, in
`0034_demo_knopf.sql`. Die beiden SQL-Dateien rufen ab jetzt bloss die
Funktionen auf. Zwei Fassungen derselben erfundenen Saison hätten
zwangsläufig auseinandergelebt, und das wäre lange niemandem aufgefallen.

### Was dabei auffiel: PUBLIC durfte alles

Die neuen Funktionen laufen als `security definer`, also mit den Rechten des
Eigentümers und an den Zeilenregeln vorbei. Anders geht es nicht — die Demo
datiert Arbeiten zurück, legt abgeschlossene Aufträge an und erfasst
Messungen im Namen anderer. Das Tor davor ist die Prüfung auf den
Betriebsleiter.

Beim Nachmessen zeigte sich, dass das Tor offenstand: Postgres gibt jeder
neu angelegten Funktion automatisch der Rolle PUBLIC das Ausführungsrecht,
und ein `grant execute … to authenticated` nimmt das nicht zurück, es kommt
nur obendrauf. `demo_daten_laden()` liess sich als `anon` aufrufen, also
ohne jede Anmeldung.

Bei den übrigen Funktionen war dieselbe offene Tür folgenlos — sie laufen
mit den Rechten des Aufrufers, und `anon` hat auf keine einzige Tabelle
Zugriff. Trotzdem ist sie jetzt für alle zu (`0035_nur_angemeldete.sql`).
Dass Auslöser weiterhin feuern, obwohl PUBLIC das Ausführen entzogen ist,
ist nachgemessen und nicht vermutet: Postgres prüft dieses Recht beim
Anlegen des Auslösers, nicht bei jedem Schreibvorgang.

Damit das nicht wieder einreisst, verlangt `pruefung.sql` jetzt zweierlei:
dass **keine** Funktion in `public` für PUBLIC ausführbar ist, und dass
**jede** für `authenticated` erreichbar ist. Wer künftig eine Funktion ohne
eigenen `grant` anlegt, merkt es beim nächsten Testlauf statt nie.

---

## Das Erscheinungsbild: Betriebssoftware, nicht Bastelprojekt

### Ausgangslage

Die Oberfläche war funktional, sah aber danach aus, was sie war: gewachsen.
Beige Flächen, orange Pillen, Emojis in der Navigation, jede dritte Angabe
per Inline-Stil formatiert. Dazu handfeste Fehler, die nie jemand gesehen
hat, weil kein Test einen Bildschirm ansieht: Im Kaskadenbild stand
`var(--rahmen)` — eine CSS-Variable, die es nie gab; der Ersatzwert griff,
nur eben im Dunkelmodus mit demselben Hellgrau wie im Hellen. Die
Beschriftung der Grafik war oben und unten abgeschnitten. Jede Handy-Seite
lief 2 px über die Bildschirmbreite. Und der Warenausgang stürzte beim
Formatieren des Datums ab, weil eine State-Variable namens `datum` die
gleichnamige Formatierungsfunktion verdeckte.

### Der Prüfstand kam vor dem Umbau

`pruefstand/bildschirme.mjs` rendert jede Seite der App in einem echten
Browser — Handy und Desktop, hell und dunkel, 88 Screenshots — und meldet
Konsolenfehler und wagrechtes Überlaufen. Supabase läuft dabei nicht:
Playwright fängt jede Anfrage ab und antwortet aus JSON-Abzügen, die
`pruefstand/daten_dumpen.sh` aus der lokalen Demo-Datenbank zieht. Die App
sieht echte Datenformen und echte Zahlen, nur ohne Netz. Erst dieser
Prüfstand hat die vier Fehler oben sichtbar gemacht — „npm run build läuft
durch" hätte keinen davon gefunden.

### Die Gestaltungsentscheidungen

- **Eine Akzentfarbe.** Das Kürbis-Orange bleibt die Identität, wird aber
  Signal statt Anstrich: Hauptaktion, aktiver Reiter, sonst nichts. Flächen
  sind neutrales Grau, Karten weiss mit feinem Rand. Grün/Rot/Blau/Gelb
  sind Zustände, die Strom-Farben der Auswertung (Verdunstung, Schimmel,
  Ausschuss, Nebenkanal) sind überall dieselben — als Variablen, damit der
  Dunkelmodus mitzieht.
- **Inter, mitgebaut.** Die Schrift kommt als npm-Paket in den Build statt
  von einem CDN — in der Halle ist das Netz wackelig. Zahlen stehen überall
  in Tabellenziffern, sonst tanzen Spalten beim Vergleichen.
- **Navigation wie Werkzeug.** Kopfleiste weiss mit Marken-Kachel,
  darunter Reiter mit Unterstreichung und kleinen Strichzeichen — von Hand
  als einfache Geometrie, keine Icon-Bibliothek. Die Ebenen-Wahl im
  Dashboard ist ein Segment-Umschalter, kein Knopf-Trio.
- **Zwei Nutzergruppen, zwei Dichten.** Arbeiter-Seiten bleiben schmal
  (560 px), gross und berührungstauglich — 44 px Mindesthöhe überall.
  Betriebsleiter-Seiten werden breiter (1040 px) und dichter: Kennzahlen
  als Kacheln, Tabellen mit ruhigen Linien und Zeilen-Hover.
- **Das Kaskadenbild neu vermessen.** Alle Y-Koordinaten leiten sich jetzt
  aus benannten Höhen ab, die Abzweigungen schliessen bündig an, das
  abgezweigte Stück ist oben im Eingangs-Band markiert, und die
  Restmenge trägt ihre Beschriftung im Balken.

Was bewusst gleich blieb: jede Karte, jede Zahl, jeder Text und jeder
Rechenweg. Der Umbau ist Erscheinung und Fehlerbehebung — kein einziger
Datenbank-Aufruf hat sich geändert.

---

# Vierte Prüfrunde (3. September): die Kette in beide Richtungen

Die Prüfung nach `docs/archiv/PROMPT_PRUEFUNG.md` ging jede Zahl im Dashboard
rückwärts bis zur Rohzeile und jede Maske vorwärts bis zum Balken. Was dabei
entschieden wurde, steht hier; die Messungen dahinter in
`STATISTIK_BEFUND.md`, die Annahmen in `ABLAUF.md`.

## Die Kette rückwärts: sechs Befunde zwischen Waage und Balken (0036)

Alle sechs am laufenden System nachgemessen, alle in `0036_kette.sql`
behoben, alle seither in `pruefung.sql` festgehalten:

1. **Ohne Wägung stand die Verdunstung auf 0 kg, mit Bereich 0–0.** Der
   Koeffizient war `coalesce(mittel, 0)`. Eine Zahl, die aussieht wie
   gemessen und das Gegenteil sagt. Jetzt bleibt ein Koeffizient ohne
   Messung NULL, der Strom ist NULL, das Ranking sagt „nicht gemessen", und
   die Kennzahl heisst „Lagerverlust mindestens", solange ein Strom fehlt.
   Die Regel „Leer ist nicht null" galt für Tara und Messwerte; für die
   Koeffizienten galt sie nicht.
2. **Messungen ohne Nenner verschwanden spurlos.** 80 kg Schimmel an einem
   Auftrag ohne gezählte Paletten und 112 kg an einem Waschgang ohne
   verarbeitete Menge erzeugten keinen Punkt im Modell, und nichts meldete
   es. `v_plausibilitaet` führt sie jetzt als „Ohne Nenner" mit dem Rat, was
   nachzutragen ist. `pruefung.sql` verlangt seither, dass jedes erfasste
   Kilo Faules entweder angekommen oder gemeldet ist: Σ erfasst = angekommen
   + gemeldet.
3. **Die Palox-Waage zeigt brutto, der Behälter wiegt 45 kg.** Nach dem
   Leeren und bei der ersten Ablesung galt der volle Stand als Menge, samt
   Behälter: jedes Leeren buchte 45 kg Schimmel. Die Tara ist jetzt eine
   Einstellung (`palox_tara_kg`), und die Menge wird aus den Ständen
   abgeleitet (`v_schimmel_menge`), nicht aus dem Kilo-Wert, den die App
   damals gebildet hat. Der Stand bleibt, wie er abgelesen wurde; ändert sich
   die Tara, ändert sich die Menge mit.
4. **Der Lagerbestand bekam das Alter der ganzen Charge.** Wird zuerst
   verarbeitet, was zuletzt kam, sind die übrigen Paletten die ältesten. In
   der Demo lagen sie drei bis sechs Tage neben dem Chargenmittel, bei
   k = 1.6 rund 4.5 % Verderb. Das Alter kommt jetzt aus den *nicht
   gezählten* Paletten, deren Eingangsdaten bekannt sind.
5. **Der Restbestand war zu klein, die Lücke zu gross.** Er rechnete „zu
   klein" und „zu gross" schon heraus, obwohl beides noch physisch im Lager
   liegt. In der Demo fehlten 12.5 t; die Lücke der Massenbilanz fiel von
   4.8 % auf 2.1 %, als der Restbestand die Masse nach Verdunstung und
   Verderb wurde.
6. **Die Kistenzahl der Überfüllung war fest verdrahtet** (8.0), die
   Kennzahl je Palette las die Einstellung. Bei 9 kg ergab das −15 t
   „Überschuss" aus Kisten, die es nie gab. Beides liest jetzt dieselbe
   Einstellung.

Nebenbefund, ohne Wirkung auf Zahlen: Postgres gibt jeder neuen Funktion das
Ausführungsrecht für PUBLIC. `palox_tara_kg()` war so anonym aufrufbar, und
`pruefung.sql` hat es gemeldet. `0035` setzt seither die Vorgabe für alle
künftigen Funktionen um (`alter default privileges … revoke execute … from
public`), statt es bei jeder Funktion einzeln zu hoffen.

## Die Kette vorwärts: die Masken werden gefahren, nicht gelesen

Der Bildschirm-Prüfstand rendert Seiten; er beweist nicht, dass ein
eingegebener Wert im Balken ankommt. Deshalb `pruefstand/kette.mjs`: Ein
echter Browser erfasst über die Masken eine komplette Arbeit (neue Arbeit
mit Käufer, Paletten zählen und eine wiegen, Palox ablesen, zu klein und zu
gross, Abschluss mit den Fragen). Jede Schreibanfrage an Supabase wird
mitgeschnitten. `pruefstand/kette_pruefen.sh` spielt genau diese Anfragen
in eine echte Postgres ein und prüft, ob jeder Wert in der Auswertung steht.

Das fängt, was der Bildschirm-Prüfstand nicht fangen kann: Der Prüfstand
nimmt jedes POST entgegen, Postgres nicht. Der erste Lauf fand genau so
einen Fall: Die App schickte beim Abschluss `ende_ts` von der Uhr des
Telefons. Geht die vor oder nach, verletzt das die Regel `ende_nach_start`,
und der Abschluss scheitert, ohne dass der Bildschirm es je gezeigt hätte.
Das Ende setzt jetzt der Server (Auslöser `auftrag_ende_setzen`), die App
schickt nur noch den Status. Beide Prüfstände laufen in `run.sh`.

## Der Palox-Sockel: geschätzt, ausgewiesen, nur gesetzt, wenn belegt (0037)

Der Betrieb hat den Palox als Kompost-Behälter beschrieben: Neben Faulem
landen darin Erde, Hagelnarben, Schnittfehler, rund 2 % der Masse, die nie
gefault hat. Das Modell las alles als zeitabhängigen Verderb. Was das kostet,
sagt die Simulation (25 Saisons, Saisonmitte, 2 % Sockel, Modell ohne
Sockel): Schimmel **+40 %**, Überdeckung **0 %**.

### Die Entscheidung: der Sockel ist ein Parameter mit Nachweispflicht

Der gemessene Anteil ist `a₀ + (1 − a₀)·F(t)`. `a₀` wird über ein Gitter
(0–10 %, Schritt 0.25 %) mitgeschätzt: Für jeden Kandidaten werden die
Verarbeitungspunkte bereinigt, die Weibull-Gerade angepasst und der Fehler im
Anteilsraum über alle Punkte gebildet. Lagerkontrollen tragen keinen Sockel
(wer eine Palette aufmacht, zählt Faules, keine Erde); die Waschen-Punkte
tragen ihn in derselben Form.

Die eigentliche Entscheidung ist die Regel, wann der Sockel gilt. Zwei Regeln
wurden gemessen, je 25 Saisons, 12 Palettenwägungen:

| Regel | Sockel-Lage, Saisonmitte | Selektion, Saisonende | Selektion, Saisonmitte |
|---|---|---|---|
| ohne Sockel (vorher) | Schimmel +40.5 %, 0 % | −2.0 %, 100 % | +8.7 %, 96 % |
| kleinster Sockel im 1-%-Band | **0.0 %, 100 %** | −13.3 %, 12 %, **3.8 t Sockel erfunden** | +7.7 %, 76 %, 3.0 t erfunden |
| nur wenn F-Test belegt | +19.7 %, 48 % | −3.7 %, 88 %, 0.6 t erfunden | +8.6 %, 84 %, 0.6 t erfunden |

Die lockere Regel trifft in der Sockel-Lage genau, erfindet aber unter
Selektion Tonnen von Grundaussortierung, die es nicht gibt, und drückt den
Schimmel um 13 %. Die strenge Regel (das Modell ohne Sockel muss nach einem
F-Test mit Freiheitsgraden nach Chargen nachweisbar schlechter passen)
halbiert die Verzerrung in der Sockel-Lage und erfindet fast nichts. Gewählt
ist die strenge.

Warum keine Schwelle dazwischen: Das Verhältnis „Fehler ohne Sockel / bester
Fehler" liegt bei echtem Sockel am Saisonende (Median 1.36) genauso wie bei
Selektion ohne Sockel (1.32); nur in der Saisonmitte hebt sich der echte
Sockel ab (1.58, Schwelle 1.57). Keine Schwelle trennt die beiden Lagen, sie
verschiebt nur, wo die Zahl danebenliegt. Gewählt ist die Seite, die nichts
erfindet: Wo der Sockel nicht belegt ist, steht er auf 0, und der Bereich
(Profil über dieselbe Schwelle) sagt, wie gross er sein könnte. Die
Überdeckung dieses Bereichs liegt bei 68–84 %; die Verzerrung des
Schimmel-Balkens bei echtem Sockel am Saisonende bleibt bei rund +46–48 %,
unverändert gegenüber vorher (vollständige Matrix in `STATISTIK_BEFUND.md`:
Saisonmitte +22.7 % bei 44 % Überdeckung, Saisonende +48.3 % bei 0 %). Das
steht so in `ABLAUF.md` und als Frage 5 in
`FRAGEN.md`: Eine Angabe beim Leeren des Palox, wie viel davon nicht faul war,
wäre die Messung, die das Schätzen erübrigt.

### Zwei bewusste Vereinfachungen

- **Keine Kovarianz zwischen a₀ und (λ, k).** Der Sockel geht als eigener
  globaler Parameter mit eigener Varianz in die Fehlerfortpflanzung
  (∂G/∂a₀ = M1, ∂S/∂a₀ = −M1·F); dass ein anderes a₀ auch ein anderes λ und
  k ergäbe, wird nicht mitgeführt. Die gemessenen Überdeckungen enthalten
  diese Vereinfachung bereits.
- **Das Gitter macht das Modell rund vierzigmal so teuer.** Im Lasttest
  brauchte das Dashboard damit 72.9 s, über dem 8-s-Limit von Supabase.
  Das Modell wird deshalb als `mv_schimmel_modell` gespeichert und in der
  Kette von `auswertung_aktualisieren()` vor der Kaskade aufgefrischt; das
  Dashboard braucht wieder 0.2–0.5 s. Wer die Kurve anschaut, sieht den
  Stand der letzten Aktualisierung, wie bei allen anderen Kennzahlen seit
  0016.

## Zu Kleine sind ein Kanal, kein Verlust (0037)

Zu Kleine gehen an die Tiere. Damit sind sie kein physischer Verlust,
sondern ein anderer Kanal wie die zu Grossen, und wandern aus Buch A (Verlust)
nach Buch B (anderer Kanal / Marge), als „Zu klein (Tierfutter)". Das
verschiebt einen ganzen Balken: Die Hauptursache wird nur noch zwischen
Verdunstung und Schimmel entschieden. Dazu kommt ein drittes Buch, `feld`,
für die Grundaussortierung: physisch weg, aber nicht während der Lagerung
entstanden. Die Kennzahl „Lagerverlust" umfasst nur Buch A; die
Saisonbilanz weist beide getrennt aus.

## Das Sortierschema hängt am Käufer und am Datum (0038)

Coop will es anders als Migros, und dieselbe Sorte läuft je nach Bestellung
mit Kaliberbändern oder mit „Kiste ab x kg". Die Grenzen standen als ein
Wert je Sorte; wer sie änderte, klassierte rückwirkend jede je eingelesene
CSV neu, und der gemessene Ausschussanteil änderte sich, ohne dass ein Kürbis
anders gewogen wurde.

Jetzt gibt es `sortierschema` mit einer Fassung je (Sorte × Käufer) und
`gilt_ab`. Eine Fassung wird nie geändert, es kommt eine neue dazu. Jeder
Auftrag und jeder Sortierlauf hält fest, mit welcher Fassung gearbeitet
wurde; die Klassierung liest diese Fassung, nicht „die aktuelle". Käufer
legen die Arbeiter selbst an, beim Eröffnen der Arbeit, das ist Erfassung
und kein Stammdaten-Pflegefall. `sorte_kaliber` bleibt die Sortenliste;
ihre Grenzen sind nur noch der Ausgangswert für die erste Standard-Fassung.

Dabei fiel ein Fehler auf, der seit `0004` schlief: `lauf_neu_klassieren`
verwies in einem `update … from` auf die Zieltabelle unter ihrem Alias, was
Postgres ablehnt. Die Funktion war nie ausgeführt worden, kein Test rief sie.
Der neue Sortierschema-Test tut es (Käufer bekommt ab Dezember 700 g, der
Dezember-Lauf wird neu klassiert, der November-Lauf bleibt), und die
Funktion ist umgeschrieben.

## Antworten sind Messwerte (0039)

Beim Abschliessen wird der Arbeiter gefragt: „War alles aus einer Charge?"
Das ist keine Bedienlogik, sondern eine Aussage über die Verlässlichkeit
einer anderen Messung: Bei Nein weiss niemand, wie alt die Ware im Palox war.
Die Antworten stehen jetzt in `auftrag_angabe` als Schlüssel und Wert, nie
überschrieben, es gilt die letzte. Bei „nein" bekommt die Messung die Quelle
`verarbeitung_gemischt`: Sie zählt in der Massenbilanz (Masse ist Masse),
aber nicht im Verderbsmodell (kein verlässliches Alter). Vorher wurde die
Frage gestellt und die Antwort verworfen.

Bewusst nur für Angaben, über die nicht gerechnet und nicht verknüpft wird
(docs/Datenarchitektur, Regel 2). Wer eine neue Frage einbaut, braucht keine
neue Spalte; wer über eine Antwort rechnen will, braucht eine.

## Das Kistenmass kommt von der Sorte, nicht aus einer Einstellung (0040)

Seit 0038 gehört das Kistenmass zu (Sorte × Käufer) mit Gültigkeitsdatum, und
die Ausgangs-Kennzahl liest es dort. Die Überfüllung im Marge-Buch tat es
nicht: Sie teilte die ganze Weg-2-Masse durch die eine Einstellung
`soll_kg_pro_kiste`, gleichgültig um welche Sorte es ging.

Der Betrieb hat am 3. September gesagt, für welche Sorte die 8-kg-Kiste gilt,
lasse sich erst sagen, wenn einmal alles gewaschen und erfasst ist. Das ist
eine Antwort, die aus den Daten kommen wird — also muss die Rechnung sie von
dort nehmen können, statt auf eine gepflegte Zahl in den Einstellungen zu
warten. Jede Charge bringt ab jetzt ihr eigenes Kistenmass mit, aus der zuletzt
gültigen Kisten-Fassung ihrer Sorte.

Zwei Entscheidungen dabei:

- **Ohne Fassung gilt weiter die Einstellung.** Sonst fiele die Überfüllung auf
  null, sobald jemand die erste Fassung anlegt, und niemand wüsste warum. Der
  Rechenweg sagt stattdessen, wie viele Chargen aus einem Schema gerechnet
  wurden: Solange dort „0 von 42" steht, ist die Zahl so grob wie zuvor.
- **Je Sorte eine Fassung, nicht je Käufer.** Welchem Käufer eine bestimmte
  Kiste zugutekam, steht im Warenausgang nicht. Genommen wird die zuletzt
  gültige Fassung, Standard vor käuferspezifisch. Haben zwei Käufer derselben
  Sorte verschiedene Kistenmasse, ist das eine Näherung — sie steht als Annahme
  in `ABLAUF.md`.

## Lagerkontrollen ersetzen die fehlende Sockel-Messung nicht (gemessen)

Auf die Frage, ob sich beim Leeren des Palox trennen lässt, was faul war,
antwortete der Betrieb: schwierig. Die Lagerkontrolle wäre der naheliegende
Ersatz, denn sie trägt den Sockel nicht. Gemessen (2 % echter Sockel, 12 und
24 Kontrollen je Saison) ändert sie den Anteil der Saisons, in denen der Sockel
erkannt wird, jedoch nicht: 44 % bleibt 44 %, 0 % bleibt 0 %. Der Grund ist,
dass Kontrollen nicht dieselbe Ware messen wie die Verarbeitungspunkte — der
Widerspruch zwischen beiden Quellen wird als Streuung verbucht, nicht als
Sockel.

Was sie leisten, ist der Bereich: Er wird von 16 % auf 112–178 % breit und
enthält die Wahrheit in 96–100 % statt in 0–44 % der Saisons. Aus einer
selbstsicher falschen Zahl wird eine offen unsichere. Zwölf Kontrollen je
Saison reichen dafür; vierundzwanzig bringen nichts dazu. Diese Empfehlung
steht als Zahl in `STATISTIK_BEFUND.md`, damit sie nicht als Bauchgefühl
weitergereicht wird.

## Am Waschbecken zählen Kisten, und das Kistengewicht wird gemessen (0041)

Am Waschbecken kannte die Auswertung die verarbeitete Menge nicht. Der Arbeiter
trägt dort ein, wie viel Faules er aussortiert hat — ohne Gesamtmenge ist das
wertlos: „3 kg schlecht" sagt nichts, solange offen ist, ob sie aus 100 kg oder
aus 1000 kg kamen. Bisher gab es nur ein Feld für kg von Hand, und der Betrieb
hat klargestellt, dass auf Weg 1 nie gewogen wird.

Dass es dort keine Paletten mehr gibt, ist keine Erfassungslücke, sondern
Physik: Beim Sortieren löst sich die Palette auf. Die Kürbisse verteilen sich
nach Grösse auf Kaliber-Kisten — aus einer Palette werden fünf Kisten, und in
einer Kiste liegt Ware aus mehreren Paletten. Wochen später kommt das ans
Waschbecken. Die Einheit, die es dort gibt, ist die Kiste.

### Die Entscheidung: zählen an beiden Enden, wiegen nirgends

- **Wer die Arbeit eröffnet, trägt das Kaliber ein.** Eine Angabe je Arbeit
  statt eine je Kiste, und sie kommt von der Person mit dem besten Überblick
  (so vom Betrieb vorgegeben).
- **Wer an der Station steht, zählt.** Beim Waschen die geleerten Kisten, beim
  Sortieren die gefüllten — je Kaliberband.
- **Das Kistengewicht wird nicht geschätzt und nicht gewogen, sondern
  gerechnet.** Beim Sortieren ist die Masse je Kaliber aus der CSV bekannt (die
  Maschine wiegt jeden Kürbis). Masse je Kaliber geteilt durch gezählte Kisten
  ergibt kg je Kiste, mit Streuung über die Läufe und damit mit einem Bereich —
  ein gemessener Koeffizient wie die anderen auch.

Damit bleibt die Architekturregel gewahrt: Gespeichert wird die Zählung, das
Kistengewicht ist Ableitung. Ändert sich die Messgrundlage, ändert sich die
Masse mit; die gezählte Zahl bleibt, wie sie gezählt wurde. Kein Wiegen, keine
zusätzliche Waage, keine Schätzung.

Die Masse einer Arbeit hat jetzt drei Quellen in dieser Reihenfolge: gewogene
Paletten, eingetippter Durchsatz, gezählte Kisten mal Kistengewicht.
`masse_quelle` sagt, welche es war. Fehlt für ein Kaliber noch jede Messung,
bleibt die Masse **NULL, nicht 0** — der Waschgang steht weiter unter
„Auffälligkeiten", jetzt aber mit dem konkreten Rat, beim nächsten Sortierlauf
mitzuzählen; das Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser
Sorte.

### Was dabei technisch zu beachten war

`mv_kaliber_verteilung` stand am Ende der Aktualisierungskette, weil sie ein
Blatt war, das niemand weiterlas. Jetzt hängt das Kistengewicht daran und damit
die Masse am Waschbecken, die Punkte des Verderbsmodells und die Kaskade. Sie
steht deshalb ganz vorne; ihre eigenen Quellen sind reine Tabellen.

Die abgeleitete Masse kommt bewusst nicht in `mv_auftrag_masse`, sondern eine
Ebene darüber in `v_auftrag_masse` — die gespeicherte Ansicht hätte sonst samt
allem, was auf ihr steht, neu gebaut werden müssen.

### Annahme, die mitgeht

Eine Kiste, die beim Sortieren gefüllt wurde, kommt als dieselbe Kiste ans
Waschbecken. Wird zwischendurch umgepackt oder zusammengeschüttet, stimmt das
Kistengewicht nicht mehr. Das steht in `ABLAUF.md` unter den Annahmen und hängt
an Frage 13 in `FRAGEN.md`.

## Das Datum vom Palettenzettel ist Pflicht (0041)

Es war freiwillig. Fehlt es, rechnet die Auswertung das Alter des
Lagerbestands mit dem Mittel der ganzen Charge — in der Demo drei bis sechs
Tage daneben, bei k = 1.6 rund 4.5 % Verderb (Befund 4 aus 0036). Der Betrieb
hat entschieden: „zwing sie."

Die Bedingung in der Datenbank ist bewusst weicher als „nie leer": Ein Datum
ist entbehrlich, wenn es ohnehin feststeht — bei einer erkannten Palette oder
einer Wägung steht es dort, und die Auswertung nimmt es von dort. Verlangt wird
es genau dann, wenn es sonst niemand kennt.

Angelegt ist sie als `not valid`: Neue Zeilen brauchen ein Datum, bestehende
behalten ihre Lücke. Sie nachträglich zu füllen hiesse, eine Beobachtung zu
erfinden, die niemand gemacht hat.

## Funktionen dürfen sich nicht auf den Suchpfad verlassen (0042)

Beim ersten Einrichten in Supabase brach `setup.sql` ab:

```
ERROR: relation "einstellung" does not exist
QUERY: select coalesce((select (wert #>> '{}')::numeric from einstellung …
CONTEXT: SQL function "palox_tara_kg" during inlining
```

Die Tabelle stand zweihundert Bildschirmseiten weiter oben in derselben Datei.
Lokal lief dieselbe Datei auf einer frischen Datenbank fehlerfrei durch — und
zwar in jedem Testlauf seit Monaten.

Der Grund ist eine Eigenheit von Postgres. Der Rumpf einer SQL-Funktion ist
Text. Beim Planen einer Abfrage setzt Postgres ihn ein und löst die Namen darin
**in diesem Moment** auf, mit dem Suchpfad der aufrufenden Sitzung. Der Verweis
einer Ansicht auf die Funktion steht dagegen als feste Kennung — die Ansicht
findet die Funktion also immer, und erst der Rumpf fällt auf die Nase. `psql`
hat `public` im Suchpfad, der SQL-Editor des Anbieters nicht.

Zwei Antworten, je nach Kosten der Funktion:

- **Wo je Zeile eingesetzt wird** (`palox_tara_kg` in `v_palox_stand`,
  `klassiere` je Gewichtsstufe, `schimmelanteil` in den Kaskaden-Ansichten):
  Tabellen **und Typen** stehen jetzt mit `public.` davor. Das Einsetzen bleibt
  erlaubt, das Tempo also auch. Dass auch die Typen dazugehören, hat der
  Prüflauf gezeigt: `'unklassiert'::kuerbis_klasse` scheiterte an derselben
  Stelle.
- **Alle übrigen** bekommen einen festen Suchpfad (`alter function … set
  search_path = public`). Das verhindert das Einsetzen — bei einer Funktion,
  die einmal je Abfrage läuft, kein Verlust, und es macht sie unabhängig davon,
  wer sie aufruft. Die Regel gilt als Schleife über alles, was noch keinen Pfad
  hat, damit sie auch für künftige Funktionen greift.

Der Prüflauf fährt seither die ganze Kaskade einmal mit leerem Suchpfad durch —
alle sieben gespeicherten Auswertungen neu gerechnet, alle Kennzahlen abgefragt.
Wäre diese Prüfung früher dagewesen, hätte der Fehler den Betrieb nie erreicht.
Das ist die eigentliche Lehre: Der Testlauf lief unter genau den Bedingungen,
unter denen die Software nie laufen würde.

---

# Fünfte Runde (3. September): den vereinbarten Ablauf wirklich bauen

Eine Durchsicht zeigte, dass eine Reihe am 1. und 2. September bestätigter
Absprachen zwar in `docs/ABLAUF.md` stand, aber nie in die Masken gekommen war.
Die Dokumente waren zum Protokoll der Absicht geworden, die App dahinter
zurückgeblieben. Diese Runde schliesst die Lücke — und baut das, was sie nicht
wieder aufkommen lässt. Jede Absprache trägt jetzt eine Kennung und ihren Test
(`docs/ABMACHUNGEN.md`).

## Der eigentliche Fund: die Prüfstände fragten nicht, was besprochen war

Die Prüfstände testeten, ob die App richtig **rechnet**, nicht ob sie das
**fragt**, was der Betrieb festgelegt hat. Deshalb fiel die Palox-Ablesung
(AB-02) niemandem beim Prüfen auf: Die Rechnung dahinter war korrekt, nur
verlangte keine Maske die Ablesung. Die Antwort darauf ist der Lückenscanner
(`pruefstand/luecken.sh`, Teil von `run.sh`), der in beide Richtungen prüft,
dass zwischen Erfassung und Auswertung nichts nur auf einer Seite existiert.

## Die Absprachen und die Entscheidungen dahinter

- **AB-01 Sortierart je Arbeit.** Bisher hing „Kiste ab x kg" oder „Kaliber" an
  (Sorte × Käufer × Datum), und ein Index liess nur eine Fassung je Stichtag
  zu. Der Betrieb macht aber beides. Der Index umfasst jetzt die Art, beide
  Fassungen dürfen nebeneinander stehen, und der Arbeiter wählt beim Eröffnen.
  Kehrseite, vorher falsch: Nach Kaliber gibt es kein Sollgewicht je Kiste und
  damit keine Überfüllung — die rechnete die Auswertung trotzdem, weil sie ohne
  Kisten-Fassung auf die globale Einstellung zurückfiel und jede Wägung
  mitzählte (leer als null). Jetzt zählt sie nur Masse aus Kisten-Arbeiten.
- **AB-02 Palox bei Beginn und Abschluss.** Ein Start-Hinweis führt zur
  Ablesung, der Abschluss ist gesperrt, bis abgelesen wurde. Darauf ruht die
  ganze Palox-Rechnung; ohne Ablesung landete der Schimmel zweier Arbeiten auf
  einer.
- **AB-03 Ausschuss wiegen.** Brutto, Kisten und Gebinde erfasst, das Netto vom
  Auslöser abgeleitet — dieselbe Regel wie beim Palox (gespeichert wird der
  Waagenstand). Die Schätzung bleibt für Notfälle, zählt als Messwert weiter;
  unterschieden wird sie am fehlenden Brutto, nicht am `gemessen`-Flag (das
  hätte sie aus der Rechnung genommen). Ein Prüf-View meldet, wenn eine
  nachträglich geänderte Tara ein gespeichertes Netto überholt.
- **AB-04/05 Geführter Abschluss.** Die zwei Ausschuss-Paletten-Fragen (leer zu
  Beginn, alles von dieser Arbeit) sind Angaben wie „alles aus einer Charge".
  Der Abschluss verlangt sie zusammen mit der Palox-Ablesung — die eine Stelle,
  an der Vollständigkeit erzwingbar ist.
- **AB-06 Chargennummer eintippen** (mit Vorschlagsliste), unbekannte Nummer
  blockiert das Starten statt sie still anzulegen.
- **AB-07 Erfassungsbeginn.** Die Saison lief schon, als die App kam. Der
  Vorab-Ausgang je Charge (`charge_vorlauf`) geht als bekannter Ausgang in die
  Massenbilanz, damit die Lücke nicht den späten Start als fehlende Masse
  ausweist.
- **AB-08 Fax** als eigene Tätigkeit, fachlich ein Waschgang (Station
  unverändert, damit die Kaskade nicht angefasst wird), über `ist_fax`
  getrennt.
- **AB-09 Lagerkontrolle:** die Auswahlart der Palette wird festgehalten
  (zufällig erreichbar / Mitte-unten / gezielt). Das gestapelte Lager macht
  „nimm irgendeine" unmöglich; die ehrliche Vorgabe ist „zufällig unter den
  erreichbaren", und gezielte Kontrollen lassen sich später aus der
  Selektionsprüfung ausnehmen.
- **AB-10 Waagen-Hinweis** in der Palox-Maske: direkt ablesen, nicht umrechnen.

## Warum das Modell unverändert bleibt

Diese Runde ändert die Erfassung, nicht das Modell. Die Simulationsmatrix
(25 Saisons je Bahn, vorher/nachher) belegt es: Verzerrung und Überdeckung der
Ströme bleiben stehen. Die Massenkaskade, das Verderbsmodell und der Sockel aus
der vierten Runde sind nicht angetastet — Fax bleibt ein Waschgang, die
Sortierart wählt nur, nach welcher gespeicherten Fassung klassiert wird.

## Ballast abwerfen (0048)

Der Durchgang aus der Vogelperspektive (`docs/archiv/PROMPT_ABSCHLUSS.md`)
fragte zuerst, was zu viel ist. Massstab: Ein Objekt, das kein Bildschirm liest,
keine Ansicht braucht und höchstens ein Test anfasst, kostet bei jeder Änderung
Pflege und erklärt niemandem etwas. Wegwerfen ist eine Änderung wie jede andere
— erst belegen, dann entfernen, dann prüfen, dass alles grün bleibt.

**Belegt** wurde je Objekt dreifach: `pg_depend` kennt keinen Leser, kein
Funktionsrumpf nennt es (`pg_proc.prosrc`), `src/` greift nicht darauf zu.

| Objekt | Herkunft | Warum weg | Was bleibt |
|---|---|---|---|
| `marge_messung` (+ Typ `marge_art`) | 0001 | Alt-Kanal für von Hand eingetippte Marge-Posten. Die App schrieb ihn nur in den ersten Stunden des 25. August (10b8a3f → a1a6cd5). Überfüllung kommt aus `ausgang_wiegung`, Nebenkanal aus der CSV. | Ein Wächter: hält die Tabelle Zeilen, bricht `setup.sql` mit Anleitung ab — nichts Gemessenes verschwindet still. Geprüft in run.sh Stufe 3b am alten Stand. |
| `v_verdunstung_stichprobe` | 0006 | Seit 0018 (gepoolte Koeffizienten) ohne Leser. | — |
| `v_sortier_kuerbis` | 0005 | Expansion des Histogramms je Kürbis; nur ein Test las sie. | Der Test rechnet direkt mit `sum(anzahl)` und `sum(anzahl·gewicht)` — der Beleg, dass die Kodierung verlustfrei ist, bleibt. |
| `v_dubletten_pruefung`, `v_schlag_effekt` | 0022, 0026, 0037 | Prüfbare Annahmen, die drei Migrationen mitpflegen mussten und nie jemand las. | Der Befund steht in `STATISTIK_BEFUND.md`; die Abfragen stehen in Git. |
| `v_auftrag_sortierart` | 0043 | Nie angebunden. | — |
| `v_ausschuss_pruef` | 0044 | Die Prüfung war richtig, der Ort falsch: eine eigene Sicht, die kein Bildschirm las. | Zeile „Ausschuss-Tara" in `v_plausibilitaet`, wo der Betriebsleiter sie sieht. Test AB-03 prüft beides: kein Befund bei unveränderter Tara, genau einer nach der Änderung. |
| `schimmel_n(numeric)` | 0006 | Für den alten Rechenweg; seit 0036 nennt ihn keine Ansicht. | — |
| sechs `docs/PROMPT_*.md` | — | Arbeitsaufträge vergangener Runden im Hauptordner. | `docs/archiv/` — Geschichte, nicht Anleitung. |
| Bemerkung der Kisten-Standardfassungen | 0043 | Vier Zeilen, die auf dem Handy die ganze Karte füllten. | Ein Satz; 0048 kürzt auch bereits angelegte Zeilen (eine Notiz, kein Messwert). |

**Bewusst behalten:** `schimmel_messung.teilgewicht` und `auftrag.geplante_paletten`
können auf dem Betrieb Daten halten und kosten nichts; der Zweig „Nicht
ausgewertet" in den Auffälligkeiten fiel dagegen mit der Tabelle, die er
meldete.

## Der Abschluss-Durchgang: fertig bauen, nicht umbauen

Was nach dem Abwerfen noch fehlte, war Feinschliff, kein Modell:

- **Reiter brechen um** statt abzuschneiden (`.navleiste.unter`): „Fertige
  Pale…" auf dem Handy und „Erfassungsbegin" auf dem Desktop waren nicht lesbar.
- **Ein Hinweis je Sache:** Der Abschluss-Reiter hat seinen eigenen
  Palox-Hinweis (AB-02); der allgemeine darüber blendet sich dort aus. Die
  Warnung „Frage nach den leeren Paletten offen" im Abschluss entfiel — die
  Frage selbst steht mit ihren Knöpfen direkt darüber. Der Schlüssel
  `ausschussLeerOffen` ging in allen sechs Sprachen mit.
- **Eine Charge, ein Feld:** `ChargeFeld` ist der Baustein für „neue Arbeit"
  und „Lagerkontrolle" (AB-06). Die Kontrolle hatte noch eine Auswahlliste —
  dieselbe Frage sah an zwei Orten verschieden aus.
- **Die Demo altert nicht mehr:** Feste Daten (September 2026) hiessen ein
  Jahr später „liegt seit 0 Tagen", weil die Ware erst in der Zukunft
  eingelagert worden wäre. 0034 rechnet jetzt von `current_date − 240` aus;
  alle Abstände und damit jedes Modellergebnis bleiben gleich.
- **„Nicht belegt" statt „0.0 t":** Setzt der F-Test den Sockel a₀ auf 0,
  zeigte die Kaskade eine Zeile „Nicht lagerbedingt · 0.0 t (0.0 %)" — eine
  Zahl, die wie eine Messung aussah. Der Wasserfall lässt Ströme ohne Masse
  weg; die Karte sagt mit `sockel_nachweis` und `sockel_schwelle`, warum a₀
  auf 0 steht: nicht „kein Feldanteil", sondern „mit diesen Daten nicht von
  der Verderbskurve zu trennen".
- **CSV-Import:** ein Knopf im Stil der App statt des browsereigenen
  „Choose Files".
- **Sortierschemata als Liste, nicht als Tabelle:** Vier Spalten quetschten
  die Regel auf dem Handy in eine schmale Spalte und schnitten sie ab. Jetzt
  je Sorte × Käufer ein Block, je Fassung eine Zeile mit Datum und Regel.
- **„Liegt seit" statt „Lagertage"** in „Sortiert — wartet aufs Waschen":
  Die Spalte zeigte das Alter bis zum Stichtag (`alter_lager`, die Grösse der
  Hochrechnung) — neben einer Tabelle, die „liegt seit 203 Tagen" bis heute
  sagte. Eine Zustandstabelle zeigt das Alter bis heute (`alter_lager_heute`);
  die Hochrechnung rechnet unverändert bis zum Stichtag.
- **Prüfstand in sechs Sprachen:** `SPRACHE=hu node pruefstand/bildschirme.mjs`
  rendert die Arbeiter-Masken in der Sprache mit den längsten Wörtern. Die
  Klickwege nennen Reiter und Knöpfe über ihren Text-Schlüssel und holen das
  Wort aus dem Wörterbuch der App — vorher standen deutsche Wörter im
  Prüfstand, und in jeder anderen Sprache lief er ins Leere.

## Zwei Apps in einer: Zähler, Vorarbeiter, Betriebsleiter (UI-Umbau, 0049)

Der Betrieb wollte zweierlei: eine Arbeiter-App, die niemanden verwirrt, und
eine Betriebsleiter-Seite, die erklärt statt auflistet. Das Konzept mit den
Leitlinien und Quellen steht in `docs/UI-KONZEPT.md`; hier die Entscheidungen.

### Die Rolle hängt an der Arbeit, nicht an der Person

Wer eine Arbeit eröffnet, ist ihr Vorarbeiter; wer beitritt, ist Zähler.
Konten, Rollenverwaltung, Passwörter — nichts davon. Der Vorarbeiter sieht
eine Checkliste (Palox zu Beginn · Ausschuss-Paletten leer? · Zählen ·
Ausschuss wiegen · Fertige Palette · Abschliessen), der Zähler sieht einen
Zähler. Fällt das Handy des Vorarbeiters aus, holt ein Tipp die
Vorarbeiter-Ansicht auf jedes andere. Die Rolle wird nicht gespeichert: Sie
ist keine Messung, und nichts in der Auswertung hängt daran.

### Ein Bildschirm, eine Frage

Das Eröffnen und das Abschliessen sind Assistenten nach den NN/g-Regeln:
feste Reihenfolge, Schrittanzeige, nur die Fragen, die für die Tätigkeit
gelten, am Ende eine Zusammenfassung. Der Abschluss-Assistent *beginnt* mit der
Palox-Ablesung — so ist AB-02 nicht mehr ein Hinweis, den man übersehen kann,
sondern der erste Schritt, an dem man nicht vorbeikommt. Wer die Startfrage
nach den leeren Ausschuss-Paletten vergessen hat, bekommt sie im Abschluss
nachgestellt (AB-04: der Abschluss erzwingt die Vollständigkeit).

### Rückgängig statt Nachfrage

„+" zählt sofort, „Rückgängig" nimmt die letzte Palette zurück. Die frühere
Frage „wiegen oder nur zählen?" bei jedem Tipp ist weg; Wiegen ist ein eigener,
kleinerer Knopf. Das Datum vom Zettel bleibt für die nächste Palette stehen —
die kommen zu Dutzenden mit demselben Datum, und jedes Neueintippen war eine
Gelegenheit für einen Fehler.

### Der Betriebsleiter bekommt fünf Fragen statt drei Ebenen

Überblick (wie viel, woran, was tun) · Ursachen (warum, wie sicher) · Chargen
(wo steht welche) · Messungen (was weiss die Auswertung nicht) · Betrieb
(was läuft, Grundlagen). Jeder Reiter trägt seinen Satz oben. Die frühere
Aufteilung in „Überblick / Aufschlüsselung / Rohdaten" hatte keinen Ort, an
dem man eine Charge nachschlagen konnte, und die Rohdaten waren ein Ort für
alles, was sonst nirgends hinpasste.

### Was aus den neuen Erfassungspunkten wurde (0049)

Sechs Sichten, kein Modell: Gewichtsverteilung aus der CSV (vom Betrieb seit
dem 2. September gewünscht), Alter der verarbeiteten Ware gegen die Charge
(wird das Älteste zuerst verarbeitet — die Fehlerquelle, die keine Rechnung
wegbekommt), Durchsatz je Arbeit, Überfüllung je Käufer, Datenqualität als
Zähler je Absprache, Eingang und Ausgang über die Saison. Alle sechs lesen nur
Tabellen, die die Masken schon füllen; der Lückenscanner blieb still, die
achtzehn Dashboard-Ansichten brauchen zusammen rund 300 ms.

### Diagramme von Hand, Farben geprüft

Kurven und Punkte sind SVG ohne Bibliothek; jedes Diagramm hat Hover, Legende
ab zwei Reihen und eine Tabelle. Die sechs Strom-Farben wurden mit einem
Palettenprüfer (Farbfehlsichtigkeit, Kontrast) neu gesetzt — die alten lagen
für Rot-Grün-Schwäche zu nah beieinander. Drei der neuen liegen im Hellmodus
unter 3:1 Kontrast; deshalb trägt jeder Strom überall seinen Namen als Text.

### Die Demo läuft auf der Hand-Linie nach „Kiste ab x kg"

Sonst hätte die Demo keine Überfüllung gezeigt: Nach Kaliber gibt es kein
Sollgewicht (AB-01), und die Hand-Linie füllt 8-kg-Kisten. Reine
Demo-Änderung in 0034.

## Vier Fehler aus der Halle, und die Demo als Praxistest (0051, 0052)

Der Betrieb hat am 7. September vier Dinge gesagt, die die App anders
verstanden hatte. Alle vier stecken in 0051; die Demo in 0052 zeigt sie.

### Fax ist kein Waschgang

Beim Fax wird nicht gewaschen. Die gewaschene Ware steht in Kisten, bis eine
Bestellung kommt; dann werden Etiketten angebracht, und dabei wird nochmals
Faules aussortiert. Die App hatte Fax als Waschgang geführt (Station waschen,
`ist_fax`) — und damit zweimal falsch gerechnet: die Fax-Masse zählte als
*gewaschen* und schob die Charge ein zweites Mal aus dem Lager; das Faule ging
als Punkt in die Verderbskurve, obwohl es vom Waschen und Stehen kommt, nicht
von der Lagerdauer (ABLAUF.md wusste das seit dem 2. September).

Jetzt: Kein neuer Enum-Wert — der wäre in der einen Transaktion von
`setup.sql` nicht verwendbar —, sondern `ist_fax` ist überall ausgenommen, wo
Waschen gerechnet wird. Der Arbeiter zählt die gemachten Kisten (je Kaliber
oder nach Sollgewicht, Band −1; „+ 1 Palette" zählt die Einstellung
`kisten_pro_palette`) und wiegt das Faule kistenweise: `schimmel_messung`
trägt Brutto, Kisten, Gebinde, `mit_palette`; das Netto rechnet ein Auslöser,
wie beim Ausschuss. „Nichts Faules" ist eine Messung mit 0 kg. Der Strom
„Faul beim Abpacken (Fax)" hat einen Koeffizienten je Sorte
(`v_koeff_fax`, derselbe Bündelungs-Schätzer wie zu klein und zu gross),
bezogen auf die verkaufsfähige Masse, mit Fehlerfortpflanzung. Unbekannt —
nicht 0 — bis die erste Fax-Arbeit Faules gewogen hat.

Dazu kennt die Bilanz den dritten Lagerabschnitt: verkaufsfähig gewaschen
minus durchs Fax gegangen ist „gewaschen, wartet auf Bestellung". Ohne
Fax-Erfassung bleibt die Zeile leer und die Bilanz rechnet wie bisher — sonst
liesse sich ein fehlender Ausgang nie mehr von wartender Ware unterscheiden.

### Die Maschine kennt nur Bänder

Die Frage „Kiste ab x kg oder Kaliber?" gibt es beim Sortieren nicht. Die
Frage, die es gibt: *Welche* Bänder sind heute eingestellt? Der Assistent
zeigt sie als Grenzen — zu klein unter, Band 1 bis, Band 2 bis, …, zu gross
ab — mit „wie zuletzt: übernehmen" oder „anpassen". Lückenlos per Bauart;
falsch kann nur die Reihenfolge sein, und das sagt die Maske. Von Hand
ebenso: Kiste ab x kg (welches x) oder Kaliber (welche Bänder).

Was bestätigt wird, ist die Fassung, nach der die Arbeit läuft; was geändert
wird, wird eine neue Fassung ab heute (`sortierschema_festlegen`). Nichts
Altes wird überschrieben — ausser die Fassung desselben Tages, denn zweimal
am selben Tag ist dieselbe Einstellung. Die Funktion läuft in der Datenbank,
damit `kette_pruefen.sh` sie mit denselben Argumenten ruft wie die App.

### Es gibt kein FIFO

Der Eingang einer Charge verteilt sich über Wochen, der Ausgang auch, und
verarbeitet wird, was erreichbar ist. Gespeichert war das immer richtig
(jede Palette mit Datum, jede Zählung mit Zetteldatum). Gerechnet wurde mit
*einem* Alter je Charge. Jetzt führt `v_charge_kohorte` den Bestand je
Eingangstag (Paletten des Tages minus gezählte Paletten mit diesem Datum),
`mv_kaskade` rechnet den Lagerbestand je Kohorte mit ihrem Alter,
`v_naechste_charge` ebenso, und „liegt seit" ist eine Spanne: 128–161 Tage,
4 Eingangstage. Die Chargen-Seite zeigt je Eingangstag, was kam, was gezählt
wurde, was liegt. Ein Zetteldatum ohne Palette fällt jetzt auf.

Bei einer Kurve mit k ≈ 1.2–1.7 und Spannen von zwei bis vier Wochen macht
das je Charge wenige Prozent des Verderbs aus — der eigentliche Gewinn ist,
dass die Zahl auf dem Bildschirm nicht mehr etwas behauptet, das es nicht
gibt.

### Die sechsstellige Nummer ist unsere

Die Planungsdatei des Betriebs führt je Schlag und Sorte beide Nummern: die
vierstellige (Bioprodukte) und die sechsstellige aus dem Perigon der Firma AG.
232 von 236 Kürbiszeilen der AG-Datei seit Juli 2026 tragen eine davon. Die
Nummer steht jetzt an der Charge (`charge.perigon_nr`), der Import löst sie
auf (`chargeAufloeser`); die eine doppelte Nummer (198976, Butterkin und
Tiana in Rümlang) entscheidet der Artikel, sonst bleibt die Zeile ohne Bezug.

### Was sonst noch klar wurde

- Die Kilo-Frage am Ende des Waschens ist weg: Die Menge sind die gezählten
  Kisten. Fehlen sie, sagt es der Abschluss, statt eine Zahl zu verlangen.
- Diagramme: Der oberste Punkt sass auf der Rahmenlinie — die Achse hat jetzt
  Luft darüber; liegen die Werte eng beieinander, zeigt sie den Bereich der
  Werte statt der Null. Die Verdunstung zeigt eine Reihe je Sorte mit der
  Sortenrate als Bezugslinie.
- Die Gewichtsverteilung erklärt die Stufenbreite und nennt den Schwerpunkt.
  Dass die Balken bei 25 g dünner wurden, lag an der alten Demo: acht
  Gewichtsstufen. Die neue hat je Lauf rund 150.
- Buch B ist aufgeschlüsselt: je Sorte (mit Kisten), je Charge, je Arbeit
  (die Messung dahinter), Überfüllung je Käufer.
- Der Überblick hat „Arbeit und Tempo": je Tätigkeit Arbeiten, Stunden,
  Median der Dauer, kg je Stunde und je Personenstunde.

### Die Demo als Praxistest (0052)

Die alte Demo war eine Rechenübung. Die neue entsteht so, wie der Betrieb
arbeitet: 36 Chargen der Anbauplanung 2026 in halber Menge, Ernte je Charge
in ihrer Erntewoche an Werktagen, Sortierläufe abwechselnd vom jüngsten und
vom ältesten Stapel, CSV mit rund 150 Gewichtsstufen und gezählten Kisten,
Waschen je Kaliber Wochen später, Fax je Bestellung mit gewogenem Faulem,
Lieferungen über Wochen verschränkt. Verderb nach einer Weibull-Kurve je
Sorte, Verdunstung mit Streuung je Palette. Deterministisch.

Zwei Dinge hat der Praxistest sofort gefunden: An einer Station läuft nur
eine Arbeit zugleich — sonst verschränken sich die Palox-Ablesungen und die
Differenzen werden falsch (die Demo serialisiert je Station). Und ohne
Fax-Erfassung fehlte der Bilanz der dritte Lagerabschnitt: gewaschene Ware,
die auf eine Bestellung wartet, war „Lücke". Beides steht oben.

Was die Demo ehrlich zeigt: Das Verderbsmodell fittet über alle Sorten
eine Kurve; später im Jahr liegt vor allem Butternut, das langsamer
verdirbt — die gemeinsame Kurve wird flacher (k ≈ 1.2 bei erzeugten
1.5–1.7). Die Wasch-Punkte tragen das ihre bei: ihr Sortier-Anteil ist das
Mittel aller Sortierläufe der Charge. Das ist die Grenze aus
`STATISTIK_BEFUND.md`, nicht ein Fehler der Demo.

Drei Kleinigkeiten hat der Praxistest noch dazugelegt, als die Kette mit
dem Fax-Auftrag lief:

- **Der Kisten-Zähler verlor bei schnellem Doppeltipp einen Zähler.** Der
  Knopf war wieder frei, bevor der neue Stand geladen war; der zweite Tipp
  rechnete vom alten weiter (32 → 1 → 33). Jetzt bleibt der Zähler gesperrt,
  bis der Stand da ist — Paletten zählen und Rückgängig gleich mit.
- **Die Demo hängte die gewogene Palette an die falsche Zählzeile.** Die
  Wägung gehörte zur ersten Palette der Arbeit, verknüpft war sie mit der
  Zählzeile mit der kleinsten ID — das konnte ein anderer Eingangstag sein.
  Die Kohortenrechnung zeigte dann „mehr gezählt als gekommen". Acht von 526
  Verknüpfungen; die Demo verknüpft jetzt über das Zetteldatum.
- **Die Chargen-Kopfzeile sagte „Sortiert / gewaschen 0 kg / 0 kg"** bei
  Chargen, die über die Hand-Linie gingen — die Sicht zählt dort nur die
  Maschine. Jetzt steht die Hand-Linie eigens, und die Maschine heisst so.

### Wer schon eine Demo hat, sieht nur „entfernen"

Die Demo-Karte bot das Laden nur an, solange keine Demo in der Datenbank
lag. Wer das Werkzeug aktualisiert, hat aber die alte Saison noch drin und
kam so nie an die neue. Jetzt steht dort **„Demo-Saison neu laden"**:
entfernen und laden in einem Schritt. Zwei Demos nebeneinander gibt es
weiterhin nicht — die Mengen würden doppelt zählen, und `demo_daten_laden()`
weist einen zweiten Aufruf ab.

Dabei kam ein Fehler heraus, den die neue Rundlauf-Prüfung fand (laden,
entfernen, Zählstand muss wieder derselbe sein): Das Entfernen löschte die
Käufer Coop, Migros, Rathgeb und Bio Partner, sobald nichts mehr an ihnen
hing — auch dann, wenn der Betrieb sie selbst eingetragen hatte. Käufer
tragen jetzt eine Bemerkung, und gelöscht wird nur, was `DEMO` trägt.
Die Kehrseite ist gewollt: Käufer, welche die **alte** Demo angelegt hat,
tragen die Markierung nicht und bleiben beim Entfernen stehen. Ein Name im
Stammdatenregister ohne Daten daran ist harmlos; ihn auf Verdacht zu
löschen wäre es nicht.

### Zwei Sicherungen von Supabase, die der Prüfstand nicht hat

Der erste Versuch auf dem echten Supabase brach ab: „UPDATE requires a
WHERE clause". Supabase lässt die API-Verbindung mit der Erweiterung
`safeupdate` laufen, die jedes UPDATE und DELETE ohne WHERE abweist — auch
in einer Funktion, auch auf einer Hilfstabelle. Die Demo hatte genau eines
(die Sorteneigenschaften auf der Hilfstabelle der Chargen). Der lokale
Prüfstand kennt die Erweiterung nicht, darum kam es durch. Jetzt liest eine
Wache in `pruefung.sql` jeden Funktionsrumpf und verlangt bei jedem
UPDATE/DELETE ein WHERE auf oberster Ebene; gegen den alten Stand schlägt
sie an, mit der Korrektur nicht.

Die zweite Sicherung ist die Zeit: ein API-Aufruf hat acht Sekunden. Die
Demo braucht hier 0.6 s für die Daten und 1.25 s für das Neurechnen der
Auswertung — auf einer kleinen Supabase-Instanz ein Mehrfaches davon. Darum
rechnen `demo_daten_laden()` und `demo_daten_entfernen()` die Auswertung
nicht mehr selbst; die App ruft `auswertung_aktualisieren()` gleich danach
als eigenen Aufruf, die SQL-Dateien tun dasselbe in derselben Abfrage
(LATERAL erzwingt die Reihenfolge). Zwei kurze Aufrufe statt eines langen.

Das reichte nicht. Auf einer kleinen Instanz brach schon das Neurechnen
allein ab („canceling statement due to statement timeout"). Also die
Einstellung selbst, in `0053_zeitlimit.sql`: `authenticated` bekommt 30
Sekunden statt acht. Das ist keine Tariffrage — die Limits hängen an der
Rolle und sind im Gratis-Tarif genauso änderbar. `anon` bleibt bei drei
Sekunden: Wer nicht angemeldet ist, rechnet hier nichts, und ein knappes
Limit ist dort eine Sicherung.

Warum 30 und nicht mehr: Supabase lässt für Client-Abfragen höchstens 60
Sekunden zu, und eine halbe Minute ist die Grenze dessen, was vor dem
Bildschirm noch als „es rechnet" durchgeht. Wird die Rechnung länger, ist
nicht das Limit das Problem, sondern die Rechnung. Die Prüfung „Auswertung
bei dreifacher Saisongrösse" in `run.sh` bewacht genau das.

Die Migration ist vorsichtig: Steht das Limit schon, tut sie nichts. Darf
sie die Rolle nicht ändern (fremde Datenbank, engere Rechte), sagt sie es
als Hinweis und lässt die Einrichtung weiterlaufen — alles andere
funktioniert auch mit acht Sekunden.

## Nur behaupten, was man wissen kann (Runde E: 0054, 0055, Überblick und Ursachen neu)

Der Betriebsleiter hat drei Dinge gesagt, die zusammengehören. Erstens: Die
Erfassung in der Halle ist punktuell — vielleicht werden in einer Saison nur
fünfzehn Waschgänge dokumentiert. Zweitens: Der Überblick soll drei bis fünf
Dinge zeigen, logisch, verständlich, relevant — und nichts vorhersagen, was
sich nicht vorhersagen lässt. Drittens: Die Ursachen sollen in die Tiefe
gehen, je Charge, aber ohne Ratschläge für die Saison.

### Was daraus folgt

Vollständig sind genau zwei Listen: der Wareneingang (jede Palette im
Erntejournal) und der Warenausgang (jede Lieferung auf einem Lieferschein).
Alles aus den Arbeiten ist Stichprobe. Aus Stichproben kommen Raten —
Verdunstung je Tag, Faules je Lagertag, zu klein je Band, Faules je Fax —
und Raten lassen sich auf die vollständige Eingangsmasse hochrechnen. Was
sich aus Stichproben *nicht* ergibt, sind Mengen: wie viel schon sortiert,
gewaschen, „wartet aufs Waschen". Diese Zahlen standen im Überblick und in
den Ursachen, als wären sie gezählt. Sie sind weg.

„Noch im Haus" ist deshalb neu gerechnet: Eingang (gemessen) minus
Ausgeliefert (gemessen) minus Verlust und anderer Kanal (Modell) — je
Charge, und daraus je Sorte, Schlag oder Charge. Ohne eingelesenen
Warenausgang steht dort ein Strich, keine Zahl.

Gestrichen sind: „Was kostet Warten" (eine Vorhersage je Charge, deren
Paletten an verschiedenen Tagen kamen und in unbekannter Reihenfolge gehen —
das lässt sich nicht sagen), „Was jetzt zu tun ist" (Erfassungslücken
gehören zu Messungen), die Liste aller Fax-Arbeiten (was nützt sie? Die Rate
je Sorte und je Charge sagt mehr), „Arbeit und Tempo" (nach Betrieb →
Arbeiten, wo die Arbeiten stehen) und die Bilanz (nach Messungen, weil sie
das Modell prüft). Geblieben sind im Überblick vier Zahlen, die Hauptursachen
gesamt oder je Gruppe, der Bestand je Gruppe, die Kaliber je Sorte und die
Saison im Verlauf.

### Der Warenausgang ist jetzt einlesbar

Der Bildschirm fehlte noch ganz, obwohl Leser, Regeln und Schema standen
(`PROMPT_WARENAUSGANG.md`). Jetzt: Betrieb → Warenausgang → „Excel-Dateien
wählen". Der Browser liest die Datei, zeigt Befund und Abgleich (neu,
geändert, unverändert, verschwunden), lässt unbestätigte Artikel klären und
übernimmt dann in einem Aufruf (`ausgang_uebernehmen`, 0055): Datei,
Rohzeilen, Lieferungen. Zeile für Zeile über die API wären es für eine
Datei des Betriebs tausende Aufrufe gewesen. Die beiden echten Dateien vom
7. September liest der Leser in unter einer halben Sekunde, Kopf erkannt,
keine Zeile übersprungen.

Die Funktion löscht nichts („verschwunden" wird gezeigt, nicht getilgt),
rät keine Sorte (eine Lieferung ohne Charge und ohne bestätigte Sorte kommt
mit Grund zurück) und setzt bei einem geänderten Fingerabdruck
`geaendert_ts`, damit eine im Perigon korrigierte Zeile eine Korrektur
bleibt und keine zweite Lieferung wird.

### Das Kaliber am Waschbecken

Die Bänder je Sorte stehen seit 0003 in den Stammdaten — aus der
Spezifikation §6, die der Betrieb geliefert hat. Sechs der elf Sorten haben
dort dieselben drei Bänder (600–1100–1600–2000); das ist die Vorgabe, kein
Versehen, und die Maske sagt jetzt, woher die Bänder kommen. Neu kann der
Vorarbeiter ein eigenes Band eingeben (0054), wenn das Etikett etwas anderes
nennt. Das Kistengewicht dazu findet die Auswertung nur, wenn beim Sortieren
je ein Band mit genau diesen Grenzen gezählt wurde; sonst bleibt die Masse
unbekannt, und die Plausibilität sagt es — statt einer geratenen Zahl.

### Die Kaliber-Verteilung war je Charge statt je Sorte

Die Sicht liefert je Charge eine Zeile je Band; die Karte zeigte sie
ungebündelt — für Amoro viermal „600–1100 g" untereinander. Jetzt bündelt
`kaliberJeSorte()` über alle Chargen, in der Reihenfolge zu klein, Bänder
aufsteigend, zu gross; im Überblick als ein Balken je Sorte.

### Die Verdunstung als kumulierter Verlust

Die Rate je Tag als Punktwolke war nicht lesbar. Jetzt steht je gewogener
Palette, wie viel Prozent ihres Eingangsgewichts sie bis zum Wiegen verloren
hat, über der Lagerdauer — und die gestrichelte Linie ist, was die
Auswertung für die Sorte rechnet (1 − (1 − r)^t). Liegen die Punkte um sie
herum, trägt die Rate; liegen sie systematisch daneben, stimmt sie nicht.
Dazu je Sorte: Rate je Tag, Verlust nach hundert Tagen, Bereich, Anzahl.

### Was der Lasttest fand

Die erste Fassung der Kistenmasse-Sicht (0054) suchte das Gewicht zum
eigenen Band mit einem LATERAL-Verbund über `v_koeff_gebinde` — und die
ist selbst eine Aggregation über alle Sortiergewichte. Postgres rechnete
sie damit je Kistenzeile neu: die achtzehn Dashboard-Sichten brauchten bei
dreifacher Saisongrösse 26 Sekunden statt einer, `v_marge_buch` allein
11. Genau dafür steht der Lasttest in `run.sh`. Jetzt wird das eigene Band
über eine kleine Tabelle der Bandgrenzen auf seinen Index abgebildet, und
die Kistengewichte werden wie in 0041 einmal gerechnet und verbunden:
0.2 Sekunden.

### Was der Typprüfer nicht prüfte

`npx tsc --noEmit -p .` war ein Nichts: die `tsconfig.json` des Projekts
hat keine Dateien, nur Verweise. Geprüft wurde in Wahrheit nur durch
`npm run build` (`tsc -b`). Der echte Aufruf ist
`npx tsc -p tsconfig.app.json --noEmit`; er steht jetzt in der README.


## Eine Palette wird im Lager nicht schwerer (Runde F: 0056, setup.sql ohne Zwischenrechnung)

Am 7. September stand der Überblick auf dem Hof mit „numeric field
overflow — a field with precision 12, scale 2 must round to an absolute
value less than 10^10", und `setup.sql` brach mit derselben Meldung ab.
Nachgestellt auf der Demo: drei Wägungen, bei denen die Palette beim
Nachwiegen *mehr* wog als beim Eingang (420 → 1180 kg brutto nach zwei
Tagen), drücken die gepoolte Verdunstungsrate auf −0.2 je Tag. Die Basis
für den Schimmelanteil ist Eingang × (1 − Rate)^Lagertage; mit 1.2^170
wird aus 700 kg eine Zahl mit 16 Stellen, und `numeric(12,2)` hält zehn.

### Was daraus folgt

Verdunstung nimmt Masse, sie gibt keine. Eine Palette, die schwerer
geworden ist, ist keine Beobachtung über Verdunstung, sondern über die
Erfassung: falsche Gebindeart (Tara), falsche Kistenzahl oder ein
Zahlendreher. Drei Dinge sind deshalb geändert (0056, AB-20):

1. `v_verdunstung_messung.verwendbar` verlangt, dass das Netto jetzt
   höchstens 1 % über dem Netto beim Eingang liegt. Das eine Prozent ist
   die Toleranz zwischen zwei Waagen — die Palette wurde beim Eingang oft
   auf einer anderen gewogen als beim Nachwiegen. Darüber ist es kein
   Rauschen mehr. Die Wägung bleibt gespeichert (gelöscht wird nichts,
   was Daten trägt) und steht unter Auffälligkeiten: „sie wiegt jetzt
   760 kg mehr als beim Eingang, und im Lager wird keine Palette
   schwerer", mit dem Rat, Gebindeart, Kistenzahl und beide Gewichte zu
   prüfen.
2. `v_koeff_verdunstung` gibt nie eine negative Rate aus. Kleine Zunahmen
   innerhalb der Toleranz bleiben Messungen (die Einzelrate steht, wie
   sie gemessen wurde), drücken das Mittel aber höchstens auf 0 — „keine
   messbare Verdunstung". NULL bleibt NULL: ohne Wägung ist die Rate
   unbekannt, nicht null.
3. `v_schimmel_beobachtung` rechnet die Basis mit derselben gedeckelten
   Rate wie Kaskade und Bestand (0 … 5 % je Tag, seit 0030 beziehungsweise
   0051) und mit Lagertagen ≥ 0. Ein Eingangsdatum in der Zukunft
   (Tippfehler) kann so nichts mehr sprengen; die Basis ist höchstens der
   Eingang, und das prüft `pruefung.sql`.

### Warum setup.sql trotzdem abbrach — und jetzt nicht mehr

Die Korrektur allein hätte den Hof nicht erreicht. `setup.sql` ist die
ganze Geschichte der Datenbank hintereinander; auf einer bestehenden
Datenbank räumt 0000 das Rechenwerk weg und die Datei baut es neu auf.
Dabei wurden die gespeicherten Auswertungen (`mv_…`) an der Stelle
gefüllt, an der ihre Migration sie anlegt — mit der Formel *dieser*
Migration auf den *echten* Daten. Die Fassung von 0016 kannte die
Deckelung nicht und lief über, lange bevor die Datei bei 0056 ankam. Ein
längst korrigierter Rechenfehler blockierte so jede Aktualisierung.

Deshalb legen alle Migrationen ihre gespeicherten Auswertungen jetzt ohne
Inhalt an (`create materialized view … with no data`), und die frühe
Füllung in 0016 ist weg. Gerechnet wird einmal, am Ende von `setup.sql`,
mit den heutigen Formeln — in einem Block, der einen Fehler abfängt: die
Datenbank ist dann trotzdem aktualisiert, die Fertig-Zeile sagt
„Auswertung NICHT berechnet (…)" mit dem Grund, und die App rechnet beim
nächsten Öffnen erneut. `run.sh` verlangt in jeder Stufe, die setup.sql
einspielt, das „Auswertung berechnet." in der Fertig-Zeile; die neue
Stufe 4b spielt den Fall vom 7. September nach (Demo, drei schwerere
Paletten, Aktualisierung, Dashboard-Sichten, drei Auffälligkeiten).

Das ist eine Änderung an alten Migrationen — hier bewusst: Die einzige
Art, wie sie je ausgeführt werden, ist als Teil von `setup.sql`, und
`with no data` ändert am Ergebnis nichts, nur daran, *wann* gerechnet
wird. Stufe 3b (alter Stand mit Daten, dann die heutige Datei) und der
Aufstiegstest (alte Demo bis 0050, dann 0051 ff.) laufen unverändert.

### Nachtrag: Die Datenbank sagt, auf welchem Stand sie ist (0057)

Nach 0056 kam vom Hof: „im Überblick ist weiterhin numeric overflow".
Gefuzzt auf einer Kopie der Demo mit dem 0056-Stand — Eingangsdatum im
Jahr 2027, Arbeit 400 Tage vor dem Eingang, Wägungen mit 85 % Verlust
an einem Tag, 99 Millionen gezählte Kisten, Palette mit zehn Millionen
Kilo (die Spalte lässt das gar nicht zu) — bringt keine Dashboard-Sicht
mehr zum Überlaufen; nur eine erfundene Sortier-CSV-Zeile mit 10^13 Gramm
tut es noch, und die schreibt kein Parser. Wahrscheinlichste Erklärung:
Die App lief gegen eine Datenbank, die 0056 noch nicht hatte. Das kann
die App bisher nicht wissen — sie ruft Sichten, und die antworten mit
den Formeln, die dort stehen.

Deshalb 0057: `schema_stand()` nennt die Nummer der jüngsten Migration;
die Auswertung fragt sie als Erstes ab und vergleicht mit
`SCHEMA_ERWARTET` in `src/lib/version.ts`. Bei Abweichung (oder wenn die
Funktion fehlt, also vor 0057) steht im Klartext, dass Schritt 3 zu
wiederholen ist. Jede Fehlermeldung aus einer Sicht trägt jetzt den
Namen der Sicht („v_plausibilitaet: numeric field overflow"). Dazu
`supabase/diagnose.sql` für den SQL-Editor: Stand, Neuberechnung, jede
Sicht des Überblicks, und die Rohdaten, die Formeln sprengen können —
als Tabelle, die sich kopieren lässt. Regel: jede Migration setzt
`schema_stand()` auf ihre Nummer und zieht `SCHEMA_ERWARTET` nach;
`run.sh` (Stufe 1) und `npm test` schlagen sonst an. Und
`v_ausschuss_beobachtung` rechnet seine Basis jetzt ebenfalls mit der
gedeckelten Rate — die letzte Sicht, die (1 − Rate)^Lagertage roh nahm.

## Eine Zahl darf nicht den ganzen Bildschirm kosten (0058)

Nach 0056 und 0057 kam vom Hof zum dritten Mal „numeric field overflow" —
jetzt mit Namen, weil 0057 den Sichtnamen in die Meldung schreibt:
`v_hochrechnung`. Die Diagnose auf der Betriebsdatenbank zeigte: Stand
0057, Verdunstungsrate sauber (0.000470 … 0.000475), Auswertung rechnet
durch, aber `v_saisonbilanz` und `v_marge_buch` scheitern. Es waren also
nicht mehr die Rohdaten, sondern die Sichten, die daraus Hochrechnung,
Bereiche und Bilanz machen.

### Der eigentliche Konstruktionsfehler

Diese Sichten casten berechnete Grössen hart auf `numeric(14,2)`,
`numeric(12,6)` oder `numeric(10,4)`. Ein solcher Cast ist eine
*Behauptung* über den Wertebereich. Bei einer gespeicherten Spalte ist das
richtig — dort ist er eine Zusage über die Daten. Bei einer berechneten
Grösse ist er eine Wette: Trifft sie nicht zu, bricht nicht die eine Zahl
weg, sondern **die ganze Sicht**. Der Betriebsleiter sieht dann einen
leeren Bildschirm mit einer Meldung, die ihm nichts sagt, und kann nichts
tun. Das ist die schlechteste aller Ausfallarten — und sie hat sich in
drei Runden dreimal gezeigt, jedes Mal an einer anderen Stelle. Nicht die
Stellen waren das Problem, sondern das Muster.

Zwei Beispiele, beide realistisch:

- `luecke_anteil` ist `(Eingang − Verlust − Ausgang − …) / Eingang`, hart
  auf `numeric(10,4)`, also unter 10⁶. Ist der Warenausgang eingelesen und
  der Wareneingang noch nicht (das Erntejournal ist ein eigener Import),
  wird das Verhältnis beliebig gross — und die Bilanz bricht ab, statt zu
  sagen, dass der Eingang fehlt.
- `kg_unten` und `kg_oben` sind Wert ± t · Streuung. Die Streuung kommt aus
  einer fortgepflanzten Varianz; bei wenigen Messpunkten kann sie sehr
  gross werden. Der Mittelwert ist dann noch brauchbar, der Bereich nicht
  — abbrechen darf deswegen nichts.

### Was 0058 ändert

`zahl(wert, stellen, grenze)` rundet wie bisher, gibt aber **NULL statt
eines Fehlers**, wenn der Wert nicht in die Zielspalte passt. NULL heisst
im ganzen Projekt „unbekannt", und genau das ist es: Die Zahl ist nicht
ermittelbar. Die App zeigt dafür „—", der Rest des Bildschirms steht. Alle
Casts in `v_hochrechnung`, `verlust_ranking()`, `v_saisonbilanz` und
`v_marge_buch` laufen jetzt darüber — und zwar *alle*, nicht nur die, an
denen es gerade geklemmt hat. Welcher Wert es auf dem Hof war, ist damit
nicht mehr entscheidend.

Dazu zwei inhaltliche Korrekturen, die keine Notbremsen sind, sondern
Physik: Jeder Koeffizient in der Hochrechnung ist ein **Anteil** und wird
auf 0 … 1 geklammert — bisher galt das für r, f, zu klein und zu gross,
nicht aber für den Sockel a₀. Und jede Masse ist **nie negativ**. Ein
Anteil über 1 oder eine negative Masse gibt es nicht; wo sie entstünden,
ist die Rechnung ohnehin falsch, und die Klammerung macht sie wenigstens
nicht unmöglich darstellbar.

Schliesslich nennt die Bilanz den häufigsten Grund jetzt beim Namen: „Es
ist weit mehr ausgeliefert als eingelagert. Fast immer fehlt der
Wareneingang (Erntejournal noch nicht eingelesen) oder er deckt nur einen
Teil der Saison ab." Das ist die Antwort, die der Betriebsleiter braucht —
nicht eine Fehlermeldung über Zahlenformate.

### Was die Diagnose falsch gemacht hat

`supabase/diagnose.sql` prüfte jede Sicht mit `select count(*)`. Postgres
wertet die Spaltenausdrücke dabei **gar nicht aus** — die Casts laufen nie.
Deshalb meldete die Diagnose `v_hochrechnung` als lesbar, während die App
genau an ihr scheiterte. Sie prüft jetzt mit `select *`, gibt zusätzlich
`pg_exception_detail` aus (die Zeile, die sagt, welche Präzision überlief)
und listet die Grössenordnungen, die einen Überlauf erklären: Ein- und
Ausgang, die Extremwerte der Kaskade, die Modellvarianzen, die Ströme mit
ihren Bereichen und das Sollgewicht je Kiste. Eine Diagnose, die eine
falsche Entwarnung geben kann, ist schlimmer als keine.

## Aufhören, Sicht für Sicht zu flicken (0059)

Nach 0058 kam vom Betrieb `v_massenbilanz: numeric field overflow`. Das war
vorhersehbar und mein Fehler. 0056 hat die Rohdaten abgesichert, 0057 den
Stand sichtbar gemacht, 0058 vier Sichten gehärtet — jedes Mal die, an der
es gerade klemmte. Im Schema stehen aber **26 Sichten mit zusammen 89
harten Casts** auf berechnete Grössen. Jeder einzelne kann eine Sicht
sprengen, und welcher es trifft, hängt an den Daten des Betriebs. Sie
einzeln abzuwarten hätte den Betriebsleiter noch zwanzigmal vor einen
leeren Bildschirm gestellt.

### Der Umbau

Statt weiterzuflicken: alle auf einmal, mechanisch und nachprüfbar. Ein
Umschreiber liest jede Sichtdefinition über `pg_get_viewdef`, findet jeden
`::numeric(p,s)`, bestimmt den Anfang des Ausdrucks davor (mit Klammer-,
`CASE … END`- und Fensterfunktions-Behandlung) und legt `zahl(…, s,
10^(p−s))` darum. Der Cast bleibt stehen — deshalb ändern sich die
Spaltentypen nicht, und `create or replace view` genügt ohne Kaskade.

Nachgewiesen ist die Gleichwertigkeit, nicht behauptet: Auf der Demo-Saison
liefern alle 26 umgeschriebenen Sichten Zeile für Zeile denselben Inhalt
(Prüfsumme je Sicht), und alle **777 Spalten** aller Sichten behalten ihren
Typ. Es ändert sich ausschliesslich, was passiert, wenn eine Zahl nicht
darstellbar ist: vorher Abbruch der Sicht, jetzt NULL in dieser einen
Spalte.

Drei gespeicherte Sichten bleiben bewusst aussen vor, mit Begründung im
Prüfblock: `mv_auftrag_masse.lagertage` ist eine Differenz zweier
Datumswerte, `mv_sortier_lauf_masse.masse_kg` und
`mv_kaliber_verteilung.masse_kg` sind Σ Anzahl × Gramm ÷ 1000 mit Gramm
unter 60 000 aus der CSV-Reinigung. Beide sind durch die Reinigungsregeln
beziehungsweise den Datumsbereich von Postgres schon begrenzt, und sie
liessen sich nur mit `drop … cascade` über die ganze Kette ändern. Ändert
sich eine Reinigungsregel, gehört die Ausnahmeliste geprüft — das steht
neben der Liste.

### Der Rückfallschutz

`pruefung.sql` zählt in jeder Sicht die engen Casts und die
`zahl()`-Aufrufe und verlangt Gleichheit. Wer künftig einen harten Cast
einbaut, hört es beim nächsten Testlauf statt Wochen später vom Betrieb.
Dazu die Gegenprobe: Jede Sicht, die das Dashboard lädt, wird mit
`select *` gelesen — `count(*)` wertet die Spaltenausdrücke nicht aus und
hätte genau diese Fehlerklasse durchgelassen.

### Und die zweite Hälfte: die App darf nicht mitsterben

Der Backend-Umbau macht einen Ausfall unwahrscheinlich, nicht unmöglich.
Deshalb lädt die Auswertung jede Sicht jetzt **für sich**: Scheitert eine,
sind ihre Zahlen unbekannt, alles andere steht, und oben auf dem Reiter
sagt eine Karte, welche Sicht es war und woran es lag. Auch ein
gescheitertes Neurechnen bricht nicht mehr ab — dann wird mit dem letzten
gespeicherten Stand weitergearbeitet, und das steht dabei.

Das ist der eigentliche Fortschritt dieser Runde: Vorher konnte **eine**
Zahl den ganzen Bildschirm kosten. Jetzt kostet sie sich selbst.

## Punktuell erfasst, vollständig gerechnet (Runde G: 0060)

Der Betrieb hat am 8. September die App Maske für Maske durchgesehen und
siebzehn Punkte zurückgegeben. Die meisten betreffen einzelne Fragen — was
beim Fax gezählt wird, ob der Käufer gefragt wird, wie der Palox beim Waschen
geführt wird. Einer betrifft das Fundament, und mit ihm beginnt diese Runde:

> Du kriegst hier nur punktuelle Messungen. Du weisst nur, wie viel noch im
> Lager ist, beim Vergleich von Eingang und Ausgang.

### Was falsch war

Bis 0059 kannte die Rechnung die Menge „ausgelagert" aus den **gezählten
Paletten**: Jede Arbeit zählt, was sie aus dem Lager holt, und die Kaskade
nahm diese Zählung als Masse, die die Halle verlassen hat. Das ist eine
Annahme, die im Betrieb nie galt. Nicht jede Arbeit wird in der App erfasst —
vielleicht fünfzehn Waschgänge in einer Saison —, und was nicht gezählt wird,
liegt in der Rechnung noch im Lager, altert weiter und verdirbt weiter. Der
Bestand war zu hoch, der Verlust zu hoch, und beides ohne Warnung. Das PDF
behauptete an einer Stelle sogar, aus dem Zählen folge, „wie viel noch liegt,
je Eingangstag". Das war falsch.

### Der Kern: das Ausgelagerte kommt aus den Lieferungen

Vollständig sind zwei Listen: der Wareneingang (jede Palette, aus dem
Erntejournal) und der Warenausgang (jede Lieferung, aus den Lieferscheinen).
Alles dazwischen ist Stichprobe. Also muss die Rechnung von den beiden Enden
her laufen:

```
hinter einer verkauften Lieferung L am Tag d (Charge c, Eingangstag e):
    Eingangsmasse  =  L ÷ verkaufsfähiger Anteil beim Alter (d − e)
ausgelagert(c, e) =  Σ dieser Eingangsmassen, verteilt nach Eingangsanteil des Tags
lager(c, e)       =  eingang(c, e) − ausgelagert(c, e)          (≥ 0)
```

Der verkaufsfähige Anteil ist derselbe Koeffizientensatz wie vorher
(Verdunstung, Verderb beim Alter, zu klein, zu gross, Fax), nur rückwärts
angewandt — die Lieferung sagt, was am Ende herauskam, das Modell sagt, wie
viel dafür hineingehen musste. Der Anteil ist nach unten auf 0.25 geklammert,
damit eine Lieferung an eine sehr alte Kohorte nicht das Vierfache der Halle
verlangt. Es gibt kein FIFO: eine Lieferung geht auf alle Eingangstage der
Charge im Verhältnis ihres Eingangs, weil die App nicht weiss, welche Palette
gegangen ist. Eine Lieferung ohne Charge geht auf die Chargen der Sorte, ebenso
nach Eingangsanteil. Der Vorlauf (AB-07) ist eine Pseudo-Lieferung am
Erfassungsbeginn.

Was übrig bleibt, ist der Bestand — nicht als Projektion aus gezählten
Paletten, sondern als Differenz zweier vollständiger Listen, jeweils mit
seinem Alter. Auf diesen Bestand läuft die Kaskade weiter bis zum Stichtag.
Die Bilanz „Eingang = Verlust + Kanal + verkauft + verkaufsfähig im Haus"
schliesst dadurch von selbst; geprüft wird an den Rändern: Was an die Tiere
und in den Nebenkanal geliefert wurde, gegen das, was das Modell dafür
rechnet — und die **Überzählung**: Steckt hinter den Lieferungen einer Charge
mehr Eingangsmasse, als je eingelagert wurde, fehlt fast immer der
Wareneingang dieser Charge oder eine Lieferung ist falsch zugeordnet. Das
steht als Befund im Klartext, und eine Lieferung an eine Charge ohne
jeden Eingang fällt eigens auf.

Die gezählten Paletten bleiben, was sie sind: der Nenner der Palox-Messung
und das Alter der Arbeit. Sie bestimmen keine Menge mehr. `v_charge_kohorte`
zählt sie noch je Eingangstag („in der App gezählt") — als Information, nicht
als Bestand.

### Was der Test dabei lehrte

Der alte Kette-Test verlangte, dass die Überfüllung auf eine geänderte
Einstellung `soll_kg_pro_kiste` reagiert. Sie tat es nach 0060 nicht mehr, und
das war richtig: Das Soll steht jetzt an der Arbeit (Kistensystem), nicht in
einer Einstellung, und die Kistenzahl der Überfüllung folgt der **verkauften
Masse** — mehr verkauft, mehr Kisten, mehr verschenkt. Der Test prüft jetzt
genau das: Eine Lieferung hebt die Überfüllung, ein höheres Soll an der
Arbeit senkt sie. Ein Test, der eine falsche Annahme prüft, ist gefährlicher
als keiner.

### Fax nach beiden Wegen, eine Fax-Art

Der Betrieb: Fax gibt es auch nach dem Waschen + Sortieren, und es sind
dieselben Handgriffe. Also eine Art. Gezählt wird nicht mehr je Kaliber,
sondern die **Palettenzahl gesamt** (eine Zahl, „+ 1"), das Faule wird
kistenweise gewogen, und freiwillig die Tage seit dem Waschen — die
Grösse, die den Waschschaden vom Liegen nach dem Waschen trennt. Die Masse
einer Fax-Arbeit ist Paletten × gemessene Palettenmasse je Sorte und
Kistensystem (`v_koeff_palette_netto`, aus den gewogenen fertigen
Paletten; Rückfall auf die Sorte). Wo keine fertige Palette je gewogen
wurde, ist die Fax-Masse unbekannt — und die Datenqualität sagt es.

### Zettelgewicht statt Ausschuss

Beim Waschen + Sortieren wird zu klein und zu gross nicht mehr gewogen: Der
Anteil kommt aus der Sortier-CSV, so gut wie auf Weg 1 — der Betrieb sortiert
von Hand nach denselben Grenzen. Dafür tippt der Zähler je Palette das
**Gewicht vom Zettel** (Pflicht, jede Palette neu, weil sich Gewichte
unterscheiden; das Datum bleibt stehen). Das Netto folgt der Palette im
Wareneingang mit genau diesem Brutto, Datum und dieser Charge; passt keine,
der mittleren Tara der Charge — und ein Zettelgewicht ohne Palette fällt auf,
denn es ist ein Zahlendreher oder eine fehlende Palette im Erntejournal. Das
ist der gemessene Nenner der Handlinie, ohne eine zweite Wägung.

### Kistensystem statt Käufer

„Für wen?" fiel weg. Was die Rechnung braucht, ist nicht der Käufer, sondern
das **Kistensystem**: Kiste ab x kg (Soll — daraus Überfüllung), x Stück je
Kaliber (Erwartung aus der CSV: Stück × mittleres Bandgewicht — eine
Information für den Packplatz, keine Marge) oder anderes (nicht rechenbar,
ehrlich gesagt). Fertige Paletten werden gewogen, wo das System rechenbar ist.
Alte Arbeiten behalten ihren Käufer; keine Maske schreibt ihn mehr, und der
Lückenscanner kennt die Begründung.

### Zwei Stationen, ein gefallener Palox

Es gibt nur die **Waschstrasse** und die **Sortiermaschine**. Waschen +
Sortieren ist die Waschstrasse mit Sortieren am Band — derselbe Palox.
`palox_station()` bildet das ab, ohne die alte Station an den Aufträgen zu
ändern. Fällt der Stand zwischen zwei Ablesungen, wurde geleert: kein Häkchen
mehr, die Menge dieser Arbeit ist unbekannt (NULL, nicht negativ, keine
angenommene Zahl), die Arbeit hat keinen Punkt in der Kurve, und der Befund
„Palox geleert" sagt es dem Betriebsleiter. Beim Waschen ist die Ablesung
freiwillig — der Betrieb wollte den Arbeiter dort nicht damit aufhalten.

### Sortierdatum je Kiste, Kontrolle mit Vorschlag, Wörter

Beim Waschen fragt der Zähler das **Sortierdatum von der Kiste**, mit „kein
Datum" als echter Antwort; die Kisten je Kaliber werden über die Daten
summiert. Die Lagerkontrolle schlägt **drei Chargen** vor (bestandsstärkste,
wenigste Kontrollen), fragt Eingangsdatum und Eingangsgewicht vom Zettel und
nimmt mehrere Paletten hintereinander. Und „Buch A" / „Buch B" sind aus der
Oberfläche verschwunden: Die Ursachen trennen echten Verlust von keinem echten
Verlust, der Überblick zeigt den Verlust zusammen — nach Gesamt, Sorte, Schlag
und Charge, das Faule aus dem Palox als „Palox". Die Grundaussortierung
(Sockel) rechnet im Modell weiter, ohne eigene Maske und ohne eigenen Balken.

### Zwei Antworten auf Rückfragen des Betriebs

- **Warenausgang Juli/August:** Die zweite Excel-Datei enthält zehn
  Kürbis-Zeilen im Juli 2026 ohne Chargennummer, die erste beginnt im August.
  Beide sind importierbar; die Juli-Lieferungen verteilen sich je Sorte auf
  die Chargen (AB-23), sobald die Artikel bestätigt sind.
- **Datum stehen lassen:** Bleibt — mit zwei Änderungen: Der „+"-Knopf zeigt
  das Datum, das er speichert („+ 1 Palette · 01.09."), und beim Waschen +
  Sortieren muss das Gewicht je Palette neu getippt werden, das Datum nicht.

### Was der Lasttest fand: der JIT

Mit 0060 hat die Kaskade je Eingangstag statt je Charge Zeilen — rund
zwanzigmal mehr —, und der Lasttest (4300 t, 840 Arbeiten) meldete das
Dashboard mit 2.8 statt 0.75 Sekunden. Die Suche führte nicht zu einer
langsamen Sicht, sondern zum Postgres-JIT: Bei geschätzten Plankosten über
100 000 übersetzt Postgres die Ausdrücke einer Abfrage vor der Ausführung
in Maschinencode, und diese Übersetzung kostete bei `v_plausibilitaet`
(vierzehn Zweige) eine Sekunde und bei `verlust_ranking()` zwei — für
Abfragen, die ohne JIT in 120 beziehungsweise 490 Millisekunden fertig
sind. Für Abfragen dieser Art — viele Ausdrücke, wenige Zeilen — ist der
JIT eine Bremse; PostgreSQL 19 schaltet ihn deshalb standardmässig ab.

Zwei Massnahmen: `v_hochrechnung` (ein Strom je Charge, Portion und
Eingangstag) ist jetzt gespeichert (`mv_hochrechnung`, mit der Kaskade
erneuert), und die Datenbank schaltet den JIT ab — als Einstellung der
Datenbank, wo das erlaubt ist, sonst mit einem Hinweis, und für
`verlust_ranking()` und die Neuberechnung in jedem Fall. Das Dashboard
liegt damit wieder bei den früheren Werten.

### Was offen bleibt

- Die Klammer 0.25 für den verkaufsfähigen Anteil ist eine Setzung, keine
  Messung. Sie greift nur bei sehr alten Kohorten; wo sie greift, steht die
  Überzählung als Befund.
- Der Bestand je Eingangstag folgt dem Eingangsanteil. Verarbeitet der
  Betrieb systematisch das Jüngste zuerst, liegt das gerechnete Alter im Haus
  zu jung — „liegt seit" bleibt deshalb eine Spanne.
- Die Palettenmasse je Kistensystem kommt aus wenigen Wägungen. Ihr Bereich
  steht an der Fax-Masse; ohne Wägung gibt es keine.

## Bis heute, gespeichert, nur Gemessenes (Runde H: 0061)

Die zweite Durchsicht galt der Auswertung selbst. Drei Vorwürfe, alle
berechtigt: die Zahlen behaupten mehr, als sie wissen; das Dashboard lädt zu
lange und stirbt manchmal ganz; und die Arbeiter-App fragt an mehreren
Stellen nach Dingen, die niemand beobachten kann.

### „Heute" ist ein Datum, kein Saisonende

Die Kaskade rechnete bisher jede Portion bis zu ihrem Ende durch: liegende
Ware bis zum Ende der Lagerung, Verlust also inklusive dessen, was erst noch
kommt. Auf dem Überblick stand damit ein Verlust, den es noch gar nicht
gibt, und ein Bestand, der um genau diesen Betrag zu klein war.

0061 führt `heute()` ein — normalerweise `current_date`, im Test die
Einstellung `heute_test`, damit Prüfungen ein festes Datum haben. Jede
Portion altert bis `stichtag()`: ausgelagerte Ware bis zu ihrem Liefertag,
liegende bis heute. Daraus:

- `verlust_heute_kg` = Verdunstung + Schimmel + Sockel + Fax, alles bis heute;
- `im_haus_heute_kg` = Eingang − Ausgang − Verlust bis heute;
- was danach käme, steht nur im Verlauf, ab der Heute-Marke gestrichelt, und
  fliesst in keine Kennzahl.

Ein Sonderfall kostete einen halben Tag: Fax-Verlust an Ware, die noch im
Lager liegt, ist **Erwartung, kein Verlust** — er steht als `fax_erwartet_kg`
getrennt und zählt nicht in `verlust_heute_kg`. Ohne diese Trennung wurde die
Ware doppelt abgezogen und die Saisonbilanz zeigte eine Lücke von 6.3 t, wo
in Wahrheit eine Überzählung stand.

### Die App rechnet nicht mehr beim Hinsehen

Bisher waren die Dashboard-Zahlen Sichten: Jeder Seitenaufruf rechnete die
halbe Auswertung neu, ein Dutzend Sichten gleichzeitig, und bei genügend
Daten schlug Supabases 8-Sekunden-Grenze zu — sieben Sichten meldeten
„statement timeout", die Seite zeigte eine halbe Auswertung.

Jetzt gibt es zu jeder gelesenen Sicht eine gespeicherte Fassung (`erg_*`,
materialisiert). Die App liest nur diese; sie rechnet nichts. Neu gerechnet
wird auf Knopfdruck, in **fünf Schritten**, jeder ein eigener Aufruf mit
eigener Verbindung und eigenem Zeitbudget:

| Schritt | Was er erneuert | Demo | Dreifache Saison |
|---|---|---|---|
| 1 | Rohdaten (Wägungen, Gebinde, Ausgang, Lieferungen) | 0.1 s | 0.5 s |
| 2 | Arbeiten (Massen, Fax, Ausschuss, Durchsatz) | 1.1 s | 1.7 s |
| 3 | Kaskade (Kohorten, Ströme je Eingangstag) | 0.7 s | 1.3 s |
| 4 | Ergebnis (Verlust, Verlauf, Chargen, Bilanz) | 1.2 s | 1.6 s |
| 5 | Befunde (Plausibilität, Datenqualität) | 0.2 s | 0.2 s |

Der Fortschritt steht auf dem Bildschirm; scheitert ein Schritt, nennt die
App ihn beim Namen, und die übrigen Zahlen bleiben stehen. `run.sh` prüft
jeden Schritt einzeln gegen eine Grenze von 6 Sekunden — die Liste der
gelesenen Ansichten holt es aus dem Frontend-Quelltext, damit sie nicht
auseinanderdriftet.

Der Nebeneffekt ist die eigentliche Zahl: alle dreissig gelesenen Ansichten
zusammen brauchen jetzt **25 Millisekunden** statt mehrerer Sekunden.

### Was der Lasttest fand: eine Kurve, 113 000 mal gerechnet

Bei dreifacher Saison brauchte Schritt 4 zunächst 5.7 Sekunden — nah an der
Grenze, ab der Supabase abbricht. Schuld war eine einzige Sicht: der Verlauf
je Woche. Er rechnet für jede Portion der Kaskade und jede Woche das
Verderbsmodell F(t) aus; bei 1890 Portionen und 60 Wochen sind das 113 000
Auswertungen, jede mit einer Suche in der Verderbskurve (Sortieren und
Abschneiden je Zeile).

F(t) hängt aber nur vom Alter in Tagen ab, von sonst nichts. Also wird es
einmal je Tag gerechnet — rund 400 Zeilen — und angejoint. Der Verlauf fällt
von 4.9 auf 0.65 Sekunden, Schritt 4 von 5.7 auf 1.6, und die Zahlen sind
bis auf die letzte Nachkommastelle dieselben (geprüft an Summe des Bestands
und des kumulierten Verlusts über alle 372 Zeilen).

Das ist derselbe Fehlertyp wie der JIT-Fund in 0060: nicht eine falsche
Formel, sondern eine richtige Formel an der falschen Stelle im Plan.

### Und der zweite Fund: veraltete Statistik

Derselbe Lasttest zeigte kurz darauf 33 Sekunden für Schritt 2 — bei
denselben Daten, die er sonst in 1.1 schafft. Der Unterschied war nicht die
Datenmenge, sondern der Zeitpunkt: unmittelbar nach einem grossen Import.
Postgres schätzt Pläne aus Statistiken, die ein Hintergrundprozess pflegt;
direkt nach dem Laden stehen dort noch die Zahlen von vorher, und der Planer
wählt Verschachtelungen, die um Grössenordnungen danebenliegen.

Genau dieser Fall trifft den Betrieb am ersten Tag: Daten einspielen, dann
rechnen. Schritt 1 analysiert deshalb zuerst alle Rohtabellen des Schemas —
auf der Demo 0.2 Sekunden — und rechnet erst danach. Die gespeicherten
Sichten werden ohnehin nach jedem Erneuern analysiert.

### Waschen zählt Paletten

Beim Waschen aus dem Zwischenlager zählte die App bisher Kisten, je Kiste mit
Sortierdatum. Der Betrieb: Die Kisten stehen auf Paletten, und der Zettel mit
dem Sortierdatum hängt an der Palette. Also wird gezählt, was dort steht: die
Palette, mit Sortierdatum vom Zettel und Kistenzahl darauf (Vorgabe aus der
Einstellung, änderbar, wenn eine nicht voll ist). Die Masse ist Kisten ×
gemessenes Kistengewicht des Kalibers; die Zeit im Zwischenlager kommt
massegewichtet aus den Sortierdaten.

Damit teilen sich zwei sehr verschiedene Dinge eine Tabelle: die
Eingangspalette (Eingangsdatum, Zettelgewicht) und die Kaliber-Palette
(Sortierdatum, Kisten). Die Sicht auf den Wareneingang schliesst Zeilen mit
Kistenzahl aus — sonst hätte die Demo-Saison 119.5 t Eingang zu viel gehabt.

### Was die App nicht mehr fragt

Drei Fragen sind ersatzlos weg, weil ihre Antwort keine Beobachtung war:

- **„Davon faul" bei der Lagerkontrolle.** Die Palette wird gewogen, nicht
  ausgepackt. Was das kostet: Die Kontrolle ist kein Punkt der Schimmelkurve
  mehr, nur noch der Verdunstungskurve. Die Kurve verliert die einzigen
  Punkte, deren Palette nicht nach Aussehen gewählt wurde
  (`STATISTIK_BEFUND.md`) — dafür steht in ihr nichts Erfundenes mehr.
- **„Wie wurde die Palette gegriffen?"** Wer greift, weiss selten, ob er
  zufällig greift; die Antwort war Selbsteinschätzung, nicht Beobachtung.
- **„Faules sichtbar" beim Wiegen einer Eingangspalette.** Dieselbe Sache:
  ein Blick auf die Aussenseite eines Stapels.

Geblieben ist der **Palox beim Waschen**: gefragt, nicht Pflicht. Er ist
die einzige Messung dieser Station, die Faules beziffert; verlangen kann man
sie nicht, weil die Waschstrasse ihn mit dem Waschen + Sortieren teilt und
nicht jede Arbeit ihn leert.

### Überfüllung: nur, wo gewogen und verkauft

Verschenkte Marge war bisher „Überschuss je Kiste × alle Kisten" — die Zahl
der Kisten war geraten. Jetzt zählt der Import die verkauften Kisten aus den
Verkaufsdateien mit (`AufPosBatchPackageQuantity`, sonst aus Menge und
Kisteninhalt), und verschenkt wird nur beziffert, wo eine Wägung **und**
verkaufte Kisten vorliegen. Ohne Datei oder ohne Wägung steht NULL, nicht 0.
Der Käufer kommt nirgends mehr vor; getrennt wird nach Kistensystem: „Kiste
ab x kg" hat eine Marge, „x Stück je Kiste" hat keine — dort sagt die
Abweichung vom erwarteten Stückgewicht nur, wo im Band die Ware liegt.

### Was offen bleibt (Runde H)

- **Überfüllte Ware steht rechnerisch noch im Haus.** Sie verlässt den
  Betrieb in verkauften Kisten, ohne bezahlt zu werden; die Bilanz kennt sie
  nur als Marge, nicht als Abgang. Solange die Überfüllung klein gegen die
  Liefermenge ist, verschiebt das den Bestand um wenig — sauber wäre es erst,
  wenn die Lieferzeile das tatsächliche Kistengewicht trüge.
- **In der Datei eines Käufers steht bei 225 Kilo-Zeilen `GewichtProArtikel`
  auf 0** (zusammen 174.8 t). Der Import übergeht sie als „ohne Masse". Das
  ist keine stille Lücke — die Datenlage weist sie aus —, aber es ist auch
  keine Lösung; sie braucht eine Antwort vom Betrieb, welches Gewicht dort
  gemeint ist.
- Die Erinnerung an drei Wägungen und drei fertige Paletten ist bewusst
  keine Sperre. Wer sie überspringt, verliert die Verdunstungsrate dieser
  Arbeit und das Kistengewicht — sichtbar in der Datenqualität, nicht in
  einer Blockade.

## Runde I — jede Zahl sagt, was sie ist (8. September, Migration 0062)

Der Betriebsleiter in Runde I: „auf der Webseite hast du immer noch so
komische Angaben wie einfach einen Verlust, der nicht klar ist." Das war kein
Schönheitsfehler. Ein Wort, das zwei Dinge bedeutet, ist ein Rechenfehler mit
Verzögerung: Irgendwann addiert jemand zwei Zahlen, die nicht zusammengehören.

### Ein Prüfstand, der liest, was ein Mensch liest

`pruefstand/beschriftung.mjs` rendert die zwölf Ansichten des Betriebsleiters
in einem echten Browser mit den echten Demo-Daten und erntet **jede Zahl mit
Einheit samt ihrer Beschriftung** — aus der Kennzahl, dem Spaltenkopf, dem
Zeilenkopf einer Matrix, dem Begriff einer Liste. Nicht der Quelltext wird
geprüft, sondern das Bild.

Sechs Regeln, dazu die Gegenprobe:

- **R1** Jede Zahl hat eine Beschriftung.
- **R2** Jede Beschriftung einer Masse steht im Begriffslexikon
  `pruefstand/begriffe.json` — mit Bedeutung und Herkunftsspalte. Der
  **längste** passende Eintrag gewinnt: „Gewogene Masse · zu klein" ist eine
  gewogene Masse, kein hochgerechneter Kanal.
- **R3** „Verlust" nie ohne Zusatz.
- **R4** Jede gerechnete Grösse trägt in ihrer Karte die Herkunftsmarke, die
  zu ihr gehört. Ein Begriff, der beides sein kann, steht als
  `gemessen|gerechnet` im Lexikon — dann muss die Karte sagen, welches gilt.
- **R5** Jede Prozentzahl nennt ihre Bezugsgrösse.
- **R6** Keine Modellwörter („Buch A/B"), keine kaputten Zahlen.
- **Gegenprobe**: die vier Kopfzahlen des Überblicks, unabhängig aus
  `erg_bilanz` nachgerechnet. Eine richtige Beschriftung an einer falschen
  Zahl wäre schlimmer als gar keine.

2667 Zahlen, zwölf Ansichten, grün. Was der Prüfstand dabei gefunden hat:

- **Ein `NaN` auf der Messungen-Seite** — die Karte las eine Spalte, die es
  nach der Umbenennung nicht mehr gab. Auf dem Bildschirm stand „NaN t · NaN %".
- **Nackte Massen**: „Masse" stand an sechs Stellen für sechs verschiedene
  Dinge. Jetzt: Bewegte Masse, Masse der Lieferung, Masse in der Datei, Masse
  des Artikels, Gewogene Masse.
- **Zwei Erklärungen unter 36 Tabellenzeilen.** Die Legende der Chargen-Seite
  sagte richtig, welche Spalte gemessen und welche gerechnet ist — nur stand
  sie hinter der Tabelle, wo sie niemand liest. Sie steht jetzt darüber.
- **Eine nackte Tonnage** im Untertitel der Charge-Zeilen, ohne ein Wort daneben.

### Zwei Rechenfehler

**Lieferungen an die Tiere fehlten auf der Ausgangsseite.** Die Kaskade nahm
als ausgelagert nur, was mit `buch = 'verkauf'` geliefert wurde. Was an die
Tiere oder in den Nebenkanal ging (`buch = 'marge'`), hatte den Betrieb
verlassen — auf dem Papier lag es weiter im Lager: Es alterte, verdunstete und
verdarb weiter und stand am Ende noch einmal unter „noch im Haus". In der
Demo-Saison sind das 2 950 kg von 115 837 kg Lieferungen, gut 2.5 %.

Die Kaskade nimmt jetzt beide Bücher. Weil `v_lieferung_kohorte` je Charge,
Eingangstag **und Buch** eine Zeile liefert, muss sie dabei über das Buch
summieren — sonst käme jede Kohorte zweimal in die Rechnung, und der Fehler
wäre nur umgedreht. Ergebnis: Der Rest der Saisonbilanz lag bei −4 274 kg und
hiess „Lücke"; jetzt sind es **−0.05 kg.** Was übrig bleibt, heisst Überzählung
und ist, was es ist — ein Datenfehler, kein Verlust.

**Vordatierte Lieferscheine zählten sofort.** Sie sind im Betrieb üblich. Eine
Zahl, die „bis heute" heisst, darf aber nichts enthalten, was noch nicht
passiert ist. `v_lieferung_kohorte` filtert jetzt auf `datum <= heute()` — und
damit die Menge nicht spurlos verschwindet, nennt die Plausibilität sie als
Befund „Lieferung in der Zukunft" mit Masse, Datum und Rat. In den echten
Demo-Daten steckte genau so ein Lieferschein.

### Namen, die etwas anderes meinten

| bisher | jetzt | warum |
|---|---|---|
| `kanal_heute_kg` | `kanal_ausgelagert_kg` | enthielt nur das Ausgelagerte, nicht auch den Kanal im Lager |
| `v_wiegung_kennzahl.verlust_kg` | `verdunstung_kg` | ist die Verdunstung einer Palette, nicht ihr Verlust |
| `verlust_14_kg` | `prognose_verlust_14_kg` | ist Prognose, nicht Stand |
| `schimmel_kum_kg` (mit Sockel) | `schimmel_kum_kg` + `sockel_kum_kg` | der Sockel ist nicht lagerbedingt und gehört nicht in dieselbe Zahl |
| „Verlust" ohne Zeitbezug | „Verlust bis heute" | überall |

### Die Grafik trifft die Kennzahl

Der Verlauf endete am letzten Sonntag vor heute — die Linie zeigte bis zu
sechs Tage alte Zahlen neben einer Kennzahl von heute. `erg_verlauf` hat jetzt
eine Stützstelle **genau auf heute()**; ein Test vergleicht sie mit
`erg_bilanz`. Der Schlüssel der Sicht ist damit `bis`, nicht mehr `woche`: die
laufende Woche trägt zwei Punkte.

### Was sonst noch aufgeräumt wurde

- **Die Lagerkontrolle ist korrigierbar.** 24 von 41 Wägungen gehören zu
  keiner Arbeit — der Betriebsleiter wiegt zwischendurch nach. Sie standen in
  der Auswertung, waren aber über keine Arbeit erreichbar und damit nicht zu
  berichtigen. Unter Messungen steht jetzt ein eigener Block dafür.
- **Der Fax-Block zeigt eine Zahl**, wie besprochen. Worauf sie beruht und was
  noch kommt, steht darunter im Satz. Und die Stichprobe nimmt nur Arbeiten,
  bei denen das Faule wirklich gewogen wurde: eine ungewogene Arbeit als
  „0 kg faul" mitzuzählen drückte den gemessenen Anteil nach unten. Leer ist
  nicht null.
- **Die Glocke steht nur noch einmal im Code.** Überblick und Ursachen zeigen
  dieselbe Verteilung mit denselben Grenzen und Farben; die Rechnung stand
  zweimal da, Zeile für Zeile gleich.
- **`v_hochrechnung` (einige Megabyte) hing am Laden jeder Seite**, obwohl nur
  der CSV-Export unter Messungen sie braucht. Jetzt holt sie, wer sie braucht,
  beim Klick.
- **Zwei Kommentare sagten die Unwahrheit**: `erg_ueberfuellung` wird in
  Schritt 1 erneuert, nicht in Schritt 4; und die App liest nicht „nur erg_*"
  — die Arbeiter-Masken lesen weiter ihre v_*-Sichten.
- Zwei tote `void`-Ausdrücke und der Auffälligkeiten-Hinweis auf der
  Chargen-Seite sind weg; Befunde stehen seit Runde H nur unter Messungen.

### Was geprüft und für richtig befunden wurde

- **`bekannt = true` bei `koeff_n_min = 0`** ist kein Fehler: Der Koeffizient
  ist bekannt, nur nicht aus eigenen Messungen dieser Gruppe. `koeff_basis`
  sagt das („Wiegungen aller Sorten, zu wenige eigene Chargen"), und ein Test
  verlangt jetzt, dass diese Begründung nie fehlt.
- **`v_verlust_ranking`** liefert alle Ströme, auch die, die kein Verlust
  sind. Die Sicht steht auf keinem Bildschirm; ihr Kommentar sagt jetzt, dass
  `buch` die Einordnung trägt und eine Summe über alle Zeilen Äpfel und Birnen
  addiert.

### Was offen bleibt (Runde I)

- **`erg_ueberfuellung` ist über die Ebenen nicht additiv**: je Sorte summiert
  1 526 kg, je Charge 1 547 kg (1.4 % Unterschied). Beide Ebenen sind für sich
  ehrlich aus gemessenen Grössen gerechnet; die Differenz entsteht, weil
  Lieferungen ohne Chargenbezug je Ebene anders verteilt werden. Die App zeigt
  nie beide Ebenen zugleich, so dass niemand sie addiert — sauber wäre eine
  gemeinsame Grundlage.

## Runde J — der Code auf den heutigen Stand (9. September)

Der Betriebsleiter: *„Ich glaube, der Code ist für ältere Programme geschrieben.
Inzwischen hat sich viel geändert."* Er hatte recht — vier Hauptversionen lagen
zurück, und dahinter steckte mehr als nur Zahlen in einer Datei.

### Was gehoben wurde

| | vorher | jetzt | warum es nicht nur eine Zahl ist |
|---|---|---|---|
| React | 18.3 | 19.2 | — |
| React Router | 6.30 | 7.18 | offener Redirect über den Backslash in `<Link>` und `useNavigate` (Sicherheitsmeldung) |
| Vite | 5.4 | 8.2 | der Entwicklungsserver war von jeder Webseite auslesbar; bündelt jetzt mit Rolldown |
| TypeScript | 5.9 | 7.0 | die native Fassung — der ganze Projektverbund in 1.2 s statt spürbar länger |
| Supabase | 2.112 | 2.116 | — |

Der Code selbst brauchte für React 19 und Router 7 **keine einzige Änderung**.
Das ist kein Zufall: kein `forwardRef`, kein `React.FC`, kein `defaultProps` —
nichts von dem, was diese Hauptversionen entfernt haben, war je benutzt worden.

Von sieben gemeldeten Schwachstellen sind drei übrig, alle in `wrangler →
miniflare → sharp`. Das ist der lokale Cloudflare-Emulator, eine reine
Entwicklungsabhängigkeit. **In dem, was beim Benutzer ankommt, sind es null**
(`npm audit --omit=dev`). npms Vorschlag wäre, Wrangler um 115 Fassungen
zurückzudrehen; das würde die Veröffentlichung brechen und nichts verbessern.

### Die Falle, die eine Stunde gekostet hat

Das alte `typecheck`-Skript rief `tsc -b --noEmit false --emitDeclarationOnly
false` auf. Dieser erste Zweig scheiterte zwar immer (weil
`allowImportingTsExtensions` ein `noEmit` verlangt) und fiel still auf den
richtigen Befehl zurück — aber **vorher hatte er 53 `.js`-Dateien neben den
`.tsx`-Quellen abgelegt** und dazu eine `vite.config.js` neben der `.ts`.

Vite löst `./App` nach `App.js` auf, *bevor* es `App.tsx` ansieht. Ab dem
Moment baute jeder Build eine eingefrorene Kopie des Quelltextes. Änderungen
wirkten nicht mehr — der Dateiname des Bündels blieb bei jedem Build identisch,
was der einzige sichtbare Hinweis war.

Das führte mich zuerst zu einem falschen Schluss: Ich hielt es für eine
Eigenheit von Rolldown, dass `React.lazy` nicht greift. Nach dem Aufräumen der
53 Dateien griff es sofort. Der Fehler lag nicht im Bündler, sondern im
Werkzeug davor.

Behoben: Das `typecheck`-Skript ist jetzt schlicht `tsc -b` (respektiert
`noEmit`), und `.gitignore` fängt Kompilate neben dem Quelltext ab, damit
niemand mehr in dieselbe Falle läuft.

### Vier Bündel statt einem

Bis hierher lag die ganze App in einer Datei: 822 kB, bevor in der Halle der
erste Knopf erschien — Diagramme, Kaskade und Excel-Leser inbegriffen, die ein
Arbeiter beim Palettenzählen noch nie gebraucht hat.

Jetzt sind es vier, und die Auswertung des Betriebsleiters hängt hinter
`React.lazy`:

| Bündel | Grösse | wann |
|---|---|---|
| index | 39 kB | Anmeldung und die vier Arbeiter-Bildschirme |
| grundlage | 350 kB | was beide Rollen brauchen |
| fremd | 246 kB | React, Router, Supabase |
| **auswertung** | **189 kB** | **erst, wenn der Betriebsleiter eine Auswertungsseite öffnet** |

Erster Start in der Halle: **822 → 635 kB** (gepackt 234 → 186 kB). Geprüft,
nicht behauptet: `index.html` lädt die Auswertung nicht vor, und im
Einstiegsbündel stehen fünf dynamische Importe.

Der Kniff steckt im Vorrang der Gruppe „grundlage". Ohne ihn zieht die
Auswertung die gemeinsame Grundlage an sich, der Einstieg muss sie von dort
holen — und lädt damit die ganze Auswertung doch wieder mit, nur über einen
Umweg. Zwei Bündel, beide sofort geladen: eine Trennung, die nur auf dem
Papier steht.

### Im SQL-Editor sieht man jetzt nichts mehr

`setup.sql` räumt vor jedem Anlegen auf, damit dieselbe Datei einrichtet *und*
aktualisiert. Auf einer leeren Datenbank gibt es nichts wegzuräumen, und
Postgres sagte das jedes Mal: **135 Zeilen** „materialized view … does not
exist, skipping" und „drop cascades to 17 other objects". Harmlos — aber wer
das im Supabase-Editor sieht, liest eine Wand von Problemen.

Ein `set client_min_messages = warning` am Kopf der erzeugten Datei stellt das
ab. Was durchkommt, ist echter Ärger. Die pg_cron-Auskunft, die dabei
verlorenginge, steht jetzt in der Schlusszeile, wo sie ohnehin hingehört.

Gemessen auf einer frischen Datenbank: **2 Sekunden, 0 Fehler, 0 Warnungen,
0 Hinweise**, dann eine Zeile:

> Fertig. Die Datenbank steht: 42 Chargen, 11 Sorten, 28 Tabellen, 62
> Auswertungen. Auswertung berechnet. Ohne pg_cron rechnet die App selbst
> nach, wenn etwas veraltet ist. Weiter im README bei Schritt 4.

`run.sh` prüft das seit Runde J mit: Gibt `setup.sql` auch nur eine
Hinweiszeile aus, schlägt die Stufe fehl.

## Runde K — setup.sql passt wieder in den SQL-Editor (9. September)

### Der Befund

Beim Einfügen von `setup.sql` in den Supabase-SQL-Editor:

> Error: Query is too large to be run via the SQL Editor

Der Editor schickt die Datei als **einen Anfragekörper**, und der ist bei
**1 MB** zu Ende. `setup.sql` war 1 142 678 Bytes gross — 94 kB darüber. Damit
war der einzige Weg versperrt, den der Betrieb hat: markieren, einfügen, Run.

### Die Ursache war nicht die Datenbank, sondern ihre Geschichte

`setup.sql` war die Aneinanderreihung aller damals 63 Migrationen. Gemessen an den
einzelnen Anweisungen:

| | |
|---|---|
| Anweisungen insgesamt | 1 257 |
| davon Ansichten, gespeicherte Ansichten, Funktionen | 869 (1 028 kB) |
| davon **überholt** — von einer späteren Migration ersetzt | 416 (**616 kB, 54 %**) |

`v_saisonbilanz` steht neunmal in der Datei, `v_marge_buch` fünfzehnmal,
`v_massenbilanz` dreizehnmal. Jede dieser Fassungen wurde beim Einspielen
angelegt und Sekunden später überschrieben. Und der Anteil wächst weiter: Fast
jede Migration schreibt Formeln neu, kaum eine legt neue Tabellen an.

### Die Teilung

In den Migrationen stehen zwei Dinge nebeneinander, die sich völlig
verschieden verhalten:

**Tabellen, Spalten, Bedingungen, Nachträge an den Daten** sind eine
*Geschichte*. Jeder Schritt zählt. Eine Datenbank, die seit dem Frühjahr auf
dem Hof läuft, wird genau durch diese Schritte auf den heutigen Stand
gebracht — man kann keinen weglassen.

**Ansichten und die Funktionen, die auf ihnen rechnen**, sind keine
Geschichte, sondern ein *Zustand*. Es zählt nur, wie die Formel heute lautet.
Eine Zwischenfassung von August anzulegen und sofort zu überschreiben ist
reine Arbeit ohne Ergebnis.

`setup.sql` heisst deshalb seit dieser Runde:

- **Teil A** — die Geschichte, vollständig und in ihrer Reihenfolge (249 kB)
- **Teil B** — das Rechenwerk, jede Formel genau einmal (269 kB)

**529 kB statt 1 116 kB — 53 % kleiner, gut die Hälfte der Grenze.** Und die
Datei wächst künftig nur noch mit dem, was wirklich neu ist: Eine Migration,
die zehn Formeln neu schreibt, macht sie nicht mehr grösser.

### Die Reihenfolge in Teil B wird ausgerechnet, nicht geraten

Eine Ansicht steht auf der anderen. `supabase/verdichten.mjs` liest, welche
Ansicht welche liest, und sortiert topologisch; ist die Reihenfolge nicht
kreisfrei, bricht der Bau ab. Zuerst wird das alte Rechenwerk weggeräumt — in
umgekehrter Reihenfolge, damit nichts unter einem anderen wegbricht —, dann
neu gebaut. Auf einer leeren Datenbank passiert beim Wegräumen nichts; auf
einer bestehenden verschwindet das alte Rechenwerk, damit das neue sauber
daneben steht statt darüber. Die Daten sind davon nicht berührt: In Ansichten
liegt nichts, sie rechnen nur.

### Was der Verdichter nicht lesen kann, sagt die Migration ihm

Eine Anweisung in 0061 baut 26 gespeicherte Ansichten über zusammengesetztes
SQL — `execute format('create materialized view %I as select * from %I', …)`
in einer Schleife. Da hilft kein Lesen: Die Namen entstehen erst beim Laufen.
Statt zu raten, sagt es die Migration selbst, in einem Kommentar darüber:

```sql
-- verdichter: baut erg_gewichte erg_kaliber erg_gebinde erg_ausgang
```

Damit ist die Anweisung ein Objekt wie jedes andere und wird richtig
einsortiert. Findet der Verdichter so etwas ohne Angabe, **bricht er ab** und
sagt, welche Zeile fehlt — lieber ein klarer Halt als eine `setup.sql`, die an
der falschen Stelle aufhört.

### Warum das kein Vertrauensakt ist

Eine Datei umzubauen, die eine Produktionsdatenbank einrichtet, ist genau die
Sorte Änderung, bei der „sieht richtig aus" nicht genügt. `run.sh` baut
deshalb seit dieser Runde **zwei Datenbanken** — eine aus den Migrationen
einzeln, eine aus `setup.sql` — und vergleicht ihre Fingerabdrücke Zeile für
Zeile: jede Spalte mit Typ und Vorgabewert, jede Ansicht, jede gespeicherte
Ansicht, jede Funktion, jeder Index, jede Zugriffsregel, jeder Auslöser, jede
Bedingung, jedes Recht, jede Beschreibung.

**2613 Objekte, kein Unterschied.** Weicht eine Zeile ab, bricht der Lauf ab
und nennt sie.

### Was dieser Vergleich nebenbei gefunden hat

Zwei Dinge, nach denen niemand gesucht hatte und die beide Wege betrafen:

**26 Ansichten hatten gar keine Beschreibung** — darunter `v_kaskade`,
`v_marge_buch`, `v_massenbilanz`, `v_hochrechnung`, also der Kern der
Auswertung. Nicht, weil niemand eine geschrieben hätte: Wer eine Ansicht mit
`drop … cascade` wegräumt, reisst die darauf aufbauenden mit; die werden
gleich danach neu gebaut, ihre Beschreibung aber nicht. Beim ersten Mal
unauffällig, nach neun Umbauten steht die halbe Auswertung unbeschriftet da.
Die Beschreibung ist das, was im SQL-Editor und in jedem auslesenden Werkzeug
erklärt, was eine Zahl bedeutet — dieselbe Lücke, gegen die der
Begriffs-Prüfstand auf der Oberfläche antritt, eine Ebene tiefer. Migration
0063 schreibt sie neu, für die Fassung, die heute gilt; keine alte
Beschreibung wurde zurückgeholt, denn eine Erklärung von damals passt nicht
auf eine Formel von heute.

**Der Rundumschlag „keine Funktion ist für PUBLIC ausführbar"** stammt aus
0035 und galt für das, was damals da war. In der Reihenfolge der Migrationen
fiel nie auf, dass später Funktionen dazugekommen sind. Der Verdichter zieht
solche Rundumschläge jetzt ans Ende — und damit es nicht von einer
Reihenfolge abhängt, steht die Regel in 0063 noch einmal ausdrücklich.

`pruefung.sql` hält beides fest: Ansichten ohne Beschreibung und Funktionen
mit PUBLIC-Recht müssen null sein.

## Runde L — das Prüfwerk, und was es gefunden hat (9. September, 0064 bis 0066)

### Warum ein eigenes Werkzeug

Die Prüfstände der Runden A bis K prüfen, ob das Programm tut, was gemeint
ist. Sie können nicht prüfen, ob das Gemeinte stimmt: Wer eine Formel
schreibt und danach den Test dazu, prüft zweimal dieselbe Annahme. Runde L
baut deshalb ein Werkzeug, das die Datenbank **gegen sich selbst** befragt —
`pruefwerk/`, zehn Sonden, jede mit einer eigenen Methode:

| Sonde | Fragt |
|---|---|
| 01 Herkunft | Liest die Oberfläche etwas, das es nicht gibt? Sagt eine gespeicherte Ansicht dasselbe wie ihre Quelle? |
| 02 Bezugsgrössen | Steht über einer Prozentzahl derselbe Nenner, mit dem sie gerechnet ist? |
| 03 Erfassung | Wird etwas erfasst und nie gelesen? Verlangt eine Maske ein Feld, das die Tabelle leer lässt? |
| 04 Orakel | Rechnet eine zweite, unabhängig geschriebene Kaskade dasselbe? Wie weit ist der Betrieb von den Schutzgrenzen entfernt? |
| 05 Metamorph | Was muss gleich bleiben, wenn man die Daten verdoppelt, verschiebt, spiegelt? |
| 06 Mutation | Wenn man eine Formel absichtlich verstellt — merkt es irgendein Test? |
| 07 Szenarien | Acht Papierfälle, von Hand nachgerechnet, gegen die Datenbank gehalten |
| 08 Leer ist nicht null | Wo wird aus einer Lücke eine Zahl? |
| 09 Einheiten | Hält jede Spalte, was ihr Name verspricht? |
| 10 Annahmen | Steht zu jeder Annahme, wo ihr Bruch auffiele — und stimmt das? |

Jede Sonde hat eine **Selbstprobe**: Sie baut sich einen Fall, in dem sie
etwas finden *muss*. Findet sie ihn nicht, meldet der Lauf „STUMPF" und bricht
ab. Eine Sonde, die immer schweigt, ist wertlos und darf nicht wie ein
Gütesiegel aussehen.

### Was gefunden wurde

24 Befunde, davon 18 mit Folgen für eine Zahl. Sie hatten fast alle dieselbe
Form — nicht ein Rechenfehler, sondern eine **Verwechslung von „null" und
„nichts gemessen"**, in beide Richtungen:

**0064 — Leer ist nicht null, auch am Eingang.** Fünf Stellen:
`v_palette` rechnete eine fehlende Kistenzahl als null Kisten und verbuchte
das Gewicht der Kisten als Kürbis (bei 30 Kisten à 1 kg auf 950 kg Netto:
3,2 % zu viel Eingang, und nichts fiel auf). Dieselbe Rechnung stand an drei
weiteren Stellen und drückte über das Verhältnis der beiden Nettos die
Verdunstungsrate nach unten. Ein Verluststrom ohne Messung stand in
`v_hochrechnung_basis` als 0,00 kg — dieselbe Datenbank gab damit auf zwei
Wegen zwei Antworten, denn `erg_verlust` schrieb dort seit jeher NULL.
`coalesce(im_haus_heute_kg, eingang_kg)` griff auch dann, wenn es Kaskaden­zeilen
gibt und nur die liegende Portion fehlt — eine vollständig ausgelieferte
Charge über 950 kg meldete 950 kg „noch im Haus". Und drei Dinge, die der
Betrieb sehen soll, sah er nicht: eine Gebindeart ohne hinterlegte Tara, eine
Charge mit mehr Ausgang als Eingang (4180 kg in der Demosaison), ein
Zettelgewicht, das zur Charge passt, aber nicht zum Tag.

**0065 — Entsorgtes verlässt das Lager.** Was in den Kompost geht, hat den
Betrieb verlassen — es lag aber weiter im Bestand und alterte dort weiter,
während seine Masse gleichzeitig im Ausgang stand. Dieselbe Ware zweimal. Die
Kaskade bekommt eine dritte Portion (`entsorgt`) neben `ausgelagert` und
`lager`; entsorgte Masse wird über die Verdunstung auf ihren Eingang
zurückgerechnet, zählt vollständig als Schimmel und nicht als Lieferung. Auf
der Demosaison ändert sich keine einzige Zahl — dort gibt es keinen Kompost —,
und genau das ist der Beweis, dass die Änderung nur wirkt, wo sie soll.

**0066 — Kein Kilo aus einer Lücke, auch nicht im Rechenweg.** Die Nachlese,
dreimal dieselbe Frage, zweimal mit umgekehrtem Vorzeichen.

Erstens: Der Rechenweg eines Verluststroms zeigt vier Teilbeträge (an
ausgelieferter Ware, an liegender Ware, jenseits der Messungen, beim Abpacken
erwartet). Alle vier entstehen als `sum(...) filter (...)`, und eine Summe über
keine Zeile ist in SQL NULL. Gemeint ist aber „null Kilo in dieser Portion":
Fax hat nichts an der liegenden Ware, weil dort noch nicht abgepackt wurde.
Nachweis, dass 0 der richtige Wert ist: `kg = kg_beobachtet + kg_projiziert`
gilt auf allen 366 Zeilen der Demosaison exakt, sobald man NULL als 0 liest.
Die Oberfläche hat sich mit `?? 0` beholfen — und schrieb dadurch bei einem
*ungemessenen* Strom „Ergebnis bis heute: nicht gemessen" und zwei Zeilen
darunter „Davon an ausgelieferter Ware: 0 kg". Jetzt gilt: Ist der Strom
gemessen, sind alle vier Teilbeträge Zahlen; ist er es nicht, sind alle vier
NULL. Dazwischen gibt es nichts.

Zweitens, und das war der teuerste Fund der Nachlese: **zwei Auslöser haben
ein Nettogewicht erfunden.** `ausschuss_netto_setzen` und
`schimmel_netto_setzen` rechnen brutto − Kisten × Tara und schreiben das
Ergebnis in die Pflichtspalte `kg` — mit `coalesce(kisten, 0)` bzw.
`coalesce(kisten, 1)` und `coalesce(tara, 0)`. Fehlte die Kistenzahl oder die
hinterlegte Tara, wurde damit das **Bruttogewicht als Netto gespeichert** und
mit `gemessen = true` markiert. Das ist derselbe Fehler wie bei der Palette in
0064, nur schlimmer: Dort wurde er beim Lesen gemacht, hier wird er
geschrieben und bleibt stehen.

Die Zeile wird trotzdem nicht abgewiesen. Sie ist eine Beobachtung („eine
Kiste Kleines gewogen, 120 kg brutto"), nur eben keine Nettomasse — sie
bekommt `gemessen = false`, und `v_ausschuss_beobachtung` und
`v_schimmel_menge` lesen ohnehin nur Gemessenes. Eine Bedingung auf der
Tabelle (wie `lieferung_hat_menge` in 0064) wäre hier falsch gewesen: Bei
der Lieferung ist die Zeile ohne Menge unbrauchbar, hier ist sie es nicht.

Drittens: Die Auffälligkeit „Ausschuss-Tara" hat dasselbe Netto ein zweites
Mal nachgerechnet, wieder mit `coalesce`. Fehlte die Tara, kam als „richtiges"
Netto das Bruttogewicht heraus, die Prüfung schlug an und gab die falsche
Auskunft: *„Die Gebinde-Tara wurde nach dem Wiegen geändert."* Sie wurde nicht
geändert, sie fehlt. Nebenbei fiel dabei eine SQL-Eigenheit auf, die genau in
dieselbe Falle führt: **`greatest(null, 0)` ist 0, nicht NULL** — die Prüfung
hätte auch nach dem Entfernen der `coalesce` weiter angeschlagen, wenn das
Netto nicht ausdrücklich vorher geprüft würde. Jetzt rechnet sie nur nach, wo
sich etwas nachrechnen lässt, und die Lücke steht als eigene Art daneben:
„Ausschuss ohne Tara".

### Was ausdrücklich nicht gemacht wurde

Keine neue Auswertung, keine neue Grafik, kein neuer Bildschirm, keine neue
Frage an den Arbeiter. Fünf der zehn Reparaturen bedeuten sogar **weniger**
Anzeige: eine Null verschwindet, ein „—" tritt an ihre Stelle.

Zwei Feststellungen sind bewusst offen geblieben und stehen als Frage in
`docs/PLAN_REPARATUREN.md`: **wovon** der Verlust in Prozent gerechnet werden
soll (16,1 % des Eingangs gegen 25,1 % des noch nicht Ausgelieferten — bis zu
9 Prozentpunkte Unterschied, und die Wahl gehört dem Betrieb), und ob zwischen
Eingang und Wägung umgestapelt wird (11 % zu hohe Tagesrate, wenn ja; das ist
eine Frage an die Halle, keine an den Code).

### Wie die Reparaturen gehalten werden

Nicht durch die Sonden — die laufen von Hand. Jede Reparatur ist mit einer
Behauptung in `supabase/test/pruefung.sql` festgenagelt, und zwar **in beide
Richtungen**: eine Zahl genau dann, wenn gemessen wurde, und unbekannt genau
dann, wenn nicht. Dazu die Mutationssonde: Sie verstellt fünfzehn Formeln
einzeln in den Migrationen, baut jedes Mal ein ganzes Schema neu, spielt die
echten Demodaten ein und fragt, ob irgendein Test anschlägt. Was dabei
übersteht, ist die Lücke im Netz — und steht als Befund im Bericht, nicht als
gute Nachricht.

## Runde M — die Werkstätten, und der Tag des Arbeiters (9. September, 0067)

Runde L hat gefragt: *bedeutet diese Zahl, was dasteht?* Runde M fragt vier
andere Fragen, und für jede gibt es eine Werkstatt in `werkstatt/`:

| | Die Frage |
|---|---|
| **A — Rechenwerk** | Ist das der richtige Schätzer, und ist er ehrlich über sich selbst? |
| **B — Fundament** | Ist die Datenbank unter der Fachlogik gesund? |
| **C — Bauwerk** | Ist der Code so gebaut, wie ein Programm dieser Grösse gebaut sein sollte? |
| **D — Nutzen** | Löst dieses Programm die Probleme des Betriebs? |

Zwei Regeln gelten für jedes Werkzeug dort, und beide stammen aus einem Fehler
der letzten Runde:

**Keine Feststellung ohne Grösse.** `befund()` wirft, wenn die Zahl fehlt. Eine
Liste von Meinungen nimmt niemand ernst, und „ausserhalb des Umfangs" darf man
erst sagen, nachdem man beziffert hat, wovon man spricht.

**Keine Feststellung ohne Gegenrede.** Ebenfalls Pflicht: das beste Argument
*gegen* den eigenen Befund, aufgeschrieben von dem, der ihn macht.

**Und jedes Werkzeug hat eine Selbstprobe** — einen eingebauten Fehler, den es
finden *muss*. In Runde L ist die Mutationssonde unbemerkt blind geworden: Neun
ihrer dreizehn Mutationen zeigten auf Formeln, die zwei Migrationen später
anders hiessen. Sie änderte nichts mehr und meldete „keine überlebende
Mutation" — das sah wie ein gutes Ergebnis aus und war das Gegenteil. Der
Läufer `werkstatt/lauf.mjs` geht mit Rückgabewert 2, wenn auch nur ein Werkzeug
seine Selbstprobe nicht besteht oder keine hat.

### Die Zeitzone: `betriebstag()` statt `::date`

Das Programm rechnet mit Lagertagen. Ein Lagertag ist die Differenz aus einem
**Kalendertag** (`eingangsdatum`, vom Zettel abgetippt, Ortszeit) und einem
**Zeitpunkt** (`wiege_ts`, von der Datenbank gesetzt, ohne Ort). Aus dem
Zeitpunkt wurde mit `::date` wieder ein Kalendertag — in der Zeitzone der
Sitzung. Die Datenbank läuft auf UTC, der Betrieb steht in der Schweiz.

Entschieden: **Jede Stelle sagt ausdrücklich, welchen Kalendertag sie meint.**
`betriebstag(wiege_ts)` statt `wiege_ts::date`, und die Zone steht als
Einstellung `zeitzone` in der Datenbank (Rückfall `Europe/Zurich`).

Nicht entschieden wurde `alter database … set timezone`. Das verlegt dieselbe
stille Annahme nur an eine andere Stelle, und auf Supabase steht sie nicht in
der Hand dieses Projekts.

Dieselbe Korrektur in der Oberfläche: An fünf Stellen entstand „heute" als
`new Date().toISOString().slice(0, 10)` — der Tag in UTC. Zwischen Mitternacht
und zwei Uhr Ortszeit bot die Maske dem Arbeiter **gestern** als Vorgabe an.
Jetzt gibt es eine Funktion `heute()` in `lib/format.ts`; fünf gleiche
Ausdrücke werden zu einem.

Gemessen (`werkstatt/b_fundament/b5_zeit.mjs`, Demosaison): Saisonverlust
52 119.38 → 52 099.70 kg, ein verschobener Lagertag, 19.68 kg. Klein — aber
einseitig, und auf der Rate einer einzelnen Wägung bis zu 14.4 % bei der
kürzesten Lagerung.

Beim Bauen der Migration hat sich der Fall von selbst gestellt: Um 22:03 UTC
sagte dieselbe Datenbank `current_date → 2026-09-09` und
`betriebstag(now()) → 2026-09-10`. Zwei Zwischenstände, eine Stunde
auseinander gerechnet, unterschieden sich um einen ganzen Lagertag je Charge.
In der Sommerzeit dauert dieses Fenster zwei Stunden — jede Nacht.

**Was bewusst liegen bleibt, mit Zahl:** `mv_auftrag_masse` enthält dieselbe
Verwechslung, ist aber eine gespeicherte Sicht — sie lässt sich nur neu bauen,
und `drop materialized view … cascade` nimmt **51 Objekte** mit. Nachgemessen,
bevor das als „später" abgetan wird: 5 von 309 Arbeiten haben einen
Startzeitpunkt, dessen UTC-Tag und Schweizer Tag auseinanderfallen; die Sicht
in der Betriebszone neu gefüllt und alles nachgerechnet ergibt auf der
Demosaison **dieselben vier Zahlen bis auf den Rappen**. Der Umbau bewegt heute
nichts und bleibt deshalb liegen.

### Zwei Zusagen der Datenbank eingelöst

Vier Prüfbedingungen standen seit ihrer Einführung mit `NOT VALID` im Schema:
Postgres wendet sie auf neue Zeilen an, hat aber nie nachgesehen, ob die
vorhandenen sie erfüllen, und darf sie beim Planen nicht voraussetzen.
Nachgerechnet: null Verstösse bei allen vieren. Jetzt bestätigt.

Fünf Indexe beantworten nur Fragen, die ein anderer Index auch beantwortet —
ihre Schlüsselspalten sind das Präfix eines anderen. Zusammen 120 kB, bei jedem
Schreibvorgang mitgepflegt. Gestrichen.

### Der Bildschirm-Prüfstand konnte nicht scheitern

`pruefstand/bildschirme.mjs` kannte im ganzen Quelltext nur `process.exit(0)`.
Er zählte Konsolenfehler und wagerechtes Überlaufen, schrieb sie als
„✗"-Zeilen — und endete mit null. In einer Kette wie
`run.sh && kette && bildschirme` ging er stillschweigend durch. Ausgerechnet
der einzige Prüfstand, der die Oberfläche wirklich ansieht.

Schlimmer noch: Sein erstes Argument ist ein **Namensfilter**, während jeder
andere Prüfstand dort die Datenbank-URL nimmt. Wer sie aus Gewohnheit mitgab,
filterte auf einen Namen, den kein Bildschirm trägt — die Schleife übersprang
alle 172 Aufnahmen, es entstand kein Bild, und der Schlusssatz lautete
trotzdem „Fertig … keine Konsolenfehler". Gemessen: 1.2 Sekunden mit Argument,
über 315 Sekunden ohne.

Jetzt zählt er die Aufnahmen, nennt sie im Schlusssatz, weist ein Argument
zurück, auf das kein Bildschirm passt, und endet mit eins, wenn etwas
fehlschlug oder nichts entstand.

### Neu rechnen ist Sache des Betriebsleiters (0068)

`auswertung_schritt()` und `auswertung_aktualisieren()` liefen mit
Eigentümerrechten und prüften nichts. Gemessen: Der Arbeiter Tomasz
(`ist_admin()` = falsch) lässt beide durchlaufen; ein Lauf dauert 2 960 ms und
nimmt dabei AccessExclusiveLock auf jede gespeicherte Ansicht — `refresh …
concurrently` kommt im ganzen Projekt nicht vor. Ein paralleler Leser von
`erg_gewichte` wartete **2 897 ms** gegen höchstens 1.34 ms im Ruhezustand.

Die Oberfläche ruft das Neurechnen nur von Betriebsleiterseiten aus, und die
sind in `src/App.tsx` hinter `istAdmin` weggeschlossen. Es fehlte allein die
Tür auf der Datenbankseite: PostgREST kennt die Grenze der Oberfläche nicht.

Entschieden: Der Wächter lässt ausdrücklich durch, **wer ohne Anmeldung
kommt** — die Prüfstände, die Simulation und `demo_bauen.sh` laufen als
Eigentümer der Datenbank. Ein Wächter, der die eigenen Prüfungen erschlägt,
wird beim ersten Ärger wieder ausgebaut.

Dazu zwei Kleinigkeiten aus derselben Runde: `erg_punkte` ist eine Kopie von
`mv_schimmel_punkte` statt einer zweiten Rechnung derselben Sicht (gemessen
103 ms von 3 017 ms und 120 kB je Neurechnen), und `zahl()` hält den
**gerundeten** Wert gegen die Grenze statt den ungerundeten — das Fenster, in
dem ein Wert die Prüfung besteht und beim Runden darüber gehoben wird, war
0.005 kg breit bei 10¹² kg.

### Was ein Vergleich zweier Wege nicht findet (0069)

0067 hat fünf Sichten neu geschrieben und dabei `with (security_invoker =
true)` verloren — `create or replace view` löscht die Einstellungen einer
Sicht, wenn die neue Fassung keine mitbringt. Die Klausel stand in keiner
geänderten Zeile und war trotzdem weg. Seither liefen `v_auftrag_masse` und
vier weitere mit den Rechten ihres Eigentümers; die Zeilenregeln der Tabellen
darunter galten beim Lesen durch sie nicht.

Nachgestellt auf einer Kopie: Wird die Leseregel von `auftrag` auf den
Betriebsleiter verengt, sieht ein angemeldeter Arbeiter dort **0 Zeilen** und
durch `v_auftrag_masse` weiterhin **308**.

Heute kostet das nichts — jede Leseregel lautet `true`, `anon` hat auf keine
dieser Sichten ein Leserecht. Es kostet an dem Tag, an dem der Betrieb eine
Regel verengt.

**Die Lehre ist die wichtigere Hälfte.** Der Abgleich in `supabase/test/run.sh`
stellt die Datenbank aus den Migrationen neben die aus setup.sql und meldete
Deckungsgleichheit über alle 2 636 Objekte — beide Wege hatten denselben
Fehler. Ein Vergleich zweier Wege findet nur, was die Wege **trennt**, nie das,
was sie teilen. Entschieden: Für Eigenschaften, die immer gelten müssen, steht
ab jetzt eine Zusicherung ohne Vergleich in `pruefung.sql`. Die erste lautet:
jede Sicht in `public` hat `security_invoker = true`. Gegengeprüft, dass sie
beisst.

### Ein Teillauf darf den Bestand nicht ersetzen

`node werkstatt/lauf.mjs --nur a4` schrieb sein Ergebnis nach
`werkstatt/befunde/befunde.json` — dieselbe Datei wie der volle Lauf. Ein
Nachlauf zur Kontrolle ersetzte damit die zweiundzwanzig Feststellungen des
vollen Laufs durch die eine von a4, und `bericht.mjs` machte daraus einen
Bericht, der vollständig aussah und über einundzwanzig Feststellungen schwieg.

Jetzt schreibt ein Teillauf nach `teil_<kürzel>.json`; nur der volle Lauf darf
`befunde.json` ersetzen.

### Wer eine Formel für sich rechnet, prüft seinen Nachbau

`werkstatt/a_rechenwerk/a7_raender.mjs` holt die Formel für den verkaufsfähigen
Anteil mit `pg_get_viewdef` aus der laufenden Sicht — damit sie nicht
auseinanderlaufen können — und rechnet sie über ein Gitter aus Randwerten. In
der ersten Fassung hat es die Zahlen dort eingesetzt, wo `a_klein_n` steht, und
ihr rohe Ausschussanteile gegeben. `a_klein_n` ist aber die **normierte**
Grösse: Eine Stufe vorher teilt die Sicht durch `GREATEST(a_klein + a_gross,
1)`. Das Werkzeug hat der Formel damit eine Eingabe gegeben, die sie nie
bekommt, einen negativen Faktor herausbekommen und daraus einen Befund
geschrieben — mit Grösse und Gegenrede.

Entschieden: Ein Werkzeug, das eine Formel für sich rechnet, rechnet **die
Kette** und weist zuerst nach, dass sein Nachbau auf echten Zeilen dieselben
Zahlen ergibt wie die veröffentlichte Spalte. Weicht eine um mehr als 1e-6 ab,
bricht es ab. Derselbe Wächter hat in a4 den vergessenen gepoolten Term
gefangen.

Was von a7 bleibt, sind drei Freisprüche: Der Boden `GREATEST(…, 0.25)` kann
bei den gemessenen Verdunstungsraten (0.046 % bis 0.062 % je Tag) nicht
greifen — er läge bei 6.9 Jahren Lagerdauer; die Normierung der beiden
Ausschussanteile hält; und über 210 Randwerte bleibt der Anteil in (0, 1].

## Runde N — die Gegenprobe, der gemeldete Fehler, das Erscheinungsbild (11. September, 0070)

Diese Runde prüfte die App **mit Werkzeugen, die ihr nicht gehören** (eine
zweite Rechnung aus den Rohtabellen, eine böse Saison, Drehbücher aus der
Halle) und arbeitete den gemeldeten Fehler und das Erscheinungsbild ab. Der
volle Befund steht in `docs/GEGENPROBE_BEFUND.md`; hier die Entscheidungen.

### Negative Lagertage sind nie plausibel — der Zettel bleibt trotzdem stehen

Ein Zettel mit dem Jahr 2029 ergab negative Lagertage, die als plausibel galten
und ein Diagramm bis −1000 Tage zogen. Zwei Wege wären möglich gewesen: das
falsche Datum beim Speichern **sperren**, oder es **stehen lassen und melden**.
Wir lassen es stehen: gespeichert wird, was beobachtet wurde. Falsch war, was
die Auswertung daraus machte — und das ist repariert (0070): plausibel nur bei
Lagertagen ≥ 0, und eine neue Auffälligkeit „Zetteldatum Zukunft" bringt den
Fehler dem Betriebsleiter zur Korrektur. Der Zähler warnt beim Tippen, sperrt
aber nicht (Frage 59).

### Das Diagramm kennt die Einheit seiner Achse

Der eigentliche Anzeigefehler sass tiefer als der eine Zettel: `Linien` nahm
`Math.min(...alleX)` als Achsenanfang, also durfte **jeder** Ausreisser die
Achse an sich reissen. Jetzt kennt `src/lib/achse.ts` die Einheit — Lagertage
beginnen bei 0, Prozent liegt zwischen 0 und 100 — und ein einzelner Punkt, der
die Spanne der übrigen um mehr als das Doppelte verlängert, bestimmt die Achse
nicht mehr; er steht als Satz unter dem Bild. Dieselbe Regel steht unabhängig
in `gegenprobe/bildschirm/achse.ts`, damit die Gegenprobe die App prüfen kann,
ohne aus ihr zu importieren.

### Sortierte Paletten werden nicht als Lagerkontrolle gewogen

Der Betrieb hat entschieden (Frage 57): Nach dem Sortieren stehen die Kisten
auf neuen Paletten, deren Eingangsgewicht niemand kennt — sie nachzuwiegen ist
nutzlos. Die App bekommt deshalb **keinen** dritten Weg in der Maske. Die
Datenbank fängt den Fall ab: Eine Wägung, deren Netto auf das Gramm gleich
geblieben ist (Rate exakt null — ein kopiertes Eingangsgewicht), ist nicht
verwendbar. Eine kleine Zunahme durch Waagenrauschen bleibt es dagegen — die
Zusage aus 0056 gilt weiter, sie war der Grund, „strikten Verlust" wieder zu
verwerfen und nur die exakte Gleichheit auszuschliessen.

### Betriebstag und Sortier-Eingang bleiben zurückgestellt — wie in 0067, mit Zahl

`mv_auftrag_masse` (Betriebstag statt UTC-Tag) und `mv_sortier_eingang` (ein
falsches Jahr vergiftet den gemittelten Eingangstag) sitzen beide hinter einem
51-Objekt-Cascade. 0067 hatte das schon gemessen: fünf von 309 Arbeiten sind
betroffen, die ganze Auswertung ergibt danach dieselben Zahlen bis auf den
Rappen. Der falsche Zettel wird jetzt gemeldet und aus der Statistik gehalten;
die verbleibende Wirkung ist eine falsch **angezeigte** Lagerdauer, bis der
Betriebsleiter das Jahr berichtigt. Der Umbau gehört in eine eigene Runde, nicht
in diese (N-03, N-04 in `docs/GEGENPROBE_BEFUND.md`).

### Die Bänder werden nicht verengt, obwohl eines nachweislich zu eng ist

Die Simulationsmatrix zeigt: die Rangfolge der Ursachen stimmt zu 100 %, die
Hauptströme sind unverzerrt. Der eine blinde Fleck (N-14): liegt ein echter
Palox-Sockel vor, mischt das Modell ihn mit dem Schimmel — der Schimmel wird um
21 % zu hoch geschätzt, sein Band überdeckt nur 47 % statt 95 %. Das Band
**trotzdem** zu verengen wäre falsch: ohne bessere Trennung von Sockel und
Schimmel senkt das die Überdeckung nur weiter. Die Trennung hängt am
Verderbsmodell hinter demselben Cascade und ist ein eigener, statistisch
schwerer Schritt. `gegenprobe/orakel/band.ts` (Delta-Methode mit voller
Kovarianz) ist der Massstab, an dem eine künftige Runde das misst.

### Warum das Erscheinungsbild gleich bleibt und doch neu ist

Struktur, Reiter, Grafiken und Zahlen sind unverändert — der Auftrag war
ausdrücklich „gleiche Struktur, gleiche Infos, nur schöner". Neu ist das
Zeichensystem: ein warmes, sehr helles Neutral statt kühlem Grau, Tiefe aus
einer feinen Kontur und einem flachen Schatten statt harter Rahmen, ein
satterer Kürbis als einziger Akzent, einfarbige SVG-Strichzeichen statt Emoji,
und ruhige Bewegung (Knopf, Fokus, Linie, Karte). Alles ohne eine neue
Abhängigkeit; die Strom-Farben blieben, weil sie Bedeutung tragen und auf
Farbfehlsichtigkeit geprüft sind.

## Runde O — das Erscheinungsbild ganz, nicht halb

Runde N hatte nur die Zeichen getauscht (Farben, Schrift, SVG statt Emoji) und
das als „komplett" gemeldet; die Bildschirme selbst waren unverändert. Der
Betrieb hat das gesehen. Runde O baut jede Seite neu — Funktionen und Zahlen
identisch, bewiesen durch die unveränderten Prüfstände. Was gebaut ist, steht
in `docs/DESIGN_RUNDE_O.md`; hier die Entscheidungen.

### Die Kurve läuft über die letzte Messung hinaus — mit derselben Formel wie die Datenbank

Ein Diagramm über Lagertage, das an der letzten Messung endet, beantwortet die
Frage des Betriebs nicht („wie geht es potenziell weiter?"). Die Kurve wird
deshalb 60 Tage weitergezeichnet, gestrichelt, mit Band. Sie ist keine neue
Rechnung: `schimmelKurve` und `verdunstungKurve` in `src/auswertung/daten.ts`
werten genau die Koeffizienten aus, die `erg_kurve` liefert (ln λ, k, x̄,
Varianzen, Kovarianz, Streufaktor), nur an mehr Stellen — gegen `erg_kurve`
nachgerechnet (0.0211 gegen 0.0208 an der Stichprobe). Die Zahlen „Prognose:
zwei Wochen länger liegen" kommen unverändert aus `erg_naechste_charge`.

### „Heute" gibt es auf der Lagertage-Achse nur je Charge

Jede Charge kam an einem anderen Tag herein; ein gemeinsames „heute" wäre
gelogen. Also: je Charge eine Raute bei ihrem Alter (Grösse nach Masse); ist
eine Charge gewählt, eine Linie „heute · N Tage im Lager"; sonst eine Zone
„hier liegt die Ware heute (von–bis Tage)". Das ist beobachtet (Alter aus
`erg_charge`), nicht gefolgert.

### Das Schwebefeld liegt neben dem Rollbereich, nicht darin

Der gemeldete Fehler (Tooltip verschwindet unter der Legende) kam von
`overflow: auto` am Rollbereich, der das absolut gesetzte Feld abschnitt. Das
Feld ist jetzt Geschwister des Rollbereichs innerhalb `.diagramm`
(`position: relative`) und klappt nach oben, wenn der Zeiger tief steht.

### Herkunft steht oben in der Karte, nicht nur in der Erklärung

Der Begriffs-Prüfstand liest die ersten 1 800 Zeichen einer Karte; eine
Tabelle mit 27 Chargen schiebt die Erklärung darunter hinaus. Das ist kein
Prüfstandsfehler, sondern ein Hinweis: Wer eine lange Tabelle liest, sieht die
Erklärung darunter auch nicht. Die Herkunftsmarke steht deshalb im Titel des
Aufklappers oder in der Filterleiste — dort, wo der Chef hinschaut. Aus
demselben Grund heisst die Prognosezeile „zwei Wochen länger liegen": „14 Tage"
sieht wie eine Zahl mit Einheit aus, und eine Zeile, die selbst wie ein Wert
aussieht, hat keine Beschriftung.

### Zwei Prüfstände wurden präziser, keiner lockerer

`invarianten.mjs` las die SVG-Zeichen der neuen Werkzeugknöpfe („Als Tabelle")
als Diagramme mit null Achsenstrichen — der Vertrag sagt seit Runde N
`svg[data-x-einheit]`; jetzt liest er nur das. `bildschirme.mjs` nennt bei
Überlauf die Elemente, die hinausragen. Schwellen, Regeln und Lexikonpflicht
sind unverändert; das Lexikon bekam den Begriff „Tempo".

### Was bewusst nicht gemacht wurde

Kein Chart-Paket, kein Animations-Paket, keine neue Abhängigkeit — die
Diagramme bleiben lesbar und die Prüfstände können sie zurücklesen. Keine
Änderung an Schema oder Sichten: Runde O ist reines Frontend, `run.sh` läuft
unverändert grün.

## Runde P — was liegt, und was davon verkauft sich (13. September, 0071)

Der Betrieb hat zwei Fragen gestellt und dazugesagt, dass die Antworten
darauf fehlen: *wie viel kam rein, ging raus, liegt noch — und wie viel davon
ist verkaufsfähig* und *wo geht mein Kürbis hin, was war am schlimmsten*.
Gebaut ist beides in `docs/DESIGN_RUNDE_P.md`, gemessen im
`docs/BEFUND_RUNDE_P.md`; hier stehen die Entscheidungen.

### Eine Formel für heute und für morgen

Jede Zahl über die Zukunft ist die Kaskade (`mv_kaskade`, Portion „lager") an
einem späteren Tag ausgewertet — dieselben Faktoren, dieselben Klammern, kein
zweites Modell. Das ist keine Stilfrage: `v_naechste_charge` hatte eine eigene
Zwei-Wochen-Formel (F auf 0.99 geklammert, Verderb bedingt auf die gute
Masse) und sagte für Charge 1632 466 kg, wo die Kaskade 388 kg sagt — 20 %
auseinander, beide Zahlen im selben Programm. Ab 0071 gibt es genau **eine**.

Bewiesen wird das nicht durch Lesen, sondern durch Block 0071 in
`supabase/test/pruefung.sql`: Bei Horizont 0 muss jede Prognosezahl auf zwei
Rappen die Zahl von heute sein. Der Block war vor der Migration rot (die Sicht
gab es nicht) und ist seither grün.

### Der Anteil in Prozent, nicht die Menge in Tonnen

Der Betrieb weiss im Oktober nicht, wie der Verkauf weitergeht — eine
Mengenprognose wäre eine Behauptung über sein Geschäft. Der **Anteil** ist
eine Aussage über die Ware: *von dem, was dann noch liegt, sind y %
verkaufsfähig*. Der Nenner ist die heute liegende Eingangsware und bleibt über
den ganzen Horizont derselbe; was sich ändert, ist nur die Zusammensetzung.
Genau so hat der Betriebsleiter die Frage gestellt („ich hab noch 400 Tonnen,
aber nur 65 % sind verkaufbar"), und genau so steht sie jetzt da.

### Die zu Kleinen gehören ins Bild, aber nicht in die Prognose

Ein Kürbis unter 600 g war schon auf dem Feld zu klein; „zu klein" und „zu
gross" wachsen nicht mit der Lagerdauer. Sie werden trotzdem gezeigt — als
Band, das über die Zeit **flach** bleibt. Der Betriebsleiter sieht damit ohne
Erklärung, welche zwei Bänder mit dem Liegen wachsen und welche zwei von
Anfang an da waren. Sie aus der Grafik zu nehmen wäre bequemer gewesen und
hätte die Frage „wo ist der Rest?" erzeugt.

### Der Verlust ist keine Kopfzahl mehr

Die vier Kopfzahlen heissen Eingang · Ausgeliefert · Im Lager · Davon
verkaufsfähig. Der Verlust ist der **Abstand** zwischen den letzten beiden —
in dieser Form liest ihn der Betriebsleiter, ohne dass ihm jemand erklären
muss, was alles hineinzählt. Dieselbe Entscheidung trägt den Verlauf: vier
Linien (Eingang, Ausgeliefert, Im Lager, Davon verkaufsfähig) statt einer
Verlustlinie.

### Zwei Identitäten, die stehen bleiben dürfen

`v_wohin` teilt den ganzen Eingang auf und rechnet den Rest **nicht** weg:
`rest_kg` und `lager_rest_kg` stehen als Spalten da. Beide haben den
Erwartungswert null. Eine doppelt gezählte oder vergessene Portion bleibt
darin als Zahl sichtbar, statt in einer Summe zu verschwinden — auf der Demo
sind es −0.06 und −0.02 kg über 61 Gruppen, also Rundung.

### Keine neue Frage an den Arbeiter

Der Betrieb hat gefragt, ob für die fehlenden Auswertungen mehr Daten nötig
sind. Die Antwort ist nein. „Faules beim Abpacken" war „faul dargestellt",
weil ihm der Zusammenhang fehlte — den gibt es seit Migration 0060 als
Angabe *Tage seit dem Waschen*, sie wurde nur nie ausgewertet. Jetzt schon:
0–1 Tage 1.31 %, 2–3 Tage 2.34 %, Bereiche ohne Überschneidung.

Die einzige Änderung in der Halle nimmt Arbeit **weg**: „Tage seit dem
Waschen" ist beim Fax-Abschluss aus der letzten Wasch-Arbeit derselben Charge
vorbelegt. Vorgeschlagen wird nur, was Sinn ergibt — nichts aus der Zukunft,
nichts, was länger als zwei Wochen her ist. Die Grenze ist gemessen (in der
ganzen Saison steht die Zahl auf 1, 2 oder 3 Tagen), nicht geraten: Eine
Wasch-Arbeit von vor fünf Monaten ist nicht die, aus der diese Paletten
kommen, und dann ist das Feld leer besser als falsch vorbelegt.

### „Spielraum", nicht „verschenkte Marge"

Bei Stück-Kisten wird je Stück bezahlt; jedes Gramm über der Unterkante des
Kalibers geht unbezahlt mit. Das als „verschenkt" zu bezeichnen wäre ein
Vorwurf an eine Halle, die gar nicht anders kann — niemand sortiert auf die
Kante. Die Zahl heisst deshalb **Spielraum**, und daneben steht, wo im Band
die Ware tatsächlich liegt (Kaori Kuri 10 %, Orangita 58 %, Ker Madec 79 %).
Ob das Absicht ist, weiss nur der Betrieb; die Frage steht in `FRAGEN.md` (61).

### Leer ist nicht null — auch in der Kopfzahl

Fehlt ein Koeffizient, bleibt der Anteil NULL und die Masse ist eine obere
Schranke. Das stand in der Datenbank seit 0064 richtig, auf dem Bildschirm
aber nicht: Die Kopfzahl „Davon verkaufsfähig" zeigte die Schranke wie eine
Schätzung. Gefunden hat das nicht ein Test, sondern das neue Drehbuch *Die
Sorte ohne Wägung* (`gegenprobe/drehbuecher/03_…`), das eine leere App Szene
für Szene füllt und nach jeder Messung fragt, was die App jetzt behauptet.
Die Karte sagt seither **„höchstens"**, solange etwas fehlt.

### Ein Zyklus in der Datenbank, strukturell gelöst

`v_prognose` braucht die Ränder der Koeffizienten (r, klein, gross, fax je
Sorte). Liest sie diese aus den gespeicherten `erg_koeff_*`, entsteht ein
echter Kreis: Die Schleife, die `erg_koeff_*` füllt, hinge dann an einer
Sicht, die aus `erg_koeff_*` liest — `setup.sql` liess sich nicht mehr
topologisch sortieren. Das war kein Werkzeugproblem, sondern ein Zyklus im
Objektgraphen. Gelöst mit einer eigenen kleinen Matrix `mv_koeff_rand` (acht
geklammerte Zahlen je Sorte), die Schritt 2 füllt und die ausserhalb der
markierten Schleife steht.

### Was bewusst nicht gemacht wurde

Keine Tabelle und keine Spalte gelöscht. Keine neue Abhängigkeit. Kein neuer
Reiter und keine neue Frage in der Halle. Kein Palettenbestand je Kaliber
(Frage 58 ist entschieden: entfällt). Und keine Mengenprognose in Tonnen —
der Betrieb bekommt Prozente, weil er die Verkaufsseite besser kennt als die
App.

## Runde Q — die Erfassung scharf schalten (11. September, 0072 bis 0076)

Diese Runde ist die letzte, in der an der **Erfassung** etwas geändert wird.
Der Betrieb hat das gesagt und es stimmt: Die Auswertung darf ewig
weiterlernen, aber was in der Halle nicht gemessen wurde, ist für diese Saison
weg. Ab jetzt sind die Daten echt und werden nicht mehr gelöscht.

### Der Palox rechnete über die Arbeitsgrenze hinweg — an zwei Stellen

Der gemeldete Fehler war „minus 445, warum — es sind 45 kg": Die erste
Ablesung einer Arbeit wurde als Menge verbucht, obwohl sie nur der Stand ist,
bei dem die Arbeit beginnt. Beim Suchen fand sich derselbe Denkfehler ein
zweites Mal, und dort war er gefährlicher.

`v_palox_stand` bildete das Fenster über die **Station**, nicht über die
Arbeit. Ein *fallender* Startstand liess die Arbeit aus der Rechnung fallen —
zufällig richtig. Ein *steigender* buchte die Differenz zur letzten Arbeit
derselben Station als Faules dieser Arbeit: fremde Kilo, still, ohne Befund.
Der Betrieb hatte die Regel längst gesagt — „arbeitsschritte werden nie über
nacht pausiert … deswegen soll nie von der letzten arbeit der palox wert
irgendwie übernommen werden" — sie stand nur nicht in der Sicht.

Was daraus folgt: Die erste Ablesung ist ein Startstand und ergibt 0 kg. Zwei
Ablesungen sind Pflicht; mit einer einzigen hat die Arbeit **keine** Faul-Menge,
statt einer erfundenen. Fällt der Stand, fragt die Maske, statt stillschweigend
`kg: 0` zu schreiben.

**Was das an den Demo-Zahlen ändert** — ausdrücklich eine Aussage über die
Beispieldaten, nicht über den Betrieb: vorher 132 Arbeiten mit zusammen
10 705 kg Faulem, nachher 128 Arbeiten mit 8 159 kg. Die Beispieldaten waren mit
13 549 kg erzeugt worden. Die Differenz sind Arbeiten ohne Startablesung; sie
sind jetzt ehrlich *unbekannt* statt falsch beziffert.

### Die Beinahe-Falle: eine Kistenzahl, die 289 Zeilen verschwinden liess

`v_auftrag_palette_masse` endete mit `where ap.kisten is null`. Das war eine
Abgrenzung gegen die Wasch-Paletten, die dort nicht hingehören — nur hing sie
an der falschen Spalte. Sobald die Wäge-Maske die Kistenzahl auf die
**Eingangs**palette schreibt (genau das, was diese Runde bringt), fällt jede
solche Palette aus der Sicht.

Im Versuch nachgemessen: 289 Zeilen → 0, und 31 Sortierarbeiten stehen danach
mit `n_paletten = 0` und Masse NULL da. Kein Fehler, keine Warnung — die Masse
wäre einfach weg gewesen. 0074 grenzt jetzt nach der **Station** ab, nicht nach
einer Spalte, die sich füllen darf.

Das ist die Sorte Fehler, die diese Runde verhindern sollte: nicht der falsch
gerechnete Wert, sondern der stumme Ausfall.

### Kisten je Kaliber zählen: gestrichen, nicht verbessert

„niemand wird händisch die kisten zählen und in der app eintragen." Der Reiter
blieb also nicht in besserer Form stehen, er ist weg. Ein Eingabefeld, das
niemand füllt, ist schlimmer als keines: Es sieht in jeder Auswertung so aus,
als hätte es eine Messung geben können.

Was einmal gezählt **wurde**, bleibt gespeichert und wird weiter angezeigt.
Nicht mehr erheben ist etwas anderes als verschweigen.

### Das Alter beim Waschen ist eine Schätzung, und das steht jetzt dran

Der Betrieb hat einen Denkfehler im Erklärdokument korrigiert: Auf einer
Palette mit sortierten Kisten kommen mehrere Eingangsdaten zusammen — „dann
gibt es nur noch sortierdatum und kalibergrösse und chargennummer". Die Palette
trägt kein Eingangsdatum mehr.

Der ehrliche Ersatz ist das **massegewichtete mittlere Eingangsdatum der
Charge**, und seine Unsicherheit ist die Streuung der Erntedaten derselben
Charge — eine Zahl, die die App sich selbst ausrechnen kann. `alter_quelle`
sagt seither je Arbeit, ob das Alter abgelesen oder geschätzt ist.

Ob die Erntespanne einer Charge endgültig ist, kann die App nicht wissen: Eine
Lücke im Erntejournal kann drei Tage Regen sein oder das Saisonende. Das sagt
der Betrieb mit einem Haken, nicht die Statistik.

### Die Kontrollpalette misst, was einmalige Wägungen nicht messen können

Bisher wurde jede Lagerkontrolle an einer anderen Palette gemacht. Daraus
lässt sich eine mittlere Rate schätzen, aber nicht die Frage beantworten, die
den Betrieb wirklich beschäftigt: ob die Verdunstung zu Beginn schneller läuft
(„wir glauben jetzt zu beginn hats viel schock"). Dafür braucht es **dieselbe**
Palette zweimal. Am Anfang alle 14 Tage, später alle 30 — und ausdrücklich
ohne Faules zu zählen, denn „was wir nicht können - wöchentlich faule zählen".

### Die Schrumpfung des Verderbs: bewusst in die nächste Runde

Geplant war, den Verderb wie die Verdunstung je Sorte zu schrumpfen und mit
● ◐ ○ zu kennzeichnen, wie gut eine Sorte belegt ist. Gebaut wurde nur die
**Lage** (`v_verderb_lage`, 0075): je Sorte, auf wie vielen eigenen Messpunkten
aus wie vielen Chargen die gemeinsame Kurve dort ruht.

Zwei Gründe. Erstens ist die Schrumpfung der einzige offene Punkt, der die
**Kaskade** bewegt; alles andere dieser Runde sind Masken. Beides zusammen
hiesse: Zahlen und Bildschirme ändern sich gleichzeitig, und wenn danach etwas
falsch aussieht, kann niemand sagen, welches von beidem es war. Zweitens wäre
ein ◐ auf einer Sorte, deren Zahl in Wirklichkeit zu hundert Prozent das
Gesamtmittel ist, ein Zeichen, das lügt. Solange es nur eine Kurve für alles
gibt, steht überall ○.

### Nichts geht verloren — Journal, Wächter, zwei Webseiten

Der Auftrag war wörtlich: „genügend geschützt dass dort nicht mehr gross
rumgepfuscht wird von der KI und falls schon, dann nur so dass nichts verloren
geht". Drei Schichten:

1. **Das Journal.** Jede Änderung an einer der 17 Erfassungstabellen schreibt
   Vorher und Nachher nach `erfassung_journal`, mit Person und Zeit. Eine
   gelöschte Messung ist damit nicht weg, sondern gelöscht *und* aufgehoben.
2. **Der Zerstörungswächter.** `supabase/test/keine_zerstoerung.sh` liest jede
   Migration, bevor sie läuft, und weist `drop table`, `drop column`,
   `truncate` und `delete` ohne `where` ab. Drei begründete Altfälle stehen mit
   Namen auf der Ausnahmeliste — eine Liste mit Namen ist etwas anderes als
   eine Regel mit Löchern.
3. **Zwei Datenbanken.** Echtbetrieb und Beispiel laufen getrennt, und welche
   vorliegt, sagt die **Datenbank** (`einstellung.betriebsmodus`), nicht der
   Build. Ein Build kann sich irren; eine Datenbank weiss, was sie ist. Im
   Echtmodus weist ein Auslöser das Anlegen von Beispieldaten ab, auch von
   Hand im SQL-Editor.

### Der Schichtwechsel, vier Kanten

Beitreten geht seit je mit zwei Tipps. Was fehlte, waren die Kanten, die genau
beim Schichtwechsel weh tun: Die Liste auf der Startseite lud **einmal** und
alterte danach still (das Handy liegt zwischen zwei Griffen auf der Palette);
ein zweiter „Mitmachen"-Tipp lief in eine rote Datenbankmeldung, weil der
Eintrag von einem anderen Gerät schon stand; `verlassen_ts` wurde **nirgends**
gesetzt, also stand am Abend die ganze Tagesbelegschaft unter „Dabei"; und die
Rolle merkte sich das Gerät je Arbeit, nicht je Person — wer das Handy um vier
Uhr übernahm, erbte sie.

Alle vier sind behoben. Keine davon war ein Rechenfehler; alle vier hätten in
der Halle Zeit gekostet.

### Was bewusst nicht gemacht wurde

Keine Tabelle und keine Spalte gelöscht (der Wächter würde es auch abweisen).
Keine neue Abhängigkeit. Keine Schrumpfung des Verderbs (eigene Runde, siehe
oben). Und `alter_spanne_tage` wird zwar gerechnet und dokumentiert, aber noch
nirgends als Fehlerbalken gezeichnet — das gehört zur Markierung der einzelnen
Punkte in der Verderbskurve, und die ist Sache der Auswertungsrunde. Bis dahin
sagt eine Fussnote unter der Kurve, welche Punkte abgelesen und welche
geschätzt sind.

## Runde R — vor der ersten echten Palette, und der Plan für das Dashboard

### Die Kette lief seit Runde P nicht mehr — und hat sofort etwas gefunden

`pruefstand/kette.mjs` war zuletzt am 13. September grün gelaufen, **vor**
Migration 0072. Die Runde Q hatte den Palox auf „je Arbeit" umgestellt (erste
Ablesung = Startstand, Menge = Ende − Anfang), das Zettelgewicht beim Sortieren
zur Pflicht gemacht, die Kisten je Kaliber gestrichen und 36 Kisten je Palette
vorbelegt — und die Kette war nie nachgezogen worden, weil der lokale
Postgres-Server ausgefallen war und der Prüfstand darum still übersprungen
wurde. Ein früherer Bericht nannte die Kette trotzdem grün: Das war falsch, es
war das alte Protokoll. Nachgezogen sind fünf Schritte; beim Nachziehen fand
die Kette einen echten toten Punkt: Der Abschluss beim Waschen verlangte die
Antwort auf „Palox zwischendurch geleert?", zeigte die Frage aber nur nach
einer Ablesung — ohne Ablesung (die beim Waschen freiwillig ist) kam kein
Arbeiter je an „Arbeit fertig" vorbei. Eine Bedingung (`paloxAblesungen > 0`)
behebt es. Lehre, festgehalten: Ein Prüfstand, der nicht läuft, ist kein
grüner Prüfstand.

### Fax auf Eis heisst 0 durch Entscheid, nicht unbekannt

Der Betrieb streicht Fax aus der Oberfläche, nicht aus der Datenbank. Die
Kaskade hätte zwei falsche Möglichkeiten gehabt: den Fax-Anteil der alten
Demo-Saison weiterrechnen (2 350 kg „erwartet", die niemand mehr misst) oder
ihn als unbekannt führen — dann wäre die verkaufsfähige Masse für immer
„höchstens" beschriftet, in jeder Prognose. Beides wäre eine Zahl aus einer
Lücke. Die dritte Möglichkeit ist die Entscheidung selbst: Der Betrieb misst
kein Faules beim Abpacken, also erwartet die Kaskade keins — 0, bekannt, mit
der Basis „eingefroren". Ein Schalter (`einstellung.fax_eingefroren`), keine
gelöschte Sicht; der Prüfblock 0078 dreht ihn kurz zurück und beweist, dass die
alte Rechnung dahinter lebt. Zwei ältere Tests, die „ohne Fax-Arbeit ist der
Strom unbekannt" prüften, prüfen jetzt beides: mit Schalter 0, ohne Schalter
unbekannt.

### Das Lager nach Kaliber: eine Funktion je Aufruf, nichts im Rechenwerk

Die erste Fassung von `v_lager_kaliber` rechnete alle dreissig Horizonte auf
einmal — 1.16 s auf der Demo, 0.65 s nach dem Auftrennen einer OR-Verknüpfung
in zwei Hash-Joins. Der Bildschirm braucht aber nur zwei Spalten: „heute" und
„in X Wochen". Also eine Funktion `lager_kaliber(h)`. Dabei zeigte der Plan den
ersten Fresser: `betriebstag()` je Kürbiszeile — 4 238 Aufrufe, 150 ms; einmal
je Sortierlauf gerechnet sind es 34 ms für den ganzen Aufruf.

Die zweite Fassung hielt „heute" noch als gespeicherte Sicht im Rechenwerk.
Der Lasttest hat sie gekippt: Sein Prüfdatensatz hat 255 000 CSV-Kürbisse,
„heute" kostete dort eine Sekunde, und das Neurechnen lag mit 13.1 s über
seiner Zwölf-Sekunden-Grenze — von der die Grundlinie ohne jede neue Sicht
schon 11.6 bis 12.0 s braucht. Der Verbund mit Ungleichung (Gewicht zwischen
Bandgrenzen) über 219 000 Zeilen wurde durch `width_bucket` über die
Bandschwellen je Sorte ersetzt; und die gespeicherte Fassung ist weg. Der
Bildschirm ruft `lager_kaliber(0)` und `lager_kaliber(7·X)` direkt — zwei
Aufrufe, im Speicher gehalten. Das ist eine bewusste Ausnahme von „nur
gespeicherte Sichten" (0061): Die Regel schützt vor Zeitüberschreitungen beim
Laden, und ein Aufruf von 35 ms auf der Demo ist keine; der Prüfblock misst
ihn. Die Formel steht einmal; `v_lager_kaliber` (für den SQL-Editor) und der
Aufruf lesen dieselbe Funktion; der Prüfblock beweist die Identität zur
Kaskade über alle Horizonte per Funktion — und verbietet eine gespeicherte
Fassung ausdrücklich, damit niemand sie in guter Absicht zurückbaut.

### Was die Aufteilung ehrlich macht

Ein Kürbis, der durch Verdunstung unter das kleinste Band fällt, ist laut
Kaskade noch verkaufsfähig (die rechnet mit einem konstanten Anteil „zu
klein"), laut Band nicht mehr. Statt ihn still im kleinsten Band zu lassen oder
still abzuziehen, steht er als eigene Spalte „unter Kaliber" da — so bleibt die
Summe die Kaskade, und der Betriebsleiter sieht, wie viel seiner Ware dem
Kaliber entwächst. Chargen ohne eigene Sortier-CSV bekommen die Verteilung
ihrer Sorte und sagen es (`basis = 'sorte'`); 37 von 86 liegenden Portionen
der Demo sind so. Sorten ohne jede CSV bekommen keine Aufteilung — eine Zeile
mit der ganzen Masse und ohne Band.

### Die Marge ohne Verkaufsdatei

Der Betrieb will je Palette wissen, was die Kiste über dem Soll hat, und aus
etwa zehn Wägungen je Saison den Durchschnitt — nicht eine Hochrechnung auf
verkaufte Kisten, die er nie einer Wägung zuordnen kann. `v_marge_wiegung`
tut genau das und nichts weiter; `v_ueberfuellung_verkauf` bleibt für die
andere Frage bestehen. Der Prüfblock verbietet der neuen Sicht das Wort
`lieferung`.

### Was bewusst nicht gemacht wurde

Das Dashboard selbst ist nicht umgebaut — das ist der Auftrag der Runde R an
die ausführende KI (`docs/PROMPT_RUNDE_R.md`), mit dem Vertrag
`pruefstand/abnahme_r.mjs`, der heute rot ist und es bleiben soll, bis die
zwei Reiter stehen. Keine Erfassungstabelle, keine Spalte, keine
Arbeiter-Maske wurde für die Auswertung geändert; die einzige neue
Erfassungsspalte dieser Runde (Kontrollpalette: Eingangsdatum und Brutto vom
Zettel, 0077) ist freiwillig. `fertige_paletten_gesamt` wird gespeichert, aber
noch von keiner Sicht gelesen — der Nenner beim Waschen ist § 5.3 des
Auftrags.

## Runde R — die zwei ersten Reiter (16. September)

### Warum der Reiter „Lagermanagement" heisst und nicht mehr „Überblick"

Ein Überblick ist alles und nichts. Der Betrieb macht das Dashboard mit einer
Frage auf: „wieviel kürbis ist gerade im lager — aber halt genau". Der Name
sagt jetzt, was der Reiter kann, und die Trennung ist scharf: **alles über
morgen steht im Lagermanagement, alles bis heute in den Ursachen.** Wer wissen
will, was die liegende Ware in acht Wochen noch wert ist, geht in den ersten
Reiter; wer wissen will, wo das Faule herkam, in den zweiten. Vorher stand
beides auf beiden, und keine Karte sagte, auf welchen Tag sie sich bezieht.

### Zwei Achsen an derselben Messung

„wann hat fäulnis besonders zugelegt … plötzlich ab dezember" und „faulen sie
nach N Wochen" sind zwei Fragen an **eine** Messung. Statt zwei Grafiken
nebeneinander zu stellen (und damit zu suggerieren, es seien zwei Messreihen),
tragen die zwei Zeitbilder der Ursachen einen Umschalter: *Kalender* oder
*liegt seit*. Dieselben Punkte, eine andere x-Achse. Die Wahl merkt sich der
Browser je Karte (`localStorage`), damit niemand sie bei jedem Aufruf neu
treffen muss.

Auf dem Kalender endet die Achse bei heute — rechts davon gibt es keine
Messung, und eine leere Fläche mit dem Wort „Prognose" wäre eine Behauptung.
Auf der Lagerdauer heisst der Bereich rechts der Heute-Linie **„länger
gelagert"**: dort liegt nicht die Zukunft, sondern längere Lagerung.

### Der Messtag kommt aus dem Betriebstag, nicht aus `now()`

`v_schimmel_punkte.messtag` ist `betriebstag(...)` der Arbeit (oder der
Wägung) — dieselbe Funktion, die schon über „gehört diese Ablesung zu gestern
Abend oder zu heute früh" entscheidet. Damit liegt ein Punkt im Kalender genau
dort, wo die Arbeit im Journal steht, und der Prüfblock kann es zeilenweise
nachrechnen (0079 a5). Ein zweiter Datumsbegriff hätte zwei Wahrheiten ergeben.

### `mv_schimmel_punkte` bleibt eingefroren, `erg_punkte` wird neu gebaut

Die Spalte gehört an beide — aber `mv_schimmel_punkte` neu anzulegen verlangt
`cascade` und nimmt **34** Objekte mit (`v_schimmel_kurve`,
`v_schimmel_modell_rechnen`, `v_selektionsverdacht`, `mv_kaskade`,
`erg_prognose` …). Eine Runde, die das Dashboard umbaut, reisst nicht die
Kaskade ein. Also: `mv_schimmel_punkte` steht mit einer **ausdrücklichen
Spaltenliste** und `if not exists` da (Migrationsweg und `setup.sql` ergeben
dieselbe Fassung), und `erg_punkte` — die Fassung, die die App liest — wird aus
`v_schimmel_punkte` gebaut. Der Prüfblock 0068 (b) prüft seither nicht mehr
„Kopie", sondern: gleiche Werte in den gemeinsamen Spalten, keine
Analyse-Sicht liest `erg_punkte`, und ein `refresh` bleibt unter einer Sekunde.

### Der Nenner beim Waschen: erst die eigenen Paletten, dann die Kisten

`v_auftrag_masse` hat eine neue Quelle **vor** dem Kistenweg:
`fertige_paletten` = `fertige_paletten_gesamt` × dem Mittel der eigenen
gewogenen vollen Paletten dieser Arbeit. Warum davor: Die Kaliber-Palette aus
dem Zwischenlager wird nie gewogen, der Kistenweg rechnet also mit einem
Kistengewicht aus *fremden* Arbeiten und quer über den Gebindewechsel. Die
fertigen Paletten sind gewogen, in dieser Arbeit, in diesem Gebinde.

Dass der Kistenweg das Faule doppelt zählt (er misst, was *hineinging*, und die
Basis addiert das Faule noch einmal), steht als Befund B-1 im
`BEFUND_RUNDE_R.md` und als Frage an den Betrieb in `FRAGEN.md`. Repariert wird
er nicht mit einer Formel, sondern mit einer Angabe: Sobald eine Wasch-Arbeit
ihre fertigen Paletten meldet, greift der neue Weg.

### Zwei Bilder, eine Rechnung

`kaliber_glocke(h)` und `lager_kaliber(h)` lesen beide `kuerbis_stichtag(h)`
und `lager_schluessel()`. Der Prüfblock beweist an drei Stichtagen, dass die
Stufen einer Gruppe auf die Masse ihrer Bänder summieren. Zwei Bilder, die
über dieselbe Ware Verschiedenes sagen, wären schlimmer als ein Bild weniger.

### Die Marge zeichnet kein Diagramm

Ein Balken um eine Nulllinie und ein Punkt in einem Band sind **eine Zahl je
Zeile**. Dafür ein SVG mit Achse zu bauen, hiesse eine Achse zu zeichnen, die
nichts trägt. Die zwei Karten tragen ihre Zahlen in einer Tabelle und daneben
ein kleines Bild aus CSS. Wer keine Farben sieht, liest die Tabelle.

### Die Spalte sagt ihre Herkunft im Kopf

In der Tabelle „Was ist noch im Haus?" sind die Spalten **verschiedener**
Herkunft: links gerechnet bis heute, rechts über heute hinaus. Eine
Herkunftsmarke am Fuss der Karte hätte für beide gegolten und damit für keine.
Darum steht sie in der Kopfzelle der Spaltengruppe — dort, wo man die Zahl
liest. Deshalb heisst die zweite Gruppe auch „verkaufsfähig in X Wochen" und
nicht bloss „in X Wochen": Eine Beschriftung muss sagen, wovon die Kilo sind.

### Drei Prüfstände waren stumpf

Beim Grünmachen ist aufgefallen, dass drei Werkzeuge nicht massen, was sie
behaupteten — und alle drei wären **still** grün geblieben:

- Die Abnahme verglich zweimal `innerText` eines SVG-Elements. SVG hat kein
  `innerText`; zwei leere Zeichenketten sind immer gleich, der Punkt hätte nie
  angeschlagen. Jetzt `textContent` plus `data-x-einheit`.
- Der Begriffs-Prüfstand warf beide Kopfzeilen einer Tabelle in eine Liste;
  bei zwei Kopfzeilen verrutschten die Spaltennamen. Jetzt löst er `colspan`
  und `rowspan` auf und setzt je Spalte zusammen, was ein Mensch liest.
- Die Herkunfts-Sonde des Prüfwerks las `src/pages/Ueberblick.tsx` — eine
  Datei, die es seit dieser Runde nicht mehr gibt. Sie wäre beim nächsten Lauf
  abgestürzt, statt ihren Befund zu melden.

Ein Werkzeug, das nicht rot werden kann, ist kein Werkzeug. Das gehört zum
Ergebnis der Runde wie die zwei Reiter selbst.

### Was bewusst nicht gemacht wurde

Kein neuer Reiter; Chargen, Messungen und Betrieb sind unverändert. Keine
Prognose auf Ursachen. Keine zweite Verdunstungs- oder Verderbsformel im
Frontend. Keine Schlag-Ebene in den Filtern. Keine Fax-Rückkehr. Keine
Verkaufsdatei in der Marge. Kein Umbau der Arbeiter-App — auch nicht „nur ein
Feld": `#fertige-gesamt` gab es seit Runde Q, die Kette füllt es jetzt bloss
aus, damit der neue Weg im Prüfstand wirklich läuft.

## Runde T: die Arbeiter-App führt, statt zu erklären

### Die Startablesung des Palox ist eine Sperre, keine Empfehlung

Bis Runde T stand nach dem Start „Später" unter der Palox-Maske. Das war gut
gemeint — der Vorarbeiter steht vielleicht noch nicht an der Waage — und
führte in eine Falle, die erst am Ende zuschnappte: Mit nur der Ablesung am
Schluss hat die Arbeit keine Faul-Menge (AB-51: zwei Ablesungen, sonst keine
Differenz), der Abschluss verlangte die zweite, und die Ware war längst
durch. Der einzige Ausweg wäre „Stand unverändert" gewesen — eine erfundene
Null. Der Betrieb: „warum überhaupt dann weiter kommen ohne anklicken?"

Entschieden: Solange die Startablesung fehlt, gibt es keine Checkliste.
„Zurück" führt aus der Arbeit hinaus, nicht an der Frage vorbei; wer die
Rolle wechselt oder die Arbeit neu öffnet, landet wieder bei der Frage. Der
ehrliche Ausweg bleibt: *Palox kann nicht abgelesen werden* — mit Nachfrage
und der Folge im Klartext — setzt `auftrag.palox_unbekannt`, dieselbe Spalte
wie beim Leeren zwischendurch (0072). Die Arbeit hat dann eine **unbekannte**
Faul-Menge, nicht null, und der Abschluss fragt sie nicht mehr nach
Ablesungen. Keine neue Spalte, kein neues Wort in der Datenbank.

Was nicht gesperrt wird: der Zähler. Wer beitritt, zählt — der Palox ist
Sache dessen, der die Arbeit führt.

### Ein grauer Knopf ohne Grund ist eine Sackgasse

Der Rahmen `Schritt` kannte zwei Zustände: Knopf da und Knopf weg. „Weg"
hiess in der Praxis: Der Arbeiter scrollt, sucht, findet nichts — und die
Antwort kam erst drei Schritte später als Liste „Fehlt noch". Jetzt ist der
Knopf immer da; ist er grau, steht der eine Satz darüber, der sagt, was
fehlt. Die Prüfstände haben das mitgemacht: `kette.mjs` prüft nicht mehr,
dass der Knopf fehlt, sondern dass er gesperrt ist — mit dem Grund daneben.

### Was bewusst nicht gemacht wurde

Keine Migration. Keine neue Tabelle, keine neue Spalte, kein neuer
Einstellungsschlüssel — die Namen der Zählblätter stehen im Code
(`src/lib/taetigkeit.ts`), weil sie sich mit dem Papier ändern, nicht mit
der Saison. Die Lagerkontrolle ist unberührt; die Fax bleibt eingefroren.
Und die Erklärungen sind nicht gelöscht, sondern umgezogen: Wofür eine Zahl
gebraucht wird, steht in `DATENERHEBUNG.md` — dort liest es der
Betriebsleiter, der es wissen muss.

## Runde U: zwei Arten von Sortierdatei (21. September, 0082)

### Die Annahme war falsch, und sie war still falsch

Bis hierher galt: Ein Sortierlauf, eine CSV, das Datum im Namen. Der
Betrieb korrigierte das: „es gibt nur eine 1614 - und bei jedem sortieren
wird einfach unterhalb weiter angefügt - also die zuweisung auf das datum
ist nicht möglich".

Das sind zwei verschiedene Fehler, und beide liefen lautlos:

**Doppelzählung.** `roh_pruefsumme unique` schützt vor derselben Datei,
nicht vor der gewachsenen. Wer dieselbe Sammeldatei ein zweites Mal
hochlädt, brachte bis 0082 alles vom ersten Mal noch einmal mit — die
Charge hatte plötzlich doppelt so viele Kürbisse, und keine Meldung sagte
es.

**Ein Datum, das niemand gemessen hat.** Ohne Datum im Namen nahm die App
den Zeitstempel der Datei. Bei einer Sammeldatei ist das der Moment des
letzten Anhängens; bei einer kopierten Datei der des Kopierens. Aus diesem
Tag rechnet die Verdunstung, wie lange ein Kürbis geschrumpft ist.

### Was jetzt gilt

Die App kennt **zwei Arten**. Eine **Lauf-Datei** trägt das Datum im Namen
— ab Oktober 2026 im Format `1614_07_10_26`, aber der Parser nimmt jeden
Trenner (`1614.07.10.26`, `1616 7 10 26`, `1614-07-10-2026`), ein- oder
zweistellige Tage, zwei- oder vierstellige Jahre, mit oder ohne Uhrzeit.
Eine **Sammeldatei** heisst nur nach der Charge.

Von einer Sammeldatei wird nur das **Delta** gespeichert. Die Datenbank
rechnet es; die Oberfläche zeigt es vorher an („7 in der Datei → 3 schon
bekannt → 4 neu"), damit niemand blind drückt.

Statt eines erfundenen Zeitpunkts steht ein **Zeitfenster**. Daraus leitet
`sortiertag_bestimmen()` den Sortiertag ab: Liegt genau eine Sortier-Arbeit
im Fenster, gilt ihr Tag; liegen mehrere, das nach Zählung gewichtete
Mittel; liegt keine, die Mitte des Fensters. Und die Lesung sagt in
`sortiertag_quelle`, welcher Fall es war — dieselbe Ehrlichkeit wie bei
`masse_quelle`.

Der Zeitstempel der Datei ist damit **keine Datumsquelle mehr**, sondern
nur noch obere Schranke: Später als da kann nichts darin sortiert worden
sein.

### Warum die Datei nicht einfach neu hochgeladen wird

Der Betrieb hatte die Sammeldateien schon hochgeladen, bevor diese Runde
begann — sie lagen als Lauf-Dateien in der Warteschlange. Löschen und neu
einlesen wäre der naheliegende Weg und der falsche: Die Masse ist richtig
(jede Datei wurde einmal hochgeladen), nur die Deutung ist falsch. Und
beim Löschen verschwände die Rohdatei aus dem Speicher.

`lesung_als_sammel()` deutet sie an Ort und Stelle um: Der Zeitstempel
wandert von `datei_zeit` nach `bis_ts` und wird zur oberen Schranke, der
Sortiertag wird abgeleitet, die Zuordnung zu einer Arbeit fällt weg. Kein
Kilogramm bewegt sich.

### Die Probe, die eine falsche Datei abweist

`reinigen()` entscheidet je Zeile aus der Zeile und dem zuletzt behaltenen
Wert. Damit ist die Reinigung **präfixstabil**: Was aus den ersten N Zeilen
entsteht, entsteht auch aus den ersten N Zeilen einer längeren Datei.
Nachgemessen, bevor darauf gebaut wurde: `reinigen(P+S).n_gueltig −
reinigen(P).n_gueltig = reinigen(S).n_gueltig` (298 = 298), keine negative
Stufe.

Daraus folgt die Probe: Zieht man vom Histogramm der Datei ab, was schon
eingelesen ist, darf **keine Stufe negativ** werden. Wird eine es doch, ist
die Datei keine Fortsetzung — sie wurde bearbeitet, oder sie gehört zu einer
anderen Charge. Dann wird nichts übernommen und gesagt, welche Stufen
fehlen.

### Was der Prüfblock gefunden hat

Zwei Fehler, die ohne ihn in Betrieb gegangen wären.

Der erste in `lesung_als_sammel()`: Erst kürzen, dann löschen, was
vollständig bekannt ist. Die zweite Anweisung las die schon gekürzte Zahl —
aus 6 gelesenen bei 4 bekannten wurden 2, und 2 ist nicht mehr grösser als
4, also verschwanden auch die. Die Lesung meldete zwei Kürbisse und trug
keinen. Jetzt wird erst gelöscht, dann gekürzt.

Der zweite ist älter und wog schwerer. `setup.sql` entsteht verdichtet; von
jedem Objekt bleibt nur die jüngste Anweisung, und die wandert in einen nach
Abhängigkeiten geordneten Teil. Bauen zwei angemeldete Anweisungen dasselbe
Objekt, zog der Verdichter zwischen ihnen keine Kante — der Kommentar
versprach, sie stünden dann in der Reihenfolge der Migrationen, der Code
hielt das aber nicht. Die Sortierung nahm, was zuerst fertig war. Bei
`erg_punkte` hiess das: Die Kaskaden-Schleife wartet auf zwei Dutzend
Ansichten, die spätere Fassung aus 0079 auf eine — also lief die spätere
zuerst und die Schleife überschrieb sie. In **jeder aus setup.sql
eingerichteten Datenbank** fehlte `erg_punkte` seit 0079 die Spalte
`messtag`, die der Ursachen-Bildschirm liest; aus den Migrationen einzeln
eingespielt war sie da. Der Abgleich in `run.sh` sieht genau solche
Unterschiede — er war nur nie bis zu Ende gelaufen.

### Was bewusst nicht gemacht wurde

**Kein neuer Wert in `zuordnung_status`.** Naheliegend wäre gewesen, eine
Sammel-Lesung mit `zuordnung = 'sammel'` zu kennzeichnen. Dagegen sprach
zweierlei: `alter type … add value` in einer Transaktion ist heikel, und
der Status hat für eine Sammel-Lesung ohnehin keine Bedeutung. Die
Warteschlange fragt deshalb nach `art = 'lauf'` — nach dem, was sie meint.

**Die Demo-Saison zeigt die Sammeldatei noch nicht.** `demo_daten_laden()`
erzeugt weiterhin nur Lauf-Dateien mit Datum im Namen — die Fähigkeit ist in
`test/csv.test.ts` und im Prüfblock 0082 belegt, nicht in den Beispieldaten.
Das weicht von der Linie aus Runde S ab („jede Fähigkeit der Masken kommt in
den Daten vor"); es steht hier, damit es nicht stillschweigend untergeht. Wer
es nachholt, braucht eine Migration am Demo-Erzeuger und muss die
Reproduzierbarkeitsprobe 0081 (f) mitziehen.

**Keine gelöschte Spalte.** `datei_zeit` und `datei_zeit_quelle` bleiben;
sie halten fest, was beim Einlesen bekannt war, und Abschnitt 2 der
Migration liest sie, um die Bestandsdaten ehrlich zu deuten: Wer sein Datum
aus dem Dateinamen hatte, bekommt `sortiertag_quelle = 'datei'`, wer es vom
Zeitstempel hatte, `'dateistempel'` — und der sagt von sich, dass er kein
Sortierdatum ist.

## Runde V: die Halle meldet sich (26. September, 0083–0088)

### Der Ausschuss, der immer null war

Der Betrieb: „ich glaube es hat einen bug beim eintragen von zu klein und
zu gross bei waschen und waschen und sortieren - man kanns zwar eingeben -
aber es gibt trotzdem immer nur 0 ein". Er hatte recht, und der Fehler
lag an zwei Stellen, die einander deckten.

Die Rechnung zog **immer** die Palette ab — 25 kg —, auch wenn der
Ausschuss in einer einzelnen Kiste auf dem Boden stand. Eine Kiste von 12
kg brutto minus 1.5 kg Tara minus 25 kg Palette ist −14.5 kg. Und dieses
Ergebnis klemmte die Maske mit `Math.max(…, 0)` auf null, und der Auslöser
in der Datenbank mit `greatest(…, 0)` gleich noch einmal. Zwei Sicherungen,
die beide dasselbe taten: aus einer unmöglichen Zahl eine falsche machen.

Jetzt fragt die Maske, ob die Ware auf einer Palette steht
(`mit_palette`), und die Datenbank **weigert sich** bei einem Netto unter
null mit einem Satz, der sagt, was nicht stimmen kann. Die alten Zeilen
wurden nachträglich gedeutet: Wo die Null nur aus der Palette kam — ohne
Palette wäre das Netto positiv —, steht jetzt „ohne Palette". Wo es nicht
eindeutig ist, steht „Palette fraglich" in den Auffälligkeiten, und der
Betriebsleiter entscheidet.

### Brutto und Netto

Der Betrieb wollte sichergehen: „du weisst dass das zettelgewicht brutto
ist - und dass das abgelesene gewicht auch brutto ist … schau dass du
immer brutto und netto korrekt speicherst". Das Audit über alle
Schreibpfade fand keinen Fall, in dem die App ein Netto speichert: Jede
Tabelle nimmt `brutto_kg`, und jedes Netto entsteht in einem Auslöser aus
Brutto, Kisten, Gebinde und Palette. Die Verdunstung vergleicht also Netto
mit Netto derselben Rechnung. Was fehlte, war das Wort: Die Felder heissen
jetzt „(kg brutto)", in allen sechs Sprachen.

### Der Palox wird mittendrin geleert

Seit 0073 galt: Fällt der Stand, ist die Menge der ganzen Arbeit unbekannt
— richtig („leer ist nicht null"), aber schade, denn der Betrieb leert
den Palox, wenn er voll ist, und das ist oft mitten am Tag. Der Weg, der
die Menge bekannt hält, sind zwei Ablesungen: vor dem Leeren (eine normale
Ablesung, die Differenz zählt) und danach die leere Box. Die zweite ist
ein **neuer Anfang**: `palox_nach_leeren`, Differenz 0, und alles Weitere
rechnet von dort.

Warum nicht das alte `palox_geleert` wiederverwenden? Weil es das
Gegenteil bedeutet: „der Stand ist gefallen, und niemand weiss, wie viel
vorher noch dazukam" — eine unbekannte Menge. Die neue Spalte bedeutet
„gemessen geleert" — eine bekannte. Zwei Bedeutungen, zwei Spalten; eine
Spalte mit zwei Bedeutungen wäre der nächste stille Fehler.

Die Ablesung nach dem Leeren ist mit dem Leergewicht aus den
Einstellungen **vorbelegt**, und die Maske sagt das (AB-50: eine
vorbelegte Zahl darf nicht wie eine gemessene aussehen). Wer die Waage
abliest, überschreibt sie.

### Die Rückmeldung — und warum sie nicht im Repository liegt

Der Betrieb: „am ende eines auftrags … soll die app fragen ob alles gut
lief oder verbesserungswünsche … textfeld … grosser knopf mit mikrofon
… und die audiodatei soll irgendwo im github abgelegt werden".

Der Text und der Knopf sind gebaut, wie gewünscht (0085,
`Sprachaufnahme.tsx`): aufnehmen, beenden, anhören, löschen, neu
aufnehmen, „Bitte auf Hochdeutsch sprechen". Gespeichert wird beim
Abschliessen — und nur, wenn etwas da ist: Text, Aufnahme oder beides.
Eine leere Rückmeldung gibt es nicht als Zeile.

Die Datei liegt **nicht** im Repository, sondern im Speicher des
Supabase-Projekts (Bucket `rueckmeldungen`), und das ist eine bewusste
Abweichung vom Wortlaut. Ein Repository ist Quelltext: Jede Datei darin
ist eine Fassung des Programms, wird bei jedem Auschecken mitkopiert und
ist für jeden lesbar, der den Quelltext lesen darf. Eine Sprachaufnahme
über einen Arbeitstag ist ein Betriebsdatum — sie gehört dorthin, wo auch
die Rohdateien der Sortiermaschine und jede Messung liegen, hinter
denselben Zugangsregeln, im selben Projekt, das der Betrieb selbst
verwaltet. Der Bucket ist nicht öffentlich; die App holt sich zum Anhören
eine auf eine Stunde befristete Adresse. Und eine Aufnahme wird nie
überschrieben oder gelöscht — es gibt keine Regel dafür.

Ausgewertet wird die Rückmeldung nicht. Sie ist eine Stimme aus der Halle
für den Betriebsleiter; sie steht bei den Arbeiten unter Betrieb, mit
einem Zeichen für Text oder Ton, zum Aufklappen.

Was der Prüfstand nicht kann: aufnehmen. Ein Browser ohne Mikrofon nimmt
nichts auf, und die Kette läuft in einem solchen. Sie prüft den Text —
im ersten Durchlauf kommt er an, im zweiten bleibt er leer und erzeugt
keine Zeile. Die Zustände der Aufnahme (läuft, fertig, gelöscht, neu) sind
von Hand geprüft; der Prüfblock 0085 prüft die Datenbank dahinter.

### Die verschenkte Marge, gegliedert wie die Ansicht

Zwei Karten nebeneinander, je Sorte zusammengefasst, das Kaliber als „K2"
ohne Gramm: Der Betrieb nannte es scheusslich, und er hatte recht. Der
Bildschirm kann nur gliedern, was die Datenbank auseinanderhält —
`v_marge_wiegung` (0078) fasst je Sorte zusammen, die Charge ist darin
verschwunden. 0086 stellt dieselbe Rechnung eine Ebene feiner daneben
(`v_marge_charge`): dieselben Spalten, derselbe Nenner (nur volle
Paletten), plus Charge und Schlag. Nicht statt, sondern zusätzlich: Die
Zahl je Sorte ist die, mit der der Betriebsleiter die Kisten füllen lässt;
die je Charge zeigt, wo es herkommt.

Die Karte folgt dem Filter oben, eine Stufe feiner: alle Chargen → je
Sorte ein Block, die Chargen aufklappbar darunter; eine Sorte → die
Chargen untereinander; eine Charge → ihre Wägungen. Das Kaliber heisst,
was es wiegt: „K2 · 900–1200 g", aus dem Sortierschema der Sorte. Der
Prüfblock 0086 hält die Chargen gegen die Sorte: Wägungen, Kisten und das
gewichtete Mittel je Kiste müssen sich aufsummieren — sonst zeigte die
aufgeklappte Charge andere Zahlen als die Zeile darüber.

### Was die Kette gefunden hat

Beim Rückwärts-Einspielen der Runde (`kette_pruefen.sh`) stand die Kiste
Ausschuss von 12 kg ohne Palette — richtig als 11 kg gespeichert — sofort
als Auffälligkeit da: „aus Brutto 12.00 kg und heutiger Tara wären es
0 kg". Die Nachrechnung in `v_plausibilitaet` (0066/0070) war die alte
Rechnung: immer die Palette abziehen, und das Ergebnis mit `greatest(…, 0)`
auf null klemmen. Die zwei Fehler aus 0083 lebten dort ein drittes Mal
weiter — und hätten jede richtige Ausschuss-Zeile ohne Palette als
Tippfehler gemeldet. 0087 lässt die Probe so rechnen wie den Auslöser;
der Prüfblock 0087 hält beides fest: richtig gespeichert heisst keine
Meldung, und eine nach dem Wiegen geänderte Tara wird weiterhin gemeldet.

### Nachtrag: der Ausschuss Kiste für Kiste (0088)

Nach dem Fix aus 0083 hat der Betrieb gesagt, wie der Ausschuss wirklich
gewogen wird: „sie werden wahrscheinlich in G2-Kisten sein … die Kisten
werden nacheinander auf eine Waage gestellt … sie werden nie auf Paletten
stehen, sondern halt nur einzelne Kisten". Damit ist die Frage „steht eine
Palette drunter?" beim Ausschuss beantwortet — mit Nein, ein für alle Mal —
und die Maske hat sie nicht mehr. Stattdessen sagt sie, was gilt, vor dem
Feld: „Eine einzelne Kiste auf die Waage — ohne Palette", zählt mit
(„Kiste 3"), hat G2 vorbelegt und nimmt die nächste Kiste mit Enter.

**Eine Zeile je Art, nicht eine je Kiste.** `kg` ist ganzzahlig, und der
Auslöser rundet je Zeile. Drei Kisten zu 12, 13.5 und 11 kg brutto sind
netto 10.5, 12 und 9.5 — als drei Zeilen 11 + 12 + 10 = 33 kg, als eine
Zeile 36.5 − 4.5 = 32 kg. Die Summe wird einmal gerundet. Die einzelnen
Gewichte gehen dabei nicht verloren: Sie stehen in der Bemerkung („3
Kisten einzeln gewogen: 12 · 13.5 · 11 kg"), lesbar in der Arbeit und in
der Korrektur. Der Prüfblock 0088 hält beide Rechnungen nebeneinander
fest, damit niemand die Zeile später „vereinfacht".

**Was keine einzelne Kiste sein kann, wird gesagt.** Unter der leeren
Kiste: gesperrt. Ab 60 kg: gesperrt — „So schwer ist keine einzelne
Kiste". Ab 30 kg: eine Rückfrage, aber erlaubt. Die zwei Zahlen sind
Setzungen aus der Erfahrung mit vollen G2-Kisten (meist 12 bis 25 kg); sie
stehen als Konstanten oben in `AusschussMaske.tsx`.

**Die noch nicht eingetragenen Kisten überleben ein zugeklapptes Handy.**
Sie liegen bis zum Eintragen im Browser (`localStorage`, je Arbeit) — was
an der Waage gezählt wurde, soll nicht an einem Bildschirmschoner hängen.

### Farben

„Ausgang kumuliert" und „Davon verkaufsfähig" waren rot und grün. Für
jemanden mit Rot-Grün-Schwäche sind das zwei gleiche Linien. Jetzt grau
und blau (`--text-leise`, `--blau`). Die Regel daraus steht als AB-79:
Keine Aussage hängt allein an Rot gegen Grün.

### Was bewusst nicht gemacht wurde

**Keine Verschriftlichung der Aufnahme.** Ein Dienst, der Sprache zu Text
macht, wäre eine neue Abhängigkeit und ein Weg der Betriebsdaten nach
draussen. Der Betriebsleiter hört zu.

**Die Demo-Saison hat keine Rückmeldungen und kein gemessenes Leeren.**
Beides ist im Prüfblock und in der Kette belegt, nicht in den
Beispieldaten — dieselbe Abweichung wie bei der Sammeldatei in Runde U,
und aus demselben Grund hier notiert.

**Die Frage zu Charge 1625 ist offen.** „Im Lager 937 kg" ist die
Eingangsmasse, die noch keine Lieferung erklärt (Eingang minus
Lieferungen ÷ verkaufsfähigen Anteil), nicht das, was in der Halle liegt.
Ob dort etwa eine Tonne oder drei liegen, entscheidet, ob nur die
Beschriftung oder die Ausbeute falsch ist — die Antwort steht aus.

## Runde W: Löschen, die Marge verständlich, ein Punkt ist ein Punkt (26. September, 0089)

### Arbeiten löschen

Der Betrieb wollte im Büro Arbeiten auswählen und löschen — laufende wie
fertige. Die Datenbank konnte das seit 0013: `auftrag_endgueltig_loeschen`
nimmt die Arbeit samt allem, was an ihr hängt, und räumt auch die zwei
Tabellen auf, die nur `on delete set null` haben (Wägungen, Sortierläufe)
— ohne das blieben Wägungen verwaist zurück und zählten weiter. Neu ist
der Weg dorthin: ein kleiner Knopf, Kreise an den Zeilen, eine Leiste, die
mitzählt, und eine Rückfrage, die die gewählten Arbeiten aufzählt und sagt,
was mitgeht. Danach rechnen die Ergebnisse neu, und das Journal (0072)
behält jede gelöschte Zeile.

### Die verschenkte Marge — erst verstehen, dann zeigen

Die Karte aus 0086 hatte beide Kistensysteme in einer Tabelle und die
Chargen als einen Block darunter. Der Betrieb: „ich komme da überhaupt
nicht raus … da steht wieder 10 Stück pro Kiste und Kaliber 2 … es geht ja
darum, Kiste ab x Kilo". Er hat recht, und der Fehler war ein Verständnis-
fehler, kein Layoutfehler. Also zuerst das Verständnis, so wie es jetzt
über jeder der zwei Tabellen steht:

**Kiste ab x kg.** Der Kunde zahlt die Kiste zu einem Mindestgewicht
(„ab 8 kg"). Alles darüber ist geschenkt. Gemessen an vollen fertigen
Paletten: Netto ÷ Kisten = gewogen je Kiste; minus Soll = zu viel je
Kiste. Wie viele Kürbisse in der Kiste liegen, weiss die Waage nicht — und
es spielt für diesen Verkauf keine Rolle. Ein Kaliber kann an der Wägung
stehen (wenn die Palette eines trägt); es steht dann in der aufgeklappten
Liste, nicht in der Zeile.

**x Stück je Kiste.** Der Kunde zahlt je Kürbis, nach Kaliber („10 Stück
K2, 900–1200 g"). Bezahlt ist die Bandmitte; jedes Gramm darüber ist
geschenkt. Gemessen: Netto ÷ (Kisten × Stück) = gewogen je Stück; minus
Bandmitte.

Zwei Blöcke, klar getrennt, jeder mit seinem Satz. Und statt „die Chargen
dahinter" als ein Block: jede Zeile lässt sich aufklappen und zeigt **nur
ihre** Wägungen — Kaliber 1 angeklickt zeigt alle Einträge mit Kaliber 1,
jede mit Datum, Charge und dem Knopf zur Arbeit. Halbe Paletten stehen in
der Liste, zählen aber nicht (0072); die Liste sagt es an der Zeile. Dafür
trägt `erg_ausgang` seit 0089 die Spalte `voll`.

### Ein Punkt ist ein Punkt

Der Zeiger im Messbild traf bisher die x-Stelle: alles, was am selben Tag
gewogen wurde, stand im Kasten. Bei einer Zeitreihe ist das richtig
(eine Woche, drei Linien); bei einem Messbild aus Punkten ist es falsch —
der Betrieb: „ich möchte einfach nur das Pop-up für den Punkt selber".
`Linien` kennt jetzt zwei Treffer: `spalte` (Zeitreihe) und `punkt`
(Messbild: der eine Punkt unter dem Zeiger, sonst nichts). Ein Klick auf
den Punkt öffnet die Arbeit dahinter als Fenster über der Seite
(`ArbeitFenster`): Palox, gezählte Paletten, Wägungen, Ausschuss, fertige
Paletten, Angaben, Rückmeldung — zum Nachsehen; berichtigt wird auf der
Arbeitsseite, wohin der Knopf führt. Mit dem Finger gibt es kein Ziehen,
dann zählt der Punkt, den das Antippen getroffen hat.

### Eine Verdunstung, die keine ist

„Kaori Kuri … 4,8 % täglich. Kann ja natürlich nicht sein." Richtig — und
bis 0089 zählte die Wägung trotzdem in die Rate der Sorte. `verwendbar`
kannte vier Gründe (schwerer geworden, unverändert, Schimmel sichtbar,
abgebrochen), aber keinen für „zu schnell". Eine Grenze musste her, und sie
ist eine **Einstellung**, keine Zahl im Code: `verdunstung_rate_max_pro_tag`,
Vorgabe 0.01 (1 % je Tag, das Zehnfache dessen, was die Wägungen im Herbst
zeigen). Darüber ist eine Wägung nicht plausibel: Sie zählt nicht in die
Rate, steht grau im Bild, und als Auffälligkeit „Verdunstung" unter
Messungen mit dem Weg zur Korrektur — denn sie ist ein falsches
Zettelgewicht, eine andere Palette oder falsche Kisten, und das gehört
berichtigt, nicht weggeschaut.

Und jede Wägung, die nicht zählt, sagt seit 0089 **warum** (`grund`). Im
Bild stand bisher für alle dasselbe („die Palette wurde nicht leichter"),
auch wenn der Grund ein anderer war.

### Was der Lasttest gefunden hat

Die erste Fassung von `v_verdunstung_messung` kostete bei dreifacher
Saison 1.2 Sekunden mehr als die alte — und `run.sh` hat es gemeldet
(12.8 s statt unter 12). Nicht die Rechnung war teuer, die Form: Bei einer
flachen Sicht setzt der Planer jede Spalte an jeder Verwendungsstelle neu
ein. Die Rate stand in `rate_pro_tag`, in `plausibel` und im Grund; in
jeder davon rechnete `betriebstag()` von vorn, und die ist keine billige
Funktion. Jetzt stehen die Stufen einzeln (`offset 0`): einmal Netto und
Lagertage, einmal die Rate, einmal der Grund. Die Sicht ist damit schneller
als die alte (57 statt 72 ms für `erg_wiegung`, 680 statt 1085 ms für
`mv_koeff_rand`). Die Schwelle im Lasttest blieb, wo sie war.

### Was bewusst nicht gemacht wurde

**Keine Ausreisserstatistik.** Eine Grenze relativ zum Mittel der Sorte
(„dreimal so schnell wie die anderen") wäre datenabhängig — mit zwei
Wägungen einer Sorte gäbe es kein Mittel, und der Ausreisser hielte sich
selbst für normal. Eine feste, sichtbare, änderbare Grenze ist ehrlicher.

**Das Fenster berichtigt nicht.** Es zeigt. Berichtigt wird dort, wo es
schon immer berichtigt wurde — in der Korrektur der Arbeitsseite —, damit
es eine Stelle gibt, an der Änderungen stattfinden, und das Journal sie
alle sieht.

## Runde X: der Betrieb liest seine Auffälligkeiten (26. September, 0090)

Der Betrieb hat die Auffälligkeiten seiner echten Messungen durchgelesen
und Punkt für Punkt gefragt. Die Antworten stehen hier, weil sie zeigen,
wo die App recht hatte, wo sie falsch redete, und wo sie schwieg.

### „0 kg zu klein, 22 kg zu gross, 28 kg Bezugsmasse"

Ja, die Null ist der Fehler aus 0083: Bis dahin zog die Ausschuss-Rechnung
immer die Palette ab und klemmte das negative Ergebnis auf null. Die alten
Zeilen sind nachgerechnet, wo es eindeutig war; wo nicht, steht „Palette
fraglich". Die 28 kg Bezugsmasse sind der andere Teil dieser Auffälligkeit:
Die Bezugsmasse ist das, was diese Arbeit an Eingangsware verarbeitet hat
(die gezählten Paletten mit Zettelgewicht, minus Verdunstung und Faules).
28 kg heisst: An dieser Arbeit hängt fast keine Eingangspalette — dann
sind 22 kg zu gross 79 % davon, und das ist nicht plausibel. Nachzusehen
in der Korrektur: Sind die Paletten dieser Arbeit gezählt?

### „173 kg Faules erfasst, aber keine Kiste gezählt"

Eine Arbeit, bei der nur der Palox abgelesen wurde und sonst nichts —
kein Nenner, also fliesst das Faule nirgends ein. Wie das passieren konnte:
Palox ablesen ist der erste Schritt und Pflicht; alles andere kam nicht.
Seit Runde T sagt die Checkliste, was fehlt; diese Arbeit ist älter. In
der Korrektur lässt sich die Palette nachtragen.

### „Waagenstand sinkt von 229 auf 55"

Genau der Fall, für den es seit 0084 den Knopf „Palox leeren" gibt: vor
dem Leeren ablesen, leeren, die leere Box ablesen — dann bleibt die Menge
bekannt. Der Rat der Auffälligkeit nennt den Knopf jetzt.

### „Palette mit 235 kg vom Zettel, 18 Kisten — gerechnet mit der mittleren Tara"

Der Betrieb hat recht: Wenn die Kisten dastehen, ist die eigene Tara
besser als die mittlere. `v_auftrag_palette_masse` rechnet seit 0090 in
dieser Reihenfolge: gewogen → im Wareneingang gefunden → Zettel minus die
gezählten Kisten und ihre Tara (neu) → Zettel minus mittlere Tara → Tages-
mittel → Chargenmittel. Und die Auffälligkeit sagt, welcher Fall gilt.

Dass die Palette im Wareneingang fehlt, ist die eigentliche Frage — sie
kommt mehrmals vor („wir haben nirgends diesen Eingang"). Meist steht die
Palette im Erntejournal unter einer anderen Chargennummer, oder die Zeile
fehlt dort. Seit Runde X zieht sich das Journal von selbst nach (unten);
was dann noch fehlt, fehlt im Journal.

### „Was ist 218 bei Wägung?"

Die Datenbanknummer der verknüpften Wägung. Ein Fehler der Anzeige, kein
Fehler der Daten: Die Korrektur zeigte das Feld `wiegung_id` roh. Jetzt
steht dort das Gewicht (Zettel → jetzt) und daneben das gerechnete Netto
der Palette mit seiner Quelle. Und die Korrektur beginnt mit einem Kopf:
welche Tätigkeit, welche Charge, wann, wer — und einer Tabelle „Diese
Arbeit braucht / Da ist / fehlt", damit man sieht, was fehlt, ohne es aus
den Blöcken zu erraten.

### „Kistengewicht unbekannt — wird das rückwirkend korrigiert?"

Ja, von selbst. Die Menge eines Waschgangs aus Kisten ist Kisten × mittleres
Kistengewicht dieses Bandes, und das Kistengewicht kommt aus den Sortier-
läufen, bei denen die gefüllten Kisten je Band gezählt werden. Sobald ein
Sortierlauf dieses Band zählt, hat der Waschgang seine Masse — rückwirkend,
denn es ist eine Sicht, keine gespeicherte Zahl. Es ist eine Warteschlange
ohne Knopf. Eine Bedingung: Das Band muss dasselbe sein. Wäscht jemand
„700–900 g" als eigenes Kaliber, das beim Sortieren nie so gezählt wird,
bleibt die Meldung stehen — dann in der Korrektur das passende Band wählen.

### „160 kg mehr ausgeliefert als Eingang — aber der Ausgang ist kleiner"

Der Betrieb hat recht, der Satz war falsch. Gemeint war: Die Lieferungen
(6'348 kg) brauchen nach der gerechneten Ausbeute (verkaufsfähiger Anteil)
mehr Eingang, als erfasst ist (9'549 kg) — 160 kg mehr. Das ist kein
„zu viel geliefert", sondern ein „die Rechnung erwartet aus diesem Eingang
weniger Verkauf". Jetzt steht genau das da, mit der Ausbeute in Prozent.
Und der Rat nennt die dritte Möglichkeit, die er bisher verschwieg: Die
Charge ist besser als das Modell — dann ist „Im Lager" für sie zu klein
gerechnet (dieselbe Frage wie die 937 kg aus Runde V).

### „Wird das Erntejournal jedes Mal neu geholt?"

Bisher nicht — nur auf Knopfdruck unter Stammdaten. Jetzt holt das
Dashboard die veröffentlichte CSV beim Öffnen (höchstens alle zehn
Minuten je Gerät) und übernimmt, was neu ist. Nur Neues: Eine Palette,
die schon da ist, wird nicht angefasst — was der Betriebsleiter berichtigt
hat, bleibt berichtigt. Gab es Neues, rechnen die Ergebnisse neu, und die
Karte sagt, wie viele. Der volle Abgleich mit Vorschau bleibt unter
Stammdaten.

### Was bewusst nicht gemacht wurde

**Die Auffälligkeiten sind keine Tabelle geworden.** Der Betrieb liest sie
Satz für Satz; eine Zeile je Arbeit mit der Tätigkeit davor reicht.

**Kein automatisches Überschreiben aus dem Journal.** Der Abgleich legt
an, was neu ist, und lässt stehen, was da ist — auch wenn das Journal
inzwischen anders lautet. Sonst überschriebe ein Tippfehler im Sheet eine
Berichtigung in der App, ohne dass jemand es sähe.
