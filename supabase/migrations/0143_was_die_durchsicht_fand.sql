-- 0143 — Was die Durchsicht fand (Runde BK)
--
-- Der Betrieb am 9. November: „Take a good look at all the last few changes …
-- find bugs, things that don't make sense, don't add up, mistakes in
-- reasoning … fix." Die Runde hat 0136 bis 0141 von zwei unabhängigen Lesern
-- gegen den Stand 135 prüfen lassen und jeden Fund nachgerechnet. Vier sind
-- Fehler der Runde selbst und hier behoben:
--
--   1. lieferungen_nachordnen() (0141), Stufe 0, las die Sorte eines
--      Mix-Anteils mit ':mix:(.+)$'. Spalte W ist freier Text: steht dort
--      „mix", ist die Kennung …:mix:1, die Laufnummer galt als Sorte, und der
--      Fremdschlüssel auf sorte_kaliber brach jeden Rechenlauf ab — „Neu
--      rechnen" und der Zeitplan, bis jemand die Zeile findet. Jetzt
--      verankert (mix_sorte), und zurückgeholt wird nur auf eine Sorte, die es
--      gibt.
--   2. Stufe 2 (Produzent und Artikel) kannte die Mix-Regel nicht: ein
--      Mix-Anteil mit unbekannter Nummer bekam über den Produzenten doch die
--      Charge einer anderen Sorte, Stufe 0 holte ihn zurück, Stufe 2 setzte
--      ihn wieder — bei jedem Lauf. Jetzt lässt Stufe 2 Mix-Anteile aus.
--   3. Ein Lieferschein ohne Charge ging nach dem Eingang auf alle Chargen
--      seiner Sorte — auch auf eine, die schon vor dem Liefertag am Lager leer
--      bestätigt war (0134). Ihr Posten „mehr weg als gerechnet" (0138)
--      schrumpfte, und die Chargen mit Ware behielten zu viel. Jetzt wie bei
--      Hagel (0138): nicht auf die leere, solange die Sorte eine andere hat.
--   4. v_verschenkt_charge zeigte ein Minus, wenn die gewogenen Kisten einer
--      Charge unter dem Sollgewicht lagen; die Kaskade rechnete dann 0. Die
--      Sicht (der Chargen-Reiter liest sie) sagt jetzt dasselbe.
--
-- Was bewusst nicht gemacht wurde (steht in ENTSCHEIDUNGEN mit Zahlen):
-- - Das Verschenkte läuft weiter über die Charge, die Perigon nennt, nicht
--   über v_lieferung_charge wie die Masse (Topf, ohne Charge, Liefertag).
-- - Ein Tierfutter-Lieferschein (Buch marge) zieht weiter vom Liegenden ab,
--   nicht vom Aussortierten — im Betrieb gibt es keinen; die Frage geht an
--   den Betrieb.
-- - erg_verlauf führt das Verschenkte nicht als eigene Linie.

-- ---------- 1. Was eine Kennung über den Mix sagt ----------
create or replace function mix_sorte(p_extern_id text) returns text
language sql immutable set search_path = public as $$
  -- quelle:position:<Spalte W>:<lauf>:mix:<Sorte> oder quelle:position:rest:mix:<Sorte> (lieferungenBauen, 0131).
  -- Verankert: steht in Spalte W selbst „mix", ist die Kennung …:mix:1 — und 1 ist keine Sorte.
  select substring(p_extern_id from '^[^:]*:[0-9]+:.+:mix:([^:]+)$')
$$;
comment on function mix_sorte(text) is
  'Die Sorte eines Mix-Anteils aus der Kennung seiner Lieferung (lieferung_import.extern_id, …:mix:<Sorte>) — leer, wenn die Kennung kein Mix-Anteil ist. Verankert an Firma, Position und dem Teil davor (0143): eine Chargennummer „mix" in Spalte W macht aus der Laufnummer keine Sorte.';
revoke all on function mix_sorte(text) from public;
grant execute on function mix_sorte(text) to authenticated;

