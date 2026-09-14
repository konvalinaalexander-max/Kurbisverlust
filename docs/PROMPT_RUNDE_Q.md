# Auftrag Runde Q: Die Erfassung scharf schalten

## 0. In einem Satz

Bring die **Arbeiter-App** und das **Datenmodell** in den Zustand, in dem ab
morgen echte Daten erfasst werden dürfen: die drei Palox-Fehler weg, der
Gebindewechsel beim Waschen richtig gerechnet, das Alter ehrlich als Schätzung
ausgewiesen, die Kontrollpalette erhoben, zwei getrennte Webseiten (echt /
Beispiel) — und eine Datenbank, in der eine erfasste Messung **nicht mehr
verloren gehen kann**, auch wenn eine spätere KI daran arbeitet.

Danach wird an der Erfassung nichts mehr geändert. Die Auswertung darf ewig
weiterlernen; was an der Erfassung fehlt, ist für die laufende Saison weg.

---

## 1. Woher das kommt

Der Betrieb (Kürbis-Hof, Schweiz) hat das Dokument `docs/Die-Arbeiter-App.pdf`
(Quelle: `docs/halle.html`) gegengelesen und dabei vier Dinge korrigiert, die
im Code heute falsch oder gar nicht abgebildet sind. Dieser Auftrag setzt genau
das um — nicht mehr, nicht weniger.

**Die vier Korrekturen, wörtlich:**

> „wenn ich bei sortieren palox zu beginn ablese rechnet es minus 445? warum -
> es sind 45 kg"

> „beim waschen — egal ob waschen und sortieren oder nur waschen — die gebinde
> art ändert sich … in den g2 ist voll gestapelt - in den ifcos nicht - also
> kanns sein dass 3 paletten vorne reingehen und hinten 4 rauskommen"

> „auf dem palette mit sortieren kisten - kommen ja mehrere eingangsdaten
> zusammen … dann gibt es nur noch - sortierdatum und kalibergrösse und
> chargennummer - also das sind alle angaben die wir kennen von diesem palette"

> „mir ist dann wichtig dass die daten der arbeiter app von nun an richtig
> erfasst werden - richtig in der datenbank angelegt - und auch genügend
> geschützt dass dort nicht mehr gross rumgepfuscht wird von der KI und falls
> schon, dann nur so dass nichts verloren geht"

Der letzte Satz ist der wichtigste Auftrag dieser Runde. Alles andere ist
Handwerk; das hier ist die Zusage an den Betrieb.

---

## 2. Was du liest, bevor du eine Zeile schreibst

| Datei | Warum |
|---|---|
| `docs/halle.html` | **Die Spezifikation dieser Runde.** Elf Kapitel, Station für Station, mit den Masken als Skizze und allen elf Änderungen auf einer Seite (Kapitel 10). Wo dieser Auftrag und das Dokument sich widersprechen, gilt **dieser Auftrag** — und du schreibst den Widerspruch in den Bericht. |
| `docs/FRAGEN_RUNDE_Q.md` | Die Befunde F1–F10 und die Antworten des Betriebs vom 14.09. |
| `docs/DATENERHEBUNG.md` | Wo die Daten heute liegen, Teil A / Teil B von `setup.sql`, die Sicherungslage. |
| `docs/ABMACHUNGEN.md` | Die Regeln, die nie gebrochen werden. |
| `supabase/verdichten.mjs` | Warum `setup.sql` so gebaut wird, wie sie gebaut wird. Teil A ist Geschichte und wird nur **angefügt**; Teil B ist Rechenwerk und wird ganz ersetzt. |
| `src/arbeit/*` und `src/pages/Kontrolle.tsx` | Der Code, den du anfasst. |

**Was du nicht als Wahrheit nimmst:** die Zahlen in der Datenbank. Das sind von
einer KI erzeugte Beispieldaten. Sie haben die richtige *Form*, aber über den
Betrieb sagen sie nichts. Du darfst mit ihnen rechnen, um zu prüfen, dass eine
Formel läuft. Du darfst aus ihnen **keine** Aussage über den Betrieb ableiten
und keine in einen Kommentar, eine Doku oder den Bericht schreiben.

---

## 3. Die Haltung — zwölf Regeln

1. **Beobachtung statt Folgerung.** Gespeichert wird, was der Arbeiter gesehen
   hat (Waagenstand, Kistenzahl, Gebinde), nie das Ergebnis (Menge, Netto).
   Ergebnisse sind Sichten und dürfen sich ändern, ohne dass eine Messung
   stirbt.
2. **Leer ist nicht null.** Nicht gemessen heisst `NULL` oder `gemessen =
   false`, nie `0`. Wo eine echte Null gemeint ist, gibt es einen eigenen Knopf
   („Nichts Faules", „Stand unverändert"), der sie ausdrücklich schreibt.
3. **Nichts wird gelöscht.** Keine Tabelle, keine Spalte, keine Zeile. Was
   nicht mehr gebraucht wird, wird aus der Oberfläche genommen und im Schema
   mit einem Kommentar stillgelegt. Das gilt auch für Spalten, die du selbst
   für überflüssig hältst.
4. **Rot zuerst.** Jede Änderung bekommt zuerst eine Prüfung, die **rot ist**.
   Du lässt sie laufen und zeigst im Bericht, dass sie rot war. Erst dann
   baust du. Danach grün, und nichts anderes wird rot.
5. **Ein Test wird nie abgeschaltet, abgeschwächt, übersprungen oder in
   Quarantäne gestellt, um grün zu werden.** Wird eine bestehende Prüfung
   rot, ist entweder dein Code falsch oder die Prüfung war falsch — im zweiten
   Fall begründest du das im Bericht, einzeln, mit der Rechnung.
6. **Keine neue Abhängigkeit.** `package.json` bekommt kein Paket dazu.
7. **Der Arbeiter darf nicht langsamer werden.** Zwei neue Fragen sind
   erlaubt und verlangt (Q5, Q6). Jede weitere musst du begründen. Zähle die
   Tipp-Schritte je Tätigkeit vorher und nachher und trage beide Zahlen in
   den Bericht.
8. **Sechs Sprachen.** Jeder neue Text geht durch `src/lib/i18n.ts` und
   existiert in allen dort geführten Sprachen. Kein fest verdrahteter String
   in einer Maske.
9. **Nie warten.** Wo dieser Auftrag eine Frage offen lässt, steht eine
   Voreinstellung dabei (§9). Du nimmst sie, baust weiter und schreibst in
   den Bericht, welche du genommen hast.
10. **Keine erfundene Zahl.** Kein Beispielwert im Code, keine „ungefähr"-Zahl
    in einer Doku, keine Behauptung über den Betrieb.
11. **Klein halten.** Jeder Block wird einzeln fertig, einzeln geprüft,
    einzeln committet. Kein Sammelcommit über drei Blöcke.
12. **Ehrlich berichten.** Was nicht funktioniert hat, steht im Bericht. Was
    du ausgelassen hast, steht im Bericht — mit dem Grund. Ein Block, der zu
    80 % fertig ist, wird als 80 % gemeldet und nicht als fertig.

---

## 4. Die siebzehn Änderungen

### Block A — Der Palox (Q1–Q4)

Das ist der gemeldete Fehler und die wichtigste Änderung der Runde.

