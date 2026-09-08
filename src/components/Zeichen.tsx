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


/** Warteschlange: Uhr. */
export const ZUhr = () => (
  <Z>{<>
    <circle cx="8" cy="8" r="5.5" />
    <path d="M8 5.2V8l2 1.4" />
  </>}</Z>
)


/** Stammdaten: Schieberegler. */
export const ZRegler = () => (
  <Z>{<>
    <path d="M2.5 4.8h5M10.5 4.8h3" /><circle cx="9" cy="4.8" r="1.5" />
    <path d="M2.5 11.2h2M8.5 11.2h5" /><circle cx="7" cy="11.2" r="1.5" />
  </>}</Z>
)


/** Lagerkontrolle: Lupe. */
export const ZLupe = () => (
  <Z>{<>
    <circle cx="7" cy="7" r="4.5" />
    <path d="m10.5 10.5 3 3" />
  </>}</Z>
)

