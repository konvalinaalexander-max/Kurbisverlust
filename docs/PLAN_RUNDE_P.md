# Plan Runde P — die zwei Fragen des Betriebsleiters

Dieser Plan ist von einer KI für eine andere geschrieben. Die erste hat
gelesen, gerechnet und entschieden (Kaskade, Sichten, Demo-Zahlen, offene
Fragen); die zweite baut, prüft und berichtet. Der Auftrag an sie steht in
`docs/PROMPT_RUNDE_P.md`; hier steht das **Was**, das **Warum** und das
**Wie** — Sicht für Sicht, Karte für Karte, mit Toren zwischen den Phasen.

Die beiden SQL-Entwürfe in `docs/entwurf_runde_p/` sind **gegen die Demo
gerechnet und stimmen**: `v_prognose` liefert bei Horizont 0 auf den Rappen
dieselben Zahlen wie `erg_charge`/`erg_bilanz`, und `v_wohin` erfüllt seine
beiden Identitäten auf allen 61 Gruppenzeilen mit |Rest| ≤ 0.03 kg. Sie sind
der Kern dieser Runde; alles andere hängt daran.

## 0. Der Anlass, in den Worten des Betriebs

> „Der Betriebsleiter will primär zwei Sachen wissen. **1.** Wie viel Kürbis
> kam rein und raus — und wie viel von dem, das noch im Haus ist, ist
> verkaufsfähig. Die erste Grafik soll deshalb *im Lager* und *verkaufsfähig*
> zeigen statt Verlust, genau wie die ersten Überblickszahlen: Eingang,
> Ausgang, im Haus, verkaufsfähig — mit Prognose, und schon dort alle / Sorte /
> Charge einstellbar. Die Zu-Kleinen werden ja nicht erst mit der Zeit zu
> klein, sie sind es von Anfang an — überleg, wie du das darstellst,
> insbesondere in der Prognose. **2.** Am Saisonende den Überblick haben: Was
> war am schlimmsten, was ist das grösste Problem, wo geht mein Kürbis hin.
> Die Prognose eher in Prozent, weil wir nicht wissen, wie die Verkaufssaison
> weitergeht: *Ich hab noch 400 Tonnen — aber die App sagt, nur 65 % davon
> sind noch verkaufbar.* Ursachen → Palox ist überladen. Fax und Überfüllung
> sind noch faul dargestellt. Und stell bei allem sicher, dass die Zahlen
> stimmen."

## 1. Die zwei Fragen — und der Grundsatz

| Frage | Antwort auf dem Bildschirm | Woraus |
|---|---|---|
| **F1** Wie viel kam rein, wie viel ging raus, wie viel liegt noch — und wie viel davon ist verkaufsfähig, heute und in x Wochen? | Vier Kopfzahlen (Eingang · Ausgeliefert · Im Lager · davon verkaufsfähig, mit Prozent), der Saisonverlauf mit *Im Lager* und *Verkaufsfähig* statt Verlust, ab heute gestrichelt; der verkaufsfähige Anteil als Prozentreihe für 1/2/4/8/12 Wochen — alles je Gesamt / Sorte / Schlag / Charge | `erg_bilanz`, `erg_charge`, **neu `erg_prognose`**, **`erg_verlauf` v2** |
| **F2** Wohin ging der Kürbis, und was war am schlimmsten? | Ein 100-%-Balken des Eingangs (ausgeliefert · anderer Kanal · verdunstet · faul · Fax · im Lager, davon verkaufsfähig), darunter die Rangfolge der Ursachen mit Bereich, und „so geht es weiter: x kg je Tag" — je Gesamt / Sorte / Schlag / Charge | **neu `erg_wohin`**, `erg_verlust`, `erg_prognose` |
| dazu, unverändert wichtig | Was ist noch im Haus (je Charge, älteste zuerst), wie gross sind die Kürbisse (Glocke), Chargen, Messungen, Betrieb | wie heute |

**Der Grundsatz dieser Runde, in fünf Sätzen:**

1. **Für die Zukunft Prozent, nicht Kilo.** Niemand weiss, wie schnell verkauft
   wird. Was die App weiss: wie die *liegende* Ware altert. Also sagt sie:
   „Von dem, was heute liegt, ist in 4 Wochen noch 74 % verkaufsfähig — wenn
   nichts verkauft wird." Der Nenner ist immer die liegende Ware als
   Eingangsware (`lager_kg`), und er bleibt über den Horizont konstant.
2. **Eine Formel.** Jede Prognose ist die Kaskade (`mv_kaskade`) an einem
   späteren Tag ausgewertet — nichts anderes. Bei Horizont 0 ist sie auf den
   Rappen die Zahl von heute (`erg_charge`). Die bisherige
   `v_naechste_charge` wird auf dieselbe Formel gestellt, damit nirgends zwei
   Zwei-Wochen-Zahlen stehen.
3. **Zu klein und zu gross sind ein Anteil, keine Zeitfunktion.** Sie stehen
   in der Prognose als flaches Band (sie wachsen nicht), mindern aber, was als
   Hauptware zählt. Sie heissen nie Verlust.
4. **Jede Zahl trägt ihren Nenner** — „des Eingangs" oder „der liegenden
   Ware" —, und der Begriffs-Prüfstand erzwingt es weiter.
