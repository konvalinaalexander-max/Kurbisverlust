#!/usr/bin/env bash
# Eine frische Demo-Datenbank aufbauen: Schema aus den Migrationen, drei
# Konten, die Demo-Saison laden und einmal durchrechnen.
#
# Gebraucht wird sie von den Browser-Prüfständen: bildschirme.mjs und
# beschriftung.mjs spielen der App echte Antworten vor, und die kommen aus
# pruefstand/daten — dort abgelegt von daten_dumpen.sh, das genau diese
# Datenbank liest. Ohne dieses Skript wusste nur, wer dabei war, wie man
# dahin kommt; in der CI konnte es niemand.
#
#   ./pruefstand/demo_bauen.sh 'postgresql://…' && ./pruefstand/daten_dumpen.sh 'postgresql://…'
set -euo pipefail
U="${1:-postgresql://postgres@/demo?host=/tmp/pgsock&port=55432}"
HIER="$(cd "$(dirname "$0")" && pwd)"
WURZEL="$HIER/.."

psql "$U" -v ON_ERROR_STOP=1 -q -c "
  set client_min_messages = warning;
  drop schema if exists public cascade;  create schema public;
  drop schema if exists auth cascade;    drop schema if exists storage cascade;"
# Die Teile, die auf Supabase die Plattform stellt (auth, storage, auth.uid()).
psql "$U" -v ON_ERROR_STOP=1 -q -f "$WURZEL/supabase/test/stub_supabase.sql"

for f in "$WURZEL"/supabase/migrations/*.sql; do
  psql "$U" -v ON_ERROR_STOP=1 -q -f "$f" >/dev/null 2>&1 \
    || { echo "FEHLER in $(basename "$f"):"; psql "$U" -q -f "$f" 2>&1 | grep -i error | head -3; exit 1; }
done

# Ein Betriebsleiter und zwei Arbeiter — die Rollen, die die Masken kennen.
psql "$U" -v ON_ERROR_STOP=1 -q -c "
  insert into auth.users (id, email, raw_user_meta_data) values
    ('11111111-1111-1111-1111-111111111111', 'chef@hof.test', '{\"name\":\"Alexander\"}'),
    ('22222222-2222-2222-2222-222222222222', null, '{\"name\":\"Tomasz\"}'),
    ('33333333-3333-3333-3333-333333333333', null, '{\"name\":\"Ildikó\"}');
  update profil set rolle = 'admin' where id = '11111111-1111-1111-1111-111111111111';
  update profil set aktiv = true;"

psql "$U" -v ON_ERROR_STOP=1 -qtA -c "select demo_daten_laden()" >/dev/null
# Seit 0055 rechnet demo_daten_laden() nicht mehr selbst — wie die App: eigener Aufruf.
psql "$U" -v ON_ERROR_STOP=1 -qtA -c "select auswertung_aktualisieren()" >/dev/null

echo "Demo-Datenbank steht: Schema $(psql "$U" -qtAc 'select schema_stand()'), \
$(psql "$U" -qtAc 'select count(*) from charge') Chargen, \
$(psql "$U" -qtAc 'select count(*) from palette') Paletten."
