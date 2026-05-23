import { useState, useCallback } from 'react'
import { useWalletClient } from 'wagmi'
import { createX402Payment, encodeX402Header, submitToRelayer, type X402PaymentPayload } from '../lib/x402'

const DEX_BASE = 'https://web3.okx.com/api/v5/dex/aggregator'
const CHAIN_ID = '1952' // X Layer testnet (falls back to simulated quote if unsupported)
const NATIVE = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'

export interface DexQuote {
  fromToken: string
  toToken: string
  fromAmount: string
  toAmount: string
  estimateGasFee: string
  priceImpact: string
  route: string
  callData?: string
  to?: string
}

async function fetchQuote(fromToken: string, toToken: string, amount: string): Promise<DexQuote> {
  const url = `${DEX_BASE}/quote?chainId=${CHAIN_ID}&fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&slippage=0.01`
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json' },
  })
  const json = await res.json()
  if (json.code !== '0' && json.code !== 0) {
    // OKX DEX may not support testnet — return a simulated quote for demo
    const inAmt = Number(amount) / 1e18
    const simOut = Math.floor(inAmt * 0.98 * 1e6) // ~0.98 USDC per OKB (demo)
    return {
      fromToken,
      toToken,
      fromAmount: amount,
      toAmount: String(simOut),
      estimateGasFee: '0',
      priceImpact: '0.2',
      route: 'Simulated (testnet)',
    }
  }
  const d = json.data?.[0]
  return {
    fromToken,
    toToken,
    fromAmount: amount,
    toAmount: d?.toTokenAmount ?? '0',
    estimateGasFee: d?.estimateGasFee ?? '0',
    priceImpact: d?.priceImpactPercentage ?? '0',
    route: d?.dexRouterList?.[0]?.subRouterList?.[0]?.dexProtocol?.[0]?.dexName ?? 'OKX DEX',
  }
}

async function fetchSwapCalldata(fromToken: string, toToken: string, amount: string, userAddress: string) {
  const url = `${DEX_BASE}/swap?chainId=${CHAIN_ID}&fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&slippage=0.01&userWalletAddress=${userAddress}`
  const res = await fetch(url)
  const json = await res.json()
  if (json.code !== '0' && json.code !== 0) return null
  return json.data?.[0]
}

export function useOkxDex() {
  const [quote, setQuote] = useState<DexQuote | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const { data: walletClient } = useWalletClient()

  const getQuote = useCallback(async (fromToken: string, toToken: string, amount: string) => {
    setLoading(true)
    setError(null)
    try {
      const q = await fetchQuote(fromToken, toToken, amount)
      setQuote(q)
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Failed to fetch quote')
    } finally {
      setLoading(false)
    }
  }, [])

  const executeSwap = useCallback(async (fromToken: string, toToken: string, amount: string) => {
    if (!walletClient) return
    setLoading(true)
    setError(null)
    try {
      const swapData = await fetchSwapCalldata(fromToken, toToken, amount, walletClient.account.address)
      if (!swapData) throw new Error('Swap not available on testnet — get USDC from the faucet instead')
      await walletClient.sendTransaction({
        to: swapData.tx.to,
        data: swapData.tx.data,
        value: BigInt(swapData.tx.value ?? '0'),
        gas: BigInt(swapData.tx.gas ?? 300000),
      })
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Swap failed')
    } finally {
      setLoading(false)
    }
  }, [walletClient])

  return { quote, loading, error, getQuote, executeSwap, NATIVE }
}

// ── x402 gasless payment hook ─────────────────────────────────────────────────
//
// When the user has OKX Wallet, BracketSwap can route their bet through the
// x402 protocol so they need zero OKB for gas:
//   1. User signs an EIP-3009 TransferWithAuthorization for USDC (no gas)
//   2. Signed payload is sent to the BracketSwap relayer as X-Payment header
//   3. Relayer pays OKB gas and calls router.addLiquidity on their behalf
//
// Falls back to direct transaction if relayer is unavailable (testnet demo).
export function useX402() {
  const hasOkxWallet = typeof window !== 'undefined' && !!(window as { okxwallet?: unknown }).okxwallet
  const [isSigning, setIsSigning] = useState(false)
  const [payment, setPayment] = useState<X402PaymentPayload | null>(null)
  const [x402Header, setX402Header] = useState<string | null>(null)
  const { data: walletClient } = useWalletClient()

  const signPayment = useCallback(async (usdcAmount: bigint): Promise<{
    payment: X402PaymentPayload
    header: string
    relayedTxHash: `0x${string}` | null
  } | null> => {
    if (!walletClient) return null
    setIsSigning(true)
    try {
      const p = await createX402Payment(walletClient, usdcAmount)
      const header = encodeX402Header(p)
      setPayment(p)
      setX402Header(header)
      // Try relayer; testnet will return null and caller falls back to direct tx
      const relayedTxHash = await submitToRelayer(header, {
        poolKey: null,
        tickLower: -887220,
        tickUpper: 887220,
        liquidityDelta: usdcAmount.toString(),
      })
      return { payment: p, header, relayedTxHash }
    } catch {
      return null
    } finally {
      setIsSigning(false)
    }
  }, [walletClient])

  const clearPayment = useCallback(() => {
    setPayment(null)
    setX402Header(null)
  }, [])

  return {
    hasOkxWallet,
    zeroGas: hasOkxWallet,
    isSigning,
    payment,
    x402Header,
    signPayment,
    clearPayment,
  }
}
