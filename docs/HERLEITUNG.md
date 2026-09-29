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

## 1. Netto einer Eingangspalette (`v_palette`)

**Braucht:** Brutto vom Zettel (Erntejournal), Kisten, Gebindeart → Tara je
Kiste und Palette (`gebinde`).
**Rechnung:** Netto = Brutto − Kisten × Kistentara − Palettentara.
**Fehlt etwas:** Netto bleibt **null**. Die Charge rechnet ihren Eingang mit
dem Mittel der Paletten, die ein Netto haben, mal Anzahl aller Paletten
(`v_charge_rueckgrat`); das Dashboard sagt „n Paletten ohne Nettogewicht —
für sie rechnet der Eingang mit dem Mittel der übrigen".
**Urteil:** ehrlich. Ein Ersatz aus derselben Charge, sichtbar benannt.

## 2. Die Masse einer Arbeit — der Nenner (`v_auftrag_masse`)

Je gezählter Palette (`v_auftrag_palette_masse`), in dieser Reihenfolge:

| Quelle | Wann | Was |
|---|---|---|
| `gewogen` | die Palette wurde in dieser Arbeit gewogen | ihr eigenes Netto (Zettel-Brutto minus ihre Tara) |
| `zettel` | Zettelgewicht und -datum finden die Palette im Wareneingang | das Netto dieser Palette |
| `zettel-kisten` (0090) | kein Treffer, aber Kisten und Gebinde gezählt | Zettel − Kisten × Kistentara − Palette |
| `zettel-charge-tara` | kein Treffer, keine Kisten | Zettel − mittlere Tara der Charge |
| `palette` | die Palette ist über ihre Nummer verknüpft | ihr Netto |
| `datum-mittel` | nur das Datum ist da | Mittel der Paletten dieses Eingangstags |
| `charge-mittel` | nichts als die Charge | Mittel der Charge |

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
Grenze `verdunstung_rate_max_pro_tag` (Vorgabe 1 % je Tag). Jede Wägung,
die nicht zählt, sagt warum (`grund`).
**Zusammenfassen:** je Charge das nach Masse gewichtete Mittel → je Sorte →
zum Gesamtwert aller Sorten gezogen (empirisches Bayes: der Zug ist stark,
wenn die Sorte wenige Chargen hat, schwach, wenn sie viele hat). Die
`basis` sagt es: „Wiegungen dieser Sorte" (b ≥ 0.67) · „…, zum Gesamtwert
gezogen" · „Wiegungen aller Sorten" · „keine Wiegung vorhanden".
**Fehlt alles:** unbekannt, nicht null — die Kaskade rechnet dann ohne
Verdunstung und das Dashboard sagt „nicht gemessen".
**Urteil:** ehrlich; die Grenze (0089) war die Lücke.

## 6. Zu klein, zu gross, anderer Kanal (`v_koeff_ausschuss`, `v_koeff_nebenkanal`)

**Braucht:** je Sortierlauf die Masse unter dem kleinsten und über dem
grössten Band (CSV, klassiert nach der Fassung des Auftrags) — und von der
Handlinie die gewogenen Kisten (0088). Anteile an der Masse des Laufs.
**Zusammenfassen:** wie die Verdunstung — je Sorte, zum Gesamtwert gezogen,
`basis` sagt es.
**Fehlt alles:** unbekannt.
**Fehlt eine Art** (nur „zu gross" gewogen, „zu klein" übersprungen): diese
Art ist unbekannt, nicht 0; die gemessene zählt; keine Auffälligkeit (0097).
**Wohin:** ins Haus, nicht in den Ausgang (0101) — aussortiert steht es in
Paloxen, bis ein Lieferschein es holt; das Buch „marge" (an die Tiere, in
den Nebenkanal) zählt erst dann, und der Befund der Bilanz vergleicht beides.
**Urteil:** ehrlich.

## 7. Faules im Lager — die Stationswerte (`v_palox_erwartung`, `v_charge_weg`, seit 0106)

