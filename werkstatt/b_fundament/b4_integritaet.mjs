/**
 * B4 — Was die Datenbank wirklich garantiert.
 *
 * DIE FRAGE
 *
 * Eine Prüfbedingung im Schema liest sich wie ein Versprechen. Ob sie eines
 * ist, hängt an Dingen, die im Schema nicht auffallen:
 *
 *   — Eine Bedingung mit `NOT VALID` gilt **nur für neue Zeilen**. Für die
 *     vorhandenen sagt sie nichts, und der Planer darf sich nicht auf sie
 *     stützen. Sie sieht im `\d`-Ausdruck genauso aus wie eine echte.
 *
 *   — Ein Fremdschlüssel garantiert, dass der Bezug existiert. Er garantiert
 *     **nicht**, dass es ihn nur einmal gibt.
 *
 *   — Ein eindeutiger Schlüssel garantiert Eindeutigkeit über *seine* Spalten.
 *     Ob das die Spalten sind, die der Betrieb für „dieselbe Beobachtung"
 *     hält, steht nirgends.
 *
 * WAS DIESES WERKZEUG TUT
 *
 * 1. Es sucht jede unbestätigte Prüfbedingung und **rechnet ihren Ausdruck
 *    selbst gegen die vorhandenen Zeilen**. Ergibt das null Verstösse, ist die
 *    Bedingung bestätigungsfähig und das Versprechen kostenlos einzulösen.
 *
 * 2. Es fragt für jede Messtabelle: **Was passiert, wenn dieselbe Beobachtung
 *    zweimal in der Datenbank steht?** Nicht als Überlegung — es legt auf einer
 *    Kopie eine wortgleiche zweite Zeile an, rechnet die ganze Auswertung neu
 *    und misst die Verschiebung in Kilogramm. Und es prüft, ob irgendetwas
 *    das verhindert oder wenigstens meldet.
 *
 * 3. Es sucht Indexe, die ein anderer Index bereits vollständig abdeckt.
 *
 * DIE GEGENPROBE, DIE DIESES WERKZEUG SICH SELBST STELLT
 *
 * Eine zweite Wägung derselben Palette ist **kein Fehler** — Paletten werden
 * mehrfach gewogen, dafür ist die Verdunstungsmessung da. Der Befund darf also
 * nicht lauten „Doppelte sind verboten", sondern nur: *diese* Doppelung
 * verschiebt *so viele* Kilogramm, und weder Datenbank noch Plausibilitäts-
 * sicht sagen ein Wort dazu. Was daraus folgt, entscheidet der Betrieb.
 */
import { frage, wert, tue, kopie, rechne, wegwerfen, befund, messung } from '../umgebung.mjs'

export const lang = true

const WERKSTATT = 'B — Fundament'

/* ---------- 1. Versprechen, die keine sind -------------------------------- */

/**
 * Der Ausdruck einer Prüfbedingung, gegen die vorhandenen Zeilen gerechnet.
 * `pg_get_constraintdef` liefert `CHECK ((...)) NOT VALID` — daraus wird der
 * nackte Ausdruck, und der geht in ein `count(*) filter (where not (...))`.
 * `not null` ist dabei die richtige Prüfung: eine Bedingung, die NULL ergibt,
 * gilt in Postgres als erfüllt, und genau so soll hier gezählt werden.
 */
function unbestaetigt(db) {
  const bedingungen = frage(db, `
    select con.conname as name, rel.relname as tabelle,
           pg_get_constraintdef(con.oid) as text
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace n on n.oid = rel.relnamespace
     where n.nspname = 'public' and con.contype = 'c' and not con.convalidated
     order by rel.relname, con.conname`)

  return bedingungen.map(b => {
    const ausdruck = b.text.replace(/^CHECK\s*\(/i, '').replace(/\)\s*(NOT VALID)?\s*$/i, '')
    const zeilen = wert(db, `select count(*) from ${b.tabelle}`)
    const verstoesse = wert(db, `
      select count(*) from ${b.tabelle} where not (${ausdruck})`)
    return { ...b, ausdruck, zeilen: Number(zeilen), verstoesse: Number(verstoesse) }
  })
}

