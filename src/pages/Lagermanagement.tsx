import { Fragment, useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useBetriebsmodus } from '../lib/betriebsmodus'
import { imDemoModus } from '../lib/supabase'
import DemoDaten from '../components/DemoDaten'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Erklaerung, Herkunft, Hinweis, Karte, Kennzahl, Leer, Marke, Segmente } from '../components/Bausteine'
import { Glocke, Linien, tonnenAchse, type Reihe } from '../components/Diagramm'
import { kaliberGlockeBei, lagerKaliberBei, lieferungenVon, prognoseBei, useAuswertung, useStichtag, wohinVon,
         type Auswertung, type Bestand, type KaliberGlocke, type LagerKaliber, type Prognose, fehlendeRaten } from '../auswertung/daten'
import { IM_LAGER_TEXT, imLagerBei, palettenIm, palettenText } from '../auswertung/lager'
import { Ungereimtheiten } from '../auswertung/Ungereimtheiten'
import { offenText, summiere } from '../auswertung/ausweis'
import { LagerLeiste, LagerRechnung } from '../auswertung/LagerKette'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { JournalAbgleich } from '../betrieb/JournalAbgleich'
import { useZaehler } from '../design/bewegung'
import { ZWarnung, ZChevron } from '../components/Zeichen'
import { chargenNachFeld } from '../lib/felder'
import { WOCHEN_MAX, WochenFeld } from '../components/WochenFeld'

const TAG = 86400000
/** Wie weit der Betriebsleiter vorausschauen darf: eine Saison. */
const STUFE_G = 50

/** Der Filter dieser Seite: alles, eine Sorte oder eine Charge — kein Schlag. */
interface Filter { gruppe: 'gesamt' | 'sorte' | 'charge'; schluessel: string }

/** Eine Tonnenzahl, die beim Erscheinen zu ihrem Wert läuft. */
function Tonnen({ kg }: { kg: number | null | undefined }) {
  const w = useZaehler(kg)
  return <>{tonnen(w)}</>
}

/**
 * Lagermanagement — der erste Reiter des Betriebsleiters. Er fragt im
 * Tagesgeschäft dasselbe wie am Saisonende, nur anders herum:
 *
 *   „wieviel kürbis ist gerade im lager - aber halt genau - von welcher
 *    sorte von welcher charge … von dem kaliber von der charge ist noch so
 *    viel da - aber mit dem aktuellen verdampfung ist dann nur noch so viel
 *    von dem kaliber übrig weil gewisse in eine andere kalibergrösse fallen"
 *
 * Vier Zahlen, der Verlauf, die Tabelle mit den Kalibern — heute und in X
 * Wochen —, die Glocke. Jede Zahl über die Zukunft ist dieselbe Kaskade,
 * nur an einem späteren Tag ausgewertet: `lager_kaliber(h)` teilt die
 * verkaufsfähige Masse auf die Bänder auf, sonst nichts.
 */
export default function Lagermanagement() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const modus = useBetriebsmodus()
  const [params, setParams] = useSearchParams()

  const filter: Filter = params.get('charge') ? { gruppe: 'charge', schluessel: params.get('charge')! }
    : params.get('sorte') ? { gruppe: 'sorte', schluessel: params.get('sorte')! }
    : { gruppe: 'gesamt', schluessel: '' }
  // Runde AD: Grundeinstellung 0 Wochen — die Tabelle zeigt heute; wer die
  // Wochen ändert, sieht die ganze Tabelle am Stichtag, nicht eine zweite Hälfte.
  const wochen = Math.min(WOCHEN_MAX, Math.max(0, Math.round(Number(params.get('wochen')) || 0)))

  const setzen = (wert: string) => {
    const [g, k] = wert.split('|')
    const neu = new URLSearchParams(params)
    neu.delete('sorte'); neu.delete('charge')
    if (g && k) neu.set(g, k)
    setParams(neu, { replace: true })
  }
  const setzeWochen = (n: number) => {
    const neu = new URLSearchParams(params)
    neu.set('wochen', String(n))
    setParams(neu, { replace: true })
  }

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  const s = daten.saison
  if (!s || daten.bestand.length === 0) {
    return (
      <>
        <Reiterkopf titel="Lagermanagement nach Charge" stand={daten.stand} zeitplan={daten.zeitplan} veraltet={daten.veraltet} aktuell={daten.aktuell} />
        <Probleme liste={daten.probleme} />
        <Hinweis>Noch keine auswertbaren Daten. Dafür braucht es mindestens Eingangspaletten mit hinterlegter Tara — siehe Betrieb → Stammdaten.</Hinweis>
        {/* 0081: Auch im Demo-Modus — dort erklärt die Karte, was der
            Demo-Datenbank noch fehlt, statt zu verschwinden. */}
        {(modus === 'beispiel' || imDemoModus)
          && <DemoDaten kompakt nachAenderung={() => void neuRechnen()} />}
      </>
    )
  }

  return (
    <>
      <Reiterkopf titel="Lagermanagement nach Charge"
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt}
                  zeitplan={daten.zeitplan} veraltet={daten.veraltet} aktuell={daten.aktuell} />
      <JournalAbgleich />
      <Probleme liste={daten.probleme} />
      <Ungereimtheiten daten={daten} />
      {daten.befunde.length > 0 && (
        <div className="hinweis warnung" role="status">
          <span className="hinweis-zeichen"><ZWarnung size={18} /></span>
          <div className="hinweis-text">
            <strong>{daten.befunde.length} Auffälligkeiten</strong> — Messungen, die nicht in die Rechnung eingehen, meist ein Tippfehler.{' '}
            <Link to="/messungen/auffaelligkeiten">Ansehen und korrigieren</Link>
          </div>
        </div>
      )}

      <Filterleiste daten={daten} filter={filter} setzen={setzen} />
      <Kennzahlen daten={daten} filter={filter} />
      <VomLagerZumVerkauf daten={daten} filter={filter} />
      <Verlauf daten={daten} filter={filter} />
      <ImHaus daten={daten} filter={filter} wochen={wochen} setzeWochen={setzeWochen} />
      <Glockenkarte daten={daten} filter={filter} wochen={wochen} setzeWochen={setzeWochen} />
    </>
  )
}

