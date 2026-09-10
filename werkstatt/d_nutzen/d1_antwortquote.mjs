/**
 * D1 — Antwortquote: wie oft sagt das Programm „weiss ich nicht"?
 *
 * WARUM ES DIESES WERKZEUG GIBT
 *
 * `docs/UI-KONZEPT.md` schreibt für jeden Reiter des Betriebsleiters in eine
 * Spalte „Beantwortet", welche Frage er beantwortet. Das ist ein Versprechen,
 * und es ist bisher nirgends nachgemessen.
 *
 * Das Programm hält seit Runde L eine harte Regel: **Leer ist nicht null.**
 * Was nicht gemessen ist, steht als „—", nie als 0,00 kg. Die Regel ist
 * richtig, und sie hat eine Kehrseite, die niemand beziffert hat: Je
 * strenger sie durchgesetzt wird, desto öfter steht auf dem Bildschirm ein
 * Strich statt einer Zahl. Ein Bildschirm voller Striche ist ehrlich und
 * nutzlos.
 *
 * WAS ES MISST
 *
 * Für jede gespeicherte Ansicht, aus der die Oberfläche liest, und für jede
 * Spalte darin: den Anteil der Zeilen, in denen ein Wert steht. Nicht
 * geschätzt — gezählt, mit `count(spalte)` gegen `count(*)`.
 *
 * Daraus zwei Zahlen je Bildschirm: wie viele **Zahlen** er heute zeigen
 * kann, und wie viele davon Striche sind.
 *
 * WAS ES NICHT MISST
 *
 * Ob ein Strich richtig ist. Ein „—" beim verkaufsfähigen Anteil einer Charge
 * ohne einzige Wägung ist genau das, was dastehen soll — die Alternative wäre
 * eine erfundene Zahl. Dieses Werkzeug sagt nur, **wie oft** es vorkommt und
 * **wo**; ob es zu oft ist, ist eine Frage an den Betrieb.
 *
 * Und es misst nicht die Oberfläche selbst. Ob eine Spalte, die zu 100 %
 * gefüllt ist, auch wirklich auf einem Bildschirm steht, sagt der
 * Beschriftungs-Prüfstand (`pruefstand/beschriftung`), nicht dieses Werkzeug.
 */
import { frage, lies, befund, messung } from '../umgebung.mjs'

export const lang = false

const WERKSTATT = 'D — Nutzen'

/**
 * Welche gespeicherte Ansicht gehört zu welchem Reiter?
 *
 * Von Hand zugeordnet — die Oberfläche lädt alles in einem Rutsch
 * (`src/auswertung/daten.ts`) und sagt nicht selbst, welcher Reiter welche
 * Zahl zeigt. Die Zuordnung folgt der Tabelle in `docs/UI-KONZEPT.md`; wo
 * eine Ansicht auf zwei Reitern erscheint, steht sie beim vorderen.
 */
const REITER = [
  { name: 'Überblick', frage: 'Was kam herein, was ging hinaus, was ist bis heute verloren — und woran?',
    sichten: ['erg_bilanz', 'erg_verlust', 'erg_verlauf', 'erg_kaliber'] },
  { name: 'Ursachen', frage: 'Echter Verlust und kein echter Verlust, jede Ursache in der Tiefe',
    sichten: ['erg_punkte', 'erg_kurve', 'erg_modell', 'erg_ausschuss', 'erg_fax',
              'erg_ueberfuellung', 'erg_selektion'] },
  { name: 'Chargen', frage: 'Wo steht welche Charge?',
    sichten: ['erg_charge', 'erg_kohorte', 'erg_lieferung'] },
  { name: 'Messungen', frage: 'Was weiss die Auswertung — und was nicht?',
    sichten: ['erg_plausibilitaet', 'erg_datenqualitaet', 'erg_datenlage', 'erg_massenbilanz',
              'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
              'erg_koeff_ueberfuellung', 'erg_wiegung', 'erg_gewichte', 'erg_gebinde'] },
  { name: 'Betrieb', frage: 'Was ist heute los, und wie pflege ich die Grundlagen?',
    sichten: ['erg_durchsatz', 'erg_verarbeitung_alter', 'erg_ausgang', 'erg_marge',
              'erg_naechste_charge'] },
]

/** Spalten, die keine Antwort sind, sondern die Frage: Schlüssel und Beschriftungen. */
const KEINE_ANTWORT = /^(id|charge_nr|sorte|schlag|gruppe|schluessel|strom|art|basis|name|titel|kohorte|eingangsdatum|datum|woche|tag|ts|start_ts|wiege_ts|portion|station|quelle|einheit|kistensystem|kaliber_idx|von|bis)$/

