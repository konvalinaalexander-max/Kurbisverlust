import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { SCHEMA_ERWARTET, datenbankVeraltet } from '../lib/version'
import type { Datenlage, Hochrechnung, Massenbilanz } from '../lib/typen'
import { heute as heuteOrtszeit } from '../lib/format'

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

export interface Modell {
  n: number; c_chargen: number; t_min: number; t_max: number
  k: number | null; lambda: number | null; smearing: number | null; brauchbar: boolean
  sockel: number | null; sockel_nachweis: number | null; sockel_schwelle: number | null
  /** Die Anpassung im Logarithmus (erg_modell): Achse ln λ, Mittel der ln t,
   *  die Varianzen und ihre Kovarianz, das t-Quantil — daraus das Band. */
  ln_lambda?: number | null; x_mittel?: number | null
  var_achse?: number | null; var_k?: number | null; kov_achse_k?: number | null; t_faktor?: number | null
}
export interface Schimmelpunkt {
  auftrag_id: number | null; charge_nr: number; sorte: string; lagertage: number
  schimmel_kg: number; basis_jetzt_kg: number; anteil: number | null; plausibel: boolean; quelle: string
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
   *  kanal_ausgelagert_kg ist der andere Kanal, der schon passiert ist; kanal_im_haus_kg
   *  ist die Erwartung an der Ware, die noch unsortiert liegt.
   *  0064: **null heisst „nicht gemessen"**, nicht null Kilo. Jeder dieser Ströme ist
   *  null, solange sein Koeffizient keine Messung hat; das Kennzeichen daneben sagt,
   *  welcher. Wer hier mit `?? 0` rechnet, macht aus Unwissen eine gemessene Null. */
  verdunstung_heute_kg: number | null; schimmel_heute_kg: number | null
  sockel_heute_kg: number | null; sockel_oben_kg: number
  fax_heute_kg: number | null; fax_erwartet_kg: number | null
  verlust_heute_kg: number | null; kanal_ausgelagert_kg: number | null
  im_haus_heute_kg: number; kanal_im_haus_kg: number | null; heute: string
  verlust_bekannt: boolean; verdunstung_bekannt: boolean; schimmel_bekannt: boolean
  sockel_nachgewiesen: boolean; fax_bekannt: boolean; kanal_bekannt: boolean
}
export interface NaechsteCharge {
  charge_nr: number; sorte: string; schlag: string; lager_kg: number; alter_tage: number
  masse_jetzt_kg: number; verdunstung_14_kg: number | null; schimmel_14_kg: number | null
  prognose_verlust_14_kg: number | null; hochgerechnet: boolean; modell_gilt: boolean
  alter_von: number | null; alter_bis: number | null; n_kohorten: number | null
}
export interface Kohorte {
  charge_nr: number; eingangsdatum: string; n_paletten: number; n_verarbeitet: number; n_rest: number
  netto_je_palette: number | null; rest_kg: number | null; alter_heute: number
  eingang_kg: number | null
}
export interface FaxBeobachtung {
  auftrag_id: number; charge_nr: number; sorte: string; schlag: string; kaeufer: string | null
  start_ts: string; ende_ts: string | null; status: string
  masse_kg: number | null; masse_quelle: string | null; kisten: number
  faul_kg: number; faul_erfasst: boolean; anteil: number | null; plausibel: boolean
  paletten_gesamt: number | null; tage_seit_waschen: number | null; kistensystem: string | null
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
  sockel_heute_kg: number | null; sockel_oben_kg: number
  fax_heute_kg: number | null; fax_erwartet_kg: number | null
  kanal_ausgelagert_kg: number | null; kanal_unten_kg: number | null; kanal_oben_kg: number | null
  im_haus_heute_kg: number; verkaufsfaehig_heute_kg: number; kanal_im_haus_kg: number | null
  lager_kg: number; gegenprobe_wartet_kg: number | null; ueberzaehlung_kg: number
  fax_durchsatz_kg: number | null; n_fax_arbeiten: number | null
  verlust_bekannt: boolean; verdunstung_bekannt: boolean; schimmel_bekannt: boolean
  sockel_nachgewiesen: boolean; fax_bekannt: boolean; kanal_bekannt: boolean
  bilanz_rest_kg: number | null; bilanz_rest_anteil: number | null; ausgang_deckung: number | null; befund: string
}
export interface Selektion { n_verarbeitung: number | null; n_lager: number | null; unterschied: number | null; befund: string }
export interface Befund { art: string; auftrag_id: number | null; charge_nr: number; sorte: string; start_ts: string | null; befund: string; rat: string }
export interface Wiegung {
  id: number; auftrag_id: number | null; charge_nr: number; sorte: string; lagertage: number; wiege_ts: string
  netto_damals_kg: number | null; netto_jetzt_kg: number | null; kg_pro_kiste: number | null
  kg_pro_kuerbis: number | null; verdunstung_kg: number | null; sichtbar_schimmel: boolean
}
export interface Kurve { altersklasse: string; von: number; bis: number; messungen: number; gemessen: number | null; verwendet: number | null; unten: number | null; oben: number | null; erlaeuterung: string }
export interface Kaliberzeile { charge_nr: number; sorte: string; klasse: string; band_von: number | null; band_bis: number | null; n_kuerbis: number; masse_kg: number }
export interface LieferungKurz { charge_nr: number | null; sorte: string | null; datum: string; masse_kg: number | null; buch: string; ziel_name: string }
export interface Marge { posten: string; kg: number | null; kg_unten: number | null; kg_oben: number | null; erlaeuterung: string; gemessen: boolean }
export interface Gewichtsstufe { sorte: string; schlag: string; charge_nr: number; stufe_g: number; n: number }
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
 * Verkauft gegen gewogen, je Sorte oder Charge und Kistensystem
 * (erg_ueberfuellung, 0061). verschenkt_kg nur, wo beides da ist: gewogene
 * Kisten desselben Systems und verkaufte Kisten aus der Verkaufsdatei.
 */
