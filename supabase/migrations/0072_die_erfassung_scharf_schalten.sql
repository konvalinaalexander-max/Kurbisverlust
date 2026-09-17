-- =====================================================================
-- 0072 — Die Erfassung scharf schalten
--
-- Ab der nächsten Saison sind die erfassten Daten echt. Diese Migration
-- richtet das Schema darauf aus. Sie legt nur an: Spalten, Tabellen,
-- Rechte, Auslöser, Einstellungen. Das Rechenwerk folgt in 0073.
--
-- DER GEMELDETE FEHLER
--
-- Der Betrieb: „wenn ich bei sortieren palox zu beginn ablese rechnet es
-- minus 445? warum - es sind 45 kg". Der Fehler sitzt an zwei Stellen.
-- In der Maske holt PaloxMaske.tsx den letzten Stand derselben *Station*
-- über Arbeitsgrenzen hinweg; in der Datenbank fenstert v_palox_stand
-- genauso. Beginnt eine Arbeit mit einem niedrigeren Stand als die
-- Vorarbeit endete, wird die Differenz NULL und die ganze Arbeit fällt
-- aus der Rechnung — zufällig richtig, aber eine verlorene Messung.
-- Beginnt sie mit einem höheren, werden ihr fremde Kilo als Fäulnis
-- angelastet, und das sieht niemand.
--
-- Die Regel des Betriebs: „arbeitsschritte werden nie über nacht pausiert
-- … deswegen soll nie von der letzten arbeit der palox wert irgendwie
-- übernommen werden". Jede Arbeit liest ihren eigenen Anfang und ihr
-- eigenes Ende: Menge = S₂ − S₁. Die 45 kg Leergewicht kürzen sich in der
-- Differenz heraus und dürfen nirgends mehr abgezogen werden.
--
-- DER GEBINDEWECHSEL
--
-- „in den g2 ist voll gestapelt - in den ifcos nicht - also kanns sein
-- dass 3 paletten vorne reingehen und hinten 4 rauskommen". Eine Palette
-- bedeutet vor und nach der Waschstrasse etwas anderes. Dafür braucht es
-- die Gebindeart der Kaliber-Paletten und die Gesamtzahl der fertigen.
--
-- DIE MASSE JE KALIBERBAND
--
-- Der Betrieb hat selbst gefunden, wie sie zu haben ist: „du siehst ja
-- dann anzahl paletten - mit anzahl kisten und total vom brutto gewicht -
-- dann weisst du wieviel sortiert worden ist". Dafür wird das
-- Zettelgewicht auch beim Sortieren zur Pflicht — bisher nur bei Waschen
-- + Sortieren. Zusammen mit der CSV ergibt das die Masse je Band, ohne
-- je eine Kiste zählen zu müssen (was ohnehin niemand tut).
--
-- DIE ZUSAGE
--
-- „mir ist dann wichtig dass die daten der arbeiter app von nun an
-- richtig erfasst werden - richtig in der datenbank angelegt - und auch
-- genügend geschützt dass dort nicht mehr gross rumgepfuscht wird von der
-- KI und falls schon, dann nur so dass nichts verloren geht."
--
-- Dafür: erfassung_journal. Jede Änderung an jeder Messtabelle wird
-- festgehalten, bei einem Löschen die ganze alte Zeile als jsonb. Das
-- Journal selbst kann niemand ändern oder löschen — auch der Admin nicht.
-- =====================================================================
set client_min_messages = warning;

-- =====================================================================
-- 1. Der Palox liest nur noch innerhalb derselben Arbeit
-- =====================================================================

alter table auftrag add column if not exists palox_unbekannt boolean not null default false;
comment on column auftrag.palox_unbekannt is
  'Der Palox wurde während dieser Arbeit geleert. Die Faul-Menge der Arbeit '
  'ist damit unbekannt — nicht null. Die Auswertung lässt die Arbeit aus der '
  'Verderbsrechnung heraus; die Ablesungen selbst bleiben erhalten. Gesetzt '
  'wird die Spalte, wenn der Stand fällt oder der Abschluss danach fragt.';

