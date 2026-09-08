import { supabase } from '../lib/supabase'
import { einstellung, stammdaten } from '../lib/db'
import type { Auftrag, AuftragGebinde, Charge } from '../lib/typen'

/** Eine Schimmelmessung dieser Arbeit: Palox-Ablesung oder gewogene Kiste. */
export interface Ablesung {
  id: number; kg: number; ts: string; palox_stand_kg: number | null
  brutto_kg: number | null; kisten: number | null; gebindeart: string | null; mit_palette: boolean
  bemerkung: string | null
}
/** Zu klein / zu gross, je Palette gewogen (Waschen + Sortieren, am Ende). */
export interface AusschussZeile {
  id: number; art: 'zu_klein' | 'zu_gross'; kg: number; ts: string
  gemessen: boolean; brutto_kg: number | null; kisten: number | null; gebindeart: string | null; bemerkung: string | null
}
/** Eine gezählte Palette: am Eingang (Eingangsdatum, Zettelgewicht, Wägung) oder
 *  beim Waschen die Kaliber-Palette aus dem Zwischenlager (Sortierdatum, Kisten). */
export interface Palette {
  id: number; wiegung_id: number | null; eingangsdatum: string | null; brutto_zettel_kg: number | null
  sortierdatum: string | null; kisten: number | null
}
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
    supabase.from('auftrag_palette').select('id, wiegung_id, eingangsdatum, brutto_zettel_kg, sortierdatum, kisten')
      .eq('auftrag_id', auftragId).order('ts'),
    supabase.from('auftrag_gebinde').select('*').eq('auftrag_id', auftragId).order('kaliber_idx').order('sortierdatum'),
    supabase.from('schimmel_messung')
      .select('id, kg, ts, palox_stand_kg, brutto_kg, kisten, gebindeart, mit_palette, bemerkung')
      .eq('auftrag_id', auftragId).order('ts'),
    supabase.from('ausschuss_messung').select('id, art, kg, ts, gemessen, brutto_kg, kisten, gebindeart, bemerkung')
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

/** Wie viele fertige Paletten am Ende gewogen sein sollen — drei, und
 *  nicht mehr, als die Arbeit überhaupt hergibt (Runde H). */
export const FERTIGE_SOLL = 3
/** Wie viele Eingangspaletten beim Waschen + Sortieren gewogen sein sollen. */
export const WIEGEN_SOLL = 3

/**
 * Was an dieser Station überhaupt anfällt (docs/ABLAUF.md, Runde H).
 *
 * Zwei Stationen: Sortiermaschine und Waschstrasse. „Waschen + Sortieren" ist
 * die Waschstrasse mit Sortieren von Hand am Band dahinter — derselbe Palox.
 *
 *  Sortieren            Eingangspaletten mit Datum, Kisten je Kaliber, Palox (Pflicht)
 *  Waschen + Sortieren  Eingangspaletten mit Datum und Gewicht vom Zettel (Pflicht),
 *                       mindestens drei davon gewogen (erinnert), Palox (Pflicht),
 *                       am Ende zu klein / zu gross je Palette gewogen und
 *                       fertige Paletten (mindestens drei, erinnert)
 *  Waschen              Kaliber-Paletten aus dem Zwischenlager: Sortierdatum vom
 *                       Zettel und Kisten je Palette (Pflicht — die Menge), Palox
 *                       gefragt, nicht Pflicht; am Ende fertige Paletten (verlangt)
 *  Fax                  Faules kistenweise gewogen, Paletten als Gesamtzahl
 *
 * Zu klein / zu gross am Band kommt aus der Sortier-CSV; von Hand (Waschen +
 * Sortieren) wird es am Ende je Palette gewogen — dort gibt es keine CSV.
 */
export function stationsProfil(a: Auftrag) {
  const fax = a.ist_fax
  const rechenbar = a.kistensystem === 'kiste_ab' || a.kistensystem === 'stueck'
  const waschen = !fax && a.station === 'waschen'
  return {
    istFax: fax,
    /** Eingangspaletten zählen (Sortieren, Waschen + Sortieren). */
    hatPaletten: !fax && a.station !== 'waschen',
    /** Beim Waschen + Sortieren steht das Eingangsgewicht auf dem Zettel — Pflicht je Palette. */
    zettelGewichtPflicht: a.station === 'waschen_sortieren',
    /** Kaliber-Paletten aus dem Zwischenlager zählen: Sortierdatum und Kisten je Palette (Waschen). */
    hatWaschPaletten: waschen,
    /** Kisten je Kaliber zählen — nur noch beim Sortieren (die gefüllten). */
    hatKisten: !fax && a.station === 'sortieren',
    /** Eine Palette wiegen: wo Eingangspaletten gezählt werden. */
    mitWiegen: !fax && a.station !== 'waschen',
    /** Mindestens drei Eingangspaletten wiegen — bevor sie in die Waschmaschine kommen (erinnert, nicht erzwungen). */
    wiegenSoll: a.station === 'waschen_sortieren' ? WIEGEN_SOLL : 0,
    /** Zu klein / zu gross am Ende je Palette wiegen: nur von Hand (Waschen + Sortieren). */
    hatAusschuss: a.station === 'waschen_sortieren',
    /** Fertige Palette wiegen — nur, wenn das Kistensystem rechenbar ist. */
    hatAusgang: !fax && a.station !== 'sortieren' && rechenbar,
    /** Beim Waschen sind die fertigen Paletten die eine Messung am Ende: verlangt. */
    ausgangPflicht: waschen && rechenbar,
    hatPalox: !fax,
    /** Am Sortierband und an der Waschstrasse mit Sortieren ist der Palox Pflicht;
     *  beim Waschen aus Kisten gefragt, nicht Pflicht (der Nenner sind die gezählten Paletten). */
    paloxPflicht: !fax && a.station !== 'waschen',
    hatFaule: fax,
    /** Fax: die Palettenzahl als Gesamtzahl am Ende. */
    hatFaxPaletten: fax,
    kistensystemRechenbar: rechenbar,
  }
}

/** Wie viele fertige Paletten diese Arbeit mindestens gewogen haben soll:
 *  drei — oder weniger, wenn sie nicht mehr hergibt (Kisten ÷ Kisten je Palette). */
export function fertigeSoll(d: ArbeitDaten): number {
  const p = stationsProfil(d.auftrag)
  if (!p.hatAusgang) return 0
  const kisten = d.paletten.reduce((s, x) => s + (x.kisten ?? 0), 0)
  if (p.hatWaschPaletten && kisten > 0) return Math.max(1, Math.min(FERTIGE_SOLL, Math.ceil(kisten / d.kistenProPalette)))
  return FERTIGE_SOLL
}

export const uhrzeit = (ts: string, gebietsschema: string) =>
  new Date(ts).toLocaleTimeString(gebietsschema, { hour: '2-digit', minute: '2-digit' })
