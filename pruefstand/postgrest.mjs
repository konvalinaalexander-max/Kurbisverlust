/**
 * Der Filter des Mini-PostgREST — von bildschirme.mjs und kette.mjs geteilt.
 * Versteht eq/in/is/not.is/like, order, limit. Mehr braucht die App nicht.
 */
/* ---------- Mini-PostgREST: eq/in/is/like/not-Filter, order, limit ------- */
export function filtern(zeilen, params) {
  let erg = [...zeilen]
  for (const [k, roh] of params.entries()) {
    if (['select', 'order', 'limit', 'offset', 'on_conflict', 'columns'].includes(k)) continue
    for (const v of params.getAll(k)) {
      if (v.startsWith('eq.')) {
        const w = v.slice(3)
        erg = erg.filter(z => String(z[k]) === w)
      } else if (v.startsWith('in.(')) {
        const werte = v.slice(4, -1).split(',').map(s => s.replace(/^"|"$/g, ''))
        erg = erg.filter(z => werte.includes(String(z[k])))
      } else if (v === 'is.null') {
        erg = erg.filter(z => z[k] === null || z[k] === undefined)
      } else if (v === 'not.is.null') {
        erg = erg.filter(z => z[k] !== null && z[k] !== undefined)
      } else if (v.startsWith('like.')) {
        const muster = new RegExp('^' + v.slice(5).replace(/[.+?^${}()|[\]\\]/g, '\\$&')
          .replace(/%/g, '.*').replace(/\*/g, '.*') + '$')
        erg = erg.filter(z => muster.test(String(z[k] ?? '')))
      }
    }
  }
  const order = params.get('order')
  if (order) {
    const [spalte, ...rest] = order.split('.')
    const absteigend = rest.includes('desc')
    erg.sort((a, b) => {
      const x = a[spalte], y = b[spalte]
      if (x === y) return 0
      if (x === null) return 1
      if (y === null) return -1
      return (x < y ? -1 : 1) * (absteigend ? -1 : 1)
    })
  }
  // .range(von, bis) von supabase-js wird zu offset + limit — beides ehren,
  // sonst blättert das seitenweise Laden der App (0059) endlos weiter.
  const offset = params.get('offset')
  if (offset) erg = erg.slice(Number(offset))
  const limit = params.get('limit')
  if (limit) erg = erg.slice(0, Number(limit))
  return erg
}


/* ---------- Seitenweise: der Range-Kopf von supabase-js .range(von, bis) ---
 * PostgREST liefert nur die Zeilen von–bis. Die App lädt grosse Sichten seit
 * 0059 in Seiten zu 1000 und hört auf, sobald eine Seite kürzer ist — eine
 * Attrappe, die den Kopf ignoriert, lässt sie endlos weiterblättern. */
export function seite(zeilen, kopf) {
  const r = /^(\d+)-(\d+)$/.exec(kopf?.['range'] ?? '')
  if (!r) return zeilen
  return zeilen.slice(Number(r[1]), Number(r[2]) + 1)
}
