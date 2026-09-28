import { Link } from 'react-router-dom'
import { Aufklapp, Erklaerung, Hinweis, Karte, Marke } from '../components/Bausteine'
import { fehlendeRaten, useAuswertung, type Auswertung, type Prognose, type SortenK } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { tonnen, zahl } from '../lib/format'

/**
 * Messungen ausstehend — der Reiter rechts vom Betrieb (Runde AF).
 *
 * Der Betrieb: „Anteil unbekannt, solange eine Rate nicht gemessen ist —
 * welche Rate fehlt dir? … einen Reiter rechts vom Betrieb: noch
 * auszuführende Messungen." Hier steht je Sorte, welche der vier Raten
 * gemessen ist, welche aus allen Sorten geliehen wird und welche fehlt —
 * mit dem Satz, was in der Halle dafür zu tun ist, und was die Messung
 * freischaltet. Die Sorten mit Ware im Haus zuerst, die grösste oben.
 */
export default function Ausstehend() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  const gesamt = daten.prognose.find(p => p.gruppe === 'gesamt' && p.h === 0) ?? null
  const fehlt = fehlendeRaten(gesamt)
  const sorten = daten.prognose.filter(p => p.gruppe === 'sorte' && p.h === 0)
    .sort((a, b) => b.lager_kg - a.lager_kg)
  const mitWare = sorten.filter(p => p.lager_kg > 0)
  const ohneWare = sorten.filter(p => !(p.lager_kg > 0))

  return (
    <>
      <Reiterkopf titel="Messungen ausstehend" stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt}
                  zeitplan={daten.zeitplan} veraltet={daten.veraltet} aktuell={daten.aktuell} />
      <Probleme liste={daten.probleme} />

      {gesamt && (fehlt.length === 0
        ? <Hinweis art="gut">Alle vier Raten sind gemessen — der verkaufsfähige Anteil und der Verlust bis heute sind für alle Chargen bekannt.
            Was unten noch fehlt, macht einzelne Sorten genauer: Dort rechnet die Auswertung derweil mit dem Wert aller Sorten.</Hinweis>
        : <Hinweis art="warnung"><strong>Noch nicht gemessen: {fehlt.join(', ')}.</strong> Solange eine dieser Raten fehlt, bleibt der verkaufsfähige
            Anteil unbekannt und der Verlust bis heute unvollständig — die Auswertung erfindet keine Zahl. Unten steht je Sorte, was zu tun ist.</Hinweis>)}

      <Karte id="ausstehend-sorten" titel="Je Sorte: was gemessen ist, was fehlt">
        <SortenTabelle daten={daten} sorten={mitWare} />
        {ohneWare.length > 0 && (
          <Aufklapp titel={<><span>Sorten ohne Ware im Haus</span> <span className="leise">{ohneWare.length}</span></>}>
            <SortenTabelle daten={daten} sorten={ohneWare} />
          </Aufklapp>
        )}
        <Erklaerung titel="Wie die vier Raten gemessen werden — und was sie freischalten">
          <p><strong>Verdunstung</strong> — Kontrollpalette: eine Palette der Sorte heute wiegen und in ein bis zwei Wochen noch einmal
          (Arbeiter-App → Kontrolle; auch der Zettel am Eingang zählt als erste Wägung). Schaltet frei: den Wasserverlust bis heute und den
          verkaufsfähigen Anteil.</p>
          <p><strong>Faules im Lager</strong> — bei jeder Arbeit den Palox leeren und das Faule wiegen (Arbeiter-App, „Palox leeren"). Das
          Verderbsmodell braucht Messungen aus mehreren Chargen und Lagerdauern; bis dahin gilt die Treppe der bisherigen Messungen. Schaltet
          frei: Faules bis heute und die Prognose.</p>
          <p><strong>Zu klein / zu gross</strong> — beim Waschen + Sortieren von Hand die aussortierten Kisten wiegen (Abschluss der Arbeit,
          eine Art darf fehlen: sie bleibt dann unbekannt, nicht 0). Am Band liest die Sortierdatei es selbst. Schaltet frei: was im Haus
          nicht verkaufsfähig ist, und den verkaufsfähigen Anteil.</p>
          <p><strong>Faules beim Abpacken (Fax)</strong> — bei einer Fax-Arbeit das aussortierte Faule wiegen. Schaltet frei: den letzten Schritt
          vor dem Lieferschein.</p>
          <p><strong>Kistengewicht je Band</strong> — beim Waschen eine fertige Palette des Bandes wiegen (Abschluss). Das ändert keinen Verlust,
          aber die Marge je Kiste (Lagermanagement → Wie schwer sind die Kürbisse).</p>
          <p>Fehlt einer Sorte eine eigene Messung, rechnet die Auswertung mit dem Wert aller Sorten und sagt es („geliehen"). Welche Chargen
          ohne jede Stichprobe sind, steht unter <Link to="/messungen">Messungen → Wo fehlen Messungen?</Link>.</p>
        </Erklaerung>
      </Karte>
    </>
  )
}

