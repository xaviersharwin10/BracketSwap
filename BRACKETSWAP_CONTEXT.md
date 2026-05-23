# BracketSwap — Full Architecture & Context Document

> Created: 2026-05-22 | Status: Confirmed idea, pre-implementation

---

## What Is BracketSwap?

BracketSwap is a **World Cup Tournament Liquidity Protocol** built on Uniswap V4 Hooks, deployed on X Layer.

It transforms the FIFA World Cup bracket structure into a chain of AMM prediction pools where:
- Every match has its own pair of outcome liquidity pools (Team A WIN / USDC and Team B WIN / USDC)
- A single Uniswap V4 Hook enforces the entire match lifecycle as a state machine
- Winning LPs receive a **BracketReceipt NFT** that encodes their payout entitlement AND can be redeemed directly into the next-round pool (bracket rollover)
- Dynamic fees shift as kickoff approaches — rewarding early LPs and maximizing price discovery near match time

The result: a composable, self-playing prediction market that follows the World Cup from Group Stage → Round of 16 → Quarterfinals → Semifinals → Final.

---

## Why This Wins

### Against Judging Criteria

| Criterion | How BracketSwap Satisfies It |
|---|---|
| **Innovation** | First protocol to chain AMM pool outcomes across tournament rounds via composable receipt NFTs. Dynamic fee schedule tied to real-world match timing. Bracket topology in DeFi is genuinely novel. |
| **Market Potential** | World Cup 2026 = ~$100B+ in global bets. X Layer's $0.0005/tx makes micro-bets viable. Launches just as tournament begins June 2026. |
| **Completion** | End-to-end flow is demonstrable: LP → swap → oracle settles → receipt minted → redeem into next round. Every step is on-chain and verifiable. |
| **Demo Video** | Natural narrative: "I staked $50 on Brazil, they won, I got a BracketReceipt, I redeemed into the Quarter-final pool, they won again…" |

### Against Hard Requirements

| Requirement | Status |
|---|---|
| World Cup themed | Core concept IS the World Cup bracket |
| Built on X Layer | All contracts deploy on X Layer EVM |
| Uniswap V4 Hook mechanism | Hook is the central piece — enforces all logic |
| NEW hook contract logic built during hackathon | BracketSwap hook is purpose-built |
| V4 Pool + Hook contracts deployed on X Layer | Required, achievable |
| Twitter/X account tagging sponsors | Must create + post throughout |
| Active social media during hackathon | Required |
| Submitted via Google Form | Required |

---

## System Architecture

```
  User / Frontend
       │
       ▼
  ┌────────────────────────────────────────────────────────────────┐
  │                    X LAYER (EVM L2)                            │
  │                                                                │
  │  ┌──────────────────────────────────────────────────────────┐  │
  │  │                   BracketRouter                          │  │
  │  │  (implements IUnlockCallback)                            │  │
  │  │                                                          │  │
  │  │  addLiquidity()   rollover()   claimWinnings()           │  │
  │  │  claimReceipt()   redeemReceipt()   drainLosingPool()    │  │
  │  │  unlockCallback() — all multi-pool ops go here           │  │
  │  └──────────┬───────────────────────────┬───────────────────┘  │
  │             │ unlock() / modifyLiquidity │ mint() / burn()      │
  │             ▼                           ▼                       │
  │  ┌──────────────────────┐   ┌───────────────────────────────┐  │
  │  │  Uniswap V4          │   │  BracketReceipt ERC-721       │  │
  │  │  PoolManager         │   │  escrow[receiptId] = usdcAmt  │  │
  │  │                      │   └───────────────────────────────┘  │
  │  │  Pool A (TeamA/USDC) │                                       │
  │  │  Pool B (TeamB/USDC) │                                       │
  │  └──────────┬───────────┘                                       │
  │             │ hook callbacks                                     │
  │             ▼                                                    │
  │  ┌──────────────────────────────────────────────────────────┐   │
  │  │                  BracketSwapHook                         │   │
  │  │  (callbacks only — never calls PoolManager.unlock())     │   │
  │  │                                                          │   │
  │  │  ① Gatekeeper    — beforeAddLiquidity, beforeSwap,      │   │
  │  │                     beforeRemoveLiquidity                │   │
  │  │  ② Bookkeeper    — afterAddLiquidity, afterRemove        │   │
  │  │  ③ State Machine — setMatchLive(), settleMatch()         │   │
  │  │  ④ Dynamic Fees  — beforeSwap returns fee override       │   │
  │  │                                                          │   │
  │  │  poolToMatchId[PoolId] mapping — no reliance on hookData │   │
  │  │  for matchId lookup                                      │   │
  │  └──────────────────────────────────────────────────────────┘   │
  │                                                                │
  │  ┌──────────────────────────────────────────────────────────┐   │
  │  │  MockOracle (admin-callable for demo)                    │   │
  │  │  → calls BracketSwapHook.setMatchLive() / settleMatch()  │   │
  │  └──────────────────────────────────────────────────────────┘   │
  └────────────────────────────────────────────────────────────────┘
```

