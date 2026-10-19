# Herleitung — woher jede gerechnete Zahl ihre Eingaben nimmt

Der Betrieb: „Wenn du eine Zahl X rechnen willst, welche Zahlen A, B, C
und D brauchst du, und wo genau holst du die her? Und wenn du C nicht
hast — wie errätst du dir das C? Macht das Sinn?"

Diese Datei antwortet je Grösse: die Eingaben, ihre Quelle, die
Reihenfolge der Ersatzwege, und ob der Ersatz ehrlich ist. Die Regel
darüber: **Leer ist nicht null.** Ein Ersatz ist erlaubt, wenn er aus
Messungen derselben Art stammt und die Zahl sagt, dass sie ein Ersatz ist
(`masse_quelle`, `basis`, `sortiertag_quelle`, `grund`). Wo kein Ersatz
aus Messungen möglich ist, bleibt die Grösse unbekannt und steht als
Auffälligkeit da. Geprüft am 26. September; wer eine Kette ändert, ändert
diese Datei mit.

Seit 0109 steht die Formel von `v_auftrag_masse`, `v_koeff_gebinde`,
`v_schimmel_punkte` und `v_koeff_kaliber_geschaetzt` in `<sicht>_formel`;
die Sicht liest sie über eine Planungsgrenze (`<sicht>_zaun()`, AB-125).
An den Ketten unten ändert das nichts — nur, wo man die Formel ändert.

## 1. Netto einer Eingangspalette (`v_palette`)

**Braucht:** Brutto vom Zettel (Erntejournal), Kisten, Gebindeart → Tara je
Kiste und Palette (`gebinde`).
**Rechnung:** Netto = Brutto − Kisten × Kistentara − Palettentara.
**Fehlt etwas:** Netto bleibt **null**. Die Charge rechnet ihren Eingang mit
dem Mittel der Paletten, die ein Netto haben, mal Anzahl aller Paletten
(`v_charge_rueckgrat`); das Dashboard sagt „n Paletten ohne Nettogewicht —
für sie rechnet der Eingang mit dem Mittel der übrigen".
**Gebinde ohne Palette (0116):** Holz-Palox 45 kg, Plastik-Palox 35 kg Tara
— eine Palox ist ein Gebinde, eine „Kiste", keine Palette darunter. Bis
0116 hatte „Holz Palox" keine Tara: ihr Netto blieb null, und die Charge
zählte sie mit dem Mittel ihrer übrigen Paletten (auf der Kopie der
Betriebsdaten 18 Holz-Palox, jetzt 4.8 t statt 7.4 t; Eingang 656.5 t →
653.9 t).
**Urteil:** ehrlich. Ein Ersatz aus derselben Charge, sichtbar benannt.

## 2. Die Masse einer Arbeit — der Nenner (`v_auftrag_masse`)

Je gezählter Palette (`v_auftrag_palette_masse`), in dieser Reihenfolge:

| Quelle | Wann | Was |
|---|---|---|
| `gewogen` | die Palette wurde in dieser Arbeit gewogen | ihr eigenes Netto (Zettel-Brutto minus ihre Tara) |
| `zettel` | Zettelgewicht und -datum finden die Palette im Wareneingang | das Netto dieser Palette |
| `zettel-kisten` (0090) | kein Treffer, aber Kisten und Gebinde gezählt | Zettel − Kisten × Kistentara − Palette |
| `zettel-kisten-charge` (0116) | kein Treffer, Kisten gezählt, das Gebinde hat keine Tara | Zettel − Kisten × Tara je Kiste der Charge |
| `zettel-charge-tara` | kein Treffer, keine Kisten | Zettel − mittlere Tara der Charge |
| `palette` | die Palette ist über ihre Nummer verknüpft | ihr Netto |
| `datum-je-kiste` (0116) | kein Gewicht, Datum und Kisten | Netto je Kiste dieses Eingangstags × Kisten |
| `datum-mittel` | nur das Datum ist da | Mittel der Paletten dieses Eingangstags |
| `charge-je-kiste` (0116) | kein Gewicht, kein Datum, Kisten | Netto je Kiste der Charge × Kisten |
| `charge-mittel` | nichts als die Charge | Mittel der Charge |

Seit 0116 gilt: Wo Kisten gezählt sind, wird je Kiste gerechnet — nie ein
Mittel ganzer Paletten für eine halbe Palette oder eine einzelne Palox (der
Betrieb: „schau, dass du das auf die Kiste anpasst"; vorher rechneten die
Holz-Palox der Charge 1638 mit 79 kg Tara, der einer G2-Palette mit 36
Kisten).

