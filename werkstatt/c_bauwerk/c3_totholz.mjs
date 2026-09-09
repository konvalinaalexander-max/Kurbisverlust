/**
 * C3 — Totholz in der Oberfläche, mit Beweis.
 *
 * DIE FRAGE
 *
 * `src/lib/i18n.ts` ist mit 1434 Zeilen die grösste Datei des Programms. Sie
 * enthält jeden Text in sechs Sprachen; ein Schlüssel kostet also sechs Zeilen
 * plus den deutschen Eintrag. Ein Schlüssel, den niemand mehr anzeigt, kostet
 * dasselbe und zeigt nichts.
 *
 * Dasselbe gilt für Exporte, die niemand einführt, und für Klassen im
 * Stylesheet, die in keinem Element stehen.
 *
 * WARUM EIN NAIVES WERKZEUG HIER GEFÄHRLICH IST
 *
 * Die Oberfläche greift Texte **nicht nur** über `t('schluessel')` ab. In
 * `lib/taetigkeit.ts` steht eine Tabelle mit `text: TextId`, und in
 * `NeueArbeit.tsx` ein `Record<string, TextId>`; von dort kommen Schlüssel als
 * Werte in `t(a.text)`. Ein Werkzeug, das nur nach `t('…')` sucht, hielte
 * genau diese Texte für tot — und ihr Verschwinden fiele erst dem Arbeiter in
 * der Halle auf.
 *
 * Deshalb zählt hier **jedes** Vorkommen des Schlüssels als Zeichenkette
 * irgendwo im Quelltext als Benutzung. Das ist absichtlich grosszügig: Es
 * findet weniger Totholz, aber es schlägt nie vor, etwas Lebendiges zu fällen.
 *
 * DER BEWEIS
 *
 * Ein Vorschlag ohne Beweis ist eine Meinung. Dieses Werkzeug legt deshalb
 * eine Wegwerfkopie des Quellbaums an, **entfernt die Kandidaten wirklich**
 * und lässt darauf `tsc` und die Testsuite laufen. Erst was das übersteht,
 * kommt in den Bericht — mit der Zeilenzahl, die es einspart.
 *
 * Für die Texte ist `tsc` ein echter Beweis und nicht bloss ein Indiz: `TextId`
 * ist `keyof typeof de`. Fällt ein Schlüssel weg, passt jede Tabelle, die ihn
 * als `TextId` führt, nicht mehr — und der Übersetzer sagt es.
 *
 * Für Klassen im Stylesheet kann `tsc` nichts beweisen. Sie stehen deshalb als
 * **Kandidaten** da, ausdrücklich ohne Beweis, und werden nicht als Reduktion
 * gezählt.
 */
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync, cpSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { WURZEL, lies, alleDateien, zeilen, befund, messung } from '../umgebung.mjs'

export const lang = true

const WERKSTATT = 'C — Bauwerk'
const I18N = 'src/lib/i18n.ts'

/* ---------- 1. Texte, die niemand mehr anzeigt ---------------------------- */

/**
 * Die Schlüssel des deutschen Wörterbuchs. Gelesen wird der Block zwischen
 * `const de = {` und der Zeile, die ihn schliesst — nicht die ganze Datei,
 * damit die fünf Übersetzungen nicht mitgezählt werden.
 */
function textschluessel(quelle) {
  const anfang = quelle.indexOf('const de = {')
  if (anfang < 0) throw new Error(`${I18N}: der Block "const de = {" fehlt — der Aufbau der `
    + 'Datei hat sich geändert, und dieses Werkzeug darf nichts behaupten.')
  const ende = quelle.indexOf('\n}', anfang)
  const block = quelle.slice(anfang, ende)
  return [...block.matchAll(/^\s{2}([a-zA-Z_][a-zA-Z0-9_]*)\s*:/gm)].map(m => m[1])
}

