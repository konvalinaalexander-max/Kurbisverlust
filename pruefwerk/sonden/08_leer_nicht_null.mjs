/**
 * Sonde 08 — Leer ist nicht null
 *
 * Der Grundsatz des Programms steht in `docs/ABLAUF.md`: Was nicht gemessen
 * wurde, ist **unbekannt**, nicht null. Eine Null ist eine Aussage — „hier ist
 * nichts passiert" —, und diese Aussage darf nur machen, wer nachgesehen hat.
 *
 * Geprüft wird das in einer Welt, in der garantiert nichts gemessen ist: drei
 * Paletten, eine Lieferung, keine einzige Wägung, keine Palox-Ablesung. Jede
 * Zahl, die dann trotzdem als Zahl dasteht statt als „—", ist eine Behauptung
 * ohne Grundlage.
 *
 * Als Massstab dient die Sicht, die es richtig macht: `erg_verlust` liefert in
 * dieser Welt `kg = NULL` und `bekannt = false`. Wo eine andere Sicht dieselbe
 * Grösse als 0,00 ausweist, widersprechen sich zwei Sichten derselben
 * Datenbank — und die Oberfläche zeigt, je nach Seite, mal das eine, mal das
 * andere.
 */
import { befund, frage, lies, dateien, rechne, zeileVon } from '../umgebung.mjs'
import { geruest, paletten, papierfall } from '../saison.mjs'

export const lang = false

/**
 * Welche Spalte welchen Strom meint. Von Hand, weil die Namen es nicht
 * hergeben: `sockel_heute_kg` heisst in `erg_verlust` „Nicht lagerbedingt",
 * und `kanal_*` fasst zwei Ströme zusammen. Eine geratene Zuordnung wäre hier
 * schlimmer als keine.
 */
const ZUORDNUNG = [
  { spalte: 'verdunstung_heute_kg', stroeme: ['Verdunstung'] },
  { spalte: 'schimmel_heute_kg',    stroeme: ['Schimmel/Fäulnis'] },
  { spalte: 'sockel_heute_kg',      stroeme: ['Nicht lagerbedingt'] },
  { spalte: 'fax_heute_kg',         stroeme: ['Faul beim Abpacken (Fax)'] },
  { spalte: 'fax_erwartet_kg',      stroeme: ['Faul beim Abpacken (Fax)'] },
  { spalte: 'kanal_ausgelagert_kg', stroeme: ['Zu klein (Tierfutter)', 'Nebenkanal zu gross'] },
  { spalte: 'kanal_im_haus_kg',     stroeme: ['Zu klein (Tierfutter)', 'Nebenkanal zu gross'] },
  { spalte: 'verlust_heute_kg',     stroeme: ['Verdunstung', 'Schimmel/Fäulnis', 'Nicht lagerbedingt',
                                              'Faul beim Abpacken (Fax)'] },
]

const SICHTEN = ['v_saisonbilanz', 'erg_charge']

