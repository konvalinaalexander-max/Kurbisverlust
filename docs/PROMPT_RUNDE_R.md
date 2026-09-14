# Auftrag Runde R: Lagermanagement und Ursachen — das Dashboard neu ausgerichtet

## 0. In einem Satz

Baue die zwei ersten Reiter des Betriebsleiter-Dashboards neu — **Lagermanagement**
(Vergangenheit – heute – Prognose: was liegt, wovon, in welchem Kaliber, heute und
in X Wochen) und **Ursachen** (Vergangenheit bis heute: wohin ging der Kürbis, wann
und wo entstand das Faule und die Verdunstung, was verschenkt die Waage) — mit
**einer** Mathematik (der Kaskade), professionellen, interaktiven Diagrammen,
ohne eine Erfassungstabelle, eine Arbeiter-Maske oder eine Zeile echter Daten
anzurühren, und so, dass eine Prüfung jeden Punkt dieses Auftrags nachweist.

## 1. Wer hier spricht, und was schon getan ist

Eine erste KI hat diese Runde **geplant und die Datenbank vorgebaut**. Du führst
aus. Was du vorfindest (alles auf `claude/new-session-vrnnyo`):

- **Die Erfassung ist scharf.** Seit Runde Q laufen echte Daten in die
  Datenbank (`docs/ZWEI_WEBSEITEN.md`, `einstellung.erfassung_scharf`). Deshalb
  gilt in dieser Runde absolut: **keine Änderung an einer Erfassungstabelle,
  keiner Spalte, keiner RLS-Regel, keinem Auslöser, keiner Arbeiter-Maske.**
  Erlaubt sind Sichten, Funktionen und `erg_*`-Ergebnistabellen (Migration 0079
  ff.) und alles im Betriebsleiter-Frontend.
