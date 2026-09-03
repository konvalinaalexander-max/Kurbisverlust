-- =====================================================================
-- 0038 — Das Sortierschema hängt am Käufer, nicht an der Sorte
--
-- Vom Betrieb am 2. September klargestellt: Coop will es anders als Migros,
-- und dieselbe Sorte läuft je nach Bestellung mit „Kiste ab x kg" oder mit
-- Kaliberbändern. Die Kaliber-Grenzen sind damit keine Eigenschaft der Sorte
-- mehr, sondern eine Eigenschaft von (Sorte × Käufer) zu einem Zeitpunkt.
--
-- Bisher standen die Grenzen als ein Wert je Sorte in sorte_kaliber. Wer sie
-- dort ändert, klassiert damit rückwirkend jede je eingelesene CSV neu — die
-- Datei vom Oktober mit den Grenzen vom Januar. Der gemessene Ausschussanteil
-- ändert sich, ohne dass ein einziger Kürbis anders gewogen wurde. Das ist die
-- Regel 1 aus docs/Datenarchitektur: Kontext muss datiert sein.
--
-- Deshalb:
--   * sortierschema: je (Sorte × Käufer) eine Fassung mit gilt_ab. Geändert
--     wird nie eine Zeile — es kommt eine neue dazu.
--   * kaeufer: Coop, Migros und was sonst dazukommt. Die Arbeiter legen neue
--     selbst an; das ist Teil der Erfassung, kein Stammdaten-Pflegefall.
--   * Jeder Auftrag hält fest, mit welcher Fassung gearbeitet wurde
--     (sortierschema_id), jeder Sortierlauf ebenso. Die Klassierung liest
--     diese Fassung, nicht „die aktuelle". Reproduzierbar, auch wenn beim
--     nächsten Mal anders sortiert wird.
--
-- sorte_kaliber bleibt die Sortenliste (an ihr hängen Chargen und Fremd-
-- schlüssel); ihre Grenzen-Spalten sind ab jetzt nur noch der Ausgangswert,
-- aus dem beim Einrichten die erste Standard-Fassung je Sorte entsteht.
-- =====================================================================

create table if not exists kaeufer (
  code      text primary key,
  name      text not null,
  aktiv     boolean not null default true,
  erfasser  uuid references profil(id) default auth.uid(),
  ts        timestamptz not null default now()
);
comment on table kaeufer is
  'Abnehmer, für die sortiert wird. Ein Käufer bestimmt das Sortierschema. '
  'code ist kurz und stabil (coop, migros); name ist die Anzeige.';

create table if not exists sortierschema (
  id                bigserial primary key,
  sorte             text not null references sorte_kaliber(sorte) on update cascade,
  kaeufer           text references kaeufer(code),          -- NULL = Standard, ohne bestimmten Käufer
  gilt_ab           date not null default current_date,
  art               text not null default 'kaliber' check (art in ('kaliber', 'kiste')),
  verlust_unter     int,                                     -- art = kaliber
  kaliber_baender   jsonb,                                   -- [[von, bis), …]
  kanal_ab          int,
  soll_kg_pro_kiste numeric(6,2),                            -- art = kiste
  bemerkung         text,
  erfasser          uuid references profil(id) default auth.uid(),
  ts                timestamptz not null default now(),
  constraint sortierschema_kaliber_vollstaendig
    check (art <> 'kaliber' or (verlust_unter is not null and kaliber_baender is not null
                                and kanal_ab is not null)),
  constraint sortierschema_kiste_vollstaendig
    check (art <> 'kiste' or soll_kg_pro_kiste is not null),
  constraint sortierschema_baender_liste
    check (kaliber_baender is null or jsonb_typeof(kaliber_baender) = 'array')
);
comment on table sortierschema is
  'Eine datierte Fassung der Sortierregeln je Sorte und Käufer. Nie ändern, '
  'nur eine neue Fassung mit späterem gilt_ab anlegen — sonst ändert sich '
  'rückwirkend jede Klassierung, die je darauf beruhte.';
comment on column sortierschema.art is
  'kaliber: Bänder in Gramm, unter verlust_unter ist zu klein, ab kanal_ab zu '
  'gross. kiste: Kiste ab soll_kg_pro_kiste, Gewicht der Stücke egal.';

