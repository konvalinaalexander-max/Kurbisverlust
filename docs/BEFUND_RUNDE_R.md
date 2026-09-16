# Befund Runde R — Lagermanagement und Ursachen

*16. September. Ausgeführt nach
`docs/PROMPT_RUNDE_R.md` und `docs/DESIGN_RUNDE_R.md`.*

Der Betrieb hat in seinen Worten gesagt, wofür er das Dashboard aufmacht:

> „wieviel kürbis ist gerade im lager — aber halt genau — von welcher sorte von
> welcher charge … von dem kaliber von der charge ist noch so viel da — aber
> mit dem aktuellen verdampfung ist dann nur noch so viel von dem kaliber übrig
> weil gewisse in eine andere kalibergrösse fallen"

und

> „wann hat fäulnis besonders zugelegt … plötzlich ab dezember"

Das sind zwei verschiedene Fragen an dieselben Daten. Runde R macht daraus zwei
Reiter: **Lagermanagement** beantwortet die erste (was liegt, wovon, in welchem
Kaliber, heute und in X Wochen), **Ursachen** die zweite (wohin der Kürbis bis
heute ging, wann das Faule entstand, was die Waage verschenkt). Alles auf
Ursachen endet bei heute; jede Aussage über morgen steht im Lagermanagement.

---

## § 0 — Die Grundlinie (Phase 0, vor dem Umbau)

| Prüfung | Stand vor der Runde |
|---|---|
| `./supabase/test/run.sh` | grün, sieben Stufen, 79 Migrationen, letzter Block 0078 |
| `node pruefstand/kette.mjs` + `kette_pruefen.sh` | grün |
| `node pruefstand/bildschirme.mjs` | grün, keine Konsolenfehler |
| `npm run pruefen` (`tsc` · `npm test` · `build`) | grün, 103 Tests |
| `node pruefstand/beschriftung.mjs` | grün |
| **`node pruefstand/abnahme_r.mjs`** | **12 von 59 Punkten — 47 offen** |
| Lasttest (Stufe 6, dreifache Saison) | 11.17 s bei einer Decke von 12 s |

