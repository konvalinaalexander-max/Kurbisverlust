/**
 * Runde BF: Fall für Fall. Der Betrieb, 24. Oktober, zum Reiter Perigon: „Es
 * ist irgendwie Information Overload. Mach es angenehmer, verständlicher …
 * damit ich Fall für Fall angenehm abarbeiten kann. Den Fall verstehe, sehe,
 * was passiert ist. Und du musst uns auch nicht 1000 Lösungsvorschläge
 * vorschlagen … wichtiger ist, dass wir verstehen, was passiert ist." Und:
 * „wenn du sagst, so viel ist Eingang, so viel ist Ausgang, das kann nicht
 * sein … dann gib kurz an, warum — was genau die Logik dahinter ist:
 * Verdunstung, Palox, aussortieren … wenn die Dinge so 300 Kilo sind, haben
 * wir vielleicht Zweifel, ob du überhaupt richtig rechnest."
 *
 * Ein Fall ist eine Frage an den Chef — nicht eine Zeile der Datenbank:
 *  - je Charge, bei der herein und hinaus nicht aufgehen, alles zu ihr in
 *    einem Fall (vor dem Eingang verkauft, mehr verkauft als möglich, nie
 *    eingegangen, Paletten wohl von einer anderen Charge, umgebucht). Die
 *    Perigon-Zeilen „vor dem Eingang" derselben Charge sind ihre Belege —
 *    bis Runde BE standen sie zweimal da, je Position und je Charge;
 *  - je Art eines Fehlers in der Perigon-Datei alle Positionen dieser Art
 *    (die Frage ist dieselbe: „35-mal Mix auf einer Charge — stimmt das?"),
 *    jede einzeln anzusehen;
 *  - je Sache im Chargenregister.
 * „Lieferscheine ohne Charge je Sorte" ist Auskunft: Ihre Ursachen stehen als
 * Fälle der Perigon-Datei da (keine Nummer, Rest, Spalte S = 0 …).
 *
 * Hier steht ohne React (test/faelle.test.ts prüft es): wie die Fälle
 * entstehen, wie es um sie steht, was passiert ist (in Sätzen), und die
 * Rückrechnung einer Überzählung aus der Kaskade.
 */
import type { ChargeSpur, PerigonBefund, PerigonVerlauf, UngereimtZeile, VermerkStand } from './daten'
import type { Schwere, Ungereimtheit } from './ungereimt'
import { PERIGON_ART, betroffen, istOffen, standVon } from './perigon.ts'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format.ts'

export type FallTyp = 'charge' | 'art' | 'register' | 'auskunft'
/** Worum es geht — die Überschriften der Liste, in dieser Folge. */
export type Thema = 'menge' | 'datei' | 'artikel' | 'register' | 'auskunft'
export const THEMA_FOLGE: Thema[] = ['menge', 'datei', 'artikel', 'register', 'auskunft']
export const THEMA_NAME: Record<Thema, string> = {
  menge: 'Herein und hinaus gehen nicht auf',
  datei: 'Fehler in der Perigon-Datei',
  artikel: 'Artikel, Label, Mix',
  register: 'Chargenregister',
  auskunft: 'Zur Auskunft',
}

export interface Fall {
  /** die Kennung, unter der der Fall seine Nummer trägt (0127): charge:<nr>, art:<art>, Schlüssel der Sache */
  id: string
  typ: FallTyp
  thema: Thema
  /** wer: „Charge 1626 · Tiana", „Kürbis Mix auf einer Charge" */
  titel: string
  /** in wenigen Worten, was nicht aufgeht — die zweite Zeile in der Liste */
  unter: string
  schwere: Schwere
  /** die Kilo, um die es geht — bei einer Charge das Grösste ihrer Sachen (sie überschneiden sich), nie 0 statt unbekannt */
  kg: number | null
  /** die Schlüssel, an denen Stand und Vermerk hängen (perigon_vermerk) — ohne die blosse Auskunft */
  teile: string[]
  sachen: Ungereimtheit[]
  befunde: PerigonBefund[]
  charge_nr: number | null
  sorte: string | null
  /** die Art der Perigon-Zeilen (typ art) oder der Sache (register, auskunft) */
  art: string | null
}

