-- 0135 — Was der Zettel sagt (Runde BJ, Schritt 5)
--
-- Der Betrieb am 7. November, zu den Auffälligkeiten der Messungen (111, die
-- meisten „Zettelgewicht"): „das wichtige ist eigentlich nicht, den ganz
-- genauen Grund zu finden — aber dass das Programm trotzdem Infos daraus
-- beziehen kann: die Daten, die verwendbar sind, trotzdem nimmt, und die, die
-- nicht verwendbar sind, ignoriert — aber nicht den ganzen Arbeitsschritt
-- vernachlässigt." Zum Datum: „das sollte genau funktionieren … also da wäre
-- ich strikter". Und: die App soll alte offene Arbeiten melden.
--
--   v_charge_palettenbild  je Charge die volle Palette (häufigste Kistenzahl)
--                          und das Netto je Kiste (Median) — woran ein Rest
--                          und eine Teilpalette zu erkennen sind
--   v_wiegung_netto        das Netto einer Wägung; eine Teilpalette, gewogen
--                          mit dem Zettel der ganzen Palette, anteilig
--                          (Netto der vollen Palette × Kisten ÷ volle Kisten)
--   v_zettel_doppelt       derselbe Zettel mit derselben Wägung innert
--                          10 Sekunden ein zweites Mal gespeichert
--   v_zettel_lage          je Zettel: Palox, Rest einer Palette, Palox nach
--                          der Anzahl zugeordnet, doppelt
--   v_verdunstung_messung  Netto aus v_wiegung_netto; die doppelte Wägung
--                          zählt nicht
--   v_auftrag_palette_masse  der doppelte Zettel zählt nicht; die Wägung
--                          einer Teilpalette mit ihrem anteiligen Netto
--   v_plausibilitaet       kein „Zettelgewicht" für einen Rest, für Palox,
--                          die nach der Anzahl aufgehen, und für den doppelten
--                          Zettel; neu „Doppelt gespeichert" und „Arbeit
--                          offen" (seit mehr als 3 Tagen)
--   v_plausibilitaet_0064_zusatz  das Datum bleibt streng, der Satz sagt
--                          beide Daten: Zettel und Journal
--   paletten_zuordnen()    der Satz sagt, was „ohne eigene Palette" heisst

-- ---------- v_charge_palettenbild ----------
create or replace view v_charge_palettenbild with (security_invoker = true) as
select p.charge_nr,
       mode() within group (order by p.kisten desc) as kisten_voll,
       zahl(percentile_cont(0.5) within group (order by p.netto_kg / p.kisten), 3, 100000)::numeric(10,3) as netto_je_kiste,
       count(*)::int as n_paletten
  from v_palette p
 where p.kisten > 1 and coalesce(p.gebindeart, '') !~* 'palox' and p.netto_kg > 0
 group by p.charge_nr;
comment on view v_charge_palettenbild is
  'Je Charge, wie ihre Paletten aussehen (0135): kisten_voll ist die häufigste Kistenzahl (bei Gleichstand die grössere), netto_je_kiste der Median des Nettos je Kiste — ohne Palox. Daran erkennt die App einen Rest einer Palette (weniger Kisten, Netto je Kiste wie die Charge) und eine Teilpalette, gewogen mit dem Zettel der ganzen Palette.';
grant select on v_charge_palettenbild to authenticated;

-- ---------- v_wiegung_netto ----------
-- Die drei Zettel-Sichten v_wiegung_netto, v_zettel_doppelt und v_zettel_lage stehen, wie die vier
-- Knoten-Sichten seit 0109, hinter einer Planungsgrenze (<sicht>_formel, <sicht>_zaun()): Sie stecken in
-- der Verdunstung, der Masse der Arbeit und den Auffälligkeiten, und eingesetzt plante
-- erg_plausibilitaet auf der Demo mit 1035 Knoten (0109 erlaubt 1000); mit Grenze 781.
-- Eine Teilpalette, gewogen mit dem Zettel der ganzen Palette: das Zettelgewicht
-- liegt näher bei einer vollen Palette der Charge als bei den gewogenen Kisten.
-- Dann ist das Netto damals das der vollen Palette, anteilig auf die Kisten.
create or replace view v_wiegung_netto_formel with (security_invoker = true) as
select w.id,
       case when t.teil
            then zahl((w.brutto_damals_kg - pb.kisten_voll * g.tara_kg_pro_kiste - g.tara_kg_palette) * w.kisten / pb.kisten_voll, 2, 100000000)
            else w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette end as netto_damals_kg,
       w.brutto_jetzt_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette as netto_jetzt_kg,
       case when t.teil then pb.kisten_voll end as kisten_voll,
       coalesce(t.teil, false) as anteilig
  from verdunstung_wiegung w
  left join gebinde g on g.art = w.gebindeart
  left join v_charge_palettenbild pb on pb.charge_nr = w.charge_nr
  cross join lateral (
    select w.kisten > 1 and coalesce(w.gebindeart, '') !~* 'palox' and w.kisten < pb.kisten_voll - 2
       and pb.netto_je_kiste > 0 and g.tara_kg_pro_kiste is not null and g.tara_kg_palette is not null
       and abs(w.brutto_damals_kg - (pb.kisten_voll * (g.tara_kg_pro_kiste + pb.netto_je_kiste) + g.tara_kg_palette))
         < abs(w.brutto_damals_kg - (w.kisten * (g.tara_kg_pro_kiste + pb.netto_je_kiste) + g.tara_kg_palette)) as teil) t;
comment on view v_wiegung_netto_formel is
  'Die Formel von v_wiegung_netto (0135); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
grant select on v_wiegung_netto_formel to authenticated;

create or replace function v_wiegung_netto_zaun() returns setof v_wiegung_netto_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_wiegung_netto_formel;
end $$;
comment on function v_wiegung_netto_zaun() is
  'Planungsgrenze (0135, wie 0109): liest v_wiegung_netto_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_wiegung_netto_zaun() from public;
grant execute on function v_wiegung_netto_zaun() to authenticated;

create or replace view v_wiegung_netto with (security_invoker = true) as
select * from v_wiegung_netto_zaun();
comment on view v_wiegung_netto is
  'Das Netto einer Wägung (0135): damals und jetzt, Brutto minus Kisten × Kistengewicht minus Palette. Eine Teilpalette, gewogen mit dem Zettel der ganzen Palette (weniger Kisten als die volle Palette der Charge, mehr als zwei weniger, und das Zettelgewicht liegt näher bei einer vollen Palette als bei den gewogenen Kisten), rechnet damals anteilig: Netto der vollen Palette × gewogene Kisten ÷ volle Kisten (anteilig, kisten_voll). Palox nie.';
grant select on v_wiegung_netto to authenticated;

-- ---------- v_zettel_doppelt ----------
create or replace view v_zettel_doppelt_formel with (security_invoker = true) as
select z.id, e.id as erstes_id, z.auftrag_id, z.eingangsdatum, z.brutto_zettel_kg, z.kisten,
       coalesce(wz.brutto_jetzt_kg, z.brutto_gewogen_kg) as gewogen_kg,
       zahl(extract(epoch from z.ts - e.ts), 1, 100000)::numeric(8,1) as sekunden
  from auftrag_palette z
  left join verdunstung_wiegung wz on wz.id = z.wiegung_id
  join lateral (
    select e.id, e.ts
      from auftrag_palette e
      left join verdunstung_wiegung we on we.id = e.wiegung_id
     where e.auftrag_id = z.auftrag_id and e.id < z.id
       and e.eingangsdatum is not distinct from z.eingangsdatum
       and e.brutto_zettel_kg = z.brutto_zettel_kg
       and e.kisten is not distinct from z.kisten
       and coalesce(we.brutto_jetzt_kg, e.brutto_gewogen_kg) = coalesce(wz.brutto_jetzt_kg, z.brutto_gewogen_kg)
       and abs(extract(epoch from z.ts - e.ts)) <= 10
     order by e.id desc
     limit 1) e on true
 where coalesce(wz.brutto_jetzt_kg, z.brutto_gewogen_kg) is not null;
comment on view v_zettel_doppelt_formel is
  'Die Formel von v_zettel_doppelt (0135); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
grant select on v_zettel_doppelt_formel to authenticated;

create or replace function v_zettel_doppelt_zaun() returns setof v_zettel_doppelt_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_zettel_doppelt_formel;
end $$;
comment on function v_zettel_doppelt_zaun() is
  'Planungsgrenze (0135, wie 0109): liest v_zettel_doppelt_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_zettel_doppelt_zaun() from public;
grant execute on function v_zettel_doppelt_zaun() to authenticated;

create or replace view v_zettel_doppelt with (security_invoker = true) as
select * from v_zettel_doppelt_zaun();
comment on view v_zettel_doppelt is
  'Derselbe Zettel ein zweites Mal gespeichert (0135): in derselben Arbeit, mit demselben Eingangsdatum, Gewicht und Kisten, mit derselben Wägung aufs Gramm und innert 10 Sekunden nach dem ersten. In 10 Sekunden wiegt niemand eine zweite Palette. Der zweite zählt nicht in die Masse der Arbeit und seine Wägung nicht in die Verdunstung; ohne Wägung bleibt er (zwei gleiche Paletten sind möglich).';
grant select on v_zettel_doppelt to authenticated;

-- ---------- v_zettel_lage ----------
create or replace view v_zettel_lage_formel with (security_invoker = true) as
with z as (
  select ap.id, ap.auftrag_id, a.charge_nr, ap.eingangsdatum, ap.brutto_zettel_kg, ap.kisten, ap.gebindeart,
         coalesce(ap.gebindeart, '') ~* 'palox' or ap.kisten = 1 as palox
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
   where a.abgebrochen_ts is null
)
select z.id, z.auftrag_id, z.charge_nr, z.palox,
       -- Rest einer Palette, neu gewogen und angeschrieben: weniger Kisten als die volle Palette,
       -- das Netto je Kiste wie die Charge (±25 %), und keine Palette mit genau diesen Kisten im
       -- Journal (±3 Tage) — sonst wäre es eher ein vertipptes Gewicht
       coalesce(not z.palox and z.kisten > 1 and z.kisten < pb.kisten_voll - 2
                and g.tara_kg_pro_kiste is not null and g.tara_kg_palette is not null and pb.netto_je_kiste > 0
                and abs((z.brutto_zettel_kg - z.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette) / z.kisten - pb.netto_je_kiste)
                    <= 0.25 * pb.netto_je_kiste
                and not exists (select 1 from palette p where p.charge_nr = z.charge_nr and p.kisten = z.kisten
                                   and abs(p.eingangsdatum - z.eingangsdatum) <= 3), false) as rest,
       -- Palox nach der Anzahl: so viele Palox-Zettel der Charge an dem Tag (alle Arbeiten, ohne
       -- doppelte), wie das Journal Palox hat — oder weniger
       coalesce(z.palox and z.eingangsdatum is not null
                and (select count(*) from z z2
                      where z2.charge_nr = z.charge_nr and z2.eingangsdatum = z.eingangsdatum and z2.palox
                        and not (z2.id = any (array(select d.id from v_zettel_doppelt d))))
                    <= (select count(*) from palette p
                         where p.charge_nr = z.charge_nr and p.eingangsdatum = z.eingangsdatum
                           and (coalesce(p.gebindeart, '') ~* 'palox' or p.kisten = 1)), false) as palox_passt,
       -- die doppelten einmal je Abfrage gelesen (über ihre Grenze), nicht einmal je Zettel
       z.id = any (array(select d.id from v_zettel_doppelt d)) as doppelt
  from z
  left join v_charge_palettenbild pb on pb.charge_nr = z.charge_nr
  left join gebinde g on g.art = z.gebindeart;
comment on view v_zettel_lage_formel is
  'Die Formel von v_zettel_lage (0135); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
grant select on v_zettel_lage_formel to authenticated;

create or replace function v_zettel_lage_zaun() returns setof v_zettel_lage_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_zettel_lage_formel;
end $$;
comment on function v_zettel_lage_zaun() is
  'Planungsgrenze (0135, wie 0109): liest v_zettel_lage_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_zettel_lage_zaun() from public;
grant execute on function v_zettel_lage_zaun() to authenticated;

create or replace view v_zettel_lage with (security_invoker = true) as
select * from v_zettel_lage_zaun();
comment on view v_zettel_lage is
  'Je Zettel einer Arbeit, was die App über ihn weiss, ohne eine Palette mit genau seinem Gewicht zu finden (0135): palox (Gebinde Palox oder eine Kiste), rest (Rest einer Palette, neu gewogen und angeschrieben: weniger Kisten als die volle Palette der Charge, das Netto je Kiste wie die Charge ±25 %, und im Journal ±3 Tage keine Palette mit genau diesen Kisten), palox_passt (Palox werden über die Anzahl zugeordnet: nicht mehr Palox-Zettel der Charge an dem Tag als Palox im Journal) und doppelt (v_zettel_doppelt). Für sie gibt es kein „Zettelgewicht".';
grant select on v_zettel_lage to authenticated;

-- ---------- v_verdunstung_messung: Netto aus v_wiegung_netto, die doppelte Wägung zählt nicht ----------
create or replace view v_verdunstung_messung with (security_invoker=true) as
 SELECT b.id,
    b.charge_nr,
    b.sorte,
    b.schlag,
    b.palette_id,
    b.eingangsdatum,
    b.wiege_ts,
    b.sichtbar_schimmel,
    b.erfasser,
    b.auftrag_id,
    b.netto_damals_kg,
    b.netto_jetzt_kg,
    b.lagertage,
    r.rate_pro_tag,
    u.grund IS NULL AS verwendbar,
    r.rate_pro_tag IS NULL OR r.rate_pro_tag <= k.rate_max AS plausibel,
    u.grund,
    b.kisten_voll,
    b.anteilig
   FROM ( SELECT w.id,
            w.charge_nr,
            c.sorte,
            c.schlag,
            w.palette_id,
            w.eingangsdatum,
            w.wiege_ts,
            w.sichtbar_schimmel,
            w.erfasser,
            w.auftrag_id,
            w.gemessen,
            a.id IS NOT NULL AND a.abgebrochen_ts IS NOT NULL AS abgebrochen,
            wn.netto_damals_kg,
            wn.netto_jetzt_kg,
            betriebstag(w.wiege_ts) - w.eingangsdatum AS lagertage,
            wn.kisten_voll,
            wn.anteilig,
            (EXISTS ( SELECT 1
                   FROM auftrag_palette ap
                     JOIN v_zettel_doppelt d ON d.id = ap.id
                  WHERE ap.wiegung_id = w.id)) AS doppelt
           FROM verdunstung_wiegung w
             JOIN charge c ON c.nr = w.charge_nr
             LEFT JOIN auftrag a ON a.id = w.auftrag_id
             LEFT JOIN v_wiegung_netto wn ON wn.id = w.id
         OFFSET 0) b
     CROSS JOIN ( SELECT verdunstung_rate_max() AS rate_max) k
     CROSS JOIN LATERAL ( SELECT zahl(
                CASE
                    WHEN b.netto_damals_kg > 0::numeric AND b.netto_jetzt_kg > 0::numeric AND b.lagertage > 0 THEN 1::numeric - power(b.netto_jetzt_kg / b.netto_damals_kg, 1.0 / b.lagertage::numeric)
                    ELSE NULL::numeric
                END, 6, 10000::numeric)::numeric(10,6) AS rate_pro_tag
         OFFSET 0) r
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM messung_ausschluss x
                      WHERE x.art = 'verdunstung'::text AND x.bezug_id = b.id)) THEN 'von Hand ausgeschlossen'::text
                    WHEN NOT b.gemessen THEN 'nicht gemessen'::text
                    WHEN b.doppelt THEN 'doppelt gespeichert — dieselbe Wägung zählt einmal'::text
                    WHEN b.sichtbar_schimmel THEN 'Schimmel sichtbar — die Palette verlor mehr als Wasser'::text
                    WHEN b.abgebrochen THEN 'Arbeit abgebrochen'::text
                    WHEN b.netto_damals_kg IS NULL OR b.netto_jetzt_kg IS NULL THEN 'ohne Netto — die Tara des Gebindes fehlt'::text
                    WHEN b.netto_damals_kg <= 0::numeric OR b.netto_jetzt_kg <= 0::numeric THEN 'Netto unter null — das Brutto ist kleiner als die Tara'::text
                    WHEN b.lagertage <= 0 THEN 'am Eingangstag gewogen — keine Lagerdauer'::text
                    WHEN b.netto_jetzt_kg > (b.netto_damals_kg * 1.01) THEN 'schwerer geworden — Waagenrauschen oder ein kopiertes Eingangsgewicht'::text
                    WHEN b.netto_jetzt_kg = b.netto_damals_kg THEN 'unverändert — dieselbe Zahl zweimal'::text
                    WHEN r.rate_pro_tag > k.rate_max THEN format('zu schnell — %s %% je Tag ist keine Verdunstung'::text, round(r.rate_pro_tag * 100::numeric, 2))
                    ELSE NULL::text
                END AS grund) u;