/** Jede Datei ausser i18n.ts selbst — dort steht jeder Schlüssel sechsmal. */
const pfade = (verzeichnis, muster) => alleDateien(verzeichnis, { muster }).map(d => d.pfad)

const anderswo = () => pfade('src', /\.(ts|tsx)$/).filter(p => !p.endsWith('i18n.ts'))
  .concat(pfade('test', /\.(ts|tsx|mjs)$/))
  .concat(pfade('pruefstand', /\.(mjs|json)$/))
  .map(lies).join('\n')

/* ---------- 2. Exporte, die niemand einführt ------------------------------ */

const EINSTIEGE = /^src\/(main|App)\.tsx$/

function exporte() {
  const raus = []
  for (const pfad of pfade('src', /\.(ts|tsx)$/)) {
    if (EINSTIEGE.test(pfad)) continue
    const text = lies(pfad)
    for (const m of text.matchAll(
      /^export\s+(?:default\s+)?(?:async\s+)?(function|const|let|class|type|interface)\s+([A-Za-z_][A-Za-z0-9_]*)/gm))
      raus.push({ pfad, art: m[1], name: m[2] })
  }
  return raus
}

/** Wird der Name irgendwo ausserhalb seiner eigenen Datei erwähnt? */
function eingefuehrt(name, eigenePfad) {
  const wort = new RegExp(`\\b${name}\\b`)
  return pfade('src', /\.(ts|tsx)$/).concat(pfade('test', /\.(ts|tsx)$/))
    .some(p => p !== eigenePfad && wort.test(lies(p)))
}

/* ---------- 3. Klassen im Stylesheet, die in keinem Element stehen -------- */

