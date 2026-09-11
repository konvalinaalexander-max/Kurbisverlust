import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import { AuthProvider } from './auth/AuthProvider'
import { SprachProvider } from './sprache/SprachProvider'
// Die Schrift wird mitgebaut statt von einem CDN geladen: In der Halle ist das
// Netz wackelig, und die App muss auch dann gleich aussehen.
import '@fontsource-variable/inter'
import './index.css'
// Runde N: das neue Erscheinungsbild. tokens.css lädt NACH index.css und
// überschreibt dort die Farb- und Mass-Zeichen (warmes Neutral statt kühlem
// Grau, satterer Kürbis, weichere Radien); die Struktur-Regeln von index.css
// greifen die Zeichen von selbst auf. bewegung.css legt die Bewegung darüber.
import './design/tokens.css'
import './design/bewegung.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <SprachProvider>
        <AuthProvider>
          <App />
        </AuthProvider>
      </SprachProvider>
    </BrowserRouter>
  </React.StrictMode>,
)
