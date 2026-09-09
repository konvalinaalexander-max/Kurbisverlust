/**
 * Sonde 04 — Orakel
 *
 * Ein zweites Rechenwerk, das dieselbe Kaskade rechnet, aber nichts von der
 * Datenbank übernimmt ausser den Eingangswerten. Geschrieben aus `docs/ABLAUF.md`
 * und `docs/programm.html`, nicht aus dem SQL — sonst prüft man eine Abschrift
 * gegen ihr Original und findet zwangsläufig nichts.
 *
 * Was hier geprüft wird, ist genau die Stelle, an der ein Rechenfehler
 * niemandem auffällt: Die Summe geht auf (das prüft `invarianten.mjs`), die
 * Zahlen sehen plausibel aus — und trotzdem steht ein Faktor an der falschen
 * Stelle. Ein Term zu viel oder zu wenig verschiebt Masse zwischen zwei
 * Verlustarten, ohne die Bilanz zu stören.
 *
 * Die Formeln, wie sie in der Dokumentation stehen:
 *
 *   m1              = m0 · (1 − r)^t
 *   Verdunstung     = m0 − m1
 *   Sockel          = m1 · a₀
 *   Schimmel        = m1 · (1 − a₀) · f
 *   m2              = m1 · (1 − a₀) · (1 − f)
 *   zu klein        = m2 · a_klein
 *   Nebenkanal      = m2 · a_gross
 *   Fax             = m2 · (1 − a_klein − a_gross) · a_fax
 *   verkaufsfähig   = m2 · (1 − a_klein − a_gross) · (1 − a_fax)
 *
 *   f (Modell)      = 1 − exp(−exp(η)),  η = ln λ' + k · ln(max(t, 1))
 *   Anteil          = max((1−r)^t · (1−a₀) · (1−f) · (1−a_klein−a_gross) · (1−a_fax), 0.25)
 *   m0 (ausgelagert)= geliefert / Anteil
 */
import { befund, frage, kopie, tue } from '../umgebung.mjs'

export const lang = false

/* ---------- Das zweite Rechenwerk ---------------------------------------- */

/** Die Kaskade, aus der Dokumentation nachgebaut. Reines JavaScript. */
export function kaskade({ m0, r, t, a0, f, klein, gross, fax }) {
  const m1 = m0 * Math.pow(1 - r, t)
  const m2 = m1 * (1 - a0) * (1 - f)
  const rest = m2 * (1 - klein - gross)
  return {
    m1, m2,
    verdunstung: m0 - m1,
    sockel: m1 * a0,
    schimmel: m1 * (1 - a0) * f,
    klein: m2 * klein,
    nebenkanal: m2 * gross,
    fax: rest * fax,
    verkaufsfaehig: rest * (1 - fax),
  }
}

/** Der verkaufsfähige Anteil einer Portion — mit dem Boden bei 25 %. */
export function anteil({ r, t, a0, f, klein, gross, fax }) {
  const roh = Math.pow(1 - r, t) * (1 - a0) * (1 - f) * (1 - klein - gross) * (1 - fax)
  return { roh, gedeckelt: Math.max(roh, 0.25), amBoden: roh < 0.25 }
}

/** Das Verderbsmodell — Gompertz auf der Lagerdauer. */
export function fModell({ lnLambda, k, t }) {
  const eta = Math.min(Math.max(lnLambda + k * Math.log(Math.max(t, 1)), -40), 3)
  return { eta, f: Math.min(Math.max(1 - Math.exp(-Math.exp(eta)), 0), 1) }
}

/* ---------- Lauf ---------------------------------------------------------- */

const GENAU = 1e-6      // relative Genauigkeit; darunter ist es Rundung

