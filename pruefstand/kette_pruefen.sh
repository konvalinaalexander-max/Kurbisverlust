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

  -- Zu klein / zu gross je Palette am Ende (0061): 60 brutto, 4 G2 → 60 − 6 − 25 = 29 kg, gemessen
  assert (select count(*) from ausschuss_messung where auftrag_id = a) = 1, 'Eine Ausschuss-Palette gewogen';
  assert (select kg from ausschuss_messung where auftrag_id = a and art = 'zu_klein' and gemessen and brutto_kg = 60 and kisten = 4) = 29,
    'Der Ausschuss-Auslöser rechnet das Netto aus Brutto und Tara (29 kg)';
  assert (select klein_kg from v_ausschuss_beobachtung where auftrag_id = a and weg = 'hand') = 29,
    'Der von Hand gewogene Ausschuss kommt nicht als Beobachtung an';
  assert not exists (select 1 from v_auftrag_angabe where auftrag_id = a and schluessel like 'ausschuss%'),
    'Die Ausschuss-Fragen gibt es nicht mehr';
  -- Die Wägung ohne Faul-Frage (0061): faul_kg bleibt leer, die Wägung zählt trotzdem
  assert (select faul_kg is null and not sichtbar_schimmel from verdunstung_wiegung where auftrag_id = a),
    'Beim Wiegen wird nicht mehr nach Faulem gefragt';
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
  -- Seit 0061 wird das Fax-Faule am Liefertag gebucht (AB-31). In dieser Kette
  -- gibt es keine Lieferung: Es steht also nichts als Verlust bis heute da,
  -- sondern als Erwartung an der Ware, die noch liegt — und die gemessenen
  -- 6 kg bestimmen den Koeffizienten dahinter.
  assert (select kg from v_verlust_ranking where strom = 'Faul beim Abpacken (Fax)') is null,
    'Ohne Lieferung darf Fax-Faules kein Verlust bis heute sein';
  assert (select kg_erwartet from v_verlust_ranking where strom = 'Faul beim Abpacken (Fax)') > 0,
    'Das erwartete Fax-Faule der liegenden Ware fehlt';
  assert (select max(mittel) from v_koeff_fax) > 0,
    'Die gemessenen 6 kg bestimmen den Fax-Koeffizienten nicht';
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
  -- Kaliber-Paletten aus dem Zwischenlager (0061): drei mit je 32 Kisten, zwei datiert, eine ohne Datum
  assert not exists (select 1 from auftrag_gebinde where auftrag_id = a.id), 'Beim Waschen werden keine Kisten je Kaliber mehr gezählt';
  assert (select count(*) from auftrag_palette where auftrag_id = a.id and kisten is not null) = 3
     and (select sum(kisten) from auftrag_palette where auftrag_id = a.id) = 96,
    'Drei Paletten mit 96 Kisten erwartet';
  assert (select count(*) from auftrag_palette where auftrag_id = a.id and sortierdatum = date '2026-09-03') = 2,
    'Zwei Paletten mit Sortierdatum 3.9.';
  assert (select count(*) from auftrag_palette where auftrag_id = a.id and sortierdatum is null and kisten = 32) = 1,
    'Eine Palette ohne Datum — als Antwort, nicht als Lücke';
  assert (select count(*) from auftrag_palette where auftrag_id = a.id and eingangsdatum is not null) = 0,
    'Kaliber-Paletten haben kein Eingangsdatum';
  assert (select n_paletten = 3 and kisten = 96 and n_mit_sortierdatum = 2 from v_auftrag_wasch_paletten where auftrag_id = a.id),
    'Die Wasch-Paletten kommen nicht als Menge an';
  assert (select zwischenlager_tage from v_auftrag_wasch_paletten where auftrag_id = a.id) = (current_date - date '2026-09-03'),
    format('Die Tage im Zwischenlager sind %s statt %s', (select zwischenlager_tage from v_auftrag_wasch_paletten where auftrag_id = a.id), current_date - date '2026-09-03');
  assert not exists (select 1 from v_auftrag_palette_masse where auftrag_id = a.id),
    'Kaliber-Paletten dürfen nicht als Eingangspaletten zählen';
  -- Drei fertige Paletten (verlangt beim Waschen, Runde H), je mit Kaliber und Stück je Kiste
  assert (select count(*) from ausgang_wiegung where auftrag_id = a.id and kaliber_idx = -2 and kuerbisse_pro_kiste = 6) = 3,
    'Drei fertige Paletten mit Kaliber und Stück je Kiste erwartet';
  assert not exists (select 1 from schimmel_messung where auftrag_id = a.id),
    'Der Palox war beim Waschen freiwillig und wurde nicht abgelesen';
  assert a.status = 'abgeschlossen', 'Der Abschluss der Wasch-Arbeit ist nicht angekommen — ohne Palox muss er gehen';
  assert not exists (select 1 from v_plausibilitaet where auftrag_id = a.id and art = 'Kaliber fehlt'),
    'Ein eigenes Kaliber gilt als Kaliber — „Kaliber fehlt" darf nicht auffallen';
  assert exists (select 1 from v_plausibilitaet where auftrag_id = a.id and art = 'Kistengewicht'
                    and befund like '%700–900 g%' and befund like '%3 Paletten mit 96 Kisten%'),
    'Das Kistengewicht zum eigenen Kaliber ist unbekannt — das muss die Plausibilität an den gezählten Paletten sagen';
  assert (select eingang_netto_kg from v_auftrag_masse where auftrag_id = a.id) is null,
    'Ohne Kistengewicht darf die Arbeit keine Masse behaupten';
  raise notice 'OK  Waschen: eigenes Kaliber, Kaliber-Paletten mit Sortierdatum und Kisten, drei fertige Paletten, Palox freiwillig';
end $$;

-- ---------- Die Lagerkontrolle (0061) -------------------------------------
-- Ohne Faul-Frage und ohne „wie gegriffen": die Kontrolle ist eine
-- Verdunstungsmessung — und nur das. Punkt der Schimmelkurve ist sie nicht
-- mehr (das Faule sieht beim Wiegen niemand).
do $$
declare v_n int;
begin
  select count(*) into v_n from verdunstung_wiegung
   where auftrag_id is null and charge_nr = 1613 and faul_kg is null and auswahl is null
     and brutto_damals_kg = 950 and brutto_jetzt_kg = 905 and eingangsdatum = date '2026-09-02';
  assert v_n = 2, format('Zwei Kontrollen mit Zettel-Datum und -Gewicht, ohne Faul und Auswahl erwartet, %s angekommen', v_n);
  assert (select lagerkontrollen from v_datenqualitaet) >= 2, 'Die Datenqualität zählt die Kontrollen';
  assert (select count(*) from v_verdunstung_messung where auftrag_id is null and charge_nr = 1613 and verwendbar) = 2,
    'Die Kontrollen sind Punkte der Verdunstungskurve';
  assert not exists (select 1 from v_schimmel_punkte where quelle = 'lager'),
    'Ohne Faul-Frage darf die Kontrolle kein Punkt der Schimmelkurve sein';
  raise notice 'OK  Kontrolle: bleibt stehen, Zettel-Datum und -Gewicht, zwei Paletten, ohne Faul-Frage';
end $$;
SQL
echo "——— Kette in beide Richtungen geprüft ———"
