import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { ZHaken } from '../components/Zeichen'
import type { Charge } from '../lib/typen'
import { zettelBefund, type EingangPalette, type FremdePalette } from './zettel'

const zahlOderNull = (v: unknown) => (v === null || v === undefined || v === '' ? null : Number(v))

/**
 * Der Wareneingang dieser Charge, und die Paletten anderer Chargen am Tag
 * vom Zettel — zwei kleine Abfragen, die zweite nur, wenn sich das Datum
 * ändert. Schlägt eine fehl, prüft die Maske nichts: Die Prüfung ist ein
 * Hinweis, kein Tor.
 */
function useWareneingang(chargeNr: number | null, datum: string) {
  const [eigen, setEigen] = useState<EingangPalette[] | null>(null)
  const [fremd, setFremd] = useState<{ datum: string; zeilen: FremdePalette[] } | null>(null)
  useEffect(() => {
    if (chargeNr === null) return
    let weg = false
    void supabase.from('palette').select('eingangsdatum, brutto_kg, kisten').eq('charge_nr', chargeNr)
      .then(({ data, error }) => {
        if (weg || error) return
        setEigen(((data ?? []) as { eingangsdatum: string; brutto_kg: unknown; kisten: unknown }[])
          .map(z => ({ eingangsdatum: z.eingangsdatum, brutto_kg: zahlOderNull(z.brutto_kg), kisten: zahlOderNull(z.kisten) })))
      })
    return () => { weg = true }
  }, [chargeNr])
  useEffect(() => {
    if (chargeNr === null || !/^\d{4}-\d{2}-\d{2}$/.test(datum)) return
    let weg = false
    void supabase.from('palette').select('charge_nr, brutto_kg').eq('eingangsdatum', datum).neq('charge_nr', chargeNr)
      .then(({ data, error }) => {
        if (weg || error) return
        setFremd({ datum, zeilen: ((data ?? []) as { charge_nr: number; brutto_kg: unknown }[])
          .map(z => ({ charge_nr: z.charge_nr, brutto_kg: zahlOderNull(z.brutto_kg) })) })
      })
    return () => { weg = true }
  }, [chargeNr, datum])
  return { eigen, fremd: fremd && fremd.datum === datum ? fremd.zeilen : [] }
}

/** Der Wert erst, wenn er eine Weile still steht — sonst meldet die Prüfung
 *  bei „43" schon „gibt es nicht", während „432" noch getippt wird. */
function useStill<T>(wert: T, ms: number): T | undefined {
  const [still, setStill] = useState<T | undefined>(undefined)
  useEffect(() => {
    const id = window.setTimeout(() => setStill(wert), ms)
    return () => window.clearTimeout(id)
  }, [wert, ms])
  return still
}

/**
 * Was vom Zettel getippt ist, gegen den Wareneingang (Runde AO, zettel.ts).
 * Steht direkt unter dem Gewicht: grün, wenn die Palette so eingegangen
 * ist; gelb mit dem einen Satz, was zu prüfen ist, wenn nicht.
 */
export function ZettelPruefung({ chargeNr, datum, brutto, kisten = null, kistenSetzen }: {
  chargeNr: number | null; datum: string; brutto: number | null
  /** Was auf der Maske als Kisten steht — und wie man es ersetzt („übernehmen"). */
  kisten?: number | null; kistenSetzen?: (n: number) => void
}) {
  const { t, gebietsschema } = useSprache()
  const { eigen, fremd } = useWareneingang(chargeNr, datum)
  // Geprüft wird das Gewicht, das seit 600 ms so dasteht; solange getippt
  // wird, nur der Tag.
  const still = useStill(brutto, 600)
  const gewicht = still === brutto ? brutto : null
  const [chargen, setChargen] = useState<Charge[]>([])
  useEffect(() => { stammdaten().then(s => setChargen(s.chargen)).catch(() => { /* ohne Namen geht es auch */ }) }, [])
  if (eigen === null) return null
  const b = zettelBefund(eigen, fremd, datum, gewicht, kisten)
  if (b === null) return null
  const tag = (iso: string) => new Date(iso + 'T00:00:00').toLocaleDateString(gebietsschema, { day: '2-digit', month: '2-digit' })
  const kg = gewicht === null ? '' : gewicht.toLocaleString(gebietsschema)
  if (b.art === 'passt') {
    return <p id="zettel-pruefung" className="zettel-pruefung gut" role="status"><ZHaken size={16} /> {t('zettelPasst')}</p>
  }
  if (b.art === 'ohne_eingang') return <p id="zettel-pruefung" className="zettel-pruefung leise" role="status">{t('zettelOhneEingang')}</p>
  if (b.art === 'kisten_anders') {
    return (
      <div id="zettel-pruefung" className="zettel-pruefung">
        <Hinweis art="warnung">
          {t('zettelKistenAnders').replaceAll('{n}', String(b.kisten)).replaceAll('{hier}', String(kisten ?? ''))}
          {kistenSetzen && (
            <div style={{ marginTop: '.5rem' }}>
              <button type="button" id="zettel-kisten-uebernehmen" onClick={() => kistenSetzen(b.kisten)}>
                {t('zettelKistenUebernehmen').replace('{n}', String(b.kisten))}
              </button>
            </div>
          )}
        </Hinweis>
      </div>
    )
  }
  const fremde = b.art === 'fremde_charge' ? chargen.find(c => c.nr === b.charge_nr) : undefined
  const text = b.art === 'fremde_charge'
    ? t('zettelFremdeCharge').replace('{charge}', fremde ? chargeText(fremde) : String(b.charge_nr))
    : b.art === 'anderer_tag'
      ? t('zettelAndererTag').replace('{kg}', kg).replace('{tage}', b.tage.slice(0, 3).map(tag).join(', ') + (b.tage.length > 3 ? ' …' : ''))
      : b.art === 'kein_tag'
        ? t('zettelKeinTag').replace('{datum}', tag(datum))
        : t('zettelKeinGewicht').replace('{datum}', tag(datum)).replace('{kg}', kg)
  return <div id="zettel-pruefung" className="zettel-pruefung"><Hinweis art="warnung">{text}</Hinweis></div>
}