- **Migration 0078** (`supabase/migrations/0078_das_lager_nach_kaliber_und_fax_auf_eis.sql`)
  liegt fertig, geprüft und grün:
  - `lager_kaliber(p_h integer)` — die verkaufsfähige Masse je Charge und je
    Sorte am Horizont `p_h` (Tage, ein Wert aus `erg_prognose.h`: 0, 7, 14 … 196,
    198), aufgeteilt auf die Kaliberbänder der Sorte. Jeder sortierte Kürbis der
    Charge (`sortier_gewicht`, Klasse „kaliber") wird um `(1 − r)^(heute + h −
    sortiertag)` geschrumpft und neu in sein Band gelegt; `kaliber_idx −1` heisst
    „unter dem kleinsten Band". **Die Summe über die Bänder ist
    `erg_prognose.verkaufsfaehig_kg`** — der Prüfblock 0078 (b2) beweist das
    über alle 30 Horizonte. `basis` sagt, woher die Verteilung kommt: `charge`
    (eigene CSV), `sorte` (die CSV-Kürbisse der Sorte), `keine` (eine Zeile ohne
    Band mit der ganzen Masse — leer ist nicht null). Ein Aufruf kostet ~35 ms.
  - `v_lager_kaliber` — `lager_kaliber(0)`, also „heute", als Sicht für den
    SQL-Editor. **Keine gespeicherte Fassung im Rechenwerk:** Der Lasttest
    (dreifache Saison, 255 000 CSV-Kürbisse) liegt beim Neurechnen mit
    11.6–12.0 s an seiner Zwölf-Sekunden-Grenze; „heute" allein kostete dort
    eine Sekunde. Der Bildschirm ruft `rpc('lager_kaliber', { p_h: 0 })` und
    `rpc('lager_kaliber', { p_h: 7·X })` — zwei Aufrufe, je 35 ms auf der
    Demo, im Speicher gehalten. Prüfblock 0078 (b1b) verbietet eine
    gespeicherte Fassung ausdrücklich.
  - `v_marge_wiegung` / `erg_marge_wiegung` — je Sorte und Kistensystem der
    Durchschnitt der gewogenen **vollen** fertigen Paletten: Kiste ab
    (`kg_je_kiste`, `soll_kg_pro_kiste`, `zuviel_je_kiste = Ist − Soll`,
    `sd_je_kiste`, `n_wiegungen`, `kisten`); Stück (`kaliber_idx`,
    `stueck_je_kiste`, `g_je_kuerbis`, `band_mittel_g`, `g_ueber_bandmitte`).
    **Ohne Verkaufsdatei** — Prüfblock 0078 (d4) verbietet der Sicht sogar das
    Wort `lieferung`.
  - **Fax auf Eis:** `einstellung.fax_eingefroren = true` → `v_koeff_fax` gibt
    0 mit Basis „eingefroren" — **0 durch Entscheid, bekannt, nicht unbekannt**.
    Die Kaskade erwartet damit kein Faules beim Abpacken mehr; gemessenes Faules
    alter Fax-Arbeiten bleibt in `fax_heute_kg`. Der Schalter zurück, und alles
    rechnet wie vor Runde R (Prüfblock 0078 (a6)).
- **Der Prüfblock 0078** in `supabase/test/pruefung.sql` — lies ihn: er sagt,
  was die neuen Zahlen versprechen. Alle sieben Stufen von
  `./supabase/test/run.sh` sind grün.
- **Die Arbeiter-App bietet Fax nicht mehr an** (`src/lib/taetigkeit.ts`,
  `angeboten: false`); die Fax-Blöcke des Dashboards sind entfernt; die Kette
  (`pruefstand/kette.mjs` + `kette_pruefen.sh`) ist auf 0072 nachgezogen und
  grün.
- **`pruefstand/abnahme_r.mjs`** — der Vertrag dieses Auftrags als Prüfstand:
  welche Elemente die zwei Reiter tragen müssen und welche Worte nicht mehr
  vorkommen dürfen (§ 8). **Er ist heute rot. Du machst ihn grün** — und
  erweiterst ihn, wo du Neues baust.
- **`docs/DESIGN_RUNDE_R.md` — das Design, verbindlich.** Wie jeder Block
  aufgebaut ist, was er sagt, welche Farbe was bedeutet, wie sich jedes
  Element bedient, was verboten ist, und welche Designpunkte die Abnahme
  prüft (D-01 bis D-08). Es lässt dir Handwerksspielraum, keinen
  Gestaltungsspielraum: Wo es etwas festlegt, gilt es; wo es schweigt, gilt
  `docs/DESIGN_RUNDE_O.md`; wo beide schweigen, wird weggelassen. Jede
  Abweichung steht mit Grund im Bericht § 3.
- Zum Lesen, bevor du eine Zeile schreibst: `docs/DESIGN_RUNDE_R.md` ganz,
  `docs/PLAN_RUNDE_P.md` §1–§2 (die zwei Fragen, Begriffe und Nenner),
  `docs/DESIGN_RUNDE_O.md` (Bausteine, Zeichen, Bewegung, Diagramm-Vertrag),
  `docs/ABMACHUNGEN.md` (AB-61 bis AB-64 sind neu), `docs/ENTSCHEIDUNGEN.md`
  (Abschnitt Runde R), die Migration 0078 ganz, `src/pages/Ueberblick.tsx`,
  `src/pages/Ursachen.tsx`, `src/auswertung/daten.ts`,
  `src/components/Diagramm.tsx`, `src/components/Bausteine.tsx`,
  `src/design/tokens.css`.

## 2. Der Betrieb in seinen Worten

Das ist der Massstab. Jede Karte muss auf einen dieser Sätze zeigen können.

> „das lager management - das ist wichtig - wieviel kürbis ist gerade im lager -
> aber halt genau - von welcher sorte von welcher charge … so viel steht im
> lager - so viel davon ist faul - davon ist so viel verkaufsfähig … von dem
> kaliber von der charge ist noch so viel da - aber dann vlt auch rechnen - ja
> aber mit dem aktuellen verdampfung - ist dann nur noch so viel von dem kaliber
> übrig weil gewisse in eine andere kalibergrösse fallen"

> „statt überblick und ursache lieber lager management und ursache … beide
> reiter zuoberst der filter alle / sorte / charge — der gilt für alle blöcke"

> „lagermanagement: vergangenheit – heute – prognose. ursachen: vergangenheit
> bis heute, keine spekulation"

> „wann hat fäulnis besonders zugelegt - welche sorte welche charge - z.b. wärs
> ja spannend zu sehen - plötzlich ab dezember - dieser kürbis wurde faul - fast
> vollständig auf einen schlag … also dass er rückblickend in der saison
> nachschauen kann"

> „ich weiss nicht ob verdunstungsrate konstant ist - ich denke nicht … im
> dezember wirds kalt sein - das wird sich stark ändern - deswegen messen wir ja"

> „wenn du keine messpunkte hast - darfst du annehmen - dass sie faulen wie
> mittelmass - aber falls du messpunkte hast - zeig einerseits an dass es von
> spezifischen messpunkten gerechnet wurde und nicht von mittelmass"

> „wir können diesen wert ja eh nie einem verkauf zuordnen - die idee ist ja nur
> pro palette zu wissen - und das halt vlt 10x messen pro saison und dann einen
> durchschnittswert zu generieren … bei kaliber 1100 bis 1850 - gebe ich immer
> durchschnitt 1750 - viel mehr als ich sollte"

> „fax … streiche das vorläufig komplett - also nicht aus der datenbank … aus
> dem UI … im hintergrund halt einfach auf eis legen"

> „weniger ist mehr dafür qualität … die grafiken müssen professionell sein,
> interaktiv … und die mathematik muss stimmen"

## 3. Die Haltung — was in dieser Runde unverhandelbar ist

1. **Eine Formel.** Jede Zahl über Bestand, Verkaufsfähigkeit und Zukunft ist
   die Kaskade (`mv_kaskade` → `erg_prognose`). Die Aufteilung nach Kaliber ist
   `lager_kaliber(h)` — nichts wird im Frontend „nachgerechnet". Wer im
   Frontend `(1 - r) ** t` tippt, hat verloren.
2. **Rot zuerst.** Der Prüfblock 0079 wird geschrieben und rot gesehen, bevor
   die Migration 0079 entsteht; `abnahme_r.mjs` ist rot, bevor die Reiter
   umgebaut sind. Ein Test wird nie abgeschaltet, abgeschwächt oder
   übersprungen, um grün zu werden.
3. **Leer ist nicht null.** `basis = 'keine'` heisst „keine Sortier-CSV" und
   steht als Strich mit Grund da, nie als 0 kg. Ein `null` aus `erg_*` wird nie
   mit `?? 0` verrechnet.
4. **Der Nenner steht dabei.** Jede Prozentzahl sagt, wovon. „Verkaufsfähig
   76 %" heisst „von dem, was im Lager liegt (in Eingangskilo)".
5. **Die Herkunft steht dabei.** Jede Karte trägt `<Herkunft art="gemessen" |
   "gerechnet" | "prognose">`; `basis = 'sorte'` wird als „aus der Sorte"
   markiert, eine Charge mit eigenen Messpunkten als „eigene Messung".
6. **Nichts an der Erfassung.** Keine Migration ändert eine Tabelle mit
   Erfassungsdaten. Der Zerstörungswächter läuft als erste Stufe; er ist nicht
   die Grenze — die Grenze ist: **nur Sichten, Funktionen, `erg_*`**.
7. **Die Faulheitsfalle.** „Sieht richtig aus" ist kein Beweis. Jede neue
   Sicht bekommt Identitäten im Prüfblock (Summe = Kaskade; Teile = Ganzes),
   jede neue Beschriftung einen Eintrag in `pruefstand/begriffe.json`, jeder
   neue Bildschirm einen Eintrag in `bildschirme.mjs` und in `abnahme_r.mjs`.
8. **Professionell heisst:** Crosshair-Tooltip über alle Reihen, Legende zum
   Ein-/Ausblenden, Zoom, Heute-Marke, Achsen mit Einheit und Titel, kein
   Ausreisser bestimmt die Achse, Tabellen-Ausweichansicht, dunkel wie hell
   lesbar, auf 390 px Breite bedienbar. Das alles kann `Diagramm.tsx` schon —
   benutze es, erweitere es, ersetze es nicht.

## 4. Die zwei Reiter, Block für Block

Dieser Abschnitt sagt **was** jeder Block zeigt und woher die Zahl kommt.
**Wie** er aussieht und sich bedient — Aufbau, Farben, Tooltips, Zustände,
Handy — steht in `docs/DESIGN_RUNDE_R.md` § 2 (Lagermanagement) und § 3
(Ursachen), Block für Block mit denselben Kennungen (L1–L4, U1–U4). Beides
zusammen ist der Auftrag; keins ersetzt das andere.

Fünf Reiter bleiben: **Lagermanagement · Ursachen · Chargen · Messungen ·
Betrieb**. Der Pfad `/dashboard` bleibt (Lesezeichen, Prüfstände), der Reiter
heisst „Lagermanagement", die Datei wird `src/pages/Lagermanagement.tsx`
(`Ueberblick.tsx` verschwindet). Chargen, Messungen, Betrieb bleiben, wie sie
sind — bis auf Fax-Reste, die noch auftauchen.

### 4.1 Der Filter (beide Reiter, ganz oben)

Ein Element, `<select id="lager-filter">` auf Lagermanagement, `#uf` auf Ursachen
(gibt es schon): Optionen `gesamt|` („Alle Chargen"), `sorte|<Sorte>`,
`charge|<Nr>`. **Kein Schlag** mehr — der Betrieb hat Alle / Sorte / Charge
gesagt; `erg_*` behält die Schlag-Zeilen, die Oberfläche zeigt sie nicht. Die
Wahl steht in der URL (`?sorte=…`, `?charge=…`), wie heute auf Ursachen, und
gilt für **jeden** Block darunter. Ein Wechsel des Reiters nimmt die Wahl mit
(dieselben Suchparameter).

### 4.2 Lagermanagement

Reihenfolge von oben nach unten. Karten-Ids sind Vertrag (§ 8).

**(L1) Vier Kennzahlen** — `#kz-eingang`, `#kz-ausgang`, `#kz-lager`,
`#kz-verkaufsfaehig`, aus `erg_wohin` (Zeile der Filtergruppe) und
`erg_prognose` (h = 0):

| Kennzahl | Zahl | Untertitel (optional, klein) |
|---|---|---|
| Eingang | `erg_wohin.eingang_kg` | `n_chargen` Chargen, erste bis letzte Lieferung |
| Ausgang | `erg_wohin.geliefert_kg` | „+ `kanal_ausgelagert_kg` anderer Kanal (zu klein / zu gross)" |
| Im Lager | `erg_prognose.lager_kg` (h = 0) | „in Eingangskilo; heute noch `gute_ware_kg` Ware" |
| Davon verkaufsfähig | `erg_prognose.verkaufsfaehig_kg` (h = 0) | `verkaufsfaehig_anteil` in Prozent — **leer, wenn `null`** (0064) |

Die vier Zahlen müssen den Identitäten von `v_wohin` gehorchen (Prüfblock 0071);
du prüfst sie nicht neu, du liest sie nur.

**(L2) „Die Saison im Verlauf"** — `#lager-verlauf`. Bleibt (Ueberblick.tsx
`Verlauf`), Datenquelle `erg_verlauf` je Gruppe, vier Linien: Eingang kumuliert,
Ausgang kumuliert, im Lager, verkaufsfähig; ab heute gestrichelt (`prognoseAb`),
Heute-Marke. Streiche die Fax-Linie/-Fläche, falls noch eine da ist.

