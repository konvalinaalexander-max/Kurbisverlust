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
