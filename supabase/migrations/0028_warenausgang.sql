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
