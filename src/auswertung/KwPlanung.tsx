import { useMemo, useState } from 'react'
import { kg, tonnen, zahl } from '../lib/format'
import { Herkunft, Karte, Leer } from '../components/Bausteine'
import { Mehrwahl, type MehrwahlGruppe } from '../components/Mehrwahl'
import type { KundeGruppe, KundeTag } from './daten'
import type { GruppeRang } from './artikel'
import { gruppeWahl, kundeWahl, kundenDerWahl, kundenGruppen, kwName, kwTabelle, saisonVon, tagPlus, wocheMontag, wochenDerSaison, wochenText,
         type KwArtikel, type KwKundengruppe, type KwTabelle } from './kw'

/**
 * KW-Planung (Runde BL) — unten im Lagermanagement nach Artikel.
 *
 *   „Wir wollen einfach nachschauen, wie viel lief in den letzten KWs nach
 *    Kunde und Produkt. … Artikel ist egal, es geht nur um Kunde. Kunde und
 *    KW. … Erste Spalte Produkt, die nächsten Spalten die KWs, die ausgesucht
 *    sind, rechts davon Summe. … Wenn ich mehrere Kunden anklicke, machst du
 *    zwei Tabellen untereinander. … dass man ganze Kategorien anklicken kann
 *    oder nur einzelne Kunden innerhalb der Kategorien."
 *
 * Der Block folgt nicht der Artikelwahl oben: gewählt wird hier, wer und
 * wann. Die Zahlen sind die Positionen der Perigon-Dateien — alle, die die
 * Datenbank hat (lib/seiten.ts), nach Kalenderwoche zusammengezählt.
 */

const SCHLUESSEL = 'artikel.kw'
/** Ohne eigene Wahl: die laufende Woche und die drei davor. */
const VORGABE_WOCHEN = 4

interface Gemerkt { kunden: string[]; wochen: string[] | null }
function gemerktLesen(): Gemerkt {
  try {
    const g = JSON.parse(localStorage.getItem(SCHLUESSEL) ?? 'null') as Partial<Gemerkt> | null
    if (g && Array.isArray(g.kunden) && g.kunden.every(k => typeof k === 'string')
        && (g.wochen === null || (Array.isArray(g.wochen) && g.wochen.every(w => typeof w === 'string'))))
      return { kunden: g.kunden, wochen: g.wochen ?? null }
  } catch { /* privates Fenster */ }
  return { kunden: [], wochen: null }
}

const masse = (v: number) => Math.abs(v) >= 1000 ? tonnen(v) : kg(v, 0)
const labelName = (l: string | null) => l === 'D' ? 'Demeter' : l === 'K' ? 'Knospe' : 'Label unbekannt'
const groesseName = (g: string) => g === 'stueck' ? 'je Stück' : g === 'lose' ? 'lose' : g
const tagKurz = (d: string) => `${Number(d.slice(8, 10))}.${Number(d.slice(5, 7))}.`

