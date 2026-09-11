/**
 * Orakel 6 — die Bilanz: Invarianten, die über alle Zeilen einer Sicht
 * gelten müssen, unabhängig von jeder Formel.
 *
 * Diese Prüfungen brauchen keine zweite Rechnung, nur Buchhaltung: Was
 * hineinkommt, muss herauskommen. Sie sind deshalb die **billigsten** und
 * zugleich die, die am seltensten geschrieben werden.
 *
 * Jede Funktion nimmt rohe Zeilen (so wie psql sie als JSON liefert) und
 * gibt eine Liste von Verstössen zurück — leer heisst „stimmt".
 */
import { nahe } from './zahlen.ts'

export interface Verstoss { regel: string; wo: string; ist: string; soll: string }

type Zeile = Record<string, unknown>
const z = (r: Zeile, k: string): number | null => r[k] == null ? null : Number(r[k])

/** K1 — Je (Charge, Kohorte): Σ m0 über die Portionen = Eingang der Kohorte + Überzählung. */
export function kohorteGeschlossen(kaskade: Zeile[], kohorten: Zeile[]): Verstoss[] {
  const v: Verstoss[] = []
  const eingang = new Map<string, number>()
  for (const k of kohorten) eingang.set(`${k.charge_nr}|${k.eingangsdatum}`, z(k, 'eingang_kg') ?? 0)
  const summe = new Map<string, { m0: number; ueber: number }>()
  for (const r of kaskade) {
    const s = summe.get(`${r.charge_nr}|${r.kohorte}`) ?? { m0: 0, ueber: 0 }
    s.m0 += z(r, 'm0') ?? 0; s.ueber = Math.max(s.ueber, z(r, 'ueberzaehlung_kg') ?? 0)
    summe.set(`${r.charge_nr}|${r.kohorte}`, s)
  }
  for (const [key, s] of summe) {
    const e = eingang.get(key)
    if (e == null) { v.push({ regel: 'K1', wo: key, ist: `m0 ${s.m0.toFixed(2)}`, soll: 'eine Kohorte mit Eingang' }); continue }
    if (!nahe(s.m0 - s.ueber, e, 1e-6, 0.02)) v.push({ regel: 'K1', wo: key, ist: `Σ m0 − Überzählung = ${(s.m0 - s.ueber).toFixed(2)}`, soll: `Eingang ${e.toFixed(2)}` })
  }
  return v
}

/** K2 — In jeder Zeile: Σ Ströme = m0. */
export function stroemeSummieren(kaskade: Zeile[]): Verstoss[] {
  const v: Verstoss[] = []
  for (const r of kaskade) {
    const teile = ['verdunstung_kg', 'sockel_kg', 'schimmel_kg', 'klein_kg', 'nebenkanal_kg', 'fax_kg', 'verkaufsfaehig_kg'].map(k => z(r, k) ?? 0)
    const s = teile.reduce((a, b) => a + b, 0), m0 = z(r, 'm0') ?? 0
    if (!nahe(s, m0, 1e-6, 1e-6)) v.push({ regel: 'K2', wo: `${r.charge_nr}/${r.portion}/${r.kohorte}`, ist: s.toFixed(6), soll: m0.toFixed(6) })
  }
  return v
}

/** K3 — Nichts ist negativ, kein Anteil über 1, keine Zahl NaN oder unendlich. */
export function nichtsUnmoeglich(zeilen: Zeile[], massen: string[], anteile: string[], wo: (r: Zeile) => string): Verstoss[] {
  const v: Verstoss[] = []
  for (const r of zeilen) {
    for (const k of massen) { const x = z(r, k); if (x != null && !(Number.isFinite(x) && x >= 0)) v.push({ regel: 'K3', wo: `${wo(r)}.${k}`, ist: String(r[k]), soll: '≥ 0 und endlich' }) }
    for (const k of anteile) { const x = z(r, k); if (x != null && !(Number.isFinite(x) && x >= 0 && x <= 1)) v.push({ regel: 'K3', wo: `${wo(r)}.${k}`, ist: String(r[k]), soll: '0 … 1' }) }
  }
  return v
}

