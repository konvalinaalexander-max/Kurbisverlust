# Die Warenausgangsdateien: was drinsteht

Der Betrieb führt seine Lieferscheine in Perigon und zieht dort die Auswertung
**„Abgleich Rückverfolgbarkeit, seit Anfang Jahr, Gemüse"** als Excel-Datei.
Diese Datei soll die App einlesen — immer die ganze, nie nur die Änderungen.

Diese Seite hält fest, was tatsächlich in den Dateien steht. Alle Zahlen sind
an den drei Dateien vom 6. September 2026 gemessen, nicht geschätzt. Die
Dateien selbst liegen **nicht** im Repository: sie enthalten Kundennamen und
Preise. Für die Tests gibt es eine erfundene Datei gleicher Form
(`test/daten/warenausgang-probe.xlsx`, gebaut von `probe_bauen.py`).

## Es sind zwei Firmen, nicht eine

| Datei | Zeilen | Zeitraum | Kürbiszeilen | Kunden |
|---|---|---|---|---|
| **Imhofbio** | 5 649 | 01.01.2024 – 06.09.2026 | 5 649 (alle) | Coop, Migros, RVZ, Aclens |
| **Imhof BioProdukte** | 6 496 | 03.01.2024 – 05.09.2026 | 914 | Rathgeb, Bio Partner, Derrer, Hofladen |

Die eine Firma handelt fast nur Kürbis und beliefert den Detailhandel, die
andere führt das ganze Gemüsesortiment (137 Artikelkennungen: Karotten, Salat,
Tomaten, Gurken …) und beliefert den Grosshandel. **Beide zählen in dieselbe
Bilanz**, aber ihre Positionsnummern sind je Firma vergeben: `AufPosId` läuft in
der einen bei 3.5 Millionen, in der anderen bei 123 000. Ein Import muss die
Herkunft deshalb mitführen — sonst wären es zufällig dieselben Schlüssel.

