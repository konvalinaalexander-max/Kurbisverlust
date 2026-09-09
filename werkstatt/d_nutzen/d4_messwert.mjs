/**
 * D4 — Was eine Messung bringt.
 *
 * DIE FRAGE
 *
 * Jede Zahl dieses Programms ist mit Arbeiterzeit bezahlt. Eine
 * Lagerkontroll-Wägung heisst: Stapler holen, Palette auf die Waage, ablesen,
 * eintippen, zurückstellen. Eine Palox-Ablesung heisst: hinsehen, eintippen.
 * Ein Sortierlauf mit CSV kostet fast nichts, weil die Maschine ihn ohnehin
 * schreibt.
 *
 * Der Betrieb hat also längst eine Investitionsentscheidung getroffen, ohne je
 * die Rendite zu sehen: **Welche dieser Messungen nimmt am meisten
 * Unsicherheit weg — je Messung und je Minute?**
 *
 * Diese Zahl hat ihm noch niemand gesagt. Sie ist die Grundlage für den Satz
 * „davon macht mehr" und für den Satz „das könnt ihr weglassen" — und der
 * zweite ist für einen Betrieb in der Erntezeit mehr wert als der erste.
 *
 * WIE GEMESSEN WIRD
 *
 * Nicht durch Nachdenken über Formeln. Je Messart wird auf einer Kopie der
 * Datenbank **alles gelöscht, was diese Messart je erfasst hat**, die volle
 * Auswertung neu gerechnet und nachgesehen, wie viel weiter die Bänder danach
 * sind. Der Unterschied, geteilt durch die Zahl der Messungen, ist ihr Ertrag.
 *
 * Das ist absichtlich grob: Es misst den Ertrag der Messart als Ganzes, nicht
 * den der einundvierzigsten Wägung. Der Grenzertrag ist kleiner als der
 * Durchschnitt — beides steht in der Tabelle, damit niemand das eine für das
 * andere hält.
 *
 * DREI ANTWORTEN SIND MÖGLICH, UND ALLE DREI ZÄHLEN
 *
 *   Das Band wird weiter  — die Messung trägt. Um wie viel, steht da.
 *   Das Band bleibt gleich — die Messung trägt zu dieser Zahl nichts bei.
 *                            Das ist kein Fehler der Messung; vielleicht
 *                            trägt sie woanders. Aber es ist eine Auskunft.
 *   Die Zahl verschwindet  — ohne diese Messung kann das Programm gar nichts
 *                            mehr sagen. Das ist der höchste Ertrag von allen
 *                            und lässt sich nicht in Kilogramm ausdrücken.
 *
 * DIE MINUTEN SIND EINE ANNAHME
 *
 * Wie lange eine Messung in der Halle dauert, weiss dieses Werkzeug nicht. Die
 * Zahlen unten sind geschätzt und stehen deshalb **als eigene Spalte** da, nicht
 * eingerechnet und versteckt. Wer sie korrigiert, ändert eine Zeile in dieser
 * Datei und bekommt die Rangfolge neu. Die Spalte „je Messung" ist von der
 * Annahme unberührt.
 */
import { frage, tue, kopie, rechne, wegwerfen, befund, messung } from '../umgebung.mjs'

export const lang = true

const WERKSTATT = 'D — Nutzen'

/**
 * Die Messarten, wie der Arbeiter sie kennt — nicht wie die Tabellen heissen.
 *
 * `minuten` ist geschätzt und ausdrücklich zur Korrektur durch den Betrieb
 * gedacht; `wegdamit` ist die Anweisung, die diese Messart aus der Datenbank
 * entfernt, ohne etwas anderes anzurühren.
 */
