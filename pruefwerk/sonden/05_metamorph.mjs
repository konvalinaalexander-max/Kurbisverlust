/**
 * Sonde 05 — Metamorphe Beziehungen
 *
 * Es gibt Aussagen, die **unabhängig von den Daten** gelten müssen. Man
 * braucht kein bekanntes richtiges Ergebnis, um sie zu prüfen — nur zwei
 * Läufe oder eine Summe, die aufgehen muss. Das ist der Grund, warum diese
 * Sonde Dinge findet, nach denen niemand gesucht hat: Sie stellt keine Frage
 * über eine bestimmte Zahl, sondern über die Form des ganzen Rechenwerks.
 *
 * Geprüft wird auf einer **Kopie** der Demo-Datenbank. Die Demodaten bleiben
 * unangetastet — eine Sonde, die ihr eigenes Prüfobjekt verändert, ist beim
 * zweiten Lauf wertlos.
 */
import { befund, frage, rechne, tue, wert, url } from '../umgebung.mjs'
import { execFileSync } from 'node:child_process'

export const lang = false

/** Eine Wegwerf-Kopie der Demo-Datenbank. */
function kopie(quelle, ziel) {
  const p = (sql) => execFileSync('psql', [url('postgres'), '-qX', '-c', sql], { encoding: 'utf8' })
  p(`select pg_terminate_backend(pid) from pg_stat_activity where datname in ('${ziel}','${quelle}') and pid <> pg_backend_pid()`)
  p(`drop database if exists ${ziel}`)
  p(`create database ${ziel} template ${quelle}`)
  return ziel
}

