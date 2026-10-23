-- 0122 — Wer im Perigon wie heisst; der Weg der Ware je Charge
--
-- WARUM
--
-- 1. Der Betrieb, 23. Oktober, mit der Liste der Perigon-Nummern: „Oettli
--    heisst leider im Bio-Perigon Inauen, bitte verknüpfen … wir arbeiten mit
--    Trüeb — ausser du findest Perigon, wo es Trüb heisst; schau, dass die App
--    mit beiden arbeitet. Es gibt nur einen: Trüb ist Trüeb."
--
--    Die Liste deckt sich mit dem, was 0051 eingetragen hat; neu sind 1719
--    (Oettli) = 199156 und 1763 (Trüeb) = 199158. Eingetragen wird, wo noch
--    keine Nummer steht; steht eine andere, sagt setup.sql es als Warnung —
--    vielleicht hat der Betriebsleiter sie unter Stammdaten schon berichtigt.
--    198976 steht in der Liste weiter bei 1649 und 1650 (siehe 3).
--
--    Ein Name, zwei Schreibweisen: schlag_alias hält, wie ein Schlag
--    anderswo heisst (Inauen, „Oettli, Inauen", Ötli → Oettli; Trüb, Trueb →
--    Trüeb). Der Abgleich mit dem Erntejournal (src/lib/import.ts) und die
--    Zuordnung über den Produzenten (3) lesen dieselbe Tabelle; der
--    Betriebsleiter ergänzt sie unter Stammdaten.
--
-- 2. Spalte X der Perigon-Datei (LiefProdAdrName) ist der Produzent der
--    Perigon-Charge. Wer dort wie heisst, lernt die App aus den Zeilen, deren
--    Nummer sie kennt (v_perigon_produzent): Ein Name, der nur bei Chargen
--    eines Schlags vorkommt, gehört zu diesem Schlag. Steht er bei mehreren
--    (der eigene Betrieb bei allen eigenen Feldern), lernt sie nichts daraus.
--
-- 3. Ein Lieferschein mit einer Nummer, die an keiner Charge steht, bekommt
--    seine Charge über den Produzenten, wenn das eindeutig ist: Der Produzent
--    gehört zu genau einem Schlag, und dieser Schlag hat in der Saison genau
--    eine Charge, deren Sorte zum Artikel passt. So die 11 Lieferscheine
--    „Butternut lose" mit 198977 (Produzent Sauter): Rümlang Sauter hat genau
--    eine Butternut-Charge, 1650. Jede solche Zuordnung steht mit ihrem Grund
--    in lieferung_nachordnung und als Hinweis in v_ungereimtheit
--    („nachgeordnet") — der Betriebsleiter sieht sie und trägt die Nummer
--    unter Stammdaten ein, dann steht es fest.
--
-- 4. Der Betrieb: „Aktuell ist noch nicht ganz klar, was jetzt von welcher
--    Charge war — ob der Eingang bei welcher Charge war, dann die Arbeit im
--    Lager bei welcher Charge und der Warenausgang bei welcher Charge; was
--    hast du schon umgebucht, was noch nicht, was würdest du wie umbuchen."
--
--    v_charge_spur legt je Charge die drei Stationen nebeneinander: herein
--    (Erntejournal, wie es dort steht, und was umgebucht wurde), bearbeitet
--    (Arbeiten in der Halle), hinaus (Perigon-Lieferscheine, nach Artikel).
--    v_ungereimtheit nennt bei „mehr verkauft als möglich", „vor dem
--    Eingang" und „nie eingegangen" die Chargen, von denen die Ware wohl kam
--    (kandidaten): derselbe Artikel, laut App noch Paletten da, höchstens die
--    Hälfte verkauft, eingegangen vor dem letzten Lieferschein — derselbe
--    Schlag und dieselbe Sorte zuerst. Umgebucht wird damit nichts: Ohne
--    Zettel ist es ein Vorschlag zum Zählen.

-- =====================================================================
-- 1. Die Perigon-Nummern der Planungsliste vom 23. Oktober
-- =====================================================================
do $$
declare r record; v_ist int; v_neu int := 0;
begin
  for r in select * from (values
    (1598, 198876), (1599, 198877), (1601, 198888), (1603, 198915), (1604, 198916),
    (1605, 198917), (1606, 198919), (1607, 198889), (1608, 198920), (1609, 198918),
    (1610, 198921), (1611, 198922), (1612, 198944), (1613, 198923), (1614, 198945),
    (1615, 198946), (1616, 198947), (1617, 198948), (1618, 198949), (1619, 198950),
    (1620, 198951), (1623, 198955), (1624, 198956), (1625, 198957), (1626, 198958),
    (1627, 198959), (1628, 198970), (1630, 198969), (1631, 198968), (1632, 198960),
    (1633, 198961), (1634, 198962), (1635, 198963), (1636, 198966), (1637, 198964),
    (1638, 198965), (1646, 198952), (1647, 198953), (1648, 198974), (1649, 198976),
    (1650, 198976), (1651, 198975), (1719, 199156), (1763, 199158)) v(nr, p)
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
end $$;

-- =====================================================================
-- 2. Ein Name, zwei Schreibweisen
-- =====================================================================
-- Vergleichsform wie src/lib/import.ts: Unicode zusammengesetzt (ein ü, das
-- als u + Trema ankommt, ist dasselbe ü), klein, Satzzeichen zu Leerzeichen.
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
  angelegt_ts timestamptz not null default now(),
  constraint schlag_alias_namen check (name_norm(alias) is not null and name_norm(schlag) is not null),
  constraint schlag_alias_nicht_sich_selbst check (name_norm(alias) <> name_norm(schlag))
);
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

