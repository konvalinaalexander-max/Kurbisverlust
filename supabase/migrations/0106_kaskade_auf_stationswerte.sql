-- =====================================================================
-- 0106 — Die Kaskade rechnet mit den Stationswerten; das Verderbsmodell
--         ist gestrichen (Runde AJ, Entscheid des Betriebs, 29. September)
-- =====================================================================
--
-- Der Betrieb, nachdem er die Zahlen der Saison gesehen hatte: „Ich habe
-- das Gefühl, unsere Software ist extrem bloated und unnötig kompliziert."
-- Und zur Sache: An der Sortiermaschine legen fünf Jungs nur eklig Faules
-- in den Palox, an der Waschstrasse zwei junge Frauen auch Ästhetik und
-- Schäden — „es sind einfach zwei sehr unterschiedliche Arten von Augen".
-- Ein Modell, das alle Ablesungen aller Augen auf eine Kurve über die
-- Lagerdauer legt (0017: F(t) = 1 − exp(−λ·t^k), im Logarithmus angepasst,
-- mit Smearing zurückgerechnet, mit Sockel a₀, mit Selektionszuschlag),
-- rechnet damit etwas, was es im Betrieb nicht gibt. Auf den echten Daten
-- war es am 29. September nicht einmal anpassbar (k = −0.49, brauchbar =
-- false); die Kaskade lief seit Saisonbeginn auf der Treppenfunktion.
--
-- Beschlossen (docs/ENTSCHLACKUNG.md, Stufe 2): Die Kaskade rechnet das
-- Faule ab jetzt mit dem, was der Betrieb unter dem Diagramm liest — dem
-- Palox-Anteil je Station (0105), je Sorte, aus den letzten vier Wochen.
-- Was eine Charge auf ihrem Weg verliert, ist die Zusammensetzung der
-- Stationen, durch die sie geht:
--
--   f = p_hand · f_W+S + (1 − p_hand) · (f_S + (1 − f_S) · p_wasch · g_W)
--
--   p_hand   Anteil der Charge, der von Hand gewaschen + sortiert wird
--            (aus ihren eigenen Arbeiten, sonst denen der Sorte, sonst allen)
--   p_wasch  1, wenn die Bandware der Sorte in dieser Saison gewaschen wird
--   f_W+S, f_S, g_W   der Palox-Anteil der Station: für ausgelagerte Ware
--            die eigene Messung der Charge, für liegende Ware die Erwartung
--            der Sorte (vier Wochen → Saison → alle Sorten, v_palox_erwartung)
--
-- In der Prognose wächst der Anteil mit dem Zuwachs je Woche, den die
-- Kennzahl je Station seit 0105 ausweist — und nur, wenn sie ihn ausweist
-- (vier Wochen, fünf Arbeiten). Vorher steht die Prognose des Faulen auf
-- dem Stand von heute und sagt es (zuwachs_bekannt = false).
--
-- Gestrichen sind damit: v_schimmel_modell_rechnen, mv_schimmel_modell,
-- v_schimmel_modell, schimmelanteil(), sockel_anteil(), v_schimmel_kurve,
-- v_schimmel_kurve_anzeige, v_selektionsverdacht, v_verderb_lage,
-- erg_modell, erg_kurve, erg_selektion — und mv_schimmel_punkte, an der
-- seit 0105 nichts mehr hängt (erg_punkte liest v_schimmel_punkte selbst).
-- Mit ihnen gehen der Sockel (a0, sockel_kg, sockel_*), modell_gilt,
-- f_extrapoliert, hochgerechnet und die Ableitungen d_f_eta, d_eta, d_a0.
-- Neu heissen die Kennzeichen f_geliehen (der Anteil kommt aus den
-- Arbeiten aller Sorten) und zuwachs_bekannt (die Prognose schreibt fort).
--
-- Keine Tabelle und keine Spalte einer Tabelle wird gelöscht. Die Punkte
-- (schimmel_messung, verdunstung_wiegung) bleiben, wie sie sind; nur die
-- Rechnung darüber ist eine andere.
--
-- Was die Kaskade an ihrem Rechenweg sonst nicht ändert: Verdunstung,
-- zu klein / zu gross, Fax, die Rückrechnung des Ausgelagerten, die
-- Überzählung, die drei Portionen (0065) — alles wie bisher.

-- ---------------------------------------------------------------------
-- 1. Wegräumen — in der Reihenfolge der Abhängigkeit, jedes beim Namen
-- ---------------------------------------------------------------------
-- Die Kaskade reisst mit „cascade" alles mit, was an ihr hängt; unten
-- wird es in derselben Reihenfolge neu gebaut. Die Modellobjekte werden
-- ausdrücklich genannt, damit der Verdichter weiss, dass es sie am Ende
-- nicht mehr gibt (und die alte Schleife aus 0061/0068, die erg_modell
-- aus v_schimmel_modell baute, in setup.sql nicht mehr läuft).
drop materialized view if exists mv_kaskade cascade;
drop materialized view if exists erg_modell cascade;
drop materialized view if exists erg_kurve cascade;
drop materialized view if exists erg_selektion cascade;
drop view if exists v_schimmel_kurve_anzeige cascade;
drop view if exists v_selektionsverdacht cascade;
drop function if exists schimmelanteil(numeric, text);
drop function if exists sockel_anteil();
drop view if exists v_schimmel_modell cascade;
drop materialized view if exists mv_schimmel_modell cascade;
drop view if exists v_schimmel_modell_rechnen cascade;
drop view if exists v_schimmel_kurve cascade;
drop view if exists v_verderb_lage cascade;
drop materialized view if exists mv_schimmel_punkte cascade;

-- ---------------------------------------------------------------------
-- 2. Der Palox-Anteil je Station — Erwartung, eigener Wert, Weg der Charge
-- ---------------------------------------------------------------------
-- Ab wie vielen Arbeiten gilt ein Wert der Sorte (und der aller Sorten in
-- den letzten vier Wochen)? Drei. Ein einzelner Wert der ganzen Saison
-- über alle Sorten gilt ab der ersten Arbeit — sonst rechnete die Kaskade
-- bis zur dritten Arbeit „unbekannt", obwohl ein Auge etwas gesehen hat.
create or replace function palox_mindest_arbeiten() returns int
language sql immutable as $$ select 3 $$;
comment on function palox_mindest_arbeiten() is
  'Ab so vielen Arbeiten gilt der Palox-Anteil einer Sorte je Station (0106); darunter fällt die Kaskade auf die '
  'ganze Saison der Sorte zurück, dann auf alle Sorten.';
revoke all on function palox_mindest_arbeiten() from public;
grant execute on function palox_mindest_arbeiten() to authenticated;

-- Die Zusammensetzung über den Weg der Charge. NULL, sobald eine Station
-- auf dem Weg keinen Wert hat: dann ist das Faule unbekannt, nicht 0.
create or replace function palox_f(p_hand numeric, p_wasch numeric, f_ws numeric, f_s numeric, g_w numeric)
returns numeric language sql immutable as $$
  select case
           when p_hand is null then null
           when p_hand > 0 and f_ws is null then null
           when p_hand < 1 and f_s is null then null
           when p_hand < 1 and coalesce(p_wasch, 0) > 0 and g_w is null then null
           else least(greatest(
                  p_hand * coalesce(f_ws, 0)
                  + (1 - p_hand) * (coalesce(f_s, 0)
                                    + (1 - coalesce(f_s, 0)) * coalesce(p_wasch, 0) * coalesce(g_w, 0)),
                0), 1)
         end
$$;
comment on function palox_f(numeric, numeric, numeric, numeric, numeric) is
  'Der Palox-Anteil einer Charge über ihren Weg (0106): p_hand · f_W+S + (1 − p_hand) · (f_S + (1 − f_S) · p_wasch · g_W). '
  'NULL, wenn eine Station auf dem Weg keinen Wert hat — leer ist nicht null.';
revoke all on function palox_f(numeric, numeric, numeric, numeric, numeric) from public;
grant execute on function palox_f(numeric, numeric, numeric, numeric, numeric) to authenticated;

-- Derselbe Anteil d Tage später (oder früher): jede Station um ihren
-- Zuwachs je Woche fortgeschrieben, zwischen 0 und 1 gehalten, dann wie
-- heute zusammengesetzt. Ohne Zuwachs (NULL) bleibt die Station stehen.
create or replace function palox_f_nach(p_hand numeric, p_wasch numeric, f_ws numeric, f_s numeric, g_w numeric,
                                        b_ws numeric, b_s numeric, g_b numeric, d_tage numeric)
returns numeric language sql immutable as $$
  select palox_f(p_hand, p_wasch,
                 case when f_ws is null then null else least(greatest(f_ws + coalesce(b_ws, 0) * d_tage / 7.0, 0), 1) end,
                 case when f_s  is null then null else least(greatest(f_s  + coalesce(b_s,  0) * d_tage / 7.0, 0), 1) end,
                 case when g_w  is null then null else least(greatest(g_w  + coalesce(g_b,  0) * d_tage / 7.0, 0), 1) end)
$$;
comment on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) is
  'palox_f() d Tage später: jede Station um ihren Zuwachs je Woche (Kennzahl 0105) fortgeschrieben (0106).';
revoke all on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) from public;
grant execute on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) to authenticated;

-- Die Erwartung je Sorte und Station: massegewichtet über die plausiblen
-- Punkte, zuerst die letzten vier Wochen der Sorte, dann ihre Saison, dann
-- alle Sorten (vier Wochen, Saison). Jede Zeile sagt, woher sie kommt.
-- Gelesen wird v_schimmel_punkte, nicht die Kopie erg_punkte: die Punkte
-- gibt es auf einem Weg (0068), und die Sicht zeigt immer den Stand von jetzt.
create or replace view v_palox_erwartung with (security_invoker = true) as
-- „materialized": die Punkte einmal rechnen, nicht je Sorte und Ebene neu
-- (Lasttest: 790 → unter 400 ms je Aufruf).
with punkte as materialized (
  select e.sorte, e.station, e.charge_nr, e.messtag, e.basis_jetzt_kg as w, e.anteil_station as y
    from v_schimmel_punkte e
   where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
     and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
     and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
), sorten as (
  select distinct sorte from v_kaskade_basis
  union
  select distinct sorte from punkte
), stationen(station) as (
  values ('waschen_sortieren'), ('sortieren'), ('waschen')
), ebenen(rang, ebene, quelle) as (
  values (1, 'sorte_4w',    'Arbeiten dieser Sorte, letzte vier Wochen'),
         (2, 'sorte_saison', 'Arbeiten dieser Sorte, ganze Saison'),
         (3, 'alle_4w',      'Arbeiten aller Sorten, letzte vier Wochen'),
         (4, 'alle_saison',  'Arbeiten aller Sorten, ganze Saison')
), fenster as materialized (
  -- heute() einmal: „materialized", sonst zieht der Planer den Einzeiler in
  -- die Verknüpfung unten und ruft heute() je Punkt und Ebene (Lasttest:
  -- 443 ms statt 9 ms in genau dieser Verknüpfung)
  select heute() - 28 as vier_wochen_ab
), je_ebene as (
  select s.sorte, st.station, e.rang, e.ebene, e.quelle,
         count(p.y)::int                                  as n_arbeiten,
         count(distinct p.charge_nr)::int                 as n_chargen,
         min(p.messtag)                                   as seit,
         max(p.messtag)                                   as bis,
         sum(p.w * p.y) / nullif(sum(p.w), 0)             as anteil,
         stddev_samp(p.y)                                 as sd
    from sorten s
    cross join stationen st
    cross join ebenen e
    cross join fenster f
    left join punkte p
           on p.station = st.station
          and (e.rang in (3, 4) or p.sorte = s.sorte)
          and (e.rang in (2, 4) or p.messtag > f.vier_wochen_ab)
   group by s.sorte, st.station, e.rang, e.ebene, e.quelle
), gueltig as (
  select *
    from je_ebene
   where n_arbeiten >= case when rang = 4 then 1 else palox_mindest_arbeiten() end
)
select distinct on (sorte, station)
       sorte, station, ebene, quelle,
       zahl(anteil, 5, 1)::numeric(10,5)                                            as anteil,
       -- das Band über die Arbeiten: ± t · sd / √n; eine Arbeit hat kein Band
       -- (ein zahl() je Cast — die Regel von 0059)
       zahl(case when n_arbeiten >= 2 and sd is not null
                 then greatest(anteil - t_quantil_95(n_arbeiten - 1) * sd / sqrt(n_arbeiten), 0)
                 else anteil end, 5, 1)::numeric(10,5)                              as unten,
       zahl(case when n_arbeiten >= 2 and sd is not null
                 then least(anteil + t_quantil_95(n_arbeiten - 1) * sd / sqrt(n_arbeiten), 1)
                 else anteil end, 5, 1)::numeric(10,5)                              as oben,
       n_arbeiten, n_chargen, seit, bis,
       (ebene like 'alle%')                                                          as geliehen
  from gueltig
 order by sorte, station, rang;
comment on view v_palox_erwartung is
  'Je Sorte und Station der erwartete Palox-Anteil (0106): das nach Masse gewichtete Mittel der plausiblen Punkte — '
  'zuerst die letzten vier Wochen der Sorte, dann ihre Saison, dann alle Sorten (ab palox_mindest_arbeiten() Arbeiten, '
  'die ganze Saison aller Sorten ab einer). ebene/quelle sagen, welche Stufe gilt; geliehen = aus allen Sorten. '
  'unten/oben: ± t · sd/√n über die Arbeiten.';
grant select on v_palox_erwartung to authenticated;

-- Der eigene Wert einer Charge je Station — für das, was sie schon durch
-- diese Station geschickt hat, gilt die eigene Messung vor jeder Erwartung.
create or replace view v_charge_palox with (security_invoker = true) as
select e.charge_nr, e.station,
       zahl(sum(e.basis_jetzt_kg * e.anteil_station) / nullif(sum(e.basis_jetzt_kg), 0), 5, 1)::numeric(10,5) as anteil,
       count(*)::int as n_arbeiten
  from v_schimmel_punkte e
 where e.plausibel_station and e.anteil_station is not null and e.basis_jetzt_kg > 0
   and e.station in ('sortieren', 'waschen', 'waschen_sortieren')
   and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
 group by e.charge_nr, e.station;
comment on view v_charge_palox is
  'Je Charge und Station ihr eigener Palox-Anteil (0106), massegewichtet über ihre plausiblen Arbeiten — gilt für die '
  'ausgelagerte Ware der Charge vor der Erwartung der Sorte.';
grant select on v_charge_palox to authenticated;

-- Der Weg einer Charge: wie viel von Hand (Waschen + Sortieren), wie viel
-- über das Band — und ob Bandware dieser Sorte gewaschen wird. Aus den
-- eigenen Arbeiten; hat die Charge keine, aus denen der Sorte; hat die
-- Sorte keine, aus allen. Gar keine Arbeit: der Weg ist unbekannt.
create or replace view v_charge_weg with (security_invoker = true) as
with arbeit as (
  select a.charge_nr, a.sorte,
         sum(a.eingang_netto_kg) filter (where a.station = 'waschen_sortieren')          as hand_kg,
         sum(a.eingang_netto_kg) filter (where a.station = 'sortieren')                  as band_kg,
         sum(a.eingang_netto_kg) filter (where a.station = 'waschen' and not a.ist_fax)  as wasch_kg
    from v_auftrag_masse a
   where a.eingang_netto_kg is not null and a.eingang_netto_kg > 0
   group by a.charge_nr, a.sorte
), je_sorte as (
  select sorte, sum(hand_kg) as hand_kg, sum(band_kg) as band_kg, sum(wasch_kg) as wasch_kg
    from arbeit group by sorte
), alle as (
  select sum(hand_kg) as hand_kg, sum(band_kg) as band_kg, sum(wasch_kg) as wasch_kg from arbeit
)
select b.charge_nr, b.sorte,
       case when coalesce(c.hand_kg, 0) + coalesce(c.band_kg, 0) > 0
              then coalesce(c.hand_kg, 0) / (coalesce(c.hand_kg, 0) + coalesce(c.band_kg, 0))
            when coalesce(s.hand_kg, 0) + coalesce(s.band_kg, 0) > 0
              then coalesce(s.hand_kg, 0) / (coalesce(s.hand_kg, 0) + coalesce(s.band_kg, 0))
            when coalesce(x.hand_kg, 0) + coalesce(x.band_kg, 0) > 0
              then coalesce(x.hand_kg, 0) / (coalesce(x.hand_kg, 0) + coalesce(x.band_kg, 0))
       end                                                                      as p_hand,
       -- Bandware wird gewaschen, sobald die Charge oder ihre Sorte in
       -- dieser Saison eine Wasch-Arbeit hat (AB-121). Eine Sorte, die nur
       -- sortiert wird, verkauft ungewaschen: p_wasch = 0.
       case when coalesce(c.wasch_kg, 0) > 0 or coalesce(s.wasch_kg, 0) > 0 then 1
            when coalesce(s.hand_kg, 0) + coalesce(s.band_kg, 0) > 0 then 0
            when coalesce(x.wasch_kg, 0) > 0 then 1
            when coalesce(x.hand_kg, 0) + coalesce(x.band_kg, 0) > 0 then 0
       end::numeric                                                             as p_wasch,
       case when coalesce(c.hand_kg, 0) + coalesce(c.band_kg, 0) > 0 then 'eigenen Arbeiten'
            when coalesce(s.hand_kg, 0) + coalesce(s.band_kg, 0) > 0 then 'Arbeiten der Sorte'
            when coalesce(x.hand_kg, 0) + coalesce(x.band_kg, 0) > 0 then 'Arbeiten aller Sorten'
       end                                                                      as weg_quelle,
       coalesce(c.hand_kg, 0) as hand_kg, coalesce(c.band_kg, 0) as band_kg, coalesce(c.wasch_kg, 0) as wasch_kg
  from v_kaskade_basis b
  left join arbeit c on c.charge_nr = b.charge_nr
  left join je_sorte s on s.sorte = b.sorte
  cross join alle x;
comment on view v_charge_weg is
  'Der Weg einer Charge durch die Stationen (0106): p_hand = Anteil von Hand (Waschen + Sortieren) an der verarbeiteten '
  'Masse, p_wasch = 1, wenn Bandware dieser Sorte gewaschen wird. Aus den eigenen Arbeiten, sonst denen der Sorte, sonst '
  'allen (weg_quelle); ohne jede Arbeit NULL.';
grant select on v_charge_weg to authenticated;


