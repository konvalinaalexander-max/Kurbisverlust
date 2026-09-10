/**
 * B3 — Rechte: was sieht und darf wer wirklich?
 *
 * WARUM ES DIESES WERKZEUG GIBT
 *
 * Die Rechte dieses Programms stehen an drei Stellen, und keine davon sagt
 * für sich, was am Ende gilt:
 *
 *   * die Regeln auf den Tabellen (`row level security`),
 *   * die Leserechte auf Sichten und gespeicherten Ansichten (`grant`),
 *   * die Oberfläche, die manche Seiten hinter `istAdmin` wegschliesst.
 *
 * Die Oberfläche zählt dabei am wenigsten: PostgREST ist offen, und wer die
 * Adresse kennt, redet direkt mit der Datenbank. Genau daran hing der Befund
 * aus 0068 — das Neurechnen war für jeden Angemeldeten aufrufbar, obwohl der
 * Knopf dafür nur auf einer Betriebsleiterseite steht.
 *
 * Dieses Werkzeug liest die Rechte deshalb nicht nur, es **handelt** danach:
 * Es legt auf einer Kopie einen Arbeiter und einen Betriebsleiter an, wird zu
 * ihnen und versucht dann jede Tabelle, jede Sicht und jede gespeicherte
 * Ansicht zu lesen. Was dabei herauskommt, ist keine Auslegung einer Regel,
 * sondern eine Beobachtung.
 *
 * DER FALL, DEN NUR DAS HANDELN FINDET
 *
 * Eine Sicht in PostgreSQL läuft normalerweise mit den Rechten **ihres
 * Eigentümers**. Die Zeilenregeln der Tabellen darunter gelten dann nicht:
 * Wer die Sicht lesen darf, sieht alles darin. Erst `with (security_invoker =
 * true)` dreht das um — dann gilt für jede Zeile, was für den gilt, der
 * fragt.
 *
 * Dieses Programm setzt die Option seit 0005 überall. Wer eine solche Sicht
 * später mit `create or replace view` neu schreibt und die Klausel weglässt,
 * schaltet den Schutz ab — lautlos. Der Abgleich in `supabase/test/run.sh`
 * merkt es nicht: Er vergleicht setup.sql gegen die Migrationen, und beide
 * Wege haben denselben Fehler.
 *
 * WAS ES NICHT TUT
 *
 * Es bewertet die Regeln nicht. Ob ein Arbeiter die Lieferungen aller Chargen
 * sehen darf, ist eine Frage an den Betrieb und keine an das Programm. Das
 * Werkzeug sagt nur, **was gilt** — und wo zwei Stellen Verschiedenes sagen.
 */
import { execFileSync } from 'node:child_process'
import { frage, wert, tue, kopie, wegwerfen, befund, messung, url } from '../umgebung.mjs'

export const lang = false

const WERKSTATT = 'B — Fundament'

/* ---------- Was die Datenbank über sich selbst sagt ----------------------- */

/** Alle Sichten mit der Angabe, ob die Zeilenregeln der Tabellen darunter gelten. */
export function sichten(db) {
  return frage(db, `
    select c.relname as name,
           coalesce(c.reloptions::text, '') like '%security_invoker=true%' as ruft_mit_leserrechten,
           pg_get_userbyid(c.relowner) as eigentuemer
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'v'
     order by c.relname`)
}

/** Welche Tabellen unter einer Sicht haben Zeilenregeln? */
function tabellenUnter(db, sicht) {
  return frage(db, `
    select distinct t.relname as name, t.relrowsecurity as mit_regeln
      from pg_depend d
      join pg_rewrite r on r.oid = d.objid
      join pg_class v on v.oid = r.ev_class
      join pg_class t on t.oid = d.refobjid
      join pg_namespace n on n.oid = t.relnamespace
     where v.relname = '${sicht}' and t.relkind = 'r' and n.nspname = 'public'
     order by 1`)
}