/** Was je Charge zu einem Fall zusammengehört. */
const CHARGE_ARTEN = new Set(['ueberzaehlung', 'ohne_eingang', 'vor_eingang', 'vorschlag', 'umgebucht', 'nachgeordnet'])
/** Die Perigon-Zeilen, deren Frage die Datei selbst betrifft — Mengen, Nummern, Gewicht. */
const DATEI_ARTEN = new Set(['menge_null', 'zu_viel', 'rest', 'keine_nummer', 'unbekannt', 'mehrdeutig', 'ohne_gewicht', 'masse_abweichung'])
/** Was nur Auskunft ist: es erledigt sich von selbst oder ist kein Fehler. */
const AUSKUNFT_ARTEN = new Set(['nachholen', 'ruecknahme'])

const RANG: Record<Schwere, number> = { rot: 0, gelb: 1, info: 2 }
const schwerste = (xs: { schwere: Schwere }[]): Schwere =>
  xs.some(x => x.schwere === 'rot') ? 'rot' : xs.some(x => x.schwere === 'gelb') ? 'gelb' : 'info'
const stueck = (k: number, ein: string, mehr: string) => `${zahl(k)} ${k === 1 ? ein : mehr}`
const n = (x: unknown): number | null => (x === null || x === undefined || x === '' ? null : Number(x))
const kurzTag = (iso: string | null | undefined) => {
  if (!iso) return ''
  const [, mo, ta] = iso.slice(0, 10).split('-')
  return `${Number(ta)}.${Number(mo)}.`
}
/** „2.9.–14.10." oder „23.9." */
export const spanne = (von: string | null | undefined, bis: string | null | undefined) =>
  !von ? '' : bis && bis.slice(0, 10) !== von.slice(0, 10) ? `${kurzTag(von)}–${kurzTag(bis)}` : kurzTag(von)

/** In wenigen Worten, was eine Sache je Charge sagt — für die zweite Zeile der Liste. */
function sacheKurz(u: Ungereimtheit): string {
  const m = u.roh?.mehr ?? {}
  switch (u.art) {
    case 'ueberzaehlung': return `${tonnen(u.kg)} mehr verkauft, als möglich`
    case 'ohne_eingang': return 'verkauft, aber nie eingegangen'
    case 'vor_eingang': return `${tonnen(u.kg)} vor dem Eingang verkauft`
    case 'vorschlag': return `Paletten wohl von ${n(m.von_charge_nr) ?? '?'}`
    case 'umgebucht': return `Paletten von ${n(m.von_charge_nr) ?? '?'} umgebucht`
    case 'nachgeordnet': return 'Nummer über den Produzenten zugeordnet'
    default: return u.titel
  }
}

/**
 * Aus den Sachen je Charge (v_ungereimtheit, schon in Sätzen) und den
 * Perigon-Zeilen (v_perigon_befund) die Fälle — das Wichtigste zuerst: nach
 * Thema, dann rot vor gelb, dann die grössten.
 */