export async function laufen({ db }) {
  const raus = []
  const B = (o) => raus.push(befund({ sonde: '04_orakel', kuerzel: 'ORA', ...o }))
  const z = (x) => Number(x ?? 0)

  const zeilen = frage(db, `
    select charge_nr, sorte, portion, kohorte::text as kohorte,
           alter_tage::float8 as alter_tage, m0::float8 as m0, m1::float8 as m1, m2::float8 as m2,
           r::float8 as r, f::float8 as f, a0::float8 as a0,
           a_klein_n::float8 as klein, a_gross_n::float8 as gross, a_fax::float8 as fax,
           verdunstung_kg::float8 as verdunstung, sockel_kg::float8 as sockel,
           schimmel_kg::float8 as schimmel, klein_kg::float8 as klein_kg,
           nebenkanal_kg::float8 as nebenkanal, fax_kg::float8 as fax_kg,
           verkaufsfaehig_kg::float8 as verkaufsfaehig,
           verkaufsfaehig_anteil::float8 as v_anteil, geliefert_kg::float8 as geliefert,
           d_m1_r::float8 as d_m1_r, d_f_eta::float8 as d_f_eta, u::float8 as u,
           modell_gilt, f_extrapoliert
      from mv_kaskade where m0 > 0`)

  if (zeilen.length === 0) return raus

  /* 4a. Jeder Strom gegen die Formel aus der Dokumentation */
  const STROEME = ['m1', 'm2', 'verdunstung', 'sockel', 'schimmel', 'klein', 'nebenkanal', 'fax', 'verkaufsfaehig']
  const abw = Object.fromEntries(STROEME.map(s => [s, { max: 0, zeile: null }]))
  for (const q of zeilen) {
    const soll = kaskade({ m0: z(q.m0), r: z(q.r), t: z(q.alter_tage), a0: z(q.a0), f: z(q.f),
                           klein: z(q.klein), gross: z(q.gross), fax: z(q.fax) })
    const ist = { ...soll, m1: z(q.m1), m2: z(q.m2), verdunstung: z(q.verdunstung),
                  sockel: z(q.sockel), schimmel: z(q.schimmel), klein: z(q.klein_kg),
                  nebenkanal: z(q.nebenkanal), fax: z(q.fax_kg), verkaufsfaehig: z(q.verkaufsfaehig) }
    for (const s of STROEME) {
      const d = Math.abs(soll[s] - ist[s]) / Math.max(Math.abs(soll[s]), 1)
      if (d > abw[s].max) abw[s] = { max: d, zeile: q, soll: soll[s], ist: ist[s] }
    }
  }
  for (const [s, a] of Object.entries(abw)) {
    if (a.max <= GENAU) continue
    B({ klasse: 3, ort: { sicht: 'mv_kaskade', spalte: s },
        titel: `„${s}" rechnet anders als die Dokumentation`,
        steht_da: `Charge ${a.zeile.charge_nr}, ${a.zeile.portion}, t=${a.zeile.alter_tage}: ${a.ist.toFixed(2)} kg`,
        muesste: `${a.soll.toFixed(2)} kg nach der Formel in docs/ABLAUF.md`,
        warum: 'Die Bilanz geht trotzdem auf, weil beide Seiten dieselbe Gesamtmasse verteilen. '
             + 'Nur landet sie in der falschen Ursache — und der Betrieb ändert dann das Falsche.',
        beleg: 'pruefwerk/sonden/04_orakel.mjs → kaskade()',
        groesse: { wert: Number((a.max * 100).toFixed(3)), einheit: '% Abweichung', basis: `${zeilen.length} Portionen` },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* 4b. Der verkaufsfähige Anteil und die Rückrechnung auf m0 */
  let anteilAbw = { max: 0 }, m0Abw = { max: 0 }, amBoden = []
  for (const q of zeilen) {
    const a = anteil({ r: z(q.r), t: z(q.alter_tage), a0: z(q.a0), f: z(q.f),
                       klein: z(q.klein), gross: z(q.gross), fax: z(q.fax) })
    const d = Math.abs(a.gedeckelt - z(q.v_anteil)) / Math.max(a.gedeckelt, 1e-9)
    if (d > anteilAbw.max) anteilAbw = { max: d, q, soll: a.gedeckelt, ist: z(q.v_anteil) }
    if (a.amBoden) amBoden.push({ q, roh: a.roh })
    if (q.portion === 'ausgelagert' && z(q.geliefert) > 0) {
      const soll = z(q.geliefert) / a.gedeckelt
      const dm = Math.abs(soll - z(q.m0)) / Math.max(soll, 1)
      if (dm > m0Abw.max) m0Abw = { max: dm, q, soll, ist: z(q.m0) }
    }
  }
  if (anteilAbw.max > GENAU) {
    B({ klasse: 3, ort: { sicht: 'mv_kaskade', spalte: 'verkaufsfaehig_anteil' },
        titel: 'Der verkaufsfähige Anteil rechnet anders als die Dokumentation',
        steht_da: `${anteilAbw.ist.toFixed(6)} bei Charge ${anteilAbw.q.charge_nr}, t=${anteilAbw.q.alter_tage}`,
        muesste: `${anteilAbw.soll.toFixed(6)}`,
        warum: 'Aus diesem Anteil wird zurückgerechnet, wie viel Eingangsware hinter einer Lieferung '
             + 'steckt. Ein Fehler hier verschiebt die gesamte Bilanz zwischen „ausgeliefert" und „im Haus".',
        beleg: 'pruefwerk/sonden/04_orakel.mjs → anteil()',
        groesse: { wert: Number((anteilAbw.max * 100).toFixed(4)), einheit: '% Abweichung', basis: 'Demosaison' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }
  if (m0Abw.max > 1e-4) {
    B({ klasse: 3, ort: { sicht: 'mv_kaskade', spalte: 'm0' },
        titel: 'Die Eingangsmasse hinter einer Lieferung ist nicht geliefert ÷ Anteil',
        steht_da: `${m0Abw.ist.toFixed(2)} kg`, muesste: `${m0Abw.soll.toFixed(2)} kg`,
        warum: 'Die Rückrechnung ist die einzige Brücke von der Lieferung zur Eingangsware. '
             + 'Stimmt sie nicht, stimmt „noch im Haus" nicht.',
        beleg: 'pruefwerk/sonden/04_orakel.mjs → 4b',
        groesse: { wert: Number(Math.abs(m0Abw.soll - m0Abw.ist).toFixed(1)), einheit: 'kg',
                   basis: `Charge ${m0Abw.q.charge_nr}` },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* 4c. Der Boden bei 25 % — sitzt er, ist die Rückrechnung still falsch */
  if (amBoden.length) {
    const kg = amBoden.reduce((s, x) => s + z(x.q.geliefert) * (1 / x.roh - 1 / 0.25), 0)
    B({ klasse: 3, ort: { sicht: 'mv_kaskade', spalte: 'verkaufsfaehig_anteil' },
        titel: 'Der Boden bei 25 % greift — die Rückrechnung gibt die Lieferung nicht mehr her',
        steht_da: `${amBoden.length} Portionen mit einem rohen Anteil unter 0,25 `
                + `(kleinster ${Math.min(...amBoden.map(x => x.roh)).toFixed(3)}).`,
        muesste: 'Entweder ohne Boden rechnen und die Portion als „unbrauchbar" kennzeichnen, '
               + 'oder mit Boden rechnen und die Lieferung als nicht rückrechenbar melden — aber nicht '
               + 'stillschweigend eine Zahl liefern, die die eigene Lieferung nicht wiedergibt.',
        warum: 'Der Boden verhindert eine Division durch fast null. Er bewirkt aber auch, dass '
             + '`verkaufsfaehig_kg` kleiner ist als `geliefert_kg` — die Kaskade behauptet dann, es sei '
             + 'weniger ausgeliefert worden, als der Lieferschein sagt.',
        beleg: 'pruefwerk/sonden/04_orakel.mjs → 4c',
        groesse: { wert: Math.round(Math.abs(kg)), einheit: 'kg fehlende Eingangsmasse', basis: 'Demosaison' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* 4d. Die Ableitungen für die Fehlerfortpflanzung, numerisch nachgeprüft */
  let dR = { max: 0 }, dF = { max: 0 }
  const h = 1e-7
  for (const q of zeilen) {
    const m0 = z(q.m0), r = z(q.r), t = z(q.alter_tage)
    const num = (m0 * Math.pow(1 - (r + h), t) - m0 * Math.pow(1 - (r - h), t)) / (2 * h)
    const d = Math.abs(num - z(q.d_m1_r)) / Math.max(Math.abs(num), 1)
    if (d > dR.max) dR = { max: d, q, num, ist: z(q.d_m1_r) }
    if (q.modell_gilt === true || q.modell_gilt === 't') {
      // η aus f zurückgewonnen: f = 1 − exp(−exp(η))  ⇒  η = ln(−ln(1−f))
      const f = z(q.f)
      if (f > 0 && f < 1) {
        const eta = Math.log(-Math.log(1 - f))
        const g = (e) => 1 - Math.exp(-Math.exp(e))
        const num2 = (g(eta + h) - g(eta - h)) / (2 * h)
        const d2 = Math.abs(num2 - z(q.d_f_eta)) / Math.max(Math.abs(num2), 1e-9)
        if (d2 > dF.max) dF = { max: d2, q, num: num2, ist: z(q.d_f_eta) }
      }
    }
  }
  for (const [name, a, spalte, wozu] of [
    ['∂m1/∂r', dR, 'd_m1_r', 'die Unsicherheit der Verdunstungsrate'],
    ['∂f/∂η', dF, 'd_f_eta', 'die Unsicherheit des Verderbsmodells']]) {
    if (a.max <= 1e-4) continue
    B({ klasse: 2, ort: { sicht: 'mv_kaskade', spalte },
        titel: `Die Ableitung ${name} stimmt nicht mit der Steigung überein`,
        steht_da: `${a.ist.toPrecision(6)} bei Charge ${a.q.charge_nr}, t=${a.q.alter_tage}`,
        muesste: `${a.num.toPrecision(6)} (zentraler Differenzenquotient, h=${h})`,
        warum: `Über diese Ableitung wird ${wozu} in den Bereich („Bereich x–y t") fortgepflanzt. `
             + 'Ist sie falsch, ist der angezeigte Bereich falsch — die Mittelwerte bleiben richtig, '
             + 'und deshalb fällt es nie auf.',
        beleg: 'pruefwerk/sonden/04_orakel.mjs → 4d',
        groesse: { wert: Number((a.max * 100).toFixed(3)), einheit: '% Abweichung', basis: 'Demosaison' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* 4e. Das Verderbsmodell selbst */
  const m = frage(db, `select ln_lambda_korrigiert::float8 as lnl, k::float8 as k,
                              t_max::float8 as t_max, brauchbar from v_schimmel_modell`)[0]
  if (m?.brauchbar === true || m?.brauchbar === 't') {
    let fAbw = { max: 0 }
    for (const q of zeilen.filter(q => q.modell_gilt === true || q.modell_gilt === 't')) {
      const s = fModell({ lnLambda: z(m.lnl), k: z(m.k), t: z(q.alter_tage) })
      const d = Math.abs(s.f - z(q.f))
      if (d > fAbw.max) fAbw = { max: d, q, soll: s.f, ist: z(q.f), eta: s.eta }
    }
    if (fAbw.max > 1e-9) {
      B({ klasse: 3, ort: { sicht: 'mv_kaskade', spalte: 'f' },
          titel: 'Der Verderbsanteil f folgt nicht der Modellformel',
          steht_da: `f = ${fAbw.ist.toFixed(8)} bei t = ${fAbw.q.alter_tage}`,
          muesste: `f = ${fAbw.soll.toFixed(8)} aus 1 − exp(−exp(${fAbw.eta.toFixed(5)}))`,
          warum: 'f bestimmt, wie viel der liegenden Ware als faul gilt — die grösste Einzelursache.',
          beleg: 'pruefwerk/sonden/04_orakel.mjs → fModell()',
          groesse: { wert: Number((fAbw.max * 100).toFixed(4)), einheit: 'Prozentpunkte auf f', basis: 'Demosaison' },
          sicherheit: 'hoch', marke: 'Reparatur' })
    }
    /* 4f. Wie weit reicht das Modell wirklich? */
    const drueber = zeilen.filter(q => z(q.alter_tage) > z(m.t_max))
    if (drueber.length) {
      const masse = drueber.reduce((s, q) => s + z(q.schimmel) + z(q.sockel), 0)
      const ohneMarke = drueber.filter(q => !(q.f_extrapoliert === true || q.f_extrapoliert === 't'))
      if (ohneMarke.length) {
        B({ klasse: 2, ort: { sicht: 'mv_kaskade', spalte: 'f_extrapoliert' },
            titel: 'Verlängertes Modell ohne Kennzeichen',
            steht_da: `${ohneMarke.length} Portionen liegen länger als die längste Messung `
                    + `(${z(m.t_max).toFixed(0)} Tage), tragen aber f_extrapoliert = falsch.`,
            muesste: 'Jede Portion jenseits der Messungen muss das Kennzeichen tragen.',
            warum: 'Das Kennzeichen ist die einzige Stelle, an der die Oberfläche erkennen kann, '
                 + 'dass eine Zahl aus einer Verlängerung stammt und nicht aus Messungen.',
            beleg: 'pruefwerk/sonden/04_orakel.mjs → 4f',
            groesse: { wert: Math.round(masse), einheit: 'kg Faules jenseits der Messungen', basis: 'Demosaison' },
            sicherheit: 'hoch', marke: 'Reparatur' })
      }
    }
  }

  /* 4g. Wie weit sind die Schutzgrenzen entfernt?
     Drei Stellen der Kaskade sind Vorkehrungen für den Ausnahmefall: der Boden
     des verkaufsfähigen Anteils bei 25 %, der Deckel der Verdunstungsrate bei
     5 % je Tag, der Sockel a₀. Die Mutationssonde (06) findet sie auf den
     Demodaten „ohne Wirkung" — sie sind so weit weg, dass eine Verstellung
     keine Zahl ändert. Das ist kein Freispruch, sondern ein Abstand, und ein
     Abstand gehört gemessen: solange er gross ist, ist die Stelle ungeprüft
     und ungefährlich; wird er klein, ist sie ungeprüft und gefährlich. */
  const anteile = zeilen.map(q => anteil({ r: z(q.r), t: z(q.alter_tage), a0: z(q.a0), f: z(q.f),
                                           klein: z(q.klein), gross: z(q.gross), fax: z(q.fax) }).roh)
  const kleinster = Math.min(...anteile)
  const groessteRate = Math.max(...zeilen.map(q => z(q.r)))
  const groessterSockel = Math.max(...zeilen.map(q => z(q.a0)))
  const knapp = kleinster < 0.35 || groessteRate > 0.03 || groessterSockel > 0
  B({ klasse: knapp ? 2 : 1, ort: { sicht: 'mv_kaskade' },
      titel: knapp
        ? 'Eine Schutzgrenze der Kaskade rückt in Reichweite'
        : 'Gemessen: die drei Schutzgrenzen der Kaskade sind weit entfernt — und darum ungeprüft',
      steht_da: `Kleinster verkaufsfähiger Anteil ${kleinster.toFixed(3)} (Boden bei 0,250). `
              + `Grösste Verdunstungsrate ${(100 * groessteRate).toFixed(3)} % je Tag (Deckel bei 5 %). `
              + `Grösster Sockel a₀ ${(100 * groessterSockel).toFixed(2)} % `
              + `(${groessterSockel > 0 ? 'nachgewiesen' : 'nicht nachweisbar, also 0'}).`,
      muesste: knapp
        ? 'Solange eine Grenze in Reichweite ist, gehört sie geprüft: ein Papierfall, der sie ansteuert, '
        + 'und eine Behauptung, die das erwartete Verhalten festhält.'
        : 'Nichts — die Zahlen sind die Auskunft. Sie stehen hier, damit der Abstand nicht unbemerkt '
        + 'kleiner wird.',
      warum: 'Der Boden bei 25 % verhindert eine Division durch fast null, wenn eine Sorte sehr schlecht '
           + 'hält; der Deckel bei 5 % je Tag fängt einen Zahlendreher in einer Wägung ab; der Sockel '
           + 'trennt Feldschäden von Lagerschäden. Alle drei wirken nur im Ausnahmefall — und genau der '
           + 'kommt in den Demodaten nicht vor. Eine Verstellung an ihnen bleibt deshalb unbemerkt, ohne '
           + 'dass es an den Prüfungen läge.',
      beleg: 'pruefwerk/sonden/04_orakel.mjs → 4g; Gegenstück zu MUT-001 in Sonde 06',
      groesse: { wert: Number((kleinster - 0.25).toFixed(3)), einheit: 'Abstand des kleinsten Anteils zum Boden',
                 basis: `${zeilen.length} Portionen` },
      sicherheit: 'hoch', marke: knapp ? 'Reparatur' : 'kein Fehler' })

  return raus
}

/**
 * Selbstprobe — in zwei Stufen.
 *
 * Erst rechnet das Orakel gegen sich selbst: Erhält die Kaskade die Masse,
 * fällt ein bekannter Abschreibfehler auf, trifft das Modell seinen bekannten
 * Wert. Das prüft die Formeln.
 *
 * Dann, und das ist der Teil, der zählt: Auf einer Kopie der Demodaten wird
 * `mv_kaskade` durch eine Tabelle ersetzt, in der genau ein Term verstellt ist
 * (`zu klein` von m1 statt von m2 gerechnet). Findet der volle Lauf diesen
 * Fehler nicht, ist die Sonde stumpf — und dann sagt auch ihr leerer Befund
 * auf den echten Daten nichts.
 */
export async function selbstprobe({ db = 'demo' } = {}) {
  const e = { m0: 1000, r: 0.001, t: 100, a0: 0.05, f: 0.2, klein: 0.03, gross: 0.02, fax: 0.01 }
  const richtig = kaskade(e)
  const summe = richtig.verdunstung + richtig.sockel + richtig.schimmel + richtig.klein
              + richtig.nebenkanal + richtig.fax + richtig.verkaufsfaehig
  if (Math.abs(summe - e.m0) > 1e-9) return false               // Masse bleibt erhalten
  if (Math.abs(e.m0 * e.a0 - richtig.sockel) < 1e-6) return false // Sockel auf m0 wäre etwas anderes
  const a = anteil(e)
  if (a.amBoden) return false
  const zurueck = kaskade({ ...e, m0: richtig.verkaufsfaehig / a.gedeckelt })
  if (Math.abs(zurueck.verkaufsfaehig - richtig.verkaufsfaehig) > 1e-6) return false
  const fm = fModell({ lnLambda: 0, k: 0, t: 50 })
  if (Math.abs(fm.f - (1 - Math.exp(-1))) > 1e-12) return false  // η = 0 ⇒ f = 1 − e⁻¹

  // Der scharfe Teil: ein verstellter Term in einer Kopie der echten Daten.
  const probe = kopie(db, 'pw_orakel_probe')
  tue(probe, `create table pw_ersatz as select * from mv_kaskade;
              update pw_ersatz set klein_kg = m1 * a_klein_n;
              drop materialized view mv_kaskade cascade;
              alter table pw_ersatz rename to mv_kaskade;`)
  const gefunden = await laufen({ db: probe })
  return gefunden.some(b => b.titel.includes('klein'))
}
