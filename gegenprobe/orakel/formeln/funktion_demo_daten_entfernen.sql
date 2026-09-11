-- funktion: demo_daten_entfernen()
-- Löscht restlos alles, was demo_daten_laden() angelegt hat. Echte Daten bleiben unberührt — erkannt wird die Demo an bemerkung = 'DEMO', extern_id 'demo-…' und datei_name 'DEMO-…'.

CREATE OR REPLACE FUNCTION public.demo_daten_entfernen()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter entfernen.';
  end if;

  -- Reihenfolge ist wichtig: verdunstung_wiegung und sortier_lauf hängen mit
  -- "on delete set null" am Auftrag — würde man den Auftrag zuerst löschen,
  -- blieben ihre Zeilen verwaist zurück und zählten weiter mit.
  delete from verdunstung_wiegung
   where auftrag_id in (select id from auftrag where bemerkung = 'DEMO')
      or bemerkung = 'DEMO-KONTROLLE';
  delete from ausgang_wiegung
   where auftrag_id in (select id from auftrag where bemerkung = 'DEMO');
  delete from sortier_gewicht
   where lauf_id in (select id from sortier_lauf where datei_name like 'DEMO-%');
  delete from sortier_lauf where datei_name like 'DEMO-%';

  -- Der Rest hängt mit "on delete cascade" am Auftrag
  delete from lieferung where bemerkung = 'DEMO';      -- lieferung_import kaskadiert
  delete from ausgang_zeile where quelle = 'DEMO';
  delete from ausgang_artikel where bemerkung = 'DEMO';
  delete from ausgang_quelle where code = 'DEMO' and bemerkung = 'DEMO';
  delete from auftrag where bemerkung = 'DEMO';
  delete from charge_vorlauf where bemerkung like 'DEMO%';
  delete from palette where extern_id like 'demo-%';
  delete from sortierschema where bemerkung like 'DEMO%';
  -- Nur die von der Demo angelegten Käufer, und auch die nur, wenn nichts
  -- mehr an ihnen hängt. Ein Käufer, den der Betrieb selbst eingetragen hat,
  -- bleibt — auch wenn er zufällig denselben Code trägt.
  delete from kaeufer k where k.bemerkung = 'DEMO'
     and not exists (select 1 from auftrag a where a.kaeufer = k.code)
     and not exists (select 1 from sortierschema s where s.kaeufer = k.code);

  -- Kein Neurechnen hier — siehe demo_daten_laden(): eigener Aufruf danach.
  return (
    select format('Demo-Daten entfernt. Übrig: %s Paletten, %s Arbeiten, %s Sortierläufe.',
                  (select count(*) from palette),
                  (select count(*) from auftrag),
                  (select count(*) from sortier_lauf))
  );
end $function$
