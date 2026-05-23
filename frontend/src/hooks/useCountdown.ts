import { useState, useEffect } from 'react'

export function useCountdown(targetTs: number) {
  const [remaining, setRemaining] = useState(targetTs - Math.floor(Date.now() / 1000))

  useEffect(() => {
    const id = setInterval(() => {
      setRemaining(targetTs - Math.floor(Date.now() / 1000))
    }, 1000)
    return () => clearInterval(id)
  }, [targetTs])

  if (remaining <= 0) return null

  const d = Math.floor(remaining / 86400)
  const h = Math.floor((remaining % 86400) / 3600)
  const m = Math.floor((remaining % 3600) / 60)
  const s = remaining % 60

  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m ${s}s`
}
