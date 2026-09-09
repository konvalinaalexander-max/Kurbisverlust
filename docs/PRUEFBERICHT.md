# Prüfbericht

*Erzeugt von `pruefwerk/bericht.mjs` aus dem Lauf des Prüfwerks. Nicht von Hand ändern —
die Fassung, die zählt, entsteht neu mit `node pruefwerk/lauf.mjs && node pruefwerk/bericht.mjs`.*

## Was hier steht

8 Feststellungen aus 10 Sonden. Jede hat eine Grösse — ohne Grösse
ist eine Feststellung eine Meinung, und eine Liste von Meinungen nimmt niemand ernst. Jede hat
eine Gegenrede, wo es eine gibt: das beste Argument dagegen, aufgeschrieben von dem, der die
Feststellung gemacht hat.

Nicht jede Feststellung ist ein Fehler. 4 sind ausdrücklich
„geprüft und in Ordnung" — sie stehen hier, weil ein Bericht, der nur Fehler nennt, nicht sagt,
wie weit nachgesehen wurde.

| Klasse | Was das heisst | Anzahl |
|---|---|---|
| 3 — Bedeutung | Die Zahl steht da und meint etwas anderes, als der Leser denkt — oder sie ist falsch. | 2 |
| 2 — Kette | Erfassung, Rechnung und Anzeige passen nicht sauber zusammen; heute trägt es, morgen vielleicht nicht. | 2 |
| 1 — Technisch | Im Bestand nachgesehen und in Ordnung befunden, oder eine Kleinigkeit ohne Folge für eine Zahl. | 4 |

| Marke | Was zu tun ist | Anzahl |
|---|---|---|
| Reparatur | Etwas ist falsch und lässt sich richtigstellen, ohne die App zu erweitern. | 2 |
| Frage an den Betrieb | Zwei Lesarten sind beide vertretbar; entscheiden muss der Betrieb. | 1 |
| Entscheidung des Betriebs | Es geht um den Ablauf im Betrieb, nicht um den Code. | 1 |
| kein Fehler | Nachgesehen, in Ordnung. | 4 |

## Was geprüft wurde

| Sonde | Feststellungen | Dauer | Selbstprobe |
|---|---|---|---|
| `01_herkunft` | 0 | 12.6 s | ok |
| `02_bezugsgroessen` | 1 | 0.2 s | ok |
| `03_erfassung` | 1 | 1.6 s | ok |
| `04_orakel` | 1 | 0.5 s | ok |
| `05_metamorph` | 0 | 6.8 s | ok |
| `06_mutation` | 1 | 1049.1 s | ok |
| `07_szenarien` | 1 | 57.5 s | ok |
| `08_leer_nicht_null` | 1 | 18.3 s | ok |
| `09_einheiten` | 1 | 40.8 s | ok |
| `10_annahmen` | 1 | 0.3 s | ok |

Die Spalte **Selbstprobe** ist die wichtigste der Tabelle. Jede Sonde bekommt einen Fall
vorgesetzt, in dem sie anschlagen *muss*. Steht dort „ok", hat sie ihren eigenen eingebauten
Fehler gefunden; steht dort „STUMPF", sagt auch ihr leeres Ergebnis nichts.

## Klasse 3 — Bedeutung

Die Zahl steht da und meint etwas anderes, als der Leser denkt — oder sie ist falsch.

### BEZ-001 · Verlust in Prozent — wovon? Drei Lesarten, bis zu 9.0 Prozentpunkte auseinander

*Frage an den Betrieb · Sicherheit hoch · Aufwand klein · `src/pages/Ueberblick.tsx:66` · `v_saisonbilanz`*

**Grösse.** **9 Prozentpunkte** (Demosaison, 323268 kg Eingang)

**Was dasteht.** „16.12 % des Eingangs" (52119 von 323268 kg). Dieselbe Zahl bezogen auf das, was noch nicht ausgeliefert ist, wäre 25.13 % (52119 von 207432 kg).

**Was dastehen müsste.** Zwei Zahlen nebeneinander, jede mit ihrer Aufgabe: Saisonbilanz 16.1 % des Eingangs (was von allem, was hereinkam, weg ist) und getrennt nach Ware: ausgelieferte Ware 13.1 % (18167 von 138950 kg Eingangsmasse), liegende Ware 18.0 % (33952 von 188498 kg, wächst weiter).

