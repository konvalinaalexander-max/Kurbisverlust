/**
 * A4 — Fehlerfortpflanzung: wie unsicher sagt das Programm, dass es sei?
 *
 * DIE FRAGE
 *
 * Jede Verlustzahl trägt ein Band. Das Band entsteht so:
 *
 *     Streuung = sqrt( var_verdunstung + var_ausschuss + var_modell )
 *     Band     = Wert ± t(df) · Streuung
 *
 * Der erste Teil ist sauber gebaut: eine Delta-Methode mit Ableitungen nach
 * jedem Koeffizienten, beim Schimmelmodell sogar mit der Kovarianz zwischen
 * Achsenabschnitt und Steigung. Das ist mehr Sorgfalt, als man erwartet.
 *
 * Der zweite Teil hat ein Loch, und es ist ein grosses:
 *
 *     df = LEAST(df_verdunstung, df_ausschuss, df_modell)
 *
 * Die Freiheitsgrade werden als **Minimum** genommen. Das heisst: Der am
 * schlechtesten belegte Bestandteil bestimmt die Breite des Bands — auch wenn
 * er zur Varianz fast nichts beiträgt.
 *
 * WARUM DAS TEUER IST
 *
 * `t(1) = 12.706`, `t(30) = 1.960`. Zwischen einem Freiheitsgrad und dreissig
 * liegt Faktor **6.5** in der Bandbreite. Und df = 1 kommt leicht zustande:
 * Eine einzige Sorte mit einer einzigen eigenen Wägung genügt, denn über die
 * Sorten wird ebenfalls das Minimum genommen.
 *
 * Ein Band, das sechsmal zu weit ist, ist kein harmloser Sicherheitszuschlag.
 * Es sagt dem Betrieb, er wisse nichts, wo er etwas weiss — und
 * Zurückhaltung, die nicht begründet ist, kostet Entscheidungen.
 *
 * WIE ES RICHTIG GEHT
 *
 * Für eine Summe von Varianzen mit verschiedenen Freiheitsgraden gibt es seit
 * 1946 die Näherung von Satterthwaite:
 *
 *                  ( Σ vᵢ )²
 *     df_eff  =  ─────────────
 *                 Σ ( vᵢ² / dfᵢ )
 *
 * Sie gewichtet jeden Freiheitsgrad mit dem **Quadrat seines Varianzanteils**.
 * Trägt der schlecht belegte Bestandteil wenig bei, zieht er das Ergebnis
 * kaum herunter — genau das, was das Minimum nicht kann. Trägt er alles bei,
 * ergibt Satterthwaite von selbst wieder df = 1: Die Näherung ist nicht
 * grosszügiger, sie ist genauer.
 *
 * WAS DIESES WERKZEUG TUT
 *
 * Es holt die drei Varianzbestandteile **aus der Sicht selbst** — nicht aus
 * einer Nachbildung, die auseinanderlaufen könnte —, rechnet Satterthwaite
 * daneben und beziffert den Unterschied in Kilogramm. Und es prüft vorher, ob
 * es die richtigen Bestandteile erwischt hat: Ihre Summe muss die
 * veröffentlichte Streuung ergeben.
 */
import { frage, wert, befund, messung } from '../umgebung.mjs'

const WERKSTATT = 'A — Rechenwerk'

/** Dieselbe Tabelle, die `t_quantil_95()` in der Datenbank führt. */
const T95 = [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306,
             2.262, 2.228, 2.201, 2.179, 2.160, 2.145, 2.131, 2.120,
             2.110, 2.101, 2.093, 2.086, 2.080, 2.074, 2.069, 2.064,
             2.060, 2.056, 2.052, 2.048, 2.045]
export const t95 = (df) => !df || df < 1 ? 12.706 : df >= 30 ? 1.960 : T95[Math.floor(df) - 1]

/**
 * Satterthwaites effektive Freiheitsgrade.
 *
 * Bestandteile ohne Varianz fallen heraus — sie tragen weder zur Summe noch
 * zum Nenner bei, und ihr Freiheitsgrad hat kein Gewicht. Genau das ist der
 * Unterschied zum Minimum, das auch einen Bestandteil mit Varianz null noch
 * mitzählt.
 */
export function satterthwaite(teile) {
  const gueltig = teile.filter(t => Number.isFinite(t.varianz) && t.varianz > 0
                                 && Number.isFinite(t.df) && t.df >= 1)
  if (!gueltig.length) return null
  const summe = gueltig.reduce((a, t) => a + t.varianz, 0)
  const nenner = gueltig.reduce((a, t) => a + (t.varianz ** 2) / t.df, 0)
  return nenner > 0 ? (summe ** 2) / nenner : null
}