comment on view v_verdunstung_messung is 'Je Wägung derselben Palette: Netto damals und jetzt, Lagertage, die Tagesrate — und ob sie in die Rate der Sorte zählt (verwendbar). Seit 0089 sagt `grund`, warum nicht, und `plausibel`, ob die Rate unter der Grenze verdunstung_rate_max_pro_tag liegt: Was schneller schwindet, ist keine Verdunstung. Seit 0135 kommt das Netto aus v_wiegung_netto: eine Teilpalette, gewogen mit dem Zettel der ganzen Palette, rechnet damals anteilig (anteilig, kisten_voll); eine doppelt gespeicherte Wägung (v_zettel_doppelt) zählt nicht.';
grant select on v_verdunstung_messung to authenticated;

-- ---------- v_auftrag_palette_masse: der doppelte Zettel zählt nicht ----------
create or replace view v_auftrag_palette_masse with (security_invoker=true) as
 WITH wiegung AS MATERIALIZED (
         SELECT vw.id,
            zahl(wn.netto_damals_kg, 2, 100000000::numeric)::numeric(10,2) AS netto_damals_kg,
            vw.eingangsdatum
           FROM verdunstung_wiegung vw
             LEFT JOIN v_wiegung_netto wn ON wn.id = vw.id
        ), datum_mittel AS MATERIALIZED (
         SELECT v_palette.charge_nr,
            v_palette.eingangsdatum,
            avg(v_palette.netto_kg) AS netto_mittel,
            avg(v_palette.netto_kg / v_palette.kisten::numeric) FILTER (WHERE v_palette.netto_kg IS NOT NULL AND v_palette.kisten > 0) AS netto_je_kiste
           FROM v_palette
          GROUP BY v_palette.charge_nr, v_palette.eingangsdatum
        ), charge_mittel AS MATERIALIZED (
         SELECT v_palette.charge_nr,
            avg(v_palette.netto_kg) AS netto_mittel,
            avg(v_palette.brutto_kg - v_palette.netto_kg) FILTER (WHERE v_palette.netto_kg IS NOT NULL) AS tara_mittel,
            avg(v_palette.netto_kg / v_palette.kisten::numeric) FILTER (WHERE v_palette.netto_kg IS NOT NULL AND v_palette.kisten > 0) AS netto_je_kiste,
            avg((v_palette.brutto_kg - v_palette.netto_kg) / v_palette.kisten::numeric) FILTER (WHERE v_palette.netto_kg IS NOT NULL AND v_palette.kisten > 0) AS tara_je_kiste
           FROM v_palette
          GROUP BY v_palette.charge_nr
        ), charge_datum AS MATERIALIZED (
         SELECT v_charge_rueckgrat.charge_nr,
            v_charge_rueckgrat.eingangsdatum_mittel
           FROM v_charge_rueckgrat
        ), zettel AS MATERIALIZED (
         SELECT ap_1.id,
            COALESCE(pe.netto_kg,
                CASE
                    WHEN pe.id IS NULL AND ap_1.kisten IS NOT NULL AND g.tara_kg_pro_kiste IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND (ap_1.brutto_zettel_kg - ap_1.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) > 0::numeric THEN zahl(ap_1.brutto_zettel_kg - ap_1.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, 100000000::numeric)::numeric(10,2)
                    ELSE NULL::numeric
                END, zahl(ap_1.brutto_zettel_kg - COALESCE(ap_1.kisten::numeric * cm_1.tara_je_kiste, cm_1.tara_mittel), 2, 100000000::numeric)::numeric(10,2)) AS netto_kg,
            pe.id IS NOT NULL AS exakt,
            pe.id IS NULL AND ap_1.kisten IS NOT NULL AND g.tara_kg_pro_kiste IS NOT NULL AND g.tara_kg_palette IS NOT NULL AND (ap_1.brutto_zettel_kg - ap_1.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) > 0::numeric AS kisten_tara,
            pe.id IS NULL AND ap_1.kisten IS NOT NULL AND cm_1.tara_je_kiste IS NOT NULL AS kisten_charge
           FROM auftrag_palette ap_1
             JOIN auftrag a_1 ON a_1.id = ap_1.auftrag_id
             LEFT JOIN LATERAL ( SELECT p_1.id,
                    p_1.netto_kg
                   FROM v_palette p_1
                  WHERE p_1.charge_nr = a_1.charge_nr AND p_1.eingangsdatum = ap_1.eingangsdatum AND p_1.brutto_kg = ap_1.brutto_zettel_kg AND p_1.netto_kg IS NOT NULL
                  ORDER BY p_1.id
                 LIMIT 1) pe ON true
             LEFT JOIN gebinde g ON g.art = ap_1.gebindeart
             LEFT JOIN charge_mittel cm_1 ON cm_1.charge_nr = a_1.charge_nr
          WHERE ap_1.brutto_zettel_kg IS NOT NULL
        )
 SELECT ap.id,
    ap.auftrag_id,
    a.charge_nr,
    a.start_ts,
    COALESCE(w.netto_damals_kg, z.netto_kg, p.netto_kg, ap.kisten::numeric * d.netto_je_kiste, d.netto_mittel, ap.kisten::numeric * cm.netto_je_kiste, cm.netto_mittel) AS netto_kg,
    COALESCE(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) AS eingangsdatum,
        CASE
            WHEN w.netto_damals_kg IS NOT NULL THEN 'gewogen'::text
            WHEN z.netto_kg IS NOT NULL AND z.exakt THEN 'zettel'::text
            WHEN z.netto_kg IS NOT NULL AND z.kisten_tara THEN 'zettel-kisten'::text
            WHEN z.netto_kg IS NOT NULL AND z.kisten_charge THEN 'zettel-kisten-charge'::text
            WHEN z.netto_kg IS NOT NULL THEN 'zettel-charge-tara'::text
            WHEN p.netto_kg IS NOT NULL THEN 'palette'::text
            WHEN ap.kisten IS NOT NULL AND d.netto_je_kiste IS NOT NULL THEN 'datum-je-kiste'::text
            WHEN d.netto_mittel IS NOT NULL THEN 'datum-mittel'::text
            WHEN ap.kisten IS NOT NULL AND cm.netto_je_kiste IS NOT NULL THEN 'charge-je-kiste'::text
            WHEN cm.netto_mittel IS NOT NULL THEN 'charge-mittel'::text
            ELSE 'unbekannt'::text
        END AS masse_quelle
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     LEFT JOIN wiegung w ON w.id = ap.wiegung_id
     LEFT JOIN zettel z ON z.id = ap.id
     LEFT JOIN v_palette p ON p.id = ap.palette_id
     LEFT JOIN datum_mittel d ON d.charge_nr = a.charge_nr AND d.eingangsdatum = ap.eingangsdatum
     LEFT JOIN charge_mittel cm ON cm.charge_nr = a.charge_nr
     LEFT JOIN charge_datum cd ON cd.charge_nr = a.charge_nr
  WHERE NOT (a.station = 'waschen'::station AND NOT a.ist_fax) AND NOT (EXISTS ( SELECT 1
           FROM v_zettel_doppelt dz
          WHERE dz.id = ap.id));
