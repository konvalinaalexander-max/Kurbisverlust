-- =====================================================================
-- 0062 — Jede Zahl sagt, was sie ist
--
-- Der Betriebsleiter am 9. September: „auf der Webseite hast du immer noch
-- so komische Angaben wie einfach einen Verlust, der nicht klar ist."
-- Die Durchsicht danach fand nicht nur unklare Namen, sondern zwei echte
-- Rechenfehler dahinter. Diese Migration räumt beides auf.
--
-- DIE ZWEI RECHENFEHLER
--
-- 1. Was an die Tiere und in den Nebenkanal geliefert wurde, verliess den
--    Betrieb — die Kaskade rechnete es aber weiter als Bestand: Es alterte,
--    verdunstete und verdarb auf dem Papier weiter und stand am Ende noch
--    einmal in „noch im Haus". In der Demo-Saison 2 950 kg doppelt.
--    Die Kaskade nimmt jetzt beide Bücher (verkauf und marge) als Ausgang.
--
-- 2. Lieferscheine mit einem Datum in der Zukunft zählten in jede Zahl, die
--    „bis heute" heisst — und liessen die Ware bis zu einem Liefertag nach
--    heute altern. Vordatierte Lieferscheine sind im Betrieb üblich. Sie
--    zählen jetzt erst ab ihrem Tag und fallen vorher als Befund auf.
--
-- DIE IRREFÜHRENDEN NAMEN
--
--   kanal_heute_kg      hiess „bis heute", enthielt aber zu 60 % Ware, die
--                       noch gar nicht sortiert ist → kanal_ausgelagert_kg
--                       (passiert) und kanal_im_haus_kg (Erwartung)
--   fax_kg              war der Durchsatz am Fax, nicht das Faule daneben
--                       → fax_durchsatz_kg
--   verlust_kg (Wägung) ist der Gewichtsunterschied zweier Wägungen
--                       derselben Palette, also Verdunstung → verdunstung_kg
--   verlust_14_kg       ist reine Prognose → prognose_verlust_14_kg,
--                       und sie enthält jetzt auch Sockel und Fax
--   luecke_kg           hatte das Vorzeichen der Überzählung und ging nie
--                       auf → bilanz_rest_kg, Erwartungswert 0
--   wartet_kg           war 0, wo nichts erfasst ist (nicht „nichts wartet")
--                       → gegenprobe_wartet_kg, NULL wo unbekannt
--   faul_kum_kg         enthielt den Sockel (Erde, Hagelnarben — war nie
--                       faul) → schimmel_kum_kg und sockel_kum_kg getrennt
--
-- WAS SONST EHRLICHER WIRD
--
--   * verlust_bekannt prüfte zwei von sechs Koeffizienten. Jetzt alle.
--   * Ein Verluststrom ohne Messung war 0. Jetzt NULL: Leer ist nicht null.
--   * Der Verlauf hat eine Stützstelle genau auf heute — bisher endete die
--     Ist-Linie am letzten Sonntag davor und zeigte eine andere Zahl als die
--     Kennzahl daneben.
--   * Neben sockel_heute_kg steht sockel_oben_kg: 0 heisst „nicht
--     nachweisbar", nicht „gemessen null" — und die obere Klammer ist
--     1.5 % des Eingangs.
-- =====================================================================

-- ---------- 1. Lieferungen zählen ab ihrem Tag ---------------------------
-- Ein Lieferschein mit Datum in der Zukunft ist erfasst, aber noch nicht
-- passiert. Er gehört nicht in eine Zahl, die „bis heute" heisst.
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
   where l.masse_kg is not null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge')
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
  'Gelieferte Masse je Charge, Eingangstag und Buch (verkauf, marge), mit dem '
  'massegewichteten Alter am Liefertag; nur Lieferungen bis heute() (0062). '
  'Grundlage der Rückrechnung in der Kaskade.';
grant select on v_lieferung_kohorte to authenticated;

-- ---------- 2. Die Kaskade: was geliefert ist, liegt nicht mehr ----------
-- mv_kaskade wird aus ihrem Quelltext von 0060 nachgebaut, mit genau einer
-- Änderung: Die Lieferungen umfassen beide Bücher. Ware, die als Tierfutter
-- oder in den Nebenkanal ging, ist aus dem Haus — sie darf nicht weiter
-- altern und nicht ein zweites Mal im Bestand stehen.
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
            GREATEST(((((power(((1)::numeric - x.r), x.alter_tage) * ((1)::numeric - x.a0)) * ((1)::numeric - x.f)) * (((1)::numeric - x.a_klein_n) - x.a_gross_n)) * ((1)::numeric - x.a_fax)), 0.25) AS verkaufsfaehig_anteil
           FROM mit_f x
        ), ausgelagert AS (
         SELECT a.charge_nr,
            a.sorte,
            a.schlag,
            a.eingang_kg,
            a.stichtag,
            a.r,
            a.r_bekannt,
            a.r_n,
            a.r_basis,
            a.a_klein,
            a.a_klein_bekannt,
            a.klein_n,
            a.klein_basis,
            a.a_gross,
            a.a_gross_bekannt,
            a.gross_n,
            a.gross_basis,
            a.a_fax,
            a.a_fax_bekannt,
            a.fax_n,
            a.fax_basis,
            a.a_klein_n,
            a.a_gross_n,
            a.portion,
            a.kohorte,
            a.geliefert_kg,
            a.alter_tage,
            a.eingang_kohorte_kg,
            a.n_lieferungen,
            a.u,
            a.eta,
            a.modell_gilt,
            a.f_extrapoliert,
            a.f_n,
            a.f_treppe,
            a.f_bekannt,
            a.a0,
            a.a0_bekannt,
            a.a0_var,
            a.f,
            a.verkaufsfaehig_anteil,
            (a.geliefert_kg / a.verkaufsfaehig_anteil) AS m0,
            (0)::numeric AS ueberzaehlung_kg
           FROM anteil a
          WHERE (a.portion = 'ausgelagert'::text)
        ), lager AS (
         SELECT a.charge_nr,
            a.sorte,
            a.schlag,
            a.eingang_kg,
            a.stichtag,
            a.r,
            a.r_bekannt,
            a.r_n,
            a.r_basis,
            a.a_klein,
            a.a_klein_bekannt,
            a.klein_n,
            a.klein_basis,
            a.a_gross,
            a.a_gross_bekannt,
            a.gross_n,
            a.gross_basis,
            a.a_fax,
            a.a_fax_bekannt,
            a.fax_n,
            a.fax_basis,
            a.a_klein_n,
            a.a_gross_n,
            a.portion,
            a.kohorte,
            a.geliefert_kg,
            a.alter_tage,
            a.eingang_kohorte_kg,
            a.n_lieferungen,
            a.u,
            a.eta,
            a.modell_gilt,
            a.f_extrapoliert,
            a.f_n,
            a.f_treppe,
            a.f_bekannt,
            a.a0,
            a.a0_bekannt,
            a.a0_var,
            a.f,
            a.verkaufsfaehig_anteil,
            GREATEST((a.eingang_kohorte_kg - COALESCE(x.m0, (0)::numeric)), (0)::numeric) AS m0,
            GREATEST((COALESCE(x.m0, (0)::numeric) - a.eingang_kohorte_kg), (0)::numeric) AS ueberzaehlung_kg
           FROM (anteil a
             LEFT JOIN ( SELECT ausgelagert.charge_nr,
                    ausgelagert.kohorte,
                    sum(ausgelagert.m0) AS m0
                   FROM ausgelagert
                  GROUP BY ausgelagert.charge_nr, ausgelagert.kohorte) x ON (((x.charge_nr = a.charge_nr) AND (x.kohorte = a.kohorte))))
          WHERE (a.portion = 'lager'::text)
        ), alle AS (
         SELECT ausgelagert.charge_nr,
            ausgelagert.sorte,
            ausgelagert.schlag,
            ausgelagert.eingang_kg,
            ausgelagert.stichtag,
            ausgelagert.r,
            ausgelagert.r_bekannt,
            ausgelagert.r_n,
            ausgelagert.r_basis,
            ausgelagert.a_klein,
            ausgelagert.a_klein_bekannt,
            ausgelagert.klein_n,
            ausgelagert.klein_basis,
            ausgelagert.a_gross,
            ausgelagert.a_gross_bekannt,
            ausgelagert.gross_n,
            ausgelagert.gross_basis,
            ausgelagert.a_fax,
            ausgelagert.a_fax_bekannt,
            ausgelagert.fax_n,
            ausgelagert.fax_basis,
            ausgelagert.a_klein_n,
            ausgelagert.a_gross_n,
            ausgelagert.portion,
            ausgelagert.kohorte,
            ausgelagert.geliefert_kg,
            ausgelagert.alter_tage,
            ausgelagert.eingang_kohorte_kg,
            ausgelagert.n_lieferungen,
            ausgelagert.u,
            ausgelagert.eta,
            ausgelagert.modell_gilt,
            ausgelagert.f_extrapoliert,
            ausgelagert.f_n,
            ausgelagert.f_treppe,
            ausgelagert.f_bekannt,
            ausgelagert.a0,
            ausgelagert.a0_bekannt,
            ausgelagert.a0_var,
            ausgelagert.f,
            ausgelagert.verkaufsfaehig_anteil,
            ausgelagert.m0,
            ausgelagert.ueberzaehlung_kg
           FROM ausgelagert
        UNION ALL
         SELECT lager.charge_nr,
            lager.sorte,
            lager.schlag,
            lager.eingang_kg,
            lager.stichtag,
            lager.r,
            lager.r_bekannt,
            lager.r_n,
            lager.r_basis,
            lager.a_klein,
            lager.a_klein_bekannt,
            lager.klein_n,
            lager.klein_basis,
            lager.a_gross,
            lager.a_gross_bekannt,
            lager.gross_n,
            lager.gross_basis,
            lager.a_fax,
            lager.a_fax_bekannt,
            lager.fax_n,
            lager.fax_basis,
            lager.a_klein_n,
            lager.a_gross_n,
            lager.portion,
            lager.kohorte,
            lager.geliefert_kg,
            lager.alter_tage,
            lager.eingang_kohorte_kg,
            lager.n_lieferungen,
            lager.u,
            lager.eta,
            lager.modell_gilt,
            lager.f_extrapoliert,
            lager.f_n,
            lager.f_treppe,
            lager.f_bekannt,
            lager.a0,
            lager.a0_bekannt,
            lager.a0_var,
            lager.f,
            lager.verkaufsfaehig_anteil,
            lager.m0,
            lager.ueberzaehlung_kg
           FROM lager
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
    ((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) AS m2,
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
    (m1 * a0) AS sockel_kg,
    ((m1 * ((1)::numeric - a0)) * f) AS schimmel_kg,
    (((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * a_klein_n) AS klein_kg,
    (((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * a_gross_n) AS nebenkanal_kg,
    ((((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * (((1)::numeric - a_klein_n) - a_gross_n)) * a_fax) AS fax_kg,
    ((((m1 * ((1)::numeric - a0)) * ((1)::numeric - f)) * (((1)::numeric - a_klein_n) - a_gross_n)) * ((1)::numeric - a_fax)) AS verkaufsfaehig_kg,
    kohorte,
    geliefert_kg,
    ueberzaehlung_kg,
    n_lieferungen,
    verkaufsfaehig_anteil
   FROM kaskade k
 with no data;
-- Der eindeutige Index ist Pflicht: ohne ihn kann die Sicht nicht nebenläufig
-- erneuert werden, und das Rechenwerk erneuert sie in Schritt 3.
create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, portion, coalesce(kohorte, '1900-01-01'::date));
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);
grant select on mv_kaskade to authenticated;
comment on materialized view mv_kaskade is
  'Die Massenkaskade je Charge, Eingangstag und Portion (ausgelagert / lager). '
  'Ausgelagert ist, was hinter den Lieferungen beider Bücher steckt — verkauft '
  'und in den anderen Kanal (0062); der Rest liegt und altert bis heute().';


-- ---------- 3. Was an der Kaskade hing, neu angelegt -----------------------
-- Der Reihe nach, wie sie aufeinander bauen. Unverändert übernommen, ausser
-- wo unten ausdrücklich etwas anders steht.

create or replace view v_kaskade with (security_invoker = true) as
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

drop materialized view if exists mv_hochrechnung cascade;
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
create index if not exists mv_hochrechnung_charge on mv_hochrechnung (charge_nr, buch);
grant select on mv_hochrechnung to authenticated;

create or replace view v_hochrechnung with (security_invoker = true) as
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


-- ---------- 4. Die Kennzahlen je Charge, mit ehrlichen Namen -------------

drop view if exists v_hochrechnung_basis cascade;
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
         -- 0061: bis heute
         sum(verdunstung_kg)                                                  as verdunstung_heute_kg,
         sum(schimmel_kg)                                                     as schimmel_heute_kg,
         sum(sockel_kg)                                                       as sockel_heute_kg,
         -- 0062: „bis heute" heisst passiert. Zu klein und zu gross wird beim
         -- Sortieren aussortiert — an der Ware, die noch liegt, ist das noch
         -- nicht geschehen. Also getrennt wie beim Fax: was am Ausgelagerten
         -- schon passiert ist, und was an der liegenden Ware zu erwarten ist.
         sum(klein_kg + nebenkanal_kg) filter (where portion = 'ausgelagert')  as kanal_ausgelagert_kg,
         -- Fax-Faules ist gemessen an dem, was abgepackt wurde (ausgelagert);
         -- für die Ware im Haus ist es eine Erwartung, kein Verlust bis heute
         sum(fax_kg) filter (where portion = 'ausgelagert')                   as fax_heute_kg,
         sum(fax_kg) filter (where portion = 'lager')                         as fax_erwartet_kg,
         sum(m2) filter (where portion = 'lager')                             as im_haus_heute_kg,
         sum(klein_kg + nebenkanal_kg) filter (where portion = 'lager')       as kanal_im_haus_kg,
         -- 0062: alle sechs Koeffizienten, nicht zwei. In verlust_heute_kg
         -- stecken Verdunstung, Verderb, Sockel und Fax; wie viel Fax-Masse
         -- übrig bleibt, hängt zusätzlich an zu klein und zu gross.
         bool_and(r_bekannt and f_bekannt and a0_bekannt and a_fax_bekannt
                  and a_klein_bekannt and a_gross_bekannt)                     as verlust_bekannt,
         bool_and(r_bekannt)                                                   as verdunstung_bekannt,
         bool_and(f_bekannt)                                                   as schimmel_bekannt,
         bool_and(a0_bekannt)                                                  as sockel_nachgewiesen,
         bool_and(a_fax_bekannt)                                               as fax_bekannt,
         bool_and(a_klein_bekannt and a_gross_bekannt)                         as kanal_bekannt,
         max(a0_var)                                                           as a0_var
    from mv_kaskade
   group by charge_nr
)
select b.charge_nr, b.schlag, b.sorte,
       b.eingang_kg,
       b.n_paletten,
       b.eingangsdatum_mittel,
       zahl(coalesce(k.ausgelagert_kg, 0), 2, 1e12)::numeric(14,2)             as ausgelagert_kg,
       zahl(k.alter_ausgelagert, 1, 1e5)::numeric(8,1)                         as alter_ausgelagert,
       zahl(coalesce(k.lager_kg, b.eingang_kg), 2, 1e12)::numeric(14,2)         as lager_kg,
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
       round(coalesce(k.lager_kg, b.eingang_kg)
             / nullif(b.eingang_kg / nullif(b.n_paletten, 0), 0))::int        as n_rest_paletten,
       coalesce(k.n_rest_kohorten, b.n_eingangstage)                          as n_rest_kohorten,
       (heute() - coalesce(k.rest_bis, b.eingang_bis))::int                   as alter_lager_von,
       (heute() - coalesce(k.rest_von, b.eingang_von))::int                   as alter_lager_bis,
       zahl(coalesce(k.geliefert_kg, 0), 2, 1e12)::numeric(14,2)              as geliefert_kg,
       zahl(k.verkaufsfaehig_lager_kg, 2, 1e12)::numeric(14,2)                 as verkaufsfaehig_lager_kg,
       coalesce(k.n_lieferungen, 0)                                           as n_lieferungen,
       -- neu (0061): alles bis heute, mit Namen, die es sagen
       zahl(k.verdunstung_heute_kg, 2, 1e12)::numeric(14,2)                   as verdunstung_heute_kg,
       zahl(k.schimmel_heute_kg, 2, 1e12)::numeric(14,2)                      as schimmel_heute_kg,
       zahl(k.sockel_heute_kg, 2, 1e12)::numeric(14,2)                        as sockel_heute_kg,
       zahl(coalesce(k.fax_heute_kg, 0), 2, 1e12)::numeric(14,2)              as fax_heute_kg,
       zahl(k.verdunstung_heute_kg + k.schimmel_heute_kg + k.sockel_heute_kg + coalesce(k.fax_heute_kg, 0),
            2, 1e12)::numeric(14,2)                                           as verlust_heute_kg,
       zahl(coalesce(k.kanal_ausgelagert_kg, 0), 2, 1e12)::numeric(14,2)      as kanal_ausgelagert_kg,
       zahl(coalesce(k.fax_erwartet_kg, 0), 2, 1e12)::numeric(14,2)           as fax_erwartet_kg,
       zahl(coalesce(k.im_haus_heute_kg, b.eingang_kg), 2, 1e12)::numeric(14,2) as im_haus_heute_kg,
       zahl(k.kanal_im_haus_kg, 2, 1e12)::numeric(14,2)                       as kanal_im_haus_kg,
       coalesce(k.verlust_bekannt, false)                                     as verlust_bekannt,
       coalesce(k.verdunstung_bekannt, false)                                 as verdunstung_bekannt,
       coalesce(k.schimmel_bekannt, false)                                    as schimmel_bekannt,
       coalesce(k.sockel_nachgewiesen, false)                                 as sockel_nachgewiesen,
       coalesce(k.fax_bekannt, false)                                         as fax_bekannt,
       coalesce(k.kanal_bekannt, false)                                       as kanal_bekannt,
       -- 1.96 Standardabweichungen über dem Sockel, auf die liegende Masse:
       -- was „nicht nachweisbar" im schlechtesten Fall bedeuten kann
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
  'Je Charge, alles bis heute (0061): Eingang und geliefert (gemessen), '
  'ausgelagert (Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus '
  'ausgelagert, in Eingangskilo), verlust_heute_kg (Verdunstung + Schimmel + Sockel bis '
  'heute + Fax am Abgepackten; fax_erwartet_kg steht daneben), '
  'im_haus_heute_kg (was heute nach Verdunstung und Verderb noch da ist), '
  'verkaufsfaehig_lager_kg (davon in der richtigen Grösse). Keine Prognose. '
  '0062: kanal_ausgelagert_kg ist der andere Kanal, der schon passiert ist; '
  'kanal_im_haus_kg ist die Erwartung an der liegenden Ware. verlust_bekannt '
  'prüft alle sechs Koeffizienten, je Strom steht ein eigenes Flag daneben; '
  'sockel_oben_kg ist die obere Klammer des Sockels — 0 heisst nicht nachweisbar.';



grant select on v_hochrechnung_basis to authenticated;

drop materialized view if exists erg_charge cascade;
create materialized view erg_charge as select * from v_hochrechnung_basis with no data;
grant select on erg_charge to authenticated;
comment on materialized view erg_charge is 'v_hochrechnung_basis, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';
create unique index if not exists erg_charge_pk on erg_charge (charge_nr);
create index if not exists erg_charge_sorte on erg_charge (sorte);


-- ---------- 5. Die Ströme je Gruppe, unverändert übernommen --------------

create or replace view v_verlust_je_gruppe with (security_invoker = true) as
WITH gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text,
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

drop materialized view if exists erg_verlust cascade;
create materialized view erg_verlust as select * from v_verlust_je_gruppe with no data;
grant select on erg_verlust to authenticated;
comment on materialized view erg_verlust is 'v_verlust_je_gruppe, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';
create unique index if not exists erg_verlust_pk on erg_verlust (gruppe, schluessel, strom);

create or replace view v_marge_buch with (security_invoker = true) as
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

drop materialized view if exists erg_marge cascade;
create materialized view erg_marge as select * from v_marge_buch with no data;
grant select on erg_marge to authenticated;
comment on materialized view erg_marge is 'v_marge_buch, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';

create or replace view v_massenbilanz with (security_invoker = true) as
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

drop materialized view if exists erg_massenbilanz cascade;
create materialized view erg_massenbilanz as select * from v_massenbilanz with no data;
grant select on erg_massenbilanz to authenticated;
comment on materialized view erg_massenbilanz is 'v_massenbilanz, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';


-- ---------- 6. Die nächsten 14 Tage sind Prognose, und heissen so --------

create or replace view v_naechste_charge with (security_invoker = true) as
with modell as materialized (
  select * from v_schimmel_modell
), kohorten as materialized (
  select charge_nr, eingangsdatum, anteil from v_kohorte_anteil
), bestand as (
  select b.charge_nr, b.sorte, b.schlag, b.lager_kg,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05) as r,
         t.m0, t.alter_tage
    from erg_charge b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    cross join lateral (
      select b.lager_kg * c.anteil as m0,
             greatest((heute() - c.eingangsdatum)::numeric, 0) as alter_tage
        from kohorten c where c.charge_nr = b.charge_nr
      union all
      select b.lager_kg, greatest(b.alter_lager_heute, 0)
       where not exists (select 1 from kohorten c where c.charge_nr = b.charge_nr)
    ) t
   where b.lager_kg > 0
), mit_f as (
  select b.*,
         b.m0 * power(1 - b.r, b.alter_tage) as masse_jetzt_kg,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage, 1)), -40), 3))), 0), 0.99) end as f_jetzt,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage + 14, 1)), -40), 3))), 0), 0.99) end as f_dann,
         (m.brauchbar and b.alter_tage > m.t_max) as hochgerechnet,
         m.brauchbar as modell_gilt
    from bestand b cross join modell m
), je_charge as (
  select charge_nr, sorte, schlag, lager_kg, modell_gilt,
         bool_or(hochgerechnet)                                        as hochgerechnet,
         sum(masse_jetzt_kg)                                           as masse_jetzt_kg,
         sum(masse_jetzt_kg * alter_tage) / nullif(sum(masse_jetzt_kg), 0) as alter_tage,
         min(alter_tage) as alter_von, max(alter_tage) as alter_bis,
         count(*)::int as n_kohorten,
         sum(masse_jetzt_kg * (1 - power(1 - r, 14)))                  as verdunstung_14_kg,
         case when modell_gilt
              then sum(masse_jetzt_kg * (f_dann - f_jetzt) / nullif(1 - f_jetzt, 0)) end as schimmel_14_kg
    from mit_f
   group by charge_nr, sorte, schlag, lager_kg, modell_gilt
)
select charge_nr, sorte, schlag,
       zahl(lager_kg, 2, 1e12)::numeric(14,2)                               as lager_kg,
       round(alter_tage)::int                                               as alter_tage,
       zahl(masse_jetzt_kg, 2, 1e12)::numeric(14,2)                         as masse_jetzt_kg,
       zahl(verdunstung_14_kg, 1, 1e11)::numeric(12,1)                      as verdunstung_14_kg,
       zahl(schimmel_14_kg, 1, 1e11)::numeric(12,1)                         as schimmel_14_kg,
       -- 0062: Das ist reine Prognose — der Name sagt es jetzt. Und wo das
       -- Verderbsmodell nicht gilt, bleibt die Zahl leer statt heimlich auf
       -- die Verdunstung allein zusammenzuschrumpfen.
       zahl(verdunstung_14_kg + schimmel_14_kg, 1, 1e11)::numeric(12,1)      as prognose_verlust_14_kg,
       hochgerechnet, modell_gilt,
       round(alter_von)::int as alter_von, round(alter_bis)::int as alter_bis, n_kohorten
  from je_charge
 order by zahl(verdunstung_14_kg + coalesce(schimmel_14_kg, 0), 1, 1e11)::numeric(12,1) desc nulls last;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag '
  'ab heute() gerechnet und je Charge summiert; der Bestand aus erg_charge (0061). '
  'prognose_verlust_14_kg ist Verdunstung + Verderb der nächsten 14 Tage — reine '
  'Prognose, nicht im Verlust bis heute enthalten, und leer, wo das Modell nicht '
  'gilt. Sockel und Fax stecken nicht darin (0062).';