/* ---------- Der Filter: alle, eine Sorte, eine Charge ---------------------- */

function Filterleiste({ daten, filter, setzen }: { daten: Auswertung; filter: Filter; setzen: (w: string) => void }) {
  const sorten = [...new Set(daten.bestand.map(b => b.sorte))].sort((a, b) => a.localeCompare(b, 'de'))
  const felder = chargenNachFeld(daten.bestand)
  const imFilter = chargenIm(daten.bestand, filter)
  const name = filter.gruppe === 'gesamt' ? '' : filter.gruppe === 'charge'
    ? `Charge ${filter.schluessel}` : filter.schluessel
  return (
    <div className="filterleiste haftend">
      <label htmlFor="lager-filter">Ansicht</label>
      <select id="lager-filter" value={filter.gruppe === 'gesamt' ? '' : `${filter.gruppe}|${filter.schluessel}`}
              onChange={e => setzen(e.target.value)}>
        <option value="">alle Chargen</option>
        <optgroup label="Sorte">{sorten.map(x => <option key={x} value={`sorte|${x}`}>{x}</option>)}</optgroup>
        {/* Runde AD: die Chargen nach Feld, darin nach Sorte, dann die Nummer —
            „wichtiger ist Feld und Sorte und dann die Zahl". Das Feld ist die
            Gruppe (fett), die Zeile heisst „Sorte (Nr)" — ohne das Wort Charge (Runde AF). */}
        {felder.map(f => (
          <optgroup key={f.feld} label={f.feld}>
            {f.chargen.map(c => <option key={c.charge_nr} value={`charge|${c.charge_nr}`}>{c.sorte} ({c.charge_nr})</option>)}
          </optgroup>
        ))}
      </select>
      {filter.gruppe !== 'gesamt' && <span className="aktiv-filter">{name}</span>}
      <span>{imFilter.length} {imFilter.length === 1 ? 'Charge' : 'Chargen'} · {imFilter.filter(b => b.lager_kg > 0).length} mit Ware im Haus</span>
      {filter.gruppe !== 'gesamt' && <button type="button" className="werkzeug-knopf" onClick={() => setzen('')}>alle zeigen</button>}
    </div>
  )
}

/**
 * 0121: Vom Lager zum Verkaufsfähigen, Schritt für Schritt (v_lager_ausweis) —
 * der Betrieb: „minus Verdunstung (mit Lagerdauer und täglicher Rate), minus
 * Palox, minus zu klein, zu gross … und vielleicht minus verschenkte Marge.
 * Kommunizier das clever, in Worten." Für die Auswahl oben, über ihre Chargen.
 * 0123: bis zu dem, was als Artikel verkauft werden kann — mit „passt in
 * keinen Artikel" und der Überfüllung als Abzug.
 */
function VomLagerZumVerkauf({ daten, filter }: { daten: Auswertung; filter: Filter }) {
  const nrn = new Set(chargenIm(daten.bestand, filter).map(b => b.charge_nr))
  const s = summiere(daten.ausweis.filter(a => nrn.has(a.charge_nr)))
  if (!(s.eingang > 0)) return null
  return (
    <Karte id="lager-kette" titel="Vom Lager zum Verkaufsfähigen" unter="was im Lager steht, was davon abgeht, was als Artikel verkauft werden kann">
      <LagerRechnung s={s} />
      <Erklaerung titel="Was die Schritte heissen">
        <p><strong>Im Lager</strong>: die Eingangspaletten, die noch dastehen, mit dem Gewicht beim Eingang — vor Verdunstung, Palox und Arbeit.
        <strong> Verdunstet</strong>: Wasser, das die Kürbisse seit dem Eingang verloren haben — gerechnet aus der Lagerdauer und der gewogenen
        Rate je Tag. <strong>Faul (Palox)</strong>: was beim Waschen und Sortieren faul in den Palox geht. <strong>Zu klein / zu gross</strong>: was
        die Sortiermaschine unter dem kleinsten und über dem obersten Band herausnimmt; das Zu-Grosse steht auf den Paletten „+2000 g" und geht in
        einen anderen Kanal. <strong>Passt in keinen Artikel</strong>: die Maschine lässt es durch, aber es ist leichter oder schwerer als die
        Gewichte der Artikel (Coop-Artikeldaten unter Stammdaten) — aus der Sortier-CSV, jeder Kürbis um die gemessene Verdunstung geschrumpft.
        <strong> Überfüllung</strong>: was in den Kisten über dem Sollgewicht mitgeht und nicht bezahlt wird — aus den gewogenen fertigen
        Paletten, auf dem Teil, der als Artikel geht. <strong>Verkaufsfähig</strong> ist, was danach bleibt: was wir als Artikel tatsächlich
        verkaufen können. <strong>Unique</strong> (Hagelware) ist darin — nicht faul, sie wird als Knospe verkauft, wie ein eigener Artikel.
        Ist die Überfüllung einer Charge nicht gewogen oder fehlt ihre Sortier-CSV, steht „höchstens" davor.</p>
      </Erklaerung>
    </Karte>
  )
}

function chargenIm(bestand: Bestand[], f: Filter): Bestand[] {
  if (f.gruppe === 'charge') return bestand.filter(b => String(b.charge_nr) === f.schluessel)
  if (f.gruppe === 'sorte') return bestand.filter(b => b.sorte === f.schluessel)
  return bestand
}

/* ---------- L1: Vier Zahlen ------------------------------------------------ */

