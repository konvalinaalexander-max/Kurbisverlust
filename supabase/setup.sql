-- =====================================================================
-- Kürbis-Verlust-Tracking — das komplette Setup in einer Datei
--
-- ERZEUGT. Nicht von Hand ändern — Quelle ist supabase/migrations/*.sql,
-- zusammengefügt von supabase/setup_bauen.sh.
--
-- SO WIRD SIE BENUTZT
--   1. Diese Datei komplett markieren und kopieren (Strg+A, Strg+C).
--   2. Im Supabase-Dashboard links auf "SQL Editor".
--   3. In das große leere Feld einfügen (Strg+V).
--   4. Unten rechts auf "Run" klicken.
-- Das war alles. Kein zweiter Durchlauf, keine weitere Datei.
--
-- Unten im Ergebnisfenster muss danach eine Zeile stehen, die mit
-- "Fertig." beginnt und die Anzahl Chargen und Sorten nennt.
-- =====================================================================

-- Schutz vor dem versehentlichen zweiten Durchlauf: Das gesamte Skript
-- läuft in einer Transaktion, ein Abbruch hier ändert also gar nichts.
do $$
begin
  if to_regclass('public.charge') is not null then
    raise exception E'Das Setup wurde bereits eingespielt — es ist nichts zu tun.\n'
      'Es hat sich nichts geändert. Weiter geht es im README bei Schritt 3.';
  end if;
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
create type rolle            as enum ('admin', 'arbeiter');
create type verarbeitungsweg as enum ('maschine', 'hand');           -- Weg 1 / Weg 2
create type station          as enum ('sortieren', 'waschen', 'waschen_sortieren');
create type auftrag_status   as enum ('offen', 'abgeschlossen');
create type kuerbis_klasse   as enum ('verlust_klein', 'kaliber', 'nebenkanal', 'unklassiert');
create type marge_art        as enum ('nebenkanal', 'ueberfuellung');
create type ausschuss_art    as enum ('zu_klein', 'zu_gross');
create type zuordnung_status as enum ('auto', 'manuell', 'offen', 'mehrdeutig');

-- ---------- Benutzer & Rollen ----------------------------------------
create table profil (
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

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Stammdaten -----------------------------------------------
create table gebinde (
  art               text primary key,
  tara_kg_pro_kiste numeric(6,3),          -- NULL = unbekannt, nicht 0
  tara_kg_palette   numeric(6,3),
  bemerkung         text
);
comment on column gebinde.tara_kg_pro_kiste is
  'Leergewicht einer Kiste. NULL bedeutet "nicht erfasst" — Netto bleibt dann NULL statt falsch zu sein.';

create table sorte_kaliber (
  sorte           text primary key,
  verlust_unter   int  not null,           -- < diesem Gewicht = Verlust (weggeworfen)
  kaliber_baender jsonb not null,          -- [[300,800],[800,2000]] — Konvention [untere, obere)
  kanal_ab        int  not null default 2000,
  constraint kaliber_baender_ist_liste check (jsonb_typeof(kaliber_baender) = 'array')
);
comment on table sorte_kaliber is
  'Kaliber-Grenzen in Gramm. Die Anzahl Bänder variiert je Sorte (2–4) und ist bewusst nicht fix.';

create table charge (
  nr     int primary key,                  -- undurchsichtige ID, nicht fortlaufend
  schlag text not null,
  sorte  text not null references sorte_kaliber(sorte) on update cascade,
  saison int  not null,
  unique (schlag, sorte, saison)
);
comment on table charge is
  'Charge = Schlag × Sorte. Die Chargennummer ist der Join-Schlüssel des gesamten Systems.';

-- ---------- Wareneingang (Import aus der Journal-App) ------------------
create table palette (
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

create index on palette (charge_nr, eingangsdatum);

-- ---------- Auftrag ---------------------------------------------------
create table auftrag (
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
create index on auftrag (charge_nr, start_ts);
create index on auftrag (status, start_ts desc);

create table auftrag_teilnehmer (
  id             bigserial primary key,
  auftrag_id     bigint not null references auftrag(id) on delete cascade,
  profil_id      uuid   not null default auth.uid() references profil(id),
  beigetreten_ts timestamptz not null default now(),
  verlassen_ts   timestamptz
);
create unique index auftrag_teilnehmer_aktiv
  on auftrag_teilnehmer (auftrag_id, profil_id) where verlassen_ts is null;

-- Paletten zählen: eine Zeile je gezählter Palette (Spec §10 — Pflichtfeld).
create table auftrag_palette (
  id            bigserial primary key,
  auftrag_id    bigint not null references auftrag(id) on delete cascade,
  palette_id    bigint references palette(id),   -- falls die konkrete Palette bekannt ist
  eingangsdatum date,                            -- sonst: Datum vom Zettel
  erfasser      uuid not null default auth.uid() references profil(id),
  ts            timestamptz not null default now()
);
create index on auftrag_palette (auftrag_id);

-- ---------- Messungen --------------------------------------------------
-- Schimmel/Fäulnis: klein genug, um direkt gewogen zu werden (Spec §9).
create table schimmel_messung (
  id          bigserial primary key,
  auftrag_id  bigint not null references auftrag(id) on delete cascade,
  kg          int not null check (kg >= 0),      -- ganzzahlig (Spec §10)
  teilgewicht boolean not null default false,    -- Palox voll → Zwischenwägung
  gemessen    boolean not null default true,
  erfasser    uuid not null default auth.uid() references profil(id),
  ts          timestamptz not null default now(),
  bemerkung   text
);
create index on schimmel_messung (auftrag_id);

-- Ausschuss zu klein / zu gross nach Auge (nur Weg 2 — Weg 1 kommt aus der CSV).
create table ausschuss_messung (
  id         bigserial primary key,
  auftrag_id bigint not null references auftrag(id) on delete cascade,
  art        ausschuss_art not null,
  kg         int not null check (kg >= 0),
  gemessen   boolean not null default true,
  erfasser   uuid not null default auth.uid() references profil(id),
  ts         timestamptz not null default now(),
  bemerkung  text
);
create index on ausschuss_messung (auftrag_id, art);

-- Verdunstung: bester Messpunkt ist Weg 2 beim Herausholen aus dem Lager (Spec §3).
create table verdunstung_wiegung (
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
create index on verdunstung_wiegung (charge_nr, eingangsdatum);

-- Buch B: verschenkte Marge (Spec §2) — niemals mit dem Verlust-Buch mischen.
create table marge_messung (
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
create index on marge_messung (auftrag_id, art);

-- ---------- Sortier-CSV -------------------------------------------------
create table sortier_lauf (
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
create index on sortier_lauf (charge_nr, datei_zeit);
create index on sortier_lauf (zuordnung) where zuordnung in ('offen', 'mehrdeutig');

-- Bereinigte Einzelgewichte, lauflängenkodiert (gewicht_g → anzahl).
-- Verlustfrei gegenüber "eine Zeile je Kürbis": die Reihenfolge wird nach der
-- Dubletten-Reinigung nicht mehr gebraucht, das Gewicht hat 2-g-Auflösung.
-- Spart auf der Supabase-Gratis-Stufe rund 90 % Speicher. v_sortier_kuerbis
-- expandiert die Zeilen wieder, falls doch pro Kürbis gerechnet werden soll.
create table sortier_gewicht (
  lauf_id     bigint not null references sortier_lauf(id) on delete cascade,
  gewicht_g   int    not null,
  anzahl      int    not null check (anzahl > 0),
  klasse      kuerbis_klasse not null,
  kaliber_idx int,                     -- Index im Bänder-Array, NULL außerhalb der Kaliber
  primary key (lauf_id, gewicht_g)
);
create index on sortier_gewicht (lauf_id, klasse);

-- ---------- Einstellungen ------------------------------------------------
create table einstellung (
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
-- Rückmeldung im Ergebnisfenster
-- =====================================================================
select format('Fertig. %s Chargen und %s Sorten angelegt, %s Tabellen und %s Auswertungen erstellt. Weiter im README bei Schritt 3.',
              (select count(*) from charge),
              (select count(*) from sorte_kaliber),
              (select count(*) from pg_tables where schemaname = 'public'),
              (select count(*) from pg_views  where schemaname = 'public')) as ergebnis;
