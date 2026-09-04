-- =====================================================================
-- 0049 — Kennzahlen für den Betriebsleiter aus den neuen Erfassungspunkten
--
-- Seit 0041–0047 erfasst die App mehr, als die Auswertung zeigte: das Datum
-- jeder gezählten Palette, Kisten je Kaliber, ob der Ausschuss gewogen oder
-- geschätzt wurde, wie die Kontrollpalette gegriffen wurde, Käufer und
-- Sortierart je Arbeit, Start und Ende. Diese Sichten machen daraus, was
-- der Betriebsleiter wissen will (docs/UI-KONZEPT.md) — ohne das Modell
-- anzufassen. Alles liest Tabellen, die die Masken bereits füllen.
--
-- Regeln wie überall: gerechnet wird aus Beobachtungen; was fehlt, ist NULL,
-- nicht 0; jede Sicht ist billig genug für Supabases 8-Sekunden-Grenze
-- (gemessen in run.sh, Stufe 5 und 6).
-- =====================================================================

-- ---------- 1. Gewichtsverteilung aus der Sortier-CSV ------------------------
-- Vom Betrieb ausdrücklich gewünscht (ABLAUF.md): Balken in wählbarer Breite,
-- die Kalibergrenzen darübergelegt, nach Sorte, Schlag oder Charge. Hier in
-- 25-g-Stufen; gröbere Stufen (50/100 g) fasst die Oberfläche zusammen.
create or replace view v_gewichtsverteilung with (security_invoker = true) as
select c.sorte, c.schlag, l.charge_nr,
       (g.gewicht_g / 25) * 25 as stufe_g,
       sum(g.anzahl)::bigint   as n
  from sortier_gewicht g
  join sortier_lauf l on l.id = g.lauf_id
  join charge c on c.nr = l.charge_nr
  left join auftrag a on a.id = l.auftrag_id
 where a.id is null or a.abgebrochen_ts is null
 group by c.sorte, c.schlag, l.charge_nr, (g.gewicht_g / 25) * 25;
comment on view v_gewichtsverteilung is
  'Kürbisse je 25-g-Stufe aus den Sortier-CSVs, je Charge (mit Sorte und Schlag). '
  'Eine Aussage über den Anbau, nicht über das Lager.';
grant select on v_gewichtsverteilung to authenticated;

-- ---------- 2. Wird das Älteste zuerst verarbeitet? --------------------------
-- Seit AB-11 hat jede gezählte Palette ein Datum. Damit lässt sich je Arbeit
-- sagen, wie alt die verarbeitete Ware war — und wie alt die Charge an dem
-- Tag im Mittel war. Die Differenz sagt, ob älter oder jünger als der
-- Durchschnitt verarbeitet wurde. Das ist die Reihenfolge, die das Modell
-- nicht kennt und die STATISTIK_BEFUND.md als grösste Fehlerquelle nennt.
create or replace view v_verarbeitung_alter with (security_invoker = true) as
with gezaehlt as (
  select ap.auftrag_id, count(*)::int as n_paletten,
         avg(a.start_ts::date - ap.eingangsdatum)::numeric(10,1) as alter_verarbeitet
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
   where ap.eingangsdatum is not null and a.abgebrochen_ts is null
   group by ap.auftrag_id
), charge_am_tag as (
  select a.id as auftrag_id,
         avg(a.start_ts::date - p.eingangsdatum)::numeric(10,1) as alter_charge
    from auftrag a
    join palette p on p.charge_nr = a.charge_nr and p.eingangsdatum <= a.start_ts::date
   where a.abgebrochen_ts is null
   group by a.id
)
select a.id as auftrag_id, a.charge_nr, c.sorte, c.schlag, a.station, a.weg,
       a.start_ts::date as tag, g.n_paletten, g.alter_verarbeitet, l.alter_charge,
       (g.alter_verarbeitet - l.alter_charge)::numeric(10,1) as differenz
  from auftrag a
  join charge c on c.nr = a.charge_nr
  join gezaehlt g on g.auftrag_id = a.id
  left join charge_am_tag l on l.auftrag_id = a.id
 where a.abgebrochen_ts is null and a.station <> 'waschen';
