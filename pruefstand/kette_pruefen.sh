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
update profil set aktiv = true where id = '22222222-2222-2222-2222-222222222222';
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
const auftraege = []         // echte Ids der Arbeiten, der Reihe nach
const wert = v => v === null ? 'null'
  : typeof v === 'number' ? String(v)
  : typeof v === 'boolean' ? String(v)
  : `'${String(v).replace(/'/g, "''")}'`
const sql = q => execFileSync('psql', [url, '-v', 'ON_ERROR_STOP=1', '-qtA', '-c',
  "set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222'; " + q],
  { encoding: 'utf8' }).trim()

for (const p of protokoll) {
  if (p.methode === 'RPC') {
    // Die Fassung festlegen (0051): dieselben Argumente wie aus der App, die
    // echte Funktion, und ihre Id wird wie eine Einfügung abgebildet.
    const a = p.args ?? {}
    const q = `select ${p.tabelle}(p_sorte => ${wert(a.p_sorte)}, p_kaeufer => ${wert(a.p_kaeufer ?? null)}, `
      + `p_art => ${wert(a.p_art)}, p_baender => ${a.p_baender == null ? 'null' : wert(JSON.stringify(a.p_baender)) + '::jsonb'}, `
      + `p_soll => ${a.p_soll == null ? 'null' : wert(a.p_soll)}, p_bemerkung => ${wert(a.p_bemerkung ?? null)})`
    const erg = sql(q)
    ids[p.zeilen[0].id] = Number(erg)
    console.log(`   ${p.tabelle}: gerufen (Fassung ${erg})`)
    continue
  }
  for (const z of p.zeilen ?? [{}]) {
    const { id: fakeId, ts: _ts, ...felder } = z
    for (const k of Object.keys(felder)) {
      if (/_id$/.test(k) && felder[k] in ids) felder[k] = ids[felder[k]]
    }
    if (p.methode === 'POST') {
      const spalten = Object.keys(felder)
      // PostgREST-Upsert: ignore-duplicates → do nothing, merge-duplicates → do update
      const schluessel = String(p.filter?.on_conflict ?? '').split(',').map(k => k.trim()).filter(Boolean)
      const rest = spalten.filter(k => !schluessel.includes(k))
      const konflikt = /ignore-duplicates/.test(p.prefer ?? '')
        ? ` on conflict (${schluessel.join(', ')}) do nothing`
        : /merge-duplicates/.test(p.prefer ?? '') && schluessel.length
          ? ` on conflict (${schluessel.join(', ')}) do update set ${rest.length ? rest.map(k => `${k} = excluded.${k}`).join(', ') : `${schluessel[0]} = excluded.${schluessel[0]}`}`
          : ''
      const ruecklauf = spalten.length && !/do nothing/.test(konflikt) ? ' returning id' : ''
      const q = `insert into ${p.tabelle} (${spalten.join(', ')}) values (${spalten.map(k => wert(felder[k])).join(', ')})${konflikt}${ruecklauf}`
      const erg = sql(q)
      if (ruecklauf && erg) ids[fakeId] = Number(erg)
      if (p.tabelle === 'auftrag' && erg) auftraege.push(Number(erg))
      console.log(`   ${p.tabelle}: eingespielt${ruecklauf ? ` (id ${erg})` : ''}`)
    } else if (p.methode === 'PATCH') {
      const id = ids[Number(String(p.filter.id).replace('eq.', ''))]
      const setzt = Object.keys(felder).map(k => `${k} = ${wert(felder[k])}`).join(', ')
      sql(`update ${p.tabelle} set ${setzt} where id = ${id}`)
      console.log(`   ${p.tabelle}: geändert (id ${id})`)
    }
  }
}
require('node:fs').writeFileSync('/tmp/kette_ids.json', JSON.stringify({ ids, auftraege }))
JS

AUFTRAG="$(node -e "const m=require('/tmp/kette_ids.json'); console.log(m.auftraege[0])")"
psql "$URL" -qtA -c "select auswertung_aktualisieren()" >/dev/null

