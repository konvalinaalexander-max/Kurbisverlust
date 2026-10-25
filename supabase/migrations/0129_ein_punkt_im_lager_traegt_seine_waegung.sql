-- =====================================================================
-- 0129 — Ein Punkt im Lager trägt seine Wägung
-- =====================================================================
--
-- WARUM
--
-- Am 25. Oktober fiel der Prüfblock 0095 (b2) durch — auch auf dem Stand
-- davor, ohne dass jemand etwas geändert hatte: „nach dem Zeitplan-Lauf
-- ohne eindeutigen Spaltenindex: erg_punkte". Die Demo-Saison rechnet vom
-- heutigen Tag aus; an diesem Tag wog sie zwei Kontrollpaletten derselben
-- Charge am selben Tag, beide gleich lange gelagert. Ihre beiden Faul-Punkte
-- hatten denselben Schlüssel (Charge, Arbeit, Quelle, Messtag, Lagertage) —
-- ein Punkt aus dem Lager hat keine Arbeit, die ihn unterscheidet.
--
-- Im Betrieb ist das kein Sonderfall, sondern die Regel: Eine Lagerkontrolle
-- wiegt mehrere Paletten derselben Charge am selben Tag. Dann bekommt
-- erg_punkte keinen eindeutigen Index, und die Nacht erneuert sie nicht
-- nebenläufig (die App wartet, statt die alte Fassung zu lesen). Gerechnet
-- wird nichts anders — es fehlt nur die Kennung.
--
-- 1. v_schimmel_punkte_formel bekommt hinten die Spalte messung_id: bei einem
--    Punkt aus dem Lager die Wägung (verdunstung_wiegung.id — dieselbe, die
--    „benutzen" an/ab ausschliesst), sonst leer (die Arbeit unterscheidet).
--    Angehängt, nichts weggenommen; die Formel bleibt Zeichen für Zeichen.
-- 2. v_schimmel_punkte reicht sie durch, erg_punkte wird mit ihr neu
--    angelegt (leer bis zum nächsten Rechnen, wie jede neue Fassung).
-- 3. Der Schlüssel von erg_punkte nimmt sie dazu.
--
-- Prüfblock 0129 in supabase/test/pruefung.sql: zwei Lagerwägungen
-- derselben Charge am selben Tag, beide mit Faulem — zwei Punkte, zwei
-- Schlüssel, und erg_punkte bekommt ihren eindeutigen Index.
-- =====================================================================

-- =====================================================================
-- 1. Die Formel, mit der Wägung
-- =====================================================================
create or replace view v_schimmel_punkte_formel with (security_invoker = true) as
WITH sortier_lauf_anteil AS MATERIALIZED (
         SELECT b.charge_nr,
            b.start_ts,
            b.schimmel_kg,
            b.basis_jetzt_kg
           FROM v_schimmel_beobachtung b
          WHERE ((b.station = 'sortieren'::station) AND b.plausibel AND (b.anteil IS NOT NULL))
        ), gemischt AS (
         SELECT v_auftrag_angabe.auftrag_id
           FROM v_auftrag_angabe
          WHERE ((v_auftrag_angabe.schluessel = 'eine_charge'::text) AND (v_auftrag_angabe.wert = 'false'::text))
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lagertage,
    b.schimmel_kg,
    b.basis_jetzt_kg,
    b.anteil,
    (b.plausibel AND (NOT (EXISTS ( SELECT 1
           FROM messung_ausschluss x
          WHERE ((x.art = 'palox'::text) AND (x.bezug_id = b.auftrag_id)))))) AS plausibel,
        CASE
            WHEN (g.auftrag_id IS NOT NULL) THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    b.auftrag_id,
    betriebstag(b.start_ts) AS messtag,
    (b.station)::text AS station,
    b.anteil AS anteil_station,
    (b.plausibel AND (NOT (EXISTS ( SELECT 1
           FROM messung_ausschluss x
          WHERE ((x.art = 'palox'::text) AND (x.bezug_id = b.auftrag_id)))))) AS plausibel_station,
    NULL::bigint AS messung_id
   FROM (v_schimmel_beobachtung b
     LEFT JOIN gemischt g ON ((g.auftrag_id = b.auftrag_id)))
  WHERE (b.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station]))
