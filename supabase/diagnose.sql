-- =====================================================================
-- Kürbis-Verlust-Tracking — Diagnose für den SQL-Editor
--
-- Wenn die App eine rohe Fehlermeldung zeigt (etwa „numeric field
-- overflow"): diese Datei komplett in den Supabase-SQL-Editor einfügen und
-- ausführen. Sie ändert nichts. Unten erscheint eine Tabelle: welchen
-- Stand die Datenbank hat, welche Auswertungs-Sicht scheitert und was in
-- den Rohdaten auffällig ist. Das Ergebnis lässt sich kopieren und
-- weitergeben.
-- =====================================================================
create temp table if not exists diagnose (nr serial, was text, befund text);
truncate diagnose;

do $$
declare v text; v_n bigint; v_stand text;
begin
  -- 1. Stand der Datenbank
  begin
    execute 'select schema_stand()' into v_stand;
    insert into diagnose (was, befund) values ('Stand der Datenbank', 'Migration ' || v_stand);
  exception when undefined_function then
    insert into diagnose (was, befund) values ('Stand der Datenbank',
      'älter als 0057 — setup.sql noch einmal ausführen (README, Schritt 3)');
  end;

  -- 2. Rechnet die Auswertung durch?
  begin
    perform auswertung_aktualisieren();
    insert into diagnose (was, befund) values ('Auswertung neu rechnen', 'läuft durch');
  exception when others then
    insert into diagnose (was, befund) values ('Auswertung neu rechnen', 'FEHLER: ' || sqlerrm);
  end;

  -- 3. Jede Sicht, die der Überblick lädt
  foreach v in array array['v_hochrechnung','v_massenbilanz','v_datenlage','v_plausibilitaet',
      'v_kaliber_verteilung','v_schimmel_kurve_anzeige','v_schimmel_modell','v_selektionsverdacht',
      'v_saisonbilanz','v_schimmel_punkte','v_hochrechnung_basis','v_naechste_charge',
      'v_koeff_verdunstung','v_koeff_ausschuss','v_koeff_nebenkanal','v_koeff_ueberfuellung',
      'v_wiegung_kennzahl','v_marge_buch','v_gewichtsverteilung','v_verarbeitung_alter',
      'v_durchsatz','v_ueberfuellung_kaeufer','v_datenqualitaet','v_saisonverlauf','v_koeff_gebinde',
      'v_charge_kohorte','v_fax_beobachtung','v_ausschuss_beobachtung','v_lieferung_masse'] loop
    begin
      execute format('select count(*) from %I', v) into v_n;
    exception when others then
      insert into diagnose (was, befund) values ('Sicht ' || v, 'FEHLER: ' || sqlerrm);
    end;
  end loop;
  if not exists (select 1 from diagnose where was like 'Sicht %') then
    insert into diagnose (was, befund) values ('Sichten des Überblicks', 'alle lesbar');
  end if;

  -- 4. Rohdaten, die Formeln sprengen können
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

  select coalesce(round(min(mittel), 6), 0)::text || ' … ' || coalesce(round(max(mittel), 6), 0)::text into v_stand
    from v_koeff_verdunstung;
  insert into diagnose (was, befund) values ('Verdunstungsrate je Tag (kleinste … grösste)', v_stand);
end $$;

select nr, was, befund from diagnose order by nr;