create or replace function lieferungen_nachordnen() returns int
language plpgsql security definer set search_path = public as $$
declare v_n int; v_m int; v_z int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Lieferscheine nachordnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- Stufe 0 (0141): Ein Mix-Anteil (extern_id …:mix:<Sorte>) ist die Ware seiner Sorte nach dem
  -- Rezept, ohne Charge. Stufe 1 hat ihm bis 0141 die Charge gegeben, die Perigon für den ganzen Mix
  -- nennt — und mit ihr deren Sorte (im Betrieb 2.3 t Lekor und Orangita als Butterkin 1624/1649).
  -- Was so auf einer Charge einer anderen Sorte steht, geht zurück: ohne Charge, an seine Sorte.
  with mix as (
    select l.id, mix_sorte(li.extern_id) as sorte
      from lieferung l
      join lieferung_import li on li.lieferung_id = l.id
     where li.extern_id like '%:mix:%'
  ), zurueck as (
    update lieferung l set charge_nr = null, sorte = m.sorte
      from mix m
     where l.id = m.id and m.sorte is not null
       -- 0143: nur eine Sorte, die es gibt — sonst bräche der Fremdschlüssel den ganzen Rechenlauf ab
       and exists (select 1 from sorte_kaliber k where k.sorte = m.sorte)
       and (l.sorte is distinct from m.sorte
            or (l.charge_nr is not null
                and not exists (select 1 from charge c where c.nr = l.charge_nr and c.sorte = m.sorte)))
    returning l.id
  ), weg as (
    delete from lieferung_nachordnung n using zurueck z where n.lieferung_id = z.id
    returning 1
  )
  select count(*) into v_z from zurueck;

  -- Stufe 1 (0121): die eigene Nummer, sonst eine Perigon-Nummer an genau einer Charge.
  with offen as (
    select l.id, z.charge_extern, regexp_replace(z.charge_extern, '\D', '', 'g') as ziffern,
           mix_sorte(li.extern_id) as mix_sorte
      from lieferung l
      join lieferung_import li on li.lieferung_id = l.id
      join ausgang_zeile z on z.id = li.zeile_id
     where l.charge_nr is null and li.extern_id not like '%:rest' and li.extern_id not like '%:rest:mix:%'
       and coalesce(z.charge_extern, '') ~ '\d'
  ), geloest as (
    select o.id, o.ziffern, o.mix_sorte,
           coalesce((select c.nr from charge c where c.nr::text = o.ziffern),
                    (select min(c.nr) from charge c where c.perigon_nr::text = o.ziffern
                      having count(*) = 1)) as charge_nr
      from offen o
  ), gesetzt as (
    update lieferung l set charge_nr = g.charge_nr, sorte = c.sorte
      from geloest g join charge c on c.nr = g.charge_nr
     where l.id = g.id and g.charge_nr is not null
       -- 0141: ein Mix-Anteil nur auf eine Charge seiner Sorte
       and (g.mix_sorte is null or c.sorte = g.mix_sorte)
    returning l.id, l.charge_nr, g.ziffern
  )
  insert into lieferung_nachordnung (lieferung_id, charge_nr, weg, nummer, grund)
  select s.id, s.charge_nr, 'nummer', s.ziffern,
         format('Die Nummer %s steht inzwischen an Charge %s.', s.ziffern, s.charge_nr)
    from gesetzt s
  on conflict (lieferung_id) do update
    set charge_nr = excluded.charge_nr, weg = excluded.weg, nummer = excluded.nummer,
        produzent = null, grund = excluded.grund, ts = now();
  get diagnostics v_n = row_count;

  -- Stufe 2 (0122): Die Nummer steht an keiner Charge. Produzent (Spalte X)
  -- und Artikel zeigen auf genau eine Charge der Saison — dann diese.
  with offen as (
    select l.id, l.datum, z.produzent, z.artikel, z.preisgruppe,
           regexp_replace(z.charge_extern, '\D', '', 'g') as ziffern
      from lieferung l
      join lieferung_import li on li.lieferung_id = l.id
      join ausgang_zeile z on z.id = li.zeile_id
     where l.charge_nr is null and li.extern_id not like '%:rest' and li.extern_id not like '%:rest:mix:%'
       and coalesce(z.charge_extern, '') ~ '\d'
       -- 0143: ein Mix-Anteil ist nach Rezept verteilt; Produzent und Artikel des Mix sagen nichts über seine Charge
       and mix_sorte(li.extern_id) is null
       and name_norm(z.produzent) is not null
       and not exists (select 1 from charge x
                        where x.nr::text = regexp_replace(z.charge_extern, '\D', '', 'g')
                           or x.perigon_nr::text = regexp_replace(z.charge_extern, '\D', '', 'g'))
  ), mit as (
    -- wie schlag_von_produzent(), aber v_perigon_produzent einmal gelesen statt je Lieferschein
    select o.*, coalesce(pp.schlag, (select min(c.schlag) from charge c where name_norm(c.schlag) = name_norm(o.produzent))) as schlag,
           (artikel_einordnen(o.artikel, o.preisgruppe)).gruppe as gruppe
      from offen o
      left join v_perigon_produzent pp on pp.produzent = name_norm(o.produzent)
  ), geloest as (
    select m.id, m.ziffern, m.produzent, m.schlag, m.gruppe,
           (select min(c.nr) from charge c join sorte_kaliber sk on sk.sorte = c.sorte
             where name_norm(c.schlag) = name_norm(m.schlag) and sk.artikelgruppe = m.gruppe
               and c.saison = saison_von(m.datum)
            having count(*) = 1) as charge_nr
      from mit m
     where m.schlag is not null and m.gruppe is not null and m.gruppe not in ('Mix', 'andere')
  ), gesetzt as (
    update lieferung l set charge_nr = g.charge_nr, sorte = c.sorte
      from geloest g join charge c on c.nr = g.charge_nr
     where l.id = g.id and g.charge_nr is not null
    returning l.id, l.charge_nr, g.ziffern, g.produzent, g.schlag, g.gruppe
  )
  insert into lieferung_nachordnung (lieferung_id, charge_nr, weg, nummer, produzent, grund)
  select s.id, s.charge_nr, 'produzent', s.ziffern, s.produzent,
         format('Die Nummer %s steht an keiner Charge. Perigon nennt als Produzent %s — das ist %s —, und %s hat genau eine Charge mit %s: %s.',
                s.ziffern, s.produzent, s.schlag, s.schlag, s.gruppe, s.charge_nr)
    from gesetzt s
  on conflict (lieferung_id) do update
    set charge_nr = excluded.charge_nr, weg = excluded.weg, nummer = excluded.nummer,
        produzent = excluded.produzent, grund = excluded.grund, ts = now();
  get diagnostics v_m = row_count;
  return v_z + v_n + v_m;