export function faelleBilden(befunde: PerigonBefund[], sachen: Ungereimtheit[], spur: ChargeSpur[] = []): Fall[] {
  const spurVon = new Map(spur.map(s => [s.charge_nr, s]))
  const jeCharge = new Map<number, { sachen: Ungereimtheit[]; befunde: PerigonBefund[] }>()
  const faelle: Fall[] = []
  for (const u of sachen) {
    if (CHARGE_ARTEN.has(u.art) && u.charge_nr != null) {
      const c = jeCharge.get(u.charge_nr) ?? { sachen: [], befunde: [] }
      c.sachen.push(u)
      jeCharge.set(u.charge_nr, c)
    } else if (u.art === 'stammdaten') {
      faelle.push({ id: u.schluessel, typ: 'register', thema: 'register', titel: u.titel, unter: 'im Chargenregister', schwere: u.schwere,
                    kg: u.kg, teile: u.schwere === 'info' ? [] : [u.schluessel], sachen: [u], befunde: [], charge_nr: u.charge_nr, sorte: u.sorte, art: u.art })
    } else {
      // Lieferscheine ohne Charge je Sorte (und was sonst kommt): Auskunft — die Ursachen sind Fälle der Datei
      faelle.push({ id: u.schluessel, typ: 'auskunft', thema: 'auskunft', titel: u.titel, unter: 'zur Auskunft', schwere: 'info',
                    kg: u.kg, teile: [], sachen: [u], befunde: [], charge_nr: u.charge_nr, sorte: u.sorte, art: u.art })
    }
  }
  const jeArt = new Map<string, PerigonBefund[]>()
  for (const b of befunde) {
    const c = b.charge_nr != null ? jeCharge.get(b.charge_nr) : undefined
    if (b.art === 'vor_eingang' && c?.sachen.some(u => u.art === 'vor_eingang')) { c.befunde.push(b); continue }
    jeArt.set(b.art, [...(jeArt.get(b.art) ?? []), b])
  }
  for (const [nr, c] of jeCharge) {
    const ernst = c.sachen.filter(u => u.schwere !== 'info')
    const s = spurVon.get(nr)
    const sorte = c.sachen[0]?.sorte ?? s?.sorte ?? null
    const reihe = [...c.sachen].sort((a, b) => RANG[a.schwere] - RANG[b.schwere] || (betroffen(b) ?? -1) - (betroffen(a) ?? -1))
    faelle.push({
      id: `charge:${nr}`, typ: 'charge', thema: ernst.length ? 'menge' : 'auskunft',
      titel: `Charge ${nr}${sorte ? ` · ${sorte}` : ''}`,
      unter: (ernst.length ? reihe.filter(u => u.schwere !== 'info') : reihe).sort((a, b) => ERZAEHLT.indexOf(a.art) - ERZAEHLT.indexOf(b.art)).map(sacheKurz).join(' · '),
      schwere: schwerste(ernst.length ? ernst : [{ schwere: 'info' }]),
      kg: ernst.length ? Math.max(...ernst.map(u => betroffen(u) ?? 0)) || null : null,
      teile: [...ernst.map(u => u.schluessel), ...c.befunde.map(b => b.schluessel)],
      sachen: reihe, befunde: c.befunde, charge_nr: nr, sorte, art: null,
    })
  }
  for (const [art, liste] of jeArt) {
    const info = PERIGON_ART[art as keyof typeof PERIGON_ART]
    const auskunft = AUSKUNFT_ARTEN.has(art) || liste.every(b => b.schwere === 'info')
    const reihe = [...liste].sort((a, b) => (betroffen(b) ?? -1) - (betroffen(a) ?? -1) || b.datum.localeCompare(a.datum))
    const kgs = reihe.map(betroffen)
    const daten = reihe.map(b => b.datum).sort()
    const eine = reihe.length === 1 ? reihe[0] : null
    faelle.push({
      id: `art:${art}`, typ: 'art', thema: auskunft ? 'auskunft' : DATEI_ARTEN.has(art) ? 'datei' : 'artikel',
      titel: info?.name ?? art,
      unter: eine ? `${datum(eine.datum)} · ${eine.kunde ?? 'Kunde unbekannt'} · Position ${eine.pos_id}`
        : `${stueck(reihe.length, 'Lieferschein', 'Lieferscheine')} · ${spanne(daten[0], daten[daten.length - 1])}`,
      schwere: auskunft ? 'info' : schwerste(reihe),
      kg: kgs.some(x => x != null) ? kgs.reduce<number>((a, x) => a + (x ?? 0), 0) : null,
      teile: auskunft ? [] : reihe.map(b => b.schluessel),
      sachen: [], befunde: reihe, charge_nr: eine?.charge_nr ?? null, sorte: eine?.sorte ?? null, art,
    })
  }
  return faelle.sort((a, b) => THEMA_FOLGE.indexOf(a.thema) - THEMA_FOLGE.indexOf(b.thema) || RANG[a.schwere] - RANG[b.schwere]
    || (b.kg ?? -1) - (a.kg ?? -1) || a.titel.localeCompare(b.titel))
}

/* ---------- Wie es um einen Fall steht ---------------------------------- */

/**
 * Der Stand eines Falls aus den Ständen seiner Teile: erledigt, wenn alle
 * erledigt sind (kein Fehler, wenn alle das sind); in Abklärung, sobald einer
 * es ist; sonst offen. Ein Fall ohne Teile (Auskunft) ist offen — er zählt
 * aber nirgends als offen (fallOffen).
 */
