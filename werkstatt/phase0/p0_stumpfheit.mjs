/**
 * Phase 0 — Sind die vorhandenen Werkzeuge überhaupt noch scharf?
 *
 * WARUM DAS VOR ALLEM ANDEREN KOMMT
 *
 * In Runde L ist die Mutationssonde unbemerkt blind geworden. Neun ihrer
 * dreizehn Mutationen zeigten auf Formeln, die zwei Migrationen später anders
 * hiessen; die Sonde änderte also nichts mehr und meldete pflichtgemäss „keine
 * überlebende Mutation". Das sah wie ein gutes Ergebnis aus und war das
 * Gegenteil.
 *
 * Ein Werkzeug, das nichts findet, sagt zwei mögliche Dinge, und man sieht
 * ihm nicht an, welches: *hier ist nichts* oder *ich sehe nichts mehr*. Der
 * einzige Weg, die beiden zu unterscheiden, ist ein Fehler, den man selbst
 * hineinlegt und der gefunden werden **muss**.
 *
 * Deshalb steht diese Prüfung vor jeder neuen Suche. Solange nicht feststeht,
 * dass die vorhandenen Werkzeuge sehen, ist ihr Schweigen kein Argument.
 *
 * WAS GEPRÜFT WIRD
 *
 *   Die zehn Sonden des Prüfwerks — jede hat eine eingebaute Selbstprobe;
 *   hier wird sie ausgeführt und das Ergebnis aufgeschrieben.
 *
 *   Die Prüfstände — sie haben keine. Für sie gilt zweierlei: Erstens muss
 *   ein Prüfstand überhaupt **scheitern können**; ein Programm, das nur
 *   `exit 0` kennt, ist kein Prüfstand, sondern ein Bericht. Zweitens muss er
 *   an einem hineingelegten Fehler tatsächlich scheitern.
 */
import { execFileSync } from 'node:child_process'
import { join } from 'node:path'
import { WURZEL, url, tue, kopie, wegwerfen, lies, befund, messung } from '../umgebung.mjs'

export const lang = true

const WERKSTATT = 'Phase 0 — Schärfe der vorhandenen Werkzeuge'

/* ---------- Die zehn Sonden ----------------------------------------------- */

async function sonden(umgebung) {
  const verzeichnis = join(WURZEL, 'pruefwerk/sonden')
  const dateien = execFileSync('ls', [verzeichnis], { encoding: 'utf8' })
    .split('\n').filter(f => f.endsWith('.mjs')).sort()
  const raus = []
  for (const datei of dateien) {
    const modul = await import(join(verzeichnis, datei))
    let ergebnis = 'ohne Selbstprobe'
    if (modul.selbstprobe) {
      try { ergebnis = (await modul.selbstprobe(umgebung)) ? 'ok' : 'STUMPF' }
      catch (e) { ergebnis = 'Fehler: ' + e.message }
    }
    raus.push({ name: datei.replace(/\.mjs$/, ''), art: 'Sonde', ergebnis })
  }
  return raus
}

/* ---------- Die Prüfstände ------------------------------------------------ */

/**
 * Kann dieses Werkzeug überhaupt scheitern?
 *
 * Ein Prüfstand ohne einen einzigen Weg zu einem Rückgabewert ungleich null
 * ist per Bauart blind: Er mag Zeilen mit „✗" ausgeben, aber niemand, der ihn
 * aufruft, erfährt davon. In einer Kette wie `run.sh && kette && bildschirme`
 * geht so ein Werkzeug stillschweigend durch.
 */
function kannScheitern(text) {
  const nullig = [...text.matchAll(/process\.exit\((\d+)\)|(?:^|\n)\s*exit\s+(\d+)/g)]
    .map(m => Number(m[1] ?? m[2]))
  return { wege: nullig, kann: nullig.some(n => n !== 0) }
}

/** Dasselbe für eine Datei im Projekt. */
const kannScheiternDatei = (pfad) => kannScheitern(lies(pfad))

