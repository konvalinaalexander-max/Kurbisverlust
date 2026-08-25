-- =====================================================================
-- 0025 — Der Schimmel beim Waschen ist ein Zuwachs, kein Gesamtwert
--
-- Nach 0024 kommt Schimmel #2 im Modell an. Trotzdem blieb die Schätzung
-- daneben (25 Saisons, zweistufiger Weg 1, 30 % im Lager):
--
--   Schimmel/Fäulnis   Verzerrung −16.4 %   Überdeckung 4 %
--
-- Der Grund steckt im Ablauf, nicht in der Statistik. Auf Weg 1 wird zweimal
-- Faules aussortiert: einmal vor dem Sortierband, Wochen später nochmals vor
-- dem Waschbecken. Im Palox am Waschbecken liegt aber nur, was **seit dem
-- Sortieren** dazugekommen ist — der erste Teil ist längst entsorgt.
--
-- Die Kurve F(t) ist dagegen kumulativ: „welcher Anteil der Ware ist bis Tag t
-- insgesamt verdorben". Wer den Waschen-Palox direkt als F(t₂) liest, setzt
--
--   F(t₂) ≈ F(t₂) − F(t₁)     statt      F(t₂)
--
-- also einen deutlich zu kleinen Wert — und zwar ausgerechnet bei den längsten
-- Lagerdauern, wo die Kurve am steilsten ist. Das Modell wird dadurch flacher
-- angepasst und unterschätzt alles, was lange liegt.
--
-- Der naheliegende Weg — den ersten Betrag in Kilo dazurechnen — geht schief:
-- Der Durchsatz am Waschbecken ist schon um Verdunstung, Schimmel und
-- Ausschuss vermindert, taugt also nicht als Bezugsmasse für eine Menge, die
-- beim Sortieren entnommen wurde. Gemessen hat dieser Ansatz +15.3 %
-- Verzerrung ergeben — genauso falsch wie vorher, nur andersherum.
--
-- Richtig wird es über Anteile statt über Kilo. Am Waschbecken kommt eine
-- Masse an, von der ein Teil faul ist:
--
--   g = Schimmel₂ / (Durchsatz + Schimmel₂)
--
-- Das ist der Anteil der *Überlebenden* des ersten Durchgangs, die es bis
-- hierher nicht geschafft haben. Beide Durchgänge zusammen ergeben dann
--
--   1 − F(t₂) = (1 − F(t₁)) · (1 − g)
--
-- Darin steckt keine einzige Kilo-Umrechnung mehr: g stammt vollständig aus
-- am Waschbecken gemessenen Grössen, F(t₁) ist der Anteil, den dieselbe
-- Charge beim Sortieren hatte. Ist beim Sortieren nichts gemessen worden,
-- gilt F(t₁) = 0 und der Punkt sagt nur, was er sicher weiss.
-- =====================================================================

create or replace view v_schimmel_punkte with (security_invoker = true) as
with schimmel_je_auftrag as materialized (
  select auftrag_id, sum(kg)::numeric as kg
    from schimmel_messung where gemessen group by auftrag_id
),
-- Der Anteil, den die Charge beim Sortieren schon hatte: F(t₁).
-- Nur Sortierläufe, die *vor* dem Waschen lagen — was später sortiert wurde,
-- kann in diesem Waschgang nicht dabei gewesen sein. Ohne diese Einschränkung
-- fliesst der Zustand späterer, älterer Ware in frühe Waschgänge ein und der
-- Punkt fällt zu hoch aus (gemessen: +7.5 % auf den Waschen-Punkten).
sortier_lauf_anteil as materialized (
  select b.charge_nr, b.start_ts, b.schimmel_kg, b.basis_jetzt_kg
    from v_schimmel_beobachtung b
   where b.station = 'sortieren' and b.plausibel and b.anteil is not null
)
-- Erster Durchgang und Weg 2: der Palox enthält alles bis dahin Verdorbene,
-- der gemessene Anteil ist direkt F(t).
select b.charge_nr, b.sorte, b.schlag, b.lagertage, b.schimmel_kg,
       b.basis_jetzt_kg, b.anteil, b.plausibel,
       'verarbeitung'::text as quelle, b.auftrag_id
  from v_schimmel_beobachtung b
 where b.station in ('sortieren', 'waschen_sortieren')
union all
-- Zweiter Durchgang auf Weg 1: aus dem Zuwachs den kumulativen Wert bilden.
select a.charge_nr, a.sorte, a.schlag, a.lagertage,
       s.kg                                                      as schimmel_kg,
       (a.eingang_netto_kg + s.kg)                               as basis_jetzt_kg,
       k.f2                                                      as anteil,
       anteil_plausibel(k.f2)                                    as plausibel,
       'verarbeitung', a.auftrag_id
  from v_auftrag_masse a
  join schimmel_je_auftrag s on s.auftrag_id = a.auftrag_id
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
-- Lagerkontrollen: eine zufällig gegriffene Palette, nichts vorher entnommen.
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
  'Alle Schimmelbeobachtungen als *kumulativer* Anteil F(t). Der Palox am '
  'Waschbecken enthält nur den Zuwachs seit dem Sortieren; daraus wird über '
  'die bedingte Überlebensrate der kumulative Wert gebildet, ohne Kilo '
  'umzurechnen. quelle = lager heisst: zufällig gegriffen, also frei von der '
  'Selektionsverzerrung der Verarbeitungsreihenfolge.';

grant select on v_schimmel_punkte to authenticated;
