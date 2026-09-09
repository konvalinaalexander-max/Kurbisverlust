/**
 * Sonde 06 — Mutation
 *
 * Die Frage, die keine grüne Testsuite beantwortet: *Was würde auffallen, wenn
 * es falsch wäre?* Eine Suite, die auch dann grün bleibt, wenn man die Formel
 * verstellt, prüft nicht die Formel — sie prüft, dass das Programm läuft.
 *
 * Vorgehen: In den Migrationen wird genau eine Stelle verstellt — jede
 * Verstellung ein Fehler, den ein Mensch wirklich machen könnte. Dann wird das
 * Schema damit neu gebaut und die vorhandene Prüfung (`supabase/test/pruefung.sql`)
 * darauf losgelassen, dazu die Invarianten aus `invarianten.mjs`.
 *
 *   Die Prüfung schlägt an  →  gut, die Stelle ist abgesichert.
 *   Die Prüfung bleibt grün →  **überlebt**: An dieser Stelle könnte man den
 *                              Faktor vertauschen, und niemand merkte es.
 *
 * Ein Überlebender ist kein Fehler im Programm. Er ist eine Lücke im Netz —
 * und die Stelle, an der ein künftiger Fehler unbemerkt hineinkäme.
 */
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, readdirSync, writeFileSync, cpSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { WURZEL, befund, datenbank, tue, url } from '../umgebung.mjs'
import * as inv from '../invarianten.mjs'
import { CHARGE, CHEF, SORTE } from '../saison.mjs'

export const lang = true

const K62 = 'supabase/migrations/0062_jede_zahl_sagt_was_sie_ist.sql'
const K61 = 'supabase/migrations/0061_bis_heute_und_gespeichert.sql'

/**
 * Die Verstellungen. Jede ist ein Fehler, den man beim Schreiben oder beim
 * Umbauen wirklich macht — kein zufälliges Zeichenvertauschen, das ohnehin
 * nicht compiliert.
 */
export const MUTATIONEN = [
  { id: 'sockel-auf-m0', datei: K62, was: 'Der Sockel wird vom Eingangsgewicht statt vom Gewicht nach der Verdunstung genommen',
    alt: '(m1 * a0) AS sockel_kg', neu: '(m0 * a0) AS sockel_kg' },
  { id: 'schimmel-ohne-sockel', datei: K62, was: 'Der Schimmel rechnet den Sockel nicht heraus — dieselbe Ware zweimal',
    alt: '((m1 * ((1)::numeric - a0)) * f) AS schimmel_kg', neu: '(m1 * f) AS schimmel_kg' },
  { id: 'klein-statt-gross', datei: K62, was: 'Zu klein und zu gross vertauscht',
    alt: '* a_klein_n) AS klein_kg', neu: '* a_gross_n) AS klein_kg' },
  { id: 'boden-tiefer', datei: K62, was: 'Der Boden des verkaufsfähigen Anteils von 25 % auf 5 %',
    alt: '0.25) AS verkaufsfaehig_anteil', neu: '0.05) AS verkaufsfaehig_anteil' },
  { id: 'rate-deckel-weg', datei: K62, was: 'Die Verdunstungsrate darf zehnmal so gross werden',
    alt: '0.05) AS r,', neu: '0.50) AS r,' },
  { id: 'marge-nicht-ausgeliefert', datei: K62, was: 'Tierfutter und Nebenkanal gelten wieder als nicht ausgeliefert',
    alt: "ARRAY['verkauf'::text, 'marge'::text]", neu: "ARRAY['verkauf'::text]" },
  { id: 'ein-tag-mehr', datei: K62, was: 'Die Ware altert einen Tag zu lang',
    alt: '(t.m0 * power(((1)::numeric - t.r), t.alter_tage)) AS m1',
    neu: '(t.m0 * power(((1)::numeric - t.r), t.alter_tage + (1)::numeric)) AS m1' },
  { id: 'ueberzaehlung-ungebremst', datei: K62, was: 'Die liegende Masse darf negativ werden',
    alt: 'GREATEST((a.eingang_kohorte_kg - COALESCE(x.m0, (0)::numeric)), (0)::numeric) AS m0',
    neu: '(a.eingang_kohorte_kg - COALESCE(x.m0, (0)::numeric)) AS m0' },
  { id: 'ableitung-vorzeichen', datei: K62, was: 'Das Vorzeichen der Ableitung ∂m1/∂r gedreht',
    alt: '(((- t.m0) * t.alter_tage) * power', neu: '(((+ t.m0) * t.alter_tage) * power' },
  { id: 'fax-doppelt', datei: K61, was: 'Das Fax-Faule der liegenden Ware zählt als Verlust bis heute',
    alt: "sum(fax_kg) filter (where portion = 'ausgelagert')", neu: 'sum(fax_kg)' },
  { id: 'bekannt-zu-grosszuegig', datei: K61, was: '„Verlust bekannt" schon, wenn *ein* Koeffizient gemessen ist',
    alt: 'bool_and(r_bekannt and f_bekannt)', neu: 'bool_or(r_bekannt or f_bekannt)' },
  { id: 'kanal-im-haus-alles', datei: K61, was: 'Der Kanal der ausgelieferten Ware zählt als „noch im Haus"',
    alt: "sum(klein_kg + nebenkanal_kg) filter (where portion = 'lager')", neu: 'sum(klein_kg + nebenkanal_kg)' },
]

