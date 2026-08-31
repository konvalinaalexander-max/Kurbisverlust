-- Fingerabdruck des Schemas: jede Spalte, jede Ansicht, jede Funktion, jeder
-- Index, jede Zugriffsregel, jeder Auslöser, jede Bedingung, jedes Recht —
-- als eine sortierte Textliste.
--
-- Wozu: Eine Aktualisierung darf nicht "irgendwie durchlaufen", sie muss
-- dieselbe Datenbank hinterlassen wie eine Neueinrichtung. Sonst rechnet ein
-- Betrieb mit einer Ansicht, die es woanders längst anders gibt, und niemand
-- merkt es. Zwei Fingerabdrücke, ein `diff` — und die Frage ist beantwortet,
-- statt sie an Stichproben zu glauben.
--
-- Die Definitionen werden als md5 verglichen: Es geht um "gleich oder nicht",
-- nicht darum, tausend Zeilen SQL nebeneinanderzulegen.
\pset tuples_only on
\pset format unaligned

select 'SPALTE  '||table_name||'.'||column_name||'  '||data_type
       ||'  vorgabe='||coalesce(column_default,'-')||'  null='||is_nullable
  from information_schema.columns where table_schema = 'public' order by 1;

select 'ANSICHT  '||viewname||'  '||md5(definition)
  from pg_views where schemaname = 'public' order by 1;

select 'GESPEICHERT  '||matviewname||'  '||md5(definition)
  from pg_matviews where schemaname = 'public' order by 1;

select 'FUNKTION  '||p.oid::regprocedure||'  '||md5(pg_get_functiondef(p.oid))
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prokind in ('f', 'p') order by 1;

select 'INDEX  '||indexdef from pg_indexes where schemaname = 'public' order by 1;

select 'REGEL  '||c.relname||'.'||p.polname||'  '
       ||md5(coalesce(pg_get_expr(p.polqual, p.polrelid), '')
             ||coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')||p.polcmd::text)
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' order by 1;

select 'AUSLOESER  '||n.nspname||'.'||c.relname||'.'||t.tgname
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
 where not t.tgisinternal order by 1;

select 'BEDINGUNG  '||conrelid::regclass||'  '||conname||'  '||pg_get_constraintdef(oid)
  from pg_constraint where connamespace = 'public'::regnamespace order by 1;

select 'RECHT  '||table_name||'  '||grantee||'  '||privilege_type
  from information_schema.role_table_grants where table_schema = 'public' order by 1;
