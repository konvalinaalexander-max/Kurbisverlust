-- =====================================================================
-- 0064 — Leer ist nicht null, auch am Eingang
--
-- Runde L hat mit dem Prüfwerk (pruefwerk/) nachgesehen, wo aus einer
-- Lücke eine Zahl wird. Fünf Stellen, alle nach demselben Muster:
-- `coalesce(etwas_unbekanntes, 0)`. Die Null rechnet dann weiter und sieht
-- aus wie eine Messung.
--
--   1. Fehlt die Kistenzahl einer Palette, rechnet v_palette mit **null
--      Kisten**. Das Gewicht der Kisten wird als Kürbis verbucht: bei 30
--      Kisten à 1 kg auf 950 kg Netto sind das 3,2 % zu viel Eingang. Und
--      es fällt nirgends auf — die Palette hat ein Netto, es ist nur falsch.
--      Dasselbe für die fehlende Palettentara.
--
--   2. Dieselbe Rechnung steht an drei weiteren Stellen (Wägung damals /
--      jetzt). Dort kürzt sich die Palettentara im Verhältnis heraus, die
--      Kistentara aber nicht: Beide Nettos werden zu hoch, ihr Verhältnis
--      rückt gegen 1, und die Verdunstungsrate wird zu klein.
--
--   3. Ein Verluststrom ohne Messung stand in v_hochrechnung_basis als
--      0,00 kg. erg_verlust macht es seit jeher richtig (NULL, bekannt =
--      false) — dieselbe Datenbank gab damit auf zwei Wegen zwei Antworten.
--      Auf dem Überblick stand „Verlust bis heute: 0,0 t · 0,0 % des
--      Eingangs", bevor die erste Palette gewogen war.
--
--   4. `coalesce(k.im_haus_heute_kg, b.eingang_kg)` war für den Fall
--      gedacht, dass es zu einer Charge **gar keine** Kaskadenzeile gibt —
--      dann liegt tatsächlich noch alles. Sie griff aber auch, wenn es
--      Zeilen gibt und nur die Portion „lager" fehlt, und das ist der
--      genaue Gegenfall: Es liegt nichts mehr. Eine vollständig
--      ausgelieferte Charge über 950 kg meldete 950 kg „noch im Haus", und
--      die Bilanz ging um dieselben 950 kg nicht auf. Am Saisonende wird
--      das der Normalfall.
--
--   5. Drei Dinge, die der Betrieb sehen soll, sah er nicht: eine
--      Gebindeart ohne hinterlegte Tara (die ganze Charge fällt aus der
--      Bilanz), eine Charge, die mehr ausgeliefert hat als je erfasst
--      wurde (4180 kg in der Demosaison), und ein Zettelgewicht, das zur
--      Charge passt, aber nicht zum Tag (still genähert).
--
-- Nichts davon ist eine neue Funktion. Es sind fünf Stellen, an denen eine
-- Zahl behauptet hat, gemessen zu sein.
-- =====================================================================

-- ---------- 1. Das Netto einer Palette ----------------------------------
-- Ohne Kistenzahl gibt es kein Netto. Ohne hinterlegte Tara auch nicht —
-- das war schon so, weil `g.tara_kg_pro_kiste` ohne coalesce steht; die
-- Palettentara bekommt jetzt dieselbe Behandlung.
create or replace view v_palette with (security_invoker = true) as
select p.id, p.charge_nr, p.eingangsdatum, p.brutto_kg, p.kisten, p.gebindeart,
       p.brutto_kg - p.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette as netto_kg
  from palette p
  left join gebinde g on g.art = p.gebindeart;
comment on view v_palette is
  'Jede Eingangspalette mit ihrem Nettogewicht: brutto − Kisten × Kistentara − '
  'Palettentara. netto_kg ist NULL, sobald eine der drei Angaben fehlt (0064) — '
  'eine fehlende Kistenzahl heisst nicht „null Kisten". Wie viele Paletten einer '
  'Charge ein Netto haben, steht als n_paletten_mit_netto in v_kaskade_basis.';