type Stand = { art: 'fehlt' | 'geliehen' | 'eigen'; text: string }
const geliehen = (k: SortenK) => /alle(r)? Sorten/i.test(k.basis)

function standVon(bekannt: boolean, k: SortenK | undefined, was: string): Stand {
  if (!bekannt) return { art: 'fehlt', text: `fehlt — ${was}` }
  // basis sagt „alle Sorten (zu wenige eigene Chargen)" bzw. „Wiegungen aller Sorten (…)", wenn der Wert geliehen ist.
  if (!k || k.n === 0 || geliehen(k)) return { art: 'geliehen', text: `geliehen (alle Sorten${k ? `, ${k.n} eigene` : ''})` }
  return { art: 'eigen', text: `${zahl(k.n)} ${k.n === 1 ? 'Messung' : 'Messungen'}` }
}

function Zelle({ s }: { s: Stand }) {
  return s.art === 'fehlt' ? <Marke art="warnung">{s.text}</Marke>
    : s.art === 'geliehen' ? <span className="leise">{s.text}</span>
    : <span>{s.text}</span>
}

function SortenTabelle({ daten, sorten }: { daten: Auswertung; sorten: Prognose[] }) {
  if (sorten.length === 0) return <p className="leise">keine</p>
  const schimmelJe = (s: string) => daten.lage.filter(l => l.sorte === s).reduce((a, l) => a + l.n_schimmel, 0)
  const bandJe = (s: string) => daten.gebinde.filter(g => g.sorte === s && g.n > 0).length
  const taraJe = (s: string) => daten.lage.filter(l => l.sorte === s).reduce((a, l) => a + (l.n_paletten - l.n_paletten_mit_netto), 0)
  return (
    <div className="rollbar"><table className="dicht">
      <thead><tr>
        <th>Sorte</th><th className="zahl">im Haus</th>
        <th>Verdunstung</th><th>Faules im Lager</th><th>zu klein / zu gross</th><th>Fax</th><th>Kistengewicht je Band</th><th>Leergewicht</th>
      </tr></thead>
      <tbody>{sorten.map(p => {
        const s = p.schluessel
        const verd = standVon(p.r_bekannt, daten.sorten.verdunstung.find(k => k.sorte === s), 'eine Palette zweimal wiegen')
        const nSch = schimmelJe(s)
        const faul: Stand = !p.f_bekannt ? { art: 'fehlt', text: 'fehlt — beim Leeren das Faule wiegen' }
          : nSch === 0 ? { art: 'geliehen', text: 'geliehen (alle Sorten, keine eigene)' }
          : { art: 'eigen', text: `${zahl(nSch)} ${nSch === 1 ? 'Messung' : 'Messungen'}${daten.modell?.brauchbar ? '' : ' · Modell noch nicht brauchbar'}` }
        const klein = daten.sorten.ausschuss.find(k => k.sorte === s), gross = daten.sorten.nebenkanal.find(k => k.sorte === s)
        const kanal: Stand = !p.kanal_bekannt ? { art: 'fehlt', text: 'fehlt — zu klein und zu gross wiegen' }
          : (klein && gross && !geliehen(klein) && !geliehen(gross))
            ? { art: 'eigen', text: `${zahl(klein.n)} / ${zahl(gross.n)} Messungen` }
            : { art: 'geliehen', text: `geliehen (alle Sorten, ${klein && !geliehen(klein) ? klein.n : 0} / ${gross && !geliehen(gross) ? gross.n : 0} eigene)` }
        const fax: Stand = p.fax_bekannt ? { art: 'eigen', text: 'gemessen' } : { art: 'fehlt', text: 'fehlt — bei einer Fax-Arbeit das Faule wiegen' }
        const nBand = bandJe(s)
        const band: Stand = nBand > 0 ? { art: 'eigen', text: `${nBand} ${nBand === 1 ? 'Band' : 'Bänder'} gewogen` } : { art: 'fehlt', text: 'fehlt — eine fertige Palette wiegen' }
        const tara = taraJe(s)
        const leer: Stand = tara > 0 ? { art: 'fehlt', text: `${zahl(tara)} Paletten ohne Leergewicht — im Erntejournal nachtragen` } : { art: 'eigen', text: 'vollständig' }
        return (
          <tr key={s}>
            <td><strong>{s}</strong></td>
            <td className="zahl">{p.lager_kg > 0 ? tonnen(p.lager_kg) : <span className="leise">—</span>}</td>
            <td><Zelle s={verd} /></td><td><Zelle s={faul} /></td><td><Zelle s={kanal} /></td><td><Zelle s={fax} /></td><td><Zelle s={band} /></td><td><Zelle s={leer} /></td>
          </tr>
        )
      })}</tbody>
    </table></div>
  )
}
