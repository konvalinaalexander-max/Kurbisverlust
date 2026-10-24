import { useCallback, useEffect, useState } from 'react'
import type { GruppePlan, GruppeRang, KundePlan } from './artikel'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { SCHEMA_ERWARTET, datenbankVeraltet } from '../lib/version'
import type { Datenlage, Hochrechnung, Massenbilanz } from '../lib/typen'
import { heute as heuteOrtszeit, zeitpunkt } from '../lib/format'
import { anforderungOffen, bauZustand, istAktuell, rechnetGerade, zeitplanZustand, ANFORDERUNG_HOECHSTENS_MIN, RECHNEN_HOECHSTENS_MIN, type ZeitplanZustand } from '../lib/zeitplan'

/* =========================================================================
   Die Auswertung für den Betriebsleiter — ein Datenstand für alle Reiter.

   Seit 0061 liest die App nur gespeicherte Ergebnisse (erg_*): kleine,
   indizierte Tabellen, die die Datenbank in fünf Schritten füllt. Nichts,
   was hier geladen wird, rechnet beim Laden — deshalb kann kein Reiter mehr
   in ein Zeitlimit laufen. Ist der Stand veraltet, ruft die App die fünf
   Schritte nacheinander (jeder für sich kurz genug für eine Verbindung) und
   zeigt dabei, wo sie steht. Scheitert ein Schritt, bleibt der letzte
   gespeicherte Stand stehen — mit dem Hinweis, welcher Schritt fehlt.
   ========================================================================= */

/** 0106: der erwartete Palox-Anteil je Sorte und Station — womit die Kaskade
 *  für liegende Ware rechnet. ebene/quelle sagen, welche Stufe gilt (Sorte,
 *  vier Wochen → Sorte, Saison → alle Sorten); geliehen = aus allen Sorten. */
/**
 * Je Sorte und Station (erg_palox_erwartung, seit 0111): `anteil` ist der
 * Grundausschuss — das massegewichtete Mittel der Arbeiten (`mittel`), um den
 * Anstieg der Station auf null Lagertage zurückgelegt; `lager_mittel` die
 * mittlere Lagerdauer dahinter, `anstieg_je_woche` der Anstieg, mit dem
 * zurückgelegt wurde (leer: noch keiner messbar; 0: keiner sicher, seit 0113 —
 * dann ist `anteil` das Mittel). Ebene 'sorte' ab drei eigenen Arbeiten,
 * sonst 'alle' (geliehen).
 */
export interface PaloxErwartung {
  sorte: string; station: string; ebene: string; quelle: string
  anteil: number; unten: number; oben: number; n_arbeiten: number; n_chargen: number
  seit: string; bis: string; geliehen: boolean
  mittel: number | null; lager_mittel: number | null; anstieg_je_woche: number | null
}
export interface Schimmelpunkt {
  auftrag_id: number | null; charge_nr: number; sorte: string; lagertage: number
  schimmel_kg: number; basis_jetzt_kg: number; anteil: number | null; plausibel: boolean; quelle: string
  /** 0079: der Betriebstag der Messung. Die Lagerdauer sagt „nach wie vielen
   *  Wochen", der Messtag „ab wann" — zwei Fragen an dieselbe Messung. */
  messtag: string
  /** 0105: welches Auge den Punkt gesehen hat — sortieren, waschen,
   *  waschen_sortieren, lager (Kontrollpalette) — und sein eigener Anteil,
   *  ohne das Dazurechnen des Modells (beim Waschen: der Wasch-Palox allein). */
  station: string
  anteil_station: number | null
  /** … und ob dieser eigene Anteil plausibel ist (nicht der aufgelaufene). */
  plausibel_station: boolean
}
/** 0105: je Station, wie viel in den Palox geht — „Vergleiche nur unter ihresgleichen". */
/**
 * Je Station (v_palox_station, seit 0111): `zuwachs_je_woche` ist der Anstieg
 * des Palox-Anteils je Woche Lagerdauer, innerhalb der Sorten gemessen — leer,
 * solange er nicht messbar ist (fünf Arbeiten in Sorten mit mindestens zwei,
 * drei Wochen Spanne der Lagerdauern), 0, solange er nicht sicher ist (seit
 * 0113: die untere Grenze `anstieg_unten` über 0), nie negativ; `zuwachs_text`
 * sagt dann, warum. `anstieg_roh` mit Band ist, was gemessen wurde; `grund`
 * der Grundausschuss der Station bei null Tagen (ohne Anstieg: das Mittel).
 */
export interface PaloxStation {
  station: string; n_arbeiten: number; n_chargen: number; seit: string; bis: string; tage: number
  anteil_mittel: number | null; anteil_median: number | null; anteil_4w: number | null; n_4w: number
  zuwachs_je_woche: number | null; zuwachs_text: string | null
  anstieg_roh: number | null; anstieg_unten: number | null; anstieg_oben: number | null
  n_paar: number; spanne_tage: number | null
  lager_von: number | null; lager_bis: number | null; lager_mittel: number | null; grund: number | null
}
/**
 * Je Charge (erg_charge, 0061): Eingang gemessen, geliefert gemessen,
 * ausgelagert = die Eingangsmasse hinter den Lieferungen (zurückgerechnet),
 * lager_kg = Eingang − ausgelagert (in Eingangskilo). Alles Gerechnete gilt
 * bis heute: verlust_heute_kg, im_haus_heute_kg, verkaufsfaehig_lager_kg.
 * Keine Zahl hier stammt aus einer gezählten Arbeit.
 */
export interface Bestand {
  charge_nr: number; sorte: string; schlag: string
  eingang_kg: number; lager_kg: number; gegenprobe_wartet_kg: number | null; sortiert_kg: number; gewaschen_kg: number
  ausgelagert_kg: number; alter_lager: number; alter_lager_heute: number; ueberzaehlung_kg: number
  n_paletten: number; n_paletten_mit_netto: number; eingangsdatum_mittel: string | null
  eingang_von: string | null; eingang_bis: string | null; n_eingangstage: number | null
  rest_von: string | null; rest_bis: string | null; n_rest_paletten: number | null; n_rest_kohorten: number | null
  alter_lager_von: number | null; alter_lager_bis: number | null
  geliefert_kg: number; verkaufsfaehig_lager_kg: number | null; n_lieferungen: number
  /** 0061/0062: bis heute — die Teile des Verlusts, was im Haus liegt, was davon anderer Kanal ist.
   *  kanal_ausgelagert_kg ist zu klein/zu gross, hinter den Lieferungen aussortiert — steht im Haus, Teil von im_haus_heute_kg (0101); kanal_im_haus_kg
   *  ist die Erwartung an der Ware, die noch unsortiert liegt.
   *  0064: **null heisst „nicht gemessen"**, nicht null Kilo. Jeder dieser Ströme ist
   *  null, solange sein Koeffizient keine Messung hat; das Kennzeichen daneben sagt,
   *  welcher. Wer hier mit `?? 0` rechnet, macht aus Unwissen eine gemessene Null. */
  verdunstung_heute_kg: number | null; schimmel_heute_kg: number | null
  fax_heute_kg: number | null; fax_erwartet_kg: number | null
  verlust_heute_kg: number | null; kanal_ausgelagert_kg: number | null
  im_haus_heute_kg: number; kanal_im_haus_kg: number | null; heute: string
  verlust_bekannt: boolean; verdunstung_bekannt: boolean; schimmel_bekannt: boolean
  fax_bekannt: boolean; kanal_bekannt: boolean
  /** 0106: der Palox-Anteil, mit dem das Liegende rechnet, und woher er kommt. */
  faul_anteil: number | null; faul_quelle: string | null
}
export interface NaechsteCharge {
  charge_nr: number; sorte: string; schlag: string; lager_kg: number; alter_tage: number
  masse_jetzt_kg: number; verdunstung_14_kg: number | null; schimmel_14_kg: number | null
  prognose_verlust_14_kg: number | null; f_geliehen: boolean; zuwachs_bekannt: boolean
  alter_von: number | null; alter_bis: number | null; n_kohorten: number | null
}
export interface Kohorte {
  charge_nr: number; eingangsdatum: string; n_paletten: number; n_verarbeitet: number; n_rest: number
  netto_je_palette: number | null; rest_kg: number | null; alter_heute: number
  eingang_kg: number | null
}
export interface AusschussBeobachtung {
  weg: string; charge_nr: number; sorte: string; auftrag_id: number | null
  basis_kg: number; klein_kg: number | null; gross_kg: number | null; plausibel: boolean
}
export interface SortenK { sorte: string; mittel: number | null; unten: number | null; oben: number | null; n: number; basis: string }
/** Die Saisonbilanz (erg_bilanz, 0061): alles bis heute, nichts davon Prognose. */
export interface Saisonbilanz {
  heute: string; eingang_kg: number; n_chargen: number
  ausgang_kg: number; verkauf_kg: number; marge_kg: number; entsorgt_kg: number; ausgang_fehler_kg: number
  n_lieferungen: number; letzte_lieferung: string | null; vorlauf_kg: number; geliefert_kg: number; ausgelagert_kg: number
  /** 0064: null heisst „nicht gemessen" — siehe Bestand. */
  verlust_heute_kg: number | null; verlust_unten_kg: number | null; verlust_oben_kg: number | null
  verdunstung_heute_kg: number | null; schimmel_heute_kg: number | null
  fax_heute_kg: number | null; fax_erwartet_kg: number | null
  kanal_ausgelagert_kg: number | null; kanal_unten_kg: number | null; kanal_oben_kg: number | null
  im_haus_heute_kg: number; verkaufsfaehig_heute_kg: number; kanal_im_haus_kg: number | null
  lager_kg: number; gegenprobe_wartet_kg: number | null; ueberzaehlung_kg: number
  fax_durchsatz_kg: number | null; n_fax_arbeiten: number | null
  verlust_bekannt: boolean; verdunstung_bekannt: boolean; schimmel_bekannt: boolean
  fax_bekannt: boolean; kanal_bekannt: boolean
  bilanz_rest_kg: number | null; bilanz_rest_anteil: number | null; ausgang_deckung: number | null; befund: string
}
/** 0091: der Kommentar zur Ware einer Arbeit — geschrieben oder mitgeschrieben. */
/** 0094: `text` ist die Kurzfassung (nur gelesene Kommentare kommen hier an), `roh` das Gesagte. */
export interface Kommentar { auftrag_id: number; charge_nr: number; text: string; mit_aufnahme: boolean; ts: string; roh: string | null; n: number }
export interface Befund { art: string; auftrag_id: number | null; charge_nr: number; sorte: string; start_ts: string | null; befund: string; rat: string }
export interface Wiegung {
  id: number; auftrag_id: number | null; charge_nr: number; sorte: string; lagertage: number; wiege_ts: string
  netto_damals_kg: number | null; netto_jetzt_kg: number | null; kg_pro_kiste: number | null
  kg_pro_kuerbis: number | null; verdunstung_kg: number | null; sichtbar_schimmel: boolean
  rate_pro_tag: number | null; verwendbar: boolean
  /** 0089: unter der Grenze verdunstung_rate_max_pro_tag? Und wenn die
   *  Wägung nicht zählt: warum nicht — in Worten. */
  plausibel: boolean; grund: string | null
}
export interface VerarbeitungAlter {
  auftrag_id: number; charge_nr: number; sorte: string; schlag: string; station: string; weg: string
  tag: string; n_paletten: number; alter_verarbeitet: number; alter_charge: number | null; differenz: number | null
}
export interface Durchsatz {
  auftrag_id: number; charge_nr: number; sorte: string; station: string; weg: string; ist_fax: boolean
  start_ts: string; ende_ts: string; dauer_h: number; masse_kg: number | null; masse_quelle: string | null
  n_paletten: number; kg_pro_h: number | null; n_teilnehmer: number
}
/**
 * Die verschenkte Marge je Wägung (erg_marge_wiegung, 0078) — ohne
 * Verkaufsdatei: je Sorte und Kistensystem der Durchschnitt der gewogenen
 * vollen fertigen Paletten. „Kiste ab x kg": Ist gegen Soll je Kiste.
 * „x Stück je Kaliber": Gramm je Kürbis gegen die Mitte des Bands.
 */
