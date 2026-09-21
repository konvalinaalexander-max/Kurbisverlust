-- =====================================================================
-- 0080 — Tabula rasa vor dem Testtag
--
-- Der Betrieb: „was ich nun brauche - ist ein ‚löschen' knopf - und zwar um
-- alle aktuelen arbeiten die noch laufen zu löschen - und auch die
-- gespeicherten daten zu löschen - so dass wir eine tabula rasa haben und
-- heute damit testen können".
--
-- Am Testtag in der Halle wird ausprobiert, vertippt, abgebrochen und noch
-- einmal von vorn angefangen. Bisher gab es dafür nur den Weg über den
-- SQL-Editor des Anbieters: Tabelle für Tabelle, in der richtigen
-- Reihenfolge, von Hand. Das macht niemand mitten in einer Schicht — und
-- wer es doch tut, vergisst eine Tabelle und wundert sich nachher über
-- Zahlen, die aus Resten kommen.
--
-- WAS DIESE MIGRATION NICHT TUT
--
-- Sie löscht nichts. Sie legt eine Funktion an. Gelöscht wird erst, wenn
-- ein Mensch sie aufruft — mit dem Bestätigungswort in der Hand. Das ist
-- der Unterschied, den `keine_zerstoerung.sh` seit dieser Runde kennt.
--
-- WARUM DAS ÜBERHAUPT VERANTWORTBAR IST
--
-- Weil fast nichts verloren geht. An den Erfassungstabellen hängt seit 0072
-- der Auslöser `erfassung_journal_schreiben()`; er schreibt bei jedem
-- Löschen die ganze alte Zeile als jsonb ins `erfassung_journal`.
--
-- 16 der 19 geleerten Tabellen tragen ihn. Die drei ohne sind die des
-- Warenausgang-Imports: `ausgang_datei`, `ausgang_zeile` und
-- `lieferung_import`. Sie sind keine Messung der Halle, sondern der
-- eingelesene Inhalt einer Excel-Datei, die der Betrieb weiterhin hat und
-- erneut hochladen kann — deshalb hat 0055 ihnen nie einen Auslöser
-- gegeben.
--
-- (0072 nennt 17 Tabellen; `marge_messung` steht darunter, wurde aber schon
-- in 0048 abgeworfen. Die Schleife überspringt sie per `to_regclass`, es
-- sind also 16 lebende. Nachgemessen an der Demo-Saison: 10 030 gelöschte
-- Zeilen, 9 710 davon im Journal — die 320 fehlenden waren `ausgang_zeile`
-- und `lieferung_import`; `ausgang_datei` stand dort zufällig leer und ist
-- mir bei der Messung entgangen. Gezählt wird die Wahrheit hier deshalb aus
-- `pg_trigger`, nicht aus einer Messung.)
--
-- Genau so steht es auch in der Oberfläche. Ein Versprechen, das nur zu
-- 97 % gilt, wäre schlimmer als keines.
--
-- WAS STEHEN BLEIBT
--
-- Die Stammdaten: die 42 Chargen der Anbauplanung, die Sorten mit ihren
-- Kaliber-Grenzen, die Gebinde mit ihrer Tara, die Käufer, die datierten
-- Sortierschemata, die Konten, die Einstellungen, die bestätigten
-- Artikel-Zuordnungen des Warenausgangs und die Quelle, aus der er kommt.
-- Nach dem Leeren steht die App genau so da wie nach dem Einrichten: leer,
-- aber arbeitsfähig. Wer auch die Stammdaten neu will, spielt setup.sql in
-- ein frisches Projekt ein — dafür ist der Knopf nicht da.
--
-- TEMPO
--
-- Gemessen auf der lokalen Datenbank, alles in einer Transaktion, mit
-- Journal: eine volle Demo-Saison (10 030 Zeilen) in 281 ms; die 45-fache
-- Menge des Lasttests (270 000 Zeilen) in 6,2 s. Supabase gibt einem
-- Angemeldeten 30 s, seit setup.sql das Limit hochsetzt. Läuft es doch
-- einmal hinein, bricht die ganze Transaktion ab und es ist *nichts*
-- gelöscht — halb geleert gibt es nicht.
--
-- Die Auswertung rechnet die Funktion nicht selbst neu. Das ist derselbe
-- Grund wie bei `demo_daten_laden()`: ein API-Aufruf hat sein eigenes
-- Zeitlimit, und das Rechnen ist der teuerste Teil. Die App ruft
-- `auswertung_aktualisieren()` danach getrennt auf; auf der leeren
-- Datenbank läuft das durch (gemessen: 2,8 s) und lässt jede gespeicherte
-- Auswertung leer zurück — das Lagermanagement sagt dann wieder „Noch
-- keine auswertbaren Daten".
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Was gerade dasteht — ohne etwas anzufassen
-- ---------------------------------------------------------------------
-- Die Oberfläche soll die Zahlen nennen können, bevor gedrückt wird. „Alles
-- löschen" ist eine Behauptung; „309 Arbeiten, 844 Paletten, 187
-- Lieferungen löschen" ist eine Auskunft.
create or replace function erfassung_umfang()
returns table (tabelle text, was text, zeilen bigint)
language sql stable security definer set search_path = public as $$
  select * from (values
    ('auftrag',                 'Arbeiten (auch laufende)',          (select count(*) from auftrag)),
    ('auftrag_palette',         'gezählte Paletten je Arbeit',       (select count(*) from auftrag_palette)),
    ('auftrag_gebinde',         'gezählte Gebinde je Arbeit',        (select count(*) from auftrag_gebinde)),
    ('auftrag_angabe',          'Antworten aus dem Abschluss',       (select count(*) from auftrag_angabe)),
    ('auftrag_teilnehmer',      'Teilnehmer an Arbeiten',            (select count(*) from auftrag_teilnehmer)),
    ('palette',                 'Eingangspaletten',                  (select count(*) from palette)),
    ('lieferung',               'Lieferungen',                       (select count(*) from lieferung)),
    ('lieferung_import',        'Zuordnungen Lieferung ↔ Importzeile', (select count(*) from lieferung_import)),
    ('sortier_lauf',            'Sortierläufe',                      (select count(*) from sortier_lauf)),
    ('sortier_gewicht',         'gemessene Gewichtsstufen',          (select count(*) from sortier_gewicht)),
    ('schimmel_messung',        'Messungen von Faulem',              (select count(*) from schimmel_messung)),
    ('ausschuss_messung',       'Ausschuss-Wägungen',                (select count(*) from ausschuss_messung)),
    ('ausgang_wiegung',         'Wägungen fertiger Paletten',        (select count(*) from ausgang_wiegung)),
    ('verdunstung_wiegung',     'Lagerkontroll-Wägungen',            (select count(*) from verdunstung_wiegung)),
    ('kontrollpalette',         'Kontrollpaletten',                  (select count(*) from kontrollpalette)),
    ('kontrollpalette_wiegung', 'Wägungen der Kontrollpaletten',     (select count(*) from kontrollpalette_wiegung)),
    ('ausgang_datei',           'hochgeladene Warenausgangsdateien', (select count(*) from ausgang_datei)),
    ('ausgang_zeile',           'Zeilen aus Warenausgangsdateien',   (select count(*) from ausgang_zeile)),
    ('charge_vorlauf',          'Angaben zum Erfassungsbeginn',      (select count(*) from charge_vorlauf))
  ) as t(tabelle, was, zeilen)
  where zeilen > 0
  order by zeilen desc;
