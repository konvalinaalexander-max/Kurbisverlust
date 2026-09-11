-- sicht: v_auftrag_angabe
-- Die freien Angaben zu einer Arbeit (Palox-Stand, Kistensystem, Notizen) als Schlüssel-Wert-Paare, je Arbeit eine Zeile pro Angabe.

 SELECT DISTINCT ON (auftrag_id, schluessel) auftrag_id,
    schluessel,
    wert,
    ts,
    erfasser
   FROM auftrag_angabe
  ORDER BY auftrag_id, schluessel, ts DESC, id DESC;
