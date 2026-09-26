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

Dann je Arbeit: die Summe der gezählten Paletten → sonst **fertige Paletten**
(Waschen: gezählte fertige Paletten × Mittel der gewogenen; 3 reichen) →
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
**Fehlt beides:** unbekannt, Auffälligkeit „Kistengewicht" mit dem neuen Rat.
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
**Urteil:** ehrlich.

## 7. Faules im Lager — das Verderbsmodell (`mv_schimmel_modell`)

**Braucht:** je Arbeit das Faule aus dem Palox (Differenz der Ablesungen,
`v_schimmel_menge`) gegen die Masse der Arbeit (Abschnitt 2) und die
Lagertage (Abschnitt 3) → ein Punkt (Anteil, Tage). Nicht plausible Punkte
(Anteil zu hoch für die Basis) stehen grau und zählen nicht.
**Modell:** F(t) = 1 − exp(−λ·t^k), **ein Modell für alle Sorten**, im
Logarithmus angepasst, mit Smearing zurückgerechnet, chargen-robust
gefehlert; dazu der Sockel a₀ (was ohne Fäulnis im Palox landet) — nur,
wenn die Daten ihn belegen, sonst 0.
**Fehlt eine Eingabe:** eine Arbeit ohne Nenner liefert keinen Punkt
(Auffälligkeit „Ohne Nenner"); ein Leeren ohne Ablesung macht die Menge
unbekannt (Auffälligkeit „Palox geleert"); ohne genügend Punkte gibt es
keine Kurve, und die Kaskade rechnet ohne Verderb — sichtbar.
**Urteil:** ehrlich. Ein Modell je Sorte ist die offene Frage der Saison
(`docs/SAISONBEGLEITUNG.md` § 2) — erst mit genug Punkten je Sorte.

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
Eingang − ausgelagert; auf beide dieselbe Kaskade Verdunstung → Sockel →
Verderb → zu klein/zu gross → Fax.
**Fehlt ein Koeffizient:** er ist unbekannt; die Kaskade lässt seinen
Schritt aus und das Dashboard sagt „nicht gemessen" — sie erfindet keinen.
**Wenn die Rechnung nicht aufgeht:** Überzählung (die Lieferungen brauchen
mehr Eingang, als erfasst ist) — seit 0090 mit den drei Möglichkeiten:
Eingang fehlt, Lieferschein falsch gebucht, Charge besser als das Modell.
**Urteil:** ehrlich; die Ausbeute ist die Stelle, an der ein zu hoher
Koeffizient „Im Lager" zu klein rechnet (Charge 1625) — die Saisonbegleitung
fragt danach.

## 12. Was nirgends erraten wird

- Eine Menge aus einer Zählung ohne Masse (AB-23).
- Ein Netto aus einem Brutto ohne Tara („Ausschuss ohne Tara", „Tara fehlt").
- Ein Sortiertag aus einem Dateistempel (0082).
- Eine Verdunstung über der Grenze (0089).
- Ein Koeffizient aus null Messungen.
