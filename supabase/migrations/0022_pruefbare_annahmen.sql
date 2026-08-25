-- =====================================================================
-- 0022 — Zwei Annahmen prüfbar machen, statt sie zu glauben
--
-- ---------- 1. Die Dubletten-Regel ---------------------------------------
-- Regel 3 der CSV-Reinigung verwirft jeden Wert, der gleich seinem direkten
-- Vorgänger ist — 12–28 % aller Zeilen. Begründet ist das damit, dass zwei
-- echte Kürbisse nacheinander nur mit verschwindender Wahrscheinlichkeit
-- exakt gleich viel wiegen. Diese Wahrscheinlichkeit lässt sich aus der
-- Gewichtsverteilung selbst ausrechnen: Für unabhängige Ziehungen ist sie
-- Σ pᵢ², die Summe der quadrierten Anteile je Gewichtsstufe.
--
-- Damit wird prüfbar, was die Regel fälschlich entfernt: Von den verworfenen
-- Zeilen sind höchstens Σpᵢ² / Nachbar_gleich_Anteil echte Gleichheiten.
-- Die Ansicht rechnet beides aus den tatsächlich eingelesenen Dateien.
--
-- ---------- 2. Stratifizierung nach Schlag -------------------------------
-- Spec §9 nennt Sorte, Schlag und Lagerdauer. Gebaut ist nur Sorte. Ob der
-- Schlag eigenständig etwas beiträgt, entscheidet nicht die Meinung, sondern
-- die Frage, ob die Unterschiede zwischen Schlägen grösser sind als das, was
-- blosses Stichprobenrauschen erzeugt. Genau das rechnet v_schlag_effekt —
-- dieselbe Momentenschätzung wie bei der Sorten-Bündelung.
--
-- Anzumerken: In diesen Daten ist jede Charge genau eine Kombination aus
-- Schlag und Sorte (42 Chargen, 42 Kombinationen). Der Schlag ist damit in
-- der Charge verschachtelt, und die chargen-robuste Fehlerrechnung aus 0017
-- und 0018 hat die Streuung zwischen Schlägen bereits im Bereich drin. Eine
-- eigene Schlag-Stratifizierung würde die Punktschätzung ändern, nicht die
-- Ehrlichkeit des Bereichs — sie lohnt sich nur, wenn tau2_schlag deutlich
-- über 0 liegt.
-- =====================================================================

create or replace view v_dubletten_pruefung with (security_invoker = true) as
with anteile as (
  -- Gewichtsverteilung über alle eingelesenen Dateien
  select gewicht_g, sum(anzahl)::numeric as n from sortier_gewicht group by gewicht_g
), gesamt as (
  select sum(n) as n_gesamt, sum(power(n, 2)) as summe_quadrate,
         count(*)::int as n_stufen from anteile
), laeufe as (
  select sum(n_dubletten)::numeric as verworfen, sum(n_roh)::numeric as roh
    from sortier_lauf where n_roh > 0
)
select g.n_gesamt::bigint                                            as kuerbisse,
       l.roh::bigint                                                 as zeilen_roh,
       l.verworfen::bigint                                           as zeilen_verworfen,
       (l.verworfen / nullif(l.roh, 0))                              as anteil_verworfen,
       -- Σpᵢ²: wie oft zwei unabhängig gezogene Kürbisse gleich viel wiegen
       (g.summe_quadrate / nullif(power(g.n_gesamt, 2), 0))           as zufalls_gleichheit,
       -- Wie viel der verworfenen Zeilen war vermutlich echt?
       (g.summe_quadrate / nullif(power(g.n_gesamt, 2), 0))
         / nullif(l.verworfen / nullif(l.roh, 0), 0)                  as anteil_faelschlich,
       case
         when l.roh is null or l.roh = 0 then 'keine CSV eingelesen'
         -- Testdaten haben oft nur eine Handvoll Gewichte; Σpᵢ² ist dann
         -- gross, ohne dass das über echte Kürbisse etwas aussagt.
         when g.n_stufen < 50
           then format('nur %s verschiedene Gewichte — das sind keine echten '
                       || 'Messdaten, die Prüfung sagt hier nichts', g.n_stufen)
         when (g.summe_quadrate / nullif(power(g.n_gesamt, 2), 0))
              / nullif(l.verworfen / nullif(l.roh, 0), 0) < 0.05
           then 'Regel trägt: die verworfenen Gleichheiten sind weit häufiger, '
                || 'als Zufall sie erzeugen könnte'
         else 'Vorsicht: der Zufall erklärt einen erheblichen Teil der '
              || 'verworfenen Zeilen — die Regel gehört an einer handgezählten '
              || 'Palette überprüft (Spec §13)'
       end                                                            as befund,
       g.n_stufen                                                     as gewichtsstufen
  from gesamt g cross join laeufe l;

comment on view v_dubletten_pruefung is
  'Prüft die Dubletten-Regel gegen die Gewichtsverteilung selbst. '
  'anteil_faelschlich ist der Anteil der verworfenen Zeilen, der auch bei '
  'echten, unabhängigen Kürbissen aufgetreten wäre.';

create or replace view v_schlag_effekt with (security_invoker = true) as
with punkte as (
  select p.schlag, p.charge_nr, p.basis_jetzt_kg::numeric as w,
         ln(-ln(1 - p.anteil::numeric)) - (m.ln_lambda + m.k * ln(p.lagertage::numeric)) as e
    from v_schimmel_punkte p cross join v_schimmel_modell m
   where m.brauchbar and p.plausibel and p.anteil > 0 and p.anteil < 1 and p.lagertage > 0
), je_schlag as (
  select schlag, count(*)::int as n, count(distinct charge_nr)::int as c,
         sum(w) as sw, sum(w * e) / nullif(sum(w), 0) as mittel
    from punkte group by schlag
), streuung as (
  select count(*)::int                                                  as n_schlaege,
         sum(sw * power(mittel, 2)) / nullif(sum(sw), 0)                as beobachtet,
         -- Was blosses Rauschen erzeugen würde: die mittlere Varianz der
         -- Schlagmittel bei zufälliger Zuordnung
         (select sum(w * power(e, 2)) / nullif(sum(w), 0) from punkte)
           / nullif(avg(n), 0)                                          as erwartet_durch_zufall
    from je_schlag where n >= 2
)
select n_schlaege, beobachtet, erwartet_durch_zufall,
       greatest(beobachtet - erwartet_durch_zufall, 0)                  as tau2_schlag,
       case
         when n_schlaege is null or n_schlaege < 3
           then 'zu wenige Schläge mit Messungen'
         when greatest(beobachtet - erwartet_durch_zufall, 0) <= 0
           then 'die Unterschiede zwischen Schlägen sind nicht grösser als '
                || 'Stichprobenrauschen — eine eigene Schlag-Schätzung brächte nichts'
         when beobachtet > 2 * erwartet_durch_zufall
           then 'die Schläge unterscheiden sich deutlich — eine eigene '
                || 'Schlag-Stratifizierung wäre begründet'
         else 'schwacher Hinweis auf Schlag-Unterschiede, für eine eigene '
              || 'Schätzung reicht es noch nicht'
       end                                                              as befund
  from streuung;

comment on view v_schlag_effekt is
  'Entscheidet an den Daten, ob eine Stratifizierung nach Schlag begründet '
  'ist. Bis tau2_schlag deutlich über 0 liegt, steckt die Streuung zwischen '
  'Schlägen bereits in der chargen-robusten Fehlerrechnung.';

grant select on v_dubletten_pruefung, v_schlag_effekt to authenticated;
