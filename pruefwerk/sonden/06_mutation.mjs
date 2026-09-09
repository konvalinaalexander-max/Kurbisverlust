/**
 * Sonde 06 — Mutation
 *
 * Die Frage, die keine grüne Testsuite beantwortet: *Was würde auffallen, wenn
 * es falsch wäre?* Eine Suite, die auch dann grün bleibt, wenn man die Formel
 * verstellt, prüft nicht die Formel — sie prüft, dass das Programm läuft.
 *
 * Vorgehen: In den Migrationen wird genau eine Stelle verstellt — jede
 * Verstellung ein Fehler, den ein Mensch wirklich machen könnte. Das Schema
 * wird damit neu gebaut, die **echten Demodaten** werden eingespielt (auf einer
 * Saison ohne Messungen sind die meisten Verstellungen wirkungslos, weil alle
 * Koeffizienten 0 sind — dort fände man nichts und hielte das für ein gutes
 * Zeichen), neu gerechnet, und dann wird gefragt:
 *
 *   Ändert sich überhaupt eine Zahl?   Nein → **ohne Wirkung** auf diesen Daten.
 *   Schlägt `pruefung.sql` an?         Ja   → gut, die Stelle ist abgesichert.
 *   Schlägt eine Invariante an?        Ja   → ebenfalls gefangen.
 *   Nichts von beidem?                 →      **überlebt**: Man könnte den
 *                                             Faktor vertauschen, die Zahlen
 *                                             wären andere, und niemand merkte es.
 *
 * Ein Überlebender ist kein Fehler im Programm. Er ist eine Lücke im Netz —
 * und die Stelle, an der ein künftiger Fehler unbemerkt hineinkäme.
 *
 * Die Invariante „Unwissen" zählt hier ausdrücklich **nicht** als Fang: Sie
 * meldet, dass Koeffizienten fehlen, und das tut sie unabhängig von jeder
 * Verstellung. Wer sie mitzählt, bekommt zwölf von zwölf gefangen und lernt
 * nichts.
 */
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, readdirSync, writeFileSync, cpSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { WURZEL, befund, datenbank, frage, tue, url, wert } from '../umgebung.mjs'
import * as inv from '../invarianten.mjs'

export const lang = true

const K62 = 'supabase/migrations/0062_jede_zahl_sagt_was_sie_ist.sql'

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
  { id: 'fax-doppelt', datei: K62, was: 'Das Fax-Faule der liegenden Ware zählt als Verlust bis heute',
    alt: "sum(fax_kg) filter (where portion = 'ausgelagert')", neu: 'sum(fax_kg)' },
  { id: 'bekannt-zu-grosszuegig', datei: K62, was: '„Verlust bekannt" schon, wenn *ein* Koeffizient gemessen ist',
    alt: 'bool_and(r_bekannt and f_bekannt and a0_bekannt and a_fax_bekannt',
    neu: 'bool_or(r_bekannt or f_bekannt or a0_bekannt or a_fax_bekannt' },
  { id: 'kanal-im-haus-alles', datei: K62, was: 'Der Kanal der ausgelieferten Ware zählt als „noch im Haus"',
    alt: "sum(klein_kg + nebenkanal_kg) filter (where portion = 'lager')       as kanal_im_haus_kg",
    neu: 'sum(klein_kg + nebenkanal_kg)                                        as kanal_im_haus_kg' },
  { id: 'im-haus-alles', datei: K62, was: 'Auch die ausgelieferte Ware zählt als „noch im Haus"',
    alt: "sum(m2) filter (where portion = 'lager')                             as im_haus_heute_kg",
    neu: 'sum(m2)                                                              as im_haus_heute_kg' },
]

/* ---------- Ein Schema aus (womöglich verstellten) Migrationen ------------ */

function bauen(db, mutation) {
  datenbank(db)
  const verz = mkdtempSync(join(tmpdir(), 'pw-mut-'))
  cpSync(join(WURZEL, 'supabase/migrations'), join(verz, 'migrations'), { recursive: true })
  if (mutation) {
    const name = mutation.datei.split('/').pop()
    const ziel = join(verz, 'migrations', name)
    const text = readFileSync(ziel, 'utf8')
    if (!text.includes(mutation.alt)) { rmSync(verz, { recursive: true, force: true }); return 'Stelle nicht gefunden' }
    // Eine Verstellung in einer Migration, die eine spätere ohnehin ersetzt,
    // wirkt nie — und sähe dann wie „gut abgesichert" aus. Das ist der
    // gefährlichste Irrtum, den diese Sonde machen kann.
    const spaeter = readdirSync(join(verz, 'migrations')).filter(f => f.endsWith('.sql') && f > name)
      .find(f => readFileSync(join(verz, 'migrations', f), 'utf8').includes(mutation.alt))
    if (spaeter) { rmSync(verz, { recursive: true, force: true }); return `Stelle wird von ${spaeter} überschrieben` }
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
    // psql schreibt viele NOTICE-Zeilen; die echte Meldung ist die mit ERROR.
    const t = String(e.stderr ?? '')
    const zeilen = t.split('\n').filter(z => /\bERROR\b/.test(z))
    return (zeilen[zeilen.length - 1] ?? t.split('\n').filter(Boolean).pop() ?? 'Prüfung schlägt an').slice(0, 200)
  }
}

