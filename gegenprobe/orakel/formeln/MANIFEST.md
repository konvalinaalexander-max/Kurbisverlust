# Die Rechenobjekte, wie die Datenbank sie heute hält

Abgezogen aus der Datenbank `demo` mit `node gegenprobe/orakel/formeln_holen.mjs`.
Nicht von Hand ändern — der nächste Abzug überschreibt alles. Wer wissen will, ob sich
eine Formel seit dem letzten Abzug bewegt hat, zieht neu ab und sieht es im `git diff`.

63 Sichten, 38 gespeicherte Sichten, 44 Funktionen.

| Art | Name | Datei | Zeilen | Prüfsumme |
|---|---|---|---|---|
| gespeichert | `erg_ausgang` | `gespeichert_erg_ausgang.sql` | 23 | `ece01c31cfd5` |
| gespeichert | `erg_ausschuss` | `gespeichert_erg_ausschuss.sql` | 9 | `1efeaef8a5c2` |
| gespeichert | `erg_bilanz` | `gespeichert_erg_bilanz.sql` | 38 | `c5a66a2ae89f` |
| gespeichert | `erg_charge` | `gespeichert_erg_charge.sql` | 53 | `ac9b5a58f935` |
| gespeichert | `erg_datenlage` | `gespeichert_erg_datenlage.sql` | 11 | `361e1d0a66f3` |
| gespeichert | `erg_datenqualitaet` | `gespeichert_erg_datenqualitaet.sql` | 26 | `5000ab7e1502` |
| gespeichert | `erg_durchsatz` | `gespeichert_erg_durchsatz.sql` | 15 | `b11d79ce83b1` |
| gespeichert | `erg_fax` | `gespeichert_erg_fax.sql` | 20 | `416d3530d70f` |
| gespeichert | `erg_gebinde` | `gespeichert_erg_gebinde.sql` | 8 | `4bf2e1aa69d5` |
| gespeichert | `erg_gewichte` | `gespeichert_erg_gewichte.sql` | 6 | `20d8805623a6` |
| gespeichert | `erg_kaliber` | `gespeichert_erg_kaliber.sql` | 9 | `953c4e41b877` |
| gespeichert | `erg_koeff_ausschuss` | `gespeichert_erg_koeff_ausschuss.sql` | 7 | `06d826063d8f` |
| gespeichert | `erg_koeff_nebenkanal` | `gespeichert_erg_koeff_nebenkanal.sql` | 7 | `3087328aa05a` |
| gespeichert | `erg_koeff_ueberfuellung` | `gespeichert_erg_koeff_ueberfuellung.sql` | 6 | `69a51fc28af1` |
| gespeichert | `erg_koeff_verdunstung` | `gespeichert_erg_koeff_verdunstung.sql` | 7 | `e7c699d5e307` |
| gespeichert | `erg_kohorte` | `gespeichert_erg_kohorte.sql` | 10 | `f5173e9caf6e` |
| gespeichert | `erg_kurve` | `gespeichert_erg_kurve.sql` | 10 | `b13735cd91d4` |
| gespeichert | `erg_lieferung` | `gespeichert_erg_lieferung.sql` | 19 | `43c6ef16a799` |
| gespeichert | `erg_marge` | `gespeichert_erg_marge.sql` | 7 | `83de381d24a1` |
| gespeichert | `erg_massenbilanz` | `gespeichert_erg_massenbilanz.sql` | 17 | `a5f321496d73` |
| gespeichert | `erg_modell` | `gespeichert_erg_modell.sql` | 25 | `f36f05e060db` |
| gespeichert | `erg_naechste_charge` | `gespeichert_erg_naechste_charge.sql` | 15 | `9b74d6657c7f` |
| gespeichert | `erg_plausibilitaet` | `gespeichert_erg_plausibilitaet.sql` | 8 | `172b2cd0cb9e` |
| gespeichert | `erg_punkte` | `gespeichert_erg_punkte.sql` | 11 | `6130ec5d5fc8` |
| gespeichert | `erg_selektion` | `gespeichert_erg_selektion.sql` | 7 | `bd0e8eb5dc59` |
| gespeichert | `erg_ueberfuellung` | `gespeichert_erg_ueberfuellung.sql` | 28 | `7db5e3ebdee9` |
| gespeichert | `erg_verarbeitung_alter` | `gespeichert_erg_verarbeitung_alter.sql` | 12 | `ef92f06687a6` |
| gespeichert | `erg_verlauf` | `gespeichert_erg_verlauf.sql` | 158 | `a54483b6034e` |
| gespeichert | `erg_verlust` | `gespeichert_erg_verlust.sql` | 22 | `9bc3a22cdb13` |
| gespeichert | `erg_wiegung` | `gespeichert_erg_wiegung.sql` | 18 | `4e211199f262` |
| gespeichert | `mv_auftrag_masse` | `gespeichert_mv_auftrag_masse.sql` | 22 | `7b79dd8c0b0b` |
| gespeichert | `mv_hochrechnung` | `gespeichert_mv_hochrechnung.sql` | 42 | `15e7578062e0` |
| gespeichert | `mv_kaliber_verteilung` | `gespeichert_mv_kaliber_verteilung.sql` | 13 | `430bf250c221` |
| gespeichert | `mv_kaskade` | `gespeichert_mv_kaskade.sql` | 615 | `0b26bc509231` |
| gespeichert | `mv_schimmel_modell` | `gespeichert_mv_schimmel_modell.sql` | 25 | `55071a2f37b0` |
| gespeichert | `mv_schimmel_punkte` | `gespeichert_mv_schimmel_punkte.sql` | 11 | `fde374da48f8` |
| gespeichert | `mv_sortier_eingang` | `gespeichert_mv_sortier_eingang.sql` | 6 | `40153db2944b` |
| gespeichert | `mv_sortier_lauf_masse` | `gespeichert_mv_sortier_lauf_masse.sql` | 20 | `9da629ccf779` |
| sicht | `v_auftrag_angabe` | `sicht_v_auftrag_angabe.sql` | 7 | `31d5907bdd2f` |
| sicht | `v_auftrag_gebinde_masse` | `sicht_v_auftrag_gebinde_masse.sql` | 36 | `de2d6915ecd8` |
| sicht | `v_auftrag_masse` | `sicht_v_auftrag_masse.sql` | 39 | `6c0b32a108a2` |
| sicht | `v_auftrag_palette_masse` | `sicht_v_auftrag_palette_masse.sql` | 61 | `3176f5cd9043` |
| sicht | `v_auftrag_wasch_paletten` | `sicht_v_auftrag_wasch_paletten.sql` | 27 | `f9846d705b00` |
| sicht | `v_ausgang_artikel_vorschlag` | `sicht_v_ausgang_artikel_vorschlag.sql` | 52 | `d60713226270` |
| sicht | `v_ausgang_kennzahl` | `sicht_v_ausgang_kennzahl.sql` | 67 | `144f1087ff93` |
| sicht | `v_ausgang_lage` | `sicht_v_ausgang_lage.sql` | 30 | `e0dc43ffa76f` |
| sicht | `v_ausgang_pruef` | `sicht_v_ausgang_pruef.sql` | 35 | `a407062bb610` |
| sicht | `v_ausschuss_beobachtung` | `sicht_v_ausschuss_beobachtung.sql` | 30 | `5a1d1aa959a7` |
| sicht | `v_charge_kohorte` | `sicht_v_charge_kohorte.sql` | 35 | `6047ab48ae97` |
| sicht | `v_charge_rueckgrat` | `sicht_v_charge_rueckgrat.sql` | 15 | `41f9c4d48363` |
| sicht | `v_datenlage` | `sicht_v_datenlage.sql` | 20 | `29970ac0042d` |
| sicht | `v_datenqualitaet` | `sicht_v_datenqualitaet.sql` | 160 | `222babf04421` |
| sicht | `v_durchsatz` | `sicht_v_durchsatz.sql` | 23 | `02586574f660` |
| sicht | `v_fax_beobachtung` | `sicht_v_fax_beobachtung.sql` | 28 | `87b36418675c` |
| sicht | `v_gewichtsverteilung` | `sicht_v_gewichtsverteilung.sql` | 11 | `ad3d3bbdc291` |
| sicht | `v_hochrechnung` | `sicht_v_hochrechnung.sql` | 25 | `8baa061aae36` |
| sicht | `v_hochrechnung_basis` | `sicht_v_hochrechnung_basis.sql` | 127 | `8069e0820291` |
| sicht | `v_kaliber_verteilung` | `sicht_v_kaliber_verteilung.sql` | 9 | `7c6ef2229996` |
| sicht | `v_kaskade` | `sicht_v_kaskade.sql` | 49 | `27aaa517ff2b` |
| sicht | `v_kaskade_basis` | `sicht_v_kaskade_basis.sql` | 57 | `60c9bae3691d` |
| sicht | `v_koeff_ausschuss` | `sicht_v_koeff_ausschuss.sql` | 37 | `7c2b19d69e83` |
| sicht | `v_koeff_fax` | `sicht_v_koeff_fax.sql` | 37 | `7c3a4b8f4a3a` |
| sicht | `v_koeff_gebinde` | `sicht_v_koeff_gebinde.sql` | 54 | `b70804f9c45f` |
| sicht | `v_koeff_kaliber_geschaetzt` | `sicht_v_koeff_kaliber_geschaetzt.sql` | 106 | `237e8c91e63e` |
| sicht | `v_koeff_nebenkanal` | `sicht_v_koeff_nebenkanal.sql` | 37 | `2bcfb48a200c` |
| sicht | `v_koeff_palette_netto` | `sicht_v_koeff_palette_netto.sql` | 8 | `5bed2545146e` |
| sicht | `v_koeff_roh_kaliber` | `sicht_v_koeff_roh_kaliber.sql` | 23 | `bea484e6e802` |
| sicht | `v_koeff_roh_verdunstung` | `sicht_v_koeff_roh_verdunstung.sql` | 7 | `ffb53e1c31f8` |
| sicht | `v_koeff_ueberfuellung` | `sicht_v_koeff_ueberfuellung.sql` | 26 | `0263dca1bf4d` |
| sicht | `v_koeff_unsicherheit` | `sicht_v_koeff_unsicherheit.sql` | 17 | `2f14f2984385` |
| sicht | `v_koeff_verdunstung` | `sicht_v_koeff_verdunstung.sql` | 48 | `1f31ec3c619f` |
| sicht | `v_koeff_verdunstung_geschaetzt` | `sicht_v_koeff_verdunstung_geschaetzt.sql` | 106 | `f5e809f99386` |
| sicht | `v_kohorte_anteil` | `sicht_v_kohorte_anteil.sql` | 7 | `0a684c89565b` |
| sicht | `v_kontrolle_vorschlag` | `sicht_v_kontrolle_vorschlag.sql` | 23 | `0e244523add6` |
| sicht | `v_lieferung_kohorte` | `sicht_v_lieferung_kohorte.sql` | 41 | `a5d5fed03350` |
| sicht | `v_lieferung_masse` | `sicht_v_lieferung_masse.sql` | 36 | `0e3cc6150f2d` |
| sicht | `v_marge_buch` | `sicht_v_marge_buch.sql` | 49 | `730a611f6c83` |
| sicht | `v_massenbilanz` | `sicht_v_massenbilanz.sql` | 49 | `20201d7c3579` |
| sicht | `v_naechste_charge` | `sicht_v_naechste_charge.sql` | 109 | `19ea305bdfcf` |
| sicht | `v_palette` | `sicht_v_palette.sql` | 9 | `8986da3705b8` |
| sicht | `v_palox_stand` | `sicht_v_palox_stand.sql` | 19 | `28cc46d93111` |
| sicht | `v_plausibilitaet` | `sicht_v_plausibilitaet.sql` | 243 | `36ccfdbb617f` |
| sicht | `v_plausibilitaet_0054_zusatz` | `sicht_v_plausibilitaet_0054_zusatz.sql` | 49 | `90993267f053` |
| sicht | `v_plausibilitaet_0064_zusatz` | `sicht_v_plausibilitaet_0064_zusatz.sql` | 55 | `b878b26b0822` |
| sicht | `v_saisonbilanz` | `sicht_v_saisonbilanz.sql` | 116 | `204d569e8774` |
| sicht | `v_schimmel_beobachtung` | `sicht_v_schimmel_beobachtung.sql` | 21 | `8ca4c212a1e9` |
| sicht | `v_schimmel_kurve` | `sicht_v_schimmel_kurve.sql` | 27 | `412bffa8a03d` |
| sicht | `v_schimmel_kurve_anzeige` | `sicht_v_schimmel_kurve_anzeige.sql` | 27 | `59cdbc23ce08` |
| sicht | `v_schimmel_menge` | `sicht_v_schimmel_menge.sql` | 12 | `a793e2b1db03` |
| sicht | `v_schimmel_modell` | `sicht_v_schimmel_modell.sql` | 25 | `437aa2b6d9fa` |
| sicht | `v_schimmel_modell_rechnen` | `sicht_v_schimmel_modell_rechnen.sql` | 298 | `79b98af5e3a4` |
| sicht | `v_schimmel_punkte` | `sicht_v_schimmel_punkte.sql` | 65 | `065939f9d825` |
| sicht | `v_selektionsverdacht` | `sicht_v_selektionsverdacht.sql` | 50 | `7a30f363a232` |
| sicht | `v_sortier_lauf_masse` | `sicht_v_sortier_lauf_masse.sql` | 17 | `8015eef6639c` |
| sicht | `v_ueberfuellung_verkauf` | `sicht_v_ueberfuellung_verkauf.sql` | 104 | `7eda2ee5cd2d` |
| sicht | `v_verarbeitung_alter` | `sicht_v_verarbeitung_alter.sql` | 32 | `9cdd8195a0d2` |
| sicht | `v_verdunstung_messung` | `sicht_v_verdunstung_messung.sql` | 25 | `b1a76ff7285d` |
| sicht | `v_verkauf_lieferung` | `sicht_v_verkauf_lieferung.sql` | 78 | `f90d4413a206` |
| sicht | `v_verlust_je_gruppe` | `sicht_v_verlust_je_gruppe.sql` | 232 | `19cc762671de` |
| sicht | `v_verlust_ranking` | `sicht_v_verlust_ranking.sql` | 13 | `c35e5e5e0528` |
| sicht | `v_wiegung_kennzahl` | `sicht_v_wiegung_kennzahl.sql` | 24 | `dc8d2c116adf` |
| funktion | `anteil_plausibel(p_anteil numeric)` | `funktion_anteil_plausibel.sql` | 8 | `b713654afc3d` |
| funktion | `auftrag_abbrechen(p_auftrag_id bigint, p_grund text)` | `funktion_auftrag_abbrechen.sql` | 20 | `83e316c5d570` |
| funktion | `auftrag_ende_setzen()` | `funktion_auftrag_ende_setzen.sql` | 14 | `6b9358b5b66a` |
| funktion | `auftrag_endgueltig_loeschen(p_auftrag_id bigint)` | `funktion_auftrag_endgueltig_loeschen.sql` | 17 | `668c0b242be9` |
| funktion | `auftrag_manuell_zuordnen(p_lauf_id bigint, p_auftrag_id bigint)` | `funktion_auftrag_manuell_zuordnen.sql` | 15 | `5723c45b5ba6` |
| funktion | `auftrag_schema_setzen()` | `funktion_auftrag_schema_setzen.sql` | 20 | `7eb22d1c282c` |
| funktion | `auftrag_zuordnen(p_lauf_id bigint)` | `funktion_auftrag_zuordnen.sql` | 58 | `4c5bfd486b00` |
| funktion | `ausgang_uebernehmen(p_quelle text, p_quelle_name text, p_datei jsonb, p_zeilen jsonb, p_lieferungen jsonb)` | `funktion_ausgang_uebernehmen.sql` | 137 | `a72004446aec` |
| funktion | `ausschuss_netto_setzen()` | `funktion_ausschuss_netto_setzen.sql` | 22 | `eb4bf3d9682a` |
| funktion | `auswertung_aktualisieren()` | `funktion_auswertung_aktualisieren.sql` | 19 | `d6feecf343d7` |
| funktion | `auswertung_schritt(p_schritt integer)` | `funktion_auswertung_schritt.sql` | 92 | `9c7b60a57a29` |
| funktion | `auswertung_veraltet()` | `funktion_auswertung_veraltet.sql` | 11 | `7f3d8676e89f` |
| funktion | `auswertung_wenn_veraltet()` | `funktion_auswertung_wenn_veraltet.sql` | 17 | `0f65b89e2c62` |
| funktion | `betriebstag(p_ts timestamp with time zone)` | `funktion_betriebstag.sql` | 9 | `72f2b24f93db` |
| funktion | `betriebszone()` | `funktion_betriebszone.sql` | 10 | `e4ae62a8dd6d` |
| funktion | `csv_lauf_speichern(p_charge_nr integer, p_datei_name text, p_roh_datei_ref text, p_roh_pruefsumme text, p_datei_zeit timestamp with time zone, p_datei_zeit_quelle text, p_reinigung jsonb, p_n_roh integer, p_n_overflow integer, p_n_klein integer, p_n_dubletten integer, p_histogramm jsonb)` | `funktion_csv_lauf_speichern.sql` | 31 | `84c141856917` |
| funktion | `demo_daten_entfernen()` | `funktion_demo_daten_entfernen.sql` | 48 | `0d8c730000f0` |
| funktion | `demo_daten_laden()` | `funktion_demo_daten_laden.sql` | 709 | `5ed59af20df4` |
| funktion | `handle_new_user()` | `funktion_handle_new_user.sql` | 19 | `d6bb36f1b3d9` |
| funktion | `heute()` | `funktion_heute.sql` | 11 | `d3fa4c26d878` |
| funktion | `ist_admin()` | `funktion_ist_admin.sql` | 9 | `28841ae7fc56` |
| funktion | `ist_aktiv()` | `funktion_ist_aktiv.sql` | 9 | `2a5ddc36d56c` |
| funktion | `ist_beteiligt(p_auftrag_id bigint)` | `funktion_ist_beteiligt.sql` | 12 | `95aee0adffb0` |
| funktion | `klassiere(p_sorte text, p_gewicht_g integer)` | `funktion_klassiere_c6e3e4.sql` | 8 | `8bd2c3e817cb` |
| funktion | `klassiere(p_schema_id bigint, p_gewicht_g integer)` | `funktion_klassiere_9c91e4.sql` | 28 | `104541afa2ad` |
| funktion | `korrekturfenster()` | `funktion_korrekturfenster.sql` | 6 | `a33130efd7a2` |
| funktion | `lauf_neu_klassieren(p_lauf_id bigint)` | `funktion_lauf_neu_klassieren.sql` | 40 | `9d13bc8cde98` |
| funktion | `lieferung_import_zeilen_verbinden(p_quelle text)` | `funktion_lieferung_import_zeilen_verbinden.sql` | 28 | `d3e888d16f97` |
| funktion | `palox_letzter_stand(p_station station)` | `funktion_palox_letzter_stand.sql` | 13 | `c2f2acd70a69` |
| funktion | `palox_station(p_station station)` | `funktion_palox_station.sql` | 10 | `19568b3a25f2` |
| funktion | `palox_tara_kg()` | `funktion_palox_tara_kg.sql` | 9 | `ddd9f78abba6` |
| funktion | `rolle_schuetzen()` | `funktion_rolle_schuetzen.sql` | 16 | `2cc07223e203` |
| funktion | `schema_stand()` | `funktion_schema_stand.sql` | 7 | `73de89418201` |
| funktion | `schimmel_netto_setzen()` | `funktion_schimmel_netto_setzen.sql` | 27 | `fdf47d6f2ba4` |
| funktion | `schimmelanteil(p_lagertage numeric, p_szenario text)` | `funktion_schimmelanteil.sql` | 25 | `0829ff1cac63` |
| funktion | `sockel_anteil()` | `funktion_sockel_anteil.sql` | 8 | `06e050d4c19f` |
| funktion | `sortierschema_festlegen(p_sorte text, p_kaeufer text, p_art text, p_baender jsonb, p_soll numeric, p_bemerkung text)` | `funktion_sortierschema_festlegen.sql` | 88 | `d7291caebdf3` |
| funktion | `sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date)` | `funktion_sortierschema_fuer_534298.sql` | 8 | `a91e1a0a5364` |
| funktion | `sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date, p_art text)` | `funktion_sortierschema_fuer_cf8685.sql` | 21 | `da05b0b60b68` |
| funktion | `stichtag()` | `funktion_stichtag.sql` | 10 | `ef7cfa33df89` |
| funktion | `t_quantil_95(p_df integer)` | `funktion_t_quantil_95.sql` | 15 | `9b6deb08ab1a` |
| funktion | `verlust_ranking(p_sorte text, p_schlag text, p_charge integer)` | `funktion_verlust_ranking.sql` | 20 | `0e542777ee1d` |
| funktion | `zahl(p_wert numeric, p_stellen integer, p_grenze numeric)` | `funktion_zahl_468772.sql` | 10 | `f8fb4db66e81` |
| funktion | `zahl(p_wert double precision, p_stellen integer, p_grenze numeric)` | `funktion_zahl_89123b.sql` | 7 | `e045c3c26a58` |
