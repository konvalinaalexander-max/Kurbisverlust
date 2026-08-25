-- =====================================================================
-- 0010 — Gebinde-Tara aus dem Erntejournal übernehmen
--
-- Die Leergewichte kennt der Betrieb bereits — sie stehen fest im Code der
-- Wareneingang-App (src/lib/constants.ts). Sie hier einzutragen erspart dem
-- Betriebsleiter das Nachwiegen und macht das Netto sofort berechenbar.
--
--   Netto = Brutto − 25 (Palette) − Kisten × Tara(Gebindeart)
--
-- Quelle: Kürbis-Erntejournal, PALETTE_TARA_KG = 25 und GEBINDEARTEN.
-- „G2" ist der Standard, den die App bei leerem Gebinde-Feld annimmt.
--
-- Einzeln einspielbar; überschreibt vorhandene Werte bewusst nicht, damit eine
-- von Hand nachgewogene Zahl erhalten bleibt (on conflict do nothing).
-- =====================================================================

insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette, bemerkung) values
  ('G2',         1.500, 25.000, 'Standardkiste (auch bei leerem Gebinde-Feld im Journal)'),
  ('IFCO 6410',  1.360, 25.000, 'IFCO-Klappkiste'),
  ('IFCO 6416',  1.680, 25.000, 'IFCO-Klappkiste'),
  ('IFCO 6424',  2.000, 25.000, 'IFCO-Klappkiste')
on conflict (art) do nothing;