**(L3) „Was ist noch im Haus"** — `#lager-tabelle`. **Das Herz des Reiters.**
Eine Tabelle:

- Zeilen: Filter „Alle" → eine Zeile je **Sorte** (`lager_kaliber(0)`,
  `gruppe = 'sorte'`); Filter „Sorte" → eine Zeile je **Charge** dieser Sorte
  (`gruppe = 'charge'`, `sorte = …`); Filter „Charge" → **eine** Zeile.
  Nur Zeilen mit `lager_kg > 0`. Sortiert nach `lager_kg` absteigend.
- Spalten: **Sorte | Charge** · **im Lager** (`lager_kg`, in t mit einer
  Nachkommastelle, kg unter 1 t) · Gruppe **„verkaufsfähig heute"** mit
  Unterspalten **je Kaliberband** (`kaliber_idx 0…n`, Kopf „600–1100 g"),
  einer Spalte **„unter Kaliber"** (`kaliber_idx = −1`, nur wenn irgendeine
  Zeile > 0), und **„gesamt"** (`verkaufsfaehig_kg`, mit `anteil` als
  Prozent vom Lager) · Gruppe **„in X Wochen"** mit denselben Unterspalten.
- **X** ist ein Zahlenfeld `#lager-wochen` (1 … 28, Vorgabe 4). Die Spalten
  „verkaufsfähig heute" kommen aus `rpc('lager_kaliber', { p_h: 0 })`, die
  Spalten „in X Wochen" aus `rpc('lager_kaliber', { p_h: 7 · X })` — ein
  Aufruf je Horizont, Ergebnis je Horizont im Speicher gehalten (Map), während
  des Ladens die alten Zahlen leise grau; der Aufruf für 0 läuft beim Laden der
  Seite mit. Datum des Horizonts steht im Gruppenkopf („in 4 Wochen · 12. Okt").
- Die Bänder unterscheiden sich je Sorte (Orangita: 300–800 g; Lekor:
  700–1200 g). Im Filter „Alle" heissen die Spaltenköpfe darum „Kaliber 1 …
  Kaliber 4" und jede Zelle trägt ihr Band klein darunter („600–1100 g");
  eine Sorte mit zwei Bändern lässt die übrigen Zellen leer (kein 0).
  In den Filtern „Sorte" und „Charge" stehen die Gramm direkt im Kopf.