**Warum das zählt.** Die dritte Lesart — Verlust geteilt durch (Eingang − Ausgang) — ist die, nach der gefragt wird, und sie ist die einzige, die niemand verwenden sollte: Der Zähler enthält auch den Verlust der Ware, die bereits ausgeliefert ist, der Nenner aber nicht mehr ihre Masse. Sie mischt zwei Bestände und ist deshalb immer zu hoch. Was hinter der Frage steckt — „welcher Prozentsatz ist die Zahl, an der ich etwas ändern kann?" — beantwortet die Trennung nach Portion, und die rechnet die Kaskade ohnehin schon: die liegende Ware ist die Zahl zum Handeln, die ausgelieferte die zum Nachrechnen.

**Gegenrede.** Man kann argumentieren, dass eine einzige Zahl leichter zu merken ist als drei. Dagegen steht, dass die eine Zahl heute schon zwei Bedeutungen trägt und der Betriebsleiter nicht sieht, welche. Die Trennung nach Portion kostet keine neue Rechnung — sie steht bereits in mv_kaskade.

<sub>Nachweis: pruefwerk/sonden/02_bezugsgroessen.mjs → lesarten(); mv_kaskade nach portion gruppiert</sub>

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

### ERF-001 · 31 Felder verlangt die Maske, die Datenbank lässt sie leer

*Reparatur · Sicherheit hoch · Aufwand klein · `auftrag, auftrag_palette, ausgang_wiegung, ausschuss_messung, lieferung, schimmel_messung, verdunstung_wiegung`*

**Grösse.** **31 Felder ohne Bedingung** (31 Felder, die die Maske verlangt)

**Was dasteht.** Insgesamt 31 Felder, die die Maske verlangt und die Tabelle nicht: auftrag.kaeufer, auftrag.sortierschema_id, auftrag.kaliber_idx, auftrag.kaliber_von_g, auftrag.kaliber_bis_g, auftrag.kistensystem, auftrag.soll_kg_pro_kiste, auftrag.stueck_je_kiste, auftrag_palette.eingangsdatum, auftrag_palette.wiegung_id, auftrag_palette.brutto_zettel_kg, auftrag_palette.sortierdatum, auftrag_palette.kisten, ausgang_wiegung.gebindeart, ausgang_wiegung.kuerbisse_pro_kiste, ausgang_wiegung.kaliber_idx, ausschuss_messung.brutto_kg, ausschuss_messung.kisten, ausschuss_messung.gebindeart, lieferung.charge_nr, lieferung.sorte, lieferung.kg, lieferung.kisten, lieferung.kunde, schimmel_messung.brutto_kg, schimmel_messung.kisten, schimmel_messung.gebindeart, verdunstung_wiegung.auftrag_id, verdunstung_wiegung.kisten, verdunstung_wiegung.gebindeart, verdunstung_wiegung.kuerbisse_pro_kiste

**Was dastehen müsste.** `not null` auf den Feldern, ohne die die Zeile nicht rechenbar ist. Wo eine Lücke zulässig sein soll, gehört sie ausdrücklich zugelassen — und die Rechnung dahinter muss sie als „unbekannt" behandeln, nicht als Null.

**Warum das zählt.** Die Maske ist nicht der einzige Weg in die Tabelle: Der Excel-Import des Warenausgangs, eine Korrektur im SQL-Editor und jede künftige Maske schreiben an ihr vorbei. Die Bedingung in der Tabelle ist die einzige Stelle, die für alle Wege gilt. `palette.kisten` ist der belegte Fall: fehlt die Zahl, rechnet `v_palette` mit null Kisten und das Nettogewicht wird zu hoch (Sonde 08).

**Gegenrede.** Eine Bedingung nachträglich zu setzen kann an Altbeständen scheitern, in denen die Lücke schon steht. Dann ist die richtige Antwort nicht „lassen", sondern erst aufräumen und dann setzen — oder die Lücke sauber als „unbekannt" durch die Rechnung tragen.

<sub>Nachweis: pruefwerk/sonden/03_erfassung.mjs → 3b</sub>

---

### MUT-001 · 4 Verstellungen ändern auf den Demodaten keine einzige Zahl

*Reparatur · Sicherheit hoch · Aufwand mittel · `supabase/migrations`*

**Grösse.** **4 Verstellungen ohne Wirkung** (15 Verstellungen auf den Demodaten)