# Und jetzt rückwärts: kommt jeder Wert an?
psql "$URL" -v ON_ERROR_STOP=1 -v auftrag="$AUFTRAG" <<'SQL'
select set_config('kette.auftrag', :'auftrag', false);
do $$
declare a bigint := current_setting('kette.auftrag')::bigint; v numeric; v_txt text; v_n int;
begin
  -- Der Auftrag: kein Käufer mehr, dafür das Kistensystem und die Fassung (0060)
  assert (select kaeufer from auftrag where id = a) is null, 'Der Käufer wird nicht mehr gefragt';
  assert (select kistensystem from auftrag where id = a) = 'kiste_ab'
     and (select soll_kg_pro_kiste from auftrag where id = a) = 8, 'Kistensystem „Kiste ab 8 kg" nicht angekommen';
  assert (select sortierschema_id from auftrag where id = a) is not null, 'Sortierschema nicht festgehalten';
  assert (select status from auftrag where id = a) = 'abgeschlossen', 'Abschluss nicht angekommen';

  -- Drei Paletten: zwei mit Gewicht vom Zettel, eine gewogen und verbunden
  select count(*) into v_n from auftrag_palette where auftrag_id = a;
  assert v_n = 3, format('3 Paletten gezählt, %s angekommen', v_n);
  assert (select count(*) from auftrag_palette where auftrag_id = a and brutto_zettel_kg = 950) = 3,
    'Das Gewicht vom Zettel (950) muss an allen drei Paletten stehen — auch an der gewogenen';
  assert (select count(*) from auftrag_palette where auftrag_id = a and wiegung_id is not null) = 1,
    'Die gewogene Palette ist nicht mit ihrer Wägung verbunden';
  assert (select count(*) from v_auftrag_palette_masse where auftrag_id = a and masse_quelle = 'zettel') = 2,
    'Die Zettelgewichte finden ihre Palette im Wareneingang (Quelle „zettel")';
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
    'Die Bezugsmasse der drei Paletten stimmt nicht (3 × 865: Zettel 950 − 40·1.5 − 25)';

  -- Kein zu klein / zu gross mehr (0060): nichts gewogen, nichts gefragt
  assert not exists (select 1 from ausschuss_messung where auftrag_id = a), 'Ausschuss wird nicht mehr erfasst';
  assert not exists (select 1 from v_auftrag_angabe where auftrag_id = a and schluessel like 'ausschuss%'),
    'Die Ausschuss-Fragen gibt es nicht mehr';
  assert (select wert from v_auftrag_angabe where auftrag_id = a and schluessel = 'eine_charge') = 'true',
    'Die Antwort „alles aus einer Charge" ist nicht angekommen';

  -- Nichts blieb ohne Nenner, nichts wurde als unplausibel aussortiert
  assert not exists (select 1 from v_plausibilitaet where auftrag_id = a),
    'Die Arbeit taucht in der Plausibilität auf — etwas fehlt oder wirkt vertippt';

  -- Die Fassung wurde beim Eröffnen festgelegt: „Kiste ab x kg", Soll 8 kg, ohne Käufer
  assert (select art from sortierschema where id = (select sortierschema_id from auftrag where id = a)) = 'kiste',
    'Die Arbeit lief als „Kiste ab x kg" — die Fassung muss das sagen';
  assert (select kaeufer from sortierschema where id = (select sortierschema_id from auftrag where id = a)) is null,
    'Die Fassung hängt an der Sorte, nicht an einem Käufer';
  -- Die fertige Palette (345 brutto, 32 G2: 345 − 48 − 25 = 272 → 8.5 kg je Kiste), Soll aus der Arbeit
  assert (select kg_pro_kiste from v_ausgang_kennzahl where auftrag_id = a) = 8.5,
    'Die fertige Palette ergibt 8.5 kg je Kiste';
  assert (select ueberfuellung_je_kiste from v_ausgang_kennzahl where auftrag_id = a) = 0.5,
    'Überfüllung: 0.5 kg je Kiste über dem Soll von 8 (aus der Arbeit)';
  assert (select kistensystem from v_ausgang_kennzahl where auftrag_id = a) = 'kiste_ab', 'Kistensystem an der Wägung';
  assert (select kg_je_gebinde from v_koeff_gebinde where sorte = 'Tiana' and kaliber_idx = -1) = 8.5,
    'Aus der fertigen Palette folgt das Kistengewicht ohne Kaliber (0051)';
  assert (select netto_kg from v_koeff_palette_netto where sorte = 'Tiana' and kistensystem = 'kiste_ab') = 272,
    'Die Palettenmasse je Sorte und Kistensystem ist 272 kg';

  -- Die Sortier-Arbeit lief mit angepassten Bändern: zweite Grenze 900 statt 800,
  -- als neue Fassung von heute — die alte blieb stehen. Zwei Kisten Kaliber 1 gezählt.
  assert exists (select 1 from auftrag x join sortierschema s on s.id = x.sortierschema_id
                  where x.station = 'sortieren' and s.gilt_ab = current_date
                    and (s.kaliber_baender -> 0 ->> 1)::int = 900),
    'Die angepassten Bänder müssen als Fassung von heute an der Sortier-Arbeit hängen';
  assert (select count(*) from sortierschema where sorte = 'Tiana' and art = 'kaliber') >= 2,
    'Die alte Fassung darf nicht überschrieben worden sein';
  assert (select sum(anzahl) from auftrag_gebinde g join auftrag x on x.id = g.auftrag_id
           where x.station = 'sortieren' and g.kaliber_idx = 0) = 2,
    'Zwei Kisten Kaliber 1 beim Sortieren gezählt';

  -- Und ganz oben: die echten Verlustströme sind beziffert
  assert (select kg from v_verlust_ranking where strom = 'Verdunstung') > 0, 'Verdunstung nicht beziffert';
  assert (select kg from v_verlust_ranking where strom = 'Schimmel/Fäulnis') > 0, 'Schimmel nicht beziffert';
  raise notice 'OK  Die Kette hält: jeder Wert aus den Masken kommt in der Auswertung an';
