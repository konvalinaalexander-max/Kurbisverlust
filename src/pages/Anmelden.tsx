import { useState, type FormEvent } from 'react'
import { imDemoModus, supabase } from '../lib/supabase'
import { demoBetreten, demoMoeglich, demoVerlassen } from '../lib/demo'
import { useSprache } from '../sprache/SprachProvider'
import { Hinweis } from '../components/Bausteine'
import { ZKuerbis } from '../components/Zeichen'

const NAME_SCHLUESSEL = 'arbeiter_name'

/**
 * Startseite. Für den Arbeiter genau ein Feld und ein Knopf — mehr nicht.
 * Der Betriebsleiter-Login liegt klein darunter.
 *
 * Seit 0081 führt von hier aus ein dritter Weg weg: „Demo ansehen". Er ist
 * bewusst der unscheinbarste von dreien — wer morgens um sechs in der Halle
 * steht, soll ihn nicht aus Versehen treffen. Und er erscheint überhaupt
 * nur, wenn für diese Webseite eine Demo-Datenbank hinterlegt ist.
 */
export default function Anmelden() {
  const { t } = useSprache()
  if (imDemoModus) return <DemoEintritt />
  return (
    <div className="huelle eng anmelden">
      <h1 className="marke-gross">
        <span className="zeichen" aria-hidden="true"><ZKuerbis size={26} /></span>
        {t('appName')}
      </h1>
      <ArbeiterStart />
      <BetriebsleiterLogin />
      {demoMoeglich && (
        <p className="mitte" style={{ marginTop: '2rem' }}>
          <button type="button" className="leise-knopf" onClick={demoBetreten}>
            Demo ansehen — erfundene Saison, nichts davon ist der Betrieb
          </button>
        </p>
      )}
    </div>
  )
}

/**
 * Der Eingang in der Demo-Datenbank. Kein Passwort, kein Konto: ein Name,
 * damit die Arbeiten jemandem gehören, und los. Angemeldet wird anonym —
 * dasselbe Verfahren wie für die Arbeiter in der Halle.
 *
 * In der Demo-Datenbank zählt jeder Angemeldete als Betriebsleiter (0081).
 * Deshalb steht hier auch, dass beide Seiten offen sind: die Halle über den
 * Kürbis oben links, das Büro über die Reiter.
 */
