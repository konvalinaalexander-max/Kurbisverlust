/**
 * Die Rolle an einer Arbeit: Vorarbeiter (Checkliste, Ablesen, Abschluss)
 * oder Zähler (nur der Zähler). Sie hängt an der Arbeit, nicht an der Person:
 * Wer eröffnet hat, führt. Jedes andere Handy kann die Führung mit einem Tipp
 * übernehmen — gemerkt wird das nur lokal, es ist keine Messung.
 */
const SCHLUESSEL = (auftragId: number) => `fuehrung_${auftragId}`

export function fuehrtLokal(auftragId: number): boolean | null {
  try {
    const w = localStorage.getItem(SCHLUESSEL(auftragId))
    return w === null ? null : w === '1'
  } catch { return null }
}

export function fuehrungSetzen(auftragId: number, fuehrt: boolean) {
  try { localStorage.setItem(SCHLUESSEL(auftragId), fuehrt ? '1' : '0') } catch { /* privater Modus */ }
}

export function istVorarbeiter(auftragId: number, eroeffnetVon: string, ich: string | undefined): boolean {
  const lokal = fuehrtLokal(auftragId)
  if (lokal !== null) return lokal
  return !!ich && ich === eroeffnetVon
}
