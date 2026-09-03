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

Die Prüfung nach `docs/PROMPT_PRUEFUNG.md` ging jede Zahl im Dashboard
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