**Der Betrieb hat gesagt:** Es gibt zwei stationäre Palox-Boxen (Sortiermaschine,
Waschstrasse). Sie sind **nicht tariert**: leer zeigt die Waage 45 kg.
Arbeitsschritte werden **nie über Nacht pausiert** — eine Arbeit beginnt und
endet am selben Tag. Zwischen zwei Arbeiten liegt unbekannt viel. Deshalb:
*„nie von der letzten Arbeit den Palox-Wert irgendwie übernehmen"*, und
*„dann mach da einfach nach fragen — wurde Palox geleert? und falls ja —
verwende die Daten nicht"*.

**Q1 — Der letzte Stand wird auftragsgebunden.**

Heute holt `PaloxMaske.tsx` über `palox_letzter_stand(p_station)` den letzten
Stand **derselben Station über Arbeitsgrenzen hinweg**. Daraus entstand die
gemeldete `−445`: letzte Ablesung einer fremden Arbeit 490, du liest die leere
Box mit 45 ab, angezeigt wird `45 − 490`.

- Neue Funktion:

  ```sql
  create or replace function palox_stand_dieser_arbeit(p_auftrag_id bigint)
  returns numeric language sql stable as $$
    select s.palox_stand_kg
      from public.schimmel_messung s
     where s.auftrag_id = p_auftrag_id
       and s.palox_stand_kg is not null and s.gemessen
     order by s.ts desc, s.id desc limit 1;
  $$;
  ```