export function fallStand(f: Pick<Fall, 'teile'>, verlauf: Map<string, PerigonVerlauf>): VermerkStand {
  const st = f.teile.map(s => standVon(verlauf, s))
  if (st.length === 0) return 'offen'
  if (st.every(s => s === 'kein_fehler')) return 'kein_fehler'
  if (st.every(s => s === 'erledigt' || s === 'kein_fehler')) return 'erledigt'
  if (st.some(s => s === 'in_abklaerung')) return 'in_abklaerung'
  return 'offen'
}
/** Wie viele Teile schon erledigt sind — „12 von 35" bei einem Fall mit vielen Positionen. */
export function fallFortschritt(f: Pick<Fall, 'teile'>, verlauf: Map<string, PerigonVerlauf>): { fertig: number; von: number } {
  return { fertig: f.teile.filter(s => ['erledigt', 'kein_fehler'].includes(standVon(verlauf, s))).length, von: f.teile.length }
}
/** Offen heisst: nicht nur Auskunft, und weder erledigt noch „kein Fehler". */
export function fallOffen(f: Pick<Fall, 'teile' | 'schwere'>, verlauf: Map<string, PerigonVerlauf>): boolean {
  return f.teile.length > 0 && istOffen(f.schwere, fallStand(f, verlauf))
}

export type FallFilter = { stand: 'offen' | 'abklaerung' | 'erledigt' | 'alle'; suche: string; art: string; charge: number | null; sorte: string }
export const FALL_FILTER_LEER: FallFilter = { stand: 'offen', suche: '', art: '', charge: null, sorte: '' }

/** Die Fälle, die zum Filter passen — Stand, Art, Charge (auch in den Positionen), Sorte, Suche. */
export function faelleFiltern(faelle: Fall[], verlauf: Map<string, PerigonVerlauf>, f: FallFilter): Fall[] {
  const s = f.suche.trim().toLowerCase()
  return faelle.filter(x => {
    const st = fallStand(x, verlauf)
    if (f.stand === 'offen' && !fallOffen(x, verlauf)) return false
    if (f.stand === 'abklaerung' && st !== 'in_abklaerung') return false
    if (f.stand === 'erledigt' && st !== 'erledigt' && st !== 'kein_fehler') return false
    if (f.art && x.art !== f.art && !x.sachen.some(u => u.art === f.art) && !x.befunde.some(b => b.art === f.art)) return false
    if (f.charge != null && x.charge_nr !== f.charge && !x.befunde.some(b => b.charge_nr === f.charge || (b.nummern ?? '').split(', ').includes(String(f.charge)))
        && !x.sachen.some(u => u.beteiligt.includes(f.charge!) || u.von_charge_nr === f.charge)) return false
    if (f.sorte && x.sorte !== f.sorte && !x.befunde.some(b => b.sorte === f.sorte) && !x.sachen.some(u => u.sorte === f.sorte)) return false
    if (!s) return true
    const worte = [x.titel, x.unter, x.charge_nr, x.sorte, ...x.befunde.flatMap(b => [b.artikel, b.kunde, b.nummern, b.charge_nr, b.pos_id, b.sorte]),
                   ...x.sachen.flatMap(u => [u.titel, u.charge_nr, u.von_charge_nr, u.sorte])]
    return worte.some(v => v != null && String(v).toLowerCase().includes(s))
  })
}

/* ---------- Was passiert ist -------------------------------------------- */

export interface Geschichte {
  /** herein und hinaus, je ein Satz — nur bei einer Charge */
  herein: string | null
  hinaus: string | null
  /** was nicht aufgeht, je Sache ein Satz — in der Folge, in der man es erzählt, mit der Schwere der Sache */
  punkte: { text: string; schwere: Schwere }[]
  /** was das für die Zahlen der App heisst — ein Satz, kein Vorschlag */
  folge: string | null
}

const PALETTE = (k: number) => stueck(k, 'Palette', 'Paletten')
/** Die Folge, in der die Sachen einer Charge erzählt werden. */
const ERZAEHLT = ['vor_eingang', 'ohne_eingang', 'ueberzaehlung', 'vorschlag', 'umgebucht', 'nachgeordnet']

