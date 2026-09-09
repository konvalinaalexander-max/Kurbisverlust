/**
 * A3 — Der Verhältnis-Schätzer: der Nenner ist selbst geschätzt.
 *
 * DIE FRAGE
 *
 * Die ganze Eingangsmasse einer Kohorte entsteht aus einer Division:
 *
 *     m0 = geliefert_kg / verkaufsfaehig_anteil
 *
 * Der Zähler ist gewogen. Der Nenner ist **geschätzt** — er ist ein Produkt
 * aus fünf Koeffizienten, von denen jeder aus wenigen Messungen kommt:
 *
 *     anteil = (1−r)^t · (1−a₀) · (1−f) · (1−klein−gross) · (1−a_fax)
 *
 * Das ist ein Verhältnis-Schätzer, und Verhältnis-Schätzer sind nicht
 * erwartungstreu. Für eine gekrümmte Funktion gilt die Ungleichung von Jensen:
 * der Mittelwert der Funktion ist nicht die Funktion des Mittelwerts. `1/x` ist
 * konvex, also gilt
 *
 *     E[1/â]  >  1/E[â]
 *
 * — und zwar immer, nicht manchmal. Die geschätzte Eingangsmasse ist im Mittel
 * **zu gross**, ganz gleich wie sorgfältig die Koeffizienten geschätzt sind.
 * Wieviel zu gross, hängt allein davon ab, wie unsicher der Nenner ist.
 *
 * DIE RECHNUNG
 *
 * Der Nenner ist ein Produkt. Im Log-Raum wird daraus eine Summe, und die
 * Summe vieler kleiner Unsicherheiten ist annähernd normalverteilt — der
 * Nenner selbst also annähernd lognormal. Für ein lognormales â mit
 * `Var(ln â) = s²` gilt exakt:
 *
 *     E[1/â] / (1/E[â])  =  exp(s²)
 *
 * Der Fehler ist damit **beziffert und nicht bloss benannt**: relativ
 * `exp(s²) − 1`, in Kilogramm `m0 · (exp(s²) − 1)`.
 *
 * WARUM DAS NICHT „NUR THEORIE" IST
 *
 * Zwei Gründe, sich das anzusehen, obwohl der Effekt klein sein dürfte.
 *
 * Erstens ist er **einseitig**. Zufällige Fehler mitteln sich über 42 Chargen
 * weg; dieser nicht. Er zeigt in jeder Charge in dieselbe Richtung und addiert
 * sich zur Saisonsumme.
 *
 * Zweitens wächst er mit dem Quadrat der Unsicherheit. Bei einer Sorte mit
 * eigenen Wägungen ist er verschwindend; bei einer Sorte, die sich die
 * Verdunstungsrate von allen anderen leiht, ist er es womöglich nicht — und
 * das sind zwölf von vierzehn Sorten.
 *
 * WAS DIESES WERKZEUG TUT
 *
 * Es rechnet `s²` je Kohortenzeile aus den Bändern, die das Programm für seine
 * Koeffizienten ohnehin führt, und daraus die Verzerrung in Kilogramm. Und es
 * prüft die Formel gegen eine Ziehung: 20 000 lognormale Nenner, gemittelt,
 * müssen dasselbe ergeben. Eine Formel, die nur auf dem Papier steht, ist in
 * dieser Werkstatt kein Beleg.
 */
import { frage, wert, befund, messung, zufall, mittel } from '../umgebung.mjs'

const WERKSTATT = 'A — Rechenwerk'

/** Der Boden, den die Kaskade unter den Anteil legt. */
const BODEN = 0.25

/**
 * Die Varianz von `ln(anteil)` je Kohortenzeile.
 *
 * `anteil` ist ein Produkt, `ln(anteil)` also eine Summe von fünf Beiträgen.
 * Für jeden Faktor `(1−θ)` gilt `∂ln(1−θ)/∂θ = −1/(1−θ)`, beim
 * Verdunstungsglied `(1−r)^t` kommt das `t` davor. Die Varianzen der
 * Koeffizienten stammen aus den Bändern, die die Auswertung führt: halbe
 * Bandbreite geteilt durch 1.96, quadriert.
 *
 * Die Koeffizienten werden als unabhängig behandelt. Sind sie es nicht, ist
 * die Zahl unten falsch — und zwar in unbekannter Richtung. Das steht in der
 * Gegenrede und nicht im Kleingedruckten.
 */