-- Der letzte Stand DIESER Arbeit. Die Maske rechnet die Differenz dagegen
-- und nie mehr gegen eine fremde Arbeit.
create or replace function palox_stand_dieser_arbeit(p_auftrag_id bigint)
returns numeric language sql stable set search_path = public as $$
  select s.palox_stand_kg
    from public.schimmel_messung s
   where s.auftrag_id = p_auftrag_id
     and s.palox_stand_kg is not null and s.gemessen
   order by s.ts desc, s.id desc limit 1;
$$;
comment on function palox_stand_dieser_arbeit(bigint) is
  'Was die Palox-Waage zuletzt in DIESER Arbeit zeigte. Arbeitsschritte werden '
  'nie über Nacht pausiert; zwischen zwei Arbeiten liegt unbekannt viel. Der '
  'Stand vom letzten Mal sagt deshalb nichts über den Anfang dieser Arbeit '
  '(0072). palox_letzter_stand(station) bleibt bestehen, wird aber von keiner '
  'Maske mehr zur Differenzbildung benutzt.';
revoke all on function palox_stand_dieser_arbeit(bigint) from public;
grant execute on function palox_stand_dieser_arbeit(bigint) to authenticated;

-- =====================================================================
-- 2. Der Gebindewechsel beim Waschen
-- =====================================================================

alter table auftrag_palette add column if not exists gebindeart text
  references gebinde(art) on update cascade;
comment on column auftrag_palette.gebindeart is
  'In welchem Gebinde die Palette steht. Beim Waschen aus dem Zwischenlager '
  'gefragt, weil die Tara davon abhängt und sich das Gebinde an der '
  'Waschstrasse ändert (G2 → IFCO). Der Betrieb: „meistens G2, aber auch nur '
  'so 95 %" — also gefragt, nicht vorausgesetzt (0072).';

alter table auftrag add column if not exists fertige_paletten_gesamt int
  check (fertige_paletten_gesamt is null or fertige_paletten_gesamt >= 0);
comment on column auftrag.fertige_paletten_gesamt is
  'Waschen und Waschen + Sortieren: wie viele fertige Paletten am Ende '
  'insgesamt dastanden. Die App kennt sonst nur die *gewogenen*. Ohne diese '
  'Zahl ist die Ausgangsmasse unbekannt — nicht null. Nicht Pflicht: der '
  'Betrieb sagt „die fertigen paletten werden eher nicht gezählt" (0072).';

alter table ausgang_wiegung add column if not exists voll boolean not null default true;
comment on column ausgang_wiegung.voll is
  'Ob diese fertige Palette voll ist. Der Betrieb: „vlt die ersten beiden '
  'paletten je 40 kisten ifco und die letzte vlt nur 24". Eine nicht volle '
  'Palette zählt für die Masse, aber nicht für kg je Kiste und Kürbisse je '
  'Kiste — sonst zieht sie den Koeffizienten nach unten (0072).';

-- =====================================================================
-- 3. Wann eine Charge fertig geerntet ist
-- =====================================================================
-- Das Alter beim Waschen ist das massegewichtete mittlere Eingangsdatum
-- der Charge. Solange die Ernte läuft, wandert dieser Mittelwert mit
-- jedem Import. Erst wenn die Charge vollständig ist, steht er fest.
-- Der Betrieb: „vlt kann ich ja irgendwo dann in den einstellungen
-- angeben - nun ernte vorbei - und dann inkludiert das system diese
-- angabe".

alter table charge add column if not exists ernte_abgeschlossen_ts timestamptz;
comment on column charge.ernte_abgeschlossen_ts is
  'Wann der Betrieb gesagt hat, dass von dieser Charge nichts mehr kommt. Ab '
  'dann ist das massegewichtete mittlere Eingangsdatum endgültig und die '
  'Streuung der Erntedaten belastbar. Vorher trägt jede Altersangabe den '
  'Zusatz „Ernte läuft noch" (0072).';