**The golden rule:** Router calls PoolManager. PoolManager calls Hook. Hook never calls PoolManager back.

---

## Pool Structure

Each World Cup match spawns exactly **two pools** in the Uniswap V4 PoolManager:

```
Match: Brazil vs Germany

Pool A: BRA_WIN/USDC   (LP here = you believe Brazil wins)
Pool B: GER_WIN/USDC   (LP here = you believe Germany wins)
```

- `BRA_WIN` and `GER_WIN` are ERC-20 "outcome tokens" minted by the hook (worthless if team loses, redeemable if team wins)
- USDC is the base currency for all pools (stable, universally understood)
- Both pools share the same Hook contract
- A `matchId` (bytes32) maps both pools to a single `MatchPool` struct

### Why Two Pools Instead of One?

A single pool for outcome A vs outcome B would require a specialized AMM invariant. Two USDC-paired pools is:
1. Directly compatible with standard Uniswap V4 CPMM math
2. Price in each pool = implied probability of that outcome
3. Price discovery happens through normal swapping — no custom math needed
4. Composable with the rest of Uniswap V4 ecosystem

---

## Core Data Structures

```solidity
// Match lifecycle
enum MatchState { OPEN, LIVE, SETTLED }

// One match = two pools + metadata
struct MatchPool {
    PoolKey poolA;          // Team A WIN / USDC pool key
    PoolKey poolB;          // Team B WIN / USDC pool key
    address teamA;          // Address of Team A outcome token
    address teamB;          // Address of Team B outcome token
    uint256 kickoffTime;    // Unix timestamp when match starts
    MatchState state;       // OPEN → LIVE → SETTLED
    address winner;         // Set at settlement (address(0) until then)
    uint8   round;          // 1=Group, 2=R16, 3=QF, 4=SF, 5=Final
    uint256 totalWinnerLiquidity; // set by router during drainLosingPool, used to compute multiplier
    uint256 totalPot;             // winner + loser USDC, set same time
}

// One LP position (stored in hook, not pool manager)
struct Position {
    address owner;
    uint128 liquidityShares; // Share of pool (matches V4 liquidity type)
    address teamSide;        // Which outcome token pool they LPed into
    bytes32 matchId;
    int24   tickLower;       // Needed for remove liquidity call
    int24   tickUpper;
}

// BracketReceipt NFT metadata (stored on-chain in NFT contract)
struct ReceiptData {
    bytes32 matchId;        // Which match was won
    address winningTeam;    // Which team they backed
    uint256 usdcEntitlement;// USDC they can claim OR roll into next round
    uint8   tournamentRound; // 1=Group, 2=R16, 3=QF, 4=SF, 5=Final
    bool    redeemed;       // True after claim or rollover
}
```

---

## The Hook's Four Jobs

The hook has **four jobs only — all are callbacks**. It never initiates pool operations. Settlement (claim, rollover, receipt) lives entirely in `BracketRouter`.

