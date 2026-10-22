-- 0121 — Die Palette geht mit ihrer Arbeit; was im Lager liegt, Schritt für
--        Schritt; Ware ohne Charge
--
-- WARUM
--
-- 1. Der Betrieb, 22. Oktober: „aktuell zeigt's mir Rüegg Amoro immer noch
--    1 Tonne als verkaufsfähig — lösche das nur raus, wenn du dir sicher bist,
--    also nicht löschen, aber erzwinge es nicht, ausser es ist plausibel."
--
--    Was geschah (docs/ENTSCHEIDUNGEN.md, Runde AW): Das Erntejournal führt
--    am 23.9. sechs IFCO-Paletten Rüegg unter Amoro (Charge 1625). Am 1.10.
--    lief die Arbeit 1602 auf Charge 1627 (Rüegg · Fictor), die im Journal nie
--    eine Palette hatte; ihre fünf Zettel tragen genau die Gewichte von fünf
--    dieser Paletten (448, 444, 433, 433, 380 kg). Danach gingen 1.4 t als 1627
--    hinaus. Die App liess die sechs Paletten bei 1625 liegen — und zeigte dort
--    über eine Tonne, die längst verkauft war — und 1627 lieferte, was es nie
--    bekam.
--
--    Die Regel, die hier entscheidet, ist bewusst eng (paletten_zuordnen):
--    Eine Palette geht nur dann zur Charge ihrer Arbeit, wenn (a) mindestens
--    zwei Zettel dieser Arbeit, die in der eigenen Charge keine Palette
--    finden, aufs Kilo genau zu Paletten einer anderen Charge desselben
--    Schlags passen, Eingang höchstens drei Tage auseinander, (b) das
--    mindestens 80 % dieser Zettel sind und (c) die Charge der Arbeit mehr
--    ausgeliefert hat, als sie laut Journal je bekam. Eine Palette, die schon
--    eine Arbeit ihrer eigenen Charge gezählt hat, geht nirgends hin. Kamen
--    die Paletten als eine Fuhre (selber Tag, selbes Gebinde, mindestens drei)
--    und liegen 80 % davon nachweislich in der Arbeit, geht der Rest der
--    Fuhre mit. Passt weniger (die Hälfte und mehr, aber unter 80 %, oder
--    die Charge der Arbeit ist nicht überliefert), bleibt es ein Vorschlag:
--    nichts wird gebucht, die App zeigt es als Ungereimtheit.
--
--    Nichts wird gelöscht: Die Charge des Journals bleibt in
--    palette.charge_nr_journal stehen, jede Umbuchung mit ihrem Grund in
--    palette_zuordnung, und der Betriebsleiter nimmt sie mit einem Klick
--    zurück (palette_zuordnung_setzen). Ein neuer Abgleich mit dem Journal
--    überschreibt sie nicht (Trigger palette_charge_halten) — es sei denn, das
--    Journal nennt eine andere Charge als die, von der umgebucht wurde: Dann
--    hat der Betrieb dort berichtigt, und das Journal gilt.
--
-- 2. Der Betrieb: „bei Artikel und bei Chargen jeweils ausweisen, wie viele
--    Kilo im Lager sind — als Paletten — und daneben davon verkaufsfähig:
--    minus Verdunstung (mit Lagerdauer und täglicher Rate), minus Palox, minus
--    zu klein, zu gross … und vielleicht minus verschenkte Marge." Und: „was
--    mit Hagelschaden ist, wird nicht fortgeschmissen und ist auch nicht faul,
--    das wird anders verkauft — Unique, wie ein eigener Artikel, nur Knospe."
--
--    v_lager_ausweis legt die Kette je Charge an einer Stelle hin, aus den
--    Zahlen der Kaskade (erg_prognose, heute): die Eingangsmasse auf den
--    Paletten, die noch liegen; davon verdunstet; faul (Palox); Unique
--    (Hagel); zu klein und zu gross nach der Sortiermaschine; Faules beim
--    Abpacken; verkaufsfähig; und was davon als Überfüllung in den Kisten
--    mitgeht (Marge). Die Kaskade zählt den Hagel weiter im Palox-Anteil
--    (0116: f = 1 − (1 − f₀)·(1 − Hagel)), so steht er auch in jeder Messung
--    einer Hagel-Charge. Aus derselben Formel folgt der Hagel-Teil genau:
--    Hagel = gute Ware · Hagel / (1 − Hagel). Er ist kein Faules: Der Ausweis
--    nimmt ihn aus dem Palox heraus und zeigt ihn als Unique.
--
-- 3. Der Betrieb: „aktuell ist eine Meldung, es kennt Charge 1719 nicht — aber
--    inzwischen sollte es das ja kennen. Finde einen Weg, dass das korrekt
--    funktioniert." Ein Lieferschein, dessen Chargennummer beim Einlesen
--    noch keiner Charge gehörte, blieb ohne Charge, bis jemand die Datei neu
--    einlas. Jetzt löst jeder Rechenlauf solche Nummern noch einmal auf
--    (lieferungen_nachordnen): die eigene Nummer, sonst eine Perigon-Nummer,
--    die an genau einer Charge steht — wie beim Einlesen
--    (src/lib/warenausgang.ts, chargeAufloeser). Steht sie an mehreren,
--    bleibt die Zeile, wie sie ist; dann entscheidet beim Einlesen der
--    Artikel.
--
-- 4. Ware ohne Charge (v_ohne_charge): Lieferscheine ohne Chargennummer
--    verteilt die Rechnung nach dem Eingang auf die Chargen ihrer Sorte
--    (0114). Je Sorte steht jetzt da, wie viel das ist, auf welche Chargen es
--    fällt — und wie viel davon hinausging, bevor diese Chargen überhaupt
--    eingingen, oder auf gar keine Charge fällt.

