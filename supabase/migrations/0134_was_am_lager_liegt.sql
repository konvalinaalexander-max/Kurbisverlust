-- 0134 — Was am Lager liegt (Runde BJ, Schritt 4)
--
-- Der Betrieb am 7. November, zum Plan: „Überzählung getrennt" — sicher ein
-- Datenfehler, wenn mehr geliefert als hereingekommen ist; „die Rate passt
-- nicht zur Charge", und das nur, wenn die Lieferungen ausserhalb der Spanne
-- liegen. „Pro Charge: liegt noch etwa N Paletten", damit er beim Zählen
-- vergleichen kann. Und ein Knopf „Charge ist leer (am Lager bestätigt)":
-- „Dann gilt Eingang minus geliefert als echter Verlust, und damit prüft die
-- App ihre Raten."
--
-- Bis hier hiess jede Überzählung „mehr geliefert als gekommen — ein Zettel
-- oder eine Zuordnung stimmt nicht", auch wenn weniger hinausging, als
-- hereinkam, und nur die gerechneten Raten mehr Eingang verlangten (1630,
-- 1620, 1625, 1614, 1627, 1650). Und eine Charge, die am Lager leer war, lag
-- in der App weiter mit dem Rest, den die Raten erwarten.
--
--   charge.leer_am        das Datum, an dem der Betriebsleiter die Charge am
--                         Lager leer gefunden hat (null: nicht bestätigt)
--   mv_kaskade            eine leer bestätigte Charge hat ab dem Tag nichts
--                         mehr im Lager; ihre Lagerzeile bleibt mit 0 stehen
--   v_charge_bedarf       je Charge: wie viel Eingang die Lieferungen
--                         brauchen — mit den Raten, mit den günstigsten und
--                         den ungünstigsten der Spanne; die Art der
--                         Überzählung; bei einer leeren Charge der echte
--                         Verlust gegen den gerechneten
--   v_am_lager            je Eingangstag: was noch liegt, in Paletten
--   v_ungereimtheit,      melden die Überzählung nur noch als Datenfehler
--   v_plausibilitaet_…    oder als Rate, die nicht passt — nicht, wenn sie
--                         in der Spanne liegt
--
-- Hagel-Chargen bleiben aussen vor: ihre Lieferungen kommen aus dem
-- Ünique-Topf (0133), der seine Überzählung selbst sagt (v_unique_topf).

alter table charge add column if not exists leer_am date;
alter table charge add column if not exists leer_ts timestamptz;
comment on column charge.leer_am is
  'Der Tag, an dem der Betriebsleiter die Charge am Lager leer gefunden hat (0134). Ab dann hat sie in der Kaskade nichts mehr im Lager, und Eingang minus geliefert ist ihr echter Verlust (v_charge_bedarf). Null: nicht bestätigt — dann rechnet die App mit dem Rest, den die Raten erwarten.';
comment on column charge.leer_ts is 'Wann „Charge ist leer" zuletzt gesetzt oder zurückgenommen wurde (0134).';

-- ========== Die Kaskade und was an ihr hängt, neu gedruckt (eine leere Charge hat kein Lager mehr) ==========
drop materialized view if exists mv_kaskade cascade;


-- ---------- mv_kaskade ----------
create materialized view mv_kaskade as
 WITH kohorten AS MATERIALIZED (
         SELECT k.charge_nr,
            k.eingangsdatum,
            k.anteil,
            b.eingang_kg * k.anteil AS eingang_kg
           FROM v_kohorte_anteil k
             JOIN v_kaskade_basis b ON b.charge_nr = k.charge_nr
        ), lieferungen AS MATERIALIZED (
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            sum(v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, 0::numeric)) / NULLIF(sum(v_lieferung_kohorte.masse_kg), 0::numeric) AS alter_tage,
            sum(v_lieferung_kohorte.n_lieferungen)::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE v_lieferung_kohorte.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), entsorgt_lief AS (
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            sum(v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, 0::numeric)) / NULLIF(sum(v_lieferung_kohorte.masse_kg), 0::numeric) AS alter_tage,
            sum(v_lieferung_kohorte.n_lieferungen)::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE v_lieferung_kohorte.buch = 'verlust'::text
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), koeff AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.eingang_kg,
            b.stichtag,
            LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            kv.mittel IS NOT NULL AS r_bekannt,
            kv.n AS r_n,
            kv.basis AS r_basis,
                CASE
                    WHEN hc.hagel_anteil > 0::numeric THEN 0::numeric
                    ELSE LEAST(GREATEST(COALESCE(ka.mittel, 0::numeric), 0::numeric), 1::numeric)
                END AS a_klein,
            hc.hagel_anteil > 0::numeric OR ka.mittel IS NOT NULL AS a_klein_bekannt,
                CASE
                    WHEN hc.hagel_anteil > 0::numeric THEN 0
                    ELSE ka.n
                END AS klein_n,
                CASE
                    WHEN hc.hagel_anteil > 0::numeric THEN 'Hagel-Charge (Ünique-Topf): nicht nach Grösse sortiert'::text
                    ELSE ka.basis
                END AS klein_basis,
                CASE
                    WHEN hc.hagel_anteil > 0::numeric THEN 0::numeric
                    ELSE LEAST(GREATEST(COALESCE(kn.mittel, 0::numeric), 0::numeric), 1::numeric)
                END AS a_gross,
            hc.hagel_anteil > 0::numeric OR kn.mittel IS NOT NULL AS a_gross_bekannt,
                CASE
                    WHEN hc.hagel_anteil > 0::numeric THEN 0
                    ELSE kn.n
                END AS gross_n,
                CASE
                    WHEN hc.hagel_anteil > 0::numeric THEN 'Hagel-Charge (Ünique-Topf): nicht nach Grösse sortiert'::text
                    ELSE kn.basis
                END AS gross_basis,
                CASE
                    WHEN hc.hagel_anteil > 0::numeric THEN 0::numeric
                    ELSE LEAST(GREATEST(COALESCE(kf.mittel, 0::numeric), 0::numeric), 1::numeric)
                END AS a_fax,
            hc.hagel_anteil > 0::numeric OR kf.mittel IS NOT NULL AS a_fax_bekannt,
                CASE
                    WHEN hc.hagel_anteil > 0::numeric THEN 0
                    ELSE kf.n
                END AS fax_n,
                CASE
                    WHEN hc.hagel_anteil > 0::numeric THEN 'Hagel-Charge (Ünique-Topf): kein Fax'::text
                    ELSE kf.basis
                END AS fax_basis
           FROM v_kaskade_basis b
             LEFT JOIN charge hc ON hc.nr = b.charge_nr
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b.sorte
             LEFT JOIN v_koeff_ausschuss ka ON ka.sorte = b.sorte
             LEFT JOIN v_koeff_nebenkanal kn ON kn.sorte = b.sorte
             LEFT JOIN v_koeff_fax kf ON kf.sorte = b.sorte
          WHERE b.eingang_kg > 0::numeric
        ), koeff_norm AS (
         SELECT k.charge_nr,
            k.sorte,
            k.schlag,
            k.eingang_kg,
            k.stichtag,
            k.r,
            k.r_bekannt,
            k.r_n,
            k.r_basis,
            k.a_klein,
            k.a_klein_bekannt,
            k.klein_n,
            k.klein_basis,
            k.a_gross,
            k.a_gross_bekannt,
            k.gross_n,
            k.gross_basis,
            k.a_fax,
            k.a_fax_bekannt,
            k.fax_n,
            k.fax_basis,
            k.a_klein / n.f AS a_klein_n,
            k.a_gross / n.f AS a_gross_n
           FROM koeff k
             CROSS JOIN LATERAL ( SELECT GREATEST(COALESCE(k.a_klein, 0::numeric) + COALESCE(k.a_gross, 0::numeric), 1::numeric) AS f) n
        ), weg AS MATERIALIZED (
         SELECT v_charge_weg.charge_nr,
            v_charge_weg.p_hand,
            v_charge_weg.p_wasch,
            v_charge_weg.weg_quelle
           FROM v_charge_weg
        ), erwartung AS MATERIALIZED (
         SELECT v_palox_erwartung.sorte,
            v_palox_erwartung.station,
            v_palox_erwartung.anteil,
            v_palox_erwartung.unten,
            v_palox_erwartung.oben,
            v_palox_erwartung.n_arbeiten,
            v_palox_erwartung.geliehen,
            v_palox_erwartung.quelle
           FROM v_palox_erwartung
        ), eigen AS MATERIALIZED (
         SELECT v_charge_palox.charge_nr,
            v_charge_palox.station,
            v_charge_palox.anteil,
            v_charge_palox.n_arbeiten,
            v_charge_palox.unten,
            v_charge_palox.oben,
            v_charge_palox.quelle
           FROM v_charge_palox
        ), hagel_erw AS MATERIALIZED (
         SELECT v_hagel_erwartung.charge_nr,
            v_hagel_erwartung.station,
            v_hagel_erwartung.anteil,
            v_hagel_erwartung.unten,
            v_hagel_erwartung.oben,
            v_hagel_erwartung.n_arbeiten,
            v_hagel_erwartung.geliehen,
            v_hagel_erwartung.quelle
           FROM v_hagel_erwartung
        ), zuwachs AS MATERIALIZED (
         SELECT v_palox_station.station,
            v_palox_station.zuwachs_je_woche
           FROM v_palox_station
        ), je_station AS MATERIALIZED (
         SELECT k.charge_nr,
            p.portion,
            st.station,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.anteil
                    ELSE er.anteil
                END AS f,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.unten
                    ELSE er.unten
                END AS unten,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.oben
                    ELSE er.oben
                END AS oben,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.n_arbeiten
                    ELSE er.n_arbeiten
                END AS n,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN false
                    ELSE COALESCE(er.geliehen, false)
                END AS geliehen,
                CASE
                    WHEN p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL THEN ei.quelle
                    ELSE er.quelle
                END AS quelle,
            p.portion = 'ausgelagert'::text AND ei.anteil IS NOT NULL AS eigen
           FROM koeff k
             CROSS JOIN ( VALUES ('ausgelagert'::text), ('lager'::text)) p(portion)
             CROSS JOIN ( VALUES ('waschen_sortieren'::text), ('sortieren'::text), ('waschen'::text)) st(station)
             LEFT JOIN LATERAL ( SELECT COALESCE(he.anteil, e0.anteil) AS anteil,
                    COALESCE(he.unten, e0.unten) AS unten,
                    COALESCE(he.oben, e0.oben) AS oben,
                    COALESCE(he.n_arbeiten, e0.n_arbeiten) AS n_arbeiten,
                    COALESCE(he.geliehen, e0.geliehen) AS geliehen,
                    COALESCE(he.quelle, e0.quelle) AS quelle
                   FROM ( SELECT 1 AS eins) x
                     LEFT JOIN erwartung e0 ON e0.sorte = k.sorte AND e0.station = st.station
                     LEFT JOIN hagel_erw he ON he.charge_nr = k.charge_nr AND he.station = st.station) er ON true
             LEFT JOIN eigen ei ON ei.charge_nr = k.charge_nr AND ei.station = st.station
        ), roh AS (
         SELECT k.charge_nr,
            'ausgelagert'::text AS portion,
            l.kohorte,
            l.masse_kg AS geliefert_kg,
            COALESCE(l.alter_tage, 0::numeric) AS alter_tage,
            NULL::numeric AS eingang_kohorte_kg,
            l.n_lieferungen
           FROM koeff_norm k
             JOIN lieferungen l ON l.charge_nr = k.charge_nr
        UNION ALL
         SELECT k.charge_nr,
            'entsorgt'::text AS text,
            e.kohorte,
            e.masse_kg,
            COALESCE(e.alter_tage, 0::numeric) AS "coalesce",
            NULL::numeric AS "numeric",
            e.n_lieferungen
           FROM koeff_norm k
             JOIN entsorgt_lief e ON e.charge_nr = k.charge_nr
        UNION ALL
         SELECT k.charge_nr,
            'lager'::text AS text,
            c.eingangsdatum,
            NULL::numeric AS "numeric",
            GREATEST((k.stichtag - c.eingangsdatum)::numeric, 0::numeric) AS "greatest",
            c.eingang_kg,
            0
           FROM koeff_norm k
             JOIN kohorten c ON c.charge_nr = k.charge_nr
        ), kal AS MATERIALIZED (
         SELECT q.charge_nr,
            q.ebene,
            q.schluessel,
            q.lo,
            q.hi,
            q.n_laeufe,
            q.basis
           FROM mv_kaliber_quelle q
        ), hagel AS MATERIALIZED (
         SELECT c.nr AS charge_nr,
            c.hagel_anteil AS h
           FROM charge c
          WHERE c.hagel_anteil > 0::numeric
        ), teile AS (
         SELECT k.charge_nr,
            k.sorte,
            k.schlag,
            k.eingang_kg,
            k.stichtag,
            k.r,
            k.r_bekannt,
            k.r_n,
            k.r_basis,
            k.a_klein,
            k.a_klein_bekannt OR ka.klein IS NOT NULL AS a_klein_bekannt,
            COALESCE(kq.n_laeufe, k.klein_n) AS klein_n,
            COALESCE(kq.basis, k.klein_basis) AS klein_basis,
            k.a_gross,
            k.a_gross_bekannt OR ka.gross IS NOT NULL AS a_gross_bekannt,
            COALESCE(kq.n_laeufe, k.gross_n) AS gross_n,
            COALESCE(kq.basis, k.gross_basis) AS gross_basis,
            k.a_fax,
            k.a_fax_bekannt,
            k.fax_n,
            k.fax_basis,
            COALESCE(ka.klein, k.a_klein_n) AS a_klein_n,
            COALESCE(ka.gross, k.a_gross_n) AS a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            hh.h AS hagel,
            COALESCE(ws.eigen, false) OR COALESCE(s.eigen, false) OR COALESCE(wa.eigen, false) AS f_eigen,
            w.p_hand,
            w.p_wasch,
            w.weg_quelle,
            nach.f_ws,
            nach.f_s,
            nach.g_w,
            hagel_f(palox_f(w.p_hand, w.p_wasch, nach.f_ws, nach.f_s, nach.g_w), hh.h) AS f_roh,
            hagel_f(palox_f_nach(w.p_hand, w.p_wasch, ws.unten, s.unten, wa.unten, b.b_ws, b.b_s, b.b_w, t.alter_tage), hh.h) AS f_unten_roh,
            hagel_f(palox_f_nach(w.p_hand, w.p_wasch, ws.oben, s.oben, wa.oben, b.b_ws, b.b_s, b.b_w, t.alter_tage), hh.h) AS f_oben_roh,
            LEAST(
                CASE
                    WHEN w.p_hand > 0::numeric THEN ws.n
                    ELSE NULL::integer
                END,
                CASE
                    WHEN w.p_hand < 1::numeric THEN s.n
                    ELSE NULL::integer
                END,
                CASE
                    WHEN w.p_hand < 1::numeric AND w.p_wasch > 0::numeric THEN wa.n
                    ELSE NULL::integer
                END) AS f_n,
            COALESCE(
                CASE
                    WHEN w.p_hand > 0::numeric THEN ws.geliehen
                    ELSE NULL::boolean
                END, false) OR COALESCE(
                CASE
                    WHEN w.p_hand < 1::numeric THEN s.geliehen
                    ELSE NULL::boolean
                END, false) OR COALESCE(
                CASE
                    WHEN w.p_hand < 1::numeric AND w.p_wasch > 0::numeric THEN wa.geliehen
                    ELSE NULL::boolean
                END, false) AS f_geliehen,
            concat_ws('; '::text,
                CASE
                    WHEN w.p_hand > 0::numeric THEN 'Waschen + Sortieren: '::text || COALESCE(ws.quelle, 'kein Wert'::text)
                    ELSE NULL::text
                END,
                CASE
                    WHEN w.p_hand < 1::numeric THEN 'Sortieren: '::text || COALESCE(s.quelle, 'kein Wert'::text)
                    ELSE NULL::text
                END,
                CASE
                    WHEN w.p_hand < 1::numeric AND w.p_wasch > 0::numeric THEN 'Waschen: '::text || COALESCE(wa.quelle, 'kein Wert'::text)
                    ELSE NULL::text
                END,
                CASE
                    WHEN w.weg_quelle IS NOT NULL THEN 'Weg nach '::text || w.weg_quelle
                    ELSE NULL::text
                END,
                CASE
                    WHEN hh.h > 0::numeric THEN format('Hagel %s %% eingetragen: Ünique-Topf'::text, round(hh.h * 100::numeric))
                    ELSE NULL::text
                END) AS f_quelle,
            b.b_ws,
            b.b_s,
            b.b_w,
            (w.p_hand = 0::numeric OR b.b_ws IS NOT NULL) AND (w.p_hand = 1::numeric OR b.b_s IS NOT NULL) AND (w.p_hand = 1::numeric OR COALESCE(w.p_wasch, 0::numeric) = 0::numeric OR b.b_w IS NOT NULL) AS zuwachs_roh
           FROM koeff_norm k
             JOIN roh t ON t.charge_nr = k.charge_nr
             LEFT JOIN weg w ON w.charge_nr = k.charge_nr
             LEFT JOIN je_station ws ON ws.charge_nr = k.charge_nr AND ws.station = 'waschen_sortieren'::text AND ws.portion =
                CASE
                    WHEN t.portion = 'lager'::text THEN 'lager'::text
                    ELSE 'ausgelagert'::text
                END
             LEFT JOIN je_station s ON s.charge_nr = k.charge_nr AND s.station = 'sortieren'::text AND s.portion =
                CASE
                    WHEN t.portion = 'lager'::text THEN 'lager'::text
                    ELSE 'ausgelagert'::text
                END
             LEFT JOIN je_station wa ON wa.charge_nr = k.charge_nr AND wa.station = 'waschen'::text AND wa.portion =
                CASE
                    WHEN t.portion = 'lager'::text THEN 'lager'::text
                    ELSE 'ausgelagert'::text
                END
             LEFT JOIN zuwachs zws ON zws.station = 'waschen_sortieren'::text
             LEFT JOIN zuwachs zs ON zs.station = 'sortieren'::text
             LEFT JOIN zuwachs zw ON zw.station = 'waschen'::text
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN ws.eigen THEN 0::numeric
                            ELSE zws.zuwachs_je_woche
                        END AS b_ws,
                        CASE
                            WHEN s.eigen THEN 0::numeric
                            ELSE zs.zuwachs_je_woche
                        END AS b_s,
                        CASE
                            WHEN wa.eigen THEN 0::numeric
                            ELSE zw.zuwachs_je_woche
                        END AS b_w) b
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN ws.f IS NULL THEN NULL::numeric
                            ELSE LEAST(GREATEST(ws.f + COALESCE(b.b_ws, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric)
                        END AS f_ws,
                        CASE
                            WHEN s.f IS NULL THEN NULL::numeric
                            ELSE LEAST(GREATEST(s.f + COALESCE(b.b_s, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric)
                        END AS f_s,
                        CASE
                            WHEN wa.f IS NULL THEN NULL::numeric
                            ELSE LEAST(GREATEST(wa.f + COALESCE(b.b_w, 0::numeric) * t.alter_tage / 7.0, 0::numeric), 1::numeric)
                        END AS g_w) nach
             LEFT JOIN kal kq ON kq.charge_nr = k.charge_nr AND NOT (k.charge_nr IN ( SELECT hc.nr
                   FROM charge hc
                  WHERE hc.hagel_anteil > 0::numeric))
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - k.r, t.alter_tage)) ka(klein, gross) ON true
             LEFT JOIN hagel hg ON hg.charge_nr = k.charge_nr
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN hg.h IS NULL OR t.portion = 'entsorgt'::text THEN 0::numeric
                            ELSE hg.h
                        END AS h) hh
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
            t.hagel,
            t.f_eigen,
            t.p_hand,
            t.p_wasch,
            t.weg_quelle,
            t.f_ws,
            t.f_s,
            t.g_w,
            t.f_roh,
            t.f_unten_roh,
            t.f_oben_roh,
            t.f_n,
            t.f_geliehen,
            t.f_quelle,
            t.b_ws,
            t.b_s,
            t.b_w,
            t.zuwachs_roh,
            t.f_roh IS NOT NULL AS f_bekannt,
            COALESCE(t.f_roh, 0::numeric) AS f,
            COALESCE(t.f_unten_roh, t.f_roh, 0::numeric) AS f_unten,
            COALESCE(t.f_oben_roh, t.f_roh, 0::numeric) AS f_oben,
                CASE
                    WHEN t.f_roh IS NULL OR t.f_n IS NULL OR t.f_n < 2 THEN 0::numeric
                    ELSE (COALESCE(t.f_oben_roh, t.f_roh) - COALESCE(t.f_unten_roh, t.f_roh)) / (2::numeric * t_quantil_95(t.f_n - 1))
                END AS f_se,
            t.f_roh IS NOT NULL AND COALESCE(t.zuwachs_roh, false) AS zuwachs_bekannt
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
            x.hagel,
            x.f_eigen,
            x.p_hand,
            x.p_wasch,
            x.weg_quelle,
            x.f_ws,
            x.f_s,
            x.g_w,
            x.f_roh,
            x.f_unten_roh,
            x.f_oben_roh,
            x.f_n,
            x.f_geliehen,
            x.f_quelle,
            x.b_ws,
            x.b_s,
            x.b_w,
            x.zuwachs_roh,
            x.f_bekannt,
            x.f,
            x.f_unten,
            x.f_oben,
            x.f_se,
            x.zuwachs_bekannt,
            GREATEST(power(1::numeric - x.r, x.alter_tage) * (1::numeric - x.f) * (1::numeric - x.a_klein_n - x.a_gross_n) * (1::numeric - x.a_fax), 0.25) AS verkaufsfaehig_anteil,
            GREATEST(power(1::numeric - x.r, x.alter_tage), 0.25) AS verdunstungs_anteil
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
            a.hagel,
            a.f_eigen,
            a.p_hand,
            a.p_wasch,
            a.weg_quelle,
            a.f_ws,
            a.f_s,
            a.g_w,
            a.f_roh,
            a.f_unten_roh,
            a.f_oben_roh,
            a.f_n,
            a.f_geliehen,
            a.f_quelle,
            a.b_ws,
            a.b_s,
            a.b_w,
            a.zuwachs_roh,
            a.f_bekannt,
            a.f,
            a.f_unten,
            a.f_oben,
            a.f_se,
            a.zuwachs_bekannt,
            a.verkaufsfaehig_anteil,
            a.verdunstungs_anteil,
                CASE
                    WHEN a.portion = 'entsorgt'::text THEN a.geliefert_kg / a.verdunstungs_anteil
                    ELSE a.geliefert_kg / a.verkaufsfaehig_anteil
                END AS m0,
            0::numeric AS ueberzaehlung_kg
           FROM anteil a
          WHERE a.portion = ANY (ARRAY['ausgelagert'::text, 'entsorgt'::text])
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
            a.hagel,
            a.f_eigen,
            a.p_hand,
            a.p_wasch,
            a.weg_quelle,
            a.f_ws,
            a.f_s,
            a.g_w,
            a.f_roh,
            a.f_unten_roh,
            a.f_oben_roh,
            a.f_n,
            a.f_geliehen,
            a.f_quelle,
            a.b_ws,
            a.b_s,
            a.b_w,
            a.zuwachs_roh,
            a.f_bekannt,
            a.f,
            a.f_unten,
            a.f_oben,
            a.f_se,
            a.zuwachs_bekannt,
            a.verkaufsfaehig_anteil,
            a.verdunstungs_anteil,
                CASE
                    WHEN a.charge_nr IN (SELECT cl.nr FROM charge cl WHERE cl.leer_am IS NOT NULL AND cl.leer_am <= heute()) THEN 0::numeric
                    ELSE GREATEST(a.eingang_kohorte_kg - COALESCE(x.m0, 0::numeric), 0::numeric)
                END AS m0,
            GREATEST(COALESCE(x.m0, 0::numeric) - a.eingang_kohorte_kg, 0::numeric) AS ueberzaehlung_kg
           FROM anteil a
             LEFT JOIN ( SELECT ausgelagert.charge_nr,
                    ausgelagert.kohorte,
                    sum(ausgelagert.m0) AS m0
                   FROM ausgelagert
                  GROUP BY ausgelagert.charge_nr, ausgelagert.kohorte) x ON x.charge_nr = a.charge_nr AND x.kohorte = a.kohorte
          WHERE a.portion = 'lager'::text
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
            ausgelagert.hagel,
            ausgelagert.f_eigen,
            ausgelagert.p_hand,
            ausgelagert.p_wasch,
            ausgelagert.weg_quelle,
            ausgelagert.f_ws,
            ausgelagert.f_s,
            ausgelagert.g_w,
            ausgelagert.f_roh,
            ausgelagert.f_unten_roh,
            ausgelagert.f_oben_roh,
            ausgelagert.f_n,
            ausgelagert.f_geliehen,
            ausgelagert.f_quelle,
            ausgelagert.b_ws,
            ausgelagert.b_s,
            ausgelagert.b_w,
            ausgelagert.zuwachs_roh,
            ausgelagert.f_bekannt,
            ausgelagert.f,
            ausgelagert.f_unten,
            ausgelagert.f_oben,
            ausgelagert.f_se,
            ausgelagert.zuwachs_bekannt,
            ausgelagert.verkaufsfaehig_anteil,
            ausgelagert.verdunstungs_anteil,
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
            lager.hagel,
            lager.f_eigen,
            lager.p_hand,
            lager.p_wasch,
            lager.weg_quelle,
            lager.f_ws,
            lager.f_s,
            lager.g_w,
            lager.f_roh,
            lager.f_unten_roh,
            lager.f_oben_roh,
            lager.f_n,
            lager.f_geliehen,
            lager.f_quelle,
            lager.b_ws,
            lager.b_s,
            lager.b_w,
            lager.zuwachs_roh,
            lager.f_bekannt,
            lager.f,
            lager.f_unten,
            lager.f_oben,
            lager.f_se,
            lager.zuwachs_bekannt,
            lager.verkaufsfaehig_anteil,
            lager.verdunstungs_anteil,
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
            t.hagel,
            t.f_eigen,
            t.p_hand,
            t.p_wasch,
            t.weg_quelle,
            t.f_ws,
            t.f_s,
            t.g_w,
            t.f_roh,
            t.f_unten_roh,
            t.f_oben_roh,
            t.f_n,
            t.f_geliehen,
            t.f_quelle,
            t.b_ws,
            t.b_s,
            t.b_w,
            t.zuwachs_roh,
            t.f_bekannt,
            t.f,
            t.f_unten,
            t.f_oben,
            t.f_se,
            t.zuwachs_bekannt,
            t.verkaufsfaehig_anteil,
            t.verdunstungs_anteil,
            t.m0,
            t.ueberzaehlung_kg,
            t.m0 * power(1::numeric - t.r, t.alter_tage) AS m1,
            (- t.m0) * t.alter_tage * power(1::numeric - t.r, GREATEST(t.alter_tage - 1::numeric, 0::numeric)) AS d_m1_r
           FROM alle t
          WHERE t.m0 > 0::numeric OR t.ueberzaehlung_kg > 0::numeric OR t.portion = 'lager'::text AND (t.charge_nr IN (SELECT cl.nr FROM charge cl WHERE cl.leer_am IS NOT NULL AND cl.leer_am <= heute()))
        )
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    m0,
    m1,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f)
        END AS m2,
    r,
    f,
    f_unten,
    f_oben,
    f_se,
    f_ws,
    f_s,
    g_w,
    p_hand,
    p_wasch,
    f_quelle,
    f_geliehen,
    b_ws,
    b_s,
    b_w,
    zuwachs_bekannt,
    a_klein_n,
    a_gross_n,
    a_fax,
    d_m1_r,
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
    a_fax_bekannt,
    m0 - m1 AS verdunstung_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN m1
            ELSE m1 * f
        END AS schimmel_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * a_klein_n
        END AS klein_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * a_gross_n
        END AS nebenkanal_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * (1::numeric - a_klein_n - a_gross_n) * a_fax
        END AS fax_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - f) * (1::numeric - a_klein_n - a_gross_n) * (1::numeric - a_fax)
        END AS verkaufsfaehig_kg,
    kohorte,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE geliefert_kg
        END AS geliefert_kg,
    ueberzaehlung_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0
            ELSE n_lieferungen
        END AS n_lieferungen,
    verkaufsfaehig_anteil,
    hagel,
    f_eigen
   FROM kaskade