comment on view v_auftrag_palette_masse is 'Je gezählter Palette einer Arbeit ihr Netto und woher es stammt (masse_quelle): gewogen · zettel (im Wareneingang gefunden) · zettel-kisten (Zettel minus die gezählten Kisten und ihre Tara, 0090) · zettel-charge-tara · palette · datum-mittel · charge-mittel. Seit 0135: ein doppelt gespeicherter Zettel (v_zettel_doppelt) zählt nicht; eine gewogene Teilpalette mit dem Zettel der ganzen Palette mit ihrem anteiligen Netto (v_wiegung_netto).';
grant select on v_auftrag_palette_masse to authenticated;

-- ---------- v_plausibilitaet_0064_zusatz: das Datum, streng und mit beiden Daten ----------
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
            CASE
                WHEN u.r IS NULL THEN 'ohne gemessene Verdunstung'::text
                ELSE format('Verdunstung %s %% je Tag'::text, round(100::numeric * u.r, 2))
            END,
            CASE
                WHEN u.f IS NULL THEN 'ohne Palox-Rate'::text
                ELSE format('Palox %s %%'::text, round(100::numeric * u.f))
            END)
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
    format('Zettel vom %s mit %s kg (%s gezählt): eine Palette mit genau diesem Gewicht%s steht im Wareneingang am %s, nicht am %s. Zettel und Journal tragen verschiedene Daten — eines ist falsch; %s, nicht mit der Palette selbst.'::text, to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text), ap.brutto_zettel_kg, count(*),
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM palette p
              WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg AND p.kisten = ANY (array_agg(ap.kisten)))) THEN ' und gleichen Kisten'::text
            ELSE ''::text
        END, ( SELECT string_agg(DISTINCT to_char(p.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text), ', '::text) AS string_agg
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg), to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text),
        CASE
            WHEN bool_and(m.masse_quelle = 'gewogen'::text) THEN 'gerechnet wird mit der Wägung der Palette'::text
            WHEN bool_and(m.masse_quelle = 'zettel-kisten'::text) THEN 'gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette)'::text
            WHEN bool_and(m.masse_quelle = ANY (ARRAY['zettel-kisten'::text, 'zettel-kisten-charge'::text, 'gewogen'::text])) THEN 'gerechnet wird mit den gezählten Kisten und der Tara je Kiste der Charge (Zettel − Kisten × Tara je Kiste)'::text
            ELSE 'gerechnet wird mit der mittleren Tara ganzer Paletten der Charge — an der Zählung fehlt die Kistenzahl'::text
        END) AS befund,
    'Datum auf dem Zettel und im Journal vergleichen — stimmt der Zettel, im Journal berichtigen; stimmt das Journal, in der Korrektur der Arbeit das Zetteldatum.'::text AS rat,
    (((('zettel:'::text || ap.auftrag_id) || ':'::text) || ap.brutto_zettel_kg) || ':'::text) || ap.eingangsdatum AS bezug
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.id = ap.id
  WHERE ap.brutto_zettel_kg IS NOT NULL AND ap.eingangsdatum IS NOT NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg)) AND NOT (EXISTS ( SELECT 1
           FROM v_palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg AND p.eingangsdatum = ap.eingangsdatum AND p.netto_kg IS NOT NULL)) AND NOT (EXISTS ( SELECT 1
           FROM v_zettel_lage zl
          WHERE zl.id = ap.id AND (zl.palox_passt OR zl.doppelt)))
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
comment on view v_plausibilitaet_0064_zusatz is 'Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die Paletten fehlen im Eingang), eine Charge mit mehr Ausgang als Eingang, und ein Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag. 0128: dazu je Auffälligkeit ihr Bezug. Seit 0134 sagt die Überzählung, welche sie ist (v_charge_bedarf.art): sicher ein Datenfehler, oder die Raten passen nicht zur Charge — und nur, wenn die Lieferungen ausserhalb der Spanne der Raten liegen. Seit 0135 bleibt das Datum streng, und der Satz nennt beide Daten, Zettel und Journal; Palox, die nach der Anzahl aufgehen, und doppelte Zettel stehen nicht da.';
grant select on v_plausibilitaet_0064_zusatz to authenticated;