5. **Leer ist nicht null.** Fehlt einer Sorte ein Koeffizient, ist ihr
   verkaufsfähiger Anteil unbekannt, nicht 100 %.

## 2. Begriffe und Nenner — mit den Zahlen der Demo (Stand 11.09.)

| Begriff | Bedeutung | Spalte | Demo | Herkunft |
|---|---|---|---|---|
| Eingang | Netto laut Erntejournal | `erg_bilanz.eingang_kg` | 323.3 t | gemessen |
| Ausgeliefert | Lieferscheine + Vorlauf (alle Bücher) | `erg_bilanz.geliefert_kg` | 116.4 t | gemessen |
| **Im Lager** *(neu als Kopfzahl)* | Eingangsware, die nicht hinter einer Lieferung steckt: Eingang + Überzählung − Ausgelagert | `erg_bilanz.lager_kg` | 187.8 t | gerechnet |
| Gute Ware heute *(bisher „Noch im Haus")* | Im Lager nach Wasserverlust und Faulem bis heute | `erg_bilanz.im_haus_heute_kg` | 153.6 t | gerechnet |
| **Verkaufsfähig** | Gute Ware ohne zu klein / zu gross und ohne das Faule, das beim Abpacken noch anfällt | `erg_bilanz.verkaufsfaehig_heute_kg` | 144.1 t | gerechnet |
| **Verkaufsfähiger Anteil** | Verkaufsfähig ÷ Im Lager | `erg_prognose.verkaufsfaehig_anteil` (h = 0) | 76.7 % | gerechnet |
| Prognose h Tage | dasselbe bei heute + h, wenn nichts verkauft wird | `erg_prognose` (h = 7 … 84) | 76.0 · 75.4 · 74.0 · 71.4 · 68.8 % | Prognose |
| Verkaufsfähig je Tag | (Verkaufsfähig(0) − Verkaufsfähig(7)) ÷ 7 | aus `erg_prognose` | 182 kg/Tag (Verdunstung 85, Faules 109, Kanal und Fax schrumpfen mit −12) | Prognose |

Warum **Im Lager = Eingangsware** und nicht die gute Ware: Der Betriebsleiter
denkt in dem, was er eingelagert und nicht ausgeliefert hat („ich hab noch
400 Tonnen"). Auf diesen Nenner passt seine Frage („aber nur 65 % verkaufbar"),
und nur dieser Nenner bleibt über die Zeit konstant — der verkaufsfähige
Anteil an der *guten* Ware wäre über jeden Horizont fast gleich (≈ 94 %) und
sagte nichts. Frage 51 (Nenner in Prozent) wird damit **beantwortet**: an der
liegenden Ware; „des Eingangs" bleibt für die Saisonbilanz (F2).

**Wohin ging der Kürbis (F2), Demo gesamt, 100 % = Eingang + Überzählung
(327.4 t):**

| Teil | t | % | Spalte in `v_wohin` |
|---|---|---|---|
| Ausgeliefert (Hauptware und Kanal-Lieferungen) | 116.4 | 35.6 | `geliefert_kg` |
| Anderer Kanal an der ausgelieferten Ware (zu klein 2.9, zu gross 2.1) | 5.0 | 1.5 | `kanal_ausgelagert_kg` |
| Verdunstet an der ausgelieferten Ware | 7.8 | 2.4 | `verdunstet_ausgelagert_kg` |
| Faul an der ausgelieferten Ware (inkl. nicht lagerbedingt) | 8.1 | 2.5 | `faul_ausgelagert_kg` |
| Faules beim Abpacken (Fax) | 2.4 | 0.7 | `fax_kg` |
| **Im Lager** | **187.8** | **57.4** | `lager_kg` |
| · davon verkaufsfähig | 144.1 | 44.0 | `lager_verkaufsfaehig_kg` |
| · zu klein / zu gross (Anteil, wächst nicht) | 7.1 | 2.2 | `lager_kanal_kg` |
| · Faules beim Abpacken, erwartet | 2.4 | 0.7 | `lager_fax_kg` |
| · faul bis heute | 18.3 | 5.6 | `lager_faul_kg` |
| · verdunstet bis heute | 15.9 | 4.9 | `lager_verdunstet_kg` |

Rangfolge der Ursachen bis heute (beide Portionen, `erg_verlust` gesamt):
Faules im Lager 26.4 t (8.2 % des Eingangs, Bereich 9.9–42.8) · Verdunstung
23.7 t (7.3 %, 19.0–28.3) · zu klein 7.3 t (2.3 %, kein Verlust) · zu gross
4.8 t (1.5 %, kein Verlust) · Faules beim Abpacken 2.4 t (0.8 %) · nicht
lagerbedingt 0 (bis 2.5). Das ist die Antwort auf „was war am schlimmsten".

## 3. Die Datenbank — Migration 0071 „Was liegt, und was davon verkauft sich"

Alles als `create or replace view … with (security_invoker = true)`; die
gespeicherten Tabellen über die `verdichter`-Paare wie in 0061 (Zeile 1539 ff.)
und in `auswertung_schritt()` Schritt 4. Keine Tabelle, keine Spalte wird
gelöscht; `v_naechste_charge` behält ihre Spalten.

### 3.1 `v_prognose` → `erg_prognose` *(Entwurf liegt, validiert)*

`docs/entwurf_runde_p/v_prognose.sql`. Je `gruppe` (gesamt, sorte, schlag,
charge), `schluessel` und Horizont `h ∈ {0, 7, 14, 28, 56, 84}` Tage: die
Portion „lager" der Kaskade bei `alter_tage + h` ausgewertet, mit **genau**
den Formeln und Klammern von `mv_kaskade` (`f` aus dem Modell, sonst Treppe;
`eta` in [−40, 3]; `f` in [0, 1] — **nicht** 0.99 wie in `v_naechste_charge`).

Spalten: `n_chargen, lager_kg, verdunstet_kg, sockel_kg, faul_kg, kanal_kg,
fax_kg, verkaufsfaehig_kg, gute_ware_kg, verkaufsfaehig_anteil, r_bekannt,
f_bekannt, kanal_bekannt, fax_bekannt, vollstaendig, modell_gilt, alter_tage`.
Invarianten je Zeile: `lager_kg` ist über h konstant;
`verdunstet + sockel + faul + kanal + fax + verkaufsfaehig = lager_kg`;
`verkaufsfaehig_anteil` fällt monoton in h.

**Dazu in der Migration (noch nicht im Entwurf):**

- `verkaufsfaehig_unten_kg`, `verkaufsfaehig_oben_kg`: das Band — konservativ
  als Produkt der ungünstigsten Ränder. Unten: `r_oben` je Sorte
  (`v_koeff_verdunstung.oben`), `F_oben(t)` aus dem Modellband
  (η ± `t_faktor`·√(`var_achse` + u²·`var_k` + 2u·`kov_achse_k`), u = ln t −
  `x_mittel`, wie `erg_kurve`/`schimmelKurve` im Frontend), `a_klein/a_gross/a_fax`
  je `oben`. Oben spiegelbildlich. Ist ein Koeffizient nicht bekannt, sind
  Anteil und Band **NULL** (0064-Muster: `case when bool_and(bekannt) …`).
  Das Band ist kein gemeinsames 95-%-Intervall, sondern eine Hülle — so steht
  es in der Erklärung.
- `verkaufsfaehig_je_tag_kg = (VF(0) − VF(7)) / 7`, `verdunstet_je_tag_kg`,
  `faul_je_tag_kg` (Differenzen von h = 0 auf 7, durch 7) als Spalten der
  Zeile h = 0 (oder eigene kleine Sicht `v_prognose_rate` — Wahl der
  ausführenden KI, aber **eine** Quelle).
- Primärschlüssel `(gruppe, schluessel, h)`; `grant select … to authenticated`.

### 3.2 `v_wohin` → `erg_wohin` *(Entwurf liegt, validiert)*

`docs/entwurf_runde_p/v_wohin.sql`. Je Gruppe **eine** Zeile, die den Eingang
aufteilt (Tabelle in §2). Ströme aus `erg_verlust` (`kg_beobachtet` = an der
ausgelieferten Ware, `kg_projiziert` = an der liegenden Ware), Bestand aus
`erg_charge`. Zwei Identitäten mit `rest_kg` und `lager_rest_kg` als Spalten
— beide müssen in `pruefung.sql` unter 0.1 kg liegen. Primärschlüssel
`(gruppe, schluessel)`.

### 3.3 `erg_verlauf` v2 — je Gruppe, mit *Im Lager* und *Verkaufsfähig*

Heute: je Woche und Sorte (`sorte NULL` = alles), Linien Eingang, Ausgang,
Verlust, im Haus. Neu:

- **Gruppen** wie überall: `gruppe, schluessel` (gesamt, sorte, schlag,
  charge) statt `sorte`; Primärschlüssel `(woche, gruppe, schluessel)`.
  Grouping Sets über `(woche, bis, sorte)`, `(…, schlag)`, `(…, charge_nr)`,
  `(woche, bis)`.
- **Neue Spalten je Woche:** `lager_kg` = Σ `m0` der Portionen mit
  `kohorte ≤ bis` und (`liefertag` NULL oder `> bis`) — Eingangsware, die am
  Wochenende noch nicht hinter einer Lieferung steckt; `verkaufsfaehig_kg`
  = Σ `m0·(1−r)^t·(1−a0)·(1−f(t))·(1−a_klein_n−a_gross_n)·(1−a_fax)` derselben
  Portionen (`t` wie heute in `je_woche`); `kanal_kg`, `fax_kg` analog. Die
  bestehenden Spalten bleiben.
- **Ausgang je Gruppe:** Lieferungen ohne Chargennummer werden wie in
  `v_lieferung_kohorte` (CTE `lief`) nach Eingangsanteil der Sorte verteilt.
  Dafür eine kleine Sicht `v_lieferung_charge_tag (charge_nr, datum, buch,
  masse_kg)` mit genau dieser Regel; `v_lieferung_kohorte` darf darauf
  umgestellt werden (dann gibt es die Regel nur einmal). Der Vorlauf wie
  bisher am Erfassungsbeginn.
- **Horizont:** Wochen bis `greatest(stichtag(), heute() + 84)` — die Prognose
  reicht immer mindestens zwölf Wochen, auch wenn das Saisonende näher liegt.
- **Stützstelle heute** bleibt (0062). An ihr müssen `lager_kg` und
  `verkaufsfaehig_kg` der Gruppe `gesamt` gleich `erg_bilanz.lager_kg` und
  `erg_bilanz.verkaufsfaehig_heute_kg` sein, je Sorte/Schlag/Charge gleich den
  Summen aus `erg_charge` (Prüfung).

### 3.4 `v_naechste_charge` auf `v_prognose` stellen

Gleiche Spalten wie heute, aber `verdunstung_14_kg = verdunstet(14) −
verdunstet(0)`, `schimmel_14_kg = faul(14) − faul(0)`,
`prognose_verlust_14_kg = verkaufsfaehig(0) − verkaufsfaehig(14)` je Charge
aus `v_prognose`; `masse_jetzt_kg = gute_ware_kg(0)`. Damit sagt „zwei Wochen
länger liegen" auf Chargen, Ursachen und Überblick dieselbe Zahl. (Heute
weichen die Formeln ab: `f` bis 0.99 geklammert, Verderb bedingt auf die gute
Masse — für Charge 1632 466 kg statt 388 kg. Die Kaskaden-Formel gilt.)

