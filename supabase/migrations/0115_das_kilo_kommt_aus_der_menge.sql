-- 0115 — Das Kilo kommt aus der Menge; was Perigon nicht mehr sagt, ist keine Lieferung mehr
--
-- WARUM
--
-- Beim Prüfen der Perigon-Dateien Zeile für Zeile (15. Oktober, Runde AR):
--
-- 1. Die App rechnete die Masse jeder Position als Menge × „Gewicht je
--    Artikel" (GewichtProArtikel). Im Perigon-Artikelstamm steht bei vielen
--    kg-Artikeln 0 statt 1 — bei Imhof BioProdukte in der Saison 2024/25 fast
--    überall (Butternut, Butterkin, „Kürbis ganz"). Bei einem kg-Artikel ist
--    die Menge aber schon das Gewicht. So zählten im Vergleich je Kunde mit
--    den Vorjahren 86.7 t (2024/25) und 12.1 t (2023/24) als 0 kg — 81.6 t
--    statt mindestens 168.3 t —, und diese Saison wurden 11 Positionen mit
--    340 kg nie eine Lieferung (Mandarin 256 kg am 12.10. darunter).
--    Jetzt (perigon_kg): Gewicht je Artikel > 0 → Menge × Gewicht; sonst bei
--    Einheit kg → die Menge; sonst (Stück ohne Stückgewicht, bei Imhofbio
--    2024/25 12'322 Stück Muscade und Kabocha) → unbekannt, leer — nicht 0.
--    Was schon gespeichert ist, wird hier nachgerechnet; der Vergleich je
--    Kunde zeigt die Stück ohne Gewicht, statt sie wegzulassen.
-- 2. Trug Perigon bei einer Position, die zuerst ohne Charge kam, die Charge
--    später nach, legte das Einlesen eine neue Lieferung an — und die alte
--    „ohne Chargenbezug" blieb stehen: Die Masse zählte doppelt (4 Positionen,
--    520 kg). Jetzt entfernt das Einlesen für jede Position der Datei, was
--    die Datei nicht mehr ergibt.
--
-- Was danach im Betrieb zu tun ist: setup.sql, dann beide Perigon-Dateien
-- einmal neu einlesen — die App legt die fehlenden Lieferungen an und
-- ersetzt die doppelten. Bis dahin stehen sie im Warenausgang als Positionen,
-- die nicht mit den Lieferungen übereinstimmen (v_ausgang_pruef).

-- =====================================================================
-- 1. Die Masse einer Perigon-Menge — eine Regel, wie perigonKg() in der App
-- =====================================================================
create or replace function perigon_kg(p_menge numeric, p_gewicht numeric, p_einheit text) returns numeric
language sql immutable set search_path = public as $$
  select case
           when p_menge is null then null
           when coalesce(p_gewicht, 0) > 0 then round(p_menge * p_gewicht, 3)
           when lower(btrim(coalesce(p_einheit, ''))) like 'kg%' then round(p_menge, 3)
         end
$$;
comment on function perigon_kg(numeric, numeric, text) is
  'Die Masse einer Perigon-Menge in kg (0115): Gewicht je Artikel > 0 → Menge × Gewicht; sonst bei Einheit kg die Menge selbst (der Artikelstamm führt dort oft 0 statt 1); sonst — Stück ohne Stückgewicht — unbekannt (null), nie 0. Dieselbe Regel wie perigonKg() in src/lib/warenausgang.ts.';
revoke all on function perigon_kg(numeric, numeric, text) from public;
grant execute on function perigon_kg(numeric, numeric, text) to authenticated;

-- =====================================================================
-- 2. Was schon gespeichert ist, nachrechnen
-- =====================================================================
-- Nur wo das Gewicht je Artikel fehlt oder 0 ist — sonst bleibt alles, wie es
-- die App beim Einlesen gerechnet hat. Der Ausdruck ist perigon_kg(), hier
-- ausgeschrieben: Diese Anweisungen laufen bei jedem setup.sql an ihrer
-- Stelle in der Geschichte, und dort gibt es die Funktion noch nicht.
update ausgang_zeile
   set kg_position = case when lower(btrim(coalesce(einheit, ''))) like 'kg%' then round(coalesce(menge, 0), 3) end,
       kg_charge   = case when lower(btrim(coalesce(einheit, ''))) like 'kg%' then round(coalesce(batch_menge, 0), 3) end
 where coalesce(gewicht_je_artikel, 0) = 0
   and (kg_position is distinct from case when lower(btrim(coalesce(einheit, ''))) like 'kg%' then round(coalesce(menge, 0), 3) end
        or kg_charge is distinct from case when lower(btrim(coalesce(einheit, ''))) like 'kg%' then round(coalesce(batch_menge, 0), 3) end);

update ausgang_position
   set kg = case when lower(btrim(coalesce(einheit, ''))) like 'kg%' then round(coalesce(menge, 0), 3) end
 where coalesce(gewicht_je_artikel, 0) = 0
   and kg is distinct from case when lower(btrim(coalesce(einheit, ''))) like 'kg%' then round(coalesce(menge, 0), 3) end;

comment on table ausgang_position is
  'Jede Lieferscheinposition der Perigon-Datei, alle Saisons (0112) — einmal je Position, kg nach perigon_kg (0115): Menge × Gewicht je Artikel, bei kg-Artikeln ohne Gewicht die Menge, bei Stück ohne Stückgewicht leer. Nur für den Vergleich je Kunde und Saison; die Bilanz rechnet mit ausgang_zeile und lieferung.';

-- =====================================================================
-- 3. Einlesen: die Masse nach der Regel, und was die Datei nicht mehr ergibt
-- =====================================================================
create or replace function ausgang_historie_uebernehmen(p_quelle text, p_positionen jsonb, p_lose jsonb default '[]'::jsonb)
returns jsonb language plpgsql security invoker set search_path = public as $fn$
declare
  v_pos  int := 0;
  v_lose int := 0;
  v_saisons jsonb;
begin
  if not ist_admin() then
    raise exception 'Den Warenausgang übernimmt nur der Betriebsleiter.';
  end if;
  if not exists (select 1 from ausgang_quelle where code = p_quelle) then
    raise exception 'Die Firma „%" ist noch nicht angelegt — zuerst den Warenausgang übernehmen.', p_quelle;
  end if;

  with eingang as (
    select * from jsonb_to_recordset(coalesce(p_positionen, '[]'::jsonb)) as x(
      pos_id bigint, datum date, journal text, kunde text, artikel_id text, artikel text,
      preisgruppe text, einheit text, menge numeric, gewicht_je_artikel numeric,
      gebindeart text, gebinde_menge numeric)
  ), geschrieben as (
    insert into ausgang_position (quelle, pos_id, datum, saison, journal, kunde, artikel_id, artikel, preisgruppe,
                                  einheit, menge, gewicht_je_artikel, kg, gebindeart, gebinde_menge)
    select p_quelle, e.pos_id, e.datum, saison_von(e.datum), e.journal, e.kunde, e.artikel_id, e.artikel,
           nullif(e.preisgruppe, ''), e.einheit, e.menge, e.gewicht_je_artikel,
           perigon_kg(coalesce(e.menge, 0), e.gewicht_je_artikel, e.einheit), nullif(e.gebindeart, ''),
           round(e.gebinde_menge)::int
      from eingang e
     where e.pos_id is not null and e.datum is not null and e.artikel_id is not null and e.artikel is not null
    on conflict (quelle, pos_id) do update
      set datum = excluded.datum, saison = excluded.saison, journal = excluded.journal, kunde = excluded.kunde,
          artikel_id = excluded.artikel_id, artikel = excluded.artikel, preisgruppe = excluded.preisgruppe,
          einheit = excluded.einheit, menge = excluded.menge, gewicht_je_artikel = excluded.gewicht_je_artikel,
          kg = excluded.kg, gebindeart = excluded.gebindeart, gebinde_menge = excluded.gebinde_menge, ts = now()
    returning saison
  )
  select coalesce(jsonb_object_agg(s.saison::text, s.n), '{}'::jsonb), coalesce(sum(s.n), 0)::int
    into v_saisons, v_pos
    from (select saison, count(*)::int as n from geschrieben group by saison) s;

  -- Die Labels an die Zeilen der laufenden Saison (die Bilanz-Zeilen).
  with lose as (
    select * from jsonb_to_recordset(coalesce(p_lose, '[]'::jsonb)) as x(
      pos_id bigint, charge_extern text, lauf_nr int, liefer_label text, preisgruppe text)
  ), gesetzt as (
    update ausgang_zeile z
       set liefer_label = nullif(l.liefer_label, ''), preisgruppe = nullif(l.preisgruppe, '')
      from lose l
     where z.quelle = p_quelle and z.pos_id = l.pos_id
       and z.charge_extern = coalesce(l.charge_extern, '') and z.lauf_nr = coalesce(l.lauf_nr, 1)
       and (z.liefer_label is distinct from nullif(l.liefer_label, '')
            or z.preisgruppe is distinct from nullif(l.preisgruppe, ''))
    returning 1
  )
  select count(*) into v_lose from gesetzt;

  return jsonb_build_object('positionen', v_pos, 'je_saison', v_saisons, 'labels_gesetzt', v_lose);
end $fn$;
comment on function ausgang_historie_uebernehmen(text, jsonb, jsonb) is
  'Schreibt beim Einlesen der Perigon-Datei jede Position aller Saisons nach ausgang_position und die Labels (LiefPrsGrpName, Preisgruppe) an die Zeilen der laufenden Saison (0112). Die Masse nach perigon_kg (0115): bei kg-Artikeln ohne Gewicht je Artikel die Menge, bei Stück ohne Stückgewicht leer. Nur der Betriebsleiter.';
revoke all on function ausgang_historie_uebernehmen(text, jsonb, jsonb) from public;
grant execute on function ausgang_historie_uebernehmen(text, jsonb, jsonb) to authenticated;

create or replace function ausgang_uebernehmen(
  p_quelle       text,
  p_quelle_name  text,
  p_datei        jsonb,
  p_zeilen       jsonb,
  p_lieferungen  jsonb
) returns jsonb
language plpgsql security invoker set search_path = public as $fn$
declare
  v_datei_id     bigint;
  v_zeilen_neu   int := 0;
  v_zeilen_alt   int := 0;
  v_lief_neu     int := 0;
  v_lief_alt     int := 0;
  v_uebergangen  jsonb := '[]'::jsonb;
  l              record;
  v_lief_id      bigint;
  v_gebinde      text;
  v_sorte        text;
  v_charge       int;
  v_fremd        text;
  v_fremd_n      int;
  v_ersetzt      int := 0;
begin
  if not ist_admin() then
    raise exception 'Den Warenausgang übernimmt nur der Betriebsleiter.';
  end if;
  if p_quelle is null or p_quelle = '' then
    raise exception 'Ohne Quelle (Firma) keine Übernahme — an ihr hängt die Eindeutigkeit der Positionsnummern.';
  end if;

  -- 0099: Der Wächter. Kennt die Datenbank Zeilen dieser Datei — gleiche
  -- Position, gleiche Charge, gleicher Fingerabdruck — schon unter einer
  -- anderen Firma, dann IST es diese Firma, und unter einem zweiten Namen
  -- stünde alles doppelt in der Bilanz (28. September: 35 t). Die App fragt
  -- vorher; die Datenbank lässt es so oder so nicht zu.
  select z.quelle, count(*) into v_fremd, v_fremd_n
    from jsonb_to_recordset(p_zeilen) as x(pos_id bigint, charge_extern text, lauf_nr int, fingerabdruck text)
    join ausgang_zeile z on z.pos_id = x.pos_id and z.charge_extern = coalesce(x.charge_extern, '')
                        and z.lauf_nr = coalesce(x.lauf_nr, 1) and z.fingerabdruck = x.fingerabdruck
   where z.quelle <> p_quelle
   group by z.quelle order by count(*) desc limit 1;
  if v_fremd is not null then
    raise exception 'Diese Datei gehört zur Firma „%": % ihrer Zeilen sind dort schon bekannt. Unter „%" übernommen stünde alles doppelt in der Bilanz.',
      v_fremd, v_fremd_n, p_quelle using errcode = '23505';
  end if;

  insert into ausgang_quelle (code, name, dateiname_muster)
  values (p_quelle, coalesce(nullif(p_quelle_name, ''), p_quelle), p_quelle)
  on conflict (code) do nothing;

  insert into ausgang_datei (quelle, dateiname, pruefsumme, n_zeilen, n_kuerbis,
                             n_neu, n_geaendert, n_unveraendert, von_datum, bis_datum)
  values (p_quelle,
          p_datei ->> 'dateiname', p_datei ->> 'pruefsumme',
          coalesce((p_datei ->> 'n_zeilen')::int, 0), coalesce((p_datei ->> 'n_kuerbis')::int, 0),
          coalesce((p_datei ->> 'n_neu')::int, 0), coalesce((p_datei ->> 'n_geaendert')::int, 0),
          coalesce((p_datei ->> 'n_unveraendert')::int, 0),
          nullif(p_datei ->> 'von_datum', '')::date, nullif(p_datei ->> 'bis_datum', '')::date)
  on conflict (quelle, pruefsumme) do update
    set dateiname = excluded.dateiname, n_zeilen = excluded.n_zeilen, n_kuerbis = excluded.n_kuerbis,
        n_neu = excluded.n_neu, n_geaendert = excluded.n_geaendert,
        n_unveraendert = excluded.n_unveraendert, von_datum = excluded.von_datum,
        bis_datum = excluded.bis_datum, ts = now()
  returning id into v_datei_id;

  with eingang as (
    select * from jsonb_to_recordset(p_zeilen) as x(
      pos_id bigint, charge_extern text, lauf_nr int, fingerabdruck text,
      datum date, journal text, auftragsnr text, kunde text,
      artikel_id text, artikel text, einheit text,
      menge numeric, gewicht_je_artikel numeric, batch_menge numeric,
      kg_position numeric, kg_charge numeric,
      gebindeart text, gebinde_menge numeric, gebinde_inhalt numeric,
      batch_gebinde numeric,
      produzent text, erloes numeric)
  ), geschrieben as (
    insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datei_id,
                               datum, journal, auftragsnr, kunde, artikel_id, artikel, einheit,
                               menge, gewicht_je_artikel, batch_menge, kg_position, kg_charge,
                               gebindeart, gebinde_menge, gebinde_inhalt, batch_gebinde, produzent, erloes)
    select p_quelle, z.pos_id, coalesce(z.charge_extern, ''), coalesce(z.lauf_nr, 1), z.fingerabdruck, v_datei_id,
           z.datum, z.journal, z.auftragsnr, z.kunde, z.artikel_id, z.artikel, z.einheit,
           z.menge, z.gewicht_je_artikel, z.batch_menge, z.kg_position, z.kg_charge,
           z.gebindeart, round(z.gebinde_menge)::int, round(z.gebinde_inhalt)::int,
           round(z.batch_gebinde)::int, z.produzent, z.erloes
      from eingang z
     where z.pos_id is not null and z.datum is not null and z.artikel_id is not null
    on conflict (quelle, pos_id, charge_extern, lauf_nr) do update
      set geaendert_ts = case when ausgang_zeile.fingerabdruck <> excluded.fingerabdruck
                              then now() else ausgang_zeile.geaendert_ts end,
          fingerabdruck = excluded.fingerabdruck, datei_id = excluded.datei_id,
          datum = excluded.datum, journal = excluded.journal, auftragsnr = excluded.auftragsnr,
          kunde = excluded.kunde, artikel_id = excluded.artikel_id, artikel = excluded.artikel,
          einheit = excluded.einheit, menge = excluded.menge,
          gewicht_je_artikel = excluded.gewicht_je_artikel, batch_menge = excluded.batch_menge,
          kg_position = excluded.kg_position, kg_charge = excluded.kg_charge,
          gebindeart = excluded.gebindeart, gebinde_menge = excluded.gebinde_menge,
          gebinde_inhalt = excluded.gebinde_inhalt, batch_gebinde = excluded.batch_gebinde,
          produzent = excluded.produzent, erloes = excluded.erloes
    returning (xmax = 0) as neu
  )
  select count(*) filter (where neu), count(*) filter (where not neu)
    into v_zeilen_neu, v_zeilen_alt from geschrieben;

  for l in
    select * from jsonb_to_recordset(p_lieferungen) as x(
      extern_id text, datum date, charge_nr int, sorte text, kg numeric,
      gebindeart text, kunde text, bemerkung text)
  loop
    if l.extern_id is null or l.datum is null or l.kg is null or l.kg <= 0 then
      v_uebergangen := v_uebergangen || jsonb_build_object(
        'extern_id', l.extern_id, 'grund', 'ohne Kennung, Datum oder Masse');
      continue;
    end if;
    v_charge := case when exists (select 1 from charge c where c.nr = l.charge_nr) then l.charge_nr end;
    v_sorte  := case when exists (select 1 from sorte_kaliber s where s.sorte = l.sorte) then l.sorte end;
    if v_charge is null and v_sorte is null then
      v_uebergangen := v_uebergangen || jsonb_build_object(
        'extern_id', l.extern_id, 'kg', l.kg, 'datum', l.datum, 'kunde', l.kunde,
        'grund', 'weder Charge noch bestätigte Sorte — der Artikel ist noch nicht zugeordnet');
      continue;
    end if;
    v_gebinde := case when exists (select 1 from gebinde g where g.art = l.gebindeart) then l.gebindeart end;

    select i.lieferung_id into v_lief_id from lieferung_import i where i.extern_id = l.extern_id;
    if v_lief_id is not null then
      update lieferung
         set datum = l.datum, charge_nr = v_charge, sorte = v_sorte, kg = l.kg,
             gebindeart = v_gebinde, kunde = l.kunde,
             bemerkung = nullif(concat_ws(' · ', nullif(l.bemerkung, ''),
                                          case when v_gebinde is null and l.gebindeart is not null
                                               then 'Gebinde laut Datei: ' || l.gebindeart end), '')
       where id = v_lief_id;
      update lieferung_import set ts = now() where lieferung_id = v_lief_id;
      v_lief_alt := v_lief_alt + 1;
    else
      insert into lieferung (datum, charge_nr, sorte, kg, gebindeart, ziel, kunde, bemerkung)
      values (l.datum, v_charge, v_sorte, l.kg, v_gebinde, 'verkauf', l.kunde,
              nullif(concat_ws(' · ', nullif(l.bemerkung, ''),
                               case when v_gebinde is null and l.gebindeart is not null
                                    then 'Gebinde laut Datei: ' || l.gebindeart end), ''))
      returning id into v_lief_id;
      insert into lieferung_import (lieferung_id, quelle, extern_id)
      values (v_lief_id, p_quelle, l.extern_id);
      v_lief_neu := v_lief_neu + 1;
    end if;
  end loop;

  -- 0115: Was die Datei für ihre Positionen nicht mehr ergibt, ist keine
  -- Lieferung mehr. Kam eine Position zuerst ohne Charge (Lieferung „rest")
  -- und trägt Perigon die Charge später nach, entsteht eine neue Lieferung
  -- „Position:Charge:1" — die alte blieb bis hier stehen, und die Masse zählte
  -- doppelt (beim Betrieb 4 Positionen, 520 kg). Die App schickt für jede
  -- Position der Datei alle ihre Lieferungen; was davon nicht mehr dabei ist,
  -- geht. Positionen, die nicht in der Datei stehen, bleiben, wie sie sind.
  with positionen as (
    select distinct x.pos_id
      from jsonb_to_recordset(p_zeilen) as x(pos_id bigint)
     where x.pos_id is not null
  ), soll as (
    select x.extern_id
      from jsonb_to_recordset(p_lieferungen) as x(extern_id text)
     where x.extern_id is not null
  ), weg as (
    -- (Der Alias heisst nicht „l": so heisst oben die Schleifenvariable, und
    -- PL/pgSQL nähme sie statt der Tabelle.)
    delete from lieferung weg_l
     using lieferung_import i
     where i.lieferung_id = weg_l.id
       and i.quelle = p_quelle
       and split_part(i.extern_id, ':', 2) ~ '^[0-9]+$'
       and split_part(i.extern_id, ':', 2)::bigint in (select pos_id from positionen)
       and i.extern_id not in (select extern_id from soll)
    returning weg_l.id
  )
  select count(*)::int into v_ersetzt from weg;

  -- 0061: jede Lieferung dieser Quelle kennt ihre Zeile
  perform lieferung_import_zeilen_verbinden(p_quelle);

  return jsonb_build_object(
    'datei_id', v_datei_id,
    'zeilen_neu', v_zeilen_neu, 'zeilen_geaendert', v_zeilen_alt,
    'lieferungen_neu', v_lief_neu, 'lieferungen_aktualisiert', v_lief_alt,
    'lieferungen_ersetzt', v_ersetzt,
    'uebergangen', v_uebergangen);
end $fn$;
comment on function ausgang_uebernehmen is
  'Schreibt eine hochgeladene Warenausgangsdatei in einem Zug: Quelle (falls neu), '
  'Datei (Prüfsumme), Rohzeilen (Upsert, geaendert_ts bei anderem Fingerabdruck, seit '
  '0061 mit Kisten je Chargenzeile) und Lieferungen (Upsert über lieferung_import.extern_id, '
  'mit ihrer Zeile verbunden). Seit 0099 abgewiesen, wenn die Zeilen unter '
  'einer anderen Firma schon bekannt sind (sonst doppelte Bilanz). Seit 0115 entfernt sie für '
  'jede Position der Datei die Lieferungen, die die Datei nicht mehr ergibt (Charge nachgetragen, '
  'anders aufgeteilt) — sonst zählte die Masse doppelt; Positionen ausserhalb der Datei bleiben. '
  'Gibt zurück, was neu, was aktualisiert, was ersetzt und was nicht übernommen wurde (mit Grund).';
revoke all on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) from public;
grant execute on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) to authenticated;

