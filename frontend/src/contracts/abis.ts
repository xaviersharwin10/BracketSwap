const POOL_KEY_COMPONENTS = [
  { name: 'currency0',   type: 'address' },
  { name: 'currency1',   type: 'address' },
  { name: 'fee',         type: 'uint24'  },
  { name: 'tickSpacing', type: 'int24'   },
  { name: 'hooks',       type: 'address' },
] as const

export const ERC20_ABI = [
  { type: 'function', name: 'balanceOf', inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'allowance', inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'approve',   inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }], stateMutability: 'nonpayable' },
  { type: 'function', name: 'decimals',  inputs: [], outputs: [{ type: 'uint8' }], stateMutability: 'view' },
  { type: 'function', name: 'mint',      inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [], stateMutability: 'nonpayable' },
] as const

export const ROUTER_ABI = [
  {
    type: 'function', name: 'addLiquidity',
    inputs: [
      { name: 'key', type: 'tuple', components: POOL_KEY_COMPONENTS },
      { name: 'tickLower',      type: 'int24'  },
      { name: 'tickUpper',      type: 'int24'  },
      { name: 'liquidityDelta', type: 'int256' },
    ],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'removeLiquidity',
    inputs: [{ name: 'positionId', type: 'uint256' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'claimWinnings',
    inputs: [{ name: 'positionId', type: 'uint256' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    // Atomic rollover: remove winning position from settled pool + add to next round pool in one tx
    type: 'function', name: 'rollover',
    inputs: [
      { name: 'positionId',       type: 'uint256' },
      { name: 'nextKey',          type: 'tuple',  components: POOL_KEY_COMPONENTS },
      { name: 'nextTickLower',    type: 'int24'   },
      { name: 'nextTickUpper',    type: 'int24'   },
      { name: 'nextLiquidityDelta', type: 'int256' },
    ],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    // Claim receipt NFT: escrows USDC in BracketReceipt contract, returns receiptId
    type: 'function', name: 'claimReceipt',
    inputs: [{ name: 'positionId', type: 'uint256' }],
    outputs: [{ name: 'receiptId', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    // Redeem receipt NFT into next-round pool (NFT path — tradable position)
    type: 'function', name: 'redeemReceipt',
    inputs: [
      { name: 'receiptId',      type: 'uint256' },
      { name: 'nextKey',        type: 'tuple',  components: POOL_KEY_COMPONENTS },
      { name: 'tickLower',      type: 'int24'   },
      { name: 'tickUpper',      type: 'int24'   },
      { name: 'liquidityDelta', type: 'int256'  },
    ],
    outputs: [], stateMutability: 'nonpayable',
  },
] as const

export const HOOK_ABI = [
  {
    type: 'function', name: 'getMatch',
    inputs: [{ name: 'matchId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'tuple', components: [
      { name: 'poolA',  type: 'tuple', components: POOL_KEY_COMPONENTS },
      { name: 'poolB',  type: 'tuple', components: POOL_KEY_COMPONENTS },
      { name: 'teamA',  type: 'address' },
      { name: 'teamB',  type: 'address' },
      { name: 'kickoffTime',          type: 'uint256' },
      { name: 'state',                type: 'uint8'   },
      { name: 'winner',               type: 'address' },
      { name: 'round',                type: 'uint8'   },
      { name: 'totalWinnerLiquidity', type: 'uint256' },
      { name: 'totalPot',             type: 'uint256' },
    ]}],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'getPosition',
    inputs: [{ name: 'positionId', type: 'uint256' }],
    outputs: [{ name: '', type: 'tuple', components: [
      { name: 'owner',           type: 'address' },
      { name: 'liquidityShares', type: 'uint128' },
      { name: 'teamSide',        type: 'address' },
      { name: 'matchId',         type: 'bytes32' },
      { name: 'tickLower',       type: 'int24'   },
      { name: 'tickUpper',       type: 'int24'   },
    ]}],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'nextPositionId',
    inputs: [],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'payoutMultiplier',
    inputs: [{ name: 'matchId', type: 'bytes32' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

// BracketReceipt ERC-721 — scan + display held receipts
export const RECEIPT_ABI = [
  {
    type: 'function', name: 'nextReceiptId',
    inputs: [],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'ownerOf',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'getReceipt',
    inputs: [{ name: 'receiptId', type: 'uint256' }],
    outputs: [{ name: '', type: 'tuple', components: [
      { name: 'matchId',          type: 'bytes32' },
      { name: 'winningTeam',      type: 'address' },
      { name: 'usdcEntitlement',  type: 'uint256' },
      { name: 'tournamentRound',  type: 'uint8'   },
      { name: 'redeemed',         type: 'bool'    },
    ]}],
    stateMutability: 'view',
  },
] as const