### 3.5 `v_fax_wartezeit` → `erg_fax_wartezeit`

Aus `v_fax_beobachtung` (abgeschlossen, Masse bekannt): je `gruppe` ('alle' |
'sorte') und `klasse` ('0–1 Tage', '2–3 Tage', '4 und mehr', 'unbekannt') nach
`tage_seit_waschen`: `n, masse_kg, faul_kg, anteil = Σfaul/Σ(masse+faul)`
(massegewichtet), `unten, oben` über `t_quantil_95(n−1)`·sd(anteil je Arbeit)/√n.
Demo: 0–1 Tage **1.3 %** (43 Arbeiten), 2–3 Tage **2.3 %** (99) — das ist
die Aussage, die der Betrieb braucht: *Abpacken am Tag nach dem Waschen
halbiert das Faule beim Fax.* Keine neue Frage an den Arbeiter; die 18
„unbekannt" zeigen, wo der Vorarbeiter die Tage nicht kannte.

### 3.6 Überfüllung bei Stück-Kisten: Lage im Band

In `v_ueberfuellung_verkauf` zwei Spalten für `kistensystem = 'stueck'`:
`lage_im_band = (g_je_kuerbis − band_von_g) / (band_bis_g − band_von_g)`
(0 = Unterkante, 1 = Oberkante; NULL ohne Band) und
`spielraum_kg = (g_je_kuerbis − band_von_g) / 1000 · stueck_verkauft` (nur
wo gewogen **und** verkauft). Bezahlt wird je Stück; jedes Gramm über der
Unterkante ist unbezahlte Masse — aber niemand sortiert auf die Kante. Deshalb
heisst es **Spielraum**, nicht verschenkt. Demo: Kaori Kuri 1100–1600 g
liefert 1148 g (10 % im Band — gut), Fictor 1479 g (76 %), Lekor 1400 g (40 %).
Für „Kiste ab x kg" bleibt `verschenkt_kg` (Tiana 8.48 statt 8.0 kg → 1.2 t
± 0.14 auf 2 546 Kisten).