**Braucht:** je Arbeit das Faule aus dem Palox (Differenz der Ablesungen,
`v_schimmel_menge`) gegen die Masse der Arbeit (Abschnitt 2) → ein Punkt
(Anteil dieses Auges, `anteil_station`; beim Waschen der Wasch-Palox allein
gegen die Masse hinein, 0105). Nicht plausible Punkte (Anteil über 90 %)
stehen grau und zählen nicht.
**Rechnung:** kein Modell über die Lagerdauer mehr (bis 0105: F(t) =
1 − exp(−λ·t^k) mit Sockel, Smearing, Selektionszuschlag — gestrichen auf
Entscheid des Betriebs, Runde AJ). Stattdessen je Sorte und Station der
**erwartete Palox-Anteil**: das nach Masse gewichtete Mittel der plausiblen
Punkte, zuerst die letzten vier Wochen der Sorte (ab drei Arbeiten,
`palox_mindest_arbeiten()`), sonst ihre ganze Saison, sonst alle Sorten
(vier Wochen, dann Saison; `ebene`, `quelle`, `geliehen` sagen es). Was eine
Charge auf ihrem Weg verliert, ist die Zusammensetzung der Stationen
(`palox_f`): f = p_hand · f_W+S + (1 − p_hand) · (f_S + (1 − f_S) · p_wasch · g_W),
mit p_hand = Anteil von Hand an der verarbeiteten Masse und p_wasch = 1, wenn
Bandware der Sorte in dieser Saison gewaschen wird (`v_charge_weg`: aus den
eigenen Arbeiten, sonst denen der Sorte, sonst allen). Für **ausgelagerte**
Ware gilt die eigene Messung der Charge je Station vor der Erwartung
(`v_charge_palox`), für **liegende** die Erwartung der Sorte. `f_quelle`
an jeder Kaskadenzeile sagt, welche Werte es waren.
**Zuwachs:** die Kennzahl je Station (`palox_station_kennzahl()`, 0105)
liefert den Zuwachs je Woche — massegewichtete Gerade über den Messtag, erst
nach vier Wochen und fünf Arbeiten. Die Prognose schreibt jede Station um
diesen Zuwachs fort (`palox_f_nach`) und setzt neu zusammen; der Verlauf
verschiebt so auch zurück. Ohne Zuwachs steht der Anteil still, und
`zuwachs_bekannt = false` sagt es: `faul_je_tag_kg` und die Zwei-Wochen-Zahl
(`v_naechste_charge`) bleiben leer.
**Fehlt eine Eingabe:** eine Arbeit ohne Nenner liefert keinen Punkt
(Auffälligkeit „Ohne Nenner"); ein Leeren ohne Ablesung macht die Menge
unbekannt (Auffälligkeit „Palox geleert"); hat eine Station auf dem Weg
keinen Wert (auch nicht geliehen), ist das Faule der Charge unbekannt
(`f_bekannt = false`), nicht 0 — Verlust, Bilanz und Prognose sagen es.
**Urteil:** ehrlich und aus dem Betrieb: Was ein Auge in den Palox legt, ist
Faules dieser Station — Erde, Hagel, Schnitt eingeschlossen; einen Sockel,
der das herausrechnet, gibt es nicht mehr. Die offene Frage der Saison ist
der Zuwachs ab Dezember (`docs/SAISONBEGLEITUNG.md` § 2).

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

## 13. Was nirgends erraten wird

- Eine Menge aus einer Zählung ohne Masse (AB-23).
- Ein Netto aus einem Brutto ohne Tara („Ausschuss ohne Tara", „Tara fehlt").
- Ein Sortiertag aus einem Dateistempel (0082).
- Eine Verdunstung über der Grenze (0089).
- Ein Koeffizient aus null Messungen.
- Eine Ausschuss-Art, die niemand gewogen hat (0097).
- Ein Sockel ohne Nachweis — er ist 0 und sagt es (0097).
- Die Grenzen eines Bandes aus einer fremden Fassung (0097).
