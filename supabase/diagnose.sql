-- =====================================================================
-- Kürbis-Verlust-Tracking — Diagnose für den SQL-Editor
--
-- Wenn die App eine rohe Fehlermeldung zeigt: diese Datei komplett in den
-- Supabase-SQL-Editor einfügen und ausführen. Sie ändert nichts. Unten
-- erscheint eine Tabelle: welchen Stand die Datenbank hat, welche Sicht
-- scheitert und woran, und welche Grössen aus dem Rahmen fallen. Das
-- Ergebnis lässt sich markieren, kopieren und weitergeben.
-- =====================================================================
create temp table if not exists diagnose (nr serial, was text, befund text);
truncate diagnose;

do $$
declare v text; v_n bigint; v_txt text; v_detail text; v_fehler int := 0;
        v_zeile record;
begin
  -- 1. Stand der Datenbank
  begin
    execute 'select schema_stand()' into v_txt;
    insert into diagnose (was, befund) values ('Stand der Datenbank', 'Migration ' || v_txt);
  exception when undefined_function then
    insert into diagnose (was, befund) values ('Stand der Datenbank',
      'älter als 0057 — setup.sql noch einmal ausführen (README, Schritt 3)');
  end;

  -- 2. Rechnet die Auswertung durch?
  begin
    perform auswertung_aktualisieren();
    insert into diagnose (was, befund) values ('Auswertung neu rechnen', 'läuft durch');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    insert into diagnose (was, befund) values ('Auswertung neu rechnen',
      'FEHLER: ' || sqlerrm || coalesce(' — ' || v_detail, ''));
  end;

  -- 3. Jede Sicht, die das Dashboard lädt — mit „select *", nicht mit
  --    „count(*)": Postgres wertet die Spaltenausdrücke sonst gar nicht aus,
  --    und genau daran ging die erste Diagnose vorbei.
  foreach v in array array['v_hochrechnung','v_massenbilanz','v_datenlage','v_plausibilitaet',
      'v_kaliber_verteilung','v_schimmel_kurve_anzeige','v_schimmel_modell','v_selektionsverdacht',
      'v_saisonbilanz','v_schimmel_punkte','v_hochrechnung_basis','v_naechste_charge',
      'v_koeff_verdunstung','v_koeff_ausschuss','v_koeff_nebenkanal','v_koeff_ueberfuellung',
      'v_wiegung_kennzahl','v_marge_buch','v_gewichtsverteilung','v_verarbeitung_alter',
      'v_durchsatz','v_ueberfuellung_kaeufer','v_datenqualitaet','v_saisonverlauf','v_koeff_gebinde',
      'v_charge_kohorte','v_fax_beobachtung','v_ausschuss_beobachtung','v_lieferung_masse',
      'v_verlust_ranking','v_kaskade','v_auftrag_masse','v_schimmel_beobachtung',
      'v_lieferung_kohorte','v_koeff_palette_netto','v_kontrolle_vorschlag','v_kaskade_basis',
      'v_ausgang_kennzahl','v_palox_stand','v_schimmel_menge','v_kohorte_anteil'] loop
    begin
      execute format('select count(*) from (select * from %I) q', v) into v_n;
    exception when others then
      v_fehler := v_fehler + 1;
      get stacked diagnostics v_detail = pg_exception_detail;
      insert into diagnose (was, befund) values ('Sicht ' || v,
        'FEHLER: ' || sqlerrm || coalesce(' — ' || v_detail, ''));
    end;
  end loop;
  if v_fehler = 0 then
    insert into diagnose (was, befund) values ('Sichten des Dashboards', 'alle lesbar');
  end if;

  -- 3b. Sind alle Zahlenschranken abgesichert? (0059)
  begin
    select count(*) into v_n
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('v','m')
       and c.relname not in ('mv_auftrag_masse','mv_sortier_lauf_masse','mv_kaliber_verteilung')
       and regexp_count(pg_get_viewdef(c.oid, true), '::numeric\(\d+,\d+\)')
           <> regexp_count(pg_get_viewdef(c.oid, true), 'zahl\(');
    insert into diagnose (was, befund) values ('Sichten mit ungesicherter Zahlenschranke',
      v_n || case when v_n > 0 then ' — setup.sql ist älter als 0059' else ' (alle abgesichert)' end);
  exception when others then
    insert into diagnose (was, befund) values ('Sichten mit ungesicherter Zahlenschranke',
      'nicht prüfbar: ' || sqlerrm);
  end;

  -- 4. Die Grössenordnungen, die einen Überlauf erklären
  begin
    select 'Eingang ' || round(coalesce(sum(eingang_kg), 0) / 1000.0, 1) || ' t'
      into v_txt from v_hochrechnung_basis;
    insert into diagnose (was, befund) values ('Wareneingang (Erntejournal)', v_txt);
    select 'Ausgang ' || round(coalesce(sum(masse_kg), 0) / 1000.0, 1) || ' t aus '
           || count(*) || ' Lieferungen' into v_txt from v_lieferung_masse;
    insert into diagnose (was, befund) values ('Warenausgang (Lieferscheine)', v_txt);
  exception when others then
    insert into diagnose (was, befund) values ('Ein- und Ausgang', 'FEHLER: ' || sqlerrm);
  end;

  begin
    select 'grösste Portion ' || round(max(m0)) || ' kg · Rate bis ' || round(max(r), 6)
           || ' · Schimmelanteil bis ' || round(max(f), 4) || ' · Sockel bis ' || round(max(a0), 4)
           || ' · Lagertage bis ' || round(max(alter_tage))
      into v_txt from mv_kaskade;
    insert into diagnose (was, befund) values ('Kaskade, Extremwerte', coalesce(v_txt, 'leer'));
  exception when others then
    insert into diagnose (was, befund) values ('Kaskade, Extremwerte', 'FEHLER: ' || sqlerrm);
  end;

  begin
    select 'k=' || round(k, 4) || ' · var_achse=' || round(var_achse, 6)
           || ' · var_k=' || round(var_k, 6) || ' · Sockel=' || round(sockel, 4)
           || ' · Chargen=' || c_chargen || ' · brauchbar=' || brauchbar
      into v_txt from v_schimmel_modell;
    insert into diagnose (was, befund) values ('Verderbsmodell', coalesce(v_txt, 'nicht gerechnet'));
  exception when others then
    insert into diagnose (was, befund) values ('Verderbsmodell', 'FEHLER: ' || sqlerrm);
  end;

  begin
    select string_agg(strom || ': ' || coalesce(round(kg)::text, '—')
                      || ' [' || coalesce(round(kg_unten)::text, '—') || ' … '
                      || coalesce(round(kg_oben)::text, '—') || ']', ' · ')
      into v_txt from v_verlust_ranking;
    insert into diagnose (was, befund) values ('Ströme mit Bereich (kg)', coalesce(v_txt, 'keine'));
  exception when others then
    insert into diagnose (was, befund) values ('Ströme mit Bereich', 'FEHLER: ' || sqlerrm);
  end;

  -- 5. Rohdaten, die Formeln sprengen können
  select count(*) into v_n from verdunstung_wiegung w
    join gebinde g on g.art = w.gebindeart
   where w.brutto_jetzt_kg - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste
         > (w.brutto_damals_kg - coalesce(w.kisten, 0) * g.tara_kg_pro_kiste) * 1.01;
  insert into diagnose (was, befund) values ('Wägungen, bei denen die Palette schwerer wurde (über 1 %)',
    v_n || case when v_n > 0 then ' — unter Messungen → Auffälligkeiten nachsehen (Gebindeart, Kistenzahl, Zahlendreher)' else '' end);

  select count(*) into v_n from palette
   where eingangsdatum > current_date or eingangsdatum < current_date - 400;
  insert into diagnose (was, befund) values ('Paletten mit Eingangsdatum in der Zukunft oder älter als 400 Tage', v_n::text);

  select count(*) into v_n from auftrag a
   where a.abgebrochen_ts is null
     and a.start_ts::date < (select min(p.eingangsdatum) from palette p where p.charge_nr = a.charge_nr);
  insert into diagnose (was, befund) values ('Arbeiten, die vor dem ersten Eingang ihrer Charge begonnen haben', v_n::text);

  select count(*) into v_n from sortier_gewicht where gewicht_g > 100000 or anzahl > 100000;
  insert into diagnose (was, befund) values ('Sortier-CSV-Zeilen über 100 kg je Kürbis oder über 100 000 Stück', v_n::text);

  select coalesce(round(min(mittel), 6), 0)::text || ' … ' || coalesce(round(max(mittel), 6), 0)::text
    into v_txt from v_koeff_verdunstung;
  insert into diagnose (was, befund) values ('Verdunstungsrate je Tag (kleinste … grösste)', v_txt);

  select coalesce((select (wert #>> '{}') from einstellung where schluessel = 'soll_kg_pro_kiste'), 'nicht gesetzt')
    into v_txt;
  insert into diagnose (was, befund) values ('Sollgewicht je Kiste (Einstellung)', v_txt);

  -- Zusagen, die wegen vorhandener Zeilen unbestätigt bleiben.
  --
  -- Vier Prüfbedingungen sind **nach** den Daten ins Schema gekommen. Für
  -- neue Zeilen gelten sie ab dem ersten Tag; ob die vorhandenen sie
  -- erfüllen, sieht Postgres erst beim Bestätigen nach. setup.sql bestätigt
  -- jede, für die kein Verstoss vorliegt, und lässt die übrigen in Ruhe —
  -- vorher brach es an dieser Stelle ab und rollte das ganze Einrichten
  -- zurück (0067).
  --
  -- Hier steht, welche Zeilen dahinterstehen. Sie sind nicht kaputt: Sie
  -- sind aus einer Zeit, in der die App weniger verlangt hat. Wer sie
  -- ergänzt, kann setup.sql erneut ausführen; die Zusage wird dann bestätigt.
  for v_zeile in
    select c.conrelid::regclass::text as tabelle, c.conname as name,
           pg_get_expr(c.conbin, c.conrelid) as bedingung
      from pg_constraint c
     where c.connamespace = 'public'::regnamespace and c.contype = 'c'
       and not c.convalidated
     order by c.conname
  loop
    begin
      execute format('select count(*) from %s where not (%s)',
                     v_zeile.tabelle, v_zeile.bedingung) into v_n;
    exception when others then
      v_n := null;
    end;
    if coalesce(v_n, 0) > 0 then
      insert into diagnose (was, befund) values (
        format('Zusage "%s" auf %s noch nicht bestätigt', v_zeile.name, v_zeile.tabelle),
        format('%s vorhandene Zeile(n) erfüllen sie nicht — für neue Zeilen gilt sie. '
               || 'Bedingung: %s', v_n, v_zeile.bedingung));
    end if;
  end loop;
end $$;

select nr, was, befund from diagnose order by nr;
