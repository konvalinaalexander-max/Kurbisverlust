# Rohdaten der Saison

_Abzug vom 2026-10-04. Von `pruefstand/betrieb_abzug.mjs` geschrieben; nicht von Hand ändern._

Je Tabelle die Zeilen mit den Spalten aus `ROHTABELLEN` (`pruefstand/durchgang_pruefungen.mjs`) — ohne Kundennamen, Preise, freie Texte und Personen. Für den Plausibilitätsdurchgang (`DURCHGANG.md`) und für jede Runde, die eine Zahl nachrechnen will.

| Tabelle | Zeilen | Spalten |
|---|---|---|
| charge | 42 | nr, sorte, schlag, saison, ernte_abgeschlossen_ts |
| palette | 1708 | id, charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id, quelle |
| auftrag | 33 | id, weg, station, charge_nr, start_ts, ende_ts, status, abgebrochen_ts, ist_fax, kaliber_idx, kistensystem, soll_kg_pro_kiste, stueck_je_kiste, paletten_gesamt, fertige_paletten_gesamt, palox_unbekannt, tage_seit_waschen, geplante_paletten |
| auftrag_palette | 145 | id, auftrag_id, palette_id, eingangsdatum, brutto_zettel_kg, sortierdatum, kisten, gebindeart, wiegung_id, ts |
| auftrag_gebinde | 0 | id, auftrag_id, kaliber_idx, anzahl, sortierdatum, datum_fehlt, ts |
| schimmel_messung | 66 | id, auftrag_id, kg, palox_stand_kg, palox_geleert, palox_nach_leeren, brutto_kg, kisten, gebindeart, mit_palette, gemessen, ts |
| ausschuss_messung | 20 | id, auftrag_id, art, kg, brutto_kg, kisten, gebindeart, mit_palette, gemessen, ts |
| verdunstung_wiegung | 42 | id, auftrag_id, charge_nr, palette_id, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, sichtbar_schimmel, gemessen, wiege_ts, kuerbisse_pro_kiste, faul_kg |
| ausgang_wiegung | 39 | id, auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, kuerbisse_pro_kiste, kaliber_idx, voll, gemessen, ts |
| kontrollpalette | 0 | id, charge_nr, palette_id, kennzeichen, angelegt_ts, beendet_ts, beendet_grund, eingangsdatum, brutto_eingang_kg |
| kontrollpalette_wiegung | 0 | id, kontrollpalette_id, brutto_kg, kisten, gebindeart, sichtbar_schimmel, wiege_ts |
| lieferung | 772 | id, datum, charge_nr, sorte, kg, kisten, gebindeart, ziel, ts |
| sortier_lauf | 12 | id, charge_nr, auftrag_id, datei_zeit, n_roh, n_overflow, n_klein, n_dubletten, n_gueltig, art, sortiertag, sortiertag_quelle |
| gebinde | 6 | art, tara_kg_pro_kiste, tara_kg_palette |
| auswertung_stand | 1 | id, geaendert_ts, berechnet_ts, dauer_ms |