comment on view v_verarbeitung_alter is
  'Je Arbeit mit gezählten, datierten Paletten: mittleres Alter der verarbeiteten '
  'Ware gegen das mittlere Alter aller Paletten der Charge an dem Tag. '
  'differenz > 0: älter als der Durchschnitt verarbeitet.';
grant select on v_verarbeitung_alter to authenticated;

-- ---------- 3. Durchsatz je Arbeit --------------------------------------------
-- Start setzt der Server, Ende der Abschluss (0039). Mit der Masse aus
-- v_auftrag_masse ergibt das Kilo je Stunde — je Station, je Tag. Ohne Masse
-- oder unter einer Viertelstunde bleibt die Rate NULL.
create or replace view v_durchsatz with (security_invoker = true) as
select a.id as auftrag_id, a.charge_nr, m.sorte, a.station, a.weg, a.ist_fax,
       a.start_ts, a.ende_ts,
       (extract(epoch from a.ende_ts - a.start_ts) / 3600)::numeric(10,2) as dauer_h,
       m.eingang_netto_kg as masse_kg, m.masse_quelle, m.n_paletten,
       (case when m.eingang_netto_kg is not null and a.ende_ts - a.start_ts >= interval '15 minutes'
             then m.eingang_netto_kg / (extract(epoch from a.ende_ts - a.start_ts) / 3600) end)::numeric(10,1) as kg_pro_h,
       (select count(*) from auftrag_teilnehmer t where t.auftrag_id = a.id)::int as n_teilnehmer
  from auftrag a
  join v_auftrag_masse m on m.auftrag_id = a.id
 where a.status = 'abgeschlossen' and a.abgebrochen_ts is null and a.ende_ts is not null;
comment on view v_durchsatz is
  'Abgeschlossene Arbeiten mit Dauer, Masse und Kilo je Stunde. kg_pro_h ist NULL, '
  'wenn die Masse unbekannt ist oder die Arbeit kürzer als eine Viertelstunde war.';
grant select on v_durchsatz to authenticated;

-- ---------- 4. Überfüllung je Käufer und Sorte --------------------------------
-- Seit 0043 kennt jede Arbeit ihren Käufer und ihre Sortierart. Die verschenkte
-- Marge lässt sich damit dem zuordnen, der sie bekommt.
create or replace view v_ueberfuellung_kaeufer with (security_invoker = true) as
select coalesce(a.kaeufer, '')                as kaeufer,
       coalesce(k.name, 'ohne Käufer')        as kaeufer_name,
       x.sorte,
       count(*)::int                          as n_wiegungen,
       sum(x.kisten)::int                     as kisten,
       avg(x.kg_pro_kiste)::numeric(10,3)     as kg_pro_kiste,
       avg(x.soll_kg_pro_kiste)::numeric(10,2) as soll_kg_pro_kiste,
       avg(x.ueberfuellung_je_kiste)::numeric(10,3) as ueberfuellung_je_kiste,
       sum(x.ueberfuellung_kg)::numeric(12,1) as ueberfuellung_kg
  from v_ausgang_kennzahl x
  join auftrag a on a.id = x.auftrag_id
  left join kaeufer k on k.code = a.kaeufer
 where x.ueberfuellung_je_kiste is not null and a.abgebrochen_ts is null
 group by coalesce(a.kaeufer, ''), coalesce(k.name, 'ohne Käufer'), x.sorte;
comment on view v_ueberfuellung_kaeufer is
  'Gewogene fertige Paletten je Käufer und Sorte: Kilo je Kiste, Überschuss über '
  'das Soll. Nur Arbeiten nach „Kiste ab x kg" — nach Kaliber gibt es kein Soll.';
grant select on v_ueberfuellung_kaeufer to authenticated;

