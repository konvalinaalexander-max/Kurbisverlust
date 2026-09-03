# Was ich vom Betrieb wissen muss

> **Stand 2. September — das meiste ist beantwortet.**
> Die Antworten stehen als Tatsachen in **`docs/ABLAUF.md`**, nicht mehr hier. Diese Datei
> bleibt als vollständige Liste der einmal gestellten Fragen bestehen.
>
> **Noch offen:** die Preise (für eine Rangfolge in Franken statt in Kilo), welche Massnahme
> aus welchem Ergebnis folgen würde, die übrigen Abgänge neben dem Lieferschein-Verkauf, und
> die Perigon-Vorlage für den Warenausgangs-Import.
>
> **Aus der Prüfung vom 3. September — vier Fragen, die direkt an der Rechnung hängen:**
>
> 1. **Wie kommt die verarbeitete Menge am Waschbecken (Weg 1) zustande?** Der Betrieb
>    hat gesagt, auf Weg 1 werde nie gewogen. Ohne diese Zahl hat der Schimmel, der beim
>    Waschen aussortiert wird, keinen Nenner — die Auswertung meldet ihn dann als „ohne
>    Nenner" und rechnet ihn nirgends ein. Möglich wären: Kaliber-Kisten zählen (dann
>    braucht es einmal ein Kistengewicht je Sorte), oder die Menge aus dem Lieferschein
>    des Tages. Welche Angabe ist am Waschbecken realistisch?
> 2. **Für welche Sorte gilt die 8-kg-Kiste?** Die Überfüllung wird heute auf alle
>    Weg-2-Ware hochgerechnet. Gilt die Kiste nur für eine Sorte, ist das zu viel.
> 3. **Zeigt die Palox-Waage wirklich brutto, und wiegt der Behälter 45 kg?** Beides ist
>    jetzt so hinterlegt (Einstellung `palox_tara_kg`). Zeigt sie netto, gehört die
>    Einstellung auf 0 — sonst fehlen bei jeder ersten Ablesung 45 kg.
> 4. **Welche Paletten kommen zuerst dran — die zuletzt eingelagerten (oben, vorne)?**
>    Das Alter des Bestands wird jetzt aus den noch liegenden Paletten gebildet; das
>    stimmt nur, wenn beim Zählen das Datum vom Zettel eingetragen wird. Ist das
>    Pflichtfeld in der Halle durchsetzbar?
> 5. **Lässt sich beim Leeren des Palox trennen, was faul war und was nicht?** Erde,
>    Hagelnarben und Schnittfehler sind sichtbar etwas anderes als Fäulnis. Eine grobe
>    Angabe je Leeren („davon nicht faul: etwa ein Zehntel") wäre eine Messung. Ohne sie
>    muss die Auswertung den Sockel aus dem Zeitverlauf schätzen — und das gelingt nur
>    in der Saisonmitte in knapp jeder zweiten Saison, am Saisonende nie, weil ein Sockel
>    dort genauso aussieht wie „Schlechtes zuerst verarbeitet" (Messung in
>    `STATISTIK_BEFUND.md`, vierte Runde).
>
> **Was der Palox enthält** (Erde, Blätter, Hagelnarben, Schnittfehler) ist seit dieser
> Prüfung im Modell: als Sockel, den die Auswertung aus den Messungen schätzt und nur
> dann setzt, wenn die Messungen ihn belegen — siehe `ABLAUF.md` und
> `STATISTIK_BEFUND.md`.

Jede Frage hier ist eine Stelle, an der die Software heute etwas **annimmt**.
Solange die Annahme unbestätigt ist, kann die Rechnung danebenliegen, ohne
dass es jemand merkt — und das Ziel des ganzen Werkzeugs ist, die Ursachen zu
**rangieren**. Eine falsche Annahme, die einen Strom um 30 % verschiebt, kann
die Rangfolge kippen und damit die Antwort umdrehen.

