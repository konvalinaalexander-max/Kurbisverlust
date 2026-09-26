import { useEffect, useRef, useState } from 'react'
import { useSprache } from '../sprache/SprachProvider'
import { Hinweis } from '../components/Bausteine'
import { ZKreuz, ZMikrofon, ZStopp } from '../components/Zeichen'

/** Eine fertige Aufnahme, wie der Abschluss sie speichert. */
export interface Aufnahme {
  blob: Blob
  typ: string
  sekunden: number
  /** Zum Anhören vor dem Abschicken — eine Objekt-URL, die wieder freigegeben wird. */
  url: string
  /** 0091: was das Handy beim Aufnehmen mitgeschrieben hat — die Spracherkennung
   *  des Browsers, auf Hochdeutsch eingestellt. null, wenn es keine gibt. */
  transkript: string | null
}

/** Die Spracherkennung des Browsers, ohne Typen aus der DOM-Bibliothek:
 *  Chrome und Android haben sie als webkitSpeechRecognition, Safari auf dem
 *  iPhone seit 14.5. Wo sie fehlt, wird nur aufgenommen. */
interface Erkennung {
  lang: string; continuous: boolean; interimResults: boolean
  onresult: ((e: { resultIndex: number; results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }> }) => void) | null
  onerror: (() => void) | null
  start(): void; stop(): void
}
function erkennungBauen(): Erkennung | null {
  const w = window as unknown as { SpeechRecognition?: new () => Erkennung; webkitSpeechRecognition?: new () => Erkennung }
  const K = w.SpeechRecognition ?? w.webkitSpeechRecognition
  if (!K) return null
  try {
    const e = new K()
    // Hochdeutsch aus der Schweiz: das Nächste an dem, was in der Halle
    // gesprochen wird. Mundart versteht sie schlecht — darum steht „Bitte
    // Hochdeutsch" unter dem Knopf, und das Transkript wird gezeigt, nicht
    // nur gespeichert.
    e.lang = 'de-CH'; e.continuous = true; e.interimResults = false
    return e
  } catch { return null }
}

/** Länger als fünf Minuten redet niemand über eine Arbeit; danach hört die
 *  Aufnahme von selbst auf, statt den Speicher des Handys zu füllen. */
const LAENGSTENS_S = 300

/** Was der Browser aufnehmen kann — Chrome und Android webm/opus, das
 *  iPhone mp4. Das erste, das geht, wird genommen; die Endung folgt daraus. */
function aufnahmeTyp(): string | null {
  if (typeof MediaRecorder === 'undefined') return null
  for (const t of ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus']) {
    if (MediaRecorder.isTypeSupported(t)) return t
  }
  return ''
}

export function sprachaufnahmeMoeglich(): boolean {
  return typeof navigator !== 'undefined' && !!navigator.mediaDevices?.getUserMedia && aufnahmeTyp() !== null
}

/**
 * Der grosse Mikrofon-Knopf am Ende einer Arbeit (0085).
 *
 * Drücken startet, drücken beendet. Danach lässt sich die Aufnahme anhören,
 * löschen oder neu machen — abgeschickt wird sie erst mit der Arbeit. Ohne
 * Mikrofon oder ohne Erlaubnis sagt die Maske das und lässt das Schreiben.
 */