$$;

comment on function erfassung_umfang() is
  'Was der Löschknopf treffen würde, Tabelle für Tabelle, ohne etwas zu ändern. '
  'Nur Zeilen mit Inhalt. Dieselben 19 Tabellen, die erfassung_leeren() leert — '
  'die Liste hier und die Liste dort müssen deckungsgleich bleiben, sonst nennt '
  'die Oberfläche eine kleinere Zahl, als sie dann löscht (0080).';

revoke all on function erfassung_umfang() from public;
grant execute on function erfassung_umfang() to authenticated;


-- ---------------------------------------------------------------------
-- 2. Der Löschknopf
-- ---------------------------------------------------------------------
-- Die Reihenfolge ist nachgemessen, nicht geraten: jede Tabelle steht vor
-- der, auf die sie zeigt. Auf `on delete cascade` wird bewusst NICHT
-- vertraut, obwohl es die halbe Arbeit täte — eine eigene Anweisung je
-- Tabelle ist die einzige Art, die Reihenfolge festzulegen und im Journal
-- ablesbar zu machen, welche Tabelle wann wie viele Zeilen verloren hat.
--
-- Das Bestätigungswort ist kein Zierrat. Ein Knopf, der mit einem Tipper
-- eine Saison wegnimmt, wird irgendwann versehentlich getroffen — am
-- ehesten von dem, der ihn am besten kennt.
create or replace function erfassung_leeren(p_bestaetigung text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  v_vorher  bigint;
  v_journal bigint;
  v_zeile   record;
  v_bericht text := '';
begin
  -- Dieselbe Regel wie bei demo_daten_entfernen(): Wer über die App kommt,
  -- muss Betriebsleiter sein. Im SQL-Editor gibt es keine Anmeldung
  -- (auth.uid() ist null) — dort darf es weiterhin gehen, sonst wäre der
  -- Weg zu, wenn die App gerade nicht läuft.
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Die Erfassung leeren darf nur der Betriebsleiter.';
  end if;

  if p_bestaetigung is distinct from 'ALLES LOESCHEN' then
    raise exception E'Zum Leeren fehlt das Bestätigungswort.\nEs lautet: ALLES LOESCHEN';
  end if;

  select count(*) into v_journal from erfassung_journal;

  -- Der Umfang, bevor er verschwindet — für den Rückgabetext.
  for v_zeile in select was, zeilen from erfassung_umfang() loop
    v_bericht := v_bericht || format('%s %s, ', v_zeile.zeilen, v_zeile.was);
  end loop;

  select count(*) into v_vorher from palette;

  -- Von den Blättern zur Wurzel. Jede dieser Zeilen geht durch den
  -- Journal-Auslöser, sofern die Tabelle ihn trägt (16 von 19 tun es).
  --
  -- `where true` ist kein Zierrat und keine Umgehung, sondern Pflicht:
  -- Supabase lässt die API-Verbindung mit der Sicherung „safeupdate"
  -- laufen, und die weist ein DELETE ohne WHERE ab — auch im Rumpf einer
  -- Funktion. Ohne diese drei Wörter liefe der Knopf auf dem Prüfstand
  -- durch und auf der echten Seite in einen Fehler. `pruefung.sql` hat
  -- dafür eine eigene Wache; sie hat genau das hier gefunden.
  -- Gelesen heisst es: alle Zeilen, mit Absicht.
  delete from sortier_gewicht where true;
  delete from sortier_lauf where true;
  delete from auftrag_palette where true;
  delete from auftrag_angabe where true;
  delete from auftrag_gebinde where true;
  delete from auftrag_teilnehmer where true;
  delete from schimmel_messung where true;
  delete from ausschuss_messung where true;
  delete from ausgang_wiegung where true;
  delete from verdunstung_wiegung where true;
  delete from auftrag where true;
  delete from kontrollpalette_wiegung where true;
  delete from kontrollpalette where true;
  delete from lieferung_import where true;
  delete from lieferung where true;
  delete from ausgang_zeile where true;
  delete from ausgang_datei where true;
  delete from charge_vorlauf where true;
  delete from palette where true;

  -- Die Auswertung gilt ab jetzt als veraltet; gerechnet wird getrennt.
  update auswertung_stand set geaendert_ts = now() where id = 1;

  select count(*) - v_journal into v_journal from erfassung_journal;

  v_bericht := rtrim(v_bericht, ', ');

  if v_bericht = '' then
    return 'Es war schon leer — nichts zu löschen.';
  end if;

  return format('Erfassung geleert: %s. Davon stehen %s Zeilen mit ihrem alten Inhalt '
                'im Journal und bleiben nachlesbar. Chargen, Sorten, Gebinde, Käufer, '
                'Sortierschemata, Konten und Einstellungen sind unberührt.',
                v_bericht, v_journal);
end $fn$;

comment on function erfassung_leeren(text) is
  'Leert alle Erfassungsdaten (Arbeiten, Paletten, Wägungen, Lieferungen, '
  'Lagerkontrollen, eingelesene Warenausgangsdateien) und lässt die Stammdaten '
  'stehen. Verlangt das Bestätigungswort „ALLES LOESCHEN" und den Betriebsleiter. '
  'Jede gelöschte Zeile einer Erfassungstabelle steht mit ihrem alten Inhalt im '
  'erfassung_journal; ausgang_datei, ausgang_zeile und lieferung_import tragen den '
  'Auslöser nicht und sind nur über die hochgeladene Datei wiederherstellbar. Rechnet die '
  'Auswertung nicht neu — eigener Aufruf, wie bei demo_daten_laden() (0080).';

revoke all on function erfassung_leeren(text) from public;
grant execute on function erfassung_leeren(text) to authenticated;


-- ---------------------------------------------------------------------
-- 3. Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 80 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
