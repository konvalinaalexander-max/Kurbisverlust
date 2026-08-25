-- =====================================================================
-- 0011 — Unplausible Messungen abfangen, ohne sie zu verstecken
--
-- Gefunden beim Durchgehen der Rechenkette: Ein vertippter Schimmelwert
-- (5000 statt 500 kg auf einer 865-kg-Palette) ergab 578 % Schimmelanteil.
-- Der Wert lief ungebremst durch die Kaskade und erzeugte −4135 kg
-- „verkaufsfähige" Masse und 5000 kg Verlust bei 865 kg Eingang.
--
-- Zwei Regeln daraus:
--   1. Die Rechnung wird gegen Unsinn gesichert (Anteile bleiben in [0,1],
--      Bezugsmassen werden nie negativ).
--   2. Aussortierte Werte verschwinden nicht still — v_plausibilitaet listet
--      sie für den Betriebsleiter auf. Eine unplausible Messung ist fast immer
--      ein Tippfehler, den man korrigieren will, keine Zahl zum Wegwerfen.
-- =====================================================================

-- ---------- Schwelle ------------------------------------------------------
-- Über 90 % der Masse als Schimmel oder Ausschuss ist real nicht zu erwarten;
-- so etwas kommt praktisch nur durch einen Tippfehler zustande.
create or replace function anteil_plausibel(p_anteil numeric)
returns boolean language sql immutable as $$
  select p_anteil is not null and p_anteil >= 0 and p_anteil <= 0.9;
$$;

-- ---------- Schimmel ------------------------------------------------------
create or replace view v_schimmel_beobachtung with (security_invoker = true) as
select am.auftrag_id, am.charge_nr, am.sorte, am.schlag, am.weg, am.station,
       am.start_ts, am.lagertage, am.masse_quelle,
       s.kg                                                        as schimmel_kg,
       am.eingang_netto_kg                                         as eingang_kg,
       (am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage))::numeric(12,2)
                                                                   as basis_jetzt_kg,
       (s.kg / nullif(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage), 0))
                                                                   as anteil,
       -- neu ans Ende angehängt, damit bestehende Views weiterlaufen
       anteil_plausibel(
         (s.kg / nullif(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage), 0))::numeric
       )                                                           as plausibel
  from v_auftrag_masse am
  join (select auftrag_id, sum(kg)::numeric as kg
          from schimmel_messung where gemessen group by auftrag_id) s
       on s.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
 where am.eingang_netto_kg is not null
   and am.lagertage is not null;

-- Nur plausible Beobachtungen bilden die Kurve.
create or replace view v_schimmel_kurve with (security_invoker = true) as
with klassen(von, bis) as (
  values (0, 14), (15, 30), (31, 60), (61, 90), (91, 120), (121, 180), (181, 100000)
), je_klasse as (
  select k.von, k.bis,
         count(b.auftrag_id)::int as n,
         sum(b.schimmel_kg) / nullif(sum(b.basis_jetzt_kg), 0) as anteil,
         stddev_samp(b.anteil)                                 as sd
    from klassen k
    left join v_schimmel_beobachtung b
           on b.lagertage >= k.von and b.lagertage <= k.bis
          and b.anteil is not null and b.plausibel
   group by k.von, k.bis
)
select von, bis, n, anteil, sd,
       least(greatest(
         max(anteil) over (order by von rows between unbounded preceding and current row), 0), 1)
                                                                    as anteil_mono,
       case when n >= 2 then greatest(anteil - 1.96 * sd / sqrt(n), 0) end as unten,
       case when n >= 2 then least(anteil + 1.96 * sd / sqrt(n), 1) end    as oben
  from je_klasse;

-- Letzte Sicherung direkt an der Quelle: Was hier herauskommt, geht als
-- (1 − f) in die Kaskade. Ein f > 1 würde negative Masse erzeugen.
create or replace function schimmelanteil(p_lagertage numeric, p_szenario text default 'mittel')
returns numeric language sql stable as $$
  select least(greatest(coalesce((
    select case p_szenario
             when 'unten' then coalesce(k.unten, k.anteil_mono)
             when 'oben'  then coalesce(k.oben,  k.anteil_mono)
             else k.anteil_mono end
      from v_schimmel_kurve k
     where k.von <= p_lagertage and k.n > 0
     order by k.von desc
     limit 1
  ), 0), 0), 1)::numeric;