-- Wer in Perigon Spalte X wie heisst: was der Betrieb gesagt hat (schlag_alias),
-- und was die App aus den Zeilen gelernt hat, deren Nummer sie kennt — ein
-- Name, der nur bei Chargen eines Schlags vorkommt.
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
comment on view v_perigon_produzent is
  'Wer in Perigon Spalte X (Produzent) wie heisst, und welcher Schlag das in der App ist (0122): quelle betrieb = schlag_alias; gelernt = aus den Zeilen, deren Chargennummer die App kennt, wenn der Name nur bei Chargen eines Schlags vorkommt.';
grant select on v_perigon_produzent to authenticated;

create or replace function schlag_von_produzent(p text) returns text
language sql stable security invoker set search_path = public as $$
  select coalesce(
    (select v.schlag from v_perigon_produzent v where v.produzent = name_norm(p) order by v.quelle limit 1),
    (select min(c.schlag) from charge c where name_norm(c.schlag) = name_norm(p)))
$$;
comment on function schlag_von_produzent(text) is
  'Der Schlag der App zu einem Namen aus Perigon Spalte X oder dem Journal: zuerst schlag_alias, dann gelernt, dann ein Schlag gleichen Namens; sonst null (0122).';
revoke all on function schlag_von_produzent(text) from public;
grant execute on function schlag_von_produzent(text) to authenticated;

-- =====================================================================
-- 3. Lieferscheine nachordnen: über die Nummer, sonst über den Produzenten
-- =====================================================================
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

-- =====================================================================
-- 4. Der Weg der Ware je Charge
-- =====================================================================
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
       (select jsonb_agg(jsonb_build_object('gruppe', coalesce(x.gruppe, 'andere'), 'kg', round(x.kg)) order by x.kg desc)
          from artikel x where x.nr = c.nr) as nach_artikel,
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
comment on view v_charge_spur is
  'Der Weg der Ware je Charge (0122): herein laut Erntejournal (journal_*: die Charge, die das Journal nennt) und wie die App jetzt zählt (paletten, eingang_kg), was umgebucht ist oder vorgeschlagen (weg: von hier weg, her: hierher), bearbeitet in der Halle (Arbeiten, mit Zahl der Zettel), hinaus laut Perigon (Lieferscheine, nach Artikelgruppe, davon nachgeordnet), und was laut App noch da ist (rest_paletten).';
grant select on v_charge_spur to authenticated;