-- ---------------------------------------------------------------------
-- 3. Die Kaskade — ohne Sockel, mit dem Anteil über den Weg der Charge
-- ---------------------------------------------------------------------
-- Was gleich bleibt, steht wie in 0065/0101: Kohorten, Lieferungen, die
-- Portionen ausgelagert / entsorgt / lager, die Rückrechnung m0 aus dem
-- Gelieferten, die Überzählung. Neu ist nur, woher f kommt — und dass es
-- keinen Schritt „Sockel" zwischen Verdunstung und Faulem mehr gibt:
--   m1 = m0 · (1 − r)^t,   m2 = m1 · (1 − f),   dann zu klein / zu gross, Fax.
create materialized view mv_kaskade as
with kohorten as materialized (
  select k.charge_nr, k.eingangsdatum, k.anteil, b.eingang_kg * k.anteil as eingang_kg
    from v_kohorte_anteil k
    join v_kaskade_basis b on b.charge_nr = k.charge_nr
), lieferungen as materialized (
  select charge_nr, kohorte, sum(masse_kg) as masse_kg,
         sum(masse_kg * coalesce(alter_tage, 0)) / nullif(sum(masse_kg), 0) as alter_tage,
         sum(n_lieferungen)::int as n_lieferungen
    from v_lieferung_kohorte
   where buch in ('verkauf', 'marge')
   group by charge_nr, kohorte
), entsorgt_lief as (
  select charge_nr, kohorte, sum(masse_kg) as masse_kg,
         sum(masse_kg * coalesce(alter_tage, 0)) / nullif(sum(masse_kg), 0) as alter_tage,
         sum(n_lieferungen)::int as n_lieferungen
    from v_lieferung_kohorte
   where buch = 'verlust'
   group by charge_nr, kohorte
), koeff as (
  select b.charge_nr, b.sorte, b.schlag, b.eingang_kg, b.stichtag,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05) as r,
         (kv.mittel is not null) as r_bekannt, kv.n as r_n, kv.basis as r_basis,
         least(greatest(coalesce(ka.mittel, 0), 0), 1) as a_klein,
         (ka.mittel is not null) as a_klein_bekannt, ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(coalesce(kn.mittel, 0), 0), 1) as a_gross,
         (kn.mittel is not null) as a_gross_bekannt, kn.n as gross_n, kn.basis as gross_basis,
         least(greatest(coalesce(kf.mittel, 0), 0), 1) as a_fax,
         (kf.mittel is not null) as a_fax_bekannt, kf.n as fax_n, kf.basis as fax_basis
    from v_kaskade_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
    left join v_koeff_fax         kf on kf.sorte = b.sorte
   where b.eingang_kg > 0
), koeff_norm as (
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
), weg as materialized (
  select charge_nr, p_hand, p_wasch, weg_quelle from v_charge_weg
), erwartung as materialized (
  select sorte, station, anteil, unten, oben, n_arbeiten, geliehen, quelle from v_palox_erwartung
), eigen as materialized (
  select charge_nr, station, anteil, n_arbeiten from v_charge_palox
), zuwachs as materialized (
  -- der Zuwachs je Station (Anteil je Woche, alle Sorten) — NULL, solange
  -- die Kennzahl ihn nicht ausweist (vier Wochen, fünf Arbeiten)
  select station, zuwachs_je_woche from v_palox_station
), je_station as materialized (
  -- je Charge, Portion und Station der Wert, der gilt: für Ausgelagertes
  -- die eigene Messung (wenn es eine gibt), für Liegendes die Erwartung
  select k.charge_nr, p.portion, st.station,
         case when p.portion = 'ausgelagert' and ei.anteil is not null then ei.anteil      else er.anteil     end as f,
         case when p.portion = 'ausgelagert' and ei.anteil is not null then ei.anteil      else er.unten      end as unten,
         case when p.portion = 'ausgelagert' and ei.anteil is not null then ei.anteil      else er.oben       end as oben,
         case when p.portion = 'ausgelagert' and ei.anteil is not null then ei.n_arbeiten  else er.n_arbeiten end as n,
         case when p.portion = 'ausgelagert' and ei.anteil is not null then false else coalesce(er.geliehen, false) end as geliehen,
         case when p.portion = 'ausgelagert' and ei.anteil is not null
              then format('eigene Messung (%s Arbeiten)', ei.n_arbeiten) else er.quelle end as quelle
    from koeff k
    cross join (values ('ausgelagert'), ('lager')) p(portion)
    cross join (values ('waschen_sortieren'), ('sortieren'), ('waschen')) st(station)
    left join erwartung er on er.sorte = k.sorte and er.station = st.station
    left join eigen ei on ei.charge_nr = k.charge_nr and ei.station = st.station
), roh as (
  select k.charge_nr, 'ausgelagert'::text as portion, l.kohorte, l.masse_kg::numeric as geliefert_kg,
         coalesce(l.alter_tage, 0) as alter_tage, null::numeric as eingang_kohorte_kg, l.n_lieferungen
    from koeff_norm k join lieferungen l on l.charge_nr = k.charge_nr
  union all
  select k.charge_nr, 'entsorgt', e.kohorte, e.masse_kg::numeric,
         coalesce(e.alter_tage, 0), null::numeric, e.n_lieferungen
    from koeff_norm k join entsorgt_lief e on e.charge_nr = k.charge_nr
  union all
  select k.charge_nr, 'lager', c.eingangsdatum, null::numeric,
         greatest((k.stichtag - c.eingangsdatum)::numeric, 0), c.eingang_kg, 0
    from koeff_norm k join kohorten c on c.charge_nr = k.charge_nr
), teile as (
  select k.*, t.portion, t.kohorte, t.geliefert_kg, t.alter_tage, t.eingang_kohorte_kg, t.n_lieferungen,
         w.p_hand, w.p_wasch, w.weg_quelle,
         ws.f as f_ws, s.f as f_s, wa.f as g_w,
         palox_f(w.p_hand, w.p_wasch, ws.f, s.f, wa.f)              as f_roh,
         palox_f(w.p_hand, w.p_wasch, ws.unten, s.unten, wa.unten)  as f_unten_roh,
         palox_f(w.p_hand, w.p_wasch, ws.oben, s.oben, wa.oben)     as f_oben_roh,
         -- die Stationen auf dem Weg: W+S bei p_hand > 0, das Band bei
         -- p_hand < 1, die Waschstrasse bei p_hand < 1 und p_wasch > 0
         least(case when w.p_hand > 0 then ws.n end,
               case when w.p_hand < 1 then s.n end,
               case when w.p_hand < 1 and w.p_wasch > 0 then wa.n end)         as f_n,
         (coalesce(case when w.p_hand > 0 then ws.geliehen end, false)
          or coalesce(case when w.p_hand < 1 then s.geliehen end, false)
          or coalesce(case when w.p_hand < 1 and w.p_wasch > 0 then wa.geliehen end, false)) as f_geliehen,
         concat_ws('; ',
           case when w.p_hand > 0 then 'Waschen + Sortieren: ' || coalesce(ws.quelle, 'kein Wert') end,
           case when w.p_hand < 1 then 'Sortieren: ' || coalesce(s.quelle, 'kein Wert') end,
           case when w.p_hand < 1 and w.p_wasch > 0 then 'Waschen: ' || coalesce(wa.quelle, 'kein Wert') end,
           case when w.weg_quelle is not null then 'Weg nach ' || w.weg_quelle end) as f_quelle,
         zws.zuwachs_je_woche as b_ws, zs.zuwachs_je_woche as b_s, zw.zuwachs_je_woche as b_w,
         -- fortschreiben kann die Prognose nur, wenn jede Station auf dem
         -- Weg ihren Zuwachs hat
         ((w.p_hand = 0 or zws.zuwachs_je_woche is not null)
          and (w.p_hand = 1 or zs.zuwachs_je_woche is not null)
          and (w.p_hand = 1 or coalesce(w.p_wasch, 0) = 0 or zw.zuwachs_je_woche is not null)) as zuwachs_roh
    from koeff_norm k
    join roh t on t.charge_nr = k.charge_nr
    left join weg w on w.charge_nr = k.charge_nr
    left join je_station ws on ws.charge_nr = k.charge_nr and ws.station = 'waschen_sortieren'
                           and ws.portion = case when t.portion = 'lager' then 'lager' else 'ausgelagert' end
    left join je_station s  on s.charge_nr = k.charge_nr and s.station = 'sortieren'
                           and s.portion = case when t.portion = 'lager' then 'lager' else 'ausgelagert' end
    left join je_station wa on wa.charge_nr = k.charge_nr and wa.station = 'waschen'
                           and wa.portion = case when t.portion = 'lager' then 'lager' else 'ausgelagert' end
    left join zuwachs zws on zws.station = 'waschen_sortieren'
    left join zuwachs zs  on zs.station = 'sortieren'
    left join zuwachs zw  on zw.station = 'waschen'
), mit_f as (
  select t.*,
         (t.f_roh is not null)                                as f_bekannt,
         coalesce(t.f_roh, 0)                                 as f,
         coalesce(t.f_unten_roh, t.f_roh, 0)                  as f_unten,
         coalesce(t.f_oben_roh, t.f_roh, 0)                   as f_oben,
         -- die Streuung des Anteils aus seinem Band: (oben − unten) / (2 t)
         case when t.f_roh is null or t.f_n is null or t.f_n < 2 then 0
              else (coalesce(t.f_oben_roh, t.f_roh) - coalesce(t.f_unten_roh, t.f_roh))
                   / (2 * t_quantil_95(t.f_n - 1)) end        as f_se,
         (t.f_roh is not null and coalesce(t.zuwachs_roh, false)) as zuwachs_bekannt
    from teile t
), anteil as (
  select x.*,
         greatest(power(1 - x.r, x.alter_tage) * (1 - x.f) * (1 - x.a_klein_n - x.a_gross_n) * (1 - x.a_fax), 0.25)
                                                              as verkaufsfaehig_anteil,
         greatest(power(1 - x.r, x.alter_tage), 0.25)         as verdunstungs_anteil
    from mit_f x
), ausgelagert as (
  select a.*,
         case when a.portion = 'entsorgt' then a.geliefert_kg / a.verdunstungs_anteil
              else a.geliefert_kg / a.verkaufsfaehig_anteil end as m0,
         0::numeric as ueberzaehlung_kg
    from anteil a
   where a.portion in ('ausgelagert', 'entsorgt')
), lager as (
  select a.*,
         greatest(a.eingang_kohorte_kg - coalesce(x.m0, 0), 0) as m0,
         greatest(coalesce(x.m0, 0) - a.eingang_kohorte_kg, 0) as ueberzaehlung_kg
    from anteil a
    left join (select charge_nr, kohorte, sum(m0) as m0 from ausgelagert group by charge_nr, kohorte) x
           on x.charge_nr = a.charge_nr and x.kohorte = a.kohorte
   where a.portion = 'lager'
), alle as (
  select * from ausgelagert
  union all
  select * from lager
), kaskade as (
  select t.*,
         t.m0 * power(1 - t.r, t.alter_tage)                                       as m1,
         -t.m0 * t.alter_tage * power(1 - t.r, greatest(t.alter_tage - 1, 0))      as d_m1_r
    from alle t
   where t.m0 > 0 or t.ueberzaehlung_kg > 0
)
select charge_nr, sorte, schlag, portion, alter_tage, eingang_kg,
       m0, m1,
       case when portion = 'entsorgt' then 0 else m1 * (1 - f) end                 as m2,
       r, f, f_unten, f_oben, f_se, f_ws, f_s, g_w, p_hand, p_wasch, f_quelle, f_geliehen,
       b_ws, b_s, b_w, zuwachs_bekannt,
       a_klein_n, a_gross_n, a_fax, d_m1_r,
       r_n, r_basis, klein_n, klein_basis, gross_n, gross_basis, f_n, fax_n, fax_basis,
       r_bekannt, f_bekannt, a_klein_bekannt, a_gross_bekannt, a_fax_bekannt,
       m0 - m1                                                                     as verdunstung_kg,
       case when portion = 'entsorgt' then m1 else m1 * f end                      as schimmel_kg,
       case when portion = 'entsorgt' then 0 else m1 * (1 - f) * a_klein_n end     as klein_kg,
       case when portion = 'entsorgt' then 0 else m1 * (1 - f) * a_gross_n end     as nebenkanal_kg,
       case when portion = 'entsorgt' then 0
            else m1 * (1 - f) * (1 - a_klein_n - a_gross_n) * a_fax end            as fax_kg,
       case when portion = 'entsorgt' then 0
            else m1 * (1 - f) * (1 - a_klein_n - a_gross_n) * (1 - a_fax) end      as verkaufsfaehig_kg,
       kohorte,
       case when portion = 'entsorgt' then 0 else geliefert_kg end                 as geliefert_kg,
       ueberzaehlung_kg,
       case when portion = 'entsorgt' then 0 else n_lieferungen end                as n_lieferungen,
       verkaufsfaehig_anteil
  from kaskade
 with no data;
create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, portion, coalesce(kohorte, date '1900-01-01'));
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);
comment on materialized view mv_kaskade is
  'Die Massenkaskade je Charge, Eingangstag und Portion. Drei Portionen: „ausgelagert" ist die Eingangsmasse hinter '
  'den verkauften und in den Nebenkanal gegangenen Lieferungen, „entsorgt" die hinter dem Kompost (0065 — nur um die '
  'Verdunstung zurückgerechnet, weil entsorgte Ware selbst das Faule ist), „lager" der Rest, der noch liegt. Je Portion '
  'die Ströme Verdunstung, Faules, zu klein, Nebenkanal, Fax und verkaufsfähig. Seit 0106 ist f der Palox-Anteil über '
  'den Weg der Charge (palox_f: p_hand, p_wasch, f_ws, f_s, g_w) — für Ausgelagertes die eigene Messung, für Liegendes '
  'die Erwartung der Sorte (f_quelle sagt es; f_geliehen: aus allen Sorten). b_ws/b_s/b_w sind die Zuwächse je Woche '
  'der Kennzahl (0105), zuwachs_bekannt sagt, ob die Prognose fortschreiben darf. Kein Sockel mehr.';
grant select on mv_kaskade to authenticated;

create view v_kaskade with (security_invoker = true) as
select charge_nr, sorte, schlag, portion, alter_tage, eingang_kg, m0, m1, m2,
       r, f, f_unten, f_oben, f_se, f_ws, f_s, g_w, p_hand, p_wasch, f_quelle, f_geliehen,
       b_ws, b_s, b_w, zuwachs_bekannt,
       a_klein_n, a_gross_n, a_fax, d_m1_r,
       r_n, r_basis, klein_n, klein_basis, gross_n, gross_basis, f_n, fax_n, fax_basis,
       r_bekannt, f_bekannt, a_klein_bekannt, a_gross_bekannt, a_fax_bekannt,
       verdunstung_kg, schimmel_kg, klein_kg, nebenkanal_kg, fax_kg, verkaufsfaehig_kg,
       kohorte, geliefert_kg, ueberzaehlung_kg, n_lieferungen, verkaufsfaehig_anteil
  from mv_kaskade;
comment on view v_kaskade is
  'Der Massenfluss je Charge, Eingangstag und Portion: Was eingelagert wurde (eingang_kg) verteilt sich auf Verdunstung, '
  'Faules, zu klein, Nebenkanal, Fax und verkaufsfähige Ware. Die Ströme addieren sich zum Eingang. "Verlust" ist hier '
  'nur, was wirklich verloren ist: verdunstung_kg, schimmel_kg. klein_kg und nebenkanal_kg sind kein Verlust, sondern ein '
  'anderer Kanal. Seit 0106 ohne Sockel; f kommt aus den Stationswerten (f_quelle).';
grant select on v_kaskade to authenticated;

-- ---------------------------------------------------------------------
-- 4. Die Kaskade auseinandergelegt — ohne den Strom „Nicht lagerbedingt"
-- ---------------------------------------------------------------------
-- Was der Sockel war (Erde, Hagelnarben, Schnittfehler im Palox), steckt
-- jetzt im Stationswert: Was ein Auge in den Palox legt, ist Faules dieser
-- Station, ob es gefault hat oder nicht. Der Betrieb liest nicht mehr zwei
-- Ströme, wo er einen Palox sieht.
create materialized view mv_hochrechnung as
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage, k.eingang_kg,
       zahl(c.m0)::numeric(14,2)                                         as portion_kg,
       k.f_geliehen, k.f_n, k.f_se,
       s.strom, s.buch,
       (case when s.bekannt then zahl(s.kg) end)::numeric(14,2)          as kg,
       zahl(s.basis_kg)::numeric(14,2)                                   as basis_kg,
       (case when s.bekannt then zahl(s.koeffizient, 6, 100000) end)::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel,
       s.d_r, s.d_f, s.d_a,
       s.koeff_art, s.bekannt as koeff_bekannt, k.kohorte
  from v_kaskade k
  cross join lateral (
    select greatest(k.m0, 0) as m0, greatest(k.m1, 0) as m1, greatest(k.m2, 0) as m2,
           greatest(k.verkaufsfaehig_kg, 0) as verkaufsfaehig_kg,
           least(greatest(k.r, 0), 1) as r, least(greatest(k.f, 0), 1) as f,
           least(greatest(k.a_klein_n, 0), 1) as a_klein_n, least(greatest(k.a_gross_n, 0), 1) as a_gross_n,
           least(greatest(k.a_fax, 0), 1) as a_fax
  ) c
  cross join lateral (values
    ('Verdunstung'::text, 'verlust'::text, c.m0 - c.m1, c.m0, c.r, k.r_n, k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'::text,
     -k.d_m1_r, 0::numeric, 0::numeric, null::text, k.r_bekannt),
    ('Schimmel/Fäulnis', 'verlust', c.m1 * c.f, c.m1, c.f, k.f_n, k.f_quelle,
     'Masse nach Verdunstung × Palox-Anteil der Stationen auf dem Weg der Charge (0106)',
     k.d_m1_r * c.f, c.m1, 0::numeric, null::text, k.f_bekannt),
    ('Zu klein (Tierfutter)', 'marge', c.m1 * (1 - c.f) * c.a_klein_n, c.m2, c.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust',
     k.d_m1_r * (1 - c.f) * c.a_klein_n, -c.m1 * c.a_klein_n, c.m2, 'ausschuss', k.a_klein_bekannt),
    ('Nebenkanal zu gross', 'marge', c.m1 * (1 - c.f) * c.a_gross_n, c.m2, c.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal',
     k.d_m1_r * (1 - c.f) * c.a_gross_n, -c.m1 * c.a_gross_n, c.m2, 'nebenkanal', k.a_gross_bekannt),
    ('Faul beim Abpacken (Fax)', 'verlust', c.m1 * (1 - c.f) * (1 - c.a_klein_n - c.a_gross_n) * c.a_fax,
     c.m2 * (1 - c.a_klein_n - c.a_gross_n), c.a_fax, k.fax_n, k.fax_basis,
     'Verkaufsfähige Masse × Anteil Faules, das beim Etikettieren aussortiert wird — vom Waschen und Stehen, nicht von der Lagerdauer',
     k.d_m1_r * (1 - c.f) * (1 - c.a_klein_n - c.a_gross_n) * c.a_fax,
     -c.m1 * (1 - c.a_klein_n - c.a_gross_n) * c.a_fax, c.m2 * (1 - c.a_klein_n - c.a_gross_n), 'fax', k.a_fax_bekannt),
    ('Verkaufsfähig', 'bilanz', c.verkaufsfaehig_kg, c.m2, null::numeric, null::int, null::text, 'Rest der Kaskade',
     0::numeric, 0::numeric, 0::numeric, null::text, true)
  ) s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel, d_r, d_f, d_a, koeff_art, bekannt)
 with no data;