grant select on v_naechste_charge to authenticated;

drop materialized view if exists erg_naechste_charge cascade;
create materialized view erg_naechste_charge as select * from v_naechste_charge with no data;
grant select on erg_naechste_charge to authenticated;
comment on materialized view erg_naechste_charge is 'v_naechste_charge, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';

create or replace view v_kontrolle_vorschlag with (security_invoker = true) as
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


-- ---------- 7. Die Saisonbilanz: die Gleichung, die wirklich gilt --------

create view v_saisonbilanz with (security_invoker = true) as
with charge as (
  select sum(eingang_kg)                 as eingang_kg,
         sum(ausgelagert_kg)             as ausgelagert_kg,
         sum(geliefert_kg)               as geliefert_kg,
         sum(lager_kg)                   as lager_kg,
         sum(wartet_kg)                  as wartet_kg,
         sum(ueberzaehlung_kg)           as ueberzaehlung_kg,
         sum(verkaufsfaehig_lager_kg)    as verkaufsfaehig_heute_kg,
         sum(im_haus_heute_kg)           as im_haus_heute_kg,
         sum(kanal_im_haus_kg)           as kanal_im_haus_kg,
         sum(verlust_heute_kg)           as verlust_heute_kg,
         sum(verdunstung_heute_kg)       as verdunstung_heute_kg,
         sum(schimmel_heute_kg)          as schimmel_heute_kg,
         sum(sockel_heute_kg)            as sockel_heute_kg,
         sum(fax_heute_kg)               as fax_heute_kg,
         sum(fax_erwartet_kg)            as fax_erwartet_kg,
         sum(kanal_ausgelagert_kg)       as kanal_ausgelagert_kg,
         bool_and(verlust_bekannt)       as bekannt,
         count(*)::int                   as n_chargen,
         max(heute)                      as heute
    from erg_charge
), bereich as (
  select sum(kg_unten) filter (where buch in ('verlust', 'feld')) as verlust_unten_kg,
         sum(kg_oben)  filter (where buch in ('verlust', 'feld')) as verlust_oben_kg,
         sum(kg)       filter (where buch in ('verlust', 'feld')) as verlust_kg,
         sum(kg_unten) filter (where buch = 'marge')              as kanal_unten_kg,
         sum(kg_oben)  filter (where buch = 'marge')              as kanal_oben_kg
    from erg_verlust where gruppe = 'gesamt'
), vorlauf as (
  select coalesce(sum(ausgang_vor_app_kg), 0) as kg from charge_vorlauf
), ausgang as (
  -- 0062: nur, was bis heute geliefert ist. Ein Lieferschein mit Datum in der
  -- Zukunft ist erfasst, aber noch nicht passiert.
  select coalesce(sum(masse_kg), 0)                                as kg,
         coalesce(sum(masse_kg) filter (where buch = 'verkauf'), 0) as verkauf_kg,
         coalesce(sum(masse_kg) filter (where buch = 'marge'), 0)   as marge_kg,
         coalesce(sum(masse_kg) filter (where buch = 'verlust'), 0) as entsorgt_kg,
         coalesce(sum(masse_fehler_kg), 0)                          as fehler_kg,
         count(*)::int                                             as n_lieferungen,
         max(datum)                                                as letzte_lieferung
    from v_lieferung_masse where datum <= heute()
), fax as (
  select coalesce(sum(masse_kg), 0) as kg, count(*)::int as n
    from v_fax_beobachtung where status = 'abgeschlossen' and masse_kg is not null
)
select c.heute,
       zahl(c.eingang_kg)::numeric(14,2)                       as eingang_kg,
       c.n_chargen,
       -- was den Betrieb verlassen hat (gemessen)
       zahl(a.kg + vl.kg)::numeric(14,2)                       as ausgang_kg,
       zahl(a.verkauf_kg)::numeric(14,2)                       as verkauf_kg,
       zahl(a.marge_kg)::numeric(14,2)                         as marge_kg,
       zahl(a.entsorgt_kg)::numeric(14,2)                      as entsorgt_kg,
       zahl(a.fehler_kg)::numeric(14,2)                        as ausgang_fehler_kg,
       a.n_lieferungen,
       a.letzte_lieferung,
       zahl(vl.kg)::numeric(14,2)                              as vorlauf_kg,
       zahl(c.geliefert_kg)::numeric(14,2)                     as geliefert_kg,
       zahl(c.ausgelagert_kg)::numeric(14,2)                   as ausgelagert_kg,
       -- der Verlust bis heute (gerechnet), mit Bereich
       zahl(c.verlust_heute_kg)::numeric(14,2)                 as verlust_heute_kg,
       zahl(b.verlust_unten_kg)::numeric(14,2)                 as verlust_unten_kg,
       zahl(b.verlust_oben_kg)::numeric(14,2)                  as verlust_oben_kg,
       zahl(c.verdunstung_heute_kg)::numeric(14,2)             as verdunstung_heute_kg,
       zahl(c.schimmel_heute_kg)::numeric(14,2)                as schimmel_heute_kg,
       zahl(c.sockel_heute_kg)::numeric(14,2)                  as sockel_heute_kg,
       zahl(c.fax_heute_kg)::numeric(14,2)                     as fax_heute_kg,
       zahl(c.fax_erwartet_kg)::numeric(14,2)                  as fax_erwartet_kg,
       -- kein echter Verlust: anderer Kanal
       zahl(c.kanal_ausgelagert_kg)::numeric(14,2)             as kanal_ausgelagert_kg,
       zahl(b.kanal_unten_kg)::numeric(14,2)                   as kanal_unten_kg,
       zahl(b.kanal_oben_kg)::numeric(14,2)                    as kanal_oben_kg,
       -- was heute noch da ist
       zahl(c.im_haus_heute_kg)::numeric(14,2)                 as im_haus_heute_kg,
       zahl(c.verkaufsfaehig_heute_kg)::numeric(14,2)          as verkaufsfaehig_heute_kg,
       zahl(c.kanal_im_haus_kg)::numeric(14,2)                 as kanal_im_haus_kg,
       zahl(c.lager_kg)::numeric(14,2)                         as lager_kg,
       zahl(c.wartet_kg)::numeric(14,2)                        as gegenprobe_wartet_kg,
       zahl(c.ueberzaehlung_kg)::numeric(14,2)                 as ueberzaehlung_kg,
       -- 0062: das ist der Durchsatz am Fax, nicht das Faule dabei. Das Faule
       -- steht als fax_heute_kg weiter oben — sie unterscheiden sich um das
       -- Fünfzigfache, und die alten Namen lagen nebeneinander.
       zahl(f.kg)::numeric(14,2)                               as fax_durchsatz_kg,
       f.n                                                     as n_fax_arbeiten,
       coalesce(c.bekannt, false)                              as verlust_bekannt,
       -- 0062: Die Gleichung, die wirklich gilt, hat die Überzählung auf der
       -- Eingangsseite: Eingang + Überzählung = geliefert + Verlust bis heute
       -- + Kanal am Ausgelagerten + noch im Haus. Was übrig bleibt, ist der
       -- Rundungsrest — Erwartungswert null. Die alte Spalte luecke_kg trug
       -- das Vorzeichen der Überzählung und ging nie auf.
       zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg
            - c.kanal_ausgelagert_kg - c.im_haus_heute_kg)::numeric(14,2)
                                                               as bilanz_rest_kg,
       zahl(case when c.eingang_kg > 0
                 then (c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.verlust_heute_kg
                       - c.kanal_ausgelagert_kg - c.im_haus_heute_kg) / c.eingang_kg end,
            4, 1e5)::numeric(10,4)                             as bilanz_rest_anteil,
       zahl(case when c.eingang_kg > 0 then (a.kg + vl.kg) / c.eingang_kg end, 4, 1e5)::numeric(10,4)
                                                               as ausgang_deckung,
       case
         when coalesce(c.eingang_kg, 0) <= 0
           then 'Es ist kein Wareneingang erfasst. Ohne das Erntejournal gibt es '
                || 'nichts, worauf sich Verlust und Bestand beziehen könnten.'
         when coalesce(c.ueberzaehlung_kg, 0) > 0.05 * c.eingang_kg
           then format('Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — '
                       || 'bei einigen Chargen rund %s kg zu viel. Fast immer fehlt der '
                       || 'Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine '
                       || 'Lieferung ist der falschen Charge zugeordnet.',
                       round(c.ueberzaehlung_kg))
         when a.n_lieferungen = 0 and vl.kg = 0
           then 'Kein Warenausgang erfasst — dann liegt rechnerisch noch alles im Haus, '
                || 'und der Verlust bis heute gilt für die ganze Eingangsmasse. Sobald die '
                || 'Lieferscheine eingelesen sind, teilt sich die Ware in ausgeliefert und liegend.'
         when not coalesce(c.bekannt, false)
           then 'Ein Verluststrom ist noch nicht gemessen — die Ursachen sind erst '
                || 'vollständig, wenn jeder Koeffizient mindestens eine Messung hat.'
         else format('Bis heute (%s): %s t Eingang = %s t ausgeliefert + %s t Verlust '
                     || '(Verdunstung %s t, Faules %s t, Fax %s t) + %s t anderer Kanal '
                     || '+ %s t noch im Haus (davon %s t verkaufsfähig). Die Prognose bis zum '
                     || 'Saisonende steht in der Grafik, nicht in diesen Zahlen.%s',
                     to_char(c.heute, 'DD.MM.YYYY'),
                     round(c.eingang_kg / 1000.0, 1),
                     round(c.geliefert_kg / 1000.0, 1),
                     round(c.verlust_heute_kg / 1000.0, 1),
                     round(c.verdunstung_heute_kg / 1000.0, 1),
                     round((c.schimmel_heute_kg + c.sockel_heute_kg) / 1000.0, 1),
                     round(c.fax_heute_kg / 1000.0, 1),
                     round(c.kanal_ausgelagert_kg / 1000.0, 1),
                     round(c.im_haus_heute_kg / 1000.0, 1),
                     round(c.verkaufsfaehig_heute_kg / 1000.0, 1),
                     concat_ws(' ', '',
                       case when a.marge_kg > 0
                            then format('An die Tiere und in den Nebenkanal geliefert: %s kg, gerechnet: %s kg.',
                                        round(a.marge_kg), round(c.kanal_ausgelagert_kg)) end,
                       case when a.entsorgt_kg > 0
                            then format('Entsorgt: %s kg, gerechneter Schimmel: %s kg.',
                                        round(a.entsorgt_kg), round(c.schimmel_heute_kg)) end,
                       case when coalesce(c.ueberzaehlung_kg, 0) > 0
                            then format('%s kg Überzählung.', round(c.ueberzaehlung_kg)) end))
       end                                                     as befund
  from charge c cross join bereich b cross join ausgang a cross join vorlauf vl cross join fax f;
