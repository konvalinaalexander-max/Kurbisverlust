/**
 * Sonde 09 — Einheiten
 *
 * Die Beschriftungen auf dem Bildschirm prüft seit Runde I der Begriffs-
 * Prüfstand (`pruefstand/beschriftung.mjs`, Teil von `npm run pruefen`): Jede
 * Zahl mit Einheit muss eine Beschriftung haben, die im Begriffslexikon steht.
 * Das wird hier nicht wiederholt.
 *
 * Was dort nicht geprüft wird, ist die andere Hälfte: Hält der **Wert** in der
 * Datenbank, was sein **Name** verspricht? Eine Spalte `…_anteil`, in der 13.07
 * steht statt 0.1307, ist der klassische Fehler — die Beschriftung stimmt, die
 * Zahl ist um den Faktor hundert daneben, und weil sie durch eine
 * Prozentformatierung läuft, sieht man es erst, wenn 1307 % dasteht.
 *
 * Geprüft wird deshalb der Wertebereich gegen die Namensendung, über alle
 * Sichten hinweg:
 *
 *   …_anteil     zwischen 0 und 1
 *   …_kg         nicht negativ (ausser wo eine Differenz gemeint ist)
 *   …_tage       nicht negativ
 *   …_g          Gramm, nicht Kilogramm — ein Kürbis wiegt nicht 0.8 g
 *   n_…          ganzzahlig und nicht negativ
 *
 * Ausnahmen stehen unten mit Begründung. Eine Ausnahme ohne Begründung ist
 * eine Regel, die man aufgegeben hat.
 */
import { befund, frage } from '../umgebung.mjs'

export const lang = false

/**
 * Spalten, die ihrer Endung nach eine Regel brechen dürfen — jede mit dem
 * Grund. Wer eine hinzufügt, schreibt den Grund dazu.
 */
const AUSNAHMEN = {
  'd_m1_r': 'Ableitung — negativ von Natur aus',
  'd_f_eta': 'Ableitung',
  'u': 'zentrierter Logarithmus der Lagerdauer, negativ für junge Ware',
}

/**
 * Namen, bei denen das Vorzeichen die Aussage ist. Eine Abweichung, eine
 * Differenz, ein Rest und ein Fehler dürfen negativ sein — das ist keine
 * Ausnahme von der Regel, sondern eine eigene Wortgruppe. Ihre Werte werden
 * deshalb nicht auf „nicht negativ" geprüft; alles andere (etwa dass ein
 * Anteil nicht über 1 geht) gilt weiter.
 */
const MIT_VORZEICHEN = /abweichung|differenz|_rest_|^rest_|fehler|korrektur|versatz|ueberfuellung/

const REGELN = [
  { endung: /_anteil$/, name: 'Anteil', pruefung: (s) => `${s} < -0.0001 or ${s} > 1.0001`,
    erwartet: 'zwischen 0 und 1',
    // Eine Abweichung darf negativ sein, aber ein Anteil bleibt ein Anteil:
    // der Betrag gehört unter 1. Genau das fängt den Faktor hundert.
    mitVorzeichen: { pruefung: (s) => `abs(${s}) > 1.0001`, erwartet: 'im Betrag höchstens 1' } },
  { endung: /_kg$/, name: 'Masse', pruefung: (s) => `${s} < -0.01`, erwartet: 'nicht negativ' },
  { endung: /_tage$|^alter_|_lagertage$/, name: 'Dauer', pruefung: (s) => `${s} < 0`, erwartet: 'nicht negativ' },
  { endung: /^n_|^anzahl/, name: 'Anzahl', pruefung: (s) => `${s} < 0`, erwartet: 'nicht negativ' },
  { endung: /_g$/, name: 'Gramm', pruefung: (s) => `${s} > 0 and ${s} < 20`,
    erwartet: 'in Gramm — ein Wert unter 20 deutet auf Kilogramm hin' },
]

