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

`v_sortier_kuerbis` expandiert die Zeilen per `generate_series` wieder, falls
doch einmal pro Kürbis gerechnet werden soll.

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

- `marge_messung.art = 'nebenkanal'`: Der Enum-Wert existiert, aber die
  Nebenkanal-Mengen kommen aus der Sortier-CSV bzw. aus
  `ausschuss_messung('zu_gross')`. Eine hier erfasste Zeile würde spurlos
  verschwinden — sie taucht deshalb in `v_plausibilitaet` als „Nicht
  ausgewertet" auf. Die App schreibt sie nie.
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

`v_koeff_ueberfuellung` liest beide Quellen: die neuen Palettenwägungen und
ältere `marge_messung`-Zeilen. So verliert kein bereits erfasster Wert seine
Wirkung.

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
