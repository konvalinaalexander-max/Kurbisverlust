import { useEffect, useState } from 'react'
import { ZDrucken, ZHaken, ZKopieren, ZKuerbis } from '../components/Zeichen'
import QRCode from 'qrcode'
import { Hinweis, Karte } from '../components/Bausteine'

/**
 * Der QR-Code zum Aufhängen in der Halle. Er enthält schlicht die Adresse
 * dieser App — wer ihn mit der Handy-Kamera scannt, landet auf der Startseite,
 * tippt seinen Namen und ist drin.
 */
export default function Zugang() {
  const url = window.location.origin
  const [qr, setQr] = useState<string | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const [kopiert, setKopiert] = useState(false)

  useEffect(() => {
    QRCode.toDataURL(url, { width: 640, margin: 2, errorCorrectionLevel: 'M' })
      .then(setQr)
      .catch(e => setFehler(String(e)))
  }, [url])

  async function kopieren() {
    try {
      await navigator.clipboard.writeText(url)
      setKopiert(true); setTimeout(() => setKopiert(false), 2000)
    } catch { /* ohne Zwischenablage-Recht: der Nutzer markiert von Hand */ }
  }

  return (
    <>
      <h1 className="kein-druck">Zugang für Arbeiter</h1>

      <Hinweis>
        <p className="oben-0 unten-0">
          Diesen QR-Code ausdrucken und in der Halle aufhängen. Die Arbeiter
          scannen ihn mit der normalen Handy-Kamera, tippen einmal ihren Namen und
          können sofort Aufträge starten oder beitreten — <strong>kein Konto,
          keine Mail, kein Passwort</strong>.
        </p>
      </Hinweis>

      <section className="karte druckbereich mitte">
        <h2 className="zugang-titel"><span className="kachel" aria-hidden="true"><ZKuerbis size={22} /></span>Kürbis-Verlust — Zugang</h2>
        <p className="leise nur-druck oben-0">
          Mit der Handy-Kamera scannen, Namen eintippen, loslegen.
        </p>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        {qr && (
          <img src={qr} alt="QR-Code zur App" className="qr-bild" />
        )}
        <p className="qr-adresse">
          {url}
        </p>
      </section>

      <div className="reihe kein-druck">
        <button type="button" onClick={() => window.print()}><ZDrucken size={18} />QR-Code drucken</button>
        <button type="button" onClick={kopieren}>{kopiert ? <><ZHaken size={18} />Kopiert</> : <><ZKopieren size={18} />Adresse kopieren</>}</button>
      </div>

      <Karte titel="Gut zu wissen" >
        <ul className="zugang-liste">
          <li>Jedes Handy merkt sich seine Anmeldung — beim nächsten Mal geht es
              ohne Nachfrage direkt weiter.</li>
          <li>Der eingetippte Name steht bei jeder Erfassung dabei, damit man
              nachvollziehen kann, wer was gemessen hat.</li>
          <li>Arbeiter sehen nur die Aufträge und können messen. Das Dashboard,
              der CSV-Upload und die Stammdaten bleiben dem Betriebsleiter
              vorbehalten.</li>
          <li>Wer das Handy wechselt oder unten auf „Abmelden" tippt, gibt beim
              nächsten Mal einfach wieder den Namen ein.</li>
        </ul>
      </Karte>
    </>
  )
}