function Kennzahlen({ daten, filter }: { daten: Auswertung; filter: Filter }) {
  const w = wohinVon(daten.wohin, filter.gruppe, filter.schluessel)
  const p0 = prognoseBei(daten.prognose, filter.gruppe, filter.schluessel, 0)
  const chargen = chargenIm(daten.bestand, filter)
  const paletten = chargen.reduce((a, b) => a + b.n_paletten, 0)
  const ohneNetto = chargen.reduce((a, b) => a + (b.n_paletten - b.n_paletten_mit_netto), 0)
  // 0114: jeder Lieferschein einmal — die Summe über die Chargen zählte einen
  // ohne Chargennummer einmal je Charge seiner Sorte (und die Datenbank jeden
  // einmal je Eingangstag: „4'836 Lieferungen" bei 1'133).
  const lieferungen = lieferungenVon(daten.lieferungGruppe, filter.gruppe, filter.schluessel)?.n_lieferungen ?? null
  // 23. Oktober: „Im Lager will ich, was wirklich steht — Paletten, bevor wir
  // etwas in den Palox schmeissen, bevor es Arbeiten erlebt, und vor der
  // Verdunstung … und verkaufsfähig das, was wir wirklich verkaufen können."
  // Im Lager: die Eingangspaletten, die noch stehen, mit dem Gewicht beim
  // Eingang. Verkaufsfähig: was davon als Artikel verkauft werden kann
  // (v_lager_ausweis.verkaufbar_kg, 0123) — und der Anteil an genau diesem
  // Lager. Bis hier teilte die Kachel das Verkaufsfähige der Sortiermaschine
  // durch die gute Ware („96 %"), die Leiste darunter rechnete vom Eingang.
  const lager = imLagerBei(daten.prognose, filter.gruppe, filter.schluessel, 0)
  const restPaletten = palettenIm(chargen)
  const nrn = new Set(chargen.map(b => b.charge_nr))
  const kette = summiere(daten.ausweis.filter(a => nrn.has(a.charge_nr)))
  const lagerKg = kette.eingang > 0 ? kette.eingang : lager.kg
  const bekannt = kette.eingang > 0 && kette.luecken < kette.n
  // Offen (Überfüllung nicht gewogen, keine Sortier-CSV): höchstens so viel. Eine Charge ohne Rate fehlt
  // in der Summe ganz — das sagt der Zeiger, nicht „höchstens".
  const hoechstens = !bekannt || kette.offen.size > 0
  const herkunftText = [kette.offen.size > 0 ? `Höchstens, weil noch offen: ${offenText(kette)}` : '',
    kette.luecken > 0 ? `${kette.luecken} von ${kette.n} Chargen fehlen darin — eine Rate ist nicht gemessen` : ''].filter(Boolean).join('. ')
  const anteil = bekannt && lagerKg ? kette.verkaufbar / lagerKg : null
  // Ohne Ausweis (alte Datenbank): die Teile der Kaskade, wie bisher.
  const teile = p0 ? [
    { name: 'verkaufsfähig', kg: p0.verkaufsfaehig_kg, farbe: 'var(--strom-vf)' },
    { name: 'zu klein / zu gross', kg: p0.kanal_kg, farbe: 'var(--strom-ausschuss)' },
    { name: 'faul beim Abpacken', kg: p0.fax_kg, farbe: 'var(--strom-schimmel)' },
  ] : []
  const summe = teile.reduce((a, t) => a + t.kg, 0)

  return (
    <div className="kennzahl-reihe">
      <Kennzahl titel="Eingang" id="kz-eingang"
                wert={<><Tonnen kg={w?.eingang_kg} />{ohneNetto === 0
                  ? <Herkunft art="gemessen" />
                  : <Herkunft art="gerechnet" text={`${ohneNetto} Paletten ohne Nettogewicht — für sie rechnet der Eingang mit dem Mittel der übrigen`} />}</>}
                unter={<>{zahl(paletten)} Paletten</>} />
      <Kennzahl titel="Ausgang" id="kz-ausgang"
                wert={(w?.geliefert_kg ?? 0) > 0 ? <><Tonnen kg={w?.geliefert_kg} /><Herkunft art="gemessen" /></> : '—'}
                unter={(w?.geliefert_kg ?? 0) > 0
                  // Runde AF: Ausgang ist nur der Lieferschein. Zu klein und zu gross,
                  // das beim Sortieren herausfällt, steht im Haus (0101) — nicht hier.
                  ? <>{lieferungen !== null ? <>{zahl(lieferungen)} {lieferungen === 1 ? 'Lieferung' : 'Lieferungen'} ab Lieferschein</> : 'ab Lieferschein'}</>
                  : <>noch kein Warenausgang eingelesen — <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link></>} />
      {/* 0121: zuerst die Paletten — „so viele wirst du im Lager wohl antreffen" —, darunter die Kilo darauf. */}
      <Kennzahl titel="Im Lager" ton="kuerbis" id="kz-lager"
                wert={restPaletten !== null && restPaletten > 0
                  ? <>{palettenText(restPaletten)}<Herkunft art="gerechnet" text="die Eingangspaletten, die noch dastehen: Eingangsmasse, die nicht ausgeliefert ist, durch die mittlere Eingangspalette" /></>
                  : <><Tonnen kg={lagerKg} /><Herkunft art="gerechnet" text={`Im Lager ist ${IM_LAGER_TEXT}`} /></>}
                unter={<>{tonnen(lagerKg)} beim Eingang · vor Verdunstung, Palox und Arbeit</>} />
      <Kennzahl titel="Davon verkaufsfähig" ton="gruen" id="kz-verkaufsfaehig"
                wert={<>
                  {hoechstens && <span className="mini-wort">höchstens </span>}
                  <Tonnen kg={bekannt ? kette.verkaufbar : p0?.verkaufsfaehig_kg} />
                  {anteil !== null && <span className="neben-zahl"> · {prozent(anteil, 0)}</span>}
                  <Herkunft art="gerechnet" text={bekannt && herkunftText ? herkunftText : undefined} /></>}
                unter={<>
                  {/* 0121: dieselbe Leiste wie überall — die Ware, wie sie einging, bis zum Verkaufsfähigen (Schritte darunter). */}
                  {kette.eingang > 0 ? <LagerLeiste s={kette} /> : (
                    <span className="mini-anteile" aria-hidden="true">
                      {teile.filter(t => t.kg > 0).map(t => (
                        <span key={t.name} style={{ width: `${(t.kg / Math.max(summe, 1)) * 100}%`, background: t.farbe }} />
                      ))}
                    </span>)}
                  {anteil === null
                    // Runde AF: der Betrieb fragte „welche Rate?" — hier steht sie, mit dem Weg zum Reiter.
                    ? <>unbekannt, solange {fehlendeRaten(p0).join(', ') || 'eine Rate'} nicht gemessen ist — <Link to="/messungen/ausstehend">Messungen → Ausstehend</Link></>
                    : <>als Artikel verkaufbar — von dem, was im Lager steht</>}
                </>} />
    </div>
  )
}

