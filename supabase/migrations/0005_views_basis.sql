-- =====================================================================
-- 0005 — Auswertung, Teil 1: Rückgrat und Messungen
--
-- Aufbau nach Spec §9: Das *Rückgrat* ist für jede Charge bekannt
-- (Eingangsgewicht, Daten, Sorte, Schlag, Palettenzahl, CSV). Die
-- *Koeffizienten* stammen aus Stichproben. Teil 1 bereitet beides auf,
-- Teil 2 (0006) rechnet hoch.
--
-- Alle Views laufen mit security_invoker → die RLS der Tabellen gilt weiter.
-- =====================================================================

-- ---------- Netto je Palette ---------------------------------------------
-- Netto = Brutto − Kisten·Tara − Paletten-Tara. Fehlt ein Tara-Wert, bleibt
-- das Netto NULL: eine unbekannte Tara als 0 zu behandeln würde die
-- Eingangsmasse systematisch zu hoch ansetzen (Leer ≠ 0, Spec §8).
create view v_palette with (security_invoker = true) as
select p.id, p.charge_nr, p.eingangsdatum, p.brutto_kg, p.kisten, p.gebindeart,
       p.brutto_kg
         - coalesce(p.kisten, 0) * g.tara_kg_pro_kiste
         - coalesce(g.tara_kg_palette, 0) as netto_kg
  from palette p
  left join gebinde g on g.art = p.gebindeart;

-- ---------- Rückgrat je Charge -------------------------------------------
create view v_charge_rueckgrat with (security_invoker = true) as
select c.nr as charge_nr, c.schlag, c.sorte, c.saison,
       count(p.id)                          as n_paletten,
       count(p.netto_kg)                    as n_paletten_mit_netto,
       sum(p.netto_kg)                      as eingang_netto_kg,
       sum(p.brutto_kg)                     as eingang_brutto_kg,
       min(p.eingangsdatum)                 as erster_eingang,
       max(p.eingangsdatum)                 as letzter_eingang,
       -- massegewichtetes mittleres Eingangsdatum: die Charge wird gestaffelt
       -- eingelagert, ein einzelnes Datum wäre irreführend (Spec §1).
       (date '2000-01-01' + (sum((p.eingangsdatum - date '2000-01-01') * coalesce(p.netto_kg, 1))
                             / nullif(sum(coalesce(p.netto_kg, 1)), 0))::int) as eingangsdatum_mittel
  from charge c
  left join v_palette p on p.charge_nr = c.nr
 group by c.nr, c.schlag, c.sorte, c.saison;

comment on view v_charge_rueckgrat is
  'Das für jede Charge sicher Bekannte. Grundlage jeder Hochrechnung.';

-- ---------- Masse hinter einer gezählten Palette --------------------------
-- Der Arbeiter zählt Paletten und notiert optional das Eingangsdatum vom
-- Zettel. Daraus wird die Eingangsmasse geschätzt — mit einer sichtbaren
-- Genauigkeitsstufe, damit im Rechenweg steht, wie gut die Zahl ist.
create view v_auftrag_palette_masse with (security_invoker = true) as
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(p.netto_kg, d.netto_mittel, cm.netto_mittel)              as netto_kg,
       coalesce(p.eingangsdatum, ap.eingangsdatum, cm.eingangsdatum_mittel) as eingangsdatum,
       case when p.netto_kg  is not null then 'palette'
            when d.netto_mittel  is not null then 'datum-mittel'
            when cm.netto_mittel is not null then 'charge-mittel'
            else 'unbekannt' end                                          as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join v_palette p on p.id = ap.palette_id
  left join lateral (
        select avg(x.netto_kg) as netto_mittel
          from v_palette x
         where x.charge_nr = a.charge_nr and x.eingangsdatum = ap.eingangsdatum
       ) d on true
  left join lateral (
        select avg(x.netto_kg) as netto_mittel, r.eingangsdatum_mittel
          from v_palette x, v_charge_rueckgrat r
         where x.charge_nr = a.charge_nr and r.charge_nr = a.charge_nr
         group by r.eingangsdatum_mittel
       ) cm on true;

