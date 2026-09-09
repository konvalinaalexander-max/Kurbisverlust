-- =====================================================================
-- 0065 — Entsorgtes verlässt das Lager
--
-- Die Lieferungen kennen drei Bücher: verkauft, in den Nebenkanal (Tiere,
-- zu klein / zu gross) und entsorgt (Kompost). Die Kaskade kannte zwei.
-- Was als Kompost weggefahren wurde, zählte damit im Ausgang **und** lag
-- gleichzeitig weiter im Lager — dieselbe Ware zweimal.
--
-- Es ist derselbe Fehler, den 0062 für das zweite Buch behoben hat, nur
-- für das dritte. In der Demosaison ist er folgenlos, weil dort nichts
-- entsorgt wird; das Prüfwerk hat ihn an einem gebauten Fall mit 500 kg
-- Kompost gemessen (pruefwerk/sonden/07_szenarien.mjs → S5).
--
-- WIE ENTSORGTE WARE GERECHNET WIRD
--
-- Bei verkaufter Ware rechnet die Kaskade rückwärts durch die ganze
-- Ausbeute: hinter 100 kg Lieferung steckt mehr Eingangsware, weil davor
-- Wasser entwichen, Faules aussortiert und zu Kleines abgezweigt wurde.
--
-- Bei entsorgter Ware gilt das nicht. Sie ist selbst das Ergebnis dieser
-- Ursachen — Faules, das den Betrieb verlässt. Zurückgerechnet wird
-- deshalb nur die Verdunstung: 100 kg Kompost nach 200 Tagen waren beim
-- Eingang 100 / (1−r)^200 kg. Diese Eingangsmasse wird der liegenden
-- Portion abgezogen; sie zählt als Verdunstung (was an Wasser entwich)
-- und als Faules (der Rest, der weggefahren wurde).
--
-- Der Verlust wächst dadurch nicht doppelt: Für die entsorgte Masse
-- rechnet das Verderbsmodell nicht noch einmal, weil sie aus der
-- liegenden Portion bereits heraus ist. An dieser Stelle schlägt eine
-- Beobachtung eine Hochrechnung — genau so, wie es sein soll.
--
-- Keine neue Ursache, keine neue Spalte, kein neuer Bildschirm: Entsorgtes
-- erscheint dort, wo es hingehört, unter Faulem.
-- =====================================================================

