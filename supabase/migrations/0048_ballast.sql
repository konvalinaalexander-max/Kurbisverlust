-- =====================================================================
-- 0048 — Ballast abwerfen
--
-- Der Rundgang aus der Vogelperspektive (docs/archiv/PROMPT_ABSCHLUSS.md)
-- fand Objekte, die kein Bildschirm liest, keine Ansicht braucht und höchstens
-- ein Test noch anfasst. Jedes wurde vorher belegt: pg_depend kennt keinen
-- Leser, kein Funktionsrumpf nennt es, src/ greift nicht darauf zu. Was hier
-- fällt, steht weiter in Git (0006, 0022, 0026, 0037, 0043, 0044) — wer die
-- Frage eines Tages wieder stellt, findet die Abfrage dort.
--
--   marge_messung           Alt-Kanal für von Hand eingetippte Marge-Posten.
--                           Die App schrieb ihn nur in den ersten Stunden des
--                           25. August (10b8a3f → a1a6cd5); seither kommt die
--                           Überfüllung aus ausgang_wiegung, der Nebenkanal aus
--                           der CSV. Hält die Tabelle trotzdem Zeilen, bricht
--                           diese Datei ab — nichts, was jemand gemessen hat,
--                           verschwindet still.
--   v_verdunstung_stichprobe  seit 0018 (gepoolte Koeffizienten) ohne Leser.
--   v_sortier_kuerbis       Expansion des Histogramms je Kürbis — nur ein Test
--                           las sie; der rechnet jetzt direkt mit sum(anzahl).
--   v_dubletten_pruefung, v_schlag_effekt  Prüfbare Annahmen aus 0022. Drei
--                           Migrationen mussten sie mitpflegen, gelesen hat sie
--                           nie jemand. Der Befund steht in STATISTIK_BEFUND.md.
--   v_auftrag_sortierart    0043, nie angebunden.
--   v_ausschuss_pruef       0044 — die Prüfung ist richtig, nur der Ort war
--                           falsch: sie steht jetzt als Zeile „Ausschuss-Tara"
--                           in v_plausibilitaet, wo der Betriebsleiter sie sieht.
--   schimmel_n(numeric)     Aus 0006 für den alten Rechenweg; seit 0036 nennt
--                           ihn keine Ansicht mehr.
-- =====================================================================

-- ---------- 1. Wächter: keine Messung geht still verloren -------------------
do $$
declare v_n bigint;
begin
  if to_regclass('public.marge_messung') is null then return; end if;
  select count(*) into v_n from public.marge_messung;
  if v_n > 0 then
    raise exception using
      message = format('marge_messung enthält %s Zeile(n) — die Einrichtung bricht hier ab.', v_n),
      detail  = 'Diese Tabelle war der frühere Kanal für von Hand eingetippte Marge-Posten. '
                'Die App schreibt sie seit dem 25. August nicht mehr, und ab dieser Fassung '
                'liest sie keine Auswertung mehr. Damit kein Messwert still verschwindet, '
                'wird sie nur gelöscht, wenn sie leer ist.',
      hint    = 'Im SQL-Editor: select * from marge_messung; — ansehen, bei Bedarf als CSV '
                'sichern, dann delete from marge_messung; und setup.sql erneut ausführen.';
  end if;
end $$;

-- ---------- 2. Die beiden Leser ohne marge_messung neu fassen ---------------
-- Überfüllung: nur noch die fertigen Paletten (Rohdaten statt Differenz).
-- Spalten und Typen bleiben, darum genügt create or replace.
create or replace view v_koeff_ueberfuellung with (security_invoker = true) as
with roh as (
  select k.ueberfuellung_kg as wert, k.kisten as n_kisten, k.ueberfuellung_je_kiste as je_kiste
    from v_ausgang_kennzahl k
   where k.ueberfuellung_je_kiste is not null
), s as (
  select count(*)::int as n,
         sum(wert) / nullif(sum(n_kisten), 0)::numeric as kg_pro_kiste,
         stddev_samp(je_kiste) as sd
    from roh
)
select n,
       kg_pro_kiste::numeric(10,3)                                  as kg_pro_kiste,
       sd::numeric(10,3)                                            as sd,
       (case when sd is null or n < 2 then kg_pro_kiste
             else greatest(kg_pro_kiste - 1.96 * sd / sqrt(n), 0) end)::numeric(10,3) as unten,
       (case when sd is null or n < 2 then kg_pro_kiste
             else kg_pro_kiste + 1.96 * sd / sqrt(n) end)::numeric(10,3)              as oben
  from s;

