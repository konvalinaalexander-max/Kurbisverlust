-- =====================================================================
-- 0014 — Abfragbare Zahlen und Einblick hinter die Rechnung
--
-- TEIL A — numerische Ausgaben
--
-- power() und sqrt() liefern in Postgres "double precision". Das floss bis in
-- die Views durch, die der Betriebsleiter direkt abfragt — und dort scheitert
-- dann das Naheliegendste:
--
--   select round(kg, 1) from v_verlust_ranking;
--   ERROR:  function round(double precision, integer) does not exist
--
-- Genau dieser Weg ist ausdrücklich vorgesehen (Spec §11: Zugriff auf die
-- Rohdaten über die SQL-Oberfläche). Die Ausgabespalten sind deshalb jetzt
-- numeric. Die Zwischenrechnung in v_kaskade bleibt double — dort ist es
-- schneller und niemand fragt sie von Hand ab.
--
-- TEIL B — die Kurve sichtbar machen
--
-- Die Schimmel-Hochrechnung ist der undurchsichtigste Teil des Modells. Ohne
-- Einblick in die Kurve muss man ihr glauben. v_schimmel_kurve_anzeige legt
-- sie offen: je Altersklasse der gemessene Anteil, wie viele Messungen
-- dahinterstehen und welcher Wert tatsächlich verwendet wird.
-- =====================================================================

drop view if exists v_marge_buch;
drop view if exists v_verlust_ranking;
drop view if exists v_massenbilanz;
drop view if exists v_hochrechnung;

create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.szenario, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg,
       s.strom, s.buch,
       s.kg::numeric(14,2)          as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       s.koeffizient::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung',      'verlust', k.verdunstung_kg, k.m0, k.r,       k.r_n,     k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'),
    ('Schimmel/Fäulnis', 'verlust', k.schimmel_kg,    k.m1, k.f,       schimmel_n(k.alter_tage),
     'Schimmelkurve nach Lagerdauer',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer'),
    ('Ausschuss zu klein','verlust', k.klein_kg,      k.m2, k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze'),
    ('Nebenkanal zu gross','marge',  k.nebenkanal_kg, k.m2, k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'),
    ('Verkaufsfähig',    'bilanz',  k.verkaufsfaehig_kg, k.m2, null::numeric, null::int, null::text,
     'Rest der Kaskade')
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel);

create view v_verlust_ranking with (security_invoker = true) as
select strom, buch,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       sum(kg) filter (where szenario = 'mittel' and portion = 'ausgelagert') as kg_beobachtet,
       sum(kg) filter (where szenario = 'mittel' and portion = 'lager')       as kg_projiziert,
       min(koeff_n)                                                          as koeff_n_min
  from v_hochrechnung
 where buch = 'verlust'
 group by strom, buch
 order by 3 desc nulls last;

create view v_marge_buch with (security_invoker = true) as
select 'Nebenkanal zu gross'::text as posten,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from v_hochrechnung where buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.kisten)::numeric(14,2),
       (u.unten * v.kisten)::numeric(14,2),
       (u.oben  * v.kisten)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.kisten))
  from v_koeff_ueberfuellung u
  cross join lateral (
        select sum(h.kg * b.weg2_anteil) / 8.0 as kisten
          from v_hochrechnung h
          join v_hochrechnung_basis b on b.charge_nr = h.charge_nr
         where h.strom = 'Verkaufsfähig' and h.szenario = 'mittel'
       ) v
 where u.n > 0;