export interface Ueberfuellung {
  gruppe: 'sorte' | 'charge'; sorte: string; charge_nr: number | null
  kistensystem: 'kiste_ab' | 'stueck' | 'unbekannt'
  soll_kg_pro_kiste: number | null; stueck_je_kiste: number | null; kaliber_idx: number | null
  band_von_g: number | null; band_bis_g: number | null; nenn_g: number | null
  n_lieferungen: number; kg_verkauft: number | null; kisten_verkauft: number | null; n_anteilig: number
  stueck_verkauft: number | null; von: string | null; bis: string | null
  n_wiegungen: number; kisten_gewogen: number | null; kg_je_kiste: number | null; sd_je_kiste: number | null
  zuviel_je_kiste: number | null; zuviel_gewogen_kg: number | null
  verschenkt_kg: number | null; verschenkt_fehler_kg: number | null
  g_je_kuerbis: number | null; band_mittel_g: number | null
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
}
export interface AusgangKennzahl {
  id: number; auftrag_id: number; charge_nr: number; sorte: string; schlag: string; ts: string
  kisten: number; kg_pro_kiste: number | null; kg_pro_kuerbis: number | null
  soll_kg_pro_kiste: number | null; ueberfuellung_je_kiste: number | null; ueberfuellung_kg: number | null
  kistensystem: string | null; kaliber_idx: number | null; stueck_je_kiste: number | null
  erwartet_kg_pro_kiste: number | null; abweichung_je_kiste: number | null; band_mittel_g: number | null
}
/**
 * Der Verlauf je Woche (erg_verlauf, 0061): Eingang und Ausgang kumuliert
 * (gemessen), der Verlust kumuliert (gerechnet, bis heute), danach als
 * Prognose (prognose = true). sorte NULL = alles.
 */
