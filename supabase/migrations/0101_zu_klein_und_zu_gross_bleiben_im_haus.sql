-- =====================================================================
-- 0101 — Zu klein und zu gross bleiben im Haus
--
-- Der Betrieb, am ersten Tag mit der ganzen Saison im Lagermanagement:
-- „15,2 Tonnen anderer Kanal — wie kommst du auf diese Zahl? … die stehen
-- dann schon noch im Lager, die sind dann einfach nicht mehr verkaufsfähig
-- … rechne die noch nicht zum Verkauf, sondern wirklich nur die, die du mit
-- Lieferschein hast."
--
-- Er hat recht. Die Kaskade rechnet aus jeder Lieferung die Eingangsmasse
-- dahinter zurück, und zu dieser Masse gehört ein Anteil, der beim Sortieren
-- als zu klein oder zu gross herausfiel. Bis 0100 stand dieser Anteil als
-- „anderer Kanal am Ausgelagerten" neben dem Ausgang — als hätte er den
-- Betrieb verlassen. Verlassen hat ihn nur, was auf einem Lieferschein
-- steht; alle 587 Lieferungen des Betriebs sind Verkauf, das Buch „marge"
-- (an die Tiere, in den Nebenkanal) ist leer. Die 15,2 t stehen also in
-- Paloxen im Haus, nicht verkaufsfähig, bis ein Lieferschein sie holt.
--
-- Darum, ohne die Kaskade selbst anzufassen (ihre Ströme stimmen, nur die
-- Zuordnung war falsch):
--   · erg_charge.im_haus_heute_kg = Liegendes nach Verdunstung und Verderb
--     + hinter den Lieferungen Aussortiertes. kanal_ausgelagert_kg bleibt
--     als Spalte und heisst jetzt: aussortiert, im Haus.
--   · Die Saisonbilanz: Eingang + Überzählung = ausgeliefert + Verlust
--     + im Haus. Kein Term „anderer Kanal" mehr; der Befund nennt die
--     Tonnen zu klein/zu gross im Haus.
--   · erg_verlauf: im_haus_kg je Woche dazu, neue Spalte aussortiert_kg —
--     auf heute dieselbe Zahl wie die Bilanz (Prüfblock 0049 hält das).
--   · v_prognose: „vollständig" ohne den Sockel — wie erg_charge seit 0097.
--     Das Lagermanagement sagte „Anteil unbekannt, solange eine Rate nicht
--     gemessen ist", weil der Sockel-Nachweis fehlte, den 0097 längst nicht
--     mehr verlangt; und der Betrieb fragte zu Recht: „welche Rate?"
-- Der Ausgang war schon immer nur der Lieferschein (geliefert_kg); die
-- Lagermanagement-Seite hängt jetzt nichts mehr daran.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Je Charge: im Haus = Liegendes + Aussortiertes
-- ---------------------------------------------------------------------
create or replace view v_hochrechnung_basis with (security_invoker = true) as
with je_charge as (
  select charge_nr,
         sum(m0) filter (where portion = 'ausgelagert')                       as ausgelagert_kg,
         sum(m0 * alter_tage) filter (where portion = 'ausgelagert')
           / nullif(sum(m0) filter (where portion = 'ausgelagert'), 0)        as alter_ausgelagert,
         sum(m0) filter (where portion = 'lager')                             as lager_kg,
         sum(m0 * alter_tage) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as alter_lager,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager')              as verkaufsfaehig_lager_kg,
         sum(geliefert_kg)                                                    as geliefert_kg,
         sum(ueberzaehlung_kg)                                                as ueberzaehlung_kg,
         sum(n_lieferungen)::int                                              as n_lieferungen,
         min(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_von,
         max(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_bis,
         count(*) filter (where portion = 'lager' and m0 > 0)::int            as n_rest_kohorten,
         sum(m0 * (kohorte - date '2000-01-01')) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as rest_tage_seit_epoche,
         -- 0064: jede Stromsumme nur, wenn ihr Koeffizient gemessen ist.
         -- Das `coalesce` innerhalb der Bedingung trennt zwei Sorten NULL:
         -- „der Koeffizient ist unbekannt" (dann bleibt die ganze Summe NULL)
         -- von „diese Portion gibt es nicht" — eine Charge ohne Lieferung hat
         -- keine Zeile mit portion = 'ausgelagert', und dort ist 0 richtig.
         case when bool_and(r_bekannt)  then coalesce(sum(verdunstung_kg), 0) end as verdunstung_heute_kg,
         case when bool_and(f_bekannt)  then coalesce(sum(schimmel_kg), 0)    end as schimmel_heute_kg,
         -- 0097: Der Sockel a₀ ist der Anteil, der schon am ersten Tag faul
         -- war — er gilt nur, wenn die Daten ihn belegen (sockel_nachweis).
         -- Solange sie es nicht tun, ist er 0, nicht unbekannt: mv_kaskade
         -- rechnet ihn dann mit 0. Bis 0096 hing hier a0_bekannt, und weil
         -- das Verderbsmodell mit zwölf Punkten noch nicht brauchbar war,
         -- stand am ersten Tag mit echten Zahlen überall „Verlust bis heute —".
         case when bool_and(f_bekannt)  then coalesce(sum(sockel_kg), 0)      end as sockel_heute_kg,
         -- 0101: umgedeutet — zu klein und zu gross, das hinter den Lieferungen
         -- aussortiert wurde und im Haus steht (Teil von im_haus_heute_kg).
         -- Der Name bleibt: Spalten werden nie weggenommen.
         case when bool_and(a_klein_bekannt and a_gross_bekannt)
              then coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'ausgelagert'), 0)
              end                                                             as kanal_ausgelagert_kg,
         case when bool_and(a_fax_bekannt)
              then coalesce(sum(fax_kg) filter (where portion = 'ausgelagert'), 0) end as fax_heute_kg,
         case when bool_and(a_fax_bekannt)
              then coalesce(sum(fax_kg) filter (where portion = 'lager'), 0) end       as fax_erwartet_kg,
         -- 0101: Zu klein und zu gross, das hinter den Lieferungen aussortiert
         -- wurde, hat den Betrieb nicht verlassen — es steht im Haus, bis ein
         -- Lieferschein es holt (der Betrieb: „die stehen dann schon noch im
         -- Lager … rechne die noch nicht zum Verkauf"). Darum zählt es zu „im
         -- Haus": nicht verkaufsfähig, aber da. Bis 0100 stand es als „anderer
         -- Kanal am Ausgelagerten" neben dem Ausgang, als wäre es weg.
         -- Die Summe ist die Zahl der Kaskade: Ist die Rate nicht gemessen,
         -- rechnet sie dort 0 (kanal_bekannt sagt es; kanal_ausgelagert_kg
         -- bleibt leer). Ohne liegende Portion ist das Liegende 0, nicht leer —
         -- sonst verschwände das Aussortierte mit ihm.
         coalesce(sum(m2) filter (where portion = 'lager'), 0)
           + coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'ausgelagert'), 0)
                                                                              as im_haus_heute_kg,
         case when bool_and(a_klein_bekannt and a_gross_bekannt)
              then coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'lager'), 0)
              end                                                             as kanal_im_haus_kg,
         bool_and(r_bekannt and f_bekannt and a_fax_bekannt
                  and a_klein_bekannt and a_gross_bekannt)                     as verlust_bekannt,
         bool_and(r_bekannt)                                                   as verdunstung_bekannt,
         bool_and(f_bekannt)                                                   as schimmel_bekannt,
         bool_and(a0_bekannt)                                                  as sockel_nachgewiesen,
         bool_and(a_fax_bekannt)                                               as fax_bekannt,
         bool_and(a_klein_bekannt and a_gross_bekannt)                         as kanal_bekannt,
         max(a0_var)                                                           as a0_var,
         -- 0064: gab es zu dieser Charge überhaupt eine Kaskadenzeile?
         count(*) > 0                                                          as gerechnet,
         count(*) filter (where portion = 'lager') > 0                         as hat_lager
    from mv_kaskade
   group by charge_nr
)
select b.charge_nr, b.schlag, b.sorte,
       b.eingang_kg,
       b.n_paletten,
       b.eingangsdatum_mittel,
       zahl(coalesce(k.ausgelagert_kg, 0), 2, 1e12)::numeric(14,2)             as ausgelagert_kg,
       zahl(k.alter_ausgelagert, 1, 1e5)::numeric(8,1)                         as alter_ausgelagert,
       -- 0064: keine Kaskadenzeile → es liegt noch alles. Zeilen, aber keine
       -- Portion „lager" → es liegt nichts mehr. Bisher hiess beides „alles".
       zahl(case when k.gerechnet is not true then b.eingang_kg
                 else coalesce(k.lager_kg, 0) end, 2, 1e12)::numeric(14,2)     as lager_kg,
       zahl(coalesce(k.alter_lager, (b.stichtag - b.eingangsdatum_mittel)), 1, 1e5)::numeric(8,1)
                                                                              as alter_lager,
       zahl((heute() - x.rest_datum), 1, 1e5)::numeric(8,1)                    as alter_lager_heute,
       b.weg2_anteil,
       b.stichtag,
       b.n_paletten_mit_netto,
       zahl(coalesce(k.ueberzaehlung_kg, 0), 2, 1e12)::numeric(14,2)           as ueberzaehlung_kg,
       b.sortiert_kg, b.gewaschen_kg, b.wartet_kg, b.anteil_gewaschen, b.alter_band, b.am_band_kg,
       x.rest_datum                                                           as eingangsdatum_rest,
       (coalesce(k.n_lieferungen, 0) > 0)                                     as rest_alter_aus_zaehlung,
       b.eingang_von, b.eingang_bis, b.n_eingangstage,
       coalesce(k.rest_von, b.eingang_von)                                    as rest_von,
       coalesce(k.rest_bis, b.eingang_bis)                                    as rest_bis,
       round(case when k.gerechnet is not true then b.eingang_kg else coalesce(k.lager_kg, 0) end
             / nullif(b.eingang_kg / nullif(b.n_paletten, 0), 0))::int        as n_rest_paletten,
       coalesce(k.n_rest_kohorten, b.n_eingangstage)                          as n_rest_kohorten,
       (heute() - coalesce(k.rest_bis, b.eingang_bis))::int                   as alter_lager_von,
       (heute() - coalesce(k.rest_von, b.eingang_von))::int                   as alter_lager_bis,
       zahl(coalesce(k.geliefert_kg, 0), 2, 1e12)::numeric(14,2)              as geliefert_kg,
       zahl(k.verkaufsfaehig_lager_kg, 2, 1e12)::numeric(14,2)                 as verkaufsfaehig_lager_kg,
       coalesce(k.n_lieferungen, 0)                                           as n_lieferungen,
       zahl(k.verdunstung_heute_kg, 2, 1e12)::numeric(14,2)                   as verdunstung_heute_kg,
       zahl(k.schimmel_heute_kg, 2, 1e12)::numeric(14,2)                      as schimmel_heute_kg,
       zahl(k.sockel_heute_kg, 2, 1e12)::numeric(14,2)                        as sockel_heute_kg,
       zahl(k.fax_heute_kg, 2, 1e12)::numeric(14,2)                           as fax_heute_kg,
       -- Der Verlust ist die Summe von vier Strömen. Fehlt einer, ist die
       -- Summe unbekannt — nicht die Summe der übrigen.
       zahl(k.verdunstung_heute_kg + k.schimmel_heute_kg + k.sockel_heute_kg + k.fax_heute_kg,
            2, 1e12)::numeric(14,2)                                           as verlust_heute_kg,
       zahl(k.kanal_ausgelagert_kg, 2, 1e12)::numeric(14,2)                   as kanal_ausgelagert_kg,
       zahl(k.fax_erwartet_kg, 2, 1e12)::numeric(14,2)                        as fax_erwartet_kg,
       zahl(case when k.gerechnet is not true then b.eingang_kg
                 else coalesce(k.im_haus_heute_kg, 0) end, 2, 1e12)::numeric(14,2) as im_haus_heute_kg,
       zahl(k.kanal_im_haus_kg, 2, 1e12)::numeric(14,2)                       as kanal_im_haus_kg,
       coalesce(k.verlust_bekannt, false)                                     as verlust_bekannt,
       coalesce(k.verdunstung_bekannt, false)                                 as verdunstung_bekannt,
       coalesce(k.schimmel_bekannt, false)                                    as schimmel_bekannt,
       coalesce(k.sockel_nachgewiesen, false)                                 as sockel_nachgewiesen,
       coalesce(k.fax_bekannt, false)                                         as fax_bekannt,
       coalesce(k.kanal_bekannt, false)                                       as kanal_bekannt,
       zahl(coalesce(k.lager_kg, 0) * 1.96 * sqrt(greatest(coalesce(k.a0_var, 0), 0)), 2, 1e12)::numeric(14,2)
                                                                              as sockel_oben_kg,
       heute()                                                                as heute
  from v_kaskade_basis b
  left join je_charge k on k.charge_nr = b.charge_nr
  cross join lateral (
    select case when k.rest_tage_seit_epoche is not null
                then date '2000-01-01' + round(k.rest_tage_seit_epoche)::int
                else b.eingangsdatum_mittel end as rest_datum
  ) x
 where b.eingang_kg is not null;

