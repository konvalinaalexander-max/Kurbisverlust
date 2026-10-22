-- =====================================================================
-- 0120 — Oettli und Trüeb im Chargenregister
--
-- Das Erntejournal führt keine Chargennummer; die App findet die Charge
-- einer Journalzeile über Schlag und Sorte (src/lib/import.ts, Tests in
-- test/import.test.ts). Hier: (a) die zwei neuen Schläge stehen im Register,
-- mit Nummer, Sorte und Saison und geschrieben wie im Journal — sonst fände
-- der Abgleich ihre Zeilen nicht; (b) Stand 120.
-- =====================================================================
do $$
declare r record;
begin
  for r in select * from (values (1719, 'Oettli', 'Kaori Kuri'), (1763, 'Trüeb', 'Amoro')) v(nr, schlag, sorte) loop
    assert exists (select 1 from charge c where c.nr = r.nr and c.schlag = r.schlag and c.sorte = r.sorte and c.saison = 2026),
      format('0120 (a1): Charge %s ist nicht %s · %s (2026), sondern %s', r.nr, r.schlag, r.sorte,
             coalesce((select format('%s · %s (%s)', c.schlag, c.sorte, c.saison) from charge c where c.nr = r.nr), 'nicht im Register'));
    assert (select count(*) from charge c where c.schlag = r.schlag and c.sorte = r.sorte and c.saison = 2026) = 1,
      format('0120 (a2): %s · %s steht mehr als einmal im Register — der Abgleich wüsste nicht, welche Charge', r.schlag, r.sorte);
  end loop;
  assert schema_stand() >= 120, format('0120 (b1): schema_stand() = %s', schema_stand());
  raise notice 'OK  0120 — Oettli · Kaori Kuri = 1719 und Trüeb · Amoro = 1763 stehen im Register, geschrieben wie im Journal';
end $$;

select '——— 0120 Oettli und Trüeb im Chargenregister ———' as ergebnis;
