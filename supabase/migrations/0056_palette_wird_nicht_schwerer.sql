-- =====================================================================
-- 0056 — Eine Palette wird im Lager nicht schwerer
-- Kürbis-Verlust-Tracking
--
-- WAS PASSIERT IST
--
-- Auf dem Hof stand der Überblick mit „numeric field overflow", und
-- setup.sql brach mit derselben Meldung ab. Die Ursache war eine Wägung,
-- bei der die Palette *mehr* wog als beim Eingang — falsche Tara, falsche
-- Kistenzahl oder ein Zahlendreher. Die Tagesrate daraus ist negativ, und
-- (1 − Rate) hoch Lagertage wächst dann ins Unermessliche: bei −0.2 je Tag
-- und hundert Lagertagen um das Milliardenfache. Die Basis für den
-- Schimmelanteil ist numeric(12,2) und hält höchstens 10^10. Nachgestellt
-- in pruefung.sql (Block 0056) und run.sh (Stufe 4b).
--
-- WAS SICH ÄNDERT
--
-- 1. Eine Wägung, deren Netto um mehr als 1 % über dem Eingangsnetto liegt,
--    zählt nicht in die Verdunstungsrate (verwendbar = false). Sie bleibt
--    gespeichert — gelöscht wird nichts, was Daten trägt — und steht unter
--    Auffälligkeiten mit dem Grund und dem Rat. Das eine Prozent ist die
--    Toleranz zwischen zwei Waagen; mehr ist kein Rauschen, sondern ein
--    Fehler in Tara, Kistenzahl oder Zahl.
-- 2. Die Rate je Sorte ist nie negativ: Verdunstung kann Masse nur nehmen.
--    Kleine Zunahmen innerhalb der Toleranz drücken das Mittel höchstens
--    auf 0 — „keine messbare Verdunstung", nicht „Zunahme".
-- 3. Die Basis für den Schimmelanteil rechnet mit derselben gedeckelten
--    Rate wie Kaskade und Bestand (0 … 5 % je Tag) und mit Lagertagen ≥ 0.
--    Ein Eingangsdatum in der Zukunft (Tippfehler) sprengt so nichts mehr.
--
-- Dazu gehört, ausserhalb dieser Datei: setup.sql rechnet die gespeicherten
-- Auswertungen nicht mehr in jeder Zwischenfassung ihrer Formeln auf den
-- echten Daten aus (create materialized view … with no data), sondern
-- einmal am Ende mit den heutigen. Sonst hätte diese Korrektur die
-- Aktualisierung gar nicht erreicht: die Fassung von 0016 wäre vorher
-- über dieselbe Wägung gestolpert.
-- =====================================================================

-- ---------- 1. Die Wägung: schwerer als beim Eingang zählt nicht --------
create or replace view v_verdunstung_messung with (security_invoker = true) as
select w.id, w.charge_nr, c.sorte, c.schlag, w.palette_id, w.eingangsdatum,
       w.wiege_ts, w.sichtbar_schimmel, w.erfasser, w.auftrag_id,
       n.netto_damals_kg, n.netto_jetzt_kg,
       (w.wiege_ts::date - w.eingangsdatum) as lagertage,
       case when n.netto_damals_kg > 0 and n.netto_jetzt_kg > 0
             and (w.wiege_ts::date - w.eingangsdatum) > 0
            then 1 - power(n.netto_jetzt_kg / n.netto_damals_kg,
                           1.0 / (w.wiege_ts::date - w.eingangsdatum))
       end::numeric(10,6) as rate_pro_tag,
       (w.gemessen and not w.sichtbar_schimmel
        and n.netto_damals_kg > 0 and n.netto_jetzt_kg > 0
        and (w.wiege_ts::date - w.eingangsdatum) > 0
        -- 0056: eine Palette wird im Lager nicht schwerer. Bis 1 % ist es
        -- die Toleranz zwischen zwei Waagen, darüber ein Fehler.
        and n.netto_jetzt_kg <= n.netto_damals_kg * 1.01
        and (a.id is null or a.abgebrochen_ts is null)) as verwendbar
  from verdunstung_wiegung w
  join charge c on c.nr = w.charge_nr
  left join auftrag a on a.id = w.auftrag_id
  left join gebinde g on g.art = w.gebindeart
  cross join lateral (
        select w.brutto_damals_kg - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                                  - coalesce(g.tara_kg_palette, 0) as netto_damals_kg,
               w.brutto_jetzt_kg  - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
                                  - coalesce(g.tara_kg_palette, 0) as netto_jetzt_kg
       ) n;
comment on view v_verdunstung_messung is
  'Jede Verdunstungswägung mit Netto damals und jetzt, Lagertagen und Tagesrate. '
  'verwendbar: gemessen, ohne sichtbaren Schimmel, positive Nettos, Wiegedatum nach '
  'dem Eingang, Arbeit nicht abgebrochen — und die Palette höchstens 1 % schwerer '
  'als beim Eingang (0056). Was nicht verwendbar ist, steht in v_plausibilitaet.';