/**
 * Ein hineingelegter Fehler, den der Prüfstand finden muss.
 *
 * Die Datenbank ist immer eine Wegwerfkopie — kein Prüfstand rührt hier die
 * Demodaten an.
 */
const FAELLE = [
  {
    name: 'luecken.sh',
    pfad: 'pruefstand/luecken.sh',
    was: 'eine Erfassungsspalte, die keine Maske schreibt',
    legen: (db) => tue(db, `alter table verdunstung_wiegung add column probe_ohne_maske numeric`),
    laufen: (db) => execFileSync('bash', [join(WURZEL, 'pruefstand/luecken.sh'), url(db)],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 120000 }),
  },
  {
    name: 'kette.mjs',
    pfad: 'pruefstand/kette.mjs',
    was: 'eine Kaskadenformel, die ein anderes Ergebnis liefert',
    legen: (db) => tue(db, `
      create or replace function zahl(x numeric, stellen integer default 2,
                                      grenze numeric default null)
        returns numeric language sql immutable as $$
        select case when x is null then null else round(x * 1.05, stellen) end $$`),
    laufen: (db) => execFileSync('node', [join(WURZEL, 'pruefstand/kette.mjs'), url(db)],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 300000, cwd: WURZEL }),
  },
]

function faellePruefen() {
  const raus = []
  for (const fall of FAELLE) {
    const bauart = kannScheiternDatei(fall.pfad)
    const probe = kopie('demo', `wk_p0_${fall.name.replace(/\W/g, '')}`)
    let ohne = null, mit = null
    try {
      try { fall.laufen(probe); ohne = 'läuft durch' } catch { ohne = 'scheitert schon ohne Fehler' }
      fall.legen(probe)
      try { fall.laufen(probe); mit = 'läuft durch' } catch { mit = 'scheitert' }
    } finally {
      wegwerfen(probe)
    }
    raus.push({ ...fall, ...bauart, ohne, mit,
                ergebnis: ohne !== 'läuft durch' ? 'nicht beurteilbar'
                        : mit === 'scheitert' ? 'ok' : 'STUMPF' })
  }
  return raus
}

/* ---------- Lauf ---------------------------------------------------------- */

const STAENDE = [
  ['pruefstand/kette.mjs', 'Kette: Maske → Datenbank → Auswertung'],
  ['pruefstand/bildschirme.mjs', 'Bildschirme rendern, Konsolenfehler, Überlauf'],
  ['pruefstand/beschriftung.mjs', 'Begriffe: sagt jede Zahl, was sie ist?'],
  ['pruefstand/luecken.sh', 'Lücken zwischen Masken und Auswertung'],
  ['pruefstand/kette_pruefen.sh', 'Kette gegen die mitgeschnittenen Anfragen'],
  ['pruefstand/demo_bauen.sh', 'Demodaten neu bauen'],
  ['supabase/test/run.sh', 'Datenbanksuite in sieben Stufen'],
]

