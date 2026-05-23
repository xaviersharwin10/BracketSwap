import { useState, useEffect, useMemo } from 'react'
import {
  useAccount, useConnect, useDisconnect,
  useReadContract, useWriteContract, useWaitForTransactionReceipt,
} from 'wagmi'
import { injected } from 'wagmi/connectors'
import { parseUnits, formatUnits, formatEther } from 'viem'
import { useBalance } from 'wagmi'
import { ADDRESSES, MATCHES, type MatchConfig } from './contracts/addresses'
import { ERC20_ABI, ROUTER_ABI, HOOK_ABI, RECEIPT_ABI } from './contracts/abis'
import { useOkxDex, useX402 } from './hooks/useOkxDex'
import { useCountdown } from './hooks/useCountdown'
import './App.css'

// ── Constants ─────────────────────────────────────────────────────────────────
const STATE_LABEL = ['OPEN', 'LIVE', 'SETTLED'] as const
const STATE_COLOR = { 0: '#22c55e', 1: '#f59e0b', 2: '#a78bfa' } as const
const NULL_ADDR = '0x0000000000000000000000000000000000000000'
// Full-range ticks for tickSpacing=60: -14787*60 and 14787*60
const TICK_LOWER = -887220
const TICK_UPPER =  887220

// ── Helpers ───────────────────────────────────────────────────────────────────
function fmtUsdc(n: bigint) {
  return Number(formatUnits(n, 6)).toLocaleString('en-US', { maximumFractionDigits: 2 }) + ' USDC'
}

function computeFee(kickoffTime: number): { pct: string; label: string } {
  const remaining = kickoffTime - Math.floor(Date.now() / 1000)
  if (remaining > 48 * 3600) return { pct: '1.00%', label: '>48h to kickoff' }
  if (remaining > 24 * 3600) return { pct: '0.60%', label: '>24h to kickoff' }
  if (remaining > 6  * 3600) return { pct: '0.30%', label: '>6h to kickoff'  }
  return { pct: '0.10%', label: '<6h to kickoff' }
}

function matchIdxOf(matchId: string): number {
  return MATCHES.findIndex(m => m.id.toLowerCase() === matchId.toLowerCase())
}

// ── Toast ─────────────────────────────────────────────────────────────────────
type Toast = { id: number; msg: string; type: 'info' | 'success' | 'error' }
let toastId = 0

function ToastContainer({ toasts, onRemove }: { toasts: Toast[]; onRemove: (id: number) => void }) {
  return (
    <div className="toast-container">
      {toasts.map(t => (
        <div key={t.id} className={`toast toast-${t.type}`} onClick={() => onRemove(t.id)}>{t.msg}</div>
      ))}
    </div>
  )
}

// ── ConnectBar ────────────────────────────────────────────────────────────────
function ConnectBar({ onToast }: { onToast: (msg: string, type?: Toast['type']) => void }) {
  const { address, isConnected } = useAccount()
  const { connect } = useConnect()
  const { disconnect } = useDisconnect()
  const { zeroGas } = useX402()
  const { data: okbBal } = useBalance({ address, query: { enabled: !!address } })

  return (
    <header className="topbar">
      <div className="topbar-left">
        <span className="brand">⚽ BracketSwap</span>
        <span className="chain-pill">X Layer Testnet</span>
        {zeroGas && <span className="gas-pill">⚡ Zero Gas via x402</span>}
      </div>
      <div className="topbar-right">
        {isConnected ? (
          <>
            <span className="wallet-bal">{okbBal ? Number(formatEther(okbBal.value)).toFixed(4) + ' OKB' : ''}</span>
            <span className="wallet-addr">{address?.slice(0, 6)}…{address?.slice(-4)}</span>
            <button className="btn-ghost" onClick={() => disconnect()}>Disconnect</button>
          </>
        ) : (
          <button className="btn-primary" onClick={() => {
            connect({ connector: injected() })
            onToast('Connecting wallet…', 'info')
          }}>Connect Wallet</button>
        )}
      </div>
    </header>
  )
}

// ── BracketJourney (HERO) ─────────────────────────────────────────────────────
// The core UI that makes BracketSwap unique: follow Brazil through 3 rounds.
function MatchStateBadge({ matchId }: { matchId: `0x${string}` }) {
  const { data } = useReadContract({
    address: ADDRESSES.hook as `0x${string}`,
    abi: HOOK_ABI,
    functionName: 'getMatch',
    args: [matchId],
  })
  const state = data ? Number(data.state) : 0
  const label = STATE_LABEL[state]
  const color = STATE_COLOR[state as 0 | 1 | 2]
  return <span className="state-badge" style={{ background: color }}>{label}</span>
}