create index if not exists mv_hochrechnung_charge on mv_hochrechnung (charge_nr, buch);
comment on materialized view mv_hochrechnung is
  'v_hochrechnung, gespeichert. Inhaltlich gleich; erneuert von auswertung_schritt(3).';
grant select on mv_hochrechnung to authenticated;

create view v_hochrechnung with (security_invoker = true) as
select charge_nr, sorte, schlag, portion, alter_tage, eingang_kg, portion_kg, f_geliehen, f_n, f_se,
       strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel, d_r, d_f, d_a,
       koeff_art, koeff_bekannt, kohorte
  from mv_hochrechnung;
comment on view v_hochrechnung is
  'Die Kaskade auseinandergelegt: eine Zeile je Charge, Portion und Strom, mit dem verwendeten Koeffizienten, seiner '
  'Herkunft (koeff_art, beim Faulen koeff_basis = f_quelle), der Zahl der Messungen dahinter (koeff_n) und der Formel. '
  'koeff_bekannt = false heisst: geschätzt, nicht gemessen. f_geliehen: der Palox-Anteil kommt aus den Arbeiten aller '
  'Sorten (0106).';
grant select on v_hochrechnung to authenticated;

-- ---------------------------------------------------------------------
-- 5. Die Ströme je Gruppe — die Unsicherheit des Faulen aus seinem Band
-- ---------------------------------------------------------------------
-- Bis 0105 kam die Streuung des Faulen aus der Kovarianz der Anpassung
-- (Delta-Methode über η), dazu der Selektionszuschlag. Jetzt aus dem Band
-- des Stationswerts: f_se je Zeile, ∂kg/∂f · f_se über die Zeilen summiert
-- (die Zeilen einer Sorte teilen denselben Wert — sie schwanken gemeinsam,
-- nicht unabhängig). kg_extrapoliert heisst seit 0106: mit einem
-- geliehenen Anteil gerechnet (aus allen Sorten), nicht mehr „über den
-- Messbereich des Modells hinaus".
create or replace view v_verlust_je_gruppe with (security_invoker = true) as
with gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from v_kaskade_basis
  union all select 'sorte',  sorte,           charge_nr from v_kaskade_basis
  union all select 'schlag', schlag,          charge_nr from v_kaskade_basis
  union all select 'charge', charge_nr::text, charge_nr from v_kaskade_basis
), zeilen as materialized (
  select g.gruppe, g.schluessel, h.charge_nr, h.sorte, h.portion, h.f_geliehen, h.f_n, h.f_se,
         h.strom, h.buch, h.kg, h.basis_kg, h.koeff_n, h.koeff_basis, h.formel,
         h.d_r, h.d_f, h.d_a, h.koeff_art, h.koeff_bekannt,
         (h.strom = 'Faul beim Abpacken (Fax)' and h.portion = 'lager') as erwartet
    from mv_hochrechnung h
    join gruppen g on g.charge_nr = h.charge_nr
   where h.buch in ('verlust', 'marge')
), unsicherheit as materialized (
  select art, sorte, b, varianz_eigen, gewicht_gesamt, varianz_gesamt, df from v_koeff_unsicherheit
), eingang as materialized (
  select g.gruppe, g.schluessel, sum(b.eingang_kg) as eingang_kg, count(*)::int as n_chargen
    from gruppen g join v_kaskade_basis b on b.charge_nr = g.charge_nr
   group by g.gruppe, g.schluessel
), je_sorte as materialized (
  select gruppe, schluessel, strom, buch, sorte, max(koeff_art) as koeff_art,
         sum(d_r) as g_r, sum(d_a) as g_a
    from zeilen
   where not erwartet
   group by gruppe, schluessel, strom, buch, sorte
), je_strom_f as materialized (
  select gruppe, schluessel, strom, buch,
         sum(d_f * f_se) as g_f,
         min(f_n)        as f_n_min
    from zeilen
   where not erwartet
   group by gruppe, schluessel, strom, buch
), varianz_r as materialized (
  select s.gruppe, s.schluessel, s.strom, s.buch,
         sum(power(s.g_r, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_r * coalesce(u.gewicht_gesamt, 1)), 2) * max(coalesce(u.varianz_gesamt, 0)) as varianz,
         min(coalesce(u.df, 1)) as df
    from je_sorte s
    left join unsicherheit u on u.art = 'verdunstung' and u.sorte is not distinct from s.sorte
   group by s.gruppe, s.schluessel, s.strom, s.buch
), varianz_a as materialized (
  select s.gruppe, s.schluessel, s.strom, s.buch,
         sum(power(s.g_a, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_a * coalesce(u.gewicht_gesamt, 1)), 2) * max(coalesce(u.varianz_gesamt, 0)) as varianz,
         min(coalesce(u.df, 1)) as df
    from je_sorte s
    left join unsicherheit u on u.art = s.koeff_art and u.sorte is not distinct from s.sorte
   where s.koeff_art is not null
   group by s.gruppe, s.schluessel, s.strom, s.buch
), varianz_f as materialized (
  select gruppe, schluessel, strom, buch,
         power(g_f, 2)                              as varianz,
         greatest(coalesce(f_n_min, 2) - 1, 1)       as df
    from je_strom_f
), summe as materialized (
  select z.gruppe, z.schluessel, z.strom, z.buch,
         sum(z.kg) filter (where not z.erwartet)                              as kg,
         bool_and(z.koeff_bekannt)                                            as bekannt,
         sum(z.kg) filter (where z.portion = 'ausgelagert')                   as kg_beobachtet,
         sum(z.kg) filter (where z.portion = 'lager' and not z.erwartet)      as kg_projiziert,
         sum(z.kg) filter (where z.f_geliehen and not z.erwartet)             as kg_extrapoliert,
         sum(z.kg) filter (where z.erwartet)                                  as kg_erwartet,
         min(z.koeff_n)                                                       as koeff_n_min,
         sum(z.basis_kg)                                                      as basis_kg,
         max(z.koeff_basis)                                                   as koeff_basis,
         max(z.koeff_art)                                                     as koeff_art,
         max(z.formel)                                                        as formel
    from zeilen z
   group by z.gruppe, z.schluessel, z.strom, z.buch
)
select s.gruppe, s.schluessel, s.strom, s.buch,
       (case when s.bekannt then zahl(s.kg) end)::numeric(14,2)                                     as kg,
       (case when s.bekannt then zahl(greatest(s.kg - g.t * g.streuung, 0)) end)::numeric(14,2)     as kg_unten,
       (case when s.bekannt then zahl(s.kg + g.t * g.streuung) end)::numeric(14,2)                  as kg_oben,
       (case when s.bekannt then zahl(coalesce(s.kg_beobachtet, 0)) end)::numeric(14,2)             as kg_beobachtet,
       (case when s.bekannt then zahl(coalesce(s.kg_projiziert, 0)) end)::numeric(14,2)             as kg_projiziert,
       (case when s.bekannt then zahl(coalesce(s.kg_extrapoliert, 0)) end)::numeric(14,2)           as kg_extrapoliert,
       (case when s.bekannt then zahl(coalesce(s.kg_erwartet, 0)) end)::numeric(14,2)               as kg_erwartet,
       s.koeff_n_min,
       (case when s.bekannt then zahl(g.streuung) end)::numeric(14,2)                               as streuung_kg,
       g.df,
       zahl(s.basis_kg)::numeric(14,2)                                                              as basis_kg,
       s.koeff_basis, s.koeff_art, s.formel, s.bekannt,
       zahl(e.eingang_kg)::numeric(14,2)                                                            as eingang_kg,
       e.n_chargen
  from summe s
  join eingang e on e.gruppe = s.gruppe and e.schluessel = s.schluessel
  left join varianz_r vr on vr.gruppe = s.gruppe and vr.schluessel = s.schluessel and vr.strom = s.strom and vr.buch = s.buch
  left join varianz_a va on va.gruppe = s.gruppe and va.schluessel = s.schluessel and va.strom = s.strom and va.buch = s.buch
  left join varianz_f vf on vf.gruppe = s.gruppe and vf.schluessel = s.schluessel and vf.strom = s.strom and vf.buch = s.buch
  cross join lateral (
    select sqrt(greatest(coalesce(vr.varianz, 0) + coalesce(va.varianz, 0) + coalesce(vf.varianz, 0), 0)) as streuung,
           least(coalesce(vr.df, 999), coalesce(va.df, 999), coalesce(vf.df, 999)) as df
  ) g0
  cross join lateral (select g0.streuung, g0.df, t_quantil_95(g0.df) as t) g;
comment on view v_verlust_je_gruppe is
  'Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, Charge). kg_beobachtet ist gemessen, '
  'kg_projiziert auf noch nicht Gemessenes übertragen, kg_extrapoliert seit 0106 mit einem aus allen Sorten geliehenen '
  'Palox-Anteil gerechnet — drei verschiedene Sicherheiten, darum drei Spalten. Ist der Strom gemessen (bekannt), sind '
  'alle vier Teilbeträge Zahlen und kg_beobachtet + kg_projiziert = kg. Das Band kg_unten/kg_oben kommt aus der '
  'Unsicherheit der Koeffizienten, beim Faulen aus dem Band des Stationswerts (f_se).';
grant select on v_verlust_je_gruppe to authenticated;

create materialized view erg_verlust as
select gruppe, schluessel, strom, buch, kg, kg_unten, kg_oben, kg_beobachtet, kg_projiziert, kg_extrapoliert,
       kg_erwartet, koeff_n_min, streuung_kg, df, basis_kg, koeff_basis, koeff_art, formel, bekannt, eingang_kg, n_chargen
  from v_verlust_je_gruppe
 with no data;
create unique index if not exists erg_verlust_pk on erg_verlust (gruppe, schluessel, strom);
comment on materialized view erg_verlust is
  'v_verlust_je_gruppe, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';
grant select on erg_verlust to authenticated;
grant select on v_verlust_ranking to authenticated;
grant select on v_schimmel_punkte to authenticated;


create or replace view v_marge_buch with (security_invoker = true) as
WITH verkauf AS (
         SELECT sum(v_ueberfuellung_verkauf.verschenkt_kg) AS verschenkt_kg,
            sum(
                CASE
                    WHEN v_ueberfuellung_verkauf.verschenkt_kg IS NULL THEN NULL::numeric
                    ELSE GREATEST(v_ueberfuellung_verkauf.verschenkt_kg - COALESCE(v_ueberfuellung_verkauf.verschenkt_fehler_kg, 0::numeric), 0::numeric)
                END) AS verschenkt_unten_kg,
            sum(v_ueberfuellung_verkauf.verschenkt_kg + COALESCE(v_ueberfuellung_verkauf.verschenkt_fehler_kg, 0::numeric)) AS verschenkt_oben_kg,
            sum(v_ueberfuellung_verkauf.kisten_verkauft) FILTER (WHERE v_ueberfuellung_verkauf.n_wiegungen > 0) AS kisten_gerechnet,
            sum(v_ueberfuellung_verkauf.kisten_verkauft) FILTER (WHERE v_ueberfuellung_verkauf.n_wiegungen = 0) AS kisten_ungewogen,
            sum(v_ueberfuellung_verkauf.n_wiegungen) AS n_wiegungen,
            sum(v_ueberfuellung_verkauf.kisten_gewogen) AS kisten_gewogen,
            sum(v_ueberfuellung_verkauf.zuviel_je_kiste * v_ueberfuellung_verkauf.kisten_gewogen::numeric) / NULLIF(sum(v_ueberfuellung_verkauf.kisten_gewogen) FILTER (WHERE v_ueberfuellung_verkauf.zuviel_je_kiste IS NOT NULL), 0::numeric) AS zuviel_je_kiste,
            count(*) FILTER (WHERE v_ueberfuellung_verkauf.n_lieferungen > 0)::integer AS n_gruppen_verkauft
           FROM v_ueberfuellung_verkauf
          WHERE v_ueberfuellung_verkauf.gruppe = 'sorte'::text AND v_ueberfuellung_verkauf.kistensystem = 'kiste_ab'::text
        ), datei AS (
         SELECT count(*)::integer AS n
           FROM lieferung_import
        )
 SELECT r.strom AS posten,
    r.kg,
    r.kg_unten,
    r.kg_oben,
        CASE r.strom
            WHEN 'Nebenkanal zu gross'::text THEN 'Ware über der oberen Kalibergrenze geht in einen anderen Verkaufskanal — nicht weg, nur nicht zum besten Preis'::text
            WHEN 'Zu klein (Tierfutter)'::text THEN 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'::text
            ELSE ''::text
        END AS erlaeuterung,
    r.kg IS NOT NULL AS gemessen
   FROM erg_verlust r
  WHERE r.gruppe = 'gesamt'::text AND r.buch = 'marge'::text
UNION ALL
 SELECT 'Überfüllung der Kisten'::text AS posten,
    zahl(v.verschenkt_kg)::numeric(14,2) AS kg,
    zahl(v.verschenkt_unten_kg)::numeric(14,2) AS kg_unten,
    zahl(v.verschenkt_oben_kg)::numeric(14,2) AS kg_oben,
        CASE
            WHEN d.n = 0 THEN 'Keine Verkaufsdatei eingelesen — wie viele Kisten „ab x kg" verkauft wurden, weiss die App nicht. Nichts gerechnet.'::text
            WHEN COALESCE(v.n_wiegungen, 0::bigint) = 0 THEN format('%s Kisten „ab x kg" laut Verkaufsdatei verkauft, aber keine fertige Palette dieses Systems gewogen — nichts gerechnet.'::text, round(COALESCE(v.kisten_ungewogen, 0::numeric)))
            ELSE format(('%s gewogene Paletten (%s Kisten): im Schnitt %s kg je Kiste über dem Soll. '::text || 'Verkauft laut Verkaufsdatei: %s Kisten desselben Systems — daraus die Zahl. '::text) || '%s'::text, v.n_wiegungen, round(COALESCE(v.kisten_gewogen, 0::numeric)), round(COALESCE(v.zuviel_je_kiste, 0::numeric), 3), round(COALESCE(v.kisten_gerechnet, 0::numeric)),
            CASE
                WHEN COALESCE(v.kisten_ungewogen, 0::numeric) > 0::numeric THEN format('Weitere %s verkaufte Kisten haben kein gewogenes Gegenstück (Sorte oder Soll ohne Wägung) und sind nicht gerechnet.'::text, round(v.kisten_ungewogen))
                ELSE 'Kisten nach Stück haben kein Sollgewicht und damit keine Überfüllung.'::text
            END)
        END AS erlaeuterung,
    v.verschenkt_kg IS NOT NULL AS gemessen
   FROM verkauf v
     CROSS JOIN datei d;
comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb verlassen hat, ohne verkaufsfähig zu sein — zu klein, Nebenkanal, Überfüllung. Kein '
  'Verlust im Sinne von verdorben, sondern Masse in einem anderen Kanal. kg_unten und kg_oben spannen den Bereich auf, '
  'gemessen sagt, ob dahinter Messungen oder Schätzungen stehen.';
grant select on v_marge_buch to authenticated;