/** K4 — Ausgelagert: geliefert ≤ m0 (ein Verkaufsanteil ≤ 1 kann nicht mehr liefern, als eingegangen ist). */
export function geliefertNichtMehrAlsEingang(kaskade: Zeile[]): Verstoss[] {
  return kaskade.filter(r => r.portion === 'ausgelagert')
    .filter(r => (z(r, 'geliefert_kg') ?? 0) > (z(r, 'm0') ?? 0) * (1 + 1e-9))
    .map(r => ({ regel: 'K4', wo: `${r.charge_nr}/${r.kohorte}`, ist: `geliefert ${r.geliefert_kg}`, soll: `≤ m0 ${r.m0}` }))
}

/** K5 — Ein Band ist ein Band: unten ≤ mittel ≤ oben, und alle drei da oder keins. */
export function bandGeordnet(zeilen: Zeile[], unten: string, mittel: string, oben: string, wo: (r: Zeile) => string): Verstoss[] {
  const v: Verstoss[] = []
  for (const r of zeilen) {
    const u = z(r, unten), m = z(r, mittel), o = z(r, oben)
    const da = [u, m, o].filter(x => x != null).length
    if (da !== 0 && da !== 3) { v.push({ regel: 'K5', wo: wo(r), ist: `${u} / ${m} / ${o}`, soll: 'alle drei oder keins' }); continue }
    if (da === 3 && !((u as number) <= (m as number) + 1e-9 && (m as number) <= (o as number) + 1e-9)) v.push({ regel: 'K5', wo: wo(r), ist: `${u} ≤ ${m} ≤ ${o}?`, soll: 'unten ≤ mittel ≤ oben' })
  }
  return v
}

/**
 * K7 — Die Zeit läuft vorwärts: Kein plausibler Schimmelpunkt und keine Arbeit
 * hat negative Lagertage. Ein Zettel mit dem Jahr 2029 darf gespeichert
 * werden (Beobachtung), aber nicht als plausibel rechnen.
 *
 * Auf der bösen Saison ist diese Regel heute **verletzt** (B1: −139 und
 * −1053 Tage, plausibel = true) — sie ist die rote Prüfung, an der Phase 4
 * die Reparatur misst.
 */
export function zeitLaeuftVorwaerts(punkte: Zeile[], arbeiten: Zeile[]): Verstoss[] {
  const v: Verstoss[] = []
  for (const p of punkte) {
    const t = z(p, 'lagertage')
    if (t != null && t < 0 && p.plausibel === true) v.push({ regel: 'K7', wo: `Punkt Charge ${p.charge_nr} (${p.quelle})`, ist: `${t} Lagertage, plausibel`, soll: 'nicht plausibel oder Lagertage ≥ 0' })
  }
  for (const a of arbeiten) {
    const t = z(a, 'lagertage')
    if (t != null && t < 0) v.push({ regel: 'K7', wo: `Arbeit ${a.auftrag_id} (${a.station})`, ist: `${t} Lagertage`, soll: '≥ 0 oder Auffälligkeit statt Zahl' })
  }
  return v
}

/**
 * K6 — Die Saisonbilanz: Eingang = geliefert (alle Bücher) + Verlust + im Haus,
 * je Gruppe, in Eingangskilo. Welche Spalten das genau sind, hängt an
 * `erg_massenbilanz`; die ausführende Runde trägt die Namen ein und nimmt
 * diese Funktion in gegen_db.test.ts auf. Bis dahin ist sie eine Zusage ohne
 * Beweis — und steht deshalb im Bericht als „nicht geprüft", nicht als grün.
 */
export function saisonGeschlossen(_bilanz: Zeile[]): Verstoss[] {
  throw new Error('K6 noch nicht gebaut: Spalten von erg_massenbilanz zuordnen (siehe docs/PLAN_RUNDE_N.md, Phase 2)')
}