create unique index if not exists sortierschema_eindeutig
  on sortierschema (sorte, coalesce(kaeufer, ''), gilt_ab);
create index if not exists sortierschema_suche on sortierschema (sorte, kaeufer, gilt_ab desc);

-- Die erste Fassung je Sorte: der bisherige Stand aus sorte_kaliber, gültig
-- „seit immer". Nur, wo noch keine Fassung existiert — beim Aktualisieren
-- bleibt alles stehen, was der Betrieb inzwischen angelegt hat.
insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab,
                           bemerkung, erfasser)
select sk.sorte, null, date '2000-01-01', 'kaliber', sk.verlust_unter, sk.kaliber_baender,
       sk.kanal_ab, 'Ausgangswert aus der Spezifikation (§6)', null
  from sorte_kaliber sk
 where not exists (select 1 from sortierschema s where s.sorte = sk.sorte and s.kaeufer is null);

comment on column sorte_kaliber.kaliber_baender is
  'Nur noch der Ausgangswert für die erste Standard-Fassung in sortierschema. '
  'Klassiert wird nach sortierschema, nicht nach dieser Spalte.';

-- ---------- Welche Fassung gilt? -------------------------------------------
create or replace function sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date)
returns bigint language sql stable as $$
  select coalesce(
    -- die Fassung dieses Käufers, die am Stichtag galt
    (select id from sortierschema
      where sorte = p_sorte and kaeufer is not distinct from p_kaeufer and gilt_ab <= p_datum
      order by gilt_ab desc limit 1),
    -- sonst die Standard-Fassung
    (select id from sortierschema
      where sorte = p_sorte and kaeufer is null and gilt_ab <= p_datum
      order by gilt_ab desc limit 1),
    -- sonst irgendeine Standard-Fassung (Datum vor jeder Fassung)
    (select id from sortierschema
      where sorte = p_sorte and kaeufer is null
      order by gilt_ab limit 1));
$$;
comment on function sortierschema_fuer is
  'Die Fassung, die für Sorte und Käufer an einem Tag galt. Ohne passende '
  'Käufer-Fassung gilt der Standard der Sorte.';

-- ---------- Klassierung nach einer Fassung ---------------------------------
create or replace function klassiere(p_schema_id bigint, p_gewicht_g int)
returns table (klasse kuerbis_klasse, kaliber_idx int)
language sql stable as $$
  with k as (select * from sortierschema where id = p_schema_id),
       band as (
         select (ord - 1)::int as idx
         from k, jsonb_array_elements(k.kaliber_baender) with ordinality as b(grenzen, ord)
         where k.art = 'kaliber'
           and p_gewicht_g >= (grenzen->>0)::int
           and p_gewicht_g <  (grenzen->>1)::int
         order by ord limit 1
       )
  select case
           when (select count(*) from k) = 0                 then 'unklassiert'::kuerbis_klasse
           -- Kiste ab x kg: das Stückgewicht spielt keine Rolle, alles ist
           -- Hauptkanal. Zu klein und zu gross werden dort nach Augenmass
           -- erfasst, nicht aus der CSV.
           when (select art from k) = 'kiste'                then 'kaliber'::kuerbis_klasse
           when p_gewicht_g <  (select verlust_unter from k) then 'verlust_klein'::kuerbis_klasse
           when p_gewicht_g >= (select kanal_ab       from k) then 'nebenkanal'::kuerbis_klasse
           when (select count(*) from band) = 1               then 'kaliber'::kuerbis_klasse
           else 'unklassiert'::kuerbis_klasse
         end,
         (select idx from band);
$$;

-- Die alte Signatur bleibt: Sorte → Standard-Fassung von heute. Für Tests,
-- Simulation und alles, was keinen Käufer kennt.
create or replace function klassiere(p_sorte text, p_gewicht_g int)
returns table (klasse kuerbis_klasse, kaliber_idx int)
language sql stable as $$
  select * from klassiere(sortierschema_fuer(p_sorte, null, current_date), p_gewicht_g);
$$;

