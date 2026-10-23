-- =====================================================================
-- Kürbis-Verlust-Tracking — setup.sql: das komplette Setup in einer Datei
--
-- ERZEUGT. Nicht von Hand ändern — Quelle ist supabase/migrations/*.sql,
-- gebaut von supabase/setup_bauen.sh.
--
-- SO WIRD SIE BENUTZT
--   1. Diese Datei komplett markieren und kopieren (Strg+A, Strg+C).
--   2. Im Supabase-Dashboard links auf "SQL Editor".
--   3. In das grosse leere Feld einfügen (Strg+V).
--   4. Unten rechts auf "Run" klicken.
-- Das war alles. Keine weitere Datei.
--
-- DIESELBE DATEI AKTUALISIERT AUCH
--
-- Sie richtet nicht nur ein, sie bringt eine bestehende Datenbank ebenso
-- auf den neuesten Stand — gleiche Datei, gleiche vier Handgriffe. Die
-- Daten bleiben dabei stehen; erneuert wird nur, was die Datenbank aus
-- ihnen ausrechnet. Alles läuft in einer Transaktion, es gibt also kein
-- halb Aktualisiertes: entweder ganz durch, oder alles wie vorher.
--
-- Unten im Ergebnisfenster muss danach eine Zeile stehen, die mit
-- "Fertig." beginnt und die Anzahl Chargen und Sorten nennt.
--
-- WIE SIE AUFGEBAUT IST
--
-- Teil A ist die Geschichte: Tabellen, Spalten, Bedingungen, Rechte und die
-- Nachträge an den Daten, Migration für Migration. Jeder Schritt zählt —
-- eine Datenbank, die seit dem Frühjahr läuft, wird genau durch sie auf den
-- heutigen Stand gebracht.
--
-- Teil B ist das Rechenwerk: die Ansichten und die Funktionen, die auf ihnen
-- rechnen. Das ist keine Geschichte, sondern ein Zustand — es zählt nur, wie
-- die Formel heute lautet. Jede steht deshalb genau einmal.
--
-- Das ist nicht nur ordentlicher, es war nötig: Aneinandergereiht ergaben die
-- Migrationen 1,14 MB, und der SQL-Editor nimmt höchstens 1 MB ("Query is too
-- large to be run via the SQL Editor"). Über die Hälfte davon waren Fassungen
-- von Formeln, die eine spätere Migration ohnehin überschreibt.
-- =====================================================================

-- Nur Warnungen und Fehler anzeigen.
--
-- Diese Datei räumt vor jedem Anlegen auf ("drop ... if exists"), damit sie
-- auf einer leeren wie auf einer bestehenden Datenbank läuft. Auf einer
-- leeren gibt es nichts wegzuräumen, und Postgres sagt das jedes Mal:
-- "materialized view ... does not exist, skipping". Das sind über hundert
-- Zeilen, die aussehen wie eine Wand von Problemen und keines sind. Sie
-- bleiben hier unsichtbar; was wirklich schiefgeht, kommt als WARNING oder
-- ERROR durch und ist dann auch zu sehen.
set client_min_messages = warning;

-- Nie warten, nie hängen (Runde AG, 28. September).
--
-- Diese Datei räumt das Rechenwerk weg und baut es neu. Dafür braucht sie
-- auf jeder gespeicherten Ansicht eine Sperre — und trifft sie auf eine
-- laufende Rechnung (Zeitplan, „Neu rechnen"), müsste sie warten, bis die
-- fertig ist: bis zu zwei Minuten, länger als der SQL-Editor wartet. Der
-- Editor gibt dann auf („Load failed"), und die Sitzung hier blockiert mit
-- ihren halb gehaltenen Sperren alles, was die App liest. Darum: Eine
-- laufende Rechnung wird beendet (sie ist eine Transaktion, es geht nichts
-- verloren, der Zeitplan holt sie nach), und auf keine Sperre wird länger
-- als 20 Sekunden gewartet — lieber ein klarer Fehler („canceling statement
-- due to lock timeout": zwei Minuten später nochmals Run) als eine Sitzung,
-- die die Datenbank festhält, bis jemand das Projekt neu startet.
--
-- Seit 0103 nimmt diese Datei dazu selbst die Sperre der Rechnung
-- (Beratungssperre, bis zum Ende der Transaktion): Ein Lauf des Zeitplans,
-- der währenddessen tickt, sieht sie besetzt und geht sofort, statt auf
-- eine halb gebaute Ansicht zu treffen. Und ein Rest von „rechnet gerade"
-- (rechnet_seit) einer eben beendeten Rechnung wird gelöst, damit „Neu
-- rechnen" nicht eine Viertelstunde auf einen Lauf wartet, den es nicht
-- mehr gibt.
set lock_timeout = '20s';
do $$
declare r record; v_n int := 0;
begin
  for r in select pid from pg_stat_activity
            where datname = current_database() and pid <> pg_backend_pid()
              and state <> 'idle'
              and (query ~* 'auswertung_(schritt|wenn_veraltet|aktualisieren|sofort_lauf)'
                   or query ilike '%refresh materialized view%')
              and query not ilike '%setup.sql%'
  loop
    begin
      if pg_terminate_backend(r.pid) then v_n := v_n + 1; end if;
    exception when others then null;
    end;
  end loop;
  if v_n > 0 then
    raise warning 'setup.sql: % laufende Rechnung(en) beendet, damit die Einrichtung nicht auf sie wartet — der Zeitplan rechnet nach.', v_n;
  end if;
  perform pg_advisory_xact_lock(hashtext('auswertung_schritt'));
  if to_regclass('public.auswertung_stand') is not null then
    execute 'update public.auswertung_stand set rechnet_seit = null where id = 1 and rechnet_seit is not null';
  end if;
exception when others then
  raise notice 'setup.sql: laufende Rechnungen nicht prüfbar (%)', sqlerrm;
end $$;

-- =====================================================================
-- TEIL A — Tabellen, Daten, Rechte: die Geschichte
-- =====================================================================


-- aus 0000_aktualisierung.sql

do $$
declare
  z record;
begin
  -- Kein Kürbis-Schema vorhanden? Dann ist das eine Neueinrichtung und es
  -- gibt nichts wegzuräumen.
  if to_regclass('public.charge') is null then
    return;
  end if;

  raise notice 'Bestehende Datenbank erkannt — das Rechenwerk wird erneuert, die Daten bleiben.';

  -- 1. Zugriffsregeln. Zuerst, weil sie auf Funktionen wie ist_admin()
  --    zeigen; solange sie stehen, lässt sich die Funktion nicht löschen.
  for z in
    select p.polname, c.relname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
  loop
    execute format('drop policy if exists %I on public.%I', z.polname, z.relname);
  end loop;

  -- 2. Auslöser auf den eigenen Tabellen und der eine auf auth.users, der
  --    neuen Anmeldungen ein Profil gibt.
  for z in
    select t.tgname, c.relname, n.nspname
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where not t.tgisinternal
       and (n.nspname = 'public'
            or (n.nspname = 'auth' and t.tgname = 'on_auth_user_created'))
  loop
    execute format('drop trigger if exists %I on %I.%I', z.tgname, z.nspname, z.relname);
  end loop;

  -- 3. Gespeicherte Auswertungen und Ansichten. Erst die gespeicherten
  --    (relkind 'm'), dann die berechneten — `cascade` räumt mit, was
  --    aufeinander aufbaut, und setup.sql baut die Kette danach neu.
  --    Das Namensmuster v_ / mv_ ist die Konvention des Projekts; was
  --    jemand von Hand daneben angelegt hat, bleibt stehen.
  for z in
    select c.relname, c.relkind
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind in ('v', 'm')
       and c.relname ~ '^m?v_'
     order by case c.relkind when 'm' then 0 else 1 end
  loop
    if z.relkind = 'm' then
      execute format('drop materialized view if exists public.%I cascade', z.relname);
    else
      execute format('drop view if exists public.%I cascade', z.relname);
    end if;
  end loop;

  -- 4. Funktionen. Zum Schluss, wenn niemand mehr auf sie zeigt. Auch die
  --    Signatur muss weg und nicht nur der Name: 0032 hat aus
  --    palox_letzter_stand() eines mit Argument gemacht, und zwei
  --    Funktionen gleichen Namens verwirren PostgREST.
  for z in
    select p.oid::regprocedure::text as sig, p.prokind
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p')
  loop
    execute format('drop %s if exists %s cascade',
                   case z.prokind when 'p' then 'procedure' else 'function' end,
                   z.sig);
  end loop;
end $$;

-- aus 0001_schema.sql

do $$
begin
  if to_regtype('rolle') is null then
    create type rolle as enum ('admin', 'arbeiter');
  end if;
  if to_regtype('verarbeitungsweg') is null then
    create type verarbeitungsweg as enum ('maschine', 'hand');   -- Weg 1 / Weg 2
  end if;
  if to_regtype('station') is null then
    create type station as enum ('sortieren', 'waschen', 'waschen_sortieren');
  end if;
  if to_regtype('auftrag_status') is null then
    create type auftrag_status as enum ('offen', 'abgeschlossen');
  end if;
  if to_regtype('kuerbis_klasse') is null then
    create type kuerbis_klasse as enum ('verlust_klein', 'kaliber', 'nebenkanal', 'unklassiert');
  end if;
  if to_regtype('marge_art') is null then
    create type marge_art as enum ('nebenkanal', 'ueberfuellung');
  end if;
  if to_regtype('ausschuss_art') is null then
    create type ausschuss_art as enum ('zu_klein', 'zu_gross');
  end if;
  if to_regtype('zuordnung_status') is null then
    create type zuordnung_status as enum ('auto', 'manuell', 'offen', 'mehrdeutig');
  end if;
end $$;

create table if not exists profil (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null,
  rolle      rolle not null default 'arbeiter',
  aktiv      boolean not null default true,
  erstellt_ts timestamptz not null default now()
);
comment on table profil is
  'Ein Profil je Login. Der erste Benutzer muss per SQL auf rolle=''admin'' gesetzt werden — siehe README.';

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profil (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create table if not exists gebinde (
  art               text primary key,
  tara_kg_pro_kiste numeric(6,3),
  tara_kg_palette   numeric(6,3),
  bemerkung         text
);
comment on column gebinde.tara_kg_pro_kiste is
  'Leergewicht einer Kiste. NULL bedeutet "nicht erfasst" — Netto bleibt dann NULL statt falsch zu sein.';

create table if not exists sorte_kaliber (
  sorte           text primary key,
  verlust_unter   int  not null,
  kaliber_baender jsonb not null,
  kanal_ab        int  not null default 2000,
  constraint kaliber_baender_ist_liste check (jsonb_typeof(kaliber_baender) = 'array')
);
comment on table sorte_kaliber is
  'Kaliber-Grenzen in Gramm. Die Anzahl Bänder variiert je Sorte (2–4) und ist bewusst nicht fix.';

create table if not exists charge (
  nr     int primary key,
  schlag text not null,
  sorte  text not null references sorte_kaliber(sorte) on update cascade,
  saison int  not null,
  unique (schlag, sorte, saison)
);
comment on table charge is
  'Charge = Schlag × Sorte. Die Chargennummer ist der Join-Schlüssel des gesamten Systems.';

create table if not exists palette (
  id            bigserial primary key,
  charge_nr     int  not null references charge(nr),
  eingangsdatum date not null,
  brutto_kg     numeric(8,2) not null,
  kisten        int,
  gebindeart    text references gebinde(art) on update cascade,
  extern_id     text unique,
  quelle        text not null default 'journal-import',
  erfasst_ts    timestamptz not null default now()
);
comment on column palette.extern_id is
  'Stabile ID der Sheet-Zeile. Verhindert Doppel-Import; ein erneuter Import aktualisiert dieselbe Zeile.';

create index if not exists palette_charge_nr_eingangsdatum_idx on palette (charge_nr, eingangsdatum);

create table if not exists auftrag (
  id                bigserial primary key,
  weg               verarbeitungsweg not null,
  station           station not null,
  charge_nr         int not null references charge(nr),
  start_ts          timestamptz not null default now(),
  ende_ts           timestamptz,
  geplante_paletten int,
  status            auftrag_status not null default 'offen',
  eroeffnet_von     uuid not null default auth.uid() references profil(id),
  durchsatz_kg      numeric(10,2),
  bemerkung         text,
  constraint ende_nach_start check (ende_ts is null or ende_ts >= start_ts)
);
comment on column auftrag.durchsatz_kg is
  'Verarbeitete Menge, falls keine Paletten gezählt werden können. Nötig beim Waschen '
  'auf Weg 1: dort sind die Original-Paletten längst in Kaliber-Kisten aufgelöst, es gibt '
  'also keine Palettenzahl mehr — ohne diese Angabe hat der dort gemessene Schimmel #2 '
  'keinen Nenner. Leer lassen, wenn Paletten gezählt wurden.';
create index if not exists auftrag_charge_nr_start_ts_idx on auftrag (charge_nr, start_ts);
create index if not exists auftrag_status_start_ts_idx on auftrag (status, start_ts desc);

create table if not exists auftrag_teilnehmer (
  id             bigserial primary key,
  auftrag_id     bigint not null references auftrag(id) on delete cascade,
  profil_id      uuid   not null default auth.uid() references profil(id),
  beigetreten_ts timestamptz not null default now(),
  verlassen_ts   timestamptz
);
create unique index if not exists auftrag_teilnehmer_aktiv
  on auftrag_teilnehmer (auftrag_id, profil_id) where verlassen_ts is null;

create table if not exists auftrag_palette (
  id            bigserial primary key,
  auftrag_id    bigint not null references auftrag(id) on delete cascade,
  palette_id    bigint references palette(id),
  eingangsdatum date,
  erfasser      uuid not null default auth.uid() references profil(id),
  ts            timestamptz not null default now()
);
create index if not exists auftrag_palette_auftrag_id_idx on auftrag_palette (auftrag_id);

create table if not exists schimmel_messung (
  id          bigserial primary key,
  auftrag_id  bigint not null references auftrag(id) on delete cascade,
  kg          int not null check (kg >= 0),
  teilgewicht boolean not null default false,
  gemessen    boolean not null default true,
  erfasser    uuid not null default auth.uid() references profil(id),
  ts          timestamptz not null default now(),
  bemerkung   text
);
create index if not exists schimmel_messung_auftrag_id_idx on schimmel_messung (auftrag_id);

create table if not exists ausschuss_messung (
  id         bigserial primary key,
  auftrag_id bigint not null references auftrag(id) on delete cascade,
  art        ausschuss_art not null,
  kg         int not null check (kg >= 0),
  gemessen   boolean not null default true,
  erfasser   uuid not null default auth.uid() references profil(id),
  ts         timestamptz not null default now(),
  bemerkung  text
);
create index if not exists ausschuss_messung_auftrag_id_art_idx on ausschuss_messung (auftrag_id, art);

create table if not exists verdunstung_wiegung (
  id                bigserial primary key,
  auftrag_id        bigint references auftrag(id) on delete set null,
  charge_nr         int  not null references charge(nr),
  palette_id        bigint references palette(id),
  eingangsdatum     date not null,
  brutto_damals_kg  numeric(8,2) not null,
  brutto_jetzt_kg   numeric(8,2) not null,
  kisten            int,
  gebindeart        text references gebinde(art) on update cascade,
  sichtbar_schimmel boolean not null default false,
  gemessen          boolean not null default true,
  erfasser          uuid not null default auth.uid() references profil(id),
  wiege_ts          timestamptz not null default now(),
  ts                timestamptz not null default now(),
  bemerkung         text
);
create index if not exists verdunstung_wiegung_charge_nr_eingangsdatum_idx on verdunstung_wiegung (charge_nr, eingangsdatum);

create table if not exists marge_messung (
  id         bigserial primary key,
  auftrag_id bigint not null references auftrag(id) on delete cascade,
  art        marge_art not null,
  wert       numeric(10,3) not null,
  einheit    text not null default 'kg',
  n_kisten   int,
  gemessen   boolean not null default true,
  erfasser   uuid not null default auth.uid() references profil(id),
  ts         timestamptz not null default now(),
  bemerkung  text
);
create index if not exists marge_messung_auftrag_id_art_idx on marge_messung (auftrag_id, art);

create table if not exists sortier_lauf (
  id                bigserial primary key,
  charge_nr         int references charge(nr),
  datei_name        text not null,
  roh_datei_ref     text,
  roh_pruefsumme    text unique,
  datei_zeit        timestamptz,
  datei_zeit_quelle text,
  auftrag_id        bigint references auftrag(id) on delete set null,
  zuordnung         zuordnung_status not null default 'offen',
  reinigung         jsonb not null,
  n_roh             int not null,
  n_overflow        int not null,
  n_klein           int not null,
  n_dubletten       int not null,
  n_gueltig         int not null,
  hochgeladen_von   uuid not null default auth.uid() references profil(id),
  gelesen_ts        timestamptz not null default now()
);
create index if not exists sortier_lauf_charge_nr_datei_zeit_idx on sortier_lauf (charge_nr, datei_zeit);
create index if not exists sortier_lauf_zuordnung_idx on sortier_lauf (zuordnung) where zuordnung in ('offen', 'mehrdeutig');

create table if not exists sortier_gewicht (
  lauf_id     bigint not null references sortier_lauf(id) on delete cascade,
  gewicht_g   int    not null,
  anzahl      int    not null check (anzahl > 0),
  klasse      kuerbis_klasse not null,
  kaliber_idx int,
  primary key (lauf_id, gewicht_g)
);
create index if not exists sortier_gewicht_lauf_id_klasse_idx on sortier_gewicht (lauf_id, klasse);

create table if not exists einstellung (
  schluessel text primary key,
  wert       jsonb not null,
  bemerkung  text
);

-- aus 0002_rls.sql

create or replace function public.ist_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profil where id = auth.uid() and rolle = 'admin' and aktiv);
$$;

create or replace function public.korrekturfenster()
returns interval language sql immutable as $$ select interval '12 hours' $$;

create or replace function public.ist_beteiligt(p_auftrag_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from auftrag a
                  where a.id = p_auftrag_id and a.eroeffnet_von = auth.uid())
      or exists (select 1 from auftrag_teilnehmer t
                  where t.auftrag_id = p_auftrag_id and t.profil_id = auth.uid());
$$;

alter table profil              enable row level security;
alter table gebinde             enable row level security;
alter table sorte_kaliber       enable row level security;
alter table charge              enable row level security;
alter table palette             enable row level security;
alter table auftrag             enable row level security;
alter table auftrag_teilnehmer  enable row level security;
alter table auftrag_palette     enable row level security;
alter table schimmel_messung    enable row level security;
alter table ausschuss_messung   enable row level security;
alter table verdunstung_wiegung enable row level security;
alter table marge_messung       enable row level security;
alter table sortier_lauf        enable row level security;
alter table sortier_gewicht     enable row level security;
alter table einstellung         enable row level security;

create policy profil_lesen  on profil for select to authenticated using (true);
create policy profil_eigen  on profil for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profil_admin  on profil for all to authenticated
  using (ist_admin()) with check (ist_admin());

create or replace function public.rolle_schuetzen()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- auth.uid() ist NULL, wenn direkt per SQL gearbeitet wird (Supabase-SQL-Editor,
  -- Migration). Das ist der vorgesehene Weg, den allerersten Betriebsleiter zu
  -- ernennen. Über die App liegt immer ein Login vor, dort greift die Prüfung.
  if new.rolle is distinct from old.rolle and auth.uid() is not null and not ist_admin() then
    raise exception 'Die Rolle darf nur der Betriebsleiter ändern.';
  end if;
  return new;
end $$;

drop trigger if exists profil_rolle_schuetzen on profil;
create trigger profil_rolle_schuetzen
  before update on profil
  for each row execute function public.rolle_schuetzen();

do $$
declare t text;
begin
  foreach t in array array['gebinde', 'sorte_kaliber', 'charge', 'palette', 'einstellung'] loop
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_lesen', t);
    execute format('create policy %I on %I for all to authenticated using (ist_admin()) with check (ist_admin())',
                   t || '_admin', t);
  end loop;
end $$;

create policy auftrag_lesen on auftrag for select to authenticated using (true);
create policy auftrag_eroeffnen on auftrag for insert to authenticated
  with check (eroeffnet_von = auth.uid());

create policy auftrag_aendern on auftrag for update to authenticated
  using (ist_admin() or (status = 'offen' and ist_beteiligt(id)))
  with check (ist_admin() or ist_beteiligt(id));
create policy auftrag_loeschen on auftrag for delete to authenticated using (ist_admin());

create policy teilnehmer_lesen on auftrag_teilnehmer for select to authenticated using (true);
create policy teilnehmer_beitreten on auftrag_teilnehmer for insert to authenticated
  with check (profil_id = auth.uid() or ist_admin());
create policy teilnehmer_aendern on auftrag_teilnehmer for update to authenticated
  using (profil_id = auth.uid() or ist_admin());
create policy teilnehmer_admin on auftrag_teilnehmer for delete to authenticated using (ist_admin());

do $$
declare t text;
begin
  foreach t in array array['auftrag_palette', 'schimmel_messung', 'ausschuss_messung',
                           'verdunstung_wiegung', 'marge_messung'] loop
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_lesen', t);
    execute format('create policy %I on %I for insert to authenticated with check (erfasser = auth.uid() or ist_admin())',
                   t || '_erfassen', t);
    execute format('create policy %I on %I for update to authenticated using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()))',
                   t || '_korrigieren', t);
    execute format('create policy %I on %I for delete to authenticated using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()))',
                   t || '_zuruecknehmen', t);
  end loop;
end $$;

create policy lauf_lesen on sortier_lauf for select to authenticated using (true);
create policy lauf_admin on sortier_lauf for all to authenticated
  using (ist_admin()) with check (ist_admin());

create policy gewicht_lesen on sortier_gewicht for select to authenticated using (true);
create policy gewicht_admin on sortier_gewicht for all to authenticated
  using (ist_admin()) with check (ist_admin());

insert into storage.buckets (id, name, public)
values ('rohdaten', 'rohdaten', false)
on conflict (id) do nothing;

drop policy if exists rohdaten_lesen     on storage.objects;
drop policy if exists rohdaten_schreiben on storage.objects;

create policy rohdaten_lesen on storage.objects for select to authenticated
  using (bucket_id = 'rohdaten');
create policy rohdaten_schreiben on storage.objects for insert to authenticated
  with check (bucket_id = 'rohdaten' and ist_admin());

-- aus 0003_stammdaten.sql

insert into einstellung (schluessel, wert, bemerkung) values
  ('saison_aktuell',   '2026'::jsonb,
   'Erntesaison, auf die sich Chargen und Auswertung beziehen.'),
  ('saison_ende',      '"2027-03-31"'::jsonb,
   'Stichtag der Hochrechnung: bis dahin wird die Lagerdauer projiziert.'),
  ('zuordnung_fenster_h', '12'::jsonb,
   'Zeitfenster (Stunden) um die Dateizeit, in dem nach einem passenden Auftrag gesucht wird.'),
  ('reinigung_standard',
   '{"overflow_ab": 60000, "min_gramm": 100, "dubletten_zusammenfassen": true}'::jsonb,
   'Voreinstellung der CSV-Reinigung (Spec §4). Pro Lauf umstellbar; die tatsächlich '
   'verwendeten Parameter stehen in sortier_lauf.reinigung.')
on conflict (schluessel) do nothing;

insert into sorte_kaliber (sorte, verlust_unter, kaliber_baender, kanal_ab) values
  ('Orangita',      300, '[[300,800],[800,2000]]',                        2000),
  ('Kaori Kuri',    600, '[[600,1100],[1100,1600],[1600,2000]]',          2000),
  ('Mieluna',       500, '[[500,800],[800,1300],[1300,1800],[1800,2000]]', 2000),
  ('Amoro',         600, '[[600,1100],[1100,1600],[1600,2000]]',          2000),
  ('Butterkin',     500, '[[500,600],[600,1200],[1200,1800],[1800,2000]]', 2000),
  ('Bolp 5110',     600, '[[600,1100],[1100,1600],[1600,2000]]',          2000),
  ('Orange Summer', 600, '[[600,1100],[1100,1600],[1600,2000]]',          2000),
  ('Lekor',         700, '[[700,1200],[1200,1700],[1700,2000]]',          2000),
  ('Fictor',        600, '[[600,1100],[1100,1600],[1600,2000]]',          2000),
  ('Tiana',         500, '[[500,800],[800,1300],[1300,1800],[1800,2000]]', 2000),
  ('Ker Madec',     600, '[[600,1100],[1100,1600],[1600,2000]]',          2000)
on conflict (sorte) do update
  set verlust_unter   = excluded.verlust_unter,
      kaliber_baender = excluded.kaliber_baender,
      kanal_ab        = excluded.kanal_ab;

insert into charge (nr, schlag, sorte, saison) values
  (1598, 'Illnau Bruno',    'Kaori Kuri',    2026),
  (1599, 'Illnau Bruno',    'Orangita',      2026),
  (1601, 'Illnau Bruno',    'Mieluna',       2026),
  (1603, 'Illnau Gross',    'Bolp 5110',     2026),
  (1604, 'Illnau Gross',    'Orangita',      2026),
  (1605, 'Illnau Gross',    'Orange Summer', 2026),
  (1606, 'Illnau Gross',    'Lekor',         2026),
  (1607, 'Illnau Gross',    'Amoro',         2026),
  (1608, 'Illnau Gross',    'Butterkin',     2026),
  (1609, 'Illnau Gross',    'Kaori Kuri',    2026),
  (1610, 'Illnau Gross',    'Fictor',        2026),
  (1611, 'Negi Thalheim',   'Tiana',         2026),
  (1612, 'Slowgrow Uster',  'Butterkin',     2026),
  (1613, 'Slowgrow Uster',  'Tiana',         2026),
  (1614, 'Slowgrow Uster',  'Kaori Kuri',    2026),
  (1615, 'Slowgrow Uster',  'Ker Madec',     2026),
  (1616, 'Slowgrow Uster',  'Lekor',         2026),
  (1617, 'Slowgrow Uster',  'Orangita',      2026),
  (1618, 'Slowgrow Uster',  'Orange Summer', 2026),
  (1619, 'Gossau Eberhard', 'Kaori Kuri',    2026),
  (1620, 'Gossau Eberhard', 'Orangita',      2026),
  (1623, 'Agasul Rüegg',    'Mieluna',       2026),
  (1624, 'Agasul Rüegg',    'Butterkin',     2026),
  (1625, 'Agasul Rüegg',    'Amoro',         2026),
  (1626, 'Agasul Rüegg',    'Tiana',         2026),
  (1627, 'Agasul Rüegg',    'Fictor',        2026),
  (1628, 'Agasul Baumann',  'Kaori Kuri',    2026),
  (1630, 'Rümlang Keller',  'Kaori Kuri',    2026),
  (1631, 'Rümlang Keller',  'Mieluna',       2026),
  (1632, 'Andi Ball',       'Tiana',         2026),
  (1633, 'Daniel Böhler',   'Tiana',         2026),
  (1634, 'Daniel Böhler',   'Amoro',         2026),
  (1635, 'Daniel Böhler',   'Kaori Kuri',    2026),
  (1636, 'Klaus Böhler',    'Tiana',         2026),
  (1637, 'Klaus Böhler',    'Amoro',         2026),
  (1638, 'Klaus Böhler',    'Kaori Kuri',    2026),
  (1646, 'Gossau Eberhard', 'Butterkin',     2026),
  (1647, 'Bonomo',          'Tiana',         2026),
  (1648, 'Russikon BundB',  'Orange Summer', 2026),
  (1649, 'Rümlang Sauter',  'Butterkin',     2026),
  (1650, 'Rümlang Sauter',  'Tiana',         2026),
  (1651, 'Rümlang Sauter',  'Kaori Kuri',    2026)
on conflict (nr) do update
  set schlag = excluded.schlag, sorte = excluded.sorte, saison = excluded.saison;

-- aus 0004_logik.sql

create or replace function klassiere(p_sorte text, p_gewicht_g int)
returns table (klasse kuerbis_klasse, kaliber_idx int)
language sql stable as $$
  with k as (select * from public.sorte_kaliber where sorte = p_sorte),
       band as (
         select (ord - 1)::int as idx
         from k, jsonb_array_elements(k.kaliber_baender) with ordinality as b(grenzen, ord)
         where p_gewicht_g >= (grenzen->>0)::int
           and p_gewicht_g <  (grenzen->>1)::int
         order by ord limit 1
       )
  select case
           when (select count(*) from k) = 0            then 'unklassiert'::public.kuerbis_klasse
           when p_gewicht_g <  (select verlust_unter from k) then 'verlust_klein'::public.kuerbis_klasse
           when p_gewicht_g >= (select kanal_ab       from k) then 'nebenkanal'::public.kuerbis_klasse
           when (select count(*) from band) = 1          then 'kaliber'::public.kuerbis_klasse
           else 'unklassiert'::public.kuerbis_klasse
         end,
         (select idx from band);
$$;

comment on function klassiere is
  '< Verlust-Grenze = VERLUST (weggeworfen) · in einem Band = HAUPTKANAL · '
  '>= kanal_ab = NEBENKANAL (kein Verlust, separat auszuweisen).';

create or replace function auftrag_zuordnen(p_lauf_id bigint)
returns zuordnung_status language plpgsql as $$
declare
  v_lauf   sortier_lauf%rowtype;
  v_fenster interval;
  v_treffer bigint[];
begin
  select * into v_lauf from sortier_lauf where id = p_lauf_id;
  if v_lauf.charge_nr is null or v_lauf.datei_zeit is null then
    update sortier_lauf set zuordnung = 'offen' where id = p_lauf_id;
    return 'offen';
  end if;

  select make_interval(hours => (wert #>> '{}')::int) into v_fenster
    from einstellung where schluessel = 'zuordnung_fenster_h';
  v_fenster := coalesce(v_fenster, interval '12 hours');

  -- 1) Dateizeit liegt innerhalb eines Auftragsintervalls.
  --    Ein nicht abgeschlossener Auftrag endet spätestens dann, wenn der
  --    nächste Auftrag derselben Charge beginnt — sonst würde ein vergessener
  --    Abschluss alle späteren Dateien an sich ziehen.
  with grenzen as (
    select a.id, a.start_ts,
           coalesce(a.ende_ts,
                    least(lead(a.start_ts) over (order by a.start_ts),
                          a.start_ts + interval '24 hours')) as bis
      from auftrag a
     where a.charge_nr = v_lauf.charge_nr
       and a.weg = 'maschine' and a.station = 'sortieren'
  )
  select array_agg(g.id) into v_treffer
    from grenzen g
   where v_lauf.datei_zeit >= g.start_ts and v_lauf.datei_zeit <= g.bis;

  -- 2) sonst: Aufträge, deren Start im Fenster um die Dateizeit liegt
  if coalesce(array_length(v_treffer, 1), 0) = 0 then
    select array_agg(a.id) into v_treffer
      from auftrag a
     where a.charge_nr = v_lauf.charge_nr
       and a.weg = 'maschine' and a.station = 'sortieren'
       and a.start_ts between v_lauf.datei_zeit - v_fenster and v_lauf.datei_zeit + v_fenster;
  end if;

  if coalesce(array_length(v_treffer, 1), 0) = 1 then
    update sortier_lauf set auftrag_id = v_treffer[1], zuordnung = 'auto' where id = p_lauf_id;
    return 'auto';
  elsif coalesce(array_length(v_treffer, 1), 0) > 1 then
    update sortier_lauf set auftrag_id = null, zuordnung = 'mehrdeutig' where id = p_lauf_id;
    return 'mehrdeutig';
  else
    update sortier_lauf set auftrag_id = null, zuordnung = 'offen' where id = p_lauf_id;
    return 'offen';
  end if;
end $$;

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
  v_sorte   text;
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

  select sorte into v_sorte from charge where nr = p_charge_nr;

  insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
  select v_lauf_id, (e->>0)::int, (e->>1)::int, k.klasse, k.kaliber_idx
    from jsonb_array_elements(p_histogramm) e
    cross join lateral klassiere(v_sorte, (e->>0)::int) k;

  perform auftrag_zuordnen(v_lauf_id);
  return v_lauf_id;
end $$;

-- aus 0008_rechte.sql

grant usage on schema public to anon, authenticated;

grant insert, update, delete on
  profil, gebinde, sorte_kaliber, charge, palette, einstellung,
  auftrag, auftrag_teilnehmer, auftrag_palette,
  schimmel_messung, ausschuss_messung, verdunstung_wiegung, marge_messung,
  sortier_lauf, sortier_gewicht
  to authenticated;

alter default privileges in schema public grant select on tables to authenticated;
alter default privileges in schema public grant usage, select on sequences to authenticated;
alter default privileges in schema public grant execute on functions to authenticated;

-- aus 0009_anonyme_arbeiter.sql

alter table profil add column if not exists anonym boolean not null default false;

-- aus 0010_gebinde_tara.sql

insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette, bemerkung) values
  ('G2',         1.500, 25.000, 'Standardkiste (auch bei leerem Gebinde-Feld im Journal)'),
  ('IFCO 6410',  1.360, 25.000, 'IFCO-Klappkiste'),
  ('IFCO 6416',  1.680, 25.000, 'IFCO-Klappkiste'),
  ('IFCO 6424',  2.000, 25.000, 'IFCO-Klappkiste')
on conflict (art) do nothing;

-- aus 0011_plausibilitaet.sql

create or replace function anteil_plausibel(p_anteil numeric)
returns boolean language sql immutable as $$
  select p_anteil is not null and p_anteil >= 0 and p_anteil <= 0.9;
$$;

create or replace function public.ist_aktiv()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profil where id = auth.uid() and aktiv);
$$;

do $$
declare t text;
begin
  foreach t in array array['auftrag_palette', 'schimmel_messung', 'ausschuss_messung',
                           'verdunstung_wiegung', 'marge_messung'] loop
    execute format('drop policy if exists %I on %I', t || '_erfassen', t);
    execute format('create policy %I on %I for insert to authenticated '
                   'with check ((erfasser = auth.uid() and ist_aktiv()) or ist_admin())',
                   t || '_erfassen', t);
  end loop;
end $$;

drop policy if exists auftrag_eroeffnen on auftrag;
create policy auftrag_eroeffnen on auftrag for insert to authenticated
  with check ((eroeffnet_von = auth.uid() and ist_aktiv()) or ist_admin());
grant execute on function anteil_plausibel(numeric), ist_aktiv() to authenticated;

-- aus 0012_wiegen_beim_zaehlen.sql

alter table auftrag_palette
  add column if not exists wiegung_id bigint references verdunstung_wiegung(id) on delete set null;

comment on column auftrag_palette.wiegung_id is
  'Verweist auf die Wägung derselben Palette, falls sie beim Zählen gewogen wurde. '
  'Dann ist ihr Eingangsgewicht bekannt statt geschätzt.';

create index if not exists auftrag_palette_wiegung on auftrag_palette (wiegung_id);

alter table verdunstung_wiegung
  add column if not exists kuerbisse_pro_kiste int check (kuerbisse_pro_kiste > 0);

-- aus 0013_ausgang_und_abbruch.sql

alter table auftrag add column if not exists abgebrochen_ts timestamptz;
alter table auftrag add column if not exists abbruch_grund  text;

comment on column auftrag.abgebrochen_ts is
  'Gesetzt = die Arbeit wurde verworfen. Die erfassten Zeilen bleiben stehen, '
  'zählen aber in keiner Auswertung mehr. So bleibt nachvollziehbar, dass hier '
  'etwas passiert ist, ohne dass es das Ergebnis verfälscht.';

create index if not exists auftrag_aktiv on auftrag (charge_nr) where abgebrochen_ts is null;

create table if not exists ausgang_wiegung (
  id                  bigserial primary key,
  auftrag_id          bigint not null references auftrag(id) on delete cascade,
  charge_nr           int    not null references charge(nr),
  brutto_kg           numeric(8,2) not null check (brutto_kg > 0),
  kisten              int    not null check (kisten > 0),
  gebindeart          text references gebinde(art) on update cascade,
  kuerbisse_pro_kiste int check (kuerbisse_pro_kiste > 0),
  gemessen            boolean not null default true,
  erfasser            uuid not null default auth.uid() references profil(id),
  ts                  timestamptz not null default now(),
  bemerkung           text
);
comment on table ausgang_wiegung is
  'Eine fertig gepackte Palette nach dem Waschen. Aus Brutto, Kistenzahl und '
  'Gebindeart folgt, wie viel Kürbis tatsächlich je Kiste ausgeliefert wird.';

create index if not exists ausgang_wiegung_auftrag on ausgang_wiegung (auftrag_id);

alter table ausgang_wiegung enable row level security;
create policy ausgang_lesen on ausgang_wiegung for select to authenticated using (true);
create policy ausgang_erfassen on ausgang_wiegung for insert to authenticated
  with check ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
create policy ausgang_korrigieren on ausgang_wiegung for update to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()));
create policy ausgang_zuruecknehmen on ausgang_wiegung for delete to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()));

grant select, insert, update, delete on ausgang_wiegung to authenticated;
grant usage, select on sequence ausgang_wiegung_id_seq to authenticated;

insert into einstellung (schluessel, wert, bemerkung) values
  ('soll_kg_pro_kiste', '8'::jsonb,
   'Fixpreis-Grenze je Kiste. Alles darüber ist verschenkte Ware (Marge-Buch).')
on conflict (schluessel) do nothing;

create or replace function auftrag_abbrechen(p_auftrag_id bigint, p_grund text default null)
returns void language plpgsql as $$
begin
  update auftrag
     set abgebrochen_ts = now(),
         abbruch_grund  = p_grund,
         status         = 'abgeschlossen',
         -- greatest, nicht einfach now(): Die Prüfregel verlangt ende_ts >= start_ts.
         -- Ein Abbruch darf nie an einer Zeitverschiebung scheitern.
         ende_ts        = greatest(coalesce(ende_ts, now()), start_ts)
   where id = p_auftrag_id and abgebrochen_ts is null;

  update sortier_lauf
     set auftrag_id = null, zuordnung = 'offen'
   where auftrag_id = p_auftrag_id;
end $$;

create or replace function auftrag_endgueltig_loeschen(p_auftrag_id bigint)
returns void language plpgsql as $$
begin
  if not ist_admin() then
    raise exception 'Endgültig löschen darf nur der Betriebsleiter.';
  end if;

  delete from verdunstung_wiegung where auftrag_id = p_auftrag_id;
  delete from ausgang_wiegung      where auftrag_id = p_auftrag_id;
  update sortier_lauf set auftrag_id = null, zuordnung = 'offen'
   where auftrag_id = p_auftrag_id;
  delete from auftrag where id = p_auftrag_id;
end $$;

grant execute on function auftrag_abbrechen(bigint, text),
                          auftrag_endgueltig_loeschen(bigint) to authenticated;

create or replace function anteil_plausibel(p_anteil numeric)
returns boolean language sql immutable as $$
  select p_anteil is not null and p_anteil >= 0 and p_anteil <= 0.5;
$$;

create index if not exists palette_charge_netto on palette (charge_nr, eingangsdatum, gebindeart);
create index if not exists schimmel_auftrag on schimmel_messung (auftrag_id) where gemessen;
create index if not exists ausschuss_auftrag on ausschuss_messung (auftrag_id, art) where gemessen;
create index if not exists verdunstung_auftrag on verdunstung_wiegung (auftrag_id) where gemessen;
create index if not exists sortier_lauf_auftrag on sortier_lauf (auftrag_id) where auftrag_id is not null;

-- aus 0016_auswertung_speichern.sql

create table if not exists auswertung_stand (
  id            int primary key default 1 check (id = 1),
  berechnet_ts  timestamptz,
  dauer_ms      int,
  geaendert_ts  timestamptz not null default now()
);
insert into auswertung_stand (id) values (1) on conflict (id) do nothing;

alter table auswertung_stand enable row level security;
drop policy if exists stand_lesen on auswertung_stand;
create policy stand_lesen on auswertung_stand for select to authenticated using (true);
grant select on auswertung_stand to authenticated;

comment on table auswertung_stand is
  'Wann wurde die Auswertung zuletzt gerechnet, und hat sich seither etwas '
  'geändert? geaendert_ts setzen die Erfassungstabellen selbst.';

create or replace function auswertung_veraltet()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update auswertung_stand set geaendert_ts = now() where id = 1;
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['palette', 'auftrag', 'auftrag_palette', 'schimmel_messung',
                           'ausschuss_messung', 'verdunstung_wiegung', 'marge_messung',
                           'ausgang_wiegung', 'sortier_lauf', 'sortier_gewicht',
                           'gebinde', 'sorte_kaliber', 'einstellung'] loop
    execute format('drop trigger if exists %I on %I', t || '_veraltet', t);
    execute format('create trigger %I after insert or update or delete on %I '
                   'for each statement execute function auswertung_veraltet()',
                   t || '_veraltet', t);
  end loop;
end $$;

-- aus 0017_schimmelmodell.sql

create or replace function t_quantil_95(p_df int)
returns numeric language sql immutable as $$
  select case
    when p_df is null or p_df < 1 then 12.706
    when p_df >= 30 then 1.960
    else (array[12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306,
                2.262, 2.228, 2.201, 2.179, 2.160, 2.145, 2.131, 2.120,
                2.110, 2.101, 2.093, 2.086, 2.080, 2.074, 2.069, 2.064,
                2.060, 2.056, 2.052, 2.048, 2.045])[p_df]
  end::numeric;
$$;

comment on function t_quantil_95(int) is
  'Zweiseitiges 95-%-Quantil der t-Verteilung. Bei wenigen unabhängigen '
  'Gruppen ist 1.96 zu optimistisch.';

grant execute on function t_quantil_95(int) to authenticated;

-- aus 0020_lagerkontrolle.sql

alter table verdunstung_wiegung
  add column if not exists faul_kg numeric(8,2)
    check (faul_kg is null or faul_kg >= 0);

comment on column verdunstung_wiegung.faul_kg is
  'Wie viel der gewogenen Palette faul ist. Freiwillig — aber der einzige '
  'Schimmelwert, dessen Palette nicht danach ausgewählt wurde, wie sie aussah.';

create or replace function auswertung_aktualisieren()
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v_start timestamptz := clock_timestamp();
begin
  -- Reihenfolge ist Pflicht: jede Stufe liest die vorige.
  refresh materialized view mv_sortier_lauf_masse;
  refresh materialized view mv_sortier_eingang;
  refresh materialized view mv_auftrag_masse;
  refresh materialized view mv_schimmel_punkte;
  refresh materialized view mv_kaskade;
  refresh materialized view mv_kaliber_verteilung;

  update auswertung_stand
     set berechnet_ts = now(),
         dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
   where id = 1;

  return now();
end $$;

-- aus 0027_palox_stand.sql

alter table schimmel_messung
  add column if not exists palox_stand_kg numeric(8,2)
    check (palox_stand_kg is null or palox_stand_kg >= 0);

comment on column schimmel_messung.palox_stand_kg is
  'Was auf der Palox-Waage stand, als diese Menge gebucht wurde. kg ist die '
  'daraus gebildete Differenz zum vorherigen Stand — beides wird behalten, '
  'damit sich der Wert nachrechnen lässt.';

create or replace function palox_letzter_stand()
returns numeric language sql stable as $$
  select palox_stand_kg from public.schimmel_messung
   where palox_stand_kg is not null and gemessen
   order by ts desc, id desc limit 1;
$$;

comment on function palox_letzter_stand is
  'Was zuletzt auf der Palox-Waage stand. Der Arbeiter-Bildschirm zieht das '
  'vom neuen Stand ab, damit niemand im Kopf rechnen muss.';
grant execute on function palox_letzter_stand() to authenticated;

-- aus 0028_warenausgang.sql

create table if not exists ausgang_ziel (
  code       text primary key,
  name       text not null,
  buch       text not null check (buch in ('verkauf', 'verlust', 'marge')),
  reihenfolge int  not null default 100
);

comment on table ausgang_ziel is
  'Wohin Ware den Betrieb verlässt. buch entscheidet, in welcher Rechnung sie '
  'auftaucht: verkauf = planmässig raus, verlust = Buch A, marge = Buch B.';

insert into ausgang_ziel (code, name, buch, reihenfolge) values
  ('verkauf',     'Verkauf (Lieferschein)',  'verkauf', 10),
  ('hofladen',    'Hofladen / Direktverkauf', 'verkauf', 20),
  ('tierfutter',  'Tierfutter',               'marge',   30),
  ('eigenbedarf', 'Eigenbedarf / Personal',   'verlust', 40),
  ('kompost',     'Kompost / Entsorgung',     'verlust', 50)
on conflict (code) do nothing;

create table if not exists lieferung (
  id          bigserial primary key,
  datum       date        not null,
  charge_nr   int         references charge(nr),
  sorte       text        references sorte_kaliber(sorte),

  kg          numeric(12,2) check (kg is null or kg > 0),
  kisten      int           check (kisten is null or kisten > 0),
  gebindeart  text        references gebinde(art) on update cascade,
  ziel        text        not null default 'verkauf' references ausgang_ziel(code),
  kunde       text,
  erfasser    uuid        not null default auth.uid() references profil(id),
  ts          timestamptz not null default now(),
  bemerkung   text,
  constraint lieferung_menge check (kg is not null or kisten is not null),

  constraint lieferung_zuordnung check (charge_nr is not null or sorte is not null)
);

comment on table lieferung is
  'Was den Betrieb verlassen hat. Kilo oder Kistenzahl genügt — was auf dem '
  'Lieferschein steht. Ohne Charge zählt die Lieferung für die ganze Sorte.';

create index if not exists lieferung_datum  on lieferung (datum);
create index if not exists lieferung_charge on lieferung (charge_nr) where charge_nr is not null;
create index if not exists lieferung_sorte  on lieferung (sorte);

alter table lieferung enable row level security;

create policy lieferung_lesen on lieferung for select to authenticated using (true);
create policy lieferung_erfassen on lieferung for insert to authenticated
  with check (ist_admin());
create policy lieferung_aendern on lieferung for update to authenticated
  using (ist_admin());
create policy lieferung_loeschen on lieferung for delete to authenticated
  using (ist_admin());

create policy ausgang_ziel_lesen on ausgang_ziel for select to authenticated using (true);
alter table ausgang_ziel enable row level security;

drop trigger if exists lieferung_veraltet on lieferung;
create trigger lieferung_veraltet after insert or update or delete on lieferung
  for each statement execute function auswertung_veraltet();
grant insert, update, delete on lieferung to authenticated;
grant usage on sequence lieferung_id_seq to authenticated;;

-- aus 0032_palox_je_station.sql

alter table schimmel_messung
  add column if not exists palox_geleert boolean not null default false;

comment on column schimmel_messung.palox_geleert is
  'Der Arbeiter hat den Palox seit der letzten Ablesung geleert. Dann ist der '
  'neue Stand selbst die Menge — auch wenn er über dem alten liegt.';

drop function if exists palox_letzter_stand();

create or replace function palox_letzter_stand(p_station station)
returns numeric language sql stable as $$
  select s.palox_stand_kg
    from public.schimmel_messung s
    join public.auftrag a on a.id = s.auftrag_id
   where s.palox_stand_kg is not null and s.gemessen
     and a.station = p_station
   order by s.ts desc, s.id desc limit 1;
$$;

comment on function palox_letzter_stand(station) is
  'Was zuletzt auf der Palox-Waage DIESER Station stand. Die Eingabemaske '
  'zieht das vom neuen Stand ab, damit niemand im Kopf rechnen muss.';

grant execute on function palox_letzter_stand(station) to authenticated;

alter default privileges in schema public revoke execute on functions from public;

-- aus 0036_kette.sql

insert into einstellung (schluessel, wert, bemerkung) values
  ('palox_tara_kg', '45'::jsonb,
   'Leergewicht des Palox (Sammelbehälter für Faules). Die Waage zeigt brutto; '
   'bei der ersten Ablesung einer Station und nach dem Leeren wird die Tara '
   'vom Stand abgezogen. Bei der Differenz zweier Stände kürzt sie sich weg.')
on conflict (schluessel) do nothing;

create or replace function palox_tara_kg()
returns numeric language sql stable as $$
  select coalesce((select (wert #>> '{}')::numeric from public.einstellung
                    where schluessel = 'palox_tara_kg'), 0);
$$;
revoke execute on function palox_tara_kg() from public;
grant execute on function palox_tara_kg() to authenticated;

-- aus 0038_sortierschema.sql

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
  kaeufer           text references kaeufer(code),
  gilt_ab           date not null default current_date,
  art               text not null default 'kaliber' check (art in ('kaliber', 'kiste')),
  verlust_unter     int,
  kaliber_baender   jsonb,
  kanal_ab          int,
  soll_kg_pro_kiste numeric(6,2),
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

insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab,
                           bemerkung, erfasser)
select sk.sorte, null, date '2000-01-01', 'kaliber', sk.verlust_unter, sk.kaliber_baender,
       sk.kanal_ab, 'Ausgangswert aus der Spezifikation (§6)', null
  from sorte_kaliber sk
 where not exists (select 1 from sortierschema s where s.sorte = sk.sorte and s.kaeufer is null);

comment on column sorte_kaliber.kaliber_baender is
  'Nur noch der Ausgangswert für die erste Standard-Fassung in sortierschema. '
  'Klassiert wird nach sortierschema, nicht nach dieser Spalte.';

create or replace function sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date)
returns bigint language sql stable as $$
  select coalesce(
    -- die Fassung dieses Käufers, die am Stichtag galt
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is not distinct from p_kaeufer and gilt_ab <= p_datum
      order by gilt_ab desc limit 1),
    -- sonst die Standard-Fassung
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is null and gilt_ab <= p_datum
      order by gilt_ab desc limit 1),
    -- sonst irgendeine Standard-Fassung (Datum vor jeder Fassung)
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is null
      order by gilt_ab limit 1));
$$;
comment on function sortierschema_fuer is
  'Die Fassung, die für Sorte und Käufer an einem Tag galt. Ohne passende '
  'Käufer-Fassung gilt der Standard der Sorte.';

create or replace function klassiere(p_schema_id bigint, p_gewicht_g int)
returns table (klasse kuerbis_klasse, kaliber_idx int)
language sql stable as $$
  with k as (select * from public.sortierschema where id = p_schema_id),
       band as (
         select (ord - 1)::int as idx
         from k, jsonb_array_elements(k.kaliber_baender) with ordinality as b(grenzen, ord)
         where k.art = 'kaliber'
           and p_gewicht_g >= (grenzen->>0)::int
           and p_gewicht_g <  (grenzen->>1)::int
         order by ord limit 1
       )
  select case
           when (select count(*) from k) = 0                 then 'unklassiert'::public.kuerbis_klasse
           -- Kiste ab x kg: das Stückgewicht spielt keine Rolle, alles ist
           -- Hauptkanal. Zu klein und zu gross werden dort nach Augenmass
           -- erfasst, nicht aus der CSV.
           when (select art from k) = 'kiste'                then 'kaliber'::public.kuerbis_klasse
           when p_gewicht_g <  (select verlust_unter from k) then 'verlust_klein'::public.kuerbis_klasse
           when p_gewicht_g >= (select kanal_ab       from k) then 'nebenkanal'::public.kuerbis_klasse
           when (select count(*) from band) = 1               then 'kaliber'::public.kuerbis_klasse
           else 'unklassiert'::public.kuerbis_klasse
         end,
         (select idx from band);
$$;

create or replace function klassiere(p_sorte text, p_gewicht_g int)
returns table (klasse kuerbis_klasse, kaliber_idx int)
language sql stable as $$
  select * from public.klassiere(public.sortierschema_fuer(p_sorte, null, current_date), p_gewicht_g);
$$;

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

update auftrag a
   set sortierschema_id = sortierschema_fuer(c.sorte, a.kaeufer, a.start_ts::date)
  from charge c
 where c.nr = a.charge_nr and a.sortierschema_id is null;

update sortier_lauf l
   set sortierschema_id = coalesce(
         (select a.sortierschema_id from auftrag a where a.id = l.auftrag_id),
         sortierschema_fuer(c.sorte, null, coalesce(l.datei_zeit, l.gelesen_ts)::date))
  from charge c
 where c.nr = l.charge_nr and l.sortierschema_id is null;

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

alter table kaeufer enable row level security;
alter table sortierschema enable row level security;
drop policy if exists kaeufer_lesen on kaeufer;
drop policy if exists kaeufer_anlegen on kaeufer;
drop policy if exists kaeufer_aendern on kaeufer;
create policy kaeufer_lesen on kaeufer for select to authenticated using (true);

create policy kaeufer_anlegen on kaeufer for insert to authenticated
  with check (ist_aktiv() or ist_admin());
create policy kaeufer_aendern on kaeufer for update to authenticated using (ist_admin());

drop policy if exists sortierschema_lesen on sortierschema;
drop policy if exists sortierschema_anlegen on sortierschema;
drop policy if exists sortierschema_aendern on sortierschema;
drop policy if exists sortierschema_loeschen on sortierschema;
create policy sortierschema_lesen on sortierschema for select to authenticated using (true);

create policy sortierschema_anlegen on sortierschema for insert to authenticated
  with check (ist_aktiv() or ist_admin());
create policy sortierschema_aendern on sortierschema for update to authenticated using (ist_admin());
create policy sortierschema_loeschen on sortierschema for delete to authenticated using (ist_admin());

grant select, insert on kaeufer to authenticated;
grant update on kaeufer to authenticated;
grant select, insert, update, delete on sortierschema to authenticated;
grant usage, select on sequence sortierschema_id_seq to authenticated;

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

drop trigger if exists sortierschema_veraltet on sortierschema;
create trigger sortierschema_veraltet after insert or update or delete on sortierschema
  for each statement execute function auswertung_veraltet();

-- aus 0039_auftrag_angabe.sql

create table if not exists auftrag_angabe (
  id          bigserial primary key,
  auftrag_id  bigint not null references auftrag(id) on delete cascade,
  schluessel  text not null,
  wert        text not null,
  erfasser    uuid not null default auth.uid() references profil(id),
  ts          timestamptz not null default now()
);
comment on table auftrag_angabe is
  'Antworten aus dem Abschluss-Ablauf, als Schlüssel und Wert. Nur für Angaben, '
  'über die nicht gerechnet wird. Nie überschreiben — nochmal antworten; es '
  'gilt die letzte Antwort je Schlüssel.';
create index if not exists auftrag_angabe_auftrag on auftrag_angabe (auftrag_id, schluessel, ts desc);

alter table auftrag_angabe enable row level security;
drop policy if exists angabe_lesen on auftrag_angabe;
drop policy if exists angabe_erfassen on auftrag_angabe;
drop policy if exists angabe_aendern on auftrag_angabe;
drop policy if exists angabe_loeschen on auftrag_angabe;
create policy angabe_lesen on auftrag_angabe for select to authenticated using (true);
create policy angabe_erfassen on auftrag_angabe for insert to authenticated
  with check ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
create policy angabe_aendern on auftrag_angabe for update to authenticated using (ist_admin());
create policy angabe_loeschen on auftrag_angabe for delete to authenticated using (ist_admin());
grant select, insert, update, delete on auftrag_angabe to authenticated;
grant usage, select on sequence auftrag_angabe_id_seq to authenticated;

drop trigger if exists auftrag_angabe_veraltet on auftrag_angabe;
create trigger auftrag_angabe_veraltet after insert or update or delete on auftrag_angabe
  for each statement execute function auswertung_veraltet();

create or replace function auftrag_ende_setzen()
returns trigger language plpgsql as $$
begin
  if new.status = 'abgeschlossen' and old.status is distinct from 'abgeschlossen' then
    if new.ende_ts is null or new.ende_ts < new.start_ts then
      new.ende_ts := greatest(now(), new.start_ts);
    end if;
  end if;
  return new;
end $$;
revoke execute on function auftrag_ende_setzen() from public;
drop trigger if exists auftrag_ende on auftrag;
create trigger auftrag_ende before update on auftrag
  for each row execute function auftrag_ende_setzen();

-- aus 0041_gebinde.sql

alter table auftrag_palette drop constraint if exists auftrag_palette_datum_pflicht;
alter table auftrag_palette add constraint auftrag_palette_datum_pflicht
  check (eingangsdatum is not null or palette_id is not null or wiegung_id is not null)
  not valid;
comment on column auftrag_palette.eingangsdatum is
  'Datum vom Palettenzettel. Pflicht für neue Zeilen (0041) — ohne es rechnet '
  'die Auswertung das Alter des Lagerbestands mit dem Chargenmittel. Entbehrlich '
  'nur, wenn das Datum ohnehin feststeht: bei einer erkannten Palette oder einer '
  'Wägung steht es dort. Zeilen aus der Zeit davor dürfen leer sein; '
  'nachträglich gefüllt würde ein Datum erfunden, das niemand abgelesen hat.';

alter table auftrag add column if not exists kaliber_idx int;
comment on column auftrag.kaliber_idx is
  'Beim Waschen: welches Kaliberband aus dem Sortierschema der Arbeit gewaschen '
  'wird (Index in kaliber_baender). Trägt ein, wer die Arbeit eröffnet. NULL an '
  'allen anderen Stationen.';
alter table auftrag drop constraint if exists auftrag_kaliber_nur_waschen;
alter table auftrag add constraint auftrag_kaliber_nur_waschen
  check (kaliber_idx is null or station = 'waschen') not valid;

create table if not exists auftrag_gebinde (
  id          bigserial primary key,
  auftrag_id  bigint not null references auftrag(id) on delete cascade,
  kaliber_idx int not null check (kaliber_idx >= 0),
  anzahl      int not null default 0 check (anzahl >= 0),
  erfasser    uuid not null default auth.uid() references profil(id),
  ts          timestamptz not null default now(),
  unique (auftrag_id, kaliber_idx)
);
comment on table auftrag_gebinde is
  'Gezählte Kaliber-Kisten je Arbeit und Kaliber. Beim Sortieren die gefüllten, '
  'beim Waschen die geleerten. Was eine Kiste wiegt, steht hier nicht — das '
  'wird aus der CSV gemessen (v_koeff_gebinde).';

alter table auftrag_gebinde enable row level security;
drop policy if exists gebinde_lesen on auftrag_gebinde;
drop policy if exists gebinde_erfassen on auftrag_gebinde;
drop policy if exists gebinde_aendern on auftrag_gebinde;
drop policy if exists gebinde_loeschen on auftrag_gebinde;
create policy gebinde_lesen on auftrag_gebinde for select to authenticated using (true);
create policy gebinde_erfassen on auftrag_gebinde for insert to authenticated
  with check ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());

create policy gebinde_aendern on auftrag_gebinde for update to authenticated
  using ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
create policy gebinde_loeschen on auftrag_gebinde for delete to authenticated
  using ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
grant select, insert, update, delete on auftrag_gebinde to authenticated;
grant usage, select on sequence auftrag_gebinde_id_seq to authenticated;

drop trigger if exists auftrag_gebinde_veraltet on auftrag_gebinde;
create trigger auftrag_gebinde_veraltet after insert or update or delete on auftrag_gebinde
  for each statement execute function auswertung_veraltet();

-- aus 0042_suchpfad.sql

do $$
declare z record;
begin
  for z in
    select p.oid::regprocedure::text as sig, p.prokind
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p')
       -- Schon gesetzt? Dann nichts zu tun.
       and (p.proconfig is null
            or not exists (select 1 from unnest(p.proconfig) c where c like 'search\_path=%'))
       -- Diese sollen eingesetzt werden dürfen: ihre Rümpfe nennen die
       -- Tabellen ausdrücklich mit Schema, oder sie fassen gar keine an.
       and p.proname not in ('palox_tara_kg', 'palox_letzter_stand', 'klassiere',
                             'schimmelanteil', 'schimmel_n', 'sockel_anteil',
                             'sortierschema_fuer', 't_quantil_95',
                             'anteil_plausibel', 'korrekturfenster')
  loop
    execute format('alter %s %s set search_path = public',
                   case z.prokind when 'p' then 'procedure' else 'function' end, z.sig);
  end loop;
end $$;

-- aus 0043_sortierart_je_arbeit.sql

drop index if exists sortierschema_eindeutig;
create unique index if not exists sortierschema_eindeutig
  on sortierschema (sorte, coalesce(kaeufer, ''), art, gilt_ab);

insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
select sk.sorte, null, date '2000-01-01', 'kiste',
       coalesce((select (wert #>> '{}')::numeric from public.einstellung
                  where schluessel = 'soll_kg_pro_kiste'), 8),
       'Standard beim Einrichten — Sollgewicht aus der Einstellung. '
       'Echtes Sollgewicht je Sorte: neue Fassung anlegen, nicht diese ändern.'
  from sorte_kaliber sk
 where not exists (select 1 from sortierschema s
                    where s.sorte = sk.sorte and s.kaeufer is null and s.art = 'kiste');

create or replace function sortierschema_fuer(p_sorte text, p_kaeufer text,
                                              p_datum date, p_art text)
returns bigint language sql stable as $$
  select coalesce(
    -- die Fassung dieses Käufers in dieser Art, die am Stichtag galt
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is not distinct from p_kaeufer
        and art = p_art and gilt_ab <= p_datum
      order by gilt_ab desc limit 1),
    -- sonst die Standard-Fassung dieser Art
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is null and art = p_art and gilt_ab <= p_datum
      order by gilt_ab desc limit 1),
    -- sonst irgendeine Standard-Fassung dieser Art
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is null and art = p_art
      order by gilt_ab limit 1));
$$;
comment on function sortierschema_fuer(text, text, date, text) is
  'Die Fassung einer bestimmten Art (kaliber oder kiste), die für Sorte und '
  'Käufer an einem Tag galt. Die Art wählt der Arbeiter beim Eröffnen.';
revoke execute on function sortierschema_fuer(text, text, date, text) from public;
grant execute on function sortierschema_fuer(text, text, date, text) to authenticated;

create or replace function sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date)
returns bigint language sql stable as $$
  select public.sortierschema_fuer(p_sorte, p_kaeufer, p_datum, 'kaliber');
$$;

create or replace function auftrag_schema_setzen()
returns trigger language plpgsql as $$
begin
  if new.sortierschema_id is null and new.station = 'waschen' then
    select l.sortierschema_id into new.sortierschema_id
      from public.sortier_lauf l
      join public.auftrag a on a.id = l.auftrag_id
     where l.charge_nr = new.charge_nr and l.sortierschema_id is not null
     order by coalesce(l.datei_zeit, l.gelesen_ts) desc limit 1;
  end if;
  if new.sortierschema_id is null then
    select public.sortierschema_fuer(c.sorte, new.kaeufer, new.start_ts::date, 'kaliber')
      into new.sortierschema_id
      from public.charge c where c.nr = new.charge_nr;
  end if;
  return new;
end $$;
revoke execute on function auftrag_schema_setzen() from public;
revoke execute on function auftrag_schema_setzen() from public;

-- aus 0044_ausschuss_wiegen.sql

alter table ausschuss_messung add column if not exists brutto_kg    numeric(10,2);
alter table ausschuss_messung add column if not exists kisten       int;
alter table ausschuss_messung add column if not exists gebindeart   text references gebinde(art);
comment on column ausschuss_messung.brutto_kg is
  'Waagenstand der Ausschuss-Palette (brutto). Ist er gesetzt, ist kg das '
  'daraus abgeleitete Netto; sonst ist kg die eingetippte Schätzung.';

create or replace function ausschuss_netto_setzen()
returns trigger language plpgsql as $$
declare v_tara_kiste numeric; v_tara_palette numeric;
begin
  if new.brutto_kg is not null then
    select g.tara_kg_pro_kiste, coalesce(g.tara_kg_palette, 0)
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    new.kg := greatest(round(new.brutto_kg
                - coalesce(new.kisten, 0) * coalesce(v_tara_kiste, 0)
                - coalesce(v_tara_palette, 0)), 0);
    new.gemessen := true;
  end if;
  return new;
end $$;
revoke execute on function ausschuss_netto_setzen() from public;
drop trigger if exists ausschuss_netto on ausschuss_messung;
create trigger ausschuss_netto before insert or update on ausschuss_messung
  for each row execute function ausschuss_netto_setzen();

-- aus 0045_kontrolle_auswahl.sql

alter table verdunstung_wiegung
  add column if not exists auswahl text
  check (auswahl is null or auswahl in ('erreichbar_zufaellig', 'mitte_unten', 'gezielt'));
comment on column verdunstung_wiegung.auswahl is
  'Nur bei der Lagerkontrolle gesetzt: wie die Palette gegriffen wurde — '
  'erreichbar_zufaellig (ehrliche Vorgabe), mitte_unten (besser), gezielt '
  '(nach Aussehen, für die Selektionsprüfung untauglich).';

-- aus 0046_fax.sql

alter table auftrag add column if not exists ist_fax boolean not null default false;
comment on column auftrag.ist_fax is
  'Fax-Arbeit: eigener Waschgang nach Bestellung. Fachlich ein Waschgang '
  '(Station waschen), nur für die Erfassung getrennt gehalten.';

-- aus 0047_erfassungsbeginn.sql

insert into einstellung (schluessel, wert, bemerkung) values
  ('erfassungsbeginn', 'null'::jsonb,
   'Ab wann die App mitzählt (JJJJ-MM-TT). Vor diesem Tag ausgelieferte Masse '
   'steht je Charge in charge_vorlauf und geht als Ausgang in die Bilanz ein.')
on conflict (schluessel) do nothing;

create table if not exists charge_vorlauf (
  charge_nr           int primary key references charge(nr) on delete cascade,
  ausgang_vor_app_kg  numeric(14,2) not null check (ausgang_vor_app_kg >= 0),
  bemerkung           text,
  erfasser            uuid not null default auth.uid() references profil(id),
  ts                  timestamptz not null default now()
);
comment on table charge_vorlauf is
  'Grobe Angabe des Betriebsleiters: wie viel einer Charge vor dem '
  'Erfassungsbeginn schon ausgeliefert war. Kein Messwert der App — geht als '
  'bekannter Ausgang in die Bilanz, damit die Lücke nicht den späten Start '
  'der Erfassung als fehlende Masse ausweist.';

alter table charge_vorlauf enable row level security;
drop policy if exists vorlauf_lesen on charge_vorlauf;
drop policy if exists vorlauf_pflegen on charge_vorlauf;
create policy vorlauf_lesen on charge_vorlauf for select to authenticated using (true);
create policy vorlauf_pflegen on charge_vorlauf for all to authenticated
  using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on charge_vorlauf to authenticated;

drop trigger if exists charge_vorlauf_veraltet on charge_vorlauf;
create trigger charge_vorlauf_veraltet after insert or update or delete on charge_vorlauf
  for each statement execute function auswertung_veraltet();

-- aus 0048_ballast.sql

do $$
declare v_n bigint;
begin
  if to_regclass('public.marge_messung') is null then return; end if;
  select count(*) into v_n from public.marge_messung;
  if v_n > 0 then
    raise exception using
      message = format('marge_messung enthält %s Zeile(n) — die Einrichtung bricht hier ab.', v_n),
      detail  = 'Diese Tabelle war der frühere Kanal für von Hand eingetippte Marge-Posten. '
                'Die App schreibt sie seit dem 25. August nicht mehr, und ab dieser Fassung '
                'liest sie keine Auswertung mehr. Damit kein Messwert still verschwindet, '
                'wird sie nur gelöscht, wenn sie leer ist.',
      hint    = 'Im SQL-Editor: select * from marge_messung; — ansehen, bei Bedarf als CSV '
                'sichern, dann delete from marge_messung; und setup.sql erneut ausführen.';
  end if;
end $$;

drop table if exists marge_messung;
drop type  if exists marge_art;

update sortierschema
   set bemerkung = 'Standard beim Einrichten — Sollgewicht aus der Einstellung. '
                || 'Echtes Sollgewicht je Sorte: neue Fassung anlegen, nicht diese ändern.'
 where bemerkung like 'Beim Einrichten aus der Einstellung soll_kg_pro_kiste übernommen%';

-- aus 0050_warenausgang_import.sql

create table if not exists ausgang_quelle (
  code              text primary key,
  name              text not null,

  dateiname_muster  text,
  aktiv             boolean not null default true,
  bemerkung         text,
  erfasser          uuid references profil(id) default auth.uid(),
  ts                timestamptz not null default now()
);

comment on table ausgang_quelle is
  'Die Firma, aus deren Warenwirtschaft eine Warenausgangsdatei kommt. '
  'Positionsnummern sind nur innerhalb einer Quelle eindeutig.';

create table if not exists ausgang_datei (
  id                bigserial primary key,
  quelle            text not null references ausgang_quelle(code) on update cascade,
  dateiname         text not null,
  pruefsumme        text not null,
  n_zeilen          int  not null default 0,
  n_kuerbis         int  not null default 0,
  n_neu             int  not null default 0,
  n_geaendert       int  not null default 0,
  n_unveraendert    int  not null default 0,
  von_datum         date,
  bis_datum         date,
  bemerkung         text,
  hochgeladen_von   uuid not null references profil(id) default auth.uid(),
  ts                timestamptz not null default now()
);

create unique index if not exists ausgang_datei_pruefsumme
  on ausgang_datei (quelle, pruefsumme);

comment on table ausgang_datei is
  'Jedes Hochladen mit Prüfsumme und Bilanz. Dieselbe Datei zweimal hochladen '
  'ist erlaubt: die Prüfsumme erkennt sie wieder.';

create table if not exists ausgang_zeile (
  id                 bigserial primary key,
  quelle             text   not null references ausgang_quelle(code) on update cascade,
  pos_id             bigint not null,
  charge_extern      text   not null default '',

  lauf_nr            int    not null default 1,
  fingerabdruck      text   not null,
  datei_id           bigint references ausgang_datei(id) on delete set null,
  datum              date   not null,
  journal            text,
  auftragsnr         text,
  kunde              text,
  artikel_id         text   not null,
  artikel            text   not null,
  einheit            text,
  menge              numeric(14,3),
  gewicht_je_artikel numeric(10,4),
  batch_menge        numeric(14,3),
  kg_position        numeric(14,3),
  kg_charge          numeric(14,3),
  gebindeart         text,
  gebinde_menge      int,
  gebinde_inhalt     int,
  produzent          text,
  erloes             numeric(14,2),
  erfasser           uuid not null references profil(id) default auth.uid(),
  ts                 timestamptz not null default now(),
  geaendert_ts       timestamptz,
  constraint ausgang_zeile_eindeutig unique (quelle, pos_id, charge_extern, lauf_nr)
);

create index if not exists ausgang_zeile_datum on ausgang_zeile (datum);
create index if not exists ausgang_zeile_artikel on ausgang_zeile (artikel_id, artikel);
create index if not exists ausgang_zeile_charge on ausgang_zeile (charge_extern);

comment on table ausgang_zeile is
  'Eine Zeile der Warenausgangsdatei: welcher Teil einer Lieferscheinposition '
  'aus welcher Charge kam. kg_position gilt für die ganze Position und steht '
  'auf jeder ihrer Zeilen — beim Summieren je Position nur einmal zählen.';
comment on column ausgang_zeile.kg_position is
  'Masse der ganzen Position (Menge × Gewicht je Artikel). Auf allen Zeilen '
  'derselben Position gleich; je Position einmal zählen, sonst Doppelzählung.';
comment on column ausgang_zeile.kg_charge is
  'Der dieser Charge zugeordnete Teil (Batchmenge × Gewicht je Artikel).';

create table if not exists ausgang_artikel (
  artikel_id    text not null,
  artikel       text not null,
  ist_kuerbis   boolean not null,
  sorte         text references sorte_kaliber(sorte) on update cascade,
  bestaetigt_von uuid references profil(id) default auth.uid(),
  ts            timestamptz not null default now(),
  bemerkung     text,
  primary key (artikel_id, artikel)
);

comment on table ausgang_artikel is
  'Bestätigte Zuordnung eines Verkaufsartikels: Kürbis ja/nein und welche '
  'Sorte. Dieselbe Artikelkennung trug im Zeitverlauf verschiedene Artikel, '
  'darum gehört der Name zum Schlüssel.';

create table if not exists lieferung_import (
  lieferung_id bigint primary key references lieferung(id) on delete cascade,
  quelle       text   not null references ausgang_quelle(code) on update cascade,

  extern_id    text   not null unique,
  zeile_id     bigint references ausgang_zeile(id) on delete set null,
  ts           timestamptz not null default now()
);

create index if not exists lieferung_import_quelle on lieferung_import (quelle);

comment on table lieferung_import is
  'Welche Lieferung aus welcher Importzeile stammt. Von Hand erfasste '
  'Lieferungen stehen hier nicht — sie haben keine Kennung aus dem Perigon.';

alter table ausgang_quelle  enable row level security;
alter table ausgang_datei   enable row level security;
alter table ausgang_zeile   enable row level security;
alter table ausgang_artikel enable row level security;
alter table lieferung_import enable row level security;

do $$
declare t text;
begin
  foreach t in array array['ausgang_quelle', 'ausgang_datei', 'ausgang_zeile',
                           'ausgang_artikel', 'lieferung_import'] loop
    execute format('drop policy if exists %I on %I', t || '_lesen', t);
    execute format('drop policy if exists %I on %I', t || '_admin', t);
    -- Lesen darf jeder Angemeldete (die Auswertung zeigt die Zahlen ohnehin),
    -- schreiben nur der Betriebsleiter: der Import ist seine Arbeit.
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_lesen', t);
    execute format('create policy %I on %I for all to authenticated using (ist_admin()) with check (ist_admin())',
                   t || '_admin', t);
  end loop;
end $$;

grant select on ausgang_quelle, ausgang_datei, ausgang_zeile, ausgang_artikel,
  lieferung_import to authenticated;
grant insert, update, delete on ausgang_quelle, ausgang_datei, ausgang_zeile,
  ausgang_artikel, lieferung_import to authenticated;
grant usage on sequence ausgang_datei_id_seq, ausgang_zeile_id_seq to authenticated;

-- aus 0051_fax_kaliber_alter.sql

alter table charge add column if not exists perigon_nr int;
comment on column charge.perigon_nr is
  'Chargennummer derselben Ware im Perigon der Firma AG (sechsstellig). Aus der '
  'Planungsdatei des Betriebs; nicht eindeutig (198976 steht an zwei Chargen).';
create index if not exists charge_perigon on charge (perigon_nr) where perigon_nr is not null;

update charge c set perigon_nr = v.p
  from (values
    (1598, 198876), (1599, 198877), (1601, 198888), (1603, 198915), (1604, 198916),
    (1605, 198917), (1606, 198919), (1607, 198889), (1608, 198920), (1609, 198918),
    (1610, 198921), (1611, 198922), (1612, 198944), (1613, 198923), (1614, 198945),
    (1615, 198946), (1616, 198947), (1617, 198948), (1618, 198949), (1619, 198950),
    (1620, 198951), (1623, 198955), (1624, 198956), (1625, 198957), (1626, 198958),
    (1627, 198959), (1628, 198970), (1630, 198969), (1631, 198968), (1632, 198960),
    (1633, 198961), (1634, 198962), (1635, 198963), (1636, 198966), (1637, 198964),
    (1638, 198965), (1646, 198952), (1647, 198953), (1648, 198974), (1649, 198976),
    (1650, 198976), (1651, 198975)) as v(nr, p)
 where c.nr = v.nr and c.perigon_nr is null;

insert into einstellung (schluessel, wert)
values ('kisten_pro_palette', '32'::jsonb)
on conflict (schluessel) do nothing;

alter table schimmel_messung add column if not exists brutto_kg   numeric(10,2);
alter table schimmel_messung add column if not exists kisten      int;
alter table schimmel_messung add column if not exists gebindeart  text references gebinde(art);
alter table schimmel_messung add column if not exists mit_palette boolean not null default false;
comment on column schimmel_messung.brutto_kg is
  'Waagenstand einer Kiste (oder mehrerer auf einer Palette) mit Faulem, brutto. '
  'Ist er gesetzt, ist kg das daraus abgeleitete Netto; palox_stand_kg bleibt leer. '
  'Beim Fax die einzige Art, Faules zu erfassen.';
comment on column schimmel_messung.mit_palette is
  'true: die Kisten standen beim Wiegen auf einer Palette, deren Tara mit abgeht. '
  'false: einzelne Kiste auf der Tischwaage.';

create or replace function schimmel_netto_setzen()
returns trigger language plpgsql as $$
declare v_tara_kiste numeric; v_tara_palette numeric;
begin
  if new.brutto_kg is not null then
    if new.palox_stand_kg is not null then
      raise exception 'Eine Messung ist entweder eine Palox-Ablesung oder eine Kistenwägung, nicht beides.';
    end if;
    select g.tara_kg_pro_kiste, coalesce(g.tara_kg_palette, 0)
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    new.kg := greatest(round(new.brutto_kg
                - coalesce(new.kisten, 1) * coalesce(v_tara_kiste, 0)
                - case when new.mit_palette then coalesce(v_tara_palette, 0) else 0 end), 0);
    new.gemessen := true;
  end if;
  return new;
end $$;
revoke execute on function schimmel_netto_setzen() from public;
drop trigger if exists schimmel_netto on schimmel_messung;
create trigger schimmel_netto before insert or update on schimmel_messung
  for each row execute function schimmel_netto_setzen();

alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_kaliber_idx_check;
alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_kaliber_gueltig;
alter table auftrag_gebinde add constraint auftrag_gebinde_kaliber_gueltig
  check (kaliber_idx >= -1);
comment on column auftrag_gebinde.kaliber_idx is
  'Index in kaliber_baender der Fassung der Arbeit. −1 = Kisten nach Sollgewicht '
  '(ohne Kaliber), wie sie von der Hand-Linie kommen.';

alter table auftrag drop constraint if exists auftrag_fax_nur_waschen;
alter table auftrag add constraint auftrag_fax_nur_waschen
  check (not ist_fax or station = 'waschen') not valid;
comment on column auftrag.ist_fax is
  'Fax: Etikettieren und Abpacken nach Bestellung, dabei wird Faules aussortiert. '
  'Kein Waschgang — die Station bleibt nur technisch „waschen"; jede Rechnung, die '
  'Waschen meint, nimmt ist_fax aus (0051).';

create or replace function sortierschema_festlegen(
  p_sorte text, p_kaeufer text, p_art text,
  p_baender jsonb default null, p_soll numeric default null, p_bemerkung text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_alt  sortierschema%rowtype;
  v_id   bigint;
  v_von  int; v_bis int; v_prev int; v_i int;
  v_gleich boolean;
begin
  if not (ist_aktiv() or ist_admin()) then
    raise exception 'Nur angemeldete Arbeiter dürfen eine Fassung festlegen.';
  end if;
  if p_art not in ('kaliber', 'kiste') then
    raise exception 'Unbekannte Sortierart „%".', p_art;
  end if;
  if not exists (select 1 from sorte_kaliber where sorte = p_sorte) then
    raise exception 'Unbekannte Sorte „%".', p_sorte;
  end if;

  if p_art = 'kaliber' then
    if p_baender is null or jsonb_typeof(p_baender) <> 'array' or jsonb_array_length(p_baender) = 0 then
      raise exception 'Kaliberbänder fehlen.';
    end if;
    v_prev := null;
    for v_i in 0 .. jsonb_array_length(p_baender) - 1 loop
      v_von := (p_baender -> v_i ->> 0)::int;
      v_bis := (p_baender -> v_i ->> 1)::int;
      if v_von is null or v_bis is null or v_von < 0 or v_bis <= v_von then
        raise exception 'Band % ist nicht aufsteigend (%–% g).', v_i + 1, v_von, v_bis;
      end if;
      if v_prev is not null and v_von <> v_prev then
        raise exception 'Band % beginnt bei % g, Band % endet aber bei % g — die Bänder müssen lückenlos anschliessen.',
          v_i + 1, v_von, v_i, v_prev;
      end if;
      v_prev := v_bis;
    end loop;
    v_von := (p_baender -> 0 ->> 0)::int;
    v_bis := v_prev;
  else
    if p_soll is null or p_soll <= 0 then
      raise exception 'Sollgewicht je Kiste fehlt.';
    end if;
  end if;

  -- Gilt heute schon genau das? Dann ist es dieselbe Fassung — auch wenn es
  -- die Standardfassung ohne Käufer ist.
  select * into v_alt from sortierschema
   where id = sortierschema_fuer(p_sorte, p_kaeufer, current_date, p_art);
  if found then
    v_gleich := case when p_art = 'kaliber'
                     then v_alt.kaliber_baender = p_baender
                     else v_alt.soll_kg_pro_kiste = p_soll end;
    if v_gleich then return v_alt.id; end if;
  end if;

  -- Sonst die Fassung von heute für diese Sorte, diesen Käufer, diese Art:
  -- gibt es sie schon, wird sie ersetzt (zweimal am selben Tag ist dieselbe
  -- Einstellung); sonst entsteht sie neu. Ältere Fassungen bleiben unberührt.
  select id into v_id from sortierschema
   where sorte = p_sorte and kaeufer is not distinct from p_kaeufer
     and art = p_art and gilt_ab = current_date;
  if v_id is not null then
    update sortierschema
       set verlust_unter = case when p_art = 'kaliber' then v_von end,
           kaliber_baender = case when p_art = 'kaliber' then p_baender end,
           kanal_ab = case when p_art = 'kaliber' then v_bis end,
           soll_kg_pro_kiste = case when p_art = 'kiste' then p_soll end,
           bemerkung = coalesce(p_bemerkung, bemerkung),
           erfasser = coalesce(auth.uid(), erfasser), ts = now()
     where id = v_id;
  else
    insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender,
                               kanal_ab, soll_kg_pro_kiste, bemerkung, erfasser)
    values (p_sorte, p_kaeufer, current_date, p_art,
            case when p_art = 'kaliber' then v_von end,
            case when p_art = 'kaliber' then p_baender end,
            case when p_art = 'kaliber' then v_bis end,
            case when p_art = 'kiste' then p_soll end,
            coalesce(p_bemerkung, 'Beim Eröffnen einer Arbeit festgelegt'),
            auth.uid())
    returning id into v_id;
  end if;
  return v_id;
end $$;
comment on function sortierschema_festlegen is
  'Die Fassung, nach der eine Arbeit läuft: Gilt heute schon dasselbe, kommt deren '
  'id zurück; sonst entsteht eine neue Fassung ab heute (oder die von heute wird '
  'ersetzt). Kaliber: Bänder lückenlos aufsteigend, zu klein = erstes von, zu gross '
  '= letztes bis. Kiste: Sollgewicht.';
revoke execute on function sortierschema_festlegen(text, text, text, jsonb, numeric, text) from public;
grant execute on function sortierschema_festlegen(text, text, text, jsonb, numeric, text) to authenticated;

-- aus 0052_demo_saison.sql

alter table kaeufer add column if not exists bemerkung text;
comment on column kaeufer.bemerkung is
  'Freitext zum Käufer. ''DEMO'' markiert die von der Demo-Saison angelegten '
  'Käufer, damit demo_daten_entfernen() nur diese wieder löscht.';

-- aus 0053_zeitlimit.sql

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    raise notice 'Zeitlimit: Rolle authenticated gibt es hier nicht — übersprungen';
    return;
  end if;

  -- Steht es schon auf 30s, ändern wir nichts (und melden auch nichts):
  -- die Datei läuft bei jeder Aktualisierung mit.
  if exists (
    select 1 from pg_roles
     where rolname = 'authenticated'
       and 'statement_timeout=30s' = any(coalesce(rolconfig, '{}'))
  ) then
    return;
  end if;

  alter role authenticated set statement_timeout = '30s';
  raise notice 'Zeitlimit für angemeldete Benutzer auf 30 Sekunden gesetzt (vorher 8)';

exception
  -- Auf einer fremden Datenbank darf man vielleicht keine Rollen ändern.
  -- Das ist kein Grund, die ganze Einrichtung scheitern zu lassen: alles
  -- andere läuft auch mit acht Sekunden, nur das Neurechnen der Auswertung
  -- kann dann abbrechen. Die Meldung sagt, was von Hand zu tun wäre.
  when insufficient_privilege or wrong_object_type then
    raise notice 'Zeitlimit liess sich nicht setzen (keine Berechtigung). '
                 'Von Hand im SQL-Editor: alter role authenticated set statement_timeout = ''30s'';';
end $$;

notify pgrst, 'reload config';

-- aus 0054_eigenes_kaliber.sql

alter table auftrag add column if not exists kaliber_von_g int;
alter table auftrag add column if not exists kaliber_bis_g int;
alter table auftrag drop constraint if exists auftrag_eigenes_kaliber;
alter table auftrag add constraint auftrag_eigenes_kaliber
  check ((kaliber_von_g is null and kaliber_bis_g is null)
      or (kaliber_von_g is not null and kaliber_bis_g is not null
          and kaliber_von_g >= 0 and kaliber_bis_g > kaliber_von_g
          and kaliber_idx is null));
comment on column auftrag.kaliber_von_g is
  'Eigenes Kaliber beim Waschen (0054): untere Grenze in Gramm, wenn das Etikett '
  'keines der Bänder der Fassung nennt. Dann ist kaliber_idx leer.';
comment on column auftrag.kaliber_bis_g is
  'Eigenes Kaliber beim Waschen (0054): obere Grenze in Gramm.';

alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_kaliber_gueltig;
alter table auftrag_gebinde add constraint auftrag_gebinde_kaliber_gueltig
  check (kaliber_idx >= -2);
comment on column auftrag_gebinde.kaliber_idx is
  'Index in kaliber_baender der Fassung der Arbeit. −1 = Kisten nach Sollgewicht '
  '(ohne Kaliber), wie sie von der Hand-Linie kommen. −2 = Kisten zum eigenen '
  'Kaliber der Arbeit (auftrag.kaliber_von_g/bis_g, 0054).';

-- aus 0058_auswertung_haelt_stand.sql

create or replace function zahl(p_wert numeric, p_stellen int default 2,
                                p_grenze numeric default 1e11)
returns numeric language sql immutable parallel safe set search_path = public
as $$
  select case when p_wert is not null and abs(p_wert) < p_grenze
              then round(p_wert, p_stellen) end
$$;
revoke all on function zahl(numeric, int, numeric) from public;
grant execute on function zahl(numeric, int, numeric) to anon, authenticated;

create or replace function zahl(p_wert double precision, p_stellen int default 2,
                                p_grenze numeric default 1e11)
returns numeric language sql immutable parallel safe set search_path = public
as $$ select zahl(p_wert::numeric, p_stellen, p_grenze) $$;
revoke all on function zahl(double precision, int, numeric) from public;
grant execute on function zahl(double precision, int, numeric) to anon, authenticated;

-- aus 0060_punktuell_erfasst_vollstaendig_gerechnet.sql

create or replace function palox_station(p_station station) returns station
language sql immutable parallel safe as $$
  -- voll qualifiziert: die Funktion wird in Sichten eingebettet und muss auch
  -- mit leerem Suchpfad rechnen (Prüfblock „Suchpfad")
  select case when p_station = 'waschen_sortieren'::public.station then 'waschen'::public.station else p_station end
$$;
comment on function palox_station(station) is
  'Welcher Palox zu einer Station gehört: die Waschstrasse (waschen und '
  'waschen_sortieren) teilt sich einen, die Sortiermaschine hat ihren eigenen (0060).';
revoke all on function palox_station(station) from public;
grant execute on function palox_station(station) to authenticated;

create or replace function palox_letzter_stand(p_station station)
returns numeric language sql stable as $$
  select s.palox_stand_kg
    from public.schimmel_messung s
    join public.auftrag a on a.id = s.auftrag_id
   where s.palox_stand_kg is not null and s.gemessen
     and public.palox_station(a.station) = public.palox_station(p_station)
   order by s.ts desc, s.id desc limit 1;
$$;

alter table auftrag add column if not exists kistensystem text
  check (kistensystem in ('kiste_ab', 'stueck', 'anderes'));
alter table auftrag add column if not exists soll_kg_pro_kiste numeric(6,2)
  check (soll_kg_pro_kiste > 0);
alter table auftrag add column if not exists stueck_je_kiste int
  check (stueck_je_kiste > 0);
comment on column auftrag.kistensystem is
  'Wie die Kisten nach dem Waschen gefüllt werden: kiste_ab (bis zum Sollgewicht '
  'soll_kg_pro_kiste), stueck (stueck_je_kiste Kürbisse eines Kalibers) oder '
  'anderes. Nur die ersten beiden sind rechenbar — bei „anderes" wird keine '
  'fertige Palette verlangt (0060).';

alter table auftrag add column if not exists paletten_gesamt int
  check (paletten_gesamt >= 0);
alter table auftrag add column if not exists tage_seit_waschen int
  check (tage_seit_waschen >= 0);
comment on column auftrag.paletten_gesamt is
  'Fax: wie viele Paletten gemacht wurden, als Gesamtzahl am Ende eingetragen. '
  'Die Masse folgt aus der gemessenen Nettomasse einer fertigen Palette (0060).';
comment on column auftrag.tage_seit_waschen is
  'Fax, freiwillig: wie lange die Ware seit dem Waschen stand (Tage).';

alter table auftrag_palette add column if not exists brutto_zettel_kg numeric(8,2)
  check (brutto_zettel_kg > 0);
comment on column auftrag_palette.brutto_zettel_kg is
  'Bruttogewicht vom Palettenzettel (Eingangsgewicht), beim Waschen + Sortieren '
  'abgelesen. Damit hat der Palox dieser Arbeit einen Nenner. Das Netto findet '
  'die Auswertung über die Palette im Wareneingang (gleiche Charge, gleiches '
  'Datum, gleiches Brutto), sonst über die mittlere Tara der Charge (0060).';

alter table auftrag_gebinde add column if not exists sortierdatum date;
alter table auftrag_gebinde add column if not exists datum_fehlt boolean not null default false;
alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_auftrag_id_kaliber_idx_key;
alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_eindeutig;
alter table auftrag_gebinde add constraint auftrag_gebinde_eindeutig
  unique nulls not distinct (auftrag_id, kaliber_idx, sortierdatum);
comment on column auftrag_gebinde.sortierdatum is
  'Beim Waschen: das Sortierdatum, das die Arbeiter beim Sortieren auf die Kiste '
  'schreiben. NULL beim Sortieren (dort gibt es noch keins) oder wenn keins auf '
  'der Kiste steht — dann sagt datum_fehlt, dass gefragt wurde (0060).';

update auftrag_gebinde g
   set sortierdatum = x.datum
  from (select distinct on (auftrag_id) auftrag_id, wert::date as datum
          from auftrag_angabe
         where schluessel = 'sortierdatum' and wert ~ '^\d{4}-\d{2}-\d{2}$'
         order by auftrag_id, ts desc) x
 where x.auftrag_id = g.auftrag_id and g.sortierdatum is null;

alter table ausgang_wiegung add column if not exists kaliber_idx int;
comment on column ausgang_wiegung.kaliber_idx is
  'Bei Stück-Kisten: das Kaliber der gewogenen Palette (Index in den Bändern der '
  'Fassung; −2 = eigenes Kaliber der Arbeit). Daraus die Erwartung je Kiste aus '
  'der Sortier-CSV (0060).';

update auftrag a
   set kistensystem = 'kiste_ab', soll_kg_pro_kiste = s.soll_kg_pro_kiste
  from sortierschema s
 where s.id = a.sortierschema_id and s.art = 'kiste' and s.soll_kg_pro_kiste > 0
   and a.kistensystem is null;

do $$
begin
  execute format('alter database %I set jit = off', current_database());
  raise notice 'JIT für die Datenbank % abgeschaltet (gilt ab der nächsten Verbindung).', current_database();
exception when others then
  raise notice 'JIT nicht abgeschaltet (%): die Auswertung rechnet richtig, nur langsamer.', sqlerrm;
end $$;

-- aus 0061_bis_heute_und_gespeichert.sql

create or replace function heute() returns date
language sql stable set search_path = public as $$
  select coalesce((select nullif(wert #>> '{}', '')::date from public.einstellung where schluessel = 'heute_test'),
                  current_date)
$$;
comment on function heute() is
  'Der Tag, bis zu dem gerechnet wird — current_date, im Test die Einstellung heute_test (0061).';
revoke all on function heute() from public;
grant execute on function heute() to authenticated;

create or replace function stichtag() returns date
language sql stable set search_path = public as $$
  select greatest((select nullif(wert #>> '{}', '')::date from public.einstellung where schluessel = 'saison_ende'),
                  public.heute())
$$;
comment on function stichtag() is
  'Bis wohin die Prognose reicht: das Saisonende aus den Einstellungen, mindestens heute (0061).';
revoke all on function stichtag() from public;
grant execute on function stichtag() to authenticated;

alter table auftrag_palette add column if not exists sortierdatum date;
alter table auftrag_palette add column if not exists kisten int check (kisten is null or kisten > 0);
comment on column auftrag_palette.sortierdatum is
  'Beim Waschen: das Sortierdatum vom Zettel der Palette (die Zeit im Zwischenlager). 0061.';
comment on column auftrag_palette.kisten is
  'Beim Waschen: wie viele Kaliber-Kisten auf dieser Palette standen — die Masse ist Kisten × Kistengewicht. 0061.';
create index if not exists auftrag_palette_sortierdatum on auftrag_palette (auftrag_id, sortierdatum);

alter table auftrag_palette drop constraint if exists auftrag_palette_datum_pflicht;
alter table auftrag_palette add constraint auftrag_palette_datum_pflicht
  check (eingangsdatum is not null or sortierdatum is not null or kisten is not null
         or palette_id is not null or wiegung_id is not null)
  not valid;

alter table ausgang_zeile add column if not exists batch_gebinde int;
comment on column ausgang_zeile.batch_gebinde is
  'Kisten dieser Chargenzeile (AufPosBatchPackageQuantity Charge). Die Kistenzahl '
  'der Position steht in gebinde_menge. 0061.';

create or replace function lieferung_import_zeilen_verbinden(p_quelle text default null)
returns int language sql volatile set search_path = public as $$
  with charge_zeilen as (
    update lieferung_import i
       set zeile_id = z.id
      from ausgang_zeile z
     where i.zeile_id is null
       and (p_quelle is null or i.quelle = p_quelle)
       and z.quelle = i.quelle
       and i.extern_id = z.quelle || ':' || z.pos_id || ':' || z.charge_extern || ':' || z.lauf_nr
     returning 1
  ), rest_zeilen as (
    update lieferung_import i
       set zeile_id = z.id
      from (select distinct on (quelle, pos_id) id, quelle, pos_id
              from ausgang_zeile order by quelle, pos_id, lauf_nr, id) z
     where i.zeile_id is null
       and (p_quelle is null or i.quelle = p_quelle)
       and z.quelle = i.quelle
       and i.extern_id = z.quelle || ':' || z.pos_id || ':rest'
     returning 1
  )
  select (select count(*) from charge_zeilen) + (select count(*) from rest_zeilen)
$$;
comment on function lieferung_import_zeilen_verbinden(text) is
  'Trägt lieferung_import.zeile_id aus der Kennung nach (Chargenzeile oder erste '
  'Zeile der Position). Läuft nach jeder Übernahme; einmal für alles Bestehende (0061).';
revoke all on function lieferung_import_zeilen_verbinden(text) from public;
grant execute on function lieferung_import_zeilen_verbinden(text) to authenticated;
do $$ begin perform lieferung_import_zeilen_verbinden(null); end $$;

create or replace function auswertung_schritt(p_schritt int)
returns jsonb language plpgsql security definer
set search_path = public set jit = off as $$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
begin
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'mv_schimmel_punkte', 'mv_schimmel_modell',
                       'erg_punkte', 'erg_modell', 'erg_kurve', 'erg_selektion',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_ueberfuellung', 'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_verlauf', 'erg_bilanz', 'erg_marge',
                       'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  -- Schritt 1 bringt zuerst die Statistik der Rohtabellen auf Stand. Nach
  -- einem grossen Import (Saisonstart, Warenausgang, Demo) schätzt der Planer
  -- sonst mit Zahlen von vorher und wählt Pläne, die um Grössenordnungen
  -- danebenliegen: gemessen 33 Sekunden für Schritt 2, wo er mit frischer
  -- Statistik 1.1 braucht. Das Analysieren aller Rohtabellen kostet auf der
  -- Demo 0.2 Sekunden — der beste Handel im ganzen Rechenwerk.
  if p_schritt = 1 then
    for v_name in
      select c.relname
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r'
       order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
  end if;

  foreach v_name in array v_namen loop
    execute format('refresh materialized view %I', v_name);
    execute format('analyze %I', v_name);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),   -- nicht now(): das wäre der Beginn der Transaktion
           dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif p_schritt = 1 then
    update auswertung_stand
       set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  else
    update auswertung_stand
       set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5);
end $$;
revoke all on function auswertung_schritt(int) from public;
grant execute on function auswertung_schritt(int) to authenticated;

create or replace function auswertung_aktualisieren()
returns timestamptz language plpgsql security definer
set search_path = public set jit = off as $$
declare i int;
begin
  for i in 1..5 loop
    perform auswertung_schritt(i);
  end loop;
  return now();
end $$;

do $$
declare v_id bigint; v_gleich boolean;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    select jobid, (schedule = '*/10 * * * *' and command = 'select public.auswertung_wenn_veraltet()' and active)
      into v_id, v_gleich
      from cron.job where jobname = 'auswertung_wenn_veraltet' order by jobid limit 1;
    if v_id is null then
      perform cron.schedule('auswertung_wenn_veraltet', '*/10 * * * *',
                            'select public.auswertung_wenn_veraltet()');
      raise notice 'Zeitplan: auswertung_wenn_veraltet() alle zehn Minuten (pg_cron) — neu angelegt.';
    elsif v_gleich then
      raise notice 'Zeitplan: auswertung_wenn_veraltet() alle zehn Minuten (pg_cron) — steht schon, bleibt.';
    else
      perform cron.alter_job(job_id => v_id, schedule => '*/10 * * * *',
                             command => 'select public.auswertung_wenn_veraltet()', active => true);
      raise notice 'Zeitplan: auswertung_wenn_veraltet() alle zehn Minuten (pg_cron) — angepasst.';
    end if;
  else
    raise notice 'pg_cron fehlt — die App rechnet selbst nach, wenn etwas veraltet ist.';
  end if;
exception when others then
  raise notice 'Zeitplan nicht angelegt (%): die App rechnet selbst nach.', sqlerrm;
end $$;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;

alter table lieferung drop constraint if exists lieferung_hat_menge;
alter table lieferung add constraint lieferung_hat_menge
  check (kg is not null or kisten is not null) not valid;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;

-- aus 0067_der_tag_des_arbeiters.sql

create or replace function betriebszone() returns text
language sql stable set search_path = public
as $$
  select coalesce(nullif((select wert #>> '{}' from public.einstellung
                           where schluessel = 'zeitzone'), ''), 'Europe/Zurich')
$$;
comment on function betriebszone() is
  'Die Zeitzone, in der der Betrieb steht. Einstellung „zeitzone", Rückfall Europe/Zurich.';

revoke execute on function betriebszone() from public;
grant  execute on function betriebszone() to authenticated;

create or replace function betriebstag(p_ts timestamptz) returns date
language sql stable set search_path = public
as $$
  select (p_ts at time zone public.betriebszone())::date
$$;
comment on function betriebstag(timestamptz) is
  'Der Kalendertag eines Zeitpunkts in der Zone des Betriebs — nicht der in UTC. '
  'Überall dort zu benutzen, wo aus einem Zeitstempel ein Tag wird, der mit einem '
  'abgetippten Datum verrechnet wird.';
revoke execute on function betriebstag(timestamptz) from public;
grant  execute on function betriebstag(timestamptz) to authenticated;

create or replace function heute() returns date
language sql stable set search_path = public
as $$
  select coalesce((select nullif(wert #>> '{}', '')::date from public.einstellung
                    where schluessel = 'heute_test'),
                  public.betriebstag(now()))
$$;

insert into einstellung (schluessel, wert)
values ('zeitzone', to_jsonb('Europe/Zurich'::text))
on conflict (schluessel) do nothing;

do $$
declare offen text;
begin
  select string_agg(c.relname, ', ') into offen
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and pg_get_viewdef(c.oid, true) ~ '[a-z_][a-z0-9_]*(_ts|_zeit)\s*::\s*date';
  if offen is not null then
    raise exception 'Diese Sichten mischen weiterhin UTC-Tag und Betriebstag: %', offen;
  end if;
end $$;

do $$
declare
  r record;
  v_offen bigint;
begin
  for r in
    select c.conrelid::regclass::text as tabelle, c.conname as name,
           pg_get_expr(c.conbin, c.conrelid) as bedingung
      from pg_constraint c
      join pg_namespace n on n.oid = c.connamespace
     where n.nspname = 'public'
       and not c.convalidated
       and c.conname in ('auftrag_fax_nur_waschen', 'auftrag_kaliber_nur_waschen',
                         'auftrag_palette_datum_pflicht', 'lieferung_hat_menge')
     order by c.conname
  loop
    execute format('select count(*) from %s where not (%s)', r.tabelle, r.bedingung)
      into v_offen;
    if v_offen = 0 then
      execute format('alter table %s validate constraint %I', r.tabelle, r.name);
      raise notice 'Zusage % bestätigt (keine Zeile verstösst dagegen).', r.name;
    else
      raise notice 'Zusage % bleibt unbestätigt: % Zeile(n) in % erfüllen sie nicht. '
                   'Für neue Zeilen gilt sie weiter; die vorhandenen stehen unter '
                   'Auffälligkeiten.', r.name, v_offen, r.tabelle;
    end if;
  end loop;
end $$;

drop index if exists auftrag_palette_auftrag_id_idx;
drop index if exists ausschuss_auftrag;
drop index if exists schimmel_auftrag;
drop index if exists palette_charge_nr_eingangsdatum_idx;
drop index if exists auftrag_aktiv;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;

create or replace function zahl(p_wert numeric, p_stellen integer default 2,
                                p_grenze numeric default 100000000000)
returns numeric language sql immutable parallel safe set search_path = public
as $$
  select case when p_wert is not null and abs(round(p_wert, p_stellen)) < p_grenze
              then round(p_wert, p_stellen) end
$$;
comment on function zahl(numeric, integer, numeric) is
  'Rundet und lässt alles über der Grenze weg. Seit 0068 wird der **gerundete** '
  'Wert gegen die Grenze gehalten: vorher konnte ein Wert knapp darunter die '
  'Prüfung bestehen und beim Runden darüber gehoben werden, worauf numeric(14,2) '
  'ihn abwies und das ganze Neurechnen abbrach. Das Fenster war 0.005 kg breit '
  'bei 10^12 kg.';

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;

-- aus 0070_die_zeit_laeuft_vorwaerts.sql

set client_min_messages = warning;

-- aus 0072_die_erfassung_scharf_schalten.sql

set client_min_messages = warning;

alter table auftrag add column if not exists palox_unbekannt boolean not null default false;
comment on column auftrag.palox_unbekannt is
  'Der Palox wurde während dieser Arbeit geleert. Die Faul-Menge der Arbeit '
  'ist damit unbekannt — nicht null. Die Auswertung lässt die Arbeit aus der '
  'Verderbsrechnung heraus; die Ablesungen selbst bleiben erhalten. Gesetzt '
  'wird die Spalte, wenn der Stand fällt oder der Abschluss danach fragt.';

create or replace function palox_stand_dieser_arbeit(p_auftrag_id bigint)
returns numeric language sql stable set search_path = public as $$
  select s.palox_stand_kg
    from public.schimmel_messung s
   where s.auftrag_id = p_auftrag_id
     and s.palox_stand_kg is not null and s.gemessen
   order by s.ts desc, s.id desc limit 1;
$$;
comment on function palox_stand_dieser_arbeit(bigint) is
  'Was die Palox-Waage zuletzt in DIESER Arbeit zeigte. Arbeitsschritte werden '
  'nie über Nacht pausiert; zwischen zwei Arbeiten liegt unbekannt viel. Der '
  'Stand vom letzten Mal sagt deshalb nichts über den Anfang dieser Arbeit '
  '(0072). palox_letzter_stand(station) bleibt bestehen, wird aber von keiner '
  'Maske mehr zur Differenzbildung benutzt.';
revoke all on function palox_stand_dieser_arbeit(bigint) from public;
grant execute on function palox_stand_dieser_arbeit(bigint) to authenticated;

alter table auftrag_palette add column if not exists gebindeart text
  references gebinde(art) on update cascade;
comment on column auftrag_palette.gebindeart is
  'In welchem Gebinde die Palette steht. Beim Waschen aus dem Zwischenlager '
  'gefragt, weil die Tara davon abhängt und sich das Gebinde an der '
  'Waschstrasse ändert (G2 → IFCO). Der Betrieb: „meistens G2, aber auch nur '
  'so 95 %" — also gefragt, nicht vorausgesetzt (0072).';

alter table auftrag add column if not exists fertige_paletten_gesamt int
  check (fertige_paletten_gesamt is null or fertige_paletten_gesamt >= 0);
comment on column auftrag.fertige_paletten_gesamt is
  'Waschen und Waschen + Sortieren: wie viele fertige Paletten am Ende '
  'insgesamt dastanden. Die App kennt sonst nur die *gewogenen*. Ohne diese '
  'Zahl ist die Ausgangsmasse unbekannt — nicht null. Nicht Pflicht: der '
  'Betrieb sagt „die fertigen paletten werden eher nicht gezählt" (0072).';

alter table ausgang_wiegung add column if not exists voll boolean not null default true;
comment on column ausgang_wiegung.voll is
  'Ob diese fertige Palette voll ist. Der Betrieb: „vlt die ersten beiden '
  'paletten je 40 kisten ifco und die letzte vlt nur 24". Eine nicht volle '
  'Palette zählt für die Masse, aber nicht für kg je Kiste und Kürbisse je '
  'Kiste — sonst zieht sie den Koeffizienten nach unten (0072).';

alter table charge add column if not exists ernte_abgeschlossen_ts timestamptz;
comment on column charge.ernte_abgeschlossen_ts is
  'Wann der Betrieb gesagt hat, dass von dieser Charge nichts mehr kommt. Ab '
  'dann ist das massegewichtete mittlere Eingangsdatum endgültig und die '
  'Streuung der Erntedaten belastbar. Vorher trägt jede Altersangabe den '
  'Zusatz „Ernte läuft noch" (0072).';

create table if not exists kontrollpalette (
  id            bigserial primary key,
  charge_nr     int  not null references charge(nr),
  palette_id    bigint references palette(id),
  kennzeichen   text not null,
  standort      text,
  angelegt_ts   timestamptz not null default now(),
  angelegt_von  uuid not null default auth.uid() references profil(id),
  beendet_ts    timestamptz,
  beendet_grund text,
  bemerkung     text
);
comment on table kontrollpalette is
  'Eine markierte Palette, die eine Saison lang stehen bleibt und nur gewogen '
  'wird. Fünf Stück auf den ertragsstärksten Chargen (Antwort des Betriebs). '
  'Wird nie gelöscht — am Ende wird beendet_ts gesetzt und sie verarbeitet.';
comment on column kontrollpalette.kennzeichen is
  'Was auf der Palette steht, damit man sie im Lager wiederfindet.';
create index if not exists kontrollpalette_charge_idx on kontrollpalette (charge_nr);

create table if not exists kontrollpalette_wiegung (
  id                 bigserial primary key,
  kontrollpalette_id bigint not null references kontrollpalette(id),
  brutto_kg          numeric(8,2) not null check (brutto_kg > 0),
  kisten             int not null check (kisten > 0),
  gebindeart         text references gebinde(art) on update cascade,
  sichtbar_schimmel  boolean not null default false,
  erfasser           uuid not null default auth.uid() references profil(id),
  wiege_ts           timestamptz not null default now(),
  ts                 timestamptz not null default now(),
  bemerkung          text
);
comment on table kontrollpalette_wiegung is
  'Eine Wägung einer Kontrollpalette. Gespeichert wird das Brutto mit '
  'Kistenzahl und Gebinde — das Netto ist Ableitung (Beobachtung statt '
  'Folgerung). Zwei aufeinanderfolgende Wägungen ergeben eine Rate für den '
  'Zeitraum dazwischen.';
create index if not exists kontrollpalette_wiegung_pal_ts_idx
  on kontrollpalette_wiegung (kontrollpalette_id, wiege_ts);

alter table kontrollpalette         enable row level security;
alter table kontrollpalette_wiegung enable row level security;

drop policy if exists kp_lesen       on kontrollpalette;
drop policy if exists kp_anlegen     on kontrollpalette;
drop policy if exists kp_aendern     on kontrollpalette;
drop policy if exists kp_loeschen    on kontrollpalette;
create policy kp_lesen    on kontrollpalette for select to authenticated using (true);
create policy kp_anlegen  on kontrollpalette for insert to authenticated
  with check ((angelegt_von = auth.uid() and ist_aktiv()) or ist_admin());
create policy kp_aendern  on kontrollpalette for update to authenticated
  using (ist_admin() or (angelegt_von = auth.uid() and ist_aktiv()));

create policy kp_loeschen on kontrollpalette for delete to authenticated using (ist_admin());

drop policy if exists kpw_lesen    on kontrollpalette_wiegung;
drop policy if exists kpw_erfassen on kontrollpalette_wiegung;
drop policy if exists kpw_aendern  on kontrollpalette_wiegung;
drop policy if exists kpw_loeschen on kontrollpalette_wiegung;
create policy kpw_lesen    on kontrollpalette_wiegung for select to authenticated using (true);
create policy kpw_erfassen on kontrollpalette_wiegung for insert to authenticated
  with check ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
create policy kpw_aendern  on kontrollpalette_wiegung for update to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()));
create policy kpw_loeschen on kontrollpalette_wiegung for delete to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()));

grant select, insert, update, delete on kontrollpalette         to authenticated;
grant select, insert, update, delete on kontrollpalette_wiegung to authenticated;

drop trigger if exists kontrollpalette_veraltet on kontrollpalette;
create trigger kontrollpalette_veraltet after insert or update or delete on kontrollpalette
  for each statement execute function auswertung_veraltet();
drop trigger if exists kontrollpalette_wiegung_veraltet on kontrollpalette_wiegung;
create trigger kontrollpalette_wiegung_veraltet after insert or update or delete on kontrollpalette_wiegung
  for each statement execute function auswertung_veraltet();

create table if not exists erfassung_journal (
  id       bigserial primary key,
  tabelle  text not null,
  zeile_id text,
  vorgang  text not null check (vorgang in ('insert', 'update', 'delete')),
  alt      jsonb,
  neu      jsonb,
  wer      uuid,
  wann     timestamptz not null default now()
);
comment on table erfassung_journal is
  'Jede Änderung an jeder Messtabelle. Bei einem Löschen steht die ganze alte '
  'Zeile als jsonb darin — damit ist nichts endgültig weg, auch wenn jemand '
  'löscht. Niemand kann das Journal ändern oder löschen, auch der Admin nicht: '
  'ein Protokoll, das sich bearbeiten lässt, ist keines (0072).';
create index if not exists erfassung_journal_tabelle_wann_idx on erfassung_journal (tabelle, wann desc);
create index if not exists erfassung_journal_zeile_idx on erfassung_journal (tabelle, zeile_id);

create or replace function erfassung_journal_schreiben()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_alt jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_neu jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_zeile text;
begin
  -- Die Kennung der Zeile, ohne den Primärschlüssel jeder Tabelle zu kennen:
  -- id, sonst nr, sonst schluessel, sonst nichts. Die ganze Zeile steht
  -- ohnehin in alt/neu — die Kennung dient nur dem schnellen Nachschlagen.
  v_zeile := coalesce(v_neu, v_alt) ->> 'id';
  if v_zeile is null then v_zeile := coalesce(v_neu, v_alt) ->> 'nr'; end if;
  if v_zeile is null then v_zeile := coalesce(v_neu, v_alt) ->> 'schluessel'; end if;

  insert into erfassung_journal (tabelle, zeile_id, vorgang, alt, neu, wer)
  values (tg_table_name, v_zeile, lower(tg_op), v_alt, v_neu, auth.uid());
  return null;
end $$;
comment on function erfassung_journal_schreiben() is
  'Hängt nach jeder Zeilenänderung an einer Messtabelle und schreibt sie ins '
  'erfassung_journal. security definer, damit auch ein Arbeiter ohne Rechte '
  'auf dem Journal protokolliert wird — sonst könnte genau der, dessen '
  'Änderung festzuhalten wäre, sie ungesehen machen.';

revoke all on function erfassung_journal_schreiben() from public;
grant execute on function erfassung_journal_schreiben() to authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'schimmel_messung', 'ausschuss_messung', 'ausgang_wiegung', 'verdunstung_wiegung',
    'marge_messung', 'auftrag', 'auftrag_palette', 'auftrag_gebinde', 'auftrag_angabe',
    'auftrag_teilnehmer', 'palette', 'lieferung', 'sortier_lauf', 'sortier_gewicht',
    'kontrollpalette', 'kontrollpalette_wiegung', 'charge_vorlauf']
  loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists %I on %I', t || '_journal', t);
      execute format('create trigger %I after insert or update or delete on %I '
                     'for each row execute function erfassung_journal_schreiben()',
                     t || '_journal', t);
    end if;
  end loop;
end $$;

alter table erfassung_journal enable row level security;
drop policy if exists journal_lesen on erfassung_journal;
create policy journal_lesen on erfassung_journal for select to authenticated using (ist_admin());

revoke all on erfassung_journal from authenticated, anon;
grant select on erfassung_journal to authenticated;

create or replace function arbeit_offen(p_auftrag_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select status = 'offen' from public.auftrag where id = p_auftrag_id), true);
$$;
comment on function arbeit_offen(bigint) is
  'Ob die Arbeit noch offen ist. Nach dem Abschluss darf eine Messzeile nur '
  'noch korrigiert werden, nicht gelöscht — ausser durch den Admin (0072).';
revoke all on function arbeit_offen(bigint) from public;
grant execute on function arbeit_offen(bigint) to authenticated;

drop policy if exists schimmel_zuruecknehmen on schimmel_messung;
create policy schimmel_zuruecknehmen on schimmel_messung for delete to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()
                         and arbeit_offen(auftrag_id)));

drop policy if exists ausschuss_zuruecknehmen on ausschuss_messung;
create policy ausschuss_zuruecknehmen on ausschuss_messung for delete to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()
                         and arbeit_offen(auftrag_id)));

drop policy if exists ausgang_zuruecknehmen on ausgang_wiegung;
create policy ausgang_zuruecknehmen on ausgang_wiegung for delete to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()
                         and arbeit_offen(auftrag_id)));

update einstellung set wert = '36'::jsonb,
       bemerkung = 'Wie viele Kisten in der Regel auf einer Palette stehen. '
                   'Vorbelegung der Maske, keine Annahme der Rechnung — je Palette '
                   'wird gefragt, weil es teils 32 und teils 36 sind (0072).'
 where schluessel = 'kisten_pro_palette' and wert = '32'::jsonb
   and bemerkung is null;

insert into einstellung (schluessel, wert, bemerkung) values
  ('betriebsmodus', '"echt"'::jsonb,
   'echt oder beispiel. Im Beispielmodus zeigt die App ein dauerhaftes Band '
   '„Beispieldaten — nicht der Betrieb"; im Echtmodus verweigern die '
   'Demo-Daten ihren Dienst. Steht in der Datenbank und nicht im Build, damit '
   'eine falsch gebaute Seite nicht behaupten kann, sie sei die andere (0072).'),
  ('gebinde_lager', '"G2"'::jsonb,
   'Welches Gebinde im Lager vorbelegt wird. Der Betrieb: „meistens G2, aber '
   'auch nur so 95 %" — eine Vorbelegung, keine Annahme (0072).'),
  ('fax_tage_vorgabe', '4'::jsonb,
   'Wie viele Tage zwischen Waschen und Fax angenommen werden, wenn die App '
   'nichts Besseres weiss. Der Betrieb: „vlt gehen wir einfach von durchschnitt '
   'von 4 tagen aus". Ausdrücklich eine Annahme, keine Messung (0072).'),
  ('erfassung_scharf', 'false'::jsonb,
   'Stehen auf dieser Datenbank echte Erfassungsdaten? Steht sie auf true, '
   'warnt setup.sql beim Einspielen deutlich (0072).'),
  ('letzte_sicherung', 'null'::jsonb,
   'Wann der Betrieb zuletzt eine Sicherung gezogen hat, von Hand vermerkt. '
   'Kein automatischer Mechanismus — eine Erinnerung, die man nicht übersieht.'),
  ('ernte_abgeschlossen', 'false'::jsonb,
   'Ist die Ernte der Saison durch? Dann stehen alle mittleren Eingangsdaten '
   'fest. Einzelne Chargen lassen sich über charge.ernte_abgeschlossen_ts '
   'vorher schon abschliessen (0072).'),
  ('kontrollpalette_tage_anfang', '14'::jsonb,
   'Abstand der Kontrollpaletten-Wägungen in den ersten vier Wochen. Der '
   'Betrieb vermutet am Anfang einen Schock beim Einlagern — dort muss dichter '
   'gemessen werden als später (0072).'),
  ('kontrollpalette_tage_spaeter', '30'::jsonb,
   'Abstand der Kontrollpaletten-Wägungen nach den ersten vier Wochen.')
on conflict (schluessel) do nothing;

create or replace function demo_nur_im_beispielmodus()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce((select wert #>> '{}' from public.einstellung
                where schluessel = 'betriebsmodus'), 'echt') = 'echt' then
    raise exception
      'Diese Datenbank läuft im Echtmodus — Beispieldaten werden nicht geladen. '
      'Für die Beispiel-Webseite gibt es eine eigene Datenbank. Soll es hier '
      'doch eine sein: einstellung betriebsmodus auf "beispiel" setzen.';
  end if;
  return new;
end $$;
comment on function demo_nur_im_beispielmodus() is
  'Hält Beispieldaten aus einer Datenbank im Echtmodus heraus (0072).';
revoke all on function demo_nur_im_beispielmodus() from public;
grant execute on function demo_nur_im_beispielmodus() to authenticated;

drop trigger if exists palette_keine_demo on palette;
create trigger palette_keine_demo before insert on palette
  for each row when (new.extern_id like 'demo-%')
  execute function demo_nur_im_beispielmodus();

drop trigger if exists sortier_lauf_keine_demo on sortier_lauf;
create trigger sortier_lauf_keine_demo before insert on sortier_lauf
  for each row when (new.datei_name like 'DEMO-%')
  execute function demo_nur_im_beispielmodus();

-- aus 0073_palox_je_arbeit_und_ehrliches_alter.sql

set client_min_messages = warning;

-- aus 0074_die_eingangspalette_darf_kisten_haben.sql

set client_min_messages = warning;

-- aus 0075_woher_die_verderbszahl_kommt.sql

set client_min_messages = warning;

-- aus 0077_die_kontrollpalette_kennt_ihren_eingang.sql

alter table kontrollpalette
  add column if not exists eingangsdatum     date,
  add column if not exists brutto_eingang_kg numeric(8,2)
    check (brutto_eingang_kg is null or brutto_eingang_kg > 0);

comment on column kontrollpalette.eingangsdatum is
  'Das Eingangsdatum vom Zettel an der Palette — freiwillig beim Anlegen (0077).';
comment on column kontrollpalette.brutto_eingang_kg is
  'Das Bruttogewicht beim Wareneingang vom Zettel, mit denselben Kisten wie '
  'die Wägungen — freiwillig; fehlt es, beginnt die Kurve bei der ersten Wägung (0077).';

-- aus 0078_das_lager_nach_kaliber_und_fax_auf_eis.sql

set client_min_messages = warning;

insert into einstellung (schluessel, wert, bemerkung) values
  ('fax_eingefroren', 'true'::jsonb,
   'Fax (Faules beim Abpacken) wird nicht erfasst — Entscheid des Betriebs (Runde R). '
   'Solange true, ist der erwartete Fax-Anteil 0 durch Entscheid (bekannt, nicht '
   'unbekannt), und die App bietet keine Fax-Arbeit an. false: wie vor Runde R.')
on conflict (schluessel) do nothing;

-- aus 0079_der_messtag_der_nenner_und_die_glocke.sql

set client_min_messages = warning;

-- aus 0080_tabula_rasa_vor_dem_testtag.sql

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
    ('charge_vorlauf',          'Angaben zum Erfassungsbeginn',      (select count(*) from charge_vorlauf))
  ) as t(tabelle, was, zeilen)
  where zeilen > 0
  order by zeilen desc;
$$;

comment on function erfassung_umfang() is
  'Was der Löschknopf treffen würde, Tabelle für Tabelle, ohne etwas zu ändern. '
  'Nur Zeilen mit Inhalt. Dieselben 19 Tabellen, die erfassung_leeren() leert — '
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
  -- Journal-Auslöser, sofern die Tabelle ihn trägt (16 von 19 tun es).
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
  'erfassung_journal; ausgang_datei, ausgang_zeile und lieferung_import tragen den '
  'Auslöser nicht und sind nur über die hochgeladene Datei wiederherstellbar. Rechnet die '
  'Auswertung nicht neu — eigener Aufruf, wie bei demo_daten_laden() (0080).';

revoke all on function erfassung_leeren(text) from public;
grant execute on function erfassung_leeren(text) to authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_beispiel boolean := coalesce(
    (select wert #>> '{}' from einstellung where schluessel = 'betriebsmodus'), 'echt') = 'beispiel';
begin
  insert into public.profil (id, name, anonym, rolle)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'name', ''),
             nullif(split_part(new.email, '@', 1), ''),
             'Gast'),
    new.email is null,
    case when v_beispiel then 'admin' else 'arbeiter' end::rolle
  )
  on conflict (id) do nothing;
  return new;
end $$;

comment on function public.handle_new_user is
  'Legt zu jedem neuen Konto das Profil an. In einer Beispieldatenbank '
  '(einstellung.betriebsmodus = ''beispiel'') wird es zum Betriebsleiter, damit '
  'ein Demo-Besucher auch das Dashboard sieht; in der Datenbank des Betriebs '
  'bleibt es beim Arbeiter (0081).';

-- aus 0082_zwei_arten_von_sortierdatei.sql

alter table sortier_lauf add column if not exists art text not null default 'lauf';
do $$ begin
  alter table sortier_lauf add constraint sortier_lauf_art_check
    check (art in ('lauf', 'sammel'));
exception when duplicate_object then null; end $$;
comment on column sortier_lauf.art is
  '''lauf'': ein Sortierlauf, das Datum steht im Dateinamen. ''sammel'': die '
  'kumulative Datei einer ganzen Charge ohne Datum, bei der die Maschine bei '
  'jedem Sortieren unten anhängt. Bei ''sammel'' trägt der Lauf nur das DELTA '
  'zur vorigen Lesung, damit nichts doppelt zählt (0082).';

alter table sortier_lauf add column if not exists von_ts timestamptz;
alter table sortier_lauf add column if not exists bis_ts timestamptz;
comment on column sortier_lauf.von_ts is
  'Frühester Zeitpunkt, zu dem ein Kürbis dieser Lesung sortiert worden sein '
  'kann: das Ende der vorigen Lesung derselben Sammeldatei, sonst der erste '
  'Eingang der Charge — vor dem Eingang kann nichts sortiert worden sein. Bei '
  'einer Lauf-Datei gleich datei_zeit (0082).';
comment on column sortier_lauf.bis_ts is
  'Spätester Zeitpunkt: der Zeitstempel der Datei beim Hochladen, sonst der '
  'Zeitpunkt des Einlesens. Bei einer Lauf-Datei gleich datei_zeit (0082).';

alter table sortier_lauf add column if not exists sortiertag date;
alter table sortier_lauf add column if not exists sortiertag_quelle text;
comment on column sortier_lauf.sortiertag is
  'Der Tag, an dem die Kürbisse dieser Lesung gewogen wurden — der Startpunkt '
  'der Verdunstungsrechnung. Bei einer Lauf-Datei abgelesen, bei einer '
  'Sammeldatei abgeleitet. Leer heisst unbekannt, nicht heute (0082).';
comment on column sortier_lauf.sortiertag_quelle is
  'Woher der Sortiertag kommt: ''datei'' (aus dem Dateinamen), ''arbeit'' (genau '
  'eine Sortier-Arbeit der Charge im Zeitfenster), ''arbeiten-mittel'' (mehrere, '
  'nach gezählten Paletten gewichtet), ''fenster-mitte'' (keine Arbeit erfasst — '
  'die Mitte zwischen von_ts und bis_ts), ''betriebsleiter'' (von Hand gesetzt), '
  '''dateistempel'' (der Zeitstempel des Dateisystems — eine obere Schranke, kein '
  'Sortierdatum), ''gelesen'' (der Tag des Einlesens). '
  'Leer: kein Sortiertag bekannt (0082).';

alter table sortier_lauf add column if not exists vorgaenger_id bigint references sortier_lauf(id);
comment on column sortier_lauf.vorgaenger_id is
  'Die vorige Lesung derselben Sammeldatei. Macht die Kette der Lesungen '
  'nachvollziehbar: jede trägt nur, was seit der vorigen dazukam (0082).';

alter table sortier_lauf add column if not exists voll_n_roh int;
comment on column sortier_lauf.voll_n_roh is
  'Rohzeilen der GANZEN Datei bei dieser Lesung — n_roh zählt dagegen nur die '
  'Zeilen, die neu dazukamen. Bei einer Lauf-Datei sind beide gleich (0082).';

create index if not exists sortier_lauf_charge_art_idx on sortier_lauf (charge_nr, art, gelesen_ts);

update sortier_lauf
   set von_ts            = coalesce(von_ts, datei_zeit),
       bis_ts            = coalesce(bis_ts, datei_zeit, gelesen_ts),
       sortiertag        = coalesce(sortiertag, betriebstag(coalesce(datei_zeit, gelesen_ts))),
       sortiertag_quelle = coalesce(sortiertag_quelle,
                             case
                               when datei_zeit is null                    then 'gelesen'
                               when datei_zeit_quelle = 'dateiname'       then 'datei'
                               when datei_zeit_quelle = 'manuell'         then 'betriebsleiter'
                               else 'dateistempel'
                             end),
       voll_n_roh        = coalesce(voll_n_roh, n_roh)
 where sortiertag is null or sortiertag_quelle is null or voll_n_roh is null;

create or replace function sortiertag_bestimmen(
  p_charge_nr int, p_von timestamptz, p_bis timestamptz
) returns table (tag date, quelle text)
language sql stable set search_path = public as $$
  with arbeit as (
    select a.id, betriebstag(a.start_ts) as tag,
           -- Gewicht: was in dieser Arbeit gezählt wurde. Ohne Zählung
           -- zählt die Arbeit einfach als eine — nie als null.
           greatest(coalesce((select count(*) from auftrag_palette p where p.auftrag_id = a.id), 0), 1) as w
      from auftrag a
     where a.charge_nr = p_charge_nr
       and a.station = 'sortieren' and not a.ist_fax
       and a.abgebrochen_ts is null
       and (p_von is null or a.start_ts >= p_von)
       and (p_bis is null or a.start_ts <= p_bis)
  )
  select case
           when (select count(*) from arbeit) = 1 then (select tag from arbeit)
           when (select count(*) from arbeit) > 1 then
             (select (sum(w * (tag - date '2000-01-01')) / sum(w))::int + date '2000-01-01' from arbeit)
           when p_von is not null and p_bis is not null then
             (p_von + (p_bis - p_von) / 2)::date
         end,
         case
           when (select count(*) from arbeit) = 1 then 'arbeit'
           when (select count(*) from arbeit) > 1 then 'arbeiten-mittel'
           when p_von is not null and p_bis is not null then 'fenster-mitte'
         end
$$;
comment on function sortiertag_bestimmen(int, timestamptz, timestamptz) is
  'Der Sortiertag für eine Sammeldatei und woher er kommt. Erfasste '
  'Sortier-Arbeiten im Zeitfenster schlagen die Fenstermitte; ohne Fenster '
  'gibt es keinen Tag — leer ist nicht null (0082).';
revoke all on function sortiertag_bestimmen(int, timestamptz, timestamptz) from public;
grant execute on function sortiertag_bestimmen(int, timestamptz, timestamptz) to authenticated;

create or replace function csv_sammel_speichern(
  p_charge_nr      int,
  p_datei_name     text,
  p_roh_datei_ref  text,
  p_roh_pruefsumme text,
  p_reinigung      jsonb,
  p_n_roh          int,
  p_n_overflow     int,
  p_n_klein        int,
  p_n_dubletten    int,
  p_histogramm     jsonb,
  p_von            timestamptz default null,
  p_bis            timestamptz default null
) returns jsonb language plpgsql as $$
declare
  v_lauf_id   bigint;
  v_vorher    bigint;
  v_n_bekannt int;
  v_n_neu     int;
  v_negativ   jsonb;
  v_von       timestamptz;
  v_bis       timestamptz;
  v_tag       date;
  v_quelle    text;
  v_laeufe    int;
  v_roh_vorher int;
  v_ov_vorher  int;
  v_kl_vorher  int;
  v_du_vorher  int;
begin
  -- Die vorige Lesung derselben Sammeldatei.
  select id, coalesce(bis_ts, gelesen_ts) into v_vorher, v_von
    from sortier_lauf
   where charge_nr = p_charge_nr and art = 'sammel'
   order by gelesen_ts desc, id desc
   limit 1;

  -- Das Fenster. Nach unten: das Ende der vorigen Lesung, sonst der erste
  -- Eingang der Charge — vor dem Eingang kann nichts sortiert worden sein.
  v_von := coalesce(p_von, v_von,
                    (select min(eingangsdatum)::timestamptz from palette where charge_nr = p_charge_nr));
  v_bis := coalesce(p_bis, now());
  if v_von is not null and v_von > v_bis then
    return jsonb_build_object('fehler', 'fenster',
      'meldung', 'Das Zeitfenster endet vor seinem Anfang.');
  end if;

  -- Was frühere Sammel-Lesungen dieser Charge schon tragen — an Kürbissen
  -- und an Trichterzahlen. Jede gespeicherte Zahl einer Lesung sagt, was
  -- DIESE Lesung dazugebracht hat; die Summe über alle Lesungen ist die
  -- Zahl der ganzen Datei. So bleiben n_roh, n_overflow, n_klein,
  -- n_dubletten und n_gueltig untereinander vergleichbar.
  select coalesce(sum(g.anzahl), 0)::int into v_n_bekannt
    from sortier_gewicht g
    join sortier_lauf l on l.id = g.lauf_id
   where l.charge_nr = p_charge_nr and l.art = 'sammel';

  select coalesce(sum(n_roh), 0)::int, coalesce(sum(n_overflow), 0)::int,
         coalesce(sum(n_klein), 0)::int, coalesce(sum(n_dubletten), 0)::int
    into v_roh_vorher, v_ov_vorher, v_kl_vorher, v_du_vorher
    from sortier_lauf where charge_nr = p_charge_nr and art = 'sammel';

  -- Die Probe: Wird eine Stufe negativ, ist die Datei keine reine
  -- Erweiterung. Dann wird nichts übernommen.
  with voll as (
    select (e->>0)::int as gewicht_g, (e->>1)::int as anzahl
      from jsonb_array_elements(p_histogramm) e
  ), bekannt as (
    select g.gewicht_g, sum(g.anzahl)::int as anzahl
      from sortier_gewicht g
      join sortier_lauf l on l.id = g.lauf_id
     where l.charge_nr = p_charge_nr and l.art = 'sammel'
     group by g.gewicht_g
  ), d as (
    select coalesce(v.gewicht_g, b.gewicht_g) as gewicht_g,
           coalesce(v.anzahl, 0) - coalesce(b.anzahl, 0) as diff
      from voll v full join bekannt b on b.gewicht_g = v.gewicht_g
  )
  select coalesce(sum(diff) filter (where diff > 0), 0)::int,
         coalesce(jsonb_agg(jsonb_build_array(gewicht_g, -diff) order by gewicht_g)
                  filter (where diff < 0), '[]'::jsonb)
    into v_n_neu, v_negativ
    from d;

  if jsonb_array_length(v_negativ) > 0 then
    return jsonb_build_object(
      'fehler', 'keine_erweiterung',
      'negativ', v_negativ,
      'meldung', 'Diese Datei ist keine Erweiterung der zuletzt eingelesenen: '
              || jsonb_array_length(v_negativ)
              || ' Gewichtsstufen fehlen darin. Wurde die Datei bearbeitet, oder '
              || 'gehört sie zu einer anderen Charge?');
  end if;

  if v_n_neu = 0 then
    return jsonb_build_object('fehler', 'nichts_neu',
      'n_bekannt', v_n_bekannt,
      'meldung', 'In dieser Datei steht nichts, was nicht schon eingelesen wäre.');
  end if;

  select tag, quelle into v_tag, v_quelle from sortiertag_bestimmen(p_charge_nr, v_von, v_bis);

  -- Eine Sammel-Lesung gehört zu keiner einzelnen Arbeit: `zuordnung` bleibt
  -- auf dem Vorgabewert und bedeutet für sie nichts. Die Warteschlange fragt
  -- deshalb nach `art = 'lauf'` — nicht nach dem Status.
  insert into sortier_lauf (charge_nr, datei_name, roh_datei_ref, roh_pruefsumme,
                            art, von_ts, bis_ts, sortiertag, sortiertag_quelle,
                            vorgaenger_id, voll_n_roh, reinigung,
                            n_roh, n_overflow, n_klein, n_dubletten, n_gueltig)
  values (p_charge_nr, p_datei_name, p_roh_datei_ref, p_roh_pruefsumme,
          'sammel', v_von, v_bis, v_tag, v_quelle,
          v_vorher, p_n_roh, p_reinigung,
          greatest(p_n_roh       - v_roh_vorher, 0),
          greatest(p_n_overflow  - v_ov_vorher,  0),
          greatest(p_n_klein     - v_kl_vorher,  0),
          greatest(p_n_dubletten - v_du_vorher,  0),
          v_n_neu)
  returning id into v_lauf_id;

  -- Nur das Delta wird gespeichert.
  insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
  with voll as (
    select (e->>0)::int as gewicht_g, (e->>1)::int as anzahl
      from jsonb_array_elements(p_histogramm) e
  ), bekannt as (
    select g.gewicht_g, sum(g.anzahl)::int as anzahl
      from sortier_gewicht g
      join sortier_lauf l on l.id = g.lauf_id
     where l.charge_nr = p_charge_nr and l.art = 'sammel' and l.id <> v_lauf_id
     group by g.gewicht_g
  )
  select v_lauf_id, v.gewicht_g, v.anzahl - coalesce(b.anzahl, 0), 'unklassiert', null
    from voll v left join bekannt b on b.gewicht_g = v.gewicht_g
   where v.anzahl - coalesce(b.anzahl, 0) > 0;

  perform lauf_neu_klassieren(v_lauf_id);

  select count(*)::int into v_laeufe
    from sortier_lauf where charge_nr = p_charge_nr and art = 'lauf';

  return jsonb_build_object(
    'lauf_id', v_lauf_id,
    'n_neu', v_n_neu,
    'n_bekannt', v_n_bekannt,
    'sortiertag', v_tag,
    'sortiertag_quelle', v_quelle,
    'von', v_von, 'bis', v_bis,
    'lauf_dateien', v_laeufe);
end $$;
comment on function csv_sammel_speichern is
  'Liest eine Sammeldatei ein: speichert nur, was seit der vorigen Lesung '
  'dazukam, und weist die Datei ab, wenn sie keine Erweiterung der vorigen ist. '
  'Gibt zurück, was übernommen wurde, welcher Sortiertag gilt und woher er '
  'kommt (0082).';

revoke all on function csv_sammel_speichern(int, text, text, text, jsonb, int, int,
                                            int, int, jsonb, timestamptz, timestamptz) from public;
grant execute on function csv_sammel_speichern(int, text, text, text, jsonb, int, int,
                                               int, int, jsonb, timestamptz, timestamptz) to authenticated;

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
                            n_roh, n_overflow, n_klein, n_dubletten, n_gueltig,
                            art, von_ts, bis_ts, voll_n_roh,
                            sortiertag, sortiertag_quelle)
  values (p_charge_nr, p_datei_name, p_roh_datei_ref, p_roh_pruefsumme,
          p_datei_zeit, p_datei_zeit_quelle, p_reinigung,
          p_n_roh, p_n_overflow, p_n_klein, p_n_dubletten, v_gueltig,
          -- Eine Lauf-Datei ist ein Zeitpunkt, kein Zeitraum: von und bis
          -- fallen zusammen, und voll_n_roh ist n_roh.
          'lauf', p_datei_zeit, coalesce(p_datei_zeit, now()), p_n_roh,
          betriebstag(coalesce(p_datei_zeit, now())),
          case
            when p_datei_zeit is null              then 'gelesen'
            when p_datei_zeit_quelle = 'dateiname' then 'datei'
            when p_datei_zeit_quelle = 'manuell'   then 'betriebsleiter'
            else 'dateistempel'
          end)
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
comment on function csv_lauf_speichern is
  'Liest eine Lauf-Datei ein — einen Sortierlauf mit Datum im Namen. Seit 0082 '
  'füllt sie auch art, das Zeitfenster und den Sortiertag mit seiner Quelle; '
  'ohne den fiele der Lauf aus der Verdunstungsrechnung.';

create or replace function lesung_als_sammel(
  p_lauf_id bigint,
  p_von     timestamptz default null,
  p_bis     timestamptz default null
) returns jsonb language plpgsql as $$
declare
  v_lauf    sortier_lauf%rowtype;
  v_von     timestamptz;
  v_bis     timestamptz;
  v_tag     date;
  v_quelle  text;
  v_negativ jsonb;
  v_neu     int;
  v_vorher  bigint;
begin
  select * into v_lauf from sortier_lauf where id = p_lauf_id;
  if not found then
    return jsonb_build_object('fehler', 'unbekannt', 'meldung', 'Diese Lesung gibt es nicht.');
  end if;
  if v_lauf.art = 'sammel' then
    return jsonb_build_object('fehler', 'schon_sammel',
      'meldung', 'Diese Lesung gilt bereits als Sammeldatei.');
  end if;

  -- Das Fenster: nach unten die letzte Sammel-Lesung derselben Charge, sonst
  -- der erste Eingang — vor dem Eingang kann nichts sortiert worden sein.
  -- Nach oben der Zeitstempel der Datei, sonst der Zeitpunkt des Einlesens.
  select id, coalesce(bis_ts, gelesen_ts) into v_vorher, v_von
    from sortier_lauf
   where charge_nr = v_lauf.charge_nr and art = 'sammel' and id <> p_lauf_id
   order by gelesen_ts desc, id desc limit 1;

  v_von := coalesce(p_von, v_von,
             (select min(eingangsdatum)::timestamptz from palette where charge_nr = v_lauf.charge_nr));
  v_bis := coalesce(p_bis, v_lauf.datei_zeit, v_lauf.gelesen_ts);
  if v_von is not null and v_von > v_bis then
    return jsonb_build_object('fehler', 'fenster',
      'meldung', 'Das Zeitfenster endet vor seinem Anfang.');
  end if;

  -- Trägt diese Lesung Kürbisse, die eine frühere Sammel-Lesung derselben
  -- Charge schon hat? Dann ist sie eine spätere Lesung derselben Datei und
  -- darf nur ihr Delta behalten.
  with bekannt as (
    select g.gewicht_g, sum(g.anzahl)::int as anzahl
      from sortier_gewicht g join sortier_lauf l on l.id = g.lauf_id
     where l.charge_nr = v_lauf.charge_nr and l.art = 'sammel' and l.id <> p_lauf_id
     group by g.gewicht_g
  ), d as (
    select coalesce(v.gewicht_g, b.gewicht_g) as gewicht_g,
           coalesce(v.anzahl, 0) - coalesce(b.anzahl, 0) as diff
      from (select gewicht_g, anzahl from sortier_gewicht where lauf_id = p_lauf_id) v
      full join bekannt b on b.gewicht_g = v.gewicht_g
  )
  select coalesce(sum(diff) filter (where diff > 0), 0)::int,
         coalesce(jsonb_agg(jsonb_build_array(gewicht_g, -diff) order by gewicht_g)
                  filter (where diff < 0), '[]'::jsonb)
    into v_neu, v_negativ
    from d;

  if jsonb_array_length(v_negativ) > 0 then
    return jsonb_build_object('fehler', 'keine_erweiterung', 'negativ', v_negativ,
      'meldung', 'Diese Lesung passt nicht als Fortsetzung der schon vorhandenen '
              || 'Sammel-Lesungen dieser Charge — es fehlen Gewichtsstufen.');
  end if;

  -- Das Delta behalten: was eine frühere Lesung schon trägt, fällt weg.
  --
  -- Die Reihenfolge ist hier kein Geschmack, sondern der Unterschied
  -- zwischen richtig und falsch. Erst wird gelöscht, dann gekürzt — beide
  -- Anweisungen vergleichen mit derselben, ungekürzten Zahl. Stünde das
  -- Kürzen voran, läse das Löschen danach die schon gekürzte Zahl und
  -- nähme auch das weg, was gerade übrig geblieben ist: Aus 6 gelesenen
  -- bei 4 bekannten würden erst 2 — und die 2 sind nicht mehr grösser als
  -- 4, also verschwänden sie. Die Lesung meldete 2 Kürbisse und trüge
  -- keinen einzigen.
  if v_vorher is not null then
    -- Stufen, die vollständig bekannt sind, tragen nichts mehr bei.
    delete from sortier_gewicht g
     using (select gewicht_g, sum(anzahl)::int as anzahl
              from sortier_gewicht sg join sortier_lauf l on l.id = sg.lauf_id
             where l.charge_nr = v_lauf.charge_nr and l.art = 'sammel' and l.id <> p_lauf_id
             group by gewicht_g) b
     where g.lauf_id = p_lauf_id and g.gewicht_g = b.gewicht_g and g.anzahl <= b.anzahl;

    with bekannt as (
      select g.gewicht_g, sum(g.anzahl)::int as anzahl
        from sortier_gewicht g join sortier_lauf l on l.id = g.lauf_id
       where l.charge_nr = v_lauf.charge_nr and l.art = 'sammel' and l.id <> p_lauf_id
       group by g.gewicht_g
    )
    update sortier_gewicht g
       set anzahl = g.anzahl - coalesce(b.anzahl, 0)
      from (select gewicht_g from sortier_gewicht where lauf_id = p_lauf_id) alle
      left join bekannt b on b.gewicht_g = alle.gewicht_g
     where g.lauf_id = p_lauf_id and g.gewicht_g = alle.gewicht_g
       and g.anzahl - coalesce(b.anzahl, 0) > 0;
  end if;

  select tag, quelle into v_tag, v_quelle
    from sortiertag_bestimmen(v_lauf.charge_nr, v_von, v_bis);
  if p_von is not null or p_bis is not null then v_quelle := 'betriebsleiter'; end if;

  update sortier_lauf
     set art               = 'sammel',
         von_ts            = v_von,
         bis_ts            = v_bis,
         -- Der Zeitstempel war nie ein Sortierdatum. Er steht jetzt in
         -- bis_ts; hier stünde er als Messung, die es nie gab.
         datei_zeit        = null,
         sortiertag        = v_tag,
         sortiertag_quelle = v_quelle,
         vorgaenger_id     = v_vorher,
         voll_n_roh        = coalesce(voll_n_roh, n_roh),
         n_gueltig         = v_neu,
         auftrag_id        = null,
         zuordnung         = 'offen'
   where id = p_lauf_id;

  perform lauf_neu_klassieren(p_lauf_id);

  return jsonb_build_object('lauf_id', p_lauf_id, 'n_gueltig', v_neu,
    'sortiertag', v_tag, 'sortiertag_quelle', v_quelle, 'von', v_von, 'bis', v_bis);
end $$;
comment on function lesung_als_sammel(bigint, timestamptz, timestamptz) is
  'Deutet eine schon eingelesene Datei nachträglich als Sammeldatei: Zeitfenster '
  'statt erfundenem Zeitpunkt, abgeleiteter Sortiertag, keine Zuordnung zu einer '
  'Arbeit. Der Zeitstempel der Datei geht nicht verloren — er wird zur oberen '
  'Schranke des Fensters. Gebraucht für die Dateien, die vor 0082 hochgeladen '
  'wurden und in der Warteschlange liegen (0082).';
revoke all on function lesung_als_sammel(bigint, timestamptz, timestamptz) from public;
grant execute on function lesung_als_sammel(bigint, timestamptz, timestamptz) to authenticated;

create or replace function lauf_neu_klassieren(p_lauf_id bigint)
returns int language plpgsql as $$
declare v_schema bigint; v_n int;
begin
  -- Die Fassung: vom Auftrag, sonst vom Lauf, sonst der Standard der Sorte
  -- zum Sortiertag. Ohne Sortiertag bleibt der Tag des Einlesens — besser
  -- eine Fassung als keine Klassierung, aber sortiertag_quelle sagt, dass
  -- der Tag geschätzt ist.
  select coalesce(a.sortierschema_id, l.sortierschema_id,
                  sortierschema_fuer(c.sorte, null,
                                     coalesce(l.sortiertag, betriebstag(coalesce(l.datei_zeit, l.gelesen_ts)))))
    into v_schema
    from sortier_lauf l
    join charge c on c.nr = l.charge_nr
    left join auftrag a on a.id = l.auftrag_id
   where l.id = p_lauf_id;

  update sortier_lauf set sortierschema_id = v_schema where id = p_lauf_id;

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

-- aus 0083_der_ausschuss_stand_nicht_auf_einer_palette.sql

alter table ausschuss_messung
  add column if not exists mit_palette boolean not null default true;
comment on column ausschuss_messung.mit_palette is
  'Stand die Ware beim Wiegen auf einer Palette? Nur dann wird die '
  'Palettentara abgezogen. Vorgabe true, damit die Zeilen von vor 0083 '
  'ihre Bedeutung behalten (0083).';

create or replace function ausschuss_netto_setzen() returns trigger
language plpgsql
as $$
declare v_tara_kiste numeric; v_tara_palette numeric; v_netto numeric; v_tara numeric;
begin
  if new.brutto_kg is not null then
    select g.tara_kg_pro_kiste, g.tara_kg_palette
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    -- Ohne Palette braucht es die Palettentara nicht — dann ist sie 0 und
    -- nicht unbekannt. Die Kistentara braucht es immer.
    v_tara  := new.kisten * v_tara_kiste
             + case when new.mit_palette then v_tara_palette else 0 end;
    v_netto := new.brutto_kg - v_tara;
    if v_netto is null then
      -- Ohne Kistenzahl oder ohne hinterlegte Tara gibt es kein Netto (0066).
      new.gemessen := false;
    elsif v_netto < 0 then
      -- Kein greatest(…, 0) mehr: Ein Brutto unter der Tara ist ein
      -- Widerspruch, keine leere Wägung. So kam bis 0083 jede Kiste, die
      -- ohne Palette auf der Waage stand, als null Kilo an.
      raise exception
        'Das Gewicht (% kg) ist kleiner als die Tara (% × % kg Kiste%) = % kg. So kann die Ware nicht gewogen worden sein — steht sie wirklich auf einer Palette?',
        new.brutto_kg, new.kisten, v_tara_kiste,
        case when new.mit_palette then format(' + Palette %s kg', v_tara_palette) else '' end,
        v_tara;
    else
      new.kg := round(v_netto);
      new.gemessen := true;
    end if;
  end if;
  return new;
end $$;
comment on function ausschuss_netto_setzen() is
  'Setzt kg auf das Netto aus Brutto, Kistenzahl und hinterlegter Tara — die '
  'Palettentara nur, wenn mit_palette (0083). Fehlt eine Angabe, gibt es kein '
  'Netto: die Zeile bleibt stehen, gemessen wird false (0066). Ein negatives '
  'Netto wird zurückgewiesen statt auf null geklemmt (0083).';

create or replace function schimmel_netto_setzen() returns trigger
language plpgsql
as $$
declare v_tara_kiste numeric; v_tara_palette numeric; v_netto numeric; v_tara numeric;
begin
  if new.brutto_kg is not null then
    if new.palox_stand_kg is not null then
      raise exception 'Eine Messung ist entweder eine Palox-Ablesung oder eine Kistenwägung, nicht beides.';
    end if;
    select g.tara_kg_pro_kiste, g.tara_kg_palette
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    v_tara  := new.kisten * v_tara_kiste
             + case when new.mit_palette then v_tara_palette else 0 end;
    v_netto := new.brutto_kg - v_tara;
    if v_netto is null then
      new.gemessen := false;
    elsif v_netto < 0 then
      raise exception
        'Das Gewicht (% kg) ist kleiner als die Tara (% × % kg Kiste%) = % kg. So kann das Faule nicht gewogen worden sein — steht es wirklich auf einer Palette?',
        new.brutto_kg, new.kisten, v_tara_kiste,
        case when new.mit_palette then format(' + Palette %s kg', v_tara_palette) else '' end,
        v_tara;
    else
      new.kg := round(v_netto);
      new.gemessen := true;
    end if;
  end if;
  return new;
end $$;
comment on function schimmel_netto_setzen() is
  'Setzt kg auf das Netto aus Brutto, Kistenzahl und hinterlegter Tara (die '
  'Palettentara nur, wenn die Palette mitgewogen wurde). Fehlt eine nötige '
  'Angabe, gibt es kein Netto: die Zeile bleibt stehen und gemessen wird '
  'false (0066). Ein negatives Netto wird zurückgewiesen (0083).';

do $$
declare v_n int;
begin
  with rep as (
    update ausschuss_messung m
       set mit_palette = false
      from gebinde g
     where g.art = m.gebindeart
       and m.brutto_kg is not null and m.kisten is not null
       and m.gemessen and m.mit_palette
       and m.kg = 0
       -- Mit Palette hätte es null (oder weniger) ergeben …
       and m.brutto_kg - m.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette <= 0
       -- … ohne Palette bleibt etwas übrig. Dann stand keine drunter.
       and m.brutto_kg - m.kisten * g.tara_kg_pro_kiste > 0
    returning m.id)
  select count(*) into v_n from rep;
  if v_n > 0 then
    raise notice '0083: % Ausschuss-Wägungen standen nicht auf einer Palette — Netto nachgerechnet.', v_n;
  end if;
end $$;

-- aus 0084_der_palox_wird_mittendrin_geleert.sql

alter table schimmel_messung
  add column if not exists palox_nach_leeren boolean not null default false;
comment on column schimmel_messung.palox_nach_leeren is
  'Die Ablesung der leeren Box direkt nach dem Leeren: keine Menge, sondern '
  'der neue Nullpunkt für die nächste Differenz (0084). palox_geleert '
  'daneben bleibt das Alte: ein gefallener Stand ohne diese Ablesung, also '
  'eine unbekannte Menge.';

-- aus 0085_die_rueckmeldung_am_ende_jeder_arbeit.sql

create table if not exists auftrag_rueckmeldung (
  id             bigserial primary key,
  auftrag_id     bigint not null references auftrag(id) on delete cascade,
  text           text,
  audio_ref      text,
  audio_typ      text,
  audio_sekunden int check (audio_sekunden is null or audio_sekunden >= 0),
  erfasser       uuid not null default auth.uid() references profil(id),
  ts             timestamptz not null default now(),

  constraint auftrag_rueckmeldung_nicht_leer
    check (nullif(btrim(coalesce(text, '')), '') is not null or audio_ref is not null)
);
comment on table auftrag_rueckmeldung is
  'Was die Person, die eine Arbeit abgeschlossen hat, dazu zu sagen hatte: '
  'geschrieben, gesprochen (Datei im Bucket rueckmeldungen) oder beides. Wird '
  'nicht ausgewertet — gelesen und angehört (0085).';
comment on column auftrag_rueckmeldung.audio_ref is
  'Pfad der Aufnahme im Bucket rueckmeldungen: <auftrag_id>/<zeit>.<endung>.';
comment on column auftrag_rueckmeldung.audio_sekunden is
  'Dauer der Aufnahme, wie die App sie beim Aufnehmen gemessen hat.';
create index if not exists auftrag_rueckmeldung_auftrag on auftrag_rueckmeldung (auftrag_id, ts desc);

alter table auftrag_rueckmeldung enable row level security;
drop policy if exists rueckmeldung_lesen    on auftrag_rueckmeldung;
drop policy if exists rueckmeldung_erfassen on auftrag_rueckmeldung;
drop policy if exists rueckmeldung_aendern  on auftrag_rueckmeldung;
drop policy if exists rueckmeldung_loeschen on auftrag_rueckmeldung;
create policy rueckmeldung_lesen on auftrag_rueckmeldung for select to authenticated using (true);
create policy rueckmeldung_erfassen on auftrag_rueckmeldung for insert to authenticated
  with check ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
create policy rueckmeldung_aendern on auftrag_rueckmeldung for update to authenticated using (ist_admin());
create policy rueckmeldung_loeschen on auftrag_rueckmeldung for delete to authenticated using (ist_admin());
grant select, insert, update, delete on auftrag_rueckmeldung to authenticated;
grant usage, select on sequence auftrag_rueckmeldung_id_seq to authenticated;

drop trigger if exists auftrag_rueckmeldung_journal on auftrag_rueckmeldung;
create trigger auftrag_rueckmeldung_journal after insert or update or delete on auftrag_rueckmeldung
  for each row execute function erfassung_journal_schreiben();

insert into storage.buckets (id, name, public)
values ('rueckmeldungen', 'rueckmeldungen', false)
on conflict (id) do nothing;

drop policy if exists rueckmeldungen_lesen     on storage.objects;
drop policy if exists rueckmeldungen_schreiben on storage.objects;

create policy rueckmeldungen_lesen on storage.objects for select to authenticated
  using (bucket_id = 'rueckmeldungen');
create policy rueckmeldungen_schreiben on storage.objects for insert to authenticated
  with check (bucket_id = 'rueckmeldungen' and (ist_aktiv() or ist_admin()));

-- aus 0088_der_ausschuss_wird_kiste_fuer_kiste_gewogen.sql

alter table ausschuss_messung alter column mit_palette set default false;
comment on column ausschuss_messung.mit_palette is
  'Stand der Ausschuss beim Wiegen auf einer Palette? Seit 0088 ist die Antwort '
  'im Betrieb immer Nein — Ausschuss wird Kiste für Kiste gewogen; der Standard '
  'ist darum false. Alte Zeilen (vor 0083 immer mit Palette gerechnet) tragen '
  'noch true, wo es nicht eindeutig zu deuten war.';
comment on column ausschuss_messung.bemerkung is
  'Freier Text. Seit 0088 stehen hier bei einer Wägung Kiste für Kiste die '
  'einzelnen Bruttogewichte („3 Kisten einzeln gewogen: 12 · 13.5 · 11 kg") — '
  'die Zeile selbst trägt die Summe.';

-- aus 0089_eine_verdunstung_die_keine_ist.sql

insert into einstellung (schluessel, wert, bemerkung) values
  ('verdunstung_rate_max_pro_tag', '0.01'::jsonb,
   'Höchste Verdunstung je Tag, die noch eine sein kann — als Anteil (0.01 = 1 % je Tag). '
   'Eine Wägung darüber ist keine Verdunstung, sondern ein falsches Zettelgewicht, eine andere '
   'Palette oder falsche Kisten: Sie zählt nicht in die Rate und steht unter Auffälligkeiten (0089).')
on conflict (schluessel) do nothing;

create or replace function verdunstung_rate_max() returns numeric
language sql stable as $$
  select coalesce((select (wert #>> '{}')::numeric from public.einstellung
                    where schluessel = 'verdunstung_rate_max_pro_tag'), 0.01);
$$;
comment on function verdunstung_rate_max() is
  'Die Grenze aus der Einstellung verdunstung_rate_max_pro_tag (Vorgabe 0.01 = 1 % je Tag, 0089).';

revoke execute on function verdunstung_rate_max() from public;
grant execute on function verdunstung_rate_max() to authenticated;

-- aus 0091_die_rueckmeldung_hat_zwei_arten_und_ein_transkript.sql

alter table auftrag_rueckmeldung
  add column if not exists art text not null default 'app'
    constraint auftrag_rueckmeldung_art check (art in ('app', 'ware')),
  add column if not exists transkript text,
  add column if not exists transkript_quelle text
    constraint auftrag_rueckmeldung_transkript_quelle check (transkript_quelle is null or transkript_quelle in ('handy', 'hand'));
comment on column auftrag_rueckmeldung.art is
  'app: Feedback zur App (für die nächste Runde am Programm). ware: Kommentar zur '
  'Ware dieser Arbeit (für den Betriebsleiter, steht an den Messungen). 0091.';
comment on column auftrag_rueckmeldung.transkript is
  'Was das Handy beim Aufnehmen mitgeschrieben hat (Spracherkennung des Browsers, '
  'Hochdeutsch) — oder was der Mensch daraus gemacht hat. Der Text, den man liest, '
  'wenn man die Aufnahme nicht hören kann (0091).';
comment on column auftrag_rueckmeldung.transkript_quelle is
  'handy: automatisch mitgeschrieben, ungeprüft. hand: vom Menschen geprüft oder getippt.';

alter table auftrag_rueckmeldung drop constraint if exists auftrag_rueckmeldung_transkript_passt;
alter table auftrag_rueckmeldung add constraint auftrag_rueckmeldung_transkript_passt
  check ((transkript is null) = (transkript_quelle is null) and (transkript is null or audio_ref is not null));
create index if not exists auftrag_rueckmeldung_art on auftrag_rueckmeldung (art, ts desc);

-- aus 0094_der_kommentar_wird_gelesen_bevor_er_im_dashboard_steht.sql

alter table auftrag_rueckmeldung
  add column if not exists kurz text,
  add column if not exists kurz_quelle text
    constraint auftrag_rueckmeldung_kurz_quelle check (kurz_quelle is null or kurz_quelle in ('runde', 'betriebsleiter')),
  add column if not exists kurz_ts timestamptz,
  add column if not exists kurz_charge_nr int references charge(nr);
comment on column auftrag_rueckmeldung.kurz is
  'Die Kurzfassung des Kommentars zur Ware, wie das Dashboard sie zeigt („Hagelschaden"). '
  'Leer = noch nicht gelesen; dann steht die Rückmeldung nirgends im Dashboard (0094).';
comment on column auftrag_rueckmeldung.kurz_quelle is
  'runde: die Runde am Programm hat gekürzt (docs/betrieb/kurzfassungen.json, vom Betriebsabzug '
  'eingespielt). betriebsleiter: der Betriebsleiter selbst, unter Betrieb → Arbeiten. Die des '
  'Betriebsleiters überschreibt der Abzug nie.';
comment on column auftrag_rueckmeldung.kurz_ts is 'Wann gekürzt wurde.';
comment on column auftrag_rueckmeldung.kurz_charge_nr is
  'Gehört der Kommentar zu einer anderen Charge als die Arbeit, steht sie hier; sonst leer und '
  'die Charge der Arbeit gilt (0094).';

alter table auftrag_rueckmeldung drop constraint if exists auftrag_rueckmeldung_kurz_passt;
alter table auftrag_rueckmeldung add constraint auftrag_rueckmeldung_kurz_passt
  check ((kurz is null) = (kurz_quelle is null)
     and (kurz is null) = (kurz_ts is null)
     and (kurz is null or nullif(btrim(kurz), '') is not null)
     and (kurz is null or art = 'ware')
     and (kurz_charge_nr is null or kurz is not null));

-- aus 0095_die_zahlen_liegen_fertig_da.sql

alter table auswertung_stand add column if not exists rechnet_seit timestamptz;
comment on column auswertung_stand.rechnet_seit is
  'Seit wann gerade gerechnet wird (Schritt 1 setzt, Schritt 5 löscht). Die App zeigt '
  'dann „wird gerade erneuert" und lädt nach, sobald berechnet_ts weiterrückt (0095).';

create or replace function auswertung_schluessel()
returns table (sicht text, ausdruck text) language sql immutable set search_path = public as $$
  values
    ('erg_ausgang',            'id'),
    ('erg_ausschuss',          'weg, charge_nr, auftrag_id'),
    ('erg_bilanz',             'heute'),
    ('erg_charge',             'charge_nr'),
    ('erg_datenlage',          'charge_nr'),
    ('erg_datenqualitaet',     'paletten_gezaehlt'),
    ('erg_durchsatz',          'auftrag_id'),
    ('erg_fax',                'auftrag_id'),
    ('erg_fax_wartezeit',      'gruppe, sorte, klasse'),
    ('erg_gebinde',            'sorte, kaliber_idx'),
    ('erg_gewichte',           'charge_nr, stufe_g'),
    ('erg_kaliber',            'charge_nr, klasse, kaliber_idx'),
    ('erg_koeff_ausschuss',    'sorte'),
    ('erg_koeff_fax',          'sorte'),
    ('erg_koeff_nebenkanal',   'sorte'),
    ('erg_koeff_ueberfuellung','n'),
    ('erg_koeff_verdunstung',  'sorte'),
    ('erg_kohorte',            'charge_nr, eingangsdatum'),
    ('erg_kurve',              'altersklasse'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_modell',             'n'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_plausibilitaet',     'art, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage'),
    ('erg_selektion',          'n_verarbeitung'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte'),
    ('mv_schimmel_modell',     'n'),
    ('mv_schimmel_punkte',     'charge_nr, auftrag_id, quelle, lagertage')
$$;
comment on function auswertung_schluessel() is
  'Je gespeicherter Ansicht die Spalten, unter denen ihre Zeilen eindeutig sind — der '
  'Schlüssel des Index, mit dem der Zeitplan sie nebenläufig erneuert (0095). Jede '
  'erg_-Ansicht steht hier; der Prüfblock verlangt es.';
revoke execute on function auswertung_schluessel() from public;
grant execute on function auswertung_schluessel() to authenticated;

do $$
begin
  execute 'alter role postgres set statement_timeout = ''15min''';
  raise notice 'Zeitgrenze der Rolle postgres: 15 Minuten (für den Zeitplan).';
exception when others then
  raise notice 'Zeitgrenze der Rolle nicht gesetzt (%): der Zeitplan läuft mit der Vorgabe der Datenbank.', sqlerrm;
end $$;

create or replace function auswertung_schluessel()
returns table (sicht text, ausdruck text) language sql immutable set search_path = public as $$
  values
    ('erg_ausgang',            'id'),
    ('erg_ausschuss',          'weg, charge_nr, auftrag_id'),
    ('erg_bilanz',             'heute'),
    ('erg_charge',             'charge_nr'),
    ('erg_datenlage',          'charge_nr'),
    ('erg_datenqualitaet',     'paletten_gezaehlt'),
    ('erg_durchsatz',          'auftrag_id'),
    ('erg_fax',                'auftrag_id'),
    ('erg_fax_wartezeit',      'gruppe, sorte, klasse'),
    ('erg_gebinde',            'sorte, kaliber_idx'),
    ('erg_gewichte',           'charge_nr, stufe_g'),
    ('erg_kaliber',            'charge_nr, klasse, kaliber_idx'),
    ('erg_koeff_ausschuss',    'sorte'),
    ('erg_koeff_fax',          'sorte'),
    ('erg_koeff_nebenkanal',   'sorte'),
    ('erg_koeff_ueberfuellung','n'),
    ('erg_koeff_verdunstung',  'sorte'),
    ('erg_kohorte',            'charge_nr, eingangsdatum'),
    ('erg_kurve',              'altersklasse'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_modell',             'n'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_plausibilitaet',     'art, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage'),
    ('erg_selektion',          'n_verarbeitung'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte'),
    ('mv_schimmel_modell',     'n'),
    ('mv_schimmel_punkte',     'charge_nr, auftrag_id, quelle, lagertage')
$$;

revoke execute on function auswertung_schluessel() from public;
grant execute on function auswertung_schluessel() to authenticated;

alter table profil add column if not exists darf_abbrechen boolean not null default false;
comment on column profil.darf_abbrechen is
  'Darf laufende Arbeiten abbrechen, auch fremde (0097). Setzt der Betriebsleiter unter Benutzer.';

create or replace function public.darf_abbrechen()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profil where id = auth.uid() and darf_abbrechen and aktiv);
$$;
revoke execute on function public.darf_abbrechen() from public;
grant execute on function public.darf_abbrechen() to authenticated;

create or replace function auftrag_abbrechen(p_auftrag_id bigint, p_grund text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_status auftrag_status;
begin
  if not (ist_admin() or ist_beteiligt(p_auftrag_id) or darf_abbrechen()) then
    raise exception 'Abbrechen darf, wer an der Arbeit beteiligt ist, der Betriebsleiter — oder wer die Erlaubnis dazu hat.'
      using errcode = '42501';
  end if;
  select status into v_status from auftrag where id = p_auftrag_id;
  if not ist_admin() and v_status is distinct from 'offen' then
    raise exception 'Nur eine laufende Arbeit lässt sich abbrechen.' using errcode = '42501';
  end if;

  update auftrag
     set abgebrochen_ts = now(),
         abbruch_grund  = p_grund,
         status         = 'abgeschlossen',
         -- greatest, nicht einfach now(): Die Prüfregel verlangt ende_ts >= start_ts.
         -- Ein Abbruch darf nie an einer Zeitverschiebung scheitern.
         ende_ts        = greatest(coalesce(ende_ts, now()), start_ts)
   where id = p_auftrag_id and abgebrochen_ts is null;

  update sortier_lauf
     set auftrag_id = null, zuordnung = 'offen'
   where auftrag_id = p_auftrag_id;
end $$;
comment on function auftrag_abbrechen is
  'Verwirft eine Arbeit. Die Erfassungen bleiben als Spur stehen, zählen aber '
  'nirgends mehr mit; zugeordnete Sortier-CSVs gehen zurück in die Warteschlange. '
  'Seit 0097 mit eigener Prüfung: Beteiligte, Betriebsleiter, oder wer die Erlaubnis hat (profil.darf_abbrechen).';
revoke execute on function auftrag_abbrechen(bigint, text) from public;
grant execute on function auftrag_abbrechen(bigint, text) to authenticated;

-- aus 0098_der_zeitplan_notiert_sich_selbst.sql

alter table auswertung_stand add column if not exists zeitplan_gerufen_ts timestamptz;
comment on column auswertung_stand.zeitplan_gerufen_ts is
  'Wann der Zeitplan (auswertung_wenn_veraltet) zuletzt gerufen wurde — auch ohne Rechnung. '
  'Eigene Notiz der Datenbank, weil pg_cron nicht überall eine Laufgeschichte schreibt (0098).';

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

-- aus 0100_gerechnet_wird_nur_an_einer_stelle.sql

create or replace function auswertung_schritt_intern(p_schritt integer, p_nebenlaeufig boolean)
returns jsonb language plpgsql security definer set search_path = public set jit = off as $$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
  v_ausdruck text;
  v_eindeutig boolean;
  v_gefuellt boolean;
  v_seit timestamptz;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- 0100: Gerechnet wird nur an einer Stelle. Schritt 1 besetzt den Platz
  -- (rechnet_seit), und wer ihn besetzt findet — jünger als die Zeitgrenze —,
  -- rechnet nicht mit, sondern bekommt „wartet" zurück. Am 28. September
  -- rechneten mehrere Fenster und der Zeitplan gleichzeitig, jede Rechnung
  -- gut zwei Minuten, und die Datenbank antwortete eine halbe Stunde niemandem.
  -- Ein Rest, der älter als 15 Minuten ist (0095: länger rechnet kein Lauf),
  -- ist ein abgebrochener Lauf und wird übernommen.
  if p_schritt = 1 then
    update auswertung_stand
       set rechnet_seit = clock_timestamp()
     where id = 1 and (rechnet_seit is null or rechnet_seit < clock_timestamp() - interval '15 minutes')
    returning rechnet_seit into v_seit;
    if v_seit is null then
      select rechnet_seit into v_seit from auswertung_stand where id = 1;
      return jsonb_build_object('schritt', 1, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                                'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true, 'rechnet_seit', v_seit);
    end if;
  end if;
  -- Und je Schritt eine Sperre für die Dauer des Aufrufs: zwei Erneuerungen
  -- derselben Ansicht zur selben Sekunde gibt es nicht — wer sie trifft, wartet.
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return jsonb_build_object('schritt', p_schritt, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                              'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true,
                              'rechnet_seit', (select rechnet_seit from auswertung_stand where id = 1));
  end if;
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'mv_schimmel_punkte', 'mv_schimmel_modell',
                       'erg_punkte', 'erg_modell', 'erg_kurve', 'erg_selektion',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_fax', 'erg_koeff_ueberfuellung', 'mv_koeff_rand',
                       'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_fax_wartezeit', 'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_prognose', 'erg_wohin', 'erg_verlauf', 'erg_bilanz',
                       'erg_marge', 'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage',
                       'erg_marge_wiegung', 'erg_marge_charge'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  if p_schritt = 1 then
    for v_name in
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
  end if;

  foreach v_name in array v_namen loop
    v_eindeutig := false;
    if p_nebenlaeufig then
      -- Nebenläufig geht nur mit eindeutigem Index und nur, wenn die Ansicht
      -- schon einmal gefüllt wurde. Den Index legt der Lauf bei Bedarf an;
      -- gelingt das nicht (eine doppelte Zeile), bleibt es beim normalen Weg.
      select s.ausdruck into v_ausdruck from auswertung_schluessel() s where s.sicht = v_name;
      select c.relispopulated into v_gefuellt from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_name;
      if v_ausdruck is not null and coalesce(v_gefuellt, false) then
        begin
          -- Ein Index aus Spalten muss es sein: Die Ausdrucksindizes älterer
          -- Migrationen (coalesce …) zählen für Postgres hier nicht.
          if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indrelid
                          where c.relname = v_name and i.indisunique and i.indexprs is null and i.indpred is null) then
            execute format('create unique index %I on %I (%s) nulls not distinct', v_name || '_eindeutig', v_name, v_ausdruck);
          end if;
          v_eindeutig := true;
        exception when others then
          raise notice 'auswertung_schritt: % bekommt keinen eindeutigen Index (%) — wird normal erneuert', v_name, sqlerrm;
        end;
      end if;
    end if;
    if v_eindeutig then
      begin
        execute format('refresh materialized view concurrently %I', v_name);
      exception when others then
        raise notice 'auswertung_schritt: % nicht nebenläufig erneuert (%) — normal erneuert', v_name, sqlerrm;
        execute format('refresh materialized view %I', v_name);
      end;
    else
      execute format('refresh materialized view %I', v_name);
    end if;
    execute format('analyze %I', v_name);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),
           rechnet_seit = null,
           dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif p_schritt = 1 then
    update auswertung_stand
       set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  else
    update auswertung_stand
       set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5, 'nebenlaeufig', p_nebenlaeufig, 'wartet', false);
end $$;
revoke execute on function auswertung_schritt_intern(integer, boolean) from public;
grant execute on function auswertung_schritt_intern(integer, boolean) to authenticated;

create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand; i int; v_erg jsonb;
begin
  update auswertung_stand set zeitplan_gerufen_ts = now() where id = 1;
  select * into v_stand from auswertung_stand where id = 1;
  if v_stand.berechnet_ts is not null and v_stand.geaendert_ts <= v_stand.berechnet_ts then
    return false;
  end if;
  -- 0100: rechnet schon jemand, tut der Zeitplan nichts — der nächste Takt sieht nach.
  v_erg := auswertung_schritt_intern(1, true);
  if (v_erg ->> 'wartet') = 'true' then
    return false;
  end if;
  for i in 2..5 loop
    perform auswertung_schritt_intern(i, true);
  end loop;
  return true;
end $$;
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

-- aus 0102_gerechnet_wird_auf_anforderung.sql

alter table auswertung_stand add column if not exists angefordert_ts timestamptz;
comment on column auswertung_stand.angefordert_ts is
  'Wann zuletzt „Neu rechnen" angefordert wurde (auswertung_anfordern, 0102). Steht die Anforderung '
  'jünger als berechnet_ts, ist sie erledigt.';

create or replace function auswertung_zeitplan()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v jsonb;
  v_st auswertung_stand;
  v_j jsonb;
  v_sofort boolean := false;
begin
  select * into v_st from auswertung_stand where id = 1;
  v := jsonb_build_object('aktiv', false,
                          'rechnet_seit', v_st.rechnet_seit,
                          'berechnet_ts', v_st.berechnet_ts,
                          'geaendert_ts', v_st.geaendert_ts,
                          'gerufen_ts', v_st.zeitplan_gerufen_ts,
                          'angefordert_ts', v_st.angefordert_ts);
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      execute $q$
        select jsonb_build_object('aktiv', j.active, 'takt', j.schedule,
                                  'letzter_start', d.start_time, 'letzter_status', d.status,
                                  'letzte_dauer_s', round(extract(epoch from d.end_time - d.start_time)::numeric, 1),
                                  'letzte_meldung', left(d.return_message, 200),
                                  'quelle', case when d.start_time is null then null else 'pg_cron' end)
          from cron.job j
          left join lateral (select r.* from cron.job_run_details r
                              where r.jobid = j.jobid order by r.start_time desc limit 1) d on true
         where j.jobname = 'auswertung_wenn_veraltet'
      $q$ into v_j;
      if v_j is not null then v := v || v_j; end if;
      execute $q$select exists (select 1 from cron.job where jobname = 'auswertung_sofort')$q$ into v_sofort;
    exception when others then
      v := v || jsonb_build_object('fehler', sqlerrm);
    end;
  end if;
  -- 0098: Schweigt pg_cron, gilt die eigene Notiz.
  if (v ->> 'letzter_start') is null and v_st.zeitplan_gerufen_ts is not null then
    v := v || jsonb_build_object(
      'letzter_start', v_st.zeitplan_gerufen_ts,
      'letzter_status', case when v_st.rechnet_seit is not null and v_st.rechnet_seit >= v_st.zeitplan_gerufen_ts - interval '1 minute'
                               then 'running' else 'succeeded' end,
      'quelle', 'eigene_notiz');
  end if;
  -- 0102: Ist der Sofort-Lauf eingetragen (eine Anforderung in Arbeit)?
  v := v || jsonb_build_object('sofort', v_sofort);
  return v;
end $$;
revoke execute on function auswertung_zeitplan() from public;
grant execute on function auswertung_zeitplan() to authenticated;
revoke execute on function auswertung_zeitplan() from public;
grant execute on function auswertung_zeitplan() to authenticated;
comment on function auswertung_zeitplan() is
  'Läuft der Zeitplan (pg_cron-Job auswertung_wenn_veraltet)? Mit Takt, letztem Lauf, Status, Dauer, '
  'ob gerade gerechnet wird (rechnet_seit), seit 0098 auch aus der eigenen Notiz der Datenbank '
  '(quelle), seit 0102 mit angefordert_ts und sofort (Sofort-Lauf eingetragen).';
revoke execute on function auswertung_zeitplan() from public;
grant execute on function auswertung_zeitplan() to authenticated;

-- aus 0103_ein_zeitplan_eine_sperre.sql

create table if not exists auswertung_laufzeit (
  id           bigint generated always as identity primary key,
  ts           timestamptz not null default clock_timestamp(),
  schritt      int not null,
  sicht        text not null,
  nebenlaeufig boolean not null,
  dauer_ms     int not null
);
comment on table auswertung_laufzeit is
  'Je Erneuerung einer gespeicherten Ansicht ihre Dauer (0103), sieben Tage lang. '
  'auswertung_diagnose() nennt die langsamsten des letzten Laufs.';
alter table auswertung_laufzeit enable row level security;
drop policy if exists laufzeit_lesen on auswertung_laufzeit;
create policy laufzeit_lesen on auswertung_laufzeit for select to authenticated using (ist_admin());
grant select on auswertung_laufzeit to authenticated;

create or replace function auswertung_schritt_intern(p_schritt integer, p_nebenlaeufig boolean)
returns jsonb language plpgsql security definer set search_path = public set jit = off as $$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
  v_ausdruck text;
  v_eindeutig boolean;
  v_gefuellt boolean;
  v_seit timestamptz;
  v_t timestamptz;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- Je Aufruf eine Beratungssperre (0100): zwei Erneuerungen derselben
  -- Ansicht zur selben Sekunde gibt es nicht. Im Zeitplan-Weg hält der
  -- ganze Lauf sie (eine Transaktion); ein Schritt aus der App, der sie
  -- nicht bekommt, geht sofort mit „wartet".
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return jsonb_build_object('schritt', p_schritt, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                              'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true,
                              'rechnet_seit', (select rechnet_seit from auswertung_stand where id = 1));
  end if;
  -- Der App-Weg (fünf einzelne Aufrufe, je eine Transaktion) merkt sich in
  -- rechnet_seit, dass er läuft (0100). Der Zeitplan-Weg tut das nicht: Ein
  -- Update hier hielte die Zeile bis zum Ende des Laufs gesperrt, und jedes
  -- „Neu rechnen" bliebe daran hängen (0103).
  if p_schritt = 1 and not p_nebenlaeufig then
    update auswertung_stand
       set rechnet_seit = clock_timestamp()
     where id = 1 and (rechnet_seit is null or rechnet_seit < clock_timestamp() - interval '15 minutes')
    returning rechnet_seit into v_seit;
    if v_seit is null then
      select rechnet_seit into v_seit from auswertung_stand where id = 1;
      return jsonb_build_object('schritt', 1, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                                'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true, 'rechnet_seit', v_seit);
    end if;
  end if;
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'mv_schimmel_punkte', 'mv_schimmel_modell',
                       'erg_punkte', 'erg_modell', 'erg_kurve', 'erg_selektion',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_fax', 'erg_koeff_ueberfuellung', 'mv_koeff_rand',
                       'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_fax_wartezeit', 'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_prognose', 'erg_wohin', 'erg_verlauf', 'erg_bilanz',
                       'erg_marge', 'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage',
                       'erg_marge_wiegung', 'erg_marge_charge'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  if p_schritt = 1 then
    for v_name in
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
    delete from auswertung_laufzeit where ts < clock_timestamp() - interval '7 days';
  end if;

  foreach v_name in array v_namen loop
    v_t := clock_timestamp();
    v_eindeutig := false;
    if p_nebenlaeufig then
      select s.ausdruck into v_ausdruck from auswertung_schluessel() s where s.sicht = v_name;
      select c.relispopulated into v_gefuellt from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_name;
      if v_ausdruck is not null and coalesce(v_gefuellt, false) then
        begin
          if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indrelid
                          where c.relname = v_name and i.indisunique and i.indexprs is null and i.indpred is null) then
            execute format('create unique index %I on %I (%s) nulls not distinct', v_name || '_eindeutig', v_name, v_ausdruck);
          end if;
          v_eindeutig := true;
        exception when others then
          raise notice 'auswertung_schritt: % bekommt keinen eindeutigen Index (%) — wird normal erneuert', v_name, sqlerrm;
        end;
      end if;
    end if;
    if v_eindeutig then
      begin
        execute format('refresh materialized view concurrently %I', v_name);
      exception when others then
        raise notice 'auswertung_schritt: % nicht nebenläufig erneuert (%) — normal erneuert', v_name, sqlerrm;
        execute format('refresh materialized view %I', v_name);
      end;
    else
      execute format('refresh materialized view %I', v_name);
    end if;
    execute format('analyze %I', v_name);
    -- 0103: Wo die Minuten hingehen, sagt jeder Lauf selbst.
    insert into auswertung_laufzeit (schritt, sicht, nebenlaeufig, dauer_ms)
    values (p_schritt, v_name, v_eindeutig, (extract(epoch from clock_timestamp() - v_t) * 1000)::int);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),
           rechnet_seit = null,
           dauer_ms = case when p_nebenlaeufig then null else coalesce(dauer_ms, 0) end
                      + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif not p_nebenlaeufig then
    if p_schritt = 1 then
      update auswertung_stand
         set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
       where id = 1;
    else
      update auswertung_stand
         set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
       where id = 1;
    end if;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5, 'nebenlaeufig', p_nebenlaeufig, 'wartet', false);
end $$;
revoke execute on function auswertung_schritt_intern(integer, boolean) from public;
grant execute on function auswertung_schritt_intern(integer, boolean) to authenticated;

create or replace function auswertung_drossel_min() returns int
language sql immutable set search_path = public as $$ select 10 $$;

create or replace function auswertung_drossel(p_dauer_ms int) returns interval
language sql immutable set search_path = public as $$
  select greatest(make_interval(mins => auswertung_drossel_min()),
                  3 * make_interval(secs => (coalesce(p_dauer_ms, 0) / 1000.0)::double precision))
$$;
comment on function auswertung_drossel(int) is
  'Wie lange nach einem Lauf die Halle keinen neuen auslöst (0103): zehn Minuten, mindestens aber '
  'das Dreifache seiner Dauer. Eine Anforderung („Neu rechnen") wartet nicht.';

revoke all on function auswertung_drossel_min() from public;
grant execute on function auswertung_drossel_min() to authenticated;
revoke all on function auswertung_drossel(int) from public;
grant execute on function auswertung_drossel(int) to authenticated;

create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand; i int; v_erg jsonb; v_dauer timestamptz := clock_timestamp(); r record; v_n int := 0;
begin
  -- 1. Die Sperre — vor allem anderen. Wer sie nicht bekommt, geht sofort:
  --    keine Zeile angefasst, kein Arbeiter besetzt, kein Konvoi.
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return false;
  end if;
  select * into v_stand from auswertung_stand where id = 1;
  -- 2. Nichts veraltet, oder veraltet, aber weder angefordert noch älter als
  --    die Drossel: nur den Aufruf notieren (0098) und gehen.
  if v_stand.berechnet_ts is not null and v_stand.geaendert_ts <= v_stand.berechnet_ts then
    update auswertung_stand set zeitplan_gerufen_ts = now() where id = 1;
    return false;
  end if;
  if v_stand.berechnet_ts is not null
     and not (v_stand.angefordert_ts is not null and v_stand.angefordert_ts > v_stand.berechnet_ts)
     and v_stand.berechnet_ts > clock_timestamp() - auswertung_drossel(v_stand.dauer_ms) then
    update auswertung_stand set zeitplan_gerufen_ts = now() where id = 1;
    return false;
  end if;
  -- 3. Fremde Reste beenden: eine Sitzung, die noch an einer Rechnung hängt
  --    (ein Konvoi von vor 0103, ein Schritt aus der App), hält Sperren, auf
  --    die dieser Lauf sonst wartete. Eine Erneuerung ist eine Transaktion —
  --    beendet heisst zurückgerollt, nichts geht verloren. Gemeint sind nur
  --    Rechnungen: nicht das Lesen des Standes durch die App (Millisekunden,
  --    aber „auswertung_stand" im Text) und nie setup.sql (Zeile 2 nennt
  --    sich, und ihre Einspielung hält die Sperre ohnehin selbst).
  begin
    for r in select pid from pg_stat_activity
              where datname = current_database() and pid <> pg_backend_pid()
                and state <> 'idle'
                and (query ~* 'auswertung_(schritt|wenn_veraltet|aktualisieren|sofort_lauf)'
                     or query ilike '%refresh materialized view%')
                and query not ilike '%setup.sql%'
    loop
      begin
        if pg_terminate_backend(r.pid) then v_n := v_n + 1; end if;
      exception when others then
        raise notice 'auswertung_wenn_veraltet: Sitzung % nicht beendet (%)', r.pid, sqlerrm;
      end;
    end loop;
    if v_n > 0 then raise notice 'auswertung_wenn_veraltet: % fremde Rechnung(en) beendet', v_n; end if;
  exception when others then
    raise notice 'auswertung_wenn_veraltet: fremde Rechnungen nicht prüfbar (%)', sqlerrm;
  end;
  -- 4. Auf keine Sperre länger als 30 Sekunden warten: Ein Lauf, der wartet,
  --    soll abbrechen und in einer Minute wiederkommen — nicht 15 Minuten
  --    lang alles festhalten, was er schon hat.
  perform set_config('lock_timeout', '30s', true);
  -- 5. Rechnen. Die Buchhaltung (berechnet_ts, dauer_ms, gerufen_ts) macht
  --    Schritt 5 am Ende, in einem Update — bis dahin bleibt die Zeile frei.
  for i in 1..5 loop
    v_erg := auswertung_schritt_intern(i, true);
    if (v_erg ->> 'wartet') = 'true' then
      return false;
    end if;
  end loop;
  update auswertung_stand
     set zeitplan_gerufen_ts = now(),
         dauer_ms = (extract(epoch from clock_timestamp() - v_dauer) * 1000)::int
   where id = 1;
  return true;
end $$;
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

create or replace function auswertung_sofort_lauf() returns text
language plpgsql security definer set search_path = public set jit = off as $$
declare v_erg boolean;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'auswertung_sofort'$q$;
  end if;
  v_erg := auswertung_wenn_veraltet();
  return case when v_erg then 'gerechnet' else 'nichts zu tun' end;
end $$;
revoke all on function auswertung_sofort_lauf() from public;
grant execute on function auswertung_sofort_lauf() to authenticated;
comment on function auswertung_sofort_lauf() is
  'Seit 0103 ohne eigenen Eintrag: ruft den Lauf des Zeitplans und trägt einen Rest von „auswertung_sofort" aus.';

do $$
declare v_id bigint; v_takt text;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'auswertung_sofort';
    select jobid, schedule into v_id, v_takt from cron.job where jobname = 'auswertung_wenn_veraltet' order by jobid limit 1;
    if v_id is not null and v_takt is distinct from '*/1 * * * *' then
      perform cron.alter_job(job_id => v_id, schedule => '*/1 * * * *',
                             command => 'select public.auswertung_wenn_veraltet()', active => true);
      raise notice 'Zeitplan: auswertung_wenn_veraltet() jede Minute (0103) — angepasst.';
    elsif v_id is null then
      perform cron.schedule('auswertung_wenn_veraltet', '*/1 * * * *', 'select public.auswertung_wenn_veraltet()');
      raise notice 'Zeitplan: auswertung_wenn_veraltet() jede Minute (0103) — neu angelegt.';
    end if;
  end if;
exception when others then
  raise notice 'Zeitplan nicht angepasst (%)', sqlerrm;
end $$;

do $$
begin
  execute 'alter role postgres set statement_timeout = ''60min''';
exception when others then
  raise notice 'Zeitgrenze der Rolle postgres nicht gesetzt (%)', sqlerrm;
end $$;

create or replace function auswertung_diagnose() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb; v_aktiv jsonb; v_laeufe jsonb; v_ansichten jsonb; v_grenzen jsonb;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Die Diagnose sieht nur der Betriebsleiter.' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'pid', pid, 'rolle', usename, 'programm', left(application_name, 40), 'zustand', state,
           'wartet_auf', case when wait_event_type is null then null else wait_event_type || ': ' || coalesce(wait_event, '') end,
           'seit_s', round(extract(epoch from clock_timestamp() - coalesce(query_start, backend_start))::numeric, 1),
           'abfrage', left(query, 120)) order by query_start), '[]'::jsonb)
    into v_aktiv
    from pg_stat_activity
   where datname = current_database() and pid <> pg_backend_pid() and state <> 'idle' and backend_type = 'client backend';
  v_laeufe := '[]'::jsonb;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      execute $q$
        select coalesce(jsonb_agg(jsonb_build_object(
                 'job', j.jobname, 'takt', j.schedule, 'aktiv', j.active, 'status', d.status,
                 'start', d.start_time, 'dauer_s', round(extract(epoch from d.end_time - d.start_time)::numeric, 1),
                 'meldung', left(d.return_message, 200)) order by d.start_time desc), '[]'::jsonb)
          from (select * from cron.job_run_details order by start_time desc limit 20) d
          join cron.job j using (jobid)
      $q$ into v_laeufe;
    exception when others then
      v_laeufe := jsonb_build_array(jsonb_build_object('fehler', sqlerrm));
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('name', c.relname, 'gefuellt', c.relispopulated,
                                               'zeilen', c.reltuples::bigint) order by c.relname), '[]'::jsonb)
    into v_ansichten
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'm';
  v_grenzen := jsonb_build_object(
    'statement_timeout_postgres', (select array_to_string(rolconfig, ',') from pg_roles where rolname = 'postgres'),
    'statement_timeout_authenticated', (select array_to_string(rolconfig, ',') from pg_roles where rolname = 'authenticated'),
    'max_worker_processes', current_setting('max_worker_processes', true),
    'max_connections', current_setting('max_connections', true),
    'cron_max_running_jobs', current_setting('cron.max_running_jobs', true));
  v := jsonb_build_object('jetzt', clock_timestamp(), 'aktiv', v_aktiv, 'laeufe', v_laeufe,
                          'langsamste', (select coalesce(jsonb_agg(jsonb_build_object('sicht', l.sicht, 'dauer_s', round(l.dauer_ms / 1000.0, 1),
                                                                                       'nebenlaeufig', l.nebenlaeufig, 'ts', l.ts)
                                                                    order by l.dauer_ms desc), '[]'::jsonb)
                                           from (select * from auswertung_laufzeit order by ts desc limit 60) l),
                          'ansichten_ungefuellt', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                                   where n.nspname = 'public' and c.relkind = 'm' and not c.relispopulated),
                          'ansichten', v_ansichten, 'grenzen', v_grenzen,
                          'stand', (select to_jsonb(s) from auswertung_stand s where id = 1));
  return v;
end $$;
comment on function auswertung_diagnose() is
  'Was die Datenbank gerade tut (0103): aktive Sitzungen, die letzten zwanzig Läufe des Zeitplans, '
  'die langsamsten Ansichten des letzten Laufs, welche gespeicherten Ansichten gefüllt sind, die '
  'Zeitgrenzen. Nur für den Betriebsleiter.';
revoke all on function auswertung_diagnose() from public;
grant execute on function auswertung_diagnose() to authenticated;

-- aus 0104_waschen_wird_gewogen.sql

alter table auftrag_palette add column if not exists brutto_gewogen_kg numeric;
do $$
begin
  alter table auftrag_palette add constraint auftrag_palette_brutto_gewogen_positiv
    check (brutto_gewogen_kg is null or brutto_gewogen_kg > 0);
exception when duplicate_object then null;
end $$;
comment on column auftrag_palette.brutto_gewogen_kg is
  'Waschen (0104): Brutto der Palette mit Kisten, gewogen am Anfang der Waschstrasse — Pflicht in der App. '
  'Netto = Brutto − Kisten × Kistentara − Palettentara (gebinde).';

create or replace function palox_trend_mindest_tage() returns int
language sql immutable set search_path = public as $$ select 28 $$;
revoke all on function palox_trend_mindest_tage() from public;
grant execute on function palox_trend_mindest_tage() to authenticated;

create or replace function palox_station_kennzahl(p_bis date, p_ab date default null)
returns table (
  station text, n_arbeiten int, n_chargen int, seit date, bis date, tage int,
  anteil_mittel numeric, anteil_median numeric, anteil_4w numeric, n_4w int,
  zuwachs_je_woche numeric, zuwachs_text text)
language plpgsql stable set search_path = public as $$
#variable_conflict use_column
begin
  return query
  with p as (
    select e.station, e.charge_nr, e.auftrag_id, e.messtag, e.basis_jetzt_kg as w, e.anteil_station as y
      from erg_punkte e
     where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
       and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
       and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
       and e.messtag <= p_bis and (p_ab is null or e.messtag >= p_ab)
  ), q as (
    -- t: Tage seit dem ersten Messtag dieser Station — die Achse der Geraden
    select p.*, (p.messtag - min(p.messtag) over (partition by p.station))::numeric as t from p
  ), je as (
    select station,
           count(*)::int as n_arbeiten, count(distinct charge_nr)::int as n_chargen,
           min(messtag) as seit, max(messtag) as bis, (max(messtag) - min(messtag))::int as tage,
           sum(w * y) / nullif(sum(w), 0) as anteil_mittel,
           percentile_cont(0.5) within group (order by y) as anteil_median,
           sum(w * y) filter (where messtag > p_bis - 28) / nullif(sum(w) filter (where messtag > p_bis - 28), 0) as anteil_4w,
           count(*) filter (where messtag > p_bis - 28)::int as n_4w,
           -- massegewichtete Gerade y = a + b · t: b in Anteil je Tag
           (sum(w * t * y) * sum(w) - sum(w * t) * sum(w * y))
           / nullif(sum(w * t * t) * sum(w) - power(sum(w * t), 2), 0) as b_je_tag
      from q
     group by station
  )
  select station, n_arbeiten, n_chargen, seit, bis, tage,
         zahl(anteil_mittel, 5, 1)::numeric(10,5), zahl(anteil_median, 5, 1)::numeric(10,5),
         zahl(anteil_4w, 5, 1)::numeric(10,5), n_4w,
         case when tage >= palox_trend_mindest_tage() and n_arbeiten >= 5
              then zahl(b_je_tag * 7, 5, 1)::numeric(10,5) end as zuwachs_je_woche,
         case when tage >= palox_trend_mindest_tage() and n_arbeiten >= 5 then null
              when n_arbeiten < 5 then format('Zuwachs erst ab fünf Arbeiten (%s bis jetzt)', n_arbeiten)
              else format('Zuwachs erst nach vier Wochen Messungen (seit %s, %s Tage)', to_char(seit, 'DD.MM.'), tage) end as zuwachs_text
    from je
   order by case je.station when 'waschen_sortieren' then 1 when 'waschen' then 2 else 3 end;
end $$;
revoke all on function palox_station_kennzahl(date, date) from public;
grant execute on function palox_station_kennzahl(date, date) to authenticated;

create or replace function palox_mindest_arbeiten() returns int
language sql immutable as $$ select 3 $$;
comment on function palox_mindest_arbeiten() is
  'Ab so vielen Arbeiten gilt der Palox-Anteil einer Sorte je Station (0106); darunter fällt die Kaskade auf die '
  'ganze Saison der Sorte zurück, dann auf alle Sorten.';
revoke all on function palox_mindest_arbeiten() from public;
grant execute on function palox_mindest_arbeiten() to authenticated;

create or replace function palox_f(p_hand numeric, p_wasch numeric, f_ws numeric, f_s numeric, g_w numeric)
returns numeric language sql immutable as $$
  select case
           when p_hand is null then null
           when p_hand > 0 and f_ws is null then null
           when p_hand < 1 and f_s is null then null
           when p_hand < 1 and coalesce(p_wasch, 0) > 0 and g_w is null then null
           else least(greatest(
                  p_hand * coalesce(f_ws, 0)
                  + (1 - p_hand) * (coalesce(f_s, 0)
                                    + (1 - coalesce(f_s, 0)) * coalesce(p_wasch, 0) * coalesce(g_w, 0)),
                0), 1)
         end
$$;
comment on function palox_f(numeric, numeric, numeric, numeric, numeric) is
  'Der Palox-Anteil einer Charge über ihren Weg (0106): p_hand · f_W+S + (1 − p_hand) · (f_S + (1 − f_S) · p_wasch · g_W). '
  'NULL, wenn eine Station auf dem Weg keinen Wert hat — leer ist nicht null.';
revoke all on function palox_f(numeric, numeric, numeric, numeric, numeric) from public;
grant execute on function palox_f(numeric, numeric, numeric, numeric, numeric) to authenticated;

create or replace function auswertung_schluessel()
returns table (sicht text, ausdruck text) language sql immutable set search_path = public as $$
  values
    ('erg_ausgang',            'id'),
    ('erg_ausschuss',          'weg, charge_nr, auftrag_id'),
    ('erg_bilanz',             'heute'),
    ('erg_charge',             'charge_nr'),
    ('erg_datenlage',          'charge_nr'),
    ('erg_datenqualitaet',     'paletten_gezaehlt'),
    ('erg_durchsatz',          'auftrag_id'),
    ('erg_fax',                'auftrag_id'),
    ('erg_fax_wartezeit',      'gruppe, sorte, klasse'),
    ('erg_gebinde',            'sorte, kaliber_idx'),
    ('erg_gewichte',           'charge_nr, stufe_g'),
    ('erg_kaliber',            'charge_nr, klasse, kaliber_idx'),
    ('erg_koeff_ausschuss',    'sorte'),
    ('erg_koeff_fax',          'sorte'),
    ('erg_koeff_nebenkanal',   'sorte'),
    ('erg_koeff_ueberfuellung','n'),
    ('erg_koeff_verdunstung',  'sorte'),
    ('erg_kohorte',            'charge_nr, eingangsdatum'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_plausibilitaet',     'art, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte')
$$;
revoke execute on function auswertung_schluessel() from public;
grant execute on function auswertung_schluessel() to authenticated;

-- aus 0107_gerechnet_wird_nachts_und_auf_knopfdruck.sql

alter table auswertung_stand add column if not exists fehler_ts timestamptz;
alter table auswertung_stand add column if not exists fehler text;
comment on column auswertung_stand.fehler_ts is
  'Wann der letzte Lauf gescheitert ist (0107). Bis zur nächsten Anforderung oder Nacht wird nicht wieder versucht.';
comment on column auswertung_stand.fehler is
  'Warum der letzte Lauf gescheitert ist (0107), gekürzt auf 500 Zeichen. Leer nach einem gelungenen Lauf.';

create or replace function auswertung_jetzt() returns timestamptz
language sql stable set search_path = public as $$
  select coalesce(nullif(current_setting('kuerbis.jetzt_test', true), '')::timestamptz, clock_timestamp())
$$;
comment on function auswertung_jetzt() is
  'Jetzt für den Zeitplan (0107); in der Prüfung über kuerbis.jetzt_test gestellt.';
revoke all on function auswertung_jetzt() from public;
grant execute on function auswertung_jetzt() to authenticated;

drop function if exists auswertung_drossel(int);
drop function if exists auswertung_drossel_min();

CREATE OR REPLACE FUNCTION public.auswertung_schritt_intern(p_schritt integer, p_nebenlaeufig boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
  v_ausdruck text;
  v_eindeutig boolean;
  v_gefuellt boolean;
  v_seit timestamptz;
  v_t timestamptz;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- Je Aufruf eine Beratungssperre (0100): zwei Erneuerungen derselben
  -- Ansicht zur selben Sekunde gibt es nicht. Im Zeitplan-Weg hält der
  -- ganze Lauf sie (eine Transaktion); ein Schritt aus der App, der sie
  -- nicht bekommt, geht sofort mit „wartet".
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return jsonb_build_object('schritt', p_schritt, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                              'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true,
                              'rechnet_seit', (select rechnet_seit from auswertung_stand where id = 1));
  end if;
  -- Der App-Weg (fünf einzelne Aufrufe, je eine Transaktion) merkt sich in
  -- rechnet_seit, dass er läuft (0100). Der Zeitplan-Weg tut das nicht: Ein
  -- Update hier hielte die Zeile bis zum Ende des Laufs gesperrt, und jedes
  -- „Neu rechnen" bliebe daran hängen (0103).
  if p_schritt = 1 and not p_nebenlaeufig then
    update auswertung_stand
       set rechnet_seit = clock_timestamp()
     where id = 1 and (rechnet_seit is null or rechnet_seit < clock_timestamp() - interval '15 minutes')
    returning rechnet_seit into v_seit;
    if v_seit is null then
      select rechnet_seit into v_seit from auswertung_stand where id = 1;
      return jsonb_build_object('schritt', 1, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                                'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true, 'rechnet_seit', v_seit);
    end if;
  end if;
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'erg_punkte',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_fax', 'erg_koeff_ueberfuellung', 'mv_koeff_rand',
                       'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_fax_wartezeit', 'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['erg_palox_erwartung', 'mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_prognose', 'erg_wohin', 'erg_verlauf', 'erg_bilanz',
                       'erg_marge', 'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage',
                       'erg_marge_wiegung', 'erg_marge_charge'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  if p_schritt = 1 then
    for v_name in
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
    delete from auswertung_laufzeit where ts < clock_timestamp() - interval '7 days';
  end if;

  foreach v_name in array v_namen loop
    v_t := clock_timestamp();
    v_eindeutig := false;
    if p_nebenlaeufig then
      select s.ausdruck into v_ausdruck from auswertung_schluessel() s where s.sicht = v_name;
      select c.relispopulated into v_gefuellt from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_name;
      if v_ausdruck is not null and coalesce(v_gefuellt, false) then
        begin
          if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indrelid
                          where c.relname = v_name and i.indisunique and i.indexprs is null and i.indpred is null) then
            execute format('create unique index %I on %I (%s) nulls not distinct', v_name || '_eindeutig', v_name, v_ausdruck);
          end if;
          v_eindeutig := true;
        exception when others then
          raise notice 'auswertung_schritt: % bekommt keinen eindeutigen Index (%) — wird normal erneuert', v_name, sqlerrm;
        end;
      end if;
    end if;
    if v_eindeutig then
      begin
        execute format('refresh materialized view concurrently %I', v_name);
      exception when others then
        raise notice 'auswertung_schritt: % nicht nebenläufig erneuert (%) — normal erneuert', v_name, sqlerrm;
        execute format('refresh materialized view %I', v_name);
      end;
    else
      execute format('refresh materialized view %I', v_name);
    end if;
    execute format('analyze %I', v_name);
    -- 0103: Wo die Minuten hingehen, sagt jeder Lauf selbst.
    insert into auswertung_laufzeit (schritt, sicht, nebenlaeufig, dauer_ms)
    values (p_schritt, v_name, v_eindeutig, (extract(epoch from clock_timestamp() - v_t) * 1000)::int);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),
           rechnet_seit = null,
           dauer_ms = case when p_nebenlaeufig then null else coalesce(dauer_ms, 0) end
                      + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif not p_nebenlaeufig then
    if p_schritt = 1 then
      update auswertung_stand
         set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
       where id = 1;
    else
      update auswertung_stand
         set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
       where id = 1;
    end if;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5, 'nebenlaeufig', p_nebenlaeufig, 'wartet', false);
end $function$;

create or replace function auswertung_schluessel()
returns table (sicht text, ausdruck text) language sql immutable set search_path = public as $$
  values
    ('erg_ausgang',            'id'),
    ('erg_ausschuss',          'weg, charge_nr, auftrag_id'),
    ('erg_bilanz',             'heute'),
    ('erg_charge',             'charge_nr'),
    ('erg_datenlage',          'charge_nr'),
    ('erg_datenqualitaet',     'paletten_gezaehlt'),
    ('erg_durchsatz',          'auftrag_id'),
    ('erg_fax',                'auftrag_id'),
    ('erg_fax_wartezeit',      'gruppe, sorte, klasse'),
    ('erg_gebinde',            'sorte, kaliber_idx'),
    ('erg_gewichte',           'charge_nr, stufe_g'),
    ('erg_kaliber',            'charge_nr, klasse, kaliber_idx'),
    ('erg_koeff_ausschuss',    'sorte'),
    ('erg_koeff_fax',          'sorte'),
    ('erg_koeff_nebenkanal',   'sorte'),
    ('erg_koeff_ueberfuellung','n'),
    ('erg_koeff_verdunstung',  'sorte'),
    ('erg_kohorte',            'charge_nr, eingangsdatum'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_palox_erwartung',    'sorte, station'),
    ('erg_plausibilitaet',     'art, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte')
$$;

do $$
declare v_id bigint; v_takt text;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'auswertung_sofort';
    select jobid, schedule into v_id, v_takt from cron.job where jobname = 'auswertung_wenn_veraltet' order by jobid limit 1;
    if v_id is null then
      perform cron.schedule('auswertung_wenn_veraltet', '*/1 * * * *', 'select public.auswertung_wenn_veraltet()');
      raise notice 'Zeitplan: jede Minute ein Blick, gerechnet nur nachts und auf „Neu rechnen" (0107) — neu angelegt.';
    else
      perform cron.alter_job(job_id => v_id, schedule => '*/1 * * * *',
                             command => 'select public.auswertung_wenn_veraltet()', active => true);
      raise notice 'Zeitplan: jede Minute ein Blick, gerechnet nur nachts und auf „Neu rechnen" (0107).';
    end if;
  end if;
exception when others then
  raise notice 'Zeitplan nicht angepasst (%)', sqlerrm;
end $$;

-- aus 0108_ein_abgebrochener_lauf_wird_nicht_wiederholt.sql

create sequence if not exists auswertung_versuch;
comment on sequence auswertung_versuch is
  'Je Lauf des Zeitplans eine Nummer, gezogen beim Anfang (0108). Eine Folge rollt nicht zurück: Eine Nummer über '
  'auswertung_stand.versuch_fertig heisst, ein Lauf hat angefangen und nie aufgehört.';
alter table auswertung_stand add column if not exists versuch_fertig bigint;
comment on column auswertung_stand.versuch_fertig is
  'Die Nummer (auswertung_versuch) des letzten Laufs, der zu Ende kam — gelungen oder mit gefangenem Fehler (0108).';

create or replace function auswertung_grund(p_jetzt timestamptz, p_berechnet timestamptz, p_geaendert timestamptz,
                                            p_angefordert timestamptz, p_fehler timestamptz)
returns text language sql stable set search_path = public as $$
  with z as (
    select (p_jetzt at time zone betriebszone())                                        as lokal,
           (date_trunc('day', p_jetzt at time zone betriebszone()) at time zone betriebszone()) as mitternacht
  )
  select case
    -- „Neu rechnen": jünger als der Stand und als der letzte Fehlschlag
    when p_angefordert is not null
         and p_angefordert > coalesce(p_berechnet, '-infinity')
         and p_angefordert > coalesce(p_fehler, '-infinity')                           then 'angefordert'
    -- frisch eingespielt: noch nie gerechnet, noch nie gescheitert
    when p_berechnet is null and p_fehler is null                                      then 'erstmals'
    -- nachts einmal: 2 bis 5 Uhr Ortszeit, tagsüber etwas erfasst, seit
    -- Mitternacht weder gerechnet noch gescheitert (Mitternacht gibt es in
    -- Europe/Zurich nie zweimal, zwei Uhr in der Umstellungsnacht schon)
    when extract(hour from z.lokal) >= 2 and extract(hour from z.lokal) < 5
         and p_geaendert > coalesce(p_berechnet, '-infinity')
         and coalesce(p_berechnet, '-infinity') < z.mitternacht
         and coalesce(p_fehler, '-infinity') < z.mitternacht                           then 'nachts'
  end
  from z
$$;
revoke all on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) from public;
grant execute on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) to authenticated;
comment on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) is
  'Warum jetzt gerechnet wird (0107, 0108) — ''angefordert'', ''erstmals'', ''nachts'' — oder null: dann nicht. '
  'Die eine Regel des Zeitplans; tagsüber löst die Halle nie eine Rechnung aus.';
revoke all on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) from public;
grant execute on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) to authenticated;

create or replace function auswertung_cron_da() returns boolean
language sql stable set search_path = public as $$
  select current_setting('kuerbis.zeitplan_test', true) = 'an'
      or exists (select 1 from pg_extension where extname = 'pg_cron')
$$;
comment on function auswertung_cron_da() is
  'Ob pg_cron installiert ist (0108) — dann rechnet nur der Zeitplan, nie der Browser. In der Prüfung: kuerbis.zeitplan_test = ''an''.';
revoke all on function auswertung_cron_da() from public;
grant execute on function auswertung_cron_da() to authenticated;

create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand; i int; v_erg jsonb; v_start timestamptz := clock_timestamp(); v_grund text;
  v_letzter bigint; v_versuch bigint;
begin
  -- Die Sperre vor allem anderen: nie zwei Läufe. Wer sie hält, lebt —
  -- darum wird ein Abbruch erst hinter der Sperre festgestellt.
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return false;
  end if;
  select * into v_stand from auswertung_stand where id = 1;
  -- Ein Lauf hat angefangen und ist nie fertig geworden: abgebrochen
  -- (Neustart, Absturz, beendet). Gemerkt wie ein Fehlschlag, nicht wiederholt.
  select case when is_called then last_value else 0 end into v_letzter from auswertung_versuch;
  if v_letzter > coalesce(v_stand.versuch_fertig, 0) then
    update auswertung_stand
       set fehler_ts = clock_timestamp(),
           fehler = 'Lauf abgebrochen (Neustart, Absturz oder beendet) — nicht wiederholt',
           versuch_fertig = v_letzter, zeitplan_gerufen_ts = now()
     where id = 1;
    raise warning 'Auswertung: der letzte Lauf wurde abgebrochen — nicht wiederholt';
    return false;
  end if;
  v_grund := auswertung_grund(auswertung_jetzt(), v_stand.berechnet_ts, v_stand.geaendert_ts,
                              v_stand.angefordert_ts, v_stand.fehler_ts);
  if v_grund is null then
    update auswertung_stand set zeitplan_gerufen_ts = now() where id = 1;   -- nur die Notiz (0098)
    -- Einmal je Stunde das Protokoll von pg_cron kürzen (eine Zeile je Minute).
    if extract(minute from clock_timestamp()) = 0 then
      begin
        execute $q$delete from cron.job_run_details where end_time < now() - interval '7 days'$q$;
      exception when others then
        null;
      end;
    end if;
    return false;
  end if;
  -- Ab hier zählt der Lauf: Die Nummer bleibt gezogen, was auch geschieht.
  v_versuch := nextval('auswertung_versuch');
  perform set_config('lock_timeout', '30s', true);
  begin
    for i in 1..5 loop
      v_erg := auswertung_schritt_intern(i, true);
      if (v_erg ->> 'wartet') = 'true' then
        raise exception 'Schritt % wartet auf eine Sperre', i;
      end if;
    end loop;
  exception when query_canceled or others then
    update auswertung_stand
       set fehler_ts = clock_timestamp(), fehler = left(sqlerrm, 500), zeitplan_gerufen_ts = now(),
           versuch_fertig = v_versuch
     where id = 1;
    raise warning 'Auswertung (%) nicht gerechnet: %', v_grund, sqlerrm;
    return false;
  end;
  -- Der Stand ist der Beginn des Laufs: Was währenddessen erfasst wurde,
  -- zählt als neu (nachts wird es nachgeholt, der Chip sagt es).
  update auswertung_stand
     set berechnet_ts = v_start, zeitplan_gerufen_ts = now(), fehler_ts = null, fehler = null,
         versuch_fertig = v_versuch,
         dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
   where id = 1;
  return true;
end $$;
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;
comment on function auswertung_wenn_veraltet() is
  'Der Lauf des Zeitplans (pg_cron, jede Minute): rechnet nur, wenn auswertung_grund() es sagt — „Neu rechnen", nachts '
  'einmal, oder noch nie gerechnet (0107). Jeder Lauf zieht beim Anfang eine Nummer (auswertung_versuch, 0108); ein '
  'Lauf, der nie fertig wurde, gilt als Fehlschlag und wird nicht wiederholt. Der Stand ist der Beginn des Laufs.';
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

create or replace function auswertung_anfordern() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ts timestamptz; v_id bigint; v_aktiv boolean; v_takt text;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  update auswertung_stand
     set geaendert_ts = clock_timestamp(), angefordert_ts = clock_timestamp()
   where id = 1
  returning angefordert_ts into v_ts;
  if current_setting('kuerbis.zeitplan_test', true) = 'an' then
    return jsonb_build_object('weg', 'zeitplan', 'takt', '*/1 * * * *', 'angefordert_ts', v_ts);
  end if;
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return jsonb_build_object('weg', 'app', 'angefordert_ts', v_ts);
  end if;
  begin
    execute $q$select jobid, active, schedule from cron.job where jobname = 'auswertung_wenn_veraltet' order by jobid limit 1$q$
       into v_id, v_aktiv, v_takt;
    if v_id is null then
      -- Fehlt der Eintrag ganz (ausgetragen), trägt „Neu rechnen" ihn ein.
      execute $q$select cron.schedule('auswertung_wenn_veraltet', '*/1 * * * *', 'select public.auswertung_wenn_veraltet()')$q$;
      v_takt := '*/1 * * * *';
    elsif not v_aktiv then
      -- Abgeschaltet (Notaus): bleibt abgeschaltet. Die Anforderung steht und
      -- wird gerechnet, sobald jemand den Zeitplan wieder einschaltet.
      return jsonb_build_object('weg', 'aus', 'angefordert_ts', v_ts,
        'hinweis', 'Der Zeitplan der Datenbank ist abgeschaltet (Notaus) — gerechnet wird, sobald er wieder eingeschaltet ist');
    end if;
  exception when others then
    return jsonb_build_object('weg', 'aus', 'angefordert_ts', v_ts, 'hinweis', 'Zeitplan nicht lesbar: ' || sqlerrm);
  end;
  return jsonb_build_object('weg', 'zeitplan', 'takt', coalesce(v_takt, '*/1 * * * *'), 'angefordert_ts', v_ts);
end $$;
revoke all on function auswertung_anfordern() from public;
grant execute on function auswertung_anfordern() to authenticated;
revoke all on function auswertung_anfordern() from public;
grant execute on function auswertung_anfordern() to authenticated;
revoke all on function auswertung_anfordern() from public;
grant execute on function auswertung_anfordern() to authenticated;
comment on function auswertung_anfordern() is
  '„Neu rechnen" (0102, 0107, 0108): merkt die Anforderung; wo pg_cron da ist, rechnet der Zeitplan sie beim nächsten '
  'Takt. Fehlt der Eintrag, wird er angelegt; ist er abgeschaltet (Notaus), bleibt er es (weg: aus). Ohne pg_cron '
  '(Prüfung, Demo) weg: app. Nur für den Betriebsleiter oder ohne Anmeldung.';
revoke all on function auswertung_anfordern() from public;
grant execute on function auswertung_anfordern() to authenticated;

create or replace function auswertung_aktualisieren() returns timestamptz
language plpgsql security definer set search_path = public set jit = 'off'
as $$
declare i int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.'
      using errcode = '42501';
  end if;
  -- Aus dem Browser (angemeldet), wo pg_cron da ist: nur anfordern (0107, 0108).
  if auth.uid() is not null and auswertung_cron_da() then
    perform auswertung_anfordern();
    return now();
  end if;
  for i in 1..5 loop
    perform auswertung_schritt_intern(i, false);
  end loop;
  return now();
end $$;

comment on function auswertung_aktualisieren is
  'Rechnet die Auswertung neu. Dauert je nach Datenmenge einige Sekunden — '
  'währenddessen sind die drei gespeicherten Ansichten kurz gesperrt.';

grant execute on function auswertung_aktualisieren() to authenticated;
revoke execute on function auswertung_aktualisieren() from public;
grant execute on function auswertung_aktualisieren() to authenticated;
revoke all on function auswertung_aktualisieren() from public;
grant execute on function auswertung_aktualisieren() to authenticated;
comment on function auswertung_aktualisieren() is
  'Alle fünf Schritte des Neurechnens nacheinander — für die Prüfstände und Einspielungen ohne Anmeldung. '
  'Aus dem Browser fordert sie nur an, wo pg_cron da ist (0107, 0108). Nur für den Betriebsleiter.';
revoke all on function auswertung_aktualisieren() from public;
grant execute on function auswertung_aktualisieren() to authenticated;

create or replace function auswertung_schritt(p_schritt integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and auswertung_cron_da() then
    if p_schritt = 1 then
      perform auswertung_anfordern();
    end if;
    return jsonb_build_object('schritt', p_schritt, 'schritte', 5, 'titel', 'angefordert', 'dauer_ms', 0,
                              'fertig', p_schritt = 5, 'nebenlaeufig', true, 'wartet', false, 'angefordert', true);
  end if;
  return auswertung_schritt_intern(p_schritt, false);
end $$;
revoke execute on function auswertung_schritt(integer) from public;
grant execute on function auswertung_schritt(integer) to authenticated;
revoke execute on function auswertung_schritt(integer) from public;
grant execute on function auswertung_schritt(integer) to authenticated;
comment on function auswertung_schritt(integer) is
  'Ein Schritt des Neurechnens aus der App — nur ohne pg_cron (Demo ohne Zeitplan, Prüfung). Wo pg_cron da ist, fordert '
  'Schritt 1 an und alle Schritte melden sich sofort zurück (0107, 0108); gerechnet wird im Hintergrund.';
revoke execute on function auswertung_schritt(integer) from public;
grant execute on function auswertung_schritt(integer) to authenticated;

drop function if exists auswertung_zeitplan_aktiv();

do $$
begin
  execute 'alter role postgres set statement_timeout = ''15min''';
  raise notice 'Zeitgrenze der Rolle postgres: 15 Minuten (0108).';
exception when others then
  raise notice 'Zeitgrenze der Rolle nicht gesetzt (%)', sqlerrm;
end $$;

-- aus 0110_rechnen_auf_postgres_17.sql

create or replace function palox_f_nach(p_hand numeric, p_wasch numeric, f_ws numeric, f_s numeric, g_w numeric,
                                        b_ws numeric, b_s numeric, g_b numeric, d_tage numeric)
returns numeric language sql immutable as $$
  select public.palox_f(p_hand, p_wasch,
                 case when f_ws is null then null else least(greatest(f_ws + coalesce(b_ws, 0) * d_tage / 7.0, 0), 1) end,
                 case when f_s  is null then null else least(greatest(f_s  + coalesce(b_s,  0) * d_tage / 7.0, 0), 1) end,
                 case when g_w  is null then null else least(greatest(g_w  + coalesce(g_b,  0) * d_tage / 7.0, 0), 1) end)
$$;
revoke all on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) from public;
grant execute on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) to authenticated;
comment on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) is
  'palox_f() d Tage später: jede Station um ihren Zuwachs je Woche (Kennzahl 0105) fortgeschrieben (0106). '
  'Nennt palox_f mit Schema, weil PostgreSQL 17 beim Auffrischen nur pg_catalog sucht (0110).';
revoke all on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) from public;
grant execute on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) to authenticated;

-- aus 0111_palox_grundausschuss_und_anstieg.sql

create or replace function anteil_mindest_messungen() returns int
language sql immutable as $$ select 3 $$;
comment on function anteil_mindest_messungen() is
  'Ab so vielen eigenen Messungen (Wägungen, Sortierläufe, Handmessungen) gilt der Wert der Sorte; darunter der Wert aller Sorten (0111).';
revoke all on function anteil_mindest_messungen() from public;
grant execute on function anteil_mindest_messungen() to authenticated;

drop function if exists palox_station_kennzahl(date, date) cascade;

drop function if exists palox_trend_mindest_tage();

create or replace function palox_anstieg_mindest_tage() returns int
language sql immutable as $$ select 21 $$;
comment on function palox_anstieg_mindest_tage() is
  'So viele Tage müssen die Lagerdauern innerhalb einer Sorte mindestens auseinanderliegen, bevor eine Station ihren Anstieg je Woche ausweist (0111).';
revoke all on function palox_anstieg_mindest_tage() from public;
grant execute on function palox_anstieg_mindest_tage() to authenticated;

create or replace function palox_anstieg(p_roh numeric, p_n_paar int, p_spanne int) returns numeric
language sql immutable as $$
  select case when p_roh is not null and p_n_paar >= 5 and p_spanne >= public.palox_anstieg_mindest_tage()
              then greatest(p_roh, 0) end
$$;
comment on function palox_anstieg(numeric, integer, integer) is
  'Der Anstieg je Woche, der gilt (0111): leer unter fünf Arbeiten in Sorten mit zwei Arbeiten oder unter palox_anstieg_mindest_tage() Spanne, sonst der gemessene, nie unter 0.';
revoke all on function palox_anstieg(numeric, integer, integer) from public;
grant execute on function palox_anstieg(numeric, integer, integer) to authenticated;

create function palox_station_kennzahl(p_bis date, p_ab date default null)
returns table(station text, n_arbeiten int, n_chargen int, seit date, bis date, tage int,
              anteil_mittel numeric, anteil_median numeric, anteil_4w numeric, n_4w int,
              zuwachs_je_woche numeric, zuwachs_text text,
              anstieg_roh numeric, anstieg_unten numeric, anstieg_oben numeric,
              n_paar int, spanne_tage int, lager_von int, lager_bis int,
              lager_mittel numeric, grund numeric)
language plpgsql stable set search_path = public as $$
#variable_conflict use_column
begin
  return query
  with p as (
    select e.station, e.sorte, e.charge_nr, e.messtag, e.lagertage::numeric as t,
           e.basis_jetzt_kg as w, e.anteil_station as y
      from erg_punkte e
     where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
       and e.lagertage is not null
       and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
       and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
       and e.messtag <= p_bis and (p_ab is null or e.messtag >= p_ab)
  ), s as (
    -- Je Sorte und Station die eigene Mitte: verglichen wird nur innerhalb der Sorte.
    select p.*,
           sum(p.w * p.t) over ws / sum(p.w) over ws as t_s,
           sum(p.w * p.y) over ws / sum(p.w) over ws as y_s,
           count(*) over ws                         as n_s,
           max(p.t) over ws - min(p.t) over ws      as spanne_s
      from p
    window ws as (partition by p.station, p.sorte)
  ), je as (
    select station,
           count(*)::int as n_arbeiten, count(distinct charge_nr)::int as n_chargen,
           min(messtag) as seit, max(messtag) as bis, (max(messtag) - min(messtag))::int as tage,
           sum(w * y) / nullif(sum(w), 0) as anteil_mittel,
           percentile_cont(0.5) within group (order by y) as anteil_median,
           sum(w * y) filter (where messtag > p_bis - 28) / nullif(sum(w) filter (where messtag > p_bis - 28), 0) as anteil_4w,
           count(*) filter (where messtag > p_bis - 28)::int as n_4w,
           count(*) filter (where n_s >= 2)::int as n_paar,
           count(distinct sorte) filter (where n_s >= 2)::int as n_sorten_paar,
           coalesce(max(spanne_s), 0)::int as spanne_tage,
           min(t)::int as lager_von, max(t)::int as lager_bis,
           sum(w * t) / nullif(sum(w), 0) as lager_mittel,
           avg(w) filter (where n_s >= 2) as w_mittel,
           sum(w * (t - t_s) * (y - y_s)) / nullif(sum(w * power(t - t_s, 2)), 0) as b_tag
      from s
     group by station
  ), streuung as (
    -- Wie weit die Arbeiten um ihre Geraden streuen (je Sorte eine eigene
    -- Höhe, eine gemeinsame Steigung): daraus der Standardfehler der Steigung.
    select s.station,
           sum(s.w / j.w_mittel * power((s.y - s.y_s) - j.b_tag * (s.t - s.t_s), 2)) as sse,
           sum(s.w / j.w_mittel * power(s.t - s.t_s, 2)) as sxx,
           j.n_paar - j.n_sorten_paar - 1 as df
      from s join je j on j.station = s.station
     where s.n_s >= 2 and j.b_tag is not null
     group by s.station, j.n_paar, j.n_sorten_paar
  ), fertig as (
    select j.*,
           case when st.df >= 1 and st.sxx > 0 then sqrt(st.sse / st.df / st.sxx) end as se_tag,
           st.df,
           palox_anstieg(j.b_tag * 7, j.n_paar, j.spanne_tage) is not null as bekannt
      from je j left join streuung st on st.station = j.station
  )
  select f.station, f.n_arbeiten, f.n_chargen, f.seit, f.bis, f.tage,
         zahl(f.anteil_mittel, 5, 1)::numeric(10,5), zahl(f.anteil_median::numeric, 5, 1)::numeric(10,5),
         zahl(f.anteil_4w, 5, 1)::numeric(10,5), f.n_4w,
         zahl(palox_anstieg(f.b_tag * 7, f.n_paar, f.spanne_tage), 5, 1)::numeric(10,5) as zuwachs_je_woche,
         case when f.bekannt and f.b_tag >= 0 then null
              when f.bekannt then format('kein Anstieg messbar (gemessen %s Punkte je Woche)',
                                         replace(replace(to_char(f.b_tag * 700, 'FM990.0'), '.', ','), '-', '−'))
              when f.n_paar < 5 then format('Anstieg erst ab fünf Arbeiten in Sorten mit mindestens zwei Arbeiten (%s bis jetzt)', f.n_paar)
              else format('Anstieg erst, wenn die Lagerdauern einer Sorte %s Tage auseinanderliegen (bis jetzt %s)',
                          palox_anstieg_mindest_tage(), f.spanne_tage) end as zuwachs_text,
         zahl(f.b_tag * 7, 5, 1)::numeric(10,5) as anstieg_roh,
         zahl((f.b_tag - t_quantil_95(f.df) * f.se_tag) * 7, 5, 1)::numeric(10,5) as anstieg_unten,
         zahl((f.b_tag + t_quantil_95(f.df) * f.se_tag) * 7, 5, 1)::numeric(10,5) as anstieg_oben,
         f.n_paar, f.spanne_tage, f.lager_von, f.lager_bis,
         zahl(f.lager_mittel, 1, 100000)::numeric(10,1) as lager_mittel,
         zahl(greatest(f.anteil_mittel - coalesce(palox_anstieg(f.b_tag * 7, f.n_paar, f.spanne_tage), 0) * f.lager_mittel / 7.0, 0), 5, 1)::numeric(10,5) as grund
    from fertig f
   order by case f.station when 'waschen_sortieren' then 1 when 'waschen' then 2 else 3 end;
end $$;
revoke all on function palox_station_kennzahl(date, date) from public;
grant execute on function palox_station_kennzahl(date, date) to authenticated;

-- aus 0112_lager_nach_artikel.sql

alter table sorte_kaliber add column if not exists artikelgruppe text;
comment on column sorte_kaliber.artikelgruppe is
  'Als welcher Artikel die Sorte verkauft wird (Knirps, Butternut, Butterkin/Muskat, Kabocha, Mandarin, …) — 0112. Leer: v_sorte_artikelgruppe nimmt die meistverkaufte Gruppe der Sorte.';

update sorte_kaliber s set artikelgruppe = v.gruppe
  from (values ('Kaori Kuri', 'Knirps'), ('Ker Madec', 'Knirps'), ('Orange Summer', 'Knirps'),
               ('Amoro', 'Knirps'), ('Fictor', 'Knirps'),
               ('Tiana', 'Butternut'), ('Mieluna', 'Butternut'),
               ('Butterkin', 'Butterkin/Muskat'), ('Lekor', 'Kabocha'), ('Orangita', 'Mandarin')) v(sorte, gruppe)
 where s.sorte = v.sorte and s.artikelgruppe is null;

alter table charge add column if not exists label text;
do $$ begin
  alter table charge add constraint charge_label_dk check (label in ('D', 'K'));
exception when duplicate_object then null; end $$;
comment on column charge.label is
  'Demeter (D) oder Knospe (K) — 0112. Leer: v_charge_label nimmt das Label, mit dem Perigon die Charge geliefert hat.';

alter table ausgang_zeile add column if not exists liefer_label text;
alter table ausgang_zeile add column if not exists preisgruppe text;
comment on column ausgang_zeile.liefer_label is
  'LiefPrsGrpName der Perigon-Datei: das Label der gelieferten Charge (D, K, CH-K, …) — 0112.';
comment on column ausgang_zeile.preisgruppe is
  'AuftragsPrsGrpBez der Perigon-Datei: das Label, als das der Artikel verkauft wurde (D, K, …) — 0112.';

create table if not exists artikel_kaliber (
  gruppe          text not null,
  groesse         text not null check (groesse in ('klein', 'gross', 'stueck')),
  von_g           int  not null check (von_g >= 0),
  bis_g           int  not null,
  stueck_je_kiste int  check (stueck_je_kiste > 0),
  bemerkung       text,
  erfasser        uuid references profil(id) default auth.uid(),
  ts              timestamptz not null default now(),
  primary key (gruppe, groesse),
  constraint artikel_kaliber_spanne check (bis_g > von_g)
);
comment on table artikel_kaliber is
  'Was ein Artikel gross und klein nennt: je Artikelgruppe das Kaliber in Gramm [von, bis) und die Stück je Kiste (0112). Vorbelegt aus den Coop-Artikeldaten 2026; „stueck" heisst: eine Grösse.';

insert into artikel_kaliber (gruppe, groesse, von_g, bis_g, stueck_je_kiste, bemerkung)
values ('Knirps', 'klein', 600, 1100, 10, 'Coop-Artikeldaten 2026'),
       ('Knirps', 'gross', 1100, 1600, 8, 'Coop-Artikeldaten 2026'),
       ('Butternut', 'klein', 800, 1300, 10, 'Coop-Artikeldaten 2026'),
       ('Butternut', 'gross', 1300, 1800, 8, 'Coop-Artikeldaten 2026'),
       ('Butterkin/Muskat', 'klein', 600, 1200, 10, 'Coop-Artikeldaten 2026'),
       ('Butterkin/Muskat', 'gross', 1200, 1800, 8, 'Coop-Artikeldaten 2026'),
       ('Kabocha', 'klein', 700, 1200, 10, 'Coop-Artikeldaten 2026'),
       ('Kabocha', 'gross', 1200, 1700, 8, 'Coop-Artikeldaten 2026'),
       ('Mandarin', 'stueck', 300, 800, 12, 'Coop-Artikeldaten 2026')
on conflict (gruppe, groesse) do nothing;

alter table artikel_kaliber enable row level security;
drop policy if exists artikel_kaliber_lesen on artikel_kaliber;
drop policy if exists artikel_kaliber_admin on artikel_kaliber;
create policy artikel_kaliber_lesen on artikel_kaliber for select to authenticated using (true);
create policy artikel_kaliber_admin on artikel_kaliber for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on artikel_kaliber to authenticated;

create or replace function artikel_einordnen(p_artikel text, p_preisgruppe text default null)
returns table (gruppe text, groesse text, label text)
language sql immutable set search_path = public as $$
  select case when a ~ '(knirps|potimarron|hokkaido|kuri)' then 'Knirps'
              when a ~ 'butternu' then 'Butternut'
              when a ~ '(butterkin|muskat|muscat)' then 'Butterkin/Muskat'
              when a ~ '(kobocha|kabocha)' then 'Kabocha'
              when a ~ 'mandarin' then 'Mandarin'
              when a ~ '\mmix\M' then 'Mix'
              when a ~ 'k(ü|u|ue)rb' then 'andere'
         end,
         case when a ~ '(gross|\mgros\M|\mgr\.)' then 'gross'
              when a ~ '(klein|\mkl\.)' then 'klein'
              else 'lose' end,
         case when upper(coalesce(p_preisgruppe, '')) in ('D', 'DU') then 'D'
              when upper(coalesce(p_preisgruppe, '')) in ('K', 'KZ') then 'K'
              when a ~ '(demeter|\mdem\M)' then 'D'
              when a ~ 'knospe' then 'K'
         end
    from (select lower(coalesce(p_artikel, '')) as a) t
$$;

revoke all on function artikel_einordnen(text, text) from public;
grant execute on function artikel_einordnen(text, text) to authenticated;

create or replace function ist_kuerbis_vorschlag(p_artikel_id text, p_artikel text)
returns boolean language sql immutable set search_path = public as $$
  select lower(coalesce(p_artikel_id, '') || ' ' || coalesce(p_artikel, '')) ~ 'k(ü|u|ue)rb'
     and lower(coalesce(p_artikel_id, '') || ' ' || coalesce(p_artikel, '')) !~ '(verrechnung|arbeit|lohn|transport|miete|gebühr)'
$$;
revoke all on function ist_kuerbis_vorschlag(text, text) from public;
grant execute on function ist_kuerbis_vorschlag(text, text) to authenticated;

create or replace function saison_von(p_datum date) returns int
language sql immutable set search_path = public as $$
  select case when extract(month from p_datum) >= 7 then extract(year from p_datum)::int
              else extract(year from p_datum)::int - 1 end
$$;
revoke all on function saison_von(date) from public;
grant execute on function saison_von(date) to authenticated;

create table if not exists ausgang_position (
  quelle             text   not null references ausgang_quelle(code) on update cascade on delete cascade,
  pos_id             bigint not null,
  datum              date   not null,
  saison             int    not null,
  journal            text,
  kunde              text,
  artikel_id         text   not null,
  artikel            text   not null,
  preisgruppe        text,
  einheit            text,
  menge              numeric(14,3),
  gewicht_je_artikel numeric(10,4),
  kg                 numeric(14,3),
  gebindeart         text,
  gebinde_menge      int,
  ts                 timestamptz not null default now(),
  primary key (quelle, pos_id)
);
create index if not exists ausgang_position_saison on ausgang_position (saison, kunde);
comment on table ausgang_position is
  'Jede Lieferscheinposition der Perigon-Datei, alle Saisons (0112) — einmal je Position, kg = Menge × Gewicht je Artikel. Nur für den Vergleich je Kunde und Saison; die Bilanz rechnet mit ausgang_zeile und lieferung.';

alter table ausgang_position enable row level security;
drop policy if exists ausgang_position_lesen on ausgang_position;
drop policy if exists ausgang_position_admin on ausgang_position;
create policy ausgang_position_lesen on ausgang_position for select to authenticated using (true);
create policy ausgang_position_admin on ausgang_position for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on ausgang_position to authenticated;

insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette, bemerkung)
values ('Migros Kiste U', 2.43, 25.0, 'Rückmeldung aus der Halle, 10.10.2026 (0112): Tara 2.43 kg je Kiste'),
       ('Plastik Palox', 35.0, 0, 'Rückmeldung aus der Halle, 10.10.2026 (0112): eine Palox = ein Gebinde, Tara 35 kg, keine Palette')
on conflict (art) do nothing;

-- aus 0113_demeter_wenn_je_demeter.sql

create or replace function artikel_einordnen(p_artikel text, p_preisgruppe text default null)
returns table (gruppe text, groesse text, label text)
language sql immutable set search_path = public as $$
  select case when a ~ '(knirps|potimarron|hokkaido|kuri)' then 'Knirps'
              when a ~ 'butternu' then 'Butternut'
              when a ~ '(butterkin|muskat|muscat)' then 'Butterkin/Muskat'
              when a ~ '(kobocha|kabocha)' then 'Kabocha'
              when a ~ 'mandarin' then 'Mandarin'
              when a ~ '\mmix\M' then 'Mix'
              when a ~ 'k(ü|u|ue)rb' then 'andere'
         end,
         case when a ~ '(gross|\mgros\M|\mgr\.)' then 'gross'
              when a ~ '(klein|\mkl\.)' then 'klein'
              else 'lose' end,
         -- Die Preisgruppe des Auftrags zuerst: D, DU (Demeter); K, KZ, CH-K,
         -- KAdR (Knospe). Andere (SG …) sagen nichts — dann der Name.
         case when upper(coalesce(p_preisgruppe, '')) like 'D%' then 'D'
              when upper(coalesce(p_preisgruppe, '')) ~ '^(K|CH-K)' then 'K'
              when a ~ '(demeter|\mdem\M)' then 'D'
              when a ~ 'knospe' then 'K'
         end
    from (select lower(coalesce(p_artikel, '')) as a) t
$$;
comment on function artikel_einordnen(text, text) is
  'Ein Verkaufsartikel aus Perigon eingeordnet: Artikelgruppe, Grösse (gross, klein, lose) und Label (D/K, aus der Preisgruppe — D…: Demeter; K…, CH-K: Knospe —, sonst aus dem Namen) — 0112, Preisgruppen seit 0113.';
revoke all on function artikel_einordnen(text, text) from public;
grant execute on function artikel_einordnen(text, text) to authenticated;

create or replace function palox_anstieg(p_roh numeric, p_n_paar int, p_spanne int, p_unten numeric) returns numeric
language sql immutable as $$
  select case when public.palox_anstieg(p_roh, p_n_paar, p_spanne) is null then null
              when p_roh > 0 and p_unten > 0 then p_roh
              else 0 end
$$;
comment on function palox_anstieg(numeric, integer, integer, numeric) is
  'Der Anstieg je Woche, der gilt (seit 0113): leer wie palox_anstieg(roh, n, spanne); sonst der gemessene, wenn er positiv und sicher ist (untere Grenze des 95-%-Bereichs über 0), sonst 0.';
revoke all on function palox_anstieg(numeric, integer, integer, numeric) from public;
grant execute on function palox_anstieg(numeric, integer, integer, numeric) to authenticated;

-- aus 0115_das_kilo_kommt_aus_der_menge.sql

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

revoke all on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) from public;
grant execute on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) to authenticated;
revoke all on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) from public;
grant execute on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) to authenticated;
revoke all on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) from public;
grant execute on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) to authenticated;
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

-- aus 0116_die_groesse_kommt_aus_der_sortierdatei.sql

insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette, bemerkung)
values ('Holz Palox', 45.0, 0, 'Betrieb, 19.10.2026 (0116): eine Palox = ein Gebinde, Tara 45 kg, keine Palette'),
       ('Plastik Palox', 35.0, 0, 'Betrieb, 19.10.2026 (0116): eine Palox = ein Gebinde, Tara 35 kg, keine Palette')
on conflict (art) do update
  set tara_kg_pro_kiste = excluded.tara_kg_pro_kiste, tara_kg_palette = excluded.tara_kg_palette,
      bemerkung = excluded.bemerkung
  where gebinde.tara_kg_pro_kiste is distinct from excluded.tara_kg_pro_kiste
     or gebinde.tara_kg_palette is distinct from excluded.tara_kg_palette;

alter table charge add column if not exists hagel_anteil numeric(5,4);
alter table charge add column if not exists hagel_ts timestamptz;
do $$ begin
  alter table charge add constraint charge_hagel_anteil check (hagel_anteil > 0 and hagel_anteil <= 1);
exception when duplicate_object then null; end $$;
comment on column charge.hagel_anteil is
  'Hagelschaden der Charge als Anteil des Eingangs (0116), vom Betriebsleiter unter Chargen gesetzt; leer = kein Hagel. Er kommt beim Waschen und Sortieren in den Palox: f = 1 − (1 − f) · (1 − Hagel) für alles, was noch liegt, und für Ausgelagertes ohne eigene Messung. 1 = nichts verkaufsfähig.';
comment on column charge.hagel_ts is 'Wann der Hagelschaden zuletzt gesetzt wurde (0116).';

create table if not exists messung_ausschluss (
  art       text   not null check (art in ('palox', 'palox_lager', 'verdunstung')),
  bezug_id  bigint not null,
  grund     text,
  erfasser  uuid references profil(id) on delete set null default auth.uid(),
  ts        timestamptz not null default now(),
  primary key (art, bezug_id)
);
comment on table messung_ausschluss is
  'Messungen, die der Betriebsleiter von Hand aus der Rechnung nimmt (0116): palox — der Palox-Anteil einer Arbeit (bezug_id = auftrag.id); palox_lager — das Faule einer Kontrollwägung (bezug_id = verdunstung_wiegung.id); verdunstung — eine Verdunstungs-Wägung (bezug_id = verdunstung_wiegung.id). Die Messung bleibt im Bild und zählt in keine Rate; ab der nächsten Rechnung. Löschen der Zeile nimmt sie wieder auf.';
alter table messung_ausschluss enable row level security;
drop policy if exists messung_ausschluss_lesen on messung_ausschluss;
drop policy if exists messung_ausschluss_admin on messung_ausschluss;
create policy messung_ausschluss_lesen on messung_ausschluss for select to authenticated using (true);
create policy messung_ausschluss_admin on messung_ausschluss for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on messung_ausschluss to authenticated;

create table if not exists kunde_gruppe (
  kunde     text primary key check (btrim(kunde) <> ''),
  gruppe    text not null check (btrim(gruppe) <> ''),
  erfasser  uuid references profil(id) on delete set null default auth.uid(),
  ts        timestamptz not null default now()
);
comment on table kunde_gruppe is
  'Zu welcher Gruppe ein Perigon-Kunde (AuftragsLieferant) gehört (0116), vom Betriebsleiter gesetzt. Ohne Eintrag ordnet die App nach dem Namen: Migros, Coop (auch RVZ/RZV), sonst Kleinkunden.';
alter table kunde_gruppe enable row level security;
drop policy if exists kunde_gruppe_lesen on kunde_gruppe;
drop policy if exists kunde_gruppe_admin on kunde_gruppe;
create policy kunde_gruppe_lesen on kunde_gruppe for select to authenticated using (true);
create policy kunde_gruppe_admin on kunde_gruppe for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on kunde_gruppe to authenticated;

create table if not exists kunde_plan (
  id            bigint generated by default as identity primary key,
  saison        int  not null,
  kunde         text not null check (btrim(kunde) <> ''),
  artikelgruppe text not null default '',
  groesse       text not null default '' check (groesse in ('', 'klein', 'gross')),
  label         text not null default '' check (label in ('', 'D', 'K')),
  kg            numeric(12,1) not null check (kg >= 0),
  erfasser      uuid references profil(id) on delete set null default auth.uid(),
  ts            timestamptz not null default now(),
  unique (saison, kunde, artikelgruppe, groesse, label)
);
comment on table kunde_plan is
  'Die Planmenge eines Kunden für eine Saison (0116), in kg — je Artikelgruppe, Grösse und Label oder für alle ('''' = alle). Gilt genau für die Wahl, für die sie eingetragen ist; ohne Plan nimmt die App die ganze Vorjahressaison als Plan. Vom Betriebsleiter gesetzt.';
alter table kunde_plan enable row level security;
drop policy if exists kunde_plan_lesen on kunde_plan;
drop policy if exists kunde_plan_admin on kunde_plan;
create policy kunde_plan_lesen on kunde_plan for select to authenticated using (true);
create policy kunde_plan_admin on kunde_plan for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on kunde_plan to authenticated;

alter table ausgang_position add column if not exists roh jsonb;
comment on column ausgang_position.roh is
  'Die Zeilen der Perigon-Datei zu dieser Position, je Zeile alle Spalten so, wie sie in der Datei stehen (Spaltenname → Wert) — 0116, für „die ganze Excel-Zeile" in der App. Leer, bis die Datei nach 0116 neu eingelesen ist.';

create or replace function palox_station_kennzahl(p_bis date, p_ab date default null)
returns table(station text, n_arbeiten int, n_chargen int, seit date, bis date, tage int,
              anteil_mittel numeric, anteil_median numeric, anteil_4w numeric, n_4w int,
              zuwachs_je_woche numeric, zuwachs_text text,
              anstieg_roh numeric, anstieg_unten numeric, anstieg_oben numeric,
              n_paar int, spanne_tage int, lager_von int, lager_bis int,
              lager_mittel numeric, grund numeric)
language plpgsql stable set search_path = public as $$
#variable_conflict use_column
begin
  return query
  with p as (
    select e.station, e.sorte, e.charge_nr, e.messtag, e.lagertage::numeric as t,
           e.basis_jetzt_kg as w, e.anteil_station as y
      from erg_punkte e
     where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
       and e.lagertage is not null
       and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
       and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
       and e.messtag <= p_bis and (p_ab is null or e.messtag >= p_ab)
       -- 0116: eine Charge mit Hagel trägt ihren Hagel nicht in den Anteil der Station.
       and not exists (select 1 from charge hc where hc.nr = e.charge_nr and hc.hagel_anteil > 0)
  ), s as (
    -- Je Sorte und Station die eigene Mitte: verglichen wird nur innerhalb der Sorte.
    select p.*,
           sum(p.w * p.t) over ws / sum(p.w) over ws as t_s,
           sum(p.w * p.y) over ws / sum(p.w) over ws as y_s,
           count(*) over ws                         as n_s,
           max(p.t) over ws - min(p.t) over ws      as spanne_s
      from p
    window ws as (partition by p.station, p.sorte)
  ), je as (
    select station,
           count(*)::int as n_arbeiten, count(distinct charge_nr)::int as n_chargen,
           min(messtag) as seit, max(messtag) as bis, (max(messtag) - min(messtag))::int as tage,
           sum(w * y) / nullif(sum(w), 0) as anteil_mittel,
           percentile_cont(0.5) within group (order by y) as anteil_median,
           sum(w * y) filter (where messtag > p_bis - 28) / nullif(sum(w) filter (where messtag > p_bis - 28), 0) as anteil_4w,
           count(*) filter (where messtag > p_bis - 28)::int as n_4w,
           count(*) filter (where n_s >= 2)::int as n_paar,
           count(distinct sorte) filter (where n_s >= 2)::int as n_sorten_paar,
           coalesce(max(spanne_s), 0)::int as spanne_tage,
           min(t)::int as lager_von, max(t)::int as lager_bis,
           sum(w * t) / nullif(sum(w), 0) as lager_mittel,
           avg(w) filter (where n_s >= 2) as w_mittel,
           sum(w * (t - t_s) * (y - y_s)) / nullif(sum(w * power(t - t_s, 2)), 0) as b_tag
      from s
     group by station
  ), streuung as (
    -- Wie weit die Arbeiten um ihre Geraden streuen (je Sorte eine eigene
    -- Höhe, eine gemeinsame Steigung): daraus der Standardfehler der Steigung.
    select s.station,
           sum(s.w / j.w_mittel * power((s.y - s.y_s) - j.b_tag * (s.t - s.t_s), 2)) as sse,
           sum(s.w / j.w_mittel * power(s.t - s.t_s, 2)) as sxx,
           j.n_paar - j.n_sorten_paar - 1 as df
      from s join je j on j.station = s.station
     where s.n_s >= 2 and j.b_tag is not null
     group by s.station, j.n_paar, j.n_sorten_paar
  ), fertig as (
    select j.*,
           case when st.df >= 1 and st.sxx > 0 then sqrt(st.sse / st.df / st.sxx) end as se_tag,
           st.df,
           palox_anstieg(j.b_tag * 7, j.n_paar, j.spanne_tage) is not null as bekannt
      from je j left join streuung st on st.station = j.station
  ), regel as (
    -- Seit 0113: Der Anstieg gilt erst, wenn er sicher ist — die untere
    -- Grenze seines 95-%-Bereichs liegt über 0. Sonst gilt 0, und der
    -- Grundausschuss ist das gemessene Mittel (der Betrieb: „du musst nicht
    -- denken, dass wenn ich es heute ins Lager tue und morgen verkaufe, dass
    -- ich null Ausschuss habe").
    select f.*,
           case when f.se_tag is not null then (f.b_tag - t_quantil_95(f.df) * f.se_tag) * 7 end as unten_woche,
           palox_anstieg(f.b_tag * 7, f.n_paar, f.spanne_tage,
                         case when f.se_tag is not null then (f.b_tag - t_quantil_95(f.df) * f.se_tag) * 7 end) as gilt
      from fertig f
  )
  select f.station, f.n_arbeiten, f.n_chargen, f.seit, f.bis, f.tage,
         zahl(f.anteil_mittel, 5, 1)::numeric(10,5), zahl(f.anteil_median::numeric, 5, 1)::numeric(10,5),
         zahl(f.anteil_4w, 5, 1)::numeric(10,5), f.n_4w,
         zahl(f.gilt, 5, 1)::numeric(10,5) as zuwachs_je_woche,
         case when f.gilt > 0 then null
              when f.bekannt and f.b_tag > 0 then format('Anstieg noch nicht sicher (gemessen +%s %% je Woche, Bereich %s bis +%s %%) — gilt als 0',
                                         replace(to_char(f.b_tag * 700, 'FM990.0'), '.', ','),
                                         replace(replace(to_char(coalesce(f.unten_woche * 100, -99.9), 'FM990.0'), '.', ','), '-', '−'),
                                         replace(to_char((f.b_tag + t_quantil_95(f.df) * coalesce(f.se_tag, 0)) * 700, 'FM990.0'), '.', ','))
              when f.bekannt then format('kein Anstieg (gemessen %s %% je Woche — gilt als 0)',
                                         replace(replace(to_char(f.b_tag * 700, 'FM990.0'), '.', ','), '-', '−'))
              when f.n_paar < 5 then format('Anstieg erst ab fünf Arbeiten in Sorten mit mindestens zwei Arbeiten (%s bis jetzt)', f.n_paar)
              else format('Anstieg erst, wenn die Lagerdauern einer Sorte %s Tage auseinanderliegen (bis jetzt %s)',
                          palox_anstieg_mindest_tage(), f.spanne_tage) end as zuwachs_text,
         zahl(f.b_tag * 7, 5, 1)::numeric(10,5) as anstieg_roh,
         zahl((f.b_tag - t_quantil_95(f.df) * f.se_tag) * 7, 5, 1)::numeric(10,5) as anstieg_unten,
         zahl((f.b_tag + t_quantil_95(f.df) * f.se_tag) * 7, 5, 1)::numeric(10,5) as anstieg_oben,
         f.n_paar, f.spanne_tage, f.lager_von, f.lager_bis,
         zahl(f.lager_mittel, 1, 100000)::numeric(10,1) as lager_mittel,
         zahl(greatest(f.anteil_mittel - coalesce(f.gilt, 0) * f.lager_mittel / 7.0, 0), 5, 1)::numeric(10,5) as grund
    from regel f
   order by case f.station when 'waschen_sortieren' then 1 when 'waschen' then 2 else 3 end;
end $$;

comment on function palox_station_kennzahl(date, date) is
  'Die Kennzahl je Station (0105, Anstieg seit 0111): Mittel, Median, letzte vier Wochen, und der Anstieg des Palox-Anteils je Woche Lagerdauer — innerhalb der Sorten gerechnet, nie negativ, bekannt ab fünf Arbeiten in Sorten mit zwei Arbeiten und drei Wochen Spanne der Lagerdauern; seit 0113 gilt er erst, wenn er sicher ist (sonst 0, der Grundausschuss ist dann das Mittel).';
revoke all on function palox_station_kennzahl(date, date) from public;
grant execute on function palox_station_kennzahl(date, date) to authenticated;

create or replace function hagel_f(p_f numeric, p_hagel numeric) returns numeric
language sql immutable as $$
  select case when coalesce(p_hagel, 0) <= 0 then p_f
              when p_hagel >= 1 then 1::numeric
              when p_f is null then null
              else 1 - (1 - least(greatest(p_f, 0), 1)) * (1 - p_hagel) end
$$;
comment on function hagel_f(numeric, numeric) is
  'Der Palox-Anteil mit Hagelschaden (0116): 1 − (1 − f) · (1 − Hagel). Ohne Hagel f; 100 % Hagel 1.';
revoke all on function hagel_f(numeric, numeric) from public;
grant execute on function hagel_f(numeric, numeric) to authenticated;

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
      gebindeart text, gebinde_menge numeric, roh jsonb)
  ), geschrieben as (
    insert into ausgang_position (quelle, pos_id, datum, saison, journal, kunde, artikel_id, artikel, preisgruppe,
                                  einheit, menge, gewicht_je_artikel, kg, gebindeart, gebinde_menge, roh)
    select p_quelle, e.pos_id, e.datum, saison_von(e.datum), e.journal, e.kunde, e.artikel_id, e.artikel,
           nullif(e.preisgruppe, ''), e.einheit, e.menge, e.gewicht_je_artikel,
           perigon_kg(coalesce(e.menge, 0), e.gewicht_je_artikel, e.einheit), nullif(e.gebindeart, ''),
           round(e.gebinde_menge)::int, e.roh
      from eingang e
     where e.pos_id is not null and e.datum is not null and e.artikel_id is not null and e.artikel is not null
    on conflict (quelle, pos_id) do update
      set datum = excluded.datum, saison = excluded.saison, journal = excluded.journal, kunde = excluded.kunde,
          artikel_id = excluded.artikel_id, artikel = excluded.artikel, preisgruppe = excluded.preisgruppe,
          einheit = excluded.einheit, menge = excluded.menge, gewicht_je_artikel = excluded.gewicht_je_artikel,
          kg = excluded.kg, gebindeart = excluded.gebindeart, gebinde_menge = excluded.gebinde_menge,
          -- 0116: die ganze Zeile; eine Datei ohne sie (ältere App) lässt die gespeicherte stehen.
          roh = coalesce(excluded.roh, ausgang_position.roh), ts = now()
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
revoke all on function ausgang_historie_uebernehmen(text, jsonb, jsonb) from public;
grant execute on function ausgang_historie_uebernehmen(text, jsonb, jsonb) to authenticated;
revoke all on function ausgang_historie_uebernehmen(text, jsonb, jsonb) from public;
grant execute on function ausgang_historie_uebernehmen(text, jsonb, jsonb) to authenticated;
comment on function ausgang_historie_uebernehmen(text, jsonb, jsonb) is
  'Schreibt beim Einlesen der Perigon-Datei jede Position aller Saisons nach ausgang_position und die Labels (LiefPrsGrpName, Preisgruppe) an die Zeilen der laufenden Saison (0112). Die Masse nach perigon_kg (0115): bei kg-Artikeln ohne Gewicht je Artikel die Menge, bei Stück ohne Stückgewicht leer. Seit 0116 mit der ganzen Zeile der Datei (roh), für die Anzeige in der App. Nur der Betriebsleiter.';
revoke all on function ausgang_historie_uebernehmen(text, jsonb, jsonb) from public;
grant execute on function ausgang_historie_uebernehmen(text, jsonb, jsonb) to authenticated;

create or replace function demo_daten_laden()
returns text language plpgsql security definer set search_path = public as $fn$
declare
  v_anker date := current_date - 215;
  -- Der Schnitt „was ist schon passiert" hing bisher an now(). Damit war die
  -- Saison nur *fast* reproduzierbar: lud man sie morgens und mittags, kamen
  -- verschieden viele Arbeiten heraus, weil ein Start von gestern abend beim
  -- einen Lauf noch vor der Grenze lag und beim anderen dahinter. Gemessen:
  -- 367 gegen 376 Arbeiten, zwei Läufe im Abstand von Minuten. Jetzt liegt
  -- die Grenze auf einer festen Stunde des Tages — zweimal laden am selben
  -- Tag gibt zweimal dieselbe Saison. Nur die laufenden Arbeiten am Schluss
  -- hängen weiter an now(), denn die sollen wirklich gerade laufen.
  v_jetzt timestamptz := current_date::timestamptz + interval '17 hours';
  v_wer   uuid := auth.uid();
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter laden.';
  end if;
  if exists (select 1 from palette where extern_id like 'demo-%') then
    raise exception E'Die Demo-Saison ist schon geladen.\nZum Neuladen zuerst entfernen.';
  end if;

  -- Im SQL-Editor gibt es keinen Login — dann tritt der Betriebsleiter ein.
  if v_wer is null then
    select id into v_wer from profil where rolle = 'admin' order by erstellt_ts limit 1;
  end if;
  if v_wer is null then select id into v_wer from profil order by erstellt_ts limit 1; end if;
  if v_wer is null then
    raise exception E'Es gibt noch kein Benutzerkonto.\nLege zuerst dein Betriebsleiter-Konto an (README, Schritt 7) und versuche es dann nochmal.';
  end if;
  perform set_config('request.jwt.claim.sub', v_wer::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_wer)::text, true);

  -- ---------- Stammdaten der Demo ----------------------------------------
  -- Bei Konflikt bleibt der bestehende Käufer, wie er ist — samt seiner
  -- (leeren) Bemerkung. Genau daran erkennt das Entfernen ihn als echten.
  insert into kaeufer (code, name, bemerkung) values
    ('nordmarkt', 'Nordmarkt Genossenschaft', 'DEMO'), ('talhof', 'Talhof Bio AG', 'DEMO'),
    ('gruenwerk', 'Grünwerk Handel', 'DEMO'), ('feldfrisch', 'Feldfrisch Ost', 'DEMO')
  on conflict (code) do nothing;
  -- Nordmarkt nimmt Butternut in der 8-kg-Kiste; Talhof will Kaori Kuri enger.
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'nordmarkt', v_anker + 20, 'kiste', 8, 'DEMO — Nordmarkt nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'nordmarkt' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'gruenwerk', v_anker + 25, 'kiste', 8, 'DEMO — Grünwerk nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'gruenwerk' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab, bemerkung)
  select 'Kaori Kuri', 'talhof', v_anker + 60, 'kaliber', 600, '[[600,1000],[1000,1400],[1400,2000]]'::jsonb, 2000,
         'DEMO — Talhof will Kaori Kuri in engeren Bändern (beim Eröffnen einer Arbeit geändert)'
   where not exists (select 1 from sortierschema where sorte = 'Kaori Kuri' and kaeufer = 'talhof' and art = 'kaliber');
  -- Ein Vorlauf: Charge 1611 lieferte schon 5 t, bevor die App lief.
  insert into charge_vorlauf (charge_nr, ausgang_vor_app_kg, bemerkung)
  values (1611, 5000, 'DEMO — vor dem Erfassungsbeginn ausgeliefert')
  on conflict (charge_nr) do nothing;

  -- ---------- Hilfstabellen ------------------------------------------------
  drop table if exists demo_charge; drop table if exists demo_pal; drop table if exists demo_lauf;
  create temp table demo_charge (
    nr int primary key, sorte text, weg text, kg numeric, kw int,
    anteil_verarbeitet numeric,      -- wie viel der Charge bis heute verarbeitet ist
    r numeric,                       -- Verdunstung je Tag
    lambda numeric, k numeric, sockel numeric,   -- Verderbskurve
    fax_anteil numeric, gramm int, sd int,       -- Faules beim Fax, Gewicht je Kürbis
    kg_kiste numeric, kaeufer text
  );
  -- Die ganze Anbauplanung, nicht nur ein Teil davon: jede Charge des
  -- Stammdatenregisters bekommt einen Eingang. Vorher blieben sechs ohne
  -- jede Zeile — im Dashboard standen sie als Chargen ohne Daten, und wer
  -- die Demo anschaute, hielt das für einen Fehler des Werkzeugs.
  insert into demo_charge (nr, kg, kw, anteil_verarbeitet) values
    (1598,  2200, 35, 1.00), (1599,  1400, 34, 0.85), (1601,  9800, 38, 0.25),
    (1603,  3100, 36, 1.00), (1604,  2600, 34, 0.90), (1605,  1200, 34, 1.00),
    (1606,   800, 33, 1.00), (1607,  1900, 34, 1.00), (1608,  6400, 36, 0.70),
    (1609, 12500, 35, 0.80), (1610,  4200, 37, 0.45), (1611, 38000, 37, 0.60),
    (1612, 16500, 35, 0.75), (1613, 24000, 35, 0.90), (1614,  3900, 34, 1.00),
    (1615,  3100, 34, 1.00), (1616,  8600, 34, 0.85), (1617,  2400, 35, 1.00),
    (1618,  4100, 34, 1.00), (1619,  1800, 34, 1.00), (1620,  2900, 35, 0.55),
    (1623,  9100, 36, 0.65), (1624,  7800, 35, 0.85), (1625,  2600, 34, 1.00),
    (1626,  4600, 39, 0.00), (1627,  2900, 39, 0.40), (1628, 11000, 34, 0.95),
    (1630, 10800, 34, 0.90), (1631, 14200, 39, 0.15), (1632, 35000, 37, 0.50),
    (1633, 22000, 38, 0.35), (1634,  6600, 36, 0.70), (1635,  5900, 36, 0.80),
    (1636, 17000, 36, 0.55), (1637,  5400, 36, 0.75), (1638,  4800, 36, 0.30),
    (1646,  7200, 34, 0.80), (1647,  8100, 39, 0.25), (1648,  9700, 34, 0.90),
    (1649, 20500, 38, 0.40), (1650,  2400, 39, 0.00), (1651,  3300, 35, 1.00);
  update demo_charge d set sorte = c.sorte from charge c where c.nr = d.nr;
  -- Butternut von Hand, alles andere über die Maschine. Sorteneigenschaften
  -- so, wie sie im Betrieb beobachtet werden: Hokkaido verdunstet schneller,
  -- Butternut hält länger, Mandarin ist klein.
  -- Mit WHERE, obwohl jede Zeile gemeint ist: Supabase lässt die API-Verbindung
  -- mit der Sicherung safeupdate laufen, die ein UPDATE ohne Bedingung abweist —
  -- auch in einer Funktion, auch auf einer Hilfstabelle.
  update demo_charge set
    weg    = case when sorte in ('Tiana', 'Mieluna') then 'hand' else 'maschine' end,
    r      = case sorte when 'Tiana' then 0.00045 when 'Mieluna' then 0.00050 when 'Butterkin' then 0.00060
                        when 'Orangita' then 0.00090 when 'Lekor' then 0.00065 else 0.00080 end,
    -- λ so, dass nach 150 Tagen rund 8 % (Butternut) bis 14 % (Mandarin) faul sind
    lambda = case sorte when 'Tiana' then 800 when 'Mieluna' then 720 when 'Butterkin' then 600
                        when 'Orangita' then 450 when 'Lekor' then 560 when 'Kaori Kuri' then 520 else 500 end,
    k      = case sorte when 'Tiana' then 1.5 when 'Orangita' then 1.9 else 1.7 end,
    sockel = case sorte when 'Orangita' then 0.006 else 0.004 end,
    fax_anteil = case sorte when 'Tiana' then 0.012 when 'Mieluna' then 0.015 when 'Orangita' then 0.030
                            when 'Butterkin' then 0.020 else 0.024 end,
    gramm  = case sorte when 'Orangita' then 560 when 'Butterkin' then 1250 when 'Lekor' then 1500
                        when 'Kaori Kuri' then 1100 when 'Amoro' then 1300 when 'Ker Madec' then 1000
                        when 'Fictor' then 1400 when 'Orange Summer' then 1200 when 'Bolp 5110' then 1200
                        when 'Tiana' then 1400 else 1200 end,
    sd     = case sorte when 'Orangita' then 170 when 'Tiana' then 420 when 'Lekor' then 420 else 320 end,
    kg_kiste = case sorte when 'Orangita' then 10.8 when 'Tiana' then 12.4 when 'Mieluna' then 12.0
                          when 'Butterkin' then 11.8 else 11.4 end,
    kaeufer = case nr % 4 when 0 then 'nordmarkt' when 1 then 'talhof' when 2 then 'gruenwerk' else 'feldfrisch' end
   where sorte is not null;
  -- Die zwei grossen Abnehmer teilen sich die frühen Chargen; die zwei
  -- kleineren nehmen, was später kommt — so steht es in der Verkaufsplanung.
  update demo_charge set kaeufer = case when nr % 2 = 0 then 'nordmarkt' else 'talhof' end
   where kw <= 35;

  create temp table demo_pal (
    id bigint, nr int, datum date, netto numeric, kisten int, verarbeitet boolean default false
  );
  create temp table demo_lauf (
    auftrag_id bigint, nr int, sorte text, start_ts timestamptz, masse_kg numeric, alter_tage numeric,
    art text, kaeufer text, baender jsonb, kg_je_kiste numeric,
    kisten int[]       -- gefüllte Kisten je Band (Index = Band)
  );

  -- ---------- 1. Wareneingang: je Charge in ihrer Erntewoche ---------------
  declare d record; v_n int; v_p int; v_tag date; v_kisten int; v_netto numeric; v_je_tag int;
          v_zufall numeric; v_art text; v_id bigint;
  begin
    for d in select * from demo_charge order by nr loop
      v_n := greatest(round(d.kg / (32 * d.kg_kiste))::int, 2);
      v_je_tag := case when v_n <= 6 then 4 when v_n <= 20 then 8 when v_n <= 60 then 14 else 22 end;
      v_tag := v_anker + (d.kw - 34) * 7 + (d.nr % 3);
      for v_p in 1 .. v_n loop
        -- Werktage: Samstag und Sonntag wird nicht geerntet
        if v_p > 1 and (v_p - 1) % v_je_tag = 0 then v_tag := v_tag + 1; end if;
        while extract(isodow from v_tag) >= 6 loop v_tag := v_tag + 1; end loop;
        v_zufall := (hashtext(format('pal-%s-%s', d.nr, v_p))::bigint & 2147483647)::numeric / 2147483647;
        v_kisten := 30 + (v_p * 7 + d.nr) % 5;
        v_netto  := round(v_kisten * d.kg_kiste * (0.94 + 0.12 * v_zufall), 1);
        -- Fremde Produzenten liefern teils in IFCO-Kisten
        v_art := case when d.nr in (1648, 1628, 1630, 1631) and v_p % 3 = 0 then 'IFCO 6416' else 'G2' end;
        insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
        values (d.nr, v_tag, v_netto + v_kisten * (case when v_art = 'G2' then 1.5 else 1.68 end) + 25,
                v_kisten, v_art, format('demo-%s-%s', d.nr, v_p))
        returning id into v_id;
        insert into demo_pal (id, nr, datum, netto, kisten) values (v_id, d.nr, v_tag, v_netto, v_kisten);
      end loop;
    end loop;
    raise notice 'Demo: Wareneingang angelegt (% Paletten)', (select count(*) from demo_pal);
  end;

  -- ---------- 2. Verarbeitung -----------------------------------------------
  -- Sortieren (Maschine) bzw. Waschen + Sortieren (Hand), in mehreren Läufen,
  -- ohne FIFO. Je Lauf: Paletten mit Datum vom Zettel, Palox zu Beginn und am
  -- Ende (Faules nach der Verderbskurve), CSV oder Wägungen, Kisten je Kaliber.
  declare d record; v_lauf int; v_n_laeufe int; v_n_pal int; v_verarbeitet int; v_ziel int;
          v_start timestamptz; v_auftrag bigint; v_masse numeric; v_tage numeric; v_f numeric;
          v_schimmel numeric; v_zufall numeric; v_schema bigint; v_art text; v_kaeufer text;
          v_baender jsonb; v_nb int; v_i int; v_hist jsonb; v_n int; v_gramm numeric;
          v_kisten int[]; v_kg_band numeric; v_klein numeric; v_gross numeric; v_x numeric;
          p record; v_pal_ids bigint[]; v_netto numeric; v_kisten_p int; v_brutto numeric;
          v_wiegung bigint; v_datum date; v_abstand int;
  begin
    for d in select * from demo_charge where anteil_verarbeitet > 0 order by nr loop
      select count(*) into v_n_pal from demo_pal where nr = d.nr;
      v_ziel := round(v_n_pal * d.anteil_verarbeitet)::int;
      if v_ziel = 0 then continue; end if;
      v_n_laeufe := greatest(ceil(v_ziel / 16.0)::int, 1);
      v_verarbeitet := 0;
      v_abstand := greatest(round(172.0 / v_n_laeufe)::int, 8);

      for v_lauf in 1 .. v_n_laeufe loop
        -- Wie viele Paletten dieser Lauf nimmt, und wann
        v_n := least(v_ziel - v_verarbeitet, 12 + (d.nr + v_lauf) % 8);
        exit when v_n <= 0;
        v_zufall := (hashtext(format('lauf-%s-%s', d.nr, v_lauf))::bigint & 2147483647)::numeric / 2147483647;
        -- Jede Charge kommt zu ihrer Zeit dran: die einen bald nach der Ernte,
        -- die anderen Wochen später — so bleibt bis heute etwas zu tun.
        v_start := (v_anker + (d.kw - 34) * 7 + 12 + (d.nr % 7) * 12 + (v_lauf - 1) * v_abstand + floor(v_zufall * 6)::int)::timestamptz
                   + interval '7 hours' + (d.nr % 3) * interval '30 minutes';
        while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
        exit when v_start > v_jetzt - interval '2 days';

        -- Kein FIFO: ungerade Läufe greifen die jüngsten Paletten, gerade die
        -- ältesten — je nachdem, an welchen Stapel man herankommt.
        select array_agg(id) into v_pal_ids from (
          select id from demo_pal where nr = d.nr and not verarbeitet
           order by case when v_lauf % 2 = 1 then datum end desc,
                    case when v_lauf % 2 = 0 then datum end asc, id
           limit v_n) s;
        update demo_pal set verarbeitet = true where id = any(v_pal_ids);
        select sum(netto), sum(netto * (v_start::date - datum)) / sum(netto)
          into v_masse, v_tage from demo_pal where id = any(v_pal_ids);
        v_verarbeitet := v_verarbeitet + v_n;

        -- Die Fassung: Maschine immer Kaliber; von Hand die 8-kg-Kiste — bis auf
        -- eine Charge, die Migros nach Kaliber will (dort bleibt das Kisten-
        -- gewicht beim Fax unbekannt, und die Auswertung sagt es).
        v_kaeufer := d.kaeufer;
        v_art := case when d.weg = 'maschine' then 'kaliber'
                      when d.nr = 1647 then 'kaliber' else 'kiste' end;
        v_schema := sortierschema_fuer(d.sorte, v_kaeufer, v_start::date, v_art);
        select kaliber_baender into v_baender from sortierschema where id = v_schema;
        if v_art = 'kaliber' and v_baender is null then
          select kaliber_baender into v_baender from sortierschema
           where sorte = d.sorte and art = 'kaliber' and kaeufer is null order by gilt_ab desc limit 1;
        end if;
        v_nb := coalesce(jsonb_array_length(v_baender), 0);

        -- 0060: das Kistensystem steht an der Arbeit — von Hand „Kiste ab 8 kg"
        -- oder Stück-Kisten eines Kalibers; die Sortiermaschine fragt nicht.
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaeufer, sortierschema_id, bemerkung,
                             geplante_paletten, kistensystem, soll_kg_pro_kiste, stueck_je_kiste)
        values (case when d.weg = 'maschine' then 'maschine' else 'hand' end::verarbeitungsweg,
                case when d.weg = 'maschine' then 'sortieren' else 'waschen_sortieren' end::station,
                d.nr, v_start,
                v_start + make_interval(mins => (240 + v_n * 14 + floor(v_zufall * 40)::int)),
                'abgeschlossen', v_kaeufer, v_schema, 'DEMO', v_n,
                case when d.weg = 'maschine' then null when v_art = 'kiste' then 'kiste_ab' else 'stueck' end,
                case when d.weg <> 'maschine' and v_art = 'kiste' then 8 end,
                case when d.weg <> 'maschine' and v_art = 'kaliber' then greatest(round(d.kg_kiste * 1000 / d.gramm)::int, 1) end)
        returning id into v_auftrag;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_auftrag, id from profil order by erstellt_ts limit (2 + (v_lauf % 2))
        on conflict do nothing;

        -- Paletten zählen — mit dem Datum vom Zettel; beim Waschen + Sortieren
        -- auch mit dem Gewicht vom Zettel (0060), damit der Palox einen Nenner hat.
        -- 0076: die Maske lässt die Palette aus der Liste greifen — dann steht
        -- sie mit ihrer Nummer da und die Masse ist exakt bekannt. Jede dritte
        -- Arbeit tippt stattdessen nur das Zetteldatum ab; dort bleibt die
        -- Masse ein Mittel. Beides kommt vor, und die Herkunftsspalte im
        -- Dashboard soll beides zeigen.
        -- 0072: in welchem Gebinde die Palette steht, wird gefragt — meistens
        -- G2, manchmal IFCO.
        insert into auftrag_palette (auftrag_id, palette_id, eingangsdatum, ts, brutto_zettel_kg, gebindeart)
        select v_auftrag,
               case when (d.nr + v_lauf) % 3 <> 0 then dp.id end,
               dp.datum, v_start + make_interval(mins => (10 + row_number() over (order by dp.id) * 12)::int),
               case when d.weg <> 'maschine' then (select pl.brutto_kg from palette pl where pl.id = dp.id) end,
               (select pl.gebindeart from palette pl where pl.id = dp.id)
          from demo_pal dp where dp.id = any(v_pal_ids);

        -- Verderb bis heute: Weibull je Sorte plus Sockel, mit Streuung je Lauf
        v_f := 1 - exp(-power(v_tage / d.lambda, d.k));
        v_schimmel := round(v_masse * power(1 - d.r, v_tage) * (d.sockel + v_f) * (0.8 + 0.4 * v_zufall));
        insert into schimmel_messung (auftrag_id, kg, ts) values (v_auftrag, greatest(v_schimmel, 1)::int, v_start + interval '5 hours');
        insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

        if d.weg = 'maschine' then
          -- ---- Die Sortier-CSV: was am Band ankommt, jeder Kürbis gewogen ----
          -- Masse am Band = Eingang − Verdunstung − Faules; das Gewicht je
          -- Kürbis ist mit der Lagerdauer entsprechend kleiner.
          v_x := v_masse * power(1 - d.r, v_tage) - v_schimmel;
          v_gramm := d.gramm * power(1 - d.r, v_tage);
          v_n := greatest(round(v_x * 1000 / v_gramm)::int, 50);
          -- Glockenförmig in 10-g-Stufen von −3σ bis +3σ, plus ein leichter
          -- zweiter Gipfel bei manchen Schlägen (ungleiche Reife).
          select jsonb_agg(jsonb_build_array(g, anz)) into v_hist from (
            select g, greatest(round(v_n * 10 * (
                     exp(-power((g - v_gramm) / d.sd, 2) / 2) / (d.sd * 2.5066)
                     + case when d.nr % 5 = 0 then 0.35 * exp(-power((g - v_gramm * 1.45) / (d.sd * 0.6), 2) / 2) / (d.sd * 0.6 * 2.5066) else 0 end
                   ))::int, 0) as anz
              from generate_series(greatest(round((v_gramm - 3 * d.sd) / 10) * 10, 100)::int,
                                   round((v_gramm + 3.5 * d.sd) / 10)::int * 10, 10) g) h
           where anz > 0;
          perform csv_lauf_speichern(
            d.nr, format('DEMO-%s-%s', d.nr, to_char(v_start, 'DD-MM-HH24-MI')),
            format('demo/sortierdateien/%s-%s.csv', d.nr, to_char(v_start, 'YYYYMMDD')),
            format('demo-pruefsumme-%s', v_auftrag),
            v_start + interval '90 minutes', 'dateiname',
            '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
            (v_n * 1.03)::int, 2 + v_lauf % 3, 5 + v_lauf % 7, (v_n * 0.02)::int, v_hist);

          -- Kisten je Kaliber gezählt: Masse des Bands durch das Kistengewicht
          v_kisten := array[]::int[];
          for v_i in 0 .. v_nb - 1 loop
            select coalesce(sum((e->>1)::numeric * (e->>0)::numeric), 0) / 1000 into v_kg_band
              from jsonb_array_elements(v_hist) e
             where (e->>0)::int >= (v_baender->v_i->>0)::int and (e->>0)::int < (v_baender->v_i->>1)::int;
            v_kisten := v_kisten || greatest(round(v_kg_band / (d.kg_kiste * (0.97 + 0.06 * v_zufall)))::int, 0);
          end loop;
          insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
          select v_auftrag, i - 1, v_kisten[i] from generate_series(1, v_nb) i where v_kisten[i] > 0
          on conflict (auftrag_id, kaliber_idx, sortierdatum) do nothing;
          insert into demo_lauf values (v_auftrag, d.nr, d.sorte, v_start, v_x, v_tage, 'kaliber', v_kaeufer, v_baender, d.kg_kiste, v_kisten);
        else
          -- ---- Von Hand: eine Palette gewogen, Ausschuss gewogen, fertige Palette ----
          select p2.* into p from demo_pal p2 where p2.id = v_pal_ids[1];
          v_wiegung := null;
          v_brutto := p.netto + p.kisten * 1.5 + 25;
          -- 0076: die gewogene Palette ist bekannt, nicht nur ihr Eingangstag.
          -- Jede vierte Wägung sagt ausserdem, wie viel davon faul war — der
          -- einzige Schimmelwert, dessen Palette nicht nach dem Aussehen
          -- ausgewählt wurde.
          insert into verdunstung_wiegung (auftrag_id, charge_nr, palette_id, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                           kisten, gebindeart, kuerbisse_pro_kiste, faul_kg, wiege_ts)
          values (v_auftrag, d.nr, p.id, p.datum, v_brutto,
                  round((p.netto * power(1 - d.r * (0.7 + 0.6 * v_zufall), v_start::date - p.datum) + p.kisten * 1.5 + 25) * 2) / 2.0,
                  p.kisten, 'G2', 4 + (d.nr % 3),
                  case when v_lauf % 4 = 0 then round(p.netto * (0.004 + 0.02 * v_zufall), 1) end,
                  v_start + interval '2 hours')
          returning id into v_wiegung;
          -- Die Wägung gehört zu der gezählten Palette mit demselben Zetteldatum —
          -- sonst zählte die Kohortenrechnung sie einem anderen Eingangstag zu.
          update auftrag_palette set wiegung_id = v_wiegung
           where id = (select min(id) from auftrag_palette
                        where auftrag_id = v_auftrag and eingangsdatum = p.datum);

          v_x := v_masse * power(1 - d.r, v_tage) - v_schimmel;
          v_klein := round(v_x * (0.025 + 0.02 * v_zufall));
          v_gross := round(v_x * (0.010 + 0.015 * (1 - v_zufall)));
          v_kisten_p := greatest(ceil(v_klein / 22.0), 1)::int;
          insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart, ts, bemerkung)
          values (v_auftrag, 'zu_klein', v_klein + v_kisten_p * 1.5 + 25, v_kisten_p, 'G2', v_start + interval '6 hours',
                  case when v_lauf % 6 = 0 then 'Viel Kleines in dieser Charge' end);
          if v_lauf % 3 = 0 then
            -- Einmal nicht gewogen, nur geschätzt — das zeigt die Datenqualität.
            insert into ausschuss_messung (auftrag_id, art, kg, ts) values (v_auftrag, 'zu_gross', v_gross::int, v_start + interval '6 hours');
          else
            v_kisten_p := greatest(ceil(v_gross / 22.0), 1)::int;
            insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart, ts)
            values (v_auftrag, 'zu_gross', v_gross + v_kisten_p * 1.5 + 25, v_kisten_p, 'G2', v_start + interval '6 hours');
          end if;
          insert into auftrag_angabe (auftrag_id, schluessel, wert)
          values (v_auftrag, 'ausschuss_leer', 'true'), (v_auftrag, 'ausschuss_von_auftrag', 'true');

          -- Fertige Paletten: bei „Kiste ab 8 kg" überfüllt (8.2–8.6), nach
          -- Kaliber ohne Soll — dort zählt nur das Kistengewicht.
          v_kg_band := case when v_art = 'kiste' then 8.15 + 0.45 * v_zufall else 11.5 + 1.5 * v_zufall end;
          for v_i in 1 .. 2 loop
            insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, kuerbisse_pro_kiste, ts)
            values (v_auftrag, d.nr, round((32 * (v_kg_band + 0.05 * v_i) + 32 * 1.5 + 25) * 2) / 2.0, 32, 'G2',
                    case when v_art = 'kiste' then 5 + (d.nr % 2) else null end,
                    v_start + make_interval(hours => 3 + v_i));
          end loop;
          -- Für das Fax: die Masse in Kisten (−1 = Kiste nach Soll, sonst Bänder gleich verteilt)
          v_kisten := array[]::int[];
          if v_art = 'kiste' then
            v_kisten := array[greatest(round((v_x - v_klein - v_gross) / v_kg_band)::int, 1)];
          else
            for v_i in 0 .. v_nb - 1 loop
              v_kisten := v_kisten || greatest(round((v_x - v_klein - v_gross) / v_nb / v_kg_band)::int, 0);
            end loop;
          end if;
          -- 0072: „die fertigen paletten werden eher nicht gezählt" — aber
          -- wenn doch, ist die Ausgangsmasse der Arbeit bekannt statt nur
          -- geschätzt. Zwei von drei Arbeiten zählen sie.
          if v_lauf % 3 <> 0 then
            update auftrag set fertige_paletten_gesamt =
                   greatest(ceil((v_x - v_klein - v_gross) / (32 * v_kg_band))::int, 1)
             where id = v_auftrag;
          end if;
          insert into demo_lauf values (v_auftrag, d.nr, d.sorte, v_start, v_x - v_klein - v_gross, v_tage, v_art, v_kaeufer, v_baender, v_kg_band, v_kisten);
        end if;
      end loop;
    end loop;
    raise notice 'Demo: Sortieren und Waschen + Sortieren angelegt (% Arbeiten)', (select count(*) from demo_lauf);
  end;

  -- ---------- 3. Waschen je Kaliber, Wochen später (Weg 1) ------------------
  -- Aus jedem Sortierlauf werden die Bänder nacheinander gewaschen: die
  -- gefüllten Kisten geleert, Palox abgelesen (Schimmel #2, klein), eine
  -- fertige Palette gewogen. Nicht jedes Band ist schon dran — was wartet,
  -- steht in der Auswertung als „wartet aufs Waschen".
  declare l record; v_i int; v_start timestamptz; v_neu bigint; v_zufall numeric; v_kg numeric; v_kisten int;
          v_anteil numeric; v_gewaschen int[]; v_zufall2 numeric;
          v_eigen boolean; v_ohne_pal boolean; v_von int; v_bis int;
  begin
    for l in select * from demo_lauf where art = 'kaliber' and exists (select 1 from auftrag a where a.id = demo_lauf.auftrag_id and a.station = 'sortieren') order by start_ts loop
      v_gewaschen := array[]::int[];
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_zufall := (hashtext(format('wasch-%s-%s-%s', l.nr, l.start_ts::date, v_i))::bigint & 2147483647)::numeric / 2147483647;
        -- Das letzte Band der späten Läufe wartet noch
        if l.kisten[v_i] = 0 or (v_i = array_length(l.kisten, 1) and l.start_ts > v_jetzt - interval '60 days') then
          v_gewaschen := v_gewaschen || 0; continue;
        end if;
        v_start := l.start_ts + make_interval(days => 6 + v_i * 5 + floor(v_zufall * 25)::int) + interval '1 hour';
        while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
        if v_start > v_jetzt - interval '1 day' then v_gewaschen := v_gewaschen || 0; continue; end if;
        v_kisten := l.kisten[v_i];
        -- 0054: manchmal nennt das Etikett kein Band der Fassung, sondern ein
        -- eigenes Kaliber — „ab 900 g" statt „Band 2". Dann steht die Grenze
        -- an der Arbeit und der Bandindex bleibt leer.
        v_eigen := (l.nr + v_i) % 13 = 0 and l.baender is not null
                   and jsonb_array_length(l.baender) > v_i - 1;
        if v_eigen then
          v_von := (l.baender->(v_i - 1)->>0)::int + 50;
          v_bis := (l.baender->(v_i - 1)->>1)::int - 50;
          if v_bis <= v_von then v_eigen := false; end if;
        end if;
        -- Auf Weg 1 sind die Eingangspaletten beim Waschen längst in
        -- Kaliberkisten aufgelöst. Meistens zählt der Vorarbeiter die
        -- Zwischenlager-Paletten; jede vierte Arbeit kann das nicht und gibt
        -- stattdessen die verarbeitete Menge an — sonst hätte der dort
        -- gemessene Schimmel keinen Nenner. Beim eigenen Kaliber ist das
        -- immer so: dort kennt niemand das Gewicht einer Kiste, weil dieses
        -- Band beim Sortieren nie gezählt wurde. Gemessen, bevor das hier
        -- stand: fünf Waschgänge meldeten „die Messung hat keinen Nenner" —
        -- richtig gerechnet, aber in einer Demo unnötig.
        v_ohne_pal := (l.nr + v_i + extract(day from l.start_ts)::int) % 4 = 0 or v_eigen;
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx, sortierschema_id, bemerkung,
                             kistensystem, stueck_je_kiste, kaliber_von_g, kaliber_bis_g, durchsatz_kg, geplante_paletten)
        values ('maschine', 'waschen', l.nr, v_start,
                v_start + make_interval(mins => 90 + v_kisten * 5 + floor(v_zufall * 30)::int),
                'abgeschlossen', case when v_eigen then null else v_i - 1 end,
                (select sortierschema_id from auftrag where id = l.auftrag_id), 'DEMO',
                'stueck', greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1),
                case when v_eigen then v_von end, case when v_eigen then v_bis end,
                case when v_ohne_pal then round(v_kisten * l.kg_je_kiste) end,
                case when v_ohne_pal then null else ceil(v_kisten / 32.0)::int end)
        returning id into v_neu;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_neu, id from profil order by erstellt_ts limit 2 on conflict do nothing;
        -- Q22, Schichtwechsel: an langen Waschgängen geht einer um vier Uhr
        -- und ein anderer übernimmt. Wer gegangen ist, steht mit seiner Zeit da.
        if v_kisten > 120 then
          update auftrag_teilnehmer set verlassen_ts = v_start + interval '4 hours'
           where auftrag_id = v_neu
             and profil_id = (select profil_id from auftrag_teilnehmer where auftrag_id = v_neu order by profil_id limit 1);
          insert into auftrag_teilnehmer (auftrag_id, profil_id, beigetreten_ts)
          select v_neu, id, v_start + interval '4 hours' from profil
           where id not in (select profil_id from auftrag_teilnehmer where auftrag_id = v_neu)
           order by erstellt_ts limit 1
          on conflict do nothing;
        end if;
        -- 0061: beim Waschen werden Paletten gezählt — das Sortierdatum vom
        -- Zettel und die Kisten je Palette (höchstens 32), so wie die Maske.
        if not v_ohne_pal then
          -- 0104: Seit Mitte August wiegt die Demo-Halle jede Wasch-Palette am
          -- Anfang der Strasse (die Regel des Betriebs vom 29. September; die
          -- Demo zeigt, was die App kann). Brutto = Palette + Kisten × (Tara +
          -- Kistengewicht der Charge, leicht streuend). Ältere Waschgänge
          -- bleiben ungewogen — für sie gelten die Ersätze.
          insert into auftrag_palette (auftrag_id, sortierdatum, kisten, gebindeart, brutto_gewogen_kg)
          select v_neu, l.start_ts::date, x.kisten, x.art,
                 case when v_start::date >= current_date - 45
                      then round(g.tara_kg_palette + x.kisten * (g.tara_kg_pro_kiste
                                 + l.kg_je_kiste * (0.96 + 0.08 * ((hashtext(format('waage-%s-%s', l.nr, s))::bigint & 2147483647)::numeric / 2147483647))), 1)
                 end
            from generate_series(1, ceil(v_kisten / 32.0)::int) s
            cross join lateral (select least(32, v_kisten - (s - 1) * 32) as kisten,
                                       case when s % 5 = 0 then 'IFCO 6416' else 'G2' end as art) x
            join gebinde g on g.art = x.art;
        end if;
        -- Schimmel #2: was seit dem Sortieren in der Kiste dazukam. Der Verderb
        -- geht in der Kiste weiter, nach derselben Kurve — bedingt auf das, was
        -- beim Sortieren noch gut war: (F(t_wasch) − F(t_sort)) / (1 − F(t_sort)).
        v_kg := v_kisten * l.kg_je_kiste;
        select d2.lambda, d2.k into v_anteil, v_zufall2 from demo_charge d2 where d2.nr = l.nr;
        v_anteil := greatest(
          ((1 - exp(-power((l.alter_tage + (v_start::date - l.start_ts::date)) / v_anteil, v_zufall2)))
           - (1 - exp(-power(l.alter_tage / v_anteil, v_zufall2))))
          / (exp(-power(l.alter_tage / v_anteil, v_zufall2))), 0.002);
        insert into schimmel_messung (auftrag_id, kg, ts)
        values (v_neu, greatest(round(v_kg * v_anteil * (0.75 + 0.5 * v_zufall)), 1)::int, v_start + interval '3 hours');
        insert into auftrag_angabe (auftrag_id, schluessel, wert)
        values (v_neu, 'eine_charge', 'true');
        -- Fertige Palette nach Kaliber: kein Soll, nur das Kistengewicht
        insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, ts, kaliber_idx, kuerbisse_pro_kiste, bemerkung)
        values (v_neu, l.nr, round((32 * l.kg_je_kiste * (0.96 + 0.08 * v_zufall) + 32 * 1.5 + 25) * 2) / 2.0, 32, 'G2',
                v_start + interval '2 hours', case when v_eigen then null else v_i - 1 end,
                greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1),
                case when v_eigen then format('Eigenes Kaliber %s–%s g', v_von, v_bis) end);
        -- Wie viele fertige Paletten am Ende dastanden. Ohne diese Zahl kennt
        -- die App nur die *gewogene* — die Ausgangsmasse wäre unbekannt.
        if (l.nr + v_i) % 3 <> 0 then
          update auftrag set fertige_paletten_gesamt = greatest(ceil(v_kisten / 32.0)::int, 1) where id = v_neu;
        end if;
        v_gewaschen := v_gewaschen || v_kisten;
      end loop;
      update demo_lauf set kisten = v_gewaschen where auftrag_id = l.auftrag_id;
    end loop;
    raise notice 'Demo: Waschgänge angelegt';
  end;

  -- ---------- 4. Fax und Lieferungen ----------------------------------------
  -- Nach dem Waschen steht die Ware in Kisten, bis eine Bestellung kommt. Das
  -- Fax macht daraus Paletten mit Etikett und sortiert dabei Faules aus —
  -- gewogen, kistenweise. Was gemacht wird, geht innert Tagen raus. Die
  -- Lieferungen einer Charge verteilen sich so über Wochen und verschränken
  -- sich mit denen anderer Chargen.
  declare l record; v_i int; v_start timestamptz; v_neu bigint; v_zufall numeric; v_kisten int; v_rest int;
          v_teil int; v_masse numeric; v_faul numeric; v_n_faul int; v_j int; v_kaeufer text; v_kunde text;
          v_lief numeric; v_schema bigint;
          -- 0061: die Verkaufsdatei zur Lieferung
          v_pos int := 0; v_lief_id bigint; v_lief_datum date; v_einheit text; v_inhalt int;
          v_gja numeric; v_menge numeric; v_stueck int; v_artikel text; v_artikel_id text;
  begin
    -- Die Warenwirtschaft der Demo: jede Lieferung steht auch als Zeile einer
    -- Verkaufsdatei da (Einheit, Gebindeinhalt, Kisten je Chargenzeile), so wie
    -- sie der Import aus dem Perigon anlegt. Daraus die verkauften Kisten.
    insert into ausgang_quelle (code, name, dateiname_muster, bemerkung)
    values ('DEMO', 'Demo-Warenwirtschaft', 'demo', 'DEMO') on conflict (code) do nothing;
    for l in select * from demo_lauf order by start_ts loop
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_rest := l.kisten[v_i];
        if v_rest <= 0 then continue; end if;
        v_j := 0;
        while v_rest > 0 loop
          v_j := v_j + 1;
          exit when v_j > 4;
          v_zufall := (hashtext(format('fax-%s-%s-%s-%s', l.nr, l.start_ts::date, v_i, v_j))::bigint & 2147483647)::numeric / 2147483647;
          -- Ein Teil der Ware wartet noch auf eine Bestellung
          if v_zufall < 0.12 then exit; end if;
          v_teil := least(v_rest, 32 * (1 + floor(v_zufall * 4)::int) + floor(v_zufall * 20)::int);
          v_start := l.start_ts + make_interval(days => 20 + v_i * 6 + v_j * 9 + floor(v_zufall * 12)::int) + interval '2 hours';
          while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
          exit when v_start > v_jetzt - interval '1 day';
          v_kaeufer := case when v_j % 3 = 0 then (case l.kaeufer when 'nordmarkt' then 'talhof' when 'talhof' then 'nordmarkt' when 'gruenwerk' then 'feldfrisch' else 'gruenwerk' end) else l.kaeufer end;
          v_schema := case when l.art = 'kiste' then sortierschema_fuer(l.sorte, l.kaeufer, v_start::date, 'kiste') else null end;
          -- 0060: die Palettenzahl als Gesamtzahl, die Tage seit dem Waschen, das
          -- Kistensystem. Jede zweite Fax-Arbeit zählt zusätzlich noch Kisten
          -- (der Weg vor 0060) — beide Wege müssen dieselbe Masse ergeben.
          insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, ende_ts, status, kaeufer, sortierschema_id, bemerkung,
                               kistensystem, soll_kg_pro_kiste, paletten_gesamt, tage_seit_waschen)
          values ('maschine', 'waschen', l.nr, true, v_start,
                  v_start + make_interval(mins => 40 + v_teil * 2 + floor(v_zufall * 25)::int),
                  'abgeschlossen', v_kaeufer, v_schema, 'DEMO',
                  case when l.art = 'kiste' then 'kiste_ab' else 'stueck' end,
                  case when l.art = 'kiste' then 8 end,
                  ceil(v_teil / 32.0)::int,
                  case when v_j % 3 = 0 then null else 1 + floor(v_zufall * 3)::int end)
          returning id into v_neu;
          insert into auftrag_teilnehmer (auftrag_id, profil_id)
          select v_neu, id from profil order by erstellt_ts limit 1 on conflict do nothing;
          if v_j % 2 = 1 then
            insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
            values (v_neu, case when l.art = 'kiste' then -1 else v_i - 1 end, v_teil);
          end if;
          insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_neu, 'eine_charge', 'true');
          -- Faules: kistenweise gewogen, 1–3 Kisten, Anteil je Sorte mit Streuung.
          -- Jede fünfte Fax-Arbeit hat nichts Faules — auch das ist eine Messung.
          v_masse := v_teil * l.kg_je_kiste;
          v_faul := round(v_masse * (select fax_anteil from demo_charge where nr = l.nr) * (0.4 + 1.2 * v_zufall), 1);
          if v_j % 5 = 0 or v_faul < 1 then
            insert into schimmel_messung (auftrag_id, kg, ts, bemerkung) values (v_neu, 0, v_start + interval '1 hour', 'Nichts Faules');
            v_faul := 0;
          else
            v_n_faul := least(greatest(ceil(v_faul / 9.0)::int, 1), 3);
            insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, mit_palette, ts)
            select v_neu, 0, round(v_faul / v_n_faul + 1.5 + (s - 1) * 0.5, 1), 1, 'G2', false,
                   v_start + make_interval(mins => 30 + s * 20)
              from generate_series(1, v_n_faul) s;
            select coalesce(sum(kg), 0) into v_faul from schimmel_messung where auftrag_id = v_neu;
          end if;
          -- Die Lieferung, wie die Verkaufsdatei sie führt (0061): Kisten × Inhalt,
          -- nominal — „Kiste ab 8 kg" steht mit 8 kg auf dem Lieferschein, die
          -- Stück-Kiste mit Stück × Nenngewicht. Was die Kiste wirklich wiegt,
          -- weiss nur die Waage (Überfüllung). 1–7 Tage nach dem Fax.
          v_lief_datum := (v_start + make_interval(days => 1 + floor(v_zufall * 6)::int))::date;
          v_kunde := case v_kaeufer when 'nordmarkt' then 'Nordmarkt Verteilzentrale' when 'talhof' then 'Talhof Bio AG'
                                    when 'gruenwerk' then 'Grünwerk Handel' else 'Feldfrisch Ost' end;
          v_pos := v_pos + 1;
          if l.art = 'kiste' then
            v_einheit := 'kg'; v_inhalt := 8; v_gja := 1;
            v_artikel := 'Bio Kürbis ' || l.sorte || ' lose'; v_artikel_id := 'kürb' || lower(left(l.sorte, 3));
          else
            v_stueck := greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1);
            v_einheit := 'Stk.'; v_inhalt := v_stueck;
            v_gja := round((select gramm from demo_charge where nr = l.nr) / 1000.0, 2);
            v_artikel := 'Bio Kürbis ' || l.sorte || ' Dem'; v_artikel_id := 'kürb' || lower(left(l.sorte, 3)) || 'd';
          end if;
          v_menge := v_teil * v_inhalt;
          v_lief := round(v_menge * v_gja, 1);
          insert into ausgang_artikel (artikel_id, artikel, ist_kuerbis, sorte, bemerkung)
          values (v_artikel_id, v_artikel, true, l.sorte, 'DEMO') on conflict (artikel_id, artikel) do nothing;
          insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, journal, auftragsnr,
                                     kunde, artikel_id, artikel, einheit, menge, gewicht_je_artikel, batch_menge,
                                     kg_position, kg_charge, gebindeart, gebinde_menge, gebinde_inhalt, batch_gebinde, produzent,
                                     erloes)
          values ('DEMO', v_pos, l.nr::text, 1, 'demo-' || v_pos, v_lief_datum, 'Lieferschein', 'LS-' || (100000 + v_pos),
                  v_kunde, v_artikel_id, v_artikel, v_einheit, v_menge, v_gja, v_menge,
                  v_lief, v_lief, 'IFCO', v_teil, v_inhalt, v_teil, 'Demo-Hof',
                  round(v_lief * (1.55 + 0.5 * v_zufall), 2))
          on conflict (quelle, pos_id, charge_extern, lauf_nr) do nothing;
          insert into lieferung (datum, charge_nr, sorte, kg, kisten, gebindeart, ziel, kunde, bemerkung)
          values (v_lief_datum, l.nr, l.sorte, v_lief, v_teil, 'G2', 'verkauf', v_kunde, 'DEMO')
          returning id into v_lief_id;
          insert into lieferung_import (lieferung_id, quelle, extern_id)
          values (v_lief_id, 'DEMO', format('DEMO:%s:%s:1', v_pos, l.nr));
          v_rest := v_rest - v_teil;
        end loop;
      end loop;
    end loop;
    -- Zu klein geht an die Tiere — als Lieferung mit Ziel Tierfutter, damit die
    -- Bilanz es sieht.
    insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
    select (a.start_ts + interval '3 days')::date, a.charge_nr, c.sorte, sum(m.kg), 'tierfutter', 'Hof Zürcher (Tiere)', 'DEMO'
      from ausschuss_messung m join auftrag a on a.id = m.auftrag_id join charge c on c.nr = a.charge_nr
     where a.bemerkung = 'DEMO' and m.art = 'zu_klein'
     group by a.id, a.start_ts, a.charge_nr, c.sorte;
    -- Und der Hofladen nimmt ab und zu ein paar Kisten
    insert into lieferung (datum, sorte, kisten, ziel, kunde, bemerkung)
    select (v_anker + 40 + i * 11)::date, case when i % 2 = 0 then 'Tiana' else 'Kaori Kuri' end, 6 + i % 5, 'hofladen', 'Hofladen', 'DEMO'
      from generate_series(1, 10) i;
    perform lieferung_import_zeilen_verbinden('DEMO');
    raise notice 'Demo: Fax und Lieferungen angelegt (mit Verkaufsdatei)';
  end;

  -- ---------- 4b. An jeder Station läuft nur eine Arbeit zugleich -----------
  -- Die Arbeiten sind je Charge entstanden; zwei Chargen können so am selben
  -- Tag zur selben Stunde stehen. Im Betrieb geht das nicht (ein Band, ein
  -- Palox je Station) — also rücken sie hintereinander, samt allem, was an
  -- ihnen hängt. Fax hat keinen Palox und läuft nebenher.
  declare v record; v_prev timestamptz; v_station text := ''; v_delta interval;
  begin
    for v in
      select id, palox_station(station)::text as station, start_ts, ende_ts from auftrag
       where bemerkung = 'DEMO' and not ist_fax and status = 'abgeschlossen' and abgebrochen_ts is null
       order by palox_station(station), start_ts, id
    loop
      if v.station <> v_station then v_station := v.station; v_prev := null; end if;
      if v_prev is not null and v.start_ts < v_prev + interval '20 minutes' then
        v_delta := (v_prev + interval '20 minutes') - v.start_ts;
        update auftrag set start_ts = start_ts + v_delta, ende_ts = ende_ts + v_delta where id = v.id;
        update auftrag_palette set ts = ts + v_delta where auftrag_id = v.id;
        update schimmel_messung set ts = ts + v_delta where auftrag_id = v.id;
        update ausschuss_messung set ts = ts + v_delta where auftrag_id = v.id;
        update ausgang_wiegung set ts = ts + v_delta where auftrag_id = v.id;
        update verdunstung_wiegung set wiege_ts = wiege_ts + v_delta where auftrag_id = v.id;
        update sortier_lauf set datei_zeit = datei_zeit + v_delta where auftrag_id = v.id;
        v.ende_ts := v.ende_ts + v_delta;
      end if;
      v_prev := v.ende_ts;
    end loop;
  end;

  -- ---------- 5. Palox-Ablesungen je Arbeit (AB-02) -------------------------
  -- Je Station läuft der Stand über die Arbeiten weiter: eine Ablesung zu
  -- Beginn (Stand unverändert) und eine am Ende. Geleert, wenn er sonst
  -- überliefe. Gespeichert wird der Stand, die Menge folgt daraus. Fax hat
  -- keinen Palox — dort ist das Faule gewogen.
  declare v record; v_stand numeric := 0; v_station text := ''; v_geleert boolean; v_i int := 0;
  begin
    for v in
      select s.id, s.auftrag_id, s.kg, palox_station(a.station)::text as station, a.start_ts, a.ende_ts
        from schimmel_messung s
        join auftrag a on a.id = s.auftrag_id
       where a.bemerkung = 'DEMO' and not a.ist_fax and s.palox_stand_kg is null and s.brutto_kg is null
       order by palox_station(a.station), a.start_ts, s.id
    loop
      v_i := v_i + 1;
      if v.station <> v_station then v_station := v.station; v_stand := palox_tara_kg(); end if;
      -- Zwischen zwei Arbeiten geleert, weil der Palox sonst überliefe. Das
      -- ist der Normalfall, und er kostet seit 0073 keine Messung mehr: die
      -- neue Arbeit beginnt einfach bei der leeren Box und liest ihren
      -- eigenen Anfang ab.
      if v_stand + v.kg > 800 then v_stand := palox_tara_kg(); end if;
      -- Jede 17. Arbeit hat die Ablesung zu Beginn vergessen — die Datenqualität zeigt es.
      if v_i % 17 <> 0 then
        insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert, ts)
        values (v.auftrag_id, 0, v_stand, false, v.start_ts + interval '10 minutes');
      end if;
      -- Jede 23. Arbeit wird MITTENDRIN geleert. Der Betrieb sagt, das kommt
      -- vor. Dann ist die Menge dieser Arbeit unbekannt — nicht null: wie
      -- viel beim Leeren herausging, weiss niemand (0073).
      v_geleert := v_i % 23 = 0;
      if v_geleert
        then v_stand := palox_tara_kg() + round(v.kg * 0.4);
        else v_stand := v_stand + v.kg;
      end if;
      update schimmel_messung
         set palox_stand_kg = v_stand, palox_geleert = v_geleert, ts = coalesce(v.ende_ts, v.start_ts + interval '5 hours') - interval '10 minutes'
       where id = v.id;
      if v_geleert then
        update auftrag set palox_unbekannt = true where id = v.auftrag_id;
      end if;
    end loop;
    raise notice 'Demo: Palox-Ablesungen nachgetragen';
  end;

  -- ---------- 6. Lagerkontrollen --------------------------------------------
  -- Gegriffene Paletten, wie sie der Bildschirm „Palette kontrollieren"
  -- erfasst: Eingangsdatum, Gewicht damals und jetzt, Kisten, Kistenart.
  -- Seit 0061 ohne „davon faul" und ohne Auswahlart — die Kontrolle ist eine
  -- Verdunstungsmessung, nichts weiter.
  declare p record; v_i int := 0; v_tag date; v_tage int; v_zufall numeric; d record;
  begin
    for p in select * from demo_pal where not verarbeitet
              order by (hashtext(format('kontrolle-%s-%s', nr, datum))::bigint & 2147483647), id loop
      v_i := v_i + 1;
      exit when v_i > 24;
      select * into d from demo_charge where nr = p.nr;
      v_zufall := (hashtext('kontr-' || v_i)::bigint & 2147483647)::numeric / 2147483647;
      v_tag := greatest(p.datum + 20, v_anker + 40 + v_i * 6);
      exit when v_tag >= current_date;
      v_tage := v_tag - p.datum;
      -- Wie die Palette gegriffen wurde, entscheidet, ob die Messung für die
      -- Selektionsprüfung taugt: zufällig erreichbar ist die ehrliche Vorgabe,
      -- Mitte-unten ist besser, gezielt („die sieht schlecht aus") ist für den
      -- Vergleich untauglich — und genau das soll die Demo zeigen.
      insert into verdunstung_wiegung (charge_nr, palette_id, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                       kisten, gebindeart, auswahl, faul_kg, wiege_ts, bemerkung)
      values (p.nr, p.id, p.datum, p.netto + p.kisten * 1.5 + 25,
              round((p.netto * power(1 - d.r * (0.8 + 0.4 * v_zufall), v_tage) + p.kisten * 1.5 + 25) * 2) / 2.0,
              p.kisten, 'G2',
              case v_i % 5 when 0 then 'gezielt' when 1 then 'mitte_unten' else 'erreichbar_zufaellig' end,
              case when v_i % 3 <> 0 then round(p.netto * (0.003 + 0.03 * v_zufall), 1) end,
              v_tag::timestamptz + interval '10 hours', 'DEMO-KONTROLLE');
    end loop;
    raise notice 'Demo: Lagerkontrollen angelegt';
  end;

  -- ---------- 6b. Kontrollpaletten: dieselbe Palette immer wieder ----------
  -- Die Lagerkontrolle (Bildschirm „Palette kontrollieren") lebt davon, dass
  -- eine gekennzeichnete Palette über Wochen immer wieder auf dieselbe Waage
  -- kommt. Zwei Wägungen derselben Palette ergeben eine Verdunstungsrate je
  -- Tag, ohne jede Annahme — der sauberste Wert, den der Betrieb hat.
  -- Ohne diesen Abschnitt blieb der ganze Bildschirm in der Demo leer.
  declare pk record; v_kp bigint; v_i int := 0; v_tag date; v_netto numeric;
          v_schimmel boolean; v_zufall numeric; v_j int; v_rate numeric;
  begin
    for pk in
      select dp.id, dp.nr, dp.datum, dp.netto, dp.kisten, dc.r, dc.sorte
        from demo_pal dp join demo_charge dc on dc.nr = dp.nr
       where not dp.verarbeitet
       order by dc.sorte, (hashtext(format('kp-%s-%s', dp.nr, dp.datum))::bigint & 2147483647)
    loop
      -- Je Sorte eine Kontrollpalette, höchstens zwölf.
      continue when exists (select 1 from kontrollpalette k join charge c on c.nr = k.charge_nr
                             where c.sorte = pk.sorte and k.bemerkung = 'DEMO');
      v_i := v_i + 1;
      exit when v_i > 12;
      v_tag := pk.datum + 14 + (pk.nr % 7);
      -- Zu spät angelegt lohnt sich nicht — aber das ist der Grund, diese
      -- Palette zu überspringen, nicht der Grund, aufzuhören.
      if v_tag >= current_date - 30 then v_i := v_i - 1; continue; end if;
      insert into kontrollpalette (charge_nr, palette_id, kennzeichen, standort, angelegt_ts, angelegt_von,
                                   eingangsdatum, brutto_eingang_kg, bemerkung)
      values (pk.nr, pk.id, format('K-%s-%s', pk.nr, chr(64 + v_i)),
              format('Halle %s, Reihe %s', 1 + v_i % 2, 1 + v_i % 6),
              v_tag::timestamptz + interval '9 hours', v_wer,
              pk.datum, round((pk.netto + pk.kisten * 1.5 + 25) * 2) / 2.0, 'DEMO')
      returning id into v_kp;
      -- Alle zwei bis drei Wochen gewogen, bis heute. Die Palette wird
      -- leichter, nie schwerer — und bei einer sieht man am Ende Schimmel,
      -- dann taugt das Paar nicht mehr für die Rate.
      v_j := 0;
      loop
        v_j := v_j + 1;
        v_tag := v_tag + 14 + ((hashtext(format('kpw-%s-%s-%s', pk.nr, pk.datum, v_j))::bigint & 7))::int;
        exit when v_tag >= current_date or v_j > 12;
        v_zufall := (hashtext(format('kpz-%s-%s-%s', pk.nr, pk.datum, v_j))::bigint & 2147483647)::numeric / 2147483647;
        v_netto := pk.netto * power(1 - pk.r * (0.85 + 0.3 * v_zufall), (v_tag - pk.datum));
        v_schimmel := v_i = 3 and v_tag > current_date - 45;
        insert into kontrollpalette_wiegung (kontrollpalette_id, brutto_kg, kisten, gebindeart,
                                             sichtbar_schimmel, erfasser, wiege_ts, ts, bemerkung)
        values (v_kp, round((v_netto + pk.kisten * 1.5 + 25) * 2) / 2.0, pk.kisten, 'G2',
                v_schimmel, v_wer, v_tag::timestamptz + interval '10 hours',
                v_tag::timestamptz + interval '10 hours',
                case when v_schimmel then 'Erste faule Stellen sichtbar'
                     when v_j = 1 then 'Erste Wägung nach dem Einlagern' end);
      end loop;
      -- Eine Kontrollpalette ist inzwischen verarbeitet — sie wird beendet,
      -- statt einfach zu verschwinden.
      if v_i = 5 then
        update kontrollpalette set beendet_ts = (current_date - 12)::timestamptz + interval '11 hours',
               beendet_grund = 'Palette verarbeitet'
         where id = v_kp;
      end if;
    end loop;
    raise notice 'Demo: Kontrollpaletten angelegt (% Stück, % Wägungen)',
      (select count(*) from kontrollpalette where bemerkung = 'DEMO'),
      (select count(*) from kontrollpalette_wiegung);
  end;

  -- ---------- 6c. Die Verkaufsdatei als Datei ------------------------------
  -- Die Zeilen der Warenwirtschaft kommen im Betrieb nicht einzeln, sondern
  -- als Excel-Datei: einmal im Monat hochgeladen, mit Prüfsumme und Zeitraum.
  -- Ohne diesen Abschnitt stand der Warenausgang-Import der Demo ohne eine
  -- einzige Datei da — als wäre die Ware aus dem Nichts gekommen.
  declare m record; v_datei bigint; v_n int; v_korr_monat date;
  begin
    -- Der Monat, dessen Datei ein zweites Mal hochgeladen wurde: der erste
    -- mit mindestens zwei Zeilen. Die Demo hängt am heutigen Datum; fällt
    -- die erste Lieferung ans Monatsende, hat der erste Monat nur eine
    -- Zeile — und eine Datei, die „2 geändert" sagt, während nur eine
    -- Zeile eine Änderungszeit trägt, wäre ein Fehler der Demo (0096).
    select date_trunc('month', datum)::date into v_korr_monat
      from ausgang_zeile where quelle = 'DEMO'
     group by 1 having count(*) >= 2 order by 1 limit 1;
    for m in
      select date_trunc('month', datum)::date as monat, min(datum) as von, max(datum) as bis,
             count(*)::int as n
        from ausgang_zeile where quelle = 'DEMO' group by 1 order by 1
    loop
      insert into ausgang_datei (quelle, dateiname, pruefsumme, n_zeilen, n_kuerbis, n_neu,
                                 n_geaendert, n_unveraendert, von_datum, bis_datum, bemerkung,
                                 hochgeladen_von, ts)
      values ('DEMO', format('Lieferungen_%s.xlsx', to_char(m.monat, 'YYYY-MM')),
              format('demo-datei-%s', to_char(m.monat, 'YYYYMM')),
              m.n + 4, m.n, m.n - (case when m.monat = v_korr_monat then 2 else 0 end),
              case when m.monat = v_korr_monat then 2 else 0 end,
              4, m.von, m.bis, 'DEMO', v_wer,
              (m.bis + 2)::timestamptz + interval '8 hours')
      returning id into v_datei;
      update ausgang_zeile set datei_id = v_datei
       where quelle = 'DEMO' and date_trunc('month', datum)::date = m.monat;
      -- Dieser Monat wurde ein zweites Mal hochgeladen, weil zwei Positionen
      -- in der Warenwirtschaft nachträglich korrigiert worden waren. Die Datei
      -- zählt sie als geändert, und die Zeilen tragen ihre Änderungszeit.
      if v_datei is not null and m.monat = v_korr_monat then
        update ausgang_zeile set geaendert_ts = (m.bis + 9)::timestamptz + interval '8 hours'
         where id in (select id from ausgang_zeile where datei_id = v_datei order by pos_id limit 2);
      end if;
    end loop;
    -- Zwei Abweichungen, wie sie wirklich vorkommen: einmal wurde eine
    -- Lieferung von Hand nachkorrigiert, einmal blieb eine Palette am Rampen-
    -- rand stehen. Der Abgleich „Datei gegen Lieferung" soll in der Demo nicht
    -- leer sein — sonst sieht niemand, dass es ihn gibt.
    -- Sortiert nach Datum, Charge und Menge, nicht nach der laufenden Nummer:
    -- die Nummer ist nach einem Neuaufbau eine andere, das Datum nicht.
    update lieferung set kg = round(kg * 0.94, 1)
     where id in (select l.id from lieferung l join lieferung_import i on i.lieferung_id = l.id
                   where l.bemerkung = 'DEMO' and l.kg > 400
                   order by l.datum, l.charge_nr, l.kg limit 1);
    update lieferung set kg = round(kg * 1.07, 1)
     where id in (select l.id from lieferung l join lieferung_import i on i.lieferung_id = l.id
                   where l.bemerkung = 'DEMO' and l.kg > 400
                   order by l.datum desc, l.charge_nr desc, l.kg desc limit 1);
    raise notice 'Demo: Verkaufsdateien angelegt (%)', (select count(*) from ausgang_datei where bemerkung = 'DEMO');
  end;

  -- ---------- 6d. Ernte abgeschlossen --------------------------------------
  -- Solange die Ernte einer Charge läuft, wandert ihr mittleres Eingangsdatum
  -- mit jeder Palette, und jede Altersangabe trägt den Zusatz „Ernte läuft
  -- noch". Für die früh geernteten Chargen hat der Betrieb längst gesagt, dass
  -- nichts mehr kommt — die späten stehen noch offen. Beides soll man sehen.
  update charge set ernte_abgeschlossen_ts = (
           select max(p.eingangsdatum) + 3 from palette p where p.charge_nr = charge.nr)::timestamptz + interval '18 hours'
   where nr in (select nr from demo_charge where kw <= 37)
     and ernte_abgeschlossen_ts is null
     and exists (select 1 from palette p where p.charge_nr = charge.nr and p.extern_id like 'demo-%');

  -- ---------- 7. Sonderfälle, wie sie in jeder Saison vorkommen -------------
  declare v_auftrag bigint; v_datum date; v_id bigint;
  begin
    -- (1) Eine abgebrochene Arbeit: falsche Charge gewählt
    insert into auftrag (weg, station, charge_nr, start_ts, bemerkung)
    values ('hand', 'waschen_sortieren', 1611, (v_anker + 63)::timestamptz + interval '9 hours', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, datum from demo_pal where nr = 1611 order by id limit 3;
    perform auftrag_abbrechen(v_auftrag, 'Falsche Charge gewählt');

    -- (2) Ein Zahlendreher beim Palox: 4500 statt 450 kg — die Rechnung lässt
    --     ihn aus, die Auffälligkeiten melden ihn ganz oben.
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
    values ('hand', 'waschen_sortieren', 1611, (v_anker + 70)::timestamptz + interval '8 hours',
            (v_anker + 70)::timestamptz + interval '15 hours', 'abgeschlossen', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, datum from demo_pal where nr = 1611 and not verarbeitet order by datum limit 6;
    update demo_pal set verarbeitet = true where id in (select id from demo_pal where nr = 1611 and not verarbeitet order by datum limit 6);
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 4500, 4545, (v_anker + 70)::timestamptz + interval '14 hours');
    insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

    -- (3) Ein Zetteldatum, das zu keiner Palette passt (12 und 21 vertauscht)
    select datum into v_datum from demo_pal where nr = 1613 order by datum limit 1;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select a.id, v_datum + 9 from auftrag a where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
     order by a.start_ts limit 1;

    -- (4) Ein Waschgang ohne gezählte Kisten: die Messung hat keinen Nenner
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx, bemerkung)
    values ('maschine', 'waschen', 1614, (v_anker + 95)::timestamptz + interval '8 hours',
            (v_anker + 95)::timestamptz + interval '11 hours', 'abgeschlossen', 1, 'DEMO')
    returning id into v_auftrag;
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 9, 300, (v_anker + 95)::timestamptz + interval '10 hours');

    -- (5) Eine Sortier-CSV, die keiner Arbeit zugeordnet ist (Warteschlange)
    perform csv_lauf_speichern(1619, 'DEMO-1619-ohne-arbeit', 'demo/sortierdateien/1619-ohne-arbeit.csv',
      'demo-pruefsumme-warteschlange',
      (v_anker + 130)::timestamptz + interval '13 hours', 'dateiname',
      '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
      420, 1, 3, 6,
      '[[800,40],[900,90],[1000,120],[1100,100],[1200,50],[1300,10]]'::jsonb);

    -- (6) Drei laufende Arbeiten von heute — damit die Masken nicht leer sind
    insert into auftrag (weg, station, charge_nr, start_ts, status, kaeufer, sortierschema_id, bemerkung,
                         kistensystem, soll_kg_pro_kiste)
    values ('hand', 'waschen_sortieren', 1631, now() - interval '2 hours', 'offen', 'nordmarkt',
            sortierschema_fuer('Mieluna', null, current_date, 'kiste'), 'DEMO', 'kiste_ab', 8)
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg)
    select v_auftrag, dp.datum, (select pl.brutto_kg from palette pl where pl.id = dp.id)
      from demo_pal dp where dp.nr = 1631 and not dp.verarbeitet order by dp.datum desc limit 3;
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 0, 45, now() - interval '110 minutes');

    insert into auftrag (weg, station, charge_nr, start_ts, status, kaliber_idx, bemerkung)
    select 'maschine', 'waschen', l.nr, now() - interval '90 minutes', 'offen', 0, 'DEMO'
      from demo_lauf l join auftrag a on a.id = l.auftrag_id
     where a.station = 'sortieren' and l.kisten[1] > 0 order by l.start_ts desc limit 1
    returning id into v_auftrag;
    if v_auftrag is not null then
      update auftrag set kistensystem = 'stueck', stueck_je_kiste = 6 where id = v_auftrag;
      insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl, sortierdatum) values (v_auftrag, 0, 6, current_date - 21);
    end if;

    insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, status, kaeufer, bemerkung)
    select 'maschine', 'waschen', l.nr, true, now() - interval '50 minutes', 'offen', 'talhof', 'DEMO'
      from demo_lauf l join auftrag a on a.id = l.auftrag_id
     where a.station = 'sortieren' order by l.start_ts limit 1
    returning id into v_auftrag;
    if v_auftrag is not null then
      update auftrag set kistensystem = 'stueck', stueck_je_kiste = 6 where id = v_auftrag;
      insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, ts)
      values (v_auftrag, 0, 8.5, 1, 'G2', now() - interval '20 minutes');
    end if;

    -- (7) Ein Palox, der zwischendurch geleert wurde, ohne dass jemand abgelesen
    --     hat: der Stand fällt von 410 auf 130. Die Menge dieser Arbeit ist
    --     unbekannt (0060) — die Auswertung sagt es, der Arbeiter wird nicht gefragt.
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, kistensystem, soll_kg_pro_kiste)
    values ('hand', 'waschen_sortieren', 1613, (v_anker + 118)::timestamptz + interval '8 hours',
            (v_anker + 118)::timestamptz + interval '14 hours', 'abgeschlossen', 'DEMO', 'kiste_ab', 8)
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg)
    select v_auftrag, dp.datum, (select pl.brutto_kg from palette pl where pl.id = dp.id)
      from demo_pal dp where dp.nr = 1613 and not dp.verarbeitet order by dp.datum limit 4;
    update demo_pal set verarbeitet = true where id in (select id from demo_pal where nr = 1613 and not verarbeitet order by datum limit 4);
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts)
    values (v_auftrag, 0, 410, (v_anker + 118)::timestamptz + interval '8 hours 10 minutes'),
           (v_auftrag, 0, 130, (v_anker + 118)::timestamptz + interval '13 hours 50 minutes');
    insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

    raise notice 'Demo: Sonderfälle und laufende Arbeiten angelegt';
  end;

  -- ---------- 8. Beteiligte an den laufenden Arbeiten ------------------------
  insert into auftrag_teilnehmer (auftrag_id, profil_id)
  select a.id, v_wer from auftrag a where a.bemerkung = 'DEMO' and a.status = 'offen'
  on conflict do nothing;

  -- ---------- 9. Rückmeldungen aus der Halle (0091, 0093, 0094) --------------
  -- Geschrieben, nicht gesprochen: Eine Aufnahme wäre eine Datei im Bucket,
  -- und die kann eine SQL-Funktion nicht anlegen. Jede Rückmeldung steht kurz
  -- nach dem Ende der Arbeit bei einer Person, die daran beteiligt war — die
  -- Arbeit aus Sonderfall 7 hat keine Beteiligten, dort ist es der
  -- Betriebsleiter selbst. Und sie steht an Arbeiten, an denen man sie im
  -- Dashboard auch findet.
  --
  -- 0094: Was die Halle sagt, ist die halbe Geschichte; was das Dashboard
  -- zeigt, ist die Kurzfassung, die jemand daraus gemacht hat — die Runde am
  -- Programm oder der Betriebsleiter. Drei der vier zur Ware sind gekürzt;
  -- die vierte ist noch nicht gelesen und steht darum noch nirgends.
  declare v_a1 bigint; v_a2 bigint; v_a3 bigint; v_a4 bigint;
  begin
    -- (1) Zur Ware, an der Sortier-Arbeit der Charge 1628 (Hagel auf dem
    --     hinteren Feld) mit dem meisten Faulen — fest an der Charge, denn die
    --     Demo hängt am Datum, und „die Arbeit mit dem meisten Faulen" wechselt
    --     sonst über Nacht die Charge (Runde AI, Prüfblock 0093 am 29. 9.).
    select a.id into v_a1
      from auftrag a join schimmel_messung s on s.auftrag_id = a.id
     where a.bemerkung = 'DEMO' and a.status = 'abgeschlossen' and a.station = 'sortieren' and a.charge_nr = 1628
     order by s.kg desc, a.id limit 1;
    -- (2) Zur Ware, an der Arbeit mit dem falschen Zetteldatum (Sonderfall 3):
    --     die Auffälligkeit zeigt die Kurzfassung mit an.
    select a.id into v_a2 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
     order by a.start_ts limit 1;
    -- (3) Zur Ware und (4) zur App, an der Arbeit, deren Palox zwischendurch
    --     geleert wurde (Sonderfall 7): beide Arten an einer Arbeit, wie es
    --     das Arbeitsfenster und Betrieb → Arbeiten zeigen.
    select a.id into v_a3 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
       and exists (select 1 from schimmel_messung s where s.auftrag_id = a.id and s.palox_stand_kg = 410)
     order by a.start_ts limit 1;
    -- (5) Zur Ware, noch nicht gelesen: an der ersten Wasch+Sortier-Arbeit
    --     der Charge 1636 — unter Betrieb → Arbeiten wartet sie auf ihre
    --     Kurzfassung, im Dashboard steht sie noch nicht.
    select a.id into v_a4 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1636 and a.station = 'waschen_sortieren' and a.status = 'abgeschlossen'
     order by a.start_ts limit 1;
    if v_a1 is null or v_a2 is null or v_a3 is null or v_a4 is null then
      raise exception 'Demo: die Arbeiten für die Rückmeldungen fehlen — die Saison oben hat sich geändert.';
    end if;
    insert into auftrag_rueckmeldung (auftrag_id, art, text, erfasser, ts, kurz, kurz_quelle, kurz_ts)
    select r.auftrag_id, r.art, r.text,
           coalesce((select t.profil_id from auftrag_teilnehmer t
                      where t.auftrag_id = r.auftrag_id order by t.profil_id limit 1), v_wer),
           coalesce(a.ende_ts, a.start_ts) + make_interval(mins => 3 * r.nr),
           r.kurz, r.quelle,
           case when r.kurz is not null then coalesce(a.ende_ts, a.start_ts) + make_interval(days => 1, hours => 8) end
      from (values
              (1, v_a1, 'ware',
               'Also am Anfang habe ich gedacht, das ist normal, aber dann waren so viele mit Dellen und Rissen, '
               'ich glaube das war der Hagel im Juli auf dem hinteren Feld, darum haben wir so viel weggeworfen.',
               'Hagelschaden', 'runde'),
              (2, v_a2, 'ware',
               'Der Zettel war nass, das Datum konnte man kaum lesen, ich habe 13. geschrieben, kann auch 31. gewesen sein.',
               'Zettel nass, Datum unsicher', 'betriebsleiter'),
              (3, v_a3, 'ware',
               'Sehr viel Faules, der Palox war randvoll — wir haben ihn zwischendurch geleert.',
               'Viel Faules, Palox zwischendurch geleert', 'runde'),
              (4, v_a3, 'app',
               'Wo trage ich ein, dass der Palox geleert wurde? Ich habe es nicht gefunden.',
               null, null),
              (5, v_a4, 'ware',
               'Die Kürbisse waren viel kleiner als sonst, fast alles K1, und ein paar mit weichen Stellen.',
               null, null)
           ) as r(nr, auftrag_id, art, text, kurz, quelle)
      join auftrag a on a.id = r.auftrag_id
     order by r.nr;
    raise notice 'Demo: Rückmeldungen aus der Halle angelegt (drei gekürzt, eine ungelesen, eine zur App)';
  end;

  -- ---------- 7. Runde AS (0116): Hagel, Ausreisser, Kunden, ein Plan ----
  -- Was die Runde neu kann, kommt in der Demo vor (0081 b): ein Hagelschaden
  -- an der Charge, deren Arbeit die Halle mit „Hagelschaden" gemeldet hat;
  -- der randvolle Palox als von Hand ausgeschlossener Ausreisser, dazu eine
  -- Verdunstungs-Wägung; zwei Kunden in einer Gruppe; ein Plan; und eine
  -- Perigon-Zeile, deren Artikel einer anderen Gruppe ist als die Sorte
  -- ihrer Charge.
  declare v_ch int; v_a bigint; v_w bigint; v_saison int; v_z bigint;
  begin
    select a.charge_nr into v_ch from auftrag_rueckmeldung r join auftrag a on a.id = r.auftrag_id
     where a.bemerkung = 'DEMO' and r.kurz = 'Hagelschaden' order by a.start_ts limit 1;
    update charge set hagel_anteil = 0.20, hagel_ts = v_jetzt where nr = v_ch;
    -- Der Ausreisser: die späte Sortier-Arbeit der Charge 1630, der höchste
    -- Palox-Anteil der Demo (rund 14 %) — ein Messpunkt, der sonst zählte.
    select a.id into v_a from auftrag a
     where a.bemerkung = 'DEMO' and a.station = 'sortieren' and a.charge_nr = 1630
     order by a.start_ts desc limit 1;
    if v_a is not null then
      insert into messung_ausschluss (art, bezug_id, grund, erfasser, ts)
      values ('palox', v_a, 'DEMO — Palox randvoll, viele zu kleine darin: nicht typisch', v_wer, v_jetzt)
      on conflict do nothing;
    end if;
    select w.id into v_w from verdunstung_wiegung w join auftrag a on a.id = w.auftrag_id
     where a.bemerkung = 'DEMO' and w.gemessen order by w.wiege_ts desc, w.id desc limit 1;
    if v_w is not null then
      insert into messung_ausschluss (art, bezug_id, grund, erfasser, ts)
      values ('verdunstung', v_w, 'DEMO — Ausreisser', v_wer, v_jetzt)
      on conflict do nothing;
    end if;
    insert into kunde_gruppe (kunde, gruppe, erfasser, ts)
    values ('Nordmarkt Verteilzentrale', 'Grosshandel', v_wer, v_jetzt), ('Feldfrisch Ost', 'Grosshandel', v_wer, v_jetzt)
    on conflict (kunde) do nothing;
    select saison_von(max(datum)) into v_saison from ausgang_zeile where quelle = 'DEMO';
    insert into kunde_plan (saison, kunde, artikelgruppe, groesse, label, kg, erfasser, ts)
    select v_saison, 'Talhof Bio AG', '', '', '', round(sum(kg_position) * 1.6, -2), v_wer, v_jetzt
      from ausgang_zeile where quelle = 'DEMO' and kunde = 'Talhof Bio AG'
    having sum(kg_position) > 0
    on conflict do nothing;
    -- Eine Perigon-Zeile als Mandarin verkauft, geliefert aus einer Knirps-Charge (Kaori Kuri).
    select z.id into v_z from ausgang_zeile z join charge c on c.nr::text = z.charge_extern
     where z.quelle = 'DEMO' and c.sorte = 'Kaori Kuri' order by z.datum desc, z.pos_id desc limit 1;
    insert into ausgang_artikel (artikel_id, artikel, ist_kuerbis, sorte, bemerkung)
    values ('kürbmand', 'Bio Kürbis Mandarin Dem', true, null, 'DEMO') on conflict (artikel_id, artikel) do nothing;
    update ausgang_zeile set artikel_id = 'kürbmand', artikel = 'Bio Kürbis Mandarin Dem' where id = v_z;
    raise notice 'Demo: Hagel an Charge %, Ausreisser ausgeschlossen, eine Kundengruppe, ein Plan, eine Perigon-Auffälligkeit (0116)', v_ch;
  end;

  drop table if exists demo_charge; drop table if exists demo_pal; drop table if exists demo_lauf;

  -- Die Auswertung wird hier absichtlich nicht neu gerechnet: Supabase gibt
  -- einem API-Aufruf acht Sekunden, und das Rechnen ist der teuerste Teil.
  -- Die App ruft auswertung_aktualisieren() gleich danach als eigenen
  -- Aufruf; demo_daten.sql tut dasselbe. Bis dahin steht die Auswertung als
  -- veraltet da — die Auslöser an den Tabellen haben das schon vermerkt.
  return (
    select format('Demo-Saison steht: %s Paletten in %s Chargen, %s Arbeiten (davon %s Fax), %s Sortierläufe, '
                  || '%s Lieferungen, %s Kontrollpaletten mit %s Wägungen, %s Verkaufsdateien, %s Rückmeldungen. '
                  || 'Eingang %s t. Jetzt in der App unter Lagermanagement anschauen.',
                  (select count(*) from palette where extern_id like 'demo-%'),
                  (select count(distinct charge_nr) from palette where extern_id like 'demo-%'),
                  (select count(*) from auftrag where bemerkung = 'DEMO'),
                  (select count(*) from auftrag where bemerkung = 'DEMO' and ist_fax),
                  (select count(*) from sortier_lauf where datei_name like 'DEMO-%'),
                  (select count(*) from lieferung where bemerkung = 'DEMO'),
                  (select count(*) from kontrollpalette where bemerkung = 'DEMO'),
                  (select count(*) from kontrollpalette_wiegung),
                  (select count(*) from ausgang_datei where bemerkung = 'DEMO'),
                  (select count(*) from auftrag_rueckmeldung r join auftrag a on a.id = r.auftrag_id where a.bemerkung = 'DEMO'),
                  (select round(sum(eingang_netto_kg) / 1000, 1) from v_charge_rueckgrat))
  );
end $fn$;

grant execute on function demo_daten_laden() to authenticated;
grant execute on function demo_daten_laden() to authenticated;
grant execute on function demo_daten_laden() to authenticated;
revoke execute on function demo_daten_laden() from public;
grant execute on function demo_daten_laden() to authenticated;
revoke execute on function demo_daten_laden() from public;
grant execute on function demo_daten_laden() to authenticated;
revoke execute on function demo_daten_laden() from public;
grant execute on function demo_daten_laden() to authenticated;

comment on function demo_daten_laden is
  'Legt die erfundene Demo-Saison an (Arbeiten mit bemerkung = ''DEMO'', Paletten mit extern_id ''demo-…'', Sortierdateien ''DEMO-…'', Lieferungen und Verkaufsdateien ''DEMO'', Kontrollpaletten mit bemerkung ''DEMO''; seit 0116 ein Hagelschaden, zwei ausgeschlossene Ausreisser, eine Kundengruppe und ein Plan). Echte Daten bleiben unberührt; im Echtmodus lässt sie sich gar nicht laden (0072). Deterministisch: zweimal laden gibt zweimal dieselbe Saison (0081).';
grant execute on function demo_daten_laden() to authenticated;

create or replace function demo_daten_entfernen()
returns text language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter entfernen.';
  end if;

  -- Zuerst der Erntestand: er wird an den Demo-Paletten erkannt.
  update charge set ernte_abgeschlossen_ts = null
   where ernte_abgeschlossen_ts is not null
     and nr in (select distinct charge_nr from palette where extern_id like 'demo-%');
  -- 0116: Hagel, Ausschlüsse, Kundengruppen und Pläne der Demo — vor den
  -- Arbeiten und Wägungen, an denen die Ausschlüsse hängen.
  update charge set hagel_anteil = null, hagel_ts = null
   where hagel_anteil is not null
     and nr in (select distinct charge_nr from palette where extern_id like 'demo-%');
  -- Auch wenn die Wägung oder Arbeit dazu schon weg ist: der Grund sagt DEMO.
  delete from messung_ausschluss
   where grund like 'DEMO %'
      or (art = 'palox' and bezug_id in (select id from auftrag where bemerkung = 'DEMO'))
      or (art in ('verdunstung', 'palox_lager')
          and bezug_id in (select id from verdunstung_wiegung
                            where auftrag_id in (select id from auftrag where bemerkung = 'DEMO')
                               or bemerkung = 'DEMO-KONTROLLE'));
  delete from kunde_gruppe where kunde in ('Nordmarkt Verteilzentrale', 'Feldfrisch Ost')
     and exists (select 1 from ausgang_zeile where quelle = 'DEMO');
  delete from kunde_plan where kunde in ('Nordmarkt Verteilzentrale', 'Talhof Bio AG', 'Grünwerk Handel', 'Feldfrisch Ost')
     and exists (select 1 from ausgang_zeile where quelle = 'DEMO');

  -- Die Kontrollpaletten vor den Paletten — sie zeigen mit palette_id darauf.
  delete from kontrollpalette_wiegung
   where kontrollpalette_id in (select id from kontrollpalette where bemerkung = 'DEMO');
  delete from kontrollpalette where bemerkung = 'DEMO';

  -- Reihenfolge ist wichtig: verdunstung_wiegung und sortier_lauf hängen mit
  -- "on delete set null" am Auftrag — würde man den Auftrag zuerst löschen,
  -- blieben ihre Zeilen verwaist zurück und zählten weiter mit.
  delete from verdunstung_wiegung
   where auftrag_id in (select id from auftrag where bemerkung = 'DEMO')
      or bemerkung = 'DEMO-KONTROLLE';
  delete from ausgang_wiegung
   where auftrag_id in (select id from auftrag where bemerkung = 'DEMO');
  delete from sortier_gewicht
   where lauf_id in (select id from sortier_lauf where datei_name like 'DEMO-%');
  delete from sortier_lauf where datei_name like 'DEMO-%';

  -- Der Rest hängt mit "on delete cascade" am Auftrag
  delete from lieferung where bemerkung = 'DEMO';      -- lieferung_import kaskadiert
  delete from ausgang_zeile where quelle = 'DEMO';
  delete from ausgang_datei where quelle = 'DEMO' and bemerkung = 'DEMO';
  delete from ausgang_artikel where bemerkung = 'DEMO';
  delete from ausgang_quelle where code = 'DEMO' and bemerkung = 'DEMO';
  delete from auftrag where bemerkung = 'DEMO';
  delete from charge_vorlauf where bemerkung like 'DEMO%';
  delete from palette where extern_id like 'demo-%';
  delete from sortierschema where bemerkung like 'DEMO%';
  -- Nur die von der Demo angelegten Käufer, und auch die nur, wenn nichts
  -- mehr an ihnen hängt. Ein Käufer, den der Betrieb selbst eingetragen hat,
  -- bleibt — auch wenn er zufällig denselben Code trägt.
  delete from kaeufer k where k.bemerkung = 'DEMO'
     and not exists (select 1 from auftrag a where a.kaeufer = k.code)
     and not exists (select 1 from sortierschema s where s.kaeufer = k.code);

  -- Kein Neurechnen hier — siehe demo_daten_laden(): eigener Aufruf danach.
  return (
    select format('Demo-Daten entfernt. Übrig: %s Paletten, %s Arbeiten, %s Sortierläufe, %s Kontrollpaletten.',
                  (select count(*) from palette),
                  (select count(*) from auftrag),
                  (select count(*) from sortier_lauf),
                  (select count(*) from kontrollpalette))
  );
end $fn$;

grant execute on function demo_daten_entfernen() to authenticated;
grant execute on function demo_daten_entfernen() to authenticated;
grant execute on function demo_daten_entfernen() to authenticated;

comment on function demo_daten_entfernen is
  'Löscht restlos alles, was demo_daten_laden() angelegt hat — samt Kontrollpaletten, Verkaufsdateien, dem Erntestand und (seit 0116) dem Hagel, den Ausschlüssen, Kundengruppen und Plänen der Demo. Echte Daten bleiben unberührt; erkannt wird die Demo an bemerkung = ''DEMO'', extern_id ''demo-…'' und datei_name ''DEMO-…'' (0081).';
grant execute on function demo_daten_entfernen() to authenticated;

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
  -- 0116: die ganze Zeile, wie sie in der Perigon-Datei stünde — damit das
  -- Lieferungs-Fenster auch in der Beispieldatenbank zeigt, was es kann.
  -- Ohne Erlös: Preise gehören nicht in die Demo.
  update ausgang_position p
     set roh = jsonb_build_array(jsonb_build_object(
           'AuftragsJournal', p.journal, 'AuftragsLieferDatum', to_char(p.datum, 'DD.MM.YYYY'),
           'AuftragsLieferant', p.kunde, 'AufPosId', p.pos_id, 'AuftragsArtId', p.artikel_id, 'AuftragsArtikel', p.artikel,
           'AuftragsArtikelMenge', p.menge, 'AuftragsArtikelEinheit', p.einheit, 'GewichtProArtikel', p.gewicht_je_artikel,
           'AuftragsChargeManuell', null, 'AufPosBatchQuantity Charge', null, 'AuftragsGebBez', p.gebindeart,
           'AuftragsGebindemenge', p.gebinde_menge, 'AuftragsPrsGrpBez', p.preisgruppe, 'LiefPrsGrpName', p.preisgruppe,
           'AuftragsErloesTotExkl', null))
   where p.quelle = 'DEMO' and p.roh is null;
  return format('Demo: %s Lieferungen in zwei Vorjahren, Labels an den Demo-Verkaufszeilen.', v_n);
end $fn$;

revoke all on function demo_vorjahre_laden() from public;
grant execute on function demo_vorjahre_laden() to authenticated;

revoke all on function demo_vorjahre_laden() from public;
grant execute on function demo_vorjahre_laden() to authenticated;
comment on function demo_vorjahre_laden() is
  'Ergänzt die Demo um das Perigon-Label je Verkaufszeile und zwei Vorjahre je Demo-Kunde (ausgang_position, quelle DEMO) — für Lager nach Artikel (0112); seit 0115 mit ein paar Stück ohne Stückgewicht im Vorjahr (kg leer), seit 0116 mit der ganzen Zeile (roh). Gleich nach demo_daten_laden() aufrufen; demo_daten_entfernen() räumt es mit der Demo-Firma weg.';

revoke all on function demo_vorjahre_laden() from public;
grant execute on function demo_vorjahre_laden() to authenticated;

-- aus 0117_kundengruppen_in_reihe_und_mit_plan.sql

create table if not exists kunde_gruppe_rang (
  gruppe    text primary key check (btrim(gruppe) <> ''),
  rang      int  not null,
  erfasser  uuid references profil(id) on delete set null default auth.uid(),
  ts        timestamptz not null default now()
);
comment on table kunde_gruppe_rang is
  'In welcher Reihenfolge die Kundengruppen unter Lagermanagement nach Artikel stehen (0117), vom Betriebsleiter gesetzt (kleiner Rang zuerst). Ohne Eintrag stehen die Gruppen nach ihrer Menge, Kleinkunden zuletzt.';
alter table kunde_gruppe_rang enable row level security;
drop policy if exists kunde_gruppe_rang_lesen on kunde_gruppe_rang;
drop policy if exists kunde_gruppe_rang_admin on kunde_gruppe_rang;
create policy kunde_gruppe_rang_lesen on kunde_gruppe_rang for select to authenticated using (true);
create policy kunde_gruppe_rang_admin on kunde_gruppe_rang for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on kunde_gruppe_rang to authenticated;

create table if not exists gruppe_plan (
  id            bigint generated by default as identity primary key,
  saison        int  not null,
  gruppe        text not null check (btrim(gruppe) <> ''),
  artikelgruppe text not null default '',
  groesse       text not null default '' check (groesse in ('', 'klein', 'gross')),
  label         text not null default '' check (label in ('', 'D', 'K')),
  kg            numeric(12,1) not null check (kg >= 0),
  erfasser      uuid references profil(id) on delete set null default auth.uid(),
  ts            timestamptz not null default now(),
  unique (saison, gruppe, artikelgruppe, groesse, label)
);
comment on table gruppe_plan is
  'Die Planmenge einer ganzen Kundengruppe für eine Saison (0117), in kg — je Artikelgruppe, Grösse und Label oder für alle ('''' = alle), wie kunde_plan. Gilt für die Gruppe als Ganzes: noch zu liefern = dieser Plan weniger das Gelieferte aller ihrer Kunden; Pläne einzelner Kunden darin zählen dann nicht noch einmal. Vom Betriebsleiter gesetzt.';
alter table gruppe_plan enable row level security;
drop policy if exists gruppe_plan_lesen on gruppe_plan;
drop policy if exists gruppe_plan_admin on gruppe_plan;
create policy gruppe_plan_lesen on gruppe_plan for select to authenticated using (true);
create policy gruppe_plan_admin on gruppe_plan for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on gruppe_plan to authenticated;

-- aus 0119_zwei_sortierschemata_halten_die_rechnung_nicht_an.sql

create table if not exists auswertung_index_entfernt (
  id     bigint generated by default as identity primary key,
  sicht  text not null,
  grund  text not null,
  ts     timestamptz not null default now()
);
comment on table auswertung_index_entfernt is
  'Wenn beim Erneuern ein eindeutiger Index die Daten nicht mehr hergab (0119): welche Ansicht, warum, wann. Die Rechnung lief weiter; der Index wurde entfernt (bei erg_* entsteht er in der nächsten Nacht aus auswertung_schluessel neu — und fällt wieder hier auf, wenn der Schlüssel falsch ist).';
alter table auswertung_index_entfernt enable row level security;
drop policy if exists auswertung_index_entfernt_lesen on auswertung_index_entfernt;
create policy auswertung_index_entfernt_lesen on auswertung_index_entfernt for select to authenticated using (ist_admin());
grant select on auswertung_index_entfernt to authenticated;

create or replace function auswertung_schluessel()
returns table (sicht text, ausdruck text) language sql immutable set search_path = public as $$
  values
    ('erg_ausgang',            'id'),
    ('erg_bilanz',             'heute'),
    ('erg_charge',             'charge_nr'),
    ('erg_datenlage',          'charge_nr'),
    ('erg_datenqualitaet',     'paletten_gezaehlt'),
    ('erg_durchsatz',          'auftrag_id'),
    ('erg_fax',                'auftrag_id'),
    ('erg_fax_wartezeit',      'gruppe, sorte, klasse'),
    ('erg_gebinde',            'sorte, kaliber_idx'),
    ('erg_gewichte',           'charge_nr, stufe_g'),
    ('erg_kaliber',            'charge_nr, klasse, kaliber_idx, band_von, band_bis'),
    ('erg_koeff_ausschuss',    'sorte'),
    ('erg_koeff_fax',          'sorte'),
    ('erg_koeff_nebenkanal',   'sorte'),
    ('erg_koeff_ueberfuellung','n'),
    ('erg_koeff_verdunstung',  'sorte'),
    ('erg_kohorte',            'charge_nr, eingangsdatum'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_palox_erwartung',    'sorte, station'),
    ('erg_plausibilitaet',     'art, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte')
$$;

drop index if exists erg_kaliber_eindeutig;
drop index if exists erg_ausschuss_eindeutig;

-- aus 0120_oettli_und_trueeb_im_chargenregister.sql

do $$
declare r record; v_andere int;
begin
  for r in select * from (values (1719, 'Oettli', 'Kaori Kuri', 2026),
                                 (1763, 'Trüeb',  'Amoro',      2026)) v(nr, schlag, sorte, saison)
  loop
    select nr into v_andere from charge
     where schlag = r.schlag and sorte = r.sorte and saison = r.saison and nr <> r.nr;
    if v_andere is not null then
      raise warning 'Chargenregister: % · % (%) steht schon unter Charge %, nicht unter % — nichts geändert; unter Stammdaten → Chargen klären.',
        r.schlag, r.sorte, r.saison, v_andere, r.nr;
      continue;
    end if;
    insert into charge (nr, schlag, sorte, saison) values (r.nr, r.schlag, r.sorte, r.saison)
    on conflict (nr) do update set schlag = excluded.schlag, sorte = excluded.sorte
     where (charge.schlag, charge.sorte) is distinct from (excluded.schlag, excluded.sorte);
  end loop;
end $$;

-- aus 0121_die_palette_geht_mit_ihrer_arbeit.sql

alter table palette add column if not exists charge_nr_journal int references charge(nr);
comment on column palette.charge_nr_journal is
  'Die Charge, die das Erntejournal der Palette gibt (0121). palette.charge_nr ist die Charge, mit der gerechnet wird — dieselbe, ausser die Palette ist mit Beleg zur Charge ihrer Arbeit umgebucht (palette_zuordnung).';
update palette set charge_nr_journal = charge_nr where charge_nr_journal is null;

create table if not exists palette_zuordnung (
  palette_id     bigint primary key references palette(id) on delete cascade,
  von_charge_nr  int    not null references charge(nr),
  nach_charge_nr int    not null references charge(nr),
  auftrag_id     bigint references auftrag(id) on delete set null,
  art            text   not null check (art in ('zettel', 'fuhre')),
  stand          text   not null default 'vorschlag' check (stand in ('angewandt', 'vorschlag', 'zurueckgenommen')),
  grund          text   not null,
  angelegt_ts    timestamptz not null default now(),
  geaendert_ts   timestamptz,
  geaendert_von  uuid references profil(id) on delete set null,
  check (von_charge_nr <> nach_charge_nr)
);
comment on table palette_zuordnung is
  'Paletten, die nach dem Beleg ihrer Zettel zur Charge der Arbeit gehören, die sie verarbeitet hat (0121). stand: angewandt (die Rechnung zählt sie bei nach_charge_nr), vorschlag (Beleg zu schwach — nur gezeigt), zurueckgenommen (vom Betriebsleiter; die Regel legt sie nicht wieder an). art: zettel (ein Zettel passt aufs Kilo), fuhre (kam mit solchen Paletten am selben Tag im selben Gebinde).';
alter table palette_zuordnung enable row level security;
drop policy if exists palette_zuordnung_lesen on palette_zuordnung;
create policy palette_zuordnung_lesen on palette_zuordnung for select to authenticated using (true);
grant select on palette_zuordnung to authenticated;

create or replace function palette_charge_halten() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_nach int;
begin
  if coalesce(current_setting('kuerbis.zuordnung', true), '') <> 'an' then
    new.charge_nr_journal := new.charge_nr;
  end if;
  select z.nach_charge_nr into v_nach from palette_zuordnung z
   where z.palette_id = new.id and z.stand = 'angewandt' and z.von_charge_nr = new.charge_nr_journal;
  new.charge_nr := coalesce(v_nach, new.charge_nr_journal, new.charge_nr);
  return new;
end $$;
comment on function palette_charge_halten() is
  'Hält eine angewandte Umbuchung (palette_zuordnung) über jeden Abgleich mit dem Journal: charge_nr_journal bekommt, was der Abgleich schreibt; charge_nr die Charge der Arbeit, solange das Journal die alte Charge nennt (0121).';

revoke all on function palette_charge_halten() from public;
grant execute on function palette_charge_halten() to authenticated;
drop trigger if exists palette_charge_halten on palette;
create trigger palette_charge_halten before insert or update of charge_nr on palette
  for each row execute function palette_charge_halten();

create or replace function paletten_zuordnen() returns int
language plpgsql security definer set search_path = public as $$
declare
  z record; w record; v_ch record; g record;
  v_pid bigint;
  v_eigen bigint[] := '{}';       -- Paletten, die ein Zettel ihrer eigenen Charge gezählt hat
  v_vergeben bigint[] := '{}';    -- Paletten, die schon eine andere Arbeit bekommen hat
  v_ohne bigint[];                -- Zettel einer Arbeit ohne eigene Palette
  v_best_charge int; v_best bigint[]; v_best_zettel text[];
  v_treffer bigint[]; v_zettel text[];
  v_anteil numeric; v_geliefert numeric; v_eingang numeric; v_stand text; v_n int := 0;
begin
  -- Der Rechenlauf ruft sie (Zeitplan: ohne Anmeldung); von Hand nur der Betriebsleiter.
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Paletten zuordnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  if to_regclass('pg_temp.zuordnung_neu') is null then
    create temp table zuordnung_neu (
      palette_id bigint primary key, von_charge_nr int, nach_charge_nr int, auftrag_id bigint,
      art text, stand text, grund text) on commit drop;
  end if;
  -- Arbeitstabellen dieses Aufrufs (temporär, mit der Transaktion weg) — leer beginnen.
  delete from zuordnung_neu where palette_id is not null;

  -- Zettel ohne eigene Palette: zuerst nimmt jeder Zettel eine Palette seiner
  -- eigenen Charge (laut Journal), aufs Kilo, Eingang ±3 Tage, die nächste
  -- zuerst — wie der Durchgang (pruefstand/durchgang_pruefungen.mjs, 4c).
  if to_regclass('pg_temp.zettel_ohne') is null then
    create temp table zettel_ohne (zettel_id bigint primary key, auftrag_id bigint) on commit drop;
  end if;
  delete from zettel_ohne where zettel_id is not null;
  for z in
    select ap.id, ap.auftrag_id, ap.brutto_zettel_kg, ap.eingangsdatum, a.charge_nr
      from auftrag_palette ap join auftrag a on a.id = ap.auftrag_id
     where a.abgebrochen_ts is null and ap.brutto_zettel_kg is not null and ap.eingangsdatum is not null
     order by a.start_ts, ap.id
  loop
    v_pid := null;
    select pl.id into v_pid from palette pl
     where coalesce(pl.charge_nr_journal, pl.charge_nr) = z.charge_nr and pl.brutto_kg = z.brutto_zettel_kg
       and abs(pl.eingangsdatum - z.eingangsdatum) <= 3 and not (pl.id = any(v_eigen))
     order by abs(pl.eingangsdatum - z.eingangsdatum), pl.id limit 1;
    if v_pid is not null then v_eigen := v_eigen || v_pid;
    else insert into zettel_ohne values (z.id, z.auftrag_id);
    end if;
  end loop;

  -- Je Arbeit mit mindestens zwei solchen Zetteln: die Charge desselben
  -- Schlags, zu deren Paletten die meisten passen.
  for w in
    select a.id as auftrag_id, a.charge_nr, c.schlag, count(*)::int as n_ohne
      from zettel_ohne zo join auftrag a on a.id = zo.auftrag_id join charge c on c.nr = a.charge_nr
     group by a.id, a.charge_nr, c.schlag, a.start_ts
    having count(*) >= 2
     order by a.start_ts, a.id
  loop
    v_best_charge := null; v_best := '{}'; v_best_zettel := '{}';
    for v_ch in select nr from charge where schlag = w.schlag and nr <> w.charge_nr order by nr loop
      v_treffer := '{}'; v_zettel := '{}';
      for z in
        select ap.id, ap.brutto_zettel_kg, ap.eingangsdatum
          from zettel_ohne zo join auftrag_palette ap on ap.id = zo.zettel_id
         where zo.auftrag_id = w.auftrag_id order by ap.id
      loop
        v_pid := null;
        select pl.id into v_pid from palette pl
         where coalesce(pl.charge_nr_journal, pl.charge_nr) = v_ch.nr and pl.brutto_kg = z.brutto_zettel_kg
           and abs(pl.eingangsdatum - z.eingangsdatum) <= 3
           and not (pl.id = any(v_eigen)) and not (pl.id = any(v_vergeben)) and not (pl.id = any(v_treffer))
         order by abs(pl.eingangsdatum - z.eingangsdatum), pl.id limit 1;
        if v_pid is not null then
          v_treffer := v_treffer || v_pid;
          v_zettel := v_zettel || format('%s kg', trim(to_char(z.brutto_zettel_kg, 'FM99990.##')));
        end if;
      end loop;
      if cardinality(v_treffer) > cardinality(v_best) then
        v_best_charge := v_ch.nr; v_best := v_treffer; v_best_zettel := v_zettel;
      end if;
    end loop;
    continue when cardinality(v_best) < 2;
    v_anteil := cardinality(v_best)::numeric / w.n_ohne;
    continue when v_anteil < 0.5;

    -- Hat die Charge der Arbeit mehr ausgeliefert, als sie laut Journal je bekam?
    select coalesce(sum(l.masse_kg), 0) into v_geliefert from v_lieferung_masse l
     where l.charge_nr = w.charge_nr and l.buch in ('verkauf', 'marge') and l.masse_kg > 0;
    select coalesce(sum(vp.netto_kg), 0) into v_eingang from v_palette vp join palette pl on pl.id = vp.id
     where coalesce(pl.charge_nr_journal, pl.charge_nr) = w.charge_nr;
    v_stand := case when v_anteil >= 0.8 and v_geliefert > v_eingang then 'angewandt' else 'vorschlag' end;

    insert into zuordnung_neu
    select pl.id, v_best_charge, w.charge_nr, w.auftrag_id, 'zettel', v_stand,
           format('%s von %s Zetteln der Arbeit %s (Charge %s) ohne eigene Palette passen aufs Kilo zu Paletten von Charge %s (%s)%s',
                  cardinality(v_best), w.n_ohne, w.auftrag_id, w.charge_nr, v_best_charge, array_to_string(v_best_zettel, ', '),
                  case when v_geliefert > v_eingang
                       then format('; Charge %s lieferte %s kg bei %s kg Eingang', w.charge_nr, round(v_geliefert), round(v_eingang))
                       else format('; Charge %s lieferte nicht mehr, als sie bekam', w.charge_nr) end)
      from palette pl where pl.id = any(v_best)
    on conflict (palette_id) do nothing;
    v_vergeben := v_vergeben || v_best;

    -- Die Fuhre: Paletten desselben Tags und Gebindes, von denen 80 % in der Arbeit lagen.
    if v_stand = 'angewandt' then
      for g in
        select pl.eingangsdatum, pl.gebindeart, count(*)::int as n,
               count(*) filter (where pl.id = any(v_best))::int as n_drin
          from palette pl
         where coalesce(pl.charge_nr_journal, pl.charge_nr) = v_best_charge
           and (pl.eingangsdatum, coalesce(pl.gebindeart, '')) in
               (select p2.eingangsdatum, coalesce(p2.gebindeart, '') from palette p2 where p2.id = any(v_best))
         group by pl.eingangsdatum, pl.gebindeart
      loop
        continue when g.n < 3 or g.n_drin::numeric / g.n < 0.8;
        insert into zuordnung_neu
        select pl.id, v_best_charge, w.charge_nr, w.auftrag_id, 'fuhre', 'angewandt',
               format('kam am %s mit %s weiteren %s-Paletten, die in der Arbeit %s lagen (%s von %s der Fuhre)',
                      to_char(g.eingangsdatum, 'DD.MM.'), g.n_drin, coalesce(g.gebindeart, 'Gebinde'), w.auftrag_id, g.n_drin, g.n)
          from palette pl
         where coalesce(pl.charge_nr_journal, pl.charge_nr) = v_best_charge
           and pl.eingangsdatum = g.eingangsdatum and coalesce(pl.gebindeart, '') = coalesce(g.gebindeart, '')
           and not (pl.id = any(v_best)) and not (pl.id = any(v_eigen)) and not (pl.id = any(v_vergeben))
        on conflict (palette_id) do nothing;
        v_vergeben := v_vergeben || array(select zn.palette_id from zuordnung_neu zn where zn.auftrag_id = w.auftrag_id and zn.art = 'fuhre');
      end loop;
    end if;
  end loop;

  -- Abgleichen: Was die Regel angelegt hat und keinen Beleg mehr hat, geht;
  -- was der Betriebsleiter gesetzt hat (geaendert_ts), bleibt, wie er es will.
  delete from palette_zuordnung pz
   where pz.geaendert_ts is null and pz.stand <> 'zurueckgenommen'
     and not exists (select 1 from zuordnung_neu zn where zn.palette_id = pz.palette_id
                        and zn.nach_charge_nr = pz.nach_charge_nr and zn.von_charge_nr = pz.von_charge_nr);
  update palette_zuordnung pz set stand = zn.stand, grund = zn.grund, auftrag_id = zn.auftrag_id, art = zn.art
    from zuordnung_neu zn
   where zn.palette_id = pz.palette_id and pz.geaendert_ts is null and pz.stand <> 'zurueckgenommen'
     and (pz.stand, pz.grund, pz.art) is distinct from (zn.stand, zn.grund, zn.art);
  insert into palette_zuordnung (palette_id, von_charge_nr, nach_charge_nr, auftrag_id, art, stand, grund)
  select zn.palette_id, zn.von_charge_nr, zn.nach_charge_nr, zn.auftrag_id, zn.art, zn.stand, zn.grund from zuordnung_neu zn
  on conflict (palette_id) do nothing;

  -- Anwenden: jede Palette auf die Charge, die gilt — der Trigger rechnet sie aus.
  perform set_config('kuerbis.zuordnung', 'an', true);
  update palette pl set charge_nr = pl.charge_nr
   where pl.charge_nr is distinct from coalesce(
           (select z2.nach_charge_nr from palette_zuordnung z2
             where z2.palette_id = pl.id and z2.stand = 'angewandt' and z2.von_charge_nr = pl.charge_nr_journal),
           pl.charge_nr_journal, pl.charge_nr);
  get diagnostics v_n = row_count;
  perform set_config('kuerbis.zuordnung', '', true);
  return v_n;
end $$;
comment on function paletten_zuordnen() is
  'Die Regel aus 0121: Paletten zur Charge der Arbeit, die sie nachweislich verarbeitet hat (Zettel aufs Kilo, 80 %, die Charge der Arbeit lieferte mehr, als sie bekam; dazu der Rest einer Fuhre). Schwächerer Beleg bleibt Vorschlag. Läuft zu Beginn jedes Rechenlaufs; gibt zurück, wie viele Paletten die Charge gewechselt haben.';
revoke all on function paletten_zuordnen() from public;
grant execute on function paletten_zuordnen() to authenticated;

create or replace function palette_zuordnung_setzen(p_palette_ids bigint[], p_stand text) returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Umbuchen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  if p_stand not in ('angewandt', 'zurueckgenommen') then
    raise exception 'palette_zuordnung_setzen: Stand % gibt es nicht (angewandt, zurueckgenommen).', p_stand;
  end if;
  update palette_zuordnung set stand = p_stand, geaendert_ts = now(), geaendert_von = auth.uid()
   where palette_id = any(p_palette_ids);
  get diagnostics v_n = row_count;
  perform set_config('kuerbis.zuordnung', 'an', true);
  update palette pl set charge_nr = pl.charge_nr where pl.id = any(p_palette_ids);
  perform set_config('kuerbis.zuordnung', '', true);
  return v_n;
end $$;
comment on function palette_zuordnung_setzen(bigint[], text) is
  'Der Betriebsleiter bucht Paletten um (angewandt) oder nimmt die Umbuchung zurück (zurueckgenommen) — die Regel legt eine zurückgenommene nicht wieder an (0121).';
revoke all on function palette_zuordnung_setzen(bigint[], text) from public;
grant execute on function palette_zuordnung_setzen(bigint[], text) to authenticated;

create or replace function lieferungen_nachordnen() returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Lieferscheine nachordnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  with offen as (
    select l.id, regexp_replace(z.charge_extern, '\D', '', 'g') as ziffern
      from lieferung l
      join lieferung_import li on li.lieferung_id = l.id
      join ausgang_zeile z on z.id = li.zeile_id
     where l.charge_nr is null and li.extern_id not like '%:rest'
       and coalesce(z.charge_extern, '') ~ '\d'
  ), geloest as (
    select o.id,
           coalesce((select c.nr from charge c where c.nr::text = o.ziffern),
                    (select min(c.nr) from charge c where c.perigon_nr::text = o.ziffern
                      having count(*) = 1)) as charge_nr
      from offen o
  )
  update lieferung l set charge_nr = g.charge_nr, sorte = c.sorte
    from geloest g join charge c on c.nr = g.charge_nr
   where l.id = g.id and g.charge_nr is not null;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function lieferungen_nachordnen() from public;
grant execute on function lieferungen_nachordnen() to authenticated;

CREATE OR REPLACE FUNCTION public.auswertung_schritt_intern(p_schritt integer, p_nebenlaeufig boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
  v_ausdruck text;
  v_eindeutig boolean;
  v_gefuellt boolean;
  v_seit timestamptz;
  v_t timestamptz;
  v_index text;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- Je Aufruf eine Beratungssperre (0100): zwei Erneuerungen derselben
  -- Ansicht zur selben Sekunde gibt es nicht. Im Zeitplan-Weg hält der
  -- ganze Lauf sie (eine Transaktion); ein Schritt aus der App, der sie
  -- nicht bekommt, geht sofort mit „wartet".
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return jsonb_build_object('schritt', p_schritt, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                              'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true,
                              'rechnet_seit', (select rechnet_seit from auswertung_stand where id = 1));
  end if;
  -- Der App-Weg (fünf einzelne Aufrufe, je eine Transaktion) merkt sich in
  -- rechnet_seit, dass er läuft (0100). Der Zeitplan-Weg tut das nicht: Ein
  -- Update hier hielte die Zeile bis zum Ende des Laufs gesperrt, und jedes
  -- „Neu rechnen" bliebe daran hängen (0103).
  if p_schritt = 1 and not p_nebenlaeufig then
    update auswertung_stand
       set rechnet_seit = clock_timestamp()
     where id = 1 and (rechnet_seit is null or rechnet_seit < clock_timestamp() - interval '15 minutes')
    returning rechnet_seit into v_seit;
    if v_seit is null then
      select rechnet_seit into v_seit from auswertung_stand where id = 1;
      return jsonb_build_object('schritt', 1, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                                'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true, 'rechnet_seit', v_seit);
    end if;
  end if;
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'erg_punkte',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_fax', 'erg_koeff_ueberfuellung', 'mv_koeff_rand',
                       'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_fax_wartezeit', 'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      -- 0116: die Gewichtsverteilung beim Eingang vor der Kaskade, die sie liest.
      v_namen := array['erg_palox_erwartung', 'mv_kaliber_eingang', 'mv_kaliber_quelle', 'mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_prognose', 'erg_wohin', 'erg_verlauf', 'erg_bilanz',
                       'erg_marge', 'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage',
                       'erg_marge_wiegung', 'erg_marge_charge'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  if p_schritt = 1 then
    -- 0121: zuerst die Lieferscheine, deren Charge die App inzwischen kennt,
    -- dann die Paletten zur Charge ihrer Arbeit, wo der Beleg reicht —
    -- alles, was danach gerechnet wird, sieht sie dort.
    perform lieferungen_nachordnen();
    perform paletten_zuordnen();
    for v_name in
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
    delete from auswertung_laufzeit where ts < clock_timestamp() - interval '7 days';
  end if;

  foreach v_name in array v_namen loop
    v_t := clock_timestamp();
    v_eindeutig := false;
    if p_nebenlaeufig then
      select s.ausdruck into v_ausdruck from auswertung_schluessel() s where s.sicht = v_name;
      select c.relispopulated into v_gefuellt from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_name;
      if v_ausdruck is not null and coalesce(v_gefuellt, false) then
        begin
          if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indrelid
                          where c.relname = v_name and i.indisunique and i.indexprs is null and i.indpred is null) then
            execute format('create unique index %I on %I (%s) nulls not distinct', v_name || '_eindeutig', v_name, v_ausdruck);
          end if;
          v_eindeutig := true;
        exception when others then
          raise notice 'auswertung_schritt: % bekommt keinen eindeutigen Index (%) — wird normal erneuert', v_name, sqlerrm;
        end;
      end if;
    end if;
    if v_eindeutig then
      begin
        execute format('refresh materialized view concurrently %I', v_name);
      exception when others then
        raise notice 'auswertung_schritt: % nicht nebenläufig erneuert (%) — normal erneuert', v_name, sqlerrm;
        v_eindeutig := false;
      end;
    end if;
    if not v_eindeutig then
      begin
        execute format('refresh materialized view %I', v_name);
      exception when unique_violation then
        -- 0119: Ein eindeutiger Index, den die Daten nicht mehr hergeben, hält die
        -- Rechnung nicht an. Er geht weg (die Ansicht wird dann normal erneuert,
        -- nicht nebenläufig), die Rechnung läuft weiter, und der Lauf sagt es.
        raise notice 'auswertung_schritt: % — ein eindeutiger Index passt nicht mehr zu den Daten (%); entfernt, normal erneuert', v_name, sqlerrm;
        for v_index in
          select i.relname from pg_index x join pg_class i on i.oid = x.indexrelid join pg_class c on c.oid = x.indrelid
           join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relname = v_name and x.indisunique
        loop
          execute format('drop index if exists %I', v_index);
        end loop;
        insert into auswertung_index_entfernt (sicht, grund) values (v_name, sqlerrm);
        execute format('refresh materialized view %I', v_name);
      end;
    end if;
    execute format('analyze %I', v_name);
    -- 0103: Wo die Minuten hingehen, sagt jeder Lauf selbst.
    insert into auswertung_laufzeit (schritt, sicht, nebenlaeufig, dauer_ms)
    values (p_schritt, v_name, v_eindeutig, (extract(epoch from clock_timestamp() - v_t) * 1000)::int);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),
           rechnet_seit = null,
           dauer_ms = case when p_nebenlaeufig then null else coalesce(dauer_ms, 0) end
                      + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif not p_nebenlaeufig then
    if p_schritt = 1 then
      update auswertung_stand
         set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
       where id = 1;
    else
      update auswertung_stand
         set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
       where id = 1;
    end if;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5, 'nebenlaeufig', p_nebenlaeufig, 'wartet', false);
end $function$;
revoke execute on function auswertung_schritt_intern(integer, boolean) from public;
grant execute on function auswertung_schritt_intern(integer, boolean) to authenticated;

comment on function auswertung_schritt_intern(integer, boolean) is
  'Ein Schritt des Neurechnens (0078), wahlweise nebenläufig (0095). Beratungssperre je Aufruf (0100); der App-Weg merkt '
  'sich rechnet_seit, der Zeitplan-Weg fasst auswertung_stand erst am Ende an; je Ansicht wird die Dauer notiert '
  '(auswertung_laufzeit, 0103). Schritt 3 rechnet seit 0107 auch erg_palox_erwartung, seit 0116 vor der Kaskade die Gewichtsverteilung beim Eingang (mv_kaliber_eingang, mv_kaliber_quelle). Seit 0119 hält ein eindeutiger Index, den die Daten nicht mehr hergeben, die Rechnung nicht an: er wird entfernt und in auswertung_index_entfernt notiert. Seit 0121 ordnet Schritt 1 zuerst Lieferscheine (lieferungen_nachordnen) und Paletten (paletten_zuordnen) zu. Nur für den Betriebsleiter oder ohne Anmeldung.';

-- aus 0122_wer_im_perigon_wie_heisst.sql

do $$
declare r record; v_ist int; v_neu int := 0;
begin
  -- 0124: Die Liste läuft genau einmal. setup.sql spielt jede Migration bei
  -- jedem Einspielen neu ein; ohne Marke trüge sie eine Nummer, die der
  -- Betriebsleiter unter Stammdaten bewusst gelöscht hat, beim nächsten Mal
  -- wieder ein — und warnte bei jeder bewusst geänderten jedes Mal von neuem.
  if exists (select 1 from einstellung where schluessel = 'perigon_liste_2026_10_23') then return; end if;
  -- Die Berichtigung vom 23. Oktober: 1650 ist 198977, nicht 198976 — nur,
  -- wo noch die alte Nummer der Planungsdatei (0051) steht.
  update charge set perigon_nr = 198977 where nr = 1650 and perigon_nr = 198976;
  if found then raise notice 'Charge 1650: Perigon-Nr. 198976 → 198977 (Liste vom 23. Oktober, berichtigt).'; end if;
  for r in select * from (values
    (1598, 198876), (1599, 198877), (1601, 198888), (1603, 198915), (1604, 198916),
    (1605, 198917), (1606, 198919), (1607, 198889), (1608, 198920), (1609, 198918),
    (1610, 198921), (1611, 198922), (1612, 198944), (1613, 198923), (1614, 198945),
    (1615, 198946), (1616, 198947), (1617, 198948), (1618, 198949), (1619, 198950),
    (1620, 198951), (1623, 198955), (1624, 198956), (1625, 198957), (1626, 198958),
    (1627, 198959), (1628, 198970), (1630, 198969), (1631, 198968), (1632, 198960),
    (1633, 198961), (1634, 198962), (1635, 198963), (1636, 198966), (1637, 198964),
    (1638, 198965), (1646, 198952), (1647, 198953), (1648, 198974), (1649, 198976),
    (1650, 198977), (1651, 198975), (1719, 199156), (1763, 199158)) v(nr, p)
  loop
    select c.perigon_nr into v_ist from charge c where c.nr = r.nr;
    if not found then continue; end if;
    if v_ist is null then
      update charge set perigon_nr = r.p where nr = r.nr;
      v_neu := v_neu + 1;
    elsif v_ist <> r.p then
      raise warning 'Charge %: in der App steht die Perigon-Nr. %, in der Liste vom 23. Oktober %. Nichts geändert — unter Stammdaten → Chargen klären.', r.nr, v_ist, r.p;
    end if;
  end loop;
  if v_neu > 0 then raise notice 'Perigon-Nummern der Liste vom 23. Oktober: % eingetragen.', v_neu; end if;
  insert into einstellung (schluessel, wert, bemerkung)
  values ('perigon_liste_2026_10_23', 'true'::jsonb,
          'Die Perigon-Nummern der Planungsliste vom 23. Oktober sind eingetragen (0122). Die Liste läuft nicht noch einmal (0124); Nummern pflegt der Betriebsleiter unter Stammdaten → Chargen.')
  on conflict (schluessel) do nothing;
end $$;
comment on column charge.perigon_nr is
  'Chargennummer derselben Ware im Perigon der Firma AG (sechsstellig). Aus der '
  'Planungsdatei des Betriebs (0051), ergänzt und berichtigt mit der Liste vom '
  '23. Oktober (0122). Gehört zu genau einer Charge; steht sie an zweien, sagt '
  'es v_stammdaten_pruefung.';

create or replace function name_norm(p text) returns text
language sql immutable set search_path = public as $$
  select nullif(btrim(regexp_replace(regexp_replace(lower(normalize(coalesce(p, ''), nfc)), '[[:punct:]]+', ' ', 'g'), '\s+', ' ', 'g')), '')
$$;
comment on function name_norm(text) is
  'Vergleichsform eines Namens (Schlag, Produzent): NFC, klein, Satzzeichen zu Leerzeichen — wie norm() in src/lib/import.ts (0122).';
revoke all on function name_norm(text) from public;
grant execute on function name_norm(text) to authenticated;

create table if not exists schlag_alias (
  alias       text primary key,
  schlag      text not null,
  angelegt_ts timestamptz not null default now()
);

do $$ begin
  alter table schlag_alias add constraint schlag_alias_namen check (name_norm(alias) is not null and name_norm(schlag) is not null);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table schlag_alias add constraint schlag_alias_nicht_sich_selbst check (name_norm(alias) <> name_norm(schlag));
exception when duplicate_object then null; end $$;
comment on table schlag_alias is
  'Wie ein Schlag anderswo heisst — im Erntejournal oder in Perigon Spalte X (Produzent): Inauen ist Oettli, Trüb ist Trüeb (0122). Der Abgleich mit dem Journal und die Zuordnung über den Produzenten lesen sie; der Betriebsleiter pflegt sie unter Stammdaten.';
create unique index if not exists schlag_alias_norm on schlag_alias (name_norm(alias));
alter table schlag_alias enable row level security;
drop policy if exists schlag_alias_lesen on schlag_alias;
create policy schlag_alias_lesen on schlag_alias for select to authenticated using (true);
drop policy if exists schlag_alias_admin on schlag_alias;
create policy schlag_alias_admin on schlag_alias for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on schlag_alias to authenticated;

insert into schlag_alias (alias, schlag) values
  ('Inauen', 'Oettli'), ('Oettli, Inauen', 'Oettli'), ('Ötli', 'Oettli'), ('Oetli', 'Oettli'),
  ('Trüb', 'Trüeb'), ('Trueb', 'Trüeb')
on conflict do nothing;

create table if not exists lieferung_nachordnung (
  lieferung_id bigint primary key references lieferung(id) on delete cascade,
  charge_nr    int not null references charge(nr),
  weg          text not null check (weg in ('nummer', 'produzent')),
  nummer       text,
  produzent    text,
  grund        text not null,
  ts           timestamptz not null default now()
);
comment on table lieferung_nachordnung is
  'Welcher Lieferschein seine Charge erst im Rechenlauf bekam und warum (0121/0122): weg nummer = die Nummer der Datei kennt die App inzwischen; produzent = die Nummer steht an keiner Charge, aber Produzent (Spalte X) und Artikel zeigen auf genau eine.';
alter table lieferung_nachordnung enable row level security;
drop policy if exists lieferung_nachordnung_lesen on lieferung_nachordnung;
create policy lieferung_nachordnung_lesen on lieferung_nachordnung for select to authenticated using (true);
grant select on lieferung_nachordnung to authenticated;

create or replace function lieferungen_nachordnen() returns int
language plpgsql security definer set search_path = public as $$
declare v_n int; v_m int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Lieferscheine nachordnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- Stufe 1 (0121): die eigene Nummer, sonst eine Perigon-Nummer an genau einer Charge.
  with offen as (
    select l.id, z.charge_extern, regexp_replace(z.charge_extern, '\D', '', 'g') as ziffern
      from lieferung l
      join lieferung_import li on li.lieferung_id = l.id
      join ausgang_zeile z on z.id = li.zeile_id
     where l.charge_nr is null and li.extern_id not like '%:rest'
       and coalesce(z.charge_extern, '') ~ '\d'
  ), geloest as (
    select o.id, o.ziffern,
           coalesce((select c.nr from charge c where c.nr::text = o.ziffern),
                    (select min(c.nr) from charge c where c.perigon_nr::text = o.ziffern
                      having count(*) = 1)) as charge_nr
      from offen o
  ), gesetzt as (
    update lieferung l set charge_nr = g.charge_nr, sorte = c.sorte
      from geloest g join charge c on c.nr = g.charge_nr
     where l.id = g.id and g.charge_nr is not null
    returning l.id, l.charge_nr, g.ziffern
  )
  insert into lieferung_nachordnung (lieferung_id, charge_nr, weg, nummer, grund)
  select s.id, s.charge_nr, 'nummer', s.ziffern,
         format('Die Nummer %s steht inzwischen an Charge %s.', s.ziffern, s.charge_nr)
    from gesetzt s
  on conflict (lieferung_id) do update
    set charge_nr = excluded.charge_nr, weg = excluded.weg, nummer = excluded.nummer,
        produzent = null, grund = excluded.grund, ts = now();
  get diagnostics v_n = row_count;

  -- Stufe 2 (0122): Die Nummer steht an keiner Charge. Produzent (Spalte X)
  -- und Artikel zeigen auf genau eine Charge der Saison — dann diese.
  with offen as (
    select l.id, l.datum, z.produzent, z.artikel, z.preisgruppe,
           regexp_replace(z.charge_extern, '\D', '', 'g') as ziffern
      from lieferung l
      join lieferung_import li on li.lieferung_id = l.id
      join ausgang_zeile z on z.id = li.zeile_id
     where l.charge_nr is null and li.extern_id not like '%:rest'
       and coalesce(z.charge_extern, '') ~ '\d'
       and name_norm(z.produzent) is not null
       and not exists (select 1 from charge x
                        where x.nr::text = regexp_replace(z.charge_extern, '\D', '', 'g')
                           or x.perigon_nr::text = regexp_replace(z.charge_extern, '\D', '', 'g'))
  ), mit as (
    -- wie schlag_von_produzent(), aber v_perigon_produzent einmal gelesen statt je Lieferschein
    select o.*, coalesce(pp.schlag, (select min(c.schlag) from charge c where name_norm(c.schlag) = name_norm(o.produzent))) as schlag,
           (artikel_einordnen(o.artikel, o.preisgruppe)).gruppe as gruppe
      from offen o
      left join v_perigon_produzent pp on pp.produzent = name_norm(o.produzent)
  ), geloest as (
    select m.id, m.ziffern, m.produzent, m.schlag, m.gruppe,
           (select min(c.nr) from charge c join sorte_kaliber sk on sk.sorte = c.sorte
             where name_norm(c.schlag) = name_norm(m.schlag) and sk.artikelgruppe = m.gruppe
               and c.saison = saison_von(m.datum)
            having count(*) = 1) as charge_nr
      from mit m
     where m.schlag is not null and m.gruppe is not null and m.gruppe not in ('Mix', 'andere')
  ), gesetzt as (
    update lieferung l set charge_nr = g.charge_nr, sorte = c.sorte
      from geloest g join charge c on c.nr = g.charge_nr
     where l.id = g.id and g.charge_nr is not null
    returning l.id, l.charge_nr, g.ziffern, g.produzent, g.schlag, g.gruppe
  )
  insert into lieferung_nachordnung (lieferung_id, charge_nr, weg, nummer, produzent, grund)
  select s.id, s.charge_nr, 'produzent', s.ziffern, s.produzent,
         format('Die Nummer %s steht an keiner Charge. Perigon nennt als Produzent %s — das ist %s —, und %s hat genau eine Charge mit %s: %s.',
                s.ziffern, s.produzent, s.schlag, s.schlag, s.gruppe, s.charge_nr)
    from gesetzt s
  on conflict (lieferung_id) do update
    set charge_nr = excluded.charge_nr, weg = excluded.weg, nummer = excluded.nummer,
        produzent = excluded.produzent, grund = excluded.grund, ts = now();
  get diagnostics v_m = row_count;
  return v_n + v_m;
end $$;
comment on function lieferungen_nachordnen() is
  'Gibt Lieferscheinen ohne Charge ihre Charge, sobald die Nummer der Datei eine kennt (eigene Nummer, sonst eine Perigon-Nummer an genau einer Charge, 0121) — oder, steht die Nummer an keiner Charge, wenn Produzent (Spalte X) und Artikel auf genau eine Charge der Saison zeigen (0122). Schreibt den Grund in lieferung_nachordnung; läuft zu Beginn jedes Rechenlaufs; gibt zurück, wie viele es waren.';
revoke all on function lieferungen_nachordnen() from public;
grant execute on function lieferungen_nachordnen() to authenticated;

alter function auftrag_schema_setzen() set search_path = public;
alter function ausschuss_netto_setzen() set search_path = public;
alter function csv_lauf_speichern(int, text, text, text, timestamptz, text, jsonb, int, int, int, int, jsonb) set search_path = public;
alter function csv_sammel_speichern(int, text, text, text, jsonb, int, int, int, int, jsonb, timestamptz, timestamptz) set search_path = public;
alter function lauf_neu_klassieren(bigint) set search_path = public;
alter function lesung_als_sammel(bigint, timestamptz, timestamptz) set search_path = public;
alter function schimmel_netto_setzen() set search_path = public;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 124 $$;
comment on function schema_stand is
  'Nummer der jüngsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET (src/lib/version.ts) und verlangt bei Abweichung, setup.sql '
  'erneut auszuführen. Jede Migration setzt sie auf ihre eigene Nummer.';
revoke all on function schema_stand() from public;
grant execute on function schema_stand() to anon, authenticated;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';


-- =====================================================================
-- TEIL B — Das Rechenwerk: die Formeln, wie sie heute lauten
-- =====================================================================
-- Ab hier steht jede Ansicht und jede darauf rechnende Funktion genau
-- einmal — in 162 Schritten, in der Reihenfolge, in der eine auf der
-- anderen steht. Die Reihenfolge ist ausgerechnet, nicht geraten:
-- setup_bauen.sh sortiert topologisch und bricht ab, wenn sie nicht
-- kreisfrei wäre.
--
-- Zuerst wird weggeräumt, in umgekehrter Reihenfolge. Auf einer leeren
-- Datenbank passiert dabei nichts; auf einer bestehenden verschwindet das
-- alte Rechenwerk, damit das neue sauber daneben steht statt darüber.
-- Die Daten sind davon nicht berührt: In Ansichten liegt nichts, sie
-- rechnen nur. Was in den gespeicherten Ansichten (mv_…, erg_…) steht,
-- wird am Ende dieser Datei neu berechnet.
-- =====================================================================

drop view if exists v_charge_spur cascade;
drop view if exists v_lager_ausweis cascade;
drop view if exists v_ungereimtheit cascade;
drop view if exists v_stammdaten_pruefung cascade;
drop view if exists v_perigon_produzent cascade;
drop view if exists v_perigon_pruefung cascade;
drop view if exists v_ohne_charge cascade;
drop materialized view if exists erg_kaliber cascade;
drop view if exists v_kaliber_verteilung cascade;
drop materialized view if exists mv_kaliber_verteilung cascade;
drop view if exists v_kunde_position cascade;
drop materialized view if exists erg_wohin cascade;
drop view if exists v_wohin cascade;
drop view if exists v_saisonbilanz cascade;
drop view if exists v_marge_buch cascade;
drop view if exists v_plausibilitaet cascade;
drop view if exists v_verlust_ranking cascade;
drop materialized view if exists erg_verlust cascade;
drop view if exists v_verlust_je_gruppe cascade;
drop view if exists v_plausibilitaet_0054_zusatz cascade;
drop view if exists v_naechste_charge cascade;
drop view if exists v_massenbilanz cascade;
drop view if exists v_kontrolle_vorschlag cascade;
drop view if exists v_hochrechnung cascade;
drop view if exists v_plausibilitaet_0064_zusatz cascade;
drop materialized view if exists mv_hochrechnung cascade;
drop view if exists v_lager_kaliber cascade;
drop materialized view if exists erg_prognose cascade;
drop materialized view if exists erg_charge cascade;
drop view if exists v_prognose cascade;
drop view if exists v_kaskade cascade;
drop view if exists v_hochrechnung_basis cascade;
drop materialized view if exists erg_verlauf cascade;
drop materialized view if exists mv_kaskade cascade;
drop materialized view if exists mv_kaliber_quelle cascade;
drop materialized view if exists mv_kaliber_eingang cascade;
drop view if exists v_kaliber_lauf cascade;
drop view if exists v_kaliber_fassung cascade;
drop materialized view if exists erg_palox_erwartung cascade;
drop view if exists v_palox_erwartung cascade;
drop view if exists v_charge_palox cascade;
drop view if exists v_schimmel_punkte cascade;
drop view if exists v_schimmel_punkte_formel cascade;
drop view if exists v_lauf_vergleich cascade;
drop materialized view if exists mv_koeff_rand cascade;
drop materialized view if exists erg_koeff_fax cascade;
drop view if exists v_koeff_fax cascade;
drop view if exists v_koeff_nebenkanal cascade;
drop view if exists v_koeff_ausschuss cascade;
drop view if exists v_koeff_unsicherheit cascade;
drop view if exists v_koeff_kaliber_geschaetzt cascade;
drop view if exists v_koeff_kaliber_geschaetzt_formel cascade;
drop view if exists v_koeff_roh_kaliber cascade;
drop view if exists v_ausschuss_beobachtung cascade;
drop view if exists v_schimmel_beobachtung cascade;
drop view if exists v_koeff_verdunstung cascade;
drop view if exists v_koeff_verdunstung_geschaetzt cascade;
drop view if exists v_wiegung_kennzahl cascade;
drop view if exists v_koeff_roh_verdunstung cascade;
drop view if exists v_verdunstung_messung cascade;
drop view if exists v_lieferung_gruppe cascade;
drop view if exists v_charge_weg cascade;
drop materialized view if exists erg_fax_wartezeit cascade;
drop view if exists v_fax_wartezeit cascade;
drop view if exists v_kaskade_basis cascade;
drop view if exists v_fax_beobachtung cascade;
drop view if exists v_durchsatz cascade;
drop view if exists v_auftrag_masse cascade;
drop view if exists v_auftrag_masse_formel cascade;
drop view if exists v_datenqualitaet cascade;
drop materialized view if exists mv_sortier_eingang cascade;
drop materialized view if exists mv_auftrag_masse cascade;
drop view if exists v_auftrag_palette_masse cascade;
drop view if exists v_kunde_tag cascade;
drop view if exists v_verkauf_position cascade;
drop view if exists v_lieferung_kohorte cascade;
drop view if exists v_lieferung_charge_tag cascade;
drop view if exists v_lieferung_charge cascade;
drop view if exists v_charge_label cascade;
drop view if exists v_sorte_artikelgruppe cascade;
drop view if exists v_palox_station cascade;
drop view if exists v_auftrag_wasch_paletten cascade;
drop view if exists v_auftrag_gebinde_masse cascade;
drop view if exists v_koeff_gebinde cascade;
drop view if exists v_koeff_gebinde_formel cascade;
drop materialized view if exists mv_schimmel_punkte cascade;
drop view if exists v_verderb_lage cascade;
drop view if exists v_schimmel_kurve cascade;
drop view if exists v_schimmel_modell_rechnen cascade;
drop materialized view if exists mv_schimmel_modell cascade;
drop view if exists v_schimmel_modell cascade;
drop view if exists v_selektionsverdacht cascade;
drop view if exists v_schimmel_kurve_anzeige cascade;
drop materialized view if exists erg_selektion cascade;
drop materialized view if exists erg_kurve cascade;
drop materialized view if exists erg_modell cascade;
drop view if exists v_auftrag_wasch_gewogen cascade;
drop materialized view if exists erg_marge_charge cascade;
drop materialized view if exists erg_marge_wiegung cascade;
drop view if exists v_marge_charge cascade;
drop view if exists v_marge_wiegung cascade;
drop view if exists v_auftrag_fertige_masse cascade;
drop view if exists v_koeff_palette_netto cascade;
drop view if exists v_ausgang_voll cascade;
drop materialized view if exists erg_ueberfuellung cascade;
drop view if exists v_ueberfuellung_verkauf cascade;
drop view if exists v_koeff_ueberfuellung cascade;
drop view if exists v_lieferung_masse cascade;
drop view if exists v_ausgang_kennzahl cascade;
drop view if exists v_arbeit_kommentar cascade;
drop view if exists v_schimmel_menge cascade;
drop view if exists v_palox_stand cascade;
drop view if exists v_sortier_lesung cascade;
drop materialized view if exists erg_lager_kaliber cascade;
drop view if exists v_kontrollpalette_vorschlag cascade;
drop view if exists v_kontrollpalette_rate cascade;
drop view if exists v_charge_erntespanne cascade;
drop view if exists v_verarbeitung_alter cascade;
drop view if exists v_kohorte_anteil cascade;
drop view if exists v_charge_kohorte cascade;
drop view if exists v_datenlage cascade;
drop view if exists v_charge_rueckgrat cascade;
drop view if exists v_palette cascade;
drop view if exists v_saisonverlauf cascade;
drop view if exists v_ueberfuellung_kaeufer cascade;
drop view if exists v_verkauf_lieferung cascade;
drop view if exists v_ausgang_pruef cascade;
drop view if exists v_ausgang_lage cascade;
drop view if exists v_ausgang_artikel_vorschlag cascade;
drop view if exists v_gewichtsverteilung cascade;
drop view if exists v_verdunstung_stichprobe cascade;
drop view if exists v_sortier_kuerbis cascade;
drop view if exists v_schlag_effekt cascade;
drop view if exists v_dubletten_pruefung cascade;
drop view if exists v_auftrag_sortierart cascade;
drop view if exists v_ausschuss_pruef cascade;
drop view if exists v_auftrag_angabe cascade;
drop view if exists v_sortier_lauf_masse cascade;
drop materialized view if exists mv_sortier_lauf_masse cascade;


-- ---------------------------------------------------------------------
-- Neu bauen — von unten nach oben
-- ---------------------------------------------------------------------


create materialized view if not exists mv_sortier_lauf_masse as
select l.id as lauf_id, l.charge_nr, c.sorte, c.schlag, l.auftrag_id,
       l.datei_name, l.datei_zeit, l.zuordnung,
       sum(g.anzahl)                                                    as n_kuerbis,
       (sum(g.anzahl::bigint * g.gewicht_g) / 1000.0)::numeric(12,2)    as masse_kg,
       sum(g.anzahl) filter (where g.klasse = 'verlust_klein')          as n_klein,
       (sum(g.anzahl::bigint * g.gewicht_g) filter (where g.klasse = 'verlust_klein')
        / 1000.0)::numeric(12,2)                                        as masse_klein_kg,
       sum(g.anzahl) filter (where g.klasse = 'nebenkanal')             as n_nebenkanal,
       (sum(g.anzahl::bigint * g.gewicht_g) filter (where g.klasse = 'nebenkanal')
        / 1000.0)::numeric(12,2)                                        as masse_nebenkanal_kg,
       sum(g.anzahl) filter (where g.klasse = 'kaliber')                as n_kaliber,
       (sum(g.anzahl::bigint * g.gewicht_g) filter (where g.klasse = 'kaliber')
        / 1000.0)::numeric(12,2)                                        as masse_kaliber_kg
  from sortier_lauf l
  join charge c on c.nr = l.charge_nr
  join sortier_gewicht g on g.lauf_id = l.id
 group by l.id, l.charge_nr, c.sorte, c.schlag, l.auftrag_id, l.datei_name,
          l.datei_zeit, l.zuordnung with no data;

create or replace view v_sortier_lauf_masse with (security_invoker = true) as
select * from mv_sortier_lauf_masse;

create or replace view v_auftrag_angabe with (security_invoker = true) as
select distinct on (auftrag_id, schluessel)
       auftrag_id, schluessel, wert, ts, erfasser
  from auftrag_angabe
 order by auftrag_id, schluessel, ts desc, id desc;
drop function if exists schimmel_n(numeric);

-- aus 0049_betriebsleiter_kennzahlen.sql

create or replace view v_gewichtsverteilung with (security_invoker = true) as
select c.sorte, c.schlag, l.charge_nr,
       (g.gewicht_g / 25) * 25 as stufe_g,
       sum(g.anzahl)::bigint   as n
  from sortier_gewicht g
  join sortier_lauf l on l.id = g.lauf_id
  join charge c on c.nr = l.charge_nr
  left join auftrag a on a.id = l.auftrag_id
 where a.id is null or a.abgebrochen_ts is null
 group by c.sorte, c.schlag, l.charge_nr, (g.gewicht_g / 25) * 25;

create or replace view v_ausgang_artikel_vorschlag with (security_invoker = true) as
 WITH zeile_charge AS (
         SELECT z.id,
            z.artikel_id,
            z.artikel,
            z.datum,
            z.kg_charge,
            c.nr AS charge_nr,
            c.sorte
           FROM ausgang_zeile z
             CROSS JOIN LATERAL ( SELECT NULLIF(regexp_replace(z.charge_extern, '\D'::text, ''::text, 'g'::text), ''::text)::bigint AS nummer) x
             LEFT JOIN LATERAL ( SELECT c_1.nr,
                    c_1.sorte
                   FROM charge c_1
                  WHERE x.nummer IS NOT NULL AND (c_1.nr = x.nummer OR c_1.perigon_nr = x.nummer)
                  ORDER BY (c_1.nr = x.nummer) DESC, c_1.nr
                 LIMIT 1) c ON true
        ), beobachtet AS (
         SELECT zeile_charge.artikel_id,
            zeile_charge.artikel,
            count(*)::integer AS zeilen,
            min(zeile_charge.datum) AS von,
            max(zeile_charge.datum) AS bis,
            sum(zeile_charge.kg_charge) AS kg,
            count(*) FILTER (WHERE zeile_charge.charge_nr IS NOT NULL)::integer AS zeilen_mit_charge
           FROM zeile_charge
          GROUP BY zeile_charge.artikel_id, zeile_charge.artikel
        ), sorte_je_artikel AS (
         SELECT DISTINCT ON (zeile_charge.artikel_id, zeile_charge.artikel) zeile_charge.artikel_id,
            zeile_charge.artikel,
            zeile_charge.sorte,
            count(*)::integer AS n
           FROM zeile_charge
          WHERE zeile_charge.charge_nr IS NOT NULL
          GROUP BY zeile_charge.artikel_id, zeile_charge.artikel, zeile_charge.sorte
          ORDER BY zeile_charge.artikel_id, zeile_charge.artikel, (count(*)) DESC, zeile_charge.sorte
        )
 SELECT b.artikel_id,
    b.artikel,
    b.zeilen,
    b.von,
    b.bis,
    zahl(b.kg, 1, 1e13)::numeric(14,1) AS kg,
    b.zeilen_mit_charge,
    a.ist_kuerbis AS bestaetigt_kuerbis,
    a.sorte AS bestaetigte_sorte,
    a.artikel_id IS NOT NULL AS bestaetigt,
    lower((b.artikel_id || ' '::text) || b.artikel) ~ 'k(ü|u|ue)rb'::text AND lower((b.artikel_id || ' '::text) || b.artikel) !~ '(verrechnung|arbeit|lohn|transport|miete)'::text AS vorschlag_kuerbis,
    s.sorte AS vorschlag_sorte,
    s.n AS vorschlag_belege
   FROM beobachtet b
     LEFT JOIN ausgang_artikel a ON a.artikel_id = b.artikel_id AND a.artikel = b.artikel
     LEFT JOIN sorte_je_artikel s ON s.artikel_id = b.artikel_id AND s.artikel = b.artikel;

create or replace view v_ausgang_lage with (security_invoker = true) as
 SELECT code AS quelle,
    name,
    (( SELECT count(*) AS count
           FROM ausgang_zeile z
          WHERE z.quelle = q.code))::integer AS zeilen,
    ( SELECT min(z.datum) AS min
           FROM ausgang_zeile z
          WHERE z.quelle = q.code) AS von,
    ( SELECT max(z.datum) AS max
           FROM ausgang_zeile z
          WHERE z.quelle = q.code) AS bis,
    ( SELECT max(d.ts) AS max
           FROM ausgang_datei d
          WHERE d.quelle = q.code) AS zuletzt_geladen,
    (( SELECT count(*) AS count
           FROM ausgang_datei d
          WHERE d.quelle = q.code))::integer AS dateien,
    (( SELECT count(*) AS count
           FROM lieferung_import i
          WHERE i.quelle = q.code))::integer AS lieferungen,
    zahl((( SELECT COALESCE(sum(l.kg), 0::numeric) AS "coalesce"
           FROM lieferung_import i
             JOIN lieferung l ON l.id = i.lieferung_id
          WHERE i.quelle = q.code)), 1, 1e13)::numeric(14,1) AS kg,
    (( SELECT count(*) AS count
           FROM v_ausgang_artikel_vorschlag v
          WHERE NOT v.bestaetigt AND v.vorschlag_kuerbis AND (EXISTS ( SELECT 1
                   FROM ausgang_zeile z
                  WHERE z.quelle = q.code AND z.artikel_id = v.artikel_id AND z.artikel = v.artikel))))::integer AS artikel_offen
   FROM ausgang_quelle q;

create or replace view v_ausgang_pruef with (security_invoker = true) as
 WITH urteil AS (
         SELECT v_ausgang_artikel_vorschlag.artikel_id,
            v_ausgang_artikel_vorschlag.artikel,
            COALESCE(v_ausgang_artikel_vorschlag.bestaetigt_kuerbis, v_ausgang_artikel_vorschlag.vorschlag_kuerbis) AS kuerbis
           FROM v_ausgang_artikel_vorschlag
        ), pos AS (
         SELECT DISTINCT ON (z.quelle, z.pos_id) z.quelle,
            z.pos_id,
            z.datum,
            z.artikel_id,
            z.artikel,
            z.kunde,
            z.kg_position
           FROM ausgang_zeile z
          ORDER BY z.quelle, z.pos_id, z.lauf_nr
        ), geliefert AS (
         SELECT i.quelle,
            NULLIF(split_part(i.extern_id, ':'::text, 2), ''::text)::bigint AS pos_id,
            sum(l.kg) AS kg
           FROM lieferung_import i
             JOIN lieferung l ON l.id = i.lieferung_id
          GROUP BY i.quelle, (NULLIF(split_part(i.extern_id, ':'::text, 2), ''::text)::bigint)
        )
 SELECT p.quelle,
    p.pos_id,
    p.datum,
    p.artikel,
    p.kunde,
    zahl(p.kg_position, 2, 1e12)::numeric(14,2) AS kg_datei,
    zahl(COALESCE(g.kg, 0::numeric), 2, 1e12)::numeric(14,2) AS kg_lieferung,
    zahl((COALESCE(g.kg, 0::numeric) - p.kg_position), 2, 1e12)::numeric(14,2) AS abweichung_kg
   FROM pos p
     JOIN urteil u ON u.artikel_id = p.artikel_id AND u.artikel = p.artikel AND u.kuerbis
     LEFT JOIN geliefert g ON g.quelle = p.quelle AND g.pos_id = p.pos_id
  WHERE abs(COALESCE(g.kg, 0::numeric) - p.kg_position) > 0.05 AND p.kg_position > 0::numeric;
drop function if exists verlust_ranking(text, text, numeric);
drop function if exists verlust_ranking(text, text, numeric, int);

create or replace view v_verkauf_lieferung with (security_invoker = true) as
with position as (
  select quelle, pos_id,
         max(gebinde_menge)                                                    as gebinde_menge,
         max(kg_position)                                                      as kg_position,
         sum(batch_gebinde)      filter (where charge_extern <> '')             as batch_gebinde_summe,
         bool_and(batch_gebinde is not null) filter (where charge_extern <> '') as alle_gezaehlt
    from ausgang_zeile
   group by quelle, pos_id
), band as (

  select distinct on (s.sorte, i.idx) s.sorte, i.idx as kaliber_idx,
         (s.kaliber_baender -> i.idx ->> 0)::int as von,
         (s.kaliber_baender -> i.idx ->> 1)::int as bis
    from sortierschema s
    cross join lateral generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) as i(idx)
   where s.art = 'kaliber' and s.kaliber_baender is not null and s.kaeufer is null
     and s.gilt_ab <= heute()
   order by s.sorte, i.idx, s.gilt_ab desc
)
select l.id                                                                     as lieferung_id,
       l.datum, l.charge_nr,
       coalesce(l.sorte, c.sorte)                                               as sorte,
       l.kg, i.quelle, z.artikel, z.einheit, z.gebinde_inhalt, z.gewicht_je_artikel,
       ks.kistensystem,
       case when ks.kistensystem = 'kiste_ab' then zahl(z.gebinde_inhalt, 2, 1e4)::numeric(6,2) end as soll_kg_pro_kiste,
       case when ks.kistensystem = 'stueck'   then z.gebinde_inhalt end          as stueck_je_kiste,
       case when ks.kistensystem = 'stueck'   then round(z.gewicht_je_artikel * 1000)::int end as nenn_g,
       case when ks.kistensystem = 'stueck'   then b.kaliber_idx end             as kaliber_idx,
       zahl(k.kisten, 1, 1e7)::numeric(10,1)                                    as kisten,
       k.kisten_quelle,
       case when ks.kistensystem = 'stueck'
            then zahl(k.kisten * z.gebinde_inhalt, 0, 1e9)::numeric(12,0) end    as stueck
  from lieferung l
  join lieferung_import i on i.lieferung_id = l.id
  join ausgang_zeile z    on z.id = i.zeile_id
  join position p         on p.quelle = z.quelle and p.pos_id = z.pos_id
  left join charge c      on c.nr = l.charge_nr
  cross join lateral (
    select case when z.einheit ~* '^stk' and coalesce(z.gebinde_inhalt, 0) > 0
                     and coalesce(z.gewicht_je_artikel, 0) > 0                 then 'stueck'
                when z.einheit ~* '^kg' and coalesce(z.gebinde_inhalt, 0) > 1   then 'kiste_ab'
                else 'unbekannt' end::text as kistensystem) ks
  left join band b on ks.kistensystem = 'stueck' and b.sorte = coalesce(l.sorte, c.sorte)
                  and round(z.gewicht_je_artikel * 1000) >= b.von and round(z.gewicht_je_artikel * 1000) < b.bis
  cross join lateral (
    select case

             when i.extern_id not like '%:rest' and z.batch_gebinde > 0
               then z.batch_gebinde::numeric

             when i.extern_id like '%:rest' and coalesce(p.alle_gezaehlt, true) and p.gebinde_menge > 0
               then greatest(p.gebinde_menge - coalesce(p.batch_gebinde_summe, 0), 0)::numeric

             when p.gebinde_menge > 0 and p.kg_position > 0
               then p.gebinde_menge * l.kg / p.kg_position
           end as kisten,
           case
             when i.extern_id not like '%:rest' and z.batch_gebinde > 0 then 'zeile'
             when i.extern_id like '%:rest' and coalesce(p.alle_gezaehlt, true) and p.gebinde_menge > 0 then 'rest'
             when p.gebinde_menge > 0 and p.kg_position > 0 then 'anteil'
           end::text as kisten_quelle) k
 where l.ziel = 'verkauf' and ks.kistensystem is not null;

-- aus 0064_leer_ist_nicht_null.sql

create or replace view v_palette with (security_invoker = true) as
select p.id, p.charge_nr, p.eingangsdatum, p.brutto_kg, p.kisten, p.gebindeart,
       p.brutto_kg - p.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette as netto_kg
  from palette p
  left join gebinde g on g.art = p.gebindeart;

-- aus 0021_fehlende_tara_und_ueberzaehlung.sql

create or replace view v_charge_rueckgrat with (security_invoker = true) as
select c.nr as charge_nr, c.schlag, c.sorte, c.saison,
       count(p.id)                                     as n_paletten,
       count(p.netto_kg)                               as n_paletten_mit_netto,

       (sum(p.netto_kg) / nullif(count(p.netto_kg), 0) * count(p.id))
                                                       as eingang_netto_kg,
       sum(p.brutto_kg)                                as eingang_brutto_kg,
       min(p.eingangsdatum)                            as erster_eingang,
       max(p.eingangsdatum)                            as letzter_eingang,
       '2000-01-01'::date + (sum((p.eingangsdatum - '2000-01-01'::date)::numeric
              * coalesce(p.netto_kg, 1)) / nullif(sum(coalesce(p.netto_kg, 1)), 0))::int
                                                       as eingangsdatum_mittel,
       sum(p.netto_kg)                                 as eingang_netto_gemessen_kg
  from charge c
  left join v_palette p on p.charge_nr = c.nr
 group by c.nr, c.schlag, c.sorte, c.saison;

create view v_datenlage with (security_invoker = true) as
select r.charge_nr, r.sorte, r.schlag, r.n_paletten,

       r.n_paletten_mit_netto, r.eingang_netto_kg as eingang_kg,
       (select count(*) from verdunstung_wiegung w where w.charge_nr = r.charge_nr) as n_wiegungen,
       (select count(*) from auftrag a join schimmel_messung s on s.auftrag_id = a.id
         where a.charge_nr = r.charge_nr)                                           as n_schimmel,
       (select count(*) from sortier_lauf l where l.charge_nr = r.charge_nr)        as n_sortierlaeufe,
       (select count(*) from auftrag a where a.charge_nr = r.charge_nr)             as n_auftraege
  from v_charge_rueckgrat r;

create or replace view v_charge_kohorte with (security_invoker = true) as
with gezaehlt as (
  select a.charge_nr,
         coalesce(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum) as eingangsdatum,
         count(*)::int                                                 as n
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join palette p on p.id = ap.palette_id
    left join verdunstung_wiegung w on w.id = ap.wiegung_id
   where a.abgebrochen_ts is null
     and a.station in ('sortieren', 'waschen_sortieren')
   group by a.charge_nr, coalesce(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum)
), je_datum as (
  select p.charge_nr, p.eingangsdatum, count(*)::int as n,
         avg(p.netto_kg) as netto_mittel
    from v_palette p group by p.charge_nr, p.eingangsdatum
), charge_netto as (
  select charge_nr, avg(netto_kg) as netto from v_palette group by charge_nr
)
select d.charge_nr, d.eingangsdatum,
       d.n                                                          as n_paletten,
       coalesce(g.n, 0)                                             as n_verarbeitet,
       greatest(d.n - coalesce(g.n, 0), 0)                          as n_rest,
       zahl(coalesce(d.netto_mittel, cn.netto), 2, 1e8)::numeric(10,2) as netto_je_palette,
       zahl(greatest(d.n - coalesce(g.n, 0), 0)
            * coalesce(d.netto_mittel, cn.netto), 2, 1e10)::numeric(12,2) as rest_kg,
       (current_date - d.eingangsdatum)                             as alter_heute,

       zahl(d.n * coalesce(d.netto_mittel, cn.netto), 2, 1e10)::numeric(12,2) as eingang_kg
  from je_datum d
  join charge_netto cn on cn.charge_nr = d.charge_nr
  left join gezaehlt g on g.charge_nr = d.charge_nr and g.eingangsdatum = d.eingangsdatum;

create or replace view v_kohorte_anteil with (security_invoker = true) as
select charge_nr, eingangsdatum, n_rest, rest_kg,
       zahl(eingang_kg / nullif(sum(eingang_kg) over (partition by charge_nr), 0), 6, 1e4)::numeric(10,6) as anteil
  from v_charge_kohorte
 where eingang_kg > 0;

create or replace view v_verarbeitung_alter with (security_invoker = true) as
with tage as materialized (
  select a.id, a.charge_nr, a.station, a.weg, betriebstag(a.start_ts) as tag
    from auftrag a
   where a.abgebrochen_ts is null
), gezaehlt as (
  select t.id as auftrag_id, count(*)::int as n_paletten,
         zahl(avg(t.tag - ap.eingangsdatum), 1, 1e9)::numeric(10,1) as alter_verarbeitet
    from tage t
    join auftrag_palette ap on ap.auftrag_id = t.id
   where ap.eingangsdatum is not null
   group by t.id
), charge_am_tag as (
  select t.id as auftrag_id,
         zahl(avg(t.tag - p.eingangsdatum), 1, 1e9)::numeric(10,1) as alter_charge
    from tage t
    join palette p on p.charge_nr = t.charge_nr and p.eingangsdatum <= t.tag
   group by t.id
)
select t.id as auftrag_id, t.charge_nr, c.sorte, c.schlag, t.station, t.weg, t.tag,
       g.n_paletten, g.alter_verarbeitet, l.alter_charge,
       zahl(g.alter_verarbeitet - l.alter_charge, 1, 1e9)::numeric(10,1) as differenz
  from tage t
  join charge c on c.nr = t.charge_nr
  join gezaehlt g on g.auftrag_id = t.id
  left join charge_am_tag l on l.auftrag_id = t.id
 where t.station <> 'waschen'::station;

create or replace view v_charge_erntespanne with (security_invoker = true) as
select p.charge_nr,
       count(*)::int                                                   as n_paletten,
       min(p.eingangsdatum)                                            as erster_tag,
       max(p.eingangsdatum)                                            as letzter_tag,
       (max(p.eingangsdatum) - min(p.eingangsdatum))::int               as spanne_tage,
       zahl(sqrt(nullif(
         sum(p.netto_kg * power((p.eingangsdatum - r.eingangsdatum_mittel)::numeric, 2))
         / nullif(sum(p.netto_kg), 0), 0)), 1, 100000)::numeric(6,1)   as streuung_tage,
       c.ernte_abgeschlossen_ts is not null
         or coalesce((select (wert #>> '{}')::boolean from einstellung
                       where schluessel = 'ernte_abgeschlossen'), false) as ernte_fertig
  from v_palette p
  join charge c on c.nr = p.charge_nr
  join v_charge_rueckgrat r on r.charge_nr = p.charge_nr
 where p.netto_kg is not null
 group by p.charge_nr, c.ernte_abgeschlossen_ts, r.eingangsdatum_mittel;

create or replace view v_kontrollpalette_rate with (security_invoker = true) as
with w as (
  select k.id as kontrollpalette_id, k.charge_nr, c.sorte, k.kennzeichen,
         wg.wiege_ts, wg.sichtbar_schimmel,
         case when g.tara_kg_pro_kiste is null or g.tara_kg_palette is null then null
              else wg.brutto_kg - wg.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette end as netto_kg
    from kontrollpalette_wiegung wg
    join kontrollpalette k on k.id = wg.kontrollpalette_id
    join charge c on c.nr = k.charge_nr
    left join gebinde g on g.art = wg.gebindeart
),
paar as (
  select w.*,
         lag(wiege_ts)          over p as von_ts,
         lag(netto_kg)          over p as netto_von_kg,
         lag(sichtbar_schimmel) over p as schimmel_von
    from w
  window p as (partition by kontrollpalette_id order by wiege_ts, netto_kg)
)
select kontrollpalette_id, charge_nr, sorte, kennzeichen,
       von_ts, wiege_ts as bis_ts,
       (betriebstag(wiege_ts) - betriebstag(von_ts))::int as tage,
       netto_von_kg, netto_kg as netto_bis_kg,
       case when netto_von_kg > 0 and netto_kg > 0
             and betriebstag(wiege_ts) > betriebstag(von_ts)
            then zahl(1 - power(netto_kg / netto_von_kg,
                                1.0 / (betriebstag(wiege_ts) - betriebstag(von_ts))::numeric),
                      6, 1)::numeric(9,6)
       end as rate_je_tag,

       (netto_von_kg is not null and netto_kg is not null
        and not coalesce(schimmel_von, false) and not sichtbar_schimmel
        and (betriebstag(wiege_ts) - betriebstag(von_ts)) >= 7
        and netto_kg <= netto_von_kg) as verwendbar
  from paar
 where von_ts is not null;

create or replace view v_kontrollpalette_vorschlag with (security_invoker = true) as
select r.charge_nr, c.sorte, c.schlag, r.eingang_netto_kg,
       rank() over (order by r.eingang_netto_kg desc nulls last) as rang,
       exists (select 1 from kontrollpalette k
                where k.charge_nr = r.charge_nr and k.beendet_ts is null) as hat_schon
  from v_charge_rueckgrat r
  join charge c on c.nr = r.charge_nr
 where r.eingang_netto_kg > 0;

create or replace view v_sortier_lesung with (security_invoker = true) as
select l.id, l.charge_nr, c.sorte, c.schlag, l.datei_name, l.art,
       l.von_ts, l.bis_ts, l.sortiertag, l.sortiertag_quelle,
       l.vorgaenger_id, l.voll_n_roh, l.n_roh, l.n_gueltig, l.gelesen_ts,
       l.zuordnung::text as zuordnung, l.auftrag_id,
       (select count(*) from sortier_gewicht g where g.lauf_id = l.id)::int as stufen,

       zahl((select coalesce(sum(g.anzahl::bigint * g.gewicht_g), 0) / 1000.0
               from sortier_gewicht g where g.lauf_id = l.id), 2, 1e10) as masse_kg,
       case l.sortiertag_quelle
         when 'datei'          then 'aus dem Dateinamen'
         when 'arbeit'         then 'aus der Sortier-Arbeit im Zeitraum'
         when 'arbeiten-mittel' then 'Mittel der Sortier-Arbeiten im Zeitraum'
         when 'fenster-mitte'  then 'Mitte des Zeitraums — geschätzt'
         when 'betriebsleiter' then 'von Hand gesetzt'
         when 'dateistempel'   then 'Zeitstempel der Datei — kein Sortierdatum'
         when 'gelesen'        then 'Tag des Einlesens — geschätzt'
         else 'nicht bekannt'
       end                                                                  as sortiertag_text
  from sortier_lauf l
  join charge c on c.nr = l.charge_nr;

create or replace view v_palox_stand with (security_invoker = true) as
select s.id,
       s.auftrag_id,
       s.ts,
       s.palox_stand_kg,
       s.kg,
       lag(s.palox_stand_kg) over w                                  as vorher,
       case
         when s.palox_nach_leeren                          then 0
         when lag(s.palox_stand_kg) over w is null         then 0
         when s.palox_geleert                              then null
         when s.palox_stand_kg < lag(s.palox_stand_kg) over w then null
         else s.palox_stand_kg - lag(s.palox_stand_kg) over w
       end                                                          as differenz,
       (s.palox_geleert
        or (lag(s.palox_stand_kg) over w is not null
            and s.palox_stand_kg < lag(s.palox_stand_kg) over w))
       and not s.palox_nach_leeren                                   as zwischendurch_geleert,
       palox_station(a.station)                                      as station,
       s.palox_nach_leeren                                           as nach_leeren
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
 where s.palox_stand_kg is not null and s.gemessen
window w as (partition by s.auftrag_id order by s.ts, s.id)
 order by s.auftrag_id, s.ts, s.id;

create or replace view v_schimmel_menge with (security_invoker = true) as
select s.auftrag_id,
       sum(case when s.palox_stand_kg is null then s.kg else p.differenz end)::numeric as kg,
       count(*)::int as n_ablesungen
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
  left join v_palox_stand p on p.id = s.id
 where s.gemessen and not a.palox_unbekannt
 group by s.auftrag_id
having bool_and(s.palox_stand_kg is null or p.differenz is not null)
   and (count(*) filter (where s.palox_stand_kg is not null) = 0
     or count(*) filter (where s.palox_stand_kg is not null) >= 2);

create or replace view v_arbeit_kommentar with (security_invoker = true) as
select r.auftrag_id,
       coalesce(r.kurz_charge_nr, a.charge_nr) as charge_nr,
       string_agg(r.kurz, ' · ' order by r.ts) as text,
       bool_or(r.audio_ref is not null) as mit_aufnahme,
       max(r.ts) as ts,
       string_agg(coalesce(nullif(btrim(r.text), ''), r.transkript, '(nur Aufnahme)'), ' · ' order by r.ts) as roh,
       count(*)::int as n
  from auftrag_rueckmeldung r
  join auftrag a on a.id = r.auftrag_id
 where r.art = 'ware'
   and r.kurz is not null
 group by r.auftrag_id, coalesce(r.kurz_charge_nr, a.charge_nr);

-- aus 0097_was_der_betrieb_am_ersten_tag_sah.sql

create or replace view v_ausgang_kennzahl with (security_invoker = true) as
with grenzen as (

  select distinct s.sorte, (e.band ->> 0)::int as von, (e.band ->> 1)::int as bis
    from sortierschema s
    cross join lateral jsonb_array_elements(s.kaliber_baender) as e(band)
   where s.art = 'kaliber' and s.kaliber_baender is not null
  union
  select distinct c.sorte, a.kaliber_von_g, a.kaliber_bis_g
    from auftrag a join charge c on c.nr = a.charge_nr
   where a.kaliber_von_g is not null and a.kaliber_bis_g is not null
), band_mittel as (

  select g.sorte, g.von, g.bis,
         sum(sg.anzahl::bigint * sg.gewicht_g)::numeric / nullif(sum(sg.anzahl), 0) as gramm
    from grenzen g
    join charge c on c.sorte = g.sorte
    join sortier_lauf l on l.charge_nr = c.nr
    join sortier_gewicht sg on sg.lauf_id = l.id and sg.gewicht_g >= g.von and sg.gewicht_g < g.bis
   group by g.sorte, g.von, g.bis
)
select w.id, w.auftrag_id, w.charge_nr, c.sorte, c.schlag, w.ts, w.brutto_kg, w.kisten,
       w.gebindeart, w.kuerbisse_pro_kiste, n.netto_kg,
       zahl(n.netto_kg / w.kisten, 3, 1e7)::numeric(10,3)                          as kg_pro_kiste,
       zahl(n.netto_kg / nullif(w.kisten * w.kuerbisse_pro_kiste, 0), 3, 1e7)::numeric(10,3) as kg_pro_kuerbis,
       s.soll::numeric                                                              as soll_kg_pro_kiste,
       zahl(case when s.soll is not null then n.netto_kg / w.kisten - s.soll end, 3, 1e7)::numeric(10,3)
                                                                                    as ueberfuellung_je_kiste,
       zahl(case when s.soll is not null then n.netto_kg - w.kisten * s.soll end, 2, 1e8)::numeric(10,2)
                                                                                    as ueberfuellung_kg,

       coalesce(a.kistensystem, case when ss.art = 'kiste' then 'kiste_ab' end)::text as kistensystem,
       w.kaliber_idx,
       e.stueck                                                                     as stueck_je_kiste,
       zahl(e.stueck * bm.gramm / 1000.0, 3, 1e7)::numeric(10,3)                    as erwartet_kg_pro_kiste,
       zahl(n.netto_kg / w.kisten - e.stueck * bm.gramm / 1000.0, 3, 1e7)::numeric(10,3)
                                                                                    as abweichung_je_kiste,
       zahl(bm.gramm, 0, 1e6)::numeric(8,0)                                         as band_mittel_g,

       bd.von                                                                       as band_von_g,
       bd.bis                                                                       as band_bis_g
  from ausgang_wiegung w
  join auftrag a on a.id = w.auftrag_id
  join charge c on c.nr = w.charge_nr
  left join gebinde g on g.art = w.gebindeart
  left join sortierschema ss on ss.id = a.sortierschema_id
  cross join lateral (
    select zahl(w.brutto_kg - w.kisten * g.tara_kg_pro_kiste - coalesce(g.tara_kg_palette, 0), 2, 1e8)::numeric(10,2) as netto_kg) n
  cross join lateral (
    select case when a.kistensystem = 'kiste_ab' then a.soll_kg_pro_kiste
                when a.kistensystem is null and ss.art = 'kiste' then ss.soll_kg_pro_kiste end as soll) s
  cross join lateral (
    select case when a.kistensystem = 'stueck' then coalesce(w.kuerbisse_pro_kiste, a.stueck_je_kiste) end as stueck) e
  cross join lateral (
    select case when w.kaliber_idx = -2 then null else coalesce(w.kaliber_idx, a.kaliber_idx) end as idx) i
  cross join lateral (

    select case when i.idx is null then a.kaliber_von_g else (f.baender -> i.idx ->> 0)::int end as von,
           case when i.idx is null then a.kaliber_bis_g else (f.baender -> i.idx ->> 1)::int end as bis
      from (select coalesce(ss.kaliber_baender,
                            (select x.kaliber_baender from sortierschema x
                              where x.sorte = c.sorte and x.art = 'kaliber' and x.kaeufer is null
                                and x.kaliber_baender is not null
                              order by x.gilt_ab desc limit 1)) as baender) f) bd
  left join band_mittel bm on bm.sorte = c.sorte and bm.von = bd.von and bm.bis = bd.bis
 where w.gemessen and a.abgebrochen_ts is null and n.netto_kg > 0;

create or replace view v_lieferung_masse with (security_invoker = true) as
with kiste as (

  select avg(kg_pro_kiste)                            as mittel,
         stddev_samp(kg_pro_kiste)                    as sd,
         count(*)::int                                as n
    from v_ausgang_kennzahl where kg_pro_kiste is not null
)
select l.*, z.name as ziel_name, z.buch,
       coalesce(l.kg, l.kisten * k.mittel)                          as masse_kg,
       case when l.kg is not null then 'gewogen'
            when k.n > 0          then 'aus Kisten hochgerechnet'
            else 'Kistengewicht unbekannt' end                      as masse_quelle,

       case when l.kg is not null then 0
            when k.n >= 2 then l.kisten * t_quantil_95(k.n - 1) * k.sd / sqrt(k.n)
       end                                                          as masse_fehler_kg,
       k.n                                                          as kisten_n
  from lieferung l
  join ausgang_ziel z on z.code = l.ziel
  cross join kiste k;

create or replace view v_koeff_ueberfuellung with (security_invoker = true) as
 WITH roh AS (
         SELECT k.ueberfuellung_kg AS wert,
            k.kisten AS n_kisten,
            k.ueberfuellung_je_kiste AS je_kiste
           FROM v_ausgang_kennzahl k
          WHERE k.ueberfuellung_je_kiste IS NOT NULL
        ), s AS (
         SELECT count(*)::integer AS n,
            sum(roh.wert) / NULLIF(sum(roh.n_kisten), 0)::numeric AS kg_pro_kiste,
            stddev_samp(roh.je_kiste) AS sd
           FROM roh
        )
 SELECT n,
    zahl(kg_pro_kiste, 3, 1e7)::numeric(10,3) AS kg_pro_kiste,
    zahl(sd, 3, 1e7)::numeric(10,3) AS sd,
        zahl(CASE
            WHEN sd IS NULL OR n < 2 THEN kg_pro_kiste::double precision
            ELSE GREATEST(kg_pro_kiste::double precision - (1.96 * sd)::double precision / sqrt(n::double precision), 0::double precision)
        END, 3, 1e7)::numeric(10,3) AS unten,
        zahl(CASE
            WHEN sd IS NULL OR n < 2 THEN kg_pro_kiste::double precision
            ELSE kg_pro_kiste::double precision + (1.96 * sd)::double precision / sqrt(n::double precision)
        END, 3, 1e7)::numeric(10,3) AS oben
   FROM s;

create or replace view v_ueberfuellung_verkauf with (security_invoker = true) as
with verkauft as (
  select case when grouping(v.charge_nr) = 1 then 'sorte' else 'charge' end as gruppe,
         v.sorte, v.charge_nr, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx,
         count(*)::int as n_lieferungen, sum(v.kg) as kg_verkauft, sum(v.kisten) as kisten_verkauft,
         count(*) filter (where v.kisten_quelle = 'anteil')::int as n_anteilig,
         sum(v.stueck) as stueck_verkauft,
         sum(v.stueck * v.nenn_g::numeric) / nullif(sum(v.stueck), 0) as nenn_g,
         min(v.datum) as von, max(v.datum) as bis
    from v_verkauf_lieferung v
   where v.sorte is not null
   group by grouping sets ((v.sorte, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx),
                           (v.sorte, v.charge_nr, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx))
), gewogen as (
  select case when grouping(k.charge_nr) = 1 then 'sorte' else 'charge' end as gruppe,
         k.sorte, k.charge_nr, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
         case when k.kistensystem = 'stueck' then k.kaliber_idx end as kaliber_idx,
         count(*)::int as n_wiegungen, sum(k.kisten) as kisten_gewogen,
         sum(k.netto_kg) / nullif(sum(k.kisten), 0)::numeric as kg_je_kiste,
         stddev_samp(k.kg_pro_kiste) as sd_je_kiste,
         sum(k.ueberfuellung_kg) as zuviel_gewogen_kg,
         sum(k.netto_kg) / nullif(sum(k.kisten * k.stueck_je_kiste), 0)::numeric * 1000 as g_je_kuerbis,
         max(k.band_mittel_g) as band_mittel_g
    from v_ausgang_kennzahl k
   where k.kistensystem in ('kiste_ab', 'stueck')
     and (k.kistensystem <> 'kiste_ab' or k.soll_kg_pro_kiste is not null)
     and (k.kistensystem <> 'stueck'   or k.stueck_je_kiste  is not null)
   group by grouping sets ((k.sorte, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
                            (case when k.kistensystem = 'stueck' then k.kaliber_idx end)),
                           (k.sorte, k.charge_nr, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
                            (case when k.kistensystem = 'stueck' then k.kaliber_idx end)))
), band as (
  select distinct on (s.sorte, i.idx) s.sorte, i.idx as kaliber_idx,
         ((s.kaliber_baender -> i.idx) ->> 0)::int as von,
         ((s.kaliber_baender -> i.idx) ->> 1)::int as bis
    from sortierschema s
    cross join lateral generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) i(idx)
   where s.art = 'kaliber' and s.kaliber_baender is not null and s.kaeufer is null and s.gilt_ab <= heute()
   order by s.sorte, i.idx, s.gilt_ab desc
)
select coalesce(v.gruppe, g.gruppe)                       as gruppe,
       coalesce(v.sorte, g.sorte)                         as sorte,
       coalesce(v.charge_nr, g.charge_nr)                 as charge_nr,
       coalesce(v.kistensystem, g.kistensystem)           as kistensystem,
       coalesce(v.soll_kg_pro_kiste, g.soll_kg_pro_kiste) as soll_kg_pro_kiste,
       coalesce(v.stueck_je_kiste, g.stueck_je_kiste)     as stueck_je_kiste,
       coalesce(v.kaliber_idx, g.kaliber_idx)             as kaliber_idx,
       b.von as band_von_g, b.bis as band_bis_g,
       zahl(v.nenn_g, 0, 1e6)::numeric(8,0)               as nenn_g,
       coalesce(v.n_lieferungen, 0)                       as n_lieferungen,
       zahl(v.kg_verkauft, 1, 1e11)::numeric(12,1)        as kg_verkauft,
       zahl(v.kisten_verkauft, 0, 1e9)::numeric(12,0)     as kisten_verkauft,
       coalesce(v.n_anteilig, 0)                          as n_anteilig,
       zahl(v.stueck_verkauft, 0, 1e9)::numeric(12,0)     as stueck_verkauft,
       v.von, v.bis,
       coalesce(g.n_wiegungen, 0)                         as n_wiegungen,
       g.kisten_gewogen,
       zahl(g.kg_je_kiste, 3, 1e7)::numeric(10,3)         as kg_je_kiste,
       zahl(g.sd_je_kiste, 3, 1e7)::numeric(10,3)         as sd_je_kiste,
       zahl(g.kg_je_kiste - g.soll_kg_pro_kiste, 3, 1e7)::numeric(10,3) as zuviel_je_kiste,
       zahl(g.zuviel_gewogen_kg, 1, 1e11)::numeric(12,1)  as zuviel_gewogen_kg,
       zahl(case when g.n_wiegungen > 0 and v.kisten_verkauft is not null and g.kistensystem = 'kiste_ab'
                 then greatest(g.kg_je_kiste - g.soll_kg_pro_kiste, 0) * v.kisten_verkauft
                 else null::numeric end,
            1, 1e11)::numeric(12,1)                       as verschenkt_kg,
       zahl(case when g.n_wiegungen >= 2 and v.kisten_verkauft is not null and g.kistensystem = 'kiste_ab'
                 then (t_quantil_95(g.n_wiegungen - 1) * g.sd_je_kiste)::double precision
                      / sqrt(g.n_wiegungen::double precision) * v.kisten_verkauft::double precision end,
            1, 1e11)::numeric(12,1)                       as verschenkt_fehler_kg,
       zahl(g.g_je_kuerbis, 0, 1e6)::numeric(8,0)         as g_je_kuerbis,
       zahl(g.band_mittel_g, 0, 1e6)::numeric(8,0)        as band_mittel_g,

       zahl(case when b.von is not null and b.bis is not null and b.bis > b.von and g.g_je_kuerbis is not null
                 then (g.g_je_kuerbis - b.von) / (b.bis - b.von)::numeric end,
            4, 1e4)::numeric(8,4)                         as lage_im_band,
       zahl(case when g.g_je_kuerbis is not null and b.von is not null and v.stueck_verkauft is not null
                 then (g.g_je_kuerbis - b.von) / 1000.0 * v.stueck_verkauft end,
            1, 1e11)::numeric(12,1)                       as spielraum_kg
  from verkauft v
  full join gewogen g
    on g.gruppe = v.gruppe and g.sorte = v.sorte and g.charge_nr is not distinct from v.charge_nr
   and g.kistensystem = v.kistensystem
   and g.soll_kg_pro_kiste is not distinct from v.soll_kg_pro_kiste
   and g.stueck_je_kiste is not distinct from v.stueck_je_kiste
   and g.kaliber_idx is not distinct from v.kaliber_idx
  left join band b on b.sorte = coalesce(v.sorte, g.sorte)
                  and b.kaliber_idx = coalesce(v.kaliber_idx, g.kaliber_idx);
create materialized view erg_ueberfuellung as select * from v_ueberfuellung_verkauf with no data;

create or replace view v_ausgang_voll with (security_invoker = true) as
select k.id, k.auftrag_id, k.charge_nr, k.sorte, k.schlag, k.ts, k.brutto_kg, k.kisten,
       k.gebindeart, k.kuerbisse_pro_kiste, k.netto_kg, k.kg_pro_kiste, k.kg_pro_kuerbis,
       k.soll_kg_pro_kiste, k.ueberfuellung_je_kiste, k.ueberfuellung_kg, k.kistensystem,
       k.kaliber_idx, k.stueck_je_kiste, k.erwartet_kg_pro_kiste, k.abweichung_je_kiste,
       k.band_mittel_g,
       w.voll,

       k.band_von_g, k.band_bis_g
  from v_ausgang_kennzahl k
  join ausgang_wiegung w on w.id = k.id;

create or replace view v_koeff_palette_netto with (security_invoker = true) as
select sorte, kistensystem,
       count(*)::int                                              as n,
       zahl(avg(netto_kg), 2, 100000000)::numeric(10,2)           as netto_kg,
       zahl(stddev_samp(netto_kg), 2, 100000000)::numeric(10,2)   as sd,
       zahl(avg(kisten), 1, 1000000)::numeric(8,1)                as kisten
  from v_ausgang_voll k
 where coalesce(k.voll, true)
 group by grouping sets ((sorte, kistensystem), (sorte));

create or replace view v_auftrag_fertige_masse with (security_invoker = true) as
select a.id as auftrag_id,
       zahl(a.fertige_paletten_gesamt::numeric * coalesce(eig.netto_kg, kp.netto_kg),
            2, 10000000000)::numeric(12,2) as kg
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join (select v.auftrag_id, avg(v.netto_kg) as netto_kg
               from v_ausgang_voll v
              where coalesce(v.voll, true) and v.netto_kg > 0
              group by v.auftrag_id) eig on eig.auftrag_id = a.id
  left join lateral (
       select p.netto_kg
         from v_koeff_palette_netto p
        where p.sorte = c.sorte
          and (p.kistensystem = a.kistensystem
               or p.kistensystem is null and a.kistensystem is distinct from 'anderes')
        order by (p.kistensystem = a.kistensystem) desc nulls last
        limit 1) kp on true
 where a.station = 'waschen' and not a.ist_fax
   and coalesce(a.fertige_paletten_gesamt, 0) > 0
   and coalesce(eig.netto_kg, kp.netto_kg) is not null;

create or replace view v_marge_wiegung with (security_invoker = true) as
with w as (

  select k.*, coalesce(aw.voll, true) as voll
    from v_ausgang_kennzahl k
    join ausgang_wiegung aw on aw.id = k.id
   where k.kisten > 0 and k.netto_kg is not null and k.kistensystem is not null
)
select w.sorte, w.kistensystem,
       case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end   as soll_kg_pro_kiste,
       case when w.kistensystem = 'stueck'   then w.kaliber_idx end         as kaliber_idx,
       case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end     as stueck_je_kiste,
       case when w.kistensystem = 'stueck'   then w.band_mittel_g end       as band_mittel_g,
       count(*)::int                                                       as n_wiegungen,
       sum(w.kisten)::int                                                  as kisten,
       zahl(avg(w.kg_pro_kiste), 3, 1e4)::numeric(10,3)                    as kg_je_kiste,
       zahl(stddev_samp(w.kg_pro_kiste), 3, 1e4)::numeric(10,3)            as sd_je_kiste,

       zahl(avg(w.ueberfuellung_je_kiste), 3, 1e4)::numeric(10,3)          as zuviel_je_kiste,

       zahl(avg(w.kg_pro_kuerbis) * 1000, 0, 1e6)::numeric(8,0)            as g_je_kuerbis,
       zahl(avg(w.kg_pro_kuerbis) * 1000 - w.band_mittel_g, 0, 1e6)::numeric(8,0) as g_ueber_bandmitte,
       betriebstag(min(w.ts))                                              as von,
       betriebstag(max(w.ts))                                              as bis,

       case when w.kistensystem = 'stueck'   then w.band_von_g end         as band_von_g,
       case when w.kistensystem = 'stueck'   then w.band_bis_g end         as band_bis_g,
       count(*) filter (where w.voll)::int                                 as n_voll
  from w
 group by w.sorte, w.kistensystem,
          case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end,
          case when w.kistensystem = 'stueck'   then w.kaliber_idx end,
          case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end,
          case when w.kistensystem = 'stueck'   then w.band_mittel_g end,
          case when w.kistensystem = 'stueck'   then w.band_von_g end,
          case when w.kistensystem = 'stueck'   then w.band_bis_g end,
          w.band_mittel_g;

create or replace view v_marge_charge with (security_invoker = true) as
with w as (
  select k.*
    from v_ausgang_voll k
   where k.kisten > 0 and k.netto_kg is not null and k.kistensystem is not null
)
select w.charge_nr,
       w.sorte,
       w.schlag,
       w.kistensystem,
       case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end   as soll_kg_pro_kiste,
       case when w.kistensystem = 'stueck'   then w.kaliber_idx end         as kaliber_idx,
       case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end     as stueck_je_kiste,
       case when w.kistensystem = 'stueck'   then w.band_mittel_g end       as band_mittel_g,
       count(*)::int                                                       as n_wiegungen,
       sum(w.kisten)::int                                                  as kisten,
       zahl(avg(w.kg_pro_kiste), 3, 10000)::numeric(10,3)                  as kg_je_kiste,
       zahl(stddev_samp(w.kg_pro_kiste), 3, 10000)::numeric(10,3)          as sd_je_kiste,
       zahl(avg(w.ueberfuellung_je_kiste), 3, 10000)::numeric(10,3)        as zuviel_je_kiste,
       zahl(avg(w.kg_pro_kuerbis) * 1000, 0, 1000000)::numeric(8,0)        as g_je_kuerbis,
       zahl(avg(w.kg_pro_kuerbis) * 1000 - w.band_mittel_g, 0, 1000000)::numeric(8,0)
                                                                           as g_ueber_bandmitte,
       betriebstag(min(w.ts))                                              as von,
       betriebstag(max(w.ts))                                              as bis,
       case when w.kistensystem = 'stueck'   then w.band_von_g end         as band_von_g,
       case when w.kistensystem = 'stueck'   then w.band_bis_g end         as band_bis_g,
       count(*) filter (where w.voll)::int                                 as n_voll
  from w
 group by w.charge_nr, w.sorte, w.schlag, w.kistensystem,
          case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end,
          case when w.kistensystem = 'stueck'   then w.kaliber_idx end,
          case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end,
          case when w.kistensystem = 'stueck'   then w.band_mittel_g end,
          case when w.kistensystem = 'stueck'   then w.band_von_g end,
          case when w.kistensystem = 'stueck'   then w.band_bis_g end,
          w.band_mittel_g;

create materialized view erg_marge_wiegung as select * from v_marge_wiegung with no data;

create materialized view erg_marge_charge as select * from v_marge_charge with no data;

create or replace view v_auftrag_wasch_gewogen with (security_invoker = true) as
with p as (
  select ap.auftrag_id, ap.id, ap.kisten,
         case when ap.brutto_gewogen_kg is not null
               and g.tara_kg_pro_kiste is not null and g.tara_kg_palette is not null
               and ap.brutto_gewogen_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette > 0
              then ap.brutto_gewogen_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette
         end as netto_kg
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join gebinde g on g.art = ap.gebindeart
   where a.station = 'waschen' and not a.ist_fax and ap.kisten is not null and ap.kisten > 0
)
select auftrag_id,
       count(*)::int                                          as n_paletten,
       count(netto_kg)::int                                   as n_gewogen,
       coalesce(sum(kisten) filter (where netto_kg is not null), 0)::int as kisten_gewogen,
       coalesce(sum(kisten) filter (where netto_kg is null), 0)::int     as kisten_ungewogen,

       zahl(sum(netto_kg)
            + coalesce(sum(kisten) filter (where netto_kg is null), 0)
              * (sum(netto_kg) / nullif(sum(kisten) filter (where netto_kg is not null), 0)),
            2, 10000000000)::numeric(12,2)                    as kg,
       zahl(sum(netto_kg) / nullif(sum(kisten) filter (where netto_kg is not null), 0), 3, 10000000)::numeric(10,3)
                                                              as kg_je_kiste,
       case when count(netto_kg) = count(*) then 'gewogen_strasse' else 'gewogen_strasse_teils' end as quelle
  from p
 group by auftrag_id
having count(netto_kg) > 0;
drop function if exists schimmelanteil(numeric, text);
drop function if exists sockel_anteil();

-- aus 0109_die_rechnung_plant_klein.sql

create or replace view v_koeff_gebinde_formel with (security_invoker = true) as
 WITH gezaehlt AS (
         SELECT auftrag_gebinde.auftrag_id,
            auftrag_gebinde.kaliber_idx,
            sum(auftrag_gebinde.anzahl)::integer AS anzahl
           FROM auftrag_gebinde
          GROUP BY auftrag_gebinde.auftrag_id, auftrag_gebinde.kaliber_idx
        ), je_arbeit AS (
         SELECT a.id AS auftrag_id,
            c.sorte,
            g.kaliber_idx,
            g.anzahl,
            sum(sg.anzahl::bigint * sg.gewicht_g) / 1000.0 AS kg
           FROM gezaehlt g
             JOIN auftrag a ON a.id = g.auftrag_id AND a.abgebrochen_ts IS NULL
             JOIN charge c ON c.nr = a.charge_nr
             JOIN sortier_lauf l ON l.auftrag_id = a.id
             JOIN sortier_gewicht sg ON sg.lauf_id = l.id AND sg.klasse = 'kaliber'::kuerbis_klasse AND sg.kaliber_idx = g.kaliber_idx
          WHERE (a.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND g.anzahl > 0
          GROUP BY a.id, c.sorte, g.kaliber_idx, g.anzahl
        ), band AS (
         SELECT DISTINCT s_1.sorte,
            i.idx AS kaliber_idx,
            ((s_1.kaliber_baender -> i.idx) ->> 0)::integer AS von,
            ((s_1.kaliber_baender -> i.idx) ->> 1)::integer AS bis
           FROM sortierschema s_1
             CROSS JOIN LATERAL generate_series(0, jsonb_array_length(s_1.kaliber_baender) - 1) i(idx)
          WHERE s_1.art = 'kaliber'::text AND s_1.kaliber_baender IS NOT NULL
        ), je_wasch AS (
         SELECT a.id AS auftrag_id,
            c.sorte,
            COALESCE(a.kaliber_idx, e.kaliber_idx) AS kaliber_idx,
            sum(ap.kisten)::integer AS anzahl,
            a.fertige_paletten_gesamt::numeric * eig.netto_kg AS kg
           FROM auftrag a
             JOIN charge c ON c.nr = a.charge_nr
             JOIN auftrag_palette ap ON ap.auftrag_id = a.id AND ap.kisten IS NOT NULL
             JOIN ( SELECT v.auftrag_id,
                    avg(v.netto_kg) AS netto_kg
                   FROM v_ausgang_voll v
                  WHERE COALESCE(v.voll, true) AND v.netto_kg > 0::numeric
                  GROUP BY v.auftrag_id) eig ON eig.auftrag_id = a.id
             LEFT JOIN LATERAL ( SELECT b.kaliber_idx
                   FROM band b
                  WHERE a.kaliber_idx IS NULL AND b.sorte = c.sorte AND b.von = a.kaliber_von_g AND b.bis = a.kaliber_bis_g
                  ORDER BY b.kaliber_idx
                 LIMIT 1) e ON true
          WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL AND COALESCE(a.fertige_paletten_gesamt, 0) > 0
          GROUP BY a.id, c.sorte, (COALESCE(a.kaliber_idx, e.kaliber_idx)), a.fertige_paletten_gesamt, eig.netto_kg
         HAVING sum(ap.kisten) > 0 AND COALESCE(a.kaliber_idx, e.kaliber_idx) IS NOT NULL
        ), je_wasch_gewogen AS (
         SELECT a.id AS auftrag_id,
            c.sorte,
            COALESCE(a.kaliber_idx, e.kaliber_idx) AS kaliber_idx,
            wg.kisten_gewogen AS anzahl,
            wg.kg_je_kiste * wg.kisten_gewogen::numeric AS kg
           FROM v_auftrag_wasch_gewogen wg
             JOIN auftrag a ON a.id = wg.auftrag_id AND a.abgebrochen_ts IS NULL
             JOIN charge c ON c.nr = a.charge_nr
             LEFT JOIN LATERAL ( SELECT b.kaliber_idx
                   FROM band b
                  WHERE a.kaliber_idx IS NULL AND b.sorte = c.sorte AND b.von = a.kaliber_von_g AND b.bis = a.kaliber_bis_g
                  ORDER BY b.kaliber_idx
                 LIMIT 1) e ON true
          WHERE wg.kisten_gewogen > 0 AND COALESCE(a.kaliber_idx, e.kaliber_idx) IS NOT NULL
        ), s AS (
         SELECT q.sorte,
            q.kaliber_idx,
            count(*)::integer AS n,
            sum(q.kg) / NULLIF(sum(q.anzahl), 0)::numeric AS kg_je_gebinde,
            stddev_samp(q.kg / q.anzahl::numeric) AS sd
           FROM ( SELECT je_arbeit.sorte,
                    je_arbeit.kaliber_idx,
                    je_arbeit.anzahl,
                    je_arbeit.kg
                   FROM je_arbeit
                UNION ALL
                 SELECT je_wasch.sorte,
                    je_wasch.kaliber_idx,
                    je_wasch.anzahl,
                    je_wasch.kg
                   FROM je_wasch
                UNION ALL
                 SELECT je_wasch_gewogen.sorte,
                    je_wasch_gewogen.kaliber_idx,
                    je_wasch_gewogen.anzahl,
                    je_wasch_gewogen.kg
                   FROM je_wasch_gewogen) q
          GROUP BY q.sorte, q.kaliber_idx
        UNION ALL
         SELECT k.sorte,
            '-1'::integer,
            count(*)::integer AS count,
            sum(k.netto_kg) / NULLIF(sum(k.kisten), 0)::numeric,
            stddev_samp(k.kg_pro_kiste) AS stddev_samp
           FROM v_ausgang_kennzahl k
          WHERE k.soll_kg_pro_kiste IS NOT NULL OR k.kistensystem = 'kiste_ab'::text
          GROUP BY k.sorte
        )
 SELECT sorte,
    kaliber_idx,
    n,
    zahl(kg_je_gebinde, 3, 10000000::numeric)::numeric(10,3) AS kg_je_gebinde,
    zahl(sd, 3, 10000000::numeric)::numeric(10,3) AS sd,
    zahl(
        CASE
            WHEN sd IS NULL OR n < 2 THEN kg_je_gebinde::double precision
            ELSE GREATEST(kg_je_gebinde::double precision - (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision), 0::double precision)
        END, 3, 10000000::numeric)::numeric(10,3) AS unten,
    zahl(
        CASE
            WHEN sd IS NULL OR n < 2 THEN kg_je_gebinde::double precision
            ELSE kg_je_gebinde::double precision + (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision)
        END, 3, 10000000::numeric)::numeric(10,3) AS oben
   FROM s
  WHERE kg_je_gebinde IS NOT NULL;

create or replace function v_koeff_gebinde_zaun() returns setof v_koeff_gebinde_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_koeff_gebinde_formel;
end $$;

create or replace view v_koeff_gebinde with (security_invoker = true) as
select * from v_koeff_gebinde_zaun();

create or replace view v_auftrag_gebinde_masse with (security_invoker = true) as
with band as (
  select distinct s.sorte, i.idx as kaliber_idx,
         (s.kaliber_baender -> i.idx ->> 0)::int as von,
         (s.kaliber_baender -> i.idx ->> 1)::int as bis
    from sortierschema s
    cross join lateral generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) as i(idx)
   where s.art = 'kaliber' and s.kaliber_baender is not null
), gezaehlt as (
  select auftrag_id, kaliber_idx, sum(anzahl)::int as anzahl
    from auftrag_gebinde group by auftrag_id, kaliber_idx
)
select a.id as auftrag_id, g.kaliber_idx, g.anzahl,
       zahl(g.anzahl * k.kg_je_gebinde, 2, 1e10)::numeric(12,2) as kg,
       zahl(g.anzahl * k.unten, 2, 1e10)::numeric(12,2)         as kg_unten,
       zahl(g.anzahl * k.oben, 2, 1e10)::numeric(12,2)          as kg_oben,
       k.n                                                      as n_messungen
  from auftrag a
  join charge c on c.nr = a.charge_nr
  join gezaehlt g on g.auftrag_id = a.id
  left join lateral (
    select b.kaliber_idx from band b
     where g.kaliber_idx = -2 and b.sorte = c.sorte
       and b.von = a.kaliber_von_g and b.bis = a.kaliber_bis_g
     order by b.kaliber_idx limit 1
  ) e on true
  left join v_koeff_gebinde k
         on k.sorte = c.sorte
        and k.kaliber_idx = case when g.kaliber_idx = -2 then e.kaliber_idx else g.kaliber_idx end
 where a.station = 'waschen' and a.abgebrochen_ts is null;

-- aus 0069_die_regeln_gelten_wieder.sql

create or replace view v_auftrag_wasch_paletten with (security_invoker = true) as
WITH band AS (
         SELECT DISTINCT s.sorte,
            i.idx AS kaliber_idx,
            ((s.kaliber_baender -> i.idx) ->> 0)::integer AS von,
            ((s.kaliber_baender -> i.idx) ->> 1)::integer AS bis
           FROM sortierschema s
             CROSS JOIN LATERAL generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) i(idx)
          WHERE s.art = 'kaliber'::text AND s.kaliber_baender IS NOT NULL
        )
 SELECT a.id AS auftrag_id,
    count(*)::integer AS n_paletten,
    sum(ap.kisten)::integer AS kisten,
    zahl(sum(ap.kisten)::numeric * max(k.kg_je_gebinde), 2, '10000000000'::numeric)::numeric(12,2) AS kg,
    max(k.n) AS n_messungen,
    zahl(sum((ap.kisten * (betriebstag(a.start_ts) - ap.sortierdatum))::numeric) FILTER (WHERE ap.sortierdatum IS NOT NULL) / NULLIF(sum(ap.kisten) FILTER (WHERE ap.sortierdatum IS NOT NULL), 0)::numeric, 1, '100000'::numeric)::numeric(8,1) AS zwischenlager_tage,
    count(*) FILTER (WHERE ap.sortierdatum IS NOT NULL)::integer AS n_mit_sortierdatum
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     JOIN auftrag_palette ap ON ap.auftrag_id = a.id AND ap.kisten IS NOT NULL
     LEFT JOIN LATERAL ( SELECT b.kaliber_idx
           FROM band b
          WHERE a.kaliber_idx IS NULL AND b.sorte = c.sorte AND b.von = a.kaliber_von_g AND b.bis = a.kaliber_bis_g
          ORDER BY b.kaliber_idx
         LIMIT 1) e ON true
     LEFT JOIN v_koeff_gebinde k ON k.sorte = c.sorte AND k.kaliber_idx = COALESCE(a.kaliber_idx, e.kaliber_idx)
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL
  GROUP BY a.id;

create view v_palox_station with (security_invoker = true) as
select * from palox_station_kennzahl(heute());

create or replace view v_sorte_artikelgruppe with (security_invoker = true) as
with verkauft as (
  select l.sorte, e.gruppe, sum(l.kg) as kg
    from lieferung l
    join lieferung_import li on li.lieferung_id = l.id
    join ausgang_zeile z on z.id = li.zeile_id
   cross join lateral artikel_einordnen(z.artikel, z.preisgruppe) e
   where l.sorte is not null and e.gruppe is not null and e.gruppe not in ('andere', 'Mix')
   group by l.sorte, e.gruppe
), haupt as (
  select distinct on (sorte) sorte, gruppe, kg from verkauft order by sorte, kg desc, gruppe
)
select s.sorte,
       coalesce(s.artikelgruppe, h.gruppe) as artikelgruppe,
       case when s.artikelgruppe is not null then 'Stammdaten'
            when h.gruppe is not null then 'verkauft als' end as quelle,
       h.gruppe as gruppe_verkauft
  from sorte_kaliber s
  left join haupt h on h.sorte = s.sorte;

create or replace view v_charge_label with (security_invoker = true) as
with zeile as (

  select l.charge_nr,
         case when upper(coalesce(z.liefer_label, '')) like 'D%' then 'D'
              when upper(coalesce(z.liefer_label, '')) ~ '^(K|CH-K)' then 'K' end as geliefert,
         e.label as verkauft
    from lieferung l
    join lieferung_import li on li.lieferung_id = l.id
    join ausgang_zeile z on z.id = li.zeile_id
   cross join lateral artikel_einordnen(z.artikel, z.preisgruppe) e
   where l.charge_nr is not null
), perigon as (
  select charge_nr,
         count(*) filter (where coalesce(geliefert, verkauft) = 'D')::int as n_d,
         count(*) filter (where coalesce(geliefert, verkauft) = 'K')::int as n_k,
         count(*) filter (where geliefert = 'K' and verkauft = 'D')::int as n_widerspruch
    from zeile
   group by charge_nr
), eigen as (
  select c.nr as charge_nr, c.schlag,
         coalesce(c.label, case when p.n_d > 0 then 'D' when p.n_k > 0 then 'K' end) as label,
         case when c.label is not null then 'Stammdaten'
              when p.n_d > 0 or p.n_k > 0 then 'Perigon' end as quelle,
         p.n_d, p.n_k, p.n_widerspruch
    from charge c
    left join perigon p on p.charge_nr = c.nr
), produzent as (

  select schlag, case when bool_or(label = 'D') then 'D' else 'K' end as label
    from eigen
   where label is not null and nullif(trim(schlag), '') is not null
   group by schlag
)
select e.charge_nr,
       coalesce(e.label, pr.label, 'K') as label,
       coalesce(e.quelle, case when pr.label is not null then 'Produzent' else 'angenommen' end) as quelle,
       coalesce(e.n_d, 0) > 0 and coalesce(e.n_k, 0) > 0 as gemischt,
       coalesce(e.n_d, 0) as n_d,
       coalesce(e.n_k, 0) as n_k,
       coalesce(e.n_widerspruch, 0) as n_widerspruch
  from eigen e
  left join produzent pr on pr.schlag = e.schlag;

-- aus 0114_eine_lieferung_ist_eine_lieferung.sql

create or replace view v_lieferung_charge with (security_invoker = true) as
select l.id, l.datum, l.buch, l.masse_kg, c.charge_nr, c.anteil,
       l.charge_nr is null as ohne_charge
  from (select heute() as heute) d
  cross join v_lieferung_masse l
  cross join lateral (
    select l.charge_nr, 1::numeric as anteil where l.charge_nr is not null
    union all
    select r.charge_nr, r.eingang_netto_kg / sum(r.eingang_netto_kg) over ()
      from v_charge_rueckgrat r
     where l.charge_nr is null and r.sorte = l.sorte and r.eingang_netto_kg > 0
  ) c
 where l.masse_kg is not null and l.masse_kg > 0
   and l.buch in ('verkauf', 'marge', 'verlust') and l.datum <= d.heute
union all

select -cv.charge_nr,
       coalesce((select nullif(wert #>> '{}', '')::date from einstellung where schluessel = 'erfassungsbeginn'),
                r.letzter_eingang),
       'verkauf', cv.ausgang_vor_app_kg, cv.charge_nr, 1, false
  from charge_vorlauf cv join v_charge_rueckgrat r on r.charge_nr = cv.charge_nr
 where cv.ausgang_vor_app_kg > 0;

create or replace view v_lieferung_charge_tag with (security_invoker = true) as
select charge_nr, datum, buch,
       zahl(sum(masse_kg * anteil), 2, 1e12)::numeric(14,2) as masse_kg,
       count(distinct id)::int                              as n_lieferungen
  from v_lieferung_charge
 group by charge_nr, datum, buch;

create or replace view v_lieferung_kohorte with (security_invoker = true) as
select f.charge_nr,
       k.eingangsdatum as kohorte,
       f.buch,
       zahl(sum(f.masse_kg * k.anteil), 2, 1e12)::numeric(14,2) as masse_kg,
       zahl(sum(f.masse_kg * k.anteil * greatest(f.datum - k.eingangsdatum, 0)::numeric)
            / nullif(sum(f.masse_kg * k.anteil), 0), 1, 1e5)::numeric(8,1) as alter_tage,
       sum(f.n_lieferungen)::int as n_lieferungen,
       min(f.datum) as von,
       max(f.datum) as bis
  from v_lieferung_charge_tag f
  join v_kohorte_anteil k on k.charge_nr = f.charge_nr
 group by f.charge_nr, k.eingangsdatum, f.buch;

create or replace view v_verkauf_position with (security_invoker = true) as
select p.quelle, p.pos_id, p.datum, p.saison, p.journal, p.kunde, p.artikel_id, p.artikel, p.preisgruppe,
       p.kg, p.gebindeart, p.gebinde_menge, 'datei'::text as herkunft, p.menge, p.einheit
  from ausgang_position p
union all
select z.quelle, z.pos_id, z.datum, saison_von(z.datum), z.journal, z.kunde, z.artikel_id, z.artikel, z.preisgruppe,
       z.kg_position, z.gebindeart, z.gebinde_menge, 'zeile'::text, z.menge, z.einheit
  from (select distinct on (quelle, pos_id) * from ausgang_zeile order by quelle, pos_id, lauf_nr) z
 where not exists (select 1 from ausgang_position p where p.quelle = z.quelle and p.pos_id = z.pos_id);

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

create or replace view v_auftrag_palette_masse with (security_invoker = true) as
with wiegung as materialized (
  select vw.id,
         zahl(vw.brutto_damals_kg - vw.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000)::numeric(10,2) as netto_damals_kg,
         vw.eingangsdatum
    from verdunstung_wiegung vw
    left join gebinde g on g.art = vw.gebindeart
), datum_mittel as materialized (

  select charge_nr, eingangsdatum, avg(netto_kg) as netto_mittel,
         avg(netto_kg / kisten) filter (where netto_kg is not null and kisten > 0) as netto_je_kiste
    from v_palette group by charge_nr, eingangsdatum
), charge_mittel as materialized (
  select charge_nr, avg(netto_kg) as netto_mittel,
         avg(brutto_kg - netto_kg) filter (where netto_kg is not null) as tara_mittel,
         avg(netto_kg / kisten) filter (where netto_kg is not null and kisten > 0) as netto_je_kiste,
         avg((brutto_kg - netto_kg) / kisten) filter (where netto_kg is not null and kisten > 0) as tara_je_kiste
    from v_palette group by charge_nr
), charge_datum as materialized (
  select charge_nr, eingangsdatum_mittel from v_charge_rueckgrat
), zettel as materialized (
  select ap.id,
         coalesce(pe.netto_kg,

                  case when pe.id is null and ap.kisten is not null
                        and g.tara_kg_pro_kiste is not null and g.tara_kg_palette is not null
                        and ap.brutto_zettel_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette > 0
                       then zahl(ap.brutto_zettel_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000)::numeric(10,2)
                  end,

                  zahl(ap.brutto_zettel_kg - coalesce(ap.kisten::numeric * cm.tara_je_kiste, cm.tara_mittel), 2, 100000000)::numeric(10,2)) as netto_kg,
         (pe.id is not null) as exakt,
         (pe.id is null and ap.kisten is not null
          and g.tara_kg_pro_kiste is not null and g.tara_kg_palette is not null
          and ap.brutto_zettel_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette > 0) as kisten_tara,
         (pe.id is null and ap.kisten is not null and cm.tara_je_kiste is not null) as kisten_charge
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join lateral (
      select p.id, p.netto_kg
        from v_palette p
       where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum
         and p.brutto_kg = ap.brutto_zettel_kg and p.netto_kg is not null
       order by p.id limit 1) pe on true
    left join gebinde g on g.art = ap.gebindeart
    left join charge_mittel cm on cm.charge_nr = a.charge_nr
   where ap.brutto_zettel_kg is not null
)
select ap.id,
       ap.auftrag_id,
       a.charge_nr,
       a.start_ts,
       coalesce(w.netto_damals_kg, z.netto_kg, p.netto_kg,
                ap.kisten * d.netto_je_kiste, d.netto_mittel, ap.kisten * cm.netto_je_kiste, cm.netto_mittel) as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) as eingangsdatum,
       case
         when w.netto_damals_kg is not null       then 'gewogen'
         when z.netto_kg is not null and z.exakt  then 'zettel'
         when z.netto_kg is not null and z.kisten_tara then 'zettel-kisten'
         when z.netto_kg is not null and z.kisten_charge then 'zettel-kisten-charge'
         when z.netto_kg is not null              then 'zettel-charge-tara'
         when p.netto_kg is not null              then 'palette'
         when ap.kisten is not null and d.netto_je_kiste is not null then 'datum-je-kiste'
         when d.netto_mittel is not null          then 'datum-mittel'
         when ap.kisten is not null and cm.netto_je_kiste is not null then 'charge-je-kiste'
         when cm.netto_mittel is not null         then 'charge-mittel'
         else 'unbekannt'
       end as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join wiegung w on w.id = ap.wiegung_id
  left join zettel z on z.id = ap.id
  left join v_palette p on p.id = ap.palette_id
  left join datum_mittel d on d.charge_nr = a.charge_nr and d.eingangsdatum = ap.eingangsdatum
  left join charge_mittel cm on cm.charge_nr = a.charge_nr
  left join charge_datum cd on cd.charge_nr = a.charge_nr
 where not (a.station = 'waschen' and not a.ist_fax);

create materialized view if not exists mv_auftrag_masse as
select a.id as auftrag_id, a.charge_nr, c.sorte, c.schlag, a.weg, a.station,
       a.start_ts, a.ende_ts, a.status,
       count(m.id)                                     as n_paletten,
       coalesce(sum(m.netto_kg), a.durchsatz_kg)        as eingang_netto_kg,
       case when sum(m.netto_kg) is not null then 'paletten'
            when a.durchsatz_kg  is not null then 'durchsatz'
            else 'fehlt' end                            as masse_quelle,
       (sum((a.start_ts::date - m.eingangsdatum) * m.netto_kg)
        / nullif(sum(m.netto_kg), 0))::numeric(10,1)    as lagertage
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_auftrag_palette_masse m on m.auftrag_id = a.id
 where a.abgebrochen_ts is null
 group by a.id, a.charge_nr, c.sorte, c.schlag, a.weg, a.station,
          a.start_ts, a.ende_ts, a.status, a.durchsatz_kg with no data;

-- aus 0026_schimmelpunkte_speichern.sql

create materialized view if not exists mv_sortier_eingang as
select a.charge_nr,
       sum((m.eingangsdatum - date '2000-01-01')::numeric * m.netto_kg)
         / nullif(sum(m.netto_kg), 0)                        as tage_seit_epoche
  from auftrag a
  join v_auftrag_palette_masse m on m.auftrag_id = a.id
 where a.station = 'sortieren' and a.abgebrochen_ts is null
 group by a.charge_nr with no data;

create or replace view v_datenqualitaet with (security_invoker = true) as
with arbeiten as (select a.* from auftrag a where a.abgebrochen_ts is null),
     fertig as (select * from arbeiten where status = 'abgeschlossen')
select
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id)::int as paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where ap.eingangsdatum is not null)::int                                             as paletten_mit_datum,
  (select count(*) from fertig where not ist_fax)::int                                    as arbeiten_fertig,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null))::int                     as arbeiten_mit_ablesung,
  (select count(*) from fertig f where not f.ist_fax and (select count(*) from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null) >= 2)::int                as arbeiten_mit_zwei_ablesungen,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from auftrag_angabe g
    where g.auftrag_id = f.id and g.schluessel = 'eine_charge'))::int                     as arbeiten_mit_antwort,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen)::int                                                                as ausschuss_messungen,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen and m.brutto_kg is not null)::int                                    as ausschuss_gewogen,
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.gemessen)::int                                       as lagerkontrollen,
  (select count(*) from sortier_lauf)::int                                                as sortierlaeufe,
  (select count(*) from sortier_lauf where auftrag_id is not null)::int                   as sortierlaeufe_zugeordnet,
  (select count(*) from fertig f where f.station = 'sortieren')::int                      as sortier_arbeiten,
  (select count(*) from fertig f where f.station = 'sortieren' and exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int              as sortier_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax)::int      as wasch_arbeiten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax
    and (f.kaliber_idx is not null or f.kaliber_von_g is not null)
    and (exists (select 1 from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)
         or exists (select 1 from auftrag_palette p where p.auftrag_id = f.id and p.kisten > 0)))::int
                                                                                          as wasch_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax)::int                                    as fax_arbeiten,
  (select count(*) from fertig f where f.ist_fax and (f.paletten_gesamt > 0 or exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)))::int             as fax_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax and exists (select 1
    from schimmel_messung s where s.auftrag_id = f.id and s.gemessen))::int               as fax_arbeiten_mit_faulem,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren')::int                                           as ws_paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren' and ap.brutto_zettel_kg is not null)::int       as ws_paletten_mit_zettelgewicht,
  (select count(*) from fertig f where f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))::int
                                                                                          as arbeiten_nach_waschen,
  (select count(*) from fertig f where (f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))
    and f.kistensystem is not null)::int                                                  as arbeiten_mit_kistensystem,
  ((select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
     where a.station = 'waschen' and not a.ist_fax)
   + (select coalesce(sum(p.kisten), 0) from auftrag_palette p join arbeiten a on a.id = p.auftrag_id
       where a.station = 'waschen' and not a.ist_fax))::int                               as wasch_kisten_gezaehlt,
  ((select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
     where a.station = 'waschen' and not a.ist_fax and (g.sortierdatum is not null or g.datum_fehlt))
   + (select coalesce(sum(p.kisten), 0) from auftrag_palette p join arbeiten a on a.id = p.auftrag_id
       where a.station = 'waschen' and not a.ist_fax and p.sortierdatum is not null))::int
                                                                                          as wasch_kisten_mit_sortierdatum,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from v_palox_stand p
    where p.auftrag_id = f.id and p.differenz is null))::int                              as arbeiten_mit_palox_unbekannt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where not a.ist_fax and a.station in ('sortieren', 'waschen_sortieren'))::int         as eingangspaletten,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where not a.ist_fax and a.station in ('sortieren', 'waschen_sortieren')
      and ap.kisten is not null and ap.kisten > 0)::int                                   as eingangspaletten_mit_kisten,
  (select count(*) from mv_auftrag_masse m join fertig f on f.id = m.auftrag_id
    where not f.ist_fax and m.lagertage is not null)::int                                 as arbeiten_alter_gemessen,

  (select count(*) from sortier_lauf where art = 'sammel')::int                           as sammel_lesungen,
  (select count(*) from sortier_lauf where sortiertag is not null)::int                   as lesungen_mit_sortiertag,
  (select count(*) from sortier_lauf
    where sortiertag_quelle in ('datei', 'arbeit'))::int                                  as lesungen_sortiertag_bezeugt;

create or replace view v_auftrag_masse_formel with (security_invoker = true) as
 SELECT m.auftrag_id,
    m.charge_nr,
    m.sorte,
    m.schlag,
    m.weg,
    m.station,
    m.start_ts,
    m.ende_ts,
    m.status,
    m.n_paletten,
    COALESCE(m.eingang_netto_kg, wg.kg, fpg.kg, wp.kg, gb.kg, fp.kg) AS eingang_netto_kg,
        CASE
            WHEN m.masse_quelle <> 'fehlt'::text THEN m.masse_quelle
            WHEN wg.kg IS NOT NULL THEN wg.quelle
            WHEN fpg.kg IS NOT NULL THEN 'fertige_paletten'::text
            WHEN wp.kg IS NOT NULL THEN 'wasch_paletten'::text
            WHEN gb.kg IS NOT NULL THEN 'gebinde'::text
            WHEN fp.kg IS NOT NULL THEN 'fax_paletten'::text
            ELSE 'fehlt'::text
        END AS masse_quelle,
    zahl(COALESCE(m.lagertage,
        CASE
            WHEN m.station = 'waschen'::station THEN (betriebstag(m.start_ts) - '2000-01-01'::date)::numeric - COALESCE(se.tage_seit_epoche, (r.eingangsdatum_mittel - '2000-01-01'::date)::numeric)
            ELSE NULL::numeric
        END), 1, 1000000000::numeric)::numeric(10,1) AS lagertage,
    a.ist_fax,
    wp.zwischenlager_tage,
        CASE
            WHEN m.lagertage IS NOT NULL THEN 'gemessen'::text
            WHEN m.station <> 'waschen'::station THEN NULL::text
            WHEN se.tage_seit_epoche IS NOT NULL THEN 'sortiermittel'::text
            WHEN r.eingangsdatum_mittel IS NOT NULL THEN 'chargenmittel'::text
            ELSE NULL::text
        END AS alter_quelle,
        CASE
            WHEN m.lagertage IS NOT NULL THEN NULL::numeric
            ELSE es.streuung_tage
        END AS alter_spanne_tage,
    COALESCE(es.ernte_fertig, false) AS ernte_fertig
   FROM mv_auftrag_masse m
     JOIN auftrag a ON a.id = m.auftrag_id
     LEFT JOIN mv_sortier_eingang se ON se.charge_nr = m.charge_nr
     LEFT JOIN v_charge_rueckgrat r ON r.charge_nr = m.charge_nr
     LEFT JOIN v_charge_erntespanne es ON es.charge_nr = m.charge_nr
     LEFT JOIN v_auftrag_wasch_paletten wp ON wp.auftrag_id = m.auftrag_id
     LEFT JOIN v_auftrag_wasch_gewogen wg ON wg.auftrag_id = m.auftrag_id
     LEFT JOIN ( SELECT v_auftrag_gebinde_masse.auftrag_id,
            sum(v_auftrag_gebinde_masse.kg) AS kg
           FROM v_auftrag_gebinde_masse
          GROUP BY v_auftrag_gebinde_masse.auftrag_id) gb ON gb.auftrag_id = m.auftrag_id
     LEFT JOIN v_auftrag_fertige_masse fpg ON fpg.auftrag_id = m.auftrag_id
     LEFT JOIN LATERAL ( SELECT zahl(a.paletten_gesamt::numeric * p.netto_kg, 2, '10000000000'::bigint::numeric)::numeric(12,2) AS kg
           FROM v_koeff_palette_netto p
          WHERE a.ist_fax AND a.paletten_gesamt > 0 AND p.sorte = m.sorte AND (p.kistensystem = a.kistensystem OR p.kistensystem IS NULL AND a.kistensystem IS DISTINCT FROM 'anderes'::text)
          ORDER BY (p.kistensystem = a.kistensystem) DESC NULLS LAST
         LIMIT 1) fp ON true;

create or replace function v_auftrag_masse_zaun() returns setof v_auftrag_masse_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_auftrag_masse_formel;
end $$;

create or replace view v_auftrag_masse with (security_invoker = true) as
select * from v_auftrag_masse_zaun();

create or replace view v_durchsatz with (security_invoker = true) as
 SELECT a.id AS auftrag_id,
    a.charge_nr,
    m.sorte,
    a.station,
    a.weg,
    a.ist_fax,
    a.start_ts,
    a.ende_ts,
    zahl((EXTRACT(epoch FROM a.ende_ts - a.start_ts) / 3600::numeric), 2, 1e8)::numeric(10,2) AS dauer_h,
    m.eingang_netto_kg AS masse_kg,
    m.masse_quelle,
    m.n_paletten,
        zahl(CASE
            WHEN m.eingang_netto_kg IS NOT NULL AND (a.ende_ts - a.start_ts) >= '00:15:00'::interval THEN m.eingang_netto_kg / (EXTRACT(epoch FROM a.ende_ts - a.start_ts) / 3600::numeric)
            ELSE NULL::numeric
        END, 1, 1e9)::numeric(10,1) AS kg_pro_h,
    (( SELECT count(*) AS count
           FROM auftrag_teilnehmer t
          WHERE t.auftrag_id = a.id))::integer AS n_teilnehmer
   FROM auftrag a
     JOIN v_auftrag_masse m ON m.auftrag_id = a.id
  WHERE a.status = 'abgeschlossen'::auftrag_status AND a.abgebrochen_ts IS NULL AND a.ende_ts IS NOT NULL;

create or replace view v_fax_beobachtung with (security_invoker = true) as
select a.id as auftrag_id, a.charge_nr, c.sorte, c.schlag, a.kaeufer,
       a.start_ts, a.ende_ts, a.status, a.abgebrochen_ts,
       m.eingang_netto_kg                                            as masse_kg,
       m.masse_quelle,
       coalesce(g.kisten, 0)                                         as kisten,
       coalesce(s.kg, 0)                                             as faul_kg,
       (s.auftrag_id is not null)                                    as faul_erfasst,
       zahl(coalesce(s.kg, 0) / nullif(m.eingang_netto_kg + coalesce(s.kg, 0), 0), 5, 1e5)::numeric(10,5)
                                                                     as anteil,
       anteil_plausibel(coalesce(s.kg, 0) / nullif(m.eingang_netto_kg + coalesce(s.kg, 0), 0))
                                                                     as plausibel,

       a.paletten_gesamt, a.tage_seit_waschen, a.kistensystem
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_auftrag_masse m on m.auftrag_id = a.id
  left join v_schimmel_menge s on s.auftrag_id = a.id
  left join (select auftrag_id, sum(anzahl)::int as kisten from auftrag_gebinde group by auftrag_id) g
         on g.auftrag_id = a.id
 where a.ist_fax and a.abgebrochen_ts is null;

create or replace view v_kaskade_basis with (security_invoker = true) as
with stichtag as (

  select heute() as bis
), je_station as (
  select charge_nr,
         sum(eingang_netto_kg) filter (where station = 'sortieren')          as sortiert_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen' and not ist_fax) as gewaschen_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren')  as hand_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren'
                                         and weg = 'hand')                   as kg_hand,
         sum(eingang_netto_kg * lagertage) filter (
             where station in ('sortieren', 'waschen_sortieren') and lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (
               where station in ('sortieren', 'waschen_sortieren') and lagertage is not null), 0)
                                                                             as alter_band,
         sum(eingang_netto_kg) filter (where station in ('sortieren', 'waschen_sortieren'))
                                                                             as am_band_kg
    from v_auftrag_masse
   where eingang_netto_kg is not null
   group by charge_nr
), anteil as (
  select s.*,
         least(coalesce(s.gewaschen_kg, 0) / nullif(s.sortiert_kg, 0), 1)     as anteil_gewaschen
    from je_station s
), kohorte as (
  select k.charge_nr,
         min(k.eingangsdatum)                                     as eingang_von,
         max(k.eingangsdatum)                                     as eingang_bis,
         count(*)::int                                            as n_eingangstage
    from v_charge_kohorte k
   group by k.charge_nr
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg                                                     as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       s.bis                                                                  as stichtag,
       r.n_paletten_mit_netto,

       coalesce(a.sortiert_kg, 0)                                             as sortiert_kg,
       coalesce(a.gewaschen_kg, 0)                                            as gewaschen_kg,
       coalesce(a.hand_kg, 0)                                                 as hand_kg,
       (coalesce(a.sortiert_kg, 0) * (1 - coalesce(a.anteil_gewaschen, 0)))    as wartet_kg,
       coalesce(a.anteil_gewaschen, 0)                                        as anteil_gewaschen,
       coalesce(a.kg_hand / nullif(coalesce(a.hand_kg, 0)
                                   + coalesce(a.sortiert_kg, 0), 0), 0)       as weg2_anteil,
       a.alter_band,
       coalesce(a.am_band_kg, 0)                                              as am_band_kg,
       k.eingang_von, k.eingang_bis, k.n_eingangstage,

       heute()                                                                as heute,
       stichtag()                                                             as saison_ende
  from v_charge_rueckgrat r
  cross join stichtag s
  left join anteil a on a.charge_nr = r.charge_nr
  left join kohorte k on k.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;

create or replace view v_fax_wartezeit with (security_invoker = true) as
with roh as (
  select case when f.tage_seit_waschen is null then 'unbekannt'
              when f.tage_seit_waschen <= 1    then '0–1 Tage'
              when f.tage_seit_waschen <= 3    then '2–3 Tage'
              else '4 und mehr' end                              as klasse,
         f.sorte, f.masse_kg, f.faul_kg, f.anteil
    from v_fax_beobachtung f
   where f.status = 'abgeschlossen' and f.masse_kg is not null
), je as (

  select g.gruppe,
         (case when g.gruppe = 'sorte' then roh.sorte end) as sorte,
         roh.klasse,
         count(*)::int as n, sum(roh.masse_kg) as masse_kg, sum(roh.faul_kg) as faul_kg,
         sum(roh.faul_kg) / nullif(sum(roh.masse_kg + roh.faul_kg), 0) as anteil,
         stddev_samp(roh.anteil) as sd
    from roh cross join lateral (select unnest(array['alle', 'sorte']) as gruppe) g
   group by g.gruppe, (case when g.gruppe = 'sorte' then roh.sorte end), roh.klasse
)
select gruppe,
       sorte,
       klasse,
       case klasse when '0–1 Tage' then 1 when '2–3 Tage' then 2
                   when '4 und mehr' then 3 else 4 end          as reihenfolge,
       n,
       zahl(masse_kg, 1, 1e11)::numeric(12,1)                    as masse_kg,
       zahl(faul_kg,  1, 1e11)::numeric(12,1)                    as faul_kg,
       zahl(anteil, 5, 1e5)::numeric(10,5)                       as anteil,
       case when n >= 2 and sd is not null
            then zahl(greatest(anteil - t_quantil_95(n - 1) * sd / sqrt(n), 0), 5, 1e5)::numeric(10,5)
            else zahl(anteil, 5, 1e5)::numeric(10,5) end         as unten,
       case when n >= 2 and sd is not null
            then zahl(least(anteil + t_quantil_95(n - 1) * sd / sqrt(n), 1), 5, 1e5)::numeric(10,5)
            else zahl(anteil, 5, 1e5)::numeric(10,5) end         as oben
  from je;
create materialized view erg_fax_wartezeit as select * from v_fax_wartezeit with no data;

create or replace view v_charge_weg with (security_invoker = true) as
with arbeit as (
  select a.charge_nr, a.sorte,
         sum(a.eingang_netto_kg) filter (where a.station = 'waschen_sortieren')          as hand_kg,
         sum(a.eingang_netto_kg) filter (where a.station = 'sortieren')                  as band_kg,
         sum(a.eingang_netto_kg) filter (where a.station = 'waschen' and not a.ist_fax)  as wasch_kg
    from v_auftrag_masse a
   where a.eingang_netto_kg is not null and a.eingang_netto_kg > 0
   group by a.charge_nr, a.sorte
), je_sorte as (
  select sorte, sum(hand_kg) as hand_kg, sum(band_kg) as band_kg, sum(wasch_kg) as wasch_kg
    from arbeit group by sorte
), alle as (
  select sum(hand_kg) as hand_kg, sum(band_kg) as band_kg, sum(wasch_kg) as wasch_kg from arbeit
)
select b.charge_nr, b.sorte,
       case when coalesce(c.hand_kg, 0) + coalesce(c.band_kg, 0) > 0
              then coalesce(c.hand_kg, 0) / (coalesce(c.hand_kg, 0) + coalesce(c.band_kg, 0))
            when coalesce(s.hand_kg, 0) + coalesce(s.band_kg, 0) > 0
              then coalesce(s.hand_kg, 0) / (coalesce(s.hand_kg, 0) + coalesce(s.band_kg, 0))
            when coalesce(x.hand_kg, 0) + coalesce(x.band_kg, 0) > 0
              then coalesce(x.hand_kg, 0) / (coalesce(x.hand_kg, 0) + coalesce(x.band_kg, 0))
       end                                                                      as p_hand,

       case when coalesce(c.wasch_kg, 0) > 0 or coalesce(s.wasch_kg, 0) > 0 then 1
            when coalesce(s.hand_kg, 0) + coalesce(s.band_kg, 0) > 0 then 0
            when coalesce(x.wasch_kg, 0) > 0 then 1
            when coalesce(x.hand_kg, 0) + coalesce(x.band_kg, 0) > 0 then 0
       end::numeric                                                             as p_wasch,
       case when coalesce(c.hand_kg, 0) + coalesce(c.band_kg, 0) > 0 then 'eigenen Arbeiten'
            when coalesce(s.hand_kg, 0) + coalesce(s.band_kg, 0) > 0 then 'Arbeiten der Sorte'
            when coalesce(x.hand_kg, 0) + coalesce(x.band_kg, 0) > 0 then 'Arbeiten aller Sorten'
       end                                                                      as weg_quelle,
       coalesce(c.hand_kg, 0) as hand_kg, coalesce(c.band_kg, 0) as band_kg, coalesce(c.wasch_kg, 0) as wasch_kg
  from v_kaskade_basis b
  left join arbeit c on c.charge_nr = b.charge_nr
  left join je_sorte s on s.sorte = b.sorte
  cross join alle x;

create or replace view v_lieferung_gruppe with (security_invoker = true) as
with lief as (
  select l.id, l.ohne_charge, b.charge_nr, b.sorte, b.schlag
    from v_lieferung_charge l
    join v_kaskade_basis b on b.charge_nr = l.charge_nr
   where l.buch in ('verkauf', 'marge') and l.id > 0 and b.eingang_kg is not null
), gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, id, ohne_charge from lief
  union all select 'sorte',  sorte,             id, ohne_charge from lief
  union all select 'schlag', schlag,            id, ohne_charge from lief
  union all select 'charge', charge_nr::text,   id, ohne_charge from lief
)
select gruppe, schluessel,
       count(distinct id)::int                             as n_lieferungen,
       count(distinct id) filter (where ohne_charge)::int  as n_ohne_charge
  from gruppen
 group by gruppe, schluessel;

create or replace view v_verdunstung_messung with (security_invoker = true) as
select b.id,
       b.charge_nr,
       b.sorte,
       b.schlag,
       b.palette_id,
       b.eingangsdatum,
       b.wiege_ts,
       b.sichtbar_schimmel,
       b.erfasser,
       b.auftrag_id,
       b.netto_damals_kg,
       b.netto_jetzt_kg,
       b.lagertage,
       r.rate_pro_tag,
       (u.grund is null)                                               as verwendbar,
       (r.rate_pro_tag is null or r.rate_pro_tag <= k.rate_max)       as plausibel,
       u.grund
  from (

    select w.id, w.charge_nr, c.sorte, c.schlag, w.palette_id, w.eingangsdatum, w.wiege_ts,
           w.sichtbar_schimmel, w.erfasser, w.auftrag_id, w.gemessen,
           (a.id is not null and a.abgebrochen_ts is not null)                              as abgebrochen,
           w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette as netto_damals_kg,
           w.brutto_jetzt_kg  - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette as netto_jetzt_kg,
           (betriebstag(w.wiege_ts) - w.eingangsdatum)                                       as lagertage
      from verdunstung_wiegung w
      join charge c on c.nr = w.charge_nr
      left join auftrag a on a.id = w.auftrag_id
      left join gebinde g on g.art = w.gebindeart
    offset 0
  ) b

  cross join (select verdunstung_rate_max() as rate_max) k
  cross join lateral (
    select zahl(case when b.netto_damals_kg > 0 and b.netto_jetzt_kg > 0 and b.lagertage > 0
                     then 1 - power(b.netto_jetzt_kg / b.netto_damals_kg, (1.0 / b.lagertage)::numeric)
                end, 6, 10000)::numeric(10,6) as rate_pro_tag
    offset 0
  ) r
  cross join lateral (

    select case

             when exists (select 1 from messung_ausschluss x where x.art = 'verdunstung' and x.bezug_id = b.id)
                                                                     then 'von Hand ausgeschlossen'
             when not b.gemessen                                     then 'nicht gemessen'
             when b.sichtbar_schimmel                                then 'Schimmel sichtbar — die Palette verlor mehr als Wasser'
             when b.abgebrochen                                      then 'Arbeit abgebrochen'
             when b.netto_damals_kg is null or b.netto_jetzt_kg is null then 'ohne Netto — die Tara des Gebindes fehlt'
             when b.netto_damals_kg <= 0 or b.netto_jetzt_kg <= 0    then 'Netto unter null — das Brutto ist kleiner als die Tara'
             when b.lagertage <= 0                                   then 'am Eingangstag gewogen — keine Lagerdauer'
             when b.netto_jetzt_kg > b.netto_damals_kg * 1.01        then 'schwerer geworden — Waagenrauschen oder ein kopiertes Eingangsgewicht'
             when b.netto_jetzt_kg = b.netto_damals_kg               then 'unverändert — dieselbe Zahl zweimal'
             when r.rate_pro_tag > k.rate_max
               then format('zu schnell — %s %% je Tag ist keine Verdunstung', round(r.rate_pro_tag * 100, 2))
           end as grund
  ) u;

-- aus 0018_koeffizienten_gepoolt.sql

create or replace view v_koeff_roh_verdunstung with (security_invoker = true) as

select 'verdunstung'::text as art, m.sorte, m.charge_nr,
       m.rate_pro_tag::numeric as anteil, m.netto_jetzt_kg::numeric as gewicht
  from v_verdunstung_messung m
 where m.verwendbar and m.netto_jetzt_kg > 0;

create or replace view v_wiegung_kennzahl with (security_invoker = true) as
select w.id,
       w.auftrag_id,
       w.charge_nr,
       c.sorte,
       c.schlag,
       w.eingangsdatum,
       w.wiege_ts,
       w.kisten,
       w.gebindeart,
       w.sichtbar_schimmel,
       w.kuerbisse_pro_kiste,
       (betriebstag(w.wiege_ts) - w.eingangsdatum)                                   as lagertage,
       n.netto_damals_kg,
       n.netto_jetzt_kg,
       zahl(n.netto_jetzt_kg / nullif(w.kisten, 0)::numeric, 3, 10000000)::numeric(10,3)                          as kg_pro_kiste,
       zahl(n.netto_jetzt_kg / nullif(w.kisten * w.kuerbisse_pro_kiste, 0)::numeric, 3, 10000000)::numeric(10,3)  as kg_pro_kuerbis,
       zahl(n.netto_damals_kg - n.netto_jetzt_kg, 2, 100000000)::numeric(10,2)                                     as verdunstung_kg,
       m.rate_pro_tag,
       m.verwendbar,
       m.plausibel,
       m.grund
  from verdunstung_wiegung w
  join charge c on c.nr = w.charge_nr
  left join auftrag a on a.id = w.auftrag_id
  left join gebinde g on g.art = w.gebindeart
  left join v_verdunstung_messung m on m.id = w.id
  cross join lateral (
    select zahl(w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000)::numeric(10,2) as netto_damals_kg,
           zahl(w.brutto_jetzt_kg  - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000)::numeric(10,2) as netto_jetzt_kg) n
 where w.gemessen and (a.id is null or a.abgebrochen_ts is null);

create or replace view v_koeff_verdunstung_geschaetzt with (security_invoker = true) as
with roh as materialized (
  select art, sorte, charge_nr, anteil, gewicht
    from v_koeff_roh_verdunstung
   where anteil is not null and gewicht > 0
), mitte as (
  select art, sorte,
         count(*)::int                         as n,
         count(distinct charge_nr)::int        as c_chargen,
         sum(gewicht)                          as sw,
         sum(anteil * gewicht) / sum(gewicht)  as mittel
    from roh
   group by grouping sets ((art, sorte), (art))
), ebene as (
  select m.art, m.sorte, m.n, m.c_chargen, m.mittel,
         case when m.n > 1
              then (select sum(r.gewicht * power(r.anteil - m.mittel, 2)) from roh r
                     where r.art = m.art and (m.sorte is null or r.sorte = m.sorte))
                   / m.sw / (m.n - 1) end      as varianz
    from mitte m
), gitter as (
  select a.art, sk.sorte from (select distinct art from roh) a cross join sorte_kaliber sk
  union all
  select a.art, null::text from (select distinct art from roh) a
)
select gi.art, gi.sorte,
       coalesce(v.n, 0)                                        as n,
       coalesce(v.c_chargen, 0)                                as c_chargen,
       v.mittel                                                as mittel_roh,
       v.varianz                                               as varianz_roh,
       g.mittel                                                as mittel_gesamt,
       null::numeric                                           as tau2,
       b.gewicht                                               as b,
       case when b.gewicht = 1 then coalesce(v.mittel, g.mittel) else g.mittel end as mittel,
       case when b.gewicht = 1 then coalesce(v.varianz, 0) else coalesce(g.varianz, 0) end as varianz,
       greatest(case when b.gewicht = 1 then coalesce(v.n, 0) else g.n end - 1, 1) as df,
       g.n                                                     as n_gesamt,
       b.gewicht * coalesce(v.varianz, 0)                      as varianz_eigen,
       1 - b.gewicht                                           as gewicht_gesamt,
       coalesce(g.varianz, 0)                                  as varianz_gesamt
  from gitter gi
  join ebene g on g.art = gi.art and g.sorte is null
  left join ebene v on v.art = gi.art and v.sorte is not distinct from gi.sorte
 cross join lateral (
   select case when gi.sorte is null then 1.0
               when coalesce(v.n, 0) >= anteil_mindest_messungen() then 1.0
               else 0.0 end::numeric as gewicht) b;

create or replace view v_koeff_verdunstung with (security_invoker = true) as
select sk.sorte,
       case when k.mittel < 0 then 0 else k.mittel end as mittel,
       case when coalesce(k.varianz, 0) = 0 then case when k.mittel < 0 then 0 else k.mittel end
            else greatest(k.mittel - k.t * sqrt(k.varianz), 0) end::double precision as unten,
       case when coalesce(k.varianz, 0) = 0 then case when k.mittel < 0 then 0 else k.mittel end
            else greatest(k.mittel + k.t * sqrt(k.varianz), 0) end::double precision as oben,
       coalesce(k.n, 0) as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Wiegung vorhanden'
            when k.b = 1 then 'Wiegungen dieser Sorte'
            else format('Wiegungen aller Sorten (eigene: %s, gilt ab %s)', coalesce(k.n, 0), anteil_mindest_messungen())
       end as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_verdunstung_geschaetzt g
     where g.art = 'verdunstung' and g.sorte is not distinct from sk.sorte) k on true;

create or replace view v_schimmel_beobachtung with (security_invoker = true) as
 SELECT am.auftrag_id,
    am.charge_nr,
    am.sorte,
    am.schlag,
    am.weg,
    am.station,
    am.start_ts,
    am.lagertage,
    am.masse_quelle,
    s.kg AS schimmel_kg,
    am.eingang_netto_kg AS eingang_kg,
    zahl(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 2, '10000000000'::numeric)::numeric(12,2) AS basis_jetzt_kg,
    s.kg / NULLIF(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 0::numeric) AS anteil,
    anteil_plausibel(s.kg / NULLIF(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 0::numeric)) AND am.lagertage >= 0::numeric AS plausibel,
    am.ist_fax
   FROM v_auftrag_masse am
     JOIN v_schimmel_menge s ON s.auftrag_id = am.auftrag_id
     LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = am.sorte
     CROSS JOIN LATERAL ( SELECT LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            GREATEST(am.lagertage, 0::numeric) AS tage) x
  WHERE am.eingang_netto_kg IS NOT NULL AND am.lagertage IS NOT NULL;

create or replace view v_ausschuss_beobachtung with (security_invoker = true) as
 SELECT 'maschine'::verarbeitungsweg AS weg,
    lm.charge_nr,
    lm.sorte,
    lm.auftrag_id,
    lm.masse_kg AS basis_kg,
    lm.masse_klein_kg AS klein_kg,
    lm.masse_nebenkanal_kg AS gross_kg,
    true AS plausibel
   FROM v_sortier_lauf_masse lm
  WHERE lm.masse_kg > 0::numeric
UNION ALL
 SELECT 'hand'::verarbeitungsweg AS weg,
    am.charge_nr,
    am.sorte,
    am.auftrag_id,
    n.basis AS basis_kg,
    h.klein_kg,
    h.gross_kg,

    (h.klein_kg IS NULL OR anteil_plausibel(h.klein_kg / NULLIF(n.basis, 0::numeric)))
      AND (h.gross_kg IS NULL OR anteil_plausibel(h.gross_kg / NULLIF(n.basis, 0::numeric))) AS plausibel
   FROM v_auftrag_masse am
     JOIN ( SELECT ausschuss_messung.auftrag_id,
            sum(ausschuss_messung.kg) FILTER (WHERE ausschuss_messung.art = 'zu_klein'::ausschuss_art)::numeric AS klein_kg,
            sum(ausschuss_messung.kg) FILTER (WHERE ausschuss_messung.art = 'zu_gross'::ausschuss_art)::numeric AS gross_kg
           FROM ausschuss_messung
          WHERE ausschuss_messung.gemessen
          GROUP BY ausschuss_messung.auftrag_id) h ON h.auftrag_id = am.auftrag_id
     LEFT JOIN v_schimmel_menge sm ON sm.auftrag_id = am.auftrag_id
     LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = am.sorte
     CROSS JOIN LATERAL ( SELECT zahl(GREATEST(am.eingang_netto_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), GREATEST(am.lagertage, 0::numeric)) - COALESCE(sm.kg, 0::numeric), 0::numeric), 2, 1e10)::numeric(12,2) AS basis) n
  WHERE am.weg = 'hand'::verarbeitungsweg AND am.eingang_netto_kg IS NOT NULL AND am.lagertage IS NOT NULL;

create or replace view v_koeff_roh_kaliber with (security_invoker = true) as
 SELECT 'ausschuss'::text AS art,
    b.sorte,
    b.charge_nr,
    b.klein_kg / b.basis_kg AS anteil,
    b.basis_kg AS gewicht
   FROM v_ausschuss_beobachtung b
  WHERE b.plausibel AND b.basis_kg > 0::numeric AND b.klein_kg IS NOT NULL
UNION ALL
 SELECT 'nebenkanal'::text AS art,
    b.sorte,
    b.charge_nr,
    b.gross_kg / b.basis_kg AS anteil,
    b.basis_kg AS gewicht
   FROM v_ausschuss_beobachtung b
  WHERE b.plausibel AND b.basis_kg > 0::numeric AND b.gross_kg IS NOT NULL
UNION ALL
 SELECT 'fax'::text AS art,
    f.sorte,
    f.charge_nr,
    f.anteil::numeric AS anteil,
    zahl((f.masse_kg + f.faul_kg), 2, 1e10)::numeric(12,2) AS gewicht
   FROM v_fax_beobachtung f
  WHERE f.plausibel AND f.masse_kg > 0::numeric AND f.faul_erfasst AND f.status = 'abgeschlossen'::auftrag_status;

create or replace view v_koeff_kaliber_geschaetzt_formel with (security_invoker = true) as
with roh as materialized (
  select art, sorte, charge_nr, anteil, gewicht
    from v_koeff_roh_kaliber
   where anteil is not null and gewicht > 0
), mitte as (
  select art, sorte,
         count(*)::int                         as n,
         count(distinct charge_nr)::int        as c_chargen,
         sum(gewicht)                          as sw,
         sum(anteil * gewicht) / sum(gewicht)  as mittel
    from roh
   group by grouping sets ((art, sorte), (art))
), ebene as (
  select m.art, m.sorte, m.n, m.c_chargen, m.mittel,
         case when m.n > 1
              then (select sum(r.gewicht * power(r.anteil - m.mittel, 2)) from roh r
                     where r.art = m.art and (m.sorte is null or r.sorte = m.sorte))
                   / m.sw / (m.n - 1) end      as varianz
    from mitte m
), gitter as (
  select a.art, sk.sorte from (select distinct art from roh) a cross join sorte_kaliber sk
  union all
  select a.art, null::text from (select distinct art from roh) a
)
select gi.art, gi.sorte,
       coalesce(v.n, 0)                                        as n,
       coalesce(v.c_chargen, 0)                                as c_chargen,
       v.mittel                                                as mittel_roh,
       v.varianz                                               as varianz_roh,
       g.mittel                                                as mittel_gesamt,
       null::numeric                                           as tau2,
       b.gewicht                                               as b,
       case when b.gewicht = 1 then coalesce(v.mittel, g.mittel) else g.mittel end as mittel,
       case when b.gewicht = 1 then coalesce(v.varianz, 0) else coalesce(g.varianz, 0) end as varianz,
       greatest(case when b.gewicht = 1 then coalesce(v.n, 0) else g.n end - 1, 1) as df,
       g.n                                                     as n_gesamt,
       b.gewicht * coalesce(v.varianz, 0)                      as varianz_eigen,
       1 - b.gewicht                                           as gewicht_gesamt,
       coalesce(g.varianz, 0)                                  as varianz_gesamt
  from gitter gi
  join ebene g on g.art = gi.art and g.sorte is null
  left join ebene v on v.art = gi.art and v.sorte is not distinct from gi.sorte
 cross join lateral (
   select case when gi.sorte is null then 1.0
               when coalesce(v.n, 0) >= anteil_mindest_messungen() then 1.0
               else 0.0 end::numeric as gewicht) b;

create or replace function v_koeff_kaliber_geschaetzt_zaun() returns setof v_koeff_kaliber_geschaetzt_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_koeff_kaliber_geschaetzt_formel;
end $$;

create or replace view v_koeff_kaliber_geschaetzt with (security_invoker = true) as
select * from v_koeff_kaliber_geschaetzt_zaun();

create or replace view v_koeff_unsicherheit with (security_invoker = true) as
select art, sorte, b, varianz_eigen, gewicht_gesamt, varianz_gesamt, df
  from v_koeff_verdunstung_geschaetzt
union all
select art, sorte, b, varianz_eigen, gewicht_gesamt, varianz_gesamt, df
  from v_koeff_kaliber_geschaetzt;

create or replace view v_koeff_ausschuss with (security_invoker = true) as
select sk.sorte, k.mittel,
       case when coalesce(k.varianz, 0) = 0 then k.mittel
            else greatest(k.mittel - k.t * sqrt(k.varianz), 0) end::double precision as unten,
       case when coalesce(k.varianz, 0) = 0 then k.mittel
            else least(k.mittel + k.t * sqrt(k.varianz), 1) end::double precision as oben,
       coalesce(k.n, 0) as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Messung vorhanden'
            when k.b = 1 then 'Sortierläufe/Handmessungen dieser Sorte'
            else format('alle Sorten (eigene: %s, gilt ab %s)', coalesce(k.n, 0), anteil_mindest_messungen())
       end as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'ausschuss' and g.sorte is not distinct from sk.sorte) k on true;

create or replace view v_koeff_nebenkanal with (security_invoker = true) as
select sk.sorte, k.mittel,
       case when coalesce(k.varianz, 0) = 0 then k.mittel
            else greatest(k.mittel - k.t * sqrt(k.varianz), 0) end::double precision as unten,
       case when coalesce(k.varianz, 0) = 0 then k.mittel
            else least(k.mittel + k.t * sqrt(k.varianz), 1) end::double precision as oben,
       coalesce(k.n, 0) as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Messung vorhanden'
            when k.b = 1 then 'Sortierläufe/Handmessungen dieser Sorte'
            else format('alle Sorten (eigene: %s, gilt ab %s)', coalesce(k.n, 0), anteil_mindest_messungen())
       end as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'nebenkanal' and g.sorte is not distinct from sk.sorte) k on true;

create or replace view v_koeff_fax with (security_invoker = true) as
with schalter as (
  select coalesce((select (wert #>> '{}')::boolean from einstellung where schluessel = 'fax_eingefroren'), false) as eingefroren
)
select sk.sorte,
       case when s.eingefroren then 0::numeric else k.mittel end as mittel,
       case when s.eingefroren then 0::double precision
            when coalesce(k.varianz, 0) = 0 then k.mittel::double precision
            else greatest(k.mittel - k.t * sqrt(k.varianz), 0)::double precision end as unten,
       case when s.eingefroren then 0::double precision
            when coalesce(k.varianz, 0) = 0 then k.mittel::double precision
            else least(k.mittel + k.t * sqrt(k.varianz), 1)::double precision end as oben,
       case when s.eingefroren then 0 else coalesce(k.n, 0) end as n,
       case when s.eingefroren then 'eingefroren (Runde R): Fax wird nicht erfasst, erwarteter Anteil 0 durch Entscheid'
            when coalesce(k.n_gesamt, 0) = 0 then 'keine Fax-Arbeit mit gewogenem Faulem'
            when k.b = 1 then 'Fax-Arbeiten dieser Sorte'
            else format('alle Sorten (eigene: %s, gilt ab %s)', coalesce(k.n, 0), anteil_mindest_messungen())
       end as basis
  from sorte_kaliber sk
 cross join schalter s
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'fax' and g.sorte is not distinct from sk.sorte) k on true;
create materialized view erg_koeff_fax as select * from v_koeff_fax with no data;
create materialized view mv_koeff_rand as
  select b.sorte,
         least(greatest(coalesce(kv.unten::numeric, 0), 0), 0.05)   as r_unten,
         least(greatest(coalesce(kv.oben::numeric,  0), 0), 0.05)   as r_oben,
         least(greatest(coalesce(ka.unten::numeric, 0), 0), 1)      as klein_unten,
         least(greatest(coalesce(ka.oben::numeric,  0), 0), 1)      as klein_oben,
         least(greatest(coalesce(kn.unten::numeric, 0), 0), 1)      as gross_unten,
         least(greatest(coalesce(kn.oben::numeric,  0), 0), 1)      as gross_oben,
         least(greatest(coalesce(kf.unten::numeric, 0), 0), 1)      as fax_unten,
         least(greatest(coalesce(kf.oben::numeric,  0), 0), 1)      as fax_oben
    from (select distinct sorte from v_kaskade_basis) b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
    left join v_koeff_fax         kf on kf.sorte = b.sorte
with no data;

create view v_lauf_vergleich with (security_invoker = true) as
with lauf as (
  select l.id as lauf_id, l.charge_nr, c.sorte, l.sortiertag, l.sortiertag_quelle, l.datei_name
    from sortier_lauf l
    join charge c on c.nr = l.charge_nr
   where l.sortiertag is not null
), stueck as (
  select g.lauf_id, g.gewicht_g, sum(g.anzahl) as anzahl
    from sortier_gewicht g
   where g.klasse <> 'unklassiert' and g.anzahl > 0 and g.gewicht_g > 0
   group by g.lauf_id, g.gewicht_g
), kumuliert as (
  select s.lauf_id, s.gewicht_g, s.anzahl,
         sum(s.anzahl) over (partition by s.lauf_id order by s.gewicht_g) as bis_hier,
         sum(s.anzahl) over (partition by s.lauf_id) as gesamt
    from stueck s
), je_lauf as (
  select k.lauf_id,
         max(k.gesamt)::int                                                     as n_kuerbis,
         sum(k.anzahl * k.gewicht_g)::numeric / nullif(max(k.gesamt), 0)        as mittel_g,
         min(k.gewicht_g) filter (where k.bis_hier >= 0.25 * k.gesamt)          as q1_g,
         min(k.gewicht_g) filter (where k.bis_hier >= 0.50 * k.gesamt)          as median_g,
         min(k.gewicht_g) filter (where k.bis_hier >= 0.75 * k.gesamt)          as q3_g
    from kumuliert k
   group by k.lauf_id
), mit_erstem as (
  select l.*, j.n_kuerbis, j.mittel_g, j.q1_g, j.median_g, j.q3_g,
         first_value(l.lauf_id) over w   as erster_lauf_id,
         first_value(l.sortiertag) over w as erster_tag,
         first_value(j.median_g) over w  as erster_median_g,
         first_value(j.mittel_g) over w  as erster_mittel_g,
         count(*) over (partition by l.charge_nr) as n_laeufe
    from lauf l
    join je_lauf j on j.lauf_id = l.lauf_id
  window w as (partition by l.charge_nr order by l.sortiertag, l.lauf_id)
)
select m.charge_nr, m.sorte, m.lauf_id, m.datei_name, m.sortiertag, m.sortiertag_quelle, m.n_laeufe,
       m.n_kuerbis,
       zahl(m.mittel_g, 1, 100000)::numeric(8,1) as mittel_g,
       m.q1_g, m.median_g, m.q3_g,
       m.erster_lauf_id,
       (m.sortiertag - m.erster_tag)              as tage_seit_erstem,
       case when m.sortiertag - m.erster_tag >= 7 and m.erster_median_g > 0 and m.median_g > 0
            then zahl(1 - power(m.median_g::numeric / m.erster_median_g, 1.0 / (m.sortiertag - m.erster_tag)), 6, 1)
       end::numeric(10,6)                          as rate_median,
       case when m.sortiertag - m.erster_tag >= 7 and m.erster_mittel_g > 0 and m.mittel_g > 0
            then zahl(1 - power(m.mittel_g / m.erster_mittel_g, 1.0 / (m.sortiertag - m.erster_tag)), 6, 1)
       end::numeric(10,6)                          as rate_mittel,
       kv.mittel                                   as rate_wiegungen
  from mit_erstem m
  left join v_koeff_verdunstung kv on kv.sorte = m.sorte;

create or replace view v_schimmel_punkte_formel with (security_invoker = true) as
 WITH sortier_lauf_anteil AS MATERIALIZED (
         SELECT b.charge_nr,
            b.start_ts,
            b.schimmel_kg,
            b.basis_jetzt_kg
           FROM v_schimmel_beobachtung b
          WHERE b.station = 'sortieren'::station AND b.plausibel AND b.anteil IS NOT NULL
        ), gemischt AS (
         SELECT v_auftrag_angabe.auftrag_id
           FROM v_auftrag_angabe
          WHERE v_auftrag_angabe.schluessel = 'eine_charge'::text AND v_auftrag_angabe.wert = 'false'::text
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lagertage,
    b.schimmel_kg,
    b.basis_jetzt_kg,
    b.anteil,
    b.plausibel AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox'::text AND x.bezug_id = b.auftrag_id)) AS plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    b.auftrag_id,
    betriebstag(b.start_ts) AS messtag,
    b.station::text AS station,
    b.anteil AS anteil_station,
    b.plausibel AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox'::text AND x.bezug_id = b.auftrag_id)) AS plausibel_station
   FROM v_schimmel_beobachtung b
     LEFT JOIN gemischt g ON g.auftrag_id = b.auftrag_id
  WHERE b.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])
UNION ALL
 SELECT a.charge_nr,
    a.sorte,
    a.schlag,
    a.lagertage,
    s.kg AS schimmel_kg,
    a.eingang_netto_kg + s.kg AS basis_jetzt_kg,
    k.f2 AS anteil,
    anteil_plausibel(k.f2) AND a.lagertage >= 0::numeric AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox'::text AND x.bezug_id = a.auftrag_id)) AS plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    a.auftrag_id,
    betriebstag(a.start_ts) AS messtag,
    'waschen'::text AS station,
    x.g AS anteil_station,
    anteil_plausibel(x.g) AND a.lagertage >= 0::numeric AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox'::text AND x.bezug_id = a.auftrag_id)) AS plausibel_station
   FROM v_auftrag_masse a
     JOIN v_schimmel_menge s ON s.auftrag_id = a.auftrag_id
     LEFT JOIN gemischt g ON g.auftrag_id = a.auftrag_id
     LEFT JOIN LATERAL ( SELECT sum(sl.schimmel_kg) / NULLIF(sum(sl.basis_jetzt_kg), 0::numeric) AS f1
           FROM sortier_lauf_anteil sl
          WHERE sl.charge_nr = a.charge_nr AND sl.start_ts <= a.start_ts) sa ON true
     CROSS JOIN LATERAL ( SELECT s.kg / NULLIF(a.eingang_netto_kg + s.kg, 0::numeric) AS g) x
     CROSS JOIN LATERAL ( SELECT 1::numeric - (1::numeric - LEAST(GREATEST(COALESCE(sa.f1, 0::numeric), 0::numeric), 0.99)) * (1::numeric - LEAST(GREATEST(COALESCE(x.g, 0::numeric), 0::numeric), 0.99)) AS f2) k
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.lagertage IS NOT NULL AND a.eingang_netto_kg IS NOT NULL AND a.eingang_netto_kg > 0::numeric
UNION ALL
 SELECT w.charge_nr,
    w.sorte,
    w.schlag,
    w.lagertage,
    v.faul_kg AS schimmel_kg,
    w.netto_jetzt_kg AS basis_jetzt_kg,
    v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric) AS anteil,
    anteil_plausibel(v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric)) AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox_lager'::text AND x.bezug_id = w.id)) AS plausibel,
    'lager'::text AS quelle,
    NULL::bigint AS auftrag_id,
    betriebstag(w.wiege_ts) AS messtag,
    'lager'::text AS station,
    v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric) AS anteil_station,
    anteil_plausibel(v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric)) AND NOT (EXISTS ( SELECT 1 FROM messung_ausschluss x WHERE x.art = 'palox_lager'::text AND x.bezug_id = w.id)) AS plausibel_station
   FROM v_verdunstung_messung w
     JOIN verdunstung_wiegung v ON v.id = w.id
  WHERE v.faul_kg IS NOT NULL AND v.gemessen AND w.netto_jetzt_kg > 0::numeric AND w.lagertage > 0;

create or replace function v_schimmel_punkte_zaun() returns setof v_schimmel_punkte_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_schimmel_punkte_formel;
end $$;

create or replace view v_schimmel_punkte with (security_invoker = true) as
select * from v_schimmel_punkte_zaun();

do $$
begin
  execute 'drop materialized view if exists erg_punkte cascade';
  execute 'create materialized view erg_punkte as select * from v_schimmel_punkte with no data';
  execute 'grant select on erg_punkte to authenticated';
  execute $q$create index if not exists erg_punkte_charge      on erg_punkte (charge_nr)$q$;
  execute $q$create index if not exists erg_punkte_charge on erg_punkte (charge_nr)$q$;
  execute format('comment on materialized view erg_punkte is %L',
                 'v_schimmel_punkte mit dem Messtag (0079) und seit 0105 mit Station und eigenem Anteil, '
                 'gespeichert für die App. Erneuert mit auswertung_schritt().');
end $$;

create or replace view v_charge_palox with (security_invoker = true) as
select e.charge_nr, e.station,
       zahl(sum(e.basis_jetzt_kg * e.anteil_station) / nullif(sum(e.basis_jetzt_kg), 0), 5, 1)::numeric(10,5) as anteil,
       count(*)::int as n_arbeiten
  from v_schimmel_punkte e
 where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
   and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
   and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
 group by e.charge_nr, e.station;

create or replace view v_palox_erwartung with (security_invoker = true) as
with punkte as materialized (
  select e.sorte, e.station, e.charge_nr, e.messtag, e.lagertage::numeric as t,
         e.basis_jetzt_kg as w, e.anteil_station as y
    from v_schimmel_punkte e
   where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
     and e.lagertage is not null
     and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
     and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')

     and not exists (select 1 from charge hc where hc.nr = e.charge_nr and hc.hagel_anteil > 0)
), anstieg as materialized (
  select k.station, k.zuwachs_je_woche as b from v_palox_station k
), sorten as (
  select distinct sorte from v_kaskade_basis
  union
  select distinct sorte from punkte
), stationen(station) as (
  values ('waschen_sortieren'), ('sortieren'), ('waschen')
), ebenen(rang, ebene, quelle) as (
  values (1, 'sorte', 'Arbeiten dieser Sorte'), (2, 'alle', 'Arbeiten aller Sorten')
), je_ebene as (
  select s.sorte, st.station, e.rang, e.ebene, e.quelle,
         count(p.y)::int                          as n_arbeiten,
         count(distinct p.charge_nr)::int         as n_chargen,
         min(p.messtag)                           as seit,
         max(p.messtag)                           as bis,
         sum(p.w * p.y) / nullif(sum(p.w), 0)     as mittel,
         sum(p.w * p.t) / nullif(sum(p.w), 0)     as lager_mittel,
         stddev_samp(p.y)                         as sd
    from sorten s
   cross join stationen st
   cross join ebenen e
    left join punkte p on p.station = st.station and (e.rang = 2 or p.sorte = s.sorte)
   group by s.sorte, st.station, e.rang, e.ebene, e.quelle
), gueltig as (
  select j.*, a.b,
         greatest(j.mittel - coalesce(a.b, 0) * j.lager_mittel / 7.0, 0) as grund
    from je_ebene j
    left join anstieg a on a.station = j.station
   where j.n_arbeiten >= case when j.rang = 2 then 1 else palox_mindest_arbeiten() end
)
select distinct on (sorte, station)
       sorte, station, ebene, quelle,
       zahl(grund, 5, 1)::numeric(10,5) as anteil,
       zahl(case when n_arbeiten >= 2 and sd is not null
                 then greatest(grund - t_quantil_95(n_arbeiten - 1) * sd / sqrt(n_arbeiten), 0)
                 else grund end, 5, 1)::numeric(10,5) as unten,
       zahl(case when n_arbeiten >= 2 and sd is not null
                 then least(grund + t_quantil_95(n_arbeiten - 1) * sd / sqrt(n_arbeiten), 1)
                 else grund end, 5, 1)::numeric(10,5) as oben,
       n_arbeiten, n_chargen, seit, bis,
       ebene = 'alle' as geliehen,
       zahl(mittel, 5, 1)::numeric(10,5) as mittel,
       zahl(lager_mittel, 1, 100000)::numeric(10,1) as lager_mittel,
       zahl(b, 5, 1)::numeric(10,5) as anstieg_je_woche
  from gueltig
 order by sorte, station, rang;

create materialized view erg_palox_erwartung as
select * from v_palox_erwartung
with no data;

create or replace view v_kaliber_fassung with (security_invoker = true) as
select distinct on (s.sorte) s.sorte,
       (s.kaliber_baender -> 0 ->> 0)::int                                          as lo,
       (s.kaliber_baender -> (jsonb_array_length(s.kaliber_baender) - 1) ->> 1)::int as hi,
       s.gilt_ab
  from sortierschema s
 where s.art = 'kaliber' and s.kaeufer is null and s.gilt_ab <= heute()
   and s.kaliber_baender is not null and jsonb_array_length(s.kaliber_baender) > 0
 order by s.sorte, s.gilt_ab desc;

create or replace view v_kaliber_lauf with (security_invoker = true) as
with lauf as (
  select l.id as lauf_id, l.charge_nr, c.sorte, l.sortiertag, l.auftrag_id
    from sortier_lauf l
    join charge c on c.nr = l.charge_nr
    left join auftrag a on a.id = l.auftrag_id
   where l.sortiertag is not null and (a.id is null or a.abgebrochen_ts is null)
     and exists (select 1 from sortier_gewicht g where g.lauf_id = l.id and g.anzahl > 0 and g.gewicht_g > 0)
), zettel as (
  select l.lauf_id,
         sum(coalesce(m.netto_kg, 1) * (l.sortiertag - m.eingangsdatum))::numeric / nullif(sum(coalesce(m.netto_kg, 1)), 0) as alter_tage,
         count(*)::int as n_paletten
    from lauf l
    join v_auftrag_palette_masse m on m.auftrag_id = l.auftrag_id
   where m.eingangsdatum is not null and m.eingangsdatum <= l.sortiertag
   group by l.lauf_id
), eingang as (
  select l.lauf_id,
         sum(coalesce(p.netto_kg, p.brutto_kg) * (l.sortiertag - p.eingangsdatum))::numeric
           / nullif(sum(coalesce(p.netto_kg, p.brutto_kg)), 0) as alter_tage,
         count(*)::int as n_paletten
    from lauf l
    join v_palette p on p.charge_nr = l.charge_nr and p.eingangsdatum <= l.sortiertag
   group by l.lauf_id
)
select l.lauf_id, l.charge_nr, l.sorte, l.sortiertag, l.auftrag_id,
       coalesce(z.alter_tage, e.alter_tage)                                   as alter_tage,
       case when z.alter_tage is not null then 'zettel'
            when e.alter_tage is not null then 'eingang' end                  as alter_quelle,
       coalesce(z.n_paletten, e.n_paletten)                                   as n_paletten,
       least(greatest(coalesce(kv.mittel, 0), 0), 0.05)::numeric              as r
  from lauf l
  left join zettel z on z.lauf_id = l.lauf_id
  left join eingang e on e.lauf_id = l.lauf_id
  left join v_koeff_verdunstung kv on kv.sorte = l.sorte;

create materialized view mv_kaliber_eingang as
with kuerbis as (
  select l.charge_nr, l.sorte,
         round(g.gewicht_g::numeric / power(1 - l.r, l.alter_tage), 0) as g0,
         g.anzahl,
         g.gewicht_g::numeric / power(1 - l.r, l.alter_tage) * g.anzahl / 1000.0 as masse_kg
    from v_kaliber_lauf l
    join sortier_gewicht g on g.lauf_id = l.lauf_id
   where l.alter_tage is not null and l.alter_tage >= 0 and g.anzahl > 0 and g.gewicht_g > 0
), je as (
  select 'charge'::text as ebene, charge_nr::text as schluessel, g0, sum(masse_kg) as masse_kg, sum(anzahl)::bigint as n_kuerbis
    from kuerbis group by charge_nr, g0
  union all
  select 'sorte', sorte, g0, sum(masse_kg), sum(anzahl)::bigint
    from kuerbis group by sorte, g0
)
select ebene, schluessel, g0, masse_kg, n_kuerbis,
       sum(masse_kg) over (partition by ebene, schluessel order by g0)
         / sum(masse_kg) over (partition by ebene, schluessel) as anteil_bis
  from je
with no data;

create materialized view mv_kaliber_quelle as
with laeufe as (
  select charge_nr, count(*)::int as n
    from v_kaliber_lauf where alter_tage is not null and alter_tage >= 0 group by charge_nr
), je_sorte as (
  select sorte, count(*)::int as n, count(distinct charge_nr)::int as c
    from v_kaliber_lauf where alter_tage is not null and alter_tage >= 0 group by sorte
)
select b.charge_nr, b.sorte, f.lo, f.hi,
       case when lc.n > 0 then 'charge' else 'sorte' end                      as ebene,
       case when lc.n > 0 then b.charge_nr::text else b.sorte end              as schluessel,
       coalesce(lc.n, ls.n)                                                     as n_laeufe,
       case when lc.n > 0
            then format('Sortierdatei der Charge (%s %s), auf den Eingangstag zurückgerechnet',
                        lc.n, case when lc.n = 1 then 'Lauf' else 'Läufe' end)
            else format('Sortierdateien der Sorte (%s %s aus %s %s), auf den Eingangstag zurückgerechnet',
                        ls.n, case when ls.n = 1 then 'Lauf' else 'Läufe' end,
                        ls.c, case when ls.c = 1 then 'Charge' else 'Chargen' end) end as basis
  from v_kaskade_basis b
  join v_kaliber_fassung f on f.sorte = b.sorte
  left join laeufe lc on lc.charge_nr = b.charge_nr
  left join je_sorte ls on ls.sorte = b.sorte
 where coalesce(lc.n, 0) > 0 or coalesce(ls.n, 0) > 0
with no data;

create or replace function kaliber_anteil(p_ebene text, p_schluessel text, p_lo numeric, p_hi numeric, p_q numeric)
returns table (klein numeric, gross numeric)
language sql stable set search_path = public as $$
  select case when p_ebene is null or p_lo is null or coalesce(p_q, 0) <= 0 then null
              else coalesce((select k.anteil_bis from mv_kaliber_eingang k
                              where k.ebene = p_ebene and k.schluessel = p_schluessel and k.g0 < p_lo / p_q
                              order by k.g0 desc limit 1), 0) end,
         case when p_ebene is null or p_hi is null or coalesce(p_q, 0) <= 0 then null
              else 1 - coalesce((select k.anteil_bis from mv_kaliber_eingang k
                                  where k.ebene = p_ebene and k.schluessel = p_schluessel and k.g0 <= p_hi / p_q
                                  order by k.g0 desc limit 1), 0) end
$$;

create materialized view mv_kaskade as
 WITH kohorten AS MATERIALIZED (
         SELECT k.charge_nr,
            k.eingangsdatum,
            k.anteil,
            b.eingang_kg * k.anteil AS eingang_kg
           FROM v_kohorte_anteil k
             JOIN v_kaskade_basis b ON b.charge_nr = k.charge_nr
        ), lieferungen AS MATERIALIZED (
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            sum(v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, 0::numeric)) / NULLIF(sum(v_lieferung_kohorte.masse_kg), 0::numeric) AS alter_tage,
            sum(v_lieferung_kohorte.n_lieferungen)::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE v_lieferung_kohorte.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), entsorgt_lief AS (
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            sum(v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, 0::numeric)) / NULLIF(sum(v_lieferung_kohorte.masse_kg), 0::numeric) AS alter_tage,
            sum(v_lieferung_kohorte.n_lieferungen)::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE v_lieferung_kohorte.buch = 'verlust'::text
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), koeff AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.eingang_kg,
            b.stichtag,
            LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            kv.mittel IS NOT NULL AS r_bekannt,
            kv.n AS r_n,
            kv.basis AS r_basis,
            LEAST(GREATEST(COALESCE(ka.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_klein,
            ka.mittel IS NOT NULL AS a_klein_bekannt,
            ka.n AS klein_n,
            ka.basis AS klein_basis,
            LEAST(GREATEST(COALESCE(kn.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_gross,
            kn.mittel IS NOT NULL AS a_gross_bekannt,
            kn.n AS gross_n,
            kn.basis AS gross_basis,
            LEAST(GREATEST(COALESCE(kf.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_fax,
            kf.mittel IS NOT NULL AS a_fax_bekannt,
            kf.n AS fax_n,
            kf.basis AS fax_basis
           FROM v_kaskade_basis b
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b.sorte
             LEFT JOIN v_koeff_ausschuss ka ON ka.sorte = b.sorte
             LEFT JOIN v_koeff_nebenkanal kn ON kn.sorte = b.sorte
             LEFT JOIN v_koeff_fax kf ON kf.sorte = b.sorte
          WHERE b.eingang_kg > 0::numeric
        ), koeff_norm AS (
         SELECT k.charge_nr,
            k.sorte,
            k.schlag,
            k.eingang_kg,
            k.stichtag,
            k.r,
            k.r_bekannt,
            k.r_n,
            k.r_basis,
            k.a_klein,
            k.a_klein_bekannt,
            k.klein_n,
            k.klein_basis,
            k.a_gross,
            k.a_gross_bekannt,
            k.gross_n,
            k.gross_basis,
            k.a_fax,
            k.a_fax_bekannt,
            k.fax_n,
            k.fax_basis,
            k.a_klein / n.f AS a_klein_n,
            k.a_gross / n.f AS a_gross_n
           FROM koeff k
             CROSS JOIN LATERAL ( SELECT GREATEST(COALESCE(k.a_klein, 0::numeric) + COALESCE(k.a_gross, 0::numeric), 1::numeric) AS f) n
        ), weg AS MATERIALIZED (
         SELECT v_charge_weg.charge_nr,
            v_charge_weg.p_hand,
            v_charge_weg.p_wasch,
            v_charge_weg.weg_quelle
           FROM v_charge_weg
        ), erwartung AS MATERIALIZED (
         SELECT v_palox_erwartung.sorte,
            v_palox_erwartung.station,
            v_palox_erwartung.anteil,
            v_palox_erwartung.unten,
            v_palox_erwartung.oben,
            v_palox_erwartung.n_arbeiten,
            v_palox_erwartung.geliehen,
            v_palox_erwartung.quelle
           FROM v_palox_erwartung
        ), eigen AS MATERIALIZED (
         SELECT v_charge_palox.charge_nr,
            v_charge_palox.station,
            v_charge_palox.anteil,
            v_charge_palox.n_arbeiten
           FROM v_charge_palox
        ), zuwachs AS MATERIALIZED (
         SELECT v_palox_station.station,
            v_palox_station.zuwachs_je_woche
           FROM v_palox_station
        ), je_station AS MATERIALIZED (
         SELECT k.charge_nr,
            p.portion,
            st.station,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.anteil
                    ELSE er.anteil
                END AS f,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.anteil
                    ELSE er.unten
                END AS unten,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.anteil
                    ELSE er.oben
                END AS oben,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.n_arbeiten
                    ELSE er.n_arbeiten
                END AS n,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN false
                    ELSE COALESCE(er.geliehen, false)
                END AS geliehen,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN format('eigene Messung (%s Arbeiten)'::text, ei.n_arbeiten)
                    ELSE er.quelle
                END AS quelle,
            p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL AS eigen
           FROM koeff k
             CROSS JOIN ( VALUES ('ausgelagert'::text), ('lager'::text)) p(portion)
             CROSS JOIN ( VALUES ('waschen_sortieren'::text), ('sortieren'::text), ('waschen'::text)) st(station)
             LEFT JOIN erwartung er ON er.sorte = k.sorte AND er.station = st.station
             LEFT JOIN eigen ei ON ei.charge_nr = k.charge_nr AND ei.station = st.station
        ), roh AS (
         SELECT k.charge_nr,
            'ausgelagert'::text AS portion,
            l.kohorte,
            l.masse_kg AS geliefert_kg,
            COALESCE(l.alter_tage, 0::numeric) AS alter_tage,
            NULL::numeric AS eingang_kohorte_kg,
            l.n_lieferungen
           FROM koeff_norm k
             JOIN lieferungen l ON l.charge_nr = k.charge_nr
        UNION ALL
         SELECT k.charge_nr,
            'entsorgt'::text AS text,
            e.kohorte,
            e.masse_kg,
            COALESCE(e.alter_tage, 0::numeric) AS "coalesce",
            NULL::numeric AS "numeric",
            e.n_lieferungen
           FROM koeff_norm k
             JOIN entsorgt_lief e ON e.charge_nr = k.charge_nr
        UNION ALL
         SELECT k.charge_nr,
            'lager'::text AS text,
            c.eingangsdatum,
            NULL::numeric AS "numeric",
            GREATEST((k.stichtag - c.eingangsdatum)::numeric, 0::numeric) AS "greatest",
            c.eingang_kg,
            0
           FROM koeff_norm k
             JOIN kohorten c ON c.charge_nr = k.charge_nr
        ), kal AS MATERIALIZED (
         SELECT q.charge_nr, q.ebene, q.schluessel, q.lo, q.hi, q.n_laeufe, q.basis
           FROM mv_kaliber_quelle q
        ), hagel AS MATERIALIZED (
         SELECT c.nr AS charge_nr, c.hagel_anteil AS h
           FROM charge c
          WHERE c.hagel_anteil > 0::numeric
        ), teile AS (
         SELECT k.charge_nr,
            k.sorte,
            k.schlag,
            k.eingang_kg,
            k.stichtag,
            k.r,
            k.r_bekannt,
            k.r_n,
            k.r_basis,
            k.a_klein,
            k.a_klein_bekannt OR ka.klein IS NOT NULL AS a_klein_bekannt,
            COALESCE(kq.n_laeufe, k.klein_n) AS klein_n,
            COALESCE(kq.basis, k.klein_basis) AS klein_basis,
            k.a_gross,
            k.a_gross_bekannt OR ka.gross IS NOT NULL AS a_gross_bekannt,
            COALESCE(kq.n_laeufe, k.gross_n) AS gross_n,
            COALESCE(kq.basis, k.gross_basis) AS gross_basis,
            k.a_fax,
            k.a_fax_bekannt,
            k.fax_n,
            k.fax_basis,
            COALESCE(ka.klein, k.a_klein_n) AS a_klein_n,
            COALESCE(ka.gross, k.a_gross_n) AS a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            hh.h AS hagel,
            COALESCE(ws.eigen, false) OR COALESCE(s.eigen, false) OR COALESCE(wa.eigen, false) AS f_eigen,
            w.p_hand,
            w.p_wasch,
            w.weg_quelle,
            nach.f_ws,
            nach.f_s,
            nach.g_w,
            hagel_f(palox_f(w.p_hand, w.p_wasch, nach.f_ws, nach.f_s, nach.g_w), hh.h) AS f_roh,
            hagel_f(palox_f_nach(w.p_hand, w.p_wasch, ws.unten, s.unten, wa.unten, b.b_ws, b.b_s, b.b_w, t.alter_tage), hh.h) AS f_unten_roh,
            hagel_f(palox_f_nach(w.p_hand, w.p_wasch, ws.oben, s.oben, wa.oben, b.b_ws, b.b_s, b.b_w, t.alter_tage), hh.h) AS f_oben_roh,
            LEAST(
                CASE
                    WHEN w.p_hand > 0::numeric THEN ws.n
                    ELSE NULL::integer
                END,
                CASE
                    WHEN w.p_hand < 1::numeric THEN s.n
                    ELSE NULL::integer
                END,
                CASE
                    WHEN w.p_hand < 1::numeric AND w.p_wasch > 0::numeric THEN wa.n
                    ELSE NULL::integer
                END) AS f_n,
            COALESCE(
                CASE
                    WHEN w.p_hand > 0::numeric THEN ws.geliehen
                    ELSE NULL::boolean
                END, false) OR COALESCE(
                CASE
                    WHEN w.p_hand < 1::numeric THEN s.geliehen
                    ELSE NULL::boolean
                END, false) OR COALESCE(
                CASE
                    WHEN w.p_hand < 1::numeric AND w.p_wasch > 0::numeric THEN wa.geliehen
                    ELSE NULL::boolean
                END, false) AS f_geliehen,
            concat_ws('; '::text,
                CASE
                    WHEN w.p_hand > 0::numeric THEN 'Waschen + Sortieren: '::text || COALESCE(ws.quelle, 'kein Wert'::text)
                    ELSE NULL::text
                END,
                CASE
                    WHEN w.p_hand < 1::numeric THEN 'Sortieren: '::text || COALESCE(s.quelle, 'kein Wert'::text)
                    ELSE NULL::text
                END,
                CASE
                    WHEN w.p_hand < 1::numeric AND w.p_wasch > 0::numeric THEN 'Waschen: '::text || COALESCE(wa.quelle, 'kein Wert'::text)
                    ELSE NULL::text
                END,
                CASE
                    WHEN w.weg_quelle IS NOT NULL THEN 'Weg nach '::text || w.weg_quelle
                    ELSE NULL::text
                END,
                CASE
                    WHEN hh.h > 0::numeric THEN format('Hagelschaden %s %%'::text, round(hh.h * 100::numeric))
                    ELSE NULL::text
                END) AS f_quelle,
            b.b_ws,
            b.b_s,
            b.b_w,
            (w.p_hand = 0::numeric OR b.b_ws IS NOT NULL) AND (w.p_hand = 1::numeric OR b.b_s IS NOT NULL) AND (w.p_hand = 1::numeric OR COALESCE(w.p_wasch, 0::numeric) = 0::numeric OR b.b_w IS NOT NULL) AS zuwachs_roh
           FROM koeff_norm k
             JOIN roh t ON t.charge_nr = k.charge_nr
             LEFT JOIN weg w ON w.charge_nr = k.charge_nr
             LEFT JOIN je_station ws ON ws.charge_nr = k.charge_nr AND ws.station = 'waschen_sortieren'::text AND ws.portion =
                CASE
                    WHEN t.portion = 'lager'::text THEN 'lager'::text
                    ELSE 'ausgelagert'::text
                END
             LEFT JOIN je_station s ON s.charge_nr = k.charge_nr AND s.station = 'sortieren'::text AND s.portion =
                CASE
                    WHEN t.portion = 'lager'::text THEN 'lager'::text
                    ELSE 'ausgelagert'::text
                END
             LEFT JOIN je_station wa ON wa.charge_nr = k.charge_nr AND wa.station = 'waschen'::text AND wa.portion =
                CASE
                    WHEN t.portion = 'lager'::text THEN 'lager'::text
                    ELSE 'ausgelagert'::text
                END
             LEFT JOIN zuwachs zws ON zws.station = 'waschen_sortieren'::text
             LEFT JOIN zuwachs zs ON zs.station = 'sortieren'::text
             LEFT JOIN zuwachs zw ON zw.station = 'waschen'::text
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN ws.eigen THEN 0::numeric
                            ELSE zws.zuwachs_je_woche
                        END AS b_ws,
                        CASE
                            WHEN s.eigen THEN 0::numeric
                            ELSE zs.zuwachs_je_woche
                        END AS b_s,
                        CASE
                            WHEN wa.eigen THEN 0::numeric
                            ELSE zw.zuwachs_je_woche
                        END AS b_w) b
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN ws.f IS NULL THEN NULL::numeric
                            ELSE LEAST(GREATEST(ws.f + COALESCE(b.b_ws, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric)
                        END AS f_ws,
                        CASE
                            WHEN s.f IS NULL THEN NULL::numeric
                            ELSE LEAST(GREATEST(s.f + COALESCE(b.b_s, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric)
                        END AS f_s,
                        CASE
                            WHEN wa.f IS NULL THEN NULL::numeric
                            ELSE LEAST(GREATEST(wa.f + COALESCE(b.b_w, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric)
                        END AS g_w) nach
             LEFT JOIN kal kq ON kq.charge_nr = k.charge_nr
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - k.r, t.alter_tage)) ka ON true
             LEFT JOIN hagel hg ON hg.charge_nr = k.charge_nr
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN hg.h IS NULL OR t.portion = 'entsorgt'::text THEN 0::numeric
                            WHEN t.portion = 'lager'::text THEN hg.h
                            WHEN COALESCE(ws.eigen, false) OR COALESCE(s.eigen, false) OR COALESCE(wa.eigen, false) THEN 0::numeric
                            ELSE hg.h
                        END AS h) hh
        ), mit_f AS (
         SELECT t.charge_nr,
            t.sorte,
            t.schlag,
            t.eingang_kg,
            t.stichtag,
            t.r,
            t.r_bekannt,
            t.r_n,
            t.r_basis,
            t.a_klein,
            t.a_klein_bekannt,
            t.klein_n,
            t.klein_basis,
            t.a_gross,
            t.a_gross_bekannt,
            t.gross_n,
            t.gross_basis,
            t.a_fax,
            t.a_fax_bekannt,
            t.fax_n,
            t.fax_basis,
            t.a_klein_n,
            t.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            t.hagel,
            t.f_eigen,
            t.p_hand,
            t.p_wasch,
            t.weg_quelle,
            t.f_ws,
            t.f_s,
            t.g_w,
            t.f_roh,
            t.f_unten_roh,
            t.f_oben_roh,
            t.f_n,
            t.f_geliehen,
            t.f_quelle,
            t.b_ws,
            t.b_s,
            t.b_w,
            t.zuwachs_roh,
            t.f_roh IS NOT NULL AS f_bekannt,
            COALESCE(t.f_roh, 0::numeric) AS f,
            COALESCE(t.f_unten_roh, t.f_roh, 0::numeric) AS f_unten,
            COALESCE(t.f_oben_roh, t.f_roh, 0::numeric) AS f_oben,
                CASE
                    WHEN t.f_roh IS NULL OR t.f_n IS NULL OR t.f_n < 2 THEN 0::numeric
                    ELSE (COALESCE(t.f_oben_roh, t.f_roh) - COALESCE(t.f_unten_roh, t.f_roh)) / (2::numeric * t_quantil_95(t.f_n - 1))
                END AS f_se,
            t.f_roh IS NOT NULL AND COALESCE(t.zuwachs_roh, false) AS zuwachs_bekannt
           FROM teile t
        ), anteil AS (
         SELECT x.charge_nr,
            x.sorte,
            x.schlag,
            x.eingang_kg,
            x.stichtag,
            x.r,
            x.r_bekannt,
            x.r_n,
            x.r_basis,
            x.a_klein,
            x.a_klein_bekannt,
            x.klein_n,
            x.klein_basis,
            x.a_gross,
            x.a_gross_bekannt,
            x.gross_n,
            x.gross_basis,
            x.a_fax,
            x.a_fax_bekannt,
            x.fax_n,
            x.fax_basis,
            x.a_klein_n,
            x.a_gross_n,
            x.portion,
            x.kohorte,
            x.geliefert_kg,
            x.alter_tage,
            x.eingang_kohorte_kg,
            x.n_lieferungen,
            x.hagel,
            x.f_eigen,
            x.p_hand,
            x.p_wasch,
            x.weg_quelle,
            x.f_ws,
            x.f_s,
            x.g_w,
            x.f_roh,
            x.f_unten_roh,
            x.f_oben_roh,
            x.f_n,
            x.f_geliehen,
            x.f_quelle,
            x.b_ws,
            x.b_s,
            x.b_w,
            x.zuwachs_roh,
            x.f_bekannt,
            x.f,
            x.f_unten,
            x.f_oben,
            x.f_se,
            x.zuwachs_bekannt,
            GREATEST(power(1::numeric - x.r, x.alter_tage) * (1::numeric - x.f) * (1::numeric - x.a_klein_n - x.a_gross_n) * (1::numeric - x.a_fax), 0.25) AS verkaufsfaehig_anteil,
            GREATEST(power(1::numeric - x.r, x.alter_tage), 0.25) AS verdunstungs_anteil
           FROM mit_f x
        ), ausgelagert AS (
         SELECT a.charge_nr,
            a.sorte,
            a.schlag,
            a.eingang_kg,
            a.stichtag,
            a.r,
            a.r_bekannt,
            a.r_n,
            a.r_basis,
            a.a_klein,
            a.a_klein_bekannt,
            a.klein_n,
            a.klein_basis,
            a.a_gross,
            a.a_gross_bekannt,
            a.gross_n,
            a.gross_basis,
            a.a_fax,
            a.a_fax_bekannt,
            a.fax_n,
            a.fax_basis,
            a.a_klein_n,
            a.a_gross_n,
            a.portion,
            a.kohorte,
            a.geliefert_kg,
            a.alter_tage,
            a.eingang_kohorte_kg,
            a.n_lieferungen,
            a.hagel,
            a.f_eigen,
            a.p_hand,
            a.p_wasch,
            a.weg_quelle,
            a.f_ws,
            a.f_s,
            a.g_w,
            a.f_roh,
            a.f_unten_roh,
            a.f_oben_roh,
            a.f_n,
            a.f_geliehen,
            a.f_quelle,
            a.b_ws,
            a.b_s,
            a.b_w,
            a.zuwachs_roh,
            a.f_bekannt,
            a.f,
            a.f_unten,
            a.f_oben,
            a.f_se,
            a.zuwachs_bekannt,
            a.verkaufsfaehig_anteil,
            a.verdunstungs_anteil,
                CASE
                    WHEN a.portion = 'entsorgt'::text THEN a.geliefert_kg / a.verdunstungs_anteil
                    ELSE a.geliefert_kg / a.verkaufsfaehig_anteil
                END AS m0,
            0::numeric AS ueberzaehlung_kg
           FROM anteil a
          WHERE a.portion = ANY (ARRAY['ausgelagert'::text, 'entsorgt'::text])
        ), lager AS (
         SELECT a.charge_nr,
            a.sorte,
            a.schlag,
            a.eingang_kg,
            a.stichtag,
            a.r,
            a.r_bekannt,
            a.r_n,
            a.r_basis,
            a.a_klein,
            a.a_klein_bekannt,
            a.klein_n,
            a.klein_basis,
            a.a_gross,
            a.a_gross_bekannt,
            a.gross_n,
            a.gross_basis,
            a.a_fax,
            a.a_fax_bekannt,
            a.fax_n,
            a.fax_basis,
            a.a_klein_n,
            a.a_gross_n,
            a.portion,
            a.kohorte,
            a.geliefert_kg,
            a.alter_tage,
            a.eingang_kohorte_kg,
            a.n_lieferungen,
            a.hagel,
            a.f_eigen,
            a.p_hand,
            a.p_wasch,
            a.weg_quelle,
            a.f_ws,
            a.f_s,
            a.g_w,
            a.f_roh,
            a.f_unten_roh,
            a.f_oben_roh,
            a.f_n,
            a.f_geliehen,
            a.f_quelle,
            a.b_ws,
            a.b_s,
            a.b_w,
            a.zuwachs_roh,
            a.f_bekannt,
            a.f,
            a.f_unten,
            a.f_oben,
            a.f_se,
            a.zuwachs_bekannt,
            a.verkaufsfaehig_anteil,
            a.verdunstungs_anteil,
            GREATEST(a.eingang_kohorte_kg - COALESCE(x.m0, 0::numeric), 0::numeric) AS m0,
            GREATEST(COALESCE(x.m0, 0::numeric) - a.eingang_kohorte_kg, 0::numeric) AS ueberzaehlung_kg
           FROM anteil a
             LEFT JOIN ( SELECT ausgelagert.charge_nr,
                    ausgelagert.kohorte,
                    sum(ausgelagert.m0) AS m0
                   FROM ausgelagert
                  GROUP BY ausgelagert.charge_nr, ausgelagert.kohorte) x ON x.charge_nr = a.charge_nr AND x.kohorte = a.kohorte
          WHERE a.portion = 'lager'::text
        ), alle AS (
         SELECT ausgelagert.charge_nr,
            ausgelagert.sorte,
            ausgelagert.schlag,
            ausgelagert.eingang_kg,
            ausgelagert.stichtag,
            ausgelagert.r,
            ausgelagert.r_bekannt,
            ausgelagert.r_n,
            ausgelagert.r_basis,
            ausgelagert.a_klein,
            ausgelagert.a_klein_bekannt,
            ausgelagert.klein_n,
            ausgelagert.klein_basis,
            ausgelagert.a_gross,
            ausgelagert.a_gross_bekannt,
            ausgelagert.gross_n,
            ausgelagert.gross_basis,
            ausgelagert.a_fax,
            ausgelagert.a_fax_bekannt,
            ausgelagert.fax_n,
            ausgelagert.fax_basis,
            ausgelagert.a_klein_n,
            ausgelagert.a_gross_n,
            ausgelagert.portion,
            ausgelagert.kohorte,
            ausgelagert.geliefert_kg,
            ausgelagert.alter_tage,
            ausgelagert.eingang_kohorte_kg,
            ausgelagert.n_lieferungen,
            ausgelagert.hagel,
            ausgelagert.f_eigen,
            ausgelagert.p_hand,
            ausgelagert.p_wasch,
            ausgelagert.weg_quelle,
            ausgelagert.f_ws,
            ausgelagert.f_s,
            ausgelagert.g_w,
            ausgelagert.f_roh,
            ausgelagert.f_unten_roh,
            ausgelagert.f_oben_roh,
            ausgelagert.f_n,
            ausgelagert.f_geliehen,
            ausgelagert.f_quelle,
            ausgelagert.b_ws,
            ausgelagert.b_s,
            ausgelagert.b_w,
            ausgelagert.zuwachs_roh,
            ausgelagert.f_bekannt,
            ausgelagert.f,
            ausgelagert.f_unten,
            ausgelagert.f_oben,
            ausgelagert.f_se,
            ausgelagert.zuwachs_bekannt,
            ausgelagert.verkaufsfaehig_anteil,
            ausgelagert.verdunstungs_anteil,
            ausgelagert.m0,
            ausgelagert.ueberzaehlung_kg
           FROM ausgelagert
        UNION ALL
         SELECT lager.charge_nr,
            lager.sorte,
            lager.schlag,
            lager.eingang_kg,
            lager.stichtag,
            lager.r,
            lager.r_bekannt,
            lager.r_n,
            lager.r_basis,
            lager.a_klein,
            lager.a_klein_bekannt,
            lager.klein_n,
            lager.klein_basis,
            lager.a_gross,
            lager.a_gross_bekannt,
            lager.gross_n,
            lager.gross_basis,
            lager.a_fax,
            lager.a_fax_bekannt,
            lager.fax_n,
            lager.fax_basis,
            lager.a_klein_n,
            lager.a_gross_n,
            lager.portion,
            lager.kohorte,
            lager.geliefert_kg,
            lager.alter_tage,
            lager.eingang_kohorte_kg,
            lager.n_lieferungen,
            lager.hagel,
            lager.f_eigen,
            lager.p_hand,
            lager.p_wasch,
            lager.weg_quelle,
            lager.f_ws,
            lager.f_s,
            lager.g_w,
            lager.f_roh,
            lager.f_unten_roh,
            lager.f_oben_roh,
            lager.f_n,
            lager.f_geliehen,
            lager.f_quelle,
            lager.b_ws,
            lager.b_s,
            lager.b_w,
            lager.zuwachs_roh,
            lager.f_bekannt,
            lager.f,
            lager.f_unten,
            lager.f_oben,
            lager.f_se,
            lager.zuwachs_bekannt,
            lager.verkaufsfaehig_anteil,
            lager.verdunstungs_anteil,
            lager.m0,
            lager.ueberzaehlung_kg
           FROM lager
        ), kaskade AS (
         SELECT t.charge_nr,
            t.sorte,
            t.schlag,
            t.eingang_kg,
            t.stichtag,
            t.r,
            t.r_bekannt,
            t.r_n,
            t.r_basis,
            t.a_klein,
            t.a_klein_bekannt,
            t.klein_n,
            t.klein_basis,
            t.a_gross,
            t.a_gross_bekannt,
            t.gross_n,
            t.gross_basis,
            t.a_fax,
            t.a_fax_bekannt,
            t.fax_n,
            t.fax_basis,
            t.a_klein_n,
            t.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            t.hagel,
            t.f_eigen,
            t.p_hand,
            t.p_wasch,
            t.weg_quelle,
            t.f_ws,
            t.f_s,
            t.g_w,
            t.f_roh,
            t.f_unten_roh,
            t.f_oben_roh,
            t.f_n,
            t.f_geliehen,
            t.f_quelle,
            t.b_ws,
            t.b_s,
            t.b_w,
            t.zuwachs_roh,
            t.f_bekannt,
            t.f,
            t.f_unten,
            t.f_oben,
            t.f_se,
            t.zuwachs_bekannt,
            t.verkaufsfaehig_anteil,
            t.verdunstungs_anteil,
            t.m0,
            t.ueberzaehlung_kg,
            t.m0 * power(1::numeric - t.r, t.alter_tage) AS m1,
            (- t.m0) * t.alter_tage * power(1::numeric - t.r, GREATEST(t.alter_tage - 1::numeric, 0::numeric)) AS d_m1_r
           FROM alle t
          WHERE t.m0 > 0::numeric OR t.ueberzaehlung_kg > 0::numeric
        )
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    m0,
    m1,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f)
        END AS m2,
    r,
    f,
    f_unten,
    f_oben,
    f_se,
    f_ws,
    f_s,
    g_w,
    p_hand,
    p_wasch,
    f_quelle,
    f_geliehen,
    b_ws,
    b_s,
    b_w,
    zuwachs_bekannt,
    a_klein_n,
    a_gross_n,
    a_fax,
    d_m1_r,
    r_n,
    r_basis,
    klein_n,
    klein_basis,
    gross_n,
    gross_basis,
    f_n,
    fax_n,
    fax_basis,
    r_bekannt,
    f_bekannt,
    a_klein_bekannt,
    a_gross_bekannt,
    a_fax_bekannt,
    m0 - m1 AS verdunstung_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN m1
            ELSE m1 * f
        END AS schimmel_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * a_klein_n
        END AS klein_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * a_gross_n
        END AS nebenkanal_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * (1::numeric - a_klein_n - a_gross_n) * a_fax
        END AS fax_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * (1::numeric - a_klein_n - a_gross_n) * (1::numeric - a_fax)
        END AS verkaufsfaehig_kg,
    kohorte,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE geliefert_kg
        END AS geliefert_kg,
    ueberzaehlung_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0
            ELSE n_lieferungen
        END AS n_lieferungen,
    verkaufsfaehig_anteil,
    hagel,
    f_eigen
   FROM kaskade
with no data;

create or replace function lager_schluessel()
returns table (charge_nr integer, sorte text, basis text, schluessel text, r numeric)
language sql stable set search_path = public as $$
with liegend as (
  select k.charge_nr, k.sorte, sum(k.m0 * k.r) / nullif(sum(k.m0), 0) as r
    from mv_kaskade k where k.portion = 'lager' group by k.charge_nr, k.sorte
), rate_sorte as (
  select sorte, sum(m0 * r) / nullif(sum(m0), 0) as r
    from mv_kaskade where portion = 'lager' group by sorte
), mit_csv as (
  select distinct l.charge_nr, c.sorte
    from sortier_lauf l join charge c on c.nr = l.charge_nr
    join sortier_gewicht g on g.lauf_id = l.id
   where g.klasse = 'kaliber' and g.anzahl > 0 and g.gewicht_g > 0
     and l.sortiertag is not null
)
select l.charge_nr, l.sorte,
       case when exists (select 1 from mit_csv m where m.charge_nr = l.charge_nr) then 'charge'
            when exists (select 1 from mit_csv m where m.sorte = l.sorte)         then 'sorte'
            else 'keine' end,
       case when exists (select 1 from mit_csv m where m.charge_nr = l.charge_nr) then l.charge_nr::text
            else l.sorte end,
       case when exists (select 1 from mit_csv m where m.charge_nr = l.charge_nr) then l.r
            else rs.r end
  from liegend l
  left join rate_sorte rs on rs.sorte = l.sorte
$$;

create or replace function kuerbis_stichtag(p_h integer)
returns table (basis text, schluessel text, sorte text, h integer, anzahl integer, g double precision)
language sql stable set search_path = public as $$
with stichtag as (
  select heute() as heute
), lauf as materialized (
  -- Der Sortiertag steht seit 0082 an der Lesung: abgelesen bei einer
  -- Lauf-Datei, abgeleitet bei einer Sammeldatei (sortiertag_quelle sagt
  -- welches). Vorher stand hier betriebstag(l.datei_zeit).
  select l.id, l.charge_nr, c.sorte, l.sortiertag
    from sortier_lauf l join charge c on c.nr = l.charge_nr
   where l.sortiertag is not null
), kuerbis as (
  -- Nur die Klasse „kaliber": zu klein und Nebenkanal sind aus der
  -- verkaufsfähigen Masse schon heraus (a_klein_n, a_gross_n).
  select l.charge_nr, l.sorte, l.sortiertag, g.gewicht_g, g.anzahl
    from sortier_gewicht g join lauf l on l.id = g.lauf_id
   where g.klasse = 'kaliber' and g.anzahl > 0 and g.gewicht_g > 0
), schluessel as (
  select 'charge' as basis, s.schluessel, s.sorte, s.charge_nr, s.r
    from lager_schluessel() s where s.basis = 'charge'
  union
  select distinct 'sorte', s.sorte, s.sorte, null::int, s.r
    from lager_schluessel() s where s.basis = 'sorte'
)
select v.basis, v.schluessel, v.sorte, p_h, k.anzahl,
       k.gewicht_g * power((1 - coalesce(v.r, 0))::double precision,
                           greatest(t.heute + p_h - k.sortiertag, 0)::double precision)
  from schluessel v
  join kuerbis k on k.charge_nr = v.charge_nr
  cross join stichtag t
 where v.basis = 'charge'
union all
select v.basis, v.schluessel, v.sorte, p_h, k.anzahl,
       k.gewicht_g * power((1 - coalesce(v.r, 0))::double precision,
                           greatest(t.heute + p_h - k.sortiertag, 0)::double precision)
  from schluessel v
  join kuerbis k on k.sorte = v.sorte
  cross join stichtag t
 where v.basis = 'sorte'
$$;

create materialized view erg_verlauf as
 WITH tag AS MATERIALIZED (
         SELECT heute() AS heute,
            stichtag() AS stichtag
        ), wochen AS MATERIALIZED (
         SELECT w_1.w::date AS woche,
            (w_1.w + '6 days'::interval)::date AS bis
           FROM tag t,
            LATERAL generate_series(date_trunc('week'::text, COALESCE(( SELECT min(palette.eingangsdatum) AS min
                   FROM palette), t.heute)::timestamp with time zone)::date::timestamp with time zone, date_trunc('week'::text, GREATEST(t.stichtag, t.heute + 84)::timestamp with time zone)::date::timestamp with time zone, '7 days'::interval) w_1(w)
        UNION
         SELECT date_trunc('week'::text, t.heute::timestamp with time zone)::date AS date_trunc,
            t.heute
           FROM tag t
        ), gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text AS text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text AS text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text AS text,
            v_kaskade_basis.charge_nr::text AS charge_nr,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        ), portionen AS MATERIALIZED (
         SELECT k.charge_nr,
            k.portion,
            k.kohorte,
            k.m0,
            k.r,
            k.f,
            k.f_ws,
            k.f_s,
            k.g_w,
            k.p_hand,
            k.p_wasch,
            k.b_ws,
            k.b_s,
            k.b_w,
            k.zuwachs_bekannt,
            k.a_klein_n,
            k.a_gross_n,
            k.a_fax,
            k.hagel,
            k.alter_tage,
                CASE
                    WHEN k.portion = 'ausgelagert'::text THEN k.kohorte + round(k.alter_tage)::integer
                    ELSE NULL::date
                END AS liefertag,
                CASE
                    WHEN k.portion = 'ausgelagert'::text THEN k.fax_kg
                    ELSE 0::numeric
                END AS fax_kg
           FROM mv_kaskade k
          WHERE k.m0 > 0::numeric AND k.kohorte IS NOT NULL
        ), lieferanteil AS MATERIALIZED (
         SELECT w_1.bis,
            l.charge_nr,
            sum(l.masse_kg) FILTER (WHERE l.datum <= w_1.bis) / NULLIF(sum(l.masse_kg), 0::numeric) AS q
           FROM wochen w_1
             CROSS JOIN v_lieferung_charge_tag l
          WHERE l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])
          GROUP BY w_1.bis, l.charge_nr
        ), je_woche AS (
         SELECT w_1.woche,
            w_1.bis,
            p.charge_nr,
            q.q * (p.m0 - n.d) + (1::numeric - q.q) * (p.m0 - n.u) AS verdunstung_kg,
            q.q * n.d * f.d + (1::numeric - q.q) * n.u * f.u AS schimmel_kg,
            q.q * p.fax_kg AS fax_kg,
            (1::numeric - q.q) * p.m0 AS lager_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) AS gute_ware_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * ku.kn AS kanal_lager_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * (1::numeric - ku.kn) * p.a_fax AS fax_lager_kg,
            q.q * n.d * (1::numeric - f.d) * (p.a_klein_n + p.a_gross_n) AS aussortiert_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * (1::numeric - ku.kn) * (1::numeric - p.a_fax) AS verkaufsfaehig_kg
           FROM wochen w_1
             JOIN portionen p ON p.kohorte <= w_1.bis
             CROSS JOIN tag d_1
             LEFT JOIN lieferanteil la ON la.bis = w_1.bis AND la.charge_nr = p.charge_nr
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.liefertag IS NULL THEN 0::numeric
                            ELSE LEAST(GREATEST(COALESCE(la.q,
                            CASE
                                WHEN p.liefertag <= w_1.bis THEN 1::numeric
                                ELSE 0::numeric
                            END), 0::numeric), 1::numeric)
                        END AS q) q
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.liefertag IS NULL THEN GREATEST(w_1.bis - p.kohorte, 0)::numeric
                            ELSE LEAST(GREATEST(w_1.bis - p.kohorte, 0)::numeric, p.alter_tage)
                        END AS u) t
             CROSS JOIN LATERAL ( SELECT p.m0 * power(1::numeric - p.r, COALESCE(p.alter_tage, 0::numeric)) AS d,
                    p.m0 * power(1::numeric - p.r, t.u) AS u) n
             LEFT JOIN mv_kaliber_quelle kq ON kq.charge_nr = p.charge_nr
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - p.r, t.u)) kl ON true
             CROSS JOIN LATERAL ( SELECT COALESCE(kl.klein + kl.gross, p.a_klein_n + p.a_gross_n) AS kn) ku
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(p.p_hand, p.p_wasch, p.f_ws, p.f_s, p.g_w, p.b_ws, p.b_s, p.b_w, 0::numeric), p.hagel), p.f)
                            ELSE p.f
                        END AS d,
                        CASE
                            WHEN p.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(p.p_hand, p.p_wasch, p.f_ws, p.f_s, p.g_w, p.b_ws, p.b_s, p.b_w, (LEAST(w_1.bis, COALESCE(p.liefertag, w_1.bis)) - COALESCE(p.liefertag, d_1.heute))::numeric), p.hagel), p.f)
                            ELSE p.f
                        END AS u) f
        ), je_charge AS MATERIALIZED (
         SELECT je_woche.woche,
            je_woche.bis,
            je_woche.charge_nr,
            sum(je_woche.verdunstung_kg) AS verdunstung_kg,
            sum(je_woche.schimmel_kg) AS schimmel_kg,
            sum(je_woche.fax_kg) AS fax_kg,
            sum(je_woche.gute_ware_kg) AS im_haus_kg,
            sum(je_woche.lager_kg) AS lager_kg,
            sum(je_woche.kanal_lager_kg) AS kanal_kg,
            sum(je_woche.fax_lager_kg) AS fax_lager_kg,
            sum(je_woche.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(je_woche.aussortiert_kg) AS aussortiert_kg
           FROM je_woche
          GROUP BY je_woche.woche, je_woche.bis, je_woche.charge_nr
        ), verlust AS (
         SELECT j.woche,
            j.bis,
            g.gruppe,
            g.schluessel,
            sum(j.verdunstung_kg) AS verdunstung_kg,
            sum(j.schimmel_kg) AS schimmel_kg,
            sum(j.fax_kg) AS fax_kg,
            sum(j.im_haus_kg) AS im_haus_kg,
            sum(j.lager_kg) AS lager_kg,
            sum(j.kanal_kg) AS kanal_kg,
            sum(j.fax_lager_kg) AS fax_lager_kg,
            sum(j.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(j.aussortiert_kg) AS aussortiert_kg
           FROM je_charge j
             JOIN gruppen g ON g.charge_nr = j.charge_nr
          GROUP BY j.woche, j.bis, g.gruppe, g.schluessel
        ), eingang_charge AS MATERIALIZED (
         SELECT w_1.woche,
            w_1.bis,
            k.charge_nr,
            sum(k.eingang_kg) AS kg
           FROM wochen w_1
             JOIN v_charge_kohorte k ON k.eingangsdatum <= w_1.bis
          GROUP BY w_1.woche, w_1.bis, k.charge_nr
        ), eingang AS (
         SELECT e_1.woche,
            e_1.bis,
            g.gruppe,
            g.schluessel,
            sum(e_1.kg) AS kg
           FROM eingang_charge e_1
             JOIN gruppen g ON g.charge_nr = e_1.charge_nr
          GROUP BY e_1.woche, e_1.bis, g.gruppe, g.schluessel
        ), ausgang_charge AS MATERIALIZED (
         SELECT w_1.woche,
            w_1.bis,
            l.charge_nr,
            sum(l.masse_kg) AS kg
           FROM wochen w_1
             JOIN v_lieferung_charge_tag l ON l.datum <= w_1.bis
          GROUP BY w_1.woche, w_1.bis, l.charge_nr
        ), ausgang AS (
         SELECT a_1.woche,
            a_1.bis,
            g.gruppe,
            g.schluessel,
            sum(a_1.kg) AS kg
           FROM ausgang_charge a_1
             JOIN gruppen g ON g.charge_nr = a_1.charge_nr
          GROUP BY a_1.woche, a_1.bis, g.gruppe, g.schluessel
        ), liste AS (
         SELECT DISTINCT gruppen.gruppe,
            gruppen.schluessel
           FROM gruppen
        )
 SELECT w.woche,
    w.bis,
    w.bis > d.heute AS prognose,
    s.gruppe,
    s.schluessel,
    zahl(COALESCE(e.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS eingang_kum_kg,
    zahl(COALESCE(a.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgang_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_kum_kg,
    zahl(COALESCE(v.schimmel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_kum_kg,
    zahl(COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric) + COALESCE(v.schimmel_kg, 0::numeric) + COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_kum_kg,
    zahl(COALESCE(v.im_haus_kg, 0::numeric) + COALESCE(v.aussortiert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_kg,
    zahl(COALESCE(v.lager_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(COALESCE(v.verkaufsfaehig_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(COALESCE(v.kanal_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_kg,
    zahl(COALESCE(v.fax_lager_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_lager_kg,
    zahl(COALESCE(v.aussortiert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS aussortiert_kg
   FROM wochen w
     CROSS JOIN liste s
     CROSS JOIN tag d
     LEFT JOIN verlust v ON v.bis = w.bis AND v.gruppe = s.gruppe AND v.schluessel = s.schluessel
     LEFT JOIN eingang e ON e.bis = w.bis AND e.gruppe = s.gruppe AND e.schluessel = s.schluessel
     LEFT JOIN ausgang a ON a.bis = w.bis AND a.gruppe = s.gruppe AND a.schluessel = s.schluessel
with no data;

create view v_hochrechnung_basis with (security_invoker = true) as
 WITH je_charge AS (
         SELECT mv_kaskade.charge_nr,
            sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text) AS ausgelagert_kg,
            sum(mv_kaskade.m0 * mv_kaskade.alter_tage) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric) AS alter_ausgelagert,
            sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS lager_kg,
            sum(mv_kaskade.m0 * mv_kaskade.alter_tage) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS alter_lager,
            sum(mv_kaskade.verkaufsfaehig_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS verkaufsfaehig_lager_kg,
            sum(mv_kaskade.geliefert_kg) AS geliefert_kg,
            sum(mv_kaskade.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(mv_kaskade.n_lieferungen)::integer AS n_lieferung_kohorten,
            min(mv_kaskade.kohorte) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric) AS rest_von,
            max(mv_kaskade.kohorte) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric) AS rest_bis,
            count(*) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric)::integer AS n_rest_kohorten,
            sum(mv_kaskade.m0 * (mv_kaskade.kohorte - '2000-01-01'::date)::numeric) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS rest_tage_seit_epoche,
                CASE
                    WHEN bool_and(mv_kaskade.r_bekannt) THEN COALESCE(sum(mv_kaskade.verdunstung_kg), 0::numeric)
                    ELSE NULL::numeric
                END AS verdunstung_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.f_bekannt) THEN COALESCE(sum(mv_kaskade.schimmel_kg), 0::numeric)
                    ELSE NULL::numeric
                END AS schimmel_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) THEN COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS kanal_ausgelagert_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_fax_bekannt) THEN COALESCE(sum(mv_kaskade.fax_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS fax_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_fax_bekannt) THEN COALESCE(sum(mv_kaskade.fax_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS fax_erwartet_kg,
            COALESCE(sum(mv_kaskade.m2) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) + COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric) AS im_haus_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) THEN COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS kanal_im_haus_kg,
            bool_and(mv_kaskade.r_bekannt AND mv_kaskade.f_bekannt AND mv_kaskade.a_fax_bekannt AND mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) AS verlust_bekannt,
            bool_and(mv_kaskade.r_bekannt) AS verdunstung_bekannt,
            bool_and(mv_kaskade.f_bekannt) AS schimmel_bekannt,
            bool_and(mv_kaskade.a_fax_bekannt) AS fax_bekannt,
            bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) AS kanal_bekannt,
            sum(mv_kaskade.m1 * mv_kaskade.f) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m1) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS faul_anteil_lager,
            max(mv_kaskade.f_quelle) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS faul_quelle,
            count(*) > 0 AS gerechnet,
            count(*) FILTER (WHERE mv_kaskade.portion = 'lager'::text) > 0 AS hat_lager
           FROM mv_kaskade
          GROUP BY mv_kaskade.charge_nr
        )
 SELECT b.charge_nr,
    b.schlag,
    b.sorte,
    b.eingang_kg,
    b.n_paletten,
    b.eingangsdatum_mittel,
    zahl(COALESCE(k.ausgelagert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgelagert_kg,
    zahl(k.alter_ausgelagert, 1, '100000'::numeric)::numeric(8,1) AS alter_ausgelagert,
    zahl(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.lager_kg, 0::numeric)
        END, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(COALESCE(k.alter_lager, (b.stichtag - b.eingangsdatum_mittel)::numeric), 1, '100000'::numeric)::numeric(8,1) AS alter_lager,
    zahl((heute() - x.rest_datum)::double precision, 1, '100000'::numeric)::numeric(8,1) AS alter_lager_heute,
    b.weg2_anteil,
    b.stichtag,
    b.n_paletten_mit_netto,
    zahl(COALESCE(k.ueberzaehlung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ueberzaehlung_kg,
    b.sortiert_kg,
    b.gewaschen_kg,
    b.wartet_kg,
    b.anteil_gewaschen,
    b.alter_band,
    b.am_band_kg,
    x.rest_datum AS eingangsdatum_rest,
    COALESCE(k.n_lieferung_kohorten, 0) > 0 AS rest_alter_aus_zaehlung,
    b.eingang_von,
    b.eingang_bis,
    b.n_eingangstage,
    COALESCE(k.rest_von, b.eingang_von) AS rest_von,
    COALESCE(k.rest_bis, b.eingang_bis) AS rest_bis,
    round(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.lager_kg, 0::numeric)
        END / NULLIF(b.eingang_kg / NULLIF(b.n_paletten, 0)::numeric, 0::numeric))::integer AS n_rest_paletten,
    COALESCE(k.n_rest_kohorten, b.n_eingangstage) AS n_rest_kohorten,
    heute() - COALESCE(k.rest_bis, b.eingang_bis) AS alter_lager_von,
    heute() - COALESCE(k.rest_von, b.eingang_von) AS alter_lager_bis,
    zahl(COALESCE(k.geliefert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS geliefert_kg,
    zahl(k.verkaufsfaehig_lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_lager_kg,
    COALESCE(n.n_lieferungen, 0) AS n_lieferungen,
    zahl(k.verdunstung_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_heute_kg,
    zahl(k.schimmel_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_heute_kg,
    zahl(k.fax_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_heute_kg,
    zahl(k.verdunstung_heute_kg + k.schimmel_heute_kg + k.fax_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_heute_kg,
    zahl(k.kanal_ausgelagert_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(k.fax_erwartet_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_erwartet_kg,
    zahl(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.im_haus_heute_kg, 0::numeric)
        END, 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_heute_kg,
    zahl(k.kanal_im_haus_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_im_haus_kg,
    COALESCE(k.verlust_bekannt, false) AS verlust_bekannt,
    COALESCE(k.verdunstung_bekannt, false) AS verdunstung_bekannt,
    COALESCE(k.schimmel_bekannt, false) AS schimmel_bekannt,
    COALESCE(k.fax_bekannt, false) AS fax_bekannt,
    COALESCE(k.kanal_bekannt, false) AS kanal_bekannt,
    zahl(k.faul_anteil_lager, 4, 1::numeric)::numeric(6,4) AS faul_anteil,
    k.faul_quelle,
    heute() AS heute
   FROM v_kaskade_basis b
     LEFT JOIN je_charge k ON k.charge_nr = b.charge_nr
     LEFT JOIN ( SELECT v_lieferung_charge.charge_nr,
            count(DISTINCT v_lieferung_charge.id)::integer AS n_lieferungen
           FROM v_lieferung_charge
          WHERE (v_lieferung_charge.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])) AND v_lieferung_charge.id > 0
          GROUP BY v_lieferung_charge.charge_nr) n ON n.charge_nr = b.charge_nr
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN k.rest_tage_seit_epoche IS NOT NULL THEN '2000-01-01'::date + round(k.rest_tage_seit_epoche)::integer
                    ELSE b.eingangsdatum_mittel
                END AS rest_datum) x
  WHERE b.eingang_kg IS NOT NULL;

create view v_kaskade with (security_invoker = true) as
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    m0,
    m1,
    m2,
    r,
    f,
    f_unten,
    f_oben,
    f_se,
    f_ws,
    f_s,
    g_w,
    p_hand,
    p_wasch,
    f_quelle,
    f_geliehen,
    b_ws,
    b_s,
    b_w,
    zuwachs_bekannt,
    a_klein_n,
    a_gross_n,
    a_fax,
    d_m1_r,
    r_n,
    r_basis,
    klein_n,
    klein_basis,
    gross_n,
    gross_basis,
    f_n,
    fax_n,
    fax_basis,
    r_bekannt,
    f_bekannt,
    a_klein_bekannt,
    a_gross_bekannt,
    a_fax_bekannt,
    verdunstung_kg,
    schimmel_kg,
    klein_kg,
    nebenkanal_kg,
    fax_kg,
    verkaufsfaehig_kg,
    kohorte,
    geliefert_kg,
    ueberzaehlung_kg,
    n_lieferungen,
    verkaufsfaehig_anteil
   FROM mv_kaskade;

create view v_prognose with (security_invoker = true) as
 WITH tag AS MATERIALIZED (
         SELECT heute() AS heute,
            stichtag() AS stichtag
        ), ende AS (
         SELECT GREATEST(LEAST(t.stichtag - t.heute, 400), 28) AS tage
           FROM tag t
        ), horizonte AS (
         SELECT g.h
           FROM ende e,
            LATERAL generate_series(0, e.tage, 7) g(h)
        UNION
         SELECT 7
        UNION
         SELECT 14
        UNION
         SELECT 28
        UNION
         SELECT ende.tage
           FROM ende
        ), grenzen AS (
         SELECT mv_koeff_rand.sorte,
            mv_koeff_rand.r_unten,
            mv_koeff_rand.r_oben,
            mv_koeff_rand.klein_unten,
            mv_koeff_rand.klein_oben,
            mv_koeff_rand.gross_unten,
            mv_koeff_rand.gross_oben,
            mv_koeff_rand.fax_unten,
            mv_koeff_rand.fax_oben
           FROM mv_koeff_rand
        ), lager AS MATERIALIZED (
         SELECT k.charge_nr,
            k.sorte,
            k.schlag,
            k.kohorte,
            k.alter_tage,
            k.m0,
            k.r,
            k.f,
            k.f_unten,
            k.f_oben,
            k.f_ws,
            k.f_s,
            k.g_w,
            k.p_hand,
            k.p_wasch,
            k.b_ws,
            k.b_s,
            k.b_w,
            k.zuwachs_bekannt,
            k.a_klein_n,
            k.a_gross_n,
            k.a_fax,
            k.hagel,
            k.r_bekannt,
            k.f_bekannt,
            k.a_klein_bekannt,
            k.a_gross_bekannt,
            k.a_fax_bekannt,
            k.f_geliehen,
            COALESCE(g.r_unten, 0::numeric) AS r_unten,
            COALESCE(g.r_oben, 0::numeric) AS r_oben,
            COALESCE(g.klein_unten, 0::numeric) AS klein_unten,
            COALESCE(g.klein_oben, 0::numeric) AS klein_oben,
            COALESCE(g.gross_unten, 0::numeric) AS gross_unten,
            COALESCE(g.gross_oben, 0::numeric) AS gross_oben,
            COALESCE(g.fax_unten, 0::numeric) AS fax_unten,
            COALESCE(g.fax_oben, 0::numeric) AS fax_oben,
            power(1::numeric - k.r, k.alter_tage) AS wa,
            power(1::numeric - GREATEST(COALESCE(g.r_unten, 0::numeric), 0::numeric), k.alter_tage) AS wa_unten,
            power(1::numeric - GREATEST(COALESCE(g.r_oben, 0::numeric), 0::numeric), k.alter_tage) AS wa_oben
           FROM mv_kaskade k
             LEFT JOIN grenzen g ON g.sorte = k.sorte
          WHERE k.portion = 'lager'::text AND k.m0 > 0::numeric AND k.alter_tage >= 0::numeric
        ), faktor_h AS MATERIALIZED (
         SELECT c.charge_nr,
            h.h,
            power(1::numeric - c.r, h.h::numeric) AS wh,
            power(1::numeric - GREATEST(c.r_unten, 0::numeric), h.h::numeric) AS wh_unten,
            power(1::numeric - GREATEST(c.r_oben, 0::numeric), h.h::numeric) AS wh_oben
           FROM ( SELECT DISTINCT lager.charge_nr,
                    lager.r,
                    lager.r_unten,
                    lager.r_oben
                   FROM lager) c
             CROSS JOIN horizonte h
        ), je_portion AS (
         SELECT l.charge_nr,
            l.sorte,
            l.schlag,
            l.kohorte,
            l.alter_tage,
            l.m0,
            l.r,
            l.f,
            l.f_unten,
            l.f_oben,
            l.f_ws,
            l.f_s,
            l.g_w,
            l.p_hand,
            l.p_wasch,
            l.b_ws,
            l.b_s,
            l.b_w,
            l.zuwachs_bekannt,
            COALESCE(kh.klein, l.a_klein_n) AS a_klein_n,
            COALESCE(kh.gross, l.a_gross_n) AS a_gross_n,
            l.a_klein_n AS a_klein_0,
            l.a_gross_n AS a_gross_0,
            l.a_fax,
            l.r_bekannt,
            l.f_bekannt,
            l.a_klein_bekannt,
            l.a_gross_bekannt,
            l.a_fax_bekannt,
            l.f_geliehen,
            l.r_unten,
            l.r_oben,
            COALESCE(kh.klein, l.klein_unten) AS klein_unten,
            COALESCE(kh.klein, l.klein_oben) AS klein_oben,
            COALESCE(kh.gross, l.gross_unten) AS gross_unten,
            COALESCE(kh.gross, l.gross_oben) AS gross_oben,
            l.fax_unten,
            l.fax_oben,
            l.wa,
            l.wa_unten,
            l.wa_oben,
            h.h,
            (l.alter_tage + h.h::numeric)::integer AS t,
                CASE
                    WHEN l.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(l.p_hand, l.p_wasch, l.f_ws, l.f_s, l.g_w, l.b_ws, l.b_s, l.b_w, h.h::numeric), l.hagel), l.f)
                    ELSE l.f
                END AS f_h,
            w.wh,
            w.wh_unten,
            w.wh_oben,
            d.heute + h.h AS datum
           FROM lager l
             CROSS JOIN horizonte h
             CROSS JOIN tag d
             JOIN faktor_h w ON w.charge_nr = l.charge_nr AND w.h = h.h
             LEFT JOIN mv_kaliber_quelle kq ON kq.charge_nr = l.charge_nr
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - l.r, l.alter_tage + h.h::numeric)) kh ON true
        ), mit_band AS (
         SELECT p.charge_nr,
            p.sorte,
            p.schlag,
            p.kohorte,
            p.alter_tage,
            p.m0,
            p.r,
            p.f,
            p.f_unten,
            p.f_oben,
            p.f_ws,
            p.f_s,
            p.g_w,
            p.p_hand,
            p.p_wasch,
            p.b_ws,
            p.b_s,
            p.b_w,
            p.zuwachs_bekannt,
            p.a_klein_n,
            p.a_gross_n,
            p.a_klein_0,
            p.a_gross_0,
            p.a_fax,
            p.r_bekannt,
            p.f_bekannt,
            p.a_klein_bekannt,
            p.a_gross_bekannt,
            p.a_fax_bekannt,
            p.f_geliehen,
            p.r_unten,
            p.r_oben,
            p.klein_unten,
            p.klein_oben,
            p.gross_unten,
            p.gross_oben,
            p.fax_unten,
            p.fax_oben,
            p.wa,
            p.wa_unten,
            p.wa_oben,
            p.h,
            p.t,
            p.f_h,
            p.wh,
            p.wh_unten,
            p.wh_oben,
            p.datum,
            LEAST(GREATEST(p.f_unten + (p.f_h - p.f), 0::numeric), 1::numeric) AS f_unten_h,
            LEAST(GREATEST(p.f_oben + (p.f_h - p.f), 0::numeric), 1::numeric) AS f_oben_h
           FROM je_portion p
        ), stroeme AS (
         SELECT p.charge_nr,
            p.h,
            p.datum,
            p.t,
            p.m0,
            p.m0 - x.m1 AS verdunstet_kg,
            x.m1 * p.f_h AS faul_kg,
            y.m2 - z.rest AS kanal_kg,
            y.m2 * p.a_klein_n AS klein_kg,
            y.m2 * p.a_gross_n AS gross_kg,
            z.rest * p.a_fax AS fax_kg,
            z.rest * (1::numeric - p.a_fax) AS verkaufsfaehig_kg,
            y.m2 AS gute_ware_kg,
            p.m0 * p.wa_oben * p.wh_oben * (1::numeric - p.f_oben_h) * (1::numeric - LEAST(p.klein_oben / GREATEST(p.klein_oben + p.gross_oben, 1::numeric) + p.gross_oben / GREATEST(p.klein_oben + p.gross_oben, 1::numeric), 1::numeric)) * (1::numeric - p.fax_oben) AS vf_unten,
            p.m0 * p.wa_unten * p.wh_unten * (1::numeric - p.f_unten_h) * (1::numeric - LEAST(p.klein_unten / GREATEST(p.klein_unten + p.gross_unten, 1::numeric) + p.gross_unten / GREATEST(p.klein_unten + p.gross_unten, 1::numeric), 1::numeric)) * (1::numeric - p.fax_unten) AS vf_oben,
            (1::numeric - p.f) * (b0.basis - b.basis * p.wh) AS verlust_wasser,
            b.basis * p.wh * GREATEST(p.f_h - p.f, 0::numeric) AS verlust_faeulnis,
            p.m0 * p.t::numeric AS m0_mal_t,
            p.r_bekannt,
            p.f_bekannt,
            p.a_klein_bekannt,
            p.a_gross_bekannt,
            p.a_fax_bekannt,
            p.f_geliehen,
            p.zuwachs_bekannt
           FROM mit_band p
             CROSS JOIN LATERAL ( SELECT p.m0 * p.wa * p.wh AS m1) x
             CROSS JOIN LATERAL ( SELECT x.m1 * (1::numeric - p.f_h) AS m2) y
             CROSS JOIN LATERAL ( SELECT y.m2 * (1::numeric - p.a_klein_n - p.a_gross_n) AS rest) z
             CROSS JOIN LATERAL ( SELECT p.m0 * (1::numeric - p.a_klein_n - p.a_gross_n) * (1::numeric - p.a_fax) * p.wa AS basis) b

             CROSS JOIN LATERAL ( SELECT p.m0 * (1::numeric - p.a_klein_0 - p.a_gross_0) * (1::numeric - p.a_fax) * p.wa AS basis) b0
        ), gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text AS text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text AS text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text AS text,
            v_kaskade_basis.charge_nr::text AS charge_nr,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        ), je_charge AS MATERIALIZED (
         SELECT s_1.charge_nr,
            s_1.h,
            max(s_1.datum) AS datum,
            count(*)::integer AS n_kohorten,
            sum(s_1.m0) AS lager_kg,
            sum(s_1.verdunstet_kg) AS verdunstet_kg,
            sum(s_1.faul_kg) AS faul_kg,
            sum(s_1.kanal_kg) AS kanal_kg,
            sum(s_1.klein_kg) AS klein_kg,
            sum(s_1.gross_kg) AS gross_kg,
            sum(s_1.fax_kg) AS fax_kg,
            sum(s_1.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(s_1.gute_ware_kg) AS gute_ware_kg,
            sum(s_1.vf_unten) AS vf_unten_kg,
            sum(s_1.vf_oben) AS vf_oben_kg,
            sum(s_1.verlust_wasser) AS verlust_wasser_kg,
            sum(s_1.verlust_faeulnis) AS verlust_faeulnis_kg,
            sum(s_1.m0_mal_t) AS m0_mal_t,
            bool_and(s_1.r_bekannt) AS r_bekannt,
            bool_and(s_1.f_bekannt) AS f_bekannt,
            bool_and(s_1.a_klein_bekannt AND s_1.a_gross_bekannt) AS kanal_bekannt,
            bool_and(s_1.a_fax_bekannt) AS fax_bekannt,
            bool_or(s_1.f_geliehen) AS f_geliehen,
            bool_and(s_1.zuwachs_bekannt) AS zuwachs_bekannt,
            min(s_1.t) AS alter_von,
            max(s_1.t) AS alter_bis
           FROM stroeme s_1
          GROUP BY s_1.charge_nr, s_1.h
        ), summe AS MATERIALIZED (
         SELECT g.gruppe,
            g.schluessel,
            j.h,
            max(j.datum) AS datum,
            count(*)::integer AS n_chargen,
            sum(j.n_kohorten)::integer AS n_kohorten,
            sum(j.lager_kg) AS lager_kg,
            sum(j.verdunstet_kg) AS verdunstet_kg,
            sum(j.faul_kg) AS faul_kg,
            sum(j.kanal_kg) AS kanal_kg,
            sum(j.klein_kg) AS klein_kg,
            sum(j.gross_kg) AS gross_kg,
            sum(j.fax_kg) AS fax_kg,
            sum(j.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(j.gute_ware_kg) AS gute_ware_kg,
            sum(j.vf_unten_kg) AS vf_unten_kg,
            sum(j.vf_oben_kg) AS vf_oben_kg,
            sum(j.verlust_wasser_kg) AS verlust_wasser_kg,
            sum(j.verlust_faeulnis_kg) AS verlust_faeulnis_kg,
            bool_and(j.r_bekannt) AS r_bekannt,
            bool_and(j.f_bekannt) AS f_bekannt,
            bool_and(j.kanal_bekannt) AS kanal_bekannt,
            bool_and(j.fax_bekannt) AS fax_bekannt,
            bool_or(j.f_geliehen) AS f_geliehen,
            bool_and(j.zuwachs_bekannt) AS zuwachs_bekannt,
            sum(j.m0_mal_t) / NULLIF(sum(j.lager_kg), 0::numeric) AS alter_tage,
            min(j.alter_von) AS alter_von,
            max(j.alter_bis) AS alter_bis
           FROM je_charge j
             JOIN gruppen g ON g.charge_nr = j.charge_nr
          GROUP BY g.gruppe, g.schluessel, j.h
        ), rate AS (
         SELECT s0.gruppe,
            s0.schluessel,
            (s1.verlust_wasser_kg + s1.verlust_faeulnis_kg) / s1.h::numeric AS vf_je_tag_kg,
            s1.verlust_wasser_kg / s1.h::numeric AS verdunstet_je_tag_kg,
                CASE
                    WHEN s1.zuwachs_bekannt THEN s1.verlust_faeulnis_kg / s1.h::numeric
                    ELSE NULL::numeric
                END AS faul_je_tag_kg
           FROM summe s0
             JOIN LATERAL ( SELECT x.gruppe,
                    x.schluessel,
                    x.h,
                    x.datum,
                    x.n_chargen,
                    x.n_kohorten,
                    x.lager_kg,
                    x.verdunstet_kg,
                    x.faul_kg,
                    x.kanal_kg,
                    x.fax_kg,
                    x.verkaufsfaehig_kg,
                    x.gute_ware_kg,
                    x.vf_unten_kg,
                    x.vf_oben_kg,
                    x.verlust_wasser_kg,
                    x.verlust_faeulnis_kg,
                    x.r_bekannt,
                    x.f_bekannt,
                    x.kanal_bekannt,
                    x.fax_bekannt,
                    x.f_geliehen,
                    x.zuwachs_bekannt,
                    x.alter_tage,
                    x.alter_von,
                    x.alter_bis
                   FROM summe x
                  WHERE x.gruppe = s0.gruppe AND x.schluessel = s0.schluessel AND x.h > 0
                  ORDER BY x.h
                 LIMIT 1) s1 ON true
          WHERE s0.h = 0
        )
 SELECT s.gruppe,
    s.schluessel,
    s.h,
    s.datum,
    s.n_chargen,
    s.n_kohorten,
    zahl(s.lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(s.verdunstet_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstet_kg,
    zahl(s.faul_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS faul_kg,
    zahl(s.kanal_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_kg,
    zahl(s.fax_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kg,
    zahl(s.verkaufsfaehig_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(s.gute_ware_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS gute_ware_kg,
    zahl(s.verlust_wasser_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_wasser_kg,
    zahl(s.verlust_faeulnis_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_faeulnis_kg,
    zahl(s.verlust_wasser_kg + s.verlust_faeulnis_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_verkaufsfaehig_kg,
        CASE
            WHEN v.vollstaendig AND s.lager_kg > 0::numeric THEN zahl(s.verkaufsfaehig_kg / s.lager_kg, 4, 1::numeric)
            ELSE NULL::numeric
        END::numeric(6,4) AS verkaufsfaehig_anteil,
        CASE
            WHEN v.vollstaendig THEN zahl(s.vf_unten_kg, 2, '1000000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(14,2) AS verkaufsfaehig_unten_kg,
        CASE
            WHEN v.vollstaendig THEN zahl(s.vf_oben_kg, 2, '1000000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(14,2) AS verkaufsfaehig_oben_kg,
    zahl(r.vf_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS verkaufsfaehig_je_tag_kg,
    zahl(r.verdunstet_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS verdunstet_je_tag_kg,
    zahl(r.faul_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS faul_je_tag_kg,
    s.r_bekannt,
    s.f_bekannt,
    s.kanal_bekannt,
    s.fax_bekannt,
    v.vollstaendig,
    s.f_geliehen,
    s.zuwachs_bekannt,
    round(s.alter_tage)::integer AS alter_tage,
    s.alter_von,
    s.alter_bis,
    zahl(s.klein_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS klein_kg,
    zahl(s.gross_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS gross_kg
   FROM summe s
     CROSS JOIN LATERAL ( SELECT s.r_bekannt AND s.f_bekannt AND s.kanal_bekannt AND s.fax_bekannt AS vollstaendig) v
     LEFT JOIN rate r ON r.gruppe = s.gruppe AND r.schluessel = s.schluessel;

create materialized view erg_charge as
 SELECT charge_nr,
    schlag,
    sorte,
    eingang_kg,
    n_paletten,
    eingangsdatum_mittel,
    ausgelagert_kg,
    alter_ausgelagert,
    lager_kg,
    alter_lager,
    alter_lager_heute,
    weg2_anteil,
    stichtag,
    n_paletten_mit_netto,
    ueberzaehlung_kg,
    sortiert_kg,
    gewaschen_kg,
    wartet_kg,
    anteil_gewaschen,
    alter_band,
    am_band_kg,
    eingangsdatum_rest,
    rest_alter_aus_zaehlung,
    eingang_von,
    eingang_bis,
    n_eingangstage,
    rest_von,
    rest_bis,
    n_rest_paletten,
    n_rest_kohorten,
    alter_lager_von,
    alter_lager_bis,
    geliefert_kg,
    verkaufsfaehig_lager_kg,
    n_lieferungen,
    verdunstung_heute_kg,
    schimmel_heute_kg,
    fax_heute_kg,
    verlust_heute_kg,
    kanal_ausgelagert_kg,
    fax_erwartet_kg,
    im_haus_heute_kg,
    kanal_im_haus_kg,
    verlust_bekannt,
    verdunstung_bekannt,
    schimmel_bekannt,
    fax_bekannt,
    kanal_bekannt,
    faul_anteil,
    faul_quelle,
    heute
   FROM v_hochrechnung_basis
with no data;

create materialized view erg_prognose as
 SELECT gruppe,
    schluessel,
    h,
    datum,
    n_chargen,
    n_kohorten,
    lager_kg,
    verdunstet_kg,
    faul_kg,
    kanal_kg,
    fax_kg,
    verkaufsfaehig_kg,
    gute_ware_kg,
    verlust_wasser_kg,
    verlust_faeulnis_kg,
    verlust_verkaufsfaehig_kg,
    verkaufsfaehig_anteil,
    verkaufsfaehig_unten_kg,
    verkaufsfaehig_oben_kg,
    verkaufsfaehig_je_tag_kg,
    verdunstet_je_tag_kg,
    faul_je_tag_kg,
    r_bekannt,
    f_bekannt,
    kanal_bekannt,
    fax_bekannt,
    vollstaendig,
    f_geliehen,
    zuwachs_bekannt,
    alter_tage,
    alter_von,
    alter_bis,
    klein_kg,
    gross_kg
   FROM v_prognose
with no data;

create or replace function kaliber_glocke(p_h integer)
returns table (
  gruppe text, schluessel text, sorte text, h integer, datum date,
  stufe_g integer, n_kuerbis integer, masse_kg numeric(14,2), anteil numeric(6,4),
  basis text, n_chargen integer
)
language sql stable security definer set search_path = public as $$
with stufen as (
  select w.basis, w.schluessel, w.sorte,
         (floor(w.g / 50) * 50)::int as stufe_g,
         sum(w.anzahl * w.g) as masse_g,
         sum(w.anzahl)::int  as n_kuerbis
    from kuerbis_stichtag(p_h) w
   group by w.basis, w.schluessel, w.sorte, (floor(w.g / 50) * 50)::int
), anteile as (
  select s.*, s.masse_g / nullif(sum(s.masse_g) over (partition by s.basis, s.schluessel), 0) as anteil
    from stufen s
), je_charge as (
  select p.schluessel::int as charge_nr, c.sorte, p.h, p.datum,
         q.basis, q.schluessel as key, a.stufe_g, a.n_kuerbis,
         p.verkaufsfaehig_kg * a.anteil as masse_kg
    from erg_prognose p
    join charge c on c.nr = p.schluessel::int
    join lager_schluessel() q on q.charge_nr = c.nr
    join anteile a on a.basis = q.basis and a.schluessel = q.schluessel
   where p.gruppe = 'charge' and p.h = p_h and q.basis <> 'keine'
), schluessel_je_sorte as (
  select distinct sorte, basis, key from je_charge
), stueck_je_sorte as (
  -- Je Sorte die gewogenen Stück: jeder Schlüssel einmal, nicht je Charge.
  select k.sorte, a.stufe_g, sum(a.n_kuerbis)::int as n_kuerbis
    from schluessel_je_sorte k
    join anteile a on a.basis = k.basis and a.schluessel = k.key
   group by k.sorte, a.stufe_g
), zeilen as (
  select 'charge'::text as gruppe, charge_nr::text as schluessel, sorte, h, datum,
         stufe_g, n_kuerbis, masse_kg,
         masse_kg / nullif(sum(masse_kg) over (partition by charge_nr), 0) as anteil,
         basis, 1 as n_chargen
    from je_charge
  union all
  select 'sorte', j.sorte, j.sorte, max(j.h), max(j.datum),
         j.stufe_g, max(s.n_kuerbis), sum(j.masse_kg),
         sum(j.masse_kg) / nullif(sum(sum(j.masse_kg)) over (partition by j.sorte), 0),
         case when count(distinct j.basis) = 1 then min(j.basis) else 'gemischt' end,
         count(distinct j.charge_nr)::int
    from je_charge j
    left join stueck_je_sorte s on s.sorte = j.sorte and s.stufe_g = j.stufe_g
   group by j.sorte, j.stufe_g
)
select gruppe, schluessel, sorte, h, datum, stufe_g,
       n_kuerbis,
       zahl(masse_kg, 2, 1e12)::numeric(14,2) as masse_kg,
       zahl(anteil, 4, 1)::numeric(6,4)       as anteil,
       basis, n_chargen
  from zeilen
$$;
drop function if exists lager_kaliber(integer);
create function lager_kaliber(p_h integer)
returns table(gruppe text, schluessel text, sorte text, h integer, datum date, kaliber_idx integer,
              band_von integer, band_bis integer, kg numeric, anteil numeric, basis text, n_kuerbis integer,
              verkaufsfaehig_kg numeric, lager_kg numeric, n_chargen integer,
              klasse text, klein_kg numeric, gross_kg numeric, geschrumpft_kg numeric)
language sql stable security definer set search_path = public as $$
with fassung as (
  -- Die Bänder je Sorte: die jüngste gültige Fassung.
  select distinct on (s.sorte) s.sorte, s.kaliber_baender
    from sortierschema s
   where s.art = 'kaliber' and s.gilt_ab <= heute()
   order by s.sorte, s.gilt_ab desc, s.id desc
), band as (
  select f.sorte, (x.ordinality - 1)::int as kaliber_idx,
         (x.b ->> 0)::int as band_von, (x.b ->> 1)::int as band_bis,
         x.ordinality = jsonb_array_length(f.kaliber_baender) as letztes
    from fassung f
   cross join lateral jsonb_array_elements(f.kaliber_baender) with ordinality as x(b, ordinality)
), schwellen as (
  -- Je Sorte die Bandgrenzen als sortierte Schwellen: von_0, von_1, …, bis_n.
  select b.sorte,
         array_agg(b.band_von::numeric order by b.kaliber_idx)
           || (select max(x.band_bis)::numeric from band x where x.sorte = b.sorte and x.letztes) as grenzen,
         count(*)::int as n_baender
    from band b
   group by b.sorte
), verteilung_roh as (
  -- Massenanteile je Band. Bucket 0 = unter dem kleinsten Band
  -- (kaliber_idx −1); Bucket n+1 (genau auf der Obergrenze) gehört zum
  -- obersten Band — Klasse „kaliber" heisst, die Maschine hat ihn im Band
  -- gesehen, und schrumpfende Ware wächst nicht darüber hinaus.
  select w.basis, w.schluessel, w.sorte,
         case when sw.grenzen is null then null
              else least(width_bucket(w.g::numeric, sw.grenzen), sw.n_baender) - 1 end as kaliber_idx,
         sum(w.anzahl * w.g)  as masse_g,
         sum(w.anzahl)        as n_kuerbis
    from kuerbis_stichtag(p_h) w
    left join schwellen sw on sw.sorte = w.sorte
   group by w.basis, w.schluessel, w.sorte,
            case when sw.grenzen is null then null
                 else least(width_bucket(w.g::numeric, sw.grenzen), sw.n_baender) - 1 end
), verteilung_band as (
  -- Unter dem kleinsten Band (Bucket −1) zählt im kleinsten Band (0); der
  -- Anteil darunter bleibt als Auskunft stehen.
  select v.basis, v.schluessel, v.sorte,
         case when v.kaliber_idx is null then null else greatest(v.kaliber_idx, 0) end as kaliber_idx,
         sum(v.masse_g)                                             as masse_g,
         coalesce(sum(v.masse_g) filter (where v.kaliber_idx = -1), 0) as masse_darunter_g,
         sum(v.n_kuerbis)                                           as n_kuerbis
    from verteilung_roh v
   group by v.basis, v.schluessel, v.sorte,
            case when v.kaliber_idx is null then null else greatest(v.kaliber_idx, 0) end
), verteilung as (
  select v.basis, v.schluessel, v.sorte, v.kaliber_idx, b.band_von, b.band_bis,
         v.masse_g / nullif(sum(v.masse_g) over w, 0)          as anteil,
         sum(v.masse_darunter_g) over w / nullif(sum(v.masse_g) over w, 0) as anteil_darunter,
         sum(v.n_kuerbis) over w                               as n_kuerbis
    from verteilung_band v
    left join band b on b.sorte = v.sorte and b.kaliber_idx = v.kaliber_idx
  window w as (partition by v.basis, v.schluessel)
), prognose as (
  select p.schluessel::int as charge_nr, c.sorte, c.schlag, p.h, p.datum, q.basis, q.schluessel as q_schluessel,
         p.verkaufsfaehig_kg, p.lager_kg,
         case when p.kanal_bekannt then p.klein_kg end as klein_kg,
         case when p.kanal_bekannt then p.gross_kg end as gross_kg
    from erg_prognose p
    join charge c on c.nr = p.schluessel::int
    join lager_schluessel() q on q.charge_nr = c.nr
   where p.gruppe = 'charge' and p.h = p_h
), je_band as (
  select p.charge_nr, p.sorte, p.h, p.datum, p.basis,
         v.kaliber_idx, v.band_von, v.band_bis,
         case when p.basis = 'keine' then null else v.anteil end              as anteil,
         case when p.basis = 'keine' then p.verkaufsfaehig_kg
              else p.verkaufsfaehig_kg * v.anteil end                         as kg,
         v.n_kuerbis, v.anteil_darunter
    from prognose p
    left join verteilung v on v.basis = p.basis and v.schluessel = p.q_schluessel
), je_charge as (
  -- Je Charge, was unter das kleinste Band geschrumpft ist — ein Teil des
  -- kleinsten Bandes, zur Auskunft (ohne CSV: unbekannt).
  select p.*,
         case when p.basis = 'keine' then null
              else p.verkaufsfaehig_kg * coalesce((select max(b.anteil_darunter) from je_band b
                                                    where b.charge_nr = p.charge_nr), 0) end as geschrumpft_kg,
         (select max(b.n_kuerbis) from je_band b where b.charge_nr = p.charge_nr) as n_kuerbis
    from prognose p
), zeilen_charge as (
  -- Die Bänder: das Verkaufsfähige …
  select b.charge_nr, b.sorte, b.h, b.datum, 'kaliber'::text as klasse,
         case when b.basis = 'keine' then null else b.kaliber_idx end as kaliber_idx,
         b.band_von, b.band_bis, b.kg, b.anteil, b.basis
    from je_band b
  union all
  -- … Unterkaliber: zu klein …
  select c.charge_nr, c.sorte, c.h, c.datum, 'unter', -1, null, null,
         c.klein_kg, null, c.basis
    from je_charge c
  union all
  -- … Überkaliber: zu gross.
  select c.charge_nr, c.sorte, c.h, c.datum, 'ueber', -2, null, null,
         c.gross_kg, null, c.basis
    from je_charge c
), zeilen as (
  select 'charge'::text as gruppe, z.charge_nr::text as schluessel, z.sorte, z.h, z.datum,
         z.kaliber_idx, z.band_von, z.band_bis, z.kg, z.anteil, z.basis, c.n_kuerbis,
         c.verkaufsfaehig_kg,
         c.lager_kg, 1 as n_chargen, z.klasse, c.klein_kg, c.gross_kg, c.geschrumpft_kg
    from zeilen_charge z
    join je_charge c on c.charge_nr = z.charge_nr
  union all
  select 'sorte', s.sorte, s.sorte, s.h, s.datum,
         s.kaliber_idx, s.band_von, s.band_bis, s.kg, s.anteil, s.basis, s.n_kuerbis,
         s.verkaufsfaehig_kg, s.lager_kg, s.n_chargen, s.klasse, s.klein_kg, s.gross_kg, s.geschrumpft_kg
    from (
      select z.sorte, z.h, max(z.datum) as datum, z.kaliber_idx, z.band_von, z.band_bis, z.klasse,
             sum(z.kg) as kg,
             null::numeric as anteil,
             case when count(distinct z.basis) = 1 then min(z.basis) else 'gemischt' end as basis,
             (select max(c2.n_kuerbis) from je_charge c2 where c2.sorte = z.sorte) as n_kuerbis,
             (select sum(c2.verkaufsfaehig_kg) from je_charge c2 where c2.sorte = z.sorte) as verkaufsfaehig_kg,
             (select sum(c2.lager_kg) from je_charge c2 where c2.sorte = z.sorte) as lager_kg,
             (select count(*) from je_charge c2 where c2.sorte = z.sorte)::int as n_chargen,
             (select sum(c2.klein_kg) from je_charge c2 where c2.sorte = z.sorte) as klein_kg,
             (select sum(c2.gross_kg) from je_charge c2 where c2.sorte = z.sorte) as gross_kg,
             (select sum(c2.geschrumpft_kg) from je_charge c2 where c2.sorte = z.sorte) as geschrumpft_kg
        from zeilen_charge z
       group by z.sorte, z.h, z.kaliber_idx, z.band_von, z.band_bis, z.klasse
    ) s
)
select gruppe, schluessel, sorte, h, datum,
       kaliber_idx, band_von, band_bis,
       zahl(kg, 2, 1e12)::numeric(14,2)                     as kg,
       -- anteil: Anteil des Bandes am Verkaufsfähigen (die Bänder zusammen 1).
       -- zu klein/zu gross haben keinen — sie sind nicht verkaufsfähig.
       zahl(case when basis = 'keine' or klasse <> 'kaliber' then null
                 else kg / nullif(verkaufsfaehig_kg, 0) end, 4, 1)::numeric(6,4) as anteil,
       basis,
       n_kuerbis::int                                       as n_kuerbis,
       zahl(verkaufsfaehig_kg, 2, 1e12)::numeric(14,2)      as verkaufsfaehig_kg,
       zahl(lager_kg, 2, 1e12)::numeric(14,2)               as lager_kg,
       n_chargen::int                                       as n_chargen,
       klasse,
       zahl(klein_kg, 2, 1e12)::numeric(14,2)               as klein_kg,
       zahl(gross_kg, 2, 1e12)::numeric(14,2)               as gross_kg,
       zahl(geschrumpft_kg, 2, 1e12)::numeric(14,2)         as geschrumpft_kg
  from zeilen
$$;

create view v_lager_kaliber with (security_invoker = true) as
select * from lager_kaliber(0);

create or replace function artikel_lager_teile(p_h integer)
returns table (charge_nr int, sorte text, artikelgruppe text, label text, groesse text,
               kg numeric, g_mittel numeric, h int, datum date)
language sql stable security definer set search_path = public as $$
with prognose as (
  select p.schluessel::int as charge_nr, c.sorte, p.h, p.datum, p.verkaufsfaehig_kg,
         q.basis, q.schluessel as q_schluessel
    from erg_prognose p
    join charge c on c.nr = p.schluessel::int
    left join lager_schluessel() q on q.charge_nr = c.nr
   where p.gruppe = 'charge' and p.h = p_h and p.verkaufsfaehig_kg > 0
), zuordnung as (
  select p.*, g.artikelgruppe, l.label
    from prognose p
    left join v_sorte_artikelgruppe g on g.sorte = p.sorte
    left join v_charge_label l on l.charge_nr = p.charge_nr
), verteilung as (
  select w.basis, w.schluessel, w.sorte, w.anzahl, w.g::numeric as g
    from kuerbis_stichtag(p_h) w
   where exists (select 1 from zuordnung z where z.basis = w.basis and z.q_schluessel = w.schluessel)
), mit_klasse as (
  select v.basis, v.schluessel,
         coalesce(k.groesse, case when ak.n = 0 then 'lose'
                                  when v.g < ak.min_von then 'darunter'
                                  when v.g >= ak.max_bis then 'darueber'
                                  else 'dazwischen' end) as groesse,
         v.anzahl, v.g
    from verteilung v
    left join v_sorte_artikelgruppe sg on sg.sorte = v.sorte
    left join lateral (select count(*) as n, min(a.von_g) as min_von, max(a.bis_g) as max_bis
                         from artikel_kaliber a where a.gruppe = sg.artikelgruppe) ak on true
    left join artikel_kaliber k on k.gruppe = sg.artikelgruppe and v.g >= k.von_g and v.g < k.bis_g
), anteile as (
  select m.basis, m.schluessel, m.groesse,
         sum(m.anzahl * m.g) / nullif(sum(sum(m.anzahl * m.g)) over (partition by m.basis, m.schluessel), 0) as anteil,
         sum(m.anzahl * m.g) / nullif(sum(m.anzahl), 0) as g_mittel
    from mit_klasse m
   group by m.basis, m.schluessel, m.groesse
)
select z.charge_nr, z.sorte, z.artikelgruppe, z.label,
       coalesce(a.groesse, 'ohne Verteilung') as groesse,
       case when a.anteil is null then z.verkaufsfaehig_kg else z.verkaufsfaehig_kg * a.anteil end as kg,
       a.g_mittel, z.h, z.datum
  from zuordnung z
  left join anteile a on a.basis = z.basis and a.schluessel = z.q_schluessel
$$;

create or replace function artikel_lager_charge(p_h integer)
returns table (charge_nr int, sorte text, artikelgruppe text, label text, groesse text,
               von_g int, bis_g int, stueck_je_kiste int,
               kg numeric, stueck numeric, kisten numeric, g_mittel numeric, h int, datum date)
language sql stable security definer set search_path = public as $$
  select t.charge_nr, t.sorte, t.artikelgruppe, t.label, t.groesse, k.von_g, k.bis_g, k.stueck_je_kiste,
         zahl(t.kg, 2, 1e12)::numeric(14,2),
         zahl(t.kg * 1000 / nullif(t.g_mittel, 0), 0, 1e12)::numeric(14,0),
         zahl(t.kg * 1000 / nullif(t.g_mittel, 0) / nullif(k.stueck_je_kiste, 0), 0, 1e12)::numeric(14,0),
         zahl(t.g_mittel, 0, 1e6)::numeric(10,0),
         t.h, t.datum
    from artikel_lager_teile(p_h) t
    left join artikel_kaliber k on k.gruppe = t.artikelgruppe and k.groesse = t.groesse
$$;

create or replace function artikel_lager(p_h integer)
returns table (artikelgruppe text, label text, groesse text, von_g int, bis_g int, stueck_je_kiste int,
               kg numeric, stueck numeric, kisten numeric, g_mittel numeric,
               n_chargen int, chargen int[], h int, datum date)
language sql stable security definer set search_path = public as $$
select j.artikelgruppe, j.label, j.groesse, k.von_g, k.bis_g, k.stueck_je_kiste,
       zahl(sum(j.kg), 2, 1e12)::numeric(14,2),
       zahl(sum(j.kg * 1000 / nullif(j.g_mittel, 0)), 0, 1e12)::numeric(14,0),
       zahl(sum(j.kg * 1000 / nullif(j.g_mittel, 0)) / nullif(max(k.stueck_je_kiste), 0), 0, 1e12)::numeric(14,0),
       zahl(sum(j.kg) * 1000 / nullif(sum(j.kg * 1000 / nullif(j.g_mittel, 0)), 0), 0, 1e6)::numeric(10,0),
       count(distinct j.charge_nr)::int, array_agg(distinct j.charge_nr order by j.charge_nr),
       max(j.h)::int, max(j.datum)
  from artikel_lager_teile(p_h) j
  left join artikel_kaliber k on k.gruppe = j.artikelgruppe and k.groesse = j.groesse
 group by j.artikelgruppe, j.label, j.groesse, k.von_g, k.bis_g, k.stueck_je_kiste
$$;

create materialized view mv_hochrechnung as
 SELECT k.charge_nr,
    k.sorte,
    k.schlag,
    k.portion,
    k.alter_tage,
    k.eingang_kg,
    zahl(c.m0)::numeric(14,2) AS portion_kg,
    k.f_geliehen,
    k.f_n,
    k.f_se,
    s.strom,
    s.buch,
        CASE
            WHEN s.bekannt THEN zahl(s.kg)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
        CASE
            WHEN s.bekannt THEN zahl(s.koeffizient, 6, 100000::numeric)
            ELSE NULL::numeric
        END::numeric(12,6) AS koeffizient,
    s.koeff_n,
    s.koeff_basis,
    s.formel,
    s.d_r,
    s.d_f,
    s.d_a,
    s.koeff_art,
    s.bekannt AS koeff_bekannt,
    k.kohorte
   FROM v_kaskade k
     CROSS JOIN LATERAL ( SELECT GREATEST(k.m0, 0::numeric) AS m0,
            GREATEST(k.m1, 0::numeric) AS m1,
            GREATEST(k.m2, 0::numeric) AS m2,
            GREATEST(k.verkaufsfaehig_kg, 0::numeric) AS verkaufsfaehig_kg,
            LEAST(GREATEST(k.r, 0::numeric), 1::numeric) AS r,
            LEAST(GREATEST(k.f, 0::numeric), 1::numeric) AS f,
            LEAST(GREATEST(k.a_klein_n, 0::numeric), 1::numeric) AS a_klein_n,
            LEAST(GREATEST(k.a_gross_n, 0::numeric), 1::numeric) AS a_gross_n,
            LEAST(GREATEST(k.a_fax, 0::numeric), 1::numeric) AS a_fax) c
     CROSS JOIN LATERAL ( VALUES ('Verdunstung'::text,'verlust'::text,c.m0 - c.m1,c.m0,c.r,k.r_n,k.r_basis,'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'::text,- k.d_m1_r,0::numeric,0::numeric,NULL::text,k.r_bekannt), ('Schimmel/Fäulnis'::text,'verlust'::text,c.m1 * c.f,c.m1,c.f,k.f_n,k.f_quelle,'Masse nach Verdunstung × Palox-Anteil der Stationen auf dem Weg der Charge (0106)'::text,k.d_m1_r * c.f,c.m1,0::numeric,NULL::text,k.f_bekannt), ('Zu klein (Tierfutter)'::text,'marge'::text,c.m1 * (1::numeric - c.f) * c.a_klein_n,c.m2,c.a_klein_n,k.klein_n,k.klein_basis,'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust'::text,k.d_m1_r * (1::numeric - c.f) * c.a_klein_n,(- c.m1) * c.a_klein_n,c.m2,'ausschuss'::text,k.a_klein_bekannt), ('Nebenkanal zu gross'::text,'marge'::text,c.m1 * (1::numeric - c.f) * c.a_gross_n,c.m2,c.a_gross_n,k.gross_n,k.gross_basis,'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'::text,k.d_m1_r * (1::numeric - c.f) * c.a_gross_n,(- c.m1) * c.a_gross_n,c.m2,'nebenkanal'::text,k.a_gross_bekannt), ('Faul beim Abpacken (Fax)'::text,'verlust'::text,c.m1 * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),c.a_fax,k.fax_n,k.fax_basis,'Verkaufsfähige Masse × Anteil Faules, das beim Etikettieren aussortiert wird — vom Waschen und Stehen, nicht von der Lagerdauer'::text,k.d_m1_r * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,(- c.m1) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),'fax'::text,k.a_fax_bekannt), ('Verkaufsfähig'::text,'bilanz'::text,c.verkaufsfaehig_kg,c.m2,NULL::numeric,NULL::integer,NULL::text,'Rest der Kaskade'::text,0::numeric,0::numeric,0::numeric,NULL::text,true)) s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel, d_r, d_f, d_a, koeff_art, bekannt)
with no data;

create view v_plausibilitaet_0064_zusatz with (security_invoker = true) as
 SELECT 'Tara fehlt'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    min(p.eingangsdatum)::timestamp with time zone AS start_ts,
    format('%s von %s Paletten der Charge haben kein Nettogewicht (%s kg brutto): %s. %s'::text, count(*), r.n_paletten, round(sum(p.brutto_kg)),
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'die Gebindeart steht nicht auf der Palette'::text
            WHEN bool_or(g.art IS NULL) THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN bool_or(g.tara_kg_pro_kiste IS NULL) THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN bool_or(g.tara_kg_palette IS NULL) THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END,
        CASE
            WHEN r.n_paletten_mit_netto = 0 THEN 'Damit hat die Charge gar keinen Eingang — sie fehlt in der ganzen Bilanz.'::text
            ELSE format('Für sie rechnet der Eingang mit dem Mittel der übrigen: %s der %s kg '::text || 'Eingang sind hochgerechnet, nicht gewogen.'::text, round(r.eingang_netto_kg - r.eingang_netto_gemessen_kg), round(r.eingang_netto_kg))
        END) AS befund,
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'Gebindeart am Wareneingang nachtragen.'::text
            WHEN bool_or(g.art IS NULL) OR bool_or(g.tara_kg_pro_kiste IS NULL) OR bool_or(g.tara_kg_palette IS NULL) THEN 'Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. '::text || 'Die Zahlen rechnen sich danach von selbst neu.'::text
            ELSE 'Kistenzahl der Palette im Wareneingang nachtragen.'::text
        END AS rat
   FROM palette p
     LEFT JOIN gebinde g ON g.art = p.gebindeart
     JOIN charge c ON c.nr = p.charge_nr
     JOIN v_charge_rueckgrat r ON r.charge_nr = p.charge_nr
  WHERE (p.brutto_kg - p.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) IS NULL
  GROUP BY p.charge_nr, c.sorte, r.n_paletten, r.n_paletten_mit_netto, r.eingang_netto_kg, r.eingang_netto_gemessen_kg
UNION ALL
 SELECT 'Überzählung'::text AS art,
    NULL::bigint AS auftrag_id,
    h.charge_nr,
    h.sorte,
    h.eingangsdatum_mittel::timestamp with time zone AS start_ts,
    format('Die Lieferungen dieser Charge (%s kg) brauchen nach der gerechneten Ausbeute (%s %% verkaufsfähig) %s kg Eingang — erfasst sind %s kg, also %s kg zu wenig. Geliefert wurde nicht mehr als eingelagert; es wurde mehr geliefert, als die Rechnung aus diesem Eingang erwartet.'::text, round(h.geliefert_kg), round(100::numeric * h.geliefert_kg / NULLIF(h.eingang_kg + h.ueberzaehlung_kg, 0::numeric)), round(h.eingang_kg + h.ueberzaehlung_kg), round(h.eingang_kg), round(h.ueberzaehlung_kg)) AS befund,
    'Drei Möglichkeiten: Im Erntejournal fehlt eine Palette dieser Charge; ein Lieferschein ist auf die falsche Chargennummer gebucht; oder diese Charge hat weniger Verlust als das Modell annimmt — dann ist „Im Lager" für sie zu klein gerechnet. Die ersten zwei lassen sich nachtragen.'::text AS rat
   FROM v_hochrechnung_basis h
  WHERE h.ueberzaehlung_kg > 0::numeric
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — %s, nicht mit der Palette selbst.'::text, count(*), ap.brutto_zettel_kg, to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text),
        CASE
            WHEN bool_and(m.masse_quelle = 'gewogen'::text) THEN 'gerechnet wird mit der Wägung der Palette'::text
            WHEN bool_and(m.masse_quelle = 'zettel-kisten'::text) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            WHEN bool_and(m.masse_quelle = ANY (ARRAY['zettel-kisten'::text, 'zettel-kisten-charge'::text, 'gewogen'::text])) THEN 'gerechnet wird mit den gezählten Kisten und der Tara je Kiste der Charge (Zettel − Kisten × Tara je Kiste)'::text
            ELSE 'gerechnet wird mit der mittleren Tara ganzer Paletten der Charge — an der Zählung fehlt die Kistenzahl'::text
        END) AS befund,
    'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.id = ap.id
  WHERE ap.brutto_zettel_kg IS NOT NULL AND ap.eingangsdatum IS NOT NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg)) AND NOT (EXISTS ( SELECT 1
           FROM v_palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg AND p.eingangsdatum = ap.eingangsdatum AND p.netto_kg IS NOT NULL))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg, ap.eingangsdatum
UNION ALL
 SELECT 'Palette fraglich'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s: %s kg brutto in %s Kiste(n) %s, mit Palette gewogen — davon bleiben %s kg netto. Eine leere Palette wiegt allein %s kg.'::text,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'Zu klein'::text
            ELSE 'Zu gross'::text
        END, m.brutto_kg, m.kisten, m.gebindeart, m.kg, g.tara_kg_palette) AS befund,
    'Standen die Kisten direkt auf der Waage? Dann in der Korrektur „mit Palette" abwählen — das Netto rechnet sich von selbst neu.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.gemessen AND m.mit_palette AND m.brutto_kg IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND m.brutto_kg < (2::numeric * g.tara_kg_palette) AND a.abgebrochen_ts IS NULL
UNION ALL
 SELECT 'Verdunstung'::text AS art,
    m.auftrag_id,
    m.charge_nr,
    m.sorte,
    m.wiege_ts AS start_ts,
    format('%s %% je Tag: %s kg → %s kg in %s Tagen — so schnell verdunstet kein Kürbis (Grenze %s %% je Tag)'::text, round(m.rate_pro_tag * 100::numeric, 2), round(m.netto_damals_kg), round(m.netto_jetzt_kg), m.lagertage, round(verdunstung_rate_max() * 100::numeric, 2)) AS befund,
    'Zettelgewicht, Kisten und Gebinde dieser Wägung prüfen — oder es ist eine andere Palette. Bis zur Korrektur zählt sie nicht in die Rate.'::text AS rat
   FROM v_verdunstung_messung m
  WHERE m.grund ~~ 'zu schnell%'::text;

create view v_hochrechnung with (security_invoker = true) as
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    portion_kg,
    f_geliehen,
    f_n,
    f_se,
    strom,
    buch,
    kg,
    basis_kg,
    koeffizient,
    koeff_n,
    koeff_basis,
    formel,
    d_r,
    d_f,
    d_a,
    koeff_art,
    koeff_bekannt,
    kohorte
   FROM mv_hochrechnung;

create view v_kontrolle_vorschlag with (security_invoker = true) as
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lager_kg,
    b.alter_lager_von,
    b.alter_lager_bis,
    b.eingang_von,
    b.eingang_bis,
    COALESCE(k.n_kontrollen, 0) AS n_kontrollen,
    k.zuletzt,
    b.im_haus_heute_kg,
    heute() - COALESCE(k.zuletzt, b.eingang_von) AS tage_seit_wiegung,
    zahl(b.im_haus_heute_kg * GREATEST(heute() - COALESCE(k.zuletzt, b.eingang_von), 1)::numeric, 0, '10000000000000'::numeric)::numeric(14,0) AS informationswert
   FROM erg_charge b
     LEFT JOIN ( SELECT verdunstung_wiegung.charge_nr,
            count(*) FILTER (WHERE verdunstung_wiegung.auftrag_id IS NULL)::integer AS n_kontrollen,
            max(verdunstung_wiegung.wiege_ts)::date AS zuletzt
           FROM verdunstung_wiegung
          WHERE verdunstung_wiegung.gemessen
          GROUP BY verdunstung_wiegung.charge_nr) k ON k.charge_nr = b.charge_nr
  WHERE b.im_haus_heute_kg > 0::numeric
  ORDER BY (zahl(b.im_haus_heute_kg * GREATEST(heute() - COALESCE(k.zuletzt, b.eingang_von), 1)::numeric, 0, '10000000000000'::numeric)::numeric(14,0)) DESC NULLS LAST, b.im_haus_heute_kg DESC
 LIMIT 3;

create view v_massenbilanz with (security_invoker = true) as
 WITH csv_anteil AS MATERIALIZED (
         SELECT am.charge_nr,
            COALESCE(sum(am.eingang_netto_kg) FILTER (WHERE (EXISTS ( SELECT 1
                   FROM sortier_lauf l
                  WHERE l.auftrag_id = am.auftrag_id))) / NULLIF(sum(am.eingang_netto_kg), 0::numeric), 0::numeric) AS anteil_mit_csv
           FROM v_auftrag_masse am
          WHERE (am.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND am.eingang_netto_kg IS NOT NULL
          GROUP BY am.charge_nr
        ), gemessen AS MATERIALIZED (
         SELECT v_sortier_lauf_masse.charge_nr,
            sum(v_sortier_lauf_masse.masse_kg) AS gemessen_kg
           FROM v_sortier_lauf_masse
          GROUP BY v_sortier_lauf_masse.charge_nr
        ), rest AS MATERIALIZED (
         SELECT v_kaskade.charge_nr,
            sum(v_kaskade.m2) FILTER (WHERE v_kaskade.portion = 'lager'::text) AS restbestand_kg
           FROM v_kaskade
          GROUP BY v_kaskade.charge_nr
        ), modell AS MATERIALIZED (
         SELECT b_1.charge_nr,
            b_1.am_band_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), COALESCE(b_1.alter_band, 0::numeric)) * (1::numeric - COALESCE(ep.anteil, er.anteil)) * q.anteil_mit_csv AS am_band_modell_kg
           FROM v_kaskade_basis b_1
             LEFT JOIN csv_anteil q ON q.charge_nr = b_1.charge_nr
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b_1.sorte
             LEFT JOIN v_charge_palox ep ON ep.charge_nr = b_1.charge_nr AND ep.station = 'sortieren'::text
             LEFT JOIN v_palox_erwartung er ON er.sorte = b_1.sorte AND er.station = 'sortieren'::text
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.eingang_kg,
    b.ausgelagert_kg,
    b.lager_kg,
    b.n_paletten,
    b.alter_ausgelagert,
    b.alter_lager,
    b.stichtag,
    zahl(m.am_band_modell_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS modell_am_band_kg,
    c.gemessen_kg AS csv_gemessen_kg,
    zahl(c.gemessen_kg - m.am_band_modell_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS abweichung_kg,
        CASE
            WHEN m.am_band_modell_kg > 0::numeric THEN zahl((c.gemessen_kg - m.am_band_modell_kg) / m.am_band_modell_kg, 4, '1000000'::numeric)::numeric(10,4)
            ELSE NULL::numeric
        END AS abweichung_anteil,
    zahl(r.restbestand_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS restbestand_kg,
    kb.alter_band
   FROM erg_charge b
     JOIN v_kaskade_basis kb ON kb.charge_nr = b.charge_nr
     LEFT JOIN modell m ON m.charge_nr = b.charge_nr
     LEFT JOIN gemessen c ON c.charge_nr = b.charge_nr
     LEFT JOIN rest r ON r.charge_nr = b.charge_nr;

create view v_naechste_charge with (security_invoker = true) as
 SELECT p0.schluessel::integer AS charge_nr,
    b.sorte,
    b.schlag,
    p0.lager_kg,
    p0.alter_tage,
    p0.gute_ware_kg AS masse_jetzt_kg,
    zahl(p14.verlust_wasser_kg, 1, '100000000000'::numeric)::numeric(12,1) AS verdunstung_14_kg,
        CASE
            WHEN p0.zuwachs_bekannt THEN zahl(p14.verlust_faeulnis_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1) AS schimmel_14_kg,
        CASE
            WHEN p0.zuwachs_bekannt THEN zahl(p14.verlust_verkaufsfaehig_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1) AS prognose_verlust_14_kg,
    p0.f_geliehen,
    p0.zuwachs_bekannt,
    p0.alter_von,
    p0.alter_bis,
    p0.n_kohorten
   FROM erg_prognose p0
     JOIN erg_prognose p14 ON p14.gruppe = 'charge'::text AND p14.schluessel = p0.schluessel AND p14.h = 14
     JOIN v_kaskade_basis b ON b.charge_nr = p0.schluessel::integer
  WHERE p0.gruppe = 'charge'::text AND p0.h = 0 AND p0.lager_kg > 0::numeric
  ORDER BY (
        CASE
            WHEN p0.zuwachs_bekannt THEN zahl(p14.verlust_verkaufsfaehig_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1)) DESC NULLS LAST;

create view v_plausibilitaet_0054_zusatz with (security_invoker = true) as
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber für ein Band mit diesen Grenzen hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, a.kaliber_von_g, a.kaliber_bis_g) AS befund,
    'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) oder die fertigen Paletten wiegen (drei reichen).'::text AS rat
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx = '-2'::integer AND NOT (EXISTS ( SELECT 1
           FROM v_auftrag_wasch_gewogen wg
          WHERE wg.auftrag_id = g.auftrag_id AND wg.quelle = 'gewogen_strasse'::text))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    wp.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '::text || 'die Menge dieser Arbeit damit auch'::text, wp.n_paletten, wp.kisten,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN format('für das Band %s–%s g hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen'::text, a.kaliber_von_g, a.kaliber_bis_g)
            ELSE 'für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen'::text
        END) AS befund,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen.'::text
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — dann kennt die App das Kistengewicht des Bandes, rückwirkend auch für diese Arbeit; oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat
   FROM v_auftrag_wasch_paletten wp
     JOIN auftrag a ON a.id = wp.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE wp.kg IS NULL AND wp.kisten > 0 AND NOT (EXISTS ( SELECT 1
           FROM v_auftrag_wasch_gewogen wg
          WHERE wg.auftrag_id = wp.auftrag_id AND wg.quelle = 'gewogen_strasse'::text))
UNION ALL
 SELECT 'Lieferung in der Zukunft'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    l.datum::timestamp with time zone AS start_ts,
    format('Lieferschein über %s kg mit Datum %s — das liegt nach heute (%s). '::text || 'Die Menge zählt erst ab diesem Tag in Ausgang und Bestand.'::text, round(l.masse_kg), to_char(l.datum::timestamp with time zone, 'DD.MM.YYYY'::text), to_char(heute()::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Stimmt das Datum? Ein vordatierter Lieferschein ist in Ordnung — die Zahl '::text || 'erscheint von selbst, sobald der Tag da ist. Ein Zahlendreher gehört korrigiert.'::text AS rat
   FROM v_lieferung_masse l
  WHERE l.datum > heute() AND l.masse_kg IS NOT NULL AND l.masse_kg > 0::numeric
UNION ALL
 SELECT v_plausibilitaet_0064_zusatz.art,
    v_plausibilitaet_0064_zusatz.auftrag_id,
    v_plausibilitaet_0064_zusatz.charge_nr,
    v_plausibilitaet_0064_zusatz.sorte,
    v_plausibilitaet_0064_zusatz.start_ts,
    v_plausibilitaet_0064_zusatz.befund,
    v_plausibilitaet_0064_zusatz.rat
   FROM v_plausibilitaet_0064_zusatz;

create view v_verlust_je_gruppe with (security_invoker = true) as
 WITH gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text AS text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text AS text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text AS text,
            v_kaskade_basis.charge_nr::text AS charge_nr,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        ), zeilen AS MATERIALIZED (
         SELECT g_1.gruppe,
            g_1.schluessel,
            h.charge_nr,
            h.sorte,
            h.portion,
            h.f_geliehen,
            h.f_n,
            h.f_se,
            h.strom,
            h.buch,
            h.kg,
            h.basis_kg,
            h.koeff_n,
            h.koeff_basis,
            h.formel,
            h.d_r,
            h.d_f,
            h.d_a,
            h.koeff_art,
            h.koeff_bekannt,
            h.strom = 'Faul beim Abpacken (Fax)'::text AND h.portion = 'lager'::text AS erwartet
           FROM mv_hochrechnung h
             JOIN gruppen g_1 ON g_1.charge_nr = h.charge_nr
          WHERE h.buch = ANY (ARRAY['verlust'::text, 'marge'::text])
        ), unsicherheit AS MATERIALIZED (
         SELECT v_koeff_unsicherheit.art,
            v_koeff_unsicherheit.sorte,
            v_koeff_unsicherheit.b,
            v_koeff_unsicherheit.varianz_eigen,
            v_koeff_unsicherheit.gewicht_gesamt,
            v_koeff_unsicherheit.varianz_gesamt,
            v_koeff_unsicherheit.df
           FROM v_koeff_unsicherheit
        ), eingang AS MATERIALIZED (
         SELECT g_1.gruppe,
            g_1.schluessel,
            sum(b.eingang_kg) AS eingang_kg,
            count(*)::integer AS n_chargen
           FROM gruppen g_1
             JOIN v_kaskade_basis b ON b.charge_nr = g_1.charge_nr
          GROUP BY g_1.gruppe, g_1.schluessel
        ), je_sorte AS MATERIALIZED (
         SELECT zeilen.gruppe,
            zeilen.schluessel,
            zeilen.strom,
            zeilen.buch,
            zeilen.sorte,
            max(zeilen.koeff_art) AS koeff_art,
            sum(zeilen.d_r) AS g_r,
            sum(zeilen.d_a) AS g_a
           FROM zeilen
          WHERE NOT zeilen.erwartet
          GROUP BY zeilen.gruppe, zeilen.schluessel, zeilen.strom, zeilen.buch, zeilen.sorte
        ), je_strom_f AS MATERIALIZED (
         SELECT zeilen.gruppe,
            zeilen.schluessel,
            zeilen.strom,
            zeilen.buch,
            sum(zeilen.d_f * zeilen.f_se) AS g_f,
            min(zeilen.f_n) AS f_n_min
           FROM zeilen
          WHERE NOT zeilen.erwartet
          GROUP BY zeilen.gruppe, zeilen.schluessel, zeilen.strom, zeilen.buch
        ), varianz_r AS MATERIALIZED (
         SELECT s_1.gruppe,
            s_1.schluessel,
            s_1.strom,
            s_1.buch,
            sum(power(s_1.g_r, 2::numeric) * COALESCE(u.varianz_eigen, 0::numeric)) + power(sum(s_1.g_r * COALESCE(u.gewicht_gesamt, 1::numeric)), 2::numeric) * max(COALESCE(u.varianz_gesamt, 0::numeric)) AS varianz,
            min(COALESCE(u.df, 1)) AS df
           FROM je_sorte s_1
             LEFT JOIN unsicherheit u ON u.art = 'verdunstung'::text AND NOT u.sorte IS DISTINCT FROM s_1.sorte
          GROUP BY s_1.gruppe, s_1.schluessel, s_1.strom, s_1.buch
        ), varianz_a AS MATERIALIZED (
         SELECT s_1.gruppe,
            s_1.schluessel,
            s_1.strom,
            s_1.buch,
            sum(power(s_1.g_a, 2::numeric) * COALESCE(u.varianz_eigen, 0::numeric)) + power(sum(s_1.g_a * COALESCE(u.gewicht_gesamt, 1::numeric)), 2::numeric) * max(COALESCE(u.varianz_gesamt, 0::numeric)) AS varianz,
            min(COALESCE(u.df, 1)) AS df
           FROM je_sorte s_1
             LEFT JOIN unsicherheit u ON u.art = s_1.koeff_art AND NOT u.sorte IS DISTINCT FROM s_1.sorte
          WHERE s_1.koeff_art IS NOT NULL
          GROUP BY s_1.gruppe, s_1.schluessel, s_1.strom, s_1.buch
        ), varianz_f AS MATERIALIZED (
         SELECT je_strom_f.gruppe,
            je_strom_f.schluessel,
            je_strom_f.strom,
            je_strom_f.buch,
            power(je_strom_f.g_f, 2::numeric) AS varianz,
            GREATEST(COALESCE(je_strom_f.f_n_min, 2) - 1, 1) AS df
           FROM je_strom_f
        ), summe AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            sum(z.kg) FILTER (WHERE NOT z.erwartet) AS kg,
            bool_and(z.koeff_bekannt) AS bekannt,
            sum(z.kg) FILTER (WHERE z.portion = 'ausgelagert'::text) AS kg_beobachtet,
            sum(z.kg) FILTER (WHERE z.portion = 'lager'::text AND NOT z.erwartet) AS kg_projiziert,
            sum(z.kg) FILTER (WHERE z.f_geliehen AND NOT z.erwartet) AS kg_extrapoliert,
            sum(z.kg) FILTER (WHERE z.erwartet) AS kg_erwartet,
            min(z.koeff_n) AS koeff_n_min,
            sum(z.basis_kg) AS basis_kg,
            max(z.koeff_basis) AS koeff_basis,
            max(z.koeff_art) AS koeff_art,
            max(z.formel) AS formel
           FROM zeilen z
          GROUP BY z.gruppe, z.schluessel, z.strom, z.buch
        )
 SELECT s.gruppe,
    s.schluessel,
    s.strom,
    s.buch,
        CASE
            WHEN s.bekannt THEN zahl(s.kg)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg,
        CASE
            WHEN s.bekannt THEN zahl(GREATEST(s.kg - g.t * g.streuung, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_unten,
        CASE
            WHEN s.bekannt THEN zahl(s.kg + g.t * g.streuung)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_oben,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_beobachtet, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_beobachtet,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_projiziert, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_projiziert,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_extrapoliert, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_extrapoliert,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_erwartet, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_erwartet,
    s.koeff_n_min,
        CASE
            WHEN s.bekannt THEN zahl(g.streuung)
            ELSE NULL::numeric
        END::numeric(14,2) AS streuung_kg,
    g.df,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
    s.koeff_basis,
    s.koeff_art,
    s.formel,
    s.bekannt,
    zahl(e.eingang_kg)::numeric(14,2) AS eingang_kg,
    e.n_chargen
   FROM summe s
     JOIN eingang e ON e.gruppe = s.gruppe AND e.schluessel = s.schluessel
     LEFT JOIN varianz_r vr ON vr.gruppe = s.gruppe AND vr.schluessel = s.schluessel AND vr.strom = s.strom AND vr.buch = s.buch
     LEFT JOIN varianz_a va ON va.gruppe = s.gruppe AND va.schluessel = s.schluessel AND va.strom = s.strom AND va.buch = s.buch
     LEFT JOIN varianz_f vf ON vf.gruppe = s.gruppe AND vf.schluessel = s.schluessel AND vf.strom = s.strom AND vf.buch = s.buch
     CROSS JOIN LATERAL ( SELECT sqrt(GREATEST(COALESCE(vr.varianz, 0::numeric) + COALESCE(va.varianz, 0::numeric) + COALESCE(vf.varianz, 0::numeric), 0::numeric)) AS streuung,
            LEAST(COALESCE(vr.df, 999), COALESCE(va.df, 999), COALESCE(vf.df, 999)) AS df) g0
     CROSS JOIN LATERAL ( SELECT g0.streuung,
            g0.df,
            t_quantil_95(g0.df) AS t) g;

create materialized view erg_verlust as
 SELECT gruppe,
    schluessel,
    strom,
    buch,
    kg,
    kg_unten,
    kg_oben,
    kg_beobachtet,
    kg_projiziert,
    kg_extrapoliert,
    kg_erwartet,
    koeff_n_min,
    streuung_kg,
    df,
    basis_kg,
    koeff_basis,
    koeff_art,
    formel,
    bekannt,
    eingang_kg,
    n_chargen
   FROM v_verlust_je_gruppe
with no data;

create function verlust_ranking(p_sorte text default null, p_schlag text default null, p_charge int default null)
returns table (
  strom text, buch text, kg numeric, kg_unten numeric, kg_oben numeric,
  kg_beobachtet numeric, kg_projiziert numeric, kg_extrapoliert numeric, kg_erwartet numeric,
  koeff_n_min int, streuung_kg numeric, df int)
language sql stable set search_path = public as $$
  select e.strom, e.buch, e.kg, e.kg_unten, e.kg_oben, e.kg_beobachtet, e.kg_projiziert, e.kg_extrapoliert,
         e.kg_erwartet, e.koeff_n_min, e.streuung_kg, e.df
    from public.erg_verlust e
   where e.gruppe = case when p_charge is not null then 'charge'
                         when p_sorte  is not null then 'sorte'
                         when p_schlag is not null then 'schlag'
                         else 'gesamt' end
     and e.schluessel = case when p_charge is not null then p_charge::text
                             when p_sorte  is not null then p_sorte
                             when p_schlag is not null then p_schlag
                             else '' end
   order by e.kg desc nulls last
$$;

create view v_verlust_ranking with (security_invoker = true) as
select * from verlust_ranking();

create view v_plausibilitaet with (security_invoker = true) as
 SELECT 'Schimmel'::text AS art,
    b.auftrag_id,
    b.charge_nr,
    b.sorte,
    b.start_ts,
    format('%s kg Schimmel auf %s kg Ware — das wären %s %%'::text, round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100::numeric)) AS befund,
    'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text AS rat
   FROM v_schimmel_beobachtung b
  WHERE b.anteil IS NOT NULL AND NOT b.plausibel AND NOT b.ist_fax AND b.lagertage >= 0::numeric
UNION ALL
 SELECT 'Fax'::text AS art,
    f.auftrag_id,
    f.charge_nr,
    f.sorte,
    f.start_ts,
    format('%s kg Faules bei %s (%s kg) — das wären %s %%'::text, round(f.faul_kg),
        CASE
            WHEN f.paletten_gesamt > 0 THEN f.paletten_gesamt || ' Paletten'::text
            ELSE f.kisten || ' Kisten'::text
        END, round(f.masse_kg), round(f.anteil * 100::numeric)) AS befund,
    'Entweder die Palettenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'::text AS rat
   FROM v_fax_beobachtung f
  WHERE f.anteil IS NOT NULL AND NOT f.plausibel
UNION ALL
 SELECT 'Ausschuss'::text AS art,
    a.auftrag_id,
    a.charge_nr,
    a.sorte,
    NULL::timestamp with time zone AS start_ts,
    format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse'::text, round(COALESCE(a.klein_kg, 0::numeric)), round(COALESCE(a.gross_kg, 0::numeric)), round(a.basis_kg)) AS befund,
    'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'::text AS rat
   FROM v_ausschuss_beobachtung a
  WHERE a.weg = 'hand'::verarbeitungsweg AND NOT a.plausibel
UNION ALL
 SELECT 'Ohne Nenner'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein'::text, concat_ws(' und '::text,
        CASE
            WHEN COALESCE(s.kg, 0::numeric) > 0::numeric THEN round(s.kg) || ' kg Faules'::text
            ELSE NULL::text
        END,
        CASE
            WHEN COALESCE(x.kg, 0::numeric) > 0::numeric THEN round(x.kg) || ' kg zu klein/gross'::text
            ELSE NULL::text
        END),
        CASE
            WHEN a.ist_fax THEN 'keine Palette gezählt oder noch keine fertige Palette dieser Sorte gewogen'::text
            WHEN a.station = 'waschen'::station THEN 'keine Kiste gezählt und keine Menge eingetragen'::text
            WHEN a.station = 'waschen_sortieren'::station THEN 'keine Palette mit Gewicht vom Zettel gezählt'::text
            ELSE 'keine Palette gezählt'::text
        END) AS befund,
        CASE
            WHEN a.ist_fax THEN ('Die Palettenzahl am Ende der Fax-Arbeit eintragen. Fehlt die Palettenmasse, '::text || 'beim Waschen oder Waschen + Sortieren eine fertige Palette wiegen — sie '::text) || 'gilt dann für alle Fax-Arbeiten der Sorte.'::text
            WHEN a.station = 'waschen'::station THEN 'Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich '::text || 'selbst) oder die verarbeitete Menge in kg nachtragen.'::text
            WHEN a.station = 'waschen_sortieren'::station THEN 'Die Paletten mit Datum und Gewicht vom Zettel am Auftrag nachtragen.'::text
            ELSE 'Die gezählten Paletten am Auftrag nachtragen.'::text
        END AS rat
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_schimmel_menge s ON s.auftrag_id = a.id
     LEFT JOIN ( SELECT ausschuss_messung.auftrag_id,
            sum(ausschuss_messung.kg)::numeric AS kg
           FROM ausschuss_messung
          WHERE ausschuss_messung.gemessen
          GROUP BY ausschuss_messung.auftrag_id) x ON x.auftrag_id = a.id
     LEFT JOIN v_auftrag_masse m ON m.auftrag_id = a.id
  WHERE a.abgebrochen_ts IS NULL AND (COALESCE(s.kg, 0::numeric) > 0::numeric OR COALESCE(x.kg, 0::numeric) > 0::numeric) AND COALESCE(m.eingang_netto_kg, 0::numeric) <= 0::numeric
UNION ALL
 SELECT 'Palox'::text AS art,
    s.auftrag_id,
    a.charge_nr,
    c.sorte,
    s.ts AS start_ts,
    format('Waagenstand %s kg liegt unter dem Leergewicht des Palox (%s kg)'::text, s.palox_stand_kg, palox_tara_kg()) AS befund,
    'Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '::text || 'Sonst ist der Stand vertippt.'::text AS rat
   FROM schimmel_messung s
     JOIN auftrag a ON a.id = s.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE s.gemessen AND a.abgebrochen_ts IS NULL AND s.palox_stand_kg IS NOT NULL AND s.palox_stand_kg < palox_tara_kg()
UNION ALL
 SELECT 'Palox geleert'::text AS art,
    p.auftrag_id,
    a.charge_nr,
    c.sorte,
    p.ts AS start_ts,
    format('Der Waagenstand fiel von %s auf %s kg — der Palox wurde zwischendurch geleert. '::text || 'Wie viel davor noch dazukam, weiss niemand; das Faule dieser Arbeit ist unbekannt.'::text, p.vorher, p.palox_stand_kg) AS befund,
    'Nichts zu korrigieren. Beim nächsten Mal in der Checkliste „Palox leeren" drücken: vor dem Leeren ablesen, danach die leere Box — dann bleibt die Menge bekannt.'::text AS rat
   FROM v_palox_stand p
     JOIN auftrag a ON a.id = p.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE p.differenz IS NULL AND a.abgebrochen_ts IS NULL
UNION ALL
 SELECT 'Wägung'::text AS art,
    w.auftrag_id,
    w.charge_nr,
    w.sorte,
    w.wiege_ts AS start_ts,
    ('Palette gewogen, aber '::text ||
        CASE
            WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'für die Gebindeart fehlt die Tara'::text
            WHEN w.lagertage <= 0 THEN 'das Wiegedatum liegt nicht nach dem Eingangsdatum'::text
            WHEN w.netto_damals_kg <= 0::numeric OR w.netto_jetzt_kg <= 0::numeric THEN 'das Netto ist null oder negativ'::text
            WHEN w.netto_jetzt_kg > (w.netto_damals_kg * 1.01) THEN format('sie wiegt jetzt %s kg mehr als beim Eingang, und im Lager wird keine Palette schwerer'::text, round(w.netto_jetzt_kg - w.netto_damals_kg))
            WHEN w.netto_jetzt_kg = w.netto_damals_kg THEN 'sie hat kein Gramm verloren — sehr wahrscheinlich wurde das Eingangsgewicht kopiert (etwa bei einer sortierten Palette, deren Zettelgewicht es nicht gibt)'::text
            ELSE 'sie ist nicht verwertbar'::text
        END) || ' — sie zählt nicht in die Verdunstungsrate'::text AS befund,
        CASE
            WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'Unter Stammdaten → Gebinde die Tara nachtragen.'::text
            WHEN w.netto_jetzt_kg > (w.netto_damals_kg * 1.01) THEN 'Gebindeart, Kistenzahl und beide Gewichte prüfen — meist stimmt die Tara nicht oder eine Zahl ist verdreht.'::text
            ELSE 'Eingangsdatum und Gewichte der Wägung prüfen.'::text
        END AS rat
   FROM v_verdunstung_messung w
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
  WHERE NOT w.verwendbar AND NOT w.sichtbar_schimmel AND COALESCE(w.grund, ''::text) !~~ 'zu schnell%'::text AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
           FROM verdunstung_wiegung v
          WHERE v.id = w.id AND v.gemessen))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN format('%s Kisten nach Sollgewicht gezählt, aber für diese Sorte wurde noch '::text || 'nie eine fertige Palette gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl)
            ELSE format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, g.kaliber_idx + 1)
        END AS befund,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN 'Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '::text || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'::text
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — daraus kennt die App das Kistengewicht des Bandes, rückwirkend für alle Waschgänge dieser Sorte, auch für diesen. Oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx <> '-2'::integer
UNION ALL
 SELECT 'Waage'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
        CASE
            WHEN w.netto_kg <= 0::numeric THEN format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — leichter als ihre Kisten und die Palette (Tara %s kg)'::text, ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(ap.kisten::numeric * g.tara_kg_pro_kiste + g.tara_kg_palette, 1))
            ELSE format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — %s kg je Kiste'::text, ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(w.netto_kg / ap.kisten::numeric, 1))
        END AS befund,
    'Waage, Kistenzahl oder Gebinde prüfen und im Korrekturfenster der Arbeit berichtigen — bis dahin rechnet die Masse dieser Palette mit.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = ap.gebindeart
     CROSS JOIN LATERAL ( SELECT ap.brutto_gewogen_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_kg) w
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL AND ap.brutto_gewogen_kg IS NOT NULL AND ap.kisten IS NOT NULL AND ap.kisten > 0 AND g.tara_kg_pro_kiste IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND (w.netto_kg <= 0::numeric OR (w.netto_kg / ap.kisten::numeric) < 4::numeric OR (w.netto_kg / ap.kisten::numeric) > 30::numeric)
UNION ALL
 SELECT 'Kaliber fehlt'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen'::text AS befund,
    'Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '::text || 'Stammdaten → Sortierschemata.'::text AS rat
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.kaliber_idx IS NULL AND a.kaliber_von_g IS NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM auftrag_gebinde g
          WHERE g.auftrag_id = a.id AND g.anzahl > 0))
UNION ALL
 SELECT 'Ausschuss-Tara'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    m.ts AS start_ts,
    format('%s kg %s gespeichert — aus Brutto %s kg und heutiger Tara wären es %s kg'::text, m.kg,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'zu klein'::text
            ELSE 'zu gross'::text
        END, m.brutto_kg, round(n.roh)) AS befund,
    'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '::text || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
     CROSS JOIN LATERAL ( SELECT m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste -
                CASE
                    WHEN m.mit_palette THEN g.tara_kg_palette
                    ELSE 0::numeric
                END AS roh) n
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND n.roh IS NOT NULL AND m.kg::numeric <> round(n.roh)
UNION ALL
 SELECT 'Ausschuss ohne Tara'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    m.ts AS start_ts,
    format('%s kg %s mit %s kg brutto gespeichert — nachrechnen lässt sich das nicht: %s'::text, m.kg,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'zu klein'::text
            ELSE 'zu gross'::text
        END, m.brutto_kg,
        CASE
            WHEN m.gebindeart IS NULL THEN 'an der Wägung steht keine Gebindeart'::text
            WHEN g.art IS NULL THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN g.tara_kg_pro_kiste IS NULL THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN g.tara_kg_palette IS NULL THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END) AS befund,
    'Die gespeicherten Kilo bleiben, wie sie sind — geprüft werden können sie erst, '::text || 'wenn Gebindeart, Tara und Kistenzahl beisammen sind.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND (m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) IS NULL
UNION ALL
 SELECT 'Zetteldatum'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Zetteldatum %s gezählt, aber an dem Tag kam keine Palette dieser Charge'::text, count(*), to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.eingangsdatum IS NOT NULL AND ap.palette_id IS NULL AND ap.wiegung_id IS NULL AND a.abgebrochen_ts IS NULL AND NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.eingangsdatum = ap.eingangsdatum))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.eingangsdatum
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — %s'::text, count(*), ap.brutto_zettel_kg,
        CASE
            WHEN bool_and(m.masse_quelle = 'gewogen'::text) THEN 'gerechnet wird mit der Wägung der Palette'::text
            WHEN bool_and(m.masse_quelle = 'zettel-kisten'::text) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            WHEN bool_and(m.masse_quelle = ANY (ARRAY['zettel-kisten'::text, 'zettel-kisten-charge'::text, 'gewogen'::text])) THEN 'gerechnet wird mit den gezählten Kisten und der Tara je Kiste der Charge (Zettel − Kisten × Tara je Kiste)'::text
            ELSE 'gerechnet wird mit der mittleren Tara ganzer Paletten der Charge — an der Zählung fehlt die Kistenzahl'::text
        END) AS befund,
    'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal).'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.id = ap.id
  WHERE ap.brutto_zettel_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg
UNION ALL
 SELECT 'Lieferung ohne Eingang'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    min(l.datum)::timestamp with time zone AS start_ts,
    format('%s Lieferung(en) mit %s kg an Charge %s, aber im Wareneingang steht keine Palette dieser Charge'::text, count(*), round(sum(l.masse_kg)), l.charge_nr) AS befund,
    'Wareneingang der Charge nachtragen (Erntejournal) — oder die Lieferung gehört zu einer anderen Charge.'::text AS rat
   FROM v_lieferung_masse l
  WHERE l.buch = 'verkauf'::text AND l.charge_nr IS NOT NULL AND l.masse_kg > 0::numeric AND NOT (EXISTS ( SELECT 1
           FROM v_kohorte_anteil k
          WHERE k.charge_nr = l.charge_nr))
  GROUP BY l.charge_nr, l.sorte
UNION ALL
 SELECT v_plausibilitaet_0054_zusatz.art,
    v_plausibilitaet_0054_zusatz.auftrag_id,
    v_plausibilitaet_0054_zusatz.charge_nr,
    v_plausibilitaet_0054_zusatz.sorte,
    v_plausibilitaet_0054_zusatz.start_ts,
    v_plausibilitaet_0054_zusatz.befund,
    v_plausibilitaet_0054_zusatz.rat
   FROM v_plausibilitaet_0054_zusatz
UNION ALL
 SELECT 'Zetteldatum Zukunft'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Eingangsdatum %s gezählt — das liegt in der Zukunft, sehr wahrscheinlich ein falsches Jahr'::text, count(*), to_char(max(ap.eingangsdatum)::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung korrigieren (Jahr prüfen). Die Beobachtung bleibt gespeichert, bis sie berichtigt ist; solange rechnet die Auswertung sie nicht mit.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.eingangsdatum > heute() AND a.abgebrochen_ts IS NULL
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts
UNION ALL
 SELECT 'Palettengewicht'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    p.eingangsdatum::timestamp with time zone AS start_ts,
    format('Eine Palette mit %s kg brutto — für eine Palette Kürbisse ist das unmöglich'::text, round(p.brutto_kg)) AS befund,
    'Bruttogewicht im Wareneingang prüfen — sehr wahrscheinlich ein Zahlendreher.'::text AS rat
   FROM palette p
     JOIN charge c ON c.nr = p.charge_nr
  WHERE p.brutto_kg > 2000::numeric;

create view v_marge_buch with (security_invoker = true) as
 WITH verkauf AS (
         SELECT sum(v_ueberfuellung_verkauf.verschenkt_kg) AS verschenkt_kg,
            sum(
                CASE
                    WHEN v_ueberfuellung_verkauf.verschenkt_kg IS NULL THEN NULL::numeric
                    ELSE GREATEST(v_ueberfuellung_verkauf.verschenkt_kg - COALESCE(v_ueberfuellung_verkauf.verschenkt_fehler_kg, 0::numeric), 0::numeric)
                END) AS verschenkt_unten_kg,
            sum(v_ueberfuellung_verkauf.verschenkt_kg + COALESCE(v_ueberfuellung_verkauf.verschenkt_fehler_kg, 0::numeric)) AS verschenkt_oben_kg,
            sum(v_ueberfuellung_verkauf.kisten_verkauft) FILTER (WHERE v_ueberfuellung_verkauf.n_wiegungen > 0) AS kisten_gerechnet,
            sum(v_ueberfuellung_verkauf.kisten_verkauft) FILTER (WHERE v_ueberfuellung_verkauf.n_wiegungen = 0) AS kisten_ungewogen,
            sum(v_ueberfuellung_verkauf.n_wiegungen) AS n_wiegungen,
            sum(v_ueberfuellung_verkauf.kisten_gewogen) AS kisten_gewogen,
            sum(v_ueberfuellung_verkauf.zuviel_je_kiste * v_ueberfuellung_verkauf.kisten_gewogen::numeric) / NULLIF(sum(v_ueberfuellung_verkauf.kisten_gewogen) FILTER (WHERE v_ueberfuellung_verkauf.zuviel_je_kiste IS NOT NULL), 0::numeric) AS zuviel_je_kiste,
            count(*) FILTER (WHERE v_ueberfuellung_verkauf.n_lieferungen > 0)::integer AS n_gruppen_verkauft
           FROM v_ueberfuellung_verkauf
          WHERE v_ueberfuellung_verkauf.gruppe = 'sorte'::text AND v_ueberfuellung_verkauf.kistensystem = 'kiste_ab'::text
        ), datei AS (
         SELECT count(*)::integer AS n
           FROM lieferung_import
        )
 SELECT r.strom AS posten,
    r.kg,
    r.kg_unten,
    r.kg_oben,
        CASE r.strom
            WHEN 'Nebenkanal zu gross'::text THEN 'Ware über der oberen Kalibergrenze geht in einen anderen Verkaufskanal — nicht weg, nur nicht zum besten Preis'::text
            WHEN 'Zu klein (Tierfutter)'::text THEN 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'::text
            ELSE ''::text
        END AS erlaeuterung,
    r.kg IS NOT NULL AS gemessen
   FROM erg_verlust r
  WHERE r.gruppe = 'gesamt'::text AND r.buch = 'marge'::text
UNION ALL
 SELECT 'Überfüllung der Kisten'::text AS posten,
    zahl(v.verschenkt_kg)::numeric(14,2) AS kg,
    zahl(v.verschenkt_unten_kg)::numeric(14,2) AS kg_unten,
    zahl(v.verschenkt_oben_kg)::numeric(14,2) AS kg_oben,
        CASE
            WHEN d.n = 0 THEN 'Keine Verkaufsdatei eingelesen — wie viele Kisten „ab x kg" verkauft wurden, weiss die App nicht. Nichts gerechnet.'::text
            WHEN COALESCE(v.n_wiegungen, 0::bigint) = 0 THEN format('%s Kisten „ab x kg" laut Verkaufsdatei verkauft, aber keine fertige Palette dieses Systems gewogen — nichts gerechnet.'::text, round(COALESCE(v.kisten_ungewogen, 0::numeric)))
            ELSE format(('%s gewogene Paletten (%s Kisten): im Schnitt %s kg je Kiste über dem Soll. '::text || 'Verkauft laut Verkaufsdatei: %s Kisten desselben Systems — daraus die Zahl. '::text) || '%s'::text, v.n_wiegungen, round(COALESCE(v.kisten_gewogen, 0::numeric)), round(COALESCE(v.zuviel_je_kiste, 0::numeric), 3), round(COALESCE(v.kisten_gerechnet, 0::numeric)),
            CASE
                WHEN COALESCE(v.kisten_ungewogen, 0::numeric) > 0::numeric THEN format('Weitere %s verkaufte Kisten haben kein gewogenes Gegenstück (Sorte oder Soll ohne Wägung) und sind nicht gerechnet.'::text, round(v.kisten_ungewogen))
                ELSE 'Kisten nach Stück haben kein Sollgewicht und damit keine Überfüllung.'::text
            END)
        END AS erlaeuterung,
    v.verschenkt_kg IS NOT NULL AS gemessen
   FROM verkauf v
     CROSS JOIN datei d;

create view v_saisonbilanz with (security_invoker = true) as
 WITH charge AS (
         SELECT sum(erg_charge.eingang_kg) AS eingang_kg,
            sum(erg_charge.ausgelagert_kg) AS ausgelagert_kg,
            sum(erg_charge.geliefert_kg) AS geliefert_kg,
            sum(erg_charge.lager_kg) AS lager_kg,
            sum(erg_charge.wartet_kg) AS wartet_kg,
            sum(erg_charge.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(erg_charge.verkaufsfaehig_lager_kg) AS verkaufsfaehig_heute_kg,
            sum(erg_charge.im_haus_heute_kg) AS im_haus_heute_kg,
            sum(erg_charge.kanal_im_haus_kg) AS kanal_im_haus_kg,
            sum(erg_charge.verlust_heute_kg) AS verlust_heute_kg,
            sum(erg_charge.verdunstung_heute_kg) AS verdunstung_heute_kg,
            sum(erg_charge.schimmel_heute_kg) AS schimmel_heute_kg,
            sum(erg_charge.fax_heute_kg) AS fax_heute_kg,
            sum(erg_charge.fax_erwartet_kg) AS fax_erwartet_kg,
            sum(erg_charge.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            bool_and(erg_charge.verlust_bekannt) AS bekannt,
            count(*)::integer AS n_chargen,
            max(erg_charge.heute) AS heute
           FROM erg_charge
        ), bereich AS (
         SELECT sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_oben_kg,
            sum(erg_verlust.kg) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_kg,
            sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = 'marge'::text) AS kanal_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = 'marge'::text) AS kanal_oben_kg
           FROM erg_verlust
          WHERE erg_verlust.gruppe = 'gesamt'::text
        ), vorlauf AS (
         SELECT COALESCE(sum(charge_vorlauf.ausgang_vor_app_kg), 0::numeric) AS kg
           FROM charge_vorlauf
        ), ausgang AS (
         SELECT COALESCE(sum(v_lieferung_masse.masse_kg), 0::numeric) AS kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'verkauf'::text), 0::numeric) AS verkauf_kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'marge'::text), 0::numeric) AS marge_kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'verlust'::text), 0::numeric) AS entsorgt_kg,
            COALESCE(sum(v_lieferung_masse.masse_fehler_kg), 0::double precision) AS fehler_kg,
            count(*)::integer AS n_lieferungen,
            max(v_lieferung_masse.datum) AS letzte_lieferung
           FROM v_lieferung_masse
          WHERE v_lieferung_masse.datum <= heute()
        ), fax AS (
         SELECT COALESCE(sum(v_fax_beobachtung.masse_kg), 0::numeric) AS kg,
            count(*)::integer AS n
           FROM v_fax_beobachtung
          WHERE v_fax_beobachtung.status = 'abgeschlossen'::auftrag_status AND v_fax_beobachtung.masse_kg IS NOT NULL
        )
 SELECT c.heute,
    zahl(c.eingang_kg)::numeric(14,2) AS eingang_kg,
    c.n_chargen,
    zahl(a.kg + vl.kg)::numeric(14,2) AS ausgang_kg,
    zahl(a.verkauf_kg)::numeric(14,2) AS verkauf_kg,
    zahl(a.marge_kg)::numeric(14,2) AS marge_kg,
    zahl(a.entsorgt_kg)::numeric(14,2) AS entsorgt_kg,
    zahl(a.fehler_kg)::numeric(14,2) AS ausgang_fehler_kg,
    a.n_lieferungen,
    a.letzte_lieferung,
    zahl(vl.kg)::numeric(14,2) AS vorlauf_kg,
    zahl(c.geliefert_kg)::numeric(14,2) AS geliefert_kg,
    zahl(c.ausgelagert_kg)::numeric(14,2) AS ausgelagert_kg,
    zahl(c.verlust_heute_kg)::numeric(14,2) AS verlust_heute_kg,
    zahl(b.verlust_unten_kg)::numeric(14,2) AS verlust_unten_kg,
    zahl(b.verlust_oben_kg)::numeric(14,2) AS verlust_oben_kg,
    zahl(c.verdunstung_heute_kg)::numeric(14,2) AS verdunstung_heute_kg,
    zahl(c.schimmel_heute_kg)::numeric(14,2) AS schimmel_heute_kg,
    zahl(c.fax_heute_kg)::numeric(14,2) AS fax_heute_kg,
    zahl(c.fax_erwartet_kg)::numeric(14,2) AS fax_erwartet_kg,
    zahl(c.kanal_ausgelagert_kg)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(b.kanal_unten_kg)::numeric(14,2) AS kanal_unten_kg,
    zahl(b.kanal_oben_kg)::numeric(14,2) AS kanal_oben_kg,
    zahl(c.im_haus_heute_kg)::numeric(14,2) AS im_haus_heute_kg,
    zahl(c.verkaufsfaehig_heute_kg)::numeric(14,2) AS verkaufsfaehig_heute_kg,
    zahl(c.kanal_im_haus_kg)::numeric(14,2) AS kanal_im_haus_kg,
    zahl(c.lager_kg)::numeric(14,2) AS lager_kg,
    zahl(c.wartet_kg)::numeric(14,2) AS gegenprobe_wartet_kg,
    zahl(c.ueberzaehlung_kg)::numeric(14,2) AS ueberzaehlung_kg,
    zahl(f.kg)::numeric(14,2) AS fax_durchsatz_kg,
    f.n AS n_fax_arbeiten,
    COALESCE(c.bekannt, false) AS verlust_bekannt,
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.im_haus_heute_kg)::numeric(14,2) AS bilanz_rest_kg,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.im_haus_heute_kg) / c.eingang_kg
            ELSE NULL::numeric
        END, 4, '100000'::numeric)::numeric(10,4) AS bilanz_rest_anteil,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (a.kg + vl.kg) / c.eingang_kg
            ELSE NULL::numeric
        END, 4, '100000'::numeric)::numeric(10,4) AS ausgang_deckung,
        CASE
            WHEN COALESCE(c.eingang_kg, 0::numeric) <= 0::numeric THEN 'Es ist kein Wareneingang erfasst. Ohne das Erntejournal gibt es '::text || 'nichts, worauf sich Verlust und Bestand beziehen könnten.'::text
            WHEN COALESCE(c.ueberzaehlung_kg, 0::numeric) > (0.05 * c.eingang_kg) THEN format((('Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — '::text || 'bei einigen Chargen rund %s kg zu viel. Fast immer fehlt der '::text) || 'Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine '::text) || 'Lieferung ist der falschen Charge zugeordnet.'::text, round(c.ueberzaehlung_kg))
            WHEN a.n_lieferungen = 0 AND vl.kg = 0::numeric THEN ('Kein Warenausgang erfasst — dann liegt rechnerisch noch alles im Haus, '::text || 'und der Verlust bis heute gilt für die ganze Eingangsmasse. Sobald die '::text) || 'Lieferscheine eingelesen sind, teilt sich die Ware in ausgeliefert und liegend.'::text
            WHEN NOT COALESCE(c.bekannt, false) THEN 'Ein Verluststrom ist noch nicht gemessen — die Ursachen sind erst '::text || 'vollständig, wenn jeder Koeffizient mindestens eine Messung hat.'::text
            ELSE format((('Bis heute (%s): %s t Eingang = %s t ausgeliefert + %s t Verlust '::text || '(Verdunstung %s t, Faules %s t, Fax %s t) '::text) || '+ %s t noch im Haus (davon %s t verkaufsfähig, %s t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum '::text) || 'Saisonende steht in der Grafik, nicht in diesen Zahlen.%s'::text, to_char(c.heute::timestamp with time zone, 'DD.MM.YYYY'::text), round(c.eingang_kg / 1000.0, 1), round(c.geliefert_kg / 1000.0, 1), round(c.verlust_heute_kg / 1000.0, 1), round(c.verdunstung_heute_kg / 1000.0, 1), round(c.schimmel_heute_kg / 1000.0, 1), round(c.fax_heute_kg / 1000.0, 1), round(c.im_haus_heute_kg / 1000.0, 1), round(c.verkaufsfaehig_heute_kg / 1000.0, 1), round((c.kanal_ausgelagert_kg + c.kanal_im_haus_kg) / 1000.0, 1), concat_ws(' '::text, '',
            CASE
                WHEN a.marge_kg > 0::numeric THEN format('An die Tiere und in den Nebenkanal geliefert: %s kg; hinter den Lieferungen aussortiert gerechnet: %s kg.'::text, round(a.marge_kg), round(c.kanal_ausgelagert_kg))
                ELSE NULL::text
            END,
            CASE
                WHEN a.entsorgt_kg > 0::numeric THEN format('Entsorgt: %s kg, gerechneter Schimmel: %s kg.'::text, round(a.entsorgt_kg), round(c.schimmel_heute_kg))
                ELSE NULL::text
            END,
            CASE
                WHEN COALESCE(c.ueberzaehlung_kg, 0::numeric) > 0::numeric THEN format('%s kg Überzählung.'::text, round(c.ueberzaehlung_kg))
                ELSE NULL::text
            END))
        END AS befund
   FROM charge c
     CROSS JOIN bereich b
     CROSS JOIN ausgang a
     CROSS JOIN vorlauf vl
     CROSS JOIN fax f;

create view v_wohin with (security_invoker = true) as
 WITH gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'sorte'::text AS text,
            erg_charge.sorte,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'schlag'::text AS text,
            erg_charge.schlag,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'charge'::text AS text,
            erg_charge.charge_nr::text AS charge_nr,
            erg_charge.charge_nr
           FROM erg_charge
        ), charge AS (
         SELECT g.gruppe,
            g.schluessel,
            count(*)::integer AS n_chargen,
            sum(c_1.eingang_kg) AS eingang_kg,
            sum(c_1.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(c_1.geliefert_kg) AS geliefert_kg,
            sum(c_1.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            sum(c_1.fax_heute_kg) AS fax_kg,
            sum(c_1.im_haus_heute_kg) AS lager_gute_ware_kg,
            sum(c_1.verkaufsfaehig_lager_kg) AS lager_verkaufsfaehig_kg,
            sum(c_1.kanal_im_haus_kg) AS lager_kanal_kg,
            sum(c_1.fax_erwartet_kg) AS lager_fax_kg,
            sum(c_1.lager_kg) AS lager_kg,
            bool_and(c_1.verlust_bekannt) AS vollstaendig
           FROM gruppen g
             JOIN erg_charge c_1 ON c_1.charge_nr = g.charge_nr
          GROUP BY g.gruppe, g.schluessel
        ), stroeme AS (
         SELECT erg_verlust.gruppe,
            erg_verlust.schluessel,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Verdunstung'::text) AS verdunstet_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Verdunstung'::text) AS lager_verdunstet_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Schimmel/Fäulnis'::text) AS faul_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Schimmel/Fäulnis'::text) AS lager_faul_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Zu klein (Tierfutter)'::text) AS klein_ausgelagert_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Nebenkanal zu gross'::text) AS gross_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Zu klein (Tierfutter)'::text) AS lager_klein_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Nebenkanal zu gross'::text) AS lager_gross_kg
           FROM erg_verlust
          GROUP BY erg_verlust.gruppe, erg_verlust.schluessel
        )
 SELECT c.gruppe,
    c.schluessel,
    c.n_chargen,
    zahl(c.eingang_kg)::numeric(14,2) AS eingang_kg,
    zahl(c.ueberzaehlung_kg)::numeric(14,2) AS ueberzaehlung_kg,
    zahl(c.geliefert_kg)::numeric(14,2) AS geliefert_kg,
    zahl(c.kanal_ausgelagert_kg)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(s.klein_ausgelagert_kg)::numeric(14,2) AS klein_ausgelagert_kg,
    zahl(s.gross_ausgelagert_kg)::numeric(14,2) AS gross_ausgelagert_kg,
    zahl(s.verdunstet_ausgelagert_kg)::numeric(14,2) AS verdunstet_ausgelagert_kg,
    zahl(s.faul_ausgelagert_kg)::numeric(14,2) AS faul_ausgelagert_kg,
    zahl(c.fax_kg)::numeric(14,2) AS fax_kg,
    zahl(c.lager_kg)::numeric(14,2) AS lager_kg,
    zahl(c.lager_gute_ware_kg)::numeric(14,2) AS lager_gute_ware_kg,
    zahl(c.lager_verkaufsfaehig_kg)::numeric(14,2) AS lager_verkaufsfaehig_kg,
    zahl(c.lager_kanal_kg)::numeric(14,2) AS lager_kanal_kg,
    zahl(s.lager_klein_kg)::numeric(14,2) AS lager_klein_kg,
    zahl(s.lager_gross_kg)::numeric(14,2) AS lager_gross_kg,
    zahl(c.lager_fax_kg)::numeric(14,2) AS lager_fax_kg,
    zahl(s.lager_faul_kg)::numeric(14,2) AS lager_faul_kg,
    zahl(s.lager_verdunstet_kg)::numeric(14,2) AS lager_verdunstet_kg,
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.kanal_ausgelagert_kg - s.verdunstet_ausgelagert_kg - s.faul_ausgelagert_kg - c.fax_kg - c.lager_kg)::numeric(14,2) AS rest_kg,
    zahl(c.lager_kg - c.lager_verkaufsfaehig_kg - c.lager_kanal_kg - c.lager_fax_kg - s.lager_faul_kg - s.lager_verdunstet_kg)::numeric(14,2) AS lager_rest_kg,
    c.vollstaendig
   FROM charge c
     LEFT JOIN stroeme s ON s.gruppe = c.gruppe AND s.schluessel = c.schluessel;

create materialized view erg_wohin as
 SELECT gruppe,
    schluessel,
    n_chargen,
    eingang_kg,
    ueberzaehlung_kg,
    geliefert_kg,
    kanal_ausgelagert_kg,
    klein_ausgelagert_kg,
    gross_ausgelagert_kg,
    verdunstet_ausgelagert_kg,
    faul_ausgelagert_kg,
    fax_kg,
    lager_kg,
    lager_gute_ware_kg,
    lager_verkaufsfaehig_kg,
    lager_kanal_kg,
    lager_klein_kg,
    lager_gross_kg,
    lager_fax_kg,
    lager_faul_kg,
    lager_verdunstet_kg,
    rest_kg,
    lager_rest_kg,
    vollstaendig
   FROM v_wohin
with no data;

create or replace view v_kunde_position with (security_invoker = true) as
select v.quelle, v.pos_id, v.kunde, v.saison, v.datum, e.gruppe, e.groesse, e.label,
       v.artikel_id, v.artikel, v.preisgruppe, v.menge, v.einheit, v.kg, v.herkunft
  from v_verkauf_position v
  left join ausgang_artikel a on a.artikel_id = v.artikel_id and a.artikel = v.artikel
 cross join lateral artikel_einordnen(v.artikel, v.preisgruppe) e
 where coalesce(v.journal, '') <> 'L'
   and coalesce(a.ist_kuerbis, ist_kuerbis_vorschlag(v.artikel_id, v.artikel))
   and v.kunde is not null and v.kunde <> '';
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
          (s.kaliber_baender -> g.kaliber_idx ->> 1)::int with no data;

create or replace view v_kaliber_verteilung with (security_invoker = true) as
select * from mv_kaliber_verteilung;

do $$
declare
  paar text[];
  paare text[][] := array[
    -- [erg-Name, Quelle]
    ['erg_gewichte',           'v_gewichtsverteilung'],
    ['erg_kaliber',            'v_kaliber_verteilung'],
    ['erg_gebinde',            'v_koeff_gebinde'],
    ['erg_ausgang',            'v_ausgang_voll'],        -- seit 0089 mit voll
    ['erg_lieferung',          'v_lieferung_masse'],
    ['erg_kohorte',            'v_charge_kohorte'],
    ['erg_koeff_verdunstung',  'v_koeff_verdunstung'],
    ['erg_koeff_ausschuss',    'v_koeff_ausschuss'],
    ['erg_koeff_nebenkanal',   'v_koeff_nebenkanal'],
    ['erg_koeff_ueberfuellung','v_koeff_ueberfuellung'],
    ['erg_wiegung',            'v_wiegung_kennzahl'],
    ['erg_fax',                'v_fax_beobachtung'],
    ['erg_ausschuss',          'v_ausschuss_beobachtung'],
    ['erg_verarbeitung_alter', 'v_verarbeitung_alter'],
    ['erg_durchsatz',          'v_durchsatz'],
    ['erg_bilanz',             'v_saisonbilanz'],
    ['erg_marge',              'v_marge_buch'],
    ['erg_massenbilanz',       'v_massenbilanz'],
    ['erg_naechste_charge',    'v_naechste_charge'],
    ['erg_datenlage',          'v_datenlage'],
    ['erg_plausibilitaet',     'v_plausibilitaet'],
    ['erg_datenqualitaet',     'v_datenqualitaet']
  ];
begin
  foreach paar slice 1 in array paare loop
    execute format('drop materialized view if exists %I cascade', paar[1]);
    execute format('create materialized view %I as select * from %I with no data', paar[1], paar[2]);
    execute format('grant select on %I to authenticated', paar[1]);
    execute format('comment on materialized view %I is %L', paar[1],
                   format('%s, gespeichert für die App Erneuert mit auswertung_schritt().', paar[2]));
  end loop;
end $$;

do $$
declare
  paar text[];
  paare text[][] := array[
    ['erg_bilanz',          'v_saisonbilanz'],
    ['erg_marge',           'v_marge_buch'],
    ['erg_massenbilanz',    'v_massenbilanz'],
    ['erg_naechste_charge', 'v_naechste_charge'],
    ['erg_plausibilitaet',  'v_plausibilitaet']
  ];
begin
  foreach paar slice 1 in array paare loop
    execute format('drop materialized view if exists %I cascade', paar[1]);
    execute format('create materialized view %I as select * from %I with no data', paar[1], paar[2]);
    execute format('grant select on %I to authenticated', paar[1]);
    execute format('comment on materialized view %I is %L', paar[1],
                   format('%s, gespeichert für die App Erneuert mit auswertung_schritt().', paar[2]));
  end loop;
end $$;

create materialized view if not exists erg_kaliber as select * from v_kaliber_verteilung with no data;

create or replace view v_ohne_charge with (security_invoker = true) as
with l as (
  select l.id, l.datum, l.sorte, l.masse_kg
    from v_lieferung_masse l
   where l.charge_nr is null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge') and l.datum <= heute()
), auf as (
  select lc.id, lc.charge_nr, l.sorte, l.masse_kg * lc.anteil as kg, l.datum < r.erster_eingang as vor_eingang
    from v_lieferung_charge lc
    join l on l.id = lc.id
    join v_charge_rueckgrat r on r.charge_nr = lc.charge_nr
   where lc.ohne_charge
), je_charge as (
  select a.sorte, a.charge_nr, sum(a.kg) as kg, sum(a.kg) filter (where a.vor_eingang) as kg_vor
    from auf a group by a.sorte, a.charge_nr
)
select l.sorte,
       count(*)::int as n_lieferungen,
       zahl(sum(l.masse_kg), 2, 1e12)::numeric(14,2) as kg,
       min(l.datum) as erste, max(l.datum) as letzte,
       zahl(coalesce((select sum(j.kg_vor) from je_charge j where j.sorte is not distinct from l.sorte), 0), 2, 1e12)::numeric(14,2) as kg_vor_eingang,
       zahl(coalesce(sum(l.masse_kg) filter (where not exists (select 1 from auf a where a.id = l.id)), 0), 2, 1e12)::numeric(14,2) as kg_ohne_ziel,
       (select jsonb_agg(jsonb_build_object('charge_nr', j.charge_nr, 'kg', round(j.kg, 1), 'kg_vor_eingang', round(coalesce(j.kg_vor, 0), 1)) order by j.charge_nr)
          from je_charge j where j.sorte is not distinct from l.sorte) as verteilt_auf
  from l
 group by l.sorte;

create or replace view v_perigon_pruefung with (security_invoker = true) as
with zeile as (
  select z.id, z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_extern, z.kg_charge, z.liefer_label,
         l.id as lieferung_id, l.charge_nr, l.kg as kg_lieferung, c.sorte, sk.artikelgruppe as gruppe_charge,
         e.gruppe as gruppe_artikel, e.label as label_verkauft,
         case when upper(coalesce(z.liefer_label, '')) like 'D%' then 'D'
              when upper(coalesce(z.liefer_label, '')) ~ '^(K|CH-K)' then 'K' end as label_geliefert,
         li.extern_id like '%:rest' as rest,
         regexp_replace(z.charge_extern, '\D', '', 'g') as ziffern,
         coalesce((select x.nr from charge x where x.nr::text = regexp_replace(z.charge_extern, '\D', '', 'g')),
                  (select min(x.nr) from charge x where x.perigon_nr::text = regexp_replace(z.charge_extern, '\D', '', 'g')
                   having count(*) = 1)) as bekannt
    from ausgang_zeile z
    join lieferung_import li on li.zeile_id = z.id
    join lieferung l on l.id = li.lieferung_id
    left join charge c on c.nr = l.charge_nr
    left join sorte_kaliber sk on sk.sorte = c.sorte
   cross join lateral artikel_einordnen(z.artikel, z.preisgruppe) e
)
select 'Charge nicht zugeordnet'::text as art, z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge as kg,

       case when z.bekannt is not null
            then format('Auf dem Lieferschein steht %s; die Nummer steht an Charge %s; beim Einlesen kannte die App sie noch nicht. '
                        || 'Beim nächsten Rechnen bekommt der Lieferschein seine Charge von selbst.', z.charge_extern, z.bekannt)
            when (select count(*) from charge x where x.perigon_nr::text = z.ziffern) > 1
            then format('Auf dem Lieferschein steht die Perigon-Nummer %s; sie steht an mehreren Chargen, und der Artikel sagt nicht, '
                        || 'welche Sorte es ist. Die Datei unter Betrieb → Warenausgang neu einlesen, dort entscheidet der Artikel.', z.charge_extern)
            else format('Auf dem Lieferschein steht die Charge %s; diese Nummer steht an keiner Charge der App. Die Nummer unter Stammdaten → '
                        || 'Chargen anlegen oder bei der richtigen Charge als Perigon-Nr. eintragen; beim nächsten Rechnen bekommt der '
                        || 'Lieferschein sie von selbst.', z.charge_extern) end as befund
  from zeile z
 where z.charge_extern <> '' and z.charge_nr is null and not z.rest
union all
select 'Teil ohne Charge', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, null::int, zahl(z.kg_lieferung, 3, 1e11)::numeric(14,3),
       format('%s kg der Position haben keine Charge: Spalte S („AufPosBatchQuantity Charge") schreibt der Charge %s weniger zu, als die Position geliefert hat. Diese Kilo zählen im Warenausgang, aber bei keiner Charge — dort bleibt die Ware im Lager stehen. In Perigon die Menge je Charge nachtragen.',
              trim(to_char(z.kg_lieferung, 'FM999999990.0')), z.charge_extern)
  from zeile z
 where z.rest and z.charge_extern <> ''
union all
select 'Artikel passt nicht zur Sorte', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge,
       format('Verkauft als %s, aber die Charge %s ist %s — und %s geht als %s. Entweder steht der falsche Artikel oder die falsche Charge auf dem Lieferschein.', z.gruppe_artikel, z.charge_nr, z.sorte, z.sorte, z.gruppe_charge)
  from zeile z
 where z.gruppe_artikel is not null and z.gruppe_charge is not null
   and z.gruppe_artikel not in ('Mix', 'andere') and z.gruppe_artikel <> z.gruppe_charge
union all
select 'Als Demeter verkauft, als Knospe geliefert', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge,
       format('Verkauft zum Demeter-Preis (Preisgruppe), aber die Ware der Charge %s trägt das Lieferlabel %s — das ist Knospe.', z.charge_nr, z.liefer_label)
  from zeile z
 where z.label_verkauft = 'D' and z.label_geliefert = 'K' and not z.rest
union all
select 'Lieferung vor dem Eingang', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge,
       format('Geliefert am %s, aber die Charge %s kam laut Erntejournal erst am %s an — von ihr kann die Ware nicht sein.', to_char(z.datum, 'DD.MM.YYYY'), z.charge_nr,
              to_char(e.erst, 'DD.MM.YYYY'))
  from zeile z
  join (select charge_nr, min(eingangsdatum) as erst from palette group by charge_nr) e on e.charge_nr = z.charge_nr
 where z.datum < e.erst;

create or replace view v_perigon_produzent with (security_invoker = true) as
with gelesen as (
  select name_norm(z.produzent) as produzent, min(z.produzent) as name, c.schlag, count(*)::int as n
    from ausgang_zeile z
    join lieferung_import li on li.zeile_id = z.id
    join lieferung l on l.id = li.lieferung_id
    join charge c on c.nr = l.charge_nr
   where name_norm(z.produzent) is not null
     and (c.nr::text = regexp_replace(z.charge_extern, '\D', '', 'g')
          or c.perigon_nr::text = regexp_replace(z.charge_extern, '\D', '', 'g'))
   group by name_norm(z.produzent), c.schlag
), eindeutig as (
  select produzent, min(name) as name, min(schlag) as schlag, sum(n)::int as n
    from gelesen group by produzent having count(distinct schlag) = 1
)
select name_norm(a.alias) as produzent, a.alias as name, a.schlag, 'betrieb'::text as quelle, null::int as n_zeilen
  from schlag_alias a
union all
select e.produzent, e.name, e.schlag, 'gelernt', e.n
  from eindeutig e
 where not exists (select 1 from schlag_alias a where name_norm(a.alias) = e.produzent);

create or replace function schlag_von_produzent(p text) returns text
language sql stable security invoker set search_path = public as $$
  select coalesce(
    (select v.schlag from v_perigon_produzent v where v.produzent = name_norm(p) order by v.quelle limit 1),
    (select min(c.schlag) from charge c where name_norm(c.schlag) = name_norm(p)))
$$;

create or replace view v_stammdaten_pruefung with (security_invoker = true) as
with saison as (
  select max(c.saison) as s from charge c where exists (select 1 from palette p where p.charge_nr = c.nr)
), datei as (

  select x.nummer, x.n, x.produzent, x.gruppe, x.charge_nr,
         coalesce(pp.schlag, (select min(c.schlag) from charge c where name_norm(c.schlag) = name_norm(x.produzent))) as schlag
    from (select regexp_replace(z.charge_extern, '\D', '', 'g') as nummer, count(*)::int as n,
                 min(z.produzent) as produzent, min(e.gruppe) as gruppe, min(l.charge_nr) as charge_nr
            from ausgang_zeile z
            cross join lateral artikel_einordnen(z.artikel, z.preisgruppe) e
            left join lieferung_import li on li.zeile_id = z.id
            left join lieferung l on l.id = li.lieferung_id
           where regexp_replace(z.charge_extern, '\D', '', 'g') <> ''
           group by 1) x
    left join v_perigon_produzent pp on pp.produzent = name_norm(x.produzent)
), doppelt as (
  select c.perigon_nr, array_agg(c.nr order by c.nr) as chargen,
         jsonb_agg(jsonb_build_object('charge_nr', c.nr, 'schlag', c.schlag, 'sorte', c.sorte) order by c.nr) as liste,
         array_agg(distinct c.schlag) as schlaege
    from charge c where c.perigon_nr is not null
   group by c.perigon_nr having count(*) > 1
)
select 'perigon_doppelt'::text as pruefung, d.perigon_nr::text as schluessel, d.chargen,
       jsonb_build_object(
         'perigon_nr', d.perigon_nr, 'chargen', d.liste,
         'zeilen_mit_nummer', coalesce((select f.n from datei f where f.nummer = d.perigon_nr::text), 0),
         'verwandte', (select jsonb_agg(jsonb_build_object('nummer', f.nummer, 'n', f.n, 'produzent', f.produzent,
                                                           'gruppe', f.gruppe, 'charge_nr', f.charge_nr) order by f.nummer)
                         from datei f
                        where not exists (select 1 from charge x where x.nr::text = f.nummer or x.perigon_nr::text = f.nummer)
                          and (abs(f.nummer::numeric - d.perigon_nr) <= 2
                               or f.schlag = any (d.schlaege)))) as mehr
  from doppelt d
union all
select 'ohne_perigon_nr', c.nr::text, array[c.nr],
       jsonb_build_object('schlag', c.schlag, 'sorte', c.sorte,
                          'paletten', (select count(*) from palette p where p.charge_nr = c.nr),
                          'lieferscheine', (select count(*) from lieferung l where l.charge_nr = c.nr))
  from charge c, saison s
 where c.perigon_nr is null and c.saison = s.s
   and (exists (select 1 from palette p where p.charge_nr = c.nr) or exists (select 1 from lieferung l where l.charge_nr = c.nr))
union all
select 'schlag_zweimal', name_norm(c.schlag), array_agg(c.nr order by c.nr),
       jsonb_build_object('name', c.schlag, 'gemeint', min(a.schlag))
  from charge c join schlag_alias a on name_norm(a.alias) = name_norm(c.schlag)
 group by c.schlag
union all
select 'schlag_zweimal', name_norm(c.schlag), array_agg(c.nr order by c.nr),
       jsonb_build_object('name', min(c.schlag), 'gemeint', max(c.schlag))
  from charge c
 group by name_norm(c.schlag) having count(distinct c.schlag) > 1;

create or replace function ungereimt_kandidaten(p_nr int, p_bis date) returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_agg(k.j order by k.rang)
    from (select jsonb_build_object('charge_nr', x.charge_nr, 'schlag', x.schlag, 'sorte', x.sorte,
                                    'rest_paletten', round(x.n_rest_paletten), 'eingang_kg', round(x.eingang_kg),
                                    'geliefert_kg', round(coalesce(x.geliefert_kg, 0)), 'eingang_von', x.eingang_von,
                                    'gleicher_schlag', x.schlag = c.schlag, 'gleiche_sorte', x.sorte = c.sorte) as j,
                 row_number() over (order by (x.schlag = c.schlag) desc, (x.sorte = c.sorte) desc, x.n_rest_paletten desc, x.charge_nr) as rang
            from charge c
            join sorte_kaliber sk on sk.sorte = c.sorte
            join erg_charge x on x.charge_nr <> c.nr
            join sorte_kaliber sx on sx.sorte = x.sorte
           where c.nr = p_nr and sx.artikelgruppe = sk.artikelgruppe
             and x.n_rest_paletten >= 1 and x.eingang_kg > 0
             and coalesce(x.geliefert_kg, 0) <= 0.5 * x.eingang_kg
             and (p_bis is null or x.eingang_von <= p_bis)) k
   where k.rang <= 4
$$;

create or replace view v_ungereimtheit with (security_invoker = true) as
with lief as (
  select l.charge_nr, l.datum, l.masse_kg from v_lieferung_masse l
   where l.charge_nr is not null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge') and l.datum <= heute()
), eingang as (
  select charge_nr, min(eingangsdatum) as erst, count(*)::int as n from palette group by charge_nr
)
select 'ohne_eingang'::text as art, c.nr as charge_nr, c.sorte, c.schlag,
       zahl(sum(l.masse_kg), 2, 1e12)::numeric(14,2) as kg, count(*)::int as n, min(l.datum) as von, max(l.datum) as bis,
       jsonb_build_object('kandidaten', ungereimt_kandidaten(c.nr, max(l.datum))) as mehr
  from lief l join charge c on c.nr = l.charge_nr
 where not exists (select 1 from eingang e where e.charge_nr = l.charge_nr)
 group by c.nr, c.sorte, c.schlag
union all
select 'vor_eingang', c.nr, c.sorte, c.schlag,
       zahl(sum(l.masse_kg), 2, 1e12)::numeric(14,2), count(*)::int, min(l.datum), max(l.datum),
       jsonb_build_object('erster_eingang', e.erst, 'kandidaten', ungereimt_kandidaten(c.nr, max(l.datum)))
  from lief l join eingang e on e.charge_nr = l.charge_nr join charge c on c.nr = l.charge_nr
 where l.datum < e.erst
 group by c.nr, c.sorte, c.schlag, e.erst
union all
select 'ueberzaehlung', b.charge_nr, b.sorte, b.schlag,
       zahl(b.ueberzaehlung_kg, 2, 1e12)::numeric(14,2), b.n_lieferungen, null::date, null::date,
       jsonb_build_object('geliefert_kg', round(b.geliefert_kg), 'eingang_kg', round(b.eingang_kg), 'ausgelagert_kg', round(b.ausgelagert_kg),
                          'eingang_von', b.eingang_von, 'eingang_bis', b.eingang_bis,
                          'kandidaten', ungereimt_kandidaten(b.charge_nr, (select max(l.datum) from lief l where l.charge_nr = b.charge_nr)))

  from erg_charge b where b.ueberzaehlung_kg > greatest(100, 0.03 * b.eingang_kg)
union all
select 'ohne_charge', null::int, o.sorte, null::text,
       o.kg, o.n_lieferungen, o.erste, o.letzte,
       jsonb_build_object('kg_vor_eingang', o.kg_vor_eingang, 'kg_ohne_ziel', o.kg_ohne_ziel, 'verteilt_auf', o.verteilt_auf)
  from v_ohne_charge o
union all
select case z.stand when 'angewandt' then 'umgebucht' else 'vorschlag' end, z.nach_charge_nr, c.sorte, c.schlag,
       zahl(sum(vp.netto_kg), 2, 1e12)::numeric(14,2), count(*)::int, min(p.eingangsdatum), max(p.eingangsdatum),
       jsonb_build_object('von_charge_nr', z.von_charge_nr, 'auftrag_id', z.auftrag_id,
                          'grund', min(z.grund) filter (where z.art = 'zettel'),
                          'paletten', jsonb_agg(z.palette_id order by z.palette_id),
                          'von_betriebsleiter', bool_or(z.geaendert_ts is not null))
  from palette_zuordnung z
  join palette p on p.id = z.palette_id
  join v_palette vp on vp.id = z.palette_id
  join charge c on c.nr = z.nach_charge_nr
 where z.stand in ('angewandt', 'vorschlag')
 group by z.stand, z.nach_charge_nr, z.von_charge_nr, z.auftrag_id, c.sorte, c.schlag
union all
select 'nachgeordnet', n.charge_nr, c.sorte, c.schlag,
       zahl(sum(l.masse_kg), 2, 1e12)::numeric(14,2), count(*)::int, min(l.datum), max(l.datum),
       jsonb_build_object('nummern', jsonb_agg(distinct n.nummer), 'produzent', min(n.produzent), 'grund', min(n.grund),
                          'perigon_nr', c.perigon_nr)
  from lieferung_nachordnung n
  join v_lieferung_masse l on l.id = n.lieferung_id
  join charge c on c.nr = n.charge_nr
 where n.weg = 'produzent'

   and n.nummer is distinct from c.perigon_nr::text and n.nummer is distinct from c.nr::text
 group by n.charge_nr, c.sorte, c.schlag, c.perigon_nr
union all
select 'stammdaten', s.chargen[1], c.sorte, c.schlag, zahl(null::numeric, 2, 1e12)::numeric(14,2), cardinality(s.chargen), null::date, null::date,
       s.mehr || jsonb_build_object('pruefung', s.pruefung, 'chargen_nr', to_jsonb(s.chargen))
  from v_stammdaten_pruefung s
  join charge c on c.nr = s.chargen[1];

-- aus 0124_was_der_ausweis_nicht_weiss_sagt_er.sql

create or replace view v_lager_ausweis with (security_invoker = true) as
with hagel_lager as (
  select k.charge_nr, max(k.hagel) filter (where k.portion = 'lager' and k.m0 > 0) as h,
         sum(case when k.portion <> 'lager' and k.hagel > 0 and k.hagel < 1 then k.m2 * k.hagel / (1 - k.hagel) else 0 end) as hagel_ausgelagert
    from mv_kaskade k group by k.charge_nr
), marge_charge as (
  select m.charge_nr,
         sum(m.zuviel_je_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)
           / nullif(sum(m.soll_kg_pro_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null), 0) as a,
         sum(m.n_wiegungen) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)::int as n_kg,
         bool_or(m.kistensystem = 'stueck') as stueck
    from erg_marge_charge m group by m.charge_nr
), marge_sorte as (
  select m.sorte,
         sum(m.zuviel_je_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)
           / nullif(sum(m.soll_kg_pro_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null), 0) as a,
         sum(m.n_wiegungen) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)::int as n_kg,
         bool_or(m.kistensystem = 'stueck') as stueck
    from erg_marge_charge m group by m.sorte
), ohne_system as (

  select k.charge_nr, count(*)::int as n
    from v_ausgang_kennzahl k
   where k.kistensystem is null
      or (k.kistensystem = 'kiste_ab' and coalesce(k.soll_kg_pro_kiste, 0) <= 0)
   group by k.charge_nr
), basis as (
  select c.charge_nr, c.sorte, c.schlag, c.n_rest_paletten as paletten, c.lager_kg as liegend_kg,
         p.lager_kg, p.alter_tage, p.verdunstet_kg, p.verdunstet_je_tag_kg, p.faul_kg as faul_mit_hagel_kg,
         p.gute_ware_kg, p.klein_kg, p.gross_kg, p.fax_kg, p.verkaufsfaehig_kg,
         p.r_bekannt, p.f_bekannt, p.kanal_bekannt, p.fax_bekannt,
         coalesce(hl.h, 0) as h, coalesce(hl.hagel_ausgelagert, 0) as hagel_ausgelagert,
         c.verlust_heute_kg,
         case when mc.a is not null then mc.a
              when mc.stueck then 0
              when ms.a is not null then ms.a
              when ms.stueck then 0 end as marge_anteil,
         case when mc.a is not null then format('gewogen: %s %s dieser Charge', mc.n_kg, case when mc.n_kg = 1 then 'Palette' else 'Paletten' end)
              when mc.stueck then 'Stück-Kisten: ohne Sollgewicht keine Überfüllung'
              when ms.a is not null then format('Sorte %s: %s gewogene %s', c.sorte, ms.n_kg, case when ms.n_kg = 1 then 'Palette' else 'Paletten' end)
              when ms.stueck then 'Stück-Kisten: ohne Sollgewicht keine Überfüllung'
              when os.n > 0 then format('%s gewogene %s, aber die Arbeit hat kein Kistensystem oder kein Sollgewicht — keine Überfüllung zu rechnen (Messungen → Arbeiten → korrigieren)',
                                        os.n, case when os.n = 1 then 'Palette' else 'Paletten' end)
              else 'nicht gewogen' end as marge_quelle,
         coalesce(os.n, 0) as n_ohne_system
    from erg_charge c
    left join erg_prognose p on p.gruppe = 'charge' and p.schluessel = c.charge_nr::text and p.h = 0
    left join hagel_lager hl on hl.charge_nr = c.charge_nr
    left join marge_charge mc on mc.charge_nr = c.charge_nr
    left join marge_sorte ms on ms.sorte = c.sorte
    left join ohne_system os on os.charge_nr = c.charge_nr
), mit_hagel as (
  select b.*,
         case when b.gute_ware_kg is null then null
              when b.h <= 0 then 0::numeric
              when b.h >= 1 then null
              else b.gute_ware_kg * b.h / (1 - b.h) end as unique_kg
    from basis b
), artikel as (

  select t.charge_nr,
         sum(t.kg) filter (where t.groesse in ('darunter', 'darueber', 'dazwischen')) as keinen_artikel_kg,
         sum(t.kg) filter (where t.groesse = 'lose' and t.artikelgruppe is null) as gruppe_offen_kg,
         sum(t.kg) filter (where t.groesse = 'ohne Verteilung') as groesse_offen_kg
    from artikel_lager_teile(0) t
   group by t.charge_nr
), verkaufbar as (
  select m.*,

         case when m.verkaufsfaehig_kg is null then null
              when m.verkaufsfaehig_kg <= 0 then 0::numeric
              when coalesce(a.groesse_offen_kg, 0) > 0 then null
              else coalesce(a.keinen_artikel_kg, 0) end as keinen_artikel_kg,
         case when m.verkaufsfaehig_kg is null then null
              when m.verkaufsfaehig_kg > 0 then coalesce(a.groesse_offen_kg, 0) else 0::numeric end as groesse_offen_kg,
         case when m.verkaufsfaehig_kg is null then null
              when m.verkaufsfaehig_kg > 0 then coalesce(a.gruppe_offen_kg, 0) else 0::numeric end as gruppe_offen_kg
    from mit_hagel m
    left join artikel a on a.charge_nr = m.charge_nr
), netto as (
  select v.*,
         v.verkaufsfaehig_kg - coalesce(v.keinen_artikel_kg, 0) as als_artikel_kg,
         (v.verkaufsfaehig_kg - coalesce(v.keinen_artikel_kg, 0)) * v.marge_anteil / (1 + v.marge_anteil) as ueberfuellung_kg
    from verkaufbar v
)
select m.charge_nr, m.sorte, m.schlag,
       m.paletten,
       zahl(coalesce(m.lager_kg, m.liegend_kg), 2, 1e12)::numeric(14,2) as eingang_kg,
       m.alter_tage,
       zahl(m.verdunstet_kg, 2, 1e12)::numeric(14,2) as verdunstet_kg,
       zahl(m.verdunstet_je_tag_kg, 2, 1e12)::numeric(14,2) as verdunstet_je_tag_kg,

       zahl(case when m.h >= 1 then null else m.faul_mit_hagel_kg - coalesce(m.unique_kg, 0) end, 2, 1e12)::numeric(14,2) as faul_kg,
       zahl(m.unique_kg, 2, 1e12)::numeric(14,2) as unique_kg,
       zahl(nullif(m.h, 0), 4, 1e1)::numeric(5,4) as hagel_anteil,
       zahl(m.klein_kg, 2, 1e12)::numeric(14,2) as zu_klein_kg,
       zahl(m.gross_kg, 2, 1e12)::numeric(14,2) as zu_gross_kg,
       zahl(m.fax_kg, 2, 1e12)::numeric(14,2) as fax_kg,
       zahl(m.verkaufsfaehig_kg, 2, 1e12)::numeric(14,2) as verkaufsfaehig_kg,
       zahl(m.marge_anteil, 5, 1e3)::numeric(8,5) as marge_anteil,
       m.marge_quelle,
       zahl(m.verkaufsfaehig_kg * m.marge_anteil / (1 + m.marge_anteil), 2, 1e12)::numeric(14,2) as marge_kg,
       zahl(m.verkaufsfaehig_kg / (1 + m.marge_anteil), 2, 1e12)::numeric(14,2) as verrechenbar_kg,
       zahl(case when m.h >= 1 then null else m.hagel_ausgelagert + coalesce(m.unique_kg, 0) end, 2, 1e12)::numeric(14,2) as hagel_bis_heute_kg,
       coalesce(m.r_bekannt, false) as r_bekannt, coalesce(m.f_bekannt, false) as f_bekannt,
       coalesce(m.kanal_bekannt, false) as kanal_bekannt, coalesce(m.fax_bekannt, false) as fax_bekannt,

       zahl(m.keinen_artikel_kg, 2, 1e12)::numeric(14,2) as keinen_artikel_kg,
       zahl(m.groesse_offen_kg, 2, 1e12)::numeric(14,2) as groesse_offen_kg,
       zahl(m.ueberfuellung_kg, 2, 1e12)::numeric(14,2) as ueberfuellung_kg,
       zahl(case when m.h >= 1 then null
                 else m.als_artikel_kg - coalesce(m.ueberfuellung_kg, 0) + coalesce(m.unique_kg, 0) end, 2, 1e12)::numeric(14,2) as verkaufbar_kg,
       nullif(concat_ws(', ',
         case when m.h >= 1 then 'Hagel 100 %: Unique und Faules nicht trennbar' end,
         case when m.verkaufsfaehig_kg > 0 and m.marge_anteil is null then
                case when m.n_ohne_system > 0 then 'Überfüllung offen: Paletten gewogen, aber die Arbeit hat kein Kistensystem oder kein Sollgewicht'
                     else 'Überfüllung nicht gewogen' end end,
         case when m.groesse_offen_kg > 0 then 'Grösse offen (keine Sortier-CSV)' end,
         case when m.gruppe_offen_kg > 0 then 'Artikelgruppe fehlt (Stammdaten → Sorten)' end), '') as verkaufbar_offen,

       zahl(m.gruppe_offen_kg, 2, 1e12)::numeric(14,2) as gruppe_offen_kg
  from netto m;

create or replace view v_charge_spur with (security_invoker = true) as
with journal as (
  select coalesce(p.charge_nr_journal, p.charge_nr) as nr, count(*)::int as n,
         sum(vp.netto_kg) as kg, min(p.eingangsdatum) as von, max(p.eingangsdatum) as bis
    from palette p join v_palette vp on vp.id = p.id
   group by 1
), jetzt as (
  select p.charge_nr as nr, count(*)::int as n, sum(vp.netto_kg) as kg
    from palette p join v_palette vp on vp.id = p.id
   group by 1
), zuordnung as (
  select z.von_charge_nr, z.nach_charge_nr, z.stand, count(*)::int as n, sum(vp.netto_kg) as kg
    from palette_zuordnung z join v_palette vp on vp.id = z.palette_id
   where z.stand in ('angewandt', 'vorschlag')
   group by 1, 2, 3
), arbeit as (
  select a.charge_nr as nr, count(*)::int as n,
         min((a.start_ts at time zone 'Europe/Zurich')::date) as von,
         max((a.start_ts at time zone 'Europe/Zurich')::date) as bis,
         jsonb_agg(jsonb_build_object('id', a.id, 'datum', (a.start_ts at time zone 'Europe/Zurich')::date,
                                      'station', a.station, 'zettel', (select count(*) from auftrag_palette ap where ap.auftrag_id = a.id))
                   order by a.start_ts) as liste
    from auftrag a
   where a.abgebrochen_ts is null
   group by a.charge_nr
), lief as (
  select l.charge_nr as nr, count(*)::int as n, sum(l.masse_kg) as kg, min(l.datum) as von, max(l.datum) as bis
    from v_lieferung_masse l
   where l.charge_nr is not null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge') and l.datum <= heute()
   group by l.charge_nr
), artikel as (
  select l.charge_nr as nr, (artikel_einordnen(z.artikel, z.preisgruppe)).gruppe as gruppe, sum(l.masse_kg) as kg
    from v_lieferung_masse l
    join lieferung_import li on li.lieferung_id = l.id
    join ausgang_zeile z on z.id = li.zeile_id
   where l.charge_nr is not null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge') and l.datum <= heute()
   group by 1, 2
), nach_artikel as (

  select x.nr, coalesce(x.gruppe, 'andere') as gruppe, x.kg from artikel x
  union all
  select f.nr, 'ohne Perigon-Zeile', f.kg - coalesce(a.kg, 0)
    from lief f
    left join (select x.nr, sum(x.kg) as kg from artikel x group by x.nr) a on a.nr = f.nr
   where f.kg - coalesce(a.kg, 0) > 0.5
), nach as (
  select n.charge_nr as nr, n.weg, count(*)::int as n, sum(l.masse_kg) as kg
    from lieferung_nachordnung n join v_lieferung_masse l on l.id = n.lieferung_id
   group by 1, 2
)
select c.nr as charge_nr, c.schlag, c.sorte, sk.artikelgruppe,
       coalesce(j.n, 0) as journal_paletten, zahl(j.kg, 2, 1e12)::numeric(14,2) as journal_kg, j.von as journal_von, j.bis as journal_bis,
       coalesce(t.n, 0) as paletten, zahl(t.kg, 2, 1e12)::numeric(14,2) as eingang_kg,
       (select jsonb_agg(jsonb_build_object('charge_nr', z.nach_charge_nr, 'stand', z.stand, 'paletten', z.n, 'kg', round(z.kg))
                         order by z.stand, z.nach_charge_nr)
          from zuordnung z where z.von_charge_nr = c.nr) as weg,
       (select jsonb_agg(jsonb_build_object('charge_nr', z.von_charge_nr, 'stand', z.stand, 'paletten', z.n, 'kg', round(z.kg))
                         order by z.stand, z.von_charge_nr)
          from zuordnung z where z.nach_charge_nr = c.nr) as her,
       coalesce(a.n, 0) as arbeiten, a.von as arbeit_von, a.bis as arbeit_bis, a.liste as arbeit_liste,
       coalesce(f.n, 0) as lieferscheine, zahl(f.kg, 2, 1e12)::numeric(14,2) as geliefert_kg, f.von as lief_von, f.bis as lief_bis,
       (select jsonb_agg(jsonb_build_object('gruppe', x.gruppe, 'kg', round(x.kg)) order by x.kg desc)
          from nach_artikel x where x.nr = c.nr) as nach_artikel,
       (select jsonb_agg(jsonb_build_object('weg', x.weg, 'n', x.n, 'kg', round(x.kg)) order by x.weg)
          from nach x where x.nr = c.nr) as nachgeordnet,
       zahl(b.n_rest_paletten, 1, 1e6)::numeric(7,1) as rest_paletten
  from charge c
  left join sorte_kaliber sk on sk.sorte = c.sorte
  left join journal j on j.nr = c.nr
  left join jetzt t on t.nr = c.nr
  left join arbeit a on a.nr = c.nr
  left join lief f on f.nr = c.nr
  left join erg_charge b on b.charge_nr = c.nr
 where j.n is not null or t.n is not null or a.n is not null or f.n is not null;

-- ---------------------------------------------------------------------
-- Beschreibungen, Leserechte und Indizes
-- ---------------------------------------------------------------------
-- Nach einem "drop" ist beides weg: Was eine Ansicht bedeutet und wer sie
-- lesen darf. Beides wird hier wieder gesetzt.
-- ---------------------------------------------------------------------


grant select on all tables in schema public to authenticated;

grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

grant select on v_plausibilitaet to authenticated;

grant select on v_wiegung_kennzahl to authenticated;

grant select on v_ausgang_kennzahl to authenticated;

create unique index if not exists mv_sortier_lauf_masse_pk on mv_sortier_lauf_masse (lauf_id);
create index if not exists mv_sortier_lauf_masse_charge on mv_sortier_lauf_masse (charge_nr);

create unique index if not exists mv_auftrag_masse_pk on mv_auftrag_masse (auftrag_id);
create index if not exists mv_auftrag_masse_charge on mv_auftrag_masse (charge_nr);
create index if not exists mv_auftrag_masse_station on mv_auftrag_masse (station) where eingang_netto_kg is not null;
grant select on mv_sortier_lauf_masse, mv_auftrag_masse, mv_kaskade,
                mv_kaliber_verteilung to authenticated;

grant select on v_koeff_roh_verdunstung, v_koeff_roh_kaliber,
               v_koeff_verdunstung_geschaetzt, v_koeff_kaliber_geschaetzt to authenticated;

grant select on v_koeff_unsicherheit to authenticated;

grant select on v_kaskade, v_hochrechnung, v_verlust_ranking,
               v_marge_buch, v_massenbilanz to authenticated;

comment on view v_charge_rueckgrat is
  'eingang_netto_kg ist auf alle Paletten der Charge hochgerechnet; '
  'eingang_netto_gemessen_kg ist die Summe der Paletten mit bekannter Tara. '
  'Weichen die beiden ab, fehlt bei n_paletten − n_paletten_mit_netto '
  'Paletten die Gebindeart.';

grant select on v_charge_rueckgrat, v_hochrechnung_basis to authenticated;
grant select on v_verlust_ranking, v_marge_buch to authenticated;

grant select on v_auftrag_masse, v_hochrechnung_basis to authenticated;

grant select on v_schimmel_punkte to authenticated;

create unique index if not exists mv_sortier_eingang_pk on mv_sortier_eingang (charge_nr);

grant select on v_palox_stand to authenticated;

comment on view v_lieferung_masse is
  'Lieferungen in Kilo. Kistenangaben werden über das gemessene Kilo je Kiste '
  'umgerechnet; masse_fehler_kg sagt, wie unsicher diese Umrechnung ist.';

grant select on lieferung, ausgang_ziel, v_lieferung_masse to authenticated;

grant select on v_saisonbilanz to authenticated;

grant select on v_hochrechnung_basis, v_massenbilanz to authenticated;
grant select on v_palox_stand to authenticated;

grant select on v_naechste_charge to authenticated;

-- aus 0035_nur_angemeldete.sql

revoke execute on all functions in schema public from public;

grant select on v_palox_stand, v_schimmel_menge to authenticated;

grant select on v_kaskade, v_hochrechnung, v_verlust_ranking, v_marge_buch,
               v_massenbilanz, v_saisonbilanz, v_plausibilitaet,
               v_hochrechnung_basis, v_koeff_ueberfuellung to authenticated;
grant select on mv_kaliber_verteilung, v_kaliber_verteilung, v_ausgang_kennzahl to authenticated;
grant select on v_auftrag_angabe to authenticated;

grant select on v_marge_buch to authenticated;
grant select on v_koeff_gebinde to authenticated;
grant select on v_auftrag_gebinde_masse to authenticated;

grant select on v_plausibilitaet to authenticated;
grant select on v_marge_buch to authenticated;
grant select on v_koeff_ueberfuellung to authenticated;
grant select on v_saisonbilanz to authenticated;

grant select on v_plausibilitaet to authenticated;
comment on view v_gewichtsverteilung is
  'Kürbisse je 25-g-Stufe aus den Sortier-CSVs, je Charge (mit Sorte und Schlag). '
  'Eine Aussage über den Anbau, nicht über das Lager.';
grant select on v_gewichtsverteilung to authenticated;
grant select on v_verarbeitung_alter to authenticated;
grant select on v_durchsatz to authenticated;
grant select on v_datenqualitaet to authenticated;
grant select on v_ausgang_artikel_vorschlag to authenticated;
grant select on v_ausgang_pruef to authenticated;
grant select on v_ausgang_lage to authenticated;
grant select on v_fax_beobachtung to authenticated;
grant select on v_koeff_fax to authenticated;
grant select on v_charge_kohorte to authenticated;
grant select on v_kohorte_anteil to authenticated;

grant select on v_kaskade, v_hochrechnung, v_verlust_ranking, v_marge_buch,
               v_massenbilanz, v_saisonbilanz, v_plausibilitaet, v_datenqualitaet,
               v_hochrechnung_basis, v_naechste_charge, v_koeff_gebinde,
               v_auftrag_masse, v_schimmel_beobachtung, v_schimmel_punkte,
               v_koeff_roh_kaliber, v_ausgang_artikel_vorschlag to authenticated;
grant select on v_plausibilitaet_0054_zusatz to authenticated;

grant select on v_verdunstung_messung, v_koeff_verdunstung, v_schimmel_beobachtung,
                v_plausibilitaet to authenticated;
grant select on v_ausschuss_beobachtung to authenticated;
grant select on v_hochrechnung to authenticated;
grant select on v_saisonbilanz to authenticated;
grant select on v_marge_buch to authenticated;
comment on view v_auftrag_gebinde_masse is 'Verarbeitete Menge einer Wascharbeit aus gezählten Kisten mal gemessenem Kistengewicht. kg ist NULL, solange das Kaliber nie am Sortieren gezählt wurde — dann fehlt der Nenner weiterhin. Index −2 (eigenes Kaliber) findet sein Gewicht über die Bandgrenzen in einer Fassung der Sorte (0054).';
grant select on v_auftrag_gebinde_masse to authenticated;
grant select on v_auftrag_masse to authenticated;
grant select on v_auftrag_palette_masse to authenticated;
comment on view v_ausgang_artikel_vorschlag is 'Jeder Artikel aus den Importzeilen mit Vorschlag und Bestätigung. Die vorgeschlagene Sorte stammt aus den Zeilen, die eine eigene Chargennummer tragen — beobachtet, nicht geraten.';
grant select on v_ausgang_artikel_vorschlag to authenticated;
grant select on v_ausgang_kennzahl to authenticated;
comment on view v_ausgang_lage is 'Je Quelle: wie viel eingelesen ist, bis wann, und wie viele Artikel noch auf ihre Bestätigung warten.';
grant select on v_ausgang_lage to authenticated;
comment on view v_ausgang_pruef is 'Kürbis-Positionen, deren übernommene Lieferungen nicht die Masse der Datei ergeben. Leer ist der Normalfall; jede Zeile hier ist ein Kilo zu viel oder zu wenig. Eine vergessene Position steht hier mit ihrer vollen Masse.';
grant select on v_ausgang_pruef to authenticated;
comment on view v_ausschuss_beobachtung is 'Zu klein und zu gross je Arbeit gegen ihre Basis: am Band die CSV-Masse, von Hand der Eingang abzüglich Verdunstung (gedeckelte Rate, 0057) und Schimmel.';
grant select on v_ausschuss_beobachtung to authenticated;
grant select on v_charge_kohorte to authenticated;
comment on view v_durchsatz is 'Abgeschlossene Arbeiten mit Dauer, Masse und Kilo je Stunde. kg_pro_h ist NULL, wenn die Masse unbekannt ist oder die Arbeit kürzer als eine Viertelstunde war.';
grant select on v_durchsatz to authenticated;
grant select on v_fax_beobachtung to authenticated;
grant select on v_hochrechnung to authenticated;
grant select on v_koeff_gebinde to authenticated;
comment on view v_koeff_roh_kaliber is 'Koeffizienten-Rohwerte in einheitlicher Form: Anteil, die Masse, die er vertritt, und die Charge, aus der er stammt. ausschuss, nebenkanal, fax.';
grant select on v_koeff_roh_kaliber to authenticated;
comment on view v_koeff_ueberfuellung is 'Überschuss je Kiste über dem Sollgewicht, aus den Wägungen fertiger Paletten. Gezählt werden nur Wägungen, aus denen sich überhaupt ein Überschuss ergibt — Arbeiten nach Kaliber haben kein Sollgewicht und zählen nicht mit.';
grant select on v_koeff_ueberfuellung to authenticated;
grant select on v_kohorte_anteil to authenticated;
grant select on v_massenbilanz to authenticated;
grant select on v_naechste_charge to authenticated;
comment on view v_schimmel_beobachtung is 'Schimmel je Arbeit gegen die Masse, die am Tag der Arbeit noch da war: Eingang abzüglich Verdunstung mit der gedeckelten Rate (0056). Fax-Faules bleibt beobachtbar, geht aber nicht in die Verderbskurve.';
grant select on v_schimmel_beobachtung to authenticated;
grant select on v_verarbeitung_alter to authenticated;
grant select on v_verdunstung_messung to authenticated;
grant select on v_wiegung_kennzahl to authenticated;
comment on view v_ausgang_kennzahl is
  'Je fertiger Palette: Kilo je Kiste, der Überschuss über das Sollgewicht (nur '
  'Kiste ab x kg — sonst NULL) und bei Stück-Kisten die Erwartung je Kiste aus '
  'dem mittleren Stückgewicht des Kalibers in der Sortier-CSV (0060).';
grant select on v_koeff_palette_netto to authenticated;
comment on view v_charge_kohorte is
  'Je Charge und Eingangstag: wie viele Paletten kamen (eingang_kg), wie viele '
  'davon in der App mit diesem Zetteldatum gezählt wurden (n_verarbeitet — '
  'punktuell, keine Menge). Die Kaskade verteilt den Bestand nach eingang_kg (0060).';
comment on view v_kohorte_anteil is
  'Der Anteil jedes Eingangstags am Eingang der Charge — und damit am Bestand '
  'und an jeder Lieferung: es gibt kein Zuerst-rein-zuerst-raus, und die App '
  'weiss nicht, welche Palette gegangen ist (0060).';
grant select on v_lieferung_kohorte to authenticated;
grant select on v_kaskade_basis to authenticated;
grant select on mv_kaskade to authenticated;
grant select on v_kaskade to authenticated;
grant select on v_hochrechnung_basis to authenticated;
grant select on mv_hochrechnung to authenticated;
grant select on v_hochrechnung to authenticated;
grant select on v_verlust_ranking to authenticated;
grant select on v_saisonbilanz to authenticated;
grant select on v_marge_buch to authenticated;
grant select on v_massenbilanz to authenticated;
grant select on v_naechste_charge to authenticated;
comment on view v_fax_beobachtung is
  'Je Fax-Arbeit: die Masse (Paletten × gemessene Palettenmasse, oder gezählte '
  'Kisten), das gewogene Faule und sein Anteil an dem, was durch die Hände ging. '
  'Dazu die Tage seit dem Waschen, wenn der Vorarbeiter sie kannte (0060).';
grant select on v_kontrolle_vorschlag to authenticated;
grant select on v_auftrag_wasch_paletten to authenticated;
comment on view v_kaskade_basis is
  'Eingang je Charge (vollständig, aus dem Erntejournal) und die Gegenproben aus '
  'den erfassten Arbeiten. stichtag ist seit 0061 heute(): die Ware im Haus altert '
  'bis heute, nicht bis zum Saisonende; saison_ende ist nur der Horizont der Prognose.';
grant select on erg_verlauf to authenticated;
grant select on v_verlust_je_gruppe to authenticated;
grant select on erg_verlust to authenticated;
comment on function verlust_ranking(text, text, int) is
  'Alle Ströme mit Bereich, wahlweise je Charge, Sorte oder Schlag — aus erg_verlust '
  'gelesen, nicht gerechnet (0061). Eine Kombination der Filter gibt es nicht mehr.';
revoke all on function verlust_ranking(text, text, int) from public;
grant execute on function verlust_ranking(text, text, int) to authenticated;
grant select on v_verlust_ranking to authenticated;
comment on view v_verkauf_lieferung is
  'Jede importierte Verkaufslieferung mit dem Kistensystem aus der Datei (Einheit × '
  'Gebindeinhalt): Kiste ab x kg, Stück je Kiste mit Nenngewicht, oder unbekannt. '
  'kisten aus der Chargenzeile (zeile), dem Rest der Position (rest) oder anteilig '
  'an der Position (anteil). Von Hand erfasste Lieferungen stehen nicht hier (0061).';
grant select on v_verkauf_lieferung to authenticated;
grant select on v_ueberfuellung_verkauf to authenticated;
grant select on erg_ueberfuellung to authenticated;
grant select on erg_charge to authenticated;
grant select on v_kontrolle_vorschlag to authenticated;
grant select on v_saisonbilanz to authenticated;
grant select on v_marge_buch to authenticated;
grant select on v_plausibilitaet_0054_zusatz to authenticated;

create index if not exists erg_gewichte_sorte     on erg_gewichte (sorte);
create index if not exists erg_ausgang_ts         on erg_ausgang (ts);
create index if not exists erg_lieferung_datum    on erg_lieferung (datum);
create index if not exists erg_kohorte_charge     on erg_kohorte (charge_nr, eingangsdatum);
create index if not exists erg_punkte_charge      on erg_punkte (charge_nr);
create index if not exists erg_wiegung_ts         on erg_wiegung (wiege_ts);
create index if not exists erg_fax_start          on erg_fax (start_ts);
create index if not exists erg_durchsatz_start    on erg_durchsatz (start_ts);
create index if not exists erg_verarbeitung_tag   on erg_verarbeitung_alter (tag);
create index if not exists erg_verlauf_woche      on erg_verlauf (woche);
grant select on v_lieferung_kohorte to authenticated;
grant select on mv_kaskade to authenticated;
grant select on v_kaskade to authenticated;
grant select on mv_hochrechnung to authenticated;
grant select on v_hochrechnung to authenticated;

grant select on v_hochrechnung_basis to authenticated;
grant select on erg_charge to authenticated;
grant select on v_verlust_je_gruppe to authenticated;
grant select on erg_verlust to authenticated;
grant select on v_marge_buch to authenticated;
grant select on v_massenbilanz to authenticated;

grant select on v_naechste_charge to authenticated;
grant select on v_kontrolle_vorschlag to authenticated;
grant select on v_saisonbilanz to authenticated;

grant select on v_saisonbilanz to authenticated;
grant select on erg_verlauf to authenticated;
grant select on erg_verlauf to authenticated;
grant select on v_wiegung_kennzahl to authenticated;
grant select on v_plausibilitaet_0054_zusatz to authenticated;

comment on view v_verlust_ranking is
  'Alle Ströme der Kaskade für eine Gruppe, absteigend nach Masse — nicht nur '
  'Verlust: buch sagt, was es ist (verlust = echter Verlust, marge = anderer '
  'Kanal, feld = nicht lagerbedingt). Nur für Diagnose und SQL-Editor; die App '
  'liest erg_verlust. Wer über alle Zeilen summiert, summiert Äpfel und Birnen.';

-- aus 0063_jede_sicht_sagt_was_sie_ist.sql

revoke execute on all functions in schema public from public;

comment on view v_auftrag_angabe is
  'Die freien Angaben zu einer Arbeit (Palox-Stand, Kistensystem, Notizen) '
  'als Schlüssel-Wert-Paare, je Arbeit eine Zeile pro Angabe.';

comment on view v_sortier_lauf_masse is
  'Je Sortierlauf aus der Waage-Datei: wie viele Kürbisse mit welcher Masse '
  'in welchen Kanal gingen — Kaliber (verkaufsfähig), zu klein, Nebenkanal. '
  'Alle Massen in kg, gewogen, nicht gerechnet.';

comment on materialized view mv_sortier_lauf_masse is
  'v_sortier_lauf_masse, gespeichert. Inhaltlich gleich; erneuert von '
  'auswertung_schritt(1).';

comment on materialized view mv_sortier_eingang is
  'Je Charge der früheste Sortiertag als Tage seit 1970 — die Rechengrösse '
  'für das Alter beim Verarbeiten. Nur eine Hilfsgrösse, keine Kennzahl.';

comment on view v_datenlage is
  'Je Charge: wie viel überhaupt erfasst ist — Paletten, davon mit bekanntem '
  'Netto, Wiegungen, Schimmelmessungen, Sortierläufe, Arbeiten. Die Zahlen '
  'sagen, wie belastbar alles andere zu dieser Charge ist.';

comment on materialized view mv_auftrag_masse is
  'Je Arbeit die Eingangsmasse und woher sie kommt (masse_quelle: gewogen, '
  'aus Paletten gerechnet oder geschätzt), dazu Station, Dauer und '
  'Lagertage. Erneuert von auswertung_schritt(1).';

comment on view v_koeff_roh_verdunstung is
  'Die einzelnen Verdunstungsmessungen, bevor gemittelt wird: je Charge ein '
  'Anteil und sein Gewicht in der Mittelung. Die Rohdaten zu '
  'v_koeff_verdunstung — hier steht, worauf der Koeffizient beruht.';
comment on view v_palette is
  'Jede Eingangspalette mit ihrem Nettogewicht: brutto − Kisten × Kistentara − '
  'Palettentara. netto_kg ist NULL, sobald eine der drei Angaben fehlt (0064) — '
  'eine fehlende Kistenzahl heisst nicht „null Kisten". Wie viele Paletten einer '
  'Charge ein Netto haben, steht als n_paletten_mit_netto in v_kaskade_basis.';
grant select on v_verdunstung_messung to authenticated;
grant select on v_wiegung_kennzahl to authenticated;
grant select on v_plausibilitaet_0064_zusatz to authenticated;
comment on view v_lieferung_kohorte is
  'Gelieferte Masse je Charge, Eingangstag und Buch (verkauf, marge, verlust), '
  'mit dem massegewichteten Alter am Liefertag; nur Lieferungen bis heute(). '
  'Grundlage der Rückrechnung in der Kaskade. 0065: das dritte Buch ist dabei — '
  'was in den Kompost ging, hat den Betrieb verlassen und gehört aus dem Lager.';
grant select on v_lieferung_kohorte to authenticated;
grant select on mv_kaskade to authenticated;
grant select on v_hochrechnung_basis to authenticated;
grant select on v_kaskade to authenticated;
grant select on v_hochrechnung to authenticated;
grant select on v_kontrolle_vorschlag to authenticated;
grant select on v_massenbilanz to authenticated;
grant select on v_naechste_charge to authenticated;
grant select on v_plausibilitaet_0064_zusatz to authenticated;
grant select on v_plausibilitaet_0054_zusatz to authenticated;
grant select on v_plausibilitaet to authenticated;
grant select on v_verlust_je_gruppe to authenticated;
grant select on v_marge_buch to authenticated;
grant select on v_saisonbilanz to authenticated;

create index if not exists erg_gewichte_sorte     on erg_gewichte (sorte);
create index if not exists erg_ausgang_ts         on erg_ausgang (ts);
create index if not exists erg_lieferung_datum    on erg_lieferung (datum);
create index if not exists erg_kohorte_charge     on erg_kohorte (charge_nr, eingangsdatum);
create index if not exists erg_punkte_charge      on erg_punkte (charge_nr);
create index if not exists erg_wiegung_ts         on erg_wiegung (wiege_ts);
create index if not exists erg_fax_start          on erg_fax (start_ts);
create index if not exists erg_durchsatz_start    on erg_durchsatz (start_ts);
create index if not exists erg_verarbeitung_tag   on erg_verarbeitung_alter (tag);
grant select on v_verlust_je_gruppe to authenticated;
grant select on v_plausibilitaet to authenticated;
grant select on v_auftrag_wasch_paletten to authenticated;
grant select on v_auftrag_masse to authenticated;
grant select on v_verarbeitung_alter to authenticated;
grant select on v_verdunstung_messung to authenticated;
grant select on v_wiegung_kennzahl to authenticated;

create index if not exists erg_gewichte_sorte     on erg_gewichte (sorte);
create index if not exists erg_ausgang_ts         on erg_ausgang (ts);
create index if not exists erg_lieferung_datum    on erg_lieferung (datum);
create index if not exists erg_kohorte_charge     on erg_kohorte (charge_nr, eingangsdatum);
create index if not exists erg_punkte_charge      on erg_punkte (charge_nr);
create index if not exists erg_wiegung_ts         on erg_wiegung (wiege_ts);
create index if not exists erg_fax_start          on erg_fax (start_ts);
create index if not exists erg_durchsatz_start    on erg_durchsatz (start_ts);
create index if not exists erg_verarbeitung_tag   on erg_verarbeitung_alter (tag);
grant select on v_auftrag_wasch_paletten to authenticated;
comment on view v_auftrag_wasch_paletten is
  'Beim Waschen gezählte Paletten: Kisten gesamt, Masse = Kisten × gemessenes Kistengewicht des Kalibers, Tage im Zwischenlager aus dem Sortierdatum (0061).';
grant select on v_auftrag_masse to authenticated;
grant select on v_verarbeitung_alter to authenticated;
comment on view v_verarbeitung_alter is
  'Je Arbeit mit gezählten, datierten Paletten: mittleres Alter der verarbeiteten Ware gegen das mittlere Alter aller Paletten der Charge an dem Tag. differenz > 0: älter als der Durchschnitt verarbeitet.';
grant select on v_verdunstung_messung to authenticated;
grant select on v_wiegung_kennzahl to authenticated;
create unique index if not exists erg_koeff_fax_pk on erg_koeff_fax (sorte);
grant select on erg_koeff_fax to authenticated;
comment on materialized view erg_koeff_fax is
  'v_koeff_fax, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';
create unique index if not exists mv_koeff_rand_pk on mv_koeff_rand (sorte);
grant select on mv_koeff_rand to authenticated;
comment on materialized view mv_koeff_rand is
  'Die Ränder der Koeffizienten je Sorte (Verdunstung, zu klein, zu gross, '
  'Fax), geklammert wie in der Kaskade — die Grundlage der Hülle in '
  'v_prognose. Erneuert mit auswertung_schritt(2) (0071).';
grant select on v_prognose to authenticated;
grant select on erg_prognose to authenticated;
grant select on v_wohin to authenticated;
grant select on v_lieferung_charge_tag to authenticated;
grant select on erg_verlauf to authenticated;

comment on view v_fax_wartezeit is
  'Faules beim Abpacken nach Tagen zwischen Waschen und Fax — je Klasse '
  '(0–1 Tage, 2–3 Tage, 4 und mehr, unbekannt), einmal über alle Sorten und '
  'einmal je Sorte. Der Anteil ist massegewichtet (Faules ÷ durchgegangene '
  'Masse + Faules), der Bereich aus der Streuung zwischen den Arbeiten. '
  'Grundlage: auftrag.tage_seit_waschen, freiwillig seit 0060 (0071).';
grant select on v_fax_wartezeit to authenticated;

comment on view v_ueberfuellung_verkauf is
  'Je Sorte und je Charge, je Kistensystem: verkaufte Kisten und Kilo aus der '
  'Verkaufsdatei, gewogene Kisten und Kilo je Kiste aus den fertigen Paletten. '
  'Bei „Kiste ab x kg" ist der Überschuss verschenkte Ware (verschenkt_kg). '
  'Bei „x Stück je Kaliber" zählt die Lage im Band: 0 = Unterkante, 1 = '
  'Oberkante, über 1 heisst, die Wägung passt nicht zu ihrem Kaliber. '
  'spielraum_kg ist die Masse über der Unterkante, die unbezahlt mitgeht — '
  'Rahmen, nicht Verlust: niemand sortiert auf die Kante (0061, 0071).';
grant select on v_marge_buch to authenticated;
create index if not exists erg_ueberfuellung_gruppe on erg_ueberfuellung (gruppe, sorte, charge_nr);
grant select on erg_ueberfuellung to authenticated;
comment on materialized view erg_ueberfuellung is
  'v_ueberfuellung_verkauf, gespeichert für die App (0061, 0071). Erneuert mit auswertung_schritt().';
grant select on erg_wohin to authenticated;
create unique index if not exists erg_fax_wartezeit_pk on erg_fax_wartezeit (gruppe, coalesce(sorte, ''), klasse);
grant select on erg_fax_wartezeit to authenticated;
comment on materialized view erg_fax_wartezeit is
  'v_fax_wartezeit, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';

comment on view v_schimmel_menge is
  'Wie viel Faules eine Arbeit ergeben hat. Aus Palox-Ablesungen die Summe der '
  'Differenzen innerhalb der Arbeit (S₂ − S₁), aus gewogenen Kisten die Summe '
  'der Kilo. Keine Zeile, wenn nur einmal abgelesen wurde (das ist ein '
  'Startstand, kein Messwert), wenn eine Differenz unbekannt ist, oder wenn '
  'der Palox während der Arbeit geleert wurde (0073). Unbekannt ist nicht null.';

comment on view v_charge_erntespanne is
  'Über wie viele Tage sich die Ernte einer Charge zieht und wie stark die '
  'Masse darüber streut (massegewichtete Standardabweichung in Tagen). Das ist '
  'die Unsicherheit jeder Altersangabe, die über das Chargenmittel läuft. '
  'Solange die Ernte läuft, wandert der Mittelwert mit jedem Import — '
  'ernte_fertig sagt, ob er steht (0073).';

comment on view v_kontrollpalette_rate is
  'Je zwei aufeinanderfolgende Wägungen einer Kontrollpalette eine '
  'Verdunstungsrate für den Zeitraum DAZWISCHEN — nicht für die ganze Saison. '
  'Fällt die erste Rate deutlich höher aus als die späteren, ist der vermutete '
  'Schock beim Einlagern gemessen statt vermutet (0073). Wird in dieser Runde '
  'nur erhoben und angezeigt, nicht in die Kaskade eingebaut.';

grant select on v_charge_erntespanne, v_kontrollpalette_rate to authenticated;

comment on view v_kontrollpalette_vorschlag is
  'Die Chargen nach Eingangsmasse geordnet, mit der Angabe, ob schon eine '
  'Kontrollpalette darauf steht. Die fünf obersten sind der Vorschlag (0073).';
grant select on v_kontrollpalette_vorschlag to authenticated;
comment on view v_ausgang_voll is
  'v_ausgang_kennzahl mit der Angabe, ob die Palette voll war. Nicht volle '
  'zählen für die Masse, aber nicht für kg je Kiste — der Betrieb: „vlt die '
  'ersten beiden paletten je 40 kisten ifco und die letzte vlt nur 24" (0073).';
grant select on v_ausgang_voll to authenticated;
comment on view v_koeff_palette_netto is
  'Was eine VOLLE fertige Palette wiegt, je Sorte und Kistensystem. Nicht '
  'volle Paletten bleiben draussen — sonst zieht die halbvolle letzte Palette '
  'jeder Arbeit den Mittelwert nach unten und von dort die Fax-Masse (0073).';
comment on view v_koeff_fax is
  'Anteil Faules beim Abpacken (Fax), je Sorte — bezogen auf die Masse, die durch '
  'das Fax ging. NULL, solange keine Fax-Arbeit Faules gewogen hat: unbekannt, nicht 0. '
  'Steht einstellung.fax_eingefroren auf true (Runde R), ist der Anteil 0 durch '
  'Entscheid — bekannt, Basis „eingefroren" (0078).';
revoke all on function lager_kaliber(integer) from public;
grant execute on function lager_kaliber(integer) to authenticated;
grant select on v_lager_kaliber to authenticated;
comment on view v_marge_wiegung is
  'Die verschenkte Marge je Wägung, ohne Verkaufsdatei: je Sorte und Kistensystem '
  'der Durchschnitt der gewogenen vollen fertigen Paletten. Kiste ab: kg je Kiste '
  'gegen das Soll (zuviel_je_kiste = Ist − Soll). Stück: Gramm je Kürbis gegen die '
  'Bandmitte (g_ueber_bandmitte). Der Betrieb: „pro palette wissen, vlt 10x messen '
  'pro saison, dann einen durchschnittswert" (0078).';
grant select on v_marge_wiegung to authenticated;
grant select on erg_marge_wiegung to authenticated;
revoke all on function lager_schluessel() from public;
grant execute on function lager_schluessel() to authenticated;
revoke all on function kuerbis_stichtag(integer) from public;
grant execute on function kuerbis_stichtag(integer) to authenticated;
comment on function kaliber_glocke(integer) is
  'Die Gewichtsverteilung der liegenden verkaufsfähigen Ware am Stichtag '
  'heute + p_h, in 50-Gramm-Stufen: dieselben Kürbisse wie lager_kaliber(p_h), '
  'dieselbe Masse. n_kuerbis ist die gewogene Stückzahl hinter der Form (je '
  'Verteilungsschlüssel einmal), masse_kg die verkaufsfähige Masse der Kaskade '
  'in dieser Stufe. Chargen ohne Sortier-CSV stehen nicht darin — für sie gibt '
  'es keine Verteilung (0079).';
revoke all on function kaliber_glocke(integer) from public;
grant execute on function kaliber_glocke(integer) to authenticated;

create index if not exists erg_punkte_charge on erg_punkte (charge_nr);
comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, die Verdunstung dazwischen '
  '(0062 — vorher verlust_kg), kg je Kiste und je Kürbis, und seit 0079 die '
  'Tagesrate aus v_verdunstung_messung samt der Marke, ob sie verwendbar ist. '
  'Ohne Kistenzahl oder hinterlegte Tara gibt es kein Netto (0064).';
create index if not exists erg_wiegung_ts on erg_wiegung (wiege_ts);
comment on view v_auftrag_fertige_masse is
  'Beim Waschen die Masse, die herauskam: fertige Paletten gesamt mal der '
  'mittleren Masse der eigenen gewogenen vollen Paletten, hilfsweise der ihrer '
  'Sorte und ihres Kistensystems (0079). Nur Zeilen, für die beides bekannt '
  'ist — fehlt eine Angabe, gibt es keine Zeile: unbekannt, nicht null.';
grant select on v_auftrag_fertige_masse to authenticated;
comment on function lager_schluessel() is
  'Je Charge mit liegender Ware: woher ihre Gewichtsverteilung kommt (eigene '
  'Sortier-CSV, die der Sorte, oder keine) und mit welcher Verdunstungsrate '
  'geschrumpft wird. Seit 0082 zählt eine CSV nur mit, wenn ihr Sortiertag '
  'bekannt ist — ohne ihn lässt sich nicht sagen, wie lange geschrumpft wurde.';
comment on function kuerbis_stichtag(integer) is
  'Jeder sortierte Kürbis, wie er am Stichtag heute + p_h wiegt — geschrumpft '
  'ab seinem Sortiertag. Seit 0082 aus sortier_lauf.sortiertag; Lesungen ohne '
  'bekannten Sortiertag bleiben draussen, statt mit einem erfundenen Tag zu '
  'rechnen (0079, 0082).';
comment on view v_sortier_lesung is
  'Je eingelesener Datei: welche Art, welcher Zeitraum, welcher Sortiertag und '
  'woher er kommt. Eine Sammel-Lesung trägt nur das Delta zur vorigen — '
  'n_gueltig ist also, was DAZUKAM, nicht was in der Datei steht (0082).';
grant select on v_sortier_lesung to authenticated;

comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung. Seit 0061 zählen beim Waschen die '
  'gezählten Paletten (Kisten mit Sortierdatum) mit; die Lagerkontrolle zählt '
  'als Verdunstungsmessung, ohne Faul-Angabe. Seit 0076 zusätzlich die '
  'Kistenzahl auf der Eingangspalette. Seit 0082 die zwei Arten von '
  'Sortierdatei und die Güte des Sortiertags: Wie viele Lesungen haben '
  'überhaupt einen, und bei wie vielen ist er bezeugt statt geschätzt? '
  'Darauf ruht die Gewichtsverteilung des Lagers (0082).';
grant select on v_plausibilitaet_0064_zusatz to authenticated;
comment on view v_palox_stand is
  'Je Palox-Ablesung die Differenz zur vorigen derselben Arbeit. Die erste '
  'Ablesung und die nach dem Leeren (0084) sind Anfänge ohne Menge; ein '
  'gefallener Stand ohne angemeldetes Leeren ist eine unbekannte Differenz, '
  'keine Null (0073).';
grant select on v_palox_stand to authenticated;
comment on view v_marge_charge is
  'Die verschenkte Marge je Wägung, eine Ebene feiner als v_marge_wiegung: je '
  'Charge, Kistensystem und Soll bzw. Kaliber der Durchschnitt der gewogenen '
  'vollen fertigen Paletten (0086). Dieselbe Rechnung wie 0078.';
grant select on v_marge_charge to authenticated;
grant select on erg_marge_charge to authenticated;
grant select on v_plausibilitaet to authenticated;
comment on view v_verdunstung_messung is
  'Je Wägung derselben Palette: Netto damals und jetzt, Lagertage, die Tagesrate — '
  'und ob sie in die Rate der Sorte zählt (verwendbar). Seit 0089 sagt `grund`, '
  'warum nicht, und `plausibel`, ob die Rate unter der Grenze '
  'verdunstung_rate_max_pro_tag liegt: Was schneller schwindet, ist keine Verdunstung.';
grant select on v_verdunstung_messung to authenticated;
grant select on v_wiegung_kennzahl to authenticated;
create index if not exists erg_wiegung_ts on erg_wiegung (wiege_ts);
create index if not exists erg_ausgang_ts on erg_ausgang (ts);
grant select on v_plausibilitaet_0064_zusatz to authenticated;
comment on view v_auftrag_palette_masse is
  'Je gezählter Palette einer Arbeit ihr Netto und woher es stammt (masse_quelle): '
  'gewogen · zettel (im Wareneingang gefunden) · zettel-kisten (Zettel minus die gezählten '
  'Kisten und ihre Tara, 0090) · zettel-charge-tara · palette · datum-mittel · charge-mittel.';
grant select on v_auftrag_palette_masse to authenticated;
grant select on v_plausibilitaet to authenticated;
grant select on v_plausibilitaet_0064_zusatz to authenticated;
grant select on v_arbeit_kommentar to authenticated;
grant select on v_koeff_gebinde to authenticated;
grant select on v_plausibilitaet to authenticated;
grant select on v_plausibilitaet_0054_zusatz to authenticated;
comment on view v_arbeit_kommentar is
  'Je Arbeit der Kommentar zur Ware, so wie das Dashboard ihn an die Messungen hängt: '
  'text ist die Kurzfassung (0094 — nur gelesene und gekürzte Rückmeldungen erscheinen), '
  'roh das, was die Person gesagt hat, charge_nr die zugeordnete Charge (kurz_charge_nr, '
  'sonst die der Arbeit).';
grant select on v_arbeit_kommentar to authenticated;
create index if not exists erg_ausgang_ts on erg_ausgang (ts);
grant select on erg_marge_wiegung to authenticated;
comment on materialized view erg_marge_wiegung is
  'Gespeichert: die verschenkte Marge je Sorte, Kistensystem und Band (0078) — seit 0097 mit den '
  'Grenzen des Bandes aus der Fassung des Auftrags und mit jeder gewogenen Palette je Kiste (n_voll sagt, wie viele voll waren).';
grant select on erg_marge_charge to authenticated;
comment on materialized view erg_marge_charge is
  'Gespeichert: die verschenkte Marge je Charge (0086) — seit 0097 mit den Grenzen des Bandes '
  'aus der Fassung des Auftrags und mit jeder gewogenen Palette je Kiste.';

create unique index if not exists erg_verlauf_pk on erg_verlauf (woche, bis, gruppe, schluessel);
create index if not exists erg_verlauf_gruppe on erg_verlauf (gruppe, schluessel, bis);
create index if not exists erg_verlauf_woche on erg_verlauf (woche);
grant select on erg_verlauf to authenticated;
comment on view v_auftrag_wasch_gewogen is
  'Waschen (0104): die Masse hinein aus den am Anfang der Strasse gewogenen Paletten — Brutto minus Kisten × '
  'Kistentara minus Palettentara. Nicht gewogene Paletten rechnen mit dem Mittel je Kiste der gewogenen (quelle „teils").';
grant select on v_auftrag_wasch_gewogen to authenticated;

comment on materialized view erg_punkte is
  'v_schimmel_punkte mit dem Messtag (0079) und seit 0105 mit Station und eigenem Anteil, '
  'gespeichert für die App. Erneuert mit auswertung_schritt().';
grant select on v_palox_station to authenticated;
grant select on v_palox_erwartung to authenticated;
comment on view v_charge_palox is
  'Je Charge und Station ihr eigener Palox-Anteil (0106), massegewichtet über ihre plausiblen Arbeiten — gilt für die '
  'ausgelagerte Ware der Charge vor der Erwartung der Sorte.';
grant select on v_charge_palox to authenticated;
comment on view v_charge_weg is
  'Der Weg einer Charge durch die Stationen (0106): p_hand = Anteil von Hand (Waschen + Sortieren) an der verarbeiteten '
  'Masse, p_wasch = 1, wenn Bandware dieser Sorte gewaschen wird. Aus den eigenen Arbeiten, sonst denen der Sorte, sonst '
  'allen (weg_quelle); ohne jede Arbeit NULL.';
grant select on v_charge_weg to authenticated;
grant select on mv_kaskade to authenticated;
grant select on v_kaskade to authenticated;
grant select on mv_hochrechnung to authenticated;
grant select on v_hochrechnung to authenticated;
grant select on v_verlust_je_gruppe to authenticated;
grant select on erg_verlust to authenticated;
grant select on v_verlust_ranking to authenticated;
grant select on v_schimmel_punkte to authenticated;
grant select on v_marge_buch to authenticated;
grant select on v_hochrechnung_basis to authenticated;
grant select on erg_charge to authenticated;
grant select on v_kontrolle_vorschlag to authenticated;
grant select on v_massenbilanz to authenticated;
grant select on v_saisonbilanz to authenticated;
grant select on v_prognose to authenticated;
grant select on erg_prognose to authenticated;
grant select on v_naechste_charge to authenticated;
grant select on erg_verlauf to authenticated;
grant select on v_wohin to authenticated;
grant select on erg_wohin to authenticated;
grant select on v_plausibilitaet_0064_zusatz to authenticated;
grant select on v_plausibilitaet_0054_zusatz to authenticated;
grant select on v_plausibilitaet to authenticated;

create index if not exists erg_gewichte_sorte     on erg_gewichte (sorte);
create index if not exists erg_ausgang_ts         on erg_ausgang (ts);
create index if not exists erg_lieferung_datum    on erg_lieferung (datum);
create index if not exists erg_kohorte_charge     on erg_kohorte (charge_nr, eingangsdatum);
create index if not exists erg_wiegung_ts         on erg_wiegung (wiege_ts);
create index if not exists erg_fax_start          on erg_fax (start_ts);
create index if not exists erg_durchsatz_start    on erg_durchsatz (start_ts);
create index if not exists erg_verarbeitung_tag   on erg_verarbeitung_alter (tag);
comment on materialized view erg_ausgang is
  'Gespeichert: jede gewogene fertige Palette mit ihren Kennzahlen (v_ausgang_voll) — seit 0089 mit voll, damit die Marge-Karte sagen kann, welche Wägung nicht zählt.';
comment on materialized view erg_wiegung is
  'Gespeichert: jede Wägung mit ihren Kennzahlen (v_wiegung_kennzahl), seit 0089 mit plausibel und grund. Schritt 4 des Rechenwerks.';
grant select on erg_palox_erwartung to authenticated;
comment on view v_koeff_gebinde_formel is
  'Das Kistengewicht je Sorte und Kaliberband: aus Wasch-Arbeiten, die hinein gezählt und heraus gewogen haben (0092), und aus Sortierläufen mit gezählten Kisten (0060). kaliber_idx −1: Sollgewicht-Kisten aus gewogenen fertigen Paletten. — Die Formel (0109); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
grant select on v_koeff_gebinde_formel to authenticated;
comment on function v_koeff_gebinde_zaun() is
  'Planungsgrenze (0109): liest v_koeff_gebinde_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_koeff_gebinde_zaun() from public;
grant execute on function v_koeff_gebinde_zaun() to authenticated;
comment on view v_koeff_gebinde is
  'Das Kistengewicht je Sorte und Kaliberband: aus Wasch-Arbeiten, die hinein gezählt und heraus gewogen haben (0092), und aus Sortierläufen mit gezählten Kisten (0060). kaliber_idx −1: Sollgewicht-Kisten aus gewogenen fertigen Paletten. Seit 0109 über die Planungsgrenze v_koeff_gebinde_zaun(); die Formel steht in v_koeff_gebinde_formel.';
comment on view v_auftrag_masse_formel is
  'Die Masse einer Arbeit und ihr Alter. Die Masse in dieser Reihenfolge: gewogene oder vom Zettel gelesene Eingangspaletten; beim Waschen die fertigen Paletten dieser Arbeit (0079, „fertige_paletten"); die gezählten Kisten der Kaliber-Paletten („wasch_paletten"); gezählte Gebinde; bei Fax die Palettenzahl. Fehlt alles, ist die Masse unbekannt — nicht null. — Die Formel (0109); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
grant select on v_auftrag_masse_formel to authenticated;
comment on function v_auftrag_masse_zaun() is
  'Planungsgrenze (0109): liest v_auftrag_masse_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_auftrag_masse_zaun() from public;
grant execute on function v_auftrag_masse_zaun() to authenticated;
comment on view v_auftrag_masse is
  'Die Masse einer Arbeit und ihr Alter. Die Masse in dieser Reihenfolge: gewogene oder vom Zettel gelesene Eingangspaletten; beim Waschen die fertigen Paletten dieser Arbeit (0079, „fertige_paletten"); die gezählten Kisten der Kaliber-Paletten („wasch_paletten"); gezählte Gebinde; bei Fax die Palettenzahl. Fehlt alles, ist die Masse unbekannt — nicht null. Seit 0109 über die Planungsgrenze v_auftrag_masse_zaun(); die Formel steht in v_auftrag_masse_formel.';
comment on view v_schimmel_punkte_formel is
  'Jede Faul-Messung als Punkt: die Lagerdauer (wie lange lag die Ware?) und seit 0079 der Messtag (wann wurde gemessen?). Zwei Achsen für zwei Fragen — „faulen sie nach N Wochen" und „ab wann ging es los". Der Messtag ist der Betriebstag, nie ts::date (0067/0070). — Die Formel (0109); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
grant select on v_schimmel_punkte_formel to authenticated;
comment on function v_schimmel_punkte_zaun() is
  'Planungsgrenze (0109): liest v_schimmel_punkte_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_schimmel_punkte_zaun() from public;
grant execute on function v_schimmel_punkte_zaun() to authenticated;
comment on view v_schimmel_punkte is
  'Jede Faul-Messung als Punkt: die Lagerdauer (wie lange lag die Ware?) und seit 0079 der Messtag (wann wurde gemessen?). Zwei Achsen für zwei Fragen — „faulen sie nach N Wochen" und „ab wann ging es los". Der Messtag ist der Betriebstag, nie ts::date (0067/0070). Seit 0109 über die Planungsgrenze v_schimmel_punkte_zaun(); die Formel steht in v_schimmel_punkte_formel.';
grant select on v_koeff_kaliber_geschaetzt_formel to authenticated;
comment on function v_koeff_kaliber_geschaetzt_zaun() is
  'Planungsgrenze (0109): liest v_koeff_kaliber_geschaetzt_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_koeff_kaliber_geschaetzt_zaun() from public;
grant execute on function v_koeff_kaliber_geschaetzt_zaun() to authenticated;
comment on view v_koeff_verdunstung_geschaetzt is
  'Die Verdunstungsrate je Sorte (0111): das massegewichtete Mittel der verwendbaren Wägungen der Sorte, ab anteil_mindest_messungen() Wägungen; sonst das Mittel aller Sorten (b = 0, geliehen). Bis 0110 wurde der Sortenwert per empirischem Bayes zum Gesamtwert gezogen; tau2 bleibt deshalb leer. varianz = Unsicherheit des Mittels, df = n − 1 der geltenden Ebene.';
comment on view v_koeff_verdunstung is
  'Die Verdunstungsrate je Tag je Sorte, wie die Kaskade sie nimmt (0111): Mittel der eigenen Wägungen ab drei, sonst aller Sorten; nie negativ, das Band ± t · √varianz. basis sagt die Ebene („dieser Sorte" / „aller Sorten").';

comment on view v_koeff_ausschuss is
  'Zu klein je Sorte (Anteil der Masse unter dem kleinsten Band) mit Bereich, Zahl der Messungen und Bezugsgrösse — seit 0111 das Mittel der eigenen Sortierläufe und Handmessungen ab drei, sonst aller Sorten.';
comment on view v_koeff_nebenkanal is
  'Zu gross je Sorte (Anteil der Masse über dem grössten Band, Nebenkanal) mit Bereich, Zahl der Messungen und Bezugsgrösse — seit 0111 das Mittel der eigenen Messungen ab drei, sonst aller Sorten. Kein Verlust: ein anderer Kanal.';
comment on view v_koeff_unsicherheit is
  'Je Koeffizient und Sorte: der eigene Fehleranteil (b = 1: der Wert der Sorte gilt) oder der Fehler des Gesamtwerts (b = 0: geliehen, 0111). Getrennt, weil der Gesamtwert für alle Sorten derselbe ist und seine Fehler sich nicht wegmitteln.';
comment on view v_palox_station is
  'Die Kennzahl je Station bis heute (0105) — unter dem Diagramm „Palox-Ausschuss". zuwachs_je_woche ist seit 0111 der Anstieg je Woche Lagerdauer.';
grant select on v_palox_station to authenticated;
comment on view v_palox_erwartung is
  'Je Sorte und Station der Grundausschuss (0111): der Palox-Anteil bei frischer Ware — Mittel der plausiblen Punkte der Sorte (massegewichtet), um den Anstieg der Station (v_palox_station.zuwachs_je_woche) auf null Lagertage zurückgelegt. Ab palox_mindest_arbeiten() Arbeiten der Sorte, sonst aller Sorten (geliehen). Für Ware mit t Lagertagen gilt anteil + anstieg_je_woche · t / 7. mittel/lager_mittel: wie gemessen. unten/oben: ± t · sd/√n.';
grant select on v_palox_erwartung to authenticated;
comment on materialized view erg_palox_erwartung is
  'v_palox_erwartung, gespeichert (0107): der Grundausschuss je Sorte und Station mit dem Anstieg der Station (0111) — das Dashboard und der Betriebsabzug lesen diese Fassung. Schritt 3.';
grant select on erg_palox_erwartung to authenticated;
grant select on mv_kaskade to authenticated;
grant select on erg_verlauf to authenticated;
grant select on v_hochrechnung_basis to authenticated;
grant select on v_kaskade to authenticated;
grant select on v_prognose to authenticated;
grant select on erg_charge to authenticated;
grant select on erg_prognose to authenticated;
grant select on mv_hochrechnung to authenticated;
grant select on v_plausibilitaet_0064_zusatz to authenticated;
grant select on v_hochrechnung to authenticated;
grant select on v_kontrolle_vorschlag to authenticated;
grant select on v_massenbilanz to authenticated;
grant select on v_naechste_charge to authenticated;
grant select on v_plausibilitaet_0054_zusatz to authenticated;
grant select on v_verlust_je_gruppe to authenticated;
grant select on erg_verlust to authenticated;
grant select on v_plausibilitaet to authenticated;
grant select on v_marge_buch to authenticated;
grant select on v_saisonbilanz to authenticated;
grant select on v_wohin to authenticated;
grant select on erg_wohin to authenticated;
comment on function lager_kaliber(integer) is
  'Was in h Tagen noch im Haus ist, je Charge und je Sorte, nach Kaliber (0079, Unter-/Überkaliber seit 0111): klasse ''unter'' (kaliber_idx −1: zu klein), ''kaliber'' (die Bänder; ohne Sortier-CSV eine Zeile ohne Band), ''ueber'' (kaliber_idx −2: zu gross). verkaufsfaehig_kg = Summe der Bänder = Verkaufsfähiges der Prognose. geschrumpft_kg: der Teil des kleinsten Bandes, der seit der Sortierung darunter geschrumpft ist (zur Auskunft). anteil: Anteil des Bandes am Verkaufsfähigen.';
revoke all on function lager_kaliber(integer) from public;
grant execute on function lager_kaliber(integer) to authenticated;
comment on view v_lager_kaliber is
  'lager_kaliber(0): das Lager nach Kaliber heute, mit Unter- und Überkaliber (0111) — zum Nachschauen im SQL-Editor. Der Bildschirm ruft lager_kaliber(0) und lager_kaliber(7·X) direkt; im Rechenwerk (auswertung_schritt) steht keine gespeicherte Fassung (0078).';
grant select on v_lager_kaliber to authenticated;
comment on view v_lauf_vergleich is
  'Sortierläufe derselben Charge nebeneinander (AB-113, 0111): je Lauf Median, Quartile und Mittel des Gewichts je Kürbis; gegen den ersten Lauf der Charge die Tage dazwischen und die Rate je Tag aus Median und Mittel (ab sieben Tagen), daneben die Rate aus den Palettenwägungen der Sorte. Gegenprobe, nicht Teil der Rate: Es sind andere Kürbisse.';
grant select on v_lauf_vergleich to authenticated;
grant select on v_verkauf_position to authenticated;
grant select on v_kunde_tag to authenticated;
comment on view v_sorte_artikelgruppe is
  'Je Sorte die Artikelgruppe: aus den Stammdaten, sonst die meistverkaufte Gruppe ihrer Lieferungen; gruppe_verkauft zum Vergleich (0112).';
grant select on v_sorte_artikelgruppe to authenticated;
grant select on v_charge_label to authenticated;
revoke all on function artikel_lager(integer) from public;
grant execute on function artikel_lager(integer) to authenticated;
comment on view v_charge_label is
  'Je Charge Demeter (D) oder Knospe (K) — seit 0113 nach der Regel des Betriebs: Stammdaten; sonst D, sobald Perigon sie einmal als Demeter geliefert (oder, ohne Lieferlabel, verkauft) hat; sonst K aus Perigon; sonst wie die anderen Chargen desselben Schlags (Produzent); sonst K, angenommen („Knospe ist alles, das nicht Demeter ist"). gemischt: beide geliefert; n_widerspruch: als Demeter verkauft, aber als Knospe geliefert — zum Prüfen.';
grant select on v_charge_label to authenticated;
comment on function artikel_lager_teile(integer) is
  'Die ungerundeten Teile hinter artikel_lager und artikel_lager_charge: je Charge das Verkaufsfähige in h Tagen, nach den Artikelkalibern ihrer Gruppe geteilt (0113; bis 0112 im Innern von artikel_lager).';
revoke all on function artikel_lager_teile(integer) from public;
comment on function artikel_lager_charge(integer) is
  'Das Verkaufsfähige in h Tagen je Charge und Artikel (Gruppe, Label, Grösse) — dieselben Teile wie artikel_lager(h), nur nicht zusammengezählt: woraus „Knirps klein · Demeter" besteht (0113).';
revoke all on function artikel_lager_charge(integer) from public;
grant execute on function artikel_lager_charge(integer) to authenticated;
comment on function artikel_lager(integer) is
  'Das Verkaufsfähige in h Tagen je Artikelgruppe, Label (D/K) und Grösse (klein, gross, stueck; darunter/darueber: in keinem Artikelkaliber; lose: Gruppe ohne Kaliber; ohne Verteilung: keine Sortier-CSV) — dieselbe Masse wie lager_kaliber(h), nach den Artikelkalibern geteilt; Stück = kg ÷ mittleres Gewicht der Klasse (0112). Seit 0113 aus artikel_lager_teile, wie artikel_lager_charge.';
revoke all on function artikel_lager(integer) from public;
grant execute on function artikel_lager(integer) to authenticated;
comment on view v_lieferung_charge is
  'Jede Lieferung bis heute() (Verkauf, Marge, Verlust) und die Chargen, von denen sie genommen hat: mit Chargennummer ganz (anteil 1); ohne nach dem Eingang auf die Chargen ihrer Sorte verteilt (ohne_charge); der Ausgang vor der App am Erfassungsbeginn als eine Lieferung mit id = −Charge. Die Regel gibt es nur hier: v_lieferung_charge_tag, v_lieferung_kohorte, die Kaskade und v_lieferung_gruppe rechnen darauf (0114; bis dahin im Innern von v_lieferung_charge_tag, 0071).';
grant select on v_lieferung_charge to authenticated;
comment on view v_lieferung_charge_tag is
  'Gelieferte Masse je Charge, Tag und Buch — nur Lieferungen bis heute(). Eine Lieferung ohne Chargennummer wird nach dem Eingangsanteil auf die Chargen ihrer Sorte verteilt; der Vorlauf zählt am Erfassungsbeginn. Seit 0114 aus v_lieferung_charge, wo die Regel steht; v_lieferung_kohorte rechnet darauf (0071).';
grant select on v_lieferung_charge_tag to authenticated;
comment on view v_lieferung_gruppe is
  'Je Gruppe (gesamt, Sorte, Schlag, Charge) die Lieferscheine bis heute (Verkauf, Marge), die von ihren Chargen genommen haben — jeder einmal, auch wenn er ohne Chargennummer auf mehrere Chargen verteilt ist; n_ohne_charge: wie viele davon keine Chargennummer trugen. Der Ausgang vor der App ist Masse, kein Lieferschein, und zählt hier nicht. Nur Chargen mit Eingang, wie erg_charge (0114).';
grant select on v_lieferung_gruppe to authenticated;
grant select on v_hochrechnung_basis to authenticated;
grant select on v_plausibilitaet to authenticated;
grant select on erg_verlauf to authenticated;
comment on view v_verkauf_position is
  'Je Lieferscheinposition: Datum, Saison, Kunde, Artikel, kg — aus ausgang_position (alle Saisons), ergänzt um die Positionen der laufenden Saison, die nur in ausgang_zeile stehen (0112). Seit 0115 mit Menge und Einheit: kg ist leer, wo Perigon die Masse nicht hergibt.';
grant select on v_verkauf_position to authenticated;
comment on view v_kunde_tag is
  'Geliefert je Kunde, Saison, Tag und Artikel (Gruppe, Grösse, Label) — nur Kürbis, ohne interne Umbuchung (Journal L). Für den Vergleich mit den Vorjahren (0112). Seit 0115: stueck_ohne_gewicht und positionen_ohne_gewicht — was Perigon ohne Stückgewicht führt, steht nicht in kg, aber es steht da.';
grant select on v_kunde_tag to authenticated;
grant usage, select on all sequences in schema public to authenticated;
comment on view v_kaliber_fassung is
  'Die Grenzen der gültigen Fassung je Sorte (0116): lo = untere Grenze des ersten Bandes (darunter zu klein), hi = obere Grenze des letzten (darüber zu gross).';
comment on view v_kaliber_lauf is
  'Je Sortierlauf mit Gewichten (0116): das Alter der Ware beim Sortieren — aus den Zetteldaten der Arbeit (alter_quelle zettel), sonst aus den Paletten der Charge, die am Sortiertag schon da waren (eingang) —, und die Verdunstungsrate der Sorte, mit der jeder Kürbis auf den Eingangstag zurückgerechnet wird.';
create unique index if not exists mv_kaliber_eingang_pk on mv_kaliber_eingang (ebene, schluessel, g0);
comment on materialized view mv_kaliber_eingang is
  'Die Gewichtsverteilung beim Eingang (0116), je Charge (ebene charge) und je Sorte (ebene sorte) aus den Sortierläufen, jeder Kürbis um die Verdunstung seiner Sorte über das Alter beim Sortieren zurückgerechnet (v_kaliber_lauf). anteil_bis: Anteil der Masse bis und mit g0 Gramm. Erneuert mit auswertung_schritt() vor der Kaskade.';
create unique index if not exists mv_kaliber_quelle_pk on mv_kaliber_quelle (charge_nr);
comment on materialized view mv_kaliber_quelle is
  'Je Charge, woher zu klein und zu gross kommen (0116): aus der Verteilung beim Eingang ihrer eigenen Sortierläufe (ebene charge), sonst der ihrer Sorte (ebene sorte), mit den Grenzen lo/hi der gültigen Fassung. Fehlt eine Charge hier, gilt der gemessene Anteil der Sorte.';
comment on function kaliber_anteil(text, text, numeric, numeric, numeric) is
  'Massenanteil zu klein (unter lo) und zu gross (über hi) einer Verteilung beim Eingang (mv_kaliber_eingang), jeder Kürbis um den Faktor q = (1 − r)^Alter geschrumpft (0116). Leer ohne Verteilung.';
revoke all on function kaliber_anteil(text, text, numeric, numeric, numeric) from public;
grant execute on function kaliber_anteil(text, text, numeric, numeric, numeric) to authenticated;
create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, portion, COALESCE(kohorte, '1900-01-01'::date));
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);
comment on materialized view mv_kaskade is
  'Die Massenkaskade je Charge, Eingangstag und Portion. Drei Portionen: „ausgelagert" ist die Eingangsmasse hinter den verkauften und in den Nebenkanal gegangenen Lieferungen, „entsorgt" die hinter dem Kompost (0065 — nur um die Verdunstung zurückgerechnet, weil entsorgte Ware selbst das Faule ist), „lager" der Rest, der noch liegt. Je Portion die Ströme Verdunstung, Palox-Ausschuss, zu klein, zu gross, Fax und verkaufsfähig. f ist der Palox-Anteil über den Weg der Charge (palox_f: p_hand, p_wasch, f_ws, f_s, g_w). Seit 0111 gilt jeder Stationswert für das Alter der Portion: Grundausschuss der Sorte (v_palox_erwartung) + Anstieg der Station je Woche Lagerdauer (v_palox_station) × alter_tage / 7; für Ausgelagertes mit eigener Messung gilt diese, ohne Anstieg. f_quelle sagt, woher; f_geliehen: aus allen Sorten. b_ws/b_s/b_w ist der Anstieg, mit dem Prognose und Verlauf fortschreiben (0 bei eigener Messung), zuwachs_bekannt sagt, ob sie es dürfen.';
grant select on mv_kaskade to authenticated;
create index if not exists erg_verlauf_woche on erg_verlauf (woche);
create unique index if not exists erg_verlauf_pk on erg_verlauf (woche, bis, gruppe, schluessel);
create index if not exists erg_verlauf_gruppe on erg_verlauf (gruppe, schluessel, bis);
comment on materialized view erg_verlauf is
  'Je Woche und Gruppe (gesamt, Sorte, Schlag, Charge): Eingang und Ausgang kumuliert (gemessen), im Lager (Eingangsware, die noch nicht hinter einer Lieferung steckt) und davon verkaufsfähig (gerechnet) — ab heute als Prognose bis zum Saisonende (prognose = true). Der Verlust ist der Abstand zwischen im Lager und verkaufsfähig; seine Teile stehen weiter als eigene Spalten (0071). Seit 0106 ohne Sockel: das Faule ist der Palox-Anteil der Stationen, mit dem Zuwachs je Woche zurück und voraus verschoben, wo die Kennzahl ihn ausweist. Seit 0114 fällt „im Lager" mit den Lieferungen: je Woche der Teil, den die Lieferungen der Charge bis dahin ausmachen, nicht alles am mittleren Liefertag.';
grant select on erg_verlauf to authenticated;
comment on view v_hochrechnung_basis is
  'Je Charge, alles bis heute: Eingang und geliefert (gemessen), ausgelagert (Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus ausgelagert, in Eingangskilo), verlust_heute_kg (Verdunstung + Faules + Fax am Abgepackten), im_haus_heute_kg (Eingangsmasse, die noch liegt, nach Verdunstung und Verderb, plus hinter den Lieferungen Aussortiertes, 0101). Keine Prognose. 0064: Jede Stromsumme ist NULL, solange ihr Koeffizient keine Messung hat. Seit 0106 ohne Sockel; faul_anteil und faul_quelle sagen, womit das Liegende rechnet und woher es kommt. Seit 0114 zählt n_lieferungen jeden Lieferschein, der von der Charge genommen hat, einmal (bis dahin einmal je Eingangstag; der Ausgang vor der App zählt in der Masse, nicht als Lieferschein).';
grant select on v_hochrechnung_basis to authenticated;
comment on view v_kaskade is
  'Der Massenfluss je Charge, Eingangstag und Portion: Was eingelagert wurde (eingang_kg) verteilt sich auf Verdunstung, Faules, zu klein, Nebenkanal, Fax und verkaufsfähige Ware. Die Ströme addieren sich zum Eingang. "Verlust" ist hier nur, was wirklich verloren ist: verdunstung_kg, schimmel_kg. klein_kg und nebenkanal_kg sind kein Verlust, sondern ein anderer Kanal. Seit 0106 ohne Sockel; f kommt aus den Stationswerten (f_quelle).';
grant select on v_kaskade to authenticated;
comment on view v_prognose is
  'Was aus der heute liegenden Ware wird, wenn sie liegen bleibt — je Gruppe (gesamt, Sorte, Schlag, Charge) und je Horizont h Tage, von heute bis zum Saisonende in Wochenschritten (7/14/28 immer dabei). Es ist die Kaskade (mv_kaskade, Portion „lager") bei alter_tage + h, mit denselben Formeln: bei h = 0 stehen deshalb genau die Zahlen von erg_charge. Der Palox-Anteil wächst je Station um ihren Anstieg je Woche Lagerdauer (0111) — nur wenn zuwachs_bekannt; sonst bleibt der Anteil von heute stehen und faul_je_tag_kg ist leer. kanal_kg = klein_kg + gross_kg (zu klein, zu gross; getrennt seit 0111). f_geliehen: ein Anteil aus allen Sorten. Der Nenner ist lager_kg, die Eingangsware, die noch nicht hinter einer Lieferung steckt; vollstaendig heisst: Verdunstung, Palox, Ausschuss und Fax gemessen.';
grant select on v_prognose to authenticated;
create unique index if not exists erg_charge_pk on erg_charge (charge_nr);
create index if not exists erg_charge_sorte on erg_charge (sorte);
comment on materialized view erg_charge is
  'v_hochrechnung_basis, gespeichert für die App (0062). Erneuert mit auswertung_schritt(). Seit 0101 zählt im_haus_heute_kg das hinter den Lieferungen Aussortierte mit (kanal_ausgelagert_kg: zu klein und zu gross, im Haus, nicht verkaufsfähig). Seit 0106 ohne Sockel, mit faul_anteil und faul_quelle.';
grant select on erg_charge to authenticated;
create unique index if not exists erg_prognose_pk on erg_prognose (gruppe, schluessel, h);
create index if not exists erg_prognose_gruppe on erg_prognose (gruppe, h);
comment on materialized view erg_prognose is
  'v_prognose, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';
grant select on erg_prognose to authenticated;
create index if not exists mv_hochrechnung_charge on mv_hochrechnung (charge_nr, buch);
comment on materialized view mv_hochrechnung is
  'v_hochrechnung, gespeichert. Inhaltlich gleich; erneuert von auswertung_schritt(3).';
grant select on mv_hochrechnung to authenticated;
comment on view v_plausibilitaet_0064_zusatz is
  'Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die Paletten fehlen im Eingang), eine Charge mit mehr Ausgang als Eingang, und ein Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag.';
grant select on v_plausibilitaet_0064_zusatz to authenticated;
comment on view v_hochrechnung is
  'Die Kaskade auseinandergelegt: eine Zeile je Charge, Portion und Strom, mit dem verwendeten Koeffizienten, seiner Herkunft (koeff_art, beim Faulen koeff_basis = f_quelle), der Zahl der Messungen dahinter (koeff_n) und der Formel. koeff_bekannt = false heisst: geschätzt, nicht gemessen. f_geliehen: der Palox-Anteil kommt aus den Arbeiten aller Sorten (0106).';
grant select on v_hochrechnung to authenticated;
comment on view v_kontrolle_vorschlag is
  'Welche Charge als Nächstes kontrolliert werden sollte. informationswert gewichtet, wie viel noch im Haus liegt, wie lange die letzte Wiegung her ist und wie unsicher die Charge bisher ist — eine Reihenfolge, kein Befehl.';
grant select on v_kontrolle_vorschlag to authenticated;
comment on view v_massenbilanz is
  'Die Probe aufs Exempel je Charge: Was die Kaskade am Band erwartet (modell_am_band_kg: Bandarbeiten nach Verdunstung und Palox-Anteil der Sortierstation, 0106) gegen das, was die Sortier-Datei gewogen hat (csv_gemessen_kg). abweichung_anteil nahe 0 heisst, die Koeffizienten treffen die Wirklichkeit; systematisch positiv heisst, die Verluste sind überschätzt. Nur für Chargen mit Sortier-Datei aussagekräftig.';
grant select on v_massenbilanz to authenticated;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Gerechnet aus v_prognose (Horizont 14 gegen Horizont 0) — dieselbe Formel wie die Kaskade, damit es im ganzen Programm nur eine Zwei-Wochen-Zahl gibt. prognose_verlust_14_kg ist, was an **verkaufsfähiger** Ware verloren geht, und verdunstung_14_kg + schimmel_14_kg ergeben es auf den Rappen. Seit 0106 leer, solange die Kennzahl je Station keinen Zuwachs ausweist (zuwachs_bekannt = false).';
grant select on v_naechste_charge to authenticated;
comment on view v_plausibilitaet_0054_zusatz is
  'Zusatzprüfungen zu v_plausibilitaet, die seit 0054 dazugekommen sind — je Auffälligkeit Art, betroffene Arbeit, Befund und Rat. Wird von v_plausibilitaet mitgelesen; einzeln braucht sie niemand.';
grant select on v_plausibilitaet_0054_zusatz to authenticated;
comment on view v_verlust_je_gruppe is
  'Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, Charge). kg_beobachtet ist gemessen, kg_projiziert auf noch nicht Gemessenes übertragen, kg_extrapoliert seit 0106 mit einem aus allen Sorten geliehenen Palox-Anteil gerechnet — drei verschiedene Sicherheiten, darum drei Spalten. Ist der Strom gemessen (bekannt), sind alle vier Teilbeträge Zahlen und kg_beobachtet + kg_projiziert = kg. Das Band kg_unten/kg_oben kommt aus der Unsicherheit der Koeffizienten, beim Faulen aus dem Band des Stationswerts (f_se).';
grant select on v_verlust_je_gruppe to authenticated;
create unique index if not exists erg_verlust_pk on erg_verlust (gruppe, schluessel, strom);
comment on materialized view erg_verlust is
  'v_verlust_je_gruppe, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';
grant select on erg_verlust to authenticated;
comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette. 0066: „Ausschuss-Tara" rechnet nur nach, wo Kistenzahl und hinterlegte Tara da sind; fehlt eine, steht die Lücke als „Ausschuss ohne Tara" daneben. 0087: die Nachrechnung zieht die Palette nur ab, wenn sie mitgewogen wurde, und klemmt nichts auf null. 0114: eine zu schnell leichter gewordene Wägung steht nur als „Verdunstung" da, nicht noch einmal als „Wägung".';
grant select on v_plausibilitaet to authenticated;
comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb verlassen hat, ohne verkaufsfähig zu sein — zu klein, Nebenkanal, Überfüllung. Kein Verlust im Sinne von verdorben, sondern Masse in einem anderen Kanal. kg_unten und kg_oben spannen den Bereich auf, gemessen sagt, ob dahinter Messungen oder Schätzungen stehen.';
grant select on v_marge_buch to authenticated;
comment on view v_saisonbilanz is
  'Die Saison bis heute in einer Zeile (erg_bilanz). Seit 0101: Eingang + Überzählung = ausgeliefert (Lieferscheine) + Verlust bis heute + im Haus — zu klein und zu gross sind Teil von im Haus (kanal_ausgelagert_kg aussortiert, kanal_im_haus_kg im Liegenden erwartet), nicht Ausgang. Seit 0106 ohne Sockel.';
grant select on v_saisonbilanz to authenticated;
comment on view v_wohin is
  'Wohin ging der Kürbis — je Gruppe (gesamt, Sorte, Schlag, Charge) der ganze Eingang aufgeteilt: ausgeliefert, anderer Kanal, verdunstet und faul an der ausgelieferten Ware, Faules beim Abpacken, und was noch liegt (davon verkaufsfähig, Kanal, Fax erwartet, faul, verdunstet). rest_kg und lager_rest_kg sind die zwei Identitäten: beide haben den Erwartungswert null, und eine doppelt gezählte Portion bliebe darin stehen. Seit 0106 ohne Sockel.';
grant select on v_wohin to authenticated;
create unique index if not exists erg_wohin_pk on erg_wohin (gruppe, schluessel);
comment on materialized view erg_wohin is
  'v_wohin, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';
grant select on erg_wohin to authenticated;
comment on view v_kunde_position is
  'Jede Kürbis-Position je Kunde (0116), eingeordnet nach Artikelgruppe, Grösse und Label — dieselbe Auswahl wie v_kunde_tag, nur nicht zusammengezählt. Für die Liste der Lieferungen eines Kunden; die ganze Zeile steht in ausgang_position.roh.';
grant select on v_kunde_position to authenticated;
grant select on v_perigon_pruefung to authenticated;
grant select on v_perigon_pruefung to authenticated;
create unique index if not exists mv_kaliber_pk
  on mv_kaliber_verteilung (charge_nr, klasse, coalesce(kaliber_idx, -1), coalesce(band_von, -1), coalesce(band_bis, -1));
comment on materialized view mv_kaliber_verteilung is
  'v_kaliber_verteilung, gespeichert. Inhaltlich gleich; erneuert von '
  'auswertung_schritt(2).';
grant select on mv_kaliber_verteilung to authenticated;
comment on view v_kaliber_verteilung is
  'Wie sich die sortierte Ware je Charge auf die Kaliberbänder verteilt: '
  'Stückzahl und Masse je Band, dazu die Klassen "zu klein" und '
  '"Nebenkanal". Gewogen aus den Sortierläufen.';
grant select on v_kaliber_verteilung to authenticated;
grant select on erg_kaliber to authenticated;
comment on materialized view erg_kaliber is 'v_kaliber_verteilung, gespeichert für die App Erneuert mit auswertung_schritt().';
grant select on v_lager_ausweis to authenticated;
comment on view v_ohne_charge is
  'Lieferscheine ohne Chargennummer bis heute (Verkauf, Marge), je Sorte (0121): wie viele, wie viel, von wann bis wann; auf welche Chargen die Rechnung sie verteilt (verteilt_auf, nach dem Eingang, 0114); kg_vor_eingang: was davon hinausging, bevor die Charge, die es tragen soll, eingegangen war; kg_ohne_ziel: was auf keine Charge fällt, weil keine Charge der Sorte Eingang hat (oder die Sorte fehlt).';
grant select on v_ohne_charge to authenticated;
grant select on v_ungereimtheit to authenticated;
comment on view v_perigon_pruefung is
  'Seit 0121 in Sätzen, die ohne Perigon-Kenntnis zu lesen sind; eine Nummer, die die App inzwischen kennt, holt der nächste Rechenlauf nach. Was beim Durchsehen der Perigon-Zeilen der laufenden Saison auffällt (0116, 0118), je Zeile mit dem Satz, was zu tun ist: Charge nicht zugeordnet (eine Nummer, die die App nicht auflösen kann), Teil ohne Charge (die Datei schreibt den Chargen weniger zu, als die Position geliefert hat — 0118), Artikel passt nicht zur Sorte der gelieferten Charge, als Demeter verkauft und als Knospe geliefert, Lieferung vor dem ersten Eingang.';
grant select on v_perigon_pruefung to authenticated;
comment on view v_perigon_produzent is
  'Wer in Perigon Spalte X (Produzent) wie heisst, und welcher Schlag das in der App ist (0122): quelle betrieb = schlag_alias; gelernt = aus den Zeilen, deren Chargennummer die App kennt, wenn der Name nur bei Chargen eines Schlags vorkommt.';
grant select on v_perigon_produzent to authenticated;
comment on function schlag_von_produzent(text) is
  'Der Schlag der App zu einem Namen aus Perigon Spalte X oder dem Journal: zuerst schlag_alias, dann gelernt, dann ein Schlag gleichen Namens; sonst null (0122).';
revoke all on function schlag_von_produzent(text) from public;
grant execute on function schlag_von_produzent(text) to authenticated;
grant select on v_charge_spur to authenticated;
comment on view v_stammdaten_pruefung is
  'Was im Chargenregister selbst nicht stimmt (0122): perigon_doppelt (eine Perigon-Nummer an mehreren Chargen, mit den verwandten Nummern aus den Dateien), ohne_perigon_nr (Charge der laufenden Saison mit Ware, ohne Perigon-Nummer), schlag_zweimal (ein Schlag unter zwei Namen).';
grant select on v_stammdaten_pruefung to authenticated;
comment on function ungereimt_kandidaten(int, date) is
  'Chargen, von denen die Ware einer Charge mit Ungereimtheit wohl kam (0122): derselbe Artikel, laut App noch Paletten, höchstens zur Hälfte verkauft, vor p_bis eingegangen; derselbe Schlag und dieselbe Sorte zuerst, höchstens vier.';
revoke all on function ungereimt_kandidaten(int, date) from public;
grant execute on function ungereimt_kandidaten(int, date) to authenticated;
comment on view v_ungereimtheit is
  'Was zwischen Perigon, Erntejournal und Lager nicht zusammenpasst, je Charge oder Sorte, mit den Kilo, um die es geht (0121, 0122): ohne_eingang, vor_eingang, ueberzaehlung (mit kandidaten: Chargen, von denen die Ware wohl kam), ohne_charge, umgebucht, vorschlag, nachgeordnet (über den Produzenten zugeordnet), stammdaten (was im Chargenregister nicht stimmt, v_stammdaten_pruefung). Die Zeilen der Perigon-Dateien stehen in v_perigon_pruefung; der Weg der Ware je Charge in v_charge_spur.';
grant select on v_ungereimtheit to authenticated;
grant select on v_lager_ausweis to authenticated;

comment on view v_lager_ausweis is
  'Was im Lager liegt, Schritt für Schritt, je Charge heute (0121, 0123, 0124): eingang_kg (Eingangsmasse auf den Paletten, die noch stehen — „im Lager") − verdunstet − faul (Palox, ohne Hagel) − unique (Hagel, wird als Knospe verkauft) − zu klein − zu gross (Sortiermaschine) − Faules beim Abpacken = verkaufsfaehig_kg (nach der Sortiermaschine); davon marge_kg Überfüllung (marge_anteil = zu viel ÷ Soll, gewogen je Charge, sonst je Sorte; Stück-Kisten 0), verrechenbar_kg der Rest. verkaufbar_kg = verkaufsfaehig_kg − keinen_artikel_kg (leichter oder schwerer als die Artikelgewichte, artikel_lager_teile; leer ohne Sortier-CSV) − ueberfuellung_kg (auf dem Teil, der als Artikel geht) + unique_kg — was als Artikel tatsächlich verkauft werden kann. groesse_offen_kg: ohne Sortier-CSV; gruppe_offen_kg: Sorte ohne Artikelgruppe (0124) — beides nicht abgezogen, verkaufbar_kg ist dann eine obere Schranke, und verkaufbar_offen sagt, was fehlt. Hagel 100 %: faul_kg, unique_kg und verkaufbar_kg leer (nicht trennbar). hagel_bis_heute_kg: der Hagel-Teil im Faulen bis heute, kein Verlust. Aus erg_prognose (h = 0), erg_charge, mv_kaskade, erg_marge_charge, v_ausgang_kennzahl, artikel_lager_teile(0).';
grant select on v_lager_ausweis to authenticated;
comment on view v_charge_spur is
  'Der Weg der Ware je Charge (0122): herein laut Erntejournal (journal_*: die Charge, die das Journal nennt) und wie die App jetzt zählt (paletten, eingang_kg), was umgebucht ist oder vorgeschlagen (weg: von hier weg, her: hierher), bearbeitet in der Halle (Arbeiten, mit Zahl der Zettel), hinaus laut Lieferscheinen (Lieferscheine; nach_artikel: je Artikelgruppe aus den Perigon-Zeilen, der Rest als „ohne Perigon-Zeile" — die Teile gehen auf geliefert_kg auf (0124); davon nachgeordnet), und was laut App noch da ist (rest_paletten).';
grant select on v_charge_spur to authenticated;

comment on view v_koeff_kaliber_geschaetzt_formel is
  'Zu klein (ausschuss), zu gross (nebenkanal) und Fax je Sorte: seit 0111 das massegewichtete Mittel der eigenen Messungen ab anteil_mindest_messungen() Messungen, sonst das Mittel aller Sorten (b = 0, geliehen); b = 1 heisst: die Sorte trägt sich selbst. Kein Zug zum Gesamtwert mehr; tau2 bleibt leer. — Die Formel (0109); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
comment on view v_koeff_kaliber_geschaetzt is
  'Zu klein (ausschuss), zu gross (nebenkanal) und Fax je Sorte: seit 0111 das massegewichtete Mittel der eigenen Messungen ab anteil_mindest_messungen() Messungen, sonst das Mittel aller Sorten (b = 0, geliehen); b = 1 heisst: die Sorte trägt sich selbst. Seit 0109 über die Planungsgrenze v_koeff_kaliber_geschaetzt_zaun(); die Formel steht in v_koeff_kaliber_geschaetzt_formel.';


-- =====================================================================
-- Der App sagen, dass es etwas Neues gibt
-- =====================================================================
-- Zwischen der Datenbank und der App sitzt PostgREST. Es merkt sich, welche
-- Tabellen und Funktionen es gibt, und schaut nicht bei jeder Anfrage neu
-- nach. Ohne diesen Anstoss kann die App nach einer Aktualisierung noch eine
-- Weile behaupten, eine gerade angelegte Funktion gebe es nicht — genau die
-- Meldung "Could not find the function ... in the schema cache". Der Anstoss
-- wird beim Abschluss der Transaktion zugestellt, also erst, wenn wirklich
-- alles durchgelaufen ist.
notify pgrst, 'reload schema';

-- =====================================================================
-- Die Auswertung: rechnen lassen — oder rechnen
-- =====================================================================
-- Die gespeicherten Auswertungen (mv_…) werden oben ohne Inhalt angelegt.
-- Bis Runde AG rechnete diese Datei sie hier zu Ende — mit der vollen
-- Saison des Betriebs länger, als der SQL-Editor auf eine Antwort wartet
-- („Load failed", die ganze Einspielung zurückgerollt, und bis dahin hielt
-- die Transaktion Sperren auf allem, was die App liest). Darum: Wo ein
-- Zeitplan da ist (pg_cron), wird nur angefordert — der Lauf des Zeitplans
-- (jede Minute, 0103) rechnet gleich nach dem Einspielen im Hintergrund,
-- unter der Zeitgrenze der Rolle (60 Minuten); die App sagt derweil „wird
-- gebaut" und lädt von selbst nach. Ohne Zeitplan (die Tests, eine
-- Datenbank ohne pg_cron) wird hier gerechnet wie bisher: da wartet niemand
-- im Browser.
--
-- Vorher noch einmal: Läufe, die während dieser Datei begonnen haben und
-- auf ihre Sperren warten (mit dem Stand von vor dieser Datei im Bauch),
-- werden beendet — sonst rechnete gleich nach dem Abschluss noch ein alter.
-- Ob ein Zeitplan da ist, sagt auswertung_cron_da() (0108): pg_cron, oder in
-- der Prüfung kuerbis.zeitplan_test = 'an' — so spielt run.sh (3c) den Weg
-- des Betriebs nach, ohne pg_cron.
do $$
declare v_erg jsonb; r record;
begin
  for r in select pid from pg_stat_activity
            where datname = current_database() and pid <> pg_backend_pid()
              and state <> 'idle'
              and (query ~* 'auswertung_(schritt|wenn_veraltet|aktualisieren|sofort_lauf)'
                   or query ilike '%refresh materialized view%')
              and query not ilike '%setup.sql%'
  loop
    begin
      perform pg_terminate_backend(r.pid);
    exception when others then null;
    end;
  end loop;
  if auswertung_cron_da() then
    v_erg := auswertung_anfordern();
    if (v_erg ->> 'weg') = 'zeitplan' then
      perform set_config('kuerbis.auswertung',
        format('Auswertung angefordert (%s Uhr): der Zeitplan rechnet sie jetzt im Hintergrund, in zwei bis vier Minuten steht sie — die App zeigt derweil „wird gebaut" und lädt von selbst nach.',
               to_char(now(), 'HH24:MI')), false);
      return;
    end if;
  end if;
  perform auswertung_aktualisieren();
  perform set_config('kuerbis.auswertung', 'Auswertung berechnet.', false);
exception when others then
  perform set_config('kuerbis.auswertung',
    format('Auswertung NICHT berechnet (%s) — in der App auf „Neu rechnen"; unter Messungen → Auffälligkeiten nachsehen.', sqlerrm),
    false);
end $$;

-- =====================================================================
-- Rückmeldung im Ergebnisfenster
-- =====================================================================
-- Was der Nutzer wissen muss, steht in dieser einen Zeile — die Hinweise
-- oben sind stummgeschaltet. Dazu gehört auch, ob pg_cron da ist: Fehlt es,
-- rechnet nur „Neu rechnen" in der App, kein Zeitplan.
do $$
begin
  perform set_config('kuerbis.cron',
    case when exists (select 1 from pg_extension where extname = 'pg_cron')
         then '' else ' Ohne pg_cron rechnet die App nur auf „Neu rechnen" — beim Öffnen nie.' end,
    false);
  -- Liegen hier echte Erfassungsdaten (einstellung erfassung_scharf, 0072)?
  -- Dann steht es vorne in der Fertig-Zeile UND kommt als Warnung durch —
  -- Warnungen sind nicht stummgeschaltet (AB-43), genau dafür. Wer die Datei
  -- gerade in die echte Datenbank eingespielt hat, soll es lesen; wer eine
  -- Sicherung vergessen hat, soll es jetzt merken und nicht nächste Woche.
  perform set_config('kuerbis.scharf',
    case when coalesce((select (wert #>> '{}')::boolean from einstellung
                         where schluessel = 'erfassung_scharf'), false)
         then 'ACHTUNG: Auf dieser Datenbank liegen echte Erfassungsdaten (erfassung_scharf). '
         else '' end,
    false);
  if current_setting('kuerbis.scharf', true) <> '' then
    raise warning 'Echte Erfassungsdaten auf dieser Datenbank — vor jedem weiteren Einspielen eine Sicherung ziehen (docs/ZWEI_WEBSEITEN.md).';
  end if;
end $$;

select format('%sFertig. Die Datenbank steht: %s Chargen, %s Sorten, %s Tabellen, %s Auswertungen. %s%s Weiter im README bei Schritt 4.',
              coalesce(current_setting('kuerbis.scharf', true), ''),
              (select count(*) from charge),
              (select count(*) from sorte_kaliber),
              (select count(*) from pg_tables where schemaname = 'public'),
              (select count(*) from pg_views  where schemaname = 'public'),
              coalesce(nullif(current_setting('kuerbis.auswertung', true), ''), 'Auswertung nicht gerechnet.'),
              coalesce(current_setting('kuerbis.cron', true), '')) as ergebnis;
