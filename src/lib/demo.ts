/**
 * Der Demo-Eingang: eine Webseite, zwei Datenbanken.
 *
 * Der Betrieb will beides von derselben Adresse aus: wer sich anmeldet,
 * arbeitet mit den echten Daten; wer vor dem Anmelden auf „Demo ansehen"
 * drückt, landet in einer erfundenen Saison und darf dort alles anfassen —
 * Arbeiten eröffnen, wiegen, zählen, abschliessen. Was er dort tut, soll
 * wirklich in einer Datenbank landen (sonst rechnet das Dashboard nicht mit),
 * aber niemals in der des Betriebs.
 *
 * Deshalb zwei Supabase-Projekte. Es gibt keinen anderen ehrlichen Weg: Eine
 * Demo, die in dieselbe Datenbank schreibt, ist keine Demo, sondern eine
 * Verschmutzung der echten Zahlen — und das ist genau das, was der
 * Löschknopf aus 0080 gerade beseitigt hat. Die zweite Datenbank kostet
 * nichts (Gratis-Stufe), trägt dieselbe setup.sql und sagt selbst von sich,
 * dass sie eine Beispieldatenbank ist (einstellung.betriebsmodus =
 * 'beispiel'). Von dort kommt auch das gelbe Band oben.
 *
 * Umgeschaltet wird beim Start, nicht im Betrieb: Die Adresse der Datenbank
 * steht im Supabase-Client, und der wird einmal beim Laden der Seite gebaut.
 * Ein Wechsel mitten im Betrieb liesse die halbe App noch mit der anderen
 * Datenbank reden — offene Abfragen, gemerkte Auswertung, die Sitzung im
 * Speicher. Also: Merkzettel setzen, Seite neu laden, fertig. Das ist auch
 * für den Besucher das Verständlichste.
 *
 * Ist keine Demo-Datenbank eingerichtet, gibt es den Knopf nicht. Ein Knopf,
 * der beim Drücken eine Fehlermeldung zeigt, ist schlimmer als keiner.
 */

const SCHLUESSEL = 'demo_modus'

const url = (import.meta.env.VITE_DEMO_SUPABASE_URL as string | undefined)?.trim()
const schluessel = (import.meta.env.VITE_DEMO_SUPABASE_ANON_KEY as string | undefined)?.trim()

/** Ist für diese Webseite überhaupt eine Demo-Datenbank hinterlegt? */
export const demoMoeglich = Boolean(url && schluessel)

/** Die Zugangsdaten der Demo-Datenbank — nur wenn beide da sind. */
export const demoZugang = demoMoeglich ? { url: url as string, schluessel: schluessel as string } : null

/**
 * Steht der Merkzettel? Im privaten Modus kann localStorage werfen; dann gilt
 * die sichere Antwort „nein, echter Betrieb".
 */
export function demoAktiv(): boolean {
  if (!demoMoeglich) return false
  try { return localStorage.getItem(SCHLUESSEL) === '1' } catch { return false }
}

/**
 * Hinein: Merkzettel setzen und die Seite neu laden. Der Neustart ist keine
 * Bequemlichkeit, sondern der Punkt — danach redet die ganze App mit der
 * Demo-Datenbank und mit keiner anderen.
 */
export function demoBetreten(): void {
  try { localStorage.setItem(SCHLUESSEL, '1') } catch { /* privater Modus */ }
  window.location.assign('/')
}

/** Wieder hinaus. Dasselbe rückwärts. */
export function demoVerlassen(): void {
  try { localStorage.removeItem(SCHLUESSEL) } catch { /* privater Modus */ }
  window.location.assign('/')
}
