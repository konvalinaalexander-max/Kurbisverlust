-- sicht: v_datenlage
-- Je Charge: wie viel überhaupt erfasst ist — Paletten, davon mit bekanntem Netto, Wiegungen, Schimmelmessungen, Sortierläufe, Arbeiten. Die Zahlen sagen, wie belastbar alles andere zu dieser Charge ist.

 SELECT charge_nr,
    sorte,
    schlag,
    n_paletten,
    n_paletten_mit_netto,
    eingang_netto_kg AS eingang_kg,
    ( SELECT count(*) AS count
           FROM verdunstung_wiegung w
          WHERE w.charge_nr = r.charge_nr) AS n_wiegungen,
    ( SELECT count(*) AS count
           FROM auftrag a
             JOIN schimmel_messung s ON s.auftrag_id = a.id
          WHERE a.charge_nr = r.charge_nr) AS n_schimmel,
    ( SELECT count(*) AS count
           FROM sortier_lauf l
          WHERE l.charge_nr = r.charge_nr) AS n_sortierlaeufe,
    ( SELECT count(*) AS count
           FROM auftrag a
          WHERE a.charge_nr = r.charge_nr) AS n_auftraege
   FROM v_charge_rueckgrat r;