function BracketJourney({ activeIdx, onSelect }: { activeIdx: number; onSelect: (i: number) => void }) {
  return (
    <div className="bracket-journey">
      <div className="journey-label">🏆 Brazil's World Cup Path — Follow your team through every round</div>
      <div className="journey-steps">
        {MATCHES.map((m, i) => (
          <div key={m.id} className="journey-row">
            <div
              className={`journey-step ${i === activeIdx ? 'active' : ''}`}
              onClick={() => onSelect(i)}
            >
              <div className="step-round">{m.round}</div>
              <div className="step-teams">
                <span className="step-flag">🇧🇷</span>
                <span className="step-vs">vs</span>
                <span className="step-flag">{m.teamB.flag}</span>
              </div>
              <div className="step-names">{m.teamA.name} vs {m.teamB.name}</div>
              <MatchStateBadge matchId={m.id} />
            </div>
            {i < MATCHES.length - 1 && (
              <div className="journey-arrow">
                <span className="arrow-icon">→</span>
                <span className="arrow-label">roll over</span>
              </div>
            )}
          </div>
        ))}
      </div>
      <div className="journey-tagline">
        Win → Roll → Win → Roll → Claim · <b>$50 compounds through the bracket</b>
      </div>
    </div>
  )
}

// ── MatchHero ─────────────────────────────────────────────────────────────────
function MatchHero({ match }: { match: MatchConfig }) {
  const { data: matchData } = useReadContract({
    address: ADDRESSES.hook as `0x${string}`,
    abi: HOOK_ABI,
    functionName: 'getMatch',
    args: [match.id],
  })
  const { data: multiplier } = useReadContract({
    address: ADDRESSES.hook as `0x${string}`,
    abi: HOOK_ABI,
    functionName: 'payoutMultiplier',
    args: [match.id],
  })

  const state = matchData ? Number(matchData.state) : 0
  const countdown = useCountdown(match.kickoffTime)
  const winner = matchData?.winner?.toLowerCase()
  const braWon = winner === match.teamA.token.toLowerCase()
  const oppWon = winner === match.teamB.token.toLowerCase()
  const pot = matchData?.totalPot ?? 0n
  const multi = multiplier ?? 0n
  const fee = computeFee(match.kickoffTime)

  return (
    <div className="match-hero">
      <div className="match-meta-row">
        <span className="round-label">{match.round}</span>
        <span className="state-badge" style={{ background: STATE_COLOR[state as 0|1|2] }}>{STATE_LABEL[state]}</span>
        {state === 0 && (
          <span className="fee-pill">LP fee: {fee.pct} <span className="fee-sub">({fee.label})</span></span>
        )}
      </div>
      <div className="teams-row">
        <div className={`team-block ${braWon ? 'winner-glow' : ''}`}>
          <div className="flag-big">{match.teamA.flag}</div>
          <div className="team-nm">{match.teamA.name}</div>
          {braWon && <div className="crown">🏆</div>}
        </div>
        <div className="vs-block">
          {countdown && state === 0 ? (
            <><div className="countdown">{countdown}</div><div className="until-ko">until kickoff</div></>
          ) : state === 1 ? (
            <div className="live-pulse">LIVE</div>
          ) : (
            <div className="vs-text">FT</div>
          )}
        </div>
        <div className={`team-block ${oppWon ? 'winner-glow' : ''}`}>
          <div className="flag-big">{match.teamB.flag}</div>
          <div className="team-nm">{match.teamB.name}</div>
          {oppWon && <div className="crown">🏆</div>}
        </div>
      </div>
      <div className="pot-row">
        {pot > 0n && <span className="pot-label">Total Pot: <b>{fmtUsdc(pot)}</b></span>}
        {multi > 0n && <span className="pot-label">Payout Multiplier: <b>{(Number(multi) / 1e18).toFixed(2)}x</b></span>}
        {state === 2 && multi === 0n && <span className="pot-label muted">Awaiting settlement data…</span>}
      </div>
    </div>
  )
}

