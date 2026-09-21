-- =====================================================================
-- 0082 — Zwei Arten von Sortierdatei
--
-- Der Betrieb hat eine Annahme korrigiert, auf der die Sortier-CSV seit
-- dem ersten Tag ruhte: „ich dachte jedesmal wenn ich sortiere gibt es
-- eine neue CSV - aber dem ist nicht so - stattdessen heisst die datei
-- jedesmal z.b. 1614 - also es gibt nur eine 1614 - und bei jedem
-- sortieren wird einfach unterhalb weiter angefügt."
--
-- Ab Oktober 2026 tragen die Dateien wieder ein Datum im Namen
-- (`1614_07_10_26`, beliebige Trenner). Die Dateien der bisherigen Saison
-- — rund ein Monat Sortieren je Charge — bleiben aber, wie sie sind, und
-- müssen einlesbar sein. Also kennt die App von hier an zwei Arten:
--
--   'lauf'    ein Sortierlauf. Das Datum steht im Namen. Wie bisher.
--   'sammel'  eine Datei je Charge, kumulativ. Kein Datum, und der
--             nächste Upload enthält alles vom vorigen noch einmal.
--
-- Zwei Dinge macht die Sammeldatei kaputt, und beide still:
--
--   1. DOPPELZÄHLUNG. `roh_pruefsumme unique` schützt nur vor derselben
--      Datei — die gewachsene hat eine andere Prüfsumme und bringt die
--      alten Kürbisse ein zweites Mal mit. Niemand merkt es; die Charge
--      hat am Ende mehr sortiert, als sie je gewogen hat.
--      Gegenmittel: gespeichert wird nur das DELTA. Und weil die
--      Reinigung präfixstabil ist (src/lib/csv.ts, test/csv.test.ts),
--      genügt dafür eine Subtraktion — und eine negative Stufe ist der
--      Beweis, dass die Datei keine reine Erweiterung ist.
--
--   2. DAS ERFUNDENE DATUM. Ohne Datum im Namen nahm die App bisher den
--      Zeitstempel des Dateisystems. Bei einer Sammeldatei ist das der
--      Zeitpunkt des letzten Anhängens — für die Kürbisse vom ersten Tag
--      also Wochen zu spät. Daran hängt mehr, als man denkt:
--        · `betriebstag(l.datei_zeit)` ist der Sortiertag, ab dem die
--          Verdunstung rechnet (0079). Wochen zu spät heisst: zu wenig
--          Schwund, zu schwere Kürbisse im Lager.
--        · `lauf_neu_klassieren` wählt die Kaliberbänder nach diesem
--          Datum. Zu spät heisst: womöglich die falschen Bänder.
--      Gegenmittel: `datei_zeit` wird für eine Sammeldatei gar nicht
--      erst gesetzt. Stattdessen ein Zeitfenster (von .. bis) und ein
--      daraus abgeleiteter `sortiertag`, der sagt, woher er kommt —
--      dieselbe Bauart wie `masse_quelle` und wie das geschätzte
--      Chargenalter aus AB-50.
--
-- Nichts wird gelöscht: `datei_zeit` und `auftrag_id` bleiben mit allem,
-- was drinsteht. Für eine Sammeldatei sind sie leer — und leer ist nicht
-- null, sondern unbekannt.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Was für eine Datei war das, und für welchen Zeitraum gilt sie?
-- ---------------------------------------------------------------------

alter table sortier_lauf add column if not exists art text not null default 'lauf';
do $$ begin
  alter table sortier_lauf add constraint sortier_lauf_art_check
    check (art in ('lauf', 'sammel'));
