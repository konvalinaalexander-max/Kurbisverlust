# Was ich vom Betrieb wissen muss

Jede Frage hier ist eine Stelle, an der die Software heute etwas **annimmt**.
Solange die Annahme unbestätigt ist, kann die Rechnung danebenliegen, ohne
dass es jemand merkt — und das Ziel des ganzen Werkzeugs ist, die Ursachen zu
**rangieren**. Eine falsche Annahme, die einen Strom um 30 % verschiebt, kann
die Rangfolge kippen und damit die Antwort umdrehen.

Die Fragen sind nach Wirkung geordnet, nicht nach Bequemlichkeit. Antworten
werden unter der jeweiligen Frage eingetragen; was beantwortet ist, wandert
als Fakt nach `ABLAUF.md` und als Annahme aus der Tabelle dort heraus.

**Die fünf, die am meisten bewegen:** 1, 5, 10, 17, 24.

---

## 1 — Was am Eingang gewogen wird

Gewaschen wird erst ganz am Schluss. Das Eingangs-Brutto enthält also
Feld-Erde, das Ausgangsgewicht nicht.

**1. Wie viel Erde hängt am Kürbis, wenn er ins Lager kommt?**
Ein Gefühl genügt (unter 1 %? gegen 5 %?). Oder wurde je eine Palette vor und
nach dem Waschen gewogen?
*Warum:* Diese Differenz ist Masse, die zwischen Eingang und Ausgang
verschwindet, ohne ein Verlust zu sein. In der Saisonbilanz sieht sie aus wie
Verlust, und in der Verdunstungsrate steckt sie womöglich mit drin.

> Antwort:

**2. Fällt oder trocknet die Erde im Lager ab?**
*Warum:* Die Verdunstungsrate wird als „Brutto damals − Brutto jetzt" derselben
Palette gemessen. Fällt Erde ab, misst das teils Erde statt Wasser — die Rate
wäre systematisch zu hoch, und Verdunstung steht heute auf Platz 1.

> Antwort:

**3. Ist das Datum auf dem Zettel der Erntetag oder der Einlagerungstag?**
Und liegen dazwischen je Tage (Anhänger, Zwischenlager, Wochenende)?
*Warum:* An diesem Datum hängt jede Lagerdauer und damit die ganze
Verderbskurve.

> Antwort:

**4. Gibt es Zukauf — Ware von anderen Betrieben?**
*Warum:* Die käme nicht aus dem Erntejournal, hätte also keinen Eingang. Sie
würde beim Verarbeiten als Masse auftauchen, die es laut Bilanz nie gab.

> Antwort:

---

## 2 — Der Palox, die einzige direkte Schimmelmessung

**5. Was landet alles im Palox?**
Nur Faules — oder auch zu Kleines, Erde, Blätter, kaputte Kisten?
*Warum:* Alles, was mit hineinfällt, verbucht die Software heute als
Schimmel. Landen die zu Kleinen dort mit drin, wird Ausschuss als Fäulnis
gezählt und beide Ströme sind falsch — der eine zu gross, der andere zu klein.

> Antwort:

**6. Steht der Palox wirklich auf einer Waage — und zeigt sie brutto oder netto?**
Falls brutto: ist es immer derselbe Behälter mit demselben Leergewicht?
*Warum:* Die Software rechnet mit der Differenz zweier Ablesungen. Wechselt
der Behälter zwischendurch, springt die Differenz um sein Leergewicht.

> Antwort:

**7. Wie viele Paloxe stehen je Station?**
*Warum:* Das Modell nimmt genau einen je Station an (Sortierband,
Waschbecken, Hand-Linie). Zwei Teams parallel am selben Platz mit zwei
Behältern bringen die Differenzrechnung durcheinander.

> Antwort:

**8. Wird das Leeren zuverlässig gemeldet?**
Und leert ihn je jemand, der gerade keine Arbeit offen hat — abends, der
Stapler, am Wochenende?
*Warum:* Ein unbemerktes Leeren macht die nächste Differenz negativ oder
falsch klein. Es gibt ein Häkchen dafür, aber nur, wenn jemand es setzt.

> Antwort:

**9. Wird immer am Ende einer Arbeit abgelesen?**
*Warum:* Die abgelesene Menge wird der Arbeit zugeschrieben, an deren Ende sie
steht. Sammelt der Palox über mehrere Arbeiten weiter, ohne dass jemand
abliest, sitzt der Schimmel am falschen Lager-Alter.

> Antwort:

---

## 3 — Was „zu klein" und „zu gross" wirklich sind

**10. Was passiert physisch mit den zu Kleinen?**
Kompost, Tierfutter, Hofladen, Suppenkürbis — oder wirklich weg?
*Warum:* Die Software verbucht sie als **Totalverlust**. Gehen sie an Tiere
oder in den Verkauf, sind sie kein Verlust, sondern ein anderer Kanal. Dann
schrumpft ein ganzer Balken im Ranking auf null.

> Antwort:

**11. Und die zu Grossen — gibt es dafür wirklich einen Abnehmer und einen Preis?**
*Warum:* Die Software nennt sie „Nebenkanal, kein Verlust". Ist es in
Wahrheit auch Kompost, fehlt ein Verlust in der Rechnung.

> Antwort:

**12. Kommen die zu Kleinen überhaupt aufs Sortierband?**
Oder werden sie schon im Feld oder beim Einlagern aussortiert?
*Warum:* Der Ausschuss-Koeffizient kommt aus der Sortier-CSV. Was nie aufs
Band kommt, taucht dort nicht auf — der Ausschuss wäre dann systematisch zu
niedrig gemessen.

