-- 0120 — Oettli und Trüeb im Chargenregister
--
-- WARUM
--
-- Der Betrieb, 22. Oktober: „Ötli und Trüb … beim Wareneingang in der
-- Journal-App hinzugefügt, die Wareneingänge gemacht, im Google Sheet sind
-- sie drin — aber sie kommen nicht in der Kürbis-App an."
--
-- Das Erntejournal führt keine Chargennummer. Die App findet die Charge einer
-- Journalzeile über Schlag und Sorte (src/lib/import.ts, wie das Register aus
-- 0003). Für die zwei neuen Schläge stand im Register nichts, also blieben
-- ihre Zeilen ohne Charge und wurden nicht übernommen. Die Nummern hatte der
-- Betrieb in Runde AS genannt (Oettli 1719, Trüeb 1763), die Sorten jetzt:
-- Oettli liefert Kaori Kuri, Trüeb Amoro. Geschrieben wie im Journal — „so
-- steht's im Journal, dann in der Kürbis-App auch so".
--
-- Steht eine der beiden Nummern schon im Register (von Hand unter Stammdaten
-- angelegt, etwa als „Ötli" oder „Trüb"), bekommt sie Schlag und Sorte des
-- Journals; sonst fände der Abgleich sie nicht. Hält eine andere Nummer
-- schon denselben Schlag mit derselben Sorte, bleibt alles, wie es ist, und
-- setup.sql sagt es als Warnung — welche Nummer stimmt, weiss nur der Betrieb.

do $$
declare r record; v_andere int;
begin
  for r in select * from (values (1719, 'Oettli', 'Kaori Kuri', 2026),
                                 (1763, 'Trüeb',  'Amoro',      2026)) v(nr, schlag, sorte, saison)
  loop
    select nr into v_andere from charge
     where schlag = r.schlag and sorte = r.sorte and saison = r.saison and nr <> r.nr;
    if v_andere is not null then
      raise warning 'Chargenregister: % · % (%) steht schon unter Charge %, nicht unter % — nichts geändert; unter Stammdaten → Chargen klären.',
        r.schlag, r.sorte, r.saison, v_andere, r.nr;
      continue;
    end if;
    insert into charge (nr, schlag, sorte, saison) values (r.nr, r.schlag, r.sorte, r.saison)
    on conflict (nr) do update set schlag = excluded.schlag, sorte = excluded.sorte
     where (charge.schlag, charge.sorte) is distinct from (excluded.schlag, excluded.sorte);
  end loop;
end $$;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 120 $$;
