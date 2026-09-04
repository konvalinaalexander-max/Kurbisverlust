import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import type { ArbeitDaten } from './daten'
import type { Gebinde } from '../lib/typen'

/**
 * Eine Palette wiegen und dabei zählen. Der Arbeiter tippt ab, was auf dem
 * Zettel steht — keine Palettenliste, bei hunderten gleich schweren Paletten
 * wäre die nicht bedienbar. Die Wägung wird zuerst gespeichert, dann die
 * Palette mit dem Verweis darauf.
 */
export function WiegenMaske({ d, zettelDatum, fertig }: {
  d: ArbeitDaten; zettelDatum: string; fertig: () => Promise<void>
}) {
  const { t } = useSprache()
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [datum, setDatum] = useState(zettelDatum)
  const [damals, setDamals] = useState('')
  const [jetzt, setJetzt] = useState('')
  const [kisten, setKisten] = useState('')
  const [art, setArt] = useState('')
  const [proKiste, setProKiste] = useState('')
  const [schimmel, setSchimmel] = useState(false)
  const [faul, setFaul] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void stammdaten().then(s => { setGebinde(s.gebinde); setArt(a => a || s.gebinde[0]?.art || '') })
  }, [])

  const vollstaendig = datum !== '' && damals !== '' && jetzt !== '' && kisten !== '' && art !== ''
  const tara = gebinde.find(g => g.art === art)
  const netto = kisten !== '' && jetzt !== '' && tara?.tara_kg_pro_kiste != null
    ? Number(jetzt) - Number(kisten) * tara.tara_kg_pro_kiste - (tara.tara_kg_palette ?? 0) : null

  async function speichern() {
    if (!vollstaendig) return
    setLaeuft(true); setFehler(null)
    const { data, error } = await supabase.from('verdunstung_wiegung').insert({
      auftrag_id: d.auftrag.id, charge_nr: d.auftrag.charge_nr, eingangsdatum: datum,
      brutto_damals_kg: Number(damals), brutto_jetzt_kg: Number(jetzt),
      kisten: Number(kisten), gebindeart: art,
      kuerbisse_pro_kiste: proKiste === '' ? null : Number(proKiste),
      sichtbar_schimmel: schimmel,
      faul_kg: schimmel && faul !== '' ? Number(faul) : null,
    }).select('id').single()
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    const { error: f2 } = await supabase.from('auftrag_palette').insert({
      auftrag_id: d.auftrag.id, eingangsdatum: datum, wiegung_id: (data as { id: number }).id,
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
      <label className="ankreuzen" style={{ marginBottom: '.5rem' }}>
        <input type="checkbox" checked={schimmel} onChange={e => setSchimmel(e.target.checked)} />
        {t('faulesSichtbar')}
      </label>
      {schimmel && (
        <div className="feld">
          <label htmlFor="w-faul">{t('wievielFaul')} ({t('freiwillig')})</label>
          <input id="w-faul" type="number" inputMode="decimal" step="0.5" min={0} value={faul}
                 onChange={e => setFaul(e.target.value)} />
        </div>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <button className="haupt" style={{ width: '100%', minHeight: 60 }} onClick={() => void speichern()}
              disabled={laeuft || !vollstaendig}>{t('eintragen')}</button>
    </div>
  )
}