/* ---------- 2. Dieselbe Beobachtung zweimal ------------------------------- */

/**
 * Die Messtabellen, die in eine Kilogrammzahl eingehen — und der Satz, der
 * beschreibt, was der Betrieb an dieser Stelle für „dieselbe Beobachtung"
 * hält. Der Satz steht hier und nicht im Bericht, weil er eine **Annahme** ist
 * und als solche kenntlich sein muss.
 */
const MESSTABELLEN = [
  { tabelle: 'verdunstung_wiegung', gleich: 'dieselbe Palette am selben Tag noch einmal gewogen',
    gewicht: 'brutto_jetzt_kg' },
  { tabelle: 'schimmel_messung', gleich: 'dieselbe Schimmelmenge zweimal am Auftrag erfasst',
    gewicht: 'kg', faelle: [
      { name: 'als Kistengewicht', wo: 'palox_stand_kg is null and gemessen' },
      { name: 'als Palox-Ablesung', wo: 'palox_stand_kg is not null and gemessen' }] },
  { tabelle: 'ausschuss_messung', gleich: 'dieselbe Ausschusskiste zweimal am Auftrag erfasst',
    gewicht: 'kg' },
  { tabelle: 'ausgang_wiegung', gleich: 'dieselbe fertige Palette zweimal gewogen',
    gewicht: 'brutto_kg' },
  { tabelle: 'lieferung', gleich: 'derselbe Lieferschein zweimal abgetippt',
    gewicht: 'kg' },
  { tabelle: 'auftrag_palette', gleich: 'dieselbe Eingangspalette zweimal am Auftrag gezählt',
    gewicht: 'brutto_zettel_kg', faelle: [
      { name: 'mit Zettelgewicht', wo: 'brutto_zettel_kg is not null' },
      { name: 'nur gezählt', wo: 'brutto_zettel_kg is null', gewicht: 'kisten' }] },
]

/** Die Zahlen, an denen sich eine Doppelung zeigen würde. */
const BILANZ = `select eingang_kg::float8, ausgang_kg::float8, verlust_heute_kg::float8,
                       verdunstung_heute_kg::float8, schimmel_heute_kg::float8,
                       im_haus_heute_kg::float8 from v_saisonbilanz`

/**
 * Eine wortgleiche zweite Zeile anlegen — ohne `id`, ohne Zeitstempel, die die
 * Datenbank selbst setzt. Alles andere wird übernommen, denn genau das tut ein
 * Mensch, der denselben Zettel zweimal abtippt.
 */
function doppeln(db, tabelle, wo) {
  const spalten = frage(db, `
    select a.attname as name
      from pg_attribute a join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = ${lit(tabelle)}
       and a.attnum > 0 and not a.attisdropped
       and a.attname not in ('id', 'erfasst_ts', 'geaendert_ts')
     order by a.attnum`).map(z => z.name)
  tue(db, `insert into ${tabelle} (${spalten.join(', ')})
           select ${spalten.join(', ')} from ${tabelle} where ${wo}`)
}

const lit = (s) => `'${String(s).replaceAll("'", "''")}'`

/**
 * Verhindert oder meldet irgendetwas die Doppelung? Geprüft werden die zwei
 * Stellen, an denen so etwas stehen müsste: ein eindeutiger Index über den
 * fachlichen Schlüssel, und ein Eintrag in der Plausibilitätssicht.
 */
function schutz(db, m) {
  const eindeutig = frage(db, `
    select i.indexrelid::regclass::text as name
      from pg_index i
     where i.indrelid = ${lit(m.tabelle)}::regclass and i.indisunique`)
    .map(z => z.name)
    .filter(n => !n.endsWith('_pkey'))
  return { eindeutige_indexe: eindeutig }
}

