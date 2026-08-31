-- =====================================================================
-- Kürbis-Verlust-Tracking — das komplette Setup in einer Datei
--
-- ERZEUGT. Nicht von Hand ändern — Quelle ist supabase/migrations/*.sql,
-- zusammengefügt von supabase/setup_bauen.sh.
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
  with k as (select * from sorte_kaliber where sorte = p_sorte),
       band as (
         select (ord - 1)::int as idx
         from k, jsonb_array_elements(k.kaliber_baender) with ordinality as b(grenzen, ord)
         where p_gewicht_g >= (grenzen->>0)::int
           and p_gewicht_g <  (grenzen->>1)::int
         order by ord limit 1
       )
  select case
           when (select count(*) from k) = 0            then 'unklassiert'::kuerbis_klasse
           when p_gewicht_g <  (select verlust_unter from k) then 'verlust_klein'::kuerbis_klasse
           when p_gewicht_g >= (select kanal_ab       from k) then 'nebenkanal'::kuerbis_klasse
           when (select count(*) from band) = 1          then 'kaliber'::kuerbis_klasse
           else 'unklassiert'::kuerbis_klasse
         end,
         (select idx from band);
$$;

comment on function klassiere is
  '< Verlust-Grenze = VERLUST (weggeworfen) · in einem Band = HAUPTKANAL · '
  '>= kanal_ab = NEBENKANAL (kein Verlust, separat auszuweisen).';

-- ---------- Einen Lauf neu klassieren (nach Grenzen-Änderung) -------------
create or replace function lauf_neu_klassieren(p_lauf_id bigint)
returns int language plpgsql as $$
declare v_sorte text; v_n int;
begin
  select c.sorte into v_sorte
    from sortier_lauf l join charge c on c.nr = l.charge_nr
   where l.id = p_lauf_id;

  update sortier_gewicht g
     set klasse = k.klasse, kaliber_idx = k.kaliber_idx
    from klassiere(v_sorte, g.gewicht_g) k
   where g.lauf_id = p_lauf_id;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

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

create or replace function auftrag_manuell_zuordnen(p_lauf_id bigint, p_auftrag_id bigint)
returns void language sql as $$
  update sortier_lauf
     set auftrag_id = p_auftrag_id,
         zuordnung  = case when p_auftrag_id is null then 'offen'::zuordnung_status
                            else 'manuell'::zuordnung_status end
   where id = p_lauf_id;
$$;

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
-- aus 0005_views_basis.sql
-- =====================================================================

-- =====================================================================
-- 0005 — Auswertung, Teil 1: Rückgrat und Messungen
--
-- Aufbau nach Spec §9: Das *Rückgrat* ist für jede Charge bekannt
-- (Eingangsgewicht, Daten, Sorte, Schlag, Palettenzahl, CSV). Die
-- *Koeffizienten* stammen aus Stichproben. Teil 1 bereitet beides auf,
-- Teil 2 (0006) rechnet hoch.
--
-- Alle Views laufen mit security_invoker → die RLS der Tabellen gilt weiter.
-- =====================================================================

-- ---------- Netto je Palette ---------------------------------------------
-- Netto = Brutto − Kisten·Tara − Paletten-Tara. Fehlt ein Tara-Wert, bleibt
-- das Netto NULL: eine unbekannte Tara als 0 zu behandeln würde die
-- Eingangsmasse systematisch zu hoch ansetzen (Leer ≠ 0, Spec §8).
create view v_palette with (security_invoker = true) as
select p.id, p.charge_nr, p.eingangsdatum, p.brutto_kg, p.kisten, p.gebindeart,
       p.brutto_kg
         - coalesce(p.kisten, 0) * g.tara_kg_pro_kiste
         - coalesce(g.tara_kg_palette, 0) as netto_kg
  from palette p
  left join gebinde g on g.art = p.gebindeart;

-- ---------- Rückgrat je Charge -------------------------------------------
create view v_charge_rueckgrat with (security_invoker = true) as
select c.nr as charge_nr, c.schlag, c.sorte, c.saison,
       count(p.id)                          as n_paletten,
       count(p.netto_kg)                    as n_paletten_mit_netto,
       sum(p.netto_kg)                      as eingang_netto_kg,
       sum(p.brutto_kg)                     as eingang_brutto_kg,
       min(p.eingangsdatum)                 as erster_eingang,
       max(p.eingangsdatum)                 as letzter_eingang,
       -- massegewichtetes mittleres Eingangsdatum: die Charge wird gestaffelt
       -- eingelagert, ein einzelnes Datum wäre irreführend (Spec §1).
       (date '2000-01-01' + (sum((p.eingangsdatum - date '2000-01-01') * coalesce(p.netto_kg, 1))
                             / nullif(sum(coalesce(p.netto_kg, 1)), 0))::int) as eingangsdatum_mittel
  from charge c
  left join v_palette p on p.charge_nr = c.nr
 group by c.nr, c.schlag, c.sorte, c.saison;

comment on view v_charge_rueckgrat is
  'Das für jede Charge sicher Bekannte. Grundlage jeder Hochrechnung.';

-- ---------- Masse hinter einer gezählten Palette --------------------------
-- Der Arbeiter zählt Paletten und notiert optional das Eingangsdatum vom
-- Zettel. Daraus wird die Eingangsmasse geschätzt — mit einer sichtbaren
-- Genauigkeitsstufe, damit im Rechenweg steht, wie gut die Zahl ist.
create view v_auftrag_palette_masse with (security_invoker = true) as
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(p.netto_kg, d.netto_mittel, cm.netto_mittel)              as netto_kg,
       coalesce(p.eingangsdatum, ap.eingangsdatum, cm.eingangsdatum_mittel) as eingangsdatum,
       case when p.netto_kg  is not null then 'palette'
            when d.netto_mittel  is not null then 'datum-mittel'
            when cm.netto_mittel is not null then 'charge-mittel'
            else 'unbekannt' end                                          as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join v_palette p on p.id = ap.palette_id
  left join lateral (
        select avg(x.netto_kg) as netto_mittel
          from v_palette x
         where x.charge_nr = a.charge_nr and x.eingangsdatum = ap.eingangsdatum
       ) d on true
  left join lateral (
        select avg(x.netto_kg) as netto_mittel, r.eingangsdatum_mittel
          from v_palette x, v_charge_rueckgrat r
         where x.charge_nr = a.charge_nr and r.charge_nr = a.charge_nr
         group by r.eingangsdatum_mittel
       ) cm on true;

-- ---------- Auftrag: verarbeitete Masse und Lagerdauer --------------------
create view v_auftrag_masse with (security_invoker = true) as
select a.id as auftrag_id, a.charge_nr, c.sorte, c.schlag, a.weg, a.station,
       a.start_ts, a.ende_ts, a.status,
       count(m.id)                                     as n_paletten,
       -- Eingangs-Äquivalent der verarbeiteten Menge: entweder aus gezählten
       -- Paletten oder — beim Waschen auf Weg 1 — aus dem erfassten Durchsatz.
       coalesce(sum(m.netto_kg), a.durchsatz_kg)        as eingang_netto_kg,
       case when sum(m.netto_kg) is not null then 'paletten'
            when a.durchsatz_kg  is not null then 'durchsatz'
            else 'fehlt' end                            as masse_quelle,
       -- massegewichtete Lagerdauer bis zum Auftragsbeginn
       (sum((a.start_ts::date - m.eingangsdatum) * m.netto_kg)
        / nullif(sum(m.netto_kg), 0))::numeric(10,1)    as lagertage
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_auftrag_palette_masse m on m.auftrag_id = a.id
 group by a.id, a.charge_nr, c.sorte, c.schlag, a.weg, a.station,
          a.start_ts, a.ende_ts, a.status, a.durchsatz_kg;

-- ---------- Sortierlauf: Masse je Klasse ----------------------------------
create view v_sortier_lauf_masse with (security_invoker = true) as
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
 group by l.id, l.charge_nr, c.sorte, c.schlag, l.auftrag_id, l.datei_name, l.datei_zeit, l.zuordnung;

-- Verteilung je Kaliber-Band — für „engeres Band liefern" (Spec §3, Weg 1).
create view v_kaliber_verteilung with (security_invoker = true) as
select l.charge_nr, c.sorte, g.klasse, g.kaliber_idx,
       (s.kaliber_baender -> g.kaliber_idx ->> 0)::int as band_von,
       (s.kaliber_baender -> g.kaliber_idx ->> 1)::int as band_bis,
       sum(g.anzahl)                                                 as n_kuerbis,
       (sum(g.anzahl::bigint * g.gewicht_g) / 1000.0)::numeric(12,2) as masse_kg
  from sortier_gewicht g
  join sortier_lauf l on l.id = g.lauf_id
  join charge c on c.nr = l.charge_nr
  join sorte_kaliber s on s.sorte = c.sorte
 group by l.charge_nr, c.sorte, g.klasse, g.kaliber_idx, s.kaliber_baender;

-- Eine Zeile je Kürbis, aus dem Histogramm zurückgewonnen. Gespeichert wird
-- lauflängenkodiert (siehe Kommentar an sortier_gewicht); wer doch einmal pro
-- Kürbis rechnen will — Quantile, Verteilungsplots — nimmt diese View.
create view v_sortier_kuerbis with (security_invoker = true) as
select g.lauf_id, l.charge_nr, c.sorte, g.gewicht_g, g.klasse, g.kaliber_idx
  from sortier_gewicht g
  join sortier_lauf l on l.id = g.lauf_id
  join charge c on c.nr = l.charge_nr
  cross join generate_series(1, g.anzahl);


-- =====================================================================
-- aus 0006_koeffizienten.sql
-- =====================================================================

-- =====================================================================
-- 0006 — Auswertung, Teil 2: die Koeffizienten aus den Stichproben
--
-- Jeder Koeffizient kommt als (mittel, unten, oben, n, basis) — die
-- Unsicherheit wird mitgeführt, nicht weggerundet (Spec §9). `basis` sagt,
-- woraus der Wert stammt, und ist die Grundlage des aufklappbaren
-- Rechenwegs auf Ebene 3 des Dashboards.
--
-- Modell der Massenkaskade (in dieser Reihenfolge angewandt):
--   Eingang  --Verdunstung-->  M1  --Schimmel-->  M2  --Ausschuss/Nebenkanal-->  verkaufsfähig
-- Jeder Anteil bezieht sich auf die Masse, die in seinen Schritt hineingeht.
-- Nur so lassen sich die Ströme addieren, ohne Basen zu vermischen.
-- =====================================================================

-- ---------- Verdunstung ---------------------------------------------------
-- Wasserverlust läuft multiplikativ, nicht linear: aus dem Gewichtsverhältnis
-- wird eine Tagesrate r mit  netto_jetzt = netto_damals · (1−r)^Lagertage.
-- Vorteil gegenüber „Prozent pro Tag mal Tage": die Hochrechnung kann auch
-- über lange Lagerdauern nie mehr als die vorhandene Masse verbrauchen.
create view v_verdunstung_messung with (security_invoker = true) as
select w.id, w.charge_nr, c.sorte, c.schlag, w.palette_id, w.eingangsdatum,
       w.wiege_ts, w.sichtbar_schimmel, w.erfasser, w.auftrag_id,
       n.netto_damals_kg, n.netto_jetzt_kg,
       (w.wiege_ts::date - w.eingangsdatum) as lagertage,
       case when n.netto_damals_kg > 0 and n.netto_jetzt_kg > 0
             and (w.wiege_ts::date - w.eingangsdatum) > 0
            then 1 - power(n.netto_jetzt_kg / n.netto_damals_kg,
                           1.0 / (w.wiege_ts::date - w.eingangsdatum))
       end::numeric(10,6) as rate_pro_tag,
       -- Sichtbar verschimmelte Paletten mischen Fäulnis in die Verdunstung.
       -- Sie bleiben sichtbar, zählen aber nicht in den Koeffizienten.
       (w.gemessen and not w.sichtbar_schimmel
        and n.netto_damals_kg > 0 and n.netto_jetzt_kg > 0
        and (w.wiege_ts::date - w.eingangsdatum) > 0) as verwendbar
  from verdunstung_wiegung w
  join charge c on c.nr = w.charge_nr
  left join gebinde g on g.art = w.gebindeart
  cross join lateral (
        select w.brutto_damals_kg - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                                  - coalesce(g.tara_kg_palette, 0) as netto_damals_kg,
               w.brutto_jetzt_kg  - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                                  - coalesce(g.tara_kg_palette, 0) as netto_jetzt_kg
       ) n;

-- Je Sorte und über alles. Das Intervall ist der 95-%-Bereich für den
-- Mittelwert (normale Näherung, ab n ≥ 2).
create view v_verdunstung_stichprobe with (security_invoker = true) as
with roh as (select * from v_verdunstung_messung where verwendbar)
select grp.sorte, s.n, s.mittel, s.sd,
       case when s.n >= 2 then s.mittel - 1.96 * s.sd / sqrt(s.n) end as unten,
       case when s.n >= 2 then s.mittel + 1.96 * s.sd / sqrt(s.n) end as oben
  from (select sorte from roh group by sorte union all select null) grp
  cross join lateral (
        select count(*)::int as n, avg(rate_pro_tag) as mittel, stddev_samp(rate_pro_tag) as sd
          from roh where grp.sorte is null or roh.sorte = grp.sorte
       ) s;

-- Effektiver Koeffizient je Sorte: eigene Stichprobe, sobald sie belastbar
-- ist (n ≥ 3), sonst der Gesamtwert. Die Spalte `basis` macht das sichtbar.
create view v_koeff_verdunstung with (security_invoker = true) as
-- Bei n = 1 gibt es keinen Streubereich. Dann gilt der Punktwert für alle
-- drei Szenarien — der Bereich ist noch nicht bestimmbar, und `n` sagt das.
-- Eine erfundene Spanne wäre schlimmer als eine sichtbar fehlende.
select sk.sorte,
       coalesce(js.mittel, ge.mittel)                              as mittel,
       coalesce(js.unten,  ge.unten,  js.mittel, ge.mittel)        as unten,
       coalesce(js.oben,   ge.oben,   js.mittel, ge.mittel)        as oben,
       coalesce(js.n, ge.n, 0)                                     as n,
       case when js.sorte is not null then 'Wiegungen dieser Sorte'
            when ge.n > 0            then 'Wiegungen aller Sorten (zu wenige eigene)'
            else 'keine Wiegung vorhanden' end                     as basis
  from sorte_kaliber sk
  left join v_verdunstung_stichprobe js on js.sorte = sk.sorte and js.n >= 3
  left join v_verdunstung_stichprobe ge on ge.sorte is null;

-- ---------- Schimmel / Fäulnis -------------------------------------------
-- Beobachtung je Auftrag: welcher Anteil der Masse, die an diesem Tag aus dem
-- Lager kam, war faul. Der Nenner ist die *heutige* Masse — also die
-- Eingangsmasse abzüglich der bis dahin verdunsteten Menge. Sonst würde der
-- Schimmelanteil mit der Lagerdauer allein durch die Verdunstung steigen.
create view v_schimmel_beobachtung with (security_invoker = true) as
select am.auftrag_id, am.charge_nr, am.sorte, am.schlag, am.weg, am.station,
       am.start_ts, am.lagertage, am.masse_quelle,
       s.kg                                                        as schimmel_kg,
       am.eingang_netto_kg                                         as eingang_kg,
       (am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage))::numeric(12,2)
                                                                   as basis_jetzt_kg,
       (s.kg / nullif(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage), 0))
                                                                   as anteil
  from v_auftrag_masse am
  join (select auftrag_id, sum(kg)::numeric as kg
          from schimmel_messung where gemessen group by auftrag_id) s
       on s.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
 where am.eingang_netto_kg is not null
   and am.lagertage is not null;

comment on view v_schimmel_beobachtung is
  'Bekannte kleine Verzerrung: der Palox wird heute gewogen, die faulen '
  'Kürbisse haben also selbst schon Wasser verloren. Der wahre Anteil liegt '
  'geringfügig höher als hier ausgewiesen.';

-- Altersklassen der Lagerdauer. Der Schimmelanteil ist *kumulativ*: ein
-- Auftrag nach 90 Tagen zeigt alles, was bis dahin verdorben ist.
create view v_schimmel_kurve with (security_invoker = true) as
with klassen(von, bis) as (
  values (0, 14), (15, 30), (31, 60), (61, 90), (91, 120), (121, 180), (181, 100000)
), je_klasse as (
  select k.von, k.bis,
         count(b.auftrag_id)::int as n,
         -- massegewichtet: eine große Palette wiegt schwerer als eine kleine
         sum(b.schimmel_kg) / nullif(sum(b.basis_jetzt_kg), 0) as anteil,
         stddev_samp(b.anteil)                                 as sd
    from klassen k
    left join v_schimmel_beobachtung b
           on b.lagertage >= k.von and b.lagertage <= k.bis and b.anteil is not null
   group by k.von, k.bis
)
select von, bis, n, anteil, sd,
       -- Kumulativ heißt: der Anteil kann mit dem Alter nicht sinken. Bei
       -- wenigen Stichproben tut er das trotzdem; das laufende Maximum
       -- glättet solche Ausreißer nach unten weg (isotone Korrektur).
       max(anteil) over (order by von rows between unbounded preceding and current row) as anteil_mono,
       case when n >= 2 then greatest(anteil - 1.96 * sd / sqrt(n), 0) end as unten,
       case when n >= 2 then least(anteil + 1.96 * sd / sqrt(n), 1) end    as oben
  from je_klasse;

-- Schimmelanteil bei gegebener Lagerdauer. Ist die Altersklasse leer, gilt
-- der letzte belegte Wert darunter (Treppenfunktion, nach oben fortgeschrieben).
create or replace function schimmelanteil(p_lagertage numeric, p_szenario text default 'mittel')
returns numeric language sql stable as $$
  select coalesce((
    select case p_szenario
             when 'unten' then coalesce(k.unten, k.anteil_mono)
             when 'oben'  then coalesce(k.oben,  k.anteil_mono)
             else k.anteil_mono end
      from v_schimmel_kurve k
     where k.von <= p_lagertage and k.n > 0
     order by k.von desc
     limit 1
  ), 0)::numeric;
$$;

-- ---------- Ausschuss zu klein & Nebenkanal zu gross ----------------------
-- Weg 1: direkt aus der Sortier-CSV (Massenanteil im selben Strom, gleiche
-- Basis, gleicher Moment). Weg 2: aus den Handmessungen, Basis = verarbeitete
-- Masse nach Verdunstung und abzüglich des ausgelesenen Schimmels.
create view v_ausschuss_beobachtung with (security_invoker = true) as
-- masse_kg ist die Gesamtmasse des Laufs, inklusive der zu kleinen und der
-- zu großen Kürbisse — genau die Masse, die über das Band gelaufen ist.
select 'maschine'::verarbeitungsweg as weg, lm.charge_nr, lm.sorte, lm.auftrag_id,
       lm.masse_kg                                  as basis_kg,
       lm.masse_klein_kg                            as klein_kg,
       lm.masse_nebenkanal_kg                       as gross_kg
  from v_sortier_lauf_masse lm
 where lm.masse_kg > 0
union all
select 'hand'::verarbeitungsweg, am.charge_nr, am.sorte, am.auftrag_id,
       (am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage)
        - coalesce(sm.kg, 0))::numeric(12,2),
       h.klein_kg, h.gross_kg
  from v_auftrag_masse am
  join (select auftrag_id,
               sum(kg) filter (where art = 'zu_klein')::numeric as klein_kg,
               sum(kg) filter (where art = 'zu_gross')::numeric as gross_kg
          from ausschuss_messung where gemessen group by auftrag_id) h
       on h.auftrag_id = am.auftrag_id
  left join (select auftrag_id, sum(kg)::numeric as kg from schimmel_messung
              where gemessen group by auftrag_id) sm on sm.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
 where am.weg = 'hand' and am.eingang_netto_kg is not null and am.lagertage is not null;

create view v_koeff_ausschuss with (security_invoker = true) as
with roh as (
  select sorte, klein_kg / nullif(basis_kg, 0) as anteil, basis_kg
    from v_ausschuss_beobachtung where klein_kg is not null and basis_kg > 0
), stich as (
  select grp.sorte, s.n, s.mittel, s.sd
    from (select sorte from roh group by sorte union all select null) grp
    cross join lateral (
      select count(*)::int as n,
             -- massegewichtet: ein großer Lauf zählt mehr als ein kleiner
             sum(anteil * basis_kg) / nullif(sum(basis_kg), 0) as mittel,
             stddev_samp(anteil) as sd
        from roh where grp.sorte is null or roh.sorte = grp.sorte) s
), eff as (
  select sk.sorte,
         coalesce(js.n, ge.n, 0)        as n,
         coalesce(js.mittel, ge.mittel) as mittel,
         coalesce(js.sd, ge.sd)         as sd,
         case when js.sorte is not null then 'Sortierläufe/Handmessungen dieser Sorte'
              when ge.n > 0             then 'alle Sorten (zu wenige eigene)'
              else 'keine Messung vorhanden' end as basis
    from sorte_kaliber sk
    left join stich js on js.sorte = sk.sorte and js.n >= 2
    left join stich ge on ge.sorte is null
)
select sorte, mittel,
       -- Ohne Streuung (n < 2) gibt es keinen Bereich: dann gilt der Punktwert
       -- für alle drei Szenarien. greatest()/least() würden NULL still zu 0
       -- bzw. 1 machen und damit einen Bereich vortäuschen, den es nicht gibt.
       case when sd is null or n < 2 then mittel
            else greatest(mittel - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then mittel
            else least(mittel + 1.96 * sd / sqrt(n), 1) end    as oben,
       n, basis
  from eff;

create view v_koeff_nebenkanal with (security_invoker = true) as
with roh as (
  select sorte, gross_kg / nullif(basis_kg, 0) as anteil, basis_kg
    from v_ausschuss_beobachtung where gross_kg is not null and basis_kg > 0
), stich as (
  select grp.sorte, s.n, s.mittel, s.sd
    from (select sorte from roh group by sorte union all select null) grp
    cross join lateral (
      select count(*)::int as n,
             -- massegewichtet: ein großer Lauf zählt mehr als ein kleiner
             sum(anteil * basis_kg) / nullif(sum(basis_kg), 0) as mittel,
             stddev_samp(anteil) as sd
        from roh where grp.sorte is null or roh.sorte = grp.sorte) s
), eff as (
  select sk.sorte,
         coalesce(js.n, ge.n, 0)        as n,
         coalesce(js.mittel, ge.mittel) as mittel,
         coalesce(js.sd, ge.sd)         as sd,
         case when js.sorte is not null then 'Sortierläufe/Handmessungen dieser Sorte'
              when ge.n > 0             then 'alle Sorten (zu wenige eigene)'
              else 'keine Messung vorhanden' end as basis
    from sorte_kaliber sk
    left join stich js on js.sorte = sk.sorte and js.n >= 2
    left join stich ge on ge.sorte is null
)
select sorte, mittel,
       -- Ohne Streuung (n < 2) gibt es keinen Bereich: dann gilt der Punktwert
       -- für alle drei Szenarien. greatest()/least() würden NULL still zu 0
       -- bzw. 1 machen und damit einen Bereich vortäuschen, den es nicht gibt.
       case when sd is null or n < 2 then mittel
            else greatest(mittel - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then mittel
            else least(mittel + 1.96 * sd / sqrt(n), 1) end    as oben,
       n, basis
  from eff;

-- ---------- Überfüllung (Buch B, Weg 2) -----------------------------------
-- Fixpreis je Kiste ab 8 kg, real 8.1–8.5 → der Überschuss ist verschenkte
-- Ware. Gemessen wird der Überschuss über n Kisten; hier auf eine Kiste
-- heruntergerechnet.
create view v_koeff_ueberfuellung with (security_invoker = true) as
with roh as (
  select wert, n_kisten, wert / nullif(n_kisten, 0) as je_kiste
    from marge_messung where art = 'ueberfuellung' and gemessen and n_kisten > 0
), s as (
  select count(*)::int as n,
         sum(wert) / nullif(sum(n_kisten), 0) as kg_pro_kiste,
         stddev_samp(je_kiste)                as sd
    from roh
)
select n, kg_pro_kiste, sd,
       case when sd is null or n < 2 then kg_pro_kiste
            else greatest(kg_pro_kiste - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then kg_pro_kiste
            else kg_pro_kiste + 1.96 * sd / sqrt(n) end              as oben
  from s;


-- Wie viele Beobachtungen stecken hinter dem Schimmelanteil für diese
-- Lagerdauer? Gehört in den aufklappbaren Rechenweg auf Ebene 3.
create or replace function schimmel_n(p_lagertage numeric)
returns int language sql stable as $$
  select coalesce((select k.n from v_schimmel_kurve k
                    where k.von <= p_lagertage and k.n > 0
                    order by k.von desc limit 1), 0);
$$;


-- =====================================================================
-- aus 0007_hochrechnung.sql
-- =====================================================================

-- =====================================================================
-- 0007 — Auswertung, Teil 3: Hochrechnung, Ranking, Massenbilanz
--
-- Verlust = Koeffizient × bekannte Größe, stratifiziert nach Sorte und
-- Lagerdauer, Ergebnis als Bereich (Spec §9). Jede Charge wird in zwei
-- Portionen zerlegt:
--   * ausgelagert — schon verarbeitet, Lagerdauer beobachtet
--   * im Lager    — rechts-zensiert, bis zum Stichtag projiziert
-- Genau das ist die Antwort auf „mitten in der Saison auswertbar".
-- =====================================================================

create view v_hochrechnung_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung where schluessel = 'saison_ende'),
                  current_date) as bis
), ausgang as (
  -- Was hat das Lager verlassen? Nur die erste Station zählt: Waschen auf
  -- Weg 1 ist ein zweiter Griff an bereits sortierte Ware, keine neue Auslagerung.
  select charge_nr,
         sum(eingang_netto_kg)                                              as kg,
         sum(eingang_netto_kg * lagertage) / nullif(sum(eingang_netto_kg), 0) as lagertage,
         sum(eingang_netto_kg) filter (where weg = 'hand')                  as kg_hand
    from v_auftrag_masse
   where station in ('sortieren', 'waschen_sortieren')
     and eingang_netto_kg is not null
   group by charge_nr
)
select r.charge_nr, r.schlag, r.sorte, r.eingang_netto_kg as eingang_kg,
       r.n_paletten, r.eingangsdatum_mittel,
       coalesce(a.kg, 0)::numeric                                    as ausgelagert_kg,
       a.lagertage                                                   as alter_ausgelagert,
       greatest(r.eingang_netto_kg - coalesce(a.kg, 0), 0)::numeric   as lager_kg,
       (s.bis - r.eingangsdatum_mittel)::numeric                     as alter_lager,
       (current_date - r.eingangsdatum_mittel)::numeric              as alter_lager_heute,
       coalesce(a.kg_hand / nullif(a.kg, 0), 0)                      as weg2_anteil,
       s.bis                                                         as stichtag
  from v_charge_rueckgrat r
  cross join stichtag s
  left join ausgang a on a.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;

-- ---------- Die Kaskade, je Charge und Szenario ---------------------------
create view v_kaskade with (security_invoker = true) as
with sz(szenario) as (values ('unten'), ('mittel'), ('oben')),
koeff as (
  select b.*, sz.szenario,
         -- Ein Koeffizient außerhalb des Plausiblen ist ein Rechenartefakt
         -- der kleinen Stichprobe, kein Messergebnis — daher gekappt.
         least(greatest(case sz.szenario when 'unten' then kv.unten
                                         when 'oben'  then kv.oben
                                         else kv.mittel end, 0), 0.05) as r,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(case sz.szenario when 'unten' then ka.unten
                                         when 'oben'  then ka.oben
                                         else ka.mittel end, 0), 1) as a_klein,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(case sz.szenario when 'unten' then kn.unten
                                         when 'oben'  then kn.oben
                                         else kn.mittel end, 0), 1) as a_gross,
         kn.n as gross_n, kn.basis as gross_basis
    from v_hochrechnung_basis b
    cross join sz
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
),
koeff_norm as (
  -- Im oberen Szenario können die Obergrenzen von „zu klein" und „zu gross"
  -- zusammen über 100 % liegen. Beide dann proportional herunterskalieren:
  -- das erhält ihr Verhältnis und lässt keine negative Restmasse entstehen.
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  -- Beide Portionen in einer Form, damit die Kaskade nur einmal dasteht.
  select k.*, t.portion, t.m0, t.alter_tage,
         schimmelanteil(t.alter_tage, k.szenario) as f
    from koeff_norm k
    cross join lateral (values
        ('ausgelagert', k.ausgelagert_kg, coalesce(k.alter_ausgelagert, 0)),
        ('lager',       k.lager_kg,       greatest(k.alter_lager, 0))
      ) as t(portion, m0, alter_tage)
   where t.m0 > 0
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))::numeric              as m1,
         (t.m0 * power(1 - t.r, t.alter_tage) * (1 - t.f))::numeric  as m2
    from teile t
)
select k.*,
       k.m0 - k.m1                                    as verdunstung_kg,
       k.m1 - k.m2                                    as schimmel_kg,
       k.m2 * k.a_klein_n                             as klein_kg,
       k.m2 * k.a_gross_n                             as nebenkanal_kg,
       k.m2 * (1 - k.a_klein_n - k.a_gross_n)         as verkaufsfaehig_kg
  from kaskade k;

-- ---------- Ströme in Langform: die Datenquelle des Dashboards -------------
create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.szenario, k.portion, k.alter_tage,
       k.eingang_kg, k.m0 as portion_kg, s.strom, s.buch, s.kg, s.basis_kg,
       s.koeffizient, s.koeff_n, s.koeff_basis, s.formel
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung',      'verlust', k.verdunstung_kg, k.m0, k.r,       k.r_n,     k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'),
    ('Schimmel/Fäulnis', 'verlust', k.schimmel_kg,    k.m1, k.f,       schimmel_n(k.alter_tage), 'Schimmelkurve nach Lagerdauer',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer'),
    ('Ausschuss zu klein','verlust', k.klein_kg,      k.m2, k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze'),
    ('Nebenkanal zu gross','marge',  k.nebenkanal_kg, k.m2, k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'),
    ('Verkaufsfähig',    'bilanz',  k.verkaufsfaehig_kg, k.m2, null::numeric, null::int, null::text,
     'Rest der Kaskade')
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel);

-- ---------- Ebene 1: die Ursachen, rangiert ------------------------------
create view v_verlust_ranking with (security_invoker = true) as
select strom, buch,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       sum(kg) filter (where szenario = 'mittel' and portion = 'ausgelagert') as kg_beobachtet,
       sum(kg) filter (where szenario = 'mittel' and portion = 'lager')       as kg_projiziert,
       min(koeff_n)                                                          as koeff_n_min
  from v_hochrechnung
 where buch = 'verlust'
 group by strom, buch
 order by 3 desc nulls last;

-- ---------- Buch B: verschenkte Marge ------------------------------------
-- Weg 1 (Nebenkanal-Überschuss) und Weg 2 (Überfüllung) sind zwei völlig
-- verschiedene Wege, Ware zu verschenken. Sie stehen bewusst nebeneinander
-- und werden nie in das Verlust-Buch gemischt (Spec §2).
create view v_marge_buch with (security_invoker = true) as
select 'Nebenkanal zu gross'::text as posten,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from v_hochrechnung where buch = 'marge'
union all
select 'Überfüllung der 8-kg-Kisten',
       u.kg_pro_kiste * v.kisten, u.unten * v.kisten, u.oben * v.kisten,
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.kisten))
  from v_koeff_ueberfuellung u
  cross join lateral (
        -- Kistenzahl aus der verkaufsfähigen Weg-2-Masse (Fixpreis ab 8 kg)
        select sum(h.kg * b.weg2_anteil) / 8.0 as kisten
          from v_hochrechnung h
          join v_hochrechnung_basis b on b.charge_nr = h.charge_nr
         where h.strom = 'Verkaufsfähig' and h.szenario = 'mittel'
       ) v
 where u.n > 0;

-- ---------- Massenbilanz als Kontrolle ------------------------------------
-- Der eigentliche Test ist nicht, ob die Kaskade in sich aufgeht (das tut sie
-- per Konstruktion), sondern ob sie die *gemessene* Wirklichkeit trifft: die
-- modellierte Masse am Sortierband gegen die tatsächlich gewogene CSV-Masse.
create view v_massenbilanz with (security_invoker = true) as
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       m.modell_kg                                     as modell_am_band_kg,
       c.gemessen_kg                                   as csv_gemessen_kg,
       (c.gemessen_kg - m.modell_kg)                   as abweichung_kg,
       case when m.modell_kg > 0
            then (c.gemessen_kg - m.modell_kg) / m.modell_kg end as abweichung_anteil,
       h.restbestand_kg
  from v_hochrechnung_basis b
  left join lateral (
        select sum(k.m2) as modell_kg from v_kaskade k
         where k.charge_nr = b.charge_nr and k.szenario = 'mittel' and k.portion = 'ausgelagert'
       ) m on true
  left join lateral (
        select sum(lm.masse_kg) as gemessen_kg
          from v_sortier_lauf_masse lm where lm.charge_nr = b.charge_nr
       ) c on true
  left join lateral (
        select sum(k.verkaufsfaehig_kg) as restbestand_kg from v_kaskade k
         where k.charge_nr = b.charge_nr and k.szenario = 'mittel' and k.portion = 'lager'
       ) h on true;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

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

-- Lesen: alle Tabellen und Auswerte-Views.
grant select on all tables in schema public to authenticated;

-- Schreiben: nur die Tabellen, in die tatsächlich geschrieben wird.
grant insert, update, delete on
  profil, gebinde, sorte_kaliber, charge, palette, einstellung,
  auftrag, auftrag_teilnehmer, auftrag_palette,
  schimmel_messung, ausschuss_messung, verdunstung_wiegung, marge_messung,
  sortier_lauf, sortier_gewicht
  to authenticated;

grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

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

-- ---------- Schimmel ------------------------------------------------------
create or replace view v_schimmel_beobachtung with (security_invoker = true) as
select am.auftrag_id, am.charge_nr, am.sorte, am.schlag, am.weg, am.station,
       am.start_ts, am.lagertage, am.masse_quelle,
       s.kg                                                        as schimmel_kg,
       am.eingang_netto_kg                                         as eingang_kg,
       (am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage))::numeric(12,2)
                                                                   as basis_jetzt_kg,
       (s.kg / nullif(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage), 0))
                                                                   as anteil,
       -- neu ans Ende angehängt, damit bestehende Views weiterlaufen
       anteil_plausibel(
         (s.kg / nullif(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage), 0))::numeric
       )                                                           as plausibel
  from v_auftrag_masse am
  join (select auftrag_id, sum(kg)::numeric as kg
          from schimmel_messung where gemessen group by auftrag_id) s
       on s.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
 where am.eingang_netto_kg is not null
   and am.lagertage is not null;

-- Nur plausible Beobachtungen bilden die Kurve.
create or replace view v_schimmel_kurve with (security_invoker = true) as
with klassen(von, bis) as (
  values (0, 14), (15, 30), (31, 60), (61, 90), (91, 120), (121, 180), (181, 100000)
), je_klasse as (
  select k.von, k.bis,
         count(b.auftrag_id)::int as n,
         sum(b.schimmel_kg) / nullif(sum(b.basis_jetzt_kg), 0) as anteil,
         stddev_samp(b.anteil)                                 as sd
    from klassen k
    left join v_schimmel_beobachtung b
           on b.lagertage >= k.von and b.lagertage <= k.bis
          and b.anteil is not null and b.plausibel
   group by k.von, k.bis
)
select von, bis, n, anteil, sd,
       least(greatest(
         max(anteil) over (order by von rows between unbounded preceding and current row), 0), 1)
                                                                    as anteil_mono,
       case when n >= 2 then greatest(anteil - 1.96 * sd / sqrt(n), 0) end as unten,
       case when n >= 2 then least(anteil + 1.96 * sd / sqrt(n), 1) end    as oben
  from je_klasse;

-- Letzte Sicherung direkt an der Quelle: Was hier herauskommt, geht als
-- (1 − f) in die Kaskade. Ein f > 1 würde negative Masse erzeugen.
create or replace function schimmelanteil(p_lagertage numeric, p_szenario text default 'mittel')
returns numeric language sql stable as $$
  select least(greatest(coalesce((
    select case p_szenario
             when 'unten' then coalesce(k.unten, k.anteil_mono)
             when 'oben'  then coalesce(k.oben,  k.anteil_mono)
             else k.anteil_mono end
      from v_schimmel_kurve k
     where k.von <= p_lagertage and k.n > 0
     order by k.von desc
     limit 1
  ), 0), 0), 1)::numeric;
$$;

-- ---------- Ausschuss und Nebenkanal --------------------------------------
-- Auf Weg 2 wird die Bezugsmasse um den ausgelesenen Schimmel verringert.
-- Ist dieser Wert vertippt, wurde die Basis negativ und der Anteil unsinnig.
create or replace view v_ausschuss_beobachtung with (security_invoker = true) as
select 'maschine'::verarbeitungsweg as weg, lm.charge_nr, lm.sorte, lm.auftrag_id,
       lm.masse_kg                                  as basis_kg,
       lm.masse_klein_kg                            as klein_kg,
       lm.masse_nebenkanal_kg                       as gross_kg,
       true                                         as plausibel
  from v_sortier_lauf_masse lm
 where lm.masse_kg > 0
union all
select 'hand'::verarbeitungsweg, am.charge_nr, am.sorte, am.auftrag_id,
       n.basis, h.klein_kg, h.gross_kg,
       anteil_plausibel((h.klein_kg  / nullif(n.basis, 0))::numeric)
         and anteil_plausibel((coalesce(h.gross_kg, 0) / nullif(n.basis, 0))::numeric)
  from v_auftrag_masse am
  join (select auftrag_id,
               sum(kg) filter (where art = 'zu_klein')::numeric as klein_kg,
               sum(kg) filter (where art = 'zu_gross')::numeric as gross_kg
          from ausschuss_messung where gemessen group by auftrag_id) h
       on h.auftrag_id = am.auftrag_id
  left join (select auftrag_id, sum(kg)::numeric as kg from schimmel_messung
              where gemessen group by auftrag_id) sm on sm.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
  cross join lateral (
        select greatest(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage)
                        - coalesce(sm.kg, 0), 0)::numeric(12,2) as basis
       ) n
 where am.weg = 'hand' and am.eingang_netto_kg is not null and am.lagertage is not null;

create or replace view v_koeff_ausschuss with (security_invoker = true) as
with roh as (
  select sorte, klein_kg / nullif(basis_kg, 0) as anteil, basis_kg
    from v_ausschuss_beobachtung
   where klein_kg is not null and basis_kg > 0 and plausibel
), stich as (
  select grp.sorte, s.n, s.mittel, s.sd
    from (select sorte from roh group by sorte union all select null) grp
    cross join lateral (
      select count(*)::int as n,
             sum(anteil * basis_kg) / nullif(sum(basis_kg), 0) as mittel,
             stddev_samp(anteil) as sd
        from roh where grp.sorte is null or roh.sorte = grp.sorte) s
), eff as (
  select sk.sorte, coalesce(js.n, ge.n, 0) as n,
         coalesce(js.mittel, ge.mittel) as mittel, coalesce(js.sd, ge.sd) as sd,
         case when js.sorte is not null then 'Sortierläufe/Handmessungen dieser Sorte'
              when ge.n > 0             then 'alle Sorten (zu wenige eigene)'
              else 'keine Messung vorhanden' end as basis
    from sorte_kaliber sk
    left join stich js on js.sorte = sk.sorte and js.n >= 2
    left join stich ge on ge.sorte is null
)
select sorte, mittel,
       case when sd is null or n < 2 then mittel else greatest(mittel - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then mittel else least(mittel + 1.96 * sd / sqrt(n), 1) end    as oben,
       n, basis
  from eff;

create or replace view v_koeff_nebenkanal with (security_invoker = true) as
with roh as (
  select sorte, gross_kg / nullif(basis_kg, 0) as anteil, basis_kg
    from v_ausschuss_beobachtung
   where gross_kg is not null and basis_kg > 0 and plausibel
), stich as (
  select grp.sorte, s.n, s.mittel, s.sd
    from (select sorte from roh group by sorte union all select null) grp
    cross join lateral (
      select count(*)::int as n,
             sum(anteil * basis_kg) / nullif(sum(basis_kg), 0) as mittel,
             stddev_samp(anteil) as sd
        from roh where grp.sorte is null or roh.sorte = grp.sorte) s
), eff as (
  select sk.sorte, coalesce(js.n, ge.n, 0) as n,
         coalesce(js.mittel, ge.mittel) as mittel, coalesce(js.sd, ge.sd) as sd,
         case when js.sorte is not null then 'Sortierläufe/Handmessungen dieser Sorte'
              when ge.n > 0             then 'alle Sorten (zu wenige eigene)'
              else 'keine Messung vorhanden' end as basis
    from sorte_kaliber sk
    left join stich js on js.sorte = sk.sorte and js.n >= 2
    left join stich ge on ge.sorte is null
)
select sorte, mittel,
       case when sd is null or n < 2 then mittel else greatest(mittel - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then mittel else least(mittel + 1.96 * sd / sqrt(n), 1) end    as oben,
       n, basis
  from eff;

-- ---------- Was aussortiert wurde, muss sichtbar bleiben ------------------
create view v_plausibilitaet with (security_invoker = true) as
-- Schimmelmessungen, die mehr wiegen als die Palette hergibt
select 'Schimmel'::text as art, b.auftrag_id, b.charge_nr, b.sorte, b.start_ts,
       format('%s kg Schimmel auf %s kg Ware — das wären %s %%',
              round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100)) as befund,
       'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text as rat
  from v_schimmel_beobachtung b
 where b.anteil is not null and not b.plausibel
union all
-- Handmessungen auf Weg 2 mit unsinnigem Verhältnis
select 'Ausschuss', a.auftrag_id, a.charge_nr, a.sorte, null::timestamptz,
       format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse',
              round(coalesce(a.klein_kg, 0)), round(coalesce(a.gross_kg, 0)), round(a.basis_kg)),
       'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'
  from v_ausschuss_beobachtung a
 where a.weg = 'hand' and not a.plausibel
union all
-- Erfasst, aber von keiner Auswertung gelesen: Nebenkanal-Kilos werden aus der
-- Sortier-CSV bzw. aus ausschuss_messung('zu_gross') gewonnen. Eine Zeile hier
-- würde sonst spurlos verschwinden.
select 'Nicht ausgewertet', m.auftrag_id, a.charge_nr, c.sorte, m.ts,
       format('%s %s als marge_messung(nebenkanal) erfasst', m.wert, m.einheit),
       'Nebenkanal-Mengen gehören auf Weg 2 unter „zu gross"; auf Weg 1 kommen sie aus der CSV.'
  from marge_messung m
  join auftrag a on a.id = m.auftrag_id
  join charge c on c.nr = a.charge_nr
 where m.art = 'nebenkanal';

comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet. Nicht ignorieren: '
  'fast immer ein Tippfehler, der sich korrigieren lässt.';

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

grant select on v_plausibilitaet to authenticated;
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

-- ---------- Masse hinter einer gezählten Palette --------------------------
-- Neue oberste Stufe: die tatsächlich gewogene Palette. Der Rest der Leiter
-- bleibt unverändert, damit auch nur gezählte Paletten weiterhin zählen.
create or replace view v_auftrag_palette_masse with (security_invoker = true) as
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(w.netto_damals_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel)   as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum,
                cm.eingangsdatum_mittel)                                          as eingangsdatum,
       case when w.netto_damals_kg is not null then 'gewogen'
            when p.netto_kg        is not null then 'palette'
            when d.netto_mittel    is not null then 'datum-mittel'
            when cm.netto_mittel   is not null then 'charge-mittel'
            else 'unbekannt' end                                                  as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join lateral (
        -- Eingangs-Netto aus der Wägung: genau die Palette, exakt ihr Gewicht
        select (vw.brutto_damals_kg
                - coalesce(vw.kisten, 0) * g.tara_kg_pro_kiste
                - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_damals_kg,
               vw.eingangsdatum
          from verdunstung_wiegung vw
          left join gebinde g on g.art = vw.gebindeart
         where vw.id = ap.wiegung_id
       ) w on true
  left join v_palette p on p.id = ap.palette_id
  left join lateral (
        select avg(x.netto_kg) as netto_mittel
          from v_palette x
         where x.charge_nr = a.charge_nr and x.eingangsdatum = ap.eingangsdatum
       ) d on true
  left join lateral (
        select avg(x.netto_kg) as netto_mittel, r.eingangsdatum_mittel
          from v_palette x, v_charge_rueckgrat r
         where x.charge_nr = a.charge_nr and r.charge_nr = a.charge_nr
         group by r.eingangsdatum_mittel
       ) cm on true;

-- ---------- Was eine gewogene Palette verrät ------------------------------
-- Beantwortet die Frage „wie schwer ist ein einzelner Kürbis im Schnitt?",
-- für die es auf der Hand-Linie sonst keine Quelle gibt.
create view v_wiegung_kennzahl with (security_invoker = true) as
select w.id, w.auftrag_id, w.charge_nr, c.sorte, c.schlag,
       w.eingangsdatum, w.wiege_ts, w.kisten, w.gebindeart,
       w.sichtbar_schimmel, w.kuerbisse_pro_kiste,
       (w.wiege_ts::date - w.eingangsdatum)                              as lagertage,
       n.netto_damals_kg, n.netto_jetzt_kg,
       (n.netto_jetzt_kg / nullif(w.kisten, 0))::numeric(10,3)           as kg_pro_kiste,
       (n.netto_jetzt_kg / nullif(w.kisten * w.kuerbisse_pro_kiste, 0))::numeric(10,3)
                                                                         as kg_pro_kuerbis,
       (n.netto_damals_kg - n.netto_jetzt_kg)::numeric(10,2)             as verlust_kg
  from verdunstung_wiegung w
  join charge c on c.nr = w.charge_nr
  left join gebinde g on g.art = w.gebindeart
  cross join lateral (
        select (w.brutto_damals_kg - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_damals_kg,
               (w.brutto_jetzt_kg  - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_jetzt_kg
       ) n
 where w.gemessen;

comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, Gewichtsverlust, kg je Kiste '
  'und — falls die Kürbisse je Kiste erfasst wurden — kg je Kürbis.';

grant select on v_wiegung_kennzahl to authenticated;


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

create view v_ausgang_kennzahl with (security_invoker = true) as
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
  cross join lateral (
        select (w.brutto_kg - w.kisten * g.tara_kg_pro_kiste
                - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_kg
       ) n
  cross join lateral (
        select coalesce((select (wert #>> '{}')::numeric from einstellung
                          where schluessel = 'soll_kg_pro_kiste'), 8) as soll
       ) s
 where w.gemessen and a.abgebrochen_ts is null and n.netto_kg > 0;

comment on view v_ausgang_kennzahl is
  'Je fertiger Palette: tatsächliche Kilo je Kiste und der Überschuss über die '
  'Fixpreis-Grenze. Der Überschuss ist kein Verlust — die Ware ist verkauft, '
  'nur nicht bezahlt.';

grant select on v_ausgang_kennzahl to authenticated;

-- ---------- Überfüllung aus beiden Quellen --------------------------------
-- Die fertige Palette ist die bessere Quelle (Rohdaten statt Differenz), aber
-- ältere marge_messung-Zeilen dürfen deshalb nicht verloren gehen.
create or replace view v_koeff_ueberfuellung with (security_invoker = true) as
with roh as (
  select m.wert, m.n_kisten, (m.wert / nullif(m.n_kisten, 0))::numeric as je_kiste
    from marge_messung m
    join auftrag a on a.id = m.auftrag_id
   where m.art = 'ueberfuellung' and m.gemessen and m.n_kisten > 0
     and a.abgebrochen_ts is null
  union all
  select k.ueberfuellung_kg, k.kisten, k.ueberfuellung_je_kiste
    from v_ausgang_kennzahl k
), s as (
  select count(*)::int as n,
         sum(wert) / nullif(sum(n_kisten), 0) as kg_pro_kiste,
         stddev_samp(je_kiste)                as sd
    from roh
)
select n, kg_pro_kiste, sd,
       case when sd is null or n < 2 then kg_pro_kiste
            else greatest(kg_pro_kiste - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then kg_pro_kiste
            else kg_pro_kiste + 1.96 * sd / sqrt(n) end              as oben
  from s;

-- ---------- Abgebrochene Arbeiten aus der Auswertung nehmen ---------------
create or replace view v_auftrag_masse with (security_invoker = true) as
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
          a.start_ts, a.ende_ts, a.status, a.durchsatz_kg;

-- Wägungen einer abgebrochenen Arbeit dürfen die Verdunstungsrate nicht
-- beeinflussen. Ohne diesen Filter zählten sie weiter mit.
create or replace view v_verdunstung_messung with (security_invoker = true) as
select w.id, w.charge_nr, c.sorte, c.schlag, w.palette_id, w.eingangsdatum,
       w.wiege_ts, w.sichtbar_schimmel, w.erfasser, w.auftrag_id,
       n.netto_damals_kg, n.netto_jetzt_kg,
       (w.wiege_ts::date - w.eingangsdatum) as lagertage,
       case when n.netto_damals_kg > 0 and n.netto_jetzt_kg > 0
             and (w.wiege_ts::date - w.eingangsdatum) > 0
            then 1 - power(n.netto_jetzt_kg / n.netto_damals_kg,
                           1.0 / (w.wiege_ts::date - w.eingangsdatum))
       end::numeric(10,6) as rate_pro_tag,
       (w.gemessen and not w.sichtbar_schimmel
        and n.netto_damals_kg > 0 and n.netto_jetzt_kg > 0
        and (w.wiege_ts::date - w.eingangsdatum) > 0
        and (a.id is null or a.abgebrochen_ts is null)) as verwendbar
  from verdunstung_wiegung w
  join charge c on c.nr = w.charge_nr
  left join auftrag a on a.id = w.auftrag_id
  left join gebinde g on g.art = w.gebindeart
  cross join lateral (
        select w.brutto_damals_kg - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                                  - coalesce(g.tara_kg_palette, 0) as netto_damals_kg,
               w.brutto_jetzt_kg  - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                                  - coalesce(g.tara_kg_palette, 0) as netto_jetzt_kg
       ) n;

create or replace view v_wiegung_kennzahl with (security_invoker = true) as
select w.id, w.auftrag_id, w.charge_nr, c.sorte, c.schlag,
       w.eingangsdatum, w.wiege_ts, w.kisten, w.gebindeart,
       w.sichtbar_schimmel, w.kuerbisse_pro_kiste,
       (w.wiege_ts::date - w.eingangsdatum)                              as lagertage,
       n.netto_damals_kg, n.netto_jetzt_kg,
       (n.netto_jetzt_kg / nullif(w.kisten, 0))::numeric(10,3)           as kg_pro_kiste,
       (n.netto_jetzt_kg / nullif(w.kisten * w.kuerbisse_pro_kiste, 0))::numeric(10,3)
                                                                         as kg_pro_kuerbis,
       (n.netto_damals_kg - n.netto_jetzt_kg)::numeric(10,2)             as verlust_kg
  from verdunstung_wiegung w
  join charge c on c.nr = w.charge_nr
  left join auftrag a on a.id = w.auftrag_id
  left join gebinde g on g.art = w.gebindeart
  cross join lateral (
        select (w.brutto_damals_kg - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_damals_kg,
               (w.brutto_jetzt_kg  - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_jetzt_kg
       ) n
 where w.gemessen and (a.id is null or a.abgebrochen_ts is null);

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


-- =====================================================================
-- aus 0014_zahlen_und_einblick.sql
-- =====================================================================

-- =====================================================================
-- 0014 — Abfragbare Zahlen und Einblick hinter die Rechnung
--
-- TEIL A — numerische Ausgaben
--
-- power() und sqrt() liefern in Postgres "double precision". Das floss bis in
-- die Views durch, die der Betriebsleiter direkt abfragt — und dort scheitert
-- dann das Naheliegendste:
--
--   select round(kg, 1) from v_verlust_ranking;
--   ERROR:  function round(double precision, integer) does not exist
--
-- Genau dieser Weg ist ausdrücklich vorgesehen (Spec §11: Zugriff auf die
-- Rohdaten über die SQL-Oberfläche). Die Ausgabespalten sind deshalb jetzt
-- numeric. Die Zwischenrechnung in v_kaskade bleibt double — dort ist es
-- schneller und niemand fragt sie von Hand ab.
--
-- TEIL B — die Kurve sichtbar machen
--
-- Die Schimmel-Hochrechnung ist der undurchsichtigste Teil des Modells. Ohne
-- Einblick in die Kurve muss man ihr glauben. v_schimmel_kurve_anzeige legt
-- sie offen: je Altersklasse der gemessene Anteil, wie viele Messungen
-- dahinterstehen und welcher Wert tatsächlich verwendet wird.
-- =====================================================================

drop view if exists v_marge_buch;
drop view if exists v_verlust_ranking;
drop view if exists v_massenbilanz;
drop view if exists v_hochrechnung;

create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.szenario, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg,
       s.strom, s.buch,
       s.kg::numeric(14,2)          as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       s.koeffizient::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung',      'verlust', k.verdunstung_kg, k.m0, k.r,       k.r_n,     k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'),
    ('Schimmel/Fäulnis', 'verlust', k.schimmel_kg,    k.m1, k.f,       schimmel_n(k.alter_tage),
     'Schimmelkurve nach Lagerdauer',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer'),
    ('Ausschuss zu klein','verlust', k.klein_kg,      k.m2, k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze'),
    ('Nebenkanal zu gross','marge',  k.nebenkanal_kg, k.m2, k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'),
    ('Verkaufsfähig',    'bilanz',  k.verkaufsfaehig_kg, k.m2, null::numeric, null::int, null::text,
     'Rest der Kaskade')
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel);

create view v_verlust_ranking with (security_invoker = true) as
select strom, buch,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       sum(kg) filter (where szenario = 'mittel' and portion = 'ausgelagert') as kg_beobachtet,
       sum(kg) filter (where szenario = 'mittel' and portion = 'lager')       as kg_projiziert,
       min(koeff_n)                                                          as koeff_n_min
  from v_hochrechnung
 where buch = 'verlust'
 group by strom, buch
 order by 3 desc nulls last;

create view v_marge_buch with (security_invoker = true) as
select 'Nebenkanal zu gross'::text as posten,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from v_hochrechnung where buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.kisten)::numeric(14,2),
       (u.unten * v.kisten)::numeric(14,2),
       (u.oben  * v.kisten)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.kisten))
  from v_koeff_ueberfuellung u
  cross join lateral (
        select sum(h.kg * b.weg2_anteil) / 8.0 as kisten
          from v_hochrechnung h
          join v_hochrechnung_basis b on b.charge_nr = h.charge_nr
         where h.strom = 'Verkaufsfähig' and h.szenario = 'mittel'
       ) v
 where u.n > 0;

-- Die Massenbilanz vergleicht das Modell gegen die gewogene CSV. Dabei darf
-- nur verglichen werden, was auch wirklich über das Sortierband lief: Geht eine
-- Charge teils von Hand (keine CSV) und teils über die Maschine, stand vorher
-- die Modellmasse der *ganzen* Charge gegen die CSV eines Teils davon — die
-- Bilanz zeigte dann dauerhaft ein Defizit von 30–60 %, ohne dass etwas falsch
-- war. Das Modell wird deshalb auf den CSV-Anteil der ausgelagerten Masse
-- heruntergerechnet.
create view v_massenbilanz with (security_invoker = true) as
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       (m.modell_kg * q.anteil_mit_csv)::numeric(14,2)     as modell_am_band_kg,
       c.gemessen_kg                                       as csv_gemessen_kg,
       (c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)::numeric(14,2) as abweichung_kg,
       case when m.modell_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)
                  / (m.modell_kg * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       h.restbestand_kg::numeric(14,2)                     as restbestand_kg
  from v_hochrechnung_basis b
  left join lateral (
        select sum(k.m2) as modell_kg from v_kaskade k
         where k.charge_nr = b.charge_nr and k.szenario = 'mittel' and k.portion = 'ausgelagert'
       ) m on true
  left join lateral (
        -- Welcher Anteil der ausgelagerten Masse hat überhaupt eine CSV?
        select coalesce(
                 sum(am.eingang_netto_kg) filter (
                   where exists (select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
                 / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
          from v_auftrag_masse am
         where am.charge_nr = b.charge_nr
           and am.station in ('sortieren', 'waschen_sortieren')
           and am.eingang_netto_kg is not null
       ) q on true
  left join lateral (
        select sum(lm.masse_kg) as gemessen_kg
          from v_sortier_lauf_masse lm where lm.charge_nr = b.charge_nr
       ) c on true
  left join lateral (
        select sum(k.verkaufsfaehig_kg) as restbestand_kg from v_kaskade k
         where k.charge_nr = b.charge_nr and k.szenario = 'mittel' and k.portion = 'lager'
       ) h on true;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

-- ---------- Teil B: die Schimmelkurve offenlegen --------------------------
drop view if exists v_schimmel_kurve_anzeige;
create view v_schimmel_kurve_anzeige with (security_invoker = true) as
select k.von, k.bis,
       case when k.bis > 9999 then k.von || '+ Tage'
            else k.von || '–' || k.bis || ' Tage' end       as altersklasse,
       k.n                                                  as messungen,
       (k.anteil)::numeric(10,4)                            as gemessen,
       (k.anteil_mono)::numeric(10,4)                       as verwendet,
       (k.unten)::numeric(10,4)                             as unten,
       (k.oben)::numeric(10,4)                              as oben,
       case when k.n = 0 then 'keine Messung — es gilt der Wert der Klasse darunter'
            when k.anteil is distinct from k.anteil_mono
                 then 'gemessener Wert lag unter einer jüngeren Klasse; verdorbene Ware '
                      || 'wird nicht wieder gesund, deshalb wird der höhere Wert verwendet'
            when k.n < 2 then 'nur eine Messung — noch kein Bereich bestimmbar'
            else 'aus den Messungen dieser Altersklasse' end as erlaeuterung
  from v_schimmel_kurve k
 order by k.von;

comment on view v_schimmel_kurve_anzeige is
  'Die Schimmel-Hochrechnung zum Nachschauen: was gemessen wurde, was daraus '
  'verwendet wird und warum.';

grant select on v_schimmel_kurve_anzeige to authenticated;

-- ---------- Plausibilitäts-Schwelle nachgeschärft --------------------------
-- 90 % waren zu lasch: Ein Zahlendreher (450 → 4500 kg) landete bei 87 % und
-- rutschte durch. Über die Hälfte einer Palette als Schimmel ist entweder ein
-- Tippfehler oder eine Katastrophe — beides gehört dem Betriebsleiter gemeldet,
-- und beides würde den Koeffizienten beherrschen, wenn es mitgerechnet würde.
create or replace function anteil_plausibel(p_anteil numeric)
returns boolean language sql immutable as $$
  select p_anteil is not null and p_anteil >= 0 and p_anteil <= 0.5;
$$;


-- =====================================================================
-- aus 0015_tempo.sql
-- =====================================================================

-- =====================================================================
-- 0015 — Tempo: die Auswertung lief in Supabases Zeitlimit
--
-- Symptom: „canceling statement due to statement timeout" beim Öffnen der
-- Auswertung. Gemessen an der Demo-Saison (535 Paletten, 22 Arbeiten):
--   v_hochrechnung   2 553 ms
--   v_verlust_ranking 2 441 ms
--   v_marge_buch     3 895 ms
-- Das Dashboard holt ein Dutzend Ansichten gleichzeitig — auf der geteilten
-- Gratis-CPU reicht das für die 8-Sekunden-Grenze.
--
-- Zwei Ursachen, beide dieselbe Sorte Fehler: etwas Teures wird pro Zeile
-- statt einmal gerechnet.
--
--   1. schimmelanteil() ist eine Funktion, die intern die ganze Kette
--      v_schimmel_kurve → v_schimmel_beobachtung → v_auftrag_masse abfragt.
--      In v_kaskade stand sie in der Select-Liste — also 60 Aufrufe à 16 ms,
--      jeder mit der vollständigen Kette dahinter. Jetzt wird die Kurve einmal
--      in eine materialisierte CTE gelegt und angejoint.
--
--   2. v_auftrag_palette_masse holte das Chargen- und Datumsmittel über
--      seitliche Unterabfragen — für jede der 286 gezählten Paletten neu,
--      inklusive einer Aggregation über alle 535 Eingangspaletten. Jetzt
--      werden diese Mittel einmal gebildet und normal angejoint.
--
-- Ergebnis identisch, nur schneller: Die Prüfabfragen rechnen dieselben Zahlen.
-- =====================================================================

-- ---------- 1. Masse hinter einer gezählten Palette -----------------------
create or replace view v_auftrag_palette_masse with (security_invoker = true) as
with wiegung as materialized (
  -- Eingangs-Netto der gewogenen Paletten, einmal für alle
  select vw.id,
         (vw.brutto_damals_kg
          - coalesce(vw.kisten, 0) * g.tara_kg_pro_kiste
          - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_damals_kg,
         vw.eingangsdatum
    from verdunstung_wiegung vw
    left join gebinde g on g.art = vw.gebindeart
), datum_mittel as materialized (
  select charge_nr, eingangsdatum, avg(netto_kg) as netto_mittel
    from v_palette group by charge_nr, eingangsdatum
), charge_mittel as materialized (
  select charge_nr, avg(netto_kg) as netto_mittel
    from v_palette group by charge_nr
), charge_datum as materialized (
  select charge_nr, eingangsdatum_mittel from v_charge_rueckgrat
)
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(w.netto_damals_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel) as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum,
                cd.eingangsdatum_mittel)                                        as eingangsdatum,
       case when w.netto_damals_kg is not null then 'gewogen'
            when p.netto_kg        is not null then 'palette'
            when d.netto_mittel    is not null then 'datum-mittel'
            when cm.netto_mittel   is not null then 'charge-mittel'
            else 'unbekannt' end                                                as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join wiegung w  on w.id = ap.wiegung_id
  left join v_palette p on p.id = ap.palette_id
  left join datum_mittel d on d.charge_nr = a.charge_nr and d.eingangsdatum = ap.eingangsdatum
  left join charge_mittel cm on cm.charge_nr = a.charge_nr
  left join charge_datum cd on cd.charge_nr = a.charge_nr;

-- ---------- 2. Die Kaskade ohne Funktionsaufruf je Zeile ------------------
drop view if exists v_marge_buch;
drop view if exists v_verlust_ranking;
drop view if exists v_massenbilanz;
drop view if exists v_hochrechnung;
drop view if exists v_kaskade;

create view v_kaskade with (security_invoker = true) as
with sz(szenario) as (values ('unten'), ('mittel'), ('oben')),
kurve as materialized (
  -- Einmal berechnet statt einmal je Zeile — das war der teure Teil
  select von, anteil_mono, unten, oben, n from v_schimmel_kurve where n > 0
),
koeff as (
  select b.*, sz.szenario,
         least(greatest(case sz.szenario when 'unten' then kv.unten
                                         when 'oben'  then kv.oben
                                         else kv.mittel end, 0), 0.05) as r,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(case sz.szenario when 'unten' then ka.unten
                                         when 'oben'  then ka.oben
                                         else ka.mittel end, 0), 1) as a_klein,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(case sz.szenario when 'unten' then kn.unten
                                         when 'oben'  then kn.oben
                                         else kn.mittel end, 0), 1) as a_gross,
         kn.n as gross_n, kn.basis as gross_basis
    from v_hochrechnung_basis b
    cross join sz
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
),
koeff_norm as (
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  select k.*, t.portion, t.m0, t.alter_tage,
         -- Treppenfunktion: die höchste Altersklasse, die nicht über dem Alter
         -- liegt. Der Join geht gegen die kleine CTE, nicht gegen die Kette.
         least(greatest(coalesce(
           case k.szenario when 'unten' then coalesce(s.unten, s.anteil_mono)
                           when 'oben'  then coalesce(s.oben,  s.anteil_mono)
                           else s.anteil_mono end, 0), 0), 1)          as f,
         s.n                                                           as f_n
    from koeff_norm k
    cross join lateral (values
        ('ausgelagert', k.ausgelagert_kg, coalesce(k.alter_ausgelagert, 0)),
        ('lager',       k.lager_kg,       greatest(k.alter_lager, 0))
      ) as t(portion, m0, alter_tage)
    left join lateral (
        select c.anteil_mono, c.unten, c.oben, c.n from kurve c
         where c.von <= t.alter_tage order by c.von desc limit 1
       ) s on true
   where t.m0 > 0
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))::numeric              as m1,
         (t.m0 * power(1 - t.r, t.alter_tage) * (1 - t.f))::numeric  as m2
    from teile t
)
select k.*,
       k.m0 - k.m1                                    as verdunstung_kg,
       k.m1 - k.m2                                    as schimmel_kg,
       k.m2 * k.a_klein_n                             as klein_kg,
       k.m2 * k.a_gross_n                             as nebenkanal_kg,
       k.m2 * (1 - k.a_klein_n - k.a_gross_n)         as verkaufsfaehig_kg
  from kaskade k;

create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.szenario, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg,
       s.strom, s.buch,
       s.kg::numeric(14,2)          as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       s.koeffizient::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung',      'verlust', k.verdunstung_kg, k.m0, k.r,       k.r_n,     k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'),
    ('Schimmel/Fäulnis', 'verlust', k.schimmel_kg,    k.m1, k.f,       k.f_n,
     'Schimmelkurve nach Lagerdauer',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer'),
    ('Ausschuss zu klein','verlust', k.klein_kg,      k.m2, k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze'),
    ('Nebenkanal zu gross','marge',  k.nebenkanal_kg, k.m2, k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'),
    ('Verkaufsfähig',    'bilanz',  k.verkaufsfaehig_kg, k.m2, null::numeric, null::int, null::text,
     'Rest der Kaskade')
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel);

create view v_verlust_ranking with (security_invoker = true) as
select strom, buch,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       sum(kg) filter (where szenario = 'mittel' and portion = 'ausgelagert') as kg_beobachtet,
       sum(kg) filter (where szenario = 'mittel' and portion = 'lager')       as kg_projiziert,
       min(koeff_n)                                                          as koeff_n_min
  from v_hochrechnung
 where buch = 'verlust'
 group by strom, buch
 order by 3 desc nulls last;

-- v_marge_buch fragte v_hochrechnung zweimal ab — einmal direkt und einmal in
-- einer seitlichen Unterabfrage. Jetzt einmal, in einer materialisierten CTE.
create view v_marge_buch with (security_invoker = true) as
with hr as materialized (
  select charge_nr, strom, buch, szenario, kg from v_hochrechnung
), kisten as materialized (
  select sum(h.kg * b.weg2_anteil) / 8.0 as anzahl
    from hr h
    join v_hochrechnung_basis b on b.charge_nr = h.charge_nr
   where h.strom = 'Verkaufsfähig' and h.szenario = 'mittel'
)
select 'Nebenkanal zu gross'::text as posten,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from hr where buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       (u.unten * v.anzahl)::numeric(14,2),
       (u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.anzahl))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;

create view v_massenbilanz with (security_invoker = true) as
with modell as materialized (
  select charge_nr,
         sum(m2) filter (where portion = 'ausgelagert') as modell_kg,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade where szenario = 'mittel' group by charge_nr
), csv_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (
             where exists (select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
           / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
    from v_auftrag_masse am
   where am.station in ('sortieren', 'waschen_sortieren')
     and am.eingang_netto_kg is not null
   group by am.charge_nr
), gemessen as materialized (
  select charge_nr, sum(masse_kg) as gemessen_kg from v_sortier_lauf_masse group by charge_nr
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       (m.modell_kg * q.anteil_mit_csv)::numeric(14,2)      as modell_am_band_kg,
       c.gemessen_kg                                        as csv_gemessen_kg,
       (c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)::numeric(14,2) as abweichung_kg,
       case when m.modell_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)
                  / (m.modell_kg * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       m.restbestand_kg::numeric(14,2)                      as restbestand_kg
  from v_hochrechnung_basis b
  left join modell m     on m.charge_nr = b.charge_nr
  left join csv_anteil q on q.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

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
          l.datei_zeit, l.zuordnung;

create unique index if not exists mv_sortier_lauf_masse_pk on mv_sortier_lauf_masse (lauf_id);
create index if not exists mv_sortier_lauf_masse_charge on mv_sortier_lauf_masse (charge_nr);

create or replace view v_sortier_lauf_masse with (security_invoker = true) as
select * from mv_sortier_lauf_masse;

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
          a.start_ts, a.ende_ts, a.status, a.durchsatz_kg;

create unique index if not exists mv_auftrag_masse_pk on mv_auftrag_masse (auftrag_id);
create index if not exists mv_auftrag_masse_charge on mv_auftrag_masse (charge_nr);
create index if not exists mv_auftrag_masse_station on mv_auftrag_masse (station) where eingang_netto_kg is not null;

create or replace view v_auftrag_masse with (security_invoker = true) as
select * from mv_auftrag_masse;

-- ---------- 3. Die Hochrechnung selbst ------------------------------------
-- Derselbe Rumpf wie bisher in v_kaskade — nur liest er jetzt die beiden
-- gespeicherten Ansichten von oben und wird selbst gespeichert. v_kaskade
-- steckte in drei Dashboard-Ansichten und wurde dabei dreimal gerechnet.
create materialized view if not exists mv_kaskade as
with sz(szenario) as (values ('unten'), ('mittel'), ('oben')),
kurve as materialized (
  select von, anteil_mono, unten, oben, n from v_schimmel_kurve where n > 0
),
koeff as (
  select b.*, sz.szenario,
         least(greatest(case sz.szenario when 'unten' then kv.unten
                                         when 'oben'  then kv.oben
                                         else kv.mittel end, 0), 0.05) as r,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(case sz.szenario when 'unten' then ka.unten
                                         when 'oben'  then ka.oben
                                         else ka.mittel end, 0), 1) as a_klein,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(case sz.szenario when 'unten' then kn.unten
                                         when 'oben'  then kn.oben
                                         else kn.mittel end, 0), 1) as a_gross,
         kn.n as gross_n, kn.basis as gross_basis
    from v_hochrechnung_basis b
    cross join sz
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
),
koeff_norm as (
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  select k.*, t.portion, t.m0, t.alter_tage,
         least(greatest(coalesce(
           case k.szenario when 'unten' then coalesce(s.unten, s.anteil_mono)
                           when 'oben'  then coalesce(s.oben,  s.anteil_mono)
                           else s.anteil_mono end, 0), 0), 1)          as f,
         s.n                                                           as f_n
    from koeff_norm k
    cross join lateral (values
        ('ausgelagert', k.ausgelagert_kg, coalesce(k.alter_ausgelagert, 0)),
        ('lager',       k.lager_kg,       greatest(k.alter_lager, 0))
      ) as t(portion, m0, alter_tage)
    left join lateral (
        select c.anteil_mono, c.unten, c.oben, c.n from kurve c
         where c.von <= t.alter_tage order by c.von desc limit 1
       ) s on true
   where t.m0 > 0
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))::numeric              as m1,
         (t.m0 * power(1 - t.r, t.alter_tage) * (1 - t.f))::numeric  as m2
    from teile t
)
select k.*,
       k.m0 - k.m1                                    as verdunstung_kg,
       k.m1 - k.m2                                    as schimmel_kg,
       k.m2 * k.a_klein_n                             as klein_kg,
       k.m2 * k.a_gross_n                             as nebenkanal_kg,
       k.m2 * (1 - k.a_klein_n - k.a_gross_n)         as verkaufsfaehig_kg
  from kaskade k;

create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, szenario, portion);
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);

create or replace view v_kaskade with (security_invoker = true) as
select * from mv_kaskade;

-- ---------- 4. Kaliber-Verteilung -----------------------------------------
-- Scannt ebenfalls alle Gewichtsstufen und wächst mit jeder eingelesenen CSV.
create materialized view if not exists mv_kaliber_verteilung as
select l.charge_nr, c.sorte, g.klasse, g.kaliber_idx,
       (s.kaliber_baender -> g.kaliber_idx ->> 0)::int as band_von,
       (s.kaliber_baender -> g.kaliber_idx ->> 1)::int as band_bis,
       sum(g.anzahl)                                                 as n_kuerbis,
       (sum(g.anzahl::bigint * g.gewicht_g) / 1000.0)::numeric(12,2) as masse_kg
  from sortier_gewicht g
  join sortier_lauf l on l.id = g.lauf_id
  join charge c on c.nr = l.charge_nr
  join sorte_kaliber s on s.sorte = c.sorte
 group by l.charge_nr, c.sorte, g.klasse, g.kaliber_idx, s.kaliber_baender;

create unique index if not exists mv_kaliber_pk
  on mv_kaliber_verteilung (charge_nr, klasse, coalesce(kaliber_idx, -1));

create or replace view v_kaliber_verteilung with (security_invoker = true) as
select * from mv_kaliber_verteilung;

-- ---------- Neu berechnen -------------------------------------------------
-- Reihenfolge zählt: mv_kaskade liest die beiden anderen. Würde sie zuerst
-- erneuert, rechnete sie mit den alten Zahlen.
create or replace function auswertung_aktualisieren()
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v_start timestamptz := clock_timestamp();
begin
  refresh materialized view mv_sortier_lauf_masse;
  refresh materialized view mv_auftrag_masse;
  refresh materialized view mv_kaskade;
  refresh materialized view mv_kaliber_verteilung;

  update auswertung_stand
     set berechnet_ts = now(),
         dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
   where id = 1;

  return now();
end $$;

comment on function auswertung_aktualisieren is
  'Rechnet die Auswertung neu. Dauert je nach Datenmenge einige Sekunden — '
  'währenddessen sind die drei gespeicherten Ansichten kurz gesperrt.';

grant execute on function auswertung_aktualisieren() to authenticated;
grant select on mv_sortier_lauf_masse, mv_auftrag_masse, mv_kaskade,
                mv_kaliber_verteilung to authenticated;

-- Beim Einspielen einmal füllen, damit das Dashboard sofort etwas zeigt.
select auswertung_aktualisieren();


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

-- ---------- Das angepasste Modell -----------------------------------------
-- mv_kaskade hängt daran und muss vorher weichen; es wird unten neu gebaut.
drop materialized view if exists mv_kaskade cascade;
drop view if exists v_schimmel_kurve_anzeige;
drop view if exists v_schimmel_modell;

create view v_schimmel_modell with (security_invoker = true) as
with beob as (
  -- Einzelbeobachtungen statt Altersklassen: mehr Information, und die
  -- Klassengrenzen verfälschen den Verlauf nicht.
  select b.charge_nr,
         b.lagertage::numeric                   as t,
         b.anteil::numeric                      as f,
         b.basis_jetzt_kg::numeric              as gewicht
    from v_schimmel_beobachtung b
   where b.plausibel and b.anteil > 0 and b.anteil < 1 and b.lagertage > 0
), punkte as (
  select charge_nr, ln(t) as x, ln(-ln(1 - f)) as y, gewicht as w, t from beob
), summen as (
  select count(*)::int as n, count(distinct charge_nr)::int as c_chargen,
         min(t) as t_min, max(t) as t_max,
         sum(w) as sw, sum(w * x) as swx, sum(w * y) as swy,
         sum(w * x * x) as swxx, sum(w * x * y) as swxy
    from punkte
), fit as (
  select s.*,
         case when s.sw * s.swxx - s.swx * s.swx <> 0
              then (s.sw * s.swxy - s.swx * s.swy)
                   / (s.sw * s.swxx - s.swx * s.swx) end              as k,
         s.swx / nullif(s.sw, 0)                                      as x_mittel
    from summen s
), mit_achse as (
  select f.*, case when f.k is not null then (f.swy - f.k * f.swx) / f.sw end as ln_lambda
    from fit f
), rest as (
  select m.*,
         -- Zentriert um x_mittel sind Achse und Steigung getrennt schätzbar.
         (select sum(p.w * power(p.x - m.x_mittel, 2)) from punkte p)              as sxx,
         (select sum(p.w * power(p.y - (m.ln_lambda + m.k * p.x), 2)) from punkte p) as sse,
         (select sum(p.w * exp(p.y - (m.ln_lambda + m.k * p.x))) / nullif(sum(p.w), 0)
            from punkte p)                                                        as smearing
    from mit_achse m
), gruppen as (
  -- Je Charge die gewichteten Residuen aufsummieren; die Streuung dieser
  -- Chargensummen ist der Fehler, nicht die der Einzelpunkte.
  select r.*, g.saa, g.skk, g.sak
    from rest r
    cross join lateral (
      select sum(power(c.ga, 2)) as saa, sum(power(c.gk, 2)) as skk,
             sum(c.ga * c.gk)    as sak
        from (select p.charge_nr,
                     sum(p.w * (p.y - (r.ln_lambda + r.k * p.x)))                      as ga,
                     sum(p.w * (p.x - r.x_mittel) * (p.y - (r.ln_lambda + r.k * p.x))) as gk
                from punkte p group by p.charge_nr) c
    ) g
)
select n, c_chargen, t_min, t_max, k, ln_lambda, exp(ln_lambda) as lambda,
       x_mittel, sxx, smearing,
       -- Das ist, was tatsächlich gerechnet wird: Fit plus Smearing
       ln_lambda + ln(greatest(smearing, 0.01))                      as ln_lambda_korrigiert,
       case when n > 2 then sse / (n - 2) * n / nullif(sw, 0) end    as sigma2,
       -- Sandwich-Varianzen, mit der üblichen Korrektur für wenige Gruppen
       case when c_chargen > 1
            then saa / power(sw, 2) * c_chargen::numeric / (c_chargen - 1) end  as var_achse,
       case when c_chargen > 1 and sxx <> 0
            then skk / power(sxx, 2) * c_chargen::numeric / (c_chargen - 1) end as var_k,
       case when c_chargen > 1 and sxx <> 0
            then sak / (sw * sxx) * c_chargen::numeric / (c_chargen - 1) end    as kov_achse_k,
       t_quantil_95(c_chargen - 1)                                              as t_faktor,
       -- Brauchbar heisst auch: genug *unabhängige* Gruppen. Mit ein oder
       -- zwei Chargen lässt sich der Fehler nicht schätzen, und ein Modell
       -- ohne belastbare Fehlerangabe ist hier schlimmer als die Treppe.
       (n >= 3 and c_chargen >= 3 and k is not null and k > 0
        and t_max > t_min * 1.5)                                                as brauchbar
  from gruppen;

comment on view v_schimmel_modell is
  'Verderbsmodell F(t) = 1 − exp(−λ·S·t^k), S = Duan-Smearing. Der Fehler ist '
  'chargen-robust: Messungen aus derselben Charge sind keine unabhängigen '
  'Beobachtungen. brauchbar = false heisst: zu wenige Chargen oder zu '
  'ähnliche Lagerdauern — es gilt die Treppenfunktion.';

-- ---------- Schimmelanteil bei gegebener Lagerdauer -----------------------
-- Für Anzeige und Einzelabfragen. Die Kaskade rechnet die Formel inline,
-- weil ein Funktionsaufruf je Zeile 2 441 ms gekostet hat (siehe 0015).
create or replace function schimmelanteil(p_lagertage numeric, p_szenario text default 'mittel')
returns numeric language sql stable as $$
  with m as (select * from v_schimmel_modell),
  u as (select m.*, ln(greatest(p_lagertage, 1)) - m.x_mittel as u from m)
  select coalesce(
    (select least(greatest(1 - exp(-exp(least(greatest(
       u.ln_lambda_korrigiert + u.k * ln(greatest(p_lagertage, 1))
       + case p_szenario when 'unten' then -1 when 'oben' then 1 else 0 end
         * u.t_faktor * sqrt(greatest(
             u.var_achse + power(u.u, 2) * u.var_k + 2 * u.u * u.kov_achse_k, 0))
       , -40), 3))), 0), 1)
       from u where u.brauchbar and u.var_achse is not null),
    -- Rückfall: die Treppenfunktion, solange das Modell nicht trägt
    (select least(greatest(coalesce(
       case p_szenario when 'unten' then coalesce(k.unten, k.anteil_mono)
                       when 'oben'  then coalesce(k.oben,  k.anteil_mono)
                       else k.anteil_mono end, 0), 0), 1)
       from v_schimmel_kurve k
      where k.von <= p_lagertage and k.n > 0
      order by k.von desc limit 1),
    0)::numeric;
$$;

-- ---------- Die Kaskade, jetzt mit dem Modell -----------------------------
-- Rumpf wie in 0016; neu ist allein, wie f zustande kommt: das Modell wird
-- einmal als CTE materialisiert und die Formel inline gerechnet — eine
-- ln/exp-Rechnung je Zeile statt einer Abfrage je Zeile.
create materialized view mv_kaskade as
with sz(szenario) as (values ('unten'), ('mittel'), ('oben')),
modell as materialized (
  select * from v_schimmel_modell
),
kurve as materialized (
  -- Rückfall für die Zeit, in der noch zu wenig gemessen wurde, um ein
  -- Modell anzupassen — am Saisonanfang ist das der Normalfall.
  select von, anteil_mono, unten, oben, n from v_schimmel_kurve where n > 0
),
koeff as (
  select b.*, sz.szenario,
         least(greatest(case sz.szenario when 'unten' then kv.unten
                                         when 'oben'  then kv.oben
                                         else kv.mittel end, 0), 0.05) as r,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(case sz.szenario when 'unten' then ka.unten
                                         when 'oben'  then ka.oben
                                         else ka.mittel end, 0), 1) as a_klein,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(case sz.szenario when 'unten' then kn.unten
                                         when 'oben'  then kn.oben
                                         else kn.mittel end, 0), 1) as a_gross,
         kn.n as gross_n, kn.basis as gross_basis
    from v_hochrechnung_basis b
    cross join sz
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
),
koeff_norm as (
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  select k.*, t.portion, t.m0, t.alter_tage,
         case when m.brauchbar and m.var_achse is not null then
           least(greatest(1 - exp(-exp(least(greatest(
             m.ln_lambda_korrigiert + m.k * ln(greatest(t.alter_tage, 1))
             + case k.szenario when 'unten' then -1 when 'oben' then 1 else 0 end
               * m.t_faktor * e.se
             , -40), 3))), 0), 1)
         else
           least(greatest(coalesce(
             case k.szenario when 'unten' then coalesce(s.unten, s.anteil_mono)
                             when 'oben'  then coalesce(s.oben,  s.anteil_mono)
                             else s.anteil_mono end, 0), 0), 1)
         end                                                          as f,
         case when m.brauchbar and m.var_achse is not null then m.c_chargen else s.n end as f_n,
         -- Wird hier über den gemessenen Bereich hinaus gerechnet? Das gehört
         -- ins Dashboard, nicht in eine Fussnote.
         (m.brauchbar and m.var_achse is not null and t.alter_tage > m.t_max) as f_extrapoliert
    from koeff_norm k
    cross join modell m
    cross join lateral (values
        ('ausgelagert', k.ausgelagert_kg, coalesce(k.alter_ausgelagert, 0)),
        ('lager',       k.lager_kg,       greatest(k.alter_lager, 0))
      ) as t(portion, m0, alter_tage)
    -- Vorhersagefehler an dieser Lagerdauer: wächst mit dem Abstand vom
    -- Schwerpunkt der Messungen. Beim Lagerbestand, der länger liegt als
    -- alles je Verarbeitete, wird der Bereich dadurch von selbst breiter —
    -- statt eine Sicherheit vorzutäuschen, die es nicht gibt.
    cross join lateral (
      select sqrt(greatest(coalesce(m.var_achse, 0)
             + power(ln(greatest(t.alter_tage, 1)) - coalesce(m.x_mittel, 0), 2)
               * coalesce(m.var_k, 0)
             + 2 * (ln(greatest(t.alter_tage, 1)) - coalesce(m.x_mittel, 0))
               * coalesce(m.kov_achse_k, 0), 0)) as se) e
    left join lateral (
        select c.anteil_mono, c.unten, c.oben, c.n from kurve c
         where c.von <= t.alter_tage order by c.von desc limit 1
       ) s on true
   where t.m0 > 0
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))::numeric              as m1,
         (t.m0 * power(1 - t.r, t.alter_tage) * (1 - t.f))::numeric  as m2
    from teile t
)
select k.*,
       k.m0 - k.m1                                    as verdunstung_kg,
       k.m1 - k.m2                                    as schimmel_kg,
       k.m2 * k.a_klein_n                             as klein_kg,
       k.m2 * k.a_gross_n                             as nebenkanal_kg,
       k.m2 * (1 - k.a_klein_n - k.a_gross_n)         as verkaufsfaehig_kg
  from kaskade k;

create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, szenario, portion);
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);

create or replace view v_kaskade with (security_invoker = true) as
select * from mv_kaskade;

-- ---------- Die abhängigen Ansichten wieder aufbauen ----------------------
-- Sie hingen an v_kaskade und fielen mit dem cascade-Drop mit. Rumpf wie in
-- 0015; neu ist allein, dass durchgereicht wird, ob hochgerechnet wurde.
create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.szenario, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg, k.f_extrapoliert,
       s.strom, s.buch,
       s.kg::numeric(14,2)          as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       s.koeffizient::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung',      'verlust', k.verdunstung_kg, k.m0, k.r,       k.r_n,     k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'),
    ('Schimmel/Fäulnis', 'verlust', k.schimmel_kg,    k.m1, k.f,       k.f_n,
     'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer'),
    ('Ausschuss zu klein','verlust', k.klein_kg,      k.m2, k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze'),
    ('Nebenkanal zu gross','marge',  k.nebenkanal_kg, k.m2, k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'),
    ('Verkaufsfähig',    'bilanz',  k.verkaufsfaehig_kg, k.m2, null::numeric, null::int, null::text,
     'Rest der Kaskade')
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel);

create view v_verlust_ranking with (security_invoker = true) as
select strom, buch,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       sum(kg) filter (where szenario = 'mittel' and portion = 'ausgelagert') as kg_beobachtet,
       sum(kg) filter (where szenario = 'mittel' and portion = 'lager')       as kg_projiziert,
       -- Wie viel des Ergebnisses steht jenseits der längsten gemessenen
       -- Lagerdauer? Eine Zahl, die zu 80 % auf Hochrechnung beruht, darf
       -- nicht aussehen wie eine gemessene.
       sum(kg) filter (where szenario = 'mittel' and f_extrapoliert)          as kg_extrapoliert,
       min(koeff_n)                                                          as koeff_n_min
  from v_hochrechnung
 where buch = 'verlust'
 group by strom, buch
 order by 3 desc nulls last;

create view v_marge_buch with (security_invoker = true) as
with hr as materialized (
  select charge_nr, strom, buch, szenario, kg from v_hochrechnung
), kisten as materialized (
  select sum(h.kg * b.weg2_anteil) / 8.0 as anzahl
    from hr h
    join v_hochrechnung_basis b on b.charge_nr = h.charge_nr
   where h.strom = 'Verkaufsfähig' and h.szenario = 'mittel'
)
select 'Nebenkanal zu gross'::text as posten,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from hr where buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       (u.unten * v.anzahl)::numeric(14,2),
       (u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.anzahl))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;

create view v_massenbilanz with (security_invoker = true) as
with modell as materialized (
  select charge_nr,
         sum(m2) filter (where portion = 'ausgelagert') as modell_kg,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade where szenario = 'mittel' group by charge_nr
), csv_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (
             where exists (select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
           / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
    from v_auftrag_masse am
   where am.station in ('sortieren', 'waschen_sortieren')
     and am.eingang_netto_kg is not null
   group by am.charge_nr
), gemessen as materialized (
  select charge_nr, sum(masse_kg) as gemessen_kg from v_sortier_lauf_masse group by charge_nr
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       (m.modell_kg * q.anteil_mit_csv)::numeric(14,2)      as modell_am_band_kg,
       c.gemessen_kg                                        as csv_gemessen_kg,
       (c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)::numeric(14,2) as abweichung_kg,
       case when m.modell_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)
                  / (m.modell_kg * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       m.restbestand_kg::numeric(14,2)                      as restbestand_kg
  from v_hochrechnung_basis b
  left join modell m     on m.charge_nr = b.charge_nr
  left join csv_anteil q on q.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

-- ---------- Anzeige: was das Modell tut und woher es kommt ----------------
drop view if exists v_schimmel_kurve_anzeige;
create view v_schimmel_kurve_anzeige with (security_invoker = true) as
select k.von, k.bis,
       case when k.bis > 9999 then k.von || '+ Tage'
            else k.von || '–' || k.bis || ' Tage' end       as altersklasse,
       k.n                                                  as messungen,
       (k.anteil)::numeric(10,4)                            as gemessen,
       -- Was tatsächlich gerechnet wird: das Modell an der Klassenmitte
       (schimmelanteil((k.von + least(k.bis, k.von + 60)) / 2.0))::numeric(10,4) as verwendet,
       (schimmelanteil((k.von + least(k.bis, k.von + 60)) / 2.0, 'unten'))::numeric(10,4) as unten,
       (schimmelanteil((k.von + least(k.bis, k.von + 60)) / 2.0, 'oben'))::numeric(10,4)  as oben,
       case when not (select brauchbar from v_schimmel_modell)
                 then 'Modell noch nicht anpassbar — es gilt die Treppenfunktion'
            when k.von > (select t_max from v_schimmel_modell)
                 then 'über die längste gemessene Lagerdauer hinaus — hochgerechnet, '
                      || 'daher der breitere Bereich'
            when k.n = 0 then 'keine eigene Messung — aus dem Verlauf interpoliert'
            else 'durch Messungen dieser Altersklasse gestützt' end as erlaeuterung
  from v_schimmel_kurve k
 order by k.von;

grant execute on function t_quantil_95(int) to authenticated;
grant select on v_schimmel_modell, v_schimmel_kurve_anzeige, v_kaskade,
               v_hochrechnung, v_verlust_ranking, v_marge_buch,
               v_massenbilanz to authenticated;


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

create or replace view v_koeff_roh_kaliber with (security_invoker = true) as
-- Massenanteil je Sortierlauf bzw. Handmessung, gewichtet mit der sortierten
-- Masse. Beide Kaliber-Koeffizienten stammen aus derselben Beobachtung.
select 'ausschuss'::text as art, b.sorte, b.charge_nr,
       b.klein_kg / b.basis_kg as anteil, b.basis_kg as gewicht
  from v_ausschuss_beobachtung b
 where b.plausibel and b.basis_kg > 0 and b.klein_kg is not null
union all
select 'nebenkanal', b.sorte, b.charge_nr,
       b.gross_kg / b.basis_kg, b.basis_kg
  from v_ausschuss_beobachtung b
 where b.plausibel and b.basis_kg > 0 and b.gross_kg is not null;

comment on view v_koeff_roh_kaliber is
  'Koeffizienten-Rohwerte in einheitlicher Form: Anteil, die Masse, die er '
  'vertritt, und die Charge, aus der er stammt.';

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

comment on view v_koeff_kaliber_geschaetzt is
  'Massegewichteter Anteil je Sorte, chargen-robust gefehlert und per '
  'empirischem Bayes zum Gesamtwert gezogen. b = 1 heisst: die Sorte trägt '
  'sich selbst, b = 0: es gilt der Gesamtwert.';

-- ---------- Die drei benannten Koeffizienten ------------------------------
-- Gleiche Spalten wie bisher, damit Kaskade und Dashboard unverändert lesen.
create or replace view v_koeff_verdunstung with (security_invoker = true) as
select sk.sorte,
       coalesce(k.mittel, 0)::numeric                                  as mittel,
       -- Ist die Varianz 0, gab es nichts zu streuen (eine einzige Charge).
       -- Dann steht der Punktwert dreimal da — das ist ehrlicher als ein
       -- erfundener Bereich, und basis/n sagen, warum.
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                         as unten,
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
             else k.mittel + k.t * sqrt(k.varianz)
        end)::double precision                                         as oben,
       coalesce(k.n, 0)                                                as n,
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

create or replace view v_koeff_ausschuss with (security_invoker = true) as
select sk.sorte,
       coalesce(k.mittel, 0)::numeric                                       as mittel,
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                              as unten,
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
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
       coalesce(k.mittel, 0)::numeric                                       as mittel,
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                              as unten,
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
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

grant select on v_koeff_roh_verdunstung, v_koeff_roh_kaliber,
               v_koeff_verdunstung_geschaetzt, v_koeff_kaliber_geschaetzt to authenticated;

-- ---------- Unsicherheit aller Koeffizienten an einer Stelle --------------
-- Wird nur von der Fehlerfortpflanzung gelesen, nie von den Koeffizienten
-- selbst — sonst wäre der Zyklus von oben wieder da.
create or replace view v_koeff_unsicherheit with (security_invoker = true) as
select art, sorte, b, varianz_eigen, gewicht_gesamt, varianz_gesamt, df
  from v_koeff_verdunstung_geschaetzt
union all
select art, sorte, b, varianz_eigen, gewicht_gesamt, varianz_gesamt, df
  from v_koeff_kaliber_geschaetzt;

comment on view v_koeff_unsicherheit is
  'Je Koeffizient und Sorte: der eigene Fehleranteil, das Gewicht auf dem '
  'gemeinsamen Gesamtwert und dessen Fehler. Getrennt, weil der Gesamtwert '
  'für alle Sorten derselbe ist und seine Fehler sich nicht wegmitteln.';

grant select on v_koeff_unsicherheit to authenticated;


-- =====================================================================
-- aus 0019_fehlerfortpflanzung.sql
-- =====================================================================

-- =====================================================================
-- 0019 — Ein Bereich, der wirklich ein Bereich ist
--
-- Bisher wurden drei Szenarien gerechnet: „unten" setzte *alle* Koeffizienten
-- gleichzeitig an ihre untere Grenze, „oben" alle an die obere. Das
-- unterstellt, dass sich alle Messfehler im Gleichtakt bewegen — und für
-- Ströme weiter unten in der Kaskade stimmt nicht einmal die Richtung.
--
-- Der Harness zeigt es unmissverständlich (25 Saisons, 50 % im Lager):
--
--   Ausschuss zu klein   Bereichsbreite −2.3 %   Überdeckung 0 %
--
-- Eine *negative* Breite: kg_unten lag über kg_oben. Der Grund ist zwingend.
-- Weniger Verdunstung und weniger Schimmel heisst mehr Masse, die überhaupt
-- bis zum Sortierband kommt. Im Szenario „unten" sind r und f klein, also ist
-- die Masse gross — und der Ausschuss daraus grösser als im Szenario „oben".
-- Die Grenzen tauschen die Plätze. Das war nie ein Konfidenzintervall; es sah
-- nur aus wie eins.
--
-- ---------- Statt dessen: Fehlerfortpflanzung ----------------------------
-- Für jeden Strom wird ausgerechnet, wie stark er auf jeden Koeffizienten
-- reagiert (die Ableitung), und die Fehler werden entsprechend ihrer
-- tatsächlichen Abhängigkeit zusammengesetzt:
--
--   m1 = m0·(1−r)^t        D := ∂m1/∂r = −m0·t·(1−r)^(t−1)
--   m2 = m1·(1−f)
--
--   Verdunstung   V = m0−m1     ∂V/∂r = −D
--   Schimmel      S = m1·f      ∂S/∂r = D·f          ∂S/∂f = m1
--   Ausschuss     K = m2·a      ∂K/∂r = D·(1−f)·a    ∂K/∂f = −m1·a   ∂K/∂a = m2
--
-- Damit wandert der Fehler von r automatisch in Schimmel und Ausschuss
-- weiter, statt dort als unabhängig behandelt zu werden.
--
-- Zusammengesetzt wird nach der wahren Korrelationsstruktur:
--
--   * Der Schimmelkoeffizient stammt aus *einem* Modell mit zwei Parametern
--     (Achse A, Steigung k). Über alle Chargen hinweg ist es derselbe Fehler,
--     nicht 42 unabhängige. Also werden erst die Ableitungen summiert und
--     dann einmal mit der 2×2-Kovarianz des Modells multipliziert.
--   * r und die Kaliber-Anteile sind je Sorte geschätzt, aber alle Sorten
--     hängen über die Bündelung am selben Gesamtwert. Der eigene Anteil geht
--     quadratisch ein (unabhängig), der gemeinsame linear (identisch).
--
-- Das Ergebnis ist ein Bereich, dessen Grenzen in der richtigen Reihenfolge
-- stehen und der aussagt, was er behauptet.
--
-- Nebeneffekt: mv_kaskade hat nur noch ein Drittel der Zeilen, weil die drei
-- Szenarien wegfallen. Das Neuberechnen wird entsprechend schneller.
-- =====================================================================

drop materialized view if exists mv_kaskade cascade;

create materialized view mv_kaskade as
with modell as materialized (
  select * from v_schimmel_modell
),
kurve as materialized (
  select von, anteil_mono, n from v_schimmel_kurve where n > 0
),
koeff as (
  select b.*,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05) as r,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(coalesce(ka.mittel, 0), 0), 1)    as a_klein,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(coalesce(kn.mittel, 0), 0), 1)    as a_gross,
         kn.n as gross_n, kn.basis as gross_basis
    from v_hochrechnung_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
),
koeff_norm as (
  -- Zusammen dürfen die beiden Kaliber-Anteile nicht über 1 liegen. Der Fall
  -- tritt nur bei widersprüchlichen Messungen auf; die Ableitungen unten
  -- rechnen mit dem unnormierten Koeffizienten, was dann geringfügig zu
  -- gross ist — auf der sicheren Seite.
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  select k.*, t.portion, t.m0, t.alter_tage,
         -- η = ln λ + k·ln t, zentriert um den Schwerpunkt der Messungen
         ln(greatest(t.alter_tage, 1)) - coalesce(m.x_mittel, 0)        as u,
         case when m.brauchbar then
           m.ln_lambda_korrigiert + m.k * ln(greatest(t.alter_tage, 1))
         end                                                            as eta,
         m.brauchbar                                                    as modell_gilt,
         (m.brauchbar and t.alter_tage > m.t_max)                       as f_extrapoliert,
         case when m.brauchbar then m.c_chargen else s.n end            as f_n,
         s.anteil_mono                                                  as f_treppe
    from koeff_norm k
    cross join modell m
    cross join lateral (values
        ('ausgelagert', k.ausgelagert_kg, coalesce(k.alter_ausgelagert, 0)),
        ('lager',       k.lager_kg,       greatest(k.alter_lager, 0))
      ) as t(portion, m0, alter_tage)
    left join lateral (
        select c.anteil_mono, c.n from kurve c
         where c.von <= t.alter_tage order by c.von desc limit 1
       ) s on true
   where t.m0 > 0
),
mit_f as (
  select t.*,
         case when t.modell_gilt
              then least(greatest(1 - exp(-exp(least(greatest(t.eta, -40), 3))), 0), 1)
              else least(greatest(coalesce(t.f_treppe, 0), 0), 1) end   as f
    from teile t
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))                          as m1,
         -- ∂m1/∂r, negativ: mehr Verdunstungsrate → weniger Masse
         (-t.m0 * t.alter_tage * power(1 - t.r, greatest(t.alter_tage - 1, 0))) as d_m1_r,
         -- ∂f/∂η = (1−f)·e^η. Ohne Modell ist die Treppe eine Konstante,
         -- also keine Ableitung — dann steht der Fehler auf 0 und n sagt,
         -- dass es keine Aussage ist.
         case when t.modell_gilt
              then (1 - t.f) * exp(least(greatest(t.eta, -40), 3))
              else 0 end                                                as d_f_eta
    from mit_f t
)
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage, k.eingang_kg,
       k.m0, k.m1, (k.m1 * (1 - k.f)) as m2,
       k.r, k.f, k.a_klein_n, k.a_gross_n,
       k.u, k.d_m1_r, k.d_f_eta, k.modell_gilt, k.f_extrapoliert,
       k.r_n, k.r_basis, k.klein_n, k.klein_basis, k.gross_n, k.gross_basis, k.f_n,
       (k.m0 - k.m1)                                          as verdunstung_kg,
       (k.m1 * k.f)                                           as schimmel_kg,
       (k.m1 * (1 - k.f) * k.a_klein_n)                       as klein_kg,
       (k.m1 * (1 - k.f) * k.a_gross_n)                       as nebenkanal_kg,
       (k.m1 * (1 - k.f) * (1 - k.a_klein_n - k.a_gross_n))   as verkaufsfaehig_kg
  from kaskade k;

create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, portion);
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);

create or replace view v_kaskade with (security_invoker = true) as
select * from mv_kaskade;

-- ---------- Die Ströme mit ihren Ableitungen ------------------------------
create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg, k.f_extrapoliert, k.u,
       s.strom, s.buch,
       s.kg::numeric(14,2)          as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       s.koeffizient::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel,
       -- Empfindlichkeit dieses Stroms gegenüber jedem Koeffizienten
       s.d_r                        as d_r,
       s.d_f * k.d_f_eta            as d_eta,
       s.d_a                        as d_a,
       s.koeff_art                  as koeff_art
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung', 'verlust', k.m0 - k.m1, k.m0, k.r, k.r_n, k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen',
     -k.d_m1_r, 0::numeric, 0::numeric, null::text),
    ('Schimmel/Fäulnis', 'verlust', k.m1 * k.f, k.m1, k.f, k.f_n,
     'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer',
     k.d_m1_r * k.f, k.m1, 0::numeric, null::text),
    ('Ausschuss zu klein', 'verlust', k.m1 * (1 - k.f) * k.a_klein_n, k.m2,
     k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze',
     k.d_m1_r * (1 - k.f) * k.a_klein_n, -k.m1 * k.a_klein_n, k.m2, 'ausschuss'),
    ('Nebenkanal zu gross', 'marge', k.m1 * (1 - k.f) * k.a_gross_n, k.m2,
     k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal',
     k.d_m1_r * (1 - k.f) * k.a_gross_n, -k.m1 * k.a_gross_n, k.m2, 'nebenkanal'),
    ('Verkaufsfähig', 'bilanz', k.verkaufsfaehig_kg, k.m2, null::numeric, null::int,
     null::text, 'Rest der Kaskade', 0::numeric, 0::numeric, 0::numeric, null::text)
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel,
         d_r, d_f, d_a, koeff_art);

-- ---------- Die Zusammenfassung mit fortgepflanztem Fehler ----------------
create view v_verlust_ranking with (security_invoker = true) as
with zeilen as materialized (
  select * from v_hochrechnung where buch in ('verlust', 'marge')
),
-- Je Strom und Sorte die Ableitungen aufsummieren. Innerhalb einer Sorte ist
-- es derselbe geschätzte Koeffizient, die Ableitungen addieren sich also.
je_sorte as (
  select z.strom, z.buch, z.sorte, max(z.koeff_art) as koeff_art,
         sum(z.d_r) as g_r, sum(z.d_a) as g_a
    from zeilen z group by z.strom, z.buch, z.sorte
),
-- Der Schimmelkoeffizient ist *ein* Modell für alle Sorten und Chargen.
je_strom_modell as (
  select z.strom, z.buch,
         sum(z.d_eta)       as g_achse,
         sum(z.d_eta * z.u) as g_steigung
    from zeilen z group by z.strom, z.buch
),
varianz_r as (
  -- Eigener Anteil quadratisch (unabhängig je Sorte), gemeinsamer Anteil
  -- linear (für alle Sorten derselbe Gesamtwert).
  select s.strom, s.buch,
         sum(power(s.g_r, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_r * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = 'verdunstung' and u.sorte is not distinct from s.sorte
   group by s.strom, s.buch
),
varianz_a as (
  select s.strom, s.buch,
         sum(power(s.g_a, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_a * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = s.koeff_art and u.sorte is not distinct from s.sorte
   where s.koeff_art is not null
   group by s.strom, s.buch
),
varianz_f as (
  -- Quadratische Form mit der 2×2-Kovarianz des Verderbsmodells
  select m.strom, m.buch,
         power(m.g_achse, 2) * coalesce(sm.var_achse, 0)
         + 2 * m.g_achse * m.g_steigung * coalesce(sm.kov_achse_k, 0)
         + power(m.g_steigung, 2) * coalesce(sm.var_k, 0)       as varianz,
         coalesce(sm.c_chargen - 1, 1)                          as df
    from je_strom_modell m cross join v_schimmel_modell sm
),
summe as (
  select z.strom, z.buch,
         sum(z.kg)                                                as kg,
         sum(z.kg) filter (where z.portion = 'ausgelagert')       as kg_beobachtet,
         sum(z.kg) filter (where z.portion = 'lager')             as kg_projiziert,
         sum(z.kg) filter (where z.f_extrapoliert)                as kg_extrapoliert,
         min(z.koeff_n)                                           as koeff_n_min
    from zeilen z group by z.strom, z.buch
)
select s.strom, s.buch, s.kg,
       greatest(s.kg - g.t * g.streuung, 0)::numeric(14,2)   as kg_unten,
       (s.kg + g.t * g.streuung)::numeric(14,2)              as kg_oben,
       s.kg_beobachtet, s.kg_projiziert, s.kg_extrapoliert, s.koeff_n_min,
       g.streuung::numeric(14,2)                             as streuung_kg,
       g.df                                                  as df
  from summe s
  left join varianz_r vr on vr.strom = s.strom and vr.buch = s.buch
  left join varianz_a va on va.strom = s.strom and va.buch = s.buch
  left join varianz_f vf on vf.strom = s.strom and vf.buch = s.buch
  cross join lateral (
    select sqrt(greatest(coalesce(vr.varianz, 0) + coalesce(va.varianz, 0)
                         + coalesce(vf.varianz, 0), 0))       as streuung,
           least(coalesce(vr.df, 999), coalesce(va.df, 999),
                 coalesce(vf.df, 999))                        as df
  ) g0
  cross join lateral (select g0.streuung, g0.df, t_quantil_95(g0.df) as t) g
 order by s.kg desc nulls last;

comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall: die '
  'Empfindlichkeit jedes Stroms gegenüber jedem Koeffizienten mal dessen '
  'Fehler, zusammengesetzt nach der tatsächlichen Korrelation. Nicht drei '
  'Szenarien — die standen bei nachgelagerten Strömen in der falschen '
  'Reihenfolge.';

-- ---------- Marge-Buch ----------------------------------------------------
create view v_marge_buch with (security_invoker = true) as
with kisten as materialized (
  select sum(k.verkaufsfaehig_kg * b.weg2_anteil) / 8.0 as anzahl
    from v_kaskade k join v_hochrechnung_basis b on b.charge_nr = k.charge_nr
)
select r.strom as posten, r.kg, r.kg_unten::numeric as kg_unten,
       r.kg_oben::numeric as kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from v_verlust_ranking r where r.buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       (u.unten * v.anzahl)::numeric(14,2),
       (u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.anzahl))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;

-- ---------- Massenbilanz --------------------------------------------------
create view v_massenbilanz with (security_invoker = true) as
with modell as materialized (
  select charge_nr,
         sum(m2) filter (where portion = 'ausgelagert') as modell_kg,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade group by charge_nr
), csv_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (
             where exists (select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
           / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
    from v_auftrag_masse am
   where am.station in ('sortieren', 'waschen_sortieren')
     and am.eingang_netto_kg is not null
   group by am.charge_nr
), gemessen as materialized (
  select charge_nr, sum(masse_kg) as gemessen_kg from v_sortier_lauf_masse group by charge_nr
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       (m.modell_kg * q.anteil_mit_csv)::numeric(14,2)      as modell_am_band_kg,
       c.gemessen_kg                                        as csv_gemessen_kg,
       (c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)::numeric(14,2) as abweichung_kg,
       case when m.modell_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)
                  / (m.modell_kg * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       m.restbestand_kg::numeric(14,2)                      as restbestand_kg
  from v_hochrechnung_basis b
  left join modell m     on m.charge_nr = b.charge_nr
  left join csv_anteil q on q.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

grant select on v_kaskade, v_hochrechnung, v_verlust_ranking,
               v_marge_buch, v_massenbilanz to authenticated;


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

-- ---------- Alle Schimmelpunkte, egal woher --------------------------------
create or replace view v_schimmel_punkte with (security_invoker = true) as
-- Aus der Verarbeitung: Summe je Arbeit, bezogen auf die Masse nach Verdunstung
select b.charge_nr, b.sorte, b.schlag, b.lagertage, b.schimmel_kg,
       b.basis_jetzt_kg, b.anteil, b.plausibel,
       'verarbeitung'::text as quelle, b.auftrag_id
  from v_schimmel_beobachtung b
union all
-- Aus dem Lager: eine gewogene Palette, bei der jemand nachgesehen hat
select w.charge_nr, w.sorte, w.schlag, w.lagertage,
       v.faul_kg, w.netto_jetzt_kg,
       v.faul_kg / nullif(w.netto_jetzt_kg, 0),
       anteil_plausibel(v.faul_kg / nullif(w.netto_jetzt_kg, 0)),
       'lager', null::bigint
  from v_verdunstung_messung w
  join verdunstung_wiegung v on v.id = w.id
 where v.faul_kg is not null and v.gemessen
   and w.netto_jetzt_kg > 0 and w.lagertage > 0;

comment on view v_schimmel_punkte is
  'Alle Schimmelbeobachtungen. quelle = lager heisst: die Palette wurde nicht '
  'danach ausgewählt, wie sie aussah — nur diese Punkte sind frei von der '
  'Selektionsverzerrung der Verarbeitungsreihenfolge.';

-- ---------- Modell und Treppe lesen jetzt beide Quellen -------------------
create or replace view v_schimmel_modell with (security_invoker = true) as
with beob as (
  select b.charge_nr,
         b.lagertage::numeric                   as t,
         b.anteil::numeric                      as f,
         b.basis_jetzt_kg::numeric              as gewicht
    from v_schimmel_punkte b
   where b.plausibel and b.anteil > 0 and b.anteil < 1 and b.lagertage > 0
), punkte as (
  select charge_nr, ln(t) as x, ln(-ln(1 - f)) as y, gewicht as w, t from beob
), summen as (
  select count(*)::int as n, count(distinct charge_nr)::int as c_chargen,
         min(t) as t_min, max(t) as t_max,
         sum(w) as sw, sum(w * x) as swx, sum(w * y) as swy,
         sum(w * x * x) as swxx, sum(w * x * y) as swxy
    from punkte
), fit as (
  select s.*,
         case when s.sw * s.swxx - s.swx * s.swx <> 0
              then (s.sw * s.swxy - s.swx * s.swy)
                   / (s.sw * s.swxx - s.swx * s.swx) end              as k,
         s.swx / nullif(s.sw, 0)                                      as x_mittel
    from summen s
), mit_achse as (
  select f.*, case when f.k is not null then (f.swy - f.k * f.swx) / f.sw end as ln_lambda
    from fit f
), rest as (
  select m.*,
         (select sum(p.w * power(p.x - m.x_mittel, 2)) from punkte p)              as sxx,
         (select sum(p.w * power(p.y - (m.ln_lambda + m.k * p.x), 2)) from punkte p) as sse,
         (select sum(p.w * exp(p.y - (m.ln_lambda + m.k * p.x))) / nullif(sum(p.w), 0)
            from punkte p)                                                        as smearing
    from mit_achse m
), gruppen as (
  select r.*, g.saa, g.skk, g.sak
    from rest r
    cross join lateral (
      select sum(power(c.ga, 2)) as saa, sum(power(c.gk, 2)) as skk,
             sum(c.ga * c.gk)    as sak
        from (select p.charge_nr,
                     sum(p.w * (p.y - (r.ln_lambda + r.k * p.x)))                      as ga,
                     sum(p.w * (p.x - r.x_mittel) * (p.y - (r.ln_lambda + r.k * p.x))) as gk
                from punkte p group by p.charge_nr) c
    ) g
)
select n, c_chargen, t_min, t_max, k, ln_lambda, exp(ln_lambda) as lambda,
       x_mittel, sxx, smearing,
       ln_lambda + ln(greatest(smearing, 0.01))                      as ln_lambda_korrigiert,
       case when n > 2 then sse / (n - 2) * n / nullif(sw, 0) end    as sigma2,
       case when c_chargen > 1
            then saa / power(sw, 2) * c_chargen::numeric / (c_chargen - 1) end  as var_achse,
       case when c_chargen > 1 and sxx <> 0
            then skk / power(sxx, 2) * c_chargen::numeric / (c_chargen - 1) end as var_k,
       case when c_chargen > 1 and sxx <> 0
            then sak / (sw * sxx) * c_chargen::numeric / (c_chargen - 1) end    as kov_achse_k,
       t_quantil_95(c_chargen - 1)                                              as t_faktor,
       (n >= 3 and c_chargen >= 3 and k is not null and k > 0
        and t_max > t_min * 1.5)                                                as brauchbar
  from gruppen;

create or replace view v_schimmel_kurve with (security_invoker = true) as
with klassen(von, bis) as (
  values (0,14), (15,30), (31,60), (61,90), (91,120), (121,180), (181,100000)
), je_klasse as (
  select k.von, k.bis,
         count(b.anteil)::int as n,
         sum(b.schimmel_kg) / nullif(sum(b.basis_jetzt_kg), 0) as anteil,
         stddev_samp(b.anteil) as sd
    from klassen k
    left join v_schimmel_punkte b
           on b.lagertage >= k.von and b.lagertage <= k.bis
          and b.anteil is not null and b.plausibel
   group by k.von, k.bis
)
select von, bis, n, anteil, sd,
       least(greatest(max(anteil) over (order by von
             rows between unbounded preceding and current row), 0), 1) as anteil_mono,
       case when n >= 2 then greatest(anteil - 1.96 * sd / sqrt(n), 0) end as unten,
       case when n >= 2 then least(anteil + 1.96 * sd / sqrt(n), 1) end   as oben
  from je_klasse;

-- ---------- Wie stark verzerrt die Verarbeitungsreihenfolge? --------------
-- Der naheliegende Test — hängen die Abweichungen vom Verlauf mit der
-- Verarbeitungsreihenfolge zusammen? — funktioniert nicht: innerhalb einer
-- Charge *ist* die Reihenfolge die Lagerdauer, und die steckt schon im
-- Modell. Die Regression hat den Zusammenhang bereits aufgebraucht.
--
-- Was wirklich trägt, ist der Vergleich der beiden Quellen. Lagerkontrollen
-- werden zufällig gegriffen, Verarbeitungsmessungen nach Aussehen sortiert.
-- Sagen beide dasselbe, gibt es keine Selektion. Liegen die Lagerkontrollen
-- systematisch höher, wurde nach Zustand ausgewählt und der aus der
-- Verarbeitung geschätzte Verlauf ist zu flach.
create or replace view v_selektionsverdacht with (security_invoker = true) as
with rest as (
  select p.quelle, p.basis_jetzt_kg::numeric as w,
         ln(-ln(1 - p.anteil::numeric)) - (m.ln_lambda + m.k * ln(p.lagertage::numeric)) as e
    from v_schimmel_punkte p cross join v_schimmel_modell m
   where m.brauchbar and p.plausibel
     and p.anteil > 0 and p.anteil < 1 and p.lagertage > 0
), je_quelle as (
  select quelle, count(*)::int as n, sum(w * e) / nullif(sum(w), 0) as mittel
    from rest group by quelle
)
select (select n from je_quelle where quelle = 'verarbeitung')      as n_verarbeitung,
       (select n from je_quelle where quelle = 'lager')             as n_lager,
       (select mittel from je_quelle where quelle = 'verarbeitung') as rest_verarbeitung,
       (select mittel from je_quelle where quelle = 'lager')        as rest_lager,
       -- Der Unterschied im Log-Raum; exp() davon ist der Faktor, um den
       -- die zufällig gegriffene Ware fauler ist als die ausgewählte.
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

comment on view v_selektionsverdacht is
  'Vergleicht zufällig gegriffene Lagerkontrollen mit den nach Aussehen '
  'ausgewählten Verarbeitungsmessungen. Ohne Lagerkontrollen ist die '
  'Selektionsverzerrung grundsätzlich nicht prüfbar.';

grant select on v_schimmel_punkte, v_selektionsverdacht to authenticated;


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

comment on view v_charge_rueckgrat is
  'eingang_netto_kg ist auf alle Paletten der Charge hochgerechnet; '
  'eingang_netto_gemessen_kg ist die Summe der Paletten mit bekannter Tara. '
  'Weichen die beiden ab, fehlt bei n_paletten − n_paletten_mit_netto '
  'Paletten die Gebindeart.';

create or replace view v_hochrechnung_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung
                    where schluessel = 'saison_ende'), current_date) as bis
), ausgang as (
  select charge_nr,
         sum(eingang_netto_kg) as kg,
         sum(eingang_netto_kg * lagertage) / nullif(sum(eingang_netto_kg), 0) as lagertage,
         sum(eingang_netto_kg) filter (where weg = 'hand') as kg_hand
    from v_auftrag_masse
   where station in ('sortieren', 'waschen_sortieren') and eingang_netto_kg is not null
   group by charge_nr
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       coalesce(a.kg, 0)                                            as ausgelagert_kg,
       a.lagertage                                                  as alter_ausgelagert,
       greatest(r.eingang_netto_kg - coalesce(a.kg, 0), 0)          as lager_kg,
       (s.bis - r.eingangsdatum_mittel)::numeric                    as alter_lager,
       (current_date - r.eingangsdatum_mittel)::numeric             as alter_lager_heute,
       coalesce(a.kg_hand / nullif(a.kg, 0), 0)                     as weg2_anteil,
       s.bis                                                        as stichtag,
       r.n_paletten_mit_netto,
       -- Wie viel musste weggekappt werden, damit der Lagerbestand nicht
       -- negativ wird? Grösser als 0 heisst: es wurde mehr ausgelagert als je
       -- eingelagert — Paletten doppelt gezählt oder Tara fehlt.
       greatest(coalesce(a.kg, 0) - r.eingang_netto_kg, 0)          as ueberzaehlung_kg
  from v_charge_rueckgrat r
  cross join stichtag s
  left join ausgang a on a.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;

comment on view v_hochrechnung_basis is
  'ueberzaehlung_kg > 0 heisst: es wurde mehr Masse ausgelagert als je '
  'eingelagert. Der Lagerbestand wird dann auf 0 gekappt — die Zahl hier ist '
  'die einzige Spur, die eine Doppelzählung hinterlässt.';

grant select on v_charge_rueckgrat, v_hochrechnung_basis to authenticated;


-- =====================================================================
-- aus 0022_pruefbare_annahmen.sql
-- =====================================================================

-- =====================================================================
-- 0022 — Zwei Annahmen prüfbar machen, statt sie zu glauben
--
-- ---------- 1. Die Dubletten-Regel ---------------------------------------
-- Regel 3 der CSV-Reinigung verwirft jeden Wert, der gleich seinem direkten
-- Vorgänger ist — 12–28 % aller Zeilen. Begründet ist das damit, dass zwei
-- echte Kürbisse nacheinander nur mit verschwindender Wahrscheinlichkeit
-- exakt gleich viel wiegen. Diese Wahrscheinlichkeit lässt sich aus der
-- Gewichtsverteilung selbst ausrechnen: Für unabhängige Ziehungen ist sie
-- Σ pᵢ², die Summe der quadrierten Anteile je Gewichtsstufe.
--
-- Damit wird prüfbar, was die Regel fälschlich entfernt: Von den verworfenen
-- Zeilen sind höchstens Σpᵢ² / Nachbar_gleich_Anteil echte Gleichheiten.
-- Die Ansicht rechnet beides aus den tatsächlich eingelesenen Dateien.
--
-- ---------- 2. Stratifizierung nach Schlag -------------------------------
-- Spec §9 nennt Sorte, Schlag und Lagerdauer. Gebaut ist nur Sorte. Ob der
-- Schlag eigenständig etwas beiträgt, entscheidet nicht die Meinung, sondern
-- die Frage, ob die Unterschiede zwischen Schlägen grösser sind als das, was
-- blosses Stichprobenrauschen erzeugt. Genau das rechnet v_schlag_effekt —
-- dieselbe Momentenschätzung wie bei der Sorten-Bündelung.
--
-- Anzumerken: In diesen Daten ist jede Charge genau eine Kombination aus
-- Schlag und Sorte (42 Chargen, 42 Kombinationen). Der Schlag ist damit in
-- der Charge verschachtelt, und die chargen-robuste Fehlerrechnung aus 0017
-- und 0018 hat die Streuung zwischen Schlägen bereits im Bereich drin. Eine
-- eigene Schlag-Stratifizierung würde die Punktschätzung ändern, nicht die
-- Ehrlichkeit des Bereichs — sie lohnt sich nur, wenn tau2_schlag deutlich
-- über 0 liegt.
-- =====================================================================

create or replace view v_dubletten_pruefung with (security_invoker = true) as
with anteile as (
  -- Gewichtsverteilung über alle eingelesenen Dateien
  select gewicht_g, sum(anzahl)::numeric as n from sortier_gewicht group by gewicht_g
), gesamt as (
  select sum(n) as n_gesamt, sum(power(n, 2)) as summe_quadrate,
         count(*)::int as n_stufen from anteile
), laeufe as (
  select sum(n_dubletten)::numeric as verworfen, sum(n_roh)::numeric as roh
    from sortier_lauf where n_roh > 0
)
select g.n_gesamt::bigint                                            as kuerbisse,
       l.roh::bigint                                                 as zeilen_roh,
       l.verworfen::bigint                                           as zeilen_verworfen,
       (l.verworfen / nullif(l.roh, 0))                              as anteil_verworfen,
       -- Σpᵢ²: wie oft zwei unabhängig gezogene Kürbisse gleich viel wiegen
       (g.summe_quadrate / nullif(power(g.n_gesamt, 2), 0))           as zufalls_gleichheit,
       -- Wie viel der verworfenen Zeilen war vermutlich echt?
       (g.summe_quadrate / nullif(power(g.n_gesamt, 2), 0))
         / nullif(l.verworfen / nullif(l.roh, 0), 0)                  as anteil_faelschlich,
       case
         when l.roh is null or l.roh = 0 then 'keine CSV eingelesen'
         -- Testdaten haben oft nur eine Handvoll Gewichte; Σpᵢ² ist dann
         -- gross, ohne dass das über echte Kürbisse etwas aussagt.
         when g.n_stufen < 50
           then format('nur %s verschiedene Gewichte — das sind keine echten '
                       || 'Messdaten, die Prüfung sagt hier nichts', g.n_stufen)
         when (g.summe_quadrate / nullif(power(g.n_gesamt, 2), 0))
              / nullif(l.verworfen / nullif(l.roh, 0), 0) < 0.05
           then 'Regel trägt: die verworfenen Gleichheiten sind weit häufiger, '
                || 'als Zufall sie erzeugen könnte'
         else 'Vorsicht: der Zufall erklärt einen erheblichen Teil der '
              || 'verworfenen Zeilen — die Regel gehört an einer handgezählten '
              || 'Palette überprüft (Spec §13)'
       end                                                            as befund,
       g.n_stufen                                                     as gewichtsstufen
  from gesamt g cross join laeufe l;

comment on view v_dubletten_pruefung is
  'Prüft die Dubletten-Regel gegen die Gewichtsverteilung selbst. '
  'anteil_faelschlich ist der Anteil der verworfenen Zeilen, der auch bei '
  'echten, unabhängigen Kürbissen aufgetreten wäre.';

create or replace view v_schlag_effekt with (security_invoker = true) as
with punkte as (
  select p.schlag, p.charge_nr, p.basis_jetzt_kg::numeric as w,
         ln(-ln(1 - p.anteil::numeric)) - (m.ln_lambda + m.k * ln(p.lagertage::numeric)) as e
    from v_schimmel_punkte p cross join v_schimmel_modell m
   where m.brauchbar and p.plausibel and p.anteil > 0 and p.anteil < 1 and p.lagertage > 0
), je_schlag as (
  select schlag, count(*)::int as n, count(distinct charge_nr)::int as c,
         sum(w) as sw, sum(w * e) / nullif(sum(w), 0) as mittel
    from punkte group by schlag
), streuung as (
  select count(*)::int                                                  as n_schlaege,
         sum(sw * power(mittel, 2)) / nullif(sum(sw), 0)                as beobachtet,
         -- Was blosses Rauschen erzeugen würde: die mittlere Varianz der
         -- Schlagmittel bei zufälliger Zuordnung
         (select sum(w * power(e, 2)) / nullif(sum(w), 0) from punkte)
           / nullif(avg(n), 0)                                          as erwartet_durch_zufall
    from je_schlag where n >= 2
)
select n_schlaege, beobachtet, erwartet_durch_zufall,
       greatest(beobachtet - erwartet_durch_zufall, 0)                  as tau2_schlag,
       case
         when n_schlaege is null or n_schlaege < 3
           then 'zu wenige Schläge mit Messungen'
         when greatest(beobachtet - erwartet_durch_zufall, 0) <= 0
           then 'die Unterschiede zwischen Schlägen sind nicht grösser als '
                || 'Stichprobenrauschen — eine eigene Schlag-Schätzung brächte nichts'
         when beobachtet > 2 * erwartet_durch_zufall
           then 'die Schläge unterscheiden sich deutlich — eine eigene '
                || 'Schlag-Stratifizierung wäre begründet'
         else 'schwacher Hinweis auf Schlag-Unterschiede, für eine eigene '
              || 'Schätzung reicht es noch nicht'
       end                                                              as befund
  from streuung;

comment on view v_schlag_effekt is
  'Entscheidet an den Daten, ob eine Stratifizierung nach Schlag begründet '
  'ist. Bis tau2_schlag deutlich über 0 liegt, steckt die Streuung zwischen '
  'Schlägen bereits in der chargen-robusten Fehlerrechnung.';

grant select on v_dubletten_pruefung, v_schlag_effekt to authenticated;


-- =====================================================================
-- aus 0023_ranking_mit_filter.sql
-- =====================================================================

-- =====================================================================
-- 0023 — Das Ranking auch gefiltert richtig rechnen
--
-- Das Dashboard lässt nach Sorte, Schlag und Mindest-Lagerdauer filtern und
-- summierte die Ströme dafür bisher selbst im Browser. Solange der Bereich
-- aus drei Szenarien bestand, ging das: drei Summen, fertig. Seit 0019 ist
-- der Bereich eine fortgepflanzte Streuung — Summieren führt dabei zum
-- falschen Ergebnis, weil sich Fehler nicht addieren, sondern je nach
-- Korrelation quadratisch oder linear zusammensetzen.
--
-- Die Statistik ein zweites Mal in TypeScript zu schreiben wäre die sicherste
-- Art, die beiden auseinanderlaufen zu lassen. Statt dessen wandert der Filter
-- dorthin, wo gerechnet wird. Die Kaskade hat je Charge und Portion eine
-- Zeile — ein paar Dutzend —, das kostet nichts.
-- =====================================================================

drop view if exists v_marge_buch;
drop view if exists v_verlust_ranking;

create or replace function verlust_ranking(
  p_sorte          text    default null,
  p_schlag         text    default null,
  p_min_lagertage  numeric default null)
returns table (
  strom text, buch text, kg numeric, kg_unten numeric, kg_oben numeric,
  kg_beobachtet numeric, kg_projiziert numeric, kg_extrapoliert numeric,
  koeff_n_min int, streuung_kg numeric, df int)
language sql stable as $$
with zeilen as materialized (
  select * from v_hochrechnung
   where buch in ('verlust', 'marge')
     and (p_sorte is null or sorte = p_sorte)
     and (p_schlag is null or schlag = p_schlag)
     and (p_min_lagertage is null or alter_tage >= p_min_lagertage)
),
je_sorte as (
  select z.strom, z.buch, z.sorte, max(z.koeff_art) as koeff_art,
         sum(z.d_r) as g_r, sum(z.d_a) as g_a
    from zeilen z group by z.strom, z.buch, z.sorte
),
je_strom_modell as (
  select z.strom, z.buch,
         sum(z.d_eta)       as g_achse,
         sum(z.d_eta * z.u) as g_steigung
    from zeilen z group by z.strom, z.buch
),
varianz_r as (
  select s.strom, s.buch,
         sum(power(s.g_r, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_r * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = 'verdunstung' and u.sorte is not distinct from s.sorte
   group by s.strom, s.buch
),
varianz_a as (
  select s.strom, s.buch,
         sum(power(s.g_a, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_a * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = s.koeff_art and u.sorte is not distinct from s.sorte
   where s.koeff_art is not null
   group by s.strom, s.buch
),
varianz_f as (
  select m.strom, m.buch,
         power(m.g_achse, 2) * coalesce(sm.var_achse, 0)
         + 2 * m.g_achse * m.g_steigung * coalesce(sm.kov_achse_k, 0)
         + power(m.g_steigung, 2) * coalesce(sm.var_k, 0)       as varianz,
         coalesce(sm.c_chargen - 1, 1)                          as df
    from je_strom_modell m cross join v_schimmel_modell sm
),
summe as (
  select z.strom, z.buch,
         sum(z.kg)                                                as kg,
         sum(z.kg) filter (where z.portion = 'ausgelagert')       as kg_beobachtet,
         sum(z.kg) filter (where z.portion = 'lager')             as kg_projiziert,
         sum(z.kg) filter (where z.f_extrapoliert)                as kg_extrapoliert,
         min(z.koeff_n)                                           as koeff_n_min
    from zeilen z group by z.strom, z.buch
)
select s.strom, s.buch, s.kg,
       greatest(s.kg - g.t * g.streuung, 0)::numeric(14,2),
       (s.kg + g.t * g.streuung)::numeric(14,2),
       s.kg_beobachtet, s.kg_projiziert, s.kg_extrapoliert, s.koeff_n_min,
       g.streuung::numeric(14,2), g.df
  from summe s
  left join varianz_r vr on vr.strom = s.strom and vr.buch = s.buch
  left join varianz_a va on va.strom = s.strom and va.buch = s.buch
  left join varianz_f vf on vf.strom = s.strom and vf.buch = s.buch
  cross join lateral (
    select sqrt(greatest(coalesce(vr.varianz, 0) + coalesce(va.varianz, 0)
                         + coalesce(vf.varianz, 0), 0))       as streuung,
           least(coalesce(vr.df, 999), coalesce(va.df, 999),
                 coalesce(vf.df, 999))                        as df
  ) g0
  cross join lateral (select g0.streuung, g0.df, t_quantil_95(g0.df) as t) g
 order by s.kg desc nulls last;
$$;

comment on function verlust_ranking(text, text, numeric) is
  'Die Ströme mit fortgepflanztem 95-%-Bereich, wahlweise auf Sorte, Schlag '
  'oder Mindest-Lagerdauer eingeschränkt. Der Bereich lässt sich nicht durch '
  'Summieren gefilterter Zeilen gewinnen — deshalb gehört der Filter hierher.';

create view v_verlust_ranking with (security_invoker = true) as
select * from verlust_ranking();

comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall: die '
  'Empfindlichkeit jedes Stroms gegenüber jedem Koeffizienten mal dessen '
  'Fehler, zusammengesetzt nach der tatsächlichen Korrelation.';

create view v_marge_buch with (security_invoker = true) as
with kisten as materialized (
  select sum(k.verkaufsfaehig_kg * b.weg2_anteil) / 8.0 as anzahl
    from v_kaskade k join v_hochrechnung_basis b on b.charge_nr = k.charge_nr
)
select r.strom as posten, r.kg, r.kg_unten, r.kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from v_verlust_ranking r where r.buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       (u.unten * v.anzahl)::numeric(14,2),
       (u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.anzahl))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;

grant execute on function verlust_ranking(text, text, numeric) to authenticated;
grant select on v_verlust_ranking, v_marge_buch to authenticated;


-- =====================================================================
-- aus 0024_weg1_zweiter_lagerabschnitt.sql
-- =====================================================================

-- =====================================================================
-- 0024 — Weg 1 hat zwei Lagerabschnitte, das Modell kannte nur einen
--
-- Spec §3 beschreibt Weg 1 als: Lager → Sortieren → **Lager** → Waschen →
-- Warenausgang. Zwischen Sortieren und Waschen liegen Wochen bis Monate, und
-- die Ware liegt in dieser Zeit in Kaliber-Kisten wieder in derselben Halle.
-- Der Betrieb bestätigt: **alles**, was sortiert wurde, wird später gewaschen.
--
-- Das Modell kannte diesen zweiten Abschnitt nicht. Zwei Folgen, beide belegt.
--
-- ---------- 1. Schimmel #2 verschwand spurlos ----------------------------
-- Beim Waschen wird nochmals Faules aussortiert — Spec §3 nennt das
-- ausdrücklich „Schimmel #2, zeitaufgelöst". Der Arbeiter trägt es ein, die
-- Datenbank speichert es, und das Modell hat es weggeworfen:
--
--   Wasch-Auftrag mit 900 kg Schimmel  →  0 Zeilen in v_schimmel_punkte
--
-- Der Grund: v_schimmel_beobachtung verlangt eine Lagerdauer, und die kam aus
-- den gezählten Paletten. Beim Waschen gibt es keine zu zählen — die
-- Original-Paletten haben sich beim Sortieren in Kaliber-Kisten aufgelöst.
-- Also blieb lagertage NULL und die Messung fiel heraus.
--
-- Behoben: Ein Wasch-Auftrag erbt die Lagerdauer aus dem, was beim Sortieren
-- derselben Charge gezählt wurde — massegewichtet über die Eingangsdaten.
-- Damit steht Schimmel #2 dort in der Kurve, wo er hingehört: bei einer
-- deutlich längeren Lagerdauer als Schimmel #1. Genau diese Punkte fehlten
-- dem Verderbsmodell am rechten Rand.
--
-- ---------- 2. Sortierte Ware galt als aus dem Haus -----------------------
-- ausgelagert_kg zählte Sortieren und Waschen+Sortieren. Sortierte Ware war
-- damit „raus", obwohl sie physisch in derselben Halle steht und weiter
-- verdunstet und verdirbt. Ihr Alter blieb beim Sortiertag stehen.
--
-- Jetzt gilt: Aus dem Lager ist, was den *letzten* Schritt hinter sich hat —
-- Weg 2 nach Waschen+Sortieren, Weg 1 erst nach dem Waschen. Was sortiert
-- ist und auf das Waschen wartet, zählt weiter zum Bestand und altert weiter.
--
-- Der zweite Abschnitt wird dabei nicht als eigene Kaskadenstufe gerechnet,
-- sondern über das Alter: Verdunstung und Schimmel sind kumulativ, es genügt
-- also, das *Endalter* einzusetzen statt des Sortieralters. Der Ausschuss
-- wurde beim Sortieren entnommen und wird hier auf die etwas kleinere Masse
-- am Ende bezogen — ein Fehler in der Grössenordnung 0.1 % des Stroms, gegen
-- den es sich nicht lohnt, eine zweite Stufe zu bauen.
-- =====================================================================

-- ---------- Lagerdauer auch ohne gezählte Paletten ------------------------
create or replace view v_auftrag_masse with (security_invoker = true) as
with sortier_eingang as (
  -- Wann kam die Ware herein, die diese Charge beim Sortieren durchlaufen hat?
  -- Massegewichtet, in Tagen seit einer festen Epoche (Datumsarithmetik lässt
  -- sich nicht mitteln).
  select a.charge_nr,
         sum((m.eingangsdatum - date '2000-01-01')::numeric * m.netto_kg)
           / nullif(sum(m.netto_kg), 0)                        as tage_seit_epoche
    from auftrag a
    join v_auftrag_palette_masse m on m.auftrag_id = a.id
   where a.station = 'sortieren' and a.abgebrochen_ts is null
   group by a.charge_nr
), charge_eingang as (
  -- Rückfall, falls zur Charge kein Sortier-Auftrag erfasst ist
  select charge_nr, (eingangsdatum_mittel - date '2000-01-01')::numeric as tage_seit_epoche
    from v_charge_rueckgrat
)
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten, m.eingang_netto_kg,
       m.masse_quelle,
       (coalesce(
         m.lagertage,
         -- Beim Waschen auf Weg 1 gibt es nichts zu zählen. Die Lagerdauer
         -- ist trotzdem bekannt: sie läuft ab dem Wareneingang, nicht ab dem
         -- Sortiertag. Ohne das fiel Schimmel #2 aus dem Modell.
         case when m.station = 'waschen'
              then ((m.start_ts::date - date '2000-01-01')::numeric
                    - coalesce(se.tage_seit_epoche, ce.tage_seit_epoche))
         end
       ))::numeric(10,1)                                       as lagertage
  from mv_auftrag_masse m
  left join sortier_eingang se on se.charge_nr = m.charge_nr
  left join charge_eingang  ce on ce.charge_nr = m.charge_nr;

comment on view v_auftrag_masse is
  'Masse und Lagerdauer je Arbeit. Wasch-Aufträge auf Weg 1 zählen keine '
  'Paletten — ihre Lagerdauer wird aus dem Wareneingang der sortierten Ware '
  'abgeleitet, sonst fiele Schimmel #2 aus der Auswertung.';

-- ---------- Aus dem Lager ist, was den letzten Schritt hinter sich hat ----
create or replace view v_hochrechnung_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung
                    where schluessel = 'saison_ende'), current_date) as bis
), je_station as (
  select charge_nr,
         sum(eingang_netto_kg) filter (where station = 'sortieren')          as sortiert_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen')            as gewaschen_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren')  as hand_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren'
                                         and weg = 'hand')                   as kg_hand,
         -- Endverarbeitungsalter: massegewichtet über die Schritte, nach denen
         -- die Ware wirklich draussen ist.
         sum(eingang_netto_kg * lagertage) filter (
             where station in ('waschen', 'waschen_sortieren') and lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (
               where station in ('waschen', 'waschen_sortieren') and lagertage is not null), 0)
                                                                             as alter_ende,
         -- Rückfall, solange noch nichts gewaschen ist
         sum(eingang_netto_kg * lagertage) filter (where lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (where lagertage is not null), 0)
                                                                             as alter_irgendwas
    from v_auftrag_masse
   where eingang_netto_kg is not null
   group by charge_nr
), anteil as (
  select s.*,
         -- Welcher Teil der sortierten Ware ist schon gewaschen? gewaschen_kg
         -- ist beim Waschen gemessen, also nach den Verlusten des ersten
         -- Abschnitts — der Anteil fällt dadurch etwas zu klein aus und die
         -- wartende Menge etwas zu gross. Das liegt auf der vorsichtigen Seite.
         least(coalesce(s.gewaschen_kg, 0) / nullif(s.sortiert_kg, 0), 1)     as anteil_gewaschen
    from je_station s
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       -- Draussen ist: Weg 2 komplett, Weg 1 nur der gewaschene Teil.
       (coalesce(a.hand_kg, 0)
        + coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0))       as ausgelagert_kg,
       coalesce(a.alter_ende, a.alter_irgendwas)                              as alter_ausgelagert,
       -- Im Haus ist: was nie angefasst wurde, plus was sortiert ist und auf
       -- das Waschen wartet. Beides altert bis zum Stichtag weiter, beides
       -- rechnet die Kaskade mit demselben Alter — deshalb eine Portion.
       greatest(r.eingang_netto_kg
                - coalesce(a.hand_kg, 0)
                - coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0), 0)
                                                                              as lager_kg,
       (s.bis - r.eingangsdatum_mittel)::numeric                              as alter_lager,
       (current_date - r.eingangsdatum_mittel)::numeric                       as alter_lager_heute,
       coalesce(a.kg_hand / nullif(coalesce(a.hand_kg, 0)
                                   + coalesce(a.sortiert_kg, 0), 0), 0)       as weg2_anteil,
       s.bis                                                                  as stichtag,
       r.n_paletten_mit_netto,
       greatest(coalesce(a.hand_kg, 0) + coalesce(a.sortiert_kg, 0)
                - r.eingang_netto_kg, 0)                                      as ueberzaehlung_kg,
       coalesce(a.sortiert_kg, 0)                                             as sortiert_kg,
       coalesce(a.gewaschen_kg, 0)                                            as gewaschen_kg,
       -- Sortiert, aber noch nicht gewaschen: steht in Kaliber-Kisten in der
       -- Halle. Für den Betriebsleiter die Menge, die als nächstes ans
       -- Waschbecken muss.
       (coalesce(a.sortiert_kg, 0) * (1 - coalesce(a.anteil_gewaschen, 0)))    as wartet_kg,
       coalesce(a.anteil_gewaschen, 0)                                        as anteil_gewaschen
  from v_charge_rueckgrat r
  cross join stichtag s
  left join anteil a on a.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;

comment on view v_hochrechnung_basis is
  'ausgelagert_kg ist die Masse, die den letzten Verarbeitungsschritt hinter '
  'sich hat — auf Weg 1 also erst nach dem Waschen. wartet_kg steht sortiert '
  'in Kaliber-Kisten und altert weiter. ueberzaehlung_kg > 0 heisst: mehr '
  'ausgelagert als je eingelagert, also Paletten doppelt gezählt.';

grant select on v_auftrag_masse, v_hochrechnung_basis to authenticated;


-- =====================================================================
-- aus 0025_schimmel_zwei_stufen.sql
-- =====================================================================

-- =====================================================================
-- 0025 — Der Schimmel beim Waschen ist ein Zuwachs, kein Gesamtwert
--
-- Nach 0024 kommt Schimmel #2 im Modell an. Trotzdem blieb die Schätzung
-- daneben (25 Saisons, zweistufiger Weg 1, 30 % im Lager):
--
--   Schimmel/Fäulnis   Verzerrung −16.4 %   Überdeckung 4 %
--
-- Der Grund steckt im Ablauf, nicht in der Statistik. Auf Weg 1 wird zweimal
-- Faules aussortiert: einmal vor dem Sortierband, Wochen später nochmals vor
-- dem Waschbecken. Im Palox am Waschbecken liegt aber nur, was **seit dem
-- Sortieren** dazugekommen ist — der erste Teil ist längst entsorgt.
--
-- Die Kurve F(t) ist dagegen kumulativ: „welcher Anteil der Ware ist bis Tag t
-- insgesamt verdorben". Wer den Waschen-Palox direkt als F(t₂) liest, setzt
--
--   F(t₂) ≈ F(t₂) − F(t₁)     statt      F(t₂)
--
-- also einen deutlich zu kleinen Wert — und zwar ausgerechnet bei den längsten
-- Lagerdauern, wo die Kurve am steilsten ist. Das Modell wird dadurch flacher
-- angepasst und unterschätzt alles, was lange liegt.
--
-- Der naheliegende Weg — den ersten Betrag in Kilo dazurechnen — geht schief:
-- Der Durchsatz am Waschbecken ist schon um Verdunstung, Schimmel und
-- Ausschuss vermindert, taugt also nicht als Bezugsmasse für eine Menge, die
-- beim Sortieren entnommen wurde. Gemessen hat dieser Ansatz +15.3 %
-- Verzerrung ergeben — genauso falsch wie vorher, nur andersherum.
--
-- Richtig wird es über Anteile statt über Kilo. Am Waschbecken kommt eine
-- Masse an, von der ein Teil faul ist:
--
--   g = Schimmel₂ / (Durchsatz + Schimmel₂)
--
-- Das ist der Anteil der *Überlebenden* des ersten Durchgangs, die es bis
-- hierher nicht geschafft haben. Beide Durchgänge zusammen ergeben dann
--
--   1 − F(t₂) = (1 − F(t₁)) · (1 − g)
--
-- Darin steckt keine einzige Kilo-Umrechnung mehr: g stammt vollständig aus
-- am Waschbecken gemessenen Grössen, F(t₁) ist der Anteil, den dieselbe
-- Charge beim Sortieren hatte. Ist beim Sortieren nichts gemessen worden,
-- gilt F(t₁) = 0 und der Punkt sagt nur, was er sicher weiss.
-- =====================================================================

create or replace view v_schimmel_punkte with (security_invoker = true) as
with schimmel_je_auftrag as materialized (
  select auftrag_id, sum(kg)::numeric as kg
    from schimmel_messung where gemessen group by auftrag_id
),
-- Der Anteil, den die Charge beim Sortieren schon hatte: F(t₁).
-- Nur Sortierläufe, die *vor* dem Waschen lagen — was später sortiert wurde,
-- kann in diesem Waschgang nicht dabei gewesen sein. Ohne diese Einschränkung
-- fliesst der Zustand späterer, älterer Ware in frühe Waschgänge ein und der
-- Punkt fällt zu hoch aus (gemessen: +7.5 % auf den Waschen-Punkten).
sortier_lauf_anteil as materialized (
  select b.charge_nr, b.start_ts, b.schimmel_kg, b.basis_jetzt_kg
    from v_schimmel_beobachtung b
   where b.station = 'sortieren' and b.plausibel and b.anteil is not null
)
-- Erster Durchgang und Weg 2: der Palox enthält alles bis dahin Verdorbene,
-- der gemessene Anteil ist direkt F(t).
select b.charge_nr, b.sorte, b.schlag, b.lagertage, b.schimmel_kg,
       b.basis_jetzt_kg, b.anteil, b.plausibel,
       'verarbeitung'::text as quelle, b.auftrag_id
  from v_schimmel_beobachtung b
 where b.station in ('sortieren', 'waschen_sortieren')
union all
-- Zweiter Durchgang auf Weg 1: aus dem Zuwachs den kumulativen Wert bilden.
select a.charge_nr, a.sorte, a.schlag, a.lagertage,
       s.kg                                                      as schimmel_kg,
       (a.eingang_netto_kg + s.kg)                               as basis_jetzt_kg,
       k.f2                                                      as anteil,
       anteil_plausibel(k.f2)                                    as plausibel,
       'verarbeitung', a.auftrag_id
  from v_auftrag_masse a
  join schimmel_je_auftrag s on s.auftrag_id = a.auftrag_id
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
 where a.station = 'waschen' and a.lagertage is not null
   and a.eingang_netto_kg is not null and a.eingang_netto_kg > 0
union all
-- Lagerkontrollen: eine zufällig gegriffene Palette, nichts vorher entnommen.
select w.charge_nr, w.sorte, w.schlag, w.lagertage,
       v.faul_kg, w.netto_jetzt_kg,
       v.faul_kg / nullif(w.netto_jetzt_kg, 0),
       anteil_plausibel(v.faul_kg / nullif(w.netto_jetzt_kg, 0)),
       'lager', null::bigint
  from v_verdunstung_messung w
  join verdunstung_wiegung v on v.id = w.id
 where v.faul_kg is not null and v.gemessen
   and w.netto_jetzt_kg > 0 and w.lagertage > 0;

comment on view v_schimmel_punkte is
  'Alle Schimmelbeobachtungen als *kumulativer* Anteil F(t). Der Palox am '
  'Waschbecken enthält nur den Zuwachs seit dem Sortieren; daraus wird über '
  'die bedingte Überlebensrate der kumulative Wert gebildet, ohne Kilo '
  'umzurechnen. quelle = lager heisst: zufällig gegriffen, also frei von der '
  'Selektionsverzerrung der Verarbeitungsreihenfolge.';

grant select on v_schimmel_punkte to authenticated;


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
 group by a.charge_nr;

create unique index if not exists mv_sortier_eingang_pk on mv_sortier_eingang (charge_nr);

create or replace view v_auftrag_masse with (security_invoker = true) as
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten, m.eingang_netto_kg,
       m.masse_quelle,
       (coalesce(
         m.lagertage,
         -- Beim Waschen auf Weg 1 gibt es nichts zu zählen. Die Lagerdauer
         -- läuft trotzdem ab dem Wareneingang, nicht ab dem Sortiertag.
         case when m.station = 'waschen'
              then ((m.start_ts::date - date '2000-01-01')::numeric
                    - coalesce(se.tage_seit_epoche,
                               (r.eingangsdatum_mittel - date '2000-01-01')::numeric))
         end
       ))::numeric(10,1)                                     as lagertage
  from mv_auftrag_masse m
  left join mv_sortier_eingang se on se.charge_nr = m.charge_nr
  left join v_charge_rueckgrat  r  on r.charge_nr = m.charge_nr;

-- ---------- Die Schimmelpunkte speichern ----------------------------------
create materialized view if not exists mv_schimmel_punkte as
select * from v_schimmel_punkte;

create index if not exists mv_schimmel_punkte_charge on mv_schimmel_punkte (charge_nr);
create index if not exists mv_schimmel_punkte_quelle on mv_schimmel_punkte (quelle);

comment on materialized view mv_schimmel_punkte is
  'Die gespeicherte Fassung von v_schimmel_punkte. Alles, was rechnet, liest '
  'diese hier; v_schimmel_punkte selbst rechnet neu und wird nur beim '
  'Neuberechnen gebraucht.';

-- ---------- Die Leser auf die gespeicherte Fassung umhängen ----------------

create or replace view v_schimmel_modell with (security_invoker = true) as
WITH beob AS (
         SELECT b.charge_nr,
            b.lagertage AS t,
            b.anteil AS f,
            b.basis_jetzt_kg AS gewicht
           FROM mv_schimmel_punkte b
          WHERE b.plausibel AND b.anteil > 0::numeric AND b.anteil < 1::numeric AND b.lagertage > 0::numeric
        ), punkte AS (
         SELECT beob.charge_nr,
            ln(beob.t) AS x,
            ln(- ln(1::numeric - beob.f)) AS y,
            beob.gewicht AS w,
            beob.t
           FROM beob
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
        ), fit AS (
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
           FROM fit f
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
    n >= 3 AND c_chargen >= 3 AND k IS NOT NULL AND k > 0::numeric AND t_max > (t_min * 1.5) AS brauchbar
   FROM gruppen;

create or replace view v_schimmel_kurve with (security_invoker = true) as
WITH klassen(von, bis) AS (
         VALUES (0,14), (15,30), (31,60), (61,90), (91,120), (121,180), (181,100000)
        ), je_klasse AS (
         SELECT k.von,
            k.bis,
            count(b.anteil)::integer AS n,
            sum(b.schimmel_kg) / NULLIF(sum(b.basis_jetzt_kg), 0::numeric) AS anteil,
            stddev_samp(b.anteil) AS sd
           FROM klassen k
             LEFT JOIN mv_schimmel_punkte b ON b.lagertage >= k.von::numeric AND b.lagertage <= k.bis::numeric AND b.anteil IS NOT NULL AND b.plausibel
          GROUP BY k.von, k.bis
        )
 SELECT von,
    bis,
    n,
    anteil,
    sd,
    LEAST(GREATEST(max(anteil) OVER (ORDER BY von ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0::numeric), 1::numeric) AS anteil_mono,
        CASE
            WHEN n >= 2 THEN GREATEST(anteil::double precision - (1.96 * sd)::double precision / sqrt(n::double precision), 0::double precision)
            ELSE NULL::double precision
        END AS unten,
        CASE
            WHEN n >= 2 THEN LEAST(anteil::double precision + (1.96 * sd)::double precision / sqrt(n::double precision), 1::double precision)
            ELSE NULL::double precision
        END AS oben
   FROM je_klasse;

create or replace view v_selektionsverdacht with (security_invoker = true) as
WITH rest AS (
         SELECT p.quelle,
            p.basis_jetzt_kg AS w,
            ln(- ln(1::numeric - p.anteil)) - (m.ln_lambda + m.k * ln(p.lagertage)) AS e
           FROM mv_schimmel_punkte p
             CROSS JOIN v_schimmel_modell m
          WHERE m.brauchbar AND p.plausibel AND p.anteil > 0::numeric AND p.anteil < 1::numeric AND p.lagertage > 0::numeric
        ), je_quelle AS (
         SELECT rest.quelle,
            count(*)::integer AS n,
            sum(rest.w * rest.e) / NULLIF(sum(rest.w), 0::numeric) AS mittel
           FROM rest
          GROUP BY rest.quelle
        )
 SELECT ( SELECT je_quelle.n
           FROM je_quelle
          WHERE je_quelle.quelle = 'verarbeitung'::text) AS n_verarbeitung,
    ( SELECT je_quelle.n
           FROM je_quelle
          WHERE je_quelle.quelle = 'lager'::text) AS n_lager,
    ( SELECT je_quelle.mittel
           FROM je_quelle
          WHERE je_quelle.quelle = 'verarbeitung'::text) AS rest_verarbeitung,
    ( SELECT je_quelle.mittel
           FROM je_quelle
          WHERE je_quelle.quelle = 'lager'::text) AS rest_lager,
    (( SELECT je_quelle.mittel
           FROM je_quelle
          WHERE je_quelle.quelle = 'lager'::text)) - (( SELECT je_quelle.mittel
           FROM je_quelle
          WHERE je_quelle.quelle = 'verarbeitung'::text)) AS unterschied,
        CASE
            WHEN (( SELECT je_quelle.n
               FROM je_quelle
              WHERE je_quelle.quelle = 'lager'::text)) IS NULL THEN 'keine Lagerkontrollen — Selektion nicht prüfbar'::text
            WHEN (( SELECT je_quelle.n
               FROM je_quelle
              WHERE je_quelle.quelle = 'lager'::text)) < 5 THEN 'zu wenige Lagerkontrollen für eine Aussage'::text
            WHEN abs((( SELECT je_quelle.mittel
               FROM je_quelle
              WHERE je_quelle.quelle = 'lager'::text)) - (( SELECT je_quelle.mittel
               FROM je_quelle
              WHERE je_quelle.quelle = 'verarbeitung'::text))) > 0.2 THEN ((('verarbeitete und zufällig gegriffene Paletten sagen Verschiedenes — '::text || 'es wird nach Aussehen ausgewählt. Bei gleichem Alter sind die '::text) || 'verarbeiteten fauler, dafür bleibt am Ende die robustere Ware '::text) || 'liegen: der Verlauf wird zu flach und die Hochrechnung auf lange '::text) || 'Lagerdauern zu niedrig. Mehr Lagerkontrollen beheben das.'::text
            ELSE 'beide Quellen sagen dasselbe — kein Hinweis auf Selektion'::text
        END AS befund;

create or replace view v_schlag_effekt with (security_invoker = true) as
WITH punkte AS (
         SELECT p.schlag,
            p.charge_nr,
            p.basis_jetzt_kg AS w,
            ln(- ln(1::numeric - p.anteil)) - (m.ln_lambda + m.k * ln(p.lagertage)) AS e
           FROM mv_schimmel_punkte p
             CROSS JOIN v_schimmel_modell m
          WHERE m.brauchbar AND p.plausibel AND p.anteil > 0::numeric AND p.anteil < 1::numeric AND p.lagertage > 0::numeric
        ), je_schlag AS (
         SELECT punkte.schlag,
            count(*)::integer AS n,
            count(DISTINCT punkte.charge_nr)::integer AS c,
            sum(punkte.w) AS sw,
            sum(punkte.w * punkte.e) / NULLIF(sum(punkte.w), 0::numeric) AS mittel
           FROM punkte
          GROUP BY punkte.schlag
        ), streuung AS (
         SELECT count(*)::integer AS n_schlaege,
            sum(je_schlag.sw * power(je_schlag.mittel, 2::numeric)) / NULLIF(sum(je_schlag.sw), 0::numeric) AS beobachtet,
            (( SELECT sum(punkte.w * power(punkte.e, 2::numeric)) / NULLIF(sum(punkte.w), 0::numeric)
                   FROM punkte)) / NULLIF(avg(je_schlag.n), 0::numeric) AS erwartet_durch_zufall
           FROM je_schlag
          WHERE je_schlag.n >= 2
        )
 SELECT n_schlaege,
    beobachtet,
    erwartet_durch_zufall,
    GREATEST(beobachtet - erwartet_durch_zufall, 0::numeric) AS tau2_schlag,
        CASE
            WHEN n_schlaege IS NULL OR n_schlaege < 3 THEN 'zu wenige Schläge mit Messungen'::text
            WHEN GREATEST(beobachtet - erwartet_durch_zufall, 0::numeric) <= 0::numeric THEN 'die Unterschiede zwischen Schlägen sind nicht grösser als '::text || 'Stichprobenrauschen — eine eigene Schlag-Schätzung brächte nichts'::text
            WHEN beobachtet > (2::numeric * erwartet_durch_zufall) THEN 'die Schläge unterscheiden sich deutlich — eine eigene '::text || 'Schlag-Stratifizierung wäre begründet'::text
            ELSE 'schwacher Hinweis auf Schlag-Unterschiede, für eine eigene '::text || 'Schätzung reicht es noch nicht'::text
        END AS befund
   FROM streuung;


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

grant select on mv_schimmel_punkte, mv_sortier_eingang, v_auftrag_masse,
                v_schimmel_modell, v_schimmel_kurve, v_selektionsverdacht,
                v_schlag_effekt to authenticated;


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

-- ---------- Was stand zuletzt drauf? --------------------------------------
-- Der Arbeiter-Bildschirm liest das, bevor er die Differenz anzeigt.
create or replace view v_palox_stand with (security_invoker = true) as
select s.id, s.auftrag_id, s.ts, s.palox_stand_kg, s.kg,
       lag(s.palox_stand_kg) over (order by s.ts, s.id)          as vorher,
       case when lag(s.palox_stand_kg) over (order by s.ts, s.id) is null then s.palox_stand_kg
            when s.palox_stand_kg < lag(s.palox_stand_kg) over (order by s.ts, s.id)
                 then s.palox_stand_kg
            else s.palox_stand_kg - lag(s.palox_stand_kg) over (order by s.ts, s.id)
       end                                                        as differenz,
       (lag(s.palox_stand_kg) over (order by s.ts, s.id) is not null
        and s.palox_stand_kg < lag(s.palox_stand_kg) over (order by s.ts, s.id))
                                                                  as zwischendurch_geleert
  from schimmel_messung s
 where s.palox_stand_kg is not null and s.gemessen
 order by s.ts, s.id;

comment on view v_palox_stand is
  'Die Waagenstände der Reihe nach mit der jeweils daraus folgenden Menge. '
  'zwischendurch_geleert = true heisst: der Stand ist gefallen, der Palox '
  'wurde also geleert — dann gilt der neue Stand selbst als Menge.';

-- ---------- Der letzte Stand, für die Eingabemaske ------------------------
create or replace function palox_letzter_stand()
returns numeric language sql stable as $$
  select palox_stand_kg from schimmel_messung
   where palox_stand_kg is not null and gemessen
   order by ts desc, id desc limit 1;
$$;

comment on function palox_letzter_stand is
  'Was zuletzt auf der Palox-Waage stand. Der Arbeiter-Bildschirm zieht das '
  'vom neuen Stand ab, damit niemand im Kopf rechnen muss.';

grant select on v_palox_stand to authenticated;
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

comment on view v_lieferung_masse is
  'Lieferungen in Kilo. Kistenangaben werden über das gemessene Kilo je Kiste '
  'umgerechnet; masse_fehler_kg sagt, wie unsicher diese Umrechnung ist.';

grant select on lieferung, ausgang_ziel, v_lieferung_masse to authenticated;
grant insert, update, delete on lieferung to authenticated;
grant usage on sequence lieferung_id_seq to authenticated;


-- =====================================================================
-- aus 0029_saisonbilanz.sql
-- =====================================================================

-- =====================================================================
-- 0029 — Aus der Massenbilanz wird eine Bilanz
--
-- Bisher verglich v_massenbilanz das Modell mit der Sortier-CSV, und das auch
-- nur für den Teil einer Charge, der überhaupt eine CSV hat. Das prüft die
-- Koeffizienten — mehr nicht. Über die Verluste sagt es nichts, denn die CSV
-- wiegt, was *ankommt*, nicht was verschwand.
--
-- Mit dem Warenausgang (0028) geht die eigentliche Gegenprobe:
--
--   Eingang = Verlust + Ausgang + Restbestand
--
-- Was übrig bleibt, ist die Lücke. Sie ist die einzige Zahl im ganzen System,
-- die misst, was das Modell *nicht* sieht — nicht geschätzt, sondern als
-- Differenz zweier unabhängig erhobener Grössen.
--
-- Ehrlich bleibt sie nur mit einer Angabe daneben: wie vollständig der
-- Warenausgang überhaupt erfasst ist. Sind erst drei Lieferscheine drin, ist
-- die Lücke riesig und sagt nichts über das Modell — nur über die Erfassung.
-- Deshalb steht die Deckung immer dabei.
-- =====================================================================

create or replace view v_saisonbilanz with (security_invoker = true) as
with eingang as (
  select sum(eingang_kg)          as kg,
         sum(lager_kg)            as im_lager_kg,
         sum(wartet_kg)           as wartet_kg
    from v_hochrechnung_basis
), verlust as (
  select sum(kg)                  as kg,
         sum(kg_unten)            as kg_unten,
         sum(kg_oben)             as kg_oben
    from v_verlust_ranking where buch = 'verlust'
), rest as (
  -- Was das Modell für den Lagerbestand als verkaufsfähig übrig lässt
  select sum(verkaufsfaehig_kg)   as kg
    from v_kaskade where portion = 'lager'
), ausgang as (
  select coalesce(sum(masse_kg), 0)                                as kg,
         coalesce(sum(masse_kg) filter (where buch = 'verkauf'), 0) as verkauf_kg,
         coalesce(sum(masse_kg) filter (where buch = 'marge'), 0)   as marge_kg,
         coalesce(sum(masse_kg) filter (where buch = 'verlust'), 0) as entsorgt_kg,
         coalesce(sum(masse_fehler_kg), 0)                          as fehler_kg,
         count(*)::int                                             as n_lieferungen
    from v_lieferung_masse
)
select e.kg                                                as eingang_kg,
       v.kg                                                as verlust_modell_kg,
       v.kg_unten                                          as verlust_unten_kg,
       v.kg_oben                                           as verlust_oben_kg,
       a.kg                                                as ausgang_kg,
       a.verkauf_kg, a.marge_kg, a.entsorgt_kg,
       a.fehler_kg                                         as ausgang_fehler_kg,
       a.n_lieferungen,
       r.kg                                                as restbestand_modell_kg,
       e.im_lager_kg, e.wartet_kg,
       -- Die Lücke: was weder als Verlust erklärt noch als Ausgang gebucht
       -- noch als Bestand übrig ist.
       (e.kg - v.kg - a.kg - r.kg)                         as luecke_kg,
       case when e.kg > 0 then (e.kg - v.kg - a.kg - r.kg) / e.kg end
                                                           as luecke_anteil,
       -- Wie viel der Ernte ist durch Lieferscheine gedeckt? Ohne das ist die
       -- Lücke keine Aussage über das Modell.
       case when e.kg > 0 then a.kg / e.kg end             as ausgang_deckung,
       case
         when a.n_lieferungen = 0
           then 'Kein Warenausgang erfasst — die Bilanz kann nichts prüfen. '
                || 'Der Restbestand ist eine Hochrechnung, kein Inventar.'
         when a.kg / nullif(e.kg, 0) < 0.2
           then 'Erst ein Bruchteil des Ausgangs ist erfasst — die Lücke sagt '
                || 'bislang mehr über die Erfassung als über das Modell.'
         when abs(e.kg - v.kg - a.kg - r.kg) / nullif(e.kg, 0) < 0.05
           then 'Die Bilanz geht auf: Eingang, Verlust, Ausgang und Bestand '
                || 'passen auf wenige Prozent zusammen.'
         when (e.kg - v.kg - a.kg - r.kg) > 0
           then 'Es fehlt Masse: mehr eingelagert, als sich durch Verlust, '
                || 'Ausgang und Bestand erklären lässt. Entweder ist ein '
                || 'Abgang nicht erfasst, oder ein Verlust wird unterschätzt.'
         else 'Es ist zu viel Masse da: mehr ausgeliefert und übrig, als je '
              || 'eingelagert wurde. Meist doppelt gezählte Paletten oder '
              || 'fehlende Tara im Wareneingang.'
       end                                                 as befund
  from eingang e cross join verlust v cross join rest r cross join ausgang a;

comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand. '
  'luecke_kg ist die einzige Grösse im System, die misst, was das Modell '
  'nicht sieht. Nur aussagekräftig, soweit der Ausgang erfasst ist — '
  'ausgang_deckung sagt, wie weit das ist.';

grant select on v_saisonbilanz to authenticated;


-- =====================================================================
-- aus 0030_bilanz_am_band.sql
-- =====================================================================

-- =====================================================================
-- 0030 — Die Massenbilanz muss denselben Zeitpunkt vergleichen
--
-- v_massenbilanz stellt das Modell neben die Sortier-CSV: Die Maschine hat
-- jeden Kürbis gewogen, das Modell sagt voraus, wie viel über das Band laufen
-- müsste. Weichen die beiden systematisch ab, rechnet die Kaskade falsch.
--
-- Seit 0024 endet die Kaskade auf Weg 1 aber erst beim *Waschen*, Wochen nach
-- dem Sortieren. Verglichen wurde damit die Masse am Ende des zweiten
-- Lagerabschnitts mit einer Wägung vom Anfang — in der Prüffixtur 40 Tage
-- Unterschied und prompt 8.2 % Abweichung, die niemandes Fehler war ausser
-- dieser Gegenüberstellung.
--
-- Die CSV wiegt, was beim Sortieren über das Band lief. Also muss das Modell
-- genau dafür seine Vorhersage machen: Eingangsmasse, vermindert um
-- Verdunstung und Schimmel **bis zum Sortiertag**.
-- =====================================================================

-- Das Alter am Band, getrennt vom Endalter der Kaskade.
create or replace view v_hochrechnung_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung
                    where schluessel = 'saison_ende'), current_date) as bis
), je_station as (
  select charge_nr,
         sum(eingang_netto_kg) filter (where station = 'sortieren')          as sortiert_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen')            as gewaschen_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren')  as hand_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren'
                                         and weg = 'hand')                   as kg_hand,
         sum(eingang_netto_kg * lagertage) filter (
             where station in ('waschen', 'waschen_sortieren') and lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (
               where station in ('waschen', 'waschen_sortieren') and lagertage is not null), 0)
                                                                             as alter_ende,
         sum(eingang_netto_kg * lagertage) filter (where lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (where lagertage is not null), 0)
                                                                             as alter_irgendwas,
         -- Wann lief die Ware über ein Band? Das ist der Zeitpunkt, den die
         -- Sortier-CSV gewogen hat.
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
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       (coalesce(a.hand_kg, 0)
        + coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0))       as ausgelagert_kg,
       coalesce(a.alter_ende, a.alter_irgendwas)                              as alter_ausgelagert,
       greatest(r.eingang_netto_kg
                - coalesce(a.hand_kg, 0)
                - coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0), 0)
                                                                              as lager_kg,
       (s.bis - r.eingangsdatum_mittel)::numeric                              as alter_lager,
       (current_date - r.eingangsdatum_mittel)::numeric                       as alter_lager_heute,
       coalesce(a.kg_hand / nullif(coalesce(a.hand_kg, 0)
                                   + coalesce(a.sortiert_kg, 0), 0), 0)       as weg2_anteil,
       s.bis                                                                  as stichtag,
       r.n_paletten_mit_netto,
       greatest(coalesce(a.hand_kg, 0) + coalesce(a.sortiert_kg, 0)
                - r.eingang_netto_kg, 0)                                      as ueberzaehlung_kg,
       coalesce(a.sortiert_kg, 0)                                             as sortiert_kg,
       coalesce(a.gewaschen_kg, 0)                                            as gewaschen_kg,
       (coalesce(a.sortiert_kg, 0) * (1 - coalesce(a.anteil_gewaschen, 0)))    as wartet_kg,
       coalesce(a.anteil_gewaschen, 0)                                        as anteil_gewaschen,
       a.alter_band,
       coalesce(a.am_band_kg, 0)                                              as am_band_kg
  from v_charge_rueckgrat r
  cross join stichtag s
  left join anteil a on a.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;

-- ---------- Modell und CSV am selben Tag ----------------------------------
create or replace view v_massenbilanz with (security_invoker = true) as
with csv_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (
             where exists (select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
           / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
    from v_auftrag_masse am
   where am.station in ('sortieren', 'waschen_sortieren')
     and am.eingang_netto_kg is not null
   group by am.charge_nr
), gemessen as materialized (
  select charge_nr, sum(masse_kg) as gemessen_kg from v_sortier_lauf_masse group by charge_nr
), rest as materialized (
  select charge_nr, sum(verkaufsfaehig_kg) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade group by charge_nr
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       -- Was das Modell für den Tag am Band vorhersagt: Eingangsmasse minus
       -- Verdunstung und Schimmel *bis dahin*, nicht bis zum Waschen.
       (b.am_band_kg
        * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05), coalesce(b.alter_band, 0))
        * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
        * q.anteil_mit_csv)::numeric(14,2)                   as modell_am_band_kg,
       c.gemessen_kg                                         as csv_gemessen_kg,
       (c.gemessen_kg
        - b.am_band_kg
          * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05), coalesce(b.alter_band, 0))
          * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
          * q.anteil_mit_csv)::numeric(14,2)                 as abweichung_kg,
       case when b.am_band_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg
                   - b.am_band_kg
                     * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05),
                             coalesce(b.alter_band, 0))
                     * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
                     * q.anteil_mit_csv)
                  / (b.am_band_kg
                     * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05),
                             coalesce(b.alter_band, 0))
                     * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
                     * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       r.restbestand_kg::numeric(14,2)                       as restbestand_kg,
       b.alter_band
  from v_hochrechnung_basis b
  left join csv_anteil q on q.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr
  left join rest r       on r.charge_nr = b.charge_nr
  left join v_koeff_verdunstung kv on kv.sorte = b.sorte;

comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. '
  'abweichung_anteil nahe 0 heisst, die Koeffizienten treffen die Realität. '
  'Nur aussagekräftig für Chargen mit CSV — und sie prüft die Koeffizienten, '
  'nicht die Verluste: die CSV wiegt, was ankommt, nicht was verschwand.';

grant select on v_hochrechnung_basis, v_massenbilanz to authenticated;


-- =====================================================================
-- aus 0031_selektionszuschlag.sql
-- =====================================================================

-- =====================================================================
-- 0031 — Was sich nicht wegrechnen lässt, gehört in den Bereich
--
-- Wird zuerst verarbeitet, was schlecht aussieht, dann misst man die
-- schlechtere Hälfte der Ernte. In der Simulation, mitten in der Saison:
--
--   verarbeitete Paletten   mittlere Anfälligkeit  1.52
--   noch im Lager stehende  mittlere Anfälligkeit  0.80
--
-- Ich habe versucht, das zu korrigieren — die Kurve für stehende Ware um den
-- gemessenen Unterschied zu verschieben. Es hat nicht funktioniert, und der
-- Grund ist lehrreich genug, um ihn festzuhalten:
--
--   ohne Lagerkontrollen, ohne Korrektur   +13.3 %
--   mit Lagerkontrollen, ohne Korrektur    +14.3 %
--   mit Lagerkontrollen und Korrektur      −15.2 %
--
-- Der Versatz dreht das Vorzeichen, ohne den Betrag zu verkleinern. Die
-- Selektion verbiegt nämlich nicht die *Höhe* der Kurve, sondern ihre
-- *Steigung*: Anfällige Paletten werden früh gemessen, robuste spät, und die
-- angepasste Steigung k fiel dabei von wahren 1.6 auf 1.14. Einen falschen
-- Anstieg repariert kein Niveau-Versatz. Die Korrektur ist deshalb wieder
-- entfernt worden, statt Komplexität zu behalten, die nichts einbringt.
--
-- Was bleibt, ist die ehrliche Konsequenz: Wenn beide Quellen Verschiedenes
-- sagen, wissen wir, dass die Schimmelzahl für die stehende Ware daneben liegt
-- — nur nicht, in welche Richtung. Genau das ist ein Fall für den Bereich.
-- Der Zuschlag beträgt den gemessenen Unterschied, angewandt auf den Teil des
-- Schimmels, der auf noch stehende Ware entfällt.
--
-- Ohne Lagerkontrollen bleibt der Zuschlag 0 — dann ist die Selektion nicht
-- einmal prüfbar, und das Dashboard sagt genau das (v_selektionsverdacht).
-- =====================================================================

create or replace view v_schimmel_modell with (security_invoker = true) as
WITH beob AS (
         SELECT b.charge_nr,
            b.lagertage AS t,
            b.anteil AS f,
            b.basis_jetzt_kg AS gewicht
           FROM mv_schimmel_punkte b
          WHERE b.plausibel AND b.anteil > 0::numeric AND b.anteil < 1::numeric AND b.lagertage > 0::numeric
        ), punkte AS (
         SELECT beob.charge_nr,
            ln(beob.t) AS x,
            ln(- ln(1::numeric - beob.f)) AS y,
            beob.gewicht AS w,
            beob.t
           FROM beob
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
        ), fit AS (
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
           FROM fit f
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
    -- Wie weit sagen zufällig gegriffene und nach Aussehen ausgewählte Ware
    -- Verschiedenes? Im Log-Raum, erst ab fünf Kontrollen.
    ( SELECT CASE WHEN count(*) FILTER (WHERE p.quelle = 'lager') >= 5
                  -- Der blosse Betrag einer verrauschten Differenz ist immer
                  -- grösser als null, auch wenn gar kein Unterschied besteht.
                  -- Deshalb wird der eigene Standardfehler abgezogen: Es bleibt
                  -- nur, was sich nicht durch Zufall erklären lässt.
                  THEN greatest(
                    abs(sum(p.w * p.e) FILTER (WHERE p.quelle = 'lager')
                          / NULLIF(sum(p.w) FILTER (WHERE p.quelle = 'lager'), 0)
                      - sum(p.w * p.e) FILTER (WHERE p.quelle = 'verarbeitung')
                          / NULLIF(sum(p.w) FILTER (WHERE p.quelle = 'verarbeitung'), 0))
                    - 1.96 * stddev_samp(p.e) FILTER (WHERE p.quelle = 'lager')
                             / sqrt(count(*) FILTER (WHERE p.quelle = 'lager')), 0)::numeric
             END
        FROM ( SELECT b.quelle, b.basis_jetzt_kg::numeric AS w,
                      ln(-ln(1::numeric - b.anteil::numeric))
                        - (gruppen.ln_lambda + gruppen.k * ln(b.lagertage::numeric)) AS e
                 FROM mv_schimmel_punkte b
                WHERE b.plausibel AND b.anteil > 0::numeric AND b.anteil < 1::numeric
                  AND b.lagertage > 0::numeric) p) AS selektions_versatz
   FROM gruppen;;

comment on view v_schimmel_modell is
  'Verderbsmodell F(t) = 1 − exp(−λ·S·t^k), chargen-robust gefehlert. '
  'selektions_versatz ist der gemessene Unterschied zwischen zufällig '
  'gegriffener und nach Aussehen ausgewählter Ware — er lässt sich nicht '
  'herausrechnen, geht aber in den ausgewiesenen Bereich ein.';

CREATE OR REPLACE FUNCTION public.verlust_ranking(p_sorte text DEFAULT NULL::text, p_schlag text DEFAULT NULL::text, p_min_lagertage numeric DEFAULT NULL::numeric)
 RETURNS TABLE(strom text, buch text, kg numeric, kg_unten numeric, kg_oben numeric, kg_beobachtet numeric, kg_projiziert numeric, kg_extrapoliert numeric, koeff_n_min integer, streuung_kg numeric, df integer)
 LANGUAGE sql
 STABLE
AS $function$
with zeilen as materialized (
  select * from v_hochrechnung
   where buch in ('verlust', 'marge')
     and (p_sorte is null or sorte = p_sorte)
     and (p_schlag is null or schlag = p_schlag)
     and (p_min_lagertage is null or alter_tage >= p_min_lagertage)
),
je_sorte as (
  select z.strom, z.buch, z.sorte, max(z.koeff_art) as koeff_art,
         sum(z.d_r) as g_r, sum(z.d_a) as g_a
    from zeilen z group by z.strom, z.buch, z.sorte
),
je_strom_modell as (
  select z.strom, z.buch,
         sum(z.d_eta)       as g_achse,
         sum(z.d_eta * z.u) as g_steigung
    from zeilen z group by z.strom, z.buch
),
varianz_r as (
  select s.strom, s.buch,
         sum(power(s.g_r, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_r * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = 'verdunstung' and u.sorte is not distinct from s.sorte
   group by s.strom, s.buch
),
varianz_a as (
  select s.strom, s.buch,
         sum(power(s.g_a, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_a * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = s.koeff_art and u.sorte is not distinct from s.sorte
   where s.koeff_art is not null
   group by s.strom, s.buch
),
varianz_f as (
  select m.strom, m.buch,
         power(m.g_achse, 2) * coalesce(sm.var_achse, 0)
         + 2 * m.g_achse * m.g_steigung * coalesce(sm.kov_achse_k, 0)
         + power(m.g_steigung, 2) * coalesce(sm.var_k, 0)       as varianz,
         coalesce(sm.c_chargen - 1, 1)                          as df
    from je_strom_modell m cross join v_schimmel_modell sm
),
summe as (
  select z.strom, z.buch,
         sum(z.kg)                                                as kg,
         sum(z.kg) filter (where z.portion = 'ausgelagert')       as kg_beobachtet,
         sum(z.kg) filter (where z.portion = 'lager')             as kg_projiziert,
         sum(z.kg) filter (where z.f_extrapoliert)                as kg_extrapoliert,
         min(z.koeff_n)                                           as koeff_n_min
    from zeilen z group by z.strom, z.buch
)
select s.strom, s.buch, s.kg,
       greatest(s.kg - g.t * g.streuung - zu.zuschlag, 0)::numeric(14,2),
       (s.kg + g.t * g.streuung + zu.zuschlag)::numeric(14,2),
       s.kg_beobachtet, s.kg_projiziert, s.kg_extrapoliert, s.koeff_n_min,
       g.streuung::numeric(14,2), g.df
  from summe s
  left join varianz_r vr on vr.strom = s.strom and vr.buch = s.buch
  left join varianz_a va on va.strom = s.strom and va.buch = s.buch
  left join varianz_f vf on vf.strom = s.strom and vf.buch = s.buch
  cross join lateral (select coalesce(sm2.selektions_versatz, 0) as versatz
                       from v_schimmel_modell sm2) sel
  cross join lateral (
    select sqrt(greatest(coalesce(vr.varianz, 0) + coalesce(va.varianz, 0)
                         + coalesce(vf.varianz, 0), 0))       as streuung,
           least(coalesce(vr.df, 999), coalesce(va.df, 999),
                 coalesce(vf.df, 999))                        as df
  ) g0
  cross join lateral (select g0.streuung, g0.df, t_quantil_95(g0.df) as t) g
  -- Der Zuschlag ist keine Streuung, sondern eine Verzerrung unbekannter
  -- Richtung: Er wird nicht mit t multipliziert, sondern schlicht auf beide
  -- Grenzen gelegt. Er trifft nur den Teil des Schimmels, der auf noch
  -- stehende Ware entfällt — bei bereits verarbeiteter ist er gemessen.
  cross join lateral (
    select case when s.strom = 'Schimmel/Fäulnis'
                then coalesce(s.kg_projiziert, 0) * abs(exp(sel.versatz) - 1)
                else 0 end                                    as zuschlag) zu
 order by s.kg desc nulls last;
$function$;

create or replace view v_verlust_ranking with (security_invoker = true) as
select * from verlust_ranking();

grant select on v_schimmel_modell, v_verlust_ranking to authenticated;
grant execute on function verlust_ranking(text, text, numeric) to authenticated;


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
    from schimmel_messung s
    join auftrag a on a.id = s.auftrag_id
   where s.palox_stand_kg is not null and s.gemessen
     and a.station = p_station
   order by s.ts desc, s.id desc limit 1;
$$;

comment on function palox_letzter_stand(station) is
  'Was zuletzt auf der Palox-Waage DIESER Station stand. Die Eingabemaske '
  'zieht das vom neuen Stand ab, damit niemand im Kopf rechnen muss.';

-- ---------- Die Ablesungen der Reihe nach, je Station ---------------------
create or replace view v_palox_stand with (security_invoker = true) as
select s.id, s.auftrag_id, s.ts, s.palox_stand_kg, s.kg,
       lag(s.palox_stand_kg) over w                                as vorher,
       case
         when s.palox_geleert then s.palox_stand_kg
         when lag(s.palox_stand_kg) over w is null then s.palox_stand_kg
         when s.palox_stand_kg < lag(s.palox_stand_kg) over w then s.palox_stand_kg
         else s.palox_stand_kg - lag(s.palox_stand_kg) over w
       end                                                          as differenz,
       (s.palox_geleert
        or (lag(s.palox_stand_kg) over w is not null
            and s.palox_stand_kg < lag(s.palox_stand_kg) over w))   as zwischendurch_geleert,
       a.station
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
 where s.palox_stand_kg is not null and s.gemessen
window w as (partition by a.station order by s.ts, s.id)
 order by a.station, s.ts, s.id;

comment on view v_palox_stand is
  'Die Waagenstände je Station der Reihe nach, mit der jeweils daraus '
  'folgenden Menge. zwischendurch_geleert: der Stand ist gefallen oder der '
  'Arbeiter hat das Leeren gemeldet — dann gilt der neue Stand als Menge.';

grant execute on function palox_letzter_stand(station) to authenticated;
grant select on v_palox_stand to authenticated;


-- =====================================================================
-- aus 0033_naechste_charge.sql
-- =====================================================================

-- =====================================================================
-- 0033 — Welche Charge sollte als nächstes verarbeitet werden?
--
-- Die Frage stellt sich der Betriebsleiter jede Woche, und die Daten geben
-- sie her: Für jede Charge mit Bestand lässt sich beziffern, was zwei
-- weitere Wochen Liegenlassen voraussichtlich kosten — Verdunstung nach der
-- Sortenrate, Verderb nach dem angepassten Verlaufsmodell. Die Reihenfolge
-- dieser Zahlen ist die Antwort.
--
-- Zwei Ehrlichkeiten gehören dazu:
--
-- * Der Verderbszuwachs ist bedingt gerechnet — auf die Ware, die bis heute
--   durchgehalten hat: (F(t+14) − F(t)) / (1 − F(t)). Ohne die Bedingung
--   würde bereits verdorbene Masse ein zweites Mal verderben.
-- * Wo das Alter der Charge jenseits der längsten gemessenen Lagerdauer
--   liegt, ist die Zahl hochgerechnet, nicht gemessen — die Spalte
--   hochgerechnet sagt es, und das Dashboard zeigt es an.
--
-- Das Verlaufsmodell wird einmal je Abfrage gerechnet (materialisierte CTE),
-- nicht einmal je Charge — sonst stünden hier 40 Regressionen je Aufruf.
-- =====================================================================

create or replace view v_naechste_charge with (security_invoker = true) as
with modell as materialized (
  select * from v_schimmel_modell
),
bestand as (
  select b.charge_nr, b.sorte, b.schlag, b.lager_kg,
         -- Nie negativ: eine Demo- oder Testsaison kann in der Zukunft
         -- liegen, und ein negatives Alter ergäbe negative Verluste.
         greatest(b.alter_lager_heute, 0)                      as alter_tage,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05)      as r
    from v_hochrechnung_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
   where b.lager_kg > 0
),
mit_f as (
  select b.*,
         -- Masse heute: Eingang der liegenden Ware, um die Verdunstung bis
         -- heute vermindert.
         b.lager_kg * power(1 - b.r, greatest(b.alter_tage, 0)) as masse_jetzt_kg,
         case when m.brauchbar then least(greatest(
           1 - exp(-exp(least(greatest(
             m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage, 1))
           , -40), 3))), 0), 0.99) end                          as f_jetzt,
         case when m.brauchbar then least(greatest(
           1 - exp(-exp(least(greatest(
             m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage + 14, 1))
           , -40), 3))), 0), 0.99) end                          as f_dann,
         (m.brauchbar and b.alter_tage > m.t_max)               as hochgerechnet,
         m.brauchbar                                            as modell_gilt
    from bestand b cross join modell m
)
select charge_nr, sorte, schlag,
       lager_kg::numeric(14,2),
       round(alter_tage)::int                                   as alter_tage,
       masse_jetzt_kg::numeric(14,2),
       (masse_jetzt_kg * (1 - power(1 - r, 14)))::numeric(12,1) as verdunstung_14_kg,
       (case when modell_gilt
             then masse_jetzt_kg * (f_dann - f_jetzt) / nullif(1 - f_jetzt, 0)
             else null end)::numeric(12,1)                      as schimmel_14_kg,
       (masse_jetzt_kg * (1 - power(1 - r, 14))
        + coalesce(masse_jetzt_kg * (f_dann - f_jetzt) / nullif(1 - f_jetzt, 0), 0)
       )::numeric(12,1)                                         as verlust_14_kg,
       hochgerechnet, modell_gilt
  from mit_f
 order by verlust_14_kg desc nulls last;

comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Die '
  'Reihenfolge beantwortet, was als nächstes verarbeitet gehört. '
  'schimmel_14_kg ist NULL, solange das Verlaufsmodell nicht trägt — dann '
  'steht die Antwort nur auf der Verdunstung.';

grant select on v_naechste_charge to authenticated;


-- =====================================================================
-- aus 0034_demo_knopf.sql
-- =====================================================================

-- =====================================================================
-- 0034 — Demo-Saison auf Knopfdruck
--
-- Bisher lag die Demo-Saison als SQL-Datei herum: kopieren, im
-- Supabase-SQL-Editor einfügen, Run — und zum Aufräumen nochmal dasselbe
-- mit einer zweiten Datei. Das ist ein Umweg über ein Werkzeug, das mit der
-- App nichts zu tun hat, und niemand macht ihn zweimal freiwillig.
--
-- Hier werden daraus zwei Funktionen, die die App direkt aufrufen kann.
-- Derselbe Inhalt, dieselben Zahlen — nur eben ein Knopf statt eines
-- Ausflugs ins Dashboard des Datenbank-Anbieters. Die beiden SQL-Dateien
-- rufen ab jetzt nur noch diese Funktionen auf, damit es die Saison nicht
-- an zwei Orten gibt, die auseinanderlaufen können.
--
-- SICHERHEIT
--
-- Beide Funktionen laufen als "security definer", also mit den Rechten des
-- Eigentümers und damit an den Zeilenregeln vorbei. Das ist nötig, weil die
-- Demo Dinge tut, die im Alltag niemand darf: Arbeiten rückdatieren,
-- abgeschlossene Aufträge anlegen, Messungen im Namen anderer erfassen.
-- Das Tor davor ist die Prüfung auf den Betriebsleiter, gleich in der ersten
-- Zeile — ein Arbeiter kommt hier nicht durch.
-- =====================================================================

create or replace function demo_daten_laden()
returns text language plpgsql security definer set search_path = public as $fn$
begin
  -- Aus der App darf das nur der Betriebsleiter. Im SQL-Editor gibt es keinen
  -- Login (auth.uid() ist NULL) — wer dort sitzt, hat ohnehin vollen Zugriff
  -- auf die Datenbank, da wäre die Prüfung nur Theater.
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter laden.';
  end if;

  if exists (select 1 from palette where extern_id like 'demo-%') then
    raise exception E'Die Demo-Saison ist schon geladen.\n'
      'Zum Neuladen zuerst entfernen.';
  end if;

  declare v_wer uuid := auth.uid();
  begin
    -- Aus der App heraus ist jemand angemeldet und gilt als Erfasser. Im
    -- SQL-Editor gibt es keinen Login, auth.uid() ist dort NULL — und alle
    -- Erfasser-Spalten sind NOT NULL. Dann tritt der Betriebsleiter ein.
    if v_wer is null then
      select id into v_wer from profil where rolle = 'admin' order by erstellt_ts limit 1;
    end if;
    if v_wer is null then
      select id into v_wer from profil order by erstellt_ts limit 1;
    end if;
    if v_wer is null then
      raise exception E'Es gibt noch kein Benutzerkonto.\n'
        'Lege zuerst dein Betriebsleiter-Konto an (README, Schritt 7) '
        'und versuche es dann nochmal.';
    end if;
    -- Beide Schreibweisen setzen: Supabase liest je nach Version die eine oder
    -- die andere, und auth.uid() muss hier einen Wert liefern.
    perform set_config('request.jwt.claim.sub', v_wer::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_wer)::text, true);
  end;

  declare
    v_chargen int[] := array[1613, 1614, 1616, 1606, 1611, 1626, 1630, 1635, 1647, 1650];
    v_charge  int;
    v_i       int;
    v_p       int;
    v_n_pal   int;
    v_datum   date;
    v_brutto  numeric;
    v_kisten  int;
    v_art     text;
    v_auftrag bigint;
    v_lauf    int;
    v_start   timestamptz;
    v_tage    int;
    v_netto   numeric;
    v_masse   numeric;
    v_rate    numeric := 0.0006;      -- Verdunstung je Tag
    v_wiegung bigint;
    v_klein   numeric;
    v_gross   numeric;
    v_schimmel numeric;
    v_anteil  numeric;
  begin
    -- ---------- Wareneingang: 10 Chargen, gestaffelt eingelagert ----------
    foreach v_charge in array v_chargen loop
      v_i := array_position(v_chargen, v_charge);
      v_n_pal := 30 + (v_i * 13) % 40;               -- 30 bis 69 Paletten
      for v_p in 1 .. v_n_pal loop
        -- Einlagerung über zwei bis drei Wochen verteilt
        v_datum  := date '2026-09-01' + ((v_i - 1) * 5) + (v_p * 17) % 18;
        v_brutto := 900 + ((v_i * 7 + v_p * 11) % 90);
        v_kisten := 36 + (v_p % 5);
        v_art    := case when (v_i + v_p) % 7 = 0 then 'IFCO 6416' else 'G2' end;
        insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
        values (v_charge, v_datum, v_brutto, v_kisten, v_art,
                format('demo-%s-%s', v_charge, v_p));
      end loop;
    end loop;

    -- ---------- Verarbeitung: Aufträge über Oktober bis Februar ----------
    foreach v_charge in array v_chargen loop
      v_i := array_position(v_chargen, v_charge);

      for v_lauf in 1 .. 2 loop
        -- Erster Lauf früh, zweiter deutlich später — so entstehen kurze und
        -- lange Lagerdauern und die Schimmelkurve bekommt mehrere Stützstellen.
        v_start := (date '2026-10-15' + ((v_i - 1) * 6) + (v_lauf - 1) * 55)::timestamptz
                   + interval '8 hours';

        -- Ungerade Chargen über die Maschine, gerade von Hand — beide Wege belegt
        if (v_i + v_lauf) % 2 = 1 then
          insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
          values ('maschine', 'sortieren', v_charge, v_start,
                  v_start + interval '6 hours', 'abgeschlossen', 'DEMO')
          returning id into v_auftrag;
        else
          insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
          values ('hand', 'waschen_sortieren', v_charge, v_start,
                  v_start + interval '7 hours', 'abgeschlossen', 'DEMO')
          returning id into v_auftrag;
        end if;

        -- Paletten zählen: 8 bis 20 Stück je Lauf, mit Datum vom Zettel
        v_n_pal := 8 + (v_i * 3 + v_lauf * 5) % 13;
        insert into auftrag_palette (auftrag_id, eingangsdatum)
        select v_auftrag, p.eingangsdatum
          from (select eingangsdatum from palette
                 where charge_nr = v_charge order by eingangsdatum
                 offset (v_lauf - 1) * 15 limit v_n_pal) p;

        -- Wie viel Masse hat dieser Lauf bewegt, und wie alt war sie?
        -- Direkt aus der Palettenzuordnung gerechnet, nicht aus v_auftrag_masse:
        -- die ist seit 0016 eine gespeicherte Ansicht und mitten im Anlegen noch
        -- leer. Der frühere Leseversuch dort traf NULL, und das stille
        -- »continue« übersprang sämtliche Messungen der Demo — deshalb zeigte
        -- die Auswertung 0.0 t Verdunstung und ein Modell aus sechs Punkten.
        select sum(m.netto_kg),
               sum((v_start::date - m.eingangsdatum) * m.netto_kg) / nullif(sum(m.netto_kg), 0)
          into v_masse, v_tage
          from v_auftrag_palette_masse m where m.auftrag_id = v_auftrag;
        if v_masse is null or v_tage is null then continue; end if;

        -- ---------- Schimmel: wächst mit der Lagerdauer ----------
        v_anteil := case when v_tage <  30 then 0.010
                         when v_tage <  60 then 0.020
                         when v_tage <  90 then 0.033
                         when v_tage < 120 then 0.045
                         else                   0.058 end;
        v_schimmel := round(v_masse * power(1 - v_rate, v_tage) * v_anteil);
        if v_schimmel > 0 then
          insert into schimmel_messung (auftrag_id, kg) values (v_auftrag, v_schimmel::int);
        end if;

        -- ---------- Eine Palette wiegen (nur auf der Hand-Linie) ----------
        if (v_i + v_lauf) % 2 = 0 then
          select brutto_kg, kisten, gebindeart, eingangsdatum
            into v_brutto, v_kisten, v_art, v_datum
            from palette where charge_nr = v_charge
            order by eingangsdatum offset (v_lauf - 1) * 15 limit 1;

          v_netto := v_brutto - v_kisten * 1.5 - 25;
          insert into verdunstung_wiegung (auftrag_id, charge_nr, eingangsdatum,
                 brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart,
                 kuerbisse_pro_kiste, wiege_ts)
          values (v_auftrag, v_charge, v_datum, v_brutto,
                  -- Mit Streuung je Wägung (±20 % auf die Rate): echte Paletten
                  -- verdunsten verschieden schnell, und ein Demo-Bereich von
                  -- ±0.1 % lehrte den Betriebsleiter eine falsche Sicherheit.
                  round((v_netto * power(1 - v_rate * (0.8 + random() * 0.4),
                                         v_start::date - v_datum)
                         + v_kisten * 1.5 + 25)::numeric, 1),
                  v_kisten, v_art, 4 + (v_i % 3), v_start)
          returning id into v_wiegung;

          update auftrag_palette set wiegung_id = v_wiegung, eingangsdatum = v_datum
           where id = (select min(id) from auftrag_palette where auftrag_id = v_auftrag);

          -- ---------- Ausschuss nach Augenmass ----------
          v_klein := round(v_masse * 0.030);
          v_gross := round(v_masse * 0.015);
          insert into ausschuss_messung (auftrag_id, art, kg)
          values (v_auftrag, 'zu_klein', v_klein::int), (v_auftrag, 'zu_gross', v_gross::int);

          -- ---------- Fertige Palette: 8.2 bis 8.4 kg je Kiste ----------
          insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten,
                 gebindeart, kuerbisse_pro_kiste)
          values (v_auftrag, v_charge,
                  round((32 * (8.20 + (v_i % 3) * 0.10) + 32 * 1.5 + 25)::numeric, 1),
                  32, 'G2', 4);
        end if;
      end loop;
    end loop;

    raise notice 'Demo: Wareneingang und Verarbeitung angelegt';
  end;

  -- ---------- Weg 1, zweiter Abschnitt: Waschen ----------------------------
  -- Spec §3: Lager → Sortieren → **Lager** → Waschen. Zwischen den beiden
  -- Schritten liegen Wochen, in denen die Ware in Kaliber-Kisten weiter
  -- verdunstet und verdirbt. Ohne diese Aufträge sieht der Betriebsleiter den
  -- zweiten Lagerabschnitt nie — und die Demo zeigt eine Welt, die es so nicht
  -- gibt.
  declare v record; v_neu bigint; v_i int := 0;
  begin
    -- v_auftrag_masse ist eine gespeicherte Ansicht. Innerhalb dieser einen
    -- Transaktion kennt sie die eben angelegten Aufträge noch nicht — ohne
    -- Neuberechnung liefe die Schleife ins Leere und die Demo wäre still
    -- unvollständig.
    perform auswertung_aktualisieren();
    for v in
      select a.id, a.charge_nr, a.start_ts, m.eingang_netto_kg
        from auftrag a
        join v_auftrag_masse m on m.auftrag_id = a.id
       where a.bemerkung = 'DEMO' and a.station = 'sortieren'
         and m.eingang_netto_kg is not null
       order by a.id
    loop
      v_i := v_i + 1;
      -- Zwei Drittel sind inzwischen gewaschen, der Rest wartet noch.
      exit when v_i > 6;
      insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status,
                           durchsatz_kg, bemerkung)
      values ('maschine', 'waschen', v.charge_nr,
              v.start_ts + (35 + v_i * 7) * interval '1 day',
              v.start_ts + (35 + v_i * 7) * interval '1 day' + interval '7 hours',
              'abgeschlossen',
              round(v.eingang_netto_kg * 0.90, 2), 'DEMO')
      returning id into v_neu;

      -- Schimmel #2: was seit dem Sortieren dazugekommen ist. Der Palox steht
      -- auf der Waage, deshalb Stand und Differenz.
      insert into schimmel_messung (auftrag_id, kg, palox_stand_kg)
      values (v_neu, round(v.eingang_netto_kg * 0.004)::int,
              round(v.eingang_netto_kg * 0.004, 1));
    end loop;
    raise notice 'Demo: zweiter Lagerabschnitt (Waschen) angelegt';
  end;

  -- ---------- Lagerkontrollen ----------------------------------------------
  -- Ein paar zufällig gegriffene Paletten, wie sie der neue Bildschirm
  -- „Palette kontrollieren" erfasst: ohne Arbeit, mit Pflichtfeld „davon faul".
  -- Damit zeigt die Demo auch den Selektionsvergleich mit echtem Befund.
  declare v record; v_i int := 0; v_netto numeric; v_tage int; v_faul numeric;
          v_kontrolltag date;
  begin
    for v in
      select p.charge_nr, p.eingangsdatum, p.brutto_kg, p.kisten, p.gebindeart
        from palette p order by p.id offset 40
    loop
      v_i := v_i + 1;
      exit when v_i > 8;
      -- Der Kontrolltag muss IN der Demo-Saison liegen (Sep 2026 – Mär 2027),
      -- nicht am heutigen Datum: die Demo spielt in der Zukunft, und
      -- current_date ergäbe negative Lagertage.
      v_kontrolltag := date '2027-02-20' - (v_i * 9);
      v_netto := v.brutto_kg - v.kisten * 1.5 - 25;
      v_tage  := greatest(v_kontrolltag - v.eingangsdatum, 1);
      -- Faulanteil grob nach Alter, zwei Kontrollen ohne Befund (0 ist eine
      -- echte Antwort, kein leeres Feld)
      v_faul  := case when v_i % 4 = 0 then 0
                      else round(v_netto * least(v_tage, 200) * 0.00018, 1) end;
      insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg,
             brutto_jetzt_kg, kisten, gebindeart, wiege_ts, faul_kg,
             sichtbar_schimmel, bemerkung)
      values (v.charge_nr, v.eingangsdatum, v.brutto_kg,
              round((v_netto * power(0.9994, v_tage) + v.kisten * 1.5 + 25)::numeric, 1),
              v.kisten, v.gebindeart,
              v_kontrolltag, v_faul, v_faul > 0, 'DEMO-KONTROLLE');
    end loop;
    raise notice 'Demo: Lagerkontrollen angelegt';
  end;

  -- ---------- Warenausgang -------------------------------------------------
  -- Ohne ihn ist der Restbestand eine Hochrechnung, die niemand nachgezählt hat,
  -- und die Bilanz kann nichts prüfen (Spec §9).
  declare v record; v_i int := 0;
  begin
    perform auswertung_aktualisieren();
    for v in
      select b.charge_nr, b.sorte, b.ausgelagert_kg
        from v_hochrechnung_basis b
       where b.ausgelagert_kg > 0 order by b.ausgelagert_kg desc
    loop
      v_i := v_i + 1;
      -- Der grösste Teil geht als Verkauf raus, in Kilo wie auf dem Lieferschein.
      insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
      values (current_date - (v_i * 5), v.charge_nr, v.sorte,
              round(v.ausgelagert_kg * 0.80, 2), 'verkauf',
              case when v_i % 2 = 0 then 'Grosshandel Zürich' else 'Genossenschaft' end,
              'DEMO');
      -- Ein kleiner Teil in Kisten — damit die Umrechnung sichtbar wird.
      if v_i % 3 = 0 then
        insert into lieferung (datum, sorte, kisten, ziel, kunde, bemerkung)
        values (current_date - (v_i * 5) + 1, v.sorte,
                greatest(round(v.ausgelagert_kg * 0.05 / 8)::int, 1), 'verkauf',
                'Hofladen Wetzikon', 'DEMO');
      end if;
    end loop;
    raise notice 'Demo: Warenausgang angelegt';
  end;

  -- ---------- Sortier-CSVs für drei Maschinen-Läufe ------------------------
  -- Histogramm statt Einzelzeilen (so speichert die App es auch). Die Verteilung
  -- ist grob glockenförmig um 900 g, mit Ausläufern unter der Sorten-Grenze und
  -- über 2000 g — daraus entstehen Ausschuss- und Nebenkanal-Anteil.
  declare
    v_auftrag bigint;
    v_charge  int;
    v_masse   numeric;
    v_hist    jsonb;
    v_n       int;
    v_r       record;
  begin
    for v_r in
      select a.id, a.charge_nr, a.start_ts, m.eingang_netto_kg, m.lagertage
        from auftrag a
        join v_auftrag_masse m on m.auftrag_id = a.id
       where a.bemerkung = 'DEMO' and a.station = 'sortieren'
         and m.eingang_netto_kg is not null and m.lagertage is not null
       order by a.id limit 3
    loop
      -- Die CSV soll das wiegen, was am Band ankommt: Eingang minus Verdunstung
      -- minus Schimmel. Nur dann ist die Massenbilanz eine echte Probe und nicht
      -- bloss ein Vergleich zweier unabhängiger Erfindungen.
      v_masse := v_r.eingang_netto_kg
                 * power(1 - 0.0006, v_r.lagertage)
                 * (1 - case when v_r.lagertage <  30 then 0.010
                             when v_r.lagertage <  60 then 0.020
                             when v_r.lagertage <  90 then 0.033
                             when v_r.lagertage < 120 then 0.045
                             else                          0.058 end);
      -- Das Histogramm unten wiegt im Mittel 1.075 kg je Kürbis
      v_n := greatest((v_masse / 1.075)::int, 100);

      v_hist := jsonb_build_array(
        jsonb_build_array( 350, (v_n * 0.010)::int),   -- unter 500 g → Verlust
        jsonb_build_array( 450, (v_n * 0.020)::int),
        jsonb_build_array( 650, (v_n * 0.120)::int),
        jsonb_build_array( 850, (v_n * 0.260)::int),
        jsonb_build_array(1050, (v_n * 0.280)::int),
        jsonb_build_array(1350, (v_n * 0.190)::int),
        jsonb_build_array(1700, (v_n * 0.100)::int),
        jsonb_build_array(2150, (v_n * 0.020)::int)    -- ab 2000 g → Nebenkanal
      );

      perform csv_lauf_speichern(
        v_r.charge_nr,
        format('DEMO-%s-%s', v_r.charge_nr, to_char(v_r.start_ts, 'DD-MM-HH24-MI')),
        null, format('demo-pruefsumme-%s', v_r.id),
        v_r.start_ts + interval '90 minutes', 'dateiname',
        '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
        (v_n * 1.28)::int, 4, 9, (v_n * 0.27)::int,
        v_hist);
    end loop;
    raise notice 'Demo: Sortier-CSVs eingelesen';
  end;

  -- ---------- Zwei Sonderfälle, damit man sie einmal gesehen hat -----------
  declare v_auftrag bigint; v_charge int := 1611;
  begin
    -- (1) Eine abgebrochene Arbeit: taucht in keiner Auswertung auf,
    --     ist aber unter Stammdaten → Abgebrochene Arbeiten sichtbar.
    insert into auftrag (weg, station, charge_nr, start_ts, bemerkung)
    values ('hand', 'waschen_sortieren', v_charge, timestamptz '2026-11-03 09:00+01', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id) select v_auftrag from generate_series(1, 4);
    perform auftrag_abbrechen(v_auftrag, 'Falsche Charge gewählt');

    -- (2) Ein Zahlendreher: 4500 statt 450 kg Schimmel. Die Rechnung bleibt
    --     davon unberührt; das Dashboard meldet den Fund ganz oben.
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
    values ('hand', 'waschen_sortieren', v_charge, timestamptz '2026-11-10 08:00+01',
            timestamptz '2026-11-10 15:00+01', 'abgeschlossen', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, eingangsdatum from palette where charge_nr = v_charge
     order by eingangsdatum limit 6;
    insert into schimmel_messung (auftrag_id, kg) values (v_auftrag, 4500);

    raise notice 'Demo: Sonderfälle angelegt (abgebrochen, Zahlendreher)';
  end;
  return (
  select format('Demo-Saison steht: %s Paletten in %s Chargen, %s Arbeiten, %s Sortierläufe. '
                  || 'Eingang %s t. Jetzt in der App unter Auswertung anschauen.',
                  (select count(*) from palette where extern_id like 'demo-%'),
                  (select count(distinct charge_nr) from palette where extern_id like 'demo-%'),
                  (select count(*) from auftrag where bemerkung = 'DEMO'),
                  (select count(*) from sortier_lauf where datei_name like 'DEMO-%'),
                  (select round(sum(eingang_netto_kg) / 1000, 1) from v_charge_rueckgrat))
  );
end $fn$;

comment on function demo_daten_laden is
  'Legt die erfundene Demo-Saison an (Aufträge mit bemerkung = ''DEMO'', Paletten mit extern_id ''demo-…'', Sortierdateien ''DEMO-…''). Echte Daten bleiben unberührt.';

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
  delete from lieferung where bemerkung = 'DEMO';
  delete from auftrag where bemerkung = 'DEMO';

  delete from palette where extern_id like 'demo-%';

  perform auswertung_aktualisieren();
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
-- Rückmeldung im Ergebnisfenster
-- =====================================================================
select format('Fertig. Die Datenbank steht: %s Chargen, %s Sorten, %s Tabellen, %s Auswertungen. Weiter im README bei Schritt 4.',
              (select count(*) from charge),
              (select count(*) from sorte_kaliber),
              (select count(*) from pg_tables where schemaname = 'public'),
              (select count(*) from pg_views  where schemaname = 'public')) as ergebnis;
