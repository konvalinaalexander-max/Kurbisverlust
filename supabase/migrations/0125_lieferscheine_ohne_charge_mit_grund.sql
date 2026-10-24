-- 0125 — Jeder Lieferschein ohne Charge, mit dem Grund
--
-- WARUM
--
-- Der Betrieb, 24. Oktober: „bitte weis mir in der App auch Lieferscheine
-- ohne Charge aus — dass du mir das auch anzeigst, ich kann draufklicken, und
-- du zeigst mir die Zeile vom Perigon."
--
-- Bis hier stand ein Lieferschein ohne Charge nur als Summe je Sorte da
-- (v_ohne_charge, 0121: „Tiana · 13 Lieferscheine · 2.5 t, verteilt auf …"),
-- in der Leiste oben, aufgeklappt, hinter einem Knopf. Dass es dafür fünf
-- verschiedene Ursachen gibt, sagte die App nirgends — und genau das braucht
-- der Betrieb, um zu wissen, wo er etwas ändern muss:
--
--   von Hand      die Lieferung wurde in der App erfasst, ohne Charge;
--   keine_nummer  in Perigon steht keine Chargennummer (Spalte W leer);
--   menge_null    Perigon nennt eine oder mehrere Chargen, teilt aber keine
--                 Menge zu (Spalte S = 0) — die ganze Position bleibt ohne
--                 Charge (so die Oettli-Ware ab 9. Oktober);
--   rest          Perigon teilt den Chargen weniger zu, als die Position
--                 geliefert hat; der Rest ist ohne Charge (0118);
--   nachholen     die Nummer kannte die App beim Einlesen nicht, inzwischen
--                 steht sie an einer Charge — das nächste Rechnen ordnet zu
--                 (lieferungen_nachordnen, 0121);
--   mehrdeutig    die Perigon-Nummer steht an mehreren Chargen;
--   unbekannt     die Nummer steht an keiner Charge der App;
--   ohne_zeile    aus Perigon eingelesen (Verknüpfung oder Bemerkung des
--                 Einlesens), aber die Zeile der Datei ist nicht mehr da —
--                 die Datei neu einlesen.
--
-- v_lieferung_ohne_charge nennt je Lieferschein Datum, Sorte, Kunde, Masse,
-- Firma und Position (für das Fenster mit der Perigon-Zeile), den Artikel,
-- die Nummern aus Spalte W, den Grund und den Satz, was zu tun ist. Es sind
-- genau die Lieferscheine von v_ohne_charge (verkauft, mit Masse, bis heute)
-- — die Summe je Sorte ist dieselbe; der Prüfblock hält es fest.
--
-- Nichts wird umgebucht. Die Sicht sagt nur, warum.

-- =====================================================================
-- 1. Die Sicht
-- =====================================================================
create or replace view v_lieferung_ohne_charge with (security_invoker = true) as
with l as (
  -- dieselben Lieferscheine wie v_ohne_charge (0121)
  select m.id, m.datum, m.sorte, m.kunde, m.masse_kg, m.bemerkung
    from v_lieferung_masse m
   where m.charge_nr is null and m.masse_kg > 0 and m.buch in ('verkauf', 'marge') and m.datum <= heute()
), mit as (
  select l.*, i.lieferung_id is not null as eingelesen, i.quelle, i.extern_id, coalesce(i.extern_id like '%:rest', false) as rest,
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
              when not p.rest and p.eigene is not null then 'nachholen'
              when not p.rest and cardinality(p.an_perigon) = 1 then 'nachholen'
              when not p.rest and cardinality(p.an_perigon) > 1 then 'mehrdeutig'
              when not p.rest then 'unbekannt'
              when p.nummern is null then 'keine_nummer'
              when p.kg_zugeteilt <= 0 then 'menge_null'
              else 'rest' end as grund,
         coalesce(p.eigene, case when cardinality(p.an_perigon) = 1 then p.an_perigon[1] end) as bekannt,
         case when p.nummern like '%,%' then 'die Chargen ' || p.nummern else 'die Charge ' || p.nummern end as chargen_text
    from pos p
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
         when 'nachholen' then 'Nichts — beim nächsten Rechnen („Neu rechnen" oben) bekommt der Lieferschein die Charge von selbst.'
         when 'mehrdeutig' then 'Unter Betrieb → Stammdaten → Chargen die Nummer nur bei der richtigen Charge lassen; beim nächsten Rechnen bekommt der Lieferschein sie.'
         when 'unbekannt' then 'Unter Betrieb → Stammdaten → Chargen bei der richtigen Charge als Perigon-Nr. eintragen; beim nächsten Rechnen bekommt der Lieferschein sie von selbst.'
         else 'In Perigon die Charge und die Menge je Charge (Spalten W und S) eintragen, dann die Datei unter Betrieb → Warenausgang neu einlesen.'
       end as tun
  from grund g;
comment on view v_lieferung_ohne_charge is
  'Jeder Lieferschein ohne Charge (0125) — dieselben wie v_ohne_charge: verkauft, mit Masse, bis heute — mit Firma und Position der Perigon-Zeile, Artikel, den Nummern aus Spalte W und dem Grund: von_hand (in der App erfasst), ohne_zeile (Zeile der Datei fehlt), nachholen (die Nummer steht inzwischen an einer Charge), mehrdeutig (Perigon-Nummer an mehreren Chargen), unbekannt (Nummer an keiner Charge), keine_nummer (Spalte W leer), menge_null (Chargen genannt, Spalte S = 0), rest (S kleiner als die Position). satz sagt es in Worten, tun was zu tun ist. Nichts wird umgebucht.';
grant select on v_lieferung_ohne_charge to authenticated;

-- =====================================================================
-- Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 125 $$;