> Antwort:

**13. Auf der Hand-Linie: wird „zu klein / zu gross" gewogen oder geschätzt?**
Und in welchem Behälter landet es?
*Warum:* Die Spec sagt „nach Auge, locker". Wenn geschätzt wird, muss der
Bereich um diesen Strom breiter sein, als er heute ist.

> Antwort:

---

## 4 — Sortierband und CSV

**14. Wiegt die Maschine vor dem Waschen — also mit Erde dran?**
Und sind die Kaliber-Grenzen des Abnehmers auf schmutzigem oder gewaschenem
Gewicht definiert?
*Warum:* Wenn die Maschine schmutzig wiegt und der Abnehmer sauber zählt,
sind alle Kaliber-Zuordnungen systematisch um das Erdgewicht verschoben —
und der Ausschuss „zu klein" wird zu klein gemessen.

> Antwort:

**15. Bleibt eine Kaliber-Kiste chargenrein?**
Wenn nach Charge A gleich Charge B über dasselbe Band läuft: kommen die in
dieselbe Kiste?
*Warum:* Dann ist die Charge-Identität weg, und der Schimmel, der später beim
Waschen aussortiert wird, lässt sich keiner Lagerdauer mehr zuordnen.

> Antwort:

**16. Läuft je ein Kürbis zweimal über das Band?**
Rücklauf, Nachsortieren, Bandstau.
*Warum:* Dann zählt die CSV ihn doppelt. Die Dubletten-Regel fängt nur direkt
aufeinanderfolgende Doppel ab, keinen späteren zweiten Durchlauf.

> Antwort:

---

## 5 — Lager und Zeit

**17. Ist die Halle geheizt oder temperiert — oder folgt sie dem Wetter?**
Gibt es Lüftung? Weiss jemand ungefähr die Temperaturen über die Saison?
*Warum:* Das Modell nimmt eine über die ganze Saison **konstante**
Verdunstungsrate an. Von September (mild) bis März (kalt) ist das kaum
richtig. Dann wird die frühe Verdunstung unter- und die späte überschätzt —
und die Hochrechnung auf lange Lagerdauern zieht sich mit.

> Antwort:

**18. Liegen wirklich alle Paletten unter gleichen Bedingungen?**
Aussenwand gegen Mitte, oben gegen unten, beim Tor gegen hinten.
*Warum:* Das Modell behandelt die Halle als einen Ort. Systematische
Unterschiede landen sonst im Fehlerbereich statt im Modell.

> Antwort:

**19. Was passiert am Saisonende mit dem Rest?**
Weg, oder in die neue Saison? Und bleibt er dann derselben Charge zugerechnet?
*Warum:* Das Modell kennt nur „bis zum Stichtag gelagert" und weiss nicht,
was danach kommt.

> Antwort:

---

## 6 — Was den Betrieb sonst verlässt

**20. Welche Abgänge gibt es neben dem Lieferschein-Verkauf, und wie gross sind sie ungefähr?**
Hofladen, Tierfutter, Eigenbedarf/Personal, Kompost, Geschenke.
*Warum:* Was nicht erfasst ist, sieht in der Bilanz aus wie Verlust. Selbst
grobe Monatssummen je Weg helfen.

> Antwort:

**21. In welcher Einheit steht die Menge auf dem Lieferschein — Kilo oder Kisten?**
*Warum:* Beides geht, Kisten werden umgerechnet. Die Antwort ändert nur, wie
genau die Gegenprobe schliesst.

> Antwort:

**22. Gibt es Rückläufer oder Reklamationen?**
Ware, die zurückkommt und dann entsorgt wird.
*Warum:* Sie wäre doppelt gezählt — einmal als Ausgang, einmal nicht als
Verlust.

> Antwort:

---

## 7 — Wozu das Ganze: das entscheidet, was genau genug sein muss

**23. Was würdest Du ändern, wenn Verdunstung gewinnt? Was bei Schimmel? Was bei Ausschuss?**
*Warum:* Wenn zwei Ursachen zur selben Massnahme führen, muss ich sie gar
nicht auseinanderhalten — dafür andere umso schärfer. Heute sagt das
Dashboard „Schimmel und Ausschuss sind nicht auseinanderzuhalten". Ob das
schlimm ist, hängt allein an dieser Antwort.

> Antwort:

**24. Soll die Rangfolge in Kilo oder in Franken sein?**
*Warum:* In Kilo gewinnt heute die Verdunstung. In Franken kann es kippen:
Auf der Maschinen-Linie wird **pro Stück je Kaliber** bezahlt — ein leichterer
Kürbis kostet dort erst etwas, wenn er ins nächsttiefere Band rutscht. Auf der
Hand-Linie wird **pro Kiste ab 8 kg** bezahlt — dort kostet Verdunstung sofort.
Schimmel kostet dagegen immer den ganzen Kürbis. Mit Deinen Preisen kann ich
beide Rangfolgen nebeneinander zeigen; ohne sie bleibt es bei Kilo.

> Antwort:

**25. Die 8-kg-Kiste: gibt es eine geforderte Mindestmenge mit Toleranz?**
Muss sie garantiert ≥ 8.0 kg sein, oder ist 8.0 ein Zielwert?
*Warum:* Muss sie garantiert darüber liegen, ist ein Zuschlag Absicht und kein
Fehler — dann ist nicht die Überfüllung das Problem, sondern die Streuung beim
Füllen. Das ist eine andere Massnahme.

> Antwort:
