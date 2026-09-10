-- =====================================================================
-- 0068 — Was die Gegenrede übrig gelassen hat
--
-- Runde M hat das System siebenmal vermessen und daraus 110 Verdachte
-- gezogen. Jeder wurde am laufenden System nachgemessen; jeder, der die
-- Messung überstand, wurde einem zweiten Leser vorgelegt mit dem
-- ausdrücklichen Auftrag, ihn zum Einsturz zu bringen.
--
-- Von den Verdachten, die diese zweite Prüfung vollständig durchlaufen
-- haben, blieben drei stehen. Sie stehen hier — mit den Zahlen des
-- Gegenlesers, nicht denen des Aufschreibers, denn der Gegenleser hat
-- mehrere davon nach unten korrigiert.
--
-- Was dabei genauso zählt: **zwölf Verdachte sind an der Gegenrede
-- zerbrochen**, und fast immer nach demselben Muster — die Rohzahlen
-- reproduzierten sich exakt, der Satz darüber nicht. „Der Freiheitsgrad
-- wird von einer Sorte mit 0.18 % Varianzanteil gesetzt" etwa: die
-- 0.18 % waren ungewichtet gerechnet, richtig sind 0.015 %, und ohne
-- diese Sorte setzt eine andere denselben Freiheitsgrad. Der Befund
-- dahinter stimmt trotzdem — nur eben aus einem anderen Grund.
--
-- ---------------------------------------------------------------------
-- 1. Das Neurechnen steht jedem Angemeldeten offen
--
-- `auswertung_schritt()` und `auswertung_aktualisieren()` sind
-- SECURITY DEFINER und prüfen nichts. Gemessen: Der Arbeiter Tomasz
-- (`ist_admin()` = f, `ist_aktiv()` = t) lässt beide durchlaufen. Ein
-- Lauf dauert 2 960 ms und nimmt dabei AccessExclusiveLock auf jede
-- gespeicherte Ansicht — `refresh ... concurrently` kommt im ganzen
-- Projekt nicht vor. Ein paralleler Leser von `erg_gewichte` wartete
-- gemessen **2 897 ms**, gegen höchstens 1.34 ms im Ruhezustand.
--
-- Die Oberfläche ruft das Neurechnen nur von den Betriebsleiterseiten
-- aus, und die sind in `src/App.tsx` bereits hinter `istAdmin`
-- weggeschlossen (`/dashboard`, `/ursachen`, `/chargen`, `/messungen`,
-- `/betrieb`). Es fehlt allein die Tür auf der Datenbankseite: Wer den
-- Aufruf direkt an PostgREST schickt, kommt am Riegel der Oberfläche
-- vorbei.
--
-- Der Wächter lässt ausdrücklich durch, wer **ohne Anmeldung** kommt —
-- also die Prüfstände, die Simulation und `demo_bauen.sh`, die als
-- Eigentümer der Datenbank laufen. Sonst wäre die halbe Werkstatt tot,
-- und ein Wächter, der die eigenen Prüfungen erschlägt, wird beim
-- ersten Ärger wieder ausgebaut.
--
-- ---------------------------------------------------------------------
-- 2. `erg_punkte` rechnet dieselbe Sicht ein zweites Mal
--
-- `erg_punkte` und `mv_schimmel_punkte` haben zeichengleiche
-- Definitionen und denselben Inhalt (142 Zeilen, `except` in beide
-- Richtungen null). Beide werden bei jedem Neurechnen aus
-- `v_schimmel_punkte` gefüllt — dieselbe Rechnung, zweimal.
--
-- Die Schwestern machen es anders: `erg_kaliber` liest
-- `v_kaliber_verteilung`, und das ist `select * from
-- mv_kaliber_verteilung` — eine billige Kopie. Dasselbe bei
-- `erg_modell`. Nur bei den Punkten fehlt die Hülle.
--
-- Gemessen im A/B-Versuch auf derselben Datenbank, je neun Läufe
-- abwechselnd: **103.2 ms von 3 016.7 ms**, also 3.42 %, plus 120 kB
-- doppelt gespeichert. Der Gegenleser hat dabei zwei Einschränkungen
-- gefunden, die dazugehören: 48–55 ms davon sind reine Planzeit und
-- damit von der Datenmenge unabhängig — auf einer grösseren Saison
-- fällt der Prozentsatz. Und die beiden Fassungen können nie
-- auseinanderlaufen, weil sie in derselben Transaktion entstehen. Es
-- geht also um Zeit und Platz, nicht um Richtigkeit.
--
-- ---------------------------------------------------------------------
-- 3. `zahl()` prüft die Grenze vor dem Runden
--
-- `zahl(p_wert, p_stellen, p_grenze)` vergleicht `abs(p_wert)` mit der
-- Grenze und rundet **danach**. Ein Wert knapp unter der Grenze kommt
-- durch die Prüfung und wird beim Runden über sie gehoben; die
-- Zielspalte `numeric(14,2)` nimmt ihn dann nicht mehr, und das ganze
-- Neurechnen bricht ab.
--
-- Der Gegenleser hat das Fenster ausgemessen, in dem das passieren
-- kann: 0.005 kg breit, bei 10¹² kg. Das ist ein Faktor von rund drei
-- Millionen von jeder Zahl entfernt, die in diesem Betrieb vorkommt.
-- Der Befund bleibt also richtig und folgenlos — und die Reparatur ist
-- eine Zeile, die Prüfung und Guss auf denselben Wert stellt.
-- =====================================================================

