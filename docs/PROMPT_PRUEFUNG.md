# Auftrag: das Programm auf Herz und Nieren prüfen

## 0. Was das ist

Du prüfst ein laufendes System, das auf einem echten Betrieb echte
Entscheidungen tragen soll: Wohin verschwinden die Kürbisse zwischen Ernte und
Lastwagen, und welche Massnahme lohnt sich? Es ist über elf Runden gewachsen,
alle Prüfstände sind grün, die Doku ist umfangreich.

**Genau das ist die Gefahr.** Eine grüne Testsuite beweist, dass das Programm
tut, was es tut — nicht, dass es das Richtige tut. Ein Test, den derselbe
Kopf geschrieben hat wie den Code, prüft dieselbe Annahme zweimal. Deine
Aufgabe ist nicht, die Tests noch einmal laufen zu lassen. Deine Aufgabe ist,
die Stellen zu finden, an denen das Programm **etwas Falsches richtig
ausrechnet**.

Du baust nicht zuerst. Du prüfst zuerst, belegst, und baust dann.

## 1. Die drei Fehlerklassen — und welche zählt

| Klasse | Beispiel | Wer findet sie sonst |
|---|---|---|
| **1 — technisch** | Absturz, falscher Typ, Zeile geht verloren | tsc, Tests, Prüfstände |
| **2 — Kette** | Ein Feld wird erfasst und nie gelesen; die Auswertung liest eine Spalte, die keine Maske füllt | Lückenscanner, Kette |
| **3 — Bedeutung** | Die Zahl ist korrekt gerechnet und meint das Falsche | **niemand** |

Klasse 1 und 2 hat das Projekt weitgehend im Griff. **Deine Beute ist
Klasse 3.** Dorthin gehören:

- eine Masse, deren Tara nicht abgezogen wird, weil niemand nach den Kisten
  fragt;
- ein Prozentwert, dessen Nenner eine andere Frage beantwortet als die, die
  der Betriebsleiter stellt;
- ein Koeffizient, der an Ware A gemessen und auf Ware B angewendet wird;
- eine Grösse, die „bis heute" heisst und etwas enthält, das noch nicht
  passiert ist;
- ein Wort auf dem Bildschirm, das im Betrieb etwas anderes bedeutet als im
  Code.

Für **jede** Zahl, die auf einem Bildschirm steht, musst du am Ende drei
Fragen beantworten können:

1. Aus welchen Rohzeilen entsteht sie, mit welcher Formel, in welcher Einheit?
2. Welche Entscheidung trifft der Betriebsleiter damit — und würde eine
   **andere, ebenso vertretbare Definition** zu einer **anderen Entscheidung**
   führen?
3. Welche Messung würde sie widerlegen, und erhebt die App diese Messung?

Wo Frage 2 mit „ja" endet, ist die Definition eine Entscheidung des Betriebs
und keine des Programmierers. Solche Stellen legst du dem Betrieb vor
(Abschnitt 8) — du entscheidest sie nicht still.

## 2. Bevor du irgendetwas prüfst: lesen

In dieser Reihenfolge, vollständig, nicht überflogen:

1. `docs/ABLAUF.md` — **was auf dem Betrieb wirklich passiert.** Der Massstab.
   Ganz am Ende steht eine Tabelle „Annahmen, die im Modell stecken" mit rund
   zwanzig Zeilen. Jede davon ist ein Prüfauftrag.
2. `docs/ABMACHUNGEN.md` — 46 Zusagen mit Datum und dem Test, der sie hält.
3. `docs/FRAGEN.md` — was der Betrieb **nicht** beantwortet hat. Achte darauf,
   ob eine offene Frage im Code inzwischen still beantwortet wurde.
4. `docs/ENTSCHEIDUNGEN.md` — warum etwas so ist. Lang, aber jede Runde hat
   einen eigenen Abschnitt.
5. `docs/STATISTIK_BEFUND.md` — was gemessen wurde und wie gut es trifft.
6. `supabase/setup.sql`, **Teil B** — dort steht jede Ansicht und jede
   rechnende Funktion **genau einmal**, in ausgerechneter Reihenfolge. Das ist
   der schnellste Weg zum heutigen Rechenwerk; die Migrationen darunter sind
   die Geschichte, nicht der Stand.
