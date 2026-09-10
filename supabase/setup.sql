-- =====================================================================
-- Kürbis-Verlust-Tracking — das komplette Setup in einer Datei
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

-- =====================================================================
-- TEIL A — Tabellen, Daten, Rechte: die Geschichte
-- =====================================================================


-- =====================================================================
-- aus 0000_aktualisierung.sql
-- =====================================================================

-- =====================================================================
-- 0000 — Vorbereitung: Platz machen für eine Aktualisierung
-- Kürbis-Verlust-Tracking
--
-- WOZU DAS DA IST
--
-- setup.sql ist die ganze Geschichte der Datenbank hintereinander. Auf einer
-- leeren Datenbank läuft sie glatt durch. Auf einer, die schon einen älteren
-- Stand trägt, nicht: `create view` stolpert über die Ansicht, die es schon
-- gibt, `create policy` über die Regel gleichen Namens. Früher stand deshalb
-- am Anfang eine Sperre, die den zweiten Durchlauf abgewiesen hat — mit der
-- Folge, dass eine einmal eingerichtete Datenbank nie wieder etwas Neues
-- bekommen hat. Ein Betrieb konnte monatelang auf einem alten Stand laufen
-- und hat es erst gemerkt, wenn die App eine Funktion suchte, die es dort
-- nie gegeben hat.
--
-- Statt abzuweisen, wird hier aufgeräumt: alles, was die Datenbank nur
-- *ausrechnet*, fliegt raus — Ansichten, Funktionen, Zugriffsregeln,
-- Auslöser. Danach sieht die Datenbank für den Rest von setup.sql aus wie
-- eine frische, und das Skript baut das Rechenwerk vollständig neu auf.
--
-- WAS DABEI NICHT ANGEFASST WIRD
--
-- Tabellen und ihr Inhalt. Jede Messung, jede Palette, jeder Auftrag bleibt
-- unberührt: gelöscht wird ausschliesslich, was sich aus diesen Daten wieder
-- herstellen lässt. Und weil das gesamte Skript in einer Transaktion läuft,
-- gibt es kein Dazwischen — entweder die Aktualisierung geht ganz durch,
-- oder die Datenbank steht unverändert da wie vorher.
--
-- Auf einer leeren Datenbank tut diese Datei nichts.
-- =====================================================================

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


-- =====================================================================
-- aus 0001_schema.sql
-- =====================================================================

-- =====================================================================
-- 0001 — Schema: Tabellen, Typen, Indizes
-- Kürbis-Verlust-Tracking
--
-- Grundsätze (Spec §8):
--   * Rohdaten sind immutable. Reinigung/Klassierung ist reproduzierbar.
--   * Jede Messzeile trägt `gemessen`, `erfasser`, `ts`.
--   * Leer ≠ 0: eine fehlende Messung ist NULL/keine Zeile, niemals 0.
-- =====================================================================

-- ---------- Typen ----------------------------------------------------
-- `create type` kennt kein "if not exists". Dieser Block ist das Ersatz-
-- stück: Auf einer bestehenden Datenbank sind die Typen längst da und
-- werden übersprungen, statt die Aktualisierung abzubrechen. Wegwerfen
-- und neu anlegen geht nicht — an den Typen hängen die Tabellenspalten.
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

-- ---------- Benutzer & Rollen ----------------------------------------
create table if not exists profil (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null,
  rolle      rolle not null default 'arbeiter',
  aktiv      boolean not null default true,
  erstellt_ts timestamptz not null default now()
);
comment on table profil is
  'Ein Profil je Login. Der erste Benutzer muss per SQL auf rolle=''admin'' gesetzt werden — siehe README.';

-- Neue Auth-Benutzer bekommen automatisch ein Arbeiter-Profil.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profil (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

-- Beim Aktualisieren steht der Auslöser schon; ohne das Wegräumen hier
-- scheitert das Anlegen.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Stammdaten -----------------------------------------------
create table if not exists gebinde (
  art               text primary key,
  tara_kg_pro_kiste numeric(6,3),          -- NULL = unbekannt, nicht 0
  tara_kg_palette   numeric(6,3),
  bemerkung         text
);
comment on column gebinde.tara_kg_pro_kiste is
  'Leergewicht einer Kiste. NULL bedeutet "nicht erfasst" — Netto bleibt dann NULL statt falsch zu sein.';

create table if not exists sorte_kaliber (
  sorte           text primary key,
  verlust_unter   int  not null,           -- < diesem Gewicht = Verlust (weggeworfen)
  kaliber_baender jsonb not null,          -- [[300,800],[800,2000]] — Konvention [untere, obere)
  kanal_ab        int  not null default 2000,
  constraint kaliber_baender_ist_liste check (jsonb_typeof(kaliber_baender) = 'array')
);
comment on table sorte_kaliber is
  'Kaliber-Grenzen in Gramm. Die Anzahl Bänder variiert je Sorte (2–4) und ist bewusst nicht fix.';

create table if not exists charge (
  nr     int primary key,                  -- undurchsichtige ID, nicht fortlaufend
  schlag text not null,
  sorte  text not null references sorte_kaliber(sorte) on update cascade,
  saison int  not null,
  unique (schlag, sorte, saison)
);
comment on table charge is
  'Charge = Schlag × Sorte. Die Chargennummer ist der Join-Schlüssel des gesamten Systems.';

-- ---------- Wareneingang (Import aus der Journal-App) ------------------
create table if not exists palette (
  id            bigserial primary key,
  charge_nr     int  not null references charge(nr),
  eingangsdatum date not null,
  brutto_kg     numeric(8,2) not null,
  kisten        int,
  gebindeart    text references gebinde(art) on update cascade,
  extern_id     text unique,               -- Zeilen-ID aus dem Sheet → idempotenter Import
  quelle        text not null default 'journal-import',
  erfasst_ts    timestamptz not null default now()
);
comment on column palette.extern_id is
  'Stabile ID der Sheet-Zeile. Verhindert Doppel-Import; ein erneuter Import aktualisiert dieselbe Zeile.';

create index if not exists palette_charge_nr_eingangsdatum_idx on palette (charge_nr, eingangsdatum);

-- ---------- Auftrag ---------------------------------------------------
create table if not exists auftrag (
  id                bigserial primary key,
  weg               verarbeitungsweg not null,
  station           station not null,
  charge_nr         int not null references charge(nr),
  start_ts          timestamptz not null default now(),   -- verlässliche Server-Zeit
  ende_ts           timestamptz,
  geplante_paletten int,
  status            auftrag_status not null default 'offen',
  eroeffnet_von     uuid not null default auth.uid() references profil(id),
  durchsatz_kg      numeric(10,2),                        -- siehe Kommentar unten
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

-- Paletten zählen: eine Zeile je gezählter Palette (Spec §10 — Pflichtfeld).
create table if not exists auftrag_palette (
  id            bigserial primary key,
  auftrag_id    bigint not null references auftrag(id) on delete cascade,
  palette_id    bigint references palette(id),   -- falls die konkrete Palette bekannt ist
  eingangsdatum date,                            -- sonst: Datum vom Zettel
  erfasser      uuid not null default auth.uid() references profil(id),
  ts            timestamptz not null default now()
);
create index if not exists auftrag_palette_auftrag_id_idx on auftrag_palette (auftrag_id);

-- ---------- Messungen --------------------------------------------------
-- Schimmel/Fäulnis: klein genug, um direkt gewogen zu werden (Spec §9).
create table if not exists schimmel_messung (
  id          bigserial primary key,
  auftrag_id  bigint not null references auftrag(id) on delete cascade,
  kg          int not null check (kg >= 0),      -- ganzzahlig (Spec §10)
  teilgewicht boolean not null default false,    -- Palox voll → Zwischenwägung
  gemessen    boolean not null default true,
  erfasser    uuid not null default auth.uid() references profil(id),
  ts          timestamptz not null default now(),
  bemerkung   text
);
create index if not exists schimmel_messung_auftrag_id_idx on schimmel_messung (auftrag_id);

-- Ausschuss zu klein / zu gross nach Auge (nur Weg 2 — Weg 1 kommt aus der CSV).
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

-- Verdunstung: bester Messpunkt ist Weg 2 beim Herausholen aus dem Lager (Spec §3).
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
  sichtbar_schimmel boolean not null default false,  -- dann nicht für die Verdunstungsrate verwenden
  gemessen          boolean not null default true,
  erfasser          uuid not null default auth.uid() references profil(id),
  wiege_ts          timestamptz not null default now(),
  ts                timestamptz not null default now(),
  bemerkung         text
);
create index if not exists verdunstung_wiegung_charge_nr_eingangsdatum_idx on verdunstung_wiegung (charge_nr, eingangsdatum);

-- Buch B: verschenkte Marge (Spec §2) — niemals mit dem Verlust-Buch mischen.
create table if not exists marge_messung (
  id         bigserial primary key,
  auftrag_id bigint not null references auftrag(id) on delete cascade,
  art        marge_art not null,
  wert       numeric(10,3) not null,   -- nebenkanal: kg · ueberfuellung: Überschuss-kg
  einheit    text not null default 'kg',
  n_kisten   int,                      -- bei Überfüllung: wie viele Kisten die Wägung umfasst
  gemessen   boolean not null default true,
  erfasser   uuid not null default auth.uid() references profil(id),
  ts         timestamptz not null default now(),
  bemerkung  text
);
create index if not exists marge_messung_auftrag_id_art_idx on marge_messung (auftrag_id, art);

-- ---------- Sortier-CSV -------------------------------------------------
create table if not exists sortier_lauf (
  id                bigserial primary key,
  charge_nr         int references charge(nr),
  datei_name        text not null,
  roh_datei_ref     text,                 -- Pfad im Storage-Bucket "rohdaten" (unverändert)
  roh_pruefsumme    text unique,          -- SHA-256 der Rohdatei → verhindert Doppel-Upload
  datei_zeit        timestamptz,          -- aus dem Dateinamen geparst
  datei_zeit_quelle text,                 -- 'dateiname' | 'lastModified' | 'manuell'
  auftrag_id        bigint references auftrag(id) on delete set null,
  zuordnung         zuordnung_status not null default 'offen',
  reinigung         jsonb not null,       -- die verwendeten Parameter → reproduzierbar
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

-- Bereinigte Einzelgewichte, lauflängenkodiert (gewicht_g → anzahl).
-- Verlustfrei gegenüber "eine Zeile je Kürbis": die Reihenfolge wird nach der
-- Dubletten-Reinigung nicht mehr gebraucht, das Gewicht hat 2-g-Auflösung.
-- Spart auf der Supabase-Gratis-Stufe rund 90 % Speicher. v_sortier_kuerbis
-- expandiert die Zeilen wieder, falls doch pro Kürbis gerechnet werden soll.
create table if not exists sortier_gewicht (
  lauf_id     bigint not null references sortier_lauf(id) on delete cascade,
  gewicht_g   int    not null,
  anzahl      int    not null check (anzahl > 0),
  klasse      kuerbis_klasse not null,
  kaliber_idx int,                     -- Index im Bänder-Array, NULL außerhalb der Kaliber
  primary key (lauf_id, gewicht_g)
);
create index if not exists sortier_gewicht_lauf_id_klasse_idx on sortier_gewicht (lauf_id, klasse);

-- ---------- Einstellungen ------------------------------------------------
create table if not exists einstellung (
  schluessel text primary key,
  wert       jsonb not null,
  bemerkung  text
);


-- =====================================================================
-- aus 0002_rls.sql
-- =====================================================================

-- =====================================================================
-- 0002 — Rollen & Row Level Security
--
-- Zwei Rollen (Spec §10): Betriebsleiter (admin) und Arbeiter.
-- Leitlinie: Arbeiter dürfen alles sehen, was sie für ihre Arbeit brauchen,
-- und Messungen erfassen. Korrigieren/Löschen darf man die eigene frische
-- Zeile; alles andere macht der Betriebsleiter.
-- =====================================================================

create or replace function public.ist_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profil where id = auth.uid() and rolle = 'admin' and aktiv);
$$;

-- Wie lange darf ein Arbeiter eine eigene Erfassung noch korrigieren?
create or replace function public.korrekturfenster()
returns interval language sql immutable as $$ select interval '12 hours' $$;

-- Ist der angemeldete Benutzer an diesem Auftrag beteiligt (Eröffner oder Beigetretener)?
-- security definer, damit die Policy auf auftrag nicht rekursiv auf sich selbst prüft.
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

-- ---------- Profil ----------------------------------------------------
create policy profil_lesen  on profil for select to authenticated using (true);
create policy profil_eigen  on profil for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profil_admin  on profil for all to authenticated
  using (ist_admin()) with check (ist_admin());

-- Die Rolle darf nur der Betriebsleiter ändern. Als Trigger statt in der Policy:
-- eine Unterabfrage auf profil innerhalb einer profil-Policy wäre rekursiv.
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

-- ---------- Stammdaten: lesen alle, schreiben nur Admin ----------------
do $$
declare t text;
begin
  foreach t in array array['gebinde', 'sorte_kaliber', 'charge', 'palette', 'einstellung'] loop
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_lesen', t);
    execute format('create policy %I on %I for all to authenticated using (ist_admin()) with check (ist_admin())',
                   t || '_admin', t);
  end loop;
end $$;

-- ---------- Auftrag ----------------------------------------------------
create policy auftrag_lesen on auftrag for select to authenticated using (true);
create policy auftrag_eroeffnen on auftrag for insert to authenticated
  with check (eroeffnet_von = auth.uid());
-- Beitreten, Zwischenstand ändern, abschließen darf jeder Beteiligte.
-- Ändern/abschließen darf, wer am Auftrag beteiligt ist — solange er offen ist.
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

-- ---------- Messungen: erfassen darf jeder Angemeldete -----------------
-- Eigene frische Zeilen korrigierbar, alte nur durch den Betriebsleiter.
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

-- ---------- Sortier-CSV: nur der Betriebsleiter lädt hoch --------------
create policy lauf_lesen on sortier_lauf for select to authenticated using (true);
create policy lauf_admin on sortier_lauf for all to authenticated
  using (ist_admin()) with check (ist_admin());

create policy gewicht_lesen on sortier_gewicht for select to authenticated using (true);
create policy gewicht_admin on sortier_gewicht for all to authenticated
  using (ist_admin()) with check (ist_admin());

-- ---------- Storage: Rohdateien ----------------------------------------
insert into storage.buckets (id, name, public)
values ('rohdaten', 'rohdaten', false)
on conflict (id) do nothing;

-- storage.objects gehört Supabase und überlebt ein Zurücksetzen des
-- public-Schemas. Deshalb hier erst aufräumen, sonst scheitert ein erneutes
-- Setup an einer Policy, die noch von vorhin herumliegt.
drop policy if exists rohdaten_lesen     on storage.objects;
drop policy if exists rohdaten_schreiben on storage.objects;

create policy rohdaten_lesen on storage.objects for select to authenticated
  using (bucket_id = 'rohdaten');
create policy rohdaten_schreiben on storage.objects for insert to authenticated
  with check (bucket_id = 'rohdaten' and ist_admin());
-- Kein update/delete: die Rohdatei bleibt unverändert (Spec §4).


-- =====================================================================
-- aus 0003_stammdaten.sql
-- =====================================================================

-- =====================================================================
-- 0003 — Stammdaten der laufenden Saison
--
-- Quelle: Spec §6 (Kaliber-Grenzen) und §7 (Charge-Registry).
-- Kanonische Sorten-Schreibweise ist die hier verwendete; im Grenzen-Sheet
-- stand fälschlich „Lektor" statt „Lekor".
-- =====================================================================

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

-- ---------- Sorten-Kaliber-Grenzen (Gramm, Konvention [untere, obere)) ----
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

-- ---------- Charge-Registry (Schlag × Sorte → Chargennummer) -------------
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

-- ---------- Gebinde ------------------------------------------------------
-- Die Gebindearten kommen aus der Journal-App und werden beim Paletten-Import
-- automatisch angelegt. Die Tara-Gewichte kennt nur der Betrieb — bis sie
-- eingetragen sind, bleibt tara NULL und das Netto der Palette NULL
-- (Leer ≠ 0). Zu pflegen unter Stammdaten → Gebinde.


-- =====================================================================
-- aus 0004_logik.sql
-- =====================================================================

-- =====================================================================
-- 0004 — Klassierung, CSV-Aufnahme, Auftrags-Zuordnung
--
-- Arbeitsteilung (Spec §12): Parsen und Reinigen der CSV laufen im Browser
-- (die Dubletten-Regel braucht die Zeilenreihenfolge). Klassiert wird hier
-- in der Datenbank — so gibt es genau eine Wahrheit für die Kaliber-Grenzen,
-- und eine Änderung der Grenzen lässt sich auf alte Läufe neu anwenden.
-- =====================================================================

-- ---------- Klassierung eines Einzelgewichts (Spec §6) -------------------
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

-- ---------- Zuordnung CSV-Lauf → Auftrag (Spec §5) ------------------------
-- Zuerst über Zeit-Enthaltensein im Auftragsintervall, sonst über die
-- nächstliegende Startzeit innerhalb des Fensters. Nur eindeutige Treffer
-- werden automatisch gesetzt; alles andere landet in der Admin-Warteschlange.
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

-- ---------- CSV-Lauf aufnehmen -------------------------------------------
-- Der Browser liefert das bereits gereinigte Histogramm [[gewicht_g, anzahl], …]
-- plus die Reinigungs-Kennzahlen. Hier wird klassiert und zugeordnet.
-- Läuft als Invoker → die RLS-Policy „nur Betriebsleiter" greift.
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

comment on function csv_lauf_speichern is
  'Nimmt einen gereinigten Sortierlauf auf. Die Rohdatei liegt unverändert im '
  'Storage-Bucket "rohdaten"; p_reinigung hält fest, mit welchen Parametern '
  'gereinigt wurde, damit das Ergebnis reproduzierbar bleibt.';


-- =====================================================================
-- aus 0008_rechte.sql
-- =====================================================================

-- =====================================================================
-- 0008 — Rechte
--
-- Was ein Angemeldeter *darf*, entscheiden die Policies aus 0002. Die
-- Grants hier öffnen nur überhaupt die Tür; ohne passende Policy sieht
-- und ändert man trotzdem nichts.
-- =====================================================================

grant usage on schema public to anon, authenticated;

-- Schreiben: nur die Tabellen, in die tatsächlich geschrieben wird.
grant insert, update, delete on
  profil, gebinde, sorte_kaliber, charge, palette, einstellung,
  auftrag, auftrag_teilnehmer, auftrag_palette,
  schimmel_messung, ausschuss_messung, verdunstung_wiegung, marge_messung,
  sortier_lauf, sortier_gewicht
  to authenticated;

-- Neue Objekte späterer Migrationen erben dieselben Rechte.
alter default privileges in schema public grant select on tables to authenticated;
alter default privileges in schema public grant usage, select on sequences to authenticated;
alter default privileges in schema public grant execute on functions to authenticated;


-- =====================================================================
-- aus 0009_anonyme_arbeiter.sql
-- =====================================================================

-- =====================================================================
-- 0009 — Arbeiter ohne Konto (anonyme Anmeldung)
--
-- Arbeiter sollen per QR-Code in die App kommen und sofort loslegen —
-- ohne Mail, ohne Passwort. Sie tippen einmal ihren Namen, mehr nicht.
-- Der Betriebsleiter behält seinen echten Login fürs Dashboard.
--
-- Technisch nutzen wir Supabase "Anonymous sign-ins": Auch ein anonymer
-- Nutzer bekommt eine echte, gerätefeste Identität (auth.uid()). Damit
-- funktioniert die gesamte Rechte- und Erfasser-Logik unverändert weiter —
-- eine anonyme Anmeldung ist trotzdem an genau eine Person (den Namen) und
-- ein Gerät gebunden.
--
-- WICHTIG, EINMALIG IM SUPABASE-DASHBOARD: Authentication → Sign In / Providers
-- → Anonymous sign-ins aktivieren. Sonst lehnt Supabase die Anmeldung ab.
--
-- Diese Datei ist gefahrlos einzeln einspielbar (alles "if not exists" bzw.
-- "create or replace").
-- =====================================================================

-- Kennzeichnet Geräte-Anmeldungen ohne Konto — nur zur Anzeige für den
-- Betriebsleiter und für eine spätere Aufräum-Möglichkeit.
alter table profil add column if not exists anonym boolean not null default false;

-- Beim Anlegen eines neuen Nutzers das Profil füllen. Neu gegenüber 0001:
--   * anonyme Nutzer haben keine E-Mail → als anonym markieren
--   * leerer Metadaten-Name zählt wie kein Name
--   * letzte Rückfallebene "Gast", damit die Anmeldung nie an einem
--     fehlenden Namen scheitert (NOT NULL)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profil (id, name, anonym)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'name', ''),
             nullif(split_part(new.email, '@', 1), ''),
             'Gast'),
    new.email is null
  )
  on conflict (id) do nothing;
  return new;
end $$;


-- =====================================================================
-- aus 0010_gebinde_tara.sql
-- =====================================================================

-- =====================================================================
-- 0010 — Gebinde-Tara aus dem Erntejournal übernehmen
--
-- Die Leergewichte kennt der Betrieb bereits — sie stehen fest im Code der
-- Wareneingang-App (src/lib/constants.ts). Sie hier einzutragen erspart dem
-- Betriebsleiter das Nachwiegen und macht das Netto sofort berechenbar.
--
--   Netto = Brutto − 25 (Palette) − Kisten × Tara(Gebindeart)
--
-- Quelle: Kürbis-Erntejournal, PALETTE_TARA_KG = 25 und GEBINDEARTEN.
-- „G2" ist der Standard, den die App bei leerem Gebinde-Feld annimmt.
--
-- Einzeln einspielbar; überschreibt vorhandene Werte bewusst nicht, damit eine
-- von Hand nachgewogene Zahl erhalten bleibt (on conflict do nothing).
-- =====================================================================

insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette, bemerkung) values
  ('G2',         1.500, 25.000, 'Standardkiste (auch bei leerem Gebinde-Feld im Journal)'),
  ('IFCO 6410',  1.360, 25.000, 'IFCO-Klappkiste'),
  ('IFCO 6416',  1.680, 25.000, 'IFCO-Klappkiste'),
  ('IFCO 6424',  2.000, 25.000, 'IFCO-Klappkiste')
on conflict (art) do nothing;


-- =====================================================================
-- aus 0011_plausibilitaet.sql
-- =====================================================================

-- =====================================================================
-- 0011 — Unplausible Messungen abfangen, ohne sie zu verstecken
--
-- Gefunden beim Durchgehen der Rechenkette: Ein vertippter Schimmelwert
-- (5000 statt 500 kg auf einer 865-kg-Palette) ergab 578 % Schimmelanteil.
-- Der Wert lief ungebremst durch die Kaskade und erzeugte −4135 kg
-- „verkaufsfähige" Masse und 5000 kg Verlust bei 865 kg Eingang.
--
-- Zwei Regeln daraus:
--   1. Die Rechnung wird gegen Unsinn gesichert (Anteile bleiben in [0,1],
--      Bezugsmassen werden nie negativ).
--   2. Aussortierte Werte verschwinden nicht still — v_plausibilitaet listet
--      sie für den Betriebsleiter auf. Eine unplausible Messung ist fast immer
--      ein Tippfehler, den man korrigieren will, keine Zahl zum Wegwerfen.
-- =====================================================================

-- ---------- Schwelle ------------------------------------------------------
-- Über 90 % der Masse als Schimmel oder Ausschuss ist real nicht zu erwarten;
-- so etwas kommt praktisch nur durch einen Tippfehler zustande.
create or replace function anteil_plausibel(p_anteil numeric)
returns boolean language sql immutable as $$
  select p_anteil is not null and p_anteil >= 0 and p_anteil <= 0.9;
$$;

-- ---------- Deaktivierte Personen dürfen nichts mehr erfassen -------------
-- profil.aktiv war bisher nur Zierde: die Erfassungs-Policies fragten es nicht ab.
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


-- =====================================================================
-- aus 0012_wiegen_beim_zaehlen.sql
-- =====================================================================

-- =====================================================================
-- 0012 — Wiegen gehört ans Zählen, nicht in einen eigenen Reiter
--
-- Es ist dieselbe Person, die die Paletten zählt und sie wiegt. Statt eines
-- getrennten Reiters fragt die App künftig bei jeder gezählten Palette, ob
-- sie auch gewogen wurde. Daraus folgen zwei Änderungen am Datenmodell:
--
--   1. Zählung und Wägung müssen verbunden sein (wiegung_id) — bisher standen
--      sie unverbunden nebeneinander, obwohl sie dieselbe Palette meinen.
--   2. Die Palette wird nicht mehr aus einer Liste gesucht. Bei hunderten
--      Paletten, von denen viele gleich schwer sind, ist das nicht bedienbar
--      und lädt zum Vergreifen ein. Der Arbeiter tippt stattdessen ab, was
--      auf dem Zettel steht: Eingangsdatum und Eingangsgewicht. Beide Felder
--      gibt es in verdunstung_wiegung bereits; palette_id bleibt einfach leer.
--
-- Der Gewinn ist größer als nur die Bedienung: Eine gewogene Palette liefert
-- ihr Eingangsgewicht *exakt* mit. Bisher musste die Auswertung die Masse
-- hinter einer gezählten Palette über Mittelwerte schätzen.
-- =====================================================================

alter table auftrag_palette
  add column if not exists wiegung_id bigint references verdunstung_wiegung(id) on delete set null;

comment on column auftrag_palette.wiegung_id is
  'Verweist auf die Wägung derselben Palette, falls sie beim Zählen gewogen wurde. '
  'Dann ist ihr Eingangsgewicht bekannt statt geschätzt.';

create index if not exists auftrag_palette_wiegung on auftrag_palette (wiegung_id);

-- Wie viele Kürbisse in einer Kiste liegen. Freiwillig, aber die einzige
-- Angabe, die aus dem Palettengewicht ein Durchschnittsgewicht je Kürbis
-- macht — auf der Hand-Linie gibt es keine Sortier-CSV, die das liefert.
alter table verdunstung_wiegung
  add column if not exists kuerbisse_pro_kiste int check (kuerbisse_pro_kiste > 0);


-- =====================================================================
-- aus 0013_ausgang_und_abbruch.sql
-- =====================================================================

-- =====================================================================
-- 0013 — Fertige Paletten wiegen, und Arbeiten abbrechen können
--
-- TEIL A — Die fertige Palette
--
-- Nach dem Waschen entstehen neue Paletten; die Ware landet nicht wieder in
-- derselben. Interessant ist dort eine einzige Zahl: Wie viel Kürbis liegt
-- wirklich in einer Kiste?
--
--   Soll:  Palette + 32 Kisten × Tara + 32 × 8 kg
--   Ist:   Palette + 32 Kisten × Tara + 32 × x     →  x = ?
--
--   x = (Brutto − Palettentara − Kisten × Kistentara) / Kisten
--
-- Bezahlt wird ein Fixpreis je Kiste ab 8 kg. Jedes Kilo über x = 8 ist
-- verschenkte Ware und gehört ins Marge-Buch (Spec §2, Buch B) — niemals ins
-- Verlust-Buch, denn die Ware ist verkauft.
--
-- TEIL B — Abbrechen
--
-- Eine Arbeit wird mit der falschen Charge eröffnet, ein Handy fällt aus, es
-- kommt etwas dazwischen. Bisher liess sich so ein Auftrag nicht loswerden.
--
-- Gelöscht wird dabei bewusst nicht sofort: verdunstung_wiegung und
-- sortier_lauf hängen mit "on delete set null" am Auftrag. Ein Löschen würde
-- die Wägungen verwaist zurücklassen — und sie zählten weiter in die
-- Verdunstungsrate, ohne dass irgendwo stünde, wozu sie gehörten. Genau die
-- Sorte Phantom-Daten, die es zu vermeiden gilt.
-- =====================================================================

-- ---------- Teil B: Abbruch-Kennzeichen -----------------------------------
alter table auftrag add column if not exists abgebrochen_ts timestamptz;
alter table auftrag add column if not exists abbruch_grund  text;

comment on column auftrag.abgebrochen_ts is
  'Gesetzt = die Arbeit wurde verworfen. Die erfassten Zeilen bleiben stehen, '
  'zählen aber in keiner Auswertung mehr. So bleibt nachvollziehbar, dass hier '
  'etwas passiert ist, ohne dass es das Ergebnis verfälscht.';

create index if not exists auftrag_aktiv on auftrag (charge_nr) where abgebrochen_ts is null;

-- ---------- Teil A: die fertige Palette -----------------------------------
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

-- ---------- Abbrechen und endgültig löschen -------------------------------
-- Abbrechen behält die Zeilen, nimmt sie aber überall aus der Rechnung.
-- Eine zugeordnete Sortier-CSV wandert zurück in die Warteschlange, sonst
-- hinge sie an einer Arbeit, die es nicht mehr gibt.
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

comment on function auftrag_abbrechen is
  'Verwirft eine Arbeit. Die Erfassungen bleiben als Spur stehen, zählen aber '
  'nirgends mehr mit; zugeordnete Sortier-CSVs gehen zurück in die Warteschlange.';

-- Endgültig löschen darf nur der Betriebsleiter. Wichtig sind die beiden
-- Tabellen mit "on delete set null": Ohne dieses Aufräumen blieben ihre Zeilen
-- verwaist zurück und zählten weiter mit, ohne dass jemand sähe, wozu sie gehören.
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

-- ---------- Plausibilitäts-Schwelle nachgeschärft --------------------------
-- 90 % waren zu lasch: Ein Zahlendreher (450 → 4500 kg) landete bei 87 % und
-- rutschte durch. Über die Hälfte einer Palette als Schimmel ist entweder ein
-- Tippfehler oder eine Katastrophe — beides gehört dem Betriebsleiter gemeldet,
-- und beides würde den Koeffizienten beherrschen, wenn es mitgerechnet würde.
create or replace function anteil_plausibel(p_anteil numeric)
returns boolean language sql immutable as $$
  select p_anteil is not null and p_anteil >= 0 and p_anteil <= 0.5;
$$;

-- ---------- Indizes für die Auswertungspfade ------------------------------
create index if not exists palette_charge_netto on palette (charge_nr, eingangsdatum, gebindeart);
create index if not exists schimmel_auftrag on schimmel_messung (auftrag_id) where gemessen;
create index if not exists ausschuss_auftrag on ausschuss_messung (auftrag_id, art) where gemessen;
create index if not exists verdunstung_auftrag on verdunstung_wiegung (auftrag_id) where gemessen;
create index if not exists sortier_lauf_auftrag on sortier_lauf (auftrag_id) where auftrag_id is not null;


-- =====================================================================
-- aus 0016_auswertung_speichern.sql
-- =====================================================================

-- =====================================================================
-- 0016 — Die Auswertung einmal rechnen, nicht bei jedem Hinschauen
--
-- Das Feilen an einzelnen Abfragen (0015) hat das Symptom verschoben, nicht
-- die Ursache beseitigt. Gemessen an einem Lasttest mit 5 040 Paletten,
-- 840 Arbeiten und 255 300 Gewichtsstufen — rund dem Dreifachen einer echten
-- Saison — brauchten die zwölf Dashboard-Ansichten zusammen 4.1 Sekunden.
-- Auf Supabases geteilter CPU wäre das ein Abbruch, und mit jeder weiteren
-- Palette würde es schlimmer.
--
-- Der Grund ist die Bauart: Die Auswertung ist ein tiefer Baum, der bei jedem
-- Lesen von den Rohdaten aufwärts komplett neu gerechnet wird. v_kaskade
-- allein steckt in drei Dashboard-Ansichten und wurde dreimal gerechnet.
--
-- Eine Saisonauswertung ist aber keine Live-Anzeige. Sie darf ein paar Minuten
-- alt sein. Deshalb werden die drei teuren Knoten jetzt als materialisierte
-- Ansichten gespeichert und auf Knopfdruck neu berechnet:
--
--   mv_sortier_lauf_masse   verdichtet 255 000 Gewichtsstufen auf 300 Zeilen
--   mv_auftrag_masse        verdichtet die Palettenzählungen auf 840 Zeilen
--   mv_kaskade              die eigentliche Hochrechnung
--
-- Die gewohnten Namen (v_…) bleiben und zeigen jetzt auf die gespeicherten
-- Daten. Damit gibt es weiterhin genau eine Wahrheit: App, SQL-Editor und
-- Prüfabfragen sehen dasselbe.
--
-- Nebenwirkung, die man kennen muss: Nach einer Erfassung ist die Auswertung
-- erst nach dem nächsten Berechnen aktuell. Die App zeigt den Stand an und
-- meldet, wenn seither etwas erfasst wurde.
-- =====================================================================

-- ---------- Stand der Auswertung -----------------------------------------
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

-- Jede Erfassung meldet, dass die Auswertung veraltet ist. Auf Anweisungsebene
-- statt je Zeile: Ein Import mit 500 Paletten löst so einen Aufruf aus, nicht 500.
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

-- Gefüllt wird hier nicht (0056): setup.sql rechnet die gespeicherten
-- Auswertungen einmal am Ende mit den heutigen Formeln, nicht in jeder
-- Zwischenfassung auf den echten Daten. Die Ansichten oben sind deshalb
-- ohne Inhalt angelegt (with no data).


-- =====================================================================
-- aus 0017_schimmelmodell.sql
-- =====================================================================

-- =====================================================================
-- 0017 — Die Schimmelkurve als Verderbsmodell statt als Treppe
--
-- Gemessen mit dem Simulations-Harness (supabase/test/simulation): Saisons
-- mit selbst gesetzter Wahrheit (λ = 1.07e-5, k = 1.6) durchlaufen die
-- Pipeline, danach steht fest, wie weit sie danebenlag (Verzerrung) und wie
-- oft der ausgewiesene Bereich den wahren Wert enthielt (Überdeckung). Ein
-- Bereich, der 95 % heissen soll, muss in rund 95 % der Saisons treffen.
--
--   Lage                              Verzerrung   Überdeckung
--   Saisonende, 25 % im Lager            −6.2 %        70 %
--   mitten in der Saison, 50 % im Lager  −46.3 %         0 %
--
-- Drei Ursachen, alle nachgewiesen, alle hier behoben.
--
-- ---------- 1. Flach fortschreiben ist keine Projektion -------------------
-- Für Lagerdauern ohne Messung schrieb v_schimmel_kurve den letzten
-- bekannten Wert fort. Derselbe Datenstand, Wahrheit daneben gestellt:
--
--   Lagertage   Wahrheit   Treppenfunktion   Modell (dieses hier)
--        30       0.25 %        0.23 %             0.25 %
--        90       1.42 %        1.19 %             1.52 %
--       150       3.19 %        2.03 %             3.48 %
--       210       5.41 %        2.03 %             5.97 %
--                               ↑ flach ab 120 Tagen
--
-- Und genau dort liegt die Masse: mitten in der Saison 341.8 t Lagerbestand
-- mit 167–201 Tagen Alter — jenseits der längsten je gemessenen Lagerdauer
-- (113 Tage). Die Treppe gab dieser Hälfte der Ernte den Schimmelanteil kurz
-- gelagerter Ware. Spec §9 verlangt ausdrücklich, rechts-zensierte Ware zu
-- projizieren; flach fortschreiben ist keine Projektion, sondern eine
-- Weigerung.
--
-- Statt dessen ein Verlaufsmodell:  F(t) = 1 − exp(−λ · t^k)
--
-- Die übliche Weibull-Form für Verderbsprozesse; k > 1 heisst, die Rate
-- steigt mit der Lagerdauer — genau das beobachtet man bei Kürbissen.
-- Logarithmiert wird daraus eine Gerade,
--
--   ln(−ln(1 − F)) = ln λ + k · ln t
--
-- also eine gewichtete lineare Regression, die Postgres selbst rechnet.
-- Gewichtet mit der Masse hinter der Messung: 20 t wiegen schwerer als 800 kg.
--
-- ---------- 2. Rücktransformation aus dem Log-Raum ------------------------
-- exp() des Mittelwerts im Log-Raum ergibt den *geometrischen* Mittelwert,
-- nicht den arithmetischen. Wo die Anfälligkeit der Paletten streut, ist das
-- systematisch zu wenig. Nachgemessen:
--
--   Duans Smearing-Faktor  S = Σ w·exp(Residuum) / Σ w = 1.0781
--   Normal-Näherung        exp(σ²/2)                   = 1.0714
--
-- Beide sagen dasselbe, die Log-Residuen sind also brauchbar normal. +7.8 %
-- gegen die verbliebenen −6.1 % Verzerrung: das ist der fehlende Betrag.
-- Genommen wird Duan, weil er ohne Verteilungsannahme auskommt.
--
-- ---------- 3. 339 Messungen sind nicht 339 -------------------------------
-- Die Beobachtungen liegen in 12 Chargen. Innerhalb einer Charge sind sie
-- ähnlich — gleicher Schlag, gleiche Ernte, gleiches Lager —, zwischen
-- Chargen nicht. Wer sie als unabhängig zählt, rechnet sich die Sicherheit
-- schön. An denselben Daten:
--
--                           naiv    chargen-robust   Faktor
--   Standardfehler von k   0.0016        0.0509        31×
--   Standardfehler Achse   0.0202        0.0241       1.2×
--
-- Die Steigung ist der springende Punkt, denn sie bestimmt genau das, was
-- jenseits des gemessenen Bereichs passiert. 31× zu klein heisst: dort, wo
-- der Bereich am meisten gebraucht wird, war er um mehr als eine
-- Grössenordnung zu eng.
--
-- Ersetzt durch den chargen-robusten Sandwich-Schätzer: die gewichteten
-- Residuen werden je Charge aufsummiert, und die Streuung *dieser Summen*
-- ist der Fehler. Dazu die t-Verteilung mit C−1 Freiheitsgraden statt 1.96 —
-- bei zwölf Gruppen ist die Normalverteilung eine Behauptung, keine Näherung.
-- =====================================================================

-- ---------- t-Quantil, zweiseitig 95 % ------------------------------------
-- Postgres bringt keine t-Verteilung mit. Tabelle für kleine Freiheitsgrade,
-- darüber die Normalverteilung — ab df ≈ 30 ist der Unterschied unter 5 %.
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


-- =====================================================================
-- aus 0020_lagerkontrolle.sql
-- =====================================================================

-- =====================================================================
-- 0020 — Die eine Messung, die das Modell wirklich braucht
--
-- Nach 0017–0019 trifft die Auswertung in fast allen Lagen. Ein Fall bleibt,
-- und es ist der realistischste (25 Saisons, 50 % im Lager, „Schlechtes
-- zuerst" verarbeitet):
--
--   Schimmel/Fäulnis   Verzerrung −13.0 %   Überdeckung 8 %
--
-- Das ist die Selektionsverzerrung aus Punkt 7 der Überprüfung, und sie ist
-- strukturell: Wer schlecht aussieht, kommt zuerst dran. Anfällige Paletten
-- werden also bei *kurzer* Lagerdauer gemessen, robuste erst spät. Der
-- gemessene Verlauf wird dadurch flacher als der wahre — und je weiter
-- extrapoliert wird, desto stärker schlägt das durch.
--
-- Aus Schimmelmessungen an verarbeiteter Ware allein ist das nicht zu
-- beheben: Alter und Anfälligkeit sind durch die Verarbeitungsreihenfolge
-- vermengt, und keine Statistik trennt, was die Daten nicht trennen. Was hilft,
-- ist eine Messung, deren Auswahl *nicht* am Zustand hängt:
--
--   Ab und zu eine zufällig gegriffene Palette im Lager aufmachen und
--   notieren, wie viel davon faul ist.
--
-- Dafür braucht es keinen neuen Bildschirm. Paletten werden ohnehin
-- gelegentlich gewogen; die Wägung bekommt ein zusätzliches Feld „davon
-- faul (kg)". Ein Wert mehr auf einer Maske, die es schon gibt.
--
-- Diese Punkte gehen mit demselben Gewicht in dieselbe Regression wie die
-- Messungen aus der Verarbeitung — nur sind sie nicht danach ausgewählt, wie
-- die Palette aussah.
-- =====================================================================

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


-- =====================================================================
-- aus 0027_palox_stand.sql
-- =====================================================================

-- =====================================================================
-- 0027 — Der Arbeiter liest ab, die Software rechnet
--
-- Der Palox mit dem Faulen steht auf einer Waage und läuft über mehrere
-- Arbeiten weiter. Bisher musste der Arbeiter selbst die Differenz zum
-- letzten Mal bilden und nur diese eintragen.
--
-- Das ist genau die Sorte Schwierigkeit, an der Erfassung scheitert: Er muss
-- sich merken oder nachschlagen, was vorher draufstand, im Kopf abziehen, und
-- ein Rechenfehler ist hinterher nicht mehr erkennbar — die Differenz sieht
-- aus wie jede andere Zahl.
--
-- Jetzt trägt er ein, was auf der Waage steht. Die Differenz bildet die
-- Software, zeigt sie ihm an, und beide Zahlen bleiben erhalten: der Stand
-- als Beleg, die Differenz als Messwert. Wer später nachrechnen will, kann es.
--
-- Wird der Palox zwischendurch geleert, fällt der Stand. Dann ist der neue
-- Stand selbst die Menge seit dem Leeren — die Software erkennt das und sagt
-- es dem Arbeiter, statt eine negative Menge zu buchen.
-- =====================================================================

alter table schimmel_messung
  add column if not exists palox_stand_kg numeric(8,2)
    check (palox_stand_kg is null or palox_stand_kg >= 0);

comment on column schimmel_messung.palox_stand_kg is
  'Was auf der Palox-Waage stand, als diese Menge gebucht wurde. kg ist die '
  'daraus gebildete Differenz zum vorherigen Stand — beides wird behalten, '
  'damit sich der Wert nachrechnen lässt.';

-- ---------- Der letzte Stand, für die Eingabemaske ------------------------
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


-- =====================================================================
-- aus 0028_warenausgang.sql
-- =====================================================================

-- =====================================================================
-- 0028 — Der Warenausgang, ohne den die Bilanz keine ist
--
-- Spec §188 sieht ausdrücklich vor: „Massenbilanz Eingang vs. Verkauf +
-- Verlust + Restbestand als Check". Der Verkauf ist nie gebaut worden.
-- Ohne ihn prüft v_massenbilanz nur, ob die Koeffizienten die Masse am
-- Sortierband treffen — über die Verluste sagt sie nichts, und der
-- Restbestand ist eine Hochrechnung, die niemand je nachgezählt hat.
--
-- Was dafür nötig ist, steht ohnehin auf jedem Lieferschein, weil danach
-- verrechnet wird: Datum, Sorte, und entweder Kilo oder Kistenzahl.
-- Palettengewichte braucht es nicht — die kennt der Betrieb gar nicht.
--
-- Kisten werden über das gemessene Kilo je Kiste umgerechnet
-- (v_ausgang_kennzahl aus 0013, aus fertig gepackten Paletten). Die
-- zusätzliche Unsicherheit dieser Umrechnung wird mitgeführt und ausgewiesen,
-- statt sie zu verschweigen.
--
-- Ein Ziel je Lieferung, weil nicht alles Verkauf ist: Was an Tiere geht,
-- ist kein physischer Verlust im Sinne von Buch A, sondern ein anderer Kanal;
-- was kompostiert wird, ist echter Verlust. Beides verschwand bisher
-- vollständig aus der Rechnung — und fehlende Masse sieht in einer Bilanz
-- immer aus wie Verlust.
-- =====================================================================

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
  -- Entweder Kilo oder Kisten — mindestens eines von beiden.
  kg          numeric(12,2) check (kg is null or kg > 0),
  kisten      int           check (kisten is null or kisten > 0),
  gebindeart  text        references gebinde(art) on update cascade,
  ziel        text        not null default 'verkauf' references ausgang_ziel(code),
  kunde       text,
  erfasser    uuid        not null default auth.uid() references profil(id),
  ts          timestamptz not null default now(),
  bemerkung   text,
  constraint lieferung_menge check (kg is not null or kisten is not null),
  -- Ohne Sorte oder Charge lässt sich nichts zuordnen.
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


-- =====================================================================
-- aus 0032_palox_je_station.sql
-- =====================================================================

-- =====================================================================
-- 0032 — Der Palox-Stand gehört zur Station, nicht zum Betrieb
--
-- Der Palox mit dem Faulen steht auf einer Waage; der Arbeiter liest den
-- Stand ab, die Software bildet die Differenz zum letzten Mal (0027). Der
-- Betrieb hat zwei Dinge klargestellt, die diese Rechnung bisher übersah:
--
-- 1. „Das letzte Mal" war global. Sortierband, Waschbecken und Hand-Linie
--    sind aber verschiedene Arbeitsplätze mit je eigenem Sammelbehälter —
--    niemand trägt einen Palox samt Waage durch die Halle. Liefen zwei
--    Linien gleichzeitig, verzahnten sich ihre Ablesungen und jede Differenz
--    war falsch. Der Stand wird jetzt je Station geführt.
--
--    (Annahme dahinter, in docs/ABLAUF.md vermerkt: je Station genau ein
--    Palox. Sollten zwei Teams an derselben Station parallel arbeiten,
--    bräuchte es eine Behälter-Kennung — das wäre ein Feld mehr für den
--    Arbeiter und wird erst gebaut, wenn der Betrieb sagt, dass es vorkommt.)
--
-- 2. Zwischen zwei Ablesungen kann der Palox geleert worden sein. Fällt der
--    Stand, merkt die Software das selbst. Wird er aber geleert und danach
--    ÜBER den alten Stand hinaus neu befüllt, sieht die Zahlenreihe harmlos
--    aus und die Differenz unterschlägt still die entsorgte Menge. Dagegen
--    hilft nur der Arbeiter: ein Kennzeichen „war zwischendurch leer", das
--    die Rechnung auf den vollen Stand umstellt. Das Kennzeichen wird
--    gespeichert, damit jede Menge nachrechenbar bleibt.
--
-- Was der Betrieb ausserdem angeregt hat — die Palettenzahl der Arbeit als
-- Prüfgrösse — passiert in der Eingabemaske: Sie zeigt die Differenz sofort
-- als „kg je Palette" und warnt, wenn das unplausibel gross wird. Meist
-- heisst das: eine Ablesung wurde vergessen, und die Menge zweier Arbeiten
-- ist auf einer gelandet.
-- =====================================================================

alter table schimmel_messung
  add column if not exists palox_geleert boolean not null default false;

comment on column schimmel_messung.palox_geleert is
  'Der Arbeiter hat den Palox seit der letzten Ablesung geleert. Dann ist der '
  'neue Stand selbst die Menge — auch wenn er über dem alten liegt.';

-- ---------- Der letzte Stand, je Station ----------------------------------
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

-- Und für alles, was danach noch angelegt wird: Ohne diese Zeile bekäme jede
-- Funktion aus einer späteren Migration wieder das Standardrecht für PUBLIC —
-- die Prüfung würde es finden, aber erst beim nächsten Testlauf, nicht beim
-- Anlegen. Gilt für die Rolle, die setup.sql einspielt.
alter default privileges in schema public revoke execute on functions from public;


-- =====================================================================
-- aus 0036_kette.sql
-- =====================================================================

-- =====================================================================
-- 0036 — Die Kette: was erfasst wird, kommt an — und was fehlt, ist unbekannt
--
-- Gefunden beim Rückwärtsgehen von jeder Dashboard-Zahl bis zur Rohzeile.
-- Sechs Befunde, alle am laufenden System nachgemessen, alle hier behoben.
--
-- ---------- 1. Ohne Wägung stand die Verdunstung auf 0 kg — mit Bereich ---
-- v_koeff_verdunstung lieferte coalesce(mittel, 0): Gab es in der ganzen
-- Datenbank keine einzige Palettenwägung, hiess der Koeffizient 0, und die
-- Kaskade rechnete damit weiter. Im Ranking stand dann
--
--   Verdunstung   0.00 kg   Bereich 0.00 – 0.00 kg
--
-- Das ist eine Zahl, die aussieht wie gemessen, und sie sagt das Gegenteil
-- der Wahrheit: „kein Verlust" statt „nicht gemessen". Dasselbe bei Ausschuss
-- und Nebenkanal ohne Sortier-CSV und ohne Handmessung. Leer ist nicht null —
-- die Regel galt für Tara und Messwerte, für die Koeffizienten galt sie nicht.
--
-- Jetzt bleibt ein Koeffizient ohne Messung NULL. Die Kaskade rechnet die
-- Masse weiter, als würde nichts abgezogen (etwas Besseres gibt es nicht),
-- aber der Strom selbst ist NULL und das Ranking sagt „nicht gemessen".
--
-- ---------- 2. Messungen ohne Nenner verschwanden spurlos -----------------
-- Ein Auftrag mit 80 kg Schimmel, bei dem niemand Paletten gezählt hat, und
-- ein Waschgang mit 112 kg Schimmel ohne verarbeitete Menge: beide erzeugen
-- keinen Punkt im Verderbsmodell, und keine Ansicht meldete es.
--
--   erfasst 242 kg  →  angekommen 50 kg
--
-- Das ist die Fehlerart, die in diesem Projekt schon zweimal vorkam (Schimmel
-- #2 vor 0024). v_plausibilitaet listet solche Arbeiten jetzt auf, mit dem
-- Rat, was nachzutragen ist. Ebenso Palettenwägungen, die nicht verwertbar
-- sind (Tara fehlt, Datum verkehrt), ohne dass sichtbar Faules der Grund war.
--
-- ---------- 3. Die Palox-Waage zeigt brutto, und der Behälter wiegt 45 kg --
-- Vom Betrieb bestätigt (2. September). Bei der Differenz zweier Stände kürzt
-- sich das Leergewicht weg. Nach dem Leeren und bei der ersten Ablesung einer
-- Station galt aber der volle Stand als Menge — samt Behälter. Jedes Leeren
-- buchte 45 kg Schimmel, die keiner war. Die Tara steht jetzt als Einstellung
-- (palox_tara_kg) und wird dort abgezogen, wo der Stand selbst die Menge ist.
--
-- Dazu die Regel aus docs/Datenarchitektur: gespeichert wird, was beobachtet
-- wurde — der Waagenstand. Die Menge ist Ableitung. Wo ein Stand erfasst ist,
-- rechnet die Auswertung ab jetzt mit der aus den Ständen abgeleiteten Menge
-- (v_schimmel_menge), nicht mit dem Kilo-Wert, den die App damals daraus
-- gebildet hat. Ändert sich die Tara, ändert sich die Menge mit — der Stand
-- bleibt, wie er abgelesen wurde.
--
-- ---------- 4. Der Lagerbestand bekam das Alter der ganzen Charge ----------
-- alter_lager = Stichtag − massegewichtetes Eingangsdatum aller Paletten der
-- Charge. Die noch liegenden Paletten sind aber nicht „alle": Wird zuerst
-- verarbeitet, was zuletzt kam (gestapeltes Lager — der Betrieb hat gesagt,
-- man kommt nicht an jede Palette), sind die übrigen die ältesten. In der
-- Demo-Saison lagen die restlichen Paletten drei bis sechs Tage neben dem
-- Chargenmittel. Bei k = 1.6 sind fünf Tage auf 180 rund 4.5 % Verderb —
-- systematisch, nicht zufällig. Die Eingangsdaten der gezählten Paletten
-- sind bekannt (Pflichtfeld). Also wird das Alter jetzt aus den *nicht
-- gezählten* Paletten gebildet; erst wenn keine Zählung ein Datum trägt,
-- gilt wieder das Chargenmittel.
--
-- ---------- 5. Der Restbestand war zu klein, die Lücke zu gross ----------
-- v_saisonbilanz rechnete den Restbestand als „verkaufsfähig" der liegenden
-- Ware — also nach Abzug von zu klein und zu gross, die aber erst beim
-- Verarbeiten aussortiert werden und heute noch physisch im Lager liegen.
-- In der Demo fehlten so 12.5 t im Bestand, und die Lücke enthielt sie als
-- „unerklärt". Der Restbestand ist jetzt die Masse nach Verdunstung und
-- Verderb (m2), ohne die Aufteilung, die noch gar nicht stattgefunden hat.
--
-- ---------- 6. Die Kistenzahl der Überfüllung war fest verdrahtet ---------
-- v_marge_buch teilte die Weg-2-Masse durch 8.0, die Kennzahl je Palette las
-- aber die Einstellung soll_kg_pro_kiste. Stellt der Betriebsleiter 9 ein,
-- ergab das −15 t „Überschuss" aus 21 739 Kisten, die es nie gab. Jetzt
-- liest beides dieselbe Einstellung.
--
-- Was ausserdem auffiel und mitgeht: v_koeff_ueberfuellung lieferte double
-- precision, und round(sd, 3) scheiterte im SQL-Editor (Regel aus 0014);
-- v_saisonbilanz gab ungerundete numerics mit 190 Nachkommastellen aus.
-- =====================================================================

-- ---------- 3. Palox-Tara als Einstellung ---------------------------------
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


-- =====================================================================
-- aus 0038_sortierschema.sql
-- =====================================================================

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

-- ---------- Klassierung nach einer Fassung ---------------------------------
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

-- Die alte Signatur bleibt: Sorte → Standard-Fassung von heute. Für Tests,
-- Simulation und alles, was keinen Käufer kennt.
create or replace function klassiere(p_sorte text, p_gewicht_g int)
returns table (klasse kuerbis_klasse, kaliber_idx int)
language sql stable as $$
  select * from public.klassiere(public.sortierschema_fuer(p_sorte, null, current_date), p_gewicht_g);
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


-- =====================================================================
-- aus 0039_auftrag_angabe.sql
-- =====================================================================

-- =====================================================================
-- 0039 — Antworten sind Messwerte
--
-- Beim Abschliessen einer Arbeit wird der Arbeiter etwas gefragt, das keine
-- Bedienlogik ist, sondern eine Aussage über die Verlässlichkeit einer
-- anderen Messung: „War alles aus einer Charge?" Bei Nein weiss niemand, wie
-- alt die Ware im Palox war — die Messung darf dann nicht in das Verderbs-
-- modell, das aus Alter und Anteil eine Kurve macht. In der Massenbilanz
-- zählt sie weiter, denn Masse ist Masse.
--
-- Solche Fragen werden sich ändern; es kommen neue dazu und alte fallen weg.
-- Für jede eine Spalte anzulegen hiesse, mitten in der Saison die Datenbank
-- umbauen. Deshalb eine Tabelle mit Schlüssel und Wert — bewusst nur für
-- Antworten, über die nicht gerechnet und nicht verknüpft wird
-- (docs/Datenarchitektur, Regel 2). Eine Antwort wird nie überschrieben; wer
-- sich korrigiert, antwortet nochmal, und es gilt die letzte.
--
-- Schlüssel, die die App heute schreibt:
--   eine_charge    'true' | 'false'   War alles aus einer Charge?
--   gleiche_sorte  'true' | 'false'   Wenn nicht: wenigstens dieselbe Sorte?
--   sortierdatum   'JJJJ-MM-TT'       Beim Waschen: Datum auf der Kaliber-Kiste
-- =====================================================================

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

-- ---------- Das Ende einer Arbeit setzt der Server ---------------------------
-- Fund beim Nachspielen der Masken: Die App schickte beim Abschliessen
-- ende_ts von der Uhr des Handys. Geht die Uhr auch nur eine Minute nach
-- (oder wurde die Arbeit eben erst eröffnet), verletzt das die Regel
-- ende_ts >= start_ts, und der Arbeiter kann die Arbeit nicht abschliessen —
-- mit einer Meldung, die ihm nichts sagt. Für das Abbrechen war genau das in
-- 0013 schon bedacht, für das Abschliessen nicht. Spec §10 verlangt
-- Server-Zeit; jetzt gilt sie an beiden Enden.
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


-- =====================================================================
-- aus 0041_gebinde.sql
-- =====================================================================

-- =====================================================================
-- 0041 — Die Kiste ist am Waschbecken die Einheit, und ihr Gewicht wird
--        gemessen, nicht geschätzt
--
-- Der Betrieb hat am 3. September zwei Dinge entschieden.
--
-- ---------- 1. Das Datum vom Zettel ist Pflicht --------------------------
-- Beim Palettenzählen war es freiwillig. Steht es nicht da, rechnet die
-- Auswertung das Alter des Lagerbestands mit dem Mittel der ganzen Charge —
-- in der Demo drei bis sechs Tage daneben (0036, Befund 4). „Zwing sie",
-- sagt der Betrieb, und damit ist es eine Pflichtangabe.
--
-- Die Bedingung wird als NOT VALID angelegt: Neue Zeilen brauchen ein Datum,
-- bestehende behalten ihre Lücke. Sie nachträglich mit einem gefolgerten
-- Datum zu füllen hiesse, eine Beobachtung zu erfinden, die niemand gemacht
-- hat (docs/Datenarchitektur, Regel 3).
--
-- ---------- 2. Am Waschbecken werden Kisten gezählt ----------------------
-- Am Waschbecken kennt die Auswertung die verarbeitete Menge nicht: Die
-- Palette ist beim Sortieren in Kaliber-Kisten aufgelöst worden, ein Kürbis
-- einer Palette liegt in fünf Kisten und eine Kiste hält Ware aus mehreren
-- Paletten. Ohne Menge hat der dort ausgelesene Schimmel keinen Nenner und
-- fällt aus der Rechnung („Ohne Nenner", 0036).
--
-- Gewogen wird auf Weg 1 nie. Die Einheit, die es dort gibt, ist die Kiste.
-- Also:
--
--   * Wer die Arbeit eröffnet, trägt ein, welches Kaliber gewaschen wird.
--     Das ist in der Regel die Person mit dem besten Überblick, und es ist
--     eine Angabe je Arbeit statt eine je Kiste.
--   * Wer an der Station steht, zählt nur: wie viele Kisten, und das Datum.
--   * Was eine Kiste wiegt, wird nicht geschätzt und nicht gewogen, sondern
--     am Sortieren gemessen. Dort ist die Masse je Kaliber aus der CSV
--     bekannt (die Maschine wiegt jeden Kürbis), und die gefüllten Kisten
--     werden ebenfalls gezählt. Aus beidem folgt kg je Kiste je Kaliber —
--     mit Streuung über die Läufe, also mit einem Bereich.
--
-- Damit bleibt die Regel gewahrt: Gespeichert wird die Zählung, das Gewicht
-- der Kiste ist Ableitung. Ändert sich die Messung, ändert sich die Masse
-- mit; die gezählte Zahl bleibt, wie sie gezählt wurde.
--
-- Gibt es für ein Kaliber noch keine einzige Messung, bleibt die Masse NULL
-- — nicht 0. Der Waschgang steht dann weiter unter „Ohne Nenner", jetzt aber
-- mit dem Hinweis, dass die Kistenzählung beim Sortieren fehlt.
--
-- Annahme, die dabei mitgeht: Eine Kiste, die beim Sortieren gefüllt wurde,
-- kommt als dieselbe Kiste ans Waschbecken. Wird zwischendurch umgepackt
-- oder zusammengeschüttet, stimmt das Kistengewicht nicht mehr — das steht
-- als Annahme in ABLAUF.md und als Frage 13 in FRAGEN.md.
-- =====================================================================

-- ---------- 1. Das Datum ist Pflicht -------------------------------------
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

-- ---------- 2. Welches Kaliber gewaschen wird ----------------------------
alter table auftrag add column if not exists kaliber_idx int;
comment on column auftrag.kaliber_idx is
  'Beim Waschen: welches Kaliberband aus dem Sortierschema der Arbeit gewaschen '
  'wird (Index in kaliber_baender). Trägt ein, wer die Arbeit eröffnet. NULL an '
  'allen anderen Stationen.';
alter table auftrag drop constraint if exists auftrag_kaliber_nur_waschen;
alter table auftrag add constraint auftrag_kaliber_nur_waschen
  check (kaliber_idx is null or station = 'waschen') not valid;

-- ---------- 3. Die Zählung ------------------------------------------------
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
-- Eine Zählung ist eine Zahl, die man hochzählt und korrigiert, keine Messreihe:
-- Der Erfasser darf seine eigene Zahl ändern, solange die Arbeit läuft.
create policy gebinde_aendern on auftrag_gebinde for update to authenticated
  using ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
create policy gebinde_loeschen on auftrag_gebinde for delete to authenticated
  using ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
grant select, insert, update, delete on auftrag_gebinde to authenticated;
grant usage, select on sequence auftrag_gebinde_id_seq to authenticated;

drop trigger if exists auftrag_gebinde_veraltet on auftrag_gebinde;
create trigger auftrag_gebinde_veraltet after insert or update or delete on auftrag_gebinde
  for each statement execute function auswertung_veraltet();


-- =====================================================================
-- aus 0042_suchpfad.sql
-- =====================================================================

-- =====================================================================
-- 0042 — Funktionen dürfen sich nicht auf den Suchpfad verlassen
--
-- Beim Einrichten in Supabase brach setup.sql ab:
--
--   ERROR: relation "einstellung" does not exist
--   QUERY: select coalesce((select (wert #>> '{}')::numeric from einstellung …
--   CONTEXT: SQL function "palox_tara_kg" during inlining
--
-- Der Grund ist eine Eigenheit von Postgres, die man leicht übersieht. Der
-- Rumpf einer SQL-Funktion ist Text. Beim Planen einer Abfrage setzt Postgres
-- ihn ein („inlining") und löst die Namen darin **in diesem Moment** auf, mit
-- dem Suchpfad der aufrufenden Sitzung. In einer Ansicht steht der Verweis auf
-- die Funktion dagegen als feste Kennung — die Ansicht findet die Funktion
-- also immer, und erst der Rumpf fällt auf die Nase.
--
-- Läuft das Skript in einer Sitzung, deren Suchpfad `public` nicht enthält —
-- und der SQL-Editor mancher Anbieter tut genau das —, dann kennt der Rumpf
-- die Tabelle nicht, obwohl sie zwei Bildschirmseiten weiter oben angelegt
-- wurde. Lokal fiel das nie auf, weil psql `public` im Pfad hat.
--
-- Zwei Antworten darauf, je nachdem, was die Funktion kostet:
--
--   * Wo die Funktion je Zeile eingesetzt wird (palox_tara_kg in v_palox_stand,
--     klassiere je Gewichtsstufe, schimmelanteil in den Kaskaden-Ansichten),
--     stehen die Tabellen jetzt mit `public.` davor. Das Einsetzen bleibt
--     erlaubt, das Tempo also auch.
--   * Alle übrigen bekommen einen festen Suchpfad. Das verhindert das
--     Einsetzen — bei einer Funktion, die einmal je Abfrage läuft, ist das
--     kein Verlust, und es macht sie ein für alle Mal unabhängig davon, wer
--     sie aufruft.
--
-- Der Prüflauf fährt seither die ganze Kaskade einmal mit leerem Suchpfad
-- durch. Wäre das früher dagewesen, hätte der Fehler den Betrieb nie erreicht.
-- =====================================================================

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


-- =====================================================================
-- aus 0043_sortierart_je_arbeit.sql
-- =====================================================================

-- =====================================================================
-- 0043 — Wie sortiert wird, entscheidet die Arbeit, nicht die Stammdaten
--
-- Der Betrieb am 3. September: „manchmal tun wir einfach Kisten mit 8 kg,
-- manchmal ist dort das Kistengewicht egal, stattdessen machen wir von Hand
-- Kaliber." Und dazu, wie es abläuft: Bei „Waschen + Sortieren" geht die Ware
-- durch eine Trommel auf ein Band, und dort sortieren die Arbeiter nach den
-- Regeln, die beim Eröffnen der Arbeit festgelegt werden. Beim Sortieren an
-- der Maschine läuft es nach der hinterlegten Fassung — auch dort soll beim
-- Eröffnen noch einmal bestätigt werden.
--
-- Bisher hing die Art (`kaliber` oder `kiste`) an (Sorte × Käufer × Datum).
-- Ein eindeutiger Index liess für dieselbe Sorte und denselben Käufer nur
-- **eine** Fassung je Stichtag zu — beides gleichzeitig zu hinterlegen war
-- also gar nicht möglich, geschweige denn, es je Arbeit zu wählen.
--
-- Was das kostet, hängt an der Klassierung: Die Sortier-CSV wird nach der
-- Fassung der Arbeit klassiert. Lief eine Arbeit als „Kiste ab x kg", ist aber
-- `kaliber` hinterlegt, wandert alles unterhalb der Kaliber-Untergrenze in den
-- Strom „Zu klein (Tierfutter)" — ein ganzer Balken im Dashboard, aus einer
-- Regel, die an dem Tag nicht galt. Umgekehrt verschwindet er ganz.
--
-- Deshalb:
--   * Der Index umfasst jetzt auch die Art. Eine Sorte darf für denselben
--     Käufer beide Fassungen gleichzeitig führen. Der Betrieb hält es für
--     unwahrscheinlich, dass beides am selben Tag vorkommt — gebaut ist es
--     trotzdem so, damit die Frage nicht wieder aufkommt.
--   * `sortierschema_fuer` bekommt eine Fassung mit Art. Ohne Art bleibt es
--     bei „die zuletzt gültige", damit alles Bestehende weiterläuft.
--   * Je Sorte gibt es ab jetzt auch eine Kisten-Standardfassung. Ihr
--     Sollgewicht kommt aus der Einstellung `soll_kg_pro_kiste` — demselben
--     Wert, mit dem die Auswertung schon bisher gerechnet hat. Das ist keine
--     erfundene Zahl, sondern dieselbe an einem besseren Ort. Ohne diese
--     Fassung könnte der Arbeiter „Kiste" gar nicht erst wählen.
--
-- ---------- Und die Kehrseite: keine Kiste, keine Überfüllung -------------
-- Die Überfüllung ist die verschenkte Marge, wenn in eine Kiste, die als
-- 8-kg-Kiste verkauft wird, 8.3 kg wandern. Wird nach Kaliber sortiert, gibt
-- es kein Sollgewicht je Kiste — und damit auch nichts zu verschenken. Bisher
-- rechnete die Auswertung trotzdem, weil sie ohne Kisten-Fassung auf die
-- globale Einstellung zurückfiel. Ab jetzt zählt für die Überfüllung nur die
-- Masse aus Arbeiten, die wirklich als „Kiste ab x kg" liefen.
-- =====================================================================

-- ---------- 1. Beide Arten dürfen nebeneinander stehen -------------------
drop index if exists sortierschema_eindeutig;
create unique index if not exists sortierschema_eindeutig
  on sortierschema (sorte, coalesce(kaeufer, ''), art, gilt_ab);

-- ---------- 2. Je Sorte auch eine Kisten-Fassung --------------------------
insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
select sk.sorte, null, date '2000-01-01', 'kiste',
       coalesce((select (wert #>> '{}')::numeric from public.einstellung
                  where schluessel = 'soll_kg_pro_kiste'), 8),
       'Standard beim Einrichten — Sollgewicht aus der Einstellung. '
       'Echtes Sollgewicht je Sorte: neue Fassung anlegen, nicht diese ändern.'
  from sorte_kaliber sk
 where not exists (select 1 from sortierschema s
                    where s.sorte = sk.sorte and s.kaeufer is null and s.art = 'kiste');

-- ---------- 3. Die Fassung zu einer Art ----------------------------------
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

-- ---------- 8. Der alte Drei-Argument-Aufruf wird eindeutig --------------
-- sortierschema_fuer(sorte, kaeufer, datum) ohne Art gibt es weiter — die
-- Klassierung und der Auslöser fallen darauf zurück, wenn die App keine
-- Fassung nennt. Mit zwei Arten je Sorte war „die zuletzt gültige" aber nicht
-- mehr eindeutig. Historisch gab es nur Kaliber; genau das bleibt die
-- Vorgabe, damit keine bestehende Arbeit still die Art wechselt.
create or replace function sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date)
returns bigint language sql stable as $$
  select public.sortierschema_fuer(p_sorte, p_kaeufer, p_datum, 'kaliber');
$$;

-- Und der Auslöser reicht die Art durch, wenn die App eine nennt (über die
-- Fassung, die sie schickt). Nennt sie keine, bleibt es bei Kaliber.
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


-- =====================================================================
-- aus 0044_ausschuss_wiegen.sql
-- =====================================================================

-- =====================================================================
-- 0044 — Ausschuss wird gewogen, nicht geschätzt
--
-- Der Betrieb am 1. September: Der Ausschuss (zu klein, zu gross) soll
-- gewogen werden — auf eine Palette stellen, Kistenzahl und Gewicht erfassen —
-- statt ihn nach Augenmass zu schätzen. Bisher trug die Maske nur ein Kilo-
-- Feld, in das jemand eine geschätzte Zahl schrieb.
--
-- Erfasst wird ab jetzt wie bei der fertigen Palette: das Bruttogewicht auf
-- der Waage, die Zahl der Kisten und die Gebindeart. Das Netto ist Ableitung —
-- brutto minus Kisten-Tara minus Paletten-Tara. Damit gilt auch hier die
-- Regel: gespeichert wird, was beobachtet wurde (der Waagenstand), gerechnet
-- wird das Netto.
--
-- Die geschätzte Eingabe bleibt möglich (kg direkt), für die Fälle, in denen
-- nicht gewogen werden kann. Die Spalte `gemessen` unterscheidet beides schon
-- immer; neu ist, dass eine echte Wägung dahinterstehen kann.
--
-- Technisch: kg bleibt die Spalte, die alle Auswertungen lesen — sie wird zur
-- abgeleiteten Grösse, sobald ein Bruttogewicht da ist, gesetzt von einem
-- Auslöser. Ohne Brutto bleibt kg die eingetippte Schätzung. Ändert sich
-- später eine Gebinde-Tara, stimmt ein alt gespeichertes Netto nicht mehr mit
-- dem Brutto überein — genau wie beim Palox macht das eine Plausibilitäts-
-- zeile sichtbar, statt es still zu lassen.
-- =====================================================================

alter table ausschuss_messung add column if not exists brutto_kg    numeric(10,2);
alter table ausschuss_messung add column if not exists kisten       int;
alter table ausschuss_messung add column if not exists gebindeart   text references gebinde(art);
comment on column ausschuss_messung.brutto_kg is
  'Waagenstand der Ausschuss-Palette (brutto). Ist er gesetzt, ist kg das '
  'daraus abgeleitete Netto; sonst ist kg die eingetippte Schätzung.';

-- Netto ableiten, sobald brutto da ist.
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


-- =====================================================================
-- aus 0045_kontrolle_auswahl.sql
-- =====================================================================

-- =====================================================================
-- 0045 — Die Lagerkontrolle hält fest, wie die Palette ausgewählt wurde
--
-- Der Betrieb: Das Lager ist gestapelt, man kommt nicht an jede Palette. „Nimm
-- irgendeine" ist damit nicht durchführbar. Was bleibt, ist das Ehrliche: eine
-- zufällige unter den heute erreichbaren — und die App soll festhalten, dass es
-- so war. Damit ist die Messung nicht frei von Auswahl, aber ihre Auswahl ist
-- wenigstens bekannt und nicht am Zustand der Ware orientiert.
--
-- Die Auswahlart steht als Spalte an der Lagerkontrolle. Die ehrliche Vorgabe
-- ist „zufällig unter den erreichbaren"; „aus der Mitte/unten gegriffen" ist
-- besser (weniger an die Erreichbarkeit gebunden), „gezielt" ist die Warnung,
-- dass nach Aussehen gewählt wurde — solche Kontrollen taugen für die
-- Selektionsprüfung nicht und werden dort später ausgenommen.
-- =====================================================================

alter table verdunstung_wiegung
  add column if not exists auswahl text
  check (auswahl is null or auswahl in ('erreichbar_zufaellig', 'mitte_unten', 'gezielt'));
comment on column verdunstung_wiegung.auswahl is
  'Nur bei der Lagerkontrolle gesetzt: wie die Palette gegriffen wurde — '
  'erreichbar_zufaellig (ehrliche Vorgabe), mitte_unten (besser), gezielt '
  '(nach Aussehen, für die Selektionsprüfung untauglich).';


-- =====================================================================
-- aus 0046_fax.sql
-- =====================================================================

-- =====================================================================
-- 0046 — Fax ist ein eigener Arbeitsgang
--
-- Der Betrieb (2. September): „Fax" ist immer ein eigener Arbeitsgang nach
-- Bestellung; tagsüber wird provisorisch vorgewaschen. Diese Arbeiten sind
-- fachlich ein Waschgang, gehören aber getrennt gezählt — sonst verschwinden
-- sie in den regulären Wascharbeiten oder werden gar nicht erfasst.
--
-- Deshalb eine Markierung an der Arbeit, nicht eine neue Station: fachlich
-- bleibt es ein Waschgang (Station waschen), damit die ganze Massenkaskade
-- unverändert rechnet. `ist_fax` trennt die Fax-Arbeiten für die Erfassung
-- und spätere Auswertung, ohne das Modell anzufassen.
-- =====================================================================

alter table auftrag add column if not exists ist_fax boolean not null default false;
comment on column auftrag.ist_fax is
  'Fax-Arbeit: eigener Waschgang nach Bestellung. Fachlich ein Waschgang '
  '(Station waschen), nur für die Erfassung getrennt gehalten.';


-- =====================================================================
-- aus 0047_erfassungsbeginn.sql
-- =====================================================================

-- =====================================================================
-- 0047 — Erfassungsbeginn: was vor der App schon rausging
--
-- Der Betrieb (1. September): Die Saison lief bereits, als die App kam — ein
-- Teil der Ernte lag schon, ein Teil war schon ausgeliefert, ohne dass die App
-- es gesehen hat. Ohne diese Angabe behauptet die Massenbilanz eine Lücke, die
-- keine ist: Der Eingang zählt die ganze Charge, der Ausgang aber nur, was seit
-- dem Erfassungsbeginn erfasst wurde.
--
-- Deshalb:
--   * einstellung 'erfassungsbeginn' — ab wann die App mitzählt. Nur zur
--     Anzeige und als Erinnerung; die Bilanz rechnet mit der Zahl unten.
--   * charge_vorlauf — je Charge, wie viel Masse vor dem Erfassungsbeginn schon
--     ausgeliefert wurde. Eine grobe Angabe des Betriebsleiters, kein Messwert
--     aus der App; sie steht getrennt und wird als solche ausgewiesen.
--
-- Die Massenbilanz zählt diesen Vorlauf zum erfassten Ausgang. Damit misst die
-- Lücke wieder das Modell und die Erfassung, nicht den Umstand, dass die App
-- mitten in der Saison dazukam.
-- =====================================================================

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


-- =====================================================================
-- aus 0048_ballast.sql
-- =====================================================================

-- =====================================================================
-- 0048 — Ballast abwerfen
--
-- Der Rundgang aus der Vogelperspektive (docs/archiv/PROMPT_ABSCHLUSS.md)
-- fand Objekte, die kein Bildschirm liest, keine Ansicht braucht und höchstens
-- ein Test noch anfasst. Jedes wurde vorher belegt: pg_depend kennt keinen
-- Leser, kein Funktionsrumpf nennt es, src/ greift nicht darauf zu. Was hier
-- fällt, steht weiter in Git (0006, 0022, 0026, 0037, 0043, 0044) — wer die
-- Frage eines Tages wieder stellt, findet die Abfrage dort.
--
--   marge_messung           Alt-Kanal für von Hand eingetippte Marge-Posten.
--                           Die App schrieb ihn nur in den ersten Stunden des
--                           25. August (10b8a3f → a1a6cd5); seither kommt die
--                           Überfüllung aus ausgang_wiegung, der Nebenkanal aus
--                           der CSV. Hält die Tabelle trotzdem Zeilen, bricht
--                           diese Datei ab — nichts, was jemand gemessen hat,
--                           verschwindet still.
--   v_verdunstung_stichprobe  seit 0018 (gepoolte Koeffizienten) ohne Leser.
--   v_sortier_kuerbis       Expansion des Histogramms je Kürbis — nur ein Test
--                           las sie; der rechnet jetzt direkt mit sum(anzahl).
--   v_dubletten_pruefung, v_schlag_effekt  Prüfbare Annahmen aus 0022. Drei
--                           Migrationen mussten sie mitpflegen, gelesen hat sie
--                           nie jemand. Der Befund steht in STATISTIK_BEFUND.md.
--   v_auftrag_sortierart    0043, nie angebunden.
--   v_ausschuss_pruef       0044 — die Prüfung ist richtig, nur der Ort war
--                           falsch: sie steht jetzt als Zeile „Ausschuss-Tara"
--                           in v_plausibilitaet, wo der Betriebsleiter sie sieht.
--   schimmel_n(numeric)     Aus 0006 für den alten Rechenweg; seit 0036 nennt
--                           ihn keine Ansicht mehr.
-- =====================================================================

-- ---------- 1. Wächter: keine Messung geht still verloren -------------------
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

-- ---------- 3. Abwerfen -------------------------------------------------------
drop table if exists marge_messung;
drop type  if exists marge_art;

-- ---------- 4. Ein Satz statt eines Absatzes --------------------------------
-- Die beim Einrichten angelegten Kisten-Fassungen trugen eine vierzeilige
-- Bemerkung, die auf dem Handy die ganze Karte füllte. Die Bemerkung ist eine
-- Notiz, kein Messwert — sie darf kürzer werden.
update sortierschema
   set bemerkung = 'Standard beim Einrichten — Sollgewicht aus der Einstellung. '
                || 'Echtes Sollgewicht je Sorte: neue Fassung anlegen, nicht diese ändern.'
 where bemerkung like 'Beim Einrichten aus der Einstellung soll_kg_pro_kiste übernommen%';


-- =====================================================================
-- aus 0050_warenausgang_import.sql
-- =====================================================================

-- =====================================================================
-- 0050 — Warenausgang aus dem Warenwirtschaftssystem einlesen
--
-- Der Betrieb führt seine Lieferscheine in Perigon. Zweimal im Jahr — oder
-- wöchentlich — zieht er dort die Auswertung „Abgleich Rückverfolgbarkeit"
-- als Excel-Datei und lädt sie hier hoch. **Immer die ganze Datei**, nie nur
-- die neuen Zeilen: die App muss selbst erkennen, was sie schon kennt.
--
-- Und es sind zwei Dateien, weil der Betrieb zwei Firmen hat (docs/
-- WARENAUSGANG_BEFUND.md): eine liefert an Coop und Migros, die andere an den
-- Grosshandel. Beide führen Kürbis, beide zählen in dieselbe Bilanz, ihre
-- Positionsnummern sind aber je Firma vergeben — deshalb hängt alles hier an
-- einer *Quelle*.
--
-- AUFBAU
--
--   ausgang_quelle   Die Firma (Mandant), aus deren Perigon die Datei kommt.
--   ausgang_datei    Eine hochgeladene Datei, mit Prüfsumme: dieselbe Datei
--                    zweimal hochzuladen ist erlaubt und folgenlos.
--   ausgang_zeile    Die Rohzeilen, wie sie in der Datei standen — eine Zeile
--                    je Charge-Zuordnung einer Lieferscheinposition. Das ist
--                    die Wahrheit, aus der alles Weitere folgt.
--   ausgang_artikel  Welcher Artikel ist Kürbis, und welche Sorte ist er?
--                    Vom Betriebsleiter bestätigt, nicht geraten.
--   lieferung_import Welche Lieferung aus welcher Importzeile stammt. Die
--                    Lieferungen selbst landen in `lieferung`, wo die
--                    Auswertung sie ohnehin sucht.
--
-- WARUM DIE ROHZEILEN BLEIBEN
--
-- Ohne sie liesse sich beim nächsten Hochladen nicht sagen, was neu ist — die
-- Datei enthält jedes Mal alles. Und eine Zeile, die der Betrieb im Perigon
-- korrigiert, muss hier als Änderung sichtbar werden und nicht als zweite
-- Lieferung. Der Fingerabdruck macht das billig: gleicher Schlüssel, gleicher
-- Fingerabdruck heisst „schon gesehen, nichts zu tun".
-- =====================================================================

-- ---------- 1. Woher die Datei kommt --------------------------------------
create table if not exists ausgang_quelle (
  code              text primary key,
  name              text not null,
  -- Woran die App die Datei wiedererkennt (Kleinschreibung, Teilzeichenkette).
  dateiname_muster  text,
  aktiv             boolean not null default true,
  bemerkung         text,
  erfasser          uuid references profil(id) default auth.uid(),
  ts                timestamptz not null default now()
);

comment on table ausgang_quelle is
  'Die Firma, aus deren Warenwirtschaft eine Warenausgangsdatei kommt. '
  'Positionsnummern sind nur innerhalb einer Quelle eindeutig.';

-- ---------- 2. Eine hochgeladene Datei ------------------------------------
create table if not exists ausgang_datei (
  id                bigserial primary key,
  quelle            text not null references ausgang_quelle(code) on update cascade,
  dateiname         text not null,
  pruefsumme        text not null,             -- SHA-256 der Rohdatei
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

-- Dieselbe Datei nochmals: erkannt und folgenlos, nicht doppelt verarbeitet.
create unique index if not exists ausgang_datei_pruefsumme
  on ausgang_datei (quelle, pruefsumme);

comment on table ausgang_datei is
  'Jedes Hochladen mit Prüfsumme und Bilanz. Dieselbe Datei zweimal hochladen '
  'ist erlaubt: die Prüfsumme erkennt sie wieder.';

-- ---------- 3. Die Rohzeilen ----------------------------------------------
create table if not exists ausgang_zeile (
  id                 bigserial primary key,
  quelle             text   not null references ausgang_quelle(code) on update cascade,
  pos_id             bigint not null,          -- AufPosId: die Lieferscheinposition
  charge_extern      text   not null default '',
  -- Dieselbe Position kann dieselbe Charge zweimal nennen (kommt in den echten
  -- Dateien vor). Ohne Laufnummer verlöre eine der beiden Zeilen ihren Platz.
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

-- ---------- 4. Welcher Artikel ist Kürbis, und welche Sorte? --------------
-- Die Datei kennt Verkaufsartikel („Bio Kürbis Butternut Dem gross"), die
-- Auswertung kennt Sorten („Tiana"). Dazwischen liegt eine Übersetzung, die
-- nur der Betrieb kennt. Sie wird deshalb bestätigt und nicht geraten — die
-- App darf einen Vorschlag machen, aber sie schreibt ihn nicht als Wahrheit.
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

-- ---------- 5. Die Lieferung weiss, woher sie kommt ------------------------
-- Zwei Spalten an `lieferung` wären der kürzere Weg gewesen — und der falsche:
-- v_lieferung_masse liest die Tabelle mit `l.*`, und neue Spalten landen dort
-- mitten in der Sicht. Beim ersten Einrichten entstand sie vor der Spalte, beim
-- zweiten danach; der Fingerabdruck-Vergleich in run.sh fiel darüber, und
-- „create or replace" konnte es nicht richten (eine Sichtspalte lässt sich nicht
-- umbenennen). Gefunden von der Stufe, die genau dafür da ist.
--
-- Also eine Beitabelle: Woher eine Lieferung kommt, ist etwas *über* sie und
-- nicht Teil von ihr. Die Auswertung merkt davon nichts.
create table if not exists lieferung_import (
  lieferung_id bigint primary key references lieferung(id) on delete cascade,
  quelle       text   not null references ausgang_quelle(code) on update cascade,
  -- Quelle:Position:Charge:Lauf — dieselbe Datei nochmals hochladen trifft
  -- dieselbe Zeile und legt keine zweite Lieferung an.
  extern_id    text   not null unique,
  zeile_id     bigint references ausgang_zeile(id) on delete set null,
  ts           timestamptz not null default now()
);

create index if not exists lieferung_import_quelle on lieferung_import (quelle);

comment on table lieferung_import is
  'Welche Lieferung aus welcher Importzeile stammt. Von Hand erfasste '
  'Lieferungen stehen hier nicht — sie haben keine Kennung aus dem Perigon.';

-- ---------- 6. Rechte ------------------------------------------------------
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

-- ---------- 10. Die Auswertung merkt, dass neue Lieferungen da sind -------
-- lieferung hängt schon am Auslöser aus 0028; die Rohzeilen brauchen keinen:
-- aus ihnen rechnet keine gespeicherte Ansicht.


-- =====================================================================
-- aus 0051_fax_kaliber_alter.sql
-- =====================================================================

-- =====================================================================
-- 0051 — Vier Fehler aus der Halle: Fax, Kaliber am Start, Alter ohne
--        FIFO, und die Perigon-Nummer der Charge
--
-- Der Betrieb hat am 7. September vier Dinge klargestellt, die die App
-- bis hierher anders verstanden hatte.
--
-- ---------- 1. Fax ist kein Waschgang -------------------------------------
-- Beim Fax wird nicht gewaschen. Die gewaschene Ware steht in Kisten, bis
-- eine Bestellung kommt; dann werden Etiketten angebracht und dabei wird
-- nochmals Faules aussortiert. Am Ende weiss der Arbeiter zweierlei: wie
-- viele Kisten er gemacht hat („eine Palette mit 32 Kisten, dann noch 10")
-- und wie viel Faules dabei herauskam — gewogen, kistenweise, mit Gebinde
-- („2 Kisten mit 7.5 und 8.5 kg in G2"). Kein Palox, kein zu klein/zu gross.
--
-- Bis 0050 lief Fax als Waschgang (Station waschen, ist_fax). Das war
-- doppelt falsch: Die Fax-Masse zählte als *gewaschen* und schob damit die
-- Charge ein zweites Mal aus dem Lager, und das Faule ging als Punkt in die
-- Verderbskurve — obwohl es nichts mit der Lagerdauer zu tun hat, sondern
-- mit dem Waschen und dem Stehen danach (ABLAUF.md kannte das längst).
--
-- Jetzt: Fax bleibt an der Station waschen (kein neuer Enum-Wert — der wäre
-- in der einen Transaktion von setup.sql nicht verwendbar), aber überall,
-- wo Waschen gerechnet wird, ist Fax ausgenommen. Faules wird als Wägung
-- erfasst (brutto, Kisten, Gebinde, mit/ohne Palette), das Netto rechnet
-- ein Auslöser — dieselbe Regel wie beim Ausschuss (0044). Und Fax bekommt
-- den eigenen Strom, den ABLAUF.md verlangt: „Faul beim Abpacken", ein
-- Koeffizient je Sorte, bezogen auf die verkaufsfähige Masse, nicht auf die
-- Zeit. Er steht in Buch A, mit Bereich, mit Fehlerfortpflanzung.
--
-- ---------- 2. Die Maschine sortiert immer nach Kaliber -------------------
-- Die Frage „Kiste ab x kg oder Kaliber?" gibt es beim Sortieren nicht — die
-- Maschine kennt nur Bänder. Die Frage, die es gibt, ist: *welche* Bänder
-- sind heute eingestellt? Das fragt die App ab jetzt beim Eröffnen, mit der
-- letzten Einstellung als Vorschlag („wie zuletzt — übernehmen / anpassen").
-- Bei Waschen + Sortieren von Hand ebenso: Kiste ab x kg (welches x?) oder
-- Kaliber (welche Bänder?). Was der Vorarbeiter bestätigt, ist die Fassung,
-- nach der die Arbeit läuft; was er ändert, wird eine neue, datierte Fassung
-- (sortierschema_festlegen). Nichts wird überschrieben — ausser die Fassung
-- desselben Tages, denn zweimal am selben Tag ist dieselbe Einstellung.
--
-- ---------- 3. Es gibt kein FIFO ------------------------------------------
-- Der Eingang einer Charge verteilt sich über Wochen, der Ausgang auch, und
-- welche Palette wann drankommt, hängt davon ab, an welche man herankommt.
-- Gespeichert war das schon richtig: jede Palette mit ihrem Eingangsdatum,
-- jede gezählte Palette mit dem Datum vom Zettel. Gerechnet wurde aber mit
-- *einem* Alter je Charge — dem massegewichteten Mittel der übrigen
-- Paletten (0036). Bei einer Kurve, die mit dem Alter steiler wird, ist das
-- Mittel zu wenig: Der Bestand wird jetzt je Eingangstag geführt
-- (v_charge_kohorte: Paletten des Tages minus gezählte Paletten des Tages)
-- und die Kaskade rechnet den Lagerbestand je Kohorte mit ihrem eigenen
-- Alter. Aus „liegt seit 143 Tagen" wird „liegt seit 128–161 Tagen, 4
-- Eingangstage". v_naechste_charge rechnet ebenso je Kohorte.
--
-- ---------- 4. Die sechsstellige Chargennummer ist unsere -----------------
-- Die Planungsdatei des Betriebs führt je Schlag und Sorte beide Nummern:
-- die vierstellige (Bioprodukte) und die sechsstellige aus dem Perigon der
-- anderen Firma (AG). 232 von 236 Kürbiszeilen der AG-Datei seit Juli 2026
-- tragen eine Nummer aus dieser Liste — der Chargenbezug ist also da, er
-- war nur nicht hinterlegt. Ab jetzt steht die Perigon-Nummer an der Charge.
-- Eine Nummer (198976) steht in der Planung an zwei Chargen (1649 Butterkin
-- und 1650 Tiana, beide Rümlang Sauter); dort entscheidet der Artikel.
-- =====================================================================

-- ---------- 4. Perigon-Nummer je Charge ----------------------------------
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

-- ---------- Eine Palette sind 32 Kisten ----------------------------------
-- Aus der Planungsdatei („Anzahl Paletten à 32 G2"). Der Zähler beim Fax
-- bietet „+ 1 Palette" an und zählt damit diese Zahl Kisten.
insert into einstellung (schluessel, wert)
values ('kisten_pro_palette', '32'::jsonb)
on conflict (schluessel) do nothing;

-- ---------- 1a. Faules wird gewogen: Brutto, Kisten, Gebinde ------------
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

-- ---------- 1b. Kisten ohne Kaliber: Index −1 -----------------------------
-- Ware von der Hand-Linie („Kiste ab x kg") hat kein Kaliber. Wer sie beim
-- Fax zählt, zählt Kisten nach Sollgewicht — Index −1. Was so eine Kiste
-- wiegt, ist nicht das Soll, sondern die gewogene fertige Palette.
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

-- ---------- 2. Eine Fassung festlegen, beim Eröffnen -----------------------
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


-- =====================================================================
-- aus 0052_demo_saison.sql
-- =====================================================================

-- =====================================================================
-- 0052 — Die Demo-Saison, neu: so, wie die Daten wirklich kommen
--
-- Die alte Demo (0034) war eine Rechenübung: zehn Chargen, zwei Läufe je
-- Charge, ein Histogramm aus acht Gewichtsstufen, Waschen als eingetippte
-- Menge, Fax als Waschgang. Sie zeigte nicht, was das System seit 0041 bis
-- 0051 erfasst — und einiges davon falsch (die Gewichtsverteilung hatte acht
-- Balken, „liegt seit" eine Zahl).
--
-- Diese Saison ist ein Praxistest: Sie entsteht so, wie der Betrieb arbeitet.
--
--   * Die Chargen sind die der Planungsdatei 2026 (37 mit erwartetem Ertrag),
--     die Mengen auf die Hälfte verkleinert, damit der Knopf in wenigen
--     Sekunden fertig ist. Ernte je Charge in ihrer Erntewoche, an Werktagen,
--     über Tage bis Wochen verteilt — je grösser, desto länger.
--   * Eine Palette sind 30–34 G2-Kisten à 10.8–12.4 kg (Planung: „32 G2",
--     Sorte macht den Unterschied), brutto mit Kisten- und Palettentara.
--   * Kein FIFO: Ein Sortierlauf nimmt Paletten von dem Eingangstag, an den
--     man herankommt — abwechselnd vom jüngsten und vom ältesten Stapel.
--     Manche Chargen sind ganz verarbeitet, manche zur Hälfte, manche liegen
--     noch komplett.
--   * Weg 1 für Hokkaido, Mandarin, Butterkin, Kabocha: Sortieren an der
--     Maschine (CSV mit 150 Gewichtsstufen, Kisten je Kaliber gezählt, zwei
--     Palox-Ablesungen), Wochen später Waschen je Kaliber (geleerte Kisten
--     gezählt, Palox, fertige Palette), dann Fax je Bestellung (Kisten je
--     Kaliber, Faules kistenweise gewogen), dann Lieferungen an den Käufer.
--   * Weg 2 für Butternut: Waschen + Sortieren von Hand, als „Kiste ab 8 kg"
--     für Coop und Rathgeb, nach Kaliber für Migros — mit gewogener Palette
--     (Verdunstung), gewogenem Ausschuss (einer geschätzt), fertiger Palette
--     (überfüllt), dann Fax und Lieferung.
--   * Der Verderb folgt einer Weibull-Kurve je Sorte plus Sockel; die
--     Verdunstung einer Sortenrate mit Streuung je Palette; das Faule beim
--     Fax einem Anteil je Sorte.
--   * Lieferungen gehen über Wochen, verschränkt über Chargen — die eine wird
--     in sechs Teilen geliefert, die andere in zwei.
--   * Lagerkontrollen (zufällig erreichbar, Mitte-unten, gezielt), ein
--     Vorlauf, und die Sonderfälle, die es in jeder Saison gibt: eine
--     abgebrochene Arbeit, ein Zahlendreher, eine Arbeit ohne Ablesung, ein
--     Waschgang ohne gezählte Kisten, eine CSV in der Warteschlange, ein
--     Zetteldatum, das zu keiner Palette passt — und drei laufende Arbeiten
--     von heute (Waschen + Sortieren, Waschen, Fax), damit die Masken etwas
--     zu zeigen haben.
--
-- Alles ist deterministisch (kein random()): Zweimal laden gibt zweimal
-- dieselbe Saison. Die Demo spielt relativ zu heute (Ernte vor rund 200
-- Tagen), damit sie nicht altert; die Kalenderdaten sind deshalb verschoben.
-- =====================================================================

-- Die Demo legt vier Käufer an (Coop, Migros, Rathgeb, Bio Partner). Beim
-- Entfernen dürfen nur die wieder verschwinden, die sie selbst angelegt hat:
-- Wer „coop" schon vor der Demo im Stammdatenregister hatte, behält ihn.
-- Dieselbe Markierung wie überall sonst — DEMO in einer Bemerkung.
alter table kaeufer add column if not exists bemerkung text;
comment on column kaeufer.bemerkung is
  'Freitext zum Käufer. ''DEMO'' markiert die von der Demo-Saison angelegten '
  'Käufer, damit demo_daten_entfernen() nur diese wieder löscht.';

create or replace function demo_daten_laden()
returns text language plpgsql security definer set search_path = public as $fn$
declare
  v_anker date := current_date - 200;
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
    ('coop', 'Coop', 'DEMO'), ('migros', 'Migros', 'DEMO'),
    ('rathgeb', 'Rathgeb', 'DEMO'), ('biopartner', 'Bio Partner', 'DEMO')
  on conflict (code) do nothing;
  -- Coop nimmt Butternut in der 8-kg-Kiste; Migros will Kaori Kuri enger.
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'coop', v_anker + 20, 'kiste', 8, 'DEMO — Coop nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'coop' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'rathgeb', v_anker + 25, 'kiste', 8, 'DEMO — Rathgeb nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'rathgeb' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab, bemerkung)
  select 'Kaori Kuri', 'migros', v_anker + 60, 'kaliber', 600, '[[600,1000],[1000,1400],[1400,2000]]'::jsonb, 2000,
         'DEMO — Migros will Kaori Kuri in engeren Bändern (beim Eröffnen einer Arbeit geändert)'
   where not exists (select 1 from sortierschema where sorte = 'Kaori Kuri' and kaeufer = 'migros' and art = 'kaliber');
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
  insert into demo_charge (nr, kg, kw, anteil_verarbeitet) values
    (1598,  1600, 36, 1.00), (1601,  1300, 38, 0.00), (1607,  1400, 34, 1.00),
    (1605,   900, 34, 1.00), (1606,   600, 34, 1.00), (1611, 40000, 37, 0.55),
    (1613, 23000, 35, 0.85), (1612, 15000, 35, 0.70), (1614,  3600, 34, 1.00),
    (1615,  3400, 34, 1.00), (1616,  9000, 34, 0.80), (1617,  2600, 35, 1.00),
    (1618,  3800, 34, 1.00), (1619,  1700, 34, 1.00), (1620,  2300, 35, 0.60),
    (1646,  7600, 34, 0.75), (1647,  7500, 39, 0.30), (1623,  8700, 36, 0.65),
    (1624,  8400, 35, 0.80), (1625,  2800, 34, 1.00), (1626,  4300, 39, 0.00),
    (1627,  2600, 39, 0.50), (1648, 10200, 34, 0.90), (1628,  6900, 36, 0.60),
    (1649, 22000, 38, 0.45), (1650,  2200, 39, 0.00), (1651,  3100, 35, 1.00),
    (1630, 10300, 34, 0.95), (1631, 15000, 39, 0.20), (1633, 24000, 38, 0.40),
    (1634,  6200, 36, 0.70), (1635,  6200, 36, 0.85), (1636, 18000, 36, 0.60),
    (1637,  5000, 36, 0.70), (1638,  5000, 36, 0.35), (1632, 37000, 37, 0.50);
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
    kaeufer = case nr % 4 when 0 then 'coop' when 1 then 'migros' when 2 then 'rathgeb' else 'biopartner' end
   where sorte is not null;
  -- Demeter-Ware geht an Coop und Migros, Knospe an Rathgeb und Bio Partner —
  -- so steht es in der Verkaufsplanung.
  update demo_charge d set kaeufer = case when d.nr % 2 = 0 then 'coop' else 'migros' end
    from charge c where c.nr = d.nr and c.schlag in ('Illnau Bruno', 'Illnau Gross', 'Negi Thalheim', 'Slowgrow Uster',
                                                     'Gossau Eberhard', 'Bonomo', 'Daniel Böhler', 'Klaus Böhler', 'Andi Ball');

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
        exit when v_start > now() - interval '2 days';

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
                             kistensystem, soll_kg_pro_kiste, stueck_je_kiste)
        values (case when d.weg = 'maschine' then 'maschine' else 'hand' end::verarbeitungsweg,
                case when d.weg = 'maschine' then 'sortieren' else 'waschen_sortieren' end::station,
                d.nr, v_start,
                v_start + make_interval(mins => (240 + v_n * 14 + floor(v_zufall * 40)::int)),
                'abgeschlossen', v_kaeufer, v_schema, 'DEMO',
                case when d.weg = 'maschine' then null when v_art = 'kiste' then 'kiste_ab' else 'stueck' end,
                case when d.weg <> 'maschine' and v_art = 'kiste' then 8 end,
                case when d.weg <> 'maschine' and v_art = 'kaliber' then greatest(round(d.kg_kiste * 1000 / d.gramm)::int, 1) end)
        returning id into v_auftrag;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_auftrag, id from profil order by erstellt_ts limit (2 + (v_lauf % 2))
        on conflict do nothing;

        -- Paletten zählen — mit dem Datum vom Zettel; beim Waschen + Sortieren
        -- auch mit dem Gewicht vom Zettel (0060), damit der Palox einen Nenner hat.
        insert into auftrag_palette (auftrag_id, eingangsdatum, ts, brutto_zettel_kg)
        select v_auftrag, dp.datum, v_start + make_interval(mins => (10 + row_number() over (order by dp.id) * 12)::int),
               case when d.weg <> 'maschine' then (select pl.brutto_kg from palette pl where pl.id = dp.id) end
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
            null, format('demo-pruefsumme-%s', v_auftrag),
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
          insert into verdunstung_wiegung (auftrag_id, charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                           kisten, gebindeart, kuerbisse_pro_kiste, wiege_ts)
          values (v_auftrag, d.nr, p.datum, v_brutto,
                  round((p.netto * power(1 - d.r * (0.7 + 0.6 * v_zufall), v_start::date - p.datum) + p.kisten * 1.5 + 25) * 2) / 2.0,
                  p.kisten, 'G2', 4 + (d.nr % 3), v_start + interval '2 hours')
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
          insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart, ts)
          values (v_auftrag, 'zu_klein', v_klein + v_kisten_p * 1.5 + 25, v_kisten_p, 'G2', v_start + interval '6 hours');
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
  begin
    for l in select * from demo_lauf where art = 'kaliber' and exists (select 1 from auftrag a where a.id = demo_lauf.auftrag_id and a.station = 'sortieren') order by start_ts loop
      v_gewaschen := array[]::int[];
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_zufall := (hashtext(format('wasch-%s-%s', l.auftrag_id, v_i))::bigint & 2147483647)::numeric / 2147483647;
        -- Das letzte Band der späten Läufe wartet noch
        if l.kisten[v_i] = 0 or (v_i = array_length(l.kisten, 1) and l.start_ts > now() - interval '60 days') then
          v_gewaschen := v_gewaschen || 0; continue;
        end if;
        v_start := l.start_ts + make_interval(days => 6 + v_i * 5 + floor(v_zufall * 25)::int) + interval '1 hour';
        while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
        if v_start > now() - interval '1 day' then v_gewaschen := v_gewaschen || 0; continue; end if;
        v_kisten := l.kisten[v_i];
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx, sortierschema_id, bemerkung,
                             kistensystem, stueck_je_kiste)
        values ('maschine', 'waschen', l.nr, v_start,
                v_start + make_interval(mins => 90 + v_kisten * 5 + floor(v_zufall * 30)::int),
                'abgeschlossen', v_i - 1, (select sortierschema_id from auftrag where id = l.auftrag_id), 'DEMO',
                'stueck', greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1))
        returning id into v_neu;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_neu, id from profil order by erstellt_ts limit 2 on conflict do nothing;
        -- 0061: beim Waschen werden Paletten gezählt — das Sortierdatum vom
        -- Zettel und die Kisten je Palette (höchstens 32), so wie die Maske.
        insert into auftrag_palette (auftrag_id, sortierdatum, kisten)
        select v_neu, l.start_ts::date, least(32, v_kisten - (s - 1) * 32)
          from generate_series(1, ceil(v_kisten / 32.0)::int) s;
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
        insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, ts, kaliber_idx, kuerbisse_pro_kiste)
        values (v_neu, l.nr, round((32 * l.kg_je_kiste * (0.96 + 0.08 * v_zufall) + 32 * 1.5 + 25) * 2) / 2.0, 32, 'G2',
                v_start + interval '2 hours', v_i - 1,
                greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1));
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
          v_zufall := (hashtext(format('fax-%s-%s-%s', l.auftrag_id, v_i, v_j))::bigint & 2147483647)::numeric / 2147483647;
          -- Ein Teil der Ware wartet noch auf eine Bestellung
          if v_zufall < 0.12 then exit; end if;
          v_teil := least(v_rest, 32 * (1 + floor(v_zufall * 4)::int) + floor(v_zufall * 20)::int);
          v_start := l.start_ts + make_interval(days => 20 + v_i * 6 + v_j * 9 + floor(v_zufall * 12)::int) + interval '2 hours';
          while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
          exit when v_start > now() - interval '1 day';
          v_kaeufer := case when v_j % 3 = 0 then (case l.kaeufer when 'coop' then 'migros' when 'migros' then 'coop' when 'rathgeb' then 'biopartner' else 'rathgeb' end) else l.kaeufer end;
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
          v_kunde := case v_kaeufer when 'coop' then 'Coop Verteilzentrale' when 'migros' then 'Migros Ostschweiz'
                                    when 'rathgeb' then 'Rathgeb Bio' else 'Bio Partner Schweiz' end;
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
                                     kg_position, kg_charge, gebindeart, gebinde_menge, gebinde_inhalt, batch_gebinde, produzent)
          values ('DEMO', v_pos, l.nr::text, 1, 'demo-' || v_pos, v_lief_datum, 'Lieferschein', 'LS-' || (100000 + v_pos),
                  v_kunde, v_artikel_id, v_artikel, v_einheit, v_menge, v_gja, v_menge,
                  v_lief, v_lief, 'IFCO', v_teil, v_inhalt, v_teil, 'Demo-Hof')
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
      -- Jede 17. Arbeit hat die Ablesung zu Beginn vergessen — die Datenqualität zeigt es.
      if v_i % 17 <> 0 then
        insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert, ts)
        values (v.auftrag_id, 0, v_stand, false, v.start_ts + interval '10 minutes');
      end if;
      v_geleert := v_stand + v.kg > 800;
      if v_geleert then v_stand := palox_tara_kg(); end if;
      v_stand := v_stand + v.kg;
      update schimmel_messung
         set palox_stand_kg = v_stand, palox_geleert = v_geleert, ts = coalesce(v.ende_ts, v.start_ts + interval '5 hours') - interval '10 minutes'
       where id = v.id;
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
    for p in select * from demo_pal where not verarbeitet order by (hashtext('kontrolle-' || id)::bigint & 2147483647) loop
      v_i := v_i + 1;
      exit when v_i > 24;
      select * into d from demo_charge where nr = p.nr;
      v_zufall := (hashtext('kontr-' || v_i)::bigint & 2147483647)::numeric / 2147483647;
      v_tag := greatest(p.datum + 20, v_anker + 40 + v_i * 6);
      exit when v_tag >= current_date;
      v_tage := v_tag - p.datum;
      insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart,
                                       wiege_ts, bemerkung)
      values (p.nr, p.datum, p.netto + p.kisten * 1.5 + 25,
              round((p.netto * power(1 - d.r * (0.8 + 0.4 * v_zufall), v_tage) + p.kisten * 1.5 + 25) * 2) / 2.0,
              p.kisten, 'G2', v_tag::timestamptz + interval '10 hours', 'DEMO-KONTROLLE');
    end loop;
    raise notice 'Demo: Lagerkontrollen angelegt';
  end;

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
    perform csv_lauf_speichern(1619, 'DEMO-1619-ohne-arbeit', null, 'demo-pruefsumme-warteschlange',
      (v_anker + 130)::timestamptz + interval '13 hours', 'dateiname',
      '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
      420, 1, 3, 6,
      '[[800,40],[900,90],[1000,120],[1100,100],[1200,50],[1300,10]]'::jsonb);

    -- (6) Drei laufende Arbeiten von heute — damit die Masken nicht leer sind
    insert into auftrag (weg, station, charge_nr, start_ts, status, kaeufer, sortierschema_id, bemerkung,
                         kistensystem, soll_kg_pro_kiste)
    values ('hand', 'waschen_sortieren', 1631, now() - interval '2 hours', 'offen', 'coop',
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
    select 'maschine', 'waschen', l.nr, true, now() - interval '50 minutes', 'offen', 'migros', 'DEMO'
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

  drop table if exists demo_charge; drop table if exists demo_pal; drop table if exists demo_lauf;

  -- Die Auswertung wird hier absichtlich nicht neu gerechnet: Supabase gibt
  -- einem API-Aufruf acht Sekunden, und das Rechnen ist der teuerste Teil.
  -- Die App ruft auswertung_aktualisieren() gleich danach als eigenen
  -- Aufruf; demo_daten.sql tut dasselbe. Bis dahin steht die Auswertung als
  -- veraltet da — die Auslöser an den Tabellen haben das schon vermerkt.
  return (
    select format('Demo-Saison steht: %s Paletten in %s Chargen, %s Arbeiten (davon %s Fax), %s Sortierläufe, %s Lieferungen. '
                  || 'Eingang %s t. Jetzt in der App unter Überblick anschauen.',
                  (select count(*) from palette where extern_id like 'demo-%'),
                  (select count(distinct charge_nr) from palette where extern_id like 'demo-%'),
                  (select count(*) from auftrag where bemerkung = 'DEMO'),
                  (select count(*) from auftrag where bemerkung = 'DEMO' and ist_fax),
                  (select count(*) from sortier_lauf where datei_name like 'DEMO-%'),
                  (select count(*) from lieferung where bemerkung = 'DEMO'),
                  (select round(sum(eingang_netto_kg) / 1000, 1) from v_charge_rueckgrat))
  );
end $fn$;

comment on function demo_daten_laden is
  'Legt die erfundene Demo-Saison an (Aufträge mit bemerkung = ''DEMO'', Paletten mit extern_id ''demo-…'', Sortierdateien ''DEMO-…''). Echte Daten bleiben unberührt.';

grant execute on function demo_daten_laden() to authenticated;

comment on function demo_daten_laden is
  'Legt die erfundene Demo-Saison an (Aufträge mit bemerkung = ''DEMO'', Paletten mit extern_id ''demo-…'', Sortierdateien ''DEMO-…'', Lieferungen ''DEMO''). Echte Daten bleiben unberührt. Deterministisch.';
grant execute on function demo_daten_laden() to authenticated;


create or replace function demo_daten_entfernen()
returns text language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter entfernen.';
  end if;

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
    select format('Demo-Daten entfernt. Übrig: %s Paletten, %s Arbeiten, %s Sortierläufe.',
                  (select count(*) from palette),
                  (select count(*) from auftrag),
                  (select count(*) from sortier_lauf))
  );
end $fn$;

comment on function demo_daten_entfernen is
  'Löscht restlos alles, was demo_daten_laden() angelegt hat. Echte Daten bleiben unberührt — erkannt wird die Demo an bemerkung = ''DEMO'', extern_id ''demo-…'' und datei_name ''DEMO-…''.';

grant execute on function demo_daten_entfernen() to authenticated;

comment on function demo_daten_entfernen is
  'Löscht restlos alles, was demo_daten_laden() angelegt hat. Echte Daten bleiben unberührt — erkannt wird die Demo an bemerkung = ''DEMO'', extern_id ''demo-…'' und datei_name ''DEMO-…''.';
grant execute on function demo_daten_entfernen() to authenticated;


-- =====================================================================
-- aus 0053_zeitlimit.sql
-- =====================================================================

-- =====================================================================
-- 0053 — Das Zeitlimit für die Auswertung hochsetzen
--
-- Supabase gibt jeder Abfrage über die API ein Zeitlimit, je nach Rolle:
-- anon 3 Sekunden, authenticated 8 Sekunden. Das ist keine Frage des
-- Tarifs, sondern eine Einstellung an der Rolle — im Gratis-Tarif genauso
-- änderbar wie im bezahlten.
--
-- Acht Sekunden reichen für alles, was die Halle tut: eine Palette zählen,
-- eine Wägung eintragen, eine Arbeit abschliessen. Sie reichen nicht für
-- das, was danach kommt: auswertung_aktualisieren() rechnet in einem Zug
-- alle Sichten neu — Sortierläufe, Kaliberverteilung, Schimmelmodell,
-- Massenkaskade. Das ist ein Stapellauf über die ganze Saison, und er
-- wird mit jeder Charge länger, nicht kürzer. Auf einer kleinen Instanz
-- ist er schon bei der Demo-Saison über acht Sekunden.
--
-- Darum: 30 Sekunden für angemeldete Benutzer. Warum nicht mehr: Supabase
-- lässt für Dashboard- und Client-Abfragen höchstens 60 Sekunden zu, und
-- eine Abfrage, die eine halbe Minute hält, ist die Obergrenze dessen, was
-- ein Mensch vor dem Bildschirm noch als "es rechnet" durchgehen lässt.
-- Alles darüber wäre kein Zeitlimit-Problem mehr, sondern ein Zeichen,
-- dass die Rechnung selbst zu teuer geworden ist.
--
-- anon bleibt bei drei Sekunden. Wer nicht angemeldet ist, hat hier nichts
-- zu rechnen; ein knappes Limit ist dort eine Sicherung, keine Bremse.
-- =====================================================================

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

-- Die API-Schicht (PostgREST) liest die Rolleneinstellungen beim Start.
-- Ohne dieses Signal gälte das neue Limit erst nach dem nächsten Neustart.
-- NOTIFY an einen Kanal, auf dem niemand lauscht, ist ein Nichts — auf dem
-- Prüfstand also unbedenklich.
notify pgrst, 'reload config';


-- =====================================================================
-- aus 0054_eigenes_kaliber.sql
-- =====================================================================

-- =====================================================================
-- 0054 — Waschen: das Kaliber wählen oder ein eigenes angeben
--
-- Am Waschbecken kommen Kisten mit einem Etikett an. Meist steht darauf
-- eines der Bänder, mit denen die Maschine sortiert hat — dann wählt der
-- Vorarbeiter es aus der Liste. Manchmal steht etwas anderes darauf: die
-- Maschine war an dem Tag anders eingestellt, oder es ist Ware, die nie
-- über die Maschine ging. Dafür gab es bisher keinen Platz — die Arbeit
-- lief ohne Kaliber, und die gezählten Kisten hatten keinen Nenner.
--
-- Jetzt kann die Arbeit ein eigenes Band tragen: kaliber_von_g / kaliber_bis_g.
-- Die Kisten dazu werden unter Index −2 gezählt (wie −1 die Kisten nach
-- Sollgewicht). Was so eine Kiste wiegt, weiss die Auswertung nur, wenn
-- beim Sortieren je ein Band mit genau diesen Grenzen gezählt wurde —
-- sonst bleibt die Masse unbekannt, und die Plausibilität sagt es.
--
-- Die Bänder je Sorte kommen weiterhin aus der Vorgabe des Betriebs
-- (Spezifikation §6, sorte_kaliber → sortierschema) beziehungsweise aus der
-- Fassung des letzten Sortierlaufs der Charge. Sechs der elf Sorten haben
-- dort dieselben drei Bänder (600–1100–1600–2000) — das ist die Vorgabe,
-- kein Versehen; die Maske nennt jetzt, woher die Bänder kommen.
-- =====================================================================

-- ---------- 1. Die Spalten am Auftrag --------------------------------------
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

-- Kisten zum eigenen Kaliber: Index −2
alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_kaliber_gueltig;
alter table auftrag_gebinde add constraint auftrag_gebinde_kaliber_gueltig
  check (kaliber_idx >= -2);
comment on column auftrag_gebinde.kaliber_idx is
  'Index in kaliber_baender der Fassung der Arbeit. −1 = Kisten nach Sollgewicht '
  '(ohne Kaliber), wie sie von der Hand-Linie kommen. −2 = Kisten zum eigenen '
  'Kaliber der Arbeit (auftrag.kaliber_von_g/bis_g, 0054).';


-- =====================================================================
-- aus 0058_auswertung_haelt_stand.sql
-- =====================================================================

-- =====================================================================
-- 0058 — Eine einzelne unmögliche Zahl darf die Auswertung nicht sprengen
-- Kürbis-Verlust-Tracking
--
-- WAS PASSIERT IST
--
-- Nach 0056 und 0057 stand im Überblick weiterhin „numeric field
-- overflow", jetzt mit Namen: v_hochrechnung. Die Diagnose auf der
-- Betriebsdatenbank zeigte: Stand 0057, Verdunstungsrate in Ordnung
-- (0.000470 … 0.000475), Auswertung rechnet durch — aber v_saisonbilanz
-- und v_marge_buch scheitern. Es sind also nicht mehr die Rohdaten,
-- sondern die Sichten, die daraus Hochrechnung, Bereiche und Bilanz
-- machen.
--
-- Der Grund ist ein Bauprinzip, das sich als falsch erwiesen hat: Diese
-- Sichten casten berechnete Grössen hart auf numeric(14,2),
-- numeric(12,6) oder numeric(10,4). Ein solcher Cast ist eine
-- *Behauptung* über den Wertebereich. Trifft sie nicht zu — weil eine
-- Messung fehlt, ein Nenner winzig ist oder eine Varianz aus wenigen
-- Punkten gross wird —, dann bricht die ganze Sicht ab. Nicht die eine
-- Zahl fehlt, sondern der ganze Bildschirm bleibt leer. Das ist die
-- schlechteste aller Ausfallarten: Der Betriebsleiter sieht nichts und
-- kann nichts tun.
--
-- Zwei Beispiele, beide realistisch:
--   · luecke_anteil = (Eingang − Verlust − Ausgang − …) / Eingang, hart
--     auf numeric(10,4) (also unter 10^6). Ist der Wareneingang noch
--     nicht eingelesen, der Warenausgang aber schon, wird das Verhältnis
--     beliebig gross — und die Bilanz bricht ab, statt zu sagen, dass
--     der Eingang fehlt.
--   · kg_unten/kg_oben = Wert ± t · Streuung. Die Streuung kommt aus
--     einer Varianz; bei wenigen Messpunkten kann sie sehr gross werden.
--     Der Mittelwert ist dann noch brauchbar, der Bereich nicht — aber
--     abbrechen darf deswegen nichts.
--
-- WAS SICH ÄNDERT
--
-- 1. `zahl(wert, stellen, grenze)` rundet wie bisher, gibt aber NULL
--    statt eines Fehlers, wenn der Wert ausserhalb dessen liegt, was die
--    Spalte tragen kann. NULL heisst im ganzen Projekt „unbekannt", und
--    genau das ist es: Die Zahl ist nicht ermittelbar. Die App zeigt
--    dafür „—", der Rest des Bildschirms steht.
-- 2. Jeder Koeffizient in der Hochrechnung ist ein *Anteil* und wird auf
--    0 … 1 geklammert, jede Masse auf ≥ 0. Das ist keine Notbremse,
--    sondern die Physik: Ein Anteil über 1 oder eine negative Masse gibt
--    es nicht. Bisher war nur der Sockel a₀ ungeklammert.
-- 3. Die Plausibilität meldet den Fall, der hinter dem häufigsten
--    Verhältnis-Ausreisser steckt: Es sind Lieferungen erfasst, aber
--    (fast) kein Wareneingang. Dann fehlt das Erntejournal, und die
--    Bilanz kann gar nicht aufgehen.
--
-- Die Spaltentypen bleiben unverändert; nichts muss neu gebaut werden.
-- =====================================================================

create or replace function zahl(p_wert numeric, p_stellen int default 2,
                                p_grenze numeric default 1e11)
returns numeric language sql immutable parallel safe set search_path = public
as $$
  select case when p_wert is not null and abs(p_wert) < p_grenze
              then round(p_wert, p_stellen) end
$$;
comment on function zahl(numeric, int, numeric) is
  'Rundet auf p_stellen und gibt NULL, wenn der Wert nicht in die Zielspalte '
  'passt (0058). Eine einzelne unmögliche Zahl macht damit eine Spalte '
  'unbekannt, statt die ganze Sicht abbrechen zu lassen.';
revoke all on function zahl(numeric, int, numeric) from public;
grant execute on function zahl(numeric, int, numeric) to anon, authenticated;

-- Manche Zwischenwerte sind Gleitkomma (Koeffizienten-Grenzen, Anteile).
-- Ohne diese Fassung müsste an jeder Aufrufstelle ein Cast stehen, und genau
-- der wird beim nächsten Umbau vergessen.
create or replace function zahl(p_wert double precision, p_stellen int default 2,
                                p_grenze numeric default 1e11)
returns numeric language sql immutable parallel safe set search_path = public
as $$ select zahl(p_wert::numeric, p_stellen, p_grenze) $$;
revoke all on function zahl(double precision, int, numeric) from public;
grant execute on function zahl(double precision, int, numeric) to anon, authenticated;


-- =====================================================================
-- aus 0060_punktuell_erfasst_vollstaendig_gerechnet.sql
-- =====================================================================

-- =====================================================================
-- 0060 — Punktuell erfasst, vollständig gerechnet
-- Kürbis-Verlust-Tracking
--
-- WOZU DAS DA IST
--
-- Der Betrieb hat am 8. September klargestellt, was die App wissen kann und
-- was nicht: Vollständig sind nur der Wareneingang (Erntejournal) und der
-- Warenausgang (Lieferscheine). Was in der Halle passiert, wird punktuell
-- erfasst — vielleicht jede zehnte Arbeit. Aus Arbeiten kommen Raten,
-- nie Mengen. Bis 0059 teilte die Kaskade die Eingangsmasse trotzdem nach
-- den *gezählten* Arbeiten in „ausgelagert" und „im Lager" — eine Annahme,
-- die bei punktueller Erfassung schlicht falsch ist. Jetzt gilt:
--
--   im Lager = Eingang − das, was hinter den Lieferungen steckt.
--
-- Was hinter einer Lieferung steckt, rechnet die Kaskade rückwärts: die
-- gelieferte Masse geteilt durch den verkaufsfähigen Anteil bei dem Alter,
-- das die Ware am Liefertag hatte. Jeder Eingangstag einer Charge trägt
-- dazu seinen Anteil am Eingang bei — es gibt kein Zuerst-rein-zuerst-raus,
-- und die App weiss nicht, welche Palette gegangen ist.
--
-- Dazu, was die Halle wirklich hergibt (docs/ABLAUF.md, ABMACHUNGEN AB-23 ff.):
--   · Zwei Stationen: Sortiermaschine und Waschstrasse. „Waschen + Sortieren"
--     ist die Waschstrasse mit Sortieren am Band dahinter — derselbe Palox.
--   · Der Palox-Stand kann fallen (zwischendurch geleert). Der Arbeiter wird
--     nicht gefragt; die Menge dieser Arbeit ist dann unbekannt, nicht null.
--   · Am Ende jeder Arbeit nach dem Waschen wird gefragt, nach welchem System
--     die Kisten gefüllt werden: Kiste ab x kg, x Stück eines Kalibers, oder
--     anderes. Nur die ersten beiden sind rechenbar.
--   · Beim Waschen + Sortieren steht das Eingangsgewicht auf dem Zettel; es
--     wird abgelesen, damit der Palox eine Masse als Nenner hat.
--   · Fax gibt es nach beiden Wegen; gezählt werden Paletten als Gesamtzahl,
--     das Faule wird kistenweise gewogen, freiwillig die Tage seit dem Waschen.
--   · Beim Waschen aus Kaliber-Kisten steht das Sortierdatum auf der Kiste;
--     es wird je Kiste mitgezählt, „kein Datum" ist eine Antwort.
-- =====================================================================

-- ---------- 1. Zwei Stationen, ein Palox je Station ----------------------
-- Die Waschstrasse hat einen Palox — ob dahinter von Hand sortiert wird oder
-- nicht. Vor 0060 hatte „waschen_sortieren" einen eigenen Stand, und zwei
-- Ablesungen derselben Waage verzahnten sich zu falschen Differenzen.
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

-- ---------- 2. Was die Masken neu wissen wollen -------------------------
-- Das Kistensystem nach dem Waschen: Kiste ab x kg, x Stück eines Kalibers,
-- oder etwas anderes. Beim Waschen, Waschen + Sortieren und Fax gefragt.
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
-- Fax: die Palettenzahl als Gesamtzahl am Ende, und wie lange die Ware seit
-- dem Waschen stand (freiwillig).
alter table auftrag add column if not exists paletten_gesamt int
  check (paletten_gesamt >= 0);
alter table auftrag add column if not exists tage_seit_waschen int
  check (tage_seit_waschen >= 0);
comment on column auftrag.paletten_gesamt is
  'Fax: wie viele Paletten gemacht wurden, als Gesamtzahl am Ende eingetragen. '
  'Die Masse folgt aus der gemessenen Nettomasse einer fertigen Palette (0060).';
comment on column auftrag.tage_seit_waschen is
  'Fax, freiwillig: wie lange die Ware seit dem Waschen stand (Tage).';

-- Waschen + Sortieren: das Eingangsgewicht steht auf dem Zettel der Palette.
alter table auftrag_palette add column if not exists brutto_zettel_kg numeric(8,2)
  check (brutto_zettel_kg > 0);
comment on column auftrag_palette.brutto_zettel_kg is
  'Bruttogewicht vom Palettenzettel (Eingangsgewicht), beim Waschen + Sortieren '
  'abgelesen. Damit hat der Palox dieser Arbeit einen Nenner. Das Netto findet '
  'die Auswertung über die Palette im Wareneingang (gleiche Charge, gleiches '
  'Datum, gleiches Brutto), sonst über die mittlere Tara der Charge (0060).';

-- Waschen aus Kaliber-Kisten: das Sortierdatum steht auf der Kiste. Es wird
-- mitgezählt — je Kaliber und Datum ein Zähler; „kein Datum auf der Kiste"
-- ist eine Antwort, keine Lücke.
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

-- Ältere Wasch-Arbeiten hatten das Sortierdatum als Antwort am Abschluss.
update auftrag_gebinde g
   set sortierdatum = x.datum
  from (select distinct on (auftrag_id) auftrag_id, wert::date as datum
          from auftrag_angabe
         where schluessel = 'sortierdatum' and wert ~ '^\d{4}-\d{2}-\d{2}$'
         order by auftrag_id, ts desc) x
 where x.auftrag_id = g.auftrag_id and g.sortierdatum is null;

-- Fertige Palette bei Stück-Kisten: welches Kaliber, damit sich das Gewicht
-- mit der Erwartung aus der Sortier-CSV vergleichen lässt.
alter table ausgang_wiegung add column if not exists kaliber_idx int;
comment on column ausgang_wiegung.kaliber_idx is
  'Bei Stück-Kisten: das Kaliber der gewogenen Palette (Index in den Bändern der '
  'Fassung; −2 = eigenes Kaliber der Arbeit). Daraus die Erwartung je Kiste aus '
  'der Sortier-CSV (0060).';

-- Ältere Arbeiten, die ausdrücklich als „Kiste ab x kg" liefen, bekommen das
-- Kistensystem nachgetragen — das ist keine Annahme, die Fassung sagt es.
update auftrag a
   set kistensystem = 'kiste_ab', soll_kg_pro_kiste = s.soll_kg_pro_kiste
  from sortierschema s
 where s.id = a.sortierschema_id and s.art = 'kiste' and s.soll_kg_pro_kiste > 0
   and a.kistensystem is null;

-- ---------- 18c. Der JIT bremst diese Datenbank ----------------------------
-- Postgres übersetzt Ausdrücke einer Abfrage in Maschinencode, sobald der
-- Planer ihre Kosten über 100 000 schätzt. Die Sichten hier haben viele
-- Ausdrücke und wenige Zeilen: Das Übersetzen dauerte im Lasttest bis zu
-- einer Sekunde je Sicht (v_plausibilitaet 1.2 s statt 0.12 s), das Rechnen
-- fast nichts. PostgreSQL 19 schaltet den JIT aus demselben Grund
-- standardmässig ab. Hier als Einstellung der Datenbank — wo das nicht
-- erlaubt ist (fremd verwaltete Datenbank), bleibt es beim Hinweis; die
-- Sichten rechnen dann richtig, nur langsamer.
do $$
begin
  execute format('alter database %I set jit = off', current_database());
  raise notice 'JIT für die Datenbank % abgeschaltet (gilt ab der nächsten Verbindung).', current_database();
exception when others then
  raise notice 'JIT nicht abgeschaltet (%): die Auswertung rechnet richtig, nur langsamer.', sqlerrm;
end $$;


-- =====================================================================
-- aus 0061_bis_heute_und_gespeichert.sql
-- =====================================================================

-- =====================================================================
-- 0061 — Alles bis heute, die Prognose getrennt, das Rechenwerk gespeichert
--
-- Der Betrieb hat am 8. September gefragt, was „Verlust" heisst. Die
-- Antwort war unangenehm: Die Ware im Haus wurde bis zum Saisonende gealtert
-- (31. März), nicht bis heute — von 103 t „Verlust" waren 73 t eine Prognose
-- sieben Monate in die Zukunft, angezeigt wie ein Faktum. Ab jetzt gilt:
--
--   · Jede Zahl ist eine Zahl BIS HEUTE. Verlust bis heute, im Haus heute,
--     verkaufsfähig heute. Die Ware im Haus altert bis heute(), nicht weiter.
--   · Die Prognose ist eine eigene Reihe (erg_verlauf ab heute, gestrichelt),
--     nie in einer Kennzahl versteckt.
--   · Das Dashboard liest nur noch gespeicherte Ergebnisse (erg_*): klein,
--     indiziert, mit Statistik. Nichts, was die App lädt, rechnet beim Laden.
--     Auf Supabase liefen sieben live gerechnete Sichten ins Zeitlimit.
--   · Die Neuberechnung läuft in Schritten (auswertung_schritt), jeder kurz
--     genug für das Zeitlimit einer Verbindung; jeder Schritt analysiert seine
--     Sichten (materialized views bekommen sonst nie Statistiken).
--
-- Dazu aus dem Feedback: die Überfüllung aus den Verkaufsdaten (verkaufte
-- Kisten je Kistensystem, nichts mehr hochgerechnet), beim Waschen Paletten
-- mit Sortierdatum und Kistenzahl, die Lagerkontrolle als reine
-- Verdunstungsmessung, kein Käufer mehr.
-- =====================================================================

-- ---------- 0. heute() und stichtag() -------------------------------------
-- „Heute" ist eine Funktion, damit der Simulations-Harness eine Saison an
-- ihrem Stichtag prüfen kann (Einstellung heute_test). Im Betrieb ist es
-- current_date, und die Einstellung fehlt.
create or replace function heute() returns date
language sql stable set search_path = public as $$
  select coalesce((select nullif(wert #>> '{}', '')::date from public.einstellung where schluessel = 'heute_test'),
                  current_date)
$$;
comment on function heute() is
  'Der Tag, bis zu dem gerechnet wird — current_date, im Test die Einstellung heute_test (0061).';
revoke all on function heute() from public;
grant execute on function heute() to authenticated;

-- Der Stichtag ist nur noch der Horizont der Prognose.
create or replace function stichtag() returns date
language sql stable set search_path = public as $$
  select greatest((select nullif(wert #>> '{}', '')::date from public.einstellung where schluessel = 'saison_ende'),
                  public.heute())
$$;
comment on function stichtag() is
  'Bis wohin die Prognose reicht: das Saisonende aus den Einstellungen, mindestens heute (0061).';
revoke all on function stichtag() from public;
grant execute on function stichtag() to authenticated;

-- ---------- 1. Waschen zählt Paletten: Sortierdatum und Kisten je Palette --
-- Nach dem Sortieren stehen die Kaliber-Kisten wieder auf Paletten, mit
-- einem Zettel: dem Sortierdatum. Beim Waschen wird die Palette gezählt (ein
-- Tipp), mit ihrem Sortierdatum und der Kistenzahl — nicht Kiste für Kiste.
alter table auftrag_palette add column if not exists sortierdatum date;
alter table auftrag_palette add column if not exists kisten int check (kisten is null or kisten > 0);
comment on column auftrag_palette.sortierdatum is
  'Beim Waschen: das Sortierdatum vom Zettel der Palette (die Zeit im Zwischenlager). 0061.';
comment on column auftrag_palette.kisten is
  'Beim Waschen: wie viele Kaliber-Kisten auf dieser Palette standen — die Masse ist Kisten × Kistengewicht. 0061.';
create index if not exists auftrag_palette_sortierdatum on auftrag_palette (auftrag_id, sortierdatum);
-- Beim Waschen trägt die Palette ihr Sortierdatum, kein Eingangsdatum (das
-- steht auf keinem Zettel mehr). Die Pflicht „ein Datum" bleibt.
alter table auftrag_palette drop constraint if exists auftrag_palette_datum_pflicht;
alter table auftrag_palette add constraint auftrag_palette_datum_pflicht
  check (eingangsdatum is not null or sortierdatum is not null or kisten is not null
         or palette_id is not null or wiegung_id is not null)
  not valid;

-- ---------- 6. Verkaufte Kisten: aus der Verkaufsdatei, nicht hochgerechnet
-- Die Überfüllung wurde bisher auf die verkaufte Masse hochgerechnet (Anteil
-- der gewogenen Paletten, die als „Kiste ab x kg" liefen). Die Verkaufsdatei
-- weiss es besser: Jede Position trägt Einheit (kg oder Stk.), Gebindeinhalt
-- (8 kg, 10 kg — oder 12 Stück, 8 Stück) und Gebindemenge; jede Chargenzeile
-- ihre eigene Kistenzahl (AufPosBatchPackageQuantity). Geprüft an den echten
-- Dateien: Menge = Gebindemenge × Gebindeinhalt in allen 185 Kürbiszeilen mit
-- Chargenbezug, Chargenmenge = Chargenkisten × Inhalt ebenso.
--
-- Daraus das Kistensystem einer verkauften Lieferung, ohne zu raten:
--   Einheit kg,  Inhalt > 1     → Kiste ab <Inhalt> kg
--   Einheit Stk., Inhalt > 0    → <Inhalt> Stück je Kiste, Nenngewicht je Stück
--   sonst                       → unbekannt (nur Kilo — nichts behaupten)
alter table ausgang_zeile add column if not exists batch_gebinde int;
comment on column ausgang_zeile.batch_gebinde is
  'Kisten dieser Chargenzeile (AufPosBatchPackageQuantity Charge). Die Kistenzahl '
  'der Position steht in gebinde_menge. 0061.';

-- Die Lieferung kennt ihre Zeile. Bisher stand nur die Kennung in
-- lieferung_import; zeile_id blieb leer. Nachgetragen aus der Kennung
-- (Quelle:Position:Charge:Lauf); die Rest-Lieferung einer Position (ohne
-- Chargenbezug) bekommt die erste Zeile der Position — Artikel, Einheit und
-- Gebinde sind auf allen Zeilen einer Position gleich.
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

-- Die Übernahme schreibt die Kistenzahl der Chargenzeile mit und verbindet
-- die Lieferungen mit ihren Zeilen. Sonst wie 0055.
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
begin
  if not ist_admin() then
    raise exception 'Den Warenausgang übernimmt nur der Betriebsleiter.';
  end if;
  if p_quelle is null or p_quelle = '' then
    raise exception 'Ohne Quelle (Firma) keine Übernahme — an ihr hängt die Eindeutigkeit der Positionsnummern.';
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
  'Datei (Prüfsumme), Rohzeilen (Upsert, geaendert_ts bei anderem Fingerabdruck) und '
  'Lieferungen (Upsert über lieferung_import.extern_id). Löscht nichts. Gibt zurück, '
  'was neu, was aktualisiert und was nicht übernommen wurde (mit Grund).';
-- Postgres gibt jeder neuen Funktion PUBLIC das Ausführungsrecht; das nimmt
-- die Prüfung „nichts steht Nichtangemeldeten offen" nicht hin (0035).
revoke all on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) from public;
grant execute on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) to authenticated;
comment on function ausgang_uebernehmen is
  'Schreibt eine hochgeladene Warenausgangsdatei in einem Zug: Quelle (falls neu), '
  'Datei (Prüfsumme), Rohzeilen (Upsert, geaendert_ts bei anderem Fingerabdruck, seit '
  '0061 mit Kisten je Chargenzeile) und Lieferungen (Upsert über lieferung_import.extern_id, '
  'mit ihrer Zeile verbunden). Löscht nichts. Gibt zurück, was neu, was aktualisiert '
  'und was nicht übernommen wurde (mit Grund).';
revoke all on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) from public;
grant execute on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) to authenticated;

-- Die Neuberechnung in fünf Schritten. Jeder Schritt ist ein eigener Aufruf
-- der App — kurz genug für das Zeitlimit einer Verbindung — und analysiert,
-- was er erneuert hat, damit der nächste Schritt gute Pläne bekommt.
--   1  Rohdaten:  CSV-Sichten, Gewichte, Kaliber, Kisten, Lieferungen, Eingangstage
--   2  Arbeiten:  Masse je Arbeit, Verderbspunkte und -modell, Koeffizienten
--   3  Kaskade:   je Charge und Eingangstag bis heute; die Charge (erg_charge)
--   4  Ergebnis:  Ströme je Gruppe, Verlauf mit Prognose, Überfüllung, Bilanz, Marge
--   5  Befunde:   Plausibilität, Datenqualität; der Stand
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
comment on function auswertung_schritt(int) is
  'Ein Schritt der Neuberechnung (1 Rohdaten, 2 Arbeiten, 3 Kaskade, 4 Ergebnis, '
  '5 Befunde). Die App ruft die fünf nacheinander; jeder erneuert und analysiert '
  'seine gespeicherten Sichten. Schritt 5 setzt den Stand (0061).';
revoke all on function auswertung_schritt(int) from public;
grant execute on function auswertung_schritt(int) to authenticated;

-- Alles in einem Aufruf — für Tests, den SQL-Editor und den Zeitplan.
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
comment on function auswertung_aktualisieren() is
  'Die fünf Schritte der Neuberechnung nacheinander (0061). Die App ruft sie '
  'einzeln (auswertung_schritt), damit keiner ins Zeitlimit läuft.';

-- Nur rechnen, wenn sich etwas geändert hat (auswertung_veraltet setzt geaendert_ts).
create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand;
begin
  select * into v_stand from auswertung_stand where id = 1;
  if v_stand.berechnet_ts is not null and v_stand.geaendert_ts <= v_stand.berechnet_ts then
    return false;
  end if;
  perform auswertung_aktualisieren();
  return true;
end $$;
comment on function auswertung_wenn_veraltet() is
  'Rechnet neu, wenn seit der letzten Berechnung etwas geschrieben wurde — sonst '
  'nichts. Für einen Zeitplan (pg_cron), damit die App fertige Zahlen vorfindet (0061).';
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

-- Wo pg_cron da ist (Supabase), rechnet die Datenbank alle zehn Minuten nach,
-- wenn etwas veraltet ist. Wo nicht, bleibt es beim Rechnen aus der App.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'auswertung_wenn_veraltet';
    perform cron.schedule('auswertung_wenn_veraltet', '*/10 * * * *',
                          'select public.auswertung_wenn_veraltet()');
    raise notice 'Zeitplan: auswertung_wenn_veraltet() alle zehn Minuten (pg_cron).';
  else
    raise notice 'pg_cron fehlt — die App rechnet selbst nach, wenn etwas veraltet ist.';
  end if;
exception when others then
  raise notice 'Zeitplan nicht angelegt (%): die App rechnet selbst nach.', sqlerrm;
end $$;

-- Alles, was diese Migration angefasst hat, ist leer angelegt. Wer sie im
-- SQL-Editor einspielt, rechnet danach einmal — genau wie nach jeder anderen.
do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;

-- ---------- 5. Eine Lieferung ohne Menge ist keine Lieferung ------------
-- kg darf fehlen, solange die Kistenzahl da ist (dann rechnet
-- v_lieferung_masse mit dem mittleren Kistengewicht). Beides zu lassen geht
-- nicht: die Zeile zählt dann mit 0 kg in den Ausgang.
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

-- ---------- 2. Kein erfundenes Netto in der Datenbank -------------------
-- Beide Auslöser rechnen jetzt ohne coalesce. Kommt dabei nichts heraus,
-- bleibt die eingetragene Zahl stehen und die Wägung zählt nicht als
-- gemessen — die Auswertung liest nur Gemessenes (v_ausschuss_beobachtung,
-- v_schimmel_menge), und die Auffälligkeit unten nennt die Lücke beim
-- Namen. Vorher wurde das Bruttogewicht als Netto gespeichert.
create or replace function ausschuss_netto_setzen() returns trigger
language plpgsql
as $$
declare v_tara_kiste numeric; v_tara_palette numeric; v_netto numeric;
begin
  if new.brutto_kg is not null then
    select g.tara_kg_pro_kiste, g.tara_kg_palette
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    v_netto := new.brutto_kg - new.kisten * v_tara_kiste - v_tara_palette;
    if v_netto is null then
      -- Ohne Kistenzahl oder ohne hinterlegte Tara gibt es kein Netto (0066).
      new.gemessen := false;
    else
      new.kg := greatest(round(v_netto), 0);
      new.gemessen := true;
    end if;
  end if;
  return new;
end $$;
comment on function ausschuss_netto_setzen() is
  'Setzt kg auf das Netto aus Brutto, Kistenzahl und hinterlegter Tara. '
  'Fehlt eine der drei Angaben, gibt es kein Netto: die Zeile bleibt stehen, '
  'gemessen wird false, und v_plausibilitaet meldet „Ausschuss ohne Tara" (0066).';

create or replace function schimmel_netto_setzen() returns trigger
language plpgsql
as $$
declare v_tara_kiste numeric; v_tara_palette numeric; v_netto numeric;
begin
  if new.brutto_kg is not null then
    if new.palox_stand_kg is not null then
      raise exception 'Eine Messung ist entweder eine Palox-Ablesung oder eine Kistenwägung, nicht beides.';
    end if;
    select g.tara_kg_pro_kiste, g.tara_kg_palette
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    -- Ohne Palette braucht es die Palettentara nicht — dann ist sie 0 und
    -- nicht unbekannt. Die Kistentara braucht es immer.
    v_netto := new.brutto_kg - new.kisten * v_tara_kiste
             - case when new.mit_palette then v_tara_palette else 0 end;
    if v_netto is null then
      new.gemessen := false;
    else
      new.kg := greatest(round(v_netto), 0);
      new.gemessen := true;
    end if;
  end if;
  return new;
end $$;
comment on function schimmel_netto_setzen() is
  'Setzt kg auf das Netto aus Brutto, Kistenzahl und hinterlegter Tara (die '
  'Palettentara nur, wenn die Palette mitgewogen wurde). Fehlt eine nötige '
  'Angabe, gibt es kein Netto: die Zeile bleibt stehen und gemessen wird '
  'false — v_schimmel_menge liest nur Gemessenes (0066).';

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;


-- =====================================================================
-- aus 0067_der_tag_des_arbeiters.sql
-- =====================================================================

-- =====================================================================
-- 0067 — Der Tag des Arbeiters
--
-- Das Programm rechnet mit Lagertagen. Ein Lagertag entsteht als
-- Differenz zweier Dinge, die verschiedener Natur sind:
--
--   `eingangsdatum`  ein **Kalendertag**, vom Palettenzettel abgetippt.
--                    Er meint den Tag, an dem der Arbeiter in der Halle
--                    stand — Ortszeit, ohne dass es irgendwo dastünde.
--
--   `wiege_ts`       ein **Zeitpunkt**, von der Datenbank gesetzt
--                    (`now()`). Ein absoluter Augenblick, ohne Ort.
--
-- Aus dem Zeitpunkt wurde mit `::date` wieder ein Kalendertag — **in der
-- Zeitzone der Sitzung**. Die Datenbank läuft auf UTC, der Betrieb liegt
-- in der Schweiz (UTC+1, im Sommer UTC+2). Jeder Zeitpunkt zwischen
-- 22:00 UTC und Mitternacht — also 00:00 bis 02:00 Ortszeit — gehört
-- damit in UTC noch zum Vortag und in Zürich schon zum neuen Tag:
--
--     set time zone 'UTC';            select '2026-07-15 22:30+00'::timestamptz::date  → 2026-07-15
--     set time zone 'Europe/Zurich';  select '2026-07-15 22:30+00'::timestamptz::date  → 2026-07-16
--
-- Dieselbe Zeile, zwei Antworten. Welche das Programm gab, hing an einer
-- Einstellung, die niemand ausgewählt hat und die der Betreiber der
-- Datenbank jederzeit ändern kann.
--
-- WAS ES KOSTET, GEMESSEN
--
-- Dieselbe Auswertung in beiden Zeitzonen gerechnet (werkstatt/b_fundament/
-- b5_zeit.mjs, Demosaison):
--
--     Saisonverlust      52 119.38 kg   →   52 099.70 kg
--     Verdunstung        23 530.19 kg   →   23 525.18 kg
--     Schimmel           26 170.29 kg   →   26 155.61 kg
--     noch im Haus      154 545.37 kg   →  154 563.81 kg
--     Summe Lagertage         3 542     →        3 543
--
-- Wie nah das an der Wirklichkeit liegt, hat sich beim Bauen dieser
-- Migration von selbst gezeigt: Um 22:03 UTC sagte dieselbe Datenbank
--
--     current_date        → 2026-09-09
--     betriebstag(now())  → 2026-09-10
--
-- Der Betrieb war bereits im nächsten Tag, die Datenbank noch im vorigen —
-- und zwei Zwischenstände, die eine Stunde auseinander gerechnet wurden,
-- unterschieden sich um einen ganzen Lagertag je Charge. Das ist keine
-- Randerscheinung um Mitternacht: In der Sommerzeit dauert dieses Fenster
-- zwei Stunden, jede Nacht.
--
-- Ein einziger verschobener Lagertag, 19.68 kg. Klein — aber die
-- Verdunstungsrate einer Wägung ist `1 − (netto_jetzt/netto_damals)^(1/t)`,
-- und ein Tag mehr oder weniger in `t` verschiebt sie um rund `1/t` ihres
-- Werts. Bei der kürzesten Lagerung der Demosaison (acht Tage) sind das
-- 14.4 %. Der Median über alle 41 verwendbaren Wägungen liegt bei 1.2 %.
--
-- WIE ES REPARIERT WIRD
--
-- Nicht mit `alter database … set timezone`. Das verlegt die Entscheidung
-- nur an eine andere Stelle, an der sie ebenso still umkippen kann, und
-- auf Supabase steht sie ohnehin nicht in der Hand dieses Projekts.
-- Stattdessen sagt jede Stelle, die einen Zeitpunkt zu einem Kalendertag
-- macht, ausdrücklich **welchen** Kalendertag sie meint:
--
--     betriebstag(wiege_ts)   statt   wiege_ts::date
--
-- Die Zone selbst steht als Einstellung `zeitzone` in der Datenbank, mit
-- 'Europe/Zurich' als Rückfall. Ein Betrieb, der umzieht, ändert eine
-- Zeile; niemand muss dafür SQL anfassen.
--
-- WAS DIESE MIGRATION NICHT ANFASST — UND WARUM, MIT ZAHL
--
-- `mv_auftrag_masse` enthält dieselbe Verwechslung (`a.start_ts::date`),
-- ist aber eine gespeicherte Sicht: Sie lässt sich nicht ersetzen, nur
-- neu bauen, und `drop materialized view … cascade` nimmt **51 weitere
-- Objekte** mit — praktisch das ganze Rechenwerk.
--
-- Nachgemessen, bevor das als „später" abgetan wird: Von 309 Arbeiten
-- haben 5 einen Startzeitpunkt, dessen UTC-Tag und dessen Schweizer Tag
-- auseinanderfallen. Die gespeicherte Sicht in der Betriebszone neu
-- gefüllt und die ganze Auswertung nachgerechnet ergibt auf der
-- Demosaison **dieselben vier Zahlen bis auf den Rappen** — der Umbau
-- von 51 Objekten bewegt heute nichts. Deshalb bleibt er liegen; er ist
-- in docs/WERKSTATTBERICHT.md als offener Punkt vermerkt, nicht
-- vergessen.
--
-- AUSSERDEM IN DIESER MIGRATION
--
--   Vier Prüfbedingungen standen seit ihrer Einführung mit `NOT VALID`
--   im Schema. Postgres wendet sie auf neue Zeilen an, hat aber nie
--   nachgesehen, ob die vorhandenen sie erfüllen — und darf sie deshalb
--   beim Planen nicht voraussetzen. Nachgerechnet (werkstatt/b_fundament/
--   b4_integritaet.mjs): null Verstösse bei allen vieren. Aus dem
--   Versprechen wird damit eine Zusage.
--
--   Fünf Indexe beantworten nur Fragen, die ein anderer Index auch
--   beantwortet: Ihre Schlüsselspalten sind das Präfix eines anderen,
--   und wo sie eine Teilbedingung tragen, deckt der andere sie ohne
--   Bedingung ab. Zusammen 120 kB, die bei jedem Schreibvorgang
--   mitgepflegt werden, ohne je eine Abfrage zu beantworten.
-- =====================================================================

-- ---------- 1. Die Zone des Betriebs ------------------------------------

create or replace function betriebszone() returns text
language sql stable set search_path = public
as $$
  select coalesce(nullif((select wert #>> '{}' from public.einstellung
                           where schluessel = 'zeitzone'), ''), 'Europe/Zurich')
$$;
comment on function betriebszone() is
  'Die Zeitzone, in der der Betrieb steht. Einstellung „zeitzone", Rückfall Europe/Zurich.';
-- Postgres gibt neuen Funktionen das Ausführungsrecht an `public`, also auch an
-- Nichtangemeldete. Die Prüfung in supabase/test/pruefung.sql hält diese Tür
-- zu — sie hat genau diese beiden Zeilen eingefordert, bevor die Migration
-- durchging.
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

-- `heute()` liest weiterhin zuerst die Einstellung „heute_test", damit die
-- Prüfstände eine Saison an einem festen Tag betrachten können. Neu ist nur,
-- dass der Rückfall der Tag des Betriebs ist und nicht der von UTC.
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

-- Gegenprobe: Bleibt eine Sicht stehen, bricht die Migration ab. Eine
-- Reparatur, die die Hälfte erwischt, ist schlimmer als keine — sie sieht
-- erledigt aus. `mv_auftrag_masse` ist ausgenommen; warum, steht oben.
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

-- ---------- 3. Vier Zusagen einlösen ------------------------------------

alter table auftrag         validate constraint auftrag_fax_nur_waschen;
alter table auftrag         validate constraint auftrag_kaliber_nur_waschen;
alter table auftrag_palette validate constraint auftrag_palette_datum_pflicht;
alter table lieferung       validate constraint lieferung_hat_menge;

-- ---------- 4. Indexe, die ein anderer schon abdeckt --------------------
--
-- Je Zeile: der überflüssige Index, und der, der ihn deckt.
--   auftrag_palette_auftrag_id_idx      (auftrag_id)
--     ⊂ auftrag_palette_sortierdatum    (auftrag_id, sortierdatum)
--   ausschuss_auftrag                   (auftrag_id, art) wo gemessen
--     ⊂ ausschuss_messung_auftrag_id_art_idx (auftrag_id, art)
--   schimmel_auftrag                    (auftrag_id) wo gemessen
--     ⊂ schimmel_messung_auftrag_id_idx (auftrag_id)
--   palette_charge_nr_eingangsdatum_idx (charge_nr, eingangsdatum)
--     ⊂ palette_charge_netto            (charge_nr, eingangsdatum, gebindeart)
--   auftrag_aktiv                       (charge_nr) wo abgebrochen_ts is null
--     ⊂ auftrag_charge_nr_start_ts_idx  (charge_nr, start_ts)
--
-- Ein Index mit Teilbedingung ist kleiner und liegt eher im Arbeitsspeicher;
-- bei sehr vielen Zeilen kann er neben dem allgemeinen sinnvoll sein. Bei
-- den Zeilenzahlen dieses Betriebs — die grösste Messtabelle hat unter 6000
-- Zeilen — trägt das Argument nicht, und ein Arbeitstag über die Demosaison
-- hat keinen dieser fünf auch nur einmal angefasst.

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


-- =====================================================================
-- aus 0068_gegengelesen.sql
-- =====================================================================

-- =====================================================================
-- 0068 — Was die Gegenrede übrig gelassen hat
--
-- Runde M hat das System siebenmal vermessen und daraus 110 Verdachte
-- gezogen. Jeder wurde am laufenden System nachgemessen; jeder, der die
-- Messung überstand, wurde einem zweiten Leser vorgelegt mit dem
-- ausdrücklichen Auftrag, ihn zum Einsturz zu bringen.
--
-- Von den Verdachten, die diese zweite Prüfung vollständig durchlaufen
-- haben, blieben drei stehen. Sie stehen hier — mit den Zahlen des
-- Gegenlesers, nicht denen des Aufschreibers, denn der Gegenleser hat
-- mehrere davon nach unten korrigiert.
--
-- Was dabei genauso zählt: **zwölf Verdachte sind an der Gegenrede
-- zerbrochen**, und fast immer nach demselben Muster — die Rohzahlen
-- reproduzierten sich exakt, der Satz darüber nicht. „Der Freiheitsgrad
-- wird von einer Sorte mit 0.18 % Varianzanteil gesetzt" etwa: die
-- 0.18 % waren ungewichtet gerechnet, richtig sind 0.015 %, und ohne
-- diese Sorte setzt eine andere denselben Freiheitsgrad. Der Befund
-- dahinter stimmt trotzdem — nur eben aus einem anderen Grund.
--
-- ---------------------------------------------------------------------
-- 1. Das Neurechnen steht jedem Angemeldeten offen
--
-- `auswertung_schritt()` und `auswertung_aktualisieren()` sind
-- SECURITY DEFINER und prüfen nichts. Gemessen: Der Arbeiter Tomasz
-- (`ist_admin()` = f, `ist_aktiv()` = t) lässt beide durchlaufen. Ein
-- Lauf dauert 2 960 ms und nimmt dabei AccessExclusiveLock auf jede
-- gespeicherte Ansicht — `refresh ... concurrently` kommt im ganzen
-- Projekt nicht vor. Ein paralleler Leser von `erg_gewichte` wartete
-- gemessen **2 897 ms**, gegen höchstens 1.34 ms im Ruhezustand.
--
-- Die Oberfläche ruft das Neurechnen nur von den Betriebsleiterseiten
-- aus, und die sind in `src/App.tsx` bereits hinter `istAdmin`
-- weggeschlossen (`/dashboard`, `/ursachen`, `/chargen`, `/messungen`,
-- `/betrieb`). Es fehlt allein die Tür auf der Datenbankseite: Wer den
-- Aufruf direkt an PostgREST schickt, kommt am Riegel der Oberfläche
-- vorbei.
--
-- Der Wächter lässt ausdrücklich durch, wer **ohne Anmeldung** kommt —
-- also die Prüfstände, die Simulation und `demo_bauen.sh`, die als
-- Eigentümer der Datenbank laufen. Sonst wäre die halbe Werkstatt tot,
-- und ein Wächter, der die eigenen Prüfungen erschlägt, wird beim
-- ersten Ärger wieder ausgebaut.
--
-- ---------------------------------------------------------------------
-- 2. `erg_punkte` rechnet dieselbe Sicht ein zweites Mal
--
-- `erg_punkte` und `mv_schimmel_punkte` haben zeichengleiche
-- Definitionen und denselben Inhalt (142 Zeilen, `except` in beide
-- Richtungen null). Beide werden bei jedem Neurechnen aus
-- `v_schimmel_punkte` gefüllt — dieselbe Rechnung, zweimal.
--
-- Die Schwestern machen es anders: `erg_kaliber` liest
-- `v_kaliber_verteilung`, und das ist `select * from
-- mv_kaliber_verteilung` — eine billige Kopie. Dasselbe bei
-- `erg_modell`. Nur bei den Punkten fehlt die Hülle.
--
-- Gemessen im A/B-Versuch auf derselben Datenbank, je neun Läufe
-- abwechselnd: **103.2 ms von 3 016.7 ms**, also 3.42 %, plus 120 kB
-- doppelt gespeichert. Der Gegenleser hat dabei zwei Einschränkungen
-- gefunden, die dazugehören: 48–55 ms davon sind reine Planzeit und
-- damit von der Datenmenge unabhängig — auf einer grösseren Saison
-- fällt der Prozentsatz. Und die beiden Fassungen können nie
-- auseinanderlaufen, weil sie in derselben Transaktion entstehen. Es
-- geht also um Zeit und Platz, nicht um Richtigkeit.
--
-- ---------------------------------------------------------------------
-- 3. `zahl()` prüft die Grenze vor dem Runden
--
-- `zahl(p_wert, p_stellen, p_grenze)` vergleicht `abs(p_wert)` mit der
-- Grenze und rundet **danach**. Ein Wert knapp unter der Grenze kommt
-- durch die Prüfung und wird beim Runden über sie gehoben; die
-- Zielspalte `numeric(14,2)` nimmt ihn dann nicht mehr, und das ganze
-- Neurechnen bricht ab.
--
-- Der Gegenleser hat das Fenster ausgemessen, in dem das passieren
-- kann: 0.005 kg breit, bei 10¹² kg. Das ist ein Faktor von rund drei
-- Millionen von jeder Zahl entfernt, die in diesem Betrieb vorkommt.
-- Der Befund bleibt also richtig und folgenlos — und die Reparatur ist
-- eine Zeile, die Prüfung und Guss auf denselben Wert stellt.
-- =====================================================================

-- ---------- 1. Neurechnen ist Sache des Betriebsleiters ------------------

create or replace function auswertung_schritt(p_schritt integer) returns jsonb
language plpgsql security definer set search_path = public set jit = 'off'
as $$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
begin
  -- Wer ohne Anmeldung kommt, ist der Eigentümer der Datenbank: die
  -- Prüfstände, die Simulation, das Einspielen der Demodaten. Wer angemeldet
  -- ist, muss Betriebsleiter sein — ein Lauf sperrt für rund drei Sekunden
  -- jede gespeicherte Ansicht.
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.'
      using errcode = '42501';
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
comment on function auswertung_schritt(integer) is
  'Ein Schritt des Neurechnens. Nur für den Betriebsleiter — oder ohne Anmeldung, '
  'also für die Prüfstände als Eigentümer. Ein Lauf sperrt jede gespeicherte Ansicht '
  'für rund drei Sekunden (0068).';

create or replace function auswertung_aktualisieren() returns timestamptz
language plpgsql security definer set search_path = public set jit = 'off'
as $$
declare i int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.'
      using errcode = '42501';
  end if;
  for i in 1..5 loop
    perform auswertung_schritt(i);
  end loop;
  return now();
end $$;

comment on function auswertung_aktualisieren is
  'Rechnet die Auswertung neu. Dauert je nach Datenmenge einige Sekunden — '
  'währenddessen sind die drei gespeicherten Ansichten kurz gesperrt.';

grant execute on function auswertung_aktualisieren() to authenticated;
revoke execute on function auswertung_aktualisieren() from public;
grant execute on function auswertung_aktualisieren() to authenticated;
comment on function auswertung_aktualisieren() is
  'Alle fünf Schritte des Neurechnens nacheinander. Nur für den Betriebsleiter — '
  'oder ohne Anmeldung, also für die Prüfstände als Eigentümer (0068).';

-- ---------- 3. zahl() prüft, was sie auch zurückgibt ---------------------

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

-- ---------- 4. Stand der Datenbank --------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 68 $$;
comment on function schema_stand is
  'Nummer der jüngsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET (src/lib/version.ts) und verlangt bei Abweichung, setup.sql '
  'erneut auszuführen. Jede Migration setzt sie auf ihre eigene Nummer.';
revoke all on function schema_stand() from public;
grant execute on function schema_stand() to anon, authenticated;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;


-- =====================================================================
-- TEIL B — Das Rechenwerk: die Formeln, wie sie heute lauten
-- =====================================================================
-- Ab hier steht jede Ansicht und jede darauf rechnende Funktion genau
-- einmal — in 91 Schritten, in der Reihenfolge, in der eine auf der
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

drop materialized view if exists erg_punkte cascade;
drop view if exists v_wiegung_kennzahl cascade;
drop view if exists v_plausibilitaet cascade;
drop view if exists v_saisonbilanz cascade;
drop view if exists v_marge_buch cascade;
drop view if exists v_verlust_ranking cascade;
drop materialized view if exists erg_verlust cascade;
drop view if exists v_verlust_je_gruppe cascade;
drop view if exists v_plausibilitaet_0054_zusatz cascade;
drop view if exists v_plausibilitaet_0064_zusatz cascade;
drop view if exists v_naechste_charge cascade;
drop view if exists v_massenbilanz cascade;
drop view if exists v_kontrolle_vorschlag cascade;
drop view if exists v_hochrechnung cascade;
drop materialized view if exists mv_hochrechnung cascade;
drop view if exists v_kaskade cascade;
drop materialized view if exists erg_charge cascade;
drop view if exists v_hochrechnung_basis cascade;
drop materialized view if exists erg_verlauf cascade;
drop materialized view if exists mv_kaskade cascade;
drop view if exists v_schimmel_kurve_anzeige cascade;
drop view if exists v_selektionsverdacht cascade;
drop view if exists v_schimmel_modell cascade;
drop materialized view if exists mv_schimmel_modell cascade;
drop view if exists v_schimmel_modell_rechnen cascade;
drop view if exists v_schimmel_kurve cascade;
drop materialized view if exists mv_schimmel_punkte cascade;
drop view if exists v_schimmel_punkte cascade;
drop view if exists v_schimmel_beobachtung cascade;
drop view if exists v_koeff_fax cascade;
drop view if exists v_koeff_nebenkanal cascade;
drop view if exists v_koeff_ausschuss cascade;
drop view if exists v_koeff_unsicherheit cascade;
drop view if exists v_koeff_kaliber_geschaetzt cascade;
drop view if exists v_koeff_roh_kaliber cascade;
drop view if exists v_ausschuss_beobachtung cascade;
drop view if exists v_koeff_verdunstung cascade;
drop view if exists v_koeff_verdunstung_geschaetzt cascade;
drop view if exists v_koeff_roh_verdunstung cascade;
drop view if exists v_verdunstung_messung cascade;
drop view if exists v_verarbeitung_alter cascade;
drop view if exists v_kaskade_basis cascade;
drop view if exists v_fax_beobachtung cascade;
drop view if exists v_durchsatz cascade;
drop view if exists v_auftrag_masse cascade;
drop view if exists v_auftrag_wasch_paletten cascade;
drop view if exists v_lieferung_kohorte cascade;
drop materialized view if exists mv_sortier_eingang cascade;
drop materialized view if exists mv_auftrag_masse cascade;
drop view if exists v_auftrag_palette_masse cascade;
drop view if exists v_kohorte_anteil cascade;
drop view if exists v_charge_kohorte cascade;
drop view if exists v_datenlage cascade;
drop view if exists v_charge_rueckgrat cascade;
drop view if exists v_palette cascade;
drop view if exists v_datenqualitaet cascade;
drop view if exists v_saisonverlauf cascade;
drop view if exists v_ueberfuellung_kaeufer cascade;
drop materialized view if exists erg_ueberfuellung cascade;
drop view if exists v_ueberfuellung_verkauf cascade;
drop view if exists v_verkauf_lieferung cascade;
drop view if exists v_auftrag_gebinde_masse cascade;
drop view if exists v_koeff_gebinde cascade;
drop view if exists v_koeff_palette_netto cascade;
drop view if exists v_koeff_ueberfuellung cascade;
drop view if exists v_lieferung_masse cascade;
drop view if exists v_ausgang_kennzahl cascade;
drop view if exists v_schimmel_menge cascade;
drop view if exists v_palox_stand cascade;
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
drop view if exists v_kaliber_verteilung cascade;
drop materialized view if exists mv_kaliber_verteilung cascade;
drop view if exists v_sortier_lauf_masse cascade;
drop materialized view if exists mv_sortier_lauf_masse cascade;


-- ---------------------------------------------------------------------
-- Neu bauen — von unten nach oben
-- ---------------------------------------------------------------------


-- ---------- 1. Sortierläufe: 255 000 Zeilen → 300 -------------------------
-- Kein "drop cascade": Der Wrapper hat exakt dieselben Spalten und Typen wie
-- vorher, also genügt ein Ersetzen — die ganze Auswertung darüber bleibt stehen.
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

-- Die jeweils letzte Antwort je Arbeit und Schlüssel.
create or replace view v_auftrag_angabe with (security_invoker = true) as
select distinct on (auftrag_id, schluessel)
       auftrag_id, schluessel, wert, ts, erfasser
  from auftrag_angabe
 order by auftrag_id, schluessel, ts desc, id desc;
drop function if exists schimmel_n(numeric);


-- =====================================================================
-- aus 0049_betriebsleiter_kennzahlen.sql
-- =====================================================================

-- =====================================================================
-- 0049 — Kennzahlen für den Betriebsleiter aus den neuen Erfassungspunkten
--
-- Seit 0041–0047 erfasst die App mehr, als die Auswertung zeigte: das Datum
-- jeder gezählten Palette, Kisten je Kaliber, ob der Ausschuss gewogen oder
-- geschätzt wurde, wie die Kontrollpalette gegriffen wurde, Käufer und
-- Sortierart je Arbeit, Start und Ende. Diese Sichten machen daraus, was
-- der Betriebsleiter wissen will (docs/UI-KONZEPT.md) — ohne das Modell
-- anzufassen. Alles liest Tabellen, die die Masken bereits füllen.
--
-- Regeln wie überall: gerechnet wird aus Beobachtungen; was fehlt, ist NULL,
-- nicht 0; jede Sicht ist billig genug für Supabases 8-Sekunden-Grenze
-- (gemessen in run.sh, Stufe 5 und 6).
-- =====================================================================

-- ---------- 1. Gewichtsverteilung aus der Sortier-CSV ------------------------
-- Vom Betrieb ausdrücklich gewünscht (ABLAUF.md): Balken in wählbarer Breite,
-- die Kalibergrenzen darübergelegt, nach Sorte, Schlag oder Charge. Hier in
-- 25-g-Stufen; gröbere Stufen (50/100 g) fasst die Oberfläche zusammen.
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

-- v_ausgang_artikel_vorschlag: 1 Cast(s)
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

-- v_ausgang_lage: 1 Cast(s)
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

-- v_ausgang_pruef: 3 Cast(s)
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

-- Ist der Stand gefallen, wurde der Palox zwischendurch geleert — und wie
-- viel vorher noch dazukam, weiss niemand. Die Menge dieser Ablesung ist
-- dann unbekannt (NULL), nicht der neue Stand und nicht null.
create or replace view v_palox_stand with (security_invoker = true) as
select s.id, s.auftrag_id, s.ts, s.palox_stand_kg, s.kg,
       lag(s.palox_stand_kg) over w                                as vorher,
       case
         when s.palox_geleert then greatest(s.palox_stand_kg - palox_tara_kg(), 0)
         when lag(s.palox_stand_kg) over w is null then greatest(s.palox_stand_kg - palox_tara_kg(), 0)
         when s.palox_stand_kg < lag(s.palox_stand_kg) over w then null
         else s.palox_stand_kg - lag(s.palox_stand_kg) over w
       end                                                          as differenz,
       (s.palox_geleert
        or (lag(s.palox_stand_kg) over w is not null
            and s.palox_stand_kg < lag(s.palox_stand_kg) over w))   as zwischendurch_geleert,
       palox_station(a.station)                                     as station
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
 where s.palox_stand_kg is not null and s.gemessen
window w as (partition by palox_station(a.station) order by s.ts, s.id)
 order by palox_station(a.station), s.ts, s.id;

-- Eine Arbeit mit einer unbekannten Ablesung hat eine unbekannte Menge: ein
-- Teil ihres Faulen ist nirgends gemessen. Sie fällt aus der Schimmelkurve —
-- lieber ein Punkt weniger als ein zu kleiner.
create or replace view v_schimmel_menge with (security_invoker = true) as
select s.auftrag_id,
       sum(case when s.palox_stand_kg is null then s.kg else p.differenz end)::numeric as kg,
       count(*)::int as n_ablesungen
  from schimmel_messung s
  left join v_palox_stand p on p.id = s.id
 where s.gemessen
 group by s.auftrag_id
having bool_and(s.palox_stand_kg is null or p.differenz is not null);

-- ---------- 4. Fertige Palette: Soll aus der Arbeit, Erwartung bei Stück ---
-- Das Sollgewicht steht jetzt an der Arbeit (kistensystem = kiste_ab); ältere
-- Arbeiten haben es in der Fassung. Bei Stück-Kisten gibt es kein Soll, aber
-- eine Erwartung: Stück × mittleres Gewicht des Kalibers aus der Sortier-CSV.
-- Die Erwartung ist keine verschenkte Marge — sie sagt nur, wo im Band die
-- Ware liegt.
create or replace view v_ausgang_kennzahl with (security_invoker = true) as
with band_mittel as (
  -- Mittleres Stückgewicht je Sorte und Kaliber aus allen Sortierläufen
  select c.sorte, sg.kaliber_idx,
         sum(sg.anzahl::bigint * sg.gewicht_g)::numeric / nullif(sum(sg.anzahl), 0) as gramm
    from sortier_gewicht sg
    join sortier_lauf l on l.id = sg.lauf_id
    join charge c on c.nr = l.charge_nr
   where sg.klasse = 'kaliber' and sg.kaliber_idx is not null
   group by c.sorte, sg.kaliber_idx
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
       -- neu (0060)
       coalesce(a.kistensystem, case when ss.art = 'kiste' then 'kiste_ab' end)::text as kistensystem,
       w.kaliber_idx,
       e.stueck                                                                     as stueck_je_kiste,
       zahl(e.stueck * bm.gramm / 1000.0, 3, 1e7)::numeric(10,3)                    as erwartet_kg_pro_kiste,
       zahl(n.netto_kg / w.kisten - e.stueck * bm.gramm / 1000.0, 3, 1e7)::numeric(10,3)
                                                                                    as abweichung_je_kiste,
       zahl(bm.gramm, 0, 1e6)::numeric(8,0)                                         as band_mittel_g
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
  left join band_mittel bm on bm.sorte = c.sorte
        and bm.kaliber_idx = case when w.kaliber_idx = -2 then null else coalesce(w.kaliber_idx, a.kaliber_idx) end
 where w.gemessen and a.abgebrochen_ts is null and n.netto_kg > 0;

-- ---------- Kisten in Kilo, mit ausgewiesener Unsicherheit ----------------
create or replace view v_lieferung_masse with (security_invoker = true) as
with kiste as (
  -- Wie schwer ist eine ausgelieferte Kiste wirklich? Aus den fertig
  -- gepackten Paletten nach dem Waschen (0013).
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
       -- Fehler der Umrechnung: nur bei Kistenangaben, und nur so gross, wie
       -- die Wägungen es hergeben.
       case when l.kg is not null then 0
            when k.n >= 2 then l.kisten * t_quantil_95(k.n - 1) * k.sd / sqrt(k.n)
       end                                                          as masse_fehler_kg,
       k.n                                                          as kisten_n
  from lieferung l
  join ausgang_ziel z on z.code = l.ziel
  cross join kiste k;

-- v_koeff_ueberfuellung: 4 Cast(s)
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

-- Wie schwer ist eine fertige Palette netto? Je Sorte und Kistensystem aus
-- den gewogenen fertigen Paletten — der Nenner der Fax-Arbeit.
create or replace view v_koeff_palette_netto with (security_invoker = true) as
select k.sorte, k.kistensystem,
       count(*)::int                                            as n,
       zahl(avg(k.netto_kg), 2, 1e8)::numeric(10,2)             as netto_kg,
       zahl(stddev_samp(k.netto_kg), 2, 1e8)::numeric(10,2)     as sd,
       zahl(avg(k.kisten), 1, 1e6)::numeric(8,1)                as kisten
  from v_ausgang_kennzahl k
 group by grouping sets ((k.sorte, k.kistensystem), (k.sorte));

-- v_koeff_gebinde: die gezählten Kisten je Kaliber summiert (mehrere
-- Sortierdaten je Kaliber sind seit 0060 möglich); Kisten ohne Kaliber (−1)
-- aus den fertigen Paletten der Arbeiten mit Sollgewicht.
create or replace view v_koeff_gebinde with (security_invoker = true) as
with gezaehlt as (
  select auftrag_id, kaliber_idx, sum(anzahl)::int as anzahl
    from auftrag_gebinde group by auftrag_id, kaliber_idx
), je_arbeit as (
  select a.id as auftrag_id, c.sorte, g.kaliber_idx, g.anzahl,
         (sum(sg.anzahl::bigint * sg.gewicht_g) / 1000.0)::numeric as kg
    from gezaehlt g
    join auftrag a       on a.id = g.auftrag_id and a.abgebrochen_ts is null
    join charge c        on c.nr = a.charge_nr
    join sortier_lauf l  on l.auftrag_id = a.id
    join sortier_gewicht sg on sg.lauf_id = l.id
                           and sg.klasse = 'kaliber'
                           and sg.kaliber_idx = g.kaliber_idx
   where a.station in ('sortieren', 'waschen_sortieren') and g.anzahl > 0
   group by a.id, c.sorte, g.kaliber_idx, g.anzahl
), s as (
  select sorte, kaliber_idx, count(*)::int as n,
         sum(kg) / nullif(sum(anzahl), 0)   as kg_je_gebinde,
         stddev_samp(kg / anzahl)           as sd
    from je_arbeit group by sorte, kaliber_idx
  union all
  select k.sorte, -1, count(*)::int,
         sum(k.netto_kg) / nullif(sum(k.kisten), 0),
         stddev_samp(k.kg_pro_kiste)
    from v_ausgang_kennzahl k
   where k.soll_kg_pro_kiste is not null or k.kistensystem = 'kiste_ab'
   group by k.sorte
)
select sorte, kaliber_idx, n,
       zahl(kg_je_gebinde, 3, 1e7)::numeric(10,3)                       as kg_je_gebinde,
       zahl(sd, 3, 1e7)::numeric(10,3)                                  as sd,
       zahl(case when sd is null or n < 2 then kg_je_gebinde
                 else greatest(kg_je_gebinde - t_quantil_95(n - 1) * sd / sqrt(n), 0)
            end, 3, 1e7)::numeric(10,3)                                 as unten,
       zahl(case when sd is null or n < 2 then kg_je_gebinde
                 else kg_je_gebinde + t_quantil_95(n - 1) * sd / sqrt(n)
            end, 3, 1e7)::numeric(10,3)                                 as oben
  from s where kg_je_gebinde is not null;

-- ---------- 5. Kisten je Kaliber: über die Sortierdaten summiert ----------
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
drop function if exists verlust_ranking(text, text, numeric);
drop function if exists verlust_ranking(text, text, numeric, int);

-- Je verkaufter Lieferung: das Kistensystem und die Kisten aus der Datei.
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
  -- das aktuelle Kaliberschema je Sorte (ohne Käufer, art = kaliber)
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
             -- die Chargenzeile zählt ihre Kisten selbst
             when i.extern_id not like '%:rest' and z.batch_gebinde > 0
               then z.batch_gebinde::numeric
             -- der Rest der Position: Kisten der Position minus die gezählten Chargenzeilen
             when i.extern_id like '%:rest' and coalesce(p.alle_gezaehlt, true) and p.gebinde_menge > 0
               then greatest(p.gebinde_menge - coalesce(p.batch_gebinde_summe, 0), 0)::numeric
             -- sonst der Anteil an der Position (gleiche Kisten je Kilo)
             when p.gebinde_menge > 0 and p.kg_position > 0
               then p.gebinde_menge * l.kg / p.kg_position
           end as kisten,
           case
             when i.extern_id not like '%:rest' and z.batch_gebinde > 0 then 'zeile'
             when i.extern_id like '%:rest' and coalesce(p.alle_gezaehlt, true) and p.gebinde_menge > 0 then 'rest'
             when p.gebinde_menge > 0 and p.kg_position > 0 then 'anteil'
           end::text as kisten_quelle) k
 where l.ziel = 'verkauf' and ks.kistensystem is not null;

-- Verkauft gegen gewogen, je Sorte (und je Charge) und Kistensystem.
-- Verschenkt wird nur gerechnet, wo beides da ist: gewogene Kisten desselben
-- Systems (der Überschuss je Kiste) und verkaufte Kisten aus der Datei.
-- Bei Stück-Kisten gibt es kein Soll und keine verschenkte Marge — nur das
-- gemessene Stückgewicht neben dem Nenngewicht der Datei.
create or replace view v_ueberfuellung_verkauf with (security_invoker = true) as
with verkauft as (
  select case when grouping(v.charge_nr) = 1 then 'sorte' else 'charge' end as gruppe,
         v.sorte, v.charge_nr, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx,
         count(*)::int                                                       as n_lieferungen,
         sum(v.kg)                                                           as kg_verkauft,
         sum(v.kisten)                                                       as kisten_verkauft,
         count(*) filter (where v.kisten_quelle = 'anteil')::int             as n_anteilig,
         sum(v.stueck)                                                       as stueck_verkauft,
         sum(v.stueck * v.nenn_g) / nullif(sum(v.stueck), 0)                 as nenn_g,
         min(v.datum)                                                        as von,
         max(v.datum)                                                        as bis
    from v_verkauf_lieferung v
   where v.sorte is not null
   group by grouping sets ((v.sorte, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx),
                           (v.sorte, v.charge_nr, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx))
), gewogen as (
  select case when grouping(k.charge_nr) = 1 then 'sorte' else 'charge' end as gruppe,
         k.sorte, k.charge_nr, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
         case when k.kistensystem = 'stueck' then k.kaliber_idx end          as kaliber_idx,
         count(*)::int                                                       as n_wiegungen,
         sum(k.kisten)                                                       as kisten_gewogen,
         sum(k.netto_kg) / nullif(sum(k.kisten), 0)                          as kg_je_kiste,
         stddev_samp(k.kg_pro_kiste)                                         as sd_je_kiste,
         sum(k.ueberfuellung_kg)                                             as zuviel_gewogen_kg,
         sum(k.netto_kg) / nullif(sum(k.kisten * k.stueck_je_kiste), 0) * 1000 as g_je_kuerbis,
         max(k.band_mittel_g)                                                as band_mittel_g
    from v_ausgang_kennzahl k
   where k.kistensystem in ('kiste_ab', 'stueck')
     and (k.kistensystem <> 'kiste_ab' or k.soll_kg_pro_kiste is not null)
     and (k.kistensystem <> 'stueck'   or k.stueck_je_kiste is not null)
   group by grouping sets ((k.sorte, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
                            case when k.kistensystem = 'stueck' then k.kaliber_idx end),
                           (k.sorte, k.charge_nr, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
                            case when k.kistensystem = 'stueck' then k.kaliber_idx end))
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
select coalesce(v.gruppe, g.gruppe)                                           as gruppe,
       coalesce(v.sorte, g.sorte)                                             as sorte,
       coalesce(v.charge_nr, g.charge_nr)                                     as charge_nr,
       coalesce(v.kistensystem, g.kistensystem)                               as kistensystem,
       coalesce(v.soll_kg_pro_kiste, g.soll_kg_pro_kiste)                     as soll_kg_pro_kiste,
       coalesce(v.stueck_je_kiste, g.stueck_je_kiste)                         as stueck_je_kiste,
       coalesce(v.kaliber_idx, g.kaliber_idx)                                 as kaliber_idx,
       b.von                                                                  as band_von_g,
       b.bis                                                                  as band_bis_g,
       zahl(v.nenn_g, 0, 1e6)::numeric(8,0)                                   as nenn_g,
       coalesce(v.n_lieferungen, 0)                                           as n_lieferungen,
       zahl(v.kg_verkauft, 1, 1e11)::numeric(12,1)                            as kg_verkauft,
       zahl(v.kisten_verkauft, 0, 1e9)::numeric(12,0)                         as kisten_verkauft,
       coalesce(v.n_anteilig, 0)                                              as n_anteilig,
       zahl(v.stueck_verkauft, 0, 1e9)::numeric(12,0)                         as stueck_verkauft,
       v.von, v.bis,
       coalesce(g.n_wiegungen, 0)                                             as n_wiegungen,
       g.kisten_gewogen,
       zahl(g.kg_je_kiste, 3, 1e7)::numeric(10,3)                             as kg_je_kiste,
       zahl(g.sd_je_kiste, 3, 1e7)::numeric(10,3)                             as sd_je_kiste,
       zahl(g.kg_je_kiste - g.soll_kg_pro_kiste, 3, 1e7)::numeric(10,3)       as zuviel_je_kiste,
       zahl(g.zuviel_gewogen_kg, 1, 1e11)::numeric(12,1)                      as zuviel_gewogen_kg,
       -- verschenkt: nur wo gewogen UND verkaufte Kisten aus der Datei
       zahl(case when g.n_wiegungen > 0 and v.kisten_verkauft is not null and g.kistensystem = 'kiste_ab'
                 then greatest(g.kg_je_kiste - g.soll_kg_pro_kiste, 0) * v.kisten_verkauft end,
            1, 1e11)::numeric(12,1)                                           as verschenkt_kg,
       zahl(case when g.n_wiegungen >= 2 and v.kisten_verkauft is not null and g.kistensystem = 'kiste_ab'
                 then t_quantil_95(g.n_wiegungen - 1) * g.sd_je_kiste / sqrt(g.n_wiegungen) * v.kisten_verkauft end,
            1, 1e11)::numeric(12,1)                                           as verschenkt_fehler_kg,
       zahl(g.g_je_kuerbis, 0, 1e6)::numeric(8,0)                             as g_je_kuerbis,
       zahl(g.band_mittel_g, 0, 1e6)::numeric(8,0)                            as band_mittel_g
  from verkauft v
  full outer join gewogen g
         on g.gruppe = v.gruppe and g.sorte = v.sorte and g.charge_nr is not distinct from v.charge_nr
        and g.kistensystem = v.kistensystem
        and g.soll_kg_pro_kiste is not distinct from v.soll_kg_pro_kiste
        and g.stueck_je_kiste is not distinct from v.stueck_je_kiste
        and g.kaliber_idx is not distinct from v.kaliber_idx
  left join band b on b.sorte = coalesce(v.sorte, g.sorte) and b.kaliber_idx = coalesce(v.kaliber_idx, g.kaliber_idx);
create materialized view erg_ueberfuellung as select * from v_ueberfuellung_verkauf with no data;
create view v_datenqualitaet with (security_invoker = true) as
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
  -- 0061: die Lagerkontrolle ist eine Verdunstungsmessung — gezählt wird jede
  -- gemessene Kontrolle, nicht nur die mit Faul-Angabe
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
    where p.auftrag_id = f.id and p.differenz is null))::int                              as arbeiten_mit_palox_unbekannt;


-- =====================================================================
-- aus 0064_leer_ist_nicht_null.sql
-- =====================================================================

-- =====================================================================
-- 0064 — Leer ist nicht null, auch am Eingang
--
-- Runde L hat mit dem Prüfwerk (pruefwerk/) nachgesehen, wo aus einer
-- Lücke eine Zahl wird. Fünf Stellen, alle nach demselben Muster:
-- `coalesce(etwas_unbekanntes, 0)`. Die Null rechnet dann weiter und sieht
-- aus wie eine Messung.
--
--   1. Fehlt die Kistenzahl einer Palette, rechnet v_palette mit **null
--      Kisten**. Das Gewicht der Kisten wird als Kürbis verbucht: bei 30
--      Kisten à 1 kg auf 950 kg Netto sind das 3,2 % zu viel Eingang. Und
--      es fällt nirgends auf — die Palette hat ein Netto, es ist nur falsch.
--      Dasselbe für die fehlende Palettentara.
--
--   2. Dieselbe Rechnung steht an drei weiteren Stellen (Wägung damals /
--      jetzt). Dort kürzt sich die Palettentara im Verhältnis heraus, die
--      Kistentara aber nicht: Beide Nettos werden zu hoch, ihr Verhältnis
--      rückt gegen 1, und die Verdunstungsrate wird zu klein.
--
--   3. Ein Verluststrom ohne Messung stand in v_hochrechnung_basis als
--      0,00 kg. erg_verlust macht es seit jeher richtig (NULL, bekannt =
--      false) — dieselbe Datenbank gab damit auf zwei Wegen zwei Antworten.
--      Auf dem Überblick stand „Verlust bis heute: 0,0 t · 0,0 % des
--      Eingangs", bevor die erste Palette gewogen war.
--
--   4. `coalesce(k.im_haus_heute_kg, b.eingang_kg)` war für den Fall
--      gedacht, dass es zu einer Charge **gar keine** Kaskadenzeile gibt —
--      dann liegt tatsächlich noch alles. Sie griff aber auch, wenn es
--      Zeilen gibt und nur die Portion „lager" fehlt, und das ist der
--      genaue Gegenfall: Es liegt nichts mehr. Eine vollständig
--      ausgelieferte Charge über 950 kg meldete 950 kg „noch im Haus", und
--      die Bilanz ging um dieselben 950 kg nicht auf. Am Saisonende wird
--      das der Normalfall.
--
--   5. Drei Dinge, die der Betrieb sehen soll, sah er nicht: eine
--      Gebindeart ohne hinterlegte Tara (die ganze Charge fällt aus der
--      Bilanz), eine Charge, die mehr ausgeliefert hat als je erfasst
--      wurde (4180 kg in der Demosaison), und ein Zettelgewicht, das zur
--      Charge passt, aber nicht zum Tag (still genähert).
--
-- Nichts davon ist eine neue Funktion. Es sind fünf Stellen, an denen eine
-- Zahl behauptet hat, gemessen zu sein.
-- =====================================================================

-- ---------- 1. Das Netto einer Palette ----------------------------------
-- Ohne Kistenzahl gibt es kein Netto. Ohne hinterlegte Tara auch nicht —
-- das war schon so, weil `g.tara_kg_pro_kiste` ohne coalesce steht; die
-- Palettentara bekommt jetzt dieselbe Behandlung.
create or replace view v_palette with (security_invoker = true) as
select p.id, p.charge_nr, p.eingangsdatum, p.brutto_kg, p.kisten, p.gebindeart,
       p.brutto_kg - p.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette as netto_kg
  from palette p
  left join gebinde g on g.art = p.gebindeart;


-- =====================================================================
-- aus 0021_fehlende_tara_und_ueberzaehlung.sql
-- =====================================================================

-- =====================================================================
-- 0021 — Zwei stille Verzerrungen der Eingangsmasse
--
-- ---------- 1. Fehlende Tara macht die Charge kleiner ---------------------
-- v_palette rechnet netto = brutto − Kisten·Tara − Palettentara. Fehlt die
-- Gebindeart, ist die Tara NULL, also auch netto — und sum() überspringt NULL
-- stillschweigend. Die Charge wird dadurch leichter, als sie ist, und jeder
-- Verlust in Prozent der Charge entsprechend grösser.
--
-- Nachgemessen an einer Charge mit 44 Paletten, bei der 4 keine Gebindeart
-- haben (9 % der Paletten):
--
--   so gerechnet    34 494 kg
--   hochgerechnet   37 943 kg
--   Fehlbetrag        10.0 %
--
-- Zehn Prozent auf der Bezugsgrösse verschieben jede Verlustquote um zehn
-- Prozent — mehr, als die meisten Unterschiede, die hier rangiert werden
-- sollen. In der Oberfläche wurde bisher gewarnt, die Zahl selbst blieb falsch.
--
-- Behoben durch Hochrechnung innerhalb der Charge: Paletten ohne bekannte
-- Tara bekommen das mittlere Nettogewicht der übrigen Paletten derselben
-- Charge. Sie stehen im selben Lager und stammen von derselben Ernte; das ist
-- die naheliegendste Annahme, die man treffen kann — und allemal besser als
-- so zu tun, als gäbe es sie nicht.
--
-- ---------- 2. Mehr ausgelagert als eingelagert --------------------------
-- lager_kg = greatest(eingang − ausgelagert, 0). Übersteigt die ausgelagerte
-- Masse die eingelagerte — weil eine Charge mehrfach über das Band lief und
-- Paletten doppelt gezählt wurden, oder weil oben Tara fehlte —, wird der
-- Rest still auf 0 gesetzt und niemand erfährt davon. Der Betrag, um den
-- gekappt wurde, wird jetzt mitgeführt: er ist die einzige Spur, die eine
-- Doppelzählung im System hinterlässt.
-- =====================================================================

create or replace view v_charge_rueckgrat with (security_invoker = true) as
select c.nr as charge_nr, c.schlag, c.sorte, c.saison,
       count(p.id)                                     as n_paletten,
       count(p.netto_kg)                               as n_paletten_mit_netto,
       -- Auf alle Paletten der Charge hochgerechnet, nicht nur auf die mit
       -- bekannter Tara. Sind alle bekannt, ändert sich nichts.
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

-- ---------- Datenlage: was fehlt noch? ------------------------------------
-- Die Stichproben sollen die Kandidaten trennen (Spec §9). Diese View zeigt,
-- wo eine weitere Messung am meisten bringt.
create view v_datenlage with (security_invoker = true) as
select r.charge_nr, r.sorte, r.schlag, r.n_paletten,
       -- Paletten ohne hinterlegte Gebinde-Tara haben kein Netto und fehlen
       -- damit still in der Eingangsmasse. Die Lücke muss sichtbar sein.
       r.n_paletten_mit_netto, r.eingang_netto_kg as eingang_kg,
       (select count(*) from verdunstung_wiegung w where w.charge_nr = r.charge_nr) as n_wiegungen,
       (select count(*) from auftrag a join schimmel_messung s on s.auftrag_id = a.id
         where a.charge_nr = r.charge_nr)                                           as n_schimmel,
       (select count(*) from sortier_lauf l where l.charge_nr = r.charge_nr)        as n_sortierlaeufe,
       (select count(*) from auftrag a where a.charge_nr = r.charge_nr)             as n_auftraege
  from v_charge_rueckgrat r;

-- ---------- 7. Die Kohorten: der Eingang je Tag, nicht das Zählen --------
-- Wie viel von einer Charge an welchem Tag kam, ist vollständig bekannt. Wie
-- viel davon noch liegt, weiss die App nicht aus dem Zählen — dazu wird zu
-- selten gezählt. Der Anteil eines Eingangstags am Bestand ist deshalb sein
-- Anteil am Eingang; n_verarbeitet und n_rest bleiben als das, was sie sind:
-- in der App gezählte Paletten, keine Mengen.
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
       -- neu (0060): der Eingang dieses Tags
       zahl(d.n * coalesce(d.netto_mittel, cn.netto), 2, 1e10)::numeric(12,2) as eingang_kg
  from je_datum d
  join charge_netto cn on cn.charge_nr = d.charge_nr
  left join gezaehlt g on g.charge_nr = d.charge_nr and g.eingangsdatum = d.eingangsdatum;

create or replace view v_kohorte_anteil with (security_invoker = true) as
select charge_nr, eingangsdatum, n_rest, rest_kg,
       zahl(eingang_kg / nullif(sum(eingang_kg) over (partition by charge_nr), 0), 6, 1e4)::numeric(10,6) as anteil
  from v_charge_kohorte
 where eingang_kg > 0;

create or replace view v_auftrag_palette_masse with (security_invoker = true) as
with wiegung as materialized (
  select vw.id,
         zahl(vw.brutto_damals_kg - vw.kisten * g.tara_kg_pro_kiste
              - g.tara_kg_palette, 2, 1e8)::numeric(10,2) as netto_damals_kg,
         vw.eingangsdatum
    from verdunstung_wiegung vw
    left join gebinde g on g.art = vw.gebindeart
), datum_mittel as materialized (
  select charge_nr, eingangsdatum, avg(netto_kg) as netto_mittel
    from v_palette group by charge_nr, eingangsdatum
), charge_mittel as materialized (
  select charge_nr, avg(netto_kg) as netto_mittel,
         avg(brutto_kg - netto_kg) filter (where netto_kg is not null) as tara_mittel
    from v_palette group by charge_nr
), charge_datum as materialized (
  select charge_nr, eingangsdatum_mittel from v_charge_rueckgrat
), zettel as materialized (
  select ap.id,
         coalesce(pe.netto_kg,
                  zahl(ap.brutto_zettel_kg - cm.tara_mittel, 2, 1e8)::numeric(10,2)) as netto_kg,
         (pe.id is not null) as exakt
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join lateral (
      select p.id, p.netto_kg from v_palette p
       where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum
         and p.brutto_kg = ap.brutto_zettel_kg and p.netto_kg is not null
       order by p.id limit 1) pe on true
    left join charge_mittel cm on cm.charge_nr = a.charge_nr
   where ap.brutto_zettel_kg is not null
)
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(w.netto_damals_kg, z.netto_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel) as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) as eingangsdatum,
       case when w.netto_damals_kg is not null then 'gewogen'
            when z.netto_kg is not null and z.exakt then 'zettel'
            when z.netto_kg is not null then 'zettel-charge-tara'
            when p.netto_kg is not null then 'palette'
            when d.netto_mittel is not null then 'datum-mittel'
            when cm.netto_mittel is not null then 'charge-mittel'
            else 'unbekannt' end::text                                                 as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join wiegung w on w.id = ap.wiegung_id
  left join zettel z on z.id = ap.id
  left join v_palette p on p.id = ap.palette_id
  left join datum_mittel d on d.charge_nr = a.charge_nr and d.eingangsdatum = ap.eingangsdatum
  left join charge_mittel cm on cm.charge_nr = a.charge_nr
  left join charge_datum cd on cd.charge_nr = a.charge_nr
 where ap.kisten is null;

-- ---------- 2. Masse je Arbeit --------------------------------------------
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


-- =====================================================================
-- aus 0026_schimmelpunkte_speichern.sql
-- =====================================================================

-- =====================================================================
-- 0026 — Die Schimmelpunkte einmal rechnen statt viermal
--
-- v_schimmel_punkte ist mit 0025 teuer geworden: Für jeden Waschgang wird
-- nachgeschlagen, was bis dahin beim Sortieren derselben Charge gemessen
-- wurde. Das ist richtig so, aber die Ansicht hängt an vier Stellen in der
-- Kette und wurde dabei jedes Mal neu gerechnet. Dazu kam, dass
-- v_auftrag_masse seit 0024 bei jeder Referenz den Wareneingang der
-- sortierten Ware neu aggregiert — und v_auftrag_masse steckt in einem
-- Dutzend Ansichten. Die Neuberechnung stieg dadurch von 226 ms auf 2 639 ms.
--
-- Dasselbe Mittel wie in 0016: einmal rechnen, speichern, alle lesen von der
-- gespeicherten Fassung. Reihenfolge im Neuberechnen ist Pflicht — jede Stufe
-- liest die vorige.
--
-- Nicht per Umbenennung: Postgres merkt sich Abhängigkeiten über die Objekt-ID,
-- eine umbenannte Ansicht nehmen ihre Leser einfach mit. Wer den schnellen Weg
-- will, muss die Leser umhängen. Genau das passiert hier.
-- =====================================================================

-- ---------- Der Wareneingang der sortierten Ware, einmal gerechnet ---------
create materialized view if not exists mv_sortier_eingang as
select a.charge_nr,
       sum((m.eingangsdatum - date '2000-01-01')::numeric * m.netto_kg)
         / nullif(sum(m.netto_kg), 0)                        as tage_seit_epoche
  from auftrag a
  join v_auftrag_palette_masse m on m.auftrag_id = a.id
 where a.station = 'sortieren' and a.abgebrochen_ts is null
 group by a.charge_nr with no data;


-- =====================================================================
-- aus 0065_entsorgtes_verlaesst_das_lager.sql
-- =====================================================================

-- =====================================================================
-- 0065 — Entsorgtes verlässt das Lager
--
-- Die Lieferungen kennen drei Bücher: verkauft, in den Nebenkanal (Tiere,
-- zu klein / zu gross) und entsorgt (Kompost). Die Kaskade kannte zwei.
-- Was als Kompost weggefahren wurde, zählte damit im Ausgang **und** lag
-- gleichzeitig weiter im Lager — dieselbe Ware zweimal.
--
-- Es ist derselbe Fehler, den 0062 für das zweite Buch behoben hat, nur
-- für das dritte. In der Demosaison ist er folgenlos, weil dort nichts
-- entsorgt wird; das Prüfwerk hat ihn an einem gebauten Fall mit 500 kg
-- Kompost gemessen (pruefwerk/sonden/07_szenarien.mjs → S5).
--
-- WIE ENTSORGTE WARE GERECHNET WIRD
--
-- Bei verkaufter Ware rechnet die Kaskade rückwärts durch die ganze
-- Ausbeute: hinter 100 kg Lieferung steckt mehr Eingangsware, weil davor
-- Wasser entwichen, Faules aussortiert und zu Kleines abgezweigt wurde.
--
-- Bei entsorgter Ware gilt das nicht. Sie ist selbst das Ergebnis dieser
-- Ursachen — Faules, das den Betrieb verlässt. Zurückgerechnet wird
-- deshalb nur die Verdunstung: 100 kg Kompost nach 200 Tagen waren beim
-- Eingang 100 / (1−r)^200 kg. Diese Eingangsmasse wird der liegenden
-- Portion abgezogen; sie zählt als Verdunstung (was an Wasser entwich)
-- und als Faules (der Rest, der weggefahren wurde).
--
-- Der Verlust wächst dadurch nicht doppelt: Für die entsorgte Masse
-- rechnet das Verderbsmodell nicht noch einmal, weil sie aus der
-- liegenden Portion bereits heraus ist. An dieser Stelle schlägt eine
-- Beobachtung eine Hochrechnung — genau so, wie es sein soll.
--
-- Keine neue Ursache, keine neue Spalte, kein neuer Bildschirm: Entsorgtes
-- erscheint dort, wo es hingehört, unter Faulem.
-- =====================================================================

-- ---------- 1. Das dritte Buch kommt in die Kohorten --------------------
-- Bis hierher hat v_lieferung_kohorte nur „verkauf" und „marge" gezählt. Das
-- war die Stelle, an der die entsorgte Ware verschwand: Sie stand im Ausgang
-- (v_saisonbilanz nimmt dort alle Bücher), aber die Kaskade sah sie nie.
create or replace view v_lieferung_kohorte with (security_invoker = true) as
with lief as (
  select l.id, l.datum, l.buch, l.masse_kg, c.charge_nr, c.anteil
    from v_lieferung_masse l
    cross join lateral (
      select l.charge_nr as charge_nr, 1::numeric as anteil where l.charge_nr is not null
      union all
      select r.charge_nr, r.eingang_netto_kg / sum(r.eingang_netto_kg) over ()
        from v_charge_rueckgrat r
       where l.charge_nr is null and r.sorte = l.sorte and r.eingang_netto_kg > 0
    ) c
   where l.masse_kg is not null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge', 'verlust')
     and l.datum <= heute()
  union all
  -- Der Vorlauf (AB-07): was vor dem Erfassungsbeginn schon ausgeliefert war.
  select -cv.charge_nr, coalesce(
           (select nullif(wert #>> '{}', '')::date from einstellung where schluessel = 'erfassungsbeginn'),
           r.letzter_eingang),
         'verkauf', cv.ausgang_vor_app_kg, cv.charge_nr, 1
    from charge_vorlauf cv
    join v_charge_rueckgrat r on r.charge_nr = cv.charge_nr
   where cv.ausgang_vor_app_kg > 0
)
select f.charge_nr, k.eingangsdatum as kohorte, f.buch,
       zahl(sum(f.masse_kg * f.anteil * k.anteil), 2, 1e12)::numeric(14,2)      as masse_kg,
       zahl(sum(f.masse_kg * f.anteil * k.anteil * greatest(f.datum - k.eingangsdatum, 0))
            / nullif(sum(f.masse_kg * f.anteil * k.anteil), 0), 1, 1e5)::numeric(8,1) as alter_tage,
       count(distinct f.id)::int                                                as n_lieferungen,
       min(f.datum)                                                             as von,
       max(f.datum)                                                             as bis
  from lief f
  join v_kohorte_anteil k on k.charge_nr = f.charge_nr
 group by f.charge_nr, k.eingangsdatum, f.buch;

-- ---------- 2. Jede Sicht, die einen Zeitpunkt zu einem Tag macht -------
--
-- Fünf Sichten machten aus einem Zeitstempel einen Kalendertag. Sie stehen
-- hier vollständig, mit `betriebstag(...)` an der Stelle, an der vorher
-- `...::date` stand — sonst nichts geändert.
--
-- Ausgeschrieben und nicht umgeformt: setup.sql entsteht aus diesen Dateien,
-- indem von jeder Sicht die **zuletzt geschriebene Fassung** übernommen wird
-- (supabase/verdichten.mjs). Eine Migration, die Sichten zur Laufzeit umformt,
-- taucht dort gar nicht auf — setup.sql behielte die alte Fassung, und die
-- Datenbank eines neuen Betriebs hätte den Fehler weiter, während die eines
-- alten ihn nicht mehr hätte. Der Abgleich in supabase/test/run.sh würde es
-- melden; besser ist, es gar nicht erst so zu bauen.

-- Reihenfolge nach Abhängigkeit, nicht nach Alphabet: `v_auftrag_masse` liest
-- `v_auftrag_wasch_paletten`. In den Migrationen fällt das nicht auf, weil
-- dort beide Sichten schon stehen; erst der Lauf von setup.sql auf einer
-- leeren Datenbank (supabase/test/run.sh, Stufe 2) hat es gezeigt.
--
-- Eine Zeile `-- verdichter: baut …` gehört hier ausdrücklich **nicht** hin.
-- Sie ist für Anweisungen gedacht, die Sichten aus zusammengesetztem SQL
-- bauen und deren Namen der Verdichter nicht sehen kann. Diese fünf sind
-- gewöhnliche `create or replace view` — er erkennt und sortiert sie selbst.
-- Mit der Marke hielt er die fünf für **eine** Anweisung, die fünf Objekte
-- baut, und schrieb sie an jede Stelle, an der eines davon gebraucht wurde:
-- derselbe Block zweimal in setup.sql.

create or replace view v_auftrag_wasch_paletten as
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

create or replace view v_auftrag_masse as
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
    COALESCE(m.eingang_netto_kg, wp.kg, gb.kg, fp.kg) AS eingang_netto_kg,
        CASE
            WHEN m.masse_quelle <> 'fehlt'::text THEN m.masse_quelle
            WHEN wp.kg IS NOT NULL THEN 'wasch_paletten'::text
            WHEN gb.kg IS NOT NULL THEN 'gebinde'::text
            WHEN fp.kg IS NOT NULL THEN 'fax_paletten'::text
            ELSE 'fehlt'::text
        END AS masse_quelle,
    zahl(COALESCE(m.lagertage,
        CASE
            WHEN m.station = 'waschen'::station THEN (betriebstag(m.start_ts) - '2000-01-01'::date)::numeric - COALESCE(se.tage_seit_epoche, (r.eingangsdatum_mittel - '2000-01-01'::date)::numeric)
            ELSE NULL::numeric
        END), 1, '1000000000'::numeric)::numeric(10,1) AS lagertage,
    a.ist_fax,
    wp.zwischenlager_tage
   FROM mv_auftrag_masse m
     JOIN auftrag a ON a.id = m.auftrag_id
     LEFT JOIN mv_sortier_eingang se ON se.charge_nr = m.charge_nr
     LEFT JOIN v_charge_rueckgrat r ON r.charge_nr = m.charge_nr
     LEFT JOIN v_auftrag_wasch_paletten wp ON wp.auftrag_id = m.auftrag_id
     LEFT JOIN ( SELECT v_auftrag_gebinde_masse.auftrag_id,
            sum(v_auftrag_gebinde_masse.kg) AS kg
           FROM v_auftrag_gebinde_masse
          GROUP BY v_auftrag_gebinde_masse.auftrag_id) gb ON gb.auftrag_id = m.auftrag_id
     LEFT JOIN LATERAL ( SELECT zahl(a.paletten_gesamt::numeric * p.netto_kg, 2, '10000000000'::numeric)::numeric(12,2) AS kg
           FROM v_koeff_palette_netto p
          WHERE a.ist_fax AND a.paletten_gesamt > 0 AND p.sorte = m.sorte AND (p.kistensystem = a.kistensystem OR p.kistensystem IS NULL AND a.kistensystem IS DISTINCT FROM 'anderes'::text)
          ORDER BY (p.kistensystem = a.kistensystem) DESC NULLS LAST
         LIMIT 1) fp ON true;

-- v_durchsatz: 2 Cast(s)
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

-- ---------- 15. Fax: Paletten gezählt, Tage seit dem Waschen -------------
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
       -- neu (0060)
       a.paletten_gesamt, a.tage_seit_waschen, a.kistensystem
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_auftrag_masse m on m.auftrag_id = a.id
  left join v_schimmel_menge s on s.auftrag_id = a.id
  left join (select auftrag_id, sum(anzahl)::int as kisten from auftrag_gebinde group by auftrag_id) g
         on g.auftrag_id = a.id
 where a.ist_fax and a.abgebrochen_ts is null;

-- ---------- 2. Die Basis rechnet bis heute -----------------------------------
-- v_kaskade_basis.stichtag war der Tag, bis zu dem die Ware im Haus gealtert
-- wurde: das Saisonende. Jetzt ist es heute(). mv_kaskade liest die Spalte
-- beim Erneuern — die Kaskade selbst bleibt, wie sie ist. Zwei neue Spalten
-- am Ende sagen es deutlich.
create or replace view v_kaskade_basis with (security_invoker = true) as
with stichtag as (
  -- 0061: bis heute — nicht bis zum Saisonende. Der Name bleibt, weil
  -- mv_kaskade die Spalte so liest; die Spalten heute/saison_ende am Ende
  -- sagen, was gemeint ist.
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
       -- Gegenproben aus den (punktuell) erfassten Arbeiten — keine Mengen
       -- für Überblick oder Ursachen, nur für Modell-gegen-CSV.
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
       -- neu (0061)
       heute()                                                                as heute,
       stichtag()                                                             as saison_ende
  from v_charge_rueckgrat r
  cross join stichtag s
  left join anteil a on a.charge_nr = r.charge_nr
  left join kohorte k on k.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;

create or replace view v_verarbeitung_alter as
WITH gezaehlt AS (
         SELECT ap.auftrag_id,
            count(*)::integer AS n_paletten,
            zahl(avg(betriebstag(a_1.start_ts) - ap.eingangsdatum), 1, '1000000000'::numeric)::numeric(10,1) AS alter_verarbeitet
           FROM auftrag_palette ap
             JOIN auftrag a_1 ON a_1.id = ap.auftrag_id
          WHERE ap.eingangsdatum IS NOT NULL AND a_1.abgebrochen_ts IS NULL
          GROUP BY ap.auftrag_id
        ), charge_am_tag AS (
         SELECT a_1.id AS auftrag_id,
            zahl(avg(betriebstag(a_1.start_ts) - p.eingangsdatum), 1, '1000000000'::numeric)::numeric(10,1) AS alter_charge
           FROM auftrag a_1
             JOIN palette p ON p.charge_nr = a_1.charge_nr AND p.eingangsdatum <= betriebstag(a_1.start_ts)
          WHERE a_1.abgebrochen_ts IS NULL
          GROUP BY a_1.id
        )
 SELECT a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    c.schlag,
    a.station,
    a.weg,
    betriebstag(a.start_ts) AS tag,
    g.n_paletten,
    g.alter_verarbeitet,
    l.alter_charge,
    zahl(g.alter_verarbeitet - l.alter_charge, 1, '1000000000'::numeric)::numeric(10,1) AS differenz
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gezaehlt g ON g.auftrag_id = a.id
     LEFT JOIN charge_am_tag l ON l.auftrag_id = a.id
  WHERE a.abgebrochen_ts IS NULL AND a.station <> 'waschen'::station;

create or replace view v_verdunstung_messung as
SELECT w.id,
    w.charge_nr,
    c.sorte,
    c.schlag,
    w.palette_id,
    w.eingangsdatum,
    w.wiege_ts,
    w.sichtbar_schimmel,
    w.erfasser,
    w.auftrag_id,
    n.netto_damals_kg,
    n.netto_jetzt_kg,
    betriebstag(w.wiege_ts) - w.eingangsdatum AS lagertage,
    zahl(
        CASE
            WHEN n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (betriebstag(w.wiege_ts) - w.eingangsdatum) > 0 THEN 1::numeric - power(n.netto_jetzt_kg / n.netto_damals_kg, 1.0 / (betriebstag(w.wiege_ts) - w.eingangsdatum)::numeric)
            ELSE NULL::numeric
        END, 6, '10000'::numeric)::numeric(10,6) AS rate_pro_tag,
    w.gemessen AND NOT w.sichtbar_schimmel AND n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (betriebstag(w.wiege_ts) - w.eingangsdatum) > 0 AND n.netto_jetzt_kg <= (n.netto_damals_kg * 1.01) AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AS verwendbar
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_damals_kg,
            w.brutto_jetzt_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_jetzt_kg) n;


-- =====================================================================
-- aus 0018_koeffizienten_gepoolt.sql
-- =====================================================================

-- =====================================================================
-- 0018 — Koeffizienten massegewichtet, chargen-robust und teilgebündelt
--
-- Nach 0017 trifft der Schimmel. Was übrig bleibt, misst der Harness so
-- (25 Saisons, 50 % im Lager):
--
--   Ausschuss zu klein   Verzerrung −0.1 %   Bereich 0.8 % breit   Überdeckung 44 %
--
-- Der Punktwert stimmt, der Bereich ist eine Behauptung. Vier Gründe, alle
-- im Code nachweisbar, alle hier behoben.
--
-- ---------- 1. Gewichteter Mittelwert, ungewichtete Streuung --------------
-- v_koeff_ausschuss bildete den Mittelwert massegewichtet
--   sum(anteil * basis_kg) / sum(basis_kg)
-- die Streuung daneben aber ungewichtet
--   stddev_samp(anteil)
-- Das sind zwei verschiedene Grössen; die zweite beschreibt die erste nicht.
--
-- ---------- 2. n zählt Messungen, nicht unabhängige Gruppen ---------------
-- Auf dem Testbestand:
--
--   Sorte        Messungen   Chargen
--   Kaori Kuri       51         2
--   Tiana            36         1
--   Fictor           35         1
--
-- Mit n = 51 in mittel ± 1.96·sd/√n kommt ein Bereich von 0.8 % Breite
-- heraus. Tatsächlich stammen die 51 Messungen aus zwei Chargen — gleicher
-- Schlag, gleiche Ernte, gleiche Sortiereinstellung. Sie sind keine 51
-- unabhängigen Ziehungen. Bei Tiana ist es *eine* Charge: daraus lässt sich
-- die Streuung zwischen Chargen gar nicht schätzen.
--
-- ---------- 3. Verdunstung war massenungewichtet --------------------------
-- v_verdunstung_stichprobe nahm avg(rate_pro_tag): eine 400-kg-Palette zählte
-- so viel wie eine 900-kg-Palette, obwohl sie halb so viel Masse vertritt.
--
-- ---------- 4. Harte Schwelle statt Teilbündelung -------------------------
-- „eigene Sorte ab n ≥ 3, sonst global" springt: bei n = 2 gilt der globale
-- Wert voll, bei n = 3 der eigene voll — obwohl sich zwischen den beiden
-- Fällen fast nichts geändert hat. Ersetzt durch empirisches Bayes: der
-- Sortenwert wird mit dem Gewicht
--
--   B = τ² / (τ² + Fehler²)
--
-- zum Gesamtwert gezogen, wobei τ² die geschätzte echte Streuung zwischen
-- den Sorten ist. Viele verlässliche eigene Messungen → B nahe 1, der eigene
-- Wert zählt. Wenige oder aus nur einer Charge → B nahe 0, der Gesamtwert
-- trägt. Kein Sprung, und keine Sorte behauptet mehr Sicherheit als sie hat.
--
-- Alle drei Koeffizienten sind derselbe Schätzer — ein massegewichteter
-- Anteil — und werden deshalb hier einmal gemeinsam gerechnet statt dreimal
-- fast gleich.
-- =====================================================================

-- ---------- Die Rohbeobachtungen -----------------------------------------
-- Zwei getrennte Quellen, und zwar zwingend: v_ausschuss_beobachtung rechnet
-- die Basismasse der Handmessungen um die Verdunstung herunter und liest dazu
-- v_koeff_verdunstung. Läge alles in einer Ansicht, hinge der
-- Verdunstungskoeffizient über den Umweg an sich selbst — Postgres bricht das
-- mit „infinite recursion in rules" ab, und zu Recht.
create or replace view v_koeff_roh_verdunstung with (security_invoker = true) as
-- Tagesrate je gewogener Palette, gewichtet mit der Masse, die sie vertritt.
select 'verdunstung'::text as art, m.sorte, m.charge_nr,
       m.rate_pro_tag::numeric as anteil, m.netto_jetzt_kg::numeric as gewicht
  from v_verdunstung_messung m
 where m.verwendbar and m.netto_jetzt_kg > 0;

-- Derselbe Schätzer zweimal — er kann nicht über beide Quellen laufen, ohne
-- den Zyklus oben wieder aufzumachen. Änderungen gehören in beide.

-- ---------- Schätzer: Verdunstung ----------
create or replace view v_koeff_verdunstung_geschaetzt with (security_invoker = true) as
with roh as materialized (
  select art, sorte, charge_nr, anteil, gewicht from v_koeff_roh_verdunstung
   where anteil is not null and gewicht > 0
),
je_charge as (
  -- Ein Durchgang. Alles Weitere braucht nur noch diese Summen je Charge:
  -- Σw·Anteil und Σw. Frühere Fassungen scannten die Beobachtungen einmal je
  -- Sorte und brauchten 3.2 s allein für v_koeff_ausschuss.
  select art, sorte, charge_nr,
         sum(gewicht)          as sw_c,
         sum(anteil * gewicht) as swa_c,
         count(*)              as n_c
    from roh group by art, sorte, charge_nr
),
ebene as (
  -- Sortenebene und Gesamtebene (sorte = NULL) in einem Durchgang
  select art, sorte, sum(sw_c) as sw, sum(swa_c) as swa,
         sum(n_c)::int as n, count(distinct charge_nr)::int as c_chargen
    from je_charge
   group by grouping sets ((art, sorte), (art))
),
mittelwert as (
  select e.*, e.swa / nullif(e.sw, 0) as mittel from ebene e
),
varianz as (
  -- Chargen-robuste Varianz des massegewichteten Anteils. Die gewichtete
  -- Abweichungssumme einer Charge ist Σw·Anteil − Mittel·Σw, also direkt aus
  -- den Chargensummen zu haben. Die Streuung *dieser Summen* ist der Fehler;
  -- mit einer einzigen Charge gibt es nichts zu streuen und sie bleibt NULL.
  select m.*, v.varianz
    from mittelwert m
    cross join lateral (
      select case when m.c_chargen > 1 and m.sw > 0
                  then sum(power(j.swa_c - m.mittel * j.sw_c, 2)) / power(m.sw, 2)
                       * m.c_chargen::numeric / (m.c_chargen - 1) end as varianz
        from je_charge j
       where j.art = m.art and (m.sorte is null or j.sorte = m.sorte)
    ) v
),
gesamt as (
  select art, mittel, varianz, c_chargen, n, sw from varianz where sorte is null
),
tau as (
  -- τ²: wie stark sich die Sorten *wirklich* unterscheiden. Die beobachtete
  -- Streuung der Sortenmittel enthält auch den eigenen Schätzfehler; der wird
  -- abgezogen (Momentenschätzer). Bleibt nichts übrig, unterscheiden sich die
  -- Sorten nicht nachweisbar und es wird voll gebündelt.
  select v.art,
         greatest(
           sum(v.sw * power(v.mittel - g.mittel, 2)) / nullif(sum(v.sw), 0)
           - coalesce(avg(v.varianz), 0), 0) as tau2
    from varianz v join gesamt g on g.art = v.art
   where v.sorte is not null
   group by v.art
),
gitter as (
  -- Jede Sorte des Stammdatensatzes bekommt eine Zeile, auch die ungemessene.
  -- Sonst fiele sie ganz heraus und ihr Koeffizient stünde auf 0 — also „kein
  -- Verlust", was schlicht falsch ist.
  select a.art, sk.sorte from (select distinct art from roh) a cross join sorte_kaliber sk
  union all
  select art, null::text from (select distinct art from roh) a
)
select gi.art, gi.sorte, coalesce(v.n, 0) as n, coalesce(v.c_chargen, 0) as c_chargen,
       v.mittel                                            as mittel_roh,
       v.varianz                                           as varianz_roh,
       g.mittel                                            as mittel_gesamt,
       t.tau2,
       -- Bündelungsgewicht: 0 = ganz der Gesamtwert, 1 = ganz der eigene
       b.gewicht                                           as b,
       -- coalesce, weil eine Sorte ohne eigene Messung kein v.mittel hat;
       -- b ist dann 0 und es bleibt genau der Gesamtwert stehen.
       (b.gewicht * coalesce(v.mittel, g.mittel)
        + (1 - b.gewicht) * g.mittel)                      as mittel,
       -- Fehler des gebündelten Werts: der eigene, um B geschrumpft, plus
       -- der Rest-Anteil am Fehler des Gesamtwerts.
       (b.gewicht * coalesce(v.varianz, 0)
        + power(1 - b.gewicht, 2) * coalesce(g.varianz, 0)) as varianz,
       -- Freiheitsgrade: so viele unabhängige Chargen, wie tatsächlich
       -- eingehen — zwischen der eigenen Zahl und der des Gesamtwerts.
       greatest(round(b.gewicht * coalesce(v.c_chargen, 0)
                      + (1 - b.gewicht) * g.c_chargen)::int - 1, 1) as df,
       g.n                                                 as n_gesamt,
       -- Für die Fehlerfortpflanzung: der eigene, unabhängige Anteil am
       -- Fehler und das Gewicht, mit dem der (allen Sorten gemeinsame)
       -- Gesamtwert eingeht. Die beiden dürfen nicht wie unabhängige Fehler
       -- addiert werden — der Gesamtwert ist derselbe für jede Sorte.
       power(b.gewicht, 2) * coalesce(v.varianz, 0)        as varianz_eigen,
       (1 - b.gewicht)                                     as gewicht_gesamt,
       coalesce(g.varianz, 0)                              as varianz_gesamt
  from gitter gi
  join gesamt g on g.art = gi.art
  left join varianz v on v.art = gi.art and v.sorte is not distinct from gi.sorte
  left join tau t on t.art = gi.art
  cross join lateral (
    select case when gi.sorte is null then 1.0
                when v.varianz is null or v.mittel is null
                     or coalesce(t.tau2, 0) = 0 then 0.0
                else t.tau2 / (t.tau2 + v.varianz) end as gewicht
  ) b;

-- ---------- 2. Die Rate je Sorte: nie negativ -----------------------------
create or replace view v_koeff_verdunstung with (security_invoker = true) as
select sk.sorte,
       -- 0056: Verdunstung nimmt Masse, sie gibt keine. Ein Mittel unter 0
       -- kommt nur aus Waagenrauschen und heisst „keine messbare Verdunstung".
       -- NULL bleibt NULL: ohne Wiegung ist die Rate unbekannt, nicht 0.
       (case when k.mittel < 0 then 0 else k.mittel end)::numeric          as mittel,
       (case when coalesce(k.varianz, 0) = 0
               then case when k.mittel < 0 then 0 else k.mittel end
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                          as unten,
       (case when coalesce(k.varianz, 0) = 0
               then case when k.mittel < 0 then 0 else k.mittel end
             else greatest(k.mittel + k.t * sqrt(k.varianz), 0)
        end)::double precision                                          as oben,
       coalesce(k.n, 0)                                                 as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Wiegung vorhanden'
            when k.b >= 0.67        then 'Wiegungen dieser Sorte'
            when k.b >= 0.33        then 'Wiegungen dieser Sorte, zum Gesamtwert gezogen'
            else 'Wiegungen aller Sorten (zu wenige eigene Chargen)' end as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_verdunstung_geschaetzt g
     where g.art = 'verdunstung' and g.sorte is not distinct from sk.sorte
  ) k on true;

-- v_ausschuss_beobachtung: 1 Cast(s)
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
    anteil_plausibel(h.klein_kg / NULLIF(n.basis, 0::numeric)) AND anteil_plausibel(COALESCE(h.gross_kg, 0::numeric) / NULLIF(n.basis, 0::numeric)) AS plausibel
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

-- v_koeff_roh_kaliber: 1 Cast(s)
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

-- ---------- Schätzer: Ausschuss zu klein und Nebenkanal zu gross ----------
create or replace view v_koeff_kaliber_geschaetzt with (security_invoker = true) as
with roh as materialized (
  select art, sorte, charge_nr, anteil, gewicht from v_koeff_roh_kaliber
   where anteil is not null and gewicht > 0
),
je_charge as (
  -- Ein Durchgang. Alles Weitere braucht nur noch diese Summen je Charge:
  -- Σw·Anteil und Σw. Frühere Fassungen scannten die Beobachtungen einmal je
  -- Sorte und brauchten 3.2 s allein für v_koeff_ausschuss.
  select art, sorte, charge_nr,
         sum(gewicht)          as sw_c,
         sum(anteil * gewicht) as swa_c,
         count(*)              as n_c
    from roh group by art, sorte, charge_nr
),
ebene as (
  -- Sortenebene und Gesamtebene (sorte = NULL) in einem Durchgang
  select art, sorte, sum(sw_c) as sw, sum(swa_c) as swa,
         sum(n_c)::int as n, count(distinct charge_nr)::int as c_chargen
    from je_charge
   group by grouping sets ((art, sorte), (art))
),
mittelwert as (
  select e.*, e.swa / nullif(e.sw, 0) as mittel from ebene e
),
varianz as (
  -- Chargen-robuste Varianz des massegewichteten Anteils. Die gewichtete
  -- Abweichungssumme einer Charge ist Σw·Anteil − Mittel·Σw, also direkt aus
  -- den Chargensummen zu haben. Die Streuung *dieser Summen* ist der Fehler;
  -- mit einer einzigen Charge gibt es nichts zu streuen und sie bleibt NULL.
  select m.*, v.varianz
    from mittelwert m
    cross join lateral (
      select case when m.c_chargen > 1 and m.sw > 0
                  then sum(power(j.swa_c - m.mittel * j.sw_c, 2)) / power(m.sw, 2)
                       * m.c_chargen::numeric / (m.c_chargen - 1) end as varianz
        from je_charge j
       where j.art = m.art and (m.sorte is null or j.sorte = m.sorte)
    ) v
),
gesamt as (
  select art, mittel, varianz, c_chargen, n, sw from varianz where sorte is null
),
tau as (
  -- τ²: wie stark sich die Sorten *wirklich* unterscheiden. Die beobachtete
  -- Streuung der Sortenmittel enthält auch den eigenen Schätzfehler; der wird
  -- abgezogen (Momentenschätzer). Bleibt nichts übrig, unterscheiden sich die
  -- Sorten nicht nachweisbar und es wird voll gebündelt.
  select v.art,
         greatest(
           sum(v.sw * power(v.mittel - g.mittel, 2)) / nullif(sum(v.sw), 0)
           - coalesce(avg(v.varianz), 0), 0) as tau2
    from varianz v join gesamt g on g.art = v.art
   where v.sorte is not null
   group by v.art
),
gitter as (
  -- Jede Sorte des Stammdatensatzes bekommt eine Zeile, auch die ungemessene.
  -- Sonst fiele sie ganz heraus und ihr Koeffizient stünde auf 0 — also „kein
  -- Verlust", was schlicht falsch ist.
  select a.art, sk.sorte from (select distinct art from roh) a cross join sorte_kaliber sk
  union all
  select art, null::text from (select distinct art from roh) a
)
select gi.art, gi.sorte, coalesce(v.n, 0) as n, coalesce(v.c_chargen, 0) as c_chargen,
       v.mittel                                            as mittel_roh,
       v.varianz                                           as varianz_roh,
       g.mittel                                            as mittel_gesamt,
       t.tau2,
       -- Bündelungsgewicht: 0 = ganz der Gesamtwert, 1 = ganz der eigene
       b.gewicht                                           as b,
       -- coalesce, weil eine Sorte ohne eigene Messung kein v.mittel hat;
       -- b ist dann 0 und es bleibt genau der Gesamtwert stehen.
       (b.gewicht * coalesce(v.mittel, g.mittel)
        + (1 - b.gewicht) * g.mittel)                      as mittel,
       -- Fehler des gebündelten Werts: der eigene, um B geschrumpft, plus
       -- der Rest-Anteil am Fehler des Gesamtwerts.
       (b.gewicht * coalesce(v.varianz, 0)
        + power(1 - b.gewicht, 2) * coalesce(g.varianz, 0)) as varianz,
       -- Freiheitsgrade: so viele unabhängige Chargen, wie tatsächlich
       -- eingehen — zwischen der eigenen Zahl und der des Gesamtwerts.
       greatest(round(b.gewicht * coalesce(v.c_chargen, 0)
                      + (1 - b.gewicht) * g.c_chargen)::int - 1, 1) as df,
       g.n                                                 as n_gesamt,
       -- Für die Fehlerfortpflanzung: der eigene, unabhängige Anteil am
       -- Fehler und das Gewicht, mit dem der (allen Sorten gemeinsame)
       -- Gesamtwert eingeht. Die beiden dürfen nicht wie unabhängige Fehler
       -- addiert werden — der Gesamtwert ist derselbe für jede Sorte.
       power(b.gewicht, 2) * coalesce(v.varianz, 0)        as varianz_eigen,
       (1 - b.gewicht)                                     as gewicht_gesamt,
       coalesce(g.varianz, 0)                              as varianz_gesamt
  from gitter gi
  join gesamt g on g.art = gi.art
  left join varianz v on v.art = gi.art and v.sorte is not distinct from gi.sorte
  left join tau t on t.art = gi.art
  cross join lateral (
    select case when gi.sorte is null then 1.0
                when v.varianz is null or v.mittel is null
                     or coalesce(t.tau2, 0) = 0 then 0.0
                else t.tau2 / (t.tau2 + v.varianz) end as gewicht
  ) b;

-- ---------- Unsicherheit aller Koeffizienten an einer Stelle --------------
-- Wird nur von der Fehlerfortpflanzung gelesen, nie von den Koeffizienten
-- selbst — sonst wäre der Zyklus von oben wieder da.
create or replace view v_koeff_unsicherheit with (security_invoker = true) as
select art, sorte, b, varianz_eigen, gewicht_gesamt, varianz_gesamt, df
  from v_koeff_verdunstung_geschaetzt
union all
select art, sorte, b, varianz_eigen, gewicht_gesamt, varianz_gesamt, df
  from v_koeff_kaliber_geschaetzt;

create or replace view v_koeff_ausschuss with (security_invoker = true) as
select sk.sorte,
       k.mittel::numeric                                                    as mittel,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                              as unten,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else least(k.mittel + k.t * sqrt(k.varianz), 1)
        end)::double precision                                              as oben,
       coalesce(k.n, 0)                                                     as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Messung vorhanden'
            when k.b >= 0.67     then 'Sortierläufe/Handmessungen dieser Sorte'
            when k.b >= 0.33     then 'eigene Messungen, zum Gesamtwert gezogen'
            else 'alle Sorten (zu wenige eigene Chargen)' end               as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'ausschuss' and g.sorte is not distinct from sk.sorte
  ) k on true;

create or replace view v_koeff_nebenkanal with (security_invoker = true) as
select sk.sorte,
       k.mittel::numeric                                                    as mittel,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                              as unten,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else least(k.mittel + k.t * sqrt(k.varianz), 1)
        end)::double precision                                              as oben,
       coalesce(k.n, 0)                                                     as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Messung vorhanden'
            when k.b >= 0.67     then 'Sortierläufe/Handmessungen dieser Sorte'
            when k.b >= 0.33     then 'eigene Messungen, zum Gesamtwert gezogen'
            else 'alle Sorten (zu wenige eigene Chargen)' end               as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'nebenkanal' and g.sorte is not distinct from sk.sorte
  ) k on true;

create or replace view v_koeff_fax with (security_invoker = true) as
select sk.sorte,
       k.mittel::numeric                                                    as mittel,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                              as unten,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else least(k.mittel + k.t * sqrt(k.varianz), 1)
        end)::double precision                                              as oben,
       coalesce(k.n, 0)                                                     as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Fax-Arbeit mit gewogenem Faulem'
            when k.b >= 0.67     then 'Fax-Arbeiten dieser Sorte'
            when k.b >= 0.33     then 'eigene Fax-Arbeiten, zum Gesamtwert gezogen'
            else 'alle Sorten (zu wenige eigene Chargen)' end               as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'fax' and g.sorte is not distinct from sk.sorte
  ) k on true;

-- v_schimmel_beobachtung: 1 Cast(s)
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
    zahl((am.eingang_netto_kg * power(1::numeric - x.r, x.tage)), 2, 1e10)::numeric(12,2) AS basis_jetzt_kg,
    s.kg / NULLIF(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 0::numeric) AS anteil,
    anteil_plausibel(s.kg / NULLIF(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 0::numeric)) AS plausibel,
    am.ist_fax
   FROM v_auftrag_masse am
     JOIN v_schimmel_menge s ON s.auftrag_id = am.auftrag_id
     LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = am.sorte
     CROSS JOIN LATERAL ( SELECT LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            GREATEST(am.lagertage, 0::numeric) AS tage) x
  WHERE am.eingang_netto_kg IS NOT NULL AND am.lagertage IS NOT NULL;

create or replace view v_schimmel_punkte with (security_invoker = true) as
with sortier_lauf_anteil as materialized (
  select b.charge_nr, b.start_ts, b.schimmel_kg, b.basis_jetzt_kg
    from v_schimmel_beobachtung b
   where b.station = 'sortieren' and b.plausibel and b.anteil is not null
), gemischt as (
  select auftrag_id from v_auftrag_angabe where schluessel = 'eine_charge' and wert = 'false'
)
select b.charge_nr, b.sorte, b.schlag, b.lagertage, b.schimmel_kg,
       b.basis_jetzt_kg, b.anteil, b.plausibel,
       case when g.auftrag_id is not null then 'verarbeitung_gemischt' else 'verarbeitung' end::text as quelle,
       b.auftrag_id
  from v_schimmel_beobachtung b
  left join gemischt g on g.auftrag_id = b.auftrag_id
 where b.station in ('sortieren', 'waschen_sortieren')
union all
select a.charge_nr, a.sorte, a.schlag, a.lagertage,
       s.kg                                                      as schimmel_kg,
       (a.eingang_netto_kg + s.kg)                               as basis_jetzt_kg,
       k.f2                                                      as anteil,
       anteil_plausibel(k.f2)                                    as plausibel,
       case when g.auftrag_id is not null then 'verarbeitung_gemischt' else 'verarbeitung' end,
       a.auftrag_id
  from v_auftrag_masse a
  join v_schimmel_menge s on s.auftrag_id = a.auftrag_id
  left join gemischt g on g.auftrag_id = a.auftrag_id
  left join lateral (
    select sum(sl.schimmel_kg) / nullif(sum(sl.basis_jetzt_kg), 0) as f1
      from sortier_lauf_anteil sl
     where sl.charge_nr = a.charge_nr and sl.start_ts <= a.start_ts
  ) sa on true
  cross join lateral (
    select s.kg / nullif(a.eingang_netto_kg + s.kg, 0)            as g
  ) x
  cross join lateral (
    select 1 - (1 - least(greatest(coalesce(sa.f1, 0), 0), 0.99))
             * (1 - least(greatest(coalesce(x.g, 0), 0), 0.99))   as f2
  ) k
 where a.station = 'waschen' and not a.ist_fax and a.lagertage is not null
   and a.eingang_netto_kg is not null and a.eingang_netto_kg > 0
union all
select w.charge_nr, w.sorte, w.schlag, w.lagertage,
       v.faul_kg, w.netto_jetzt_kg,
       v.faul_kg / nullif(w.netto_jetzt_kg, 0),
       anteil_plausibel(v.faul_kg / nullif(w.netto_jetzt_kg, 0)),
       'lager', null::bigint
  from v_verdunstung_messung w
  join verdunstung_wiegung v on v.id = w.id
 where v.faul_kg is not null and v.gemessen
   and w.netto_jetzt_kg > 0 and w.lagertage > 0;

-- ---------- Die Schimmelpunkte speichern ----------------------------------
create materialized view if not exists mv_schimmel_punkte as
select * from v_schimmel_punkte with no data;

-- Das Modell liest seit 0037 nur quelle in (verarbeitung, lager) — der neue
-- dritte Wert bleibt ihm damit von selbst fern. Die Treppe (Rückfall) muss
-- es ausdrücklich tun:
create or replace view v_schimmel_kurve with (security_invoker = true) as
with klassen(von, bis) as (
  values (0,14), (15,30), (31,60), (61,90), (91,120), (121,180), (181,100000)
), je_klasse as (
  select k.von, k.bis,
         count(b.anteil)::int as n,
         sum(b.schimmel_kg) / nullif(sum(b.basis_jetzt_kg), 0) as anteil,
         stddev_samp(b.anteil) as sd
    from klassen k
    left join mv_schimmel_punkte b
           on b.lagertage >= k.von and b.lagertage <= k.bis
          and b.anteil is not null and b.plausibel
          and b.quelle in ('verarbeitung', 'lager')
   group by k.von, k.bis
)
select von, bis, n, anteil, sd,
       least(greatest(max(anteil) over (order by von
             rows between unbounded preceding and current row), 0), 1) as anteil_mono,
       case when n >= 2 then greatest(anteil - 1.96 * sd / sqrt(n), 0) end as unten,
       case when n >= 2 then least(anteil + 1.96 * sd / sqrt(n), 1) end   as oben
  from je_klasse;

-- v_schimmel_modell_rechnen: 2 Cast(s)
create or replace view v_schimmel_modell_rechnen with (security_invoker = true) as
 WITH roh AS (
         SELECT b.charge_nr,
            b.lagertage AS t,
            b.anteil AS f,
            b.basis_jetzt_kg AS w,
            b.quelle = 'verarbeitung'::text AS mit_sockel
           FROM mv_schimmel_punkte b
          WHERE b.plausibel AND b.anteil > 0::numeric AND b.anteil < 1::numeric AND b.lagertage > 0::numeric AND (b.quelle = ANY (ARRAY['verarbeitung'::text, 'lager'::text]))
        ), chargen AS (
         SELECT count(DISTINCT roh.charge_nr)::integer AS c
           FROM roh
        ), gitter AS (
         SELECT i.i::numeric * 0.0025 AS a0
           FROM generate_series(0, 40) i(i)
        ), kand AS (
         SELECT g.a0,
            r.charge_nr,
            r.t,
            r.f,
            r.w,
            r.mit_sockel,
            ln(r.t) AS x,
                CASE
                    WHEN r.mit_sockel THEN (r.f - g.a0) / (1::numeric - g.a0)
                    ELSE r.f
                END AS fs
           FROM gitter g
             CROSS JOIN roh r
        ), fit AS (
         SELECT q.a0,
            count(*)::integer AS n,
            count(DISTINCT q.charge_nr)::integer AS c_chargen,
            sum(q.w) AS sw,
            sum(q.w * q.x) AS swx,
            sum(q.w * q.y) AS swy,
            sum(q.w * q.x * q.x) AS swxx,
            sum(q.w * q.x * q.y) AS swxy
           FROM ( SELECT kand.a0,
                    kand.charge_nr,
                    kand.w,
                    kand.x,
                    ln(- ln(1::numeric - kand.fs)) AS y
                   FROM kand
                  WHERE kand.fs > 0::numeric AND kand.fs < 1::numeric) q
          GROUP BY q.a0
        ), param AS (
         SELECT f.a0,
            f.n,
            f.c_chargen,
            f.sw,
            f.swx,
            f.swy,
            f.swxx,
            f.swxy,
                CASE
                    WHEN (f.sw * f.swxx - f.swx * f.swx) <> 0::numeric THEN (f.sw * f.swxy - f.swx * f.swy) / (f.sw * f.swxx - f.swx * f.swx)
                    ELSE NULL::numeric
                END AS k
           FROM fit f
        ), param2 AS (
         SELECT p.a0,
            p.n,
            p.c_chargen,
            p.sw,
            p.swx,
            p.swy,
            p.swxx,
            p.swxy,
            p.k,
                CASE
                    WHEN p.k IS NOT NULL THEN (p.swy - p.k * p.swx) / p.sw
                    ELSE NULL::numeric
                END AS ln_lambda
           FROM param p
        ), smear AS (
         SELECT p.a0,
            sum(k.w * exp(ln(- ln(1::numeric - k.fs)) - (p.ln_lambda + p.k * k.x))) / NULLIF(sum(k.w), 0::numeric) AS s
           FROM param2 p
             JOIN kand k ON k.a0 = p.a0
          WHERE k.fs > 0::numeric AND k.fs < 1::numeric AND p.k IS NOT NULL
          GROUP BY p.a0
        ), guete AS (
         SELECT p.a0,
            p.n,
            p.c_chargen,
            p.k,
            p.ln_lambda,
            s.s AS smearing,
            sum(k.w * power(k.f - (
                CASE
                    WHEN k.mit_sockel THEN p.a0
                    ELSE 0::numeric
                END + (1::numeric -
                CASE
                    WHEN k.mit_sockel THEN p.a0
                    ELSE 0::numeric
                END) * (1::numeric - exp(- exp(LEAST(GREATEST(p.ln_lambda + ln(GREATEST(s.s, 0.01)) + p.k * k.x, '-40'::integer::numeric), 3::numeric))))), 2::numeric)) AS sse
           FROM param2 p
             JOIN smear s ON s.a0 = p.a0
             JOIN kand k ON k.a0 = p.a0
          WHERE p.k IS NOT NULL AND p.k > 0::numeric AND p.n >= 3
          GROUP BY p.a0, p.n, p.c_chargen, p.k, p.ln_lambda, s.s
        ), schwelle AS (
         SELECT 1::numeric + power(t_quantil_95(GREATEST(c.c - 3, 1)), 2::numeric) / GREATEST(c.c - 3, 1)::numeric AS faktor
           FROM chargen c
        ), wahl AS (
         SELECT g.a0,
            g.n,
            g.c_chargen,
            g.k,
            g.ln_lambda,
            g.smearing,
            g.sse
           FROM guete g
          WHERE g.sse <= ((( SELECT min(guete.sse) AS min
                   FROM guete)) * 1.01) AND (( SELECT guete.sse
                   FROM guete
                  WHERE guete.a0 = 0::numeric)) > ((( SELECT min(guete.sse) AS min
                   FROM guete)) * (( SELECT schwelle.faktor
                   FROM schwelle)))
          ORDER BY g.a0
         LIMIT 1
        ), gewaehlt AS (
         SELECT COALESCE(( SELECT wahl.a0
                   FROM wahl), 0::numeric) AS a0,
            COALESCE(( SELECT wahl.sse
                   FROM wahl), ( SELECT guete.sse
                   FROM guete
                  WHERE guete.a0 = 0::numeric)) AS sse,
            COALESCE(( SELECT wahl.n
                   FROM wahl), ( SELECT guete.n
                   FROM guete
                  WHERE guete.a0 = 0::numeric)) AS n_wahl
        ), grenzen AS (
         SELECT COALESCE(min(g.a0), w.a0) AS a0_unten,
            COALESCE(max(g.a0), w.a0) AS a0_oben
           FROM gewaehlt w
             LEFT JOIN guete g ON g.sse <= (w.sse * (( SELECT schwelle.faktor
                   FROM schwelle)))
          GROUP BY w.a0
        ), punkte AS (
         SELECT k.charge_nr,
            k.x,
            ln(- ln(1::numeric - k.fs)) AS y,
            k.w,
            k.t
           FROM kand k,
            gewaehlt g
          WHERE k.a0 = g.a0 AND k.fs > 0::numeric AND k.fs < 1::numeric
        ), summen AS (
         SELECT count(*)::integer AS n,
            count(DISTINCT punkte.charge_nr)::integer AS c_chargen,
            min(punkte.t) AS t_min,
            max(punkte.t) AS t_max,
            sum(punkte.w) AS sw,
            sum(punkte.w * punkte.x) AS swx,
            sum(punkte.w * punkte.y) AS swy,
            sum(punkte.w * punkte.x * punkte.x) AS swxx,
            sum(punkte.w * punkte.x * punkte.y) AS swxy
           FROM punkte
        ), fit2 AS (
         SELECT s.n,
            s.c_chargen,
            s.t_min,
            s.t_max,
            s.sw,
            s.swx,
            s.swy,
            s.swxx,
            s.swxy,
                CASE
                    WHEN (s.sw * s.swxx - s.swx * s.swx) <> 0::numeric THEN (s.sw * s.swxy - s.swx * s.swy) / (s.sw * s.swxx - s.swx * s.swx)
                    ELSE NULL::numeric
                END AS k,
            s.swx / NULLIF(s.sw, 0::numeric) AS x_mittel
           FROM summen s
        ), mit_achse AS (
         SELECT f.n,
            f.c_chargen,
            f.t_min,
            f.t_max,
            f.sw,
            f.swx,
            f.swy,
            f.swxx,
            f.swxy,
            f.k,
            f.x_mittel,
                CASE
                    WHEN f.k IS NOT NULL THEN (f.swy - f.k * f.swx) / f.sw
                    ELSE NULL::numeric
                END AS ln_lambda
           FROM fit2 f
        ), rest AS (
         SELECT m.n,
            m.c_chargen,
            m.t_min,
            m.t_max,
            m.sw,
            m.swx,
            m.swy,
            m.swxx,
            m.swxy,
            m.k,
            m.x_mittel,
            m.ln_lambda,
            ( SELECT sum(p.w * power(p.x - m.x_mittel, 2::numeric)) AS sum
                   FROM punkte p) AS sxx,
            ( SELECT sum(p.w * power(p.y - (m.ln_lambda + m.k * p.x), 2::numeric)) AS sum
                   FROM punkte p) AS sse,
            ( SELECT sum(p.w * exp(p.y - (m.ln_lambda + m.k * p.x))) / NULLIF(sum(p.w), 0::numeric)
                   FROM punkte p) AS smearing
           FROM mit_achse m
        ), gruppen AS (
         SELECT r.n,
            r.c_chargen,
            r.t_min,
            r.t_max,
            r.sw,
            r.swx,
            r.swy,
            r.swxx,
            r.swxy,
            r.k,
            r.x_mittel,
            r.ln_lambda,
            r.sxx,
            r.sse,
            r.smearing,
            g.saa,
            g.skk,
            g.sak
           FROM rest r
             CROSS JOIN LATERAL ( SELECT sum(power(c.ga, 2::numeric)) AS saa,
                    sum(power(c.gk, 2::numeric)) AS skk,
                    sum(c.ga * c.gk) AS sak
                   FROM ( SELECT p.charge_nr,
                            sum(p.w * (p.y - (r.ln_lambda + r.k * p.x))) AS ga,
                            sum(p.w * (p.x - r.x_mittel) * (p.y - (r.ln_lambda + r.k * p.x))) AS gk
                           FROM punkte p
                          GROUP BY p.charge_nr) c) g
        )
 SELECT n,
    c_chargen,
    t_min,
    t_max,
    k,
    ln_lambda,
    exp(ln_lambda) AS lambda,
    x_mittel,
    sxx,
    smearing,
    ln_lambda + ln(GREATEST(smearing, 0.01)) AS ln_lambda_korrigiert,
        CASE
            WHEN n > 2 THEN sse / (n - 2)::numeric * n::numeric / NULLIF(sw, 0::numeric)
            ELSE NULL::numeric
        END AS sigma2,
        CASE
            WHEN c_chargen > 1 THEN saa / power(sw, 2::numeric) * c_chargen::numeric / (c_chargen - 1)::numeric
            ELSE NULL::numeric
        END AS var_achse,
        CASE
            WHEN c_chargen > 1 AND sxx <> 0::numeric THEN skk / power(sxx, 2::numeric) * c_chargen::numeric / (c_chargen - 1)::numeric
            ELSE NULL::numeric
        END AS var_k,
        CASE
            WHEN c_chargen > 1 AND sxx <> 0::numeric THEN sak / (sw * sxx) * c_chargen::numeric / (c_chargen - 1)::numeric
            ELSE NULL::numeric
        END AS kov_achse_k,
    t_quantil_95(c_chargen - 1) AS t_faktor,
    n >= 3 AND c_chargen >= 3 AND k IS NOT NULL AND k > 0::numeric AND t_max > (t_min * 1.5) AS brauchbar,
    ( SELECT
                CASE
                    WHEN count(*) FILTER (WHERE p.mit_sockel = false) >= 5 THEN GREATEST(abs(sum(p.w * p.e) FILTER (WHERE NOT p.mit_sockel) / NULLIF(sum(p.w) FILTER (WHERE NOT p.mit_sockel), 0::numeric) - sum(p.w * p.e) FILTER (WHERE p.mit_sockel) / NULLIF(sum(p.w) FILTER (WHERE p.mit_sockel), 0::numeric))::double precision - (1.96 * stddev_samp(p.e) FILTER (WHERE NOT p.mit_sockel))::double precision / sqrt(count(*) FILTER (WHERE NOT p.mit_sockel)::double precision), 0::double precision)::numeric
                    ELSE NULL::numeric
                END AS "case"
           FROM ( SELECT k.mit_sockel,
                    k.w,
                    ln(- ln(1::numeric - k.fs)) - (gruppen.ln_lambda + gruppen.k * k.x) AS e
                   FROM kand k,
                    gewaehlt g
                  WHERE k.a0 = g.a0 AND k.fs > 0::numeric AND k.fs < 1::numeric) p) AS selektions_versatz,
    ( SELECT gewaehlt.a0
           FROM gewaehlt) AS sockel,
    ( SELECT grenzen.a0_unten
           FROM grenzen) AS sockel_unten,
    ( SELECT grenzen.a0_oben
           FROM grenzen) AS sockel_oben,
    zahl(((( SELECT guete.sse
           FROM guete
          WHERE guete.a0 = 0::numeric)) / NULLIF(( SELECT min(guete.sse) AS min
           FROM guete), 0::numeric)), 3, 1e7)::numeric(10,3) AS sockel_nachweis,
    zahl((( SELECT schwelle.faktor
           FROM schwelle)), 3, 1e7)::numeric(10,3) AS sockel_schwelle,
    power(((( SELECT grenzen.a0_oben
           FROM grenzen)) - (( SELECT grenzen.a0_unten
           FROM grenzen))) / 2.0 / NULLIF(t_quantil_95(c_chargen - 1), 0::numeric), 2::numeric) AS sockel_var
   FROM gruppen;

create materialized view mv_schimmel_modell as
select * from v_schimmel_modell_rechnen with no data;

create view v_schimmel_modell with (security_invoker = true) as
select * from mv_schimmel_modell;

-- Der Sockel als Zahl, für Ansichten, die ihn brauchen.
create or replace function sockel_anteil()
returns numeric language sql stable as $$
  select coalesce((select case when brauchbar then sockel else 0 end from public.v_schimmel_modell), 0);
$$;

-- schimmelanteil() liefert F(t) — reinen Verderb, ohne Sockel.
create or replace function schimmelanteil(p_lagertage numeric, p_szenario text default 'mittel')
returns numeric language sql stable as $$
  with m as (select * from public.v_schimmel_modell),
  u as (select m.*, ln(greatest(p_lagertage, 1)) - m.x_mittel as u from m)
  select coalesce(
    (select least(greatest(1 - exp(-exp(least(greatest(
       u.ln_lambda_korrigiert + u.k * ln(greatest(p_lagertage, 1))
       + case p_szenario when 'unten' then -1 when 'oben' then 1 else 0 end
         * u.t_faktor * sqrt(greatest(
             u.var_achse + power(u.u, 2) * u.var_k + 2 * u.u * u.kov_achse_k, 0))
       , -40), 3))), 0), 1)
       from u where u.brauchbar and u.var_achse is not null),
    (select least(greatest(coalesce(
       case p_szenario when 'unten' then coalesce(k.unten, k.anteil_mono)
                       when 'oben'  then coalesce(k.oben,  k.anteil_mono)
                       else k.anteil_mono end, 0), 0), 1)
       from public.v_schimmel_kurve k
      where k.von <= p_lagertage and k.n > 0
      order by k.von desc limit 1),
    0)::numeric;
$$;

-- ---------- Die abhängigen Ansichten, die am Modell hingen ---------------
create or replace view v_selektionsverdacht with (security_invoker = true) as
with rest as (
  select p.quelle, p.basis_jetzt_kg::numeric as w,
         ln(-ln(1 - x.fs)) - (m.ln_lambda + m.k * ln(p.lagertage::numeric)) as e
    from mv_schimmel_punkte p cross join v_schimmel_modell m
    cross join lateral (
      select case when p.quelle = 'verarbeitung'
                  then (p.anteil::numeric - m.sockel) / (1 - m.sockel)
                  else p.anteil::numeric end as fs) x
   where m.brauchbar and p.plausibel
     and x.fs > 0 and x.fs < 1 and p.lagertage > 0
), je_quelle as (
  select quelle, count(*)::int as n, sum(w * e) / nullif(sum(w), 0) as mittel
    from rest group by quelle
)
select (select n from je_quelle where quelle = 'verarbeitung')      as n_verarbeitung,
       (select n from je_quelle where quelle = 'lager')             as n_lager,
       (select mittel from je_quelle where quelle = 'verarbeitung') as rest_verarbeitung,
       (select mittel from je_quelle where quelle = 'lager')        as rest_lager,
       (select mittel from je_quelle where quelle = 'lager')
         - (select mittel from je_quelle where quelle = 'verarbeitung') as unterschied,
       case
         when (select n from je_quelle where quelle = 'lager') is null
           then 'keine Lagerkontrollen — Selektion nicht prüfbar'
         when (select n from je_quelle where quelle = 'lager') < 5
           then 'zu wenige Lagerkontrollen für eine Aussage'
         when abs((select mittel from je_quelle where quelle = 'lager')
                  - (select mittel from je_quelle where quelle = 'verarbeitung')) > 0.2
           then 'verarbeitete und zufällig gegriffene Paletten sagen Verschiedenes — '
                || 'es wird nach Aussehen ausgewählt. Bei gleichem Alter sind die '
                || 'verarbeiteten fauler, dafür bleibt am Ende die robustere Ware '
                || 'liegen: der Verlauf wird zu flach und die Hochrechnung auf lange '
                || 'Lagerdauern zu niedrig. Mehr Lagerkontrollen beheben das.'
         else 'beide Quellen sagen dasselbe — kein Hinweis auf Selektion'
       end                                                          as befund;

-- v_schimmel_kurve_anzeige: 4 Cast(s)
create or replace view v_schimmel_kurve_anzeige with (security_invoker = true) as
 SELECT von,
    bis,
        CASE
            WHEN bis > 9999 THEN von || '+ Tage'::text
            ELSE ((von || '–'::text) || bis) || ' Tage'::text
        END AS altersklasse,
    n AS messungen,
    zahl(anteil, 4, 1e6)::numeric(10,4) AS gemessen,
    zahl(schimmelanteil((von + LEAST(bis, von + 60))::numeric / 2.0), 4, 1e6)::numeric(10,4) AS verwendet,
    zahl(schimmelanteil((von + LEAST(bis, von + 60))::numeric / 2.0, 'unten'::text), 4, 1e6)::numeric(10,4) AS unten,
    zahl(schimmelanteil((von + LEAST(bis, von + 60))::numeric / 2.0, 'oben'::text), 4, 1e6)::numeric(10,4) AS oben,
        CASE
            WHEN NOT ( SELECT v_schimmel_modell.brauchbar
               FROM v_schimmel_modell) THEN 'Modell noch nicht anpassbar — es gilt die Treppenfunktion'::text
            WHEN von::numeric > (( SELECT v_schimmel_modell.t_max
               FROM v_schimmel_modell)) THEN 'über die längste gemessene Lagerdauer hinaus — hochgerechnet, '::text || 'daher der breitere Bereich'::text
            WHEN n = 0 THEN 'keine eigene Messung — aus dem Verlauf interpoliert'::text
            ELSE 'durch Messungen dieser Altersklasse gestützt'::text
        END ||
        CASE
            WHEN (( SELECT v_schimmel_modell.sockel
               FROM v_schimmel_modell)) > 0::numeric THEN format('; „gemessen" enthält den Sockel von %s %% (Erde, Hagel, Schnitt), '::text || '„verwendet" ist der reine Verderb'::text, round((( SELECT v_schimmel_modell.sockel
               FROM v_schimmel_modell)) * 100::numeric, 2))
            ELSE ''::text
        END AS erlaeuterung
   FROM v_schimmel_kurve k
  ORDER BY von;
create materialized view mv_kaskade as
WITH modell AS MATERIALIZED (
         SELECT v_schimmel_modell.n,
            v_schimmel_modell.c_chargen,
            v_schimmel_modell.t_min,
            v_schimmel_modell.t_max,
            v_schimmel_modell.k,
            v_schimmel_modell.ln_lambda,
            v_schimmel_modell.lambda,
            v_schimmel_modell.x_mittel,
            v_schimmel_modell.sxx,
            v_schimmel_modell.smearing,
            v_schimmel_modell.ln_lambda_korrigiert,
            v_schimmel_modell.sigma2,
            v_schimmel_modell.var_achse,
            v_schimmel_modell.var_k,
            v_schimmel_modell.kov_achse_k,
            v_schimmel_modell.t_faktor,
            v_schimmel_modell.brauchbar,
            v_schimmel_modell.selektions_versatz,
            v_schimmel_modell.sockel,
            v_schimmel_modell.sockel_unten,
            v_schimmel_modell.sockel_oben,
            v_schimmel_modell.sockel_nachweis,
            v_schimmel_modell.sockel_schwelle,
            v_schimmel_modell.sockel_var
           FROM v_schimmel_modell
        ), kurve AS MATERIALIZED (
         SELECT v_schimmel_kurve.von,
            v_schimmel_kurve.anteil_mono,
            v_schimmel_kurve.n
           FROM v_schimmel_kurve
          WHERE (v_schimmel_kurve.n > 0)
        ), kohorten AS MATERIALIZED (
         SELECT k_1.charge_nr,
            k_1.eingangsdatum,
            k_1.anteil,
            (b.eingang_kg * k_1.anteil) AS eingang_kg
           FROM (v_kohorte_anteil k_1
             JOIN v_kaskade_basis b ON ((b.charge_nr = k_1.charge_nr)))
        ), lieferungen AS MATERIALIZED (
         -- 0062: beide Bücher. Was als Tierfutter oder in den Nebenkanal ging,
         -- hat den Betrieb verlassen — es darf nicht weiter altern und nicht
         -- ein zweites Mal im Bestand stehen. Je Charge und Eingangstag eine
         -- Zeile, das Alter massegewichtet über die Bücher.
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            (sum((v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, (0)::numeric)))
             / NULLIF(sum(v_lieferung_kohorte.masse_kg), (0)::numeric)) AS alter_tage,
            (sum(v_lieferung_kohorte.n_lieferungen))::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE (v_lieferung_kohorte.buch = ANY (ARRAY['verkauf'::text, 'marge'::text]))
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), entsorgt_lief AS (
         -- 0065: Das dritte Buch. Was in den Kompost ging, hat den Betrieb
         -- verlassen — es liegt nicht mehr da und ist nicht mehr zu verkaufen.
         -- Bis 0064 sah die Kaskade es nicht: die Ware zählte im Ausgang und
         -- lag gleichzeitig weiter im Lager.
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            (sum((v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, (0)::numeric)))
             / NULLIF(sum(v_lieferung_kohorte.masse_kg), (0)::numeric)) AS alter_tage,
            (sum(v_lieferung_kohorte.n_lieferungen))::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE (v_lieferung_kohorte.buch = 'verlust'::text)
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), koeff AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.eingang_kg,
            b.stichtag,
            LEAST(GREATEST(COALESCE(kv.mittel, (0)::numeric), (0)::numeric), 0.05) AS r,
            (kv.mittel IS NOT NULL) AS r_bekannt,
            kv.n AS r_n,
            kv.basis AS r_basis,
            LEAST(GREATEST(COALESCE(ka.mittel, (0)::numeric), (0)::numeric), (1)::numeric) AS a_klein,
            (ka.mittel IS NOT NULL) AS a_klein_bekannt,
            ka.n AS klein_n,
            ka.basis AS klein_basis,
            LEAST(GREATEST(COALESCE(kn.mittel, (0)::numeric), (0)::numeric), (1)::numeric) AS a_gross,
            (kn.mittel IS NOT NULL) AS a_gross_bekannt,
            kn.n AS gross_n,
            kn.basis AS gross_basis,
            LEAST(GREATEST(COALESCE(kf.mittel, (0)::numeric), (0)::numeric), (1)::numeric) AS a_fax,
            (kf.mittel IS NOT NULL) AS a_fax_bekannt,
            kf.n AS fax_n,
            kf.basis AS fax_basis
           FROM ((((v_kaskade_basis b
             LEFT JOIN v_koeff_verdunstung kv ON ((kv.sorte = b.sorte)))
             LEFT JOIN v_koeff_ausschuss ka ON ((ka.sorte = b.sorte)))
             LEFT JOIN v_koeff_nebenkanal kn ON ((kn.sorte = b.sorte)))
             LEFT JOIN v_koeff_fax kf ON ((kf.sorte = b.sorte)))
          WHERE (b.eingang_kg > (0)::numeric)
        ), koeff_norm AS (
         SELECT k_1.charge_nr,
            k_1.sorte,
            k_1.schlag,
            k_1.eingang_kg,
            k_1.stichtag,
            k_1.r,
            k_1.r_bekannt,
            k_1.r_n,
            k_1.r_basis,
            k_1.a_klein,
            k_1.a_klein_bekannt,
            k_1.klein_n,
            k_1.klein_basis,
            k_1.a_gross,
            k_1.a_gross_bekannt,
            k_1.gross_n,
            k_1.gross_basis,
            k_1.a_fax,
            k_1.a_fax_bekannt,
            k_1.fax_n,
            k_1.fax_basis,
            (k_1.a_klein / n.f) AS a_klein_n,
            (k_1.a_gross / n.f) AS a_gross_n
           FROM (koeff k_1
             CROSS JOIN LATERAL ( SELECT GREATEST((COALESCE(k_1.a_klein, (0)::numeric) + COALESCE(k_1.a_gross, (0)::numeric)), (1)::numeric) AS f) n)
        ), roh AS (
         SELECT k_1.charge_nr,
            'ausgelagert'::text AS portion,
            l.kohorte,
            (l.masse_kg)::numeric AS geliefert_kg,
            COALESCE(l.alter_tage, (0)::numeric) AS alter_tage,
            NULL::numeric AS eingang_kohorte_kg,
            l.n_lieferungen
           FROM (koeff_norm k_1
             JOIN lieferungen l ON ((l.charge_nr = k_1.charge_nr)))
        UNION ALL
         SELECT k_1.charge_nr,
            'entsorgt'::text,
            e.kohorte,
            (e.masse_kg)::numeric,
            COALESCE(e.alter_tage, (0)::numeric),
            NULL::numeric,
            e.n_lieferungen
           FROM (koeff_norm k_1
             JOIN entsorgt_lief e ON ((e.charge_nr = k_1.charge_nr)))
        UNION ALL
         SELECT k_1.charge_nr,
            'lager'::text,
            c.eingangsdatum,
            NULL::numeric,
            GREATEST(((k_1.stichtag - c.eingangsdatum))::numeric, (0)::numeric) AS "greatest",
            c.eingang_kg,
            0
           FROM (koeff_norm k_1
             JOIN kohorten c ON ((c.charge_nr = k_1.charge_nr)))
        ), teile AS (
         SELECT k_1.charge_nr,
            k_1.sorte,
            k_1.schlag,
            k_1.eingang_kg,
            k_1.stichtag,
            k_1.r,
            k_1.r_bekannt,
            k_1.r_n,
            k_1.r_basis,
            k_1.a_klein,
            k_1.a_klein_bekannt,
            k_1.klein_n,
            k_1.klein_basis,
            k_1.a_gross,
            k_1.a_gross_bekannt,
            k_1.gross_n,
            k_1.gross_basis,
            k_1.a_fax,
            k_1.a_fax_bekannt,
            k_1.fax_n,
            k_1.fax_basis,
            k_1.a_klein_n,
            k_1.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            (ln(GREATEST(t.alter_tage, (1)::numeric)) - COALESCE(m.x_mittel, (0)::numeric)) AS u,
                CASE
                    WHEN m.brauchbar THEN (m.ln_lambda_korrigiert + (m.k * ln(GREATEST(t.alter_tage, (1)::numeric))))
                    ELSE NULL::numeric
                END AS eta,
            m.brauchbar AS modell_gilt,
            (m.brauchbar AND (t.alter_tage > m.t_max)) AS f_extrapoliert,
                CASE
                    WHEN m.brauchbar THEN m.c_chargen
                    ELSE s.n
                END AS f_n,
            s.anteil_mono AS f_treppe,
            (m.brauchbar OR (( SELECT count(*) AS count
                   FROM kurve) > 0)) AS f_bekannt,
                CASE
                    WHEN m.brauchbar THEN COALESCE(m.sockel, (0)::numeric)
                    ELSE (0)::numeric
                END AS a0,
            m.brauchbar AS a0_bekannt,
                CASE
                    WHEN m.brauchbar THEN COALESCE(m.sockel_var, (0)::numeric)
                    ELSE (0)::numeric
                END AS a0_var
           FROM (((koeff_norm k_1
             JOIN roh t ON ((t.charge_nr = k_1.charge_nr)))
             CROSS JOIN modell m)
             LEFT JOIN LATERAL ( SELECT c.anteil_mono,
                    c.n
                   FROM kurve c
                  WHERE ((c.von)::numeric <= t.alter_tage)
                  ORDER BY c.von DESC
                 LIMIT 1) s ON (true))
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
            t.u,
            t.eta,
            t.modell_gilt,
            t.f_extrapoliert,
            t.f_n,
            t.f_treppe,
            t.f_bekannt,
            t.a0,
            t.a0_bekannt,
            t.a0_var,
                CASE
                    WHEN t.modell_gilt THEN LEAST(GREATEST(((1)::numeric - exp((- exp(LEAST(GREATEST(t.eta, ('-40'::integer)::numeric), (3)::numeric))))), (0)::numeric), (1)::numeric)
                    ELSE LEAST(GREATEST(COALESCE(t.f_treppe, (0)::numeric), (0)::numeric), (1)::numeric)
                END AS f
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
            x.u,
            x.eta,
            x.modell_gilt,
            x.f_extrapoliert,
            x.f_n,
            x.f_treppe,
            x.f_bekannt,
            x.a0,
            x.a0_bekannt,
            x.a0_var,
            x.f,
            GREATEST(((((power(((1)::numeric - x.r), x.alter_tage) * ((1)::numeric - x.a0)) * ((1)::numeric - x.f)) * (((1)::numeric - x.a_klein_n) - x.a_gross_n)) * ((1)::numeric - x.a_fax)), 0.25) AS verkaufsfaehig_anteil,
            -- 0065: Für entsorgte Ware zählt nur die Verdunstung zurück. Sie ist
            -- Faules, das den Betrieb verlassen hat — die Ausbeute-Faktoren
            -- (Sockel, Verderb, Sortierung, Fax) gelten für sie nicht: sie ist
            -- selbst das Ergebnis dieser Ursachen, nicht ihr Ausgangspunkt.
            GREATEST(power(((1)::numeric - x.r), x.alter_tage), 0.25) AS verdunstungs_anteil
           FROM mit_f x
        ), ausgelagert AS (
         -- Ausgelagert und entsorgt teilen dieselbe Form: aus der Masse, die
         -- den Betrieb verlassen hat, wird die Eingangsmasse dahinter
         -- zurückgerechnet. Nur der Anteil unterscheidet sich.
         SELECT a.*,
                CASE WHEN a.portion = 'entsorgt'::text
                     THEN (a.geliefert_kg / a.verdunstungs_anteil)
                     ELSE (a.geliefert_kg / a.verkaufsfaehig_anteil) END AS m0,
                (0)::numeric AS ueberzaehlung_kg
           FROM anteil a
          WHERE (a.portion = ANY (ARRAY['ausgelagert'::text, 'entsorgt'::text]))
        ), lager AS (
         -- Was liegt, ist der Eingang des Tages minus alles, was ihn an diesem
         -- Tag schon verlassen hat — verkauft, in den Nebenkanal, in den Kompost.
         SELECT a.*,
                GREATEST((a.eingang_kohorte_kg - COALESCE(x.m0, (0)::numeric)), (0)::numeric) AS m0,
                GREATEST((COALESCE(x.m0, (0)::numeric) - a.eingang_kohorte_kg), (0)::numeric) AS ueberzaehlung_kg
           FROM (anteil a
             LEFT JOIN ( SELECT ausgelagert.charge_nr,
                    ausgelagert.kohorte,
                    sum(ausgelagert.m0) AS m0
                   FROM ausgelagert
                  GROUP BY ausgelagert.charge_nr, ausgelagert.kohorte) x
               ON (((x.charge_nr = a.charge_nr) AND (x.kohorte = a.kohorte))))
          WHERE (a.portion = 'lager'::text)
        ), alle AS (
         SELECT * FROM ausgelagert
        UNION ALL
         SELECT * FROM lager
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
            t.u,
            t.eta,
            t.modell_gilt,
            t.f_extrapoliert,
            t.f_n,
            t.f_treppe,
            t.f_bekannt,
            t.a0,
            t.a0_bekannt,
            t.a0_var,
            t.f,
            t.verkaufsfaehig_anteil,
            t.m0,
            t.ueberzaehlung_kg,
            (t.m0 * power(((1)::numeric - t.r), t.alter_tage)) AS m1,
            (((- t.m0) * t.alter_tage) * power(((1)::numeric - t.r), GREATEST((t.alter_tage - (1)::numeric), (0)::numeric))) AS d_m1_r,
                CASE
                    WHEN t.modell_gilt THEN (((1)::numeric - t.f) * exp(LEAST(GREATEST(t.eta, ('-40'::integer)::numeric), (3)::numeric)))
                    ELSE (0)::numeric
                END AS d_f_eta
           FROM alle t
          WHERE ((t.m0 > (0)::numeric) OR (t.ueberzaehlung_kg > (0)::numeric))
        )
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    m0,
    m1,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric
         ELSE ((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) END AS m2,
    r,
    f,
    a0,
    a_klein_n,
    a_gross_n,
    a_fax,
    u,
    d_m1_r,
    d_f_eta,
    modell_gilt,
    f_extrapoliert,
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
    a0_bekannt,
    a0_var,
    a_fax_bekannt,
    (m0 - m1) AS verdunstung_kg,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE (m1 * a0) END AS sockel_kg,
    -- 0065: Bei entsorgter Ware ist das Faule beobachtet, nicht gerechnet:
    -- was in den Kompost ging, ist genau die Masse des Lieferscheins, um die
    -- Verdunstung zurückgerechnet. Das Modell rechnet für diese Masse nicht
    -- noch einmal — sie ist aus der liegenden Portion bereits abgezogen.
    CASE WHEN portion = 'entsorgt'::text THEN m1
         ELSE ((m1 * ((1)::numeric - a0)) * f) END AS schimmel_kg,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE (((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * a_klein_n) END AS klein_kg,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE (((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * a_gross_n) END AS nebenkanal_kg,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE ((((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * (((1)::numeric - a_klein_n) - a_gross_n)) * a_fax) END AS fax_kg,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE ((((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * (((1)::numeric - a_klein_n) - a_gross_n)) * ((1)::numeric - a_fax)) END AS verkaufsfaehig_kg,
    kohorte,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE geliefert_kg END AS geliefert_kg,
    ueberzaehlung_kg,
    CASE WHEN portion = 'entsorgt'::text THEN 0 ELSE n_lieferungen END AS n_lieferungen,
    verkaufsfaehig_anteil
   FROM kaskade k
 with no data;


-- =====================================================================
-- Was der Kaskadenneubau mitgenommen hat
-- =====================================================================
-- `drop materialized view mv_kaskade cascade` reisst alles mit, was auf ihr
-- steht — einundzwanzig Sichten und gespeicherte Ergebnisse. Sie stehen hier
-- unverändert wieder, in der Reihenfolge ihrer Abhängigkeiten. Zwei davon
-- sind von Hand geschrieben (v_hochrechnung_basis und die Auffälligkeiten aus
-- 0064) und stehen so, wie sie dort standen; die übrigen sind die Fassung,
-- die die Datenbank vor dieser Migration hatte.
--
-- Das ist derselbe Weg, den 0062 gegangen ist. Er ist lang, aber ehrlich:
-- Wer die Migrationen liest, sieht jede Sicht in ihrer gültigen Fassung, und
-- der Prüfstand vergleicht am Ende Fingerabdruck gegen Fingerabdruck.

create materialized view erg_verlauf as
WITH modell AS MATERIALIZED (
         SELECT v_schimmel_modell.n,
            v_schimmel_modell.c_chargen,
            v_schimmel_modell.t_min,
            v_schimmel_modell.t_max,
            v_schimmel_modell.k,
            v_schimmel_modell.ln_lambda,
            v_schimmel_modell.lambda,
            v_schimmel_modell.x_mittel,
            v_schimmel_modell.sxx,
            v_schimmel_modell.smearing,
            v_schimmel_modell.ln_lambda_korrigiert,
            v_schimmel_modell.sigma2,
            v_schimmel_modell.var_achse,
            v_schimmel_modell.var_k,
            v_schimmel_modell.kov_achse_k,
            v_schimmel_modell.t_faktor,
            v_schimmel_modell.brauchbar,
            v_schimmel_modell.selektions_versatz,
            v_schimmel_modell.sockel,
            v_schimmel_modell.sockel_unten,
            v_schimmel_modell.sockel_oben,
            v_schimmel_modell.sockel_nachweis,
            v_schimmel_modell.sockel_schwelle,
            v_schimmel_modell.sockel_var
           FROM v_schimmel_modell
        ), kurve AS MATERIALIZED (
         SELECT v_schimmel_kurve.von,
            v_schimmel_kurve.anteil_mono
           FROM v_schimmel_kurve
          WHERE v_schimmel_kurve.n > 0
        ), wochen AS MATERIALIZED (
         SELECT x.woche,
            x.bis
           FROM ( SELECT w_1.w::date AS woche,
                    (w_1.w + '6 days'::interval)::date AS bis
                   FROM generate_series(date_trunc('week'::text, COALESCE(( SELECT min(palette.eingangsdatum) AS min
                           FROM palette), heute())::timestamp with time zone)::date::timestamp with time zone, date_trunc('week'::text, stichtag()::timestamp with time zone)::date::timestamp with time zone, '7 days'::interval) w_1(w)
                UNION
                 SELECT date_trunc('week'::text, heute()::timestamp with time zone)::date AS date_trunc,
                    heute() AS heute) x
        ), portionen AS MATERIALIZED (
         SELECT k.charge_nr,
            k.sorte,
            k.portion,
            k.kohorte,
            k.m0,
            k.r,
            k.a0,
            k.modell_gilt,
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
        ), f_je_tag AS MATERIALIZED (
         SELECT gs.t,
                CASE
                    WHEN gs.t <= 0 THEN 0::numeric
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(gs.t::numeric, 1::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 1::numeric)
                    ELSE LEAST(GREATEST(COALESCE(( SELECT c.anteil_mono
                       FROM kurve c
                      WHERE c.von <= gs.t
                      ORDER BY c.von DESC
                     LIMIT 1), 0::numeric), 0::numeric), 1::numeric)
                END AS f
           FROM generate_series(0, GREATEST(COALESCE((( SELECT max(w_1.bis) AS max
                   FROM wochen w_1)) - (( SELECT min(p.kohorte) AS min
                   FROM portionen p)), 0), 0)) gs(t)
             CROSS JOIN modell m
        ), je_woche AS (
         SELECT w_1.woche,
            w_1.bis,
            p.sorte,
            p.m0 * (1::numeric - power(1::numeric - p.r, x.t::numeric)) AS verdunstung_kg,
            p.m0 * power(1::numeric - p.r, x.t::numeric) * p.a0 AS sockel_kg,
            p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0) * f.f AS schimmel_kg,
                CASE
                    WHEN p.liefertag IS NOT NULL AND p.liefertag <= w_1.bis THEN p.fax_kg
                    ELSE 0::numeric
                END AS fax_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0 - (1::numeric - p.a0) * f.f)
                    ELSE 0::numeric
                END AS im_haus_kg
           FROM wochen w_1
             JOIN portionen p ON p.kohorte <= w_1.bis
             CROSS JOIN LATERAL ( SELECT GREATEST(LEAST(w_1.bis, COALESCE(p.liefertag, w_1.bis)) - p.kohorte, 0) AS t) x
             JOIN f_je_tag f ON f.t = x.t
        ), verlust AS (
         SELECT je_woche.woche,
            je_woche.bis,
            je_woche.sorte,
            sum(je_woche.verdunstung_kg) AS verdunstung_kg,
            sum(je_woche.sockel_kg) AS sockel_kg,
            sum(je_woche.schimmel_kg) AS schimmel_kg,
            sum(je_woche.fax_kg) AS fax_kg,
            sum(je_woche.im_haus_kg) AS im_haus_kg
           FROM je_woche
          GROUP BY GROUPING SETS ((je_woche.woche, je_woche.bis, je_woche.sorte), (je_woche.woche, je_woche.bis))
        ), eingang AS (
         SELECT w_1.woche,
            w_1.bis,
            p.sorte,
            sum(p.netto_kg) AS kg
           FROM wochen w_1
             JOIN ( SELECT v_1.eingangsdatum,
                    c.sorte,
                    v_1.netto_kg
                   FROM v_palette v_1
                     JOIN charge c ON c.nr = v_1.charge_nr) p ON p.eingangsdatum <= w_1.bis
          GROUP BY GROUPING SETS ((w_1.woche, w_1.bis, p.sorte), (w_1.woche, w_1.bis))
        ), ausgang AS (
         SELECT w_1.woche,
            w_1.bis,
            l.sorte,
            sum(l.masse_kg) AS kg
           FROM wochen w_1
             JOIN ( SELECT l_1.datum,
                    COALESCE(l_1.sorte, c.sorte) AS sorte,
                    l_1.masse_kg
                   FROM v_lieferung_masse l_1
                     LEFT JOIN charge c ON c.nr = l_1.charge_nr
                  WHERE l_1.masse_kg IS NOT NULL
                UNION ALL
                 SELECT COALESCE(( SELECT NULLIF(einstellung.wert #>> '{}'::text[], ''::text)::date AS "nullif"
                           FROM einstellung
                          WHERE einstellung.schluessel = 'erfassungsbeginn'::text), r.letzter_eingang) AS "coalesce",
                    r.sorte,
                    cv.ausgang_vor_app_kg
                   FROM charge_vorlauf cv
                     JOIN v_charge_rueckgrat r ON r.charge_nr = cv.charge_nr
                  WHERE cv.ausgang_vor_app_kg > 0::numeric) l ON l.datum <= w_1.bis
          GROUP BY GROUPING SETS ((w_1.woche, w_1.bis, l.sorte), (w_1.woche, w_1.bis))
        )
 SELECT w.woche,
    w.bis,
    w.bis > heute() AS prognose,
    s.sorte,
    zahl(COALESCE(e.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS eingang_kum_kg,
    zahl(COALESCE(a.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgang_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_kum_kg,
    zahl(COALESCE(v.schimmel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_kum_kg,
    zahl(COALESCE(v.sockel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS sockel_kum_kg,
    zahl(COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric) + COALESCE(v.schimmel_kg, 0::numeric) + COALESCE(v.sockel_kg, 0::numeric) + COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_kum_kg,
    zahl(COALESCE(v.im_haus_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_kg
   FROM wochen w
     CROSS JOIN ( SELECT DISTINCT verlust.sorte
           FROM verlust) s
     LEFT JOIN verlust v ON v.bis = w.bis AND NOT v.sorte IS DISTINCT FROM s.sorte
     LEFT JOIN eingang e ON e.bis = w.bis AND NOT e.sorte IS DISTINCT FROM s.sorte
     LEFT JOIN ausgang a ON a.bis = w.bis AND NOT a.sorte IS DISTINCT FROM s.sorte
with no data;

create view v_hochrechnung_basis with (security_invoker = true) as
with je_charge as (
  select charge_nr,
         sum(m0) filter (where portion = 'ausgelagert')                       as ausgelagert_kg,
         sum(m0 * alter_tage) filter (where portion = 'ausgelagert')
           / nullif(sum(m0) filter (where portion = 'ausgelagert'), 0)        as alter_ausgelagert,
         sum(m0) filter (where portion = 'lager')                             as lager_kg,
         sum(m0 * alter_tage) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as alter_lager,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager')              as verkaufsfaehig_lager_kg,
         sum(geliefert_kg)                                                    as geliefert_kg,
         sum(ueberzaehlung_kg)                                                as ueberzaehlung_kg,
         sum(n_lieferungen)::int                                              as n_lieferungen,
         min(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_von,
         max(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_bis,
         count(*) filter (where portion = 'lager' and m0 > 0)::int            as n_rest_kohorten,
         sum(m0 * (kohorte - date '2000-01-01')) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as rest_tage_seit_epoche,
         -- 0064: jede Stromsumme nur, wenn ihr Koeffizient gemessen ist.
         -- Das `coalesce` innerhalb der Bedingung trennt zwei Sorten NULL:
         -- „der Koeffizient ist unbekannt" (dann bleibt die ganze Summe NULL)
         -- von „diese Portion gibt es nicht" — eine Charge ohne Lieferung hat
         -- keine Zeile mit portion = 'ausgelagert', und dort ist 0 richtig.
         case when bool_and(r_bekannt)  then coalesce(sum(verdunstung_kg), 0) end as verdunstung_heute_kg,
         case when bool_and(f_bekannt)  then coalesce(sum(schimmel_kg), 0)    end as schimmel_heute_kg,
         case when bool_and(a0_bekannt) then coalesce(sum(sockel_kg), 0)      end as sockel_heute_kg,
         case when bool_and(a_klein_bekannt and a_gross_bekannt)
              then coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'ausgelagert'), 0)
              end                                                             as kanal_ausgelagert_kg,
         case when bool_and(a_fax_bekannt)
              then coalesce(sum(fax_kg) filter (where portion = 'ausgelagert'), 0) end as fax_heute_kg,
         case when bool_and(a_fax_bekannt)
              then coalesce(sum(fax_kg) filter (where portion = 'lager'), 0) end       as fax_erwartet_kg,
         sum(m2) filter (where portion = 'lager')                             as im_haus_heute_kg,
         case when bool_and(a_klein_bekannt and a_gross_bekannt)
              then coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'lager'), 0)
              end                                                             as kanal_im_haus_kg,
         bool_and(r_bekannt and f_bekannt and a0_bekannt and a_fax_bekannt
                  and a_klein_bekannt and a_gross_bekannt)                     as verlust_bekannt,
         bool_and(r_bekannt)                                                   as verdunstung_bekannt,
         bool_and(f_bekannt)                                                   as schimmel_bekannt,
         bool_and(a0_bekannt)                                                  as sockel_nachgewiesen,
         bool_and(a_fax_bekannt)                                               as fax_bekannt,
         bool_and(a_klein_bekannt and a_gross_bekannt)                         as kanal_bekannt,
         max(a0_var)                                                           as a0_var,
         -- 0064: gab es zu dieser Charge überhaupt eine Kaskadenzeile?
         count(*) > 0                                                          as gerechnet,
         count(*) filter (where portion = 'lager') > 0                         as hat_lager
    from mv_kaskade
   group by charge_nr
)
select b.charge_nr, b.schlag, b.sorte,
       b.eingang_kg,
       b.n_paletten,
       b.eingangsdatum_mittel,
       zahl(coalesce(k.ausgelagert_kg, 0), 2, 1e12)::numeric(14,2)             as ausgelagert_kg,
       zahl(k.alter_ausgelagert, 1, 1e5)::numeric(8,1)                         as alter_ausgelagert,
       -- 0064: keine Kaskadenzeile → es liegt noch alles. Zeilen, aber keine
       -- Portion „lager" → es liegt nichts mehr. Bisher hiess beides „alles".
       zahl(case when k.gerechnet is not true then b.eingang_kg
                 else coalesce(k.lager_kg, 0) end, 2, 1e12)::numeric(14,2)     as lager_kg,
       zahl(coalesce(k.alter_lager, (b.stichtag - b.eingangsdatum_mittel)), 1, 1e5)::numeric(8,1)
                                                                              as alter_lager,
       zahl((heute() - x.rest_datum), 1, 1e5)::numeric(8,1)                    as alter_lager_heute,
       b.weg2_anteil,
       b.stichtag,
       b.n_paletten_mit_netto,
       zahl(coalesce(k.ueberzaehlung_kg, 0), 2, 1e12)::numeric(14,2)           as ueberzaehlung_kg,
       b.sortiert_kg, b.gewaschen_kg, b.wartet_kg, b.anteil_gewaschen, b.alter_band, b.am_band_kg,
       x.rest_datum                                                           as eingangsdatum_rest,
       (coalesce(k.n_lieferungen, 0) > 0)                                     as rest_alter_aus_zaehlung,
       b.eingang_von, b.eingang_bis, b.n_eingangstage,
       coalesce(k.rest_von, b.eingang_von)                                    as rest_von,
       coalesce(k.rest_bis, b.eingang_bis)                                    as rest_bis,
       round(case when k.gerechnet is not true then b.eingang_kg else coalesce(k.lager_kg, 0) end
             / nullif(b.eingang_kg / nullif(b.n_paletten, 0), 0))::int        as n_rest_paletten,
       coalesce(k.n_rest_kohorten, b.n_eingangstage)                          as n_rest_kohorten,
       (heute() - coalesce(k.rest_bis, b.eingang_bis))::int                   as alter_lager_von,
       (heute() - coalesce(k.rest_von, b.eingang_von))::int                   as alter_lager_bis,
       zahl(coalesce(k.geliefert_kg, 0), 2, 1e12)::numeric(14,2)              as geliefert_kg,
       zahl(k.verkaufsfaehig_lager_kg, 2, 1e12)::numeric(14,2)                 as verkaufsfaehig_lager_kg,
       coalesce(k.n_lieferungen, 0)                                           as n_lieferungen,
       zahl(k.verdunstung_heute_kg, 2, 1e12)::numeric(14,2)                   as verdunstung_heute_kg,
       zahl(k.schimmel_heute_kg, 2, 1e12)::numeric(14,2)                      as schimmel_heute_kg,
       zahl(k.sockel_heute_kg, 2, 1e12)::numeric(14,2)                        as sockel_heute_kg,
       zahl(k.fax_heute_kg, 2, 1e12)::numeric(14,2)                           as fax_heute_kg,
       -- Der Verlust ist die Summe von vier Strömen. Fehlt einer, ist die
       -- Summe unbekannt — nicht die Summe der übrigen.
       zahl(k.verdunstung_heute_kg + k.schimmel_heute_kg + k.sockel_heute_kg + k.fax_heute_kg,
            2, 1e12)::numeric(14,2)                                           as verlust_heute_kg,
       zahl(k.kanal_ausgelagert_kg, 2, 1e12)::numeric(14,2)                   as kanal_ausgelagert_kg,
       zahl(k.fax_erwartet_kg, 2, 1e12)::numeric(14,2)                        as fax_erwartet_kg,
       zahl(case when k.gerechnet is not true then b.eingang_kg
                 else coalesce(k.im_haus_heute_kg, 0) end, 2, 1e12)::numeric(14,2) as im_haus_heute_kg,
       zahl(k.kanal_im_haus_kg, 2, 1e12)::numeric(14,2)                       as kanal_im_haus_kg,
       coalesce(k.verlust_bekannt, false)                                     as verlust_bekannt,
       coalesce(k.verdunstung_bekannt, false)                                 as verdunstung_bekannt,
       coalesce(k.schimmel_bekannt, false)                                    as schimmel_bekannt,
       coalesce(k.sockel_nachgewiesen, false)                                 as sockel_nachgewiesen,
       coalesce(k.fax_bekannt, false)                                         as fax_bekannt,
       coalesce(k.kanal_bekannt, false)                                       as kanal_bekannt,
       zahl(coalesce(k.lager_kg, 0) * 1.96 * sqrt(greatest(coalesce(k.a0_var, 0), 0)), 2, 1e12)::numeric(14,2)
                                                                              as sockel_oben_kg,
       heute()                                                                as heute
  from v_kaskade_basis b
  left join je_charge k on k.charge_nr = b.charge_nr
  cross join lateral (
    select case when k.rest_tage_seit_epoche is not null
                then date '2000-01-01' + round(k.rest_tage_seit_epoche)::int
                else b.eingangsdatum_mittel end as rest_datum
  ) x
 where b.eingang_kg is not null;

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
    sockel_heute_kg,
    fax_heute_kg,
    verlust_heute_kg,
    kanal_ausgelagert_kg,
    fax_erwartet_kg,
    im_haus_heute_kg,
    kanal_im_haus_kg,
    verlust_bekannt,
    verdunstung_bekannt,
    schimmel_bekannt,
    sockel_nachgewiesen,
    fax_bekannt,
    kanal_bekannt,
    sockel_oben_kg,
    heute
   FROM v_hochrechnung_basis
with no data;

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
    a0,
    a_klein_n,
    a_gross_n,
    a_fax,
    u,
    d_m1_r,
    d_f_eta,
    modell_gilt,
    f_extrapoliert,
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
    a0_bekannt,
    a0_var,
    a_fax_bekannt,
    verdunstung_kg,
    sockel_kg,
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

create materialized view mv_hochrechnung as
SELECT k.charge_nr,
    k.sorte,
    k.schlag,
    k.portion,
    k.alter_tage,
    k.eingang_kg,
    zahl(c.m0)::numeric(14,2) AS portion_kg,
    k.f_extrapoliert,
    k.u,
    s.strom,
    s.buch,
        CASE
            WHEN s.bekannt THEN zahl(s.kg)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
        CASE
            WHEN s.bekannt THEN zahl(s.koeffizient, 6, '100000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,6) AS koeffizient,
    s.koeff_n,
    s.koeff_basis,
    s.formel,
    s.d_r,
    s.d_f * k.d_f_eta AS d_eta,
    s.d_a,
    s.d_a0,
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
            LEAST(GREATEST(k.a0, 0::numeric), 1::numeric) AS a0,
            LEAST(GREATEST(k.a_klein_n, 0::numeric), 1::numeric) AS a_klein_n,
            LEAST(GREATEST(k.a_gross_n, 0::numeric), 1::numeric) AS a_gross_n,
            LEAST(GREATEST(k.a_fax, 0::numeric), 1::numeric) AS a_fax) c
     CROSS JOIN LATERAL ( VALUES ('Verdunstung'::text,'verlust'::text,c.m0 - c.m1,c.m0,c.r,k.r_n,k.r_basis,'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'::text,- k.d_m1_r,0::numeric,0::numeric,0::numeric,NULL::text,k.r_bekannt), ('Nicht lagerbedingt'::text,'feld'::text,c.m1 * c.a0,c.m1,c.a0,k.f_n,'Grundaussortierung a₀ aus dem Verderbsmodell: was bei Lagerdauer null schon im Palox läge'::text,'Masse nach Verdunstung × a₀ — Erde, Hagelnarben, Schnittfehler; kein Lagerverlust'::text,k.d_m1_r * c.a0,0::numeric,0::numeric,c.m1,NULL::text,k.a0_bekannt), ('Schimmel/Fäulnis'::text,'verlust'::text,c.m1 * (1::numeric - c.a0) * c.f,c.m1 * (1::numeric - c.a0),c.f,k.f_n,'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen'::text,'Masse nach Verdunstung und Sockel × Schimmelanteil bei dieser Lagerdauer'::text,k.d_m1_r * (1::numeric - c.a0) * c.f,c.m1 * (1::numeric - c.a0),0::numeric,(- c.m1) * c.f,NULL::text,k.f_bekannt), ('Zu klein (Tierfutter)'::text,'marge'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_klein_n,c.m2,c.a_klein_n,k.klein_n,k.klein_basis,'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_klein_n,(- c.m1) * (1::numeric - c.a0) * c.a_klein_n,c.m2,(- c.m1) * (1::numeric - c.f) * c.a_klein_n,'ausschuss'::text,k.a_klein_bekannt), ('Nebenkanal zu gross'::text,'marge'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_gross_n,c.m2,c.a_gross_n,k.gross_n,k.gross_basis,'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_gross_n,(- c.m1) * (1::numeric - c.a0) * c.a_gross_n,c.m2,(- c.m1) * (1::numeric - c.f) * c.a_gross_n,'nebenkanal'::text,k.a_gross_bekannt), ('Faul beim Abpacken (Fax)'::text,'verlust'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),c.a_fax,k.fax_n,k.fax_basis,'Verkaufsfähige Masse × Anteil Faules, das beim Etikettieren aussortiert wird — vom Waschen und Stehen, nicht von der Lagerdauer'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,(- c.m1) * (1::numeric - c.a0) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),(- c.m1) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,'fax'::text,k.a_fax_bekannt), ('Verkaufsfähig'::text,'bilanz'::text,c.verkaufsfaehig_kg,c.m2,NULL::numeric,NULL::integer,NULL::text,'Rest der Kaskade'::text,0::numeric,0::numeric,0::numeric,0::numeric,NULL::text,true)) s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel, d_r, d_f, d_a, d_a0, koeff_art, bekannt)
with no data;

create view v_hochrechnung with (security_invoker = true) as
SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    portion_kg,
    f_extrapoliert,
    u,
    strom,
    buch,
    kg,
    basis_kg,
    koeffizient,
    koeff_n,
    koeff_basis,
    formel,
    d_r,
    d_eta,
    d_a,
    d_a0,
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
            b_1.am_band_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), COALESCE(b_1.alter_band, 0::numeric)) * (1::numeric - sockel_anteil()) * (1::numeric - schimmelanteil(COALESCE(b_1.alter_band, 0::numeric))) * q.anteil_mit_csv AS am_band_modell_kg
           FROM v_kaskade_basis b_1
             LEFT JOIN csv_anteil q ON q.charge_nr = b_1.charge_nr
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b_1.sorte
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
WITH modell AS MATERIALIZED (
         SELECT v_schimmel_modell.n,
            v_schimmel_modell.c_chargen,
            v_schimmel_modell.t_min,
            v_schimmel_modell.t_max,
            v_schimmel_modell.k,
            v_schimmel_modell.ln_lambda,
            v_schimmel_modell.lambda,
            v_schimmel_modell.x_mittel,
            v_schimmel_modell.sxx,
            v_schimmel_modell.smearing,
            v_schimmel_modell.ln_lambda_korrigiert,
            v_schimmel_modell.sigma2,
            v_schimmel_modell.var_achse,
            v_schimmel_modell.var_k,
            v_schimmel_modell.kov_achse_k,
            v_schimmel_modell.t_faktor,
            v_schimmel_modell.brauchbar,
            v_schimmel_modell.selektions_versatz,
            v_schimmel_modell.sockel,
            v_schimmel_modell.sockel_unten,
            v_schimmel_modell.sockel_oben,
            v_schimmel_modell.sockel_nachweis,
            v_schimmel_modell.sockel_schwelle,
            v_schimmel_modell.sockel_var
           FROM v_schimmel_modell
        ), kohorten AS MATERIALIZED (
         SELECT v_kohorte_anteil.charge_nr,
            v_kohorte_anteil.eingangsdatum,
            v_kohorte_anteil.anteil
           FROM v_kohorte_anteil
        ), bestand AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.lager_kg,
            LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            t.m0,
            t.alter_tage
           FROM erg_charge b
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b.sorte
             CROSS JOIN LATERAL ( SELECT b.lager_kg * c.anteil AS m0,
                    GREATEST((heute() - c.eingangsdatum)::numeric, 0::numeric) AS alter_tage
                   FROM kohorten c
                  WHERE c.charge_nr = b.charge_nr
                UNION ALL
                 SELECT b.lager_kg,
                    GREATEST(b.alter_lager_heute, 0::numeric) AS "greatest"
                  WHERE NOT (EXISTS ( SELECT 1
                           FROM kohorten c
                          WHERE c.charge_nr = b.charge_nr))) t
          WHERE b.lager_kg > 0::numeric
        ), mit_f AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.lager_kg,
            b.r,
            b.m0,
            b.alter_tage,
            b.m0 * power(1::numeric - b.r, b.alter_tage) AS masse_jetzt_kg,
                CASE
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(b.alter_tage, 1::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 0.99)
                    ELSE NULL::numeric
                END AS f_jetzt,
                CASE
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(b.alter_tage + 14::numeric, 1::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 0.99)
                    ELSE NULL::numeric
                END AS f_dann,
            m.brauchbar AND b.alter_tage > m.t_max AS hochgerechnet,
            m.brauchbar AS modell_gilt
           FROM bestand b
             CROSS JOIN modell m
        ), je_charge AS (
         SELECT mit_f.charge_nr,
            mit_f.sorte,
            mit_f.schlag,
            mit_f.lager_kg,
            mit_f.modell_gilt,
            bool_or(mit_f.hochgerechnet) AS hochgerechnet,
            sum(mit_f.masse_jetzt_kg) AS masse_jetzt_kg,
            sum(mit_f.masse_jetzt_kg * mit_f.alter_tage) / NULLIF(sum(mit_f.masse_jetzt_kg), 0::numeric) AS alter_tage,
            min(mit_f.alter_tage) AS alter_von,
            max(mit_f.alter_tage) AS alter_bis,
            count(*)::integer AS n_kohorten,
            sum(mit_f.masse_jetzt_kg * (1::numeric - power(1::numeric - mit_f.r, 14::numeric))) AS verdunstung_14_kg,
                CASE
                    WHEN mit_f.modell_gilt THEN sum(mit_f.masse_jetzt_kg * (mit_f.f_dann - mit_f.f_jetzt) / NULLIF(1::numeric - mit_f.f_jetzt, 0::numeric))
                    ELSE NULL::numeric
                END AS schimmel_14_kg
           FROM mit_f
          GROUP BY mit_f.charge_nr, mit_f.sorte, mit_f.schlag, mit_f.lager_kg, mit_f.modell_gilt
        )
 SELECT charge_nr,
    sorte,
    schlag,
    zahl(lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    round(alter_tage)::integer AS alter_tage,
    zahl(masse_jetzt_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS masse_jetzt_kg,
    zahl(verdunstung_14_kg, 1, '100000000000'::numeric)::numeric(12,1) AS verdunstung_14_kg,
    zahl(schimmel_14_kg, 1, '100000000000'::numeric)::numeric(12,1) AS schimmel_14_kg,
    zahl(verdunstung_14_kg + schimmel_14_kg, 1, '100000000000'::numeric)::numeric(12,1) AS prognose_verlust_14_kg,
    hochgerechnet,
    modell_gilt,
    round(alter_von)::integer AS alter_von,
    round(alter_bis)::integer AS alter_bis,
    n_kohorten
   FROM je_charge
  ORDER BY (zahl(verdunstung_14_kg + COALESCE(schimmel_14_kg, 0::numeric), 1, '100000000000'::numeric)::numeric(12,1)) DESC NULLS LAST;

create view v_plausibilitaet_0064_zusatz with (security_invoker = true) as
-- Paletten ohne Nettogewicht: fehlende Gebindeart, fehlende Tara in den
-- Stammdaten oder fehlende Kistenzahl. Der Eingang der Charge rechnet dann mit
-- dem Mittel der übrigen Paletten weiter (v_charge_rueckgrat) — und hat kein
-- Netto mehr, sobald *keine* Palette der Charge eines hat. Beides sah man
-- bisher nur, wenn man auf der Seite Messungen nachsah.
select 'Tara fehlt'::text as art, null::bigint as auftrag_id, p.charge_nr, c.sorte,
       min(p.eingangsdatum)::timestamptz as start_ts,
       format('%s von %s Paletten der Charge haben kein Nettogewicht (%s kg brutto): %s. %s',
              count(*), r.n_paletten, round(sum(p.brutto_kg)),
              case when bool_or(p.gebindeart is null)      then 'die Gebindeart steht nicht auf der Palette'
                   when bool_or(g.art is null)             then 'diese Gebindeart steht nicht in den Stammdaten'
                   when bool_or(g.tara_kg_pro_kiste is null) then 'für die Gebindeart ist kein Kistengewicht hinterlegt'
                   when bool_or(g.tara_kg_palette is null)   then 'für die Gebindeart ist kein Palettengewicht hinterlegt'
                   else 'die Kistenzahl fehlt' end,
              case when r.n_paletten_mit_netto = 0
                   then 'Damit hat die Charge gar keinen Eingang — sie fehlt in der ganzen Bilanz.'
                   else format('Für sie rechnet der Eingang mit dem Mittel der übrigen: %s der %s kg '
                               || 'Eingang sind hochgerechnet, nicht gewogen.',
                               round(r.eingang_netto_kg - r.eingang_netto_gemessen_kg),
                               round(r.eingang_netto_kg)) end)                        as befund,
       case when bool_or(p.gebindeart is null) then 'Gebindeart am Wareneingang nachtragen.'
            when bool_or(g.art is null) or bool_or(g.tara_kg_pro_kiste is null) or bool_or(g.tara_kg_palette is null)
            then 'Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. '
                 || 'Die Zahlen rechnen sich danach von selbst neu.'
            else 'Kistenzahl der Palette im Wareneingang nachtragen.' end               as rat
  from palette p
  left join gebinde g on g.art = p.gebindeart
  join charge c on c.nr = p.charge_nr
  join v_charge_rueckgrat r on r.charge_nr = p.charge_nr
 where p.brutto_kg - p.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette is null
 group by p.charge_nr, c.sorte, r.n_paletten, r.n_paletten_mit_netto,
          r.eingang_netto_kg, r.eingang_netto_gemessen_kg
union all
-- Mehr ausgeliefert als je hereingekommen: das ist kein Verlustphänomen,
-- sondern eine Lücke im Erntejournal oder eine Lieferung auf der falschen
-- Chargennummer. Die Kaskade fängt es ab, damit die Bilanz aufgeht — und
-- genau deshalb fiel es niemandem auf.
select 'Überzählung', null::bigint, h.charge_nr, h.sorte, h.eingangsdatum_mittel::timestamptz,
       format('%s kg mehr ausgeliefert, als für diese Charge je als Eingang erfasst wurde '
              || '(%s kg Eingang, %s kg geliefert) — das sind %s %% des Eingangs',
              round(h.ueberzaehlung_kg), round(h.eingang_kg), round(h.geliefert_kg),
              round(100 * h.ueberzaehlung_kg / nullif(h.eingang_kg, 0))),
       'Fehlt im Erntejournal eine Palette dieser Charge? Oder ist ein Lieferschein auf '
       || 'die falsche Chargennummer gebucht? Beides lässt sich nachtragen; bis dahin ist '
       || 'die Verlustquote dieser Charge zu hoch, weil ihr Eingang zu klein ist.'
  from v_hochrechnung_basis h
 where h.ueberzaehlung_kg > 0
union all
-- Ein Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag: die
-- Massenrechnung fällt still auf die mittlere Tara der Charge zurück. Die
-- Auffälligkeit von 0060 prüft nur Charge und Brutto und schweigt dann.
select 'Zettelgewicht', ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette '
              || 'dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — gerechnet '
              || 'wird deshalb mit der mittleren Tara der Charge, nicht mit ihrer eigenen.',
              count(*), ap.brutto_zettel_kg, to_char(ap.eingangsdatum, 'DD.MM.YYYY')),
       'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  join charge c on c.nr = a.charge_nr
 where ap.brutto_zettel_kg is not null and ap.eingangsdatum is not null
   and a.abgebrochen_ts is null
   and exists (select 1 from palette p
                where p.charge_nr = a.charge_nr and p.brutto_kg = ap.brutto_zettel_kg)
   and not exists (select 1 from v_palette p
                    where p.charge_nr = a.charge_nr and p.brutto_kg = ap.brutto_zettel_kg
                      and p.eingangsdatum = ap.eingangsdatum and p.netto_kg is not null)
 group by ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg, ap.eingangsdatum;

create view v_plausibilitaet_0054_zusatz with (security_invoker = true) as
SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber ein Band mit diesen '::text || 'Grenzen wurde beim Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt'::text, g.anzahl, a.kaliber_von_g, a.kaliber_bis_g) AS befund,
    'Entweder das Band aus der Liste wählen, das dem Etikett entspricht, oder beim '::text || 'nächsten Sortierlauf mit diesem Band die gefüllten Kisten zählen.'::text AS rat
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx = '-2'::integer
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    wp.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '::text || 'die Menge dieser Arbeit damit auch'::text, wp.n_paletten, wp.kisten,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN format('ein Band %s–%s g wurde beim Sortieren noch nie mitgezählt'::text, a.kaliber_von_g, a.kaliber_bis_g)
            ELSE 'für dieses Kaliber wurde beim Sortieren noch nie mitgezählt'::text
        END) AS befund,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht, oder beim '::text || 'nächsten Sortierlauf mit diesem Band die gefüllten Kisten zählen.'::text
            ELSE 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '::text || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.'::text
        END AS rat
   FROM v_auftrag_wasch_paletten wp
     JOIN auftrag a ON a.id = wp.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE wp.kg IS NULL AND wp.kisten > 0
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


-- =====================================================================
-- aus 0066_kein_kilo_aus_einer_luecke.sql
-- =====================================================================

-- =====================================================================
-- 0066 — Kein Kilo aus einer Lücke, auch nicht im Rechenweg
--
-- Nachlese zu 0064. Dieselbe Frage („was heisst hier null?") an drei
-- Stellen, die beim ersten Durchgang stehengeblieben sind — und an zwei
-- davon steht das Vorzeichen andersherum: Dort steht NULL, wo eine Null
-- beobachtet ist.
--
--   1. Der Rechenweg eines Verluststroms zeigt vier Teilbeträge: was an
--      ausgelieferter Ware schon passiert ist, was an der liegenden Ware
--      gerechnet ist, was jenseits der Messungen liegt und was beim
--      Abpacken noch zu erwarten ist. Alle vier entstehen als
--      `sum(...) filter (...)`, und eine Summe über keine Zeile ist in SQL
--      NULL. Gemeint ist aber „null Kilo in dieser Portion": Fax hat
--      nichts an der liegenden Ware, weil dort noch nicht abgepackt wurde;
--      die anderen fünf Ströme haben nichts zu erwarten, weil nur beim
--      Abpacken nachsortiert wird. Beides ist beobachtet, nicht unbekannt.
--      Nachweis: kg = kg_beobachtet + kg_projiziert gilt auf allen 366
--      Zeilen der Demosaison exakt — sobald man NULL als 0 liest. Genau
--      diese Verwechslung hat 0064 in v_hochrechnung_basis behoben
--      (`sum(fax_kg) filter (ausgelagert)`); hier steht sie eine Sicht
--      weiter, in v_verlust_je_gruppe.
--
--      Die Oberfläche hat sich mit `?? 0` beholfen. Damit stand im
--      Rechenweg eines *ungemessenen* Stroms „Ergebnis bis heute: nicht
--      gemessen" und zwei Zeilen darunter „Davon an ausgelieferter Ware:
--      0 kg" — dieselbe Sicht, zwei Antworten. Ab jetzt ist die Regel
--      eindeutig: Ist der Strom gemessen, sind alle vier Teilbeträge
--      Zahlen und ergeben zusammen die Gesamtzahl; ist er es nicht, sind
--      alle vier NULL. Dazwischen gibt es nichts.
--
--   2. Zwei Auslöser haben ein Nettogewicht erfunden. `ausschuss_netto_
--      setzen` und `schimmel_netto_setzen` rechnen brutto − Kisten × Tara
--      und schreiben das Ergebnis in die Pflichtspalte `kg` — mit
--      `coalesce(kisten, 0)` bzw. `coalesce(kisten, 1)` und
--      `coalesce(tara, 0)`. Fehlt die Kistenzahl, oder ist für die
--      Gebindeart keine Tara hinterlegt, wurde damit das **Brutto**
--      als Netto gespeichert und mit `gemessen = true` markiert. Das ist
--      derselbe Fehler wie bei der Palette in 0064, nur schlimmer: Dort
--      wurde er beim Lesen gemacht, hier wird er gespeichert.
--
--      Die Zeile bleibt trotzdem stehen — sie ist eine Beobachtung („eine
--      Kiste Kleines gewogen, 120 kg brutto"), nur eben keine Nettomasse.
--      Sie wird deshalb nicht abgewiesen, sondern auf `gemessen = false`
--      gesetzt: v_ausschuss_beobachtung und v_schimmel_menge lesen ohnehin
--      nur Gemessenes, und die Auffälligkeit unten zeigt die Lücke. Eine
--      Bedingung auf der Tabelle (wie `lieferung_hat_menge` in 0064) wäre
--      hier falsch — bei der Lieferung ist die Zeile ohne Menge
--      unbrauchbar, hier ist sie es nicht.
--
--   3. Die Auffälligkeit „Ausschuss-Tara" hat dasselbe Netto ein zweites
--      Mal nachgerechnet, wieder mit coalesce. Fehlte die Tara, kam als
--      „richtiges" Netto das Bruttogewicht heraus, die Prüfung schlug an
--      und gab die falsche Auskunft: „Die Gebinde-Tara wurde nach dem
--      Wiegen geändert." Sie wurde nicht geändert, sie fehlt. Jetzt
--      rechnet die Prüfung nur nach, wo sich etwas nachrechnen lässt —
--      und damit die Lücke nicht still aus der Prüfung fällt, steht sie
--      als eigene Art daneben: „Ausschuss ohne Tara".
--
--      Eine SQL-Eigenheit führt dabei genau in dieselbe Falle und ist es
--      wert, aufgeschrieben zu werden: **`greatest(null, 0)` ist 0, nicht
--      NULL.** Das blosse Entfernen der coalesce hätte also nichts
--      geholfen — der Vergleich hätte weiter angeschlagen, nur eine
--      Klammer weiter. Das Netto wird deshalb ausdrücklich geprüft,
--      bevor es verglichen wird.
--
-- Keine neue Funktion, keine neue Zahl, keine neue Bedienung. Drei
-- Stellen, an denen eine Lücke und eine gemessene Null verwechselt wurden.
-- =====================================================================

-- ---------- 1. Die vier Teilbeträge eines Stroms ------------------------
-- `sum(...) filter (...)` über keine Zeile ist null Kilo, nicht „unbekannt".
-- Unbekannt ist der Strom als Ganzes — und das steht schon im `case`
-- darüber: ohne `bekannt` bleiben alle vier NULL, mit `bekannt` sind alle
-- vier Zahlen.
create or replace view v_verlust_je_gruppe with (security_invoker = true) as
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
            h.schlag,
            h.portion,
            h.alter_tage,
            h.eingang_kg,
            h.portion_kg,
            h.f_extrapoliert,
            h.u,
            h.strom,
            h.buch,
            h.kg,
            h.basis_kg,
            h.koeffizient,
            h.koeff_n,
            h.koeff_basis,
            h.formel,
            h.d_r,
            h.d_eta,
            h.d_a,
            h.d_a0,
            h.koeff_art,
            h.koeff_bekannt,
            h.kohorte,
            h.strom = 'Faul beim Abpacken (Fax)'::text AND h.portion = 'lager'::text AS erwartet
           FROM mv_hochrechnung h
             JOIN gruppen g_1 ON g_1.charge_nr = h.charge_nr
          WHERE h.buch = ANY (ARRAY['verlust'::text, 'marge'::text, 'feld'::text])
        ), unsicherheit AS MATERIALIZED (
         SELECT v_koeff_unsicherheit.art,
            v_koeff_unsicherheit.sorte,
            v_koeff_unsicherheit.b,
            v_koeff_unsicherheit.varianz_eigen,
            v_koeff_unsicherheit.gewicht_gesamt,
            v_koeff_unsicherheit.varianz_gesamt,
            v_koeff_unsicherheit.df
           FROM v_koeff_unsicherheit
        ), modell AS MATERIALIZED (
         SELECT v_schimmel_modell.n,
            v_schimmel_modell.c_chargen,
            v_schimmel_modell.t_min,
            v_schimmel_modell.t_max,
            v_schimmel_modell.k,
            v_schimmel_modell.ln_lambda,
            v_schimmel_modell.lambda,
            v_schimmel_modell.x_mittel,
            v_schimmel_modell.sxx,
            v_schimmel_modell.smearing,
            v_schimmel_modell.ln_lambda_korrigiert,
            v_schimmel_modell.sigma2,
            v_schimmel_modell.var_achse,
            v_schimmel_modell.var_k,
            v_schimmel_modell.kov_achse_k,
            v_schimmel_modell.t_faktor,
            v_schimmel_modell.brauchbar,
            v_schimmel_modell.selektions_versatz,
            v_schimmel_modell.sockel,
            v_schimmel_modell.sockel_unten,
            v_schimmel_modell.sockel_oben,
            v_schimmel_modell.sockel_nachweis,
            v_schimmel_modell.sockel_schwelle,
            v_schimmel_modell.sockel_var
           FROM v_schimmel_modell
        ), eingang AS MATERIALIZED (
         SELECT g_1.gruppe,
            g_1.schluessel,
            sum(b.eingang_kg) AS eingang_kg,
            count(*)::integer AS n_chargen
           FROM gruppen g_1
             JOIN v_kaskade_basis b ON b.charge_nr = g_1.charge_nr
          GROUP BY g_1.gruppe, g_1.schluessel
        ), je_sorte AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            z.sorte,
            max(z.koeff_art) AS koeff_art,
            sum(z.d_r) AS g_r,
            sum(z.d_a) AS g_a
           FROM zeilen z
          WHERE NOT z.erwartet
          GROUP BY z.gruppe, z.schluessel, z.strom, z.buch, z.sorte
        ), je_strom_modell AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            sum(z.d_eta) AS g_achse,
            sum(z.d_eta * z.u) AS g_steigung,
            sum(z.d_a0) AS g_a0
           FROM zeilen z
          WHERE NOT z.erwartet
          GROUP BY z.gruppe, z.schluessel, z.strom, z.buch
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
         SELECT m.gruppe,
            m.schluessel,
            m.strom,
            m.buch,
            power(m.g_achse, 2::numeric) * COALESCE(sm.var_achse, 0::numeric) + 2::numeric * m.g_achse * m.g_steigung * COALESCE(sm.kov_achse_k, 0::numeric) + power(m.g_steigung, 2::numeric) * COALESCE(sm.var_k, 0::numeric) + power(m.g_a0, 2::numeric) *
                CASE
                    WHEN sm.brauchbar THEN COALESCE(sm.sockel_var, 0::numeric)
                    ELSE 0::numeric
                END AS varianz,
            COALESCE(sm.c_chargen - 1, 1) AS df
           FROM je_strom_modell m
             CROSS JOIN modell sm
        ), summe AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            sum(z.kg) FILTER (WHERE NOT z.erwartet) AS kg,
            bool_and(z.koeff_bekannt) AS bekannt,
            sum(z.kg) FILTER (WHERE z.portion = 'ausgelagert'::text) AS kg_beobachtet,
            sum(z.kg) FILTER (WHERE z.portion = 'lager'::text AND NOT z.erwartet) AS kg_projiziert,
            sum(z.kg) FILTER (WHERE z.f_extrapoliert AND NOT z.erwartet) AS kg_extrapoliert,
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
            WHEN s.bekannt THEN zahl(GREATEST(s.kg - g.t * g.streuung - zu.zuschlag, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_unten,
        CASE
            WHEN s.bekannt THEN zahl(s.kg + g.t * g.streuung + zu.zuschlag)
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
     CROSS JOIN LATERAL ( SELECT COALESCE(sm2.selektions_versatz, 0::numeric) AS versatz
           FROM modell sm2) sel
     CROSS JOIN LATERAL ( SELECT sqrt(GREATEST(COALESCE(vr.varianz, 0::numeric) + COALESCE(va.varianz, 0::numeric) + COALESCE(vf.varianz, 0::numeric), 0::numeric)) AS streuung,
            LEAST(COALESCE(vr.df, 999), COALESCE(va.df, 999), COALESCE(vf.df, 999)) AS df) g0
     CROSS JOIN LATERAL ( SELECT g0.streuung,
            g0.df,
            t_quantil_95(g0.df) AS t) g
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN s.strom = 'Schimmel/Fäulnis'::text THEN COALESCE(s.kg_projiziert, 0::numeric) * abs(exp(sel.versatz) - 1::numeric)
                    ELSE 0::numeric
                END AS zuschlag) zu;

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

-- Die Funktion bleibt für Tests und den SQL-Editor — sie liest nur noch.
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

create view v_marge_buch with (security_invoker = true) as
WITH verkauf AS (
         SELECT sum(erg_ueberfuellung.verschenkt_kg) AS verschenkt_kg,
            sum(
                CASE
                    WHEN erg_ueberfuellung.verschenkt_kg IS NULL THEN NULL::numeric
                    ELSE GREATEST(erg_ueberfuellung.verschenkt_kg - COALESCE(erg_ueberfuellung.verschenkt_fehler_kg, 0::numeric), 0::numeric)
                END) AS verschenkt_unten_kg,
            sum(erg_ueberfuellung.verschenkt_kg + COALESCE(erg_ueberfuellung.verschenkt_fehler_kg, 0::numeric)) AS verschenkt_oben_kg,
            sum(erg_ueberfuellung.kisten_verkauft) FILTER (WHERE erg_ueberfuellung.n_wiegungen > 0) AS kisten_gerechnet,
            sum(erg_ueberfuellung.kisten_verkauft) FILTER (WHERE erg_ueberfuellung.n_wiegungen = 0) AS kisten_ungewogen,
            sum(erg_ueberfuellung.n_wiegungen) AS n_wiegungen,
            sum(erg_ueberfuellung.kisten_gewogen) AS kisten_gewogen,
            sum(erg_ueberfuellung.zuviel_je_kiste * erg_ueberfuellung.kisten_gewogen::numeric) / NULLIF(sum(erg_ueberfuellung.kisten_gewogen) FILTER (WHERE erg_ueberfuellung.zuviel_je_kiste IS NOT NULL), 0::numeric) AS zuviel_je_kiste,
            count(*) FILTER (WHERE erg_ueberfuellung.n_lieferungen > 0)::integer AS n_gruppen_verkauft
           FROM erg_ueberfuellung
          WHERE erg_ueberfuellung.gruppe = 'sorte'::text AND erg_ueberfuellung.kistensystem = 'kiste_ab'::text
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
            sum(erg_charge.sockel_heute_kg) AS sockel_heute_kg,
            sum(erg_charge.fax_heute_kg) AS fax_heute_kg,
            sum(erg_charge.fax_erwartet_kg) AS fax_erwartet_kg,
            sum(erg_charge.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            bool_and(erg_charge.verlust_bekannt) AS bekannt,
            count(*)::integer AS n_chargen,
            max(erg_charge.heute) AS heute
           FROM erg_charge
        ), bereich AS (
         SELECT sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = ANY (ARRAY['verlust'::text, 'feld'::text])) AS verlust_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = ANY (ARRAY['verlust'::text, 'feld'::text])) AS verlust_oben_kg,
            sum(erg_verlust.kg) FILTER (WHERE erg_verlust.buch = ANY (ARRAY['verlust'::text, 'feld'::text])) AS verlust_kg,
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
    zahl(c.sockel_heute_kg)::numeric(14,2) AS sockel_heute_kg,
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
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.kanal_ausgelagert_kg - c.im_haus_heute_kg)::numeric(14,2) AS bilanz_rest_kg,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.kanal_ausgelagert_kg - c.im_haus_heute_kg) / c.eingang_kg
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
            ELSE format((('Bis heute (%s): %s t Eingang = %s t ausgeliefert + %s t Verlust '::text || '(Verdunstung %s t, Faules %s t, Fax %s t) + %s t anderer Kanal '::text) || '+ %s t noch im Haus (davon %s t verkaufsfähig). Die Prognose bis zum '::text) || 'Saisonende steht in der Grafik, nicht in diesen Zahlen.%s'::text, to_char(c.heute::timestamp with time zone, 'DD.MM.YYYY'::text), round(c.eingang_kg / 1000.0, 1), round(c.geliefert_kg / 1000.0, 1), round(c.verlust_heute_kg / 1000.0, 1), round(c.verdunstung_heute_kg / 1000.0, 1), round((c.schimmel_heute_kg + c.sockel_heute_kg) / 1000.0, 1), round(c.fax_heute_kg / 1000.0, 1), round(c.kanal_ausgelagert_kg / 1000.0, 1), round(c.im_haus_heute_kg / 1000.0, 1), round(c.verkaufsfaehig_heute_kg / 1000.0, 1), concat_ws(' '::text, '',
            CASE
                WHEN a.marge_kg > 0::numeric THEN format('An die Tiere und in den Nebenkanal geliefert: %s kg, gerechnet: %s kg.'::text, round(a.marge_kg), round(c.kanal_ausgelagert_kg))
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

-- ---------- 3. Ausschuss-Tara: prüfen, was prüfbar ist ------------------
-- Die Prüfung „stimmt das gespeicherte Netto noch zur heutigen Tara?"
-- braucht drei Angaben. Fehlt eine, gibt es kein Vergleichsnetto — und
-- statt einer erfundenen Zahl steht die Lücke daneben („Ausschuss ohne
-- Tara"). Wie bei der Palette in 0064: leer ist nicht null.
create or replace view v_plausibilitaet with (security_invoker = true) as
SELECT 'Schimmel'::text AS art,
    b.auftrag_id,
    b.charge_nr,
    b.sorte,
    b.start_ts,
    format('%s kg Schimmel auf %s kg Ware — das wären %s %%'::text, round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100::numeric)) AS befund,
    'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text AS rat
   FROM v_schimmel_beobachtung b
  WHERE b.anteil IS NOT NULL AND NOT b.plausibel AND NOT b.ist_fax
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
    'Nichts zu korrigieren. Wird der Palox vor dem Leeren einmal abgelesen, bleibt die Menge bekannt.'::text AS rat
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
            ELSE 'sie ist nicht verwertbar'::text
        END) || ' — sie zählt nicht in die Verdunstungsrate'::text AS befund,
        CASE
            WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'Unter Stammdaten → Gebinde die Tara nachtragen.'::text
            WHEN w.netto_jetzt_kg > (w.netto_damals_kg * 1.01) THEN 'Gebindeart, Kistenzahl und beide Gewichte prüfen — meist stimmt die Tara nicht oder eine Zahl ist verdreht.'::text
            ELSE 'Eingangsdatum und Gewichte der Wägung prüfen.'::text
        END AS rat
   FROM v_verdunstung_messung w
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
  WHERE NOT w.verwendbar AND NOT w.sichtbar_schimmel AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
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
            ELSE format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber wurde beim '::text || 'Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt'::text, g.anzahl, g.kaliber_idx + 1)
        END AS befund,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN 'Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '::text || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'::text
            ELSE 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '::text || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.'::text
        END AS rat
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx <> '-2'::integer
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
        END, m.brutto_kg, GREATEST(round(n.roh), 0::numeric)) AS befund,
    'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '::text || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
     CROSS JOIN LATERAL ( SELECT m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS roh) n
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND n.roh IS NOT NULL AND m.kg::numeric <> GREATEST(round(n.roh), 0::numeric)
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
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette IS NULL
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
    format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette '::text || 'dieser Charge dieses Gewicht — gerechnet wird mit der mittleren Tara der Charge'::text, count(*), ap.brutto_zettel_kg) AS befund,
    'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
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
   FROM v_plausibilitaet_0054_zusatz;

create or replace view v_wiegung_kennzahl as
SELECT w.id,
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
    betriebstag(w.wiege_ts) - w.eingangsdatum AS lagertage,
    n.netto_damals_kg,
    n.netto_jetzt_kg,
    zahl(n.netto_jetzt_kg / NULLIF(w.kisten, 0)::numeric, 3, '10000000'::numeric)::numeric(10,3) AS kg_pro_kiste,
    zahl(n.netto_jetzt_kg / NULLIF(w.kisten * w.kuerbisse_pro_kiste, 0)::numeric, 3, '10000000'::numeric)::numeric(10,3) AS kg_pro_kuerbis,
    zahl(n.netto_damals_kg - n.netto_jetzt_kg, 2, '100000000'::numeric)::numeric(10,2) AS verdunstung_kg
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT zahl(w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, '100000000'::numeric)::numeric(10,2) AS netto_damals_kg,
            zahl(w.brutto_jetzt_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, '100000000'::numeric)::numeric(10,2) AS netto_jetzt_kg) n
  WHERE w.gemessen AND (a.id IS NULL OR a.abgebrochen_ts IS NULL);

-- Die gespeicherten Ergebnisse, die aus einer Liste entstehen
-- ---------------------------------------------------------------------
-- 0061 legt sechsundzwanzig davon in einer Schleife an; ihre Namen stehen
-- nicht im Quelltext, sondern in der Liste. Der Kaskadenneubau hat fünf
-- davon mitgenommen (erg_bilanz, erg_marge, erg_massenbilanz,
-- erg_naechste_charge, erg_plausibilitaet).
--
-- Wiederhergestellt wird hier die **ganze** Liste, mit derselben Angabe für
-- den Verdichter. Das ist Absicht: Sie ist damit dieselbe Anweisung wie in
-- 0061, und setup.sql behält genau eine davon — die letzte. Baute 0065 nur
-- die fünf, stünden in setup.sql zwei Schleifen für dieselben Namen, und
-- welche zuerst liefe, entschiede die Sortierung statt der Absicht.
-- verdichter: baut erg_gewichte erg_kaliber erg_gebinde erg_ausgang
-- verdichter: baut erg_lieferung erg_kohorte erg_punkte erg_modell erg_kurve
-- verdichter: baut erg_selektion erg_koeff_verdunstung erg_koeff_ausschuss
-- verdichter: baut erg_koeff_nebenkanal erg_koeff_ueberfuellung erg_wiegung
-- verdichter: baut erg_fax erg_ausschuss erg_verarbeitung_alter erg_durchsatz
-- verdichter: baut erg_bilanz erg_marge erg_massenbilanz erg_naechste_charge
-- verdichter: baut erg_datenlage erg_plausibilitaet erg_datenqualitaet
do $$
declare
  paar text[];
  paare text[][] := array[
    -- [erg-Name, Quelle]
    ['erg_gewichte',           'v_gewichtsverteilung'],
    ['erg_kaliber',            'v_kaliber_verteilung'],
    ['erg_gebinde',            'v_koeff_gebinde'],
    ['erg_ausgang',            'v_ausgang_kennzahl'],
    ['erg_lieferung',          'v_lieferung_masse'],
    ['erg_kohorte',            'v_charge_kohorte'],
    ['erg_punkte',             'v_schimmel_punkte'],
    ['erg_modell',             'v_schimmel_modell'],
    ['erg_kurve',              'v_schimmel_kurve_anzeige'],
    ['erg_selektion',          'v_selektionsverdacht'],
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
create materialized view erg_punkte as select * from mv_schimmel_punkte with no data;

-- ---------------------------------------------------------------------
-- Beschreibungen, Leserechte und Indizes
-- ---------------------------------------------------------------------
-- Nach einem "drop" ist beides weg: Was eine Ansicht bedeutet und wer sie
-- lesen darf. Beides wird hier wieder gesetzt.
-- ---------------------------------------------------------------------


comment on view v_charge_rueckgrat is
  'Das für jede Charge sicher Bekannte. Grundlage jeder Hochrechnung.';

comment on view v_schimmel_beobachtung is
  'Bekannte kleine Verzerrung: der Palox wird heute gewogen, die faulen '
  'Kürbisse haben also selbst schon Wasser verloren. Der wahre Anteil liegt '
  'geringfügig höher als hier ausgewiesen.';

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

-- Lesen: alle Tabellen und Auswerte-Views.
grant select on all tables in schema public to authenticated;

grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet. Nicht ignorieren: '
  'fast immer ein Tippfehler, der sich korrigieren lässt.';

grant select on v_plausibilitaet to authenticated;

comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, Gewichtsverlust, kg je Kiste '
  'und — falls die Kürbisse je Kiste erfasst wurden — kg je Kürbis.';

grant select on v_wiegung_kennzahl to authenticated;

comment on view v_ausgang_kennzahl is
  'Je fertiger Palette: tatsächliche Kilo je Kiste und der Überschuss über die '
  'Fixpreis-Grenze. Der Überschuss ist kein Verlust — die Ware ist verkauft, '
  'nur nicht bezahlt.';

grant select on v_ausgang_kennzahl to authenticated;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

comment on view v_schimmel_kurve_anzeige is
  'Die Schimmel-Hochrechnung zum Nachschauen: was gemessen wurde, was daraus '
  'verwendet wird und warum.';

grant select on v_schimmel_kurve_anzeige to authenticated;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

create unique index if not exists mv_sortier_lauf_masse_pk on mv_sortier_lauf_masse (lauf_id);
create index if not exists mv_sortier_lauf_masse_charge on mv_sortier_lauf_masse (charge_nr);

create unique index if not exists mv_auftrag_masse_pk on mv_auftrag_masse (auftrag_id);
create index if not exists mv_auftrag_masse_charge on mv_auftrag_masse (charge_nr);
create index if not exists mv_auftrag_masse_station on mv_auftrag_masse (station) where eingang_netto_kg is not null;
grant select on mv_sortier_lauf_masse, mv_auftrag_masse, mv_kaskade,
                mv_kaliber_verteilung to authenticated;

comment on view v_schimmel_modell is
  'Verderbsmodell F(t) = 1 − exp(−λ·S·t^k), S = Duan-Smearing. Der Fehler ist '
  'chargen-robust: Messungen aus derselben Charge sind keine unabhängigen '
  'Beobachtungen. brauchbar = false heisst: zu wenige Chargen oder zu '
  'ähnliche Lagerdauern — es gilt die Treppenfunktion.';

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';
grant select on v_schimmel_modell, v_schimmel_kurve_anzeige, v_kaskade,
               v_hochrechnung, v_verlust_ranking, v_marge_buch,
               v_massenbilanz to authenticated;

comment on view v_koeff_roh_kaliber is
  'Koeffizienten-Rohwerte in einheitlicher Form: Anteil, die Masse, die er '
  'vertritt, und die Charge, aus der er stammt.';

comment on view v_koeff_kaliber_geschaetzt is
  'Massegewichteter Anteil je Sorte, chargen-robust gefehlert und per '
  'empirischem Bayes zum Gesamtwert gezogen. b = 1 heisst: die Sorte trägt '
  'sich selbst, b = 0: es gilt der Gesamtwert.';

grant select on v_koeff_roh_verdunstung, v_koeff_roh_kaliber,
               v_koeff_verdunstung_geschaetzt, v_koeff_kaliber_geschaetzt to authenticated;

comment on view v_koeff_unsicherheit is
  'Je Koeffizient und Sorte: der eigene Fehleranteil, das Gewicht auf dem '
  'gemeinsamen Gesamtwert und dessen Fehler. Getrennt, weil der Gesamtwert '
  'für alle Sorten derselbe ist und seine Fehler sich nicht wegmitteln.';

grant select on v_koeff_unsicherheit to authenticated;

comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall: die '
  'Empfindlichkeit jedes Stroms gegenüber jedem Koeffizienten mal dessen '
  'Fehler, zusammengesetzt nach der tatsächlichen Korrelation. Nicht drei '
  'Szenarien — die standen bei nachgelagerten Strömen in der falschen '
  'Reihenfolge.';

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

grant select on v_kaskade, v_hochrechnung, v_verlust_ranking,
               v_marge_buch, v_massenbilanz to authenticated;

comment on view v_schimmel_punkte is
  'Alle Schimmelbeobachtungen. quelle = lager heisst: die Palette wurde nicht '
  'danach ausgewählt, wie sie aussah — nur diese Punkte sind frei von der '
  'Selektionsverzerrung der Verarbeitungsreihenfolge.';

comment on view v_selektionsverdacht is
  'Vergleicht zufällig gegriffene Lagerkontrollen mit den nach Aussehen '
  'ausgewählten Verarbeitungsmessungen. Ohne Lagerkontrollen ist die '
  'Selektionsverzerrung grundsätzlich nicht prüfbar.';

grant select on v_schimmel_punkte, v_selektionsverdacht to authenticated;

comment on view v_charge_rueckgrat is
  'eingang_netto_kg ist auf alle Paletten der Charge hochgerechnet; '
  'eingang_netto_gemessen_kg ist die Summe der Paletten mit bekannter Tara. '
  'Weichen die beiden ab, fehlt bei n_paletten − n_paletten_mit_netto '
  'Paletten die Gebindeart.';

comment on view v_hochrechnung_basis is
  'ueberzaehlung_kg > 0 heisst: es wurde mehr Masse ausgelagert als je '
  'eingelagert. Der Lagerbestand wird dann auf 0 gekappt — die Zahl hier ist '
  'die einzige Spur, die eine Doppelzählung hinterlässt.';

grant select on v_charge_rueckgrat, v_hochrechnung_basis to authenticated;

comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall: die '
  'Empfindlichkeit jedes Stroms gegenüber jedem Koeffizienten mal dessen '
  'Fehler, zusammengesetzt nach der tatsächlichen Korrelation.';
grant select on v_verlust_ranking, v_marge_buch to authenticated;

comment on view v_auftrag_masse is
  'Masse und Lagerdauer je Arbeit. Wasch-Aufträge auf Weg 1 zählen keine '
  'Paletten — ihre Lagerdauer wird aus dem Wareneingang der sortierten Ware '
  'abgeleitet, sonst fiele Schimmel #2 aus der Auswertung.';

comment on view v_hochrechnung_basis is
  'ausgelagert_kg ist die Masse, die den letzten Verarbeitungsschritt hinter '
  'sich hat — auf Weg 1 also erst nach dem Waschen. wartet_kg steht sortiert '
  'in Kaliber-Kisten und altert weiter. ueberzaehlung_kg > 0 heisst: mehr '
  'ausgelagert als je eingelagert, also Paletten doppelt gezählt.';

grant select on v_auftrag_masse, v_hochrechnung_basis to authenticated;

comment on view v_schimmel_punkte is
  'Alle Schimmelbeobachtungen als *kumulativer* Anteil F(t). Der Palox am '
  'Waschbecken enthält nur den Zuwachs seit dem Sortieren; daraus wird über '
  'die bedingte Überlebensrate der kumulative Wert gebildet, ohne Kilo '
  'umzurechnen. quelle = lager heisst: zufällig gegriffen, also frei von der '
  'Selektionsverzerrung der Verarbeitungsreihenfolge.';

grant select on v_schimmel_punkte to authenticated;

create unique index if not exists mv_sortier_eingang_pk on mv_sortier_eingang (charge_nr);

create index if not exists mv_schimmel_punkte_charge on mv_schimmel_punkte (charge_nr);
create index if not exists mv_schimmel_punkte_quelle on mv_schimmel_punkte (quelle);

comment on materialized view mv_schimmel_punkte is
  'Die gespeicherte Fassung von v_schimmel_punkte. Alles, was rechnet, liest '
  'diese hier; v_schimmel_punkte selbst rechnet neu und wird nur beim '
  'Neuberechnen gebraucht.';

comment on view v_palox_stand is
  'Die Waagenstände der Reihe nach mit der jeweils daraus folgenden Menge. '
  'zwischendurch_geleert = true heisst: der Stand ist gefallen, der Palox '
  'wurde also geleert — dann gilt der neue Stand selbst als Menge.';

grant select on v_palox_stand to authenticated;

comment on view v_lieferung_masse is
  'Lieferungen in Kilo. Kistenangaben werden über das gemessene Kilo je Kiste '
  'umgerechnet; masse_fehler_kg sagt, wie unsicher diese Umrechnung ist.';

grant select on lieferung, ausgang_ziel, v_lieferung_masse to authenticated;

comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand. '
  'luecke_kg ist die einzige Grösse im System, die misst, was das Modell '
  'nicht sieht. Nur aussagekräftig, soweit der Ausgang erfasst ist — '
  'ausgang_deckung sagt, wie weit das ist.';

grant select on v_saisonbilanz to authenticated;

comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. '
  'abweichung_anteil nahe 0 heisst, die Koeffizienten treffen die Realität. '
  'Nur aussagekräftig für Chargen mit CSV — und sie prüft die Koeffizienten, '
  'nicht die Verluste: die CSV wiegt, was ankommt, nicht was verschwand.';

grant select on v_hochrechnung_basis, v_massenbilanz to authenticated;

comment on view v_schimmel_modell is
  'Verderbsmodell F(t) = 1 − exp(−λ·S·t^k), chargen-robust gefehlert. '
  'selektions_versatz ist der gemessene Unterschied zwischen zufällig '
  'gegriffener und nach Aussehen ausgewählter Ware — er lässt sich nicht '
  'herausrechnen, geht aber in den ausgewiesenen Bereich ein.';

grant select on v_schimmel_modell, v_verlust_ranking to authenticated;

comment on view v_palox_stand is
  'Die Waagenstände je Station der Reihe nach, mit der jeweils daraus '
  'folgenden Menge. zwischendurch_geleert: der Stand ist gefallen oder der '
  'Arbeiter hat das Leeren gemeldet — dann gilt der neue Stand als Menge.';
grant select on v_palox_stand to authenticated;

comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Die '
  'Reihenfolge beantwortet, was als nächstes verarbeitet gehört. '
  'schimmel_14_kg ist NULL, solange das Verlaufsmodell nicht trägt — dann '
  'steht die Antwort nur auf der Verdunstung.';

grant select on v_naechste_charge to authenticated;


-- =====================================================================
-- aus 0035_nur_angemeldete.sql
-- =====================================================================

-- =====================================================================
-- 0035 — Funktionen nur für Angemeldete
--
-- WAS HIER SCHIEFLIEF
--
-- Postgres gibt bei jeder neu angelegten Funktion automatisch der Rolle
-- PUBLIC das Ausführungsrecht. Ein `grant execute … to authenticated`
-- nimmt das nicht zurück — es kommt nur obendrauf. Alle Funktionen des
-- Projekts standen damit auch `anon` offen, also jedem, der die Adresse der
-- API kennt und gar nicht angemeldet ist.
--
-- Bei den meisten Funktionen war das folgenlos: Sie laufen mit den Rechten
-- des Aufrufers, und `anon` hat auf keine einzige Tabelle Zugriff. Bei den
-- wenigen "security definer"-Funktionen ist es das nicht — die laufen mit
-- den Rechten des Eigentümers und damit an allen Zeilenregeln vorbei. Beim
-- Bau des Demo-Knopfes fiel es auf: `demo_daten_laden()` liess sich als
-- `anon` aufrufen und hätte 535 erfundene Paletten in die Datenbank eines
-- fremden Betriebs schreiben können.
--
-- Das Tor bleibt, wo es hingehört: Wer etwas darf, entscheiden die
-- Zeilenregeln und die Prüfung auf den Betriebsleiter. Aber ein
-- Nichtangemeldeter soll gar nicht erst anklopfen können.
--
-- Trigger sind davon nicht betroffen: Ob eine Auslöser-Funktion feuert,
-- prüft Postgres beim Anlegen des Auslösers, nicht bei jedem Schreibvorgang.
-- Das ist nachgemessen, nicht vermutet (siehe pruefung.sql).
--
-- Für neue Funktionen gilt ab jetzt: eigener `grant execute … to
-- authenticated`. Vergisst das jemand, schlägt die Prüfung fehl — dort wird
-- verlangt, dass keine Funktion in `public` für PUBLIC ausführbar ist.
-- =====================================================================

revoke execute on all functions in schema public from public;

comment on view v_palox_stand is
  'Die Waagenstände je Station der Reihe nach, mit der daraus abgeleiteten '
  'Menge. Wo der Stand selbst die Menge ist (erste Ablesung, geleert), wird '
  'die Palox-Tara abgezogen — die Waage zeigt brutto.';

comment on view v_schimmel_menge is
  'Faules je Arbeit. Wo der Waagenstand erfasst ist, gilt die daraus '
  'abgeleitete Menge (mit Tara), nicht der damals gespeicherte Kilo-Wert.';

grant select on v_palox_stand, v_schimmel_menge to authenticated;

comment on view v_hochrechnung_basis is
  'ausgelagert_kg ist die Masse, die den letzten Verarbeitungsschritt hinter '
  'sich hat — auf Weg 1 also erst nach dem Waschen. alter_lager läuft ab dem '
  'Eingangsdatum der noch liegenden Paletten (eingangsdatum_rest), nicht ab '
  'dem Mittel der ganzen Charge. ueberzaehlung_kg > 0 heisst: mehr ausgelagert '
  'als je eingelagert, also Paletten doppelt gezählt.';

comment on view v_hochrechnung is
  'Ein Strom je Charge und Portion. kg ist NULL, wenn der Koeffizient dahinter '
  'nie gemessen wurde — koeff_bekannt sagt es. Die Kaskade rechnet dann so, '
  'als würde nichts abgezogen; koeff_basis nennt den Grund.';

comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall. kg ist NULL, '
  'wenn der Koeffizient hinter dem Strom nie gemessen wurde — dann ist der '
  'Strom unbekannt, nicht null.';

comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. '
  'restbestand_kg ist die Masse, die nach Verdunstung und Verderb noch im '
  'Haus liegt — ohne die Aufteilung in zu klein/zu gross, die erst beim '
  'Verarbeiten stattfindet.';

comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand. '
  'Der Restbestand ist die Masse, die nach Verdunstung und Verderb noch im '
  'Haus liegt. luecke_kg misst, was das Modell nicht sieht — nur soweit der '
  'Ausgang erfasst ist (ausgang_deckung).';

comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, '
  'die sie gar nicht verwenden kann, weil ihnen der Nenner fehlt. Nicht '
  'ignorieren: fast immer ist etwas nachzutragen oder ein Tippfehler zu '
  'korrigieren.';

grant select on v_kaskade, v_hochrechnung, v_verlust_ranking, v_marge_buch,
               v_massenbilanz, v_saisonbilanz, v_plausibilitaet,
               v_hochrechnung_basis, v_koeff_ueberfuellung to authenticated;

comment on view v_schimmel_modell is
  'Verderbsmodell F(t) = 1 − exp(−λ·S·t^k), chargen-robust gefehlert, mit '
  'Grundaussortierung a₀ (sockel): Verarbeitungs-Punkte sind a₀ + (1−a₀)·F(t), '
  'Lagerkontrollen F(t). sockel_unten/oben ist der Profil-Bereich; '
  'selektions_versatz der Unterschied zwischen zufällig gegriffener und '
  'nach Aussehen ausgewählter Ware. Gespeichert; auswertung_aktualisieren() '
  'rechnet neu.';

grant select on mv_schimmel_modell, v_schimmel_modell_rechnen to authenticated;
revoke execute on function sockel_anteil() from public;
grant execute on function sockel_anteil() to authenticated;

comment on view v_hochrechnung is
  'Ein Strom je Charge und Portion. Bücher: verlust (Lagerverlust: Verdunstung, '
  'Schimmel), feld (nicht lagerbedingt: Grundaussortierung), marge (anderer '
  'Kanal: zu klein, zu gross), bilanz (verkaufsfähig). kg ist NULL, wenn der '
  'Koeffizient dahinter nie gemessen wurde.';

comment on view v_verlust_ranking is
  'Alle Ströme mit fortgepflanztem 95-%-Bereich. buch = verlust ist der '
  'Lagerverlust (Verdunstung, Schimmel), feld die Grundaussortierung, marge '
  'der andere Kanal (zu klein, zu gross). kg ist NULL, wenn der Koeffizient '
  'nie gemessen wurde.';

comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. '
  'Das Modell zieht Verdunstung, Sockel und Verderb bis dahin ab. '
  'restbestand_kg ist die Masse, die nach Verdunstung und Verderb noch im '
  'Haus liegt.';

comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand. '
  'verlust_modell_kg ist alles, was physisch weg ist (Lagerverlust plus '
  'Grundaussortierung); lagerverlust_kg und feld_kg zerlegen es. Zu klein '
  'und zu gross sind kein Verlust: sie verlassen den Betrieb als Ausgang.';

create unique index if not exists mv_kaliber_pk
  on mv_kaliber_verteilung (charge_nr, klasse, coalesce(kaliber_idx, -1), coalesce(band_von, -1));
grant select on mv_kaliber_verteilung, v_kaliber_verteilung, v_ausgang_kennzahl to authenticated;
grant select on v_auftrag_angabe to authenticated;

comment on view v_schimmel_punkte is
  'Alle Schimmelbeobachtungen als kumulativer Anteil F(t). quelle: '
  'verarbeitung (Palox, nach Aussehen ausgewählt), lager (zufällig gegriffene '
  'Palette), verarbeitung_gemischt (mehrere Chargen im Palox — das Alter ist '
  'geraten, der Punkt bleibt dem Zeitmodell fern).';

comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb über einen anderen Kanal verlässt, plus die '
  'verschenkte Marge aus überfüllten Kisten. Das Kistenmass kommt je Sorte aus '
  'dem Sortierschema (art = kiste), sonst aus der Einstellung soll_kg_pro_kiste.';

grant select on v_marge_buch to authenticated;

comment on view v_koeff_gebinde is
  'Wie viel eine Kaliber-Kiste wiegt, je Sorte und Kaliber — gemessen am '
  'Sortieren aus CSV-Masse und gezählten Kisten. Ohne Messung steht hier keine '
  'Zeile; die Masse am Waschbecken ist dann unbekannt, nicht null.';
grant select on v_koeff_gebinde to authenticated;

comment on view v_auftrag_gebinde_masse is
  'Verarbeitete Menge einer Wascharbeit aus gezählten Kisten mal gemessenem '
  'Kistengewicht. kg ist NULL, solange das Kaliber nie am Sortieren gezählt '
  'wurde — dann fehlt der Nenner weiterhin.';
grant select on v_auftrag_gebinde_masse to authenticated;

comment on view v_auftrag_masse is
  'Masse je Arbeit aus drei Quellen, in dieser Reihenfolge: gewogene Paletten, '
  'eingetippter Durchsatz, gezählte Kisten mal gemessenem Kistengewicht. '
  'masse_quelle sagt, welche es war; fehlt sie ganz, ist eine dort erfasste '
  'Messung ohne Nenner.';

comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, '
  'die sie gar nicht verwenden kann, weil ihnen der Nenner fehlt. Nicht '
  'ignorieren: fast immer ist etwas nachzutragen oder ein Tippfehler zu '
  'korrigieren.';

grant select on v_plausibilitaet to authenticated;

comment on view v_ausgang_kennzahl is
  'Je fertiger Palette: tatsächliche Kilo je Kiste und der Überschuss über das '
  'Sollgewicht. Der Überschuss ist NULL, wenn die Arbeit nach Kaliber lief — '
  'dann gibt es kein Sollgewicht und nichts zu verschenken.';

comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb über einen anderen Kanal verlässt, plus die '
  'verschenkte Marge aus überfüllten Kisten. Die Überfüllung zählt nur die '
  'Masse aus Arbeiten, die als „Kiste ab x kg" liefen.';
grant select on v_marge_buch to authenticated;

comment on view v_koeff_ueberfuellung is
  'Überschuss je Kiste über dem Sollgewicht. Gezählt werden nur Wägungen, aus '
  'denen sich überhaupt ein Überschuss ergibt — Arbeiten nach Kaliber haben '
  'kein Sollgewicht und zählen nicht mit.';
grant select on v_koeff_ueberfuellung to authenticated;

comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand. Der '
  'Ausgang enthält den vor dem Erfassungsbeginn ausgelieferten Vorlauf '
  '(charge_vorlauf), damit die Lücke nicht den späten Start der App misst.';
grant select on v_saisonbilanz to authenticated;

comment on view v_koeff_ueberfuellung is
  'Überschuss je Kiste über dem Sollgewicht, aus den Wägungen fertiger Paletten. '
  'Gezählt werden nur Wägungen, aus denen sich überhaupt ein Überschuss ergibt — '
  'Arbeiten nach Kaliber haben kein Sollgewicht und zählen nicht mit.';

comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, '
  'die sie gar nicht verwenden kann, weil ihnen der Nenner fehlt. Nicht '
  'ignorieren: fast immer ist etwas nachzutragen oder ein Tippfehler zu '
  'korrigieren.';

grant select on v_plausibilitaet to authenticated;
comment on view v_gewichtsverteilung is
  'Kürbisse je 25-g-Stufe aus den Sortier-CSVs, je Charge (mit Sorte und Schlag). '
  'Eine Aussage über den Anbau, nicht über das Lager.';
grant select on v_gewichtsverteilung to authenticated;
comment on view v_verarbeitung_alter is
  'Je Arbeit mit gezählten, datierten Paletten: mittleres Alter der verarbeiteten '
  'Ware gegen das mittlere Alter aller Paletten der Charge an dem Tag. '
  'differenz > 0: älter als der Durchschnitt verarbeitet.';
grant select on v_verarbeitung_alter to authenticated;
comment on view v_durchsatz is
  'Abgeschlossene Arbeiten mit Dauer, Masse und Kilo je Stunde. kg_pro_h ist NULL, '
  'wenn die Masse unbekannt ist oder die Arbeit kürzer als eine Viertelstunde war.';
grant select on v_durchsatz to authenticated;
comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung: datierte Paletten, Palox-Ablesungen je '
  'Arbeit, beantwortete Abschlussfragen, gewogener Ausschuss, Lagerkontrollen, '
  'zugeordnete CSVs, gezählte Kisten. Anteile rechnet die Oberfläche.';
grant select on v_datenqualitaet to authenticated;

comment on view v_ausgang_artikel_vorschlag is
  'Jeder Artikel aus den Importzeilen mit Vorschlag und Bestätigung. Die '
  'vorgeschlagene Sorte stammt aus den Zeilen, die eine eigene Chargennummer '
  'tragen — beobachtet, nicht geraten.';
grant select on v_ausgang_artikel_vorschlag to authenticated;

comment on view v_ausgang_pruef is
  'Kürbis-Positionen, deren übernommene Lieferungen nicht die Masse der Datei '
  'ergeben. Leer ist der Normalfall; jede Zeile hier ist ein Kilo zu viel oder '
  'zu wenig. Eine vergessene Position steht hier mit ihrer vollen Masse.';
grant select on v_ausgang_pruef to authenticated;

comment on view v_ausgang_lage is
  'Je Quelle: wie viel eingelesen ist, bis wann, und wie viele Artikel noch '
  'auf ihre Bestätigung warten.';
grant select on v_ausgang_lage to authenticated;
comment on view v_koeff_gebinde is
  'Wie viel eine Kiste wiegt, je Sorte und Kaliber — gemessen am Sortieren aus '
  'CSV-Masse und gezählten Kisten. Kaliber −1: Kisten nach Sollgewicht, gemessen '
  'an den gewogenen fertigen Paletten. Ohne Messung steht hier keine Zeile.';
comment on view v_auftrag_masse is
  'Masse je Arbeit aus drei Quellen: gewogene Paletten, eingetippter Durchsatz, '
  'gezählte Kisten mal gemessenem Kistengewicht. ist_fax: die Arbeit ist ein Fax '
  '(Abpacken), kein Waschgang — sie zählt nicht als gewaschen.';
comment on view v_schimmel_punkte is
  'Die Punkte des Verderbsmodells: aus der Verarbeitung (Palox) und aus '
  'Lagerkontrollen. Fax-Faules fehlt hier absichtlich — es hängt nicht an der '
  'Lagerdauer (v_fax_beobachtung).';
comment on view v_fax_beobachtung is
  'Je Fax-Arbeit: gemachte Kisten, daraus die Masse, das gewogene Faule und sein '
  'Anteil an dem, was durch die Hände ging (Masse + Faules). Grundlage des Stroms '
  '„Faul beim Abpacken".';
grant select on v_fax_beobachtung to authenticated;
comment on view v_koeff_roh_kaliber is
  'Koeffizienten-Rohwerte in einheitlicher Form: Anteil, die Masse, die er '
  'vertritt, und die Charge, aus der er stammt. ausschuss, nebenkanal, fax.';
comment on view v_koeff_fax is
  'Anteil Faules beim Abpacken (Fax), je Sorte — bezogen auf die Masse, die durch '
  'das Fax ging. NULL, solange keine Fax-Arbeit Faules gewogen hat: unbekannt, nicht 0.';
grant select on v_koeff_fax to authenticated;
comment on view v_charge_kohorte is
  'Je Charge und Eingangstag: wie viele Paletten kamen, wie viele davon wurden '
  'seither mit diesem Zetteldatum gezählt, wie viele liegen also noch. Kein FIFO — '
  'die gezählten Daten sagen, welche Paletten weg sind.';
grant select on v_charge_kohorte to authenticated;
grant select on v_kohorte_anteil to authenticated;
comment on view v_hochrechnung_basis is
  'ausgelagert_kg ist die Masse, die den letzten Verarbeitungsschritt hinter '
  'sich hat — auf Weg 1 also erst nach dem Waschen; Fax zählt nicht als Waschen. '
  'alter_lager ist das massegewichtete Alter der noch liegenden Paletten; '
  'alter_lager_von/bis die Spanne (jüngste bis älteste Kohorte). Die Kaskade '
  'rechnet je Kohorte (v_kohorte_anteil), nicht mit dem Mittel.';
comment on view v_kaskade is
  'Die Massenkaskade je Charge und Portion; der Lagerbestand je Eingangstag '
  '(kohorte). Fax: Faules beim Abpacken, bezogen auf die verkaufsfähige Masse.';
comment on view v_hochrechnung is
  'Ein Strom je Charge, Portion und (im Lager) Eingangstag. kg ist NULL, wenn '
  'der Koeffizient dahinter nie gemessen wurde — koeff_bekannt sagt es. Der '
  'Fax-Strom ist unbekannt, bis die erste Fax-Arbeit Faules gewogen hat.';
comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall. kg ist NULL, '
  'wenn der Koeffizient hinter dem Strom nie gemessen wurde — dann ist der '
  'Strom unbekannt, nicht null.';
comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb über einen anderen Kanal verlässt, plus die '
  'verschenkte Marge aus überfüllten Kisten. Die Aufschlüsselung je Sorte, Charge '
  'und Käufer steht in v_hochrechnung (buch = marge) und v_ueberfuellung_kaeufer.';
comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. '
  'restbestand_kg ist die Masse, die nach Verdunstung und Verderb noch im '
  'Haus liegt — über alle Eingangstage summiert.';
comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand + gewaschene '
  'Ware, die noch auf eine Bestellung wartet (gewaschen_offen_kg, nur wenn das Fax '
  'erfasst wird). Der Verlust enthält das Faule beim Abpacken (Fax).';
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag '
  'gerechnet und je Charge summiert. alter_tage ist das massegewichtete Mittel, '
  'alter_von/bis die Spanne der liegenden Kohorten.';
comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung. Fax-Arbeiten zählen getrennt: Kisten '
  'gezählt, Faules gewogen (auch „nichts Faules" ist eine Messung).';
comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die '
  'sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, '
  'Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette.';

grant select on v_kaskade, v_hochrechnung, v_verlust_ranking, v_marge_buch,
               v_massenbilanz, v_saisonbilanz, v_plausibilitaet, v_datenqualitaet,
               v_hochrechnung_basis, v_naechste_charge, v_koeff_gebinde,
               v_auftrag_masse, v_schimmel_beobachtung, v_schimmel_punkte,
               v_koeff_roh_kaliber, v_ausgang_artikel_vorschlag to authenticated;
comment on view v_auftrag_gebinde_masse is
  'Verarbeitete Menge einer Wascharbeit aus gezählten Kisten mal gemessenem '
  'Kistengewicht. kg ist NULL, solange das Kaliber nie am Sortieren gezählt '
  'wurde — dann fehlt der Nenner weiterhin. Index −2 (eigenes Kaliber) findet '
  'sein Gewicht über die Bandgrenzen in einer Fassung der Sorte (0054).';
grant select on v_plausibilitaet_0054_zusatz to authenticated;
comment on view v_verdunstung_messung is
  'Jede Verdunstungswägung mit Netto damals und jetzt, Lagertagen und Tagesrate. '
  'verwendbar: gemessen, ohne sichtbaren Schimmel, positive Nettos, Wiegedatum nach '
  'dem Eingang, Arbeit nicht abgebrochen — und die Palette höchstens 1 % schwerer '
  'als beim Eingang (0056). Was nicht verwendbar ist, steht in v_plausibilitaet.';
comment on view v_koeff_verdunstung is
  'Verdunstungsrate je Tag und Sorte, gepoolt über die verwendbaren Wägungen und '
  'bei wenigen eigenen Chargen zum Gesamtwert gezogen. Nie negativ (0056); NULL, '
  'solange keine Wägung vorliegt.';
comment on view v_schimmel_beobachtung is
  'Schimmel je Arbeit gegen die Masse, die am Tag der Arbeit noch da war: Eingang '
  'abzüglich Verdunstung mit der gedeckelten Rate (0056). Fax-Faules bleibt '
  'beobachtbar, geht aber nicht in die Verderbskurve.';

grant select on v_verdunstung_messung, v_koeff_verdunstung, v_schimmel_beobachtung,
                v_plausibilitaet to authenticated;
comment on view v_ausschuss_beobachtung is
  'Zu klein und zu gross je Arbeit gegen ihre Basis: am Band die CSV-Masse, von '
  'Hand der Eingang abzüglich Verdunstung (gedeckelte Rate, 0057) und Schimmel.';
grant select on v_ausschuss_beobachtung to authenticated;
comment on view v_hochrechnung is
  'Ein Strom je Charge, Portion und (im Lager) Eingangstag. kg ist NULL, wenn '
  'der Koeffizient dahinter nie gemessen wurde — koeff_bekannt sagt es. Jeder '
  'Koeffizient ist ein Anteil (0 … 1), jede Masse ist nie negativ (0058).';
grant select on v_hochrechnung to authenticated;
comment on view v_saisonbilanz is
  'Die Gegenprobe: Eingang = Verlust + Ausgang + Restbestand + gewaschene Ware, '
  'die noch auf eine Bestellung wartet. Eine Zahl, die nicht darstellbar ist, '
  'steht als NULL da und bricht die Bilanz nicht mehr ab (0058).';
grant select on v_saisonbilanz to authenticated;
comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb über einen anderen Kanal verlässt, plus die '
  'verschenkte Marge aus überfüllten Kisten. Ohne brauchbares Sollgewicht je '
  'Kiste bleibt die Überfüllung unbekannt statt unmöglich gross (0058).';
grant select on v_marge_buch to authenticated;
comment on view v_auftrag_gebinde_masse is 'Verarbeitete Menge einer Wascharbeit aus gezählten Kisten mal gemessenem Kistengewicht. kg ist NULL, solange das Kaliber nie am Sortieren gezählt wurde — dann fehlt der Nenner weiterhin. Index −2 (eigenes Kaliber) findet sein Gewicht über die Bandgrenzen in einer Fassung der Sorte (0054).';
grant select on v_auftrag_gebinde_masse to authenticated;
comment on view v_auftrag_masse is 'Masse je Arbeit aus drei Quellen: gewogene Paletten, eingetippter Durchsatz, gezählte Kisten mal gemessenem Kistengewicht. ist_fax: die Arbeit ist ein Fax (Abpacken), kein Waschgang — sie zählt nicht als gewaschen.';
grant select on v_auftrag_masse to authenticated;
grant select on v_auftrag_palette_masse to authenticated;
comment on view v_ausgang_artikel_vorschlag is 'Jeder Artikel aus den Importzeilen mit Vorschlag und Bestätigung. Die vorgeschlagene Sorte stammt aus den Zeilen, die eine eigene Chargennummer tragen — beobachtet, nicht geraten.';
grant select on v_ausgang_artikel_vorschlag to authenticated;
comment on view v_ausgang_kennzahl is 'Je fertiger Palette: tatsächliche Kilo je Kiste und der Überschuss über das Sollgewicht. Der Überschuss ist NULL, wenn die Arbeit nach Kaliber lief — dann gibt es kein Sollgewicht und nichts zu verschenken.';
grant select on v_ausgang_kennzahl to authenticated;
comment on view v_ausgang_lage is 'Je Quelle: wie viel eingelesen ist, bis wann, und wie viele Artikel noch auf ihre Bestätigung warten.';
grant select on v_ausgang_lage to authenticated;
comment on view v_ausgang_pruef is 'Kürbis-Positionen, deren übernommene Lieferungen nicht die Masse der Datei ergeben. Leer ist der Normalfall; jede Zeile hier ist ein Kilo zu viel oder zu wenig. Eine vergessene Position steht hier mit ihrer vollen Masse.';
grant select on v_ausgang_pruef to authenticated;
comment on view v_ausschuss_beobachtung is 'Zu klein und zu gross je Arbeit gegen ihre Basis: am Band die CSV-Masse, von Hand der Eingang abzüglich Verdunstung (gedeckelte Rate, 0057) und Schimmel.';
grant select on v_ausschuss_beobachtung to authenticated;
comment on view v_charge_kohorte is 'Je Charge und Eingangstag: wie viele Paletten kamen, wie viele davon wurden seither mit diesem Zetteldatum gezählt, wie viele liegen also noch. Kein FIFO — die gezählten Daten sagen, welche Paletten weg sind.';
grant select on v_charge_kohorte to authenticated;
comment on view v_durchsatz is 'Abgeschlossene Arbeiten mit Dauer, Masse und Kilo je Stunde. kg_pro_h ist NULL, wenn die Masse unbekannt ist oder die Arbeit kürzer als eine Viertelstunde war.';
grant select on v_durchsatz to authenticated;
comment on view v_fax_beobachtung is 'Je Fax-Arbeit: gemachte Kisten, daraus die Masse, das gewogene Faule und sein Anteil an dem, was durch die Hände ging (Masse + Faules). Grundlage des Stroms „Faul beim Abpacken".';
grant select on v_fax_beobachtung to authenticated;
comment on view v_hochrechnung is 'Ein Strom je Charge, Portion und (im Lager) Eingangstag. kg ist NULL, wenn der Koeffizient dahinter nie gemessen wurde — koeff_bekannt sagt es. Jeder Koeffizient ist ein Anteil (0 … 1), jede Masse ist nie negativ (0058).';
grant select on v_hochrechnung to authenticated;
comment on view v_koeff_gebinde is 'Wie viel eine Kiste wiegt, je Sorte und Kaliber — gemessen am Sortieren aus CSV-Masse und gezählten Kisten. Kaliber −1: Kisten nach Sollgewicht, gemessen an den gewogenen fertigen Paletten. Ohne Messung steht hier keine Zeile.';
grant select on v_koeff_gebinde to authenticated;
comment on view v_koeff_roh_kaliber is 'Koeffizienten-Rohwerte in einheitlicher Form: Anteil, die Masse, die er vertritt, und die Charge, aus der er stammt. ausschuss, nebenkanal, fax.';
grant select on v_koeff_roh_kaliber to authenticated;
comment on view v_koeff_ueberfuellung is 'Überschuss je Kiste über dem Sollgewicht, aus den Wägungen fertiger Paletten. Gezählt werden nur Wägungen, aus denen sich überhaupt ein Überschuss ergibt — Arbeiten nach Kaliber haben kein Sollgewicht und zählen nicht mit.';
grant select on v_koeff_ueberfuellung to authenticated;
grant select on v_kohorte_anteil to authenticated;
comment on view v_massenbilanz is 'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. restbestand_kg ist die Masse, die nach Verdunstung und Verderb noch im Haus liegt — über alle Eingangstage summiert.';
grant select on v_massenbilanz to authenticated;
comment on view v_naechste_charge is 'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag gerechnet und je Charge summiert. alter_tage ist das massegewichtete Mittel, alter_von/bis die Spanne der liegenden Kohorten.';
grant select on v_naechste_charge to authenticated;
comment on view v_schimmel_beobachtung is 'Schimmel je Arbeit gegen die Masse, die am Tag der Arbeit noch da war: Eingang abzüglich Verdunstung mit der gedeckelten Rate (0056). Fax-Faules bleibt beobachtbar, geht aber nicht in die Verderbskurve.';
grant select on v_schimmel_beobachtung to authenticated;
grant select on v_schimmel_kurve_anzeige to authenticated;
grant select on v_schimmel_modell_rechnen to authenticated;
comment on view v_verarbeitung_alter is 'Je Arbeit mit gezählten, datierten Paletten: mittleres Alter der verarbeiteten Ware gegen das mittlere Alter aller Paletten der Charge an dem Tag. differenz > 0: älter als der Durchschnitt verarbeitet.';
grant select on v_verarbeitung_alter to authenticated;
comment on view v_verdunstung_messung is 'Jede Verdunstungswägung mit Netto damals und jetzt, Lagertagen und Tagesrate. verwendbar: gemessen, ohne sichtbaren Schimmel, positive Nettos, Wiegedatum nach dem Eingang, Arbeit nicht abgebrochen — und die Palette höchstens 1 % schwerer als beim Eingang (0056). Was nicht verwendbar ist, steht in v_plausibilitaet.';
grant select on v_verdunstung_messung to authenticated;
comment on view v_wiegung_kennzahl is 'Je gewogener Palette: Netto damals und jetzt, Gewichtsverlust, kg je Kiste und — falls die Kürbisse je Kiste erfasst wurden — kg je Kürbis.';
grant select on v_wiegung_kennzahl to authenticated;
comment on view v_palox_stand is
  'Die Waagenstände je Palox der Reihe nach (Sortiermaschine, Waschstrasse). '
  'differenz ist die Menge seit der letzten Ablesung; ist der Stand gefallen, '
  'ist sie unbekannt (NULL) — der Palox wurde geleert, ohne dass jemand die '
  'Menge davor kennt (0060).';
comment on view v_schimmel_menge is
  'Faules je Arbeit. Palox-Ablesungen werden als Differenz gerechnet, '
  'Kistenwägungen als Netto. Eine Arbeit, bei der eine Ablesung unbekannt '
  'ist (Stand gefallen), hat hier keine Zeile: ihre Menge ist unbekannt (0060).';
comment on view v_auftrag_palette_masse is
  'Netto je gezählter Palette. Quellen der Reihe nach: gewogen, Brutto vom Zettel '
  '(über den Wareneingang gefunden oder mit der mittleren Tara der Charge), die '
  'bekannte Palette, das Tagesmittel, das Chargenmittel (0060).';
comment on view v_ausgang_kennzahl is
  'Je fertiger Palette: Kilo je Kiste, der Überschuss über das Sollgewicht (nur '
  'Kiste ab x kg — sonst NULL) und bei Stück-Kisten die Erwartung je Kiste aus '
  'dem mittleren Stückgewicht des Kalibers in der Sortier-CSV (0060).';
comment on view v_koeff_palette_netto is
  'Nettomasse einer fertigen Palette je Sorte und Kistensystem (kistensystem NULL: '
  'alle Systeme der Sorte). Daraus die Masse einer Fax-Arbeit: Paletten × Netto (0060).';
grant select on v_koeff_palette_netto to authenticated;
comment on view v_auftrag_masse is
  'Masse je Arbeit aus vier Quellen: gewogene Paletten (oder Zettel), '
  'eingetippter Durchsatz, gezählte Kisten mal gemessenem Kistengewicht, beim '
  'Fax die Palettenzahl mal gemessener Palettenmasse (0060). ist_fax: kein Waschgang.';
comment on view v_charge_kohorte is
  'Je Charge und Eingangstag: wie viele Paletten kamen (eingang_kg), wie viele '
  'davon in der App mit diesem Zetteldatum gezählt wurden (n_verarbeitet — '
  'punktuell, keine Menge). Die Kaskade verteilt den Bestand nach eingang_kg (0060).';
comment on view v_kohorte_anteil is
  'Der Anteil jedes Eingangstags am Eingang der Charge — und damit am Bestand '
  'und an jeder Lieferung: es gibt kein Zuerst-rein-zuerst-raus, und die App '
  'weiss nicht, welche Palette gegangen ist (0060).';
comment on view v_lieferung_kohorte is
  'Gelieferte Masse je Charge, Eingangstag und Buch (verkauf, marge), mit dem '
  'massegewichteten Alter am Liefertag. Grundlage der Rückrechnung in der '
  'Kaskade: was hinter einer Lieferung an Eingangsmasse steckt (0060).';
grant select on v_lieferung_kohorte to authenticated;
comment on view v_kaskade_basis is
  'Eingang je Charge (vollständig, aus dem Erntejournal) und die Gegenproben aus '
  'den erfassten Arbeiten. Was ausgelagert ist und was liegt, steht hier nicht '
  'mehr — das rechnet die Kaskade aus den Lieferungen (v_hochrechnung_basis, 0060).';
grant select on v_kaskade_basis to authenticated;
grant select on mv_kaskade to authenticated;
comment on view v_kaskade is
  'Die Massenkaskade je Charge, Portion und Eingangstag. „ausgelagert" ist die '
  'Eingangsmasse hinter den verkauften Lieferungen (zurückgerechnet über den '
  'verkaufsfähigen Anteil beim Alter am Liefertag); „lager" der Rest des '
  'Eingangstags. Keine Arbeit muss gezählt worden sein (0060).';
grant select on v_kaskade to authenticated;
comment on view v_hochrechnung_basis is
  'Je Charge: Eingang (gemessen), geliefert (gemessen), ausgelagert (die '
  'Eingangsmasse hinter den Lieferungen, zurückgerechnet), im Lager (Eingang '
  'minus ausgelagert), dazu das Alter als Spanne über die Eingangstage. Keine '
  'Zahl hier stammt aus einer gezählten Arbeit (0060). rest_alter_aus_zaehlung '
  'heisst jetzt: der Bestand ist über Lieferungen bestimmt, nicht nur vermutet.';
grant select on v_hochrechnung_basis to authenticated;
grant select on mv_hochrechnung to authenticated;
comment on view v_hochrechnung is
  'Ein Strom je Charge, Portion und Eingangstag. kg ist NULL, wenn der '
  'Koeffizient dahinter nie gemessen wurde — koeff_bekannt sagt es. Jeder '
  'Koeffizient ist ein Anteil (0 … 1), jede Masse nie negativ (0058). Die '
  'Portionen kommen seit 0060 aus den Lieferungen, nicht aus gezählten Arbeiten.';
grant select on v_hochrechnung to authenticated;
comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall. kg ist NULL, '
  'wenn der Koeffizient hinter dem Strom nie gemessen wurde — dann ist der '
  'Strom unbekannt, nicht null.';
grant select on v_verlust_ranking to authenticated;
comment on view v_saisonbilanz is
  'Eingang = Verlust + anderer Kanal + verkauft + verkaufsfähig im Haus. Seit 0060 '
  'geht sie per Konstruktion auf (das Ausgelagerte kommt aus den Lieferungen); '
  'Gegenproben sind Überzählung, gelieferter Kanal und Entsorgung. '
  'gewaschen_offen_kg gibt es nicht mehr: gewaschene, nicht gelieferte Ware liegt.';
grant select on v_saisonbilanz to authenticated;
comment on view v_marge_buch is
  'Kein echter Verlust: Ware, die den Betrieb über einen anderen Kanal verlässt, '
  'und die verschenkte Marge aus überfüllten Kisten — hochgerechnet auf die '
  'verkaufte Masse, nicht auf gezählte Arbeiten (0060).';
grant select on v_marge_buch to authenticated;
comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band — die '
  'eine Gegenprobe, die an gezählten Arbeiten hängt (und nur dort gilt). '
  'ausgelagert_kg und lager_kg stammen aus den Lieferungen (0060).';
grant select on v_massenbilanz to authenticated;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag '
  'gerechnet und je Charge summiert; der Bestand kommt aus den Lieferungen (0060).';
grant select on v_naechste_charge to authenticated;
comment on view v_fax_beobachtung is
  'Je Fax-Arbeit: die Masse (Paletten × gemessene Palettenmasse, oder gezählte '
  'Kisten), das gewogene Faule und sein Anteil an dem, was durch die Hände ging. '
  'Dazu die Tage seit dem Waschen, wenn der Vorarbeiter sie kannte (0060).';
comment on view v_kontrolle_vorschlag is
  'Drei Vorschläge für die Lagerkontrolle: die Chargen mit dem meisten Bestand '
  'und den wenigsten Kontrollen. Wer eine andere Palette greift, trägt ihre '
  'Charge selbst ein (0060).';
grant select on v_kontrolle_vorschlag to authenticated;
comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung. Seit 0060 auch: Zettelgewicht beim '
  'Waschen + Sortieren, Kistensystem nach dem Waschen, Sortierdatum je Kiste, '
  'Fax-Paletten, und Arbeiten mit unbekannter Palox-Menge (Stand gefallen).';   -- 0061: gezählte Kaliber-Paletten sind kein Eingang
comment on view v_auftrag_palette_masse is
  'Netto je gezählter Eingangspalette: gewogen, vom Zettel, aus dem Wareneingang, '
  'oder das Mittel des Eingangstags / der Charge. Beim Waschen gezählte Paletten '
  '(mit Kisten) stehen nicht hier — ihre Masse rechnet v_auftrag_wasch_paletten (0061).';
comment on view v_auftrag_wasch_paletten is
  'Beim Waschen gezählte Paletten: Kisten gesamt, Masse = Kisten × gemessenes '
  'Kistengewicht des Kalibers, Tage im Zwischenlager aus dem Sortierdatum (0061).';
grant select on v_auftrag_wasch_paletten to authenticated;
comment on view v_auftrag_masse is
  'Masse je Arbeit: gewogene Paletten oder Zettel, beim Waschen gezählte Paletten '
  '(Kisten × Kistengewicht, 0061), sonst gezählte Kisten, beim Fax die Palettenzahl '
  'mal gemessener Palettenmasse. ist_fax: kein Waschgang.';
comment on view v_kaskade_basis is
  'Eingang je Charge (vollständig, aus dem Erntejournal) und die Gegenproben aus '
  'den erfassten Arbeiten. stichtag ist seit 0061 heute(): die Ware im Haus altert '
  'bis heute, nicht bis zum Saisonende; saison_ende ist nur der Horizont der Prognose.';
comment on view v_hochrechnung_basis is
  'Je Charge, alles bis heute (0061): Eingang und geliefert (gemessen), '
  'ausgelagert (Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus '
  'ausgelagert, in Eingangskilo), verlust_heute_kg (Verdunstung + Schimmel + Sockel bis '
  'heute + Fax am Abgepackten; fax_erwartet_kg steht daneben), '
  'im_haus_heute_kg (was heute nach Verdunstung und Verderb noch da ist), '
  'verkaufsfaehig_lager_kg (davon in der richtigen Grösse). Keine Prognose.';
grant select on erg_verlauf to authenticated;
comment on materialized view erg_verlauf is
  'Je Woche (und je Sorte; sorte NULL = alles): Eingang und Ausgang kumuliert '
  '(gemessen, Ausgang: alle Lieferungen), der Verlust kumuliert (gerechnet, bis heute), '
  'danach als Prognose bis zum Saisonende (prognose = true). im_haus_kg: je Portion, '
  'was nach Verdunstung und Verderb noch da ist, solange sie nicht ausgeliefert ist (0061).';
comment on view v_verlust_je_gruppe is
  'Jeder Strom mit fortgepflanztem 95-%-Bereich für jede Gruppe: gesamt, je Sorte, '
  'je Schlag, je Charge (0061). kg NULL = Koeffizient nie gemessen. Alles bis heute: '
  'kg_beobachtet ist die ausgelieferte Ware, kg_projiziert die Ware im Haus bis heute; '
  'kg_erwartet (nur Fax) ist, was beim Abpacken der Ware im Haus noch anfallen dürfte — nicht in kg.';
grant select on v_verlust_je_gruppe to authenticated;
grant select on erg_verlust to authenticated;
comment on materialized view erg_verlust is
  'Das Ergebnis für die App: die Ströme je Gruppe, gespeichert (0061). Wird mit '
  'auswertung_schritt(4) erneuert.';
comment on function verlust_ranking(text, text, int) is
  'Alle Ströme mit Bereich, wahlweise je Charge, Sorte oder Schlag — aus erg_verlust '
  'gelesen, nicht gerechnet (0061). Eine Kombination der Filter gibt es nicht mehr.';
revoke all on function verlust_ranking(text, text, int) from public;
grant execute on function verlust_ranking(text, text, int) to authenticated;
comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall; kg NULL heisst: der '
  'Koeffizient wurde nie gemessen. Bis heute, nicht bis zum Saisonende (0061).';
grant select on v_verlust_ranking to authenticated;
comment on view v_verkauf_lieferung is
  'Jede importierte Verkaufslieferung mit dem Kistensystem aus der Datei (Einheit × '
  'Gebindeinhalt): Kiste ab x kg, Stück je Kiste mit Nenngewicht, oder unbekannt. '
  'kisten aus der Chargenzeile (zeile), dem Rest der Position (rest) oder anteilig '
  'an der Position (anteil). Von Hand erfasste Lieferungen stehen nicht hier (0061).';
grant select on v_verkauf_lieferung to authenticated;
comment on view v_ueberfuellung_verkauf is
  'Je Sorte (gruppe sorte) und je Charge (gruppe charge), je Kistensystem: verkaufte '
  'Kisten und Kilo aus der Verkaufsdatei, gewogene Kisten und Kilo je Kiste aus den '
  'fertigen Paletten. verschenkt_kg = Überschuss je gewogener Kiste × verkaufte Kisten, '
  'nur bei „Kiste ab x kg" und nur, wo beides gemessen ist. Stück-Kisten: gemessenes '
  'Stückgewicht neben dem Nenngewicht, keine Marge (0061).';
grant select on v_ueberfuellung_verkauf to authenticated;
create index if not exists erg_ueberfuellung_gruppe on erg_ueberfuellung (gruppe, sorte, charge_nr);
grant select on erg_ueberfuellung to authenticated;
comment on materialized view erg_ueberfuellung is
  'v_ueberfuellung_verkauf, gespeichert für die App (0061). Erneuert mit auswertung_schritt(1).';
grant select on erg_charge to authenticated;
comment on materialized view erg_charge is
  'v_hochrechnung_basis, gespeichert: je Charge Eingang, ausgelagert, im Haus und '
  'Verlust bis heute (0061). Erneuert mit auswertung_schritt(3).';
comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band — die '
  'eine Gegenprobe, die an gezählten Arbeiten hängt (und nur dort gilt). '
  'Die Charge kommt aus erg_charge (0061).';
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag '
  'ab heute() gerechnet und je Charge summiert; der Bestand aus erg_charge (0061).';
comment on view v_kontrolle_vorschlag is
  'Drei Vorschläge für die Lagerkontrolle: die Chargen, bei denen eine Wägung am '
  'meisten Information bringt — Bestand heute × Tage seit der letzten Wägung (0061). '
  'Wer eine andere Palette greift, trägt ihre Charge selbst ein.';
grant select on v_kontrolle_vorschlag to authenticated;
comment on view v_saisonbilanz is
  'Eingang = verkauft + Verlust bis heute + anderer Kanal + noch im Haus (0061). '
  'Alles bis heute(); nichts davon ist Prognose. luecke_kg ist die Überzählung '
  '(Lieferungen, hinter denen kein Eingang steht), sonst null.';
grant select on v_saisonbilanz to authenticated;
comment on view v_marge_buch is
  'Kein echter Verlust: Ware, die den Betrieb über einen anderen Kanal verlässt, '
  'und die verschenkte Marge aus überfüllten Kisten — verkaufte Kisten aus der '
  'Verkaufsdatei mal gewogenem Überschuss je Kiste; ohne Datei oder Wägung NULL (0061).';
grant select on v_marge_buch to authenticated;
grant select on v_plausibilitaet_0054_zusatz to authenticated;
comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung. Seit 0061 zählen beim Waschen die '
  'gezählten Paletten (Kisten mit Sortierdatum) mit; die Lagerkontrolle zählt '
  'als Verdunstungsmessung, ohne Faul-Angabe.';
-- Indizes, wo die App filtert oder sortiert
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
comment on view v_lieferung_kohorte is
  'Gelieferte Masse je Charge, Eingangstag und Buch (verkauf, marge), mit dem '
  'massegewichteten Alter am Liefertag; nur Lieferungen bis heute() (0062). '
  'Grundlage der Rückrechnung in der Kaskade.';
grant select on v_lieferung_kohorte to authenticated;
grant select on mv_kaskade to authenticated;
comment on materialized view mv_kaskade is
  'Die Massenkaskade je Charge, Eingangstag und Portion (ausgelagert / lager). '
  'Ausgelagert ist, was hinter den Lieferungen beider Bücher steckt — verkauft '
  'und in den anderen Kanal (0062); der Rest liegt und altert bis heute().';
grant select on v_kaskade to authenticated;
grant select on mv_hochrechnung to authenticated;
grant select on v_hochrechnung to authenticated;
comment on view v_hochrechnung_basis is
  'Je Charge, alles bis heute (0061): Eingang und geliefert (gemessen), '
  'ausgelagert (Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus '
  'ausgelagert, in Eingangskilo), verlust_heute_kg (Verdunstung + Schimmel + Sockel bis '
  'heute + Fax am Abgepackten; fax_erwartet_kg steht daneben), '
  'im_haus_heute_kg (was heute nach Verdunstung und Verderb noch da ist), '
  'verkaufsfaehig_lager_kg (davon in der richtigen Grösse). Keine Prognose. '
  '0062: kanal_ausgelagert_kg ist der andere Kanal, der schon passiert ist; '
  'kanal_im_haus_kg ist die Erwartung an der liegenden Ware. verlust_bekannt '
  'prüft alle sechs Koeffizienten, je Strom steht ein eigenes Flag daneben; '
  'sockel_oben_kg ist die obere Klammer des Sockels — 0 heisst nicht nachweisbar.';



grant select on v_hochrechnung_basis to authenticated;
grant select on erg_charge to authenticated;
comment on materialized view erg_charge is 'v_hochrechnung_basis, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';
grant select on v_verlust_je_gruppe to authenticated;
grant select on erg_verlust to authenticated;
comment on materialized view erg_verlust is 'v_verlust_je_gruppe, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';
grant select on v_marge_buch to authenticated;
grant select on v_massenbilanz to authenticated;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag '
  'ab heute() gerechnet und je Charge summiert; der Bestand aus erg_charge (0061). '
  'prognose_verlust_14_kg ist Verdunstung + Verderb der nächsten 14 Tage — reine '
  'Prognose, nicht im Verlust bis heute enthalten, und leer, wo das Modell nicht '
  'gilt. Sockel und Fax stecken nicht darin (0062).';



grant select on v_naechste_charge to authenticated;
grant select on v_kontrolle_vorschlag to authenticated;
comment on view v_saisonbilanz is
  'Eingang + Überzählung = ausgeliefert + Verlust bis heute + anderer Kanal am '
  'Ausgelagerten + noch im Haus (0062). Alles bis heute(); nichts davon ist '
  'Prognose. bilanz_rest_kg ist der Rest dieser Gleichung — Erwartungswert null; '
  'die Überzählung (Lieferungen, hinter denen kein Eingang steht) steht als '
  'eigene Spalte. fax_durchsatz_kg ist die am Fax abgepackte Masse, nicht das '
  'Faule dabei (fax_heute_kg).';
grant select on v_saisonbilanz to authenticated;


grant select on v_saisonbilanz to authenticated;
grant select on erg_verlauf to authenticated;
comment on materialized view erg_verlauf is
  'Je Woche (und je Sorte; sorte NULL = alles), mit einer Stützstelle genau auf '
  'heute() (0062): Eingang und Ausgang kumuliert '
  '(gemessen, Ausgang: alle Lieferungen), der Verlust kumuliert (gerechnet, bis heute), '
  'danach als Prognose bis zum Saisonende (prognose = true). im_haus_kg: je Portion, '
  'was nach Verdunstung und Verderb noch da ist, solange sie nicht ausgeliefert ist. '
  'schimmel_kum_kg und sockel_kum_kg stehen getrennt: der Sockel war nie faul (0062).';
grant select on erg_verlauf to authenticated;
comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, die Verdunstung dazwischen '
  '(0062 — vorher verlust_kg), kg je Kiste und je Kürbis.';
grant select on v_wiegung_kennzahl to authenticated;
grant select on v_plausibilitaet_0054_zusatz to authenticated;

-- ---------- 11. Ein Kommentar, der die falsche Auskunft gab --------------
-- erg_ueberfuellung wird in Schritt 1 erneuert, nicht in Schritt 4; im
-- Datenbankkommentar von 0061 stand die falsche Zahl. Wer danach eine
-- Neuberechnung von Hand anstösst, wartet sonst auf einen Schritt, der diese
-- Sicht gar nicht anfasst. Bereits eingespielte Datenbanken bekommen die
-- Berichtigung hier.
comment on materialized view erg_ueberfuellung is
  'v_ueberfuellung_verkauf, gespeichert für die App (0061). Erneuert mit auswertung_schritt(1).';

-- ---------- 12. Ein Name, der mehr verspricht, als er hält ---------------
-- v_verlust_ranking listet *alle* Ströme der Kaskade, auch die, die kein
-- Verlust sind: zu klein und zu gross gehen in einen anderen Kanal (buch =
-- 'marge'), der Sockel ist nicht lagerbedingt (buch = 'feld'). Die Sicht ist
-- ein Werkzeug für die Diagnose und steht auf keinem Bildschirm; wer sie im
-- SQL-Editor öffnet, soll das aber wissen, statt die Summe für den Verlust zu
-- halten. Der Kommentar sagt es jetzt.
comment on view v_verlust_ranking is
  'Alle Ströme der Kaskade für eine Gruppe, absteigend nach Masse — nicht nur '
  'Verlust: buch sagt, was es ist (verlust = echter Verlust, marge = anderer '
  'Kanal, feld = nicht lagerbedingt). Nur für Diagnose und SQL-Editor; die App '
  'liest erg_verlust. Wer über alle Zeilen summiert, summiert Äpfel und Birnen.';


-- =====================================================================
-- aus 0063_jede_sicht_sagt_was_sie_ist.sql
-- =====================================================================

-- =====================================================================
-- 0063 — Jede Sicht sagt, was sie ist
--
-- WIE DAS AUFGEFALLEN IST
--
-- setup.sql war zu gross für den Supabase-SQL-Editor geworden (1,14 MB gegen
-- eine Grenze von 1 MB). Die Datei wird seither verdichtet gebaut: Tabellen
-- und Daten bleiben als Geschichte stehen, die Formeln stehen nur noch in
-- ihrer heutigen Fassung. Damit das nachweislich dieselbe Datenbank ergibt,
-- vergleicht supabase/test/run.sh jetzt zwei Fingerabdrücke — einen aus den
-- Migrationen einzeln, einen aus setup.sql.
--
-- Dieser Vergleich hat etwas gefunden, wonach niemand gesucht hatte: In der
-- laufenden Datenbank haben 26 Ansichten gar keine Beschreibung. Nicht, weil
-- niemand eine geschrieben hätte — v_kaskade, v_marge_buch und v_massenbilanz
-- hatten eine —, sondern weil sie unterwegs verloren ging. Wer eine Ansicht
-- mit "drop ... cascade" wegräumt, reisst die darauf aufbauenden mit; die
-- werden gleich danach neu gebaut, ihre Beschreibung aber nicht. Beim ersten
-- Mal ist das unauffällig, nach neun Umbauten steht die halbe Auswertung
-- unbeschriftet da.
--
-- WARUM DAS ZÄHLT
--
-- Die Beschreibung ist das, was im SQL-Editor, in der Doku und in jedem
-- Werkzeug steht, das die Datenbank ausliest: was diese Zahl bedeutet und
-- worauf sie sich bezieht. Ohne sie ist "kg" nur "kg". Das ist genau die
-- Lücke, gegen die der Begriffs-Prüfstand auf der Oberfläche antritt — hier
-- ist sie eine Ebene tiefer.
--
-- Die Texte hier sind neu geschrieben, für die Fassung, die heute gilt. Keine
-- alte Beschreibung ist zurückgeholt worden: Eine Erklärung von damals kann
-- auf eine Formel von heute nicht mehr passen.
--
-- WAS NOCH DRINSTEHT
--
-- Der Rundumschlag "keine Funktion ist für PUBLIC ausführbar" stammt aus 0035
-- und galt für das, was damals da war. Seither sind Funktionen dazugekommen.
-- In der Reihenfolge der Migrationen ist das nie aufgefallen; in der
-- verdichteten setup.sql entstehen die rechnenden Funktionen ganz am Schluss.
-- Der Verdichter zieht solche Rundumschläge deshalb ans Ende — und damit das
-- nicht von einer Reihenfolge abhängt, steht die Regel hier noch einmal
-- ausdrücklich. Sie nimmt niemandem etwas: Was authenticated oder anon
-- ausführen darf, steht auf diesen Rollen, nicht auf PUBLIC.
-- =====================================================================

revoke execute on all functions in schema public from public;

-- ---------- Rohstoff: was gemessen wurde ---------------------------------

comment on view v_palette is
  'Jede Eingangspalette mit ihrem Nettogewicht: Brutto minus Tara der '
  'Gebindeart mal Kistenzahl. netto_kg ist leer, solange die Gebindeart '
  'fehlt — leer heisst hier "nicht bekannt", nicht "null Kilo".';

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

-- ---------- Die Kaskade und was auf ihr steht ----------------------------

comment on view v_kaskade is
  'Der Massenfluss je Charge, Eingangstag und Portion: Was eingelagert wurde '
  '(eingang_kg) verteilt sich auf Verdunstung, Palox-Sockel, Schimmel, zu '
  'klein, Nebenkanal, Fax und verkaufsfähige Ware. Die Ströme addieren sich '
  'zum Eingang. "Verlust" ist hier nur, was wirklich verloren ist: '
  'verdunstung_kg, sockel_kg, schimmel_kg. klein_kg und nebenkanal_kg sind '
  'kein Verlust, sondern ein anderer Kanal; ueberzaehlung_kg ist kein '
  'Verlust, sondern ein Erfassungsfehler.';

comment on materialized view mv_kaskade is
  'v_kaskade, gespeichert. Inhaltlich gleich; erneuert von '
  'auswertung_schritt(3).';

comment on view v_hochrechnung is
  'Die Kaskade auseinandergelegt: eine Zeile je Charge, Portion und Strom, '
  'mit dem verwendeten Koeffizienten, seiner Herkunft (koeff_art), der Zahl '
  'der Messungen dahinter (koeff_n) und der Formel. koeff_bekannt = false '
  'heisst: geschätzt, nicht gemessen.';

comment on materialized view mv_hochrechnung is
  'v_hochrechnung, gespeichert. Inhaltlich gleich; erneuert von '
  'auswertung_schritt(3).';

comment on view v_verlust_je_gruppe is
  'Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, '
  'Charge). kg_beobachtet ist gemessen, kg_projiziert auf noch nicht '
  'Gemessenes übertragen, kg_extrapoliert über den Messbereich hinaus '
  'gerechnet — drei verschiedene Sicherheiten, darum drei Spalten.';

comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb verlassen hat, ohne verkaufsfähig zu sein — '
  'zu klein, Nebenkanal, Überfüllung. Kein Verlust im Sinne von verdorben, '
  'sondern Masse in einem anderen Kanal. kg_unten und kg_oben spannen den '
  'Bereich auf, gemessen sagt, ob dahinter Messungen oder Schätzungen '
  'stehen.';

comment on view v_massenbilanz is
  'Die Probe aufs Exempel je Charge: Was das Modell am Band erwartet '
  '(modell_am_band_kg) gegen das, was die Sortier-Datei gewogen hat '
  '(csv_gemessen_kg). abweichung_anteil nahe 0 heisst, die Koeffizienten '
  'treffen die Wirklichkeit; systematisch positiv heisst, die Verluste sind '
  'überschätzt. Nur für Chargen mit Sortier-Datei aussagekräftig.';

comment on view v_kontrolle_vorschlag is
  'Welche Charge als Nächstes kontrolliert werden sollte. informationswert '
  'gewichtet, wie viel noch im Haus liegt, wie lange die letzte Wiegung her '
  'ist und wie unsicher die Charge bisher ist — eine Reihenfolge, kein '
  'Befehl.';

-- ---------- Kaliber und Gebinde ------------------------------------------

comment on view v_kaliber_verteilung is
  'Wie sich die sortierte Ware je Charge auf die Kaliberbänder verteilt: '
  'Stückzahl und Masse je Band, dazu die Klassen "zu klein" und '
  '"Nebenkanal". Gewogen aus den Sortierläufen.';

comment on materialized view mv_kaliber_verteilung is
  'v_kaliber_verteilung, gespeichert. Inhaltlich gleich; erneuert von '
  'auswertung_schritt(2).';

comment on materialized view mv_auftrag_masse is
  'Je Arbeit die Eingangsmasse und woher sie kommt (masse_quelle: gewogen, '
  'aus Paletten gerechnet oder geschätzt), dazu Station, Dauer und '
  'Lagertage. Erneuert von auswertung_schritt(1).';

-- ---------- Koeffizienten: wie stark ein Strom ist ------------------------

comment on view v_koeff_roh_verdunstung is
  'Die einzelnen Verdunstungsmessungen, bevor gemittelt wird: je Charge ein '
  'Anteil und sein Gewicht in der Mittelung. Die Rohdaten zu '
  'v_koeff_verdunstung — hier steht, worauf der Koeffizient beruht.';

comment on view v_koeff_verdunstung_geschaetzt is
  'Der Verdunstungs-Koeffizient je Sorte, gepoolt: eigener Mittelwert und '
  'Gesamtmittel, gewichtet nach Streuung (tau2, b). Sorten mit wenigen '
  'Messungen rücken damit näher an den Gesamtwert, statt an einem Ausreisser '
  'zu hängen.';

comment on view v_koeff_ausschuss is
  'Der Ausschuss-Koeffizient je Sorte mit Bereich (unten, oben), Zahl der '
  'Messungen (n) und Bezugsgrösse (basis). Anteil der Eingangsmasse, die '
  'beim Verarbeiten als Ausschuss anfällt.';

comment on view v_koeff_nebenkanal is
  'Der Nebenkanal-Koeffizient je Sorte mit Bereich, Zahl der Messungen und '
  'Bezugsgrösse. Anteil der Masse, der weder verkaufsfähig noch Verlust ist, '
  'sondern in einen anderen Kanal geht.';

-- ---------- Schimmel: Modell und Kurve ------------------------------------

comment on view v_schimmel_kurve is
  'Die gemessenen Schimmelanteile nach Altersklassen: je Klasse Mittelwert, '
  'Streuung und Bereich. anteil_mono ist derselbe Wert monoton gemacht — '
  'Kürbisse werden mit der Zeit nicht wieder gesund.';

comment on view v_schimmel_kurve_anzeige is
  'Die Schimmel-Hochrechnung zum Nachschauen: je Altersklasse, was gemessen '
  'wurde, was daraus verwendet wird und warum. Für den Bildschirm '
  '"Messungen", nicht zum Weiterrechnen.';

comment on view v_schimmel_modell_rechnen is
  'Die Anpassung des Verderbsmodells f(t) = 1 - exp(-lambda*t^k), Schritt '
  'für Schritt: Steigung, Achsenabschnitt, Streuungen, Kovarianz, '
  't-Faktor. brauchbar sagt, ob genug Messungen dahinterstehen.';

comment on materialized view mv_schimmel_modell is
  'Das gerechnete Verderbsmodell, gespeichert — dieselben Grössen wie '
  'v_schimmel_modell_rechnen. sockel ist der Anteil, der schon beim '
  'Einlagern verdorben war und nicht dem Lager anzulasten ist. Erneuert von '
  'auswertung_schritt(2).';

comment on view v_selektionsverdacht is
  'Prüft, ob beim Messen unbewusst ausgewählt wurde: Bleibt bei Chargen, die '
  'gerade verarbeitet werden, systematisch anderes übrig als bei denen im '
  'Lager? unterschied und befund sagen, ob der Verdacht trägt.';

-- ---------- Reste aus Zwischenständen ------------------------------------

comment on view v_plausibilitaet_0054_zusatz is
  'Zusatzprüfungen zu v_plausibilitaet, die seit 0054 dazugekommen sind — '
  'je Auffälligkeit Art, betroffene Arbeit, Befund und Rat. Wird von '
  'v_plausibilitaet mitgelesen; einzeln braucht sie niemand.';
comment on view v_palette is
  'Jede Eingangspalette mit ihrem Nettogewicht: brutto − Kisten × Kistentara − '
  'Palettentara. netto_kg ist NULL, sobald eine der drei Angaben fehlt (0064) — '
  'eine fehlende Kistenzahl heisst nicht „null Kisten". Wie viele Paletten einer '
  'Charge ein Netto haben, steht als n_paletten_mit_netto in v_kaskade_basis.';
comment on view v_verdunstung_messung is
  'Jede Verdunstungswägung mit Netto damals und jetzt, Lagertagen und Tagesrate. '
  'verwendbar: gemessen, ohne sichtbaren Schimmel, positive Nettos, Wiegedatum nach '
  'dem Eingang, Arbeit nicht abgebrochen — und die Palette höchstens 1 % schwerer als '
  'beim Eingang (0056). Ohne Kistenzahl oder ohne hinterlegte Tara gibt es kein Netto '
  'und damit keine Rate (0064). Was nicht verwendbar ist, steht in v_plausibilitaet.';
grant select on v_verdunstung_messung to authenticated;
comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, die Verdunstung dazwischen '
  '(0062 — vorher verlust_kg), kg je Kiste und je Kürbis. Ohne Kistenzahl oder '
  'hinterlegte Tara gibt es kein Netto (0064).';
grant select on v_wiegung_kennzahl to authenticated;
comment on view v_auftrag_palette_masse is
  'Netto je gezählter Eingangspalette: gewogen, vom Zettel, aus dem Wareneingang, '
  'oder das Mittel des Eingangstags / der Charge; masse_quelle sagt, welcher Weg es '
  'war. Beim Waschen gezählte Paletten (mit Kisten) stehen nicht hier — ihre Masse '
  'rechnet v_auftrag_wasch_paletten (0061). Ohne Kistenzahl kein gewogenes Netto (0064).';
comment on view v_hochrechnung_basis is
  'Je Charge, alles bis heute: Eingang und geliefert (gemessen), ausgelagert '
  '(Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus ausgelagert, in '
  'Eingangskilo), verlust_heute_kg (Verdunstung + Schimmel + Sockel + Fax am '
  'Abgepackten), im_haus_heute_kg (Eingangsmasse, die noch liegt, nach Verdunstung '
  'und Verderb). Keine Prognose. 0064: Jede Stromsumme ist NULL, solange ihr '
  'Koeffizient keine Messung hat — leer ist nicht null; die Kennzeichen daneben '
  'sagen, welche. Ohne Messung ist im_haus_heute_kg die Eingangsmasse, die noch '
  'liegt, und damit eine obere Schranke. Fehlt zu einer Charge jede Kaskadenzeile, '
  'liegt noch alles; fehlt nur die Portion „lager", liegt nichts mehr — bisher '
  'hiess beides „alles".';
comment on view v_plausibilitaet_0064_zusatz is
  'Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die '
  'Paletten fehlen im Eingang), eine Charge mit mehr Ausgang als Eingang, und ein '
  'Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag.';
grant select on v_plausibilitaet_0064_zusatz to authenticated;
comment on view v_lieferung_kohorte is
  'Gelieferte Masse je Charge, Eingangstag und Buch (verkauf, marge, verlust), '
  'mit dem massegewichteten Alter am Liefertag; nur Lieferungen bis heute(). '
  'Grundlage der Rückrechnung in der Kaskade. 0065: das dritte Buch ist dabei — '
  'was in den Kompost ging, hat den Betrieb verlassen und gehört aus dem Lager.';
grant select on v_lieferung_kohorte to authenticated;
-- Der eindeutige Index ist Pflicht: ohne ihn kann die Sicht nicht nebenläufig
-- erneuert werden, und das Rechenwerk erneuert sie in Schritt 3.
create unique index if not exists mv_kaskade_pk
  on mv_kaskade (charge_nr, portion, coalesce(kohorte, '1900-01-01'::date));
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);
grant select on mv_kaskade to authenticated;
comment on materialized view mv_kaskade is
  'Die Massenkaskade je Charge, Eingangstag und Portion. Drei Portionen: '
  '„ausgelagert" ist die Eingangsmasse hinter den verkauften und in den '
  'Nebenkanal gegangenen Lieferungen, „entsorgt" die hinter dem Kompost '
  '(0065 — nur um die Verdunstung zurückgerechnet, weil entsorgte Ware selbst '
  'das Faule ist), „lager" der Rest, der noch liegt. Je Portion die Ströme '
  'Verdunstung, Sockel, Schimmel, zu klein, Nebenkanal, Fax und verkaufsfähig; '
  'sie summieren sich zu m0. Ohne Messung ist der Koeffizient 0 und das '
  'Kennzeichen daneben falsch — wer die Ströme summiert, muss es lesen.';
create unique index if not exists erg_verlauf_pk ON public.erg_verlauf USING btree (bis, COALESCE(sorte, ''::text));
create index if not exists erg_verlauf_woche ON public.erg_verlauf USING btree (woche);
comment on materialized view erg_verlauf is
  'Je Woche (und je Sorte; sorte NULL = alles), mit einer Stützstelle genau auf heute() (0062): Eingang und Ausgang kumuliert (gemessen, Ausgang: alle Lieferungen), der Verlust kumuliert (gerechnet, bis heute), danach als Prognose bis zum Saisonende (prognose = true). im_haus_kg: je Portion, was nach Verdunstung und Verderb noch da ist, solange sie nicht ausgeliefert ist. schimmel_kum_kg und sockel_kum_kg stehen getrennt: der Sockel war nie faul (0062).';
comment on view v_hochrechnung_basis is
  'Je Charge, alles bis heute: Eingang und geliefert (gemessen), ausgelagert '
  '(Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus ausgelagert, in '
  'Eingangskilo), verlust_heute_kg (Verdunstung + Schimmel + Sockel + Fax am '
  'Abgepackten), im_haus_heute_kg (Eingangsmasse, die noch liegt, nach Verdunstung '
  'und Verderb). Keine Prognose. 0064: Jede Stromsumme ist NULL, solange ihr '
  'Koeffizient keine Messung hat — leer ist nicht null; die Kennzeichen daneben '
  'sagen, welche. Ohne Messung ist im_haus_heute_kg die Eingangsmasse, die noch '
  'liegt, und damit eine obere Schranke. Fehlt zu einer Charge jede Kaskadenzeile, '
  'liegt noch alles; fehlt nur die Portion „lager", liegt nichts mehr — bisher '
  'hiess beides „alles".';
grant select on v_hochrechnung_basis to authenticated;
create unique index if not exists erg_charge_pk ON public.erg_charge USING btree (charge_nr);
create index if not exists erg_charge_sorte ON public.erg_charge USING btree (sorte);
comment on materialized view erg_charge is
  'v_hochrechnung_basis, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';
grant select on v_kaskade to authenticated;
comment on view v_kaskade is
  'Der Massenfluss je Charge, Eingangstag und Portion: Was eingelagert wurde (eingang_kg) verteilt sich auf Verdunstung, Palox-Sockel, Schimmel, zu klein, Nebenkanal, Fax und verkaufsfähige Ware. Die Ströme addieren sich zum Eingang. "Verlust" ist hier nur, was wirklich verloren ist: verdunstung_kg, sockel_kg, schimmel_kg. klein_kg und nebenkanal_kg sind kein Verlust, sondern ein anderer Kanal; ueberzaehlung_kg ist kein Verlust, sondern ein Erfassungsfehler.';
create index if not exists mv_hochrechnung_charge ON public.mv_hochrechnung USING btree (charge_nr, buch);
comment on materialized view mv_hochrechnung is
  'v_hochrechnung, gespeichert. Inhaltlich gleich; erneuert von auswertung_schritt(3).';
grant select on v_hochrechnung to authenticated;
comment on view v_hochrechnung is
  'Die Kaskade auseinandergelegt: eine Zeile je Charge, Portion und Strom, mit dem verwendeten Koeffizienten, seiner Herkunft (koeff_art), der Zahl der Messungen dahinter (koeff_n) und der Formel. koeff_bekannt = false heisst: geschätzt, nicht gemessen.';
grant select on v_kontrolle_vorschlag to authenticated;
comment on view v_kontrolle_vorschlag is
  'Welche Charge als Nächstes kontrolliert werden sollte. informationswert gewichtet, wie viel noch im Haus liegt, wie lange die letzte Wiegung her ist und wie unsicher die Charge bisher ist — eine Reihenfolge, kein Befehl.';
grant select on v_massenbilanz to authenticated;
comment on view v_massenbilanz is
  'Die Probe aufs Exempel je Charge: Was das Modell am Band erwartet (modell_am_band_kg) gegen das, was die Sortier-Datei gewogen hat (csv_gemessen_kg). abweichung_anteil nahe 0 heisst, die Koeffizienten treffen die Wirklichkeit; systematisch positiv heisst, die Verluste sind überschätzt. Nur für Chargen mit Sortier-Datei aussagekräftig.';
grant select on v_naechste_charge to authenticated;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag ab heute() gerechnet und je Charge summiert; der Bestand aus erg_charge (0061). prognose_verlust_14_kg ist Verdunstung + Verderb der nächsten 14 Tage — reine Prognose, nicht im Verlust bis heute enthalten, und leer, wo das Modell nicht gilt. Sockel und Fax stecken nicht darin (0062).';
comment on view v_plausibilitaet_0064_zusatz is
  'Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die '
  'Paletten fehlen im Eingang), eine Charge mit mehr Ausgang als Eingang, und ein '
  'Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag.';
grant select on v_plausibilitaet_0064_zusatz to authenticated;
grant select on v_plausibilitaet_0054_zusatz to authenticated;
comment on view v_plausibilitaet_0054_zusatz is
  'Zusatzprüfungen zu v_plausibilitaet, die seit 0054 dazugekommen sind — je Auffälligkeit Art, betroffene Arbeit, Befund und Rat. Wird von v_plausibilitaet mitgelesen; einzeln braucht sie niemand.';
grant select on v_plausibilitaet to authenticated;
comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette.';
grant select on v_verlust_je_gruppe to authenticated;
comment on view v_verlust_je_gruppe is
  'Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, Charge). kg_beobachtet ist gemessen, kg_projiziert auf noch nicht Gemessenes übertragen, kg_extrapoliert über den Messbereich hinaus gerechnet — drei verschiedene Sicherheiten, darum drei Spalten.';
create unique index if not exists erg_verlust_pk ON public.erg_verlust USING btree (gruppe, schluessel, strom);
comment on materialized view erg_verlust is
  'v_verlust_je_gruppe, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';
grant select on v_marge_buch to authenticated;
comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb verlassen hat, ohne verkaufsfähig zu sein — zu klein, Nebenkanal, Überfüllung. Kein Verlust im Sinne von verdorben, sondern Masse in einem anderen Kanal. kg_unten und kg_oben spannen den Bereich auf, gemessen sagt, ob dahinter Messungen oder Schätzungen stehen.';
grant select on v_saisonbilanz to authenticated;
comment on view v_saisonbilanz is
  'Eingang + Überzählung = ausgeliefert + Verlust bis heute + anderer Kanal am Ausgelagerten + noch im Haus (0062). Alles bis heute(); nichts davon ist Prognose. bilanz_rest_kg ist der Rest dieser Gleichung — Erwartungswert null; die Überzählung (Lieferungen, hinter denen kein Eingang steht) steht als eigene Spalte. fax_durchsatz_kg ist die am Fax abgepackte Masse, nicht das Faule dabei (fax_heute_kg).';

-- Die Indizes der neu gebauten Ergebnisse. Ein „drop … cascade" nimmt sie
-- mit; ohne diese Zeilen hätte die Datenbank nach den Migrationen neun
-- Indizes weniger als nach setup.sql — und der Abgleich in
-- supabase/test/run.sh sagt es sofort.
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
comment on view v_verlust_je_gruppe is
  'Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, Charge). kg_beobachtet ist gemessen, kg_projiziert auf noch nicht Gemessenes übertragen, kg_extrapoliert über den Messbereich hinaus gerechnet — drei verschiedene Sicherheiten, darum drei Spalten. Ist der Strom gemessen (bekannt), sind alle vier Teilbeträge Zahlen und kg_beobachtet + kg_projiziert = kg; ist er es nicht, sind alle vier NULL (0066).';
grant select on v_plausibilitaet to authenticated;
comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette. 0066: „Ausschuss-Tara" rechnet nur nach, wo Kistenzahl und hinterlegte Tara da sind; fehlt eine, steht die Lücke als „Ausschuss ohne Tara" daneben.';
grant select on v_auftrag_wasch_paletten to authenticated;
comment on view v_auftrag_wasch_paletten is
  'Beim Waschen gezählte Paletten: Kisten gesamt, Masse = Kisten × gemessenes Kistengewicht des Kalibers, Tage im Zwischenlager aus dem Sortierdatum (0061).';
grant select on v_auftrag_masse to authenticated;
comment on view v_auftrag_masse is
  'Masse je Arbeit: gewogene Paletten oder Zettel, beim Waschen gezählte Paletten (Kisten × Kistengewicht, 0061), sonst gezählte Kisten, beim Fax die Palettenzahl mal gemessener Palettenmasse. ist_fax: kein Waschgang.';
grant select on v_verarbeitung_alter to authenticated;
comment on view v_verarbeitung_alter is
  'Je Arbeit mit gezählten, datierten Paletten: mittleres Alter der verarbeiteten Ware gegen das mittlere Alter aller Paletten der Charge an dem Tag. differenz > 0: älter als der Durchschnitt verarbeitet.';
grant select on v_verdunstung_messung to authenticated;
comment on view v_verdunstung_messung is
  'Jede Verdunstungswägung mit Netto damals und jetzt, Lagertagen und Tagesrate. verwendbar: gemessen, ohne sichtbaren Schimmel, positive Nettos, Wiegedatum nach dem Eingang, Arbeit nicht abgebrochen — und die Palette höchstens 1 % schwerer als beim Eingang (0056). Ohne Kistenzahl oder ohne hinterlegte Tara gibt es kein Netto und damit keine Rate (0064). Was nicht verwendbar ist, steht in v_plausibilitaet.';
grant select on v_wiegung_kennzahl to authenticated;
comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, die Verdunstung dazwischen (0062 — vorher verlust_kg), kg je Kiste und je Kürbis. Ohne Kistenzahl oder hinterlegte Tara gibt es kein Netto (0064).';
create index if not exists erg_punkte_charge on erg_punkte (charge_nr);
grant select on erg_punkte to authenticated;
comment on materialized view erg_punkte is
  'v_schimmel_punkte, gespeichert für die App Erneuert mit auswertung_schritt(). '
  'Seit 0068 eine Kopie von mv_schimmel_punkte statt einer zweiten Rechnung — '
  'gemessen 103 ms und 120 kB je Neurechnen.';


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
-- Die Auswertung einmal rechnen — hier, und nur hier
-- =====================================================================
-- Die gespeicherten Auswertungen (mv_…) werden oben ohne Inhalt angelegt.
-- Gerechnet wird einmal, am Ende, mit den heutigen Formeln. Geht das schief,
-- ist die Datenbank trotzdem aktualisiert: die Fertig-Zeile sagt es, und
-- die App rechnet beim nächsten Öffnen erneut.
do $$
begin
  perform auswertung_aktualisieren();
  perform set_config('kuerbis.auswertung', 'Auswertung berechnet.', false);
exception when others then
  perform set_config('kuerbis.auswertung',
    format('Auswertung NICHT berechnet (%s) — die App versucht es beim nächsten Öffnen erneut; unter Messungen → Auffälligkeiten nachsehen.', sqlerrm),
    false);
end $$;

-- =====================================================================
-- Rückmeldung im Ergebnisfenster
-- =====================================================================
-- Was der Nutzer wissen muss, steht in dieser einen Zeile — die Hinweise
-- oben sind stummgeschaltet. Dazu gehört auch, ob pg_cron da ist: Fehlt es,
-- rechnet die App selbst nach, statt dass ein Zeitplan es tut.
do $$
begin
  perform set_config('kuerbis.cron',
    case when exists (select 1 from pg_extension where extname = 'pg_cron')
         then '' else ' Ohne pg_cron rechnet die App selbst nach, wenn etwas veraltet ist.' end,
    false);
end $$;

select format('Fertig. Die Datenbank steht: %s Chargen, %s Sorten, %s Tabellen, %s Auswertungen. %s%s Weiter im README bei Schritt 4.',
              (select count(*) from charge),
              (select count(*) from sorte_kaliber),
              (select count(*) from pg_tables where schemaname = 'public'),
              (select count(*) from pg_views  where schemaname = 'public'),
              coalesce(nullif(current_setting('kuerbis.auswertung', true), ''), 'Auswertung nicht gerechnet.'),
              coalesce(current_setting('kuerbis.cron', true), '')) as ergebnis;