### Job 1 — Gatekeeper (`beforeAddLiquidity`, `beforeSwap`, `beforeRemoveLiquidity`)

Enforces lifecycle access rules. **Cannot be bypassed** — PoolManager routes all calls through the hook.

```
OPEN state:    LP ✓  |  Swap ✓  |  Remove ✓
LIVE state:    LP ✗  |  Swap ✗  |  Remove ✗  (match in progress)
SETTLED state: LP ✗  |  Swap ✗  |  Remove by router only (authorized)
```

**matchId is always derived from the pool key — never from hookData.**
The hook maintains `mapping(PoolId => bytes32) public poolToMatchId` populated at pool init.

```solidity
function beforeAddLiquidity(
    address, PoolKey calldata key, IPoolManager.ModifyLiquidityParams calldata, bytes calldata
) external override returns (bytes4) {
    bytes32 matchId = poolToMatchId[key.toId()];
    require(matches[matchId].state == MatchState.OPEN, "BracketSwap: match not open");
    return BaseHook.beforeAddLiquidity.selector;
}
```

### Job 2 — Bookkeeper (`afterAddLiquidity`, `afterRemoveLiquidity`)

Records and deletes LP positions in hook-owned storage. Since all add/remove goes through BracketRouter, `hookData` carries the **real user's address** (router is the V4 position owner, user is the BracketSwap-level owner).

```solidity
function afterAddLiquidity(
    address sender,          // = BracketRouter address
    PoolKey calldata key,
    IPoolManager.ModifyLiquidityParams calldata params,
    BalanceDelta delta,
    BalanceDelta feeDelta,
    bytes calldata hookData  // = abi.encode(realUserAddress)
) external override returns (bytes4, BalanceDelta) {
    bytes32 matchId = poolToMatchId[key.toId()];
    address owner = hookData.length >= 32
        ? abi.decode(hookData, (address))
        : sender;
    positions[nextPositionId++] = Position({
        owner: owner,
        liquidityShares: uint128(uint256(int256(params.liquidityDelta))),
        teamSide: _getTeamSide(key, matchId),
        matchId: matchId,
        tickLower: params.tickLower,
        tickUpper: params.tickUpper
    });
    return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
}

function afterRemoveLiquidity(
    address, PoolKey calldata key,
    IPoolManager.ModifyLiquidityParams calldata params,
    BalanceDelta, BalanceDelta, bytes calldata hookData
) external override returns (bytes4, BalanceDelta) {
    uint256 positionId = abi.decode(hookData, (uint256));
    delete positions[positionId];
    return (BaseHook.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
}
```

### Job 3 — State Machine (`setMatchLive`, `settleMatch`)

Non-callback admin functions that advance match state. Called by oracle (or admin for demo).
`settleMatch` also stores `payoutMultiplier` so BracketRouter can compute payouts during claims.

```solidity
mapping(PoolId => bytes32) public poolToMatchId;
mapping(bytes32 => uint256) public payoutMultiplier; // matchId → 1e18-scaled multiplier

function setMatchLive(bytes32 matchId) external onlyOracle {
    require(matches[matchId].state == MatchState.OPEN, "Not OPEN");
    require(block.timestamp >= matches[matchId].kickoffTime, "Too early");
    matches[matchId].state = MatchState.LIVE;
    emit MatchLive(matchId);
}

function settleMatch(
    bytes32 matchId,
    address winningTeam,
    uint256 totalWinnerLiquidity,  // supplied by router after drainLosingPool
    uint256 totalPot               // winner + loser pool USDC, supplied by router
) external onlyOracle {
    MatchPool storage match_ = matches[matchId];
    require(match_.state == MatchState.LIVE, "Not LIVE");
    match_.state = MatchState.SETTLED;
    match_.winner = winningTeam;
    payoutMultiplier[matchId] = (totalPot * 1e18) / totalWinnerLiquidity;
    emit MatchSettled(matchId, winningTeam, payoutMultiplier[matchId]);
}
```

### Job 4 — Dynamic Fee Engine (`beforeSwap`)