comment on view v_koeff_ueberfuellung is
  'Überschuss je Kiste über dem Sollgewicht, aus den Wägungen fertiger Paletten. '
  'Gezählt werden nur Wägungen, aus denen sich überhaupt ein Überschuss ergibt — '
  'Arbeiten nach Kaliber haben kein Sollgewicht und zählen nicht mit.';

-- Auffälligkeiten: der Zweig „Nicht ausgewertet" (marge_messung) entfällt,
-- der Zweig „Ausschuss-Tara" (bisher v_ausschuss_pruef) kommt dazu. Alles
-- andere ist Wort für Wort die Fassung aus 0041.
create or replace view v_plausibilitaet with (security_invoker = true) as
select 'Schimmel'::text as art, b.auftrag_id, b.charge_nr, b.sorte, b.start_ts,
       format('%s kg Schimmel auf %s kg Ware — das wären %s %%',
              round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100)) as befund,
       'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text as rat
  from v_schimmel_beobachtung b
 where b.anteil is not null and not b.plausibel
union all
select 'Ausschuss', a.auftrag_id, a.charge_nr, a.sorte, null::timestamptz,
       format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse',
              round(coalesce(a.klein_kg, 0)), round(coalesce(a.gross_kg, 0)), round(a.basis_kg)),
       'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'
  from v_ausschuss_beobachtung a
 where a.weg = 'hand' and not a.plausibel
union all
-- Messungen ohne Nenner: Faules oder Ausschuss erfasst, aber nichts, worauf
-- sich die Menge beziehen liesse. Diese Arbeiten fliessen nirgends ein — und
-- bis hierher hat das niemand erfahren.
select 'Ohne Nenner', a.id, a.charge_nr, c.sorte, a.start_ts,
       format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein',
              concat_ws(' und ',
                case when coalesce(s.kg, 0) > 0 then round(s.kg) || ' kg Faules' end,
                case when coalesce(x.kg, 0) > 0 then round(x.kg) || ' kg zu klein/gross' end),
              case when a.station = 'waschen' then 'keine Kiste gezählt und keine Menge eingetragen'
                   else 'keine Palette gezählt' end),
       case when a.station = 'waschen'
            then 'Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich '
                 || 'selbst) oder die verarbeitete Menge in kg nachtragen.'
            else 'Die gezählten Paletten am Auftrag nachtragen.' end
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_schimmel_menge s on s.auftrag_id = a.id
  left join (select auftrag_id, sum(kg)::numeric as kg from ausschuss_messung
              where gemessen group by auftrag_id) x on x.auftrag_id = a.id
  left join v_auftrag_masse m on m.auftrag_id = a.id
 where a.abgebrochen_ts is null
   and (coalesce(s.kg, 0) > 0 or coalesce(x.kg, 0) > 0)
   and coalesce(m.eingang_netto_kg, 0) <= 0
union all
-- Ein Waagenstand unter dem Leergewicht des Behälters ist unmöglich: Entweder
-- wurde netto abgelesen (dann stimmt die Einstellung nicht) oder vertippt.
select 'Palox', s.auftrag_id, a.charge_nr, c.sorte, s.ts,
       format('Waagenstand %s kg liegt unter dem Leergewicht des Palox (%s kg)',
              s.palox_stand_kg, palox_tara_kg()),
       'Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '
       || 'Sonst ist der Stand vertippt.'
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
  join charge c on c.nr = a.charge_nr
 where s.gemessen and a.abgebrochen_ts is null
   and s.palox_stand_kg is not null and s.palox_stand_kg < palox_tara_kg()
union all
-- Wägungen, die nicht verwertbar sind, ohne dass sichtbar Faules der Grund war.
select 'Wägung', w.auftrag_id, w.charge_nr, w.sorte, w.wiege_ts,
       'Palette gewogen, aber '
       || case when w.netto_damals_kg is null or w.netto_jetzt_kg is null
                 then 'für die Gebindeart fehlt die Tara'
               when w.lagertage <= 0
                 then 'das Wiegedatum liegt nicht nach dem Eingangsdatum'
               when w.netto_damals_kg <= 0 or w.netto_jetzt_kg <= 0
                 then 'das Netto ist null oder negativ'
               else 'sie ist nicht verwertbar' end
       || ' — sie zählt nicht in die Verdunstungsrate',
       case when w.netto_damals_kg is null or w.netto_jetzt_kg is null
              then 'Unter Stammdaten → Gebinde die Tara nachtragen.'
            else 'Eingangsdatum und Gewichte der Wägung prüfen.' end
  from v_verdunstung_messung w
  left join auftrag a on a.id = w.auftrag_id
 where not w.verwendbar and not w.sichtbar_schimmel
   and (a.id is null or a.abgebrochen_ts is null)
   and exists (select 1 from verdunstung_wiegung v where v.id = w.id and v.gemessen)
