# BracketSwap

**World Cup Tournament Liquidity Protocol** built on Uniswap V4 Hooks, deployed on X Layer.

BracketSwap transforms the FIFA World Cup bracket into a chain of AMM prediction pools where winning LPs roll their positions atomically across tournament rounds — Group Stage → Round of 16 → Quarterfinals — compounding their returns in a single transaction.

---

## Core Mechanic

Each World Cup match spawns **two Uniswap V4 pools** (TeamA_WIN/USDC and TeamB_WIN/USDC). A single `BracketSwapHook` enforces the entire match lifecycle as a state machine.

```
Win Group Stage   →  atomic rollover (1 tx)  →  R16 pool
Win Round of 16   →  atomic rollover (1 tx)  →  QF pool
Win Quarterfinal  →  claim compounded USDC
```

**$50 → $65 → $84 → $107** following Brazil through 3 rounds (parimutuel payout).

---

## Architecture

| Contract | Role |
|---|---|
| `BracketSwapHook` | Uniswap V4 Hook — gatekeeper, bookkeeper, state machine, dynamic fees |
| `BracketRouter` | All pool operations via `IUnlockCallback` — atomic rollover lives here |
| `BracketReceipt` | ERC-721 NFT with on-chain USDC escrow keyed by `receiptId` (travels with the NFT) |
| `OutcomeToken` | ERC-20 team outcome token per match |
| `MockOracle` | Admin oracle for demo settlement |

### Atomic Rollover (the signature feature)

```
BracketRouter.rollover(positionId, nextPoolKey, tickLower, tickUpper, liquidity)
  └── PoolManager.unlock()
        └── unlockCallback()
              ├── modifyLiquidity(oldPool, -shares)   // remove from settled pool
              ├── apply payoutMultiplier               // loser pool USDC flows to winner
              └── modifyLiquidity(newPool, +shares)   // add to next round pool
```

One transaction. Net-zero USDC flow through flash accounting. Profit above stake returned to wallet.

### BracketReceipt NFT

Instead of atomic rollover, winners can mint a `BracketReceipt` NFT:
- USDC entitlement escrowed on-chain, keyed by `receiptId` (not address)
- Transferable — buyer gets the right to enter the next round pool
- Redeemable by whoever holds the NFT via `redeemReceipt()`

### Dynamic Fee Schedule

Fees decrease as kickoff approaches — rewarding committed LPs and maximizing price discovery near match time:

| Time to kickoff | LP fee |
|---|---|
| > 48 hours | 1.00% |
| > 24 hours | 0.60% |
| > 6 hours | 0.30% |
| < 6 hours | 0.10% |

---

## OKX Ecosystem Integration

### x402 Gas-Free Entry
Users pay USDC to enter pools — zero OKB needed. The frontend signs an EIP-3009 `TransferWithAuthorization` which is sent as an `X-Payment` header to a relayer that pays gas in OKB and calls `router.addLiquidity()` on behalf of the user.

### OKX DEX API
OKB → USDC swap via OKX aggregator (500+ DEX routes) before adding liquidity. Users can enter any match with their native token.

---

## Deployment (X Layer Testnet, Chain ID 1952)

| Contract | Address |
|---|---|
| PoolManager | `0xD739555d465d7dBaE4786CA8463D7a73e7926426` |
| BracketSwapHook | `0x73ce41FB6F83E44FFce983494393C4D2BDda5f80` |
| BracketRouter | `0xC130Aa5A443eD6CA3D39bE1c4c26771D15926D5E` |
| BracketReceipt | `0xE7a13752f10B797b2249d2c9F27A5592db3343a3` |
| MockOracle | `0x28fAD9fE8588b2be5e6Db66Bbe2094c2f3b979f3` |
| USDC | `0x90A5eEE155fdEFABb38e65E14d0827b1c4f0B7c7` |

### Matches Registered

| Round | Match | Match ID |
|---|---|---|
| Group Stage | Brazil vs Germany | `0xd1c26d7c...` |
| Round of 16 | Brazil vs Spain | `0xaab95c8e...` |
| Quarter-final | Brazil vs France | `0x9cd7a7ba...` |

---

## Running Locally

```bash
cd frontend
npm install
npm run dev
# Open http://localhost:5173
# Connect MetaMask → Add X Layer Testnet (Chain ID: 1952, RPC: https://testrpc.xlayer.tech)
```

## Running Contracts

```bash
cd bracketswap
forge build
forge script script/Deploy.s.sol --rpc-url $XLAYER_RPC --broadcast
```

---

## Hackathon

Built for **Build X — XCup Hackathon** (May 2026)  
Chain: X Layer · Hook: Uniswap V4 · Theme: FIFA World Cup 2026
