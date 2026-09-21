import { test } from 'node:test'
import assert from 'node:assert/strict'
import { konfigurationPruefen, zugangBrauchbar } from '../src/lib/konfiguration.ts'

const URL_OK = 'https://qaryvviqdjnxrukpgdn.supabase.co'
const PUBLISHABLE = 'sb_publishable_Fj_FAZGOdxGiBeN4DV0v2Q_HGBxsAbCdEf'

/** Baut einen Legacy-Schlüssel mit der angegebenen Rolle. */
function jwt(rolle: string): string {
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url')
  return `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ role: rolle, iss: 'supabase' })}.unterschrift`
}

test('der neue Publishable Key wird akzeptiert', () => {
  assert.equal(konfigurationPruefen(URL_OK, PUBLISHABLE), null)
})

test('der alte anon-Schlüssel wird weiterhin akzeptiert', () => {
  assert.equal(konfigurationPruefen(URL_OK, jwt('anon')), null)
})

test('leere Konfiguration meldet kein Problem — dafür gibt es einen eigenen Hinweis', () => {
  assert.equal(konfigurationPruefen(undefined, undefined), null)
  assert.equal(konfigurationPruefen(URL_OK, undefined), null)
})

test('der geheime Schlüssel wird erkannt und deutlich benannt', () => {
  const m = konfigurationPruefen(URL_OK, 'sb_secret_d52YeAbCdEfGhIjKlMn')
  assert.match(m!, /GEHEIME/)
  assert.match(m!, /sb_publishable_/)
})

test('auch der alte service_role-Schlüssel wird erkannt', () => {
  // Sieht harmlos aus wie jeder Legacy-Schlüssel — der Unterschied steckt
  // nur in der Rolle im JWT.
  const m = konfigurationPruefen(URL_OK, jwt('service_role'))
  assert.match(m!, /GEHEIME/)
})

test('eine URL mit Pfad dahinter wird bemängelt', () => {
  // Genau das passiert, wenn man die Adresszeile des Dashboards kopiert.
  const m = konfigurationPruefen(
    'https://supabase.com/dashboard/project/qaryvviqdjnxrukpgdn/settings/api-keys', PUBLISHABLE)
  assert.match(m!, /Project URL sieht nicht richtig aus/)
  assert.match(m!, /Data API/)
})

test('ein Schrägstrich am Ende stört nicht', () => {
  assert.equal(konfigurationPruefen(`${URL_OK}/`, PUBLISHABLE), null)
})

test('ein halb kopierter Schlüssel wird bemängelt', () => {
  const m = konfigurationPruefen(URL_OK, 'FAZGOdxGiBeN4DV0v2Q')
  assert.match(m!, /nur ein Teil/)
})


/* ------------------------------------------------------------------ */
/* zugangBrauchbar — die Frage vor createClient()                      */
/*                                                                     */
/* Aus dem Betrieb gemeldet: schwarzer Bildschirm beim ersten Versuch  */
/* mit dem Demo-Knopf, ohne Weg zurück. createClient() wirft bei einer */
/* Adresse ohne https:// — und zwar beim Laden des Moduls, vor jedem   */
/* Stück Oberfläche. Diese Funktion fragt vorher, damit die App die    */
/* Meldung zeigen kann, statt zu sterben.                              */

test('brauchbar: richtige Adresse und richtiger Schlüssel', () => {
  assert.equal(zugangBrauchbar(URL_OK, PUBLISHABLE), true)
  assert.equal(zugangBrauchbar(URL_OK, jwt('anon')), true)
})

test('unbrauchbar: die Adresse ohne https:// — der gemeldete Fall', () => {
  assert.equal(zugangBrauchbar('qmhxkfyowwvsumcwssxe.supabase.co', PUBLISHABLE), false)
})

test('unbrauchbar: Adresse und Schlüssel vertauscht', () => {
  assert.equal(zugangBrauchbar(PUBLISHABLE, URL_OK), false)
})

test('unbrauchbar: die Adresse der Verwaltungsoberfläche', () => {
  assert.equal(zugangBrauchbar('https://supabase.com/dashboard/project/abcdefgh', PUBLISHABLE), false)
})

test('unbrauchbar: die API-Adresse mit /rest/v1/ dahinter', () => {
  assert.equal(zugangBrauchbar(`${URL_OK}/rest/v1/`, PUBLISHABLE), false)
})

test('unbrauchbar: ein fehlender Wert — und zwar jeder von beiden', () => {
  assert.equal(zugangBrauchbar(undefined, PUBLISHABLE), false)
  assert.equal(zugangBrauchbar(URL_OK, undefined), false)
  assert.equal(zugangBrauchbar('', ''), false)
})

test('unbrauchbar: der geheime Schlüssel — er darf nie in eine Webseite', () => {
  assert.equal(zugangBrauchbar(URL_OK, 'sb_secret_Fj_FAZGOdxGiBeN4DV0v2Q'), false)
  assert.equal(zugangBrauchbar(URL_OK, jwt('service_role')), false)
})

test('brauchbar bleibt der lokale Prüfstand', () => {
  assert.equal(zugangBrauchbar('http://localhost:5199', jwt('anon')), true)
})