/** 0086: dieselbe Marge, eine Ebene feiner — je Charge. */
export interface MargeCharge extends MargeWiegung { charge_nr: number; schlag: string }

export interface MargeWiegung {
  sorte: string; kistensystem: 'kiste_ab' | 'stueck'
  soll_kg_pro_kiste: number | null; kaliber_idx: number | null; stueck_je_kiste: number | null
  band_mittel_g: number | null
  n_wiegungen: number; kisten: number
  kg_je_kiste: number | null; sd_je_kiste: number | null; zuviel_je_kiste: number | null
  g_je_kuerbis: number | null; g_ueber_bandmitte: number | null
  von: string | null; bis: string | null
  /** 0097: die Grenzen des Bandes aus der Fassung des Auftrags — derselbe Index
   *  kann in zwei Fassungen zwei Bänder sein; und wie viele der Wägungen voll waren. */
  band_von_g: number | null; band_bis_g: number | null; n_voll: number
}

/**
 * Das Lager nach Kaliber (lager_kaliber(h), 0078/0079): die verkaufsfähige
 * Masse der Kaskade, aufgeteilt auf die Kaliberbänder der Sorte — jeder
 * Kürbis der Sortier-CSV um die gemessene Verdunstung geschrumpft und neu
 * ins Band gelegt. `kaliber_idx` −1 heisst „unter das kleinste Band
 * gefallen": laut Rechnung verkaufsfähig, laut Band nicht mehr.
 * `basis` sagt, woher die Verteilung kommt (eigene CSV, die der Sorte,
 * keine). Die Summe über die Bänder ist verkaufsfaehig_kg.
 */
export interface LagerKaliber {
  gruppe: 'charge' | 'sorte'; schluessel: string; sorte: string; h: number; datum: string
  kaliber_idx: number | null; band_von: number | null; band_bis: number | null
  kg: number | null; anteil: number | null; basis: 'charge' | 'sorte' | 'keine' | 'gemischt'
  n_kuerbis: number | null; verkaufsfaehig_kg: number; lager_kg: number; n_chargen: number
  /** 0111: 'unter' (zu klein, kaliber_idx −1), 'kaliber' (die Bänder), 'ueber' (zu gross, −2). */
  klasse: 'unter' | 'kaliber' | 'ueber'
  klein_kg: number | null; gross_kg: number | null
  /** Der Teil des kleinsten Bandes, der seit der Sortierung darunter geschrumpft ist (zur Auskunft). */
  geschrumpft_kg: number | null
}

/**
 * Demeter oder Knospe je Charge (v_charge_label) — und woher. Seit 0113 nach
 * der Regel des Betriebs: einmal als Demeter geliefert ist Demeter, sonst
 * Knospe; `quelle` Stammdaten · Perigon · Produzent · angenommen;
 * `n_widerspruch` Zeilen, die als Demeter verkauft, aber als Knospe
 * geliefert wurden — zum Prüfen.
 */
export interface ChargeLabel {
  charge_nr: number; label: 'D' | 'K' | null; quelle: string | null; gemischt: boolean; n_d: number; n_k: number
  n_widerspruch?: number
}
/** Die Artikelgruppe je Sorte (v_sorte_artikelgruppe, 0112) — und woher. */
export interface SorteGruppe { sorte: string; artikelgruppe: string | null; quelle: string | null; gruppe_verkauft: string | null }
/** Was gross und klein je Artikelgruppe heisst (artikel_kaliber, 0112). */
export interface ArtikelKaliber { gruppe: string; groesse: string; von_g: number; bis_g: number; stueck_je_kiste: number | null; bemerkung: string | null }
/**
 * Das Verkaufsfähige am Stichtag je Charge und Artikel (artikel_lager_charge,
 * 0113): dieselbe Masse wie lager_kaliber(h), nach den Kalibern des Artikels
 * geteilt (klein, gross, stueck); 'darunter'/'darueber'/'dazwischen' passen in
 * kein Artikelkaliber, 'lose' heisst die Gruppe hat keine Kaliber, 'ohne
 * Verteilung' keine Sortier-CSV. Die App zählt selbst zusammen
 * (src/auswertung/artikel.ts); artikel_lager(h) in der Datenbank tut dasselbe
 * für die Prüfblöcke.
 */
export interface ArtikelLagerCharge {
  charge_nr: number; sorte: string; artikelgruppe: string | null; label: 'D' | 'K' | null; groesse: string
  von_g: number | null; bis_g: number | null; stueck_je_kiste: number | null
  kg: number; stueck: number | null; kisten: number | null; g_mittel: number | null; h: number; datum: string
}
/** Geliefert je Kunde, Saison, Tag und Artikel (v_kunde_tag, 0112). */
export interface KundeTag {
  kunde: string; saison: number; datum: string; gruppe: string | null; groesse: string; label: string | null
  /** Runde AR (0115): leer, wenn keine Position des Tages eine bekannte Masse hat. */
  kg: number | null; positionen: number
  /** 0115: Stück, deren Masse Perigon nicht hergibt (kein Stückgewicht) — nicht in kg. */
  stueck_ohne_gewicht: number | null; positionen_ohne_gewicht: number | null
}

/** Runde AS (0116): die Gruppe eines Kunden, vom Betriebsleiter gesetzt (kunde_gruppe). */
export interface KundeGruppe { kunde: string; gruppe: string }
/** Was beim Durchsehen der Perigon-Zeilen auffällt (v_perigon_pruefung, 0116) — seit 0126 abgelöst durch PerigonBefund. */
export interface PerigonPruefung {
  art: string; quelle: string; pos_id: number; datum: string; kunde: string | null; artikel: string; charge_nr: number | null; kg: number | null; befund: string
}

/** 0126: die Arten eines Perigon-Falls (v_perigon_befund) — je Position oder je Chargenzeile. */
export type PerigonArt = 'menge_null' | 'zu_viel' | 'rest' | 'keine_nummer' | 'ohne_gewicht' | 'ruecknahme' | 'masse_abweichung' | 'label_name'
  | 'nachholen' | 'mehrdeutig' | 'unbekannt' | 'artikel_sorte' | 'demeter_knospe' | 'mix' | 'vor_eingang'
/** 0126: wo ein Fall behoben wird — in Perigon, im Chargenregister, durch neues Einlesen, bei der Firma, oder gar nicht. */
export type PerigonWo = 'perigon' | 'stammdaten' | 'einlesen' | 'firma' | 'nichts'

