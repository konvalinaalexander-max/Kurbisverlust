-- =====================================================================
-- 0083 — Der Ausschuss stand nicht auf einer Palette
--
-- Der Betrieb: „ich glaube es hat einen bug beim eintragen von zu klein
-- und zu gross … man kanns zwar eingeben - aber es gibt trotzdem immer
-- nur 0 ein."
--
-- Er hat recht, und der Fehler ist still. Die Ausschuss-Maske zieht vom
-- Brutto immer die volle Tara ab — Kisten UND Palette (25 kg). Was am Ende
-- einer Wasch-Arbeit zu klein oder zu gross war, sind aber oft ein, zwei
-- Kisten, die jemand direkt auf die Waage stellt. Eine Kiste mit 12 kg:
-- 12 − 1.5 − 25 = −14.5. Und beides, die Maske und der Auslöser
-- ausschuss_netto_setzen(), klemmten das mit greatest(…, 0) auf null.
-- Die Wägung sah gespeichert aus, das Netto war null, niemand sah, wo die
-- Kilo geblieben waren.
--
-- Die Faule-Maske hat den Schalter „Auf einer Palette gewogen" seit 0051,
-- und schimmel_messung die Spalte mit_palette dazu. Die Ausschuss-Maske hat
-- ihn nie bekommen. Das holt diese Migration nach — und sie nimmt die
-- Klammer weg: Ein negatives Netto ist kein „nichts", es ist ein
-- Widerspruch, und der wird gemeldet statt verschluckt.
--
-- Drei Dinge:
--
--   1. ausschuss_messung.mit_palette, Vorgabe true — so bleibt die
--      Bedeutung jeder bestehenden Zeile, wie sie war: mit Palettentara
--      gerechnet.
--
--   2. Beide Auslöser weisen ein negatives Netto zurück, mit einem Satz,
--      den der Arbeiter versteht. greatest(…, 0) gibt es nicht mehr — weder
--      beim Ausschuss noch beim Faulen.
--
--   3. Die bestehenden Nullen werden nachgerechnet, wo es keine Deutung
--      braucht: Ist das Brutto kleiner als die Palettentara plus die
--      Kisten, dann KANN keine Palette auf der Waage gestanden haben —
--      eine leere Palette wiegt allein schon mehr. Diese Zeilen bekommen
--      mit_palette = false, und der Auslöser rechnet ihr Netto neu.
--      Zeilen, bei denen eine kleine Zahl übrig blieb (30 kg brutto mit
--      zwei Kisten → 2 kg statt 27), lassen sich so nicht unterscheiden;
--      sie stehen als Auffälligkeit da, und in der Korrektur lässt sich
--      der Haken nachträglich setzen.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Die Spalte
-- ---------------------------------------------------------------------

alter table ausschuss_messung
  add column if not exists mit_palette boolean not null default true;
comment on column ausschuss_messung.mit_palette is
  'Stand die Ware beim Wiegen auf einer Palette? Nur dann wird die '
  'Palettentara abgezogen. Vorgabe true, damit die Zeilen von vor 0083 '
  'ihre Bedeutung behalten (0083).';

-- ---------------------------------------------------------------------
-- 2. Die Auslöser: ohne Klammer, mit Widerspruch
-- ---------------------------------------------------------------------

create or replace function ausschuss_netto_setzen() returns trigger
language plpgsql
as $$
declare v_tara_kiste numeric; v_tara_palette numeric; v_netto numeric; v_tara numeric;
begin
  if new.brutto_kg is not null then
    select g.tara_kg_pro_kiste, g.tara_kg_palette
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    -- Ohne Palette braucht es die Palettentara nicht — dann ist sie 0 und
    -- nicht unbekannt. Die Kistentara braucht es immer.
    v_tara  := new.kisten * v_tara_kiste
             + case when new.mit_palette then v_tara_palette else 0 end;
    v_netto := new.brutto_kg - v_tara;
    if v_netto is null then
      -- Ohne Kistenzahl oder ohne hinterlegte Tara gibt es kein Netto (0066).
      new.gemessen := false;
    elsif v_netto < 0 then
      -- Kein greatest(…, 0) mehr: Ein Brutto unter der Tara ist ein
      -- Widerspruch, keine leere Wägung. So kam bis 0083 jede Kiste, die
      -- ohne Palette auf der Waage stand, als null Kilo an.
      raise exception
        'Das Gewicht (% kg) ist kleiner als die Tara (% × % kg Kiste%) = % kg. So kann die Ware nicht gewogen worden sein — steht sie wirklich auf einer Palette?',
        new.brutto_kg, new.kisten, v_tara_kiste,
        case when new.mit_palette then format(' + Palette %s kg', v_tara_palette) else '' end,
        v_tara;
    else
      new.kg := round(v_netto);
      new.gemessen := true;
    end if;
  end if;
  return new;
end $$;
comment on function ausschuss_netto_setzen() is
  'Setzt kg auf das Netto aus Brutto, Kistenzahl und hinterlegter Tara — die '
  'Palettentara nur, wenn mit_palette (0083). Fehlt eine Angabe, gibt es kein '
  'Netto: die Zeile bleibt stehen, gemessen wird false (0066). Ein negatives '
  'Netto wird zurückgewiesen statt auf null geklemmt (0083).';

create or replace function schimmel_netto_setzen() returns trigger
language plpgsql
as $$
declare v_tara_kiste numeric; v_tara_palette numeric; v_netto numeric; v_tara numeric;
begin
  if new.brutto_kg is not null then
    if new.palox_stand_kg is not null then
      raise exception 'Eine Messung ist entweder eine Palox-Ablesung oder eine Kistenwägung, nicht beides.';
    end if;
    select g.tara_kg_pro_kiste, g.tara_kg_palette
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    v_tara  := new.kisten * v_tara_kiste
             + case when new.mit_palette then v_tara_palette else 0 end;
    v_netto := new.brutto_kg - v_tara;
    if v_netto is null then
      new.gemessen := false;
    elsif v_netto < 0 then
      raise exception
        'Das Gewicht (% kg) ist kleiner als die Tara (% × % kg Kiste%) = % kg. So kann das Faule nicht gewogen worden sein — steht es wirklich auf einer Palette?',
        new.brutto_kg, new.kisten, v_tara_kiste,
        case when new.mit_palette then format(' + Palette %s kg', v_tara_palette) else '' end,
        v_tara;
    else
      new.kg := round(v_netto);
      new.gemessen := true;
    end if;
  end if;
  return new;
end $$;
comment on function schimmel_netto_setzen() is
  'Setzt kg auf das Netto aus Brutto, Kistenzahl und hinterlegter Tara (die '
  'Palettentara nur, wenn die Palette mitgewogen wurde). Fehlt eine nötige '
  'Angabe, gibt es kein Netto: die Zeile bleibt stehen und gemessen wird '
  'false (0066). Ein negatives Netto wird zurückgewiesen (0083).';

-- ---------------------------------------------------------------------
-- 3. Die bestehenden Nullen, wo die Deutung zwingend ist
--
-- Der Auslöser oben ist schon die neue Fassung: mit_palette = false
-- genügt, das Netto rechnet er selbst nach.
-- ---------------------------------------------------------------------

do $$
declare v_n int;
begin
  with rep as (
    update ausschuss_messung m
       set mit_palette = false
      from gebinde g
     where g.art = m.gebindeart
       and m.brutto_kg is not null and m.kisten is not null
       and m.gemessen and m.mit_palette
       and m.kg = 0
       -- Mit Palette hätte es null (oder weniger) ergeben …
       and m.brutto_kg - m.kisten * g.tara_kg_pro_kiste - g.tara_kg_palette <= 0
       -- … ohne Palette bleibt etwas übrig. Dann stand keine drunter.
       and m.brutto_kg - m.kisten * g.tara_kg_pro_kiste > 0
    returning m.id)
  select count(*) into v_n from rep;
  if v_n > 0 then
    raise notice '0083: % Ausschuss-Wägungen standen nicht auf einer Palette — Netto nachgerechnet.', v_n;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. Was sich nicht von selbst deuten lässt, steht als Auffälligkeit da
--
-- Der Zusatz von 0064 wird vollständig wiederholt (create or replace view
-- verlangt das) und um einen Zweig verlängert: eine Ausschuss-Wägung „mit
-- Palette", deren Brutto kaum mehr wiegt als die leere Palette.
-- ---------------------------------------------------------------------

create or replace view v_plausibilitaet_0064_zusatz with (security_invoker = true) as
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
        END AS rat
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
    format('%s kg mehr ausgeliefert, als für diese Charge je als Eingang erfasst wurde '::text || '(%s kg Eingang, %s kg geliefert) — das sind %s %% des Eingangs'::text, round(h.ueberzaehlung_kg), round(h.eingang_kg), round(h.geliefert_kg), round(100::numeric * h.ueberzaehlung_kg / NULLIF(h.eingang_kg, 0::numeric))) AS befund,
    ('Fehlt im Erntejournal eine Palette dieser Charge? Oder ist ein Lieferschein auf '::text || 'die falsche Chargennummer gebucht? Beides lässt sich nachtragen; bis dahin ist '::text) || 'die Verlustquote dieser Charge zu hoch, weil ihr Eingang zu klein ist.'::text AS rat
   FROM v_hochrechnung_basis h
  WHERE h.ueberzaehlung_kg > 0::numeric
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format(('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette '::text || 'dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — gerechnet '::text) || 'wird deshalb mit der mittleren Tara der Charge, nicht mit ihrer eigenen.'::text, count(*), ap.brutto_zettel_kg, to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.brutto_zettel_kg IS NOT NULL AND ap.eingangsdatum IS NOT NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg)) AND NOT (EXISTS ( SELECT 1
           FROM v_palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg AND p.eingangsdatum = ap.eingangsdatum AND p.netto_kg IS NOT NULL))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg, ap.eingangsdatum
UNION ALL
 -- 0083: Eine Ausschuss-Wägung „mit Palette", deren Brutto kaum mehr ist
 -- als die leere Palette. Das kann stimmen — ein paar Kürbisse auf einer
 -- Palette —, aber meistens standen die Kisten direkt auf der Waage, und
 -- 25 kg Palette sind zu Unrecht abgezogen.
 SELECT 'Palette fraglich'::text AS art,
    m.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s: %s kg brutto in %s Kiste(n) %s, mit Palette gewogen — davon bleiben %s kg netto. Eine leere Palette wiegt allein %s kg.'::text,
           CASE m.art WHEN 'zu_klein' THEN 'Zu klein' ELSE 'Zu gross' END,
           m.brutto_kg, m.kisten, m.gebindeart, m.kg, g.tara_kg_palette) AS befund,
    'Standen die Kisten direkt auf der Waage? Dann in der Korrektur „mit Palette" abwählen — das Netto rechnet sich von selbst neu.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.gemessen AND m.mit_palette AND m.brutto_kg IS NOT NULL
    AND g.tara_kg_palette IS NOT NULL
    AND m.brutto_kg < 2 * g.tara_kg_palette
    AND a.abgebrochen_ts IS NULL;
grant select on v_plausibilitaet_0064_zusatz to authenticated;

-- ---------------------------------------------------------------------
-- 5. Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 83 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