const VARIANZ_JE_ZEILE = `
  with sigma as (
    select sorte,
           power(greatest(oben - unten, 0) / (2 * 1.96), 2) as var_r
      from v_koeff_verdunstung
  ), sa as (
    select sorte, power(greatest(oben - unten, 0) / (2 * 1.96), 2) as var_klein
      from v_koeff_ausschuss
  ), sn as (
    select sorte, power(greatest(oben - unten, 0) / (2 * 1.96), 2) as var_gross
      from v_koeff_nebenkanal
  ), sf as (
    select sorte, power(greatest(oben - unten, 0) / (2 * 1.96), 2) as var_fax
      from v_koeff_fax
  ), modell as (
    select coalesce(sockel_var, 0) as var_a0 from v_schimmel_modell
  )
  select k.charge_nr, k.sorte, k.portion, k.alter_tage::float8 as t,
         k.m0::float8 as m0, k.geliefert_kg::float8 as geliefert,
         k.verkaufsfaehig_anteil::float8 as anteil,
         k.r::float8 as r, k.a0::float8 as a0, k.f::float8 as f,
         k.a_klein_n::float8 as klein, k.a_gross_n::float8 as gross, k.a_fax::float8 as fax,
         coalesce(s.var_r, 0)::float8 as var_r, coalesce(sa.var_klein, 0)::float8 as var_klein,
         coalesce(sn.var_gross, 0)::float8 as var_gross, coalesce(sf.var_fax, 0)::float8 as var_fax,
         (select var_a0 from modell)::float8 as var_a0
    from mv_kaskade k
    left join sigma s  on s.sorte  = k.sorte
    left join sa      on sa.sorte  = k.sorte
    left join sn      on sn.sorte  = k.sorte
    left join sf      on sf.sorte  = k.sorte
   where k.m0 is not null and k.verkaufsfaehig_anteil > 0`

/** Var(ln anteil) — die Summe der fünf Beiträge, jeder mit seiner Ableitung. */
export function logVarianz(z) {
  const teil = (nenner, varianz, faktor = 1) =>
    nenner > 1e-9 ? (faktor / nenner) ** 2 * varianz : 0
  return teil(1 - z.r, z.var_r, z.t)          // (1−r)^t  →  ∂ln/∂r = −t/(1−r)
       + teil(1 - z.a0, z.var_a0)
       + teil(1 - z.klein - z.gross, z.var_klein)
       + teil(1 - z.klein - z.gross, z.var_gross)
       + teil(1 - z.fax, z.var_fax)
}

