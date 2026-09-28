/**
 * Die Chargen, wie der Betrieb sie sucht (Runde AD): nach Feld (Schlag),
 * darin nach Sorte, dann die Nummer. „Ich hab gemerkt, dass die Zahlen nicht
 * ganz so wichtig sind — wichtiger ist Feld und Sorte und dann die Zahl."
 * Das Feld ist die Gruppe, die Zeile heisst „Sorte (Charge Nr)".
 */
export interface ChargeKurz { charge_nr: number; sorte: string; schlag: string }

export function chargenNachFeld<T extends ChargeKurz>(chargen: T[]): { feld: string; chargen: T[] }[] {
  const je = new Map<string, T[]>()
  for (const c of chargen) { const l = je.get(c.schlag) ?? []; l.push(c); je.set(c.schlag, l) }
  return [...je.entries()]
    .sort((a, b) => a[0].localeCompare(b[0], 'de'))
    .map(([feld, l]) => ({ feld, chargen: [...l].sort((a, b) => a.sorte.localeCompare(b.sorte, 'de') || a.charge_nr - b.charge_nr) }))
}
