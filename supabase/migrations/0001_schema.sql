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
