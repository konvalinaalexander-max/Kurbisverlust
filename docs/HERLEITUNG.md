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
**Welche Charge (0120):** Das Erntejournal führt keine Chargennummer; die
Zeile findet ihre Charge über Schlag und Sorte im Register (`charge`, aus
0003, Oettli und Trüeb aus 0120), verglichen ohne Gross/klein und Satzzeichen,
Umlaute als Umlaute (`src/lib/import.ts`). Findet sie keine, wird sie nicht
übernommen — nie einer geratenen Charge zugeschlagen —, und der Abgleich beim
Öffnen des Dashboards sagt, welche Zeilen warten.

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

**Korrigiert mit einem Klick** (0128): Übernimmt der Betriebsleiter unter
Messungen → Auffälligkeiten einen Vorschlag, ändert sich genau das Zetteldatum
oder Zettelgewicht der genannten Zettel (oder „mit Palette" einer
Ausschuss-Wägung) — nur, wo noch steht, was die App sah; vorher und nachher
stehen im Vermerk (`auffaelligkeit_vermerk`). Beim nächsten Rechnen findet
`zettel` die Palette, statt mit `zettel-kisten` zu rechnen, und die Lagertage
beginnen am richtigen Tag.

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
**Rechnung:** ausgelagert = geliefert ÷ verkaufsfähiger Anteil; liegend
(`lager_kg`) = Eingang − ausgelagert; auf beide dieselbe Kaskade Verdunstung → Faules
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
Seit Runde BF zeigt der Fall im Reiter Perigon die Überzählung **rückwärts**:
die Portionen „ausgelagert" der Charge aus `mv_kaskade` zusammengezählt —
geliefert + zu klein + zu gross + Fax + Faules + verdunstet = Σ m0 =
`erg_charge.ausgelagert_kg`, je Schritt der Anteil vom Rest davor (Verdunstung
als Rate je Tag mit der nach Masse gewichteten Lagerdauer) und die Herkunft
jedes Werts aus den Spalten der Kaskade (`r_basis`, `f_quelle`, `klein_basis`,
`gross_basis`). Gerechnet wird dort nichts neu
(`src/auswertung/faelle.ts`, `rueckrechnung`); fehlt die Kaskade, steht keine
Rückrechnung da, fehlt der Eingang, kein Unterschied. „Wie sicher?" vergleicht
den Verlust, den die Charge höchstens haben dürfte (1 − geliefert ÷ Eingang),
mit dem gerechneten (1 − geliefert ÷ ausgelagert); liegt schon geliefert über
dem Eingang, geht es auch ohne jeden Verlust nicht auf.
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
**Was „im Lager" heisst (seit 22. Oktober, `src/auswertung/lager.ts`):** an
jeder Stelle dasselbe — was auf den Paletten liegt: die liegende
Eingangsmasse ohne das, was seither verdunstet oder faul geworden ist, also
die gute Ware der Kaskade (`erg_prognose.gute_ware_kg`; je Woche
`erg_verlauf.im_haus_kg − aussortiert_kg`; je Charge
`im_haus_heute_kg − kanal_ausgelagert_kg`, dieselbe Zahl). Darin das
Verkaufsfähige und zu klein / zu gross; nicht darin, was hinter den
Lieferungen schon aussortiert in Paloxen steht (die Bilanz zählt es weiter
„noch im Haus"). Dazu die **Paletten**: `n_rest_paletten` = liegende
Eingangsmasse ÷ mittlere Eingangspalette der Charge — Verdunstung und
Faules leeren keine Palette, und ohne Lieferung bleibt die Zahl gleich;
gerundet 0 heisst „< 1 Palette". **Fehlt eine Rate** (Verdunstung
oder Faules), ist die Zahl eine obere Schranke und steht mit „höchstens".
Bis zum 22. Oktober war „im Lager" die liegende Eingangsmasse selbst
(`lager_kg`, heute „Liegend") — mit dem Verdunsteten und dem Faulen darin.
**Wie viel von welchem Artikel noch da ist (Runde AQ):** je Artikelgruppe ×
Label die Chargen zusammengezählt (`src/auswertung/artikel.ts`,
`uebersichtszeilen`): Eingang, ausgelagert und geliefert, im Lager und
verkaufsfähig aus `erg_charge`, das Verkaufsfähige nach Grösse aus
`artikel_lager_charge(0)`. Ausgelagert + liegend = Eingang — der Balken ist
so lang wie der Eingang; das Liegende teilt sich in im Lager (verkaufsfähig,
zu klein / zu gross, beim Abpacken faul, Teilung unbekannt) und, blass
dahinter, seit dem Eingang verdunstet oder faul. Eine Charge ohne Teilung
zählt ganz ins Lager, und die Zeile sagt „höchstens". Ein unbekanntes Verkaufsfähiges zählt als Lücke,
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
ersten Eingang. **Welche Charge (Spalte W):** die BioProdukte-Datei nennt
die eigene, 4-stellige Nummer; die Datei der anderen Firma ihre 6-stellige
Perigon-Nummer, die über `charge.perigon_nr` (Stammdaten → Chargen) zur
eigenen wird. Spalte S sagt, wie viel der Position aus dieser Charge kam;
was die Zeilen zusammen nicht abdecken, wird ein Rest ohne Charge (zählt im
Warenausgang, bei keiner Charge) und steht seit 0118 als „Teil ohne
Charge", nicht als unbekannte Charge.
**Urteil:** ehrlich; dieselbe Zahl wie überall, nur anders geteilt.

## 12b. Die Masse einer Perigon-Position (`perigon_kg`, `perigonKg`, 0115)

**Braucht:** aus der Perigon-Datei je Zeile die Menge (`AuftragsArtikelMenge`,
je Charge `AufPosBatchQuantity Charge`), das Gewicht je Artikel
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

## 12c. Was im Lager liegt, Schritt für Schritt (`v_lager_ausweis`, 0121)

**Braucht:** je Charge die Prognose von heute (`erg_prognose`, h = 0: liegende
Eingangsmasse, verdunstet, faul, gute Ware, zu klein, zu gross, Faules beim
Abpacken, verkaufsfähig), die Restpaletten (`erg_charge.n_rest_paletten`), den
angewandten Hagel der Kaskade (`mv_kaskade.hagel`) und die Überfüllung
(`erg_marge_charge`: zu viel je Kiste und Soll).
**Rechnet:** eingang_kg − verdunstet − faul − Unique − zu klein − zu gross −
Faules beim Abpacken = verkaufsfähig. Unique = gute Ware · h/(1 − h), wo die
Kaskade den Hagel h angewandt hat; faul = Faules der Kaskade − Unique. Marge =
verkaufsfähig · a/(1 + a), a = Σ zu viel ÷ Σ Soll der gewogenen Kisten der Charge,
sonst der Sorte; Stück-Kisten haben kein Soll: a = 0. Verrechenbar = verkaufsfähig
− Marge. Die App zählt über die Chargen der Auswahl zusammen
(`src/auswertung/ausweis.ts`); die Rate je Tag ist dort verdunstet ÷ Eingang ÷
mittleres Alter (nach Masse).
**Fehlt eine Eingabe:** ohne gemessene Rate fehlt die Charge in den Abzügen und
wird als Lücke gezählt („n von m Chargen fehlen") — nie 0. Ohne gewogene Kisten
weder der Charge noch der Sorte: Marge unbekannt, „verrechenbar" steht nicht da.
**Urteil:** ehrlich; ändert keine Zahl der Kaskade, legt sie nur hin.

**Seit 0123 (23. Oktober) — im Lager und verkaufsfähig, an jeder Stelle gleich.**
*Im Lager* ist die Eingangsmasse der Paletten, die noch stehen (`eingang_kg` =
`erg_charge.lager_kg` = `erg_prognose.lager_kg`), mit den Restpaletten — ohne
Abzug, vor Verdunstung, Palox und Arbeit. *Verkaufsfähig* ist `verkaufbar_kg`:
**Braucht** dazu `artikel_lager_teile(0)` (das Verkaufsfähige der Kaskade nach
den Gewichten der Artikel geteilt, aus der Sortier-CSV, jeder Kürbis um die
gemessene Verdunstung geschrumpft) und die Überfüllung a wie oben.
**Rechnet:** passt in keinen Artikel = Σ der Teile darunter, darüber, dazwischen
und der Sorten ohne Artikel; Grösse offen = Σ ohne Verteilung; als Artikel =
verkaufsfähig − passt in keinen Artikel; Überfüllung = als Artikel · a/(1 + a);
verkaufbar = als Artikel − Überfüllung + Unique. Die Kette geht auf:
eingang − verdunstet − faul − zu klein − zu gross − Faules beim Abpacken −
passt in keinen Artikel − Überfüllung = verkaufbar. Der Anteil in der Kachel
ist verkaufbar ÷ im Lager.
**Fehlt eine Eingabe:** keine gewogene Überfüllung (Charge und Sorte): nichts
abgezogen, aber „höchstens", und `verkaufbar_offen` sagt „Überfüllung nicht
gewogen"; keine Sortier-CSV: dasselbe mit „Grösse offen" — nie 0. Die Spalten
von 0121 (`verkaufsfaehig_kg`, `marge_kg`, `verrechenbar_kg`) bleiben, wie sie
waren: das Verkaufsfähige der Sortiermaschine.
**Urteil:** ehrlich; die Zahl der Kachel ist dieselbe wie unter Chargen, im
Fenster der Charge und (je Artikel) unter Artikel. Der Verlauf über die Wochen
kennt nur das Verkaufsfähige der Sortiermaschine — dort steht der heutige
Wert als eigener Punkt daneben.

**Seit 0124 (Runde AZ) — was der Ausweis nicht wissen kann, sagt er.** Eine
Sorte ohne Artikelgruppe in den Stammdaten zählt nicht mehr als „passt in
keinen Artikel", sondern als offen: `gruppe_offen_kg`, nicht abgezogen,
`verkaufbar_offen` „Artikelgruppe fehlt (Stammdaten → Sorten)" — das
Verkaufbare ist dann eine obere Schranke. Eine Artikelgruppe ohne Gewichte
(`artikel_kaliber` leer) ist ein Artikel ohne Grösse (lose) und zählt als
verkaufbar. Ohne Sortier-CSV ist `keinen_artikel_kg` leer, nicht 0; ohne
Verkaufsfähiges sind auch `groesse_offen_kg` und `gruppe_offen_kg` leer. Hagel
100 %: `faul_kg`, `unique_kg`, `hagel_bis_heute_kg` und `verkaufbar_kg` leer
(die Kaskade kann Unique und Faules nicht trennen), Grund „Hagel 100 %".
Gewogene Paletten, deren Arbeit kein Kistensystem oder kein Sollgewicht hat
(`v_ausgang_kennzahl`): `marge_quelle` nennt die Zahl und die Stelle zum
Nachtragen, `verkaufbar_offen` „Überfüllung offen …" statt „nicht gewogen".
**Urteil:** ehrlich — jede Zahl, die der Ausweis nicht hat, fehlt sichtbar und
mit Grund (Prüfblock 0124 b1–b6, sieben Mutationen).

**Runde BA — die Paletten zum Nachzählen.** **Braucht:** je Charge die
≈-Paletten (`erg_charge.n_rest_paletten`: Eingang minus die Eingangskilo
hinter den Lieferscheinen, durch die mittlere Eingangspalette). **Rechnet:**
nichts weiter — eine Zahl, Paletten gesamt, sortiert oder nicht; der
Kontrollgang zählt, was steht. Eine Trennung in unsortierte Eingangspaletten
(aus `erg_kohorte.n_rest`) und sortierte in Kisten stand einen Tag lang da und
wurde vom Betrieb zurückgenommen: nicht jedes Sortieren läuft über die App,
also weiss sie nicht, welche Palette durch die Maschine ging. **Fehlt eine
Eingabe:** ohne Palettenzahl steht nichts, nie 0. **Urteil:** ehrlich — eine
Zahl, die der Betriebsleiter im Lager prüfen kann (`src/auswertung/lager.ts`).

## 12d. Die Charge einer Palette (`paletten_zuordnen`, 0121)

**Braucht:** Paletten mit der Charge des Journals (`charge_nr_journal`), Zettel
der Arbeiten (`auftrag_palette`: Brutto, Eingangsdatum), Lieferungen je Charge
(`v_lieferung_masse`), Netto der Paletten (`v_palette`).
**Rechnet:** siehe ENTSCHEIDUNGEN, Runde AW, 1: aufs Kilo, ±3 Tage, die eigene
Charge zuerst; umgebucht ab 2 Zetteln und 80 %, wenn die Charge der Arbeit mehr
lieferte, als sie bekam; der Rest einer Fuhre mit. `palette.charge_nr` ist danach
die Charge, mit der alles gerechnet wird.
**Fehlt eine Eingabe:** ein Zettel ohne Eingangsdatum oder Brutto belegt nichts;
ohne Beleg bleibt die Charge des Journals.
**Urteil:** eng mit Absicht — ein Vorschlag wird angezeigt, nicht gebucht.

## 12e. Lieferscheine ohne Charge (`v_ohne_charge`, `lieferungen_nachordnen`, 0121)

**Rechnet:** je Sorte die Lieferscheine ohne Chargennummer und wie die Rechnung
sie verteilt (0114: nach Eingang auf die Chargen der Sorte); was davon vor dem
Eingang der tragenden Charge lag und was auf keine fällt. Eine Nummer der Datei,
die die App inzwischen kennt (eigene Nummer, sonst eine Perigon-Nummer an genau
einer Charge), bekommt der Lieferschein im nächsten Rechenlauf.

**Seit 0125 auch einzeln (`v_lieferung_ohne_charge`).** **Braucht:** dieselben
Lieferscheine wie `v_ohne_charge` (verkauft, mit Masse, bis heute), ihre
Verknüpfung zur Perigon-Zeile (`lieferung_import`, `ausgang_zeile`), die
Bemerkung des Einlesens und das Chargenregister (Nummer, Perigon-Nr.).
**Rechnet:** je Lieferschein den Grund, in dieser Folge: aus Perigon, aber
ohne Zeile (Bemerkung „ohne Chargenbezug" / „Charge … (extern)" oder keine
Zeile der Position mehr) → `ohne_zeile`; von Hand → `von_hand`; eine eigene
Zeile mit Nummer: inzwischen an genau einer Charge → `nachholen`, an mehreren →
`mehrdeutig`, an keiner → `unbekannt`; der Rest einer Position: keine Nummer in
Spalte W → `keine_nummer`, Nummern genannt, aber Spalte S = 0 → `menge_null`,
sonst → `rest` (S kleiner als die Position). Dazu Firma und Position (für das
Fenster mit der Perigon-Zeile), Artikel, die Nummern aus W, ein Satz und was zu
tun ist. **Fehlt eine Eingabe:** ohne Verknüpfung und ohne Bemerkung gilt
„von Hand" — die Kopie aus dem Betriebsabzug führt beides nicht, dort steht
darum jeder als „von Hand"; in der Datenbank des Betriebs nicht. **Urteil:**
ehrlich — Anzahl und Summe je Sorte sind dieselben wie in `v_ohne_charge`
(Prüfblock 0125 b2); nichts wird umgebucht.

## 12f. Wer im Perigon wie heisst — die Charge über den Produzenten (`schlag_alias`, `v_perigon_produzent`, 0122)

**Braucht:** die zweiten Namen eines Schlags (`schlag_alias`: Inauen = Oettli,
Trüb = Trüeb — vom Betrieb), Spalte X der Perigon-Zeilen (`ausgang_zeile.produzent`),
die Chargen der Saison mit Sorte und Artikelgruppe (`sorte_kaliber`).
**Rechnet:** Ein Name aus Spalte X gehört zu einem Schlag, wenn der Betrieb es
gesagt hat, sonst wenn er nur bei Zeilen von Chargen *eines* Schlags vorkommt,
deren Nummer die App kennt (gelernt); sonst, wenn ein Schlag genau so heisst.
Ein Lieferschein, dessen Nummer an keiner Charge steht, bekommt im Rechenlauf
(`lieferungen_nachordnen`, Stufe 2) die Charge, wenn dieser Schlag in der Saison
genau eine Charge mit der Artikelgruppe des Artikels hat — mit dem Grund in
`lieferung_nachordnung`. Verglichen wird in der Vergleichsform (`name_norm`: NFC,
klein, ohne Satzzeichen), im Journal-Abgleich ebenso (`src/lib/import.ts`).
**Fehlt eine Eingabe:** ohne Produzent, bei einem Namen an mehreren Schlägen
(der eigene Betrieb), bei Mix oder unbekanntem Artikel, bei zwei passenden
Chargen: keine Charge — der Lieferschein bleibt „ohne Charge" und wird verteilt
wie in 12e. Ein Rest ohne Charge (Spalte S) bekommt nie eine.
**Urteil:** ehrlich, weil eindeutig oder gar nicht; jede Zuordnung steht als
Hinweis da, bis der Betriebsleiter die Nummer bei der Charge einträgt.

## 12g. Der Weg der Ware und woher sie wohl kam (`v_charge_spur`, `ungereimt_kandidaten`, `v_stammdaten_pruefung`, 0122)

**Rechnet:** je Charge herein (Paletten der Charge, die das Journal nennt, und die
die App jetzt zählt — der Unterschied sind Umbuchungen), bearbeitet (Arbeiten,
nicht abgebrochen), hinaus (Lieferscheine bis heute, nach Artikelgruppe, davon
nachgeordnet; seit 0124 steht, was keine Perigon-Zeile hat — von Hand
erfasst —, als eigener Teil „ohne Perigon-Zeile", damit die Teile auf
`geliefert_kg` aufgehen), noch da (≈ Paletten aus der Kaskade). Bei Ware, die hinausging,
ohne dass die Charge sie hatte, die Chargen, von denen sie wohl kam: derselbe
Artikel, laut App noch ≥ 1 Palette, höchstens die Hälfte verkauft, eingegangen
vor dem letzten Lieferschein; derselbe Schlag, dann dieselbe Sorte zuerst,
höchstens vier. Das Chargenregister wird geprüft: eine Perigon-Nummer an mehreren
Chargen (mit den Nummern der Dateien, die ±2 daneben liegen oder vom Produzenten
dieser Chargen kommen), eine Charge der Saison mit Ware ohne Perigon-Nummer, ein
Schlag unter zwei Namen.
**Fehlt eine Eingabe:** ohne Rechenlauf ist „noch da" unbekannt, nie 0; ohne
Kandidaten sagt der Vorschlag, dass keiner passt.
**Urteil:** Auskunft, keine Buchung — die Kandidaten verschieben keine Zahl.

## 12h. Jeder Fall einer Perigon-Position (`v_perigon_befund`, `perigon_faelle_merken`, 0126)

**Rechnet:** je Position der laufenden Saison aus ihren Zeilen (`ausgang_zeile`):
die Masse Q × AE (`kg_position`, 12b), was die Chargenzeilen mit Nummer und
Menge zuteilen (Σ S × AE, `kg_zugeteilt`), was die Rechnung daraus an
Lieferungen hat (`kg_rechnung`, ohne Rücknahmen), und davon ohne Charge. Die
Arten und die Masse, um die es geht: S = 0 — die Position (leer, wenn auch Q = 0);
zu viel — Σ S − Q (ab 0.5 kg); Rest — Q − Σ S (ab 0.5 kg); keine Nummer — Q;
ohne Gewicht — leer; Rücknahme — −Q; Rechnung ≠ Datei — Rechnung − Q (ab
0.05 kg, Vorzeichen bleibt); Artikelname gegen Preisgruppe — Q. Je Chargenzeile
mit Lieferung: die Masse ihrer Lieferung (nachholen, mehrdeutig, unbekannt —
nur ohne Charge; Artikel gegen Sorte, Demeter/Knospe, Mix, vor dem Eingang —
mit Charge). Rot ab 500 kg bei Arten, die Ware auf die falsche oder keine Charge
legen; Auskunft bei nachholen und Rücknahme.
**Merken:** nach jedem fertigen Rechenlauf alle Fälle dieser Sicht und alle
Sachen aus `v_ungereimtheit` (Schlüssel `ungereimt_schluessel`, wie in der App)
in `perigon_fall_spur`: erst gesehen, zuletzt gesehen, weg seit.
**Fehlt eine Eingabe:** ohne Gewicht je Artikel ist die Masse leer, nie 0; ohne
Rechenlauf ist ein neuer Fall noch nicht gemerkt („beim nächsten Rechnen");
ohne Vermerk ist ein Fall offen.
**Urteil:** Auskunft, keine Buchung — ein Vermerk ändert keine Zahl.
**Wo die Zeile in der Datei steht (Runde BE):** die Excel-Zeile aus `<row r>` der
.xlsx, beim Einlesen in `ausgang_position.roh` (`#zeile`, `#blatt`, `#datei`);
die einer Chargenzeile ist die lauf-te Zeile mit dieser Charge (`excelZeileVon`).
Ohne neues Einlesen ist sie leer — nie aus der Reihenfolge geraten.
**Im Fenster nachgerechnet (Runde BD, `nachrechnen` in `src/auswertung/perigon.ts`):**
je Zeile der Position aus `ausgang_zeile` die Charge (W), die Menge (S) und
ihre Kilo (`kg_charge`, sonst S × AE; bei kg-Artikeln mit AE 0 ist S das Kilo;
Stück ohne Gewicht: unbekannt, nie 0); eine Zeile mit derselben Charge und
derselben Menge wie eine frühere sagt „gleich wie Zeile …". Die Summen
(zugeteilt, Position, Rechnung) kommen aus dieser Sicht, nicht aus der
Summe im Fenster — die Zeilen zeigen nur, woraus sie bestehen.

## 13. Was nirgends erraten wird

- Eine Menge aus einer Zählung ohne Masse (AB-23).
- Ein Netto aus einem Brutto ohne Tara („Ausschuss ohne Tara", „Tara fehlt").
- Ein Sortiertag aus einem Dateistempel (0082).
- Eine Verdunstung über der Grenze (0089).
- Ein Koeffizient aus null Messungen.
- Eine Ausschuss-Art, die niemand gewogen hat (0097).
- Ein Sockel ohne Nachweis — er ist 0 und sagt es (0097).
- Die Grenzen eines Bandes aus einer fremden Fassung (0097).
- Eine Artikelgruppe für eine Sorte, die in den Stammdaten keine hat — sie
  ist offen, nicht „lose" (0124).
- Was in kein Artikelgewicht passt, ohne Sortier-CSV — leer, nicht 0 (0124).
- Ein Faul-Gewicht in der Halle ohne Ablesung des Palox — „unbekannt", nicht
  0 kg (`faulesKg`, Runde AZ).
- Ein Stückgewicht, das der Perigon-Artikelstamm nicht kennt (0115).
- Ein Hagelschaden, den niemand eingetragen hat — ohne Eintrag kein Hagel
  (0116).
- Ein Mittel ganzer Paletten für eine Palette, deren Kisten gezählt sind
  (0116).
- Die Charge eines Lieferscheins aus einem Produzenten, der bei mehreren
  Schlägen vorkommt, oder aus einem Schlag mit zwei passenden Chargen (0122).
- Woher verkaufte Ware ohne Eingang kam — die App nennt Kandidaten, gebucht
  wird nichts (0122).