/** Ein Fall in Sätzen: was herein- und hinausging, was nicht aufgeht, was das für die Zahlen heisst. */
export function geschichte(f: Fall, spur: Map<number, ChargeSpur>): Geschichte {
  if (f.typ === 'charge') return chargeGeschichte(f, f.charge_nr != null ? spur.get(f.charge_nr) : undefined)
  if (f.typ === 'art') return artGeschichte(f)
  const u = f.sachen[0]
  return { herein: null, hinaus: null, punkte: u ? [{ text: u.was, schwere: u.schwere }] : [], folge: u?.warum || null }
}

function chargeGeschichte(f: Fall, s: ChargeSpur | undefined): Geschichte {
  const nr = f.charge_nr
  const herein = !s ? null
    : s.journal_paletten > 0
      ? `Herein: ${PALETTE(s.journal_paletten)} mit ${tonnen(n(s.journal_kg))} laut Erntejournal (${spanne(s.journal_von, s.journal_bis)}).`
        + (s.her ?? []).filter(h => h.stand === 'angewandt').map(h => ` Dazu zählt die App ${PALETTE(h.paletten)} von ${h.charge_nr}, umgebucht mit Beleg.`).join('')
      : `Herein: Im Erntejournal steht unter ${nr} keine einzige Palette.`
        + (s.her ?? []).filter(h => h.stand === 'angewandt').map(h => ` Die App zählt ${PALETTE(h.paletten)} von ${h.charge_nr} hier, umgebucht mit Beleg.`).join('')
  const hinaus = !s ? null
    : s.lieferscheine > 0
      ? `Hinaus: ${stueck(s.lieferscheine, 'Lieferschein', 'Lieferscheine')} mit ${tonnen(n(s.geliefert_kg))} unter der Nummer ${nr} laut Perigon (${spanne(s.lief_von, s.lief_bis)}).`
      : `Hinaus: In Perigon steht unter ${nr} kein Lieferschein.`
  const punkte: Geschichte['punkte'] = []
  const p = (text: string, u: Ungereimtheit) => punkte.push({ text, schwere: u.schwere })
  let folge: string | null = null
  // erzählt wird in der Folge der Dinge: was vor dem Eingang ging, was ohne Eingang, was zu viel, und woher es kommen könnte
  const reihe = [...f.sachen].sort((a, b) => ERZAEHLT.indexOf(a.art) - ERZAEHLT.indexOf(b.art))
  for (const u of reihe) {
    const m = u.roh?.mehr ?? {}
    switch (u.art) {
      case 'vor_eingang': {
        const erst = typeof m.erster_eingang === 'string' ? m.erster_eingang : s?.journal_von ?? null
        p(`${stueck(u.roh?.n ?? 0, 'Lieferschein', 'Lieferscheine')} mit ${tonnen(u.kg)} ${(u.roh?.n ?? 0) === 1 ? 'ist' : 'sind'} älter als die erste Palette (${datum(erst)}) — damals war die Charge noch gar nicht da.`, u)
        folge ??= `Die App zieht diese Lieferscheine trotzdem von ${nr} ab.`
        break
      }
      case 'ueberzaehlung': {
        const gel = n(m.geliefert_kg), ein = n(m.eingang_kg), aus = n(m.ausgelagert_kg)
        p(`Für ${tonnen(gel)} auf den Lieferscheinen braucht es ${tonnen(aus)} Eingang, denn unterwegs geht Ware verloren (Verdunstung, Faules, Aussortiertes). Hereingekommen sind ${tonnen(ein)} — es fehlen ${tonnen(u.kg)}.`, u)
        folge = `Die fehlenden ${tonnen(u.kg)} zieht die App von keinem Lager ab.`
        break
      }
      case 'ohne_eingang':
        p(`${stueck(u.roh?.n ?? 0, 'Lieferschein', 'Lieferscheine')} mit ${tonnen(u.kg)} — aber kein Eingang. Diese Ware kann nicht von ${nr} sein.`, u)
        folge = `Diese ${tonnen(u.kg)} zieht die App von keinem Lager ab; dort, wo die Ware herkam, steht sie noch im Lager.`
        break
      case 'vorschlag':
      case 'umgebucht':
      case 'nachgeordnet': {
        const grund = typeof m.grund === 'string' ? m.grund.replace(/\.?$/, '.') : u.was
        p(u.art === 'umgebucht' ? `Umgebucht: ${grund}` : grund, u)
        break
      }
      default: p(u.was, u)
    }
  }
  return { herein, hinaus, punkte, folge }
}