-- ---------- v_plausibilitaet: Rest, Palox nach Anzahl, doppelt, Arbeit offen ----------
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
  WHERE NOT w.verwendbar AND NOT w.sichtbar_schimmel AND COALESCE(w.grund, ''::text) !~~ 'zu schnell%'::text AND COALESCE(w.grund, ''::text) !~~ 'doppelt%'::text AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AND (EXISTS ( SELECT 1
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
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg)) AND NOT (EXISTS ( SELECT 1
           FROM v_zettel_lage zl
          WHERE zl.id = ap.id AND (zl.rest OR zl.palox_passt OR zl.doppelt)))
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
  WHERE p.brutto_kg > 2000::numeric
UNION ALL
 SELECT 'Doppelt gespeichert'::text AS art,
    d.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('Zettel %s kg vom %s zweimal gespeichert, %s s auseinander, mit derselben Wägung (%s kg) — die App zählt ihn einmal'::text, d.brutto_zettel_kg, to_char(d.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text), round(abs(d.sekunden)), d.gewogen_kg) AS befund,
    'Nichts zu tun — in 10 Sekunden wiegt niemand eine zweite Palette.'::text AS rat,
    'zettel_doppelt:'::text || d.id AS bezug
   FROM v_zettel_doppelt d
     JOIN auftrag a ON a.id = d.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE a.abgebrochen_ts IS NULL