**Beim reinen Waschen** (0104): die am Anfang der Strasse gewogenen Paletten
— Brutto − Kisten × Kistentara − Palettentara (`v_auftrag_wasch_gewogen`,
`gewogen_strasse`); sind nicht alle gewogen, rechnen die übrigen mit dem
Mittel je Kiste der gewogenen (`gewogen_strasse_teils`). Erst danach die
Ersätze, für Arbeiten von vor dem 29. September:

Dann je Arbeit: die Summe der gezählten Paletten → sonst **fertige Paletten**
(Waschen: gezählte fertige Paletten × Mittel der gewogenen **vollen**; eine
reicht, drei sind der Rat — nicht volle zählen hier nicht, in der Marge
aber je Kiste, 0097) →
sonst **Kaliber-Paletten × Kistengewicht des Bandes** (Waschen aus Kisten,
Abschnitt 4) → sonst **gezählte Kisten je Kaliber × Kistengewicht** (alter
Weg) → beim Fax **Paletten gesamt × Palettenmasse der Sorte**. Die Quelle
steht als `masse_quelle` an jeder Arbeit (Chargen-Seite, Korrektur).
**Urteil:** ehrlich; `charge-mittel` ist der schwächste Ersatz — er gilt nur,
wenn jemand eine Palette ohne Zettel gezählt hat, und das sagt die
Auffälligkeit „Zettelgewicht" seit 0090 ausdrücklich.

## 3. Lagertage einer Arbeit

**Gemessen** aus den Eingangsdaten der gezählten Paletten. **Beim Waschen aus
Kisten** (keine Eingangspaletten): das Sortiermittel der Charge
(`mv_sortier_eingang`), sonst das Mittel der Eingangsdaten der Charge,
nach Netto gewichtet (`eingangsdatum_mittel`). Die Quelle steht daneben
(`lagertage_quelle`: gemessen · sortiermittel · chargenmittel).
**Urteil:** ehrlich; das Chargenmittel ist grob, aber richtig gewichtet.

## 4. Das Kistengewicht je Band (`v_koeff_gebinde`) — **war gebrochen, seit 0092 repariert**