/**
 * Die drei Varianzbestandteile aus `v_verlust_je_gruppe`.
 *
 * Statt sie nachzubauen — was beim nächsten Umbau der Sicht stillschweigend
 * falsch würde — wird der Quelltext der Sicht genommen, hinter der letzten
 * der drei Varianz-Teilabfragen abgeschnitten und ein eigenes `select`
 * angehängt. Das Werkzeug liest damit immer die Fassung, die wirklich läuft.
 */
function bestandteile(db) {
  const text = wert(db, `select pg_get_viewdef('v_verlust_je_gruppe'::regclass, true)`)
  const marke = '), summe AS'
  const schnitt = text.indexOf(marke)
  if (schnitt < 0 || !text.includes('varianz_f AS'))
    throw new Error('Der Aufbau von v_verlust_je_gruppe hat sich geändert — dieses Werkzeug '
      + 'findet die Varianz-Teilabfragen nicht mehr und darf deshalb nichts behaupten.')

  return frage(db, text.slice(0, schnitt + 1) + `
    select coalesce(r.gruppe, a.gruppe, f.gruppe)          as gruppe,
           coalesce(r.schluessel, a.schluessel, f.schluessel) as schluessel,
           coalesce(r.strom, a.strom, f.strom)             as strom,
           r.varianz::float8 as v_verdunstung, r.df as df_verdunstung,
           a.varianz::float8 as v_ausschuss,   a.df as df_ausschuss,
           f.varianz::float8 as v_modell,      f.df as df_modell
      from varianz_r r
      full join varianz_a a
        on a.gruppe = r.gruppe and a.schluessel = r.schluessel and a.strom = r.strom
      full join varianz_f f
        on f.gruppe = coalesce(r.gruppe, a.gruppe)
       and f.schluessel = coalesce(r.schluessel, a.schluessel)
       and f.strom = coalesce(r.strom, a.strom)`)
}

