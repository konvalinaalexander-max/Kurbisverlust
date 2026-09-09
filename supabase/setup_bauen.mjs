/**
 * Baut supabase/setup.sql aus supabase/migrations/ — die eine Datei, die der
 * Nutzer im Supabase-SQL-Editor einfügt.
 *
 * Aufruf: ./supabase/setup_bauen.sh   (nach jeder Änderung an migrations/)
 *
 * Die eigentliche Arbeit — was bleibt, was zusammenfällt, in welcher
 * Reihenfolge — steht in verdichten.mjs; dort ist auch begründet, warum.
 * Hier steht nur, was drumherum gehört: Kopf, Abschnitte, Fuss.
 */
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { anweisungen, verdichten } from './verdichten.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))
const MIGRATIONEN = join(HIER, 'migrations')
const ZIEL = join(HIER, 'setup.sql')

const dateien = readdirSync(MIGRATIONEN).filter(f => f.endsWith('.sql')).sort()

// Jede Migration mit einem Kopf versehen, damit man in setup.sql sieht, woher
// eine Anweisung stammt. Der Kopf klebt am Text davor und wandert mit ihm.
let quelle = ''
for (const f of dateien) {
  quelle += '\n\n-- =====================================================================\n'
  quelle += `-- aus ${f}\n`
  quelle += '-- =====================================================================\n\n'
  quelle += readFileSync(join(MIGRATIONEN, f), 'utf8')
}

const v = verdichten(anweisungen(quelle))

const KOPF = `-- =====================================================================
-- Kürbis-Verlust-Tracking — das komplette Setup in einer Datei
--
-- ERZEUGT. Nicht von Hand ändern — Quelle ist supabase/migrations/*.sql,
-- gebaut von supabase/setup_bauen.sh.
--
-- SO WIRD SIE BENUTZT
--   1. Diese Datei komplett markieren und kopieren (Strg+A, Strg+C).
--   2. Im Supabase-Dashboard links auf "SQL Editor".
--   3. In das grosse leere Feld einfügen (Strg+V).
--   4. Unten rechts auf "Run" klicken.
-- Das war alles. Keine weitere Datei.
--
-- DIESELBE DATEI AKTUALISIERT AUCH
--
-- Sie richtet nicht nur ein, sie bringt eine bestehende Datenbank ebenso
-- auf den neuesten Stand — gleiche Datei, gleiche vier Handgriffe. Die
-- Daten bleiben dabei stehen; erneuert wird nur, was die Datenbank aus
-- ihnen ausrechnet. Alles läuft in einer Transaktion, es gibt also kein
-- halb Aktualisiertes: entweder ganz durch, oder alles wie vorher.
--
-- Unten im Ergebnisfenster muss danach eine Zeile stehen, die mit
-- "Fertig." beginnt und die Anzahl Chargen und Sorten nennt.
--
-- WIE SIE AUFGEBAUT IST
--
-- Teil A ist die Geschichte: Tabellen, Spalten, Bedingungen, Rechte und die
-- Nachträge an den Daten, Migration für Migration. Jeder Schritt zählt —
-- eine Datenbank, die seit dem Frühjahr läuft, wird genau durch sie auf den
-- heutigen Stand gebracht.
--
-- Teil B ist das Rechenwerk: die Ansichten und die Funktionen, die auf ihnen
-- rechnen. Das ist keine Geschichte, sondern ein Zustand — es zählt nur, wie
-- die Formel heute lautet. Jede steht deshalb genau einmal.
--
-- Das ist nicht nur ordentlicher, es war nötig: Aneinandergereiht ergaben die
-- Migrationen 1,14 MB, und der SQL-Editor nimmt höchstens 1 MB ("Query is too
-- large to be run via the SQL Editor"). Über die Hälfte davon waren Fassungen
-- von Formeln, die eine spätere Migration ohnehin überschreibt.
-- =====================================================================

-- Nur Warnungen und Fehler anzeigen.
--
-- Diese Datei räumt vor jedem Anlegen auf ("drop ... if exists"), damit sie
-- auf einer leeren wie auf einer bestehenden Datenbank läuft. Auf einer
-- leeren gibt es nichts wegzuräumen, und Postgres sagt das jedes Mal:
-- "materialized view ... does not exist, skipping". Das sind über hundert
-- Zeilen, die aussehen wie eine Wand von Problemen und keines sind. Sie
-- bleiben hier unsichtbar; was wirklich schiefgeht, kommt als WARNING oder
-- ERROR durch und ist dann auch zu sehen.
set client_min_messages = warning;

-- =====================================================================
-- TEIL A — Tabellen, Daten, Rechte: die Geschichte
-- =====================================================================
`