end $$;

-- ---------- Der Fax-Durchlauf (0051, 0060) ---------------------------------
do $$
declare f record;
begin
  select * into f from v_fax_beobachtung
   where auftrag_id = (select max(id) from auftrag where ist_fax);
  assert f.auftrag_id is not null, 'Die Fax-Arbeit ist nicht angekommen';
  assert f.status = 'abgeschlossen', 'Der Fax-Abschluss ist nicht angekommen';
  assert f.kaeufer is null, 'Der Käufer wird beim Fax nicht mehr gefragt';
  assert f.kistensystem = 'kiste_ab', 'Das Kistensystem der Fax-Arbeit fehlt';
  assert f.paletten_gesamt = 2, format('2 Paletten als Gesamtzahl erwartet, angekommen %s', f.paletten_gesamt);
  assert f.tage_seit_waschen = 2, 'Die Tage seit dem Waschen sind nicht angekommen';
  assert f.masse_quelle = 'fax_paletten', format('Die Fax-Masse kommt aus den Paletten, Quelle ist „%s"', f.masse_quelle);
  assert f.masse_kg = 2 * 272, format('Fax-Masse 2 × 272 (gemessene Palettenmasse) erwartet, ist %s', f.masse_kg);
  assert f.faul_kg = 6, format('Faules 7.5 − 1.5 = 6 kg erwartet, ist %s', f.faul_kg);
  assert f.faul_erfasst, 'Das Faule gilt nicht als erfasst';
  assert (select gewaschen_kg from v_hochrechnung_basis where charge_nr = 1613) = 0,
    'Fax zählt nicht als Waschen';
  assert not exists (select 1 from v_schimmel_punkte where auftrag_id = f.auftrag_id),
    'Fax-Faules darf kein Punkt der Verderbskurve sein';
  assert (select kg from v_verlust_ranking where strom = 'Faul beim Abpacken (Fax)') > 0,
    'Der Fax-Strom ist nicht beziffert';
  assert not exists (select 1 from v_plausibilitaet where auftrag_id = f.auftrag_id),
    'Die Fax-Arbeit taucht in der Plausibilität auf';
  raise notice 'OK  Fax: Paletten gesamt, Faules gewogen, Tage seit dem Waschen, eigener Strom';