- `PaloxMaske.tsx` ruft nur noch diese.
- `palox_letzter_stand(station)` **bleibt bestehen** (Regel 3). Sie darf als
  Plausibilitätshinweis weiterleben, aber nur ausdrücklich als fremd
  gekennzeichnet („an dieser Station stand zuletzt X — das war eine andere
  Arbeit"). Voreinstellung: gar nicht anzeigen.

**Q2 — Menge ist die Differenz innerhalb der Arbeit.**

| Ablesung | `palox_stand_kg` | `kg` | Anzeige |
|---|---|---|---|
| erste dieser Arbeit | der abgelesene Wert | **0** | „Startstand 45 kg. Am Ende noch einmal ablesen." — **keine** Menge |
| jede weitere | der abgelesene Wert | `round(n − vorher)` | „265 kg faul (310 − 45)" |

- Die heutige Formel für die erste Ablesung, `Math.max(n − tara, 0)`, **entfällt
  ersatzlos**. Die Tara wird nirgends mehr von einer Menge abgezogen: sie
  kürzt sich in der Differenz von selbst heraus. Sie steht nur noch als
  Hinweistext in der Maske.
- `Menge der Arbeit = Σ kg über alle Ablesungen dieser Arbeit` — das ist
  automatisch `S₂ − S₁`, auch bei drei Zwischenablesungen.

**Q3 — Gefallener Stand: fragen, nicht schweigen.**

Heute passiert bei `n < vorher` **gar nichts**: keine Zahl, kein Hinweis, keine
Rückfrage — und beim Tippen auf „Eintragen" wird `kg: 0, palox_geleert: false`
gespeichert. Aus *unbekannt* wird eine *behauptete Null*. Das verstösst gegen
Regel 2 und zieht die Verderbskurve für alle Chargen nach unten.

- Fällt der Stand, zeigt die Maske das sofort und ausdrücklich:
  „Der Stand ist niedriger als zuletzt (490 → 45). Wurde der Palox geleert?"
  mit zwei Knöpfen: **„Ja, geleert"** und **„Nein, vertippt"**.
- „Nein" → nichts speichern, Feld leeren, Fokus zurück ins Feld.
- „Ja" → Ablesung speichern mit `palox_stand_kg = n`, `kg = 0`,
  **`gemessen = false`**, `palox_geleert = true`; zusätzlich auf dem Auftrag
  `palox_unbekannt = true` (neue Spalte, siehe unten).
- Der stille Pfad verschwindet. `palox_geleert` wird zum ersten Mal überhaupt
  gesetzt.
- **Neue Spalte:**
  ```sql
  alter table auftrag add column if not exists palox_unbekannt boolean not null default false;
  comment on column auftrag.palox_unbekannt is
    'Der Palox wurde während dieser Arbeit geleert. Die Faul-Menge der Arbeit '
    'ist damit unbekannt — nicht null. Die Auswertung lässt die Arbeit aus der '
    'Verderbsrechnung heraus, die Ablesungen bleiben erhalten.';
  ```
- **Jede Sicht, die Faules je Arbeit rechnet** (`v_schimmel_beobachtung` und
  alles, was daran hängt), schliesst Arbeiten mit `palox_unbekannt = true`
  **aus** — sie setzt sie nicht auf 0. Such die Stellen selbst; verlass dich
  nicht auf diese Aufzählung.
- Am Abschluss wird die Frage auch dann gestellt, wenn kein Stand gefallen
  ist — klein und unauffällig, weil der Betrieb sagt, es komme selten vor:
  „Palox zwischendurch geleert? nein / ja". „Ja" setzt dieselbe Spalte.

**Q4 — Derselbe Fehler steckt in der Datenbank, nicht nur in der Maske.**

Das ist der Teil, den man leicht übersieht: `v_palox_stand` macht **genau
dasselbe wie die Maske**. Sie fenstert über die Station, nicht über die Arbeit:

```sql
window w as (partition by palox_station(a.station) order by s.ts, s.id)
```

Damit greift `lag(palox_stand_kg)` in die **vorherige Arbeit**. Die Folgen sind
zwei, und die zweite ist die schlimmere:

- Ist der neue Anfangsstand **niedriger** als das Ende der Vorarbeit, wird
  `differenz` NULL, und `v_schimmel_menge` wirft über
  `having bool_and(differenz is not null)` die **ganze Arbeit** aus der
  Rechnung. Das Ergebnis ist zufällig richtig (unbekannt statt falsch), kostet
  aber eine Messung, die vollständig vorhanden ist.
- Ist er **höher** — weil zwischen zwei Arbeiten jemand etwas hineingeworfen
  hat —, wird die Differenz stillschweigend **dieser** Arbeit als Fäulnis
  angelastet. Das ist ein Überschätzen, das niemand sieht.

Dazu zieht die Sicht die Tara ab, wo `lag(...) is null` ist oder
`palox_geleert` gesetzt ist — beides wird unter der neuen Regel bedeutungslos.

**Zu ändern:**

- `v_palox_stand` fenstert über `partition by s.auftrag_id order by s.ts, s.id`.
- Erste Ablesung einer Arbeit → `differenz = 0` (Nullpunkt), **nicht**
  `greatest(stand − tara, 0)`.
- Gefallener Stand innerhalb der Arbeit → `differenz = NULL` (bleibt so) und
  zusätzlich `palox_unbekannt` auf dem Auftrag.
- `palox_geleert` löst kein `stand − tara` mehr aus, sondern `NULL`.
- **Die Tara kommt in dieser Sicht nicht mehr vor.** `palox_tara_kg()` bleibt
  bestehen (Regel 3) und wird nur noch als Hinweistext in der Maske gelesen.
  Der Wert steht bereits richtig auf `45` — daran ist nichts zu ändern.

**Das ist keine folgenlose Umstellung.** Arbeiten, die heute durch das
`having` herausfallen, bekommen künftig eine Menge; Arbeiten, denen heute
fremde Kilo angelastet werden, verlieren sie. **Miss den Unterschied und
schreib ihn in den Bericht**: wie viele Arbeiten betroffen sind, wie viele
Kilo sich verschieben, in welche Richtung. Keine Zahl daraus ist eine Aussage
über den Betrieb (es sind Beispieldaten) — aber die **Anzahl betroffener
Arbeiten** zeigt, ob die Änderung greift.

**Ausserdem:**

- Der Abschluss verlangt an den Pflicht-Stationen (`paloxPflicht`) heute
  **eine** Ablesung. Neu: **zwei** — Beginn und Ende — oder eine plus
  ausdrücklich „Stand unverändert". Der Text sagt, welche fehlt.
- Bleibt es bei einer Ablesung und die Arbeit wird trotzdem abgeschlossen
  (Abbruch, Admin): die Menge ist unbekannt, nicht 0. Prüfe, dass keine Sicht
  daraus eine Null macht — `v_schimmel_menge` liefert dann keine Zeile, und
  alles, was darauf zugreift, muss das aushalten.

**Prüfungen für Block A** (vorher rot):
- Eine Arbeit mit Ablesungen 45 → 310 hat genau 265 kg. Eine zweite Arbeit an
  derselben Station, die mit 45 beginnt, hat **nicht** `45 − 310`.
- Eine Arbeit mit einer einzigen Ablesung hat **keine** Faul-Menge (NULL),
  nicht 0 und nicht `stand − tara`.
- Eine Arbeit mit `palox_unbekannt = true` taucht in keiner Verderbsrechnung
  auf, und ihre Ablesungen sind trotzdem noch da.
- Keine Zeile in `schimmel_messung` hat `kg = 0` **und** `gemessen = true`
  **und** einen gefallenen Stand gegenüber der vorigen Ablesung derselben
  Arbeit.
- `v_palox_stand` enthält keine Zeile, deren `vorher` aus einer **anderen**
  Arbeit stammt. Formuliere das als Abfrage, nicht als Augenschein.
- Zwei aufeinanderfolgende Arbeiten an derselben Station, deren zweite mit
  einem **höheren** Stand beginnt, als die erste endete: die Differenz landet
  bei **keiner** von beiden. Heute landet sie bei der zweiten — diese Prüfung
  ist vorher rot und belegt den stillen Überschätzungsfehler.

---

### Block B — Das Gebinde und die Masse beim Waschen (Q5–Q7)

**Der Betrieb hat gesagt:** *„im lager ist alles - fast alles - in g2 kisten
aber nach dem waschen kommen sie in ifcos - in den g2 ist voll gestapelt - in
den ifcos nicht - also kanns sein dass 3 paletten vorne reingehen und hinten 4
rauskommen - da unterschiedlich viele kisten auf palette kommen - und die
kisten weniger voll befüllt sind - also hier sehr vorsichtig sein."*

Und: *„das gebinde muss selbstverständlich gefragt werden."*

Daraus folgt: **Eine „Palette" bedeutet vor und nach der Waschstrasse etwas
anderes.** Keine Rechnung darf Eingangs- und Ausgangspaletten gleichsetzen.
Die Masse läuft über die **Kiste**.

**Q5 — Gebindeart bei den Kaliber-Paletten.**

`auftrag_palette` hat heute **keine** Spalte für das Gebinde. Ohne sie ist
weder die Tara noch das kg-je-Kiste bestimmt — die Eingangsmasse des Waschens
hängt in der Luft.

```sql
alter table auftrag_palette add column if not exists gebindeart text
  references gebinde(art) on update cascade;
comment on column auftrag_palette.gebindeart is
  'In welchem Gebinde die Palette steht. Beim Waschen aus dem Zwischenlager '
  'gefragt, weil die Tara und das Gewicht je Kiste davon abhängen und sich das '
  'Gebinde an der Waschstrasse ändert (G2 → IFCO).';
```

- `Zaehler.tsx`, Teil „Kaliber-Paletten" (Waschen): ein Gebinde-Wähler neben
  „Kisten auf der Palette". Der Wert **bleibt für die nächste Palette stehen**,
  genau wie Sortierdatum und Kistenzahl, und wird wie diese im
  `localStorage` je Auftrag gemerkt.
- Vorgabe: das Gebinde der letzten Palette dieser Arbeit; sonst die neue
  Einstellung `einstellung('gebinde_lager')` mit Vorgabe `'G2'`.
- Pflicht wie die Kistenzahl.

**Q6 — Wie viele fertige Paletten sind es geworden?**

Das ist die Zahl, ohne die „3 rein, 4 raus" nicht rechenbar ist. Heute wird
beim Waschen nur die **gewogene** fertige Palette erfasst, nicht wie viele es
insgesamt wurden. Fax hat die Zahl schon (`auftrag.paletten_gesamt`), Waschen
und Waschen + Sortieren nicht.

```sql
alter table auftrag add column if not exists fertige_paletten_gesamt int
  check (fertige_paletten_gesamt >= 0);
comment on column auftrag.fertige_paletten_gesamt is
  'Waschen und Waschen + Sortieren: wie viele fertige Paletten am Ende '
  'dastanden, als Gesamtzahl. Zusammen mit den gewogenen Paletten ergibt das '
  'die Ausgangsmasse — Eingangs- und Ausgangspaletten sind nicht dieselbe '
  'Sache (Gebindewechsel G2 → IFCO).';
```

- Ein Schritt im Abschluss, bei `station in ('waschen','waschen_sortieren')`,
  direkt neben den fertigen Paletten. Eine Zahl, keine Klickerei — wie bei Fax.
- Pflicht, wenn das Kistensystem rechenbar ist (`kiste_ab` oder `stueck`);
  sonst gefragt und überspringbar.

**Q7 — Die Masse des Waschens kommt von der Ausgangsseite, nicht von der Eingangsseite.**

Hier ist ein Denkfehler zu vermeiden, der naheliegt: „Masse hinein = Kisten ×
kg je G2-Kiste". Das klingt richtig und ist unbrauchbar, denn **kg je G2-Kiste
für ein bestimmtes Kaliberband ist im Betrieb nicht messbar.** Der Betrieb hat
gesagt: *„kaliber palette könnte auf waage - aber das machen wir nicht."* Eine
gewogene *Eingangs*palette ist gemischt-kalibrig und sagt nichts über eine
einzelne Kaliber-Palette. Und nach Q8 zählt am Sortierband niemand mehr die
Kisten je Band. Der Koeffizient hat also keine Quelle.

**Rechne deshalb über die Ausgangsseite und die Massenbilanz:**

```
Masse heraus  = fertige_paletten_gesamt
                × mittlere Kisten je gewogener voller Palette
                × mittleres kg je Kiste der gewogenen vollen Paletten

kg je Kiste   = ( brutto − kisten × tara_kiste − tara_palette ) / kisten

Masse hinein  = Masse heraus + Faules (Palox) + Ausschuss
                ── eine Identität, keine Modellannahme:
                   was hineinging, ging entweder hinaus, in den Palox
                   oder in den Ausschuss ──

Anteil faul   = Faules / Masse hinein
```

Jede dieser Grössen ist in dieser Runde **gemessen**. Nichts daran ist
geschätzt, und es hängt kein Koeffizient darin, den niemand erheben kann.

- Nur fertige Paletten mit `voll = true` (Q9) gehen in die Mittelwerte für
  Kisten-je-Palette und kg-je-Kiste ein. Für `fertige_paletten_gesamt` zählen
  alle.
- Fehlt `fertige_paletten_gesamt` oder gibt es keine gewogene volle Palette,
  ist die Masse dieser Arbeit **NULL**, nicht 0 — die Arbeit erscheint als
  „Menge unbekannt". Genau dafür ist Q6 Pflicht.
- Die gezählten G2-Kisten der Eingangsseite (Q5) werden dadurch **nicht
  überflüssig**. Sie bekommen eine andere Aufgabe: **Gegenprobe**. Wo für
  (Sorte × Kaliber × G2) doch ein Koeffizient existiert — aus einer
  Lagerkontrolle, einer Kontrollpalette oder einer gewogenen Eingangspalette
  derselben Sorte —, rechnet die App die Eingangsseite zusätzlich aus und
  zeigt beide Zahlen nebeneinander. Weichen sie um mehr als 10 % ab, ist das
  eine Auffälligkeit auf `Messungen.tsx`, keine Korrektur. **Die Bilanz
  gewinnt, die Gegenprobe meldet.**

**Prüfungen (vorher rot):**
- Es gibt keine Sicht und keine Funktion im ganzen Projekt, in der eine
  Eingangspalettenzahl mit einer Ausgangspalettenzahl verglichen, subtrahiert
  oder gleichgesetzt wird. Such danach und belege im Bericht, **wo** du
  gesucht hast (Sichten, Funktionen, Frontend, Orakel).
- Für eine Wascharbeit mit vollständigen Angaben gilt
  `Masse hinein = Masse heraus + Faules + Ausschuss` auf ±0,01 kg. Das ist
  eine Identität und muss exakt aufgehen, nicht ungefähr.
- Eine Wascharbeit ohne `fertige_paletten_gesamt` hat Masse NULL — und alles,
  was darauf zugreift, hält das aus, ohne 0 daraus zu machen.

---

### Block C — Sortieren: die Kisten und die CSV (Q8–Q9)

**Der Betrieb hat gesagt:** *„kisten je kaliber werden nicht gezählt.... also
das kann das CSV nicht weil das CSV nicht weiss wieviel kürbisse pro kiste -
und niemand wird händisch die kisten zählen und in der app eintragen."*

**Q8 — „Kisten je Kaliber" verschwindet aus der Oberfläche.**

- `stationsProfil()`: `hatKisten` wird `false`. Der Reiter verschwindet aus
  `Zaehler.tsx`.
- **`auftrag_gebinde` bleibt stehen, samt aller vorhandenen Zeilen.** Setze
  einen Tabellenkommentar, der sagt, dass sie seit Runde Q nicht mehr befüllt
  wird und warum.
- Ersatz für die Masse je Kaliberband: die Sortier-CSV.
  `Σ (gewicht_g × anzahl) über sortier_gewicht je kaliber_idx`. Das ist eine
  genauere Messung als jede Zählung und existiert schon.
- Sichten, die heute aus `auftrag_gebinde` rechnen, müssen für neue Arbeiten
  **NULL** liefern, nicht 0 — und dort, wo eine CSV da ist, aus der CSV.
- **Achtung, eine Kette, die dabei reisst:** `v_koeff_gebinde` bildet heute
  „kg je Kiste" als *CSV-Masse je Band ÷ gezählte Kisten je Band*. Fällt der
  Zähler weg, hat diese Sicht am Sortierband **keine Quelle mehr**. Das ist
  hinnehmbar — Q7 rechnet die Masse des Waschens nicht mehr darüber —, aber
  es muss bewusst geschehen: lass die Sicht stehen, lass sie für neue Arbeiten
  NULL liefern, und **stelle jede Stelle, die sie heute liest, darauf um, dass
  NULL vorkommen darf**. Such diese Stellen und zähle sie im Bericht auf.
  Was „kg je Kiste" künftig speist, sind die gewogenen Paletten: die drei
  Eingangswägungen bei Waschen + Sortieren, die Lagerkontrolle, die
  Kontrollpalette (G2) und die fertigen Paletten (IFCO).
- **Neu am Abschluss des Sortierens:** ein Hinweis (kein Sperren), wenn zu
  dieser Arbeit keine Sortier-Datei zugeordnet ist:
  „Für diese Arbeit ist noch keine Sortier-Datei hochgeladen. Ohne sie kennt
  die Auswertung die Menge je Kaliber nicht."
  Das ist der Ersatz für die Sicherheit, die der Zähler vorgetäuscht hat.

**Q9 — Kürbisse je Kiste, und die halbvolle letzte Palette.**

Der Betrieb will beides messen: *„mich interessiert nicht nur bei x kilo pro
kiste sondern auch bei x kürbisse an kaliber x pro kiste - also ich will bei
beiden die fertigen palette wägen."*

- `ausgang_wiegung.kuerbisse_pro_kiste` existiert und ist optional. Neu:
  - Kistensystem `stueck` → **Pflicht**.
  - Kistensystem `kiste_ab` → verlangt, aber mit einem ausdrücklichen Knopf
    „nicht gezählt" überspringbar (leer ≠ 0).
- **Neue Spalte:**
  ```sql
  alter table ausgang_wiegung add column if not exists voll boolean not null default true;
  comment on column ausgang_wiegung.voll is
    'Ob diese fertige Palette voll ist. Die letzte Palette einer Arbeit ist es '
    'oft nicht. Eine nicht volle Palette zählt für die Masse, aber nicht für '
    'kg je Kiste und Kürbisse je Kiste — sonst zieht sie den Koeffizienten '
    'nach unten.';
  ```
  In `FertigePaletteMaske.tsx` ein Häkchen „Diese Palette ist nicht voll".
- Aus den vollen Paletten folgt je (Sorte × Kaliber × Gebinde):
  `kg je Kiste`, `Kürbisse je Kiste`, `kg je Kürbis` und die **Lage im
  Kaliberband** in Prozent. Bau das als Sicht, auch wenn das Dashboard es in
  dieser Runde noch nicht zeigt — es ist die Voraussetzung für zwei Dinge, die
  der Betrieb später will: die **Stück-Überfüllung in Franken** (wie viel
  Gramm über der Kaliber-Unterkante geht unbezahlt mit) und die
  **Kalibermigration** (wie viele Kürbisse durch Verdunstung unter die
  Unterkante ihres eigenen Bandes rutschen). Ohne diese Messung ist beides
  nicht rechenbar, und nach der Saison ist sie nicht nachholbar.

**Dazu ein bestehender Fehler in `v_ueberfuellung_verkauf` (Befund F5):**
die Sicht gruppiert **ohne** `gebindeart` und verlangt `kisten_verkauft IS NOT
NULL`. Beides ist falsch: eine G2-Kiste und eine IFCO-Kiste sind nicht dasselbe
Gebinde, und eine fehlende Verkaufs-Kistenzahl darf eine gewogene Palette nicht
aus der Rechnung werfen. Nimm `gebindeart` in die Gruppierung und trenne die
beiden Seiten: was gewogen wurde, bleibt erhalten, auch wenn die Verkaufsseite
fehlt — dann steht dort „Verkaufszahl fehlt" und nicht nichts. Eine Prüfung,
die eine gewogene Palette ohne Verkaufszeile findet und belegt, dass sie
trotzdem in der Sicht steht.

---

### Block D — Fax (Q10)

**Q10 — Der Wartezeit-Vorschlag findet die halbe Ware nicht.**

`Abschluss.tsx` sucht die letzte abgeschlossene Arbeit derselben Charge mit
`.eq('station', 'waschen')`. Ware, die über **Waschen + Sortieren** lief, ist
auch gewaschen und wird nie gefunden.

- `.eq('station','waschen')` → `.in('station', ['waschen','waschen_sortieren'])`.
- Eine Prüfung, die genau das abdeckt: Charge mit nur einer
  `waschen_sortieren`-Arbeit → der Vorschlag steht da.
- Der Vorschlag bleibt ein Vorschlag: sobald der Vorarbeiter tippt,
  verschwindet der Hinweis (so ist es heute schon, lass es so).

---

### Block E — Die Kontrollpalette (Q11)

**Der Betrieb hat gesagt:** *„ich weiss nicht ob verdunstungsrate konstant ist
- ich denke nicht - weil am anfang haben sie sicher schock von draussen feld in
halle zu kommen"* und *„an sich werden schon die schlechter aussehenden palette
ausgewählt."*

Heute rechnet die App mit **einer** Rate je Sorte über die ganze Saison, und die
Wägungen, aus denen sie kommt, sind nach Augenschein ausgewählt — beides ist
eine systematische Verzerrung. Die Kontrollpalette beseitigt beide: eine
markierte Palette je Sorte, monatlich gewogen, **nie verarbeitet**. Zwei
Wägungen derselben Palette geben eine Rate **für den Zeitraum dazwischen**.

**Q11 — Kontrollpalette erheben.**

```sql
create table if not exists kontrollpalette (
  id            bigserial primary key,
  charge_nr     int  not null references charge(nr),
  palette_id    bigint references palette(id),      -- falls die konkrete Palette bekannt ist
  kennzeichen   text not null,                      -- was draufsteht, damit man sie wiederfindet
  standort      text,
  angelegt_ts   timestamptz not null default now(),
  angelegt_von  uuid not null default auth.uid() references profil(id),
  beendet_ts    timestamptz,
  beendet_grund text,
  bemerkung     text
);

create table if not exists kontrollpalette_wiegung (
  id                 bigserial primary key,
  kontrollpalette_id bigint not null references kontrollpalette(id),
  brutto_kg          numeric(8,2) not null check (brutto_kg > 0),
  kisten             int not null check (kisten > 0),
  gebindeart         text references gebinde(art) on update cascade,
  sichtbar_schimmel  boolean not null default false,
  erfasser           uuid not null default auth.uid() references profil(id),
  wiege_ts           timestamptz not null default now(),
  ts                 timestamptz not null default now(),
  bemerkung          text
);
```

- Beide mit RLS nach dem Muster von `verdunstung_wiegung`: lesen alle,
  erfassen wer aktiv ist, korrigieren im Korrekturfenster oder Admin.
  **`delete` nur für Admin** (siehe Q15).
- `kontrollpalette` wird **nie** gelöscht, nur `beendet_ts` gesetzt.

**Sicht `v_kontrollpalette_rate`** — je aufeinanderfolgendes Wägungspaar
derselben Kontrollpalette eine Zeile:

| Spalte | Inhalt |
|---|---|
| `kontrollpalette_id`, `charge_nr`, `sorte` | wer |
| `von_ts`, `bis_ts`, `tage` | der Abschnitt |
| `netto_von_kg`, `netto_bis_kg` | Brutto minus Tara nach Gebinde |
| `rate_je_tag` | `1 − (netto_bis / netto_von)^(1/tage)` |
| `verwendbar` | `false`, wenn eine der beiden Wägungen `sichtbar_schimmel` hat, `tage < 7` ist, oder das Netto steigt |

- **Die Kaskade wird in dieser Runde nicht umgestellt.** `v_kontrollpalette_rate`
  wird erhoben und angezeigt, mehr nicht. Ob die Rate über die Saison konstant
  ist, entscheidet der Betrieb, wenn Messpunkte da sind — nicht du und nicht
  die Beispieldaten.

**Arbeiter-App:** `src/pages/Kontrolle.tsx` bekommt einen zweiten Weg
„Kontrollpalette wiegen": Kontrollpalette wählen oder neu anlegen (Charge,
Kennzeichen, Standort), dann Brutto, Kisten, Gebinde, „Schimmel sichtbar?".
Die App zeigt vor dem Speichern, **wann sie zuletzt gewogen wurde und was
dabei herauskam** — damit der Arbeiter einen Tippfehler sofort sieht.

