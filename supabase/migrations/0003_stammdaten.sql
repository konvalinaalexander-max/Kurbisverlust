-- =====================================================================
-- 0003 — Stammdaten der laufenden Saison
--
-- Quelle: Spec §6 (Kaliber-Grenzen) und §7 (Charge-Registry).
-- Kanonische Sorten-Schreibweise ist die hier verwendete; im Grenzen-Sheet
-- stand fälschlich „Lektor" statt „Lekor".
-- =====================================================================

insert into einstellung (schluessel, wert, bemerkung) values
  ('saison_aktuell',   '2026'::jsonb,
   'Erntesaison, auf die sich Chargen und Auswertung beziehen.'),
  ('saison_ende',      '"2027-03-31"'::jsonb,
   'Stichtag der Hochrechnung: bis dahin wird die Lagerdauer projiziert.'),
  ('zuordnung_fenster_h', '12'::jsonb,
   'Zeitfenster (Stunden) um die Dateizeit, in dem nach einem passenden Auftrag gesucht wird.'),
  ('reinigung_standard',
   '{"overflow_ab": 60000, "min_gramm": 100, "dubletten_zusammenfassen": true}'::jsonb,
   'Voreinstellung der CSV-Reinigung (Spec §4). Pro Lauf umstellbar; die tatsächlich '
   'verwendeten Parameter stehen in sortier_lauf.reinigung.')
on conflict (schluessel) do nothing;

-- ---------- Sorten-Kaliber-Grenzen (Gramm, Konvention [untere, obere)) ----
insert into sorte_kaliber (sorte, verlust_unter, kaliber_baender, kanal_ab) values
  ('Orangita',      300, '[[300,800],[800,2000]]',                        2000),
  ('Kaori Kuri',    600, '[[600,1100],[1100,1600],[1600,2000]]',          2000),
  ('Mieluna',       500, '[[500,800],[800,1300],[1300,1800],[1800,2000]]', 2000),
  ('Amoro',         600, '[[600,1100],[1100,1600],[1600,2000]]',          2000),
  ('Butterkin',     500, '[[500,600],[600,1200],[1200,1800],[1800,2000]]', 2000),
  ('Bolp 5110',     600, '[[600,1100],[1100,1600],[1600,2000]]',          2000),
  ('Orange Summer', 600, '[[600,1100],[1100,1600],[1600,2000]]',          2000),
  ('Lekor',         700, '[[700,1200],[1200,1700],[1700,2000]]',          2000),
  ('Fictor',        600, '[[600,1100],[1100,1600],[1600,2000]]',          2000),
  ('Tiana',         500, '[[500,800],[800,1300],[1300,1800],[1800,2000]]', 2000),
  ('Ker Madec',     600, '[[600,1100],[1100,1600],[1600,2000]]',          2000)
on conflict (sorte) do update
  set verlust_unter   = excluded.verlust_unter,
      kaliber_baender = excluded.kaliber_baender,
      kanal_ab        = excluded.kanal_ab;

-- ---------- Charge-Registry (Schlag × Sorte → Chargennummer) -------------
insert into charge (nr, schlag, sorte, saison) values
  (1598, 'Illnau Bruno',    'Kaori Kuri',    2026),
  (1599, 'Illnau Bruno',    'Orangita',      2026),
  (1601, 'Illnau Bruno',    'Mieluna',       2026),
  (1603, 'Illnau Gross',    'Bolp 5110',     2026),
  (1604, 'Illnau Gross',    'Orangita',      2026),
  (1605, 'Illnau Gross',    'Orange Summer', 2026),
  (1606, 'Illnau Gross',    'Lekor',         2026),
  (1607, 'Illnau Gross',    'Amoro',         2026),
  (1608, 'Illnau Gross',    'Butterkin',     2026),
  (1609, 'Illnau Gross',    'Kaori Kuri',    2026),
  (1610, 'Illnau Gross',    'Fictor',        2026),
  (1611, 'Negi Thalheim',   'Tiana',         2026),
  (1612, 'Slowgrow Uster',  'Butterkin',     2026),
  (1613, 'Slowgrow Uster',  'Tiana',         2026),
  (1614, 'Slowgrow Uster',  'Kaori Kuri',    2026),
  (1615, 'Slowgrow Uster',  'Ker Madec',     2026),
  (1616, 'Slowgrow Uster',  'Lekor',         2026),
  (1617, 'Slowgrow Uster',  'Orangita',      2026),
  (1618, 'Slowgrow Uster',  'Orange Summer', 2026),
  (1619, 'Gossau Eberhard', 'Kaori Kuri',    2026),
  (1620, 'Gossau Eberhard', 'Orangita',      2026),
  (1623, 'Agasul Rüegg',    'Mieluna',       2026),
  (1624, 'Agasul Rüegg',    'Butterkin',     2026),
  (1625, 'Agasul Rüegg',    'Amoro',         2026),
  (1626, 'Agasul Rüegg',    'Tiana',         2026),
  (1627, 'Agasul Rüegg',    'Fictor',        2026),
  (1628, 'Agasul Baumann',  'Kaori Kuri',    2026),
  (1630, 'Rümlang Keller',  'Kaori Kuri',    2026),
  (1631, 'Rümlang Keller',  'Mieluna',       2026),
  (1632, 'Andi Ball',       'Tiana',         2026),
  (1633, 'Daniel Böhler',   'Tiana',         2026),
  (1634, 'Daniel Böhler',   'Amoro',         2026),
  (1635, 'Daniel Böhler',   'Kaori Kuri',    2026),
  (1636, 'Klaus Böhler',    'Tiana',         2026),
  (1637, 'Klaus Böhler',    'Amoro',         2026),
  (1638, 'Klaus Böhler',    'Kaori Kuri',    2026),
  (1646, 'Gossau Eberhard', 'Butterkin',     2026),
  (1647, 'Bonomo',          'Tiana',         2026),
  (1648, 'Russikon BundB',  'Orange Summer', 2026),
  (1649, 'Rümlang Sauter',  'Butterkin',     2026),
  (1650, 'Rümlang Sauter',  'Tiana',         2026),
  (1651, 'Rümlang Sauter',  'Kaori Kuri',    2026)
on conflict (nr) do update
  set schlag = excluded.schlag, sorte = excluded.sorte, saison = excluded.saison;

-- ---------- Gebinde ------------------------------------------------------
-- Die Gebindearten kommen aus der Journal-App und werden beim Paletten-Import
-- automatisch angelegt. Die Tara-Gewichte kennt nur der Betrieb — bis sie
-- eingetragen sind, bleibt tara NULL und das Netto der Palette NULL
-- (Leer ≠ 0). Zu pflegen unter Stammdaten → Gebinde.