function cssKlassen() {
  const css = pfade('src', /\.css$/).map(lies).join('\n')
  const benutzt = pfade('src', /\.(ts|tsx)$/).map(lies).join('\n')
  const definiert = [...new Set([...css.matchAll(/\.([a-zA-Z][a-zA-Z0-9_-]*)\s*(?=[,{:.\s])/g)]
    .map(m => m[1]))]
  return { definiert, tot: definiert.filter(k => !new RegExp(`\\b${k}\\b`).test(benutzt)) }
}

/**
 * Das `export` vor einem Namen streichen, der nur in seiner eigenen Datei
 * gebraucht wird. Kein Zeichen Verhalten ändert sich — aber `tsc` sagt, ob
 * die Behauptung „braucht sonst niemand" stimmt. Damit ist auch dieser
 * Vorschlag bewiesen und nicht bloss behauptet.
 */
function exportStreichen(ort, kandidaten) {
  for (const pfad of new Set(kandidaten.map(k => k.pfad))) {
    const voll = join(ort, pfad)
    let text = readFileSync(voll, 'utf8')
    for (const k of kandidaten.filter(k => k.pfad === pfad))
      text = text.replace(
        new RegExp(`^export\\s+((?:async\\s+)?(?:${k.art})\\s+${k.name}\\b)`, 'm'), '$1')
    writeFileSync(voll, text)
  }
}

/* ---------- Der Beweis ---------------------------------------------------- */

/**
 * Eine Wegwerfkopie des Quellbaums, in der die Kandidaten wirklich fehlen —
 * dann `tsc` und die Testsuite. Kopiert werden nur die Verzeichnisse, die für
 * beides nötig sind; `node_modules` wird verknüpft statt kopiert, sonst dauert
 * der Beweis länger als die Suche.
 */
function beweisen(entfernen) {
  const ort = mkdtempSync(join(tmpdir(), 'wk-c3-'))
  try {
    // `supabase` gehört dazu, auch wenn hier nur der Quelltext geändert wird: Zwei
    // Tests lesen die Migrationen und vergleichen sie mit `SCHEMA_ERWARTET`. Fehlen
    // sie, schlägt der Beweis auf einer **unveränderten** Kopie fehl — und dann
    // verwirft er jeden Vorschlag, auch die richtigen. Die Selbstprobe unten prüft
    // deshalb ausdrücklich, dass die leere Kopie durchläuft.
    for (const teil of ['src', 'test', 'supabase', 'tsconfig.json', 'tsconfig.app.json',
                        'tsconfig.node.json', 'package.json', 'index.html', 'vite.config.ts']) {
      try { cpSync(join(WURZEL, teil), join(ort, teil), { recursive: true }) } catch { /* gibt es nicht */ }
    }
    execFileSync('ln', ['-s', join(WURZEL, 'node_modules'), join(ort, 'node_modules')])

    entfernen(ort)

    const lauf = (cmd, args) => {
      try {
        execFileSync(cmd, args, { cwd: ort, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
                                  timeout: 300000 })
        return { gut: true, meldung: '' }
      } catch (e) {
        return { gut: false, meldung: String((e.stdout ?? '') + (e.stderr ?? '')).split('\n')
          .filter(z => /^not ok|Error|error TS|# fail/.test(z)).slice(0, 4).join(' | ')
          || String((e.stdout ?? '') + (e.stderr ?? '')).split('\n').slice(-6).join(' | ') }
      }
    }
    const tsc = lauf('npx', ['tsc', '--noEmit', '-p', 'tsconfig.app.json'])
    if (!tsc.gut) return { gut: false, wo: 'tsc', ...tsc }
    const test = lauf('node', ['--test', ...pfade('test', /\.test\.ts$/).map(p => join(ort, p))])
    if (!test.gut) return { gut: false, wo: 'Testsuite', ...test }
    return { gut: true, wo: 'tsc und Testsuite' }
  } finally {
    rmSync(ort, { recursive: true, force: true })
  }
}

/** Die Zeilen eines Schlüssels aus allen sechs Wörterbüchern streichen. */
function textenEntfernen(ort, schluessel) {
  const pfad = join(ort, I18N)
  const alt = readFileSync(pfad, 'utf8').split('\n')
  const muster = new RegExp(`^\\s{2}(?:${schluessel.join('|')})\\s*:`)
  const neu = alt.filter(z => !muster.test(z))
  writeFileSync(pfad, neu.join('\n'))
  return alt.length - neu.length
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen() {
  const raus = []
  const quelle = lies(I18N)
  const alleSchluessel = textschluessel(quelle)
  const rest = anderswo()
  const totKandidaten = alleSchluessel.filter(k => !new RegExp(`['"\`]${k}['"\`]`).test(rest)
                                               && !new RegExp(`\\b${k}\\b`).test(rest))

  let geschafft = null
  if (totKandidaten.length) {
    let gestrichen = 0
    const probe = beweisen(ort => { gestrichen = textenEntfernen(ort, totKandidaten) })
    geschafft = { ...probe, schluessel: totKandidaten, zeilen: gestrichen }
  }

  const alleExporte = exporte()
  const toteExporte = alleExporte.filter(e => !eingefuehrt(e.name, e.pfad))
  const exportBeweis = toteExporte.length
    ? beweisen(ort => exportStreichen(ort, toteExporte)) : null

  const css = cssKlassen()
  const cssTot = css.tot

  raus.push(messung({
    werkstatt: WERKSTATT, titel: 'Was im Quelltext niemand mehr anspricht', einheit: 'Fundstellen',
    spalten: ['Art', 'gesucht in', 'gefunden', 'Beweis', 'Zeilen, die wegfielen'],
    erklaerung: 'Gesucht wurde grosszügig: Ein Text gilt schon dann als benutzt, wenn sein '
      + 'Schlüssel **irgendwo** im Quelltext als Wort vorkommt — nicht erst bei `t(\'schluessel\')`. '
      + 'Das findet weniger Totholz, kann aber nie etwas Lebendiges vorschlagen: Die Oberfläche '
      + 'holt Texte auch über Tabellen wie `Record<string, TextId>` ab, und ein engeres Muster '
      + 'hätte genau die für tot erklärt. Die Spalte „Beweis" sagt, ob die Kandidaten in einer '
      + 'Wegwerfkopie des Quellbaums tatsächlich entfernt wurden und `tsc` samt Testsuite danach '
      + 'noch durchliefen.',
    zeilen: [
      { 'Art': 'Texte in sechs Sprachen', 'gesucht in': `${alleSchluessel.length} Schlüssel`,
        'gefunden': totKandidaten.length,
        'Beweis': !totKandidaten.length ? 'nichts zu beweisen'
          : geschafft.gut ? `entfernt, ${geschafft.wo} grün`
          : `fehlgeschlagen bei ${geschafft.wo}`,
        'Zeilen, die wegfielen': geschafft?.gut ? geschafft.zeilen : '—' },
      { 'Art': 'Exporte ohne Einführung', 'gesucht in': `${alleExporte.length} Exporte`,
        'gefunden': toteExporte.length,
        'Beweis': !exportBeweis ? 'nichts zu beweisen'
          : exportBeweis.gut ? `\`export\` gestrichen, ${exportBeweis.wo} grün`
          : `fehlgeschlagen bei ${exportBeweis.wo}`,
        'Zeilen, die wegfielen': exportBeweis?.gut ? '0 (nur das Schlüsselwort)' : '—' },
      { 'Art': 'Klassen im Stylesheet', 'gesucht in': `${css.definiert.length} Klassen`,
        'gefunden': cssTot.length, 'Beweis': 'kein Beweis möglich (tsc sieht CSS nicht)',
        'Zeilen, die wegfielen': '—' },
    ],
  }))

  if (!totKandidaten.length) raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'TOT', klasse: 1, marke: 'kein Fehler', sicherheit: 'hoch',
    ort: { datei: I18N },
    titel: `Geprüft und in Ordnung: alle ${alleSchluessel.length} Texte werden irgendwo angezeigt`,
    steht_da: `\`${I18N}\` führt ${alleSchluessel.length} Schlüssel in sechs Sprachen, `
      + `${zeilen(I18N).length} Zeilen. Kein einziger Schlüssel fehlt im übrigen Quelltext — `
      + 'auch keiner der Schlüssel, die nur mittelbar über Tabellen wie `Record<string, TextId>` '
      + 'abgerufen werden.',
    muesste: '—',
    warum: 'Die grösste Datei des Programms ist auch die, in der Totholz am billigsten entsteht: '
      + 'Ein Text, der nicht mehr gebraucht wird, kostet weiterhin sechs Zeilen und wird bei jeder '
      + 'Sprachänderung mitgeschleppt. Dass hier nichts liegt, ist ein Befund und keine '
      + 'Selbstverständlichkeit.',
    beleg: 'werkstatt/c_bauwerk/c3_totholz.mjs, Messreihe „Was im Quelltext niemand mehr anspricht"',
    groesse: { wert: alleSchluessel.length, einheit: 'Textschlüssel, alle mit Abnehmer',
               basis: `${zeilen(I18N).length} Zeilen geprüft` },
    aufwand: 'klein',
  }))

  if (geschafft?.gut && geschafft.zeilen > 0) raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'TOT', klasse: 1, marke: 'Reduktion', sicherheit: 'hoch',
    ort: { datei: I18N },
    titel: `${totKandidaten.length} Texte werden in sechs Sprachen gepflegt und nirgends angezeigt`,
    steht_da: `\`${I18N}\` führt ${alleSchluessel.length} Textschlüssel in sechs Sprachen. `
      + `${totKandidaten.length} davon kommen im übrigen Quelltext an keiner einzigen Stelle vor — `
      + 'weder als Aufruf noch als Wert in einer Tabelle: '
      + totKandidaten.slice(0, 12).map(k => `\`${k}\``).join(', ')
      + (totKandidaten.length > 12 ? ` und ${totKandidaten.length - 12} weitere` : '') + '.',
    muesste: `Streichen. ${geschafft.zeilen} Zeilen fallen weg, und die grösste Datei des `
      + `Programms wird um ${(100 * geschafft.zeilen / zeilen(I18N).length).toFixed(0)} % kleiner.`,
    warum: 'Ein toter Text ist teurer als toter Code an anderer Stelle: Er wird bei jeder '
      + 'Sprachänderung mitübersetzt, taucht in jeder Durchsicht auf und lässt den nächsten Leser '
      + 'nach der Maske suchen, die ihn anzeigt. Es gibt sie nicht.',
    beleg: `werkstatt/c_bauwerk/c3_totholz.mjs: in einer Wegwerfkopie des Quellbaums entfernt, `
      + `${geschafft.wo} anschliessend grün`,
    groesse: { wert: geschafft.zeilen, einheit: 'Zeilen, die ersatzlos wegfallen können',
               basis: `bewiesen: entfernt, ${geschafft.wo} grün` },
    gegenrede: 'Ein Text kann für eine Maske vorgesehen sein, die noch kommt — dann wäre das '
      + 'Streichen Arbeit, die später doppelt gemacht wird. Dagegen spricht, dass ein '
      + 'vorbereiteter Text ohne Maske niemandem auffällt und beim nächsten Umbau ohnehin nicht '
      + 'mehr passt. Und die Suche ist so grosszügig gehalten, dass ein Schlüssel, der auch nur '
      + 'als Wort irgendwo steht, gar nicht erst in dieser Liste landet.',
    aufwand: 'klein',
  }))

  if (geschafft && !geschafft.gut) raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'TOT', klasse: 1, marke: 'kein Fehler', sicherheit: 'hoch',
    ort: { datei: I18N },
    titel: `${totKandidaten.length} Textschlüssel sahen tot aus und sind es nicht`,
    steht_da: `Die Suche hielt ${totKandidaten.length} Schlüssel für unbenutzt. In einer `
      + `Wegwerfkopie entfernt, bricht ${geschafft.wo}: ${geschafft.meldung}`,
    muesste: '—',
    warum: 'Genau dafür ist der Beweis da. Ohne ihn stünde hier eine Reduktion, die beim Ausführen '
      + 'die Oberfläche zerlegt hätte.',
    beleg: 'werkstatt/c_bauwerk/c3_totholz.mjs',
    groesse: { wert: totKandidaten.length, einheit: 'Kandidaten, die der Beweis verworfen hat',
               basis: geschafft.wo },
    aufwand: 'klein',
  }))

  if (toteExporte.length && exportBeweis?.gut) raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'TOT', klasse: 1, marke: 'Reduktion', sicherheit: 'mittel',
    ort: { datei: toteExporte[0].pfad },
    titel: `${toteExporte.length} Exporte werden von keiner anderen Datei eingeführt`,
    steht_da: toteExporte.map(e => `\`${e.name}\` (${e.art}, ${e.pfad})`).join(', ') + '.',
    muesste: 'Wo der Name nur in seiner eigenen Datei gebraucht wird, kann `export` weg — dann '
      + 'sieht jeder Leser sofort, dass er nichts anderswo kaputt macht, wenn er ihn ändert. Wo '
      + 'er gar nicht gebraucht wird, kann er ganz weg.',
    warum: 'Ein `export` ist ein Versprechen an den Rest des Programms. Ein Versprechen, das '
      + 'niemand einlöst, macht jede spätere Änderung an dieser Stelle vorsichtiger, als sie sein '
      + 'müsste.',
    beleg: 'werkstatt/c_bauwerk/c3_totholz.mjs: Wortsuche über src und test, danach in einer '
      + 'Wegwerfkopie das `export` gestrichen — '
      + (exportBeweis?.gut ? `${exportBeweis.wo} anschliessend grün`
                           : `${exportBeweis?.wo} bricht: ${exportBeweis?.meldung}`),
    groesse: { wert: toteExporte.length,
               einheit: 'Exporte ohne Abnehmer — sie sparen keine einzige Zeile, sie verkleinern '
                      + 'nur die Fläche, auf die der nächste Leser achten muss',
               basis: `von ${alleExporte.length} Exporten insgesamt`
                    + (exportBeweis?.gut ? `, bewiesen: ${exportBeweis.wo} grün` : '') },
    gegenrede: 'Der Ertrag ist klein und leicht zu überschätzen: **keine einzige Zeile** fällt '
      + 'weg, nur ein Schlüsselwort. Wer daraus eine Reduktion des Codes macht, rechnet sich '
      + 'etwas schön. Und ein Export kann absichtlich dastehen, damit ein künftiger Test ihn '
      + 'greifen kann — dann gehört ein Wort daneben, warum. Der Wert liegt allein darin, dass '
      + 'jeder dieser Namen heute wie eine Zusage an das ganze Programm aussieht und keine ist.',
    aufwand: 'klein',
  }))

  if (cssTot.length) raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'TOT', klasse: 1, marke: 'Reduktion', sicherheit: 'niedrig',
    ort: { datei: 'src/index.css' },
    titel: `${cssTot.length} Klassen im Stylesheet stehen in keinem Element`,
    steht_da: cssTot.slice(0, 15).map(k => `\`.${k}\``).join(', ')
      + (cssTot.length > 15 ? ` und ${cssTot.length - 15} weitere` : '') + '.',
    muesste: 'Vor dem Streichen gegenprüfen — und zwar mit dem Bildschirm-Prüfstand, nicht mit '
      + 'dem Auge: die Seiten vorher und nachher rendern und die Bilder vergleichen. `tsc` sieht '
      + 'kein CSS und kann hier nichts beweisen.',
    warum: 'Ein Stylesheet, in dem die Hälfte nichts tut, verleitet dazu, beim nächsten Umbau eine '
      + 'vorhandene Klasse zu benutzen, die anders aussieht als ihr Name verspricht.',
    beleg: 'werkstatt/c_bauwerk/c3_totholz.mjs: Klassennamen aus den Stylesheets gegen alle .ts/.tsx',
    groesse: { wert: cssTot.length, einheit: 'Klassen ohne nachweisbaren Träger',
               basis: 'Wortsuche, ohne Beweis' },
    gegenrede: 'Die Suche kennt keine zusammengesetzten Klassennamen (`className={`karte '
      + '${eng ? "schmal" : ""}`}`) und keine, die aus einer Tabelle kommen. Sie überschätzt das '
      + 'Totholz deshalb sicher — darum steht hier „Sicherheit niedrig" und ausdrücklich kein '
      + 'Beweis. Diese Zahl ist eine Suchliste, keine Streichliste.',
    aufwand: 'mittel',
  }))

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Der eingebaute Fehler ist ein **falscher** Vorschlag: In der Wegwerfkopie
 * wird ein Textschlüssel entfernt, der nachweislich gebraucht wird. Der Beweis
 * muss daran scheitern. Täte er es nicht, wäre er keiner — und dann wäre jede
 * „bewiesene Reduktion" dieses Werkzeugs eine Behauptung.
 *
 * Die Gegenprobe: eine Kopie **ohne** Änderung muss durchlaufen. Sonst läge der
 * Fehler an der Kopie, und das Werkzeug würde jeden Vorschlag verwerfen — auch
 * die richtigen, und ohne dass es jemandem auffiele.
 */
export async function selbstprobe() {
  const unveraendert = beweisen(() => {})
  if (!unveraendert.gut) return false

  const quelle = lies(I18N)
  const alle = textschluessel(quelle)
  const rest = anderswo()
  const lebendig = alle.find(k => new RegExp(`['"\`]${k}['"\`]`).test(rest))
  if (!lebendig) return false

  const mitFehler = beweisen(ort => textenEntfernen(ort, [lebendig]))
  return !mitFehler.gut
}