// ── Faucet ────────────────────────────────────────────────────────────────────
function Faucet({ onToast }: { onToast: (msg: string, type?: Toast['type']) => void }) {
  const { address } = useAccount()
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isSuccess } = useWaitForTransactionReceipt({ hash })

  useEffect(() => { if (isSuccess) onToast('Tokens minted!', 'success') }, [isSuccess])

  const mint = (token: `0x${string}`, decimals: number, amount: number, label: string) => {
    if (!address) return
    onToast(`Minting ${amount} ${label}…`, 'info')
    writeContract({ address: token, abi: ERC20_ABI, functionName: 'mint', args: [address, parseUnits(String(amount), decimals)] })
  }

  const tokens: Array<[`0x${string}`, number, number, string]> = [
    [ADDRESSES.usdc as `0x${string}`,        6,  10000, '10k USDC'],
    [ADDRESSES.braToken as `0x${string}`,    18, 1000,  '1k BRA_WIN 🇧🇷'],
    [ADDRESSES.gerToken as `0x${string}`,    18, 1000,  '1k GER_WIN 🇩🇪'],
    [ADDRESSES.braR16Token as `0x${string}`, 18, 1000,  '1k BRA_R16 🇧🇷'],
    [ADDRESSES.espToken as `0x${string}`,    18, 1000,  '1k ESP_WIN 🇪🇸'],
    [ADDRESSES.braQFToken as `0x${string}`,  18, 1000,  '1k BRA_QF 🇧🇷'],
    [ADDRESSES.fraToken as `0x${string}`,    18, 1000,  '1k FRA_WIN 🇫🇷'],
  ]

  return (
    <div className="faucet-bar">
      <span className="faucet-label">🚰 Testnet Faucet</span>
      {tokens.map(([addr, dec, amt, label]) => (
        <button key={addr} className="btn-chip" disabled={isPending}
          onClick={() => mint(addr, dec, amt, label)}>
          {label}
        </button>
      ))}
    </div>
  )
}