Returns a per-swap fee override based on time-to-kickoff. Higher fees early (reward committed LPs), lower near kickoff (maximize price discovery). matchId always from `poolToMatchId`, never from user-supplied hookData (swapper hookData is untrusted).

```solidity
function beforeSwap(
    address,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata,
    bytes calldata
) external override returns (bytes4, BeforeSwapDelta, uint24) {
    bytes32 matchId = poolToMatchId[key.toId()];
    MatchPool storage match_ = matches[matchId];
    require(match_.state == MatchState.OPEN, "BracketSwap: swaps blocked");
    uint24 fee = _computeFee(match_.kickoffTime);
    return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee);
}

function _computeFee(uint256 kickoffTime) internal view returns (uint24) {
    if (block.timestamp >= kickoffTime) revert MatchLive();
    uint256 timeRemaining = kickoffTime - block.timestamp;
    if (timeRemaining > 48 hours) return 10000;  // 1.00%
    if (timeRemaining > 24 hours) return 6000;   // 0.60%
    if (timeRemaining > 6 hours)  return 3000;   // 0.30%
    return 1000;                                  // 0.10%
}
```

Pool must be initialized with dynamic fee flag:
```solidity
poolKey.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG; // = 0x800000
```

---

## Parimutuel Payout Logic

The settlement math follows parimutuel wagering (150 years old, well-understood):

```
totalPot = winningPoolLiquidity + losingPoolLiquidity
payoutMultiplier = totalPot / winningPoolLiquidity
individual_payout = position_shares * payoutMultiplier
```

**Example:**
```
Brazil pool: $10,000 USDC (100 LPs, $100 average)
Germany pool: $3,000 USDC
Total pot: $13,000 USDC

payoutMultiplier = 13,000 / 10,000 = 1.3x
An LP who deposited $1,000 into Brazil pool gets $1,300 back
```

The payout math is NOT novel. The architecture around it is: two V4 pools per match, dynamic fees, BracketReceipt rollover, tournament topology.

---

## BracketReceipt NFT

ERC-721 contract, separate from both the hook and the router.

**Key properties:**
- Minted and burned by `BracketRouter` only (not the hook — hook never calls PoolManager.unlock())
- Encodes USDC entitlement on-chain (not just off-chain metadata)
- USDC escrow keyed by receiptId (not by address) — entitlement follows the NFT when transferred
- Can be transferred/traded — someone can buy your right to enter the next round pool
- Single-use: burned on redemption or cash-out
- Shows in any NFT wallet (OpenSea, OKX NFT marketplace)

**Why it matters for the demo:**
- Tangible artifact of winning — judges can see it in a wallet
- The "bracket rollover" flow is physically represented by an NFT
- Composable: "buy someone else's Brazil semi-final position" is a real secondary market
- `escrow[receiptId]` in BracketReceipt contract holds actual USDC, not a promise

---

## Chainlink Oracle Integration

Chainlink is live on X Layer ecosystem. Two approaches:

**Production approach (Chainlink Functions):**
```
HTTP request to football-data.org API → Chainlink DON signs result → on-chain
```

**Demo approach (admin-callable fallback):**
```solidity
address public admin;
modifier onlyOracle() {
    require(msg.sender == admin || msg.sender == oracleAddress, "Unauthorized");
    _;
}
```
For hackathon demo: admin key calls `settleMatch()` directly after manually checking results. This is honest — show the architecture, note that production uses Chainlink, demo uses admin for simplicity.

---

## OKX Onchain OS Integration

Three integration points:

### 1. x402 Gas-Free Entry (Highest Impact — Load-Bearing)
Users pay USDC directly for their LP position — no OKB needed. BracketRouter calls the x402 payment protocol before executing `addLiquidity`.
- Demo pitch: "First-time user, never bought OKB, staked Brazil in 30 seconds"
- Directly solves the #1 onboarding friction on any L2
- This is LOAD-BEARING: without it, users need OKB before they can participate