export function Sprachaufnahme({ wert, setzen }: { wert: Aufnahme | null; setzen: (a: Aufnahme | null) => void }) {
  const { t } = useSprache()
  const [zustand, setZustand] = useState<'bereit' | 'laeuft'>('bereit')
  const [sekunden, setSekunden] = useState(0)
  const [fehler, setFehler] = useState<string | null>(null)
  const rekorder = useRef<MediaRecorder | null>(null)
  const stuecke = useRef<Blob[]>([])
  const start = useRef(0)
  const uhr = useRef<number | null>(null)
  const erkennung = useRef<Erkennung | null>(null)
  const mitgeschrieben = useRef<string[]>([])

  // Die Objekt-URL einer verworfenen Aufnahme wieder freigeben.
  useEffect(() => () => { if (wert) URL.revokeObjectURL(wert.url) }, [wert])

  async function starten() {
    setFehler(null)
    const typ = aufnahmeTyp()
    if (typ === null || !navigator.mediaDevices?.getUserMedia) { setFehler(t('mikrofonFehlt')); return }
    let strom: MediaStream
    try {
      strom = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch {
      setFehler(t('mikrofonFehlt')); return
    }
    const r = new MediaRecorder(strom, typ ? { mimeType: typ } : undefined)
    stuecke.current = []
    // Mitschreiben, solange aufgenommen wird — was dabei herauskommt, steht
    // nachher unter der Aufnahme zum Prüfen.
    mitgeschrieben.current = []
    const e = erkennungBauen()
    erkennung.current = e
    if (e) {
      e.onresult = ev => {
        for (let i = ev.resultIndex; i < ev.results.length; i++) {
          const r0 = ev.results[i]
          if (r0.isFinal && r0[0]?.transcript) mitgeschrieben.current.push(r0[0].transcript.trim())
        }
      }
      e.onerror = () => { /* kein Netz, kein Recht — dann eben ohne Text */ }
      try { e.start() } catch { erkennung.current = null }
    }
    r.ondataavailable = e => { if (e.data.size > 0) stuecke.current.push(e.data) }
    r.onstop = () => {
      strom.getTracks().forEach(s => s.stop())
      const dauer = Math.max(1, Math.round((Date.now() - start.current) / 1000))
      const blob = new Blob(stuecke.current, { type: r.mimeType || typ || 'audio/webm' })
      if (wert) URL.revokeObjectURL(wert.url)
      // Die Erkennung liefert ihr Letztes oft erst kurz nach dem Stopp.
      try { erkennung.current?.stop() } catch { /* schon aus */ }
      window.setTimeout(() => {
        const text = mitgeschrieben.current.join(' ').trim()
        setzen({ blob, typ: blob.type, sekunden: dauer, url: URL.createObjectURL(blob), transkript: text || null })
      }, 400)
      setZustand('bereit')
      if (uhr.current !== null) { window.clearInterval(uhr.current); uhr.current = null }
    }
    rekorder.current = r
    start.current = Date.now()
    setSekunden(0)
    r.start(1000)
    setZustand('laeuft')
    uhr.current = window.setInterval(() => {
      const s = Math.round((Date.now() - start.current) / 1000)
      setSekunden(s)
      if (s >= LAENGSTENS_S) beenden()
    }, 500)
  }

  function beenden() {
    const r = rekorder.current
    if (r && r.state !== 'inactive') r.stop()
  }

  function loeschen() {
    if (wert) URL.revokeObjectURL(wert.url)
    setzen(null)
  }

  const mmss = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`

  if (zustand === 'laeuft') {
    return (
      <div className="aufnahme laeuft" role="group" aria-label={t('aufnahmeLaeuft')}>
        <p className="aufnahme-stand"><span className="aufnahme-punkt" aria-hidden="true" /> {t('aufnahmeLaeuft')} · {mmss(sekunden)}</p>
        <button type="button" id="aufnahme-beenden" className="haupt gross voll" onClick={beenden}>
          <ZStopp size={22} /> {t('aufnahmeBeenden')}
        </button>
      </div>
    )
  }

  return (
    <div className="aufnahme" role="group" aria-label={t('aufnahme')}>
      {wert ? (
        <>
          <p className="aufnahme-stand">{t('aufnahme')} · {mmss(wert.sekunden)}</p>
          {/* Der Browser bringt das Anhören mit — Abspielen, Pause, Spulen. */}
          <audio controls src={wert.url} style={{ width: '100%' }} />
          <div className="knopf-reihe" style={{ marginTop: '.6rem' }}>
            <button type="button" id="aufnahme-neu" style={{ flex: 2, minHeight: 48 }} onClick={() => void starten()}>
              <ZMikrofon size={18} /> {t('aufnahmeNeu')}
            </button>
            <button type="button" id="aufnahme-loeschen" className="gefahr" style={{ minHeight: 48 }} onClick={loeschen} aria-label={t('aufnahmeLoeschen')}>
              <ZKreuz size={16} /> {t('aufnahmeLoeschen')}
            </button>
          </div>
        </>
      ) : (
        <button type="button" id="aufnahme-starten" className="haupt gross voll aufnahme-start" onClick={() => void starten()}>
          <ZMikrofon size={26} /> {t('aufnahmeStarten')}
        </button>
      )}
      <p className="hilfe">{t('bitteHochdeutsch')}</p>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </div>
  )
}
