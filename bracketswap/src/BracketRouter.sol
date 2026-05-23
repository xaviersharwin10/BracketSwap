// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BracketSwapHook} from "./BracketSwapHook.sol";
import {BracketReceipt} from "./BracketReceipt.sol";

/// @notice BracketRouter — all pool operations go through here via IUnlockCallback.
/// Implements flash accounting for atomic rollover across two pools.
contract BracketRouter is IUnlockCallback {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────────────────────────────
    // Callback action enum (encoded in unlock data)
    // ──────────────────────────────────────────────────────────────────────

    enum Action {
        ADD_LIQUIDITY,
        REMOVE_LIQUIDITY,
        ROLLOVER,
        DRAIN_LOSING_POOL
    }

    // ──────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────

    IPoolManager public immutable poolManager;
    BracketSwapHook public immutable hook;
    BracketReceipt public immutable receipt;
    address public immutable usdc;

    address public admin;

    error NotAdmin();
    error NotOwner();
    error MatchNotSettled();
    error NotWinningSide();
    error ReceiptAlreadyRedeemed();
    error NotReceiptOwner();
    error ZeroLiquidity();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(IPoolManager _poolManager, BracketSwapHook _hook, BracketReceipt _receipt, address _usdc) {
        poolManager = _poolManager;
        hook = _hook;
        receipt = _receipt;
        usdc = _usdc;
        admin = msg.sender;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Match Registration (admin)
    // ──────────────────────────────────────────────────────────────────────

    function registerMatch(
        bytes32 matchId,
        PoolKey calldata poolA,
        PoolKey calldata poolB,
        address teamA,
        address teamB,
        uint256 kickoffTime,
        uint8 round
    ) external onlyAdmin {
        hook.registerMatch(matchId, poolA, poolB, teamA, teamB, kickoffTime, round);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Add Liquidity
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Add liquidity to a match pool. User must approve both pool tokens to this router.
    function addLiquidity(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta
    ) external {
        bytes memory data = abi.encode(
            Action.ADD_LIQUIDITY,
            key,
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: 0}),
            msg.sender
        );
        poolManager.unlock(data);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Remove Liquidity (early exit, match still OPEN)
    // ──────────────────────────────────────────────────────────────────────

    function removeLiquidity(uint256 positionId) external {
        BracketSwapHook.Position memory pos = hook.getPosition(positionId);
        if (pos.owner != msg.sender) revert NotOwner();

        BracketSwapHook.MatchPool memory m = hook.getMatch(pos.matchId);
        PoolKey memory key = _getPoolKeyForTeam(m, pos.teamSide);

        bytes memory data = abi.encode(
            Action.REMOVE_LIQUIDITY,
            key,
            ModifyLiquidityParams({
                tickLower: pos.tickLower,
                tickUpper: pos.tickUpper,
                liquidityDelta: -int256(uint256(pos.liquidityShares)),
                salt: 0
            }),
            positionId,
            msg.sender
        );
        poolManager.unlock(data);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Claim Winnings (settled match → USDC out, no NFT)
    // ──────────────────────────────────────────────────────────────────────

    function claimWinnings(uint256 positionId) external {
        BracketSwapHook.Position memory pos = hook.getPosition(positionId);
        if (pos.owner != msg.sender) revert NotOwner();

        BracketSwapHook.MatchPool memory m = hook.getMatch(pos.matchId);
        if (m.state != BracketSwapHook.MatchState.SETTLED) revert MatchNotSettled();
        if (pos.teamSide != m.winner) revert NotWinningSide();

        // Parimutuel payout: winner gets their share of the ENTIRE pot (winner + loser USDC).
        // Router received loser USDC via drainLosingPool. We remove LP (gets back base deposit),
        // then top up with bonus from router's reserve to reach the full parimutuel payout.
        uint256 payout = (uint256(pos.liquidityShares) * hook.payoutMultiplier(pos.matchId)) / 1e18;

        PoolKey memory key = _getPoolKeyForTeam(m, pos.teamSide);

        // Remove LP → USDC credited to router (not directly to user)
        bytes memory data = abi.encode(
            Action.REMOVE_LIQUIDITY,
            key,
            ModifyLiquidityParams({
                tickLower: pos.tickLower,
                tickUpper: pos.tickUpper,
                liquidityDelta: -int256(uint256(pos.liquidityShares)),
                salt: 0
            }),
            positionId,
            address(this) // USDC comes to router first
        );
        poolManager.unlock(data);

        // Cap at router's actual balance to absorb any AMM dust rounding
        uint256 available = IERC20(usdc).balanceOf(address(this));
        if (payout > available) payout = available;
        IERC20(usdc).safeTransfer(msg.sender, payout);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Claim Receipt (settled match → NFT + escrowed USDC, for next round LP)
    // ──────────────────────────────────────────────────────────────────────

    function claimReceipt(uint256 positionId) external returns (uint256 receiptId) {
        BracketSwapHook.Position memory pos = hook.getPosition(positionId);
        if (pos.owner != msg.sender) revert NotOwner();

        BracketSwapHook.MatchPool memory m = hook.getMatch(pos.matchId);
        if (m.state != BracketSwapHook.MatchState.SETTLED) revert MatchNotSettled();
        if (pos.teamSide != m.winner) revert NotWinningSide();

        uint256 payoutMultiplier = hook.payoutMultiplier(pos.matchId);
        uint256 usdcEntitlement = (uint256(pos.liquidityShares) * payoutMultiplier) / 1e18;

        PoolKey memory key = _getPoolKeyForTeam(m, pos.teamSide);

        // Remove from pool — router receives USDC
        bytes memory data = abi.encode(
            Action.REMOVE_LIQUIDITY,
            key,
            ModifyLiquidityParams({
                tickLower: pos.tickLower,
                tickUpper: pos.tickUpper,
                liquidityDelta: -int256(uint256(pos.liquidityShares)),
                salt: 0
            }),
            positionId,
            address(this) // USDC stays in router (escrowed)
        );
        poolManager.unlock(data);

        // Mint receipt NFT; USDC stays in this contract as escrow
        receiptId = receipt.mint(msg.sender, pos.matchId, m.winner, usdcEntitlement, m.round);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Redeem Receipt → add LP in next round pool (atomic rollover via NFT)
    // ──────────────────────────────────────────────────────────────────────

    function redeemReceipt(
        uint256 receiptId,
        PoolKey calldata nextKey,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta
    ) external {
        if (receipt.ownerOf(receiptId) != msg.sender) revert NotReceiptOwner();
        BracketReceipt.ReceiptData memory rd = receipt.getReceipt(receiptId);
        if (rd.redeemed) revert ReceiptAlreadyRedeemed();

        // Approve PoolManager to take USDC from router's escrow
        IERC20(usdc).approve(address(poolManager), rd.usdcEntitlement);

        bytes memory data = abi.encode(
            Action.ADD_LIQUIDITY,
            nextKey,
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: 0}),
            msg.sender
        );
        poolManager.unlock(data);

        receipt.markRedeemed(receiptId);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Rollover (atomic flash accounting — no NFT path)
    // ──────────────────────────────────────────────────────────────────────

    function rollover(
        uint256 positionId,
        PoolKey calldata nextKey,
        int24 nextTickLower,
        int24 nextTickUpper,
        int256 nextLiquidityDelta
    ) external {
        BracketSwapHook.Position memory pos = hook.getPosition(positionId);
        if (pos.owner != msg.sender) revert NotOwner();

        BracketSwapHook.MatchPool memory m = hook.getMatch(pos.matchId);
        if (m.state != BracketSwapHook.MatchState.SETTLED) revert MatchNotSettled();
        if (pos.teamSide != m.winner) revert NotWinningSide();

        PoolKey memory oldKey = _getPoolKeyForTeam(m, pos.teamSide);

        bytes memory data = abi.encode(
            Action.ROLLOVER,
            oldKey,
            ModifyLiquidityParams({
                tickLower: pos.tickLower,
                tickUpper: pos.tickUpper,
                liquidityDelta: -int256(uint256(pos.liquidityShares)),
                salt: 0
            }),
            positionId,
            nextKey,
            ModifyLiquidityParams({
                tickLower: nextTickLower,
                tickUpper: nextTickUpper,
                liquidityDelta: nextLiquidityDelta,
                salt: 0
            }),
            msg.sender
        );
        poolManager.unlock(data);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Drain Losing Pool (admin calls after oracle settles)
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Remove all losing-side LP positions after settleMatch has been called.
    function drainLosingPosition(bytes32 matchId, uint256 positionId) external onlyAdmin {
        BracketSwapHook.Position memory pos = hook.getPosition(positionId);
        BracketSwapHook.MatchPool memory m = hook.getMatch(matchId);
        PoolKey memory key = _getPoolKeyForTeam(m, pos.teamSide);

        bytes memory data = abi.encode(
            Action.DRAIN_LOSING_POOL,
            key,
            ModifyLiquidityParams({
                tickLower: pos.tickLower,
                tickUpper: pos.tickUpper,
                liquidityDelta: -int256(uint256(pos.liquidityShares)),
                salt: 0
            }),
            positionId,
            address(this) // USDC stays in router (adds to totalPot)
        );
        poolManager.unlock(data);
    }

    // ──────────────────────────────────────────────────────────────────────
    // IUnlockCallback
    // ──────────────────────────────────────────────────────────────────────

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "not pool manager");

        Action action = abi.decode(data[:32], (Action));

        if (action == Action.ADD_LIQUIDITY) {
            (,PoolKey memory key, ModifyLiquidityParams memory params, address user) =
                abi.decode(data, (Action, PoolKey, ModifyLiquidityParams, address));
            _handleAddLiquidity(key, params, user);
        } else if (action == Action.REMOVE_LIQUIDITY) {
            (,PoolKey memory key, ModifyLiquidityParams memory params, uint256 positionId, address recipient) =
                abi.decode(data, (Action, PoolKey, ModifyLiquidityParams, uint256, address));
            _handleRemoveLiquidity(key, params, positionId, recipient);
        } else if (action == Action.ROLLOVER) {
            (
                ,
                PoolKey memory oldKey,
                ModifyLiquidityParams memory oldParams,
                uint256 positionId,
                PoolKey memory newKey,
                ModifyLiquidityParams memory newParams,
                address user
            ) = abi.decode(data, (Action, PoolKey, ModifyLiquidityParams, uint256, PoolKey, ModifyLiquidityParams, address));
            _handleRollover(oldKey, oldParams, positionId, newKey, newParams, user);
        } else if (action == Action.DRAIN_LOSING_POOL) {
            (,PoolKey memory key, ModifyLiquidityParams memory params, uint256 positionId, address recipient) =
                abi.decode(data, (Action, PoolKey, ModifyLiquidityParams, uint256, address));
            _handleRemoveLiquidity(key, params, positionId, recipient);
        }

        return "";
    }

    // ──────────────────────────────────────────────────────────────────────
    // Internal callback handlers
    // ──────────────────────────────────────────────────────────────────────

    function _handleAddLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, address user) internal {
        (BalanceDelta delta,) = poolManager.modifyLiquidity(key, params, abi.encode(user));
        // Pull exact amounts from user into PoolManager using sync→transfer→settle pattern
        _settleFromUser(key, delta, user);
    }

    function _handleRemoveLiquidity(
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        uint256 positionId,
        address recipient
    ) internal {
        // hookData = positionId (hook bookkeeper deletes the position record)
        (BalanceDelta delta,) =
            poolManager.modifyLiquidity(key, params, abi.encode(positionId));

        // Take: if PoolManager owes us tokens (delta is positive), take USDC out
        _takeDeltas(key, delta, recipient);
    }

    function _handleRollover(
        PoolKey memory oldKey,
        ModifyLiquidityParams memory oldParams,
        uint256 positionId,
        PoolKey memory newKey,
        ModifyLiquidityParams memory newParams,
        address user
    ) internal {
        // Step 1: remove from old pool
        (BalanceDelta removeDelta,) =
            poolManager.modifyLiquidity(oldKey, oldParams, abi.encode(positionId));

        // Step 2: add to new pool (USDC credited from old remove pays for new add — flash accounting)
        (BalanceDelta addDelta,) =
            poolManager.modifyLiquidity(newKey, newParams, abi.encode(user));

        // Step 3: net settle — if payout > cost, send surplus USDC to user
        // BalanceDelta: amount1 = USDC (token1 in all pools, USDC > outcome token address)
        int128 netUsdc = removeDelta.amount1() + addDelta.amount1();
        if (netUsdc > 0) {
            // PoolManager owes us USDC (surplus payout)
            Currency usdc_ = oldKey.currency1;
            poolManager.take(usdc_, user, uint128(netUsdc));
        } else if (netUsdc < 0) {
            // We owe PoolManager USDC (user topped up more than payout — unusual but handle it)
            Currency usdc_ = oldKey.currency1;
            IERC20(Currency.unwrap(usdc_)).safeTransferFrom(user, address(poolManager), uint128(-netUsdc));
            poolManager.settle();
        }
        // If netUsdc == 0, perfectly balanced — nothing to settle
    }

    /// @dev Settle tokens already held by this router (e.g. escrowed USDC for redeemReceipt).
    function _settleDeltas(PoolKey memory key, BalanceDelta delta) internal {
        int128 amt0 = delta.amount0();
        int128 amt1 = delta.amount1();
        if (amt0 < 0) {
            poolManager.sync(key.currency0);
            IERC20(Currency.unwrap(key.currency0)).safeTransfer(address(poolManager), uint128(-amt0));
            poolManager.settle();
        }
        if (amt1 < 0) {
            poolManager.sync(key.currency1);
            IERC20(Currency.unwrap(key.currency1)).safeTransfer(address(poolManager), uint128(-amt1));
            poolManager.settle();
        }
    }

    /// @dev Settle by pulling exact amounts from `user` directly into PoolManager.
    function _settleFromUser(PoolKey memory key, BalanceDelta delta, address user) internal {
        int128 amt0 = delta.amount0();
        int128 amt1 = delta.amount1();
        if (amt0 < 0) {
            uint128 a = uint128(-amt0);
            poolManager.sync(key.currency0);
            IERC20(Currency.unwrap(key.currency0)).safeTransferFrom(user, address(poolManager), a);
            poolManager.settle();
        }
        if (amt1 < 0) {
            uint128 a = uint128(-amt1);
            poolManager.sync(key.currency1);
            IERC20(Currency.unwrap(key.currency1)).safeTransferFrom(user, address(poolManager), a);
            poolManager.settle();
        }
    }

    function _takeDeltas(PoolKey memory key, BalanceDelta delta, address recipient) internal {
        int128 amt0 = delta.amount0();
        int128 amt1 = delta.amount1();
        if (amt0 > 0) poolManager.take(key.currency0, recipient, uint128(amt0));
        if (amt1 > 0) poolManager.take(key.currency1, recipient, uint128(amt1));
    }

    // ──────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ──────────────────────────────────────────────────────────────────────

    function _getPoolKeyForTeam(BracketSwapHook.MatchPool memory m, address teamSide)
        internal
        pure
        returns (PoolKey memory)
    {
        return teamSide == m.teamA ? m.poolA : m.poolB;
    }
}