-- ---------- 2. Dieselbe Rechnung an den Wägungen ------------------------
create or replace view v_verdunstung_messung with (security_invoker = true) as
 SELECT w.id,
    w.charge_nr,
    c.sorte,
    c.schlag,
    w.palette_id,
    w.eingangsdatum,
    w.wiege_ts,
    w.sichtbar_schimmel,
    w.erfasser,
    w.auftrag_id,
    n.netto_damals_kg,
    n.netto_jetzt_kg,
    w.wiege_ts::date - w.eingangsdatum AS lagertage,
        zahl(CASE
            WHEN n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (w.wiege_ts::date - w.eingangsdatum) > 0 THEN 1::numeric - power(n.netto_jetzt_kg / n.netto_damals_kg, 1.0 / (w.wiege_ts::date - w.eingangsdatum)::numeric)
            ELSE NULL::numeric
        END, 6, 1e4)::numeric(10,6) AS rate_pro_tag,
    w.gemessen AND NOT w.sichtbar_schimmel AND n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (w.wiege_ts::date - w.eingangsdatum) > 0 AND n.netto_jetzt_kg <= (n.netto_damals_kg * 1.01) AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AS verwendbar
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT w.brutto_damals_kg - w.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_damals_kg,
            w.brutto_jetzt_kg - w.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_jetzt_kg) n;
comment on view v_verdunstung_messung is
  'Jede Verdunstungswägung mit Netto damals und jetzt, Lagertagen und Tagesrate. '
  'verwendbar: gemessen, ohne sichtbaren Schimmel, positive Nettos, Wiegedatum nach '
  'dem Eingang, Arbeit nicht abgebrochen — und die Palette höchstens 1 % schwerer als '
  'beim Eingang (0056). Ohne Kistenzahl oder ohne hinterlegte Tara gibt es kein Netto '
  'und damit keine Rate (0064). Was nicht verwendbar ist, steht in v_plausibilitaet.';
grant select on v_verdunstung_messung to authenticated;

create or replace view v_wiegung_kennzahl with (security_invoker = true) as
 SELECT w.id,
    w.auftrag_id,
    w.charge_nr,
    c.sorte,
    c.schlag,
    w.eingangsdatum,
    w.wiege_ts,
    w.kisten,
    w.gebindeart,
    w.sichtbar_schimmel,
    w.kuerbisse_pro_kiste,
    w.wiege_ts::date - w.eingangsdatum AS lagertage,
    n.netto_damals_kg,
    n.netto_jetzt_kg,
    zahl((n.netto_jetzt_kg / NULLIF(w.kisten, 0)::numeric), 3, 1e7)::numeric(10,3) AS kg_pro_kiste,
    zahl((n.netto_jetzt_kg / NULLIF(w.kisten * w.kuerbisse_pro_kiste, 0)::numeric), 3, 1e7)::numeric(10,3) AS kg_pro_kuerbis,
    zahl((n.netto_damals_kg - n.netto_jetzt_kg), 2, 1e8)::numeric(10,2) AS verdunstung_kg
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT zahl((w.brutto_damals_kg - w.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette), 2, 1e8)::numeric(10,2) AS netto_damals_kg,
            zahl((w.brutto_jetzt_kg - w.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette), 2, 1e8)::numeric(10,2) AS netto_jetzt_kg) n
  WHERE w.gemessen AND (a.id IS NULL OR a.abgebrochen_ts IS NULL);
comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, die Verdunstung dazwischen '
  '(0062 — vorher verlust_kg), kg je Kiste und je Kürbis. Ohne Kistenzahl oder '
  'hinterlegte Tara gibt es kein Netto (0064).';
grant select on v_wiegung_kennzahl to authenticated;

