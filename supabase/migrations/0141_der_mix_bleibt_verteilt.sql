-- 0141 — Der Mix bleibt nach Rezept verteilt (Runde BK)
--
-- Der Betrieb am 9. November: „Kann es sein, dass die, die nicht aufgehen,
-- Teil von Kürbis-Mixen sind?" Nachgesehen: Das Einlesen verteilt jeden Mix
-- nach dem Rezept (0131) — Butterkin füllt die Kiste, dazu 3 Orangita und
-- 3 Lekor; der Anteil einer anderen Sorte als die der genannten Charge geht
-- ohne Charge an seine Sorte (extern_id …:mix:<Sorte>). Beim Rechnen gibt
-- lieferungen_nachordnen() aber jedem Lieferschein ohne Charge die Charge,
-- die Perigon nennt — auch diesen Anteilen, und mit der Charge deren Sorte.
-- Im Betrieb standen so 112 Zeilen, 1'457 kg Lekor und 843 kg Orangita, als
-- Butterkin auf 1624 und 1649: Lekor und Orangita zu wenig abgezogen,
-- Butterkin zu viel. Die Perigon-Prüfung kannte die Mix-Anteile schon
-- (v_perigon_befund lässt …:mix: aus), nur das Nachordnen nicht.
--
-- Jetzt:
--   - Stufe 1 gibt einem Mix-Anteil die genannte Charge nur, wenn sie seine
--     Sorte ist (sonst bleibt er ohne Charge bei seiner Sorte). Der Rest einer
--     Mix-Position (…:rest:mix:<Sorte>) bekommt keine — wie jeder Rest
--     (…:rest), der keinen Chargenbezug hat.
--   - Stufe 0 holt zurück, was früher anders gesetzt wurde: ohne Charge, an
--     die Sorte aus der extern_id; der Eintrag in lieferung_nachordnung geht
--     mit. Das läuft zu Beginn jedes Rechenlaufs — nach setup.sql und
--     „Neu rechnen" stehen die 112 Zeilen wieder bei Lekor und Orangita.
--
--   - Die Liste der Lieferscheine ohne Charge (v_lieferung_ohne_charge) nennt
--     einen solchen Anteil „Mix-Anteil nach Rezept" (Grund mix), nicht mehr
--     „Nummer jetzt bekannt — bekommt die Charge von selbst".
--
-- Was bewusst nicht gemacht wurde:
-- - Ein Mix-Anteil ohne Charge geht weiter nach dem Eingang auf die Chargen
--   seiner Sorte (0114). Ob in Wirklichkeit eine Charge bevorzugt war, weiss
--   die App nicht; das ist eine Frage an den Betrieb.
-- - Stufe 2 (Produzent und Artikel) bleibt: sie lässt den Mix schon aus.