-- ---------------------------------------------------------------------
-- 2. Die Saisonbilanz ohne den Term „anderer Kanal"
-- ---------------------------------------------------------------------
create or replace view v_saisonbilanz with (security_invoker = true) as
WITH charge AS (
         SELECT sum(erg_charge.eingang_kg) AS eingang_kg,
            sum(erg_charge.ausgelagert_kg) AS ausgelagert_kg,
            sum(erg_charge.geliefert_kg) AS geliefert_kg,
            sum(erg_charge.lager_kg) AS lager_kg,
            sum(erg_charge.wartet_kg) AS wartet_kg,
            sum(erg_charge.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(erg_charge.verkaufsfaehig_lager_kg) AS verkaufsfaehig_heute_kg,
            sum(erg_charge.im_haus_heute_kg) AS im_haus_heute_kg,
            sum(erg_charge.kanal_im_haus_kg) AS kanal_im_haus_kg,
            sum(erg_charge.verlust_heute_kg) AS verlust_heute_kg,
            sum(erg_charge.verdunstung_heute_kg) AS verdunstung_heute_kg,
            sum(erg_charge.schimmel_heute_kg) AS schimmel_heute_kg,
            sum(erg_charge.sockel_heute_kg) AS sockel_heute_kg,
            sum(erg_charge.fax_heute_kg) AS fax_heute_kg,
            sum(erg_charge.fax_erwartet_kg) AS fax_erwartet_kg,
            sum(erg_charge.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            bool_and(erg_charge.verlust_bekannt) AS bekannt,
            count(*)::integer AS n_chargen,
            max(erg_charge.heute) AS heute
           FROM erg_charge
        ), bereich AS (
         SELECT sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = ANY (ARRAY['verlust'::text, 'feld'::text])) AS verlust_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = ANY (ARRAY['verlust'::text, 'feld'::text])) AS verlust_oben_kg,
            sum(erg_verlust.kg) FILTER (WHERE erg_verlust.buch = ANY (ARRAY['verlust'::text, 'feld'::text])) AS verlust_kg,
            sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = 'marge'::text) AS kanal_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = 'marge'::text) AS kanal_oben_kg
           FROM erg_verlust
          WHERE erg_verlust.gruppe = 'gesamt'::text
        ), vorlauf AS (
         SELECT COALESCE(sum(charge_vorlauf.ausgang_vor_app_kg), 0::numeric) AS kg
           FROM charge_vorlauf
        ), ausgang AS (
         SELECT COALESCE(sum(v_lieferung_masse.masse_kg), 0::numeric) AS kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'verkauf'::text), 0::numeric) AS verkauf_kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'marge'::text), 0::numeric) AS marge_kg,
            COALESCE(sum(v_lieferung_masse.masse_kg) FILTER (WHERE v_lieferung_masse.buch = 'verlust'::text), 0::numeric) AS entsorgt_kg,
            COALESCE(sum(v_lieferung_masse.masse_fehler_kg), 0::double precision) AS fehler_kg,
            count(*)::integer AS n_lieferungen,
            max(v_lieferung_masse.datum) AS letzte_lieferung
           FROM v_lieferung_masse
          WHERE v_lieferung_masse.datum <= heute()
        ), fax AS (
         SELECT COALESCE(sum(v_fax_beobachtung.masse_kg), 0::numeric) AS kg,
            count(*)::integer AS n
           FROM v_fax_beobachtung
          WHERE v_fax_beobachtung.status = 'abgeschlossen'::auftrag_status AND v_fax_beobachtung.masse_kg IS NOT NULL
        )
 SELECT c.heute,
    zahl(c.eingang_kg)::numeric(14,2) AS eingang_kg,
    c.n_chargen,
    zahl(a.kg + vl.kg)::numeric(14,2) AS ausgang_kg,
    zahl(a.verkauf_kg)::numeric(14,2) AS verkauf_kg,
    zahl(a.marge_kg)::numeric(14,2) AS marge_kg,
    zahl(a.entsorgt_kg)::numeric(14,2) AS entsorgt_kg,
    zahl(a.fehler_kg)::numeric(14,2) AS ausgang_fehler_kg,
    a.n_lieferungen,
    a.letzte_lieferung,
    zahl(vl.kg)::numeric(14,2) AS vorlauf_kg,
    zahl(c.geliefert_kg)::numeric(14,2) AS geliefert_kg,
    zahl(c.ausgelagert_kg)::numeric(14,2) AS ausgelagert_kg,
    zahl(c.verlust_heute_kg)::numeric(14,2) AS verlust_heute_kg,
    zahl(b.verlust_unten_kg)::numeric(14,2) AS verlust_unten_kg,
    zahl(b.verlust_oben_kg)::numeric(14,2) AS verlust_oben_kg,
    zahl(c.verdunstung_heute_kg)::numeric(14,2) AS verdunstung_heute_kg,
    zahl(c.schimmel_heute_kg)::numeric(14,2) AS schimmel_heute_kg,
    zahl(c.sockel_heute_kg)::numeric(14,2) AS sockel_heute_kg,
    zahl(c.fax_heute_kg)::numeric(14,2) AS fax_heute_kg,
    zahl(c.fax_erwartet_kg)::numeric(14,2) AS fax_erwartet_kg,
    zahl(c.kanal_ausgelagert_kg)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(b.kanal_unten_kg)::numeric(14,2) AS kanal_unten_kg,
    zahl(b.kanal_oben_kg)::numeric(14,2) AS kanal_oben_kg,
    zahl(c.im_haus_heute_kg)::numeric(14,2) AS im_haus_heute_kg,
    zahl(c.verkaufsfaehig_heute_kg)::numeric(14,2) AS verkaufsfaehig_heute_kg,
    zahl(c.kanal_im_haus_kg)::numeric(14,2) AS kanal_im_haus_kg,
    zahl(c.lager_kg)::numeric(14,2) AS lager_kg,
    zahl(c.wartet_kg)::numeric(14,2) AS gegenprobe_wartet_kg,
    zahl(c.ueberzaehlung_kg)::numeric(14,2) AS ueberzaehlung_kg,
    zahl(f.kg)::numeric(14,2) AS fax_durchsatz_kg,
    f.n AS n_fax_arbeiten,
    COALESCE(c.bekannt, false) AS verlust_bekannt,
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.im_haus_heute_kg)::numeric(14,2) AS bilanz_rest_kg,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.im_haus_heute_kg) / c.eingang_kg
            ELSE NULL::numeric
        END, 4, '100000'::numeric)::numeric(10,4) AS bilanz_rest_anteil,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (a.kg + vl.kg) / c.eingang_kg
            ELSE NULL::numeric
        END, 4, '100000'::numeric)::numeric(10,4) AS ausgang_deckung,
        CASE
            WHEN COALESCE(c.eingang_kg, 0::numeric) <= 0::numeric THEN 'Es ist kein Wareneingang erfasst. Ohne das Erntejournal gibt es '::text || 'nichts, worauf sich Verlust und Bestand beziehen könnten.'::text
            WHEN COALESCE(c.ueberzaehlung_kg, 0::numeric) > (0.05 * c.eingang_kg) THEN format((('Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — '::text || 'bei einigen Chargen rund %s kg zu viel. Fast immer fehlt der '::text) || 'Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine '::text) || 'Lieferung ist der falschen Charge zugeordnet.'::text, round(c.ueberzaehlung_kg))
            WHEN a.n_lieferungen = 0 AND vl.kg = 0::numeric THEN ('Kein Warenausgang erfasst — dann liegt rechnerisch noch alles im Haus, '::text || 'und der Verlust bis heute gilt für die ganze Eingangsmasse. Sobald die '::text) || 'Lieferscheine eingelesen sind, teilt sich die Ware in ausgeliefert und liegend.'::text
            WHEN NOT COALESCE(c.bekannt, false) THEN 'Ein Verluststrom ist noch nicht gemessen — die Ursachen sind erst '::text || 'vollständig, wenn jeder Koeffizient mindestens eine Messung hat.'::text
            ELSE format((('Bis heute (%s): %s t Eingang = %s t ausgeliefert + %s t Verlust '::text || '(Verdunstung %s t, Faules %s t, Fax %s t) '::text) || '+ %s t noch im Haus (davon %s t verkaufsfähig, %s t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum '::text) || 'Saisonende steht in der Grafik, nicht in diesen Zahlen.%s'::text, to_char(c.heute::timestamp with time zone, 'DD.MM.YYYY'::text), round(c.eingang_kg / 1000.0, 1), round(c.geliefert_kg / 1000.0, 1), round(c.verlust_heute_kg / 1000.0, 1), round(c.verdunstung_heute_kg / 1000.0, 1), round((c.schimmel_heute_kg + c.sockel_heute_kg) / 1000.0, 1), round(c.fax_heute_kg / 1000.0, 1), round(c.im_haus_heute_kg / 1000.0, 1), round(c.verkaufsfaehig_heute_kg / 1000.0, 1), round((c.kanal_ausgelagert_kg + c.kanal_im_haus_kg) / 1000.0, 1), concat_ws(' '::text, '',
            CASE
                WHEN a.marge_kg > 0::numeric THEN format('An die Tiere und in den Nebenkanal geliefert: %s kg; hinter den Lieferungen aussortiert gerechnet: %s kg.'::text, round(a.marge_kg), round(c.kanal_ausgelagert_kg))
                ELSE NULL::text
            END,
            CASE
                WHEN a.entsorgt_kg > 0::numeric THEN format('Entsorgt: %s kg, gerechneter Schimmel: %s kg.'::text, round(a.entsorgt_kg), round(c.schimmel_heute_kg))
                ELSE NULL::text
            END,
            CASE
                WHEN COALESCE(c.ueberzaehlung_kg, 0::numeric) > 0::numeric THEN format('%s kg Überzählung.'::text, round(c.ueberzaehlung_kg))
                ELSE NULL::text
            END))
        END AS befund
   FROM charge c
     CROSS JOIN bereich b
     CROSS JOIN ausgang a
     CROSS JOIN vorlauf vl
     CROSS JOIN fax f;


