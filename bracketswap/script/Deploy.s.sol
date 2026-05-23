// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {BracketSwapHook} from "../src/BracketSwapHook.sol";
import {BracketRouter} from "../src/BracketRouter.sol";
import {BracketReceipt} from "../src/BracketReceipt.sol";
import {MockOracle} from "../src/MockOracle.sol";
import {OutcomeToken} from "../src/OutcomeToken.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {HookMiner} from "../src/HookMiner.sol";

contract Deploy is Script {
    // Hook flags we need: afterInitialize | beforeAddLiq | afterAddLiq | beforeRemoveLiq | afterRemoveLiq | beforeSwap
    uint160 constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG
            | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.AFTER_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            | Hooks.BEFORE_SWAP_FLAG
    );

    // sqrtPriceX96 for tick=0 (1:1 unit price)
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    // Demo match: Brazil vs Germany, Group Stage
    bytes32 constant MATCH_ID_BRA_GER = keccak256("BRA_GER_GROUP_A");

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        // ── 1. Deploy PoolManager (needed for hook initcode hash) ──────────
        vm.startBroadcast(deployerPk);
        PoolManager poolManager = new PoolManager(deployer);
        vm.stopBroadcast();
        console.log("PoolManager:   ", address(poolManager));

        // ── 2. Mine hook salt (off-chain, before broadcast) ─────────────────
        bytes memory hookCreationCode = type(BracketSwapHook).creationCode;
        bytes memory hookConstructorArgs = abi.encode(address(poolManager), deployer);
        (bytes32 hookSalt, address expectedHookAddr) =
            HookMiner.find(HOOK_FLAGS, Hooks.ALL_HOOK_MASK, hookCreationCode, hookConstructorArgs);
        console.log("Hook salt:     ", uint256(hookSalt));
        console.log("Expected hook: ", expectedHookAddr);

        // ── 3. Deploy remaining contracts ────────────────────────────────────
        vm.startBroadcast(deployerPk);

        // Mock USDC (6 decimals)
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        console.log("USDC:          ", address(usdc));

        // Outcome tokens — Brazil WIN and Germany WIN
        OutcomeToken braToken = new OutcomeToken("Brazil Win", "BRA_WIN", deployer);
        OutcomeToken gerToken = new OutcomeToken("Germany Win", "GER_WIN", deployer);
        console.log("BRA_WIN token: ", address(braToken));
        console.log("GER_WIN token: ", address(gerToken));

        // Deploy BracketSwapHook via CREATE2 factory
        bytes memory hookInitcode = abi.encodePacked(hookCreationCode, hookConstructorArgs);
        (bool ok,) = HookMiner.CREATE2_FACTORY.call(abi.encodePacked(hookSalt, hookInitcode));
        require(ok, "Hook CREATE2 deploy failed");
        BracketSwapHook hook = BracketSwapHook(expectedHookAddr);
        console.log("BracketSwapHook:", address(hook));

        // Deploy BracketReceipt and BracketRouter
        BracketReceipt receipt = new BracketReceipt();
        BracketRouter router = new BracketRouter(IPoolManager(address(poolManager)), hook, receipt, address(usdc));
        console.log("BracketReceipt:", address(receipt));
        console.log("BracketRouter: ", address(router));

        // Deploy MockOracle
        MockOracle oracle = new MockOracle(address(hook));
        console.log("MockOracle:    ", address(oracle));

        // ── 4. Wire up circular references ──────────────────────────────────
        hook.setRouter(address(router));
        hook.setOracle(address(oracle));
        receipt.setRouter(address(router));

        // ── 5. Set up demo match pools ───────────────────────────────────────
        // BRA_WIN/USDC pool and GER_WIN/USDC pool for Brazil vs Germany

        // Sort currencies: Uniswap requires currency0 < currency1 by address
        (address cur0A, address cur1A) = _sortTokens(address(braToken), address(usdc));
        (address cur0B, address cur1B) = _sortTokens(address(gerToken), address(usdc));

        PoolKey memory poolA = PoolKey({
            currency0: Currency.wrap(cur0A),
            currency1: Currency.wrap(cur1A),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: hook
        });

        PoolKey memory poolB = PoolKey({
            currency0: Currency.wrap(cur0B),
            currency1: Currency.wrap(cur1B),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: hook
        });

        // Register match (sets poolToMatchId before initialize fires afterInitialize)
        _registerDemoMatch(router, poolA, poolB, address(braToken), address(gerToken));

        // Initialize both pools (triggers afterInitialize which validates registration)
        poolManager.initialize(poolA, SQRT_PRICE_1_1);
        poolManager.initialize(poolB, SQRT_PRICE_1_1);

        // Mint test USDC and outcome tokens to deployer for demo
        usdc.mint(deployer, 100_000e6);
        braToken.mint(deployer, 10_000e18);
        gerToken.mint(deployer, 10_000e18);

        vm.stopBroadcast();

        // ── 6. Print summary ─────────────────────────────────────────────────
        console.log("\n=== BracketSwap Deployment Complete ===");
        console.log("Chain ID:      ", block.chainid);
        console.log("PoolManager:   ", address(poolManager));
        console.log("USDC:          ", address(usdc));
        console.log("BRA_WIN:       ", address(braToken));
        console.log("GER_WIN:       ", address(gerToken));
        console.log("Hook:          ", address(hook));
        console.log("Router:        ", address(router));
        console.log("Receipt:       ", address(receipt));
        console.log("Oracle:        ", address(oracle));
        console.log("Match ID (BRA vs GER):", uint256(MATCH_ID_BRA_GER));
    }

    function _registerDemoMatch(
        BracketRouter router,
        PoolKey memory poolA,
        PoolKey memory poolB,
        address braToken,
        address gerToken
    ) internal {
        uint256 kickoffTime = block.timestamp + 2 days;
        router.registerMatch(
            MATCH_ID_BRA_GER,
            poolA,
            poolB,
            braToken,
            gerToken,
            kickoffTime,
            1 // Group Stage
        );
        console.log("Kickoff:       ", kickoffTime);
    }

    function _sortTokens(address a, address b) internal pure returns (address token0, address token1) {
        (token0, token1) = a < b ? (a, b) : (b, a);
    }
}
