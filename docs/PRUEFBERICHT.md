# Prüfbericht

*Erzeugt von `pruefwerk/bericht.mjs` aus dem Lauf des Prüfwerks. Nicht von Hand ändern —
die Fassung, die zählt, entsteht neu mit `node pruefwerk/lauf.mjs && node pruefwerk/bericht.mjs`.*

## Was hier steht

24 Feststellungen aus 10 Sonden. Jede hat eine Grösse — ohne Grösse
ist eine Feststellung eine Meinung, und eine Liste von Meinungen nimmt niemand ernst. Jede hat
eine Gegenrede, wo es eine gibt: das beste Argument dagegen, aufgeschrieben von dem, der die
Feststellung gemacht hat.

Nicht jede Feststellung ist ein Fehler. 3 sind ausdrücklich
„geprüft und in Ordnung" — sie stehen hier, weil ein Bericht, der nur Fehler nennt, nicht sagt,
wie weit nachgesehen wurde.

| Klasse | Was das heisst | Anzahl |
|---|---|---|
| 3 — Bedeutung | Die Zahl steht da und meint etwas anderes, als der Leser denkt — oder sie ist falsch. | 18 |
| 2 — Kette | Erfassung, Rechnung und Anzeige passen nicht sauber zusammen; heute trägt es, morgen vielleicht nicht. | 3 |
| 1 — Technisch | Im Bestand nachgesehen und in Ordnung befunden, oder eine Kleinigkeit ohne Folge für eine Zahl. | 3 |

| Marke | Was zu tun ist | Anzahl |
|---|---|---|
| Reparatur | Etwas ist falsch und lässt sich richtigstellen, ohne die App zu erweitern. | 18 |
| Frage an den Betrieb | Zwei Lesarten sind beide vertretbar; entscheiden muss der Betrieb. | 1 |
| Entscheidung des Betriebs | Es geht um den Ablauf im Betrieb, nicht um den Code. | 2 |
| kein Fehler | Nachgesehen, in Ordnung. | 3 |

## Was geprüft wurde

| Sonde | Feststellungen | Dauer | Selbstprobe |
|---|---|---|---|
| `01_herkunft` | 1 | 11.9 s | ok |
| `02_bezugsgroessen` | 3 | 0.2 s | ok |
| `03_erfassung` | 2 | 1.4 s | ok |
| `04_orakel` | 0 | 0.5 s | ok |
| `05_metamorph` | 1 | 7.4 s | ok |
| `06_mutation` | 2 | 767 s | ok |
| `07_szenarien` | 6 | 53.5 s | ok |
| `08_leer_nicht_null` | 6 | 17.6 s | ok |
| `09_einheiten` | 1 | 41.3 s | ok |
| `10_annahmen` | 2 | 0.3 s | ok |

Die Spalte **Selbstprobe** ist die wichtigste der Tabelle. Jede Sonde bekommt einen Fall
vorgesetzt, in dem sie anschlagen *muss*. Steht dort „ok", hat sie ihren eigenen eingebauten
Fehler gefunden; steht dort „STUMPF", sagt auch ihr leeres Ergebnis nichts.

## Klasse 3 — Bedeutung

Die Zahl steht da und meint etwas anderes, als der Leser denkt — oder sie ist falsch.

### ANN-001 · Zu keiner der 21 Annahmen steht, wo ihr Bruch auffiele

*Reparatur · Sicherheit hoch · Aufwand mittel · `docs/ABLAUF.md`*

**Grösse.** **21 Annahmen ohne benannte Wache** (docs/ABLAUF.md)

**Was dasteht.** Die Tabelle hat die Spalten „Warum sie drinsteht", „Was passiert, wenn sie nicht stimmt". Eine Stichwortsuche über 26 Prüfungen, Prüfstände, Tests und Auffälligkeitsarten findet zu 19 Annahmen irgendeinen Treffer — bei 15 davon in mehr als drei Dateien gleichzeitig. Das ist kein Beleg, sondern Zufall: gesucht wird ein Wort, nicht eine Behauptung.

**Was dastehen müsste.** Eine vierte Spalte „Wo es auffiele" — je Annahme entweder ein Zeiger auf die Stelle, die anschlägt (Behauptung in pruefung.sql, Auffälligkeit in v_plausibilitaet, Störfall im Prüfwerk), oder ausdrücklich „nirgends — bewusst in Kauf genommen, Schaden: …". Danach kann diese Sonde die Spalte bewachen: existiert die genannte Stelle noch?

**Warum das zählt.** Eine Annahme, deren Bruch keine Spur hinterlässt, ist die teuerste Sorte Fehler: Die Zahlen bleiben plausibel, die Prüfungen bleiben grün, und der Betrieb handelt nach einer Zahl, die seit Wochen falsch ist. Die dritte Spalte der Tabelle sagt zu jeder Zeile selbst, was dann passiert — sie ist damit bereits die Liste der stillen Fehler, nur ohne Angabe, welche davon jemand bemerken würde. Die Runde hat für genau eine Zeile nachgesehen (die umgestapelte Palette, Störfall S7) und dort einen messbaren Fehler gefunden. Das ist der Grund, die übrigen zwanzig nicht auf gut Glück stehen zu lassen.

**Gegenrede.** Man kann einwenden, dass eine Doku-Spalte nichts prüft. Stimmt — sie macht aber prüfbar, was heute nicht einmal behauptet wird, und sie kostet keine Zeile Code in der App. Der teurere Weg wäre, zu jeder Annahme sofort einen Störfall zu bauen; die Spalte sagt zuerst, welche das überhaupt wert sind.

<sub>Nachweis: pruefwerk/befunde/annahmen.md</sub>

---

### BEZ-002 · Prozentzahl aus „verlust", ohne zu prüfen, ob „verlust" gemessen ist — an 2 Stellen

