# Prompt: alles kritisch nachprüfen — Daten, Mathematik, Anzeige

Diesen Text in einer neuen Sitzung einfügen.

---

Dieses Projekt schätzt aus lückenhaften Stichproben, **wo** bei Lagerung und Verarbeitung von
Kürbissen Masse verloren geht und **welche Ursache dominiert**. Es läuft, es hat drei
Überarbeitungsrunden hinter sich, und es ist gut dokumentiert.

**Dein Auftrag ist Misstrauen.** Nimm nichts als richtig hin, nur weil es dasteht, getestet
aussieht oder in einer Doku begründet ist. Prüfe die ganze Kette — von der Zahl, die ein
Arbeiter eintippt, bis zu dem Balken, den der Betriebsleiter auf dem Bildschirm sieht — und
weise für jedes Glied **nach**, dass es stimmt. Wo es nicht stimmt, reparierst du es. Wo die
Reparatur nicht reicht, baust du es neu.

Arbeite selbstständig. Frag nicht bei jedem Schritt. Sammle Fragen, die wirklich nur der
Betrieb beantworten kann, und stelle sie gebündelt am Schluss — arbeite in der Zwischenzeit an
allem weiter, was ohne die Antworten geht.

## Zuerst lesen, und zwar vollständig

- `docs/ABLAUF.md` — was auf dem Betrieb passiert; enthält oben die frisch bestätigten Fakten
- `docs/SPEC.md` — die ursprüngliche fachliche Spezifikation
- `docs/ENTSCHEIDUNGEN.md` — jede Modellentscheidung mit Begründung
- `docs/STATISTIK_BEFUND.md` — was die bisherigen Prüfungen ergeben haben, mit Messwerten
- `docs/Datenarchitektur.pdf` bzw. `docs/architektur.html` — wie Daten gespeichert werden sollen
- `docs/FRAGEN.md` — was noch offen ist
- `README.md`, Abschnitt „Tests"

## Die vier Regeln, nach denen hier gearbeitet wird

1. **Nichts glauben, was nicht gemessen ist.** Eine Begründung in einem Kommentar ist kein
   Beleg. Wenn du behauptest, etwas sei besser geworden, zeig die Zahl vorher und nachher.
2. **Erst die Messung, dann die Änderung.** Kannst du einen Fehler nicht sichtbar machen, baue
   zuerst das, was ihn sichtbar macht. Ein Fix ohne vorher reproduzierten Fehler ist eine
   Vermutung.
3. **Eine Verbesserung, die man nicht messen kann, ist keine.** In diesem Projekt wurden schon
   drei plausibel klingende Ansätze gebaut und wieder entfernt, weil die Messung sie widerlegt
   hat. Halte es genauso.
4. **Leer ist nicht null.** Eine fehlende Messung ist NULL oder gar keine Zeile, niemals eine
   Null. Eine Null ist eine Aussage über die Welt, eine Lücke ist keine.

## Die Werkzeuge, die es schon gibt — benutze sie, erweitere sie

```bash
# Datenbank: sieben Stufen, inkl. Aktualisierung von altem Stand und Lasttest
./supabase/test/run.sh 'postgresql://…'

# Statistik: erzeugt Saisons mit bekannter Wahrheit und misst Verzerrung + Überdeckung
./supabase/test/simulation/matrix.sh 25

# Bildschirme: rendert jede Seite im echten Browser (Handy/Desktop, hell/dunkel),
# meldet Konsolenfehler und wagrechtes Überlaufen
./pruefstand/daten_dumpen.sh          # zieht Fixtures aus der lokalen Demo-Datenbank
node pruefstand/bildschirme.mjs

npm test && npx tsc --noEmit && npm run build
```

**Wichtig: lies den Code nicht nur — führe ihn aus.** Setz eine lokale Postgres auf, spiel
`setup.sql` ein, lade die Demo-Saison, render die Bildschirme, sieh dir die Bilder an. Die
schwersten Fehler dieses Projekts waren allesamt unsichtbar, solange niemand hingeschaut hat.

### Umgebung, damit du keine Zeit verlierst

```bash
# Postgres 16 ist da, muss aber als Benutzer "postgres" laufen (nicht als root)
mkdir -p /tmp/pgdata /tmp/pgsock && chown -R postgres:postgres /tmp/pgdata /tmp/pgsock
su postgres -c "/usr/lib/postgresql/16/bin/initdb -D /tmp/pgdata -U postgres --auth=trust -E UTF8 --locale=C"
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgdata -o '-k /tmp/pgsock -p 55432 -c listen_addresses=' -l /tmp/pg.log start"
URL='postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432'

# Chromium liegt fertig unter /opt/pw-browsers/chromium (kein playwright install nötig)
# Für den Bildschirm-Prüfstand braucht .env.local:
#   VITE_SUPABASE_URL=http://localhost:5199
#   VITE_SUPABASE_ANON_KEY=sb_publishable_pruefstand_000000000000
```