/**
 * Nicht irgendeine Zeile wird verdoppelt, sondern die **schwerste** — und wo
 * eine Tabelle zwei Erfassungsarten kennt, die schwerste **je Art**.
 *
 * Beides ist nötig, und beides hat dieses Werkzeug erst im zweiten Anlauf
 * getan. Eine beliebige Zeile misst nichts: trifft es zufällig eine leere,
 * kommt null heraus, und null hiesse dann fälschlich „harmlos". Und eine
 * einzige Zeile je Tabelle misst zu wenig: Die schwerste Schimmelzeile der
 * Demodaten ist eine **Palox-Ablesung**, also ein Füllstand. Zwei gleiche
 * Füllstände ergeben die Differenz null — die Doppelung verpufft. Das ist eine
 * echte und gute Eigenschaft, aber sie gilt nur für Füllstände; die zweite Art
 * derselben Tabelle ist ungeschützt. Wer nur die schwerste Zeile nimmt, meldet
 * „Tabelle geschützt" und irrt sich.
 */
function doppelversuch(db, m, fall) {
  const gewicht = fall?.gewicht ?? m.gewicht
  const wo = fall?.wo ?? 'true'
  const kandidat = frage(db, `
    select id from ${m.tabelle} where (${wo}) and ${gewicht} is not null
     order by ${gewicht} desc, id limit 1`)[0]
  if (!kandidat) return { ...m, fall, unpruefbar: `keine Zeile mit \`${gewicht}\`, wo ${wo}` }

  const probe = kopie('demo', `wk_b4_${m.tabelle.slice(0, 20)}`)
  try {
    const vorher = frage(probe, BILANZ)[0]
    doppeln(probe, m.tabelle, `id = ${lit(kandidat.id)}`)
    rechne(probe)
    const nachher = frage(probe, BILANZ)[0]
    const gemeldet = Number(wert(probe, `select count(*) from v_plausibilitaet`))
      - Number(wert(db, `select count(*) from v_plausibilitaet`))

    const bewegt = Object.keys(vorher)
      .map(k => ({ zahl: k, vorher: vorher[k], nachher: nachher[k],
                   delta: Math.round((nachher[k] - vorher[k]) * 100) / 100 }))
      .filter(z => Math.abs(z.delta) >= 0.01)

    return { ...m, fall, bewegt, gemeldet, ...schutz(db, m),
             groesste: bewegt.length ? Math.max(...bewegt.map(z => Math.abs(z.delta))) : 0 }
  } finally {
    wegwerfen(probe)
  }
}

/** Alle Fälle einer Tabelle — eine Tabelle ohne eigene Fälle hat genau einen. */
const alleVersuche = (db) => MESSTABELLEN.flatMap(m =>
  (m.faelle ?? [null]).map(f => doppelversuch(db, m, f)))

/* ---------- 3. Indexe, die ein anderer schon abdeckt ---------------------- */

/**
 * Index A ist überflüssig, wenn ein anderer Index B existiert, dessen
 * Schlüsselspalten mit denen von A beginnen, der dieselbe (oder gar keine)
 * Bedingung trägt und der mindestens so streng ist. Dann beantwortet B jede
 * Frage, die A beantwortet — und A kostet nur Schreibarbeit und Platz.
 */
