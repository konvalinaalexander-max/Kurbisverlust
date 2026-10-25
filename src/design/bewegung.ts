import { useEffect, useRef, useState, type CSSProperties } from 'react'

/**
 * Die Bewegung, die React braucht — der Rest ist CSS (bewegung.css).
 *
 * useZaehler: Eine Zahl läuft zu ihrem Wert — beim ersten Erscheinen von null
 * aus, nach „Neu rechnen" vom alten Wert zum neuen. Nie beim Rollen, nie beim
 * Zeigen; nur, wenn sich der Wert wirklich ändert. Wer Bewegung abgestellt
 * hat, sieht sofort den Endwert.
 */
export function useZaehler(ziel: number | null | undefined, dauer = 600): number | null | undefined {
  const [wert, setWert] = useState<number | null | undefined>(() => (typeof ziel === 'number' && !reduziert() ? 0 : ziel))
  const vorher = useRef<number | null>(null)
  useEffect(() => {
    if (typeof ziel !== 'number' || !Number.isFinite(ziel) || reduziert()) { setWert(ziel); vorher.current = typeof ziel === 'number' ? ziel : null; return }
    const von = vorher.current ?? 0
    vorher.current = ziel
    if (von === ziel) { setWert(ziel); return }
    const t0 = performance.now()
    let raf = 0
    const tick = (t: number) => {
      const p = Math.min(1, (t - t0) / dauer)
      const e = 1 - Math.pow(1 - p, 3)
      setWert(p >= 1 ? ziel : von + (ziel - von) * e)
      if (p < 1) raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [ziel, dauer])
  return wert
}

/** Der Stil für ein gestaffelt eintretendes Element: style={staffel(i)}. Höchstens zwölf Stufen. */
export function staffel(i: number): CSSProperties {
  return { '--i': Math.min(i, 12) } as CSSProperties
}

function reduziert(): boolean {
  return typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
}

/*
 * Von Fall zu Fall, ohne dass die Seite zittert (Runde BG). Der Betrieb: „wenn
 * man eine niedrigere antippt oder eine höhere, dann springt das, die Webseite
 * zittert kurz." Gemessen: Wer in einem langen Fall nach unten gerollt hatte und
 * links einen anderen wählte, sah die Seite weich nach oben rollen, während der
 * neue, kürzere Fall die Seite schrumpfen liess — der Browser kappte die
 * Rollposition, die weiche Bewegung federte zurück (900 → 503 → 484 → 503 →
 * 467 px). Jetzt: vor dem Wechsel sofort an den Anfang der Ansicht, nach dem
 * Wechsel — vor dem Zeichnen — nur, wenn sie ausser Sicht steht (am Handy
 * ersetzt sie die Liste). Nie weich.
 */
function obenHin(el: HTMLElement): void {
  const rand = parseFloat(getComputedStyle(el).scrollMarginTop) || 0
  window.scrollTo({ top: Math.max(0, window.scrollY + el.getBoundingClientRect().top - rand), behavior: 'instant' })
}

/** Vor einem Wechsel: steht der Kopf von #id über dem Bildrand, sofort an seinen Anfang. */
export function vorDemWechsel(id: string): void {
  const el = document.getElementById(id)
  if (el && el.getBoundingClientRect().top < 0) obenHin(el)
}

/** Nach dem Wechsel, im useLayoutEffect (vor dem Zeichnen): steht #id ausser Sicht, an seinen Anfang. */
export function nachDemWechsel(id: string): void {
  const el = document.getElementById(id)
  if (!el) return
  const oben = el.getBoundingClientRect().top
  if (oben < 0 || oben > window.innerHeight * 0.6) obenHin(el)
}
