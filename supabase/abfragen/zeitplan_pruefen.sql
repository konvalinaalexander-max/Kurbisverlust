-- =====================================================================
-- Läuft der Zeitplan? (28. September, Nachtrag zu 0095)
--
-- Im Supabase-Dashboard: SQL Editor → New query → diese Datei ganz
-- einfügen → Run. Das Ergebnis (eine Zeile) als Bildschirmfoto an die
-- Runde am Programm schicken. Die Abfrage liest nur, sie ändert nichts.
--
-- Was die Spalten sagen:
--   projekt       echt oder beispiel — in welchem Projekt du gerade bist
--   active        der Job ist eingeschaltet
--   starter       1 = der Hintergrunddienst von pg_cron läuft, 0 = nicht
--   laeufe        wie oft dieser Job schon gelaufen ist
--   alle_laeufe   wie oft überhaupt irgendein Job gelaufen ist
--   letzte_meldung  Status und Meldung des letzten Laufs
-- =====================================================================
select
  (select wert #>> '{}' from public.einstellung where schluessel = 'betriebsmodus') as projekt,
  now() as jetzt,
  j.jobname, j.schedule, j.active, j.username, j.database,
  current_setting('cron.database_name', true) as cron_db,
  (select count(*) from pg_stat_activity where backend_type = 'pg_cron launcher') as starter,
  (select count(*) from cron.job_run_details r where r.jobid = j.jobid) as laeufe,
  (select count(*) from cron.job_run_details) as alle_laeufe,
  (select max(r.start_time) from cron.job_run_details r where r.jobid = j.jobid) as letzter_lauf,
  (select r.status || ': ' || coalesce(r.return_message, '')
     from cron.job_run_details r where r.jobid = j.jobid
    order by r.start_time desc limit 1) as letzte_meldung
from cron.job j;
