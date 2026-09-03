#!/usr/bin/env bash
# =====================================================================
# Die Kette in beide Richtungen, zweiter Teil: Was die App geschrieben hat
# (pruefstand/kette_erfasst.json, aus kette.mjs), wird in eine echte Postgres
# eingespielt — Spalte für Spalte, so wie die App es schickt. Danach wird
# geprüft, dass jeder eingegebene Wert in der Auswertung ankommt.
#
# Das fängt zwei Fehlerarten, die sonst niemand sieht: eine Spalte, die die
# App schreibt und die Datenbank nicht kennt (der Bildschirm-Prüfstand nimmt
# jedes POST an), und einen Wert, der gespeichert wird und unterwegs zur
# Auswertung verschwindet (die häufigste Fehlerart dieses Projekts).
#
#   node pruefstand/kette.mjs && ./pruefstand/kette_pruefen.sh 'postgresql://…'
# =====================================================================
set -euo pipefail
URL="${1:-postgresql://postgres@/postgres?host=/tmp&port=55432}"
HIER="$(cd "$(dirname "$0")" && pwd)"
ERFASST="$HIER/kette_erfasst.json"
[ -f "$ERFASST" ] || { echo "kette_erfasst.json fehlt — zuerst node pruefstand/kette.mjs"; exit 1; }

# Frische Datenbank wie im Betrieb: setup.sql, ein Arbeiter, ein paar Paletten.
psql "$URL" -v ON_ERROR_STOP=1 -q -c "set client_min_messages = warning;
   drop schema if exists public cascade;  create schema public;
   drop schema if exists auth cascade;    drop schema if exists storage cascade;"
psql "$URL" -v ON_ERROR_STOP=1 -q -f "$HIER/../supabase/test/stub_supabase.sql"
psql "$URL" -v ON_ERROR_STOP=1 -q -1 -f "$HIER/../supabase/setup.sql" >/dev/null
psql "$URL" -v ON_ERROR_STOP=1 -q <<'SQL'
insert into auth.users (id, email, raw_user_meta_data)
values ('22222222-2222-2222-2222-222222222222', null, '{"name":"Tomasz"}');
insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
select 1613, date '2026-09-01' + (i % 4), 950, 40, 'G2', 'kette-' || i from generate_series(1, 12) i;
SQL

# Die Anfragen der Reihe nach einspielen. Die App kennt die Ids, die unser
# Prüfstand ihr gegeben hat (90001 …); hier werden sie auf die echten Ids
# abgebildet, sobald eine Tabelle sie vergibt.
node - "$URL" "$ERFASST" <<'JS'
const { execFileSync } = require('node:child_process')
const [url, datei] = process.argv.slice(2)
const protokoll = JSON.parse(require('node:fs').readFileSync(datei, 'utf8'))
const ids = {}               // fake-id → echte id
const wert = v => v === null ? 'null'
  : typeof v === 'number' ? String(v)
  : typeof v === 'boolean' ? String(v)
  : `'${String(v).replace(/'/g, "''")}'`
const sql = q => execFileSync('psql', [url, '-v', 'ON_ERROR_STOP=1', '-qtA', '-c',
  "set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222'; " + q],
  { encoding: 'utf8' }).trim()

for (const p of protokoll) {
  for (const z of p.zeilen ?? [{}]) {
    const { id: fakeId, ts: _ts, ...felder } = z
    for (const k of Object.keys(felder)) {
      if (/_id$/.test(k) && felder[k] in ids) felder[k] = ids[felder[k]]
    }
    if (p.methode === 'POST') {
      const spalten = Object.keys(felder)
      const konflikt = /ignore-duplicates/.test(p.prefer ?? '')
        ? ` on conflict (${p.filter.on_conflict}) do nothing` : ''
      const ruecklauf = spalten.length && !konflikt ? ' returning id' : ''
      const q = `insert into ${p.tabelle} (${spalten.join(', ')}) values (${spalten.map(k => wert(felder[k])).join(', ')})${konflikt}${ruecklauf}`
      const erg = sql(q)
      if (ruecklauf && erg) ids[fakeId] = Number(erg)
      console.log(`   ${p.tabelle}: eingespielt${ruecklauf ? ` (id ${erg})` : ''}`)
    } else if (p.methode === 'PATCH') {
      const id = ids[Number(String(p.filter.id).replace('eq.', ''))]
      const setzt = Object.keys(felder).map(k => `${k} = ${wert(felder[k])}`).join(', ')
      sql(`update ${p.tabelle} set ${setzt} where id = ${id}`)
      console.log(`   ${p.tabelle}: geändert (id ${id})`)
    }
  }
}
require('node:fs').writeFileSync('/tmp/kette_ids.json', JSON.stringify(ids))
JS

AUFTRAG="$(node -e "const m=require('/tmp/kette_ids.json'); console.log(m[90002])")"
psql "$URL" -qtA -c "select auswertung_aktualisieren()" >/dev/null