7. Das Frontend, in dieser Reihenfolge: `src/arbeit/` (die Masken des
   Arbeiters), `src/pages/` (die Seiten des Betriebsleiters),
   `src/auswertung/daten.ts` (was die App lädt).

Schreib dir beim Lesen **zwei Tabellen** mit, du brauchst sie in Abschnitt 4:

- **Erfassungsmatrix:** jedes Eingabefeld jeder Maske → Tabelle und Spalte →
  wer liest es → was passiert, wenn es fehlt.
- **Zahlenmatrix:** jede Zahl auf jedem Bildschirm → Quelle → Einheit →
  Zähler/Nenner bei Prozenten → gemessen oder gerechnet.

## 3. Wie geprüft wird — sechs Methoden

Lesen allein findet Klasse 3 nicht. Benutze alle sechs.

**M1 — Rückwärtsrechnen.** Nimm eine Zahl vom Bildschirm. Verfolge sie durch
jede Sicht bis zu den Rohzeilen. Rechne sie **von Hand in SQL neu**, mit einer
eigenen Abfrage, die den Weg der App nicht benutzt. Vergleiche. Mindestens
zehn Zahlen, verteilt über alle Seiten.

**M2 — Der Papierfall.** Baue eine winzige Saison, deren richtiges Ergebnis du
auf Papier ausrechnen kannst: eine Charge, drei Paletten mit bekannten
Gewichten und bekannter Gebindeart, eine Lieferung, eine Verdunstungswägung,
eine Palox-Ablesung. Setze die Koeffizienten so, dass jede Zahl analytisch
folgt (z. B. r = 0 und f = 0: dann muss verkaufsfähig = Eingang gelten). Spiel
sie in eine echte Datenbank ein und vergleiche jede Kennzahl mit deiner
Handrechnung. **Das ist der schärfste Test der ganzen Kaskade** — er findet
Vorzeichen, Reihenfolge und Doppelzählung sofort.

**M3 — Störfälle.** Baue Daten, bei denen es weh tut, und sieh nach, was
passiert. Mindestens diese:

- Gebinde ohne hinterlegte Tara (Netto muss **leer** bleiben, nicht 0);
- eine Palette, deren Kistenzahl von der Charge abweicht;
- zwei Paletten derselben Charge mit **identischem** Bruttogewicht;
- eine Palette, die zwischen zwei Wägungen umgestapelt wurde (andere
  Kistenzahl);
- eine Lieferung mit Datum in der Zukunft;
- eine Lieferung an eine Charge ohne Wareneingang;
- ein Palox-Stand, der fällt (geleert), und einer unter dem Leergewicht;
- eine Sortier-CSV zweimal eingelesen;
- eine Charge, die nur teilweise erfasst wurde (halbes Erntejournal);
- ein Koeffizient ohne einzige Messung.

Für jeden: Was zeigt die App? Ist das ehrlich? Steht es als Auffälligkeit da,
oder verschwindet es still in einer Zahl?

**M4 — Ableitungsprobe.** Ändere **einen** Eingabewert und sieh nach, ob sich
die Zahl bewegt, wie sie muss: Richtung, Grössenordnung, Einheit. Verdoppelt
sich die Eingangsmasse einer Charge, muss ihr Verlust in kg ungefähr doppelt
so gross werden und ihr Verlust in Prozent gleich bleiben. Wo das nicht gilt,
steckt ein Bezugsfehler.

**M5 — Der Zwei-Leser-Test.** Lies jeden Bildschirm zweimal: einmal als
Betriebsleiter, der den Code nicht kennt und nur die Wörter sieht, einmal als
Autor des Modells, der weiss, was gerechnet wurde. **Wo die beiden Lesarten
auseinandergehen, ist ein Befund** — auch wenn die Zahl stimmt. Beispiel:
„Verlust 12 % des Eingangs" liest der Betriebsleiter als „von dem, was ich
geerntet habe, ist ein Achtel kaputtgegangen". Der Modellautor weiss, dass ein
Teil davon an Ware hängt, die längst verkauft ist und die niemand mehr
beeinflussen kann.