/** Je Art der Perigon-Zeilen, was „N Lieferscheine …" tun — der Satz nach der Zahl. */
const ART_SATZ: Record<string, string> = {
  menge_null: 'nennen Chargen, teilen ihnen aber keine Menge zu (Spalte S = 0)',
  zu_viel: 'teilen den Chargen zusammen mehr zu, als die Position geliefert hat — meist steht dieselbe Zeile zwei- oder dreimal in der Datei',
  rest: 'teilen den Chargen weniger zu, als die Position geliefert hat; der Rest hat keine Charge',
  keine_nummer: 'haben keine Chargennummer (Spalte W ist leer)',
  unbekannt: 'nennen eine Nummer, die an keiner Charge steht',
  mehrdeutig: 'nennen eine Perigon-Nummer, die an mehreren Chargen steht',
  ohne_gewicht: 'sind in Stück verkauft, ohne Gewicht je Stück',
  masse_abweichung: 'ergeben in der App eine andere Masse als in der Datei',
  mix: 'verkaufen einen „Kürbis Mix", gebucht auf eine einzige Charge',
  artikel_sorte: 'verkaufen einen Artikel, der nicht zur Sorte der genannten Charge passt',
  label_name: 'tragen im Artikelnamen ein anderes Label als in der Preisgruppe',
  demeter_knospe: 'sind als Demeter verkauft; die Charge trägt das Lieferlabel Knospe',
  vor_eingang: 'sind älter als die erste Palette ihrer Charge',
  nachholen: 'nannten eine Nummer, die die App beim Einlesen noch nicht kannte — inzwischen steht sie an einer Charge',
  ruecknahme: 'haben eine negative Menge — Ware kam zurück',
}

function artGeschichte(f: Fall): Geschichte {
  const info = f.art ? PERIGON_ART[f.art as keyof typeof PERIGON_ART] : undefined
  const k = f.befunde.length
  if (k === 1) return { herein: null, hinaus: null, punkte: [{ text: f.befunde[0].satz, schwere: f.befunde[0].schwere }], folge: info?.app ?? null }
  const daten = f.befunde.map(b => b.datum).sort()
  const nummern = [...new Set(f.befunde.map(b => b.nummer ?? b.nummern).filter((x): x is string => !!x))]
  // Wo viele auf wenige Nummern gehen (Mix), steht, welche — die drei häufigsten
  const haeufig = [...nummern.map(nr => [nr, f.befunde.filter(b => (b.nummer ?? b.nummern) === nr).length] as const)]
    .sort((a, b) => b[1] - a[1]).slice(0, 3)
  const welche = ['mix', 'unbekannt', 'mehrdeutig', 'artikel_sorte', 'demeter_knospe'].includes(f.art ?? '') && haeufig.length
    ? ` — am häufigsten ${haeufig.map(([nr, x]) => `${nr} (${x}-mal)`).join(', ')}` : ''
  return {
    herein: null, hinaus: null,
    punkte: [{ text: `${stueck(k, 'Lieferschein', 'Lieferscheine')} vom ${spanne(daten[0], daten[k - 1])}${f.kg != null ? `, zusammen ${tonnen(f.kg)},` : ''} ${ART_SATZ[f.art ?? ''] ?? info?.heisst ?? ''}${welche}.`, schwere: f.schwere }],
    folge: info?.app ?? null,
  }
}

/* ---------- Die Rückrechnung einer Überzählung --------------------------- */

/** Eine Zeile der Kaskade (mv_kaskade, portion ausgelagert): was von einer Kohorte der Charge auf die Lieferscheine ging. */
export interface KaskadeZeile {
  m0: number | null; m1: number | null; m2: number | null; alter_tage: number | null; r: number | null
  f: number | null; a_klein_n: number | null; a_gross_n: number | null; a_fax: number | null; hagel: number | null
  verdunstung_kg: number | null; schimmel_kg: number | null; klein_kg: number | null; nebenkanal_kg: number | null
  fax_kg: number | null; geliefert_kg: number | null
  r_basis: string | null; f_quelle: string | null; klein_basis: string | null; gross_basis: string | null
}

