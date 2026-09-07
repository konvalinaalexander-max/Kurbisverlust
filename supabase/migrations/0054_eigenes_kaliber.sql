-- =====================================================================
-- 0054 — Waschen: das Kaliber wählen oder ein eigenes angeben
--
-- Am Waschbecken kommen Kisten mit einem Etikett an. Meist steht darauf
-- eines der Bänder, mit denen die Maschine sortiert hat — dann wählt der
-- Vorarbeiter es aus der Liste. Manchmal steht etwas anderes darauf: die
-- Maschine war an dem Tag anders eingestellt, oder es ist Ware, die nie
-- über die Maschine ging. Dafür gab es bisher keinen Platz — die Arbeit
-- lief ohne Kaliber, und die gezählten Kisten hatten keinen Nenner.
--
-- Jetzt kann die Arbeit ein eigenes Band tragen: kaliber_von_g / kaliber_bis_g.
-- Die Kisten dazu werden unter Index −2 gezählt (wie −1 die Kisten nach
-- Sollgewicht). Was so eine Kiste wiegt, weiss die Auswertung nur, wenn
-- beim Sortieren je ein Band mit genau diesen Grenzen gezählt wurde —
-- sonst bleibt die Masse unbekannt, und die Plausibilität sagt es.
--
-- Die Bänder je Sorte kommen weiterhin aus der Vorgabe des Betriebs
-- (Spezifikation §6, sorte_kaliber → sortierschema) beziehungsweise aus der
-- Fassung des letzten Sortierlaufs der Charge. Sechs der elf Sorten haben
-- dort dieselben drei Bänder (600–1100–1600–2000) — das ist die Vorgabe,
-- kein Versehen; die Maske nennt jetzt, woher die Bänder kommen.
-- =====================================================================

-- ---------- 1. Die Spalten am Auftrag --------------------------------------
alter table auftrag add column if not exists kaliber_von_g int;
alter table auftrag add column if not exists kaliber_bis_g int;
alter table auftrag drop constraint if exists auftrag_eigenes_kaliber;
alter table auftrag add constraint auftrag_eigenes_kaliber
  check ((kaliber_von_g is null and kaliber_bis_g is null)
      or (kaliber_von_g is not null and kaliber_bis_g is not null
          and kaliber_von_g >= 0 and kaliber_bis_g > kaliber_von_g
          and kaliber_idx is null));
comment on column auftrag.kaliber_von_g is
  'Eigenes Kaliber beim Waschen (0054): untere Grenze in Gramm, wenn das Etikett '
  'keines der Bänder der Fassung nennt. Dann ist kaliber_idx leer.';
comment on column auftrag.kaliber_bis_g is
  'Eigenes Kaliber beim Waschen (0054): obere Grenze in Gramm.';

-- Kisten zum eigenen Kaliber: Index −2
alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_kaliber_gueltig;
alter table auftrag_gebinde add constraint auftrag_gebinde_kaliber_gueltig
  check (kaliber_idx >= -2);
comment on column auftrag_gebinde.kaliber_idx is
  'Index in kaliber_baender der Fassung der Arbeit. −1 = Kisten nach Sollgewicht '
  '(ohne Kaliber), wie sie von der Hand-Linie kommen. −2 = Kisten zum eigenen '
  'Kaliber der Arbeit (auftrag.kaliber_von_g/bis_g, 0054).';

-- ---------- 2. Die Masse der Kisten kennt das eigene Kaliber ---------------
-- Ein eigenes Band wiegt so viel wie das gleiche Band beim Sortieren — wenn
-- es dort je gezählt wurde. Gesucht wird über die Grenzen, in jeder Fassung
-- der Sorte; die Messung dazu steht in v_koeff_gebinde unter dem Index, den
-- das Band in jener Fassung hatte.
create or replace view v_auftrag_gebinde_masse with (security_invoker = true) as
with band as (
  -- Welche Grenzen hat Index i in irgendeiner Fassung der Sorte? Darüber
  -- findet ein eigenes Band (−2) den Index, unter dem sein Gewicht gemessen ist.
  select distinct s.sorte, i.idx as kaliber_idx,
         (s.kaliber_baender -> i.idx ->> 0)::int as von,
         (s.kaliber_baender -> i.idx ->> 1)::int as bis
    from sortierschema s
    cross join lateral generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) as i(idx)
   where s.art = 'kaliber' and s.kaliber_baender is not null
)
select a.id as auftrag_id, g.kaliber_idx, g.anzahl,
       (g.anzahl * k.kg_je_gebinde)::numeric(12,2) as kg,
       (g.anzahl * k.unten)::numeric(12,2)         as kg_unten,
       (g.anzahl * k.oben)::numeric(12,2)          as kg_oben,
       k.n                                          as n_messungen
  from auftrag a
  join charge c on c.nr = a.charge_nr
  join auftrag_gebinde g on g.auftrag_id = a.id
  left join lateral (
    select b.kaliber_idx from band b
     where g.kaliber_idx = -2 and b.sorte = c.sorte
       and b.von = a.kaliber_von_g and b.bis = a.kaliber_bis_g
     order by b.kaliber_idx limit 1
  ) e on true
  -- Die Kistengewichte werden einmal gerechnet und dann verbunden — ein
  -- LATERAL über v_koeff_gebinde hiesse: die Gewichtstabelle je Zeile neu
  -- aggregieren, und der Lasttest in run.sh bricht (26 s statt 1 s).
  left join v_koeff_gebinde k
         on k.sorte = c.sorte
        and k.kaliber_idx = case when g.kaliber_idx = -2 then e.kaliber_idx else g.kaliber_idx end
 where a.station = 'waschen' and a.abgebrochen_ts is null;