/**
 * Für jede Spalte: wie viele Zeilen haben dort einen Wert?
 *
 * Eine Abfrage je Ansicht, nicht je Spalte — sonst sind es dreihundert
 * Abfragen und der Lauf dauert länger als alles andere in dieser Werkstatt
 * zusammen.
 */
export function fuellung(db, sicht) {
  const spalten = frage(db, `
    select a.attname as name, format_type(a.atttypid, a.atttypmod) as typ
      from pg_attribute a
     where a.attrelid = '${sicht}'::regclass and a.attnum > 0 and not a.attisdropped
     order by a.attnum`)
  if (!spalten.length) return null
  const zaehler = spalten.map(s => `count("${s.name}") as "${s.name}"`).join(', ')
  const z = frage(db, `select count(*) as pw_zeilen, ${zaehler} from ${sicht}`)[0]
  const zeilen = Number(z.pw_zeilen)
  return {
    sicht, zeilen,
    spalten: spalten.map(s => ({
      name: s.name, typ: s.typ,
      gefuellt: Number(z[s.name]),
      // Zeitpunkte sind Ereignisse, keine Antworten: `abgebrochen_ts` ohne
      // Wert heisst „nicht abgebrochen" — das ist eine Auskunft, kein Strich.
      antwort: !KEINE_ANTWORT.test(s.name)
            && !/_bekannt$|_basis$|^n_|_n$|_ts$/.test(s.name),
    })),
  }
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const raus = []
  const vorhanden = new Set(frage(db, `
    select c.relname as name from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'm'`).map(z => z.name))

  // Die Zuordnung darf nicht schweigend veralten: Eine Ansicht, die es nicht
  // mehr gibt, ist ein Fehler in diesem Werkzeug, kein Befund über das Programm.
  const fehlend = REITER.flatMap(r => r.sichten).filter(s => !vorhanden.has(s))
  if (fehlend.length) throw new Error(
    `Diese gespeicherten Ansichten stehen in der Zuordnung dieses Werkzeugs, aber nicht mehr in `
    + `der Datenbank: ${fehlend.join(', ')}. Die Zuordnung muss nachgezogen werden — sonst misst `
    + 'das Werkzeug einen Bildschirm, der anders aussieht, als es glaubt.')

  const daten = new Map()
  for (const r of REITER) for (const s of r.sichten)
    if (!daten.has(s)) daten.set(s, fuellung(db, s))

  const jeReiter = REITER.map(r => {
    const spalten = r.sichten.flatMap(s => (daten.get(s)?.spalten ?? [])
      .filter(c => c.antwort)
      .map(c => ({ ...c, sicht: s, zeilen: daten.get(s).zeilen })))
    const felder = spalten.reduce((a, c) => a + c.zeilen, 0)
    const gefuellt = spalten.reduce((a, c) => a + c.gefuellt, 0)
    const leereSpalten = spalten.filter(c => c.zeilen > 0 && c.gefuellt === 0)
    const halbe = spalten.filter(c => c.zeilen > 0 && c.gefuellt > 0 && c.gefuellt < c.zeilen)
    return { ...r, spalten, felder, gefuellt, leereSpalten, halbe }
  })

  raus.push(messung({
    werkstatt: WERKSTATT, titel: 'Antwortquote je Reiter des Betriebsleiters', einheit: 'Felder',
    spalten: ['Reiter', 'Was er beantwortet', 'Zahlenfelder', 'davon mit Wert', 'Quote',
              'Spalten ganz ohne Wert', 'Spalten teils ohne Wert'],
    erklaerung: 'Ein „Zahlenfeld" ist eine Zeile mal eine Antwortspalte. Antwortspalten sind '
      + 'alle ausser Schlüsseln und Beschriftungen (`charge_nr`, `sorte`, `basis`, `n_…`); die '
      + 'zählen nicht, weil sie die Frage sind und nicht die Antwort. Gezählt mit `count(spalte)` '
      + 'gegen `count(*)` — nicht geschätzt. Die Zuordnung Ansicht → Reiter folgt der Tabelle in '
      + '`docs/UI-KONZEPT.md`.',
    zeilen: jeReiter.map(r => ({
      'Reiter': `**${r.name}**`,
      'Was er beantwortet': r.frage,
      'Zahlenfelder': r.felder,
      'davon mit Wert': r.gefuellt,
      'Quote': r.felder ? `${(r.gefuellt / r.felder * 100).toFixed(1)} %` : '—',
      'Spalten ganz ohne Wert': r.leereSpalten.length,
      'Spalten teils ohne Wert': r.halbe.length,
    })),
  }))

  const alleLeer = jeReiter.flatMap(r => r.leereSpalten.map(c => ({ ...c, reiter: r.name })))
  raus.push(messung({
    werkstatt: WERKSTATT, titel: 'Spalten, in denen heute in keiner Zeile ein Wert steht',
    einheit: 'Spalten',
    spalten: ['Reiter', 'Ansicht', 'Spalte', 'Typ', 'Zeilen'],
    erklaerung: alleLeer.length
      ? 'Diese Spalten sind auf der Demosaison durchgehend leer. Das ist nicht automatisch ein '
        + 'Mangel — eine Spalte für eine Messung, die dieser Betrieb noch nicht macht, gehört '
        + 'leer zu sein. Es ist aber die Liste, die man durchgehen muss, um zu wissen, welche '
        + 'Hälfte des Bildschirms heute aus Strichen besteht.'
      : 'Keine. In jeder Antwortspalte der fünf Reiter steht mindestens eine Zeile mit einem Wert.',
    zeilen: alleLeer.length ? alleLeer.slice(0, 20).map(c => ({
      'Reiter': c.reiter, 'Ansicht': `\`${c.sicht}\``, 'Spalte': `\`${c.name}\``,
      'Typ': c.typ, 'Zeilen': c.zeilen,
    })) : [{ 'Reiter': '—', 'Ansicht': '—', 'Spalte': 'keine durchgehend leere Antwortspalte',
             'Typ': '—', 'Zeilen': '—' }],
  }))

  /* --- Befund --- */
  const gesamtFelder = jeReiter.reduce((a, r) => a + r.felder, 0)
  const gesamtGefuellt = jeReiter.reduce((a, r) => a + r.gefuellt, 0)
  const quote = gesamtFelder ? gesamtGefuellt / gesamtFelder : 0
  const schwaechster = [...jeReiter].filter(r => r.felder)
    .sort((a, b) => a.gefuellt / a.felder - b.gefuellt / b.felder)[0]

  const beste = [...jeReiter].filter(r => r.felder)
    .sort((a, b) => b.gefuellt / b.felder - a.gefuellt / a.felder)[0]
  const abstand = (beste.gefuellt / beste.felder - schwaechster.gefuellt / schwaechster.felder) * 100

  if (abstand >= 10 || alleLeer.length) {
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'ANTW', klasse: 2, marke: 'Frage an den Betrieb',
      sicherheit: 'hoch',
      ort: { sicht: schwaechster.sichten.join(', ') },
      titel: `Der Reiter **${schwaechster.name}** antwortet auf `
           + `${(schwaechster.gefuellt / schwaechster.felder * 100).toFixed(1)} % seiner Felder, `
           + `die übrigen auf ${(beste.gefuellt / beste.felder * 100).toFixed(1)} % bis `
           + `${(jeReiter.filter(r => r !== beste && r !== schwaechster)
                 .reduce((m, r) => Math.min(m, r.gefuellt / r.felder), 1) * 100).toFixed(1)} %`,
      steht_da: `Über alle fünf Reiter stehen ${gesamtFelder.toLocaleString('de-CH')} Zahlenfelder; `
        + `in ${gesamtGefuellt.toLocaleString('de-CH')} davon steht ein Wert, das sind `
        + `${(quote * 100).toFixed(1)} %. Sie verteilen sich sehr ungleich: `
        + jeReiter.map(r => `${r.name} ${(r.gefuellt / r.felder * 100).toFixed(1)} %`).join(', ')
        + `. Auf **${schwaechster.name}** haben ${schwaechster.halbe.length} Spalten in einem Teil `
        + `der Zeilen keinen Wert und ${schwaechster.leereSpalten.length} in keiner einzigen`
        + (alleLeer.length
            ? ` (${alleLeer.map(c => `\`${c.sicht}.${c.name}\``).join(', ')})` : '')
        + '.',
      muesste: 'Das ist keine Reparatur am Code. Je Spalte gibt es drei mögliche Antworten, und '
        + '„lassen wie es ist" ist keine davon: Entweder fehlt eine Messung, die der Betrieb '
        + 'machen könnte — dann gehört sie in `docs/FRAGEN.md`. Oder sie ist für diesen Betrieb '
        + 'nicht vorgesehen — dann gehört die Spalte weg, samt der Stelle, die sie anzeigt. Oder '
        + 'sie füllt sich erst im Lauf der Saison — dann gehört ein Satz daneben, der das sagt.',
      warum: 'Ein Strich ist die richtige Anzeige für Unbekanntes, und er ist teuer: Der '
        + 'Betriebsleiter sieht ihn und weiss nicht, ob die Messung fehlt, ob sie noch kommt oder '
        + 'ob die Spalte für seinen Betrieb nie etwas zeigen wird. Beim dritten Strich hört er '
        + 'auf, dort hinzuschauen — und übersieht den vierten, hinter dem etwas steckt. '
        + `Ausgerechnet **${schwaechster.name}** ist der Reiter, auf dem der Betriebsleiter `
        + 'nachsieht, wenn er wissen will, woran die Ware fehlt.',
      beleg: 'werkstatt/d_nutzen/d1_antwortquote.mjs: `count(spalte)` gegen `count(*)` über alle '
        + `${daten.size} gespeicherten Ansichten der fünf Reiter`,
      groesse: { wert: (schwaechster.gefuellt / schwaechster.felder * 100).toFixed(1),
                 einheit: `% Antwortquote auf ${schwaechster.name}, gegen `
                        + `${(quote * 100).toFixed(1)} % über alle fünf Reiter `
                        + `(${gesamtFelder.toLocaleString('de-CH')} Felder)`,
                 basis: 'Demosaison' },
      gegenrede: 'Drei Einwände. **Erstens** ist die Demosaison nicht der Betrieb: Sie ist gebaut, '
        + 'um die Rechenwege zu zeigen, nicht um jede Messung einmal vorzuführen. **Zweitens** ist '
        + 'ein niedriger Wert nicht automatisch schlecht — der Reiter Ursachen zeigt je Sorte und '
        + 'je Charge, und eine Sorte ohne eigene Wägung *soll* dort einen Strich haben statt einer '
        + 'geliehenen Zahl ohne Kennzeichnung. **Drittens** wiegt dieses Werkzeug jedes Feld '
        + 'gleich: Eine selten gelesene Diagnosespalte des Modells zählt so viel wie die '
        + 'Verlustzahl selbst. Die Quote ist deshalb ein Wegweiser zum Durchsehen, keine Note.',
      aufwand: 'mittel',
    }))
  } else {
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'ANTW', klasse: 1, marke: 'kein Fehler', sicherheit: 'hoch',
      ort: { sicht: 'erg_*' },
      titel: `Geprüft und in Ordnung: in jeder Antwortspalte der fünf Reiter steht mindestens `
           + 'eine Zeile mit einem Wert',
      steht_da: `${gesamtFelder.toLocaleString('de-CH')} Zahlenfelder über fünf Reiter, `
        + `${(quote * 100).toFixed(1)} % davon gefüllt, keine Spalte durchgehend leer.`,
      muesste: '—',
      warum: 'Eine Spalte, die nie etwas zeigt, kostet den Leser dieselbe Aufmerksamkeit wie eine, '
        + 'die etwas zeigt.',
      beleg: 'werkstatt/d_nutzen/d1_antwortquote.mjs',
      groesse: { wert: (quote * 100).toFixed(1), einheit: '% Antwortquote über alle fünf Reiter',
                 basis: 'Demosaison' },
      aufwand: 'klein',
    }))
  }

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Die Zählung muss eine leere Spalte finden **und** eine volle in Ruhe lassen.
 * Geprüft wird an einer erfundenen Ansicht in der laufenden Datenbank — eine
 * Zählung, die an einem Nachbau geprüft wird, prüft den Nachbau.
 */
export async function selbstprobe({ db }) {
  const { kopie, tue, wegwerfen } = await import('../umgebung.mjs')
  const probe = kopie(db, 'wk_d1_probe')
  try {
    tue(probe, `create materialized view wk_d1_sicht as
                select g as charge_nr, g as voll, null::numeric as leer,
                       case when g > 2 then g end as halb
                  from generate_series(1, 4) g`)
    const f = fuellung(probe, 'wk_d1_sicht')
    if (!f || f.zeilen !== 4) return false
    const s = Object.fromEntries(f.spalten.map(c => [c.name, c]))
    if (s.voll.gefuellt !== 4 || s.leer.gefuellt !== 0 || s.halb.gefuellt !== 2) return false
    // charge_nr ist ein Schlüssel und darf nicht als Antwort zählen.
    if (s.charge_nr.antwort !== false) return false
    if (s.voll.antwort !== true) return false
    return true
  } catch {
    return false
  } finally {
    wegwerfen(probe)
  }
}