UNION ALL
 SELECT 'Arbeit offen'::text AS art,
    a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('Arbeit seit %s offen (%s Tage) — %s Zettel und %s Palox-Ablesungen erfasst, aber kein Ende'::text, to_char(betriebstag(a.start_ts)::timestamp with time zone, 'DD.MM.YYYY'::text), heute() - betriebstag(a.start_ts), ( SELECT count(*) AS count
           FROM auftrag_palette ap
          WHERE ap.auftrag_id = a.id), ( SELECT count(*) AS count
           FROM schimmel_messung s
          WHERE s.auftrag_id = a.id)) AS befund,
    'In der Halle abschliessen — oder abbrechen, wenn die Arbeit nie lief.'::text AS rat,
    'auftrag:'::text || a.id AS bezug
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
  WHERE a.status = 'offen'::auftrag_status AND a.abgebrochen_ts IS NULL AND a.ende_ts IS NULL AND betriebstag(a.start_ts) < (heute() - 3);
comment on view v_plausibilitaet is 'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette. 0066: „Ausschuss-Tara" rechnet nur nach, wo Kistenzahl und hinterlegte Tara da sind; fehlt eine, steht die Lücke als „Ausschuss ohne Tara" daneben. 0087: die Nachrechnung zieht die Palette nur ab, wenn sie mitgewogen wurde, und klemmt nichts auf null. 0114: eine zu schnell leichter gewordene Wägung steht nur als „Verdunstung" da, nicht noch einmal als „Wägung". 0128: bezug — woran die Auffälligkeit hängt (Zettel, Wägung, Ablesung, Charge …); Art und Bezug sind die Kennung des Falls, unter der Nummer und Vermerk stehen. Ausschuss (Hand) trägt den Beginn der Arbeit als Tag. 0135: kein „Zettelgewicht" für einen Rest einer Palette, für Palox, die nach der Anzahl aufgehen, und für einen doppelt gespeicherten Zettel (v_zettel_lage); neu „Doppelt gespeichert" (zählt einmal) und „Arbeit offen" (seit mehr als drei Tagen ohne Ende).';
grant select on v_plausibilitaet to authenticated;