**Betriebsleiter:** eine Karte auf `Messungen.tsx`: je Kontrollpalette die
Wägungen als Linie, die Rate je Abschnitt als Balken darunter, und ein Hinweis,
wenn eine Kontrollpalette länger als 45 Tage nicht gewogen wurde.

---

### Block F — Ehrliche Zahlen (Q12–Q13)

**Q12 — Das Alter beim Waschen ist eine Schätzung und muss so aussehen.**

Der Betrieb hat den Denkfehler gefunden: *„auf dem palette mit sortieren kisten
- kommen ja mehrere eingangsdaten zusammen."* Es gibt kein Eingangsdatum einer
Kaliber-Palette. Auf dem Zettel stehen nur **Chargennummer, Sortierdatum,
Kalibergrösse**.

Drei Grössen, und nur die erste ist gemessen:

| Grösse | Herkunft | Genauigkeit |
|---|---|---|
| `zwischenlager_tage` = Waschtag − Sortierdatum | Zettel, je Palette | **exakt**, tagesgenau |
| Zeit vor dem Sortieren | je Palette nicht vorhanden | nur als Chargenmittel |
| `lagertage` (Gesamtalter) | Summe | **geschätzt** |

```
mittleres_eingangsdatum(charge) = Σ ( eingangsdatum_p × netto_p ) / Σ netto_p
                                  über alle Eingangspaletten der Charge

lagertage (Waschen) = betriebstag(start_ts) − mittleres_eingangsdatum(charge)
```