end $$;
comment on function lieferungen_nachordnen() is 'Gibt Lieferscheinen ohne Charge ihre Charge, sobald die Nummer der Datei eine kennt (eigene Nummer, sonst eine Perigon-Nummer an genau einer Charge, 0121) — oder, steht die Nummer an keiner Charge, wenn Produzent (Spalte X) und Artikel auf genau eine Charge der Saison zeigen (0122). Seit 0141 bekommt ein Mix-Anteil (extern_id …:mix:<Sorte>, nach Rezept verteilt) die genannte Charge nur, wenn sie seine Sorte ist; was früher auf eine Charge einer anderen Sorte ging, geht zuerst zurück (ohne Charge, an seine Sorte). Schreibt den Grund in lieferung_nachordnung; läuft zu Beginn jedes Rechenlaufs; gibt zurück, wie viele es waren. Seit 0143 liest sie die Sorte eines Mix-Anteils verankert (mix_sorte), holt nur auf eine Sorte zurück, die es gibt, und Stufe 2 lässt Mix-Anteile aus.';
revoke all on function lieferungen_nachordnen() from public;
grant execute on function lieferungen_nachordnen() to authenticated;

create or replace view v_lieferung_ohne_charge with (security_invoker = true) as
 WITH l AS (
         SELECT m.id,
            m.datum,
            m.sorte,
            m.kunde,
            m.masse_kg,
            m.bemerkung
           FROM v_lieferung_masse m
          WHERE m.charge_nr IS NULL AND m.masse_kg > 0::numeric AND (m.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])) AND m.datum <= heute()
        ), mit AS (
         SELECT l.id,
            l.datum,
            l.sorte,
            l.kunde,
            l.masse_kg,
            l.bemerkung,
            i.lieferung_id IS NOT NULL AS eingelesen,
            i.quelle,
            i.extern_id,
            COALESCE(i.extern_id ~~ '%:rest'::text OR i.extern_id ~~ '%:rest:mix:%'::text, false) AS rest,
            mix_sorte(i.extern_id) IS NOT NULL AS mix_anteil,
            COALESCE(z1.pos_id,
                CASE
                    WHEN split_part(i.extern_id, ':'::text, 2) ~ '^\d+$'::text THEN split_part(i.extern_id, ':'::text, 2)::bigint
                    ELSE NULL::bigint
                END) AS pos_id,
            z1.charge_extern,
            regexp_replace(COALESCE(z1.charge_extern, ''::text), '\D'::text, ''::text, 'g'::text) AS ziffern
           FROM l
             LEFT JOIN lieferung_import i ON i.lieferung_id = l.id
             LEFT JOIN ausgang_zeile z1 ON z1.id = i.zeile_id
        ), pos AS (
         SELECT m.id,
            m.datum,
            m.sorte,
            m.kunde,
            m.masse_kg,
            m.bemerkung,
            m.eingelesen,
            m.quelle,
            m.extern_id,
            m.rest,
            m.mix_anteil,
            m.pos_id,
            m.charge_extern,
            m.ziffern,
            p.n_zeilen,
            p.artikel,
            p.kg_position,
            p.nummern,
            p.kg_zugeteilt,
            ( SELECT x.nr
                   FROM charge x
                  WHERE m.ziffern <> ''::text AND x.nr::text = m.ziffern) AS eigene,
            ( SELECT array_agg(x.nr ORDER BY x.nr) AS array_agg
                   FROM charge x
                  WHERE m.ziffern <> ''::text AND x.perigon_nr::text = m.ziffern) AS an_perigon
           FROM mit m
             LEFT JOIN LATERAL ( SELECT count(*)::integer AS n_zeilen,
                    min(z.artikel) AS artikel,
                    max(z.kg_position) AS kg_position,
                    string_agg(DISTINCT NULLIF(btrim(z.charge_extern), ''::text), ', '::text ORDER BY (NULLIF(btrim(z.charge_extern), ''::text))) AS nummern,
                    COALESCE(sum(z.kg_charge) FILTER (WHERE btrim(z.charge_extern) <> ''::text AND z.kg_charge > 0::numeric), 0::numeric) AS kg_zugeteilt
                   FROM ausgang_zeile z
                  WHERE z.quelle = m.quelle AND z.pos_id = m.pos_id) p ON m.eingelesen
        ), grund AS (
         SELECT p.id,
            p.datum,
            p.sorte,
            p.kunde,
            p.masse_kg,
            p.bemerkung,
            p.eingelesen,
            p.quelle,
            p.extern_id,
            p.rest,
            p.mix_anteil,
            p.pos_id,
            p.charge_extern,
            p.ziffern,
            p.n_zeilen,
            p.artikel,
            p.kg_position,
            p.nummern,
            p.kg_zugeteilt,
            p.eigene,
            p.an_perigon,
                CASE
                    WHEN NOT p.eingelesen AND (p.bemerkung = 'ohne Chargenbezug'::text OR p.bemerkung ~~ 'Charge % (extern)'::text) THEN 'ohne_zeile'::text
                    WHEN NOT p.eingelesen THEN 'von_hand'::text
                    WHEN COALESCE(p.n_zeilen, 0) = 0 THEN 'ohne_zeile'::text
                    WHEN p.mix_anteil AND NOT p.rest AND b.sorte IS DISTINCT FROM p.sorte AND b.nr IS NOT NULL THEN 'mix'::text
                    WHEN NOT p.rest AND p.eigene IS NOT NULL THEN 'nachholen'::text
                    WHEN NOT p.rest AND cardinality(p.an_perigon) = 1 THEN 'nachholen'::text
                    WHEN NOT p.rest AND cardinality(p.an_perigon) > 1 THEN 'mehrdeutig'::text
                    WHEN NOT p.rest THEN 'unbekannt'::text
                    WHEN p.nummern IS NULL THEN 'keine_nummer'::text
                    WHEN p.kg_zugeteilt <= 0::numeric THEN 'menge_null'::text
                    ELSE 'rest'::text
                END AS grund,
            COALESCE(p.eigene,
                CASE
                    WHEN cardinality(p.an_perigon) = 1 THEN p.an_perigon[1]
                    ELSE NULL::integer
                END) AS bekannt,
                CASE
                    WHEN p.nummern ~~ '%,%'::text THEN 'die Chargen '::text || p.nummern
                    ELSE 'die Charge '::text || p.nummern
                END AS chargen_text,
            b.sorte AS bekannt_sorte
           FROM pos p
             LEFT JOIN charge b ON b.nr = COALESCE(p.eigene,
                CASE
                    WHEN cardinality(p.an_perigon) = 1 THEN p.an_perigon[1]
                    ELSE NULL::integer
                END)
        )
 SELECT id,
    datum,
    sorte,
    kunde,
    zahl(masse_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    quelle,
    pos_id,
    artikel,
        CASE
            WHEN rest THEN nummern
            ELSE COALESCE(NULLIF(btrim(charge_extern), ''::text), nummern)
        END AS nummer,
    grund,
        CASE grund
            WHEN 'von_hand'::text THEN 'Von Hand in der App erfasst, ohne Charge — dazu gibt es keine Perigon-Zeile.'::text
            WHEN 'ohne_zeile'::text THEN 'Aus Perigon eingelesen, aber die Zeile der Datei ist nicht mehr in der App.'::text
            WHEN 'mix'::text THEN format('Mix-Anteil %s nach Rezept: Perigon nennt für den ganzen Mix %s, das ist Charge %s (%s). Der Anteil geht darum ohne Charge an %s und wird nach dem Eingang auf ihre Chargen verteilt.'::text, sorte, charge_extern, bekannt, bekannt_sorte, sorte)
            WHEN 'nachholen'::text THEN format('Perigon nennt %s; die Nummer steht inzwischen an Charge %s — beim Einlesen kannte die App sie noch nicht.'::text, charge_extern, bekannt)
            WHEN 'mehrdeutig'::text THEN format('Perigon nennt %s; diese Perigon-Nummer steht an mehreren Chargen (%s), und der Artikel sagt nicht, an welcher.'::text, charge_extern, array_to_string(an_perigon, ', '::text))
            WHEN 'unbekannt'::text THEN format('Perigon nennt %s — diese Nummer steht an keiner Charge der App.'::text, charge_extern)
            WHEN 'keine_nummer'::text THEN 'In Perigon steht bei dieser Position keine Chargennummer (Spalte W „AuftragsChargeManuell" ist leer).'::text
            WHEN 'menge_null'::text THEN format('Perigon nennt %s, teilt aber keine Menge zu (Spalte S „AufPosBatchQuantity Charge" ist 0) — die ganze Position bleibt ohne Charge.'::text, chargen_text)
            ELSE format('Perigon teilt %s nur %s von %s kg zu (Spalte S); der Rest hat keine Charge.'::text, chargen_text, to_char(round(kg_zugeteilt), 'FM999999990'::text), to_char(round(kg_position), 'FM999999990'::text))
        END AS satz,
        CASE grund
            WHEN 'von_hand'::text THEN 'Die Charge an der Lieferung nachtragen — oder den Lieferschein in Perigon führen und die Datei neu einlesen.'::text
            WHEN 'ohne_zeile'::text THEN 'Die Datei unter Betrieb → Warenausgang neu einlesen.'::text
            WHEN 'mix'::text THEN 'Nichts — so verteilt die App den Mix nach Rezept. Stimmt das Rezept nicht: Betrieb → Stammdaten → Sorten und Artikel, Karte „Kürbis Mix", danach die Dateien neu einlesen.'::text
            WHEN 'nachholen'::text THEN 'Nichts — beim nächsten Rechnen („Neu rechnen" oben) bekommt der Lieferschein die Charge von selbst.'::text
            WHEN 'mehrdeutig'::text THEN 'Unter Betrieb → Stammdaten → Chargen die Nummer nur bei der richtigen Charge lassen; beim nächsten Rechnen bekommt der Lieferschein sie.'::text
            WHEN 'unbekannt'::text THEN 'Unter Betrieb → Stammdaten → Chargen bei der richtigen Charge als Perigon-Nr. eintragen; beim nächsten Rechnen bekommt der Lieferschein sie von selbst.'::text
            ELSE 'In Perigon die Charge und die Menge je Charge (Spalten W und S) eintragen, dann die Datei unter Betrieb → Warenausgang neu einlesen.'::text
        END AS tun
   FROM grund g;
comment on view v_lieferung_ohne_charge is 'Jeder Lieferschein ohne Charge (0125) — dieselben wie v_ohne_charge: verkauft, mit Masse, bis heute — mit Firma und Position der Perigon-Zeile, Artikel, den Nummern aus Spalte W und dem Grund: von_hand (in der App erfasst), ohne_zeile (Zeile der Datei fehlt), nachholen (die Nummer steht inzwischen an einer Charge), mehrdeutig (Perigon-Nummer an mehreren Chargen), unbekannt (Nummer an keiner Charge), keine_nummer (Spalte W leer), menge_null (Chargen genannt, Spalte S = 0), rest (S kleiner als die Position; seit 0141 auch der Rest einer Mix-Position), mix (seit 0141: Anteil einer anderen Sorte aus einem Mix, nach Rezept ohne Charge — so verteilt, nichts zu tun). satz sagt es in Worten, tun was zu tun ist. Nichts wird umgebucht.';
grant select on v_lieferung_ohne_charge to authenticated;

-- ---------- 2. Ohne Charge nicht auf eine leere Charge ----------
create or replace view v_lieferung_charge with (security_invoker = true) as
 WITH topf AS MATERIALIZED (
         SELECT t.id
           FROM v_topf_lieferung t
        ), hagel AS MATERIALIZED (
         SELECT r.charge_nr,
            r.eingang_netto_kg,
            r.erster_eingang
           FROM v_charge_rueckgrat r
             JOIN charge c ON c.nr = r.charge_nr
          WHERE c.hagel_anteil > 0::numeric AND r.eingang_netto_kg > 0::numeric
        ), leer AS MATERIALIZED (
         SELECT c.nr AS charge_nr,
            c.leer_am
           FROM charge c
          WHERE c.leer_am IS NOT NULL
        )
 SELECT l.id,
    l.datum,
    l.buch,
    l.masse_kg,
    c.charge_nr,
    c.anteil,
    l.charge_nr IS NULL AS ohne_charge
   FROM ( SELECT heute() AS heute) d
     CROSS JOIN v_lieferung_masse l
     CROSS JOIN LATERAL ( SELECT l.charge_nr,
            1::numeric AS anteil
          WHERE l.charge_nr IS NOT NULL AND NOT (EXISTS ( SELECT 1
                   FROM topf t
                  WHERE t.id = l.id))
        UNION ALL
         SELECT x.charge_nr,
            x.eingang_netto_kg / sum(x.eingang_netto_kg) OVER ()
           FROM ( SELECT r.charge_nr,
                    r.eingang_netto_kg,
                    g.rang,
                    min(g.rang) OVER () AS bester
                   FROM v_charge_rueckgrat r
                     CROSS JOIN LATERAL ( SELECT
                                CASE
                                    WHEN (EXISTS ( SELECT 1
                                       FROM hagel h
                                      WHERE h.charge_nr = r.charge_nr)) THEN 2
                                    ELSE 0
                                END +
                                CASE
                                    WHEN (EXISTS ( SELECT 1
                                       FROM leer le
                                      WHERE le.charge_nr = r.charge_nr AND le.leer_am < l.datum)) THEN 1
                                    ELSE 0
                                END AS rang) g
                  WHERE l.charge_nr IS NULL AND NOT (EXISTS ( SELECT 1
                           FROM topf t
                          WHERE t.id = l.id)) AND r.sorte = l.sorte AND r.eingang_netto_kg > 0::numeric) x
          WHERE x.rang = x.bester
        UNION ALL
         SELECT h.charge_nr,
            h.eingang_netto_kg / sum(h.eingang_netto_kg) OVER ()
           FROM hagel h
          WHERE (EXISTS ( SELECT 1
                   FROM topf t
                  WHERE t.id = l.id)) AND (h.erster_eingang <= l.datum OR NOT (EXISTS ( SELECT 1
                   FROM hagel h2
                  WHERE h2.erster_eingang <= l.datum)))) c
  WHERE l.masse_kg IS NOT NULL AND l.masse_kg > 0::numeric AND (l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text, 'verlust'::text])) AND l.datum <= d.heute