*Reparatur · Sicherheit hoch · Aufwand klein · `src/pages/Ueberblick.tsx:66`*

**Grösse.** **2 Stellen, die eine ungemessene Null als Prozent zeigen** (Strom „verlust")

**Was dasteht.** src/pages/Ueberblick.tsx:66 — `prozent(s.eingang_kg > 0 ? s.verlust_heute_kg / s.eingang_kg : null)`, beschriftet „des Eingangs"; src/pages/Ursachen.tsx:78 — `prozent(eingang > 0 ? verlust / eingang : null)`, beschriftet „des Eingangs"

**Was dastehen müsste.** Ist `verlust_bekannt` falsch, gehört dort „nicht gemessen" hin, nicht eine Zahl. Die Datenbank führt das Kennzeichen bereits mit; es wird an dieser Stelle nur nicht gelesen.

**Warum das zählt.** Ohne eine einzige Messung ist der Strom 0 kg — und 0 kg von einem Eingang sind 0,0 %. Der Leser sieht eine gemessene Null, wo nichts gemessen wurde. Genau dieser Fall tritt auf jedem Betrieb in der ersten Saison ein, bevor die erste Palette gewogen ist.

**Gegenrede.** Die Seiten zeigen unter den Zahlen einen Warnstreifen, der die ungemessenen Ursachen aufzählt — der Befund ist also kein Verschweigen. Er bleibt trotzdem stehen: Der Streifen nennt die Ursache, nicht die Folge, und die Prozentzahl darüber sieht unverändert nach einer Messung aus. Wer nur die grosse Zahl liest, liest eine Null. In den Demodaten ist `verlust` immer gemessen, deshalb fällt es nie auf — das ist kein Gegenargument, sondern die Erklärung, warum es stehen blieb.

<sub>Nachweis: src/pages/Ueberblick.tsx:66, src/pages/Ursachen.tsx:78</sub>

---

### BEZ-003 · Verlust in Prozent — wovon? Drei Lesarten, bis zu 9.0 Prozentpunkte auseinander

*Frage an den Betrieb · Sicherheit hoch · Aufwand klein · `src/pages/Ueberblick.tsx:66` · `v_saisonbilanz`*

**Grösse.** **9 Prozentpunkte** (Demosaison, 323268 kg Eingang)

**Was dasteht.** „16.12 % des Eingangs" (52119 von 323268 kg). Dieselbe Zahl bezogen auf das, was noch nicht ausgeliefert ist, wäre 25.13 % (52119 von 207432 kg).

**Was dastehen müsste.** Zwei Zahlen nebeneinander, jede mit ihrer Aufgabe: Saisonbilanz 16.1 % des Eingangs (was von allem, was hereinkam, weg ist) und getrennt nach Ware: ausgelieferte Ware 13.1 % (18167 von 138950 kg Eingangsmasse), liegende Ware 18.0 % (33952 von 188498 kg, wächst weiter).

**Warum das zählt.** Die dritte Lesart — Verlust geteilt durch (Eingang − Ausgang) — ist die, nach der gefragt wird, und sie ist die einzige, die niemand verwenden sollte: Der Zähler enthält auch den Verlust der Ware, die bereits ausgeliefert ist, der Nenner aber nicht mehr ihre Masse. Sie mischt zwei Bestände und ist deshalb immer zu hoch. Was hinter der Frage steckt — „welcher Prozentsatz ist die Zahl, an der ich etwas ändern kann?" — beantwortet die Trennung nach Portion, und die rechnet die Kaskade ohnehin schon: die liegende Ware ist die Zahl zum Handeln, die ausgelieferte die zum Nachrechnen.

**Gegenrede.** Man kann argumentieren, dass eine einzige Zahl leichter zu merken ist als drei. Dagegen steht, dass die eine Zahl heute schon zwei Bedeutungen trägt und der Betriebsleiter nicht sieht, welche. Die Trennung nach Portion kostet keine neue Rechnung — sie steht bereits in mv_kaskade.

<sub>Nachweis: pruefwerk/sonden/02_bezugsgroessen.mjs → lesarten(); mv_kaskade nach portion gruppiert</sub>

---

### ERF-001 · 6 Felder verlangt die Maske, die Datenbank lässt sie leer — und die Rechnung macht eine Null daraus

*Reparatur · Sicherheit hoch · Aufwand klein · `auftrag, auftrag_palette, ausgang_wiegung, ausschuss_messung, lieferung, schimmel_messung, verdunstung_wiegung`*

**Grösse.** **6 Felder, aus deren Lücke eine Null wird** (31 Felder, die die Maske verlangt)

**Was dasteht.** Mit Folge für die Rechnung (`coalesce(…, 0)` in einer Sicht): auftrag_palette.kisten, ausschuss_messung.kisten, lieferung.kg, lieferung.kisten, schimmel_messung.kisten, verdunstung_wiegung.kisten. Insgesamt 31 Felder, die die Maske verlangt und die Tabelle nicht: auftrag.kaeufer, auftrag.sortierschema_id, auftrag.kaliber_idx, auftrag.kaliber_von_g, auftrag.kaliber_bis_g, auftrag.kistensystem, auftrag.soll_kg_pro_kiste, auftrag.stueck_je_kiste, auftrag_palette.eingangsdatum, auftrag_palette.wiegung_id, auftrag_palette.brutto_zettel_kg, auftrag_palette.sortierdatum, auftrag_palette.kisten, ausgang_wiegung.gebindeart, ausgang_wiegung.kuerbisse_pro_kiste, ausgang_wiegung.kaliber_idx, ausschuss_messung.brutto_kg, ausschuss_messung.kisten, ausschuss_messung.gebindeart, lieferung.charge_nr, lieferung.sorte, lieferung.kg, lieferung.kisten, lieferung.kunde, schimmel_messung.brutto_kg, schimmel_messung.kisten, schimmel_messung.gebindeart, verdunstung_wiegung.auftrag_id, verdunstung_wiegung.kisten, verdunstung_wiegung.gebindeart, verdunstung_wiegung.kuerbisse_pro_kiste

**Was dastehen müsste.** `not null` auf den Feldern, ohne die die Zeile nicht rechenbar ist. Wo eine Lücke zulässig sein soll, gehört sie ausdrücklich zugelassen — und die Rechnung dahinter muss sie als „unbekannt" behandeln, nicht als Null.

**Warum das zählt.** Die Maske ist nicht der einzige Weg in die Tabelle: Der Excel-Import des Warenausgangs, eine Korrektur im SQL-Editor und jede künftige Maske schreiben an ihr vorbei. Die Bedingung in der Tabelle ist die einzige Stelle, die für alle Wege gilt. `palette.kisten` ist der belegte Fall: fehlt die Zahl, rechnet `v_palette` mit null Kisten und das Nettogewicht wird zu hoch (Sonde 08).

**Gegenrede.** Eine Bedingung nachträglich zu setzen kann an Altbeständen scheitern, in denen die Lücke schon steht. Dann ist die richtige Antwort nicht „lassen", sondern erst aufräumen und dann setzen — oder die Lücke sauber als „unbekannt" durch die Rechnung tragen.

<sub>Nachweis: pruefwerk/sonden/03_erfassung.mjs → 3b</sub>

---

### ERF-002 · Mehr geliefert als hereingekommen — und keine Auffälligkeit dazu

*Reparatur · Sicherheit hoch · Aufwand klein · `v_plausibilitaet`*

**Grösse.** **4180 kg mehr geliefert als erfasst** (9 Chargen, 1.29 % des Eingangs)

**Was dasteht.** 9 Chargen liefern zusammen 4180 kg mehr aus, als für sie je als Eingang erfasst wurde (36.6 % bei Charge 1635). `v_plausibilitaet` kennt dafür keine Art: gemeldet werden „Kistengewicht", „Lieferung in der Zukunft", „Ohne Nenner", „Palox geleert", „Schimmel", „Zetteldatum".

**Was dastehen müsste.** Eine Auffälligkeit „Überzählung" mit der Charge, den Kilo und dem Sprung zur Korrektur — wie bei „Zetteldatum" und „Lieferung in der Zukunft" auch. Der Betrieb sieht Auffälligkeiten unter Messungen; nur dort sucht er nach etwas zu Korrigierendem.

**Warum das zählt.** Eine Charge, die mehr abgibt, als sie bekommen hat, ist kein Verlustphänomen, sondern ein Erfassungsfehler: eine fehlende Palette im Erntejournal, eine Lieferung auf die falsche Charge gebucht, eine vertauschte Chargennummer. Die Kaskade fängt ihn ab, damit die Bilanz aufgeht — und genau deshalb fällt er niemandem auf. Er verzerrt aber jede Verlustquote dieser Charge, weil ihr Nenner zu klein ist.

**Gegenrede.** Die Zahl steht auf der Chargen-Seite jeder betroffenen Charge („mehr geliefert als hereingekommen") und in der Bilanz unter Messungen. Sie ist also nicht verborgen — nur nicht dort, wo der Betrieb nach Fehlern sucht, und ohne den Sprung zur Korrektur, den die anderen Auffälligkeiten haben.

<sub>Nachweis: pruefwerk/sonden/03_erfassung.mjs → 3c</sub>

---

### HER-001 · „Ausgeliefert" trägt die Marke „gemessen" und enthält eine Schätzung

*Reparatur · Sicherheit hoch · Aufwand klein · `src/pages/Ueberblick.tsx` · `v_saisonbilanz` · Spalte `ausgang_kg`*

**Grösse.** **5000 kg Schätzung in einer als gemessen ausgewiesenen Zahl** (4.3 % von „Ausgeliefert")

**Was dasteht.** ausgang_kg = 115836 kg mit der Marke „gemessen". Davon sind 5000 kg `vorlauf_kg` — die Angabe des Betriebs, was vor dem Erfassungsbeginn schon draussen war (1 Zeile(n) in `charge_vorlauf`, mit Bemerkung, ohne Lieferschein). Das sind 4.3 % der Zahl.

**Was dastehen müsste.** Entweder die Marke für diese Zahl anders wählen (gemessen + geschätzter Anteil), oder den Vorlauf aus der Zahl herausnehmen und daneben stellen. Der Untertitel nennt ihn bereits („… vor dem Erfassungsbeginn") — die Marke widerspricht dem Untertitel.

**Warum das zählt.** Die Seite erklärt die Marke selbst: „gemessen heisst: aus einer vollständigen Liste — jede Palette im Erntejournal, jede Lieferung auf einem Lieferschein." Für den Vorlauf gilt das nicht; er ist eine Erinnerung. Solange beides dieselbe Marke trägt, ist die Marke keine Auskunft mehr, sondern Dekoration — und sie steht an vier Stellen des Überblicks.

**Gegenrede.** Der Untertitel nennt den Vorlauf ausdrücklich, wer genau liest, sieht ihn also. Dagegen steht: Die Marke ist die Abkürzung für Leser, die nicht genau lesen — dafür wurde sie eingeführt. Eine Abkürzung, die im Sonderfall das Gegenteil sagt, ist schlechter als keine.

<sub>Nachweis: pruefwerk/sonden/01_herkunft.mjs → 1d</sub>

---

### LNN-001 · Ungemessene Verlustströme stehen als 0,00 kg statt als „unbekannt"

*Reparatur · Sicherheit hoch · Aufwand klein · `v_saisonbilanz und erg_charge` · Spalte `verdunstung_heute_kg, schimmel_heute_kg, sockel_heute_kg, fax_heute_kg, fax_erwartet_kg, kanal_ausgelagert_kg, kanal_im_haus_kg, verlust_heute_kg, verdunstung_heute_kg, schimmel_heute_kg, sockel_heute_kg, fax_heute_kg, fax_erwartet_kg, kanal_ausgelagert_kg, kanal_im_haus_kg, verlust_heute_kg`*

**Grösse.** **2850 kg Eingang ohne jede Verlustaussage** (Papierfall: 3 Paletten, 1 Lieferung, 0 Messungen)

**Was dasteht.** In einer Saison ohne eine einzige Messung (2850 kg Eingang) liefern 2 Sichten 16 Spalten als Zahl: v_saisonbilanz.verdunstung_heute_kg = 0.00, v_saisonbilanz.schimmel_heute_kg = 0.00, v_saisonbilanz.sockel_heute_kg = 0.00, v_saisonbilanz.fax_heute_kg = 0.00, v_saisonbilanz.fax_erwartet_kg = 0.00, v_saisonbilanz.kanal_ausgelagert_kg = 0.00, v_saisonbilanz.kanal_im_haus_kg = 0.00, v_saisonbilanz.verlust_heute_kg = 0.00, erg_charge.verdunstung_heute_kg = 0.00, erg_charge.schimmel_heute_kg = 0.00, erg_charge.sockel_heute_kg = 0.00, erg_charge.fax_heute_kg = 0.00, erg_charge.fax_erwartet_kg = 0.00, erg_charge.kanal_ausgelagert_kg = 0.00, erg_charge.kanal_im_haus_kg = 0.00, erg_charge.verlust_heute_kg = 0.00. Dieselben Ströme stehen in erg_verlust als NULL mit bekannt = false.

**Was dastehen müsste.** Dieselbe Antwort wie erg_verlust: NULL. Die Sichten führen das Kennzeichen bereits mit (`r_bekannt`, `f_bekannt`, `a_fax_bekannt`, `a0_bekannt` in mv_kaskade); es wird beim Bilden der Summen nur nicht abgefragt.

**Warum das zählt.** Die Wurzel steht in mv_kaskade: ein fehlender Koeffizient wird mit `coalesce(…, 0)` zu 0, und 0 · Masse ist 0 kg. Die Kennzeichen daneben sagen die Wahrheit, aber die kg-Spalten nicht — und die Oberfläche zeigt die kg-Spalte. Auf dem Überblick steht dann „Verlust bis heute: 0,0 t", obwohl niemand je gewogen hat. Das ist genau die Aussage, die das Programm laut ABLAUF.md nie machen soll.

**Gegenrede.** `verlust_bekannt = false` steht in derselben Zeile, und die Oberfläche zeigt einen Warnstreifen. Das reicht nicht: Der Streifen erklärt eine Zahl, die daneben weiter als Zahl dasteht — und in jede Prozentrechnung, jede Grafik und jeden Export eingeht. Ausserdem ist es ein Widerspruch zwischen zwei Sichten derselben Datenbank, und das ist unabhängig von der Darstellung ein Fehler.

<sub>Nachweis: pruefwerk/sonden/08_leer_nicht_null.mjs → Welt ohne Messung (pruefwerk/saison.mjs → papierfall)</sub>

---

### LNN-004 · Fehlt die Kistenzahl, wird sie als null Kisten gerechnet — und das Netto zu hoch

*Reparatur · Sicherheit hoch · Aufwand klein · `v_palette` · Spalte `netto_kg`*

**Grösse.** **3.2 % zu viel Eingang je betroffener Palette** (30 Kisten à 1 kg auf 950 kg Netto)

**Was dasteht.** Palette mit unbekannter Kistenzahl: netto_kg = 980.00 kg bei 1000 kg brutto. Die Sicht rechnet `coalesce(p.kisten, 0) * g.tara_kg_pro_kiste` — null Kisten wiegen nichts.

**Was dastehen müsste.** netto_kg = NULL. Die Palette wurde gewogen, aber nicht gezählt; ihr Nettogewicht ist unbekannt. Richtig wären hier 950 kg — die Sicht liefert 30 kg zu viel.

**Warum das zählt.** Die Kistenzahl darf leer bleiben (die Spalte ist nullable, die Erntejournal-Übernahme füllt sie nicht immer). Fehlt sie, verschwindet die Kistentara aus der Rechnung, und ihr Gewicht wird als Kürbis verbucht. Anders als bei der fehlenden Gebindeart merkt das niemand: Die Palette hat ein Netto, es ist nur falsch. `n_paletten_mit_netto` zählt sie mit, `v_plausibilitaet` schweigt.

**Gegenrede.** In den Demodaten hat jede Palette eine Kistenzahl. Die Spalte ist aber nullable, und im Betrieb ist der Zettel genau dann unvollständig, wenn es hektisch war. Auf einer echten Palette (456 kg brutto, 32 Kisten, 1,5 kg je Kiste) sind das 48 kg — gut ein Zehntel.

<sub>Nachweis: pruefwerk/sonden/08_leer_nicht_null.mjs → 8c</sub>

---

### LNN-005 · Der Eingang trägt das Zeichen „gemessen", enthält aber hochgerechnete Paletten

*Reparatur · Sicherheit hoch · Aufwand klein · `erg_charge` · Spalte `eingang_kg`*

**Grösse.** **965 kg hochgerechnet und als gemessen ausgewiesen** (1 von 3 Paletten)

**Was dasteht.** 3 Paletten, davon 2 mit Netto. eingang_kg = 2895 kg — die Palette ohne Gebindeart geht mit 965 kg ein, dem Mittel der übrigen. v_plausibilitaet meldet dazu 0 Auffälligkeiten.

**Was dastehen müsste.** Entweder ohne die Palette rechnen und das sagen, oder mit dem Mittel rechnen und die Zahl als teils hochgerechnet kennzeichnen. Der Überblick schreibt heute „<Herkunft art=gemessen> heisst: aus einer vollständigen Liste — jede Palette im Erntejournal" unter eine Zahl, die genau das nicht ist.

**Warum das zählt.** Der Eingang ist die Bezugsgrösse jeder Prozentzahl des Programms. Wenn er still zwischen gemessen und hochgerechnet mischt, ist jede Verlustquote entsprechend verschoben — und zwar ohne dass irgendwo eine Warnung erscheint. Die Zahl `n_paletten_mit_netto` steht bereits in derselben Zeile; sie wird nur auf der Seite Messungen gezeigt, nicht dort, wo die Herkunft behauptet wird.

**Gegenrede.** Die Seite Messungen zeigt „(2 m. Netto)" und listet die Taralücken. Das ist gut, trifft aber die falsche Seite: Die Herkunftsmarke steht auf dem Überblick, und wer dort liest, geht nicht erst auf Messungen nachsehen.

<sub>Nachweis: pruefwerk/sonden/08_leer_nicht_null.mjs → 8c</sub>

---

### LNN-006 · Die Masken rechnen ein Netto, auch wenn die Palettentara fehlt

*Reparatur · Sicherheit hoch · Aufwand klein · `src/arbeit/AusschussMaske.tsx:38`*

**Grösse.** **5 Masken** (src/arbeit und src/pages)

**Was dasteht.** src/arbeit/AusschussMaske.tsx:38, src/arbeit/FauleMaske.tsx:34, src/arbeit/FertigePaletteMaske.tsx:54, src/arbeit/WiegenMaske.tsx:42, src/pages/Kontrolle.tsx:63 — überall `tara.tara_kg_palette ?? 0`, während `tara_kg_pro_kiste != null` verlangt wird.

**Was dastehen müsste.** Beide Taras gleich behandeln: fehlt eine, gibt es kein Netto und die Maske sagt das. Sonst zeigt sie dem Arbeiter eine Zahl, die um die Palettentara zu hoch ist (in den Stammdaten 25 kg je Palette).

**Warum das zählt.** Der Arbeiter prüft die Plausibilität einer Wägung an der angezeigten Zahl. Ist sie um 25 kg zu hoch, nimmt er eine falsche Wägung an — oder er verwirft eine richtige. Zusätzlich weichen Maske und Datenbank voneinander ab: `v_palette.netto_kg` liefert bei fehlender Kistentara NULL, die Maske aber eine Zahl.

**Gegenrede.** Alle vier Gebindearten der Stammdaten haben heute eine Palettentara. Die Spalte ist aber nullable, und eine neue Gebindeart wird im Betrieb angelegt, ohne dass jemand die App danach prüft.

<sub>Nachweis: pruefwerk/sonden/08_leer_nicht_null.mjs → 8c</sub>

---

### MET-001 · Eine Lieferung in den Kompost verlässt den Betrieb, fehlt aber in Bestand und Verlust

*Reparatur · Sicherheit mittel · Aufwand klein · `v_lieferung_kohorte`*

**Grösse.** **100 % jeder entsorgten Menge zählen doppelt** (in den Demodaten ist nichts entsorgt; Sonde 07 misst den Fall mit 500 kg)

**Was dasteht.** v_lieferung_kohorte filtert auf buch in ('verkauf','marge'); entsorgt sind heute 0 kg

**Was dastehen müsste.** Entsorgte Ware ist echter Verlust: sie muss den Bestand verringern und im Verlust erscheinen.

**Warum das zählt.** Sie zählt in ausgang_kg (v_saisonbilanz nimmt dort alle Bücher), aber die Kaskade sieht sie nicht. Damit liegt sie rechnerisch weiter im Lager und altert weiter — dieselbe Fehlerart, die 0062 für die Marge behoben hat, nur für das dritte Buch. Solange niemand Kompost erfasst, ist es folgenlos; sobald doch, ist es eine stille Verschiebung.

**Gegenrede.** Vielleicht ist beabsichtigt, dass „entsorgt" nur eine Notiz ist. Dann dürfte es aber auch nicht in ausgang_kg stehen — dort steht es.

<sub>Nachweis: pruefwerk/sonden/05_metamorph.mjs, Abschnitt 6</sub>

---

### MUT-002 · 2 von 13 verstellten Formeln bleiben unbemerkt

*Reparatur · Sicherheit hoch · Aufwand mittel · `supabase/test/pruefung.sql`*

**Grösse.** **15 % der Verstellungen unbemerkt** (13 gezielte Verstellungen in 0061/0062)

**Was dasteht.** „Das Vorzeichen der Ableitung ∂m1/∂r gedreht" (ableitung-vorzeichen); „Der Kanal der ausgelieferten Ware zählt als „noch im Haus"" (kanal-im-haus-alles)

**Was dastehen müsste.** Zu jeder dieser Stellen eine Behauptung in pruefung.sql, die anschlägt, sobald sie verstellt wird — mit einer Zahl, die auf Papier nachrechenbar ist.

**Warum das zählt.** Diese Stellen tragen die ganze Fachlogik. Wer sie beim nächsten Umbau versehentlich verstellt, bekommt eine grüne Suite und falsche Zahlen. Genau so entstehen die Fehler, die niemand findet, weil alle Prüfungen grün sind.

**Gegenrede.** 7 Verstellungen werden erkannt (klein-statt-gross, marge-nicht-ausgeliefert, ein-tag-mehr, ueberzaehlung-ungebremst, fax-doppelt, bekannt-zu-grosszuegig, im-haus-alles) — das Netz ist also nicht leer, nur löchrig. Manche Lücke ist es auch wert: eine Verstellung, die nur den Bereich verschiebt, kostet weniger als eine, die die Kilogramm verschiebt. Die Liste sagt, wo man zuerst hinsieht.

<sub>Nachweis: pruefwerk/sonden/06_mutation.mjs → MUTATIONEN</sub>

---

### SZE-001 · Ohne jede Messung steht „Verlust bis heute: 0 kg" statt „unbekannt"

*Entscheidung des Betriebs · Sicherheit hoch · Aufwand mittel · `v_hochrechnung_basis` · Spalte `verlust_heute_kg`*

**Grösse.** **2850 kg Eingang ohne jede Verlustaussage** (Papierfall)

**Was dasteht.** verlust_heute_kg = 0, verlust_bekannt = false — auf dem Überblick: „0,0 t · 0 % des Eingangs"

**Was dastehen müsste.** Ist kein Koeffizient gemessen, ist der Verlust unbekannt. Eine leere Zahl sagt das; eine 0 behauptet eine Messung.

**Warum das zählt.** mv_kaskade rechnet mit coalesce(koeffizient, 0); v_hochrechnung_basis summiert diese Nullen. Der Grundsatz des Projekts heisst „Leer ist nicht null" — hier ist er auf der untersten Ebene verletzt. Ein Betrieb, der die App neu einrichtet und noch nichts gemessen hat, liest: kein Verlust. Das ist die gefährlichste Zahl von allen, weil sie beruhigt.

**Gegenrede.** Daneben steht `verlust_bekannt = false`, und der Überblick zeigt eine Warnung, welche Ursache nicht gemessen ist. Man könnte argumentieren, die Zahl sei ausgewiesen. Sie wird aber summiert, in Prozent gesetzt und in Grafiken gezeichnet, als wäre sie eine Messung.

<sub>Nachweis: pruefwerk/saison.mjs → papierfall(): 2850 kg Eingang, keine Messung, Verlust 0</sub>

---

### SZE-002 · Gebindeart ohne Tara: der Eingang verschwindet, und niemand sagt es

*Reparatur · Sicherheit hoch · Aufwand klein · `v_palette` · Spalte `netto_kg`*

**Grösse.** **2000 kg brutto, die aus der Bilanz fallen** (Störfall S2)

**Was dasteht.** 2 Paletten à 1000 kg brutto, Tara unbekannt → Eingang 0 kg, 0 Chargen in der Bilanz, 0 Auffälligkeiten

**Was dastehen müsste.** Entweder eine Auffälligkeit „Tara fehlt" mit der Zahl der betroffenen Paletten, oder der Eingang trägt „unvollständig".

**Warum das zählt.** v_palette.netto_kg wird NULL, und sum() überspringt die Zeile still. Der Eingang ist dann kleiner als die Wirklichkeit, trägt aber die Marke „gemessen" — und alle Prozentwerte, deren Nenner er ist, sind zu gross.

<sub>Nachweis: pruefwerk/sonden/07_szenarien.mjs → S2</sub>

---

### SZE-003 · Genähert ohne Auffälligkeit: das Zettelgewicht passt zur Charge, aber nicht zum Tag

*Reparatur · Sicherheit hoch · Aufwand klein · `v_plausibilitaet` · Spalte `art = 'Zettelgewicht'`*

**Grösse.** **1 stille Näherung je betroffener Palette** (Störfall S4)

**Was dasteht.** Masse aus „zettel-charge-tara" (950 kg), Auffälligkeiten „Zettelgewicht": 0

**Was dastehen müsste.** Wo die Massenrechnung auf die mittlere Tara ausweicht, muss die Auffälligkeit feuern.

**Warum das zählt.** Die Massenrechnung verlangt Charge **und Eingangsdatum und Brutto**; die Auffälligkeit prüft nur Charge und Brutto. Fällt ein Fall dazwischen — Zahlendreher im Datum, Palette an einem anderen Tag eingelagert —, rechnet die App mit der mittleren Tara der Charge, und niemand erfährt es. Genau die Näherung, die AB-26 sichtbar machen wollte, wird hier unsichtbar.

<sub>Nachweis: pruefwerk/sonden/07_szenarien.mjs → S4</sub>

---

### SZE-004 · Entsorgte Ware verlässt den Betrieb, liegt aber rechnerisch weiter im Lager

*Reparatur · Sicherheit hoch · Aufwand klein · `v_lieferung_kohorte`*

**Grösse.** **500 kg, die doppelt zählen (Ausgang und Bestand)** (Störfall S5)

**Was dasteht.** Eingang 1900 kg, 500 kg in den Kompost geliefert, „noch im Haus" 1900 kg, Verlust 0 kg, Ausgang 500 kg

**Was dastehen müsste.** Kompost ist echter Verlust: er muss den Bestand verringern und im Verlust erscheinen.

**Warum das zählt.** v_lieferung_kohorte filtert auf buch in (verkauf, marge) — das dritte Buch fehlt. v_saisonbilanz zählt die Lieferung aber in ausgang_kg. Die Masse ist damit gleichzeitig draussen und drin: sie altert weiter, verdunstet weiter und erscheint bis in alle Ewigkeit als Bestand. Dieselbe Fehlerart, die 0062 für die Marge behoben hat — für das dritte Buch blieb sie stehen.

<sub>Nachweis: pruefwerk/sonden/07_szenarien.mjs → S5</sub>

---

### SZE-005 · Wird eine Palette umgestapelt, steckt die Tara-Differenz in der Verdunstungsrate

*Entscheidung des Betriebs · Sicherheit hoch · Aufwand klein · `v_verdunstung_messung` · Spalte `rate_pro_tag`*

**Grösse.** **11 % zu hohe Tagesrate** (Störfall S7 (5 von 30 Kisten))

**Was dasteht.** gemessene Rate 0.000584/Tag (netto damals 955, jetzt 905)

**Was dastehen müsste.** 0.000527/Tag — beim Eingang standen 30 Kisten auf der Palette, bei der Wägung 25.

**Warum das zählt.** Die Sicht zieht von `brutto_damals_kg` und `brutto_jetzt_kg` **dieselbe** Tara ab, weil die Kistenzahl nur einmal gefragt wird. Fünf Kisten weniger sind 5 kg, die als Verdunstung gezählt werden. Der Fehler geht mit der Tagesrate potenziert in jede Verdunstungszahl der Sorte ein. ABLAUF.md nennt die Annahme seit Runde K — geprüft wird sie nicht.

**Gegenrede.** Vielleicht wird nie umgestapelt. ABLAUF.md sagt aber, die Paletten stehen gestapelt und man kommt nicht an jede heran — und die Lagerkontrolle empfiehlt ausdrücklich, beim Öffnen eines Stapels zu greifen. Genau dort wird umgestapelt.

<sub>Nachweis: pruefwerk/sonden/07_szenarien.mjs → S7</sub>

---

### SZE-006 · Eine vollständig ausgelieferte Charge liegt angeblich noch komplett im Haus

*Reparatur · Sicherheit hoch · Aufwand klein · `v_hochrechnung_basis` · Spalte `im_haus_heute_kg, lager_kg`*

**Grösse.** **950 kg zu viel „noch im Haus"** (eine vollständig ausgelieferte Charge von 950 kg)

**Was dasteht.** Eingang 950 kg, ausgeliefert 950 kg, „noch im Haus" 950 kg. Die Bilanz geht um -950 kg nicht auf, und die Auffälligkeiten melden nichts.

**Was dastehen müsste.** „Noch im Haus" 0 kg, Bilanzrest 0 kg.

**Warum das zählt.** Die Sicht rechnet `coalesce(k.im_haus_heute_kg, b.eingang_kg)` — gedacht für den Fall, dass es zu einer Charge **gar keine** Kaskadenzeile gibt (dann liegt tatsächlich noch alles). Sie greift aber auch, wenn es Zeilen gibt und nur die Portion „lager" fehlt — und das ist genau der umgekehrte Fall: Es liegt nichts mehr. Dasselbe bei `lager_kg`. Am Saisonende, wenn Charge um Charge leer wird, wird daraus die Regel: Der Bestand zeigt Ware, die längst ausgeliefert ist. Die Bilanz merkt es (der Rest bleibt stehen), aber der Rest steht nur unter Messungen, nicht auf dem Überblick.

**Gegenrede.** In der Demosaison liegt zu jeder Charge noch etwas, deshalb tritt der Fall dort nie auf. Das ist kein Gegenargument, sondern der Grund, warum er bisher niemandem aufgefallen ist: Die Demodaten bilden den Saisonanfang ab, nicht das Ende.

<sub>Nachweis: pruefwerk/sonden/07_szenarien.mjs → S8</sub>

## Klasse 2 — Kette

Erfassung, Rechnung und Anzeige passen nicht sauber zusammen; heute trägt es, morgen vielleicht nicht.

### BEZ-001 · Beschriftung nennt den Eingang, gerechnet wird mit etwas anderem

*Reparatur · Sicherheit mittel · Aufwand klein · `src/components/Diagramm.tsx:503`*

**Grösse.** **1 Stelle** (Quelltextprüfung)

**Was dasteht.** „Anteil am Eingang" über prozent(… / hover.z.bezug)

**Was dastehen müsste.** Entweder mit dem Eingang rechnen oder das nennen, womit gerechnet wird.

**Warum das zählt.** Die Beschriftung ist das, was der Leser als Nenner annimmt. Heute trägt die Stelle, weil der einzige Aufrufer den Eingang übergibt — ein zweiter Aufrufer mit einem anderen Bezug macht die Zahl still falsch.

**Gegenrede.** Solange es bei einem Aufrufer bleibt, ist nichts falsch. Der Befund ist eine Falle, keine Fehlfunktion — entsprechend klein zu bewerten.

<sub>Nachweis: src/components/Diagramm.tsx:503</sub>

---

### LNN-003 · 19 Stellen in der Oberfläche machen aus einer fehlenden Masse eine Null

*Reparatur · Sicherheit mittel · Aufwand mittel · `src/arbeit/AusschussMaske.tsx:38`*

**Grösse.** **19 Stellen** (src/**)

**Was dasteht.** src/arbeit/AusschussMaske.tsx:38 — `tara.tara_kg_palette ?? 0`; src/arbeit/FauleMaske.tsx:34 — `tara.tara_kg_palette ?? 0`; src/arbeit/FertigePaletteMaske.tsx:54 — `tara.tara_kg_palette ?? 0`; src/arbeit/WiegenMaske.tsx:42 — `tara.tara_kg_palette ?? 0`; src/auswertung/Karten.tsx:142 — `bilanz.ueberzaehlung_kg ?? 0`; src/auswertung/Karten.tsx:143 — `bilanz.ueberzaehlung_kg ?? 0`; src/auswertung/Karten.tsx:145 — `bilanz.ueberzaehlung_kg ?? 0`; src/auswertung/daten.ts:404 — `z.basis_kg ?? 0` … und 11 weitere

**Was dastehen müsste.** Fehlt eine Masse, gehört „—" hin. `?? 0` ist richtig, wo eine Summe über eine leere Liste gebildet wird (dort ist 0 beobachtet), und falsch, wo ein einzelner Wert fehlt.

**Warum das zählt.** Jede dieser Stellen kann eine unbekannte Masse in eine Summe tragen, die danach wie eine gemessene Zahl aussieht. Welche der Stellen harmlos ist, muss einzeln entschieden werden — die Liste ist der Anfang, nicht das Urteil.

**Gegenrede.** Ein grosser Teil davon steht in `reduce((a, b) => a + (b.kg ?? 0), 0)` und ist dort unbedenklich, weil die Liste selbst die Auskunft ist. Der Befund ist eine Liste zum Durchgehen, keine Behauptung, dass alle falsch sind.

<sub>Nachweis: pruefwerk/sonden/08_leer_nicht_null.mjs → 8b</sub>

---

### MUT-001 · 4 Verstellungen ändern auf den Demodaten keine einzige Zahl

*Reparatur · Sicherheit hoch · Aufwand mittel · `supabase/migrations`*

**Grösse.** **4 Verstellungen ohne Wirkung** (13 Verstellungen auf den Demodaten)

**Was dasteht.** „Der Sockel wird vom Eingangsgewicht statt vom Gewicht nach der Verdunstung genommen" (sockel-auf-m0); „Der Schimmel rechnet den Sockel nicht heraus — dieselbe Ware zweimal" (schimmel-ohne-sockel); „Der Boden des verkaufsfähigen Anteils von 25 % auf 5 %" (boden-tiefer); „Die Verdunstungsrate darf zehnmal so gross werden" (rate-deckel-weg)

**Was dastehen müsste.** Entweder Demodaten, in denen die Stelle wirkt, oder ein eigener Papierfall, der sie ansteuert. Solange keine Daten die Stelle erreichen, sagt kein Test etwas über sie — und eine grüne Suite bedeutet dort nichts.

**Warum das zählt.** Eine Formel, die auf den Prüfdaten nichts bewirkt, ist auf den Prüfdaten unsichtbar. Sie wirkt aber im Betrieb, sobald dort die passende Messung auftaucht — dann zum ersten Mal, ungeprüft. Drei Beispiele aus dieser Liste: Der Sockel a₀ ist in der Demosaison überall 0 (der Nachweis-Test hält ihn zurück), der Boden des verkaufsfähigen Anteils bei 25 % wird nie erreicht (der kleinste Anteil liegt bei 0,671), und der Deckel der Verdunstungsrate bei 5 % je Tag liegt hundertfach über der gemessenen Rate. Alle drei sind Schutzmassnahmen für den Ausnahmefall — und genau der ist ungeprüft.

<sub>Nachweis: pruefwerk/sonden/06_mutation.mjs</sub>

## Klasse 1 — Technisch

Im Bestand nachgesehen und in Ordnung befunden, oder eine Kleinigkeit ohne Folge für eine Zahl.

### ANN-002 · Geprüft: Die Annahme zur umgestapelten Palette steht in der Tabelle und ist messbar gebrochen

*kein Fehler · Sicherheit hoch · Aufwand klein · `docs/ABLAUF.md`*

**Grösse.** **1 bestätigte Annahme** (ABLAUF.md × Störfall S7)

**Was dasteht.** „Eine Palette hat bei der Wägung dieselbe Kistenzahl und dieselbe Gebindeart wie beim Eingang" — Folge laut Tabelle: wurde umgestapelt oder umgepackt, steckt die Differenz der Tara in der Rate und sieht aus wie Verdunstung

**Was dastehen müsste.** Nichts an der Tabelle. Der Störfall S7 in Sonde 07 zeigt die Grösse: fünf Kisten weniger geben eine um rund ein Zehntel zu hohe Tagesrate.

**Warum das zählt.** Die Tabelle ist an dieser Stelle vollständig und ehrlich — sie benennt genau den Fehler, den das Prüfwerk unabhängig gefunden hat. Das spricht für die Tabelle und dafür, die übrigen Zeilen ebenso ernst zu nehmen.

<sub>Nachweis: pruefwerk/sonden/07_szenarien.mjs → S7</sub>

---

### EIN-001 · Geprüft und in Ordnung: jede Spalte hält, was ihr Name verspricht

*kein Fehler · Sicherheit hoch · Aufwand klein · `alle Sichten`*

**Grösse.** **401 geprüfte Spalten** (alle Tabellen und Sichten)

**Was dasteht.** 401 Spalten mit einer Endung, die eine Einheit nennt (…_anteil, …_kg, …_tage, …_g, n_…), über 123 Tabellen und Sichten. Keine hält einen Wert ausserhalb ihres Bereichs. 3 Spalten sind einzeln begründet ausgenommen, dazu die Wortgruppe der Differenzen (Abweichung, Rest, Fehler, Versatz), bei der das Vorzeichen die Aussage ist.

**Was dastehen müsste.** Nichts.

**Warum das zählt.** Der häufigste stille Fehler in einer Auswertung ist ein Faktor hundert. Dass er hier nirgends steckt, ist kein Zufall, sondern das Ergebnis der Namensregeln aus Runde I — und diese Sonde hält sie künftig fest.

<sub>Nachweis: pruefwerk/sonden/09_einheiten.mjs</sub>

---

### LNN-002 · Geprüft und in Ordnung: die Bereiche sagen „unbekannt", der Mittelwert nicht

*kein Fehler · Sicherheit hoch · Aufwand klein · `v_saisonbilanz`*

**Grösse.** **4 Spalten, die es richtig machen** (Papierfall)

**Was dasteht.** verlust_unten_kg, verlust_oben_kg, kanal_unten_kg, kanal_oben_kg sind alle NULL — in derselben Zeile, in der verlust_heute_kg 0,00 ist.

**Was dastehen müsste.** Nichts. Diese Zeile ist der Beweis, dass die Sicht das Unwissen kennt und es an einer Stelle bereits richtig weitergibt.

**Warum das zählt.** Wenn die Grenzen NULL sein können, kann es der Mittelwert auch. Der Befund oben ist damit keine Frage der Machbarkeit, sondern eine vergessene Stelle.

<sub>Nachweis: pruefwerk/sonden/08_leer_nicht_null.mjs → 8a</sub>

