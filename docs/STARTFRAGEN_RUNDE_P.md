# Was ich von dir brauche, bevor Runde P anfängt

Ich habe Kaskade, Sichten und die Zahlen der Demo gelesen und die zwei
Sichten, an denen die Runde hängt, gegen die Demo gerechnet — sie stimmen.
Das Meiste im Plan (`docs/PLAN_RUNDE_P.md`) braucht keine Entscheidung von
dir: es ist Rechnung, Prüfung und Bauen. Es bleiben **drei Weggabelungen**,
bei denen deine Antwort ändert, was gebaut wird. Jede hat eine Voreinstellung;
trägst du nichts ein, gilt sie, und die ausführende KI wartet nicht.

---

## 1. „Im Lager" — welche Zahl meinst du, wenn du „ich hab noch x Tonnen" sagst?

Zwei Zahlen sind beide richtig, sie beantworten verschiedene Fragen:

| | Demo | Was es ist |
|---|---|---|
| **Eingangsware, die nicht ausgeliefert ist** | **187.8 t** | Eingang minus das, was hinter den Lieferungen steckt. Das, was du eingelagert und noch nicht verkauft hast — die Paletten, die stehen (sie wiegen heute weniger, und ein Teil ist faul). |
| Gute Ware heute | 153.6 t | Dasselbe nach Wasserverlust und Faulem bis heute. |

Davon verkaufsfähig sind in beiden Fällen **144.1 t** — aber der Prozentsatz
ist ein anderer: **77 % der Eingangsware** oder **94 % der guten Ware**. Und
nur der erste Nenner bleibt über die Zeit stehen; der zweite schrumpft mit,
und der Anteil bliebe über Wochen fast gleich, obwohl Ware verdirbt.

**Voreinstellung: Eingangsware (187.8 t, 77 %).** Das passt zu deinem Satz
„ich hab noch 400 Tonnen, aber nur 65 % sind verkaufbar". Die gute Ware steht
als Untertext daneben. (Damit ist auch Frage 51 aus Runde L entschieden.)

> Antwort:

---

## 2. Wie weit soll die Prognose reichen — und in welcher Form?

Die App kann nicht wissen, wie schnell verkauft wird. Was sie weiss: wie die
liegende Ware altert. Deshalb sagt sie **Prozent der liegenden Ware, wenn
nichts verkauft wird**: heute 77 %, in 1 Woche 76 %, in 2 Wochen 75 %, in 4
Wochen 74 %, in 8 Wochen 71 %, in 12 Wochen 69 % (Demo). Kilo nur als Rate:
„zurzeit rund 182 kg je Tag" an der liegenden Ware.

**Voreinstellung: 12 Wochen, in Prozent; im Verlauf zusätzlich bis zum
Saisonende (31.03.).** Eine Zahl „am Saisonende" ohne Verkaufstempo wäre
„wenn bis dahin nichts verkauft wird" — ehrlich, aber wenig brauchbar. Willst
du sie trotzdem?

> Antwort:

---

## 3. Fax: „Tage seit dem Waschen" automatisch vorschlagen?

In der Demo zeigt sich der Zusammenhang, den du suchst: Wird am Tag nach dem
Waschen abgepackt, sind **1.3 %** faul; wartet die Ware zwei bis drei Tage,
**2.3 %**. Die Zahl steht heute auf 142 von 160 Fax-Arbeiten — die übrigen 18
haben „unbekannt", weil der Vorarbeiter die Tage nicht wusste.

Vorschlag: Die App belegt das Feld beim Fax-Abschluss aus der letzten
Wasch-Arbeit derselben Charge vor; der Vorarbeiter kann es ändern. Keine neue
Frage, ein Feld weniger zu tippen.

**Voreinstellung: ja.**

> Antwort:

---

Nicht neu, aber jetzt spürbar: **Frage 49** (Preise je Stück und je Kiste).
Ohne sie bleiben Überfüllung und Spielraum in Kilo. Mit ihnen könnte die
Rangfolge „was war am schlimmsten" auch in Franken stehen — und dort kippt
sie womöglich (Verdunstung kostet auf der Kisten-Linie sofort, auf der
Stück-Linie erst, wenn ein Kürbis ins nächste Band rutscht).
