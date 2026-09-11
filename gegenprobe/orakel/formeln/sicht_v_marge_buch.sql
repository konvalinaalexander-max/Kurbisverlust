-- sicht: v_marge_buch
-- Buch B: Ware, die den Betrieb verlassen hat, ohne verkaufsfähig zu sein — zu klein, Nebenkanal, Überfüllung. Kein Verlust im Sinne von verdorben, sondern Masse in einem anderen Kanal. kg_unten und kg_oben spannen den Bereich auf, gemessen sagt, ob dahinter Messungen oder Schätzungen stehen.

 WITH verkauf AS (
         SELECT sum(erg_ueberfuellung.verschenkt_kg) AS verschenkt_kg,
            sum(
                CASE
                    WHEN erg_ueberfuellung.verschenkt_kg IS NULL THEN NULL::numeric
                    ELSE GREATEST(erg_ueberfuellung.verschenkt_kg - COALESCE(erg_ueberfuellung.verschenkt_fehler_kg, 0::numeric), 0::numeric)
                END) AS verschenkt_unten_kg,
            sum(erg_ueberfuellung.verschenkt_kg + COALESCE(erg_ueberfuellung.verschenkt_fehler_kg, 0::numeric)) AS verschenkt_oben_kg,
            sum(erg_ueberfuellung.kisten_verkauft) FILTER (WHERE erg_ueberfuellung.n_wiegungen > 0) AS kisten_gerechnet,
            sum(erg_ueberfuellung.kisten_verkauft) FILTER (WHERE erg_ueberfuellung.n_wiegungen = 0) AS kisten_ungewogen,
            sum(erg_ueberfuellung.n_wiegungen) AS n_wiegungen,
            sum(erg_ueberfuellung.kisten_gewogen) AS kisten_gewogen,
            sum(erg_ueberfuellung.zuviel_je_kiste * erg_ueberfuellung.kisten_gewogen::numeric) / NULLIF(sum(erg_ueberfuellung.kisten_gewogen) FILTER (WHERE erg_ueberfuellung.zuviel_je_kiste IS NOT NULL), 0::numeric) AS zuviel_je_kiste,
            count(*) FILTER (WHERE erg_ueberfuellung.n_lieferungen > 0)::integer AS n_gruppen_verkauft
           FROM erg_ueberfuellung
          WHERE erg_ueberfuellung.gruppe = 'sorte'::text AND erg_ueberfuellung.kistensystem = 'kiste_ab'::text
        ), datei AS (
         SELECT count(*)::integer AS n
           FROM lieferung_import
        )
 SELECT r.strom AS posten,
    r.kg,
    r.kg_unten,
    r.kg_oben,
        CASE r.strom
            WHEN 'Nebenkanal zu gross'::text THEN 'Ware über der oberen Kalibergrenze geht in einen anderen Verkaufskanal — nicht weg, nur nicht zum besten Preis'::text
            WHEN 'Zu klein (Tierfutter)'::text THEN 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'::text
            ELSE ''::text
        END AS erlaeuterung,
    r.kg IS NOT NULL AS gemessen
   FROM erg_verlust r
  WHERE r.gruppe = 'gesamt'::text AND r.buch = 'marge'::text
UNION ALL
 SELECT 'Überfüllung der Kisten'::text AS posten,
    zahl(v.verschenkt_kg)::numeric(14,2) AS kg,
    zahl(v.verschenkt_unten_kg)::numeric(14,2) AS kg_unten,
    zahl(v.verschenkt_oben_kg)::numeric(14,2) AS kg_oben,
        CASE
            WHEN d.n = 0 THEN 'Keine Verkaufsdatei eingelesen — wie viele Kisten „ab x kg" verkauft wurden, weiss die App nicht. Nichts gerechnet.'::text
            WHEN COALESCE(v.n_wiegungen, 0::bigint) = 0 THEN format('%s Kisten „ab x kg" laut Verkaufsdatei verkauft, aber keine fertige Palette dieses Systems gewogen — nichts gerechnet.'::text, round(COALESCE(v.kisten_ungewogen, 0::numeric)))
            ELSE format(('%s gewogene Paletten (%s Kisten): im Schnitt %s kg je Kiste über dem Soll. '::text || 'Verkauft laut Verkaufsdatei: %s Kisten desselben Systems — daraus die Zahl. '::text) || '%s'::text, v.n_wiegungen, round(COALESCE(v.kisten_gewogen, 0::numeric)), round(COALESCE(v.zuviel_je_kiste, 0::numeric), 3), round(COALESCE(v.kisten_gerechnet, 0::numeric)),
            CASE
                WHEN COALESCE(v.kisten_ungewogen, 0::numeric) > 0::numeric THEN format('Weitere %s verkaufte Kisten haben kein gewogenes Gegenstück (Sorte oder Soll ohne Wägung) und sind nicht gerechnet.'::text, round(v.kisten_ungewogen))
                ELSE 'Kisten nach Stück haben kein Sollgewicht und damit keine Überfüllung.'::text
            END)
        END AS erlaeuterung,
    v.verschenkt_kg IS NOT NULL AS gemessen
   FROM verkauf v
     CROSS JOIN datei d;