function ueberfluessigeIndexe(db) {
  const alle = frage(db, `
    select i.indexrelid::regclass::text as name,
           i.indrelid::regclass::text   as tabelle,
           i.indisunique                as eindeutig,
           i.indisprimary               as primaer,
           (select array_agg(a.attname order by k.n)
              from unnest(i.indkey[0:i.indnkeyatts-1]) with ordinality k(attnum, n)
              join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum) as spalten,
           coalesce(pg_get_expr(i.indpred, i.indrelid), '') as bedingung,
           pg_relation_size(i.indexrelid) as bytes
      from pg_index i
      join pg_class c on c.oid = i.indrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'`)

  const raus = []
  for (const a of alle) {
    if (a.primaer || !a.spalten) continue
    const deckt = alle.find(b => b.name !== a.name && b.tabelle === a.tabelle && b.spalten
      && b.spalten.length >= a.spalten.length
      && a.spalten.every((s, i) => b.spalten[i] === s)
      && (b.bedingung === '' || b.bedingung === a.bedingung)
      && (!a.eindeutig || b.eindeutig))
    if (deckt) raus.push({ ...a, gedeckt_von: deckt.name,
                           gedeckt_spalten: deckt.spalten.join(', ') + (deckt.bedingung ? ` wo ${deckt.bedingung}` : '') })
  }
  return raus
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const raus = []

  /* --- 1 --- */
  const offen = unbestaetigt(db)
  if (offen.length) {
    raus.push(messung({
      werkstatt: WERKSTATT, titel: 'Prüfbedingungen, die nur für neue Zeilen gelten',
      einheit: 'Zeilen',
      spalten: ['Bedingung', 'Tabelle', 'Zeilen geprüft', 'Verstösse'],
      erklaerung: 'Jede dieser Bedingungen steht mit `NOT VALID` im Schema. Postgres wendet sie '
        + 'auf neue und geänderte Zeilen an, hat aber nie nachgesehen, ob die vorhandenen sie '
        + 'erfüllen — und darf sie deshalb beim Planen einer Abfrage nicht voraussetzen. Die '
        + 'Spalte „Verstösse" ist der Ausdruck der Bedingung, von diesem Werkzeug selbst gegen '
        + 'die Daten gerechnet.',
      zeilen: offen.map(o => ({ 'Bedingung': o.name, 'Tabelle': o.tabelle,
        'Zeilen geprüft': o.zeilen, 'Verstösse': o.verstoesse })),
    }))

    const sauber = offen.filter(o => o.verstoesse === 0)
    const schmutzig = offen.filter(o => o.verstoesse > 0)

    if (schmutzig.length) raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'INT', klasse: 3, marke: 'Reparatur', sicherheit: 'hoch',
      ort: { tabelle: schmutzig[0].tabelle },
      titel: `${schmutzig.length} Prüfbedingung(en) werden von den vorhandenen Daten verletzt`,
      steht_da: schmutzig.map(s => `\`${s.name}\`: ${s.verstoesse} von ${s.zeilen} Zeilen`).join('; ')
        + '. Weil die Bedingung `NOT VALID` ist, hat die Datenbank das nie bemerkt.',
      muesste: 'Entweder die verletzenden Zeilen richtigstellen und die Bedingung bestätigen, '
        + 'oder die Bedingung streichen — aber nicht als unbestätigtes Versprechen stehen lassen.',
      warum: 'Eine Bedingung, die im Schema steht und nicht gilt, ist schlimmer als keine: Wer '
        + 'das Schema liest, verlässt sich darauf.',
      beleg: 'werkstatt/b_fundament/b4_integritaet.mjs, Ausdruck der Bedingung gegen die Tabelle gerechnet',
      groesse: { wert: schmutzig.reduce((a, s) => a + s.verstoesse, 0), einheit: 'verletzende Zeilen',
                 basis: 'Demodaten' },
      gegenrede: 'Vielleicht war die Bedingung absichtlich `NOT VALID`, weil Altdaten sie nicht '
        + 'erfüllen und das hingenommen wurde. Dann gehört dieser Satz als Kommentar an die Bedingung.',
      aufwand: 'klein',
    }))

    if (sauber.length) raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'INT', klasse: 2, marke: 'Reparatur', sicherheit: 'hoch',
      ort: { tabelle: sauber.map(s => s.tabelle).join(', ') },
      titel: `${sauber.length} Prüfbedingungen versprechen etwas, das die Datenbank nie nachgesehen hat`,
      steht_da: sauber.map(s => `\`${s.name}\``).join(', ') + ' stehen mit `NOT VALID` im Schema. '
        + 'Sie gelten für neue und geänderte Zeilen, aber die Datenbank garantiert nichts über die '
        + `${Math.max(...sauber.map(s => s.zeilen))} bereits vorhandenen — und der Abfrageplaner darf `
        + 'sich nicht auf sie stützen.',
      muesste: 'Nachgerechnet hat dieses Werkzeug alle vier: **null Verstösse**. '
        + '`alter table … validate constraint …` kostet einen Tabellendurchlauf und macht aus dem '
        + 'Versprechen eine Garantie. In `setup.sql` und in der Migration gehört `NOT VALID` dann weg.',
      warum: 'Solange die Bedingung unbestätigt ist, kann ein Datenimport, der die Prüfung umgeht '
        + '(`copy` mit ausgeschalteten Auslösern, ein Wiedereinspielen aus einem Abzug), Zeilen '
        + 'hinterlassen, die niemandem auffallen. Ausserdem sieht die Bedingung im Schema aus wie '
        + 'eine echte Zusage — der nächste Leser wird sie dafür halten.',
      beleg: `werkstatt/b_fundament/b4_integritaet.mjs: ${sauber.map(s => `${s.name} → 0/${s.zeilen}`).join(', ')}`,
      groesse: { wert: sauber.length, einheit: 'unbestätigte Zusagen, alle bestätigungsfähig',
                 basis: 'Demodaten, Ausdruck je Bedingung gegen die volle Tabelle gerechnet' },
      gegenrede: 'Für die Richtigkeit der Zahlen von heute ändert das nichts — kein Kilogramm '
        + 'bewegt sich. Es ist eine Zusage über morgen, kein Fehler von heute. Wer den '
        + 'Tabellendurchlauf auf der echten Datenbank scheut, kann `not valid` auch bewusst '
        + 'stehen lassen; dann gehört der Grund als Kommentar daran.',
      aufwand: 'klein',
    }))
  }

  /* --- 2 --- */
  const versuche = alleVersuche(db)
  const gemessene = versuche.filter(v => !v.unpruefbar)
  const ungeschuetzt = gemessene.filter(v => v.groesste > 0 && !v.eindeutige_indexe.length && v.gemeldet === 0)

  raus.push(messung({
    werkstatt: WERKSTATT, titel: 'Was eine doppelt erfasste Zeile in Kilogramm bewegt',
    einheit: 'kg',
    spalten: ['Tabelle', 'Wenn zweimal erfasst wird', 'Verschiebung (kg)',
              'welche Zahlen sich bewegen', 'eindeutiger Schlüssel', 'von der Plausibilitätssicht gemeldet'],
    erklaerung: 'Auf einer Kopie der Demodatenbank wurde je Tabelle die **schwerste** vorhandene '
      + 'Zeile wortgleich ein zweites Mal angelegt und die ganze Auswertung neu gerechnet. Die '
      + 'Spalte „Verschiebung" ist der grösste Unterschied in der Saisonbilanz — also der '
      + 'schlimmste Fall eines einzelnen Tippfehlers, nicht der durchschnittliche. Zu lesen ist '
      + 'die Tabelle als Preisschild, nicht als Verbotsliste: eine zweite Wägung derselben Palette '
      + 'ist ausdrücklich erlaubt und erwünscht. Zeilen mit „nicht prüfbar" stehen hier, weil das '
      + 'Weglassen einer Zeile aus einer Messtabelle wie ein Ergebnis aussähe.',
    zeilen: versuche.map(v => v.unpruefbar ? {
      'Tabelle': v.tabelle + (v.fall ? ` (${v.fall.name})` : ''),
      'Wenn zweimal erfasst wird': v.gleich,
      'Verschiebung (kg)': 'nicht prüfbar',
      'welche Zahlen sich bewegen': v.unpruefbar,
      'eindeutiger Schlüssel': '—',
      'von der Plausibilitätssicht gemeldet': '—',
    } : {
      'Tabelle': v.tabelle + (v.fall ? ` (${v.fall.name})` : ''),
      'Wenn zweimal erfasst wird': v.gleich,
      'Verschiebung (kg)': v.groesste.toFixed(2),
      'welche Zahlen sich bewegen': v.bewegt.map(b => b.zahl.replace(/_kg$/, '')).join(', ') || 'keine',
      'eindeutiger Schlüssel': v.eindeutige_indexe.join(', ') || 'keiner',
      'von der Plausibilitätssicht gemeldet': v.gemeldet > 0 ? `ja (${v.gemeldet})` : 'nein',
    }),
  }))

  if (ungeschuetzt.length) {
    const schlimmster = ungeschuetzt.reduce((a, b) => b.groesste > a.groesste ? b : a)
    const geschuetzt = gemessene.filter(v => v.groesste === 0)
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'INT', klasse: 2, marke: 'Frage an den Betrieb',
      sicherheit: 'hoch',
      ort: { tabelle: [...new Set(ungeschuetzt.map(v => v.tabelle))].join(', ') },
      titel: 'Eine doppelt abgetippte Zeile verschiebt die Bilanz um bis zu '
        + `${Math.round(schlimmster.groesste)} kg, und niemand sagt etwas`,
      steht_da: `In ${new Set(ungeschuetzt.map(v => v.tabelle)).size} von `
        + `${MESSTABELLEN.length} Messtabellen kann dieselbe Beobachtung ein zweites Mal erfasst `
        + 'werden, ohne dass ein eindeutiger Schlüssel es verhindert oder die Plausibilitätssicht '
        + 'es meldet. Nachgemessen auf je einer Kopie der Demodatenbank: eine einzige zusätzliche '
        + `Zeile in \`${schlimmster.tabelle}\` verschiebt die Saisonbilanz um `
        + `${schlimmster.groesste.toFixed(2)} kg — sie bewegt `
        + `${schlimmster.bewegt.map(b => b.zahl.replace(/_kg$/, '')).join(', ')}.`,
      muesste: 'Zwei Wege, und die Wahl gehört dem Betrieb. **Verhindern**: ein eindeutiger '
        + 'Schlüssel über die Spalten, die eine Beobachtung ausmachen — sauber, aber er verbietet '
        + 'auch die legitime Wiederholung. **Melden**: ein Zweig in `v_plausibilitaet`, der '
        + 'wortgleiche Zeilen derselben Tabelle nebeneinanderstellt und fragt „zweimal erfasst oder '
        + 'zweimal gemessen?". Das ist der Weg, den dieses Programm sonst überall geht: beobachten '
        + 'und fragen, statt zu folgern und zu verbieten.',
      warum: 'Am Zettel abtippen passiert in der Halle, unter Zeitdruck, oft von zwei Leuten '
        + 'nacheinander. Eine Doppelung ist kein seltener Sonderfall, sondern der wahrscheinlichste '
        + 'Erfassungsfehler überhaupt — und der einzige aus dieser Familie, den das Programm '
        + 'derzeit nirgends sieht.',
      beleg: 'werkstatt/b_fundament/b4_integritaet.mjs: je Fall eine Kopie der Demodatenbank, die '
        + 'schwerste Zeile wortgleich verdoppelt, `auswertung_aktualisieren()`, Saisonbilanz '
        + 'vorher/nachher; Messreihe „Was eine doppelt erfasste Zeile in Kilogramm bewegt"',
      groesse: { wert: schlimmster.groesste.toFixed(2),
                 einheit: 'kg Bilanzverschiebung aus einer einzigen doppelten Zeile',
                 basis: `${schlimmster.tabelle}, schwerste Zeile der Demodaten` },
      gegenrede: 'Drei Einwände, und alle drei sind ernst zu nehmen. **Erstens** ist eine zweite '
        + 'Wägung derselben Palette kein Fehler, sondern genau das, wofür die Verdunstungsmessung '
        + 'gebaut ist — ein eindeutiger Schlüssel wäre dort schädlich. **Zweitens** ist selbst die '
        + `grösste gemessene Verschiebung (${schlimmster.groesste.toFixed(0)} kg) gegen 323 t `
        + 'Eingang klein; sie fällt in keiner Anzeige auf, verzerrt aber auch nichts, was eine '
        + 'Entscheidung trägt. **Drittens** ist die Gefahr nicht überall gleich: '
        + (geschuetzt.length
            ? `${geschuetzt.map(v => v.tabelle + (v.fall ? ` (${v.fall.name})` : '')).join(', ')} `
              + 'bewegt sich gar nicht, weil dort ein Füllstand und nicht eine Menge erfasst wird — '
              + 'zwei gleiche Füllstände ergeben die Differenz null. Das ist keine Absicht, aber es '
              + 'wirkt. '
            : '')
        + 'Deshalb steht hier eine Frage und keine Reparaturanweisung.',
      aufwand: 'mittel',
    }))
  }

  /* --- 3 --- */
  const doppelt = ueberfluessigeIndexe(db)
  if (doppelt.length) raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'INT', klasse: 1, marke: 'Reduktion', sicherheit: 'hoch',
    ort: { tabelle: doppelt.map(d => d.tabelle).join(', ') },
    titel: `${doppelt.length} Indexe beantworten nur Fragen, die ein anderer Index auch beantwortet`,
    steht_da: doppelt.map(d => `\`${d.name}\` (${d.spalten.join(', ')}${d.bedingung ? ` wo ${d.bedingung}` : ''}) `
      + `— vollständig gedeckt von \`${d.gedeckt_von}\` (${d.gedeckt_spalten})`).join('; ') + '.',
    muesste: 'Der gedeckte Index kann weg. Jede Zeile, die geschrieben wird, muss ihn heute '
      + 'mitpflegen, ohne dass je eine Abfrage ihn braucht.',
    warum: 'Kein Kilogramm hängt daran — aber jeder Index, der nichts kann, was ein anderer nicht '
      + 'auch kann, ist Schreibarbeit bei jedem Erfassungsvorgang und eine Zeile mehr im Schema, '
      + 'die der nächste Leser verstehen muss.',
    beleg: 'werkstatt/b_fundament/b4_integritaet.mjs: Präfixvergleich der Schlüsselspalten samt '
      + 'Teilbedingung und Eindeutigkeit',
    groesse: { wert: Math.round(doppelt.reduce((a, d) => a + Number(d.bytes), 0) / 1024),
               einheit: 'kB Index, die nichts können, was ein anderer nicht auch kann',
               basis: 'Demodaten' },
    gegenrede: 'Ein Index mit Teilbedingung ist kleiner und liegt eher im Arbeitsspeicher; wer '
      + 'sehr viele Zeilen hat, kann ihn absichtlich neben dem allgemeinen halten. Bei den '
      + 'Zeilenzahlen dieses Programms (die grösste Messtabelle hat unter 6000 Zeilen) trägt das '
      + 'Argument nicht.',
    aufwand: 'klein',
  }))

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Drei eingebaute Fehler auf einer Wegwerfkopie, einer je Teil des Werkzeugs:
 *
 *   1. Eine unbestätigte Bedingung, die von den Daten **verletzt** wird —
 *      findet der Zähler den Verstoss, oder zählt er blind null?
 *   2. Ein Index, den ein anderer vollständig deckt.
 *   3. Ein Index, der **nicht** gedeckt ist, obwohl er ähnlich aussieht —
 *      die Gegenprobe gegen ein zu grosszügiges Muster.
 */
export async function selbstprobe() {
  const probe = kopie('demo', 'wk_b4_selbstprobe')
  try {
    tue(probe, `
      alter table charge add column probe_zahl integer;
      update charge set probe_zahl = -1 where nr = (select min(nr) from charge);
      alter table charge add constraint probe_bedingung check (probe_zahl >= 0) not valid;
      create index probe_eng  on lieferung (datum);
      create index probe_weit on lieferung (datum, sorte);
      create index probe_frei on lieferung (kunde);`)

    const offen = unbestaetigt(probe).find(o => o.name === 'probe_bedingung')
    if (!offen || offen.verstoesse !== 1) return false

    const gedeckt = ueberfluessigeIndexe(probe)
    const namen = gedeckt.map(g => g.name)
    if (!namen.includes('probe_eng')) return false      // muss gefunden werden
    if (namen.includes('probe_frei')) return false      // darf nicht gefunden werden
    if (namen.includes('probe_weit')) return false      // der deckende deckt sich nicht selbst

    return true
  } finally {
    wegwerfen(probe)
  }
}
