import { type WalletClient, toHex } from 'viem'
import { ADDRESSES } from '../contracts/addresses'

export const X402_RELAYER = '0xRelayerGoesHere000000000000000000000001' as `0x${string}`
export const XLAYER_CHAIN_ID = 1952

export interface X402Authorization {
  from: `0x${string}`
  to: `0x${string}`
  value: string
  validAfter: string
  validBefore: string
  nonce: `0x${string}`
}

export interface X402PaymentPayload {
  x402Version: 1
  scheme: 'exact'
  network: 'xlayer-testnet'
  payload: {
    signature: `0x${string}`
    authorization: X402Authorization
  }
}

// EIP-3009 TransferWithAuthorization domain — matches how Circle deploys USDC
const USDC_DOMAIN = {
  name: 'USD Coin',
  version: '2',
  chainId: XLAYER_CHAIN_ID,
  verifyingContract: ADDRESSES.usdc as `0x${string}`,
} as const

const TRANSFER_WITH_AUTHORIZATION_TYPES = {
  TransferWithAuthorization: [
    { name: 'from',        type: 'address' },
    { name: 'to',          type: 'address' },
    { name: 'value',       type: 'uint256' },
    { name: 'validAfter',  type: 'uint256' },
    { name: 'validBefore', type: 'uint256' },
    { name: 'nonce',       type: 'bytes32' },
  ],
} as const

/**
 * Creates a signed x402 payment payload.
 *
 * The x402 protocol uses EIP-3009 transferWithAuthorization:
 *   1. User signs USDC transfer to the relayer (no gas — only off-chain signing)
 *   2. Relayer submits the signed authorization on-chain (pays gas in OKB)
 *   3. Relayer calls router.addLiquidity on behalf of the user in the same tx
 *
 * The signed payload is sent as the X-Payment HTTP header to the relayer.
 */
export async function createX402Payment(
  walletClient: WalletClient,
  usdcAmount: bigint,
): Promise<X402PaymentPayload> {
  const account = walletClient.account!
  const nonce = toHex(crypto.getRandomValues(new Uint8Array(32))) as `0x${string}`
  const validBefore = BigInt(Math.floor(Date.now() / 1000) + 300) // 5-minute window

  const authorization = {
    from: account.address,
    to: X402_RELAYER,
    value: usdcAmount,
    validAfter: 0n,
    validBefore,
    nonce,
  }

  const signature = await walletClient.signTypedData({
    account: account.address,
    domain: USDC_DOMAIN,
    types: TRANSFER_WITH_AUTHORIZATION_TYPES,
    primaryType: 'TransferWithAuthorization',
    message: authorization,
  })

  return {
    x402Version: 1,
    scheme: 'exact',
    network: 'xlayer-testnet',
    payload: {
      signature,
      authorization: {
        from: account.address,
        to: X402_RELAYER,
        value: usdcAmount.toString(),
        validAfter: '0',
        validBefore: validBefore.toString(),
        nonce,
      },
    },
  }
}

/** Encodes the payment payload as a base64 string for the X-Payment header. */
export function encodeX402Header(payment: X402PaymentPayload): string {
  return btoa(JSON.stringify(payment))
}

/**
 * Sends the x402 payment payload to the relayer and returns the relayed tx hash.
 * In production: POST to relayer endpoint with X-Payment header.
 * In demo/testnet: falls back to null (caller should use direct tx instead).
 */
export async function submitToRelayer(
  header: string,
  calldata: { poolKey: unknown; tickLower: number; tickUpper: number; liquidityDelta: string },
): Promise<`0x${string}` | null> {
  try {
    const res = await fetch('https://relay.bracketswap.xyz/addLiquidity', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Payment': header,
      },
      body: JSON.stringify(calldata),
    })
    if (!res.ok) return null
    const { txHash } = await res.json()
    return txHash
  } catch {
    return null
  }
}
