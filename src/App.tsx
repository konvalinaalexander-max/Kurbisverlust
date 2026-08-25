import { NavLink, Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './auth/AuthProvider'
import { istKonfiguriert } from './lib/supabase'
import { Hinweis, Lade } from './components/Bausteine'
import Anmelden from './pages/Anmelden'
import Auftraege from './pages/Auftraege'
import AuftragDetail from './pages/AuftragDetail'
import CsvUpload from './pages/CsvUpload'
import Warteschlange from './pages/Warteschlange'
import Dashboard from './pages/Dashboard'
import Stammdaten from './pages/Stammdaten'

export default function App() {
  const { session, profil, laedt, istAdmin, abmelden } = useAuth()

  if (!istKonfiguriert) {
    return (
      <div className="huelle" style={{ paddingTop: '2rem' }}>
        <h1>Kürbis-Verlust</h1>
        <Hinweis art="warnung">
          <p><strong>Noch nicht mit Supabase verbunden.</strong></p>
          <p>
            Lege <code>.env.local</code> nach dem Muster von <code>.env.example</code> an und
            trage <code>VITE_SUPABASE_URL</code> und <code>VITE_SUPABASE_ANON_KEY</code> ein.
            Die Werte stehen im Supabase-Dashboard unter <em>Project Settings → API</em>.
          </p>
          <p style={{ marginBottom: 0 }}>
            Beim Hosting auf Cloudflare Pages gehören dieselben zwei Werte in die
            Umgebungsvariablen des Projekts.
          </p>
        </Hinweis>
      </div>
    )
  }

  if (laedt) return <Lade />
  if (!session) return <Anmelden />

  return (
    <>
      <header className="kopf">
        <span className="marke">🎃 Kürbis-Verlust</span>
        <span className="wer">
          {profil?.name ?? session.user.email}
          {istAdmin && ' · Betriebsleiter'}
        </span>
        <button onClick={abmelden} style={{ minHeight: 34, padding: '.3rem .7rem' }}>Abmelden</button>
      </header>

      <nav className="navleiste">
        <NavLink to="/auftraege" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Aufträge</NavLink>
        <NavLink to="/dashboard" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Auswertung</NavLink>
        {istAdmin && <NavLink to="/csv" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Sortier-CSV</NavLink>}
        {istAdmin && <NavLink to="/warteschlange" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Warteschlange</NavLink>}
        {istAdmin && <NavLink to="/stammdaten" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Stammdaten</NavLink>}
      </nav>

      <main className="huelle">
        {!profil && (
          <Hinweis art="warnung">
            Für diesen Login gibt es noch kein Profil. Der Betriebsleiter muss ihn freischalten.
          </Hinweis>
        )}
        <Routes>
          <Route path="/" element={<Navigate to="/auftraege" replace />} />
          <Route path="/auftraege" element={<Auftraege />} />
          <Route path="/auftraege/:id" element={<AuftragDetail />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/csv" element={istAdmin ? <CsvUpload /> : <NurAdmin />} />
          <Route path="/warteschlange" element={istAdmin ? <Warteschlange /> : <NurAdmin />} />
          <Route path="/stammdaten" element={istAdmin ? <Stammdaten /> : <NurAdmin />} />
          <Route path="*" element={<Hinweis>Diese Seite gibt es nicht.</Hinweis>} />
        </Routes>
      </main>
    </>
  )
}

function NurAdmin() {
  return <Hinweis art="warnung">Dieser Bereich ist dem Betriebsleiter vorbehalten.</Hinweis>
}