### 2. OKX DEX API — Multi-Token Entry
Users can deposit ETH, OKB, or any token to LP. BracketRouter calls OKX DEX API to swap the input token → USDC, then adds USDC liquidity.
```
User deposits 0.01 ETH:
  → BracketRouter calls OKX DEX API: 0.01 ETH → USDC (best rate, 500+ DEXes)
  → Resulting USDC added as liquidity to the chosen match pool
```
This is LOAD-BEARING: greatly expands who can participate without manual USDC acquisition.

**Note on losing pool drain:** When `drainLosingPool()` is called, removing liquidity from Pool B returns USDC directly from the PoolManager — no swap needed. Losing-side outcome tokens (GER_WIN) received during removal are simply burned. The USDC recovered is then available for winner payouts via `payoutMultiplier`.

### 3. OKX Agentic Wallet — Auto-Rollover (Bonus)
If time permits: OKX Agentic Wallet monitors user's BracketReceipts and auto-redeems into the next round pool when it opens. User sets up once, wallet plays the whole tournament.

---

## Tournament Structure (Demo Path)

For the hackathon demo, we trace one team's path through 3 rounds:

```
World Cup 2026 — Brazil's path (hypothetical):

Round 1 (Group Stage): 
  Match: Brazil vs Germany
  Pool opens → LPs stake → kickoff → oracle settles → BracketReceipt minted

Round 2 (Round of 16): 
  Match: Brazil vs Spain
  BracketReceipt redeemed → LP in new pool → kickoff → oracle settles → new receipt

Round 3 (Quarterfinals):
  Match: Brazil vs France
  BracketReceipt redeemed → LP in new pool → kickoff → oracle settles → claim USDC
```

This gives a complete 3-match demo flow showing all features.

---

## Contract Architecture — Correct Design

### The Core Rule
> The hook **never** calls `PoolManager.unlock()`. The router **never** enforces business logic. The hook is the brain, the router is the hands.

V4's `PoolManager` holds a mutex on `unlock()`. Hook callbacks fire **from inside** an existing `unlock()` — they cannot re-enter with a new one. Therefore the hook must never initiate pool operations. All pool operations go through `BracketRouter`.

### Separation of Responsibilities

| Contract | Role |
|---|---|
| `BracketSwapHook` | Hook callbacks only: gatekeeper, bookkeeper, state machine, dynamic fees |
| `BracketRouter` | All pool operations: addLiquidity, rollover, claimWinnings, drainLosingPool |
| `BracketReceipt` | ERC-721 NFT + USDC escrow mapping keyed by receiptId |
| `OutcomeToken` | ERC-20 team outcome token (one per team per match) |
| `MockOracle` | Admin oracle wrapper for hackathon demo |

### How Rollover Works — Atomic Flash Accounting

Single `PoolManager.unlock()` call from `BracketRouter`:

```
User calls: BracketRouter.rollover(positionId, nextMatchId, teamSide)

BracketRouter validates:
  ✓ msg.sender owns the position
  ✓ old match is SETTLED
  ✓ old position backed the winning team

BracketRouter calls: PoolManager.unlock(encodedRolloverData)

PoolManager calls back: BracketRouter.unlockCallback(data)

Inside unlockCallback — atomic, single tx:
  Step 1: Remove from old winning pool
          PoolManager.modifyLiquidity(oldPoolKey, {delta: -pos.shares}, ...)
          → hook.beforeRemoveLiquidity: checks SETTLED state ✓
          → hook.afterRemoveLiquidity: deletes old position record ✓
          → PoolManager credits USDC to router

  Step 2: Apply payout multiplier
          payoutUsdc = (pos.shares * payoutMultiplier[matchId]) / 1e18
          Extra USDC from losing pool was drained into PoolManager at settlement

  Step 3: Add to new match pool
          PoolManager.modifyLiquidity(newPoolKey, {delta: +newShares}, abi.encode(user))
          → hook.beforeAddLiquidity: checks OPEN state ✓
          → hook.afterAddLiquidity: records position owner = user (from hookData)
            Note: router is the V4 position holder; hook tracks real user in its own storage

  Step 4: Settle net delta
          USDC flows from old pool to new pool — net zero
          Any multiplier profit above stake returned to user's wallet
```