// ── BetPanel ──────────────────────────────────────────────────────────────────
function BetPanel({ match, onToast }: { match: MatchConfig; onToast: (msg: string, type?: Toast['type']) => void }) {
  const { address, isConnected } = useAccount()
  const [teamSide, setTeamSide] = useState<'A' | 'B'>('A')
  const [liquidity, setLiquidity] = useState('500000')
  const [useGasFree, setUseGasFree] = useState(false)
  const [showX402Modal, setShowX402Modal] = useState(false)
  const { zeroGas, isSigning, payment, x402Header, signPayment, clearPayment } = useX402()

  const { data: matchData } = useReadContract({
    address: ADDRESSES.hook as `0x${string}`, abi: HOOK_ABI,
    functionName: 'getMatch', args: [match.id],
  })
  const state = matchData ? Number(matchData.state) : 0

  const chosenTeam = teamSide === 'A' ? match.teamA : match.teamB
  const poolKey = chosenTeam.poolKey

  const { data: usdcBal }   = useReadContract({ address: ADDRESSES.usdc as `0x${string}`, abi: ERC20_ABI, functionName: 'balanceOf', args: [address!], query: { enabled: !!address } })
  const { data: tokenBal }  = useReadContract({ address: chosenTeam.token, abi: ERC20_ABI, functionName: 'balanceOf', args: [address!], query: { enabled: !!address } })
  const { data: usdcAllow } = useReadContract({ address: ADDRESSES.usdc as `0x${string}`, abi: ERC20_ABI, functionName: 'allowance', args: [address!, ADDRESSES.router as `0x${string}`], query: { enabled: !!address } })
  const { data: tokenAllow } = useReadContract({ address: chosenTeam.token, abi: ERC20_ABI, functionName: 'allowance', args: [address!, ADDRESSES.router as `0x${string}`], query: { enabled: !!address } })

  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isMining, isSuccess } = useWaitForTransactionReceipt({ hash })
  const busy = isPending || isMining

  useEffect(() => {
    if (isSuccess) onToast(`Bet placed on ${chosenTeam.flag} ${chosenTeam.name}! Check Positions.`, 'success')
  }, [isSuccess])

  const MAX = BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
  const needsUsdcApproval  = (usdcAllow ?? 0n) < MAX / 2n
  const needsTokenApproval = (tokenAllow ?? 0n) < MAX / 2n

  const approve = (token: `0x${string}`, symbol: string) => {
    onToast(`Approving ${symbol}…`, 'info')
    writeContract({ address: token, abi: ERC20_ABI, functionName: 'approve', args: [ADDRESSES.router as `0x${string}`, MAX] })
  }

  const placeBetDirect = () => {
    onToast(`Placing bet on ${chosenTeam.flag} ${chosenTeam.name}…`, 'info')
    writeContract({
      address: ADDRESSES.router as `0x${string}`,
      abi: ROUTER_ABI,
      functionName: 'addLiquidity',
      args: [poolKey, TICK_LOWER, TICK_UPPER, BigInt(liquidity)],
    })
  }

  const placeBetX402 = async () => {
    if (!signPayment) return
    onToast('Signing x402 payment authorization…', 'info')
    const result = await signPayment(BigInt(liquidity))
    if (!result) {
      onToast('x402 signing failed — check wallet', 'error')
      return
    }
    setShowX402Modal(true)
    if (result.relayedTxHash) {
      onToast(`Relayed tx: ${result.relayedTxHash.slice(0, 10)}… Check Positions.`, 'success')
    } else {
      // Relayer not available on testnet — show the signed payload then fall back
      onToast('Testnet: relayer unavailable — falling back to direct tx', 'info')
      setTimeout(() => {
        setShowX402Modal(false)
        clearPayment()
        placeBetDirect()
      }, 3500)
    }
  }

  const placeBet = () => {
    if (useGasFree && zeroGas) placeBetX402()
    else placeBetDirect()
  }

  const fee = computeFee(match.kickoffTime)

  if (!isConnected) return <div className="panel empty-state">Connect your wallet to place a bet.</div>
  if (state === 1) return (
    <div className="panel">
      <div className="panel-title">⏸ Match In Progress</div>
      <p className="panel-sub">Swaps and new LP positions are blocked while the match is LIVE. Check back after the final whistle.</p>
    </div>
  )
  if (state === 2) return (
    <div className="panel">
      <div className="panel-title">✅ Match Settled</div>
      <p className="panel-sub">Betting is closed. Go to Positions to claim winnings or roll over to the next round.</p>
    </div>
  )

  return (
    <div className="panel">
      <div className="panel-title">
        Place Bet — {match.round}
        {zeroGas && <span className="badge-zerogas">⚡ Zero Gas via x402</span>}
      </div>

      {/* x402 gasless toggle — only shown when OKX Wallet detected */}
      {zeroGas && (
        <div className="x402-toggle-row">
          <label className="x402-toggle-label">
            <input
              type="checkbox"
              checked={useGasFree}
              onChange={e => { setUseGasFree(e.target.checked); clearPayment(); }}
            />
            <span className="x402-toggle-text">
              ⚡ <b>Gas-Free Entry via x402</b>
              <span className="x402-toggle-sub"> — pay USDC, skip OKB entirely</span>
            </span>
          </label>
        </div>
      )}

      {/* x402 signed payload modal */}
      {showX402Modal && payment && x402Header && (
        <div className="x402-modal">
          <div className="x402-modal-title">⚡ x402 Payment Signed</div>
          <div className="x402-modal-row"><span className="x402-key">Protocol:</span><span>x402 v1 · EIP-3009 TransferWithAuthorization</span></div>
          <div className="x402-modal-row"><span className="x402-key">From:</span><span className="x402-addr">{payment.payload.authorization.from}</span></div>
          <div className="x402-modal-row"><span className="x402-key">USDC Amount:</span><span>{(Number(payment.payload.authorization.value) / 1e6).toFixed(2)} USDC</span></div>
          <div className="x402-modal-row"><span className="x402-key">Valid until:</span><span>{new Date(Number(payment.payload.authorization.validBefore) * 1000).toLocaleTimeString()}</span></div>
          <div className="x402-modal-row"><span className="x402-key">Signature:</span><span className="x402-sig">{payment.payload.signature.slice(0, 20)}…</span></div>
          <div className="x402-modal-header-row">
            <span className="x402-key">X-Payment header:</span>
            <code className="x402-header-code">{x402Header.slice(0, 40)}…</code>
          </div>
          <div className="x402-modal-note">
            Relayer receives this header, pays gas in OKB, and calls <code>router.addLiquidity()</code> on your behalf.
          </div>
          <button className="btn-ghost btn-sm" onClick={() => { setShowX402Modal(false); clearPayment() }}>Close</button>
        </div>
      )}

      <div className="fee-notice">
        Current LP fee: <b>{fee.pct}</b> <span className="muted">— {fee.label}. Fees drop as kickoff nears, rewarding early LPs.</span>
      </div>
      <div className="team-toggle">
        <button className={`toggle-btn ${teamSide === 'A' ? 'active' : ''}`} onClick={() => setTeamSide('A')}>
          {match.teamA.flag} {match.teamA.name}
        </button>
        <button className={`toggle-btn ${teamSide === 'B' ? 'active' : ''}`} onClick={() => setTeamSide('B')}>
          {match.teamB.flag} {match.teamB.name}
        </button>
      </div>
      <div className="bal-grid">
        <div className="bal-item">
          <span className="bal-label">USDC Balance</span>
          <span className="bal-value">{usdcBal !== undefined ? fmtUsdc(usdcBal) : '—'}</span>
        </div>
        <div className="bal-item">
          <span className="bal-label">{chosenTeam.flag} Token Balance</span>
          <span className="bal-value">{tokenBal !== undefined ? Number(formatUnits(tokenBal, 18)).toLocaleString() : '—'}</span>
        </div>
      </div>
      <div className="input-group">
        <label>Liquidity shares (both tokens deposited proportionally)</label>
        <input type="number" value={liquidity} onChange={e => setLiquidity(e.target.value)} min="1" />
      </div>
      <div className="btn-row">
        {needsUsdcApproval  && <button className="btn-secondary" disabled={busy} onClick={() => approve(ADDRESSES.usdc as `0x${string}`, 'USDC')}>Approve USDC</button>}
        {needsTokenApproval && <button className="btn-secondary" disabled={busy} onClick={() => approve(chosenTeam.token, chosenTeam.flag + ' Token')}>Approve {chosenTeam.flag} Token</button>}
        {!needsUsdcApproval && !needsTokenApproval && (
          <button className="btn-primary full-w" disabled={busy || isSigning || BigInt(liquidity || '0') === 0n} onClick={placeBet}>
            {isSigning ? '✍️ Signing x402 payment…' : busy ? 'Confirming…' : useGasFree && zeroGas ? `⚡ Bet Gas-Free on ${chosenTeam.flag} ${chosenTeam.name}` : `Bet on ${chosenTeam.flag} ${chosenTeam.name}`}
          </button>
        )}
      </div>
    </div>
  )
}

