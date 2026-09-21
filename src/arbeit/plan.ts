import type { TextId } from '../lib/i18n'
import type { Station } from '../lib/typen'

/**
 * Der Plan einer Arbeit in drei Blöcken: vor, während, nach (Runde T).
 *
 * Der Betrieb: „gleich zu beginn - nachdem man die art der arbeit abgelesen
 * hat - soll man auch eine übersicht kriegen was gemacht werden muss - also
 * nur kurz zum drüber lesen - und dann wird alles gefragt". Und der Grund
 * dafür: „dass die leitende person gleich zu beginn nochmals dran erinnert
 * wird - dass sie fertige paletten wiegen muss - und nicht erst am schluss
 * daran erinnert wird - dass sie noch 3 wägen muss".
 *
 * Bis hierher erfuhr der Vorarbeiter von den drei fertigen Paletten in einem
 * blauen Kasten am Ende des Assistenten und dann wieder erst im Abschluss —
 * wenn die Ware schon weg ist. Jetzt steht der ganze Weg vor dem ersten
 * Schritt, in derselben Reihenfolge, in der die App ihn nachher abfragt.
 *
 * Reine Funktion ohne Datenbank: Sie kennt die Station und weiss, ob das
 * Kistensystem rechenbar ist. Ist das noch nicht entschieden (im Assistenten
 * kommt die Frage erst später), gilt der Normalfall — die fertigen Paletten
 * stehen im Plan. Wer dann „anderes" wählt, sieht sie in der Checkliste
 * schlicht nicht; ein Punkt zu viel im Plan ist billiger als einer zu wenig.
 */
export interface PlanPunkt {
  text: TextId
  /** Nicht Pflicht — die App fragt, hält aber nicht auf. */
  freiwillig?: boolean
}
export interface Arbeitsplan {
  vorher: PlanPunkt[]
  waehrend: PlanPunkt[]
  nachher: PlanPunkt[]
  /** Gibt es ein Zählblatt für diese Arbeit? Beim Fax nicht. */
  mitZettel: boolean
}

export function arbeitsplan(station: Station, istFax: boolean, rechenbar: boolean | null): Arbeitsplan {
  const ausgang = rechenbar !== false
  const frage: PlanPunkt = { text: 'planFrage' }
  if (istFax) {
    return {
      vorher: [],
      waehrend: [{ text: 'planFaule' }],
      nachher: [{ text: 'planFaxPaletten' }, frage],
      mitZettel: false,
    }
  }
  if (station === 'sortieren') {
    return {
      vorher: [{ text: 'planPaloxStart' }],
      waehrend: [{ text: 'planZaehlenEingang' }, { text: 'planSortierdatum' }],
      nachher: [{ text: 'planPaloxEnde' }, frage],
      mitZettel: true,
    }
  }
  if (station === 'waschen') {
    return {
      vorher: [{ text: 'planPaloxStart', freiwillig: true }],
      waehrend: [{ text: 'planZaehlenWasch' }],
      nachher: [
        ...(ausgang ? [{ text: 'planDreiFertige' as const }, { text: 'planFertigeGesamt' as const }] : []),
        { text: 'planPaloxEnde', freiwillig: true },
        frage,
      ],
      mitZettel: true,
    }
  }
  // waschen_sortieren
  return {
    vorher: [{ text: 'planPaloxStart' }],
    waehrend: [{ text: 'planZaehlenEingang' }, { text: 'planDreiWiegen' }],
    nachher: [
      { text: 'planPaloxEnde' },
      { text: 'planAusschuss' },
      ...(ausgang ? [{ text: 'planDreiFertige' as const }, { text: 'planFertigeGesamt' as const }] : []),
      frage,
    ],
    mitZettel: true,
  }
}
