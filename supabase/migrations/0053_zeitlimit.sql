-- =====================================================================
-- 0053 — Das Zeitlimit für die Auswertung hochsetzen
--
-- Supabase gibt jeder Abfrage über die API ein Zeitlimit, je nach Rolle:
-- anon 3 Sekunden, authenticated 8 Sekunden. Das ist keine Frage des
-- Tarifs, sondern eine Einstellung an der Rolle — im Gratis-Tarif genauso
-- änderbar wie im bezahlten.
--
-- Acht Sekunden reichen für alles, was die Halle tut: eine Palette zählen,
-- eine Wägung eintragen, eine Arbeit abschliessen. Sie reichen nicht für
-- das, was danach kommt: auswertung_aktualisieren() rechnet in einem Zug
-- alle Sichten neu — Sortierläufe, Kaliberverteilung, Schimmelmodell,
-- Massenkaskade. Das ist ein Stapellauf über die ganze Saison, und er
-- wird mit jeder Charge länger, nicht kürzer. Auf einer kleinen Instanz
-- ist er schon bei der Demo-Saison über acht Sekunden.
--
-- Darum: 30 Sekunden für angemeldete Benutzer. Warum nicht mehr: Supabase
-- lässt für Dashboard- und Client-Abfragen höchstens 60 Sekunden zu, und
-- eine Abfrage, die eine halbe Minute hält, ist die Obergrenze dessen, was
-- ein Mensch vor dem Bildschirm noch als "es rechnet" durchgehen lässt.
-- Alles darüber wäre kein Zeitlimit-Problem mehr, sondern ein Zeichen,
-- dass die Rechnung selbst zu teuer geworden ist.
--
-- anon bleibt bei drei Sekunden. Wer nicht angemeldet ist, hat hier nichts
-- zu rechnen; ein knappes Limit ist dort eine Sicherung, keine Bremse.
-- =====================================================================

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    raise notice 'Zeitlimit: Rolle authenticated gibt es hier nicht — übersprungen';
    return;
  end if;

  -- Steht es schon auf 30s, ändern wir nichts (und melden auch nichts):
  -- die Datei läuft bei jeder Aktualisierung mit.
  if exists (
    select 1 from pg_roles
     where rolname = 'authenticated'
       and 'statement_timeout=30s' = any(coalesce(rolconfig, '{}'))
  ) then
    return;
  end if;

  alter role authenticated set statement_timeout = '30s';
  raise notice 'Zeitlimit für angemeldete Benutzer auf 30 Sekunden gesetzt (vorher 8)';

exception
  -- Auf einer fremden Datenbank darf man vielleicht keine Rollen ändern.
  -- Das ist kein Grund, die ganze Einrichtung scheitern zu lassen: alles
  -- andere läuft auch mit acht Sekunden, nur das Neurechnen der Auswertung
  -- kann dann abbrechen. Die Meldung sagt, was von Hand zu tun wäre.
  when insufficient_privilege or wrong_object_type then
    raise notice 'Zeitlimit liess sich nicht setzen (keine Berechtigung). '
                 'Von Hand im SQL-Editor: alter role authenticated set statement_timeout = ''30s'';';
end $$;

-- Die API-Schicht (PostgREST) liest die Rolleneinstellungen beim Start.
-- Ohne dieses Signal gälte das neue Limit erst nach dem nächsten Neustart.
-- NOTIFY an einen Kanal, auf dem niemand lauscht, ist ein Nichts — auf dem
-- Prüfstand also unbedenklich.
notify pgrst, 'reload config';