-- ---------- Auftrag: verarbeitete Masse und Lagerdauer --------------------
create view v_auftrag_masse with (security_invoker = true) as
select a.id as auftrag_id, a.charge_nr, c.sorte, c.schlag, a.weg, a.station,
       a.start_ts, a.ende_ts, a.status,
       count(m.id)                                     as n_paletten,
       -- Eingangs-Äquivalent der verarbeiteten Menge: entweder aus gezählten
       -- Paletten oder — beim Waschen auf Weg 1 — aus dem erfassten Durchsatz.
       coalesce(sum(m.netto_kg), a.durchsatz_kg)        as eingang_netto_kg,
       case when sum(m.netto_kg) is not null then 'paletten'
            when a.durchsatz_kg  is not null then 'durchsatz'
            else 'fehlt' end                            as masse_quelle,
       -- massegewichtete Lagerdauer bis zum Auftragsbeginn
       (sum((a.start_ts::date - m.eingangsdatum) * m.netto_kg)
        / nullif(sum(m.netto_kg), 0))::numeric(10,1)    as lagertage
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_auftrag_palette_masse m on m.auftrag_id = a.id
 group by a.id, a.charge_nr, c.sorte, c.schlag, a.weg, a.station,
          a.start_ts, a.ende_ts, a.status, a.durchsatz_kg;

-- ---------- Sortierlauf: Masse je Klasse ----------------------------------
create view v_sortier_lauf_masse with (security_invoker = true) as
select l.id as lauf_id, l.charge_nr, c.sorte, c.schlag, l.auftrag_id,
       l.datei_name, l.datei_zeit, l.zuordnung,
       sum(g.anzahl)                                                    as n_kuerbis,
       (sum(g.anzahl::bigint * g.gewicht_g) / 1000.0)::numeric(12,2)    as masse_kg,
       sum(g.anzahl) filter (where g.klasse = 'verlust_klein')          as n_klein,
       (sum(g.anzahl::bigint * g.gewicht_g) filter (where g.klasse = 'verlust_klein')
        / 1000.0)::numeric(12,2)                                        as masse_klein_kg,
       sum(g.anzahl) filter (where g.klasse = 'nebenkanal')             as n_nebenkanal,
       (sum(g.anzahl::bigint * g.gewicht_g) filter (where g.klasse = 'nebenkanal')
        / 1000.0)::numeric(12,2)                                        as masse_nebenkanal_kg,
       sum(g.anzahl) filter (where g.klasse = 'kaliber')                as n_kaliber,
       (sum(g.anzahl::bigint * g.gewicht_g) filter (where g.klasse = 'kaliber')
        / 1000.0)::numeric(12,2)                                        as masse_kaliber_kg
  from sortier_lauf l
  join charge c on c.nr = l.charge_nr
  join sortier_gewicht g on g.lauf_id = l.id
 group by l.id, l.charge_nr, c.sorte, c.schlag, l.auftrag_id, l.datei_name, l.datei_zeit, l.zuordnung;

-- Verteilung je Kaliber-Band — für „engeres Band liefern" (Spec §3, Weg 1).
create view v_kaliber_verteilung with (security_invoker = true) as
select l.charge_nr, c.sorte, g.klasse, g.kaliber_idx,
       (s.kaliber_baender -> g.kaliber_idx ->> 0)::int as band_von,
       (s.kaliber_baender -> g.kaliber_idx ->> 1)::int as band_bis,
       sum(g.anzahl)                                                 as n_kuerbis,
       (sum(g.anzahl::bigint * g.gewicht_g) / 1000.0)::numeric(12,2) as masse_kg
  from sortier_gewicht g
  join sortier_lauf l on l.id = g.lauf_id
  join charge c on c.nr = l.charge_nr
  join sorte_kaliber s on s.sorte = c.sorte
 group by l.charge_nr, c.sorte, g.klasse, g.kaliber_idx, s.kaliber_baender;

-- Eine Zeile je Kürbis, aus dem Histogramm zurückgewonnen. Gespeichert wird
-- lauflängenkodiert (siehe Kommentar an sortier_gewicht); wer doch einmal pro
-- Kürbis rechnen will — Quantile, Verteilungsplots — nimmt diese View.
create view v_sortier_kuerbis with (security_invoker = true) as
select g.lauf_id, l.charge_nr, c.sorte, g.gewicht_g, g.klasse, g.kaliber_idx
  from sortier_gewicht g
  join sortier_lauf l on l.id = g.lauf_id
  join charge c on c.nr = l.charge_nr
  cross join generate_series(1, g.anzahl);
