# Build X Hackathon — XCup Reference

> Last updated: 2026-05-22 (Day 4 of 10 — hackathon is LIVE)

---

## Overview

| Field | Detail |
|---|---|
| Name | Build X Hackathon — XCup |
| Organizer | X Layer (OKX) |
| Theme | **World Cup-themed** DApps on X Layer |
| Duration | May 19, 23:59 UTC → May 28, 23:59 UTC (10 days) |
| Submission Deadline | May 28, 23:59 UTC (via Google Form) |
| Total Prize Pool | **14,000 USDT** |

---

## Prizes

| Place | Prize |
|---|---|
| 1st | 5,000 USDT + OKX official PR support + cooperation opportunity |
| 2nd (×2) | 3,000 USDT each + OKX official PR support |
| 3rd (×3) | 1,000 USDT each + social media exposure |

---

## Eligible Tracks

1. Prediction Markets
2. Trading
3. Social
4. NFT
5. GameFi
6. AI Agent

No track-specific technical requirements — all tracks share the same base criteria.

---

## Judging Criteria

1. **Innovation** — Degree of differentiation within the World Cup context
2. **Market Potential** — Ability to convert World Cup traffic into X Layer users/transactions
3. **Completion** — Deliverables, demonstrability, on-chain verifiability
4. **Demo Video (Bonus)** — Optional 1–3 minute video submission

---

## Hard Requirements (Must Have)

- [ ] Project is **World Cup-themed**
- [ ] Built on **X Layer** (mainnet or testnet)
- [ ] Uses **Uniswap V4 Hook mechanism** — new Hook contract logic developed *during* the hackathon
- [ ] V4 Pool and Hook contracts deployed on X Layer with verifiable contract addresses
- [ ] Dedicated **X (Twitter) account** tagging @XLayerOfficial, @Uniswap, @flapdotsh
- [ ] Active social media posting throughout hackathon period
- [ ] Submitted via Google Form before deadline
- [ ] Age 18+ / jurisdiction majority
- [ ] Self-custodial wallet address for prizes

---

## About X Layer

- **Type:** EVM Layer 2 (Ethereum scaling solution)
- **Native Gas Token:** OKB
- **Block Time:** ~1 second
- **TPS:** ~5,000 average
- **Tx Cost:** ~$0.0005 USD
- **Total Addresses:** 4M+
- Both **mainnet** and **testnet** are supported
- EVM-compatible — standard Solidity/EVM tooling works
- Key ecosystem partners: Chainlink, API3, Band Protocol (oracles), Blockdaemon, BlockPI, Ankr (infra)

---

## Sponsors / Partners

| Entity | Role |
|---|---|
| X Layer | Organizer |
| Uniswap | Partner (V4 Hooks is a core requirement) |
| Flap (flapdotsh) | Partner |

---

## Onchain OS (OKX Dev Platform)

- Built for AI + Web3 development
- **Agentic Wallet:** intelligent wallet executing onchain txns via OKX Wallet infra
- **Payments:** gas-free payments via x402 protocol
- **Trade:** DEX aggregation across 500+ exchanges
- **AI Toolkit:** 9 skills / 72 features (token ops, market monitoring, risk detection)
- Integration options: Skills/CLI (`npx skills add okx/onchainos-skills`), MCP, Open API
- Supports 60+ networks, <100ms response time
- Dev portal: https://web3.okx.com/onchainos/dev-portal

---

## Uniswap V4 Hooks — Key Technical Concept

- V4 Hooks allow custom logic to execute at specific points in a pool's lifecycle (before/after swap, before/after liquidity change, etc.)
- This hackathon **requires** building novel Hook contract logic
- Contracts must be deployed on X Layer mainnet or testnet with verifiable addresses

---

## Disqualification Risks

- Dishonest conduct or plagiarism
- Multiple accounts / wash trading
- Sanctions screening at registration and pre-payout
- Violating X Layer Terms of Service

---

## IP & Legal

- Participants retain full IP ownership
- Organizers receive non-exclusive license
- Prizes to self-custodial wallets only

---

## Previous Hackathon Intelligence

### Build X Hackathon — April 2026 Edition (Previous Season)
- Ran April 1–15, 2026 (already concluded)
- Focus: AI agents — two arenas:
  - **X Layer Arena**: full-stack agentic applications deployed on X Layer
  - **Skills Arena**: reusable agent skills/modules
- Special prizes: "Most Active Agent", "Most Popular", "Best Uniswap Integration" (500 USDT each)
- Judging: AI agent judges reviewed code + onchain data; human judges evaluated creativity/practicality
- No publicly accessible winner list found — XLayer announces via Twitter/X only

### OKX ETHCC Hackathon Winners (Best XLayer proxy data)
Most relevant real-world data on what wins OKX/XLayer ecosystem hackathons:

| Prize | Project | What It Did | Why It Won |
|---|---|---|---|
| 1st (Infrastructure) | **Yamata** | DeFi superapp with hybrid CLOB + arbitrage bots connecting OKX DEX to orderbook | Technical depth + real-world trading utility |
| 2nd (Infrastructure) | **AgenPay** | AI crypto payment system in Notion workspace, multi-token OKX DEX integration | AI + practical use case |
| 1st (DeFi) | **Trendpup** | AI memecoin assistant with multi-agent architecture, trade recommendations via OKX DEX | AI + trending topic (memecoins) |
| 2nd (DeFi) | **Lendbit Finance** | Cross-chain lending with collateral-backed borrowing, OKX swap integration | Cross-chain + real yield |
| 1st (UX/AA) | **Eolia Wallet** | Smart wallet combining X Layer + OKX DEX with account abstraction | Onboarding simplification |
| 2nd (UX/AA) | **Defi in Oneclick** | WebAuthn passkeys + ERC-4337 AA, email/fingerprint login | UX innovation |
| Special | **Escrowzy OKX** | Gamified DeFi on XLayer — P2P trading + battle mechanics with NFT rewards | Gamification + XLayer-native |
| Special | **Rivalz** | ERC-6551 NFT agents generating yield via OKX DEX API | Novel NFT + income mechanism |

**Patterns that win OKX hackathons:**
1. AI integration is heavily rewarded
2. Real utility + novel mechanism beats pure novelty
3. Deep OKX/X Layer ecosystem integration (use their DEX API, their tools)
4. Gamification resonates (Escrowzy)
5. Cross-chain features demonstrate ambition
6. Practical user onboarding stories win UX tracks

### Uniswap V4 Hook Hackathon Winners (Directly relevant — V4 hooks required)
From Unichain Infinite Hackathon and NYC Hackathon:

| Project | Hook Concept | Why It Won |
|---|---|---|
| **Shift0x Prediction Market Hook** | Any V4 pool can host prediction markets — bet on future price above/below current | Eliminates centralized oracles, decentralized leverage, novel LP hedging |
| **Unipump** | pump.fun on EVM via bonding curve hooks — primary token launch via Uniswap | Novel launch mechanism, mass market appeal |
| **Swoupon** | ERC-20 LP rewards + dynamic fee adjustments | Incentivizes LPs, real utility |
| **MiladyBank** | Lending protocol built on V4 hooks, optimized interest rates | Capital efficiency story |

**V4 Hook patterns that win:**
1. Prediction/options logic baked into pool = high innovation score
2. Dynamic fees based on external events = practical + novel
3. Combined AMM + other DeFi primitive (lending, prediction, launch)
4. Real problem solved (impermanent loss, liquidity incentives)

---

## Track-by-Track Winning Probability Analysis

| Track | World Cup Fit | V4 Hook Fit | Innovation Ceiling | Build Complexity | **Win Probability** |
|---|---|---|---|---|---|
| **Prediction Markets** | ★★★★★ | ★★★★★ | Very high | Medium-High | **#1 — Highest** |
| **Trading** | ★★★★☆ | ★★★★☆ | High | Medium | **#2** |
| **AI Agent** | ★★★☆☆ | ★★★☆☆ | Very high | Very high | **#3 (risky)** |
| **GameFi** | ★★★★☆ | ★★★☆☆ | Medium | High | **#4** |
| **NFT** | ★★★☆☆ | ★★☆☆☆ | Low-Medium | Low | **#5** |
| **Social** | ★★★☆☆ | ★★☆☆☆ | Low | Low | **#6** |

### Why Prediction Markets is the #1 Track
- **World Cup** is the single biggest global sports betting/prediction event (~$100B+ in bets)
- **V4 Hooks** are a perfect fit: pool lifecycle events can trigger prediction market logic (match start = open positions, match end = settlement)
- **Judges care about market potential**: World Cup prediction markets have massive real-world demand
- **Precedent exists**: Shift0x won a Uniswap hackathon with exactly this mechanism
- **Innovation**: combining sports prediction with AMM liquidity is genuinely novel
- **Completion**: can be demonstrated end-to-end with a match prediction + resolution flow

### Recommended Winning Formula
**World Cup Prediction Market AMM on X Layer using Uniswap V4 Hooks**
- Users deposit liquidity on match outcomes (Team A wins / Draw / Team B wins)
- V4 Hook manages position creation, liquidity rebalancing, and post-match settlement
- Odds dynamically adjust as liquidity moves between outcome pools
- Optional: AI agent layer for auto-trading based on pre-match sentiment data
- On X Layer for near-zero fees (critical for micro-bets)
- Integration with Chainlink/API3 oracle for match result feed (already on X Layer ecosystem)

---

## Strategic Notes

- **Deadline pressure:** 6 days remain (today is May 22, deadline May 28)
- **Social media is mandatory** — start posting early, tag all three accounts (@XLayerOfficial, @Uniswap, @flapdotsh)
- World Cup 2026 FIFA runs June–July 2026 — hackathon captures *anticipation traffic*, product ships just before tournament starts
- **Note:** Twitter/X threads from @XLayerOfficial (tweet IDs 2048697, 2049847, 2050402) are behind auth wall — could not scrape directly. Contents unknown but referenced in XCup announcement tweet 2057793.
- **Bonus:** demo video is optional but every winning project should have one — make it show a live end-to-end flow
- Building on X Layer = cheap to demo (sub-cent transactions), easy to show "5,000 users onboarded" metrics
- Flap (@flapdotsh) is a sponsor — worth researching what Flap does and integrating with it