/** Die relative Verzerrung von 1/â bei lognormalem â: exp(s²) − 1. */
export const verzerrung = (s2) => Math.expm1(s2)

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const zeilen = frage(db, VARIANZ_JE_ZEILE)
  const raus = []
  if (!zeilen.length) return raus

  const mit = zeilen.map(z => {
    const s2 = logVarianz(z)
    return { ...z, s2, rel: verzerrung(s2), kg: z.m0 * verzerrung(s2) }
  })

  const summeM0 = mit.reduce((a, z) => a + z.m0, 0)
  const summeKg = mit.reduce((a, z) => a + z.kg, 0)
  const jeSorte = [...new Map(mit.map(z => [z.sorte, null])).keys()].map(sorte => {
    const s = mit.filter(z => z.sorte === sorte)
    return { sorte, n: s.length, m0: s.reduce((a, z) => a + z.m0, 0),
             kg: s.reduce((a, z) => a + z.kg, 0),
             rel: mittel(s.map(z => z.rel)),
             s: Math.sqrt(mittel(s.map(z => z.s2))),
             basis: wert(db, `select basis from v_koeff_verdunstung
                               where sorte = '${sorte.replaceAll("'", "''")}'`) }
  }).sort((a, b) => b.kg - a.kg)

  const amBoden = Number(wert(db, `select count(*) from mv_kaskade
                                    where verkaufsfaehig_anteil <= ${BODEN} + 1e-9`))

  raus.push(messung({
    werkstatt: WERKSTATT,
    titel: 'Die einseitige Verzerrung der geschätzten Eingangsmasse, je Sorte',
    einheit: 'kg',
    spalten: ['Sorte', 'Kohorten', 'geschätzter Eingang (kg)', 'Streuung von ln(Anteil)',
              'Verzerrung', 'zu viel (kg)', 'woher die Verdunstungsrate kommt'],
    erklaerung: 'Die Eingangsmasse entsteht als `geliefert ÷ verkaufsfähiger Anteil`. Weil der '
      + 'Nenner geschätzt ist und `1/x` sich krümmt, ist das Ergebnis im Mittel zu gross — nach '
      + 'Jensen, und zwar immer in dieselbe Richtung. Die Spalte „Streuung von ln(Anteil)" ist '
      + 'die Wurzel aus der Summe der fünf Koeffizientenbeiträge, jeder mit seiner Ableitung '
      + 'gewichtet; „Verzerrung" ist `exp(s²) − 1`. Die letzte Spalte zeigt, woran es liegt: '
      + 'Sorten mit geliehener Rate haben ein weiteres Band und damit eine grössere Verzerrung.',
    zeilen: jeSorte.map(s => ({
      'Sorte': s.sorte, 'Kohorten': s.n, 'geschätzter Eingang (kg)': s.m0.toFixed(0),
      'Streuung von ln(Anteil)': s.s.toFixed(4),
      'Verzerrung': (100 * s.rel).toFixed(3) + ' %',
      'zu viel (kg)': s.kg.toFixed(1),
      'woher die Verdunstungsrate kommt': s.basis ?? '—',
    })),
  }))

  const anteilProzent = 100 * summeKg / summeM0
  raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'VHT', klasse: anteilProzent >= 0.5 ? 2 : 1,
    marke: anteilProzent >= 0.5 ? 'Reparatur' : 'kein Fehler', sicherheit: 'hoch',
    ort: { sicht: 'mv_kaskade' },
    titel: anteilProzent >= 0.5
      ? `Die geschätzte Eingangsmasse ist systematisch zu gross — um ${summeKg.toFixed(0)} kg`
      : `Geprüft: die Division durch einen geschätzten Nenner verzerrt um ${summeKg.toFixed(0)} kg `
        + `(${anteilProzent.toFixed(3)} %) — zu wenig, um etwas zu ändern`,
    steht_da: `\`m0 = geliefert_kg / verkaufsfaehig_anteil\` teilt eine gewogene Zahl durch eine `
      + 'geschätzte. Weil `1/x` konvex ist, liegt der Erwartungswert des Quotienten über dem '
      + `Quotienten der Erwartungswerte. Gerechnet über alle ${mit.length} Kohortenzeilen: `
      + `${summeKg.toFixed(0)} kg auf ${summeM0.toFixed(0)} kg geschätzten Eingang, also `
      + `${anteilProzent.toFixed(3)} %. Am stärksten betroffen ist \`${jeSorte[0].sorte}\` mit `
      + `${jeSorte[0].kg.toFixed(1)} kg — ${jeSorte[0].basis}.`,
    muesste: anteilProzent >= 0.5
      ? 'Die Korrektur ist eine Multiplikation: `m0 · exp(−s²)`, wobei `s²` die Log-Varianz des '
        + 'Anteils ist. Alle fünf Varianzen führt die Auswertung ohnehin.'
      : '— nichts. Die Zahl steht hier, weil „vernachlässigbar" eine Behauptung ist, solange '
        + 'niemand sie ausgerechnet hat. Jetzt ist sie ausgerechnet.',
    warum: 'Der Unterschied zu einem gewöhnlichen Messfehler ist die Richtung. Ein zufälliger '
      + `Fehler mittelt sich über ${mit.length} Kohorten weg; dieser nicht — er zeigt in jeder `
      + 'Zeile nach oben und addiert sich. Ein zu grosser Eingang bedeutet ausserdem einen zu '
      + 'grossen Verlust, denn der Verlust ist die Differenz zum Ausgang.',
    beleg: 'werkstatt/a_rechenwerk/a3_verhaeltnis.mjs: Log-Varianz je Zeile aus den '
      + 'Koeffizientenbändern, `exp(s²) − 1`; die Formel gegen 20 000 gezogene Nenner geprüft',
    groesse: { wert: summeKg.toFixed(0),
               einheit: `kg zu viel geschätzter Eingang (${anteilProzent.toFixed(3)} % von `
                      + `${(summeM0 / 1000).toFixed(0)} t)`,
               basis: `${mit.length} Kohortenzeilen, Demodaten` },
    ...(anteilProzent >= 0.5 ? { gegenrede:
      'Die Rechnung behandelt die fünf Koeffizienten als unabhängig. Sind sie es nicht — und '
      + 'Verdunstung und Schimmel stammen teils aus denselben Wägungen —, ist `s²` falsch, und '
      + 'zwar in unbekannter Richtung. Ausserdem setzt `exp(s²)` voraus, dass der Nenner '
      + 'lognormal ist; er ist es nur annähernd, weil er ein Produkt weniger Faktoren ist und '
      + 'nicht vieler.' } : {}),
    aufwand: 'klein',
  }))

  /* --- Der Boden bei 0.25 --- */
  raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'VHT', klasse: 1,
    marke: amBoden > 0 ? 'Reparatur' : 'kein Fehler', sicherheit: 'hoch',
    ort: { sicht: 'mv_kaskade' },
    titel: amBoden > 0
      ? `Bei ${amBoden} Kohorten liegt der verkaufsfähige Anteil auf dem Boden von ${BODEN}`
      : `Geprüft und in Ordnung: der Boden von ${BODEN} unter dem verkaufsfähigen Anteil greift nie`,
    steht_da: `Die Kaskade legt mit \`GREATEST(…, ${BODEN})\` einen Boden unter den `
      + 'verkaufsfähigen Anteil, damit die Division nicht davonläuft. Ein Boden, der greift, macht '
      + `aus der Schätzung eine Schranke. Gemessen über alle Kohortenzeilen: ${amBoden} liegen `
      + `darauf. Der kleinste vorkommende Anteil ist `
      + `${Math.min(...mit.map(z => z.anteil)).toFixed(4)}, der grösste `
      + `${Math.max(...mit.map(z => z.anteil)).toFixed(4)}.`,
    muesste: amBoden > 0
      ? 'Wo der Boden greift, darf keine Zahl herauskommen, die aussieht wie eine Schätzung. '
        + 'Diese Zeilen gehören als „nicht schätzbar" gekennzeichnet, nicht auf den Boden gesetzt.'
      : '—',
    warum: 'Ein Boden ist eine stille Annahme: „schlimmer als das wird es nicht". Greift er, steht '
      + 'auf dem Bildschirm eine Zahl, die nicht aus den Daten kommt, sondern aus dieser Annahme — '
      + 'und nichts sagt es. Dass er heute nie greift, ist deshalb eine Auskunft, die in den '
      + 'Bericht gehört.',
    beleg: 'werkstatt/a_rechenwerk/a3_verhaeltnis.mjs',
    groesse: { wert: amBoden, einheit: `Kohortenzeilen auf dem Boden (von ${mit.length})`,
               basis: 'Demodaten' },
    ...(amBoden > 0 ? { gegenrede: 'Der Boden ist ein Schutz gegen Division durch fast null und '
      + 'als solcher richtig. Die Frage ist nicht, ob er dasteht, sondern ob sein Greifen sichtbar '
      + 'wird.' } : {}),
    aufwand: 'klein',
  }))

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Die Formel gegen die Wirklichkeit: `exp(s²) − 1` muss dasselbe ergeben wie
 * das Mitteln von 20 000 gezogenen Kehrwerten. Stimmen die beiden nicht
 * überein, ist die Herleitung falsch — und dann ist jede Kilogrammzahl dieses
 * Werkzeugs erfunden.
 *
 * Dazu zwei Gegenproben: Ohne Unsicherheit muss die Verzerrung genau null sein
 * (sonst rechnet die Formel etwas herbei), und die Log-Varianz muss mit der
 * Lagerdauer wachsen — `(1−r)^t` trägt `t²`, und wer das `t` vergisst,
 * unterschätzt die längsten Lagerungen am stärksten.
 */