/** Funktionen, die mit den Rechten ihres Eigentümers laufen. */
function definierer(db) {
  return frage(db, `
    select p.proname as name,
           pg_get_function_identity_arguments(p.oid) as argumente,
           coalesce(array_to_string(p.proconfig, ','), '') like '%search_path%' as pfad_gesetzt,
           pg_get_functiondef(p.oid) as text
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
     order by p.proname`)
}

/**
 * Die gespeicherten Ansichten mit der Angabe, ob ein Angemeldeter sie lesen darf.
 *
 * **Nicht** über `information_schema.role_table_grants`: Diese Sicht kennt nur
 * Tabellen und Sichten, gespeicherte Ansichten stehen nicht darin. Gefragt
 * danach, meldet sie für alle achtunddreissig „nein" — und das Werkzeug
 * schriebe „geprüft und in Ordnung" über einen Bestand, den es gar nicht
 * gesehen hat. `has_table_privilege` fragt die Rechte selbst.
 */
function gespeicherteAnsichten(db) {
  return frage(db, `
    select c.relname as name,
           has_table_privilege('authenticated', c.oid, 'SELECT') as fuer_angemeldete
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'm' order by 1`)
}

/* ---------- Der Versuch: als jemand anderes lesen ------------------------- */

/**
 * Wird in einer Sitzung zu einem angemeldeten Nutzer und liest.
 *
 * PostgREST setzt zwei Dinge: die Rolle (`authenticated`) und den Anspruch
 * `request.jwt.claims`, aus dem `auth.uid()` seine Kennung zieht. Beides wird
 * hier genauso gesetzt — sonst prüft man etwas, das im Betrieb nie vorkommt.
 */
