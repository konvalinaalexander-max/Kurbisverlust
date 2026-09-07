import { supabase } from '../lib/supabase'
import { einstellung, stammdaten } from '../lib/db'
import type { Auftrag, AuftragGebinde, Charge } from '../lib/typen'

/** Eine Schimmelmessung dieser Arbeit: Palox-Ablesung oder gewogene Kiste. */
export interface Ablesung {
  id: number; kg: number; ts: string; palox_stand_kg: number | null
  brutto_kg: number | null; kisten: number | null; gebindeart: string | null; mit_palette: boolean
  bemerkung: string | null
}
export interface AusschussZeile {
  id: number; art: 'zu_klein' | 'zu_gross'; kg: number; ts: string
  gemessen: boolean; brutto_kg: number | null; kisten: number | null
}
export interface Palette { id: number; wiegung_id: number | null; eingangsdatum: string | null }
/** Die Fassung, nach der die Arbeit läuft (sortierschema). */
export interface Fassung {
  id: number; art: 'kaliber' | 'kiste'; soll_kg_pro_kiste: number | null
  kaliber_baender: [number, number][] | null; gilt_ab: string; kaeufer: string | null
}

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
  fassung: Fassung | null
  /** Wie viele Kisten eine Palette sind (Einstellung, Vorgabe 32). */
  kistenProPalette: number
}

export async function arbeitLaden(auftragId: number): Promise<ArbeitDaten | null> {
  const [{ chargen, kaliber }, a, tn, pa, ge, sm, au, ag, an, kpp] = await Promise.all([
    stammdaten(),
    supabase.from('auftrag').select('*').eq('id', auftragId).maybeSingle(),
    supabase.from('auftrag_teilnehmer').select('profil_id, profil(name)')
      .eq('auftrag_id', auftragId).is('verlassen_ts', null),
    supabase.from('auftrag_palette').select('id, wiegung_id, eingangsdatum')
      .eq('auftrag_id', auftragId).order('ts'),
    supabase.from('auftrag_gebinde').select('*').eq('auftrag_id', auftragId).order('kaliber_idx'),
    supabase.from('schimmel_messung')
      .select('id, kg, ts, palox_stand_kg, brutto_kg, kisten, gebindeart, mit_palette, bemerkung')
      .eq('auftrag_id', auftragId).order('ts'),
    supabase.from('ausschuss_messung').select('id, art, kg, ts, gemessen, brutto_kg, kisten')
      .eq('auftrag_id', auftragId).order('ts'),
    supabase.from('ausgang_wiegung').select('id').eq('auftrag_id', auftragId),
    supabase.from('v_auftrag_angabe').select('schluessel, wert').eq('auftrag_id', auftragId),
    einstellung<number>('kisten_pro_palette', 32),
  ])
  if (a.error) throw a.error
  const auftrag = a.data as Auftrag | null
  if (!auftrag) return null
  const charge = chargen.find(c => c.nr === auftrag.charge_nr)

  // Die Fassung, nach der die Arbeit läuft — Bänder oder Sollgewicht. Ohne
  // Fassung gelten die Bänder der Sorte aus den Stammdaten.
  let fassung: Fassung | null = null
  if (auftrag.sortierschema_id !== null) {
    const { data } = await supabase.from('sortierschema')
      .select('id, art, soll_kg_pro_kiste, kaliber_baender, gilt_ab, kaeufer')
      .eq('id', auftrag.sortierschema_id).maybeSingle()
    fassung = (data as Fassung | null) ?? null
  }
  let baender: [number, number][] = fassung?.kaliber_baender ?? []
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
    fassung,
    kistenProPalette: Number(kpp) > 0 ? Number(kpp) : 32,
  }
}

/**
 * Was an dieser Station überhaupt anfällt (docs/ABLAUF.md).
 *
 * Fax (0051) ist kein Waschgang: keine Paletten, kein Palox, kein zu klein /
 * zu gross — gezählt werden die gemachten Kisten, gewogen wird das Faule.
 */
export function stationsProfil(a: Auftrag) {
  const fax = a.ist_fax
  return {
    istFax: fax,
    hatPaletten: a.station !== 'waschen',
    hatKisten: a.station !== 'waschen_sortieren',
    /** Ohne gezählte Kisten hat die Arbeit keine Menge (Waschen und Fax). */
    kistenPflicht: a.station === 'waschen',
    mitWiegen: a.station === 'waschen_sortieren',
    hatAusschuss: a.weg === 'hand' && !fax,
    hatAusgang: !fax && (a.station === 'waschen' || a.station === 'waschen_sortieren'),
    hatPalox: !fax,
    hatFaule: fax,
  }
}

export const uhrzeit = (ts: string, gebietsschema: string) =>
  new Date(ts).toLocaleTimeString(gebietsschema, { hour: '2-digit', minute: '2-digit' })
