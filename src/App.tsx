import { Suspense, lazy, type ReactNode } from 'react'
import { NavLink, Navigate, Route, Routes, useParams } from 'react-router-dom'
import { ZAbmelden, ZBalken, ZKiste, ZKuerbis, ZListe, ZLupe, ZRegler, ZSprache, ZUhr } from './components/Zeichen'
import { useAuth } from './auth/AuthProvider'
import { SprachAuswahl, useSprache } from './sprache/SprachProvider'
import { imDemoModus, istKonfiguriert, konfigurationsProblem } from './lib/supabase'
import { Avatar, Hinweis, Lade } from './components/Bausteine'
import { useBetriebsmodus } from './lib/betriebsmodus'
import { demoVerlassen } from './lib/demo'
import { useHaftendeKoepfe } from './design/haftkopf'
import DemoBand from './components/DemoBand'
import Anmelden from './pages/Anmelden'
import Start from './pages/Start'
import NeueArbeit from './pages/NeueArbeit'
import Arbeit from './pages/Arbeit'
import Kontrolle from './pages/Kontrolle'

// Die Auswertung des Betriebsleiters wird erst geholt, wenn er sie öffnet.
const Lagermanagement = lazy(() => import('./pages/Lagermanagement'))
const Ursachen = lazy(() => import('./pages/Ursachen'))
const Chargen = lazy(() => import('./pages/Chargen'))
const Messungen = lazy(() => import('./pages/Messungen'))
const Betrieb = lazy(() => import('./pages/Betrieb'))
const Artikel = lazy(() => import('./pages/Artikel'))

/**
 * Der Rahmen. Zwei Oberflächen aus einem System:
 *  · Das Büro (Betriebsleiter): Seitenleiste links mit den sechs Reitern, auf
 *    schmalen Bildschirmen eine Kopfzeile und die Reiter als Zeile darunter.
 *  · Die Halle (Arbeiter): nur eine Kopfzeile — Marke, Name, Sprache, Abmelden.
 */
