import { supabase } from '../lib/supabase'
import { stammdaten } from '../lib/db'
import type { Auftrag, AuftragGebinde, Charge } from '../lib/typen'

/** Eine Palox-Ablesung dieser Arbeit (schimmel_messung). */
export interface Ablesung { id: number; kg: number; ts: string; palox_stand_kg: number | null }
export interface AusschussZeile {
  id: number; art: 'zu_klein' | 'zu_gross'; kg: number; ts: string
  gemessen: boolean; brutto_kg: number | null; kisten: number | null
}
export interface Palette { id: number; wiegung_id: number | null; eingangsdatum: string | null }

/** Alles, was die Arbeit-Ansicht braucht — in einem Rutsch geladen, damit die
 *  Checkliste ihren Zustand aus denselben Zeilen liest wie die Masken. */
export interface ArbeitDaten {
  auftrag: Auftrag
  charge: Charge | undefined
  teilnehmer: { profil_id: string; name: string }[]
  paletten: Palette[]
  gebinde: AuftragGebinde[]
  ablesungen: Ablesung[]
  ausschuss: AusschussZeile[]
  nAusgang: number
  angaben: Record<string, string>
  baender: [number, number][]
}

export async function arbeitLaden(auftragId: number): Promise<ArbeitDaten | null> {
  const [{ chargen, kaliber }, a, tn, pa, ge, sm, au, ag, an] = await Promise.all([
    stammdaten(),
    supabase.from('auftrag').select('*').eq('id', auftragId).maybeSingle(),
    supabase.from('auftrag_teilnehmer').select('profil_id, profil(name)')
      .eq('auftrag_id', auftragId).is('verlassen_ts', null),
    supabase.from('auftrag_palette').select('id, wiegung_id, eingangsdatum')
      .eq('auftrag_id', auftragId).order('ts'),
    supabase.from('auftrag_gebinde').select('*').eq('auftrag_id', auftragId).order('kaliber_idx'),
    supabase.from('schimmel_messung').select('id, kg, ts, palox_stand_kg')
      .eq('auftrag_id', auftragId).order('ts'),
    supabase.from('ausschuss_messung').select('id, art, kg, ts, gemessen, brutto_kg, kisten')
      .eq('auftrag_id', auftragId).order('ts'),
    supabase.from('ausgang_wiegung').select('id').eq('auftrag_id', auftragId),
    supabase.from('v_auftrag_angabe').select('schluessel, wert').eq('auftrag_id', auftragId),
  ])
  if (a.error) throw a.error
  const auftrag = a.data as Auftrag | null
  if (!auftrag) return null
  const charge = chargen.find(c => c.nr === auftrag.charge_nr)

  // Die Bänder: aus der Fassung, nach der die Arbeit läuft; sonst aus der Sorte.
  let baender: [number, number][] = []
  if (auftrag.sortierschema_id !== null) {
    const { data } = await supabase.from('sortierschema').select('kaliber_baender')
      .eq('id', auftrag.sortierschema_id).maybeSingle()
    baender = ((data as { kaliber_baender: [number, number][] | null } | null)?.kaliber_baender) ?? []
  }
  if (baender.length === 0 && charge) {
    baender = kaliber.find(k => k.sorte === charge.sorte)?.kaliber_baender ?? []
  }

  type Eintrag = { profil_id: string; profil: { name: string } | { name: string }[] | null }
  const av = (an.data ?? []) as { schluessel: string; wert: string }[]
  return {
    auftrag, charge,
    teilnehmer: ((tn.data ?? []) as unknown as Eintrag[]).map(r => ({
      profil_id: r.profil_id,
      name: (Array.isArray(r.profil) ? r.profil[0]?.name : r.profil?.name) ?? '?',
    })),
    paletten: (pa.data ?? []) as Palette[],
    gebinde: (ge.data ?? []) as AuftragGebinde[],
    ablesungen: (sm.data ?? []) as Ablesung[],
    ausschuss: (au.data ?? []) as AusschussZeile[],
    nAusgang: ((ag.data ?? []) as unknown[]).length,
    angaben: Object.fromEntries(av.map(x => [x.schluessel, x.wert])),
    baender,
  }
}

/** Was an dieser Station überhaupt anfällt (siehe docs/ABLAUF.md). */
export function stationsProfil(a: Auftrag) {
  return {
    hatPaletten: a.station !== 'waschen',
    hatKisten: a.station !== 'waschen_sortieren',
    mitWiegen: a.station === 'waschen_sortieren',
    hatAusschuss: a.weg === 'hand',
    hatAusgang: a.station === 'waschen' || a.station === 'waschen_sortieren',
  }
}

export const uhrzeit = (ts: string, gebietsschema: string) =>
  new Date(ts).toLocaleTimeString(gebietsschema, { hour: '2-digit', minute: '2-digit' })
