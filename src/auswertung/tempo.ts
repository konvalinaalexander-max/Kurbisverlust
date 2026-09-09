import { taetigkeitVon } from '../lib/taetigkeit'
import { WOERTERBUCH } from '../lib/i18n'
import type { Durchsatz } from './daten'

export interface Tempo { name: string; zeichen: string; n: number; stunden: number; median: number; masse: number; kgProH: number | null; kgProPersonH: number | null }

/** Dauer und Durchsatz je Tätigkeit — Median statt Mittel, damit eine
 *  vergessene, über Nacht offen gebliebene Arbeit den Wert nicht verzerrt. */
export function tempoJeTaetigkeit(zeilen: Durchsatz[]): Tempo[] {
  const gruppen = new Map<string, Durchsatz[]>()
  for (const d of zeilen) {
    const k = `${d.weg}|${d.station}|${d.ist_fax}`
    gruppen.set(k, [...(gruppen.get(k) ?? []), d])
  }
  const median = (xs: number[]) => { const s = [...xs].sort((a, b) => a - b); return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : 0 }
  return [...gruppen.entries()].map(([, ds]) => {
    const d0 = ds[0]
    const ta = taetigkeitVon(d0.weg as 'maschine' | 'hand', d0.station as 'sortieren' | 'waschen' | 'waschen_sortieren', d0.ist_fax)
    const mitMasse = ds.filter(d => d.masse_kg !== null && d.dauer_h >= 0.25)
    const stundenMitMasse = mitMasse.reduce((a, d) => a + d.dauer_h, 0)
    const personStunden = mitMasse.reduce((a, d) => a + d.dauer_h * Math.max(d.n_teilnehmer, 1), 0)
    // `mitMasse` ist auf `masse_kg !== null` gefiltert; das `?? 0` steht nur
    // für den Übersetzer. Arbeiten ohne gewogene Masse zählen weder in die
    // Masse noch in die Stunden, sonst wäre der Durchsatz zu klein.
    const masse = mitMasse.reduce((a, d) => a + (d.masse_kg ?? 0), 0)
    return {
      name: ta ? WOERTERBUCH.de[ta.text] : d0.station, zeichen: ta?.zeichen ?? '',
      n: ds.length, stunden: ds.reduce((a, d) => a + d.dauer_h, 0), median: median(ds.map(d => d.dauer_h)),
      masse, kgProH: stundenMitMasse > 0 ? masse / stundenMitMasse : null,
      kgProPersonH: personStunden > 0 ? masse / personStunden : null,
    }
  }).sort((a, b) => b.n - a.n)
}