Zulässig ist das nur, weil alle Kisten auf der Palette aus **derselben Charge**
stammen. Die Unsicherheit ist genau die Streuung der Eingangsdaten innerhalb
der Charge.

- Für `station in ('sortieren','waschen_sortieren')` bleibt es beim
  **gemessenen** Alter: dort liest der Arbeiter das Eingangsdatum je Palette
  vom Zettel ab, massegewichtet über die Paletten dieser Arbeit.
- **Neue Spalten in der Auftrags-Masse-Sicht:**
  - `alter_quelle text` ∈ `{'gemessen','chargenmittel'}`
  - `alter_spanne_tage numeric` — die massegewichtete Streuung der
    Eingangsdaten der Charge. Voreinstellung: die massegewichtete
    Standardabweichung; wenn du `max − min` besser findest, begründe es.
  - `zwischenlager_tage numeric` — das exakte Stück, damit es nicht verloren
    geht.
- **Frontend:** wo ein Alter beim Waschen steht, steht die Spanne dabei
  („68 Tage ± 4") und das Zeichen für geschätzt. Nirgends darf eine geschätzte
  Zahl so aussehen wie eine gemessene.
- Wo keine Eingangspalette der Charge bekannt ist: `lagertage` ist **NULL**,
  nicht 0, und die Arbeit fällt aus der Alterskurve — sie wird nicht auf
  irgendein Mittel gesetzt.

**Q13 — Verderb bekommt dieselben Zeichen wie die Verdunstung.**

Heute rechnet die App mit **einer globalen Kurve** F(t) für alles: eine Sorte,
alle Chargen, die ganze Saison — ohne dass man das einer Zahl ansieht. Bei der
Verdunstung gibt es dafür längst die Schrumpfung in `v_koeff_*_geschaetzt`.

- Übertrage dieselbe Empirical-Bayes-Schrumpfung auf den Verderb, gruppiert
  **je Sorte** (Voreinstellung, siehe §9).
- Jede Zahl bekommt `quelle text` ∈ `{'eigen','gezogen','mittel'}` und
  `n_messpunkte int`.
- Frontend: ● eigene Messungen · ◐ zum Mittel gezogen · ○ Mittel — mit
  Tooltip, der sagt, aus wie vielen Messpunkten.
- **Prüfung (vorher rot, und die wichtigste dieses Blocks):** hat keine Sorte
  genug eigene Messpunkte, ist das Ergebnis der Kaskade **auf den Rappen
  identisch** mit dem heutigen. Die Schrumpfung darf nichts verschieben,
  solange nichts gemessen ist.

---

### Block G — Zwei Oberflächen und der Schutz der Erfassung (Q14–Q17)

**Q14 — Zwei Webseiten, zwei Datenbanken.**

Der Betrieb will *„2 verschiedene websites - eine für die echten daten und eine
für die sample daten."* Das geht nicht als Laufzeit-Schalter:
`VITE_SUPABASE_URL` und `VITE_SUPABASE_ANON_KEY` werden **beim Bauen**
eingesetzt. Zwei Webseiten heisst zwei Builds.

- `.env.echt` und `.env.beispiel` (beide **nicht** eingecheckt).
  `.env.example` bekommt beide Blöcke als Muster, mit Kommentar.
- `package.json`: `"build:echt": "vite build --mode echt"` und
  `"build:beispiel": "vite build --mode beispiel"`. Keine neue Abhängigkeit,
  kein neues Werkzeug — Vite kann das.
- Neue Einstellung in der Datenbank: `einstellung('betriebsmodus')` ∈
  `{'echt','beispiel'}`, Vorgabe `'echt'`. Sie steht in der **Datenbank**,
  nicht im Build — so kann eine falsch gebaute Seite nicht behaupten, sie sei
  die andere.
- Im Beispielmodus zeigt die App ein **dauerhaftes Band am oberen Rand**:
  „Beispieldaten — nicht der Betrieb". Im Echtmodus nichts.
- **Im Echtmodus verweigern `demo_daten_laden()` und `demo_daten_entfernen()`
  ihre Arbeit** — die Funktionen prüfen die Einstellung selbst und werfen
  einen Fehler mit klarem Text. `DemoDaten.tsx` wird im Echtmodus gar nicht
  angezeigt. Beides, weil das eine ohne das andere nichts wert ist.
- `README.md` bekommt einen Abschnitt **„Zwei Webseiten"**: welche Variable wo
  gesetzt wird, wie man in zehn Sekunden prüft, auf welcher man ist, und was
  passiert, wenn man sich vertut.

**Q15 — Die Erfassung wird unlöschbar.**

Das ist die Zusage an den Betrieb. Vier Dinge zusammen:

**(a) Ein Journal, das jede Änderung festhält.**

```sql
create table if not exists erfassung_journal (
  id        bigserial primary key,
  tabelle   text not null,
  zeile_id  text not null,
  vorgang   text not null check (vorgang in ('insert','update','delete')),
  alt       jsonb,
  neu       jsonb,
  wer       uuid,
  wann      timestamptz not null default now()
);
```

Ein Trigger `erfassung_journal_schreiben()` hängt **nach** jeder Änderung an
jeder Tabelle, in der eine Erfassung steckt — mindestens:
`schimmel_messung`, `ausschuss_messung`, `ausgang_wiegung`,
`verdunstung_wiegung`, `marge_messung`, `auftrag`, `auftrag_palette`,
`auftrag_gebinde`, `kontrollpalette`, `kontrollpalette_wiegung`, `palette`,
`lieferung`, `sortier_lauf`, `sortier_gewicht`. Prüfe selbst, ob weitere dazu
gehören, und begründe deine Liste im Bericht.

Bei `delete` wird die **ganze alte Zeile** als `jsonb` festgehalten. Damit ist
nichts endgültig weg, auch wenn jemand löscht.

- Auf `erfassung_journal` hat **niemand** `update` oder `delete`, auch der
  Admin nicht. `select` nur für Admin. `insert` nur durch den Trigger.
- Das Journal darf die Erfassung nicht bremsen: der Trigger ist
  `after ... for each row`, schreibt eine Zeile und macht sonst nichts.

**(b) Keine Migration darf mehr zerstören.**

Neues Prüfskript `supabase/test/keine_zerstoerung.sh`, Teil von
`supabase/test/run.sh`. Es durchsucht `supabase/migrations/*.sql` nach

- `drop table`, `drop column`, `truncate`
- `delete from <Messtabelle>` ohne `where`
- `alter table ... drop constraint` auf einer Messtabelle

und ist **rot**, wenn es etwas findet. Ausnahmen gibt es nur als
ausdrückliche Freigabeliste im Skript, mit Begründung im Skript selbst.
Prüfe zuerst, ob die bestehenden Migrationen sauber durchlaufen — wenn nicht,
trag die Altfälle in die Freigabeliste ein und benenne sie im Bericht.

**(c) Eine abgeschlossene Arbeit lässt sich nicht mehr löschen.**

Heute darf `authenticated` auf mehreren Messtabellen löschen, solange das
Korrekturfenster offen ist. Neu: gehört die Zeile zu einer **abgeschlossenen**
Arbeit, darf nur noch der Admin löschen — korrigieren (`update`) bleibt im
Fenster erlaubt. Begründung für den Kommentar: der Abschluss ist die Zusage
des Arbeiters, dass es stimmt.

**(d) Eine Sicherung, die der Betrieb selbst ziehen kann.**

- `docs/DATENERHEBUNG.md` bekommt einen Abschnitt **„Sicherung"**: der Weg
  über das Supabase-Dashboard, ein `pg_dump`-Einzeiler zum Kopieren, und die
  Regel: **vor jedem Einspielen von `setup.sql` eine Sicherung.**
- `einstellung('letzte_sicherung')` (Datum, von Hand gesetzt) und auf
  `Betrieb.tsx` eine Zeile: „Letzte vermerkte Sicherung: …" mit Warnfarbe ab
  30 Tagen. Kein automatischer Mechanismus — nur eine Erinnerung, die man
  nicht übersehen kann.
- `einstellung('erfassung_scharf')` (boolean). Steht sie auf `true`, gibt
  `setup.sql` beim Lauf ein deutliches `raise notice` aus: „Auf dieser
  Datenbank stehen echte Erfassungsdaten." Kein hartes Verbot — der
  Betriebsleiter muss weiterarbeiten können — aber sichtbar.

**Q16 — Kistenzahl aus dem Erntejournal.**

Der Betrieb hat bestätigt: *„beim erntejournal - ja anzahl kisten steht."*
`palette.kisten` und `palette.gebindeart` gibt es schon. Prüfe den Importpfad
(`src/lib/import.ts` und die Import-Funktion in der Datenbank) und stelle
sicher, dass beide gefüllt werden, wenn die Quelle sie hat. Wo die Quelle die
Spalte nicht hat, bleibt **NULL**, nicht 0.

Dazu eine kleine Karte auf `Betrieb.tsx`: für wie viele Eingangspaletten die
Kistenzahl bekannt ist (Anzahl und Prozent). Damit sieht der Betrieb, ob der
Weg trägt, bevor eine Rechnung darauf gebaut wird.

**Q17 — Der Arbeiter darf nicht langsamer werden.**

Zähle für jede der vier Tätigkeiten, wie viele Eingaben ein Durchgang
erfordert — vorher und nachher. Erlaubt ist genau ein Zuwachs um die zwei
verlangten Fragen (Gebindeart beim Waschen, fertige Paletten gesamt). Zwei der
Änderungen (Q1, Q3) kosten **weniger** Zeit als heute, weil eine sinnlose
negative Zahl und ein stiller Fehlpfad verschwinden. Trage beide Zahlenreihen
in den Bericht.

---

## 5. Der Arbeitsplan

Sieben Phasen. Jede endet an einem **Tor**: läuft das Tor nicht grün, gehst du
nicht weiter, sondern zurück.

### Phase 0 — Grundlinie (bevor du etwas änderst)

- `npm run pruefen` (typecheck, test, build)
- `bash supabase/test/run.sh`
- `npm run gegenprobe`
- `node pruefstand/bildschirme.mjs` — Bilder **vorher** sichern
- Schreibe die Ergebnisse in `docs/BEFUND_RUNDE_Q.md`, Abschnitt „Grundlinie".

**Tor 0:** Alles, was heute grün ist, ist grün. Ist etwas schon rot, schreibst
du es auf und rührst es nicht an — es gehört nicht zu dieser Runde.

### Phase 1 — Rot zuerst

Schreibe **alle** Prüfungen dieser Runde, bevor du eine Zeile Produktivcode
änderst:

- Block `0072` in `supabase/test/pruefung.sql` mit den Prüfungen aus §4
- `supabase/test/keine_zerstoerung.sh` (Q15b)
- Die Orakel-Gegenrechnungen in `gegenprobe/orakel/` für Q7, Q12, Q13
- Die Frontend-Prüfungen in `test/` für Q2, Q3, Q10

Lass sie laufen. **Sie müssen rot sein.** Kopiere die rote Ausgabe in den
Befund.

**Tor 1:** Jede neue Prüfung ist rot, und zwar aus dem richtigen Grund (nicht
wegen eines Tippfehlers im Test).

### Phase 2 — Migration 0072: das Schema

Nur Tabellen, Spalten, Bedingungen, Rechte, Trigger, Einstellungen. Kein
Rechenwerk. Reihenfolge: A (Palox), B (Gebinde, fertige Paletten), C (voll),
E (Kontrollpalette), G (Journal, RLS, Einstellungen).

Danach `./supabase/setup_bauen.sh` und prüfen, dass `setup.sql` unter der
Grössengrenze des SQL-Editors bleibt (siehe `verdichten.mjs`).

**Tor 2:** `bash supabase/test/run.sh` läuft durch; die Schema-Prüfungen aus
Block 0072 sind grün, die Rechenwerk-Prüfungen noch rot.

### Phase 3 — Migration 0073: das Rechenwerk

Sichten und Funktionen: Q7 (Masse über die Kiste), Q11 (`v_kontrollpalette_rate`),
Q12 (Alter, Quelle, Spanne, Zwischenlagerzeit), Q13 (Verderb mit Schrumpfung
und Zeichen), plus jede Sicht, die wegen `palox_unbekannt` oder wegen
`auftrag_gebinde` angepasst werden muss.

**Tor 3:** Alle Prüfungen grün — auch die aus Phase 1. `npm run gegenprobe`
grün. **Und:** die Kaskade liefert bei null Messpunkten exakt die heutigen
Zahlen (Q13).

### Phase 4 — Die Arbeiter-App

`PaloxMaske.tsx`, `Zaehler.tsx`, `FertigePaletteMaske.tsx`, `Abschluss.tsx`,
`Kontrolle.tsx`, `daten.ts`, `i18n.ts` in allen sechs Sprachen.

Geh jede der vier Tätigkeiten **einmal ganz durch**, im Browser, mit
Beispieldaten — vom Anlegen bis zum Abschluss. Nicht nur die geänderte Maske:
den ganzen Weg. Mach von jedem Schritt ein Bild.

**Tor 4:** Vier vollständige Durchgänge, Bilder da, keine Konsolenfehler, keine
Maske breiter als der Bildschirm. Die Schrittzahlen aus Q17 stehen im Befund.

### Phase 5 — Betriebsleiter und die zwei Oberflächen

Q11 (Karte Kontrollpalette), Q12 (Spanne und Zeichen anzeigen), Q13 (● ◐ ○),
Q14 (zwei Builds, Band, Demo-Sperre), Q16 (Karte Kistenzahl).

**Tor 5:** `npm run build:echt` und `npm run build:beispiel` laufen beide;
`node pruefstand/bildschirme.mjs` ohne Fehler; das Band erscheint im
Beispielmodus und nicht im Echtmodus.

### Phase 6 — Beweis, Doku, Bericht

- Alle Prüfstände noch einmal: `npm run pruefen`, `supabase/test/run.sh`,
  `npm run gegenprobe`, `pruefstand/bildschirme.mjs`, `pruefwerk/lauf.mjs`,
  `werkstatt/lauf.mjs`
- Bilder **nachher** gegen die Bilder **vorher** halten
- `docs/ABLAUF.md`, `docs/ABMACHUNGEN.md`, `docs/ENTSCHEIDUNGEN.md`,
  `docs/DATENERHEBUNG.md`, `README.md` nachziehen
- `docs/halle.html` und das PDF nachziehen: was gebaut ist, steht nicht mehr
  als Änderung da, sondern als Beschreibung. `node docs/pdf_bauen.mjs`
- `docs/BEFUND_RUNDE_Q.md` fertig schreiben

**Tor 6:** Alles grün, Doku stimmt mit dem Code überein, Bericht steht.

---

## 6. Der Bericht — `docs/BEFUND_RUNDE_Q.md`

Er hat genau diese Abschnitte:

1. **Grundlinie** — was vorher lief, was vorher schon rot war
2. **Rot zuerst** — jede neue Prüfung mit ihrer roten Ausgabe
3. **Q1 bis Q17** — je Änderung: was gebaut, welche Datei, welche Prüfung
   belegt es, und **was du anders gemacht hast als hier beschrieben, mit Grund**
4. **Die Schrittzahlen** (Q17), vorher und nachher, je Tätigkeit
5. **Was nicht geht** — jeder Punkt, den du nicht fertig bekommen hast, mit
   dem Stand und dem, was fehlt. Lieber drei ehrliche Lücken als eine
   behauptete Vollständigkeit.
6. **Was dem Betrieb auffallen wird** — Änderungen, die ein Arbeiter oder der
   Betriebsleiter am Bildschirm merkt, in einfachen Sätzen
7. **Offene Fragen**, die beim Bauen neu aufgetaucht sind

---

## 7. Was du nicht machst

- **Keine Tabelle, keine Spalte, keine Zeile löschen.** Auch nicht die, die du
  für tot hältst. Stilllegen und kommentieren.
- **Keine Prüfung abschalten, abschwächen, überspringen, in Quarantäne stellen
  oder mit einem `skip` versehen**, um grün zu werden.
- **Kein leerer Commit, kein Force-Push, keine Historie umschreiben.**
- **Keine neue Abhängigkeit** in `package.json`.
- **Keinen Pull Request**, ausser der Betrieb verlangt ihn ausdrücklich.
- **Keine Zahl aus den Beispieldaten** in Code, Kommentar, Doku oder Bericht
  als Aussage über den Betrieb.
- **Die Kaskade nicht umstellen.** Q13 baut die Zeichen und die Schrumpfung,
  aber solange nichts gemessen ist, rechnet sie exakt wie heute.
- **Das Dashboard nicht neu gestalten.** Diese Runde ist die Erfassung. Die
  Auswertung bekommt genau die Karten, die in §4 stehen, und keine weitere.
- **Nichts „für später" offen lassen.** Kein `TODO`, kein `FIXME`, kein
  auskommentierter Block. Was nicht fertig wird, steht im Bericht unter
  „Was nicht geht" — nicht im Code.

### Ausdrücklich verschoben — nicht vergessen, sondern später

Diese fünf Dinge sind besprochen und gewollt, gehören aber **nicht** in diese
Runde. Baue sie nicht, aber baue auch nichts, was sie später verhindert:

| Verschoben | Warum nicht jetzt | Was diese Runde dafür vorbereitet |
|---|---|---|
| **Lager-Management**: „von diesem Kaliber dieser Charge ist noch so viel da" | Dashboard, und es braucht erst echte Erfassung | Q7 (Masse über die Kiste), Q12 (Alter) |
| **Kalibermigration**: wie viele Kürbisse durch Verdunstung unter ihre Bandkante rutschen | braucht die gemessene Lage im Band und eine belastbare Verdunstungsrate | Q9 (Lage im Band), Q11 (Kontrollpalette) |
| **Überfüllung in Franken**, verknüpft mit der Verkaufsdatei | braucht `kg je Kiste` und `Kürbisse je Kiste` aus echten Wägungen | Q9 |
| **FIFO statt proportionaler Entnahme** in der Kaskade | eine Rechenentscheidung, die ohne echte Eingangsdaten nicht prüfbar ist | Q12 (Alter und Spanne sauber trennen) |
| **Die Verdunstungskurve statt einer festen Rate** | erst wenn die Kontrollpalette Messpunkte geliefert hat | Q11 (`v_kontrollpalette_rate`) |

Wenn dir beim Bauen auffällt, dass eine Entscheidung dieser Runde eines dieser
fünf Dinge später unmöglich machen würde, **hörst du auf und schreibst es in
den Bericht**, statt die Entscheidung stillschweigend zu treffen.

---

## 8. Commits und Zweig

- Entwickeln und pushen **nur** auf `claude/new-session-vrnnyo`:
  `git push -u origin claude/new-session-vrnnyo`. Bei Netzfehlern bis zu
  viermal wiederholen (2 s, 4 s, 8 s, 16 s).
- Ein Commit je Block (A bis G), deutsche Commit-Nachricht, die sagt **was**
  und **warum**, nicht welche Datei.
- Kein Modellname in Code, Kommentar, Commit, Dokument oder sonst einem
  Artefakt, das ins Repo geht.
- Die echten Excel-Dateien unter `/root/.claude/uploads/` enthalten
  Kundennamen und Preise: lokal lesen ist erlaubt, **committen nie**.

---

## 9. Offene Fragen des Betriebs — und was gilt, solange keine Antwort da ist

Fünfzehn Fragen stehen in `docs/Die-Arbeiter-App.pdf`, Kapitel 11. Sie sind
**nicht beantwortet**. Du wartest nicht darauf. Für jede, die deine Arbeit
berührt, gilt diese Voreinstellung — und du baust so, dass die andere Antwort
später **ohne Datenverlust** nachgezogen werden kann:

| Frage | Voreinstellung für diese Runde | Was sich bei der anderen Antwort ändert |
|---|---|---|
| **3** — Steht das Kistensystem beim Anlegen fest? | **Ja**, wie heute: eine Wahl je Arbeit | Bei gemischt muss die Frage von der Arbeit auf die fertige Palette wandern. Baue `ausgang_wiegung` so, dass eine spätere eigene Spalte dort möglich ist. |
| **4a** — Wird der Palox während einer Arbeit geleert? | **Selten.** Die Frage im Abschluss bleibt klein und unauffällig | Bei „oft" wird sie ein eigener Schritt |
| **4b** — Zwei Arbeiten gleichzeitig an derselben Waschstrasse? | **Nein** | Sonst braucht die Palox-Differenz eine Zuordnung auf zwei Arbeiten |
| **5a** — Wird die CSV immer hochgeladen? | **Nein, nicht immer** — darum der Hinweis am Abschluss (Q8) und kein Sperren | Bei „immer" könnte der Hinweis weg |
| **8b** — Immer gleich viele Kisten auf einer G2-Palette? | **Nein**, deshalb je Palette gefragt | Bei „immer" reicht eine Zahl je Arbeit |
| **10a** — Ist die letzte fertige Palette meist nicht voll? | **Ja** — darum das Häkchen `voll` (Q9) | — |
| **13b** — Wie viele Sorten, wie oft wiegen? | **Eine Kontrollpalette je Sorte, monatlich.** Hinweis ab 45 Tagen | Bei engeren Abständen nur die Schwelle ändern |
| **14** — Verderb: Unterschiede eher je Sorte oder je Schlag? | **Je Sorte** gruppieren | Bei „je Schlag" ändert sich nur die Gruppierungsspalte — bau sie als eine Stelle, nicht als zehn |
| **15** — Wie oft laufen zwei Chargen in einem Durchgang? | **Selten.** Gemischte Arbeiten fallen wie heute aus der Alterskurve | Bei „oft" braucht es eine zweite Chargennummer und eine Aufteilung |

---

## 10. Woran du merkst, dass du fertig bist

Nicht daran, dass die Tests grün sind. Daran, dass diese sieben Sätze stimmen:

1. Eine Arbeit liest ihren eigenen Palox-Anfang und ihr eigenes Ende ab, und
   keine Zahl aus einer fremden Arbeit kommt je vor.
2. Fällt der Stand, fragt die App — und was dann herauskommt, ist *unbekannt*,
   nie *null*.
3. Keine Rechnung im ganzen Projekt setzt eine Eingangspalette mit einer
   Ausgangspalette gleich.
4. Ein Alter, das geschätzt ist, sieht auf dem Bildschirm anders aus als
   eines, das gemessen ist — und man kann sehen, wie unsicher es ist.
5. Es gibt zwei Webseiten, und auf der echten kann niemand aus Versehen
   Beispieldaten laden.
6. Löscht jemand eine Messzeile, steht sie vollständig im Journal, und wer es
   war, steht dabei.
7. Der Arbeiter tippt nicht öfter als vorher — ausser die zwei Fragen, die der
   Betrieb ausdrücklich wollte.

Wenn einer dieser Sätze nicht stimmt, ist die Runde nicht fertig. Dann schreib
das in den Bericht, statt es grün aussehen zu lassen.
