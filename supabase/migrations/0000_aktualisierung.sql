-- =====================================================================
-- 0000 — Vorbereitung: Platz machen für eine Aktualisierung
-- Kürbis-Verlust-Tracking
--
-- WOZU DAS DA IST
--
-- setup.sql ist die ganze Geschichte der Datenbank hintereinander. Auf einer
-- leeren Datenbank läuft sie glatt durch. Auf einer, die schon einen älteren
-- Stand trägt, nicht: `create view` stolpert über die Ansicht, die es schon
-- gibt, `create policy` über die Regel gleichen Namens. Früher stand deshalb
-- am Anfang eine Sperre, die den zweiten Durchlauf abgewiesen hat — mit der
-- Folge, dass eine einmal eingerichtete Datenbank nie wieder etwas Neues
-- bekommen hat. Ein Betrieb konnte monatelang auf einem alten Stand laufen
-- und hat es erst gemerkt, wenn die App eine Funktion suchte, die es dort
-- nie gegeben hat.
--
-- Statt abzuweisen, wird hier aufgeräumt: alles, was die Datenbank nur
-- *ausrechnet*, fliegt raus — Ansichten, Funktionen, Zugriffsregeln,
-- Auslöser. Danach sieht die Datenbank für den Rest von setup.sql aus wie
-- eine frische, und das Skript baut das Rechenwerk vollständig neu auf.
--
-- WAS DABEI NICHT ANGEFASST WIRD
--
-- Tabellen und ihr Inhalt. Jede Messung, jede Palette, jeder Auftrag bleibt
-- unberührt: gelöscht wird ausschliesslich, was sich aus diesen Daten wieder
-- herstellen lässt. Und weil das gesamte Skript in einer Transaktion läuft,
-- gibt es kein Dazwischen — entweder die Aktualisierung geht ganz durch,
-- oder die Datenbank steht unverändert da wie vorher.
--
-- Auf einer leeren Datenbank tut diese Datei nichts.
-- =====================================================================

do $$
declare
  z record;
begin
  -- Kein Kürbis-Schema vorhanden? Dann ist das eine Neueinrichtung und es
  -- gibt nichts wegzuräumen.
  if to_regclass('public.charge') is null then
    return;
  end if;

  raise notice 'Bestehende Datenbank erkannt — das Rechenwerk wird erneuert, die Daten bleiben.';

  -- 1. Zugriffsregeln. Zuerst, weil sie auf Funktionen wie ist_admin()
  --    zeigen; solange sie stehen, lässt sich die Funktion nicht löschen.
  for z in
    select p.polname, c.relname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
  loop
    execute format('drop policy if exists %I on public.%I', z.polname, z.relname);
  end loop;

  -- 2. Auslöser auf den eigenen Tabellen und der eine auf auth.users, der
  --    neuen Anmeldungen ein Profil gibt.
  for z in
    select t.tgname, c.relname, n.nspname
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where not t.tgisinternal
       and (n.nspname = 'public'
            or (n.nspname = 'auth' and t.tgname = 'on_auth_user_created'))
  loop
    execute format('drop trigger if exists %I on %I.%I', z.tgname, z.nspname, z.relname);
  end loop;

  -- 3. Gespeicherte Auswertungen und Ansichten. Erst die gespeicherten
  --    (relkind 'm'), dann die berechneten — `cascade` räumt mit, was
  --    aufeinander aufbaut, und setup.sql baut die Kette danach neu.
  --    Das Namensmuster v_ / mv_ ist die Konvention des Projekts; was
  --    jemand von Hand daneben angelegt hat, bleibt stehen.
  for z in
    select c.relname, c.relkind
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind in ('v', 'm')
       and c.relname ~ '^m?v_'
     order by case c.relkind when 'm' then 0 else 1 end
  loop
    if z.relkind = 'm' then
      execute format('drop materialized view if exists public.%I cascade', z.relname);
    else
      execute format('drop view if exists public.%I cascade', z.relname);
    end if;
  end loop;

  -- 4. Funktionen. Zum Schluss, wenn niemand mehr auf sie zeigt. Auch die
  --    Signatur muss weg und nicht nur der Name: 0032 hat aus
  --    palox_letzter_stand() eines mit Argument gemacht, und zwei
  --    Funktionen gleichen Namens verwirren PostgREST.
  for z in
    select p.oid::regprocedure::text as sig, p.prokind
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p')
  loop
    execute format('drop %s if exists %s cascade',
                   case z.prokind when 'p' then 'procedure' else 'function' end,
                   z.sig);
  end loop;
end $$;
