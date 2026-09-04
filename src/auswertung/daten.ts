import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import type { Datenlage, Hochrechnung, Massenbilanz, Ranking } from '../lib/typen'

/* =========================================================================
   Die Auswertung für den Betriebsleiter — ein Datenstand für alle Reiter.
   Geladen wird einmal (gespeicherte Ansichten, 0016), gehalten im Modul;
   jeder Reiter liest daraus. „Neu rechnen" holt alles frisch.
   ========================================================================= */

export interface Modell {
  n: number; c_chargen: number; t_min: number; t_max: number
  k: number | null; lambda: number | null; smearing: number | null; brauchbar: boolean
  sockel: number | null; sockel_nachweis: number | null; sockel_schwelle: number | null
}
export interface Schimmelpunkt {
  auftrag_id: number | null; charge_nr: number; sorte: string; lagertage: number
  schimmel_kg: number; basis_jetzt_kg: number; anteil: number | null; plausibel: boolean; quelle: string
}
export interface Bestand {
  charge_nr: number; sorte: string; schlag: string
  eingang_kg: number; lager_kg: number; wartet_kg: number; sortiert_kg: number; gewaschen_kg: number
  ausgelagert_kg: number; alter_lager: number; alter_lager_heute: number; ueberzaehlung_kg: number
  n_paletten: number; eingangsdatum_mittel: string | null
}
export interface NaechsteCharge {
  charge_nr: number; sorte: string; schlag: string; lager_kg: number; alter_tage: number
  masse_jetzt_kg: number; verdunstung_14_kg: number | null; schimmel_14_kg: number | null
  verlust_14_kg: number | null; hochgerechnet: boolean; modell_gilt: boolean
}
export interface SortenK { sorte: string; mittel: number | null; unten: number | null; oben: number | null; n: number; basis: string }
export interface Saisonbilanz {
  eingang_kg: number; verlust_modell_kg: number; verlust_unten_kg: number | null; verlust_oben_kg: number | null
  ausgang_kg: number; verkauf_kg: number; marge_kg: number; entsorgt_kg: number
  restbestand_modell_kg: number; im_lager_kg: number; wartet_kg: number; vorlauf_kg: number
  luecke_kg: number; luecke_anteil: number | null; ausgang_deckung: number | null; n_lieferungen: number; befund: string
  lagerverlust_kg: number | null; feld_kg: number | null
}
export interface Selektion { n_verarbeitung: number | null; n_lager: number | null; unterschied: number | null; befund: string }
export interface Befund { art: string; auftrag_id: number | null; charge_nr: number; sorte: string; start_ts: string | null; befund: string; rat: string }
export interface Wiegung {
  id: number; auftrag_id: number | null; charge_nr: number; sorte: string; lagertage: number; wiege_ts: string
  netto_damals_kg: number | null; netto_jetzt_kg: number | null; kg_pro_kiste: number | null
  kg_pro_kuerbis: number | null; verlust_kg: number | null; sichtbar_schimmel: boolean
}
export interface Kurve { altersklasse: string; von: number; bis: number; messungen: number; gemessen: number | null; verwendet: number | null; unten: number | null; oben: number | null; erlaeuterung: string }
export interface Kaliberzeile { charge_nr: number; sorte: string; klasse: string; band_von: number | null; band_bis: number | null; n_kuerbis: number; masse_kg: number }
export interface Marge { posten: string; kg: number | null; kg_unten: number | null; kg_oben: number | null; erlaeuterung: string }
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
export interface UeberfuellungKaeufer {
  kaeufer: string; kaeufer_name: string; sorte: string; n_wiegungen: number; kisten: number
  kg_pro_kiste: number; soll_kg_pro_kiste: number; ueberfuellung_je_kiste: number; ueberfuellung_kg: number
}
export interface Datenqualitaet {
  paletten_gezaehlt: number; paletten_mit_datum: number; arbeiten_fertig: number
  arbeiten_mit_ablesung: number; arbeiten_mit_zwei_ablesungen: number; arbeiten_mit_antwort: number
  ausschuss_messungen: number; ausschuss_gewogen: number; lagerkontrollen: number; lagerkontrollen_zufaellig: number
  sortierlaeufe: number; sortierlaeufe_zugeordnet: number; sortier_arbeiten: number; sortier_arbeiten_mit_kisten: number
  wasch_arbeiten: number; wasch_arbeiten_mit_kisten: number
}
export interface Saisonwoche { woche: string; eingang_kg: number; ausgang_kg: number; eingang_kumuliert_kg: number; ausgang_kumuliert_kg: number; vorlauf_kg: number }
export interface KoeffGebinde { sorte: string; kaliber_idx: number; n: number; kg_je_gebinde: number; sd: number | null; unten: number | null; oben: number | null }
export interface KoeffZeile { was: string; wert: string; n: number; basis: string }
export interface Schema { sorte: string; kaeufer: string | null; art: string; gilt_ab: string; kaliber_baender: [number, number][] | null; verlust_unter: number | null; kanal_ab: number | null }