**M6 — Die Widerlegungsfrage.** Für jede gerechnete Zahl: Welche Messung würde
zeigen, dass sie falsch ist? Erhebt die App sie? Wenn nein — ist das gesagt?

## 4. Die Prüfachsen

### A — Erfassung → Datenbank → Auswertung, Feld für Feld

Geh die Erfassungsmatrix durch. Für jedes Feld:

- Kommt der Wert vollständig in der Datenbank an (Einheit, Rundung,
  Zeitzone)?
- Wird er von der Auswertung gelesen — **einmal**, nicht zweimal, nicht nie?
- Reicht er, um die Grösse zu bilden, die daraus gemacht wird? **Oder fehlt
  ein Feld, das die Formel braucht?**
- Was passiert, wenn er fehlt? Wird daraus stillschweigend 0?

Die letzte Frage der dritten Zeile ist die wichtigste. Sie hat den Anlass für
diese Prüfung geliefert (Abschnitt 5).

### B — Masse und Tara

Jede Masse im System ist entweder gewogen, aus einer anderen gerechnet oder
geschätzt. Verfolge **jeden** Weg, auf dem aus einem Bruttogewicht ein
Nettogewicht wird, und prüfe:

- Wird dieselbe Tara-Regel überall angewendet
  (`brutto − kisten × tara_kg_pro_kiste − tara_kg_palette`)?
- Wo eine der Grössen fehlt: bleibt das Ergebnis leer, oder wird gerechnet,
  als wäre sie null?
- Wo genähert wird (mittlere Tara, mittlere Palettenmasse, gemessenes
  Kistengewicht): **steht das an der Zahl dran?** Die Datenbank kennt
  `masse_quelle` mit sechs Stufen — kommt diese Auskunft beim Betriebsleiter
  an, oder endet sie in der Datenbank?
- Stimmt die Näherung überhaupt? Rechne den Fehler aus: Wie viele Kilo liegt
  eine Palette daneben, wenn sie zwei Kisten weniger hat als der Schnitt der
  Charge?

### C — Bezugsgrössen: jeder Prozentwert nennt seinen Nenner, und der Nenner muss stimmen

Sammle **alle** Prozentangaben der App in eine Tabelle: Ort, Zähler, Nenner,
Beschriftung. Dann prüfe jede einzelne gegen die Frage, die sie beantworten
soll.

Der Betrieb hat dazu einen konkreten Einwand erhoben, den du ernst nehmen und
durchrechnen musst — siehe Abschnitt 5, Beispiel 2. Er trifft nicht eine Zahl,
sondern das Muster: **Über die ganze App hinweg ist der Nenner der Eingang.**
Frage bei jeder: Ist der Eingang hier wirklich die Menge, auf die sich der
Verlust bezieht?

### D — Zeit, Alter, „bis heute"

- Was heisst `heute()`, was `stichtag()`, und wo wird welches benutzt?
- Enthält eine Grösse, die „bis heute" heisst, irgendetwas, das noch nicht
  passiert ist? (Vordatierte Lieferungen sind behoben — gibt es andere?)
- Das Alter der liegenden Ware kommt ohne FIFO aus dem Eingangsanteil je
  Eingangstag. Prüfe an einem Papierfall, dass die Kohortenrechnung aufgeht
  und dass „liegt seit" wirklich eine Spanne und keine Behauptung ist.
- Die Verdunstungsrate wird als **Tagesrate** gemessen und mit
  `(1−r)^Lagertage` hochgerechnet. Prüfe, dass die Lagertage bei Messung und
  Anwendung dieselbe Uhr benutzen.

### E — Die Verlust-Begriffe, überall gleich

Das System unterscheidet drei Dinge, die leicht ineinanderrutschen:

- **echter Verlust** — Verdunstung, Faules im Lager, nicht lagerbedingt, faul
  beim Abpacken. Die Masse ist weg.
- **kein echter Verlust** — zu klein, zu gross. Die Ware verlässt den Betrieb
  in einem anderen Kanal.
