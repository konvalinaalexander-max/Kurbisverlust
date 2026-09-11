# Weitere Drehbücher — angerissen, von der Runde auszuschreiben

Jedes nach dem Muster in FORMAT.md, mit SQL-Szenen für den Spieler. Die
Reihenfolge ist die Reihenfolge der Wichtigkeit.

## 03 Die doppelte Lieferung
Der Warenausgang-Import liefert dieselbe Zeile zweimal (gleiche Position,
neuer Lauf). Erwartung: `lieferung_import` mit extern_id hält die zweite
Zeile fern; kommt sie trotzdem (von Hand), zeigt die Kaskade
`ueberzaehlung_kg > 0` und die Charge steht in den Auffälligkeiten. Prüfung:
K1 hält in beiden Fällen (gegenprobe/orakel/bilanz.ts).

## 04 Umgestapelt — eine Eingangspalette wird geteilt
Eine Palette mit 30 Kisten wird im Lager auf zwei halbe verteilt (Platz).
Beide tragen den alten Zettel. Bei der Lagerkontrolle wiegt Tomasz eine
halbe: 15 Kisten, brutto 260. Erwartung: Netto aus 15 Kisten, Vergleich mit
dem halben Zettel-Netto ist **nicht** möglich (Zettel sagt 30 Kisten) — die
Maske muss fragen „ganze Palette vom Zettel?" oder die Wägung als
Schimmel-Punkt ohne Rate speichern. Heute: Rate aus 260 gegen 500 → −50 %,
`verwendbar = false` wegen „schwerer geworden"? Nein — leichter. Die Rate
wäre 3.4 % je Tag und **würde die Sorte vergiften**, wenn die Deckelung 0.05
nicht griffe. Prüfung: Rate ≤ 0.05 in `v_koeff_verdunstung`, und die Wägung
in `v_plausibilitaet` („Palette viel leichter als der Zettel").

## 05 Nachts um halb eins
Wägung 00:30 Ortszeit am Tag nach dem Eingang. Erwartung: 1 Lagertag
(betriebstag), nicht 0 (UTC) — und **überall**: `v_verdunstung_messung` ist
seit 0067 richtig, `mv_auftrag_masse` rechnet Lagertage aber noch mit
`a.start_ts::date` (gefunden beim Abzug der Formeln, Runde N Vorbereitung).
Prüfung: eine Arbeit mit start_ts 00:30 Ortszeit hat dieselben Lagertage wie
eine um 08:00 desselben Tages.

## 06 Der Zähler mit Handschuhen
Kein SQL. Bildschirm-Prüfstand: Handy 390 px, jedes Bedienelement ≥ 44 px
(I8), der Zähler 84 px, „Rückgängig" erreichbar ohne Zielen, das Datumsfeld
ohne Tastatur bedienbar. Erwartung dokumentiert in docs/UI-KONZEPT.md.

## 07 Die Saison ohne Messung
Eine Sorte mit Eingang und Lieferungen, aber ohne eine einzige Wägung und
ohne Palox-Ablesung (Lekor in der bösen Saison, B11). Erwartung: Kaskade
rechnet mit r = 0, f aus der Treppe der anderen Sorten (oder 0), alle
`*_bekannt = false`; der Überblick sagt „ohne Messung — nur Bilanz"; kein
Diagramm ist leer ohne Satz; Sortenvergleich zeigt sie mit „keine Messung".

## 08 Der Palox wird mittags geleert
Sortieren über den ganzen Tag, Palox um 12:00 voll → geleert (palox_geleert)
→ am Abend zweite Ablesung. Erwartung: Faules = (Stand mittags − Tara) +
(Stand abends − Tara), nicht nur der Abendstand. Prüfung: `v_schimmel_menge`.

## 09 Zwei Chargen in einer Arbeit
Der Vorarbeiter sortiert Reste zweier Chargen zusammen und sagt am Ende „nicht
alles aus einer Charge". Erwartung: Punkt mit Quelle `verarbeitung_gemischt`,
**nicht** in der Kurve, aber in der Chargen-Tabelle sichtbar mit Vermerk.

## 10 Der Fax-Tag
Etikettieren ohne Waschgang: Paletten gesamt, Faules kistenweise, Tage seit
dem Waschen. Erwartung: `a_fax` je Sorte, nie in die Verderbskurve
(`v_fax_beobachtung`), Masse aus Paletten × Palettennetto der Sorte.

## 11 Der Betriebsleiter tippt selbst — Korrektur mit Folgen
Er ändert ein Zettel-Brutto einer gewogenen Palette. Erwartung: Netto damals
ändert sich, Rate ändert sich, `auswertung_stand.geaendert_ts` springt, der
Überblick sagt „veraltet — neu rechnen"; nichts Abgeleitetes wird gespeichert.