exception when duplicate_object then null; end $$;
comment on column sortier_lauf.art is
  '''lauf'': ein Sortierlauf, das Datum steht im Dateinamen. ''sammel'': die '
  'kumulative Datei einer ganzen Charge ohne Datum, bei der die Maschine bei '
  'jedem Sortieren unten anhängt. Bei ''sammel'' trägt der Lauf nur das DELTA '
  'zur vorigen Lesung, damit nichts doppelt zählt (0082).';

alter table sortier_lauf add column if not exists von_ts timestamptz;
alter table sortier_lauf add column if not exists bis_ts timestamptz;
comment on column sortier_lauf.von_ts is
  'Frühester Zeitpunkt, zu dem ein Kürbis dieser Lesung sortiert worden sein '
  'kann: das Ende der vorigen Lesung derselben Sammeldatei, sonst der erste '
  'Eingang der Charge — vor dem Eingang kann nichts sortiert worden sein. Bei '
  'einer Lauf-Datei gleich datei_zeit (0082).';
comment on column sortier_lauf.bis_ts is
  'Spätester Zeitpunkt: der Zeitstempel der Datei beim Hochladen, sonst der '
  'Zeitpunkt des Einlesens. Bei einer Lauf-Datei gleich datei_zeit (0082).';

alter table sortier_lauf add column if not exists sortiertag date;
alter table sortier_lauf add column if not exists sortiertag_quelle text;
comment on column sortier_lauf.sortiertag is
  'Der Tag, an dem die Kürbisse dieser Lesung gewogen wurden — der Startpunkt '
  'der Verdunstungsrechnung. Bei einer Lauf-Datei abgelesen, bei einer '
  'Sammeldatei abgeleitet. Leer heisst unbekannt, nicht heute (0082).';
comment on column sortier_lauf.sortiertag_quelle is
  'Woher der Sortiertag kommt: ''datei'' (aus dem Dateinamen), ''arbeit'' (genau '
  'eine Sortier-Arbeit der Charge im Zeitfenster), ''arbeiten-mittel'' (mehrere, '
  'nach gezählten Paletten gewichtet), ''fenster-mitte'' (keine Arbeit erfasst — '
  'die Mitte zwischen von_ts und bis_ts), ''betriebsleiter'' (von Hand gesetzt), '
  '''dateistempel'' (der Zeitstempel des Dateisystems — eine obere Schranke, kein '
  'Sortierdatum), ''gelesen'' (der Tag des Einlesens). '
  'Leer: kein Sortiertag bekannt (0082).';

alter table sortier_lauf add column if not exists vorgaenger_id bigint references sortier_lauf(id);
comment on column sortier_lauf.vorgaenger_id is
  'Die vorige Lesung derselben Sammeldatei. Macht die Kette der Lesungen '
  'nachvollziehbar: jede trägt nur, was seit der vorigen dazukam (0082).';

alter table sortier_lauf add column if not exists voll_n_roh int;
comment on column sortier_lauf.voll_n_roh is
  'Rohzeilen der GANZEN Datei bei dieser Lesung — n_roh zählt dagegen nur die '
  'Zeilen, die neu dazukamen. Bei einer Lauf-Datei sind beide gleich (0082).';

create index if not exists sortier_lauf_charge_art_idx on sortier_lauf (charge_nr, art, gelesen_ts);

-- ---------------------------------------------------------------------
-- 2. Was schon in der Datenbank liegt, ist eine Lauf-Datei
--
-- Alles Bisherige wurde als einzelner Lauf eingelesen und behält seine
-- Bedeutung. Der Sortiertag kommt aus dem Dateidatum, wo es eines gibt;
-- sonst aus dem Zeitpunkt des Einlesens — und sagt das auch.
-- ---------------------------------------------------------------------

-- `datei_zeit_quelle` hat von Anfang an festgehalten, WOHER das Datum kam.
-- Das wird hier gebraucht: Ein Datum aus dem Dateinamen ist abgelesen, eines
-- aus dem Zeitstempel des Dateisystems ist bestenfalls eine obere Schranke.
-- Wer beides gleich behandelt, macht aus einer Vermutung eine Messung.
update sortier_lauf
   set von_ts            = coalesce(von_ts, datei_zeit),
       bis_ts            = coalesce(bis_ts, datei_zeit, gelesen_ts),
       sortiertag        = coalesce(sortiertag, betriebstag(coalesce(datei_zeit, gelesen_ts))),
       sortiertag_quelle = coalesce(sortiertag_quelle,
                             case
                               when datei_zeit is null                    then 'gelesen'
                               when datei_zeit_quelle = 'dateiname'       then 'datei'
                               when datei_zeit_quelle = 'manuell'         then 'betriebsleiter'
                               else 'dateistempel'
                             end),
       voll_n_roh        = coalesce(voll_n_roh, n_roh)
 where sortiertag is null or sortiertag_quelle is null or voll_n_roh is null;

-- ---------------------------------------------------------------------
-- 3. Der Sortiertag einer Sammeldatei: abgeleitet, mit Quelle
--
-- Die Reihenfolge ist die der Güte. Eine erfasste Sortier-Arbeit im
-- Zeitfenster ist das Beste, was es gibt — dort hat ein Mensch den Tag
-- bezeugt. Liegen mehrere im Fenster, wird nach dem gewichtet, was sie
-- gezählt haben; dieselbe Regel, nach der das Chargenalter aus den
-- Eingangstagen gemittelt wird (AB-50). Ist gar keine Arbeit erfasst —
-- der Normalfall beim Nachtragen der bisherigen Saison —, bleibt die
-- Mitte des Fensters. Sie ist eine Schätzung und heisst auch so.
-- ---------------------------------------------------------------------

create or replace function sortiertag_bestimmen(
  p_charge_nr int, p_von timestamptz, p_bis timestamptz
) returns table (tag date, quelle text)
language sql stable set search_path = public as $$
  with arbeit as (
    select a.id, betriebstag(a.start_ts) as tag,
           -- Gewicht: was in dieser Arbeit gezählt wurde. Ohne Zählung
           -- zählt die Arbeit einfach als eine — nie als null.
           greatest(coalesce((select count(*) from auftrag_palette p where p.auftrag_id = a.id), 0), 1) as w
      from auftrag a
     where a.charge_nr = p_charge_nr
       and a.station = 'sortieren' and not a.ist_fax
       and a.abgebrochen_ts is null
       and (p_von is null or a.start_ts >= p_von)
       and (p_bis is null or a.start_ts <= p_bis)
  )
  select case
           when (select count(*) from arbeit) = 1 then (select tag from arbeit)
           when (select count(*) from arbeit) > 1 then
             (select (sum(w * (tag - date '2000-01-01')) / sum(w))::int + date '2000-01-01' from arbeit)
           when p_von is not null and p_bis is not null then
             (p_von + (p_bis - p_von) / 2)::date
         end,
         case
           when (select count(*) from arbeit) = 1 then 'arbeit'
           when (select count(*) from arbeit) > 1 then 'arbeiten-mittel'
           when p_von is not null and p_bis is not null then 'fenster-mitte'
         end
$$;
comment on function sortiertag_bestimmen(int, timestamptz, timestamptz) is
  'Der Sortiertag für eine Sammeldatei und woher er kommt. Erfasste '
  'Sortier-Arbeiten im Zeitfenster schlagen die Fenstermitte; ohne Fenster '
  'gibt es keinen Tag — leer ist nicht null (0082).';
revoke all on function sortiertag_bestimmen(int, timestamptz, timestamptz) from public;
grant execute on function sortiertag_bestimmen(int, timestamptz, timestamptz) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Eine Sammeldatei einlesen: nur das Delta, und erst nach der Probe
--
-- Die Datenbank rechnet die Subtraktion, nicht der Browser: Nur sie weiss
-- sicher, was schon gespeichert ist. Der Browser rechnet dasselbe für die
-- Vorschau (histogrammAbziehen), aber massgeblich ist, was hier steht.
--
-- Abgezogen wird ausschliesslich, was frühere SAMMEL-Lesungen derselben
-- Charge tragen. Lauf-Dateien derselben Charge werden nicht abgezogen —
-- sie können Kürbisse enthalten, die in der Sammeldatei nie standen.
-- Stattdessen wird gemeldet, dass es sie gibt; entscheiden muss ein Mensch.
-- ---------------------------------------------------------------------

create or replace function csv_sammel_speichern(
  p_charge_nr      int,
  p_datei_name     text,
  p_roh_datei_ref  text,
  p_roh_pruefsumme text,
  p_reinigung      jsonb,
  p_n_roh          int,
  p_n_overflow     int,
  p_n_klein        int,
  p_n_dubletten    int,
  p_histogramm     jsonb,          -- das Histogramm der GANZEN Datei
  p_von            timestamptz default null,
  p_bis            timestamptz default null
) returns jsonb language plpgsql as $$
declare
  v_lauf_id   bigint;
  v_vorher    bigint;
  v_n_bekannt int;
  v_n_neu     int;
  v_negativ   jsonb;
  v_von       timestamptz;
  v_bis       timestamptz;
  v_tag       date;
  v_quelle    text;
  v_laeufe    int;
  v_roh_vorher int;
  v_ov_vorher  int;
  v_kl_vorher  int;
  v_du_vorher  int;
begin
  -- Die vorige Lesung derselben Sammeldatei.
  select id, coalesce(bis_ts, gelesen_ts) into v_vorher, v_von
    from sortier_lauf
   where charge_nr = p_charge_nr and art = 'sammel'
   order by gelesen_ts desc, id desc
   limit 1;

  -- Das Fenster. Nach unten: das Ende der vorigen Lesung, sonst der erste
  -- Eingang der Charge — vor dem Eingang kann nichts sortiert worden sein.
  v_von := coalesce(p_von, v_von,
                    (select min(eingangsdatum)::timestamptz from palette where charge_nr = p_charge_nr));
  v_bis := coalesce(p_bis, now());
  if v_von is not null and v_von > v_bis then
    return jsonb_build_object('fehler', 'fenster',
      'meldung', 'Das Zeitfenster endet vor seinem Anfang.');
  end if;

  -- Was frühere Sammel-Lesungen dieser Charge schon tragen — an Kürbissen
  -- und an Trichterzahlen. Jede gespeicherte Zahl einer Lesung sagt, was
  -- DIESE Lesung dazugebracht hat; die Summe über alle Lesungen ist die
  -- Zahl der ganzen Datei. So bleiben n_roh, n_overflow, n_klein,
  -- n_dubletten und n_gueltig untereinander vergleichbar.
  select coalesce(sum(g.anzahl), 0)::int into v_n_bekannt
    from sortier_gewicht g
    join sortier_lauf l on l.id = g.lauf_id
   where l.charge_nr = p_charge_nr and l.art = 'sammel';

  select coalesce(sum(n_roh), 0)::int, coalesce(sum(n_overflow), 0)::int,
         coalesce(sum(n_klein), 0)::int, coalesce(sum(n_dubletten), 0)::int
    into v_roh_vorher, v_ov_vorher, v_kl_vorher, v_du_vorher
    from sortier_lauf where charge_nr = p_charge_nr and art = 'sammel';

  -- Die Probe: Wird eine Stufe negativ, ist die Datei keine reine
  -- Erweiterung. Dann wird nichts übernommen.
  with voll as (
    select (e->>0)::int as gewicht_g, (e->>1)::int as anzahl
      from jsonb_array_elements(p_histogramm) e
  ), bekannt as (
    select g.gewicht_g, sum(g.anzahl)::int as anzahl
      from sortier_gewicht g
      join sortier_lauf l on l.id = g.lauf_id
     where l.charge_nr = p_charge_nr and l.art = 'sammel'
     group by g.gewicht_g
  ), d as (
    select coalesce(v.gewicht_g, b.gewicht_g) as gewicht_g,
           coalesce(v.anzahl, 0) - coalesce(b.anzahl, 0) as diff
      from voll v full join bekannt b on b.gewicht_g = v.gewicht_g
  )
  select coalesce(sum(diff) filter (where diff > 0), 0)::int,
         coalesce(jsonb_agg(jsonb_build_array(gewicht_g, -diff) order by gewicht_g)
                  filter (where diff < 0), '[]'::jsonb)
    into v_n_neu, v_negativ
    from d;

  if jsonb_array_length(v_negativ) > 0 then
    return jsonb_build_object(
      'fehler', 'keine_erweiterung',
      'negativ', v_negativ,
      'meldung', 'Diese Datei ist keine Erweiterung der zuletzt eingelesenen: '
              || jsonb_array_length(v_negativ)
              || ' Gewichtsstufen fehlen darin. Wurde die Datei bearbeitet, oder '
              || 'gehört sie zu einer anderen Charge?');
  end if;

  if v_n_neu = 0 then
    return jsonb_build_object('fehler', 'nichts_neu',
      'n_bekannt', v_n_bekannt,
      'meldung', 'In dieser Datei steht nichts, was nicht schon eingelesen wäre.');
  end if;

  select tag, quelle into v_tag, v_quelle from sortiertag_bestimmen(p_charge_nr, v_von, v_bis);

  -- Eine Sammel-Lesung gehört zu keiner einzelnen Arbeit: `zuordnung` bleibt
  -- auf dem Vorgabewert und bedeutet für sie nichts. Die Warteschlange fragt
  -- deshalb nach `art = 'lauf'` — nicht nach dem Status.
  insert into sortier_lauf (charge_nr, datei_name, roh_datei_ref, roh_pruefsumme,
                            art, von_ts, bis_ts, sortiertag, sortiertag_quelle,
                            vorgaenger_id, voll_n_roh, reinigung,
                            n_roh, n_overflow, n_klein, n_dubletten, n_gueltig)
  values (p_charge_nr, p_datei_name, p_roh_datei_ref, p_roh_pruefsumme,
          'sammel', v_von, v_bis, v_tag, v_quelle,
          v_vorher, p_n_roh, p_reinigung,
          greatest(p_n_roh       - v_roh_vorher, 0),
          greatest(p_n_overflow  - v_ov_vorher,  0),
          greatest(p_n_klein     - v_kl_vorher,  0),
          greatest(p_n_dubletten - v_du_vorher,  0),
          v_n_neu)
  returning id into v_lauf_id;

  -- Nur das Delta wird gespeichert.
  insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
  with voll as (
    select (e->>0)::int as gewicht_g, (e->>1)::int as anzahl
      from jsonb_array_elements(p_histogramm) e
  ), bekannt as (
    select g.gewicht_g, sum(g.anzahl)::int as anzahl
      from sortier_gewicht g
      join sortier_lauf l on l.id = g.lauf_id
     where l.charge_nr = p_charge_nr and l.art = 'sammel' and l.id <> v_lauf_id
     group by g.gewicht_g
  )
  select v_lauf_id, v.gewicht_g, v.anzahl - coalesce(b.anzahl, 0), 'unklassiert', null
    from voll v left join bekannt b on b.gewicht_g = v.gewicht_g
   where v.anzahl - coalesce(b.anzahl, 0) > 0;

  perform lauf_neu_klassieren(v_lauf_id);

  select count(*)::int into v_laeufe
    from sortier_lauf where charge_nr = p_charge_nr and art = 'lauf';

  return jsonb_build_object(
    'lauf_id', v_lauf_id,
    'n_neu', v_n_neu,
    'n_bekannt', v_n_bekannt,
    'sortiertag', v_tag,
    'sortiertag_quelle', v_quelle,
    'von', v_von, 'bis', v_bis,
    'lauf_dateien', v_laeufe);
end $$;
comment on function csv_sammel_speichern is
  'Liest eine Sammeldatei ein: speichert nur, was seit der vorigen Lesung '
  'dazukam, und weist die Datei ab, wenn sie keine Erweiterung der vorigen ist. '
  'Gibt zurück, was übernommen wurde, welcher Sortiertag gilt und woher er '
  'kommt (0082).';
-- Ohne diese zwei Zeilen stünde die Funktion jedem offen, auch ohne
-- Anmeldung — `create function` gibt public das Ausführungsrecht mit.
revoke all on function csv_sammel_speichern(int, text, text, text, jsonb, int, int,
                                            int, int, jsonb, timestamptz, timestamptz) from public;
grant execute on function csv_sammel_speichern(int, text, text, text, jsonb, int, int,
                                               int, int, jsonb, timestamptz, timestamptz) to authenticated;

-- ---------------------------------------------------------------------
-- 4a. Auch eine Lauf-Datei füllt die neuen Spalten
--
-- Abschnitt 2 hat die Bestandsdaten gedeutet — aber nur einmal, beim
-- Einspielen. Ohne diesen Block bekäme jede künftig eingelesene Lauf-Datei
-- keinen Sortiertag und fiele damit aus der Verdunstungsrechnung heraus
-- (kuerbis_stichtag verlangt ihn seit Abschnitt 6). Beim ersten Lauf des
-- Prüfstands stand genau das da: „VORHER: Sortiertag=NULL".
--
-- Die Signatur bleibt Zeichen für Zeichen dieselbe: Die Demo-Generatoren
-- (0052, 0081) rufen diese Funktion, und ein geänderter Parametersatz
-- liesse sie mit „function does not exist" auflaufen.
-- ---------------------------------------------------------------------

create or replace function csv_lauf_speichern(
  p_charge_nr         int,
  p_datei_name        text,
  p_roh_datei_ref     text,
  p_roh_pruefsumme    text,
  p_datei_zeit        timestamptz,
  p_datei_zeit_quelle text,
  p_reinigung         jsonb,
  p_n_roh             int,
  p_n_overflow        int,
  p_n_klein           int,
  p_n_dubletten       int,
  p_histogramm        jsonb
) returns bigint language plpgsql as $$
declare
  v_lauf_id bigint;
  v_gueltig int;
begin
  select coalesce(sum((e->>1)::int), 0) into v_gueltig
    from jsonb_array_elements(p_histogramm) e;

  insert into sortier_lauf (charge_nr, datei_name, roh_datei_ref, roh_pruefsumme,
                            datei_zeit, datei_zeit_quelle, reinigung,
                            n_roh, n_overflow, n_klein, n_dubletten, n_gueltig,
                            art, von_ts, bis_ts, voll_n_roh,
                            sortiertag, sortiertag_quelle)
  values (p_charge_nr, p_datei_name, p_roh_datei_ref, p_roh_pruefsumme,
          p_datei_zeit, p_datei_zeit_quelle, p_reinigung,
          p_n_roh, p_n_overflow, p_n_klein, p_n_dubletten, v_gueltig,
          -- Eine Lauf-Datei ist ein Zeitpunkt, kein Zeitraum: von und bis
          -- fallen zusammen, und voll_n_roh ist n_roh.
          'lauf', p_datei_zeit, coalesce(p_datei_zeit, now()), p_n_roh,
          betriebstag(coalesce(p_datei_zeit, now())),
          case
            when p_datei_zeit is null              then 'gelesen'
            when p_datei_zeit_quelle = 'dateiname' then 'datei'
            when p_datei_zeit_quelle = 'manuell'   then 'betriebsleiter'
            else 'dateistempel'
          end)
  returning id into v_lauf_id;

  -- Das Histogramm zunächst unklassiert ablegen; die Klasse folgt der Fassung,
  -- und die hängt am Auftrag — also erst zuordnen.
  insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
  select v_lauf_id, (e->>0)::int, (e->>1)::int, 'unklassiert', null
    from jsonb_array_elements(p_histogramm) e;

  perform auftrag_zuordnen(v_lauf_id);
  perform lauf_neu_klassieren(v_lauf_id);
  return v_lauf_id;
end $$;
comment on function csv_lauf_speichern is
  'Liest eine Lauf-Datei ein — einen Sortierlauf mit Datum im Namen. Seit 0082 '
  'füllt sie auch art, das Zeitfenster und den Sortiertag mit seiner Quelle; '
  'ohne den fiele der Lauf aus der Verdunstungsrechnung.';

-- ---------------------------------------------------------------------
-- 4b. Eine schon eingelesene Datei nachträglich als Sammeldatei deuten
--
-- Der Betrieb hat die Sammeldateien hochgeladen, bevor die App sie kannte:
-- „ich hab bevor ich den auftrag hier gestartet habe - schon probiert die
-- daten hochzuladen und jetzt sind sie dort in der warteschlange."
--
-- Was dort liegt, ist nicht falsch, sondern falsch gedeutet. Die Kürbisse
-- stehen genau einmal in der Datenbank — jede Datei wurde ja einmal
-- hochgeladen —, also stimmt die Masse. Falsch ist dreierlei: Die Lesung
-- gilt als einzelner Lauf, ihr Sortierdatum ist der Zeitstempel des
-- Dateisystems, und sie wartet auf eine Zuordnung zu einer Arbeit, die es
-- nicht gibt.
--
-- Also umdeuten statt löschen und neu einlesen. Der Zeitstempel geht dabei
-- nicht verloren: Er wandert nach bis_ts, wo er hingehört — als obere
-- Schranke des Zeitfensters. Später als da kann nichts sortiert worden sein.
--
-- Sollten für dieselbe Charge mehrere Lesungen umgedeutet werden (zweimal
-- hochgeladen), trägt jede nur ihr Delta — dieselbe Regel und dieselbe
-- Probe wie beim Einlesen.
-- ---------------------------------------------------------------------

create or replace function lesung_als_sammel(
  p_lauf_id bigint,
  p_von     timestamptz default null,
  p_bis     timestamptz default null
) returns jsonb language plpgsql as $$
declare
  v_lauf    sortier_lauf%rowtype;
  v_von     timestamptz;
  v_bis     timestamptz;
  v_tag     date;
  v_quelle  text;
  v_negativ jsonb;
  v_neu     int;
  v_vorher  bigint;
begin
  select * into v_lauf from sortier_lauf where id = p_lauf_id;
  if not found then
    return jsonb_build_object('fehler', 'unbekannt', 'meldung', 'Diese Lesung gibt es nicht.');
  end if;
  if v_lauf.art = 'sammel' then
    return jsonb_build_object('fehler', 'schon_sammel',
      'meldung', 'Diese Lesung gilt bereits als Sammeldatei.');
  end if;

  -- Das Fenster: nach unten die letzte Sammel-Lesung derselben Charge, sonst
  -- der erste Eingang — vor dem Eingang kann nichts sortiert worden sein.
  -- Nach oben der Zeitstempel der Datei, sonst der Zeitpunkt des Einlesens.
  select id, coalesce(bis_ts, gelesen_ts) into v_vorher, v_von
    from sortier_lauf
   where charge_nr = v_lauf.charge_nr and art = 'sammel' and id <> p_lauf_id
   order by gelesen_ts desc, id desc limit 1;

  v_von := coalesce(p_von, v_von,
             (select min(eingangsdatum)::timestamptz from palette where charge_nr = v_lauf.charge_nr));
  v_bis := coalesce(p_bis, v_lauf.datei_zeit, v_lauf.gelesen_ts);
  if v_von is not null and v_von > v_bis then
    return jsonb_build_object('fehler', 'fenster',
      'meldung', 'Das Zeitfenster endet vor seinem Anfang.');
  end if;

  -- Trägt diese Lesung Kürbisse, die eine frühere Sammel-Lesung derselben
  -- Charge schon hat? Dann ist sie eine spätere Lesung derselben Datei und
  -- darf nur ihr Delta behalten.
  with bekannt as (
    select g.gewicht_g, sum(g.anzahl)::int as anzahl
      from sortier_gewicht g join sortier_lauf l on l.id = g.lauf_id
     where l.charge_nr = v_lauf.charge_nr and l.art = 'sammel' and l.id <> p_lauf_id
     group by g.gewicht_g
  ), d as (
    select coalesce(v.gewicht_g, b.gewicht_g) as gewicht_g,
           coalesce(v.anzahl, 0) - coalesce(b.anzahl, 0) as diff
      from (select gewicht_g, anzahl from sortier_gewicht where lauf_id = p_lauf_id) v
      full join bekannt b on b.gewicht_g = v.gewicht_g
  )
  select coalesce(sum(diff) filter (where diff > 0), 0)::int,
         coalesce(jsonb_agg(jsonb_build_array(gewicht_g, -diff) order by gewicht_g)
                  filter (where diff < 0), '[]'::jsonb)
    into v_neu, v_negativ
    from d;

  if jsonb_array_length(v_negativ) > 0 then
    return jsonb_build_object('fehler', 'keine_erweiterung', 'negativ', v_negativ,
      'meldung', 'Diese Lesung passt nicht als Fortsetzung der schon vorhandenen '
              || 'Sammel-Lesungen dieser Charge — es fehlen Gewichtsstufen.');
  end if;

  -- Das Delta behalten: was eine frühere Lesung schon trägt, fällt weg.
  --
  -- Die Reihenfolge ist hier kein Geschmack, sondern der Unterschied
  -- zwischen richtig und falsch. Erst wird gelöscht, dann gekürzt — beide
  -- Anweisungen vergleichen mit derselben, ungekürzten Zahl. Stünde das
  -- Kürzen voran, läse das Löschen danach die schon gekürzte Zahl und
  -- nähme auch das weg, was gerade übrig geblieben ist: Aus 6 gelesenen
  -- bei 4 bekannten würden erst 2 — und die 2 sind nicht mehr grösser als
  -- 4, also verschwänden sie. Die Lesung meldete 2 Kürbisse und trüge
  -- keinen einzigen.
  if v_vorher is not null then
    -- Stufen, die vollständig bekannt sind, tragen nichts mehr bei.
    delete from sortier_gewicht g
     using (select gewicht_g, sum(anzahl)::int as anzahl
              from sortier_gewicht sg join sortier_lauf l on l.id = sg.lauf_id
             where l.charge_nr = v_lauf.charge_nr and l.art = 'sammel' and l.id <> p_lauf_id
             group by gewicht_g) b
     where g.lauf_id = p_lauf_id and g.gewicht_g = b.gewicht_g and g.anzahl <= b.anzahl;

    with bekannt as (
      select g.gewicht_g, sum(g.anzahl)::int as anzahl
        from sortier_gewicht g join sortier_lauf l on l.id = g.lauf_id
       where l.charge_nr = v_lauf.charge_nr and l.art = 'sammel' and l.id <> p_lauf_id
       group by g.gewicht_g
    )
    update sortier_gewicht g
       set anzahl = g.anzahl - coalesce(b.anzahl, 0)
      from (select gewicht_g from sortier_gewicht where lauf_id = p_lauf_id) alle
      left join bekannt b on b.gewicht_g = alle.gewicht_g
     where g.lauf_id = p_lauf_id and g.gewicht_g = alle.gewicht_g
       and g.anzahl - coalesce(b.anzahl, 0) > 0;
  end if;

  select tag, quelle into v_tag, v_quelle
    from sortiertag_bestimmen(v_lauf.charge_nr, v_von, v_bis);
  if p_von is not null or p_bis is not null then v_quelle := 'betriebsleiter'; end if;

  update sortier_lauf
     set art               = 'sammel',
         von_ts            = v_von,
         bis_ts            = v_bis,
         -- Der Zeitstempel war nie ein Sortierdatum. Er steht jetzt in
         -- bis_ts; hier stünde er als Messung, die es nie gab.
         datei_zeit        = null,
         sortiertag        = v_tag,
         sortiertag_quelle = v_quelle,
         vorgaenger_id     = v_vorher,
         voll_n_roh        = coalesce(voll_n_roh, n_roh),
         n_gueltig         = v_neu,
         auftrag_id        = null,
         zuordnung         = 'offen'
   where id = p_lauf_id;

  perform lauf_neu_klassieren(p_lauf_id);

  return jsonb_build_object('lauf_id', p_lauf_id, 'n_gueltig', v_neu,
    'sortiertag', v_tag, 'sortiertag_quelle', v_quelle, 'von', v_von, 'bis', v_bis);
end $$;
comment on function lesung_als_sammel(bigint, timestamptz, timestamptz) is
  'Deutet eine schon eingelesene Datei nachträglich als Sammeldatei: Zeitfenster '
  'statt erfundenem Zeitpunkt, abgeleiteter Sortiertag, keine Zuordnung zu einer '
  'Arbeit. Der Zeitstempel der Datei geht nicht verloren — er wird zur oberen '
  'Schranke des Fensters. Gebraucht für die Dateien, die vor 0082 hochgeladen '
  'wurden und in der Warteschlange liegen (0082).';
revoke all on function lesung_als_sammel(bigint, timestamptz, timestamptz) from public;
grant execute on function lesung_als_sammel(bigint, timestamptz, timestamptz) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Klassiert wird nach dem Sortiertag, nicht nach dem Dateidatum
--
-- Bisher: `coalesce(l.datei_zeit, l.gelesen_ts)::date`. Für eine
-- Sammeldatei wäre das der Tag des Hochladens — und damit womöglich eine
-- Fassung der Kaliberbänder, die es beim Sortieren noch gar nicht gab.
-- ---------------------------------------------------------------------

create or replace function lauf_neu_klassieren(p_lauf_id bigint)
returns int language plpgsql as $$
declare v_schema bigint; v_n int;
begin
  -- Die Fassung: vom Auftrag, sonst vom Lauf, sonst der Standard der Sorte
  -- zum Sortiertag. Ohne Sortiertag bleibt der Tag des Einlesens — besser
  -- eine Fassung als keine Klassierung, aber sortiertag_quelle sagt, dass
  -- der Tag geschätzt ist.
  select coalesce(a.sortierschema_id, l.sortierschema_id,
                  sortierschema_fuer(c.sorte, null,
                                     coalesce(l.sortiertag, betriebstag(coalesce(l.datei_zeit, l.gelesen_ts)))))
    into v_schema
    from sortier_lauf l
    join charge c on c.nr = l.charge_nr
    left join auftrag a on a.id = l.auftrag_id
   where l.id = p_lauf_id;

  update sortier_lauf set sortierschema_id = v_schema where id = p_lauf_id;

  with neu as (
    select sg.gewicht_g, k.klasse, k.kaliber_idx
      from sortier_gewicht sg
      cross join lateral klassiere(v_schema, sg.gewicht_g) k
     where sg.lauf_id = p_lauf_id
  )
  update sortier_gewicht g
     set klasse = neu.klasse, kaliber_idx = neu.kaliber_idx
    from neu
   where g.lauf_id = p_lauf_id and g.gewicht_g = neu.gewicht_g;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ---------------------------------------------------------------------
-- 6. Die Verdunstung rechnet ab dem Sortiertag, nicht ab dem Dateidatum
--
-- Dieselbe Rechnung wie in 0079, nur mit der Spalte statt mit
-- `betriebstag(l.datei_zeit)`. Für alle bisherigen Läufe ist das
-- derselbe Wert (Abschnitt 2 hat ihn genau so gesetzt); für eine
-- Sammeldatei ist es der einzige, der stimmen kann.
--
-- Kürbisse ohne Sortiertag fallen heraus, statt mit einem erfundenen Tag
-- zu rechnen. Wie viele das sind, sagt v_datenqualitaet.
-- ---------------------------------------------------------------------

create or replace function lager_schluessel()
returns table (charge_nr integer, sorte text, basis text, schluessel text, r numeric)
language sql stable set search_path = public as $$
with liegend as (
  select k.charge_nr, k.sorte, sum(k.m0 * k.r) / nullif(sum(k.m0), 0) as r
    from mv_kaskade k where k.portion = 'lager' group by k.charge_nr, k.sorte
), rate_sorte as (
  select sorte, sum(m0 * r) / nullif(sum(m0), 0) as r
    from mv_kaskade where portion = 'lager' group by sorte
), mit_csv as (
  select distinct l.charge_nr, c.sorte
    from sortier_lauf l join charge c on c.nr = l.charge_nr
    join sortier_gewicht g on g.lauf_id = l.id
   where g.klasse = 'kaliber' and g.anzahl > 0 and g.gewicht_g > 0
     and l.sortiertag is not null
)
select l.charge_nr, l.sorte,
       case when exists (select 1 from mit_csv m where m.charge_nr = l.charge_nr) then 'charge'
            when exists (select 1 from mit_csv m where m.sorte = l.sorte)         then 'sorte'
            else 'keine' end,
       case when exists (select 1 from mit_csv m where m.charge_nr = l.charge_nr) then l.charge_nr::text
            else l.sorte end,
       case when exists (select 1 from mit_csv m where m.charge_nr = l.charge_nr) then l.r
            else rs.r end
  from liegend l
  left join rate_sorte rs on rs.sorte = l.sorte
$$;
comment on function lager_schluessel() is
  'Je Charge mit liegender Ware: woher ihre Gewichtsverteilung kommt (eigene '
  'Sortier-CSV, die der Sorte, oder keine) und mit welcher Verdunstungsrate '
  'geschrumpft wird. Seit 0082 zählt eine CSV nur mit, wenn ihr Sortiertag '
  'bekannt ist — ohne ihn lässt sich nicht sagen, wie lange geschrumpft wurde.';

create or replace function kuerbis_stichtag(p_h integer)
returns table (basis text, schluessel text, sorte text, h integer, anzahl integer, g double precision)
language sql stable set search_path = public as $$
with stichtag as (
  select heute() as heute
), lauf as materialized (
  -- Der Sortiertag steht seit 0082 an der Lesung: abgelesen bei einer
  -- Lauf-Datei, abgeleitet bei einer Sammeldatei (sortiertag_quelle sagt
  -- welches). Vorher stand hier betriebstag(l.datei_zeit).
  select l.id, l.charge_nr, c.sorte, l.sortiertag
    from sortier_lauf l join charge c on c.nr = l.charge_nr
   where l.sortiertag is not null
), kuerbis as (
  -- Nur die Klasse „kaliber": zu klein und Nebenkanal sind aus der
  -- verkaufsfähigen Masse schon heraus (a_klein_n, a_gross_n).
  select l.charge_nr, l.sorte, l.sortiertag, g.gewicht_g, g.anzahl
    from sortier_gewicht g join lauf l on l.id = g.lauf_id
   where g.klasse = 'kaliber' and g.anzahl > 0 and g.gewicht_g > 0
), schluessel as (
  select 'charge' as basis, s.schluessel, s.sorte, s.charge_nr, s.r
    from lager_schluessel() s where s.basis = 'charge'
  union
  select distinct 'sorte', s.sorte, s.sorte, null::int, s.r
    from lager_schluessel() s where s.basis = 'sorte'
)
select v.basis, v.schluessel, v.sorte, p_h, k.anzahl,
       k.gewicht_g * power((1 - coalesce(v.r, 0))::double precision,
                           greatest(t.heute + p_h - k.sortiertag, 0)::double precision)
  from schluessel v
  join kuerbis k on k.charge_nr = v.charge_nr
  cross join stichtag t
 where v.basis = 'charge'
union all
select v.basis, v.schluessel, v.sorte, p_h, k.anzahl,
       k.gewicht_g * power((1 - coalesce(v.r, 0))::double precision,
                           greatest(t.heute + p_h - k.sortiertag, 0)::double precision)
  from schluessel v
  join kuerbis k on k.sorte = v.sorte
  cross join stichtag t
 where v.basis = 'sorte'
$$;
comment on function kuerbis_stichtag(integer) is
  'Jeder sortierte Kürbis, wie er am Stichtag heute + p_h wiegt — geschrumpft '
  'ab seinem Sortiertag. Seit 0082 aus sortier_lauf.sortiertag; Lesungen ohne '
  'bekannten Sortiertag bleiben draussen, statt mit einem erfundenen Tag zu '
  'rechnen (0079, 0082).';

-- ---------------------------------------------------------------------
-- 7. Die Lesungen, wie die Oberfläche sie zeigt
-- ---------------------------------------------------------------------

create or replace view v_sortier_lesung with (security_invoker = true) as
select l.id, l.charge_nr, c.sorte, c.schlag, l.datei_name, l.art,
       l.von_ts, l.bis_ts, l.sortiertag, l.sortiertag_quelle,
       l.vorgaenger_id, l.voll_n_roh, l.n_roh, l.n_gueltig, l.gelesen_ts,
       l.zuordnung::text as zuordnung, l.auftrag_id,
       (select count(*) from sortier_gewicht g where g.lauf_id = l.id)::int as stufen,
       -- zahl() statt eines harten Casts (0058): Eine einzelne unmögliche
       -- Zahl — ein Tippfehler von 900 000 g etwa — würde sonst die ganze
       -- Sicht abbrechen lassen, statt nur diese eine Masse unbekannt zu
       -- machen.
       zahl((select coalesce(sum(g.anzahl::bigint * g.gewicht_g), 0) / 1000.0
               from sortier_gewicht g where g.lauf_id = l.id), 2, 1e10) as masse_kg,
       case l.sortiertag_quelle
         when 'datei'          then 'aus dem Dateinamen'
         when 'arbeit'         then 'aus der Sortier-Arbeit im Zeitraum'
         when 'arbeiten-mittel' then 'Mittel der Sortier-Arbeiten im Zeitraum'
         when 'fenster-mitte'  then 'Mitte des Zeitraums — geschätzt'
         when 'betriebsleiter' then 'von Hand gesetzt'
         when 'dateistempel'   then 'Zeitstempel der Datei — kein Sortierdatum'
         when 'gelesen'        then 'Tag des Einlesens — geschätzt'
         else 'nicht bekannt'
       end                                                                  as sortiertag_text
  from sortier_lauf l
  join charge c on c.nr = l.charge_nr;
comment on view v_sortier_lesung is
  'Je eingelesener Datei: welche Art, welcher Zeitraum, welcher Sortiertag und '
  'woher er kommt. Eine Sammel-Lesung trägt nur das Delta zur vorigen — '
  'n_gueltig ist also, was DAZUKAM, nicht was in der Datei steht (0082).';
grant select on v_sortier_lesung to authenticated;

-- ---------------------------------------------------------------------
-- 8. Der Betriebsleiter soll sehen, worauf die Verteilung ruht
-- ---------------------------------------------------------------------

create or replace view v_datenqualitaet with (security_invoker = true) as
with arbeiten as (select a.* from auftrag a where a.abgebrochen_ts is null),
     fertig as (select * from arbeiten where status = 'abgeschlossen')
select
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id)::int as paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where ap.eingangsdatum is not null)::int                                             as paletten_mit_datum,
  (select count(*) from fertig where not ist_fax)::int                                    as arbeiten_fertig,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null))::int                     as arbeiten_mit_ablesung,
  (select count(*) from fertig f where not f.ist_fax and (select count(*) from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null) >= 2)::int                as arbeiten_mit_zwei_ablesungen,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from auftrag_angabe g
    where g.auftrag_id = f.id and g.schluessel = 'eine_charge'))::int                     as arbeiten_mit_antwort,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen)::int                                                                as ausschuss_messungen,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen and m.brutto_kg is not null)::int                                    as ausschuss_gewogen,
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.gemessen)::int                                       as lagerkontrollen,
  (select count(*) from sortier_lauf)::int                                                as sortierlaeufe,
  (select count(*) from sortier_lauf where auftrag_id is not null)::int                   as sortierlaeufe_zugeordnet,
  (select count(*) from fertig f where f.station = 'sortieren')::int                      as sortier_arbeiten,
  (select count(*) from fertig f where f.station = 'sortieren' and exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int              as sortier_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax)::int      as wasch_arbeiten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax
    and (f.kaliber_idx is not null or f.kaliber_von_g is not null)
    and (exists (select 1 from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)
         or exists (select 1 from auftrag_palette p where p.auftrag_id = f.id and p.kisten > 0)))::int
                                                                                          as wasch_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax)::int                                    as fax_arbeiten,
  (select count(*) from fertig f where f.ist_fax and (f.paletten_gesamt > 0 or exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)))::int             as fax_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax and exists (select 1
    from schimmel_messung s where s.auftrag_id = f.id and s.gemessen))::int               as fax_arbeiten_mit_faulem,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren')::int                                           as ws_paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren' and ap.brutto_zettel_kg is not null)::int       as ws_paletten_mit_zettelgewicht,
  (select count(*) from fertig f where f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))::int
                                                                                          as arbeiten_nach_waschen,
  (select count(*) from fertig f where (f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))
    and f.kistensystem is not null)::int                                                  as arbeiten_mit_kistensystem,
  ((select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
     where a.station = 'waschen' and not a.ist_fax)
   + (select coalesce(sum(p.kisten), 0) from auftrag_palette p join arbeiten a on a.id = p.auftrag_id
       where a.station = 'waschen' and not a.ist_fax))::int                               as wasch_kisten_gezaehlt,
  ((select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
     where a.station = 'waschen' and not a.ist_fax and (g.sortierdatum is not null or g.datum_fehlt))
   + (select coalesce(sum(p.kisten), 0) from auftrag_palette p join arbeiten a on a.id = p.auftrag_id
       where a.station = 'waschen' and not a.ist_fax and p.sortierdatum is not null))::int
                                                                                          as wasch_kisten_mit_sortierdatum,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from v_palox_stand p
    where p.auftrag_id = f.id and p.differenz is null))::int                              as arbeiten_mit_palox_unbekannt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where not a.ist_fax and a.station in ('sortieren', 'waschen_sortieren'))::int         as eingangspaletten,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where not a.ist_fax and a.station in ('sortieren', 'waschen_sortieren')
      and ap.kisten is not null and ap.kisten > 0)::int                                   as eingangspaletten_mit_kisten,
  (select count(*) from mv_auftrag_masse m join fertig f on f.id = m.auftrag_id
    where not f.ist_fax and m.lagertage is not null)::int                                 as arbeiten_alter_gemessen,
  -- 0082: Zwei Arten von Datei, und die Güte des Sortiertags. Darauf ruht
  -- die ganze Gewichtsverteilung des Lagers. Angehängt und nicht
  -- eingeschoben: `create or replace view` darf die Spaltenliste nur
  -- verlängern, sonst bricht es mit „cannot change name of view column".
  (select count(*) from sortier_lauf where art = 'sammel')::int                           as sammel_lesungen,
  (select count(*) from sortier_lauf where sortiertag is not null)::int                   as lesungen_mit_sortiertag,
  (select count(*) from sortier_lauf
    where sortiertag_quelle in ('datei', 'arbeit'))::int                                  as lesungen_sortiertag_bezeugt;

comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung. Seit 0061 zählen beim Waschen die '
  'gezählten Paletten (Kisten mit Sortierdatum) mit; die Lagerkontrolle zählt '
  'als Verdunstungsmessung, ohne Faul-Angabe. Seit 0076 zusätzlich die '
  'Kistenzahl auf der Eingangspalette. Seit 0082 die zwei Arten von '
  'Sortierdatei und die Güte des Sortiertags: Wie viele Lesungen haben '
  'überhaupt einen, und bei wie vielen ist er bezeugt statt geschätzt? '
  'Darauf ruht die Gewichtsverteilung des Lagers (0082).';

-- Die gespeicherte Fassung muss mitkommen: erg_datenqualitaet ist ein
-- `create materialized view … as select * from v_datenqualitaet`, und der
-- Stern ist dort beim Anlegen eingefroren. Ohne diesen Block kämen die drei
-- neuen Spalten über die Migrationen nicht an, über setup.sql schon — und
-- genau diesen Unterschied findet der Fingerabdruck-Vergleich in run.sh.
-- verdichter: baut erg_datenqualitaet
do $$
begin
  execute 'drop materialized view if exists erg_datenqualitaet cascade';
  execute 'create materialized view erg_datenqualitaet as select * from v_datenqualitaet with no data';
  execute 'grant select on erg_datenqualitaet to authenticated';
  execute format('comment on materialized view erg_datenqualitaet is %L',
                 'v_datenqualitaet, gespeichert für die App Erneuert mit auswertung_schritt().');
end $$;

-- ---------------------------------------------------------------------
-- 9. Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 82 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
