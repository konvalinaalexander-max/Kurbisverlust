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
--   3. In das große leere Feld einfügen (Strg+V).
--   4. Unten rechts auf "Run" klicken.
-- Das war alles. Kein zweiter Durchlauf, keine weitere Datei.
--
-- Unten im Ergebnisfenster muss danach eine Zeile stehen, die mit
-- "Fertig." beginnt und die Anzahl Chargen und Sorten nennt.
-- =====================================================================

-- Schutz vor dem versehentlichen zweiten Durchlauf: Das gesamte Skript
-- läuft in einer Transaktion, ein Abbruch hier ändert also gar nichts.
do $$
begin
  if to_regclass('public.charge') is not null then
    raise exception E'Das Setup wurde bereits eingespielt — es ist nichts zu tun.\n'
      'Es hat sich nichts geändert. Weiter geht es im README bei Schritt 3.';
  end if;
end $$;

KOPF

for f in "$HIER"/migrations/*.sql; do
  printf '\n\n-- =====================================================================\n'
  printf -- '-- aus %s\n' "$(basename "$f")"
  printf -- '-- =====================================================================\n\n'
  cat "$f"
done

cat <<'FUSS'


-- =====================================================================
-- Rückmeldung im Ergebnisfenster
-- =====================================================================
select format('Fertig. %s Chargen und %s Sorten angelegt, %s Tabellen und %s Auswertungen erstellt. Weiter im README bei Schritt 4.',
              (select count(*) from charge),
              (select count(*) from sorte_kaliber),
              (select count(*) from pg_tables where schemaname = 'public'),
              (select count(*) from pg_views  where schemaname = 'public')) as ergebnis;
FUSS
} > "$ZIEL"

echo "supabase/setup.sql geschrieben — $(wc -l < "$ZIEL") Zeilen, $(( $(wc -c < "$ZIEL") / 1024 )) KB"
