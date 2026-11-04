-- =====================================================================
-- 0130 — Was die Datei nicht mehr sagt, liegt beiseite
-- =====================================================================
--
-- WARUM
--
-- Der Betrieb am 4. November zu Fall 134779 im Reiter Perigon („Im Excel
-- steht dieselbe Zeile 3-mal untereinander"): „ich hab jetzt die PosId im
-- Perigon gesucht — und finde die Zeile nur einmal." Er hat recht. In der
-- Datei vom 12. Oktober stand die Position dreimal da (so hat die App sie
-- damals eingelesen: lauf_nr 1, 2, 3). Seit der Datei vom 19. Oktober steht
-- sie einmal da (heute Excel-Zeile 295). Das Einlesen schrieb die eine Zeile
-- jedes Mal neu, liess die zwei anderen aber stehen („Löscht nichts", 0055).
-- Die Lieferungen dazu hatte schon 0115 entfernt; die Lagerzahlen stimmten.
-- Gelesen haben die alten Zeilen aber 14 Sichten — darunter die Prüfung
-- v_perigon_befund, die sie als „dreimal dieselbe Zeile" meldete, und das
-- Fenster des Falls, das sie als Excel zeigte.
--
-- Auf den Daten des Betriebs (4. November) sind es 23 Zeilen in 22
-- Positionen, alle derselben Art: Perigon hat die Position später anders
-- geschrieben — meist die Charge nachgetragen (eine Zeile ohne Charge, jetzt
-- mit), dreimal die Charge geändert, einmal zwei doppelte Zeilen entfernt.
-- Drei davon erzeugten einen Fall „mehr zugeteilt als geliefert", den keine
-- Datei mehr hat (134779, und zweimal die alte und die neue Charge zusammen).
--
-- WAS
--
-- 1. ausgang_zeile_frueher: dieselben Spalten wie ausgang_zeile, dazu wann
--    und mit welcher Datei die Zeile beiseitegelegt wurde. Wie in
--    ausgang_zeile darf jeder Angemeldete lesen, schreiben nur der
--    Betriebsleiter. Nichts geht verloren: wer wissen will, was früher in
--    der Datei stand, findet es hier.
-- 2. ausgang_zeilen_beiseite(quelle, datei, zeilen): für jede Position, die
--    in der Datei steht, wandern die Zeilen, die die Datei nicht mehr hat,
--    nach ausgang_zeile_frueher. Positionen, die nicht in der Datei stehen,
--    bleiben (eine Datei kann auch nur einen Teil enthalten).
-- 3. ausgang_uebernehmen ruft sie nach dem Schreiben der Zeilen und
--    Lieferungen auf — dieselbe Regel wie 0115 für die Lieferungen — und
--    sagt, wie viele Zeilen beiseite gingen. Sonst Zeichen für Zeichen 0115.
-- 4. Einmal jetzt: was die neuste Datei jeder Firma anders hat, geht
--    beiseite (beim Betrieb die 23 Zeilen).
-- 5. erfassung_umfang und erfassung_leeren kennen die neue Tabelle (20
--    statt 19).
--
-- Damit lesen alle Sichten nur noch, was die neuste Datei sagt — ohne dass
-- eine von ihnen umgeschrieben werden musste.
--
-- Prüfblock 0130 in supabase/test/pruefung.sql.

-- =====================================================================
-- 1. Die Ablage
-- =====================================================================
create table if not exists ausgang_zeile_frueher (like ausgang_zeile);
alter table ausgang_zeile_frueher
  add column if not exists nicht_mehr_ts timestamptz not null default now(),
  add column if not exists nicht_mehr_datei_id bigint;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ausgang_zeile_frueher_pkey') then
    alter table ausgang_zeile_frueher add constraint ausgang_zeile_frueher_pkey primary key (id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ausgang_zeile_frueher_quelle_fkey') then
    -- Wird eine Firma entfernt, geht ihre Ablage mit (ausgang_quelle_entfernen, demo_daten_entfernen).
    alter table ausgang_zeile_frueher add constraint ausgang_zeile_frueher_quelle_fkey
      foreign key (quelle) references ausgang_quelle(code) on update cascade on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ausgang_zeile_frueher_nicht_mehr_datei_fkey') then
    alter table ausgang_zeile_frueher add constraint ausgang_zeile_frueher_nicht_mehr_datei_fkey
      foreign key (nicht_mehr_datei_id) references ausgang_datei(id) on delete set null;
  end if;
end $$;
create index if not exists ausgang_zeile_frueher_position on ausgang_zeile_frueher (quelle, pos_id);

comment on table ausgang_zeile_frueher is
  'Zeilen aus Warenausgangsdateien, die eine spätere Datei nicht mehr hat, obwohl sie ihre Position enthält (0130) — '
  'Perigon hat die Position anders geschrieben: Charge nachgetragen oder geändert, eine doppelte Zeile entfernt. '
  'Dieselben Spalten wie ausgang_zeile (in derselben Folge; der Prüfblock hält es), dazu nicht_mehr_ts und '
  'nicht_mehr_datei_id: wann und mit welcher Datei die Zeile beiseiteging; datei_id ist die letzte Datei, in der '
  'sie stand. Keine Sicht der Rechnung liest sie.';
comment on column ausgang_zeile_frueher.nicht_mehr_datei_id is
  'Die Datei, die die Position anders hatte (leer, wenn sie entfernt wurde oder beim einmaligen Ablegen in 0130 nicht bekannt war, welche zuerst).';

alter table ausgang_zeile_frueher enable row level security;
drop policy if exists ausgang_zeile_frueher_lesen on ausgang_zeile_frueher;
create policy ausgang_zeile_frueher_lesen on ausgang_zeile_frueher for select to authenticated using (true);
drop policy if exists ausgang_zeile_frueher_admin on ausgang_zeile_frueher;
create policy ausgang_zeile_frueher_admin on ausgang_zeile_frueher for all to authenticated
  using (ist_admin()) with check (ist_admin());
grant select, insert, delete on ausgang_zeile_frueher to authenticated;

-- =====================================================================
-- 2. Beiseitelegen, was die Datei für ihre Positionen nicht mehr hat
-- =====================================================================
create or replace function ausgang_zeilen_beiseite(p_quelle text, p_datei_id bigint, p_zeilen jsonb)
returns int language plpgsql security invoker set search_path = public as $fn$
declare v_n int;
begin
  with datei as (
    select distinct x.pos_id, coalesce(x.charge_extern, '') as charge_extern, coalesce(x.lauf_nr, 1) as lauf_nr
      from jsonb_to_recordset(p_zeilen) as x(pos_id bigint, charge_extern text, lauf_nr int)
     where x.pos_id is not null
  ), weg as (
    delete from ausgang_zeile z
     where z.quelle = p_quelle
       and z.pos_id in (select d.pos_id from datei d)
       and not exists (select 1 from datei d
                        where d.pos_id = z.pos_id and d.charge_extern = z.charge_extern and d.lauf_nr = z.lauf_nr)
    returning z.*
  ), abgelegt as (
    -- dieselbe Spaltenfolge wie ausgang_zeile, dann wann und mit welcher Datei
    insert into ausgang_zeile_frueher
    select w.*, now(), p_datei_id from weg w
    returning 1
  )
  select count(*)::int into v_n from abgelegt;
  return v_n;
end $fn$;
comment on function ausgang_zeilen_beiseite(text, bigint, jsonb) is
  'Legt für jede Position der Datei die Zeilen beiseite (nach ausgang_zeile_frueher), die die Datei nicht mehr hat — '
  'Schlüssel Position, Charge, Lauf (0130). Positionen ausserhalb der Datei bleiben. Gibt die Zahl zurück. Aufgerufen '
  'von ausgang_uebernehmen; schreiben darf nur der Betriebsleiter (Regeln der Tabellen).';
revoke all on function ausgang_zeilen_beiseite(text, bigint, jsonb) from public;
grant execute on function ausgang_zeilen_beiseite(text, bigint, jsonb) to authenticated;

-- =====================================================================
-- 3. Das Einlesen ruft es auf (sonst Zeichen für Zeichen 0115)
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
  v_ersetzt      int := 0;
  v_beiseite     int := 0;
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

  -- 0130: Hat die Datei eine Position jetzt anders (Charge nachgetragen oder
  -- geändert, eine doppelte Zeile entfernt), legt die App die Zeilen, die die
  -- Datei nicht mehr hat, beiseite — nach ausgang_zeile_frueher, nicht weg.
  -- Dieselbe Regel wie oben für die Lieferungen; Positionen, die nicht in der
  -- Datei stehen, bleiben, wie sie sind.
  v_beiseite := ausgang_zeilen_beiseite(p_quelle, v_datei_id, p_zeilen);

  -- 0061: jede Lieferung dieser Quelle kennt ihre Zeile
  perform lieferung_import_zeilen_verbinden(p_quelle);

  return jsonb_build_object(
    'datei_id', v_datei_id,
    'zeilen_neu', v_zeilen_neu, 'zeilen_geaendert', v_zeilen_alt,
    'lieferungen_neu', v_lief_neu, 'lieferungen_aktualisiert', v_lief_alt,
    'lieferungen_ersetzt', v_ersetzt,
    'zeilen_beiseite', v_beiseite,
    'uebergangen', v_uebergangen);
end $fn$;

comment on function ausgang_uebernehmen is
  'Schreibt eine hochgeladene Warenausgangsdatei in einem Zug: Quelle (falls neu), '
  'Datei (Prüfsumme), Rohzeilen (Upsert, geaendert_ts bei anderem Fingerabdruck, seit '
  '0061 mit Kisten je Chargenzeile) und Lieferungen (Upsert über lieferung_import.extern_id, '
  'mit ihrer Zeile verbunden). Seit 0099 abgewiesen, wenn die Zeilen unter '
  'einer anderen Firma schon bekannt sind (sonst doppelte Bilanz). Seit 0115 entfernt sie für '
  'jede Position der Datei die Lieferungen, die die Datei nicht mehr ergibt (Charge nachgetragen, '
  'anders aufgeteilt) — sonst zählte die Masse doppelt; seit 0130 legt sie ebenso die Zeilen beiseite, '
  'die die Datei für ihre Positionen nicht mehr hat (nach ausgang_zeile_frueher). Positionen ausserhalb '
  'der Datei bleiben. Gibt zurück, was neu, was aktualisiert, was ersetzt, was beiseitegelegt und was '
  'nicht übernommen wurde (mit Grund).';
revoke all on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) from public;
grant execute on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) to authenticated;

-- =====================================================================
-- 4. Einmal jetzt: was die neuste Datei jeder Firma anders hat
-- =====================================================================
-- Die neuste Datei hat jede ihrer Zeilen mit ihrer Kennung geschrieben
-- (datei_id). Steht eine Position in ihr, ist jede andere Zeile dieser
-- Position eine, die die Datei nicht mehr hat. Mit welcher Datei sie zuerst
-- wegfiel, weiss niemand mehr — nicht_mehr_datei_id bleibt leer;
-- datei_id sagt, wo sie zuletzt stand.
with neuste as (
  select distinct on (d.quelle) d.quelle, d.id
    from ausgang_datei d
   order by d.quelle, d.ts desc, d.id desc
), weg as (
  delete from ausgang_zeile z
   using neuste n
   where z.quelle = n.quelle
     and z.datei_id is distinct from n.id
     and exists (select 1 from ausgang_zeile y where y.quelle = z.quelle and y.pos_id = z.pos_id and y.datei_id = n.id)
  returning z.*
)
insert into ausgang_zeile_frueher
select w.*, now(), null::bigint from weg w;

-- =====================================================================
-- 5. Erfassung leeren und ihr Umfang: 20 Tabellen
-- =====================================================================
create or replace function erfassung_umfang()
returns table (tabelle text, was text, zeilen bigint)
language sql stable security definer set search_path = public as $$
  select * from (values
    ('auftrag',                 'Arbeiten (auch laufende)',          (select count(*) from auftrag)),
    ('auftrag_palette',         'gezählte Paletten je Arbeit',       (select count(*) from auftrag_palette)),
    ('auftrag_gebinde',         'gezählte Gebinde je Arbeit',        (select count(*) from auftrag_gebinde)),
    ('auftrag_angabe',          'Antworten aus dem Abschluss',       (select count(*) from auftrag_angabe)),
    ('auftrag_teilnehmer',      'Teilnehmer an Arbeiten',            (select count(*) from auftrag_teilnehmer)),
    ('palette',                 'Eingangspaletten',                  (select count(*) from palette)),
    ('lieferung',               'Lieferungen',                       (select count(*) from lieferung)),
    ('lieferung_import',        'Zuordnungen Lieferung ↔ Importzeile', (select count(*) from lieferung_import)),
    ('sortier_lauf',            'Sortierläufe',                      (select count(*) from sortier_lauf)),
    ('sortier_gewicht',         'gemessene Gewichtsstufen',          (select count(*) from sortier_gewicht)),
    ('schimmel_messung',        'Messungen von Faulem',              (select count(*) from schimmel_messung)),
    ('ausschuss_messung',       'Ausschuss-Wägungen',                (select count(*) from ausschuss_messung)),
    ('ausgang_wiegung',         'Wägungen fertiger Paletten',        (select count(*) from ausgang_wiegung)),
    ('verdunstung_wiegung',     'Lagerkontroll-Wägungen',            (select count(*) from verdunstung_wiegung)),
    ('kontrollpalette',         'Kontrollpaletten',                  (select count(*) from kontrollpalette)),
    ('kontrollpalette_wiegung', 'Wägungen der Kontrollpaletten',     (select count(*) from kontrollpalette_wiegung)),
    ('ausgang_datei',           'hochgeladene Warenausgangsdateien', (select count(*) from ausgang_datei)),
    ('ausgang_zeile',           'Zeilen aus Warenausgangsdateien',   (select count(*) from ausgang_zeile)),
    ('ausgang_zeile_frueher',   'frühere Zeilen aus Warenausgangsdateien', (select count(*) from ausgang_zeile_frueher)),
    ('charge_vorlauf',          'Angaben zum Erfassungsbeginn',      (select count(*) from charge_vorlauf))
  ) as t(tabelle, was, zeilen)
  where zeilen > 0
  order by zeilen desc;
$$;

comment on function erfassung_umfang() is
  'Was der Löschknopf treffen würde, Tabelle für Tabelle, ohne etwas zu ändern. '
  'Nur Zeilen mit Inhalt. Dieselben 20 Tabellen (seit 0130 mit ausgang_zeile_frueher), die erfassung_leeren() leert — '
  'die Liste hier und die Liste dort müssen deckungsgleich bleiben, sonst nennt '
  'die Oberfläche eine kleinere Zahl, als sie dann löscht (0080).';

revoke all on function erfassung_umfang() from public;
grant execute on function erfassung_umfang() to authenticated;

create or replace function erfassung_leeren(p_bestaetigung text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  v_vorher  bigint;
  v_journal bigint;
  v_zeile   record;
  v_bericht text := '';
begin
  -- Dieselbe Regel wie bei demo_daten_entfernen(): Wer über die App kommt,
  -- muss Betriebsleiter sein. Im SQL-Editor gibt es keine Anmeldung
  -- (auth.uid() ist null) — dort darf es weiterhin gehen, sonst wäre der
  -- Weg zu, wenn die App gerade nicht läuft.
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Die Erfassung leeren darf nur der Betriebsleiter.';
  end if;

  if p_bestaetigung is distinct from 'ALLES LOESCHEN' then
    raise exception E'Zum Leeren fehlt das Bestätigungswort.\nEs lautet: ALLES LOESCHEN';
  end if;

  select count(*) into v_journal from erfassung_journal;

  -- Der Umfang, bevor er verschwindet — für den Rückgabetext.
  for v_zeile in select was, zeilen from erfassung_umfang() loop
    v_bericht := v_bericht || format('%s %s, ', v_zeile.zeilen, v_zeile.was);
  end loop;

  select count(*) into v_vorher from palette;

  -- Von den Blättern zur Wurzel. Jede dieser Zeilen geht durch den
  -- Journal-Auslöser, sofern die Tabelle ihn trägt (16 von 20 tun es).
  --
  -- `where true` ist kein Zierrat und keine Umgehung, sondern Pflicht:
  -- Supabase lässt die API-Verbindung mit der Sicherung „safeupdate"
  -- laufen, und die weist ein DELETE ohne WHERE ab — auch im Rumpf einer
  -- Funktion. Ohne diese drei Wörter liefe der Knopf auf dem Prüfstand
  -- durch und auf der echten Seite in einen Fehler. `pruefung.sql` hat
  -- dafür eine eigene Wache; sie hat genau das hier gefunden.
  -- Gelesen heisst es: alle Zeilen, mit Absicht.
  delete from sortier_gewicht where true;
  delete from sortier_lauf where true;
  delete from auftrag_palette where true;
  delete from auftrag_angabe where true;
  delete from auftrag_gebinde where true;
  delete from auftrag_teilnehmer where true;
  delete from schimmel_messung where true;
  delete from ausschuss_messung where true;
  delete from ausgang_wiegung where true;
  delete from verdunstung_wiegung where true;
  delete from auftrag where true;
  delete from kontrollpalette_wiegung where true;
  delete from kontrollpalette where true;
  delete from lieferung_import where true;
  delete from lieferung where true;
  delete from ausgang_zeile where true;
  delete from ausgang_zeile_frueher where true;
  delete from ausgang_datei where true;
  delete from charge_vorlauf where true;
  delete from palette where true;

  -- Die Auswertung gilt ab jetzt als veraltet; gerechnet wird getrennt.
  update auswertung_stand set geaendert_ts = now() where id = 1;

  select count(*) - v_journal into v_journal from erfassung_journal;

  v_bericht := rtrim(v_bericht, ', ');

  if v_bericht = '' then
    return 'Es war schon leer — nichts zu löschen.';
  end if;

  return format('Erfassung geleert: %s. Davon stehen %s Zeilen mit ihrem alten Inhalt '
                'im Journal und bleiben nachlesbar. Chargen, Sorten, Gebinde, Käufer, '
                'Sortierschemata, Konten und Einstellungen sind unberührt.',
                v_bericht, v_journal);
end $fn$;

comment on function erfassung_leeren(text) is
  'Leert alle Erfassungsdaten (Arbeiten, Paletten, Wägungen, Lieferungen, '
  'Lagerkontrollen, eingelesene Warenausgangsdateien) und lässt die Stammdaten '
  'stehen. Verlangt das Bestätigungswort „ALLES LOESCHEN" und den Betriebsleiter. '
  'Jede gelöschte Zeile einer Erfassungstabelle steht mit ihrem alten Inhalt im '
  'erfassung_journal; ausgang_datei, ausgang_zeile, ausgang_zeile_frueher (0130) und lieferung_import tragen den '
  'Auslöser nicht und sind nur über die hochgeladene Datei wiederherstellbar. Rechnet die '
  'Auswertung nicht neu — eigener Aufruf, wie bei demo_daten_laden() (0080).';

revoke all on function erfassung_leeren(text) from public;
grant execute on function erfassung_leeren(text) to authenticated;

-- =====================================================================
-- Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 130 $$;