// ── PositionCard ──────────────────────────────────────────────────────────────
// The hero component: shows rollover, claim, and receipt options.
function PositionCard({ posId, onToast }: { posId: number; onToast: (msg: string, type?: Toast['type']) => void }) {
  const { address } = useAccount()
  const { data: pos } = useReadContract({
    address: ADDRESSES.hook as `0x${string}`, abi: HOOK_ABI,
    functionName: 'getPosition', args: [BigInt(posId)],
  })

  const matchId = pos?.matchId as `0x${string}` | undefined
  const { data: matchData } = useReadContract({
    address: ADDRESSES.hook as `0x${string}`, abi: HOOK_ABI,
    functionName: 'getMatch', args: [matchId ?? '0x0000000000000000000000000000000000000000000000000000000000000000'],
    query: { enabled: !!matchId && matchId !== '0x0000000000000000000000000000000000000000000000000000000000000000' },
  })
  const { data: multiplierData } = useReadContract({
    address: ADDRESSES.hook as `0x${string}`, abi: HOOK_ABI,
    functionName: 'payoutMultiplier', args: [matchId ?? '0x0000000000000000000000000000000000000000000000000000000000000000'],
    query: { enabled: !!matchId },
  })

  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isMining, isSuccess } = useWaitForTransactionReceipt({ hash })
  const busy = isPending || isMining

  useEffect(() => {
    if (isSuccess) onToast('Transaction confirmed!', 'success')
  }, [isSuccess])

  if (!pos || pos.owner === NULL_ADDR) return null
  if (pos.owner.toLowerCase() !== address?.toLowerCase()) return null

  const state = matchData ? Number(matchData.state) : 0
  const midx = matchId ? matchIdxOf(matchId) : -1
  const matchCfg = midx >= 0 ? MATCHES[midx] : null
  const nextMatch = midx >= 0 && midx < MATCHES.length - 1 ? MATCHES[midx + 1] : null

  const isBrazil  = matchCfg ? pos.teamSide.toLowerCase() === matchCfg.teamA.token.toLowerCase() : false
  const isWinner  = matchData?.winner?.toLowerCase() === pos.teamSide.toLowerCase()
  const multiplier = multiplierData ? (Number(multiplierData) / 1e18).toFixed(2) : null
  const estPayout  = multiplierData && pos.liquidityShares
    ? (Number(pos.liquidityShares) * Number(multiplierData) / 1e18).toLocaleString()
    : null

  const teamFlag = matchCfg ? (isBrazil ? matchCfg.teamA.flag : matchCfg.teamB.flag) : '?'
  const teamName = matchCfg ? (isBrazil ? matchCfg.teamA.name : matchCfg.teamB.name) : '?'

  const exit = () => {
    onToast('Exiting position early…', 'info')
    writeContract({ address: ADDRESSES.router as `0x${string}`, abi: ROUTER_ABI, functionName: 'removeLiquidity', args: [BigInt(posId)] })
  }
  const claim = () => {
    onToast('Claiming USDC winnings…', 'info')
    writeContract({ address: ADDRESSES.router as `0x${string}`, abi: ROUTER_ABI, functionName: 'claimWinnings', args: [BigInt(posId)] })
  }
  const getReceipt = () => {
    onToast('Minting BracketReceipt NFT…', 'info')
    writeContract({ address: ADDRESSES.router as `0x${string}`, abi: ROUTER_ABI, functionName: 'claimReceipt', args: [BigInt(posId)] })
  }
  const rollover = () => {
    if (!nextMatch) return
    onToast(`Rolling position into ${nextMatch.round}…`, 'info')
    writeContract({
      address: ADDRESSES.router as `0x${string}`,
      abi: ROUTER_ABI,
      functionName: 'rollover',
      args: [
        BigInt(posId),
        nextMatch.teamA.poolKey,           // Brazil's pool in next round
        TICK_LOWER,
        TICK_UPPER,
        BigInt(pos.liquidityShares),       // same-size position in new pool
      ],
    })
  }

  return (
    <div className={`position-card ${state === 2 && isWinner ? 'pos-winner' : state === 2 && !isWinner ? 'pos-loser' : ''}`}>
      <div className="pos-header">
        <span className="pos-num">#{posId}</span>
        <span className="pos-match">{matchCfg?.round ?? '—'}</span>
        <span className={`state-dot state-${state}`} />
      </div>
      <div className="pos-team-row">
        <span className="pos-flag">{teamFlag}</span>
        <span className="pos-team">{teamName}</span>
        <span className="pos-shares">{Number(pos.liquidityShares).toLocaleString()} shares</span>
      </div>

      {state === 2 && isWinner && multiplier && (
        <div className="pos-payout-banner">
          🎉 {multiplier}x payout · Est. {estPayout} shares value
        </div>
      )}
      {state === 2 && !isWinner && (
        <div className="pos-lost-banner">❌ Team eliminated — position closed</div>
      )}
      {state === 1 && (
        <div className="pos-live-banner">⚽ Match in progress — hold tight</div>
      )}

      <div className="pos-actions">
        {/* OPEN state: can exit early */}
        {state === 0 && (
          <button className="btn-ghost btn-sm" disabled={busy} onClick={exit}>Exit Early</button>
        )}

        {/* SETTLED + WINNER: the BracketSwap signature actions */}
        {state === 2 && isWinner && (
          <>
            {/* PRIMARY: Atomic rollover into next round — the core BracketSwap feature */}
            {nextMatch && isBrazil && (
              <button className="btn-rollover" disabled={busy} onClick={rollover}>
                🔄 Roll to {nextMatch.round} →
              </button>
            )}
            {/* Claim USDC directly */}
            <button className="btn-primary btn-sm" disabled={busy} onClick={claim}>
              💰 Claim USDC
            </button>
            {/* Mint tradable NFT receipt instead of rolling directly */}
            <button className="btn-secondary btn-sm" disabled={busy} onClick={getReceipt}>
              🎫 Get Receipt NFT
            </button>
          </>
        )}
      </div>
    </div>
  )
}