export default function App() {
  const { session, profil, laedt, istAdmin, abmelden, verbindung, neuLaden } = useAuth()
  const { t, sprache, abfrageOffen, abfrageOeffnen } = useSprache()
  // 0072: Auf der Beispiel-Webseite steht das dauerhaft oben. Nicht als
  // Hinweis, den man wegklickt — als Band, das nicht verschwindet.
  // 0081: Wer über den Demo-Knopf hereinkam, bekommt dasselbe Band mit zwei
  // Knöpfen darin — zurücksetzen und verlassen. Die Demo-Datenbank steht
  // ohnehin auf 'beispiel'; der Demo-Eingang ist nur der bequemere Weg
  // hinein, deshalb hat er Vorrang bei der Anzeige.
  const modus = useBetriebsmodus()
  const band: 'demo' | 'beispiel' | null =
    imDemoModus ? 'demo' : modus === 'beispiel' ? 'beispiel' : null
  // Runde AS: im Büro kleben die Spaltentitel je Tabelle, solange sie zu sehen ist.
  useHaftendeKoepfe(istAdmin)

  if (konfigurationsProblem) {
    // Im Demo-Modus geht es um die zwei DEMO-Werte, nicht um die des
    // Betriebs — und vor allem: Es muss hier einen Weg hinaus geben. Ohne
    // ihn sitzt der Besucher fest, weil der Merkzettel im Browser jeden
    // Neuladeversuch wieder hierher führt.
    return (
      <div className="huelle eng abstand-oben">
        <h1 className="abstand-oben">Kürbis-Verlust{imDemoModus ? ' · Demo' : ''}</h1>
        <Hinweis art="warnung">
          <p><strong>
            {imDemoModus
              ? 'Die Zugangsdaten der Demo-Datenbank stimmen nicht.'
              : 'Die Zugangsdaten stimmen nicht.'}
          </strong></p>
          <p className="unten-0">{konfigurationsProblem}</p>
        </Hinweis>
        {imDemoModus && (
          <>
            <p>
              Das betrifft nur die Demo. Die Daten des Betriebs liegen woanders
              und sind unberührt — Du kommst mit einem Tipp wieder zu ihnen.
            </p>
            <button className="haupt gross voll" onClick={demoVerlassen}>
              Demo verlassen
            </button>
          </>
        )}
        <p className="leise">
          Zu ändern bei Cloudflare unter Settings → Environment variables
          {imDemoModus ? ' (VITE_DEMO_SUPABASE_URL und VITE_DEMO_SUPABASE_ANON_KEY)' : ''}.
          Danach unter Deployments beim obersten Eintrag über das Menü ⋯ auf
          „Retry deployment" — ohne neuen Build ändert sich nichts.
        </p>
      </div>
    )
  }

  if (!istKonfiguriert) {
    return (
      <div className="huelle eng abstand-oben">
        <h1 className="abstand-oben">Kürbis-Verlust{imDemoModus ? ' · Demo' : ''}</h1>
        <Hinweis art="warnung">
          <p><strong>Noch nicht mit Supabase verbunden.</strong></p>
          <p className="unten-0">
            <code>VITE_SUPABASE_URL</code> und <code>VITE_SUPABASE_ANON_KEY</code> fehlen —
            lokal in <code>.env.local</code>, bei Cloudflare unter Environment variables.
          </p>
        </Hinweis>
        {imDemoModus && (
          <button className="haupt gross voll" onClick={demoVerlassen}>
            Demo verlassen
          </button>
        )}
      </div>
    )
  }

  // Die Sprachfrage steht vor allem anderen: Wer die App nicht lesen kann,
  // kommt auch am Anmeldebildschirm nicht weiter.
  if (abfrageOffen) return <SprachAuswahl />

  if (laedt) return <div className="huelle eng"><Lade /></div>
  if (!session) return <Anmelden />
  // Runde AG: Antwortet die Datenbank nicht, sagt die Seite es — mit dem Weg
  // hinaus — statt im Ladezustand zu bleiben (28. September, 23:01).
  if (!profil && verbindung) return (
    <div className="huelle eng">
      <Hinweis art="warnung">
        <strong>Die Datenbank antwortet nicht.</strong> {verbindung}<br />
        Meist ist sie nur gerade beschäftigt — in einer Minute nochmals versuchen. Bleibt es so, im Supabase-Dashboard
        das Projekt neu starten (Project Settings → General → Restart project) und dann hier nochmals.
        <div style={{ marginTop: '.6rem' }}>
          <button type="button" className="knopf klein" onClick={() => void neuLaden()}>Nochmals versuchen</button>
        </div>
      </Hinweis>
    </div>
  )

  // Sechs Reiter — docs/UI-KONZEPT.md. Runde AJ: Das Kernstück ist das
  // Lagermanagement mit den Chargen („der Chargenunterreiter, das ist
  // eigentlich das Kernstück"). Runde AO (12. Oktober): das Lager zweimal —
  // nach Charge (agronomisch: welche Charge fällt, welche verdunstet) und
  // nach Artikel (der Verkauf denkt in Artikeln und Kunden); die Arbeiten
  // und „Messungen ausstehend" stehen als Reiter unter Messungen.
  // Die Namen wie der Betrieb sie gab: „den oberen nennen Lagermanagement
  // nach Charge, den unteren Lagermanagement nach Artikel". In der
  // Seitenleiste steht der Zusatz als zweite Zeile, in der schmalen
  // Kopfleiste kurz „Lager nach …" — sonst passen sechs Reiter nicht.
  const reiter: [string, string, (p: { size?: number }) => ReactNode, string?][] = [
    ['/dashboard', 'Lagermanagement', ZBalken, 'nach Charge'],
    ['/artikel', 'Lagermanagement', ZKiste, 'nach Artikel'],
    ['/chargen', 'Chargen', ZListe],
    ['/ursachen', 'Ursachen', ZLupe],
    ['/messungen', 'Messungen', ZRegler],
    ['/betrieb', 'Betrieb', ZUhr],
  ]
  const name = profil?.name ?? ''
  const kuerzel = sprache.toUpperCase()

  const marke = (
    <NavLink to="/" className="marke">
      <span className="zeichen" aria-hidden="true"><ZKuerbis size={20} /></span>
      <span className="name">{t('appName')}</span>
    </NavLink>
  )

  return (
    <div className={`app ${istAdmin ? 'buero' : 'halle'}${band ? ' mit-band' : ''}`}>
      {band === 'demo' && <DemoBand />}
      {band === 'beispiel' && (
        <div className="beispiel-band kein-druck" role="status">{t('beispielBand')}</div>
      )}
      {istAdmin && (
        <aside className="seitenleiste kein-druck">
          {marke}
          <nav className="navleiste" aria-label="Bereiche">
            {reiter.map(([pfad, name, Zeichen, zusatz]) => (
              <NavLink key={pfad} to={pfad} className={({ isActive }) => (isActive ? 'aktiv' : '')}>
                <Zeichen size={18} />
                {zusatz
                  ? <span className="nav-text"><span className="lang">{name}</span><span className="kurz">Lager</span> <span className="zusatz">{zusatz}</span></span>
                  : name}
              </NavLink>
            ))}
          </nav>
          <div className="seitenleiste-fuss">
            <div className="seitenleiste-wer">
              <Avatar name={name || '?'} />
              {/* Runde AO: nur der Name — „ich bin nicht der Betriebsleiter, einfach nur Alexander". */}
              <span className="name">{name}</span>
            </div>
            <button type="button" onClick={abfrageOeffnen}><ZSprache size={17} />Sprache · {kuerzel}</button>
            <button type="button" onClick={abmelden}><ZAbmelden size={17} />{t('abmelden')}</button>
          </div>
        </aside>
      )}

      <header className="kopf kein-druck">
        {marke}
        <span className="wer">{name}</span>
        <button type="button" onClick={abfrageOeffnen} aria-label="Sprache" title="Sprache">
          <ZSprache size={17} /><span className="sprach-kuerzel">{kuerzel}</span>
        </button>
        <button type="button" className="abmelden" onClick={abmelden} aria-label={t('abmelden')} title={t('abmelden')}>
          <ZAbmelden size={17} /><span className="text">{t('abmelden')}</span>
        </button>
      </header>

      <main className={istAdmin ? 'huelle' : 'huelle eng'}>
        <Suspense fallback={<Lade />}>
        <Routes>
          <Route path="/" element={<Start />} />
          <Route path="/start" element={<Start />} />
          <Route path="/neu" element={<NeueArbeit />} />
          <Route path="/arbeit/:id" element={<Arbeit />} />
          {/* Alte Adressen (QR-Codes, Lesezeichen) laufen weiter */}
          <Route path="/auftraege" element={<Navigate to="/" replace />} />
          <Route path="/auftraege/:id" element={<AlteArbeit />} />
          <Route path="/kontrolle" element={<Kontrolle />} />
          <Route path="/dashboard" element={istAdmin ? <Lagermanagement /> : <NurAdmin />} />
          <Route path="/ursachen" element={istAdmin ? <Ursachen /> : <NurAdmin />} />
          <Route path="/chargen" element={istAdmin ? <Chargen /> : <NurAdmin />} />
          <Route path="/messungen/:teil?" element={istAdmin ? <Messungen /> : <NurAdmin />} />
          <Route path="/artikel" element={istAdmin ? <Artikel /> : <NurAdmin />} />
          <Route path="/betrieb/:teil?" element={istAdmin ? <Betrieb /> : <NurAdmin />} />
          {/* Runde AO: „Messungen ausstehend" ist ein Reiter unter Messungen. */}
          <Route path="/ausstehend" element={<Navigate to="/messungen/ausstehend" replace />} />
          {/* Alte Adressen laufen weiter */}
          <Route path="/csv" element={<Navigate to="/betrieb/csv" replace />} />
          <Route path="/warteschlange" element={<Navigate to="/betrieb/warteschlange" replace />} />
          <Route path="/lieferungen" element={<Navigate to="/betrieb/lieferungen" replace />} />
          <Route path="/stammdaten" element={<Navigate to="/betrieb/stammdaten" replace />} />
          <Route path="/zugang" element={<Navigate to="/betrieb/zugang" replace />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
        </Suspense>
      </main>
    </div>
  )
}

function AlteArbeit() {
  const { id } = useParams()
  return <Navigate to={`/arbeit/${id}`} replace />
}

function NurAdmin() {
  const { t } = useSprache()
  return <Hinweis art="warnung">{t('keineBerechtigung')}</Hinweis>
}