### BracketReceipt — Two Settlement Paths

**Path A — Atomic rollover (no receipt needed):**
```
rollover(positionId, nextMatchId, teamSide)
→ remove from old pool + add to new pool in one unlock tx
→ no NFT minted, position moves directly
```

**Path B — Receipt (tradable position):**
```
Step 1: claimReceipt(positionId)
  → Router removes position from winning pool
  → USDC held in BracketReceipt.escrow[receiptId]
  → BracketReceipt NFT minted (encodes usdcAmount, team, round)

Step 2 (optional): User transfers receipt to anyone
  → escrow[receiptId] stays with the receipt ID (not the address)
  → New owner has claim to the USDC

Step 3: redeemReceipt(receiptId, nextMatchId, teamSide)
  → Receipt owner (not original minter) calls this
  → Router takes escrow[receiptId] → adds to new pool
  → Receipt burned, new position recorded for caller
```

### Losing Pool Drain at Settlement

When `settleMatch()` is called, losing-side LPs lose their stake (prediction market — bet wrong, lose). Their USDC must be made available for winners' multiplied payouts:

```solidity
// Called by oracle immediately after settleMatch
function drainLosingPool(bytes32 matchId) external onlyOracle {
    // BracketRouter calls PoolManager.unlock()
    // Inside callback: removes ALL losing-side LP positions
    // USDC credited to PoolManager, available for winner claims
    // Records totalLiquidity drained → used to compute payoutMultiplier
}
```

### Hook Correctly Records User (not Router) as Position Owner

Since router is the V4 position holder, the hook reads user's address from `hookData`:

```solidity
function afterAddLiquidity(
    address sender, // this is BracketRouter, not the user
    PoolKey calldata key,
    IPoolManager.ModifyLiquidityParams calldata params,
    BalanceDelta delta,
    BalanceDelta feeDelta,
    bytes calldata hookData
) external override returns (bytes4, BalanceDelta) {
    bytes32 matchId = _getMatchId(key);
    // Read real owner from hookData if present (set by router), else use sender
    address owner = hookData.length >= 32
        ? abi.decode(hookData, (address))
        : sender;
    positions[nextPositionId++] = Position({
        owner: owner,
        liquidityShares: uint256(int256(params.liquidityDelta)),
        teamSide: _getTeamSide(key, matchId),
        matchId: matchId
    });
    return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
}
```

---

## Implementation Plan

### Day 1–2: Core Contracts
**File:** `src/BracketSwapHook.sol` (~350 lines)
- MatchPool struct + mapping, Position struct + mapping, MatchState enum
- beforeAddLiquidity, beforeSwap, beforeRemoveLiquidity (gatekeeper)
- afterAddLiquidity, afterRemoveLiquidity (bookkeeper — reads owner from hookData)
- setMatchLive(), settleMatch() (state machine — onlyOracle)
- computeFee() (dynamic fee engine)

**File:** `src/BracketRouter.sol` (~200 lines)
- Implements IUnlockCallback
- addLiquidity(matchId, teamSide, usdcAmount)
- rollover(positionId, nextMatchId, teamSide) — atomic flash accounting
- claimWinnings(positionId) — remove from pool, send USDC to user
- claimReceipt(positionId) — remove from pool, hold in escrow, mint NFT
- redeemReceipt(receiptId, nextMatchId, teamSide) — add to new pool from escrow
- drainLosingPool(matchId) — called by oracle at settlement
- unlockCallback() — handles all above multi-pool operations

**File:** `src/BracketReceipt.sol` (~80 lines)
- ERC-721 + escrow mapping: `mapping(uint256 receiptId => uint256 usdcAmount)`
- mint(owner, data) — only callable by router
- burn(receiptId) — only callable by router
- escrow[receiptId] set/cleared by router