Antworten werden unter der jeweiligen Frage eingetragen; was beantwortet ist,
wandert als Fakt nach `ABLAUF.md` und als Annahme aus der Tabelle dort heraus.

- **Teil 1 (1–25)** folgt dem Kürbis durch den Betrieb. Hier geht es darum,
  den Ablauf überhaupt richtig zu verstehen.
- **Teil 2 (26–50)** prüft einzelne Zahlen und Annahmen im Modell.

**Wenn Du nur fünf beantwortest:** 1, 2, 5, 6, 17. Sie hängen alle am selben
Punkt — ob ein Arbeitsgang wirklich zu genau einer Charge gehört.

---

# Teil 1 — Der Kürbis von der Ernte bis zum Lastwagen

## A. Was einen Arbeitsgang auslöst

Das ist der wichtigste Block. Die Datenbank erzwingt heute
`auftrag.charge_nr not null` — **genau eine Charge je Arbeitsgang**. Aller
Schimmel, der in einem Waschgang anfällt, hängt an dieser einen Charge und
bekommt deren Lagerdauer. Stimmt das nicht, steht das Verderbsmodell auf
Punkten mit falschem Alter, und die ganze Kurve verzieht sich.

**1. Was löst einen Arbeitsgang aus?**
Sagt jemand „heute machen wir Charge 1613" — oder „heute machen wir drei
Paletten Tiana, Kaliber 2, für den Kunden am Donnerstag"?
*Warum:* Im zweiten Fall ist der Arbeitsgang durch **Sorte + Kaliber + Menge**
definiert, und die Charge ist bloss ein Nebenprodukt davon — oft mehrere
gleichzeitig. Dann bildet die App den Ablauf grundsätzlich falsch ab.

> Antwort:

**2. Wenn eine Charge für den Kundenwunsch nicht reicht: wird gemischt?**
Und wie viele Chargen kommen typisch in einen Waschgang — eine, zwei, fünf?
*Warum:* Davon hängt ab, ob ich ein Feld ergänze oder das Datenmodell an
dieser Stelle umbaue (Arbeitsgang → mehrere Chargen mit Mengenanteil).

> Antwort:

**3. Werden nur Chargen derselben Sorte gemischt — oder auch verschiedene Sorten in einem Arbeitsgang?**
*Warum:* Sorten haben eigene Kaliber-Grenzen und eigene Verdunstungsraten.
Ein Arbeitsgang über zwei Sorten liesse sich gar nicht mehr auf einen
Koeffizienten beziehen.

> Antwort:

**4. Wie weit liegen die gemischten Chargen im Eingangsdatum auseinander?**
Tage, Wochen oder Monate?
*Warum:* Das entscheidet, wie schlimm das Mischen ist. Sind alle aus derselben
Woche, ist die mittlere Lagerdauer eine gute Näherung. Kommen September und
Januar zusammen in ein Becken, ist der gemessene Schimmel keiner Lagerdauer
mehr zuzuordnen — und genau diese Punkte tragen die Verderbskurve.

> Antwort:

**5. Weiss der Arbeiter am Waschbecken überhaupt noch, aus welcher Charge eine Kiste stammt?**
Steht das auf der Kiste oder der Palette — oder ist es nach dem Sortieren
schlicht nicht mehr erkennbar?
*Warum:* Wenn es nicht erkennbar ist, ist jede Charge-Angabe beim Waschen
geraten, und ich darf sie nicht als Tatsache verrechnen. Dann brauche ich
einen anderen Weg, das Alter zu schätzen — und muss die Unsicherheit
ausweisen, statt sie zu verschweigen.

> Antwort:

**6. Was tippt der Arbeiter heute ein, wenn er mischt?**
Die grösste Charge? Die erste? Irgendeine?
*Warum:* Das sagt mir, was in den bisherigen Daten drinsteht — und ob ich
alte Erfassungen anders lesen muss als neue.

> Antwort:

---

## B. Ernte und Wareneingang