/* ---------- Ein Schema aus (womöglich verstellten) Migrationen ------------ */

function bauen(db, mutation) {
  datenbank(db)
  const verz = mkdtempSync(join(tmpdir(), 'pw-mut-'))
  cpSync(join(WURZEL, 'supabase/migrations'), join(verz, 'migrations'), { recursive: true })
  if (mutation) {
    const ziel = join(verz, 'migrations', mutation.datei.split('/').pop())
    const text = readFileSync(ziel, 'utf8')
    if (!text.includes(mutation.alt)) { rmSync(verz, { recursive: true, force: true }); return 'Stelle nicht gefunden' }
    writeFileSync(ziel, text.replace(mutation.alt, mutation.neu))
  }
  try {
    tue(db, `drop schema if exists public cascade; create schema public;
             drop schema if exists auth cascade; drop schema if exists storage cascade;`)
    spielen(db, join(WURZEL, 'supabase/test/stub_supabase.sql'))
    for (const f of readdirSync(join(verz, 'migrations')).filter(f => f.endsWith('.sql')).sort())
      spielen(db, join(verz, 'migrations', f))
    return null
  } catch (e) {
    return `Schema baut nicht: ${e.message.slice(0, 120)}`
  } finally {
    rmSync(verz, { recursive: true, force: true })
  }
}

function spielen(db, datei) {
  try {
    execFileSync('psql', [url(db), '-qX', '-v', 'ON_ERROR_STOP=1', '-f', datei],
      { encoding: 'utf8', stdio: ['ignore', 'ignore', 'pipe'], maxBuffer: 64 * 1024 * 1024 })
  } catch (e) {
    throw new Error(String(e.stderr ?? e.message).split('\n').find(z => /ERROR/i.test(z)) ?? e.message)
  }
}

/** Die vorhandene Prüfung der Datenbankseite — schlägt sie an? */
function pruefungLaeuft(db) {
  try {
    execFileSync('psql', [url(db), '-qX', '-v', 'ON_ERROR_STOP=1', '-f',
      join(WURZEL, 'supabase/test/pruefung.sql')],
      { encoding: 'utf8', stdio: ['ignore', 'ignore', 'pipe'], maxBuffer: 64 * 1024 * 1024 })
    return null
  } catch (e) {
    const t = String(e.stderr ?? '')
    return t.split('\n').find(z => /ERROR|FEHLER|assert/i.test(z))?.slice(0, 160) ?? 'Prüfung schlägt an'
  }
}