-- =====================================================================
-- 5. v_ungereimtheit: woher die Ware wohl kam, und was nachgeordnet wurde
-- =====================================================================
-- Wie 0121, dazu:
--   kandidaten (bei ohne_eingang, vor_eingang, ueberzaehlung): Chargen
--     desselben Artikels, bei denen laut App noch Paletten stehen, die
--     höchstens zur Hälfte verkauft sind und die vor dem letzten
--     Lieferschein eingegangen waren — derselbe Schlag und dieselbe Sorte
--     zuerst, höchstens vier.
--   nachgeordnet: Lieferscheine, die ihre Charge über den Produzenten
--     bekamen (Hinweis — der Betriebsleiter trägt die Nummer ein; dann
--     steht es fest, und der Hinweis verschwindet).
-- Der Betrieb, 23. Oktober, zur Liste: „Rümlang Sauter 198976 1649 Butterkin,
-- Rümlang Sauter 198976 1650 Tiana — solche Sachen sind auch Auffälligkeiten,
-- die du ausweisen solltest; das sollte nicht sein. Such auch nach solcher
-- Art von Ungereimtheiten." Was im Chargenregister selbst nicht stimmt:
--   perigon_doppelt — eine Perigon-Nummer an mehreren Chargen; dazu, ob sie in
--     den Dateien überhaupt vorkommt, und welche Nummern dort stehen, die an
--     keiner Charge stehen, aber nah daneben liegen (±2) oder vom Produzenten
--     dieser Chargen kommen (verwandte) — bei 198976 ist das 198977.
--   ohne_perigon_nr — eine Charge der laufenden Saison mit Ware (Paletten oder
--     Lieferscheine), aber ohne Perigon-Nummer: Lieferscheine, die die
--     Perigon-Nummer tragen (die Datei der zweiten Firma), findet die App nicht.
--   schlag_zweimal — ein Schlag steht im Register unter einem Namen, den
--     schlag_alias einem anderen Schlag zuordnet (etwa „Trüb" neben „Trüeb"),
--     oder zwei Schläge heissen in der Vergleichsform gleich.
create or replace view v_stammdaten_pruefung with (security_invoker = true) as
with saison as (
  select max(c.saison) as s from charge c where exists (select 1 from palette p where p.charge_nr = c.nr)
), datei as (
  -- Nummern aus den Perigon-Dateien: wie oft, von wem (und welcher Schlag das ist, wie
  -- schlag_von_produzent(), aber v_perigon_produzent einmal gelesen statt je Nummer),
  -- welcher Artikel, und wohin die App sie heute zählt
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
comment on view v_stammdaten_pruefung is
  'Was im Chargenregister selbst nicht stimmt (0122): perigon_doppelt (eine Perigon-Nummer an mehreren Chargen, mit den verwandten Nummern aus den Dateien), ohne_perigon_nr (Charge der laufenden Saison mit Ware, ohne Perigon-Nummer), schlag_zweimal (ein Schlag unter zwei Namen).';
grant select on v_stammdaten_pruefung to authenticated;

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
comment on function ungereimt_kandidaten(int, date) is
  'Chargen, von denen die Ware einer Charge mit Ungereimtheit wohl kam (0122): derselbe Artikel, laut App noch Paletten, höchstens zur Hälfte verkauft, vor p_bis eingegangen; derselbe Schlag und dieselbe Sorte zuerst, höchstens vier.';
revoke all on function ungereimt_kandidaten(int, date) from public;
grant execute on function ungereimt_kandidaten(int, date) to authenticated;

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
  -- Wenige Kilo über dem Eingang sind die Unschärfe der gerechneten Ausbeute, keine Ungereimtheit:
  -- erst ab 100 kg und 3 % des Eingangs.
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
   -- Hat der Betriebsleiter die Nummer bei der Charge eingetragen, steht es fest: kein Hinweis mehr.
   and n.nummer is distinct from c.perigon_nr::text and n.nummer is distinct from c.nr::text
 group by n.charge_nr, c.sorte, c.schlag, c.perigon_nr
union all
select 'stammdaten', s.chargen[1], c.sorte, c.schlag, zahl(null::numeric, 2, 1e12)::numeric(14,2), cardinality(s.chargen), null::date, null::date,
       s.mehr || jsonb_build_object('pruefung', s.pruefung, 'chargen_nr', to_jsonb(s.chargen))
  from v_stammdaten_pruefung s
  join charge c on c.nr = s.chargen[1];
comment on view v_ungereimtheit is
  'Was zwischen Perigon, Erntejournal und Lager nicht zusammenpasst, je Charge oder Sorte, mit den Kilo, um die es geht (0121, 0122): ohne_eingang, vor_eingang, ueberzaehlung (mit kandidaten: Chargen, von denen die Ware wohl kam), ohne_charge, umgebucht, vorschlag, nachgeordnet (über den Produzenten zugeordnet), stammdaten (was im Chargenregister nicht stimmt, v_stammdaten_pruefung). Die Zeilen der Perigon-Dateien stehen in v_perigon_pruefung; der Weg der Ware je Charge in v_charge_spur.';
grant select on v_ungereimtheit to authenticated;

-- =====================================================================
-- 6. Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 122 $$;