/**
 * Die Demodaten in ein frisch gebautes (womöglich verstelltes) Schema.
 * Einmal gezogen, danach nur noch eingespielt — das kostet je Verstellung
 * knapp zwei Sekunden statt einer neuen Saison.
 */
let ABZUG = null
function daten(db, quelle) {
  if (!ABZUG) {
    ABZUG = join(mkdtempSync(join(tmpdir(), 'pw-daten-')), 'demo.sql')
    execFileSync('pg_dump', [url(quelle), '--data-only', '--schema=public', '--schema=auth',
      '--no-owner', '--no-privileges', '-f', ABZUG], { encoding: 'utf8' })
  }
  // Die Migrationen legen Stammdaten an (Sorten, Gebinde, Ausgangsziele). Der
  // Abzug bringt dieselben mit — also erst leeren, sonst kollidieren die
  // Schlüssel. `cascade` ist hier gefahrlos: die Datenbank ist eine Wegwerf-Kopie.
  tue(db, `do $$
             declare t text;
             begin
               for t in select format('%I.%I', schemaname, tablename) from pg_tables
                         where schemaname in ('public', 'auth')
               loop execute 'truncate table ' || t || ' cascade'; end loop;
             end $$;`)
  // `session_replication_role = replica` schaltet Auslöser und Fremdschlüssel
  // für diese Sitzung ab — sonst legt der Auslöser auf auth.users beim
  // Einspielen ein Profil an, das der Abzug gleich darauf noch einmal bringt.
  execFileSync('psql', [url(db), '-qX', '-v', 'ON_ERROR_STOP=1',
    '-c', 'set session_replication_role = replica', '-f', ABZUG],
    { encoding: 'utf8', stdio: ['ignore', 'ignore', 'pipe'], maxBuffer: 64 * 1024 * 1024 })
  tue(db, 'select auswertung_aktualisieren()')
}

/**
 * Der Fingerabdruck der Ergebnisse — ändert die Verstellung überhaupt etwas?
 *
 * Über drei Sichten, nicht über eine: `erg_charge` trägt die Kilo, die
 * Saisonbilanz die Grenzen (dort wirken die Ableitungen, nirgends sonst), und
 * `mv_kaskade` die Zwischenschritte. Über `erg_charge` allein sähe eine
 * verstellte Ableitung wie „ohne Wirkung" aus — und das wäre die falsche
 * Entwarnung.
 *
 * Zahlen werden dabei **gerundet** verglichen, nicht als Text. `to_jsonb`
 * schreibt eine Zahl mit der Nachkommastellenzahl, die aus der Rechnung fällt:
 * `m0 * a0` und `m1 * a0` sind beide 0, stehen aber als `0.00000000` und
 * `0.000000000000` da. Wer den Text vergleicht, hält das für eine Änderung und
 * meldet eine Verstellung als „überlebt", die in Wahrheit gar nichts tut.
 */
const SICHTEN_FA = ['erg_charge', 'v_saisonbilanz', 'mv_kaskade']

function fingerabdruck(db) {
  const teile = SICHTEN_FA.map(sicht => {
    const spalten = frage(db, `
      select a.attname as spalte,
             (format_type(a.atttypid, a.atttypmod) ~ '^(numeric|double|real)') as zahl
        from pg_attribute a
        join pg_class c on c.oid = a.attrelid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = '${sicht}'
         and a.attnum > 0 and not a.attisdropped
       order by a.attnum`)
    const liste = spalten.map(s => s.zahl === true || s.zahl === 't'
      ? `round("${s.spalte}"::numeric, 6)::text`
      : `"${s.spalte}"::text`).join(', ')
    return `select md5(coalesce(string_agg(z, chr(10) order by z), '')) as h
              from (select array_to_string(array[${liste}], '|') as z from "${sicht}") s`
  })
  return wert(db, `select md5(string_agg(h, '|' order by h)) from (${teile.join(' union all ')}) alle`)
}