/**
 * 0126: ein Fall einer Perigon-Position (v_perigon_befund). schluessel bleibt
 * von Rechnen zu Rechnen gleich (art:quelle:pos_id[:nummer:lauf]) — an ihm
 * hängen Vermerk und Spur. Die Zahlen der Datei: menge (Spalte Q), Gewicht je
 * Artikel (AE), kg_position = Q × AE, kg_zugeteilt = Σ S × AE der
 * Chargenzeilen; kg_rechnung: was die App daraus an Lieferungen hat. kg ist,
 * worum es geht — leer heisst unbekannt, nie 0.
 */
export interface PerigonBefund {
  schluessel: string; art: PerigonArt; schwere: 'rot' | 'gelb' | 'info'
  quelle: string; pos_id: number; datum: string; kunde: string | null; artikel: string; einheit: string | null
  menge: number | null; gewicht_je_artikel: number | null; preisgruppe: string | null; liefer_label: string | null
  kg_position: number | null; kg_zugeteilt: number | null; kg_rechnung: number | null; kg_ohne_charge: number | null; kg: number | null
  nummern: string | null; nummer: string | null; lauf_nr: number | null; charge_nr: number | null; sorte: string | null
  n_zeilen: number; satz: string; tun: string; wo: PerigonWo; eingelesen: string | null
}

/** 0126: was je Firma eingelesen ist (v_perigon_stand). */
export interface PerigonStand {
  quelle: string; name: string; zeilen: number; positionen: number; von: string | null; bis: string | null
  zuletzt_geladen: string | null; letzte_datei: string | null; letzte_bis: string | null; dateien: number
  ohne_roh: number; kg: number | null; kg_ohne_charge: number | null; faelle: number
}

/** 0126: wie es um einen Fall steht — der Betriebsleiter vermerkt, die App merkt sich, seit wann sie ihn sieht. */
export type VermerkStand = 'offen' | 'in_abklaerung' | 'erledigt' | 'kein_fehler'
export interface PerigonVerlauf {
  schluessel: string; ebene: 'zeile' | 'charge' | null; art: string | null
  erst_gesehen: string | null; zuletzt_gesehen: string | null; weg_seit: string | null
  schnappschuss: Record<string, unknown> | null
  stand: VermerkStand; notiz: string | null; vermerk_ts: string | null; vermerk_von: string | null; n_vermerke: number
}
export interface PerigonVermerk {
  id: number; schluessel: string; stand: VermerkStand; notiz: string | null; schnappschuss: Record<string, unknown> | null; wer: string | null; ts: string
}

/**
 * Was im Lager liegt, Schritt für Schritt, je Charge heute (v_lager_ausweis,
 * 0121): eingang_kg (auf den Paletten, die noch liegen, wie eingegangen) −
 * verdunstet − faul (Palox, ohne Hagel) − unique (Hagel, als Knospe verkauft)
 * − zu klein − zu gross (Sortiermaschine) − Faules beim Abpacken =
 * verkaufsfaehig_kg; davon marge_kg Überfüllung, verrechenbar_kg der Rest.
 * 0123: verkaufbar_kg ist, was wir als Artikel tatsächlich verkaufen können —
 * verkaufsfaehig_kg ohne, was in kein Artikelgewicht passt, und ohne die
 * Überfüllung darauf, mit Unique; verkaufbar_offen sagt, was dafür fehlt (dann
 * ist es eine obere Schranke). Leer heisst unbekannt (eine Rate nicht
 * gemessen), nie 0.
 */
export interface LagerAusweis {
  charge_nr: number; sorte: string; schlag: string; paletten: number | null
  eingang_kg: number | null; alter_tage: number | null
  verdunstet_kg: number | null; verdunstet_je_tag_kg: number | null; faul_kg: number | null
  unique_kg: number | null; hagel_anteil: number | null
  zu_klein_kg: number | null; zu_gross_kg: number | null; fax_kg: number | null; verkaufsfaehig_kg: number | null
  marge_anteil: number | null; marge_quelle: string; marge_kg: number | null; verrechenbar_kg: number | null
  hagel_bis_heute_kg: number | null
  r_bekannt: boolean; f_bekannt: boolean; kanal_bekannt: boolean; fax_bekannt: boolean
  keinen_artikel_kg: number | null; groesse_offen_kg: number | null; ueberfuellung_kg: number | null
  verkaufbar_kg: number | null; verkaufbar_offen: string | null
  /** 0124: Ware einer Sorte ohne Artikelgruppe — als was sie verkauft wird, ist offen; nicht abgezogen. */
  gruppe_offen_kg: number | null
}

/**
 * 0125: ein Lieferschein ohne Charge, mit dem Grund (v_lieferung_ohne_charge) — dieselben
 * wie in der Summe je Sorte (v_ohne_charge). quelle/pos_id öffnen die Perigon-Zeile;
 * ohne quelle ist er von Hand erfasst.
 */
export interface LieferungOhneCharge {
  id: number; datum: string; sorte: string | null; kunde: string | null; kg: number
  quelle: string | null; pos_id: number | null; artikel: string | null; nummer: string | null
  grund: OhneChargeGrund; satz: string; tun: string
}
export type OhneChargeGrund = 'von_hand' | 'ohne_zeile' | 'nachholen' | 'mehrdeutig' | 'unbekannt' | 'keine_nummer' | 'menge_null' | 'rest'

/** Was zwischen Perigon, Erntejournal und Lager nicht zusammenpasst (v_ungereimtheit, 0121; 0122: nachgeordnet, stammdaten). */
export interface UngereimtZeile {
  art: 'ohne_eingang' | 'vor_eingang' | 'ueberzaehlung' | 'ohne_charge' | 'umgebucht' | 'vorschlag' | 'nachgeordnet' | 'stammdaten'
  charge_nr: number | null; sorte: string | null; schlag: string | null
  kg: number | null; n: number; von: string | null; bis: string | null
  mehr: Record<string, unknown> | null
}

/**
 * Der Weg der Ware je Charge (v_charge_spur, 0122): herein laut Erntejournal
 * (journal_*: die Charge, die das Journal nennt) und wie die App jetzt zählt
 * (paletten, eingang_kg); was umgebucht oder vorgeschlagen ist (weg: von hier
 * weg, her: hierher); bearbeitet in der Halle; hinaus laut Perigon; was laut
 * App noch da ist.
 */
export interface ChargeSpur {
  charge_nr: number; schlag: string; sorte: string; artikelgruppe: string | null
  journal_paletten: number; journal_kg: number | null; journal_von: string | null; journal_bis: string | null
  paletten: number; eingang_kg: number | null
  weg: SpurZuordnung[] | null; her: SpurZuordnung[] | null
  arbeiten: number; arbeit_von: string | null; arbeit_bis: string | null
  arbeit_liste: { id: number; datum: string; station: string; zettel: number }[] | null
  lieferscheine: number; geliefert_kg: number | null; lief_von: string | null; lief_bis: string | null
  nach_artikel: { gruppe: string; kg: number }[] | null
  nachgeordnet: { weg: 'nummer' | 'produzent'; n: number; kg: number }[] | null
  rest_paletten: number | null
}
export interface SpurZuordnung { charge_nr: number; stand: 'angewandt' | 'vorschlag'; paletten: number; kg: number }

/** Dieselben Kürbisse in 50-Gramm-Stufen (kaliber_glocke(h), 0079). */
export interface KaliberGlocke {
  gruppe: 'charge' | 'sorte'; schluessel: string; sorte: string; h: number; datum: string
  stufe_g: number; n_kuerbis: number | null; masse_kg: number | null; anteil: number | null
  basis: 'charge' | 'sorte' | 'gemischt'; n_chargen: number
}

export interface Datenqualitaet {
  paletten_gezaehlt: number; paletten_mit_datum: number; arbeiten_fertig: number
  arbeiten_mit_ablesung: number; arbeiten_mit_zwei_ablesungen: number; arbeiten_mit_antwort: number
  ausschuss_messungen: number; ausschuss_gewogen: number; lagerkontrollen: number
  sortierlaeufe: number; sortierlaeufe_zugeordnet: number; sortier_arbeiten: number; sortier_arbeiten_mit_kisten: number
  wasch_arbeiten: number; wasch_arbeiten_mit_kisten: number
  fax_arbeiten: number; fax_arbeiten_mit_kisten: number; fax_arbeiten_mit_faulem: number
  ws_paletten_gezaehlt: number; ws_paletten_mit_zettelgewicht: number
  arbeiten_nach_waschen: number; arbeiten_mit_kistensystem: number
  wasch_kisten_gezaehlt: number; wasch_kisten_mit_sortierdatum: number; arbeiten_mit_palox_unbekannt: number
  eingangspaletten: number; eingangspaletten_mit_kisten: number
  arbeiten_alter_gemessen: number
}
export interface AusgangKennzahl {
  id: number; auftrag_id: number; charge_nr: number; sorte: string; schlag: string; ts: string
  kisten: number; kg_pro_kiste: number | null; kg_pro_kuerbis: number | null
  soll_kg_pro_kiste: number | null; ueberfuellung_je_kiste: number | null; ueberfuellung_kg: number | null
  kistensystem: string | null; kaliber_idx: number | null; stueck_je_kiste: number | null
  erwartet_kg_pro_kiste: number | null; abweichung_je_kiste: number | null; band_mittel_g: number | null
  /** 0089: eine volle Palette? Seit 0097 zählt jede Palette je Kiste; voll steht dabei. */
  voll: boolean
  /** 0097: die Grenzen des Bandes aus der Fassung des Auftrags. */
  band_von_g?: number | null; band_bis_g?: number | null
}
/**
 * Der Verlauf je Woche (erg_verlauf, 0061/0071): Eingang und Ausgang
 * kumuliert (gemessen), der Verlust kumuliert (gerechnet, bis heute), danach
 * als Prognose (prognose = true). Seit 0071 je Gruppe statt nur je Sorte —
 * gesamt, Sorte, Schlag, Charge — und mit der liegenden Ware: lager_kg ist
 * die Eingangsware, die an diesem Stichtag noch nicht ausgeliefert war,
 * verkaufsfaehig_kg davon der verkaufsfähige Teil. Der Verlust ist der
 * Abstand zwischen beiden Linien.
 */