**Was dasteht.** „Der Sockel wird vom Eingangsgewicht statt vom Gewicht nach der Verdunstung genommen" (sockel-auf-m0); „Der Schimmel rechnet den Sockel nicht heraus — dieselbe Ware zweimal" (schimmel-ohne-sockel); „Der Boden des verkaufsfähigen Anteils von 25 % auf 5 %" (boden-tiefer); „Die Verdunstungsrate darf zehnmal so gross werden" (rate-deckel-weg)

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

**Grösse.** **401 geprüfte Spalten** (alle Tabellen und Sichten)

**Was dasteht.** 401 Spalten mit einer Endung, die eine Einheit nennt (…_anteil, …_kg, …_tage, …_g, n_…), über 124 Tabellen und Sichten. Keine hält einen Wert ausserhalb ihres Bereichs. 3 Spalten sind einzeln begründet ausgenommen, dazu die Wortgruppe der Differenzen (Abweichung, Rest, Fehler, Versatz), bei der das Vorzeichen die Aussage ist.

**Was dastehen müsste.** Nichts.

**Warum das zählt.** Der häufigste stille Fehler in einer Auswertung ist ein Faktor hundert. Dass er hier nirgends steckt, ist kein Zufall, sondern das Ergebnis der Namensregeln aus Runde I — und diese Sonde hält sie künftig fest.

<sub>Nachweis: pruefwerk/sonden/09_einheiten.mjs</sub>

---

### LNN-001 · Geprüft: alle 7 Stellen mit `?? 0` an einer Masse sind begründet

*kein Fehler · Sicherheit hoch · Aufwand keiner · `src/auswertung/tempo.ts:25`*

**Grösse.** **7 begründete Stellen** (src/**)

**Was dasteht.** src/auswertung/tempo.ts:25, src/pages/Messungen.tsx:73, src/pages/Messungen.tsx:73, src/pages/Ursachen.tsx:405, src/pages/Ursachen.tsx:434, src/pages/Ursachen.tsx:434, src/pages/Ursachen.tsx:444 — über jeder steht, warum die Null dort beobachtet und nicht erfunden ist (gefilterte Liste, Sortierschlüssel, oder eine Summe nur über das Gerechnete).

**Was dastehen müsste.** So. Die Sonde prüft nicht, dass es keine solchen Stellen gibt — sie prüft, dass keine ohne Begründung dasteht.

**Warum das zählt.** Ein `?? 0` über einer leeren Liste ist richtig, über einem fehlenden Einzelwert falsch. Die Regel kann das nicht unterscheiden, der Satz darüber schon.

**Gegenrede.** Ein Kommentar kann falsch sein; die Sonde liest ihn nicht, sie zählt ihn. Sie hält damit die Stellen sichtbar, nicht die Begründungen wahr.

<sub>Nachweis: pruefwerk/sonden/08_leer_nicht_null.mjs → 8b</sub>

---

### ORA-001 · Gemessen: die drei Schutzgrenzen der Kaskade sind weit entfernt — und darum ungeprüft

*kein Fehler · Sicherheit hoch · Aufwand klein · `mv_kaskade`*

**Grösse.** **0.421 Abstand des kleinsten Anteils zum Boden** (156 Portionen)

**Was dasteht.** Kleinster verkaufsfähiger Anteil 0.671 (Boden bei 0,250). Grösste Verdunstungsrate 0.062 % je Tag (Deckel bei 5 %). Grösster Sockel a₀ 0.00 % (nicht nachweisbar, also 0).

**Was dastehen müsste.** Nichts — die Zahlen sind die Auskunft. Sie stehen hier, damit der Abstand nicht unbemerkt kleiner wird.

**Warum das zählt.** Der Boden bei 25 % verhindert eine Division durch fast null, wenn eine Sorte sehr schlecht hält; der Deckel bei 5 % je Tag fängt einen Zahlendreher in einer Wägung ab; der Sockel trennt Feldschäden von Lagerschäden. Alle drei wirken nur im Ausnahmefall — und genau der kommt in den Demodaten nicht vor. Eine Verstellung an ihnen bleibt deshalb unbemerkt, ohne dass es an den Prüfungen läge.

<sub>Nachweis: pruefwerk/sonden/04_orakel.mjs → 4g; Gegenstück zu MUT-001 in Sonde 06</sub>

