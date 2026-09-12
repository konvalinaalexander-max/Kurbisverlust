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