comment on view v_auftrag_gebinde_masse is
  'Verarbeitete Menge einer Wascharbeit aus gezählten Kisten mal gemessenem '
  'Kistengewicht. kg ist NULL, solange das Kaliber nie am Sortieren gezählt '
  'wurde — dann fehlt der Nenner weiterhin. Index −2 (eigenes Kaliber) findet '
  'sein Gewicht über die Bandgrenzen in einer Fassung der Sorte (0054).';

-- ---------- 3. Plausibilität und Datenqualität -----------------------------
-- „Kaliber fehlt" gilt nur, wenn weder ein Band gewählt noch ein eigenes
-- angegeben ist; das Kistengewicht zum eigenen Kaliber hat seinen eigenen Satz.
create or replace view v_plausibilitaet_0054_zusatz with (security_invoker = true) as
select 'Kistengewicht'::text as art, g.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber ein Band mit diesen '
              || 'Grenzen wurde beim Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt',
              g.anzahl, a.kaliber_von_g, a.kaliber_bis_g)                         as befund,
       'Entweder das Band aus der Liste wählen, das dem Etikett entspricht, oder beim '
       || 'nächsten Sortierlauf mit diesem Band die gefüllten Kisten zählen.'       as rat
  from v_auftrag_gebinde_masse g
  join auftrag a on a.id = g.auftrag_id
  join charge c on c.nr = a.charge_nr
 where g.kg is null and g.anzahl > 0 and g.kaliber_idx = -2;
grant select on v_plausibilitaet_0054_zusatz to authenticated;

-- Die beiden Sichten werden aus ihrem Quelltext (0051) nachgebaut, mit genau
-- zwei Änderungen: „Kaliber fehlt" nur ohne Band UND ohne eigenes Kaliber;
-- das Kistengewicht zum eigenen Kaliber hat seinen eigenen Satz (oben).
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

create or replace view v_datenqualitaet with (security_invoker = true) as
with arbeiten as (select a.* from auftrag a where a.abgebrochen_ts is null),
     fertig as (select * from arbeiten where status = 'abgeschlossen')
select
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id)::int as paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where ap.eingangsdatum is not null)::int                                             as paletten_mit_datum,
  (select count(*) from fertig where not ist_fax)::int                                    as arbeiten_fertig,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null))::int                     as arbeiten_mit_ablesung,
  (select count(*) from fertig f where not f.ist_fax and (select count(*) from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null) >= 2)::int                as arbeiten_mit_zwei_ablesungen,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from auftrag_angabe g
    where g.auftrag_id = f.id and g.schluessel = 'eine_charge'))::int                     as arbeiten_mit_antwort,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen)::int                                                                as ausschuss_messungen,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen and m.brutto_kg is not null)::int                                    as ausschuss_gewogen,
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.faul_kg is not null and w.gemessen)::int             as lagerkontrollen,
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.faul_kg is not null and w.gemessen
      and w.auswahl = 'erreichbar_zufaellig')::int                                        as lagerkontrollen_zufaellig,
  (select count(*) from sortier_lauf)::int                                                as sortierlaeufe,
  (select count(*) from sortier_lauf where auftrag_id is not null)::int                   as sortierlaeufe_zugeordnet,
  (select count(*) from fertig f where f.station = 'sortieren')::int                      as sortier_arbeiten,
  (select count(*) from fertig f where f.station = 'sortieren' and exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int              as sortier_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax)::int      as wasch_arbeiten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax
    and (f.kaliber_idx is not null or f.kaliber_von_g is not null)
    and exists (select 1 from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int
                                                                                          as wasch_arbeiten_mit_kisten,
  -- neu (0051): Fax
  (select count(*) from fertig f where f.ist_fax)::int                                    as fax_arbeiten,
  (select count(*) from fertig f where f.ist_fax and exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int              as fax_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax and exists (select 1
    from schimmel_messung s where s.auftrag_id = f.id and s.gemessen))::int               as fax_arbeiten_mit_faulem;
