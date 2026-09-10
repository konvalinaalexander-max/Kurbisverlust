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
> 1. **~~Wie kommt die verarbeitete Menge am Waschbecken (Weg 1) zustande?~~ Beantwortet
>    am 3. September:** Es werden Kisten gezählt. Wer die Arbeit eröffnet, trägt das
>    Kaliber ein; wer an der Station steht, zählt die Kisten und das Datum. Das
>    Kistengewicht wird nicht gewogen, sondern beim Sortieren gemessen — dort ist die
>    Masse je Kaliber aus der CSV bekannt und die gefüllten Kisten werden mitgezählt.
>    Offen bleibt daran nur die Umsetzung in der Halle: Zählt beim Sortieren jemand
>    zuverlässig mit? Ohne diese Zählung bleibt die Menge am Waschbecken unbekannt.
> 2. **Für welche Sorte gilt die 8-kg-Kiste?** Die Überfüllung wird heute auf alle
>    Weg-2-Ware hochgerechnet. Gilt die Kiste nur für eine Sorte, ist das zu viel.
> 3. **~~Zeigt die Palox-Waage brutto, und wiegt der Behälter 45 kg?~~ Beantwortet am
>    3. September: ja, brutto, 45 kg.** Der Arbeiter tippt den Stand ein, wie er ihn
>    sieht; die Tara zieht die App im Hintergrund ab, und zwar nur dort, wo der Stand
>    selbst die Menge ist. Die 45 kg stehen als Einstellung `palox_tara_kg` und lassen
>    sich ohne Programmieren ändern.
> 4. **~~Ist das Datum vom Zettel in der Halle durchsetzbar?~~ Beantwortet am
>    3. September: ja, es ist Pflicht.** Ohne Datum nimmt der Zähler keine Palette mehr
>    an, und die Datenbank weist die Zeile ab. Entbehrlich ist es nur dort, wo das Datum
>    ohnehin feststeht (erkannte Palette, Wägung). Offen bleibt die andere Hälfte der
>    Frage: Kommen wirklich die zuletzt eingelagerten Paletten zuerst dran?
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

---

