# docs/betrieb — was die Halle sagt, was die Auswertung findet

Diese Dateien schreibt `pruefstand/betrieb_abzug.mjs` (täglich über den
Workflow `.github/workflows/betrieb_abzug.yml`, sobald die zwei Secrets
gesetzt sind). Sie sind der Anfang jeder Runde am Programm — siehe
`CLAUDE.md` im Wurzelverzeichnis.

| Datei | Inhalt |
|---|---|
| `RUECKMELDUNGEN.md` | Rückmeldungen zur App (Aufgaben für die nächste Runde) und zur Ware (für den Betriebsleiter), mit Transkript der Aufnahmen |
| `AUFFAELLIGKEITEN.md` | Alle Auffälligkeiten der Messungen, gezählt nach Art und einzeln mit Arbeit |
| `MODELLSTAND.md` | Koeffizienten, Verderbsmodell, Datenqualität, Bilanz — zum Abgleich mit `docs/SAISONBEGLEITUNG.md` |
| `VERLAUF.md` | Eine Zeile je Abzug: werden die Auffälligkeiten weniger? |
| `rohdaten/*.json` | **Alle Rohdaten** je Tabelle (Spalten laut `ROHTABELLEN` in `pruefstand/durchgang_pruefungen.mjs`) — ohne Kundennamen, Preise, freie Texte, Personen. Damit jede Runde jede Zahl nachrechnen kann. |
| `ROHDATEN.md` | Was davon abgezogen wurde: Tabelle, Zeilen, Spalten. |
| `DURCHGANG.md` | Der **Plausibilitätsdurchgang** über die Rohdaten: Kandidaten mit Grund und Zahlen, nach Schwere. Kein Urteil — die Runde liest, rechnet nach, schreibt die Zweitmeinung. |
| `ZWEITMEINUNG.md` | **Die Zweitmeinung** der Runde am Programm über den Durchgang: was wohl passiert ist, wie sicher, was zu prüfen ist — nach Wichtigkeit, mit Nummern. Von Hand geschrieben, datiert; die nächste ersetzt sie. Der Abzug fasst sie nicht an. |
| `kurzfassungen.json` | **Der Rückweg** (0094): die Kurzfassungen der Kommentare zur Ware, eine je Nr. — von der Runde am Programm geschrieben, vom Abzug in die Datenbank eingespielt (täglich, und sofort beim Push). Erst damit steht ein Kommentar im Dashboard. |

Die `.md`-Dateien nicht von Hand ändern — der nächste Abzug überschreibt.
`kurzfassungen.json` und `ZWEITMEINUNG.md` sind die zwei Dateien hier, die
von der Runde *geschrieben* werden.
Solange die Secrets fehlen, stehen hier nur diese Zeilen.