- `basis = 'sorte'` → Zelle mit Kennzeichen „aus der Sorte" (Tooltip: „diese
  Charge hat keine Sortier-CSV; die Verteilung ist die aller sortierten
  Kürbisse der Sorte, `n_kuerbis` Stück"). `basis = 'keine'` → Bandspalten
  zeigen „—", der Tooltip sagt „keine Sortier-CSV für diese Sorte", die
  Gesamtspalte zeigt die Masse trotzdem (die kommt aus der Kaskade).
- **Nicht** in dieser Tabelle: „liegt seit", „gute Ware", ein Verlust, eine
  Prozentzahl ohne Nenner. Der Betrieb hat sie ausdrücklich gestrichen.
- Klick auf eine Sortenzeile setzt den Filter auf die Sorte; Klick auf eine
  Chargenzeile auf die Charge (wie heute die Anteilsbalken).
- Fussnote der Karte (ein Satz): „Die Summe der Bänder ist die verkaufsfähige
  Masse der Kaskade; die Bänder kommen aus der Sortier-CSV, jeder Kürbis um die
  gemessene Verdunstung geschrumpft. Fällt einer unter das kleinste Band, steht
  er in „unter Kaliber"."

**(L4) Die Glocke** — `#lager-glocke`. Die Gewichtsverteilung der Kürbisse der
gewählten Gruppe, mit Bandgrenzen als Zonen — **heute** (Knopf `#glocke-heute`)
oder **in X Wochen** (Feld `#glocke-wochen`, dasselbe X wie die Tabelle, beide
Felder gekoppelt). Die Daten kommen aus `kaliber_glocke(p_h)` (Migration 0079,
§ 5.1): dieselben geschrumpften Kürbisse wie in `lager_kaliber`, in 50-g-Stufen
gezählt, nach Masse. Unter der Glocke: `n_kuerbis` gewogen, `basis`, Schwerpunkt
in Gramm, und — als Beweis, dass es dieselbe Rechnung ist — die Bandanteile in
Prozent, die auf die Tabelle darüber passen müssen (Prüfblock 0079 (c)).
Baustein `Glocke` aus `Diagramm.tsx` (`stufen`, `breite = 50`, `grenzen`).

Was aus dem alten Überblick **weg** ist: „Wohin geht der Kürbis?" (zieht nach
Ursachen), „Verlust nach Ursache", der Aufklapper „Was ist noch im Haus?" in
seiner alten Form, alles mit Fax.

### 4.3 Ursachen

Vergangenheit bis heute. **Keine Prognose auf diesem Reiter** — kein Wort
„Prognose", „in 14 Tagen", kein gestrichelter Verlauf. Reihenfolge:

**(U1) „Wohin ging der Kürbis"** — `#urs-wohin`. Der 100-%-Balken
(`Anteilsbalken`) des Eingangs der Filtergruppe, verlustorientiert, aus
`erg_wohin`, **sechs Teile in dieser Reihenfolge**:

| Teil | Spalten aus `erg_wohin` | Farbe (Token, `DESIGN_RUNDE_R` § 1.2) |
|---|---|---|
| noch im Lager und verkaufsfähig | `lager_verkaufsfaehig_kg` | `hell(--strom-rest)` |
| verkauft | `geliefert_kg` | `--strom-rest` |
| verdunstet bis heute | `verdunstet_ausgelagert_kg + lager_verdunstet_kg` | `--strom-verdunstung` |
| Faules bis heute | `faul_ausgelagert_kg + lager_faul_kg + sockel_ausgelagert_kg + lager_sockel_kg + fax_kg + lager_fax_kg` | `--strom-schimmel` |
| zu klein | `klein_ausgelagert_kg + lager_klein_kg` | `--strom-ausschuss` |
| zu gross | `gross_ausgelagert_kg + lager_gross_kg` | `--strom-nebenkanal` |

Dieselben Farben wie auf Chargen und Messungen — eine Sache, eine Farbe.