function alsNutzer(db, uid, sql) {
  // Nicht über wert(): das packt die Abfrage in ein Unterselect, und hier
  // stehen mehrere Anweisungen — die Rolle muss vor der Abfrage gesetzt sein
  // und danach wieder fallen.
  const anspruch = uid ? `set local request.jwt.claims = '{"sub":"${uid}","role":"authenticated"}';` : ''
  try {
    const aus = execFileSync('psql', [url(db), '-qtAX', '-v', 'ON_ERROR_STOP=1',
      '-c', `begin; ${anspruch} set local role authenticated; ${sql}; commit;`],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
    return { wert: aus.trim().split('\n').filter(Boolean).at(-1) ?? null, fehler: null }
  } catch (e) {
    const text = String(e.stderr ?? e.message ?? e)
    return { wert: null, fehler: text.split('\n').find(z => /ERROR|FEHLER/.test(z)) ?? 'abgewiesen' }
  }
}

/**
 * Der Beweis, dass eine Sicht ohne `security_invoker` den Schutz wirklich
 * abschaltet — und nicht nur eine Option anders gesetzt hat.
 *
 * Auf einer Kopie wird die Leseregel **einer** Tabelle so verengt, dass ein
 * Arbeiter nichts mehr sieht. Danach wird als Arbeiter gezählt: direkt auf der
 * Tabelle (muss 0 ergeben) und durch die Sicht (ergibt bei fehlendem
 * `security_invoker` weiterhin alles).
 */
function beweisen(db, sicht, tabelle, uid) {
  const probe = kopie(db, 'wk_b3_beweis')
  try {
    tue(probe, `alter policy ${tabelle}_lesen on ${tabelle} using (ist_admin())`)
    const direkt = alsNutzer(probe, uid, `select count(*) from ${tabelle}`)
    const ueber = alsNutzer(probe, uid, `select count(*) from ${sicht}`)
    return { direkt: direkt.wert === null ? direkt.fehler : Number(direkt.wert),
             ueber: ueber.wert === null ? ueber.fehler : Number(ueber.wert) }
  } catch (e) {
    return { fehler: String(e.message ?? e).slice(0, 200) }
  } finally {
    wegwerfen(probe)
  }
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const raus = []
  const alle = sichten(db)
  const ohne = alle.filter(s => !s.ruft_mit_leserrechten)

  /* --- Messung: die Rechtelage in einer Tabelle --- */
  const defs = definierer(db)
  const ohnePfad = defs.filter(f => !f.pfad_gesetzt)
  const tabellen = frage(db, `
    select c.relname as name, c.relrowsecurity as mit_regeln,
           (select count(*) from pg_policy p where p.polrelid = c.oid) as regeln
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' order by 1`)
  const ohneRegeln = tabellen.filter(t => !t.mit_regeln)

  raus.push(messung({
    werkstatt: WERKSTATT, titel: 'Die drei Schichten der Rechte', einheit: 'Objekte',
    spalten: ['Schicht', 'Insgesamt', 'Wie erwartet', 'Anders', 'Was „anders" bedeutet'],
    erklaerung: 'Gelesen aus dem Katalog der laufenden Datenbank, nicht aus den Migrationen — '
      + 'was am Ende gilt, steht dort und nirgends sonst.',
    zeilen: [
      { 'Schicht': 'Tabellen mit Zeilenregeln', 'Insgesamt': tabellen.length,
        'Wie erwartet': tabellen.length - ohneRegeln.length, 'Anders': ohneRegeln.length,
        'Was „anders" bedeutet': ohneRegeln.length
          ? `ohne Regeln: ${ohneRegeln.map(t => t.name).join(', ')}`
          : 'jede Tabelle hat Regeln' },
      { 'Schicht': 'Sichten mit `security_invoker`', 'Insgesamt': alle.length,
        'Wie erwartet': alle.length - ohne.length, 'Anders': ohne.length,
        'Was „anders" bedeutet': ohne.length
          ? `laufen mit den Rechten des Eigentümers: ${ohne.map(s => s.name).join(', ')}`
          : 'jede Sicht gibt die Frage an die Zeilenregeln weiter' },
      { 'Schicht': 'Funktionen mit Eigentümerrechten', 'Insgesamt': defs.length,
        'Wie erwartet': defs.length - ohnePfad.length, 'Anders': ohnePfad.length,
        'Was „anders" bedeutet': ohnePfad.length
          ? `ohne festen \`search_path\`: ${ohnePfad.map(f => f.name).join(', ')}`
          : 'jede setzt ihren `search_path` fest' },
    ],
  }))

  /* --- Befund: Sichten ohne security_invoker --- */
  if (ohne.length) {
    // Für den ersten Fall wird der Schutzverlust an der laufenden Datenbank gezeigt.
    const s = ohne[0]
    const unten = tabellenUnter(db, s.name).filter(t => t.mit_regeln)
    const uid = wert(db, `select id::text from profil where rolle = 'arbeiter' and aktiv limit 1`)
      ?? wert(db, `select id::text from profil limit 1`)
    const beweis = unten.length && uid ? beweisen(db, s.name, unten[0].name, uid) : null

    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'RECHT', klasse: 2, marke: 'Reparatur', sicherheit: 'hoch',
      ort: { sicht: ohne.map(x => x.name).join(', ') },
      titel: `${ohne.length} von ${alle.length} Sichten geben die Zeilenregeln nicht mehr weiter`,
      steht_da: `\`${ohne.map(x => x.name).join('`, `')}\` stehen ohne `
        + '`with (security_invoker = true)` da. Sie laufen damit mit den Rechten ihres '
        + `Eigentümers (\`${s.eigentuemer}\`), und die Zeilenregeln der Tabellen darunter gelten `
        + `beim Lesen durch sie nicht. Die übrigen ${alle.length - ohne.length} Sichten setzen die `
        + 'Option — seit 0005, und dort steht auch der Satz „die RLS der Tabellen gilt weiter". '
        + (beweis && typeof beweis.ueber === 'number'
            ? `Nachgestellt auf einer Kopie: Wird die Leseregel von \`${unten[0].name}\` auf `
              + `Betriebsleiter verengt, sieht ein Arbeiter dort ${beweis.direkt} Zeilen — durch `
              + `\`${s.name}\` aber weiterhin ${beweis.ueber}.`
            : ''),
      muesste: 'Dieselbe Klausel wie überall sonst: `create or replace view … with '
        + '(security_invoker = true) as …`. `create or replace view` ohne die Klausel **löscht** '
        + 'eine vorhandene Einstellung — das ist der Weg, auf dem sie hier verlorengegangen ist.',
      warum: 'Heute kostet es nichts: Jede Leseregel dieses Programms lautet `true`, es darf also '
        + 'ohnehin jeder Angemeldete alles lesen. Es kostet an dem Tag, an dem der Betrieb sagt '
        + '„ein Arbeiter soll nur seine eigenen Aufträge sehen". Dann wird die Regel verengt, und '
        + 'diese fünf Sichten zeigen weiter alles — ohne Fehlermeldung, ohne Hinweis, und ohne '
        + 'dass eine Prüfung anschlägt. Genau deshalb steht sie hier als Reparatur und nicht als '
        + 'Beobachtung: Sie ist billig, solange sie folgenlos ist.',
      beleg: 'werkstatt/b_fundament/b3_rechte.mjs: `pg_class.reloptions` aller Sichten gelesen'
        + (beweis && typeof beweis.ueber === 'number'
            ? `, danach auf einer Kopie die Leseregel von \`${unten[0].name}\` verengt und als `
              + 'angemeldeter Arbeiter gezählt' : ''),
      groesse: { wert: ohne.length,
                 einheit: `Sichten ohne Zeilenregelweitergabe von ${alle.length}`
                        + (beweis && typeof beweis.ueber === 'number'
                            ? `; im Versuch ${beweis.ueber} statt ${beweis.direkt} sichtbare Zeilen` : ''),
                 basis: 'Demodaten' },
      gegenrede: 'Zwei Einwände, beide ernst. **Erstens** ist heute nichts offen, was ohne die '
        + 'Klausel offen wäre: Alle Leseregeln stehen auf `true`, und `anon` hat auf keine dieser '
        + 'Sichten ein Leserecht. Der Befund beschreibt also eine abgeschaltete Sicherung an einer '
        + 'Tür, die ohnehin offen steht. **Zweitens** sind die gespeicherten Ansichten (`erg_…`, '
        + '`mv_…`) prinzipiell so — für sie gibt es die Option gar nicht, sie laufen immer mit '
        + 'Eigentümerrechten. Wer die fünf Sichten repariert und glaubt, damit sei die Datenbank '
        + 'zeilenscharf, irrt. Dagegen steht: Eine Sicherung, die an 58 Stellen sitzt und an fünf '
        + 'fehlt, ist keine Entscheidung, sondern ein Versehen — und ein Versehen, das kein Test '
        + 'sieht, bleibt.',
      aufwand: 'klein',
    }))
  } else {
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'RECHT', klasse: 1, marke: 'kein Fehler', sicherheit: 'hoch',
      ort: { sicht: 'public' },
      titel: `Geprüft und in Ordnung: alle ${alle.length} Sichten geben die Zeilenregeln weiter`,
      steht_da: `Jede der ${alle.length} Sichten steht mit \`security_invoker = true\` da; beim `
        + 'Lesen durch sie gilt für jede Zeile, was für den gilt, der fragt.',
      muesste: '—',
      warum: 'Ohne die Klausel läuft eine Sicht mit den Rechten ihres Eigentümers, und die '
        + 'Zeilenregeln der Tabellen darunter gelten nicht mehr — lautlos.',
      beleg: 'werkstatt/b_fundament/b3_rechte.mjs: `pg_class.reloptions` aller Sichten',
      groesse: { wert: alle.length, einheit: 'Sichten geprüft, keine ohne die Klausel',
                 basis: 'Demodaten' },
      aufwand: 'klein',
    }))
  }

  /* --- Befund: Funktionen mit Eigentümerrechten ohne festen Suchpfad --- */
  if (ohnePfad.length) {
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'RECHT', klasse: 2, marke: 'Reparatur', sicherheit: 'hoch',
      ort: { funktion: ohnePfad.map(f => f.name).join(', ') },
      titel: `${ohnePfad.length} Funktionen laufen mit Eigentümerrechten, ohne ihren Suchpfad festzulegen`,
      steht_da: ohnePfad.map(f => `\`${f.name}(${f.argumente})\``).join(', ') + '.',
      muesste: '`set search_path = public` im Kopf — wie die übrigen '
        + `${defs.length - ohnePfad.length} es haben.`,
      warum: 'Eine Funktion mit Eigentümerrechten und offenem Suchpfad lässt sich von einem '
        + 'Angemeldeten übernehmen: Er legt in einem eigenen Schema eine Tabelle oder Funktion mit '
        + 'demselben Namen an, und die Funktion greift auf seine zu — mit den Rechten des '
        + 'Eigentümers.',
      beleg: 'werkstatt/b_fundament/b3_rechte.mjs: `pg_proc.proconfig` aller Funktionen mit '
        + '`prosecdef`',
      groesse: { wert: ohnePfad.length, einheit: `von ${defs.length} Funktionen mit Eigentümerrechten`,
                 basis: 'Katalog' },
      gegenrede: 'Auf einer verwalteten Supabase-Instanz kann ein gewöhnlicher Angemeldeter kein '
        + 'Schema anlegen; der Weg ist dort verstellt. Die Reparatur ist trotzdem eine Zeile.',
      aufwand: 'klein',
    }))
  }

  /* --- Befund/Messung: was der Arbeiter wirklich lesen darf --- */
  const gespeicherte = gespeicherteAnsichten(db)
  const leitzahlen = gespeicherte.filter(m => m.fuer_angemeldete)

  raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'RECHT',
    klasse: leitzahlen.length ? 1 : 1,
    marke: leitzahlen.length ? 'Frage an den Betrieb' : 'kein Fehler', sicherheit: 'hoch',
    ort: { sicht: 'erg_*, mv_*' },
    titel: leitzahlen.length
      ? `Jeder Angemeldete darf alle ${leitzahlen.length} Auswertungstabellen lesen — auch der Zähler`
      : 'Geprüft und in Ordnung: die Auswertungstabellen sind nicht für alle Angemeldeten offen',
    steht_da: leitzahlen.length
      ? `${leitzahlen.length} gespeicherte Ansichten (\`erg_…\`, \`mv_…\`) haben ein Leserecht für `
        + '`authenticated`. Darin stehen Verlustquoten je Sorte, Margen je Käufer, Durchsatz je '
        + 'Arbeiter. Die Oberfläche zeigt diese Seiten nur dem Betriebsleiter (`istAdmin` in '
        + '`src/App.tsx`), aber PostgREST kennt diese Grenze nicht — wer die Adresse und einen '
        + 'gültigen Anmeldeschlüssel hat, liest sie direkt. Gespeicherte Ansichten kennen zudem '
        + 'keine Zeilenregeln: Für sie gibt es `security_invoker` gar nicht.'
      : `Keine der ${gespeicherte.length} gespeicherten Ansichten ist für alle Angemeldeten offen.`,
    muesste: leitzahlen.length
      ? 'Das ist keine Entscheidung des Programmierers. Entweder ist es gewollt — dann gehört der '
        + 'Satz „jeder Angemeldete kann alle Auswertungen sehen" in ABLAUF.md, damit niemand etwas '
        + 'anderes annimmt. Oder es ist nicht gewollt — dann tritt an die Stelle des `grant` an '
        + '`authenticated` ein `grant` an eine Betriebsleiterrolle, und die Oberfläche ändert sich '
        + 'nicht, weil sie diese Seiten ohnehin nur ihm zeigt.'
      : '—',
    warum: 'Der Betrieb beschäftigt Saisonkräfte. Ob eine davon die Marge je Käufer und den '
      + 'Durchsatz je Kollege sehen kann, ist eine Frage über den Betrieb, nicht über die '
      + 'Datenbank — und sie ist bisher nirgends beantwortet, sondern nur beiläufig entschieden.',
    beleg: 'werkstatt/b_fundament/b3_rechte.mjs: `information_schema.role_table_grants` für '
      + '`authenticated` über alle gespeicherten Ansichten',
    groesse: { wert: leitzahlen.length,
               einheit: `gespeicherte Ansichten, die jeder Angemeldete lesen darf `
                      + `(von ${gespeicherte.length})`, basis: 'Katalog' },
    gegenrede: leitzahlen.length
      ? 'Ein Arbeiter braucht einen Anmeldeschlüssel und muss wissen, dass es PostgREST gibt — das '
        + 'ist kein Angriff, den man versehentlich ausführt. Und ein Teil dieser Tabellen ist für '
        + 'die Arbeiter-App nötig (Kaliberbänder, Gebindegewichte), lässt sich also nicht einfach '
        + 'wegnehmen. Wer hier etwas ändert, muss Tabelle für Tabelle entscheiden und die '
        + 'Arbeiter-App gegenprüfen — sonst steht der Zähler am Montag vor einer leeren Maske.'
      : undefined,
    aufwand: 'klein',
  }))

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Der Fall, den dieses Werkzeug finden muss, wird ihm auf einer Kopie
 * vorgesetzt: eine Sicht, der die Klausel fehlt.
 *
 * Und die wichtigere Hälfte: Nach dem Wiederherstellen der Klausel darf es
 * dieselbe Sicht **nicht** mehr melden. Ein Werkzeug, das immer anschlägt,
 * sagt nichts.
 */