UNION ALL
 SELECT a.charge_nr,
    a.sorte,
    a.schlag,
    a.lagertage,
    s.kg AS schimmel_kg,
    (a.eingang_netto_kg + s.kg) AS basis_jetzt_kg,
    k.f2 AS anteil,
    (anteil_plausibel(k.f2) AND (a.lagertage >= (0)::numeric) AND (NOT (EXISTS ( SELECT 1
           FROM messung_ausschluss x_1
          WHERE ((x_1.art = 'palox'::text) AND (x_1.bezug_id = a.auftrag_id)))))) AS plausibel,
        CASE
            WHEN (g.auftrag_id IS NOT NULL) THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    a.auftrag_id,
    betriebstag(a.start_ts) AS messtag,
    'waschen'::text AS station,
    x.g AS anteil_station,
    (anteil_plausibel(x.g) AND (a.lagertage >= (0)::numeric) AND (NOT (EXISTS ( SELECT 1
           FROM messung_ausschluss x_1
          WHERE ((x_1.art = 'palox'::text) AND (x_1.bezug_id = a.auftrag_id)))))) AS plausibel_station,
    NULL::bigint AS messung_id
   FROM (((((v_auftrag_masse a
     JOIN v_schimmel_menge s ON ((s.auftrag_id = a.auftrag_id)))
     LEFT JOIN gemischt g ON ((g.auftrag_id = a.auftrag_id)))
     LEFT JOIN LATERAL ( SELECT (sum(sl.schimmel_kg) / NULLIF(sum(sl.basis_jetzt_kg), (0)::numeric)) AS f1
           FROM sortier_lauf_anteil sl
          WHERE ((sl.charge_nr = a.charge_nr) AND (sl.start_ts <= a.start_ts))) sa ON (true))
     CROSS JOIN LATERAL ( SELECT (s.kg / NULLIF((a.eingang_netto_kg + s.kg), (0)::numeric)) AS g) x)
     CROSS JOIN LATERAL ( SELECT ((1)::numeric - (((1)::numeric - LEAST(GREATEST(COALESCE(sa.f1, (0)::numeric), (0)::numeric), 0.99)) * ((1)::numeric - LEAST(GREATEST(COALESCE(x.g, (0)::numeric), (0)::numeric), 0.99)))) AS f2) k)
  WHERE ((a.station = 'waschen'::station) AND (NOT a.ist_fax) AND (a.lagertage IS NOT NULL) AND (a.eingang_netto_kg IS NOT NULL) AND (a.eingang_netto_kg > (0)::numeric))
UNION ALL
 SELECT w.charge_nr,
    w.sorte,
    w.schlag,
    w.lagertage,
    v.faul_kg AS schimmel_kg,
    w.netto_jetzt_kg AS basis_jetzt_kg,
    (v.faul_kg / NULLIF(w.netto_jetzt_kg, (0)::numeric)) AS anteil,
    (anteil_plausibel((v.faul_kg / NULLIF(w.netto_jetzt_kg, (0)::numeric))) AND (NOT (EXISTS ( SELECT 1
           FROM messung_ausschluss x
          WHERE ((x.art = 'palox_lager'::text) AND (x.bezug_id = w.id)))))) AS plausibel,
    'lager'::text AS quelle,
    NULL::bigint AS auftrag_id,
    betriebstag(w.wiege_ts) AS messtag,
    'lager'::text AS station,
    (v.faul_kg / NULLIF(w.netto_jetzt_kg, (0)::numeric)) AS anteil_station,
    (anteil_plausibel((v.faul_kg / NULLIF(w.netto_jetzt_kg, (0)::numeric))) AND (NOT (EXISTS ( SELECT 1
           FROM messung_ausschluss x
          WHERE ((x.art = 'palox_lager'::text) AND (x.bezug_id = w.id)))))) AS plausibel_station,
    w.id AS messung_id
   FROM (v_verdunstung_messung w
     JOIN verdunstung_wiegung v ON ((v.id = w.id)))
  WHERE ((v.faul_kg IS NOT NULL) AND v.gemessen AND (w.netto_jetzt_kg > (0)::numeric) AND (w.lagertage > 0));