Doppelt gezählt wird dabei nichts: In der Saison 25/26 gingen ganze 0.7 t von
der einen Firma an die andere (Journal `L`, Kunde „Imhof"). Die beiden liefern
an verschiedene Kunden.

## Der Aufbau: Position und Chargenzeile

Die 32 Spalten beschreiben zwei Ebenen, und das ist die wichtigste Einsicht
für den Import:

```
Position  (AufPosId)      ein Artikel auf einem Lieferschein
                          AuftragsArtikelMenge × GewichtProArtikel = gelieferte Masse
  ├─ Chargenzeile         AuftragsChargeManuell + AufPosBatchQuantity Charge
  └─ Chargenzeile         welcher Teil der Position aus welcher Charge kam
```

Eine Position mit drei Chargen steht **dreimal** in der Datei, jedes Mal mit
derselben `AuftragsArtikelMenge`. Wer die Zeilen einfach summiert, zählt sie
dreifach. Gemessen an den echten Dateien:

| Grösse | Imhofbio | BioProdukte (Kürbis) |
|---|---|---|
| Zeilen | 5 649 | 914 |
| Positionen | 5 538 | 875 |
| Positionsmasse (je Position einmal) | 649.6 t | 315.8 t |
| davon einer Charge zugeordnet | 632.5 t | 228.3 t |
| ohne Chargenbezug | 17.1 t | 87.6 t |

`TotalGewicht` ist immer `AuftragsArtikelMenge × GewichtProArtikel` — geprüft an
5 320 Zeilen, null Abweichungen. `GewichtProArtikel` fehlt in keiner Zeile; bei
Einheit `kg` steht dort 1.

## Was eine Zeile eindeutig macht

`AufPosId` allein genügt nicht: 102 Positionen haben mehrere Chargenzeilen.
`AufPosId + Charge` genügt fast — in den echten Dateien gibt es 13 Fälle, in
denen dieselbe Position dieselbe Charge zweimal nennt (teils Wort für Wort
identisch, teils mit verschiedenen Mengen). Der Schlüssel ist deshalb

```
Quelle + AufPosId + Charge + Laufnummer
```

wobei die Laufnummer beim Lesen der Datei vergeben wird (erste, zweite Zeile
mit demselben Rest). Dazu ein **Fingerabdruck** über die inhaltlichen Felder:
gleicher Schlüssel und gleicher Fingerabdruck heisst „schon gesehen"; gleicher
Schlüssel, anderer Fingerabdruck heisst „im Perigon korrigiert".

## Die Chargennummer — nur in einer der beiden Firmen

`AuftragsChargeManuell` enthält zweierlei:

- **vierstellige Nummern** (1612, 1613, 1615, 1624, 1626 …): das sind unsere
  eigenen Chargennummern aus der Registry. Sie stehen nur in der Datei der
  Firma *BioProdukte* (373 Zeilen, 44 Nummern).
- **sechsstellige Nummern** (196122, 198951 …): Chargen aus dem Perigon selbst.
  Die Datei der Firma *Imhofbio* führt fast nur solche — von 5 649 Zeilen trägt
  genau eine eine vierstellige Nummer.

Alle in der laufenden Saison genannten vierstelligen Nummern gibt es in der
Registry: 1612 ✓ 1613 ✓ 1614 ✓ 1615 ✓ 1617 ✓ 1619 ✓ 1623 ✓ 1624 ✓ 1625 ✓ 1626 ✓.
Die Nummern der letzten Saison (1170 – 1252) kennt die Registry nicht — sie
führt nur die Saison 2026.

Gegenprobe, dass die Zuordnung stimmt: Der Schlag der Charge und der Produzent
der Zeile passen zusammen.

| Charge trägt Schlag | Zeile nennt Produzent |
|---|---|
| Slowgrow Uster | Imhof (19×) |
| Gossau Eberhard | Imhof (8×) |
| Agasul Rüegg | Peter Rüegg (13×) |

**Damit ist der Chargenbezug für die eine Firma da und für die andere nicht.**
Was die App aus den sechsstelligen Nummern macht, ist eine offene Frage (unten).

## Welche Zeilen sind Kürbis?

Die Regel „`kürb` in Artikelkennung oder Artikelname" trifft in der
Gemüse-Datei 920 von 6 496 Zeilen. Sie ist gut, aber nicht fehlerfrei:

- Sie fängt auch `Bio-Kürbis roter Knirps` unter der Kennung `kni` — richtig.
- Sie fängt aber auch `Kürbisverrechnung 2025`, `Arbeit Kürbisernte` und
  `Kürbis Mix` unter `div` — Buchungen und Arbeitsleistungen, keine Ware.

Deshalb: Die Regel schlägt vor, der Betriebsleiter bestätigt einmal je Artikel.
Ab dann ist es eine Beobachtung und keine Vermutung mehr. Zu bestätigen sind
rund 57 Artikel (25 in der einen, 32 in der anderen Datei).

Die Sorte lässt sich mitliefern, und zwar **aus den Daten selbst**: Wo eine
Zeile eine eigene Chargennummer trägt, ist die Sorte der Charge die Sorte des
Artikels. Beobachtete Paare aus den echten Dateien:

| Verkaufsartikel | Sorte laut Charge |
|---|---|
| Bio-Kürbis Butternut Demeter | Tiana (8×) |
| Bio-Kürbis Butterkin Knospe | Butterkin (6×) |
| Bio-Kürbis Butternut Knospe | Tiana (5×), Mieluna (1×) |
| Bio-Kürbis roter Knirps Demeter | Kaori Kuri (8×), Ker Madec (1×) |
| Bio-Kürbis Mandarin Demeter | Orangita (1×) |

Ein Verkaufsartikel kann also aus mehreren Sorten kommen — er ist ein
*Verkaufskaliber*, keine Sorte. Für Lieferungen mit Chargennummer spielt das
keine Rolle (die Charge sagt die Sorte); nur für die Zeilen ohne Chargenbezug
braucht es die Zuordnung, und sie ist dort eine Näherung. Das gehört so
ausgewiesen.

## Was sonst noch auffiel

**Journale.** `A` (Auftrag) trägt praktisch die ganze Masse. `G` (Gutschrift),
`E` und `L` (intern) tragen zusammen 0 kg zugeordnete Menge, aber teilweise
Erlös — Buchungen ohne Warenbewegung.

**Rücknahmen.** Zwei Zeilen in zweieinhalb Jahren haben eine negative Menge
(−3 590 kg am 09.12.2025, −344 kg am 19.09.2024). Sie dürfen nicht einfach
wegfallen: `lieferung.kg` lässt nur positive Mengen zu, also muss der Import
sie getrennt melden. Ohne diese Behandlung läge die Bilanz um 3.9 t daneben,
ohne dass es irgendwo aufgefallen wäre.

**Kandidatenzeilen ohne Menge.** 335 Zeilen in der einen und 481 in der anderen
Datei nennen eine Charge mit Batchmenge 0 — die Rückverfolgbarkeit zeigt dort
mögliche Chargen, ohne dass etwas zugeteilt wäre. Sie tragen nichts bei.

**Nicht vollständig zugeordnet.** 312 Positionen der einen und 493 der anderen
Datei sind nur teilweise einer Charge zugeordnet, 16 bzw. 11 sind *über*
zugeordnet (mehr Chargenmenge als Positionsmenge — die doppelten Zeilen von
oben). Der Import muss deshalb je Position auf die Positionsmasse deckeln und
den Rest als „ohne Chargenbezug" führen.

**Gebinde.** Die Bezeichnungen (`IFCO Gemüse 6410`, `IFCO Gemüse BLL 6416`,
`U-Gebinde`, `G2`, `G1`, `Paloxen`) überschneiden sich teilweise mit unserer
Gebinde-Tabelle, teilweise nicht. Für die Masse spielt das keine Rolle: die
Datei liefert Kilo, nicht Brutto.

**Kopfzeilen.** Eine der Dateien schreibt `AuftragsArtikelmengeSoll`, die
andere `AuftragsArtikelMengeSoll`. Der Leser vergleicht deshalb ohne Gross- und
Kleinschreibung.

## Die Antworten des Betriebs (7. September)

Alle vier Fragen sind beantwortet; die Planungsdatei hat die erste gleich
mit erledigt.

1. **Die sechsstelligen Nummern sind unsere Chargen.** Die Datei
   „Kürbisplanung und Erträge 26", Blatt „2026 Flächeneint. ink Reprt.Da.",
   führt je Schlag und Sorte beide Nummern: `Charge Bioprodukte` (vierstellig,
   1598–1651) und `Charge BioBioAG` (sechsstellig, 198876–198976). Gegen die
   AG-Datei geprüft: 232 von 236 Kürbiszeilen seit Juli 2026 tragen eine Nummer
   aus dieser Liste, keine einzige unbekannte. Die Nummer steht jetzt an der
   Charge (`charge.perigon_nr`, 0051), der Import löst sie über
   `chargeAufloeser` auf. Eine Nummer ist doppelt (198976: 1649 Butterkin und
   1650 Tiana, beide Rümlang Sauter) — dort entscheidet der Artikel
   („Butterkin" ↔ „Butternut"), sonst bleibt die Zeile ohne Bezug.
2. **Nur ab Sommer 2026.** Die Vorjahre werden nicht eingelesen.
3. **Beide Firmen sind eine.** Buchhalterisch getrennt, aber dieselben Felder,
   dieselbe Halle — alles, was in den Dateien steht, lag vorher bei uns.
4. **Interne Umbuchungen weglassen.** Rund eine Tonne je Saison (Journal `L`,
   Kunde „Imhof") — nicht relevant. Der Import überspringt Journal `L`.

## Was der Betrieb noch entscheiden muss (beantwortet, zur Nachlese)

1. **Die sechsstelligen Chargennummern.** Für die Firma, die an Coop und Migros
   liefert, gibt es keinen Bezug zu unseren Chargen. Drei Möglichkeiten:
   (a) diese Lieferungen zählen ohne Chargenbezug in die Bilanz — einfach,
   ehrlich, aber die Chargenrechnung sieht sie nie; (b) der Betrieb pflegt eine
   Übersetzungstabelle Perigon-Charge → eigene Charge; (c) im Perigon wird
   künftig die eigene Chargennummer mitgeführt. **Vorschlag: (a) jetzt, (c) auf
   Dauer** — (b) wäre Handarbeit für hunderte Nummern je Saison.
2. **Wie weit zurück?** Die Dateien reichen bis Januar 2024, die App rechnet
   die Saison 2026. Soll der Import alles einlesen (Vorjahre als Bestand) oder
   erst ab dem Erfassungsbeginn? **Vorschlag: alles einlesen, aber nur die
   laufende Saison in die Bilanz** — die Vorjahre sind dann für den
   Sortenvergleich da.
3. **Zählen die Zukäufe anderer Produzenten mit?** Die eine Firma verkauft
   Kürbis von acht Produzenten (Imhof 54 %, Daniel Böhler 13 %, Klaus Böhler
   11 %, Ball 11 % …). Unsere Charge-Registry führt Schläge, die genauso heissen
   („Daniel Böhler", „Klaus Böhler", „Andi Ball") — offenbar lagert deren Ware
   bei uns. Falls es Ware gibt, die **nie** in unserem Lager war, gehört sie
   nicht in die Verlustrechnung. **Frage an den Betrieb:** Liegt alles, was in
   diesen Dateien steht, vorher in unserer Halle?
4. **Interne Umbuchungen** (Journal `L`, Kunde „Imhof", 60 Zeilen, ~1 t): Ware,
   die von der einen Firma in die andere geht. Zählt als Ausgang oder nicht?
   **Vorschlag: als eigenes Ziel „intern" führen** und in der Bilanz nicht als
   Verkauf zählen.