Die 12 grünen Punkte der Abnahme waren die Verbote („kein ‚Überfüllung' auf
Ursachen") — sie galten, weil die Karten noch anders hiessen. Jeder Punkt, der
etwas **verlangt**, war rot: `/dashboard` hiess „Überblick", `#lager-filter`,
`#lager-tabelle`, `#lager-glocke`, `#urs-marge-kiste` gab es nicht.

Die Zahl 12/59 ist nachgemessen, nicht erinnert: der Vertrag von heute, in einem
`git worktree` auf dem Stand vor der Runde (`7237f76`) gegen dieselben Fixtures
gefahren.

---

## § 1 — Was gebaut wurde

### Die Datenbank: Migration 0079

Drei Zahlen fehlten den zwei Reitern. Alles additiv — keine Tabelle, keine
Spalte, keine Erfassungsmaske, keine RLS-Regel angefasst.

**(a) Der Messtag.** `v_schimmel_punkte` trägt jetzt hinten `messtag` — den
Betriebstag der Messung, aus drei Zweigen: der Arbeit am Palox
(`betriebstag(b.start_ts)`), der Arbeit ohne Ablesung (`betriebstag(a.start_ts)`)
und der Lagerkontrolle (`betriebstag(w.wiege_ts)`). Damit hat jeder Punkt der
Verderbskurve zwei Achsen: die Lagerdauer beantwortet „faulen sie nach N
Wochen", der Kalender „ab wann ging es los".

`erg_punkte` wird seither aus `v_schimmel_punkte` gebaut statt aus
`mv_schimmel_punkte` — sonst hätte die App den Messtag nie gesehen.
`mv_schimmel_punkte` selbst ist auf ihre zehn Spalten **eingefroren**: sie neu
anzulegen hätte `cascade` verlangt und 34 abhängige Objekte mitgenommen
(`v_schimmel_kurve`, `v_schimmel_modell_rechnen`, `v_selektionsverdacht`,
`mv_kaskade`, `erg_prognose` …). Eine Runde, die das Dashboard umbaut, reisst
nicht die Kaskade ein.

**(b) Der Nenner beim Waschen.** Die Kaliber-Palette aus dem Zwischenlager wird
nicht gewogen. Bisher rechnete die Masse einer Wasch-Arbeit über gezählte Kisten
mal einem Kistengewicht aus *anderen* Arbeiten — quer über den Gebindewechsel.
`v_auftrag_masse` hat jetzt eine Quelle davor: `fertige_paletten` =
`fertige_paletten_gesamt` × dem Mittel der **eigenen** gewogenen vollen
Paletten dieser Arbeit (hilfsweise dem ihrer Sorte und ihres Kistensystems).
Ohne Palettenzahl und ohne beide Massen bleibt die Zeile leer — unbekannt, nicht
null. Damit löst AB-64 seinen Beleg ein.

**(c) Die Glocke am Stichtag.** `kaliber_glocke(h)` zeigt dieselben Kürbisse wie
`lager_kaliber(h)`, nur in 50-Gramm-Stufen statt in Bändern. Beide lesen
`kuerbis_stichtag(h)` und `lager_schluessel()` — eine Rechnung, zwei Bilder.
Auf der Demo: `lager_kaliber(0)` ≈ 35 ms, `kaliber_glocke(0)` ≈ 40 ms.

`schema_stand()` → 79, `SCHEMA_ERWARTET` → 79, `setup.sql` neu gebaut.

### Reiter 1: Lagermanagement (`/dashboard`)

`src/pages/Lagermanagement.tsx`, neu. `src/pages/Ueberblick.tsx` ist gelöscht.
Bilder: `pruefstand/bilder/lager--desktop-light.png`,
`lager-sorte--…`, `lager-charge--…`, `lager-wochen--…`,
`lager-glocke-wochen--…` (je vier: Rechner/Handy × hell/dunkel).

| Block | Was darin steht | Zahl im Bild (Demo) | Woher |
|---|---|---|---|
| Filter | alle / je Sorte / je Charge, **ohne Schlag** | „36 Chargen · 30 mit Ware im Haus" | `erg_charge` |
| L1 Vier Zahlen | Eingang · Ausgang · Im Lager · Davon verkaufsfähig | 323.3 t · 115.8 t · 191.1 t · 150.4 t (78.7 %) | `erg_wohin.eingang_kg` · `.geliefert_kg` · `erg_prognose.lager_kg` (h=0) · `.verkaufsfaehig_kg` |
| L2 Verlauf | Lager und verkaufsfähig je Woche, Heute-Marke | — | `erg_verlauf` |
| L3 Was ist noch im Haus | Zeilen je Sorte (oder Charge), Spalten: im Lager, verkaufsfähig heute je Band, verkaufsfähig in X Wochen je Band | Tiana 95.8 t im Band 1800–2000 g | `lager_kaliber(0)` / `lager_kaliber(7·X)` |
| L4 Glocke | Gewichte in 50-g-Stufen, Kalibergrenzen, Schwerpunkt, heute / in X Wochen | Butterkin: Schwerpunkt 1096 g heute → 1058 g in 8 Wochen | `kaliber_glocke(0)` / `kaliber_glocke(56)` |

Die Tabelle hat zwei Kopfzeilen (Gruppe über Band) und eine haftende erste
Spalte: auf dem Handy ist sie sonst nach der zweiten Zahl verschwunden. Das Feld
„in X Wochen" gibt es zweimal (Tabelle und Glocke) — **ein** Zustand in der
Adresse (`?wochen=8`), 300 ms entprellt, und während nachgeladen wird, bleiben
die alten Zahlen blass stehen statt auf leer zu springen.

### Reiter 2: Ursachen (`/ursachen`)

`src/pages/Ursachen.tsx`, neu geschrieben. Bilder: `ursachen--…`,
`ursachen-sorte--…`, `ursachen-charge--…`, `ursachen-kalender--…`.

| Block | Was darin steht | Zahl im Bild (Demo) | Woher |
|---|---|---|---|
| U1 Wohin ging der Kürbis? | der ganze Eingang als 100-%-Balken in sechs Teilen, rechts der Anteil echter Verlust; darunter je Sorte (bzw. je Charge), nach Verlustanteil sortiert | 323.3 t Eingang: 150.4 t liegt verkaufsfähig · 115.8 t verkauft · 23.8 t verdunstet · 24.5 t faul · 7.3 t zu klein · 4.8 t zu gross | `erg_wohin` |
| U2 Faules im Lager | jede Palox-Ablesung als Punkt; Umschalter **Kalender** / **liegt seit** | 128 Punkte, Messtage 17.03. bis 10.09. | `erg_punkte.messtag` bzw. `.lagertage` |
| U3 Verdunstung | jede zweite Wägung als Punkt, y = Rate je Tag; derselbe Umschalter | 41 Wägungen, alle verwendbar, 0.033 – 0.096 % je Tag | `erg_wiegung.rate_pro_tag`, `.verwendbar` |
| U4 Verschenkte Marge | zwei Karten: „Kiste ab x kg" und „x Kürbisse je Kiste" | Tiana +0.48 kg je Kiste (8.48 gegen 8.00, 28 Wägungen); Mieluna +0.37 kg (4 Wägungen) | `erg_marge_wiegung` |

Die sechs Teile summieren auf der Demo 3.4 t **über** den Eingang — genau die
`ueberzaehlung_kg` (mehr geliefert als eingelagert). Der Balken verschweigt das
nicht: Unter ihm steht die Fussnote „3.4 t mehr geliefert als eingelagert — ein
Zählfehler beim Eingang, nicht Ware."

Auf dem Kalender endet die Achse bei heute; auf „liegt seit" laufen die
Modellkurve und die Rauten der heute liegenden Chargen mit. Die Marke rechts der
Heute-Linie heisst dort **„länger gelagert"**, nicht „Prognose" — auf der
Lagerdauer-Achse ist rechts nicht die Zukunft, sondern längere Lagerung.

### Was von Ursachen verschwunden ist

„Was wird aus der liegenden Ware", „Welche Charge zuerst", „Spielraum",
„Überfüllung", „Gewogen, aber nicht verkauft", jede Fax-Karte, jede Prognose.
Die Abnahme prüft die Abwesenheit als Text auf der ganzen Seite, in allen drei
Filterständen.

---

## § 2 — Die Prüfungen

### Prüfblock 0079 (`supabase/test/pruefung.sql`)

Rot-zuerst geschrieben, vor der Migration; er prüft Identitäten, nicht Zahlen:

- **(a1–a6) Messtag.** Die Spalte gibt es · es gibt Punkte · keiner ohne Messtag
  · keiner in der Zukunft · jeder Messtag **ist** der Betriebstag seiner Arbeit
  · `erg_punkte` ist die Sicht, nicht die alte Kopie.
- **(b1–b9) Wasch-Nenner.** Ein synthetischer Auftrag: Palox 165 → 285 (= 120 kg
  Faules), drei gewogene volle G2-Paletten à 345 kg brutto (345 − 32×1.5 − 25 =
  272 kg netto), `fertige_paletten_gesamt = 5`. Ohne die Zahl hat die Arbeit
  keine Masse und ist kein Punkt der Kurve; mit ihr ist die Masse heraus
  5 × 272 = **1360 kg**, die Quelle heisst `fertige_paletten`, die Masse hinein
  1360 + 120 = **1480 kg**, und der Messtag ist der Betriebstag. Ohne eigene
  Wägungen ist die Masse unbekannt oder die der Sorte — **nie 0**.
- **(c1–c7) Glocke.** Beide Funktionen gibt es · `kaliber_glocke(0)` ist nicht
  leer · **die Stufen einer Gruppe summieren auf die Masse ihrer Bänder in
  `lager_kaliber`, an drei Stichtagen (0, 28, 196)** · die Stufen sind 50 g
  breit · der Schwerpunkt steigt nie mit der Lagerdauer · ein Aufruf braucht
  weniger als 2 s.

### Die Abnahme

`node pruefstand/abnahme_r.mjs`: **59 von 59 Punkten erfüllt — die Runde ist
abgenommen.** Gefahren wird jeder Punkt in drei Filterständen (alle, eine Sorte,
eine Charge), die Designpunkte zusätzlich in eigenen Fenstern (390 px, dunkles
Thema).

### Die übrigen Stände

| Prüfstand | Ergebnis |
|---|---|
| `./supabase/test/run.sh` | grün, sieben Stufen, 80 Migrationen, Blöcke 0078 **und** 0079 |
| `node pruefstand/kette.mjs` + `kette_pruefen.sh` | grün, mit `#fertige-gesamt` = 5 im Wasch-Durchlauf |
| `node pruefstand/bildschirme.mjs` | 204 Aufnahmen, keine Konsolenfehler, kein waagrechtes Scrollen |
| `node pruefstand/beschriftung.mjs` | grün — jede Zahl beschriftet, im Lexikon, mit Herkunft, Prozente mit Bezug, Kopfzahlen gegengerechnet |
| `npm run pruefen` | grün, 103 Tests |

---

## § 3 — Abweichungen vom Auftrag

**1. Die beiden Marge-Karten zeichnen kein SVG.** Der Auftrag lässt offen, wie
U4 aussieht; `DESIGN_RUNDE_R` § 3 zeichnet einen Balken um eine Nulllinie und
einen Punkt in einem Band. Beides ist **eine Zahl je Zeile** — dafür ein
Diagramm der Bibliothek zu bemühen, hiesse eine Achse zu zeichnen, die nichts
trägt. Gebaut sind zwei kleine CSS-Bilder neben der Tabelle, die die Zahlen
trägt: `.marge-balken` (Nulllinie in der Mitte, Stab nach rechts = zu viel) und
`.band-liste` (Bandmitte als Strich, gemessener Kürbis als Punkt). Wer keine
Farben sieht, liest die Tabelle; das Bild ist die Zugabe. D-05 (SVG-Vertrag)
gilt darum nur für die zwei Liniendiagramme von U2 und U3 — so steht es im
Prüfstand.

**2. Die Spaltengruppe heisst „verkaufsfähig in X Wochen", nicht „in X
Wochen".** Der Auftrag nennt sie „in … Wochen". Der Begriffs-Prüfstand hat
gezeigt, warum das zu wenig ist: Er ordnet jeder Zahl ihre Beschriftung zu, und
„in 4 Wochen · 1800–2000 g" sagt nicht, **wovon** die Kilo sind. Mit dem Wort
davor greift der Lexikoneintrag, und die Spalte trägt ihre Herkunftsmarke
`prognose` im Kopf. Der Text „in 8 Wochen" steht weiterhin darin — die Abnahme
prüft ihn unverändert.

**3. Die Marke rechts der Heute-Linie auf „liegt seit" heisst „länger
gelagert".** Die Diagramm-Bibliothek beschriftet den Bereich rechts von „heute"
sonst mit „Prognose". Auf einer Lagerdauer-Achse ist das falsch, und es hätte
das Verbot „keine Prognose auf Ursachen" gebrochen — sichtbar geworden ist es,
weil die Abnahme den Text der ganzen Seite liest.

**4. Drei Prüfstände waren stumpf und sind geschärft worden**, bevor sie grün
wurden:

- `abnahme_r.mjs` U-03 verglich zweimal `innerText` eines SVG. SVG-Elemente
  haben kein `innerText`; der Punkt verglich zwei leere Zeichenketten und wäre
  **immer grün** gewesen. Jetzt liest er `textContent` und zusätzlich
  `data-x-einheit` (`tage` gegen `frei`).
- `beschriftung.mjs` warf beide Kopfzeilen einer Tabelle in **eine** Liste.
  Bei zwei Kopfzeilen verrutschten die Spaltennamen; „1800–2000 g" galt als
  Beschriftung einer Masse. Jetzt werden `colspan` und `rowspan` aufgelöst und
  je Spalte alle Kopfzeilen verbunden — genau das, was ein Mensch liest.
- `pruefwerk/sonden/01_herkunft.mjs` las `src/pages/Ueberblick.tsx`. Die Datei
  ist gelöscht; die Sonde wäre beim nächsten Lauf abgestürzt. Sie liest jetzt
  `Lagermanagement.tsx` und die Karte „Ausgang" — der Befund selbst gilt
  unverändert (`vorlauf_kg` steckt weiter in `geliefert_kg`).

**5. Prüfblock 0079 (c6) prüft den Schwerpunkt am spätesten Stichtag, an dem
überhaupt noch etwas liegt.** Erst hart auf 196 Tage geschrieben, war er auf dem
kurzen Prüfdatensatz von `run.sh` rot — nicht weil die Ware nicht schrumpft,
sondern weil das Lager dann leer ist und ein Vergleich gegen NULL keine Prüfung
ist. Jetzt sucht er den Stichtag (196 · 84 · 28 · 14) und meldet ausdrücklich,
wenn selbst in 14 Tagen nichts mehr liegt.

**6. Ein echter Fehler im Kartenkopf.** Auf 390 px schob der Kopf der
Glockenkarte („heute | in 8 Wochen" plus das Feld plus das Datum) die ganze
Seite 15 px seitlich aus dem Bild: `.karte-kopf .aktion` hatte `flex: none` und
nahm seine volle Wunschbreite. Gefunden hat es der Bildschirm-Prüfstand, nicht
das Auge. Auf schmalen Schirmen bricht die Aktion jetzt um.

---

## § 4 — Befunde für den Betrieb

**B-1 — Der Wasch-Nenner zählt das Faule doppelt (etwa 1 %).** Beim Waschen ist
`eingang_netto_kg` jetzt die Masse, die **herauskam** (fertige Paletten). Der
Schimmel-Zweig rechnet daraus die Basis als *heraus + Faules* — richtig. Der
alte Kisten-Zweig (`wasch_paletten`) dagegen zählt die Kisten der Paletten, die
**hineingingen**; dort ist das Faule schon drin, und die Basis addiert es ein
zweites Mal. Solange eine Wasch-Arbeit ihre fertigen Paletten meldet, greift der
neue Weg und die Sache ist sauber; wo die Zahl fehlt, bleibt der alte Weg mit
diesem Fehler. Grössenordnung auf der Demo: rund 1 % der Basis einer solchen
Arbeit. **Frage an den Betrieb:** Soll die Zahl der fertigen Paletten beim
Waschen immer Pflicht werden — auch ohne Palox-Ablesung? Dann verschwindet der
alte Weg von selbst. → `docs/FRAGEN.md`

**B-2 — Die Kalenderachse ist jetzt messbar, aber die Demo trägt die Frage
nicht.** Die Frage „wann hat die Fäulnis zugelegt — plötzlich ab Dezember?"
lässt sich seit 0079 stellen: 128 Punkte mit Messtagen vom 17. März bis zum
10. September. Ein Muster über den Winter zeigt die Demo-Saison nicht, weil in
ihr keine Winterware liegt. Die Achse steht; die Antwort kommt aus der echten
Saison. **Nichts wird daraus gefolgert, bevor die Punkte da sind.**

**B-3 — Die Verdunstungsrate streut um den Faktor drei.** 41 verwendbare
Wägungen, 0.033 % bis 0.096 % je Tag. Die Rechnung nimmt je Sorte **eine** Rate.
Ob die Streuung an der Sorte, am Lagerplatz oder an der Waage liegt, sagen die
Punkte nicht — auf der Kalenderachse wäre ein jahreszeitlicher Gang sichtbar,
wenn es ihn gibt. Auch das ist eine Frage an die echte Saison, keine zweite
Formel.

**B-4 — Die Kiste ab 8 kg wird im Mittel mit 8.48 kg gefüllt.** Tiana: +0.48 kg
je Kiste über 28 gewogene Paletten (+6 %), Mieluna: +0.37 kg über 4. Gemessen an
den gewogenen vollen fertigen Paletten, **nicht** auf verkaufte Kisten
hochgerechnet — so hat es der Betrieb verlangt.

---

## § 5 — Was bewusst nicht gemacht wurde

Kein neuer Reiter; Chargen, Messungen und Betrieb sind unverändert. Keine
Prognose auf Ursachen. Keine zweite Verdunstungs- oder Verderbsformel im
Frontend — beide Reiter lesen dieselbe Kaskade. Keine Schlag-Ebene in den
Filtern. Keine Rückkehr der Fax (`einstellung.fax_eingefroren` bleibt gesetzt);
was in der Datenbank steht, bleibt stehen und wird weiter geprüft. Keine
Verkaufsdatei in der Marge. Kein Umbau der Arbeiter-App — auch nicht „nur ein
Feld": `#fertige-gesamt` gab es schon (Runde Q), der Wasch-Durchlauf der Kette
füllt es jetzt bloss aus. Keine neue Abhängigkeit in `package.json`. Kein PDF.