-- ---------------------------------------------------------------------
-- 2. Wohin ging der Kürbis — der Eingang, vollständig aufgeteilt
--
-- Zwei Identitäten, und beide gehen **nicht** von selbst auf:
--
--   Eingang + Überzählung = ausgeliefert + anderer Kanal (ausgeliefert)
--                         + verdunstet + faul + Fax + im Lager
--   im Lager = verkaufsfähig + Kanal + Fax erwartet + faul + verdunstet
--
-- `rest_kg` und `lager_rest_kg` stehen als Spalten da, damit eine doppelt
-- gezählte oder vergessene Portion nicht unsichtbar bleibt, sondern als
-- Zahl. Block 0071 der Prüfung lässt für beide 0.1 kg zu — das ist die
-- Rundung von numeric(14,2) über sechzig Gruppen, nichts weiter.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 3. Der Verlauf: im Haus je Woche mit dem Aussortierten, aussortiert_kg
--    als eigene Spalte. Wie 0071: weg und neu, mit denselben Indizes.
-- ---------------------------------------------------------------------
drop materialized view if exists erg_verlauf cascade;
create materialized view erg_verlauf as
with tag as materialized (
  -- heute() und stichtag() **einmal** — siehe die Erklärung bei v_prognose:
  -- Beide tragen `set search_path`, werden darum nicht in die Abfrage
  -- eingesetzt und kosten je Aufruf rund 47 µs. In der Endauswahl unten
  -- stünde heute() sonst je Woche und Gruppe da, also tausendfach.
  select heute() as heute, stichtag() as stichtag
), modell as materialized (
  select * from v_schimmel_modell
), kurve as materialized (
  select von, anteil_mono from v_schimmel_kurve where n > 0
), wochen as materialized (
  select w::date as woche, (w + interval '6 days')::date as bis
    from tag t, generate_series(
      date_trunc('week', coalesce((select min(eingangsdatum) from palette), t.heute))::date,
      date_trunc('week', greatest(t.stichtag, t.heute + 84))::date, interval '7 days') w
  union
  select date_trunc('week', t.heute)::date, t.heute from tag t
), gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from v_kaskade_basis
  union all select 'sorte',  sorte,           charge_nr from v_kaskade_basis
  union all select 'schlag', schlag,          charge_nr from v_kaskade_basis
  union all select 'charge', charge_nr::text, charge_nr from v_kaskade_basis
), portionen as materialized (
  select k.charge_nr, k.portion, k.kohorte, k.m0, k.r, k.a0,
         k.a_klein_n, k.a_gross_n, k.a_fax,
         case when k.portion = 'ausgelagert' then k.kohorte + round(k.alter_tage)::int end as liefertag,
         case when k.portion = 'ausgelagert' then k.fax_kg else 0 end                      as fax_kg
    from mv_kaskade k
   where k.m0 > 0 and k.kohorte is not null
), f_je_tag as materialized (
  select gs.t,
         case when gs.t <= 0 then 0
              when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                     m.ln_lambda_korrigiert + m.k * ln(greatest(gs.t::numeric, 1)), -40), 3))), 0), 1)
              else least(greatest(coalesce((select c.anteil_mono from kurve c
                                              where c.von <= gs.t order by c.von desc limit 1), 0), 0), 1)
         end as f
    from generate_series(0, greatest(coalesce(
           (select max(w.bis) from wochen w) - (select min(p.kohorte) from portionen p), 0), 0)) gs(t)
   cross join modell m
), je_woche as (
  -- Erst je Charge und Woche verdichten: Die teure Arbeit (Portionen mal
  -- Wochen) passiert einmal statt viermal, und die vier Gruppenebenen sind
  -- danach ein billiges Hochrollen über sechsunddreissig Chargen.
  select w.woche, w.bis, p.charge_nr,
         p.m0 * (1 - power(1 - p.r, x.t))                                     as verdunstung_kg,
         p.m0 * power(1 - p.r, x.t) * p.a0                                    as sockel_kg,
         p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * f.f                        as schimmel_kg,
         case when p.liefertag is not null and p.liefertag <= w.bis then p.fax_kg else 0 end as fax_kg,
         -- Was am Wochenende noch liegt: die Portion, solange sie nicht
         -- ausgeliefert ist. „im Lager" ist die Eingangsware (m0), „gute
         -- Ware" das, was nach Verdunstung und Verderb davon übrig ist,
         -- „verkaufsfähig" davon noch ohne zu klein/zu gross und ohne das
         -- Faule, das beim Abpacken noch anfällt.
         case when p.liefertag is null or p.liefertag > w.bis then p.m0 else 0 end as lager_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * (1 - f.f) else 0 end as gute_ware_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * (1 - f.f)
                   * (p.a_klein_n + p.a_gross_n) else 0 end                        as kanal_lager_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * (1 - f.f)
                   * (1 - p.a_klein_n - p.a_gross_n) * p.a_fax else 0 end          as fax_lager_kg,
         -- 0101: Zu klein und zu gross hinter den Lieferungen — am Liefertag
         -- aussortiert, seither im Haus (nicht verkaufsfähig), bis ein
         -- Lieferschein es holt. Für eine gelieferte Portion ist x.t das Alter
         -- am Liefertag: die Masse bleibt stehen, wie sie da aussortiert war.
         case when p.liefertag is not null and p.liefertag <= w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * (1 - f.f)
                   * (p.a_klein_n + p.a_gross_n) else 0 end                        as aussortiert_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * (1 - f.f)
                   * (1 - p.a_klein_n - p.a_gross_n) * (1 - p.a_fax) else 0 end    as verkaufsfaehig_kg
    from wochen w
    join portionen p on p.kohorte <= w.bis
    cross join lateral (
      select greatest(least(w.bis, coalesce(p.liefertag, w.bis)) - p.kohorte, 0) as t
    ) x
    join f_je_tag f on f.t = x.t
), je_charge as materialized (
  select woche, bis, charge_nr,
         sum(verdunstung_kg) as verdunstung_kg, sum(sockel_kg) as sockel_kg,
         sum(schimmel_kg) as schimmel_kg, sum(fax_kg) as fax_kg,
         sum(gute_ware_kg) as im_haus_kg, sum(lager_kg) as lager_kg,
         sum(kanal_lager_kg) as kanal_kg, sum(fax_lager_kg) as fax_lager_kg,
         sum(verkaufsfaehig_kg) as verkaufsfaehig_kg,
         sum(aussortiert_kg) as aussortiert_kg
    from je_woche
   group by woche, bis, charge_nr
), verlust as (
  select j.woche, j.bis, g.gruppe, g.schluessel,
         sum(j.verdunstung_kg) as verdunstung_kg, sum(j.sockel_kg) as sockel_kg,
         sum(j.schimmel_kg) as schimmel_kg, sum(j.fax_kg) as fax_kg,
         sum(j.im_haus_kg) as im_haus_kg, sum(j.lager_kg) as lager_kg,
         sum(j.kanal_kg) as kanal_kg, sum(j.fax_lager_kg) as fax_lager_kg,
         sum(j.verkaufsfaehig_kg) as verkaufsfaehig_kg,
         sum(j.aussortiert_kg) as aussortiert_kg
    from je_charge j join gruppen g on g.charge_nr = j.charge_nr
   group by j.woche, j.bis, g.gruppe, g.schluessel
), eingang_charge as materialized (
  -- Gelesen wird v_charge_kohorte, nicht v_palette. Der Unterschied sind die
  -- Paletten ohne Nettogewicht (fehlende Tara oder Kistenzahl): v_palette
  -- lässt sie weg, v_charge_kohorte rechnet sie mit dem Mittel der übrigen
  -- hoch — so wie die Kaskade und die Saisonbilanz es tun (0064). Vorher
  -- stand im Verlauf darum ein kleinerer Eingang als in der Bilanz; auf der
  -- bösen Saison 432 237 kg gegen 432 667 kg, und die Kurve „im Haus" fing
  -- 430 kg zu tief an. Gefunden hat das K10 der Gegenprobe.
  select w.woche, w.bis, k.charge_nr, sum(k.eingang_kg) as kg
    from wochen w join v_charge_kohorte k on k.eingangsdatum <= w.bis
   group by w.woche, w.bis, k.charge_nr
), eingang as (
  select e.woche, e.bis, g.gruppe, g.schluessel, sum(e.kg) as kg
    from eingang_charge e join gruppen g on g.charge_nr = e.charge_nr
   group by e.woche, e.bis, g.gruppe, g.schluessel
), ausgang_charge as materialized (
  select w.woche, w.bis, l.charge_nr, sum(l.masse_kg) as kg
    from wochen w join v_lieferung_charge_tag l on l.datum <= w.bis
   group by w.woche, w.bis, l.charge_nr
), ausgang as (
  select a.woche, a.bis, g.gruppe, g.schluessel, sum(a.kg) as kg
    from ausgang_charge a join gruppen g on g.charge_nr = a.charge_nr
   group by a.woche, a.bis, g.gruppe, g.schluessel
), liste as (
  select distinct gruppe, schluessel from gruppen
)
select w.woche, w.bis, (w.bis > d.heute)                                      as prognose,
       s.gruppe, s.schluessel,
       zahl(coalesce(e.kg, 0), 2, 1e12)::numeric(14,2)                         as eingang_kum_kg,
       zahl(coalesce(a.kg, 0), 2, 1e12)::numeric(14,2)                         as ausgang_kum_kg,
       zahl(coalesce(v.verdunstung_kg, 0), 2, 1e12)::numeric(14,2)             as verdunstung_kum_kg,
       zahl(coalesce(v.schimmel_kg, 0), 2, 1e12)::numeric(14,2)                as schimmel_kum_kg,
       zahl(coalesce(v.sockel_kg, 0), 2, 1e12)::numeric(14,2)                  as sockel_kum_kg,
       zahl(coalesce(v.fax_kg, 0), 2, 1e12)::numeric(14,2)                     as fax_kum_kg,
       zahl(coalesce(v.verdunstung_kg, 0) + coalesce(v.schimmel_kg, 0)
            + coalesce(v.sockel_kg, 0) + coalesce(v.fax_kg, 0), 2, 1e12)::numeric(14,2)
                                                                              as verlust_kum_kg,
       -- 0101: im Haus = Liegendes nach Verdunstung und Verderb + hinter den
       -- Lieferungen Aussortiertes; auf heute dieselbe Zahl wie erg_bilanz.
       zahl(coalesce(v.im_haus_kg, 0) + coalesce(v.aussortiert_kg, 0), 2, 1e12)::numeric(14,2)
                                                                              as im_haus_kg,
       zahl(coalesce(v.lager_kg, 0), 2, 1e12)::numeric(14,2)                   as lager_kg,
       zahl(coalesce(v.verkaufsfaehig_kg, 0), 2, 1e12)::numeric(14,2)          as verkaufsfaehig_kg,
       zahl(coalesce(v.kanal_kg, 0), 2, 1e12)::numeric(14,2)                   as kanal_kg,
       zahl(coalesce(v.fax_lager_kg, 0), 2, 1e12)::numeric(14,2)               as fax_lager_kg,
       zahl(coalesce(v.aussortiert_kg, 0), 2, 1e12)::numeric(14,2)              as aussortiert_kg
  from wochen w
  cross join liste s
  cross join tag d
  left join verlust v on v.bis = w.bis and v.gruppe = s.gruppe and v.schluessel = s.schluessel
  left join eingang e on e.bis = w.bis and e.gruppe = s.gruppe and e.schluessel = s.schluessel
  left join ausgang a on a.bis = w.bis and a.gruppe = s.gruppe and a.schluessel = s.schluessel
 with no data;