-- =====================================================================
-- 1. Die Charge des Journals bleibt stehen
-- =====================================================================
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

-- Der Abgleich mit dem Journal schreibt charge_nr. Was er schreibt, ist die
-- Charge des Journals; gerechnet wird mit der Umbuchung, solange das Journal
-- noch die Charge nennt, von der umgebucht wurde. Nur paletten_zuordnen setzt
-- kuerbis.zuordnung = an — dann bleibt die Charge des Journals, wie sie ist.
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
-- Wie jede Funktion hier: nicht für Nichtangemeldete (pruefung.sql, Funktionsrechte).
revoke all on function palette_charge_halten() from public;
grant execute on function palette_charge_halten() to authenticated;
drop trigger if exists palette_charge_halten on palette;
create trigger palette_charge_halten before insert or update of charge_nr on palette
  for each row execute function palette_charge_halten();

-- =====================================================================
-- 2. Die Regel
-- =====================================================================
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

-- Der Betriebsleiter nimmt eine Umbuchung zurück — oder bucht einen Vorschlag.
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

-- =====================================================================
-- 2b. Lieferscheine, deren Charge die App inzwischen kennt
-- =====================================================================
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
comment on function lieferungen_nachordnen() is
  'Gibt Lieferscheinen ohne Charge ihre Charge, sobald die Nummer der Datei eine kennt (eigene Nummer, sonst eine Perigon-Nummer an genau einer Charge) — läuft zu Beginn jedes Rechenlaufs; gibt zurück, wie viele es waren (0121).';
revoke all on function lieferungen_nachordnen() from public;
grant execute on function lieferungen_nachordnen() to authenticated;

-- =====================================================================
-- 3. Der Rechenlauf ordnet zuerst zu (Schritt 1) — sonst wie 0119
-- =====================================================================
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

comment on function auswertung_schritt_intern(integer, boolean) is
  'Ein Schritt des Neurechnens (0078), wahlweise nebenläufig (0095). Beratungssperre je Aufruf (0100); der App-Weg merkt '
  'sich rechnet_seit, der Zeitplan-Weg fasst auswertung_stand erst am Ende an; je Ansicht wird die Dauer notiert '
  '(auswertung_laufzeit, 0103). Schritt 3 rechnet seit 0107 auch erg_palox_erwartung, seit 0116 vor der Kaskade die Gewichtsverteilung beim Eingang (mv_kaliber_eingang, mv_kaliber_quelle). Seit 0119 hält ein eindeutiger Index, den die Daten nicht mehr hergeben, die Rechnung nicht an: er wird entfernt und in auswertung_index_entfernt notiert. Seit 0121 ordnet Schritt 1 zuerst Lieferscheine (lieferungen_nachordnen) und Paletten (paletten_zuordnen) zu. Nur für den Betriebsleiter oder ohne Anmeldung.';