export async function laufen({ db }) {
  const raus = []
  const k = kopie(db, 'pw_meta')
  const B = (o) => raus.push(befund({ sonde: '05_metamorph', kuerzel: 'MET', ...o }))

  /* ---- 1. Erhaltung: die Ströme summieren sich zur Portionsmasse -------- */
  // Die Kaskade teilt m0 in sieben Teile. Was nicht aufgeht, ist entweder
  // verloren gegangen oder doppelt gezählt — beides wäre unsichtbar.
  const erh = frage(k, `
    select charge_nr, portion, kohorte,
           m0::numeric as m0,
           (verdunstung_kg + sockel_kg + schimmel_kg + klein_kg
            + nebenkanal_kg + fax_kg + verkaufsfaehig_kg)::numeric as summe
      from mv_kaskade
     where m0 > 0
       and abs(m0 - (verdunstung_kg + sockel_kg + schimmel_kg + klein_kg
                     + nebenkanal_kg + fax_kg + verkaufsfaehig_kg)) > greatest(m0 * 1e-6, 0.01)
     order by abs(m0 - (verdunstung_kg + sockel_kg + schimmel_kg + klein_kg
                        + nebenkanal_kg + fax_kg + verkaufsfaehig_kg)) desc limit 5`)
  if (erh.length) {
    const gr = Math.max(...erh.map(r => Math.abs(r.m0 - r.summe)))
    B({ klasse: 3, ort: { sicht: 'mv_kaskade' },
        titel: 'Die Ströme einer Portion summieren sich nicht zur Portionsmasse',
        steht_da: `${erh.length}+ Zeilen weichen ab, grösste ${gr.toFixed(1)} kg`,
        muesste: 'Verdunstung + Sockel + Schimmel + klein + Nebenkanal + Fax + verkaufsfähig = m0',
        warum: 'Eine Kaskade, die nicht schliesst, hat Masse verloren oder doppelt gezählt.',
        beleg: 'pruefwerk/sonden/05_metamorph.mjs, Abschnitt 1',
        groesse: { wert: Number(gr.toFixed(1)), einheit: 'kg', basis: 'Demodaten, grösste Einzelzeile' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* ---- 2. Ausgelagert: verkaufsfähig muss die Lieferung wiedergeben ----- */
  // m0 der ausgelagerten Portion ist geliefert ÷ verkaufsfähiger Anteil.
  // Also muss am Ende der Kaskade wieder genau die Lieferung stehen. Tut sie
  // es nicht, hat der Deckel greatest(…, 0.25) zugeschlagen — und dann ist
  // die zurückgerechnete Eingangsmasse zu klein, ohne dass es jemand erfährt.
  const rueck = frage(k, `
    select charge_nr, kohorte, geliefert_kg::numeric as geliefert,
           verkaufsfaehig_kg::numeric as verkaufsfaehig,
           verkaufsfaehig_anteil::numeric as anteil
      from mv_kaskade
     where portion = 'ausgelagert' and geliefert_kg > 0
       and abs(verkaufsfaehig_kg - geliefert_kg) > greatest(geliefert_kg * 1e-4, 0.05)
     order by abs(verkaufsfaehig_kg - geliefert_kg) desc`)
  if (rueck.length) {
    const summe = rueck.reduce((s, r) => s + Math.abs(r.geliefert - r.verkaufsfaehig), 0)
    const amDeckel = rueck.filter(r => Math.abs(r.anteil - 0.25) < 1e-9).length
    B({ klasse: 3, ort: { sicht: 'mv_kaskade', spalte: 'verkaufsfaehig_anteil' },
        titel: 'Zurückgerechnete Eingangsmasse gibt die Lieferung nicht wieder (Deckel 0.25)',
        steht_da: `${rueck.length} Kohorten weichen ab, davon ${amDeckel} genau am Deckel`,
        muesste: 'Bei portion = ausgelagert muss verkaufsfaehig_kg = geliefert_kg gelten — m0 wurde genau so bestimmt.',
        warum: 'greatest(…, 0.25) verhindert eine Division durch fast null, bricht dabei aber die '
             + 'Selbstkonsistenz: Die Charge bekommt weniger Eingangsmasse zugerechnet, als hinter der '
             + 'Lieferung steckt. Die Differenz erscheint nirgends.',
        beleg: 'pruefwerk/sonden/05_metamorph.mjs, Abschnitt 2',
        groesse: { wert: Number(summe.toFixed(0)), einheit: 'kg', basis: 'Demodaten, Summe über alle Kohorten' },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'mittel' })
  }

  /* ---- 3. Zerlegung: die Gruppen müssen dieselbe Summe ergeben ---------- */
  const zerl = frage(k, `
    with je as (
      select gruppe, strom, sum(kg) as kg from erg_verlust
       where gruppe in ('gesamt','sorte','schlag','charge') and kg is not null
       group by gruppe, strom)
    select g.strom, g.kg::numeric as gesamt,
           s.kg::numeric as sorte, l.kg::numeric as schlag, c.kg::numeric as charge
      from je g
      left join je s on s.strom = g.strom and s.gruppe = 'sorte'
      left join je l on l.strom = g.strom and l.gruppe = 'schlag'
      left join je c on c.strom = g.strom and c.gruppe = 'charge'
     where g.gruppe = 'gesamt'
       and (abs(coalesce(s.kg,0) - g.kg) > greatest(abs(g.kg)*1e-4, 0.5)
         or abs(coalesce(l.kg,0) - g.kg) > greatest(abs(g.kg)*1e-4, 0.5)
         or abs(coalesce(c.kg,0) - g.kg) > greatest(abs(g.kg)*1e-4, 0.5))`)
  for (const z of zerl) {
    const ab = Math.max(Math.abs((z.sorte ?? 0) - z.gesamt), Math.abs((z.schlag ?? 0) - z.gesamt), Math.abs((z.charge ?? 0) - z.gesamt))
    B({ klasse: 3, ort: { sicht: 'erg_verlust' },
        titel: `Strom „${z.strom}": Summe über die Gruppen weicht vom Gesamtwert ab`,
        steht_da: `gesamt ${Number(z.gesamt).toFixed(0)} · Sorten ${Number(z.sorte ?? 0).toFixed(0)} · `
                + `Schläge ${Number(z.schlag ?? 0).toFixed(0)} · Chargen ${Number(z.charge ?? 0).toFixed(0)} kg`,
        muesste: 'Dieselbe Masse, anders geschnitten — die vier Summen müssen gleich sein.',
        warum: 'Wer im Überblick von „Gesamt" auf „je Sorte" umschaltet, sieht sonst eine andere Menge, '
             + 'ohne dass sich etwas geändert hat.',
        beleg: 'pruefwerk/sonden/05_metamorph.mjs, Abschnitt 3',
        groesse: { wert: Number(ab.toFixed(0)), einheit: 'kg', basis: 'Demodaten' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* ---- 4. Unwissen bleibt Unwissen ------------------------------------- */
  // Ein Koeffizient ohne Messung ist unbekannt, nicht null. In der Kaskade
  // wird er aber mit coalesce(…, 0) zu null — und die Summe verlust_heute_kg
  // ist dann zu klein statt leer.
  const unbek = frage(k, `
    select 'Verdunstung' as strom, count(*) filter (where not r_bekannt) as n,
           sum(verdunstung_kg) filter (where not r_bekannt) as kg from mv_kaskade
    union all select 'Schimmel', count(*) filter (where not f_bekannt),
           sum(schimmel_kg) filter (where not f_bekannt) from mv_kaskade
    union all select 'Sockel', count(*) filter (where not a0_bekannt),
           sum(sockel_kg) filter (where not a0_bekannt) from mv_kaskade
    union all select 'Fax', count(*) filter (where not a_fax_bekannt),
           sum(fax_kg) filter (where not a_fax_bekannt) from mv_kaskade
    union all select 'zu klein', count(*) filter (where not a_klein_bekannt),
           sum(klein_kg) filter (where not a_klein_bekannt) from mv_kaskade`)
  const betroffen = unbek.filter(u => Number(u.n) > 0)
  if (betroffen.length) {
    // Wie viel Masse steht in verlust_heute_kg, obwohl ihr Koeffizient unbekannt ist?
    const stumm = frage(k, `
      select sum(verdunstung_kg) filter (where not r_bekannt)
           + sum(schimmel_kg)    filter (where not f_bekannt)
           + sum(sockel_kg)      filter (where not a0_bekannt)
           + sum(fax_kg)         filter (where not a_fax_bekannt) as kg,
             count(*) filter (where not (r_bekannt and f_bekannt and a0_bekannt and a_fax_bekannt)) as n
        from mv_kaskade`)[0]
    B({ klasse: 3, ort: { sicht: 'mv_kaskade / v_hochrechnung_basis', spalte: 'verlust_heute_kg' },
        titel: 'Ein Strom ohne Messung geht als 0 in den Verlust ein, statt die Zahl unbekannt zu machen',
        steht_da: `${betroffen.map(u => `${u.strom}: ${u.n} Zeilen`).join(', ')} — Beitrag zum Verlust: ${Number(stumm.kg ?? 0).toFixed(0)} kg`,
        muesste: 'Ein unbekannter Koeffizient macht seinen Strom leer, und die Summe darüber trägt „unvollständig".',
        warum: 'mv_kaskade rechnet mit coalesce(koeffizient, 0). v_hochrechnung_basis summiert diese Nullen '
             + 'in verlust_heute_kg. Die Kennzahl ist dann zu klein — nicht leer. `verlust_bekannt` sagt es '
             + 'zwar daneben, aber die Zahl selbst behauptet eine Messung, die es nicht gibt. Das ist genau '
             + 'der Grundsatz „Leer ist nicht null", eine Ebene tiefer verletzt.',
        beleg: 'pruefwerk/sonden/05_metamorph.mjs, Abschnitt 4',
        groesse: { wert: Number(stumm.n), einheit: 'Kaskadenzeilen mit mindestens einem unbekannten Strom', basis: 'Demodaten' },
        sicherheit: 'hoch', marke: 'Entscheidung des Betriebs', aufwand: 'mittel',
        gegenrede: 'Die Marke `verlust_bekannt` steht neben der Zahl, und der Überblick zeigt eine Warnung, '
                 + 'welche Ursache nicht gemessen ist. Man könnte sagen: die Zahl ist als unvollständig '
                 + 'ausgewiesen. Sie wird aber trotzdem summiert, verglichen und in Prozent gesetzt.' })
  }

  /* ---- 5. Die Bilanzgleichung ------------------------------------------ */
  const bil = frage(k, `select eingang_kg::numeric as eingang, ueberzaehlung_kg::numeric as ueber,
                               geliefert_kg::numeric as geliefert, verlust_heute_kg::numeric as verlust,
                               kanal_ausgelagert_kg::numeric as kanal, im_haus_heute_kg::numeric as haus,
                               bilanz_rest_kg::numeric as rest, ausgang_kg::numeric as ausgang,
                               entsorgt_kg::numeric as entsorgt
                          from v_saisonbilanz`)[0]
  if (bil && Math.abs(Number(bil.rest)) > Math.max(Number(bil.eingang) * 1e-5, 1)) {
    B({ klasse: 3, ort: { sicht: 'v_saisonbilanz', spalte: 'bilanz_rest_kg' },
        titel: 'Die Saisonbilanz geht nicht auf',
        steht_da: `Rest ${Number(bil.rest).toFixed(1)} kg bei ${Number(bil.eingang).toFixed(0)} kg Eingang`,
        muesste: 'Eingang + Überzählung = geliefert + Verlust + Kanal + im Haus, bis auf Rundung.',
        warum: 'Ein Rest über der Rundungsgrenze heisst: Masse verschwindet oder entsteht im Modell.',
        beleg: 'select bilanz_rest_kg from v_saisonbilanz',
        groesse: { wert: Number(Number(bil.rest).toFixed(1)), einheit: 'kg', basis: 'Demodaten' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* ---- 6. Entsorgte Ware: verlässt den Betrieb, fehlt aber im Modell ---- */
  // v_lieferung_kohorte nimmt nur buch in ('verkauf','marge'). Eine Lieferung
  // an den Kompost (buch = 'verlust') zählt in ausgang_kg, reduziert aber den
  // Bestand nicht und erscheint nicht als Verlust.
  const ents = Number(bil?.entsorgt ?? 0)
  const kohorteBuecher = frage(k, `select distinct buch from v_lieferung_kohorte`).map(r => r.buch)
  if (!kohorteBuecher.includes('verlust')) {
    const wieviel = wert(k, `select coalesce(sum(masse_kg), 0) from v_lieferung_masse
                              where buch = 'verlust' and datum <= heute()`)
    B({ klasse: 3, ort: { sicht: 'v_lieferung_kohorte' },
        titel: 'Eine Lieferung in den Kompost verlässt den Betrieb, fehlt aber in Bestand und Verlust',
        steht_da: `v_lieferung_kohorte filtert auf buch in ('verkauf','marge'); `
                + `entsorgt sind heute ${Number(ents).toFixed(0)} kg`,
        muesste: 'Entsorgte Ware ist echter Verlust: sie muss den Bestand verringern und im Verlust erscheinen.',
        warum: 'Sie zählt in ausgang_kg (v_saisonbilanz nimmt dort alle Bücher), aber die Kaskade sieht sie '
             + 'nicht. Damit liegt sie rechnerisch weiter im Lager und altert weiter — dieselbe Fehlerart, '
             + 'die 0062 für die Marge behoben hat, nur für das dritte Buch. Solange niemand Kompost '
             + 'erfasst, ist es folgenlos; sobald doch, ist es eine stille Verschiebung.',
        beleg: 'pruefwerk/sonden/05_metamorph.mjs, Abschnitt 6',
        groesse: { wert: Number(Number(wieviel ?? 0).toFixed(0)), einheit: 'kg entsorgt in den Demodaten', basis: 'Demodaten' },
        sicherheit: Number(wieviel ?? 0) > 0 ? 'hoch' : 'mittel', marke: 'Reparatur', aufwand: 'klein',
        gegenrede: 'Vielleicht ist beabsichtigt, dass „entsorgt" nur eine Notiz ist. Dann dürfte es aber '
                 + 'auch nicht in ausgang_kg stehen — dort steht es.' })
  }

  /* ---- 7. Idempotenz ---------------------------------------------------- */
  const fingerA = wert(k, fingerabdruck)
  rechne(k)
  const fingerB = wert(k, fingerabdruck)
  if (fingerA !== fingerB) {
    B({ klasse: 1, ort: { sicht: 'auswertung_aktualisieren()' },
        titel: 'Zweimal rechnen ergibt andere Zahlen',
        steht_da: `Fingerabdruck ${fingerA} → ${fingerB}`,
        muesste: 'Dieselben Daten, dieselbe Rechnung, dasselbe Ergebnis.',
        warum: 'Wer auf „neu rechnen" drückt und andere Zahlen bekommt, kann keiner glauben.',
        beleg: 'pruefwerk/sonden/05_metamorph.mjs, Abschnitt 7',
        groesse: { wert: 1, einheit: 'abweichender Fingerabdruck', basis: 'Demodaten' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* ---- 8. Zeitpfeil: „bis heute" wird nie kleiner ----------------------- */
  const vorher = frage(k, kennzahlen)[0]
  const heute = wert(k, 'select heute()::text')
  tue(k, `insert into einstellung (schluessel, wert) values ('heute_test', to_jsonb('${heute}'::text))
          on conflict (schluessel) do update set wert = excluded.wert`)
  tue(k, `update einstellung set wert = to_jsonb((date '${heute}' + 7)::text) where schluessel = 'heute_test'`)
  rechne(k)
  const nachher = frage(k, kennzahlen)[0]
  for (const feld of ['verlust_heute_kg', 'verdunstung_heute_kg', 'schimmel_heute_kg']) {
    const a = Number(vorher[feld] ?? 0), b = Number(nachher[feld] ?? 0)
    if (b < a - Math.max(a * 1e-6, 0.01)) {
      B({ klasse: 3, ort: { sicht: 'v_saisonbilanz', spalte: feld },
          titel: `„${feld}" wird kleiner, wenn heute später ist`,
          steht_da: `${a.toFixed(0)} kg am ${heute}, ${b.toFixed(0)} kg sieben Tage später`,
          muesste: 'Eine Grösse, die „bis heute" heisst, kann mit fortschreitender Zeit nur wachsen.',
          warum: 'Sonst schrumpft der bereits eingetretene Verlust über Nacht.',
          beleg: 'pruefwerk/sonden/05_metamorph.mjs, Abschnitt 8',
          groesse: { wert: Number((a - b).toFixed(0)), einheit: 'kg Rückgang in 7 Tagen', basis: 'Demodaten' },
          sicherheit: 'hoch', marke: 'Reparatur' })
    }
  }

  return raus
}

const fingerabdruck = `
  select md5(string_agg(z, '|' order by z)) from (
    select concat_ws(':', charge_nr, round(eingang_kg,2), round(verlust_heute_kg,2),
                     round(im_haus_heute_kg,2), round(geliefert_kg,2)) as z
      from erg_charge) t`

const kennzahlen = `select verlust_heute_kg::numeric as verlust_heute_kg,
                           verdunstung_heute_kg::numeric as verdunstung_heute_kg,
                           schimmel_heute_kg::numeric as schimmel_heute_kg,
                           im_haus_heute_kg::numeric as im_haus_heute_kg
                      from v_saisonbilanz`

/**
 * Selbstprobe: Eine Kaskadenzeile absichtlich verbiegen — die Erhaltung muss
 * anschlagen. Findet die Sonde das nicht, prüft sie nichts.
 */
export async function selbstprobe({ db }) {
  const k = kopie(db, 'pw_meta_probe')
  tue(k, `create or replace view v_kaskade with (security_invoker = true) as
            select charge_nr, sorte, schlag, portion, alter_tage, eingang_kg, m0, m1, m2, r, f, a0,
                   a_klein_n, a_gross_n, a_fax, u, d_m1_r, d_f_eta, modell_gilt, f_extrapoliert,
                   r_n, r_basis, klein_n, klein_basis, gross_n, gross_basis, f_n, fax_n, fax_basis,
                   r_bekannt, f_bekannt, a_klein_bekannt, a_gross_bekannt, a0_bekannt, a0_var,
                   a_fax_bekannt, verdunstung_kg, sockel_kg, schimmel_kg, klein_kg, nebenkanal_kg,
                   fax_kg, verkaufsfaehig_kg, kohorte, geliefert_kg, ueberzaehlung_kg,
                   n_lieferungen, verkaufsfaehig_anteil from mv_kaskade`)
  const n = wert(k, `select count(*) from mv_kaskade where m0 > 0
                       and abs(m0 - (verdunstung_kg + sockel_kg + schimmel_kg + klein_kg
                                     + nebenkanal_kg + fax_kg + verkaufsfaehig_kg)) > greatest(m0*1e-6, 0.01)`)
  // In der heilen Datenbank darf es keine Abweichung geben …
  if (Number(n) !== 0) return false
  // … und mit einer verbogenen Zeile muss die Abfrage anschlagen.
  tue(k, `create table pw_probe as select * from mv_kaskade limit 1;
          update pw_probe set verkaufsfaehig_kg = verkaufsfaehig_kg + 100;`)
  const m = wert(k, `select count(*) from pw_probe where m0 > 0
                       and abs(m0 - (verdunstung_kg + sockel_kg + schimmel_kg + klein_kg
                                     + nebenkanal_kg + fax_kg + verkaufsfaehig_kg)) > greatest(m0*1e-6, 0.01)`)
  return Number(m) === 1
}
