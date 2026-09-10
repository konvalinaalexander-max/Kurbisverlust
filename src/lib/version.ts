/**
 * Der Stand der Datenbank, den diese App voraussetzt: die Nummer der jüngsten
 * Migration, die sie kennt. Die Datenbank nennt ihren eigenen über
 * schema_stand() (0057). Liegt sie darunter oder fehlt die Funktion, sagt die
 * Auswertung im Klartext, dass setup.sql noch einmal einzuspielen ist — statt
 * an alten Formeln zu scheitern.
 *
 * Bei jeder neuen Migration nachziehen; run.sh (Stufe 1) und npm test
 * schlagen an, wenn Migration, Datenbank und App auseinanderliegen.
 */
export const SCHEMA_ERWARTET = 68

export function datenbankVeraltet(stand: number | null): string {
  const wo = stand === null
    ? 'Die Datenbank ist älter als Migration 0057 und kennt ihren Stand noch nicht'
    : `Die Datenbank steht auf Migration ${String(stand).padStart(4, '0')}, die App erwartet ${String(SCHEMA_ERWARTET).padStart(4, '0')}`
  return `${wo}. Das behebt Schritt 3 im README: supabase/setup.sql noch einmal im Supabase-SQL-Editor ausführen — `
    + 'dieselbe Datei wie beim Einrichten, die Daten bleiben stehen. Unten muss „Fertig … Auswertung berechnet." erscheinen. Danach hier F5.'
}