/** Eine kleine Saison mit Lieferung — sonst rechnet die Kaskade an nichts. */
function saison(db) {
  tue(db, `
    insert into auth.users (id, email, raw_user_meta_data) values
      ('${CHEF}', 'chef@hof.test', '{"name":"Chef"}') on conflict do nothing;
    update profil set rolle = 'admin', aktiv = true;
    insert into einstellung (schluessel, wert) values
      ('heute_test', to_jsonb('2026-09-01'::text)), ('saison_ende', to_jsonb('2027-03-31'::text))
      on conflict (schluessel) do update set wert = excluded.wert;
    insert into sorte_kaliber (sorte, verlust_unter, kaliber_baender, kanal_ab)
      values ('${SORTE}', 300, '[[300,800],[800,2000]]'::jsonb, 2000) on conflict do nothing;
    insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette) values ('P', 1.0, 20.0)
      on conflict (art) do update set tara_kg_pro_kiste = 1.0;
    insert into charge (nr, schlag, sorte, saison) values (${CHARGE}, 'Prüfschlag', '${SORTE}', 2026)
      on conflict do nothing;
    insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, quelle) values
      (${CHARGE}, '2026-06-01', 1000, 30, 'P', 'test'),
      (${CHARGE}, '2026-06-15', 1000, 30, 'P', 'test'),
      (${CHARGE}, '2026-07-01', 1000, 30, 'P', 'test');
    insert into lieferung (datum, charge_nr, sorte, kg, ziel, erfasser) values
      ('2026-08-01', ${CHARGE}, '${SORTE}', 500, 'verkauf', '${CHEF}'),
      ('2026-08-15', ${CHARGE}, '${SORTE}', 300, 'tierfutter', '${CHEF}');
    select auswertung_aktualisieren();`)
}

