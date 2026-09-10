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
 * Die Varianzbestandteile aus `v_verlust_je_gruppe` — **einzeln, nicht
 * gebündelt.**
 *
 * Die erste Fassung dieses Werkzeugs holte die drei Summanden so, wie die
 * Sicht sie bildet: einen für die Verdunstung, einen für Ausschuss/Fax/
 * Nebenkanal, einen für das Schimmelmodell. Jeder trug den Freiheitsgrad, den
 * die Sicht ihm gibt — und der ist selbst schon ein Minimum, nämlich
 * `min(df)` über die Sorten.
 *
 * Damit rechnete das Werkzeug Satterthwaite auf einem bereits verstümmelten
 * Eingang und fand nur bei einem der sechs Ströme etwas. Der Fehler steckt
 * eine Ebene tiefer: Auch **innerhalb** eines Bestandteils sind die Sorten
 * verschieden gut belegt, und auch dort wird minimiert statt gewichtet.
 *
 * Richtig ist die Zerlegung bis auf die einzelne Sorte:
 *
 *     je Sorte:   g_r² · varianz_eigen(sorte)        mit df(sorte)
 *     gepoolt:    (Σ g_r · gewicht)² · varianz_gesamt mit dem gepoolten df
 *     Modell:     die Regressionsterme                mit c_chargen − 1
 *
 * Aufgefallen ist das nicht diesem Werkzeug, sondern der Gegenrede zu einem
 * fremden Verdacht: Sie rechnete die Zerlegung bis auf die Sorte durch und kam
 * für alle sechs Ströme auf zweistellige Freiheitsgrade. Nachgerechnet stimmt
 * das — und der eigene Befund war um fünf Ströme zu schmal.
 *
 * Geholt wird die Zerlegung weiterhin aus der laufenden Sicht und nicht aus
 * einer Nachbildung, die beim nächsten Umbau still falsch würde.
 */
function bestandteile(db) {
  const text = wert(db, `select pg_get_viewdef('v_verlust_je_gruppe'::regclass, true)`)
  const marke = '), summe AS'
  const schnitt = text.indexOf(marke)
  if (schnitt < 0 || !text.includes('varianz_f AS') || !text.includes('je_sorte'))
    throw new Error('Der Aufbau von v_verlust_je_gruppe hat sich geändert — dieses Werkzeug '
      + 'findet die Varianz-Teilabfragen nicht mehr und darf deshalb nichts behaupten.')

  return frage(db, text.slice(0, schnitt + 1) + `
    select s.gruppe, s.schluessel, s.strom,
           'Verdunstung, ' || coalesce(s.sorte, 'alle Sorten gemeinsam') as name,
           (power(s.g_r, 2) * coalesce(u.varianz_eigen, 0))::float8 as varianz,
           coalesce(u.df, 1) as df
      from je_sorte s
      left join unsicherheit u on u.art = 'verdunstung' and not u.sorte is distinct from s.sorte
    union all
    select s.gruppe, s.schluessel, s.strom, 'Verdunstung, gepoolter Anteil',
           (power(sum(s.g_r * coalesce(u.gewicht_gesamt, 1)), 2)
            * max(coalesce(u.varianz_gesamt, 0)))::float8,
           max(coalesce(u.df, 1))
      from je_sorte s
      left join unsicherheit u on u.art = 'verdunstung' and not u.sorte is distinct from s.sorte
     group by s.gruppe, s.schluessel, s.strom
    union all
    select s.gruppe, s.schluessel, s.strom,
           'Ausschuss/Fax/Nebenkanal, ' || coalesce(s.sorte, 'alle Sorten gemeinsam'),
           (power(s.g_a, 2) * coalesce(u.varianz_eigen, 0))::float8, coalesce(u.df, 1)
      from je_sorte s
      left join unsicherheit u on u.art = s.koeff_art and not u.sorte is distinct from s.sorte
     where s.koeff_art is not null
    union all
    select s.gruppe, s.schluessel, s.strom, 'Ausschuss/Fax/Nebenkanal, gepoolter Anteil',
           (power(sum(s.g_a * coalesce(u.gewicht_gesamt, 1)), 2)
            * max(coalesce(u.varianz_gesamt, 0)))::float8,
           max(coalesce(u.df, 1))
      from je_sorte s
      left join unsicherheit u on u.art = s.koeff_art and not u.sorte is distinct from s.sorte
     where s.koeff_art is not null
     group by s.gruppe, s.schluessel, s.strom
    union all
    select m.gruppe, m.schluessel, m.strom, 'Schimmelmodell',
           (power(m.g_achse, 2) * coalesce(sm.var_achse, 0)
            + 2 * m.g_achse * m.g_steigung * coalesce(sm.kov_achse_k, 0)
            + power(m.g_steigung, 2) * coalesce(sm.var_k, 0)
            + power(m.g_a0, 2) * case when sm.brauchbar then coalesce(sm.sockel_var, 0)
                                      else 0 end)::float8,
           coalesce(sm.c_chargen - 1, 1)
      from je_strom_modell m cross join modell sm`)
}