**File:** `src/OutcomeToken.sol` (~40 lines)
- Standard ERC-20, minted by hook at pool creation

### Day 3: Deployment + Oracle
**File:** `script/Deploy.s.sol` (~100 lines)
- Deploy OutcomeToken ×6 (3 matches × 2 teams)
- Deploy BracketReceipt
- Deploy BracketSwapHook
- Deploy BracketRouter
- Initialize 3 match pools on X Layer (Group → R16 → QF for Brazil path)

**File:** `src/MockOracle.sol` (~30 lines)
- Admin calls setMatchLive() and settleMatch() directly for demo

### Day 4: Frontend
**File:** `frontend/src/`
- Bracket visualization (3 match pools highlighted, rest grayed out)
- LP interface: pick team, enter USDC amount → calls BracketRouter.addLiquidity
- Position tracker: shows open positions, claimable winnings, held receipts
- Receipt redemption UI: click receipt → choose atomic rollover or mint receipt

### Day 5: OKX Integration + Testing
- x402 gas-free entry via OKX Onchain OS
- End-to-end test on X Layer testnet (full demo path: LP → settle → rollover × 2 → claim)
- Record demo video

### Day 6 (buffer): Polish + Submission
- Fix testnet issues, confirm contract addresses on X Layer explorer
- Finalize demo video (2 min, show full $50 → $107 flow)
- Verify all Twitter posts made (tag @XLayerOfficial, @Uniswap, @flapdotsh)
- Submit via Google Form before May 28, 23:59 UTC

---

## Contracts to Write

| Contract | Lines (est.) | Role |
|---|---|---|
| `BracketSwapHook.sol` | ~350 | Hook callbacks only — gatekeeper, bookkeeper, state machine, dynamic fees |
| `BracketRouter.sol` | ~200 | All pool operations via IUnlockCallback — add, remove, rollover, drain |
| `BracketReceipt.sol` | ~80 | ERC-721 NFT + USDC escrow mapping keyed by receiptId |
| `OutcomeToken.sol` | ~40 | ERC-20 team outcome tokens (one per team per match) |
| `MockOracle.sol` | ~30 | Admin oracle for demo |
| `Deploy.s.sol` | ~100 | Foundry deployment script |
| **Total** | **~800** | |

---

## Novelty Map

| Element | Novel? | Evidence |
|---|---|---|
| Multi-round sequential position compounding | YES | No ETHGlobal project found implementing cross-pool receipt rollover |
| Tournament bracket pool topology | YES | No project chains AMM pools in bracket structure |
| BracketReceipt NFT as composable position | YES | NFT-as-LP-receipt in prediction context not found |
| Dynamic fees based on real-world time event | YES | Time-based fees found as use case in V4 docs, no implementation for sports events found |
| Parimutuel payout math | NO (150 years old) | Well-known, disclosed upfront |
| Two-pool-per-match structure | Partially novel | Standard CPMM applied to sports outcomes — the pairing with bracket topology is novel |

**Honest assessment**: The parimutuel math is not novel. The bracket topology + receipt rollover + dynamic fees around a V4 AMM is a genuinely novel combination.

---

## Competitive Differentiation from Known Projects

| Project | What It Did | Why BracketSwap Differs |
|---|---|---|
| Shift0x Prediction Market Hook | Price-based prediction (above/below price target) | BracketSwap uses sports outcomes + tournament continuity, not price targets |
| Polymarket | Centralized CLOB prediction market | Decentralized AMM with V4 Hooks; positions are composable NFTs |
| Any sports betting dapp | Single match, single event, cash out | Multi-round bracket with position rollover; positions persist across the tournament |

---

## Risk Register

| Risk | Severity | Mitigation |
|---|---|---|
| Pool initialization with dynamic fee flag is misconfigured | High | Test on testnet first; use V4 template code |
| Oracle not available before demo | Medium | Admin fallback callable by deployer address for demo |
| BracketReceipt redemption → pool add is a complex multi-call | Medium | Use PoolManager.unlock() pattern; test isolated |
| Running out of time (6 days, solo) | High | Core path: Hook + Receipt + 3 pools + basic frontend only. OKX integration is bonus. |
| Twitter social media requirement missed | Medium | Set daily reminders; post at each major milestone |
| Chainlink on X Layer needs setup time | Low | Admin oracle fallback ready; Chainlink is bonus |