- **Überzählung** — hinter den Lieferungen steckt mehr, als je eingelagert
  wurde. Ein Erfassungsfehler, kein physikalisches Ereignis.

Prüfe die Trennung **auf jedem Bildschirm, in jeder Grafik, in jeder Summe und
in jedem Datenbankfeldnamen**. Kann ein reales Ereignis in zwei Ströme fallen?
In keinen? Addieren sich die Ströme je Portion exakt zum Eingang?

### F — Leer ist nicht null

Das Projekt hat diesen Grundsatz. Prüfe ihn adversarisch: Suche jede Stelle,
an der `coalesce(..., 0)`, `?? 0` oder ein `left join` aus einer fehlenden
Messung eine Null macht, die dann wie eine gemessene Null aussieht. Für jede:
Ist das hier richtig, oder verschwindet damit eine Unwissenheit?

### G — Bilanz und Doppelzählung

Die Gleichung, die gelten muss:

```
Eingang + Überzählung = geliefert + Verlust bis heute
                      + anderer Kanal am Ausgelagerten + noch im Haus
```

- Geht sie auf den Demodaten auf? Auf deinem Papierfall? Auf einer Saison mit
  Störfällen aus M3?
- Was ist der Rest, und **warum** ist er nicht null?
- Kann eine Masse zweimal gezählt werden — etwa als Fax-Durchsatz und als
  Lieferung, oder als Ausschuss aus der CSV und als Palox-Inhalt?

### H — Die Annahmen aus ABLAUF.md, einzeln

Rund zwanzig Zeilen. Für jede:

1. Steht sie noch so im Code, oder ist der Code inzwischen weitergegangen?
2. Wie gross ist der Fehler, wenn sie nicht stimmt — in Kilo, nicht in Worten?
3. Weiss der Betriebsleiter davon, wenn er die betroffene Zahl ansieht?

### I — Rollen, Rechte, Mehrbenutzer

- Kann ein Zähler etwas sehen oder ändern, was ihn nichts angeht?
- Was passiert, wenn zwei Arbeiter dieselbe Arbeit gleichzeitig bearbeiten?
- Was passiert, wenn das Netz mitten in einer Erfassung wegbricht?
- Kann eine falsch getippte Messung korrigiert werden — jede, oder nur
  manche?

### J — Praxistauglichkeit in der Halle

Lies die Masken als Arbeiter mit kalten Händen auf einem alten Handy:

- Wird nach etwas gefragt, das an dieser Station niemand wissen kann?
- Wird etwas **nicht** gefragt, das dort ohne Aufwand zu haben wäre und eine
  Näherung überflüssig machen würde?
- Ist die Reihenfolge der Fragen die Reihenfolge der Handgriffe?
- Was kostet eine zusätzliche Frage — und was bringt sie in Kilo Genauigkeit?
  Diese Abwägung gehört in den Befund, nicht ins Bauchgefühl.

## 5. Zwei ausgearbeitete Beispiele — der Massstab für alles andere

Diese beiden hat der Betrieb selbst gefunden. Sie zeigen die **Tiefe**, die
erwartet wird. Arbeite beide vollständig ab und finde dann die anderen.

### Beispiel 1 — Das Gewicht vom Zettel ohne Kisten

**Was auffiel:** Beim Waschen + Sortieren fragt der Zähler
(`src/arbeit/Zaehler.tsx`) je Eingangspalette nach *Datum vom Zettel* und
*Gewicht vom Zettel* — und schreibt `auftrag_palette.brutto_zettel_kg`. Nach
der **Kistenzahl** und der **Gebindeart** fragt er nicht. Das Nettogewicht ist
aber

```
netto = Zettelgewicht − Palettengewicht − Kistenzahl × Kistengewicht(Gebindeart)
```

Die Wiegemaske (`src/arbeit/WiegenMaske.tsx`) fragt beides sehr wohl und
rechnet genau so. Die Zählmaske daneben nicht.

**Was du prüfen musst — und zwar bis zum Ende:**

