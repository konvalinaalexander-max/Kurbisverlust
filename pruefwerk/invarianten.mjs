/**
 * Was auf jeder Datenbank gelten muss — egal, welche Daten drinstehen.
 *
 * Diese Prüfungen brauchen kein bekanntes richtiges Ergebnis. Deshalb kann man
 * sie auf die Demodaten loslassen, auf einen selbstgebauten Papierfall und auf
 * eine Zufallssaison gleichermassen. Sonde 05 nimmt die Demodaten, Sonde 07
 * jeden Störfall — dieselben Regeln, andere Welt.
 *
 * Jede Regel gibt zurück, was sie gefunden hat, oder eine leere Liste.
 */
import { frage, wert } from './umgebung.mjs'

/** Die Ströme einer Portion summieren sich zu ihrer Masse. */
export function erhaltung(db) {
  return frage(db, `
    select charge_nr, portion, kohorte::text as kohorte, m0::numeric as m0,
           (verdunstung_kg + sockel_kg + schimmel_kg + klein_kg
            + nebenkanal_kg + fax_kg + verkaufsfaehig_kg)::numeric as summe
      from mv_kaskade
     where m0 > 0
       and abs(m0 - (verdunstung_kg + sockel_kg + schimmel_kg + klein_kg
                     + nebenkanal_kg + fax_kg + verkaufsfaehig_kg)) > greatest(m0 * 1e-6, 0.01)
     order by 1, 2, 3 limit 20`)
}

/** Bei portion = ausgelagert muss die Kaskade die Lieferung wiedergeben. */
export function rueckrechnung(db) {
  return frage(db, `
    select charge_nr, kohorte::text as kohorte, geliefert_kg::numeric as geliefert,
           verkaufsfaehig_kg::numeric as verkaufsfaehig, verkaufsfaehig_anteil::numeric as anteil,
           (verkaufsfaehig_anteil <= 0.2500000001) as am_deckel
      from mv_kaskade
     where portion = 'ausgelagert' and geliefert_kg > 0
       and abs(verkaufsfaehig_kg - geliefert_kg) > greatest(geliefert_kg * 1e-4, 0.05)
     order by abs(verkaufsfaehig_kg - geliefert_kg) desc limit 20`)
}

/** Dieselbe Masse, anders geschnitten: die vier Gruppen müssen gleich summieren. */
export function zerlegung(db) {
  return frage(db, `
    with je as (
      select gruppe, strom, sum(kg) as kg from erg_verlust
       where gruppe in ('gesamt','sorte','schlag','charge') and kg is not null
       group by gruppe, strom)
    select g.strom, g.kg::numeric as gesamt, s.kg::numeric as sorte,
           l.kg::numeric as schlag, c.kg::numeric as charge
      from je g
      left join je s on s.strom = g.strom and s.gruppe = 'sorte'
      left join je l on l.strom = g.strom and l.gruppe = 'schlag'
      left join je c on c.strom = g.strom and c.gruppe = 'charge'
     where g.gruppe = 'gesamt'
       and (abs(coalesce(s.kg,0) - g.kg) > greatest(abs(g.kg)*1e-4, 0.5)
         or abs(coalesce(l.kg,0) - g.kg) > greatest(abs(g.kg)*1e-4, 0.5)
         or abs(coalesce(c.kg,0) - g.kg) > greatest(abs(g.kg)*1e-4, 0.5))`)
}

/** Die Saisonbilanz geht auf. */
export function bilanz(db) {
  const b = frage(db, `select eingang_kg::numeric as eingang, bilanz_rest_kg::numeric as rest,
                              ueberzaehlung_kg::numeric as ueber, entsorgt_kg::numeric as entsorgt,
                              ausgang_kg::numeric as ausgang, geliefert_kg::numeric as geliefert,
                              verlust_heute_kg::numeric as verlust, im_haus_heute_kg::numeric as haus,
                              kanal_ausgelagert_kg::numeric as kanal
                         from v_saisonbilanz`)[0]
  if (!b) return []
  const grenze = Math.max(Number(b.eingang ?? 0) * 1e-5, 1)
  return Math.abs(Number(b.rest ?? 0)) > grenze ? [b] : []
}

/**
 * Unwissen bleibt Unwissen: Ein Strom ohne Messung darf nicht als 0 in eine
 * Summe eingehen, die dann wie eine gemessene Zahl aussieht.
 */
export function unwissen(db) {
  const z = frage(db, `
    select count(*) filter (where not r_bekannt)      as ohne_r,
           count(*) filter (where not f_bekannt)      as ohne_f,
           count(*) filter (where not a0_bekannt)     as ohne_a0,
           count(*) filter (where not a_fax_bekannt)  as ohne_fax,
           count(*) filter (where not a_klein_bekannt) as ohne_klein,
           count(*)                                    as zeilen
      from mv_kaskade`)[0]
  if (!z || Number(z.zeilen) === 0) return []
  const fehlt = Number(z.ohne_r) + Number(z.ohne_f) + Number(z.ohne_a0) + Number(z.ohne_fax)
  if (fehlt === 0) return []
  const b = frage(db, `select verlust_heute_kg::numeric as verlust, verlust_bekannt
                         from v_saisonbilanz`)[0]
  return [{ ...z, verlust: b?.verlust, verlust_bekannt: b?.verlust_bekannt }]
}

/** Zweimal rechnen ergibt dieselben Zahlen. */
export const FINGERABDRUCK = `
  select md5(coalesce(string_agg(z, '|' order by z), '')) as f from (
    select concat_ws(':', charge_nr, round(eingang_kg,2), round(verlust_heute_kg,2),
                     round(im_haus_heute_kg,2), round(geliefert_kg,2)) as z
      from erg_charge) t`
export function fingerabdruck(db) { return wert(db, FINGERABDRUCK) }

/** Alle Regeln auf einmal, als kurze Liste von Verletzungen. */
export function alle(db) {
  const raus = []
  const e = erhaltung(db);      if (e.length) raus.push({ regel: 'Erhaltung', treffer: e })
  const r = rueckrechnung(db);  if (r.length) raus.push({ regel: 'Rückrechnung', treffer: r })
  const z = zerlegung(db);      if (z.length) raus.push({ regel: 'Zerlegung', treffer: z })
  const b = bilanz(db);         if (b.length) raus.push({ regel: 'Bilanz', treffer: b })
  const u = unwissen(db);       if (u.length) raus.push({ regel: 'Unwissen', treffer: u })
  return raus
}
