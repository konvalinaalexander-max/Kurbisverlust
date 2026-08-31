/**
 * Prüft die beiden Zugangswerte, bevor irgendetwas anderes passiert.
 *
 * Ein vertippter oder verwechselter Schlüssel äußert sich sonst erst beim
 * Anmelden als nichtssagendes „Invalid API key". Und der gefährliche Fall —
 * jemand kopiert den geheimen Schlüssel in eine öffentliche Webseite — fiele
 * überhaupt nicht auf, weil damit sogar alles funktionieren würde.
 *
 * Reine Funktion ohne Umgebungszugriff, damit sie testbar bleibt.
 */
export function konfigurationPruefen(
  url: string | undefined,
  schluessel: string | undefined,
): string | null {
  if (!url || !schluessel) return null   // gar nicht konfiguriert — eigener Hinweis

  if (schluessel.startsWith('sb_secret_') || istServiceRole(schluessel)) {
    return 'Das ist der GEHEIME Schlüssel („secret" bzw. „service_role"). Er darf '
      + 'niemals in eine Webseite, weil er alle Zugriffsregeln umgeht. Nimm '
      + 'stattdessen den Publishable Key (beginnt mit sb_publishable_) oder, im '
      + 'Reiter „Legacy", den Schlüssel mit der Beschriftung anon public. '
      + 'Anschließend den geheimen Schlüssel in Supabase neu erzeugen.'
  }
  // localhost ist echt: die Supabase-CLI läuft lokal auf http://127.0.0.1:54321,
  // und der Bildschirm-Prüfstand spielt Supabase selbst. Beides kein Tippfehler.
  const lokal = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?\/?$/.test(url)
  if (!lokal && !/^https:\/\/[^/]+\.supabase\.(co|in)\/?$/.test(url)) {
    return `Die Project URL sieht nicht richtig aus: „${url}". Erwartet wird `
      + 'etwas wie https://abcdefgh.supabase.co — ohne weiteren Pfad dahinter. '
      + 'Du findest sie in Supabase unter Settings → Data API.'
  }
  if (!schluessel.startsWith('sb_publishable_') && !schluessel.startsWith('eyJ')) {
    return 'Der Schlüssel sieht nicht richtig aus. Er beginnt entweder mit '
      + 'sb_publishable_ oder mit eyJ. Womöglich wurde beim Kopieren nur ein '
      + 'Teil erwischt — in Supabase gibt es neben dem Schlüssel ein Kopier-Symbol.'
  }
  return null
}

/** Legacy-Schlüssel sind JWTs; die Rolle steht im mittleren Abschnitt. */
function istServiceRole(schluessel: string): boolean {
  const teile = schluessel.split('.')
  if (teile.length !== 3) return false
  try {
    const rumpf = teile[1].replace(/-/g, '+').replace(/_/g, '/')
    return JSON.parse(atob(rumpf)).role === 'service_role'
  } catch {
    return false
  }
}