-- Die Massenbilanz vergleicht das Modell gegen die gewogene CSV. Dabei darf
-- nur verglichen werden, was auch wirklich über das Sortierband lief: Geht eine
-- Charge teils von Hand (keine CSV) und teils über die Maschine, stand vorher
-- die Modellmasse der *ganzen* Charge gegen die CSV eines Teils davon — die
-- Bilanz zeigte dann dauerhaft ein Defizit von 30–60 %, ohne dass etwas falsch
-- war. Das Modell wird deshalb auf den CSV-Anteil der ausgelagerten Masse
-- heruntergerechnet.
create view v_massenbilanz with (security_invoker = true) as
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       (m.modell_kg * q.anteil_mit_csv)::numeric(14,2)     as modell_am_band_kg,
       c.gemessen_kg                                       as csv_gemessen_kg,
       (c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)::numeric(14,2) as abweichung_kg,
       case when m.modell_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)
                  / (m.modell_kg * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       h.restbestand_kg::numeric(14,2)                     as restbestand_kg
  from v_hochrechnung_basis b
  left join lateral (
        select sum(k.m2) as modell_kg from v_kaskade k
         where k.charge_nr = b.charge_nr and k.szenario = 'mittel' and k.portion = 'ausgelagert'
       ) m on true
  left join lateral (
        -- Welcher Anteil der ausgelagerten Masse hat überhaupt eine CSV?
        select coalesce(
                 sum(am.eingang_netto_kg) filter (
                   where exists (select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
                 / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
          from v_auftrag_masse am
         where am.charge_nr = b.charge_nr
           and am.station in ('sortieren', 'waschen_sortieren')
           and am.eingang_netto_kg is not null
       ) q on true
  left join lateral (
        select sum(lm.masse_kg) as gemessen_kg
          from v_sortier_lauf_masse lm where lm.charge_nr = b.charge_nr
       ) c on true
  left join lateral (
        select sum(k.verkaufsfaehig_kg) as restbestand_kg from v_kaskade k
         where k.charge_nr = b.charge_nr and k.szenario = 'mittel' and k.portion = 'lager'
       ) h on true;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

-- ---------- Teil B: die Schimmelkurve offenlegen --------------------------
drop view if exists v_schimmel_kurve_anzeige;
create view v_schimmel_kurve_anzeige with (security_invoker = true) as
select k.von, k.bis,
       case when k.bis > 9999 then k.von || '+ Tage'
            else k.von || '–' || k.bis || ' Tage' end       as altersklasse,
       k.n                                                  as messungen,
       (k.anteil)::numeric(10,4)                            as gemessen,
       (k.anteil_mono)::numeric(10,4)                       as verwendet,
       (k.unten)::numeric(10,4)                             as unten,
       (k.oben)::numeric(10,4)                              as oben,
       case when k.n = 0 then 'keine Messung — es gilt der Wert der Klasse darunter'
            when k.anteil is distinct from k.anteil_mono
                 then 'gemessener Wert lag unter einer jüngeren Klasse; verdorbene Ware '
                      || 'wird nicht wieder gesund, deshalb wird der höhere Wert verwendet'
            when k.n < 2 then 'nur eine Messung — noch kein Bereich bestimmbar'
            else 'aus den Messungen dieser Altersklasse' end as erlaeuterung
  from v_schimmel_kurve k
 order by k.von;

comment on view v_schimmel_kurve_anzeige is
  'Die Schimmel-Hochrechnung zum Nachschauen: was gemessen wurde, was daraus '
  'verwendet wird und warum.';

grant select on v_schimmel_kurve_anzeige to authenticated;

-- ---------- Plausibilitäts-Schwelle nachgeschärft --------------------------
-- 90 % waren zu lasch: Ein Zahlendreher (450 → 4500 kg) landete bei 87 % und
-- rutschte durch. Über die Hälfte einer Palette als Schimmel ist entweder ein
-- Tippfehler oder eine Katastrophe — beides gehört dem Betriebsleiter gemeldet,
-- und beides würde den Koeffizienten beherrschen, wenn es mitgerechnet würde.
create or replace function anteil_plausibel(p_anteil numeric)
returns boolean language sql immutable as $$
  select p_anteil is not null and p_anteil >= 0 and p_anteil <= 0.5;
$$;