-- ---------- 2. Die Rate je Sorte: nie negativ -----------------------------
create or replace view v_koeff_verdunstung with (security_invoker = true) as
select sk.sorte,
       -- 0056: Verdunstung nimmt Masse, sie gibt keine. Ein Mittel unter 0
       -- kommt nur aus Waagenrauschen und heisst „keine messbare Verdunstung".
       -- NULL bleibt NULL: ohne Wiegung ist die Rate unbekannt, nicht 0.
       (case when k.mittel < 0 then 0 else k.mittel end)::numeric          as mittel,
       (case when coalesce(k.varianz, 0) = 0
               then case when k.mittel < 0 then 0 else k.mittel end
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                          as unten,
       (case when coalesce(k.varianz, 0) = 0
               then case when k.mittel < 0 then 0 else k.mittel end
             else greatest(k.mittel + k.t * sqrt(k.varianz), 0)
        end)::double precision                                          as oben,
       coalesce(k.n, 0)                                                 as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Wiegung vorhanden'
            when k.b >= 0.67        then 'Wiegungen dieser Sorte'
            when k.b >= 0.33        then 'Wiegungen dieser Sorte, zum Gesamtwert gezogen'
            else 'Wiegungen aller Sorten (zu wenige eigene Chargen)' end as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_verdunstung_geschaetzt g
     where g.art = 'verdunstung' and g.sorte is not distinct from sk.sorte
  ) k on true;
comment on view v_koeff_verdunstung is
  'Verdunstungsrate je Tag und Sorte, gepoolt über die verwendbaren Wägungen und '
  'bei wenigen eigenen Chargen zum Gesamtwert gezogen. Nie negativ (0056); NULL, '
  'solange keine Wägung vorliegt.';

-- ---------- 3. Die Basis für den Schimmelanteil: gedeckelt ----------------
create or replace view v_schimmel_beobachtung with (security_invoker = true) as
select am.auftrag_id, am.charge_nr, am.sorte, am.schlag, am.weg, am.station,
       am.start_ts, am.lagertage, am.masse_quelle,
       s.kg                                                        as schimmel_kg,
       am.eingang_netto_kg                                         as eingang_kg,
       (am.eingang_netto_kg * power(1 - x.r, x.tage))::numeric(12,2)
                                                                   as basis_jetzt_kg,
       (s.kg / nullif(am.eingang_netto_kg * power(1 - x.r, x.tage), 0))
                                                                   as anteil,
       anteil_plausibel(
         (s.kg / nullif(am.eingang_netto_kg * power(1 - x.r, x.tage), 0))::numeric
       )                                                           as plausibel,
       am.ist_fax
  from v_auftrag_masse am
  join v_schimmel_menge s on s.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
  -- 0056: dieselbe Deckelung wie in Kaskade und Bestand (0 … 5 % je Tag),
  -- Lagertage nie unter 0. Damit ist die Basis höchstens der Eingang.
  cross join lateral (
    select least(greatest(coalesce(kv.mittel, 0), 0), 0.05) as r,
           greatest(am.lagertage, 0)                        as tage
  ) x
 where am.eingang_netto_kg is not null
   and am.lagertage is not null;
comment on view v_schimmel_beobachtung is
  'Schimmel je Arbeit gegen die Masse, die am Tag der Arbeit noch da war: Eingang '
  'abzüglich Verdunstung mit der gedeckelten Rate (0056). Fax-Faules bleibt '
  'beobachtbar, geht aber nicht in die Verderbskurve.';

-- ---------- 4. Die Plausibilität nennt den Grund --------------------------
-- Vollständig neu, weil die Kette der Zweige eine Sicht ist; geändert ist nur
-- der Zweig „Wägung" (Zunahme über 1 %).
create or replace view v_plausibilitaet with (security_invoker = true) as
select 'Schimmel'::text as art, b.auftrag_id, b.charge_nr, b.sorte, b.start_ts,
       format('%s kg Schimmel auf %s kg Ware — das wären %s %%',
              round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100)) as befund,
       'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text as rat
  from v_schimmel_beobachtung b
 where b.anteil is not null and not b.plausibel and not b.ist_fax
union all
select 'Fax', f.auftrag_id, f.charge_nr, f.sorte, f.start_ts,
       format('%s kg Faules bei %s Kisten (%s kg) — das wären %s %%',
              round(f.faul_kg), f.kisten, round(f.masse_kg), round(f.anteil * 100)),
       'Entweder die Kistenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'
  from v_fax_beobachtung f
 where f.anteil is not null and not f.plausibel
union all
select 'Ausschuss', a.auftrag_id, a.charge_nr, a.sorte, null::timestamptz,
       format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse',
              round(coalesce(a.klein_kg, 0)), round(coalesce(a.gross_kg, 0)), round(a.basis_kg)),
       'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'
  from v_ausschuss_beobachtung a
 where a.weg = 'hand' and not a.plausibel
