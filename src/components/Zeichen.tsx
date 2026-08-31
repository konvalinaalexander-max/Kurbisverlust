/**
 * Eine Handvoll Strichzeichen für die Navigation — bewusst von Hand als
 * einfache Geometrie, statt eine Icon-Bibliothek mitzuschleppen. Emojis in
 * der Navigation sehen nach Bastelei aus; kleine einfarbige Zeichen, die die
 * Textfarbe erben, nach Werkzeug.
 */
import type { ReactNode } from 'react'

function Z({ children }: { children: ReactNode }) {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" fill="none" aria-hidden="true"
         stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      {children}
    </svg>
  )
}

/** Arbeiten: eine Liste mit Haken. */
export const ZListe = () => (
  <Z>{<>
    <path d="M3 4.5h1M6.5 4.5H13" />
    <path d="M3 8h1M6.5 8H13" />
    <path d="M3 11.5h1M6.5 11.5H13" />
  </>}</Z>
)

/** Auswertung: drei Balken. */
export const ZBalken = () => (
  <Z>{<>
    <path d="M3.5 13V9" />
    <path d="M8 13V4" />
    <path d="M12.5 13V6.5" />
    <path d="M2 13.5h12" />
  </>}</Z>
)

/** CSV einlesen: Pfeil in die Ablage. */
export const ZEinlesen = () => (
  <Z>{<>
    <path d="M8 2.5v7M5.5 7 8 9.5 10.5 7" />
    <path d="M3 11v2.5h10V11" />
  </>}</Z>
)

/** Warteschlange: Uhr. */
export const ZUhr = () => (
  <Z>{<>
    <circle cx="8" cy="8" r="5.5" />
    <path d="M8 5.2V8l2 1.4" />
  </>}</Z>
)

/** Warenausgang: Kiste mit Pfeil hinaus. */
export const ZAusgang = () => (
  <Z>{<>
    <path d="M9.5 3H3v10h6.5" />
    <path d="M8 8h6M11.8 5.8 14 8l-2.2 2.2" />
  </>}</Z>
)

/** Stammdaten: Schieberegler. */
export const ZRegler = () => (
  <Z>{<>
    <path d="M2.5 4.8h5M10.5 4.8h3" /><circle cx="9" cy="4.8" r="1.5" />
    <path d="M2.5 11.2h2M8.5 11.2h5" /><circle cx="7" cy="11.2" r="1.5" />
  </>}</Z>
)

/** QR-Zugang. */
export const ZQr = () => (
  <Z>{<>
    <rect x="2.5" y="2.5" width="4.5" height="4.5" rx="1" />
    <rect x="9" y="2.5" width="4.5" height="4.5" rx="1" />
    <rect x="2.5" y="9" width="4.5" height="4.5" rx="1" />
    <path d="M9.5 9.5h1.8M12.8 9.5h.7M9.5 12.8h.7M11.8 11.6v1.9" />
  </>}</Z>
)

/** Lagerkontrolle: Lupe. */
export const ZLupe = () => (
  <Z>{<>
    <circle cx="7" cy="7" r="4.5" />
    <path d="m10.5 10.5 3 3" />
  </>}</Z>
)

/** Neue Arbeit: Plus. */
export const ZPlus = () => (
  <Z><path d="M8 3.5v9M3.5 8h9" /></Z>
)
