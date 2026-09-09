-- =====================================================================
-- 0063 — Jede Sicht sagt, was sie ist
--
-- WIE DAS AUFGEFALLEN IST
--
-- setup.sql war zu gross für den Supabase-SQL-Editor geworden (1,14 MB gegen
-- eine Grenze von 1 MB). Die Datei wird seither verdichtet gebaut: Tabellen
-- und Daten bleiben als Geschichte stehen, die Formeln stehen nur noch in
-- ihrer heutigen Fassung. Damit das nachweislich dieselbe Datenbank ergibt,
-- vergleicht supabase/test/run.sh jetzt zwei Fingerabdrücke — einen aus den
-- Migrationen einzeln, einen aus setup.sql.
--
-- Dieser Vergleich hat etwas gefunden, wonach niemand gesucht hatte: In der
-- laufenden Datenbank haben 26 Ansichten gar keine Beschreibung. Nicht, weil
-- niemand eine geschrieben hätte — v_kaskade, v_marge_buch und v_massenbilanz
-- hatten eine —, sondern weil sie unterwegs verloren ging. Wer eine Ansicht
-- mit "drop ... cascade" wegräumt, reisst die darauf aufbauenden mit; die
-- werden gleich danach neu gebaut, ihre Beschreibung aber nicht. Beim ersten
-- Mal ist das unauffällig, nach neun Umbauten steht die halbe Auswertung
-- unbeschriftet da.
--
-- WARUM DAS ZÄHLT
--
-- Die Beschreibung ist das, was im SQL-Editor, in der Doku und in jedem
-- Werkzeug steht, das die Datenbank ausliest: was diese Zahl bedeutet und
-- worauf sie sich bezieht. Ohne sie ist "kg" nur "kg". Das ist genau die
-- Lücke, gegen die der Begriffs-Prüfstand auf der Oberfläche antritt — hier
-- ist sie eine Ebene tiefer.
--
-- Die Texte hier sind neu geschrieben, für die Fassung, die heute gilt. Keine
-- alte Beschreibung ist zurückgeholt worden: Eine Erklärung von damals kann
-- auf eine Formel von heute nicht mehr passen.
--
-- WAS NOCH DRINSTEHT
--
-- Der Rundumschlag "keine Funktion ist für PUBLIC ausführbar" stammt aus 0035
-- und galt für das, was damals da war. Seither sind Funktionen dazugekommen.
-- In der Reihenfolge der Migrationen ist das nie aufgefallen; in der
-- verdichteten setup.sql entstehen die rechnenden Funktionen ganz am Schluss.
-- Der Verdichter zieht solche Rundumschläge deshalb ans Ende — und damit das
-- nicht von einer Reihenfolge abhängt, steht die Regel hier noch einmal
-- ausdrücklich. Sie nimmt niemandem etwas: Was authenticated oder anon
-- ausführen darf, steht auf diesen Rollen, nicht auf PUBLIC.
-- =====================================================================

revoke execute on all functions in schema public from public;

-- ---------- Rohstoff: was gemessen wurde ---------------------------------

comment on view v_palette is
  'Jede Eingangspalette mit ihrem Nettogewicht: Brutto minus Tara der '
  'Gebindeart mal Kistenzahl. netto_kg ist leer, solange die Gebindeart '
  'fehlt — leer heisst hier "nicht bekannt", nicht "null Kilo".';

comment on view v_auftrag_angabe is
  'Die freien Angaben zu einer Arbeit (Palox-Stand, Kistensystem, Notizen) '
  'als Schlüssel-Wert-Paare, je Arbeit eine Zeile pro Angabe.';

comment on view v_sortier_lauf_masse is
  'Je Sortierlauf aus der Waage-Datei: wie viele Kürbisse mit welcher Masse '
  'in welchen Kanal gingen — Kaliber (verkaufsfähig), zu klein, Nebenkanal. '
  'Alle Massen in kg, gewogen, nicht gerechnet.';

comment on materialized view mv_sortier_lauf_masse is
  'v_sortier_lauf_masse, gespeichert. Inhaltlich gleich; erneuert von '
  'auswertung_schritt(1).';