const teileVon = (z) => [
  { name: 'Verdunstung', varianz: z.v_verdunstung, df: z.df_verdunstung },
  { name: 'Ausschuss/Fax/Nebenkanal', varianz: z.v_ausschuss, df: z.df_ausschuss },
  { name: 'Schimmelmodell', varianz: z.v_modell, df: z.df_modell },
].filter(t => t.varianz !== null && t.varianz !== undefined)

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const roh = bestandteile(db)
  const raus = []

  /* --- Gegenprobe: haben wir die richtigen Bestandteile? --- */
  const veroeffentlicht = frage(db, `
    select gruppe, schluessel, strom, streuung_kg::float8 as streuung, df, kg::float8 as kg,
           kg_unten::float8 as unten, kg_oben::float8 as oben
      from v_verlust_je_gruppe where streuung_kg is not null`)
  const schluessel = (z) => `${z.gruppe}|${z.schluessel}|${z.strom}`
  const nachSchluessel = new Map(roh.map(z => [schluessel(z), z]))

  let schlimmste = 0
  for (const v of veroeffentlicht) {
    const b = nachSchluessel.get(schluessel(v))
    if (!b) continue
    const nachgerechnet = Math.sqrt(teileVon(b).reduce((a, t) => a + (t.varianz ?? 0), 0))
    schlimmste = Math.max(schlimmste, Math.abs(nachgerechnet - v.streuung))
  }
  if (schlimmste > 0.02)
    throw new Error(`Die aus der Sicht geholten Varianzbestandteile ergeben nicht die `
      + `veröffentlichte Streuung (grösste Abweichung ${schlimmste.toFixed(4)} kg). Das Werkzeug `
      + `hat die falschen Teilabfragen erwischt und darf nichts behaupten.`)

  /* --- Der Vergleich --- */
  const zeilen = veroeffentlicht.map(v => {
    const b = nachSchluessel.get(schluessel(v))
    if (!b) return null
    const teile = teileVon(b).filter(t => Number.isFinite(t.varianz))
    const dfEff = satterthwaite(teile)
    if (dfEff === null) return null
    const tJetzt = t95(v.df), tRichtig = t95(Math.round(dfEff))
    return { ...v, teile, df_min: v.df, df_eff: dfEff,
             halb_jetzt: tJetzt * v.streuung, halb_richtig: tRichtig * v.streuung,
             kg_zu_weit: (tJetzt - tRichtig) * v.streuung,
             faktor: tRichtig > 0 ? tJetzt / tRichtig : 1 }
  }).filter(Boolean)

  const gesamt = zeilen.filter(z => z.gruppe === 'gesamt' && z.kg > 0)
    .sort((a, b) => b.kg_zu_weit - a.kg_zu_weit)
  const betroffen = zeilen.filter(z => z.faktor > 1.2)

  raus.push(messung({
    werkstatt: WERKSTATT,
    titel: 'Freiheitsgrade der Verlustbänder: Minimum gegen Satterthwaite',
    einheit: 'kg',
    spalten: ['Verlustursache', 'Wert (kg)', 'Streuung (kg)', 'df heute (Minimum)',
              'df nach Satterthwaite', 't heute', 't richtig', 'Band heute (± kg)',
              'Band richtig (± kg)'],
    erklaerung: 'Die Zeilen sind die sechs Ströme der Gesamtsaison. „df heute" ist das Minimum '
      + 'der Freiheitsgrade der drei Varianzbestandteile, so wie `v_verlust_je_gruppe` es bildet; '
      + '„df nach Satterthwaite" gewichtet jeden Freiheitsgrad mit dem Quadrat seines '
      + 'Varianzanteils. Wo beide gleich sind, ist das heutige Band richtig — dann trägt der '
      + 'schlecht belegte Bestandteil tatsächlich fast die ganze Varianz. Die Varianzen selbst '
      + 'sind aus der laufenden Sicht geholt, nicht nachgebaut, und ihre Summe wurde gegen die '
      + 'veröffentlichte Streuung geprüft.',
    zeilen: gesamt.map(z => ({
      'Verlustursache': z.strom, 'Wert (kg)': z.kg.toFixed(0),
      'Streuung (kg)': z.streuung.toFixed(1),
      'df heute (Minimum)': z.df_min,
      'df nach Satterthwaite': z.df_eff.toFixed(1),
      't heute': t95(z.df_min).toFixed(3), 't richtig': t95(Math.round(z.df_eff)).toFixed(3),
      'Band heute (± kg)': z.halb_jetzt.toFixed(0),
      'Band richtig (± kg)': z.halb_richtig.toFixed(0),
    })),
  }))

  const schlimm = gesamt.filter(z => z.faktor > 1.2)
  if (schlimm.length) {
    const groesster = schlimm[0]
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'FPF', klasse: 3, marke: 'Reparatur', sicherheit: 'hoch',
      ort: { sicht: 'v_verlust_je_gruppe' },
      titel: 'Die Unsicherheitsbänder sind zu weit, weil der schlechteste Bestandteil sie allein bestimmt',
      steht_da: 'Die Freiheitsgrade eines Bands entstehen als `LEAST(df_verdunstung, '
        + 'df_ausschuss, df_modell)`, und innerhalb jedes Bestandteils noch einmal als '
        + '`min(df)` über die Sorten. Ein einziger schwach belegter Bestandteil zieht damit das '
        + `ganze Band auf. Beim grössten Verluststrom (\`${groesster.strom}\`, `
        + `${groesster.kg.toFixed(0)} kg) steht heute df = ${groesster.df_min}, also `
        + `t = ${t95(groesster.df_min).toFixed(3)} — obwohl `
        + `${(100 * Math.max(...groesster.teile.map(t => t.varianz)) / groesster.teile.reduce((a, t) => a + (t.varianz ?? 0), 0)).toFixed(0)} % `
        + `der Varianz aus einem Bestandteil mit df = `
        + `${groesster.teile.reduce((a, t) => (t.varianz ?? 0) > (a.varianz ?? 0) ? t : a).df} `
        + `kommen. Das Band ist dadurch ±${groesster.halb_jetzt.toFixed(0)} kg statt `
        + `±${groesster.halb_richtig.toFixed(0)} kg breit.`,
      muesste: 'Die Freiheitsgrade einer Varianzsumme sind nicht das Minimum, sondern Satterthwaites '
        + 'Näherung: `df_eff = (Σvᵢ)² / Σ(vᵢ²/dfᵢ)`. Sie ist eine Zeile SQL, braucht nichts, was '
        + 'nicht schon dasteht, und ist nicht grosszügiger — wo der schwache Bestandteil die '
        + 'Varianz wirklich trägt, ergibt sie von selbst wieder df = 1. Dieselbe Korrektur gehört '
        + 'in die `min(df)` über die Sorten innerhalb jedes Bestandteils.',
      warum: 'Ein zu weites Band ist keine gute Vorsicht. Es beantwortet die Frage „darf ich '
        + 'diesen Unterschied glauben?" mit Nein, wo die Antwort Ja wäre. Der Betrieb hat für '
        + 'diese Zahlen Arbeiterzeit bezahlt; ein Band, das ihren Wert um den Faktor '
        + `${groesster.faktor.toFixed(1)} kleinredet, macht einen Teil dieser Arbeit wertlos.`,
      beleg: 'werkstatt/a_rechenwerk/a4_fortpflanzung.mjs: Varianzbestandteile aus der laufenden '
        + 'Sicht geholt, Summe gegen `streuung_kg` geprüft, Satterthwaite danebengerechnet',
      groesse: { wert: Math.round(groesster.kg_zu_weit),
                 einheit: `kg zu breites Band beim grössten Verluststrom (Faktor ${groesster.faktor.toFixed(1)})`,
                 basis: `${schlimm.length} von ${gesamt.length} Strömen betroffen, `
                      + `${betroffen.length} von ${zeilen.length} Zeilen über alle Gruppen` },
      gegenrede: 'Drei ernsthafte Einwände. **Erstens** ist ein zu weites Band die sichere Seite: '
        + 'Wer zu wenig behauptet, führt niemanden in die Irre. **Zweitens** ist Satterthwaite '
        + 'selbst eine Näherung und setzt voraus, dass die Bestandteile unabhängig sind — sie '
        + 'stammen hier teils aus denselben Wägungen. **Drittens** löst die Korrektur das '
        + 'eigentliche Problem nicht: 41 verwendbare Wägungen bleiben 41, ob man sie mit t = 12.7 '
        + 'oder t = 1.96 multipliziert. Trotzdem ist `min` an dieser Stelle nicht die vorsichtige '
        + 'Wahl, sondern die falsche: Sie ist nicht konservativ *begründet*, sie ist eine '
        + 'Verwechslung von „Freiheitsgrade einer Summe" mit „Freiheitsgrade des schwächsten '
        + 'Summanden".',
      aufwand: 'klein',
    }))
  }

  const richtig = gesamt.filter(z => z.faktor <= 1.05)
  if (richtig.length) raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'FPF', klasse: 1, marke: 'kein Fehler', sicherheit: 'hoch',
    ort: { sicht: 'v_verlust_je_gruppe' },
    titel: `Geprüft und in Ordnung: bei ${richtig.length} von ${gesamt.length} Strömen ist das `
         + 'schmale Band nicht zu haben',
    steht_da: richtig.map(z => `\`${z.strom}\` (df ${z.df_min}, Satterthwaite `
      + `${z.df_eff.toFixed(1)})`).join(', ') + '. Bei diesen Strömen trägt der schwach belegte '
      + 'Bestandteil die Varianz tatsächlich fast allein — das weite Band ist verdient, und '
      + 'Satterthwaite gibt dasselbe Ergebnis.',
    muesste: '—',
    warum: 'Die Gegenprobe zum Befund darüber. Eine Korrektur, die überall dieselbe Richtung '
      + 'hätte, wäre verdächtig; dass sie hier nur dort greift, wo sie greifen soll, ist der '
      + 'Beleg, dass gerechnet und nicht behauptet wurde.',
    beleg: 'werkstatt/a_rechenwerk/a4_fortpflanzung.mjs, Messreihe „Freiheitsgrade der Verlustbänder"',
    groesse: { wert: richtig.length, einheit: `von ${gesamt.length} Strömen haben heute schon das `
                                            + 'richtige Band', basis: 'Demodaten' },
    aufwand: 'klein',
  }))

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Vier erfundene Fälle für Satterthwaite, jeder mit bekannter Antwort:
 *
 *   1. Ein winziger Bestandteil mit df = 1 neben einem grossen mit df = 50.
 *      Das Minimum sagt 1, Satterthwaite muss nahe 50 sagen — sonst wäre der
 *      ganze Befund dieses Werkzeugs erfunden.
 *   2. Umgekehrt: Der df-1-Bestandteil trägt fast alles. Dann muss auch
 *      Satterthwaite nahe 1 sagen; eine Näherung, die immer grosszügiger ist,
 *      wäre wertlos.
 *   3. Zwei gleich grosse Bestandteile mit df = 10. Antwort muss 20 sein
 *      (bekanntes Ergebnis: gleiche Varianzen addieren ihre Freiheitsgrade).
 *   4. Ein Bestandteil mit Varianz null darf nichts beitragen.
 */
export async function selbstprobe() {
  const nah = (a, b, wieviel = 0.05) => Math.abs(a - b) / b <= wieviel

  const eins = satterthwaite([{ varianz: 1e-6, df: 1 }, { varianz: 1, df: 50 }])
  if (!nah(eins, 50)) return false

  const zwei = satterthwaite([{ varianz: 1, df: 1 }, { varianz: 1e-6, df: 50 }])
  if (!nah(zwei, 1)) return false

  const drei = satterthwaite([{ varianz: 5, df: 10 }, { varianz: 5, df: 10 }])
  if (!nah(drei, 20)) return false

  const vier = satterthwaite([{ varianz: 0, df: 1 }, { varianz: 3, df: 12 }])
  if (!nah(vier, 12)) return false

  // Und die Tabelle selbst: t muss mit steigenden Freiheitsgraden fallen.
  for (let d = 2; d <= 40; d++) if (t95(d) > t95(d - 1)) return false
  if (t95(1) < 12 || t95(999) > 2) return false

  return true
}