export function KwPlanung({ kunden, kundeGruppe, gruppenRang, heute }: {
  kunden: KundeTag[]; kundeGruppe: KundeGruppe[]; gruppenRang: GruppeRang[]; heute: string
}) {
  const saison = saisonVon(heute)
  const wochen = useMemo(() => wochenDerSaison(kunden, saison, heute), [kunden, saison, heute])
  const gruppen = useMemo(() => kundenGruppen(kunden, saison, new Map(kundeGruppe.map(k => [k.kunde, k.gruppe])), gruppenRang),
                          [kunden, saison, kundeGruppe, gruppenRang])
  const [gemerkt, setGemerktRoh] = useState<Gemerkt>(gemerktLesen)
  const setGemerkt = (g: Gemerkt) => {
    setGemerktRoh(g)
    try { localStorage.setItem(SCHLUESSEL, JSON.stringify(g)) } catch { /* privates Fenster */ }
  }

  // Was es in dieser Saison gibt, in der Reihenfolge der Liste: je Gruppe erst die ganze Gruppe, dann ihre Kunden.
  const folge = useMemo(() => gruppen.flatMap(g => [gruppeWahl(g.name), ...g.kunden.map(k => kundeWahl(k.name))]), [gruppen])
  const gewaehlteKunden = useMemo(() => { const s = new Set(gemerkt.kunden); return folge.filter(w => s.has(w)) }, [gemerkt.kunden, folge])
  const letzte = useMemo(() => wochen.slice(-VORGABE_WOCHEN), [wochen])
  const gewaehlteWochen = useMemo(() => {
    if (gemerkt.wochen === null) return letzte
    const s = new Set(gemerkt.wochen)
    return wochen.filter(w => s.has(w))
  }, [gemerkt.wochen, wochen, letzte])
  const mitJahr = new Set(wochen.map(w => w.slice(0, 4))).size > 1

  const kundenListe: MehrwahlGruppe[] = gruppen.map(g => ({
    titel: g.name, wahl: gruppeWahl(g.name),
    wahlText: <>alle {g.kunden.length} zusammen · {masse(g.kg)}</>,
    eintraege: g.kunden.map(k => ({ schluessel: kundeWahl(k.name), name: k.name, unter: masse(k.kg) })),
  }))
  const wochenListe: MehrwahlGruppe[] = [{
    eintraege: [...wochen].reverse().map(w => {
      const montag = wocheMontag(w)
      const sonntag = tagPlus(montag, 6)
      return { schluessel: w, name: kwName(w, mitJahr), unter: `${tagKurz(montag)}–${tagKurz(sonntag)}${w === wochen[wochen.length - 1] ? ' · diese Woche' : ''}` }
    }),
  }]

  const kundenText = gewaehlteKunden.length === 0 ? 'Kunden wählen'
    : gewaehlteKunden.length <= 2 ? gewaehlteKunden.map(w => w.slice(2)).join(', ')
    : `${gewaehlteKunden.length} gewählt`
  const wText = wochenText(gewaehlteWochen, wochen)

  return (
    <Karte id="kw-planung" titel="KW-Planung: was ging in welcher Woche an wen?"
           unter={<>Lieferungen der Saison {saison}/{String(saison + 1).slice(2)} aus den Perigon-Dateien, je Kunde und Kalenderwoche —
                    unabhängig von der Artikelwahl oben. <Herkunft art="gemessen" text="jede Position der Perigon-Dateien, nach Kalenderwoche zusammengezählt" /></>}>
      {wochen.length === 0 ? <Leer titel="In dieser Saison ist noch nichts geliefert." /> : (
        <>
          <div className="filterleiste kw-wahl" id="kw-wahl">
            <span className="wahl-teil"><span id="kw-kunden-name">Kunden</span>
              <Mehrwahl id="kw-kunden" name="Kunden" text={kundenText} gewaehlt={new Set(gewaehlteKunden)} gruppen={kundenListe}
                        setzen={n => setGemerkt({ ...gemerkt, kunden: [...n] })}
                        kurzwahl={[{ name: 'jede Gruppe', id: 'kw-kunden-gruppen', wahl: () => gruppen.map(g => gruppeWahl(g.name)) },
                                   { name: 'keine', id: 'kw-kunden-keine', wahl: () => [] }]} />
            </span>
            <span className="wahl-teil"><span id="kw-wochen-name">Kalenderwochen</span>
              <Mehrwahl id="kw-wochen" name="Kalenderwochen" text={wText} gewaehlt={new Set(gewaehlteWochen)} gruppen={wochenListe}
                        setzen={n => setGemerkt({ ...gemerkt, wochen: [...n] })}
                        kurzwahl={[{ name: `die letzten ${VORGABE_WOCHEN}`, id: 'kw-wochen-letzte', wahl: () => letzte },
                                   { name: `alle ${wochen.length}`, id: 'kw-wochen-alle', wahl: () => wochen },
                                   { name: 'keine', id: 'kw-wochen-keine', wahl: () => [] }]} />
            </span>
          </div>
          {gewaehlteKunden.length === 0 && <Leer titel="Kunden wählen">Oben einen Kunden oder eine ganze Gruppe anklicken — je Auswahl steht hier eine Tabelle.</Leer>}
          {gewaehlteKunden.length > 0 && gewaehlteWochen.length === 0 && <Leer titel="Kalenderwoche wählen">Oben mindestens eine Woche anklicken.</Leer>}
          {gewaehlteWochen.length > 0 && gewaehlteKunden.map((w, i) => (
            <KwBlock key={w} nr={i} wahl={w} gruppen={gruppen} zeilen={kunden} wochen={gewaehlteWochen} alleWochen={wochen} saison={saison} mitJahr={mitJahr} />
          ))}
        </>
      )}
    </Karte>
  )
}