-- =====================================================================
-- 4. Der Vergleich je Kunde: Stück ohne Gewicht stehen da, nicht als 0
-- =====================================================================
create or replace view v_verkauf_position with (security_invoker = true) as
select p.quelle, p.pos_id, p.datum, p.saison, p.journal, p.kunde, p.artikel_id, p.artikel, p.preisgruppe,
       p.kg, p.gebindeart, p.gebinde_menge, 'datei'::text as herkunft, p.menge, p.einheit
  from ausgang_position p
union all
select z.quelle, z.pos_id, z.datum, saison_von(z.datum), z.journal, z.kunde, z.artikel_id, z.artikel, z.preisgruppe,
       z.kg_position, z.gebindeart, z.gebinde_menge, 'zeile'::text, z.menge, z.einheit
  from (select distinct on (quelle, pos_id) * from ausgang_zeile order by quelle, pos_id, lauf_nr) z
 where not exists (select 1 from ausgang_position p where p.quelle = z.quelle and p.pos_id = z.pos_id);
comment on view v_verkauf_position is
  'Je Lieferscheinposition: Datum, Saison, Kunde, Artikel, kg — aus ausgang_position (alle Saisons), ergänzt um die Positionen der laufenden Saison, die nur in ausgang_zeile stehen (0112). Seit 0115 mit Menge und Einheit: kg ist leer, wo Perigon die Masse nicht hergibt.';