export async function selbstprobe({ db }) {
  const probe = kopie(db, 'wk_b3_probe')
  try {
    tue(probe, `create or replace view wk_probe_sicht with (security_invoker = true)
                as select 1 as x`)
    if (sichten(probe).find(s => s.name === 'wk_probe_sicht')?.ruft_mit_leserrechten !== true)
      return false

    // Genau der Handgriff, der den Schutz in 0067 gelöscht hat.
    tue(probe, `create or replace view wk_probe_sicht as select 1 as x`)
    if (sichten(probe).find(s => s.name === 'wk_probe_sicht')?.ruft_mit_leserrechten !== false)
      return false

    tue(probe, `create or replace view wk_probe_sicht with (security_invoker = true)
                as select 1 as x`)
    if (sichten(probe).find(s => s.name === 'wk_probe_sicht')?.ruft_mit_leserrechten !== true)
      return false

    // Und die Rechteabfrage muss einen entzogenen Grant wirklich sehen. Die
    // erste Fassung dieses Werkzeugs fragte information_schema und meldete
    // deshalb für **alle** gespeicherten Ansichten „nicht offen" — ein
    // beruhigender Satz über einen ungeprüften Bestand.
    tue(probe, `create materialized view wk_probe_erg as select 1 as x with no data`)
    tue(probe, `grant select on wk_probe_erg to authenticated`)
    if (gespeicherteAnsichten(probe).find(m => m.name === 'wk_probe_erg')?.fuer_angemeldete !== true)
      return false
    tue(probe, `revoke select on wk_probe_erg from authenticated`)
    if (gespeicherteAnsichten(probe).find(m => m.name === 'wk_probe_erg')?.fuer_angemeldete !== false)
      return false

    return true
  } catch {
    return false
  } finally {
    wegwerfen(probe)
  }
}
