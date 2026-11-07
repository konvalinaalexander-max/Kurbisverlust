/**
 * 0134: Was die Überzählung einer Charge ist, und was eine am Lager leer
 * bestätigte Charge über die Raten sagt — in Sätzen, aus v_charge_bedarf.
 *
 * Der Betrieb am 7. November: „sicher ein Datenfehler", wenn mehr geliefert
 * als hereingekommen ist; „die Rate passt nicht zur Charge", und das nur,
 * wenn die Lieferungen ausserhalb der Spanne liegen. Ist die Charge leer,
 * „gilt Eingang minus geliefert als echter Verlust, und damit prüft die App
 * ihre Raten".
 *
 * Kilo in Kilo, nicht in Tonnen: wer nachrechnet, soll dieselbe Zahl
 * bekommen (Runde BF).
 */
import { datum, kg, prozent } from '../lib/format.ts'
import type { ChargeBedarf } from './daten.ts'

const n = (x: unknown): number | null => (x === null || x === undefined || x === '' ? null : Number(x))

/** Wie die Raten heissen, mit denen gerechnet ist: „Verdunstung 0.05 % je Tag, Palox 8 %". */
export function ratenText(b: Pick<ChargeBedarf, 'r' | 'f'>): string {
  const r = n(b.r), f = n(b.f)
  return [
    r === null ? 'ohne gemessene Verdunstung' : `Verdunstung ${(r * 100).toFixed(2)} % je Tag`,
    f === null ? 'ohne Palox-Rate' : `Palox ${prozent(f, 0)}`,
  ].join(', ')
}

export interface UeberSatz {
  /** warnung: zu melden (Datenfehler, Rate); leise: in der Spanne — eine Auskunft, keine Meldung */
  ton: 'warnung' | 'leise'
  /** das Wort auf der Marke */
  marke: string
  /** der Satz danach */
  satz: string
}

/** Was die Überzählung einer Charge ist; null, wenn es aufgeht. */
export function ueberzaehlungSatz(b: ChargeBedarf | undefined): UeberSatz | null {
  if (!b || !b.art) return null
  const ein = n(b.eingang_kg) ?? 0, gel = n(b.geliefert_kg) ?? 0
  const bed = n(b.bedarf_kg), bu = n(b.bedarf_min_kg), bo = n(b.bedarf_max_kg)
  if (b.art === 'datenfehler') return {
    ton: 'warnung', marke: `${kg(gel - ein, 0)} mehr geliefert als hereinkam`,
    satz: `Geliefert ${kg(gel, 0)}, hereingekommen ${kg(ein, 0)} — das erklärt keine Rate: sicher ein Datenfehler. Im Journal fehlt eine Palette, oder ein Lieferschein trägt die falsche Charge.`,
  }
  if (b.art === 'rate') return {
    ton: 'warnung', marke: 'Rate passt nicht zur Charge',
    satz: `Die Lieferungen (${kg(gel, 0)}) brauchen mit den Raten ${kg(bed, 0)} Eingang, auch günstig gerechnet noch ${kg(bu, 0)} — hereingekommen sind ${kg(ein, 0)}. Die Charge verliert wohl weniger als ihre Sorte (${ratenText(b)}), oder es fehlt eine Palette im Journal.`,
  }
  // spanne
  return {
    ton: 'leise', marke: 'in der Spanne',
    satz: bed !== null && bed > ein
      ? `Die Lieferungen brauchen mit den Raten ${kg(bed, 0)} Eingang, hereingekommen sind ${kg(ein, 0)} — innerhalb der Spanne der Raten (${kg(bu, 0)} bis ${kg(bo, 0)}); die App meldet das nicht.`
      : `Ein Eingangstag ist mit den Raten um ${kg(n(b.ueberzaehlung_kg), 0)} überzogen, die ganze Charge nicht (Bedarf ${kg(bed, 0)} von ${kg(ein, 0)}) — die App meldet das nicht.`,
  }
}

export interface LeerSatz {
  ton: 'fertig' | 'warnung' | 'leise'
  /** das Urteil in Worten */
  marke: string
  /** echter Verlust gegen gerechneten */
  satz: string
  /** Lieferscheine nach dem Leer-Tag, wenn es welche gibt */
  nachher: string | null
}

/** Was eine am Lager leer bestätigte Charge über ihre Raten sagt; null, wenn sie nicht leer ist. */
export function leerSatz(b: ChargeBedarf | undefined): LeerSatz | null {
  if (!b || !b.leer) return null
  const ein = n(b.eingang_kg) ?? 0, gel = n(b.geliefert_kg) ?? 0
  const echt = `Echter Verlust ${kg(n(b.echt_verlust_kg), 0)} = Eingang ${kg(ein, 0)} − geliefert ${kg(gel, 0)} (${prozent(n(b.echt_anteil))})`
  const gerechnet = b.gerechnet_anteil == null ? ''
    : `; die Raten rechneten ${prozent(n(b.gerechnet_anteil))} (${prozent(n(b.gerechnet_unten))} bis ${prozent(n(b.gerechnet_oben))})`
  const nachher = b.n_nach_leer > 0
    ? `${b.n_nach_leer === 1 ? 'Ein Lieferschein' : `${b.n_nach_leer} Lieferscheine`} mit ${kg(n(b.kg_nach_leer), 0)} ${b.n_nach_leer === 1 ? 'kam' : 'kamen'} nach dem ${datum(b.leer_am)} (zuerst am ${datum(b.erste_nach_leer)}) — war die Charge da schon leer, gehört ${b.n_nach_leer === 1 ? 'er' : 'sie'} wohl einer anderen.`
    : null
  switch (b.urteil) {
    case 'passt': return { ton: 'fertig', marke: 'Raten passen', satz: `${echt}${gerechnet} — das passt.`, nachher }
    case 'mehr_weg': return { ton: 'warnung', marke: 'mehr weg, als die Raten sagen', nachher,
      satz: `${echt}${gerechnet}. Mehr verloren, als die Raten erwarten (${ratenText(b)}) — oder Ware ging ohne Lieferschein hinaus.` }
    case 'weniger_weg': return { ton: 'warnung', marke: 'weniger weg, als die Raten sagen', nachher,
      satz: `${echt}${gerechnet}. Die Charge verlor weniger als ihre Sorte (${ratenText(b)}) — oder im Journal fehlt eine Palette.` }
    case 'datenfehler': return { ton: 'warnung', marke: 'mehr geliefert als hereinkam', nachher,
      satz: `Geliefert ${kg(gel, 0)}, hereingekommen ${kg(ein, 0)} — einen echten Verlust gibt es so nicht: sicher ein Datenfehler.` }
    case 'ohne_lieferung': return { ton: 'warnung', marke: 'leer ohne Lieferung', nachher,
      satz: `Unter dieser Nummer ging nichts hinaus, und doch ist die Charge leer: ${kg(ein, 0)} gingen unter einer anderen Charge hinaus oder ohne Lieferschein.` }
    case 'hagel': return { ton: 'leise', marke: 'Hagel-Charge', nachher,
      satz: `${echt}. Die Raten prüft hier der Ünique-Topf, nicht die einzelne Charge.` }
    default: return { ton: 'leise', marke: 'leer', satz: echt, nachher }
  }
}