export interface Auswertung {
  stand: string | null
  hochrechnung: Hochrechnung[]
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
  sorten: { verdunstung: SortenK[]; ausschuss: SortenK[] }
  wiegungen: Wiegung[]
  marge: Marge[]
  gewichte: Gewichtsstufe[]
  verarbeitung: VerarbeitungAlter[]
  durchsatz: Durchsatz[]
  ueberfuellung: UeberfuellungKaeufer[]
  qualitaet: Datenqualitaet | null
  saisonverlauf: Saisonwoche[]
  gebinde: KoeffGebinde[]
  schemata: Schema[]
}

let stand: Auswertung | null = null
let ladeVersprechen: Promise<Auswertung> | null = null
const hoerer = new Set<() => void>()

async function alles(): Promise<Auswertung> {
  const { data: st } = await supabase.from('auswertung_stand').select('berechnet_ts, geaendert_ts').maybeSingle()
  const veraltet = !st?.berechnet_ts || new Date(st.geaendert_ts) > new Date(st.berechnet_ts)
  if (veraltet) {
    const { error } = await supabase.rpc('auswertung_aktualisieren')
    if (error) throw error
  }
  const { data: st2 } = await supabase.from('auswertung_stand').select('berechnet_ts').maybeSingle()
  const q = async <T,>(name: string, order?: [string, boolean]): Promise<T[]> => {
    let s = supabase.from(name).select('*')
    if (order) s = s.order(order[0], { ascending: order[1] })
    const r = await s
    if (r.error) throw r.error
    return (r.data ?? []) as T[]
  }
  const eins = async <T,>(name: string): Promise<T | null> => {
    const r = await supabase.from(name).select('*').maybeSingle()
    return (r.data ?? null) as T | null
  }
  const [h, b, d, pl, kv, sk, mo, sel, sb, pk, hb, nc, kfv, kfa, kfn, kfu, wk, mg, gw, va, ds, uk, dq, sv, kg, ss] = await Promise.all([
    q<Hochrechnung>('v_hochrechnung'), q<Massenbilanz>('v_massenbilanz'), q<Datenlage>('v_datenlage'),
    q<Befund>('v_plausibilitaet'), q<Kaliberzeile>('v_kaliber_verteilung'), q<Kurve>('v_schimmel_kurve_anzeige'),
    eins<Modell>('v_schimmel_modell'), eins<Selektion>('v_selektionsverdacht'), eins<Saisonbilanz>('v_saisonbilanz'),
    q<Schimmelpunkt>('v_schimmel_punkte'), q<Bestand>('v_hochrechnung_basis'), q<NaechsteCharge>('v_naechste_charge'),
    q<SortenK>('v_koeff_verdunstung'), q<SortenK>('v_koeff_ausschuss'), q<SortenK>('v_koeff_nebenkanal'),
    q<{ n: number; kg_pro_kiste: number | null }>('v_koeff_ueberfuellung'),
    q<Wiegung>('v_wiegung_kennzahl', ['wiege_ts', false]), q<Marge>('v_marge_buch'),
    q<Gewichtsstufe>('v_gewichtsverteilung'), q<VerarbeitungAlter>('v_verarbeitung_alter', ['tag', true]),
    q<Durchsatz>('v_durchsatz', ['start_ts', false]), q<UeberfuellungKaeufer>('v_ueberfuellung_kaeufer'),
    eins<Datenqualitaet>('v_datenqualitaet'), q<Saisonwoche>('v_saisonverlauf', ['woche', true]),
    q<KoeffGebinde>('v_koeff_gebinde'), q<Schema>('sortierschema', ['gilt_ab', false]),
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
    { was: 'Überfüllung je Kiste', n: kfu[0]?.n ?? 0, basis: 'gewogene Ausgangspaletten',
      wert: kfu[0]?.kg_pro_kiste == null ? '—' : `${kfu[0].kg_pro_kiste.toFixed(3)} kg` },
  ]
  return {
    stand: st2?.berechnet_ts ?? null,
    hochrechnung: h, bilanz: b, lage: d, befunde: pl, kaliber: kv, kurve: sk, koeff,
    modell: mo, selektion: sel, saison: sb, punkte: pk, bestand: hb, naechste: nc,
    sorten: { verdunstung: kfv, ausschuss: kfa }, wiegungen: wk, marge: mg,
    gewichte: gw, verarbeitung: va, durchsatz: ds, ueberfuellung: uk, qualitaet: dq, saisonverlauf: sv,
    gebinde: kg, schemata: ss,
  }
}

export function auswertungLaden(erzwingen = false): Promise<Auswertung> {
  if (stand && !erzwingen) return Promise.resolve(stand)
  if (!ladeVersprechen || erzwingen) {
    const lauf = async () => {
      if (erzwingen) {
        const { error } = await supabase.rpc('auswertung_aktualisieren')
        if (error) throw error
      }
      return alles()
    }
    const v: Promise<Auswertung> = lauf()
      .then(a => { stand = a; ladeVersprechen = null; hoerer.forEach(h => h()); return a })
      .catch((f: unknown) => { ladeVersprechen = null; throw f })
    ladeVersprechen = v
    return v
  }
  return ladeVersprechen
}

export function auswertungVergessen() { stand = null }

/** Der Datenstand für einen Reiter — geladen, gehalten, auf Wunsch neu gerechnet. */
export function useAuswertung() {
  const [daten, setDaten] = useState<Auswertung | null>(stand)
  const [laedt, setLaedt] = useState(!stand)
  const [fehler, setFehler] = useState<string | null>(null)
  const laden = useCallback(async (erzwingen = false) => {
    setLaedt(true); setFehler(null)
    try { setDaten(await auswertungLaden(erzwingen)) }
    catch (f) { setFehler(fehlerText(f)) }
    finally { setLaedt(false) }
  }, [])
  useEffect(() => {
    const h = () => setDaten(stand)
    hoerer.add(h)
    if (!stand) void laden()
    return () => { hoerer.delete(h) }
  }, [laden])
  return { daten, laedt, fehler, neuRechnen: () => laden(true) }
}

/** Ein Strom, über alle Chargen summiert — für Ränge, Balken und Kaskade. */
export interface StromSumme {
  strom: string; buch: string
  mittel: number; unten: number; oben: number
  beobachtet: number; projiziert: number; extrapoliert: number; basis: number
  koeffN: number | null; koeffBasis: string | null; formel: string
  bereichBekannt: boolean; bekannt: boolean
}

export function stroemeSummieren(zeilen: Hochrechnung[], ranking: Ranking[]): StromSumme[] {
  const map = new Map<string, StromSumme>()
  for (const z of zeilen) {
    let s = map.get(z.strom)
    if (!s) {
      s = { strom: z.strom, buch: z.buch, mittel: 0, unten: 0, oben: 0, beobachtet: 0, projiziert: 0,
            extrapoliert: 0, basis: 0, koeffN: z.koeff_n, koeffBasis: z.koeff_basis, formel: z.formel,
            bereichBekannt: false, bekannt: true }
      map.set(z.strom, s)
    }
    if (z.koeff_bekannt === false || z.kg === null) { s.bekannt = false; continue }
    s.mittel += z.kg
    s.basis += z.basis_kg ?? 0
    if (z.portion === 'ausgelagert') s.beobachtet += z.kg; else s.projiziert += z.kg
    if (z.f_extrapoliert) s.extrapoliert += z.kg
    if (z.koeff_n !== null) s.koeffN = s.koeffN === null ? z.koeff_n : Math.min(s.koeffN, z.koeff_n)
  }
  for (const r of ranking) {
    const s = map.get(r.strom)
    if (!s || r.kg_unten === null || r.kg_oben === null) continue
    s.unten = r.kg_unten; s.oben = r.kg_oben; s.bereichBekannt = true
  }
  return [...map.values()]
}

/** Der Bereich je Strom kommt aus der Datenbank (Fehlerfortpflanzung, nicht Addition). */
export function useRanking(sorte: string, schlag: string, minLagertage: string, stand: string | null) {
  const [ranking, setRanking] = useState<Ranking[]>([])
  useEffect(() => {
    let verworfen = false
    void (async () => {
      const { data, error } = await supabase.rpc('verlust_ranking', {
        p_sorte: sorte || null, p_schlag: schlag || null,
        p_min_lagertage: minLagertage ? Number(minLagertage) : null,
      })
      if (!verworfen && !error) setRanking((data ?? []) as Ranking[])
    })()
    return () => { verworfen = true }
  }, [sorte, schlag, minLagertage, stand])
  return ranking
}

/** Die Farben der Ströme — überall dieselbe je Ursache (index.css). */
export const STROMFARBE: Record<string, string> = {
  'Verdunstung': 'var(--strom-verdunstung)',
  'Schimmel/Fäulnis': 'var(--strom-schimmel)',
  'Nicht lagerbedingt': 'var(--strom-feld)',
  'Zu klein (Tierfutter)': 'var(--strom-ausschuss)',
  'Nebenkanal zu gross': 'var(--strom-nebenkanal)',
}