create or replace function lieferungen_nachordnen() returns int
language plpgsql security definer set search_path = public as $$
declare v_n int; v_m int; v_z int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Lieferscheine nachordnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- Stufe 0 (0141): Ein Mix-Anteil (extern_id …:mix:<Sorte>) ist die Ware seiner Sorte nach dem
  -- Rezept, ohne Charge. Stufe 1 hat ihm bis 0141 die Charge gegeben, die Perigon für den ganzen Mix
  -- nennt — und mit ihr deren Sorte (im Betrieb 2.3 t Lekor und Orangita als Butterkin 1624/1649).
  -- Was so auf einer Charge einer anderen Sorte steht, geht zurück: ohne Charge, an seine Sorte.
  with mix as (
    select l.id, substring(li.extern_id from ':mix:(.+)$') as sorte
      from lieferung l
      join lieferung_import li on li.lieferung_id = l.id
     where li.extern_id like '%:mix:%'
  ), zurueck as (
    update lieferung l set charge_nr = null, sorte = m.sorte
      from mix m
     where l.id = m.id and m.sorte is not null
       and (l.sorte is distinct from m.sorte
            or (l.charge_nr is not null
                and not exists (select 1 from charge c where c.nr = l.charge_nr and c.sorte = m.sorte)))
    returning l.id
  ), weg as (
    delete from lieferung_nachordnung n using zurueck z where n.lieferung_id = z.id
    returning 1
  )
  select count(*) into v_z from zurueck;

  -- Stufe 1 (0121): die eigene Nummer, sonst eine Perigon-Nummer an genau einer Charge.
  with offen as (
    select l.id, z.charge_extern, regexp_replace(z.charge_extern, '\D', '', 'g') as ziffern,
           substring(li.extern_id from ':mix:(.+)$') as mix_sorte
      from lieferung l
      join lieferung_import li on li.lieferung_id = l.id
      join ausgang_zeile z on z.id = li.zeile_id
     where l.charge_nr is null and li.extern_id not like '%:rest' and li.extern_id not like '%:rest:mix:%'
       and coalesce(z.charge_extern, '') ~ '\d'
  ), geloest as (
    select o.id, o.ziffern, o.mix_sorte,
           coalesce((select c.nr from charge c where c.nr::text = o.ziffern),
                    (select min(c.nr) from charge c where c.perigon_nr::text = o.ziffern
                      having count(*) = 1)) as charge_nr
      from offen o
  ), gesetzt as (
    update lieferung l set charge_nr = g.charge_nr, sorte = c.sorte
      from geloest g join charge c on c.nr = g.charge_nr
     where l.id = g.id and g.charge_nr is not null
       -- 0141: ein Mix-Anteil nur auf eine Charge seiner Sorte
       and (g.mix_sorte is null or c.sorte = g.mix_sorte)
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
     where l.charge_nr is null and li.extern_id not like '%:rest' and li.extern_id not like '%:rest:mix:%'
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
  return v_z + v_n + v_m;
end $$;
comment on function lieferungen_nachordnen() is
  'Gibt Lieferscheinen ohne Charge ihre Charge, sobald die Nummer der Datei eine kennt (eigene Nummer, sonst eine Perigon-Nummer an genau einer Charge, 0121) — oder, steht die Nummer an keiner Charge, wenn Produzent (Spalte X) und Artikel auf genau eine Charge der Saison zeigen (0122). Seit 0141 bekommt ein Mix-Anteil (extern_id …:mix:<Sorte>, nach Rezept verteilt) die genannte Charge nur, wenn sie seine Sorte ist; was früher auf eine Charge einer anderen Sorte ging, geht zuerst zurück (ohne Charge, an seine Sorte). Schreibt den Grund in lieferung_nachordnung; läuft zu Beginn jedes Rechenlaufs; gibt zurück, wie viele es waren.';
revoke all on function lieferungen_nachordnen() from public;
grant execute on function lieferungen_nachordnen() to authenticated;

-- ---------- Die Liste der Lieferscheine ohne Charge sagt es ----------
-- Ein Mix-Anteil einer anderen Sorte hiess dort „Nummer jetzt bekannt — bekommt die Charge von selbst";
-- das tut er nicht, und das ist richtig. Jetzt eigener Grund „mix"; der Rest einer Mix-Position ist ein Rest.
create or replace view v_lieferung_ohne_charge with (security_invoker = true) as
with l as (
  -- dieselben Lieferscheine wie v_ohne_charge (0121)
  select m.id, m.datum, m.sorte, m.kunde, m.masse_kg, m.bemerkung
    from v_lieferung_masse m
   where m.charge_nr is null and m.masse_kg > 0 and m.buch in ('verkauf', 'marge') and m.datum <= heute()
), mit as (
  select l.*, i.lieferung_id is not null as eingelesen, i.quelle, i.extern_id, coalesce(i.extern_id like '%:rest' or i.extern_id like '%:rest:mix:%', false) as rest,
         coalesce(i.extern_id like '%:mix:%', false) as mix_anteil,
         coalesce(z1.pos_id, case when split_part(i.extern_id, ':', 2) ~ '^\d+$' then split_part(i.extern_id, ':', 2)::bigint end) as pos_id,
         z1.charge_extern, regexp_replace(coalesce(z1.charge_extern, ''), '\D', '', 'g') as ziffern
    from l
    left join lieferung_import i on i.lieferung_id = l.id
    left join ausgang_zeile z1 on z1.id = i.zeile_id
), pos as (
  select m.*, p.n_zeilen, p.artikel, p.kg_position, p.nummern, p.kg_zugeteilt,
         (select x.nr from charge x where m.ziffern <> '' and x.nr::text = m.ziffern) as eigene,
         (select array_agg(x.nr order by x.nr) from charge x where m.ziffern <> '' and x.perigon_nr::text = m.ziffern) as an_perigon
    from mit m
    left join lateral (
      select count(*)::int as n_zeilen, min(z.artikel) as artikel, max(z.kg_position) as kg_position,
             string_agg(distinct nullif(btrim(z.charge_extern), ''), ', ' order by nullif(btrim(z.charge_extern), '')) as nummern,
             coalesce(sum(z.kg_charge) filter (where btrim(z.charge_extern) <> '' and z.kg_charge > 0), 0) as kg_zugeteilt
        from ausgang_zeile z
       where z.quelle = m.quelle and z.pos_id = m.pos_id
    ) p on m.eingelesen
), grund as (
  select p.*,
         -- Die Bemerkung, die das Einlesen setzt (lieferungenBauen), verrät Perigon auch dann,
         -- wenn die Verknüpfung zur Zeile fehlt — dann nie „von Hand".
         case when not p.eingelesen and (p.bemerkung = 'ohne Chargenbezug' or p.bemerkung like 'Charge % (extern)') then 'ohne_zeile'
              when not p.eingelesen then 'von_hand'
              when coalesce(p.n_zeilen, 0) = 0 then 'ohne_zeile'
              -- 0141: der Anteil einer anderen Sorte aus einem Mix bleibt ohne Charge, so ist er verteilt
              when p.mix_anteil and not p.rest and b.sorte is distinct from p.sorte and b.nr is not null then 'mix'
              when not p.rest and p.eigene is not null then 'nachholen'
              when not p.rest and cardinality(p.an_perigon) = 1 then 'nachholen'
              when not p.rest and cardinality(p.an_perigon) > 1 then 'mehrdeutig'
              when not p.rest then 'unbekannt'
              when p.nummern is null then 'keine_nummer'
              when p.kg_zugeteilt <= 0 then 'menge_null'
              else 'rest' end as grund,
         coalesce(p.eigene, case when cardinality(p.an_perigon) = 1 then p.an_perigon[1] end) as bekannt,
         case when p.nummern like '%,%' then 'die Chargen ' || p.nummern else 'die Charge ' || p.nummern end as chargen_text,
         b.sorte as bekannt_sorte
    from pos p
    left join charge b on b.nr = coalesce(p.eigene, case when cardinality(p.an_perigon) = 1 then p.an_perigon[1] end)
)
select g.id, g.datum, g.sorte, g.kunde,
       zahl(g.masse_kg, 2, 1e12)::numeric(14,2) as kg,
       g.quelle, g.pos_id, g.artikel,
       -- beim Rest einer Position alle Nummern der Position, sonst die der eigenen Zeile
       case when g.rest then g.nummern else coalesce(nullif(btrim(g.charge_extern), ''), g.nummern) end as nummer,
       g.grund,
       case g.grund
         when 'von_hand' then 'Von Hand in der App erfasst, ohne Charge — dazu gibt es keine Perigon-Zeile.'
         when 'ohne_zeile' then 'Aus Perigon eingelesen, aber die Zeile der Datei ist nicht mehr in der App.'
         when 'mix' then format('Mix-Anteil %s nach Rezept: Perigon nennt für den ganzen Mix %s, das ist Charge %s (%s). Der Anteil geht darum ohne Charge an %s und wird nach dem Eingang auf ihre Chargen verteilt.',
                                g.sorte, g.charge_extern, g.bekannt, g.bekannt_sorte, g.sorte)
         when 'nachholen' then format('Perigon nennt %s; die Nummer steht inzwischen an Charge %s — beim Einlesen kannte die App sie noch nicht.', g.charge_extern, g.bekannt)
         when 'mehrdeutig' then format('Perigon nennt %s; diese Perigon-Nummer steht an mehreren Chargen (%s), und der Artikel sagt nicht, an welcher.',
                                       g.charge_extern, array_to_string(g.an_perigon, ', '))
         when 'unbekannt' then format('Perigon nennt %s — diese Nummer steht an keiner Charge der App.', g.charge_extern)
         when 'keine_nummer' then 'In Perigon steht bei dieser Position keine Chargennummer (Spalte W „AuftragsChargeManuell" ist leer).'
         when 'menge_null' then format('Perigon nennt %s, teilt aber keine Menge zu (Spalte S „AufPosBatchQuantity Charge" ist 0) — die ganze Position bleibt ohne Charge.', g.chargen_text)
         else format('Perigon teilt %s nur %s von %s kg zu (Spalte S); der Rest hat keine Charge.', g.chargen_text,
                     to_char(round(g.kg_zugeteilt), 'FM999999990'), to_char(round(g.kg_position), 'FM999999990'))
       end as satz,
       case g.grund
         when 'von_hand' then 'Die Charge an der Lieferung nachtragen — oder den Lieferschein in Perigon führen und die Datei neu einlesen.'
         when 'ohne_zeile' then 'Die Datei unter Betrieb → Warenausgang neu einlesen.'
         when 'mix' then 'Nichts — so verteilt die App den Mix nach Rezept. Stimmt das Rezept nicht: Betrieb → Stammdaten → Sorten und Artikel, Karte „Kürbis Mix", danach die Dateien neu einlesen.'
         when 'nachholen' then 'Nichts — beim nächsten Rechnen („Neu rechnen" oben) bekommt der Lieferschein die Charge von selbst.'
         when 'mehrdeutig' then 'Unter Betrieb → Stammdaten → Chargen die Nummer nur bei der richtigen Charge lassen; beim nächsten Rechnen bekommt der Lieferschein sie.'
         when 'unbekannt' then 'Unter Betrieb → Stammdaten → Chargen bei der richtigen Charge als Perigon-Nr. eintragen; beim nächsten Rechnen bekommt der Lieferschein sie von selbst.'
         else 'In Perigon die Charge und die Menge je Charge (Spalten W und S) eintragen, dann die Datei unter Betrieb → Warenausgang neu einlesen.'
       end as tun
  from grund g;
comment on view v_lieferung_ohne_charge is
  'Jeder Lieferschein ohne Charge (0125) — dieselben wie v_ohne_charge: verkauft, mit Masse, bis heute — mit Firma und Position der Perigon-Zeile, Artikel, den Nummern aus Spalte W und dem Grund: von_hand (in der App erfasst), ohne_zeile (Zeile der Datei fehlt), nachholen (die Nummer steht inzwischen an einer Charge), mehrdeutig (Perigon-Nummer an mehreren Chargen), unbekannt (Nummer an keiner Charge), keine_nummer (Spalte W leer), menge_null (Chargen genannt, Spalte S = 0), rest (S kleiner als die Position; seit 0141 auch der Rest einer Mix-Position), mix (seit 0141: Anteil einer anderen Sorte aus einem Mix, nach Rezept ohne Charge — so verteilt, nichts zu tun). satz sagt es in Worten, tun was zu tun ist. Nichts wird umgebucht.';
grant select on v_lieferung_ohne_charge to authenticated;

-- ---------- Stand ----------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 141 $$;