-- =====================================================================
-- 4. Die Kontrollpalette
-- =====================================================================
-- Heute rechnet die App mit einer Verdunstungsrate je Sorte über die
-- ganze Saison, und die Wägungen, aus denen sie kommt, sind nach
-- Augenschein ausgewählt („an sich werden schon die schlechter
-- aussehenden palette ausgewählt"). Beides verzerrt.
--
-- Eine markierte Palette je Charge, nie verarbeitet, regelmässig
-- gewogen, beseitigt beides: die Auswahl ist einmalig und bewusst, und
-- verarbeitet wird sie nicht. Zwei Wägungen derselben Palette geben eine
-- Rate FÜR DEN ZEITRAUM DAZWISCHEN — und damit die Antwort auf die Frage,
-- die heute niemand beantworten kann: „ich weiss nicht ob
-- verdunstungsrate konstant ist - ich denke nicht - weil am anfang haben
-- sie sicher schock von draussen feld in halle zu kommen".

create table if not exists kontrollpalette (
  id            bigserial primary key,
  charge_nr     int  not null references charge(nr),
  palette_id    bigint references palette(id),
  kennzeichen   text not null,
  standort      text,
  angelegt_ts   timestamptz not null default now(),
  angelegt_von  uuid not null default auth.uid() references profil(id),
  beendet_ts    timestamptz,
  beendet_grund text,
  bemerkung     text
);
comment on table kontrollpalette is
  'Eine markierte Palette, die eine Saison lang stehen bleibt und nur gewogen '
  'wird. Fünf Stück auf den ertragsstärksten Chargen (Antwort des Betriebs). '
  'Wird nie gelöscht — am Ende wird beendet_ts gesetzt und sie verarbeitet.';
comment on column kontrollpalette.kennzeichen is
  'Was auf der Palette steht, damit man sie im Lager wiederfindet.';
create index if not exists kontrollpalette_charge_idx on kontrollpalette (charge_nr);

create table if not exists kontrollpalette_wiegung (
  id                 bigserial primary key,
  kontrollpalette_id bigint not null references kontrollpalette(id),
  brutto_kg          numeric(8,2) not null check (brutto_kg > 0),
  kisten             int not null check (kisten > 0),
  gebindeart         text references gebinde(art) on update cascade,
  sichtbar_schimmel  boolean not null default false,
  erfasser           uuid not null default auth.uid() references profil(id),
  wiege_ts           timestamptz not null default now(),
  ts                 timestamptz not null default now(),
  bemerkung          text
);
comment on table kontrollpalette_wiegung is
  'Eine Wägung einer Kontrollpalette. Gespeichert wird das Brutto mit '
  'Kistenzahl und Gebinde — das Netto ist Ableitung (Beobachtung statt '
  'Folgerung). Zwei aufeinanderfolgende Wägungen ergeben eine Rate für den '
  'Zeitraum dazwischen.';
create index if not exists kontrollpalette_wiegung_pal_ts_idx
  on kontrollpalette_wiegung (kontrollpalette_id, wiege_ts);

alter table kontrollpalette         enable row level security;
alter table kontrollpalette_wiegung enable row level security;

drop policy if exists kp_lesen       on kontrollpalette;
drop policy if exists kp_anlegen     on kontrollpalette;
drop policy if exists kp_aendern     on kontrollpalette;
drop policy if exists kp_loeschen    on kontrollpalette;
create policy kp_lesen    on kontrollpalette for select to authenticated using (true);
create policy kp_anlegen  on kontrollpalette for insert to authenticated
  with check ((angelegt_von = auth.uid() and ist_aktiv()) or ist_admin());
create policy kp_aendern  on kontrollpalette for update to authenticated
  using (ist_admin() or (angelegt_von = auth.uid() and ist_aktiv()));
-- Löschen nur der Admin: eine Kontrollpalette ist eine Zusage über eine
-- ganze Saison. Beenden heisst beendet_ts setzen, nicht löschen.
create policy kp_loeschen on kontrollpalette for delete to authenticated using (ist_admin());

drop policy if exists kpw_lesen    on kontrollpalette_wiegung;
drop policy if exists kpw_erfassen on kontrollpalette_wiegung;
drop policy if exists kpw_aendern  on kontrollpalette_wiegung;
drop policy if exists kpw_loeschen on kontrollpalette_wiegung;
create policy kpw_lesen    on kontrollpalette_wiegung for select to authenticated using (true);
create policy kpw_erfassen on kontrollpalette_wiegung for insert to authenticated
  with check ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
create policy kpw_aendern  on kontrollpalette_wiegung for update to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()));
create policy kpw_loeschen on kontrollpalette_wiegung for delete to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()));