comment on materialized view mv_sortier_eingang is
  'Je Charge der früheste Sortiertag als Tage seit 1970 — die Rechengrösse '
  'für das Alter beim Verarbeiten. Nur eine Hilfsgrösse, keine Kennzahl.';

comment on view v_datenlage is
  'Je Charge: wie viel überhaupt erfasst ist — Paletten, davon mit bekanntem '
  'Netto, Wiegungen, Schimmelmessungen, Sortierläufe, Arbeiten. Die Zahlen '
  'sagen, wie belastbar alles andere zu dieser Charge ist.';

-- ---------- Die Kaskade und was auf ihr steht ----------------------------

comment on view v_kaskade is
  'Der Massenfluss je Charge, Eingangstag und Portion: Was eingelagert wurde '
  '(eingang_kg) verteilt sich auf Verdunstung, Palox-Sockel, Schimmel, zu '
  'klein, Nebenkanal, Fax und verkaufsfähige Ware. Die Ströme addieren sich '
  'zum Eingang. "Verlust" ist hier nur, was wirklich verloren ist: '
  'verdunstung_kg, sockel_kg, schimmel_kg. klein_kg und nebenkanal_kg sind '
  'kein Verlust, sondern ein anderer Kanal; ueberzaehlung_kg ist kein '
  'Verlust, sondern ein Erfassungsfehler.';

comment on materialized view mv_kaskade is
  'v_kaskade, gespeichert. Inhaltlich gleich; erneuert von '
  'auswertung_schritt(3).';

comment on view v_hochrechnung is
  'Die Kaskade auseinandergelegt: eine Zeile je Charge, Portion und Strom, '
  'mit dem verwendeten Koeffizienten, seiner Herkunft (koeff_art), der Zahl '
  'der Messungen dahinter (koeff_n) und der Formel. koeff_bekannt = false '
  'heisst: geschätzt, nicht gemessen.';

comment on materialized view mv_hochrechnung is
  'v_hochrechnung, gespeichert. Inhaltlich gleich; erneuert von '
  'auswertung_schritt(3).';

comment on view v_verlust_je_gruppe is
  'Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, '
  'Charge). kg_beobachtet ist gemessen, kg_projiziert auf noch nicht '
  'Gemessenes übertragen, kg_extrapoliert über den Messbereich hinaus '
  'gerechnet — drei verschiedene Sicherheiten, darum drei Spalten.';

comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb verlassen hat, ohne verkaufsfähig zu sein — '
  'zu klein, Nebenkanal, Überfüllung. Kein Verlust im Sinne von verdorben, '
  'sondern Masse in einem anderen Kanal. kg_unten und kg_oben spannen den '
  'Bereich auf, gemessen sagt, ob dahinter Messungen oder Schätzungen '
  'stehen.';

comment on view v_massenbilanz is
  'Die Probe aufs Exempel je Charge: Was das Modell am Band erwartet '
  '(modell_am_band_kg) gegen das, was die Sortier-Datei gewogen hat '
  '(csv_gemessen_kg). abweichung_anteil nahe 0 heisst, die Koeffizienten '
  'treffen die Wirklichkeit; systematisch positiv heisst, die Verluste sind '
  'überschätzt. Nur für Chargen mit Sortier-Datei aussagekräftig.';

comment on view v_kontrolle_vorschlag is
  'Welche Charge als Nächstes kontrolliert werden sollte. informationswert '
  'gewichtet, wie viel noch im Haus liegt, wie lange die letzte Wiegung her '
  'ist und wie unsicher die Charge bisher ist — eine Reihenfolge, kein '
  'Befehl.';

-- ---------- Kaliber und Gebinde ------------------------------------------

comment on view v_kaliber_verteilung is
  'Wie sich die sortierte Ware je Charge auf die Kaliberbänder verteilt: '
  'Stückzahl und Masse je Band, dazu die Klassen "zu klein" und '
  '"Nebenkanal". Gewogen aus den Sortierläufen.';

