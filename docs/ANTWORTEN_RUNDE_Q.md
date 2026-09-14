# Die Antworten des Betriebs — 14.09.2026

Die fünfzehn Fragen aus `docs/Die-Arbeiter-App.pdf`, Kapitel 11, beantwortet.
Was hier steht, gilt. Wo es dem Auftrag `docs/PROMPT_RUNDE_Q.md` widerspricht,
gilt diese Datei, und der Auftrag ist entsprechend nachgezogen.

---

## 1 — Die Reihenfolge

Das Bild stimmt.

## 2 — Wer tippt

Einer leitet die Arbeit an, die anderen zählen nur. **Es zählt immer nur einer
gleichzeitig.** Geht er in die Pause, soll ein anderer der Arbeit über sein
eigenes Handy beitreten und weiterzählen können.

> Folge: Der Beitritt zu einer laufenden Arbeit muss ohne Umweg funktionieren
> (`auftrag_teilnehmer` gibt es; der Weg dorthin ist zu prüfen und, wo nötig,
> sichtbarer zu machen). Kein Zwang zu einem „Vorarbeiter-Handy".

## 3 — Kistensystem

Aus einer Wascharbeit geht **nur eines**: Kiste ab x kg, *oder* x Kürbisse je
Kiste, *oder* anderes. Nicht gemischt.

> Die Voreinstellung war richtig. Keine Änderung.

## 4 — Palox

- **a)** Zwischendurch leeren **kommt vor**. Die Frage bleibt, aber sie darf
  nicht im Kleingedruckten verschwinden.
- **b)** Zwei Arbeiten gleichzeitig an derselben Waschstrasse: **nein**.
- **c)** Beide Boxen 45 kg — und weil nur die Differenz zählt, ist es ohnehin
  gleichgültig.

## 4.3 — Eine Korrektur am Dokument

> „warum sagst du es ist die einzige stelle bei der die app weiss wie alt? bei
> waschen und sortieren auch - oder nicht?"

Richtig. Das Eingangsdatum steht an **zwei** Stationen auf dem Zettel:
Sortieren **und** Waschen + Sortieren. Kapitel 4.3 behauptete, das Sortieren
sei die einzige Stelle. Das ist falsch und ist korrigiert.

## 5 — Die Sortier-CSV

- **a)** Die CSV kann **immer** hochgeladen werden.
- **b)** Bei jedem Chargenwechsel wird das der Maschine mitgeteilt, und sie
  beginnt eine **neue Datei**. Eine Datei gehört also zu genau einer Charge.
- **c)** Die Maschine **wirft zu klein und zu gross mechanisch aus** — sie
  misst nicht nur, sie sortiert. Es entstehen auch Paletten mit zu klein und
  zu gross; damit beschäftigen wir uns vorläufig nicht.

### Und der wichtigste Satz dieser Runde

> „du weisst nicht wieviele kürbisse mit diesem durchschnittlichen gewicht auf
> einer palette landen - weil selbst wenn du die kistenzahl weisst, weisst du
> nicht wieviele kürbisse pro kiste - weil die werden halt so reingedrückt wies
> halt platz hat"

Damit ist bestätigt: **kg je G2-Kiste eines Kaliberbandes ist nicht messbar.**
Der Weg „Kisten rein × kg je Kiste" ist tot, und zwar endgültig.

### Der Ausweg, den der Betrieb selbst gefunden hat

> „du siehst ja dann anzahl paletten - mit anzahl kisten und total vom brutto
> gewicht - dann weisst du wieviel sortiert worden ist"

Das ist der Schlüssel, und er verlangt **eine Änderung am Sortieren**: dort
muss das **Zettelgewicht Pflicht werden** (heute nur bei Waschen + Sortieren).
Dann gilt:

```
Masse in die Sortiermaschine  =  Σ_Eingangspaletten ( Zettel-Brutto
                                   − Kisten × Tara_Kiste − Tara_Palette )
                                 × (1 − r) ^ (Sortiertag − Eingangsdatum)
                                   ── die Verdunstung bis zum Sortiertag ──

Aufteilung auf die Kaliberbänder  =  aus der CSV
                                     ( Σ gewicht_g × anzahl je Band )

  →  Masse je Kaliberband einer Charge, am Sortiertag. Gemessen, nicht
     geschätzt — und ohne je eine Kiste zählen zu müssen.
```