-- ---------------------------------------------------------------------
-- 6. Je Charge bis heute — ohne Sockel, mit dem Anteil und seiner Quelle
-- ---------------------------------------------------------------------
-- Wie 0101, nur: kein sockel_heute_kg, kein sockel_nachgewiesen, kein
-- sockel_oben_kg; dafür faul_anteil (womit das Liegende rechnet) und
-- faul_quelle (woher der Anteil kommt) — für die Chargen-Seite.
create or replace view v_hochrechnung_basis with (security_invoker = true) as
with je_charge as (
  select charge_nr,
         sum(m0) filter (where portion = 'ausgelagert')                       as ausgelagert_kg,
         sum(m0 * alter_tage) filter (where portion = 'ausgelagert')
           / nullif(sum(m0) filter (where portion = 'ausgelagert'), 0)        as alter_ausgelagert,
         sum(m0) filter (where portion = 'lager')                             as lager_kg,
         sum(m0 * alter_tage) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as alter_lager,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager')              as verkaufsfaehig_lager_kg,
         sum(geliefert_kg)                                                    as geliefert_kg,
         sum(ueberzaehlung_kg)                                                as ueberzaehlung_kg,
         sum(n_lieferungen)::int                                              as n_lieferungen,
         min(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_von,
         max(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_bis,
         count(*) filter (where portion = 'lager' and m0 > 0)::int            as n_rest_kohorten,
         sum(m0 * (kohorte - date '2000-01-01')) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as rest_tage_seit_epoche,
         -- 0064: jede Stromsumme nur, wenn ihr Koeffizient gemessen ist.
         -- Das `coalesce` innerhalb der Bedingung trennt zwei Sorten NULL:
         -- „der Koeffizient ist unbekannt" (dann bleibt die ganze Summe NULL)
         -- von „diese Portion gibt es nicht" — eine Charge ohne Lieferung hat
         -- keine Zeile mit portion = 'ausgelagert', und dort ist 0 richtig.
         case when bool_and(r_bekannt)  then coalesce(sum(verdunstung_kg), 0) end as verdunstung_heute_kg,
         case when bool_and(f_bekannt)  then coalesce(sum(schimmel_kg), 0)    end as schimmel_heute_kg,
         -- 0097: Der Sockel a₀ ist der Anteil, der schon am ersten Tag faul
         -- war — er gilt nur, wenn die Daten ihn belegen (sockel_nachweis).
         -- Solange sie es nicht tun, ist er 0, nicht unbekannt: mv_kaskade
         -- rechnet ihn dann mit 0. Bis 0096 hing hier a0_bekannt, und weil
         -- das Verderbsmodell mit zwölf Punkten noch nicht brauchbar war,
         -- stand am ersten Tag mit echten Zahlen überall „Verlust bis heute —".
         -- 0101: umgedeutet — zu klein und zu gross, das hinter den Lieferungen
         -- aussortiert wurde und im Haus steht (Teil von im_haus_heute_kg).
         -- Der Name bleibt: Spalten werden nie weggenommen.
         case when bool_and(a_klein_bekannt and a_gross_bekannt)
              then coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'ausgelagert'), 0)
              end                                                             as kanal_ausgelagert_kg,
         case when bool_and(a_fax_bekannt)
              then coalesce(sum(fax_kg) filter (where portion = 'ausgelagert'), 0) end as fax_heute_kg,
         case when bool_and(a_fax_bekannt)
              then coalesce(sum(fax_kg) filter (where portion = 'lager'), 0) end       as fax_erwartet_kg,
         -- 0101: Zu klein und zu gross, das hinter den Lieferungen aussortiert
         -- wurde, hat den Betrieb nicht verlassen — es steht im Haus, bis ein
         -- Lieferschein es holt (der Betrieb: „die stehen dann schon noch im
         -- Lager … rechne die noch nicht zum Verkauf"). Darum zählt es zu „im
         -- Haus": nicht verkaufsfähig, aber da. Bis 0100 stand es als „anderer
         -- Kanal am Ausgelagerten" neben dem Ausgang, als wäre es weg.
         -- Die Summe ist die Zahl der Kaskade: Ist die Rate nicht gemessen,
         -- rechnet sie dort 0 (kanal_bekannt sagt es; kanal_ausgelagert_kg
         -- bleibt leer). Ohne liegende Portion ist das Liegende 0, nicht leer —
         -- sonst verschwände das Aussortierte mit ihm.
         coalesce(sum(m2) filter (where portion = 'lager'), 0)
           + coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'ausgelagert'), 0)
                                                                              as im_haus_heute_kg,
         case when bool_and(a_klein_bekannt and a_gross_bekannt)
              then coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'lager'), 0)
              end                                                             as kanal_im_haus_kg,
         bool_and(r_bekannt and f_bekannt and a_fax_bekannt
                  and a_klein_bekannt and a_gross_bekannt)                     as verlust_bekannt,
         bool_and(r_bekannt)                                                   as verdunstung_bekannt,
         bool_and(f_bekannt)                                                   as schimmel_bekannt,
         bool_and(a_fax_bekannt)                                               as fax_bekannt,
         bool_and(a_klein_bekannt and a_gross_bekannt)                         as kanal_bekannt,
         -- 0106: der Anteil, mit dem das Liegende rechnet, und woher er kommt
         sum(m1 * f) filter (where portion = 'lager')
           / nullif(sum(m1) filter (where portion = 'lager'), 0)              as faul_anteil_lager,
         max(f_quelle) filter (where portion = 'lager')                        as faul_quelle,
         -- 0064: gab es zu dieser Charge überhaupt eine Kaskadenzeile?
         count(*) > 0                                                          as gerechnet,
         count(*) filter (where portion = 'lager') > 0                         as hat_lager
    from mv_kaskade
   group by charge_nr
)
select b.charge_nr, b.schlag, b.sorte,
       b.eingang_kg,
       b.n_paletten,
       b.eingangsdatum_mittel,
       zahl(coalesce(k.ausgelagert_kg, 0), 2, 1e12)::numeric(14,2)             as ausgelagert_kg,
       zahl(k.alter_ausgelagert, 1, 1e5)::numeric(8,1)                         as alter_ausgelagert,
       -- 0064: keine Kaskadenzeile → es liegt noch alles. Zeilen, aber keine
       -- Portion „lager" → es liegt nichts mehr. Bisher hiess beides „alles".
       zahl(case when k.gerechnet is not true then b.eingang_kg
                 else coalesce(k.lager_kg, 0) end, 2, 1e12)::numeric(14,2)     as lager_kg,
       zahl(coalesce(k.alter_lager, (b.stichtag - b.eingangsdatum_mittel)), 1, 1e5)::numeric(8,1)
                                                                              as alter_lager,
       zahl((heute() - x.rest_datum), 1, 1e5)::numeric(8,1)                    as alter_lager_heute,
       b.weg2_anteil,
       b.stichtag,
       b.n_paletten_mit_netto,
       zahl(coalesce(k.ueberzaehlung_kg, 0), 2, 1e12)::numeric(14,2)           as ueberzaehlung_kg,
       b.sortiert_kg, b.gewaschen_kg, b.wartet_kg, b.anteil_gewaschen, b.alter_band, b.am_band_kg,
       x.rest_datum                                                           as eingangsdatum_rest,
       (coalesce(k.n_lieferungen, 0) > 0)                                     as rest_alter_aus_zaehlung,
       b.eingang_von, b.eingang_bis, b.n_eingangstage,
       coalesce(k.rest_von, b.eingang_von)                                    as rest_von,
       coalesce(k.rest_bis, b.eingang_bis)                                    as rest_bis,
       round(case when k.gerechnet is not true then b.eingang_kg else coalesce(k.lager_kg, 0) end
             / nullif(b.eingang_kg / nullif(b.n_paletten, 0), 0))::int        as n_rest_paletten,
       coalesce(k.n_rest_kohorten, b.n_eingangstage)                          as n_rest_kohorten,
       (heute() - coalesce(k.rest_bis, b.eingang_bis))::int                   as alter_lager_von,
       (heute() - coalesce(k.rest_von, b.eingang_von))::int                   as alter_lager_bis,
       zahl(coalesce(k.geliefert_kg, 0), 2, 1e12)::numeric(14,2)              as geliefert_kg,
       zahl(k.verkaufsfaehig_lager_kg, 2, 1e12)::numeric(14,2)                 as verkaufsfaehig_lager_kg,
       coalesce(k.n_lieferungen, 0)                                           as n_lieferungen,
       zahl(k.verdunstung_heute_kg, 2, 1e12)::numeric(14,2)                   as verdunstung_heute_kg,
       zahl(k.schimmel_heute_kg, 2, 1e12)::numeric(14,2)                      as schimmel_heute_kg,
       zahl(k.fax_heute_kg, 2, 1e12)::numeric(14,2)                           as fax_heute_kg,
       -- Der Verlust ist die Summe von vier Strömen. Fehlt einer, ist die
       -- Summe unbekannt — nicht die Summe der übrigen.
       zahl(k.verdunstung_heute_kg + k.schimmel_heute_kg + k.fax_heute_kg,
            2, 1e12)::numeric(14,2)                                           as verlust_heute_kg,
       zahl(k.kanal_ausgelagert_kg, 2, 1e12)::numeric(14,2)                   as kanal_ausgelagert_kg,
       zahl(k.fax_erwartet_kg, 2, 1e12)::numeric(14,2)                        as fax_erwartet_kg,
       zahl(case when k.gerechnet is not true then b.eingang_kg
                 else coalesce(k.im_haus_heute_kg, 0) end, 2, 1e12)::numeric(14,2) as im_haus_heute_kg,
       zahl(k.kanal_im_haus_kg, 2, 1e12)::numeric(14,2)                       as kanal_im_haus_kg,
       coalesce(k.verlust_bekannt, false)                                     as verlust_bekannt,
       coalesce(k.verdunstung_bekannt, false)                                 as verdunstung_bekannt,
       coalesce(k.schimmel_bekannt, false)                                    as schimmel_bekannt,
       coalesce(k.fax_bekannt, false)                                         as fax_bekannt,
       coalesce(k.kanal_bekannt, false)                                       as kanal_bekannt,
       zahl(k.faul_anteil_lager, 4, 1)::numeric(6,4)                            as faul_anteil,
       k.faul_quelle,
       heute()                                                                as heute
  from v_kaskade_basis b
  left join je_charge k on k.charge_nr = b.charge_nr
  cross join lateral (
    select case when k.rest_tage_seit_epoche is not null
                then date '2000-01-01' + round(k.rest_tage_seit_epoche)::int
                else b.eingangsdatum_mittel end as rest_datum
  ) x
 where b.eingang_kg is not null;
comment on view v_hochrechnung_basis is
  'Je Charge, alles bis heute: Eingang und geliefert (gemessen), ausgelagert (Eingangsmasse hinter den Lieferungen), '
  'lager_kg (Eingang minus ausgelagert, in Eingangskilo), verlust_heute_kg (Verdunstung + Faules + Fax am Abgepackten), '
  'im_haus_heute_kg (Eingangsmasse, die noch liegt, nach Verdunstung und Verderb, plus hinter den Lieferungen '
  'Aussortiertes, 0101). Keine Prognose. 0064: Jede Stromsumme ist NULL, solange ihr Koeffizient keine Messung hat. '
  'Seit 0106 ohne Sockel; faul_anteil und faul_quelle sagen, womit das Liegende rechnet und woher es kommt.';
grant select on v_hochrechnung_basis to authenticated;


create materialized view erg_charge as
SELECT charge_nr,
    schlag,
    sorte,
    eingang_kg,
    n_paletten,
    eingangsdatum_mittel,
    ausgelagert_kg,
    alter_ausgelagert,
    lager_kg,
    alter_lager,
    alter_lager_heute,
    weg2_anteil,
    stichtag,
    n_paletten_mit_netto,
    ueberzaehlung_kg,
    sortiert_kg,
    gewaschen_kg,
    wartet_kg,
    anteil_gewaschen,
    alter_band,
    am_band_kg,
    eingangsdatum_rest,
    rest_alter_aus_zaehlung,
    eingang_von,
    eingang_bis,
    n_eingangstage,
    rest_von,
    rest_bis,
    n_rest_paletten,
    n_rest_kohorten,
    alter_lager_von,
    alter_lager_bis,
    geliefert_kg,
    verkaufsfaehig_lager_kg,
    n_lieferungen,
    verdunstung_heute_kg,
    schimmel_heute_kg,
    fax_heute_kg,
    verlust_heute_kg,
    kanal_ausgelagert_kg,
    fax_erwartet_kg,
    im_haus_heute_kg,
    kanal_im_haus_kg,
    verlust_bekannt,
    verdunstung_bekannt,
    schimmel_bekannt,
    fax_bekannt,
    kanal_bekannt,
    faul_anteil,
    faul_quelle,
    heute
   FROM v_hochrechnung_basis
with no data;
create unique index if not exists erg_charge_pk on erg_charge (charge_nr);
create index if not exists erg_charge_sorte on erg_charge (sorte);
comment on materialized view erg_charge is
  'v_hochrechnung_basis, gespeichert für die App (0062). Erneuert mit auswertung_schritt(). Seit 0101 zählt '
  'im_haus_heute_kg das hinter den Lieferungen Aussortierte mit (kanal_ausgelagert_kg: zu klein und zu gross, im Haus, '
  'nicht verkaufsfähig). Seit 0106 ohne Sockel, mit faul_anteil und faul_quelle.';
grant select on erg_charge to authenticated;


create view v_kontrolle_vorschlag with (security_invoker = true) as
SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lager_kg,
    b.alter_lager_von,
    b.alter_lager_bis,
    b.eingang_von,
    b.eingang_bis,
    COALESCE(k.n_kontrollen, 0) AS n_kontrollen,
    k.zuletzt,
    b.im_haus_heute_kg,
    heute() - COALESCE(k.zuletzt, b.eingang_von) AS tage_seit_wiegung,
    zahl(b.im_haus_heute_kg * GREATEST(heute() - COALESCE(k.zuletzt, b.eingang_von), 1)::numeric, 0, '10000000000000'::numeric)::numeric(14,0) AS informationswert
   FROM erg_charge b
     LEFT JOIN ( SELECT verdunstung_wiegung.charge_nr,
            count(*) FILTER (WHERE verdunstung_wiegung.auftrag_id IS NULL)::integer AS n_kontrollen,
            max(verdunstung_wiegung.wiege_ts)::date AS zuletzt
           FROM verdunstung_wiegung
          WHERE verdunstung_wiegung.gemessen
          GROUP BY verdunstung_wiegung.charge_nr) k ON k.charge_nr = b.charge_nr
  WHERE b.im_haus_heute_kg > 0::numeric
  ORDER BY (zahl(b.im_haus_heute_kg * GREATEST(heute() - COALESCE(k.zuletzt, b.eingang_von), 1)::numeric, 0, '10000000000000'::numeric)::numeric(14,0)) DESC NULLS LAST, b.im_haus_heute_kg DESC
 LIMIT 3;
comment on view v_kontrolle_vorschlag is
  'Welche Charge als Nächstes kontrolliert werden sollte. informationswert gewichtet, wie viel noch im Haus liegt, '
  'wie lange die letzte Wiegung her ist und wie unsicher die Charge bisher ist — eine Reihenfolge, kein Befehl.';
grant select on v_kontrolle_vorschlag to authenticated;


