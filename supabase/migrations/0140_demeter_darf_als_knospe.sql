-- 0140 — Demeter darf als Knospe verkauft werden (Runde BK)
--
-- Der Betrieb am 9. November, zum Fall „Demeter und Knospe in einer
-- Position": „Demeter darf als Knospe verkauft werden — das sollte kein
-- Problem sein."
--
-- Seit 0131 meldete der Perigon-Reiter jede Position, deren Chargen
-- verschiedene Lieferlabels tragen, gleich in welche Richtung. Im Betrieb
-- waren das 25 Positionen; 24 davon sind Knospe-Artikel (Preisgruppe K) mit
-- etwas Demeter-Ware darin — erlaubt. Ein Problem ist nur die andere
-- Richtung: Knospe-Ware unter einem Artikel, der als Demeter benannt oder
-- verrechnet ist (Position 134343: „Bio-Kürbis Butterkin Demeter", 1138 kg aus
-- 1624 mit Lieferlabel Knospe).
--
-- Jetzt: label_gemischt nur, wenn die Position Demeter- und Knospe-Ware hat
-- UND Demeter im Artikelnamen oder in der Preisgruppe steht. Der Satz sagt,
-- wo Demeter steht, und: „Demeter darf als Knospe verkauft werden, Knospe
-- nicht als Demeter." Im Betrieb bleibt 134343.
--
-- Was bewusst nicht gemacht wurde:
-- - demeter_knospe (eine Chargenzeile zum Demeter-Preis mit Lieferlabel
--   Knospe) bleibt, wie er ist: er sagt dasselbe je Zeile und gilt auch, wenn
--   die Position nur Knospe-Ware hat.
-- - „Artikelname gegen Preisgruppe" (label_name) bleibt: Name und Preisgruppe
--   widersprechen sich auch dann, wenn die Ware erlaubt ist; und er steht wie
--   bisher nicht zusätzlich da, wenn die Chargen gemischt sind.
-- - Am Lager nach Artikel deckt Demeter-Ware keinen Knospe-Bedarf: das ist
--   eine Frage an den Betrieb, nicht Teil dieses Schritts.

