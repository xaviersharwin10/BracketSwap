import { createConfig, http } from 'wagmi'
import { defineChain } from 'viem'

export const xlayerTestnet = defineChain({
  id: 1952,
  name: 'X Layer Testnet',
  nativeCurrency: { name: 'OKB', symbol: 'OKB', decimals: 18 },
  rpcUrls: { default: { http: ['https://testrpc.xlayer.tech'] } },
  blockExplorers: {
    default: { name: 'OKLink', url: 'https://www.oklink.com/xlayer-test' },
  },
  testnet: true,
})

export const config = createConfig({
  chains: [xlayerTestnet],
  transports: { [xlayerTestnet.id]: http() },
})