# Und jetzt rückwärts: kommt jeder Wert an?
psql "$URL" -v ON_ERROR_STOP=1 -v auftrag="$AUFTRAG" <<'SQL'
select set_config('kette.auftrag', :'auftrag', false);
do $$
declare a bigint := current_setting('kette.auftrag')::bigint; v numeric; v_txt text; v_n int;
begin
  -- Der Auftrag samt Käufer und festgehaltener Fassung
  assert (select kaeufer from auftrag where id = a) = 'coop', 'Käufer nicht angekommen';
  assert (select sortierschema_id from auftrag where id = a) is not null, 'Sortierschema nicht festgehalten';
  assert (select status from auftrag where id = a) = 'abgeschlossen', 'Abschluss nicht angekommen';
  assert exists (select 1 from kaeufer where code = 'coop'), 'Der neue Käufer wurde nicht angelegt';

  -- Drei Paletten, eine davon gewogen und verbunden
  select count(*) into v_n from auftrag_palette where auftrag_id = a;
  assert v_n = 3, format('3 Paletten gezählt, %s angekommen', v_n);
  assert (select count(*) from auftrag_palette where auftrag_id = a and wiegung_id is not null) = 1,
    'Die gewogene Palette ist nicht mit ihrer Wägung verbunden';
  assert (select verwendbar from v_verdunstung_messung where auftrag_id = a),
    'Die Wägung zählt nicht in die Verdunstungsrate';
  assert (select rate_pro_tag from v_verdunstung_messung where auftrag_id = a) > 0,
    'Die Verdunstungsrate ist nicht berechnet';
  assert (select kg_pro_kuerbis from v_wiegung_kennzahl where auftrag_id = a) is not null,
    'Kürbisse je Kiste sind nicht angekommen';

  -- Palox: 165 auf der Waage, 45 Behälter → 120 kg, aus dem Stand abgeleitet
  select kg into v from v_schimmel_menge where auftrag_id = a;
  assert v = 120, format('Schimmelmenge erwartet 120 (165 − 45), ist %s', v);
  assert (select schimmel_kg from v_schimmel_punkte where auftrag_id = a) = 120,
    'Der Schimmel kommt nicht als Punkt im Modell an';
  assert (select quelle from v_schimmel_punkte where auftrag_id = a) = 'verarbeitung',
    'Eine Arbeit aus einer Charge gehört ins Zeitmodell';
  assert (select eingang_netto_kg from v_auftrag_masse where auftrag_id = a) = 3 * 865,
    'Die Bezugsmasse der drei Paletten stimmt nicht (3 × 865)';

  -- Zu klein wurde gewogen (Brutto 100, 4 Kisten G2: 100 − 4·1.5 − 25 = 69),
  -- zu gross geschätzt (15). Das Netto rechnet der Auslöser.
  select klein_kg, gross_kg into v, v_txt from v_ausschuss_beobachtung where auftrag_id = a;
  assert v = 69 and v_txt::numeric = 15, format('Ausschuss erwartet 69/15, ist %s/%s', v, v_txt);
  -- Gewogen hat ein Brutto, geschätzt nicht; beide zählen als Messwert.
  assert (select brutto_kg from ausschuss_messung where auftrag_id = a and art = 'zu_klein') = 100,
    'Der gewogene Ausschuss muss sein Brutto behalten';
  assert (select brutto_kg from ausschuss_messung where auftrag_id = a and art = 'zu_gross') is null,
    'Der geschätzte Ausschuss hat kein Brutto';
  assert (select mittel from v_koeff_ausschuss where sorte = 'Tiana') > 0,
    'Der Ausschuss-Koeffizient ist nicht beziffert';

  -- Die Antwort
  assert (select wert from v_auftrag_angabe where auftrag_id = a and schluessel = 'eine_charge') = 'true',
    'Die Antwort „alles aus einer Charge" ist nicht angekommen';

  -- Nichts blieb ohne Nenner, nichts wurde als unplausibel aussortiert
  assert not exists (select 1 from v_plausibilitaet where auftrag_id = a),
    'Die Arbeit taucht in der Plausibilität auf — etwas fehlt oder wirkt vertippt';

  -- Und ganz oben: die Ströme sind beziffert, keiner unbekannt
  assert (select count(*) from v_verlust_ranking where kg is null and buch in ('verlust', 'marge')) = 0,
    'Ein Strom ist noch unbekannt, obwohl alles erfasst wurde';
  assert (select kg from v_verlust_ranking where strom = 'Verdunstung') > 0, 'Verdunstung nicht beziffert';
  assert (select kg from v_verlust_ranking where strom = 'Schimmel/Fäulnis') > 0, 'Schimmel nicht beziffert';
  assert (select kg from v_verlust_ranking where strom = 'Zu klein (Tierfutter)') > 0, 'Zu klein nicht beziffert';
  raise notice 'OK  Die Kette hält: jeder Wert aus den Masken kommt in der Auswertung an';
end $$;
SQL
echo "——— Kette in beide Richtungen geprüft ———"