1. **Was macht das Backend daraus?** `v_auftrag_palette_masse` sucht zuerst
   eine Palette im Wareneingang mit gleicher Charge, gleichem Eingangsdatum
   und gleichem Bruttogewicht und nimmt deren Netto (`masse_quelle`
   = `zettel`). Findet es keine, zieht es die **mittlere Tara der Charge** ab
   (`zettel-charge-tara`). Ist das tragfähig? Rechne den Fehler für einen
   realistischen Fall aus.
2. **Ist die Näherung sichtbar?** Es gibt eine Auffälligkeit „Zettelgewicht".
   Prüfe genau, wann sie feuert — und wann **nicht**. Verdacht, den du
   bestätigen oder widerlegen musst: Die Auffälligkeit prüft nur, ob
   *irgendeine* Palette der Charge dieses Gewicht hat, die Massenrechnung
   verlangt zusätzlich dasselbe **Eingangsdatum** und ein bekanntes Netto.
   Fällt der Fall dazwischen, wird genähert **ohne** dass es jemand erfährt.
3. **Der Zahlendreher-Fall.** Zwei Paletten derselben Charge mit demselben
   Bruttogewicht: An welche wird angeknüpft? Ist das egal?
4. **Die Frage dahinter:** Wäre es besser, den Zähler nach Kisten und
   Gebindeart zu fragen? Was kostet das in der Halle (ein Feld mehr je
   Palette, oft gleich für alle), was bringt es in Kilo? Antworte mit Zahlen.
5. **Und rückwärts:** Welche anderen Massen entstehen aus einer Eingabe, der
   ein Feld für die exakte Rechnung fehlt? Such systematisch, nicht nur hier.

### Beispiel 2 — Verlust in Prozent: Prozent wovon?

**Was auffiel:** Überall steht „X % des Eingangs" — im Überblick, in den
Ursachen, in den Anteilsbalken. Der Einwand des Betriebs:

> Will ich Prozent vom Eingangsgewicht wissen, oder lieber Prozent von
> Eingang − Ausgang, also von dem, was noch da ist? Denn was verkauft wurde,
> da wurde im Verkaufsschritt das Faule ja ohnehin schon aussortiert —
> vielleicht sogar, bevor es die App gab.

**Warum der Einwand ins Schwarze trifft:** Die Kaskade rechnet zur
ausgelieferten Ware die Eingangsmasse zurück (`m0 = geliefert ÷
verkaufsfähiger Anteil`) und legt ihr denselben Verlust auf wie der liegenden.
Das ist eine **Modellannahme**, keine Messung: Ob an dieser Ware wirklich so
viel verdunstet und verdorben ist, hat niemand gewogen. Für Ware, die vor dem
Erfassungsbeginn rausging, ist es reine Rückrechnung. Der Verlust an bereits
verkaufter Ware ist ausserdem eine Zahl, an der der Betriebsleiter **nichts
mehr ändern kann** — der Verlust an der liegenden Ware dagegen ist genau die
Zahl, für die er morgens aufsteht.

**Was du tun musst:**

1. Rechne beide Kennzahlen für dieselben Daten aus:
   Verlust ÷ Eingang, und Verlust der liegenden Portion ÷ liegende Portion.
   Wie weit liegen sie auseinander — auf den Demodaten und auf einer Saison,
   die schon halb verkauft ist?
2. Prüfe, ob sich der Verlust überhaupt sauber in „an verkaufter Ware" und
   „an liegender Ware" trennen lässt. Die Kaskade führt `portion` mit den
   Werten `ausgelagert` und `lager` — reicht das?
3. Beantworte für **beide** Kennzahlen: Welche Entscheidung trägt sie?
4. Entscheide **nicht selbst**, welche die richtige ist. Leg dem Betrieb beide
   Zahlen nebeneinander, sag in einem Satz, was jede bedeutet, und frag. Es
   kann gut sein, dass beide gehören — die eine als Saisonbilanz, die andere
   als Handlungszahl.
5. Und dann dasselbe für **jeden anderen Prozentwert** der App.

## 6. Startpunkte — unbestätigt, unvollständig, kein Ersatz für eigene Suche