export interface Verlaufswoche {
  woche: string; bis: string; prognose: boolean
  gruppe: Gruppe; schluessel: string
  eingang_kum_kg: number; ausgang_kum_kg: number; verdunstung_kum_kg: number
  schimmel_kum_kg: number
  fax_kum_kg: number; verlust_kum_kg: number; im_haus_kg: number
  lager_kg: number; verkaufsfaehig_kg: number; kanal_kg: number; fax_lager_kg: number
  /** 0101: zu klein/zu gross hinter den Lieferungen — aussortiert, steht im Haus (Teil von im_haus_kg). */
  aussortiert_kg: number
}

/**
 * Die Prognose (erg_prognose, 0071): dieselbe Kaskade wie überall, nur bei
 * `alter + h` ausgewertet. h = 0 ist heute — dort steht auf den Rappen die
 * Zahl der Saisonbilanz. Die Horizonte gehen in Wochenschritten bis zum
 * Saisonende; 7, 14 und 28 Tage sind immer dabei.
 *
 * `lager_kg` ist über alle Horizonte dieselbe Zahl: Was liegt, liegt. Es
 * ändert sich nur, wie viel davon noch verkaufsfähig ist — und genau das
 * ist `verkaufsfaehig_anteil`. Ist ein Koeffizient nicht gemessen, bleibt
 * der Anteil leer (leer ist nicht null), die Massen sind dann eine obere
 * Schranke.
 */
export interface Prognose {
  gruppe: Gruppe; schluessel: string; h: number; datum: string
  n_chargen: number; n_kohorten: number
  lager_kg: number; verdunstet_kg: number; faul_kg: number
  kanal_kg: number; fax_kg: number; verkaufsfaehig_kg: number; gute_ware_kg: number
  /** 0111: kanal_kg getrennt — zu klein und zu gross. */
  klein_kg: number; gross_kg: number
  verlust_wasser_kg: number; verlust_faeulnis_kg: number; verlust_verkaufsfaehig_kg: number
  verkaufsfaehig_anteil: number | null
  verkaufsfaehig_unten_kg: number | null; verkaufsfaehig_oben_kg: number | null
  verkaufsfaehig_je_tag_kg: number | null; verdunstet_je_tag_kg: number | null; faul_je_tag_kg: number | null
  r_bekannt: boolean; f_bekannt: boolean
  kanal_bekannt: boolean; fax_bekannt: boolean; vollstaendig: boolean
  /** 0106: f_geliehen — ein Anteil aus allen Sorten; zuwachs_bekannt — die
   *  Prognose schreibt das Faule mit dem Zuwachs der Kennzahl fort. */
  f_geliehen: boolean; zuwachs_bekannt: boolean
  alter_tage: number; alter_von: number; alter_bis: number
}

/**
 * Wohin ging der Kürbis (erg_wohin, 0071): der ganze Eingang je Gruppe
 * aufgeteilt. `rest_kg` und `lager_rest_kg` sind die zwei Identitäten —
 * beide haben den Erwartungswert null, und eine doppelt gezählte Portion
 * bliebe darin stehen.
 */
export interface Wohin {
  gruppe: Gruppe; schluessel: string; n_chargen: number
  eingang_kg: number; ueberzaehlung_kg: number; geliefert_kg: number
  kanal_ausgelagert_kg: number | null; klein_ausgelagert_kg: number | null; gross_ausgelagert_kg: number | null
  verdunstet_ausgelagert_kg: number | null; faul_ausgelagert_kg: number | null
  fax_kg: number | null
  lager_kg: number; lager_gute_ware_kg: number; lager_verkaufsfaehig_kg: number | null
  lager_kanal_kg: number | null; lager_klein_kg: number | null; lager_gross_kg: number | null
  lager_fax_kg: number | null; lager_faul_kg: number | null
  lager_verdunstet_kg: number | null
  rest_kg: number | null; lager_rest_kg: number | null; vollstaendig: boolean
}

/**
 * Die Lieferscheine je Gruppe (v_lieferung_gruppe, 0114): jeder einmal, auch
 * wenn er ohne Chargennummer auf alle Chargen seiner Sorte verteilt ist. Bis
 * 0114 zählte die App die Lieferungen der Chargen zusammen — und die
 * Datenbank jede einmal je Eingangstag: „4'836 Lieferungen" bei 1'133.
 */
export interface LieferungGruppe {
  gruppe: Gruppe; schluessel: string; n_lieferungen: number; n_ohne_charge: number
}

export interface KoeffGebinde { sorte: string; kaliber_idx: number; n: number; kg_je_gebinde: number; sd: number | null; unten: number | null; oben: number | null }
export interface KoeffZeile { was: string; wert: string; n: number; basis: string }
export interface Schema { sorte: string; kaeufer: string | null; art: string; gilt_ab: string; kaliber_baender: [number, number][] | null; verlust_unter: number | null; kanal_ab: number | null }

/** 0095: läuft in der Datenbank ein Zeitplan, der von selbst nachrechnet? */
export interface Zeitplan {
  aktiv: boolean; takt: string | null
  letzterStart: string | null; letzterStatus: string | null; letzteDauerS: number | null; letzteMeldung: string | null
  /** Seit wann gerade gerechnet wird — null, wenn nicht. */
  rechnetSeit: string | null
  /** 0102: wann zuletzt „Neu rechnen" angefordert wurde; sofort: der Sofort-Lauf aus 0102 (seit 0103 nie mehr eingetragen). */
  angefordertTs: string | null
  sofort: boolean
  /** Läuft er wirklich? Eingetragen heisst nicht laufend (src/lib/zeitplan.ts). */
  zustand: ZeitplanZustand
}
export function zeitplanVon(x: unknown): Zeitplan {
  const o = (x && typeof x === 'object' ? x : {}) as Record<string, unknown>
  const s = (k: string) => (typeof o[k] === 'string' ? o[k] as string : null)
  const z = {
    aktiv: o.aktiv === true, takt: s('takt'),
    letzterStart: s('letzter_start'), letzterStatus: s('letzter_status'),
    letzteDauerS: typeof o.letzte_dauer_s === 'number' ? o.letzte_dauer_s : null, letzteMeldung: s('letzte_meldung'),
    rechnetSeit: s('rechnet_seit'),
    angefordertTs: s('angefordert_ts'), sofort: o.sofort === true,
  }
  return { ...z, zustand: zeitplanZustand(z) }
}

export interface Auswertung {
  stand: string | null
  /** 0095: der Zeitplan der Datenbank — und ob dieser Stand veraltet ist, weil
   *  die App ihn dem Zeitplan überlassen hat statt selbst zu rechnen. */
  zeitplan: Zeitplan
  veraltet: boolean
  /** Seit der letzten Rechnung nichts Neues erfasst — die Zahlen sind aktuell, wie alt die Rechnung auch ist. */
  aktuell: boolean
  /** Der Tag, bis zu dem gerechnet ist (heute(), 0061). */
  heute: string
  /** Runde AJ: Das Lagermanagement bekommt seine sechs Ergebnisse zuerst; die
   *  übrigen kommen als zweite Welle nach. Bis dahin false — die anderen
   *  Reiter warten darauf, das Lagermanagement nicht. */
  vollstaendig: boolean
  bilanz: Massenbilanz[]
  lage: Datenlage[]
  befunde: Befund[]
  koeff: KoeffZeile[]
  /** 0106: der erwartete Palox-Anteil je Sorte und Station (seit 0107 gespeichert: erg_palox_erwartung). */
  erwartung: PaloxErwartung[]
  saison: Saisonbilanz | null
  punkte: Schimmelpunkt[]
  /** 0105: die Kennzahl je Station unter dem Diagramm. */
  paloxStationen: PaloxStation[]
  bestand: Bestand[]
  naechste: NaechsteCharge[]
  sorten: { verdunstung: SortenK[]; ausschuss: SortenK[]; nebenkanal: SortenK[] }
  wiegungen: Wiegung[]
  /** Die Marge je Wägung, ohne Verkaufsdatei (0078). */
  margeWiegung: MargeWiegung[]
  margeCharge: MargeCharge[]
  /** 0091: Kommentare zur Ware, je Arbeit — hängen an den Messungen. */
  kommentare: Kommentar[]
  verarbeitung: VerarbeitungAlter[]
  qualitaet: Datenqualitaet | null
  verlauf: Verlaufswoche[]
  /** Die Prognose je Gruppe und Horizont (0071) — h = 0 ist heute. */
  prognose: Prognose[]
  /** Der ganze Eingang je Gruppe aufgeteilt (0071). */
  wohin: Wohin[]
  /** Die Lieferscheine je Gruppe, jeder einmal (0114). */
  lieferungGruppe: LieferungGruppe[]
  /** 0121: was im Lager liegt, Schritt für Schritt, je Charge (erste Welle). */
  ausweis: LagerAusweis[]
  /** 0121: was zwischen Perigon und Lager nicht passt, und die Perigon-Zeilen dazu (zweite Welle). */
  ungereimt: UngereimtZeile[]
  /** 0126: jeder Fall einer Perigon-Position (v_perigon_befund) — vorher v_perigon_pruefung. */
  perigon: PerigonBefund[]
  /** 0126: der Stand je Fall (v_perigon_verlauf) — was vermerkt ist, und seit wann die App ihn sieht. */
  faelleStand: PerigonVerlauf[]
  /** 0122: der Weg der Ware je Charge — herein, bearbeitet, hinaus (zweite Welle, mit ungereimt). */
  spur: ChargeSpur[]
  gebinde: KoeffGebinde[]
  schemata: Schema[]
  kohorten: Kohorte[]
  ausschuss: AusschussBeobachtung[]
  ausgang: AusgangKennzahl[]
  /**
   * Sichten, die sich nicht lesen liessen, und Schritte, die nicht rechneten.
   * Eine davon darf nicht den ganzen Bildschirm kosten: Ihre Zahlen sind dann
   * unbekannt, alles andere steht.
   */
  probleme: Problem[]
}