function MyPositions({ onToast }: { onToast: (msg: string, type?: Toast['type']) => void }) {
  const { isConnected } = useAccount()
  const { data: nextId } = useReadContract({ address: ADDRESSES.hook as `0x${string}`, abi: HOOK_ABI, functionName: 'nextPositionId' })
  const count = nextId ? Number(nextId) : 0

  if (!isConnected) return <div className="panel empty-state">Connect wallet to see positions.</div>

  return (
    <div className="panel">
      <div className="panel-title">
        My Positions
        <span className="panel-hint">Win a match → Roll to next round atomically in one tx</span>
      </div>
      {count === 0 ? (
        <p className="empty-msg">No positions yet. Place a bet first.</p>
      ) : (
        Array.from({ length: count }, (_, i) => (
          <PositionCard key={i} posId={i} onToast={onToast} />
        ))
      )}
    </div>
  )
}

// ── ReceiptsPanel ─────────────────────────────────────────────────────────────
// Shows BracketReceipt NFTs held by the user — tradable positions waiting to enter next round.
function ReceiptCard({ receiptId, onToast }: { receiptId: number; onToast: (msg: string, type?: Toast['type']) => void }) {
  const { address } = useAccount()
  const { data: owner } = useReadContract({
    address: ADDRESSES.receipt as `0x${string}`, abi: RECEIPT_ABI,
    functionName: 'ownerOf', args: [BigInt(receiptId)],
  })
  const { data: rd } = useReadContract({
    address: ADDRESSES.receipt as `0x${string}`, abi: RECEIPT_ABI,
    functionName: 'getReceipt', args: [BigInt(receiptId)],
  })
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isMining, isSuccess } = useWaitForTransactionReceipt({ hash })
  const busy = isPending || isMining

  useEffect(() => { if (isSuccess) onToast('Receipt redeemed!', 'success') }, [isSuccess])

  if (!owner || owner.toLowerCase() !== address?.toLowerCase()) return null
  if (!rd || rd.redeemed) return null

  const midx = matchIdxOf(rd.matchId as string)
  const matchCfg = midx >= 0 ? MATCHES[midx] : null
  const nextMatch = midx >= 0 && midx < MATCHES.length - 1 ? MATCHES[midx + 1] : null
  const winningTeamIsA = matchCfg && rd.winningTeam.toLowerCase() === matchCfg.teamA.token.toLowerCase()
  const teamFlag = matchCfg ? (winningTeamIsA ? matchCfg.teamA.flag : matchCfg.teamB.flag) : '?'
  const teamName = matchCfg ? (winningTeamIsA ? matchCfg.teamA.name : matchCfg.teamB.name) : '?'

  const redeem = () => {
    if (!nextMatch) return
    onToast(`Redeeming receipt into ${nextMatch.round}…`, 'info')
    writeContract({
      address: ADDRESSES.router as `0x${string}`,
      abi: ROUTER_ABI,
      functionName: 'redeemReceipt',
      args: [BigInt(receiptId), nextMatch.teamA.poolKey, TICK_LOWER, TICK_UPPER, BigInt(rd.usdcEntitlement)],
    })
  }
  const cashOut = () => {
    onToast('Cashing out receipt…', 'info')
    writeContract({ address: ADDRESSES.router as `0x${string}`, abi: ROUTER_ABI, functionName: 'claimWinnings', args: [BigInt(receiptId)] })
  }

  return (
    <div className="receipt-card">
      <div className="receipt-header">
        <span className="receipt-id">Receipt #{receiptId}</span>
        <span className="receipt-round">{matchCfg?.round}</span>
      </div>
      <div className="receipt-team">{teamFlag} {teamName}</div>
      <div className="receipt-usdc">💵 {fmtUsdc(rd.usdcEntitlement)} escrowed</div>
      <div className="receipt-note">This NFT can be transferred — whoever holds it can redeem into the next round.</div>
      <div className="pos-actions">
        {nextMatch && winningTeamIsA && (
          <button className="btn-rollover" disabled={busy} onClick={redeem}>
            🔄 Redeem into {nextMatch.round} →
          </button>
        )}
        <button className="btn-primary btn-sm" disabled={busy} onClick={cashOut}>💰 Cash Out</button>
      </div>
    </div>
  )
}