### 3.7 `pruefung.sql` — Block 0071 (rot vor, grün nach der Migration)

1. Je Charge: `v_prognose(charge, h=0)` gegen `erg_charge` — `lager_kg`,
   `verkaufsfaehig_lager_kg`, `im_haus_heute_kg`, `kanal_im_haus_kg`,
   `fax_erwartet_kg`: |Differenz| < 0.05 kg.
2. `v_prognose`: `lager_kg` konstant über h; Summe der Ströme = `lager_kg`
   (< 0.05 kg); `verkaufsfaehig_anteil` monoton fallend; Band umschliesst den
   Mittelwert; für eine Sorte ohne Verdunstungsmessung (Prüfcharge anlegen)
   ist der Anteil NULL, nicht 1.
3. `v_wohin`: `|rest_kg| < 0.1` und `|lager_rest_kg| < 0.1` auf **allen** Zeilen.
4. `erg_verlauf` an der Stützstelle heute = `erg_bilanz` / `erg_charge`
   (siehe 3.3); Wochen reichen bis ≥ heute + 84; keine Zeile mit `prognose`
   und `bis ≤ heute()`.
5. `v_naechste_charge` = `v_prognose` (charge, 14 − 0) je Charge (< 0.05 kg).
6. `v_fax_wartezeit`: Σ `faul_kg` über die Klassen = Σ aus `v_fax_beobachtung`.
7. `lage_im_band` in [0, 1] oder NULL; `spielraum_kg` NULL, wo nicht verkauft.

Dazu: `supabase/setup_bauen.sh`, `SCHEMA_ERWARTET = 71` und `schema_stand()`,
Fingerabdruck in `run.sh`, `node gegenprobe/orakel/formeln_holen.mjs` — die
Differenz zum Anfang ist **genau** die Objektliste von 0071.

### 3.8 Gegenprobe (Orakel) — die zweite Rechnung

- `gegenprobe/orakel/prognose.ts`: aus dem eigenen Kaskaden-Orakel die Portion
  „lager" bei t + h auswerten (dieselbe Funktion `f`, `r`, Anteile);
  Handfall mit zwei Kohorten, bekanntem r und k, von Hand gerechnet.