-- ---------- paletten_zuordnen(): was „ohne eigene Palette" heisst ----------
create or replace function paletten_zuordnen()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  z record; w record; v_ch record; g record;
  v_pid bigint;
  v_eigen bigint[] := '{}';       -- Paletten, die ein Zettel ihrer eigenen Charge gezählt hat
  v_vergeben bigint[] := '{}';    -- Paletten, die schon eine andere Arbeit bekommen hat
  v_ohne bigint[];                -- Zettel einer Arbeit ohne eigene Palette
  v_best_charge int; v_best bigint[]; v_best_zettel text[];
  v_treffer bigint[]; v_zettel text[];
  v_anteil numeric; v_geliefert numeric; v_eingang numeric; v_stand text; v_n int := 0;
begin
  -- Der Rechenlauf ruft sie (Zeitplan: ohne Anmeldung); von Hand nur der Betriebsleiter.
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Paletten zuordnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  if to_regclass('pg_temp.zuordnung_neu') is null then
    create temp table zuordnung_neu (
      palette_id bigint primary key, von_charge_nr int, nach_charge_nr int, auftrag_id bigint,
      art text, stand text, grund text) on commit drop;
  end if;
  -- Arbeitstabellen dieses Aufrufs (temporär, mit der Transaktion weg) — leer beginnen.
  delete from zuordnung_neu where palette_id is not null;

  -- Zettel ohne eigene Palette: zuerst nimmt jeder Zettel eine Palette seiner
  -- eigenen Charge (laut Journal), aufs Kilo, Eingang ±3 Tage, die nächste
  -- zuerst — wie der Durchgang (pruefstand/durchgang_pruefungen.mjs, 4c).
  if to_regclass('pg_temp.zettel_ohne') is null then
    create temp table zettel_ohne (zettel_id bigint primary key, auftrag_id bigint) on commit drop;
  end if;
  delete from zettel_ohne where zettel_id is not null;
  for z in
    select ap.id, ap.auftrag_id, ap.brutto_zettel_kg, ap.eingangsdatum, a.charge_nr
      from auftrag_palette ap join auftrag a on a.id = ap.auftrag_id
     where a.abgebrochen_ts is null and ap.brutto_zettel_kg is not null and ap.eingangsdatum is not null
     order by a.start_ts, ap.id
  loop
    v_pid := null;
    select pl.id into v_pid from palette pl
     where coalesce(pl.charge_nr_journal, pl.charge_nr) = z.charge_nr and pl.brutto_kg = z.brutto_zettel_kg
       and abs(pl.eingangsdatum - z.eingangsdatum) <= 3 and not (pl.id = any(v_eigen))
     order by abs(pl.eingangsdatum - z.eingangsdatum), pl.id limit 1;
    if v_pid is not null then v_eigen := v_eigen || v_pid;
    else insert into zettel_ohne values (z.id, z.auftrag_id);
    end if;
  end loop;

  -- Je Arbeit mit mindestens zwei solchen Zetteln: die Charge desselben
  -- Schlags, zu deren Paletten die meisten passen.
  for w in
    select a.id as auftrag_id, a.charge_nr, c.schlag, count(*)::int as n_ohne
      from zettel_ohne zo join auftrag a on a.id = zo.auftrag_id join charge c on c.nr = a.charge_nr
     group by a.id, a.charge_nr, c.schlag, a.start_ts
    having count(*) >= 2
     order by a.start_ts, a.id
  loop
    v_best_charge := null; v_best := '{}'; v_best_zettel := '{}';
    for v_ch in select nr from charge where schlag = w.schlag and nr <> w.charge_nr order by nr loop
      v_treffer := '{}'; v_zettel := '{}';
      for z in
        select ap.id, ap.brutto_zettel_kg, ap.eingangsdatum
          from zettel_ohne zo join auftrag_palette ap on ap.id = zo.zettel_id
         where zo.auftrag_id = w.auftrag_id order by ap.id
      loop
        v_pid := null;
        select pl.id into v_pid from palette pl
         where coalesce(pl.charge_nr_journal, pl.charge_nr) = v_ch.nr and pl.brutto_kg = z.brutto_zettel_kg
           and abs(pl.eingangsdatum - z.eingangsdatum) <= 3
           and not (pl.id = any(v_eigen)) and not (pl.id = any(v_vergeben)) and not (pl.id = any(v_treffer))
         order by abs(pl.eingangsdatum - z.eingangsdatum), pl.id limit 1;
        if v_pid is not null then
          v_treffer := v_treffer || v_pid;
          v_zettel := v_zettel || format('%s kg', trim(to_char(z.brutto_zettel_kg, 'FM99990.##')));
        end if;
      end loop;
      if cardinality(v_treffer) > cardinality(v_best) then
        v_best_charge := v_ch.nr; v_best := v_treffer; v_best_zettel := v_zettel;
      end if;
    end loop;
    continue when cardinality(v_best) < 2;
    v_anteil := cardinality(v_best)::numeric / w.n_ohne;
    continue when v_anteil < 0.5;

    -- Hat die Charge der Arbeit mehr ausgeliefert, als sie laut Journal je bekam?
    select coalesce(sum(l.masse_kg), 0) into v_geliefert from v_lieferung_masse l
     where l.charge_nr = w.charge_nr and l.buch in ('verkauf', 'marge') and l.masse_kg > 0;
    select coalesce(sum(vp.netto_kg), 0) into v_eingang from v_palette vp join palette pl on pl.id = vp.id
     where coalesce(pl.charge_nr_journal, pl.charge_nr) = w.charge_nr;
    v_stand := case when v_anteil >= 0.8 and v_geliefert > v_eingang then 'angewandt' else 'vorschlag' end;

    insert into zuordnung_neu
    select pl.id, v_best_charge, w.charge_nr, w.auftrag_id, 'zettel', v_stand,
           format('%s Zettel der Arbeit %s finden bei Charge %s keine Palette mit ihrem Gewicht (Eingang ±3 Tage); %s davon passen aufs Kilo zu Paletten von Charge %s (%s)%s',
                  w.n_ohne, w.auftrag_id, w.charge_nr, cardinality(v_best), v_best_charge, array_to_string(v_best_zettel, ', '),
                  case when v_geliefert > v_eingang
                       then format('; Charge %s lieferte %s kg bei %s kg Eingang', w.charge_nr, round(v_geliefert), round(v_eingang))
                       else format('; Charge %s lieferte nicht mehr, als sie bekam', w.charge_nr) end)
      from palette pl where pl.id = any(v_best)
    on conflict (palette_id) do nothing;
    v_vergeben := v_vergeben || v_best;

    -- Die Fuhre: Paletten desselben Tags und Gebindes, von denen 80 % in der Arbeit lagen.
    if v_stand = 'angewandt' then
      for g in
        select pl.eingangsdatum, pl.gebindeart, count(*)::int as n,
               count(*) filter (where pl.id = any(v_best))::int as n_drin
          from palette pl
         where coalesce(pl.charge_nr_journal, pl.charge_nr) = v_best_charge
           and (pl.eingangsdatum, coalesce(pl.gebindeart, '')) in
               (select p2.eingangsdatum, coalesce(p2.gebindeart, '') from palette p2 where p2.id = any(v_best))
         group by pl.eingangsdatum, pl.gebindeart
      loop
        continue when g.n < 3 or g.n_drin::numeric / g.n < 0.8;
        insert into zuordnung_neu
        select pl.id, v_best_charge, w.charge_nr, w.auftrag_id, 'fuhre', 'angewandt',
               format('kam am %s mit %s weiteren %s-Paletten, die in der Arbeit %s lagen (%s von %s der Fuhre)',
                      to_char(g.eingangsdatum, 'DD.MM.'), g.n_drin, coalesce(g.gebindeart, 'Gebinde'), w.auftrag_id, g.n_drin, g.n)
          from palette pl
         where coalesce(pl.charge_nr_journal, pl.charge_nr) = v_best_charge
           and pl.eingangsdatum = g.eingangsdatum and coalesce(pl.gebindeart, '') = coalesce(g.gebindeart, '')
           and not (pl.id = any(v_best)) and not (pl.id = any(v_eigen)) and not (pl.id = any(v_vergeben))
        on conflict (palette_id) do nothing;
        v_vergeben := v_vergeben || array(select zn.palette_id from zuordnung_neu zn where zn.auftrag_id = w.auftrag_id and zn.art = 'fuhre');
      end loop;
    end if;
  end loop;

  -- Abgleichen: Was die Regel angelegt hat und keinen Beleg mehr hat, geht;
  -- was der Betriebsleiter gesetzt hat (geaendert_ts), bleibt, wie er es will.
  delete from palette_zuordnung pz
   where pz.geaendert_ts is null and pz.stand <> 'zurueckgenommen'
     and not exists (select 1 from zuordnung_neu zn where zn.palette_id = pz.palette_id
                        and zn.nach_charge_nr = pz.nach_charge_nr and zn.von_charge_nr = pz.von_charge_nr);
  update palette_zuordnung pz set stand = zn.stand, grund = zn.grund, auftrag_id = zn.auftrag_id, art = zn.art
    from zuordnung_neu zn
   where zn.palette_id = pz.palette_id and pz.geaendert_ts is null and pz.stand <> 'zurueckgenommen'
     and (pz.stand, pz.grund, pz.art) is distinct from (zn.stand, zn.grund, zn.art);
  insert into palette_zuordnung (palette_id, von_charge_nr, nach_charge_nr, auftrag_id, art, stand, grund)
  select zn.palette_id, zn.von_charge_nr, zn.nach_charge_nr, zn.auftrag_id, zn.art, zn.stand, zn.grund from zuordnung_neu zn
  on conflict (palette_id) do nothing;

  -- Anwenden: jede Palette auf die Charge, die gilt — der Trigger rechnet sie aus.
  perform set_config('kuerbis.zuordnung', 'an', true);
  update palette pl set charge_nr = pl.charge_nr
   where pl.charge_nr is distinct from coalesce(
           (select z2.nach_charge_nr from palette_zuordnung z2
             where z2.palette_id = pl.id and z2.stand = 'angewandt' and z2.von_charge_nr = pl.charge_nr_journal),
           pl.charge_nr_journal, pl.charge_nr);
  get diagnostics v_n = row_count;
  perform set_config('kuerbis.zuordnung', '', true);
  return v_n;
end $function$;

-- ---------- Stand ----------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 135 $$;
