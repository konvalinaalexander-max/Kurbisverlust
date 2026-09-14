/**
 * Die Rolle an einer Arbeit: Vorarbeiter (Checkliste, Ablesen, Abschluss)
 * oder Zähler (nur der Zähler). Sie hängt an der Arbeit, nicht an der Person:
 * Wer eröffnet hat, führt. Jedes andere Handy kann die Führung mit einem Tipp
 * übernehmen — gemerkt wird das nur lokal, es ist keine Messung.
 *
 * Runde Q (Q22, Schichtwechsel): gemerkt wird je Arbeit **und je Person**.
 * In der Halle liegen wenige Handys für viele Leute. Vorher merkte sich das
 * Gerät „an Arbeit 812 führe ich" — und wer das Handy um vier Uhr übernahm,
 * erbte diese Rolle stillschweigend: entweder stand er plötzlich vor der
 * Checkliste des Vorarbeiters, oder er kam als Vorarbeiter nicht mehr an den
 * Abschluss. Mit dem Kürzel der Person im Schlüssel fällt der Neue auf die
 * ehrliche Vorgabe zurück („wer eröffnet hat, führt") und kann mit einem
 * Tipp übernehmen.
 */
const SCHLUESSEL = (auftragId: number, ich: string | undefined) =>
  `fuehrung_${auftragId}_${ich ?? 'anonym'}`

export function fuehrtLokal(auftragId: number, ich: string | undefined): boolean | null {
  try {
    const w = localStorage.getItem(SCHLUESSEL(auftragId, ich))
    return w === null ? null : w === '1'
  } catch { return null }
}

export function fuehrungSetzen(auftragId: number, ich: string | undefined, fuehrt: boolean) {
  try { localStorage.setItem(SCHLUESSEL(auftragId, ich), fuehrt ? '1' : '0') } catch { /* privater Modus */ }
}

export function istVorarbeiter(auftragId: number, eroeffnetVon: string, ich: string | undefined): boolean {
  const lokal = fuehrtLokal(auftragId, ich)
  if (lokal !== null) return lokal
  return !!ich && ich === eroeffnetVon
}