create or replace view v_perigon_befund with (security_invoker = true) as
 WITH zeile AS (
         SELECT z.id,
            z.quelle,
            z.pos_id,
            z.lauf_nr,
            z.datum,
            z.kunde,
            z.artikel_id,
            z.artikel,
            z.einheit,
            z.menge,
            z.gewicht_je_artikel,
            z.batch_menge,
            z.kg_position,
            z.kg_charge,
            z.preisgruppe,
            z.liefer_label,
            z.produzent,
            z.ts,
            z.auftragsnr,
                CASE
                    WHEN upper(COALESCE(z.liefer_label, ''::text)) ~~ 'D%'::text THEN 'D'::text
                    WHEN upper(COALESCE(z.liefer_label, ''::text)) ~ '^(K|CH-K)'::text THEN 'K'::text
                    ELSE NULL::text
                END AS label_z,
            NULLIF(btrim(z.charge_extern), ''::text) AS nummer,
            regexp_replace(COALESCE(z.charge_extern, ''::text), '\D'::text, ''::text, 'g'::text) AS ziffern
           FROM ausgang_zeile z
        ), lief AS (
         SELECT i.quelle,
            split_part(i.extern_id, ':'::text, 2)::bigint AS pos_id,
            sum(l.kg) AS kg,
            sum(l.kg) FILTER (WHERE l.charge_nr IS NULL) AS kg_ohne,
            count(DISTINCT l.charge_nr)::integer AS n_chargen,
            min(l.charge_nr) AS charge_nr,
            min(l.sorte) AS sorte
           FROM lieferung_import i
             JOIN lieferung l ON l.id = i.lieferung_id
          WHERE split_part(i.extern_id, ':'::text, 2) ~ '^\d+$'::text AND i.extern_id !~~ '%:rueckgabe'::text
          GROUP BY i.quelle, (split_part(i.extern_id, ':'::text, 2)::bigint)
        ), mixteil AS (
         SELECT i.quelle,
            split_part(i.extern_id, ':'::text, 2)::bigint AS pos_id,
            "substring"(i.extern_id, '^[^:]*:[0-9]+:(.*):mix:[^:]*$'::text) AS basis,
            string_agg(format('%s kg %s%s'::text, kg_wort(l.kg), COALESCE(l.sorte, 'ohne Sorte'::text),
                CASE
                    WHEN l.charge_nr IS NULL THEN ' (ohne Charge)'::text
                    ELSE ' auf Charge '::text || l.charge_nr
                END), ', '::text ORDER BY l.sorte) AS text,
            sum(l.kg) AS kg
           FROM lieferung_import i
             JOIN lieferung l ON l.id = i.lieferung_id
          WHERE i.extern_id ~~ '%:mix:%'::text AND split_part(i.extern_id, ':'::text, 2) ~ '^\d+$'::text
          GROUP BY i.quelle, (split_part(i.extern_id, ':'::text, 2)::bigint), ("substring"(i.extern_id, '^[^:]*:[0-9]+:(.*):mix:[^:]*$'::text))
        ), doppelt AS (
         SELECT d.quelle,
            d.pos_id,
            string_agg(format('Charge %s %s'::text, d.nummer,
                CASE d.n
                    WHEN 2 THEN 'zweimal'::text
                    WHEN 3 THEN 'dreimal'::text
                    ELSE d.n || '-mal'::text
                END), ', '::text ORDER BY d.nummer) AS text
           FROM ( SELECT zeile.quelle,
                    zeile.pos_id,
                    zeile.nummer,
                    count(*)::integer AS n
                   FROM zeile
                  WHERE zeile.nummer IS NOT NULL
                  GROUP BY zeile.quelle, zeile.pos_id, zeile.nummer
                 HAVING count(*) > 1 AND count(DISTINCT zeile.batch_menge) = 1) d
          GROUP BY d.quelle, d.pos_id
        ), pos AS (
         SELECT z.quelle,
            z.pos_id,
            min(z.datum) AS datum,
            min(z.kunde) AS kunde,
            min(z.artikel_id) AS artikel_id,
            min(z.artikel) AS artikel,
            min(z.einheit) AS einheit,
            max(z.menge) AS menge,
            max(z.gewicht_je_artikel) AS gewicht_je_artikel,
            max(z.kg_position) AS kg_position,
            min(z.preisgruppe) AS preisgruppe,
            min(z.liefer_label) AS liefer_label,
            min(z.ts) AS eingelesen,
            min(z.auftragsnr) AS auftragsnr,
            count(DISTINCT z.label_z) FILTER (WHERE z.nummer IS NOT NULL AND z.kg_charge > 0::numeric)::integer AS n_labels,
            string_agg(format('%s kg aus %s (%s)'::text, kg_wort(z.kg_charge), z.nummer,
                CASE z.label_z
                    WHEN 'D'::text THEN 'Demeter'::text
                    WHEN 'K'::text THEN 'Knospe'::text
                    ELSE COALESCE(z.liefer_label, 'ohne Label'::text)
                END), ', '::text ORDER BY z.kg_charge DESC, z.nummer) FILTER (WHERE z.nummer IS NOT NULL AND z.kg_charge > 0::numeric) AS labels_text,
            count(*)::integer AS n_zeilen,
            count(z.nummer)::integer AS n_nummer,
            count(*) FILTER (WHERE z.nummer IS NOT NULL AND z.kg_charge > 0::numeric)::integer AS n_menge,
            COALESCE(sum(z.kg_charge) FILTER (WHERE z.nummer IS NOT NULL AND z.kg_charge > 0::numeric), 0::numeric) AS kg_zugeteilt,
            string_agg(DISTINCT z.nummer, ', '::text ORDER BY z.nummer) AS nummern,
            string_agg(DISTINCT z.nummer, ', '::text ORDER BY z.nummer) FILTER (WHERE COALESCE(z.kg_charge, 0::numeric) <= 0::numeric) AS nummern_ohne_menge
           FROM zeile z
          GROUP BY z.quelle, z.pos_id
        ), p AS (
         SELECT pos.quelle,
            pos.pos_id,
            pos.datum,
            pos.kunde,
            pos.artikel_id,
            pos.artikel,
            pos.einheit,
            pos.menge,
            pos.gewicht_je_artikel,
            pos.kg_position,
            pos.preisgruppe,
            pos.liefer_label,
            pos.eingelesen,
            pos.auftragsnr,
            pos.n_labels,
            pos.labels_text,
            pos.n_zeilen,
            pos.n_nummer,
            pos.n_menge,
            pos.kg_zugeteilt,
            pos.nummern,
            pos.nummern_ohne_menge,
            f_1.kg AS kg_rechnung,
            f_1.kg_ohne,
                CASE
                    WHEN f_1.n_chargen = 1 THEN f_1.charge_nr
                    ELSE NULL::integer
                END AS charge_nr,
            COALESCE(f_1.sorte, aa.sorte) AS sorte,
            d.text AS doppelt,
                CASE
                    WHEN pos.nummern ~~ '%,%'::text THEN 'die Chargen '::text || pos.nummern
                    ELSE 'die Charge '::text || pos.nummern
                END AS chargen_text,
                CASE
                    WHEN lower(pos.artikel) ~ '(demeter|\mdem\M)'::text THEN 'D'::text
                    WHEN lower(pos.artikel) ~ 'knospe'::text THEN 'K'::text
                    ELSE NULL::text
                END AS label_name,
                CASE
                    WHEN upper(COALESCE(pos.preisgruppe, ''::text)) ~~ 'D%'::text THEN 'D'::text
                    WHEN upper(COALESCE(pos.preisgruppe, ''::text)) ~ '^(K|CH-K)'::text THEN 'K'::text
                    ELSE NULL::text
                END AS label_preis
           FROM pos
             LEFT JOIN lief f_1 ON f_1.quelle = pos.quelle AND f_1.pos_id = pos.pos_id
             LEFT JOIN ausgang_artikel aa ON aa.artikel_id = pos.artikel_id AND aa.artikel = pos.artikel
             LEFT JOIN doppelt d ON d.quelle = pos.quelle AND d.pos_id = pos.pos_id
        ), r AS (
         SELECT z.id,
            z.quelle,
            z.pos_id,
            z.lauf_nr,
            z.datum,
            z.kunde,
            z.artikel_id,
            z.artikel,
            z.einheit,
            z.menge,
            z.gewicht_je_artikel,
            z.batch_menge,
            z.kg_position,
            z.kg_charge,
            z.preisgruppe,
            z.liefer_label,
            z.produzent,
            z.ts,
            z.auftragsnr,
            z.label_z,
            z.nummer,
            z.ziffern,
            l.id AS lieferung_id,
            l.charge_nr,
            l.kg AS kg_lieferung,
            c.sorte,
            sk.artikelgruppe AS gruppe_charge,
            e.gruppe AS gruppe_artikel,
            e.label AS label_verkauft,
                CASE
                    WHEN upper(COALESCE(z.liefer_label, ''::text)) ~~ 'D%'::text THEN 'D'::text
                    WHEN upper(COALESCE(z.liefer_label, ''::text)) ~ '^(K|CH-K)'::text THEN 'K'::text
                    ELSE NULL::text
                END AS label_geliefert,
            ( SELECT x.nr
                   FROM charge x
                  WHERE z.ziffern <> ''::text AND x.nr::text = z.ziffern) AS eigene,
            ( SELECT array_agg(x.nr ORDER BY x.nr) AS array_agg
                   FROM charge x
                  WHERE z.ziffern <> ''::text AND x.perigon_nr::text = z.ziffern) AS an_perigon,
            ( SELECT min(pl.eingangsdatum) AS min
                   FROM palette pl
                  WHERE pl.charge_nr = l.charge_nr) AS erster_eingang
           FROM zeile z
             JOIN lieferung_import i ON i.zeile_id = z.id AND i.extern_id !~~ '%:rest'::text AND i.extern_id !~~ '%:rueckgabe'::text AND i.extern_id !~~ '%:mix:%'::text
             JOIN lieferung l ON l.id = i.lieferung_id
             LEFT JOIN charge c ON c.nr = l.charge_nr
             LEFT JOIN sorte_kaliber sk ON sk.sorte = c.sorte
             CROSS JOIN LATERAL ( SELECT artikel_einordnen.gruppe,
                    artikel_einordnen.groesse,
                    artikel_einordnen.label
                   FROM artikel_einordnen(z.artikel, z.preisgruppe) artikel_einordnen(gruppe, groesse, label)
                 LIMIT 1) e
          WHERE z.nummer IS NOT NULL AND COALESCE(z.kg_charge, 0::numeric) > 0::numeric
        ), fall AS (
         SELECT 'menge_null'::text AS art,
            p_1.quelle,
            p_1.pos_id,
            NULL::text AS nummer,
            NULL::integer AS lauf_nr,
            p_1.charge_nr,
            p_1.sorte,
                CASE
                    WHEN p_1.kg_position > 0::numeric THEN p_1.kg_position
                    ELSE NULL::numeric
                END AS kg,
                CASE
                    WHEN p_1.kg_position > 0::numeric THEN format('Perigon nennt %s, teilt aber keine Menge zu: Spalte S („AufPosBatchQuantity Charge") ist 0. Die Position hat %s kg (Spalte Q × AE) — sie bleibt ganz ohne Charge.'::text, p_1.chargen_text, kg_wort(p_1.kg_position))
                    ELSE format('Perigon nennt %s, aber die Position hat keine Menge — Spalte Q und Spalte S sind 0. Sie zählt nirgends; ging Ware hinaus, fehlt sie im Warenausgang.'::text, p_1.chargen_text)
                END AS satz,
            'In Perigon bei dieser Position die Menge (Spalte Q) und die Menge je Charge (Spalte S) eintragen, dann die Datei unter Betrieb → Warenausgang neu einlesen.'::text AS tun,
            'perigon'::text AS wo
           FROM p p_1
          WHERE p_1.n_nummer > 0 AND p_1.n_menge = 0 AND (p_1.kg_position > 0::numeric OR COALESCE(p_1.kg_position, 0::numeric) = 0::numeric AND COALESCE(p_1.menge, 0::numeric) = 0::numeric)
        UNION ALL
         SELECT 'zu_viel'::text,
            p_1.quelle,
            p_1.pos_id,
            NULL::text,
            NULL::integer,
            p_1.charge_nr,
            p_1.sorte,
            p_1.kg_zugeteilt - p_1.kg_position,
            format('Die Chargenzeilen geben zusammen %s kg (Spalte S × AE), die Position nur %s kg (Spalte Q × AE) — %s kg zu viel.%s Die App zählt höchstens die Position: %s.'::text, kg_wort(p_1.kg_zugeteilt), kg_wort(p_1.kg_position), kg_wort(p_1.kg_zugeteilt - p_1.kg_position),
                CASE
                    WHEN p_1.doppelt IS NOT NULL THEN format(' Dieselbe Zeile steht mehrfach da (%s).'::text, p_1.doppelt)
                    ELSE ''::text
                END,
                CASE
                    WHEN p_1.nummern ~~ '%,%'::text THEN 'die Chargen bekommen ihre Menge in der Folge der Zeilen, bis die Position voll ist — wie viel welche bekam, sagt die Datei nicht sicher'::text
                    ELSE format('%s bekommt die %s kg der Position'::text, p_1.chargen_text, kg_wort(p_1.kg_position))
                END) AS format,
            'In Perigon die Menge je Charge (Spalte S) berichtigen — zusammen so viel wie die Position —, eine doppelte Zeile entfernen, dann neu einlesen.'::text,
            'perigon'::text
           FROM p p_1
          WHERE p_1.kg_position > 0::numeric AND p_1.kg_zugeteilt > (p_1.kg_position + 0.5)
        UNION ALL
         SELECT 'rest'::text,
            p_1.quelle,
            p_1.pos_id,
            NULL::text,
            NULL::integer,
            p_1.charge_nr,
            p_1.sorte,
            p_1.kg_position - p_1.kg_zugeteilt,
            format('Perigon teilt %s nur %s von %s kg zu (Spalte S); %s kg bleiben ohne Charge.%s'::text, p_1.chargen_text, kg_wort(p_1.kg_zugeteilt), kg_wort(p_1.kg_position), kg_wort(p_1.kg_position - p_1.kg_zugeteilt),
                CASE
                    WHEN p_1.nummern_ohne_menge IS NOT NULL THEN format(' Ohne Menge genannt: %s.'::text, p_1.nummern_ohne_menge)
                    ELSE ''::text
                END) AS format,
            'In Perigon die Menge je Charge (Spalte S) nachtragen, dann neu einlesen. Bis dahin verteilt die App den Rest auf alle Chargen der Sorte.'::text,
            'perigon'::text
           FROM p p_1
          WHERE p_1.n_menge > 0 AND (p_1.kg_position - p_1.kg_zugeteilt) > 0.5
        UNION ALL
         SELECT 'keine_nummer'::text,
            p_1.quelle,
            p_1.pos_id,
            NULL::text,
            NULL::integer,
            NULL::integer AS int4,
            p_1.sorte,
            p_1.kg_position,
            format('In Perigon steht bei dieser Position keine Chargennummer (Spalte W „AuftragsChargeManuell" ist leer) — %s kg ohne Charge.'::text, kg_wort(p_1.kg_position)) AS format,
            'In Perigon die Charge (Spalte W) und die Menge je Charge (Spalte S) eintragen, dann neu einlesen. Bis dahin verteilt die App die Menge auf alle Chargen der Sorte.'::text,
            'perigon'::text
           FROM p p_1
          WHERE p_1.n_nummer = 0 AND p_1.kg_position > 0::numeric
        UNION ALL
         SELECT 'ohne_gewicht'::text,
            p_1.quelle,
            p_1.pos_id,
            NULL::text,
            NULL::integer,
            p_1.charge_nr,
            p_1.sorte,
            NULL::numeric AS "numeric",
            format('%s %s ohne Gewicht je Artikel (Spalte AE ist leer oder 0) — die Masse ist unbekannt; die App zählt die Position nicht, statt 0 kg zu raten.'::text, TRIM(BOTH FROM to_char(p_1.menge, 'FM999999990.###'::text)), COALESCE(p_1.einheit, 'Stück'::text)) AS format,
            'In Perigon das Gewicht je Artikel (Spalte AE) eintragen, dann neu einlesen.'::text,
            'perigon'::text
           FROM p p_1
          WHERE p_1.kg_position IS NULL AND COALESCE(p_1.menge, 0::numeric) <> 0::numeric
        UNION ALL
         SELECT 'ruecknahme'::text,
            p_1.quelle,
            p_1.pos_id,
            NULL::text,
            NULL::integer,
            p_1.charge_nr,
            p_1.sorte,
            - p_1.kg_position,
            format('Negative Menge (%s kg): eine Rücknahme. Die App bucht sie als Rücknahme, nicht als Verkauf.'::text, kg_wort(p_1.kg_position)) AS format,
            'Nichts in der App. Prüfen, ob die Ware wirklich zurückkam.'::text,
            'nichts'::text
           FROM p p_1
          WHERE p_1.kg_position < 0::numeric
        UNION ALL
         SELECT 'masse_abweichung'::text,
            p_1.quelle,
            p_1.pos_id,
            NULL::text,
            NULL::integer,
            p_1.charge_nr,
            p_1.sorte,
            COALESCE(p_1.kg_rechnung, 0::numeric) - p_1.kg_position,
                CASE
                    WHEN p_1.kg_rechnung IS NULL THEN format('Die Position steht in der Datei (%s kg), aber in der Rechnung gibt es keine Lieferung dazu.'::text, kg_wort(p_1.kg_position))
                    ELSE format('In der Rechnung stehen für diese Position %s kg, die Datei ergibt %s kg — %s kg %s.'::text, kg_wort(p_1.kg_rechnung), kg_wort(p_1.kg_position), kg_wort(abs(p_1.kg_rechnung - p_1.kg_position)),
                    CASE
                        WHEN p_1.kg_rechnung > p_1.kg_position THEN 'zu viel'::text
                        ELSE 'zu wenig'::text
                    END)
                END AS format,
            'Die Datei unter Betrieb → Warenausgang neu einlesen: die App legt an, was fehlt, und entfernt, was die Datei nicht mehr ergibt. Eine von Hand geänderte Lieferung bekommt dabei wieder die Masse der Datei.'::text,
            'einlesen'::text
           FROM p p_1
          WHERE p_1.kg_position > 0::numeric AND abs(COALESCE(p_1.kg_rechnung, 0::numeric) - p_1.kg_position) > 0.05
        UNION ALL
         SELECT 'label_name'::text,
            p_1.quelle,
            p_1.pos_id,
            NULL::text,
            NULL::integer,
            p_1.charge_nr,
            p_1.sorte,
            p_1.kg_position,
            format('Der Artikel heisst „%s" (%s), verkauft wurde er in der Preisgruppe %s (%s). Die App nimmt die Preisgruppe.'::text, p_1.artikel,
                CASE p_1.label_name
                    WHEN 'D'::text THEN 'Demeter'::text
                    ELSE 'Knospe'::text
                END, p_1.preisgruppe,
                CASE p_1.label_preis
                    WHEN 'D'::text THEN 'Demeter'::text
                    ELSE 'Knospe'::text
                END) AS format,
            'In Perigon Artikel oder Preisgruppe angleichen — was stimmt, weiss, wer den Auftrag erfasst hat.'::text,
            'perigon'::text
           FROM p p_1
          WHERE p_1.label_name IS NOT NULL AND p_1.label_preis IS NOT NULL AND p_1.label_name <> p_1.label_preis AND COALESCE(p_1.n_labels, 0) <= 1
        UNION ALL
         SELECT 'label_gemischt'::text,
            p_1.quelle,
            p_1.pos_id,
            NULL::text,
            NULL::integer,
            p_1.charge_nr,
            p_1.sorte,
            p_1.kg_position,
            format('Auftrag %s vom %s: unter dem Artikel „%s" (Preisgruppe %s) — %s — ging auch Knospe-Ware hinaus: %s. Demeter darf als Knospe verkauft werden, Knospe nicht als Demeter.'::text, COALESCE(NULLIF(p_1.auftragsnr, ''::text), '?'::text), to_char(p_1.datum::timestamp with time zone, 'DD.MM.YYYY'::text), p_1.artikel, COALESCE(p_1.preisgruppe, '—'::text),
                CASE
                    WHEN p_1.label_name = 'D'::text AND p_1.label_preis = 'D'::text THEN 'Demeter im Namen und in der Preisgruppe'::text
                    WHEN p_1.label_name = 'D'::text THEN 'Demeter im Namen'::text
                    ELSE 'Demeter in der Preisgruppe'::text
                END, p_1.labels_text) AS format,
            'Mit der Person klären, die den Auftrag in Perigon erfasst hat: ging Knospe-Ware als Demeter hinaus? Dann in Perigon den Artikel aufteilen (den Knospe-Teil als Knospe) oder die Charge (Spalte W) berichtigen, dann neu einlesen.'::text,
            'perigon'::text
           FROM p p_1
          WHERE p_1.n_labels > 1 AND (p_1.label_name = 'D'::text OR p_1.label_preis = 'D'::text)
        UNION ALL
         SELECT 'kg_gewicht'::text,
            p_1.quelle,
            p_1.pos_id,
            NULL::text,
            NULL::integer,
            p_1.charge_nr,
            p_1.sorte,
            p_1.kg_position,
            format('Perigon führt „%s" in kg, aber mit Gewicht je Artikel %s (Spalte AE). Die Menge (Spalte Q, %s kg) ist schon das Gewicht; Perigon rechnet das Totalgewicht trotzdem × %s (%s kg). Die App nimmt die Menge.'::text, p_1.artikel, TRIM(BOTH FROM to_char(p_1.gewicht_je_artikel, 'FM999990.###'::text)), kg_wort(p_1.menge), TRIM(BOTH FROM to_char(p_1.gewicht_je_artikel, 'FM999990.###'::text)), kg_wort(p_1.menge * p_1.gewicht_je_artikel)) AS format,
            'Im Perigon-Artikelstamm beim Artikel das Gewicht je Artikel (Spalte AE) auf 1 setzen. In der App ist nichts zu tun — sie zählt schon die Menge.'::text,
            'perigon'::text
           FROM p p_1
          WHERE lower(btrim(COALESCE(p_1.einheit, ''::text))) ~~ 'kg%'::text AND p_1.gewicht_je_artikel IS NOT NULL AND (p_1.gewicht_je_artikel <> ALL (ARRAY[0::numeric, 1::numeric]))
        UNION ALL
         SELECT 'unique_ohne_hagel'::text,
            r.quelle,
            r.pos_id,
            r.nummer,
            r.lauf_nr,
            r.charge_nr,
            r.sorte,
            r.kg_lieferung,
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM charge h
                      WHERE h.hagel_anteil > 0::numeric)) THEN format('Ünique unter Charge %s (%s), bei der kein Hagel eingetragen ist. Ünique kommt aus dem Ünique-Topf: die App zieht die %s kg vom Topf ab, nicht von Charge %s.'::text, r.charge_nr, COALESCE(r.sorte, 'Sorte unbekannt'::text), kg_wort(r.kg_lieferung), r.charge_nr)
                    ELSE format('Ünique unter Charge %s (%s), aber bei keiner Charge ist Hagel eingetragen — ohne Hagel-Charge gibt es keinen Ünique-Topf, und die App zieht die %s kg von Charge %s ab.'::text, r.charge_nr, COALESCE(r.sorte, 'Sorte unbekannt'::text), kg_wort(r.kg_lieferung), r.charge_nr)
                END AS format,
            'Steht in Perigon (Spalte W) die falsche Charge, dort berichtigen; fehlt bei der Charge der Hagel, ihn unter Chargen eintragen.'::text,
            'perigon'::text
           FROM r
          WHERE ist_unique_artikel(r.artikel) AND r.charge_nr IS NOT NULL AND NOT (EXISTS ( SELECT 1
                   FROM charge h
                  WHERE h.nr = r.charge_nr AND h.hagel_anteil > 0::numeric))
        UNION ALL
         SELECT
                CASE
                    WHEN r.eigene IS NOT NULL OR cardinality(r.an_perigon) = 1 THEN 'nachholen'::text
                    WHEN cardinality(r.an_perigon) > 1 THEN 'mehrdeutig'::text
                    ELSE 'unbekannt'::text
                END AS "case",
            r.quelle,
            r.pos_id,
            r.nummer,
            r.lauf_nr,
            NULL::integer AS int4,
            NULL::text AS text,
            r.kg_lieferung,
                CASE
                    WHEN r.eigene IS NOT NULL OR cardinality(r.an_perigon) = 1 THEN format('Perigon nennt %s; die Nummer steht inzwischen an Charge %s — beim Einlesen kannte die App sie noch nicht.'::text, r.nummer, COALESCE(r.eigene, r.an_perigon[1]))
                    WHEN cardinality(r.an_perigon) > 1 THEN format('Perigon nennt %s; diese Perigon-Nummer steht an mehreren Chargen (%s), und der Artikel sagt nicht, an welcher.'::text, r.nummer, array_to_string(r.an_perigon, ', '::text))
                    ELSE format('Perigon nennt %s — diese Nummer steht an keiner Charge der App.'::text, r.nummer)
                END AS format,
                CASE
                    WHEN r.eigene IS NOT NULL OR cardinality(r.an_perigon) = 1 THEN 'Nichts — beim nächsten Rechnen („Neu rechnen" oben) bekommt der Lieferschein die Charge von selbst.'::text
                    WHEN cardinality(r.an_perigon) > 1 THEN 'Unter Betrieb → Stammdaten → Chargen die Nummer nur bei der richtigen Charge lassen; beim nächsten Rechnen bekommt der Lieferschein sie.'::text
                    ELSE 'Unter Betrieb → Stammdaten → Chargen bei der richtigen Charge als Perigon-Nr. eintragen; beim nächsten Rechnen bekommt der Lieferschein sie von selbst. Ist die Nummer ein Tippfehler, in Perigon berichtigen.'::text
                END AS "case",
                CASE
                    WHEN r.eigene IS NOT NULL OR cardinality(r.an_perigon) = 1 THEN 'nichts'::text
                    ELSE 'stammdaten'::text
                END AS "case"
           FROM r
          WHERE r.charge_nr IS NULL
        UNION ALL
         SELECT 'artikel_sorte'::text,
            r.quelle,
            r.pos_id,
            r.nummer,
            r.lauf_nr,
            r.charge_nr,
            r.sorte,
            r.kg_lieferung,
            format('Verkauft als %s („%s"), aber die Charge %s ist %s — und %s geht als %s. Entweder steht der falsche Artikel oder die falsche Charge auf dem Lieferschein.'::text, r.gruppe_artikel, r.artikel, r.charge_nr, r.sorte, r.sorte, r.gruppe_charge) AS format,
            'Den Lieferschein ansehen: ist der Artikel falsch, in Perigon den Artikel berichtigen; ist die Charge falsch, die Charge (Spalte W) — dann neu einlesen.'::text,
            'perigon'::text
           FROM r
          WHERE r.charge_nr IS NOT NULL AND r.gruppe_artikel IS NOT NULL AND r.gruppe_charge IS NOT NULL AND (r.gruppe_artikel <> ALL (ARRAY['Mix'::text, 'andere'::text, 'Ünique'::text])) AND r.gruppe_artikel <> r.gruppe_charge
        UNION ALL
         SELECT 'demeter_knospe'::text,
            r.quelle,
            r.pos_id,
            r.nummer,
            r.lauf_nr,
            r.charge_nr,
            r.sorte,
            r.kg_lieferung,
            format('Verkauft zum Demeter-Preis (Preisgruppe %s), aber die Ware der Charge %s trägt das Lieferlabel %s — das ist Knospe.'::text, r.preisgruppe, r.charge_nr, r.liefer_label) AS format,
            'In Perigon Preisgruppe (Spalte K) und Lieferlabel (Spalte Z) prüfen: wurde Knospe als Demeter verrechnet, oder stimmt das Label nicht?'::text,
            'perigon'::text
           FROM r
          WHERE r.charge_nr IS NOT NULL AND r.label_verkauft = 'D'::text AND r.label_geliefert = 'K'::text
        UNION ALL
         SELECT 'mix'::text,
            r.quelle,
            r.pos_id,
            r.nummer,
            r.lauf_nr,
            r.charge_nr,
            r.sorte,
            r.kg_lieferung,
            format('Verkauft als „%s" auf Charge %s (%s). Die App hat den Mix nicht nach dem Rezept verteilt (in der Datei fehlt der Kisteninhalt, Spalte „AuftragsGebindeinhalt", oder es gibt kein Rezept) — sie zieht die ganzen %s kg von %s ab.'::text, r.artikel, r.charge_nr, r.sorte, kg_wort(r.kg_lieferung), r.charge_nr) AS format,
            'Fehlt der Kisteninhalt, in Perigon nachtragen und neu einlesen; fehlt das Rezept, unter Betrieb → Stammdaten → Sorten und Artikel (Kürbis Mix) eintragen. Gehört der Mix zu einer anderen Charge, in Perigon die Charge (Spalte W) berichtigen.'::text,
            'firma'::text
           FROM r
          WHERE r.charge_nr IS NOT NULL AND r.gruppe_artikel = 'Mix'::text AND NOT (EXISTS ( SELECT 1
                   FROM mixteil m
                  WHERE m.quelle = r.quelle AND m.pos_id = r.pos_id AND m.basis = ((r.nummer || ':'::text) || r.lauf_nr)))
        UNION ALL
         SELECT 'mix_verteilt'::text,
            r.quelle,
            r.pos_id,
            r.nummer,
            r.lauf_nr,
            r.charge_nr,
            r.sorte,
            r.kg_lieferung + m.kg,
            format('„%s" (%s kg) nach dem Mix-Rezept verteilt: %s kg auf Charge %s (%s), dazu %s.'::text, r.artikel, kg_wort(r.kg_lieferung + m.kg), kg_wort(r.kg_lieferung), r.charge_nr, r.sorte, m.text) AS format,
            'Nichts. Das Rezept steht unter Betrieb → Stammdaten → Sorten und Artikel (Kürbis Mix); stimmt es nicht mehr, dort berichtigen und neu einlesen.'::text,
            'nichts'::text
           FROM r
             JOIN mixteil m ON m.quelle = r.quelle AND m.pos_id = r.pos_id AND m.basis = ((r.nummer || ':'::text) || r.lauf_nr)
          WHERE r.gruppe_artikel = 'Mix'::text
        UNION ALL
         SELECT 'vor_eingang'::text,
            r.quelle,
            r.pos_id,
            r.nummer,
            r.lauf_nr,
            r.charge_nr,
            r.sorte,
            r.kg_lieferung,
            format('Geliefert am %s, aber die Charge %s kam laut Erntejournal erst am %s an (%s Tage später) — von ihr kann die Ware nicht sein.'::text, to_char(r.datum::timestamp with time zone, 'DD.MM.YYYY'::text), r.charge_nr, to_char(r.erster_eingang::timestamp with time zone, 'DD.MM.YYYY'::text), r.erster_eingang - r.datum) AS format,
            'Entweder steht die falsche Charge auf dem Lieferschein (in Perigon Spalte W berichtigen) oder das Eingangsdatum im Erntejournal stimmt nicht.'::text,
            'perigon'::text
           FROM r
          WHERE r.charge_nr IS NOT NULL AND r.erster_eingang IS NOT NULL AND r.datum < r.erster_eingang
        )
 SELECT ((((f.art || ':'::text) || f.quelle) || ':'::text) || f.pos_id) || COALESCE(((':'::text || f.nummer) || ':'::text) || f.lauf_nr, ''::text) AS schluessel,
    f.art,
        CASE
            WHEN f.art = ANY (ARRAY['nachholen'::text, 'ruecknahme'::text, 'mix_verteilt'::text]) THEN 'info'::text
            WHEN (f.art = ANY (ARRAY['menge_null'::text, 'keine_nummer'::text, 'rest'::text, 'unbekannt'::text, 'mehrdeutig'::text, 'vor_eingang'::text, 'artikel_sorte'::text, 'masse_abweichung'::text])) AND abs(COALESCE(f.kg, 0::numeric)) >= 500::numeric THEN 'rot'::text
            ELSE 'gelb'::text
        END AS schwere,
    f.quelle,
    f.pos_id,
    p.datum,
    p.kunde,
    p.artikel,
    p.einheit,
    zahl(p.menge, 3, '1000000000000'::numeric)::numeric(14,3) AS menge,
    zahl(p.gewicht_je_artikel, 4, '100000000'::numeric)::numeric(12,4) AS gewicht_je_artikel,
    p.preisgruppe,
    p.liefer_label,
    zahl(p.kg_position, 2, '1000000000000'::numeric)::numeric(14,2) AS kg_position,
    zahl(p.kg_zugeteilt, 2, '1000000000000'::numeric)::numeric(14,2) AS kg_zugeteilt,
    zahl(p.kg_rechnung, 2, '1000000000000'::numeric)::numeric(14,2) AS kg_rechnung,
    zahl(p.kg_ohne, 2, '1000000000000'::numeric)::numeric(14,2) AS kg_ohne_charge,
    zahl(f.kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kg,
    p.nummern,
    f.nummer,
    f.lauf_nr,
    COALESCE(f.charge_nr, p.charge_nr) AS charge_nr,
    COALESCE(f.sorte, p.sorte) AS sorte,
    p.n_zeilen,
    f.satz,
    f.tun,
    f.wo,
    p.eingelesen
   FROM fall f
     JOIN p ON p.quelle = f.quelle AND p.pos_id = f.pos_id;
comment on view v_perigon_befund is 'Jeder Fall einer Perigon-Position (0126), je mit einem Schlüssel, der von Rechnen zu Rechnen gleich bleibt (art:quelle:pos_id[:nummer:lauf]). Position: menge_null (Chargen genannt, Spalte S = 0 — auch Q = 0), zu_viel (Chargenzeilen > Position, z.B. dieselbe Zeile mehrfach), rest (Chargenzeilen < Position), keine_nummer (Spalte W leer), ohne_gewicht (Stück ohne Gewicht je Artikel, Masse unbekannt), ruecknahme (negative Menge), masse_abweichung (Lieferungen der Rechnung ≠ Masse der Datei), label_name (Artikelname gegen Preisgruppe), label_gemischt (Demeter- und Knospe-Ware in einer Position, die als Demeter benannt oder verrechnet ist, 0131; seit 0140 nur so: Demeter darf als Knospe verkauft werden, Knospe nicht als Demeter), kg_gewicht (kg-Artikel mit Gewicht je Artikel ≠ 1, 0131). Chargenzeile: unique_ohne_hagel (Ünique unter einer Charge ohne Hagel, 0133), nachholen (Nummer inzwischen bekannt), mehrdeutig, unbekannt, artikel_sorte, demeter_knospe, mix (Kürbis Mix auf einer Charge, nicht verteilt), mix_verteilt (nach Rezept verteilt, info, 0131), vor_eingang. kg: die Masse, um die es geht (nie 0 statt unbekannt); satz, tun und wo (perigon, stammdaten, einlesen, firma, nichts). Löst v_perigon_pruefung ab, die stehen bleibt.';

-- ---------- Stand ----------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 140 $$;