/* ---------- L2: Die Saison im Verlauf --------------------------------------- */

function Verlauf({ daten, filter }: { daten: Auswertung; filter: Filter }) {
  const k = filter.gruppe === 'gesamt' ? '' : filter.schluessel
  const wochen = daten.verlauf.filter(w => w.gruppe === filter.gruppe && w.schluessel === k)
    .sort((a, b) => a.bis.localeCompare(b.bis))
  if (wochen.length < 2) return null
  const x = (d: string) => Date.parse(d) / TAG
  const heute = x(daten.heute)
  const bisHeute = wochen.filter(w => !w.prognose)
  const xErste = x(wochen[0].woche), xLetzte = x(wochen[wochen.length - 1].bis)
  // Runde AQ: die Achse beginnt mit der ersten Woche, die Ware hatte. Bis hier
  // stand „heute" in der Mitte, und vor dem ersten Eingang lagen Monate leer
  // (beim Betrieb ab April, der erste Eingang war am 3. Juli).
  const xVon = xErste
  // 23. Oktober: Im Lager sind die Paletten vom Eingang, die noch stehen, mit dem Gewicht beim Eingang (lager_kg).
  const imLagerWoche = (w: typeof wochen[number]) => Math.max(Number(w.lager_kg), 0)
  const anteil = (w: typeof wochen[number]) => imLagerWoche(w) > 0 ? w.verkaufsfaehig_kg / imLagerWoche(w) : null
  // Was als Artikel verkauft werden kann, gibt es nur für heute (v_lager_ausweis) — ein Punkt, dieselbe Zahl wie die Kachel.
  const nrn = new Set(chargenIm(daten.bestand, filter).map(b => b.charge_nr))
  const kette = summiere(daten.ausweis.filter(a => nrn.has(a.charge_nr)))
  // Runde AD: „Eingang kumuliert" ist weg — der Eingang steht als Zahl in der
  // Kennzahl oben; als Linie war er ausgeblendet und hat nur die Legende gefüllt.
  const reihen: Reihe[] = [
    // Runde V: Orange gegen Blau statt Orange gegen Grün — das Paar, das
    // auch bei Rot-Grün-Schwäche zwei Linien bleibt. Der Ausgang ist
    // Umgebung, kein Vergleich, und steht darum in Grau.
    { name: 'Ausgang kumuliert', farbe: 'var(--text-leise)', linie: true, marker: false,
      punkte: bisHeute.map(w => ({ x: x(w.bis), y: w.ausgang_kum_kg })) },
    // Runde AO: „Im Lager" endet heute wie der Ausgang; vorhergesagt wird nur,
    // was davon verkaufsfähig bleibt. 23. Oktober: Im Lager ist wieder die
    // Eingangsmasse der Paletten, die noch stehen — der Betrieb will sehen,
    // was dasteht, vor Verdunstung, Palox und Arbeit.
    { name: 'Im Lager', farbe: 'var(--kuerbis)', linie: true, marker: false, dick: true,
      punkte: bisHeute.map(w => ({ x: x(w.bis), y: imLagerWoche(w) })) },
    // 0123: die Linie ist das, was die Sortiermaschine durchlässt — über die Wochen gerechnet. Was davon
    // in die Artikelgewichte passt und ohne Überfüllung bleibt, steht heute als Punkt daneben.
    { name: 'nach der Sortiermaschine verkaufsfähig', farbe: 'var(--blau)', linie: true, marker: false, dick: true, prognoseAb: heute,
      punkte: wochen.map(w => ({ x: x(w.bis), y: w.verkaufsfaehig_kg,
        text: `${prozent(anteil(w), 0)} von dem, was im Lager steht · zu klein/zu gross ${tonnen(w.kanal_kg)}${w.aussortiert_kg > 0 ? ` · dazu ${tonnen(w.aussortiert_kg)} schon aussortiert, in Paloxen im Haus` : ''}` })) },
    ...(kette.eingang > 0 && kette.luecken < kette.n ? [{ name: 'verkaufsfähig als Artikel, heute', farbe: 'var(--strom-vf)', marker: true, form: 'raute' as const,
      punkte: [{ x: heute, y: kette.verkaufbar,
        text: `${kette.offen.size > 0 ? 'höchstens ' : ''}${tonnen(kette.verkaufbar)} — ohne, was in kein Artikelgewicht passt, und ohne Überfüllung (die Kachel oben)` }] }] : []),
  ]
  return (
    <Karte id="lager-verlauf" titel="Die Saison im Verlauf">
      <Linien reihen={reihen} heute={{ x: heute, text: `heute, ${datum(daten.heute).slice(0, 6)}`, rechts: 'so ginge es weiter' }}
              xVon={xVon} xBis={xLetzte} hoehe={320} xKalender={0}
              xFormat={d => `Woche bis ${datum(new Date(d * TAG)).slice(0, 6)}`} yFormat={tonnenAchse}
              yTitel="Tonnen" yEinheit="kg"
              fuss={<span className="leise">verkaufsfähig ab heute gestrichelt: wenn die liegende Ware liegen bleibt</span>} />
      <Erklaerung>
        <p>Eingang und Ausgang sind <Herkunft art="gemessen" /> und enden heute.
        <strong> Im Lager</strong> ist, was an diesem Stichtag an Paletten vom Eingang dastand, mit dem Gewicht beim Eingang — es fällt
        mit jeder Lieferung und endet heute. <strong>Nach der Sortiermaschine verkaufsfähig</strong> ist <Herkunft art="gerechnet" />: ohne
        Verdunstetes, Faules und zu klein / zu gross; es fällt auch dann weiter, wenn nichts geliefert wird — die liegende Ware altert.
        Der Punkt heute ist, was davon als Artikel verkauft werden kann: ohne, was in kein Artikelgewicht passt, und ohne Überfüllung
        (dieselbe Zahl wie die Kachel oben).</p>
      </Erklaerung>
    </Karte>
  )
}

/* ---------- Die Bänder einer Gruppe ----------------------------------------- */