-- ---------- Auftrag und Sortierlauf halten ihre Fassung fest ---------------
alter table auftrag add column if not exists kaeufer text references kaeufer(code);
alter table auftrag add column if not exists sortierschema_id bigint references sortierschema(id);
comment on column auftrag.sortierschema_id is
  'Die Fassung der Sortierregeln, mit der diese Arbeit lief — beim Anlegen aus '
  'Sorte, Käufer und Datum festgehalten. Ändert sich das Schema später, bleibt '
  'die Arbeit reproduzierbar.';

alter table sortier_lauf add column if not exists sortierschema_id bigint references sortierschema(id);
comment on column sortier_lauf.sortierschema_id is
  'Die Fassung, nach der dieser Lauf klassiert ist. Aus dem Auftrag, sonst der '
  'Standard der Sorte zum Zeitpunkt der Datei.';

-- Beim Anlegen einer Arbeit die Fassung festhalten, falls die App keine nennt.
create or replace function auftrag_schema_setzen()
returns trigger language plpgsql as $$
begin
  if new.sortierschema_id is null then
    select sortierschema_fuer(c.sorte, new.kaeufer, new.start_ts::date) into new.sortierschema_id
      from charge c where c.nr = new.charge_nr;
  end if;
  return new;
end $$;
revoke execute on function auftrag_schema_setzen() from public;
drop trigger if exists auftrag_schema on auftrag;
create trigger auftrag_schema before insert on auftrag
  for each row execute function auftrag_schema_setzen();

-- Bestehende Arbeiten bekommen die Standard-Fassung ihres Starttags.
update auftrag a
   set sortierschema_id = sortierschema_fuer(c.sorte, a.kaeufer, a.start_ts::date)
  from charge c
 where c.nr = a.charge_nr and a.sortierschema_id is null;

-- Bestehende Läufe: die Fassung des zugeordneten Auftrags, sonst der Standard
-- zum Dateidatum. Die Klasse je Gewichtsstufe wurde mit genau diesen Grenzen
-- gebildet (es gab keine anderen), also muss nichts neu klassiert werden.
update sortier_lauf l
   set sortierschema_id = coalesce(
         (select a.sortierschema_id from auftrag a where a.id = l.auftrag_id),
         sortierschema_fuer(c.sorte, null, coalesce(l.datei_zeit, l.gelesen_ts)::date))
  from charge c
 where c.nr = l.charge_nr and l.sortierschema_id is null;

