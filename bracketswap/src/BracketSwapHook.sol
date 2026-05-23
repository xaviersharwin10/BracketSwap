// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/// @notice BracketSwap hook — 4 jobs: Gatekeeper, Bookkeeper, State Machine, Dynamic Fees.
/// @dev Golden rule: this contract never calls PoolManager.unlock(). All pool ops go through BracketRouter.
contract BracketSwapHook is IHooks {
    using PoolIdLibrary for PoolKey;

    // ──────────────────────────────────────────────────────────────────────
    // Types
    // ──────────────────────────────────────────────────────────────────────

    enum MatchState {
        OPEN,
        LIVE,
        SETTLED
    }

    struct MatchPool {
        PoolKey poolA;
        PoolKey poolB;
        address teamA;
        address teamB;
        uint256 kickoffTime;
        MatchState state;
        address winner;
        uint8 round; // 1=Group, 2=R16, 3=QF, 4=SF, 5=Final
        uint256 totalWinnerLiquidity;
        uint256 totalPot;
    }

    struct Position {
        address owner;
        uint128 liquidityShares;
        address teamSide;
        bytes32 matchId;
        int24 tickLower;
        int24 tickUpper;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Storage
    // ──────────────────────────────────────────────────────────────────────

    IPoolManager public immutable poolManager;
    address public admin;
    address public router; // set once via setRouter after deploy
    address public oracle; // set once via setOracle after deploy

    mapping(bytes32 => MatchPool) public matches;
    mapping(PoolId => bytes32) public poolToMatchId;
    mapping(uint256 => Position) public positions;
    mapping(bytes32 => uint256) public payoutMultiplier; // 1e18-scaled: totalPot / totalWinnerLiquidity

    uint256 public nextPositionId;

    // ──────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────

    event MatchRegistered(bytes32 indexed matchId, address teamA, address teamB, uint256 kickoffTime);
    event MatchLive(bytes32 indexed matchId);
    event MatchSettled(bytes32 indexed matchId, address winner, uint256 payoutMultiplier);
    event PositionRecorded(uint256 indexed positionId, address owner, bytes32 matchId, address teamSide);
    event PositionDeleted(uint256 indexed positionId);

    // ──────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────

    error NotRouter();
    error NotOracle();
    error NotPoolManager();
    error MatchNotOpen();
    error MatchNotLive();
    error MatchNotSettled();
    error MatchAlreadyExists();
    error TooEarlyForLive();
    error InvalidPool();
    error SwapsBlocked();

    // ──────────────────────────────────────────────────────────────────────
    // Modifiers
    // ──────────────────────────────────────────────────────────────────────

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    modifier onlyOracle() {
        if (msg.sender != oracle) revert NotOracle();
        _;
    }

    modifier onlyRouter() {
        if (msg.sender != router) revert NotRouter();
        _;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────

    constructor(IPoolManager _poolManager, address _admin) {
        poolManager = _poolManager;
        admin = _admin;
    }

    function setRouter(address _router) external {
        require(msg.sender == admin && router == address(0), "BracketSwap: already set");
        router = _router;
    }

    function setOracle(address _oracle) external {
        require(msg.sender == admin && oracle == address(0), "BracketSwap: already set");
        oracle = _oracle;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Hook flags — encoded into the contract address at deploy time
    // Required flags: afterInitialize, beforeAddLiquidity, afterAddLiquidity,
    //                 beforeRemoveLiquidity, afterRemoveLiquidity, beforeSwap
    // ──────────────────────────────────────────────────────────────────────

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ──────────────────────────────────────────────────────────────────────
    // Admin: Register match (called by router/deployer before pool init)
    // ──────────────────────────────────────────────────────────────────────

    function registerMatch(
        bytes32 matchId,
        PoolKey calldata poolA,
        PoolKey calldata poolB,
        address teamA,
        address teamB,
        uint256 kickoffTime,
        uint8 round
    ) external onlyRouter {
        if (matches[matchId].kickoffTime != 0) revert MatchAlreadyExists();
        matches[matchId] = MatchPool({
            poolA: poolA,
            poolB: poolB,
            teamA: teamA,
            teamB: teamB,
            kickoffTime: kickoffTime,
            state: MatchState.OPEN,
            winner: address(0),
            round: round,
            totalWinnerLiquidity: 0,
            totalPot: 0
        });
        poolToMatchId[poolA.toId()] = matchId;
        poolToMatchId[poolB.toId()] = matchId;
        emit MatchRegistered(matchId, teamA, teamB, kickoffTime);
    }

    // ──────────────────────────────────────────────────────────────────────
    // State Machine (oracle-controlled)
    // ──────────────────────────────────────────────────────────────────────

    function setMatchLive(bytes32 matchId) external onlyOracle {
        MatchPool storage m = matches[matchId];
        if (m.state != MatchState.OPEN) revert MatchNotOpen();
        if (block.timestamp < m.kickoffTime) revert TooEarlyForLive();
        m.state = MatchState.LIVE;
        emit MatchLive(matchId);
    }

    /// @param totalWinnerLiquidity Total liquidity shares on the winning pool side (supplied by router after drainLosingPool)
    /// @param totalPot Total USDC in both pools combined
    function settleMatch(bytes32 matchId, address winningTeam, uint256 totalWinnerLiquidity, uint256 totalPot)
        external
        onlyOracle
    {
        MatchPool storage m = matches[matchId];
        if (m.state != MatchState.LIVE) revert MatchNotLive();
        m.state = MatchState.SETTLED;
        m.winner = winningTeam;
        m.totalWinnerLiquidity = totalWinnerLiquidity;
        m.totalPot = totalPot;
        payoutMultiplier[matchId] = (totalPot * 1e18) / totalWinnerLiquidity;
        emit MatchSettled(matchId, winningTeam, payoutMultiplier[matchId]);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Hook callbacks — IHooks implementation
    // ──────────────────────────────────────────────────────────────────────

    // Job 1 — Gatekeeper: block ops on wrong-state pools

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24) external view override onlyPoolManager returns (bytes4) {
        // Confirm the pool is registered (router calls registerMatch before initializing)
        bytes32 matchId = poolToMatchId[key.toId()];
        if (matchId == bytes32(0)) revert InvalidPool();
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(address, PoolKey calldata key, ModifyLiquidityParams calldata, bytes calldata)
        external
        view
        override
        onlyPoolManager
        returns (bytes4)
    {
        bytes32 matchId = poolToMatchId[key.toId()];
        if (matchId == bytes32(0)) revert InvalidPool();
        if (matches[matchId].state != MatchState.OPEN) revert MatchNotOpen();
        return IHooks.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(address, PoolKey calldata key, ModifyLiquidityParams calldata, bytes calldata)
        external
        view
        override
        onlyPoolManager
        returns (bytes4)
    {
        bytes32 matchId = poolToMatchId[key.toId()];
        if (matchId == bytes32(0)) revert InvalidPool();
        MatchState state = matches[matchId].state;
        // Allow remove only when OPEN (user exits early) or SETTLED (claiming/rolling)
        if (state == MatchState.LIVE) revert MatchNotOpen();
        return IHooks.beforeRemoveLiquidity.selector;
    }

    // Job 4 — Dynamic Fees: time-to-kickoff schedule

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        external
        view
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bytes32 matchId = poolToMatchId[key.toId()];
        if (matchId == bytes32(0)) revert InvalidPool();
        if (matches[matchId].state != MatchState.OPEN) revert SwapsBlocked();
        uint24 fee = _computeFee(matches[matchId].kickoffTime);
        // Set the override flag so PoolManager uses this fee
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    // Job 2 — Bookkeeper: record and delete positions

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        bytes32 matchId = poolToMatchId[key.toId()];
        // hookData carries the real user address (router passes it through)
        address owner = hookData.length >= 32 ? abi.decode(hookData, (address)) : sender;
        address teamSide = _getTeamSide(key, matchId);
        uint256 positionId = nextPositionId++;
        positions[positionId] = Position({
            owner: owner,
            liquidityShares: uint128(uint256(params.liquidityDelta > 0 ? uint256(int256(params.liquidityDelta)) : 0)),
            teamSide: teamSide,
            matchId: matchId,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper
        });
        emit PositionRecorded(positionId, owner, matchId, teamSide);
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (hookData.length >= 32) {
            uint256 positionId = abi.decode(hookData, (uint256));
            emit PositionDeleted(positionId);
            delete positions[positionId];
        }
        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // Unused hooks — required by IHooks interface

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        override
        returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ──────────────────────────────────────────────────────────────────────

    function _computeFee(uint256 kickoffTime) internal view returns (uint24) {
        if (block.timestamp >= kickoffTime) revert SwapsBlocked();
        uint256 remaining = kickoffTime - block.timestamp;
        if (remaining > 48 hours) return 10000; // 1.00%
        if (remaining > 24 hours) return 6000; // 0.60%
        if (remaining > 6 hours) return 3000; // 0.30%
        return 1000; // 0.10%
    }

    function _getTeamSide(PoolKey calldata key, bytes32 matchId) internal view returns (address) {
        MatchPool storage m = matches[matchId];
        return PoolId.unwrap(key.toId()) == PoolId.unwrap(m.poolA.toId()) ? m.teamA : m.teamB;
    }

    // ──────────────────────────────────────────────────────────────────────
    // View helpers
    // ──────────────────────────────────────────────────────────────────────

    function getMatch(bytes32 matchId) external view returns (MatchPool memory) {
        return matches[matchId];
    }

    function getPosition(uint256 positionId) external view returns (Position memory) {
        return positions[positionId];
    }

    function getMatchIdForPool(PoolKey calldata key) external view returns (bytes32) {
        return poolToMatchId[key.toId()];
    }
}