union all
-- Gezählte Kisten, für deren Kaliber noch nie am Sortieren mitgezählt wurde:
-- Die Masse bleibt unbekannt, aber es ist klar, was fehlt.
select 'Kistengewicht', g.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber wurde beim '
              || 'Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt',
              g.anzahl, g.kaliber_idx + 1),
       'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '
       || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.'
  from v_auftrag_gebinde_masse g
  join auftrag a on a.id = g.auftrag_id
  join charge c on c.nr = a.charge_nr
 where g.kg is null and g.anzahl > 0
union all
-- Gezählte Kisten an einem Waschgang, der gar kein Kaliber trägt. Über die
-- Maske kann das nicht entstehen (sie zeigt den Zähler erst mit Kaliber) —
-- als Wächter steht es trotzdem hier. Ein Waschgang mit eingetippter Menge
-- braucht kein Kaliber und wird deshalb nicht gemeldet.
select 'Kaliber fehlt', a.id, a.charge_nr, c.sorte, a.start_ts,
       'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen',
       'Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '
       || 'Stammdaten → Sortierschemata.'
  from auftrag a
  join charge c on c.nr = a.charge_nr
 where a.station = 'waschen' and a.kaliber_idx is null and a.abgebrochen_ts is null
   and exists (select 1 from auftrag_gebinde g where g.auftrag_id = a.id and g.anzahl > 0)
union all
-- Gewogener Ausschuss, dessen gespeichertes Netto nicht mehr zu Brutto und
-- heutiger Tara passt: die Gebinde-Tara wurde nach dem Wiegen geändert. Bis
-- 0048 stand das in einer eigenen Sicht, die kein Bildschirm las.
select 'Ausschuss-Tara', m.auftrag_id, a.charge_nr, c.sorte, m.ts,
       format('%s kg %s gespeichert — aus Brutto %s kg und heutiger Tara wären es %s kg',
              m.kg, case m.art when 'zu_klein' then 'zu klein' else 'zu gross' end,
              m.brutto_kg,
              greatest(round(m.brutto_kg - coalesce(m.kisten, 0) * coalesce(g.tara_kg_pro_kiste, 0)
                             - coalesce(g.tara_kg_palette, 0)), 0)),
       'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '
       || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'
  from ausschuss_messung m
  join auftrag a on a.id = m.auftrag_id
  join charge c on c.nr = a.charge_nr
  left join gebinde g on g.art = m.gebindeart
 where m.brutto_kg is not null and a.abgebrochen_ts is null
   and m.kg <> greatest(round(m.brutto_kg - coalesce(m.kisten, 0) * coalesce(g.tara_kg_pro_kiste, 0)
                              - coalesce(g.tara_kg_palette, 0)), 0);

comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, '
  'die sie gar nicht verwenden kann, weil ihnen der Nenner fehlt. Nicht '
  'ignorieren: fast immer ist etwas nachzutragen oder ein Tippfehler zu '
  'korrigieren.';

grant select on v_plausibilitaet to authenticated;

-- ---------- 3. Abwerfen -------------------------------------------------------
drop table if exists marge_messung;
drop type  if exists marge_art;
drop view  if exists v_ausschuss_pruef;
drop view  if exists v_auftrag_sortierart;
drop view  if exists v_dubletten_pruefung;
drop view  if exists v_schlag_effekt;
drop view  if exists v_sortier_kuerbis;
drop view  if exists v_verdunstung_stichprobe;
drop function if exists schimmel_n(numeric);

-- ---------- 4. Ein Satz statt eines Absatzes --------------------------------
-- Die beim Einrichten angelegten Kisten-Fassungen trugen eine vierzeilige
-- Bemerkung, die auf dem Handy die ganze Karte füllte. Die Bemerkung ist eine
-- Notiz, kein Messwert — sie darf kürzer werden.
update sortierschema
   set bemerkung = 'Standard beim Einrichten — Sollgewicht aus der Einstellung. '
                || 'Echtes Sollgewicht je Sorte: neue Fassung anlegen, nicht diese ändern.'
 where bemerkung like 'Beim Einrichten aus der Einstellung soll_kg_pro_kiste übernommen%';
