-- 0118 — Ein Rest ohne Charge ist keine unbekannte Charge
--
-- WARUM
--
-- Der Betrieb, zu „Was in den Perigon-Dateien auffällt": „ich versteh nicht
-- ganz, warum du bei diesen Zeilen mäckerst — aber nicht bei allen anderen."
-- Unter „Charge nicht zugeordnet" standen zwei verschiedene Dinge mit
-- demselben Satz:
--
--   1. Eine Perigon-Nummer, die an keiner Charge steht (198977, Butternut;
--      199156, Knirps) — echt: Die App weiss nicht, welche Charge das ist.
--   2. Ein Rest: Schreibt die Datei einer Charge (Spalte S, „AufPosBatch-
--      Quantity Charge") weniger zu, als die Position geliefert hat, wird der
--      Rest eine Lieferung ohne Charge (ausgang_vorbereiten, „…:rest"). Die
--      App hängt diesen Rest an die erste Zeile der Position — und die nennt
--      eine Charge. Die Prüfung sah „Perigon nennt 198951, die Lieferung hat
--      keine" und schrieb „die Nummer kennt die App nicht", obwohl 198951 an
--      Charge 1620 steht und der Hauptteil der Position dort richtig zählt.
--      Auf der Kopie der Betriebsdaten (30.9.): 3 solche Reste, 20 kg.
--
-- Jetzt: Ein Rest steht für sich als „Teil ohne Charge", mit der Masse des
-- Rests und dem Satz, woher er kommt. „Charge nicht zugeordnet" bleibt für
-- Nummern, die die App wirklich nicht auflösen kann; und steht die Nummer an
-- genau einer Charge (die Lieferung hat sie trotzdem nicht, etwa weil die
-- Nummer erst nach dem Einlesen eingetragen wurde), sagt der Satz das und
-- verlangt nur das neue Einlesen. Ein Rest zählt auch nicht noch einmal unter
-- „Als Demeter verkauft, als Knospe geliefert" — die Zeile, an der er hängt,
-- meldet das schon mit ihrer eigenen Lieferung.

create or replace view v_perigon_pruefung with (security_invoker = true) as
with zeile as (
  select z.id, z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_extern, z.kg_charge, z.liefer_label,
         l.id as lieferung_id, l.charge_nr, l.kg as kg_lieferung, c.sorte, sk.artikelgruppe as gruppe_charge,
         e.gruppe as gruppe_artikel, e.label as label_verkauft,
         case when upper(coalesce(z.liefer_label, '')) like 'D%' then 'D'
              when upper(coalesce(z.liefer_label, '')) ~ '^(K|CH-K)' then 'K' end as label_geliefert,
         li.extern_id like '%:rest' as rest,
         regexp_replace(z.charge_extern, '\D', '', 'g') as ziffern
    from ausgang_zeile z
    join lieferung_import li on li.zeile_id = z.id
    join lieferung l on l.id = li.lieferung_id
    left join charge c on c.nr = l.charge_nr
    left join sorte_kaliber sk on sk.sorte = c.sorte
   cross join lateral artikel_einordnen(z.artikel, z.preisgruppe) e
)
select 'Charge nicht zugeordnet'::text as art, z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge as kg,
       format('Perigon nennt die Charge %s, die Lieferung hat keine — %s', z.charge_extern,
              case when exists (select 1 from charge x where x.nr::text = z.ziffern)
                   then 'die Charge gibt es; die Datei unter Betrieb → Warenausgang neu einlesen'
                   when (select count(*) from charge x where x.perigon_nr::text = z.ziffern) = 1
                   then format('die Perigon-Nummer steht an Charge %s; die Datei unter Betrieb → Warenausgang neu einlesen',
                               (select x.nr from charge x where x.perigon_nr::text = z.ziffern))
                   when (select count(*) from charge x where x.perigon_nr::text = z.ziffern) > 1
                   then 'die Perigon-Nummer steht an mehreren Chargen, und der Artikel sagt nicht, welche Sorte'
                   else 'die Nummer steht an keiner Charge; unter Stammdaten → Chargen die Perigon-Nr. eintragen (oder die Charge anlegen), dann neu einlesen' end) as befund
  from zeile z
 where z.charge_extern <> '' and z.charge_nr is null and not z.rest
union all
select 'Teil ohne Charge', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, null::int, zahl(z.kg_lieferung, 3, 1e11)::numeric(14,3),
       format('%s kg der Position nennen in der Datei keine Charge — Spalte S schreibt der Charge %s weniger zu, als geliefert wurde. Der Rest zählt im Warenausgang, aber bei keiner Charge; der Teil mit Charge zählt richtig. Zu prüfen in Perigon, nicht in der App.',
              trim(to_char(z.kg_lieferung, 'FM999999990.0')), z.charge_extern)
  from zeile z
 where z.rest and z.charge_extern <> ''
union all
select 'Artikel passt nicht zur Sorte', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge,
       format('als %s verkauft, geliefert aus Charge %s (%s, geht als %s)', z.gruppe_artikel, z.charge_nr, z.sorte, z.gruppe_charge)
  from zeile z
 where z.gruppe_artikel is not null and z.gruppe_charge is not null
   and z.gruppe_artikel not in ('Mix', 'andere') and z.gruppe_artikel <> z.gruppe_charge
union all
select 'Als Demeter verkauft, als Knospe geliefert', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge,
       format('Preisgruppe Demeter, Lieferlabel %s (Charge %s)', z.liefer_label, z.charge_nr)
  from zeile z
 where z.label_verkauft = 'D' and z.label_geliefert = 'K' and not z.rest
union all
select 'Lieferung vor dem Eingang', z.quelle, z.pos_id, z.datum, z.kunde, z.artikel, z.charge_nr, z.kg_charge,
       format('geliefert am %s, die Charge %s kam erst am %s', to_char(z.datum, 'DD.MM.YYYY'), z.charge_nr,
              to_char(e.erst, 'DD.MM.YYYY'))
  from zeile z
  join (select charge_nr, min(eingangsdatum) as erst from palette group by charge_nr) e on e.charge_nr = z.charge_nr
 where z.datum < e.erst;
comment on view v_perigon_pruefung is
  'Was beim Durchsehen der Perigon-Zeilen der laufenden Saison auffällt (0116, 0118), je Zeile mit dem Satz, was zu tun ist: Charge nicht zugeordnet (eine Nummer, die die App nicht auflösen kann), Teil ohne Charge (die Datei schreibt den Chargen weniger zu, als die Position geliefert hat — 0118), Artikel passt nicht zur Sorte der gelieferten Charge, als Demeter verkauft und als Knospe geliefert, Lieferung vor dem ersten Eingang.';
grant select on v_perigon_pruefung to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 118 $$;