export interface Verlaufswoche {
  woche: string; bis: string; prognose: boolean; sorte: string | null
  eingang_kum_kg: number; ausgang_kum_kg: number; verdunstung_kum_kg: number
  schimmel_kum_kg: number; sockel_kum_kg: number
  fax_kum_kg: number; verlust_kum_kg: number; im_haus_kg: number
}
/** Ein Strom einer Gruppe mit Bereich (erg_verlust, 0061) — vorgerechnet für gesamt, jede Sorte, jeden Schlag, jede Charge. */
export interface Verlustzeile {
  gruppe: 'gesamt' | 'sorte' | 'schlag' | 'charge'; schluessel: string
  strom: string; buch: 'verlust' | 'feld' | 'marge' | 'bilanz'
  kg: number | null; kg_unten: number | null; kg_oben: number | null
  kg_beobachtet: number | null; kg_projiziert: number | null; kg_extrapoliert: number | null; kg_erwartet: number | null
  koeff_n_min: number | null; streuung_kg: number | null; df: number | null
  basis_kg: number | null; koeff_basis: string | null; koeff_art: string | null; formel: string; bekannt: boolean
  eingang_kg: number; n_chargen: number
}
export interface KoeffGebinde { sorte: string; kaliber_idx: number; n: number; kg_je_gebinde: number; sd: number | null; unten: number | null; oben: number | null }
export interface KoeffZeile { was: string; wert: string; n: number; basis: string }
export interface Schema { sorte: string; kaeufer: string | null; art: string; gilt_ab: string; kaliber_baender: [number, number][] | null; verlust_unter: number | null; kanal_ab: number | null }

export interface Auswertung {
  stand: string | null
  /** Der Tag, bis zu dem gerechnet ist (heute(), 0061). */
  heute: string
  bilanz: Massenbilanz[]
  lage: Datenlage[]
  befunde: Befund[]
  kaliber: Kaliberzeile[]
  kurve: Kurve[]
  koeff: KoeffZeile[]
  modell: Modell | null
  selektion: Selektion | null
  saison: Saisonbilanz | null
  punkte: Schimmelpunkt[]
  bestand: Bestand[]
  naechste: NaechsteCharge[]
  sorten: { verdunstung: SortenK[]; ausschuss: SortenK[]; nebenkanal: SortenK[] }
  wiegungen: Wiegung[]
  marge: Marge[]
  gewichte: Gewichtsstufe[]
  verarbeitung: VerarbeitungAlter[]
  durchsatz: Durchsatz[]
  ueberfuellung: Ueberfuellung[]
  qualitaet: Datenqualitaet | null
  verlauf: Verlaufswoche[]
  verlust: Verlustzeile[]
  gebinde: KoeffGebinde[]
  schemata: Schema[]
  kohorten: Kohorte[]
  fax: FaxBeobachtung[]
  ausschuss: AusschussBeobachtung[]
  lieferungen: LieferungKurz[]
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
    const { error } = await supabase.rpc('auswertung_schritt', { p_schritt: i })
    if (error) {
      melden(null)
      return [{ sicht: `Neu rechnen, Schritt ${i} von ${SCHRITTE.length} (${SCHRITTE[i - 1]})`, meldung: error.message }]
    }
  }
  melden(null)
  return []
}