-- ---------- 5. Datenqualität: wie vollständig wird erfasst? ----------------
-- Eine Zeile mit Zählern; Anteile rechnet die Oberfläche. Jeder Zähler steht
-- für eine Absprache (ABMACHUNGEN.md), deren Einhaltung sich hier ablesen lässt.
create or replace view v_datenqualitaet with (security_invoker = true) as
with arbeiten as (select a.* from auftrag a where a.abgebrochen_ts is null),
     fertig as (select * from arbeiten where status = 'abgeschlossen')
select
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id)::int as paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where ap.eingangsdatum is not null)::int                                             as paletten_mit_datum,
  (select count(*) from fertig)::int                                                      as arbeiten_fertig,
  (select count(*) from fertig f where exists (select 1 from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null))::int                     as arbeiten_mit_ablesung,
  (select count(*) from fertig f where (select count(*) from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null) >= 2)::int                as arbeiten_mit_zwei_ablesungen,
  (select count(*) from fertig f where exists (select 1 from auftrag_angabe g
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
  (select count(*) from fertig f where f.station = 'waschen')::int                        as wasch_arbeiten,
  (select count(*) from fertig f where f.station = 'waschen' and f.kaliber_idx is not null
    and exists (select 1 from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int
                                                                                          as wasch_arbeiten_mit_kisten;
comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung: datierte Paletten, Palox-Ablesungen je '
  'Arbeit, beantwortete Abschlussfragen, gewogener Ausschuss, Lagerkontrollen, '
  'zugeordnete CSVs, gezählte Kisten. Anteile rechnet die Oberfläche.';
grant select on v_datenqualitaet to authenticated;

-- ---------- 6. Eingang und Ausgang über die Saison ----------------------------
-- Woche für Woche, kumuliert. Der Vorlauf (vor dem Erfassungsbeginn
-- ausgeliefert, 0047) ist undatiert und liegt als Sockel unter dem Ausgang.
-- Der Verlust ist hier bewusst nicht dabei — er ist nicht datiert, sondern
-- modelliert; die Differenz der beiden Linien ist „im Haus, ohne Verlust".
create or replace view v_saisonverlauf with (security_invoker = true) as
with ein as (
  select date_trunc('week', p.eingangsdatum)::date as woche, sum(p.netto_kg) as kg
    from v_palette p where p.netto_kg is not null and p.eingangsdatum is not null group by 1
), aus as (
  select date_trunc('week', l.datum)::date as woche, sum(l.masse_kg) as kg
    from v_lieferung_masse l where l.masse_kg is not null group by 1
), grenzen as (
  select least((select min(woche) from ein), (select min(woche) from aus)) as von,
         greatest((select max(woche) from ein), (select max(woche) from aus),
                  date_trunc('week', current_date)::date) as bis
), wochen as (
  select generate_series(g.von, g.bis, interval '1 week')::date as woche from grenzen g where g.von is not null
), vorlauf as (select coalesce(sum(ausgang_vor_app_kg), 0) as kg from charge_vorlauf)
select w.woche,
       coalesce(e.kg, 0)::numeric(12,1) as eingang_kg,
       coalesce(a.kg, 0)::numeric(12,1) as ausgang_kg,
       (sum(coalesce(e.kg, 0)) over (order by w.woche))::numeric(12,1) as eingang_kumuliert_kg,
       (sum(coalesce(a.kg, 0)) over (order by w.woche) + v.kg)::numeric(12,1) as ausgang_kumuliert_kg,
       v.kg::numeric(12,1) as vorlauf_kg
  from wochen w
  cross join vorlauf v
  left join ein e on e.woche = w.woche
  left join aus a on a.woche = w.woche;
comment on view v_saisonverlauf is
  'Wareneingang und Warenausgang je Woche und kumuliert. Der Verlust fehlt bewusst — '
  'er ist modelliert, nicht datiert; die Differenz der Linien ist „im Haus, ohne Verlust".';
grant select on v_saisonverlauf to authenticated;