comment on view v_schimmel_punkte_formel is
  'Jede Faul-Messung als Punkt: die Lagerdauer (wie lange lag die Ware?) und seit 0079 der Messtag (wann wurde gemessen?). Zwei Achsen für zwei Fragen — „faulen sie nach N Wochen" und „ab wann ging es los". Der Messtag ist der Betriebstag, nie ts::date (0067/0070). — Die Formel (0109); gelesen wird sie über die gleichnamige Sicht ohne _formel. 0129: messung_id — bei einem Punkt aus dem Lager die Wägung, sonst leer; zwei Kontrollpaletten derselben Charge am selben Tag sind zwei Punkte.';
grant select on v_schimmel_punkte_formel to authenticated;

create or replace view v_schimmel_punkte with (security_invoker = true) as
select * from v_schimmel_punkte_zaun();
comment on view v_schimmel_punkte is
  'Jede Faul-Messung als Punkt: die Lagerdauer (wie lange lag die Ware?) und seit 0079 der Messtag (wann wurde gemessen?). Zwei Achsen für zwei Fragen — „faulen sie nach N Wochen" und „ab wann ging es los". Der Messtag ist der Betriebstag, nie ts::date (0067/0070). Seit 0109 über die Planungsgrenze v_schimmel_punkte_zaun(); die Formel steht in v_schimmel_punkte_formel. 0129: mit messung_id.';
grant select on v_schimmel_punkte to authenticated;

-- =====================================================================
-- 2. erg_punkte neu, mit der Spalte
-- =====================================================================
-- verdichter: baut erg_punkte
do $$
begin
  execute 'drop materialized view if exists erg_punkte cascade';
  execute 'create materialized view erg_punkte as select * from v_schimmel_punkte with no data';
  execute 'create index if not exists erg_punkte_charge on erg_punkte (charge_nr)';
  execute 'grant select on erg_punkte to authenticated';
end $$;
-- Als eigene Anweisung, nicht im Block: setup.sql behält je Objekt den
-- jüngsten Kommentar — der aus 0105 stünde sonst hinter diesem Neubau.
comment on materialized view erg_punkte is
  'v_schimmel_punkte mit dem Messtag (0079) und seit 0105 mit Station und eigenem Anteil, gespeichert für die App. Erneuert mit auswertung_schritt(). 0129: mit messung_id (die Wägung eines Punkts aus dem Lager).';

-- =====================================================================
-- 3. Der Schlüssel
-- =====================================================================
create or replace function auswertung_schluessel()
 RETURNS TABLE(sicht text, ausdruck text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  values
    ('erg_ausgang',            'id'),
    ('erg_bilanz',             'heute'),
    ('erg_charge',             'charge_nr'),
    ('erg_datenlage',          'charge_nr'),
    ('erg_datenqualitaet',     'paletten_gezaehlt'),
    ('erg_durchsatz',          'auftrag_id'),
    ('erg_fax',                'auftrag_id'),
    ('erg_fax_wartezeit',      'gruppe, sorte, klasse'),
    ('erg_gebinde',            'sorte, kaliber_idx'),
    ('erg_gewichte',           'charge_nr, stufe_g'),
    ('erg_kaliber',            'charge_nr, klasse, kaliber_idx, band_von, band_bis'),
    ('erg_koeff_ausschuss',    'sorte'),
    ('erg_koeff_fax',          'sorte'),
    ('erg_koeff_nebenkanal',   'sorte'),
    ('erg_koeff_ueberfuellung','n'),
    ('erg_koeff_verdunstung',  'sorte'),
    ('erg_kohorte',            'charge_nr, eingangsdatum'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_palox_erwartung',    'sorte, station'),
    ('erg_plausibilitaet',     'art, bezug, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage, messung_id'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte')
$function$;

comment on function auswertung_schluessel() is
  'Je gespeicherter Ansicht die Spalten, unter denen ihre Zeilen eindeutig sind — der Schlüssel des Index, mit dem der Zeitplan sie nebenläufig erneuert (0095). Jede erg_-Ansicht steht hier; der Prüfblock verlangt es. 0128: erg_plausibilitaet mit bezug. 0129: erg_punkte mit messung_id.';

-- =====================================================================
-- Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 129 $$;
