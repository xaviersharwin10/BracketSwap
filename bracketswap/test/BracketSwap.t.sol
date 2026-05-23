// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {BracketSwapHook} from "../src/BracketSwapHook.sol";
import {BracketRouter} from "../src/BracketRouter.sol";
import {BracketReceipt} from "../src/BracketReceipt.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {OutcomeToken} from "../src/OutcomeToken.sol";
import {MockOracle} from "../src/MockOracle.sol";
import {HookMiner} from "../src/HookMiner.sol";

contract BracketSwapTest is Test {
    using PoolIdLibrary for PoolKey;

    uint160 constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG
            | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.AFTER_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            | Hooks.BEFORE_SWAP_FLAG
    );

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    int24 constant TICK_LOWER = -600;
    int24 constant TICK_UPPER = 600;
    int256 constant LIQUIDITY_DELTA = 1_000_000;

    bytes32 constant MATCH_ID = keccak256("BRA_GER_GROUP_A");

    PoolManager poolManager;
    BracketSwapHook hook;
    BracketRouter router;
    BracketReceipt receiptNft;
    MockOracle oracle;
    MockERC20 usdc;
    OutcomeToken braToken;
    OutcomeToken gerToken;

    PoolKey poolA; // BRA_WIN / USDC
    PoolKey poolB; // GER_WIN / USDC

    address alice = makeAddr("alice"); // bets on Brazil
    address bob = makeAddr("bob");     // bets on Germany
    address admin = address(this);

    function setUp() public {
        poolManager = new PoolManager(admin);

        // Mine salt for hook address
        bytes memory creationCode = type(BracketSwapHook).creationCode;
        bytes memory ctorArgs = abi.encode(address(poolManager), admin);
        (bytes32 salt, address expectedHook) =
            HookMiner.find(HOOK_FLAGS, Hooks.ALL_HOOK_MASK, creationCode, ctorArgs);

        bytes memory initcode = abi.encodePacked(creationCode, ctorArgs);
        (bool ok,) = HookMiner.CREATE2_FACTORY.call(abi.encodePacked(salt, initcode));
        require(ok, "hook deploy failed");
        hook = BracketSwapHook(expectedHook);

        usdc = new MockERC20("USD Coin", "USDC", 6);
        braToken = new OutcomeToken("Brazil Win", "BRA_WIN", admin);
        gerToken = new OutcomeToken("Germany Win", "GER_WIN", admin);
        receiptNft = new BracketReceipt();
        router = new BracketRouter(IPoolManager(address(poolManager)), hook, receiptNft, address(usdc));
        oracle = new MockOracle(address(hook));

        hook.setRouter(address(router));
        hook.setOracle(address(oracle));
        receiptNft.setRouter(address(router));

        (address c0A, address c1A) = _sort(address(braToken), address(usdc));
        (address c0B, address c1B) = _sort(address(gerToken), address(usdc));

        poolA = PoolKey({
            currency0: Currency.wrap(c0A),
            currency1: Currency.wrap(c1A),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: hook
        });
        poolB = PoolKey({
            currency0: Currency.wrap(c0B),
            currency1: Currency.wrap(c1B),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: hook
        });

        uint256 kickoff = block.timestamp + 3 days;
        router.registerMatch(MATCH_ID, poolA, poolB, address(braToken), address(gerToken), kickoff, 1);
        poolManager.initialize(poolA, SQRT_PRICE_1_1);
        poolManager.initialize(poolB, SQRT_PRICE_1_1);

        // Fund users with both outcome tokens and USDC
        usdc.mint(alice, 10_000e6);
        usdc.mint(bob, 10_000e6);
        braToken.mint(alice, 5_000e18);
        gerToken.mint(bob, 5_000e18);

        vm.startPrank(alice);
        usdc.approve(address(router), type(uint256).max);
        braToken.approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(router), type(uint256).max);
        gerToken.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    // ── Tests ─────────────────────────────────────────────────────────────

    function test_addLiquidity_recordsPosition() public {
        uint256 posId = hook.nextPositionId();

        vm.prank(alice);
        router.addLiquidity(poolA, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA);

        BracketSwapHook.Position memory pos = hook.getPosition(posId);
        assertEq(pos.owner, alice);
        assertEq(pos.matchId, MATCH_ID);
        assertEq(pos.teamSide, address(braToken));
        assertGt(pos.liquidityShares, 0);
    }

    function test_removeLiquidity_earlyExit() public {
        uint256 posId = hook.nextPositionId();

        vm.prank(alice);
        router.addLiquidity(poolA, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA);

        uint256 usdcBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        router.removeLiquidity(posId);

        BracketSwapHook.Position memory pos = hook.getPosition(posId);
        assertEq(pos.owner, address(0), "position should be deleted");
        assertGt(usdc.balanceOf(alice), usdcBefore, "should receive USDC back");
    }

    function test_fullLifecycle_claimWinnings() public {
        uint256 alicePosId = hook.nextPositionId();
        vm.prank(alice);
        router.addLiquidity(poolA, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA);
        uint256 aliceDeposit = usdc.balanceOf(address(poolManager)); // USDC now in pool A

        uint256 bobPosId = hook.nextPositionId();
        vm.prank(bob);
        router.addLiquidity(poolB, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA);

        // totalPot = exact USDC sitting in both pools (recoverable amount)
        uint256 totalPot = usdc.balanceOf(address(poolManager));
        console.log("totalPot (actual USDC in pools):", totalPot);

        BracketSwapHook.MatchPool memory m = hook.getMatch(MATCH_ID);
        vm.warp(m.kickoffTime + 1);

        oracle.setMatchLive(MATCH_ID);

        BracketSwapHook.Position memory alicePos = hook.getPosition(alicePosId);
        oracle.settleMatch(MATCH_ID, address(braToken), alicePos.liquidityShares, totalPot);
        router.drainLosingPosition(MATCH_ID, bobPosId);

        assertEq(uint8(hook.getMatch(MATCH_ID).state), uint8(BracketSwapHook.MatchState.SETTLED));

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        router.claimWinnings(alicePosId);

        uint256 payout = usdc.balanceOf(alice) - balBefore;
        console.log("Alice payout (USDC units):", payout);
        assertGt(payout, aliceDeposit, "winner earns more than her own deposit");
        assertApproxEqAbs(payout, totalPot, 5, "payout should equal totalPot within rounding");
    }

    function test_swapBlockedWhenLive() public {
        BracketSwapHook.MatchPool memory m = hook.getMatch(MATCH_ID);
        vm.warp(m.kickoffTime + 1);
        oracle.setMatchLive(MATCH_ID);

        // V4 wraps hook reverts in WrappedError — catch any revert
        usdc.mint(address(this), 1_000e6);
        braToken.mint(address(this), 1_000e18);
        usdc.approve(address(router), type(uint256).max);
        braToken.approve(address(router), type(uint256).max);
        vm.expectRevert();
        router.addLiquidity(poolA, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA);
    }

    function test_matchStateTransitions() public {
        BracketSwapHook.MatchPool memory m = hook.getMatch(MATCH_ID);

        // Cannot go live before kickoff
        vm.expectRevert(BracketSwapHook.TooEarlyForLive.selector);
        oracle.setMatchLive(MATCH_ID);

        // Goes live at kickoff
        vm.warp(m.kickoffTime + 1);
        oracle.setMatchLive(MATCH_ID);
        assertEq(uint8(hook.getMatch(MATCH_ID).state), uint8(BracketSwapHook.MatchState.LIVE));

        // Settles with winner set correctly
        oracle.settleMatch(MATCH_ID, address(braToken), 1_000, 2_000e6);
        assertEq(uint8(hook.getMatch(MATCH_ID).state), uint8(BracketSwapHook.MatchState.SETTLED));
        assertEq(hook.getMatch(MATCH_ID).winner, address(braToken));
        assertGt(hook.payoutMultiplier(MATCH_ID), 1e18, "multiplier > 1x means winners profit");
    }

    function test_loserCannotClaimWinnings() public {
        uint256 bobPosId = hook.nextPositionId();
        vm.prank(bob);
        router.addLiquidity(poolB, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA);

        uint256 alicePosId = hook.nextPositionId();
        vm.prank(alice);
        router.addLiquidity(poolA, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA);

        BracketSwapHook.MatchPool memory m = hook.getMatch(MATCH_ID);
        vm.warp(m.kickoffTime + 1);
        oracle.setMatchLive(MATCH_ID);

        BracketSwapHook.Position memory alicePos = hook.getPosition(alicePosId);
        oracle.settleMatch(MATCH_ID, address(braToken), alicePos.liquidityShares, 2_000e6);
        router.drainLosingPosition(MATCH_ID, bobPosId);

        vm.prank(bob);
        vm.expectRevert(BracketRouter.NotOwner.selector);
        router.claimWinnings(alicePosId);
    }

    function test_multipleWinners_proportionalPayout() public {
        address charlie = makeAddr("charlie");
        usdc.mint(charlie, 10_000e6);
        braToken.mint(charlie, 5_000e18);
        vm.startPrank(charlie);
        usdc.approve(address(router), type(uint256).max);
        braToken.approve(address(router), type(uint256).max);
        vm.stopPrank();

        uint256 alicePosId = hook.nextPositionId();
        vm.prank(alice);
        router.addLiquidity(poolA, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA);

        uint256 charliePosId = hook.nextPositionId();
        vm.prank(charlie);
        router.addLiquidity(poolA, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA);

        uint256 bobPosId = hook.nextPositionId();
        vm.prank(bob);
        router.addLiquidity(poolB, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA);

        uint256 totalPot = usdc.balanceOf(address(poolManager));

        BracketSwapHook.MatchPool memory m = hook.getMatch(MATCH_ID);
        vm.warp(m.kickoffTime + 1);
        oracle.setMatchLive(MATCH_ID);

        BracketSwapHook.Position memory alicePos = hook.getPosition(alicePosId);
        BracketSwapHook.Position memory charliePos = hook.getPosition(charliePosId);
        uint256 totalWinnerLiq = alicePos.liquidityShares + charliePos.liquidityShares;
        oracle.settleMatch(MATCH_ID, address(braToken), totalWinnerLiq, totalPot);
        router.drainLosingPosition(MATCH_ID, bobPosId);

        uint256 aliceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        router.claimWinnings(alicePosId);

        uint256 charlieBefore = usdc.balanceOf(charlie);
        vm.prank(charlie);
        router.claimWinnings(charliePosId);

        uint256 alicePayout = usdc.balanceOf(alice) - aliceBefore;
        uint256 charliePayout = usdc.balanceOf(charlie) - charlieBefore;

        assertApproxEqAbs(alicePayout, charliePayout, 5, "equal stakes => equal payouts");
        assertApproxEqAbs(alicePayout + charliePayout, totalPot, 10, "payouts should exhaust pot");
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    function _sort(address a, address b) internal pure returns (address, address) {
        return a < b ? (a, b) : (b, a);
    }
}