## Was bereits als falsch bekannt ist — hier fängst du an

Diese drei Punkte sind seit der letzten Betriebsrückmeldung offen. Sie sind **nicht** entdeckt
worden, sie sind gemeldet — du musst sie nicht suchen, sondern lösen. Details in `ABLAUF.md`
unter „Die Antworten vom 2. September".

1. **Der Palox ist ein Kompost-Behälter, kein Schimmel-Behälter.** Darin landen auch Erde,
   Blätter und optisch Ausgeschiedenes (Hagelnarben, Schnittfehler). Das Modell liest den
   ganzen Inhalt als zeitabhängigen Verderb und passt die Weibull-Kurve daran an. Ein
   zeitunabhängiger Sockel verzieht die Kurve dort, wo die Steigung entschieden wird.
   Der gemessene Anteil ist `a₀ + (1 − a₀)·F(t)`. Schätze `a₀` mit, weise es als eigenen
   Strom aus („nicht lagerbedingt"), und **zeige an der Simulation, dass es die Verzerrung
   verkleinert** — sonst lass es.
2. **Zu Kleine gehen an die Tiere.** Sie sind kein physischer Verlust, sondern ein anderer
   Kanal wie die zu Grossen. Von Buch A nach Buch B, und im Dashboard entsprechend
   ausgewiesen.
3. **Das Sortierschema hängt am Käufer, nicht an der Sorte.** Kaliber-Grenzen sind damit eine
   Eigenschaft von (Sorte × Käufer) zu einem Zeitpunkt. Eine CSV vom Oktober muss mit den
   Grenzen vom Oktober klassiert werden. Das verlangt zeitlich gültige Stammdaten — siehe
   Datenarchitektur.

Dazu die Richtung aus `docs/architektur.html`: **gespeichert wird, was beobachtet wurde, nie
was daraus gefolgert wurde.** Prüfe jede Tabelle daran. Wo eine gefolgerte Zahl gespeichert
ist (etwa eine fertige Kilomenge statt der zwei Waage-Ablesungen), ist das ein Befund.

## Die Fehlerarten, die dieses Projekt schon hatte

Das ist keine Anekdotensammlung, sondern dein Suchraster. Jeder dieser Fehler war unauffällig,
lief durch alle Tests und wurde erst durch gezieltes Nachmessen gefunden. Suche nach mehr
davon.

| Was war | Wie es sich zeigte |
|---|---|
| Eine ganze Migration war wirkungslos | Die Ansicht rief die geänderte Funktion gar nicht auf. Die Datei lief durch, änderte aber nichts. |
| Eine Ansicht umbenennen hebt die Materialisierung auf | Postgres verfolgt Abhängigkeiten über OIDs — die Verbraucher folgten der Umbenennung still. |
| Sorten ohne Messung bekamen Koeffizient 0 | „Kein Verlust" statt „unbekannt". Verschluckte 37 % der Verdunstung. |
| `sum()` überspringt NULL | Paletten ohne Gebindeart fielen aus der Eingangsmasse. 10 % zu klein — und damit jede Quote 10 % zu gross. |
| Ein ganzer Strom verschwand spurlos | 900 kg erfasster Schimmel erzeugten **null** Zeilen in der Auswertung. |
| Drei Szenarien statt Fehlerfortpflanzung | Ergab eine **negative** Bereichsbreite: Untergrenze über Obergrenze. |
| `sd/√n` statt chargen-robust | Standardfehler um **Faktor 31** zu klein, ausgerechnet bei der Steigung. |
| Eine CSS-Variable, die es nie gab | Der Ersatzwert griff — im Dunkelmodus mit demselben Hellgrau wie im Hellen. |
| Eine State-Variable verdeckte eine Funktion | Die Seite stürzte beim Rendern ab; kein Test merkte es. |
| Jede Handy-Seite lief 2 px über | Sichtbar nur im gerenderten Bildschirm. |
| `PUBLIC` durfte `security definer`-Funktionen ausführen | Ein `grant … to authenticated` nimmt das Standardrecht nicht zurück. |
| `setup.sql` konnte nie aktualisieren | Eine Schutzsperre machte jede bestehende Installation zur Sackgasse. |

## Die Kette, die stimmen muss

Das ist der Kern des Auftrags. Für **jede** Zahl, die im Dashboard steht, gehst du rückwärts
bis zur Rohzeile und prüfst:

- **Einheit** — kg, Gramm, Prozent, Anteil. Wo wird geteilt, wo multipliziert, wo mal 100?
- **Bezugsmasse** — bezieht sich der Prozentsatz auf den Eingang, auf die Masse nach
  Verdunstung, oder auf den Durchsatz? Die Kaskade hat eine Reihenfolge, und sie gilt.
- **Vorzeichen und Richtung** — wird etwas abgezogen, das schon abgezogen war?
- **Filter** — greift derselbe Filter in der Anzeige wie in der Datenbank-Funktion? Werden
  abgebrochene Aufträge überall gleich behandelt?
- **Doppelzählung** — kann dieselbe Masse in zwei Strömen landen?
- **Leer gegen Null** — was passiert bei fehlender Messung? Steht dann „—" oder „0"?

Bau dafür etwas Nachvollziehbares statt es einmal von Hand zu prüfen: eine Prüfabfrage, die
für jede Dashboard-Ansicht die Summen gegen die Rohtabellen stellt, und die bei jedem Testlauf
mitläuft. Wenn eine Zahl auf dem Bildschirm nicht aus der Datenbank herzuleiten ist, ist das
ein Befund — auch wenn die Zahl plausibel aussieht.

**Prüfe ausserdem in beide Richtungen:** Nicht nur „stimmt die angezeigte Zahl", sondern auch
„wird alles angezeigt, was erfasst wurde". Erfasse testweise über die Masken der App einen
kompletten Auftrag mit allem Drum und Dran und verfolge jeden eingegebenen Wert bis in die
Auswertung. Was unterwegs verschwindet, ist der schlimmste Fehlertyp dieses Projekts — er ist
zweimal vorgekommen.

## Was am Ende dastehen muss

- Alle Prüfungen grün, mit der Ausgabe im Chat: `run.sh`, `npm test`, `tsc`, `build`,
  Bildschirm-Prüfstand ohne Konsolenfehler und ohne Überlauf.
- Die Simulationsmatrix gefahren, mit **Verzerrung und Überdeckung je Strom** — und zwar vorher
  und nachher, damit man sieht, was deine Änderungen gebracht haben.
- `setup.sql` passt zu den Migrationen (Stufe 7 prüft es).
- Die Dokumentation nachgeführt: jede Modelländerung mit Begründung **und Messwert** in
  `docs/ENTSCHEIDUNGEN.md`, jede neue Annahme in der Tabelle in `docs/ABLAUF.md`.
- Committet und auf den Branch gepusht.

Am Schluss im Chat, in dieser Reihenfolge:

1. **Was war falsch** — je Befund: was, wie gefunden, wie gross die Auswirkung in Zahlen.
2. **Was du geändert hast** — und womit du belegst, dass es besser ist.
3. **Was du geprüft und für richtig befunden hast** — auch das gehört dazu; eine bestätigte
   Annahme ist ein Ergebnis.
4. **Was offen bleibt** — und was der Betrieb dafür beantworten müsste.

Schreib das für jemanden, der die Statistik nicht studiert hat, aber sein Handwerk versteht.
Keine Fachbegriffe ohne Erklärung, keine Zahl ohne Einordnung.

## Wie du arbeiten sollst

- **Nutze deine agentischen Fähigkeiten.** Plane, arbeite parallel wo es geht, delegiere
  Teilprüfungen an Unteragenten, sammle die Ergebnisse ein. Warte nicht auf Bestätigungen für
  Offensichtliches.
- **Denk weiter, als der Auftrag reicht.** Wenn dir beim Prüfen etwas auffällt, das niemand
  gefragt hat, geh dem nach. Die wertvollsten Befunde dieses Projekts kamen so zustande.
- **Wenn du etwas neu baust, dann ganz.** Kein Nebeneinander von altem und neuem Weg, keine
  toten Ansichten, keine auskommentierten Reste.
- **Halte die Kosten bei null.** Supabase- und Cloudflare-Gratisstufen; keine neue Abhängigkeit
  ohne zwingenden Grund. Supabase bricht Abfragen nach 8 Sekunden ab — das ist eine harte
  Grenze, und der Lasttest prüft sie.

## Was du nicht tun sollst

- **Keinen Test abschalten, aufweichen oder überspringen**, um grün zu werden. Ein roter Test
  ist ein Befund, kein Hindernis.
- **Keine Zahl schönen.** Wo ein Bereich breit ist, bleibt er breit. Zu breit ist die richtige
  Seite, um danebenzuliegen.
- **Keine Annahme still einbauen.** Jede Annahme kommt in die Tabelle in `ABLAUF.md`, mit der
  Folge, wenn sie nicht stimmt.
- **Kein Modellumbau ohne gemessenen Nachweis**, dass er besser ist. Plausibilität genügt hier
  nicht — das ist in diesem Projekt schon dreimal schiefgegangen.
- **Nichts löschen, was Daten enthält.** Abbrechen statt löschen, überholt statt weg.