export type Strom = 'verkauft' | 'ausschuss' | 'nebenkanal' | 'schimmel' | 'verdunstung' | 'fax'
export interface Schritt {
  strom: Strom
  was: string
  kg: number
  /** der Anteil, wie die Kaskade ihn rechnet — je vom Rest davor */
  anteil: number | null
  /** wie es gerechnet ist, in Worten */
  wie: string
  /** woher der Wert kommt (gemessen an …) */
  woher: string | null
}
export interface Rueckrechnung {
  geliefertKg: number
  /** in der Folge rückwärts: vom Lieferschein zum Eingang */
  schritte: Schritt[]
  gebrauchtKg: number
  eingangKg: number | null
  /** gebraucht − Eingang; über 0 heisst: es fehlt Eingang */
  fehltKg: number | null
  /** was unterwegs verloren geht, als Anteil des Gebrauchten */
  verlustAnteil: number
  /** wie viel die Charge höchstens verlieren dürfte, damit es aufgeht — leer, wenn es schon ohne Verlust nicht aufgeht */
  erlaubtAnteil: number | null
  ohneVerlustZuViel: boolean
}

const summe = (xs: KaskadeZeile[], k: keyof KaskadeZeile) => xs.reduce((a, x) => a + (Number(x[k]) || 0), 0)

/**
 * Die Kaskade rückwärts, wie die Datenbank sie gerechnet hat (mv_kaskade):
 * was auf den Lieferscheinen steht, plus was beim Sortieren zu klein und zu
 * gross herausfiel, plus das Faule im Palox, plus was im Lager verdunstete —
 * gibt den Eingang, den es dafür brauchte. Hier wird nichts neu gerechnet,
 * nur zusammengezählt und in Worte gefasst; die Anteile sind die der
 * Kaskade, je vom Rest davor (HERLEITUNG 11).
 */
export function rueckrechnung(zeilen: KaskadeZeile[], eingangKg: number | null): Rueckrechnung | null {
  if (zeilen.length === 0) return null
  const m0 = summe(zeilen, 'm0'), m1 = summe(zeilen, 'm1'), m2 = summe(zeilen, 'm2')
  const geliefert = summe(zeilen, 'geliefert_kg')
  if (m0 <= 0) return null
  const verd = summe(zeilen, 'verdunstung_kg'), faul = summe(zeilen, 'schimmel_kg')
  const klein = summe(zeilen, 'klein_kg'), gross = summe(zeilen, 'nebenkanal_kg'), fax = summe(zeilen, 'fax_kg')
  // die Lagerdauer, gewichtet mit der Masse jeder Kohorte
  const tage = zeilen.reduce((a, z) => a + (Number(z.m0) || 0) * (Number(z.alter_tage) || 0), 0) / m0
  const r = zeilen.find(z => z.r != null)?.r ?? null
  const z0 = zeilen[0]
  const hagel = Math.max(...zeilen.map(z => Number(z.hagel) || 0))
  const schritte: Schritt[] = []
  if (klein > 0.5) schritte.push({ strom: 'ausschuss', was: 'zu klein aussortiert', kg: klein, anteil: m2 > 0 ? klein / m2 : null,
    wie: 'beim Sortieren unter dem kleinsten Artikel — geht an die Tiere', woher: z0.klein_basis })
  if (gross > 0.5) schritte.push({ strom: 'nebenkanal', was: 'zu gross aussortiert', kg: gross, anteil: m2 > 0 ? gross / m2 : null,
    wie: 'beim Sortieren über dem grössten Artikel — bleibt im Haus, ist nicht verkauft', woher: z0.gross_basis })
  if (fax > 0.5) schritte.push({ strom: 'fax', was: 'faul beim Abpacken', kg: fax, anteil: null, wie: 'beim Etikettieren aussortiert', woher: null })
  if (faul > 0.5) schritte.push({ strom: 'schimmel', was: 'Faules in den Palox', kg: faul, anteil: m1 > 0 ? faul / m1 : null,
    wie: `beim Waschen und Sortieren aussortiert${hagel > 0 ? `, darin Hagel ${prozent(hagel)}` : ''}`, woher: z0.f_quelle })
  if (verd > 0.5) schritte.push({ strom: 'verdunstung', was: 'im Lager verdunstet', kg: verd, anteil: verd / m0,
    wie: r != null ? `${prozent(Number(r), 2)} je Tag, im Mittel ${zahl(Math.round(tage))} Tage gelagert` : `im Mittel ${zahl(Math.round(tage))} Tage gelagert`,
    woher: z0.r_basis })
  const ein = eingangKg == null ? null : Number(eingangKg)
  return {
    geliefertKg: geliefert, schritte, gebrauchtKg: m0, eingangKg: ein,
    fehltKg: ein == null ? null : m0 - ein,
    verlustAnteil: 1 - geliefert / m0,
    erlaubtAnteil: ein == null || ein <= 0 || geliefert > ein ? null : 1 - geliefert / ein,
    ohneVerlustZuViel: ein != null && geliefert > ein,
  }
}

