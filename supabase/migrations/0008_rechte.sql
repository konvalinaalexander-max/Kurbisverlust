-- =====================================================================
-- 0008 — Rechte
--
-- Was ein Angemeldeter *darf*, entscheiden die Policies aus 0002. Die
-- Grants hier öffnen nur überhaupt die Tür; ohne passende Policy sieht
-- und ändert man trotzdem nichts.
-- =====================================================================

grant usage on schema public to anon, authenticated;

-- Lesen: alle Tabellen und Auswerte-Views.
grant select on all tables in schema public to authenticated;

-- Schreiben: nur die Tabellen, in die tatsächlich geschrieben wird.
grant insert, update, delete on
  profil, gebinde, sorte_kaliber, charge, palette, einstellung,
  auftrag, auftrag_teilnehmer, auftrag_palette,
  schimmel_messung, ausschuss_messung, verdunstung_wiegung, marge_messung,
  sortier_lauf, sortier_gewicht
  to authenticated;

grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- Neue Objekte späterer Migrationen erben dieselben Rechte.
alter default privileges in schema public grant select on tables to authenticated;
alter default privileges in schema public grant usage, select on sequences to authenticated;
alter default privileges in schema public grant execute on functions to authenticated;