**7. Wird eine Charge irgendwann geschlossen?**
Oder können Wochen später noch Paletten dazukommen, während schon verarbeitet
wird?
*Warum:* Die Eingangsmasse einer Charge ist die Bezugsgrösse für jeden
Prozentsatz. Wächst sie noch, während schon Verlust dagegen gerechnet wird,
verschiebt sich jede Quote rückwirkend.

> Antwort:

**8. Liegt zwischen Feld und Halle etwas — Nachreifen, Abtrocknen, Anhänger über Nacht?**
*Warum:* Die Lagerdauer beginnt heute mit dem Datum auf dem Zettel. Steht die
Ware vorher schon Tage irgendwo, fängt die Uhr zu spät an.

> Antwort:

**9. Wird die Palette am Eingang auf einer richtigen Waage gewogen?**
Staplerwaage, Bodenwaage — oder ist das Brutto gerechnet (Kisten × Erfahrungswert)?
*Warum:* Das Eingangsgewicht ist das Rückgrat der ganzen Rechnung. Ist es
selbst geschätzt, muss der Bereich um **alles** breiter werden.

> **Antwort (teilweise):** Auf dem Maschinen-Weg werden Paletten **nie** gewogen — weder vor
> noch nach der Maschine. Verdunstung ist damit nur über Weg 2 und die Lagerkontrolle
> messbar. Ob am Wareneingang selbst gewogen wird, ist weiterhin offen.
> Antwort:

**10. Wird schon im Feld oder beim Einlagern aussortiert?**
Kaputte, angefaulte, viel zu kleine.
*Warum:* Was nie in die Halle kommt, steht in keinem Eingang — dieser Verlust
ist heute komplett unsichtbar, und er könnte grösser sein als manches, was ich
messe.

> Antwort:

---

## C. Die Halle

**11. Wie liegen die Paletten — gestapelt, und wie hoch?**
Kommt man an jede heran, oder nur an die oberste und die vorderste?
*Warum:* Das Modell rechnet seit dieser Runde mit **zufälliger Entnahme**
(jede Palette hat jeden Tag dieselbe Chance). Sind sie zwei oder drei hoch
gestapelt, nimmt man in Wahrheit oben zuerst — also das Jüngste zuerst. Dann
werden systematisch junge Paletten gemessen und alte nie, und die Kurve wird
flacher gemessen, als sie ist.

> Antwort:

**12. Sind die Paletten nach Sorte gruppiert, nach Eingangsdatum, oder wie es gerade passte?**
*Warum:* Eine Ordnung nach Datum erzeugt eine Entnahme-Reihenfolge, eine nach
Sorte nicht. Beides ändert, was eine „zufällig gegriffene" Palette wirklich
ist.

> Antwort:

