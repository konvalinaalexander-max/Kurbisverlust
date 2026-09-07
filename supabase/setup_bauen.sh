#!/usr/bin/env bash
# Fügt die Migrationen zu supabase/setup.sql zusammen — der einen Datei, die
# der Nutzer im Supabase-SQL-Editor einfügt. Nach jeder Änderung an
# supabase/migrations/ hier neu laufen lassen; die CI prüft, dass beides
# zusammenpasst.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
ZIEL="$HIER/setup.sql"

{
cat <<'KOPF'
-- =====================================================================
-- Kürbis-Verlust-Tracking — das komplette Setup in einer Datei
--
-- ERZEUGT. Nicht von Hand ändern — Quelle ist supabase/migrations/*.sql,
-- zusammengefügt von supabase/setup_bauen.sh.
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
-- =====================================================================
KOPF

for f in "$HIER"/migrations/*.sql; do
  printf '\n\n-- =====================================================================\n'
  printf -- '-- aus %s\n' "$(basename "$f")"
  printf -- '-- =====================================================================\n\n'
  cat "$f"
done

cat <<'FUSS'


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
-- setup.sql ist die ganze Geschichte der Datenbank; jede Zwischenfassung
-- einer Formel auf den echten Daten auszurechnen hiesse, dass ein längst
-- korrigierter Rechenfehler eine Aktualisierung für immer blockiert. Genau
-- das ist am 7. September passiert (numeric field overflow, 0056): die
-- Korrektur stand am Ende der Datei, der Abbruch kam in der Mitte.
-- Gerechnet wird deshalb einmal, mit den heutigen Formeln. Geht das schief,
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
select format('Fertig. Die Datenbank steht: %s Chargen, %s Sorten, %s Tabellen, %s Auswertungen. %s Weiter im README bei Schritt 4.',
              (select count(*) from charge),
              (select count(*) from sorte_kaliber),
              (select count(*) from pg_tables where schemaname = 'public'),
              (select count(*) from pg_views  where schemaname = 'public'),
              coalesce(nullif(current_setting('kuerbis.auswertung', true), ''), 'Auswertung nicht gerechnet.')) as ergebnis;
FUSS
} > "$ZIEL"

echo "supabase/setup.sql geschrieben — $(wc -l < "$ZIEL") Zeilen, $(( $(wc -c < "$ZIEL") / 1024 )) KB"