-- =====================================================================
-- 4. Was im Lager liegt, Schritt für Schritt (v_lager_ausweis)
-- =====================================================================
-- Je Charge mit Eingang, heute. Die Kette der Masse:
--   eingang_kg (auf den Paletten, die noch liegen, wie eingegangen)
--   − verdunstet_kg − faul_kg (Palox) − unique_kg (Hagel)
--   − zu_klein_kg − zu_gross_kg (Bänder der Sortiermaschine) − fax_kg
--   = verkaufsfaehig_kg;  davon marge_kg in den Kisten über dem Soll,
--   verrechenbar_kg der Rest.
-- Der Hagel: Die Kaskade rechnet f = 1 − (1 − f₀)·(1 − h) auf den Teilen,
-- an denen sie ihn anwendet (mv_kaskade.hagel > 0). Daraus genau: der
-- Hagel-Teil = gute Ware · h / (1 − h). Teile mit eigener Palox-Messung
-- tragen keinen angewendeten Hagel (die Messung sieht, was sie sieht) —
-- dort ist auch kein Unique abgeteilt.
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
              else 'nicht gewogen' end as marge_quelle
    from erg_charge c
    left join erg_prognose p on p.gruppe = 'charge' and p.schluessel = c.charge_nr::text and p.h = 0
    left join hagel_lager hl on hl.charge_nr = c.charge_nr
    left join marge_charge mc on mc.charge_nr = c.charge_nr
    left join marge_sorte ms on ms.sorte = c.sorte
), mit_hagel as (
  select b.*,
         case when b.gute_ware_kg is null then null
              when b.h <= 0 then 0::numeric
              when b.h >= 1 then null
              else b.gute_ware_kg * b.h / (1 - b.h) end as unique_kg
    from basis b
)
select m.charge_nr, m.sorte, m.schlag,
       m.paletten,
       zahl(coalesce(m.lager_kg, m.liegend_kg), 2, 1e12)::numeric(14,2) as eingang_kg,
       m.alter_tage,
       zahl(m.verdunstet_kg, 2, 1e12)::numeric(14,2) as verdunstet_kg,
       zahl(m.verdunstet_je_tag_kg, 2, 1e12)::numeric(14,2) as verdunstet_je_tag_kg,
       zahl(m.faul_mit_hagel_kg - coalesce(m.unique_kg, 0), 2, 1e12)::numeric(14,2) as faul_kg,
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
       zahl(m.hagel_ausgelagert + coalesce(m.unique_kg, 0), 2, 1e12)::numeric(14,2) as hagel_bis_heute_kg,
       coalesce(m.r_bekannt, false) as r_bekannt, coalesce(m.f_bekannt, false) as f_bekannt,
       coalesce(m.kanal_bekannt, false) as kanal_bekannt, coalesce(m.fax_bekannt, false) as fax_bekannt
  from mit_hagel m;
comment on view v_lager_ausweis is
  'Was im Lager liegt, Schritt für Schritt, je Charge heute (0121): eingang_kg (Eingangsmasse auf den Paletten, die noch liegen) − verdunstet − faul (Palox, ohne Hagel) − unique (Hagel, wird als Knospe verkauft) − zu klein − zu gross (Sortiermaschine) − Faules beim Abpacken = verkaufsfähig; davon marge_kg Überfüllung in den Kisten (marge_anteil = zu viel ÷ Soll, gewogen je Charge, sonst je Sorte; Stück-Kisten 0), verrechenbar_kg der Rest. hagel_bis_heute_kg: der Hagel-Teil im Faulen bis heute, kein Verlust. Aus erg_prognose (h = 0), erg_charge, mv_kaskade, erg_marge_charge.';
grant select on v_lager_ausweis to authenticated;

-- =====================================================================
-- 5. Ware ohne Charge (v_ohne_charge)
-- =====================================================================
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
comment on view v_ohne_charge is
  'Lieferscheine ohne Chargennummer bis heute (Verkauf, Marge), je Sorte (0121): wie viele, wie viel, von wann bis wann; auf welche Chargen die Rechnung sie verteilt (verteilt_auf, nach dem Eingang, 0114); kg_vor_eingang: was davon hinausging, bevor die Charge, die es tragen soll, eingegangen war; kg_ohne_ziel: was auf keine Charge fällt, weil keine Charge der Sorte Eingang hat (oder die Sorte fehlt).';
grant select on v_ohne_charge to authenticated;