- `gegen_db.test.ts`: **K8** `v_prognose` je Gruppe und Horizont gegen das
  Orakel (Toleranz wie K1–K4); **K9** die zwei Identitäten von `v_wohin`;
  **K10** `erg_verlauf` an der Stützstelle heute gegen `erg_bilanz`; **K11**
  `v_naechste_charge` gegen `prognose.ts` (h = 14).
- Böse Saison (`gegenprobe/bildschirm/daten` neu dumpen): eine Charge ohne
  Lieferung (alles liegt), eine ganz ausgeliefert (nichts liegt — keine
  Prognosezeile, kein NaN), der Zettel von 2029 (fällt aus der Prognose, weil
  nicht plausibel — Prüfung, dass `alter_tage ≥ 0` in `v_prognose`).
- **Simulation:** `saison.sql` bekommt zwei wahre Grössen
  `vf_anteil_28`, `vf_anteil_56`: von den am Stichtag liegenden Paletten die
  wahre gute Masse bei +28/+56 Tagen (Verdunstung `r_wahr`, Verderb
  `sim.schimmel_wahr`), ohne zu klein/zu gross (die Wahrheit kennt sie als
  Anteil) ÷ ihr Eingang. `lauf.sh` holt die Schätzung aus
  `v_prognose(gesamt, 28/56)`; `matrix.sh` zeigt Verzerrung und Überdeckung
  in zwei neuen Spalten. **Tor:** |Verzerrung| ≤ 3 Prozentpunkte in den Lagen
  ohne Sockel; Überdeckung ≥ 85 % (die Hülle ist konservativ — liegt sie
  darunter, ist sie falsch gebaut). Die Lage „2 % Sockel" darf daneben liegen
  (N-14) und steht so im Bericht.

## 4. Die Bildschirme

Kein neuer Reiter. Dieselben Bausteine, Zeichen und Bewegungen wie Runde O
(`docs/DESIGN_RUNDE_O.md`). Was unten nicht genannt ist, bleibt.

### 4.1 Überblick — vier Zahlen, zwei Karten, dann der Rest

**Kopfzahlen** (`Kennzahl`, mit Herkunftsmarke direkt an der Zahl):

| Titel | Zahl | Unter | Quelle |
|---|---|---|---|
| Eingang | 323.3 t gemessen | 844 Paletten · 36 Chargen · ab Erntejournal | `erg_bilanz` |
| Ausgeliefert | 116.4 t gemessen | 187 Lieferungen ab Lieferschein · 2.9 t an Tiere und Nebenkanal · 5 t vor dem Erfassungsbeginn | `erg_bilanz` |
| **Im Lager** (Ton kürbis) | 187.8 t gerechnet | Eingangsware, die nicht ausgeliefert ist · 27 Chargen · gute Ware heute 153.6 t | `erg_bilanz.lager_kg`, `.im_haus_heute_kg` |
| **Davon verkaufsfähig** (Ton grün) | **144.1 t · 77 %** gerechnet | Mini-Anteilsbalken der liegenden Ware (verkaufsfähig · zu klein/zu gross · Fax erwartet · faul · verdunstet) · **in 4 Wochen 74 %, in 12 Wochen 69 %** Prognose *— wenn nichts verkauft wird* | `erg_bilanz`, `erg_prognose` gesamt |

„Verlust bis heute" verschwindet aus der Kopfzeile — er steht in „Wohin geht
der Kürbis". „Noch im Haus" heisst als Kopfzahl nicht mehr; die gute Ware
steht als Untertext.

**Karte „Die Saison im Verlauf"** — Segmente **Gesamt · je Sorte · je Schlag
· je Charge** in der Kopfzeile (bei Sorte/Schlag/Charge ein `select`
daneben, wie bei der Glocke). Linien aus `erg_verlauf` v2: Eingang kumuliert
(gemessen, Fläche), Ausgeliefert kumuliert (gemessen, Fläche), **Im Lager**
(Eingangsware; dick), **Verkaufsfähig** (grün, dick; ab heute gestrichelt),
dazu ausgeblendet: gute Ware. Heute-Marke wie bisher; rechts „Prognose — wenn
nichts verkauft wird". Der Zeiger nennt je Woche auch den Anteil
(verkaufsfähig ÷ im Lager). Der Verlust ist hier keine Linie mehr — er ist
der Abstand zwischen Im Lager und Verkaufsfähig, und das sagt die Erklärung.

**Karte „Wohin geht der Kürbis?"** *(ersetzt „Woran fehlt es" und „Wem fehlt
anteilig am meisten?")* — Segmente **Gesamt · je Sorte · je Schlag · je
Charge**:

1. Bei *Gesamt* ein 100-%-Balken (`Anteilsbalken`) des Eingangs aus
   `erg_wohin`: Ausgeliefert · anderer Kanal ausgeliefert · verdunstet
   (ausgeliefert) · faul (ausgeliefert) · Faules beim Abpacken · **Im Lager**
   als heller Block, darin verkaufsfähig · zu klein/zu gross · Fax erwartet ·
   faul · verdunstet. Zeigen nennt Tonnen und Prozent des Eingangs. Bei
   *Sorte/Schlag/Charge* eine Zeile je Gruppe, sortiert nach Verlustanteil —
   dieselben Teile, dieselben Farben (Stromfarben bleiben).