function ReceiptsPanel({ onToast }: { onToast: (msg: string, type?: Toast['type']) => void }) {
  const { isConnected } = useAccount()
  const { data: nextId } = useReadContract({
    address: ADDRESSES.receipt as `0x${string}`, abi: RECEIPT_ABI,
    functionName: 'nextReceiptId',
  })
  const count = nextId ? Number(nextId) : 0

  if (!isConnected) return <div className="panel empty-state">Connect wallet to see receipts.</div>

  return (
    <div className="panel">
      <div className="panel-title">
        🎫 BracketReceipt NFTs
        <span className="panel-hint">Tradable — sell your bracket position to someone else</span>
      </div>
      <p className="panel-sub">
        When you win a match, you can mint a Receipt NFT instead of rolling directly. The NFT escrows
        your USDC payout on-chain and can be transferred or sold. Whoever holds it can redeem it into
        the next round's pool.
      </p>
      {count === 0 ? (
        <p className="empty-msg">No receipts minted yet. Win a match and choose "Get Receipt NFT".</p>
      ) : (
        Array.from({ length: count }, (_, i) => (
          <ReceiptCard key={i} receiptId={i} onToast={onToast} />
        ))
      )}
    </div>
  )
}

// ── SwapPanel (OKX DEX) ───────────────────────────────────────────────────────
function SwapPanel({ onToast }: { onToast: (msg: string, type?: Toast['type']) => void }) {
  const { address } = useAccount()
  const [amountIn, setAmountIn] = useState('1')
  const { quote, loading, error, getQuote, executeSwap, NATIVE } = useOkxDex()

  const handleQuote = () => getQuote(NATIVE, ADDRESSES.usdc, parseUnits(amountIn || '0', 18).toString())

  const handleSwap = async () => {
    if (!address) return
    onToast('Submitting OKX DEX swap…', 'info')
    await executeSwap(NATIVE, ADDRESSES.usdc, parseUnits(amountIn || '0', 18).toString())
    if (!error) onToast('Swap executed!', 'success')
    else onToast(error, 'error')
  }

  return (
    <div className="panel">
      <div className="panel-title">
        Swap OKB → USDC
        <span className="badge-okx">Powered by OKX DEX</span>
      </div>
      <p className="panel-sub">Don't have USDC? Swap your native OKB directly — 500+ DEX routes via OKX aggregator.</p>
      <div className="swap-row">
        <div className="swap-token-box">
          <span className="swap-token-label">From</span>
          <div className="swap-token-inner"><span className="token-icon">🟡</span><span>OKB</span></div>
          <input type="number" value={amountIn} onChange={e => setAmountIn(e.target.value)} placeholder="0.0" min="0" />
        </div>
        <div className="swap-arrow">→</div>
        <div className="swap-token-box">
          <span className="swap-token-label">To</span>
          <div className="swap-token-inner"><span className="token-icon">💵</span><span>USDC</span></div>
          <div className="swap-out">{quote ? formatUnits(BigInt(quote.toAmount), 6) : '—'}</div>
        </div>
      </div>
      {quote && (
        <div className="quote-meta">
          <span>Route: {quote.route}</span>
          <span>Price impact: {quote.priceImpact}%</span>
          <span>Gas: {quote.estimateGasFee === '0' ? '⚡ Zero (x402)' : quote.estimateGasFee + ' wei'}</span>
        </div>
      )}
      {error && <p className="error-msg">{error}</p>}
      <div className="btn-row">
        <button className="btn-secondary" disabled={loading} onClick={handleQuote}>
          {loading ? 'Getting quote…' : 'Get Quote'}
        </button>
        {quote && (
          <button className="btn-primary" disabled={loading || !address} onClick={handleSwap}>
            {loading ? 'Swapping…' : `Swap ${amountIn} OKB`}
          </button>
        )}
      </div>
    </div>
  )
}

