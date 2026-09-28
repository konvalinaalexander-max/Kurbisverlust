-- =====================================================================
-- 0099 — Eine Datei, eine Firma: der Wächter gegen die doppelte Bilanz
--
-- 28. September: Die neue Datei der einen Firma hiess „Imhof Bioprodukte
-- Rückverfolgbarkeit ge…" statt „imhof-bioprodukte". Der Name traf kein
-- Muster, die App legte eine dritte Firma an — 35 t standen doppelt in der
-- Bilanz, und niemand hatte es gesagt. Der Betrieb: „stelle sicher dass er
-- es besser checkt welche datei er kriegt — es gibt nur 2 … und lösch auch
-- gleich die eine datei raus, so dass ich keine warenausgangsdaten mehr
-- doppelt habe."
--
-- Drei Dinge:
--   1. ausgang_uebernehmen prüft selbst: Sind Zeilen dieser Datei (Position,
--      Charge, Fingerabdruck) unter einer anderen Firma schon bekannt, ist es
--      diese Firma — die Übernahme unter einem zweiten Namen wird abgewiesen.
--      Die App erkennt die Firma vorher am Inhalt (quelleErkennen); der
--      Wächter hier gilt auch, wenn jemand sie von Hand anders wählt.
--   2. ausgang_quelle_entfernen(code): eine Firma mit allen Zeilen, Dateien
--      und Lieferungen entfernen — der Weg, wenn dieselbe Datei unter zwei
--      Namen gelandet ist. Das Journal (0072) behält jede Lieferung; die
--      Datei lässt sich jederzeit wieder hochladen. Nur der Betriebsleiter.
--   3. Kein Schema-Umbau: keine Tabelle, keine Spalte verschwindet.
-- =====================================================================

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

  -- 0061: jede Lieferung dieser Quelle kennt ihre Zeile
  perform lieferung_import_zeilen_verbinden(p_quelle);

  return jsonb_build_object(
    'datei_id', v_datei_id,
    'zeilen_neu', v_zeilen_neu, 'zeilen_geaendert', v_zeilen_alt,
    'lieferungen_neu', v_lief_neu, 'lieferungen_aktualisiert', v_lief_alt,
    'uebergangen', v_uebergangen);
end $fn$;
comment on function ausgang_uebernehmen is
  'Schreibt eine hochgeladene Warenausgangsdatei in einem Zug: Quelle (falls neu), '
  'Datei (Prüfsumme), Rohzeilen (Upsert, geaendert_ts bei anderem Fingerabdruck, seit '
  '0061 mit Kisten je Chargenzeile) und Lieferungen (Upsert über lieferung_import.extern_id, '
  'mit ihrer Zeile verbunden). Löscht nichts. Seit 0099 abgewiesen, wenn die Zeilen unter '
  'einer anderen Firma schon bekannt sind (sonst doppelte Bilanz). Gibt zurück, was neu, '
  'was aktualisiert und was nicht übernommen wurde (mit Grund).';
revoke all on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) from public;
grant execute on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Eine Firma entfernen — mit allem, was aus ihr kam
-- ---------------------------------------------------------------------
create or replace function ausgang_quelle_entfernen(p_code text)
returns jsonb language plpgsql security invoker set search_path = public as $fn$
declare v_lief int; v_zeilen int; v_dateien int;
begin
  if not ist_admin() then
    raise exception 'Eine Firma des Warenausgangs entfernt nur der Betriebsleiter.' using errcode = '42501';
  end if;
  if not exists (select 1 from ausgang_quelle where code = p_code) then
    raise exception 'Die Firma „%" gibt es nicht.', p_code;
  end if;
  -- Zuerst die Lieferungen (das Journal schreibt jede mit); lieferung_import
  -- geht mit ihnen (on delete cascade). Von Hand erfasste Lieferungen haben
  -- keine Kennung aus dem Perigon und bleiben.
  with weg as (
    delete from lieferung l
     where l.id in (select i.lieferung_id from lieferung_import i where i.quelle = p_code)
    returning 1)
  select count(*) into v_lief from weg;
  with weg as (delete from ausgang_zeile where quelle = p_code returning 1) select count(*) into v_zeilen from weg;
  with weg as (delete from ausgang_datei where quelle = p_code returning 1) select count(*) into v_dateien from weg;
  delete from ausgang_quelle where code = p_code;
  return jsonb_build_object('quelle', p_code, 'lieferungen', v_lief, 'zeilen', v_zeilen, 'dateien', v_dateien);
end $fn$;
comment on function ausgang_quelle_entfernen(text) is
  'Entfernt eine Firma des Warenausgangs mit ihren Zeilen, Dateien und den daraus '
  'entstandenen Lieferungen (das Journal behält sie). Der Weg, wenn dieselbe Datei '
  'unter zwei Namen gelandet ist (0099). Nur der Betriebsleiter.';
revoke all on function ausgang_quelle_entfernen(text) from public;
grant execute on function ausgang_quelle_entfernen(text) to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 99 $$;