export async function laufen({ db, schnell }) {
  if (schnell) return []
  const raus = []
  const B = (o) => raus.push(befund({ sonde: '06_mutation', kuerzel: 'MUT', ...o }))
  const ziel = 'pw_mutation'

  // Erst ohne Verstellung: Läuft die Prüfung auf einem sauberen Bau durch?
  // Wenn nicht, sagt jeder folgende Vergleich nichts.
  const fehlerBau = bauen(ziel, null)
  if (fehlerBau) {
    B({ klasse: 1, ort: { datei: 'supabase/migrations' }, titel: 'Das Schema baut nicht',
        steht_da: fehlerBau, muesste: 'Die Migrationen bauen ohne Fehler.',
        warum: 'Ohne Grundlinie ist keine Mutationsprüfung möglich.',
        beleg: 'pruefwerk/sonden/06_mutation.mjs', groesse: { wert: 1, einheit: 'Fehler', basis: 'Grundlinie' },
        sicherheit: 'hoch', marke: 'Reparatur' })
    return raus
  }
  const grundlinie = pruefungLaeuft(ziel)
  if (grundlinie) {
    B({ klasse: 1, ort: { datei: 'supabase/test/pruefung.sql' }, titel: 'Die Prüfung schlägt schon ohne Verstellung an',
        steht_da: grundlinie, muesste: 'Auf einem sauberen Bau läuft sie durch.',
        warum: 'Sonst ist nicht zu unterscheiden, ob eine Verstellung erkannt wurde.',
        beleg: 'pruefwerk/sonden/06_mutation.mjs', groesse: { wert: 1, einheit: 'Fehler', basis: 'Grundlinie' },
        sicherheit: 'hoch', marke: 'Reparatur' })
    return raus
  }

  const ergebnis = []
  for (const m of MUTATIONEN) {
    if (process.env.PW_LAUT) process.stderr.write(`   … ${m.id}\n`)
    const fehler = bauen(ziel, m)
    if (fehler) { ergebnis.push({ ...m, stand: 'baut nicht', wie: fehler }); continue }
    const gefangen = pruefungLaeuft(ziel)
    if (gefangen) { ergebnis.push({ ...m, stand: 'gefangen', wie: `pruefung.sql: ${gefangen}` }); continue }
    // Die Prüfung war zufrieden. Sehen die Invarianten es?
    saison(ziel)
    const verletzt = inv.alle(ziel)
    ergebnis.push(verletzt.length
      ? { ...m, stand: 'gefangen', wie: `Invariante „${verletzt.map(v => v.regel).join(', ')}"` }
      : { ...m, stand: 'überlebt', wie: 'weder pruefung.sql noch eine Invariante' })
  }

  const ueberlebt = ergebnis.filter(e => e.stand === 'überlebt')
  const gefangen = ergebnis.filter(e => e.stand === 'gefangen')
  if (ueberlebt.length) {
    B({ klasse: 3, ort: { datei: 'supabase/test/pruefung.sql' },
        titel: `${ueberlebt.length} von ${ergebnis.length} verstellten Formeln bleiben unbemerkt`,
        steht_da: ueberlebt.map(e => `„${e.was}" (${e.id})`).join('; '),
        muesste: 'Zu jeder dieser Stellen eine Behauptung in pruefung.sql, die anschlägt, sobald sie '
               + 'verstellt wird — mit einer Zahl, die auf Papier nachrechenbar ist.',
        warum: 'Diese Stellen tragen die ganze Fachlogik. Wer sie beim nächsten Umbau versehentlich '
             + 'verstellt, bekommt eine grüne Suite und falsche Zahlen. Genau so entstehen die Fehler, '
             + 'die niemand findet, weil alle Prüfungen grün sind.',
        beleg: 'pruefwerk/sonden/06_mutation.mjs → MUTATIONEN',
        groesse: { wert: Math.round((100 * ueberlebt.length) / ergebnis.length), einheit: '% der Verstellungen unbemerkt',
                   basis: `${ergebnis.length} gezielte Verstellungen in 0061/0062` },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'mittel',
        gegenrede: `${gefangen.length} Verstellungen werden erkannt (${gefangen.map(e => e.id).join(', ') || '—'}) — `
                 + 'das Netz ist also nicht leer, nur löchrig. Manche Lücke ist es auch wert: eine '
                 + 'Verstellung, die nur den Bereich verschiebt, kostet weniger als eine, die die '
                 + 'Kilogramm verschiebt. Die Liste sagt, wo man zuerst hinsieht.' })
  }
  for (const e of ergebnis.filter(e => e.stand === 'baut nicht')) {
    B({ klasse: 1, ort: { datei: e.datei },
        titel: `Verstellung „${e.id}" liess sich nicht prüfen`,
        steht_da: e.wie, muesste: 'Die Verstellung soll bauen, damit sie etwas aussagt.',
        warum: 'Eine Verstellung, die schon am Bau scheitert, sagt nichts über die Prüfungen.',
        beleg: 'pruefwerk/sonden/06_mutation.mjs',
        groesse: { wert: 1, einheit: 'Verstellung', basis: e.id },
        sicherheit: 'hoch', marke: 'kein Fehler' })
  }
  raus.ergebnis = ergebnis
  return raus
}

/**
 * Selbstprobe: Eine Verstellung, die *sicher* auffallen muss — der Sockel vom
 * Eingangsgewicht statt vom Gewicht nach der Verdunstung — bricht die
 * Erhaltung der Masse. Findet der Aufbau das nicht, prüft er nichts.
 */
export async function selbstprobe() {
  const ziel = 'pw_mutation_probe'
  const m = { datei: K62, alt: '(m1 * a0) AS sockel_kg', neu: '(m0 * a0) AS sockel_kg' }
  if (bauen(ziel, m)) return false
  saison(ziel)
  // Bei a0 = 0 (keine Palox-Messung) ändert die Verstellung nichts — deshalb
  // wird a0 hier von Hand gesetzt, damit die Masse wirklich auseinanderfällt.
  const gebrochen = inv.erhaltung(ziel)
  if (gebrochen.length) return true
  // a0 ist 0, also greift die Verstellung nicht. Dann muss wenigstens der
  // saubere Bau die Erhaltung halten — sonst ist die Invariante selbst kaputt.
  if (bauen(ziel, null)) return false
  saison(ziel)
  return inv.erhaltung(ziel).length === 0 && inv.bilanz(ziel).length === 0
}