Seine eigene Einschränkung ist berechtigt und wird ausgewiesen:

> „aber ist das genau - vlt ergibt es dann ja 2.5 kaliberpaletten - ist dann
> der durchschnitt zu gebrauchen?"

Die **Bandmasse** ist genau. Was daraus je *Kaliber-Palette* wird, ist ein
Mittelwert über wenige Paletten und bleibt grob. Die App rechnet deshalb auf
Bandebene und zeigt die Palettenzahl nur als Anhalt — mit der Zahl der
Paletten, über die gemittelt wurde, daneben.

## 6 — Zu gross

Vorläufig nur ausweisen. Für die Arbeiter-App **nicht wichtig**. Verschoben.

## 7 — Die drei Wägungen vor dem Waschen

Bleibt eine **Erinnerung**, kein Zwang. Die Kontrollpalette kommt ohnehin.

## 8 — Kisten je Palette

- **a)** In der Regel **36 G2-Kisten je Palette**. Vorbelegen, anpassbar lassen.
  Und ja — auch **beim Sortieren** fragen.
- **b)** Es sind teils 32, teils 36. Also **immer fragen**, nie annehmen.
- **c)** Im Lager „meistens G2, aber auch nur so 95 %". Die Gebindeart muss
  also gefragt werden, nicht vorausgesetzt.

> Folge: `einstellung('kisten_pro_palette')` von 32 auf **36**. Die Zahl bleibt
> je Palette änderbar und wird nirgends als fest angenommen.

## 9 — Das Erntejournal

> „das sollst du selber checken vom erntejournal - schau dass da eine gewisse
> intelligenz drin ist im programm - vlt kann ich ja irgendwo dann in den
> einstellungen angeben - nun ernte vorbei - und dann inkludiert das system
> diese angabe"

**Ich habe keinen Zugang zum Erntejournal.** In dieser Sitzung liegen nur die
Tabellenstruktur (`palette` mit Eingangsdatum, Brutto, Kisten, Gebinde) und die
von einer KI erzeugten Beispieldaten. Solange die Datei fehlt, kann ich die
Streuung der Erntedaten nicht messen.

Was stattdessen gebaut wird, und was besser ist als eine einmalige Auswertung:
die App rechnet die Streuung **selbst**, laufend, aus den importierten
Eingangspaletten — und ein Schalter sagt ihr, wann eine Charge vollständig ist.

- `charge.ernte_abgeschlossen_ts` — ab dann ist das massegewichtete mittlere
  Eingangsdatum endgültig und die Spanne belastbar.
- `einstellung('ernte_abgeschlossen')` für die ganze Saison auf einen Schlag.
- Bis dahin steht bei jeder Altersangabe „Ernte läuft noch".

## 10 — Die fertige Palette

- **a)** Ja, die letzte ist oft nicht voll: „die ersten beiden Paletten je 40
  Kisten IFCO, die letzte vielleicht nur 24". Deshalb beim Wägen der fertigen
  Palette **immer** Kistenzahl **und** Gebindeart fragen.
- **b)** Nie eine feste Kistenzahl annehmen — **immer fragen**.
- **c)** Kürbisse je Kiste wird beim Gewichtssystem **nicht gezählt**.
  → Pflicht nur bei `stueck`.

## 11 — Die Wartezeit an der Fax

- **a)** Es gibt dort **kein Datum**. Der Mann an der Fax kann es nicht wissen.
- **b)** „vlt gehen wir einfach von durchschnitt von 4 tagen aus - aber ich
  vermute dort eh sehr wenig verlust."
- **c)** An der Fax ist die Ware **immer gewaschen**.

> Folge: Die App schlägt weiterhin vor, was sie aus den Daten weiss (und sucht
> dabei künftig auch `waschen_sortieren`, nicht nur `waschen`). Findet sie
> nichts, steht **4 Tage** da — ausdrücklich als Annahme gekennzeichnet, nicht
> als Messung.