const TEIL_B = `


-- =====================================================================
-- TEIL B — Das Rechenwerk: die Formeln, wie sie heute lauten
-- =====================================================================
-- Ab hier steht jede Ansicht und jede darauf rechnende Funktion genau
-- einmal — in ${v.reihe.length} Schritten, in der Reihenfolge, in der eine auf der
-- anderen steht. Die Reihenfolge ist ausgerechnet, nicht geraten:
-- setup_bauen.sh sortiert topologisch und bricht ab, wenn sie nicht
-- kreisfrei wäre.
--
-- Zuerst wird weggeräumt, in umgekehrter Reihenfolge. Auf einer leeren
-- Datenbank passiert dabei nichts; auf einer bestehenden verschwindet das
-- alte Rechenwerk, damit das neue sauber daneben steht statt darüber.
-- Die Daten sind davon nicht berührt: In Ansichten liegt nichts, sie
-- rechnen nur. Was in den gespeicherten Ansichten (mv_…, erg_…) steht,
-- wird am Ende dieser Datei neu berechnet.
-- =====================================================================

`

const BAUEN = `

-- ---------------------------------------------------------------------
-- Neu bauen — von unten nach oben
-- ---------------------------------------------------------------------
`

const ANHANG = `

-- ---------------------------------------------------------------------
-- Beschreibungen, Leserechte und Indizes
-- ---------------------------------------------------------------------
-- Nach einem "drop" ist beides weg: Was eine Ansicht bedeutet und wer sie
-- lesen darf. Beides wird hier wieder gesetzt.
-- ---------------------------------------------------------------------
`

const FUSS = `


-- =====================================================================
-- Der App sagen, dass es etwas Neues gibt
-- =====================================================================
-- Zwischen der Datenbank und der App sitzt PostgREST. Es merkt sich, welche
-- Tabellen und Funktionen es gibt, und schaut nicht bei jeder Anfrage neu
-- nach. Ohne diesen Anstoss kann die App nach einer Aktualisierung noch eine
-- Weile behaupten, eine gerade angelegte Funktion gebe es nicht — genau die
-- Meldung "Could not find the function ... in the schema cache". Der Anstoss
-- wird beim Abschluss der Transaktion zugestellt, also erst, wenn wirklich
-- alles durchgelaufen ist.
notify pgrst, 'reload schema';

-- =====================================================================
-- Die Auswertung einmal rechnen — hier, und nur hier
-- =====================================================================
-- Die gespeicherten Auswertungen (mv_…) werden oben ohne Inhalt angelegt.
-- Gerechnet wird einmal, am Ende, mit den heutigen Formeln. Geht das schief,
-- ist die Datenbank trotzdem aktualisiert: die Fertig-Zeile sagt es, und
-- die App rechnet beim nächsten Öffnen erneut.
do $$
begin
  perform auswertung_aktualisieren();
  perform set_config('kuerbis.auswertung', 'Auswertung berechnet.', false);
exception when others then
  perform set_config('kuerbis.auswertung',
    format('Auswertung NICHT berechnet (%s) — die App versucht es beim nächsten Öffnen erneut; unter Messungen → Auffälligkeiten nachsehen.', sqlerrm),
    false);
end $$;

-- =====================================================================
-- Rückmeldung im Ergebnisfenster
-- =====================================================================
-- Was der Nutzer wissen muss, steht in dieser einen Zeile — die Hinweise
-- oben sind stummgeschaltet. Dazu gehört auch, ob pg_cron da ist: Fehlt es,
-- rechnet die App selbst nach, statt dass ein Zeitplan es tut.
do $$
begin
  perform set_config('kuerbis.cron',
    case when exists (select 1 from pg_extension where extname = 'pg_cron')
         then '' else ' Ohne pg_cron rechnet die App selbst nach, wenn etwas veraltet ist.' end,
    false);
end $$;

select format('Fertig. Die Datenbank steht: %s Chargen, %s Sorten, %s Tabellen, %s Auswertungen. %s%s Weiter im README bei Schritt 4.',
              (select count(*) from charge),
              (select count(*) from sorte_kaliber),
              (select count(*) from pg_tables where schemaname = 'public'),
              (select count(*) from pg_views  where schemaname = 'public'),
              coalesce(nullif(current_setting('kuerbis.auswertung', true), ''), 'Auswertung nicht gerechnet.'),
              coalesce(current_setting('kuerbis.cron', true), '')) as ergebnis;
`

const inhalt = KOPF
  + v.teilA.join('')
  + TEIL_B + v.raeumen.join('\n') + '\n'
  + BAUEN + v.bauen.join('')
  + ANHANG + v.anhang.join('')
  + FUSS

writeFileSync(ZIEL, inhalt)

const kb = n => (n / 1024).toFixed(0) + ' KB'
const summe = a => a.reduce((s, x) => s + x.length, 0)
const roh = summe(anweisungen(quelle))
console.log(`supabase/setup.sql geschrieben — ${inhalt.split('\n').length} Zeilen, ${kb(inhalt.length)}`)
console.log(`  Teil A: ${v.teilA.length} Anweisungen, ${kb(summe(v.teilA))}`)
console.log(`  Teil B: ${v.reihe.length} Objekte, ${kb(summe(v.bauen) + summe(v.anhang))}`)
console.log(`  verdichtet aus ${dateien.length} Migrationen (${kb(roh)}) — ${(100 - 100 * inhalt.length / roh).toFixed(0)} % kleiner`)
if (inhalt.length > 1000000) {
  console.error(`  FEHLER: ${kb(inhalt.length)} — der Supabase-SQL-Editor nimmt höchstens 1 MB.`)
  process.exit(1)
}