-- ---------------------------------------------------------------------
-- 4. Die Prognose kennt den Anteil auch ohne Sockel-Nachweis (wie 0097)
-- ---------------------------------------------------------------------
create or replace view v_prognose with (security_invoker = true) as
with modell as materialized (
  select * from v_schimmel_modell
), kurve as materialized (
  select von, anteil_mono, unten as anteil_unten, oben as anteil_oben
    from v_schimmel_kurve where n > 0
), tag as materialized (
  -- heute() **einmal**. Die Funktion trägt `set search_path`, und das
  -- verhindert, dass Postgres sie in die Abfrage einsetzt: Jeder Aufruf ist
  -- ein echter Funktionsaufruf mit Sichern und Zurücksetzen der Einstellung,
  -- gemessen 47 µs. Stand sie — wie in der ersten Fassung — im Ausdruck
  -- `heute() + h` je Portion und Horizont, waren das im Lasttest 56 700
  -- Aufrufe und 2.7 s, mehr als die halbe Laufzeit der ganzen Sicht.
  select heute() as heute, stichtag() as stichtag
), ende as (
  -- Bis zum Saisonende, aber nie weiter als ein Jahr und nie kürzer als
  -- vier Wochen: „in zwei Wochen" muss auch am 20. März noch dastehen.
  select greatest(least(t.stichtag - t.heute, 400), 28) as tage from tag t
), horizonte as (
  select h from ende e, generate_series(0, e.tage, 7) g(h)
  union select 7 union select 14 union select 28
  union select tage from ende
), grenzen as (
  -- Die Ränder je Sorte, fertig gerechnet in Schritt 2 (mv_koeff_rand).
  select * from mv_koeff_rand
), lager as materialized (
  -- Die liegende Portion der Kaskade, unverändert übernommen. alter_tage
  -- ist dort schon auf 0 geklammert (0070: die Zeit läuft vorwärts).
  --
  -- Dazu die Verdunstung **bis heute** als fertiger Faktor: (1−r)^alter,
  -- einmal je Portion. Warum das hier steht und nicht unten in der Formel,
  -- steht bei `faktor_h`.
  select k.charge_nr, k.sorte, k.schlag, k.kohorte, k.alter_tage, k.m0,
         k.r, k.a0, k.a_klein_n, k.a_gross_n, k.a_fax,
         k.r_bekannt, k.f_bekannt, k.a0_bekannt,
         k.a_klein_bekannt, k.a_gross_bekannt, k.a_fax_bekannt,
         k.modell_gilt,
         coalesce(g.r_unten, 0) as r_unten, coalesce(g.r_oben, 0) as r_oben,
         coalesce(g.klein_unten, 0) as klein_unten, coalesce(g.klein_oben, 0) as klein_oben,
         coalesce(g.gross_unten, 0) as gross_unten, coalesce(g.gross_oben, 0) as gross_oben,
         coalesce(g.fax_unten, 0) as fax_unten, coalesce(g.fax_oben, 0) as fax_oben,
         power(1 - k.r, k.alter_tage)                            as wa,
         power(1 - greatest(coalesce(g.r_unten, 0), 0), k.alter_tage) as wa_unten,
         power(1 - greatest(coalesce(g.r_oben,  0), 0), k.alter_tage) as wa_oben
    from mv_kaskade k
    left join grenzen g on g.sorte = k.sorte
   where k.portion = 'lager' and k.m0 > 0 and k.alter_tage >= 0
), faktor_h as materialized (
  -- Warum es diese Tabelle gibt: `power()` auf numeric ist teuer — Postgres
  -- rechnet sie über Logarithmus und Exponent in voller Genauigkeit. In der
  -- ersten Fassung stand sie achtmal in der Formel und wurde für jede
  -- Portion mal jeden Horizont neu ausgeführt: beim Lasttest 1890 × 30 × 8 =
  -- 453 600 Aufrufe, gemessen 7.7 s für erg_prognose allein.
  --
  -- Dabei gilt (1−r)^(alter+h) = (1−r)^alter · (1−r)^h, und r hängt nur an
  -- der Charge. Der erste Teil steht darum oben je Portion (1890 Aufrufe),
  -- der zweite hier je Charge und Horizont (1260). Zusammen rund neuntausend
  -- statt einer halben Million — und in der Formel unten kommt kein
  -- `power()` mehr vor.
  select c.charge_nr, h.h,
         power(1 - c.r, h.h)                              as wh,
         power(1 - greatest(c.r_unten, 0), h.h)           as wh_unten,
         power(1 - greatest(c.r_oben,  0), h.h)           as wh_oben
    from (select distinct charge_nr, r, r_unten, r_oben from lager) c
   cross join horizonte h
), tage as (
  select distinct (l.alter_tage + h.h)::int as t from lager l cross join horizonte h
), f_je_tag as materialized (
  -- F(t) hängt nur vom Alter ab, nicht von der Portion — einmal je Tag
  -- gerechnet. Mittelwert und Ränder mit derselben Formel wie
  -- schimmelanteil(); der Rand ist η ± t·√(Var), nicht ein Zuschlag auf F.
  select t.t,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                     m.ln_lambda_korrigiert + m.k * ln(greatest(t.t::numeric, 1)), -40), 3))), 0), 1)
              else least(greatest(coalesce((select c.anteil_mono from kurve c
                                              where c.von <= t.t order by c.von desc limit 1), 0), 0), 1)
         end as f,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                     m.ln_lambda_korrigiert + m.k * ln(greatest(t.t::numeric, 1))
                     - m.t_faktor * sqrt(greatest(m.var_achse
                         + power(ln(greatest(t.t::numeric, 1)) - m.x_mittel, 2) * m.var_k
                         + 2 * (ln(greatest(t.t::numeric, 1)) - m.x_mittel) * m.kov_achse_k, 0)), -40), 3))), 0), 1)
              else least(greatest(coalesce((select coalesce(c.anteil_unten, c.anteil_mono) from kurve c
                                              where c.von <= t.t order by c.von desc limit 1), 0), 0), 1)
         end as f_unten,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                     m.ln_lambda_korrigiert + m.k * ln(greatest(t.t::numeric, 1))
                     + m.t_faktor * sqrt(greatest(m.var_achse
                         + power(ln(greatest(t.t::numeric, 1)) - m.x_mittel, 2) * m.var_k
                         + 2 * (ln(greatest(t.t::numeric, 1)) - m.x_mittel) * m.kov_achse_k, 0)), -40), 3))), 0), 1)
              else least(greatest(coalesce((select coalesce(c.anteil_oben, c.anteil_mono) from kurve c
                                              where c.von <= t.t order by c.von desc limit 1), 0), 0), 1)
         end as f_oben
    from tage t cross join modell m
), je_portion as (
  select l.*, h.h, (l.alter_tage + h.h)::int as t,
         f.f, f.f_unten, f.f_oben, f0.f as f_heute,
         w.wh, w.wh_unten, w.wh_oben,
         case when m.brauchbar then coalesce(m.sockel_unten, m.sockel, 0) else 0 end as a0_unten,
         case when m.brauchbar then coalesce(m.sockel_oben,  m.sockel, 0) else 0 end as a0_oben,
         m.t_max,
         d.heute + h.h as datum
    from lager l
    cross join horizonte h
    cross join modell m
    cross join tag d
    join faktor_h w  on w.charge_nr = l.charge_nr and w.h = h.h
    join f_je_tag f  on f.t  = (l.alter_tage + h.h)::int
    join f_je_tag f0 on f0.t = l.alter_tage::int
), stroeme as (
  -- Die Ströme je Portion und Horizont — und zwar **fertig**, nicht als
  -- Zwischenwerte, aus denen die Summe unten noch einmal rechnet.
  --
  -- Warum das so aussieht: Vorher standen hier m1 und m2, und die Summe
  -- setzte daraus fünfzehnmal Ausdrücke zusammen (`sum(m2 * (1 − klein −
  -- gross) * fax)` und so fort). Postgres rechnet jeden dieser Ausdrücke je
  -- Zeile neu; bei 56 700 Zeilen im Lasttest waren das Sekunden. Jetzt
  -- stehen m1, m2 und „Rest nach Kanal" **einmal** da (die drei seitlichen
  -- Verbunde), jede Stromgrösse einmal, und die Summe unten addiert nur noch.
  --
  -- Auch kein `power()` mehr: (1−r)^(alter+h) ist das Produkt der zwei
  -- fertigen Faktoren wa (bis heute) und wh (der Horizont).
  select p.charge_nr, p.h, p.datum, p.t, p.m0,
         p.m0 - x.m1                                                           as verdunstet_kg,
         x.m1 * p.a0                                                           as sockel_kg,
         x.m1 * (1 - p.a0) * p.f                                               as faul_kg,
         y.m2 - z.rest                                                         as kanal_kg,
         z.rest * p.a_fax                                                      as fax_kg,
         z.rest * (1 - p.a_fax)                                                as verkaufsfaehig_kg,
         y.m2                                                                  as gute_ware_kg,
         -- Die Ränder: alle Koeffizienten gleichzeitig am ungünstigsten Rand.
         p.m0 * p.wa_oben * p.wh_oben * (1 - p.a0_oben) * (1 - p.f_oben)
              * (1 - least(p.klein_oben / greatest(p.klein_oben + p.gross_oben, 1)
                         + p.gross_oben / greatest(p.klein_oben + p.gross_oben, 1), 1))
              * (1 - p.fax_oben)                                               as vf_unten,
         p.m0 * p.wa_unten * p.wh_unten * (1 - p.a0_unten) * (1 - p.f_unten)
              * (1 - least(p.klein_unten / greatest(p.klein_unten + p.gross_unten, 1)
                         + p.gross_unten / greatest(p.klein_unten + p.gross_unten, 1), 1))
              * (1 - p.fax_unten)                                              as vf_oben,
         -- Was das Liegen ab heute an **verkaufsfähiger** Ware kostet, exakt
         -- in zwei Teile zerlegt. Sei B = m0·(1−a0)·(1−klein−gross)·(1−fax)
         -- die verkaufsfähige Grundmasse, t₀ das heutige Alter und h der
         -- Horizont; dann ist
         --   Wasser  = B·(1−r)^t₀·(1−F(t₀))·(1 − (1−r)^h)
         --   Fäulnis = B·(1−r)^t₀·(1−r)^h·(F(t₀+h) − F(t₀))
         -- und beide zusammen sind auf den Rappen VF(0) − VF(h). Beide sind
         -- nie negativ: (1−r)^h ≤ 1, und F wächst mit der Zeit. Die naive
         -- Differenz „faul nachher minus faul vorher" hätte das nicht — bei
         -- einer Charge, deren Verderb schon gesättigt ist, verliert auch das
         -- Faule Wasser, und die Differenz würde negativ.
         b.basis * (1 - p.f_heute) * (1 - p.wh)                                as verlust_wasser,
         b.basis * p.wh * greatest(p.f - p.f_heute, 0)                         as verlust_faeulnis,
         p.m0 * p.t                                                            as m0_mal_t,
         p.r_bekannt, p.f_bekannt, p.a0_bekannt,
         p.a_klein_bekannt, p.a_gross_bekannt, p.a_fax_bekannt, p.modell_gilt,
         (p.modell_gilt and p.t > p.t_max)                                     as ueber_t_max
    from je_portion p
    cross join lateral (select p.m0 * p.wa * p.wh as m1) x
    cross join lateral (select x.m1 * (1 - p.a0) * (1 - p.f) as m2) y
    cross join lateral (select y.m2 * (1 - p.a_klein_n - p.a_gross_n) as rest) z
    cross join lateral (select p.m0 * (1 - p.a0) * (1 - p.a_klein_n - p.a_gross_n)
                             * (1 - p.a_fax) * p.wa as basis) b
), gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from v_kaskade_basis
  union all select 'sorte',  sorte,           charge_nr from v_kaskade_basis
  union all select 'schlag', schlag,          charge_nr from v_kaskade_basis
  union all select 'charge', charge_nr::text, charge_nr from v_kaskade_basis
), je_charge as materialized (
  -- Erst je Charge verdichten, dann auf die Gruppen hochrollen: Die teure
  -- Arbeit (Kohorten mal Horizonte) passiert einmal, nicht viermal.
  select s.charge_nr, s.h, max(s.datum) as datum,
         count(*)::int                                                         as n_kohorten,
         sum(s.m0)                                                             as lager_kg,
         sum(s.verdunstet_kg)                                                  as verdunstet_kg,
         sum(s.sockel_kg)                                                      as sockel_kg,
         sum(s.faul_kg)                                                        as faul_kg,
         sum(s.kanal_kg)                                                       as kanal_kg,
         sum(s.fax_kg)                                                         as fax_kg,
         sum(s.verkaufsfaehig_kg)                                              as verkaufsfaehig_kg,
         sum(s.gute_ware_kg)                                                   as gute_ware_kg,
         sum(s.vf_unten)                                                       as vf_unten_kg,
         sum(s.vf_oben)                                                        as vf_oben_kg,
         sum(s.verlust_wasser)                                                 as verlust_wasser_kg,
         sum(s.verlust_faeulnis)                                               as verlust_faeulnis_kg,
         sum(s.m0_mal_t)                                                       as m0_mal_t,
         bool_and(s.r_bekannt)                                                 as r_bekannt,
         bool_and(s.f_bekannt)                                                 as f_bekannt,
         bool_and(s.a0_bekannt)                                                as sockel_bekannt,
         bool_and(s.a_klein_bekannt and s.a_gross_bekannt)                     as kanal_bekannt,
         bool_and(s.a_fax_bekannt)                                             as fax_bekannt,
         bool_and(s.modell_gilt)                                               as modell_gilt,
         bool_or(s.ueber_t_max)                                                as hochgerechnet,
         min(s.t)                                                              as alter_von,
         max(s.t)                                                              as alter_bis
    from stroeme s
   group by s.charge_nr, s.h
), summe as materialized (
  select g.gruppe, g.schluessel, j.h, max(j.datum) as datum,
         count(*)::int                                                         as n_chargen,
         sum(j.n_kohorten)::int                                                as n_kohorten,
         sum(j.lager_kg)                                                       as lager_kg,
         sum(j.verdunstet_kg)                                                  as verdunstet_kg,
         sum(j.sockel_kg)                                                      as sockel_kg,
         sum(j.faul_kg)                                                        as faul_kg,
         sum(j.kanal_kg)                                                       as kanal_kg,
         sum(j.fax_kg)                                                         as fax_kg,
         sum(j.verkaufsfaehig_kg)                                              as verkaufsfaehig_kg,
         sum(j.gute_ware_kg)                                                   as gute_ware_kg,
         sum(j.vf_unten_kg)                                                    as vf_unten_kg,
         sum(j.vf_oben_kg)                                                     as vf_oben_kg,
         sum(j.verlust_wasser_kg)                                              as verlust_wasser_kg,
         sum(j.verlust_faeulnis_kg)                                            as verlust_faeulnis_kg,
         bool_and(j.r_bekannt)                                                 as r_bekannt,
         bool_and(j.f_bekannt)                                                 as f_bekannt,
         bool_and(j.sockel_bekannt)                                            as sockel_bekannt,
         bool_and(j.kanal_bekannt)                                             as kanal_bekannt,
         bool_and(j.fax_bekannt)                                               as fax_bekannt,
         bool_and(j.modell_gilt)                                               as modell_gilt,
         bool_or(j.hochgerechnet)                                              as hochgerechnet,
         sum(j.m0_mal_t) / nullif(sum(j.lager_kg), 0)                          as alter_tage,
         min(j.alter_von)                                                      as alter_von,
         max(j.alter_bis)                                                      as alter_bis
    from je_charge j join gruppen g on g.charge_nr = j.charge_nr
   group by g.gruppe, g.schluessel, j.h
), rate as (
  -- Was die liegende Ware zurzeit je Tag kostet: der Schritt von heute auf
  -- die nächste Stützstelle, durch ihre Tage geteilt.
  select s0.gruppe, s0.schluessel,
         (s1.verlust_wasser_kg + s1.verlust_faeulnis_kg) / s1.h          as vf_je_tag_kg,
         s1.verlust_wasser_kg / s1.h                                     as verdunstet_je_tag_kg,
         s1.verlust_faeulnis_kg / s1.h                                   as faul_je_tag_kg
    from summe s0
    join lateral (select x.* from summe x
                   where x.gruppe = s0.gruppe and x.schluessel = s0.schluessel and x.h > 0
                   order by x.h limit 1) s1 on true
   where s0.h = 0
)
select s.gruppe, s.schluessel, s.h, s.datum, s.n_chargen, s.n_kohorten,
       zahl(s.lager_kg,          2, 1e12)::numeric(14,2)            as lager_kg,
       zahl(s.verdunstet_kg,     2, 1e12)::numeric(14,2)            as verdunstet_kg,
       zahl(s.sockel_kg,         2, 1e12)::numeric(14,2)            as sockel_kg,
       zahl(s.faul_kg,           2, 1e12)::numeric(14,2)            as faul_kg,
       zahl(s.kanal_kg,          2, 1e12)::numeric(14,2)            as kanal_kg,
       zahl(s.fax_kg,            2, 1e12)::numeric(14,2)            as fax_kg,
       zahl(s.verkaufsfaehig_kg, 2, 1e12)::numeric(14,2)            as verkaufsfaehig_kg,
       zahl(s.gute_ware_kg,      2, 1e12)::numeric(14,2)            as gute_ware_kg,
       -- Was das Liegen ab heute bis zu diesem Horizont kostet, in zwei
       -- Teilen, die exakt zusammen den Verlust an verkaufsfähiger Ware
       -- ergeben (bei h = 0 sind alle drei null).
       zahl(s.verlust_wasser_kg,    2, 1e12)::numeric(14,2)         as verlust_wasser_kg,
       zahl(s.verlust_faeulnis_kg,  2, 1e12)::numeric(14,2)         as verlust_faeulnis_kg,
       zahl(s.verlust_wasser_kg + s.verlust_faeulnis_kg, 2, 1e12)::numeric(14,2)
                                                                    as verlust_verkaufsfaehig_kg,
       -- Leer ist nicht null (0064): Fehlt ein Koeffizient, sind die Massen
       -- oben eine obere Schranke — der **Anteil**, den der Betriebsleiter
       -- liest, ist dann unbekannt und bleibt leer. Ebenso die Hülle.
       (case when v.vollstaendig and s.lager_kg > 0
             then zahl(s.verkaufsfaehig_kg / s.lager_kg, 4, 1) end)::numeric(6,4) as verkaufsfaehig_anteil,
       (case when v.vollstaendig then zahl(s.vf_unten_kg, 2, 1e12) end)::numeric(14,2) as verkaufsfaehig_unten_kg,
       (case when v.vollstaendig then zahl(s.vf_oben_kg,  2, 1e12) end)::numeric(14,2) as verkaufsfaehig_oben_kg,
       zahl(r.vf_je_tag_kg,         1, 1e9)::numeric(12,1)          as verkaufsfaehig_je_tag_kg,
       zahl(r.verdunstet_je_tag_kg, 1, 1e9)::numeric(12,1)          as verdunstet_je_tag_kg,
       zahl(r.faul_je_tag_kg,       1, 1e9)::numeric(12,1)          as faul_je_tag_kg,
       s.r_bekannt, s.f_bekannt, s.sockel_bekannt, s.kanal_bekannt, s.fax_bekannt,
       v.vollstaendig, s.modell_gilt, s.hochgerechnet,
       round(s.alter_tage)::int as alter_tage, s.alter_von, s.alter_bis
  from summe s
  -- 0101: Der Sockel gehört nicht mehr dazu — seit 0097 ist er ohne Nachweis
  -- 0, nicht unbekannt (erg_charge.verlust_bekannt hängt seither an
  -- Verdunstung, Faulem, Fax und Ausschuss). Hier stand er noch: Darum sagte
  -- das Lagermanagement „der Anteil ist unbekannt, solange eine Rate nicht
  -- gemessen ist", während die Bilanz daneben den Verlust kannte.
  cross join lateral (select (s.r_bekannt and s.f_bekannt
                              and s.kanal_bekannt and s.fax_bekannt) as vollstaendig) v
  left join rate r on r.gruppe = s.gruppe and r.schluessel = s.schluessel;