with no data;
create index if not exists mv_kaskade_charge on public.mv_kaskade USING btree (charge_nr);
create unique index if not exists mv_kaskade_pk on public.mv_kaskade USING btree (charge_nr, portion, COALESCE(kohorte, '1900-01-01'::date));
comment on materialized view mv_kaskade is 'Die Massenkaskade je Charge, Eingangstag und Portion. Drei Portionen: „ausgelagert" ist die Eingangsmasse hinter den verkauften und in den Nebenkanal gegangenen Lieferungen, „entsorgt" die hinter dem Kompost (0065 — nur um die Verdunstung zurückgerechnet, weil entsorgte Ware selbst das Faule ist), „lager" der Rest, der noch liegt. Je Portion die Ströme Verdunstung, Palox-Ausschuss, zu klein, zu gross, Fax und verkaufsfähig. f ist der Palox-Anteil über den Weg der Charge (palox_f: p_hand, p_wasch, f_ws, f_s, g_w). Seit 0111 gilt jeder Stationswert für das Alter der Portion: Grundausschuss der Sorte (v_palox_erwartung) + Anstieg der Station je Woche Lagerdauer (v_palox_station) × alter_tage / 7; für Ausgelagertes mit eigener Messung gilt diese, ohne Anstieg. f_quelle sagt, woher; f_geliehen: aus allen Sorten. b_ws/b_s/b_w ist der Anstieg, mit dem Prognose und Verlauf fortschreiben (0 bei eigener Messung), zuwachs_bekannt sagt, ob sie es dürfen.';
grant select on mv_kaskade to authenticated;

