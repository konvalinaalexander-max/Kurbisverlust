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
  const limit = params.get('limit')
  if (limit) erg = erg.slice(0, Number(limit))
  return erg
}