Der Tooltip von „Faules bis heute" nennt die Teile: „davon `sockel` kg nicht
lagerbedingt (vom Feld), `fax` kg beim Abpacken gemessen (alte Fax-Arbeiten)".
`rest_kg + lager_rest_kg` > 0.5 kg → ein schmaler siebter Teil „Rest der
Zählung" mit Hinweis; sonst nichts. `ueberzaehlung_kg` steht als Fussnote
(„`x` kg mehr geliefert als eingelagert — Zählfehler beim Eingang"). Im Filter
„Alle" darunter dieselben Balken **je Sorte** (`gruppe = 'sorte'`), im Filter
„Sorte" je Charge, im Filter „Charge" nur der eine. Klick setzt den Filter.
**Die sechs Teile plus Rest müssen `eingang_kg` ergeben** — das ist die zweite
Identität aus Prüfblock 0071; du nimmst sie, du erfindest sie nicht neu. Unter
dem Balken **keine** Prozentzahl ohne Nenner: „12 % des Eingangs".

**(U2) „Faules im Lager"** — `#urs-palox`. Ein Liniendiagramm (`Linien`),
**zwei Achsen zur Wahl** (Knöpfe `#palox-achse-kalender`, `#palox-achse-liegt`):

- **Kalender:** x = Messtag (`erg_punkte.messtag`, neu in 0079), x-Achse endet
  **heute** (`xBis = heute`, Heute-Marke), y = Faules-Anteil der Messung
  (`anteil` in Prozent: kg Faules je 100 kg Ware, die durch die Maschine ging).
  Punkte, keine Linie; eine Reihe je Sorte (Filter „Alle") bzw. je Charge
  (Filter „Sorte"), Legende zum Ausblenden. Der Tooltip nennt Charge, Sorte,
  Tag, `lagertage`, `schimmel_kg` / `basis_jetzt_kg`, Quelle (`quelle`:
  Sortieren, Waschen + Sortieren, Waschen, Kontrollpalette). **Das ist die
  Ansicht für „ab Dezember wurde dieser Kürbis plötzlich faul".**
- **Liegt seit:** x = `lagertage`, y wie oben, dazu die gestrichelte
  Modellkurve `schimmelanteil(t)` aus `erg_kurve` mit Band (gibt es heute in
  `Verderb`), und je Charge mit Ware im Haus eine Raute „heute" auf der Kurve
  (gibt es: `heuteAufDerKurve`). **Das ist die Ansicht für „faulen sie nach N
  Wochen"** — Kalender oder Lagerdauer, der Betrieb will beides sehen können.
- Nicht: eine Ableitung. Der Betrieb: „täglicher Verlust nicht als Ableitung".
  Gezeigt wird je Messung, was gemessen wurde; keine Differenz zweier
  Kurvenwerte wird als Messung ausgegeben. Eine Zeile unter dem Diagramm nennt
  die Faules-Rate der Kaskade in kg je Tag (`erg_prognose.faul_je_tag_kg`, h =
  0) mit Nenner — und sagt, dass sie aus dem Modell kommt.
- Kennzeichnung: Reihen aus Chargen mit eigenen Messpunkten heissen „eigene
  Messung"; das Modell heisst „Modell (alle Sorten)"; steht eine Charge nur auf
  der Kurve, ohne Punkt, ist sie „wie Mittelmass" — das sagt der Tooltip.
- Die Tabellen „Je Charge: gemessen gegen Modell" und „Welche Charge zuerst?"
  gehen weg (die zweite ist Prognose; wenn Chargen sie nicht schon zeigt, kommt
  sie dorthin, sonst nirgends).

**(U3) „Verdunstung"** — `#urs-verdunstung`. Dasselbe Muster: Knöpfe
`#verd-achse-kalender`, `#verd-achse-liegt`. Daten `erg_wiegung`
(`wiege_ts`, `lagertage`, `rate_pro_tag`, `verwendbar`, Charge, Sorte).
- Kalender: x = `wiege_ts` (bis heute), y = Rate in % je Tag
  (`rate_pro_tag · 100`), Punkte je Sorte / je Charge; nur `verwendbar`;
  die nicht verwendbaren als graue Hohlpunkte mit Grund im Tooltip.
- Liegt seit: x = `lagertage`, y = Rate; dazu je Sorte die waagrechte Linie
  ihrer Erwartung (`erg_koeff_verdunstung`) mit Band — im Filter „Alle" nur
  die Linie der Sorten, die ausgewählt/eingeblendet sind.
- Darunter die Tabelle „Je Sorte: die Rate" (gibt es, bleibt): n Wägungen,
  Rate, Band, Basis.
- **Warum beide Achsen:** Der Betrieb glaubt nicht an eine konstante Rate
  (Feldschock, Temperatur). Auf der Kalenderachse sieht er die Jahreszeit, auf
  der Lagerdauer das Alter. Die Kaskade rechnet mit **einer** Rate je Sorte;
  das steht als Satz unter dem Diagramm — wenn die Punkte im Winter sichtbar
  fallen, ist das ein Befund für `docs/FRAGEN.md`, keine Formel im Frontend.

**(U4) „Verschenkte Marge"** — zwei Karten aus `erg_marge_wiegung`, **ohne
Verkaufsdatei**:
- `#urs-marge-kiste` — **Kiste ab x kg**: je Sorte (und Soll) eine Zeile: n
  Wägungen · Kisten · Ist kg/Kiste ± sd · Soll · zu viel je Kiste (kg und %
  vom Soll). Dazu ein Balkendiagramm Ist gegen Soll je Sorte (zwei Balken je
  Sorte oder ein Balken „zu viel" mit Nulllinie). Fussnote: „Mittel aus
  `n_wiegungen` gewogenen vollen Paletten seit `von`; nicht auf verkaufte
  Kisten hochgerechnet — der Betrieb wiegt ~10 Paletten je Saison und will den
  Durchschnitt."
- `#urs-marge-stueck` — **x Kürbisse je Kiste**: je Sorte und Kaliber eine
  Zeile: Band `band_von`–`band_bis` g · Stück je Kiste · n Wägungen · g je
  Kürbis · Bandmitte · über der Bandmitte (g und %). Darstellung: je Zeile ein
  Band als Balken mit der Bandmitte als Strich und dem gemessenen Gramm als
  Punkt darauf („Lage im Band" gibt es schon als Idee in `Ueberfuellungsblock`
  — nimm die Darstellung, nicht die Daten).
- **Weg:** der alte Block „Überfüllung: verschenkte Marge", „Gewogen, aber
  nicht verkauft", alles aus `erg_ueberfuellung` / `v_ueberfuellung_verkauf`
  auf diesem Reiter. Die Sichten bleiben in der Datenbank (Messungen darf
  sie weiter zeigen).

Was aus dem alten Ursachen-Reiter **weg** ist: „Was wird aus der liegenden
Ware?" (Prognose — Stapel), „Sortierung: zu klein, zu gross" (steckt im
Balken U1), die Glocke (zieht nach Lagermanagement), Fax-Wartezeit, Spielraum,
Überfüllung, „Welche Charge zuerst?".

### 4.4 Die übrigen Reiter

Chargen, Messungen, Betrieb: unverändert. Aber: `grep -rn "Fax\|fax" src/pages
src/auswertung src/components` — jede Stelle, die dem Betriebsleiter Fax als
Zahl oder Block zeigt, verschwindet (Messungen: Fax-Zeilen sind schon weg;
Chargen: „Abpacken" ist schon weg). Was in Tabellen wie „Arbeiten" eine alte
Fax-Arbeit als Zeile listet, bleibt lesbar (nichts wird versteckt, was erfasst
wurde).

## 5. Die Datenbank — Migration 0079 (nur Sichten, Funktionen, `erg_*`)

### 5.1 `kuerbis_stichtag(p_h)`, `lager_kaliber(p_h)` neu darauf, `kaliber_glocke(p_h)`

Eine gemeinsame Funktion `kuerbis_stichtag(p_h integer)` liefert die
geschrumpften Kürbisse: `(basis text, schluessel text, sorte text, h int,
gewicht_g numeric, anzahl int, sortiertag date)` — genau die CTEs `stichtag`,
`liegend`, `rate_sorte`, `lauf`, `kuerbis`, `quelle`, `schluessel`, `gewicht`
aus 0078, einmal herausgelöst. `lager_kaliber(p_h)` wird darauf neu gebaut
(`create or replace function`, gleiche Rückgabe, gleiche Zahlen — Prüfblock 0078
bleibt unverändert grün, das ist der Beweis). `kaliber_glocke(p_h)` zählt
dieselben Kürbisse in 50-g-Stufen: `(gruppe text, schluessel text, sorte text,
h int, stufe_g int, n_kuerbis int, masse_kg numeric, basis text)`, Zeilen je
Charge und je Sorte wie `lager_kaliber`. Prüfblock 0079 (c): für jede Gruppe
und h ∈ {0, 28, 196} ergibt `masse_kg` je Band (Stufen ins Band gelegt) dieselben
Anteile wie `lager_kaliber` (|Δ| ≤ 0.002). Timing: ein Aufruf < 200 ms auf der
Demo (Prüfblock misst wie 0078 (c4)).

### 5.2 `erg_punkte.messtag`

`v_schimmel_punkte` bekommt `messtag date` — für Arbeiten `betriebstag(a.start_ts)`,
für die Kontrollpalette der Wiegetag. `erg_punkte` wird neu aufgebaut (das Muster
steht in 0076 für `erg_datenqualitaet`: `do $$ … execute 'create materialized
view erg_punkte as select * from v_schimmel_punkte with no data' … $$` mit
Marker `-- verdichter: baut erg_punkte`). Prüfblock 0079 (a): kein Punkt ohne
`messtag`; `messtag ≤ heute()`; für die Kette-Arbeit stimmt er mit
`betriebstag(start_ts)` überein.

### 5.3 Der Nenner beim Waschen aus den fertigen Paletten

Beim Waschen wird die Kaliber-Palette nicht gewogen; seit Runde Q ist
`auftrag.fertige_paletten_gesamt` Pflicht, sobald der Palox zweimal abgelesen
wurde — **und keine Sicht liest die Spalte** (`grep -rn fertige_paletten_gesamt
supabase/migrations` zeigt nur 0072). Das ist der Punkt, an dem die
Wasch-Arbeiten Messpunkte werden: In `v_auftrag_masse` (0072-Fassung lesen!)
bekommt die Station `waschen` die Quelle `fertige_paletten`: Masse heraus =
`fertige_paletten_gesamt × Palettenmasse`, wobei die Palettenmasse das Mittel
der **eigenen** vollen fertigen Paletten der Arbeit ist (`ausgang_wiegung`,
`voll`), sonst `v_koeff_palette_netto` der Sorte und des Kistensystems; Masse
hinein = heraus + Faules dieser Arbeit (`v_schimmel_menge`). Damit steht der
Nenner, und `v_schimmel_beobachtung` liefert für die Arbeit einen Punkt.
Prüfblock 0079 (b): eine synthetische Wasch-Arbeit mit 3 gewogenen vollen
Paletten à 272 kg netto, `fertige_paletten_gesamt = 5`, Palox 165 → 285: Masse
heraus 1 360, hinein 1 480, Anteil 120 / 1 480; ohne `fertige_paletten_gesamt`
**kein** Punkt (leer ist nicht null). Die Kette (`kette_pruefen.sh`, Block
„Waschen") bekommt dieselbe Zusicherung, sobald ihr Waschen-Durchlauf
`#fertige-gesamt` ausfüllt — ergänze den Schritt in `kette.mjs` (Feld
`#fertige-gesamt`, Wert 3) und die Prüfung.

### 5.4 Nicht anfassen

`mv_kaskade`, `v_prognose`, `v_wohin`, `erg_verlauf`, `v_koeff_*` — die Kaskade
ist geprüft (0071, 0073, 0078). Wer dort etwas ändern zu müssen glaubt, schreibt
es in den Bericht und lässt es.

### 5.5 Das Rechenwerk

`auswertung_schritt(4)` bekommt `erg_punkte` (neu gebaut) wie gehabt; **keine
neue `erg_*`-Tabelle** für die Kaliber und die Glocke. Das Neurechnen bei
dreifacher Saison muss unter 12 s gesamt und 6 s je Schritt bleiben (`run.sh`
Stufe 6 misst es) — und liegt heute bei 11.6–12.0 s. Jede Sekunde, die du dem
Rechenwerk hinzufügst, kippt den Lasttest; jede, die du ihm nimmst (Schritt 2:
3.9 s, Schritt 4: 4.2 s bei dreifacher Saison), ist willkommen, aber nicht
dein Auftrag. Deshalb: Funktionen je Aufruf. `schema_stand()` → 79,
`SCHEMA_ERWARTET = 79`, `node supabase/setup_bauen.mjs`.

## 6. Das Frontend

### 6.1 Daten (`src/auswertung/daten.ts`)

- Neu laden in `Promise.all`: `erg_marge_wiegung` (Typ `MargeWiegung`),
  `erg_punkte` mit `messtag`.
- Neu: `lagerKaliberBei(h)` — `supabase.rpc('lager_kaliber', { p_h: h })`,
  Ergebnis je h gemerkt (`Map<number, LagerKaliber[]>`; h = 0 wird mit dem
  Datenstand geladen), und `kaliberGlockeBei(h)` genauso. Beide mit
  `fehlerText`, nie ein stiller Fehler. **Keine** neue `erg_*`-Tabelle für
  die Kaliber — siehe § 1.
- **Weg:** `erg_fax`, `erg_fax_wartezeit`, `erg_koeff_fax`, `erg_ueberfuellung`,
  `erg_marge` aus dem Ladeblock, sobald keine Seite sie mehr liest (`tsc` mit
  `noUnusedLocals` sagt es dir). Die Sichten bleiben in der Datenbank.

### 6.2 Die Attrappe und die Bilder

`pruefstand/attrappe.mjs` beantwortet `rpc/lager_kaliber` und `rpc/kaliber_glocke`
aus einer Fixture: `pruefstand/daten_dumpen.sh` bekommt je Funktion einen Dump
über alle 30 Horizonte (`select * from lager_kaliber(h)` für jedes `h` aus
`erg_prognose`, als ein JSON-Array mit Spalte `h`); die Attrappe filtert nach
`body.p_h`. `bildschirme.mjs`: Einträge `ueberblick*` werden `lager`,
`lager-sorte`, `lager-charge`, `lager-wochen` (X auf 8 gestellt), `lager-glocke-wochen`;
`ursachen`, `ursachen-sorte`, `ursachen-charge`, `ursachen-kalender` (beide
Achsenknöpfe auf Kalender). Vier Geräte-/Thema-Kombinationen, wie bisher.

### 6.3 Begriffe

Jede Beschriftung, unter der eine Masse steht, kommt in `pruefstand/begriffe.json`
(Bedeutung, Spalte, Art). `node pruefstand/beschriftung.mjs` ist grün.

## 7. Reihenfolge und Tore

Jede Phase endet mit einem Commit auf `claude/new-session-vrnnyo`; die Tore sind
Befehle, die grün sein müssen, bevor die nächste Phase beginnt.

### Phase 0 — Grundlinie (½ Tag)
Lies § 1. Dann: `./supabase/test/run.sh <URL>` grün · `node pruefstand/kette.mjs
&& ./pruefstand/kette_pruefen.sh <URL>` grün · `node pruefstand/bildschirme.mjs`
grün (Bilder „vorher" nach `pruefstand/bilder_vorher/` kopieren) · `node
pruefstand/abnahme_r.mjs` **rot** (zähle, wie viele Punkte rot sind — das ist
deine Liste) · `npm run pruefen` grün. Trage die Zahlen in
`docs/BEFUND_RUNDE_R.md` § 0 ein.

### Phase 1 — Die Zahlen (1 Tag)
Prüfblock 0079 in `pruefung.sql` schreiben (§ 5.1–5.3), `run.sh` laufen lassen,
**rot sehen**. Migration 0079 schreiben. `run.sh` grün, alle sieben Stufen,
Lasttest inbegriffen. Orakel (`gegenprobe/orakel`): wenn `gegen_db.test.ts` die
Kaskade prüft, bleibt es grün — es liest `v_koeff_fax` und `mv_kaskade` beide
aus der Datenbank. Tor: `run.sh` grün, `npm run gegenprobe -- --db demo` grün.

### Phase 2 — Lagermanagement (1 Tag)
`Lagermanagement.tsx` nach § 4.2, `daten.ts` nach § 6.1, Attrappe und Bilder
nach § 6.2. Tor: `abnahme_r.mjs` zeigt alle Punkte „L" grün; `bildschirme.mjs
lager` ohne Konsolenfehler; `beschriftung.mjs` grün; `tsc` grün.

### Phase 3 — Ursachen (1 Tag)
`Ursachen.tsx` nach § 4.3. Tor: `abnahme_r.mjs` ganz grün; `bildschirme.mjs`
ganz; `beschriftung.mjs`; `tsc`; `npm test`; `npm run build`.

### Phase 4 — Beweis und Bericht (½ Tag)
Alles noch einmal: `run.sh`, Kette, Bildschirme, Abnahme, Beschriftung,
`npm run pruefen`. `docs/BEFUND_RUNDE_R.md` nach § 9. `docs/ENTSCHEIDUNGEN.md`
(Abschnitt Runde R ergänzen), `docs/ABMACHUNGEN.md` (Beweise nachtragen),
`README.md` (Reiter, Prüfstände). Commit, Push.

## 8. Der Vertrag — `pruefstand/abnahme_r.mjs`

Der Prüfstand startet die App gegen die Attrappe, meldet sich als Betriebsleiter
an, öffnet `/dashboard` und `/ursachen` (jeweils Alle, eine Sorte, eine Charge)
und prüft:

**Muss da sein (Ids):** Navigation mit Link „Lagermanagement" · `#lager-filter`
mit Optionen `sorte|…` und `charge|…`, keine `schlag|…` · `#kz-eingang`,
`#kz-ausgang`, `#kz-lager`, `#kz-verkaufsfaehig` · `#lager-verlauf` ·
`#lager-tabelle` mit `thead` und mindestens einer Zeile, Kopfzelle „verkaufsfähig
heute" und „in … Wochen" · `#lager-wochen` (Zahlenfeld; nach Eingabe von 8 steht
„in 8 Wochen" im Kopf) · `#lager-glocke`, `#glocke-heute`, `#glocke-wochen` ·
`#uf` · `#urs-wohin` mit sechs Teilen in der Legende · `#urs-palox` mit
`#palox-achse-kalender` und `#palox-achse-liegt`, nach Klick wechselt der
x-Achsentitel · `#urs-verdunstung` mit `#verd-achse-kalender`,
`#verd-achse-liegt` · `#urs-marge-kiste`, `#urs-marge-stueck`.

**Darf nicht da sein (Texte, ganze Seite):** auf `/dashboard`: „Überblick",
„liegt seit", „gute Ware", „Fax", „Wohin geht der Kürbis", „Verlust nach
Ursache"; auf `/ursachen`: „Fax", „Was wird aus der liegenden Ware",
„Überfüllung", „Gewogen, aber nicht verkauft", „Prognose", „in 14 Tagen",
„Welche Charge zuerst", „Spielraum"; auf beiden: „Schlag" als Filteroption,
eine Konsolenfehlermeldung.

**Design (D-01 bis D-08, `DESIGN_RUNDE_R` § 6):** Herkunftsmarke in jeder
Karte, Kennzahlen als `.kennzahl`, Achsen-Umschalter als `Segmente`, zwei
Kopfzeilen und haftende erste Spalte in `#lager-tabelle`, `data-x-einheit`
und Legende an jedem Liniendiagramm, keine Inline-Farben/-Schriftgrössen,
kein waagrechtes Scrollen bei 390 px, dunkles Thema ohne Fehler.

Der Prüfstand druckt eine Tabelle (Punkt · Reiter · ✓/✗ · Befund) und endet mit
Exit 1, solange ein Punkt rot ist. **Erweitere ihn**, wenn du etwas baust, das
hier nicht steht — ein Vertrag, der hinter dem Bau zurückbleibt, ist keiner.

## 9. Der Bericht — `docs/BEFUND_RUNDE_R.md`

§ 0 Grundlinie (die Zahlen aus Phase 0). § 1 Was gebaut wurde, je Block mit
Bild (Pfad unter `pruefstand/bilder/`) und der Zahl, die im Bild steht, samt
Spalte, aus der sie kommt. § 2 Die Prüfungen: Block 0079 (welche Identitäten),
Abnahme (alle Punkte grün, Ausgabe eingefügt), Lasttest (ms je Schritt vorher /
nachher). § 3 Was abgewichen ist vom Auftrag, und warum — jede Abweichung ein
Absatz; keine stille. § 4 Befunde für den Betrieb (z. B. „die Verdunstungsrate
fällt im Kalender sichtbar ab September" → `docs/FRAGEN.md`). § 5 Was bewusst
nicht gemacht wurde.

## 10. Die festen Regeln (unverändert seit Runde L, verschärft seit Q)

- Entwickeln und pushen **nur** auf `claude/new-session-vrnnyo`
  (`git push -u origin claude/new-session-vrnnyo`, bei Netzfehlern 2/4/8/16 s
  wiederholen). **Nie** ein Pull Request.
- Die echten Excel-Dateien unter `/root/.claude/uploads/` enthalten Kundennamen
  und Preise: lokal lesen ja, **committen nie**.
- **Keine Modellkennung** in Code, Kommentaren, Commits, Dokumenten oder
  irgendeinem gepushten Artefakt.
- Commits mit `git -c user.name="Alexander Konvalina"
  -c user.email="konvalina.alexander@gmail.com"`, deutsche Nachricht, die sagt,
  warum — nicht nur was.
- **Nie** einen Test abschalten, abschwächen oder überspringen, um grün zu
  werden. **Nie** eine Tabelle oder Spalte löschen. **Nie** eine
  Erfassungstabelle, eine RLS-Regel, einen Auslöser, eine Arbeiter-Maske
  ändern (Runde R). **Nie** eine Zeile echter Daten ändern oder löschen.
- Leer ist nicht null. Keine neue Abhängigkeit in `package.json`.
- Migrationen nur additiv: neue Sichten, Funktionen, `erg_*`; `schema_stand()`
  und `SCHEMA_ERWARTET` nachziehen; `setup.sql` neu bauen; `run.sh` grün.

## 11. Was nicht passiert

Kein neuer Reiter. Keine Änderung an Chargen, Messungen, Betrieb ausser
Fax-Resten. Keine Prognose auf Ursachen. Keine zweite Verdunstungs- oder
Verderbsformel im Frontend. Keine Schlag-Ebene in den Filtern. Kein PDF. Keine
Fax-Rückkehr (der Schalter bleibt auf true). Keine Verkaufsdatei in der Marge.
Kein Umbau der Arbeiter-App — auch nicht „nur ein Feld".

## 12. Woran du merkst, dass du fertig bist

`node pruefstand/abnahme_r.mjs` endet mit Exit 0 und druckt jeden Punkt grün.
`./supabase/test/run.sh` sagt „alle Prüfungen bestanden" mit Block 0078 **und**
0079. `node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh` grün, mit
`#fertige-gesamt` im Waschen-Durchlauf. `node pruefstand/bildschirme.mjs` ohne
Konsolenfehler, die Bilder `lager*` und `ursachen*` liegen unter
`pruefstand/bilder/`. `node pruefstand/beschriftung.mjs` grün. `npm run pruefen`
grün. `docs/BEFUND_RUNDE_R.md` steht, mit § 3 „Abweichungen" — und wenn dort
„keine" steht, hast du § 4 dieses Auftrags **und** `docs/DESIGN_RUNDE_R.md`
noch einmal gegen deine Bilder gelesen, Block für Block, und jeden Satz des
Betriebs aus § 2 einer Karte zuordnen können.
