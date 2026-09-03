-- =====================================================================
-- 0041 — Die Kiste ist am Waschbecken die Einheit, und ihr Gewicht wird
--        gemessen, nicht geschätzt
--
-- Der Betrieb hat am 3. September zwei Dinge entschieden.
--
-- ---------- 1. Das Datum vom Zettel ist Pflicht --------------------------
-- Beim Palettenzählen war es freiwillig. Steht es nicht da, rechnet die
-- Auswertung das Alter des Lagerbestands mit dem Mittel der ganzen Charge —
-- in der Demo drei bis sechs Tage daneben (0036, Befund 4). „Zwing sie",
-- sagt der Betrieb, und damit ist es eine Pflichtangabe.
--
-- Die Bedingung wird als NOT VALID angelegt: Neue Zeilen brauchen ein Datum,
-- bestehende behalten ihre Lücke. Sie nachträglich mit einem gefolgerten
-- Datum zu füllen hiesse, eine Beobachtung zu erfinden, die niemand gemacht
-- hat (docs/Datenarchitektur, Regel 3).
--
-- ---------- 2. Am Waschbecken werden Kisten gezählt ----------------------
-- Am Waschbecken kennt die Auswertung die verarbeitete Menge nicht: Die
-- Palette ist beim Sortieren in Kaliber-Kisten aufgelöst worden, ein Kürbis
-- einer Palette liegt in fünf Kisten und eine Kiste hält Ware aus mehreren
-- Paletten. Ohne Menge hat der dort ausgelesene Schimmel keinen Nenner und
-- fällt aus der Rechnung („Ohne Nenner", 0036).
--
-- Gewogen wird auf Weg 1 nie. Die Einheit, die es dort gibt, ist die Kiste.
-- Also:
--
--   * Wer die Arbeit eröffnet, trägt ein, welches Kaliber gewaschen wird.
--     Das ist in der Regel die Person mit dem besten Überblick, und es ist
--     eine Angabe je Arbeit statt eine je Kiste.
--   * Wer an der Station steht, zählt nur: wie viele Kisten, und das Datum.
--   * Was eine Kiste wiegt, wird nicht geschätzt und nicht gewogen, sondern
--     am Sortieren gemessen. Dort ist die Masse je Kaliber aus der CSV
--     bekannt (die Maschine wiegt jeden Kürbis), und die gefüllten Kisten
--     werden ebenfalls gezählt. Aus beidem folgt kg je Kiste je Kaliber —
--     mit Streuung über die Läufe, also mit einem Bereich.
--
-- Damit bleibt die Regel gewahrt: Gespeichert wird die Zählung, das Gewicht
-- der Kiste ist Ableitung. Ändert sich die Messung, ändert sich die Masse
-- mit; die gezählte Zahl bleibt, wie sie gezählt wurde.
--
-- Gibt es für ein Kaliber noch keine einzige Messung, bleibt die Masse NULL
-- — nicht 0. Der Waschgang steht dann weiter unter „Ohne Nenner", jetzt aber
-- mit dem Hinweis, dass die Kistenzählung beim Sortieren fehlt.
--
-- Annahme, die dabei mitgeht: Eine Kiste, die beim Sortieren gefüllt wurde,
-- kommt als dieselbe Kiste ans Waschbecken. Wird zwischendurch umgepackt
-- oder zusammengeschüttet, stimmt das Kistengewicht nicht mehr — das steht
-- als Annahme in ABLAUF.md und als Frage 13 in FRAGEN.md.
-- =====================================================================

-- ---------- 1. Das Datum ist Pflicht -------------------------------------
alter table auftrag_palette drop constraint if exists auftrag_palette_datum_pflicht;
alter table auftrag_palette add constraint auftrag_palette_datum_pflicht
  check (eingangsdatum is not null or palette_id is not null or wiegung_id is not null)
  not valid;
comment on column auftrag_palette.eingangsdatum is
  'Datum vom Palettenzettel. Pflicht für neue Zeilen (0041) — ohne es rechnet '
  'die Auswertung das Alter des Lagerbestands mit dem Chargenmittel. Entbehrlich '
  'nur, wenn das Datum ohnehin feststeht: bei einer erkannten Palette oder einer '
  'Wägung steht es dort. Zeilen aus der Zeit davor dürfen leer sein; '
  'nachträglich gefüllt würde ein Datum erfunden, das niemand abgelesen hat.';

-- ---------- 2. Welches Kaliber gewaschen wird ----------------------------
alter table auftrag add column if not exists kaliber_idx int;
comment on column auftrag.kaliber_idx is
  'Beim Waschen: welches Kaliberband aus dem Sortierschema der Arbeit gewaschen '
  'wird (Index in kaliber_baender). Trägt ein, wer die Arbeit eröffnet. NULL an '
  'allen anderen Stationen.';
alter table auftrag drop constraint if exists auftrag_kaliber_nur_waschen;
alter table auftrag add constraint auftrag_kaliber_nur_waschen
  check (kaliber_idx is null or station = 'waschen') not valid;

-- Eine Wascharbeit erbt die Fassung, mit der sortiert wurde — sonst zeigte
-- der Kaliber-Index auf die Bänder einer anderen Fassung als der, die die
-- Kisten gefüllt hat.
create or replace function auftrag_schema_setzen()
returns trigger language plpgsql as $$
begin
  if new.sortierschema_id is null and new.station = 'waschen' then
    select l.sortierschema_id into new.sortierschema_id
      from sortier_lauf l
      join auftrag a on a.id = l.auftrag_id
     where l.charge_nr = new.charge_nr and l.sortierschema_id is not null
     order by coalesce(l.datei_zeit, l.gelesen_ts) desc limit 1;
  end if;
  if new.sortierschema_id is null then
    select sortierschema_fuer(c.sorte, new.kaeufer, new.start_ts::date) into new.sortierschema_id
      from charge c where c.nr = new.charge_nr;
  end if;
  return new;
end $$;
revoke execute on function auftrag_schema_setzen() from public;

-- ---------- 3. Die Zählung ------------------------------------------------
create table if not exists auftrag_gebinde (
  id          bigserial primary key,
  auftrag_id  bigint not null references auftrag(id) on delete cascade,
  kaliber_idx int not null check (kaliber_idx >= 0),
  anzahl      int not null default 0 check (anzahl >= 0),
  erfasser    uuid not null default auth.uid() references profil(id),
  ts          timestamptz not null default now(),
  unique (auftrag_id, kaliber_idx)
);
comment on table auftrag_gebinde is
  'Gezählte Kaliber-Kisten je Arbeit und Kaliber. Beim Sortieren die gefüllten, '
  'beim Waschen die geleerten. Was eine Kiste wiegt, steht hier nicht — das '
  'wird aus der CSV gemessen (v_koeff_gebinde).';

alter table auftrag_gebinde enable row level security;
drop policy if exists gebinde_lesen on auftrag_gebinde;
drop policy if exists gebinde_erfassen on auftrag_gebinde;
drop policy if exists gebinde_aendern on auftrag_gebinde;
drop policy if exists gebinde_loeschen on auftrag_gebinde;
create policy gebinde_lesen on auftrag_gebinde for select to authenticated using (true);
create policy gebinde_erfassen on auftrag_gebinde for insert to authenticated
  with check ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
-- Eine Zählung ist eine Zahl, die man hochzählt und korrigiert, keine Messreihe:
-- Der Erfasser darf seine eigene Zahl ändern, solange die Arbeit läuft.
create policy gebinde_aendern on auftrag_gebinde for update to authenticated
  using ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
create policy gebinde_loeschen on auftrag_gebinde for delete to authenticated
  using ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
grant select, insert, update, delete on auftrag_gebinde to authenticated;
grant usage, select on sequence auftrag_gebinde_id_seq to authenticated;

drop trigger if exists auftrag_gebinde_veraltet on auftrag_gebinde;
create trigger auftrag_gebinde_veraltet after insert or update or delete on auftrag_gebinde
  for each statement execute function auswertung_veraltet();

-- ---------- 4. Was eine Kiste wiegt, gemessen ----------------------------
create or replace view v_koeff_gebinde with (security_invoker = true) as
with je_arbeit as (
  -- Nur Sortier-Arbeiten: dort ist beides da, die Masse je Kaliber aus der
  -- CSV und die Zahl der gefüllten Kisten. Am Waschbecken fehlt die Masse —
  -- das ist ja gerade der Grund für die ganze Rechnung.
  select a.id as auftrag_id, c.sorte, g.kaliber_idx, g.anzahl,
         (sum(sg.anzahl::bigint * sg.gewicht_g) / 1000.0)::numeric as kg
    from auftrag_gebinde g
    join auftrag a       on a.id = g.auftrag_id and a.abgebrochen_ts is null
    join charge c        on c.nr = a.charge_nr
    join sortier_lauf l  on l.auftrag_id = a.id
    join sortier_gewicht sg on sg.lauf_id = l.id
                           and sg.klasse = 'kaliber'
                           and sg.kaliber_idx = g.kaliber_idx
   where a.station in ('sortieren', 'waschen_sortieren') and g.anzahl > 0
   group by a.id, c.sorte, g.kaliber_idx, g.anzahl
), s as (
  select sorte, kaliber_idx, count(*)::int as n,
         sum(kg) / nullif(sum(anzahl), 0)   as kg_je_gebinde,
         stddev_samp(kg / anzahl)           as sd
    from je_arbeit group by sorte, kaliber_idx
)
select sorte, kaliber_idx, n,
       kg_je_gebinde::numeric(10,3)                                     as kg_je_gebinde,
       sd::numeric(10,3)                                                as sd,
       (case when sd is null or n < 2 then kg_je_gebinde
             else greatest(kg_je_gebinde - t_quantil_95(n - 1) * sd / sqrt(n), 0)
        end)::numeric(10,3)                                             as unten,
       (case when sd is null or n < 2 then kg_je_gebinde
             else kg_je_gebinde + t_quantil_95(n - 1) * sd / sqrt(n)
        end)::numeric(10,3)                                             as oben
  from s where kg_je_gebinde is not null;

comment on view v_koeff_gebinde is
  'Wie viel eine Kaliber-Kiste wiegt, je Sorte und Kaliber — gemessen am '
  'Sortieren aus CSV-Masse und gezählten Kisten. Ohne Messung steht hier keine '
  'Zeile; die Masse am Waschbecken ist dann unbekannt, nicht null.';
grant select on v_koeff_gebinde to authenticated;

-- Die daraus abgeleitete Masse einer Wascharbeit.
create or replace view v_auftrag_gebinde_masse with (security_invoker = true) as
select a.id as auftrag_id, g.kaliber_idx, g.anzahl,
       (g.anzahl * k.kg_je_gebinde)::numeric(12,2) as kg,
       (g.anzahl * k.unten)::numeric(12,2)         as kg_unten,
       (g.anzahl * k.oben)::numeric(12,2)          as kg_oben,
       k.n                                          as n_messungen
  from auftrag a
  join charge c on c.nr = a.charge_nr
  join auftrag_gebinde g on g.auftrag_id = a.id
  left join v_koeff_gebinde k on k.sorte = c.sorte and k.kaliber_idx = g.kaliber_idx
 where a.station = 'waschen' and a.abgebrochen_ts is null;

comment on view v_auftrag_gebinde_masse is
  'Verarbeitete Menge einer Wascharbeit aus gezählten Kisten mal gemessenem '
  'Kistengewicht. kg ist NULL, solange das Kaliber nie am Sortieren gezählt '
  'wurde — dann fehlt der Nenner weiterhin.';
grant select on v_auftrag_gebinde_masse to authenticated;

-- ---------- 5. Die dritte Massenquelle ------------------------------------
-- mv_auftrag_masse bleibt, wie sie ist (sie hängt nur an Paletten und am
-- eingetippten Durchsatz). Die abgeleitete Kistenmasse kommt eine Ebene
-- darüber dazu, in der Ansicht, die alle weiteren Rechnungen lesen.
create or replace view v_auftrag_masse with (security_invoker = true) as
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten,
       coalesce(m.eingang_netto_kg, gb.kg)::numeric                     as eingang_netto_kg,
       (case when m.masse_quelle <> 'fehlt' then m.masse_quelle
             when gb.kg is not null         then 'gebinde'
             else 'fehlt' end)::text                                    as masse_quelle,
       coalesce(m.lagertage,
         case when m.station = 'waschen'
              then (m.start_ts::date - date '2000-01-01')::numeric
                   - coalesce(se.tage_seit_epoche,
                              (r.eingangsdatum_mittel - date '2000-01-01')::numeric)
              else null end)::numeric(10,1)                             as lagertage
  from mv_auftrag_masse m
  left join mv_sortier_eingang se on se.charge_nr = m.charge_nr
  left join v_charge_rueckgrat r  on r.charge_nr  = m.charge_nr
  left join (select auftrag_id, sum(kg) as kg from v_auftrag_gebinde_masse group by auftrag_id) gb
         on gb.auftrag_id = m.auftrag_id;

comment on view v_auftrag_masse is
  'Masse je Arbeit aus drei Quellen, in dieser Reihenfolge: gewogene Paletten, '
  'eingetippter Durchsatz, gezählte Kisten mal gemessenem Kistengewicht. '
  'masse_quelle sagt, welche es war; fehlt sie ganz, ist eine dort erfasste '
  'Messung ohne Nenner.';

-- ---------- 6. Auffälligkeiten ------------------------------------------
-- Gezählte Kisten ohne Kistengewicht sind kein stiller Nullwert, sondern ein
-- Hinweis mit einer Handlung dahinter: beim Sortieren mitzählen.
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
select 'Nicht ausgewertet', m.auftrag_id, a.charge_nr, c.sorte, m.ts,
       format('%s %s als marge_messung(nebenkanal) erfasst', m.wert, m.einheit),
       'Nebenkanal-Mengen gehören auf Weg 2 unter „zu gross"; auf Weg 1 kommen sie aus der CSV.'
  from marge_messung m
  join auftrag a on a.id = m.auftrag_id
  join charge c on c.nr = a.charge_nr
 where m.art = 'nebenkanal'
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
   and exists (select 1 from auftrag_gebinde g where g.auftrag_id = a.id and g.anzahl > 0);

comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, '
  'die sie gar nicht verwenden kann, weil ihnen der Nenner fehlt. Nicht '
  'ignorieren: fast immer ist etwas nachzutragen oder ein Tippfehler zu '
  'korrigieren.';

grant select on v_plausibilitaet to authenticated;

-- ---------- 7. Die Reihenfolge beim Neurechnen ----------------------------
-- mv_kaliber_verteilung stand bisher am Schluss: Sie war ein Blatt, das
-- niemand weiterlas. Jetzt hängt das Kistengewicht daran und damit die Masse
-- am Waschbecken — also die Punkte des Verderbsmodells und die Kaskade. Sie
-- muss deshalb vor mv_auftrag_masse stehen. Ihre eigenen Quellen sind reine
-- Tabellen (sortier_gewicht, sortier_lauf, sortierschema), sie darf ganz nach
-- vorne.
create or replace function auswertung_aktualisieren()
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v_start timestamptz := clock_timestamp();
begin
  refresh materialized view mv_sortier_lauf_masse;
  refresh materialized view mv_kaliber_verteilung;
  refresh materialized view mv_sortier_eingang;
  refresh materialized view mv_auftrag_masse;
  refresh materialized view mv_schimmel_punkte;
  refresh materialized view mv_schimmel_modell;
  refresh materialized view mv_kaskade;

  update auswertung_stand
     set berechnet_ts = now(),
         dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
   where id = 1;

  return now();
end $$;