---

## Demo Script (2 minutes)

1. **Open the bracket** — show World Cup bracket on frontend, 3 pools highlighted
2. **Add liquidity** — LP $50 USDC into Brazil WIN pool for Match 1 (Group Stage)
3. **Fast-forward time** — match goes LIVE, swaps are blocked (hook enforces it)
4. **Oracle settles** — Brazil wins, hook computes 1.3x multiplier
5. **Show winning position** — LP can claim $65 USDC OR roll over
6. **Roll over** — click "Roll to Round of 16" → BracketReceipt NFT minted → shown in wallet
7. **Redeem receipt** — NFT is redeemed into R16 Brazil pool, $65 auto-deployed as liquidity
8. **Show all-in** — repeat for QF, final claim is $107 USDC from initial $50
9. **Closing** — "This is BracketSwap: your World Cup bracket is now an on-chain investment strategy"

---

## Social Media Plan

Required: Daily posts during hackathon tagging @XLayerOfficial, @Uniswap, @flapdotsh

**Posts:**
1. Day 1: "Building BracketSwap — World Cup prediction market on @XLayerOfficial using @Uniswap V4 Hooks 🚀 @flapdotsh #BuildX"
2. Day 3: "Core hook contract complete — match lifecycle enforced on-chain. Brazil vs Germany pool is LIVE on @XLayerOfficial testnet"
3. Day 5: "BracketReceipt NFTs are composable: stake Brazil, win, roll your position into the Quarter-finals. All via @Uniswap V4 on @XLayerOfficial"
4. Day 6: "Submitting BracketSwap to #XCup. Watch $50 become $107 following Brazil through the @XLayerOfficial World Cup bracket 🏆"

---

## Key Decisions Made

1. **Two pools per match** (not one outcome pool) — compatible with standard V4 CPMM, no custom invariant needed
2. **BracketReceipt as NFT** (not fungible token) — each position is unique, trades naturally, shows in wallets; USDC escrow keyed by receiptId travels with the NFT
3. **Admin oracle fallback** for demo — honest acknowledgment, production uses Chainlink
4. **USDC as base currency** — stable, universally understood, avoids token price noise
5. **BracketRouter handles all pool operations via IUnlockCallback** — atomic flash accounting for rollover (remove old pool + add new pool in one unlock tx); receipt path decouples in time for tradability. Hook never calls PoolManager.unlock().
6. **matchId always from `poolToMatchId[key.toId()]`** — never from user-supplied hookData; hookData is only used to pass the real user's address from router to hook bookkeeper
7. **Time-to-kickoff fee schedule** (not AMM-imbalance based) — simpler, still novel, achievable in 6 days
8. **OKX DEX API for multi-token entry** — users deposit ETH/OKB, router swaps → USDC before adding liquidity; load-bearing, not decorative. Losing pool drain returns USDC directly (no swap needed — outcome tokens are burned).
9. **x402 for gas-free LP entry** — most impactful OKX integration; users need zero OKB to participate

---

## Hackathon Fit Score

| Dimension | Score | Notes |
|---|---|---|
| World Cup theme | 10/10 | IS the World Cup |
| V4 Hook usage | 10/10 | Hook is the entire system |
| X Layer deployment | 10/10 | EVM-compatible, $0.0005/tx enables micro-bets |
| OKX ecosystem integration | 8/10 | DEX API + x402 both used |
| Innovation | 9/10 | Novel bracket topology + receipt rollover |
| Market potential | 9/10 | $100B+ betting market narrative |
| Solo build feasibility | 7/10 | Tight but achievable with 6 days + scoped MVP |
| Demo video quality | 9/10 | Natural 2-min narrative |

**Overall: Strong contender for 1st or 2nd place**