-- Die Probe aufs Exempel: Was am Band ankommen müsste, ist die Masse der
-- Bandarbeiten nach Verdunstung und nach dem Palox-Anteil der Sortier-
-- station — der eigene der Charge, sonst die Erwartung der Sorte. Ohne
-- Wert ist das Modell am Band unbekannt, nicht 0.
create or replace view v_massenbilanz with (security_invoker = true) as
WITH csv_anteil AS MATERIALIZED (
         SELECT am.charge_nr,
            COALESCE(sum(am.eingang_netto_kg) FILTER (WHERE (EXISTS ( SELECT 1
                   FROM sortier_lauf l
                  WHERE l.auftrag_id = am.auftrag_id))) / NULLIF(sum(am.eingang_netto_kg), 0::numeric), 0::numeric) AS anteil_mit_csv
           FROM v_auftrag_masse am
          WHERE (am.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND am.eingang_netto_kg IS NOT NULL
          GROUP BY am.charge_nr
        ), gemessen AS MATERIALIZED (
         SELECT v_sortier_lauf_masse.charge_nr,
            sum(v_sortier_lauf_masse.masse_kg) AS gemessen_kg
           FROM v_sortier_lauf_masse
          GROUP BY v_sortier_lauf_masse.charge_nr
        ), rest AS MATERIALIZED (
         SELECT v_kaskade.charge_nr,
            sum(v_kaskade.m2) FILTER (WHERE v_kaskade.portion = 'lager'::text) AS restbestand_kg
           FROM v_kaskade
          GROUP BY v_kaskade.charge_nr
        ), modell AS MATERIALIZED (
         SELECT b_1.charge_nr,
            b_1.am_band_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), COALESCE(b_1.alter_band, 0::numeric)) * (1::numeric - COALESCE(ep.anteil, er.anteil)) * q.anteil_mit_csv AS am_band_modell_kg
           FROM v_kaskade_basis b_1
             LEFT JOIN csv_anteil q ON q.charge_nr = b_1.charge_nr
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b_1.sorte
             LEFT JOIN v_charge_palox ep ON ep.charge_nr = b_1.charge_nr AND ep.station = 'sortieren'::text
             LEFT JOIN v_palox_erwartung er ON er.sorte = b_1.sorte AND er.station = 'sortieren'::text
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.eingang_kg,
    b.ausgelagert_kg,
    b.lager_kg,
    b.n_paletten,
    b.alter_ausgelagert,
    b.alter_lager,
    b.stichtag,
    zahl(m.am_band_modell_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS modell_am_band_kg,
    c.gemessen_kg AS csv_gemessen_kg,
    zahl(c.gemessen_kg - m.am_band_modell_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS abweichung_kg,
        CASE
            WHEN m.am_band_modell_kg > 0::numeric THEN zahl((c.gemessen_kg - m.am_band_modell_kg) / m.am_band_modell_kg, 4, '1000000'::numeric)::numeric(10,4)
            ELSE NULL::numeric
        END AS abweichung_anteil,
    zahl(r.restbestand_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS restbestand_kg,
    kb.alter_band
   FROM erg_charge b
     JOIN v_kaskade_basis kb ON kb.charge_nr = b.charge_nr
     LEFT JOIN modell m ON m.charge_nr = b.charge_nr
     LEFT JOIN gemessen c ON c.charge_nr = b.charge_nr
     LEFT JOIN rest r ON r.charge_nr = b.charge_nr;
comment on view v_massenbilanz is
  'Die Probe aufs Exempel je Charge: Was die Kaskade am Band erwartet (modell_am_band_kg: Bandarbeiten nach Verdunstung '
  'und Palox-Anteil der Sortierstation, 0106) gegen das, was die Sortier-Datei gewogen hat (csv_gemessen_kg). '
  'abweichung_anteil nahe 0 heisst, die Koeffizienten treffen die Wirklichkeit; systematisch positiv heisst, die '
  'Verluste sind überschätzt. Nur für Chargen mit Sortier-Datei aussagekräftig.';
grant select on v_massenbilanz to authenticated;


-- Die Saisonbilanz ohne den Sockel: Verlust = Verdunstung + Faules + Fax.
create or replace view v_saisonbilanz with (security_invoker = true) as
WITH charge AS (
         SELECT sum(erg_charge.eingang_kg) AS eingang_kg,
            sum(erg_charge.ausgelagert_kg) AS ausgelagert_kg,
            sum(erg_charge.geliefert_kg) AS geliefert_kg,
            sum(erg_charge.lager_kg) AS lager_kg,
            sum(erg_charge.wartet_kg) AS wartet_kg,
            sum(erg_charge.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(erg_charge.verkaufsfaehig_lager_kg) AS verkaufsfaehig_heute_kg,
            sum(erg_charge.im_haus_heute_kg) AS im_haus_heute_kg,
            sum(erg_charge.kanal_im_haus_kg) AS kanal_im_haus_kg,
            sum(erg_charge.verlust_heute_kg) AS verlust_heute_kg,
            sum(erg_charge.verdunstung_heute_kg) AS verdunstung_heute_kg,
            sum(erg_charge.schimmel_heute_kg) AS schimmel_heute_kg,
            sum(erg_charge.fax_heute_kg) AS fax_heute_kg,
            sum(erg_charge.fax_erwartet_kg) AS fax_erwartet_kg,
            sum(erg_charge.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            bool_and(erg_charge.verlust_bekannt) AS bekannt,
            count(*)::integer AS n_chargen,
            max(erg_charge.heute) AS heute
           FROM erg_charge
        ), bereich AS (
         SELECT sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_oben_kg,
            sum(erg_verlust.kg) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_kg,
            sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = 'marge'::text) AS kanal_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = 'marge'::text) AS kanal_oben_kg
           FROM erg_verlust
          WHERE erg_verlust.gruppe = 'gesamt'::text
        ), vorlauf AS (
         SELECT COALESCE(sum(charge_vorlauf.ausgang_vor_app_kg), 0::numeric) AS kg
           FROM charge_vorlauf
        ), ausgang AS (
         SELECT COALESCE(sum(v_lieferung_masse.masse_kg), 0::numeric) AS kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'verkauf'::text), 0::numeric) AS verkauf_kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'marge'::text), 0::numeric) AS marge_kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'verlust'::text), 0::numeric) AS entsorgt_kg,
            COALESCE(sum(v_lieferung_masse.masse_fehler_kg), 0::double precision) AS fehler_kg,
            count(*)::integer AS n_lieferungen,
            max(v_lieferung_masse.datum) AS letzte_lieferung
           FROM v_lieferung_masse
          WHERE v_lieferung_masse.datum <= heute()
        ), fax AS (
         SELECT COALESCE(sum(v_fax_beobachtung.masse_kg), 0::numeric) AS kg,
            count(*)::integer AS n
           FROM v_fax_beobachtung
          WHERE v_fax_beobachtung.status = 'abgeschlossen'::auftrag_status AND v_fax_beobachtung.masse_kg IS NOT NULL
        )
 SELECT c.heute,
    zahl(c.eingang_kg)::numeric(14,2) AS eingang_kg,
    c.n_chargen,
    zahl(a.kg + vl.kg)::numeric(14,2) AS ausgang_kg,
    zahl(a.verkauf_kg)::numeric(14,2) AS verkauf_kg,
    zahl(a.marge_kg)::numeric(14,2) AS marge_kg,
    zahl(a.entsorgt_kg)::numeric(14,2) AS entsorgt_kg,
    zahl(a.fehler_kg)::numeric(14,2) AS ausgang_fehler_kg,
    a.n_lieferungen,
    a.letzte_lieferung,
    zahl(vl.kg)::numeric(14,2) AS vorlauf_kg,
    zahl(c.geliefert_kg)::numeric(14,2) AS geliefert_kg,
    zahl(c.ausgelagert_kg)::numeric(14,2) AS ausgelagert_kg,
    zahl(c.verlust_heute_kg)::numeric(14,2) AS verlust_heute_kg,
    zahl(b.verlust_unten_kg)::numeric(14,2) AS verlust_unten_kg,
    zahl(b.verlust_oben_kg)::numeric(14,2) AS verlust_oben_kg,
    zahl(c.verdunstung_heute_kg)::numeric(14,2) AS verdunstung_heute_kg,
    zahl(c.schimmel_heute_kg)::numeric(14,2) AS schimmel_heute_kg,
    zahl(c.fax_heute_kg)::numeric(14,2) AS fax_heute_kg,
    zahl(c.fax_erwartet_kg)::numeric(14,2) AS fax_erwartet_kg,
    zahl(c.kanal_ausgelagert_kg)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(b.kanal_unten_kg)::numeric(14,2) AS kanal_unten_kg,
    zahl(b.kanal_oben_kg)::numeric(14,2) AS kanal_oben_kg,
    zahl(c.im_haus_heute_kg)::numeric(14,2) AS im_haus_heute_kg,
    zahl(c.verkaufsfaehig_heute_kg)::numeric(14,2) AS verkaufsfaehig_heute_kg,
    zahl(c.kanal_im_haus_kg)::numeric(14,2) AS kanal_im_haus_kg,
    zahl(c.lager_kg)::numeric(14,2) AS lager_kg,
    zahl(c.wartet_kg)::numeric(14,2) AS gegenprobe_wartet_kg,
    zahl(c.ueberzaehlung_kg)::numeric(14,2) AS ueberzaehlung_kg,
    zahl(f.kg)::numeric(14,2) AS fax_durchsatz_kg,
    f.n AS n_fax_arbeiten,
    COALESCE(c.bekannt, false) AS verlust_bekannt,
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.im_haus_heute_kg)::numeric(14,2) AS bilanz_rest_kg,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.im_haus_heute_kg) / c.eingang_kg
            ELSE NULL::numeric
        END, 4, '100000'::numeric)::numeric(10,4) AS bilanz_rest_anteil,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (a.kg + vl.kg) / c.eingang_kg
            ELSE NULL::numeric
        END, 4, '100000'::numeric)::numeric(10,4) AS ausgang_deckung,
        CASE
            WHEN COALESCE(c.eingang_kg, 0::numeric) <= 0::numeric THEN 'Es ist kein Wareneingang erfasst. Ohne das Erntejournal gibt es '::text || 'nichts, worauf sich Verlust und Bestand beziehen könnten.'::text
            WHEN COALESCE(c.ueberzaehlung_kg, 0::numeric) > (0.05 * c.eingang_kg) THEN format((('Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — '::text || 'bei einigen Chargen rund %s kg zu viel. Fast immer fehlt der '::text) || 'Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine '::text) || 'Lieferung ist der falschen Charge zugeordnet.'::text, round(c.ueberzaehlung_kg))
            WHEN a.n_lieferungen = 0 AND vl.kg = 0::numeric THEN ('Kein Warenausgang erfasst — dann liegt rechnerisch noch alles im Haus, '::text || 'und der Verlust bis heute gilt für die ganze Eingangsmasse. Sobald die '::text) || 'Lieferscheine eingelesen sind, teilt sich die Ware in ausgeliefert und liegend.'::text
            WHEN NOT COALESCE(c.bekannt, false) THEN 'Ein Verluststrom ist noch nicht gemessen — die Ursachen sind erst '::text || 'vollständig, wenn jeder Koeffizient mindestens eine Messung hat.'::text
            ELSE format((('Bis heute (%s): %s t Eingang = %s t ausgeliefert + %s t Verlust '::text || '(Verdunstung %s t, Faules %s t, Fax %s t) '::text) || '+ %s t noch im Haus (davon %s t verkaufsfähig, %s t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum '::text) || 'Saisonende steht in der Grafik, nicht in diesen Zahlen.%s'::text, to_char(c.heute::timestamp with time zone, 'DD.MM.YYYY'::text), round(c.eingang_kg / 1000.0, 1), round(c.geliefert_kg / 1000.0, 1), round(c.verlust_heute_kg / 1000.0, 1), round(c.verdunstung_heute_kg / 1000.0, 1), round(c.schimmel_heute_kg / 1000.0, 1), round(c.fax_heute_kg / 1000.0, 1), round(c.im_haus_heute_kg / 1000.0, 1), round(c.verkaufsfaehig_heute_kg / 1000.0, 1), round((c.kanal_ausgelagert_kg + c.kanal_im_haus_kg) / 1000.0, 1), concat_ws(' '::text, '',
            CASE
                WHEN a.marge_kg > 0::numeric THEN format('An die Tiere und in den Nebenkanal geliefert: %s kg; hinter den Lieferungen aussortiert gerechnet: %s kg.'::text, round(a.marge_kg), round(c.kanal_ausgelagert_kg))
                ELSE NULL::text
            END,
            CASE
                WHEN a.entsorgt_kg > 0::numeric THEN format('Entsorgt: %s kg, gerechneter Schimmel: %s kg.'::text, round(a.entsorgt_kg), round(c.schimmel_heute_kg))
                ELSE NULL::text
            END,
            CASE
                WHEN COALESCE(c.ueberzaehlung_kg, 0::numeric) > 0::numeric THEN format('%s kg Überzählung.'::text, round(c.ueberzaehlung_kg))
                ELSE NULL::text
            END))
        END AS befund
   FROM charge c
     CROSS JOIN bereich b
     CROSS JOIN ausgang a
     CROSS JOIN vorlauf vl
     CROSS JOIN fax f;
comment on view v_saisonbilanz is
  'Die Saison bis heute in einer Zeile (erg_bilanz). Seit 0101: Eingang + Überzählung = ausgeliefert (Lieferscheine) '
  '+ Verlust bis heute + im Haus — zu klein und zu gross sind Teil von im Haus (kanal_ausgelagert_kg aussortiert, '
  'kanal_im_haus_kg im Liegenden erwartet), nicht Ausgang. Seit 0106 ohne Sockel.';
grant select on v_saisonbilanz to authenticated;


-- ---------------------------------------------------------------------
-- 7. Die Prognose — dieselbe Kaskade, mit dem Zuwachs je Station
-- ---------------------------------------------------------------------
-- Was aus der liegenden Ware wird, wenn sie liegen bleibt: Verdunstung
-- wie bisher über (1 − r)^h; das Faule über den Zuwachs je Woche der
-- Kennzahl (0105), je Station fortgeschrieben und über den Weg der Charge
-- zusammengesetzt (palox_f_nach). Weist die Kennzahl keinen Zuwachs aus,
-- bleibt der Anteil von heute stehen — zuwachs_bekannt sagt es, und die
-- Zwei-Wochen-Zahl (v_naechste_charge) bleibt dann leer, wie sie es ohne
-- brauchbares Modell auch war.
create or replace view v_prognose with (security_invoker = true) as
with tag as materialized (
  select heute() as heute, stichtag() as stichtag
), ende as (
  select greatest(least(t.stichtag - t.heute, 400), 28) as tage from tag t
), horizonte as (
  select h from ende e, generate_series(0, e.tage, 7) g(h)
  union select 7 union select 14 union select 28
  union select tage from ende
), grenzen as (
  select * from mv_koeff_rand
), lager as materialized (
  select k.charge_nr, k.sorte, k.schlag, k.kohorte, k.alter_tage, k.m0,
         k.r, k.f, k.f_unten, k.f_oben, k.f_ws, k.f_s, k.g_w, k.p_hand, k.p_wasch,
         k.b_ws, k.b_s, k.b_w, k.zuwachs_bekannt,
         k.a_klein_n, k.a_gross_n, k.a_fax,
         k.r_bekannt, k.f_bekannt, k.a_klein_bekannt, k.a_gross_bekannt, k.a_fax_bekannt, k.f_geliehen,
         coalesce(g.r_unten, 0) as r_unten, coalesce(g.r_oben, 0) as r_oben,
         coalesce(g.klein_unten, 0) as klein_unten, coalesce(g.klein_oben, 0) as klein_oben,
         coalesce(g.gross_unten, 0) as gross_unten, coalesce(g.gross_oben, 0) as gross_oben,
         coalesce(g.fax_unten, 0) as fax_unten, coalesce(g.fax_oben, 0) as fax_oben,
         power(1 - k.r, k.alter_tage)                                      as wa,
         power(1 - greatest(coalesce(g.r_unten, 0), 0), k.alter_tage)      as wa_unten,
         power(1 - greatest(coalesce(g.r_oben,  0), 0), k.alter_tage)      as wa_oben
    from mv_kaskade k
    left join grenzen g on g.sorte = k.sorte
   where k.portion = 'lager' and k.m0 > 0 and k.alter_tage >= 0
), faktor_h as materialized (
  select c.charge_nr, h.h,
         power(1 - c.r, h.h)                              as wh,
         power(1 - greatest(c.r_unten, 0), h.h)           as wh_unten,
         power(1 - greatest(c.r_oben,  0), h.h)           as wh_oben
    from (select distinct charge_nr, r, r_unten, r_oben from lager) c
   cross join horizonte h
), je_portion as (
  select l.*, h.h, (l.alter_tage + h.h)::int as t,
         -- der Anteil am Horizont: jede Station um ihren Zuwachs fortgeschrieben
         case when l.zuwachs_bekannt
              then coalesce(palox_f_nach(l.p_hand, l.p_wasch, l.f_ws, l.f_s, l.g_w, l.b_ws, l.b_s, l.b_w, h.h), l.f)
              else l.f end                                                     as f_h,
         w.wh, w.wh_unten, w.wh_oben,
         d.heute + h.h as datum
    from lager l
    cross join horizonte h
    cross join tag d
    join faktor_h w on w.charge_nr = l.charge_nr and w.h = h.h
), mit_band as (
  -- das Band wandert mit dem Anteil mit
  select p.*,
         least(greatest(p.f_unten + (p.f_h - p.f), 0), 1) as f_unten_h,
         least(greatest(p.f_oben  + (p.f_h - p.f), 0), 1) as f_oben_h
    from je_portion p
), stroeme as (
  select p.charge_nr, p.h, p.datum, p.t, p.m0,
         p.m0 - x.m1                                                           as verdunstet_kg,
         x.m1 * p.f_h                                                          as faul_kg,
         y.m2 - z.rest                                                         as kanal_kg,
         z.rest * p.a_fax                                                      as fax_kg,
         z.rest * (1 - p.a_fax)                                                as verkaufsfaehig_kg,
         y.m2                                                                  as gute_ware_kg,
         p.m0 * p.wa_oben * p.wh_oben * (1 - p.f_oben_h)
              * (1 - least(p.klein_oben / greatest(p.klein_oben + p.gross_oben, 1)
                         + p.gross_oben / greatest(p.klein_oben + p.gross_oben, 1), 1))
              * (1 - p.fax_oben)                                               as vf_unten,
         p.m0 * p.wa_unten * p.wh_unten * (1 - p.f_unten_h)
              * (1 - least(p.klein_unten / greatest(p.klein_unten + p.gross_unten, 1)
                         + p.gross_unten / greatest(p.klein_unten + p.gross_unten, 1), 1))
              * (1 - p.fax_unten)                                              as vf_oben,
         b.basis * (1 - p.f) * (1 - p.wh)                                      as verlust_wasser,
         b.basis * p.wh * greatest(p.f_h - p.f, 0)                             as verlust_faeulnis,
         p.m0 * p.t                                                            as m0_mal_t,
         p.r_bekannt, p.f_bekannt, p.a_klein_bekannt, p.a_gross_bekannt, p.a_fax_bekannt,
         p.f_geliehen, p.zuwachs_bekannt
    from mit_band p
    cross join lateral (select p.m0 * p.wa * p.wh as m1) x
    cross join lateral (select x.m1 * (1 - p.f_h) as m2) y
    cross join lateral (select y.m2 * (1 - p.a_klein_n - p.a_gross_n) as rest) z
    cross join lateral (select p.m0 * (1 - p.a_klein_n - p.a_gross_n) * (1 - p.a_fax) * p.wa as basis) b
), gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from v_kaskade_basis
  union all select 'sorte',  sorte,           charge_nr from v_kaskade_basis
  union all select 'schlag', schlag,          charge_nr from v_kaskade_basis
  union all select 'charge', charge_nr::text, charge_nr from v_kaskade_basis
), je_charge as materialized (
  select s.charge_nr, s.h, max(s.datum) as datum,
         count(*)::int                                                         as n_kohorten,
         sum(s.m0)                                                             as lager_kg,
         sum(s.verdunstet_kg)                                                  as verdunstet_kg,
         sum(s.faul_kg)                                                        as faul_kg,
         sum(s.kanal_kg)                                                       as kanal_kg,
         sum(s.fax_kg)                                                         as fax_kg,
         sum(s.verkaufsfaehig_kg)                                              as verkaufsfaehig_kg,
         sum(s.gute_ware_kg)                                                   as gute_ware_kg,
         sum(s.vf_unten)                                                       as vf_unten_kg,
         sum(s.vf_oben)                                                        as vf_oben_kg,
         sum(s.verlust_wasser)                                                 as verlust_wasser_kg,
         sum(s.verlust_faeulnis)                                               as verlust_faeulnis_kg,
         sum(s.m0_mal_t)                                                       as m0_mal_t,
         bool_and(s.r_bekannt)                                                 as r_bekannt,
         bool_and(s.f_bekannt)                                                 as f_bekannt,
         bool_and(s.a_klein_bekannt and s.a_gross_bekannt)                     as kanal_bekannt,
         bool_and(s.a_fax_bekannt)                                             as fax_bekannt,
         bool_or(s.f_geliehen)                                                 as f_geliehen,
         bool_and(s.zuwachs_bekannt)                                           as zuwachs_bekannt,
         min(s.t)                                                              as alter_von,
         max(s.t)                                                              as alter_bis
    from stroeme s
   group by s.charge_nr, s.h
), summe as materialized (
  select g.gruppe, g.schluessel, j.h, max(j.datum) as datum,
         count(*)::int                                                         as n_chargen,
         sum(j.n_kohorten)::int                                                as n_kohorten,
         sum(j.lager_kg)                                                       as lager_kg,
         sum(j.verdunstet_kg)                                                  as verdunstet_kg,
         sum(j.faul_kg)                                                        as faul_kg,
         sum(j.kanal_kg)                                                       as kanal_kg,
         sum(j.fax_kg)                                                         as fax_kg,
         sum(j.verkaufsfaehig_kg)                                              as verkaufsfaehig_kg,
         sum(j.gute_ware_kg)                                                   as gute_ware_kg,
         sum(j.vf_unten_kg)                                                    as vf_unten_kg,
         sum(j.vf_oben_kg)                                                     as vf_oben_kg,
         sum(j.verlust_wasser_kg)                                              as verlust_wasser_kg,
         sum(j.verlust_faeulnis_kg)                                            as verlust_faeulnis_kg,
         bool_and(j.r_bekannt)                                                 as r_bekannt,
         bool_and(j.f_bekannt)                                                 as f_bekannt,
         bool_and(j.kanal_bekannt)                                             as kanal_bekannt,
         bool_and(j.fax_bekannt)                                               as fax_bekannt,
         bool_or(j.f_geliehen)                                                 as f_geliehen,
         bool_and(j.zuwachs_bekannt)                                           as zuwachs_bekannt,
         sum(j.m0_mal_t) / nullif(sum(j.lager_kg), 0)                          as alter_tage,
         min(j.alter_von)                                                      as alter_von,
         max(j.alter_bis)                                                      as alter_bis
    from je_charge j join gruppen g on g.charge_nr = j.charge_nr
   group by g.gruppe, g.schluessel, j.h
), rate as (
  select s0.gruppe, s0.schluessel,
         (s1.verlust_wasser_kg + s1.verlust_faeulnis_kg) / s1.h                          as vf_je_tag_kg,
         s1.verlust_wasser_kg / s1.h                                                     as verdunstet_je_tag_kg,
         -- ohne Zuwachs gibt es keine Rate des Faulen — nicht 0
         case when s1.zuwachs_bekannt then s1.verlust_faeulnis_kg / s1.h end             as faul_je_tag_kg
    from summe s0
    join lateral (select x.* from summe x
                   where x.gruppe = s0.gruppe and x.schluessel = s0.schluessel and x.h > 0
                   order by x.h limit 1) s1 on true
   where s0.h = 0
)
select s.gruppe, s.schluessel, s.h, s.datum, s.n_chargen, s.n_kohorten,
       zahl(s.lager_kg,          2, 1e12)::numeric(14,2)            as lager_kg,
       zahl(s.verdunstet_kg,     2, 1e12)::numeric(14,2)            as verdunstet_kg,
       zahl(s.faul_kg,           2, 1e12)::numeric(14,2)            as faul_kg,
       zahl(s.kanal_kg,          2, 1e12)::numeric(14,2)            as kanal_kg,
       zahl(s.fax_kg,            2, 1e12)::numeric(14,2)            as fax_kg,
       zahl(s.verkaufsfaehig_kg, 2, 1e12)::numeric(14,2)            as verkaufsfaehig_kg,
       zahl(s.gute_ware_kg,      2, 1e12)::numeric(14,2)            as gute_ware_kg,
       zahl(s.verlust_wasser_kg,    2, 1e12)::numeric(14,2)         as verlust_wasser_kg,
       zahl(s.verlust_faeulnis_kg,  2, 1e12)::numeric(14,2)         as verlust_faeulnis_kg,
       zahl(s.verlust_wasser_kg + s.verlust_faeulnis_kg, 2, 1e12)::numeric(14,2)
                                                                    as verlust_verkaufsfaehig_kg,
       (case when v.vollstaendig and s.lager_kg > 0
             then zahl(s.verkaufsfaehig_kg / s.lager_kg, 4, 1) end)::numeric(6,4) as verkaufsfaehig_anteil,
       (case when v.vollstaendig then zahl(s.vf_unten_kg, 2, 1e12) end)::numeric(14,2) as verkaufsfaehig_unten_kg,
       (case when v.vollstaendig then zahl(s.vf_oben_kg,  2, 1e12) end)::numeric(14,2) as verkaufsfaehig_oben_kg,
       zahl(r.vf_je_tag_kg,         1, 1e9)::numeric(12,1)          as verkaufsfaehig_je_tag_kg,
       zahl(r.verdunstet_je_tag_kg, 1, 1e9)::numeric(12,1)          as verdunstet_je_tag_kg,
       zahl(r.faul_je_tag_kg,       1, 1e9)::numeric(12,1)          as faul_je_tag_kg,
       s.r_bekannt, s.f_bekannt, s.kanal_bekannt, s.fax_bekannt,
       v.vollstaendig, s.f_geliehen, s.zuwachs_bekannt,
       round(s.alter_tage)::int as alter_tage, s.alter_von, s.alter_bis
  from summe s
  cross join lateral (select (s.r_bekannt and s.f_bekannt
                              and s.kanal_bekannt and s.fax_bekannt) as vollstaendig) v
  left join rate r on r.gruppe = s.gruppe and r.schluessel = s.schluessel;