const MESSARTEN = [
  { name: 'Lagerkontroll-Wägung', minuten: 6,
    was: 'Palette aus dem Lager holen, wiegen, Wiegedatum und Gewicht eintippen, zurückstellen',
    zaehlen: 'select count(*) from verdunstung_wiegung',
    wegdamit: 'delete from verdunstung_wiegung' },

  { name: 'Palox-Ablesung', minuten: 1,
    was: 'beim Leeren oder Beginnen den Stand der Palox-Waage ablesen und eintippen',
    zaehlen: 'select count(*) from schimmel_messung where palox_stand_kg is not null',
    wegdamit: 'delete from schimmel_messung where palox_stand_kg is not null' },

  { name: 'Schimmel-Kistenwägung', minuten: 3,
    was: 'die Kiste mit Faulem wiegen und die Kistenzahl eintragen',
    zaehlen: 'select count(*) from schimmel_messung where palox_stand_kg is null',
    wegdamit: 'delete from schimmel_messung where palox_stand_kg is null' },

  { name: 'Ausschuss-Wägung', minuten: 3,
    was: 'die Kiste mit zu Kleinem oder zu Grossem wiegen',
    zaehlen: 'select count(*) from ausschuss_messung',
    wegdamit: 'delete from ausschuss_messung' },

  { name: 'Sortierlauf (CSV)', minuten: 2,
    was: 'die Datei der Sortiermaschine hochladen — die Maschine schreibt sie ohnehin',
    zaehlen: 'select count(*) from sortier_lauf',
    wegdamit: 'delete from sortier_gewicht; delete from sortier_lauf' },

  { name: 'fertige Palette wiegen', minuten: 4,
    was: 'die fertig gepackte Palette auf die Waage stellen und wiegen',
    zaehlen: 'select count(*) from ausgang_wiegung',
    wegdamit: 'delete from ausgang_wiegung' },

  { name: 'Palette mit Zettelgewicht zählen', minuten: 1,
    was: 'das Gewicht vom Palettenzettel abtippen, statt nur die Palette zu zählen',
    zaehlen: 'select count(*) from auftrag_palette where brutto_zettel_kg is not null',
    wegdamit: 'update auftrag_palette set brutto_zettel_kg = null' },
]

/**
 * Woran gemessen wird: die Breite der Verlustbänder — aber **nur über die
 * Ströme, die in beiden Läufen überhaupt ein Band haben**.
 *
 * Das ist keine Feinheit, sondern der Unterschied zwischen einer Messung und
 * einer Zahl, die in die falsche Richtung zeigt. Die erste Fassung dieses
 * Werkzeugs summierte einfach alle Bänder. Fällt beim Löschen einer Messart
 * ein Strom ganz aus, verschwindet auch sein Band aus der Summe — und dann
 * wird die Summe **kleiner**, obwohl das Programm weniger weiss. Drei der
 * sieben Messarten kamen so mit negativem Ertrag heraus: „ohne diese Messung
 * sind wir uns sicherer". Das ist offensichtlich Unsinn, und es wäre ohne die
 * Gegenprobe im Bericht gelandet.
 *
 * Verglichen wird deshalb nur die gemeinsame Schnittmenge, und die verstummten
 * Ströme werden getrennt gezählt.
 */
const BAND = `
  select strom, (kg_oben - kg_unten)::float8 / 2 as halb
    from v_verlust_je_gruppe where gruppe = 'gesamt'`

const SAISON = `select ((verlust_oben_kg - verlust_unten_kg) / 2)::float8 as halb,
                       verlust_heute_kg::float8 as verlust from v_saisonbilanz`

const bandkarte = (db) => Object.fromEntries(frage(db, BAND)
  .map(z => [z.strom, z.halb === null ? null : Number(z.halb)]))