export async function laufen({ db }) {
  const raus = []
  const B = (o) => raus.push(befund({ sonde: '09_einheiten', kuerzel: 'EIN', ...o }))

  const spalten = frage(db, `
    select c.relname as objekt, a.attname as spalte, format_type(a.atttypid, a.atttypmod) as art
      from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and a.attnum > 0 and not a.attisdropped
       and c.relkind in ('r','v','m')
       and format_type(a.atttypid, a.atttypmod) ~ '^(numeric|double|integer|bigint|real|smallint)'
     order by 1, 2`)

  const verletzt = []
  let geprueft = 0
  for (const s of spalten) {
    let regel = REGELN.find(r => r.endung.test(s.spalte))
    if (!regel || AUSNAHMEN[s.spalte]) continue
    if (MIT_VORZEICHEN.test(s.spalte)) {
      if (!regel.mitVorzeichen) continue          // „nicht negativ" gilt für Differenzen nicht
      regel = { ...regel, ...regel.mitVorzeichen }
    }
    geprueft++
    let n
    try {
      n = frage(db, `select count(*) as n, min("${s.spalte}")::numeric as kleinste,
                            max("${s.spalte}")::numeric as groesste
                       from "${s.objekt}" where ${regel.pruefung(`"${s.spalte}"`)}`)[0]
    } catch { continue }              // ungefüllte Sicht o. Ä. — Sonde 01 meldet das
    if (Number(n.n) > 0) verletzt.push({ ...s, regel: regel.name, erwartet: regel.erwartet, ...n })
  }

  for (const v of verletzt) {
    B({ klasse: v.regel === 'Anteil' || v.regel === 'Gramm' ? 3 : 2,
        ort: { sicht: v.objekt, spalte: v.spalte },
        titel: `\`${v.objekt}.${v.spalte}\` heisst nach ${v.regel}, hält aber Werte, die keine sind`,
        steht_da: `${v.n} Zeilen ausserhalb; kleinster Wert ${v.kleinste}, grösster ${v.groesste}.`,
        muesste: `${v.erwartet} — oder die Spalte heisst anders, oder sie steht mit Begründung in der `
               + 'Ausnahmeliste von pruefwerk/sonden/09_einheiten.mjs.',
        warum: 'Der Name einer Spalte ist das, wonach die Oberfläche sie formatiert. Ein Anteil wird '
             + 'mit hundert multipliziert, eine Masse in Tonnen umgerechnet, Gramm bleiben Gramm. '
             + 'Passt der Wert nicht zum Namen, ist die Anzeige um einen Faktor daneben — und zwar '
             + 'gleichmässig, sodass sie plausibel aussieht.',
        beleg: 'pruefwerk/sonden/09_einheiten.mjs',
        groesse: { wert: Number(v.n), einheit: 'Zeilen ausserhalb des Wertebereichs', basis: `${v.objekt}.${v.spalte}` },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  if (!verletzt.length) {
    B({ klasse: 1, ort: { sicht: 'alle Sichten' },
        titel: 'Geprüft und in Ordnung: jede Spalte hält, was ihr Name verspricht',
        steht_da: `${geprueft} Spalten mit einer Endung, die eine Einheit nennt (…_anteil, …_kg, `
                + `…_tage, …_g, n_…), über ${new Set(spalten.map(s => s.objekt)).size} Tabellen und `
                + `Sichten. Keine hält einen Wert ausserhalb ihres Bereichs. `
                + `${Object.keys(AUSNAHMEN).length} Spalten sind einzeln begründet ausgenommen, `
                + 'dazu die Wortgruppe der Differenzen (Abweichung, Rest, Fehler, Versatz), bei der '
                + 'das Vorzeichen die Aussage ist.',
        muesste: 'Nichts.',
        warum: 'Der häufigste stille Fehler in einer Auswertung ist ein Faktor hundert. Dass er hier '
             + 'nirgends steckt, ist kein Zufall, sondern das Ergebnis der Namensregeln aus Runde I — '
             + 'und diese Sonde hält sie künftig fest.',
        beleg: 'pruefwerk/sonden/09_einheiten.mjs',
        groesse: { wert: geprueft, einheit: 'geprüfte Spalten', basis: 'alle Tabellen und Sichten' },
        sicherheit: 'hoch', marke: 'kein Fehler' })
  }

  return raus
}

/**
 * Selbstprobe: Eine Sicht mit einem Anteil in Prozent statt als Anteil muss
 * auffallen. Ohne diesen Nachweis sagt „nichts gefunden" nichts.
 */
export async function selbstprobe({ db = 'demo' } = {}) {
  const { kopie, tue } = await import('../umgebung.mjs')
  const k = kopie(db, 'pw_einheiten_probe')
  tue(k, `create view v_pw_probe as
            select 13.07::numeric as verlust_anteil, -5::numeric as schimmel_kg;`)
  const r = await laufen({ db: k })
  return r.some(b => b.ort?.spalte === 'verlust_anteil')
      && r.some(b => b.ort?.spalte === 'schimmel_kg')
}