-- ---------- 1. Das dritte Buch kommt in die Kohorten --------------------
-- Bis hierher hat v_lieferung_kohorte nur „verkauf" und „marge" gezählt. Das
-- war die Stelle, an der die entsorgte Ware verschwand: Sie stand im Ausgang
-- (v_saisonbilanz nimmt dort alle Bücher), aber die Kaskade sah sie nie.
create or replace view v_lieferung_kohorte with (security_invoker = true) as
with lief as (
  select l.id, l.datum, l.buch, l.masse_kg, c.charge_nr, c.anteil
    from v_lieferung_masse l
    cross join lateral (
      select l.charge_nr as charge_nr, 1::numeric as anteil where l.charge_nr is not null
      union all
      select r.charge_nr, r.eingang_netto_kg / sum(r.eingang_netto_kg) over ()
        from v_charge_rueckgrat r
       where l.charge_nr is null and r.sorte = l.sorte and r.eingang_netto_kg > 0
    ) c
   where l.masse_kg is not null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge', 'verlust')
     and l.datum <= heute()
  union all
  -- Der Vorlauf (AB-07): was vor dem Erfassungsbeginn schon ausgeliefert war.
  select -cv.charge_nr, coalesce(
           (select nullif(wert #>> '{}', '')::date from einstellung where schluessel = 'erfassungsbeginn'),
           r.letzter_eingang),
         'verkauf', cv.ausgang_vor_app_kg, cv.charge_nr, 1
    from charge_vorlauf cv
    join v_charge_rueckgrat r on r.charge_nr = cv.charge_nr
   where cv.ausgang_vor_app_kg > 0
)
select f.charge_nr, k.eingangsdatum as kohorte, f.buch,
       zahl(sum(f.masse_kg * f.anteil * k.anteil), 2, 1e12)::numeric(14,2)      as masse_kg,
       zahl(sum(f.masse_kg * f.anteil * k.anteil * greatest(f.datum - k.eingangsdatum, 0))
            / nullif(sum(f.masse_kg * f.anteil * k.anteil), 0), 1, 1e5)::numeric(8,1) as alter_tage,
       count(distinct f.id)::int                                                as n_lieferungen,
       min(f.datum)                                                             as von,
       max(f.datum)                                                             as bis
  from lief f
  join v_kohorte_anteil k on k.charge_nr = f.charge_nr
 group by f.charge_nr, k.eingangsdatum, f.buch;
comment on view v_lieferung_kohorte is
  'Gelieferte Masse je Charge, Eingangstag und Buch (verkauf, marge, verlust), '
  'mit dem massegewichteten Alter am Liefertag; nur Lieferungen bis heute(). '
  'Grundlage der Rückrechnung in der Kaskade. 0065: das dritte Buch ist dabei — '
  'was in den Kompost ging, hat den Betrieb verlassen und gehört aus dem Lager.';
grant select on v_lieferung_kohorte to authenticated;

-- ---------- 2. Die Kaskade mit drei Portionen ---------------------------
drop materialized view if exists mv_kaskade cascade;
create materialized view mv_kaskade as
WITH modell AS MATERIALIZED (
         SELECT v_schimmel_modell.n,
            v_schimmel_modell.c_chargen,
            v_schimmel_modell.t_min,
            v_schimmel_modell.t_max,
            v_schimmel_modell.k,
            v_schimmel_modell.ln_lambda,
            v_schimmel_modell.lambda,
            v_schimmel_modell.x_mittel,
            v_schimmel_modell.sxx,
            v_schimmel_modell.smearing,
            v_schimmel_modell.ln_lambda_korrigiert,
            v_schimmel_modell.sigma2,
            v_schimmel_modell.var_achse,
            v_schimmel_modell.var_k,
            v_schimmel_modell.kov_achse_k,
            v_schimmel_modell.t_faktor,
            v_schimmel_modell.brauchbar,
            v_schimmel_modell.selektions_versatz,
            v_schimmel_modell.sockel,
            v_schimmel_modell.sockel_unten,
            v_schimmel_modell.sockel_oben,
            v_schimmel_modell.sockel_nachweis,
            v_schimmel_modell.sockel_schwelle,
            v_schimmel_modell.sockel_var
           FROM v_schimmel_modell
        ), kurve AS MATERIALIZED (
         SELECT v_schimmel_kurve.von,
            v_schimmel_kurve.anteil_mono,
            v_schimmel_kurve.n
           FROM v_schimmel_kurve
          WHERE (v_schimmel_kurve.n > 0)
        ), kohorten AS MATERIALIZED (
         SELECT k_1.charge_nr,
            k_1.eingangsdatum,
            k_1.anteil,
            (b.eingang_kg * k_1.anteil) AS eingang_kg
           FROM (v_kohorte_anteil k_1
             JOIN v_kaskade_basis b ON ((b.charge_nr = k_1.charge_nr)))
        ), lieferungen AS MATERIALIZED (
         -- 0062: beide Bücher. Was als Tierfutter oder in den Nebenkanal ging,
         -- hat den Betrieb verlassen — es darf nicht weiter altern und nicht
         -- ein zweites Mal im Bestand stehen. Je Charge und Eingangstag eine
         -- Zeile, das Alter massegewichtet über die Bücher.
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            (sum((v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, (0)::numeric)))
             / NULLIF(sum(v_lieferung_kohorte.masse_kg), (0)::numeric)) AS alter_tage,
            (sum(v_lieferung_kohorte.n_lieferungen))::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE (v_lieferung_kohorte.buch = ANY (ARRAY['verkauf'::text, 'marge'::text]))
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), entsorgt_lief AS (
         -- 0065: Das dritte Buch. Was in den Kompost ging, hat den Betrieb
         -- verlassen — es liegt nicht mehr da und ist nicht mehr zu verkaufen.
         -- Bis 0064 sah die Kaskade es nicht: die Ware zählte im Ausgang und
         -- lag gleichzeitig weiter im Lager.
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            (sum((v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, (0)::numeric)))
             / NULLIF(sum(v_lieferung_kohorte.masse_kg), (0)::numeric)) AS alter_tage,
            (sum(v_lieferung_kohorte.n_lieferungen))::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE (v_lieferung_kohorte.buch = 'verlust'::text)
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), koeff AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.eingang_kg,
            b.stichtag,
            LEAST(GREATEST(COALESCE(kv.mittel, (0)::numeric), (0)::numeric), 0.05) AS r,
            (kv.mittel IS NOT NULL) AS r_bekannt,
            kv.n AS r_n,
            kv.basis AS r_basis,
            LEAST(GREATEST(COALESCE(ka.mittel, (0)::numeric), (0)::numeric), (1)::numeric) AS a_klein,
            (ka.mittel IS NOT NULL) AS a_klein_bekannt,
            ka.n AS klein_n,
            ka.basis AS klein_basis,
            LEAST(GREATEST(COALESCE(kn.mittel, (0)::numeric), (0)::numeric), (1)::numeric) AS a_gross,
            (kn.mittel IS NOT NULL) AS a_gross_bekannt,
            kn.n AS gross_n,
            kn.basis AS gross_basis,
            LEAST(GREATEST(COALESCE(kf.mittel, (0)::numeric), (0)::numeric), (1)::numeric) AS a_fax,
            (kf.mittel IS NOT NULL) AS a_fax_bekannt,
            kf.n AS fax_n,
            kf.basis AS fax_basis
           FROM ((((v_kaskade_basis b
             LEFT JOIN v_koeff_verdunstung kv ON ((kv.sorte = b.sorte)))
             LEFT JOIN v_koeff_ausschuss ka ON ((ka.sorte = b.sorte)))
             LEFT JOIN v_koeff_nebenkanal kn ON ((kn.sorte = b.sorte)))
             LEFT JOIN v_koeff_fax kf ON ((kf.sorte = b.sorte)))
          WHERE (b.eingang_kg > (0)::numeric)
        ), koeff_norm AS (
         SELECT k_1.charge_nr,
            k_1.sorte,
            k_1.schlag,
            k_1.eingang_kg,
            k_1.stichtag,
            k_1.r,
            k_1.r_bekannt,
            k_1.r_n,
            k_1.r_basis,
            k_1.a_klein,
            k_1.a_klein_bekannt,
            k_1.klein_n,
            k_1.klein_basis,
            k_1.a_gross,
            k_1.a_gross_bekannt,
            k_1.gross_n,
            k_1.gross_basis,
            k_1.a_fax,
            k_1.a_fax_bekannt,
            k_1.fax_n,
            k_1.fax_basis,
            (k_1.a_klein / n.f) AS a_klein_n,
            (k_1.a_gross / n.f) AS a_gross_n
           FROM (koeff k_1
             CROSS JOIN LATERAL ( SELECT GREATEST((COALESCE(k_1.a_klein, (0)::numeric) + COALESCE(k_1.a_gross, (0)::numeric)), (1)::numeric) AS f) n)
        ), roh AS (
         SELECT k_1.charge_nr,
            'ausgelagert'::text AS portion,
            l.kohorte,
            (l.masse_kg)::numeric AS geliefert_kg,
            COALESCE(l.alter_tage, (0)::numeric) AS alter_tage,
            NULL::numeric AS eingang_kohorte_kg,
            l.n_lieferungen
           FROM (koeff_norm k_1
             JOIN lieferungen l ON ((l.charge_nr = k_1.charge_nr)))
        UNION ALL
         SELECT k_1.charge_nr,
            'entsorgt'::text,
            e.kohorte,
            (e.masse_kg)::numeric,
            COALESCE(e.alter_tage, (0)::numeric),
            NULL::numeric,
            e.n_lieferungen
           FROM (koeff_norm k_1
             JOIN entsorgt_lief e ON ((e.charge_nr = k_1.charge_nr)))
        UNION ALL
         SELECT k_1.charge_nr,
            'lager'::text,
            c.eingangsdatum,
            NULL::numeric,
            GREATEST(((k_1.stichtag - c.eingangsdatum))::numeric, (0)::numeric) AS "greatest",
            c.eingang_kg,
            0
           FROM (koeff_norm k_1
             JOIN kohorten c ON ((c.charge_nr = k_1.charge_nr)))
        ), teile AS (
         SELECT k_1.charge_nr,
            k_1.sorte,
            k_1.schlag,
            k_1.eingang_kg,
            k_1.stichtag,
            k_1.r,
            k_1.r_bekannt,
            k_1.r_n,
            k_1.r_basis,
            k_1.a_klein,
            k_1.a_klein_bekannt,
            k_1.klein_n,
            k_1.klein_basis,
            k_1.a_gross,
            k_1.a_gross_bekannt,
            k_1.gross_n,
            k_1.gross_basis,
            k_1.a_fax,
            k_1.a_fax_bekannt,
            k_1.fax_n,
            k_1.fax_basis,
            k_1.a_klein_n,
            k_1.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            (ln(GREATEST(t.alter_tage, (1)::numeric)) - COALESCE(m.x_mittel, (0)::numeric)) AS u,
                CASE
                    WHEN m.brauchbar THEN (m.ln_lambda_korrigiert + (m.k * ln(GREATEST(t.alter_tage, (1)::numeric))))
                    ELSE NULL::numeric
                END AS eta,
            m.brauchbar AS modell_gilt,
            (m.brauchbar AND (t.alter_tage > m.t_max)) AS f_extrapoliert,
                CASE
                    WHEN m.brauchbar THEN m.c_chargen
                    ELSE s.n
                END AS f_n,
            s.anteil_mono AS f_treppe,
            (m.brauchbar OR (( SELECT count(*) AS count
                   FROM kurve) > 0)) AS f_bekannt,
                CASE
                    WHEN m.brauchbar THEN COALESCE(m.sockel, (0)::numeric)
                    ELSE (0)::numeric
                END AS a0,
            m.brauchbar AS a0_bekannt,
                CASE
                    WHEN m.brauchbar THEN COALESCE(m.sockel_var, (0)::numeric)
                    ELSE (0)::numeric
                END AS a0_var
           FROM (((koeff_norm k_1
             JOIN roh t ON ((t.charge_nr = k_1.charge_nr)))
             CROSS JOIN modell m)
             LEFT JOIN LATERAL ( SELECT c.anteil_mono,
                    c.n
                   FROM kurve c
                  WHERE ((c.von)::numeric <= t.alter_tage)
                  ORDER BY c.von DESC
                 LIMIT 1) s ON (true))
        ), mit_f AS (
         SELECT t.charge_nr,
            t.sorte,
            t.schlag,
            t.eingang_kg,
            t.stichtag,
            t.r,
            t.r_bekannt,
            t.r_n,
            t.r_basis,
            t.a_klein,
            t.a_klein_bekannt,
            t.klein_n,
            t.klein_basis,
            t.a_gross,
            t.a_gross_bekannt,
            t.gross_n,
            t.gross_basis,
            t.a_fax,
            t.a_fax_bekannt,
            t.fax_n,
            t.fax_basis,
            t.a_klein_n,
            t.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            t.u,
            t.eta,
            t.modell_gilt,
            t.f_extrapoliert,
            t.f_n,
            t.f_treppe,
            t.f_bekannt,
            t.a0,
            t.a0_bekannt,
            t.a0_var,
                CASE
                    WHEN t.modell_gilt THEN LEAST(GREATEST(((1)::numeric - exp((- exp(LEAST(GREATEST(t.eta, ('-40'::integer)::numeric), (3)::numeric))))), (0)::numeric), (1)::numeric)
                    ELSE LEAST(GREATEST(COALESCE(t.f_treppe, (0)::numeric), (0)::numeric), (1)::numeric)
                END AS f
           FROM teile t
        ), anteil AS (
         SELECT x.charge_nr,
            x.sorte,
            x.schlag,
            x.eingang_kg,
            x.stichtag,
            x.r,
            x.r_bekannt,
            x.r_n,
            x.r_basis,
            x.a_klein,
            x.a_klein_bekannt,
            x.klein_n,
            x.klein_basis,
            x.a_gross,
            x.a_gross_bekannt,
            x.gross_n,
            x.gross_basis,
            x.a_fax,
            x.a_fax_bekannt,
            x.fax_n,
            x.fax_basis,
            x.a_klein_n,
            x.a_gross_n,
            x.portion,
            x.kohorte,
            x.geliefert_kg,
            x.alter_tage,
            x.eingang_kohorte_kg,
            x.n_lieferungen,
            x.u,
            x.eta,
            x.modell_gilt,
            x.f_extrapoliert,
            x.f_n,
            x.f_treppe,
            x.f_bekannt,
            x.a0,
            x.a0_bekannt,
            x.a0_var,
            x.f,
            GREATEST(((((power(((1)::numeric - x.r), x.alter_tage) * ((1)::numeric - x.a0)) * ((1)::numeric - x.f)) * (((1)::numeric - x.a_klein_n) - x.a_gross_n)) * ((1)::numeric - x.a_fax)), 0.25) AS verkaufsfaehig_anteil,
            -- 0065: Für entsorgte Ware zählt nur die Verdunstung zurück. Sie ist
            -- Faules, das den Betrieb verlassen hat — die Ausbeute-Faktoren
            -- (Sockel, Verderb, Sortierung, Fax) gelten für sie nicht: sie ist
            -- selbst das Ergebnis dieser Ursachen, nicht ihr Ausgangspunkt.
            GREATEST(power(((1)::numeric - x.r), x.alter_tage), 0.25) AS verdunstungs_anteil
           FROM mit_f x
        ), ausgelagert AS (
         -- Ausgelagert und entsorgt teilen dieselbe Form: aus der Masse, die
         -- den Betrieb verlassen hat, wird die Eingangsmasse dahinter
         -- zurückgerechnet. Nur der Anteil unterscheidet sich.
         SELECT a.*,
                CASE WHEN a.portion = 'entsorgt'::text
                     THEN (a.geliefert_kg / a.verdunstungs_anteil)
                     ELSE (a.geliefert_kg / a.verkaufsfaehig_anteil) END AS m0,
                (0)::numeric AS ueberzaehlung_kg
           FROM anteil a
          WHERE (a.portion = ANY (ARRAY['ausgelagert'::text, 'entsorgt'::text]))
        ), lager AS (
         -- Was liegt, ist der Eingang des Tages minus alles, was ihn an diesem
         -- Tag schon verlassen hat — verkauft, in den Nebenkanal, in den Kompost.
         SELECT a.*,
                GREATEST((a.eingang_kohorte_kg - COALESCE(x.m0, (0)::numeric)), (0)::numeric) AS m0,
                GREATEST((COALESCE(x.m0, (0)::numeric) - a.eingang_kohorte_kg), (0)::numeric) AS ueberzaehlung_kg
           FROM (anteil a
             LEFT JOIN ( SELECT ausgelagert.charge_nr,
                    ausgelagert.kohorte,
                    sum(ausgelagert.m0) AS m0
                   FROM ausgelagert
                  GROUP BY ausgelagert.charge_nr, ausgelagert.kohorte) x
               ON (((x.charge_nr = a.charge_nr) AND (x.kohorte = a.kohorte))))
          WHERE (a.portion = 'lager'::text)
        ), alle AS (
         SELECT * FROM ausgelagert
        UNION ALL
         SELECT * FROM lager
        ), kaskade AS (
         SELECT t.charge_nr,
            t.sorte,
            t.schlag,
            t.eingang_kg,
            t.stichtag,
            t.r,
            t.r_bekannt,
            t.r_n,
            t.r_basis,
            t.a_klein,
            t.a_klein_bekannt,
            t.klein_n,
            t.klein_basis,
            t.a_gross,
            t.a_gross_bekannt,
            t.gross_n,
            t.gross_basis,
            t.a_fax,
            t.a_fax_bekannt,
            t.fax_n,
            t.fax_basis,
            t.a_klein_n,
            t.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            t.u,
            t.eta,
            t.modell_gilt,
            t.f_extrapoliert,
            t.f_n,
            t.f_treppe,
            t.f_bekannt,
            t.a0,
            t.a0_bekannt,
            t.a0_var,
            t.f,
            t.verkaufsfaehig_anteil,
            t.m0,
            t.ueberzaehlung_kg,
            (t.m0 * power(((1)::numeric - t.r), t.alter_tage)) AS m1,
            (((- t.m0) * t.alter_tage) * power(((1)::numeric - t.r), GREATEST((t.alter_tage - (1)::numeric), (0)::numeric))) AS d_m1_r,
                CASE
                    WHEN t.modell_gilt THEN (((1)::numeric - t.f) * exp(LEAST(GREATEST(t.eta, ('-40'::integer)::numeric), (3)::numeric)))
                    ELSE (0)::numeric
                END AS d_f_eta
           FROM alle t
          WHERE ((t.m0 > (0)::numeric) OR (t.ueberzaehlung_kg > (0)::numeric))
        )
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    m0,
    m1,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric
         ELSE ((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) END AS m2,
    r,
    f,
    a0,
    a_klein_n,
    a_gross_n,
    a_fax,
    u,
    d_m1_r,
    d_f_eta,
    modell_gilt,
    f_extrapoliert,
    r_n,
    r_basis,
    klein_n,
    klein_basis,
    gross_n,
    gross_basis,
    f_n,
    fax_n,
    fax_basis,
    r_bekannt,
    f_bekannt,
    a_klein_bekannt,
    a_gross_bekannt,
    a0_bekannt,
    a0_var,
    a_fax_bekannt,
    (m0 - m1) AS verdunstung_kg,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE (m1 * a0) END AS sockel_kg,
    -- 0065: Bei entsorgter Ware ist das Faule beobachtet, nicht gerechnet:
    -- was in den Kompost ging, ist genau die Masse des Lieferscheins, um die
    -- Verdunstung zurückgerechnet. Das Modell rechnet für diese Masse nicht
    -- noch einmal — sie ist aus der liegenden Portion bereits abgezogen.
    CASE WHEN portion = 'entsorgt'::text THEN m1
         ELSE ((m1 * ((1)::numeric - a0)) * f) END AS schimmel_kg,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE (((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * a_klein_n) END AS klein_kg,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE (((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * a_gross_n) END AS nebenkanal_kg,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE ((((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * (((1)::numeric - a_klein_n) - a_gross_n)) * a_fax) END AS fax_kg,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE ((((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * (((1)::numeric - a_klein_n) - a_gross_n)) * ((1)::numeric - a_fax)) END AS verkaufsfaehig_kg,
    kohorte,
    CASE WHEN portion = 'entsorgt'::text THEN (0)::numeric ELSE geliefert_kg END AS geliefert_kg,
    ueberzaehlung_kg,
    CASE WHEN portion = 'entsorgt'::text THEN 0 ELSE n_lieferungen END AS n_lieferungen,
    verkaufsfaehig_anteil
   FROM kaskade k
 with no data;
-- Der eindeutige Index ist Pflicht: ohne ihn kann die Sicht nicht nebenläufig
-- erneuert werden, und das Rechenwerk erneuert sie in Schritt 3.
create unique index if not exists mv_kaskade_pk
  on mv_kaskade (charge_nr, portion, coalesce(kohorte, '1900-01-01'::date));
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);
grant select on mv_kaskade to authenticated;
comment on materialized view mv_kaskade is
  'Die Massenkaskade je Charge, Eingangstag und Portion. Drei Portionen: '
  '„ausgelagert" ist die Eingangsmasse hinter den verkauften und in den '
  'Nebenkanal gegangenen Lieferungen, „entsorgt" die hinter dem Kompost '
  '(0065 — nur um die Verdunstung zurückgerechnet, weil entsorgte Ware selbst '
  'das Faule ist), „lager" der Rest, der noch liegt. Je Portion die Ströme '
  'Verdunstung, Sockel, Schimmel, zu klein, Nebenkanal, Fax und verkaufsfähig; '
  'sie summieren sich zu m0. Ohne Messung ist der Koeffizient 0 und das '
  'Kennzeichen daneben falsch — wer die Ströme summiert, muss es lesen.';


-- =====================================================================
-- Was der Kaskadenneubau mitgenommen hat
-- =====================================================================
-- `drop materialized view mv_kaskade cascade` reisst alles mit, was auf ihr
-- steht — einundzwanzig Sichten und gespeicherte Ergebnisse. Sie stehen hier
-- unverändert wieder, in der Reihenfolge ihrer Abhängigkeiten. Zwei davon
-- sind von Hand geschrieben (v_hochrechnung_basis und die Auffälligkeiten aus
-- 0064) und stehen so, wie sie dort standen; die übrigen sind die Fassung,
-- die die Datenbank vor dieser Migration hatte.
--
-- Das ist derselbe Weg, den 0062 gegangen ist. Er ist lang, aber ehrlich:
-- Wer die Migrationen liest, sieht jede Sicht in ihrer gültigen Fassung, und
-- der Prüfstand vergleicht am Ende Fingerabdruck gegen Fingerabdruck.

create materialized view erg_verlauf as
WITH modell AS MATERIALIZED (
         SELECT v_schimmel_modell.n,
            v_schimmel_modell.c_chargen,
            v_schimmel_modell.t_min,
            v_schimmel_modell.t_max,
            v_schimmel_modell.k,
            v_schimmel_modell.ln_lambda,
            v_schimmel_modell.lambda,
            v_schimmel_modell.x_mittel,
            v_schimmel_modell.sxx,
            v_schimmel_modell.smearing,
            v_schimmel_modell.ln_lambda_korrigiert,
            v_schimmel_modell.sigma2,
            v_schimmel_modell.var_achse,
            v_schimmel_modell.var_k,
            v_schimmel_modell.kov_achse_k,
            v_schimmel_modell.t_faktor,
            v_schimmel_modell.brauchbar,
            v_schimmel_modell.selektions_versatz,
            v_schimmel_modell.sockel,
            v_schimmel_modell.sockel_unten,
            v_schimmel_modell.sockel_oben,
            v_schimmel_modell.sockel_nachweis,
            v_schimmel_modell.sockel_schwelle,
            v_schimmel_modell.sockel_var
           FROM v_schimmel_modell
        ), kurve AS MATERIALIZED (
         SELECT v_schimmel_kurve.von,
            v_schimmel_kurve.anteil_mono
           FROM v_schimmel_kurve
          WHERE v_schimmel_kurve.n > 0
        ), wochen AS MATERIALIZED (
         SELECT x.woche,
            x.bis
           FROM ( SELECT w_1.w::date AS woche,
                    (w_1.w + '6 days'::interval)::date AS bis
                   FROM generate_series(date_trunc('week'::text, COALESCE(( SELECT min(palette.eingangsdatum) AS min
                           FROM palette), heute())::timestamp with time zone)::date::timestamp with time zone, date_trunc('week'::text, stichtag()::timestamp with time zone)::date::timestamp with time zone, '7 days'::interval) w_1(w)
                UNION
                 SELECT date_trunc('week'::text, heute()::timestamp with time zone)::date AS date_trunc,
                    heute() AS heute) x
        ), portionen AS MATERIALIZED (
         SELECT k.charge_nr,
            k.sorte,
            k.portion,
            k.kohorte,
            k.m0,
            k.r,
            k.a0,
            k.modell_gilt,
                CASE
                    WHEN k.portion = 'ausgelagert'::text THEN k.kohorte + round(k.alter_tage)::integer
                    ELSE NULL::date
                END AS liefertag,
                CASE
                    WHEN k.portion = 'ausgelagert'::text THEN k.fax_kg
                    ELSE 0::numeric
                END AS fax_kg
           FROM mv_kaskade k
          WHERE k.m0 > 0::numeric AND k.kohorte IS NOT NULL
        ), f_je_tag AS MATERIALIZED (
         SELECT gs.t,
                CASE
                    WHEN gs.t <= 0 THEN 0::numeric
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(gs.t::numeric, 1::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 1::numeric)
                    ELSE LEAST(GREATEST(COALESCE(( SELECT c.anteil_mono
                       FROM kurve c
                      WHERE c.von <= gs.t
                      ORDER BY c.von DESC
                     LIMIT 1), 0::numeric), 0::numeric), 1::numeric)
                END AS f
           FROM generate_series(0, GREATEST(COALESCE((( SELECT max(w_1.bis) AS max
                   FROM wochen w_1)) - (( SELECT min(p.kohorte) AS min
                   FROM portionen p)), 0), 0)) gs(t)
             CROSS JOIN modell m
        ), je_woche AS (
         SELECT w_1.woche,
            w_1.bis,
            p.sorte,
            p.m0 * (1::numeric - power(1::numeric - p.r, x.t::numeric)) AS verdunstung_kg,
            p.m0 * power(1::numeric - p.r, x.t::numeric) * p.a0 AS sockel_kg,
            p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0) * f.f AS schimmel_kg,
                CASE
                    WHEN p.liefertag IS NOT NULL AND p.liefertag <= w_1.bis THEN p.fax_kg
                    ELSE 0::numeric
                END AS fax_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0 - (1::numeric - p.a0) * f.f)
                    ELSE 0::numeric
                END AS im_haus_kg
           FROM wochen w_1
             JOIN portionen p ON p.kohorte <= w_1.bis
             CROSS JOIN LATERAL ( SELECT GREATEST(LEAST(w_1.bis, COALESCE(p.liefertag, w_1.bis)) - p.kohorte, 0) AS t) x
             JOIN f_je_tag f ON f.t = x.t
        ), verlust AS (
         SELECT je_woche.woche,
            je_woche.bis,
            je_woche.sorte,
            sum(je_woche.verdunstung_kg) AS verdunstung_kg,
            sum(je_woche.sockel_kg) AS sockel_kg,
            sum(je_woche.schimmel_kg) AS schimmel_kg,
            sum(je_woche.fax_kg) AS fax_kg,
            sum(je_woche.im_haus_kg) AS im_haus_kg
           FROM je_woche
          GROUP BY GROUPING SETS ((je_woche.woche, je_woche.bis, je_woche.sorte), (je_woche.woche, je_woche.bis))
        ), eingang AS (
         SELECT w_1.woche,
            w_1.bis,
            p.sorte,
            sum(p.netto_kg) AS kg
           FROM wochen w_1
             JOIN ( SELECT v_1.eingangsdatum,
                    c.sorte,
                    v_1.netto_kg
                   FROM v_palette v_1
                     JOIN charge c ON c.nr = v_1.charge_nr) p ON p.eingangsdatum <= w_1.bis
          GROUP BY GROUPING SETS ((w_1.woche, w_1.bis, p.sorte), (w_1.woche, w_1.bis))
        ), ausgang AS (
         SELECT w_1.woche,
            w_1.bis,
            l.sorte,
            sum(l.masse_kg) AS kg
           FROM wochen w_1
             JOIN ( SELECT l_1.datum,
                    COALESCE(l_1.sorte, c.sorte) AS sorte,
                    l_1.masse_kg
                   FROM v_lieferung_masse l_1
                     LEFT JOIN charge c ON c.nr = l_1.charge_nr
                  WHERE l_1.masse_kg IS NOT NULL
                UNION ALL
                 SELECT COALESCE(( SELECT NULLIF(einstellung.wert #>> '{}'::text[], ''::text)::date AS "nullif"
                           FROM einstellung
                          WHERE einstellung.schluessel = 'erfassungsbeginn'::text), r.letzter_eingang) AS "coalesce",
                    r.sorte,
                    cv.ausgang_vor_app_kg
                   FROM charge_vorlauf cv
                     JOIN v_charge_rueckgrat r ON r.charge_nr = cv.charge_nr
                  WHERE cv.ausgang_vor_app_kg > 0::numeric) l ON l.datum <= w_1.bis
          GROUP BY GROUPING SETS ((w_1.woche, w_1.bis, l.sorte), (w_1.woche, w_1.bis))
        )
 SELECT w.woche,
    w.bis,
    w.bis > heute() AS prognose,
    s.sorte,
    zahl(COALESCE(e.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS eingang_kum_kg,
    zahl(COALESCE(a.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgang_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_kum_kg,
    zahl(COALESCE(v.schimmel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_kum_kg,
    zahl(COALESCE(v.sockel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS sockel_kum_kg,
    zahl(COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric) + COALESCE(v.schimmel_kg, 0::numeric) + COALESCE(v.sockel_kg, 0::numeric) + COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_kum_kg,
    zahl(COALESCE(v.im_haus_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_kg
   FROM wochen w
     CROSS JOIN ( SELECT DISTINCT verlust.sorte
           FROM verlust) s
     LEFT JOIN verlust v ON v.bis = w.bis AND NOT v.sorte IS DISTINCT FROM s.sorte
     LEFT JOIN eingang e ON e.bis = w.bis AND NOT e.sorte IS DISTINCT FROM s.sorte
     LEFT JOIN ausgang a ON a.bis = w.bis AND NOT a.sorte IS DISTINCT FROM s.sorte
with no data;
create unique index if not exists erg_verlauf_pk ON public.erg_verlauf USING btree (bis, COALESCE(sorte, ''::text));
create index if not exists erg_verlauf_woche ON public.erg_verlauf USING btree (woche);
comment on materialized view erg_verlauf is
  'Je Woche (und je Sorte; sorte NULL = alles), mit einer Stützstelle genau auf heute() (0062): Eingang und Ausgang kumuliert (gemessen, Ausgang: alle Lieferungen), der Verlust kumuliert (gerechnet, bis heute), danach als Prognose bis zum Saisonende (prognose = true). im_haus_kg: je Portion, was nach Verdunstung und Verderb noch da ist, solange sie nicht ausgeliefert ist. schimmel_kum_kg und sockel_kum_kg stehen getrennt: der Sockel war nie faul (0062).';

create view v_hochrechnung_basis with (security_invoker = true) as
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
grant select on v_hochrechnung_basis to authenticated;

create materialized view erg_charge as
SELECT charge_nr,
    schlag,
    sorte,
    eingang_kg,
    n_paletten,
    eingangsdatum_mittel,
    ausgelagert_kg,
    alter_ausgelagert,
    lager_kg,
    alter_lager,
    alter_lager_heute,
    weg2_anteil,
    stichtag,
    n_paletten_mit_netto,
    ueberzaehlung_kg,
    sortiert_kg,
    gewaschen_kg,
    wartet_kg,
    anteil_gewaschen,
    alter_band,
    am_band_kg,
    eingangsdatum_rest,
    rest_alter_aus_zaehlung,
    eingang_von,
    eingang_bis,
    n_eingangstage,
    rest_von,
    rest_bis,
    n_rest_paletten,
    n_rest_kohorten,
    alter_lager_von,
    alter_lager_bis,
    geliefert_kg,
    verkaufsfaehig_lager_kg,
    n_lieferungen,
    verdunstung_heute_kg,
    schimmel_heute_kg,
    sockel_heute_kg,
    fax_heute_kg,
    verlust_heute_kg,
    kanal_ausgelagert_kg,
    fax_erwartet_kg,
    im_haus_heute_kg,
    kanal_im_haus_kg,
    verlust_bekannt,
    verdunstung_bekannt,
    schimmel_bekannt,
    sockel_nachgewiesen,
    fax_bekannt,
    kanal_bekannt,
    sockel_oben_kg,
    heute
   FROM v_hochrechnung_basis
with no data;
create unique index if not exists erg_charge_pk ON public.erg_charge USING btree (charge_nr);
create index if not exists erg_charge_sorte ON public.erg_charge USING btree (sorte);
comment on materialized view erg_charge is
  'v_hochrechnung_basis, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';

create view v_kaskade with (security_invoker = true) as
SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    m0,
    m1,
    m2,
    r,
    f,
    a0,
    a_klein_n,
    a_gross_n,
    a_fax,
    u,
    d_m1_r,
    d_f_eta,
    modell_gilt,
    f_extrapoliert,
    r_n,
    r_basis,
    klein_n,
    klein_basis,
    gross_n,
    gross_basis,
    f_n,
    fax_n,
    fax_basis,
    r_bekannt,
    f_bekannt,
    a_klein_bekannt,
    a_gross_bekannt,
    a0_bekannt,
    a0_var,
    a_fax_bekannt,
    verdunstung_kg,
    sockel_kg,
    schimmel_kg,
    klein_kg,
    nebenkanal_kg,
    fax_kg,
    verkaufsfaehig_kg,
    kohorte,
    geliefert_kg,
    ueberzaehlung_kg,
    n_lieferungen,
    verkaufsfaehig_anteil
   FROM mv_kaskade;
grant select on v_kaskade to authenticated;
comment on view v_kaskade is
  'Der Massenfluss je Charge, Eingangstag und Portion: Was eingelagert wurde (eingang_kg) verteilt sich auf Verdunstung, Palox-Sockel, Schimmel, zu klein, Nebenkanal, Fax und verkaufsfähige Ware. Die Ströme addieren sich zum Eingang. "Verlust" ist hier nur, was wirklich verloren ist: verdunstung_kg, sockel_kg, schimmel_kg. klein_kg und nebenkanal_kg sind kein Verlust, sondern ein anderer Kanal; ueberzaehlung_kg ist kein Verlust, sondern ein Erfassungsfehler.';

create materialized view mv_hochrechnung as
SELECT k.charge_nr,
    k.sorte,
    k.schlag,
    k.portion,
    k.alter_tage,
    k.eingang_kg,
    zahl(c.m0)::numeric(14,2) AS portion_kg,
    k.f_extrapoliert,
    k.u,
    s.strom,
    s.buch,
        CASE
            WHEN s.bekannt THEN zahl(s.kg)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
        CASE
            WHEN s.bekannt THEN zahl(s.koeffizient, 6, '100000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,6) AS koeffizient,
    s.koeff_n,
    s.koeff_basis,
    s.formel,
    s.d_r,
    s.d_f * k.d_f_eta AS d_eta,
    s.d_a,
    s.d_a0,
    s.koeff_art,
    s.bekannt AS koeff_bekannt,
    k.kohorte
   FROM v_kaskade k
     CROSS JOIN LATERAL ( SELECT GREATEST(k.m0, 0::numeric) AS m0,
            GREATEST(k.m1, 0::numeric) AS m1,
            GREATEST(k.m2, 0::numeric) AS m2,
            GREATEST(k.verkaufsfaehig_kg, 0::numeric) AS verkaufsfaehig_kg,
            LEAST(GREATEST(k.r, 0::numeric), 1::numeric) AS r,
            LEAST(GREATEST(k.f, 0::numeric), 1::numeric) AS f,
            LEAST(GREATEST(k.a0, 0::numeric), 1::numeric) AS a0,
            LEAST(GREATEST(k.a_klein_n, 0::numeric), 1::numeric) AS a_klein_n,
            LEAST(GREATEST(k.a_gross_n, 0::numeric), 1::numeric) AS a_gross_n,
            LEAST(GREATEST(k.a_fax, 0::numeric), 1::numeric) AS a_fax) c
     CROSS JOIN LATERAL ( VALUES ('Verdunstung'::text,'verlust'::text,c.m0 - c.m1,c.m0,c.r,k.r_n,k.r_basis,'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'::text,- k.d_m1_r,0::numeric,0::numeric,0::numeric,NULL::text,k.r_bekannt), ('Nicht lagerbedingt'::text,'feld'::text,c.m1 * c.a0,c.m1,c.a0,k.f_n,'Grundaussortierung a₀ aus dem Verderbsmodell: was bei Lagerdauer null schon im Palox läge'::text,'Masse nach Verdunstung × a₀ — Erde, Hagelnarben, Schnittfehler; kein Lagerverlust'::text,k.d_m1_r * c.a0,0::numeric,0::numeric,c.m1,NULL::text,k.a0_bekannt), ('Schimmel/Fäulnis'::text,'verlust'::text,c.m1 * (1::numeric - c.a0) * c.f,c.m1 * (1::numeric - c.a0),c.f,k.f_n,'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen'::text,'Masse nach Verdunstung und Sockel × Schimmelanteil bei dieser Lagerdauer'::text,k.d_m1_r * (1::numeric - c.a0) * c.f,c.m1 * (1::numeric - c.a0),0::numeric,(- c.m1) * c.f,NULL::text,k.f_bekannt), ('Zu klein (Tierfutter)'::text,'marge'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_klein_n,c.m2,c.a_klein_n,k.klein_n,k.klein_basis,'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_klein_n,(- c.m1) * (1::numeric - c.a0) * c.a_klein_n,c.m2,(- c.m1) * (1::numeric - c.f) * c.a_klein_n,'ausschuss'::text,k.a_klein_bekannt), ('Nebenkanal zu gross'::text,'marge'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_gross_n,c.m2,c.a_gross_n,k.gross_n,k.gross_basis,'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_gross_n,(- c.m1) * (1::numeric - c.a0) * c.a_gross_n,c.m2,(- c.m1) * (1::numeric - c.f) * c.a_gross_n,'nebenkanal'::text,k.a_gross_bekannt), ('Faul beim Abpacken (Fax)'::text,'verlust'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),c.a_fax,k.fax_n,k.fax_basis,'Verkaufsfähige Masse × Anteil Faules, das beim Etikettieren aussortiert wird — vom Waschen und Stehen, nicht von der Lagerdauer'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,(- c.m1) * (1::numeric - c.a0) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),(- c.m1) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,'fax'::text,k.a_fax_bekannt), ('Verkaufsfähig'::text,'bilanz'::text,c.verkaufsfaehig_kg,c.m2,NULL::numeric,NULL::integer,NULL::text,'Rest der Kaskade'::text,0::numeric,0::numeric,0::numeric,0::numeric,NULL::text,true)) s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel, d_r, d_f, d_a, d_a0, koeff_art, bekannt)
with no data;
create index if not exists mv_hochrechnung_charge ON public.mv_hochrechnung USING btree (charge_nr, buch);
comment on materialized view mv_hochrechnung is
  'v_hochrechnung, gespeichert. Inhaltlich gleich; erneuert von auswertung_schritt(3).';

create view v_hochrechnung with (security_invoker = true) as
SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    portion_kg,
    f_extrapoliert,
    u,
    strom,
    buch,
    kg,
    basis_kg,
    koeffizient,
    koeff_n,
    koeff_basis,
    formel,
    d_r,
    d_eta,
    d_a,
    d_a0,
    koeff_art,
    koeff_bekannt,
    kohorte
   FROM mv_hochrechnung;
grant select on v_hochrechnung to authenticated;
comment on view v_hochrechnung is
  'Die Kaskade auseinandergelegt: eine Zeile je Charge, Portion und Strom, mit dem verwendeten Koeffizienten, seiner Herkunft (koeff_art), der Zahl der Messungen dahinter (koeff_n) und der Formel. koeff_bekannt = false heisst: geschätzt, nicht gemessen.';

create view v_kontrolle_vorschlag with (security_invoker = true) as
SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lager_kg,
    b.alter_lager_von,
    b.alter_lager_bis,
    b.eingang_von,
    b.eingang_bis,
    COALESCE(k.n_kontrollen, 0) AS n_kontrollen,
    k.zuletzt,
    b.im_haus_heute_kg,
    heute() - COALESCE(k.zuletzt, b.eingang_von) AS tage_seit_wiegung,
    zahl(b.im_haus_heute_kg * GREATEST(heute() - COALESCE(k.zuletzt, b.eingang_von), 1)::numeric, 0, '10000000000000'::numeric)::numeric(14,0) AS informationswert
   FROM erg_charge b
     LEFT JOIN ( SELECT verdunstung_wiegung.charge_nr,
            count(*) FILTER (WHERE verdunstung_wiegung.auftrag_id IS NULL)::integer AS n_kontrollen,
            max(verdunstung_wiegung.wiege_ts)::date AS zuletzt
           FROM verdunstung_wiegung
          WHERE verdunstung_wiegung.gemessen
          GROUP BY verdunstung_wiegung.charge_nr) k ON k.charge_nr = b.charge_nr
  WHERE b.im_haus_heute_kg > 0::numeric
  ORDER BY (zahl(b.im_haus_heute_kg * GREATEST(heute() - COALESCE(k.zuletzt, b.eingang_von), 1)::numeric, 0, '10000000000000'::numeric)::numeric(14,0)) DESC NULLS LAST, b.im_haus_heute_kg DESC
 LIMIT 3;
grant select on v_kontrolle_vorschlag to authenticated;
comment on view v_kontrolle_vorschlag is
  'Welche Charge als Nächstes kontrolliert werden sollte. informationswert gewichtet, wie viel noch im Haus liegt, wie lange die letzte Wiegung her ist und wie unsicher die Charge bisher ist — eine Reihenfolge, kein Befehl.';

create view v_massenbilanz with (security_invoker = true) as
WITH csv_anteil AS MATERIALIZED (
         SELECT am.charge_nr,
            COALESCE(sum(am.eingang_netto_kg) FILTER (WHERE (EXISTS ( SELECT 1
                   FROM sortier_lauf l
                  WHERE l.auftrag_id = am.auftrag_id))) / NULLIF(sum(am.eingang_netto_kg), 0::numeric), 0::numeric) AS anteil_mit_csv
           FROM v_auftrag_masse am
          WHERE (am.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND am.eingang_netto_kg IS NOT NULL
          GROUP BY am.charge_nr
        ), gemessen AS MATERIALIZED (
         SELECT v_sortier_lauf_masse.charge_nr,
            sum(v_sortier_lauf_masse.masse_kg) AS gemessen_kg
           FROM v_sortier_lauf_masse
          GROUP BY v_sortier_lauf_masse.charge_nr
        ), rest AS MATERIALIZED (
         SELECT v_kaskade.charge_nr,
            sum(v_kaskade.m2) FILTER (WHERE v_kaskade.portion = 'lager'::text) AS restbestand_kg
           FROM v_kaskade
          GROUP BY v_kaskade.charge_nr
        ), modell AS MATERIALIZED (
         SELECT b_1.charge_nr,
            b_1.am_band_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), COALESCE(b_1.alter_band, 0::numeric)) * (1::numeric - sockel_anteil()) * (1::numeric - schimmelanteil(COALESCE(b_1.alter_band, 0::numeric))) * q.anteil_mit_csv AS am_band_modell_kg
           FROM v_kaskade_basis b_1
             LEFT JOIN csv_anteil q ON q.charge_nr = b_1.charge_nr
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b_1.sorte
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.eingang_kg,
    b.ausgelagert_kg,
    b.lager_kg,
    b.n_paletten,
    b.alter_ausgelagert,
    b.alter_lager,
    b.stichtag,
    zahl(m.am_band_modell_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS modell_am_band_kg,
    c.gemessen_kg AS csv_gemessen_kg,
    zahl(c.gemessen_kg - m.am_band_modell_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS abweichung_kg,
        CASE
            WHEN m.am_band_modell_kg > 0::numeric THEN zahl((c.gemessen_kg - m.am_band_modell_kg) / m.am_band_modell_kg, 4, '1000000'::numeric)::numeric(10,4)
            ELSE NULL::numeric
        END AS abweichung_anteil,
    zahl(r.restbestand_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS restbestand_kg,
    kb.alter_band
   FROM erg_charge b
     JOIN v_kaskade_basis kb ON kb.charge_nr = b.charge_nr
     LEFT JOIN modell m ON m.charge_nr = b.charge_nr
     LEFT JOIN gemessen c ON c.charge_nr = b.charge_nr
     LEFT JOIN rest r ON r.charge_nr = b.charge_nr;
grant select on v_massenbilanz to authenticated;
comment on view v_massenbilanz is
  'Die Probe aufs Exempel je Charge: Was das Modell am Band erwartet (modell_am_band_kg) gegen das, was die Sortier-Datei gewogen hat (csv_gemessen_kg). abweichung_anteil nahe 0 heisst, die Koeffizienten treffen die Wirklichkeit; systematisch positiv heisst, die Verluste sind überschätzt. Nur für Chargen mit Sortier-Datei aussagekräftig.';

create view v_naechste_charge with (security_invoker = true) as
WITH modell AS MATERIALIZED (
         SELECT v_schimmel_modell.n,
            v_schimmel_modell.c_chargen,
            v_schimmel_modell.t_min,
            v_schimmel_modell.t_max,
            v_schimmel_modell.k,
            v_schimmel_modell.ln_lambda,
            v_schimmel_modell.lambda,
            v_schimmel_modell.x_mittel,
            v_schimmel_modell.sxx,
            v_schimmel_modell.smearing,
            v_schimmel_modell.ln_lambda_korrigiert,
            v_schimmel_modell.sigma2,
            v_schimmel_modell.var_achse,
            v_schimmel_modell.var_k,
            v_schimmel_modell.kov_achse_k,
            v_schimmel_modell.t_faktor,
            v_schimmel_modell.brauchbar,
            v_schimmel_modell.selektions_versatz,
            v_schimmel_modell.sockel,
            v_schimmel_modell.sockel_unten,
            v_schimmel_modell.sockel_oben,
            v_schimmel_modell.sockel_nachweis,
            v_schimmel_modell.sockel_schwelle,
            v_schimmel_modell.sockel_var
           FROM v_schimmel_modell
        ), kohorten AS MATERIALIZED (
         SELECT v_kohorte_anteil.charge_nr,
            v_kohorte_anteil.eingangsdatum,
            v_kohorte_anteil.anteil
           FROM v_kohorte_anteil
        ), bestand AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.lager_kg,
            LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            t.m0,
            t.alter_tage
           FROM erg_charge b
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b.sorte
             CROSS JOIN LATERAL ( SELECT b.lager_kg * c.anteil AS m0,
                    GREATEST((heute() - c.eingangsdatum)::numeric, 0::numeric) AS alter_tage
                   FROM kohorten c
                  WHERE c.charge_nr = b.charge_nr
                UNION ALL
                 SELECT b.lager_kg,
                    GREATEST(b.alter_lager_heute, 0::numeric) AS "greatest"
                  WHERE NOT (EXISTS ( SELECT 1
                           FROM kohorten c
                          WHERE c.charge_nr = b.charge_nr))) t
          WHERE b.lager_kg > 0::numeric
        ), mit_f AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.lager_kg,
            b.r,
            b.m0,
            b.alter_tage,
            b.m0 * power(1::numeric - b.r, b.alter_tage) AS masse_jetzt_kg,
                CASE
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(b.alter_tage, 1::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 0.99)
                    ELSE NULL::numeric
                END AS f_jetzt,
                CASE
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(b.alter_tage + 14::numeric, 1::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 0.99)
                    ELSE NULL::numeric
                END AS f_dann,
            m.brauchbar AND b.alter_tage > m.t_max AS hochgerechnet,
            m.brauchbar AS modell_gilt
           FROM bestand b
             CROSS JOIN modell m
        ), je_charge AS (
         SELECT mit_f.charge_nr,
            mit_f.sorte,
            mit_f.schlag,
            mit_f.lager_kg,
            mit_f.modell_gilt,
            bool_or(mit_f.hochgerechnet) AS hochgerechnet,
            sum(mit_f.masse_jetzt_kg) AS masse_jetzt_kg,
            sum(mit_f.masse_jetzt_kg * mit_f.alter_tage) / NULLIF(sum(mit_f.masse_jetzt_kg), 0::numeric) AS alter_tage,
            min(mit_f.alter_tage) AS alter_von,
            max(mit_f.alter_tage) AS alter_bis,
            count(*)::integer AS n_kohorten,
            sum(mit_f.masse_jetzt_kg * (1::numeric - power(1::numeric - mit_f.r, 14::numeric))) AS verdunstung_14_kg,
                CASE
                    WHEN mit_f.modell_gilt THEN sum(mit_f.masse_jetzt_kg * (mit_f.f_dann - mit_f.f_jetzt) / NULLIF(1::numeric - mit_f.f_jetzt, 0::numeric))
                    ELSE NULL::numeric
                END AS schimmel_14_kg
           FROM mit_f
          GROUP BY mit_f.charge_nr, mit_f.sorte, mit_f.schlag, mit_f.lager_kg, mit_f.modell_gilt
        )
 SELECT charge_nr,
    sorte,
    schlag,
    zahl(lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    round(alter_tage)::integer AS alter_tage,
    zahl(masse_jetzt_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS masse_jetzt_kg,
    zahl(verdunstung_14_kg, 1, '100000000000'::numeric)::numeric(12,1) AS verdunstung_14_kg,
    zahl(schimmel_14_kg, 1, '100000000000'::numeric)::numeric(12,1) AS schimmel_14_kg,
    zahl(verdunstung_14_kg + schimmel_14_kg, 1, '100000000000'::numeric)::numeric(12,1) AS prognose_verlust_14_kg,
    hochgerechnet,
    modell_gilt,
    round(alter_von)::integer AS alter_von,
    round(alter_bis)::integer AS alter_bis,
    n_kohorten
   FROM je_charge
  ORDER BY (zahl(verdunstung_14_kg + COALESCE(schimmel_14_kg, 0::numeric), 1, '100000000000'::numeric)::numeric(12,1)) DESC NULLS LAST;
grant select on v_naechste_charge to authenticated;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag ab heute() gerechnet und je Charge summiert; der Bestand aus erg_charge (0061). prognose_verlust_14_kg ist Verdunstung + Verderb der nächsten 14 Tage — reine Prognose, nicht im Verlust bis heute enthalten, und leer, wo das Modell nicht gilt. Sockel und Fax stecken nicht darin (0062).';

create view v_plausibilitaet_0064_zusatz with (security_invoker = true) as
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

create view v_plausibilitaet_0054_zusatz with (security_invoker = true) as
SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber ein Band mit diesen '::text || 'Grenzen wurde beim Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt'::text, g.anzahl, a.kaliber_von_g, a.kaliber_bis_g) AS befund,
    'Entweder das Band aus der Liste wählen, das dem Etikett entspricht, oder beim '::text || 'nächsten Sortierlauf mit diesem Band die gefüllten Kisten zählen.'::text AS rat
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx = '-2'::integer
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    wp.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '::text || 'die Menge dieser Arbeit damit auch'::text, wp.n_paletten, wp.kisten,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN format('ein Band %s–%s g wurde beim Sortieren noch nie mitgezählt'::text, a.kaliber_von_g, a.kaliber_bis_g)
            ELSE 'für dieses Kaliber wurde beim Sortieren noch nie mitgezählt'::text
        END) AS befund,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht, oder beim '::text || 'nächsten Sortierlauf mit diesem Band die gefüllten Kisten zählen.'::text
            ELSE 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '::text || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.'::text
        END AS rat
   FROM v_auftrag_wasch_paletten wp
     JOIN auftrag a ON a.id = wp.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE wp.kg IS NULL AND wp.kisten > 0
UNION ALL
 SELECT 'Lieferung in der Zukunft'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    l.datum::timestamp with time zone AS start_ts,
    format('Lieferschein über %s kg mit Datum %s — das liegt nach heute (%s). '::text || 'Die Menge zählt erst ab diesem Tag in Ausgang und Bestand.'::text, round(l.masse_kg), to_char(l.datum::timestamp with time zone, 'DD.MM.YYYY'::text), to_char(heute()::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Stimmt das Datum? Ein vordatierter Lieferschein ist in Ordnung — die Zahl '::text || 'erscheint von selbst, sobald der Tag da ist. Ein Zahlendreher gehört korrigiert.'::text AS rat
   FROM v_lieferung_masse l
  WHERE l.datum > heute() AND l.masse_kg IS NOT NULL AND l.masse_kg > 0::numeric
UNION ALL
 SELECT v_plausibilitaet_0064_zusatz.art,
    v_plausibilitaet_0064_zusatz.auftrag_id,
    v_plausibilitaet_0064_zusatz.charge_nr,
    v_plausibilitaet_0064_zusatz.sorte,
    v_plausibilitaet_0064_zusatz.start_ts,
    v_plausibilitaet_0064_zusatz.befund,
    v_plausibilitaet_0064_zusatz.rat
   FROM v_plausibilitaet_0064_zusatz;
grant select on v_plausibilitaet_0054_zusatz to authenticated;
comment on view v_plausibilitaet_0054_zusatz is
  'Zusatzprüfungen zu v_plausibilitaet, die seit 0054 dazugekommen sind — je Auffälligkeit Art, betroffene Arbeit, Befund und Rat. Wird von v_plausibilitaet mitgelesen; einzeln braucht sie niemand.';

create view v_plausibilitaet with (security_invoker = true) as
SELECT 'Schimmel'::text AS art,
    b.auftrag_id,
    b.charge_nr,
    b.sorte,
    b.start_ts,
    format('%s kg Schimmel auf %s kg Ware — das wären %s %%'::text, round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100::numeric)) AS befund,
    'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text AS rat
   FROM v_schimmel_beobachtung b
  WHERE b.anteil IS NOT NULL AND NOT b.plausibel AND NOT b.ist_fax
UNION ALL
 SELECT 'Fax'::text AS art,
    f.auftrag_id,
    f.charge_nr,
    f.sorte,
    f.start_ts,
    format('%s kg Faules bei %s (%s kg) — das wären %s %%'::text, round(f.faul_kg),
        CASE
            WHEN f.paletten_gesamt > 0 THEN f.paletten_gesamt || ' Paletten'::text
            ELSE f.kisten || ' Kisten'::text
        END, round(f.masse_kg), round(f.anteil * 100::numeric)) AS befund,
    'Entweder die Palettenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'::text AS rat
   FROM v_fax_beobachtung f
  WHERE f.anteil IS NOT NULL AND NOT f.plausibel
UNION ALL
 SELECT 'Ausschuss'::text AS art,
    a.auftrag_id,
    a.charge_nr,
    a.sorte,
    NULL::timestamp with time zone AS start_ts,
    format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse'::text, round(COALESCE(a.klein_kg, 0::numeric)), round(COALESCE(a.gross_kg, 0::numeric)), round(a.basis_kg)) AS befund,
    'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'::text AS rat
   FROM v_ausschuss_beobachtung a
  WHERE a.weg = 'hand'::verarbeitungsweg AND NOT a.plausibel
UNION ALL
 SELECT 'Ohne Nenner'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein'::text, concat_ws(' und '::text,
        CASE
            WHEN COALESCE(s.kg, 0::numeric) > 0::numeric THEN round(s.kg) || ' kg Faules'::text
            ELSE NULL::text
        END,
        CASE
            WHEN COALESCE(x.kg, 0::numeric) > 0::numeric THEN round(x.kg) || ' kg zu klein/gross'::text
            ELSE NULL::text
        END),
        CASE
            WHEN a.ist_fax THEN 'keine Palette gezählt oder noch keine fertige Palette dieser Sorte gewogen'::text
            WHEN a.station = 'waschen'::station THEN 'keine Kiste gezählt und keine Menge eingetragen'::text
            WHEN a.station = 'waschen_sortieren'::station THEN 'keine Palette mit Gewicht vom Zettel gezählt'::text
            ELSE 'keine Palette gezählt'::text
        END) AS befund,
        CASE
            WHEN a.ist_fax THEN ('Die Palettenzahl am Ende der Fax-Arbeit eintragen. Fehlt die Palettenmasse, '::text || 'beim Waschen oder Waschen + Sortieren eine fertige Palette wiegen — sie '::text) || 'gilt dann für alle Fax-Arbeiten der Sorte.'::text
            WHEN a.station = 'waschen'::station THEN 'Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich '::text || 'selbst) oder die verarbeitete Menge in kg nachtragen.'::text
            WHEN a.station = 'waschen_sortieren'::station THEN 'Die Paletten mit Datum und Gewicht vom Zettel am Auftrag nachtragen.'::text
            ELSE 'Die gezählten Paletten am Auftrag nachtragen.'::text
        END AS rat
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_schimmel_menge s ON s.auftrag_id = a.id
     LEFT JOIN ( SELECT ausschuss_messung.auftrag_id,
            sum(ausschuss_messung.kg)::numeric AS kg
           FROM ausschuss_messung
          WHERE ausschuss_messung.gemessen
          GROUP BY ausschuss_messung.auftrag_id) x ON x.auftrag_id = a.id
     LEFT JOIN v_auftrag_masse m ON m.auftrag_id = a.id
  WHERE a.abgebrochen_ts IS NULL AND (COALESCE(s.kg, 0::numeric) > 0::numeric OR COALESCE(x.kg, 0::numeric) > 0::numeric) AND COALESCE(m.eingang_netto_kg, 0::numeric) <= 0::numeric
UNION ALL
 SELECT 'Palox'::text AS art,
    s.auftrag_id,
    a.charge_nr,
    c.sorte,
    s.ts AS start_ts,
    format('Waagenstand %s kg liegt unter dem Leergewicht des Palox (%s kg)'::text, s.palox_stand_kg, palox_tara_kg()) AS befund,
    'Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '::text || 'Sonst ist der Stand vertippt.'::text AS rat
   FROM schimmel_messung s
     JOIN auftrag a ON a.id = s.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE s.gemessen AND a.abgebrochen_ts IS NULL AND s.palox_stand_kg IS NOT NULL AND s.palox_stand_kg < palox_tara_kg()
UNION ALL
 SELECT 'Palox geleert'::text AS art,
    p.auftrag_id,
    a.charge_nr,
    c.sorte,
    p.ts AS start_ts,
    format('Der Waagenstand fiel von %s auf %s kg — der Palox wurde zwischendurch geleert. '::text || 'Wie viel davor noch dazukam, weiss niemand; das Faule dieser Arbeit ist unbekannt.'::text, p.vorher, p.palox_stand_kg) AS befund,
    'Nichts zu korrigieren. Wird der Palox vor dem Leeren einmal abgelesen, bleibt die Menge bekannt.'::text AS rat
   FROM v_palox_stand p
     JOIN auftrag a ON a.id = p.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE p.differenz IS NULL AND a.abgebrochen_ts IS NULL
UNION ALL
 SELECT 'Wägung'::text AS art,
    w.auftrag_id,
    w.charge_nr,
    w.sorte,
    w.wiege_ts AS start_ts,
    ('Palette gewogen, aber '::text ||
        CASE
            WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'für die Gebindeart fehlt die Tara'::text
            WHEN w.lagertage <= 0 THEN 'das Wiegedatum liegt nicht nach dem Eingangsdatum'::text
            WHEN w.netto_damals_kg <= 0::numeric OR w.netto_jetzt_kg <= 0::numeric THEN 'das Netto ist null oder negativ'::text
            WHEN w.netto_jetzt_kg > (w.netto_damals_kg * 1.01) THEN format('sie wiegt jetzt %s kg mehr als beim Eingang, und im Lager wird keine Palette schwerer'::text, round(w.netto_jetzt_kg - w.netto_damals_kg))
            ELSE 'sie ist nicht verwertbar'::text
        END) || ' — sie zählt nicht in die Verdunstungsrate'::text AS befund,
        CASE
            WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'Unter Stammdaten → Gebinde die Tara nachtragen.'::text
            WHEN w.netto_jetzt_kg > (w.netto_damals_kg * 1.01) THEN 'Gebindeart, Kistenzahl und beide Gewichte prüfen — meist stimmt die Tara nicht oder eine Zahl ist verdreht.'::text
            ELSE 'Eingangsdatum und Gewichte der Wägung prüfen.'::text
        END AS rat
   FROM v_verdunstung_messung w
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
  WHERE NOT w.verwendbar AND NOT w.sichtbar_schimmel AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
           FROM verdunstung_wiegung v
          WHERE v.id = w.id AND v.gemessen))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN format('%s Kisten nach Sollgewicht gezählt, aber für diese Sorte wurde noch '::text || 'nie eine fertige Palette gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl)
            ELSE format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber wurde beim '::text || 'Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt'::text, g.anzahl, g.kaliber_idx + 1)
        END AS befund,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN 'Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '::text || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'::text
            ELSE 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '::text || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.'::text
        END AS rat
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx <> '-2'::integer
UNION ALL
 SELECT 'Kaliber fehlt'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen'::text AS befund,
    'Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '::text || 'Stammdaten → Sortierschemata.'::text AS rat
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.kaliber_idx IS NULL AND a.kaliber_von_g IS NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM auftrag_gebinde g
          WHERE g.auftrag_id = a.id AND g.anzahl > 0))
UNION ALL
 SELECT 'Ausschuss-Tara'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    m.ts AS start_ts,
    format('%s kg %s gespeichert — aus Brutto %s kg und heutiger Tara wären es %s kg'::text, m.kg,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'zu klein'::text
            ELSE 'zu gross'::text
        END, m.brutto_kg, GREATEST(round(m.brutto_kg - COALESCE(m.kisten, 0)::numeric * COALESCE(g.tara_kg_pro_kiste, 0::numeric) - COALESCE(g.tara_kg_palette, 0::numeric)), 0::numeric)) AS befund,
    'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '::text || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND m.kg::numeric <> GREATEST(round(m.brutto_kg - COALESCE(m.kisten, 0)::numeric * COALESCE(g.tara_kg_pro_kiste, 0::numeric) - COALESCE(g.tara_kg_palette, 0::numeric)), 0::numeric)
UNION ALL
 SELECT 'Zetteldatum'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Zetteldatum %s gezählt, aber an dem Tag kam keine Palette dieser Charge'::text, count(*), to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.eingangsdatum IS NOT NULL AND ap.palette_id IS NULL AND ap.wiegung_id IS NULL AND a.abgebrochen_ts IS NULL AND NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.eingangsdatum = ap.eingangsdatum))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.eingangsdatum
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette '::text || 'dieser Charge dieses Gewicht — gerechnet wird mit der mittleren Tara der Charge'::text, count(*), ap.brutto_zettel_kg) AS befund,
    'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.brutto_zettel_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND NOT (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg
UNION ALL
 SELECT 'Lieferung ohne Eingang'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    min(l.datum)::timestamp with time zone AS start_ts,
    format('%s Lieferung(en) mit %s kg an Charge %s, aber im Wareneingang steht keine Palette dieser Charge'::text, count(*), round(sum(l.masse_kg)), l.charge_nr) AS befund,
    'Wareneingang der Charge nachtragen (Erntejournal) — oder die Lieferung gehört zu einer anderen Charge.'::text AS rat
   FROM v_lieferung_masse l
  WHERE l.buch = 'verkauf'::text AND l.charge_nr IS NOT NULL AND l.masse_kg > 0::numeric AND NOT (EXISTS ( SELECT 1
           FROM v_kohorte_anteil k
          WHERE k.charge_nr = l.charge_nr))
  GROUP BY l.charge_nr, l.sorte
UNION ALL
 SELECT v_plausibilitaet_0054_zusatz.art,
    v_plausibilitaet_0054_zusatz.auftrag_id,
    v_plausibilitaet_0054_zusatz.charge_nr,
    v_plausibilitaet_0054_zusatz.sorte,
    v_plausibilitaet_0054_zusatz.start_ts,
    v_plausibilitaet_0054_zusatz.befund,
    v_plausibilitaet_0054_zusatz.rat
   FROM v_plausibilitaet_0054_zusatz;
grant select on v_plausibilitaet to authenticated;
comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette.';

create view v_verlust_je_gruppe with (security_invoker = true) as
WITH gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text AS text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text AS text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text AS text,
            v_kaskade_basis.charge_nr::text AS charge_nr,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        ), zeilen AS MATERIALIZED (
         SELECT g_1.gruppe,
            g_1.schluessel,
            h.charge_nr,
            h.sorte,
            h.schlag,
            h.portion,
            h.alter_tage,
            h.eingang_kg,
            h.portion_kg,
            h.f_extrapoliert,
            h.u,
            h.strom,
            h.buch,
            h.kg,
            h.basis_kg,
            h.koeffizient,
            h.koeff_n,
            h.koeff_basis,
            h.formel,
            h.d_r,
            h.d_eta,
            h.d_a,
            h.d_a0,
            h.koeff_art,
            h.koeff_bekannt,
            h.kohorte,
            h.strom = 'Faul beim Abpacken (Fax)'::text AND h.portion = 'lager'::text AS erwartet
           FROM mv_hochrechnung h
             JOIN gruppen g_1 ON g_1.charge_nr = h.charge_nr
          WHERE h.buch = ANY (ARRAY['verlust'::text, 'marge'::text, 'feld'::text])
        ), unsicherheit AS MATERIALIZED (
         SELECT v_koeff_unsicherheit.art,
            v_koeff_unsicherheit.sorte,
            v_koeff_unsicherheit.b,
            v_koeff_unsicherheit.varianz_eigen,
            v_koeff_unsicherheit.gewicht_gesamt,
            v_koeff_unsicherheit.varianz_gesamt,
            v_koeff_unsicherheit.df
           FROM v_koeff_unsicherheit
        ), modell AS MATERIALIZED (
         SELECT v_schimmel_modell.n,
            v_schimmel_modell.c_chargen,
            v_schimmel_modell.t_min,
            v_schimmel_modell.t_max,
            v_schimmel_modell.k,
            v_schimmel_modell.ln_lambda,
            v_schimmel_modell.lambda,
            v_schimmel_modell.x_mittel,
            v_schimmel_modell.sxx,
            v_schimmel_modell.smearing,
            v_schimmel_modell.ln_lambda_korrigiert,
            v_schimmel_modell.sigma2,
            v_schimmel_modell.var_achse,
            v_schimmel_modell.var_k,
            v_schimmel_modell.kov_achse_k,
            v_schimmel_modell.t_faktor,
            v_schimmel_modell.brauchbar,
            v_schimmel_modell.selektions_versatz,
            v_schimmel_modell.sockel,
            v_schimmel_modell.sockel_unten,
            v_schimmel_modell.sockel_oben,
            v_schimmel_modell.sockel_nachweis,
            v_schimmel_modell.sockel_schwelle,
            v_schimmel_modell.sockel_var
           FROM v_schimmel_modell
        ), eingang AS MATERIALIZED (
         SELECT g_1.gruppe,
            g_1.schluessel,
            sum(b.eingang_kg) AS eingang_kg,
            count(*)::integer AS n_chargen
           FROM gruppen g_1
             JOIN v_kaskade_basis b ON b.charge_nr = g_1.charge_nr
          GROUP BY g_1.gruppe, g_1.schluessel
        ), je_sorte AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            z.sorte,
            max(z.koeff_art) AS koeff_art,
            sum(z.d_r) AS g_r,
            sum(z.d_a) AS g_a
           FROM zeilen z
          WHERE NOT z.erwartet
          GROUP BY z.gruppe, z.schluessel, z.strom, z.buch, z.sorte
        ), je_strom_modell AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            sum(z.d_eta) AS g_achse,
            sum(z.d_eta * z.u) AS g_steigung,
            sum(z.d_a0) AS g_a0
           FROM zeilen z
          WHERE NOT z.erwartet
          GROUP BY z.gruppe, z.schluessel, z.strom, z.buch
        ), varianz_r AS MATERIALIZED (
         SELECT s_1.gruppe,
            s_1.schluessel,
            s_1.strom,
            s_1.buch,
            sum(power(s_1.g_r, 2::numeric) * COALESCE(u.varianz_eigen, 0::numeric)) + power(sum(s_1.g_r * COALESCE(u.gewicht_gesamt, 1::numeric)), 2::numeric) * max(COALESCE(u.varianz_gesamt, 0::numeric)) AS varianz,
            min(COALESCE(u.df, 1)) AS df
           FROM je_sorte s_1
             LEFT JOIN unsicherheit u ON u.art = 'verdunstung'::text AND NOT u.sorte IS DISTINCT FROM s_1.sorte
          GROUP BY s_1.gruppe, s_1.schluessel, s_1.strom, s_1.buch
        ), varianz_a AS MATERIALIZED (
         SELECT s_1.gruppe,
            s_1.schluessel,
            s_1.strom,
            s_1.buch,
            sum(power(s_1.g_a, 2::numeric) * COALESCE(u.varianz_eigen, 0::numeric)) + power(sum(s_1.g_a * COALESCE(u.gewicht_gesamt, 1::numeric)), 2::numeric) * max(COALESCE(u.varianz_gesamt, 0::numeric)) AS varianz,
            min(COALESCE(u.df, 1)) AS df
           FROM je_sorte s_1
             LEFT JOIN unsicherheit u ON u.art = s_1.koeff_art AND NOT u.sorte IS DISTINCT FROM s_1.sorte
          WHERE s_1.koeff_art IS NOT NULL
          GROUP BY s_1.gruppe, s_1.schluessel, s_1.strom, s_1.buch
        ), varianz_f AS MATERIALIZED (
         SELECT m.gruppe,
            m.schluessel,
            m.strom,
            m.buch,
            power(m.g_achse, 2::numeric) * COALESCE(sm.var_achse, 0::numeric) + 2::numeric * m.g_achse * m.g_steigung * COALESCE(sm.kov_achse_k, 0::numeric) + power(m.g_steigung, 2::numeric) * COALESCE(sm.var_k, 0::numeric) + power(m.g_a0, 2::numeric) *
                CASE
                    WHEN sm.brauchbar THEN COALESCE(sm.sockel_var, 0::numeric)
                    ELSE 0::numeric
                END AS varianz,
            COALESCE(sm.c_chargen - 1, 1) AS df
           FROM je_strom_modell m
             CROSS JOIN modell sm
        ), summe AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            sum(z.kg) FILTER (WHERE NOT z.erwartet) AS kg,
            bool_and(z.koeff_bekannt) AS bekannt,
            sum(z.kg) FILTER (WHERE z.portion = 'ausgelagert'::text) AS kg_beobachtet,
            sum(z.kg) FILTER (WHERE z.portion = 'lager'::text AND NOT z.erwartet) AS kg_projiziert,
            sum(z.kg) FILTER (WHERE z.f_extrapoliert AND NOT z.erwartet) AS kg_extrapoliert,
            sum(z.kg) FILTER (WHERE z.erwartet) AS kg_erwartet,
            min(z.koeff_n) AS koeff_n_min,
            sum(z.basis_kg) AS basis_kg,
            max(z.koeff_basis) AS koeff_basis,
            max(z.koeff_art) AS koeff_art,
            max(z.formel) AS formel
           FROM zeilen z
          GROUP BY z.gruppe, z.schluessel, z.strom, z.buch
        )
 SELECT s.gruppe,
    s.schluessel,
    s.strom,
    s.buch,
        CASE
            WHEN s.bekannt THEN zahl(s.kg)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg,
        CASE
            WHEN s.bekannt THEN zahl(GREATEST(s.kg - g.t * g.streuung - zu.zuschlag, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_unten,
        CASE
            WHEN s.bekannt THEN zahl(s.kg + g.t * g.streuung + zu.zuschlag)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_oben,
        CASE
            WHEN s.bekannt THEN zahl(s.kg_beobachtet)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_beobachtet,
        CASE
            WHEN s.bekannt THEN zahl(s.kg_projiziert)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_projiziert,
        CASE
            WHEN s.bekannt THEN zahl(s.kg_extrapoliert)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_extrapoliert,
        CASE
            WHEN s.bekannt THEN zahl(s.kg_erwartet)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_erwartet,
    s.koeff_n_min,
        CASE
            WHEN s.bekannt THEN zahl(g.streuung)
            ELSE NULL::numeric
        END::numeric(14,2) AS streuung_kg,
    g.df,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
    s.koeff_basis,
    s.koeff_art,
    s.formel,
    s.bekannt,
    zahl(e.eingang_kg)::numeric(14,2) AS eingang_kg,
    e.n_chargen
   FROM summe s
     JOIN eingang e ON e.gruppe = s.gruppe AND e.schluessel = s.schluessel
     LEFT JOIN varianz_r vr ON vr.gruppe = s.gruppe AND vr.schluessel = s.schluessel AND vr.strom = s.strom AND vr.buch = s.buch
     LEFT JOIN varianz_a va ON va.gruppe = s.gruppe AND va.schluessel = s.schluessel AND va.strom = s.strom AND va.buch = s.buch
     LEFT JOIN varianz_f vf ON vf.gruppe = s.gruppe AND vf.schluessel = s.schluessel AND vf.strom = s.strom AND vf.buch = s.buch
     CROSS JOIN LATERAL ( SELECT COALESCE(sm2.selektions_versatz, 0::numeric) AS versatz
           FROM modell sm2) sel
     CROSS JOIN LATERAL ( SELECT sqrt(GREATEST(COALESCE(vr.varianz, 0::numeric) + COALESCE(va.varianz, 0::numeric) + COALESCE(vf.varianz, 0::numeric), 0::numeric)) AS streuung,
            LEAST(COALESCE(vr.df, 999), COALESCE(va.df, 999), COALESCE(vf.df, 999)) AS df) g0
     CROSS JOIN LATERAL ( SELECT g0.streuung,
            g0.df,
            t_quantil_95(g0.df) AS t) g
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN s.strom = 'Schimmel/Fäulnis'::text THEN COALESCE(s.kg_projiziert, 0::numeric) * abs(exp(sel.versatz) - 1::numeric)
                    ELSE 0::numeric
                END AS zuschlag) zu;
grant select on v_verlust_je_gruppe to authenticated;
comment on view v_verlust_je_gruppe is
  'Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, Charge). kg_beobachtet ist gemessen, kg_projiziert auf noch nicht Gemessenes übertragen, kg_extrapoliert über den Messbereich hinaus gerechnet — drei verschiedene Sicherheiten, darum drei Spalten.';

create materialized view erg_verlust as
SELECT gruppe,
    schluessel,
    strom,
    buch,
    kg,
    kg_unten,
    kg_oben,
    kg_beobachtet,
    kg_projiziert,
    kg_extrapoliert,
    kg_erwartet,
    koeff_n_min,
    streuung_kg,
    df,
    basis_kg,
    koeff_basis,
    koeff_art,
    formel,
    bekannt,
    eingang_kg,
    n_chargen
   FROM v_verlust_je_gruppe
with no data;
create unique index if not exists erg_verlust_pk ON public.erg_verlust USING btree (gruppe, schluessel, strom);
comment on materialized view erg_verlust is
  'v_verlust_je_gruppe, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';

create view v_marge_buch with (security_invoker = true) as
WITH verkauf AS (
         SELECT sum(erg_ueberfuellung.verschenkt_kg) AS verschenkt_kg,
            sum(
                CASE
                    WHEN erg_ueberfuellung.verschenkt_kg IS NULL THEN NULL::numeric
                    ELSE GREATEST(erg_ueberfuellung.verschenkt_kg - COALESCE(erg_ueberfuellung.verschenkt_fehler_kg, 0::numeric), 0::numeric)
                END) AS verschenkt_unten_kg,
            sum(erg_ueberfuellung.verschenkt_kg + COALESCE(erg_ueberfuellung.verschenkt_fehler_kg, 0::numeric)) AS verschenkt_oben_kg,
            sum(erg_ueberfuellung.kisten_verkauft) FILTER (WHERE erg_ueberfuellung.n_wiegungen > 0) AS kisten_gerechnet,
            sum(erg_ueberfuellung.kisten_verkauft) FILTER (WHERE erg_ueberfuellung.n_wiegungen = 0) AS kisten_ungewogen,
            sum(erg_ueberfuellung.n_wiegungen) AS n_wiegungen,
            sum(erg_ueberfuellung.kisten_gewogen) AS kisten_gewogen,
            sum(erg_ueberfuellung.zuviel_je_kiste * erg_ueberfuellung.kisten_gewogen::numeric) / NULLIF(sum(erg_ueberfuellung.kisten_gewogen) FILTER (WHERE erg_ueberfuellung.zuviel_je_kiste IS NOT NULL), 0::numeric) AS zuviel_je_kiste,
            count(*) FILTER (WHERE erg_ueberfuellung.n_lieferungen > 0)::integer AS n_gruppen_verkauft
           FROM erg_ueberfuellung
          WHERE erg_ueberfuellung.gruppe = 'sorte'::text AND erg_ueberfuellung.kistensystem = 'kiste_ab'::text
        ), datei AS (
         SELECT count(*)::integer AS n
           FROM lieferung_import
        )
 SELECT r.strom AS posten,
    r.kg,
    r.kg_unten,
    r.kg_oben,
        CASE r.strom
            WHEN 'Nebenkanal zu gross'::text THEN 'Ware über der oberen Kalibergrenze geht in einen anderen Verkaufskanal — nicht weg, nur nicht zum besten Preis'::text
            WHEN 'Zu klein (Tierfutter)'::text THEN 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'::text
            ELSE ''::text
        END AS erlaeuterung,
    r.kg IS NOT NULL AS gemessen
   FROM erg_verlust r
  WHERE r.gruppe = 'gesamt'::text AND r.buch = 'marge'::text
UNION ALL
 SELECT 'Überfüllung der Kisten'::text AS posten,
    zahl(v.verschenkt_kg)::numeric(14,2) AS kg,
    zahl(v.verschenkt_unten_kg)::numeric(14,2) AS kg_unten,
    zahl(v.verschenkt_oben_kg)::numeric(14,2) AS kg_oben,
        CASE
            WHEN d.n = 0 THEN 'Keine Verkaufsdatei eingelesen — wie viele Kisten „ab x kg" verkauft wurden, weiss die App nicht. Nichts gerechnet.'::text
            WHEN COALESCE(v.n_wiegungen, 0::bigint) = 0 THEN format('%s Kisten „ab x kg" laut Verkaufsdatei verkauft, aber keine fertige Palette dieses Systems gewogen — nichts gerechnet.'::text, round(COALESCE(v.kisten_ungewogen, 0::numeric)))
            ELSE format(('%s gewogene Paletten (%s Kisten): im Schnitt %s kg je Kiste über dem Soll. '::text || 'Verkauft laut Verkaufsdatei: %s Kisten desselben Systems — daraus die Zahl. '::text) || '%s'::text, v.n_wiegungen, round(COALESCE(v.kisten_gewogen, 0::numeric)), round(COALESCE(v.zuviel_je_kiste, 0::numeric), 3), round(COALESCE(v.kisten_gerechnet, 0::numeric)),
            CASE
                WHEN COALESCE(v.kisten_ungewogen, 0::numeric) > 0::numeric THEN format('Weitere %s verkaufte Kisten haben kein gewogenes Gegenstück (Sorte oder Soll ohne Wägung) und sind nicht gerechnet.'::text, round(v.kisten_ungewogen))
                ELSE 'Kisten nach Stück haben kein Sollgewicht und damit keine Überfüllung.'::text
            END)
        END AS erlaeuterung,
    v.verschenkt_kg IS NOT NULL AS gemessen
   FROM verkauf v
     CROSS JOIN datei d;
grant select on v_marge_buch to authenticated;
comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb verlassen hat, ohne verkaufsfähig zu sein — zu klein, Nebenkanal, Überfüllung. Kein Verlust im Sinne von verdorben, sondern Masse in einem anderen Kanal. kg_unten und kg_oben spannen den Bereich auf, gemessen sagt, ob dahinter Messungen oder Schätzungen stehen.';

create view v_saisonbilanz with (security_invoker = true) as
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
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.kanal_ausgelagert_kg - c.im_haus_heute_kg)::numeric(14,2) AS bilanz_rest_kg,
    zahl(
        CASE
            WHEN c.eingang_kg > 0::numeric THEN (c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg - c.kanal_ausgelagert_kg - c.im_haus_heute_kg) / c.eingang_kg
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
            ELSE format((('Bis heute (%s): %s t Eingang = %s t ausgeliefert + %s t Verlust '::text || '(Verdunstung %s t, Faules %s t, Fax %s t) + %s t anderer Kanal '::text) || '+ %s t noch im Haus (davon %s t verkaufsfähig). Die Prognose bis zum '::text) || 'Saisonende steht in der Grafik, nicht in diesen Zahlen.%s'::text, to_char(c.heute::timestamp with time zone, 'DD.MM.YYYY'::text), round(c.eingang_kg / 1000.0, 1), round(c.geliefert_kg / 1000.0, 1), round(c.verlust_heute_kg / 1000.0, 1), round(c.verdunstung_heute_kg / 1000.0, 1), round((c.schimmel_heute_kg + c.sockel_heute_kg) / 1000.0, 1), round(c.fax_heute_kg / 1000.0, 1), round(c.kanal_ausgelagert_kg / 1000.0, 1), round(c.im_haus_heute_kg / 1000.0, 1), round(c.verkaufsfaehig_heute_kg / 1000.0, 1), concat_ws(' '::text, '',
            CASE
                WHEN a.marge_kg > 0::numeric THEN format('An die Tiere und in den Nebenkanal geliefert: %s kg, gerechnet: %s kg.'::text, round(a.marge_kg), round(c.kanal_ausgelagert_kg))
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
grant select on v_saisonbilanz to authenticated;
comment on view v_saisonbilanz is
  'Eingang + Überzählung = ausgeliefert + Verlust bis heute + anderer Kanal am Ausgelagerten + noch im Haus (0062). Alles bis heute(); nichts davon ist Prognose. bilanz_rest_kg ist der Rest dieser Gleichung — Erwartungswert null; die Überzählung (Lieferungen, hinter denen kein Eingang steht) steht als eigene Spalte. fax_durchsatz_kg ist die am Fax abgepackte Masse, nicht das Faule dabei (fax_heute_kg).';

-- Die gespeicherten Ergebnisse, die aus einer Liste entstehen
-- ---------------------------------------------------------------------
-- 0061 legt sechsundzwanzig davon in einer Schleife an; ihre Namen stehen
-- nicht im Quelltext, sondern in der Liste. Der Kaskadenneubau hat fünf
-- davon mitgenommen (erg_bilanz, erg_marge, erg_massenbilanz,
-- erg_naechste_charge, erg_plausibilitaet).
--
-- Wiederhergestellt wird hier die **ganze** Liste, mit derselben Angabe für
-- den Verdichter. Das ist Absicht: Sie ist damit dieselbe Anweisung wie in
-- 0061, und setup.sql behält genau eine davon — die letzte. Baute 0065 nur
-- die fünf, stünden in setup.sql zwei Schleifen für dieselben Namen, und
-- welche zuerst liefe, entschiede die Sortierung statt der Absicht.
-- verdichter: baut erg_gewichte erg_kaliber erg_gebinde erg_ausgang
-- verdichter: baut erg_lieferung erg_kohorte erg_punkte erg_modell erg_kurve
-- verdichter: baut erg_selektion erg_koeff_verdunstung erg_koeff_ausschuss
-- verdichter: baut erg_koeff_nebenkanal erg_koeff_ueberfuellung erg_wiegung
-- verdichter: baut erg_fax erg_ausschuss erg_verarbeitung_alter erg_durchsatz
-- verdichter: baut erg_bilanz erg_marge erg_massenbilanz erg_naechste_charge
-- verdichter: baut erg_datenlage erg_plausibilitaet erg_datenqualitaet
do $$
declare
  paar text[];
  paare text[][] := array[
    -- [erg-Name, Quelle]
    ['erg_gewichte',           'v_gewichtsverteilung'],
    ['erg_kaliber',            'v_kaliber_verteilung'],
    ['erg_gebinde',            'v_koeff_gebinde'],
    ['erg_ausgang',            'v_ausgang_kennzahl'],
    ['erg_lieferung',          'v_lieferung_masse'],
    ['erg_kohorte',            'v_charge_kohorte'],
    ['erg_punkte',             'v_schimmel_punkte'],
    ['erg_modell',             'v_schimmel_modell'],
    ['erg_kurve',              'v_schimmel_kurve_anzeige'],
    ['erg_selektion',          'v_selektionsverdacht'],
    ['erg_koeff_verdunstung',  'v_koeff_verdunstung'],
    ['erg_koeff_ausschuss',    'v_koeff_ausschuss'],
    ['erg_koeff_nebenkanal',   'v_koeff_nebenkanal'],
    ['erg_koeff_ueberfuellung','v_koeff_ueberfuellung'],
    ['erg_wiegung',            'v_wiegung_kennzahl'],
    ['erg_fax',                'v_fax_beobachtung'],
    ['erg_ausschuss',          'v_ausschuss_beobachtung'],
    ['erg_verarbeitung_alter', 'v_verarbeitung_alter'],
    ['erg_durchsatz',          'v_durchsatz'],
    ['erg_bilanz',             'v_saisonbilanz'],
    ['erg_marge',              'v_marge_buch'],
    ['erg_massenbilanz',       'v_massenbilanz'],
    ['erg_naechste_charge',    'v_naechste_charge'],
    ['erg_datenlage',          'v_datenlage'],
    ['erg_plausibilitaet',     'v_plausibilitaet'],
    ['erg_datenqualitaet',     'v_datenqualitaet']
  ];
begin
  foreach paar slice 1 in array paare loop
    execute format('drop materialized view if exists %I cascade', paar[1]);
    execute format('create materialized view %I as select * from %I with no data', paar[1], paar[2]);
    execute format('grant select on %I to authenticated', paar[1]);
    execute format('comment on materialized view %I is %L', paar[1],
                   format('%s, gespeichert für die App Erneuert mit auswertung_schritt().', paar[2]));
  end loop;
end $$;

-- Die Indizes der neu gebauten Ergebnisse. Ein „drop … cascade" nimmt sie
-- mit; ohne diese Zeilen hätte die Datenbank nach den Migrationen neun
-- Indizes weniger als nach setup.sql — und der Abgleich in
-- supabase/test/run.sh sagt es sofort.
create index if not exists erg_gewichte_sorte     on erg_gewichte (sorte);
create index if not exists erg_ausgang_ts         on erg_ausgang (ts);
create index if not exists erg_lieferung_datum    on erg_lieferung (datum);
create index if not exists erg_kohorte_charge     on erg_kohorte (charge_nr, eingangsdatum);
create index if not exists erg_punkte_charge      on erg_punkte (charge_nr);
create index if not exists erg_wiegung_ts         on erg_wiegung (wiege_ts);
create index if not exists erg_fax_start          on erg_fax (start_ts);
create index if not exists erg_durchsatz_start    on erg_durchsatz (start_ts);
create index if not exists erg_verarbeitung_tag   on erg_verarbeitung_alter (tag);

-- ---------- Stand der Datenbank -----------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 65 $$;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;