export async function laufen({ db, schnell }) {
  if (schnell) return []
  const raus = []
  const B = (o) => raus.push(befund({ sonde: '06_mutation', kuerzel: 'MUT', ...o }))
  const ziel = 'pw_mutation'

  // Grundlinie: sauberer Bau, echte Daten, Prüfung muss durchlaufen.
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
  // pruefung.sql hinterlässt eigene Daten — für den Vergleich zählt der Bau
  // mit den Demodaten. Also noch einmal frisch, dann die Daten hinein.
  bauen(ziel, null)
  daten(ziel, db)
  const F0 = fingerabdruck(ziel)
  const roh = inv.alle(ziel).filter(v => v.regel !== 'Unwissen')
  if (roh.length) {
    B({ klasse: 3, ort: { sicht: roh.map(v => v.regel).join(', ') },
        titel: 'Eine Invariante ist schon ohne Verstellung verletzt',
        steht_da: JSON.stringify(roh).slice(0, 300),
        muesste: 'Auf den unveränderten Demodaten halten alle Invarianten.',
        warum: 'Sonst zeigt jede Verstellung dieselbe Verletzung, und die Sonde lernt nichts.',
        beleg: 'pruefwerk/sonden/06_mutation.mjs',
        groesse: { wert: roh.length, einheit: 'verletzte Regeln', basis: 'Grundlinie mit Demodaten' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  const ergebnis = []
  for (const m of MUTATIONEN) {
    if (process.env.PW_LAUT) process.stderr.write(`   … ${m.id}\n`)
    const fehler = bauen(ziel, m)
    if (fehler) { ergebnis.push({ ...m, stand: 'baut nicht', wie: fehler }); continue }
    const gefangen = pruefungLaeuft(ziel)
    daten(ziel, db)
    const gleich = fingerabdruck(ziel) === F0
    const verletzt = inv.alle(ziel).filter(v => v.regel !== 'Unwissen')
    ergebnis.push(
      gefangen  ? { ...m, stand: 'gefangen', wie: `pruefung.sql — ${gefangen}` }
    : verletzt.length ? { ...m, stand: 'gefangen', wie: `Invariante „${verletzt.map(v => v.regel).join(', ')}"` }
    : gleich    ? { ...m, stand: 'ohne Wirkung', wie: 'keine Zahl in erg_charge, v_saisonbilanz oder mv_kaskade ändert sich' }
    :             { ...m, stand: 'überlebt', wie: 'Zahlen ändern sich, weder pruefung.sql noch eine Invariante meldet etwas' })
  }

  const ueberlebt = ergebnis.filter(e => e.stand === 'überlebt')
  const gefangen = ergebnis.filter(e => e.stand === 'gefangen')
  const wirkungslos = ergebnis.filter(e => e.stand === 'ohne Wirkung')
  if (wirkungslos.length) {
    B({ klasse: 2, ort: { datei: 'supabase/migrations' },
        titel: `${wirkungslos.length} Verstellungen ändern auf den Demodaten keine einzige Zahl`,
        steht_da: wirkungslos.map(e => `„${e.was}" (${e.id})`).join('; '),
        muesste: 'Entweder Demodaten, in denen die Stelle wirkt, oder ein eigener Papierfall, der sie '
               + 'ansteuert. Solange keine Daten die Stelle erreichen, sagt kein Test etwas über sie — '
               + 'und eine grüne Suite bedeutet dort nichts.',
        warum: 'Eine Formel, die auf den Prüfdaten nichts bewirkt, ist auf den Prüfdaten unsichtbar. '
             + 'Sie wirkt aber im Betrieb, sobald dort die passende Messung auftaucht — dann zum '
             + 'ersten Mal, ungeprüft. Drei Beispiele aus dieser Liste: Der Sockel a₀ ist in der '
             + 'Demosaison überall 0 (der Nachweis-Test hält ihn zurück), der Boden des verkaufsfähigen '
             + 'Anteils bei 25 % wird nie erreicht (der kleinste Anteil liegt bei 0,671), und der '
             + 'Deckel der Verdunstungsrate bei 5 % je Tag liegt hundertfach über der gemessenen Rate. '
             + 'Alle drei sind Schutzmassnahmen für den Ausnahmefall — und genau der ist ungeprüft.',
        beleg: 'pruefwerk/sonden/06_mutation.mjs',
        groesse: { wert: wirkungslos.length, einheit: 'Verstellungen ohne Wirkung',
                   basis: `${ergebnis.length} Verstellungen auf den Demodaten` },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'mittel' })
  }
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
 * Selbstprobe: Eine Verstellung, die die Masse nicht mehr erhält, **muss**
 * auffallen. Genommen wird „zu klein statt zu gross", weil beide Koeffizienten
 * in den Demodaten von null verschieden sind — anders als der Sockel.
 */
export async function selbstprobe({ db = 'demo' } = {}) {
  const ziel = 'pw_mutation_probe'
  if (bauen(ziel, null)) return false
  daten(ziel, db)
  const F0 = fingerabdruck(ziel)
  const m = MUTATIONEN.find(x => x.id === 'klein-statt-gross')
  if (bauen(ziel, m)) return false
  daten(ziel, db)
  return fingerabdruck(ziel) !== F0
}