2. Darunter die **Rangfolge bis heute** als dichte Tabelle aus `erg_verlust`
   der gewählten Gruppe: Ursache · bis heute (t) · % des Eingangs · Bereich —
   erst die echten Verluste (Faules im Lager, Verdunstung, Faules beim
   Abpacken, nicht lagerbedingt), dann getrennt „nicht weg, nur nicht
   Hauptware" (zu klein, zu gross). Der grösste Posten trägt eine Marke
   „grösster Posten".
3. Eine Zeile **„So geht es weiter"**: „An der liegenden Ware gehen zurzeit
   rund **182 kg je Tag** verkaufsfähige Ware verloren — Verdunstung 85,
   Faules 109" (Prognose-Marke; aus `erg_prognose` je Tag). Link „je Charge"
   zu Chargen.

**Karte „Was ist noch im Haus?"** (Aufklapper, je Gruppe wie gewählt):
Spalten Im Lager (Eingangsware) · verkaufsfähig heute (kg · %) · **in 4
Wochen %** · liegt seit · gute Ware. Älteste zuerst. Aus `erg_charge` +
`erg_prognose`.

**Karte „Wie gross sind die Kürbisse?"** unverändert.

### 4.2 Ursachen — erst die Antwort, dann die Ursache, zuletzt die Messung

Oben bleibt die Filterleiste (alle · Sorte · Charge). Darunter neu die
**Kopfzahlen der Auswahl**: Im Lager · verkaufsfähig heute (kg · %) · in 4
Wochen (%) · je Tag (kg).

**Karte „Was wird aus der liegenden Ware?"** *(neu, die eine Grafik dieses
Reiters)* — ein **gestapeltes Flächendiagramm in Prozent** (100 % = Im Lager
der Auswahl, konstant), x = Datum von heute bis heute + 84 Tage (Prognose,
gestrichelte Kante): von unten verkaufsfähig (grün) · zu klein/zu gross
(gelb, **flach** — „von Anfang an so, wächst nicht") · Fax erwartet (violett,
flach) · faul (rot, wächst) · verdunstet (blau, wächst). Zeiger nennt je Tag
alle Teile in Prozent und Tonnen. Aus `erg_prognose` (sechs Stützstellen,
dazwischen linear — oder die Kaskade an mehr Stellen; ausführende KI wählt,
aber die sechs Stützstellen müssen exakt getroffen sein). Neuer Baustein
`Stapel` in `Diagramm.tsx` mit demselben Vertrag (`data-x-einheit="datum"`,
`data-y-einheit="prozent"`, `text.strich`, `path.flaeche`).