function KwBlock({ nr, wahl, gruppen, zeilen, wochen, alleWochen, saison, mitJahr }: {
  nr: number; wahl: string; gruppen: KwKundengruppe[]; zeilen: KundeTag[]; wochen: string[]; alleWochen: string[]; saison: number; mitJahr: boolean
}) {
  const wer = useMemo(() => kundenDerWahl(wahl, gruppen), [wahl, gruppen])
  const t: KwTabelle = useMemo(() => kwTabelle(zeilen, wer, wochen, saison), [zeilen, wer, wochen, saison])
  const istGruppe = wahl.startsWith('g:')
  // „lose" steht nur dabei, wo es den Artikel auch in klein oder gross gibt — Mandarin oder Mix haben keine Grösse.
  const mitGroesse = new Set(t.artikel.filter(a => a.groesse !== 'lose').map(a => a.gruppe))
  const name = (a: KwArtikel) => (
    <><span className="kw-artikel">{a.gruppe ?? 'Artikelgruppe unbekannt'}{a.groesse !== 'lose' || mitGroesse.has(a.gruppe) ? ` ${groesseName(a.groesse)}` : ''}</span>
      <span className="kw-label"> · {labelName(a.label)}</span></>
  )
  const zelle = (v: number | undefined) => v === undefined ? <span className="kw-nichts" title="in dieser Woche nichts geliefert">–</span> : kg(v, 0)
  return (
    <section className="kw-block" id={`kw-tabelle-${nr}`}>
      <div className="kw-kopf">
        <h3>{wahl.slice(2)}{istGruppe && <span className="kw-gruppe-zusatz"> · {wer.length} {wer.length === 1 ? 'Kunde' : 'Kunden'} zusammen</span>}</h3>
        <p className="kw-gesamt">Gesamtverkauf {wochenText(wochen, alleWochen)}: <strong>{masse(t.summe)}</strong></p>
      </div>
      {t.artikel.length === 0
        ? <p className="leise kw-leer">In {wochen.length === 1 ? 'dieser Woche' : 'diesen Wochen'} nichts geliefert.</p>
        : (
          <div className="rollbar"><table className="dicht kw-tabelle">
            <thead>
              <tr>
                <th rowSpan={2} className="kw-erste">Artikel</th>
                <th colSpan={wochen.length + 1} className="gruppe kw-gruppe">geliefert</th>
              </tr>
              <tr>
                {wochen.map(w => <th key={w} className="zahl" title={`ab Montag, ${tagKurz(wocheMontag(w))}`}>{kwName(w, mitJahr)}</th>)}
                <th className="zahl summe">Summe</th>
              </tr>
            </thead>
            <tbody>
              {t.artikel.map(a => (
                <tr key={a.schluessel}>
                  <td className="kw-erste">{name(a)}</td>
                  {wochen.map(w => <td key={w} className="zahl">{zelle(a.jeWoche.get(w))}</td>)}
                  <td className="zahl summe">{a.jeWoche.size > 0 ? kg(a.summe, 0) : <span className="kw-nichts" title="geliefert, aber ohne Stückgewicht im Perigon-Artikelstamm">ohne Gewicht</span>}</td>
                </tr>
              ))}
            </tbody>
            <tfoot><tr className="summe">
              <td className="kw-erste">Gesamt</td>
              {wochen.map(w => <td key={w} className="zahl">{zelle(t.jeWoche.get(w))}</td>)}
              <td className="zahl summe">{kg(t.summe, 0)}</td>
            </tr></tfoot>
          </table></div>
        )}
      <p className="kw-fuss leise">
        Aus {zahl(t.positionen)} {t.positionen === 1 ? 'Position' : 'Positionen'} der Perigon-Dateien.
        {t.positionenOhneGewicht > 0 && <> Dazu {zahl(t.stueckOhneGewicht)} Stück in {zahl(t.positionenOhneGewicht)} {t.positionenOhneGewicht === 1 ? 'Position' : 'Positionen'} ohne
          Gewicht — im Perigon-Artikelstamm fehlt das Stückgewicht; sie stehen nicht in den Kilos.</>}
      </p>
    </section>
  )
}
