-- =====================================================================
-- 0086 — Die verschenkte Marge je Charge
--
-- Der Betrieb über die Marge-Darstellung: „scheusslich — es sagt z.b.
-- nicht welches kaliber … dann sind die messungen auch übereinander und
-- nicht clever zusammengefasst - z.b. dass dort genau so wie alles andere
-- so geordnet wird wie ganz oben angeben - wenn man alle sagt - dann alle
-- chargen - wenn man nur eine sorte hat die chargen untereinander".
--
-- Der Bildschirm kann nur gliedern, was die Datenbank auseinanderhält.
-- v_marge_wiegung (0078) fasst je Sorte zusammen — die Charge ist darin
-- verschwunden. Diese Migration stellt dieselbe Rechnung eine Ebene feiner
-- daneben: je Charge. Nicht statt, sondern zusätzlich, weil die Zahl je
-- Sorte weiter die ist, mit der der Betriebsleiter die Kisten füllen
-- lässt; die je Charge ist die, mit der er sieht, wo es herkommt.
--
-- Dieselbe Mathematik wie in 0078, derselbe Nenner (nur volle Paletten),
-- dieselben Namen der Spalten — plus charge_nr und schlag.
-- =====================================================================

create or replace view v_marge_charge with (security_invoker = true) as
with w as (
  select k.*
    from v_ausgang_voll k
   where k.kisten > 0 and k.netto_kg is not null and k.kistensystem is not null and k.voll
)
select w.charge_nr,
       w.sorte,
       w.schlag,
       w.kistensystem,
       case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end   as soll_kg_pro_kiste,
       case when w.kistensystem = 'stueck'   then w.kaliber_idx end         as kaliber_idx,
       case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end     as stueck_je_kiste,
       case when w.kistensystem = 'stueck'   then w.band_mittel_g end       as band_mittel_g,
       count(*)::int                                                       as n_wiegungen,
       sum(w.kisten)::int                                                  as kisten,
       zahl(avg(w.kg_pro_kiste), 3, 10000)::numeric(10,3)                  as kg_je_kiste,
       zahl(stddev_samp(w.kg_pro_kiste), 3, 10000)::numeric(10,3)          as sd_je_kiste,
       zahl(avg(w.ueberfuellung_je_kiste), 3, 10000)::numeric(10,3)        as zuviel_je_kiste,
       zahl(avg(w.kg_pro_kuerbis) * 1000, 0, 1000000)::numeric(8,0)        as g_je_kuerbis,
       zahl(avg(w.kg_pro_kuerbis) * 1000 - w.band_mittel_g, 0, 1000000)::numeric(8,0)
                                                                           as g_ueber_bandmitte,
       betriebstag(min(w.ts))                                              as von,
       betriebstag(max(w.ts))                                              as bis
  from w
 group by w.charge_nr, w.sorte, w.schlag, w.kistensystem,
          case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end,
          case when w.kistensystem = 'stueck'   then w.kaliber_idx end,
          case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end,
          case when w.kistensystem = 'stueck'   then w.band_mittel_g end,
          w.band_mittel_g;
comment on view v_marge_charge is
  'Die verschenkte Marge je Wägung, eine Ebene feiner als v_marge_wiegung: je '
  'Charge, Kistensystem und Soll bzw. Kaliber der Durchschnitt der gewogenen '
  'vollen fertigen Paletten (0086). Dieselbe Rechnung wie 0078.';

drop materialized view if exists erg_marge_charge;
create materialized view erg_marge_charge as select * from v_marge_charge with no data;
create unique index erg_marge_charge_pk
  on erg_marge_charge (charge_nr, kistensystem, coalesce(soll_kg_pro_kiste, -1), coalesce(kaliber_idx, -1),
                       coalesce(stueck_je_kiste, -1));
comment on materialized view erg_marge_charge is
  'Gespeichert: die Marge je Wägung je Charge (v_marge_charge). Schritt 4 des '
  'Rechenwerks (0086).';
grant select on v_marge_charge to authenticated;
grant select on erg_marge_charge to authenticated;

-- ---------------------------------------------------------------------
-- Das Rechenwerk kennt das neue Ergebnis (Schritt 4: erg_marge_charge).
-- Der Rumpf ist die Fassung, wie sie in der Datenbank steht — um einen
-- Namen länger.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auswertung_schritt(p_schritt integer)
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
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'mv_schimmel_punkte', 'mv_schimmel_modell',
                       'erg_punkte', 'erg_modell', 'erg_kurve', 'erg_selektion',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_fax', 'erg_koeff_ueberfuellung', 'mv_koeff_rand',
                       'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_fax_wartezeit', 'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
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
    for v_name in
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
  end if;

  foreach v_name in array v_namen loop
    execute format('refresh materialized view %I', v_name);
    execute format('analyze %I', v_name);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),
           dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif p_schritt = 1 then
    update auswertung_stand
       set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  else
    update auswertung_stand
       set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5);
end $function$;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 86 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
