-- =====================================================================
-- 0073 — Der Palox je Arbeit, das Alter als ausgewiesene Schätzung,
--        und die Kontrollpalette rechnet
--
-- 0072 hat das Schema gelegt. Hier rechnet es.
--
-- 1. v_palox_stand fenstert über den AUFTRAG statt über die Station.
-- 2. v_schimmel_menge verlangt zwei Ablesungen und lässt Arbeiten mit
--    geleertem Palox heraus — unbekannt, nicht null.
-- 3. v_auftrag_masse sagt, WOHER das Alter kommt und wie unsicher es ist.
-- 4. v_kontrollpalette_rate: eine Rate je Zeitraum zwischen zwei Wägungen.
-- =====================================================================
set client_min_messages = warning;

-- =====================================================================
-- 1. Der Palox: jede Arbeit liest ihren eigenen Anfang und ihr Ende
-- =====================================================================
-- Vorher: `partition by palox_station(a.station)`. Damit griff lag() in
-- die vorherige Arbeit, und die erste Ablesung einer Arbeit war eine
-- Differenz zu etwas Unbekanntem. Genau daraus entstand die gemeldete
-- „−445": letzte Ablesung einer früheren Arbeit 490, der Arbeiter liest
-- die leere Box mit 45 ab.
--
-- Nachher: `partition by s.auftrag_id`. Die erste Ablesung einer Arbeit
-- ist der **Nullpunkt** (differenz 0), nicht `stand − tara`. Die Tara
-- kürzt sich in der Differenz von selbst heraus und kommt hier nicht mehr
-- vor — wo sie abgezogen würde, wäre die Zahl eine Folgerung und keine
-- Beobachtung.
create or replace view v_palox_stand with (security_invoker = true) as
select s.id, s.auftrag_id, s.ts, s.palox_stand_kg, s.kg,
       lag(s.palox_stand_kg) over w                                as vorher,
       case
         -- Der Startstand dieser Arbeit: Nullpunkt, keine Menge.
         when lag(s.palox_stand_kg) over w is null                  then 0
         -- Zwischendurch geleert: wie viel dabei herausging, weiss
         -- niemand. Unbekannt ist nicht null (0064).
         when s.palox_geleert                                       then null
         when s.palox_stand_kg < lag(s.palox_stand_kg) over w       then null
         else s.palox_stand_kg - lag(s.palox_stand_kg) over w
       end                                                          as differenz,
       (s.palox_geleert
        or (lag(s.palox_stand_kg) over w is not null
            and s.palox_stand_kg < lag(s.palox_stand_kg) over w))   as zwischendurch_geleert,
       palox_station(a.station)                                     as station
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
 where s.palox_stand_kg is not null and s.gemessen
window w as (partition by s.auftrag_id order by s.ts, s.id)
 order by s.auftrag_id, s.ts, s.id;

comment on view v_palox_stand is
  'Die Palox-Ablesungen mit der Differenz zur vorigen Ablesung DERSELBEN '
  'Arbeit. Arbeitsschritte werden nie über Nacht pausiert; zwischen zwei '
  'Arbeiten liegt unbekannt viel, deshalb darf kein Stand über die '
  'Arbeitsgrenze hinweg verrechnet werden (0073). Die erste Ablesung ist der '
  'Nullpunkt, nicht eine Menge. Die Tara kommt nicht vor — sie kürzt sich in '
  'der Differenz weg.';

-- =====================================================================
-- 2. Eine einzige Ablesung ist ein Startstand, kein Messwert
-- =====================================================================
-- Wer nur einmal abliest, hat den Palox nicht gemessen — er hat gesagt,
-- wo er anfing. Die Menge der Arbeit ist dann unbekannt. Vorher kam dabei
-- `sum(differenz) = 0` heraus, also eine behauptete Null.
--
-- Dasselbe bei `palox_unbekannt`: der Palox wurde während der Arbeit
-- geleert, wie viel dabei herausging, weiss niemand.
create or replace view v_schimmel_menge with (security_invoker = true) as
select s.auftrag_id,
       sum(case when s.palox_stand_kg is null then s.kg else p.differenz end)::numeric as kg,
       count(*)::int as n_ablesungen
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
  left join v_palox_stand p on p.id = s.id
 where s.gemessen and not a.palox_unbekannt
 group by s.auftrag_id