export interface Problem { sicht: string; meldung: string }

/** Wo die Neuberechnung steht — für den Ladebildschirm. */
export interface Fortschritt { schritt: number; schritte: number; titel: string; fehler?: string }
export const SCHRITTE = ['Rohdaten', 'Arbeiten', 'Kaskade', 'Ergebnis', 'Befunde']

let stand: Auswertung | null = null
let ladeVersprechen: Promise<Auswertung> | null = null
const hoerer = new Set<() => void>()
const fortschrittHoerer = new Set<(f: Fortschritt | null) => void>()
let fortschritt: Fortschritt | null = null
function melden(f: Fortschritt | null) { fortschritt = f; fortschrittHoerer.forEach(h => h(f)) }

/**
 * Die fünf Schritte nacheinander — jeder ein eigener Aufruf, damit keiner
 * ins Zeitlimit läuft. Scheitert einer, bricht die Reihe ab (die folgenden
 * bauen auf ihm auf) und der Fehler steht mit seiner Nummer da.
 */
async function rechnen(): Promise<Problem[]> {
  for (let i = 1; i <= SCHRITTE.length; i++) {
    melden({ schritt: i, schritte: SCHRITTE.length, titel: SCHRITTE[i - 1] })
    const { data, error } = await supabase.rpc('auswertung_schritt', { p_schritt: i })
    if (error) {
      melden(null)
      return [{ sicht: `Neu rechnen, Schritt ${i} von ${SCHRITTE.length} (${SCHRITTE[i - 1]})`, meldung: error.message }]
    }
    // 0100: Rechnet schon jemand (ein anderes Fenster, der Zeitplan), rechnet
    // dieses Fenster nicht mit — es wartet, bis der Stand steht.
    if ((data as { wartet?: boolean } | null)?.wartet) return abwarten('laeuft')
  }
  melden(null)
  return []
}

/**
 * Warten, bis die Datenbank fertig ist — auf eine laufende Rechnung
 * (grund „laeuft": bis rechnet_seit weg ist) oder auf eine Anforderung
 * (grund „angefordert": bis ein Stand steht, der jünger ist als sie).
 * Höchstens so lange, wie ein Lauf dauern darf (0095: 15 Minuten); danach
 * bleibt der letzte Stand stehen, und die Meldung sagt, wo nachzusehen ist.
 * Am 28. September rechneten Fenster, Zeitplan und setup.sql zugleich, und
 * die Datenbank antwortete eine halbe Stunde lang niemandem — darum wartet
 * die App mit einer Anfrage alle fünf Sekunden, statt selbst zu rechnen.
 */
const WARTEN_MS = 10000
async function abwarten(grund: 'laeuft' | 'angefordert', angefordertTs?: string): Promise<Problem[]> {
  melden({ schritt: 0, schritte: SCHRITTE.length, titel: grund })
  // Der Chip soll es sofort sagen — ohne auf das Ende zu warten.
  if (stand) {
    stand = { ...stand, zeitplan: { ...stand.zeitplan, angefordertTs: grund === 'angefordert' ? new Date().toISOString() : stand.zeitplan.angefordertTs } }
    hoerer.forEach(h => h())
  }
  const bis = Date.now() + RECHNEN_HOECHSTENS_MIN * 60 * 1000
  while (Date.now() < bis) {
    await new Promise(r => globalThis.setTimeout(r, WARTEN_MS))
    const { data: st, error } = await supabase.from('auswertung_stand').select('berechnet_ts, geaendert_ts, rechnet_seit, angefordert_ts, fehler_ts, fehler').maybeSingle()
    if (error || !st) continue
    // 0107: Ein gescheiterter Lauf wird nicht wiederholt — also nicht weiter warten, sondern sagen, warum.
    const seit = angefordertTs ?? st.angefordert_ts
    if (grund === 'angefordert' && st.fehler_ts && seit && Date.parse(st.fehler_ts) >= Date.parse(seit)) {
      melden(null)
      return [{ sicht: 'Neu rechnen', meldung: `Die Rechnung ist gescheitert: ${st.fehler ?? 'ohne Meldung'}. Die gezeigten Zahlen sind der letzte Stand; ein neuer Versuch mit „Neu rechnen".` }]
    }
    const fertig = grund === 'angefordert'
      ? !anforderungOffen(st.angefordert_ts, st.berechnet_ts)
      : !rechnetGerade(st.rechnet_seit)
    if (fertig) { melden(null); return [] }
  }
  melden(null)
  return [{ sicht: 'Neu rechnen', meldung: `Nach ${RECHNEN_HOECHSTENS_MIN} Minuten liegt noch kein neuer Stand vor — gezeigt wird der letzte. Unter Betrieb nachsehen, ob der Zeitplan läuft (pg_cron), sonst setup.sql noch einmal einspielen.` }]
}

/**
 * „Neu rechnen" (Runde AG, 0102): kein Rechnen im Browser, sondern eine
 * Anforderung an die Datenbank. Mit Zeitplan (pg_cron) rechnet der Lauf
 * des Zeitplans beim nächsten Tick (jede Minute, 0103) im Hintergrund, und
 * die App wartet auf den neuen Stand. Ohne Zeitplan (Demo, Tests) rechnet
 * die App wie bisher Schritt für Schritt — die Datenbank sagt, welcher Weg.
 */
async function anfordern(): Promise<Problem[]> {
  melden({ schritt: 0, schritte: SCHRITTE.length, titel: 'angefordert' })
  const { data, error } = await supabase.rpc('auswertung_anfordern')
  if (error) {
    melden(null)
    return [{ sicht: 'Neu rechnen (Anforderung)', meldung: error.message }]
  }
  const antwort = data as { weg?: string; hinweis?: string; angefordert_ts?: string } | null
  if (antwort?.weg === 'zeitplan') return abwarten('angefordert', antwort.angefordert_ts)
  // 0107: Nur ohne pg_cron (Demo, Prüfung) rechnet die App selbst. Ist pg_cron
  // da, aber der Zeitplan liess sich nicht eintragen, rechnet sie nicht — die
  // volle Rechnung aus dem Browser war, was die Datenbank am 29.9. lahmlegte.
  if (antwort?.hinweis) {
    melden(null)
    return [{ sicht: 'Neu rechnen', meldung: antwort.hinweis }]
  }
  return rechnen()
}

/** Der Text, an dem useAuswertung den Zustand „wird gebaut" erkennt und von selbst nachlädt. */
export const IM_BAU = 'Die Auswertung wird gerade neu gebaut: Nach dem Einspielen von setup.sql rechnet der Zeitplan sie im Hintergrund. Diese Seite lädt von selbst nach.'
const NACHLADEN_IM_BAU_MS = 30000