async function alles(erzwingen: boolean): Promise<Auswertung> {
  // 0057: Erst fragen, ob die Datenbank die Formeln hat, die diese App
  // voraussetzt. Sonst scheitert die Auswertung an einem alten Stand mit
  // einer rohen Meldung, aus der niemand den Weg heraus lesen kann.
  const version = await supabase.rpc('schema_stand')
  const schemaStand = typeof version.data === 'number' ? version.data : null
  if (version.error || schemaStand === null || schemaStand < SCHEMA_ERWARTET) throw new Error(datenbankVeraltet(schemaStand))

  const { data: st } = await supabase.from('auswertung_stand').select('berechnet_ts, geaendert_ts').maybeSingle()
  const veraltet = !st?.berechnet_ts || new Date(st.geaendert_ts) > new Date(st.berechnet_ts)
  // Scheitert das Neurechnen, wird mit dem letzten gespeicherten Stand
  // weitergearbeitet — veraltete Zahlen sind besser als keine, solange
  // dabeisteht, dass sie veraltet sind.
  const probleme: Problem[] = (veraltet || erzwingen) ? await rechnen() : []
  const { data: st2 } = await supabase.from('auswertung_stand').select('berechnet_ts').maybeSingle()

  // Jede Sicht wird für sich geholt. Scheitert eine, ist *ihre* Zahl unbekannt
  // — der Rest des Bildschirms steht trotzdem.
  const merken = (name: string, fehler: { message?: string } | null) => {
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
  const [b, d, pl, kv, sk, mo, sel, sb, pk, hb, nc, kfv, kfa, kfn, kfu, wk, mg, gw, va, ds, uk, dq, vl, ve, kg, ss, ko, fx, ab, lf, ak] = await Promise.all([
    q<Massenbilanz>('erg_massenbilanz'), q<Datenlage>('erg_datenlage'),
    q<Befund>('erg_plausibilitaet'), q<Kaliberzeile>('erg_kaliber'), q<Kurve>('erg_kurve'),
    eins<Modell>('erg_modell'), eins<Selektion>('erg_selektion'), eins<Saisonbilanz>('erg_bilanz'),
    q<Schimmelpunkt>('erg_punkte'), q<Bestand>('erg_charge'), q<NaechsteCharge>('erg_naechste_charge'),
    q<SortenK>('erg_koeff_verdunstung'), q<SortenK>('erg_koeff_ausschuss'), q<SortenK>('erg_koeff_nebenkanal'),
    q<{ n: number; kg_pro_kiste: number | null }>('erg_koeff_ueberfuellung'),
    q<Wiegung>('erg_wiegung', ['wiege_ts', false]), q<Marge>('erg_marge'),
    q<Gewichtsstufe>('erg_gewichte'), q<VerarbeitungAlter>('erg_verarbeitung_alter', ['tag', true]),
    q<Durchsatz>('erg_durchsatz', ['start_ts', false]), q<Ueberfuellung>('erg_ueberfuellung'),
    eins<Datenqualitaet>('erg_datenqualitaet'), q<Verlaufswoche>('erg_verlauf', ['woche', true]),
    q<Verlustzeile>('erg_verlust'),
    q<KoeffGebinde>('erg_gebinde'), q<Schema>('sortierschema', ['gilt_ab', false]),
    q<Kohorte>('erg_kohorte', ['eingangsdatum', true]), q<FaxBeobachtung>('erg_fax', ['start_ts', false]),
    q<AusschussBeobachtung>('erg_ausschuss'),
    q<LieferungKurz>('erg_lieferung', ['datum', true]),
    q<AusgangKennzahl>('erg_ausgang', ['ts', true]),
  ])

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
  const heute = sb?.heute ?? hb[0]?.heute ?? heuteOrtszeit()
  return {
    stand: st2?.berechnet_ts ?? null, heute,
    bilanz: b, lage: d, befunde: pl, kaliber: kv, kurve: sk, koeff,
    modell: mo, selektion: sel, saison: sb, punkte: pk, bestand: hb, naechste: nc,
    sorten: { verdunstung: kfv, ausschuss: kfa, nebenkanal: kfn }, wiegungen: wk, marge: mg,
    gewichte: gw, verarbeitung: va, durchsatz: ds, ueberfuellung: uk, qualitaet: dq, verlauf: vl, verlust: ve,
    gebinde: kg, schemata: ss, kohorten: ko, fax: fx, ausschuss: ab, lieferungen: lf, ausgang: ak,
    probleme,
  }
}

export function auswertungLaden(erzwingen = false): Promise<Auswertung> {
  if (stand && !erzwingen) return Promise.resolve(stand)
  if (!ladeVersprechen || erzwingen) {
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
  return { daten, laedt, fehler, fortschritt: schritt, neuRechnen: () => laden(true) }
}

/* ---------- Die Ströme einer Gruppe ---------------------------------------- */

/** Ein Strom, über die Chargen einer Gruppe summiert, mit Bereich — aus erg_verlust. */
export interface StromSumme {
  strom: string; buch: string
  mittel: number; unten: number; oben: number
  // 0066: die Teilbeträge sind null, solange der Strom nicht gemessen ist —
  // dann gehört „nicht gemessen" hin, keine 0 kg.
  beobachtet: number | null; projiziert: number | null; extrapoliert: number | null
  erwartet: number | null; basis: number | null
  koeffN: number | null; koeffBasis: string | null; formel: string
  bereichBekannt: boolean; bekannt: boolean
  eingang: number; nChargen: number
}

export type Gruppe = 'gesamt' | 'sorte' | 'schlag' | 'charge'

/** Die Ströme einer Gruppe: gesamt, eine Sorte, ein Schlag oder eine Charge — vorgerechnet, nicht summiert. */
export function stroemeVon(zeilen: Verlustzeile[], gruppe: Gruppe, schluessel = ''): StromSumme[] {
  return zeilen.filter(z => z.gruppe === gruppe && z.schluessel === (gruppe === 'gesamt' ? '' : schluessel)).map(z => ({
    strom: z.strom, buch: z.buch,
    // Diese drei hängen an der Flagge daneben: `bekannt` ist nur wahr, wenn kg
    // gemessen ist, `bereichBekannt` nur, wenn unten und oben da sind. Jede
    // Anzeigestelle fragt erst die Flagge — die 0 hier wird nie gelesen.
    mittel: z.kg ?? 0, unten: z.kg_unten ?? 0, oben: z.kg_oben ?? 0,
    // Die Teilbeträge haben keine solche Flagge und bleiben darum, was sie
    // sind (0066): Zahlen, wenn der Strom gemessen ist, sonst null.
    beobachtet: z.kg_beobachtet, projiziert: z.kg_projiziert, extrapoliert: z.kg_extrapoliert,
    erwartet: z.kg_erwartet, basis: z.basis_kg,
    koeffN: z.koeff_n_min, koeffBasis: z.koeff_basis, formel: z.formel,
    bereichBekannt: z.kg_unten !== null && z.kg_oben !== null, bekannt: z.bekannt && z.kg !== null,
    eingang: z.eingang_kg, nChargen: z.n_chargen,
  }))
}

/** Alle Schlüssel einer Gruppe, die es vorgerechnet gibt (Sorten, Schläge, Chargen). */
export function gruppenSchluessel(zeilen: Verlustzeile[], gruppe: Gruppe): string[] {
  return [...new Set(zeilen.filter(z => z.gruppe === gruppe).map(z => z.schluessel))]
    .sort((a, b) => gruppe === 'charge' ? Number(a) - Number(b) : a.localeCompare(b, 'de'))
}

/** Die Farben der Ströme — überall dieselbe je Ursache (index.css). */
export const STROMFARBE: Record<string, string> = {
  'Verdunstung': 'var(--strom-verdunstung)',
  'Schimmel/Fäulnis': 'var(--strom-schimmel)',
  'Nicht lagerbedingt': 'var(--strom-feld)',
  'Zu klein (Tierfutter)': 'var(--strom-ausschuss)',
  'Nebenkanal zu gross': 'var(--strom-nebenkanal)',
  'Faul beim Abpacken (Fax)': 'var(--strom-fax)',
  'Palox (Faules)': 'var(--strom-schimmel)',
}

/** Kurze Namen für Beschriftungen — die Ströme heissen im Modell länger. */
export const STROMKURZ: Record<string, string> = {
  'Verdunstung': 'Verdunstung',
  'Schimmel/Fäulnis': 'Faules im Lager',
  'Nicht lagerbedingt': 'Faules vom Feld',
  'Zu klein (Tierfutter)': 'zu klein',
  'Nebenkanal zu gross': 'zu gross',
  'Faul beim Abpacken (Fax)': 'Faules beim Abpacken',
}


/** „liegt seit 128–161 Tagen" — die Spanne der noch liegenden Paletten, nie
 *  nur ein Mittel: Eingang und Ausgang verteilen sich über Wochen (0051). */
export function alterSpanne(von: number | null | undefined, bis: number | null | undefined, mittel?: number | null): string {
  if (von != null && bis != null) {
    const a = Math.round(Math.min(von, bis)), b = Math.round(Math.max(von, bis))
    return a === b ? `${a} Tagen` : `${a}–${b} Tagen`
  }
  return mittel != null ? `${Math.round(mittel)} Tagen` : '—'
}

/* ---------- Kaliber je Sorte oder Charge ------------------------------------ */

export interface Kaliberklasse { name: string; klasse: string; von: number | null; bis: number | null; n: number; kg: number }
export interface KaliberGruppe {
  schluessel: string
  sorte: string
  /** Die Bänder dieser Gruppe, lesbar („600–1100 · 1100–1600 · 1600–2000"). */
  baender: string
  /** Die Sorte wurde nach mehr als einer Bänder-Fassung sortiert — dann gibt es mehrere Gruppen. */
  mehrere: boolean
  n: number; kg: number; klassen: Kaliberklasse[]
}

/**
 * Die Kaliber-Verteilung je Sorte (oder je Charge), über alle Sortierläufe
 * gebündelt: die Sicht liefert je Charge eine Zeile je Band. Gebündelt wird
 * je Sorte und je Bänder-Fassung, sonst stünden zwei Fassungen ineinander
 * verschränkt. Reihenfolge: zu klein, die Bänder aufsteigend, zu gross.
 */
/**
 * Die Glocke vorbereiten — für den Überblick und für die Ursachen dasselbe.
 * Beide Seiten zeigen dieselbe Gewichtsverteilung mit denselben Grenzen und
 * denselben Farben; die Rechnung stand bis Runde I zweimal im Code, Zeile für
 * Zeile gleich. Zwei Kopien einer Klassierung laufen früher oder später
 * auseinander, und dann färbt die eine Seite als „zu klein", was die andere
 * noch als Kaliber zeichnet.
 *
 * Die Grenzen kommen aus der jüngsten Kaliberfassung der Sorte. Ältere
 * Fassungen tragen noch einen Käufer (bis 0060); ohne Käufer geht vor, weil
 * das die heute gültige Regel ist.
 */
export interface Glockendaten {
  stufen: { x: number; n: number }[]
  grenzen: { x: number; text: string }[]
  gesamt: number
  mittel: number | null
  klassenfarbe: (x: number) => string
  schema: Schema | undefined
}

export function glockeVorbereiten(gewichte: Gewichtsstufe[], schemata: Schema[], sorte: string, breite: number): Glockendaten {
  const stufenMap = new Map<number, number>()
  for (const g of gewichte) { const x = Math.floor(g.stufe_g / breite) * breite; stufenMap.set(x, (stufenMap.get(x) ?? 0) + g.n) }
  const stufen = [...stufenMap.entries()].map(([x, n]) => ({ x, n })).sort((a, b) => a.x - b.x)
  const schema = schemata.find(s => s.sorte === sorte && s.art === 'kaliber' && s.kaeufer === null)
    ?? schemata.find(s => s.sorte === sorte && s.art === 'kaliber')
  const grenzen: { x: number; text: string }[] = []
  if (schema?.verlust_unter != null) grenzen.push({ x: schema.verlust_unter, text: 'zu klein <' })
  ;(schema?.kaliber_baender ?? []).forEach(([a], i) => { if (i > 0) grenzen.push({ x: a, text: `K${i + 1}` }) })
  if (schema?.kanal_ab != null) grenzen.push({ x: schema.kanal_ab, text: 'zu gross ≥' })
  const gesamt = gewichte.reduce((a, g) => a + g.n, 0)
  // Die Rohstufen sind 25 g breit; als Gewicht einer Stufe gilt ihre Mitte.
  const mittel = gesamt > 0 ? gewichte.reduce((a, g) => a + (g.stufe_g + 12.5) * g.n, 0) / gesamt : null
  const klassenfarbe = (x: number) => schema?.verlust_unter != null && x + breite <= schema.verlust_unter ? 'var(--strom-ausschuss)'
    : schema?.kanal_ab != null && x >= schema.kanal_ab ? 'var(--strom-nebenkanal)' : 'var(--kuerbis)'
  return { stufen, grenzen, gesamt, mittel, klassenfarbe, schema }
}

export function kaliberJe(zeilen: Kaliberzeile[], nach: 'sorte' | 'charge'): KaliberGruppe[] {
  const proCharge = new Map<number, Kaliberzeile[]>()
  for (const z of zeilen) proCharge.set(z.charge_nr, [...(proCharge.get(z.charge_nr) ?? []), z])
  const fassung = new Map<number, string>()
  for (const [nr, rows] of proCharge) {
    const b = [...new Set(rows.filter(r => r.klasse === 'kaliber' && r.band_von !== null).map(r => `${r.band_von}–${r.band_bis}`))]
      .sort((x, y) => Number(x.split('–')[0]) - Number(y.split('–')[0]))
    fassung.set(nr, b.join(' · '))
  }
  const gruppen = new Map<string, { schluessel: string; sorte: string; baender: string; klassen: Map<string, Kaliberklasse> }>()
  for (const z of zeilen) {
    const baender = fassung.get(z.charge_nr) ?? ''
    const schluessel = nach === 'sorte' ? z.sorte : String(z.charge_nr)
    const key = `${schluessel}|${baender}`
    let g = gruppen.get(key)
    if (!g) { g = { schluessel, sorte: z.sorte, baender, klassen: new Map() }; gruppen.set(key, g) }
    const kk = z.klasse === 'kaliber' ? `k|${z.band_von}|${z.band_bis}` : z.klasse
    let k = g.klassen.get(kk)
    if (!k) {
      k = { klasse: z.klasse, von: z.band_von, bis: z.band_bis, n: 0, kg: 0,
            name: z.klasse === 'verlust_klein' ? 'zu klein' : z.klasse === 'nebenkanal' ? 'zu gross' : `${z.band_von}–${z.band_bis} g` }
      g.klassen.set(kk, k)
    }
    k.n += z.n_kuerbis; k.kg += z.masse_kg
  }
  const rang = (k: Kaliberklasse) => k.klasse === 'verlust_klein' ? -1 : k.klasse === 'nebenkanal' ? 1e9 : (k.von ?? 0)
  const proSchluessel = new Map<string, number>()
  for (const g of gruppen.values()) proSchluessel.set(g.schluessel, (proSchluessel.get(g.schluessel) ?? 0) + 1)
  return [...gruppen.values()].map(g => {
    const liste = [...g.klassen.values()].sort((a, b) => rang(a) - rang(b))
    return { schluessel: g.schluessel, sorte: g.sorte, baender: g.baender, mehrere: (proSchluessel.get(g.schluessel) ?? 0) > 1, klassen: liste,
             n: liste.reduce((s, k) => s + k.n, 0), kg: liste.reduce((s, k) => s + k.kg, 0) }
  }).sort((a, b) => b.n - a.n)
}


/* ---------- Die Kurven, an denen die Ware heute steht ------------------------ */

export interface Kurvenpunkt { mittel: number; unten: number; oben: number }

/**
 * Die Verderbskurve des Modells an einer beliebigen Stelle t — dieselbe
 * Rechnung, mit der die Datenbank je Altersklasse rechnet (0061/0062):
 * F(t) = 1 − exp(−λ·t^k), zurückgerechnet mit dem Smearing-Faktor, plus der
 * Sockel a₀. Das Band kommt aus der Kovarianz der Anpassung (Delta-Methode im
 * Logarithmus): var(η) = var_achse + d²·var_k + 2·d·kov mit d = ln t − x̄.
 *
 * Gebraucht, um die Kurve **über die Messungen hinaus** zu zeichnen — dorthin,
 * wo die Ware heute liegt und wo sie in 30 oder 60 Tagen liegt. Neue Zahlen
 * entstehen hier nicht: Die Datenbank rechnet die Kaskade mit genau dieser
 * Kurve; hier wird sie nur an mehr Stellen ausgewertet als an sieben.
 */
export function schimmelKurve(m: Modell | null): ((t: number) => Kurvenpunkt) | null {
  if (!m || !m.brauchbar || m.lambda == null || m.k == null) return null
  const lnLambda = m.ln_lambda ?? Math.log(m.lambda)
  const k = m.k, sm = m.smearing ?? 1, sockel = m.sockel ?? 0
  const xm = m.x_mittel ?? null, va = m.var_achse ?? null, vk = m.var_k ?? null, kov = m.kov_achse_k ?? 0, tf = m.t_faktor ?? 1.96
  const f = (eta: number) => Math.min(1, sm * (1 - Math.exp(-Math.exp(eta))) + sockel)
  return (t: number) => {
    if (!(t > 0)) return { mittel: sockel, unten: sockel, oben: sockel }
    const lt = Math.log(t)
    const eta = lnLambda + k * lt
    if (xm === null || va === null || vk === null) { const w = f(eta); return { mittel: w, unten: w, oben: w } }
    const d = lt - xm
    const sd = Math.sqrt(Math.max(va + d * d * vk + 2 * d * kov, 0))
    return { mittel: f(eta), unten: f(eta - tf * sd), oben: f(eta + tf * sd) }
  }
}

/** Die Verdunstung nach t Tagen bei einer Tagesrate r: 1 − (1 − r)^t, mit dem Bereich der Rate. */
export function verdunstungKurve(k: SortenK | undefined): ((t: number) => Kurvenpunkt) | null {
  if (!k || k.mittel == null) return null
  const r = k.mittel, u = k.unten ?? r, o = k.oben ?? r
  const f = (rate: number, t: number) => 1 - Math.pow(1 - rate, Math.max(t, 0))
  return (t: number) => ({ mittel: f(r, t), unten: f(u, t), oben: f(o, t) })
}

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