**13. Werden Paletten während der Saison umgestapelt, zusammengelegt oder umgepackt?**
Zwei halbe zu einer ganzen, Faules zwischendurch heraussuchen.
*Warum:* Dann stimmen Kistenzahl und Zettel-Gewicht nicht mehr zusammen — und
die Palettenwägung („Brutto damals gegen Brutto jetzt") misst eine Palette,
die es so nicht mehr gibt. Und heimlich entferntes Faules ist Verlust, den
niemand erfasst.

> Antwort:

**14. Wer entscheidet, welche Palette als nächstes drankommt — und wonach?**
Alter, Aussehen, Erreichbarkeit, Kundenwunsch?
*Warum:* Das ist laut `ABLAUF.md` die grösste verbliebene Fehlerquelle. Wird
verarbeitet, was schlecht aussieht, misst man Anfälligkeit statt Alter.

> Antwort:

---

## D. Sortieren (Weg 1)

**15. Wird für jeden Chargenwechsel wirklich eine neue Datei begonnen?**
Auch wenn zwei Chargen derselben Sorte direkt hintereinander laufen?
*Warum:* Die Zuordnung CSV → Auftrag hängt daran. Eine Datei über zwei Chargen
vermengt zwei Eingangsmassen und zwei Lagerdauern in einem Histogramm.

> **Erledigt anders:** Das Datum der CSV ist nicht nötig — die Chargennummer genügt. Siehe
> `ABLAUF.md`, Abschnitt „Braucht die Sortier-CSV ein Datum?".
> Antwort:

**16. Wie viele Paletten laufen typisch in einem Sortierlauf, und wie lange dauert er?**
*Warum:* Die Zuordnung sucht den zeitlich nächsten Auftrag. Läuft die Maschine
den ganzen Tag durch, während drei Arbeiten eröffnet und geschlossen werden,
ist „nächstliegend" nicht mehr eindeutig.

> Antwort:

**17. Wo landen die sortierten Kürbisse — bleiben die Kaliber-Kisten pro Charge getrennt?**
Oder wird eine angefangene Kiste später mit einer anderen Charge vollgemacht?
*Warum:* Wird vollgemacht, ist die Charge im Zwischenlager verloren, noch bevor
gewaschen wird. Dann ist Frage 5 schon beantwortet — negativ — und Schimmel #2
lässt sich grundsätzlich nicht mehr zuordnen.

> Antwort:

**18. Ist die Kaliber-Kiste beschriftet — und womit?**
Sorte, Kaliber, Charge, Datum?
*Warum:* Das ist die billigste denkbare Verbesserung des ganzen Systems. Steht
die Charge (oder auch nur das Sortierdatum) drauf, ist die Zuordnung beim
Waschen eine Ablesung statt einer Schätzung.

> **Antwort:** ✓ Der Betrieb kann das **Sortierdatum** draufschreiben lassen. Beim Waschen
> wird danach gefragt, mit der Möglichkeit zu überspringen. Was sonst schon draufsteht, ist
> noch offen (Frage 16 im neuen Bündel).
> Antwort:

---

## E. Waschen und Packen

**19. Nimmt der Kürbis beim Waschen Wasser auf — und wird er getrocknet?**
Wiegt eine gewaschene Kiste anders als dieselbe ungewaschen?
*Warum:* Die Kiste wird nach dem Waschen gewogen, das Lager davor. Bleibt
Oberflächenwasser dran, ist die „Überfüllung" teils Wasser und keine
verschenkte Ware.

> Antwort:

**20. Wer füllt die 8-kg-Kisten, und steht dort eine Waage?**
Wird jede Kiste gewogen oder nach Gefühl gefüllt und stichprobenweise geprüft?
*Warum:* Wenn nach Gefühl gefüllt wird, ist die Überfüllung eine
Streuungsfrage und keine Einstellungsfrage — und die Massnahme wäre eine
Waage, nicht ein anderer Zielwert.

> Antwort:

**21. Sind das die Kisten des Kunden (IFCO) oder eigene — und kommen sie zurück?**
*Warum:* Die Tara je Kistenart trägt die ganze Netto-Rechnung. Wechselnde oder
nasse Kisten verschieben sie systematisch.

> Antwort:

---

## F. Ausgang und Rückverfolgbarkeit

**22. Steht auf dem Lieferschein die Charge — und muss der Betrieb rückverfolgen können, welche Charge zu welchem Kunden ging?**
Suisse Garantie, GlobalGAP, Lebensmittelrecht.
*Warum:* Das ist die vielleicht wertvollste Frage der ganzen Liste. Besteht
eine Rückverfolgungspflicht, **gibt es diese Zuordnung schon** — irgendwo auf
Papier oder im Lieferschein-Programm. Dann muss ich das Mischen nicht schätzen,
sondern kann es ablesen.

> Antwort:

**23. Geht je Ware ungewaschen raus?**
Direkt aus dem Lager an einen Kunden, in den Hofladen, an Selbstabholer.
*Warum:* Das Modell nimmt an: **alles**, was sortiert wurde, wird später
gewaschen. Ware, die ungewaschen rausgeht, altert in der Rechnung weiter,
obwohl sie längst weg ist.

> Antwort:

**24. Gibt es mehr als eine Halle oder ein Aussenlager?**
*Warum:* „Eine Halle, gleiche Bedingungen für alle" ist eine tragende Annahme
der Statistik. Zwei Orte mit unterschiedlicher Temperatur brauchen zwei
Verdunstungsraten.

> Antwort:

---

## G. Wer erfasst — und kann er das überhaupt

**25. Wer tippt die Zahlen realistisch ein, und wie viele Leute arbeiten gleichzeitig an einer Station?**
Der am Waschbecken mit nassen Händen, oder einer, der danebensteht? Gibt es
Empfang oder WLAN in der Halle?
*Warum:* Eine Messung, die im Arbeitsablauf nicht vorkommt, findet nicht
statt — und dann rechnet das Werkzeug elegant mit nichts. Und arbeiten zwei
Teams parallel an derselben Station, stimmt die Palox-Differenzrechnung nicht
mehr (jede Ablesung zieht die andere ab).

> **Teilantwort:** Die Palox-Ablesung übernimmt, wer den Auftrag eröffnet, und wer ihn
> abschliesst. Wie viele Gruppen gleichzeitig an einer Station arbeiten, ist weiterhin
> offen — und entscheidet, ob eine Behälter-Kennung nötig wird.
> Antwort:

---

# Teil 2 — Einzelne Annahmen im Modell

Diese Fragen standen schon vorher offen. Sie prüfen Zahlen und Annahmen, nicht
den Ablauf selbst.

**Die fünf wichtigsten hier:** 26, 30, 35, 42, 49.

## Was am Eingang gewogen wird

Gewaschen wird erst ganz am Schluss. Das Eingangs-Brutto enthält also
Feld-Erde, das Ausgangsgewicht nicht.

**26. Wie viel Erde hängt am Kürbis, wenn er ins Lager kommt?**
Ein Gefühl genügt (unter 1 %? gegen 5 %?). Oder wurde je eine Palette vor und
nach dem Waschen gewogen?
*Warum:* Diese Differenz ist Masse, die zwischen Eingang und Ausgang
verschwindet, ohne ein Verlust zu sein. In der Saisonbilanz sieht sie aus wie
Verlust, und in der Verdunstungsrate steckt sie womöglich mit drin.

> Antwort:

**27. Fällt oder trocknet die Erde im Lager ab?**
*Warum:* Die Verdunstungsrate wird als „Brutto damals − Brutto jetzt" derselben
Palette gemessen. Fällt Erde ab, misst das teils Erde statt Wasser — die Rate
wäre systematisch zu hoch, und Verdunstung steht heute auf Platz 1.

> Antwort:

**28. Ist das Datum auf dem Zettel der Erntetag oder der Einlagerungstag?**
Und liegen dazwischen je Tage (Anhänger, Zwischenlager, Wochenende)?
*Warum:* An diesem Datum hängt jede Lagerdauer und damit die ganze
Verderbskurve.

> Antwort:

**29. Gibt es Zukauf — Ware von anderen Betrieben?**
*Warum:* Die käme nicht aus dem Erntejournal, hätte also keinen Eingang. Sie
würde beim Verarbeiten als Masse auftauchen, die es laut Bilanz nie gab.

> Antwort:

---

## Der Palox, die einzige direkte Schimmelmessung

**30. Was landet alles im Palox?**
Nur Faules — oder auch zu Kleines, Erde, Blätter, kaputte Kisten?
*Warum:* Alles, was mit hineinfällt, verbucht die Software heute als
Schimmel. Landen die zu Kleinen dort mit drin, wird Ausschuss als Fäulnis
gezählt und beide Ströme sind falsch — der eine zu gross, der andere zu klein.

> Antwort:

**31. Steht der Palox wirklich auf einer Waage — und zeigt sie brutto oder netto?**
Falls brutto: ist es immer derselbe Behälter mit demselben Leergewicht?
*Warum:* Die Software rechnet mit der Differenz zweier Ablesungen. Wechselt
der Behälter zwischendurch, springt die Differenz um sein Leergewicht.

> Antwort:

**32. Wie viele Paloxe stehen je Station?**
*Warum:* Das Modell nimmt genau einen je Station an (Sortierband,
Waschbecken, Hand-Linie). Zwei Teams parallel am selben Platz mit zwei
Behältern bringen die Differenzrechnung durcheinander.

> Antwort:

**33. Wird das Leeren zuverlässig gemeldet?**
Und leert ihn je jemand, der gerade keine Arbeit offen hat — abends, der
Stapler, am Wochenende?
*Warum:* Ein unbemerktes Leeren macht die nächste Differenz negativ oder
falsch klein. Es gibt ein Häkchen dafür, aber nur, wenn jemand es setzt.

> Antwort:

**34. Wird immer am Ende einer Arbeit abgelesen?**
*Warum:* Die abgelesene Menge wird der Arbeit zugeschrieben, an deren Ende sie
steht. Sammelt der Palox über mehrere Arbeiten weiter, ohne dass jemand
abliest, sitzt der Schimmel am falschen Lager-Alter.

> Antwort:

---

## Was „zu klein" und „zu gross" wirklich sind

**35. Was passiert physisch mit den zu Kleinen?**
Kompost, Tierfutter, Hofladen, Suppenkürbis — oder wirklich weg?
*Warum:* Die Software verbucht sie als **Totalverlust**. Gehen sie an Tiere
oder in den Verkauf, sind sie kein Verlust, sondern ein anderer Kanal. Dann
schrumpft ein ganzer Balken im Ranking auf null.

> Antwort:

**36. Und die zu Grossen — gibt es dafür wirklich einen Abnehmer und einen Preis?**
*Warum:* Die Software nennt sie „Nebenkanal, kein Verlust". Ist es in
Wahrheit auch Kompost, fehlt ein Verlust in der Rechnung.

> Antwort:

**37. Kommen die zu Kleinen überhaupt aufs Sortierband?**
Oder werden sie schon im Feld oder beim Einlagern aussortiert?
*Warum:* Der Ausschuss-Koeffizient kommt aus der Sortier-CSV. Was nie aufs
Band kommt, taucht dort nicht auf — der Ausschuss wäre dann systematisch zu
niedrig gemessen.

> Antwort:

**38. Auf der Hand-Linie: wird „zu klein / zu gross" gewogen oder geschätzt?**
Und in welchem Behälter landet es?
*Warum:* Die Spec sagt „nach Auge, locker". Wenn geschätzt wird, muss der
Bereich um diesen Strom breiter sein, als er heute ist.

> Antwort:

---

## Sortierband und CSV

**39. Wiegt die Maschine vor dem Waschen — also mit Erde dran?**
Und sind die Kaliber-Grenzen des Abnehmers auf schmutzigem oder gewaschenem
Gewicht definiert?
*Warum:* Wenn die Maschine schmutzig wiegt und der Abnehmer sauber zählt,
sind alle Kaliber-Zuordnungen systematisch um das Erdgewicht verschoben —
und der Ausschuss „zu klein" wird zu klein gemessen.

> Antwort:

**40. Bleibt eine Kaliber-Kiste chargenrein?**
Wenn nach Charge A gleich Charge B über dasselbe Band läuft: kommen die in
dieselbe Kiste?
*Warum:* Dann ist die Charge-Identität weg, und der Schimmel, der später beim
Waschen aussortiert wird, lässt sich keiner Lagerdauer mehr zuordnen.

> Antwort:

**41. Läuft je ein Kürbis zweimal über das Band?**
Rücklauf, Nachsortieren, Bandstau.
*Warum:* Dann zählt die CSV ihn doppelt. Die Dubletten-Regel fängt nur direkt
aufeinanderfolgende Doppel ab, keinen späteren zweiten Durchlauf.

> Antwort:

---

## Lager und Zeit

**42. Ist die Halle geheizt oder temperiert — oder folgt sie dem Wetter?**
Gibt es Lüftung? Weiss jemand ungefähr die Temperaturen über die Saison?
*Warum:* Das Modell nimmt eine über die ganze Saison **konstante**
Verdunstungsrate an. Von September (mild) bis März (kalt) ist das kaum
richtig. Dann wird die frühe Verdunstung unter- und die späte überschätzt —
und die Hochrechnung auf lange Lagerdauern zieht sich mit.

> Antwort:

**43. Liegen wirklich alle Paletten unter gleichen Bedingungen?**
Aussenwand gegen Mitte, oben gegen unten, beim Tor gegen hinten.
*Warum:* Das Modell behandelt die Halle als einen Ort. Systematische
Unterschiede landen sonst im Fehlerbereich statt im Modell.

> Antwort:

**44. Was passiert am Saisonende mit dem Rest?**
Weg, oder in die neue Saison? Und bleibt er dann derselben Charge zugerechnet?
*Warum:* Das Modell kennt nur „bis zum Stichtag gelagert" und weiss nicht,
was danach kommt.

> Antwort:

---

## Was den Betrieb sonst verlässt

**45. Welche Abgänge gibt es neben dem Lieferschein-Verkauf, und wie gross sind sie ungefähr?**
Hofladen, Tierfutter, Eigenbedarf/Personal, Kompost, Geschenke.
*Warum:* Was nicht erfasst ist, sieht in der Bilanz aus wie Verlust. Selbst
grobe Monatssummen je Weg helfen.

> Antwort:

**46. In welcher Einheit steht die Menge auf dem Lieferschein — Kilo oder Kisten?**
*Warum:* Beides geht, Kisten werden umgerechnet. Die Antwort ändert nur, wie
genau die Gegenprobe schliesst.

> Antwort:

**47. Gibt es Rückläufer oder Reklamationen?**
Ware, die zurückkommt und dann entsorgt wird.
*Warum:* Sie wäre doppelt gezählt — einmal als Ausgang, einmal nicht als
Verlust.

> Antwort:

---

## Wozu das Ganze: das entscheidet, was genau genug sein muss

**48. Was würdest Du ändern, wenn Verdunstung gewinnt? Was bei Schimmel? Was bei Ausschuss?**
*Warum:* Wenn zwei Ursachen zur selben Massnahme führen, muss ich sie gar
nicht auseinanderhalten — dafür andere umso schärfer. Heute sagt das
Dashboard „Schimmel und Ausschuss sind nicht auseinanderzuhalten". Ob das
schlimm ist, hängt allein an dieser Antwort.

> Antwort:

**49. Soll die Rangfolge in Kilo oder in Franken sein?**
*Warum:* In Kilo gewinnt heute die Verdunstung. In Franken kann es kippen:
Auf der Maschinen-Linie wird **pro Stück je Kaliber** bezahlt — ein leichterer
Kürbis kostet dort erst etwas, wenn er ins nächsttiefere Band rutscht. Auf der
Hand-Linie wird **pro Kiste ab 8 kg** bezahlt — dort kostet Verdunstung sofort.
Schimmel kostet dagegen immer den ganzen Kürbis. Mit Deinen Preisen kann ich
beide Rangfolgen nebeneinander zeigen; ohne sie bleibt es bei Kilo.

> **Teilantwort:** Die 8-kg-Kiste gilt nur für **eine** Sorte; andere werden nach Kategorien
> sortiert. Die Preisfrage selbst bleibt offen.
> Antwort:

**50. Die 8-kg-Kiste: gibt es eine geforderte Mindestmenge mit Toleranz?**
Muss sie garantiert ≥ 8.0 kg sein, oder ist 8.0 ein Zielwert?
*Warum:* Muss sie garantiert darüber liegen, ist ein Zuschlag Absicht und kein
Fehler — dann ist nicht die Überfüllung das Problem, sondern die Streuung beim
Füllen. Das ist eine andere Massnahme.

> Antwort:
