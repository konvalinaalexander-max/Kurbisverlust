-- =====================================================================
-- 0066 — Kein Kilo aus einer Lücke, auch nicht im Rechenweg
--
-- Nachlese zu 0064. Dieselbe Frage („was heisst hier null?") an drei
-- Stellen, die beim ersten Durchgang stehengeblieben sind — und an zwei
-- davon steht das Vorzeichen andersherum: Dort steht NULL, wo eine Null
-- beobachtet ist.
--
--   1. Der Rechenweg eines Verluststroms zeigt vier Teilbeträge: was an
--      ausgelieferter Ware schon passiert ist, was an der liegenden Ware
--      gerechnet ist, was jenseits der Messungen liegt und was beim
--      Abpacken noch zu erwarten ist. Alle vier entstehen als
--      `sum(...) filter (...)`, und eine Summe über keine Zeile ist in SQL
--      NULL. Gemeint ist aber „null Kilo in dieser Portion": Fax hat
--      nichts an der liegenden Ware, weil dort noch nicht abgepackt wurde;
--      die anderen fünf Ströme haben nichts zu erwarten, weil nur beim
--      Abpacken nachsortiert wird. Beides ist beobachtet, nicht unbekannt.
--      Nachweis: kg = kg_beobachtet + kg_projiziert gilt auf allen 366
--      Zeilen der Demosaison exakt — sobald man NULL als 0 liest. Genau
--      diese Verwechslung hat 0064 in v_hochrechnung_basis behoben
--      (`sum(fax_kg) filter (ausgelagert)`); hier steht sie eine Sicht
--      weiter, in v_verlust_je_gruppe.
--
--      Die Oberfläche hat sich mit `?? 0` beholfen. Damit stand im
--      Rechenweg eines *ungemessenen* Stroms „Ergebnis bis heute: nicht
--      gemessen" und zwei Zeilen darunter „Davon an ausgelieferter Ware:
--      0 kg" — dieselbe Sicht, zwei Antworten. Ab jetzt ist die Regel
--      eindeutig: Ist der Strom gemessen, sind alle vier Teilbeträge
--      Zahlen und ergeben zusammen die Gesamtzahl; ist er es nicht, sind
--      alle vier NULL. Dazwischen gibt es nichts.
--
--   2. Zwei Auslöser haben ein Nettogewicht erfunden. `ausschuss_netto_
--      setzen` und `schimmel_netto_setzen` rechnen brutto − Kisten × Tara
--      und schreiben das Ergebnis in die Pflichtspalte `kg` — mit
--      `coalesce(kisten, 0)` bzw. `coalesce(kisten, 1)` und
--      `coalesce(tara, 0)`. Fehlt die Kistenzahl, oder ist für die
--      Gebindeart keine Tara hinterlegt, wurde damit das **Brutto**
--      als Netto gespeichert und mit `gemessen = true` markiert. Das ist
--      derselbe Fehler wie bei der Palette in 0064, nur schlimmer: Dort
--      wurde er beim Lesen gemacht, hier wird er gespeichert.
--
--      Die Zeile bleibt trotzdem stehen — sie ist eine Beobachtung („eine
--      Kiste Kleines gewogen, 120 kg brutto"), nur eben keine Nettomasse.
--      Sie wird deshalb nicht abgewiesen, sondern auf `gemessen = false`
--      gesetzt: v_ausschuss_beobachtung und v_schimmel_menge lesen ohnehin
--      nur Gemessenes, und die Auffälligkeit unten zeigt die Lücke. Eine
--      Bedingung auf der Tabelle (wie `lieferung_hat_menge` in 0064) wäre
--      hier falsch — bei der Lieferung ist die Zeile ohne Menge
--      unbrauchbar, hier ist sie es nicht.
--
--   3. Die Auffälligkeit „Ausschuss-Tara" hat dasselbe Netto ein zweites
--      Mal nachgerechnet, wieder mit coalesce. Fehlte die Tara, kam als
--      „richtiges" Netto das Bruttogewicht heraus, die Prüfung schlug an
--      und gab die falsche Auskunft: „Die Gebinde-Tara wurde nach dem
--      Wiegen geändert." Sie wurde nicht geändert, sie fehlt. Jetzt
--      rechnet die Prüfung nur nach, wo sich etwas nachrechnen lässt —
--      und damit die Lücke nicht still aus der Prüfung fällt, steht sie
--      als eigene Art daneben: „Ausschuss ohne Tara".
--
--      Eine SQL-Eigenheit führt dabei genau in dieselbe Falle und ist es
--      wert, aufgeschrieben zu werden: **`greatest(null, 0)` ist 0, nicht
--      NULL.** Das blosse Entfernen der coalesce hätte also nichts
--      geholfen — der Vergleich hätte weiter angeschlagen, nur eine
--      Klammer weiter. Das Netto wird deshalb ausdrücklich geprüft,
--      bevor es verglichen wird.
--
-- Keine neue Funktion, keine neue Zahl, keine neue Bedienung. Drei
-- Stellen, an denen eine Lücke und eine gemessene Null verwechselt wurden.
-- =====================================================================

-- ---------- 1. Die vier Teilbeträge eines Stroms ------------------------
-- `sum(...) filter (...)` über keine Zeile ist null Kilo, nicht „unbekannt".
-- Unbekannt ist der Strom als Ganzes — und das steht schon im `case`
-- darüber: ohne `bekannt` bleiben alle vier NULL, mit `bekannt` sind alle
-- vier Zahlen.
create or replace view v_verlust_je_gruppe with (security_invoker = true) as
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
  'Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, Charge). kg_beobachtet ist gemessen, kg_projiziert auf noch nicht Gemessenes übertragen, kg_extrapoliert über den Messbereich hinaus gerechnet — drei verschiedene Sicherheiten, darum drei Spalten. Ist der Strom gemessen (bekannt), sind alle vier Teilbeträge Zahlen und kg_beobachtet + kg_projiziert = kg; ist er es nicht, sind alle vier NULL (0066).';

-- ---------- 2. Kein erfundenes Netto in der Datenbank -------------------
-- Beide Auslöser rechnen jetzt ohne coalesce. Kommt dabei nichts heraus,
-- bleibt die eingetragene Zahl stehen und die Wägung zählt nicht als
-- gemessen — die Auswertung liest nur Gemessenes (v_ausschuss_beobachtung,
-- v_schimmel_menge), und die Auffälligkeit unten nennt die Lücke beim
-- Namen. Vorher wurde das Bruttogewicht als Netto gespeichert.
create or replace function ausschuss_netto_setzen() returns trigger
language plpgsql
as $$
declare v_tara_kiste numeric; v_tara_palette numeric; v_netto numeric;
begin
  if new.brutto_kg is not null then
    select g.tara_kg_pro_kiste, g.tara_kg_palette
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    v_netto := new.brutto_kg - new.kisten * v_tara_kiste - v_tara_palette;
    if v_netto is null then
      -- Ohne Kistenzahl oder ohne hinterlegte Tara gibt es kein Netto (0066).
      new.gemessen := false;
    else
      new.kg := greatest(round(v_netto), 0);
      new.gemessen := true;
    end if;
  end if;
  return new;
end $$;
comment on function ausschuss_netto_setzen() is
  'Setzt kg auf das Netto aus Brutto, Kistenzahl und hinterlegter Tara. '
  'Fehlt eine der drei Angaben, gibt es kein Netto: die Zeile bleibt stehen, '
  'gemessen wird false, und v_plausibilitaet meldet „Ausschuss ohne Tara" (0066).';

create or replace function schimmel_netto_setzen() returns trigger
language plpgsql
as $$
declare v_tara_kiste numeric; v_tara_palette numeric; v_netto numeric;
begin
  if new.brutto_kg is not null then
    if new.palox_stand_kg is not null then
      raise exception 'Eine Messung ist entweder eine Palox-Ablesung oder eine Kistenwägung, nicht beides.';
    end if;
    select g.tara_kg_pro_kiste, g.tara_kg_palette
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    -- Ohne Palette braucht es die Palettentara nicht — dann ist sie 0 und
    -- nicht unbekannt. Die Kistentara braucht es immer.
    v_netto := new.brutto_kg - new.kisten * v_tara_kiste
             - case when new.mit_palette then v_tara_palette else 0 end;
    if v_netto is null then
      new.gemessen := false;
    else
      new.kg := greatest(round(v_netto), 0);
      new.gemessen := true;
    end if;
  end if;
  return new;
end $$;
comment on function schimmel_netto_setzen() is
  'Setzt kg auf das Netto aus Brutto, Kistenzahl und hinterlegter Tara (die '
  'Palettentara nur, wenn die Palette mitgewogen wurde). Fehlt eine nötige '
  'Angabe, gibt es kein Netto: die Zeile bleibt stehen und gemessen wird '
  'false — v_schimmel_menge liest nur Gemessenes (0066).';

-- ---------- 3. Ausschuss-Tara: prüfen, was prüfbar ist ------------------
-- Die Prüfung „stimmt das gespeicherte Netto noch zur heutigen Tara?"
-- braucht drei Angaben. Fehlt eine, gibt es kein Vergleichsnetto — und
-- statt einer erfundenen Zahl steht die Lücke daneben („Ausschuss ohne
-- Tara"). Wie bei der Palette in 0064: leer ist nicht null.
create or replace view v_plausibilitaet with (security_invoker = true) as
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
        END, m.brutto_kg, GREATEST(round(n.roh), 0::numeric)) AS befund,
    'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '::text || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
     CROSS JOIN LATERAL ( SELECT m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS roh) n
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND n.roh IS NOT NULL AND m.kg::numeric <> GREATEST(round(n.roh), 0::numeric)
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
    'Die gespeicherten Kilo bleiben, wie sie sind — geprüft werden können sie erst, '::text || 'wenn Gebindeart, Tara und Kistenzahl beisammen sind.'::text AS rat
   FROM ausschuss_messung m
     JOIN auftrag a ON a.id = m.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN gebinde g ON g.art = m.gebindeart
  WHERE m.brutto_kg IS NOT NULL AND a.abgebrochen_ts IS NULL AND m.brutto_kg - m.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette IS NULL
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
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette. 0066: „Ausschuss-Tara" rechnet nur nach, wo Kistenzahl und hinterlegte Tara da sind; fehlt eine, steht die Lücke als „Ausschuss ohne Tara" daneben.';

-- ---------- 4. Stand der Datenbank --------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 66 $$;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;
