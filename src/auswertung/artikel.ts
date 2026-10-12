/**
 * Lagermanagement nach Artikel — die reinen Regeln, ohne React (Runde AQ aus
 * src/pages/Artikel.tsx gezogen, damit test/artikel.test.ts sie prüfen kann).
 *
 * Ein Artikel ist Artikelgruppe × Grösse × Label. Die Wahl oben auf der Seite
 * (Artikel, klein/gross/beide, Demeter/Knospe/beide) filtert; die Übersicht
 * „Wie viel ist von welchem Artikel noch da?" zählt je Gruppe × Label die
 * Chargen zusammen: Eingang, ausgelagert (Eingangsware hinter den
 * Lieferungen), geliefert, im Lager und verkaufsfähig — dazu das
 * Verkaufsfähige nach Grösse aus denselben Teilen wie die Tabelle in Kisten.
 */
import type { ArtikelLagerCharge, Bestand, ChargeLabel, SorteGruppe } from './daten'

export const GRUPPEN_FOLGE = ['Knirps', 'Butternut', 'Butterkin/Muskat', 'Kabocha', 'Mandarin', 'Mix', 'andere']
/** Die Reihenfolge der Artikelgruppen, wie der Verkauf sie nennt; Unbekanntes zuletzt. */
export const rang = (g: string | null) => { const i = g === null ? -1 : GRUPPEN_FOLGE.indexOf(g); return i < 0 ? 99 : i }

export type GroesseWahl = 'beide' | 'klein' | 'gross'
export type LabelWahl = 'beide' | 'D' | 'K'
export interface Wahl { gruppe: string; groesse: GroesseWahl; label: LabelWahl }
export const OFFEN: Wahl = { gruppe: '', groesse: 'beide', label: 'beide' }

/**
 * Die Grösse einer Lagerzeile, wie der Verkauf sie kennt: klein und gross
 * nach den Kalibern des Artikels, Mandarin je Stück; was in kein Kaliber
 * passt, ist „ausserhalb" (lose verkäuflich); ohne Sortier-CSV „ohne Grösse".
 */
export type Klasse = 'klein' | 'gross' | 'stueck' | 'ausserhalb' | 'ohne'
export const KLASSEN: Klasse[] = ['klein', 'gross', 'stueck', 'ausserhalb', 'ohne']
export const klasseVon = (g: string): Klasse =>
  g === 'klein' || g === 'gross' || g === 'stueck' ? g : g === 'ohne Verteilung' ? 'ohne' : 'ausserhalb'

export const passtGruppe = (w: Wahl, g: string | null) => w.gruppe === '' || g === w.gruppe
export const passtLabel = (w: Wahl, l: string | null) => w.label === 'beide' || l === w.label
export const passtKlasse = (w: Wahl, k: Klasse) => w.groesse === 'beide' || k === w.groesse

/** Ein Artikel ohne Grösse (Gruppe × Label), mit allem, was seine Chargen bis heute erlebt haben. */
export interface Uebersichtszeile {
  schluessel: string; gruppe: string | null; label: 'D' | 'K' | null; n: number
  eingang: number; ausgelagert: number; geliefert: number; lager: number
  /** Das Verkaufsfähige heute; luecke: Chargen mit Ware, deren Verkaufsfähiges unbekannt ist (nie 0). */
  vf: number; luecke: number
  klassen: Map<Klasse, number>
}

export function uebersichtszeilen(bestand: Bestand[], labelVon: Map<number, ChargeLabel>, gruppeVon: Map<string, SorteGruppe>,
                           teile: ArtikelLagerCharge[], wahl: Wahl): Uebersichtszeile[] {
  const m = new Map<string, Uebersichtszeile>()
  const zuZeile = new Map<number, Uebersichtszeile>()
  for (const b of bestand) {
    const gruppe = gruppeVon.get(b.sorte)?.artikelgruppe ?? null
    const label = labelVon.get(b.charge_nr)?.label ?? null
    if (!passtGruppe(wahl, gruppe) || !passtLabel(wahl, label)) continue
    const k = `${gruppe ?? ''}|${label ?? ''}`
    let z = m.get(k)
    if (!z) {
      z = { schluessel: k, gruppe, label, n: 0, eingang: 0, ausgelagert: 0, geliefert: 0, lager: 0, vf: 0, luecke: 0, klassen: new Map() }
      m.set(k, z)
    }
    z.n += 1
    z.eingang += Number(b.eingang_kg); z.ausgelagert += Number(b.ausgelagert_kg)
    z.geliefert += Number(b.geliefert_kg); z.lager += Number(b.lager_kg)
    if (b.lager_kg > 0) {
      if (b.verkaufsfaehig_lager_kg === null) z.luecke += 1
      else z.vf += Number(b.verkaufsfaehig_lager_kg)
    }
    zuZeile.set(b.charge_nr, z)
  }
  // Das Verkaufsfähige nach Grösse: dieselben Teile wie die Tabelle darunter (heute).
  for (const t of teile) {
    const z = zuZeile.get(t.charge_nr)
    if (!z || !(Number(t.kg) > 0)) continue
    const kl = klasseVon(t.groesse)
    z.klassen.set(kl, (z.klassen.get(kl) ?? 0) + Number(t.kg))
  }
  return [...m.values()].filter(z => z.eingang > 0)
    .sort((a, b) => rang(a.gruppe) - rang(b.gruppe) || (a.gruppe ?? '').localeCompare(b.gruppe ?? '')
                    || (a.label ?? 'Z').localeCompare(b.label ?? 'Z'))
}