## 12 — Wege ohne Lieferschein

Verschoben. Zuerst die Arbeiter-App.

## 13 — Die Kontrollpalette

- **a)** Machbar. „sag mir einfach genau was du brauchst."
- **b)** Nicht alle Sorten — **fünf Chargen**, die ertragswichtigsten.
- **c)** „wir glauben jetzt zu beginn hats viel schock" → am Anfang dichter
  messen als später.
- **d)** Am Ende der Saison verarbeiten und das Faule wiegen: **ja**.
  Wöchentlich Faules zählen: **nein**, das geht nicht.

### Was gebraucht wird — die genaue Antwort auf „sag mir was du brauchst"

| | |
|---|---|
| **Wie viele** | Fünf. Die App schlägt die fünf ertragsstärksten Chargen aus den Eingangsdaten vor; der Betriebsleiter bestätigt oder wählt andere. |
| **Was drauf muss** | Ein Kennzeichen, das man von weitem liest, und der Satz „nicht verarbeiten". Die App speichert das Kennzeichen, damit man sie wiederfindet. |
| **Wann wiegen** | Monat 1: alle **14 Tage** (der Schock). Ab Monat 2: **monatlich**. Die App erinnert und zeigt, welche überfällig ist. |
| **Was erfassen** | Brutto, Kistenzahl, Gebindeart, „Schimmel sichtbar?". Vier Angaben, eine Minute. |
| **Wie oft mindestens** | Zwei Wägungen ergeben eine Rate. Vier ergeben eine Aussage darüber, **ob** die Rate fällt. |
| **Am Ende** | Verarbeiten, Faules wiegen, `beendet_ts` setzen. Das ist ein Verderbspunkt mit exakt bekanntem Alter — der genaueste, den es geben kann. |

## 14 — Sorte oder Schlag

> „absolut keine ahnung"

Bleibt bei der Voreinstellung: gruppiert wird **je Sorte**. Die Gruppierung
steht an genau einer Stelle im Code, damit ein Wechsel auf den Schlag später
eine Zeile ist und nicht zehn.

## 15 — Gemischte Arbeiten

Nicht beantwortet. Bleibt bei der Voreinstellung: gemischte Arbeiten fallen aus
der Alterskurve, ihre Messungen bleiben erhalten.

---

## Was sich am Auftrag dadurch ändert

| Nr. | Vorher im Auftrag | Jetzt |
|---|---|---|
| **Q6** | `fertige_paletten_gesamt` ist Pflicht | **Nicht Pflicht.** „die fertigen paletten werden eher nicht gezählt". Gefragt, vorbelegt mit der Zahl der gewogenen Paletten, überspringbar. Fehlt sie, ist die Ausgangsmasse unbekannt — und das steht dann auch da. |
| **neu Q18** | — | **Zettelgewicht auch beim Sortieren Pflicht.** Damit wird die Masse je Kaliberband aus Zettel + CSV rechenbar — der Weg, den der Betrieb selbst gefunden hat. |
| **neu Q19** | — | **Kisten je Eingangspalette auch beim Sortieren fragen**, vorbelegt mit 36, immer änderbar. |
| **Q8** | Kistenzähler je Kaliber fällt weg | Bleibt so. Ersatz ist jetzt aber nicht „irgendwann die CSV", sondern die Rechnung aus Q18. |
| **Q10** | Fax-Vorschlag sucht beide Stationen | Zusätzlich: findet er nichts, **4 Tage** als ausgewiesene Annahme. |
| **Q11** | eine Kontrollpalette je Sorte, monatlich | **Fünf Chargen**, erste vier Wochen alle 14 Tage, danach monatlich, am Ende verarbeiten. |
| **neu Q20** | — | **`kisten_pro_palette` von 32 auf 36.** |
| **neu Q21** | — | **Ernte-abgeschlossen-Schalter** je Charge und für die Saison. |
| **neu Q22** | — | **Einer Arbeit beitreten** muss ohne Umweg gehen (Schichtwechsel, Pause). |
| **Q6, Frage 6** | zu gross klären | Verschoben — für die Arbeiter-App nicht wichtig. |