comment on materialized view mv_kaliber_verteilung is
  'v_kaliber_verteilung, gespeichert. Inhaltlich gleich; erneuert von '
  'auswertung_schritt(2).';

comment on materialized view mv_auftrag_masse is
  'Je Arbeit die Eingangsmasse und woher sie kommt (masse_quelle: gewogen, '
  'aus Paletten gerechnet oder geschätzt), dazu Station, Dauer und '
  'Lagertage. Erneuert von auswertung_schritt(1).';

-- ---------- Koeffizienten: wie stark ein Strom ist ------------------------

comment on view v_koeff_roh_verdunstung is
  'Die einzelnen Verdunstungsmessungen, bevor gemittelt wird: je Charge ein '
  'Anteil und sein Gewicht in der Mittelung. Die Rohdaten zu '
  'v_koeff_verdunstung — hier steht, worauf der Koeffizient beruht.';

comment on view v_koeff_verdunstung_geschaetzt is
  'Der Verdunstungs-Koeffizient je Sorte, gepoolt: eigener Mittelwert und '
  'Gesamtmittel, gewichtet nach Streuung (tau2, b). Sorten mit wenigen '
  'Messungen rücken damit näher an den Gesamtwert, statt an einem Ausreisser '
  'zu hängen.';

comment on view v_koeff_ausschuss is
  'Der Ausschuss-Koeffizient je Sorte mit Bereich (unten, oben), Zahl der '
  'Messungen (n) und Bezugsgrösse (basis). Anteil der Eingangsmasse, die '
  'beim Verarbeiten als Ausschuss anfällt.';

comment on view v_koeff_nebenkanal is
  'Der Nebenkanal-Koeffizient je Sorte mit Bereich, Zahl der Messungen und '
  'Bezugsgrösse. Anteil der Masse, der weder verkaufsfähig noch Verlust ist, '
  'sondern in einen anderen Kanal geht.';

-- ---------- Schimmel: Modell und Kurve ------------------------------------

comment on view v_schimmel_kurve is
  'Die gemessenen Schimmelanteile nach Altersklassen: je Klasse Mittelwert, '
  'Streuung und Bereich. anteil_mono ist derselbe Wert monoton gemacht — '
  'Kürbisse werden mit der Zeit nicht wieder gesund.';

comment on view v_schimmel_kurve_anzeige is
  'Die Schimmel-Hochrechnung zum Nachschauen: je Altersklasse, was gemessen '
  'wurde, was daraus verwendet wird und warum. Für den Bildschirm '
  '"Messungen", nicht zum Weiterrechnen.';

comment on view v_schimmel_modell_rechnen is
  'Die Anpassung des Verderbsmodells f(t) = 1 - exp(-lambda*t^k), Schritt '
  'für Schritt: Steigung, Achsenabschnitt, Streuungen, Kovarianz, '
  't-Faktor. brauchbar sagt, ob genug Messungen dahinterstehen.';

comment on materialized view mv_schimmel_modell is
  'Das gerechnete Verderbsmodell, gespeichert — dieselben Grössen wie '
  'v_schimmel_modell_rechnen. sockel ist der Anteil, der schon beim '
  'Einlagern verdorben war und nicht dem Lager anzulasten ist. Erneuert von '
  'auswertung_schritt(2).';

comment on view v_selektionsverdacht is
  'Prüft, ob beim Messen unbewusst ausgewählt wurde: Bleibt bei Chargen, die '
  'gerade verarbeitet werden, systematisch anderes übrig als bei denen im '
  'Lager? unterschied und befund sagen, ob der Verdacht trägt.';

-- ---------- Reste aus Zwischenständen ------------------------------------

comment on view v_plausibilitaet_0054_zusatz is
  'Zusatzprüfungen zu v_plausibilitaet, die seit 0054 dazugekommen sind — '
  'je Auffälligkeit Art, betroffene Arbeit, Befund und Rat. Wird von '
  'v_plausibilitaet mitgelesen; einzeln braucht sie niemand.';

-- ---------- Stand ---------------------------------------------------------

create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 63 $$;
