/**
 * Kleine Saisons bauen, deren richtiges Ergebnis auf Papier ausrechenbar ist.
 *
 * Der Sinn: Die Demodaten sind brav. Sie haben zu jeder Sorte Messungen, zu
 * jeder Charge Lieferungen, nirgends eine fehlende Tara. Ein Prüfwerk, das
 * nur auf ihnen läuft, prüft den Schönwetterfall — und genau dort sitzt kein
 * Fehler, weil dort jeder hinschaut.
 *
 * Hier wird deshalb gebaut, was weh tut. Und zwar so klein, dass man das
 * Sollergebnis von Hand hinschreiben kann: drei Paletten, eine Lieferung,
 * bekannte Tara. Wo die App davon abweicht, ist es kein Interpretationsspiel.
 */
import { frischesSchema, rechne, tue } from './umgebung.mjs'

export const SORTE = 'Prüfkürbis'
export const SCHLAG = 'Prüfschlag'
export const CHARGE = 9001
export const HEUTE = '2026-09-01'
export const CHEF = '11111111-1111-1111-1111-111111111111'

/**
 * Das Gerüst: eine Sorte mit Kaliberbändern, eine Gebindeart mit bekannter
 * Tara, eine Charge. Alles Weitere legt der einzelne Fall dazu.
 *
 *   Kiste 1.0 kg, Palette 20 kg  →  Netto = Brutto − Kisten·1 − 20
 */
export function geruest(db, { tara_kiste = 1.0, tara_palette = 20.0, heute = HEUTE } = {}) {
  frischesSchema(db)
  tue(db, `
    insert into einstellung (schluessel, wert) values
      ('heute_test', to_jsonb('${heute}'::text)),
      ('saison_ende', to_jsonb('2027-03-31'::text))
    on conflict (schluessel) do update set wert = excluded.wert;

    insert into sorte_kaliber (sorte, verlust_unter, kaliber_baender, kanal_ab)
    values ('${SORTE}', 300, '[[300,800],[800,2000]]'::jsonb, 2000)
    on conflict (sorte) do nothing;

    insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette)
    values ('P', ${tara_kiste === null ? 'null' : tara_kiste}, ${tara_palette === null ? 'null' : tara_palette})
    on conflict (art) do update set tara_kg_pro_kiste = excluded.tara_kg_pro_kiste,
                                    tara_kg_palette   = excluded.tara_kg_palette;

    insert into charge (nr, schlag, sorte, saison)
    values (${CHARGE}, '${SCHLAG}', '${SORTE}', 2026)
    on conflict (nr) do nothing;`)
  return db
}

/** Eingangspaletten: [{ datum, brutto, kisten, art }] */
export function paletten(db, liste) {
  const werte = liste.map(p =>
    `(${CHARGE}, '${p.datum}', ${p.brutto}, ${p.kisten ?? 'null'}, ${p.art === null ? 'null' : `'${p.art ?? 'P'}'`}, 'test')`).join(',\n')
  tue(db, `insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, quelle)
           values ${werte}`)
}

/** Lieferungen: [{ datum, kg, ziel }] — ziel aus ausgang_ziel (verkauf, tierfutter, kompost …) */
export function lieferungen(db, liste) {
  const werte = liste.map(l =>
    `('${l.datum}', ${l.charge ?? CHARGE}, '${SORTE}', ${l.kg}, '${l.ziel ?? 'verkauf'}', '${CHEF}')`).join(',\n')
  tue(db, `insert into lieferung (datum, charge_nr, sorte, kg, ziel, erfasser)
           values ${werte}`)
}

/**
 * Der Papierfall.
 *
 *   3 Paletten à 1000 kg brutto, 30 Kisten, Gebinde P
 *   Netto je Palette = 1000 − 30·1 − 20 = 950  →  Eingang 2850 kg
 *   1 Lieferung 950 kg
 *   keine Messungen — also kein Koeffizient bekannt
 *
 * Erwartung, von Hand: Eingang 2850. Da nichts gemessen ist, ist jeder
 * Koeffizient unbekannt; die verkaufsfähige Ausbeute ist damit 1, hinter der
 * Lieferung stecken 950 kg Eingang, und im Haus liegen 1900 kg. Der Verlust
 * ist **nicht null, sondern unbekannt** — das ist der Punkt dieses Falls.
 */
export function papierfall(db, { heute = HEUTE } = {}) {
  geruest(db, { heute })
  paletten(db, [
    { datum: '2026-06-01', brutto: 1000, kisten: 30 },
    { datum: '2026-06-01', brutto: 1000, kisten: 30 },
    { datum: '2026-06-01', brutto: 1000, kisten: 30 },
  ])
  lieferungen(db, [{ datum: '2026-08-01', kg: 950 }])
  rechne(db)
  return {
    eingang: 2850, geliefert: 950, imHaus: 1900,
    erklaerung: '3 × (1000 − 30·1 − 20) = 2850 kg Eingang; eine Lieferung 950 kg; '
              + 'kein Koeffizient gemessen, also Ausbeute 1 und 1900 kg im Haus.',
  }
}