comment on view v_prognose is
  'Was aus der heute liegenden Ware wird, wenn sie liegen bleibt — je Gruppe (gesamt, Sorte, Schlag, Charge) und je '
  'Horizont h Tage, von heute bis zum Saisonende in Wochenschritten (7/14/28 immer dabei). Es ist die Kaskade '
  '(mv_kaskade, Portion „lager") bei alter_tage + h, mit denselben Formeln: bei h = 0 stehen deshalb genau die Zahlen '
  'von erg_charge. Seit 0106 wächst das Faule mit dem Zuwachs je Station der Kennzahl (0105) — nur wenn zuwachs_bekannt; '
  'sonst bleibt der Anteil von heute stehen und faul_je_tag_kg ist leer. f_geliehen: ein Anteil aus allen Sorten. '
  'Der Nenner ist lager_kg, die Eingangsware, die noch nicht hinter einer Lieferung steckt; vollstaendig heisst: '
  'Verdunstung, Faules, Ausschuss und Fax gemessen.';
grant select on v_prognose to authenticated;

create materialized view erg_prognose as select * from v_prognose with no data;
create unique index if not exists erg_prognose_pk on erg_prognose (gruppe, schluessel, h);
create index if not exists erg_prognose_gruppe on erg_prognose (gruppe, h);
comment on materialized view erg_prognose is
  'v_prognose, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';
grant select on erg_prognose to authenticated;

-- „Zwei Wochen länger liegen" — dieselbe Formel wie überall (0071). Ohne
-- bestimmbaren Zuwachs bleibt die Zwei-Wochen-Zahl des Faulen leer, wie
-- sie es ohne brauchbares Modell war: leer ist nicht null.
create or replace view v_naechste_charge with (security_invoker = true) as
select p0.schluessel::int                                        as charge_nr,
       b.sorte, b.schlag,
       p0.lager_kg,
       p0.alter_tage,
       p0.gute_ware_kg                                           as masse_jetzt_kg,
       zahl(p14.verlust_wasser_kg, 1, 1e11)::numeric(12,1)                       as verdunstung_14_kg,
       (case when p0.zuwachs_bekannt
             then zahl(p14.verlust_faeulnis_kg, 1, 1e11) end)::numeric(12,1)     as schimmel_14_kg,
       (case when p0.zuwachs_bekannt
             then zahl(p14.verlust_verkaufsfaehig_kg, 1, 1e11) end)::numeric(12,1)
                                                                 as prognose_verlust_14_kg,
       p0.f_geliehen, p0.zuwachs_bekannt,
       p0.alter_von, p0.alter_bis, p0.n_kohorten
  from erg_prognose p0
  join erg_prognose p14 on p14.gruppe = 'charge' and p14.schluessel = p0.schluessel and p14.h = 14
  join v_kaskade_basis b on b.charge_nr = p0.schluessel::int
 where p0.gruppe = 'charge' and p0.h = 0 and p0.lager_kg > 0
 order by (case when p0.zuwachs_bekannt
                then zahl(p14.verlust_verkaufsfaehig_kg, 1, 1e11) end)::numeric(12,1)
          desc nulls last;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Gerechnet aus v_prognose (Horizont 14 gegen '
  'Horizont 0) — dieselbe Formel wie die Kaskade, damit es im ganzen Programm nur eine Zwei-Wochen-Zahl gibt. '
  'prognose_verlust_14_kg ist, was an **verkaufsfähiger** Ware verloren geht, und verdunstung_14_kg + schimmel_14_kg '
  'ergeben es auf den Rappen. Seit 0106 leer, solange die Kennzahl je Station keinen Zuwachs ausweist '
  '(zuwachs_bekannt = false).';
grant select on v_naechste_charge to authenticated;

-- ---------------------------------------------------------------------
-- 8. Der Verlauf je Woche — das Faule mit dem Zuwachs zurück und voraus
-- ---------------------------------------------------------------------
-- Der Anteil einer Portion an einem Wochenende ist ihr Anteil (heute bzw.
-- am Liefertag) um den Zuwachs je Station verschoben: zurück in die
-- Vergangenheit, voraus in die Prognose. Ohne Zuwachs steht er still.
create materialized view erg_verlauf as
with tag as materialized (
  select heute() as heute, stichtag() as stichtag
), wochen as materialized (
  select w::date as woche, (w + interval '6 days')::date as bis
    from tag t, generate_series(
      date_trunc('week', coalesce((select min(eingangsdatum) from palette), t.heute))::date,
      date_trunc('week', greatest(t.stichtag, t.heute + 84))::date, interval '7 days') w
  union
  select date_trunc('week', t.heute)::date, t.heute from tag t
), gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from v_kaskade_basis
  union all select 'sorte',  sorte,           charge_nr from v_kaskade_basis
  union all select 'schlag', schlag,          charge_nr from v_kaskade_basis
  union all select 'charge', charge_nr::text, charge_nr from v_kaskade_basis
), portionen as materialized (
  select k.charge_nr, k.portion, k.kohorte, k.m0, k.r,
         k.f, k.f_ws, k.f_s, k.g_w, k.p_hand, k.p_wasch, k.b_ws, k.b_s, k.b_w, k.zuwachs_bekannt,
         k.a_klein_n, k.a_gross_n, k.a_fax,
         case when k.portion = 'ausgelagert' then k.kohorte + round(k.alter_tage)::int end as liefertag,
         case when k.portion = 'ausgelagert' then k.fax_kg else 0 end                      as fax_kg
    from mv_kaskade k
   where k.m0 > 0 and k.kohorte is not null
), je_woche as (
  select w.woche, w.bis, p.charge_nr,
         p.m0 * (1 - power(1 - p.r, x.t))                                     as verdunstung_kg,
         p.m0 * power(1 - p.r, x.t) * f.f                                     as schimmel_kg,
         case when p.liefertag is not null and p.liefertag <= w.bis then p.fax_kg else 0 end as fax_kg,
         case when p.liefertag is null or p.liefertag > w.bis then p.m0 else 0 end as lager_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - f.f) else 0 end                   as gute_ware_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - f.f)
                   * (p.a_klein_n + p.a_gross_n) else 0 end                            as kanal_lager_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - f.f)
                   * (1 - p.a_klein_n - p.a_gross_n) * p.a_fax else 0 end              as fax_lager_kg,
         case when p.liefertag is not null and p.liefertag <= w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - f.f)
                   * (p.a_klein_n + p.a_gross_n) else 0 end                            as aussortiert_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - f.f)
                   * (1 - p.a_klein_n - p.a_gross_n) * (1 - p.a_fax) else 0 end        as verkaufsfaehig_kg
    from wochen w
    join portionen p on p.kohorte <= w.bis
    cross join tag d
    cross join lateral (
      -- t: Tage seit dem Eingang bis zum Wochenende, höchstens bis zum Liefertag
      select greatest(least(w.bis, coalesce(p.liefertag, w.bis)) - p.kohorte, 0) as t
    ) x
    cross join lateral (
      -- der Anteil an diesem Wochenende: vom Anker (Liefertag bzw. heute)
      -- um d Tage verschoben, wenn der Zuwachs bekannt ist
      select case when p.zuwachs_bekannt
                  then coalesce(palox_f_nach(p.p_hand, p.p_wasch, p.f_ws, p.f_s, p.g_w, p.b_ws, p.b_s, p.b_w,
                                             (least(w.bis, coalesce(p.liefertag, w.bis)) - coalesce(p.liefertag, d.heute))::numeric), p.f)
                  else p.f end as f
    ) f
), je_charge as materialized (
  select woche, bis, charge_nr,
         sum(verdunstung_kg) as verdunstung_kg,
         sum(schimmel_kg) as schimmel_kg, sum(fax_kg) as fax_kg,
         sum(gute_ware_kg) as im_haus_kg, sum(lager_kg) as lager_kg,
         sum(kanal_lager_kg) as kanal_kg, sum(fax_lager_kg) as fax_lager_kg,
         sum(verkaufsfaehig_kg) as verkaufsfaehig_kg,
         sum(aussortiert_kg) as aussortiert_kg
    from je_woche
   group by woche, bis, charge_nr
), verlust as (
  select j.woche, j.bis, g.gruppe, g.schluessel,
         sum(j.verdunstung_kg) as verdunstung_kg,
         sum(j.schimmel_kg) as schimmel_kg, sum(j.fax_kg) as fax_kg,
         sum(j.im_haus_kg) as im_haus_kg, sum(j.lager_kg) as lager_kg,
         sum(j.kanal_kg) as kanal_kg, sum(j.fax_lager_kg) as fax_lager_kg,
         sum(j.verkaufsfaehig_kg) as verkaufsfaehig_kg,
         sum(j.aussortiert_kg) as aussortiert_kg
    from je_charge j join gruppen g on g.charge_nr = j.charge_nr
   group by j.woche, j.bis, g.gruppe, g.schluessel
), eingang_charge as materialized (
  -- v_charge_kohorte, nicht v_palette: die Paletten ohne Netto sind mit
  -- dem Mittel hochgerechnet, wie in Kaskade und Bilanz (0064, K10).
  select w.woche, w.bis, k.charge_nr, sum(k.eingang_kg) as kg
    from wochen w join v_charge_kohorte k on k.eingangsdatum <= w.bis
   group by w.woche, w.bis, k.charge_nr
), eingang as (
  select e.woche, e.bis, g.gruppe, g.schluessel, sum(e.kg) as kg
    from eingang_charge e join gruppen g on g.charge_nr = e.charge_nr
   group by e.woche, e.bis, g.gruppe, g.schluessel
), ausgang_charge as materialized (
  select w.woche, w.bis, l.charge_nr, sum(l.masse_kg) as kg
    from wochen w join v_lieferung_charge_tag l on l.datum <= w.bis
   group by w.woche, w.bis, l.charge_nr
), ausgang as (
  select a.woche, a.bis, g.gruppe, g.schluessel, sum(a.kg) as kg
    from ausgang_charge a join gruppen g on g.charge_nr = a.charge_nr
   group by a.woche, a.bis, g.gruppe, g.schluessel
), liste as (
  select distinct gruppe, schluessel from gruppen
)
select w.woche, w.bis, (w.bis > d.heute)                                      as prognose,
       s.gruppe, s.schluessel,
       zahl(coalesce(e.kg, 0), 2, 1e12)::numeric(14,2)                         as eingang_kum_kg,
       zahl(coalesce(a.kg, 0), 2, 1e12)::numeric(14,2)                         as ausgang_kum_kg,
       zahl(coalesce(v.verdunstung_kg, 0), 2, 1e12)::numeric(14,2)             as verdunstung_kum_kg,
       zahl(coalesce(v.schimmel_kg, 0), 2, 1e12)::numeric(14,2)                as schimmel_kum_kg,
       zahl(coalesce(v.fax_kg, 0), 2, 1e12)::numeric(14,2)                     as fax_kum_kg,
       zahl(coalesce(v.verdunstung_kg, 0) + coalesce(v.schimmel_kg, 0)
            + coalesce(v.fax_kg, 0), 2, 1e12)::numeric(14,2)                   as verlust_kum_kg,
       -- 0101: im Haus = Liegendes nach Verdunstung und Verderb + hinter den
       -- Lieferungen Aussortiertes; auf heute dieselbe Zahl wie erg_bilanz.
       zahl(coalesce(v.im_haus_kg, 0) + coalesce(v.aussortiert_kg, 0), 2, 1e12)::numeric(14,2)
                                                                              as im_haus_kg,
       zahl(coalesce(v.lager_kg, 0), 2, 1e12)::numeric(14,2)                   as lager_kg,
       zahl(coalesce(v.verkaufsfaehig_kg, 0), 2, 1e12)::numeric(14,2)          as verkaufsfaehig_kg,
       zahl(coalesce(v.kanal_kg, 0), 2, 1e12)::numeric(14,2)                   as kanal_kg,
       zahl(coalesce(v.fax_lager_kg, 0), 2, 1e12)::numeric(14,2)               as fax_lager_kg,
       zahl(coalesce(v.aussortiert_kg, 0), 2, 1e12)::numeric(14,2)              as aussortiert_kg
  from wochen w
  cross join liste s
  cross join tag d
  left join verlust v on v.bis = w.bis and v.gruppe = s.gruppe and v.schluessel = s.schluessel
  left join eingang e on e.bis = w.bis and e.gruppe = s.gruppe and e.schluessel = s.schluessel
  left join ausgang a on a.bis = w.bis and a.gruppe = s.gruppe and a.schluessel = s.schluessel
 with no data;
create unique index if not exists erg_verlauf_pk on erg_verlauf (woche, bis, gruppe, schluessel);
create index if not exists erg_verlauf_gruppe on erg_verlauf (gruppe, schluessel, bis);
create index if not exists erg_verlauf_woche on erg_verlauf (woche);
comment on materialized view erg_verlauf is
  'Je Woche und Gruppe (gesamt, Sorte, Schlag, Charge): Eingang und Ausgang kumuliert (gemessen), im Lager '
  '(Eingangsware, die noch nicht hinter einer Lieferung steckt) und davon verkaufsfähig (gerechnet) — ab heute als '
  'Prognose bis zum Saisonende (prognose = true). Der Verlust ist der Abstand zwischen im Lager und verkaufsfähig; '
  'seine Teile stehen weiter als eigene Spalten (0071). Seit 0106 ohne Sockel: das Faule ist der Palox-Anteil der '
  'Stationen, mit dem Zuwachs je Woche zurück und voraus verschoben, wo die Kennzahl ihn ausweist.';
grant select on erg_verlauf to authenticated;

-- ---------------------------------------------------------------------
-- 9. Wohin ging der Kürbis — ohne den Sockel
-- ---------------------------------------------------------------------
create or replace view v_wohin with (security_invoker = true) as
with gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from erg_charge
  union all select 'sorte',  sorte,           charge_nr from erg_charge
  union all select 'schlag', schlag,          charge_nr from erg_charge
  union all select 'charge', charge_nr::text, charge_nr from erg_charge
), charge as (
  select g.gruppe, g.schluessel,
         count(*)::int                          as n_chargen,
         sum(c.eingang_kg)                      as eingang_kg,
         sum(c.ueberzaehlung_kg)                as ueberzaehlung_kg,
         sum(c.geliefert_kg)                    as geliefert_kg,
         sum(c.kanal_ausgelagert_kg)            as kanal_ausgelagert_kg,
         sum(c.fax_heute_kg)                    as fax_kg,
         sum(c.im_haus_heute_kg)                as lager_gute_ware_kg,
         sum(c.verkaufsfaehig_lager_kg)         as lager_verkaufsfaehig_kg,
         sum(c.kanal_im_haus_kg)                as lager_kanal_kg,
         sum(c.fax_erwartet_kg)                 as lager_fax_kg,
         sum(c.lager_kg)                        as lager_kg,
         bool_and(c.verlust_bekannt)            as vollstaendig
    from gruppen g join erg_charge c on c.charge_nr = g.charge_nr
   group by g.gruppe, g.schluessel
), stroeme as (
  select gruppe, schluessel,
         sum(kg_beobachtet) filter (where strom = 'Verdunstung')           as verdunstet_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Verdunstung')           as lager_verdunstet_kg,
         sum(kg_beobachtet) filter (where strom = 'Schimmel/Fäulnis')      as faul_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Schimmel/Fäulnis')      as lager_faul_kg,
         sum(kg_beobachtet) filter (where strom = 'Zu klein (Tierfutter)') as klein_ausgelagert_kg,
         sum(kg_beobachtet) filter (where strom = 'Nebenkanal zu gross')   as gross_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Zu klein (Tierfutter)') as lager_klein_kg,
         sum(kg_projiziert) filter (where strom = 'Nebenkanal zu gross')   as lager_gross_kg
    from erg_verlust
   group by gruppe, schluessel
)
select c.gruppe, c.schluessel, c.n_chargen,
       zahl(c.eingang_kg)::numeric(14,2)                            as eingang_kg,
       zahl(c.ueberzaehlung_kg)::numeric(14,2)                      as ueberzaehlung_kg,
       zahl(c.geliefert_kg)::numeric(14,2)                          as geliefert_kg,
       zahl(c.kanal_ausgelagert_kg)::numeric(14,2)                  as kanal_ausgelagert_kg,
       zahl(s.klein_ausgelagert_kg)::numeric(14,2)                  as klein_ausgelagert_kg,
       zahl(s.gross_ausgelagert_kg)::numeric(14,2)                  as gross_ausgelagert_kg,
       zahl(s.verdunstet_ausgelagert_kg)::numeric(14,2)             as verdunstet_ausgelagert_kg,
       zahl(s.faul_ausgelagert_kg)::numeric(14,2)                   as faul_ausgelagert_kg,
       zahl(c.fax_kg)::numeric(14,2)                                as fax_kg,
       zahl(c.lager_kg)::numeric(14,2)                              as lager_kg,
       zahl(c.lager_gute_ware_kg)::numeric(14,2)                    as lager_gute_ware_kg,
       zahl(c.lager_verkaufsfaehig_kg)::numeric(14,2)               as lager_verkaufsfaehig_kg,
       zahl(c.lager_kanal_kg)::numeric(14,2)                        as lager_kanal_kg,
       zahl(s.lager_klein_kg)::numeric(14,2)                        as lager_klein_kg,
       zahl(s.lager_gross_kg)::numeric(14,2)                        as lager_gross_kg,
       zahl(c.lager_fax_kg)::numeric(14,2)                          as lager_fax_kg,
       zahl(s.lager_faul_kg)::numeric(14,2)                         as lager_faul_kg,
       zahl(s.lager_verdunstet_kg)::numeric(14,2)                   as lager_verdunstet_kg,
       zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.kanal_ausgelagert_kg
            - s.verdunstet_ausgelagert_kg - s.faul_ausgelagert_kg
            - c.fax_kg - c.lager_kg)::numeric(14,2)                 as rest_kg,
       zahl(c.lager_kg - c.lager_verkaufsfaehig_kg - c.lager_kanal_kg - c.lager_fax_kg
            - s.lager_faul_kg - s.lager_verdunstet_kg)::numeric(14,2) as lager_rest_kg,
       c.vollstaendig
  from charge c
  left join stroeme s on s.gruppe = c.gruppe and s.schluessel = c.schluessel;