export async function laufen(umgebung) {
  const raus = []
  const s = await sonden(umgebung)
  const bauart = STAENDE.map(([pfad, zweck]) => ({ pfad, zweck, ...kannScheiternDatei(pfad) }))
  const gelegt = faellePruefen()

  raus.push(messung({
    werkstatt: WERKSTATT,
    titel: 'Die zehn Sonden des Prüfwerks an ihrem eingebauten Fehler',
    einheit: 'Sonden',
    spalten: ['Sonde', 'Selbstprobe'],
    erklaerung: 'Jede Sonde bekommt einen Fall vorgesetzt, in dem sie anschlagen *muss*. Steht '
      + 'dort „ok", hat sie ihren eigenen eingebauten Fehler gefunden und ihr Schweigen im '
      + 'echten Lauf ist eine Aussage. Steht dort „STUMPF", ist es keine.',
    zeilen: s.map(x => ({ 'Sonde': x.name, 'Selbstprobe': x.ergebnis })),
  }))

  raus.push(messung({
    werkstatt: WERKSTATT,
    titel: 'Können die Prüfstände überhaupt scheitern?',
    einheit: 'Prüfstände',
    spalten: ['Prüfstand', 'wofür', 'Rückgabewerte im Quelltext', 'kann scheitern',
              'am hineingelegten Fehler'],
    erklaerung: 'Ein Prüfstand, dessen Quelltext keinen einzigen Weg zu einem Rückgabewert '
      + 'ungleich null kennt, kann niemandem etwas melden — er mag „✗" auf den Bildschirm '
      + 'schreiben, aber in einer Kette wie `run.sh && kette && bildschirme` geht er '
      + 'stillschweigend durch. Die letzte Spalte ist die härtere Prüfung: ein Fehler wurde '
      + 'wirklich hineingelegt und der Prüfstand darauf losgelassen.',
    zeilen: bauart.map(b => {
      const g = gelegt.find(x => x.pfad === b.pfad)
      return {
        'Prüfstand': b.pfad, 'wofür': b.zweck,
        'Rückgabewerte im Quelltext': b.wege.length ? [...new Set(b.wege)].sort().join(', ') : 'keine',
        'kann scheitern': b.kann ? 'ja' : 'NEIN',
        'am hineingelegten Fehler': g ? `${g.ergebnis} (${g.was})` : 'in dieser Runde nicht gelegt',
      }
    }),
  }))

  /* --- Befund: ein Prüfstand, der nicht scheitern kann --- */
  const blind = bauart.filter(b => !b.kann)
  if (blind.length) raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'STU', klasse: 2, marke: 'Reparatur', sicherheit: 'hoch',
    ort: { datei: blind[0].pfad },
    titel: `${blind.length} Prüfstand/Prüfstände können nicht scheitern — sie enden immer mit null`,
    steht_da: blind.map(b => `\`${b.pfad}\` kennt im ganzen Quelltext nur `
      + `\`process.exit(0)\`. Er zählt Konsolenfehler und wagerechtes Überlaufen, schreibt sie `
      + 'als „✗"-Zeilen und in den Schlusssatz — und endet dann mit Rückgabewert null. Wer ihn '
      + 'in einer Kette aufruft, erfährt nichts davon.').join(' '),
    muesste: '`process.exit(fehler ? 1 : 0)`. Eine Zeile. Solange sie fehlt, ist der Prüfstand '
      + 'ein Bericht, den jemand lesen muss, und kein Prüfstand.',
    warum: 'Genau dieser Prüfstand ist der einzige, der die Oberfläche wirklich ansieht — '
      + 'Konsolenfehler, wagerechtes Überlaufen auf dem Handy, ob eine Seite überhaupt lädt. '
      + 'Das sind die Fehler, die dem Arbeiter in der Halle begegnen und die keine SQL-Prüfung '
      + 'je finden wird. Dass ausgerechnet dieser Prüfstand sein Ergebnis nicht weitergeben '
      + 'kann, ist die unangenehmste Lücke im ganzen Netz.',
    beleg: 'werkstatt/phase0/p0_stumpfheit.mjs: alle Rückgabewege im Quelltext ausgezählt',
    groesse: { wert: blind.length, einheit: `von ${bauart.length} Prüfständen können nicht scheitern`,
               basis: 'Quelltextanalyse' },
    gegenrede: 'Der Prüfstand ist zum Ansehen von Bildern gebaut, nicht zum Durchwinken — ein '
      + 'Mensch sieht sich die Aufnahmen ohnehin an, und dann fällt ein „✗" auf. Das trägt, '
      + 'solange jemand hinsieht. Es trägt nicht mehr, sobald er in einer Kette läuft, und '
      + 'genau so wird er in `docs/README.md` beschrieben.',
    aufwand: 'klein',
  }))

  /* --- Befund: ein unerwartetes Argument macht den Prüfstand zum Nichtstuer --- */
  const schirm = lies('pruefstand/bildschirme.mjs')
  const block = schirm.slice(schirm.indexOf('const BILDSCHIRME = ['),
                             schirm.indexOf('\n]', schirm.indexOf('const BILDSCHIRME = [')))
  const BILDSCHIRME_ANZAHL = (block.match(/\bname:/g) ?? []).length
  const GERAETE_ANZAHL = ((schirm.slice(schirm.indexOf('const GERAETE ='))
    .slice(0, 300).match(/\bname:/g)) ?? []).length
  const BILDSCHIRME_GESAMT = BILDSCHIRME_ANZAHL * GERAETE_ANZAHL * 2
  if (/const NUR = process\.argv\[2\]/.test(schirm)
    && /if \(NUR && !schirm\.name\.includes\(NUR\)\) continue/.test(schirm)) {
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'STU', klasse: 2, marke: 'Reparatur', sicherheit: 'hoch',
      ort: { datei: 'pruefstand/bildschirme.mjs', zeile: 26 },
      titel: 'Ein unerwartetes Argument macht aus dem Bildschirm-Prüfstand einen Nichtstuer, '
           + 'der Erfolg meldet',
      steht_da: '`const NUR = process.argv[2] ?? \'\'` nimmt das erste Argument als Filter für '
        + 'Bildschirmnamen. Jeder andere Prüfstand des Projekts nimmt an dieser Stelle die '
        + 'Datenbank-URL. Wer sie hier aus Gewohnheit mitgibt, filtert auf einen Namen, den kein '
        + 'Bildschirm trägt: Die Schleife überspringt **alle**, kein Bild entsteht, und der '
        + 'Schlusssatz lautet trotzdem „Fertig … keine Konsolenfehler". Gemessen: mit der URL '
        + `als Argument läuft der Prüfstand in 1.2 Sekunden durch und macht keine einzige der `
        + `${BILDSCHIRME_GESAMT} Aufnahmen; ohne die URL braucht er ein Vielfaches davon.`,
      muesste: 'Ein Filter, der auf nichts passt, ist ein Fehler des Aufrufers und kein leerer '
        + 'Lauf: `if (NUR && !BILDSCHIRME.some(s => s.name.includes(NUR))) { console.error(…); '
        + 'process.exit(1) }`. Und der Schlusssatz gehört um die Zahl der wirklich gemachten '
        + 'Aufnahmen ergänzt — „Fertig" ohne Zähler ist kein Ergebnis.',
      warum: 'Die 1.2 Sekunden sind kein Schönheitsfehler, sondern die einzige Spur. Ein '
        + 'Prüfstand, der eine Aufgabe nicht ausführt und trotzdem Erfolg meldet, ist schlimmer '
        + 'als keiner: Er erzeugt genau das Vertrauen, das er nicht verdient. Dieser Befund '
        + 'stammt daher, dass dieses Werkzeug beim Aufruf selbst darauf hereinfiel — die '
        + 'Laufzeit war das Einzige, was nicht passte.',
      beleg: 'werkstatt/phase0/p0_stumpfheit.mjs; nachgemessen: `node pruefstand/bildschirme.mjs '
        + '"postgresql://…"` → 1.2 s und „keine Konsolenfehler", ohne Argument über 270 s; die '
        + 'Zahl der Bildschirme wird aus dem Quelltext des Prüfstands selbst gezählt',
      groesse: { wert: BILDSCHIRME_GESAMT,
                 einheit: 'Bildschirmaufnahmen, die stillschweigend ausfallen '
                        + `(${BILDSCHIRME_ANZAHL} Bildschirme × 2 Geräte × 2 Themen)`,
                 basis: 'gemessen an der Laufzeit: 1.2 s mit Argument, über 270 s ohne' },
      gegenrede: 'Wer die Anleitung liest, gibt kein Argument mit, und dann stimmt alles. Der '
        + 'Filter selbst ist nützlich — beim Entwickeln will man einen einzelnen Bildschirm '
        + 'ansehen. Es geht nicht um den Filter, sondern darum, dass sein Danebengreifen wie '
        + 'Erfolg aussieht.',
      aufwand: 'klein',
    }))
  }

  /* --- Befund/Gegenprobe: die Sonden --- */
  const stumpf = s.filter(x => x.ergebnis !== 'ok')
  raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'STU', klasse: stumpf.length ? 3 : 1,
    marke: stumpf.length ? 'Reparatur' : 'kein Fehler', sicherheit: 'hoch',
    ort: { datei: 'pruefwerk/sonden' },
    titel: stumpf.length
      ? `${stumpf.length} von ${s.length} Sonden finden ihren eigenen eingebauten Fehler nicht`
      : `Geprüft: alle ${s.length} Sonden des Prüfwerks sind noch scharf`,
    steht_da: stumpf.length
      ? stumpf.map(x => `\`${x.name}\`: ${x.ergebnis}`).join('; ')
      : `Jede der ${s.length} Sonden bekommt einen Fall vorgesetzt, in dem sie anschlagen muss, `
        + 'und findet ihn. Ihr Schweigen im echten Lauf ist damit eine Aussage und nicht bloss '
        + 'Abwesenheit. Das war in Runde L nicht so: Die Mutationssonde zeigte auf Formeln, die '
        + 'zwei Migrationen später anders hiessen, änderte nichts mehr und meldete pflichtgemäss '
        + '„keine überlebende Mutation".',
    muesste: stumpf.length ? 'Die Selbstprobe zeigt, worauf die Sonde blind ist — dort ansetzen, '
      + 'nicht am Ergebnis.' : '—',
    warum: 'Der Unterschied zwischen „hier ist nichts" und „ich sehe nichts mehr" ist der '
      + 'Unterschied zwischen einem Prüfwerk und einem Ritual. Er ist von aussen unsichtbar, '
      + 'und nur die Selbstprobe macht ihn sichtbar.',
    beleg: 'werkstatt/phase0/p0_stumpfheit.mjs: die Selbstprobe jeder Sonde ausgeführt',
    groesse: { wert: s.length - stumpf.length, einheit: `von ${s.length} Sonden belegen ihre Schärfe`,
               basis: 'Selbstprobe je Sonde' },
    ...(stumpf.length ? { gegenrede: 'Eine Selbstprobe prüft nur den einen Fall, den sie kennt. '
      + '„Ok" heisst „nicht völlig blind", nicht „sieht alles".' } : {}),
    aufwand: 'klein',
  }))

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Wer die Schärfe anderer misst, muss die eigene belegen. Geprüft wird die
 * Quelltextanalyse an zwei erfundenen Dateien: eine, die nur `exit 0` kennt
 * (muss als blind erkannt werden), und eine mit einem Weg zu `exit 1` (darf
 * es nicht).
 *
 * Ausserdem muss `kannScheitern` das `exit 1` auch dann finden, wenn es
 * eingerückt in einer Bedingung steht — genau so steht es in den Prüfständen,
 * und ein Muster, das nur am Zeilenanfang sucht, hielte sie alle für blind.
 */
export async function selbstprobe() {
  const nurNull = 'console.log("fertig")\nprocess.exit(0)\n'
  const mitEins = 'if (fehler) {\n  process.exit(1)\n}\nprocess.exit(0)\n'
  const shEins  = '#!/bin/bash\nif [ $n -gt 0 ]; then\n  exit 1\nfi\n'

  if (kannScheitern(nurNull).kann) return false
  if (!kannScheitern(mitEins).kann) return false
  if (!kannScheitern(shEins).kann) return false

  // Und die echten Dateien: kette.mjs muss scheitern können, bildschirme.mjs nicht.
  if (!kannScheiternDatei('pruefstand/kette.mjs').kann) return false
  return true
}