-- =====================================================================
-- 6. Was zwischen Perigon und Lager nicht zusammenpasst (v_ungereimtheit)
-- =====================================================================
-- Der Betrieb: „so etwas wie 1627 — das hat Ausgang, aber keinen Eingang —
-- weis in der App auffällig darauf hin; generell sollte das wirklich
-- prominent sein, überall, wo wir Probleme mit dem Perigon haben." Und: „so,
-- dass ich als Laie die Problematik erkenne, zu meinem Chef gehen kann und
-- sagen: schau, das macht keinen Sinn."
--
-- Eine Zeile je Sache, die das Lager verfälscht — je Charge oder Sorte,
-- mit den Kilo, um die es geht. Die Zeilen der Perigon-Dateien selbst
-- (v_perigon_pruefung) bleiben, wie sie sind; die App stellt beides
-- zusammen. art:
--   ohne_eingang  — Lieferscheine auf eine Charge, die nie eine Palette hatte
--   vor_eingang   — Lieferscheine einer Charge vor ihrem ersten Eingang
--   ueberzaehlung — mehr geliefert, als der Eingang hergibt (erg_charge; ab 100 kg und 3 %)
--   ohne_charge   — Lieferscheine ohne Chargennummer, je Sorte (v_ohne_charge)
--   umgebucht     — Paletten, die die App mit Beleg umgebucht hat
--   vorschlag     — Paletten, die wohl zu einer anderen Charge gehören (Beleg zu schwach)
create or replace view v_ungereimtheit with (security_invoker = true) as
with lief as (
  select l.charge_nr, l.datum, l.masse_kg from v_lieferung_masse l
   where l.charge_nr is not null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge') and l.datum <= heute()
), eingang as (
  select charge_nr, min(eingangsdatum) as erst, count(*)::int as n from palette group by charge_nr
)
select 'ohne_eingang'::text as art, c.nr as charge_nr, c.sorte, c.schlag,
       zahl(sum(l.masse_kg), 2, 1e12)::numeric(14,2) as kg, count(*)::int as n, min(l.datum) as von, max(l.datum) as bis,
       null::jsonb as mehr
  from lief l join charge c on c.nr = l.charge_nr
 where not exists (select 1 from eingang e where e.charge_nr = l.charge_nr)
 group by c.nr, c.sorte, c.schlag
union all
select 'vor_eingang', c.nr, c.sorte, c.schlag,
       zahl(sum(l.masse_kg), 2, 1e12)::numeric(14,2), count(*)::int, min(l.datum), max(l.datum),
       jsonb_build_object('erster_eingang', e.erst)
  from lief l join eingang e on e.charge_nr = l.charge_nr join charge c on c.nr = l.charge_nr
 where l.datum < e.erst
 group by c.nr, c.sorte, c.schlag, e.erst
union all
select 'ueberzaehlung', b.charge_nr, b.sorte, b.schlag,
       zahl(b.ueberzaehlung_kg, 2, 1e12)::numeric(14,2), b.n_lieferungen, null::date, null::date,
       jsonb_build_object('geliefert_kg', round(b.geliefert_kg), 'eingang_kg', round(b.eingang_kg), 'ausgelagert_kg', round(b.ausgelagert_kg),
                          'eingang_von', b.eingang_von, 'eingang_bis', b.eingang_bis)
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
 group by z.stand, z.nach_charge_nr, z.von_charge_nr, z.auftrag_id, c.sorte, c.schlag;
comment on view v_ungereimtheit is
  'Was zwischen Perigon, Erntejournal und Lager nicht zusammenpasst, je Charge oder Sorte, mit den Kilo, um die es geht (0121): ohne_eingang, vor_eingang, ueberzaehlung, ohne_charge, umgebucht, vorschlag. Die Zeilen der Perigon-Dateien stehen in v_perigon_pruefung.';
grant select on v_ungereimtheit to authenticated;

-- =====================================================================
-- 7. Die Prüfung der Perigon-Zeilen in Sätzen für jemanden ohne Perigon
-- =====================================================================
-- Gleiche Zeilen wie 0118 — nur die Sätze: was komisch ist, in Worten, die
-- ohne Perigon-Kenntnis zu verstehen sind, und was zu tun ist.
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
       -- 0121: Kennt die App die Nummer inzwischen, holt der nächste Rechenlauf
       -- die Charge von selbst nach (lieferungen_nachordnen) — kein Neu-Einlesen mehr.
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
comment on view v_perigon_pruefung is
  'Seit 0121 in Sätzen, die ohne Perigon-Kenntnis zu lesen sind; eine Nummer, die die App inzwischen kennt, holt der nächste Rechenlauf nach. Was beim Durchsehen der Perigon-Zeilen der laufenden Saison auffällt (0116, 0118), je Zeile mit dem Satz, was zu tun ist: Charge nicht zugeordnet (eine Nummer, die die App nicht auflösen kann), Teil ohne Charge (die Datei schreibt den Chargen weniger zu, als die Position geliefert hat — 0118), Artikel passt nicht zur Sorte der gelieferten Charge, als Demeter verkauft und als Knospe geliefert, Lieferung vor dem ersten Eingang.';
grant select on v_perigon_pruefung to authenticated;

-- =====================================================================
-- 8. Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 121 $$;
