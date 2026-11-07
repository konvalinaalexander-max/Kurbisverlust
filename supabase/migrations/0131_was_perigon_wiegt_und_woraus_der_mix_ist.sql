-- =====================================================================
-- 0131 — Was Perigon wiegt, woraus der Mix ist, was Perigon gelöscht hat
-- =====================================================================
--
-- WARUM
--
-- Der Betrieb am 7. November zum Artikel „Bio Kürbis Ünique": „ich glaube,
-- bei den ersten Einträgen hatte es einen Formatierfehler, so dass im
-- Faktor 10 angezeigt wird." Der Perigon-Artikelstamm führt Ünique in kg,
-- aber mit Gewicht je Artikel 10 (alle anderen kg-Artikel 1 oder 0). Die
-- Menge ist schon kg (Gebinde × Inhalt = Menge, der Erlös je kg passt nur
-- so); Perigon rechnet das Totalgewicht trotzdem × 10, und die App
-- (perigon_kg, 0115: Gewicht > 0 → Menge × Gewicht) ebenso. In der Datei
-- vom 6. November sind es 36 Zeilen: 18.4 t Ware, in der App 184 t. Von den
-- 155 t „Überzählung" der Saison sind 141 t dieser Faktor (1598, 1607, 1628).
--
-- Zum Kürbis Mix („Bio Kürbis Mix OS"): „Mix ist Mandarin 3 Stück, Kabocha
-- 3 Stück und Butterkin — bei grossen 2 Stück, bei kleinen 4–6"; „in den
-- meisten Fällen kleine Kabocha". Perigon bucht jeden Mix auf eine einzige
-- Charge — bis 12. Oktober 1624 Butterkin, ab dem 13. 1649 Butterkin, genau
-- als 1624 leer war: die Charge ist der Platzhalter der Butterkin, nicht die
-- Herkunft der Mandarin und Kabocha. Die App zog die ganzen 3.7 t von
-- Butterkin ab. Jede Mix-Zeile nennt ihr Gebinde (U-Gebinde, 8 kg).
--
-- Zur Position 134343 (18. September, „Bio-Kürbis Butterkin Demeter",
-- 1450 kg, Preisgruppe K: 1138 kg aus 1624 mit Lieferlabel K, 312 kg aus
-- 1612 mit Lieferlabel D): „weiterhin klar im Perigon-Reiter ausweisen —
-- so kann ich auf die Person zugehen, die fürs Perigon verantwortlich ist."
--
-- Und: „schau, dass das gesamte Perigon-Auszug angeschaut wird — teilweise
-- wurden rückblickend einzelne Zeilen angepasst." Das tut das Einlesen
-- (0055/0115/0130: neu, geändert, unverändert; in den Dateien vom 6./7.
-- November 64 Zeilen rückblickend geändert). Nur eine Position, die in
-- Perigon ganz gelöscht wurde, blieb: 0130 legt beiseite, was eine Position
-- der Datei nicht mehr hat — eine Position, die gar nicht mehr in der Datei
-- steht, galt als „ausserhalb der Datei".
--
-- WAS
--
-- 1. perigon_kg: bei Einheit kg ist die Menge das Gewicht — Gewicht je
--    Artikel zählt nur bei Stück. Dieselbe Regel wie perigonKg() in
--    src/lib/warenausgang.ts.
-- 2. ausgang_kg_gewicht_nachrechnen, einmal jetzt: Zeilen, Positionen und
--    Lieferungen von kg-Artikeln mit Gewicht je Artikel ≠ 0/1 nach der
--    neuen Regel (die Lieferung durch das Gewicht je Artikel — nur, solange
--    sie grösser ist als die ganze Position nach der neuen Regel; ein
--    zweiter Lauf ändert nichts).
-- 3. mix_rezept: je Sorte, wie viele Stück zu welchem Gewicht in einer
--    Mix-Kiste liegen, und welche Sorte die Kiste auffüllt; mit Herkunft.
--    Das Einlesen verteilt jede Mix-Zeile danach (Kisteninhalt aus der
--    Datei, nie angenommen). Der Teil der Sorte der genannten Charge bleibt
--    auf ihr; die anderen werden Lieferungen ohne Charge mit ihrer Sorte
--    (Kennung „…:mix:Sorte"). lieferung_import_zeilen_verbinden kennt sie.
-- 4. ausgang_positionen_geloescht: Positionen dieser Firma im Zeitraum der
--    Datei (von–bis), die die Datei gar nicht mehr hat, gehen beiseite
--    (Zeilen nach ausgang_zeile_frueher, Lieferungen weg). Fehlt mehr als
--    jede zehnte Position (mindestens 5), tut sie nichts und sagt es — dann
--    ist die Datei wohl gefiltert. Ohne die Liste der Positionen (ältere
--    App) tut sie nichts. ausgang_uebernehmen ruft sie auf.
-- 5. v_perigon_befund: neue Fälle kg_gewicht (kg-Artikel mit Gewicht ≠ 1),
--    label_gemischt (Chargen einer Position mit verschiedenen Lieferlabels —
--    mit Auftrag, Datum, Chargen und Labels), mix_verteilt (info: wie der
--    Mix verteilt ist); mix nur noch, wenn nicht verteilt; label_name nicht,
--    wenn label_gemischt.
--
-- WAS BEWUSST NICHT
--
-- - Keine Annahme für einen fehlenden Kisteninhalt: ohne ihn bleibt der Mix
--   auf der Charge und der Fall „mix" sagt es.
-- - ausgang_zeile_frueher wird nicht nachgerechnet: dort steht, was die App
--   damals hatte.
-- - ausgang_position (Vergleich mit den Vorjahren) behält gelöschte
--   Positionen: sie gehen nur aus der Bilanz dieser Saison.

-- =====================================================================
-- 1. Bei Einheit kg ist die Menge das Gewicht
-- =====================================================================
create or replace function perigon_kg(p_menge numeric, p_gewicht numeric, p_einheit text) returns numeric
language sql immutable set search_path = public as $$
  select case
           when p_menge is null then null
           when lower(btrim(coalesce(p_einheit, ''))) like 'kg%' then round(p_menge, 3)
           when coalesce(p_gewicht, 0) > 0 then round(p_menge * p_gewicht, 3)
         end
$$;
comment on function perigon_kg(numeric, numeric, text) is
  'Die Masse einer Perigon-Menge in kg (0115, 0131): bei Einheit kg die Menge selbst — das Gewicht je Artikel zählt '
  'dort nicht (Ünique: 10, sonst 1 oder 0); bei Stück Menge × Gewicht je Artikel; Stück ohne Stückgewicht unbekannt '
  '(null), nie 0. Dieselbe Regel wie perigonKg() in src/lib/warenausgang.ts.';
revoke all on function perigon_kg(numeric, numeric, text) from public;
grant execute on function perigon_kg(numeric, numeric, text) to authenticated;

-- =====================================================================
-- 2. Einmal jetzt: was nach der alten Regel × Gewicht je Artikel zählte
-- =====================================================================
create or replace function ausgang_kg_gewicht_nachrechnen() returns jsonb
language plpgsql security invoker set search_path = public as $fn$
declare v_l int; v_z int; v_p int;
begin
  -- zuerst die Lieferungen (die Zeile sagt, ob und womit), dann die Zeilen
  with falsch as (
    select l.id, l.kg, z.gewicht_je_artikel as g, perigon_kg(z.menge, z.gewicht_je_artikel, z.einheit) as pos_neu
      from lieferung l
      join lieferung_import i on i.lieferung_id = l.id
      join ausgang_zeile z on z.id = i.zeile_id
     where lower(btrim(coalesce(z.einheit, ''))) like 'kg%'
       and z.gewicht_je_artikel is not null and z.gewicht_je_artikel not in (0, 1)
  ), neu as (
    -- nur, solange die Lieferung grösser ist als die ganze Position nach der neuen Regel: ein zweiter Lauf ändert nichts
    update lieferung l set kg = round(f.kg / f.g, 2)
      from falsch f
     where l.id = f.id and f.kg > coalesce(f.pos_neu, 0) + 0.01
    returning 1
  )
  select count(*)::int into v_l from neu;

  update ausgang_zeile z
     set kg_position = perigon_kg(z.menge, z.gewicht_je_artikel, z.einheit),
         kg_charge   = perigon_kg(z.batch_menge, z.gewicht_je_artikel, z.einheit)
   where lower(btrim(coalesce(z.einheit, ''))) like 'kg%'
     and z.gewicht_je_artikel is not null and z.gewicht_je_artikel not in (0, 1)
     and (z.kg_position is distinct from perigon_kg(z.menge, z.gewicht_je_artikel, z.einheit)
          or z.kg_charge is distinct from perigon_kg(z.batch_menge, z.gewicht_je_artikel, z.einheit));
  get diagnostics v_z = row_count;

  update ausgang_position p
     set kg = perigon_kg(coalesce(p.menge, 0), p.gewicht_je_artikel, p.einheit)
   where lower(btrim(coalesce(p.einheit, ''))) like 'kg%'
     and p.gewicht_je_artikel is not null and p.gewicht_je_artikel not in (0, 1)
     and p.kg is distinct from perigon_kg(coalesce(p.menge, 0), p.gewicht_je_artikel, p.einheit);
  get diagnostics v_p = row_count;
  return jsonb_build_object('lieferungen', v_l, 'zeilen', v_z, 'positionen', v_p);
end $fn$;
comment on function ausgang_kg_gewicht_nachrechnen() is
  'Rechnet Lieferungen, Zeilen und Positionen von kg-Artikeln mit Gewicht je Artikel ≠ 0/1 nach der Regel von 0131 '
  '(die Menge ist das Gewicht): die Lieferung durch das Gewicht je Artikel, solange sie grösser ist als die ganze '
  'Position — ein zweiter Lauf ändert nichts. Einmal in 0131; schreiben darf nur der Betriebsleiter.';
revoke all on function ausgang_kg_gewicht_nachrechnen() from public;
grant execute on function ausgang_kg_gewicht_nachrechnen() to authenticated;

do $$
begin
  raise notice '0131: kg-Artikel mit Gewicht je Artikel ≠ 1 nachgerechnet — %', ausgang_kg_gewicht_nachrechnen();
end $$;

-- =====================================================================
-- 3. Woraus der Mix ist
-- =====================================================================
create table if not exists mix_rezept (
  id            bigint generated by default as identity primary key,
  artikelgruppe text    not null default 'Mix' check (btrim(artikelgruppe) <> ''),
  sorte         text    not null references sorte_kaliber(sorte) on update cascade,
  stueck        numeric(6,2)  check (stueck > 0),
  kg_je_stueck  numeric(8,3)  check (kg_je_stueck > 0),
  auffueller    boolean not null default false,
  quelle        text    not null check (btrim(quelle) <> ''),
  erfasser      uuid    references profil(id) on delete set null default auth.uid(),
  ts            timestamptz not null default now(),
  unique (artikelgruppe, sorte),
  check ((auffueller and stueck is null and kg_je_stueck is null)
      or (not auffueller and stueck is not null and kg_je_stueck is not null))
);
create unique index if not exists mix_rezept_ein_auffueller on mix_rezept (artikelgruppe) where auffueller;
comment on table mix_rezept is
  'Woraus eine Mix-Kiste ist (0131): je Sorte Stück und kg je Stück, und genau eine Sorte, die die Kiste bis zu ihrem '
  'Inhalt (Spalte „AuftragsGebindeinhalt" der Perigon-Datei) auffüllt. Das Einlesen verteilt danach jede Mix-Zeile auf '
  'die Sorten; ohne Kisteninhalt verteilt es nicht. quelle: woher Stückzahl und Gewicht kommen.';
comment on column mix_rezept.auffueller is
  'Die Sorte, die den Rest der Kiste füllt (Butterkin: 2 grosse oder 4–6 kleine) — ohne eigene Stückzahl.';

alter table mix_rezept enable row level security;
drop policy if exists mix_rezept_lesen on mix_rezept;
create policy mix_rezept_lesen on mix_rezept for select to authenticated using (true);
drop policy if exists mix_rezept_admin on mix_rezept;
create policy mix_rezept_admin on mix_rezept for all to authenticated
  using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on mix_rezept to authenticated;

-- Das Rezept des Betriebs (7. November). Gibt es eine Sorte nicht, fehlt ihre Zeile — keine Annahme.
insert into mix_rezept (artikelgruppe, sorte, stueck, kg_je_stueck, auffueller, quelle, erfasser)
select 'Mix', s.sorte, s.stueck, s.kg, s.auff, s.quelle, null
  from (values
    ('Orangita',  3::numeric, 0.55::numeric, false,
     'Betrieb, 7. November 2026: 3 Mandarin je Kiste (Mandarin = Orangita); 0.55 kg je Stück aus dem Perigon-Artikel „Bio Kürbis Mandarin Dem"'),
    ('Lekor',     3, 0.95, false,
     'Betrieb, 7. November 2026: 3 Kabocha je Kiste, „in den meisten Fällen kleine" (Kabocha = Lekor); 0.95 kg je Stück aus dem Perigon-Artikel „Bio Kürbis Kabocha klein"'),
    ('Butterkin', null, null, true,
     'Betrieb, 7. November 2026: Butterkin füllt die Kiste auf — 2 grosse oder 4–6 kleine')
  ) as s(sorte, stueck, kg, auff, quelle)
 where exists (select 1 from sorte_kaliber k where k.sorte = s.sorte)
on conflict (artikelgruppe, sorte) do nothing;

-- =====================================================================
-- 3b. Jede Lieferung kennt ihre Zeile — auch die Anteile eines Mix
-- =====================================================================
create or replace function lieferung_import_zeilen_verbinden(p_quelle text default null)
returns int language sql volatile set search_path = public as $$
  with charge_zeilen as (
    update lieferung_import i
       set zeile_id = z.id
      from ausgang_zeile z
     where i.zeile_id is null
       and (p_quelle is null or i.quelle = p_quelle)
       and z.quelle = i.quelle
       and (i.extern_id = z.quelle || ':' || z.pos_id || ':' || z.charge_extern || ':' || z.lauf_nr
            or i.extern_id like z.quelle || ':' || z.pos_id || ':' || z.charge_extern || ':' || z.lauf_nr || ':mix:%')
     returning 1
  ), rest_zeilen as (
    update lieferung_import i
       set zeile_id = z.id
      from (select distinct on (quelle, pos_id) id, quelle, pos_id
              from ausgang_zeile order by quelle, pos_id, lauf_nr, id) z
     where i.zeile_id is null
       and (p_quelle is null or i.quelle = p_quelle)
       and z.quelle = i.quelle
       and (i.extern_id = z.quelle || ':' || z.pos_id || ':rest'
            or i.extern_id like z.quelle || ':' || z.pos_id || ':rest:mix:%')
     returning 1
  )
  select (select count(*) from charge_zeilen) + (select count(*) from rest_zeilen)
$$;
comment on function lieferung_import_zeilen_verbinden(text) is
  'Trägt lieferung_import.zeile_id aus der Kennung nach (Chargenzeile oder erste '
  'Zeile der Position; seit 0131 auch die Anteile eines Mix, „…:mix:Sorte"). Läuft nach jeder Übernahme; einmal für alles Bestehende (0061).';
revoke all on function lieferung_import_zeilen_verbinden(text) from public;
grant execute on function lieferung_import_zeilen_verbinden(text) to authenticated;

-- =====================================================================
-- 4. Was Perigon gelöscht hat
-- =====================================================================
create or replace function ausgang_positionen_geloescht(p_quelle text, p_datei_id bigint, p_datei jsonb)
returns jsonb language plpgsql security invoker set search_path = public as $fn$
declare
  v_von date := nullif(p_datei ->> 'von_datum', '')::date;
  v_bis date := nullif(p_datei ->> 'bis_datum', '')::date;
  v_datei bigint[]; v_weg bigint[]; v_im_zeitraum int; v_fehlen int; v_l int := 0; v_z int := 0;
begin
  if p_datei -> 'alle_pos' is null or jsonb_typeof(p_datei -> 'alle_pos') <> 'array'
     or v_von is null or v_bis is null then
    return jsonb_build_object('positionen', 0, 'zeilen', 0, 'lieferungen', 0, 'grund', 'ohne Liste der Positionen');
  end if;
  v_datei := array(select distinct x::bigint from jsonb_array_elements_text(p_datei -> 'alle_pos') as x where x ~ '^[0-9]+$');
  select count(distinct z.pos_id)::int into v_im_zeitraum
    from ausgang_zeile z where z.quelle = p_quelle and z.datum between v_von and v_bis;
  v_weg := array(select distinct z.pos_id from ausgang_zeile z
                  where z.quelle = p_quelle and z.datum between v_von and v_bis
                    and not (z.pos_id = any(v_datei))
                  order by 1);
  v_fehlen := coalesce(cardinality(v_weg), 0);
  if v_fehlen = 0 then
    return jsonb_build_object('positionen', 0, 'zeilen', 0, 'lieferungen', 0);
  end if;
  if v_fehlen > greatest(5, v_im_zeitraum / 10) then
    return jsonb_build_object('positionen', 0, 'zeilen', 0, 'lieferungen', 0, 'fehlen', v_fehlen,
      'grund', format('%s von %s Positionen im Zeitraum fehlen in der Datei (z. B. %s) — so viele löscht niemand; die Datei ist wohl gefiltert. Nichts beiseitegelegt.',
                      v_fehlen, v_im_zeitraum, array_to_string(v_weg[1:10], ', ')));
  end if;

  -- zuerst die Lieferungen (sie zeigen auf die Zeilen), dann die Zeilen beiseite
  with weg as (
    delete from lieferung weg_l
     using lieferung_import i
     where i.lieferung_id = weg_l.id and i.quelle = p_quelle
       and split_part(i.extern_id, ':', 2) ~ '^[0-9]+$'
       and split_part(i.extern_id, ':', 2)::bigint = any(v_weg)
    returning 1
  ) select count(*)::int into v_l from weg;
  with weg as (
    delete from ausgang_zeile z
     where z.quelle = p_quelle and z.pos_id = any(v_weg)
    returning z.*
  ), abgelegt as (
    insert into ausgang_zeile_frueher select w.*, now(), p_datei_id from weg w returning 1
  ) select count(*)::int into v_z from abgelegt;
  return jsonb_build_object('positionen', v_fehlen, 'zeilen', v_z, 'lieferungen', v_l,
                            'liste', array_to_string(v_weg, ', '));
end $fn$;
comment on function ausgang_positionen_geloescht(text, bigint, jsonb) is
  'Positionen einer Firma im Zeitraum der Datei (p_datei.von_datum–bis_datum), die die Datei gar nicht mehr hat '
  '(p_datei.alle_pos: alle Positionsnummern der Datei, jeder Artikel): in Perigon gelöscht — ihre Lieferungen gehen weg, '
  'ihre Zeilen nach ausgang_zeile_frueher (0131). Fehlt mehr als jede zehnte Position (mindestens 5), nichts — die Datei '
  'ist wohl gefiltert; ohne alle_pos ebenso nichts. Gibt zurück, wie viele Positionen, Zeilen, Lieferungen. '
  'Aufgerufen von ausgang_uebernehmen; schreiben darf nur der Betriebsleiter (Regeln der Tabellen).';
revoke all on function ausgang_positionen_geloescht(text, bigint, jsonb) from public;
grant execute on function ausgang_positionen_geloescht(text, bigint, jsonb) to authenticated;

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
  v_geloescht    jsonb;
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

  -- 0131: Positionen, die im Zeitraum der Datei gar nicht mehr stehen, sind in
  -- Perigon gelöscht: ihre Zeilen gehen ebenso beiseite, ihre Lieferungen weg.
  v_geloescht := ausgang_positionen_geloescht(p_quelle, v_datei_id, p_datei);

  -- 0061: jede Lieferung dieser Quelle kennt ihre Zeile
  perform lieferung_import_zeilen_verbinden(p_quelle);

  return jsonb_build_object(
    'datei_id', v_datei_id,
    'zeilen_neu', v_zeilen_neu, 'zeilen_geaendert', v_zeilen_alt,
    'lieferungen_neu', v_lief_neu, 'lieferungen_aktualisiert', v_lief_alt,
    'lieferungen_ersetzt', v_ersetzt,
    'zeilen_beiseite', v_beiseite,
    'positionen_geloescht', v_geloescht,
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
  'die die Datei für ihre Positionen nicht mehr hat (nach ausgang_zeile_frueher); seit 0131 auch die Zeilen '
  'und Lieferungen von Positionen, die im Zeitraum der Datei gar nicht mehr stehen (in Perigon gelöscht). Positionen ausserhalb '
  'des Zeitraums bleiben. Gibt zurück, was neu, was aktualisiert, was ersetzt, was beiseitegelegt und was '
  'nicht übernommen wurde (mit Grund).';
revoke all on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) from public;
grant execute on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) to authenticated;

-- =====================================================================
-- 5. Der Reiter Perigon: kg-Gewicht, gemischte Labels, verteilter Mix
-- =====================================================================
create or replace view v_perigon_befund with (security_invoker = true) as
with zeile as (
  select z.id, z.quelle, z.pos_id, z.lauf_nr, z.datum, z.kunde, z.artikel_id, z.artikel, z.einheit, z.menge,
         z.gewicht_je_artikel, z.batch_menge, z.kg_position, z.kg_charge, z.preisgruppe, z.liefer_label, z.produzent, z.ts,
         z.auftragsnr,
         case when upper(coalesce(z.liefer_label, '')) like 'D%' then 'D'
              when upper(coalesce(z.liefer_label, '')) ~ '^(K|CH-K)' then 'K' end as label_z,
         nullif(btrim(z.charge_extern), '') as nummer,
         regexp_replace(coalesce(z.charge_extern, ''), '\D', '', 'g') as ziffern
    from ausgang_zeile z
), lief as (
  -- was die Rechnung aus der Position gemacht hat (ohne Rücknahmen)
  select i.quelle, split_part(i.extern_id, ':', 2)::bigint as pos_id,
         sum(l.kg) as kg, sum(l.kg) filter (where l.charge_nr is null) as kg_ohne,
         count(distinct l.charge_nr)::int as n_chargen, min(l.charge_nr) as charge_nr, min(l.sorte) as sorte
    from lieferung_import i
    join lieferung l on l.id = i.lieferung_id
   where split_part(i.extern_id, ':', 2) ~ '^\d+$' and i.extern_id not like '%:rueckgabe'
   group by 1, 2
), mixteil as (
  -- 0131: die Anteile eines Mix, die die App nach dem Rezept auf andere Sorten gelegt hat
  -- (Kennung „…:mix:Sorte" hinter der Kennung der Chargenzeile oder „…:rest")
  select i.quelle, split_part(i.extern_id, ':', 2)::bigint as pos_id,
         substring(i.extern_id from '^[^:]*:[0-9]+:(.*):mix:[^:]*$') as basis,
         string_agg(format('%s kg %s%s', kg_wort(l.kg), coalesce(l.sorte, 'ohne Sorte'),
                           case when l.charge_nr is null then ' (ohne Charge)' else ' auf Charge ' || l.charge_nr end),
                    ', ' order by l.sorte) as text,
         sum(l.kg) as kg
    from lieferung_import i
    join lieferung l on l.id = i.lieferung_id
   where i.extern_id like '%:mix:%' and split_part(i.extern_id, ':', 2) ~ '^\d+$'
   group by 1, 2, 3
), doppelt as (
  -- dieselbe Nummer mehrmals in derselben Position, mit derselben Menge
  select d.quelle, d.pos_id,
         string_agg(format('Charge %s %s', d.nummer, case d.n when 2 then 'zweimal' when 3 then 'dreimal' else d.n || '-mal' end), ', ' order by d.nummer) as text
    from (select quelle, pos_id, nummer, count(*)::int as n from zeile
           where nummer is not null group by 1, 2, 3 having count(*) > 1 and count(distinct batch_menge) = 1) d
   group by 1, 2
), pos as (
  select z.quelle, z.pos_id, min(z.datum) as datum, min(z.kunde) as kunde, min(z.artikel_id) as artikel_id, min(z.artikel) as artikel,
         min(z.einheit) as einheit, max(z.menge) as menge, max(z.gewicht_je_artikel) as gewicht_je_artikel,
         max(z.kg_position) as kg_position, min(z.preisgruppe) as preisgruppe, min(z.liefer_label) as liefer_label,
         min(z.ts) as eingelesen, min(z.auftragsnr) as auftragsnr,
         count(distinct z.label_z) filter (where z.nummer is not null and z.kg_charge > 0)::int as n_labels,
         string_agg(format('%s kg aus %s (%s)', kg_wort(z.kg_charge), z.nummer,
                           case z.label_z when 'D' then 'Demeter' when 'K' then 'Knospe' else coalesce(z.liefer_label, 'ohne Label') end),
                    ', ' order by z.kg_charge desc, z.nummer) filter (where z.nummer is not null and z.kg_charge > 0) as labels_text,
         count(*)::int as n_zeilen,
         count(z.nummer)::int as n_nummer,
         count(*) filter (where z.nummer is not null and z.kg_charge > 0)::int as n_menge,
         coalesce(sum(z.kg_charge) filter (where z.nummer is not null and z.kg_charge > 0), 0) as kg_zugeteilt,
         string_agg(distinct z.nummer, ', ' order by z.nummer) as nummern,
         string_agg(distinct z.nummer, ', ' order by z.nummer) filter (where coalesce(z.kg_charge, 0) <= 0) as nummern_ohne_menge
    from zeile z
   group by z.quelle, z.pos_id
), p as (
  select pos.*, f.kg as kg_rechnung, f.kg_ohne,
         case when f.n_chargen = 1 then f.charge_nr end as charge_nr,
         coalesce(f.sorte, aa.sorte) as sorte, d.text as doppelt,
         case when pos.nummern like '%,%' then 'die Chargen ' || pos.nummern else 'die Charge ' || pos.nummern end as chargen_text,
         case when lower(pos.artikel) ~ '(demeter|\mdem\M)' then 'D' when lower(pos.artikel) ~ 'knospe' then 'K' end as label_name,
         case when upper(coalesce(pos.preisgruppe, '')) like 'D%' then 'D'
              when upper(coalesce(pos.preisgruppe, '')) ~ '^(K|CH-K)' then 'K' end as label_preis
    from pos
    left join lief f on f.quelle = pos.quelle and f.pos_id = pos.pos_id
    left join ausgang_artikel aa on aa.artikel_id = pos.artikel_id and aa.artikel = pos.artikel
    left join doppelt d on d.quelle = pos.quelle and d.pos_id = pos.pos_id
), r as (
  -- jede Chargenzeile mit Menge, die eine Lieferung wurde
  select z.*, l.id as lieferung_id, l.charge_nr, l.kg as kg_lieferung, c.sorte, sk.artikelgruppe as gruppe_charge,
         e.gruppe as gruppe_artikel, e.label as label_verkauft,
         case when upper(coalesce(z.liefer_label, '')) like 'D%' then 'D'
              when upper(coalesce(z.liefer_label, '')) ~ '^(K|CH-K)' then 'K' end as label_geliefert,
         (select x.nr from charge x where z.ziffern <> '' and x.nr::text = z.ziffern) as eigene,
         (select array_agg(x.nr order by x.nr) from charge x where z.ziffern <> '' and x.perigon_nr::text = z.ziffern) as an_perigon,
         (select min(pl.eingangsdatum) from palette pl where pl.charge_nr = l.charge_nr) as erster_eingang
    from zeile z
    join lieferung_import i on i.zeile_id = z.id and i.extern_id not like '%:rest' and i.extern_id not like '%:rueckgabe'
                           and i.extern_id not like '%:mix:%'
    join lieferung l on l.id = i.lieferung_id
    left join charge c on c.nr = l.charge_nr
    left join sorte_kaliber sk on sk.sorte = c.sorte
   -- artikel_einordnen gibt genau eine Zeile; der Planer schätzt sonst 1000 je
   -- Aufruf, hält die Sicht für teuer und übersetzt sie mit JIT (3 s statt 45 ms).
   cross join lateral (select * from artikel_einordnen(z.artikel, z.preisgruppe) limit 1) e
   where z.nummer is not null and coalesce(z.kg_charge, 0) > 0
), fall as (
  -- ---- Position: was die Spalten Q, S, W, AE zusammen sagen ----
  select 'menge_null'::text as art, p.quelle, p.pos_id, null::text as nummer, null::int as lauf_nr, p.charge_nr, p.sorte,
         case when p.kg_position > 0 then p.kg_position end as kg,
         case when p.kg_position > 0
              then format('Perigon nennt %s, teilt aber keine Menge zu: Spalte S („AufPosBatchQuantity Charge") ist 0. Die Position hat %s kg (Spalte Q × AE) — sie bleibt ganz ohne Charge.',
                          p.chargen_text, kg_wort(p.kg_position))
              else format('Perigon nennt %s, aber die Position hat keine Menge — Spalte Q und Spalte S sind 0. Sie zählt nirgends; ging Ware hinaus, fehlt sie im Warenausgang.',
                          p.chargen_text) end as satz,
         'In Perigon bei dieser Position die Menge (Spalte Q) und die Menge je Charge (Spalte S) eintragen, dann die Datei unter Betrieb → Warenausgang neu einlesen.' as tun,
         'perigon' as wo
    from p where p.n_nummer > 0 and p.n_menge = 0
     and (p.kg_position > 0 or (coalesce(p.kg_position, 0) = 0 and coalesce(p.menge, 0) = 0))
  union all
  select 'zu_viel', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, p.kg_zugeteilt - p.kg_position,
         format('Die Chargenzeilen geben zusammen %s kg (Spalte S × AE), die Position nur %s kg (Spalte Q × AE) — %s kg zu viel.%s Die App zählt höchstens die Position: %s.',
                kg_wort(p.kg_zugeteilt), kg_wort(p.kg_position), kg_wort(p.kg_zugeteilt - p.kg_position),
                case when p.doppelt is not null then format(' Dieselbe Zeile steht mehrfach da (%s).', p.doppelt) else '' end,
                case when p.nummern like '%,%' then 'die Chargen bekommen ihre Menge in der Folge der Zeilen, bis die Position voll ist — wie viel welche bekam, sagt die Datei nicht sicher'
                     else format('%s bekommt die %s kg der Position', p.chargen_text, kg_wort(p.kg_position)) end),
         'In Perigon die Menge je Charge (Spalte S) berichtigen — zusammen so viel wie die Position —, eine doppelte Zeile entfernen, dann neu einlesen.',
         'perigon'
    from p where p.kg_position > 0 and p.kg_zugeteilt > p.kg_position + 0.5
  union all
  select 'rest', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, p.kg_position - p.kg_zugeteilt,
         format('Perigon teilt %s nur %s von %s kg zu (Spalte S); %s kg bleiben ohne Charge.%s', p.chargen_text,
                kg_wort(p.kg_zugeteilt), kg_wort(p.kg_position), kg_wort(p.kg_position - p.kg_zugeteilt),
                case when p.nummern_ohne_menge is not null then format(' Ohne Menge genannt: %s.', p.nummern_ohne_menge) else '' end),
         'In Perigon die Menge je Charge (Spalte S) nachtragen, dann neu einlesen. Bis dahin verteilt die App den Rest auf alle Chargen der Sorte.',
         'perigon'
    from p where p.n_menge > 0 and p.kg_position - p.kg_zugeteilt > 0.5
  union all
  select 'keine_nummer', p.quelle, p.pos_id, null, null, null::int, p.sorte, p.kg_position,
         format('In Perigon steht bei dieser Position keine Chargennummer (Spalte W „AuftragsChargeManuell" ist leer) — %s kg ohne Charge.', kg_wort(p.kg_position)),
         'In Perigon die Charge (Spalte W) und die Menge je Charge (Spalte S) eintragen, dann neu einlesen. Bis dahin verteilt die App die Menge auf alle Chargen der Sorte.',
         'perigon'
    from p where p.n_nummer = 0 and p.kg_position > 0
  union all
  select 'ohne_gewicht', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, null::numeric,
         format('%s %s ohne Gewicht je Artikel (Spalte AE ist leer oder 0) — die Masse ist unbekannt; die App zählt die Position nicht, statt 0 kg zu raten.',
                trim(to_char(p.menge, 'FM999999990.###')), coalesce(p.einheit, 'Stück')),
         'In Perigon das Gewicht je Artikel (Spalte AE) eintragen, dann neu einlesen.',
         'perigon'
    from p where p.kg_position is null and coalesce(p.menge, 0) <> 0
  union all
  select 'ruecknahme', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, -p.kg_position,
         format('Negative Menge (%s kg): eine Rücknahme. Die App bucht sie als Rücknahme, nicht als Verkauf.', kg_wort(p.kg_position)),
         'Nichts in der App. Prüfen, ob die Ware wirklich zurückkam.',
         'nichts'
    from p where p.kg_position < 0
  union all
  select 'masse_abweichung', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, coalesce(p.kg_rechnung, 0) - p.kg_position,
         case when p.kg_rechnung is null
              then format('Die Position steht in der Datei (%s kg), aber in der Rechnung gibt es keine Lieferung dazu.', kg_wort(p.kg_position))
              else format('In der Rechnung stehen für diese Position %s kg, die Datei ergibt %s kg — %s kg %s.', kg_wort(p.kg_rechnung), kg_wort(p.kg_position),
                          kg_wort(abs(p.kg_rechnung - p.kg_position)), case when p.kg_rechnung > p.kg_position then 'zu viel' else 'zu wenig' end) end,
         'Die Datei unter Betrieb → Warenausgang neu einlesen: die App legt an, was fehlt, und entfernt, was die Datei nicht mehr ergibt. Eine von Hand geänderte Lieferung bekommt dabei wieder die Masse der Datei.',
         'einlesen'
    from p where p.kg_position > 0 and abs(coalesce(p.kg_rechnung, 0) - p.kg_position) > 0.05
  union all
  select 'label_name', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, p.kg_position,
         format('Der Artikel heisst „%s" (%s), verkauft wurde er in der Preisgruppe %s (%s). Die App nimmt die Preisgruppe.', p.artikel,
                case p.label_name when 'D' then 'Demeter' else 'Knospe' end, p.preisgruppe, case p.label_preis when 'D' then 'Demeter' else 'Knospe' end),
         'In Perigon Artikel oder Preisgruppe angleichen — was stimmt, weiss, wer den Auftrag erfasst hat.',
         'perigon'
    from p where p.label_name is not null and p.label_preis is not null and p.label_name <> p.label_preis
     and coalesce(p.n_labels, 0) <= 1
  union all
  -- 0131: in einer Position Chargen mit verschiedenen Lieferlabels (Betrieb, 7. November, Position 134343)
  select 'label_gemischt', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, p.kg_position,
         format('Auftrag %s vom %s: unter dem Artikel „%s" (Preisgruppe %s) gingen Chargen mit verschiedenen Lieferlabels hinaus — %s. Knospe-Ware unter einem Demeter-Namen, oder umgekehrt?',
                coalesce(nullif(p.auftragsnr, ''), '?'), to_char(p.datum, 'DD.MM.YYYY'), p.artikel, coalesce(p.preisgruppe, '—'), p.labels_text),
         'Mit der Person klären, die den Auftrag in Perigon erfasst hat: stimmt der Artikel für alle Chargen? Sonst in Perigon den Artikel aufteilen oder die Charge (Spalte W) berichtigen, dann neu einlesen.',
         'perigon'
    from p where p.n_labels > 1
  union all
  -- 0131: ein kg-Artikel mit Gewicht je Artikel ≠ 1 (Ünique, Betrieb 7. November: Faktor 10)
  select 'kg_gewicht', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, p.kg_position,
         format('Perigon führt „%s" in kg, aber mit Gewicht je Artikel %s (Spalte AE). Die Menge (Spalte Q, %s kg) ist schon das Gewicht; Perigon rechnet das Totalgewicht trotzdem × %s (%s kg). Die App nimmt die Menge.',
                p.artikel, trim(to_char(p.gewicht_je_artikel, 'FM999990.###')), kg_wort(p.menge),
                trim(to_char(p.gewicht_je_artikel, 'FM999990.###')), kg_wort(p.menge * p.gewicht_je_artikel)),
         'Im Perigon-Artikelstamm beim Artikel das Gewicht je Artikel (Spalte AE) auf 1 setzen. In der App ist nichts zu tun — sie zählt schon die Menge.',
         'perigon'
    from p where lower(btrim(coalesce(p.einheit, ''))) like 'kg%' and p.gewicht_je_artikel is not null
     and p.gewicht_je_artikel not in (0, 1)
  -- ---- Chargenzeile: was die Nummer in Spalte W sagt ----
  union all
  select case when r.eigene is not null or cardinality(r.an_perigon) = 1 then 'nachholen'
              when cardinality(r.an_perigon) > 1 then 'mehrdeutig' else 'unbekannt' end,
         r.quelle, r.pos_id, r.nummer, r.lauf_nr, null::int, null::text, r.kg_lieferung,
         case when r.eigene is not null or cardinality(r.an_perigon) = 1
              then format('Perigon nennt %s; die Nummer steht inzwischen an Charge %s — beim Einlesen kannte die App sie noch nicht.', r.nummer, coalesce(r.eigene, r.an_perigon[1]))
              when cardinality(r.an_perigon) > 1
              then format('Perigon nennt %s; diese Perigon-Nummer steht an mehreren Chargen (%s), und der Artikel sagt nicht, an welcher.', r.nummer, array_to_string(r.an_perigon, ', '))
              else format('Perigon nennt %s — diese Nummer steht an keiner Charge der App.', r.nummer) end,
         case when r.eigene is not null or cardinality(r.an_perigon) = 1
              then 'Nichts — beim nächsten Rechnen („Neu rechnen" oben) bekommt der Lieferschein die Charge von selbst.'
              when cardinality(r.an_perigon) > 1
              then 'Unter Betrieb → Stammdaten → Chargen die Nummer nur bei der richtigen Charge lassen; beim nächsten Rechnen bekommt der Lieferschein sie.'
              else 'Unter Betrieb → Stammdaten → Chargen bei der richtigen Charge als Perigon-Nr. eintragen; beim nächsten Rechnen bekommt der Lieferschein sie von selbst. Ist die Nummer ein Tippfehler, in Perigon berichtigen.' end,
         case when r.eigene is not null or cardinality(r.an_perigon) = 1 then 'nichts' else 'stammdaten' end
    from r where r.charge_nr is null
  union all
  select 'artikel_sorte', r.quelle, r.pos_id, r.nummer, r.lauf_nr, r.charge_nr, r.sorte, r.kg_lieferung,
         format('Verkauft als %s („%s"), aber die Charge %s ist %s — und %s geht als %s. Entweder steht der falsche Artikel oder die falsche Charge auf dem Lieferschein.',
                r.gruppe_artikel, r.artikel, r.charge_nr, r.sorte, r.sorte, r.gruppe_charge),
         'Den Lieferschein ansehen: ist der Artikel falsch, in Perigon den Artikel berichtigen; ist die Charge falsch, die Charge (Spalte W) — dann neu einlesen.',
         'perigon'
    from r where r.charge_nr is not null and r.gruppe_artikel is not null and r.gruppe_charge is not null
     and r.gruppe_artikel not in ('Mix', 'andere') and r.gruppe_artikel <> r.gruppe_charge
  union all
  select 'demeter_knospe', r.quelle, r.pos_id, r.nummer, r.lauf_nr, r.charge_nr, r.sorte, r.kg_lieferung,
         format('Verkauft zum Demeter-Preis (Preisgruppe %s), aber die Ware der Charge %s trägt das Lieferlabel %s — das ist Knospe.', r.preisgruppe, r.charge_nr, r.liefer_label),
         'In Perigon Preisgruppe (Spalte K) und Lieferlabel (Spalte Z) prüfen: wurde Knospe als Demeter verrechnet, oder stimmt das Label nicht?',
         'perigon'
    from r where r.charge_nr is not null and r.label_verkauft = 'D' and r.label_geliefert = 'K'
  union all
  select 'mix', r.quelle, r.pos_id, r.nummer, r.lauf_nr, r.charge_nr, r.sorte, r.kg_lieferung,
         format('Verkauft als „%s" auf Charge %s (%s). Die App hat den Mix nicht nach dem Rezept verteilt (in der Datei fehlt der Kisteninhalt, Spalte „AuftragsGebindeinhalt", oder es gibt kein Rezept) — sie zieht die ganzen %s kg von %s ab.',
                r.artikel, r.charge_nr, r.sorte, kg_wort(r.kg_lieferung), r.charge_nr),
         'Fehlt der Kisteninhalt, in Perigon nachtragen und neu einlesen; fehlt das Rezept, unter Betrieb → Stammdaten → Sorten und Artikel (Kürbis Mix) eintragen. Gehört der Mix zu einer anderen Charge, in Perigon die Charge (Spalte W) berichtigen.',
         'firma'
    from r where r.charge_nr is not null and r.gruppe_artikel = 'Mix'
     and not exists (select 1 from mixteil m where m.quelle = r.quelle and m.pos_id = r.pos_id and m.basis = r.nummer || ':' || r.lauf_nr)
  union all
  -- 0131: nach dem Rezept verteilt — zur Nachvollziehbarkeit, kein Fehler
  select 'mix_verteilt', r.quelle, r.pos_id, r.nummer, r.lauf_nr, r.charge_nr, r.sorte, r.kg_lieferung + m.kg,
         format('„%s" (%s kg) nach dem Mix-Rezept verteilt: %s kg auf Charge %s (%s), dazu %s.',
                r.artikel, kg_wort(r.kg_lieferung + m.kg), kg_wort(r.kg_lieferung), r.charge_nr, r.sorte, m.text),
         'Nichts. Das Rezept steht unter Betrieb → Stammdaten → Sorten und Artikel (Kürbis Mix); stimmt es nicht mehr, dort berichtigen und neu einlesen.',
         'nichts'
    from r join mixteil m on m.quelle = r.quelle and m.pos_id = r.pos_id and m.basis = r.nummer || ':' || r.lauf_nr
   where r.gruppe_artikel = 'Mix'
  union all
  select 'vor_eingang', r.quelle, r.pos_id, r.nummer, r.lauf_nr, r.charge_nr, r.sorte, r.kg_lieferung,
         format('Geliefert am %s, aber die Charge %s kam laut Erntejournal erst am %s an (%s Tage später) — von ihr kann die Ware nicht sein.',
                to_char(r.datum, 'DD.MM.YYYY'), r.charge_nr, to_char(r.erster_eingang, 'DD.MM.YYYY'), r.erster_eingang - r.datum),
         'Entweder steht die falsche Charge auf dem Lieferschein (in Perigon Spalte W berichtigen) oder das Eingangsdatum im Erntejournal stimmt nicht.',
         'perigon'
    from r where r.charge_nr is not null and r.erster_eingang is not null and r.datum < r.erster_eingang
)
select f.art || ':' || f.quelle || ':' || f.pos_id || coalesce(':' || f.nummer || ':' || f.lauf_nr, '') as schluessel,
       f.art,
       case when f.art in ('nachholen', 'ruecknahme', 'mix_verteilt') then 'info'
            when f.art in ('menge_null', 'keine_nummer', 'rest', 'unbekannt', 'mehrdeutig', 'vor_eingang', 'artikel_sorte', 'masse_abweichung')
                 and abs(coalesce(f.kg, 0)) >= 500 then 'rot'
            else 'gelb' end as schwere,
       f.quelle, f.pos_id, p.datum, p.kunde, p.artikel, p.einheit,
       zahl(p.menge, 3, 1e12)::numeric(14,3) as menge,
       zahl(p.gewicht_je_artikel, 4, 1e8)::numeric(12,4) as gewicht_je_artikel,
       p.preisgruppe, p.liefer_label,
       zahl(p.kg_position, 2, 1e12)::numeric(14,2) as kg_position,
       zahl(p.kg_zugeteilt, 2, 1e12)::numeric(14,2) as kg_zugeteilt,
       zahl(p.kg_rechnung, 2, 1e12)::numeric(14,2) as kg_rechnung,
       zahl(p.kg_ohne, 2, 1e12)::numeric(14,2) as kg_ohne_charge,
       zahl(f.kg, 2, 1e12)::numeric(14,2) as kg,
       p.nummern, f.nummer, f.lauf_nr, coalesce(f.charge_nr, p.charge_nr) as charge_nr, coalesce(f.sorte, p.sorte) as sorte,
       p.n_zeilen, f.satz, f.tun, f.wo, p.eingelesen
  from fall f
  join p on p.quelle = f.quelle and p.pos_id = f.pos_id;
comment on view v_perigon_befund is
  'Jeder Fall einer Perigon-Position (0126), je mit einem Schlüssel, der von Rechnen zu Rechnen gleich bleibt (art:quelle:pos_id[:nummer:lauf]). Position: menge_null (Chargen genannt, Spalte S = 0 — auch Q = 0), zu_viel (Chargenzeilen > Position, z.B. dieselbe Zeile mehrfach), rest (Chargenzeilen < Position), keine_nummer (Spalte W leer), ohne_gewicht (Stück ohne Gewicht je Artikel, Masse unbekannt), ruecknahme (negative Menge), masse_abweichung (Lieferungen der Rechnung ≠ Masse der Datei), label_name (Artikelname gegen Preisgruppe), label_gemischt (Chargen mit verschiedenen Lieferlabels, 0131), kg_gewicht (kg-Artikel mit Gewicht je Artikel ≠ 1, 0131). Chargenzeile: nachholen (Nummer inzwischen bekannt), mehrdeutig, unbekannt, artikel_sorte, demeter_knospe, mix (Kürbis Mix auf einer Charge, nicht verteilt), mix_verteilt (nach Rezept verteilt, info, 0131), vor_eingang. kg: die Masse, um die es geht (nie 0 statt unbekannt); satz, tun und wo (perigon, stammdaten, einlesen, firma, nichts). Löst v_perigon_pruefung ab, die stehen bleibt.';
grant select on v_perigon_befund to authenticated;

-- =====================================================================
-- 6. Schemastand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 131 $$;