comment on view v_wohin is
  'Wohin ging der Kürbis — je Gruppe (gesamt, Sorte, Schlag, Charge) der ganze Eingang aufgeteilt: ausgeliefert, '
  'anderer Kanal, verdunstet und faul an der ausgelieferten Ware, Faules beim Abpacken, und was noch liegt (davon '
  'verkaufsfähig, Kanal, Fax erwartet, faul, verdunstet). rest_kg und lager_rest_kg sind die zwei Identitäten: beide '
  'haben den Erwartungswert null, und eine doppelt gezählte Portion bliebe darin stehen. Seit 0106 ohne Sockel.';
grant select on v_wohin to authenticated;

create materialized view erg_wohin as select * from v_wohin with no data;
create unique index if not exists erg_wohin_pk on erg_wohin (gruppe, schluessel);
comment on materialized view erg_wohin is
  'v_wohin, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';
grant select on erg_wohin to authenticated;


-- ---------------------------------------------------------------------
-- 10. Die Auffälligkeiten — unverändert, nur neu gebaut (sie lesen erg_charge)
-- ---------------------------------------------------------------------

create or replace view v_plausibilitaet_0064_zusatz with (security_invoker = true) as
 SELECT 'Tara fehlt'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    (min(p.eingangsdatum))::timestamp with time zone AS start_ts,
    format('%s von %s Paletten der Charge haben kein Nettogewicht (%s kg brutto): %s. %s'::text, count(*), r.n_paletten, round(sum(p.brutto_kg)),
        CASE
            WHEN bool_or((p.gebindeart IS NULL)) THEN 'die Gebindeart steht nicht auf der Palette'::text
            WHEN bool_or((g.art IS NULL)) THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN bool_or((g.tara_kg_pro_kiste IS NULL)) THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN bool_or((g.tara_kg_palette IS NULL)) THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END,
        CASE
            WHEN (r.n_paletten_mit_netto = 0) THEN 'Damit hat die Charge gar keinen Eingang — sie fehlt in der ganzen Bilanz.'::text
            ELSE format(('Für sie rechnet der Eingang mit dem Mittel der übrigen: %s der %s kg '::text || 'Eingang sind hochgerechnet, nicht gewogen.'::text), round((r.eingang_netto_kg - r.eingang_netto_gemessen_kg)), round(r.eingang_netto_kg))
        END) AS befund,
        CASE
            WHEN bool_or((p.gebindeart IS NULL)) THEN 'Gebindeart am Wareneingang nachtragen.'::text
            WHEN (bool_or((g.art IS NULL)) OR bool_or((g.tara_kg_pro_kiste IS NULL)) OR bool_or((g.tara_kg_palette IS NULL))) THEN ('Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. '::text || 'Die Zahlen rechnen sich danach von selbst neu.'::text)
            ELSE 'Kistenzahl der Palette im Wareneingang nachtragen.'::text
        END AS rat
   FROM (((palette p
     LEFT JOIN gebinde g ON ((g.art = p.gebindeart)))
     JOIN charge c ON ((c.nr = p.charge_nr)))
     JOIN v_charge_rueckgrat r ON ((r.charge_nr = p.charge_nr)))
  WHERE (((p.brutto_kg - ((p.kisten)::numeric * g.tara_kg_pro_kiste)) - g.tara_kg_palette) IS NULL)
  GROUP BY p.charge_nr, c.sorte, r.n_paletten, r.n_paletten_mit_netto, r.eingang_netto_kg, r.eingang_netto_gemessen_kg
