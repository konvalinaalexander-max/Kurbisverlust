-- =====================================================================
-- Simulations-Harness, Teil 1: Gerüst
--
-- Zweck: Saisons erzeugen, deren wahre Koeffizienten wir selbst gesetzt haben.
-- Dann läuft die Auswertung darüber und wir können messen, statt zu glauben:
--   * Trifft die Schätzung, oder liegt sie systematisch daneben?
--   * Deckt der ausgewiesene Bereich den wahren Wert so oft, wie er behauptet?
--
-- Wichtig für die Aussagekraft: Die Simulation erzeugt die Welt so, wie sie
-- ist — nicht so, wie das Modell sie annimmt. Der Verdunstungsverlauf, die
-- Schimmelentwicklung und die Auswahl der verarbeiteten Paletten folgen hier
-- eigenen Regeln. Das Modell sieht davon nur, was ein Arbeiter erfassen würde.
-- =====================================================================

create schema if not exists sim;

-- Die wahren Parameter einer Simulationsrunde
create table if not exists sim.parameter (
  lauf              int primary key,
  r_basis           numeric,   -- wahre Verdunstung je Tag, Mittel über Sorten
  schimmel_lambda   numeric,   -- Schimmel: 1 − exp(−λ·t^k)
  schimmel_k        numeric,
  anteil_klein      numeric,
  anteil_gross      numeric,
  selektion         numeric,   -- 0 = zufällige Auswahl, 1 = Schlechtes zuerst
  n_wiegungen       int,       -- wie viele Palettenwägungen die ganze Saison
  n_lagerkontrollen int default 0, -- wie viele zufällig gegriffene Lagerpaletten
  anteil_sockel     numeric default 0, -- nicht lagerbedingt im Palox: Erde, Hagel, Schnitt
  bemerkung         text
);
alter table sim.parameter add column if not exists anteil_sockel numeric default 0;

-- Die wahren Einzelheiten jeder Palette dieser Runde. Das Modell sieht davon
-- nichts — nur die daraus abgeleiteten Erfassungen.
create table if not exists sim.palette_wahr (
  lauf              int,
  palette_id        bigint,
  charge_nr         int,
  sorte             text,
  eingangsdatum     date,
  netto_eingang_kg  numeric,
  r_wahr            numeric,        -- Verdunstung dieser Palette je Tag
  verarbeitet_am    date,           -- NULL = liegt am Stichtag noch im Lager
  weg               text,           -- 'maschine' = Weg 1 (zwei Abschnitte), 'hand' = Weg 2
  gewaschen_am      date,           -- Weg 1: wann sie den zweiten Abschnitt verlässt
  anfaelligkeit     numeric,        -- Schimmelneigung, 1.0 = Durchschnitt
  primary key (lauf, palette_id)
);

-- Die wahren Saisonsummen — der Massstab, an dem die Schätzung gemessen wird
create table if not exists sim.wahrheit (
  lauf             int,
  groesse          text,
  wert             numeric,
  primary key (lauf, groesse)
);

-- Was die Auswertung daraus gemacht hat
create table if not exists sim.schaetzung (
  lauf      int,
  groesse   text,
  mittel    numeric,
  unten     numeric,
  oben      numeric,
  primary key (lauf, groesse)
);

-- Wahre kumulative Schimmelfunktion: Anteil der Masse, der nach t Tagen
-- verdorben ist. Weibull-artig — anfangs wenig, dann beschleunigt.
create or replace function sim.schimmel_wahr(p_tage numeric, p_lambda numeric,
                                             p_k numeric, p_anfaelligkeit numeric)
returns numeric language sql immutable as $$
  select least(1 - exp(-p_lambda * power(greatest(p_tage, 0), p_k) * p_anfaelligkeit), 0.95);
$$;

create table if not exists sim.auftrag_wahr (
  lauf           int,
  auftrag_id     bigint,
  charge_nr      int,
  verarbeitet_am date,
  n_paletten     int,
  netto_eingang  numeric,
  m1             numeric,   -- Masse nach Verdunstung
  schimmel       numeric,   -- wahrer Schimmel dieser Arbeit
  sockel         numeric default 0,  -- nicht lagerbedingt im Palox (Erde, Hagel)
  primary key (lauf, auftrag_id)
);
alter table sim.auftrag_wahr add column if not exists sockel numeric default 0;

-- Ein Erfasser, damit die Aufträge einen Urheber haben. Ohne den lief der
-- Harness nur zufällig — auf einem frisch aufgesetzten Schema gab es keinen
-- Benutzer und saison.sql brach mit „null value in eroeffnet_von" ab.
insert into auth.users (id, email, raw_user_meta_data)
values ('55555555-5555-5555-5555-555555555555', 'simulation@example.org',
        '{"name":"Simulation"}'::jsonb)
on conflict (id) do nothing;
update profil set rolle = 'admin'
 where id = '55555555-5555-5555-5555-555555555555';
