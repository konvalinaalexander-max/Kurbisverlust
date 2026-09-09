import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

/**
 * Vier Bündel statt einem — zugeschnitten auf die beiden Rollen.
 *
 * Der Arbeiter in der Halle zählt Paletten auf einem alten Handy in einem
 * Netz, das kommt und geht. Er hat die Auswertung des Betriebsleiters noch
 * nie gebraucht, lud sie aber bei jedem Start mit: Diagramme, Kaskade,
 * Excel-Leser — 822 kB, bevor der erste Knopf erschien.
 *
 * Seit Vite 8 bündelt Rolldown. Ohne Anweisung legt es alles in eine Datei,
 * auch was hinter React.lazy steht. Die Gruppen hier sagen, was zusammen
 * gehört; App.tsx sagt mit React.lazy, was warten darf.
 *
 *   fremd       React, Router, Supabase — ändert sich nur beim Aktualisieren
 *   auswertung  nur der Betriebsleiter: seine fünf Seiten, die Diagramme,
 *               die Kaskade, der Excel-Leser
 *   grundlage   was beide brauchen: Bausteine, Format, Anbindung, die
 *               Arbeiter-Masken-Bausteine
 *   index       Anmeldung und die vier Arbeiter-Bildschirme
 *
 * Der Vorrang bei „grundlage" ist der Kniff: Ohne ihn zieht die Auswertung
 * die gemeinsame Grundlage an sich, der Einstieg muss sie von dort holen —
 * und lädt damit die ganze Auswertung doch wieder mit, nur über einen Umweg.
 * Damit dabei nicht umgekehrt der Excel-Leser in der Grundlage landet, nimmt
 * ihre Regel die schweren Betriebsleiter-Teile ausdrücklich aus.
 */

// Was nur der Betriebsleiter braucht.
const NUR_BETRIEBSLEITER =
  /src[\\/](pages[\\/](Ueberblick|Ursachen|Chargen|Messungen|Betrieb|Lieferungen|Stammdaten|Zugang|CsvUpload|Warteschlange)|auswertung[\\/]|betrieb[\\/]|components[\\/](Diagramm|Kaskadenbild)|lib[\\/](csv|xlsx|warenausgang|import|dateiname))/

// Was beide Rollen brauchen — ohne das, was oben schon abgefangen ist.
const NUR_GEMEINSAM =
  /src[\\/](?!lib[\\/](csv|xlsx|warenausgang|import|dateiname)|components[\\/](Diagramm|Kaskadenbild))(lib|components|arbeit|auth|sprache)[\\/]/

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    // Quellkarten bleiben an: Geht in der Halle etwas schief, soll der
    // Fehlerbericht die Zeile im Quelltext nennen und nicht Spalte 41 812.
    sourcemap: true,
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [
            { name: 'fremd', test: /node_modules/ },
            { name: 'auswertung', test: NUR_BETRIEBSLEITER },
            { name: 'grundlage', test: NUR_GEMEINSAM, priority: 10 },
          ],
        },
      },
    },
  },
})