/** Alle Bestandteile einer Zeile, gruppiert nach (Gruppe, Schlüssel, Strom). */
function nachStrom(zeilen) {
  const karte = new Map()
  for (const z of zeilen) {
    const s = `${z.gruppe}|${z.schluessel}|${z.strom}`
    ;(karte.get(s) ?? karte.set(s, []).get(s)).push({
      name: z.name, varianz: Number(z.varianz), df: Number(z.df),
    })
  }
  return karte
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const roh = bestandteile(db)
  const teile = nachStrom(roh)
  const raus = []

  const veroeffentlicht = frage(db, `
    select gruppe, schluessel, strom, streuung_kg::float8 as streuung, df, kg::float8 as kg,
           kg_unten::float8 as unten, kg_oben::float8 as oben
      from v_verlust_je_gruppe where streuung_kg is not null`)
  const schluessel = (z) => `${z.gruppe}|${z.schluessel}|${z.strom}`

  /* --- Gegenprobe: ergibt die Zerlegung die veröffentlichte Streuung? ----- */
  let schlimmste = 0, geprueft = 0
  for (const v of veroeffentlicht) {
    const t = teile.get(schluessel(v))
    if (!t) continue
    const nachgerechnet = Math.sqrt(Math.max(t.reduce((a, x) => a + (x.varianz ?? 0), 0), 0))
    schlimmste = Math.max(schlimmste, Math.abs(nachgerechnet - v.streuung))
    geprueft++
  }
  if (!geprueft)
    throw new Error('Keine einzige Zeile liess sich zerlegen — das Werkzeug hat die falschen '
      + 'Teilabfragen erwischt und darf nichts behaupten.')
  if (schlimmste > 0.02)
    throw new Error(`Die aus der Sicht geholten Varianzbestandteile ergeben nicht die `
      + `veröffentlichte Streuung (grösste Abweichung ${schlimmste.toFixed(4)} kg auf `
      + `${geprueft} Zeilen). Das Werkzeug rechnet dann etwas anderes nach, als dasteht.`)

  /* --- Der Vergleich ------------------------------------------------------ */
  const zeilen = veroeffentlicht.map(v => {
    const t = teile.get(schluessel(v))
    if (!t) return null
    const dfEff = satterthwaite(t)
    if (dfEff === null) return null
    const tJetzt = t95(v.df), tRichtig = t95(Math.round(dfEff))
    const gesamt = t.reduce((a, x) => a + (x.varianz ?? 0), 0)
    const groesster = t.filter(x => x.varianz > 0).sort((a, b) => b.varianz - a.varianz)[0]
    return { ...v, teile: t, df_min: v.df, df_eff: dfEff, groesster,
             anteil_groesster: gesamt > 0 ? groesster?.varianz / gesamt : null,
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
    spalten: ['Verlustursache', 'Wert (kg)', 'Streuung (kg)', 'Bestandteile',
              'df heute (Minimum)', 'df nach Satterthwaite', 't heute', 't richtig',
              'Band heute (± kg)', 'Band richtig (± kg)', 'grösster Bestandteil'],
    erklaerung: 'Die Zeilen sind die sechs Ströme der Gesamtsaison. Die Varianz wird bis auf die '
      + 'einzelne Sorte zerlegt — je Sorte ein Bestandteil mit ihrem eigenen Freiheitsgrad, dazu '
      + 'der gepoolte Anteil und das Schimmelmodell. „df heute" ist das Minimum über alles, so wie '
      + '`v_verlust_je_gruppe` es bildet; „df nach Satterthwaite" gewichtet jeden Freiheitsgrad '
      + 'mit dem Quadrat seines Varianzanteils. Die Spalte ganz rechts nennt den Bestandteil, der '
      + 'die Varianz trägt — er ist fast nie derselbe, der den Freiheitsgrad setzt. Die Varianzen '
      + 'stammen aus der laufenden Sicht, und ihre Summe wurde auf jeder Zeile gegen die '
      + 'veröffentlichte Streuung geprüft.',
    zeilen: gesamt.map(z => ({
      'Verlustursache': z.strom, 'Wert (kg)': z.kg.toFixed(0),
      'Streuung (kg)': z.streuung.toFixed(1),
      'Bestandteile': z.teile.filter(x => x.varianz > 0).length,
      'df heute (Minimum)': z.df_min,
      'df nach Satterthwaite': z.df_eff.toFixed(1),
      't heute': t95(z.df_min).toFixed(3), 't richtig': t95(Math.round(z.df_eff)).toFixed(3),
      'Band heute (± kg)': z.halb_jetzt.toFixed(0),
      'Band richtig (± kg)': z.halb_richtig.toFixed(0),
      'grösster Bestandteil': z.groesster
        ? `${z.groesster.name} (${(100 * z.anteil_groesster).toFixed(0)} %, df ${z.groesster.df})`
        : '—',
    })),
  }))

  const schlimm = gesamt.filter(z => z.faktor > 1.2)
  if (schlimm.length) {
    const groesster = schlimm[0]
    const summe = schlimm.reduce((a, z) => a + z.kg_zu_weit, 0)
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'FPF', klasse: 3, marke: 'Reparatur', sicherheit: 'hoch',
      ort: { sicht: 'v_verlust_je_gruppe' },
      titel: `Die Unsicherheitsbänder sind bei ${schlimm.length} von ${gesamt.length} Strömen `
           + `rund ${(schlimm.reduce((a, z) => a + z.faktor, 0) / schlimm.length).toFixed(1)}-mal `
           + 'zu weit — der schlechteste Bestandteil bestimmt sie allein',
      steht_da: 'Die Freiheitsgrade eines Bands entstehen als `LEAST(df_verdunstung, '
        + 'df_ausschuss, df_modell)`, und innerhalb jedes Bestandteils noch einmal als `min(df)` '
        + 'über die Sorten. Zweimal ein Minimum, und beide Male zieht der am schlechtesten '
        + `belegte Summand das ganze Band auf. Alle ${gesamt.length} Ströme stehen deshalb auf `
        + `df = 1 und t = 12.706. Zerlegt man die Varianz bis auf die einzelne Sorte und `
        + `gewichtet jeden Freiheitsgrad mit seinem Varianzanteil, kommen `
        + `${Math.min(...schlimm.map(z => z.df_eff)).toFixed(0)} bis `
        + `${Math.max(...schlimm.map(z => z.df_eff)).toFixed(0)} heraus. Beim grössten Strom `
        + `(\`${groesster.strom}\`, ${groesster.kg.toFixed(0)} kg) trägt `
        + `\`${groesster.groesster?.name}\` `
        + `${(100 * groesster.anteil_groesster).toFixed(0)} % der Varianz und hat df `
        + `${groesster.groesster?.df} — den Freiheitsgrad setzt trotzdem ein Bestandteil mit `
        + 'df 1.',
      muesste: 'Die Freiheitsgrade einer Varianzsumme sind nicht das Minimum, sondern '
        + 'Satterthwaites Näherung: `df_eff = (Σvᵢ)² / Σ(vᵢ²/dfᵢ)`. Sie ist eine Zeile SQL, '
        + 'braucht nichts, was nicht schon dasteht, und ist nicht grosszügiger — wo der schwache '
        + 'Bestandteil die Varianz wirklich trägt, ergibt sie von selbst wieder df = 1. Nötig ist '
        + 'sie an **beiden** Stellen: über die drei Bestandteile und über die Sorten darin.',
      warum: 'Ein zu weites Band ist keine gute Vorsicht. Es beantwortet die Frage „darf ich '
        + 'diesen Unterschied glauben?" mit Nein, wo die Antwort Ja wäre. Der Betrieb hat für '
        + 'diese Zahlen Arbeiterzeit bezahlt; ein Band, das ihren Wert um mehr als das Sechsfache '
        + 'kleinredet, macht einen Teil dieser Arbeit wertlos.',
      beleg: 'werkstatt/a_rechenwerk/a4_fortpflanzung.mjs: Varianz aus der laufenden Sicht bis '
        + 'auf die einzelne Sorte zerlegt, Summe je Zeile gegen `streuung_kg` geprüft, '
        + 'Satterthwaite danebengerechnet',
      groesse: { wert: Math.round(summe),
                 einheit: `kg zu breite Bänder über alle ${schlimm.length} Ströme zusammen `
                        + `(grösster einzeln: ${Math.round(groesster.kg_zu_weit)} kg bei `
                        + `${groesster.strom})`,
                 basis: `${betroffen.length} von ${zeilen.length} Zeilen über alle Gruppen betroffen` },
      gegenrede: 'Drei ernsthafte Einwände. **Erstens** ist ein zu weites Band die sichere Seite: '
        + 'Wer zu wenig behauptet, führt niemanden in die Irre. **Zweitens** ist Satterthwaite '
        + 'selbst eine Näherung und setzt voraus, dass die Bestandteile unabhängig sind — sie '
        + 'stammen hier teils aus denselben Wägungen; für die Sorten untereinander ist die '
        + 'Annahme gut, für Verdunstung gegen Schimmel weniger. **Drittens** löst die Korrektur '
        + 'das eigentliche Problem nicht: 41 verwendbare Wägungen bleiben 41. Trotzdem ist `min` '
        + 'hier nicht die vorsichtige, sondern die falsche Wahl — sie verwechselt „Freiheitsgrade '
        + 'einer Summe" mit „Freiheitsgrade des schwächsten Summanden". Und für den grössten '
        + 'Strom gilt zusätzlich: Die Delta-Methode unterschätzt die Streuung dort um Faktor 3.9 '
        + '(Befund AUF-001), die beiden Fehler heben sich zum Teil auf. **Wer nur die '
        + 'Freiheitsgrade richtigstellt, macht das Schimmelband schlechter, nicht besser.**',
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
      + 'Bestandteil die Varianz tatsächlich fast allein — das weite Band ist verdient.',
    muesste: '—',
    warum: 'Die Gegenprobe zum Befund darüber. Eine Korrektur, die überall in dieselbe Richtung '
      + 'ginge, wäre verdächtig.',
    beleg: 'werkstatt/a_rechenwerk/a4_fortpflanzung.mjs, Messreihe „Freiheitsgrade der Verlustbänder"',
    groesse: { wert: richtig.length, einheit: `von ${gesamt.length} Strömen haben schon das `
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