UNION ALL
 SELECT - cv.charge_nr AS id,
    COALESCE(( SELECT NULLIF(einstellung.wert #>> '{}'::text[], ''::text)::date AS "nullif"
           FROM einstellung
          WHERE einstellung.schluessel = 'erfassungsbeginn'::text), r.letzter_eingang) AS datum,
    'verkauf'::text AS buch,
    cv.ausgang_vor_app_kg AS masse_kg,
    cv.charge_nr,
    1 AS anteil,
    false AS ohne_charge
   FROM charge_vorlauf cv
     JOIN v_charge_rueckgrat r ON r.charge_nr = cv.charge_nr
  WHERE cv.ausgang_vor_app_kg > 0::numeric;
comment on view v_lieferung_charge is 'Jede Lieferung bis heute() (Verkauf, Marge, Verlust) und die Chargen, von denen sie genommen hat: mit Chargennummer ganz (anteil 1); ohne nach dem Eingang auf die Chargen ihrer Sorte verteilt (ohne_charge) — seit 0138 nicht auf eine Hagel-Charge, solange die Sorte eine Charge ohne Hagel hat (Hagelware geht nur über den Topf); seit 0133 was aus dem Ünique-Topf geht (v_topf_lieferung) nach dem Eingang auf die Hagel-Chargen, die bis zum Liefertag da waren. Der Ausgang vor der App am Erfassungsbeginn als eine Lieferung mit id = −Charge. Die Regel gibt es nur hier: v_lieferung_charge_tag, v_lieferung_kohorte, die Kaskade und v_lieferung_gruppe rechnen darauf (0114). Seit 0143 auch nicht auf eine Charge, die vor dem Liefertag am Lager leer bestätigt wurde, solange die Sorte eine andere hat: die Chargen der Sorte haben einen Rang (Hagel 2, leer vor dem Liefertag 1), und der Lieferschein geht nach dem Eingang auf die mit dem kleinsten — er geht nie verloren.';
grant select on v_lieferung_charge to authenticated;

-- ---------- 3. Verschenkt ist nie weniger als nichts ----------
create or replace view v_verschenkt_charge with (security_invoker = true) as
 WITH gewogen_charge AS (
         SELECT u.charge_nr,
            u.soll_kg_pro_kiste AS soll,
            avg(u.zuviel_je_kiste) AS zuviel
           FROM erg_ueberfuellung u
          WHERE u.gruppe = 'charge'::text AND u.kistensystem = 'kiste_ab'::text AND u.zuviel_je_kiste IS NOT NULL
          GROUP BY u.charge_nr, u.soll_kg_pro_kiste
        ), gewogen_sorte AS (
         SELECT u.sorte,
            u.soll_kg_pro_kiste AS soll,
            avg(u.zuviel_je_kiste) AS zuviel
           FROM erg_ueberfuellung u
          WHERE u.gruppe = 'sorte'::text AND u.kistensystem = 'kiste_ab'::text AND u.zuviel_je_kiste IS NOT NULL
          GROUP BY u.sorte, u.soll_kg_pro_kiste
        ), verkauft AS (
         SELECT u.charge_nr,
            u.kistensystem,
            u.soll_kg_pro_kiste AS soll,
            sum(u.kg_verkauft) AS kg,
            sum(u.kisten_verkauft) AS kisten
           FROM erg_ueberfuellung u
          WHERE u.gruppe = 'charge'::text AND u.charge_nr IS NOT NULL AND u.kg_verkauft > 0::numeric
          GROUP BY u.charge_nr, u.kistensystem, u.soll_kg_pro_kiste
        ), je AS (
         SELECT v.charge_nr,
            v.kistensystem,
            v.kg,
            v.kisten,
                CASE
                    WHEN v.kistensystem = 'kiste_ab'::text AND v.kisten IS NOT NULL THEN COALESCE(gc.zuviel, gs.zuviel)
                    ELSE NULL::numeric
                END AS zuviel,
                CASE
                    WHEN v.kistensystem <> 'kiste_ab'::text OR v.kisten IS NULL THEN NULL::text
                    WHEN gc.zuviel IS NOT NULL THEN 'charge'::text
                    WHEN gs.zuviel IS NOT NULL THEN 'sorte'::text
                    ELSE NULL::text
                END AS quelle
           FROM verkauft v
             JOIN charge c ON c.nr = v.charge_nr
             LEFT JOIN gewogen_charge gc ON gc.charge_nr = v.charge_nr AND NOT gc.soll IS DISTINCT FROM v.soll
             LEFT JOIN gewogen_sorte gs ON gs.sorte = c.sorte AND NOT gs.soll IS DISTINCT FROM v.soll
        )
 SELECT charge_nr,
    zahl(sum(kg), 2, '1000000000000'::bigint::numeric)::numeric(14,2) AS verkauft_kg,
    zahl(COALESCE(sum(kg) FILTER (WHERE kistensystem = 'kiste_ab'::text), 0::numeric), 2, '1000000000000'::bigint::numeric)::numeric(14,2) AS kiste_ab_kg,
    zahl(GREATEST(COALESCE(sum(kisten * zuviel) FILTER (WHERE zuviel IS NOT NULL), 0::numeric), 0::numeric), 2, '1000000000000'::bigint::numeric)::numeric(14,2) AS verschenkt_kg,
    zahl(COALESCE(sum(kg) FILTER (WHERE kistensystem = 'kiste_ab'::text AND zuviel IS NULL), 0::numeric), 2, '1000000000000'::bigint::numeric)::numeric(14,2) AS ohne_wiegung_kg,
    zahl(COALESCE(sum(kg) FILTER (WHERE kistensystem = 'unbekannt'::text), 0::numeric), 2, '1000000000000'::bigint::numeric)::numeric(14,2) AS system_offen_kg,
    zahl(GREATEST(COALESCE(sum(kisten * zuviel) FILTER (WHERE zuviel IS NOT NULL), 0::numeric), 0::numeric) / NULLIF(sum(kg), 0::numeric), 6, 10::numeric)::numeric(10,6) AS anteil,
    string_agg(DISTINCT quelle, ', '::text ORDER BY j.quelle) AS quelle
   FROM je j
  GROUP BY charge_nr;
comment on view v_verschenkt_charge is 'Die verschenkte Marge je Charge (0136): was in den Kisten über dem Sollgewicht mitging, ohne in Perigon zu stehen — verkaufte Kisten „ab x kg" (erg_ueberfuellung) × zu viel je Kiste, gewogen bei der Charge (über alle Zeilen der Charge), sonst bei ihrer Sorte. Stück-Kisten haben kein Sollgewicht (0). ohne_wiegung_kg: Kisten ab x kg ohne Wägung bei Charge und Sorte; system_offen_kg: Lieferungen mit unbekanntem Kistensystem — beides nicht gerechnet, nicht null. anteil = verschenkt ÷ verkauft (zur Auskunft); die Kaskade verteilt verschenkt_kg auf die Lieferungen der Charge nach kg und zählt es als hinausgegangen. Seit 0143 nie unter 0: wiegen die Kisten einer Charge im Schnitt unter dem Sollgewicht, ist nichts verschenkt — so rechnete die Kaskade schon, die Sicht zeigte ein Minus.';
grant select on v_verschenkt_charge to authenticated;

-- ---------- Stand ----------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 143 $$;