grant select on v_verkauf_position to authenticated;

create or replace view v_kunde_tag with (security_invoker = true) as
select v.kunde, v.saison, v.datum, e.gruppe, e.groesse, e.label, sum(v.kg) as kg, count(*)::int as positionen,
       sum(v.menge) filter (where v.kg is null and v.menge is not null) as stueck_ohne_gewicht,
       count(*) filter (where v.kg is null)::int as positionen_ohne_gewicht
  from v_verkauf_position v
  left join ausgang_artikel a on a.artikel_id = v.artikel_id and a.artikel = v.artikel
 cross join lateral artikel_einordnen(v.artikel, v.preisgruppe) e
 where coalesce(v.journal, '') <> 'L'
   and coalesce(a.ist_kuerbis, ist_kuerbis_vorschlag(v.artikel_id, v.artikel))
   and v.kunde is not null and v.kunde <> ''
 group by v.kunde, v.saison, v.datum, e.gruppe, e.groesse, e.label;
comment on view v_kunde_tag is
  'Geliefert je Kunde, Saison, Tag und Artikel (Gruppe, Grösse, Label) — nur Kürbis, ohne interne Umbuchung (Journal L). Für den Vergleich mit den Vorjahren (0112). Seit 0115: stueck_ohne_gewicht und positionen_ohne_gewicht — was Perigon ohne Stückgewicht führt, steht nicht in kg, aber es steht da.';