-- ---------- Einen Lauf (neu) klassieren ------------------------------------
create or replace function lauf_neu_klassieren(p_lauf_id bigint)
returns int language plpgsql as $$
declare v_schema bigint; v_n int;
begin
  -- Die Fassung: vom Auftrag, sonst vom Lauf, sonst der Standard der Sorte
  -- zum Dateidatum.
  select coalesce(a.sortierschema_id, l.sortierschema_id,
                  sortierschema_fuer(c.sorte, null, coalesce(l.datei_zeit, l.gelesen_ts)::date))
    into v_schema
    from sortier_lauf l
    join charge c on c.nr = l.charge_nr
    left join auftrag a on a.id = l.auftrag_id
   where l.id = p_lauf_id;

  update sortier_lauf set sortierschema_id = v_schema where id = p_lauf_id;

  -- Fund beim Prüfen: Die Fassung aus 0004 schrieb „from klassiere(v_sorte,
  -- g.gewicht_g)" — ein Verweis auf die Zieltabelle in der FROM-Liste, den
  -- Postgres ablehnt („invalid reference to FROM-clause entry"). Die Funktion
  -- wurde nie aufgerufen, kein Test hat sie je ausgeführt, und das README
  -- empfahl sie dem Betriebsleiter nach jeder Grenzen-Änderung. Sie hätte
  -- jedes Mal mit einem Fehler geendet.
  with neu as (
    select sg.gewicht_g, k.klasse, k.kaliber_idx
      from sortier_gewicht sg
      cross join lateral klassiere(v_schema, sg.gewicht_g) k
     where sg.lauf_id = p_lauf_id
  )
  update sortier_gewicht g
     set klasse = neu.klasse, kaliber_idx = neu.kaliber_idx
    from neu
   where g.lauf_id = p_lauf_id and g.gewicht_g = neu.gewicht_g;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ---------- CSV aufnehmen: erst zuordnen, dann nach der Fassung klassieren --
create or replace function csv_lauf_speichern(
  p_charge_nr         int,
  p_datei_name        text,
  p_roh_datei_ref     text,
  p_roh_pruefsumme    text,
  p_datei_zeit        timestamptz,
  p_datei_zeit_quelle text,
  p_reinigung         jsonb,
  p_n_roh             int,
  p_n_overflow        int,
  p_n_klein           int,
  p_n_dubletten       int,
  p_histogramm        jsonb
) returns bigint language plpgsql as $$
declare
  v_lauf_id bigint;
  v_gueltig int;
begin
  select coalesce(sum((e->>1)::int), 0) into v_gueltig
    from jsonb_array_elements(p_histogramm) e;

  insert into sortier_lauf (charge_nr, datei_name, roh_datei_ref, roh_pruefsumme,
                            datei_zeit, datei_zeit_quelle, reinigung,
                            n_roh, n_overflow, n_klein, n_dubletten, n_gueltig)
  values (p_charge_nr, p_datei_name, p_roh_datei_ref, p_roh_pruefsumme,
          p_datei_zeit, p_datei_zeit_quelle, p_reinigung,
          p_n_roh, p_n_overflow, p_n_klein, p_n_dubletten, v_gueltig)
  returning id into v_lauf_id;

  -- Das Histogramm zunächst unklassiert ablegen; die Klasse folgt der Fassung,
  -- und die hängt am Auftrag — also erst zuordnen.
  insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
  select v_lauf_id, (e->>0)::int, (e->>1)::int, 'unklassiert', null
    from jsonb_array_elements(p_histogramm) e;

  perform auftrag_zuordnen(v_lauf_id);
  perform lauf_neu_klassieren(v_lauf_id);
  return v_lauf_id;
end $$;

-- Wer von Hand zuordnet, ordnet vielleicht einem Auftrag mit anderem Käufer zu
-- — dann gilt dessen Fassung, und der Lauf wird neu klassiert.
create or replace function auftrag_manuell_zuordnen(p_lauf_id bigint, p_auftrag_id bigint)
returns void language plpgsql as $$
begin
  update sortier_lauf
     set auftrag_id = p_auftrag_id,
         zuordnung  = case when p_auftrag_id is null then 'offen'::zuordnung_status
                            else 'manuell'::zuordnung_status end,
         sortierschema_id = null
   where id = p_lauf_id;
  perform lauf_neu_klassieren(p_lauf_id);
end $$;

-- ---------- Kaliber-Verteilung nach der Fassung des Laufs ------------------
drop materialized view if exists mv_kaliber_verteilung cascade;
create materialized view mv_kaliber_verteilung as
select l.charge_nr, c.sorte, g.klasse, g.kaliber_idx,
       (s.kaliber_baender -> g.kaliber_idx ->> 0)::int as band_von,
       (s.kaliber_baender -> g.kaliber_idx ->> 1)::int as band_bis,
       sum(g.anzahl)                                                 as n_kuerbis,
       (sum(g.anzahl::bigint * g.gewicht_g) / 1000.0)::numeric(12,2) as masse_kg
  from sortier_gewicht g
  join sortier_lauf l on l.id = g.lauf_id
  join charge c on c.nr = l.charge_nr
  left join sortierschema s on s.id = l.sortierschema_id
 group by l.charge_nr, c.sorte, g.klasse, g.kaliber_idx,
          (s.kaliber_baender -> g.kaliber_idx ->> 0)::int,
          (s.kaliber_baender -> g.kaliber_idx ->> 1)::int;

create unique index if not exists mv_kaliber_pk
  on mv_kaliber_verteilung (charge_nr, klasse, coalesce(kaliber_idx, -1), coalesce(band_von, -1));

create or replace view v_kaliber_verteilung with (security_invoker = true) as
select * from mv_kaliber_verteilung;

-- ---------- Die fertige Palette: Soll aus der Fassung, sonst Einstellung ---
create or replace view v_ausgang_kennzahl with (security_invoker = true) as
select w.id, w.auftrag_id, w.charge_nr, c.sorte, c.schlag, w.ts,
       w.brutto_kg, w.kisten, w.gebindeart, w.kuerbisse_pro_kiste,
       n.netto_kg,
       (n.netto_kg / w.kisten)::numeric(10,3)                       as kg_pro_kiste,
       (n.netto_kg / nullif(w.kisten * w.kuerbisse_pro_kiste, 0))::numeric(10,3)
                                                                    as kg_pro_kuerbis,
       s.soll                                                       as soll_kg_pro_kiste,
       ((n.netto_kg / w.kisten) - s.soll)::numeric(10,3)            as ueberfuellung_je_kiste,
       (n.netto_kg - w.kisten * s.soll)::numeric(10,2)              as ueberfuellung_kg
  from ausgang_wiegung w
  join auftrag a on a.id = w.auftrag_id
  join charge c on c.nr = w.charge_nr
  left join gebinde g on g.art = w.gebindeart
  left join sortierschema ss on ss.id = a.sortierschema_id
  cross join lateral (
        select (w.brutto_kg - w.kisten * g.tara_kg_pro_kiste
                - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_kg
       ) n
  cross join lateral (
        -- Das Soll je Kiste: aus der Fassung des Auftrags, wenn sie eine
        -- Kisten-Fassung ist, sonst die allgemeine Einstellung.
        select coalesce(case when ss.art = 'kiste' then ss.soll_kg_pro_kiste end,
                        (select (wert #>> '{}')::numeric from einstellung
                          where schluessel = 'soll_kg_pro_kiste'), 8) as soll
       ) s
 where w.gemessen and a.abgebrochen_ts is null and n.netto_kg > 0;

-- ---------- Rechte ---------------------------------------------------------
alter table kaeufer enable row level security;
alter table sortierschema enable row level security;
drop policy if exists kaeufer_lesen on kaeufer;
drop policy if exists kaeufer_anlegen on kaeufer;
drop policy if exists kaeufer_aendern on kaeufer;
create policy kaeufer_lesen on kaeufer for select to authenticated using (true);
-- Die Arbeiter legen neue Käufer selbst an — das ist Teil der Erfassung.
create policy kaeufer_anlegen on kaeufer for insert to authenticated
  with check (ist_aktiv() or ist_admin());
create policy kaeufer_aendern on kaeufer for update to authenticated using (ist_admin());

drop policy if exists sortierschema_lesen on sortierschema;
drop policy if exists sortierschema_anlegen on sortierschema;
drop policy if exists sortierschema_aendern on sortierschema;
drop policy if exists sortierschema_loeschen on sortierschema;
create policy sortierschema_lesen on sortierschema for select to authenticated using (true);
-- Neue Fassungen darf jeder Angemeldete anlegen (vor Ort ändern, Spec-Rück-
-- meldung 1. September). Ändern und Löschen bleibt dem Betriebsleiter — und
-- auch der soll lieber eine neue Fassung anlegen.
create policy sortierschema_anlegen on sortierschema for insert to authenticated
  with check (ist_aktiv() or ist_admin());
create policy sortierschema_aendern on sortierschema for update to authenticated using (ist_admin());
create policy sortierschema_loeschen on sortierschema for delete to authenticated using (ist_admin());

grant select, insert on kaeufer to authenticated;
grant update on kaeufer to authenticated;
grant select, insert, update, delete on sortierschema to authenticated;
grant usage, select on sequence sortierschema_id_seq to authenticated;
grant select on mv_kaliber_verteilung, v_kaliber_verteilung, v_ausgang_kennzahl to authenticated;

revoke execute on function sortierschema_fuer(text, text, date), klassiere(bigint, int),
                          klassiere(text, int), lauf_neu_klassieren(bigint),
                          csv_lauf_speichern(int, text, text, text, timestamptz, text, jsonb,
                                             int, int, int, int, jsonb),
                          auftrag_manuell_zuordnen(bigint, bigint) from public;
grant execute on function sortierschema_fuer(text, text, date), klassiere(bigint, int),
                          klassiere(text, int), lauf_neu_klassieren(bigint),
                          csv_lauf_speichern(int, text, text, text, timestamptz, text, jsonb,
                                             int, int, int, int, jsonb),
                          auftrag_manuell_zuordnen(bigint, bigint) to authenticated;

-- Änderungen an Käufern und Fassungen betreffen die Auswertung.
drop trigger if exists sortierschema_veraltet on sortierschema;
create trigger sortierschema_veraltet after insert or update or delete on sortierschema
  for each statement execute function auswertung_veraltet();