-- ---------- 1. Neurechnen ist Sache des Betriebsleiters ------------------

create or replace function auswertung_schritt(p_schritt integer) returns jsonb
language plpgsql security definer set search_path = public set jit = 'off'
as $$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
begin
  -- Wer ohne Anmeldung kommt, ist der Eigentümer der Datenbank: die
  -- Prüfstände, die Simulation, das Einspielen der Demodaten. Wer angemeldet
  -- ist, muss Betriebsleiter sein — ein Lauf sperrt für rund drei Sekunden
  -- jede gespeicherte Ansicht.
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.'
      using errcode = '42501';
  end if;
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'mv_schimmel_punkte', 'mv_schimmel_modell',
                       'erg_punkte', 'erg_modell', 'erg_kurve', 'erg_selektion',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_ueberfuellung', 'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_verlauf', 'erg_bilanz', 'erg_marge',
                       'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  -- Schritt 1 bringt zuerst die Statistik der Rohtabellen auf Stand. Nach
  -- einem grossen Import (Saisonstart, Warenausgang, Demo) schätzt der Planer
  -- sonst mit Zahlen von vorher und wählt Pläne, die um Grössenordnungen
  -- danebenliegen: gemessen 33 Sekunden für Schritt 2, wo er mit frischer
  -- Statistik 1.1 braucht. Das Analysieren aller Rohtabellen kostet auf der
  -- Demo 0.2 Sekunden — der beste Handel im ganzen Rechenwerk.
  if p_schritt = 1 then
    for v_name in
      select c.relname
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r'
       order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
  end if;

  foreach v_name in array v_namen loop
    execute format('refresh materialized view %I', v_name);
    execute format('analyze %I', v_name);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),   -- nicht now(): das wäre der Beginn der Transaktion
           dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif p_schritt = 1 then
    update auswertung_stand
       set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  else
    update auswertung_stand
       set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5);
end $$;
comment on function auswertung_schritt(integer) is
  'Ein Schritt des Neurechnens. Nur für den Betriebsleiter — oder ohne Anmeldung, '
  'also für die Prüfstände als Eigentümer. Ein Lauf sperrt jede gespeicherte Ansicht '
  'für rund drei Sekunden (0068).';

create or replace function auswertung_aktualisieren() returns timestamptz
language plpgsql security definer set search_path = public set jit = 'off'
as $$
declare i int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.'
      using errcode = '42501';
  end if;
  for i in 1..5 loop
    perform auswertung_schritt(i);
  end loop;
  return now();
end $$;
comment on function auswertung_aktualisieren() is
  'Alle fünf Schritte des Neurechnens nacheinander. Nur für den Betriebsleiter — '
  'oder ohne Anmeldung, also für die Prüfstände als Eigentümer (0068).';