grant select on v_kunde_tag to authenticated;

-- =====================================================================
-- 4b. Die Demo zeigt es
-- =====================================================================
-- Ohne einen Fall in der Demo sähe niemand, wie die App Stück ohne Gewicht
-- zeigt, und die Bildschirmprüfung könnte es nicht prüfen. Die Funktion ist
-- die aus 0112, ergänzt um einen Block am Ende.
create or replace function demo_vorjahre_laden() returns text
language plpgsql security definer set search_path = public as $fn$
declare
  v_saison int;
  v_erste date;
  v_n int := 0;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter laden.';
  end if;
  if not exists (select 1 from ausgang_quelle where code = 'DEMO') then
    return 'Keine Demo-Verkaufsdatei — keine Vorjahre.';
  end if;
  -- Das Label der gelieferten Charge, wie Perigon es führt: jede vierte Knospe.
  update ausgang_zeile z
     set liefer_label = case when z.charge_extern ~ '^[0-9]+$' and z.charge_extern::int % 4 = 1 then 'K' else 'D' end,
         preisgruppe  = case when z.charge_extern ~ '^[0-9]+$' and z.charge_extern::int % 4 = 1 then 'K' else 'D' end
   where z.quelle = 'DEMO' and z.liefer_label is null;
  -- Die laufende Saison ist die der jüngsten Demo-Lieferung. Die Demo beginnt
  -- im Frühling davor — was vor ihrer ersten Lieferung liegt, kommt dazu.
  select saison_von(max(datum)), min(datum) into v_saison, v_erste from ausgang_zeile where quelle = 'DEMO';
  if v_saison is null then return 'Keine Demo-Lieferungen — keine Vorjahre.'; end if;
  delete from ausgang_position where quelle = 'DEMO' and saison < v_saison;
  -- Je Kunde und Vorjahr eine Lieferung je Woche, nach einer Glocke über
  -- die Saison (Höhepunkt im Oktober), Grösse je Kunde aus der laufenden Saison.
  insert into ausgang_position (quelle, pos_id, datum, saison, journal, kunde, artikel_id, artikel, preisgruppe,
                                einheit, menge, gewicht_je_artikel, kg, gebindeart, gebinde_menge)
  select 'DEMO', 900000000 + j.jahr * 100000 + k.nr * 1000 + w.woche,
         make_date(v_saison - j.jahr, 7, 1) + (w.woche * 7),
         v_saison - j.jahr, 'Lieferschein', k.kunde, k.artikel_id, k.artikel, 'D', 'kg',
         x.kg, 1, x.kg, 'IFCO', null
    from (select row_number() over (order by z.kunde)::int as nr, z.kunde,
                 min(z.artikel_id) as artikel_id, min(z.artikel) as artikel,
                 greatest(sum(z.kg_position) / greatest(count(distinct date_trunc('week', z.datum)), 1), 50) as je_woche
            from ausgang_zeile z where z.quelle = 'DEMO' and z.kunde is not null group by z.kunde) k
   cross join (values (1, 1.0), (2, 0.8)) j(jahr, faktor)
   cross join generate_series(0, 51) w(woche)
   cross join lateral (select round(k.je_woche * j.faktor * (0.6 + 0.08 * k.nr)
                                    * exp(-power((w.woche - 15) / 9.0, 2))
                                    * (0.8 + 0.4 * ((k.nr * 7 + w.woche * 13 + j.jahr * 5) % 10) / 10.0)) as kg) x
   where x.kg >= 20
     and make_date(v_saison - j.jahr, 7, 1) + (w.woche * 7) < v_erste
  on conflict (quelle, pos_id) do nothing;
  get diagnostics v_n = row_count;
  -- 0115: Wie beim Betrieb 2024/25 (Muscade, 12'322 Stück): ein Kunde bekam
  -- im Vorjahr auch Stück, für die Perigon kein Stückgewicht kennt. Sie
  -- stehen ohne kg da — nicht 0, nicht geschätzt.
  insert into ausgang_position (quelle, pos_id, datum, saison, journal, kunde, artikel_id, artikel, preisgruppe,
                                einheit, menge, gewicht_je_artikel, kg, gebindeart, gebinde_menge)
  select 'DEMO', 900000000 + 100000 + k.nr * 1000 + 500 + w.woche,
         make_date(v_saison - 1, 7, 1) + (w.woche * 7), v_saison - 1, 'Lieferschein', k.kunde,
         'kürbmudkl', 'Bio Kürbis Muscade Dem klein', 'D', 'Stk.', 40 + 20 * (w.woche % 3), 0,
         perigon_kg(40 + 20 * (w.woche % 3), 0, 'Stk.'), 'IFCO', null
    from (select row_number() over (order by z.kunde)::int as nr, z.kunde
            from ausgang_zeile z where z.quelle = 'DEMO' and z.kunde is not null group by z.kunde) k
   cross join generate_series(12, 18) w(woche)
   where k.nr = 1 and make_date(v_saison - 1, 7, 1) + (w.woche * 7) < v_erste
  on conflict (quelle, pos_id) do nothing;
  return format('Demo: %s Lieferungen in zwei Vorjahren, Labels an den Demo-Verkaufszeilen.', v_n);
end $fn$;
comment on function demo_vorjahre_laden() is
  'Ergänzt die Demo um das Perigon-Label je Verkaufszeile und zwei Vorjahre je Demo-Kunde (ausgang_position, quelle DEMO) — für Lager nach Artikel (0112); seit 0115 mit ein paar Stück ohne Stückgewicht im Vorjahr (kg leer). Gleich nach demo_daten_laden() aufrufen; demo_daten_entfernen() räumt es mit der Demo-Firma weg.';
-- security definer: ohne das „revoke" könnte sie jeder rufen, auch ohne
-- Anmeldung (auth.uid() ist dann leer und die Sperre oben greift nicht).
revoke all on function demo_vorjahre_laden() from public;
grant execute on function demo_vorjahre_laden() to authenticated;

-- =====================================================================
-- 5. Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 115 $$;
