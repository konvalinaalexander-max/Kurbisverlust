export type Rolle = 'admin' | 'arbeiter'
export type Weg = 'maschine' | 'hand'
export type Station = 'sortieren' | 'waschen' | 'waschen_sortieren'
export type AuftragStatus = 'offen' | 'abgeschlossen'
export type Zuordnung = 'auto' | 'manuell' | 'offen' | 'mehrdeutig'
export type AusschussArt = 'zu_klein' | 'zu_gross'
export type MargeArt = 'nebenkanal' | 'ueberfuellung'

export interface Profil { id: string; name: string; rolle: Rolle; aktiv: boolean; anonym: boolean }
export interface Charge { nr: number; schlag: string; sorte: string; saison: number }
export interface SorteKaliber {
  sorte: string; verlust_unter: number; kaliber_baender: [number, number][]; kanal_ab: number
}
export interface Gebinde {
  art: string; tara_kg_pro_kiste: number | null; tara_kg_palette: number | null; bemerkung: string | null
}

export interface Auftrag {
  id: number; weg: Weg; station: Station; charge_nr: number
  start_ts: string; ende_ts: string | null
  geplante_paletten: number | null; status: AuftragStatus
  eroeffnet_von: string; durchsatz_kg: number | null; bemerkung: string | null
  abgebrochen_ts: string | null; abbruch_grund: string | null
}

export interface SortierLauf {
  id: number; charge_nr: number | null; datei_name: string
  roh_datei_ref: string | null; datei_zeit: string | null; datei_zeit_quelle: string | null
  auftrag_id: number | null; zuordnung: Zuordnung
  n_roh: number; n_overflow: number; n_klein: number; n_dubletten: number; n_gueltig: number
  gelesen_ts: string
}

/** Eine Zeile aus v_hochrechnung — ein Strom einer Charge in einer Portion.
 *  Die drei Szenarien gibt es seit 0019 nicht mehr: Bereiche entstehen aus
 *  Fehlerfortpflanzung, nicht daraus, alle Koeffizienten gleichzeitig an ihre
 *  Grenze zu setzen. */
export interface Hochrechnung {
  charge_nr: number; sorte: string; schlag: string
  portion: 'ausgelagert' | 'lager'
  alter_tage: number; eingang_kg: number; portion_kg: number
  f_extrapoliert: boolean
  strom: string; buch: 'verlust' | 'marge' | 'bilanz'
  kg: number | null; basis_kg: number | null
  koeffizient: number | null; koeff_n: number | null; koeff_basis: string | null
  formel: string
}

/** Eine Zeile aus verlust_ranking() — ein Strom mit fortgepflanztem Bereich.
 *  Der Bereich lässt sich nicht durch Summieren gefilterter Zeilen gewinnen,
 *  deshalb rechnet ihn die Datenbank auch für die gefilterte Ansicht. */
export interface Ranking {
  strom: string; buch: 'verlust' | 'marge' | 'bilanz'
  kg: number | null; kg_unten: number | null; kg_oben: number | null
  kg_beobachtet: number | null; kg_projiziert: number | null
  kg_extrapoliert: number | null
  koeff_n_min: number | null; streuung_kg: number | null; df: number | null
}

export interface Massenbilanz {
  charge_nr: number; sorte: string; schlag: string
  eingang_kg: number | null; ausgelagert_kg: number | null; lager_kg: number | null
  n_paletten: number; alter_ausgelagert: number | null; alter_lager: number | null
  stichtag: string; modell_am_band_kg: number | null; csv_gemessen_kg: number | null
  abweichung_kg: number | null; abweichung_anteil: number | null; restbestand_kg: number | null
}

export interface Datenlage {
  charge_nr: number; sorte: string; schlag: string
  n_paletten: number; n_paletten_mit_netto: number; eingang_kg: number | null
  n_wiegungen: number; n_schimmel: number; n_sortierlaeufe: number; n_auftraege: number
}
