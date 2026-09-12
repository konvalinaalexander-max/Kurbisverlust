import { Suspense, lazy, type ReactNode } from 'react'
import { NavLink, Navigate, Route, Routes, useParams } from 'react-router-dom'
import { ZAbmelden, ZBalken, ZKuerbis, ZListe, ZLupe, ZRegler, ZSprache, ZUhr } from './components/Zeichen'
import { useAuth } from './auth/AuthProvider'
import { SprachAuswahl, useSprache } from './sprache/SprachProvider'
import { istKonfiguriert, konfigurationsProblem } from './lib/supabase'
import { Avatar, Hinweis, Lade } from './components/Bausteine'
import Anmelden from './pages/Anmelden'
import Start from './pages/Start'
import NeueArbeit from './pages/NeueArbeit'
import Arbeit from './pages/Arbeit'
import Kontrolle from './pages/Kontrolle'

// Die Auswertung des Betriebsleiters wird erst geholt, wenn er sie öffnet.
const Ueberblick = lazy(() => import('./pages/Ueberblick'))
const Ursachen = lazy(() => import('./pages/Ursachen'))
const Chargen = lazy(() => import('./pages/Chargen'))
const Messungen = lazy(() => import('./pages/Messungen'))
const Betrieb = lazy(() => import('./pages/Betrieb'))

/**
 * Der Rahmen. Zwei Oberflächen aus einem System:
 *  · Das Büro (Betriebsleiter): Seitenleiste links mit den fünf Reitern, auf
 *    schmalen Bildschirmen eine Kopfzeile und die Reiter als Zeile darunter.
 *  · Die Halle (Arbeiter): nur eine Kopfzeile — Marke, Name, Sprache, Abmelden.
 */
export default function App() {
  const { session, profil, laedt, istAdmin, abmelden } = useAuth()
  const { t, sprache, abfrageOffen, abfrageOeffnen } = useSprache()

  if (konfigurationsProblem) {
    return (
      <div className="huelle eng abstand-oben">
        <h1 className="abstand-oben">Kürbis-Verlust</h1>
        <Hinweis art="warnung">
          <p><strong>Die Zugangsdaten stimmen nicht.</strong></p>
          <p className="unten-0">{konfigurationsProblem}</p>
        </Hinweis>
        <p className="leise">
          Zu ändern bei Cloudflare unter Settings → Environment variables.
          Danach unter Deployments beim obersten Eintrag über das Menü ⋯ auf
          „Retry deployment" — ohne neuen Build ändert sich nichts.
        </p>
      </div>
    )
  }

  if (!istKonfiguriert) {
    return (
      <div className="huelle eng abstand-oben">
        <h1 className="abstand-oben">Kürbis-Verlust</h1>
        <Hinweis art="warnung">
          <p><strong>Noch nicht mit Supabase verbunden.</strong></p>
          <p className="unten-0">
            <code>VITE_SUPABASE_URL</code> und <code>VITE_SUPABASE_ANON_KEY</code> fehlen —
            lokal in <code>.env.local</code>, bei Cloudflare unter Environment variables.
          </p>
        </Hinweis>
      </div>
    )
  }

  // Die Sprachfrage steht vor allem anderen: Wer die App nicht lesen kann,
  // kommt auch am Anmeldebildschirm nicht weiter.
  if (abfrageOffen) return <SprachAuswahl />

  if (laedt) return <div className="huelle eng"><Lade /></div>
  if (!session) return <Anmelden />

  // Fünf Reiter, je mit einem Satz, was er beantwortet (docs/UI-KONZEPT.md).
  const reiter: [string, string, (p: { size?: number }) => ReactNode][] = [
    ['/dashboard', 'Überblick', ZBalken],
    ['/ursachen', 'Ursachen', ZLupe],
    ['/chargen', 'Chargen', ZListe],
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
    <div className={`app ${istAdmin ? 'buero' : 'halle'}`}>
      {istAdmin && (
        <aside className="seitenleiste kein-druck">
          {marke}
          <nav className="navleiste" aria-label="Bereiche">
            {reiter.map(([pfad, name, Zeichen]) => (
              <NavLink key={pfad} to={pfad} className={({ isActive }) => (isActive ? 'aktiv' : '')}>
                <Zeichen size={18} />{name}
              </NavLink>
            ))}
          </nav>
          <div className="seitenleiste-fuss">
            <div className="seitenleiste-wer">
              <Avatar name={name || '?'} />
              <span className="name">{name}<span className="rolle">Betriebsleiter</span></span>
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
          <Route path="/dashboard" element={istAdmin ? <Ueberblick /> : <NurAdmin />} />
          <Route path="/ursachen" element={istAdmin ? <Ursachen /> : <NurAdmin />} />
          <Route path="/chargen" element={istAdmin ? <Chargen /> : <NurAdmin />} />
          <Route path="/messungen" element={istAdmin ? <Messungen /> : <NurAdmin />} />
          <Route path="/betrieb/:teil?" element={istAdmin ? <Betrieb /> : <NurAdmin />} />
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