**Braucht:** je Sorte und Kaliberband: kg je gefüllter Kiste.
**Bis 0092:** nur aus Sortierläufen, bei denen die gefüllten Kisten je Band
*gezählt* wurden (Kisten aus `auftrag_gebinde`, Masse aus der CSV). Seit
Runde Q zählt das niemand mehr — die Quelle war versiegt, und jeder
Waschgang ohne gewogene fertige Paletten blieb „Kistengewicht unbekannt".
Der Rat der Auffälligkeit („beim nächsten Sortierlauf zählen") war nicht
befolgbar. Das ist der Fehler, den der Betrieb „fast zehnmal" sah.
**Seit 0092:** dazu aus Wasch-Arbeiten, die ihre Kaliber-Paletten gezählt
(Kisten hinein) und ihre fertigen Paletten gewogen haben (Masse heraus):
Masse heraus ÷ Kisten hinein. Eine solche Arbeit je Sorte und Band genügt;
sie gilt rückwirkend, denn es ist eine Sicht. Das Faule und der Ausschuss
des Waschgangs fehlen in der Masse heraus — das Kistengewicht ist darum
eher etwas zu klein, nie zu gross.
**Seit 0104** dazu: Masse hinein ÷ Kisten hinein aus den am Anfang der
Waschstrasse gewogenen Paletten — direkter als Masse heraus, ohne den Abzug
des Faulen.
**Fehlt alles:** unbekannt, Auffälligkeit „Kistengewicht" mit dem Rat, beim
nächsten Waschgang zu wiegen; sie schweigt, sobald die Paletten der Arbeit
selbst gewogen sind.
**Urteil:** jetzt ehrlich und erreichbar.

## 5. Verdunstungsrate je Sorte (`v_koeff_verdunstung`)

**Braucht:** Wägungen derselben Palette zweimal (`verdunstung_wiegung`):
Netto damals, Netto jetzt, Lagertage → Rate je Tag = 1 − (jetzt/damals)^(1/Tage).
**Zählt nur:** `verwendbar` — nicht schwerer geworden, nicht unverändert,
kein Schimmel sichtbar, Arbeit nicht abgebrochen, und seit 0089 unter der
Grenze `verdunstung_rate_max_pro_tag` (Vorgabe 1 % je Tag), und seit 0116
nicht von Hand ausgeschlossen (`messung_ausschluss`, Kästchen „Diese
Messung benutzen" im Fenster der Messung, nur der Betriebsleiter). Jede
Wägung, die nicht zählt, sagt warum (`grund`); eine ausgeschlossene bleibt
im Bild.
**Zusammenfassen (seit 0111):** je Sorte das nach Masse gewichtete Mittel
ihrer eigenen verwendbaren Wägungen, ab drei (`anteil_mindest_messungen()`);
darunter das Mittel aller Sorten. Kein Zug zum Gesamtwert mehr (bis 0110:
empirisches Bayes — niemand konnte es nachrechnen). Die `basis` sagt es:
„Wiegungen dieser Sorte" · „Wiegungen aller Sorten (eigene: n, gilt ab 3)" ·
„keine Wiegung vorhanden".
**Gegenprobe, nicht Teil der Rate:** zwei Sortierläufe derselben Charge
(`v_lauf_vergleich`, AB-113) — Median und Abstand je Tag; es sind andere
Kürbisse, darum zählen sie nicht in die Rate.
**Fehlt alles:** unbekannt, nicht null — die Kaskade rechnet dann ohne
Verdunstung und das Dashboard sagt „nicht gemessen".
**Urteil:** ehrlich; die Grenze (0089) war die Lücke.

## 6. Zu klein, zu gross (seit 0116 aus der Sortierdatei), anderer Kanal

**Zuerst die Sortierdatei (0116, `mv_kaliber_quelle`, `kaliber_anteil`).**
Der Betrieb: „primär solltest du die Information aus den Sortier-CSVs
nehmen … beim Waschen und Sortieren werden viele Kürbisse dabei sein, die
unter das Limit fallen oder darüber, und sie werden von Auge nicht erkannt."
**Braucht:** die gewogenen Kürbisse jedes Sortierlaufs (`sortier_gewicht`),
den Sortiertag, das Alter der Ware beim Sortieren, die Verdunstungsrate der
Sorte (Abschnitt 5) und die Grenzen der gültigen Fassung der Sorte
(`v_kaliber_fassung`: unter der ersten Bandgrenze zu klein, über der
letzten zu gross).
**Das Alter beim Sortieren (`v_kaliber_lauf`):** aus den Zetteldaten der
Arbeit, zu der die Datei gehört, nach Netto gewichtet (eine Palette ohne
Netto zählt 1) — `alter_quelle = zettel`; ist die Datei keiner Arbeit
zugeordnet, aus den Paletten der Charge, die am Sortiertag schon da waren,
nach Netto (sonst Brutto) gewichtet — `eingang`. Ohne Sortiertag oder ohne
eine Palette davor hat der Lauf kein Alter und zählt nicht.
**Rückrechnung (`mv_kaliber_eingang`):** jeder Kürbis g0 = g / (1 − r)^Alter
(r = Verdunstung der Sorte je Tag, auf 0–5 % begrenzt; ist nirgends eine
gemessen, 0 — wie die Kaskade, die dann ohne Verdunstung rechnet). Das
ergibt je Charge und je Sorte die Gewichtsverteilung beim Eingang.
**Je Portion der Kaskade** (Alter a, für Prognose und Verlauf das Alter am
Stichtag) wird sie um q = (1 − r)^a geschrumpft: zu klein ist der
Massenanteil mit g0 < lo / q, zu gross der mit g0 > hi / q. Junge Ware hat
mehr zu gross, alte mehr zu klein — und was zu gross war, kann in die
Bänder hineintrocknen und verkaufsfähig werden. In der Prognose zählt das
in „Wasser": Es ist (1 − f) · (Basis jetzt · Anteil jetzt − Basis später ·
Anteil später) und kann deshalb negativ sein, wenn mehr Übergrösse in die
Bänder schrumpft, als Wasser verloren geht; die Summe aus Wasser und
Fäulnis bleibt genau der Verlust an Verkaufsfähigem.
**Ersatzweg, in dieser Reihenfolge:** die Läufe der Charge → die Läufe der
Sorte (`ebene`, `basis` sagen es) → der gemessene Anteil der Sorte wie bis
0115: Sortierläufe und Handmessungen (gewogene Kisten zu klein / zu gross
beim Waschen, 0088) gleich gezählt, das Mittel der Sorte ab drei eigenen
Messungen, sonst aller Sorten (`v_koeff_ausschuss`, `v_koeff_nebenkanal`).
Die Handmessungen gelten also nur noch, wo die Sorte keine Sortierdatei hat.
Auf der Kopie der Betriebsdaten (12. Oktober): 12 Läufe vom 17.8. bis
10.9., keiner einer Arbeit zugeordnet (Alter aus dem Eingang, im Mittel 19
Tage); 11 Chargen rechnen mit eigenen Läufen, 13 mit denen der Sorte, die
übrigen mit dem gemessenen Anteil. Zu klein und zu gross der liegenden
Ware 20.7 t → 16.5 t, verkaufsfähig 308.9 t → 312.2 t (mit der Tara der
Holz-Palox, Abschnitt 1).
**Fehlt alles:** unbekannt.
**Fehlt eine Art** (nur „zu gross" gewogen, „zu klein" übersprungen): diese
Art ist unbekannt, nicht 0; die gemessene zählt; keine Auffälligkeit (0097).
**Wohin:** ins Haus, nicht in den Ausgang (0101) — aussortiert steht es in
Paloxen, bis ein Lieferschein es holt; das Buch „marge" (an die Tiere, in
den Nebenkanal) zählt erst dann, und der Befund der Bilanz vergleicht beides.
**Urteil:** ehrlich. Die Rückrechnung nimmt an, dass alle Kürbisse einer
Sorte gleich schnell trocknen; ein eigenes Unsicherheitsband hat der
Anteil aus der Sortierdatei nicht (Runde AS, „Was bewusst nicht gemacht
wurde").

## 7. Faules im Lager — die Stationswerte (`v_palox_erwartung`, `v_charge_weg`, seit 0106)

**Braucht:** je Arbeit das Faule aus dem Palox (Differenz der Ablesungen,
`v_schimmel_menge`) gegen die Masse der Arbeit (Abschnitt 2) → ein Punkt
(Anteil dieses Auges, `anteil_station`; beim Waschen der Wasch-Palox allein
gegen die Masse hinein, 0105). Nicht plausible Punkte (Anteil über 90 %)
stehen grau und zählen nicht.
**Rechnung (seit 0111): Grundausschuss + Anstieg.** Je Sorte und Station
ist der Palox-Anteil eine Gerade über die Lagerdauer t:
Anteil(t) = Grundausschuss der Sorte + Anstieg der Station × t / 7.
Der **Anstieg** je Woche ist die massegewichtete Steigung der plausiblen
Punkte über ihre Lagerdauer, **innerhalb der Sorten** gemessen (jede Sorte um
ihre eigene Mitte — eine Sorte mit viel Grünem ist kein Anstieg); gemessen
wird er ab fünf Arbeiten (`n_paar`) und drei Wochen Spanne der Lagerdauern
innerhalb einer Sorte (`palox_anstieg_mindest_tage()`), und er ist nie
negativ (`palox_anstieg()`). **Gelten** tut er seit 0113 erst, wenn er
sicher ist: wenn die untere Grenze seines 95-%-Bereichs (`anstieg_unten`,
Standardfehler der gemeinsamen Steigung, je Sorte eine eigene Höhe) über 0
liegt (`palox_anstieg` mit vier Werten); sonst gilt 0, und `zuwachs_text`
sagt, warum. Der **Grundausschuss** ist das Mittel der Sorte, um den
geltenden Anstieg auf null Tage zurückgelegt: Mittel − Anstieg × mittlere
Lagerdauer / 7 (nie unter 0); gilt keiner, ist er das Mittel selbst — für
frische wie für lange gelagerte Ware („selbst wenn du heute erntest und
morgen sortierst, wirst du einen Ausschuss haben") — eigen ab drei Arbeiten (`palox_mindest_arbeiten()`), sonst
der aller Sorten (`ebene`, `quelle`, `geliehen` sagen es;
`erg_palox_erwartung.anstieg_je_woche`, `lager_mittel`). Bis 0110 war es ein
Anteil je Sorte und Station (Mittel der letzten vier Wochen), gleich für
frische und alte Ware; bis 0105 ein Modell F(t) = 1 − exp(−λ·t^k) mit
Sockel. Was eine
Charge auf ihrem Weg verliert, ist die Zusammensetzung der Stationen
(`palox_f`): f = p_hand · f_W+S + (1 − p_hand) · (f_S + (1 − f_S) · p_wasch · g_W),
mit p_hand = Anteil von Hand an der verarbeiteten Masse und p_wasch = 1, wenn
Bandware der Sorte in dieser Saison gewaschen wird (`v_charge_weg`: aus den
eigenen Arbeiten, sonst denen der Sorte, sonst allen). Für **ausgelagerte**
Ware gilt die eigene Messung der Charge je Station vor der Erwartung
(`v_charge_palox`, ohne Anstieg), sonst die Gerade **beim Alter am
Liefertag**; für **liegende** die Gerade beim heutigen Alter. `f_quelle`
an jeder Kaskadenzeile sagt, welche Werte es waren.
**Fortschreiben:** Prognose und Verlauf schreiben jede Station mit ihrem
Anstieg fort (`palox_f_nach`) und setzen neu zusammen. Ohne Anstieg (zu
wenige Arbeiten, zu kurze Spanne, gemessen ≤ 0) steht der Anteil still, und
`zuwachs_bekannt = false` sagt es: `faul_je_tag_kg` und die Zwei-Wochen-Zahl
(`v_naechste_charge`) bleiben leer. Auf den Betriebsdaten (12. Oktober,
Stand 113): Waschen + Sortieren 9,2 % (gemessen −0,8 % je Woche, kein
Anstieg), Waschen 10,5 % (gemessen +1,6 % je Woche, Bereich −2,5 bis +5,8 —
noch nicht sicher, gilt als 0), Sortieren 2,5 % (Spanne noch zu kurz) — je
bei jeder Lagerdauer. Bis 0112 galt beim Waschen der gemessene Anstieg, und
der Grundausschuss fiel auf 2 %.
**Von Hand ausgeschlossen (0116):** Eine Arbeit (`messung_ausschluss.art =
palox`, im Fenster der Messung) oder eine Kontrollwägung (`palox_lager`,
bisher nur in der Datenbank), die der Betriebsleiter nicht benutzen will, steht grau im Bild und zählt in keinen Anteil und
keinen Anstieg — wie ein nicht plausibler Punkt, mit dem Grund „von Hand
ausgeschlossen".
**Hagel (0116, `charge.hagel_anteil`, `hagel_f`):** Hagelschaden kommt beim
Waschen und Sortieren in den Palox. Er erhöht den Palox-Anteil einer Charge
dort, wo keine ihrer Messungen ihn schon enthält: f = 1 − (1 − f) · (1 − h)
für alles, was liegt, und für Ausgelagertes ohne eigene Messung der Charge
(`f_eigen`) — nie doppelt. 100 % heisst: nichts davon verkaufsfähig, auch
wenn f selbst unbekannt ist. Eine Charge mit Hagel zählt nicht in die
geteilten Anteile der Sorte und der Station (`v_palox_erwartung`,
`palox_station_kennzahl`) — sonst trüge jede andere Charge ihren Hagel mit.
Entsorgtes bleibt, wie es gewogen wurde. `mv_kaskade.hagel` sagt, welcher
Hagel angewandt wurde.
**Fehlt eine Eingabe:** eine Arbeit ohne Nenner liefert keinen Punkt
(Auffälligkeit „Ohne Nenner"); ein Leeren ohne Ablesung macht die Menge
unbekannt (Auffälligkeit „Palox geleert"); hat eine Station auf dem Weg
keinen Wert (auch nicht geliehen), ist das Faule der Charge unbekannt
(`f_bekannt = false`), nicht 0 — Verlust, Bilanz und Prognose sagen es.
**Urteil:** ehrlich und aus dem Betrieb: Was ein Auge in den Palox legt, ist
Faules dieser Station — Erde, Hagel, Schnitt eingeschlossen; „primär ist
Palox einfach Aussortieren" (12. Oktober), darum der Grundausschuss. Die
offene Frage der Saison ist der Anstieg ab Dezember
(`docs/SAISONBEGLEITUNG.md` § 2).

## 8. Fax (Faules beim Abpacken)

Eingefroren durch Entscheid des Betriebs (0078): Anteil 0, bekannt, nicht
unbekannt. Wird nicht erfasst.

## 9. Palettenmasse beim Fax (`v_koeff_palette_netto`)

Aus den gewogenen vollen fertigen Paletten: je Sorte und Kistensystem,
sonst je Sorte. Fehlt beides: die Fax-Arbeit hat keinen Nenner
(Auffälligkeit „Ohne Nenner"). Seit dem Einfrieren ohne Wirkung.

## 10. Der Sortiertag einer Lesung (0082)

Aus dem Dateinamen (Lauf-Datei) → sonst die eine Sortier-Arbeit im
Zeitfenster → sonst das nach Zählung gewichtete Mittel mehrerer → sonst die
Mitte des Fensters. `sortiertag_quelle` sagt es; ohne Sortiertag rechnet
die Verdunstung nicht mit der Lesung (AB-73).

## 11. Ausbeute und Kaskade (`v_kaskade_basis`, `mv_kaskade`)

**Braucht:** je Charge den Eingang (Abschnitt 1) und die Lieferungen; die
Koeffizienten 5–9 beim Alter am Liefertag.
**Rechnung:** ausgelagert = geliefert ÷ verkaufsfähiger Anteil; im Lager =
Eingang − ausgelagert; auf beide dieselbe Kaskade Verdunstung → Faules
(Stationswerte, Abschnitt 7) → zu klein/zu gross → Fax — seit 0106 ohne
Sockel. **Ausgang ist nur der Lieferschein**
(0101): Zu klein und zu gross, das hinter den Lieferungen aussortiert
wurde, hat den Betrieb nicht verlassen — es zählt zu „im Haus", nicht
verkaufsfähig, bis ein Lieferschein es holt (`erg_charge.im_haus_heute_kg`
= Liegendes nach Verdunstung und Verderb + `kanal_ausgelagert_kg`). Die
Bilanz lautet Eingang + Überzählung = ausgeliefert + Verlust + im Haus.
**Fehlt ein Koeffizient:** er ist unbekannt; die Kaskade lässt seinen
Schritt aus und das Dashboard sagt „nicht gemessen" — sie erfindet keinen.
**Wenn die Rechnung nicht aufgeht:** Überzählung (die Lieferungen brauchen
mehr Eingang, als erfasst ist) — seit 0090 mit den drei Möglichkeiten:
Eingang fehlt, Lieferschein falsch gebucht, Charge besser als das Modell.
**Urteil:** ehrlich; die Ausbeute ist die Stelle, an der ein zu hoher
Koeffizient „Im Lager" zu klein rechnet (Charge 1625) — die Saisonbegleitung
fragt danach.
**Wie viele Lieferungen (seit 0114):** Wie eine Lieferung auf die Chargen
fällt, steht in `v_lieferung_charge` (mit Nummer ganz, ohne Nummer nach dem
Eingang auf die Chargen der Sorte, der Ausgang vor der App am
Erfassungsbeginn). `erg_charge.n_lieferungen` zählt die Lieferscheine
(Verkauf, Marge, bis heute), die von der Charge genommen haben, jeden einmal;
`v_lieferung_gruppe` dasselbe je Gruppe — eine Lieferung ohne Nummer einmal,
nicht einmal je Charge ihrer Sorte. Der Ausgang vor der App ist Masse, kein
Lieferschein. Bis 0114 stand in `n_lieferungen` jede Lieferung einmal je
Eingangstag (die Kohorten der Kaskade, zusammengezählt) — beim Betrieb
„4'836 Lieferungen" bei 1'133.
**Der Verlauf Woche für Woche (`erg_verlauf`, seit 0114):** Braucht die
Portionen der Kaskade und die Liefertage der Charge (`v_lieferung_charge_tag`,
Verkauf und Marge). Je Woche ist von der gelieferten Portion eines
Eingangstags der Teil q weg, den die Lieferungen der Charge bis zum
Wochenende ausmachen (nach Masse); „im Lager" ist der Rest, und das
Liegende altert bis zum Wochenende, höchstens bis zum Alter der Lieferungen.
Das Gelieferte rechnet mit dem Alter der Lieferungen wie die Kaskade. Bis
0114 ging die ganze Portion an einem Tag (Eingangstag + mittleres Alter) —
beim Betrieb stand Amoro bis zum 6.9. bei 15.1 t, obwohl 2.6 t geliefert
waren, und „gesamt" sackte Mitte September um 44 t ab und stieg wieder. Ab
dem letzten Liefertag ist q = 1: heute und die Vorschau sind, was sie waren,
und sagen dasselbe wie die Saisonbilanz. **Fehlt** einer gelieferten Portion
die Lieferzeile (nach der Kaskade unmöglich), gilt die alte Umschaltung am
Liefertag — kein q aus dem Nichts.

## 12. Die Marge je Band (`v_marge_wiegung`, `v_marge_charge`)

**Braucht:** je gewogene fertige Palette Netto, Kisten und Kürbisse je
Kiste (`v_ausgang_kennzahl`) — und die **Grenzen des Bandes aus der Fassung
ihres Auftrags** (`band_von_g`, `band_bis_g`; beim eigenen Band die des
Auftrags; ohne Fassung die heute gültige Standardfassung der Sorte).
**Bandmitte:** der Schwerpunkt der Kürbisse aus den Sortierdateien der
Sorte innerhalb genau dieser Grenzen (`band_mittel`) — nicht die Mitte des
Bandes und nicht die Mitte einer anderen Fassung. Derselbe Index in zwei
Fassungen ist zwei Zeilen (0097).
**Je Kiste:** jede gewogene Palette zählt, auch eine nicht volle; `n_voll`
sagt, wie viele voll waren. Der Nenner des Waschens (Abschnitt 2) nimmt
weiter nur volle.
**Fehlt die Sortierdatei:** keine Bandmitte, kein „über der Mitte" — die
Gramm je Kürbis stehen trotzdem da.
**Urteil:** ehrlich seit 0097; davor nahm die Karte die Grenzen der
neuesten Fassung zu jedem Index, was „K1 500–600 · Mitte 878 g" ergab.

## 12a. Was im Haus ist — nach Kaliber und nach Artikel (`lager_kaliber`, `artikel_lager`, 0111, 0112)

**Braucht:** je Charge das Verkaufsfähige am Stichtag (Kaskade, Abschnitt
11; `kuerbis_stichtag(h)`) und die Gewichtsverteilung des jüngsten
Sortierlaufs der Charge, sonst der Sorte (`lager_schluessel()`).
**Nach Kaliber:** das Verkaufsfähige je Band der Fassung, im Verhältnis der
Verteilung. Was seit der Sortierung unter das kleinste Band geschrumpft ist,
zählt **im kleinsten Band** (`geschrumpft_kg` sagt, wie viel) — so summieren
sich die Bänder genau zum Verkaufsfähigen der Kennzahl und der Charge.
Daneben stehen Unterkaliber (= zu klein, `klein_kg`) und Überkaliber
(= zu gross, `gross_kg`) aus der Kaskade.
**Nach Artikel:** dieselbe Masse, nach den Kalibern der Artikelgruppe geteilt
(`artikel_kaliber`, Coop-Artikeldaten 2026): klein, gross, ausserhalb
(darunter/darüber), lose (Gruppe ohne Kaliber), ohne Verteilung (kein
Sortierlauf). Artikelgruppe aus der Sorte (`v_sorte_artikelgruppe`:
Stammdaten, sonst die meistverkaufte), Label aus der Charge
(`v_charge_label`, seit 0113: Stammdaten; sonst Demeter, sobald Perigon sie
einmal als Demeter geliefert hat — ohne Lieferlabel: verkauft —; sonst
Knospe aus Perigon; sonst wie die anderen Chargen desselben Produzenten;
sonst Knospe, angenommen; `quelle` sagt welches, `n_widerspruch` zählt
Zeilen, die als Demeter verkauft, aber als Knospe geliefert wurden;
Preisgruppen D, DU → D; K, KZ, CH-K, KAdR → K; bis 0112 entschied die
Mehrheit). Stück = kg × 1000 / Ø-Gewicht der Verteilung in diesem Kaliber,
Kisten = Stück / Stück je Kiste. **Je Charge:** `artikel_lager_charge(h)`
hat dieselben Teile ungerundet (`artikel_lager_teile`), `artikel_lager(h)`
zählt daraus zusammen — die Chargen hinter „Knirps klein · Demeter" ergeben
genau dessen Zahl.
**Fehlt eine Eingabe:** ohne Verteilung „ohne Grösse" (Masse ja, Stück
nein); ohne Artikelgruppe „Artikelgruppe unbekannt"; ohne Label „Label
unbekannt" (seit 0113 nur noch ohne die Migration), mit den Chargen dazu —
nichts wird verschluckt, die Summe bleibt das Verkaufsfähige.
**Kunden gegen Vorjahre:** `v_kunde_tag` aus `ausgang_position` (jede
Perigon-Position aller Saisons, 1. Juli – 30. Juni), nur Kürbis
(`ist_kuerbis_vorschlag`, sonst die Bestätigung des Betriebsleiters), ohne
interne Umbuchung (Journal L). Geht in keine Bilanz ein. Die Masse je
Position nach Abschnitt 12b; Stück ohne Stückgewicht zählen nicht in kg,
stehen aber als `stueck_ohne_gewicht` da (seit 0115).
**Wie viel von welchem Artikel noch da ist (Runde AQ):** je Artikelgruppe ×
Label die Chargen zusammengezählt (`src/auswertung/artikel.ts`,
`uebersichtszeilen`): Eingang, ausgelagert und geliefert, im Lager und
verkaufsfähig aus `erg_charge`, das Verkaufsfähige nach Grösse aus
`artikel_lager_charge(0)`. Ausgelagert + im Lager = Eingang — der Balken ist
so lang wie der Eingang. Ein unbekanntes Verkaufsfähiges zählt als Lücke,
nicht als 0. Eingang und ausgeliefert gibt es nur je Gruppe, nicht je Grösse.
**Kundengruppen und Pläne (Runde AS, `kunde_gruppe`, `kunde_plan`):** Ein
Kunde gehört zur Gruppe, die der Betriebsleiter gesetzt hat; ohne Eintrag
ordnet die App nach dem Namen (Migros, Coop samt RVZ/RZV, sonst
Kleinkunden). Die Gruppe ist die Summe ihrer Kunden. **Plan** ist die
eingetragene Menge der ganzen Saison, je Artikelgruppe, Grösse und Label
oder für alle; ohne Eintrag gilt, grau, die ganze Vorjahressaison des
Kunden. **Noch zu liefern** = Plan − diese Saison geliefert, je Kunde nie
unter null, über die Kunden summiert. **Seit 0117** gibt es auch den Plan
einer ganzen Gruppe (`gruppe_plan`, Stift in der Gruppenzeile): Hat eine Gruppe
einen, ist „noch zu liefern" der Gruppe dieser Plan weniger das Gelieferte
aller ihrer Kunden — die Pläne der Kunden darin stehen da, zählen aber nicht
noch einmal; ohne Gruppenplan ist die Gruppe die Summe ihrer Kunden. Die
Reihenfolge der Gruppen setzt der Betriebsleiter (`kunde_gruppe_rang`,
Pfeile in der Gruppenzeile); ohne sie stehen die Gruppen nach Menge,
Kleinkunden zuletzt. **Reicht es?** Das Verkaufsfähige im
Lager heute (je Artikel, wie oben) gegen „noch zu liefern"; fehlt etwas,
steht es rot mit „!" in der Artikeltabelle und unter den Kunden.
**Die ganze Perigon-Zeile (0116, `ausgang_position.roh`):** beim Einlesen
jede Zeile mit allen Spalten, wie sie in der Datei stand — nur zum Zeigen
(„Lieferung"-Fenster), nicht zum Rechnen; Positionen von vor 0116 haben sie
erst nach dem nächsten Einlesen. `v_perigon_pruefung` sieht jede Zeile der
laufenden Saison durch: Charge nicht zugeordnet, Artikel passt nicht zur
Sorte, als Demeter verkauft und als Knospe geliefert, Lieferung vor dem
ersten Eingang.
**Urteil:** ehrlich; dieselbe Zahl wie überall, nur anders geteilt.

## 12b. Die Masse einer Perigon-Position (`perigon_kg`, `perigonKg`, 0115)

**Braucht:** aus der Perigon-Datei je Zeile die Menge (`AufPosQuantity`,
je Charge `AufPosBatchQuantity`), das Gewicht je Artikel
(`GewichtProArtikel`) und die Einheit.
**Rechnet:** Gewicht je Artikel > 0 → Menge × Gewicht. Sonst bei Einheit kg
→ die Menge selbst (der Perigon-Artikelstamm führt bei kg-Artikeln oft 0
statt 1). Sonst — Stück ohne Stückgewicht — **unbekannt (leer), nie 0**.
Dieselbe Regel in der App (`src/lib/warenausgang.ts`, beim Einlesen: Masse
je Zeile und je Charge, daraus die Lieferungen) und in der Datenbank
(`perigon_kg()`, für die Positionen aller Saisons); `test/warenausgang.test.ts`
und Prüfblock 0115 halten beide fest.
**Lieferungen daraus:** je Position und Charge eine Lieferung, der Rest
ohne Charge als `…:rest`. Seit 0115 entfernt das Einlesen für jede Position
der Datei die Lieferungen, die die Datei nicht mehr ergibt (Charge
nachgetragen, anders aufgeteilt, keine Masse mehr) — Positionen ausserhalb
der Datei, andere Firmen und Lieferungen von Hand bleiben; das Journal
behält jede entfernte.
**Fehlt eine Eingabe:** ohne Stückgewicht keine Lieferung und keine Masse —
die Position steht beim Einlesen unter „ohne Gewicht" und im Vergleich je
Kunde als Stück. `v_ausgang_pruef` zeigt jede Position, deren Lieferungen
nicht die Masse der Datei ergeben; der Warenausgang warnt oben.
**Urteil:** ehrlich. Bis 0115 zählten kg-Artikel mit Gewicht 0 als 0 kg
(BioProdukte 2024/25: 81.6 t statt 168.3 t).

## 13. Was nirgends erraten wird

- Eine Menge aus einer Zählung ohne Masse (AB-23).
- Ein Netto aus einem Brutto ohne Tara („Ausschuss ohne Tara", „Tara fehlt").
- Ein Sortiertag aus einem Dateistempel (0082).
- Eine Verdunstung über der Grenze (0089).
- Ein Koeffizient aus null Messungen.
- Eine Ausschuss-Art, die niemand gewogen hat (0097).
- Ein Sockel ohne Nachweis — er ist 0 und sagt es (0097).
- Die Grenzen eines Bandes aus einer fremden Fassung (0097).
- Ein Stückgewicht, das der Perigon-Artikelstamm nicht kennt (0115).
- Ein Hagelschaden, den niemand eingetragen hat — ohne Eintrag kein Hagel
  (0116).
- Ein Mittel ganzer Paletten für eine Palette, deren Kisten gezählt sind
  (0116).
