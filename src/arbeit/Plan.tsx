import { useSprache } from '../sprache/SprachProvider'
import { ZAEHLBLATT } from '../lib/taetigkeit'
import type { Station } from '../lib/typen'
import { arbeitsplan, type PlanPunkt } from './plan'

/**
 * Die drei Blöcke zum Überfliegen — vor, während, nach der Arbeit.
 *
 * Kein Kasten mit Erklärungen: je Block eine kurze Liste, und beim Zählen
 * der eine Satz, der sagt, dass es das Zählblatt gibt. Wer lieber liest,
 * liest; wer es kennt, tippt auf „Weiter".
 */
export function Planliste({ station, istFax, rechenbar }: {
  station: Station; istFax: boolean; rechenbar: boolean | null
}) {
  const { t } = useSprache()
  const plan = arbeitsplan(station, istFax, rechenbar)
  const Block = ({ titel, punkte, zettel }: { titel: string; punkte: PlanPunkt[]; zettel?: boolean }) => (
    punkte.length === 0 ? null : (
      <div className="karte plan-block">
        <div className="abschnitt-titel oben-0">{titel}</div>
        <ol className="plan">
          {punkte.map(x => (
            <li key={x.text}>{t(x.text)}{x.freiwillig && <span className="leise"> · {t('freiwillig')}</span>}</li>
          ))}
        </ol>
        {zettel && plan.mitZettel && (
          <p className="leise plan-zettel">{t('planZettel').replace('{blatt}', ZAEHLBLATT[station])}</p>
        )}
      </div>
    )
  )
  return (
    <>
      <Block titel={t('vorDerArbeit')} punkte={plan.vorher} />
      <Block titel={t('waehrendDerArbeit')} punkte={plan.waehrend} zettel />
      <Block titel={t('nachDerArbeit')} punkte={plan.nachher} />
    </>
  )
}
