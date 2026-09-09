/**
 * Sonde 07 — Praxisszenarien
 *
 * Kleine Saisons, deren richtiges Ergebnis auf Papier steht, und Störfälle
 * aus `docs/ABLAUF.md`. Auf jede werden zusätzlich die Invarianten aus
 * `invarianten.mjs` losgelassen — dieselben Regeln wie auf die Demodaten,
 * nur in einer Welt, die absichtlich schiefliegt.
 *
 * Warum das nötig ist: Die Demodaten haben zu jeder Sorte Messungen, zu jeder
 * Charge Lieferungen und nirgends eine fehlende Tara. Sie prüfen den
 * Schönwetterfall. Fehler wohnen aber dort, wo etwas fehlt.
 */
import { befund, frage, tue, wert } from '../umgebung.mjs'
import * as inv from '../invarianten.mjs'
import { CHARGE, CHEF, HEUTE, SORTE, geruest, lieferungen, paletten, papierfall } from '../saison.mjs'
import { rechne } from '../umgebung.mjs'

export const lang = false

const bilanz = (db) => frage(db, `
  select eingang_kg::numeric as eingang, geliefert_kg::numeric as geliefert,
         im_haus_heute_kg::numeric as im_haus, verlust_heute_kg::numeric as verlust,
         verlust_bekannt, bilanz_rest_kg::numeric as rest, ausgang_kg::numeric as ausgang,
         ueberzaehlung_kg::numeric as ueberzaehlung, entsorgt_kg::numeric as entsorgt,
         n_chargen from v_saisonbilanz`)[0]

const auffaelligkeiten = (db) => frage(db, `select art, befund from v_plausibilitaet order by art`)

/** Eine Arbeit mit gezählten Paletten, die ihr Gewicht vom Zettel tragen. */
function arbeitMitZettel(db, zettel) {
  tue(db, `insert into auftrag (weg, station, charge_nr, eroeffnet_von, start_ts, status, ende_ts)
           values ('hand', 'waschen_sortieren', ${CHARGE}, '${CHEF}', '${HEUTE} 07:00+00', 'abgeschlossen', '${HEUTE} 12:00+00')`)
  const id = wert(db, `select max(id) from auftrag`)
  const werte = zettel.map(z => `(${id}, '${z.datum}', ${z.brutto}, '${CHEF}')`).join(',')
  tue(db, `insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg, erfasser)
           values ${werte}`)
  return id
}