Beim Lesen bin ich an diesen Stellen hängengeblieben. Sie sind **Verdacht,
nicht Befund**; manche lösen sich vermutlich in Luft auf. Prüfe sie, aber
verwechsle die Liste nicht mit dem Auftrag: Deine eigenen Funde zählen mehr.

- `verkaufsfaehig_anteil` ist nach unten auf **0.25** geklammert. Was heisst
  das für eine Charge, die wirklich schlechter ist? Wird der Deckel je
  erreicht, und merkt es jemand?
- Der Verdunstungs-Koeffizient wird aus `brutto_damals` und `brutto_jetzt`
  gebildet — beide mit **derselben** Kistenzahl und Gebindeart. Wurde die
  Palette umgestapelt, ist die Rate falsch. Wie oft passiert das?
- `masse_quelle` unterscheidet sechs Stufen je Palette; auf dem Bildschirm
  erscheint nur die gröbere Quelle je Arbeit, und die als roher englischer
  Datenbankwert in Klammern.
- Der Palox-Sockel a₀ wird nur gesetzt, wenn ein Test ihn belegt — sonst 0.
  „Nicht nachweisbar" und „null" sehen in der Summe gleich aus. Sieht man den
  Unterschied?
- Die Überfüllung je Kiste wird an gewogenen fertigen Paletten gemessen und
  auf alle verkauften Kisten der Sorte hochgerechnet. Die Annahme steht in
  ABLAUF.md — steht sie auch an der Zahl?
- `a_klein_n = a_klein / max(a_klein + a_gross, 1)`: eine Normierung, damit
  die Summe nicht über 1 geht. Wann greift sie, und was bedeutet sie dann?
- Die Auffälligkeiten (`v_plausibilitaet`) prüfen ein gutes Dutzend Fälle.
  Welche Fehlerart, die du in M3 baust, fällt durch **keine** von ihnen?

## 7. Was ein Befund enthalten muss

Ohne diese sieben Punkte ist es kein Befund, sondern eine Meinung:

| Feld | Inhalt |
|---|---|
| **Ort** | Datei und Zeile, Sicht und Spalte, Bildschirm und Beschriftung |
| **Was da steht** | die heutige Zahl oder Formel, wörtlich |
| **Was dastehen müsste** | und warum genau das |
| **Klasse** | 1 technisch · 2 Kette · 3 Bedeutung |
| **Beleg** | die Abfrage, der Papierfall, der Störfall — ausführbar, nicht behauptet |
| **Grösse** | wie viele Kilo oder Prozentpunkte auf den Demodaten. Ohne Grössenangabe kein Befund |
| **Vorschlag** | was zu tun ist, was es kostet, und ob es eine Entscheidung des Betriebs braucht |

Sortiere nach Grösse mal Wahrscheinlichkeit, nicht nach Fundreihenfolge.
Nenne ausdrücklich, was du geprüft und **in Ordnung** gefunden hast — eine
Liste, die nur Mängel enthält, sagt nichts über die Abdeckung.

## 8. Wann du fragst statt entscheidest

Frag den Betrieb, wenn beide Antworten vertretbar sind und die Wahl das
Ergebnis ändert:

- der Nenner einer Kennzahl;
- ob eine Näherung reicht oder ein Feld mehr erfasst wird;
- ob eine Ursache als echter Verlust oder als anderer Kanal zählt;
- ob eine Zahl überhaupt gezeigt werden soll, wenn sie zu unsicher ist.

Repariere ohne Rückfrage, was eindeutig falsch ist: Vorzeichen, Einheit,
doppelt gezählte Masse, eine Beschriftung, die nicht zur Formel passt, ein
fehlender Filter.

Wenn du fragst: **beide Zahlen ausgerechnet danebenlegen**, je einen Satz, was
sie bedeuten, und eine Empfehlung mit Begründung. Nicht „was möchten Sie?",
sondern „so sieht es aus, ich würde X, weil Y — einverstanden?".

## 9. Werkzeuge