async function alles(erzwingen: boolean): Promise<Auswertung> {
  // 0057: Erst fragen, ob die Datenbank die Formeln hat, die diese App
  // voraussetzt. Sonst scheitert die Auswertung an einem alten Stand mit
  // einer rohen Meldung, aus der niemand den Weg heraus lesen kann.
  const version = await supabase.rpc('schema_stand')
  const schemaStand = typeof version.data === 'number' ? version.data : null
  if (version.error || schemaStand === null || schemaStand < SCHEMA_ERWARTET) throw new Error(datenbankVeraltet(schemaStand))

  const [{ data: st }, zp] = await Promise.all([
    supabase.from('auswertung_stand').select('berechnet_ts, geaendert_ts, rechnet_seit, angefordert_ts').maybeSingle(),
    supabase.rpc('auswertung_zeitplan'),
  ])
  const zeitplan = zeitplanVon(zp.data)
  // Runde AG (0102): Öffnen rechnet nie. Die App zeigt den gespeicherten
  // Stand — den, den zuletzt jemand hat rechnen lassen —, und der Chip sagt,
  // ob er aktuell ist. Rechnet gerade jemand (Zeitplan, ein anderes Fenster),
  // wartet die App nicht: useAuswertung lädt nach, sobald der Stand steht.
  // Nur „Neu rechnen" (erzwingen) tut etwas, und auch das ist eine
  // Anforderung an den Zeitplan, kein Rechnen im Browser. Der Betrieb:
  // „Schau einfach, dass nur beim aktiven Neuladen neu geladen wird, und
  // dass die Resultate zwischengespeichert sind." Bis Runde AF rechnete die
  // App beim Öffnen selbst, sobald der Zeitplan nicht als laufend galt — am
  // 28. September rechneten so Fenster, Zeitplan und setup.sql zugleich, und
  // die Datenbank antwortete eine halbe Stunde lang niemandem.
  const rechnetSchon = rechnetGerade(st?.rechnet_seit)
  const probleme: Problem[] = erzwingen ? (rechnetSchon ? await abwarten('laeuft') : await anfordern()) : []
  const { data: st2 } = await supabase.from('auswertung_stand').select('berechnet_ts, geaendert_ts, rechnet_seit, angefordert_ts, fehler_ts, fehler').maybeSingle()
  const aktuell = istAktuell(st2?.berechnet_ts, st2?.geaendert_ts)
  const veraltet = !st2?.berechnet_ts || new Date(st2.geaendert_ts) > new Date(st2.berechnet_ts)
  zeitplan.rechnetSeit = st2?.rechnet_seit ?? zeitplan.rechnetSeit
  zeitplan.angefordertTs = st2?.angefordert_ts ?? zeitplan.angefordertTs
  // Nach setup.sql sind die gespeicherten Ansichten leer, bis der Zeitplan
  // sie gebaut hat („materialized view … has not been populated"). Das ist
  // kein Fehler der Zahlen, sondern ein Zustand: die Seite sagt es und lädt
  // von selbst nach (useAuswertung).
  let imBau = false
  const nichtGebaut = (f: { code?: string; message?: string } | null) =>
    f?.code === '55000' || /has not been populated/i.test(f?.message ?? '')

  // Jede Sicht wird für sich geholt. Scheitert eine, ist *ihre* Zahl unbekannt
  // — der Rest des Bildschirms steht trotzdem.
  const merken = (name: string, fehler: { code?: string; message?: string } | null) => {
    if (nichtGebaut(fehler)) imBau = true
    probleme.push({ sicht: name, meldung: fehler?.message ?? 'unbekannter Fehler' })
  }
  const q = async <T,>(name: string, order?: [string, boolean]): Promise<T[]> => {
    const alle: T[] = []
    for (let von = 0; ; von += SEITE) {
      let s = supabase.from(name).select('*').range(von, von + SEITE - 1)
      if (order) s = s.order(order[0], { ascending: order[1] })
      const r = await s
      if (r.error) { merken(name, r.error); return alle }
      const teil = (r.data ?? []) as T[]
      alle.push(...teil)
      if (teil.length < SEITE) return alle
    }
  }
  const eins = async <T,>(name: string): Promise<T | null> => {
    const r = await supabase.from(name).select('*').maybeSingle()
    if (r.error) { merken(name, r.error); return null }
    return (r.data ?? null) as T | null
  }
  // Runde AJ (Entschlackung, Stufe 1): erst die sechs Ergebnisse, die das
  // Lagermanagement braucht — Bestand, Prognose, Bilanz, Verlauf, Wohin,
  // Auffälligkeiten —, dann der Rest. Die erste Welle steht als Stand mit
  // vollstaendig = false, und das Lagermanagement zeichnet; die anderen
  // Reiter warten, bis die zweite Welle da ist. Was bisher 33 Anfragen vor
  // dem ersten Bild waren, sind jetzt sieben.
  const [pl, sb, hb, vl, pg, wo, lg, aw] = await Promise.all([
    q<Befund>('erg_plausibilitaet'), eins<Saisonbilanz>('erg_bilanz'), q<Bestand>('erg_charge'),
    q<Verlaufswoche>('erg_verlauf', ['woche', true]), q<Prognose>('erg_prognose', ['h', true]), q<Wohin>('erg_wohin'),
    q<LieferungGruppe>('v_lieferung_gruppe'), q<LagerAusweis>('v_lager_ausweis'),
  ])
  // 0108: Ist der Bau gescheitert (fehler_ts nach dem letzten Stand), wartet
  // die Seite nicht auf etwas, das nicht kommt, sondern sagt es. Seit dem
  // 21. Oktober nur, wenn danach nichts mehr angefordert wurde: setup.sql
  // fordert am Ende selbst an, und der Fehler von vorher ist dann Geschichte
  // (bauZustand, src/lib/zeitplan.ts).
  if (imBau) {
    const bau = bauZustand(st2)
    if (bau === 'gescheitert') {
      throw new Error(`Die Auswertung konnte nicht gerechnet werden: ${st2?.fehler ?? 'ohne Meldung'}. Die Datenbank versucht es nicht von selbst wieder — heute Nacht oder mit „Neu rechnen".`)
    }
    if (bau === 'haengt') {
      throw new Error(`Die Auswertung ist seit ${zeitpunkt(st2?.angefordert_ts)} angefordert, aber nach ${ANFORDERUNG_HOECHSTENS_MIN} Minuten noch nicht gebaut — der Zeitplan der Datenbank rechnet nicht. Unter Betrieb nachsehen, ob er läuft (pg_cron), sonst setup.sql noch einmal einspielen.`)
    }
    throw new Error(IM_BAU)
  }
  const heute = sb?.heute ?? hb[0]?.heute ?? heuteOrtszeit()
  const ersteWelle: Auswertung = {
    stand: st2?.berechnet_ts ?? null, heute, zeitplan, veraltet, aktuell, vollstaendig: false,
    bilanz: [], lage: [], befunde: pl, koeff: [], erwartung: [],
    saison: sb, punkte: [], paloxStationen: [], bestand: hb, naechste: [],
    sorten: { verdunstung: [], ausschuss: [], nebenkanal: [] }, wiegungen: [], margeWiegung: [], margeCharge: [], kommentare: [],
    verarbeitung: [], qualitaet: null, verlauf: vl,
    gebinde: [], schemata: [], kohorten: [], ausschuss: [], ausgang: [],
    prognose: pg, wohin: wo, lieferungGruppe: lg, ausweis: aw, ungereimt: [], perigon: [], faelleStand: [], spur: [], probleme,
  }
  if (!erzwingen) { stand = ersteWelle; hoerer.forEach(h => h()) }

  // 0108: erg_kaliber, erg_gewichte und erg_lieferung liest kein Bildschirm —
  // nicht mehr geholt (erg_gewichte war die drittgrösste Antwort). Runde AZ:
  // ebenso erg_verlust (die Ströme mit Bereich — seit Runde AJ las sie kein
  // Reiter mehr) und erg_durchsatz (Messungen → Arbeiten holt es selbst).
  const [b, d, pe, pk, nc, kfv, kfa, kfn, kfu, wk, mw, mc, km, va, dq, kg, ss, ko, ab, ak, ps] = await Promise.all([
    q<Massenbilanz>('erg_massenbilanz'), q<Datenlage>('erg_datenlage'),
    q<PaloxErwartung>('erg_palox_erwartung'),
    q<Schimmelpunkt>('erg_punkte'), q<NaechsteCharge>('erg_naechste_charge'),
    q<SortenK>('erg_koeff_verdunstung'), q<SortenK>('erg_koeff_ausschuss'), q<SortenK>('erg_koeff_nebenkanal'),
    q<{ n: number; kg_pro_kiste: number | null }>('erg_koeff_ueberfuellung'),
    q<Wiegung>('erg_wiegung', ['wiege_ts', false]), q<MargeWiegung>('erg_marge_wiegung'), q<MargeCharge>('erg_marge_charge'), q<Kommentar>('v_arbeit_kommentar'),
    q<VerarbeitungAlter>('erg_verarbeitung_alter', ['tag', true]),
    eins<Datenqualitaet>('erg_datenqualitaet'),
    q<KoeffGebinde>('erg_gebinde'), q<Schema>('sortierschema', ['gilt_ab', false]),
    q<Kohorte>('erg_kohorte', ['eingangsdatum', true]),
    q<AusschussBeobachtung>('erg_ausschuss'),
    q<AusgangKennzahl>('erg_ausgang', ['ts', true]),
    q<PaloxStation>('v_palox_station'),
  ])
  // 0121: was zwischen Perigon und Lager nicht passt — für den Hinweis oben auf jeder Lagerseite.
  // 0122: dazu der Weg der Ware je Charge, damit jede Sache zeigt, wo die Ware herein, durch und hinaus ging.
  // 0126: die Perigon-Fälle je Position (v_perigon_befund) statt v_perigon_pruefung, dazu ihr Stand.
  const [ug, pp, sp, fs] = await Promise.all([q<UngereimtZeile>('v_ungereimtheit'), q<PerigonBefund>('v_perigon_befund', ['datum', false]),
    q<ChargeSpur>('v_charge_spur', ['charge_nr', true]), q<PerigonVerlauf>('v_perigon_verlauf')])
  // 0108: Eine noch ungefüllte Sicht der zweiten Welle steht in probleme
  // (ihre Zahl ist unbekannt, nie 0) — die Seiten zeichnen, was da ist,
  // statt im Ladekreis zu warten. Bis 0108: IM_BAU, und Chargen, Ursachen,
  // Messungen und Ausstehend drehten, bis jemand neu lud.
  // Fax liegt auf Eis (Runde R): erg_fax, erg_fax_wartezeit und erg_koeff_fax
  // bleiben in der Datenbank, aber kein Bildschirm liest sie mehr. Ebenso
  // erg_ueberfuellung und erg_marge — die Marge hängt jetzt an den Wägungen,
  // nicht an der Verkaufsdatei (0078).

  type K = { mittel?: number | null; n: number; basis?: string }
  const mittelwert = (r: K[]) => { const g = r.filter(x => x.mittel != null); return g.length ? g.reduce((a, x) => a + (x.mittel ?? 0), 0) / g.length : null }
  const bestBasis = (r: K[]) => r.find(x => x.basis?.includes('dieser Sorte'))?.basis ?? r.find(x => x.basis && !x.basis.startsWith('keine'))?.basis ?? '—'
  const maxN = (r: K[]) => r.reduce((a, x) => Math.max(a, x.n ?? 0), 0)
  const mv = mittelwert(kfv), ma = mittelwert(kfa), mn = mittelwert(kfn)
  const koeff: KoeffZeile[] = [
    { was: 'Verdunstung je Tag', n: maxN(kfv), basis: bestBasis(kfv), wert: mv === null ? '—' : `${(mv * 100).toFixed(4)} %` },
    { was: 'Zu klein (Tierfutter)', n: maxN(kfa), basis: bestBasis(kfa), wert: ma === null ? '—' : `${(ma * 100).toFixed(2)} %` },
    { was: 'Nebenkanal zu gross', n: maxN(kfn), basis: bestBasis(kfn), wert: mn === null ? '—' : `${(mn * 100).toFixed(2)} %` },
    { was: 'Überfüllung je Kiste', n: kfu[0]?.n ?? 0, basis: 'gewogene fertige Paletten',
      wert: kfu[0]?.kg_pro_kiste == null ? '—' : `${kfu[0].kg_pro_kiste.toFixed(3)} kg` },
  ]
  return {
    ...ersteWelle, vollstaendig: true,
    bilanz: b, lage: d, koeff, erwartung: pe,
    punkte: pk, paloxStationen: ps, naechste: nc,
    sorten: { verdunstung: kfv, ausschuss: kfa, nebenkanal: kfn }, wiegungen: wk, margeWiegung: mw, margeCharge: mc, kommentare: km,
    verarbeitung: va, qualitaet: dq,
    gebinde: kg, schemata: ss, kohorten: ko, ausschuss: ab, ausgang: ak,
    ungereimt: ug, perigon: pp, faelleStand: fs, spur: sp,
  }
}