create or replace view v_auftrag_palette_masse with (security_invoker = true) as
with wiegung as materialized (
  select vw.id,
         zahl(vw.brutto_damals_kg - vw.kisten * g.tara_kg_pro_kiste
              - g.tara_kg_palette, 2, 1e8)::numeric(10,2) as netto_damals_kg,
         vw.eingangsdatum
    from verdunstung_wiegung vw
    left join gebinde g on g.art = vw.gebindeart
), datum_mittel as materialized (
  select charge_nr, eingangsdatum, avg(netto_kg) as netto_mittel
    from v_palette group by charge_nr, eingangsdatum
), charge_mittel as materialized (
  select charge_nr, avg(netto_kg) as netto_mittel,
         avg(brutto_kg - netto_kg) filter (where netto_kg is not null) as tara_mittel
    from v_palette group by charge_nr
), charge_datum as materialized (
  select charge_nr, eingangsdatum_mittel from v_charge_rueckgrat
), zettel as materialized (
  select ap.id,
         coalesce(pe.netto_kg,
                  zahl(ap.brutto_zettel_kg - cm.tara_mittel, 2, 1e8)::numeric(10,2)) as netto_kg,
         (pe.id is not null) as exakt
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join lateral (
      select p.id, p.netto_kg from v_palette p
       where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum
         and p.brutto_kg = ap.brutto_zettel_kg and p.netto_kg is not null
       order by p.id limit 1) pe on true
    left join charge_mittel cm on cm.charge_nr = a.charge_nr
   where ap.brutto_zettel_kg is not null
)
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(w.netto_damals_kg, z.netto_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel) as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) as eingangsdatum,
       case when w.netto_damals_kg is not null then 'gewogen'
            when z.netto_kg is not null and z.exakt then 'zettel'
            when z.netto_kg is not null then 'zettel-charge-tara'
            when p.netto_kg is not null then 'palette'
            when d.netto_mittel is not null then 'datum-mittel'
            when cm.netto_mittel is not null then 'charge-mittel'
            else 'unbekannt' end::text                                                 as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join wiegung w on w.id = ap.wiegung_id
  left join zettel z on z.id = ap.id
  left join v_palette p on p.id = ap.palette_id
  left join datum_mittel d on d.charge_nr = a.charge_nr and d.eingangsdatum = ap.eingangsdatum
  left join charge_mittel cm on cm.charge_nr = a.charge_nr
  left join charge_datum cd on cd.charge_nr = a.charge_nr
 where ap.kisten is null;
comment on view v_auftrag_palette_masse is
  'Netto je gezählter Eingangspalette: gewogen, vom Zettel, aus dem Wareneingang, '
  'oder das Mittel des Eingangstags / der Charge; masse_quelle sagt, welcher Weg es '
  'war. Beim Waschen gezählte Paletten (mit Kisten) stehen nicht hier — ihre Masse '
  'rechnet v_auftrag_wasch_paletten (0061). Ohne Kistenzahl kein gewogenes Netto (0064).';