/** Runde AO: −1 ist Unterkaliber (zu klein), −2 Überkaliber (zu gross). */
const UNTER = -1, UEBER = -2

interface Bandzeile {
  schluessel: string; name: string; unter: string; sorte: string
  /** Im Lager am Stichtag: die Paletten vom Eingang, die noch stehen, mit dem Gewicht beim Eingang (src/auswertung/lager.ts); null, wenn die Prognose fehlt. */
  lager: number | null; paletten: number | null; verkaufsfaehig: number; anteil: number | null
  basis: string; nKuerbis: number | null
  /** Kilo je Kaliber-Index; UNTER und UEBER daneben — leer heisst nicht gemessen. */
  kg: Map<number, number | null>
  band: Map<number, string>
  /** Der Teil des kleinsten Bandes, der seit der Sortierung darunter geschrumpft ist. */
  geschrumpft: number | null
}

/** Aus den Zeilen von `lager_kaliber(h)` die Zeilen der Tabelle — „im Lager" aus der Prognose beim selben Horizont. */
function bandzeilen(zeilen: LagerKaliber[], filter: Filter, bestand: Bestand[], prognose: Prognose[], h: number): Bandzeile[] {
  const gruppe = filter.gruppe === 'gesamt' ? 'sorte' : 'charge'
  const chargen = new Map(bestand.map(b => [String(b.charge_nr), b]))
  const map = new Map<string, Bandzeile>()
  for (const z of zeilen) {
    if (z.gruppe !== gruppe) continue
    if (filter.gruppe === 'sorte' && z.sorte !== filter.schluessel) continue
    if (filter.gruppe === 'charge' && z.schluessel !== filter.schluessel) continue
    if (!(z.lager_kg > 0)) continue
    let e = map.get(z.schluessel)
    if (!e) {
      const c = gruppe === 'charge' ? chargen.get(z.schluessel) : undefined
      e = {
        schluessel: z.schluessel,
        name: gruppe === 'charge' ? `Charge ${z.schluessel}` : z.schluessel,
        unter: gruppe === 'charge' ? `${z.sorte}${c ? ` · ${c.schlag}` : ''}` : `${z.n_chargen} ${z.n_chargen === 1 ? 'Charge' : 'Chargen'}`,
        sorte: z.sorte, lager: imLagerBei(prognose, gruppe, z.schluessel, h).kg, verkaufsfaehig: z.verkaufsfaehig_kg, anteil: null,
        paletten: gruppe === 'charge' ? (c?.n_rest_paletten ?? null) : palettenIm(bestand.filter(b => b.sorte === z.schluessel)),
        basis: z.basis, nKuerbis: z.n_kuerbis, kg: new Map(), band: new Map(), geschrumpft: z.geschrumpft_kg,
      }
      map.set(z.schluessel, e)
    }
    if (z.klasse === 'unter' || z.klasse === 'ueber') {
      // Zu klein / zu gross: eine Zahl je Zeile, leer, solange nicht gemessen.
      e.kg.set(z.klasse === 'unter' ? UNTER : UEBER, z.kg)
    } else if (z.kaliber_idx !== null) {
      e.kg.set(z.kaliber_idx, (e.kg.get(z.kaliber_idx) ?? 0) + (z.kg ?? 0))
      if (z.band_von !== null && z.band_bis !== null) e.band.set(z.kaliber_idx, `${z.band_von}–${z.band_bis} g`)
    }
    // Der Anteil am Lager gehört der Zeile, nicht dem Band.
    e.anteil = e.lager !== null && e.lager > 0 ? e.verkaufsfaehig / e.lager : null
  }
  return [...map.values()].sort((a, b) => (b.lager ?? 0) - (a.lager ?? 0))
}

/** Welche Bänder die Tabelle hat: die, die irgendeine Zeile trägt. */
function bandspalten(zeilen: Bandzeile[]): { idx: number; kopf: string; unter: string }[] {
  const idxe = [...new Set(zeilen.flatMap(z => [...z.kg.keys()]))].filter(i => i >= 0).sort((a, b) => a - b)
  return idxe.map(i => {
    const baender = [...new Set(zeilen.map(z => z.band.get(i)).filter(Boolean))] as string[]
    return { idx: i, kopf: baender.length === 1 ? baender[0] : `Kaliber ${i + 1}`, unter: baender.length === 1 ? '' : 'je Sorte eigene Grenzen' }
  })
}

/* ---------- L3: Was ist noch im Haus? --------------------------------------- */