grant select, insert, update, delete on kontrollpalette         to authenticated;
grant select, insert, update, delete on kontrollpalette_wiegung to authenticated;

drop trigger if exists kontrollpalette_veraltet on kontrollpalette;
create trigger kontrollpalette_veraltet after insert or update or delete on kontrollpalette
  for each statement execute function auswertung_veraltet();
drop trigger if exists kontrollpalette_wiegung_veraltet on kontrollpalette_wiegung;
create trigger kontrollpalette_wiegung_veraltet after insert or update or delete on kontrollpalette_wiegung
  for each statement execute function auswertung_veraltet();

-- =====================================================================
-- 5. Das Journal: nichts geht mehr verloren
-- =====================================================================

create table if not exists erfassung_journal (
  id       bigserial primary key,
  tabelle  text not null,
  zeile_id text,
  vorgang  text not null check (vorgang in ('insert', 'update', 'delete')),
  alt      jsonb,
  neu      jsonb,
  wer      uuid,
  wann     timestamptz not null default now()
);
comment on table erfassung_journal is
  'Jede Änderung an jeder Messtabelle. Bei einem Löschen steht die ganze alte '
  'Zeile als jsonb darin — damit ist nichts endgültig weg, auch wenn jemand '
  'löscht. Niemand kann das Journal ändern oder löschen, auch der Admin nicht: '
  'ein Protokoll, das sich bearbeiten lässt, ist keines (0072).';
create index if not exists erfassung_journal_tabelle_wann_idx on erfassung_journal (tabelle, wann desc);
create index if not exists erfassung_journal_zeile_idx on erfassung_journal (tabelle, zeile_id);

create or replace function erfassung_journal_schreiben()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_alt jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_neu jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_zeile text;
begin
  -- Die Kennung der Zeile, ohne den Primärschlüssel jeder Tabelle zu kennen:
  -- id, sonst nr, sonst schluessel, sonst nichts. Die ganze Zeile steht
  -- ohnehin in alt/neu — die Kennung dient nur dem schnellen Nachschlagen.
  v_zeile := coalesce(v_neu, v_alt) ->> 'id';
  if v_zeile is null then v_zeile := coalesce(v_neu, v_alt) ->> 'nr'; end if;
  if v_zeile is null then v_zeile := coalesce(v_neu, v_alt) ->> 'schluessel'; end if;

  insert into erfassung_journal (tabelle, zeile_id, vorgang, alt, neu, wer)
  values (tg_table_name, v_zeile, lower(tg_op), v_alt, v_neu, auth.uid());
  return null;
end $$;
comment on function erfassung_journal_schreiben() is
  'Hängt nach jeder Zeilenänderung an einer Messtabelle und schreibt sie ins '
  'erfassung_journal. security definer, damit auch ein Arbeiter ohne Rechte '
  'auf dem Journal protokolliert wird — sonst könnte genau der, dessen '
  'Änderung festzuhalten wäre, sie ungesehen machen.';
-- Auslöser-Funktionen ruft niemand von Hand. Offen stehen dürfen sie
-- trotzdem nicht: der Prüfblock 0069 verlangt, dass jede Funktion sagt,
-- wer sie ausführen darf.
revoke all on function erfassung_journal_schreiben() from public;
grant execute on function erfassung_journal_schreiben() to authenticated;