-- ---------- 3. Ein Strom ohne Messung ist unbekannt, nicht null ---------
-- Jede Stromsumme bekommt das Kennzeichen ihres eigenen Koeffizienten. Was
-- daraus NULL wird, gibt `zahl()` als NULL weiter, und die Oberfläche
-- schreibt „—" statt „0,0 t". Genau so macht es erg_verlust seit jeher.
--
-- Nicht angetastet: `im_haus_heute_kg` und `lager_kg`. Beide sind
-- Eingangsmasse — was hereinkam und nicht ausgelagert ist. Diese Masse ist
-- gemessen, auch wenn niemand weiss, wie viel davon inzwischen verdunstet
-- ist. Ohne Messung ist „noch im Haus" damit eine **obere Schranke**; die
-- Oberfläche sagt das, statt die Zahl zu verschweigen.
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
         case when bool_and(a0_bekannt) then coalesce(sum(sockel_kg), 0)      end as sockel_heute_kg,
         case when bool_and(a_klein_bekannt and a_gross_bekannt)
              then coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'ausgelagert'), 0)
              end                                                             as kanal_ausgelagert_kg,
         case when bool_and(a_fax_bekannt)
              then coalesce(sum(fax_kg) filter (where portion = 'ausgelagert'), 0) end as fax_heute_kg,
         case when bool_and(a_fax_bekannt)
              then coalesce(sum(fax_kg) filter (where portion = 'lager'), 0) end       as fax_erwartet_kg,
         sum(m2) filter (where portion = 'lager')                             as im_haus_heute_kg,
         case when bool_and(a_klein_bekannt and a_gross_bekannt)
              then coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'lager'), 0)
              end                                                             as kanal_im_haus_kg,
         bool_and(r_bekannt and f_bekannt and a0_bekannt and a_fax_bekannt
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
comment on view v_hochrechnung_basis is
  'Je Charge, alles bis heute: Eingang und geliefert (gemessen), ausgelagert '
  '(Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus ausgelagert, in '
  'Eingangskilo), verlust_heute_kg (Verdunstung + Schimmel + Sockel + Fax am '
  'Abgepackten), im_haus_heute_kg (Eingangsmasse, die noch liegt, nach Verdunstung '
  'und Verderb). Keine Prognose. 0064: Jede Stromsumme ist NULL, solange ihr '
  'Koeffizient keine Messung hat — leer ist nicht null; die Kennzeichen daneben '
  'sagen, welche. Ohne Messung ist im_haus_heute_kg die Eingangsmasse, die noch '
  'liegt, und damit eine obere Schranke. Fehlt zu einer Charge jede Kaskadenzeile, '
  'liegt noch alles; fehlt nur die Portion „lager", liegt nichts mehr — bisher '
  'hiess beides „alles".';

-- ---------- 4. Drei Auffälligkeiten, die dem Betrieb fehlten ------------
create or replace view v_plausibilitaet_0064_zusatz with (security_invoker = true) as
-- Paletten ohne Nettogewicht: fehlende Gebindeart, fehlende Tara in den
-- Stammdaten oder fehlende Kistenzahl. Der Eingang der Charge rechnet dann mit
-- dem Mittel der übrigen Paletten weiter (v_charge_rueckgrat) — und hat kein
-- Netto mehr, sobald *keine* Palette der Charge eines hat. Beides sah man
-- bisher nur, wenn man auf der Seite Messungen nachsah.
select 'Tara fehlt'::text as art, null::bigint as auftrag_id, p.charge_nr, c.sorte,
       min(p.eingangsdatum)::timestamptz as start_ts,
       format('%s von %s Paletten der Charge haben kein Nettogewicht (%s kg brutto): %s. %s',
              count(*), r.n_paletten, round(sum(p.brutto_kg)),
              case when bool_or(p.gebindeart is null)      then 'die Gebindeart steht nicht auf der Palette'
                   when bool_or(g.art is null)             then 'diese Gebindeart steht nicht in den Stammdaten'
                   when bool_or(g.tara_kg_pro_kiste is null) then 'für die Gebindeart ist kein Kistengewicht hinterlegt'
                   when bool_or(g.tara_kg_palette is null)   then 'für die Gebindeart ist kein Palettengewicht hinterlegt'
                   else 'die Kistenzahl fehlt' end,
              case when r.n_paletten_mit_netto = 0
                   then 'Damit hat die Charge gar keinen Eingang — sie fehlt in der ganzen Bilanz.'
                   else format('Für sie rechnet der Eingang mit dem Mittel der übrigen: %s der %s kg '
                               || 'Eingang sind hochgerechnet, nicht gewogen.',
                               round(r.eingang_netto_kg - r.eingang_netto_gemessen_kg),
                               round(r.eingang_netto_kg)) end)                        as befund,
       case when bool_or(p.gebindeart is null) then 'Gebindeart am Wareneingang nachtragen.'
            when bool_or(g.art is null) or bool_or(g.tara_kg_pro_kiste is null) or bool_or(g.tara_kg_palette is null)
            then 'Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. '
                 || 'Die Zahlen rechnen sich danach von selbst neu.'
            else 'Kistenzahl der Palette im Wareneingang nachtragen.' end               as rat
  from palette p
  left join gebinde g on g.art = p.gebindeart
  join charge c on c.nr = p.charge_nr
  join v_charge_rueckgrat r on r.charge_nr = p.charge_nr
 where p.brutto_kg - p.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette is null
 group by p.charge_nr, c.sorte, r.n_paletten, r.n_paletten_mit_netto,
          r.eingang_netto_kg, r.eingang_netto_gemessen_kg
union all
-- Mehr ausgeliefert als je hereingekommen: das ist kein Verlustphänomen,
-- sondern eine Lücke im Erntejournal oder eine Lieferung auf der falschen
-- Chargennummer. Die Kaskade fängt es ab, damit die Bilanz aufgeht — und
-- genau deshalb fiel es niemandem auf.
select 'Überzählung', null::bigint, h.charge_nr, h.sorte, h.eingangsdatum_mittel::timestamptz,
       format('%s kg mehr ausgeliefert, als für diese Charge je als Eingang erfasst wurde '
              || '(%s kg Eingang, %s kg geliefert) — das sind %s %% des Eingangs',
              round(h.ueberzaehlung_kg), round(h.eingang_kg), round(h.geliefert_kg),
              round(100 * h.ueberzaehlung_kg / nullif(h.eingang_kg, 0))),
       'Fehlt im Erntejournal eine Palette dieser Charge? Oder ist ein Lieferschein auf '
       || 'die falsche Chargennummer gebucht? Beides lässt sich nachtragen; bis dahin ist '
       || 'die Verlustquote dieser Charge zu hoch, weil ihr Eingang zu klein ist.'
  from v_hochrechnung_basis h
 where h.ueberzaehlung_kg > 0
union all
-- Ein Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag: die
-- Massenrechnung fällt still auf die mittlere Tara der Charge zurück. Die
-- Auffälligkeit von 0060 prüft nur Charge und Brutto und schweigt dann.
select 'Zettelgewicht', ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette '
              || 'dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — gerechnet '
              || 'wird deshalb mit der mittleren Tara der Charge, nicht mit ihrer eigenen.',
              count(*), ap.brutto_zettel_kg, to_char(ap.eingangsdatum, 'DD.MM.YYYY')),
       'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  join charge c on c.nr = a.charge_nr
 where ap.brutto_zettel_kg is not null and ap.eingangsdatum is not null
   and a.abgebrochen_ts is null
   and exists (select 1 from palette p
                where p.charge_nr = a.charge_nr and p.brutto_kg = ap.brutto_zettel_kg)
   and not exists (select 1 from v_palette p
                    where p.charge_nr = a.charge_nr and p.brutto_kg = ap.brutto_zettel_kg
                      and p.eingangsdatum = ap.eingangsdatum and p.netto_kg is not null)
 group by ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg, ap.eingangsdatum;