**Aufräum-Notiz (technisch, kein Betriebsthema) — erledigt:** Die Tabelle
`marge_messung` war der frühere Kanal für von Hand eingetippte Marge-Posten;
seit dem 25. August schreibt keine Maske sie mehr, Überfüllung kommt aus
`ausgang_wiegung`, der Nebenkanal aus der CSV. Migration 0048 entfernt Tabelle
und Lese-Stellen — und bricht ab, falls die Tabelle auf dem Betrieb doch noch
Zeilen hält (siehe README, „Wenn etwas klemmt").

---

## Zwei Fragen aus Runde L (9. September)

Beide kommen aus dem Prüfwerk (`pruefwerk/`, Bericht in `docs/PRUEFBERICHT.md`).
Beide sind beziffert und **nicht entschieden**: Es gibt zwei vertretbare
Antworten, und die Wahl gehört dem Betrieb, nicht dem Programm.

**51. Verlust in Prozent — wovon?**
Heute steht auf dem Überblick „16,1 % des Eingangs". Dieselbe Zahl, bezogen auf
das, was noch nicht ausgeliefert ist, wäre **25,1 %** — neun Prozentpunkte
Unterschied bei genau derselben Kilozahl.

Unser Vorschlag ist eine dritte Form, weil die beiden ersten je eine Frage
beantworten und die zweite dabei zwei Bestände mischt: **an der ausgelieferten
Ware 13,1 %, an der liegenden Ware 18,0 %.** Die erste ist die Nachrechnung
(das ist passiert), die zweite die Zahl, an der sich noch etwas ändern lässt.

*Warum es zählt:* Diese Prozentzahl ist die Zahl, die im Gespräch genannt wird.
Wer sie mit einer aus einem anderen Jahr oder von einem anderen Betrieb
vergleicht, vergleicht nur dann richtig, wenn beide denselben Nenner meinen.

> Sollen beide Zahlen stehen, oder eine — und welche?
> Antwort:

**52. Wird zwischen Eingang und Wägung umgestapelt?**
Wenn eine Palette beim Nachwiegen fünf Kisten weniger hat als beim Eingang,
zählt das Gewicht dieser fünf Kisten als verdunstetes Wasser: Die App fragt die
Kistenzahl nur einmal, beim Eingang, und zieht beide Male dieselbe Tara ab. Bei
30 Kisten sind das rund **elf Prozent zu viel auf der Tagesrate** — und die Rate
geht potenziert in jede Verdunstungszahl der Sorte ein.

Zwei Wege, beide vertretbar: Entweder wird beim Wiegen die Kistenzahl neu
gefragt (eine Frage mehr für den Arbeiter, dafür ist der Fehler weg), oder der
Betrieb sagt, dass zwischen Eingang und Wägung nicht umgestapelt wird — dann
bleibt es, wie es ist, und die Annahme steht mit ihrer Grösse in `ABLAUF.md`.

> Kommt es vor? Und wenn ja, wie oft — bei jeder zehnten Palette, oder nie?
> Antwort:

---

## Vier Fragen aus Runde M (10. September)

Beide kommen aus den Werkstätten (`werkstatt/`, Bericht in
`docs/WERKSTATTBERICHT.md`). Beide sind beziffert und **nicht entschieden**.

**53. Darf jeder Angemeldete alle Auswertungen sehen?**
Heute ja. Achtunddreissig gespeicherte Auswertungstabellen — Verlustquoten je
Sorte, Margen je Käufer, Durchsatz je Arbeiter — haben ein Leserecht für jeden
angemeldeten Nutzer. Die Oberfläche zeigt diese Seiten nur dem Betriebsleiter;
sie sind in `src/App.tsx` hinter `istAdmin` weggeschlossen. Aber die Datenbank
ist über PostgREST direkt ansprechbar, und die kennt diese Grenze nicht: Wer
die Adresse und einen gültigen Anmeldeschlüssel hat, liest sie.

*Warum es zählt:* Der Betrieb beschäftigt Saisonkräfte. Ob eine davon die
Marge je Käufer und den Durchsatz je Kollege sehen kann, ist eine Frage über
den Betrieb, nicht über die Datenbank — und sie ist bisher nirgends
beantwortet, sondern nur beiläufig entschieden.

*Was es kostet, es zu ändern:* Ein Teil dieser Tabellen ist für die
Arbeiter-App nötig (Kaliberbänder, Gebindegewichte). Es lässt sich also nicht
pauschal wegnehmen, sondern nur Tabelle für Tabelle — sonst steht der Zähler
am Montag vor einer leeren Maske. Ein halber Tag Arbeit, kein neuer Bildschirm.

> Soll ein Arbeiter die Auswertungen sehen können — alle, keine, oder nur
> die, die seine eigene Arbeit betreffen?
> Antwort:

**54. Auf dem Reiter „Ursachen" steht in jedem fünften Feld ein Strich.**
Gezählt über eine ganze Demosaison: Von den Zahlenfeldern der fünf
Betriebsleiter-Reiter sind auf **Überblick 97.8 %** gefüllt, auf **Chargen
98.5 %**, auf **Messungen 97.3 %**, auf **Betrieb 90.7 %** — und auf
**Ursachen nur 80.6 %**. Vierundzwanzig Spalten dort haben in einem Teil der
Zeilen keinen Wert, drei in keiner einzigen.

Ein Strich ist die richtige Anzeige für Unbekanntes — das ist seit Runde L
ausgemacht, und die Alternative wäre eine erfundene Zahl. Er ist aber nicht
gratis: Wer drei Striche hintereinander sieht, hört auf, dort hinzuschauen.
Und ausgerechnet „Ursachen" ist der Reiter, auf dem nachgesehen wird, wenn
jemand wissen will, woran die Ware fehlt.

*Warum es zählt:* Für jede dieser Spalten gibt es drei mögliche Antworten,
und „lassen wie es ist" ist keine davon. Entweder fehlt eine Messung, die der
Betrieb machen könnte — dann gehört sie in diese Liste. Oder sie ist für
diesen Betrieb nicht vorgesehen — dann gehört die Spalte weg, samt der Stelle,
die sie anzeigt. Oder sie füllt sich erst im Lauf der Saison — dann gehört ein
Satz daneben, der das sagt.

*Was dagegen spricht, es überzubewerten:* Die Demosaison ist nicht der
Betrieb. Und der Reiter zeigt je Sorte **und** je Charge — eine Sorte ohne
eigene Wägung *soll* dort einen Strich haben statt einer geliehenen Zahl ohne
Kennzeichnung. Die Quote ist ein Wegweiser zum Durchsehen, keine Note.

> Sollen wir die Liste der leeren Spalten gemeinsam durchgehen — welche
> Messung fehlt, welche Spalte kann weg?
> Antwort:

**55. Wozu wiegt ihr die Paletten mit dem Zettelgewicht?**
Gemessen, indem diese Messart aus einer Kopie der Datenbank **entfernt** und
alles neu gerechnet wurde: 231 Erfassungen über die Saison, rund **3.9
Arbeitsstunden**. Ohne sie ändert sich der Saisonverlust um **13 kg von
52 301 kg**, und die Summe aller Unsicherheitsbänder um **−40 kg von
28 247 kg**. Beides unter einem halben Prozent, und kein Verluststrom
verstummt.

Zum Vergleich, mit demselben Verfahren: Eine einzelne **Ausschuss-Wägung** ist
**379 kg schmaleres Band** wert — und davon gibt es in der ganzen Saison nur
34.

*Warum es zählt:* Es gibt zwei mögliche Antworten, und nur Du kennst die
richtige. Entweder dient die Messung etwas anderem als der Verlustrechnung —
Rückverfolgbarkeit, Abrechnung, Kontrolle des Arbeitsablaufs. Dann gehört
dieser Zweck aufgeschrieben, damit sie nicht eines Tages als nutzlos
gestrichen wird. Oder sie ist für die Verlustrechnung gedacht und **kommt dort
nicht an** — dann ist nicht die Messung das Problem, sondern der Weg, den sie
durch die Rechnung nimmt, und den kann ich reparieren.

> Wozu dient das Zettelgewicht je Palette? Und wenn es nur der
> Verlustrechnung dienen soll: sollen die 3.9 Stunden stattdessen in
> Ausschuss-Wägungen gehen?
> Antwort:

**56. Kommt es vor, dass dieselbe Beobachtung zweimal erfasst wird?**
In allen sechs Messtabellen kann dieselbe Beobachtung ein zweites Mal
eingetragen werden — nichts verhindert es, und nichts meldet es.
Nachgemessen auf einer Kopie: Eine einzige zusätzliche Zeile in `lieferung`
(die schwerste der Demosaison) verschiebt die Saisonbilanz um **1 888 kg**.
Sie bewegt gleichzeitig Ausgang, Verlust bis heute, Verdunstung, Schimmel und
„noch im Haus".

*Warum es zählt:* Es gibt zwei Wege, und die Wahl gehört dem Betrieb.
**Verhindern:** ein eindeutiger Schlüssel über die Spalten, die eine
Beobachtung ausmachen. Sauber — verbietet aber auch die legitime Wiederholung,
und die gibt es: zwei Paletten derselben Charge mit demselben Gewicht am
selben Tag sind kein Fehler. **Melden:** ein Zweig unter „Auffälligkeiten",
der wortgleiche Zeilen nebeneinanderstellt und fragt „zweimal erfasst oder
zweimal gemessen?". Das ist der Weg, den dieses Programm sonst überall geht —
es hindert niemanden, es zeigt.

> Wie oft passiert es, dass eine Lieferung oder eine Wägung versehentlich
> zweimal eingetragen wird? Und darf dieselbe Zahl zweimal legitim
> vorkommen?
> Antwort:
