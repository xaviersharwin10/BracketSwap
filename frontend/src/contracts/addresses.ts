export const ADDRESSES = {
  poolManager: '0xD739555d465d7dBaE4786CA8463D7a73e7926426',
  hook:        '0x73ce41FB6F83E44FFce983494393C4D2BDda5f80',
  router:      '0xC130Aa5A443eD6CA3D39bE1c4c26771D15926D5E',
  receipt:     '0xE7a13752f10B797b2249d2c9F27A5592db3343a3',
  oracle:      '0x28fAD9fE8588b2be5e6Db66Bbe2094c2f3b979f3',
  usdc:        '0x90A5eEE155fdEFABb38e65E14d0827b1c4f0B7c7',
  // Group Stage outcome tokens
  braToken:    '0x26366588906e53DECAC684b0FB0483ab7a8fb000',
  gerToken:    '0x73cC416cA7429f5b8350Fef1094A5A9f79e10F5F',
  // Round of 16 outcome tokens
  braR16Token: '0x1f35383e940EAbdC3E07E84Fe80cc635e1Ba780B',
  espToken:    '0x4F541d9C4d1C8728010E784E99C6020E2E37c994',
  // Quarter-final outcome tokens
  braQFToken:  '0xE0da9223aB541Ac8Cb7D70b0B38244041Fc49fa8',
  fraToken:    '0x7FFEF641D2a03CbE9886f76d27c1a96b65d0c4Ba',
} as const

const DYNAMIC_FEE_FLAG = 0x800000
const HOOK = '0x73ce41FB6F83E44FFce983494393C4D2BDda5f80' as `0x${string}`
const USDC = '0x90A5eEE155fdEFABb38e65E14d0827b1c4f0B7c7' as `0x${string}`

// Group Stage: BRA(0x2636) < USDC(0x90A5) and GER(0x73cC) < USDC
export const POOL_KEY_BRA_GROUP = {
  currency0: '0x26366588906e53DECAC684b0FB0483ab7a8fb000' as `0x${string}`,
  currency1: USDC,
  fee: DYNAMIC_FEE_FLAG, tickSpacing: 60, hooks: HOOK,
}
export const POOL_KEY_GER_GROUP = {
  currency0: '0x73cC416cA7429f5b8350Fef1094A5A9f79e10F5F' as `0x${string}`,
  currency1: USDC,
  fee: DYNAMIC_FEE_FLAG, tickSpacing: 60, hooks: HOOK,
}

// Round of 16: BRA_R16(0x1f35) < USDC and ESP(0x4F54) < USDC
export const POOL_KEY_BRA_R16 = {
  currency0: '0x1f35383e940EAbdC3E07E84Fe80cc635e1Ba780B' as `0x${string}`,
  currency1: USDC,
  fee: DYNAMIC_FEE_FLAG, tickSpacing: 60, hooks: HOOK,
}
export const POOL_KEY_ESP_R16 = {
  currency0: '0x4F541d9C4d1C8728010E784E99C6020E2E37c994' as `0x${string}`,
  currency1: USDC,
  fee: DYNAMIC_FEE_FLAG, tickSpacing: 60, hooks: HOOK,
}

// Quarter-final: USDC(0x90A5) < BRA_QF(0xE0da) so USDC is c0; FRA(0x7FFE) < USDC so FRA is c0
export const POOL_KEY_BRA_QF = {
  currency0: USDC,
  currency1: '0xE0da9223aB541Ac8Cb7D70b0B38244041Fc49fa8' as `0x${string}`,
  fee: DYNAMIC_FEE_FLAG, tickSpacing: 60, hooks: HOOK,
}
export const POOL_KEY_FRA_QF = {
  currency0: '0x7FFEF641D2a03CbE9886f76d27c1a96b65d0c4Ba' as `0x${string}`,
  currency1: USDC,
  fee: DYNAMIC_FEE_FLAG, tickSpacing: 60, hooks: HOOK,
}

// Backward-compat aliases
export const POOL_KEY_A = POOL_KEY_BRA_GROUP
export const POOL_KEY_B = POOL_KEY_GER_GROUP

export const MATCH_ID = '0xd1c26d7cffcb96fa3c23fbf1f22284c9ca1d1ac3f51c8ee5a5a7f23ee17f5c05' as `0x${string}`

export type PoolKeyConfig = {
  currency0: `0x${string}`
  currency1: `0x${string}`
  fee: number
  tickSpacing: number
  hooks: `0x${string}`
}

export type MatchConfig = {
  id: `0x${string}`
  label: string
  round: string
  roundNum: number
  teamA: { name: string; flag: string; token: `0x${string}`; poolKey: PoolKeyConfig }
  teamB: { name: string; flag: string; token: `0x${string}`; poolKey: PoolKeyConfig }
  kickoffTime: number
}

export const MATCHES: MatchConfig[] = [
  {
    id: '0xd1c26d7cffcb96fa3c23fbf1f22284c9ca1d1ac3f51c8ee5a5a7f23ee17f5c05',
    label: 'Brazil vs Germany',
    round: 'Group Stage',
    roundNum: 1,
    teamA: { name: 'Brazil',  flag: '🇧🇷', token: '0x26366588906e53DECAC684b0FB0483ab7a8fb000', poolKey: POOL_KEY_BRA_GROUP },
    teamB: { name: 'Germany', flag: '🇩🇪', token: '0x73cC416cA7429f5b8350Fef1094A5A9f79e10F5F', poolKey: POOL_KEY_GER_GROUP },
    kickoffTime: 1779702320,
  },
  {
    id: '0xaab95c8eaa9bc88dc203f10af77a1c982f2c903e5caa86549fe096d2600e2c2e',
    label: 'Brazil vs Spain',
    round: 'Round of 16',
    roundNum: 2,
    teamA: { name: 'Brazil', flag: '🇧🇷', token: '0x1f35383e940EAbdC3E07E84Fe80cc635e1Ba780B', poolKey: POOL_KEY_BRA_R16 },
    teamB: { name: 'Spain',  flag: '🇪🇸', token: '0x4F541d9C4d1C8728010E784E99C6020E2E37c994', poolKey: POOL_KEY_ESP_R16 },
    kickoffTime: 1779964191,
  },
  {
    id: '0x9cd7a7baf8bc0960c10c2003b0c248ac11dd63a170390bcc8da988fc5f29fb0c',
    label: 'Brazil vs France',
    round: 'Quarter-final',
    roundNum: 3,
    teamA: { name: 'Brazil', flag: '🇧🇷', token: '0xE0da9223aB541Ac8Cb7D70b0B38244041Fc49fa8', poolKey: POOL_KEY_BRA_QF },
    teamB: { name: 'France', flag: '🇫🇷', token: '0x7FFEF641D2a03CbE9886f76d27c1a96b65d0c4Ba', poolKey: POOL_KEY_FRA_QF },
    kickoffTime: 1780568991,
  },
]