comment on view v_plausibilitaet_0064_zusatz is
  'Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die '
  'Paletten fehlen im Eingang), eine Charge mit mehr Ausgang als Eingang, und ein '
  'Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag.';
grant select on v_plausibilitaet_0064_zusatz to authenticated;

-- v_plausibilitaet endet seit 0054 mit einer Zusatzsicht — das ist die Stelle,
-- an der neue Auffälligkeiten dazukommen, ohne die grosse Sicht anzufassen.
-- Ihr Rumpf steht hier unverändert aus 0062, mit einer angehängten Zeile.
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
 where g.kg is null and g.anzahl > 0 and g.kaliber_idx = -2
union all
select 'Kistengewicht', wp.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '
              || 'die Menge dieser Arbeit damit auch',
              wp.n_paletten, wp.kisten,
              case when a.kaliber_von_g is not null
                   then format('ein Band %s–%s g wurde beim Sortieren noch nie mitgezählt',
                               a.kaliber_von_g, a.kaliber_bis_g)
                   else 'für dieses Kaliber wurde beim Sortieren noch nie mitgezählt' end),
       case when a.kaliber_von_g is not null
            then 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht, oder beim '
                 || 'nächsten Sortierlauf mit diesem Band die gefüllten Kisten zählen.'
            else 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '
                 || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.' end
  from v_auftrag_wasch_paletten wp
  join auftrag a on a.id = wp.auftrag_id
  join charge c on c.nr = a.charge_nr
 where wp.kg is null and wp.kisten > 0
union all
-- 0062: Lieferungen, die noch nicht passiert sind
select 'Lieferung in der Zukunft', null::bigint, l.charge_nr, l.sorte, l.datum::timestamptz,
       format('Lieferschein über %s kg mit Datum %s — das liegt nach heute (%s). '
              || 'Die Menge zählt erst ab diesem Tag in Ausgang und Bestand.',
              round(l.masse_kg), to_char(l.datum, 'DD.MM.YYYY'), to_char(heute(), 'DD.MM.YYYY')),
       'Stimmt das Datum? Ein vordatierter Lieferschein ist in Ordnung — die Zahl '
       || 'erscheint von selbst, sobald der Tag da ist. Ein Zahlendreher gehört korrigiert.'
  from v_lieferung_masse l
 where l.datum > heute() and l.masse_kg is not null and l.masse_kg > 0
union all
select art, auftrag_id, charge_nr, sorte, start_ts, befund, rat
  from v_plausibilitaet_0064_zusatz;

-- ---------- 5. Eine Lieferung ohne Menge ist keine Lieferung ------------
-- kg darf fehlen, solange die Kistenzahl da ist (dann rechnet
-- v_lieferung_masse mit dem mittleren Kistengewicht). Beides zu lassen geht
-- nicht: die Zeile zählt dann mit 0 kg in den Ausgang.
alter table lieferung drop constraint if exists lieferung_hat_menge;
alter table lieferung add constraint lieferung_hat_menge
  check (kg is not null or kisten is not null) not valid;

-- ---------- 6. Stand der Datenbank --------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 64 $$;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;