function ImHaus({ daten, filter, wochen, setzeWochen }: {
  daten: Auswertung; filter: Filter; wochen: number; setzeWochen: (n: number) => void
}) {
  // Runde AD: EINE Tabelle am Stichtag — heute (0 Wochen) oder in X Wochen.
  // Vorher standen heute und der Stichtag nebeneinander, doppelt so breit,
  // mit Rollbalken im Block. Jetzt ändert das Wochenfeld die ganze Tabelle.
  const stand = useStichtag(lagerKaliberBei, 7 * wochen)
  const zeilen = useMemo(() => bandzeilen(stand.zeilen, filter, daten.bestand, daten.prognose, 7 * wochen),
                         [stand.zeilen, filter, daten.bestand, daten.prognose, wochen])
  const spalten = bandspalten(zeilen)
  const stichtag = stand.zeilen[0]?.datum ?? null
  const spaeter = wochen > 0
  const jeSorte = filter.gruppe === 'gesamt'
  // Eine Sorte aufklappen: ihre Chargen darunter, aus derselben Rechnung.
  const [auf, setAuf] = useState<Set<string>>(new Set())
  const umschalten = (k: string) => setAuf(a => { const n = new Set(a); if (n.has(k)) n.delete(k); else n.add(k); return n })
  const chargenVon = (sorte: string) => bandzeilen(stand.zeilen, { gruppe: 'sorte', schluessel: sorte }, daten.bestand, daten.prognose, 7 * wochen)
  const summe = (f: (z: Bandzeile) => number) => zeilen.reduce((a, z) => a + f(z), 0)
  const summePaletten = palettenIm(daten.bestand.filter(b => zeilen.some(z => jeSorte ? z.sorte === b.sorte : z.schluessel === String(b.charge_nr))))
  const herkunft = spaeter ? 'prognose' : 'gerechnet'

  return (
    <Karte id="lager-tabelle" titel="Was ist noch im Haus?"
           aktion={<WochenFeld id="lager-wochen" wochen={wochen} setzen={setzeWochen} datum={spaeter ? stichtag : null} />}>
      {stand.fehler && <Hinweis art="warnung">Die Kaliber konnten nicht geladen werden: {stand.fehler}</Hinweis>}
      {zeilen.length === 0 && !stand.laedt
        ? <Leer titel="Nichts im Lager">Sobald wieder Ware liegt, steht hier, in welchem Kaliber sie liegt.</Leer>
        : (
        <div className="rollbar">
          <table className={`dicht umbruch lagertabelle${stand.laedt ? ' laedt' : ''}`}>
            <thead>
              <tr>
                {/* Die Herkunftsmarke steht im Kopf: bis heute gerechnet, oder
                    über heute hinaus — je nach Wochenfeld die ganze Tabelle. */}
                <th rowSpan={2} className="haftend">{jeSorte ? 'Sorte' : 'Charge'}</th>
                <th rowSpan={2} className="zahl" title={`Im Lager ist ${IM_LAGER_TEXT}`}>im Lager<Herkunft art={herkunft} /></th>
                {/* Runde AP, Wunsch des Betriebs: im Lager, die Kaliber, gesamt
                    verkaufsfähig — dann, was nicht ins Band passt: zu klein, zu gross.
                    „gesamt" enthält beide nicht. 0123: hier nach der Sortiermaschine —
                    die Artikelgewichte und die Überfüllung zieht die Kachel oben ab. */}
                <th colSpan={spalten.length + 1} className={`gruppe${spaeter ? ' spaeter' : ''}`}>
                  nach der Sortiermaschine verkaufsfähig {spaeter ? `in ${wochen} Wochen` : 'heute'}
                  {spaeter && stichtag ? <span className="leise"> · {datum(stichtag).slice(0, 6)}</span> : null}
                  <Herkunft art={herkunft} />
                </th>
                <th rowSpan={2} className="zahl neben-kaliber erste">zu klein<span className="kopf-unter">unter Kaliber</span></th>
                <th rowSpan={2} className="zahl neben-kaliber">zu gross<span className="kopf-unter">über Kaliber</span></th>
              </tr>
              <tr>
                {spalten.map(sp => <th key={sp.idx} className="zahl">{sp.kopf}</th>)}
                <th className="zahl summe">gesamt<span className="kopf-unter">ohne zu klein, zu gross</span></th>
              </tr>
            </thead>
            <tbody>
              {zeilen.map(z => (
                <Fragment key={z.schluessel}>
                  <tr className={jeSorte ? `klickbar sorte-zeile${auf.has(z.schluessel) ? ' offen' : ''}` : undefined}
                      onClick={jeSorte ? () => umschalten(z.schluessel) : undefined} aria-expanded={jeSorte ? auf.has(z.schluessel) : undefined}>
                    <th scope="row" className="haftend">
                      {jeSorte && <span className="chevron" aria-hidden="true"><ZChevron size={14} /></span>}
                      <span className="zeilenname">{z.name}</span>
                      <span className="zeilenunter leise">{z.unter}</span>
                      {z.basis === 'sorte' && <Marke art="neutral" punkt={false}>aus der Sorte</Marke>}
                    </th>
                    <td className="zahl"><strong>{masse(z.lager)}</strong>
                      {z.paletten !== null && <span className="zelle-unter">{palettenText(z.paletten)}</span>}</td>
                    {spalten.map(s => <Bandzelle key={s.idx} zeile={z} idx={s.idx} filter={filter} spaeter={spaeter} />)}
                    <td className="zahl summe"><strong>{masse(z.verkaufsfaehig)}</strong>
                      {z.anteil !== null && <span className="leise"> {prozent(z.anteil, 0)}</span>}</td>
                    <Nebenzelle zeile={z} idx={UNTER} spaeter={spaeter} />
                    <Nebenzelle zeile={z} idx={UEBER} spaeter={spaeter} />
                  </tr>
                  {jeSorte && auf.has(z.schluessel) && chargenVon(z.sorte).map(c => (
                    <tr key={c.schluessel} className="charge-zeile">
                      <th scope="row" className="haftend">
                        <span className="zeilenname">{c.name}</span>
                        <span className="zeilenunter leise">{c.unter}</span>
                      </th>
                      <td className="zahl">{masse(c.lager)}{c.paletten !== null && <span className="zelle-unter">{palettenText(c.paletten)}</span>}</td>
                      {spalten.map(s => <Bandzelle key={s.idx} zeile={c} idx={s.idx} filter={{ gruppe: 'sorte', schluessel: z.sorte }} spaeter={spaeter} />)}
                      <td className="zahl summe">{masse(c.verkaufsfaehig)}{c.anteil !== null && <span className="leise"> {prozent(c.anteil, 0)}</span>}</td>
                      <Nebenzelle zeile={c} idx={UNTER} spaeter={spaeter} />
                      <Nebenzelle zeile={c} idx={UEBER} spaeter={spaeter} />
                    </tr>
                  ))}
                </Fragment>
              ))}
            </tbody>
            {zeilen.length > 1 && (
              <tfoot>
                <tr>
                  <th scope="row" className="haftend">Summe</th>
                  <td className="zahl"><strong>{masse(summe(z => z.lager ?? 0))}</strong>
                    {summePaletten !== null && <span className="zelle-unter">{palettenText(summePaletten)}</span>}</td>
                  {spalten.map(s => <td key={s.idx} className="zahl"><strong>{masse(summe(z => z.kg.get(s.idx) ?? 0))}</strong></td>)}
                  <td className="zahl summe"><strong>{masse(summe(z => z.verkaufsfaehig))}</strong></td>
                  <td className="zahl neben-kaliber erste">{nebenSumme(zeilen, UNTER)}</td>
                  <td className="zahl neben-kaliber">{nebenSumme(zeilen, UEBER)}</td>
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      )}
      <p className="hilfe">
        Im Lager = die Paletten vom Eingang, die noch stehen, mit dem Gewicht beim Eingang. Die Bänder sind die Kaliber der
        Sortiermaschine; was davon als Artikel verkauft werden kann, steht oben in der Kachel und unter Artikel.
      </p>
      <Erklaerung>
        <p><strong>Im Lager</strong> ist, was an Paletten vom Eingang noch dasteht, mit dem Gewicht beim Eingang <Herkunft art="gerechnet" />:
        die Eingangsware, die nicht ausgeliefert ist — vor Verdunstung, Palox und Arbeit. Die Paletten darunter sind die Eingangspaletten, die
        noch da sind; ohne Lieferung bleibt ihre Zahl auch in ein paar Wochen gleich.
        <strong> Verkaufsfähig</strong> heisst hier: nach der Sortiermaschine — ohne Verdunstetes, Faules und was zu klein oder zu gross ist,
        verteilt auf die Bänder der Maschine. Was davon in kein Artikelgewicht passt und was als Überfüllung in den Kisten mitgeht, zieht erst
        die Kachel oben ab („Vom Lager zum Verkaufsfähigen").</p>
        <p><strong>Zu klein</strong> (unter dem kleinsten Kaliber) und <strong>zu gross</strong> (über dem grössten) sind der gemessene Anteil der Sorte an der liegenden Ware:
        aus den Sortierläufen und den Handmessungen beim Waschen und Sortieren. Ist er für eine Sorte noch nicht gemessen, steht ein Strich — unbekannt, nicht null.</p>
        <p>Die Bänder sind keine zweite Rechnung: Jeder Kürbis der Sortier-CSV wird um die gemessene Verdunstung seiner Charge
        geschrumpft und neu in sein Band gelegt; die Massenanteile der Bänder mal der verkaufsfähigen Masse ergeben die Kilo.
        Wer seit der Sortierung knapp unter das kleinste Band geschrumpft ist, zählt weiter im kleinsten Band — ein sortierter
        Kürbis bleibt in seiner Kiste (der Zeiger über der Zahl sagt, wie viel es ist).</p>
        <p>„aus der Sorte" heisst: Diese Charge hat keine eigene Sortier-CSV — sie bekommt die Verteilung aller
        sortierten Kürbisse ihrer Sorte. Fehlt auch die, bleiben die Bänder leer: unbekannt, nicht null.</p>
      </Erklaerung>
    </Karte>
  )
}

/** Masse kurz: Tonnen ab einer Tonne, darunter Kilo. */
const masse = (v: number | null | undefined) =>
  v === null || v === undefined ? '—' : v >= 1000 ? tonnen(v) : kg(v, 0)

function Bandzelle({ zeile, idx, filter, laedt = false, spaeter = false }: {
  zeile: Bandzeile | undefined; idx: number; filter: Filter; laedt?: boolean; spaeter?: boolean
}) {
  const klasse = `zahl${spaeter ? ' spaeter' : ''}${laedt ? ' laedt' : ''}`
  if (!zeile) return <td className={klasse}>—</td>
  if (zeile.basis === 'keine') {
    return <td className={klasse} title="keine Sortier-CSV für diese Sorte — die Verteilung ist unbekannt, nicht null">—</td>
  }
  const wert = zeile.kg.get(idx)
  if (wert === undefined || wert === null) return <td className={klasse} />
  const band = zeile.band.get(idx)
  const kleinstes = idx === Math.min(...[...zeile.kg.keys()].filter(i => i >= 0))
  const darunter = kleinstes && (zeile.geschrumpft ?? 0) >= 1
    ? ` · davon ${kg(zeile.geschrumpft, 0)} seit der Sortierung knapp unter ${band?.split('–')[0] ?? 'das Band'} g geschrumpft`
    : ''
  return (
    <td className={klasse} title={`${band ?? ''} · ${zeile.sorte}${darunter}`}>
      {masse(wert)}
      {band && filter.gruppe === 'gesamt' && <span className="band-unter">{band}</span>}
    </td>
  )
}

/** Unter- oder Überkaliber einer Zeile: gemessen, sonst ein Strich. */
function Nebenzelle({ zeile, idx, spaeter = false }: { zeile: Bandzeile; idx: number; spaeter?: boolean }) {
  const klasse = `zahl neben-kaliber${idx === UNTER ? ' erste' : ''}${spaeter ? ' spaeter' : ''}`
  const wert = zeile.kg.get(idx)
  const was = idx === UNTER ? 'zu klein' : 'zu gross'
  if (wert === undefined || wert === null) {
    return <td className={klasse} title={`${was} ist für ${zeile.sorte} noch nicht gemessen — unbekannt, nicht null`}>—</td>
  }
  return (
    <td className={klasse} title={idx === UNTER
      ? `zu klein für das kleinste Band — geht an die Tiere (gemessener Anteil der Sorte)`
      : `zu gross für das grösste Band — anderer Kanal (gemessener Anteil der Sorte)`}>
      {masse(wert)}
    </td>
  )
}

/** Die Summe einer Nebenspalte — ein Strich, sobald eine Zeile unbekannt ist. */
function nebenSumme(zeilen: Bandzeile[], idx: number): string {
  let s = 0
  for (const z of zeilen) {
    const w = z.kg.get(idx)
    if (w === undefined || w === null) return '—'
    s += w
  }
  return masse(s)
}

/* ---------- L4: Wie schwer sind die Kürbisse? -------------------------------- */

function Glockenkarte({ daten, filter, wochen, setzeWochen }: {
  daten: Auswertung; filter: Filter; wochen: number; setzeWochen: (n: number) => void
}) {
  const [wann, setWann] = useState<'heute' | 'spaeter'>('heute')
  // Runde AD: bei 0 Wochen gibt es nur „heute" — der Umschalter fällt weg.
  const h = wann === 'heute' || wochen === 0 ? 0 : 7 * wochen
  const glocke = useStichtag(kaliberGlockeBei, h)
  const kaliber = useStichtag(lagerKaliberBei, h)
  const [sorte, setSorte] = useState('')

  // Eine Glocke zeigt eine Sorte: die Bänder sind je Sorte andere, und eine
  // Kurve über alle Sorten wäre eine Zahl, die es nicht gibt.
  const gruppe = filter.gruppe === 'charge' ? 'charge' : 'sorte'
  const schluessel = filter.gruppe === 'charge' ? filter.schluessel
    : filter.gruppe === 'sorte' ? filter.schluessel
    : (sorte || groessteSorte(glocke.zeilen, daten.bestand))
  const zeilen = glocke.zeilen.filter(z => z.gruppe === gruppe && z.schluessel === schluessel)
  const sorten = [...new Set(daten.bestand.filter(b => b.lager_kg > 0).map(b => b.sorte))].sort((a, b) => a.localeCompare(b, 'de'))

  const stufen = zeilen.map(z => ({ x: z.stufe_g, n: z.n_kuerbis ?? 0 })).sort((a, b) => a.x - b.x)
  const gesamt = stufen.reduce((a, s) => a + s.n, 0)
  const mittel = gesamt > 0 ? stufen.reduce((a, s) => a + (s.x + STUFE_G / 2) * s.n, 0) / gesamt : null
  const basis = zeilen[0]?.basis ?? 'keine'
  const stichtag = zeilen[0]?.datum ?? null

  // Die Grenzen und die Anteile kommen aus derselben Rechnung wie die Tabelle.
  const bandzeilenH = kaliber.zeilen.filter(z => z.gruppe === gruppe && z.schluessel === schluessel)
  const grenzen = [...new Map(bandzeilenH.filter(z => z.band_von !== null)
    .map(z => [z.band_von!, { x: z.band_von!, text: `K${(z.kaliber_idx ?? 0) + 1}` }])).values()].sort((a, b) => a.x - b.x)
  const unterstes = grenzen[0]?.x ?? null
  const anteile = bandzeilenH.filter(z => z.klasse === 'kaliber' && z.kaliber_idx !== null && (z.anteil ?? 0) > 0.001)
    .sort((a, b) => (a.kaliber_idx ?? 0) - (b.kaliber_idx ?? 0))
  // Runde AO: was unter das kleinste Band geschrumpft ist, zählt dort mit — als Anteil gesagt.
  const ersteZeile = bandzeilenH[0]
  const darunter = ersteZeile && ersteZeile.geschrumpft_kg !== null && ersteZeile.verkaufsfaehig_kg > 0
    ? ersteZeile.geschrumpft_kg / ersteZeile.verkaufsfaehig_kg : null

  return (
    <Karte id="lager-glocke" titel="Wie schwer sind die Kürbisse?"
           aktion={<span className="reihe">
             {wochen > 0 && <Segmente wahl={wann} setzen={setWann} id="glocke-umschalter"
                       teile={[['heute', 'heute', 'glocke-heute'], ['spaeter', `in ${wochen} Wochen`, 'glocke-spaeter']]} />}
             <WochenFeld id="glocke-wochen" wochen={wochen} setzen={setzeWochen} datum={wann === 'spaeter' && wochen > 0 ? stichtag : null} />
           </span>}>
      {filter.gruppe === 'gesamt' && sorten.length > 1 && (
        <div className="filterleiste">
          <label htmlFor="glocke-sorte">Sorte</label>
          <select id="glocke-sorte" value={schluessel} onChange={e => setSorte(e.target.value)}>
            {sorten.map(x => <option key={x} value={x}>{x}</option>)}
          </select>
        </div>
      )}
      {glocke.fehler && <Hinweis art="warnung">Die Glocke konnte nicht geladen werden: {glocke.fehler}</Hinweis>}
      {stufen.length === 0
        ? <Leer titel="Keine Sortier-CSV">Sobald ein Sortierlauf eingelesen ist, steht hier die Glocke.</Leer>
        : (
        <>
          <Glocke stufen={stufen} breite={STUFE_G} grenzen={grenzen} hoehe={200}
                  xFormat={x => `${x}`} mittel={mittel}
                  klassenfarbe={x => unterstes !== null && x + STUFE_G <= unterstes ? 'var(--text-leise)' : 'var(--kuerbis)'} />
          <p className="leise">
            {zahl(gesamt)} gewogen{wann === 'heute' || wochen === 0
              ? <Herkunft art="gemessen" text="die Gewichte aus der Sortier-CSV" />
              : <Herkunft art="gerechnet" text="dieselben Kürbisse, um die Verdunstung bis zum Stichtag leichter" />}
            {' · '}{basis === 'charge' ? 'eigene Messung' : basis === 'sorte' ? 'aus der Sorte' : 'gemischt'}
            {mittel !== null && <> · Schwerpunkt {Math.round(mittel)} g</>}
            {anteile.map(z => <span key={z.kaliber_idx}> · K{(z.kaliber_idx ?? 0) + 1} {prozent(z.anteil, 0)}</span>)}
            {darunter !== null && darunter >= 0.005 && unterstes !== null &&
              <span> · {prozent(darunter, 0)} inzwischen unter {unterstes} g (grau, zählen in K1)</span>}
          </p>
        </>
      )}
      <Erklaerung titel="Was die Glocke sagt">
        Dieselben Kürbisse wie in der Tabelle darüber, nur in 50-Gramm-Stufen statt in Bändern — und am selben Stichtag.
        Bezahlt wird je Stück innerhalb eines Kalibers: Wer weiss, wo eine Sorte liegt, kann ein engeres Band liefern.
        Mit der Lagerdauer wandert die Glocke nach links; was unter das kleinste Band fällt, ist grau — in der Tabelle zählt es
        weiter im kleinsten Band, denn ein sortierter Kürbis bleibt in seiner Kiste.
      </Erklaerung>
    </Karte>
  )
}

/** Ohne Wahl: die Sorte mit der meisten liegenden Ware. */
function groessteSorte(zeilen: KaliberGlocke[], bestand: Bestand[]): string {
  const je = new Map<string, number>()
  for (const b of bestand) if (b.lager_kg > 0) je.set(b.sorte, (je.get(b.sorte) ?? 0) + b.lager_kg)
  const sortiert = [...je.entries()].sort((a, b) => b[1] - a[1])
  for (const [s] of sortiert) if (zeilen.some(z => z.gruppe === 'sorte' && z.schluessel === s)) return s
  return sortiert[0]?.[0] ?? ''
}