function messen(db, art) {
  const n = Number(frage(db, art.zaehlen)[0].count)
  const probe = kopie(db, 'wk_d4_ertrag')
  try {
    const vorher = bandkarte(probe)
    const vorherS = frage(probe, SAISON)[0]
    tue(probe, art.wegdamit)
    rechne(probe)
    const nachher = bandkarte(probe)
    const nachherS = frage(probe, SAISON)[0]

    // Nur Ströme, die vorher und nachher eine Zahl haben, sind vergleichbar.
    const gemeinsam = Object.keys(vorher)
      .filter(k => vorher[k] !== null && (nachher[k] ?? null) !== null)
    const summeVorher = gemeinsam.reduce((a, k) => a + vorher[k], 0)
    const summeNachher = gemeinsam.reduce((a, k) => a + nachher[k], 0)
    const verstummt = Object.keys(vorher)
      .filter(k => vorher[k] !== null && (nachher[k] ?? null) === null)

    return { ...art, n,
      band_vorher: summeVorher, band_nachher: summeNachher, n_vergleichbar: gemeinsam.length,
      saison_vorher: vorherS.halb, saison_nachher: nachherS.halb,
      verlust_vorher: vorherS.verlust, verlust_nachher: nachherS.verlust,
      gewinn: summeNachher - summeVorher,
      verstummt: verstummt.length, verstummte: verstummt }
  } finally {
    wegwerfen(probe)
  }
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const gemessen = MESSARTEN.map(a => messen(db, a)).filter(a => a.n > 0)
  const raus = []

  const jeMessung = (a) => a.n > 0 ? a.gewinn / a.n : 0
  const jeMinute  = (a) => a.n > 0 && a.minuten > 0 ? a.gewinn / (a.n * a.minuten) : 0

  const rang = [...gemessen].sort((x, y) =>
    (y.verstummt - x.verstummt) || (jeMinute(y) - jeMinute(x)))

  raus.push(messung({
    werkstatt: WERKSTATT,
    titel: 'Was jede Messart an Unsicherheit wegnimmt',
    einheit: 'kg Bandbreite',
    spalten: ['Messart', 'Anzahl', 'Minuten je Messung (Annahme)', 'verglichene Ströme',
              'Bänder ohne sie (± kg)', 'Bänder mit ihr (± kg)', 'nimmt weg (kg)',
              'je Messung (kg)', 'je Arbeiterminute (kg)', 'Ströme, die ohne sie verstummen'],
    erklaerung: 'Je Messart wurde auf einer Kopie der Demodatenbank **alles gelöscht, was diese '
      + 'Messart je erfasst hat**, die volle Auswertung neu gerechnet und die Summe der sechs '
      + 'Verlustbänder verglichen — und zwar **nur über die Ströme, die in beiden Läufen ein Band '
      + 'haben**. Fällt ein Strom ohne diese Messart ganz aus, verschwände sonst auch sein Band '
      + 'aus der Summe, und weniger Wissen käme als engeres Band heraus. „Nimmt weg" ist die '
      + 'Differenz über die gemeinsamen Ströme: um so viel enger sind die Bänder, weil es diese '
      + 'Messungen gibt. Die Spalte ganz rechts nennt die Ströme, über die das '
      + 'Programm ohne diese Messart **gar nichts** mehr sagen kann — das ist der höchste Ertrag '
      + 'und lässt sich nicht in Kilogramm ausdrücken, deshalb steht er getrennt. Die Minuten sind '
      + 'geschätzt und stehen als eigene Spalte da, damit der Betrieb sie korrigieren kann, ohne '
      + 'dass die übrigen Zahlen sich ändern.',
    zeilen: rang.map(a => ({
      'Messart': a.name, 'Anzahl': a.n, 'Minuten je Messung (Annahme)': a.minuten,
      'verglichene Ströme': a.n_vergleichbar,
      'Bänder ohne sie (± kg)': a.band_nachher.toFixed(0),
      'Bänder mit ihr (± kg)': a.band_vorher.toFixed(0),
      'nimmt weg (kg)': a.gewinn.toFixed(0),
      'je Messung (kg)': jeMessung(a).toFixed(1),
      'je Arbeiterminute (kg)': jeMinute(a).toFixed(1),
      'Ströme, die ohne sie verstummen': a.verstummt ? a.verstummte.join(', ') : '—',
    })),
  }))

  raus.push(messung({
    werkstatt: WERKSTATT,
    titel: 'Was jede Messart am Ergebnis selbst verschiebt',
    einheit: 'kg',
    spalten: ['Messart', 'Saisonverlust ohne sie (kg)', 'mit ihr (kg)', 'Unterschied (kg)'],
    erklaerung: 'Dieselben Läufe, andere Frage: Nicht wie **sicher** die Zahl wird, sondern wie '
      + 'sie sich **verschiebt**. Eine Messart, ohne die derselbe Verlust herauskäme, bestätigt '
      + 'nur; eine, die ihn merklich verschiebt, korrigiert eine Annahme — und ist damit auch '
      + 'dann wertvoll, wenn sie die Bänder nicht enger macht.',
    zeilen: rang.map(a => ({
      'Messart': a.name,
      'Saisonverlust ohne sie (kg)': a.verlust_nachher === null
        ? 'die Zahl verschwindet' : a.verlust_nachher.toFixed(0),
      'mit ihr (kg)': a.verlust_vorher?.toFixed(0) ?? '—',
      'Unterschied (kg)': a.verlust_nachher === null || a.verlust_vorher === null
        ? 'nicht vergleichbar' : (a.verlust_nachher - a.verlust_vorher).toFixed(0),
    })),
  }))

  /* --- Der Befund: die Rangliste selbst --- */
  const beste = rang[0]
  const teuerste = [...gemessen].filter(a => !a.verstummt)
    .sort((x, y) => jeMinute(x) - jeMinute(y))[0]
  const stunden = gemessen.reduce((a, m) => a + m.n * m.minuten, 0) / 60

  raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'ERT', klasse: 2, marke: 'Entscheidung des Betriebs',
    sicherheit: 'mittel', ort: { datei: 'docs/ABLAUF.md' },
    titel: 'Die Rangfolge der Messungen nach Ertrag gibt es — sie stand nur nirgends',
    steht_da: `Der Betrieb erfasst ${gemessen.reduce((a, m) => a + m.n, 0)} Messungen in `
      + `${gemessen.length} Arten und wendet dafür nach der Annahme dieses Werkzeugs rund `
      + `${stunden.toFixed(0)} Arbeitsstunden je Saison auf. Was jede davon einbringt, hat bisher `
      + 'niemand ausgerechnet. Gemessen: '
      + rang.slice(0, 3).map(a => `**${a.name}** — ${a.verstummt
          ? `${a.verstummt} Ströme verstummen ohne sie`
          : `${jeMinute(a).toFixed(1)} kg Bandbreite je Arbeiterminute`}`).join(', ')
      + (teuerste ? `. Am wenigsten bringt **${teuerste.name}** mit `
          + `${jeMinute(teuerste).toFixed(1)} kg je Minute.` : '.'),
    muesste: 'Diese Tabelle gehört dem Betrieb, nicht diesem Bericht. Zwei Dinge folgen daraus: '
      + 'Der Betrieb kann entscheiden, **wovon er mehr macht** — und, was schwerer wiegt, wovon '
      + 'er in der Erntezeit weniger machen darf, ohne dass eine Auskunft verlorengeht. Vorher '
      + 'muss er allerdings die Minutenspalte korrigieren: Die Zahlen dort sind geschätzt, und '
      + 'die Rangfolge hängt an ihnen.',
    warum: 'In der Erntezeit ist Arbeiterzeit die knappste Grösse des Betriebs. Eine Messung, die '
      + 'in dieser Zeit gemacht wird und nichts einbringt, ist nicht neutral — sie geht auf Kosten '
      + 'einer anderen. Ohne diese Tabelle wird nach Gefühl entschieden, und das Gefühl folgt '
      + 'meist dem Aufwand, nicht dem Ertrag.',
    beleg: 'werkstatt/d_nutzen/d4_messwert.mjs: je Messart eine Kopie der Demodatenbank, alle '
      + 'Zeilen dieser Art gelöscht, `auswertung_aktualisieren()`, Bandbreiten vorher/nachher',
    groesse: { wert: stunden.toFixed(0),
               einheit: 'Arbeitsstunden je Saison, deren Ertrag bisher unbeziffert war',
               basis: `${gemessen.length} Messarten, Demodaten, Minuten geschätzt` },
    gegenrede: 'Zwei Einwände, beide ernst. **Erstens** misst dieses Verfahren den Ertrag der '
      + 'Messart als Ganzes, nicht den der nächsten einzelnen Messung. Der Grenzertrag fällt, und '
      + 'zwar ungefähr mit der Wurzel: Die einundvierzigste Wägung bringt weniger als die erste. '
      + 'Wer aus dieser Tabelle „doppelt so viele Wägungen, halb so breites Band" liest, irrt. '
      + '**Zweitens** stehen und fallen die Minutenzahlen mit einer Schätzung, die niemand aus '
      + 'dem Betrieb bestätigt hat — deshalb ist dieser Befund als Entscheidung des Betriebs '
      + 'markiert und nicht als Reparatur.',
    aufwand: 'klein',
  }))

  /* --- Wovon mehr: die ertragreichste Messung, die niemand für kritisch hält --- */
  const unkritisch = gemessen.filter(a => !a.verstummt)
    .sort((x, y) => jeMinute(y) - jeMinute(x))
  if (unkritisch.length >= 2) {
    const oben = unkritisch[0], unten = unkritisch[unkritisch.length - 1]
    const stundenOben = oben.n * oben.minuten / 60
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'ERT', klasse: 2, marke: 'Entscheidung des Betriebs',
      sicherheit: 'mittel', ort: { datei: 'docs/ABLAUF.md' },
      titel: `Die ertragreichste Messung ist zugleich eine der seltensten: ${oben.name}`,
      steht_da: `\`${oben.name}\` wird ${oben.n} Mal erfasst — rund ${stundenOben.toFixed(1)} `
        + `Arbeitsstunden in der ganzen Saison — und nimmt ${oben.gewinn.toFixed(0)} kg Bandbreite `
        + `weg, also ${jeMessung(oben).toFixed(0)} kg je einzelner Wägung. Am anderen Ende steht `
        + `\`${unten.name}\` mit ${unten.n} Erfassungen `
        + `(${(unten.n * unten.minuten / 60).toFixed(1)} Arbeitsstunden) und `
        + `${jeMessung(unten).toFixed(1)} kg je Erfassung. Zwischen den beiden liegt Faktor `
        + `${Math.abs(jeMessung(oben) / (jeMessung(unten) || 0.01)).toFixed(0)}.`,
      muesste: 'Das ist keine Programmänderung, sondern eine Frage an die Halle: Lässt sich von '
        + `\`${oben.name}\` mehr machen, ohne dass anderes liegenbleibt? Die Antwort kennt nur `
        + 'der Betrieb. Was das Programm dazu beitragen kann, ist der Hinweis an der richtigen '
        + 'Stelle — die Maske, die eine solche Wägung anbietet, könnte sagen, was sie wert ist.',
      warum: 'Wer nicht weiss, welche Messung was einbringt, verteilt seine Zeit nach Aufwand '
        + 'statt nach Ertrag. Genau das ist hier passiert: Die aufwendigste Messart bindet '
        + `${Math.max(...gemessen.map(a => a.n * a.minuten / 60)).toFixed(0)} Stunden, die `
        + 'ertragreichste unter zwei.',
      beleg: 'werkstatt/d_nutzen/d4_messwert.mjs, Messreihe „Was jede Messart an Unsicherheit wegnimmt"',
      groesse: { wert: jeMessung(oben).toFixed(0),
                 einheit: `kg Bandbreite je einzelner ${oben.name}`,
                 basis: `${oben.n} Erfassungen, Demodaten` },
      gegenrede: 'Der hohe Ertrag je Messung kann gerade **daher** kommen, dass es so wenige '
        + 'gibt: Die ersten Messungen einer Art bringen immer am meisten, und der Grenzertrag '
        + 'fällt ungefähr mit der Wurzel. Verdoppelte man die Zahl, bliebe vermutlich weniger als '
        + 'die Hälfte des Ertrags je Stück übrig. Die Rangfolge kippt dadurch aber nicht — dafür '
        + 'ist der Abstand zu gross.',
      aufwand: 'klein',
    }))
  }

  /* --- Wovon weniger: Messungen ohne messbare Wirkung --- */
  const grundband = gemessen[0]?.band_vorher ?? 1
  const stumm = gemessen.filter(a => !a.verstummt
    && Math.abs(a.gewinn) / grundband < 0.005
    && Math.abs((a.verlust_nachher ?? 0) - (a.verlust_vorher ?? 0)) / (a.verlust_vorher || 1) < 0.005)
  if (stumm.length) raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'ERT', klasse: 2, marke: 'Frage an den Betrieb',
    sicherheit: 'hoch', ort: { datei: 'docs/ABLAUF.md' },
    titel: `${stumm.length} Messart(en) kosten Arbeiterzeit, ohne eine Zahl der Auswertung messbar `
         + 'zu ändern',
    steht_da: stumm.map(a => `**${a.name}**: ${a.n} Erfassungen, rund `
      + `${(a.n * a.minuten / 60).toFixed(1)} Arbeitsstunden je Saison. Ohne sie ändert sich der `
      + `Saisonverlust um ${((a.verlust_nachher ?? 0) - (a.verlust_vorher ?? 0)).toFixed(0)} kg `
      + `von ${a.verlust_vorher?.toFixed(0)} kg, und die Summe der Bänder um `
      + `${a.gewinn.toFixed(0)} kg von ${a.band_vorher.toFixed(0)} kg — beides unter einem halben `
      + 'Prozent. Kein Strom verstummt.').join(' '),
    muesste: 'Zwei Möglichkeiten, und nur der Betrieb kennt die richtige. Entweder die Messung '
      + 'dient etwas anderem als der Verlustrechnung — Rückverfolgbarkeit, Abrechnung, Kontrolle '
      + 'des Arbeitsablaufs. Dann gehört dieser Zweck aufgeschrieben, damit sie nicht eines Tages '
      + 'als nutzlos gestrichen wird. Oder sie ist für die Verlustrechnung gedacht und **kommt '
      + 'dort nicht an** — dann ist nicht die Messung das Problem, sondern die Rechnung, die sie '
      + 'nicht liest.',
    warum: 'Die zweite Möglichkeit ist die gefährlichere: Wer etwas erfasst, das nirgends '
      + 'ankommt, erfasst es irgendwann schlampig — und niemand merkt es, weil es ohnehin '
      + 'nirgends ankommt. Bei der Palette mit Zettelgewicht wäre das besonders bitter, weil '
      + 'dieselbe Zahl an anderer Stelle sehr wohl gebraucht wird.',
    beleg: 'werkstatt/d_nutzen/d4_messwert.mjs, beide Messreihen dieser Werkstatt',
    groesse: { wert: (stumm.reduce((a, m) => a + m.n * m.minuten, 0) / 60).toFixed(1),
               einheit: 'Arbeitsstunden je Saison ohne messbare Wirkung auf eine Zahl',
               basis: 'Demodaten' },
    gegenrede: 'Auf den Demodaten, und das ist eine ernste Einschränkung. Eine Messart kann genau '
      + 'dann nichts beitragen, wenn eine andere dasselbe schon sagt — in einer Saison, in der die '
      + 'andere fehlt, wäre sie die einzige Quelle. Ausserdem misst dieses Werkzeug nur die '
      + 'Wirkung auf die Verlustrechnung; eine Zahl, die im Arbeitsablauf gebraucht wird, taucht '
      + 'hier gar nicht auf. Bevor irgendetwas weggelassen wird, gehört dieselbe Messung auf '
      + 'echten Daten mehrerer Saisons wiederholt.',
    aufwand: 'klein',
  }))

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Der eingebaute Fall: Eine Messart, von der nachweislich etwas abhängt.
 *
 * Gelöscht werden **alle** Lagerkontroll-Wägungen. Danach kann das Programm die
 * Verdunstungsrate aus nichts mehr schätzen; die Bänder müssen weiter werden
 * oder ein Strom muss verstummen. Passiert weder das eine noch das andere, misst
 * dieses Werkzeug nicht, was es zu messen vorgibt — und dann sind auch seine
 * Nullen nichts wert.
 *
 * Die Gegenprobe dazu: Ein Löschen, das **nichts** trifft (eine Bedingung, auf
 * die keine Zeile passt), darf sich nicht als Ertrag niederschlagen. Sonst
 * fände das Werkzeug überall Wirkung, auch wo keine ist.
 */
export async function selbstprobe({ db = 'demo' } = {}) {
  const wirkung = messen(db, {
    name: 'Probe', minuten: 1, zaehlen: 'select count(*) from verdunstung_wiegung',
    wegdamit: 'delete from verdunstung_wiegung',
  })
  if (wirkung.gewinn <= 0 && wirkung.verstummt <= 0) return false

  const ohne = messen(db, {
    name: 'Probe ohne Wirkung', minuten: 1,
    zaehlen: 'select count(*) from verdunstung_wiegung',
    wegdamit: "delete from verdunstung_wiegung where charge_nr = -999999",
  })
  if (Math.abs(ohne.gewinn) > 0.01 || ohne.verstummt !== 0) return false

  return true
}