UNION ALL
 SELECT 'Überzählung'::text AS art,
    NULL::bigint AS auftrag_id,
    h.charge_nr,
    h.sorte,
    (h.eingangsdatum_mittel)::timestamp with time zone AS start_ts,
    format('Die Lieferungen dieser Charge (%s kg) brauchen nach der gerechneten Ausbeute (%s %% verkaufsfähig) %s kg Eingang — erfasst sind %s kg, also %s kg zu wenig. Geliefert wurde nicht mehr als eingelagert; es wurde mehr geliefert, als die Rechnung aus diesem Eingang erwartet.'::text,
           round(h.geliefert_kg),
           round((100)::numeric * h.geliefert_kg / NULLIF(h.eingang_kg + h.ueberzaehlung_kg, (0)::numeric)),
           round(h.eingang_kg + h.ueberzaehlung_kg), round(h.eingang_kg), round(h.ueberzaehlung_kg)) AS befund,
    'Drei Möglichkeiten: Im Erntejournal fehlt eine Palette dieser Charge; ein Lieferschein ist auf die falsche Chargennummer gebucht; oder diese Charge hat weniger Verlust als das Modell annimmt — dann ist „Im Lager" für sie zu klein gerechnet. Die ersten zwei lassen sich nachtragen.'::text AS rat
   FROM v_hochrechnung_basis h
  WHERE (h.ueberzaehlung_kg > (0)::numeric)
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format((('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette '::text || 'dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — gerechnet '::text) || 'wird deshalb mit der mittleren Tara der Charge, nicht mit ihrer eigenen.'::text), count(*), ap.brutto_zettel_kg, to_char((ap.eingangsdatum)::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'::text AS rat
   FROM ((auftrag_palette ap
     JOIN auftrag a ON ((a.id = ap.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((ap.brutto_zettel_kg IS NOT NULL) AND (ap.eingangsdatum IS NOT NULL) AND (a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
           FROM palette p
          WHERE ((p.charge_nr = a.charge_nr) AND (p.brutto_kg = ap.brutto_zettel_kg)))) AND (NOT (EXISTS ( SELECT 1
           FROM v_palette p
          WHERE ((p.charge_nr = a.charge_nr) AND (p.brutto_kg = ap.brutto_zettel_kg) AND (p.eingangsdatum = ap.eingangsdatum) AND (p.netto_kg IS NOT NULL))))))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg, ap.eingangsdatum
UNION ALL
 SELECT 'Palette fraglich'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s: %s kg brutto in %s Kiste(n) %s, mit Palette gewogen — davon bleiben %s kg netto. Eine leere Palette wiegt allein %s kg.'::text,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'Zu klein'::text
            ELSE 'Zu gross'::text
        END, m.brutto_kg, m.kisten, m.gebindeart, m.kg, g.tara_kg_palette) AS befund,
    'Standen die Kisten direkt auf der Waage? Dann in der Korrektur „mit Palette" abwählen — das Netto rechnet sich von selbst neu.'::text AS rat
   FROM (((ausschuss_messung m
     JOIN auftrag a ON ((a.id = m.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
     JOIN gebinde g ON ((g.art = m.gebindeart)))
  WHERE (m.gemessen AND m.mit_palette AND (m.brutto_kg IS NOT NULL) AND (g.tara_kg_palette IS NOT NULL) AND (m.brutto_kg < ((2)::numeric * g.tara_kg_palette)) AND (a.abgebrochen_ts IS NULL))
UNION ALL
 SELECT 'Verdunstung'::text AS art,
    m.auftrag_id,
    m.charge_nr,
    m.sorte,
    m.wiege_ts AS start_ts,
    format('%s %% je Tag: %s kg → %s kg in %s Tagen — so schnell verdunstet kein Kürbis (Grenze %s %% je Tag)'::text, round((m.rate_pro_tag * (100)::numeric), 2), round(m.netto_damals_kg), round(m.netto_jetzt_kg), m.lagertage, round((verdunstung_rate_max() * (100)::numeric), 2)) AS befund,
    'Zettelgewicht, Kisten und Gebinde dieser Wägung prüfen — oder es ist eine andere Palette. Bis zur Korrektur zählt sie nicht in die Rate.'::text AS rat
   FROM v_verdunstung_messung m
  WHERE (m.grund ~~ 'zu schnell%'::text);
comment on view v_plausibilitaet_0064_zusatz is
  'Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die Paletten fehlen im Eingang), eine '
  'Charge mit mehr Ausgang als Eingang, und ein Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag.';
grant select on v_plausibilitaet_0064_zusatz to authenticated;


create or replace view v_plausibilitaet_0054_zusatz with (security_invoker = true) as
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber für ein Band mit diesen Grenzen hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, a.kaliber_von_g, a.kaliber_bis_g) AS befund,
    'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) oder die fertigen Paletten wiegen (drei reichen).'::text AS rat
   FROM ((v_auftrag_gebinde_masse g
     JOIN auftrag a ON ((a.id = g.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((g.kg IS NULL) AND (g.anzahl > 0) AND (g.kaliber_idx = '-2'::integer)
     AND NOT EXISTS (SELECT 1 FROM v_auftrag_wasch_gewogen wg WHERE wg.auftrag_id = g.auftrag_id AND wg.quelle = 'gewogen_strasse'))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    wp.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format(('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '::text || 'die Menge dieser Arbeit damit auch'::text), wp.n_paletten, wp.kisten,
        CASE
            WHEN (a.kaliber_von_g IS NOT NULL) THEN format('für das Band %s–%s g hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen'::text, a.kaliber_von_g, a.kaliber_bis_g)
            ELSE 'für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen'::text
        END) AS befund,
        CASE
            WHEN (a.kaliber_von_g IS NOT NULL) THEN 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen.'::text
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — dann kennt die App das Kistengewicht des Bandes, rückwirkend auch für diese Arbeit; oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat
   FROM ((v_auftrag_wasch_paletten wp
     JOIN auftrag a ON ((a.id = wp.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  -- 0104: sind die Paletten dieser Arbeit am Anfang der Strasse gewogen, ist ihre Masse bekannt — kein Befund.
  WHERE ((wp.kg IS NULL) AND (wp.kisten > 0)
     AND NOT EXISTS (SELECT 1 FROM v_auftrag_wasch_gewogen wg WHERE wg.auftrag_id = wp.auftrag_id AND wg.quelle = 'gewogen_strasse'))
UNION ALL
 SELECT 'Lieferung in der Zukunft'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    (l.datum)::timestamp with time zone AS start_ts,
    format(('Lieferschein über %s kg mit Datum %s — das liegt nach heute (%s). '::text || 'Die Menge zählt erst ab diesem Tag in Ausgang und Bestand.'::text), round(l.masse_kg), to_char((l.datum)::timestamp with time zone, 'DD.MM.YYYY'::text), to_char((heute())::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    ('Stimmt das Datum? Ein vordatierter Lieferschein ist in Ordnung — die Zahl '::text || 'erscheint von selbst, sobald der Tag da ist. Ein Zahlendreher gehört korrigiert.'::text) AS rat
   FROM v_lieferung_masse l
  WHERE ((l.datum > heute()) AND (l.masse_kg IS NOT NULL) AND (l.masse_kg > (0)::numeric))
UNION ALL
 SELECT v_plausibilitaet_0064_zusatz.art,
    v_plausibilitaet_0064_zusatz.auftrag_id,
    v_plausibilitaet_0064_zusatz.charge_nr,
    v_plausibilitaet_0064_zusatz.sorte,
    v_plausibilitaet_0064_zusatz.start_ts,
    v_plausibilitaet_0064_zusatz.befund,
    v_plausibilitaet_0064_zusatz.rat
   FROM v_plausibilitaet_0064_zusatz;
comment on view v_plausibilitaet_0054_zusatz is
  'Zusatzprüfungen zu v_plausibilitaet, die seit 0054 dazugekommen sind — je Auffälligkeit Art, betroffene Arbeit, '
  'Befund und Rat. Wird von v_plausibilitaet mitgelesen; einzeln braucht sie niemand.';
grant select on v_plausibilitaet_0054_zusatz to authenticated;


create or replace view v_plausibilitaet with (security_invoker = true) as
 SELECT 'Schimmel'::text AS art,
    b.auftrag_id,
    b.charge_nr,
    b.sorte,
    b.start_ts,
    format('%s kg Schimmel auf %s kg Ware — das wären %s %%'::text, round(b.schimmel_kg), round(b.basis_jetzt_kg), round((b.anteil * (100)::numeric))) AS befund,
    'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text AS rat
   FROM v_schimmel_beobachtung b
  WHERE ((b.anteil IS NOT NULL) AND (NOT b.plausibel) AND (NOT b.ist_fax) AND (b.lagertage >= (0)::numeric))
UNION ALL
 SELECT 'Fax'::text AS art,
    f.auftrag_id,
    f.charge_nr,
    f.sorte,
    f.start_ts,
    format('%s kg Faules bei %s (%s kg) — das wären %s %%'::text, round(f.faul_kg),
        CASE
            WHEN (f.paletten_gesamt > 0) THEN (f.paletten_gesamt || ' Paletten'::text)
            ELSE (f.kisten || ' Kisten'::text)
        END, round(f.masse_kg), round((f.anteil * (100)::numeric))) AS befund,
    'Entweder die Palettenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'::text AS rat
   FROM v_fax_beobachtung f
  WHERE ((f.anteil IS NOT NULL) AND (NOT f.plausibel))
UNION ALL
 SELECT 'Ausschuss'::text AS art,
    a.auftrag_id,
    a.charge_nr,
    a.sorte,
    NULL::timestamp with time zone AS start_ts,
    format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse'::text, round(COALESCE(a.klein_kg, (0)::numeric)), round(COALESCE(a.gross_kg, (0)::numeric)), round(a.basis_kg)) AS befund,
    'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'::text AS rat
   FROM v_ausschuss_beobachtung a
  WHERE ((a.weg = 'hand'::verarbeitungsweg) AND (NOT a.plausibel))
UNION ALL
 SELECT 'Ohne Nenner'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein'::text, concat_ws(' und '::text,
        CASE
            WHEN (COALESCE(s.kg, (0)::numeric) > (0)::numeric) THEN (round(s.kg) || ' kg Faules'::text)
            ELSE NULL::text
        END,
        CASE
            WHEN (COALESCE(x.kg, (0)::numeric) > (0)::numeric) THEN (round(x.kg) || ' kg zu klein/gross'::text)
            ELSE NULL::text
        END),
        CASE
            WHEN a.ist_fax THEN 'keine Palette gezählt oder noch keine fertige Palette dieser Sorte gewogen'::text
            WHEN (a.station = 'waschen'::station) THEN 'keine Kiste gezählt und keine Menge eingetragen'::text
            WHEN (a.station = 'waschen_sortieren'::station) THEN 'keine Palette mit Gewicht vom Zettel gezählt'::text
            ELSE 'keine Palette gezählt'::text
        END) AS befund,
        CASE
            WHEN a.ist_fax THEN (('Die Palettenzahl am Ende der Fax-Arbeit eintragen. Fehlt die Palettenmasse, '::text || 'beim Waschen oder Waschen + Sortieren eine fertige Palette wiegen — sie '::text) || 'gilt dann für alle Fax-Arbeiten der Sorte.'::text)
            WHEN (a.station = 'waschen'::station) THEN ('Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich '::text || 'selbst) oder die verarbeitete Menge in kg nachtragen.'::text)
            WHEN (a.station = 'waschen_sortieren'::station) THEN 'Die Paletten mit Datum und Gewicht vom Zettel am Auftrag nachtragen.'::text
            ELSE 'Die gezählten Paletten am Auftrag nachtragen.'::text
        END AS rat
   FROM ((((auftrag a
     JOIN charge c ON ((c.nr = a.charge_nr)))
     LEFT JOIN v_schimmel_menge s ON ((s.auftrag_id = a.id)))
     LEFT JOIN ( SELECT ausschuss_messung.auftrag_id,
            (sum(ausschuss_messung.kg))::numeric AS kg
           FROM ausschuss_messung
          WHERE ausschuss_messung.gemessen
          GROUP BY ausschuss_messung.auftrag_id) x ON ((x.auftrag_id = a.id)))
     LEFT JOIN v_auftrag_masse m ON ((m.auftrag_id = a.id)))
  WHERE ((a.abgebrochen_ts IS NULL) AND ((COALESCE(s.kg, (0)::numeric) > (0)::numeric) OR (COALESCE(x.kg, (0)::numeric) > (0)::numeric)) AND (COALESCE(m.eingang_netto_kg, (0)::numeric) <= (0)::numeric))
UNION ALL
 SELECT 'Palox'::text AS art,
    s.auftrag_id,
    a.charge_nr,
    c.sorte,
    s.ts AS start_ts,
    format('Waagenstand %s kg liegt unter dem Leergewicht des Palox (%s kg)'::text, s.palox_stand_kg, palox_tara_kg()) AS befund,
    ('Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '::text || 'Sonst ist der Stand vertippt.'::text) AS rat
   FROM ((schimmel_messung s
     JOIN auftrag a ON ((a.id = s.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE (s.gemessen AND (a.abgebrochen_ts IS NULL) AND (s.palox_stand_kg IS NOT NULL) AND (s.palox_stand_kg < palox_tara_kg()))
UNION ALL
 SELECT 'Palox geleert'::text AS art,
    p.auftrag_id,
    a.charge_nr,
    c.sorte,
    p.ts AS start_ts,
    format(('Der Waagenstand fiel von %s auf %s kg — der Palox wurde zwischendurch geleert. '::text || 'Wie viel davor noch dazukam, weiss niemand; das Faule dieser Arbeit ist unbekannt.'::text), p.vorher, p.palox_stand_kg) AS befund,
    'Nichts zu korrigieren. Beim nächsten Mal in der Checkliste „Palox leeren" drücken: vor dem Leeren ablesen, danach die leere Box — dann bleibt die Menge bekannt.'::text AS rat
   FROM ((v_palox_stand p
     JOIN auftrag a ON ((a.id = p.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((p.differenz IS NULL) AND (a.abgebrochen_ts IS NULL))
UNION ALL
 SELECT 'Wägung'::text AS art,
    w.auftrag_id,
    w.charge_nr,
    w.sorte,
    w.wiege_ts AS start_ts,
    (('Palette gewogen, aber '::text ||
        CASE
            WHEN ((w.netto_damals_kg IS NULL) OR (w.netto_jetzt_kg IS NULL)) THEN 'für die Gebindeart fehlt die Tara'::text
            WHEN (w.lagertage <= 0) THEN 'das Wiegedatum liegt nicht nach dem Eingangsdatum'::text
            WHEN ((w.netto_damals_kg <= (0)::numeric) OR (w.netto_jetzt_kg <= (0)::numeric)) THEN 'das Netto ist null oder negativ'::text
            WHEN (w.netto_jetzt_kg > (w.netto_damals_kg * 1.01)) THEN format('sie wiegt jetzt %s kg mehr als beim Eingang, und im Lager wird keine Palette schwerer'::text, round((w.netto_jetzt_kg - w.netto_damals_kg)))
            WHEN (w.netto_jetzt_kg = w.netto_damals_kg) THEN 'sie hat kein Gramm verloren — sehr wahrscheinlich wurde das Eingangsgewicht kopiert (etwa bei einer sortierten Palette, deren Zettelgewicht es nicht gibt)'::text
            ELSE 'sie ist nicht verwertbar'::text
        END) || ' — sie zählt nicht in die Verdunstungsrate'::text) AS befund,
        CASE
            WHEN ((w.netto_damals_kg IS NULL) OR (w.netto_jetzt_kg IS NULL)) THEN 'Unter Stammdaten → Gebinde die Tara nachtragen.'::text
            WHEN (w.netto_jetzt_kg > (w.netto_damals_kg * 1.01)) THEN 'Gebindeart, Kistenzahl und beide Gewichte prüfen — meist stimmt die Tara nicht oder eine Zahl ist verdreht.'::text
            ELSE 'Eingangsdatum und Gewichte der Wägung prüfen.'::text
        END AS rat
   FROM (v_verdunstung_messung w
     LEFT JOIN auftrag a ON ((a.id = w.auftrag_id)))
  WHERE ((NOT w.verwendbar) AND (NOT w.sichtbar_schimmel) AND ((a.id IS NULL) OR (a.abgebrochen_ts IS NULL)) AND (EXISTS ( SELECT 1
           FROM verdunstung_wiegung v
          WHERE ((v.id = w.id) AND v.gemessen))))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
        CASE
            WHEN (g.kaliber_idx = '-1'::integer) THEN format(('%s Kisten nach Sollgewicht gezählt, aber für diese Sorte wurde noch '::text || 'nie eine fertige Palette gewogen — das Kistengewicht ist unbekannt'::text), g.anzahl)
            ELSE format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, (g.kaliber_idx + 1))
        END AS befund,
        CASE
            WHEN (g.kaliber_idx = '-1'::integer) THEN ('Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '::text || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'::text)
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — daraus kennt die App das Kistengewicht des Bandes, rückwirkend für alle Waschgänge dieser Sorte, auch für diesen. Oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat
   FROM ((v_auftrag_gebinde_masse g
     JOIN auftrag a ON ((a.id = g.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  -- 0104: Sind die Paletten dieser Arbeit am Anfang der Strasse gewogen, lernt
  -- v_koeff_gebinde das Kistengewicht des Bandes daraus, g.kg ist gesetzt, und
  -- dieser Befund entfällt von selbst — eine eigene Klausel wäre unerreichbar
  -- (die Mutation hat es gezeigt). Beim eigenen Kaliber (Zusatz 0054) gibt es
  -- kein Band zum Lernen; dort steht die Klausel ausdrücklich.
  WHERE ((g.kg IS NULL) AND (g.anzahl > 0) AND (g.kaliber_idx <> '-2'::integer))
UNION ALL
 SELECT 'Waage'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    CASE
        WHEN w.netto_kg <= 0 THEN format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — leichter als ihre Kisten und die Palette (Tara %s kg)', ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(ap.kisten::numeric * g.tara_kg_pro_kiste + g.tara_kg_palette, 1))
        ELSE format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — %s kg je Kiste', ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(w.netto_kg / ap.kisten::numeric, 1))
    END AS befund,
    'Waage, Kistenzahl oder Gebinde prüfen und im Korrekturfenster der Arbeit berichtigen — bis dahin rechnet die Masse dieser Palette mit.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = ap.gebindeart
     CROSS JOIN LATERAL (SELECT ap.brutto_gewogen_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_kg) w
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL
    AND ap.brutto_gewogen_kg IS NOT NULL AND ap.kisten IS NOT NULL AND ap.kisten > 0
    AND g.tara_kg_pro_kiste IS NOT NULL AND g.tara_kg_palette IS NOT NULL
    AND (w.netto_kg <= 0 OR w.netto_kg / ap.kisten::numeric < 4 OR w.netto_kg / ap.kisten::numeric > 30)
UNION ALL
 SELECT 'Kaliber fehlt'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen'::text AS befund,
    ('Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '::text || 'Stammdaten → Sortierschemata.'::text) AS rat
   FROM (auftrag a
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((a.station = 'waschen'::station) AND (NOT a.ist_fax) AND (a.kaliber_idx IS NULL) AND (a.kaliber_von_g IS NULL) AND (a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
           FROM auftrag_gebinde g
          WHERE ((g.auftrag_id = a.id) AND (g.anzahl > 0)))))
UNION ALL
 SELECT 'Ausschuss-Tara'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    m.ts AS start_ts,
    format('%s kg %s gespeichert — aus Brutto %s kg und heutiger Tara wären es %s kg'::text, m.kg,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'zu klein'::text
            ELSE 'zu gross'::text
        END, m.brutto_kg, round(n.roh)) AS befund,
    ('Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '::text || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'::text) AS rat
   FROM ((((ausschuss_messung m
     JOIN auftrag a ON ((a.id = m.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
     LEFT JOIN gebinde g ON ((g.art = m.gebindeart)))
     CROSS JOIN LATERAL ( SELECT ((m.brutto_kg - ((m.kisten)::numeric * g.tara_kg_pro_kiste)) -
                CASE
                    WHEN m.mit_palette THEN g.tara_kg_palette
                    ELSE (0)::numeric
                END) AS roh) n)
  WHERE ((m.brutto_kg IS NOT NULL) AND (a.abgebrochen_ts IS NULL) AND (n.roh IS NOT NULL) AND ((m.kg)::numeric <> round(n.roh)))
UNION ALL
 SELECT 'Ausschuss ohne Tara'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    m.ts AS start_ts,
    format('%s kg %s mit %s kg brutto gespeichert — nachrechnen lässt sich das nicht: %s'::text, m.kg,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'zu klein'::text
            ELSE 'zu gross'::text
        END, m.brutto_kg,
        CASE
            WHEN (m.gebindeart IS NULL) THEN 'an der Wägung steht keine Gebindeart'::text
            WHEN (g.art IS NULL) THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN (g.tara_kg_pro_kiste IS NULL) THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN (g.tara_kg_palette IS NULL) THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END) AS befund,
    ('Die gespeicherten Kilo bleiben, wie sie sind — geprüft werden können sie erst, '::text || 'wenn Gebindeart, Tara und Kistenzahl beisammen sind.'::text) AS rat
   FROM (((ausschuss_messung m
     JOIN auftrag a ON ((a.id = m.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
     LEFT JOIN gebinde g ON ((g.art = m.gebindeart)))
  WHERE ((m.brutto_kg IS NOT NULL) AND (a.abgebrochen_ts IS NULL) AND (((m.brutto_kg - ((m.kisten)::numeric * g.tara_kg_pro_kiste)) - g.tara_kg_palette) IS NULL))
UNION ALL
 SELECT 'Zetteldatum'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Zetteldatum %s gezählt, aber an dem Tag kam keine Palette dieser Charge'::text, count(*), to_char((ap.eingangsdatum)::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat
   FROM ((auftrag_palette ap
     JOIN auftrag a ON ((a.id = ap.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((ap.eingangsdatum IS NOT NULL) AND (ap.palette_id IS NULL) AND (ap.wiegung_id IS NULL) AND (a.abgebrochen_ts IS NULL) AND (NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE ((p.charge_nr = a.charge_nr) AND (p.eingangsdatum = ap.eingangsdatum))))))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.eingangsdatum
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — %s'::text, count(*), ap.brutto_zettel_kg,
        CASE
            WHEN bool_and(((ap.kisten IS NOT NULL) AND (ap.gebindeart IS NOT NULL))) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            ELSE 'gerechnet wird mit der mittleren Tara der Charge; stehen Kisten und Gebinde an der Palette, mit deren Tara'::text
        END) AS befund,
    'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal).'::text AS rat
   FROM ((auftrag_palette ap
     JOIN auftrag a ON ((a.id = ap.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((ap.brutto_zettel_kg IS NOT NULL) AND (a.abgebrochen_ts IS NULL) AND (NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE ((p.charge_nr = a.charge_nr) AND (p.brutto_kg = ap.brutto_zettel_kg))))))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg
UNION ALL
 SELECT 'Lieferung ohne Eingang'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    (min(l.datum))::timestamp with time zone AS start_ts,
    format('%s Lieferung(en) mit %s kg an Charge %s, aber im Wareneingang steht keine Palette dieser Charge'::text, count(*), round(sum(l.masse_kg)), l.charge_nr) AS befund,
    'Wareneingang der Charge nachtragen (Erntejournal) — oder die Lieferung gehört zu einer anderen Charge.'::text AS rat
   FROM v_lieferung_masse l
  WHERE ((l.buch = 'verkauf'::text) AND (l.charge_nr IS NOT NULL) AND (l.masse_kg > (0)::numeric) AND (NOT (EXISTS ( SELECT 1
           FROM v_kohorte_anteil k
          WHERE (k.charge_nr = l.charge_nr)))))
  GROUP BY l.charge_nr, l.sorte
UNION ALL
 SELECT v_plausibilitaet_0054_zusatz.art,
    v_plausibilitaet_0054_zusatz.auftrag_id,
    v_plausibilitaet_0054_zusatz.charge_nr,
    v_plausibilitaet_0054_zusatz.sorte,
    v_plausibilitaet_0054_zusatz.start_ts,
    v_plausibilitaet_0054_zusatz.befund,
    v_plausibilitaet_0054_zusatz.rat
   FROM v_plausibilitaet_0054_zusatz
UNION ALL
 SELECT 'Zetteldatum Zukunft'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Eingangsdatum %s gezählt — das liegt in der Zukunft, sehr wahrscheinlich ein falsches Jahr'::text, count(*), to_char((max(ap.eingangsdatum))::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung korrigieren (Jahr prüfen). Die Beobachtung bleibt gespeichert, bis sie berichtigt ist; solange rechnet die Auswertung sie nicht mit.'::text AS rat
   FROM ((auftrag_palette ap
     JOIN auftrag a ON ((a.id = ap.auftrag_id)))
     JOIN charge c ON ((c.nr = a.charge_nr)))
  WHERE ((ap.eingangsdatum > heute()) AND (a.abgebrochen_ts IS NULL))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts
UNION ALL
 SELECT 'Palettengewicht'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    (p.eingangsdatum)::timestamp with time zone AS start_ts,
    format('Eine Palette mit %s kg brutto — für eine Palette Kürbisse ist das unmöglich'::text, round(p.brutto_kg)) AS befund,
    'Bruttogewicht im Wareneingang prüfen — sehr wahrscheinlich ein Zahlendreher.'::text AS rat
   FROM (palette p
     JOIN charge c ON ((c.nr = p.charge_nr)))
  WHERE (p.brutto_kg > (2000)::numeric);
comment on view v_plausibilitaet is 'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette. 0066: „Ausschuss-Tara" rechnet nur nach, wo Kistenzahl und hinterlegte Tara da sind; fehlt eine, steht die Lücke als „Ausschuss ohne Tara" daneben. 0087: die Nachrechnung zieht die Palette nur ab, wenn sie mitgewogen wurde, und klemmt nichts auf null.';
grant select on v_plausibilitaet to authenticated;


-- ---------------------------------------------------------------------
-- 11. Die gespeicherten Ergebnisse — die Schleife ohne Modell
-- ---------------------------------------------------------------------
-- Dieselbe Schleife wie 0061/0068, ohne erg_modell, erg_kurve und
-- erg_selektion (gestrichen) und ohne erg_punkte (baut 0105 selbst, mit
-- Station und eigenem Anteil). Die Namen stehen für den Verdichter da.
-- verdichter: baut erg_gewichte erg_kaliber erg_gebinde erg_ausgang
-- verdichter: baut erg_lieferung erg_kohorte
-- verdichter: baut erg_koeff_verdunstung erg_koeff_ausschuss
-- verdichter: baut erg_koeff_nebenkanal erg_koeff_ueberfuellung erg_wiegung
-- verdichter: baut erg_fax erg_ausschuss erg_verarbeitung_alter erg_durchsatz
-- verdichter: baut erg_bilanz erg_marge erg_massenbilanz erg_naechste_charge
-- verdichter: baut erg_datenlage erg_plausibilitaet erg_datenqualitaet
do $$
declare
  paar text[];
  paare text[][] := array[
    -- [erg-Name, Quelle]
    ['erg_gewichte',           'v_gewichtsverteilung'],
    ['erg_kaliber',            'v_kaliber_verteilung'],
    ['erg_gebinde',            'v_koeff_gebinde'],
    ['erg_ausgang',            'v_ausgang_voll'],        -- seit 0089 mit voll
    ['erg_lieferung',          'v_lieferung_masse'],
    ['erg_kohorte',            'v_charge_kohorte'],
    ['erg_koeff_verdunstung',  'v_koeff_verdunstung'],
    ['erg_koeff_ausschuss',    'v_koeff_ausschuss'],
    ['erg_koeff_nebenkanal',   'v_koeff_nebenkanal'],
    ['erg_koeff_ueberfuellung','v_koeff_ueberfuellung'],
    ['erg_wiegung',            'v_wiegung_kennzahl'],
    ['erg_fax',                'v_fax_beobachtung'],
    ['erg_ausschuss',          'v_ausschuss_beobachtung'],
    ['erg_verarbeitung_alter', 'v_verarbeitung_alter'],
    ['erg_durchsatz',          'v_durchsatz'],
    ['erg_bilanz',             'v_saisonbilanz'],
    ['erg_marge',              'v_marge_buch'],
    ['erg_massenbilanz',       'v_massenbilanz'],
    ['erg_naechste_charge',    'v_naechste_charge'],
    ['erg_datenlage',          'v_datenlage'],
    ['erg_plausibilitaet',     'v_plausibilitaet'],
    ['erg_datenqualitaet',     'v_datenqualitaet']
  ];
begin
  foreach paar slice 1 in array paare loop
    execute format('drop materialized view if exists %I cascade', paar[1]);
    execute format('create materialized view %I as select * from %I with no data', paar[1], paar[2]);
    execute format('grant select on %I to authenticated', paar[1]);
    execute format('comment on materialized view %I is %L', paar[1],
                   format('%s, gespeichert für die App Erneuert mit auswertung_schritt().', paar[2]));
  end loop;
end $$;
-- Was die Schleife mit dem „drop … cascade" wegnimmt und keine spätere
-- Stelle neu stellt: die Indexe der neu gebauten Ergebnisse (der Block aus
-- 0068 — „wer die Schleife wieder abschreibt, schreibt diesen Block mit ab";
-- der Abgleich in supabase/test/run.sh meldete sechs davon) und die
-- Klartext-Kommentare von 0089 zu erg_ausgang und erg_wiegung.
create index if not exists erg_gewichte_sorte     on erg_gewichte (sorte);
create index if not exists erg_ausgang_ts         on erg_ausgang (ts);
create index if not exists erg_lieferung_datum    on erg_lieferung (datum);
create index if not exists erg_kohorte_charge     on erg_kohorte (charge_nr, eingangsdatum);
create index if not exists erg_wiegung_ts         on erg_wiegung (wiege_ts);
create index if not exists erg_fax_start          on erg_fax (start_ts);
create index if not exists erg_durchsatz_start    on erg_durchsatz (start_ts);
create index if not exists erg_verarbeitung_tag   on erg_verarbeitung_alter (tag);
comment on materialized view erg_ausgang is
  'Gespeichert: jede gewogene fertige Palette mit ihren Kennzahlen (v_ausgang_voll) — seit 0089 mit voll, damit die Marge-Karte sagen kann, welche Wägung nicht zählt.';
comment on materialized view erg_wiegung is
  'Gespeichert: jede Wägung mit ihren Kennzahlen (v_wiegung_kennzahl), seit 0089 mit plausibel und grund. Schritt 4 des Rechenwerks.';

-- ---------------------------------------------------------------------
-- 12. Der Zeitplan rechnet kein Modell mehr
-- ---------------------------------------------------------------------
-- Schritt 2 („Arbeiten") ohne mv_schimmel_punkte, mv_schimmel_modell,
-- erg_modell, erg_kurve, erg_selektion. Alles andere wie 0103.

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
        execute format('refresh materialized view %I', v_name);
      end;
    else
      execute format('refresh materialized view %I', v_name);
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


create or replace function auswertung_schluessel()
returns table (sicht text, ausdruck text) language sql immutable set search_path = public as $$
  values
    ('erg_ausgang',            'id'),
    ('erg_ausschuss',          'weg, charge_nr, auftrag_id'),
    ('erg_bilanz',             'heute'),
    ('erg_charge',             'charge_nr'),
    ('erg_datenlage',          'charge_nr'),
    ('erg_datenqualitaet',     'paletten_gezaehlt'),
    ('erg_durchsatz',          'auftrag_id'),
    ('erg_fax',                'auftrag_id'),
    ('erg_fax_wartezeit',      'gruppe, sorte, klasse'),
    ('erg_gebinde',            'sorte, kaliber_idx'),
    ('erg_gewichte',           'charge_nr, stufe_g'),
    ('erg_kaliber',            'charge_nr, klasse, kaliber_idx'),
    ('erg_koeff_ausschuss',    'sorte'),
    ('erg_koeff_fax',          'sorte'),
    ('erg_koeff_nebenkanal',   'sorte'),
    ('erg_koeff_ueberfuellung','n'),
    ('erg_koeff_verdunstung',  'sorte'),
    ('erg_kohorte',            'charge_nr, eingangsdatum'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_plausibilitaet',     'art, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte')
$$;
revoke execute on function auswertung_schluessel() from public;
grant execute on function auswertung_schluessel() to authenticated;

-- ---------------------------------------------------------------------
-- 13. Stand
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 106 $$;
