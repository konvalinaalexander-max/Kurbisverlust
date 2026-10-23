import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { einstellung, fehlerText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { stationsProfil } from './daten'
import type { ArbeitDaten } from './daten'
import type { Gebinde } from '../lib/typen'
import { nettoKg, taraFehlt } from '../lib/masse'
import { heute } from '../lib/format'
import { ZettelPruefung } from './ZettelPruefung'
import { tageZwischen, wiegungBefund } from './zettel'

/**
 * Eine Palette wiegen und dabei zählen. Der Arbeiter tippt ab, was auf dem
 * Zettel steht (Eingangsdatum, Eingangsgewicht) — keine Palettenliste, bei
 * hunderten gleich schweren Paletten wäre die nicht bedienbar. Die Wägung
 * wird zuerst gespeichert, dann die Palette mit dem Verweis darauf. Beim
 * Sortieren und beim Waschen + Sortieren gleichermaßen (0060).
 *
 * Runde H: kein „Faules sichtbar" mehr — die Palette wird gewogen, nicht
 * ausgepackt; was faul ist, zählt der Palox. Gefragt wird nur, was man sieht.
 *
 * Runde AO: Acht Wägungen im Abzug vom 11. Oktober konnte die Auswertung
 * nicht nehmen — schwerer als beim Eingang (bis 65 kg), oder schneller
 * leichter, als ein Kürbis verdunstet (bis 4.8 % je Tag). Die Maske sagt
 * jetzt dasselbe, solange die Palette noch auf der Waage steht, mit
 * derselben Rechnung (zettel.ts); und wie im Zähler steht unter dem
 * Eingangsgewicht, ob der Zettel zum Wareneingang passt.
 */
export function WiegenMaske({ d, zettelDatum, zettelBrutto = '', kistenVorbelegt = '', gebindeVorbelegt = '', fertig }: {
  d: ArbeitDaten; zettelDatum: string; zettelBrutto?: string
  /** Runde T: Kisten und Gebinde kommen vom Zähler mit — dort stehen sie
   *  schon, und eine Wägung mit anderem Gebinde als die Zählung wäre ein
   *  stiller Widerspruch in den Daten. */
  kistenVorbelegt?: string; gebindeVorbelegt?: string
  fertig: () => Promise<void>
}) {
  const { t, gebietsschema } = useSprache()
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [datum, setDatum] = useState(zettelDatum)
  // 0060: das Eingangsgewicht steht auf dem Zettel — vorbelegt, wenn es der
  // Zähler schon eingetippt hat; gefragt wird es immer.
  const [damals, setDamals] = useState(zettelBrutto)
  const [jetzt, setJetzt] = useState('')
  const [kisten, setKisten] = useState(kistenVorbelegt)
  const [art, setArt] = useState(gebindeVorbelegt)
  const [proKiste, setProKiste] = useState('')
  const [grenze, setGrenze] = useState(0.01)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void stammdaten().then(s => { setGebinde(s.gebinde); setArt(a => a || s.gebinde[0]?.art || '') })
    // Dieselbe Grenze wie die Auffälligkeit „Verdunstung" (verdunstung_rate_max, Vorgabe 1 % je Tag)
    // Ist sie nicht zu lesen, bleibt die Vorgabe — die Grenze ist nur ein Hinweis, kein Messwert.
    void einstellung<number>('verdunstung_rate_max_pro_tag', 0.01).then(g => { if (Number(g) > 0) setGrenze(Number(g)) })
      .catch(() => { /* Vorgabe 1 % je Tag bleibt */ })
  }, [])

  const vollstaendig = datum !== '' && damals !== '' && jetzt !== '' && kisten !== '' && art !== ''
  const tara = gebinde.find(g => g.art === art)
  const netto = kisten !== '' && jetzt !== '' ? nettoKg(Number(jetzt), Number(kisten), tara) : null
  const fehlt = kisten !== '' && jetzt !== '' ? taraFehlt(tara) : null
  const befund = vollstaendig ? wiegungBefund({
    damals: Number(damals), jetzt: Number(jetzt), kisten: Number(kisten),
    taraKiste: tara?.tara_kg_pro_kiste ?? null, taraPalette: tara?.tara_kg_palette ?? null,
    tage: tageZwischen(datum, heute()), grenzeJeTag: grenze,
  }) : null
  const befundText = befund === null ? null
    : befund.art === 'datum' ? t('wiegungDatum')
    : befund.art === 'netto' ? t('wiegungNetto')
    : befund.art === 'schwerer' ? t('wiegungSchwerer').replace('{kg}', String(befund.kg))
    : befund.art === 'gleich' ? t('wiegungGleich')
    : t('wiegungZuSchnell').replace('{prozent}', befund.prozentJeTag.toLocaleString(gebietsschema))

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
    // Die gewogene Palette entsteht HIER, nicht im Zähler — jede Pflicht,
    // die nur dort durchgesetzt wird, hätte an dieser Stelle ein Loch.
    // Deshalb dieselbe Quelle (`zettelGewichtPflicht`) statt einer zweiten
    // Stationsabfrage, und dieselben Angaben: Kisten und Gebinde, die hier
    // ohnehin erfasst werden, gehen auch auf die Palettenzeile (Runde Q).
    const pr = stationsProfil(d.auftrag)
    const { error: f2 } = await supabase.from('auftrag_palette').insert({
      auftrag_id: d.auftrag.id, eingangsdatum: datum, wiegung_id: (data as { id: number }).id,
      brutto_zettel_kg: pr.zettelGewichtPflicht ? Number(damals) : null,
      kisten: pr.hatPaletten ? Number(kisten) : null,
      gebindeart: pr.hatPaletten ? art : null,
    })
    if (f2) {
      // Runde AZ: Scheitert die Palette, bleibt keine Wägung ohne Palette stehen —
      // sonst schriebe „Eintragen" beim zweiten Versuch eine zweite Wägung.
      await supabase.from('verdunstung_wiegung').delete().eq('id', (data as { id: number }).id)
      setLaeuft(false); setFehler(fehlerText(f2)); return
    }
    setLaeuft(false)
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
      <ZettelPruefung chargeNr={d.auftrag.charge_nr} datum={datum} brutto={Number(damals) > 0 ? Number(damals) : null}
                      kisten={Number(kisten) > 0 ? Number(kisten) : null} kistenSetzen={n => setKisten(String(n))} />
      <div className="feld">
        <label htmlFor="w-jetzt">{t('gewichtJetzt')}</label>
        <input id="w-jetzt" type="number" inputMode="decimal" step="0.1" min={0} value={jetzt}
               onChange={e => setJetzt(e.target.value)} style={{ fontSize: '1.2rem' }} />
      </div>
      <div className="spalten">
        <div className="feld">
          <label htmlFor="w-kisten">{t('anzahlKisten')}</label>
          <input id="w-kisten" type="number" inputMode="numeric" min={1} value={kisten}
                 onChange={e => setKisten(e.target.value)} />
        </div>
        <div className="feld">
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
        <p className="netto-zeile">
          <strong>{(netto / Number(kisten)).toFixed(2)} kg</strong> {t('jeKiste')}
          {proKiste !== '' && Number(proKiste) > 0 && (
            <> · <strong>{(netto / (Number(kisten) * Number(proKiste))).toFixed(2)} kg</strong> {t('proKuerbis')}</>
          )}
        </p>
      )}
      {fehlt && <Hinweis art="warnung">{t(fehlt)}</Hinweis>}
      {befundText && <div id="wiegung-pruefung"><Hinweis art="warnung">{befundText}</Hinweis></div>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <button type="button" className="haupt gross voll" onClick={() => void speichern()}
              disabled={laeuft || !vollstaendig}>{t('eintragen')}</button>
    </div>
  )
}