union all
select 'Ohne Nenner', a.id, a.charge_nr, c.sorte, a.start_ts,
       format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein',
              concat_ws(' und ',
                case when coalesce(s.kg, 0) > 0 then round(s.kg) || ' kg Faules' end,
                case when coalesce(x.kg, 0) > 0 then round(x.kg) || ' kg zu klein/gross' end),
              case when a.ist_fax then 'keine Kiste gezählt oder das Kistengewicht ist unbekannt'
                   when a.station = 'waschen' then 'keine Kiste gezählt und keine Menge eingetragen'
                   else 'keine Palette gezählt' end),
       case when a.ist_fax
            then 'Die gemachten Kisten je Kaliber am Auftrag zählen. Fehlt das Kistengewicht, '
                 || 'beim Sortieren mitzählen oder eine fertige Palette wiegen.'
            when a.station = 'waschen'
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
select 'Wägung', w.auftrag_id, w.charge_nr, w.sorte, w.wiege_ts,
       'Palette gewogen, aber '
       || case when w.netto_damals_kg is null or w.netto_jetzt_kg is null
                 then 'für die Gebindeart fehlt die Tara'
               when w.lagertage <= 0
                 then 'das Wiegedatum liegt nicht nach dem Eingangsdatum'
               when w.netto_damals_kg <= 0 or w.netto_jetzt_kg <= 0
                 then 'das Netto ist null oder negativ'
               when w.netto_jetzt_kg > w.netto_damals_kg * 1.01
                 then format('sie wiegt jetzt %s kg mehr als beim Eingang, und im Lager wird keine Palette schwerer',
                             round(w.netto_jetzt_kg - w.netto_damals_kg))
               else 'sie ist nicht verwertbar' end
       || ' — sie zählt nicht in die Verdunstungsrate',
       case when w.netto_damals_kg is null or w.netto_jetzt_kg is null
              then 'Unter Stammdaten → Gebinde die Tara nachtragen.'
            when w.netto_jetzt_kg > w.netto_damals_kg * 1.01
              then 'Gebindeart, Kistenzahl und beide Gewichte prüfen — meist stimmt die Tara nicht oder eine Zahl ist verdreht.'
            else 'Eingangsdatum und Gewichte der Wägung prüfen.' end
  from v_verdunstung_messung w
  left join auftrag a on a.id = w.auftrag_id
 where not w.verwendbar and not w.sichtbar_schimmel
   and (a.id is null or a.abgebrochen_ts is null)
   and exists (select 1 from verdunstung_wiegung v where v.id = w.id and v.gemessen)
union all
select 'Kistengewicht', g.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       case when g.kaliber_idx = -1
            then format('%s Kisten nach Sollgewicht gezählt, aber für diese Sorte wurde noch '
                        || 'nie eine fertige Palette gewogen — das Kistengewicht ist unbekannt', g.anzahl)
            else format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber wurde beim '
                        || 'Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt',
                        g.anzahl, g.kaliber_idx + 1) end,
       case when g.kaliber_idx = -1
            then 'Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '
                 || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'
            else 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '
                 || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.' end
  from v_auftrag_gebinde_masse g
  join auftrag a on a.id = g.auftrag_id
  join charge c on c.nr = a.charge_nr
 where g.kg is null and g.anzahl > 0 and g.kaliber_idx <> -2
union all
select 'Kaliber fehlt', a.id, a.charge_nr, c.sorte, a.start_ts,
       'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen',
       'Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '
       || 'Stammdaten → Sortierschemata.'
  from auftrag a
  join charge c on c.nr = a.charge_nr
 where a.station = 'waschen' and not a.ist_fax and a.kaliber_idx is null
   and a.kaliber_von_g is null and a.abgebrochen_ts is null
   and exists (select 1 from auftrag_gebinde g where g.auftrag_id = a.id and g.anzahl > 0)
union all
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
                              - coalesce(g.tara_kg_palette, 0)), 0)
union all
-- Ein Zetteldatum, zu dem die Charge keine Palette hat: vertippt, oder die
-- Palette fehlt im Wareneingang. So oder so stimmt eine Kohorte nicht.
select 'Zetteldatum', ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Palette(n) mit Zetteldatum %s gezählt, aber an dem Tag kam keine Palette dieser Charge',
              count(*), to_char(ap.eingangsdatum, 'DD.MM.YYYY')),
       'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  join charge c on c.nr = a.charge_nr
 where ap.eingangsdatum is not null and ap.palette_id is null and ap.wiegung_id is null
   and a.abgebrochen_ts is null
   and not exists (select 1 from palette p where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum)
 group by ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.eingangsdatum
union all
select art, auftrag_id, charge_nr, sorte, start_ts, befund, rat from v_plausibilitaet_0054_zusatz;

grant select on v_verdunstung_messung, v_koeff_verdunstung, v_schimmel_beobachtung,
                v_plausibilitaet to authenticated;