function DemoEintritt() {
  const [name, setName] = useState('Gast')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  async function los(e: FormEvent) {
    e.preventDefault()
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.auth.signInAnonymously({
      options: { data: { name: name.trim() || 'Gast' } },
    })
    if (error) {
      setLaeuft(false)
      setFehler(/anonymous|disabled|not enabled/i.test(error.message)
        ? 'In der Demo-Datenbank ist der Zugang ohne Konto noch nicht '
          + 'freigeschaltet (Supabase → Authentication → Sign In / Providers → '
          + 'Anonymous sign-ins).'
        : error.message)
    }
  }

  return (
    <div className="huelle eng anmelden" style={{ paddingTop: '1.65rem' }}>
      {/* Das gelbe Band steht sonst erst nach dem Anmelden da. Hier muss es
          schon davor stehen: Wer in der Halle aus Versehen auf „Demo ansehen"
          getippt hat, sieht sonst eine Anmeldemaske wie jede andere — und
          erfasst seine echten Wägungen in der Spielwiese. */}
      <div className="beispiel-band demo kein-druck" role="status">
        <span>Demo — erfundene Daten, nicht der Betrieb</span>
        <button type="button" className="band-knopf" onClick={demoVerlassen}>
          Demo verlassen
        </button>
      </div>
      <h1 className="marke-gross">
        <span className="zeichen" aria-hidden="true"><ZKuerbis size={26} /></span>
        Kürbis-Verlust · Demo
      </h1>
      <section className="karte eintritt">
        <p>
          Eine erfundene Saison in einer eigenen Datenbank: gut 950 Paletten
          Eingang, rund 370 Arbeiten über beide Wege, Lieferungen, Lagerkontrollen
          und ein volles Dashboard. <strong>Nichts davon ist der Betrieb.</strong>
        </p>
        <p className="leise">
          Probier ruhig alles aus — Arbeiten eröffnen, wiegen, zählen,
          abschliessen. Was Du erfasst, landet in der Demo-Datenbank und wird
          mitgerechnet; die echten Zahlen des Betriebs liegen woanders und
          bleiben unberührt. Oben im gelben Band kannst Du die Demo jederzeit
          auf den Anfangszustand zurücksetzen.
        </p>
        <form onSubmit={los}>
          <div className="feld">
            <label htmlFor="demo-name">Dein Name (nur fürs Protokoll)</label>
            <input id="demo-name" value={name} onChange={e => setName(e.target.value)}
                   autoComplete="off" style={{ fontSize: '1.2rem', minHeight: 54 }} />
          </div>
          {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
          <button className="haupt gross voll" disabled={laeuft}>
            {laeuft ? 'Moment …' : 'Demo starten'}
          </button>
        </form>
      </section>
      <p className="mitte" style={{ marginTop: '1.5rem' }}>
        <button type="button" className="leise-knopf" onClick={demoVerlassen}>
          Zurück zur Anmeldung des Betriebs
        </button>
      </p>
    </div>
  )
}

function ArbeiterStart() {
  const { t } = useSprache()
  const [name, setName] = useState(() => {
    try { return localStorage.getItem(NAME_SCHLUESSEL) ?? '' } catch { return '' }
  })
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  async function los(e: FormEvent) {
    e.preventDefault()
    const sauber = name.trim()
    if (!sauber) return
    setLaeuft(true); setFehler(null)
    try { localStorage.setItem(NAME_SCHLUESSEL, sauber) } catch { /* privater Modus */ }

    const { error } = await supabase.auth.signInAnonymously({ options: { data: { name: sauber } } })
    if (error) {
      setLaeuft(false)
      setFehler(/anonymous|disabled|not enabled/i.test(error.message)
        ? t('zugangGesperrt') : error.message)
    }
  }

  return (
    <section className="karte eintritt">
      <form onSubmit={los}>
        <div className="feld">
          <label htmlFor="name">{t('deinName')}</label>
          <input id="name" value={name} onChange={e => setName(e.target.value)}
                 autoComplete="off" autoFocus placeholder={t('namePlatzhalter')}
                 style={{ fontSize: '1.2rem', minHeight: 54 }} />
        </div>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        <button className="haupt gross voll" disabled={laeuft || !name.trim()}>
          {laeuft ? t('moment') : t('losGehts')}
        </button>
      </form>
    </section>
  )
}

function BetriebsleiterLogin() {
  const { t } = useSprache()
  const [offen, setOffen] = useState(false)
  const [modus, setModus] = useState<'anmelden' | 'registrieren'>('anmelden')
  const [email, setEmail] = useState('')
  const [passwort, setPasswort] = useState('')
  const [name, setName] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [meldung, setMeldung] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  async function absenden(e: FormEvent) {
    e.preventDefault()
    setFehler(null); setMeldung(null); setLaeuft(true)
    try {
      if (modus === 'anmelden') {
        const { error } = await supabase.auth.signInWithPassword({ email, password: passwort })
        if (error) throw error
      } else {
        const { error } = await supabase.auth.signUp({
          email, password: passwort, options: { data: { name } },
        })
        if (error) throw error
        setMeldung('Konto angelegt. Falls Supabase eine Bestätigungsmail verlangt, '
          + 'zuerst den Link in der Mail öffnen.')
      }
    } catch (f) {
      setFehler((f as Error).message)
    } finally { setLaeuft(false) }
  }

  if (!offen) {
    return (
      <p className="mitte" style={{ marginTop: '1.5rem' }}>
        <button type="button" className="leise-knopf" onClick={() => setOffen(true)}>
          {t('leiterLogin')}
        </button>
      </p>
    )
  }

  return (
    <section className="karte wechsel">
      <h2 className="oben-0">{t('leiterLogin')}</h2>
      <form onSubmit={absenden}>
        {modus === 'registrieren' && (
          <div className="feld">
            <label htmlFor="bl-name">Name</label>
            <input id="bl-name" value={name} onChange={e => setName(e.target.value)}
                   required autoComplete="name" />
          </div>
        )}
        <div className="feld">
          <label htmlFor="bl-email">E-Mail</label>
          <input id="bl-email" type="email" value={email} onChange={e => setEmail(e.target.value)}
                 required autoComplete="email" inputMode="email" />
        </div>
        <div className="feld">
          <label htmlFor="bl-pw">Passwort</label>
          <input id="bl-pw" type="password" value={passwort} onChange={e => setPasswort(e.target.value)}
                 required minLength={6}
                 autoComplete={modus === 'anmelden' ? 'current-password' : 'new-password'} />
        </div>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        {meldung && <Hinweis art="gut">{meldung}</Hinweis>}
        <button className="haupt voll" style={{ marginTop: '.5rem' }} disabled={laeuft}>
          {laeuft ? '…' : modus === 'anmelden' ? 'Anmelden' : 'Konto anlegen'}
        </button>
        <button type="button" className="blank voll" style={{ marginTop: '.5rem' }}
                onClick={() => { setModus(modus === 'anmelden' ? 'registrieren' : 'anmelden'); setFehler(null) }}>
          {modus === 'anmelden' ? 'Neues Betriebsleiter-Konto anlegen' : 'Ich habe schon ein Konto'}
        </button>
      </form>
    </section>
  )
}