/**
 * Runde AF: Welche Rate fehlt? Der Betrieb las „der Anteil ist unbekannt,
 * solange eine Rate nicht gemessen ist" und fragte zu Recht: welche. Die
 * Prognose trägt je Gruppe die vier Flaggen; hier werden sie zu Namen.
 */
export function fehlendeRaten(p: Pick<Prognose, 'r_bekannt' | 'f_bekannt' | 'kanal_bekannt' | 'fax_bekannt'> | null | undefined): string[] {
  if (!p) return []
  const f: string[] = []
  if (!p.r_bekannt) f.push('Verdunstung')
  if (!p.f_bekannt) f.push('Palox')
  if (!p.kanal_bekannt) f.push('zu klein / zu gross')
  if (!p.fax_bekannt) f.push('Faules beim Abpacken (Fax)')
  return f
}

export function auswertungLaden(erzwingen = false): Promise<Auswertung> {
  if (stand && !erzwingen) return Promise.resolve(stand)
  if (!ladeVersprechen || erzwingen) {
    // Wird neu gerechnet, sind auch die geholten Stichtage von gestern.
    if (erzwingen) { kaliberJeStichtag.clear(); glockeJeStichtag.clear(); artikelChargeJeStichtag.clear() }
    const v: Promise<Auswertung> = alles(erzwingen)
      .then(a => { stand = a; ladeVersprechen = null; hoerer.forEach(h => h()); return a })
      .catch((f: unknown) => { ladeVersprechen = null; melden(null); throw f })
    ladeVersprechen = v
    return v
  }
  return ladeVersprechen
}


/** Der Datenstand für einen Reiter — geladen, gehalten, auf Wunsch neu gerechnet. */
// Supabase liefert höchstens 1000 Zeilen je Anfrage — die Kaskade je
// Eingangstag und die Gewichtsverteilung haben mehr. Deshalb seitenweise.
const SEITE = 1000

/**
 * Die volle Hochrechnung — jede Charge mal jeder Strom, mit Formel und
 * Koeffizient. Das sind einige Megabyte und eine Sicht, die live rechnet;
 * gebraucht wird sie nur für den CSV-Export unter Messungen. Sie hing bis
 * Runde I am Laden jeder Seite und kostete auf jedem Reiter Zeit, obwohl sie
 * niemand ansah. Jetzt holt sie, wer sie braucht, in dem Moment, in dem er
 * auf „CSV exportieren" drückt.
 */
export async function hochrechnungLaden(): Promise<Hochrechnung[]> {
  const alle: Hochrechnung[] = []
  for (let von = 0; ; von += SEITE) {
    const r = await supabase.from('v_hochrechnung').select('*').range(von, von + SEITE - 1)
    if (r.error) throw new Error(r.error.message)
    const teil = (r.data ?? []) as Hochrechnung[]
    alle.push(...teil)
    if (teil.length < SEITE) return alle
  }
}

/* ---------- Das Lager nach Kaliber: je Stichtag ein Aufruf ----------------- */

/**
 * `lager_kaliber(h)` und `kaliber_glocke(h)` sind Funktionen, keine
 * gespeicherten Sichten: Das Neurechnen liegt bei dreifacher Saison an
 * seiner Zwölf-Sekunden-Grenze, und der Bildschirm braucht ohnehin nur zwei
 * Stichtage — heute und „in X Wochen". Ein Aufruf kostet rund 35 ms; jeder
 * Stichtag wird einmal geholt und behalten, bis neu gerechnet wird.
 */
const kaliberJeStichtag = new Map<number, LagerKaliber[]>()
const glockeJeStichtag = new Map<number, KaliberGlocke[]>()
const artikelChargeJeStichtag = new Map<number, ArtikelLagerCharge[]>()

async function rpcStichtag<T>(fn: string, h: number, halde: Map<number, T[]>): Promise<T[]> {
  const da = halde.get(h)
  if (da) return da
  const r = await supabase.rpc(fn, { p_h: h })
  if (r.error) throw new Error(r.error.message)
  const zeilen = (r.data ?? []) as T[]
  halde.set(h, zeilen)
  return zeilen
}

export const lagerKaliberBei = (h: number) => rpcStichtag<LagerKaliber>('lager_kaliber', h, kaliberJeStichtag)
export const kaliberGlockeBei = (h: number) => rpcStichtag<KaliberGlocke>('kaliber_glocke', h, glockeJeStichtag)
export const artikelLagerChargeBei = (h: number) => rpcStichtag<ArtikelLagerCharge>('artikel_lager_charge', h, artikelChargeJeStichtag)

/** Ein Sortierlauf neben den anderen Läufen derselben Charge (v_lauf_vergleich, 0111, AB-113). */
export interface LaufVergleich {
  charge_nr: number; sorte: string; lauf_id: number; datei_name: string | null
  sortiertag: string; n_laeufe: number; n_kuerbis: number
  mittel_g: number | null; median_g: number | null; q1_g: number | null; q3_g: number | null
  tage_seit_erstem: number; rate_median: number | null; rate_wiegungen: number | null
}

/**
 * Die Sortierläufe der Chargen, die mehr als einmal sortiert wurden — die
 * Gegenprobe der Verdunstung aus den Sortierdateien (Runde AO: „anhand des
 * sortiert CSVs könnte man eigentlich auch die Verdunstung berechnen").
 * Beobachtet, nicht Teil der Rate: Es sind nicht dieselben Kürbisse.
 */
export async function laufVergleich(): Promise<LaufVergleich[]> {
  const { data, error } = await supabase.from('v_lauf_vergleich').select('*').gte('n_laeufe', 2)
    .order('charge_nr').order('sortiertag')
  if (error) throw new Error(error.message)
  const zahl = (v: unknown) => (v === null || v === undefined ? null : Number(v))
  return ((data ?? []) as Record<string, unknown>[]).map(z => ({
    charge_nr: Number(z.charge_nr), sorte: String(z.sorte), lauf_id: Number(z.lauf_id),
    datei_name: (z.datei_name as string | null) ?? null, sortiertag: String(z.sortiertag),
    n_laeufe: Number(z.n_laeufe), n_kuerbis: Number(z.n_kuerbis),
    mittel_g: zahl(z.mittel_g), median_g: zahl(z.median_g), q1_g: zahl(z.q1_g), q3_g: zahl(z.q3_g),
    tage_seit_erstem: Number(z.tage_seit_erstem), rate_median: zahl(z.rate_median), rate_wiegungen: zahl(z.rate_wiegungen),
  }))
}