export async function selbstprobe({ saat = 20260909 } = {}) {
  const r = zufall(saat)

  for (const s of [0.02, 0.1, 0.3]) {
    const s2 = s * s
    const gezogen = mittel(Array.from({ length: 20000 }, () => 1 / Math.exp(r.normal(-s2 / 2, s))))
    // E[â] = 1 bei μ = −s²/2, also ist 1/E[â] = 1 und der Mittelwert direkt die Verzerrung.
    const erwartet = 1 + verzerrung(s2)
    if (Math.abs(gezogen - erwartet) / erwartet > 0.03) return false
  }

  if (verzerrung(0) !== 0) return false

  const zeile = { r: 0.005, a0: 0.05, f: 0.1, klein: 0.05, gross: 0.02, fax: 0.02,
                  var_r: 1e-8, var_a0: 1e-6, var_klein: 1e-5, var_gross: 1e-5, var_fax: 1e-5 }
  const kurz = logVarianz({ ...zeile, t: 10 })
  const lang = logVarianz({ ...zeile, t: 100 })
  if (!(lang > kurz)) return false
  // Der Verdunstungsbeitrag wächst mit t²; bei zehnfacher Dauer also hundertfach.
  const nurR = (t) => logVarianz({ ...zeile, t, var_a0: 0, var_klein: 0, var_gross: 0, var_fax: 0 })
  if (Math.abs(nurR(100) / nurR(10) - 100) > 1) return false

  return true
}