having bool_and(s.palox_stand_kg is null or p.differenz is not null)
   and (count(*) filter (where s.palox_stand_kg is not null) = 0
     or count(*) filter (where s.palox_stand_kg is not null) >= 2);

comment on view v_schimmel_menge is
  'Wie viel Faules eine Arbeit ergeben hat. Aus Palox-Ablesungen die Summe der '
  'Differenzen innerhalb der Arbeit (S₂ − S₁), aus gewogenen Kisten die Summe '
  'der Kilo. Keine Zeile, wenn nur einmal abgelesen wurde (das ist ein '
  'Startstand, kein Messwert), wenn eine Differenz unbekannt ist, oder wenn '
  'der Palox während der Arbeit geleert wurde (0073). Unbekannt ist nicht null.';

-- =====================================================================
-- 3. Wie weit die Erntedaten einer Charge streuen
-- =====================================================================
-- Das Alter beim Waschen ist das massegewichtete mittlere Eingangsdatum
-- der Charge. Der Betrieb hat den Grund genannt: „auf dem palette mit
-- sortieren kisten - kommen ja mehrere eingangsdaten zusammen … dann gibt
-- es nur noch - sortierdatum und kalibergrösse und chargennummer".
--
-- Diese Zahl ist eine Schätzung, und ihre Unsicherheit ist genau die
-- Streuung der Eingangsdaten innerhalb der Charge. Die rechnet die App
-- sich selbst aus — dafür braucht es kein Erntejournal von Hand.
create or replace view v_charge_erntespanne with (security_invoker = true) as
select p.charge_nr,
       count(*)::int                                                   as n_paletten,
       min(p.eingangsdatum)                                            as erster_tag,
       max(p.eingangsdatum)                                            as letzter_tag,
       (max(p.eingangsdatum) - min(p.eingangsdatum))::int               as spanne_tage,
       zahl(sqrt(nullif(
         sum(n.netto_kg * power((p.eingangsdatum - r.eingangsdatum_mittel)::numeric, 2))
         / nullif(sum(n.netto_kg), 0), 0)), 1, 100000)::numeric(6,1)   as streuung_tage,
       c.ernte_abgeschlossen_ts is not null
         or coalesce((select (wert #>> '{}')::boolean from einstellung
                       where schluessel = 'ernte_abgeschlossen'), false) as ernte_fertig
  from palette p
  join charge c on c.nr = p.charge_nr
  join v_charge_rueckgrat r on r.charge_nr = p.charge_nr
  cross join lateral (select netto_kg from v_palette v where v.id = p.id) n
 where n.netto_kg is not null
 group by p.charge_nr, c.ernte_abgeschlossen_ts, r.eingangsdatum_mittel;

comment on view v_charge_erntespanne is
  'Über wie viele Tage sich die Ernte einer Charge zieht und wie stark die '
  'Masse darüber streut (massegewichtete Standardabweichung in Tagen). Das ist '
  'die Unsicherheit jeder Altersangabe, die über das Chargenmittel läuft. '
  'Solange die Ernte läuft, wandert der Mittelwert mit jedem Import — '
  'ernte_fertig sagt, ob er steht (0073).';

-- =====================================================================
-- 4. Das Alter sagt, woher es kommt
-- =====================================================================
-- Zwei neue Spalten am Ende, damit `create or replace` die acht Sichten
-- darüber nicht anfasst. Keine bestehende Zahl ändert sich — es kommt nur
-- dazu, was man ihr bisher nicht ansah.
--
--   'gemessen'      Sortieren und Waschen + Sortieren: der Arbeiter liest
--                   das Eingangsdatum von jedem Zettel ab. Massegewichtet
--                   über die Paletten DIESER Arbeit.
--   'sortiermittel' Waschen: das mittlere Eingangsdatum der dokumentierten
--                   Sortierarbeiten dieser Charge — genauer als das
--                   Chargenmittel, aber nur so vollständig wie die
--                   Dokumentation.
--   'chargenmittel' Waschen ohne dokumentierte Sortierarbeit: das
--                   massegewichtete mittlere Eingangsdatum der Charge.
create or replace view v_auftrag_masse with (security_invoker = true) as
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten,
       coalesce(m.eingang_netto_kg, wp.kg, gb.kg, fp.kg) as eingang_netto_kg,
       case when m.masse_quelle <> 'fehlt' then m.masse_quelle
            when wp.kg is not null then 'wasch_paletten'
            when gb.kg is not null then 'gebinde'
            when fp.kg is not null then 'fax_paletten'
            else 'fehlt' end as masse_quelle,
       zahl(coalesce(m.lagertage,
         case when m.station = 'waschen'
              then (betriebstag(m.start_ts) - date '2000-01-01')::numeric
                   - coalesce(se.tage_seit_epoche, (r.eingangsdatum_mittel - date '2000-01-01')::numeric)
              else null end), 1, 1000000000)::numeric(10,1) as lagertage,
       a.ist_fax,
       wp.zwischenlager_tage,
       -- ---- neu in 0073 -------------------------------------------
       case
         when m.lagertage is not null                then 'gemessen'
         when m.station <> 'waschen'                 then null
         when se.tage_seit_epoche is not null        then 'sortiermittel'
         when r.eingangsdatum_mittel is not null     then 'chargenmittel'
         else null
       end as alter_quelle,
       case when m.lagertage is not null then null else es.streuung_tage end as alter_spanne_tage,
       coalesce(es.ernte_fertig, false) as ernte_fertig
  from mv_auftrag_masse m
  join auftrag a on a.id = m.auftrag_id
  left join mv_sortier_eingang se on se.charge_nr = m.charge_nr
  left join v_charge_rueckgrat r on r.charge_nr = m.charge_nr
  left join v_charge_erntespanne es on es.charge_nr = m.charge_nr
  left join v_auftrag_wasch_paletten wp on wp.auftrag_id = m.auftrag_id
  left join (select auftrag_id, sum(kg) as kg from v_auftrag_gebinde_masse group by auftrag_id) gb
         on gb.auftrag_id = m.auftrag_id
  left join lateral (
        select zahl(a.paletten_gesamt::numeric * p.netto_kg, 2, 10000000000)::numeric(12,2) as kg
          from v_koeff_palette_netto p
         where a.ist_fax and a.paletten_gesamt > 0 and p.sorte = m.sorte
           and (p.kistensystem = a.kistensystem
                or p.kistensystem is null and a.kistensystem is distinct from 'anderes')
         order by (p.kistensystem = a.kistensystem) desc nulls last
         limit 1) fp on true;

comment on view v_auftrag_masse is
  'Masse und Alter je Arbeit. alter_quelle sagt, ob das Alter gemessen ist '
  '(Eingangsdatum je Zettel abgelesen — Sortieren und Waschen + Sortieren) '
  'oder geschätzt (Waschen: die Kaliber-Palette hat kein eigenes '
  'Eingangsdatum). alter_spanne_tage ist die Streuung der Erntedaten der '
  'Charge, also die Unsicherheit der Schätzung. Eine geschätzte Zahl darf auf '
  'dem Bildschirm nicht aussehen wie eine gemessene (0073).';

-- =====================================================================
-- 5. Die Kontrollpalette rechnet
-- =====================================================================
-- Je zwei aufeinanderfolgende Wägungen derselben Palette eine Rate FÜR
-- DEN ZEITRAUM DAZWISCHEN. Das beantwortet die Frage, die heute niemand
-- beantworten kann: ob die Verdunstungsrate über die Saison konstant ist.
-- Der Betrieb vermutet nein — „am anfang haben sie sicher schock von
-- draussen feld in halle zu kommen". Diese Sicht misst es, statt zu raten.
--
-- Sie wird in dieser Runde NICHT in die Kaskade eingebaut. Erst erheben,
-- dann entscheiden.
create or replace view v_kontrollpalette_rate with (security_invoker = true) as
with w as (
  select k.id as kontrollpalette_id, k.charge_nr, c.sorte, k.kennzeichen,
         wg.wiege_ts, wg.sichtbar_schimmel,
         case when g.tara_kg_pro_kiste is null or g.tara_kg_palette is null then null
              else wg.brutto_kg - wg.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette end as netto_kg
    from kontrollpalette_wiegung wg
    join kontrollpalette k on k.id = wg.kontrollpalette_id
    join charge c on c.nr = k.charge_nr
    left join gebinde g on g.art = wg.gebindeart
),
paar as (
  select w.*,
         lag(wiege_ts)          over p as von_ts,
         lag(netto_kg)          over p as netto_von_kg,
         lag(sichtbar_schimmel) over p as schimmel_von
    from w
  window p as (partition by kontrollpalette_id order by wiege_ts, netto_kg)
)
select kontrollpalette_id, charge_nr, sorte, kennzeichen,
       von_ts, wiege_ts as bis_ts,
       (betriebstag(wiege_ts) - betriebstag(von_ts))::int as tage,
       netto_von_kg, netto_kg as netto_bis_kg,
       case when netto_von_kg > 0 and netto_kg > 0
             and betriebstag(wiege_ts) > betriebstag(von_ts)
            then zahl(1 - power(netto_kg / netto_von_kg,
                                1.0 / (betriebstag(wiege_ts) - betriebstag(von_ts))::numeric),
                      6, 1)::numeric(9,6)
       end as rate_je_tag,
       -- Brauchbar nur, wenn nichts dazwischenkommt: kein sichtbarer
       -- Schimmel (dann ist der Verlust kein Wasser), mindestens eine
       -- Woche Abstand (sonst rauscht die Waage lauter als die
       -- Verdunstung), und die Palette darf nicht schwerer geworden sein.
       (netto_von_kg is not null and netto_kg is not null
        and not coalesce(schimmel_von, false) and not sichtbar_schimmel
        and (betriebstag(wiege_ts) - betriebstag(von_ts)) >= 7
        and netto_kg <= netto_von_kg) as verwendbar
  from paar
 where von_ts is not null;

comment on view v_kontrollpalette_rate is
  'Je zwei aufeinanderfolgende Wägungen einer Kontrollpalette eine '
  'Verdunstungsrate für den Zeitraum DAZWISCHEN — nicht für die ganze Saison. '
  'Fällt die erste Rate deutlich höher aus als die späteren, ist der vermutete '
  'Schock beim Einlagern gemessen statt vermutet (0073). Wird in dieser Runde '
  'nur erhoben und angezeigt, nicht in die Kaskade eingebaut.';

grant select on v_charge_erntespanne, v_kontrollpalette_rate to authenticated;

-- =====================================================================
-- 6. Welche Chargen sich als Kontrollpalette lohnen
-- =====================================================================
-- Der Betrieb: „definiere 5 chargen … die ertragswichtigsten". Statt sie
-- von Hand aus einem Journal herauszusuchen, rechnet die App den
-- Vorschlag aus den Eingangsdaten — und hält ihn aktuell.
create or replace view v_kontrollpalette_vorschlag with (security_invoker = true) as
select r.charge_nr, c.sorte, c.schlag, r.eingang_netto_kg,
       rank() over (order by r.eingang_netto_kg desc nulls last) as rang,
       exists (select 1 from kontrollpalette k
                where k.charge_nr = r.charge_nr and k.beendet_ts is null) as hat_schon
  from v_charge_rueckgrat r
  join charge c on c.nr = r.charge_nr
 where r.eingang_netto_kg > 0;

comment on view v_kontrollpalette_vorschlag is
  'Die Chargen nach Eingangsmasse geordnet, mit der Angabe, ob schon eine '
  'Kontrollpalette darauf steht. Die fünf obersten sind der Vorschlag (0073).';
grant select on v_kontrollpalette_vorschlag to authenticated;

-- =====================================================================
-- 7. v_datenqualitaet neu anlegen — wegen `select a.*`
-- =====================================================================
-- Die Sicht beginnt mit `with arbeiten as (select a.* from auftrag a …)`.
-- Postgres friert den Stern beim Anlegen ein: die Spaltenliste steht fest,
-- wie sie damals war. 0072 hat `auftrag` zwei Spalten gegeben — damit
-- ergibt der Weg über die Migrationen eine andere Sicht als der Weg über
-- setup.sql (Teil B legt alles frisch an, also mit den neuen Spalten).
-- Der Fingerabdruck-Vergleich in supabase/test/run.sh hat genau das
-- gefunden. Ein Neuanlegen bringt beide Wege wieder zusammen.
--
-- Der Rumpf ist unverändert der aus 0061 — hier steht er nur noch einmal,
-- damit der Stern neu ausgerechnet wird. `create or replace` statt
-- `drop … cascade`: die Spaltenliste der Sicht selbst ändert sich nicht,
-- also bleibt die gespeicherte Fassung erg_datenqualitaet stehen. In
-- setup.sql kostet das nichts — Teil B behält ohnehin nur die letzte
-- Fassung jeder Sicht.
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
  -- 0061: die Lagerkontrolle ist eine Verdunstungsmessung — gezählt wird jede
  -- gemessene Kontrolle, nicht nur die mit Faul-Angabe
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.gemessen)::int                                       as lagerkontrollen,
  (select count(*) from sortier_lauf)::int                                                as sortierlaeufe,
  (select count(*) from sortier_lauf where auftrag_id is not null)::int                   as sortierlaeufe_zugeordnet,
  (select count(*) from fertig f where f.station = 'sortieren')::int                      as sortier_arbeiten,
  (select count(*) from fertig f where f.station = 'sortieren' and exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int              as sortier_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax)::int      as wasch_arbeiten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax
    and (f.kaliber_idx is not null or f.kaliber_von_g is not null)
    and (exists (select 1 from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)
         or exists (select 1 from auftrag_palette p where p.auftrag_id = f.id and p.kisten > 0)))::int
                                                                                          as wasch_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax)::int                                    as fax_arbeiten,
  (select count(*) from fertig f where f.ist_fax and (f.paletten_gesamt > 0 or exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)))::int             as fax_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax and exists (select 1
    from schimmel_messung s where s.auftrag_id = f.id and s.gemessen))::int               as fax_arbeiten_mit_faulem,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren')::int                                           as ws_paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren' and ap.brutto_zettel_kg is not null)::int       as ws_paletten_mit_zettelgewicht,
  (select count(*) from fertig f where f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))::int
                                                                                          as arbeiten_nach_waschen,
  (select count(*) from fertig f where (f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))
    and f.kistensystem is not null)::int                                                  as arbeiten_mit_kistensystem,
  ((select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
     where a.station = 'waschen' and not a.ist_fax)
   + (select coalesce(sum(p.kisten), 0) from auftrag_palette p join arbeiten a on a.id = p.auftrag_id
       where a.station = 'waschen' and not a.ist_fax))::int                               as wasch_kisten_gezaehlt,
  ((select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
     where a.station = 'waschen' and not a.ist_fax and (g.sortierdatum is not null or g.datum_fehlt))
   + (select coalesce(sum(p.kisten), 0) from auftrag_palette p join arbeiten a on a.id = p.auftrag_id
       where a.station = 'waschen' and not a.ist_fax and p.sortierdatum is not null))::int
                                                                                          as wasch_kisten_mit_sortierdatum,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from v_palox_stand p
    where p.auftrag_id = f.id and p.differenz is null))::int                              as arbeiten_mit_palox_unbekannt;

comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung. Seit 0061 zählen beim Waschen die '
  'gezählten Paletten (Kisten mit Sortierdatum) mit; die Lagerkontrolle zählt '
  'als Verdunstungsmessung, ohne Faul-Angabe. Seit 0073 neu angelegt, weil '
  '`select a.*` die Spaltenliste einfriert (0072 gab auftrag zwei Spalten).';

-- =====================================================================
-- 8. Der Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 73 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
