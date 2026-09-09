import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import type { ArbeitDaten } from './daten'
import type { Gebinde } from '../lib/typen'
import { nettoKg, taraFehlt } from '../lib/masse'

/**
 * Eine Palette wiegen und dabei zählen. Der Arbeiter tippt ab, was auf dem
 * Zettel steht (Eingangsdatum, Eingangsgewicht) — keine Palettenliste, bei
 * hunderten gleich schweren Paletten wäre die nicht bedienbar. Die Wägung
 * wird zuerst gespeichert, dann die Palette mit dem Verweis darauf. Beim
 * Sortieren und beim Waschen + Sortieren gleichermaßen (0060).
 *
 * Runde H: kein „Faules sichtbar" mehr — die Palette wird gewogen, nicht
 * ausgepackt; was faul ist, zählt der Palox. Gefragt wird nur, was man sieht.
 */
export function WiegenMaske({ d, zettelDatum, zettelBrutto = '', fertig }: {
  d: ArbeitDaten; zettelDatum: string; zettelBrutto?: string; fertig: () => Promise<void>
}) {
  const { t } = useSprache()
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [datum, setDatum] = useState(zettelDatum)
  // 0060: das Eingangsgewicht steht auf dem Zettel — vorbelegt, wenn es der
  // Zähler schon eingetippt hat; gefragt wird es immer.
  const [damals, setDamals] = useState(zettelBrutto)
  const [jetzt, setJetzt] = useState('')
  const [kisten, setKisten] = useState('')
  const [art, setArt] = useState('')
  const [proKiste, setProKiste] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void stammdaten().then(s => { setGebinde(s.gebinde); setArt(a => a || s.gebinde[0]?.art || '') })
  }, [])

  const vollstaendig = datum !== '' && damals !== '' && jetzt !== '' && kisten !== '' && art !== ''
  const tara = gebinde.find(g => g.art === art)
  const netto = kisten !== '' && jetzt !== '' ? nettoKg(Number(jetzt), Number(kisten), tara) : null
  const fehlt = kisten !== '' && jetzt !== '' ? taraFehlt(tara) : null

  async function speichern() {
    if (!vollstaendig) return
    setLaeuft(true); setFehler(null)
    const { data, error } = await supabase.from('verdunstung_wiegung').insert({
      auftrag_id: d.auftrag.id, charge_nr: d.auftrag.charge_nr, eingangsdatum: datum,
      brutto_damals_kg: Number(damals), brutto_jetzt_kg: Number(jetzt),
      kisten: Number(kisten), gebindeart: art,
      kuerbisse_pro_kiste: proKiste === '' ? null : Number(proKiste),
    }).select('id').single()
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    const { error: f2 } = await supabase.from('auftrag_palette').insert({
      auftrag_id: d.auftrag.id, eingangsdatum: datum, wiegung_id: (data as { id: number }).id,
      brutto_zettel_kg: d.auftrag.station === 'waschen_sortieren' ? Number(damals) : null,
    })
    setLaeuft(false)
    if (f2) { setFehler(fehlerText(f2)); return }
    await fertig()
  }

  return (
    <div className="karte">
      <div className="feld">
        <label htmlFor="w-datum">{t('eingangsdatum')}</label>
        <input id="w-datum" type="date" value={datum} onChange={e => setDatum(e.target.value)} />
      </div>
      <div className="feld">
        <label htmlFor="w-damals">{t('eingangsgewicht')}</label>
        <input id="w-damals" type="number" inputMode="decimal" step="0.1" min={0} value={damals}
               onChange={e => setDamals(e.target.value)} style={{ fontSize: '1.2rem' }} />
      </div>
      <div className="feld">
        <label htmlFor="w-jetzt">{t('gewichtJetzt')}</label>
        <input id="w-jetzt" type="number" inputMode="decimal" step="0.1" min={0} value={jetzt}
               onChange={e => setJetzt(e.target.value)} style={{ fontSize: '1.2rem' }} />
      </div>
      <div className="reihe">
        <div className="feld" style={{ flex: 1 }}>
          <label htmlFor="w-kisten">{t('anzahlKisten')}</label>
          <input id="w-kisten" type="number" inputMode="numeric" min={1} value={kisten}
                 onChange={e => setKisten(e.target.value)} />
        </div>
        <div className="feld" style={{ flex: 1 }}>
          <label htmlFor="w-art">{t('kistenart')}</label>
          <select id="w-art" value={art} onChange={e => setArt(e.target.value)}>
            {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
          </select>
        </div>
      </div>
      <div className="feld">
        <label htmlFor="w-pro">{t('kuerbisseProKiste')} ({t('freiwillig')})</label>
        <input id="w-pro" type="number" inputMode="numeric" min={1} value={proKiste}
               onChange={e => setProKiste(e.target.value)} />
      </div>
      {netto !== null && netto > 0 && (
        <p style={{ margin: '0 0 .6rem' }}>
          <strong>{(netto / Number(kisten)).toFixed(2)} kg</strong> {t('jeKiste')}
          {proKiste !== '' && Number(proKiste) > 0 && (
            <> · <strong>{(netto / (Number(kisten) * Number(proKiste))).toFixed(2)} kg</strong> {t('proKuerbis')}</>
          )}
        </p>
      )}
      {fehlt && <Hinweis art="warnung">{fehlt} Ohne sie lässt sich das Nettogewicht nicht ausrechnen — die Angabe gehört in die Stammdaten.</Hinweis>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <button className="haupt" style={{ width: '100%', minHeight: 60 }} onClick={() => void speichern()}
              disabled={laeuft || !vollstaendig}>{t('eintragen')}</button>
    </div>
  )
}