export async function laufen() {
  const raus = []
  const B = (o) => raus.push(befund({ sonde: '07_szenarien', kuerzel: 'SZE', ...o }))

  /* ---- S1: Der Papierfall ---------------------------------------------- */
  const soll = papierfall('pw_s1')
  const b1 = bilanz('pw_s1')
  const abw = [['Eingang', soll.eingang, Number(b1.eingang)],
               ['geliefert', soll.geliefert, Number(b1.geliefert)],
               ['im Haus', soll.imHaus, Number(b1.im_haus)]]
    .filter(([, s, i]) => Math.abs(s - i) > 0.01)
  if (abw.length) {
    B({ klasse: 3, ort: { sicht: 'v_saisonbilanz' },
        titel: 'Der Papierfall geht nicht auf',
        steht_da: abw.map(([n, s, i]) => `${n}: erwartet ${s}, ist ${i}`).join('; '),
        muesste: soll.erklaerung,
        warum: 'Wenn eine Saison mit drei Paletten und einer Lieferung nicht stimmt, stimmt keine.',
        beleg: 'pruefwerk/saison.mjs → papierfall()',
        groesse: { wert: Math.max(...abw.map(([, s, i]) => Math.abs(s - i))), einheit: 'kg', basis: 'Papierfall' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  // Der eigentliche Fund dieses Falls: nichts gemessen, Verlust trotzdem eine
  // Zahl. `Number(null)` ist 0 — deshalb wird hier auf NULL geprüft, nicht auf
  // die Null; sonst schlägt die Sonde auch dann an, wenn alles stimmt.
  if (b1.verlust !== null && b1.verlust_bekannt === false) {
    B({ klasse: 3, ort: { sicht: 'v_hochrechnung_basis', spalte: 'verlust_heute_kg' },
        titel: 'Ohne jede Messung steht „Verlust bis heute: 0 kg" statt „unbekannt"',
        steht_da: 'verlust_heute_kg = 0, verlust_bekannt = false — auf dem Überblick: „0,0 t · 0 % des Eingangs"',
        muesste: 'Ist kein Koeffizient gemessen, ist der Verlust unbekannt. Eine leere Zahl sagt das; eine 0 behauptet eine Messung.',
        warum: 'mv_kaskade rechnet mit coalesce(koeffizient, 0); v_hochrechnung_basis summiert diese Nullen. '
             + 'Der Grundsatz des Projekts heisst „Leer ist nicht null" — hier ist er auf der untersten Ebene '
             + 'verletzt. Ein Betrieb, der die App neu einrichtet und noch nichts gemessen hat, liest: '
             + 'kein Verlust. Das ist die gefährlichste Zahl von allen, weil sie beruhigt.',
        beleg: 'pruefwerk/saison.mjs → papierfall(): 2850 kg Eingang, keine Messung, Verlust 0',
        groesse: { wert: 2850, einheit: 'kg Eingang ohne jede Verlustaussage', basis: 'Papierfall' },
        sicherheit: 'hoch', marke: 'Entscheidung des Betriebs', aufwand: 'mittel',
        gegenrede: 'Daneben steht `verlust_bekannt = false`, und der Überblick zeigt eine Warnung, welche '
                 + 'Ursache nicht gemessen ist. Man könnte argumentieren, die Zahl sei ausgewiesen. Sie wird '
                 + 'aber summiert, in Prozent gesetzt und in Grafiken gezeichnet, als wäre sie eine Messung.' })
  }

  /* ---- S2: Gebindeart ohne hinterlegte Tara ----------------------------- */
  geruest('pw_s2', { tara_kiste: null })
  paletten('pw_s2', [{ datum: '2026-06-01', brutto: 1000, kisten: 30 },
                     { datum: '2026-06-01', brutto: 1000, kisten: 30 }])
  rechne('pw_s2')
  const b2 = bilanz('pw_s2')
  const auf2 = auffaelligkeiten('pw_s2')
  B({ klasse: Number(b2?.eingang ?? 0) === 0 && !auf2.length ? 3 : 0,
      ort: { sicht: 'v_palette', spalte: 'netto_kg' },
      titel: 'Gebindeart ohne Tara: der Eingang verschwindet, und niemand sagt es',
      steht_da: `2 Paletten à 1000 kg brutto, Tara unbekannt → Eingang ${Number(b2?.eingang ?? 0)} kg, `
              + `${b2?.n_chargen ?? 0} Chargen in der Bilanz, ${auf2.length} Auffälligkeiten`,
      muesste: 'Entweder eine Auffälligkeit „Tara fehlt" mit der Zahl der betroffenen Paletten, oder der Eingang trägt „unvollständig".',
      warum: 'v_palette.netto_kg wird NULL, und sum() überspringt die Zeile still. Der Eingang ist dann '
           + 'kleiner als die Wirklichkeit, trägt aber die Marke „gemessen" — und alle Prozentwerte, deren '
           + 'Nenner er ist, sind zu gross.',
      beleg: 'pruefwerk/sonden/07_szenarien.mjs → S2',
      groesse: { wert: 2000, einheit: 'kg brutto, die aus der Bilanz fallen', basis: 'Störfall S2' },
      sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein' })

  /* ---- S3/S4: Zettelgewicht — an welche Palette knüpft es an? ----------- */
  // Zwei Paletten derselben Charge, gleiches Brutto, verschiedene Eingangstage.
  // Der Zettel nennt Gewicht und Tag der zweiten. Die Massenrechnung verlangt
  // Charge + Tag + Brutto; die Auffälligkeit prüft nur Charge + Brutto.
  geruest('pw_s3')
  paletten('pw_s3', [
    { datum: '2026-06-01', brutto: 1000, kisten: 30 },   // netto 950
    { datum: '2026-07-01', brutto: 1000, kisten: 20 },   // netto 960 — anderer Tag, andere Kistenzahl
  ])
  arbeitMitZettel('pw_s3', [{ datum: '2026-07-01', brutto: 1000 }])
  rechne('pw_s3')
  const q3 = frage('pw_s3', `select masse_quelle, round(netto_kg,2)::numeric as netto,
                                    eingangsdatum::text as datum from v_auftrag_palette_masse`)
  const auf3 = auffaelligkeiten('pw_s3').filter(a => a.art === 'Zettelgewicht')
  if (q3.length) {
    const g = q3[0]
    const richtig = 960   // die Palette vom 1. Juli hat 20 Kisten → 1000 − 20 − 20
    if (Math.abs(Number(g.netto) - richtig) > 0.01 || g.masse_quelle !== 'zettel') {
      B({ klasse: 3, ort: { sicht: 'v_auftrag_palette_masse', spalte: 'netto_kg' },
          titel: 'Zettelgewicht knüpft an die falsche Palette an, wenn zwei dasselbe Brutto haben',
          steht_da: `Quelle „${g.masse_quelle}", Netto ${g.netto} kg (Zettel: 1000 kg vom ${g.datum})`,
          muesste: `${richtig} kg — die Palette vom 1. Juli hat 20 Kisten, nicht 30.`,
          warum: 'Der Verweis geht über (Charge, Eingangsdatum, Brutto). Haben zwei Paletten dasselbe '
               + 'Brutto, entscheidet `order by p.id limit 1` — also der Zufall der Einfügereihenfolge. '
               + 'Zwei Paletten mit gleichem Gewicht sind auf einem Hof, der in 20-kg-Schritten stapelt, '
               + 'nicht selten.',
          beleg: 'pruefwerk/sonden/07_szenarien.mjs → S3',
          groesse: { wert: Math.abs(Number(g.netto) - richtig), einheit: 'kg je betroffener Palette', basis: 'Störfall S3' },
          sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein' })
    }
  }

  // S4: Zettelgewicht, das es in der Charge gibt — aber an einem anderen Tag.
  geruest('pw_s4')
  paletten('pw_s4', [{ datum: '2026-06-01', brutto: 1000, kisten: 30 }])
  arbeitMitZettel('pw_s4', [{ datum: '2026-07-15', brutto: 1000 }])   // Tag passt nicht
  rechne('pw_s4')
  const q4 = frage('pw_s4', `select masse_quelle, round(netto_kg,2)::numeric as netto from v_auftrag_palette_masse`)[0]
  const auf4 = auffaelligkeiten('pw_s4').filter(a => a.art === 'Zettelgewicht')
  if (q4 && q4.masse_quelle !== 'zettel' && auf4.length === 0) {
    B({ klasse: 3, ort: { sicht: 'v_plausibilitaet', spalte: "art = 'Zettelgewicht'" },
        titel: 'Genähert ohne Auffälligkeit: das Zettelgewicht passt zur Charge, aber nicht zum Tag',
        steht_da: `Masse aus „${q4.masse_quelle}" (${q4.netto} kg), Auffälligkeiten „Zettelgewicht": ${auf4.length}`,
        muesste: 'Wo die Massenrechnung auf die mittlere Tara ausweicht, muss die Auffälligkeit feuern.',
        warum: 'Die Massenrechnung verlangt Charge **und Eingangsdatum und Brutto**; die Auffälligkeit prüft '
             + 'nur Charge und Brutto. Fällt ein Fall dazwischen — Zahlendreher im Datum, Palette an einem '
             + 'anderen Tag eingelagert —, rechnet die App mit der mittleren Tara der Charge, und niemand '
             + 'erfährt es. Genau die Näherung, die AB-26 sichtbar machen wollte, wird hier unsichtbar.',
        beleg: 'pruefwerk/sonden/07_szenarien.mjs → S4',
        groesse: { wert: 1, einheit: 'stille Näherung je betroffener Palette', basis: 'Störfall S4' },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein' })
  }

  /* ---- S5: Lieferung in den Kompost ------------------------------------ */
  geruest('pw_s5')
  paletten('pw_s5', [{ datum: '2026-06-01', brutto: 1000, kisten: 30 },
                     { datum: '2026-06-01', brutto: 1000, kisten: 30 }])
  lieferungen('pw_s5', [{ datum: '2026-08-01', kg: 500, ziel: 'kompost' }])
  rechne('pw_s5')
  const b5 = bilanz('pw_s5')
  if (Number(b5.im_haus) > 1899) {   // 1900 = Eingang, also nichts abgezogen
    B({ klasse: 3, ort: { sicht: 'v_lieferung_kohorte' },
        titel: 'Entsorgte Ware verlässt den Betrieb, liegt aber rechnerisch weiter im Lager',
        steht_da: `Eingang ${b5.eingang} kg, 500 kg in den Kompost geliefert, „noch im Haus" ${b5.im_haus} kg, `
                + `Verlust ${b5.verlust} kg, Ausgang ${b5.ausgang} kg`,
        muesste: 'Kompost ist echter Verlust: er muss den Bestand verringern und im Verlust erscheinen.',
        warum: 'v_lieferung_kohorte filtert auf buch in (verkauf, marge) — das dritte Buch fehlt. '
             + 'v_saisonbilanz zählt die Lieferung aber in ausgang_kg. Die Masse ist damit gleichzeitig '
             + 'draussen und drin: sie altert weiter, verdunstet weiter und erscheint bis in alle Ewigkeit '
             + 'als Bestand. Dieselbe Fehlerart, die 0062 für die Marge behoben hat — für das dritte Buch '
             + 'blieb sie stehen.',
        beleg: 'pruefwerk/sonden/07_szenarien.mjs → S5',
        groesse: { wert: 500, einheit: 'kg, die doppelt zählen (Ausgang und Bestand)', basis: 'Störfall S5' },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein' })
  }

  /* ---- S6: Lieferung ohne Wareneingang ---------------------------------- */
  geruest('pw_s6')
  lieferungen('pw_s6', [{ datum: '2026-08-01', kg: 500 }])
  rechne('pw_s6')
  const auf6 = auffaelligkeiten('pw_s6')
  const b6 = bilanz('pw_s6')
  if (!auf6.some(a => /Lieferung ohne Eingang/.test(a.art))) {
    B({ klasse: 2, ort: { sicht: 'v_plausibilitaet' },
        titel: 'Lieferung an eine Charge ohne Wareneingang fällt nicht auf',
        steht_da: `${auf6.length} Auffälligkeiten, Eingang ${b6?.eingang ?? 0}, Ausgang ${b6?.ausgang ?? 0}`,
        muesste: 'Eine Lieferung, zu der es keinen Wareneingang gibt, muss genannt werden.',
        warum: 'Sonst verschwindet sie aus der Kaskade und die Bilanz stimmt scheinbar.',
        beleg: 'pruefwerk/sonden/07_szenarien.mjs → S6',
        groesse: { wert: 500, einheit: 'kg ohne Gegenstück', basis: 'Störfall S6' },
        sicherheit: 'mittel', marke: 'Reparatur' })
  }

  /* ---- S7: Palette umgestapelt — die Verdunstungsrate erbt die Tara ----- */
  // Eingang: 30 Kisten. Bei der Wägung stehen nur noch 25 darauf (umgestapelt).
  // Der Arbeiter tippt, was er sieht: 25. Beide Bruttos bekommen dieselbe Tara.
  geruest('pw_s7')
  paletten('pw_s7', [{ datum: '2026-06-01', brutto: 1000, kisten: 30 }])
  tue('pw_s7', `insert into verdunstung_wiegung
                  (charge_nr, eingangsdatum, wiege_ts, brutto_damals_kg, brutto_jetzt_kg,
                   kisten, gebindeart, erfasser, gemessen)
                values (${CHARGE}, '2026-06-01', '${HEUTE} 08:00+00', 1000, 950, 25, 'P', '${CHEF}', true)`)
  rechne('pw_s7')
  const r7 = frage('pw_s7', `select round(rate_pro_tag, 6)::numeric as rate, lagertage,
                                    round(netto_damals_kg,1)::numeric as damals,
                                    round(netto_jetzt_kg,1)::numeric as jetzt, verwendbar
                               from v_verdunstung_messung`)[0]
  if (r7) {
    // Wahr: 30 Kisten beim Eingang → netto damals 1000−30−20 = 950; jetzt 25 Kisten → 950−25−20 = 905.
    const wahr = 1 - Math.pow(905 / 950, 1 / Number(r7.lagertage))
    const gemessen = Number(r7.rate)
    if (Math.abs(gemessen - wahr) > wahr * 0.05) {
      B({ klasse: 3, ort: { sicht: 'v_verdunstung_messung', spalte: 'rate_pro_tag' },
          titel: 'Wird eine Palette umgestapelt, steckt die Tara-Differenz in der Verdunstungsrate',
          steht_da: `gemessene Rate ${gemessen.toFixed(6)}/Tag (netto damals ${r7.damals}, jetzt ${r7.jetzt})`,
          muesste: `${wahr.toFixed(6)}/Tag — beim Eingang standen 30 Kisten auf der Palette, bei der Wägung 25.`,
          warum: 'Die Sicht zieht von `brutto_damals_kg` und `brutto_jetzt_kg` **dieselbe** Tara ab, weil '
               + 'die Kistenzahl nur einmal gefragt wird. Fünf Kisten weniger sind 5 kg, die als '
               + 'Verdunstung gezählt werden. Der Fehler geht mit der Tagesrate potenziert in jede '
               + 'Verdunstungszahl der Sorte ein. ABLAUF.md nennt die Annahme seit Runde K — geprüft wird sie nicht.',
          beleg: 'pruefwerk/sonden/07_szenarien.mjs → S7',
          groesse: { wert: Number((100 * (gemessen / wahr - 1)).toFixed(0)), einheit: '% zu hohe Tagesrate', basis: 'Störfall S7 (5 von 30 Kisten)' },
          sicherheit: 'hoch', marke: 'Entscheidung des Betriebs', aufwand: 'klein',
          gegenrede: 'Vielleicht wird nie umgestapelt. ABLAUF.md sagt aber, die Paletten stehen gestapelt '
                   + 'und man kommt nicht an jede heran — und die Lagerkontrolle empfiehlt ausdrücklich, '
                   + 'beim Öffnen eines Stapels zu greifen. Genau dort wird umgestapelt.' })
    }
  }

  /* ---- S8: Charge vollständig ausgeliefert ------------------------------ */
  /* Eine Palette, alles davon geliefert. Am Ende der Saison ist das der
     Normalfall, nicht der Sonderfall — und in der Demosaison kommt er nicht
     vor, weil überall noch etwas liegt. */
  geruest('pw_s8')
  paletten('pw_s8', [{ datum: '2026-06-01', brutto: 1000, kisten: 30 }])   // netto 950
  lieferungen('pw_s8', [{ datum: '2026-08-01', kg: 950 }])                 // alles raus
  rechne('pw_s8')
  const b8 = bilanz('pw_s8')
  const haus8 = Number(b8.im_haus)
  if (haus8 > 1) {
    B({ klasse: 3, ort: { sicht: 'v_hochrechnung_basis', spalte: 'im_haus_heute_kg, lager_kg' },
        titel: 'Eine vollständig ausgelieferte Charge liegt angeblich noch komplett im Haus',
        steht_da: `Eingang ${Number(b8.eingang).toFixed(0)} kg, ausgeliefert ${Number(b8.geliefert).toFixed(0)} kg, `
                + `„noch im Haus" ${haus8.toFixed(0)} kg. Die Bilanz geht um `
                + `${Number(b8.rest).toFixed(0)} kg nicht auf, und die Auffälligkeiten melden nichts.`,
        muesste: '„Noch im Haus" 0 kg, Bilanzrest 0 kg.',
        warum: 'Die Sicht rechnet `coalesce(k.im_haus_heute_kg, b.eingang_kg)` — gedacht für den Fall, '
             + 'dass es zu einer Charge **gar keine** Kaskadenzeile gibt (dann liegt tatsächlich noch '
             + 'alles). Sie greift aber auch, wenn es Zeilen gibt und nur die Portion „lager" fehlt — '
             + 'und das ist genau der umgekehrte Fall: Es liegt nichts mehr. Dasselbe bei `lager_kg`. '
             + 'Am Saisonende, wenn Charge um Charge leer wird, wird daraus die Regel: Der Bestand '
             + 'zeigt Ware, die längst ausgeliefert ist. Die Bilanz merkt es (der Rest bleibt stehen), '
             + 'aber der Rest steht nur unter Messungen, nicht auf dem Überblick.',
        beleg: 'pruefwerk/sonden/07_szenarien.mjs → S8',
        groesse: { wert: Math.round(haus8), einheit: 'kg zu viel „noch im Haus"',
                   basis: 'eine vollständig ausgelieferte Charge von 950 kg' },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein',
        gegenrede: 'In der Demosaison liegt zu jeder Charge noch etwas, deshalb tritt der Fall dort nie '
                 + 'auf. Das ist kein Gegenargument, sondern der Grund, warum er bisher niemandem '
                 + 'aufgefallen ist: Die Demodaten bilden den Saisonanfang ab, nicht das Ende.' })
  }

  /* ---- Die Invarianten auf jeden Störfall ------------------------------- */
  for (const [name, db] of [['S1 Papierfall', 'pw_s1'], ['S2 ohne Tara', 'pw_s2'],
                            ['S3 gleiches Brutto', 'pw_s3'], ['S5 Kompost', 'pw_s5'],
                            ['S7 umgestapelt', 'pw_s7'], ['S8 alles ausgeliefert', 'pw_s8']]) {
    for (const v of inv.alle(db)) {
      if (v.regel === 'Unwissen') continue                                  // eigener Befund oben
      if (v.regel === 'Bilanz' && name.startsWith('S8')) continue           // desgleichen
      B({ klasse: 3, ort: { sicht: v.regel },
          titel: `Invariante „${v.regel}" verletzt im Störfall ${name}`,
          steht_da: JSON.stringify(v.treffer).slice(0, 300),
          muesste: 'Die Regel gilt unabhängig von den Daten.',
          warum: 'Auf den Demodaten hält sie — im Störfall nicht. Das heisst: Sie hält aus Glück, nicht aus Bau.',
          beleg: `pruefwerk/sonden/07_szenarien.mjs → ${name}`,
          groesse: { wert: v.treffer.length, einheit: 'verletzte Zeilen', basis: name },
          sicherheit: 'hoch', marke: 'Reparatur' })
    }
  }

  return raus.filter(b => b.klasse > 0)
}

/** Selbstprobe: Der Papierfall muss reproduzierbar dieselben Zahlen liefern. */
export async function selbstprobe() {
  const soll = papierfall('pw_probe7')
  const b = bilanz('pw_probe7')
  return Math.abs(Number(b.eingang) - soll.eingang) < 0.01
      && Math.abs(Number(b.im_haus) - soll.imHaus) < 0.01
}