end $$;

-- ---------- Der Wasch-Durchlauf mit eigenem Kaliber (0054, 0060) -----------
do $$
declare a record;
begin
  select * into a from auftrag where station = 'waschen' and not ist_fax order by id desc limit 1;
  assert a.id is not null, 'Die Wasch-Arbeit ist nicht angekommen';
  assert a.kaliber_von_g = 700 and a.kaliber_bis_g = 900 and a.kaliber_idx is null,
    format('Eigenes Kaliber 700–900 erwartet, angekommen %s–%s (Index %s)', a.kaliber_von_g, a.kaliber_bis_g, a.kaliber_idx);
  assert a.kistensystem = 'stueck' and a.stueck_je_kiste = 6, 'Stück-Kisten (6 je Kiste) nicht angekommen';
  assert (select sum(anzahl) from auftrag_gebinde where auftrag_id = a.id and kaliber_idx = -2) = 4,
    'Vier Kisten zum eigenen Kaliber (Index −2) erwartet';
  assert (select anzahl from auftrag_gebinde where auftrag_id = a.id and sortierdatum = date '2026-11-15') = 3,
    'Drei Kisten mit Sortierdatum 15.11.';
  assert (select anzahl from auftrag_gebinde where auftrag_id = a.id and sortierdatum is null and datum_fehlt) = 1,
    'Eine Kiste ohne Datum — als Antwort, nicht als Lücke';
  assert (select anzahl from v_auftrag_gebinde_masse where auftrag_id = a.id) = 4,
    'Die Kisten werden über die Sortierdaten summiert';
  assert (select kaliber_idx from ausgang_wiegung where auftrag_id = a.id) = -2
     and (select kuerbisse_pro_kiste from ausgang_wiegung where auftrag_id = a.id) = 6,
    'Die fertige Palette trägt Kaliber und Stück je Kiste';
  assert not exists (select 1 from schimmel_messung where auftrag_id = a.id),
    'Der Palox war beim Waschen freiwillig und wurde nicht abgelesen';
  assert a.status = 'abgeschlossen', 'Der Abschluss der Wasch-Arbeit ist nicht angekommen — ohne Palox muss er gehen';
  assert not exists (select 1 from v_plausibilitaet where auftrag_id = a.id and art = 'Kaliber fehlt'),
    'Ein eigenes Kaliber gilt als Kaliber — „Kaliber fehlt" darf nicht auffallen';
  assert exists (select 1 from v_plausibilitaet where auftrag_id = a.id and art = 'Kistengewicht'
                    and befund like '%eigenen Kaliber 700–900 g%'),
    'Das Kistengewicht zum eigenen Kaliber ist unbekannt — das muss die Plausibilität sagen';
  assert (select eingang_netto_kg from v_auftrag_masse where auftrag_id = a.id) is null,
    'Ohne Kistengewicht darf die Arbeit keine Masse behaupten';
  raise notice 'OK  Waschen: eigenes Kaliber, Stück-Kisten, Sortierdatum je Kiste, Palox freiwillig';
end $$;

-- ---------- Die Lagerkontrolle (0060) -------------------------------------
do $$
declare v_n int;
begin
  select count(*) into v_n from verdunstung_wiegung
   where auftrag_id is null and charge_nr = 1613 and faul_kg = 0 and auswahl = 'erreichbar_zufaellig'
     and brutto_damals_kg = 950 and brutto_jetzt_kg = 905 and eingangsdatum = date '2026-09-02';
  assert v_n = 2, format('Zwei Kontrollen mit Zettel-Datum und -Gewicht erwartet, %s angekommen', v_n);
  assert (select lagerkontrollen from v_datenqualitaet) >= 2, 'Die Datenqualität zählt die Kontrollen';
  assert (select count(*) from v_schimmel_punkte where quelle = 'lager') >= 2,
    'Die Kontrollen sind Punkte der Kurve — mit 0 kg Faulem als echter Messung';
  raise notice 'OK  Kontrolle: bleibt stehen, Zettel-Datum und -Gewicht, zwei Paletten';
end $$;
SQL
echo "——— Kette in beide Richtungen geprüft ———"