-- ---------- erg_verlauf ----------
create materialized view erg_verlauf as
 WITH tag AS MATERIALIZED (
         SELECT heute() AS heute,
            stichtag() AS stichtag
        ), wochen AS MATERIALIZED (
         SELECT w_1.w::date AS woche,
            (w_1.w + '6 days'::interval)::date AS bis
           FROM tag t,
            LATERAL generate_series(date_trunc('week'::text, COALESCE(( SELECT min(palette.eingangsdatum) AS min
                   FROM palette), t.heute)::timestamp with time zone)::date::timestamp with time zone, date_trunc('week'::text, GREATEST(t.stichtag, t.heute + 84)::timestamp with time zone)::date::timestamp with time zone, '7 days'::interval) w_1(w)
        UNION
         SELECT date_trunc('week'::text, t.heute::timestamp with time zone)::date AS date_trunc,
            t.heute
           FROM tag t
        ), gruppen AS (
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
        ), portionen AS MATERIALIZED (
         SELECT k.charge_nr,
            k.portion,
            k.kohorte,
            k.m0,
            k.r,
            k.f,
            k.f_ws,
            k.f_s,
            k.g_w,
            k.p_hand,
            k.p_wasch,
            k.b_ws,
            k.b_s,
            k.b_w,
            k.zuwachs_bekannt,
            k.a_klein_n,
            k.a_gross_n,
            k.a_fax,
            k.hagel,
            k.alter_tage,
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
        ), lieferanteil AS MATERIALIZED (
         SELECT w_1.bis,
            l.charge_nr,
            sum(l.masse_kg) FILTER (WHERE l.datum <= w_1.bis) / NULLIF(sum(l.masse_kg), 0::numeric) AS q
           FROM wochen w_1
             CROSS JOIN v_lieferung_charge_tag l
          WHERE l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])
          GROUP BY w_1.bis, l.charge_nr
        ), je_woche AS (
         SELECT w_1.woche,
            w_1.bis,
            p.charge_nr,
            q.q * (p.m0 - n.d) + (1::numeric - q.q) * (p.m0 - n.u) AS verdunstung_kg,
            q.q * n.d * f.d + (1::numeric - q.q) * n.u * f.u AS schimmel_kg,
            q.q * p.fax_kg AS fax_kg,
            (1::numeric - q.q) * p.m0 AS lager_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) AS gute_ware_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * ku.kn AS kanal_lager_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * (1::numeric - ku.kn) * p.a_fax AS fax_lager_kg,
            q.q * n.d * (1::numeric - f.d) * (p.a_klein_n + p.a_gross_n) AS aussortiert_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * (1::numeric - ku.kn) * (1::numeric - p.a_fax) AS verkaufsfaehig_kg
           FROM wochen w_1
             JOIN portionen p ON p.kohorte <= w_1.bis
             CROSS JOIN tag d_1
             LEFT JOIN lieferanteil la ON la.bis = w_1.bis AND la.charge_nr = p.charge_nr
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.liefertag IS NULL THEN 0::numeric
                            ELSE LEAST(GREATEST(COALESCE(la.q,
                            CASE
                                WHEN p.liefertag <= w_1.bis THEN 1::numeric
                                ELSE 0::numeric
                            END), 0::numeric), 1::numeric)
                        END AS q) q
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.liefertag IS NULL THEN GREATEST(w_1.bis - p.kohorte, 0)::numeric
                            ELSE LEAST(GREATEST(w_1.bis - p.kohorte, 0)::numeric, p.alter_tage)
                        END AS u) t
             CROSS JOIN LATERAL ( SELECT p.m0 * power(1::numeric - p.r, COALESCE(p.alter_tage, 0::numeric)) AS d,
                    p.m0 * power(1::numeric - p.r, t.u) AS u) n
             LEFT JOIN mv_kaliber_quelle kq ON kq.charge_nr = p.charge_nr AND NOT (p.charge_nr IN ( SELECT hc.nr
                   FROM charge hc
                  WHERE hc.hagel_anteil > 0::numeric))
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - p.r, t.u)) kl(klein, gross) ON true
             CROSS JOIN LATERAL ( SELECT COALESCE(kl.klein + kl.gross, p.a_klein_n + p.a_gross_n) AS kn) ku
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(p.p_hand, p.p_wasch, p.f_ws, p.f_s, p.g_w, p.b_ws, p.b_s, p.b_w, 0::numeric), p.hagel), p.f)
                            ELSE p.f
                        END AS d,
                        CASE
                            WHEN p.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(p.p_hand, p.p_wasch, p.f_ws, p.f_s, p.g_w, p.b_ws, p.b_s, p.b_w, (LEAST(w_1.bis, COALESCE(p.liefertag, w_1.bis)) - COALESCE(p.liefertag, d_1.heute))::numeric), p.hagel), p.f)
                            ELSE p.f
                        END AS u) f
        ), je_charge AS MATERIALIZED (
         SELECT je_woche.woche,
            je_woche.bis,
            je_woche.charge_nr,
            sum(je_woche.verdunstung_kg) AS verdunstung_kg,
            sum(je_woche.schimmel_kg) AS schimmel_kg,
            sum(je_woche.fax_kg) AS fax_kg,
            sum(je_woche.gute_ware_kg) AS im_haus_kg,
            sum(je_woche.lager_kg) AS lager_kg,
            sum(je_woche.kanal_lager_kg) AS kanal_kg,
            sum(je_woche.fax_lager_kg) AS fax_lager_kg,
            sum(je_woche.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(je_woche.aussortiert_kg) AS aussortiert_kg
           FROM je_woche
          GROUP BY je_woche.woche, je_woche.bis, je_woche.charge_nr
        ), verlust AS (
         SELECT j.woche,
            j.bis,
            g.gruppe,
            g.schluessel,
            sum(j.verdunstung_kg) AS verdunstung_kg,
            sum(j.schimmel_kg) AS schimmel_kg,
            sum(j.fax_kg) AS fax_kg,
            sum(j.im_haus_kg) AS im_haus_kg,
            sum(j.lager_kg) AS lager_kg,
            sum(j.kanal_kg) AS kanal_kg,
            sum(j.fax_lager_kg) AS fax_lager_kg,
            sum(j.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(j.aussortiert_kg) AS aussortiert_kg
           FROM je_charge j
             JOIN gruppen g ON g.charge_nr = j.charge_nr
          GROUP BY j.woche, j.bis, g.gruppe, g.schluessel
        ), eingang_charge AS MATERIALIZED (
         SELECT w_1.woche,
            w_1.bis,
            k.charge_nr,
            sum(k.eingang_kg) AS kg
           FROM wochen w_1
             JOIN v_charge_kohorte k ON k.eingangsdatum <= w_1.bis
          GROUP BY w_1.woche, w_1.bis, k.charge_nr
        ), eingang AS (
         SELECT e_1.woche,
            e_1.bis,
            g.gruppe,
            g.schluessel,
            sum(e_1.kg) AS kg
           FROM eingang_charge e_1
             JOIN gruppen g ON g.charge_nr = e_1.charge_nr
          GROUP BY e_1.woche, e_1.bis, g.gruppe, g.schluessel
        ), ausgang_charge AS MATERIALIZED (
         SELECT w_1.woche,
            w_1.bis,
            l.charge_nr,
            sum(l.masse_kg) AS kg
           FROM wochen w_1
             JOIN v_lieferung_charge_tag l ON l.datum <= w_1.bis
          GROUP BY w_1.woche, w_1.bis, l.charge_nr
        ), ausgang AS (
         SELECT a_1.woche,
            a_1.bis,
            g.gruppe,
            g.schluessel,
            sum(a_1.kg) AS kg
           FROM ausgang_charge a_1
             JOIN gruppen g ON g.charge_nr = a_1.charge_nr
          GROUP BY a_1.woche, a_1.bis, g.gruppe, g.schluessel
        ), liste AS (
         SELECT DISTINCT gruppen.gruppe,
            gruppen.schluessel
           FROM gruppen
        )
 SELECT w.woche,
    w.bis,
    w.bis > d.heute AS prognose,
    s.gruppe,
    s.schluessel,
    zahl(COALESCE(e.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS eingang_kum_kg,
    zahl(COALESCE(a.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgang_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_kum_kg,
    zahl(COALESCE(v.schimmel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_kum_kg,
    zahl(COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric) + COALESCE(v.schimmel_kg, 0::numeric) + COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_kum_kg,
    zahl(COALESCE(v.im_haus_kg, 0::numeric) + COALESCE(v.aussortiert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_kg,
    zahl(COALESCE(v.lager_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(COALESCE(v.verkaufsfaehig_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(COALESCE(v.kanal_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_kg,
    zahl(COALESCE(v.fax_lager_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_lager_kg,
    zahl(COALESCE(v.aussortiert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS aussortiert_kg
   FROM wochen w
     CROSS JOIN liste s
     CROSS JOIN tag d
     LEFT JOIN verlust v ON v.bis = w.bis AND v.gruppe = s.gruppe AND v.schluessel = s.schluessel
     LEFT JOIN eingang e ON e.bis = w.bis AND e.gruppe = s.gruppe AND e.schluessel = s.schluessel
     LEFT JOIN ausgang a ON a.bis = w.bis AND a.gruppe = s.gruppe AND a.schluessel = s.schluessel
with no data;
create index if not exists erg_verlauf_gruppe on public.erg_verlauf USING btree (gruppe, schluessel, bis);
create unique index if not exists erg_verlauf_pk on public.erg_verlauf USING btree (woche, bis, gruppe, schluessel);
create index if not exists erg_verlauf_woche on public.erg_verlauf USING btree (woche);
comment on materialized view erg_verlauf is 'Je Woche und Gruppe (gesamt, Sorte, Schlag, Charge): Eingang und Ausgang kumuliert (gemessen), im Lager (Eingangsware, die noch nicht hinter einer Lieferung steckt) und davon verkaufsfähig (gerechnet) — ab heute als Prognose bis zum Saisonende (prognose = true). Der Verlust ist der Abstand zwischen im Lager und verkaufsfähig; seine Teile stehen weiter als eigene Spalten (0071). Seit 0106 ohne Sockel: das Faule ist der Palox-Anteil der Stationen, mit dem Zuwachs je Woche zurück und voraus verschoben, wo die Kennzahl ihn ausweist. Seit 0114 fällt „im Lager" mit den Lieferungen: je Woche der Teil, den die Lieferungen der Charge bis dahin ausmachen, nicht alles am mittleren Liefertag.';
grant select on erg_verlauf to authenticated;

-- ---------- v_hochrechnung_basis ----------
create or replace view v_hochrechnung_basis with (security_invoker=true) as
 WITH je_charge AS (
         SELECT mv_kaskade.charge_nr,
            sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text) AS ausgelagert_kg,
            sum(mv_kaskade.m0 * mv_kaskade.alter_tage) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric) AS alter_ausgelagert,
            sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS lager_kg,
            sum(mv_kaskade.m0 * mv_kaskade.alter_tage) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS alter_lager,
            sum(mv_kaskade.verkaufsfaehig_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS verkaufsfaehig_lager_kg,
            sum(mv_kaskade.geliefert_kg) AS geliefert_kg,
            sum(mv_kaskade.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(mv_kaskade.n_lieferungen)::integer AS n_lieferung_kohorten,
            min(mv_kaskade.kohorte) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric) AS rest_von,
            max(mv_kaskade.kohorte) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric) AS rest_bis,
            count(*) FILTER (WHERE mv_kaskade.portion = 'lager'::text AND mv_kaskade.m0 > 0::numeric)::integer AS n_rest_kohorten,
            sum(mv_kaskade.m0 * (mv_kaskade.kohorte - '2000-01-01'::date)::numeric) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m0) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS rest_tage_seit_epoche,
                CASE
                    WHEN bool_and(mv_kaskade.r_bekannt) THEN COALESCE(sum(mv_kaskade.verdunstung_kg), 0::numeric)
                    ELSE NULL::numeric
                END AS verdunstung_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.f_bekannt) THEN COALESCE(sum(mv_kaskade.schimmel_kg), 0::numeric)
                    ELSE NULL::numeric
                END AS schimmel_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) THEN COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS kanal_ausgelagert_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_fax_bekannt) THEN COALESCE(sum(mv_kaskade.fax_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS fax_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_fax_bekannt) THEN COALESCE(sum(mv_kaskade.fax_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS fax_erwartet_kg,
            COALESCE(sum(mv_kaskade.m2) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) + COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'ausgelagert'::text), 0::numeric) AS im_haus_heute_kg,
                CASE
                    WHEN bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) THEN COALESCE(sum(mv_kaskade.klein_kg + mv_kaskade.nebenkanal_kg) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric)
                    ELSE NULL::numeric
                END AS kanal_im_haus_kg,
            bool_and(mv_kaskade.r_bekannt AND mv_kaskade.f_bekannt AND mv_kaskade.a_fax_bekannt AND mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) AS verlust_bekannt,
            bool_and(mv_kaskade.r_bekannt) AS verdunstung_bekannt,
            bool_and(mv_kaskade.f_bekannt) AS schimmel_bekannt,
            bool_and(mv_kaskade.a_fax_bekannt) AS fax_bekannt,
            bool_and(mv_kaskade.a_klein_bekannt AND mv_kaskade.a_gross_bekannt) AS kanal_bekannt,
            sum(mv_kaskade.m1 * mv_kaskade.f) FILTER (WHERE mv_kaskade.portion = 'lager'::text) / NULLIF(sum(mv_kaskade.m1) FILTER (WHERE mv_kaskade.portion = 'lager'::text), 0::numeric) AS faul_anteil_lager,
            max(mv_kaskade.f_quelle) FILTER (WHERE mv_kaskade.portion = 'lager'::text) AS faul_quelle,
            count(*) > 0 AS gerechnet,
            count(*) FILTER (WHERE mv_kaskade.portion = 'lager'::text) > 0 AS hat_lager
           FROM mv_kaskade
          GROUP BY mv_kaskade.charge_nr
        )
 SELECT b.charge_nr,
    b.schlag,
    b.sorte,
    b.eingang_kg,
    b.n_paletten,
    b.eingangsdatum_mittel,
    zahl(COALESCE(k.ausgelagert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgelagert_kg,
    zahl(k.alter_ausgelagert, 1, '100000'::numeric)::numeric(8,1) AS alter_ausgelagert,
    zahl(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.lager_kg, 0::numeric)
        END, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(COALESCE(k.alter_lager, (b.stichtag - b.eingangsdatum_mittel)::numeric), 1, '100000'::numeric)::numeric(8,1) AS alter_lager,
    zahl((heute() - x.rest_datum)::double precision, 1, '100000'::numeric)::numeric(8,1) AS alter_lager_heute,
    b.weg2_anteil,
    b.stichtag,
    b.n_paletten_mit_netto,
    zahl(COALESCE(k.ueberzaehlung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ueberzaehlung_kg,
    b.sortiert_kg,
    b.gewaschen_kg,
    b.wartet_kg,
    b.anteil_gewaschen,
    b.alter_band,
    b.am_band_kg,
    x.rest_datum AS eingangsdatum_rest,
    COALESCE(k.n_lieferung_kohorten, 0) > 0 AS rest_alter_aus_zaehlung,
    b.eingang_von,
    b.eingang_bis,
    b.n_eingangstage,
    COALESCE(k.rest_von, b.eingang_von) AS rest_von,
    COALESCE(k.rest_bis, b.eingang_bis) AS rest_bis,
    round(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.lager_kg, 0::numeric)
        END / NULLIF(b.eingang_kg / NULLIF(b.n_paletten, 0)::numeric, 0::numeric))::integer AS n_rest_paletten,
    COALESCE(k.n_rest_kohorten, b.n_eingangstage) AS n_rest_kohorten,
    heute() - COALESCE(k.rest_bis, b.eingang_bis) AS alter_lager_von,
    heute() - COALESCE(k.rest_von, b.eingang_von) AS alter_lager_bis,
    zahl(COALESCE(k.geliefert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS geliefert_kg,
    zahl(k.verkaufsfaehig_lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_lager_kg,
    COALESCE(n.n_lieferungen, 0) AS n_lieferungen,
    zahl(k.verdunstung_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_heute_kg,
    zahl(k.schimmel_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_heute_kg,
    zahl(k.fax_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_heute_kg,
    zahl(k.verdunstung_heute_kg + k.schimmel_heute_kg + k.fax_heute_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_heute_kg,
    zahl(k.kanal_ausgelagert_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(k.fax_erwartet_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_erwartet_kg,
    zahl(
        CASE
            WHEN k.gerechnet IS NOT TRUE THEN b.eingang_kg
            ELSE COALESCE(k.im_haus_heute_kg, 0::numeric)
        END, 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_heute_kg,
    zahl(k.kanal_im_haus_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_im_haus_kg,
    COALESCE(k.verlust_bekannt, false) AS verlust_bekannt,
    COALESCE(k.verdunstung_bekannt, false) AS verdunstung_bekannt,
    COALESCE(k.schimmel_bekannt, false) AS schimmel_bekannt,
    COALESCE(k.fax_bekannt, false) AS fax_bekannt,
    COALESCE(k.kanal_bekannt, false) AS kanal_bekannt,
    zahl(k.faul_anteil_lager, 4, 1::numeric)::numeric(6,4) AS faul_anteil,
    k.faul_quelle,
    heute() AS heute
   FROM v_kaskade_basis b
     LEFT JOIN je_charge k ON k.charge_nr = b.charge_nr
     LEFT JOIN ( SELECT v_lieferung_charge.charge_nr,
            count(DISTINCT v_lieferung_charge.id)::integer AS n_lieferungen
           FROM v_lieferung_charge
          WHERE (v_lieferung_charge.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])) AND v_lieferung_charge.id > 0
          GROUP BY v_lieferung_charge.charge_nr) n ON n.charge_nr = b.charge_nr
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN k.rest_tage_seit_epoche IS NOT NULL THEN '2000-01-01'::date + round(k.rest_tage_seit_epoche)::integer
                    ELSE b.eingangsdatum_mittel
                END AS rest_datum) x
  WHERE b.eingang_kg IS NOT NULL;
comment on view v_hochrechnung_basis is 'Je Charge, alles bis heute: Eingang und geliefert (gemessen), ausgelagert (Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus ausgelagert, in Eingangskilo), verlust_heute_kg (Verdunstung + Faules + Fax am Abgepackten), im_haus_heute_kg (Eingangsmasse, die noch liegt, nach Verdunstung und Verderb, plus hinter den Lieferungen Aussortiertes, 0101). Keine Prognose. 0064: Jede Stromsumme ist NULL, solange ihr Koeffizient keine Messung hat. Seit 0106 ohne Sockel; faul_anteil und faul_quelle sagen, womit das Liegende rechnet und woher es kommt. Seit 0114 zählt n_lieferungen jeden Lieferschein, der von der Charge genommen hat, einmal (bis dahin einmal je Eingangstag; der Ausgang vor der App zählt in der Masse, nicht als Lieferschein).';
grant select on v_hochrechnung_basis to authenticated;

-- ---------- v_kaskade ----------
create or replace view v_kaskade with (security_invoker=true) as
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
    f_unten,
    f_oben,
    f_se,
    f_ws,
    f_s,
    g_w,
    p_hand,
    p_wasch,
    f_quelle,
    f_geliehen,
    b_ws,
    b_s,
    b_w,
    zuwachs_bekannt,
    a_klein_n,
    a_gross_n,
    a_fax,
    d_m1_r,
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
    a_fax_bekannt,
    verdunstung_kg,
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
comment on view v_kaskade is 'Der Massenfluss je Charge, Eingangstag und Portion: Was eingelagert wurde (eingang_kg) verteilt sich auf Verdunstung, Faules, zu klein, Nebenkanal, Fax und verkaufsfähige Ware. Die Ströme addieren sich zum Eingang. "Verlust" ist hier nur, was wirklich verloren ist: verdunstung_kg, schimmel_kg. klein_kg und nebenkanal_kg sind kein Verlust, sondern ein anderer Kanal. Seit 0106 ohne Sockel; f kommt aus den Stationswerten (f_quelle).';
grant select on v_kaskade to authenticated;

-- ---------- v_prognose ----------
create or replace view v_prognose with (security_invoker=true) as
 WITH tag AS MATERIALIZED (
         SELECT heute() AS heute,
            stichtag() AS stichtag
        ), ende AS (
         SELECT GREATEST(LEAST(t.stichtag - t.heute, 400), 28) AS tage
           FROM tag t
        ), horizonte AS (
         SELECT g.h
           FROM ende e,
            LATERAL generate_series(0, e.tage, 7) g(h)
        UNION
         SELECT 7
        UNION
         SELECT 14
        UNION
         SELECT 28
        UNION
         SELECT ende.tage
           FROM ende
        ), grenzen AS (
         SELECT mv_koeff_rand.sorte,
            mv_koeff_rand.r_unten,
            mv_koeff_rand.r_oben,
            mv_koeff_rand.klein_unten,
            mv_koeff_rand.klein_oben,
            mv_koeff_rand.gross_unten,
            mv_koeff_rand.gross_oben,
            mv_koeff_rand.fax_unten,
            mv_koeff_rand.fax_oben
           FROM mv_koeff_rand
        ), lager AS MATERIALIZED (
         SELECT k.charge_nr,
            k.sorte,
            k.schlag,
            k.kohorte,
            k.alter_tage,
            k.m0,
            k.r,
            k.f,
            k.f_unten,
            k.f_oben,
            k.f_ws,
            k.f_s,
            k.g_w,
            k.p_hand,
            k.p_wasch,
            k.b_ws,
            k.b_s,
            k.b_w,
            k.zuwachs_bekannt,
            k.a_klein_n,
            k.a_gross_n,
            k.a_fax,
            k.hagel,
            k.r_bekannt,
            k.f_bekannt,
            k.a_klein_bekannt,
            k.a_gross_bekannt,
            k.a_fax_bekannt,
            k.f_geliehen,
            COALESCE(g.r_unten, 0::numeric) AS r_unten,
            COALESCE(g.r_oben, 0::numeric) AS r_oben,
            COALESCE(g.klein_unten, 0::numeric) AS klein_unten,
            COALESCE(g.klein_oben, 0::numeric) AS klein_oben,
            COALESCE(g.gross_unten, 0::numeric) AS gross_unten,
            COALESCE(g.gross_oben, 0::numeric) AS gross_oben,
            COALESCE(g.fax_unten, 0::numeric) AS fax_unten,
            COALESCE(g.fax_oben, 0::numeric) AS fax_oben,
            power(1::numeric - k.r, k.alter_tage) AS wa,
            power(1::numeric - GREATEST(COALESCE(g.r_unten, 0::numeric), 0::numeric), k.alter_tage) AS wa_unten,
            power(1::numeric - GREATEST(COALESCE(g.r_oben, 0::numeric), 0::numeric), k.alter_tage) AS wa_oben
           FROM mv_kaskade k
             LEFT JOIN grenzen g ON g.sorte = k.sorte
          WHERE k.portion = 'lager'::text AND k.m0 > 0::numeric AND k.alter_tage >= 0::numeric
        ), faktor_h AS MATERIALIZED (
         SELECT c.charge_nr,
            h.h,
            power(1::numeric - c.r, h.h::numeric) AS wh,
            power(1::numeric - GREATEST(c.r_unten, 0::numeric), h.h::numeric) AS wh_unten,
            power(1::numeric - GREATEST(c.r_oben, 0::numeric), h.h::numeric) AS wh_oben
           FROM ( SELECT DISTINCT lager.charge_nr,
                    lager.r,
                    lager.r_unten,
                    lager.r_oben
                   FROM lager) c
             CROSS JOIN horizonte h
        ), je_portion AS (
         SELECT l.charge_nr,
            l.sorte,
            l.schlag,
            l.kohorte,
            l.alter_tage,
            l.m0,
            l.r,
            l.f,
            l.f_unten,
            l.f_oben,
            l.f_ws,
            l.f_s,
            l.g_w,
            l.p_hand,
            l.p_wasch,
            l.b_ws,
            l.b_s,
            l.b_w,
            l.zuwachs_bekannt,
            COALESCE(kh.klein, l.a_klein_n) AS a_klein_n,
            COALESCE(kh.gross, l.a_gross_n) AS a_gross_n,
            l.a_klein_n AS a_klein_0,
            l.a_gross_n AS a_gross_0,
            l.a_fax,
            l.r_bekannt,
            l.f_bekannt,
            l.a_klein_bekannt,
            l.a_gross_bekannt,
            l.a_fax_bekannt,
            l.f_geliehen,
            l.r_unten,
            l.r_oben,
            COALESCE(kh.klein, l.klein_unten) AS klein_unten,
            COALESCE(kh.klein, l.klein_oben) AS klein_oben,
            COALESCE(kh.gross, l.gross_unten) AS gross_unten,
            COALESCE(kh.gross, l.gross_oben) AS gross_oben,
            l.fax_unten,
            l.fax_oben,
            l.wa,
            l.wa_unten,
            l.wa_oben,
            h.h,
            (l.alter_tage + h.h::numeric)::integer AS t,
                CASE
                    WHEN l.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(l.p_hand, l.p_wasch, l.f_ws, l.f_s, l.g_w, l.b_ws, l.b_s, l.b_w, h.h::numeric), l.hagel), l.f)
                    ELSE l.f
                END AS f_h,
            w.wh,
            w.wh_unten,
            w.wh_oben,
            d.heute + h.h AS datum
           FROM lager l
             CROSS JOIN horizonte h
             CROSS JOIN tag d
             JOIN faktor_h w ON w.charge_nr = l.charge_nr AND w.h = h.h
             LEFT JOIN mv_kaliber_quelle kq ON kq.charge_nr = l.charge_nr AND NOT (l.charge_nr IN ( SELECT hc.nr
                   FROM charge hc
                  WHERE hc.hagel_anteil > 0::numeric))
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - l.r, l.alter_tage + h.h::numeric)) kh(klein, gross) ON true
        ), mit_band AS (
         SELECT p.charge_nr,
            p.sorte,
            p.schlag,
            p.kohorte,
            p.alter_tage,
            p.m0,
            p.r,
            p.f,
            p.f_unten,
            p.f_oben,
            p.f_ws,
            p.f_s,
            p.g_w,
            p.p_hand,
            p.p_wasch,
            p.b_ws,
            p.b_s,
            p.b_w,
            p.zuwachs_bekannt,
            p.a_klein_n,
            p.a_gross_n,
            p.a_klein_0,
            p.a_gross_0,
            p.a_fax,
            p.r_bekannt,
            p.f_bekannt,
            p.a_klein_bekannt,
            p.a_gross_bekannt,
            p.a_fax_bekannt,
            p.f_geliehen,
            p.r_unten,
            p.r_oben,
            p.klein_unten,
            p.klein_oben,
            p.gross_unten,
            p.gross_oben,
            p.fax_unten,
            p.fax_oben,
            p.wa,
            p.wa_unten,
            p.wa_oben,
            p.h,
            p.t,
            p.f_h,
            p.wh,
            p.wh_unten,
            p.wh_oben,
            p.datum,
            LEAST(GREATEST(p.f_unten + (p.f_h - p.f), 0::numeric), 1::numeric) AS f_unten_h,
            LEAST(GREATEST(p.f_oben + (p.f_h - p.f), 0::numeric), 1::numeric) AS f_oben_h
           FROM je_portion p
        ), stroeme AS (
         SELECT p.charge_nr,
            p.h,
            p.datum,
            p.t,
            p.m0,
            p.m0 - x.m1 AS verdunstet_kg,
            x.m1 * p.f_h AS faul_kg,
            y.m2 - z.rest AS kanal_kg,
            y.m2 * p.a_klein_n AS klein_kg,
            y.m2 * p.a_gross_n AS gross_kg,
            z.rest * p.a_fax AS fax_kg,
            z.rest * (1::numeric - p.a_fax) AS verkaufsfaehig_kg,
            y.m2 AS gute_ware_kg,
            p.m0 * p.wa_oben * p.wh_oben * (1::numeric - p.f_oben_h) * (1::numeric - LEAST(p.klein_oben / GREATEST(p.klein_oben + p.gross_oben, 1::numeric) + p.gross_oben / GREATEST(p.klein_oben + p.gross_oben, 1::numeric), 1::numeric)) * (1::numeric - p.fax_oben) AS vf_unten,
            p.m0 * p.wa_unten * p.wh_unten * (1::numeric - p.f_unten_h) * (1::numeric - LEAST(p.klein_unten / GREATEST(p.klein_unten + p.gross_unten, 1::numeric) + p.gross_unten / GREATEST(p.klein_unten + p.gross_unten, 1::numeric), 1::numeric)) * (1::numeric - p.fax_unten) AS vf_oben,
            (1::numeric - p.f) * (b0.basis - b.basis * p.wh) AS verlust_wasser,
            b.basis * p.wh * GREATEST(p.f_h - p.f, 0::numeric) AS verlust_faeulnis,
            p.m0 * p.t::numeric AS m0_mal_t,
            p.r_bekannt,
            p.f_bekannt,
            p.a_klein_bekannt,
            p.a_gross_bekannt,
            p.a_fax_bekannt,
            p.f_geliehen,
            p.zuwachs_bekannt
           FROM mit_band p
             CROSS JOIN LATERAL ( SELECT p.m0 * p.wa * p.wh AS m1) x
             CROSS JOIN LATERAL ( SELECT x.m1 * (1::numeric - p.f_h) AS m2) y
             CROSS JOIN LATERAL ( SELECT y.m2 * (1::numeric - p.a_klein_n - p.a_gross_n) AS rest) z
             CROSS JOIN LATERAL ( SELECT p.m0 * (1::numeric - p.a_klein_n - p.a_gross_n) * (1::numeric - p.a_fax) * p.wa AS basis) b
             CROSS JOIN LATERAL ( SELECT p.m0 * (1::numeric - p.a_klein_0 - p.a_gross_0) * (1::numeric - p.a_fax) * p.wa AS basis) b0
        ), gruppen AS (
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
        ), je_charge AS MATERIALIZED (
         SELECT s_1.charge_nr,
            s_1.h,
            max(s_1.datum) AS datum,
            count(*)::integer AS n_kohorten,
            sum(s_1.m0) AS lager_kg,
            sum(s_1.verdunstet_kg) AS verdunstet_kg,
            sum(s_1.faul_kg) AS faul_kg,
            sum(s_1.kanal_kg) AS kanal_kg,
            sum(s_1.klein_kg) AS klein_kg,
            sum(s_1.gross_kg) AS gross_kg,
            sum(s_1.fax_kg) AS fax_kg,
            sum(s_1.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(s_1.gute_ware_kg) AS gute_ware_kg,
            sum(s_1.vf_unten) AS vf_unten_kg,
            sum(s_1.vf_oben) AS vf_oben_kg,
            sum(s_1.verlust_wasser) AS verlust_wasser_kg,
            sum(s_1.verlust_faeulnis) AS verlust_faeulnis_kg,
            sum(s_1.m0_mal_t) AS m0_mal_t,
            bool_and(s_1.r_bekannt) AS r_bekannt,
            bool_and(s_1.f_bekannt) AS f_bekannt,
            bool_and(s_1.a_klein_bekannt AND s_1.a_gross_bekannt) AS kanal_bekannt,
            bool_and(s_1.a_fax_bekannt) AS fax_bekannt,
            bool_or(s_1.f_geliehen) AS f_geliehen,
            bool_and(s_1.zuwachs_bekannt) AS zuwachs_bekannt,
            min(s_1.t) AS alter_von,
            max(s_1.t) AS alter_bis
           FROM stroeme s_1
          GROUP BY s_1.charge_nr, s_1.h
        ), summe AS MATERIALIZED (
         SELECT g.gruppe,
            g.schluessel,
            j.h,
            max(j.datum) AS datum,
            count(*)::integer AS n_chargen,
            sum(j.n_kohorten)::integer AS n_kohorten,
            sum(j.lager_kg) AS lager_kg,
            sum(j.verdunstet_kg) AS verdunstet_kg,
            sum(j.faul_kg) AS faul_kg,
            sum(j.kanal_kg) AS kanal_kg,
            sum(j.klein_kg) AS klein_kg,
            sum(j.gross_kg) AS gross_kg,
            sum(j.fax_kg) AS fax_kg,
            sum(j.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(j.gute_ware_kg) AS gute_ware_kg,
            sum(j.vf_unten_kg) AS vf_unten_kg,
            sum(j.vf_oben_kg) AS vf_oben_kg,
            sum(j.verlust_wasser_kg) AS verlust_wasser_kg,
            sum(j.verlust_faeulnis_kg) AS verlust_faeulnis_kg,
            bool_and(j.r_bekannt) AS r_bekannt,
            bool_and(j.f_bekannt) AS f_bekannt,
            bool_and(j.kanal_bekannt) AS kanal_bekannt,
            bool_and(j.fax_bekannt) AS fax_bekannt,
            bool_or(j.f_geliehen) AS f_geliehen,
            bool_and(j.zuwachs_bekannt) AS zuwachs_bekannt,
            sum(j.m0_mal_t) / NULLIF(sum(j.lager_kg), 0::numeric) AS alter_tage,
            min(j.alter_von) AS alter_von,
            max(j.alter_bis) AS alter_bis
           FROM je_charge j
             JOIN gruppen g ON g.charge_nr = j.charge_nr
          GROUP BY g.gruppe, g.schluessel, j.h
        ), rate AS (
         SELECT s0.gruppe,
            s0.schluessel,
            (s1.verlust_wasser_kg + s1.verlust_faeulnis_kg) / s1.h::numeric AS vf_je_tag_kg,
            s1.verlust_wasser_kg / s1.h::numeric AS verdunstet_je_tag_kg,
                CASE
                    WHEN s1.zuwachs_bekannt THEN s1.verlust_faeulnis_kg / s1.h::numeric
                    ELSE NULL::numeric
                END AS faul_je_tag_kg
           FROM summe s0
             JOIN LATERAL ( SELECT x.gruppe,
                    x.schluessel,
                    x.h,
                    x.datum,
                    x.n_chargen,
                    x.n_kohorten,
                    x.lager_kg,
                    x.verdunstet_kg,
                    x.faul_kg,
                    x.kanal_kg,
                    x.fax_kg,
                    x.verkaufsfaehig_kg,
                    x.gute_ware_kg,
                    x.vf_unten_kg,
                    x.vf_oben_kg,
                    x.verlust_wasser_kg,
                    x.verlust_faeulnis_kg,
                    x.r_bekannt,
                    x.f_bekannt,
                    x.kanal_bekannt,
                    x.fax_bekannt,
                    x.f_geliehen,
                    x.zuwachs_bekannt,
                    x.alter_tage,
                    x.alter_von,
                    x.alter_bis
                   FROM summe x
                  WHERE x.gruppe = s0.gruppe AND x.schluessel = s0.schluessel AND x.h > 0
                  ORDER BY x.h
                 LIMIT 1) s1 ON true
          WHERE s0.h = 0
        )
 SELECT s.gruppe,
    s.schluessel,
    s.h,
    s.datum,
    s.n_chargen,
    s.n_kohorten,
    zahl(s.lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(s.verdunstet_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstet_kg,
    zahl(s.faul_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS faul_kg,
    zahl(s.kanal_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_kg,
    zahl(s.fax_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kg,
    zahl(s.verkaufsfaehig_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(s.gute_ware_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS gute_ware_kg,
    zahl(s.verlust_wasser_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_wasser_kg,
    zahl(s.verlust_faeulnis_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_faeulnis_kg,
    zahl(s.verlust_wasser_kg + s.verlust_faeulnis_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_verkaufsfaehig_kg,
        CASE
            WHEN v.vollstaendig AND s.lager_kg > 0::numeric THEN zahl(s.verkaufsfaehig_kg / s.lager_kg, 4, 1::numeric)
            ELSE NULL::numeric
        END::numeric(6,4) AS verkaufsfaehig_anteil,
        CASE
            WHEN v.vollstaendig THEN zahl(s.vf_unten_kg, 2, '1000000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(14,2) AS verkaufsfaehig_unten_kg,
        CASE
            WHEN v.vollstaendig THEN zahl(s.vf_oben_kg, 2, '1000000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(14,2) AS verkaufsfaehig_oben_kg,
    zahl(r.vf_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS verkaufsfaehig_je_tag_kg,
    zahl(r.verdunstet_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS verdunstet_je_tag_kg,
    zahl(r.faul_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS faul_je_tag_kg,
    s.r_bekannt,
    s.f_bekannt,
    s.kanal_bekannt,
    s.fax_bekannt,
    v.vollstaendig,
    s.f_geliehen,
    s.zuwachs_bekannt,
    round(s.alter_tage)::integer AS alter_tage,
    s.alter_von,
    s.alter_bis,
    zahl(s.klein_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS klein_kg,
    zahl(s.gross_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS gross_kg
   FROM summe s
     CROSS JOIN LATERAL ( SELECT s.r_bekannt AND s.f_bekannt AND s.kanal_bekannt AND s.fax_bekannt AS vollstaendig) v
     LEFT JOIN rate r ON r.gruppe = s.gruppe AND r.schluessel = s.schluessel;
comment on view v_prognose is 'Was aus der heute liegenden Ware wird, wenn sie liegen bleibt — je Gruppe (gesamt, Sorte, Schlag, Charge) und je Horizont h Tage, von heute bis zum Saisonende in Wochenschritten (7/14/28 immer dabei). Es ist die Kaskade (mv_kaskade, Portion „lager") bei alter_tage + h, mit denselben Formeln: bei h = 0 stehen deshalb genau die Zahlen von erg_charge. Der Palox-Anteil wächst je Station um ihren Anstieg je Woche Lagerdauer (0111) — nur wenn zuwachs_bekannt; sonst bleibt der Anteil von heute stehen und faul_je_tag_kg ist leer. kanal_kg = klein_kg + gross_kg (zu klein, zu gross; getrennt seit 0111). f_geliehen: ein Anteil aus allen Sorten. Der Nenner ist lager_kg, die Eingangsware, die noch nicht hinter einer Lieferung steckt; vollstaendig heisst: Verdunstung, Palox, Ausschuss und Fax gemessen.';
grant select on v_prognose to authenticated;

-- ---------- erg_charge ----------
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
    fax_heute_kg,
    verlust_heute_kg,
    kanal_ausgelagert_kg,
    fax_erwartet_kg,
    im_haus_heute_kg,
    kanal_im_haus_kg,
    verlust_bekannt,
    verdunstung_bekannt,
    schimmel_bekannt,
    fax_bekannt,
    kanal_bekannt,
    faul_anteil,
    faul_quelle,
    heute
   FROM v_hochrechnung_basis
with no data;
create unique index if not exists erg_charge_pk on public.erg_charge USING btree (charge_nr);
create index if not exists erg_charge_sorte on public.erg_charge USING btree (sorte);
comment on materialized view erg_charge is 'v_hochrechnung_basis, gespeichert für die App (0062). Erneuert mit auswertung_schritt(). Seit 0101 zählt im_haus_heute_kg das hinter den Lieferungen Aussortierte mit (kanal_ausgelagert_kg: zu klein und zu gross, im Haus, nicht verkaufsfähig). Seit 0106 ohne Sockel, mit faul_anteil und faul_quelle.';
grant select on erg_charge to authenticated;

-- ---------- erg_prognose ----------
create materialized view erg_prognose as
 SELECT gruppe,
    schluessel,
    h,
    datum,
    n_chargen,
    n_kohorten,
    lager_kg,
    verdunstet_kg,
    faul_kg,
    kanal_kg,
    fax_kg,
    verkaufsfaehig_kg,
    gute_ware_kg,
    verlust_wasser_kg,
    verlust_faeulnis_kg,
    verlust_verkaufsfaehig_kg,
    verkaufsfaehig_anteil,
    verkaufsfaehig_unten_kg,
    verkaufsfaehig_oben_kg,
    verkaufsfaehig_je_tag_kg,
    verdunstet_je_tag_kg,
    faul_je_tag_kg,
    r_bekannt,
    f_bekannt,
    kanal_bekannt,
    fax_bekannt,
    vollstaendig,
    f_geliehen,
    zuwachs_bekannt,
    alter_tage,
    alter_von,
    alter_bis,
    klein_kg,
    gross_kg
   FROM v_prognose
with no data;
create index if not exists erg_prognose_gruppe on public.erg_prognose USING btree (gruppe, h);
create unique index if not exists erg_prognose_pk on public.erg_prognose USING btree (gruppe, schluessel, h);
comment on materialized view erg_prognose is 'v_prognose, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';
grant select on erg_prognose to authenticated;

-- ---------- mv_hochrechnung ----------
create materialized view mv_hochrechnung as
 SELECT k.charge_nr,
    k.sorte,
    k.schlag,
    k.portion,
    k.alter_tage,
    k.eingang_kg,
    zahl(c.m0)::numeric(14,2) AS portion_kg,
    k.f_geliehen,
    k.f_n,
    k.f_se,
    s.strom,
    s.buch,
        CASE
            WHEN s.bekannt THEN zahl(s.kg)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
        CASE
            WHEN s.bekannt THEN zahl(s.koeffizient, 6, 100000::numeric)
            ELSE NULL::numeric
        END::numeric(12,6) AS koeffizient,
    s.koeff_n,
    s.koeff_basis,
    s.formel,
    s.d_r,
    s.d_f,
    s.d_a,
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
            LEAST(GREATEST(k.a_klein_n, 0::numeric), 1::numeric) AS a_klein_n,
            LEAST(GREATEST(k.a_gross_n, 0::numeric), 1::numeric) AS a_gross_n,
            LEAST(GREATEST(k.a_fax, 0::numeric), 1::numeric) AS a_fax) c
     CROSS JOIN LATERAL ( VALUES ('Verdunstung'::text,'verlust'::text,c.m0 - c.m1,c.m0,c.r,k.r_n,k.r_basis,'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'::text,- k.d_m1_r,0::numeric,0::numeric,NULL::text,k.r_bekannt), ('Schimmel/Fäulnis'::text,'verlust'::text,c.m1 * c.f,c.m1,c.f,k.f_n,k.f_quelle,'Masse nach Verdunstung × Palox-Anteil der Stationen auf dem Weg der Charge (0106)'::text,k.d_m1_r * c.f,c.m1,0::numeric,NULL::text,k.f_bekannt), ('Zu klein (Tierfutter)'::text,'marge'::text,c.m1 * (1::numeric - c.f) * c.a_klein_n,c.m2,c.a_klein_n,k.klein_n,k.klein_basis,'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust'::text,k.d_m1_r * (1::numeric - c.f) * c.a_klein_n,(- c.m1) * c.a_klein_n,c.m2,'ausschuss'::text,k.a_klein_bekannt), ('Nebenkanal zu gross'::text,'marge'::text,c.m1 * (1::numeric - c.f) * c.a_gross_n,c.m2,c.a_gross_n,k.gross_n,k.gross_basis,'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'::text,k.d_m1_r * (1::numeric - c.f) * c.a_gross_n,(- c.m1) * c.a_gross_n,c.m2,'nebenkanal'::text,k.a_gross_bekannt), ('Faul beim Abpacken (Fax)'::text,'verlust'::text,c.m1 * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),c.a_fax,k.fax_n,k.fax_basis,'Verkaufsfähige Masse × Anteil Faules, das beim Etikettieren aussortiert wird — vom Waschen und Stehen, nicht von der Lagerdauer'::text,k.d_m1_r * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,(- c.m1) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),'fax'::text,k.a_fax_bekannt), ('Verkaufsfähig'::text,'bilanz'::text,c.verkaufsfaehig_kg,c.m2,NULL::numeric,NULL::integer,NULL::text,'Rest der Kaskade'::text,0::numeric,0::numeric,0::numeric,NULL::text,true)) s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel, d_r, d_f, d_a, koeff_art, bekannt)
with no data;
create index if not exists mv_hochrechnung_charge on public.mv_hochrechnung USING btree (charge_nr, buch);
comment on materialized view mv_hochrechnung is 'v_hochrechnung, gespeichert. Inhaltlich gleich; erneuert von auswertung_schritt(3).';
grant select on mv_hochrechnung to authenticated;

-- ---------- v_plausibilitaet_0064_zusatz ----------
create or replace view v_plausibilitaet_0064_zusatz with (security_invoker=true) as
 SELECT 'Tara fehlt'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    min(p.eingangsdatum)::timestamp with time zone AS start_ts,
    format('%s von %s Paletten der Charge haben kein Nettogewicht (%s kg brutto): %s. %s'::text, count(*), r.n_paletten, round(sum(p.brutto_kg)),
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'die Gebindeart steht nicht auf der Palette'::text
            WHEN bool_or(g.art IS NULL) THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN bool_or(g.tara_kg_pro_kiste IS NULL) THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN bool_or(g.tara_kg_palette IS NULL) THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END,
        CASE
            WHEN r.n_paletten_mit_netto = 0 THEN 'Damit hat die Charge gar keinen Eingang — sie fehlt in der ganzen Bilanz.'::text
            ELSE format('Für sie rechnet der Eingang mit dem Mittel der übrigen: %s der %s kg '::text || 'Eingang sind hochgerechnet, nicht gewogen.'::text, round(r.eingang_netto_kg - r.eingang_netto_gemessen_kg), round(r.eingang_netto_kg))
        END) AS befund,
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'Gebindeart am Wareneingang nachtragen.'::text
            WHEN bool_or(g.art IS NULL) OR bool_or(g.tara_kg_pro_kiste IS NULL) OR bool_or(g.tara_kg_palette IS NULL) THEN 'Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. '::text || 'Die Zahlen rechnen sich danach von selbst neu.'::text
            ELSE 'Kistenzahl der Palette im Wareneingang nachtragen.'::text
        END AS rat,
    'charge:'::text || p.charge_nr AS bezug
   FROM palette p
     LEFT JOIN gebinde g ON g.art = p.gebindeart
     JOIN charge c ON c.nr = p.charge_nr
     JOIN v_charge_rueckgrat r ON r.charge_nr = p.charge_nr
  WHERE (p.brutto_kg - p.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) IS NULL
  GROUP BY p.charge_nr, c.sorte, r.n_paletten, r.n_paletten_mit_netto, r.eingang_netto_kg, r.eingang_netto_gemessen_kg
UNION ALL
 SELECT 'Überzählung'::text AS art,
    NULL::bigint AS auftrag_id,
    h.charge_nr,
    h.sorte,
    h.eingangsdatum_mittel::timestamp with time zone AS start_ts,
    format('Die Lieferungen dieser Charge (%s kg) brauchen nach der gerechneten Ausbeute (%s %% verkaufsfähig) %s kg Eingang — erfasst sind %s kg, also %s kg zu wenig. Geliefert wurde nicht mehr als eingelagert; es wurde mehr geliefert, als die Rechnung aus diesem Eingang erwartet.'::text, round(h.geliefert_kg), round(100::numeric * h.geliefert_kg / NULLIF(h.eingang_kg + h.ueberzaehlung_kg, 0::numeric)), round(h.eingang_kg + h.ueberzaehlung_kg), round(h.eingang_kg), round(h.ueberzaehlung_kg)) AS befund,
    'Drei Möglichkeiten: Im Erntejournal fehlt eine Palette dieser Charge; ein Lieferschein ist auf die falsche Chargennummer gebucht; oder diese Charge hat weniger Verlust als das Modell annimmt — dann ist „Im Lager" für sie zu klein gerechnet. Die ersten zwei lassen sich nachtragen.'::text AS rat,
    'charge:'::text || h.charge_nr AS bezug
   FROM v_hochrechnung_basis h
  WHERE h.ueberzaehlung_kg > 0::numeric
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — %s, nicht mit der Palette selbst.'::text, count(*), ap.brutto_zettel_kg, to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text),
        CASE
            WHEN bool_and(m.masse_quelle = 'gewogen'::text) THEN 'gerechnet wird mit der Wägung der Palette'::text
            WHEN bool_and(m.masse_quelle = 'zettel-kisten'::text) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            WHEN bool_and(m.masse_quelle = ANY (ARRAY['zettel-kisten'::text, 'zettel-kisten-charge'::text, 'gewogen'::text])) THEN 'gerechnet wird mit den gezählten Kisten und der Tara je Kiste der Charge (Zettel − Kisten × Tara je Kiste)'::text
            ELSE 'gerechnet wird mit der mittleren Tara ganzer Paletten der Charge — an der Zählung fehlt die Kistenzahl'::text
        END) AS befund,
    'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'::text AS rat,
    (((('zettel:'::text || ap.auftrag_id) || ':'::text) || ap.brutto_zettel_kg) || ':'::text) || ap.eingangsdatum AS bezug
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.id = ap.id
  WHERE ap.brutto_zettel_kg IS NOT NULL AND ap.eingangsdatum IS NOT NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg)) AND NOT (EXISTS ( SELECT 1
           FROM v_palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg AND p.eingangsdatum = ap.eingangsdatum AND p.netto_kg IS NOT NULL))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg, ap.eingangsdatum
UNION ALL
 SELECT 'Palette fraglich'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s: %s kg brutto in %s Kiste(n) %s, mit Palette gewogen — davon bleiben %s kg netto. Eine leere Palette wiegt allein %s kg.'::text,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'Zu klein'::text
            ELSE 'Zu gross'::text
        END, m.brutto_kg, m.kisten, m.gebindeart, m.kg, g.tara_kg_palette) AS befund,
    'Standen die Kisten direkt auf der Waage? Dann in der Korrektur „mit Palette" abwählen — das Netto rechnet sich von selbst neu.'::text AS rat,
    'ausschuss_messung:'::text || m.id AS bezug
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.gemessen AND m.mit_palette AND m.brutto_kg IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND m.brutto_kg < (2::numeric * g.tara_kg_palette) AND a.abgebrochen_ts IS NULL
UNION ALL
 SELECT 'Verdunstung'::text AS art,
    m.auftrag_id,
    m.charge_nr,
    m.sorte,
    m.wiege_ts AS start_ts,
    format('%s %% je Tag: %s kg → %s kg in %s Tagen — so schnell verdunstet kein Kürbis (Grenze %s %% je Tag)'::text, round(m.rate_pro_tag * 100::numeric, 2), round(m.netto_damals_kg), round(m.netto_jetzt_kg), m.lagertage, round(verdunstung_rate_max() * 100::numeric, 2)) AS befund,
    'Zettelgewicht, Kisten und Gebinde dieser Wägung prüfen — oder es ist eine andere Palette. Bis zur Korrektur zählt sie nicht in die Rate.'::text AS rat,
    'verdunstung_wiegung:'::text || m.id AS bezug
   FROM v_verdunstung_messung m
  WHERE m.grund ~~ 'zu schnell%'::text;
comment on view v_plausibilitaet_0064_zusatz is 'Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die Paletten fehlen im Eingang), eine Charge mit mehr Ausgang als Eingang, und ein Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag. 0128: dazu je Auffälligkeit ihr Bezug.';
grant select on v_plausibilitaet_0064_zusatz to authenticated;

-- ---------- v_charge_spur ----------
create or replace view v_charge_spur with (security_invoker=true) as
 WITH journal AS (
         SELECT COALESCE(p.charge_nr_journal, p.charge_nr) AS nr,
            count(*)::integer AS n,
            sum(vp.netto_kg) AS kg,
            min(p.eingangsdatum) AS von,
            max(p.eingangsdatum) AS bis
           FROM palette p
             JOIN v_palette vp ON vp.id = p.id
          GROUP BY (COALESCE(p.charge_nr_journal, p.charge_nr))
        ), jetzt AS (
         SELECT p.charge_nr AS nr,
            count(*)::integer AS n,
            sum(vp.netto_kg) AS kg
           FROM palette p
             JOIN v_palette vp ON vp.id = p.id
          GROUP BY p.charge_nr
        ), zuordnung AS (
         SELECT z.von_charge_nr,
            z.nach_charge_nr,
            z.stand,
            count(*)::integer AS n,
            sum(vp.netto_kg) AS kg
           FROM palette_zuordnung z
             JOIN v_palette vp ON vp.id = z.palette_id
          WHERE z.stand = ANY (ARRAY['angewandt'::text, 'vorschlag'::text])
          GROUP BY z.von_charge_nr, z.nach_charge_nr, z.stand
        ), arbeit AS (
         SELECT a_1.charge_nr AS nr,
            count(*)::integer AS n,
            min((a_1.start_ts AT TIME ZONE 'Europe/Zurich'::text)::date) AS von,
            max((a_1.start_ts AT TIME ZONE 'Europe/Zurich'::text)::date) AS bis,
            jsonb_agg(jsonb_build_object('id', a_1.id, 'datum', (a_1.start_ts AT TIME ZONE 'Europe/Zurich'::text)::date, 'station', a_1.station, 'zettel', ( SELECT count(*) AS count
                   FROM auftrag_palette ap
                  WHERE ap.auftrag_id = a_1.id)) ORDER BY a_1.start_ts) AS liste
           FROM auftrag a_1
          WHERE a_1.abgebrochen_ts IS NULL
          GROUP BY a_1.charge_nr
        ), lief AS (
         SELECT l.charge_nr AS nr,
            count(*)::integer AS n,
            sum(l.masse_kg) AS kg,
            min(l.datum) AS von,
            max(l.datum) AS bis
           FROM v_lieferung_masse l
          WHERE l.charge_nr IS NOT NULL AND l.masse_kg > 0::numeric AND (l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])) AND l.datum <= heute()
          GROUP BY l.charge_nr
        ), artikel AS (
         SELECT l.charge_nr AS nr,
            (artikel_einordnen(z.artikel, z.preisgruppe)).gruppe AS gruppe,
            sum(l.masse_kg) AS kg
           FROM v_lieferung_masse l
             JOIN lieferung_import li ON li.lieferung_id = l.id
             JOIN ausgang_zeile z ON z.id = li.zeile_id
          WHERE l.charge_nr IS NOT NULL AND l.masse_kg > 0::numeric AND (l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])) AND l.datum <= heute()
          GROUP BY l.charge_nr, ((artikel_einordnen(z.artikel, z.preisgruppe)).gruppe)
        ), nach_artikel AS (
         SELECT x.nr,
            COALESCE(x.gruppe, 'andere'::text) AS gruppe,
            x.kg
           FROM artikel x
        UNION ALL
         SELECT f_1.nr,
            'ohne Perigon-Zeile'::text AS text,
            f_1.kg - COALESCE(a_1.kg, 0::numeric)
           FROM lief f_1
             LEFT JOIN ( SELECT x.nr,
                    sum(x.kg) AS kg
                   FROM artikel x
                  GROUP BY x.nr) a_1 ON a_1.nr = f_1.nr
          WHERE (f_1.kg - COALESCE(a_1.kg, 0::numeric)) > 0.5
        ), nach AS (
         SELECT n.charge_nr AS nr,
            n.weg,
            count(*)::integer AS n,
            sum(l.masse_kg) AS kg
           FROM lieferung_nachordnung n
             JOIN v_lieferung_masse l ON l.id = n.lieferung_id
          GROUP BY n.charge_nr, n.weg
        )
 SELECT c.nr AS charge_nr,
    c.schlag,
    c.sorte,
    sk.artikelgruppe,
    COALESCE(j.n, 0) AS journal_paletten,
    zahl(j.kg, 2, '1000000000000'::numeric)::numeric(14,2) AS journal_kg,
    j.von AS journal_von,
    j.bis AS journal_bis,
    COALESCE(t.n, 0) AS paletten,
    zahl(t.kg, 2, '1000000000000'::numeric)::numeric(14,2) AS eingang_kg,
    ( SELECT jsonb_agg(jsonb_build_object('charge_nr', z.nach_charge_nr, 'stand', z.stand, 'paletten', z.n, 'kg', round(z.kg)) ORDER BY z.stand, z.nach_charge_nr) AS jsonb_agg
           FROM zuordnung z
          WHERE z.von_charge_nr = c.nr) AS weg,
    ( SELECT jsonb_agg(jsonb_build_object('charge_nr', z.von_charge_nr, 'stand', z.stand, 'paletten', z.n, 'kg', round(z.kg)) ORDER BY z.stand, z.von_charge_nr) AS jsonb_agg
           FROM zuordnung z
          WHERE z.nach_charge_nr = c.nr) AS her,
    COALESCE(a.n, 0) AS arbeiten,
    a.von AS arbeit_von,
    a.bis AS arbeit_bis,
    a.liste AS arbeit_liste,
    COALESCE(f.n, 0) AS lieferscheine,
    zahl(f.kg, 2, '1000000000000'::numeric)::numeric(14,2) AS geliefert_kg,
    f.von AS lief_von,
    f.bis AS lief_bis,
    ( SELECT jsonb_agg(jsonb_build_object('gruppe', x.gruppe, 'kg', round(x.kg)) ORDER BY x.kg DESC) AS jsonb_agg
           FROM nach_artikel x
          WHERE x.nr = c.nr) AS nach_artikel,
    ( SELECT jsonb_agg(jsonb_build_object('weg', x.weg, 'n', x.n, 'kg', round(x.kg)) ORDER BY x.weg) AS jsonb_agg
           FROM nach x
          WHERE x.nr = c.nr) AS nachgeordnet,
    zahl(b.n_rest_paletten::double precision, 1, '1000000'::numeric)::numeric(7,1) AS rest_paletten
   FROM charge c
     LEFT JOIN sorte_kaliber sk ON sk.sorte = c.sorte
     LEFT JOIN journal j ON j.nr = c.nr
     LEFT JOIN jetzt t ON t.nr = c.nr
     LEFT JOIN arbeit a ON a.nr = c.nr
     LEFT JOIN lief f ON f.nr = c.nr
     LEFT JOIN erg_charge b ON b.charge_nr = c.nr
  WHERE j.n IS NOT NULL OR t.n IS NOT NULL OR a.n IS NOT NULL OR f.n IS NOT NULL;
comment on view v_charge_spur is 'Der Weg der Ware je Charge (0122): herein laut Erntejournal (journal_*: die Charge, die das Journal nennt) und wie die App jetzt zählt (paletten, eingang_kg), was umgebucht ist oder vorgeschlagen (weg: von hier weg, her: hierher), bearbeitet in der Halle (Arbeiten, mit Zahl der Zettel), hinaus laut Lieferscheinen (Lieferscheine; nach_artikel: je Artikelgruppe aus den Perigon-Zeilen, der Rest als „ohne Perigon-Zeile" — die Teile gehen auf geliefert_kg auf (0124); davon nachgeordnet), und was laut App noch da ist (rest_paletten).';
grant select on v_charge_spur to authenticated;

-- ---------- v_hochrechnung ----------
create or replace view v_hochrechnung with (security_invoker=true) as
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    portion_kg,
    f_geliehen,
    f_n,
    f_se,
    strom,
    buch,
    kg,
    basis_kg,
    koeffizient,
    koeff_n,
    koeff_basis,
    formel,
    d_r,
    d_f,
    d_a,
    koeff_art,
    koeff_bekannt,
    kohorte
   FROM mv_hochrechnung;
comment on view v_hochrechnung is 'Die Kaskade auseinandergelegt: eine Zeile je Charge, Portion und Strom, mit dem verwendeten Koeffizienten, seiner Herkunft (koeff_art, beim Faulen koeff_basis = f_quelle), der Zahl der Messungen dahinter (koeff_n) und der Formel. koeff_bekannt = false heisst: geschätzt, nicht gemessen. f_geliehen: der Palox-Anteil kommt aus den Arbeiten aller Sorten (0106).';
grant select on v_hochrechnung to authenticated;

-- ---------- v_kontrolle_vorschlag ----------
create or replace view v_kontrolle_vorschlag with (security_invoker=true) as
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
comment on view v_kontrolle_vorschlag is 'Welche Charge als Nächstes kontrolliert werden sollte. informationswert gewichtet, wie viel noch im Haus liegt, wie lange die letzte Wiegung her ist und wie unsicher die Charge bisher ist — eine Reihenfolge, kein Befehl.';
grant select on v_kontrolle_vorschlag to authenticated;

-- ---------- v_lager_ausweis ----------
create or replace view v_lager_ausweis with (security_invoker=true) as
 WITH hagel_lager AS (
         SELECT k.charge_nr,
            max(k.hagel) FILTER (WHERE k.portion = 'lager'::text AND k.m0 > 0::numeric) AS h,
            sum(
                CASE
                    WHEN k.portion <> 'lager'::text AND k.hagel > 0::numeric AND k.hagel < 1::numeric THEN 0::numeric
                    ELSE 0::numeric
                END) AS hagel_ausgelagert
           FROM mv_kaskade k
          GROUP BY k.charge_nr
        ), marge_charge AS (
         SELECT m_1.charge_nr,
            sum(m_1.zuviel_je_kiste * m_1.kisten::numeric) FILTER (WHERE m_1.soll_kg_pro_kiste > 0::numeric AND m_1.zuviel_je_kiste IS NOT NULL) / NULLIF(sum(m_1.soll_kg_pro_kiste * m_1.kisten::numeric) FILTER (WHERE m_1.soll_kg_pro_kiste > 0::numeric AND m_1.zuviel_je_kiste IS NOT NULL), 0::numeric) AS a,
            sum(m_1.n_wiegungen) FILTER (WHERE m_1.soll_kg_pro_kiste > 0::numeric AND m_1.zuviel_je_kiste IS NOT NULL)::integer AS n_kg,
            bool_or(m_1.kistensystem = 'stueck'::text) AS stueck
           FROM erg_marge_charge m_1
          GROUP BY m_1.charge_nr
        ), marge_sorte AS (
         SELECT m_1.sorte,
            sum(m_1.zuviel_je_kiste * m_1.kisten::numeric) FILTER (WHERE m_1.soll_kg_pro_kiste > 0::numeric AND m_1.zuviel_je_kiste IS NOT NULL) / NULLIF(sum(m_1.soll_kg_pro_kiste * m_1.kisten::numeric) FILTER (WHERE m_1.soll_kg_pro_kiste > 0::numeric AND m_1.zuviel_je_kiste IS NOT NULL), 0::numeric) AS a,
            sum(m_1.n_wiegungen) FILTER (WHERE m_1.soll_kg_pro_kiste > 0::numeric AND m_1.zuviel_je_kiste IS NOT NULL)::integer AS n_kg,
            bool_or(m_1.kistensystem = 'stueck'::text) AS stueck
           FROM erg_marge_charge m_1
          GROUP BY m_1.sorte
        ), ohne_system AS (
         SELECT k.charge_nr,
            count(*)::integer AS n
           FROM v_ausgang_kennzahl k
          WHERE k.kistensystem IS NULL OR k.kistensystem = 'kiste_ab'::text AND COALESCE(k.soll_kg_pro_kiste, 0::numeric) <= 0::numeric
          GROUP BY k.charge_nr
        ), basis AS (
         SELECT c.charge_nr,
            c.sorte,
            c.schlag,
            c.n_rest_paletten AS paletten,
            c.lager_kg AS liegend_kg,
            p.lager_kg,
            p.alter_tage,
            p.verdunstet_kg,
            p.verdunstet_je_tag_kg,
            p.faul_kg AS faul_mit_hagel_kg,
            p.gute_ware_kg,
            p.klein_kg,
            p.gross_kg,
            p.fax_kg,
            p.verkaufsfaehig_kg,
            p.r_bekannt,
            p.f_bekannt,
            p.kanal_bekannt,
            p.fax_bekannt,
            COALESCE(hl.h, 0::numeric) AS h,
            COALESCE(hl.hagel_ausgelagert, 0::numeric) AS hagel_ausgelagert,
            c.verlust_heute_kg,
                CASE
                    WHEN mc.a IS NOT NULL THEN mc.a
                    WHEN mc.stueck THEN 0::numeric
                    WHEN ms.a IS NOT NULL THEN ms.a
                    WHEN ms.stueck THEN 0::numeric
                    ELSE NULL::numeric
                END AS marge_anteil,
                CASE
                    WHEN mc.a IS NOT NULL THEN format('gewogen: %s %s dieser Charge'::text, mc.n_kg,
                    CASE
                        WHEN mc.n_kg = 1 THEN 'Palette'::text
                        ELSE 'Paletten'::text
                    END)
                    WHEN mc.stueck THEN 'Stück-Kisten: ohne Sollgewicht keine Überfüllung'::text
                    WHEN ms.a IS NOT NULL THEN format('Sorte %s: %s gewogene %s'::text, c.sorte, ms.n_kg,
                    CASE
                        WHEN ms.n_kg = 1 THEN 'Palette'::text
                        ELSE 'Paletten'::text
                    END)
                    WHEN ms.stueck THEN 'Stück-Kisten: ohne Sollgewicht keine Überfüllung'::text
                    WHEN os.n > 0 THEN format('%s gewogene %s, aber die Arbeit hat kein Kistensystem oder kein Sollgewicht — keine Überfüllung zu rechnen (Messungen → Arbeiten → korrigieren)'::text, os.n,
                    CASE
                        WHEN os.n = 1 THEN 'Palette'::text
                        ELSE 'Paletten'::text
                    END)
                    ELSE 'nicht gewogen'::text
                END AS marge_quelle,
            COALESCE(os.n, 0) AS n_ohne_system
           FROM erg_charge c
             LEFT JOIN erg_prognose p ON p.gruppe = 'charge'::text AND p.schluessel = c.charge_nr::text AND p.h = 0
             LEFT JOIN hagel_lager hl ON hl.charge_nr = c.charge_nr
             LEFT JOIN marge_charge mc ON mc.charge_nr = c.charge_nr
             LEFT JOIN marge_sorte ms ON ms.sorte = c.sorte
             LEFT JOIN ohne_system os ON os.charge_nr = c.charge_nr
        ), mit_hagel AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.paletten,
            b.liegend_kg,
            b.lager_kg,
            b.alter_tage,
            b.verdunstet_kg,
            b.verdunstet_je_tag_kg,
            b.faul_mit_hagel_kg,
            b.gute_ware_kg,
            b.klein_kg,
            b.gross_kg,
            b.fax_kg,
            b.verkaufsfaehig_kg,
            b.r_bekannt,
            b.f_bekannt,
            b.kanal_bekannt,
            b.fax_bekannt,
            b.h,
            b.hagel_ausgelagert,
            b.verlust_heute_kg,
            b.marge_anteil,
            b.marge_quelle,
            b.n_ohne_system,
                CASE
                    WHEN b.gute_ware_kg IS NULL THEN NULL::numeric
                    WHEN b.h <= 0::numeric THEN 0::numeric
                    ELSE b.verkaufsfaehig_kg
                END AS unique_kg
           FROM basis b
        ), artikel AS (
         SELECT t.charge_nr,
            sum(t.kg) FILTER (WHERE t.groesse = ANY (ARRAY['darunter'::text, 'darueber'::text, 'dazwischen'::text])) AS keinen_artikel_kg,
            sum(t.kg) FILTER (WHERE t.groesse = 'lose'::text AND t.artikelgruppe IS NULL) AS gruppe_offen_kg,
            sum(t.kg) FILTER (WHERE t.groesse = 'ohne Verteilung'::text) AS groesse_offen_kg
           FROM artikel_lager_teile(0) t(charge_nr, sorte, artikelgruppe, label, groesse, kg, g_mittel, h, datum)
          GROUP BY t.charge_nr
        ), verkaufbar AS (
         SELECT m_1.charge_nr,
            m_1.sorte,
            m_1.schlag,
            m_1.paletten,
            m_1.liegend_kg,
            m_1.lager_kg,
            m_1.alter_tage,
            m_1.verdunstet_kg,
            m_1.verdunstet_je_tag_kg,
            m_1.faul_mit_hagel_kg,
            m_1.gute_ware_kg,
            m_1.klein_kg,
            m_1.gross_kg,
            m_1.fax_kg,
            m_1.verkaufsfaehig_kg,
            m_1.r_bekannt,
            m_1.f_bekannt,
            m_1.kanal_bekannt,
            m_1.fax_bekannt,
            m_1.h,
            m_1.hagel_ausgelagert,
            m_1.verlust_heute_kg,
            m_1.marge_anteil,
            m_1.marge_quelle,
            m_1.n_ohne_system,
            m_1.unique_kg,
                CASE
                    WHEN m_1.verkaufsfaehig_kg IS NULL THEN NULL::numeric
                    WHEN m_1.verkaufsfaehig_kg <= 0::numeric THEN 0::numeric
                    WHEN COALESCE(a.groesse_offen_kg, 0::numeric) > 0::numeric THEN NULL::numeric
                    ELSE COALESCE(a.keinen_artikel_kg, 0::numeric)
                END AS keinen_artikel_kg,
                CASE
                    WHEN m_1.verkaufsfaehig_kg IS NULL THEN NULL::numeric
                    WHEN m_1.verkaufsfaehig_kg > 0::numeric THEN COALESCE(a.groesse_offen_kg, 0::numeric)
                    ELSE 0::numeric
                END AS groesse_offen_kg,
                CASE
                    WHEN m_1.verkaufsfaehig_kg IS NULL THEN NULL::numeric
                    WHEN m_1.verkaufsfaehig_kg > 0::numeric THEN COALESCE(a.gruppe_offen_kg, 0::numeric)
                    ELSE 0::numeric
                END AS gruppe_offen_kg
           FROM mit_hagel m_1
             LEFT JOIN artikel a ON a.charge_nr = m_1.charge_nr
        ), netto AS (
         SELECT v.charge_nr,
            v.sorte,
            v.schlag,
            v.paletten,
            v.liegend_kg,
            v.lager_kg,
            v.alter_tage,
            v.verdunstet_kg,
            v.verdunstet_je_tag_kg,
            v.faul_mit_hagel_kg,
            v.gute_ware_kg,
            v.klein_kg,
            v.gross_kg,
            v.fax_kg,
            v.verkaufsfaehig_kg,
            v.r_bekannt,
            v.f_bekannt,
            v.kanal_bekannt,
            v.fax_bekannt,
            v.h,
            v.hagel_ausgelagert,
            v.verlust_heute_kg,
            v.marge_anteil,
            v.marge_quelle,
            v.n_ohne_system,
            v.unique_kg,
            v.keinen_artikel_kg,
            v.groesse_offen_kg,
            v.gruppe_offen_kg,
            v.verkaufsfaehig_kg - COALESCE(v.keinen_artikel_kg, 0::numeric) AS als_artikel_kg,
            (v.verkaufsfaehig_kg - COALESCE(v.keinen_artikel_kg, 0::numeric)) * v.marge_anteil / (1::numeric + v.marge_anteil) AS ueberfuellung_kg
           FROM verkaufbar v
        )
 SELECT charge_nr,
    sorte,
    schlag,
    paletten,
    zahl(COALESCE(lager_kg, liegend_kg), 2, '1000000000000'::numeric)::numeric(14,2) AS eingang_kg,
    alter_tage,
    zahl(verdunstet_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstet_kg,
    zahl(verdunstet_je_tag_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstet_je_tag_kg,
    zahl(faul_mit_hagel_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS faul_kg,
    zahl(unique_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS unique_kg,
    zahl(NULLIF(h, 0::numeric), 4, '10'::numeric)::numeric(5,4) AS hagel_anteil,
    zahl(klein_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS zu_klein_kg,
    zahl(gross_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS zu_gross_kg,
    zahl(fax_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kg,
    zahl(verkaufsfaehig_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(marge_anteil, 5, '1000'::numeric)::numeric(8,5) AS marge_anteil,
    marge_quelle,
    zahl(verkaufsfaehig_kg * marge_anteil / (1::numeric + marge_anteil), 2, '1000000000000'::numeric)::numeric(14,2) AS marge_kg,
    zahl(verkaufsfaehig_kg / (1::numeric + marge_anteil), 2, '1000000000000'::numeric)::numeric(14,2) AS verrechenbar_kg,
    zahl(hagel_ausgelagert, 2, '1000000000000'::numeric)::numeric(14,2) AS hagel_bis_heute_kg,
    COALESCE(r_bekannt, false) AS r_bekannt,
    COALESCE(f_bekannt, false) AS f_bekannt,
    COALESCE(kanal_bekannt, false) AS kanal_bekannt,
    COALESCE(fax_bekannt, false) AS fax_bekannt,
    zahl(keinen_artikel_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS keinen_artikel_kg,
    zahl(groesse_offen_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS groesse_offen_kg,
    zahl(ueberfuellung_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS ueberfuellung_kg,
    zahl(als_artikel_kg - COALESCE(ueberfuellung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufbar_kg,
    NULLIF(concat_ws(', '::text,
        CASE
            WHEN h > 0::numeric THEN 'Hagel-Charge: Verkauf über den Ünique-Topf'::text
            ELSE NULL::text
        END,
        CASE
            WHEN verkaufsfaehig_kg > 0::numeric AND marge_anteil IS NULL THEN
            CASE
                WHEN n_ohne_system > 0 THEN 'Überfüllung offen: Paletten gewogen, aber die Arbeit hat kein Kistensystem oder kein Sollgewicht'::text
                ELSE 'Überfüllung nicht gewogen'::text
            END
            ELSE NULL::text
        END,
        CASE
            WHEN groesse_offen_kg > 0::numeric THEN 'Grösse offen (keine Sortier-CSV)'::text
            ELSE NULL::text
        END,
        CASE
            WHEN gruppe_offen_kg > 0::numeric THEN 'Artikelgruppe fehlt (Stammdaten → Sorten)'::text
            ELSE NULL::text
        END), ''::text) AS verkaufbar_offen,
    zahl(gruppe_offen_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS gruppe_offen_kg
   FROM netto m;
comment on view v_lager_ausweis is 'Was im Lager liegt, Schritt für Schritt, je Charge heute (0121, 0123, 0124): eingang_kg (Eingangsmasse auf den Paletten, die noch stehen — „im Lager") − verdunstet − faul (Palox, ohne Hagel) − unique (Hagel, wird als Knospe verkauft) − zu klein − zu gross (Sortiermaschine) − Faules beim Abpacken = verkaufsfaehig_kg (nach der Sortiermaschine); davon marge_kg Überfüllung (marge_anteil = zu viel ÷ Soll, gewogen je Charge, sonst je Sorte; Stück-Kisten 0), verrechenbar_kg der Rest. verkaufbar_kg = verkaufsfaehig_kg − keinen_artikel_kg (leichter oder schwerer als die Artikelgewichte, artikel_lager_teile; leer ohne Sortier-CSV) − ueberfuellung_kg (auf dem Teil, der als Artikel geht) + unique_kg — was als Artikel tatsächlich verkauft werden kann. groesse_offen_kg: ohne Sortier-CSV; gruppe_offen_kg: Sorte ohne Artikelgruppe (0124) — beides nicht abgezogen, verkaufbar_kg ist dann eine obere Schranke, und verkaufbar_offen sagt, was fehlt. Hagel 100 %: faul_kg, unique_kg und verkaufbar_kg leer (nicht trennbar). hagel_bis_heute_kg: der Hagel-Teil im Faulen bis heute, kein Verlust. Aus erg_prognose (h = 0), erg_charge, mv_kaskade, erg_marge_charge, v_ausgang_kennzahl, artikel_lager_teile(0).';
grant select on v_lager_ausweis to authenticated;

-- ---------- v_massenbilanz ----------
create or replace view v_massenbilanz with (security_invoker=true) as
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
            b_1.am_band_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), COALESCE(b_1.alter_band, 0::numeric)) * (1::numeric - COALESCE(ep.anteil, er.anteil)) * q.anteil_mit_csv AS am_band_modell_kg
           FROM v_kaskade_basis b_1
             LEFT JOIN csv_anteil q ON q.charge_nr = b_1.charge_nr
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b_1.sorte
             LEFT JOIN v_charge_palox ep ON ep.charge_nr = b_1.charge_nr AND ep.station = 'sortieren'::text
             LEFT JOIN v_palox_erwartung er ON er.sorte = b_1.sorte AND er.station = 'sortieren'::text
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
comment on view v_massenbilanz is 'Die Probe aufs Exempel je Charge: Was die Kaskade am Band erwartet (modell_am_band_kg: Bandarbeiten nach Verdunstung und Palox-Anteil der Sortierstation, 0106) gegen das, was die Sortier-Datei gewogen hat (csv_gemessen_kg). abweichung_anteil nahe 0 heisst, die Koeffizienten treffen die Wirklichkeit; systematisch positiv heisst, die Verluste sind überschätzt. Nur für Chargen mit Sortier-Datei aussagekräftig.';
grant select on v_massenbilanz to authenticated;

-- ---------- v_naechste_charge ----------
create or replace view v_naechste_charge with (security_invoker=true) as
 SELECT p0.schluessel::integer AS charge_nr,
    b.sorte,
    b.schlag,
    p0.lager_kg,
    p0.alter_tage,
    p0.gute_ware_kg AS masse_jetzt_kg,
    zahl(p14.verlust_wasser_kg, 1, '100000000000'::numeric)::numeric(12,1) AS verdunstung_14_kg,
        CASE
            WHEN p0.zuwachs_bekannt THEN zahl(p14.verlust_faeulnis_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1) AS schimmel_14_kg,
        CASE
            WHEN p0.zuwachs_bekannt THEN zahl(p14.verlust_verkaufsfaehig_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1) AS prognose_verlust_14_kg,
    p0.f_geliehen,
    p0.zuwachs_bekannt,
    p0.alter_von,
    p0.alter_bis,
    p0.n_kohorten
   FROM erg_prognose p0
     JOIN erg_prognose p14 ON p14.gruppe = 'charge'::text AND p14.schluessel = p0.schluessel AND p14.h = 14
     JOIN v_kaskade_basis b ON b.charge_nr = p0.schluessel::integer
  WHERE p0.gruppe = 'charge'::text AND p0.h = 0 AND p0.lager_kg > 0::numeric
  ORDER BY (
        CASE
            WHEN p0.zuwachs_bekannt THEN zahl(p14.verlust_verkaufsfaehig_kg, 1, '100000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(12,1)) DESC NULLS LAST;
comment on view v_naechste_charge is 'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Gerechnet aus v_prognose (Horizont 14 gegen Horizont 0) — dieselbe Formel wie die Kaskade, damit es im ganzen Programm nur eine Zwei-Wochen-Zahl gibt. prognose_verlust_14_kg ist, was an **verkaufsfähiger** Ware verloren geht, und verdunstung_14_kg + schimmel_14_kg ergeben es auf den Rappen. Seit 0106 leer, solange die Kennzahl je Station keinen Zuwachs ausweist (zuwachs_bekannt = false).';
grant select on v_naechste_charge to authenticated;

-- ---------- v_plausibilitaet_0054_zusatz ----------
create or replace view v_plausibilitaet_0054_zusatz with (security_invoker=true) as
 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber für ein Band mit diesen Grenzen hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, a.kaliber_von_g, a.kaliber_bis_g) AS befund,
    'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) oder die fertigen Paletten wiegen (drei reichen).'::text AS rat,
    (('gebinde:'::text || g.auftrag_id) || ':'::text) || g.kaliber_idx AS bezug
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx = '-2'::integer AND NOT (EXISTS ( SELECT 1
           FROM v_auftrag_wasch_gewogen wg
          WHERE wg.auftrag_id = g.auftrag_id AND wg.quelle = 'gewogen_strasse'::text))
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    wp.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '::text || 'die Menge dieser Arbeit damit auch'::text, wp.n_paletten, wp.kisten,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN format('für das Band %s–%s g hat noch keine Wasch-Arbeit ihre fertigen Paletten gewogen'::text, a.kaliber_von_g, a.kaliber_bis_g)
            ELSE 'für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen'::text
        END) AS befund,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht — oder bei der nächsten Wasch-Arbeit mit diesem Band die fertigen Paletten wiegen (drei reichen) und die Kaliber-Paletten zählen.'::text
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — dann kennt die App das Kistengewicht des Bandes, rückwirkend auch für diese Arbeit; oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat,
    'waschpaletten:'::text || wp.auftrag_id AS bezug
   FROM v_auftrag_wasch_paletten wp
     JOIN auftrag a ON a.id = wp.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE wp.kg IS NULL AND wp.kisten > 0 AND NOT (EXISTS ( SELECT 1
           FROM v_auftrag_wasch_gewogen wg
          WHERE wg.auftrag_id = wp.auftrag_id AND wg.quelle = 'gewogen_strasse'::text))
UNION ALL
 SELECT 'Lieferung in der Zukunft'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    l.datum::timestamp with time zone AS start_ts,
    format('Lieferschein über %s kg mit Datum %s — das liegt nach heute (%s). '::text || 'Die Menge zählt erst ab diesem Tag in Ausgang und Bestand.'::text, round(l.masse_kg), to_char(l.datum::timestamp with time zone, 'DD.MM.YYYY'::text), to_char(heute()::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Stimmt das Datum? Ein vordatierter Lieferschein ist in Ordnung — die Zahl '::text || 'erscheint von selbst, sobald der Tag da ist. Ein Zahlendreher gehört korrigiert.'::text AS rat,
    'lieferung:'::text || l.id AS bezug
   FROM v_lieferung_masse l
  WHERE l.datum > heute() AND l.masse_kg IS NOT NULL AND l.masse_kg > 0::numeric
UNION ALL
 SELECT v_plausibilitaet_0064_zusatz.art,
    v_plausibilitaet_0064_zusatz.auftrag_id,
    v_plausibilitaet_0064_zusatz.charge_nr,
    v_plausibilitaet_0064_zusatz.sorte,
    v_plausibilitaet_0064_zusatz.start_ts,
    v_plausibilitaet_0064_zusatz.befund,
    v_plausibilitaet_0064_zusatz.rat,
    v_plausibilitaet_0064_zusatz.bezug
   FROM v_plausibilitaet_0064_zusatz;
comment on view v_plausibilitaet_0054_zusatz is 'Zusatzprüfungen zu v_plausibilitaet, die seit 0054 dazugekommen sind — je Auffälligkeit Art, betroffene Arbeit, Befund und Rat. Wird von v_plausibilitaet mitgelesen; einzeln braucht sie niemand. 0128: dazu je Auffälligkeit ihr Bezug.';
grant select on v_plausibilitaet_0054_zusatz to authenticated;

-- ---------- v_ungereimtheit ----------
create or replace view v_ungereimtheit with (security_invoker=true) as
 WITH lief AS (
         SELECT l.charge_nr,
            l.datum,
            l.masse_kg
           FROM v_lieferung_masse l
          WHERE l.charge_nr IS NOT NULL AND l.masse_kg > 0::numeric AND (l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])) AND l.datum <= heute()
        ), eingang AS (
         SELECT palette.charge_nr,
            min(palette.eingangsdatum) AS erst,
            count(*)::integer AS n
           FROM palette
          GROUP BY palette.charge_nr
        )
 SELECT 'ohne_eingang'::text AS art,
    c.nr AS charge_nr,
    c.sorte,
    c.schlag,
    zahl(sum(l.masse_kg), 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    count(*)::integer AS n,
    min(l.datum) AS von,
    max(l.datum) AS bis,
    jsonb_build_object('kandidaten', ungereimt_kandidaten(c.nr, max(l.datum))) AS mehr
   FROM lief l
     JOIN charge c ON c.nr = l.charge_nr
  WHERE NOT (EXISTS ( SELECT 1
           FROM eingang e
          WHERE e.charge_nr = l.charge_nr))
  GROUP BY c.nr, c.sorte, c.schlag
UNION ALL
 SELECT 'vor_eingang'::text AS art,
    c.nr AS charge_nr,
    c.sorte,
    c.schlag,
    zahl(sum(l.masse_kg), 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    count(*)::integer AS n,
    min(l.datum) AS von,
    max(l.datum) AS bis,
    jsonb_build_object('erster_eingang', e.erst, 'kandidaten', ungereimt_kandidaten(c.nr, max(l.datum))) AS mehr
   FROM lief l
     JOIN eingang e ON e.charge_nr = l.charge_nr
     JOIN charge c ON c.nr = l.charge_nr
  WHERE l.datum < e.erst
  GROUP BY c.nr, c.sorte, c.schlag, e.erst
UNION ALL
 SELECT 'ueberzaehlung'::text AS art,
    b.charge_nr,
    b.sorte,
    b.schlag,
    zahl(b.ueberzaehlung_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    b.n_lieferungen AS n,
    NULL::date AS von,
    NULL::date AS bis,
    jsonb_build_object('geliefert_kg', round(b.geliefert_kg), 'eingang_kg', round(b.eingang_kg), 'ausgelagert_kg', round(b.ausgelagert_kg), 'eingang_von', b.eingang_von, 'eingang_bis', b.eingang_bis, 'kandidaten', ungereimt_kandidaten(b.charge_nr, ( SELECT max(l.datum) AS max
           FROM lief l
          WHERE l.charge_nr = b.charge_nr))) AS mehr
   FROM erg_charge b
  WHERE b.ueberzaehlung_kg > GREATEST(100::numeric, 0.03 * b.eingang_kg)
UNION ALL
 SELECT 'ohne_charge'::text AS art,
    NULL::integer AS charge_nr,
    o.sorte,
    NULL::text AS schlag,
    o.kg,
    o.n_lieferungen AS n,
    o.erste AS von,
    o.letzte AS bis,
    jsonb_build_object('kg_vor_eingang', o.kg_vor_eingang, 'kg_ohne_ziel', o.kg_ohne_ziel, 'verteilt_auf', o.verteilt_auf) AS mehr
   FROM v_ohne_charge o
UNION ALL
 SELECT
        CASE z.stand
            WHEN 'angewandt'::text THEN 'umgebucht'::text
            ELSE 'vorschlag'::text
        END AS art,
    z.nach_charge_nr AS charge_nr,
    c.sorte,
    c.schlag,
    zahl(sum(vp.netto_kg), 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    count(*)::integer AS n,
    min(p.eingangsdatum) AS von,
    max(p.eingangsdatum) AS bis,
    jsonb_build_object('von_charge_nr', z.von_charge_nr, 'auftrag_id', z.auftrag_id, 'grund', min(z.grund) FILTER (WHERE z.art = 'zettel'::text), 'paletten', jsonb_agg(z.palette_id ORDER BY z.palette_id), 'von_betriebsleiter', bool_or(z.geaendert_ts IS NOT NULL)) AS mehr
   FROM palette_zuordnung z
     JOIN palette p ON p.id = z.palette_id
     JOIN v_palette vp ON vp.id = z.palette_id
     JOIN charge c ON c.nr = z.nach_charge_nr
  WHERE z.stand = ANY (ARRAY['angewandt'::text, 'vorschlag'::text])
  GROUP BY z.stand, z.nach_charge_nr, z.von_charge_nr, z.auftrag_id, c.sorte, c.schlag
UNION ALL
 SELECT 'nachgeordnet'::text AS art,
    n.charge_nr,
    c.sorte,
    c.schlag,
    zahl(sum(l.masse_kg), 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    count(*)::integer AS n,
    min(l.datum) AS von,
    max(l.datum) AS bis,
    jsonb_build_object('nummern', jsonb_agg(DISTINCT n.nummer), 'produzent', min(n.produzent), 'grund', min(n.grund), 'perigon_nr', c.perigon_nr) AS mehr
   FROM lieferung_nachordnung n
     JOIN v_lieferung_masse l ON l.id = n.lieferung_id
     JOIN charge c ON c.nr = n.charge_nr
  WHERE n.weg = 'produzent'::text AND n.nummer IS DISTINCT FROM c.perigon_nr::text AND n.nummer IS DISTINCT FROM c.nr::text
  GROUP BY n.charge_nr, c.sorte, c.schlag, c.perigon_nr
UNION ALL
 SELECT 'stammdaten'::text AS art,
    s.chargen[1] AS charge_nr,
    c.sorte,
    c.schlag,
    zahl(NULL::numeric, 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    cardinality(s.chargen) AS n,
    NULL::date AS von,
    NULL::date AS bis,
    s.mehr || jsonb_build_object('pruefung', s.pruefung, 'chargen_nr', to_jsonb(s.chargen)) AS mehr
   FROM v_stammdaten_pruefung s
     JOIN charge c ON c.nr = s.chargen[1];
comment on view v_ungereimtheit is 'Was zwischen Perigon, Erntejournal und Lager nicht zusammenpasst, je Charge oder Sorte, mit den Kilo, um die es geht (0121, 0122): ohne_eingang, vor_eingang, ueberzaehlung (mit kandidaten: Chargen, von denen die Ware wohl kam), ohne_charge, umgebucht, vorschlag, nachgeordnet (über den Produzenten zugeordnet), stammdaten (was im Chargenregister nicht stimmt, v_stammdaten_pruefung). Die Zeilen der Perigon-Dateien stehen in v_perigon_pruefung; der Weg der Ware je Charge in v_charge_spur.';
grant select on v_ungereimtheit to authenticated;

-- ---------- v_verlust_je_gruppe ----------
create or replace view v_verlust_je_gruppe with (security_invoker=true) as
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
            h.portion,
            h.f_geliehen,
            h.f_n,
            h.f_se,
            h.strom,
            h.buch,
            h.kg,
            h.basis_kg,
            h.koeff_n,
            h.koeff_basis,
            h.formel,
            h.d_r,
            h.d_f,
            h.d_a,
            h.koeff_art,
            h.koeff_bekannt,
            h.strom = 'Faul beim Abpacken (Fax)'::text AND h.portion = 'lager'::text AS erwartet
           FROM mv_hochrechnung h
             JOIN gruppen g_1 ON g_1.charge_nr = h.charge_nr
          WHERE h.buch = ANY (ARRAY['verlust'::text, 'marge'::text])
        ), unsicherheit AS MATERIALIZED (
         SELECT v_koeff_unsicherheit.art,
            v_koeff_unsicherheit.sorte,
            v_koeff_unsicherheit.b,
            v_koeff_unsicherheit.varianz_eigen,
            v_koeff_unsicherheit.gewicht_gesamt,
            v_koeff_unsicherheit.varianz_gesamt,
            v_koeff_unsicherheit.df
           FROM v_koeff_unsicherheit
        ), eingang AS MATERIALIZED (
         SELECT g_1.gruppe,
            g_1.schluessel,
            sum(b.eingang_kg) AS eingang_kg,
            count(*)::integer AS n_chargen
           FROM gruppen g_1
             JOIN v_kaskade_basis b ON b.charge_nr = g_1.charge_nr
          GROUP BY g_1.gruppe, g_1.schluessel
        ), je_sorte AS MATERIALIZED (
         SELECT zeilen.gruppe,
            zeilen.schluessel,
            zeilen.strom,
            zeilen.buch,
            zeilen.sorte,
            max(zeilen.koeff_art) AS koeff_art,
            sum(zeilen.d_r) AS g_r,
            sum(zeilen.d_a) AS g_a
           FROM zeilen
          WHERE NOT zeilen.erwartet
          GROUP BY zeilen.gruppe, zeilen.schluessel, zeilen.strom, zeilen.buch, zeilen.sorte
        ), je_strom_f AS MATERIALIZED (
         SELECT zeilen.gruppe,
            zeilen.schluessel,
            zeilen.strom,
            zeilen.buch,
            sum(zeilen.d_f * zeilen.f_se) AS g_f,
            min(zeilen.f_n) AS f_n_min
           FROM zeilen
          WHERE NOT zeilen.erwartet
          GROUP BY zeilen.gruppe, zeilen.schluessel, zeilen.strom, zeilen.buch
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
         SELECT je_strom_f.gruppe,
            je_strom_f.schluessel,
            je_strom_f.strom,
            je_strom_f.buch,
            power(je_strom_f.g_f, 2::numeric) AS varianz,
            GREATEST(COALESCE(je_strom_f.f_n_min, 2) - 1, 1) AS df
           FROM je_strom_f
        ), summe AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            sum(z.kg) FILTER (WHERE NOT z.erwartet) AS kg,
            bool_and(z.koeff_bekannt) AS bekannt,
            sum(z.kg) FILTER (WHERE z.portion = 'ausgelagert'::text) AS kg_beobachtet,
            sum(z.kg) FILTER (WHERE z.portion = 'lager'::text AND NOT z.erwartet) AS kg_projiziert,
            sum(z.kg) FILTER (WHERE z.f_geliehen AND NOT z.erwartet) AS kg_extrapoliert,
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
            WHEN s.bekannt THEN zahl(GREATEST(s.kg - g.t * g.streuung, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_unten,
        CASE
            WHEN s.bekannt THEN zahl(s.kg + g.t * g.streuung)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_oben,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_beobachtet, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_beobachtet,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_projiziert, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_projiziert,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_extrapoliert, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_extrapoliert,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_erwartet, 0::numeric))
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
     CROSS JOIN LATERAL ( SELECT sqrt(GREATEST(COALESCE(vr.varianz, 0::numeric) + COALESCE(va.varianz, 0::numeric) + COALESCE(vf.varianz, 0::numeric), 0::numeric)) AS streuung,
            LEAST(COALESCE(vr.df, 999), COALESCE(va.df, 999), COALESCE(vf.df, 999)) AS df) g0
     CROSS JOIN LATERAL ( SELECT g0.streuung,
            g0.df,
            t_quantil_95(g0.df) AS t) g;
comment on view v_verlust_je_gruppe is 'Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, Charge). kg_beobachtet ist gemessen, kg_projiziert auf noch nicht Gemessenes übertragen, kg_extrapoliert seit 0106 mit einem aus allen Sorten geliehenen Palox-Anteil gerechnet — drei verschiedene Sicherheiten, darum drei Spalten. Ist der Strom gemessen (bekannt), sind alle vier Teilbeträge Zahlen und kg_beobachtet + kg_projiziert = kg. Das Band kg_unten/kg_oben kommt aus der Unsicherheit der Koeffizienten, beim Faulen aus dem Band des Stationswerts (f_se).';
grant select on v_verlust_je_gruppe to authenticated;

-- ---------- erg_verlust ----------
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
create unique index if not exists erg_verlust_pk on public.erg_verlust USING btree (gruppe, schluessel, strom);
comment on materialized view erg_verlust is 'v_verlust_je_gruppe, gespeichert für die App (0062). Erneuert mit auswertung_schritt().';
grant select on erg_verlust to authenticated;

-- ---------- v_plausibilitaet ----------
create or replace view v_plausibilitaet with (security_invoker=true) as
 SELECT 'Schimmel'::text AS art,
    b.auftrag_id,
    b.charge_nr,
    b.sorte,
    b.start_ts,
    format('%s kg Schimmel auf %s kg Ware — das wären %s %%'::text, round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100::numeric)) AS befund,
    'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text AS rat,
    (('auftrag:'::text || b.auftrag_id) || ':'::text) || COALESCE(b.station::text, '-'::text) AS bezug
   FROM v_schimmel_beobachtung b
  WHERE b.anteil IS NOT NULL AND NOT b.plausibel AND NOT b.ist_fax AND b.lagertage >= 0::numeric
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
    'Entweder die Palettenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'::text AS rat,
    'auftrag:'::text || f.auftrag_id AS bezug
   FROM v_fax_beobachtung f
  WHERE f.anteil IS NOT NULL AND NOT f.plausibel
UNION ALL
 SELECT 'Ausschuss'::text AS art,
    a.auftrag_id,
    a.charge_nr,
    a.sorte,
    ( SELECT x.start_ts
           FROM auftrag x
          WHERE x.id = a.auftrag_id) AS start_ts,
    format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse'::text, round(COALESCE(a.klein_kg, 0::numeric)), round(COALESCE(a.gross_kg, 0::numeric)), round(a.basis_kg)) AS befund,
    'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'::text AS rat,
    'auftrag:'::text || a.auftrag_id AS bezug
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
        END AS rat,
    'auftrag:'::text || a.id AS bezug
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
    'Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '::text || 'Sonst ist der Stand vertippt.'::text AS rat,
    'schimmel_messung:'::text || s.id AS bezug
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
    'Nichts zu korrigieren. Beim nächsten Mal in der Checkliste „Palox leeren" drücken: vor dem Leeren ablesen, danach die leere Box — dann bleibt die Menge bekannt.'::text AS rat,
    'schimmel_messung:'::text || p.id AS bezug
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
            WHEN w.netto_jetzt_kg = w.netto_damals_kg THEN 'sie hat kein Gramm verloren — sehr wahrscheinlich wurde das Eingangsgewicht kopiert (etwa bei einer sortierten Palette, deren Zettelgewicht es nicht gibt)'::text
            ELSE 'sie ist nicht verwertbar'::text
        END) || ' — sie zählt nicht in die Verdunstungsrate'::text AS befund,
        CASE
            WHEN w.netto_damals_kg IS NULL OR w.netto_jetzt_kg IS NULL THEN 'Unter Stammdaten → Gebinde die Tara nachtragen.'::text
            WHEN w.netto_jetzt_kg > (w.netto_damals_kg * 1.01) THEN 'Gebindeart, Kistenzahl und beide Gewichte prüfen — meist stimmt die Tara nicht oder eine Zahl ist verdreht.'::text
            ELSE 'Eingangsdatum und Gewichte der Wägung prüfen.'::text
        END AS rat,
    'verdunstung_wiegung:'::text || w.id AS bezug
   FROM v_verdunstung_messung w
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
  WHERE NOT w.verwendbar AND NOT w.sichtbar_schimmel AND COALESCE(w.grund, ''::text) !~~ 'zu schnell%'::text AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
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
            ELSE format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber hat noch keine Wasch-Arbeit dieser Sorte ihre fertigen Paletten gewogen — das Kistengewicht ist unbekannt'::text, g.anzahl, g.kaliber_idx + 1)
        END AS befund,
        CASE
            WHEN g.kaliber_idx = '-1'::integer THEN 'Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '::text || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'::text
            ELSE 'Bei der nächsten Wasch-Arbeit dieses Kalibers jede Palette am Anfang der Strasse wiegen (seit 0104 Pflicht in der App) — daraus kennt die App das Kistengewicht des Bandes, rückwirkend für alle Waschgänge dieser Sorte, auch für diesen. Oder die fertigen Paletten wiegen (drei reichen).'::text
        END AS rat,
    (('gebinde:'::text || g.auftrag_id) || ':'::text) || g.kaliber_idx AS bezug
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx <> '-2'::integer
UNION ALL
 SELECT 'Waage'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
        CASE
            WHEN w.netto_kg <= 0::numeric THEN format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — leichter als ihre Kisten und die Palette (Tara %s kg)'::text, ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(ap.kisten::numeric * g.tara_kg_pro_kiste + g.tara_kg_palette, 1))
            ELSE format('Wasch-Palette gewogen: %s kg brutto mit %s Kisten %s — %s kg je Kiste'::text, ap.brutto_gewogen_kg, ap.kisten, ap.gebindeart, round(w.netto_kg / ap.kisten::numeric, 1))
        END AS befund,
    'Waage, Kistenzahl oder Gebinde prüfen und im Korrekturfenster der Arbeit berichtigen — bis dahin rechnet die Masse dieser Palette mit.'::text AS rat,
    'auftrag_palette:'::text || ap.id AS bezug
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = ap.gebindeart
     CROSS JOIN LATERAL ( SELECT ap.brutto_gewogen_kg - ap.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_kg) w
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL AND ap.brutto_gewogen_kg IS NOT NULL AND ap.kisten IS NOT NULL AND ap.kisten > 0 AND g.tara_kg_pro_kiste IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND (w.netto_kg <= 0::numeric OR (w.netto_kg / ap.kisten::numeric) < 4::numeric OR (w.netto_kg / ap.kisten::numeric) > 30::numeric)
UNION ALL
 SELECT 'Kaliber fehlt'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen'::text AS befund,
    'Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '::text || 'Stammdaten → Sortierschemata.'::text AS rat,
    'auftrag:'::text || a.id AS bezug
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
        END, m.brutto_kg, round(n.roh)) AS befund,
    'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '::text || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'::text AS rat,
    'ausschuss_messung:'::text || m.id AS bezug
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
     CROSS JOIN LATERAL ( SELECT m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste -
                CASE
                    WHEN m.mit_palette THEN g.tara_kg_palette
                    ELSE 0::numeric
                END AS roh) n
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND n.roh IS NOT NULL AND m.kg::numeric <> round(n.roh)
UNION ALL
 SELECT 'Ausschuss ohne Tara'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    m.ts AS start_ts,
    format('%s kg %s mit %s kg brutto gespeichert — nachrechnen lässt sich das nicht: %s'::text, m.kg,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'zu klein'::text
            ELSE 'zu gross'::text
        END, m.brutto_kg,
        CASE
            WHEN m.gebindeart IS NULL THEN 'an der Wägung steht keine Gebindeart'::text
            WHEN g.art IS NULL THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN g.tara_kg_pro_kiste IS NULL THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN g.tara_kg_palette IS NULL THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END) AS befund,
    'Die gespeicherten Kilo bleiben, wie sie sind — geprüft werden können sie erst, '::text || 'wenn Gebindeart, Tara und Kistenzahl beisammen sind.'::text AS rat,
    'ausschuss_messung:'::text || m.id AS bezug
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND (m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) IS NULL
UNION ALL
 SELECT 'Zetteldatum'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Zetteldatum %s gezählt, aber an dem Tag kam keine Palette dieser Charge'::text, count(*), to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'::text AS rat,
    (('zetteldatum:'::text || ap.auftrag_id) || ':'::text) || ap.eingangsdatum AS bezug
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
    format('%s Palette(n) mit %s kg vom Zettel gezählt, aber im Wareneingang hat keine Palette dieser Charge dieses Gewicht — %s'::text, count(*), ap.brutto_zettel_kg,
        CASE
            WHEN bool_and(m.masse_quelle = 'gewogen'::text) THEN 'gerechnet wird mit der Wägung der Palette'::text
            WHEN bool_and(m.masse_quelle = 'zettel-kisten'::text) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            WHEN bool_and(m.masse_quelle = ANY (ARRAY['zettel-kisten'::text, 'zettel-kisten-charge'::text, 'gewogen'::text])) THEN 'gerechnet wird mit den gezählten Kisten und der Tara je Kiste der Charge (Zettel − Kisten × Tara je Kiste)'::text
            ELSE 'gerechnet wird mit der mittleren Tara ganzer Paletten der Charge — an der Zählung fehlt die Kistenzahl'::text
        END) AS befund,
    'Gewicht an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang (Erntejournal).'::text AS rat,
    (('zettel:'::text || ap.auftrag_id) || ':'::text) || ap.brutto_zettel_kg AS bezug
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.id = ap.id
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
    'Wareneingang der Charge nachtragen (Erntejournal) — oder die Lieferung gehört zu einer anderen Charge.'::text AS rat,
    'charge:'::text || l.charge_nr AS bezug
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
    v_plausibilitaet_0054_zusatz.rat,
    v_plausibilitaet_0054_zusatz.bezug
   FROM v_plausibilitaet_0054_zusatz
UNION ALL
 SELECT 'Zetteldatum Zukunft'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit Eingangsdatum %s gezählt — das liegt in der Zukunft, sehr wahrscheinlich ein falsches Jahr'::text, count(*), to_char(max(ap.eingangsdatum)::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Datum an der Zählung korrigieren (Jahr prüfen). Die Beobachtung bleibt gespeichert, bis sie berichtigt ist; solange rechnet die Auswertung sie nicht mit.'::text AS rat,
    'auftrag:'::text || ap.auftrag_id AS bezug
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.eingangsdatum > heute() AND a.abgebrochen_ts IS NULL
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts
UNION ALL
 SELECT 'Palettengewicht'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    p.eingangsdatum::timestamp with time zone AS start_ts,
    format('Eine Palette mit %s kg brutto — für eine Palette Kürbisse ist das unmöglich'::text, round(p.brutto_kg)) AS befund,
    'Bruttogewicht im Wareneingang prüfen — sehr wahrscheinlich ein Zahlendreher.'::text AS rat,
    'palette:'::text || p.id AS bezug
   FROM palette p
     JOIN charge c ON c.nr = p.charge_nr
  WHERE p.brutto_kg > 2000::numeric;
comment on view v_plausibilitaet is 'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette. 0066: „Ausschuss-Tara" rechnet nur nach, wo Kistenzahl und hinterlegte Tara da sind; fehlt eine, steht die Lücke als „Ausschuss ohne Tara" daneben. 0087: die Nachrechnung zieht die Palette nur ab, wenn sie mitgewogen wurde, und klemmt nichts auf null. 0114: eine zu schnell leichter gewordene Wägung steht nur als „Verdunstung" da, nicht noch einmal als „Wägung". 0128: bezug — woran die Auffälligkeit hängt (Zettel, Wägung, Ablesung, Charge …); Art und Bezug sind die Kennung des Falls, unter der Nummer und Vermerk stehen. Ausschuss (Hand) trägt den Beginn der Arbeit als Tag.';
grant select on v_plausibilitaet to authenticated;

-- ---------- v_unique_topf ----------
create or replace view v_unique_topf with (security_invoker=true) as
 WITH hagel AS MATERIALIZED (
         SELECT c.nr AS charge_nr,
            c.sorte,
            c.hagel_anteil
           FROM charge c
          WHERE c.hagel_anteil > 0::numeric
        ), eingang AS (
         SELECT sum(b.eingang_kg) AS eingang_kg
           FROM v_kaskade_basis b
             JOIN hagel h ON h.charge_nr = b.charge_nr
        ), raus AS (
         SELECT sum(t.masse_kg) AS geliefert_kg,
            sum(t.masse_kg) FILTER (WHERE t.unique_artikel) AS unique_kg,
            sum(t.masse_kg) FILTER (WHERE t.unique_artikel AND NOT t.hagel_charge) AS unique_fremd_kg,
            count(*) FILTER (WHERE t.unique_artikel AND NOT t.hagel_charge)::integer AS n_unique_fremd,
            string_agg(DISTINCT t.charge_nr::text, ', '::text) FILTER (WHERE t.unique_artikel AND NOT t.hagel_charge) AS fremde_chargen
           FROM v_topf_lieferung t
          WHERE t.datum <= heute()
        ), lager AS (
         SELECT sum(a.eingang_kg) AS im_lager_kg,
            sum(a.verdunstet_kg) AS verdunstet_kg,
            sum(a.faul_kg) AS faul_kg,
            sum(a.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(a.marge_kg) AS marge_kg,
            sum(a.verrechenbar_kg) AS verrechenbar_kg,
            bool_and(a.r_bekannt) AS r_bekannt,
            bool_and(a.f_bekannt) AS f_bekannt,
            count(*) FILTER (WHERE a.verkaufsfaehig_kg IS NULL AND a.eingang_kg > 0::numeric)::integer AS n_unbekannt
           FROM v_lager_ausweis a
             JOIN hagel h ON h.charge_nr = a.charge_nr
        ), ueber AS (
         SELECT sum(k.ueberzaehlung_kg) AS ueberzaehlung_kg
           FROM mv_kaskade k
             JOIN hagel h ON h.charge_nr = k.charge_nr
        )
 SELECT (( SELECT count(*) AS count
           FROM hagel))::integer AS n_chargen,
    ( SELECT array_agg(h.charge_nr ORDER BY h.charge_nr) AS array_agg
           FROM hagel h) AS chargen,
    ( SELECT string_agg(DISTINCT h.sorte, ', '::text ORDER BY h.sorte) AS string_agg
           FROM hagel h) AS sorten,
    zahl(e.eingang_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS eingang_kg,
    zahl(COALESCE(r.geliefert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS geliefert_kg,
    zahl(COALESCE(r.unique_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS davon_unique_kg,
    zahl(COALESCE(r.unique_fremd_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS unique_unter_fremder_charge_kg,
    COALESCE(r.n_unique_fremd, 0) AS n_unique_unter_fremder_charge,
    r.fremde_chargen,
    zahl(l.im_lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS im_lager_kg,
    zahl(l.verdunstet_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstet_kg,
    zahl(l.faul_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS faul_kg,
    zahl(l.verkaufsfaehig_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(l.marge_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS marge_kg,
    zahl(l.verrechenbar_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verrechenbar_kg,
    COALESCE(l.n_unbekannt, 0) AS n_unbekannt,
    zahl(COALESCE(u.ueberzaehlung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ueberzaehlung_kg,
    NULLIF(concat_ws(' '::text,
        CASE
            WHEN COALESCE(u.ueberzaehlung_kg, 0::numeric) > 0::numeric THEN format('Aus dem Ünique-Topf ging %s mehr hinaus, als die Hagel-Chargen nach Verdunstung und Palox hergeben. Hagel bei einer Charge vergessen, oder unter einer Hagel-Charge Ware gebucht, die nicht von ihr war?'::text, kg_wort(u.ueberzaehlung_kg) || ' kg'::text)
            ELSE NULL::text
        END,
        CASE
            WHEN COALESCE(r.n_unique_fremd, 0) > 0 THEN format('%s Ünique-%s unter %s ohne Hagel (%s, %s kg) — der Perigon-Reiter nennt sie.'::text, r.n_unique_fremd,
            CASE
                WHEN r.n_unique_fremd = 1 THEN 'Lieferung'::text
                ELSE 'Lieferungen'::text
            END,
            CASE
                WHEN r.fremde_chargen ~~ '%,%'::text THEN 'Chargen'::text
                ELSE 'Charge'::text
            END, r.fremde_chargen, kg_wort(r.unique_fremd_kg))
            ELSE NULL::text
        END), ''::text) AS hinweis
   FROM eingang e
     CROSS JOIN raus r
     CROSS JOIN lager l
     CROSS JOIN ueber u
  WHERE (EXISTS ( SELECT 1
           FROM hagel));
comment on view v_unique_topf is 'Der Ünique-Topf (0133): alle Chargen mit Hagel zusammen, über alle Sorten — „die werden miteinander verkauft". eingang_kg: was hereinkam; geliefert_kg: was aus dem Topf ging (v_topf_lieferung, davon Ünique-Artikel und Ünique unter einer Charge ohne Hagel); im_lager_kg … verrechenbar_kg: was liegt, Schritt für Schritt wie v_lager_ausweis (Verlust nur Verdunstung, Palox und Marge — Hagelware wird nicht nach Grösse sortiert). ueberzaehlung_kg: mehr hinaus als drin sein kann; hinweis sagt, was zu prüfen ist. Ohne Hagel-Charge keine Zeile.';
grant select on v_unique_topf to authenticated;

-- ---------- v_marge_buch ----------
create or replace view v_marge_buch with (security_invoker=true) as
 WITH verkauf AS (
         SELECT sum(v_ueberfuellung_verkauf.verschenkt_kg) AS verschenkt_kg,
            sum(
                CASE
                    WHEN v_ueberfuellung_verkauf.verschenkt_kg IS NULL THEN NULL::numeric
                    ELSE GREATEST(v_ueberfuellung_verkauf.verschenkt_kg - COALESCE(v_ueberfuellung_verkauf.verschenkt_fehler_kg, 0::numeric), 0::numeric)
                END) AS verschenkt_unten_kg,
            sum(v_ueberfuellung_verkauf.verschenkt_kg + COALESCE(v_ueberfuellung_verkauf.verschenkt_fehler_kg, 0::numeric)) AS verschenkt_oben_kg,
            sum(v_ueberfuellung_verkauf.kisten_verkauft) FILTER (WHERE v_ueberfuellung_verkauf.n_wiegungen > 0) AS kisten_gerechnet,
            sum(v_ueberfuellung_verkauf.kisten_verkauft) FILTER (WHERE v_ueberfuellung_verkauf.n_wiegungen = 0) AS kisten_ungewogen,
            sum(v_ueberfuellung_verkauf.n_wiegungen) AS n_wiegungen,
            sum(v_ueberfuellung_verkauf.kisten_gewogen) AS kisten_gewogen,
            sum(v_ueberfuellung_verkauf.zuviel_je_kiste * v_ueberfuellung_verkauf.kisten_gewogen::numeric) / NULLIF(sum(v_ueberfuellung_verkauf.kisten_gewogen) FILTER (WHERE v_ueberfuellung_verkauf.zuviel_je_kiste IS NOT NULL), 0::numeric) AS zuviel_je_kiste,
            count(*) FILTER (WHERE v_ueberfuellung_verkauf.n_lieferungen > 0)::integer AS n_gruppen_verkauft
           FROM v_ueberfuellung_verkauf
          WHERE v_ueberfuellung_verkauf.gruppe = 'sorte'::text AND v_ueberfuellung_verkauf.kistensystem = 'kiste_ab'::text
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
comment on view v_marge_buch is 'Buch B: Ware, die den Betrieb verlassen hat, ohne verkaufsfähig zu sein — zu klein, Nebenkanal, Überfüllung. Kein Verlust im Sinne von verdorben, sondern Masse in einem anderen Kanal. kg_unten und kg_oben spannen den Bereich auf, gemessen sagt, ob dahinter Messungen oder Schätzungen stehen.';
grant select on v_marge_buch to authenticated;

-- ---------- v_saisonbilanz ----------
create or replace view v_saisonbilanz with (security_invoker=true) as
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
            sum(erg_charge.fax_heute_kg) AS fax_heute_kg,
            sum(erg_charge.fax_erwartet_kg) AS fax_erwartet_kg,
            sum(erg_charge.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            bool_and(erg_charge.verlust_bekannt) AS bekannt,
            count(*)::integer AS n_chargen,
            max(erg_charge.heute) AS heute
           FROM erg_charge
        ), bereich AS (
         SELECT sum(erg_verlust.kg_unten) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_unten_kg,
            sum(erg_verlust.kg_oben) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_oben_kg,
            sum(erg_verlust.kg) FILTER (WHERE erg_verlust.buch = 'verlust'::text) AS verlust_kg,
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
            ELSE format((('Bis heute (%s): %s t Eingang = %s t ausgeliefert + %s t Verlust '::text || '(Verdunstung %s t, Faules %s t, Fax %s t) '::text) || '+ %s t noch im Haus (davon %s t verkaufsfähig, %s t zu klein oder zu gross — aussortiert oder im Liegenden erwartet). Die Prognose bis zum '::text) || 'Saisonende steht in der Grafik, nicht in diesen Zahlen.%s'::text, to_char(c.heute::timestamp with time zone, 'DD.MM.YYYY'::text), round(c.eingang_kg / 1000.0, 1), round(c.geliefert_kg / 1000.0, 1), round(c.verlust_heute_kg / 1000.0, 1), round(c.verdunstung_heute_kg / 1000.0, 1), round(c.schimmel_heute_kg / 1000.0, 1), round(c.fax_heute_kg / 1000.0, 1), round(c.im_haus_heute_kg / 1000.0, 1), round(c.verkaufsfaehig_heute_kg / 1000.0, 1), round((c.kanal_ausgelagert_kg + c.kanal_im_haus_kg) / 1000.0, 1), concat_ws(' '::text, '',
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
comment on view v_saisonbilanz is 'Die Saison bis heute in einer Zeile (erg_bilanz). Seit 0101: Eingang + Überzählung = ausgeliefert (Lieferscheine) + Verlust bis heute + im Haus — zu klein und zu gross sind Teil von im Haus (kanal_ausgelagert_kg aussortiert, kanal_im_haus_kg im Liegenden erwartet), nicht Ausgang. Seit 0106 ohne Sockel.';
grant select on v_saisonbilanz to authenticated;

-- ---------- v_wohin ----------
create or replace view v_wohin with (security_invoker=true) as
 WITH gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'sorte'::text AS text,
            erg_charge.sorte,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'schlag'::text AS text,
            erg_charge.schlag,
            erg_charge.charge_nr
           FROM erg_charge
        UNION ALL
         SELECT 'charge'::text AS text,
            erg_charge.charge_nr::text AS charge_nr,
            erg_charge.charge_nr
           FROM erg_charge
        ), charge AS (
         SELECT g.gruppe,
            g.schluessel,
            count(*)::integer AS n_chargen,
            sum(c_1.eingang_kg) AS eingang_kg,
            sum(c_1.ueberzaehlung_kg) AS ueberzaehlung_kg,
            sum(c_1.geliefert_kg) AS geliefert_kg,
            sum(c_1.kanal_ausgelagert_kg) AS kanal_ausgelagert_kg,
            sum(c_1.fax_heute_kg) AS fax_kg,
            sum(c_1.im_haus_heute_kg) AS lager_gute_ware_kg,
            sum(c_1.verkaufsfaehig_lager_kg) AS lager_verkaufsfaehig_kg,
            sum(c_1.kanal_im_haus_kg) AS lager_kanal_kg,
            sum(c_1.fax_erwartet_kg) AS lager_fax_kg,
            sum(c_1.lager_kg) AS lager_kg,
            bool_and(c_1.verlust_bekannt) AS vollstaendig
           FROM gruppen g
             JOIN erg_charge c_1 ON c_1.charge_nr = g.charge_nr
          GROUP BY g.gruppe, g.schluessel
        ), stroeme AS (
         SELECT erg_verlust.gruppe,
            erg_verlust.schluessel,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Verdunstung'::text) AS verdunstet_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Verdunstung'::text) AS lager_verdunstet_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Schimmel/Fäulnis'::text) AS faul_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Schimmel/Fäulnis'::text) AS lager_faul_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Zu klein (Tierfutter)'::text) AS klein_ausgelagert_kg,
            sum(erg_verlust.kg_beobachtet) FILTER (WHERE erg_verlust.strom = 'Nebenkanal zu gross'::text) AS gross_ausgelagert_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Zu klein (Tierfutter)'::text) AS lager_klein_kg,
            sum(erg_verlust.kg_projiziert) FILTER (WHERE erg_verlust.strom = 'Nebenkanal zu gross'::text) AS lager_gross_kg
           FROM erg_verlust
          GROUP BY erg_verlust.gruppe, erg_verlust.schluessel
        )
 SELECT c.gruppe,
    c.schluessel,
    c.n_chargen,
    zahl(c.eingang_kg)::numeric(14,2) AS eingang_kg,
    zahl(c.ueberzaehlung_kg)::numeric(14,2) AS ueberzaehlung_kg,
    zahl(c.geliefert_kg)::numeric(14,2) AS geliefert_kg,
    zahl(c.kanal_ausgelagert_kg)::numeric(14,2) AS kanal_ausgelagert_kg,
    zahl(s.klein_ausgelagert_kg)::numeric(14,2) AS klein_ausgelagert_kg,
    zahl(s.gross_ausgelagert_kg)::numeric(14,2) AS gross_ausgelagert_kg,
    zahl(s.verdunstet_ausgelagert_kg)::numeric(14,2) AS verdunstet_ausgelagert_kg,
    zahl(s.faul_ausgelagert_kg)::numeric(14,2) AS faul_ausgelagert_kg,
    zahl(c.fax_kg)::numeric(14,2) AS fax_kg,
    zahl(c.lager_kg)::numeric(14,2) AS lager_kg,
    zahl(c.lager_gute_ware_kg)::numeric(14,2) AS lager_gute_ware_kg,
    zahl(c.lager_verkaufsfaehig_kg)::numeric(14,2) AS lager_verkaufsfaehig_kg,
    zahl(c.lager_kanal_kg)::numeric(14,2) AS lager_kanal_kg,
    zahl(s.lager_klein_kg)::numeric(14,2) AS lager_klein_kg,
    zahl(s.lager_gross_kg)::numeric(14,2) AS lager_gross_kg,
    zahl(c.lager_fax_kg)::numeric(14,2) AS lager_fax_kg,
    zahl(s.lager_faul_kg)::numeric(14,2) AS lager_faul_kg,
    zahl(s.lager_verdunstet_kg)::numeric(14,2) AS lager_verdunstet_kg,
    zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.kanal_ausgelagert_kg - s.verdunstet_ausgelagert_kg - s.faul_ausgelagert_kg - c.fax_kg - c.lager_kg)::numeric(14,2) AS rest_kg,
    zahl(c.lager_kg - c.lager_verkaufsfaehig_kg - c.lager_kanal_kg - c.lager_fax_kg - s.lager_faul_kg - s.lager_verdunstet_kg)::numeric(14,2) AS lager_rest_kg,
    c.vollstaendig
   FROM charge c
     LEFT JOIN stroeme s ON s.gruppe = c.gruppe AND s.schluessel = c.schluessel;
comment on view v_wohin is 'Wohin ging der Kürbis — je Gruppe (gesamt, Sorte, Schlag, Charge) der ganze Eingang aufgeteilt: ausgeliefert, anderer Kanal, verdunstet und faul an der ausgelieferten Ware, Faules beim Abpacken, und was noch liegt (davon verkaufsfähig, Kanal, Fax erwartet, faul, verdunstet). rest_kg und lager_rest_kg sind die zwei Identitäten: beide haben den Erwartungswert null, und eine doppelt gezählte Portion bliebe darin stehen. Seit 0106 ohne Sockel.';
grant select on v_wohin to authenticated;

-- ---------- erg_wohin ----------
create materialized view erg_wohin as
 SELECT gruppe,
    schluessel,
    n_chargen,
    eingang_kg,
    ueberzaehlung_kg,
    geliefert_kg,
    kanal_ausgelagert_kg,
    klein_ausgelagert_kg,
    gross_ausgelagert_kg,
    verdunstet_ausgelagert_kg,
    faul_ausgelagert_kg,
    fax_kg,
    lager_kg,
    lager_gute_ware_kg,
    lager_verkaufsfaehig_kg,
    lager_kanal_kg,
    lager_klein_kg,
    lager_gross_kg,
    lager_fax_kg,
    lager_faul_kg,
    lager_verdunstet_kg,
    rest_kg,
    lager_rest_kg,
    vollstaendig
   FROM v_wohin
with no data;
create unique index if not exists erg_wohin_pk on public.erg_wohin USING btree (gruppe, schluessel);
comment on materialized view erg_wohin is 'v_wohin, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';
grant select on erg_wohin to authenticated;

-- ---------- erg_bilanz, erg_marge, erg_massenbilanz, erg_naechste_charge, erg_plausibilitaet ----------
-- wie 0116: die gespeicherten Fassungen aus der Schleife (select * aus ihrer Sicht)
-- verdichter: baut erg_bilanz erg_marge erg_massenbilanz erg_naechste_charge erg_plausibilitaet
do $$
declare
  paar text[];
  paare text[][] := array[
    ['erg_bilanz', 'v_saisonbilanz'],
    ['erg_marge', 'v_marge_buch'],
    ['erg_massenbilanz', 'v_massenbilanz'],
    ['erg_naechste_charge', 'v_naechste_charge'],
    ['erg_plausibilitaet', 'v_plausibilitaet']
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

-- ---------- v_charge_bedarf ----------
-- Je Charge: wie viel Eingang die Lieferungen brauchen. bedarf_kg ist, was die
-- Kaskade zurückrechnet (Σ m0 der Lieferungen); bedarf_min_kg mit den
-- günstigsten Raten der Spanne (Verdunstung unten, Palox unten), bedarf_max_kg
-- mit den ungünstigsten. Zu klein, zu gross und Fax gehen mit ihrem Wert ein —
-- für sie kennt die App keine Spanne. Die Untergrenze 25 % verkaufsfähig der
-- Kaskade gilt auch hier.
create or replace view v_charge_bedarf with (security_invoker = true) as
with zeilen as (
  select k.charge_nr, k.portion, k.geliefert_kg, k.m0, k.alter_tage, k.f, k.f_unten, k.f_oben,
         k.a_klein_n, k.a_gross_n, k.a_fax,
         least(greatest(coalesce(kv.unten, kv.mittel, 0), 0), 0.05) as r_unten,
         least(greatest(coalesce(kv.oben, kv.mittel, 0), 0), 0.05) as r_oben
    from mv_kaskade k
    left join v_koeff_verdunstung kv on kv.sorte = k.sorte
   where k.portion in ('ausgelagert', 'entsorgt') and k.geliefert_kg > 0
), je as (
  select z.charge_nr,
         sum(z.m0) as bedarf_kg,
         sum(z.geliefert_kg / case when z.portion = 'entsorgt' then greatest(power(1 - z.r_unten, z.alter_tage), 0.25)
               else greatest(power(1 - z.r_unten, z.alter_tage) * (1 - z.f_unten) * (1 - z.a_klein_n - z.a_gross_n) * (1 - z.a_fax), 0.25) end) as bedarf_min_kg,
         sum(z.geliefert_kg / case when z.portion = 'entsorgt' then greatest(power(1 - z.r_oben, z.alter_tage), 0.25)
               else greatest(power(1 - z.r_oben, z.alter_tage) * (1 - z.f_oben) * (1 - z.a_klein_n - z.a_gross_n) * (1 - z.a_fax), 0.25) end) as bedarf_max_kg,
         sum(z.m0 * z.f) filter (where z.portion = 'ausgelagert') / nullif(sum(z.m0) filter (where z.portion = 'ausgelagert'), 0) as f,
         sum(z.m0 * z.f_unten) filter (where z.portion = 'ausgelagert') / nullif(sum(z.m0) filter (where z.portion = 'ausgelagert'), 0) as f_unten,
         sum(z.m0 * z.f_oben) filter (where z.portion = 'ausgelagert') / nullif(sum(z.m0) filter (where z.portion = 'ausgelagert'), 0) as f_oben
    from zeilen z
   group by z.charge_nr
), nach as (
  -- Lieferscheine dieser Nummer nach dem Tag, an dem die Charge leer war
  select l.charge_nr, count(*)::int as n, sum(l.masse_kg) as kg, min(l.datum) as erste
    from v_lieferung_masse l
    join charge c on c.nr = l.charge_nr
   where c.leer_am is not null and l.datum > c.leer_am and l.masse_kg > 0
   group by l.charge_nr
), basis as (
  select c.nr as charge_nr, c.sorte, c.schlag, e.eingang_kg, e.geliefert_kg, e.n_lieferungen,
         j.bedarf_kg, j.bedarf_min_kg, j.bedarf_max_kg, e.ueberzaehlung_kg,
         coalesce(c.hagel_anteil, 0) > 0 as hagel,
         kv.mittel as r, kv.unten as r_unten, kv.oben as r_oben, kv.basis as r_basis,
         j.f, j.f_unten, j.f_oben,
         c.leer_am, c.leer_am is not null and c.leer_am <= heute() as leer,
         n.n as n_nach_leer, n.kg as kg_nach_leer, n.erste as erste_nach_leer
    from charge c
    join erg_charge e on e.charge_nr = c.nr
    left join je j on j.charge_nr = c.nr
    left join v_koeff_verdunstung kv on kv.sorte = c.sorte
    left join nach n on n.charge_nr = c.nr
), art as (
  select b.*,
         case
           when b.hagel then null
           when b.geliefert_kg > b.eingang_kg then 'datenfehler'
           when b.bedarf_min_kg > b.eingang_kg then 'rate'
           when b.ueberzaehlung_kg > 0 or b.bedarf_kg > b.eingang_kg then 'spanne'
         end as art
    from basis b
)
select a.charge_nr, a.sorte, a.schlag, a.eingang_kg, a.geliefert_kg, a.n_lieferungen,
       zahl(a.bedarf_kg, 2, 1000000000000)::numeric(14,2) as bedarf_kg,
       zahl(a.bedarf_min_kg, 2, 1000000000000)::numeric(14,2) as bedarf_min_kg,
       zahl(a.bedarf_max_kg, 2, 1000000000000)::numeric(14,2) as bedarf_max_kg,
       a.ueberzaehlung_kg, a.hagel,
       round(a.r::numeric, 6) as r, round(a.r_unten::numeric, 6) as r_unten, round(a.r_oben::numeric, 6) as r_oben, a.r_basis,
       round(a.f::numeric, 4) as f, round(a.f_unten::numeric, 4) as f_unten, round(a.f_oben::numeric, 4) as f_oben,
       a.art,
       zahl(case a.art
              when 'datenfehler' then a.geliefert_kg - a.eingang_kg
              when 'rate' then a.bedarf_kg - a.eingang_kg
              when 'spanne' then greatest(a.bedarf_kg - a.eingang_kg, a.ueberzaehlung_kg, 0)
            end, 2, 1000000000000)::numeric(14,2) as ueber_kg,
       -- gemeldet wird ab 100 kg und 3 % des Eingangs, wie bisher die Überzählung (0121)
       coalesce(a.art in ('datenfehler', 'rate')
                and case a.art when 'datenfehler' then a.geliefert_kg - a.eingang_kg else a.bedarf_kg - a.eingang_kg end
                    > greatest(100, 0.03 * a.eingang_kg), false) as melden,
       a.leer_am, a.leer,
       case when a.leer then zahl(a.eingang_kg - a.geliefert_kg, 2, 1000000000000)::numeric(14,2) end as echt_verlust_kg,
       case when a.leer then zahl(1 - a.geliefert_kg / nullif(a.eingang_kg, 0), 4, 1000)::numeric(8,4) end as echt_anteil,
       case when a.leer and not a.hagel then zahl(1 - a.geliefert_kg / nullif(a.bedarf_kg, 0), 4, 1000)::numeric(8,4) end as gerechnet_anteil,
       case when a.leer and not a.hagel then zahl(1 - a.geliefert_kg / nullif(a.bedarf_min_kg, 0), 4, 1000)::numeric(8,4) end as gerechnet_unten,
       case when a.leer and not a.hagel then zahl(1 - a.geliefert_kg / nullif(a.bedarf_max_kg, 0), 4, 1000)::numeric(8,4) end as gerechnet_oben,
       case
         when not a.leer then null
         when a.hagel then 'hagel'
         when coalesce(a.geliefert_kg, 0) <= 0 or a.bedarf_kg is null then 'ohne_lieferung'
         when a.geliefert_kg > a.eingang_kg then 'datenfehler'
         when a.eingang_kg > a.bedarf_max_kg then 'mehr_weg'
         when a.eingang_kg < a.bedarf_min_kg then 'weniger_weg'
         else 'passt'
       end as urteil,
       -- was die Raten noch im Lager erwarteten und nun weg ist: je Eingangstag Eingang − Bedarf, wo positiv
       case when a.leer then zahl(greatest(a.eingang_kg - coalesce(a.bedarf_kg, 0) + coalesce(a.ueberzaehlung_kg, 0), 0), 2, 1000000000000)::numeric(14,2) end as weg_kg,
       coalesce(a.n_nach_leer, 0) as n_nach_leer,
       zahl(a.kg_nach_leer, 2, 1000000000000)::numeric(14,2) as kg_nach_leer,
       a.erste_nach_leer
  from art a;
comment on view v_charge_bedarf is
  'Je Charge (0134): wie viel Eingang ihre Lieferungen brauchen — mit den Raten (bedarf_kg, Σ m0 der Kaskade), mit den günstigsten der Spanne (bedarf_min_kg: Verdunstung und Palox unten) und den ungünstigsten (bedarf_max_kg); zu klein, zu gross und Fax mit ihrem Wert. art: datenfehler (mehr geliefert als hereinkam — keine Rate erklärt das), rate (auch günstig gerechnet braucht es mehr Eingang, als hereinkam — die Raten passen nicht zur Charge), spanne (nur mit den Raten zu viel, innerhalb der Spanne nicht — wird nicht gemeldet), leer (null) wenn es aufgeht; Hagel-Chargen ohne Art (der Ünique-Topf sagt es, v_unique_topf). melden: datenfehler oder rate ab 100 kg und 3 % des Eingangs. Ist die Charge am Lager leer bestätigt (charge.leer_am): echt_verlust_kg = Eingang − geliefert, echt_anteil gegen gerechnet_anteil (1 − geliefert ÷ Bedarf) mit seiner Spanne; urteil passt, mehr_weg (mehr verloren, als die Raten sagen — oder Ware ging ohne Lieferschein), weniger_weg, datenfehler, ohne_lieferung, hagel; weg_kg ist, was die Raten noch im Lager erwarteten; n_nach_leer die Lieferscheine nach dem Leer-Tag.';
grant select on v_charge_bedarf to authenticated;

-- ---------- v_am_lager ----------
-- Je Eingangstag: was laut App noch liegt — in Kilo beim Eingang und in Paletten
-- dieses Tages (die Paletten des Tages mal den Anteil, der noch liegt).
create or replace view v_am_lager with (security_invoker = true) as
select k.charge_nr, k.kohorte as eingangsdatum, ko.n_paletten, ko.eingang_kg,
       zahl(k.m0, 2, 1000000000000)::numeric(14,2) as liegt_kg,
       zahl(ko.n_paletten * k.m0 / nullif(ko.eingang_kg, 0), 1, 1000000)::numeric(7,1) as liegt_paletten
  from mv_kaskade k
  join v_charge_kohorte ko on ko.charge_nr = k.charge_nr and ko.eingangsdatum = k.kohorte
 where k.portion = 'lager' and k.m0 > 0;
comment on view v_am_lager is
  'Je Charge und Eingangstag, was laut App noch im Lager liegt (0134): liegt_kg ist das Eingangsgewicht (m0 der Lagerzeile der Kaskade), liegt_paletten die Paletten dieses Tages mal den Anteil, der noch liegt — gerechnet, eine Zahl zum Vergleichen beim Zählen am Lager.';
grant select on v_am_lager to authenticated;

-- ---------- v_ungereimtheit: die Überzählung sagt, welche sie ist ----------
create or replace view v_ungereimtheit with (security_invoker=true) as
 WITH lief AS (
         SELECT l.charge_nr,
            l.datum,
            l.masse_kg
           FROM v_lieferung_masse l
          WHERE l.charge_nr IS NOT NULL AND l.masse_kg > 0::numeric AND (l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])) AND l.datum <= heute()
        ), eingang AS (
         SELECT palette.charge_nr,
            min(palette.eingangsdatum) AS erst,
            count(*)::integer AS n
           FROM palette
          GROUP BY palette.charge_nr
        )
 SELECT 'ohne_eingang'::text AS art,
    c.nr AS charge_nr,
    c.sorte,
    c.schlag,
    zahl(sum(l.masse_kg), 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    count(*)::integer AS n,
    min(l.datum) AS von,
    max(l.datum) AS bis,
    jsonb_build_object('kandidaten', ungereimt_kandidaten(c.nr, max(l.datum))) AS mehr
   FROM lief l
     JOIN charge c ON c.nr = l.charge_nr
  WHERE NOT (EXISTS ( SELECT 1
           FROM eingang e
          WHERE e.charge_nr = l.charge_nr))
  GROUP BY c.nr, c.sorte, c.schlag
UNION ALL
 SELECT 'vor_eingang'::text AS art,
    c.nr AS charge_nr,
    c.sorte,
    c.schlag,
    zahl(sum(l.masse_kg), 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    count(*)::integer AS n,
    min(l.datum) AS von,
    max(l.datum) AS bis,
    jsonb_build_object('erster_eingang', e.erst, 'kandidaten', ungereimt_kandidaten(c.nr, max(l.datum))) AS mehr
   FROM lief l
     JOIN eingang e ON e.charge_nr = l.charge_nr
     JOIN charge c ON c.nr = l.charge_nr
  WHERE l.datum < e.erst
  GROUP BY c.nr, c.sorte, c.schlag, e.erst
UNION ALL
 SELECT 'ueberzaehlung'::text AS art,
    b.charge_nr,
    b.sorte,
    b.schlag,
    u.ueber_kg AS kg,
    b.n_lieferungen AS n,
    NULL::date AS von,
    NULL::date AS bis,
    jsonb_build_object('art', u.art, 'geliefert_kg', round(b.geliefert_kg), 'eingang_kg', round(b.eingang_kg), 'ausgelagert_kg', round(b.ausgelagert_kg),
      'bedarf_kg', round(u.bedarf_kg), 'bedarf_min_kg', round(u.bedarf_min_kg), 'bedarf_max_kg', round(u.bedarf_max_kg),
      'r', u.r, 'r_unten', u.r_unten, 'f', round(u.f, 4), 'f_unten', round(u.f_unten, 4), 'leer_am', u.leer_am,
      'eingang_von', b.eingang_von, 'eingang_bis', b.eingang_bis, 'kandidaten', ungereimt_kandidaten(b.charge_nr, ( SELECT max(l.datum) AS max
           FROM lief l
          WHERE l.charge_nr = b.charge_nr))) AS mehr
   FROM erg_charge b
     JOIN v_charge_bedarf u ON u.charge_nr = b.charge_nr
  WHERE u.melden
UNION ALL
 SELECT 'ohne_charge'::text AS art,
    NULL::integer AS charge_nr,
    o.sorte,
    NULL::text AS schlag,
    o.kg,
    o.n_lieferungen AS n,
    o.erste AS von,
    o.letzte AS bis,
    jsonb_build_object('kg_vor_eingang', o.kg_vor_eingang, 'kg_ohne_ziel', o.kg_ohne_ziel, 'verteilt_auf', o.verteilt_auf) AS mehr
   FROM v_ohne_charge o
UNION ALL
 SELECT
        CASE z.stand
            WHEN 'angewandt'::text THEN 'umgebucht'::text
            ELSE 'vorschlag'::text
        END AS art,
    z.nach_charge_nr AS charge_nr,
    c.sorte,
    c.schlag,
    zahl(sum(vp.netto_kg), 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    count(*)::integer AS n,
    min(p.eingangsdatum) AS von,
    max(p.eingangsdatum) AS bis,
    jsonb_build_object('von_charge_nr', z.von_charge_nr, 'auftrag_id', z.auftrag_id, 'grund', min(z.grund) FILTER (WHERE z.art = 'zettel'::text), 'paletten', jsonb_agg(z.palette_id ORDER BY z.palette_id), 'von_betriebsleiter', bool_or(z.geaendert_ts IS NOT NULL)) AS mehr
   FROM palette_zuordnung z
     JOIN palette p ON p.id = z.palette_id
     JOIN v_palette vp ON vp.id = z.palette_id
     JOIN charge c ON c.nr = z.nach_charge_nr
  WHERE z.stand = ANY (ARRAY['angewandt'::text, 'vorschlag'::text])
  GROUP BY z.stand, z.nach_charge_nr, z.von_charge_nr, z.auftrag_id, c.sorte, c.schlag
UNION ALL
 SELECT 'nachgeordnet'::text AS art,
    n.charge_nr,
    c.sorte,
    c.schlag,
    zahl(sum(l.masse_kg), 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    count(*)::integer AS n,
    min(l.datum) AS von,
    max(l.datum) AS bis,
    jsonb_build_object('nummern', jsonb_agg(DISTINCT n.nummer), 'produzent', min(n.produzent), 'grund', min(n.grund), 'perigon_nr', c.perigon_nr) AS mehr
   FROM lieferung_nachordnung n
     JOIN v_lieferung_masse l ON l.id = n.lieferung_id
     JOIN charge c ON c.nr = n.charge_nr
  WHERE n.weg = 'produzent'::text AND n.nummer IS DISTINCT FROM c.perigon_nr::text AND n.nummer IS DISTINCT FROM c.nr::text
  GROUP BY n.charge_nr, c.sorte, c.schlag, c.perigon_nr
UNION ALL
 SELECT 'stammdaten'::text AS art,
    s.chargen[1] AS charge_nr,
    c.sorte,
    c.schlag,
    zahl(NULL::numeric, 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    cardinality(s.chargen) AS n,
    NULL::date AS von,
    NULL::date AS bis,
    s.mehr || jsonb_build_object('pruefung', s.pruefung, 'chargen_nr', to_jsonb(s.chargen)) AS mehr
   FROM v_stammdaten_pruefung s
     JOIN charge c ON c.nr = s.chargen[1];
comment on view v_ungereimtheit is 'Was zwischen Perigon, Erntejournal und Lager nicht zusammenpasst, je Charge oder Sorte, mit den Kilo, um die es geht (0121, 0122): ohne_eingang, vor_eingang, ueberzaehlung (mit kandidaten: Chargen, von denen die Ware wohl kam), ohne_charge, umgebucht, vorschlag, nachgeordnet (über den Produzenten zugeordnet), stammdaten (was im Chargenregister nicht stimmt, v_stammdaten_pruefung). Die Zeilen der Perigon-Dateien stehen in v_perigon_pruefung; der Weg der Ware je Charge in v_charge_spur. Seit 0134 ist ueberzaehlung zweierlei (mehr.art, v_charge_bedarf): datenfehler — mehr geliefert als hereinkam, kg ist der Überschuss —, oder rate — auch mit den günstigsten Raten der Spanne braucht es mehr Eingang, als hereinkam, kg ist Bedarf − Eingang; ab 100 kg und 3 % des Eingangs. Was nur mit den Raten, nicht innerhalb ihrer Spanne zu viel ist, steht nicht mehr hier.';
grant select on v_ungereimtheit to authenticated;

-- ---------- v_plausibilitaet_0064_zusatz: ebenso ----------
create or replace view v_plausibilitaet_0064_zusatz with (security_invoker=true) as
 SELECT 'Tara fehlt'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    min(p.eingangsdatum)::timestamp with time zone AS start_ts,
    format('%s von %s Paletten der Charge haben kein Nettogewicht (%s kg brutto): %s. %s'::text, count(*), r.n_paletten, round(sum(p.brutto_kg)),
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'die Gebindeart steht nicht auf der Palette'::text
            WHEN bool_or(g.art IS NULL) THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN bool_or(g.tara_kg_pro_kiste IS NULL) THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN bool_or(g.tara_kg_palette IS NULL) THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END,
        CASE
            WHEN r.n_paletten_mit_netto = 0 THEN 'Damit hat die Charge gar keinen Eingang — sie fehlt in der ganzen Bilanz.'::text
            ELSE format('Für sie rechnet der Eingang mit dem Mittel der übrigen: %s der %s kg '::text || 'Eingang sind hochgerechnet, nicht gewogen.'::text, round(r.eingang_netto_kg - r.eingang_netto_gemessen_kg), round(r.eingang_netto_kg))
        END) AS befund,
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'Gebindeart am Wareneingang nachtragen.'::text
            WHEN bool_or(g.art IS NULL) OR bool_or(g.tara_kg_pro_kiste IS NULL) OR bool_or(g.tara_kg_palette IS NULL) THEN 'Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. '::text || 'Die Zahlen rechnen sich danach von selbst neu.'::text
            ELSE 'Kistenzahl der Palette im Wareneingang nachtragen.'::text
        END AS rat,
    'charge:'::text || p.charge_nr AS bezug
   FROM palette p
     LEFT JOIN gebinde g ON g.art = p.gebindeart
     JOIN charge c ON c.nr = p.charge_nr
     JOIN v_charge_rueckgrat r ON r.charge_nr = p.charge_nr
  WHERE (p.brutto_kg - p.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) IS NULL
  GROUP BY p.charge_nr, c.sorte, r.n_paletten, r.n_paletten_mit_netto, r.eingang_netto_kg, r.eingang_netto_gemessen_kg
UNION ALL
 SELECT 'Überzählung'::text AS art,
    NULL::bigint AS auftrag_id,
    h.charge_nr,
    h.sorte,
    h.eingangsdatum_mittel::timestamp with time zone AS start_ts,
        CASE u.art
            WHEN 'datenfehler'::text THEN format('Unter dieser Charge gingen %s kg hinaus, hereingekommen sind %s kg — %s kg mehr, als je da war. Das erklärt keine Rate: sicher ein Datenfehler.'::text, round(u.geliefert_kg), round(u.eingang_kg), round(u.geliefert_kg - u.eingang_kg))
            ELSE format('Die Lieferungen dieser Charge (%s kg) brauchen mit den gerechneten Raten %s kg Eingang, auch mit den günstigsten der Spanne noch %s kg — hereingekommen sind %s kg. Geliefert wurde nicht mehr als eingelagert, aber mehr, als die Raten aus diesem Eingang erlauben: die Raten passen nicht zur Charge.'::text, round(u.geliefert_kg), round(u.bedarf_kg), round(u.bedarf_min_kg), round(u.eingang_kg))
        END AS befund,
        CASE u.art
            WHEN 'datenfehler'::text THEN 'Zwei Möglichkeiten: Im Erntejournal fehlt eine Palette dieser Charge, oder ein Lieferschein ist auf die falsche Chargennummer gebucht. Beides lässt sich nachtragen.'::text
            ELSE format('Drei Möglichkeiten: Die Charge verliert weniger als ihre Sorte (gerechnet %s, %s); im Erntejournal fehlt eine Palette; oder ein Lieferschein gehört einer anderen Charge. Ist die Charge am Lager leer, im Reiter Chargen „Charge ist leer" drücken — dann misst die App ihren echten Verlust.'::text,
                CASE WHEN u.r IS NULL THEN 'ohne gemessene Verdunstung'::text ELSE format('Verdunstung %s %% je Tag'::text, round(100::numeric * u.r, 2)) END,
                CASE WHEN u.f IS NULL THEN 'ohne Palox-Rate'::text ELSE format('Palox %s %%'::text, round(100::numeric * u.f)) END)
        END AS rat,
    'charge:'::text || h.charge_nr AS bezug
   FROM v_hochrechnung_basis h
     JOIN v_charge_bedarf u ON u.charge_nr = h.charge_nr
  WHERE u.art = ANY (ARRAY['datenfehler'::text, 'rate'::text])
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — %s, nicht mit der Palette selbst.'::text, count(*), ap.brutto_zettel_kg, to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text),
        CASE
            WHEN bool_and(m.masse_quelle = 'gewogen'::text) THEN 'gerechnet wird mit der Wägung der Palette'::text
            WHEN bool_and(m.masse_quelle = 'zettel-kisten'::text) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            WHEN bool_and(m.masse_quelle = ANY (ARRAY['zettel-kisten'::text, 'zettel-kisten-charge'::text, 'gewogen'::text])) THEN 'gerechnet wird mit den gezählten Kisten und der Tara je Kiste der Charge (Zettel − Kisten × Tara je Kiste)'::text
            ELSE 'gerechnet wird mit der mittleren Tara ganzer Paletten der Charge — an der Zählung fehlt die Kistenzahl'::text
        END) AS befund,
    'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'::text AS rat,
    (((('zettel:'::text || ap.auftrag_id) || ':'::text) || ap.brutto_zettel_kg) || ':'::text) || ap.eingangsdatum AS bezug
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.id = ap.id
  WHERE ap.brutto_zettel_kg IS NOT NULL AND ap.eingangsdatum IS NOT NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg)) AND NOT (EXISTS ( SELECT 1
           FROM v_palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg AND p.eingangsdatum = ap.eingangsdatum AND p.netto_kg IS NOT NULL))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg, ap.eingangsdatum
UNION ALL
 SELECT 'Palette fraglich'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s: %s kg brutto in %s Kiste(n) %s, mit Palette gewogen — davon bleiben %s kg netto. Eine leere Palette wiegt allein %s kg.'::text,
        CASE m.art
            WHEN 'zu_klein'::ausschuss_art THEN 'Zu klein'::text
            ELSE 'Zu gross'::text
        END, m.brutto_kg, m.kisten, m.gebindeart, m.kg, g.tara_kg_palette) AS befund,
    'Standen die Kisten direkt auf der Waage? Dann in der Korrektur „mit Palette" abwählen — das Netto rechnet sich von selbst neu.'::text AS rat,
    'ausschuss_messung:'::text || m.id AS bezug
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.gemessen AND m.mit_palette AND m.brutto_kg IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND m.brutto_kg < (2::numeric * g.tara_kg_palette) AND a.abgebrochen_ts IS NULL
UNION ALL
 SELECT 'Verdunstung'::text AS art,
    m.auftrag_id,
    m.charge_nr,
    m.sorte,
    m.wiege_ts AS start_ts,
    format('%s %% je Tag: %s kg → %s kg in %s Tagen — so schnell verdunstet kein Kürbis (Grenze %s %% je Tag)'::text, round(m.rate_pro_tag * 100::numeric, 2), round(m.netto_damals_kg), round(m.netto_jetzt_kg), m.lagertage, round(verdunstung_rate_max() * 100::numeric, 2)) AS befund,
    'Zettelgewicht, Kisten und Gebinde dieser Wägung prüfen — oder es ist eine andere Palette. Bis zur Korrektur zählt sie nicht in die Rate.'::text AS rat,
    'verdunstung_wiegung:'::text || m.id AS bezug
   FROM v_verdunstung_messung m
  WHERE m.grund ~~ 'zu schnell%'::text;
comment on view v_plausibilitaet_0064_zusatz is 'Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die Paletten fehlen im Eingang), eine Charge mit mehr Ausgang als Eingang, und ein Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag. 0128: dazu je Auffälligkeit ihr Bezug. Seit 0134 sagt die Überzählung, welche sie ist (v_charge_bedarf.art): sicher ein Datenfehler, oder die Raten passen nicht zur Charge — und nur, wenn die Lieferungen ausserhalb der Spanne der Raten liegen.';
grant select on v_plausibilitaet_0064_zusatz to authenticated;

-- ---------- Stand ----------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 134 $$;