-- An jede Tabelle hängen, in der eine Erfassung steckt.
do $$
declare t text;
begin
  foreach t in array array[
    'schimmel_messung', 'ausschuss_messung', 'ausgang_wiegung', 'verdunstung_wiegung',
    'marge_messung', 'auftrag', 'auftrag_palette', 'auftrag_gebinde', 'auftrag_angabe',
    'auftrag_teilnehmer', 'palette', 'lieferung', 'sortier_lauf', 'sortier_gewicht',
    'kontrollpalette', 'kontrollpalette_wiegung', 'charge_vorlauf']
  loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists %I on %I', t || '_journal', t);
      execute format('create trigger %I after insert or update or delete on %I '
                     'for each row execute function erfassung_journal_schreiben()',
                     t || '_journal', t);
    end if;
  end loop;
end $$;

alter table erfassung_journal enable row level security;
drop policy if exists journal_lesen on erfassung_journal;
create policy journal_lesen on erfassung_journal for select to authenticated using (ist_admin());
-- Kein insert/update/delete für irgendwen: geschrieben wird ausschliesslich
-- durch den Auslöser (security definer), geändert wird nie.
revoke all on erfassung_journal from authenticated, anon;
grant select on erfassung_journal to authenticated;

-- =====================================================================
-- 6. Eine abgeschlossene Arbeit lässt sich nicht mehr löschen
-- =====================================================================
-- Bisher durfte ein Arbeiter eine eigene Messzeile im Korrekturfenster
-- löschen, auch wenn die Arbeit längst abgeschlossen war. Der Abschluss
-- ist aber seine Zusage, dass es stimmt. Korrigieren bleibt erlaubt;
-- löschen kann danach nur noch der Admin — und selbst dann steht die
-- Zeile vollständig im Journal.

create or replace function arbeit_offen(p_auftrag_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select status = 'offen' from public.auftrag where id = p_auftrag_id), true);
$$;
comment on function arbeit_offen(bigint) is
  'Ob die Arbeit noch offen ist. Nach dem Abschluss darf eine Messzeile nur '
  'noch korrigiert werden, nicht gelöscht — ausser durch den Admin (0072).';
revoke all on function arbeit_offen(bigint) from public;
grant execute on function arbeit_offen(bigint) to authenticated;

drop policy if exists schimmel_zuruecknehmen on schimmel_messung;
create policy schimmel_zuruecknehmen on schimmel_messung for delete to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()
                         and arbeit_offen(auftrag_id)));

drop policy if exists ausschuss_zuruecknehmen on ausschuss_messung;
create policy ausschuss_zuruecknehmen on ausschuss_messung for delete to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()
                         and arbeit_offen(auftrag_id)));

drop policy if exists ausgang_zuruecknehmen on ausgang_wiegung;
create policy ausgang_zuruecknehmen on ausgang_wiegung for delete to authenticated
  using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()
                         and arbeit_offen(auftrag_id)));

-- =====================================================================
-- 7. Einstellungen
-- =====================================================================

-- Kisten je Palette: der Betrieb sagt „generell sinds 36 g2 kisten pro
-- palette", aber „teilweise sinds 32 und teilweise 36". Die Zahl ist
-- also eine Vorbelegung, keine Annahme — gefragt wird je Palette.
-- Überschrieben wird nur der ausgelieferte Vorgabewert 32, nie eine Zahl,
-- die der Betrieb selbst gesetzt hat. Woran man beides unterscheidet:
-- 0051 legt die Zeile ohne Bemerkung an, diese Anweisung schreibt eine
-- dazu, und die Stammdaten-Maske ändert nur den Wert. Eine leere Bemerkung
-- heisst deshalb „so ausgeliefert, noch nie angefasst" — und nur dann darf
-- umgestellt werden. Ohne diese Bedingung setzte jedes weitere Einspielen
-- von setup.sql eine vom Betrieb gewählte 32 still wieder auf 36.
update einstellung set wert = '36'::jsonb,
       bemerkung = 'Wie viele Kisten in der Regel auf einer Palette stehen. '
                   'Vorbelegung der Maske, keine Annahme der Rechnung — je Palette '
                   'wird gefragt, weil es teils 32 und teils 36 sind (0072).'
 where schluessel = 'kisten_pro_palette' and wert = '32'::jsonb
   and bemerkung is null;

