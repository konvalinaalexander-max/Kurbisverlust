# Prüfbericht

*Erzeugt von `pruefwerk/bericht.mjs` aus dem Lauf des Prüfwerks. Nicht von Hand ändern —
die Fassung, die zählt, entsteht neu mit `node pruefwerk/lauf.mjs && node pruefwerk/bericht.mjs`.*

## Was hier steht

12 Feststellungen aus 10 Sonden. Jede hat eine Grösse — ohne Grösse
ist eine Feststellung eine Meinung, und eine Liste von Meinungen nimmt niemand ernst. Jede hat
eine Gegenrede, wo es eine gibt: das beste Argument dagegen, aufgeschrieben von dem, der die
Feststellung gemacht hat.

Nicht jede Feststellung ist ein Fehler. 3 sind ausdrücklich
„geprüft und in Ordnung" — sie stehen hier, weil ein Bericht, der nur Fehler nennt, nicht sagt,
wie weit nachgesehen wurde.

| Klasse | Was das heisst | Anzahl |
|---|---|---|
| 3 — Bedeutung | Die Zahl steht da und meint etwas anderes, als der Leser denkt — oder sie ist falsch. | 5 |
| 2 — Kette | Erfassung, Rechnung und Anzeige passen nicht sauber zusammen; heute trägt es, morgen vielleicht nicht. | 4 |
| 1 — Technisch | Im Bestand nachgesehen und in Ordnung befunden, oder eine Kleinigkeit ohne Folge für eine Zahl. | 3 |

| Marke | Was zu tun ist | Anzahl |
|---|---|---|
| Reparatur | Etwas ist falsch und lässt sich richtigstellen, ohne die App zu erweitern. | 7 |
| Frage an den Betrieb | Zwei Lesarten sind beide vertretbar; entscheiden muss der Betrieb. | 1 |
| Entscheidung des Betriebs | Es geht um den Ablauf im Betrieb, nicht um den Code. | 1 |
| kein Fehler | Nachgesehen, in Ordnung. | 3 |

## Was geprüft wurde

| Sonde | Feststellungen | Dauer | Selbstprobe |
|---|---|---|---|
| `01_herkunft` | 1 | 26.4 s | ok |
| `02_bezugsgroessen` | 3 | 0.2 s | ok |
| `03_erfassung` | 1 | 2.2 s | ok |
| `04_orakel` | 1 | 0.4 s | ok |
| `05_metamorph` | 1 | 12.8 s | ok |
| `06_mutation` | 1 | 1752.6 s | ok |
| `07_szenarien` | 1 | 63.3 s | ok |
| `08_leer_nicht_null` | 1 | 21 s | ok |
| `09_einheiten` | 1 | 135 s | ok |
| `10_annahmen` | 1 | 0.5 s | ok |

Die Spalte **Selbstprobe** ist die wichtigste der Tabelle. Jede Sonde bekommt einen Fall
vorgesetzt, in dem sie anschlagen *muss*. Steht dort „ok", hat sie ihren eigenen eingebauten
Fehler gefunden; steht dort „STUMPF", sagt auch ihr leeres Ergebnis nichts.

## Klasse 3 — Bedeutung

Die Zahl steht da und meint etwas anderes, als der Leser denkt — oder sie ist falsch.

### BEZ-002 · Prozentzahl aus „verlust", ohne zu prüfen, ob „verlust" gemessen ist

*Reparatur · Sicherheit hoch · Aufwand klein · `src/pages/Ursachen.tsx:147`*

