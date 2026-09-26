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
| `kurzfassungen.json` | **Der Rückweg** (0094): die Kurzfassungen der Kommentare zur Ware, eine je Nr. — von der Runde am Programm geschrieben, vom Abzug in die Datenbank eingespielt (täglich, und sofort beim Push). Erst damit steht ein Kommentar im Dashboard. |

Die `.md`-Dateien nicht von Hand ändern — der nächste Abzug überschreibt.
`kurzfassungen.json` ist die eine Datei hier, die *geschrieben* wird.
Solange die Secrets fehlen, stehen hier nur diese Zeilen.
