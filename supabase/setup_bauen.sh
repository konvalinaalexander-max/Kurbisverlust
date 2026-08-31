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
-- Rückmeldung im Ergebnisfenster
-- =====================================================================
select format('Fertig. Die Datenbank steht: %s Chargen, %s Sorten, %s Tabellen, %s Auswertungen. Weiter im README bei Schritt 4.',
              (select count(*) from charge),
              (select count(*) from sorte_kaliber),
              (select count(*) from pg_tables where schemaname = 'public'),
              (select count(*) from pg_views  where schemaname = 'public')) as ergebnis;
FUSS
} > "$ZIEL"

echo "supabase/setup.sql geschrieben — $(wc -l < "$ZIEL") Zeilen, $(( $(wc -c < "$ZIEL") / 1024 )) KB"