**Grösse.** **1 Stellen, die eine ungemessene Null als Prozent zeigen** (Strom „verlust")

**Was dasteht.** src/pages/Ursachen.tsx:147 — `prozent(eingang > 0 ? verlust / eingang : null)`, beschriftet „function Wohin("

**Was dastehen müsste.** Ist `verlust_bekannt` falsch, gehört dort „nicht gemessen" hin, nicht eine Zahl. Die Datenbank führt das Kennzeichen bereits mit; es wird an dieser Stelle nur nicht gelesen.

**Warum das zählt.** Ohne eine einzige Messung ist der Strom 0 kg — und 0 kg von einem Eingang sind 0,0 %. Der Leser sieht eine gemessene Null, wo nichts gemessen wurde. Genau dieser Fall tritt auf jedem Betrieb in der ersten Saison ein, bevor die erste Palette gewogen ist.

**Gegenrede.** In den Demodaten ist `verlust` immer gemessen, deshalb fällt es nie auf — das ist kein Gegenargument, sondern die Erklärung, warum es stehen blieb.

<sub>Nachweis: src/pages/Ursachen.tsx:147</sub>

---

### BEZ-003 · Verlust in Prozent — wovon? Drei Lesarten, bis zu 9.6 Prozentpunkte auseinander

*Frage an den Betrieb · Sicherheit hoch · Aufwand klein · `src/pages/Lagermanagement.tsx` · `v_saisonbilanz`*

**Grösse.** **9.6 Prozentpunkte** (Demosaison, 362170 kg Eingang)

**Was dasteht.** „14.87 % des Eingangs" (53848 von 362170 kg). Dieselbe Zahl bezogen auf das, was noch nicht ausgeliefert ist, wäre 24.49 % (53848 von 219867 kg).

**Was dastehen müsste.** Zwei Zahlen nebeneinander, jede mit ihrer Aufgabe: Saisonbilanz 14.9 % des Eingangs (was von allem, was hereinkam, weg ist) und getrennt nach Ware: ausgelieferte Ware 10.5 % (17445 von 165610 kg Eingangsmasse), liegende Ware 18.2 % (36402 von 200249 kg, wächst weiter).

**Warum das zählt.** Die dritte Lesart — Verlust geteilt durch (Eingang − Ausgang) — ist die, nach der gefragt wird, und sie ist die einzige, die niemand verwenden sollte: Der Zähler enthält auch den Verlust der Ware, die bereits ausgeliefert ist, der Nenner aber nicht mehr ihre Masse. Sie mischt zwei Bestände und ist deshalb immer zu hoch. Was hinter der Frage steckt — „welcher Prozentsatz ist die Zahl, an der ich etwas ändern kann?" — beantwortet die Trennung nach Portion, und die rechnet die Kaskade ohnehin schon: die liegende Ware ist die Zahl zum Handeln, die ausgelieferte die zum Nachrechnen.

**Gegenrede.** Man kann argumentieren, dass eine einzige Zahl leichter zu merken ist als drei. Dagegen steht, dass die eine Zahl heute schon zwei Bedeutungen trägt und der Betriebsleiter nicht sieht, welche. Die Trennung nach Portion kostet keine neue Rechnung — sie steht bereits in mv_kaskade.

<sub>Nachweis: pruefwerk/sonden/02_bezugsgroessen.mjs → lesarten(); mv_kaskade nach portion gruppiert</sub>

---

### HER-001 · „Ausgang" trägt die Marke „gemessen" und enthält eine Schätzung

*Reparatur · Sicherheit hoch · Aufwand klein · `src/pages/Lagermanagement.tsx` · `v_saisonbilanz` · Spalte `ausgang_kg`*

**Grösse.** **5000 kg Schätzung in einer als gemessen ausgewiesenen Zahl** (3.5 % von „Ausgang")

**Was dasteht.** ausgang_kg = 142302 kg mit der Marke „gemessen". Davon sind 5000 kg `vorlauf_kg` — die Angabe des Betriebs, was vor dem Erfassungsbeginn schon draussen war (1 Zeile(n) in `charge_vorlauf`, mit Bemerkung, ohne Lieferschein). Das sind 3.5 % der Zahl.

**Was dastehen müsste.** Entweder die Marke für diese Zahl anders wählen (gemessen + geschätzter Anteil), oder den Vorlauf aus der Zahl herausnehmen und daneben stellen. Der Untertitel nennt ihn bereits („… vor dem Erfassungsbeginn") — die Marke widerspricht dem Untertitel.

**Warum das zählt.** Die Seite erklärt die Marke selbst: „gemessen heisst: aus einer vollständigen Liste — jede Palette im Erntejournal, jede Lieferung auf einem Lieferschein." Für den Vorlauf gilt das nicht; er ist eine Erinnerung. Solange beides dieselbe Marke trägt, ist die Marke keine Auskunft mehr, sondern Dekoration — und sie steht an vier Stellen des Lagermanagements.

**Gegenrede.** Der Untertitel nennt den Vorlauf ausdrücklich, wer genau liest, sieht ihn also. Dagegen steht: Die Marke ist die Abkürzung für Leser, die nicht genau lesen — dafür wurde sie eingeführt. Eine Abkürzung, die im Sonderfall das Gegenteil sagt, ist schlechter als keine.

<sub>Nachweis: pruefwerk/sonden/01_herkunft.mjs → 1d</sub>

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

### SZE-002 · Wird eine Palette umgestapelt, steckt die Tara-Differenz in der Verdunstungsrate

*Entscheidung des Betriebs · Sicherheit hoch · Aufwand klein · `v_verdunstung_messung` · Spalte `rate_pro_tag`*

**Grösse.** **11 % zu hohe Tagesrate** (Störfall S7 (5 von 30 Kisten))

**Was dasteht.** gemessene Rate 0.000584/Tag (netto damals 955, jetzt 905)

**Was dastehen müsste.** 0.000527/Tag — beim Eingang standen 30 Kisten auf der Palette, bei der Wägung 25.

**Warum das zählt.** Die Sicht zieht von `brutto_damals_kg` und `brutto_jetzt_kg` **dieselbe** Tara ab, weil die Kistenzahl nur einmal gefragt wird. Fünf Kisten weniger sind 5 kg, die als Verdunstung gezählt werden. Der Fehler geht mit der Tagesrate potenziert in jede Verdunstungszahl der Sorte ein. ABLAUF.md nennt die Annahme seit Runde K — geprüft wird sie nicht.

**Gegenrede.** Vielleicht wird nie umgestapelt. ABLAUF.md sagt aber, die Paletten stehen gestapelt und man kommt nicht an jede heran — und die Lagerkontrolle empfiehlt ausdrücklich, beim Öffnen eines Stapels zu greifen. Genau dort wird umgestapelt.

<sub>Nachweis: pruefwerk/sonden/07_szenarien.mjs → S7</sub>

## Klasse 2 — Kette

Erfassung, Rechnung und Anzeige passen nicht sauber zusammen; heute trägt es, morgen vielleicht nicht.

### BEZ-001 · Prozentzahl ohne Wache auf dem Nenner

*Reparatur · Sicherheit hoch · Aufwand klein · `src/pages/Ursachen.tsx:461`*

**Grösse.** **1 Stelle** (Quelltextprüfung)

**Was dasteht.** prozent(z.zuviel_je_kiste / z.soll_kg_pro_kiste)

**Was dastehen müsste.** prozent(z.soll_kg_pro_kiste > 0 ? z.zuviel_je_kiste / z.soll_kg_pro_kiste : null) — ohne Nenner ist der Anteil unbekannt, nicht null und nicht unendlich.

**Warum das zählt.** Ist der Nenner 0, kommt Infinity oder NaN heraus. `prozent()` fängt NaN ab und schreibt „—", Infinity aber nicht: dort stünde „∞ %".

<sub>Nachweis: src/pages/Ursachen.tsx:461</sub>

---

### ERF-001 · 32 Felder verlangt die Maske, die Datenbank lässt sie leer

*Reparatur · Sicherheit hoch · Aufwand klein · `auftrag, auftrag_palette, ausgang_wiegung, ausschuss_messung, lieferung, schimmel_messung, verdunstung_wiegung`*

**Grösse.** **32 Felder ohne Bedingung** (32 Felder, die die Maske verlangt)

**Was dasteht.** Insgesamt 32 Felder, die die Maske verlangt und die Tabelle nicht: auftrag.kaeufer, auftrag.sortierschema_id, auftrag.kaliber_idx, auftrag.kaliber_von_g, auftrag.kaliber_bis_g, auftrag.kistensystem, auftrag.soll_kg_pro_kiste, auftrag.stueck_je_kiste, auftrag_palette.eingangsdatum, auftrag_palette.wiegung_id, auftrag_palette.brutto_zettel_kg, auftrag_palette.sortierdatum, auftrag_palette.kisten, auftrag_palette.gebindeart, ausgang_wiegung.gebindeart, ausgang_wiegung.kuerbisse_pro_kiste, ausgang_wiegung.kaliber_idx, ausschuss_messung.brutto_kg, ausschuss_messung.kisten, ausschuss_messung.gebindeart, lieferung.charge_nr, lieferung.sorte, lieferung.kg, lieferung.kisten, lieferung.kunde, schimmel_messung.brutto_kg, schimmel_messung.kisten, schimmel_messung.gebindeart, verdunstung_wiegung.auftrag_id, verdunstung_wiegung.kisten, verdunstung_wiegung.gebindeart, verdunstung_wiegung.kuerbisse_pro_kiste

**Was dastehen müsste.** `not null` auf den Feldern, ohne die die Zeile nicht rechenbar ist. Wo eine Lücke zulässig sein soll, gehört sie ausdrücklich zugelassen — und die Rechnung dahinter muss sie als „unbekannt" behandeln, nicht als Null.

**Warum das zählt.** Die Maske ist nicht der einzige Weg in die Tabelle: Der Excel-Import des Warenausgangs, eine Korrektur im SQL-Editor und jede künftige Maske schreiben an ihr vorbei. Die Bedingung in der Tabelle ist die einzige Stelle, die für alle Wege gilt. `palette.kisten` ist der belegte Fall: fehlt die Zahl, rechnet `v_palette` mit null Kisten und das Nettogewicht wird zu hoch (Sonde 08).

**Gegenrede.** Eine Bedingung nachträglich zu setzen kann an Altbeständen scheitern, in denen die Lücke schon steht. Dann ist die richtige Antwort nicht „lassen", sondern erst aufräumen und dann setzen — oder die Lücke sauber als „unbekannt" durch die Rechnung tragen.

<sub>Nachweis: pruefwerk/sonden/03_erfassung.mjs → 3b</sub>

---

### LNN-001 · 10 Stellen machen aus einer fehlenden Masse eine Null, ohne zu sagen warum

*Reparatur · Sicherheit mittel · Aufwand klein · `src/auswertung/daten.ts:810`*

**Grösse.** **10 unbegründete Stellen** (11 Stellen mit `?? 0` an einer Masse)

**Was dasteht.** src/auswertung/daten.ts:810 — `m.sockel ?? 0`; src/pages/Lagermanagement.tsx:163 — `w?.geliefert_kg ?? 0`; src/pages/Lagermanagement.tsx:164 — `w?.geliefert_kg ?? 0`; src/pages/Lagermanagement.tsx:165 — `w?.kanal_ausgelagert_kg ?? 0`; src/pages/Messungen.tsx:75 — `b.eingang_kg ?? 0`; src/pages/Messungen.tsx:75 — `a.eingang_kg ?? 0`; src/pages/Ursachen.tsx:142 — `w?.rest_kg ?? 0`; src/pages/Ursachen.tsx:142 — `w?.lager_rest_kg ?? 0` … und 2 weitere (von 11 Stellen insgesamt sind 1 begründet).

**Was dastehen müsste.** Fehlt eine Masse, gehört „—" hin. `?? 0` ist richtig, wo eine Summe über eine leere Liste gebildet oder ein Sortierschlüssel gebraucht wird (dort ist 0 beobachtet), und falsch, wo ein einzelner Wert fehlt. Was von beidem gilt, gehört als Satz darüber.

**Warum das zählt.** Jede dieser Stellen kann eine unbekannte Masse in eine Summe tragen, die danach wie eine gemessene Zahl aussieht. Welche harmlos ist, kann nur entscheiden, wer sie geschrieben hat — und muss es aufschreiben, sonst entscheidet es der nächste neu.

**Gegenrede.** Ein grosser Teil solcher Stellen steht in `reduce((a, b) => a + (b.kg ?? 0), 0)` und ist dort unbedenklich, weil die Liste selbst die Auskunft ist. Der Befund verlangt keine Änderung an der Rechnung, nur einen Satz darüber.

<sub>Nachweis: pruefwerk/sonden/08_leer_nicht_null.mjs → 8b</sub>

---

### MUT-001 · 5 Verstellungen ändern auf den Demodaten keine einzige Zahl

*Reparatur · Sicherheit hoch · Aufwand mittel · `supabase/migrations`*

**Grösse.** **5 Verstellungen ohne Wirkung** (15 Verstellungen auf den Demodaten)

**Was dasteht.** „Der Sockel wird vom Eingangsgewicht statt vom Gewicht nach der Verdunstung genommen" (sockel-auf-m0); „Der Schimmel rechnet den Sockel nicht heraus — dieselbe Ware zweimal" (schimmel-ohne-sockel); „Der Boden des verkaufsfähigen Anteils von 25 % auf 5 %" (boden-tiefer); „Die Verdunstungsrate darf zehnmal so gross werden" (rate-deckel-weg); „Das Fax-Faule der liegenden Ware zählt als Verlust bis heute" (fax-doppelt)

**Was dastehen müsste.** Entweder Demodaten, in denen die Stelle wirkt, oder ein eigener Papierfall, der sie ansteuert. Solange keine Daten die Stelle erreichen, sagt kein Test etwas über sie — und eine grüne Suite bedeutet dort nichts.

**Warum das zählt.** Eine Formel, die auf den Prüfdaten nichts bewirkt, ist auf den Prüfdaten unsichtbar. Sie wirkt aber im Betrieb, sobald dort die passende Messung auftaucht — dann zum ersten Mal, ungeprüft. Drei Beispiele aus dieser Liste: Der Sockel a₀ ist in der Demosaison überall 0 (der Nachweis-Test hält ihn zurück), der Boden des verkaufsfähigen Anteils bei 25 % wird nie erreicht (der kleinste Anteil liegt bei 0,671), und der Deckel der Verdunstungsrate bei 5 % je Tag liegt hundertfach über der gemessenen Rate. Alle drei sind Schutzmassnahmen für den Ausnahmefall — und genau der ist ungeprüft. Wie weit der Betrieb von jeder der drei Grenzen entfernt ist, misst ORA-001 (Sonde 04g); die Zahlen dort sind der Massstab dafür, wie dringend dieser Befund ist.

<sub>Nachweis: pruefwerk/sonden/06_mutation.mjs (Abstand zu den Grenzen: Sonde 04 → 4g, ORA-001)</sub>

## Klasse 1 — Technisch

Im Bestand nachgesehen und in Ordnung befunden, oder eine Kleinigkeit ohne Folge für eine Zahl.

### ANN-001 · Geprüft: Die Annahme zur umgestapelten Palette steht in der Tabelle und ist messbar gebrochen

*kein Fehler · Sicherheit hoch · Aufwand klein · `docs/ABLAUF.md`*

**Grösse.** **1 bestätigte Annahme** (ABLAUF.md × Störfall S7)

**Was dasteht.** „Eine Palette hat bei der Wägung dieselbe Kistenzahl und dieselbe Gebindeart wie beim Eingang" — Folge laut Tabelle: wurde umgestapelt oder umgepackt, steckt die Differenz der Tara in der Rate und sieht aus wie Verdunstung

**Was dastehen müsste.** Nichts an der Tabelle. Der Störfall S7 in Sonde 07 zeigt die Grösse: fünf Kisten weniger geben eine um rund ein Zehntel zu hohe Tagesrate.

**Warum das zählt.** Die Tabelle ist an dieser Stelle vollständig und ehrlich — sie benennt genau den Fehler, den das Prüfwerk unabhängig gefunden hat. Das spricht für die Tabelle und dafür, die übrigen Zeilen ebenso ernst zu nehmen.

<sub>Nachweis: pruefwerk/sonden/07_szenarien.mjs → S7</sub>

---

### EIN-001 · Geprüft und in Ordnung: jede Spalte hält, was ihr Name verspricht

*kein Fehler · Sicherheit hoch · Aufwand klein · `alle Sichten`*

**Grösse.** **523 geprüfte Spalten** (alle Tabellen und Sichten)

**Was dasteht.** 523 Spalten mit einer Endung, die eine Einheit nennt (…_anteil, …_kg, …_tage, …_g, n_…), über 145 Tabellen und Sichten. Keine hält einen Wert ausserhalb ihres Bereichs. 3 Spalten sind einzeln begründet ausgenommen, dazu die Wortgruppe der Differenzen (Abweichung, Rest, Fehler, Versatz), bei der das Vorzeichen die Aussage ist.

**Was dastehen müsste.** Nichts.

**Warum das zählt.** Der häufigste stille Fehler in einer Auswertung ist ein Faktor hundert. Dass er hier nirgends steckt, ist kein Zufall, sondern das Ergebnis der Namensregeln aus Runde I — und diese Sonde hält sie künftig fest.

<sub>Nachweis: pruefwerk/sonden/09_einheiten.mjs</sub>

---

### ORA-001 · Gemessen: die drei Schutzgrenzen der Kaskade sind weit entfernt — und darum ungeprüft

*kein Fehler · Sicherheit hoch · Aufwand klein · `mv_kaskade`*

**Grösse.** **0.441 Abstand des kleinsten Anteils zum Boden** (187 Portionen)

**Was dasteht.** Kleinster verkaufsfähiger Anteil 0.691 (Boden bei 0,250). Grösste Verdunstungsrate 0.051 % je Tag (Deckel bei 5 %). Grösster Sockel a₀ 0.00 % (nicht nachweisbar, also 0).

**Was dastehen müsste.** Nichts — die Zahlen sind die Auskunft. Sie stehen hier, damit der Abstand nicht unbemerkt kleiner wird.

**Warum das zählt.** Der Boden bei 25 % verhindert eine Division durch fast null, wenn eine Sorte sehr schlecht hält; der Deckel bei 5 % je Tag fängt einen Zahlendreher in einer Wägung ab; der Sockel trennt Feldschäden von Lagerschäden. Alle drei wirken nur im Ausnahmefall — und genau der kommt in den Demodaten nicht vor. Eine Verstellung an ihnen bleibt deshalb unbemerkt, ohne dass es an den Prüfungen läge.

<sub>Nachweis: pruefwerk/sonden/04_orakel.mjs → 4g; Gegenstück zu MUT-001 in Sonde 06</sub>