export async function laufen() {
  const raus = []
  const B = (o) => raus.push(befund({ sonde: '08_leer_nicht_null', kuerzel: 'LNN', ...o }))

  /* 8a. Die Welt ohne jede Messung */
  const db = 'pw_leer'
  papierfall(db)

  const bekannt = Object.fromEntries(
    frage(db, `select strom, bekannt from erg_verlust where gruppe = 'gesamt'`)
      .map(r => [r.strom, r.bekannt === true || r.bekannt === 't']))
  const ungemessen = (stroeme) => stroeme.every(s => bekannt[s] === false)

  const treffer = []
  for (const sicht of SICHTEN) {
    // pg_attribute statt information_schema: materialisierte Sichten stehen dort nicht.
    const spalten = frage(db, `select a.attname as spalte
                                 from pg_attribute a
                                 join pg_class c on c.oid = a.attrelid
                                 join pg_namespace n on n.oid = c.relnamespace
                                where n.nspname = 'public' and c.relname = '${sicht}'
                                  and a.attnum > 0 and not a.attisdropped`).map(r => r.spalte)
    const zeile = frage(db, `select * from ${sicht} limit 1`)[0]
    if (!zeile) continue
    for (const z of ZUORDNUNG) {
      if (!spalten.includes(z.spalte)) continue
      if (!ungemessen(z.stroeme)) continue
      const wert = zeile[z.spalte]
      if (wert === null || wert === undefined) continue
      treffer.push({ sicht, spalte: z.spalte, wert: Number(wert), stroeme: z.stroeme })
    }
  }

  if (treffer.length) {
    const bilanz = frage(db, `select eingang_kg::numeric as eingang, verlust_bekannt from v_saisonbilanz`)[0]
    B({ klasse: 3, ort: { sicht: SICHTEN.join(' und '), spalte: treffer.map(t => t.spalte).join(', ') },
        titel: 'Ungemessene Verlustströme stehen als 0,00 kg statt als „unbekannt"',
        steht_da: `In einer Saison ohne eine einzige Messung (${Math.round(Number(bilanz.eingang))} kg Eingang) `
                + `liefern ${new Set(treffer.map(t => t.sicht)).size} Sichten `
                + `${treffer.length} Spalten als Zahl: `
                + treffer.map(t => `${t.sicht}.${t.spalte} = ${t.wert.toFixed(2)}`).join(', ')
                + `. Dieselben Ströme stehen in erg_verlust als NULL mit bekannt = false.`,
        muesste: 'Dieselbe Antwort wie erg_verlust: NULL. Die Sichten führen das Kennzeichen bereits mit '
               + '(`r_bekannt`, `f_bekannt`, `a_fax_bekannt`, `a0_bekannt` in mv_kaskade); es wird beim '
               + 'Bilden der Summen nur nicht abgefragt.',
        warum: 'Die Wurzel steht in mv_kaskade: ein fehlender Koeffizient wird mit `coalesce(…, 0)` zu 0, '
             + 'und 0 · Masse ist 0 kg. Die Kennzeichen daneben sagen die Wahrheit, aber die kg-Spalten '
             + 'nicht — und die Oberfläche zeigt die kg-Spalte. Auf dem Überblick steht dann „Verlust bis '
             + 'heute: 0,0 t", obwohl niemand je gewogen hat. Das ist genau die Aussage, die das '
             + 'Programm laut ABLAUF.md nie machen soll.',
        beleg: 'pruefwerk/sonden/08_leer_nicht_null.mjs → Welt ohne Messung (pruefwerk/saison.mjs → papierfall)',
        groesse: { wert: Math.round(Number(bilanz.eingang)), einheit: 'kg Eingang ohne jede Verlustaussage',
                   basis: 'Papierfall: 3 Paletten, 1 Lieferung, 0 Messungen' },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein',
        gegenrede: '`verlust_bekannt = false` steht in derselben Zeile, und die Oberfläche zeigt einen '
                 + 'Warnstreifen. Das reicht nicht: Der Streifen erklärt eine Zahl, die daneben weiter '
                 + 'als Zahl dasteht — und in jede Prozentrechnung, jede Grafik und jeden Export eingeht. '
                 + 'Ausserdem ist es ein Widerspruch zwischen zwei Sichten derselben Datenbank, und das '
                 + 'ist unabhängig von der Darstellung ein Fehler.' })

    /* Die Bereiche machen es richtig — das ist der Beleg, dass es geht */
    const g = frage(db, `select verlust_unten_kg, verlust_oben_kg, kanal_unten_kg, kanal_oben_kg
                           from v_saisonbilanz`)[0]
    if (g && Object.values(g).every(v => v === null)) {
      B({ klasse: 1, ort: { sicht: 'v_saisonbilanz' },
          titel: 'Geprüft und in Ordnung: die Bereiche sagen „unbekannt", der Mittelwert nicht',
          steht_da: 'verlust_unten_kg, verlust_oben_kg, kanal_unten_kg, kanal_oben_kg sind alle NULL — '
                  + 'in derselben Zeile, in der verlust_heute_kg 0,00 ist.',
          muesste: 'Nichts. Diese Zeile ist der Beweis, dass die Sicht das Unwissen kennt und es an '
                 + 'einer Stelle bereits richtig weitergibt.',
          warum: 'Wenn die Grenzen NULL sein können, kann es der Mittelwert auch. Der Befund oben ist '
               + 'damit keine Frage der Machbarkeit, sondern eine vergessene Stelle.',
          beleg: 'pruefwerk/sonden/08_leer_nicht_null.mjs → 8a',
          groesse: { wert: 4, einheit: 'Spalten, die es richtig machen', basis: 'Papierfall' },
          sicherheit: 'hoch', marke: 'kein Fehler' })
    }
  }

  /* 8b. Wo im Quelltext aus „unbekannt" eine Null gemacht wird.

     Nicht jedes `?? 0` ist falsch. Über einer Liste, die selbst die Auskunft
     ist, ist die Null beobachtet; über einem einzelnen fehlenden Wert ist sie
     erfunden. Welche von beiden vorliegt, kann keine Regel entscheiden — der
     Mensch, der die Stelle geschrieben hat, aber schon. Die Sonde verlangt
     darum nicht, dass es keine solchen Stellen gibt, sondern dass **jede**
     einen Kommentar unmittelbar darüber hat, der sagt, warum die Null dort
     richtig ist. Eine Stelle ohne diesen Satz ist der Befund. */
  const MASSE = /(_kg|verlust|verdunstung|schimmel|sockel|fax|kanal|masse|netto|brutto)/i
  const stellen = []
  for (const pfad of dateien('src')) {
    const text = lies(pfad)
    const zeilen = text.split('\n')
    for (const m of text.matchAll(/([A-Za-z0-9_.?\[\]]*(?:_kg|verlust|verdunstung|schimmel|sockel|fax|kanal|masse|netto|brutto)[A-Za-z0-9_.?\[\]]*)\s*(\?\?|\|\|)\s*0\b/gi)) {
      if (!MASSE.test(m[1])) continue
      const zeile = zeileVon(text, m.index)
      /* Begründet heisst: In den drei Zeilen darüber steht ein Kommentar
         (`//`, `/*` oder eine Fortsetzung davon, auch als JSX-Kommentar). */
      const davor = zeilen.slice(Math.max(0, zeile - 4), zeile - 1)
      const begruendet = davor.some(z => /^\s*(\/\/|\/\*|\*|\{\/\*)/.test(z))
      stellen.push({ pfad, zeile, text: m[0].replace(/\s+/g, ' '), begruendet })
    }
  }
  const offen = stellen.filter(s => !s.begruendet)
  if (offen.length === 0 && stellen.length) {
    B({ klasse: 1, ort: { datei: stellen[0].pfad, zeile: stellen[0].zeile },
        titel: `Geprüft: alle ${stellen.length} Stellen mit \`?? 0\` an einer Masse sind begründet`,
        steht_da: stellen.map(s => `${s.pfad}:${s.zeile}`).join(', ')
          + ' — über jeder steht, warum die Null dort beobachtet und nicht erfunden ist '
          + '(gefilterte Liste, Sortierschlüssel, oder eine Summe nur über das Gerechnete).',
        muesste: 'So. Die Sonde prüft nicht, dass es keine solchen Stellen gibt — sie prüft, '
               + 'dass keine ohne Begründung dasteht.',
        warum: 'Ein `?? 0` über einer leeren Liste ist richtig, über einem fehlenden Einzelwert '
             + 'falsch. Die Regel kann das nicht unterscheiden, der Satz darüber schon.',
        beleg: 'pruefwerk/sonden/08_leer_nicht_null.mjs → 8b',
        groesse: { wert: stellen.length, einheit: 'begründete Stellen', basis: 'src/**' },
        sicherheit: 'hoch', marke: 'kein Fehler', aufwand: 'keiner',
        gegenrede: 'Ein Kommentar kann falsch sein; die Sonde liest ihn nicht, sie zählt ihn. '
                 + 'Sie hält damit die Stellen sichtbar, nicht die Begründungen wahr.' })
  }
  if (offen.length) {
    B({ klasse: 2, ort: { datei: offen[0].pfad, zeile: offen[0].zeile },
        titel: `${offen.length} Stellen machen aus einer fehlenden Masse eine Null, ohne zu sagen warum`,
        steht_da: offen.slice(0, 8).map(s => `${s.pfad}:${s.zeile} — \`${s.text}\``).join('; ')
                + (offen.length > 8 ? ` … und ${offen.length - 8} weitere` : '')
                + ` (von ${stellen.length} Stellen insgesamt sind ${stellen.length - offen.length} begründet).`,
        muesste: 'Fehlt eine Masse, gehört „—" hin. `?? 0` ist richtig, wo eine Summe über eine leere '
               + 'Liste gebildet oder ein Sortierschlüssel gebraucht wird (dort ist 0 beobachtet), und '
               + 'falsch, wo ein einzelner Wert fehlt. Was von beidem gilt, gehört als Satz darüber.',
        warum: 'Jede dieser Stellen kann eine unbekannte Masse in eine Summe tragen, die danach wie '
             + 'eine gemessene Zahl aussieht. Welche harmlos ist, kann nur entscheiden, wer sie '
             + 'geschrieben hat — und muss es aufschreiben, sonst entscheidet es der nächste neu.',
        beleg: 'pruefwerk/sonden/08_leer_nicht_null.mjs → 8b',
        groesse: { wert: offen.length, einheit: 'unbegründete Stellen',
                   basis: `${stellen.length} Stellen mit \`?? 0\` an einer Masse` },
        sicherheit: 'mittel', marke: 'Reparatur', aufwand: 'klein',
        gegenrede: 'Ein grosser Teil solcher Stellen steht in `reduce((a, b) => a + (b.kg ?? 0), 0)` '
                 + 'und ist dort unbedenklich, weil die Liste selbst die Auskunft ist. Der Befund '
                 + 'verlangt keine Änderung an der Rechnung, nur einen Satz darüber.' })
  }

  /* 8c. Am Eingang — dort, wo aus einer Lücke ein Gewicht wird.
     Drei Paletten, alle 1000 kg brutto, alle mit 30 Kisten gepackt. Nur steht
     es nicht überall auf dem Zettel. Richtig wäre je 1000 − 30·1 − 20 = 950 kg. */
  const t = 'pw_lnn_tara'
  geruest(t)
  paletten(t, [
    { datum: '2026-06-01', brutto: 1000, kisten: 30 },              // vollständig
    { datum: '2026-06-01', brutto: 1000, kisten: null },            // Kistenzahl fehlt
    { datum: '2026-06-01', brutto: 1000, kisten: 30, art: null },   // Gebindeart fehlt
  ])
  rechne(t)
  const p = frage(t, `select id, brutto_kg::numeric as brutto, kisten,
                             gebindeart, netto_kg::numeric as netto from v_palette order by id`)
  const c = frage(t, `select n_paletten, n_paletten_mit_netto, eingang_kg::numeric as eingang
                        from erg_charge`)[0]
  const auff = frage(t, `select art, befund from v_plausibilitaet`)

  const ohneKisten = p.find(x => x.kisten === null)
  if (ohneKisten && ohneKisten.netto !== null) {
    const zuviel = Number(ohneKisten.netto) - 950
    if (Math.abs(zuviel) > 0.01) {
      B({ klasse: 3, ort: { sicht: 'v_palette', spalte: 'netto_kg' },
          titel: 'Fehlt die Kistenzahl, wird sie als null Kisten gerechnet — und das Netto zu hoch',
          steht_da: `Palette mit unbekannter Kistenzahl: netto_kg = ${Number(ohneKisten.netto).toFixed(2)} kg `
                  + `bei ${Number(ohneKisten.brutto).toFixed(0)} kg brutto. Die Sicht rechnet `
                  + '`coalesce(p.kisten, 0) * g.tara_kg_pro_kiste` — null Kisten wiegen nichts.',
          muesste: `netto_kg = NULL. Die Palette wurde gewogen, aber nicht gezählt; ihr Nettogewicht `
                 + `ist unbekannt. Richtig wären hier ${(950).toFixed(0)} kg — die Sicht liefert `
                 + `${zuviel > 0 ? zuviel.toFixed(0) + ' kg zu viel' : Math.abs(zuviel).toFixed(0) + ' kg zu wenig'}.`,
          warum: 'Die Kistenzahl darf leer bleiben (die Spalte ist nullable, die Erntejournal-Übernahme '
               + 'füllt sie nicht immer). Fehlt sie, verschwindet die Kistentara aus der Rechnung, und '
               + 'ihr Gewicht wird als Kürbis verbucht. Anders als bei der fehlenden Gebindeart merkt '
               + 'das niemand: Die Palette hat ein Netto, es ist nur falsch. `n_paletten_mit_netto` '
               + 'zählt sie mit, `v_plausibilitaet` schweigt.',
          beleg: 'pruefwerk/sonden/08_leer_nicht_null.mjs → 8c',
          groesse: { wert: Number((100 * zuviel / 950).toFixed(1)), einheit: '% zu viel Eingang je betroffener Palette',
                     basis: '30 Kisten à 1 kg auf 950 kg Netto' },
          sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein',
          gegenrede: 'In den Demodaten hat jede Palette eine Kistenzahl. Die Spalte ist aber nullable, '
                   + 'und im Betrieb ist der Zettel genau dann unvollständig, wenn es hektisch war. '
                   + 'Auf einer echten Palette (456 kg brutto, 32 Kisten, 1,5 kg je Kiste) sind das '
                   + '48 kg — gut ein Zehntel.' })
    }
  }

  const ohneArt = p.find(x => x.gebindeart === null)
  const fehlend = Number(c.n_paletten) - Number(c.n_paletten_mit_netto)
  // Seit 0064 hängt die Herkunftsmarke des Eingangs an n_paletten_mit_netto,
  // und v_plausibilitaet meldet die Lücke. Der Befund bleibt nur, solange
  // eines von beidem fehlt.
  const markeBedingt = /n_paletten_mit_netto/.test(lies('src/pages/Ueberblick.tsx'))
  const gemeldet = auff.some(a => /Tara fehlt/.test(a.art))
  if (ohneArt && ohneArt.netto === null && fehlend > 0 && !(markeBedingt && gemeldet)) {
    const jeVoll = p.filter(x => x.netto !== null).reduce((a, x) => a + Number(x.netto), 0)
                 / p.filter(x => x.netto !== null).length
    B({ klasse: 3, ort: { sicht: 'erg_charge', spalte: 'eingang_kg' },
        titel: 'Der Eingang trägt das Zeichen „gemessen", enthält aber hochgerechnete Paletten',
        steht_da: `${Number(c.n_paletten)} Paletten, davon ${Number(c.n_paletten_mit_netto)} mit Netto. `
                + `eingang_kg = ${Number(c.eingang).toFixed(0)} kg — die Palette ohne Gebindeart geht mit `
                + `${jeVoll.toFixed(0)} kg ein, dem Mittel der übrigen. `
                + `v_plausibilitaet meldet dazu ${auff.length} Auffälligkeiten.`,
        muesste: 'Entweder ohne die Palette rechnen und das sagen, oder mit dem Mittel rechnen und die '
               + 'Zahl als teils hochgerechnet kennzeichnen. Der Überblick schreibt heute '
               + '„<Herkunft art=gemessen> heisst: aus einer vollständigen Liste — jede Palette im '
               + 'Erntejournal" unter eine Zahl, die genau das nicht ist.',
        warum: 'Der Eingang ist die Bezugsgrösse jeder Prozentzahl des Programms. Wenn er still zwischen '
             + 'gemessen und hochgerechnet mischt, ist jede Verlustquote entsprechend verschoben — und '
             + 'zwar ohne dass irgendwo eine Warnung erscheint. Die Zahl `n_paletten_mit_netto` steht '
             + 'bereits in derselben Zeile; sie wird nur auf der Seite Messungen gezeigt, nicht dort, '
             + 'wo die Herkunft behauptet wird.',
        beleg: 'pruefwerk/sonden/08_leer_nicht_null.mjs → 8c',
        groesse: { wert: Math.round(jeVoll), einheit: 'kg hochgerechnet und als gemessen ausgewiesen',
                   basis: `1 von ${Number(c.n_paletten)} Paletten` },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein',
        gegenrede: 'Die Seite Messungen zeigt „(2 m. Netto)" und listet die Taralücken. Das ist gut, '
                 + 'trifft aber die falsche Seite: Die Herkunftsmarke steht auf dem Überblick, und wer '
                 + 'dort liest, geht nicht erst auf Messungen nachsehen.' })
  }

  const maskenTara = []
  for (const pfad of dateien('src')) {
    const text = lies(pfad)
    for (const m of text.matchAll(/tara_kg_palette\s*\?\?\s*0/g))
      maskenTara.push({ pfad, zeile: zeileVon(text, m.index) })
  }
  if (maskenTara.length) {
    B({ klasse: 3, ort: { datei: maskenTara[0].pfad, zeile: maskenTara[0].zeile },
        titel: 'Die Masken rechnen ein Netto, auch wenn die Palettentara fehlt',
        steht_da: maskenTara.map(m => `${m.pfad}:${m.zeile}`).join(', ')
                + ' — überall `tara.tara_kg_palette ?? 0`, während `tara_kg_pro_kiste != null` verlangt wird.',
        muesste: 'Beide Taras gleich behandeln: fehlt eine, gibt es kein Netto und die Maske sagt das. '
               + 'Sonst zeigt sie dem Arbeiter eine Zahl, die um die Palettentara zu hoch ist (in den '
               + 'Stammdaten 25 kg je Palette).',
        warum: 'Der Arbeiter prüft die Plausibilität einer Wägung an der angezeigten Zahl. Ist sie um '
             + '25 kg zu hoch, nimmt er eine falsche Wägung an — oder er verwirft eine richtige. '
             + 'Zusätzlich weichen Maske und Datenbank voneinander ab: `v_palette.netto_kg` liefert '
             + 'bei fehlender Kistentara NULL, die Maske aber eine Zahl.',
        beleg: 'pruefwerk/sonden/08_leer_nicht_null.mjs → 8c',
        groesse: { wert: maskenTara.length, einheit: 'Masken', basis: 'src/arbeit und src/pages' },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein',
        gegenrede: 'Alle vier Gebindearten der Stammdaten haben heute eine Palettentara. Die Spalte ist '
                 + 'aber nullable, und eine neue Gebindeart wird im Betrieb angelegt, ohne dass jemand '
                 + 'die App danach prüft.' })
  }

  return raus
}

/**
 * Selbstprobe: In der Welt ohne Messung *muss* mindestens ein Strom als
 * unbekannt gelten, und `erg_verlust` *muss* ihn als NULL führen. Gilt keiner
 * als unbekannt oder steht dort eine Zahl, ist der Massstab kaputt — und dann
 * sagt auch das leere Ergebnis der Sonde nichts.
 *
 * (Bis 0064 stand hier zusätzlich, dass v_saisonbilanz denselben Strom als 0
 * ausweist — das war der Befund LNN-001. Er ist behoben; die Selbstprobe prüft
 * jetzt nur noch den Massstab, nicht mehr den Fehler.)
 */
export async function selbstprobe() {
  papierfall('pw_leer_probe')
  const r = frage('pw_leer_probe', `select count(*) filter (where not bekannt) as offen,
                                           count(*) filter (where kg is not null) as mit_zahl,
                                           count(*) as alle
                                      from erg_verlust where gruppe = 'gesamt'`)[0]
  const b = frage('pw_leer_probe', `select verlust_bekannt, verlust_heute_kg::numeric as v,
                                           eingang_kg::numeric as e
                                      from v_saisonbilanz`)[0]
  return Number(r.offen) === Number(r.alle) && Number(r.alle) > 0 && Number(r.mit_zahl) === 0
      && (b.verlust_bekannt === false || b.verlust_bekannt === 'f')
      && Number(b.e) > 0
}