// ── App ───────────────────────────────────────────────────────────────────────
type Tab = 'bet' | 'positions' | 'receipts' | 'swap'

export default function App() {
  const [activeMatchIdx, setActiveMatchIdx] = useState(0)
  const [tab, setTab] = useState<Tab>('bet')
  const [toasts, setToasts] = useState<Toast[]>([])
  const { isConnected } = useAccount()

  const addToast = (msg: string, type: Toast['type'] = 'info') => {
    const id = ++toastId
    setToasts(ts => [...ts, { id, msg, type }])
    setTimeout(() => setToasts(ts => ts.filter(t => t.id !== id)), 4000)
  }

  const activeMatch = useMemo(() => MATCHES[activeMatchIdx], [activeMatchIdx])

  const tabDefs: { key: Tab; label: string }[] = [
    { key: 'bet',       label: '🎯 Bet'        },
    { key: 'positions', label: '📋 Positions'  },
    { key: 'receipts',  label: '🎫 Receipts'   },
    { key: 'swap',      label: '🔄 Swap (OKX)' },
  ]

  return (
    <div className="app">
      <ConnectBar onToast={addToast} />

      {/* HERO: 3-round bracket journey — the thing that makes BracketSwap unique */}
      <BracketJourney activeIdx={activeMatchIdx} onSelect={setActiveMatchIdx} />

      {/* Selected match details */}
      <MatchHero match={activeMatch} />

      {isConnected && <Faucet onToast={addToast} />}

      <nav className="tab-nav">
        {tabDefs.map(({ key, label }) => (
          <button key={key} className={`tab-btn ${tab === key ? 'active' : ''}`} onClick={() => setTab(key)}>
            {label}
          </button>
        ))}
      </nav>

      <main className="tab-content">
        {tab === 'bet'       && <BetPanel match={activeMatch} onToast={addToast} />}
        {tab === 'positions' && <MyPositions onToast={addToast} />}
        {tab === 'receipts'  && <ReceiptsPanel onToast={addToast} />}
        {tab === 'swap'      && <SwapPanel onToast={addToast} />}
      </main>

      <footer className="footer">
        BracketSwap · Uniswap V4 Hooks · BracketReceipt NFT · Atomic Rollover · OKX DEX · x402 Zero Gas · X Layer Testnet
      </footer>
      <ToastContainer toasts={toasts} onRemove={id => setToasts(ts => ts.filter(t => t.id !== id))} />
    </div>
  )
}