comment on view v_saisonbilanz is
  'Eingang + Überzählung = ausgeliefert + Verlust bis heute + anderer Kanal am '
  'Ausgelagerten + noch im Haus (0062). Alles bis heute(); nichts davon ist '
  'Prognose. bilanz_rest_kg ist der Rest dieser Gleichung — Erwartungswert null; '
  'die Überzählung (Lieferungen, hinter denen kein Eingang steht) steht als '
  'eigene Spalte. fax_durchsatz_kg ist die am Fax abgepackte Masse, nicht das '
  'Faule dabei (fax_heute_kg).';
grant select on v_saisonbilanz to authenticated;


grant select on v_saisonbilanz to authenticated;

drop materialized view if exists erg_bilanz cascade;
create materialized view erg_bilanz as select * from v_saisonbilanz with no data;
grant select on erg_bilanz to authenticated;
comment on materialized view erg_bilanz is 'v_saisonbilanz, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';


-- ---------- 8. Der Verlauf: Stützstelle auf heute, Sockel getrennt -------

drop materialized view if exists erg_verlauf cascade;
create materialized view erg_verlauf as
with modell as materialized (
  select * from v_schimmel_modell
), kurve as materialized (
  select von, anteil_mono from v_schimmel_kurve where n > 0
), wochen as materialized (
  -- 0062: eine Stützstelle genau auf heute(). Ohne sie endete die Ist-Linie am
  -- letzten Sonntag davor und zeigte eine andere Zahl als die Kennzahl daneben
  -- — bis zu sechs Tage Unterschied. Jetzt trifft die Grafik den Stand.
  select woche, bis from (
    select w::date as woche, (w + interval '6 days')::date as bis
      from generate_series(
        date_trunc('week', coalesce((select min(eingangsdatum) from palette), heute()))::date,
        date_trunc('week', stichtag())::date, interval '7 days') w
    union
    select date_trunc('week', heute())::date, heute()
  ) x
), portionen as materialized (
  select k.charge_nr, k.sorte, k.portion, k.kohorte, k.m0, k.r, k.a0, k.modell_gilt,
         case when k.portion = 'ausgelagert' then k.kohorte + round(k.alter_tage)::int end as liefertag,
         case when k.portion = 'ausgelagert' then k.fax_kg else 0 end                     as fax_kg
    from mv_kaskade k
   where k.m0 > 0 and k.kohorte is not null
-- F(t) hängt nur vom Alter in Tagen ab, nicht von der Portion. Einmal je Tag
-- gerechnet statt einmal je Portion und Woche: bei dreifacher Saison sind das
-- 400 Zeilen statt 113 000 — und die Kurvensuche (ein Sortieren je Zeile)
-- entfällt genauso oft. Das ist der Unterschied zwischen 4.9 und 0.6 Sekunden.
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
  select w.woche, w.bis, p.sorte,
         p.m0 * (1 - power(1 - p.r, x.t))                                     as verdunstung_kg,
         -- 0062: Sockel und Schimmel getrennt. Der Sockel (Erde, Hagelnarben,
         -- Schnittfehler) landet im Palox, war aber nie faul — beides unter
         -- „Faules" zu führen, war schon im Namen falsch.
         p.m0 * power(1 - p.r, x.t) * p.a0                                     as sockel_kg,
         p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * f.f                         as schimmel_kg,
         -- Fax-Faules: gemessen am Abgepackten, gebucht am Liefertag
         case when p.liefertag is not null and p.liefertag <= w.bis then p.fax_kg else 0 end as fax_kg,
         -- im Haus: was von der Portion nach Verdunstung und Verderb noch da
         -- ist — solange sie nicht ausgeliefert ist. Danach ist sie weg, samt
         -- dem, was an ihr zu klein oder zu gross war.
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0 - (1 - p.a0) * f.f)
              else 0 end                                                      as im_haus_kg
    from wochen w
    join portionen p on p.kohorte <= w.bis
    cross join lateral (
      select greatest(least(w.bis, coalesce(p.liefertag, w.bis)) - p.kohorte, 0) as t
    ) x
    join f_je_tag f on f.t = x.t
), verlust as (
  select woche, bis, sorte,
         sum(verdunstung_kg) as verdunstung_kg,
         sum(sockel_kg) as sockel_kg, sum(schimmel_kg) as schimmel_kg,
         sum(fax_kg) as fax_kg,
         sum(im_haus_kg) as im_haus_kg
    from je_woche
   group by grouping sets ((woche, bis, sorte), (woche, bis))
), eingang as (
  select w.woche, w.bis, p.sorte, sum(p.netto_kg) as kg
    from wochen w
    join (select v.eingangsdatum, c.sorte, v.netto_kg from v_palette v join charge c on c.nr = v.charge_nr) p
      on p.eingangsdatum <= w.bis
   group by grouping sets ((w.woche, w.bis, p.sorte), (w.woche, w.bis))
), ausgang as (
  select w.woche, w.bis, l.sorte, sum(l.masse_kg) as kg
    from wochen w
    join (select l.datum, coalesce(l.sorte, c.sorte) as sorte, l.masse_kg
            from v_lieferung_masse l left join charge c on c.nr = l.charge_nr
           where l.masse_kg is not null
          union all
          select coalesce((select nullif(wert #>> '{}', '')::date from einstellung where schluessel = 'erfassungsbeginn'),
                          r.letzter_eingang), r.sorte, cv.ausgang_vor_app_kg
            from charge_vorlauf cv join v_charge_rueckgrat r on r.charge_nr = cv.charge_nr
           where cv.ausgang_vor_app_kg > 0) l
      on l.datum <= w.bis
   group by grouping sets ((w.woche, w.bis, l.sorte), (w.woche, w.bis))
)
select w.woche, w.bis, (w.bis > heute())                                      as prognose,
       s.sorte,
       zahl(coalesce(e.kg, 0), 2, 1e12)::numeric(14,2)                         as eingang_kum_kg,
       zahl(coalesce(a.kg, 0), 2, 1e12)::numeric(14,2)                         as ausgang_kum_kg,
       zahl(coalesce(v.verdunstung_kg, 0), 2, 1e12)::numeric(14,2)             as verdunstung_kum_kg,
       zahl(coalesce(v.schimmel_kg, 0), 2, 1e12)::numeric(14,2)                as schimmel_kum_kg,
       zahl(coalesce(v.sockel_kg, 0), 2, 1e12)::numeric(14,2)                  as sockel_kum_kg,
       zahl(coalesce(v.fax_kg, 0), 2, 1e12)::numeric(14,2)                     as fax_kum_kg,
       zahl(coalesce(v.verdunstung_kg, 0) + coalesce(v.schimmel_kg, 0)
            + coalesce(v.sockel_kg, 0) + coalesce(v.fax_kg, 0), 2, 1e12)::numeric(14,2)
                                                                              as verlust_kum_kg,
       zahl(coalesce(v.im_haus_kg, 0), 2, 1e12)::numeric(14,2)                 as im_haus_kg
  from wochen w
  cross join (select distinct sorte from verlust) s
  left join verlust v on v.bis = w.bis and v.sorte is not distinct from s.sorte
  left join eingang e on e.bis = w.bis and e.sorte is not distinct from s.sorte
  left join ausgang a on a.bis = w.bis and a.sorte is not distinct from s.sorte
 with no data;
grant select on erg_verlauf to authenticated;
comment on materialized view erg_verlauf is
  'Je Woche (und je Sorte; sorte NULL = alles), mit einer Stützstelle genau auf '
  'heute() (0062): Eingang und Ausgang kumuliert '
  '(gemessen, Ausgang: alle Lieferungen), der Verlust kumuliert (gerechnet, bis heute), '
  'danach als Prognose bis zum Saisonende (prognose = true). im_haus_kg: je Portion, '
  'was nach Verdunstung und Verderb noch da ist, solange sie nicht ausgeliefert ist. '
  'schimmel_kum_kg und sockel_kum_kg stehen getrennt: der Sockel war nie faul (0062).';



-- 0062: Der Schlüssel ist das Ende des Zeitraums, nicht die Woche. Die Woche,
-- in der heute liegt, hat zwei Zeilen: eine bis heute (Ist) und eine bis zum
-- Wochenende (Prognose) — das ist der Sinn der Stützstelle.
create unique index if not exists erg_verlauf_pk on erg_verlauf (bis, coalesce(sorte, ''));
create index if not exists erg_verlauf_woche on erg_verlauf (woche);
grant select on erg_verlauf to authenticated;

-- ---------- 9. Die Wägung misst Verdunstung, nicht „Verlust" --------------
-- Dieselbe Palette wird zweimal gewogen; niemand nimmt dazwischen einen
-- Kürbis heraus. Der Unterschied ist entwichenes Wasser. Die Spalte hiess
-- trotzdem verlust_kg und stand im selben Bildschirm neben dem gerechneten
-- Gesamtverlust — zwei ganz verschiedene Dinge unter einem Wort.
-- Eine Spalte wird umbenannt — also neu anlegen, nicht ersetzen.
drop view if exists v_wiegung_kennzahl cascade;
create view v_wiegung_kennzahl with (security_invoker = true) as
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
    -- 0062: hiess verlust_kg. Dieselbe Palette wird zweimal gewogen, und
    -- niemand nimmt dazwischen einen Kürbis heraus — der Unterschied ist
    -- entwichenes Wasser. Neben dem gerechneten Gesamtverlust im selben
    -- Bildschirm war „Verlust" für zwei ganz verschiedene Dinge dasselbe Wort.
    zahl((n.netto_damals_kg - n.netto_jetzt_kg), 2, 1e8)::numeric(10,2) AS verdunstung_kg
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT zahl((w.brutto_damals_kg - COALESCE(w.kisten, 0)::numeric * g.tara_kg_pro_kiste - COALESCE(g.tara_kg_palette, 0::numeric)), 2, 1e8)::numeric(10,2) AS netto_damals_kg,
            zahl((w.brutto_jetzt_kg - COALESCE(w.kisten, 0)::numeric * g.tara_kg_pro_kiste - COALESCE(g.tara_kg_palette, 0::numeric)), 2, 1e8)::numeric(10,2) AS netto_jetzt_kg) n
  WHERE w.gemessen AND (a.id IS NULL OR a.abgebrochen_ts IS NULL);
comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, die Verdunstung dazwischen '
  '(0062 — vorher verlust_kg), kg je Kiste und je Kürbis.';
grant select on v_wiegung_kennzahl to authenticated;
drop materialized view if exists erg_wiegung cascade;
create materialized view erg_wiegung as select * from v_wiegung_kennzahl with no data;
create index if not exists erg_wiegung_ts on erg_wiegung (wiege_ts);
grant select on erg_wiegung to authenticated;
comment on materialized view erg_wiegung is
  'v_wiegung_kennzahl, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';

-- ---------- 10. Eine Lieferung mit Datum in der Zukunft fällt auf ---------
-- Vordatierte Lieferscheine sind üblich. Sie zählen seit 0062 erst ab ihrem
-- Tag; damit niemand sie für verschwunden hält, nennt die Plausibilität sie.
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
 where l.datum > heute() and l.masse_kg is not null and l.masse_kg > 0;
grant select on v_plausibilitaet_0054_zusatz to authenticated;

-- ---------- 11. Ein Kommentar, der die falsche Auskunft gab --------------
-- erg_ueberfuellung wird in Schritt 1 erneuert, nicht in Schritt 4; im
-- Datenbankkommentar von 0061 stand die falsche Zahl. Wer danach eine
-- Neuberechnung von Hand anstösst, wartet sonst auf einen Schritt, der diese
-- Sicht gar nicht anfasst. Bereits eingespielte Datenbanken bekommen die
-- Berichtigung hier.
comment on materialized view erg_ueberfuellung is
  'v_ueberfuellung_verkauf, gespeichert für die App (0061). Erneuert mit auswertung_schritt(1).';

-- ---------- 12. Ein Name, der mehr verspricht, als er hält ---------------
-- v_verlust_ranking listet *alle* Ströme der Kaskade, auch die, die kein
-- Verlust sind: zu klein und zu gross gehen in einen anderen Kanal (buch =
-- 'marge'), der Sockel ist nicht lagerbedingt (buch = 'feld'). Die Sicht ist
-- ein Werkzeug für die Diagnose und steht auf keinem Bildschirm; wer sie im
-- SQL-Editor öffnet, soll das aber wissen, statt die Summe für den Verlust zu
-- halten. Der Kommentar sagt es jetzt.
comment on view v_verlust_ranking is
  'Alle Ströme der Kaskade für eine Gruppe, absteigend nach Masse — nicht nur '
  'Verlust: buch sagt, was es ist (verlust = echter Verlust, marge = anderer '
  'Kanal, feld = nicht lagerbedingt). Nur für Diagnose und SQL-Editor; die App '
  'liest erg_verlust. Wer über alle Zeilen summiert, summiert Äpfel und Birnen.';

-- ---------- 13. Stand der Datenbank ---------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 62 $$;

-- Alles, was diese Migration angefasst hat, ist leer angelegt. Wer sie im
-- SQL-Editor einspielt, rechnet danach einmal — genau wie nach jeder anderen.
do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;