insert into einstellung (schluessel, wert, bemerkung) values
  ('betriebsmodus', '"echt"'::jsonb,
   'echt oder beispiel. Im Beispielmodus zeigt die App ein dauerhaftes Band '
   '„Beispieldaten — nicht der Betrieb"; im Echtmodus verweigern die '
   'Demo-Daten ihren Dienst. Steht in der Datenbank und nicht im Build, damit '
   'eine falsch gebaute Seite nicht behaupten kann, sie sei die andere (0072).'),
  ('gebinde_lager', '"G2"'::jsonb,
   'Welches Gebinde im Lager vorbelegt wird. Der Betrieb: „meistens G2, aber '
   'auch nur so 95 %" — eine Vorbelegung, keine Annahme (0072).'),
  ('fax_tage_vorgabe', '4'::jsonb,
   'Wie viele Tage zwischen Waschen und Fax angenommen werden, wenn die App '
   'nichts Besseres weiss. Der Betrieb: „vlt gehen wir einfach von durchschnitt '
   'von 4 tagen aus". Ausdrücklich eine Annahme, keine Messung (0072).'),
  ('erfassung_scharf', 'false'::jsonb,
   'Stehen auf dieser Datenbank echte Erfassungsdaten? Steht sie auf true, '
   'warnt setup.sql beim Einspielen deutlich (0072).'),
  ('letzte_sicherung', 'null'::jsonb,
   'Wann der Betrieb zuletzt eine Sicherung gezogen hat, von Hand vermerkt. '
   'Kein automatischer Mechanismus — eine Erinnerung, die man nicht übersieht.'),
  ('ernte_abgeschlossen', 'false'::jsonb,
   'Ist die Ernte der Saison durch? Dann stehen alle mittleren Eingangsdaten '
   'fest. Einzelne Chargen lassen sich über charge.ernte_abgeschlossen_ts '
   'vorher schon abschliessen (0072).'),
  ('kontrollpalette_tage_anfang', '14'::jsonb,
   'Abstand der Kontrollpaletten-Wägungen in den ersten vier Wochen. Der '
   'Betrieb vermutet am Anfang einen Schock beim Einlagern — dort muss dichter '
   'gemessen werden als später (0072).'),
  ('kontrollpalette_tage_spaeter', '30'::jsonb,
   'Abstand der Kontrollpaletten-Wägungen nach den ersten vier Wochen.')
on conflict (schluessel) do nothing;

-- =====================================================================
-- 8. Im Echtmodus kommen keine Beispieldaten herein
-- =====================================================================
-- Nicht als Prüfung in der Demo-Funktion, sondern als Auslöser an den
-- Tabellen: so greift der Schutz auch, wenn jemand die Zeilen von Hand
-- einfügt oder eine spätere Fassung der Funktion die Prüfung vergisst.

create or replace function demo_nur_im_beispielmodus()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce((select wert #>> '{}' from public.einstellung
                where schluessel = 'betriebsmodus'), 'echt') = 'echt' then
    raise exception
      'Diese Datenbank läuft im Echtmodus — Beispieldaten werden nicht geladen. '
      'Für die Beispiel-Webseite gibt es eine eigene Datenbank. Soll es hier '
      'doch eine sein: einstellung betriebsmodus auf "beispiel" setzen.';
  end if;
  return new;
end $$;
comment on function demo_nur_im_beispielmodus() is
  'Hält Beispieldaten aus einer Datenbank im Echtmodus heraus (0072).';
revoke all on function demo_nur_im_beispielmodus() from public;
grant execute on function demo_nur_im_beispielmodus() to authenticated;

drop trigger if exists palette_keine_demo on palette;
create trigger palette_keine_demo before insert on palette
  for each row when (new.extern_id like 'demo-%')
  execute function demo_nur_im_beispielmodus();

drop trigger if exists sortier_lauf_keine_demo on sortier_lauf;
create trigger sortier_lauf_keine_demo before insert on sortier_lauf
  for each row when (new.datei_name like 'DEMO-%')
  execute function demo_nur_im_beispielmodus();

-- =====================================================================
-- 9. Der Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 72 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