create unique index if not exists erg_verlauf_pk on erg_verlauf (woche, bis, gruppe, schluessel);
create index if not exists erg_verlauf_gruppe on erg_verlauf (gruppe, schluessel, bis);
create index if not exists erg_verlauf_woche on erg_verlauf (woche);
grant select on erg_verlauf to authenticated;
comment on materialized view erg_verlauf is
  'Je Woche und Gruppe (gesamt, Sorte, Schlag, Charge): Eingang und Ausgang '
  'kumuliert (gemessen), im Lager (Eingangsware, die noch nicht hinter einer '
  'Lieferung steckt) und davon verkaufsfähig (gerechnet) — ab heute als '
  'Prognose bis zum Saisonende (prognose = true). Der Verlust ist der Abstand '
  'zwischen im Lager und verkaufsfähig; seine Teile stehen weiter als eigene '
  'Spalten (0071). im_haus_kg: Liegendes nach Verdunstung und Verderb plus '
  'aussortiert_kg — zu klein und zu gross hinter den Lieferungen, das im Haus '
  'steht, bis ein Lieferschein es holt (0101).';

comment on materialized view erg_charge is
  'v_hochrechnung_basis, gespeichert für die App (0062). Erneuert mit auswertung_schritt(). '
  'Seit 0101 zählt im_haus_heute_kg das hinter den Lieferungen Aussortierte mit '
  '(kanal_ausgelagert_kg: zu klein und zu gross, im Haus, nicht verkaufsfähig).';
comment on view v_saisonbilanz is
  'Die Saison bis heute in einer Zeile (erg_bilanz). Seit 0101: Eingang + Überzählung '
  '= ausgeliefert (Lieferscheine) + Verlust bis heute + im Haus — zu klein und zu gross '
  'sind Teil von im Haus (kanal_ausgelagert_kg aussortiert, kanal_im_haus_kg im '
  'Liegenden erwartet), nicht Ausgang.';

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 101 $$;