$$;

-- ---------- Ausschuss und Nebenkanal --------------------------------------
-- Auf Weg 2 wird die Bezugsmasse um den ausgelesenen Schimmel verringert.
-- Ist dieser Wert vertippt, wurde die Basis negativ und der Anteil unsinnig.
create or replace view v_ausschuss_beobachtung with (security_invoker = true) as
select 'maschine'::verarbeitungsweg as weg, lm.charge_nr, lm.sorte, lm.auftrag_id,
       lm.masse_kg                                  as basis_kg,
       lm.masse_klein_kg                            as klein_kg,
       lm.masse_nebenkanal_kg                       as gross_kg,
       true                                         as plausibel
  from v_sortier_lauf_masse lm
 where lm.masse_kg > 0
union all
select 'hand'::verarbeitungsweg, am.charge_nr, am.sorte, am.auftrag_id,
       n.basis, h.klein_kg, h.gross_kg,
       anteil_plausibel((h.klein_kg  / nullif(n.basis, 0))::numeric)
         and anteil_plausibel((coalesce(h.gross_kg, 0) / nullif(n.basis, 0))::numeric)
  from v_auftrag_masse am
  join (select auftrag_id,
               sum(kg) filter (where art = 'zu_klein')::numeric as klein_kg,
               sum(kg) filter (where art = 'zu_gross')::numeric as gross_kg
          from ausschuss_messung where gemessen group by auftrag_id) h
       on h.auftrag_id = am.auftrag_id
  left join (select auftrag_id, sum(kg)::numeric as kg from schimmel_messung
              where gemessen group by auftrag_id) sm on sm.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
  cross join lateral (
        select greatest(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage)
                        - coalesce(sm.kg, 0), 0)::numeric(12,2) as basis
       ) n
 where am.weg = 'hand' and am.eingang_netto_kg is not null and am.lagertage is not null;

create or replace view v_koeff_ausschuss with (security_invoker = true) as
with roh as (
  select sorte, klein_kg / nullif(basis_kg, 0) as anteil, basis_kg
    from v_ausschuss_beobachtung
   where klein_kg is not null and basis_kg > 0 and plausibel
), stich as (
  select grp.sorte, s.n, s.mittel, s.sd
    from (select sorte from roh group by sorte union all select null) grp
    cross join lateral (
      select count(*)::int as n,
             sum(anteil * basis_kg) / nullif(sum(basis_kg), 0) as mittel,
             stddev_samp(anteil) as sd
        from roh where grp.sorte is null or roh.sorte = grp.sorte) s
), eff as (
  select sk.sorte, coalesce(js.n, ge.n, 0) as n,
         coalesce(js.mittel, ge.mittel) as mittel, coalesce(js.sd, ge.sd) as sd,
         case when js.sorte is not null then 'Sortierläufe/Handmessungen dieser Sorte'
              when ge.n > 0             then 'alle Sorten (zu wenige eigene)'
              else 'keine Messung vorhanden' end as basis
    from sorte_kaliber sk
    left join stich js on js.sorte = sk.sorte and js.n >= 2
    left join stich ge on ge.sorte is null
)
select sorte, mittel,
       case when sd is null or n < 2 then mittel else greatest(mittel - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then mittel else least(mittel + 1.96 * sd / sqrt(n), 1) end    as oben,
       n, basis
  from eff;

create or replace view v_koeff_nebenkanal with (security_invoker = true) as
with roh as (
  select sorte, gross_kg / nullif(basis_kg, 0) as anteil, basis_kg
    from v_ausschuss_beobachtung
   where gross_kg is not null and basis_kg > 0 and plausibel
), stich as (
  select grp.sorte, s.n, s.mittel, s.sd
    from (select sorte from roh group by sorte union all select null) grp
    cross join lateral (
      select count(*)::int as n,
             sum(anteil * basis_kg) / nullif(sum(basis_kg), 0) as mittel,
             stddev_samp(anteil) as sd
        from roh where grp.sorte is null or roh.sorte = grp.sorte) s
), eff as (
  select sk.sorte, coalesce(js.n, ge.n, 0) as n,
         coalesce(js.mittel, ge.mittel) as mittel, coalesce(js.sd, ge.sd) as sd,
         case when js.sorte is not null then 'Sortierläufe/Handmessungen dieser Sorte'
              when ge.n > 0             then 'alle Sorten (zu wenige eigene)'
              else 'keine Messung vorhanden' end as basis
    from sorte_kaliber sk
    left join stich js on js.sorte = sk.sorte and js.n >= 2
    left join stich ge on ge.sorte is null
)
select sorte, mittel,
       case when sd is null or n < 2 then mittel else greatest(mittel - 1.96 * sd / sqrt(n), 0) end as unten,
       case when sd is null or n < 2 then mittel else least(mittel + 1.96 * sd / sqrt(n), 1) end    as oben,
       n, basis
  from eff;

-- ---------- Was aussortiert wurde, muss sichtbar bleiben ------------------
create view v_plausibilitaet with (security_invoker = true) as
-- Schimmelmessungen, die mehr wiegen als die Palette hergibt
select 'Schimmel'::text as art, b.auftrag_id, b.charge_nr, b.sorte, b.start_ts,
       format('%s kg Schimmel auf %s kg Ware — das wären %s %%',
              round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100)) as befund,
       'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text as rat
  from v_schimmel_beobachtung b
 where b.anteil is not null and not b.plausibel
