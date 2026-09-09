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

-- Beschreibungen zählen mit. Sie sind das, was im SQL-Editor und in der
-- Doku erklärt, was eine Zahl bedeutet — geht eine beim Verdichten von
-- setup.sql verloren, ist das ein Unterschied und soll auffallen.
select 'BESCHREIBUNG  '||c.relkind::text||' '||c.relname||'  '||md5(d.description)
  from pg_description d
  join pg_class c on c.oid = d.objoid and d.objsubid = 0
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' order by 1;

select 'BESCHREIBUNG  spalte '||c.relname||'.'||a.attname||'  '||md5(d.description)
  from pg_description d
  join pg_class c on c.oid = d.objoid
  join pg_attribute a on a.attrelid = c.oid and a.attnum = d.objsubid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and d.objsubid > 0 order by 1;

select 'BESCHREIBUNG  '||p.oid::regprocedure||'  '||md5(d.description)
  from pg_description d
  join pg_proc p on p.oid = d.objoid
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' order by 1;

-- Rechte auf Funktionen: Wer darf verlust_ranking() rufen? Steht nicht in
-- role_table_grants und fiel darum bisher durch.
select 'RECHT  '||p.oid::regprocedure||'  '||coalesce(g.grantee, '(nur Eigentümer)')||'  '||coalesce(g.privilege_type, '-')
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  left join information_schema.role_routine_grants g
         on g.specific_schema = 'public' and g.specific_name = p.proname || '_' || p.oid
 where n.nspname = 'public' and p.prokind in ('f', 'p') order by 1;