/**
 * Was „Lagermanagement nach Artikel" ausser der Auswertung braucht (0112): Label je
 * Charge, Gruppe je Sorte, die Artikelkaliber und die Lieferungen je Kunde
 * aller Saisons. Klein bis auf die Kundentage — die kommen seitenweise.
 */
export async function artikelGrundlagen(): Promise<{ labels: ChargeLabel[]; gruppen: SorteGruppe[]; kaliber: ArtikelKaliber[]; kunden: KundeTag[]
                                                    kundeGruppe: KundeGruppe[]; plaene: KundePlan[]
                                                    gruppenRang: GruppeRang[]; gruppenPlaene: GruppePlan[] }> {
  const [l, g, k, kg, kp, gr, gp] = await Promise.all([
    supabase.from('v_charge_label').select('charge_nr, label, quelle, gemischt, n_d, n_k, n_widerspruch'),
    supabase.from('v_sorte_artikelgruppe').select('*'),
    supabase.from('artikel_kaliber').select('gruppe, groesse, von_g, bis_g, stueck_je_kiste, bemerkung'),
    // Runde AS (0116): Kundengruppen und Planmengen. Die Prüfungen der Perigon-Zeilen stehen seit 0126 im Reiter Perigon.
    supabase.from('kunde_gruppe').select('kunde, gruppe'),
    supabase.from('kunde_plan').select('saison, kunde, artikelgruppe, groesse, label, kg'),
    // Runde AT (0117): die Reihenfolge der Gruppen und der Plan einer ganzen Gruppe
    supabase.from('kunde_gruppe_rang').select('gruppe, rang'),
    supabase.from('gruppe_plan').select('saison, gruppe, artikelgruppe, groesse, label, kg'),
  ])
  for (const r of [l, g, k, kg, kp, gr, gp]) if (r.error) throw new Error(r.error.message)
  const kunden: KundeTag[] = []
  for (let von = 0; ; von += SEITE) {
    const r = await supabase.from('v_kunde_tag').select('*').order('datum').range(von, von + SEITE - 1)
    if (r.error) throw new Error(r.error.message)
    const teil = (r.data ?? []) as KundeTag[]
    kunden.push(...teil)
    if (teil.length < SEITE) break
  }
  return { labels: (l.data ?? []) as ChargeLabel[], gruppen: (g.data ?? []) as SorteGruppe[], kaliber: (k.data ?? []) as ArtikelKaliber[], kunden,
           kundeGruppe: (kg.data ?? []) as KundeGruppe[], plaene: (kp.data ?? []) as KundePlan[],
           gruppenRang: (gr.data ?? []) as GruppeRang[], gruppenPlaene: (gp.data ?? []) as GruppePlan[] }
}

/**
 * Den gemerkten Stand vergessen (0080).
 *
 * `stand` hält die gerechnete Auswertung für die ganze Sitzung; jeder Reiter
 * nimmt sie, ohne nachzufragen. Das ist richtig, solange nur dazukommt —
 * aber nicht, wenn jemand die Erfassung leert. Ohne diesen Aufruf stünde
 * nach dem Löschen auf dem Überblick weiter die alte Tonnage, gerechnet aus
 * Zeilen, die es nicht mehr gibt: genau die „Zahlen aus Resten", gegen die
 * der Löschknopf gebaut ist. Wer als Nächstes einen Reiter öffnet, holt sie
 * danach frisch.
 */
export function auswertungVergessen() {
  stand = null
  ladeVersprechen = null
  kaliberJeStichtag.clear()
  glockeJeStichtag.clear()
  artikelChargeJeStichtag.clear()
}

/**
 * Ein Stichtag für einen Bildschirm: die Zeilen, ob gerade geladen wird, und
 * der Fehler, falls einer kam. Während des Ladens bleiben die zuletzt
 * geholten Zeilen stehen (der Bildschirm zeigt sie blass) — ein Sprung auf
 * leer bei jedem Tastendruck wäre unruhiger als eine alte Zahl.
 */
export function useStichtag<T>(holen: (h: number) => Promise<T[]>, h: number) {
  const [zeilen, setZeilen] = useState<T[]>([])
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)
  useEffect(() => {
    let gilt = true
    setLaedt(true)
    holen(h)
      .then(z => { if (gilt) { setZeilen(z); setFehler(null) } })
      .catch((f: unknown) => { if (gilt) setFehler(fehlerText(f)) })
      .finally(() => { if (gilt) setLaedt(false) })
    return () => { gilt = false }
  }, [holen, h])
  return { zeilen, laedt, fehler }
}

export function useAuswertung() {
  const [daten, setDaten] = useState<Auswertung | null>(stand)
  const [laedt, setLaedt] = useState(!stand)
  const [fehler, setFehler] = useState<string | null>(null)
  const [schritt, setSchritt] = useState<Fortschritt | null>(fortschritt)
  const laden = useCallback(async (erzwingen = false) => {
    setLaedt(true); setFehler(null)
    try { setDaten(await auswertungLaden(erzwingen)) }
    catch (f) { setFehler(fehlerText(f)) }
    finally { setLaedt(false) }
  }, [])
  useEffect(() => {
    const h = () => setDaten(stand)
    const fh = (f: Fortschritt | null) => setSchritt(f)
    hoerer.add(h); fortschrittHoerer.add(fh)
    if (!stand) void laden()
    return () => { hoerer.delete(h); fortschrittHoerer.delete(fh) }
  }, [laden])
  // Runde AG: „wird gebaut" ist ein Zustand, kein Fehler — alle 15 Sekunden nachsehen.
  useEffect(() => {
    if (fehler !== IM_BAU) return
    const t = window.setTimeout(() => void laden(), NACHLADEN_IM_BAU_MS)
    return () => window.clearTimeout(t)
  }, [fehler, laden])
  // 0107: Keine Nachschau-Schleife mehr. Bis 0107 fragte das Dashboard alle
  // halbe Minute nach dem Stand und lud neue Zahlen von selbst nach — Teil des
  // „automatischen Neuladens", das der Betrieb am 29.9. nicht mehr wollte. Die
  // Zahlen stehen, bis jemand „Neu rechnen" drückt oder die Seite neu öffnet.
  return { daten, laedt, fehler, fortschritt: schritt, neuRechnen: () => laden(true) }
}

/* ---------- Die Prognose: eine Zeile finden, einen Anteil lesen ------------ */

export type Gruppe = 'gesamt' | 'sorte' | 'schlag' | 'charge'

/**
 * Die Prognosezeile einer Gruppe bei einem Horizont. `h` muss eine
 * Stützstelle sein; 0, 7, 14 und 28 gibt es immer, dazu jede Woche bis zum
 * Saisonende. Gibt es sie nicht (zu weit, oder die Gruppe liegt leer),
 * kommt null zurück — und der Bildschirm schreibt „—", nicht 0.
 */
export function prognoseBei(zeilen: Prognose[], gruppe: Gruppe, schluessel: string, h: number): Prognose | null {
  const k = gruppe === 'gesamt' ? '' : schluessel
  return zeilen.find(z => z.gruppe === gruppe && z.schluessel === k && z.h === h) ?? null
}

/** Die Zerlegung des Eingangs einer Gruppe (erg_wohin). */
export function wohinVon(zeilen: Wohin[], gruppe: Gruppe, schluessel = ''): Wohin | null {
  const k = gruppe === 'gesamt' ? '' : schluessel
  return zeilen.find(z => z.gruppe === gruppe && z.schluessel === k) ?? null
}

/** Die Lieferscheine einer Gruppe, jeder einmal (v_lieferung_gruppe, 0114) — null, wenn keiner da ist. */
export function lieferungenVon(zeilen: LieferungGruppe[], gruppe: Gruppe, schluessel = ''): LieferungGruppe | null {
  const k = gruppe === 'gesamt' ? '' : schluessel
  return zeilen.find(z => z.gruppe === gruppe && z.schluessel === k) ?? null
}

/* ---------- Wo die Ware heute steht ------------------------------------------ */

/**
 * Wo die Ware **heute** auf einer Lagertage-Achse steht: je Charge im Filter
 * das Alter der liegenden Paletten (Spanne über die Eingangstage) und ihre
 * Masse — die Rauten auf der Kurve. Chargen ohne Bestand stehen nirgends.
 */
export interface Lagerstand { charge: Bestand; alter: number; von: number; bis: number; imHaus: number; naechste?: NaechsteCharge }
export function lagerstaende(bestand: Bestand[], naechste: NaechsteCharge[]): Lagerstand[] {
  return bestand
    .filter(b => b.im_haus_heute_kg > 0 && (b.alter_lager_heute != null || b.alter_lager_von != null))
    .map(b => {
      const von = b.alter_lager_von ?? b.alter_lager_heute, bis = b.alter_lager_bis ?? b.alter_lager_heute
      return { charge: b, alter: b.alter_lager_heute ?? (von + bis) / 2, von, bis, imHaus: b.im_haus_heute_kg,
               naechste: naechste.find(n => n.charge_nr === b.charge_nr) }
    })
    .sort((a, b) => b.imHaus - a.imHaus)
}