/**
 * Wie sicher der Unterschied ist, in einem Satz: Geht es schon ohne jeden
 * Verlust nicht auf, liegt es nicht an der Rechnung. Sonst: wie viel die
 * Charge höchstens verlieren dürfte, wie viel gerechnet ist und was davon
 * am meisten ausmacht — damit man selbst urteilen kann.
 */
export function wieSicher(r: Rueckrechnung): string {
  if (r.eingangKg == null) return 'Ohne Eingang lässt sich nichts gegenrechnen.'
  if (r.ohneVerlustZuViel)
    return `Das geht schon ohne jeden Verlust nicht auf: hinaus ${tonnen(r.geliefertKg)}, herein ${tonnen(r.eingangKg)}. Hier stimmt sicher etwas nicht — an der Rechnung liegt es nicht.`
  const gross = [...r.schritte].sort((a, b) => b.kg - a.kg)[0]
  return `Ohne Verlust ginge es auf (hinaus ${tonnen(r.geliefertKg)}, herein ${tonnen(r.eingangKg)}). Damit es auch mit Verlust aufgeht, dürfte die Charge höchstens ${prozent(r.erlaubtAnteil)} verlieren — gerechnet sind ${prozent(r.verlustAnteil)}`
    + (gross ? `, am meisten ${gross.was.replace(/^im Lager /, '')} (${kg(gross.kg, 0)}).` : '.')
}

/* ---------- Die Zeitleiste „vor dem Eingang" ----------------------------- */

export interface ZeitPunkt { datum: string; kg: number; vor: boolean }
export interface Zeitleiste { von: string; bis: string; eingang: string | null; punkte: ZeitPunkt[]; vorKg: number; nachKg: number }

/** Die Lieferscheine einer Charge auf einer Zeitachse, mit dem Tag der ersten Palette dazwischen. */
export function zeitleiste(lieferscheine: { datum: string; kg: number | null }[], eingang: string | null): Zeitleiste | null {
  const p = lieferscheine.filter(l => l.datum).map(l => ({ datum: l.datum.slice(0, 10), kg: Number(l.kg) || 0, vor: eingang != null && l.datum.slice(0, 10) < eingang.slice(0, 10) }))
  if (p.length === 0) return null
  const tage = [...p.map(x => x.datum), ...(eingang ? [eingang.slice(0, 10)] : [])].sort()
  return { von: tage[0], bis: tage[tage.length - 1], eingang: eingang ? eingang.slice(0, 10) : null, punkte: p.sort((a, b) => a.datum.localeCompare(b.datum)),
           vorKg: p.filter(x => x.vor).reduce((a, x) => a + x.kg, 0), nachKg: p.filter(x => !x.vor).reduce((a, x) => a + x.kg, 0) }
}

/** Was eine Sache je Charge an Zahlen trägt — fürs Bild herein / hinaus. */
export function bilanz(f: Fall): { eingangKg: number | null; geliefertKg: number | null; gebrauchtKg: number | null } | null {
  const u = f.sachen.find(x => x.art === 'ueberzaehlung') ?? f.sachen.find(x => x.art === 'ohne_eingang')
  if (!u) return null
  const m: UngereimtZeile['mehr'] = u.roh?.mehr ?? {}
  if (u.art === 'ohne_eingang') return { eingangKg: 0, geliefertKg: u.kg, gebrauchtKg: null }
  return { eingangKg: n(m?.eingang_kg), geliefertKg: n(m?.geliefert_kg), gebrauchtKg: n(m?.ausgelagert_kg) }
}