union all
-- Handmessungen auf Weg 2 mit unsinnigem Verhältnis
select 'Ausschuss', a.auftrag_id, a.charge_nr, a.sorte, null::timestamptz,
       format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse',
              round(coalesce(a.klein_kg, 0)), round(coalesce(a.gross_kg, 0)), round(a.basis_kg)),
       'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'
  from v_ausschuss_beobachtung a
 where a.weg = 'hand' and not a.plausibel
union all
-- Erfasst, aber von keiner Auswertung gelesen: Nebenkanal-Kilos werden aus der
-- Sortier-CSV bzw. aus ausschuss_messung('zu_gross') gewonnen. Eine Zeile hier
-- würde sonst spurlos verschwinden.
select 'Nicht ausgewertet', m.auftrag_id, a.charge_nr, c.sorte, m.ts,
       format('%s %s als marge_messung(nebenkanal) erfasst', m.wert, m.einheit),
       'Nebenkanal-Mengen gehören auf Weg 2 unter „zu gross"; auf Weg 1 kommen sie aus der CSV.'
  from marge_messung m
  join auftrag a on a.id = m.auftrag_id
  join charge c on c.nr = a.charge_nr
 where m.art = 'nebenkanal';

comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet. Nicht ignorieren: '
  'fast immer ein Tippfehler, der sich korrigieren lässt.';

-- ---------- Deaktivierte Personen dürfen nichts mehr erfassen -------------
-- profil.aktiv war bisher nur Zierde: die Erfassungs-Policies fragten es nicht ab.
create or replace function public.ist_aktiv()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profil where id = auth.uid() and aktiv);
$$;

do $$
declare t text;
begin
  foreach t in array array['auftrag_palette', 'schimmel_messung', 'ausschuss_messung',
                           'verdunstung_wiegung', 'marge_messung'] loop
    execute format('drop policy if exists %I on %I', t || '_erfassen', t);
    execute format('create policy %I on %I for insert to authenticated '
                   'with check ((erfasser = auth.uid() and ist_aktiv()) or ist_admin())',
                   t || '_erfassen', t);
  end loop;
end $$;

drop policy if exists auftrag_eroeffnen on auftrag;
create policy auftrag_eroeffnen on auftrag for insert to authenticated
  with check ((eroeffnet_von = auth.uid() and ist_aktiv()) or ist_admin());

grant select on v_plausibilitaet to authenticated;
grant execute on function anteil_plausibel(numeric), ist_aktiv() to authenticated;
