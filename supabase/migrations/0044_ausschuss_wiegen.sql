-- =====================================================================
-- 0044 — Ausschuss wird gewogen, nicht geschätzt
--
-- Der Betrieb am 1. September: Der Ausschuss (zu klein, zu gross) soll
-- gewogen werden — auf eine Palette stellen, Kistenzahl und Gewicht erfassen —
-- statt ihn nach Augenmass zu schätzen. Bisher trug die Maske nur ein Kilo-
-- Feld, in das jemand eine geschätzte Zahl schrieb.
--
-- Erfasst wird ab jetzt wie bei der fertigen Palette: das Bruttogewicht auf
-- der Waage, die Zahl der Kisten und die Gebindeart. Das Netto ist Ableitung —
-- brutto minus Kisten-Tara minus Paletten-Tara. Damit gilt auch hier die
-- Regel: gespeichert wird, was beobachtet wurde (der Waagenstand), gerechnet
-- wird das Netto.
--
-- Die geschätzte Eingabe bleibt möglich (kg direkt), für die Fälle, in denen
-- nicht gewogen werden kann. Die Spalte `gemessen` unterscheidet beides schon
-- immer; neu ist, dass eine echte Wägung dahinterstehen kann.
--
-- Technisch: kg bleibt die Spalte, die alle Auswertungen lesen — sie wird zur
-- abgeleiteten Grösse, sobald ein Bruttogewicht da ist, gesetzt von einem
-- Auslöser. Ohne Brutto bleibt kg die eingetippte Schätzung. Ändert sich
-- später eine Gebinde-Tara, stimmt ein alt gespeichertes Netto nicht mehr mit
-- dem Brutto überein — genau wie beim Palox macht das eine Plausibilitäts-
-- zeile sichtbar, statt es still zu lassen.
-- =====================================================================

alter table ausschuss_messung add column if not exists brutto_kg    numeric(10,2);
alter table ausschuss_messung add column if not exists kisten       int;
alter table ausschuss_messung add column if not exists gebindeart   text references gebinde(art);
comment on column ausschuss_messung.brutto_kg is
  'Waagenstand der Ausschuss-Palette (brutto). Ist er gesetzt, ist kg das '
  'daraus abgeleitete Netto; sonst ist kg die eingetippte Schätzung.';

-- Netto ableiten, sobald brutto da ist.
create or replace function ausschuss_netto_setzen()
returns trigger language plpgsql as $$
declare v_tara_kiste numeric; v_tara_palette numeric;
begin
  if new.brutto_kg is not null then
    select g.tara_kg_pro_kiste, coalesce(g.tara_kg_palette, 0)
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    new.kg := greatest(round(new.brutto_kg
                - coalesce(new.kisten, 0) * coalesce(v_tara_kiste, 0)
                - coalesce(v_tara_palette, 0)), 0);
    new.gemessen := true;
  end if;
  return new;
end $$;
revoke execute on function ausschuss_netto_setzen() from public;
drop trigger if exists ausschuss_netto on ausschuss_messung;
create trigger ausschuss_netto before insert or update on ausschuss_messung
  for each row execute function ausschuss_netto_setzen();

-- Ein gewogener Ausschuss, dessen gespeichertes Netto nicht mehr zu Brutto
-- und Tara passt (Tara nachträglich geändert), gehört sichtbar gemacht.
create or replace view v_ausschuss_pruef with (security_invoker = true) as
select m.id, m.auftrag_id, a.charge_nr, c.sorte, m.ts, m.art, m.kg, m.brutto_kg,
       greatest(round(m.brutto_kg - coalesce(m.kisten,0) * coalesce(g.tara_kg_pro_kiste,0)
                      - coalesce(g.tara_kg_palette,0)), 0) as kg_neu
  from ausschuss_messung m
  join auftrag a on a.id = m.auftrag_id
  join charge c on c.nr = a.charge_nr
  left join gebinde g on g.art = m.gebindeart
 where m.brutto_kg is not null and a.abgebrochen_ts is null
   and abs(m.kg - greatest(round(m.brutto_kg - coalesce(m.kisten,0) * coalesce(g.tara_kg_pro_kiste,0)
                                 - coalesce(g.tara_kg_palette,0)), 0)) > 0;
comment on view v_ausschuss_pruef is
  'Gewogener Ausschuss, dessen gespeichertes Netto nicht mehr zu Brutto und '
  'aktueller Tara passt — meist eine nachträglich geänderte Gebinde-Tara.';
grant select on v_ausschuss_pruef to authenticated;