```bash
npm run pruefen                     # Typen, 76 Tests, Build — ohne Datenbank
./supabase/test/run.sh 'postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432'
node pruefstand/bildschirme.mjs     # jede Seite im echten Browser, Screenshots
node pruefstand/beschriftung.mjs    # sagt jede Zahl, was sie ist?
node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh '<url>'
./pruefstand/luecken.sh '<url>'     # Maske ↔ Auswertung, in beide Richtungen
./supabase/setup_bauen.sh           # nach jeder Änderung an migrations/
```

Lokale Postgres (falls sie nicht läuft):

```bash
mkdir -p /tmp/pgsock
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgdata -l /tmp/pg.log \
  -o '-k /tmp/pgsock -p 55432 -c listen_addresses=' start"
```

Eine Datenbank mit Demodaten baust du mit `pruefstand/demo_bauen.sh`; die
Fixtures für die Bildschirm-Prüfstände zieht `pruefstand/daten_dumpen.sh`
daraus. Für M2 und M3 baust du eigene, kleine Datenbanken — nicht die
Demodaten verbiegen.

## 10. Feste Regeln

- Entwickeln und pushen **nur** auf `claude/new-session-vrnnyo`
  (`git push -u origin claude/new-session-vrnnyo`, bei Netzfehlern mit 2/4/8/16
  Sekunden erneut versuchen). **Keinen Pull Request** ohne ausdrückliche Bitte.
- Die echten Excel-Dateien unter `/root/.claude/uploads/` enthalten Kundennamen
  und Preise. Lesen ja, **committen nie**.
- Keine Modellbezeichnung in Code, Commits, Kommentaren oder Dokumenten.
- Commits mit
  `git -c user.name="Alexander Konvalina" -c user.email="konvalina.alexander@gmail.com"`
  und dem Anhang:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  Claude-Session: <Session-Link>
  ```
- **Keinen Test abschalten, überspringen oder aufweichen**, um grün zu werden.
  Ein Test, der stört, hat entweder recht oder gehört korrigiert — mit
  Begründung.
- Nichts löschen, worin Daten liegen. Ansichten, Funktionen und Oberflächen
  ja; Tabellen und Spalten nein.
- Datierte Stammdaten nie überschreiben, sondern fortschreiben.
- Was gebaut wird, wird durch einen Test festgehalten, der ohne die Änderung
  fehlschlägt. Eine Reparatur ohne Test ist keine Reparatur.

## 11. Was am Ende abgeliefert wird

1. **Der Befundbericht** (`docs/PRUEFBERICHT.md`): alles Geprüfte, alles
   Gefundene, nach Gewicht sortiert, jeder Befund mit den sieben Feldern aus
   Abschnitt 7. Dazu die Liste dessen, was du geprüft und für richtig befunden
   hast.
2. **Die Fragen an den Betrieb** — kurz, mit ausgerechneten Zahlen auf beiden
   Seiten und einer Empfehlung. Nicht mehr als eine Seite.
3. **Die Reparaturen**, die keine Rückfrage brauchen — jede mit ihrem Test,
   jede in einer Migration, wenn sie die Datenbank betrifft.
4. **Die neuen Prüfungen**, die verhindern, dass derselbe Fehler zurückkommt:
   der Papierfall als fester Testfall, die Störfälle in `run.sh`, die
   Bezugsgrössen-Tabelle als Prüfstand.
5. **Die nachgezogene Doku**: ABLAUF.md, wo sich eine Annahme geändert hat;
   ABMACHUNGEN.md um neue Zusagen; ENTSCHEIDUNGEN.md mit einem Abschnitt für
   diese Runde.
6. **Ein Bericht an mich in einfachem Deutsch**: Was hast du gesucht, wo hast
   du geschaut, was hast du gefunden, was hast du repariert, was bleibt offen,
   und was musst **ich** entscheiden.

**Schreib nicht „alles in Ordnung", wenn du nichts gefunden hast.** Schreib
dann, was du geprüft hast und wo eine Prüfung an ihre Grenze kam. Ein System
dieser Grösse, das über elf Runden gewachsen ist, hat Stellen, an denen die
Rechnung von der Wirklichkeit abweicht. Wenn du keine findest, hast du
entweder nicht tief genug gegraben — oder du kannst genau sagen, warum nicht.
