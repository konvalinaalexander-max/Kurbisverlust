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

-- Die jeweils letzte Antwort je Arbeit und Schlüssel.
create or replace view v_auftrag_angabe with (security_invoker = true) as
select distinct on (auftrag_id, schluessel)
       auftrag_id, schluessel, wert, ts, erfasser
  from auftrag_angabe
 order by auftrag_id, schluessel, ts desc, id desc;
grant select on v_auftrag_angabe to authenticated;

-- ---------- Gemischte Chargen fallen aus dem Zeitmodell ---------------------
-- quelle bekommt einen dritten Wert: verarbeitung_gemischt. Das Modell und die
-- Treppe lesen nur verarbeitung und lager; die Massenbilanz liest v_auftrag_masse
-- und sieht davon nichts — die Menge zählt weiter.
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
 where a.station = 'waschen' and a.lagertage is not null
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

comment on view v_schimmel_punkte is
  'Alle Schimmelbeobachtungen als kumulativer Anteil F(t). quelle: '
  'verarbeitung (Palox, nach Aussehen ausgewählt), lager (zufällig gegriffene '
  'Palette), verarbeitung_gemischt (mehrere Chargen im Palox — das Alter ist '
  'geraten, der Punkt bleibt dem Zeitmodell fern).';

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