-- ---------- 2. Die Punkte werden nur noch einmal gerechnet ---------------
--
-- `erg_punkte` wird zur billigen Kopie von `mv_schimmel_punkte` — genau das
-- Muster, das `erg_kaliber` und `erg_modell` schon benutzen. `v_schimmel_punkte`
-- läuft damit einmal je Neurechnen statt zweimal.
--
-- Geändert wird das an der einen Stelle, an der die sechsundzwanzig
-- gespeicherten Ergebnisse entstehen: in der Liste aus 0061/0065. Ein
-- einzelnes „drop … create" nur für erg_punkte täte es hier **nicht**.
-- Die Schleife baut erg_punkte weiterhin mit, und in setup.sql stünden dann
-- zwei Bauanweisungen für denselben Namen — der Verdichter kann einen Namen
-- nicht aus einer Schleife herauslösen, deren Liste er nur als Text sieht.
-- Beim Bau brach setup.sql genau daran ab: „relation erg_punkte already
-- exists". Steht hier dagegen die ganze Liste, mit derselben Angabe für den
-- Verdichter, dann ist sie dieselbe Anweisung wie in 0065, und setup.sql
-- behält davon die letzte — diese.
-- verdichter: baut erg_gewichte erg_kaliber erg_gebinde erg_ausgang
-- verdichter: baut erg_lieferung erg_kohorte erg_punkte erg_modell erg_kurve
-- verdichter: baut erg_selektion erg_koeff_verdunstung erg_koeff_ausschuss
-- verdichter: baut erg_koeff_nebenkanal erg_koeff_ueberfuellung erg_wiegung
-- verdichter: baut erg_fax erg_ausschuss erg_verarbeitung_alter erg_durchsatz
-- verdichter: baut erg_bilanz erg_marge erg_massenbilanz erg_naechste_charge
-- verdichter: baut erg_datenlage erg_plausibilitaet erg_datenqualitaet
do $$
declare
  paar text[];
  paare text[][] := array[
    -- [erg-Name, Quelle]
    ['erg_gewichte',           'v_gewichtsverteilung'],
    ['erg_kaliber',            'v_kaliber_verteilung'],
    ['erg_gebinde',            'v_koeff_gebinde'],
    ['erg_ausgang',            'v_ausgang_kennzahl'],
    ['erg_lieferung',          'v_lieferung_masse'],
    ['erg_kohorte',            'v_charge_kohorte'],
    -- Seit 0068 die gespeicherte Fassung statt der Sicht: zeichengleich,
    -- und die Sicht läuft je Neurechnen einmal statt zweimal.
    ['erg_punkte',             'mv_schimmel_punkte'],
    ['erg_modell',             'v_schimmel_modell'],
    ['erg_kurve',              'v_schimmel_kurve_anzeige'],
    ['erg_selektion',          'v_selektionsverdacht'],
    ['erg_koeff_verdunstung',  'v_koeff_verdunstung'],
    ['erg_koeff_ausschuss',    'v_koeff_ausschuss'],
    ['erg_koeff_nebenkanal',   'v_koeff_nebenkanal'],
    ['erg_koeff_ueberfuellung','v_koeff_ueberfuellung'],
    ['erg_wiegung',            'v_wiegung_kennzahl'],
    ['erg_fax',                'v_fax_beobachtung'],
    ['erg_ausschuss',          'v_ausschuss_beobachtung'],
    ['erg_verarbeitung_alter', 'v_verarbeitung_alter'],
    ['erg_durchsatz',          'v_durchsatz'],
    ['erg_bilanz',             'v_saisonbilanz'],
    ['erg_marge',              'v_marge_buch'],
    ['erg_massenbilanz',       'v_massenbilanz'],
    ['erg_naechste_charge',    'v_naechste_charge'],
    ['erg_datenlage',          'v_datenlage'],
    ['erg_plausibilitaet',     'v_plausibilitaet'],
    ['erg_datenqualitaet',     'v_datenqualitaet']
  ];
begin
  foreach paar slice 1 in array paare loop
    execute format('drop materialized view if exists %I cascade', paar[1]);
    execute format('create materialized view %I as select * from %I with no data', paar[1], paar[2]);
    execute format('grant select on %I to authenticated', paar[1]);
    execute format('comment on materialized view %I is %L', paar[1],
                   format('%s, gespeichert für die App Erneuert mit auswertung_schritt().', paar[2]));
  end loop;
end $$;

-- Die Indizes der neu gebauten Ergebnisse. Ein „drop … cascade" nimmt sie
-- mit; ohne diese Zeilen hätte die Datenbank nach den Migrationen neun
-- Indizes weniger als nach setup.sql. Es müssen alle neun sein: Beim ersten
-- Anlauf stand `erg_verarbeitung_tag` nicht in der Liste, und der Abgleich in
-- supabase/test/run.sh hat genau diese eine Zeile gemeldet — „+INDEX
-- erg_verarbeitung_tag, nur aus setup.sql". Wer die Schleife wieder abschreibt,
-- schreibt diesen Block mit ab.
create index if not exists erg_gewichte_sorte     on erg_gewichte (sorte);
create index if not exists erg_ausgang_ts         on erg_ausgang (ts);
create index if not exists erg_lieferung_datum    on erg_lieferung (datum);
create index if not exists erg_kohorte_charge     on erg_kohorte (charge_nr, eingangsdatum);
create index if not exists erg_punkte_charge      on erg_punkte (charge_nr);
create index if not exists erg_wiegung_ts         on erg_wiegung (wiege_ts);
create index if not exists erg_fax_start          on erg_fax (start_ts);
create index if not exists erg_durchsatz_start    on erg_durchsatz (start_ts);
create index if not exists erg_verarbeitung_tag   on erg_verarbeitung_alter (tag);
comment on materialized view erg_punkte is
  'v_schimmel_punkte, gespeichert für die App Erneuert mit auswertung_schritt(). '
  'Seit 0068 eine Kopie von mv_schimmel_punkte statt einer zweiten Rechnung — '
  'gemessen 103 ms und 120 kB je Neurechnen.';

-- ---------- 3. zahl() prüft, was sie auch zurückgibt ---------------------

create or replace function zahl(p_wert numeric, p_stellen integer default 2,
                                p_grenze numeric default 100000000000)
returns numeric language sql immutable parallel safe set search_path = public
as $$
  select case when p_wert is not null and abs(round(p_wert, p_stellen)) < p_grenze
              then round(p_wert, p_stellen) end
$$;
comment on function zahl(numeric, integer, numeric) is
  'Rundet und lässt alles über der Grenze weg. Seit 0068 wird der **gerundete** '
  'Wert gegen die Grenze gehalten: vorher konnte ein Wert knapp darunter die '
  'Prüfung bestehen und beim Runden darüber gehoben werden, worauf numeric(14,2) '
  'ihn abwies und das ganze Neurechnen abbrach. Das Fenster war 0.005 kg breit '
  'bei 10^12 kg.';

-- ---------- 4. Stand der Datenbank --------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 68 $$;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;