**Blöcke je Ursache** — jeder mit Zahlen zuerst, die Kurve **zu** (Aufklapper
„Messungen und Kurve"), damit der Reiter nicht überladen ist:

- **Verdunstung:** bis heute (t, % des Eingangs) · an der liegenden Ware bis
  heute (t, % der liegenden Ware) · je Tag (kg) · Rate je Sorte (Tabelle:
  %/Tag, Bereich, n Wägungen, Basis). Aufklapper: die bisherige Grafik.
- **Faules im Lager:** bis heute · an der liegenden Ware · je Tag · **Welche
  Charge zuerst?** (bleibt offen sichtbar, Spalten: Charge, liegt seit, Im
  Lager, verkaufsfähig %, in 4 Wochen %). Aufklapper: die Kurve mit Rauten
  und Messpunkten (unverändert aus Runde O, nur eingeklappt). Der Titel
  heisst nicht mehr „Palox".
- **Sortierung (zu klein, zu gross):** wie heute, mit dem Satz „ein Anteil
  der Ware — er wächst nicht mit der Lagerdauer und steht deshalb nicht in
  der Prognose".
- **Faules beim Abpacken (Fax):** bis heute · an der abgepackten Ware (%) ·
  erwartet an der liegenden Ware · **„Nach Wartezeit seit dem Waschen"** als
  drei Balken (0–1 · 2–3 · 4+ Tage) mit n und Bereich aus
  `erg_fax_wartezeit`, je Sorte als Aufklapper; darunter der Satz, der sich
  aus den Zahlen ergibt (nur wenn die Bereiche sich nicht überlappen:
  „Abpacken am Tag nach dem Waschen: x % statt y %"). Aufklapper: Streubild
  Anteil über Tage seit dem Waschen (`Linien`, Punkte, Farbe je Sorte).
- **Überfüllung / Spielraum:** zwei Tabellen. *Kiste ab x kg:* Sorte · Soll ·
  gewogen je Kiste · zu viel je Kiste · verkaufte Kisten · verschenkt ± Fehler.
  *Stück je Kiste:* Sorte · Kaliber (Band) · Stück je Kiste · gewogen g je
  Stück · Lage im Band als kleiner Balken (0–100 %) · verkaufte Stück ·
  Spielraum (kg). Ein Satz: „Bezahlt wird je Stück — je näher an der
  Unterkante, desto weniger Kilo gehen unbezahlt mit." In Franken erst mit
  Preisen (Frage 49).

### 4.3 Chargen

Spalten: Charge · Sorte · Eingang · Ausgeliefert · **Im Lager** · **verkaufsfähig
heute (kg · %)** · **in 4 Wochen (%)** · liegt seit · Verlust bis heute ·
Messungen. Die Legende der Herkunft oben bleibt. Sortierung wählbar (Kopf
anklicken): Im Lager, verkaufsfähig %, in 4 Wochen %. Aus `erg_charge` +
`erg_prognose` (gruppe charge).

### 4.4 Messungen, Betrieb, Halle

Unverändert — mit einer Ausnahme, die keine neue Frage ist: Beim Fax-Abschluss
wird „Tage seit dem Waschen" **vorbelegt** aus der letzten abgeschlossenen
Wasch-Arbeit derselben Charge (`auftrag` mit `station = 'waschen'`, nicht
Fax), änderbar; ohne Wasch-Arbeit bleibt das Feld leer. Das füllt die Klasse
„unbekannt" auf, ohne dass jemand mehr tippt. (Weggabelung 3 im Auftrag.)

### 4.5 Frontend-Daten und Begriffe

- `src/auswertung/daten.ts`: `Verlaufswoche` bekommt `gruppe, schluessel,
  lager_kg, verkaufsfaehig_kg, kanal_kg, fax_kg`; neu `Prognose`, `Wohin`,
  `FaxWartezeit`; `Auswertung` lädt `erg_prognose`, `erg_wohin`,
  `erg_fax_wartezeit` (je eine Sicht, jede darf für sich fehlen — 0059).
  `Ueberfuellung` bekommt `lage_im_band, spielraum_kg`.
- `pruefstand/begriffe.json`: **Im Lager** (gerechnet; `erg_bilanz.lager_kg`),
  **Gute Ware** (gerechnet; `im_haus_heute_kg`), **Spielraum** (gerechnet),
  **Verkaufsfähig je Tag** (prognose), **in 4 Wochen / in 12 Wochen**
  (prognose). „Noch im Haus" bleibt als Muster (die gute Ware).
- `pruefstand/beschriftung.mjs`: `BEZUG` um `'liegenden ware'` und
  `'der auswahl'` ergänzen; Gegenprobe der Kopfzahlen um `im lager` und
  `verkaufsfähig` gegen `erg_bilanz.lager_kg` / `.verkaufsfaehig_heute_kg`
  erweitern (statt `verlust`, `im haus`).
- `pruefstand/daten` und `gegenprobe/bildschirm/daten` nach der Migration
  **neu dumpen** (`pruefstand/daten_dumpen.sh`) — sonst sehen die Prüfstände
  die neuen Tabellen nicht.
- i18n: nichts in der Halle ändert sich ausser der Vorbelegung (kein neuer
  Text in sechs Sprachen nötig; der Hinweis „vorgeschlagen aus der letzten
  Wasch-Arbeit" darf deutsch bleiben, wenn er nur dem Vorarbeiter erscheint —
  besser: in allen sechs Sprachen, wie die anderen Hilfetexte).

## 5. Prüfstände und Beweise

| Prüfung | Befehl | Muss |
|---|---|---|
| Datenbank | `supabase/test/run.sh 'postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432'` | 7/7, Block 0071 grün, setup.sql deckungsgleich |
| Orakel | `npm run gegenprobe -- --db demo` und `-- --db boese` | 0 fehlgeschlagen, K8–K11 dabei |
| Formeldrift | `node gegenprobe/orakel/formeln_holen.mjs && git diff --stat gegenprobe/orakel/formeln` | genau die Objekte von 0071 |
| Simulation | `supabase/test/simulation/matrix.sh 15` | zwei neue Spalten, Tor aus 3.8 |
| Begriffe | `node pruefstand/beschriftung.mjs` | 0 Beanstandungen, Kopfzahlen stimmen (mit den neuen vier) |
| Invarianten | `node gegenprobe/bildschirm/invarianten.mjs` (Demo und `PRUEFSTAND_DATEN=gegenprobe/bildschirm/daten`) | 0 Verstösse; das Stapeldiagramm liest sich |
| Bilder | `node pruefstand/bildschirme.mjs` | 172+ Aufnahmen, kein Überlauf, keine Konsolenfehler; neue Szenen `ueberblick-charge-verlauf` (Verlauf je Charge), `ursachen-stapel` |
| Drehbuch | `node gegenprobe/drehbuecher/spieler.mjs NN` *(neu: „die Sorte ohne Wägung" — ihr verkaufsfähiger Anteil ist unbekannt, nicht 100 %; NN = die nächste freie Nummer laut `gegenprobe/drehbuecher/WEITERE.md`, dort eintragen)* | ok |
| Frontend | `npm run pruefen` | tsc, Tests (neu: `test/prognose.test.ts` für die Interpolation zwischen den Stützstellen), Build |

## 6. Reihenfolge und Tore

### Phase 0 — Lesen, Grundlinie (½ Tag)
`docs/PROMPT_RUNDE_P.md`, diesen Plan, `docs/entwurf_runde_p/*.sql`,
`docs/DESIGN_RUNDE_O.md`, `docs/ENTSCHEIDUNGEN.md` (Runden N, O),
`docs/ABLAUF.md` (Kaskade, Kohorten), `gegenprobe/README.md`. Grundlinie:
alle Befehle aus §5 auf dem heutigen Stand; Bilder „vorher" aufheben;
Formelabzug, `git diff` leer. Demo-Datenbank prüfen (`pg_isready`; nach
einem Neustart des Containers `pruefstand/demo_bauen.sh`).
**Tor 0:** alles grün, Drift leer.

### Phase 1 — Die Zahlen (1–1½ Tage)
Erst die rote Prüfung: Block 0071 in `pruefung.sql` schreiben, laufen lassen
— er **muss rot sein** (die Sichten fehlen). Dann Migration 0071 aus den
Entwürfen (§3.1–3.6), `verdichter`-Paare, `auswertung_schritt`, Indizes,
`setup.sql`, `SCHEMA_ERWARTET`. Orakel `prognose.ts` + K8–K11. Simulation
(§3.8). Daten neu dumpen.
**Tor 1:** `run.sh` 7/7, Gegenprobe demo **und** boese grün, Matrix mit den
neuen Spalten im Tor, Drift = 0071.

### Phase 2 — Überblick und Chargen (1 Tag)
Kopfzahlen, Verlauf je Gruppe, „Wohin geht der Kürbis", „Was ist noch im
Haus", Chargen-Spalten. Lexikon, Kopfzahlen-Gegenprobe. Bilder.
**Tor 2:** Begriffs-Prüfstand 0, Invarianten 0, Bilder ohne Überlauf; die
vier Kopfzahlen stimmen gegen `erg_bilanz`.

### Phase 3 — Ursachen (1 Tag)
Kopfzahlen der Auswahl, `Stapel`-Diagramm, die fünf Blöcke, Fax nach
Wartezeit, Spielraum. Bilder.
**Tor 3:** wie Tor 2, dazu `invarianten.mjs` liest das Stapeldiagramm
(Achsen, Marker) auf Demo und böser Saison.

### Phase 4 — Halle (½ Tag)
Vorbelegung „Tage seit dem Waschen"; das neue Drehbuch „die Sorte ohne Wägung"; `kette.mjs`.
**Tor 4:** Drehbuch ok, Kette ok, keine neue Frage in der Maske.

### Phase 5 — Bericht (½ Tag)
`docs/BEFUND_RUNDE_P.md` (Befehle und Ausgaben, Zahlen der Demo vorher/
nachher, Matrix-Spalten, Bilder), `docs/DESIGN_RUNDE_P.md` (gebauter Stand
der Bildschirme — nicht Plan), Abschnitt „Runde P" in `ENTSCHEIDUNGEN.md`
(Nenner, eine Formel, Hülle statt Intervall, Spielraum statt verschenkt,
Kanal flach), `FRAGEN.md` 60–62 (mit `docs/fragen.html` und PDF neu),
`README.md` (Reiter-Beschreibung, „Wenn etwas klemmt": Prognose leer).
**Tor 5:** Commit, Push auf `claude/new-session-vrnnyo`, keine PR.

## 7. Was nicht passiert

- Keine neue Mathematik neben der Kaskade. Wer eine Zahl „für die Zukunft"
  zeigt, wertet die Kaskade an einem späteren Tag aus — sonst nichts.
- Kein Chart-Paket, keine neue Abhängigkeit; `Stapel` ist handgeschrieben wie
  `Linien`.
- Keine Tabelle, keine Spalte wird gelöscht; `erg_naechste_charge` bleibt
  (auf der neuen Formel).
- Kein neuer Reiter, keine neue Frage an den Arbeiter — die Vorbelegung fragt
  nichts.
- Keine Kilo-Prognose als Kopfzahl. Prozent für die Zukunft, Kilo nur je Tag
  und bis heute.
- Kein Test wird abgeschaltet, abgeschwächt oder mit `skip` versehen.
- Kein Modellbezeichner in Code, Kommentaren, Commits.

## 8. Fragen an den Betrieb (neu in `docs/FRAGEN.md`)

**60. Der Nenner „an der liegenden Ware".** Die App sagt jetzt: „Im Lager
187.8 t Eingangsware, davon 77 % verkaufsfähig." Ist das die Zahl, die du im
Kopf hast, wenn du „ich hab noch x Tonnen" sagst — die eingelagerte Ware,
die nicht ausgeliefert ist? (Alternativ: die heute noch gute Ware, 153.6 t;
dann wäre der verkaufsfähige Anteil 94 % und über die Zeit fast konstant.)
*Voreinstellung: Eingangsware.* Damit ist Frage 51 beantwortet.

**61. Wie weit soll die Prognose reichen?** Heute: 12 Wochen und bis zum
Saisonende. Reicht das, oder willst du eine Zahl „am Saisonende"? Ohne
Verkaufstempo wäre sie „wenn bis dahin nichts verkauft wird" — ehrlich, aber
wenig brauchbar. *Voreinstellung: 12 Wochen, Prozent.*

**62. Fax: Tage seit dem Waschen vorbelegen?** Aus der letzten Wasch-Arbeit
derselben Charge, änderbar. Nur so wird „nach Wartezeit" vollständig (18 von
160 Arbeiten sagen heute „unbekannt"). *Voreinstellung: ja.*

Dazu die Erinnerung an **49** (Preise je Stück und Kiste — erst dann wird
aus Spielraum und Überfüllung Franken) und **50** (Toleranz der 8-kg-Kiste).
