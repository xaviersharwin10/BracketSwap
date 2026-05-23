// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

import {BracketRouter} from "../src/BracketRouter.sol";
import {BracketSwapHook} from "../src/BracketSwapHook.sol";
import {OutcomeToken} from "../src/OutcomeToken.sol";

/// @notice Registers Round of 16 and Quarter-final matches on top of the existing deployment.
/// Run after Deploy.s.sol. Reads PRIVATE_KEY from .env; all contract addresses hardcoded.
contract RegisterMatches is Script {
    // ── Existing deployment (from Deploy.s.sol output) ──────────────────────
    address constant POOL_MANAGER = 0xD739555d465d7dBaE4786CA8463D7a73e7926426;
    address constant HOOK         = 0x73ce41FB6F83E44FFce983494393C4D2BDda5f80;
    address constant ROUTER       = 0xC130Aa5A443eD6CA3D39bE1c4c26771D15926D5E;
    address constant USDC         = 0x90A5eEE155fdEFABb38e65E14d0827b1c4f0B7c7;

    // sqrtPriceX96 for 1:1 (tick = 0)
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    bytes32 constant R16_MATCH_ID = keccak256("BRA_ESP_R16");
    bytes32 constant QF_MATCH_ID  = keccak256("BRA_FRA_QF");

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        IPoolManager pm  = IPoolManager(POOL_MANAGER);
        BracketRouter router = BracketRouter(payable(ROUTER));

        vm.startBroadcast(pk);

        // ── Round of 16: Brazil vs Spain ─────────────────────────────────────
        OutcomeToken braR16 = new OutcomeToken("Brazil Win R16", "BRA_R16", deployer);
        OutcomeToken espWin = new OutcomeToken("Spain Win R16",  "ESP_WIN", deployer);

        (address c0r16A, address c1r16A) = _sort(address(braR16), USDC);
        (address c0r16B, address c1r16B) = _sort(address(espWin), USDC);

        PoolKey memory r16PoolA = PoolKey({
            currency0: Currency.wrap(c0r16A),
            currency1: Currency.wrap(c1r16A),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: BracketSwapHook(HOOK)
        });
        PoolKey memory r16PoolB = PoolKey({
            currency0: Currency.wrap(c0r16B),
            currency1: Currency.wrap(c1r16B),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: BracketSwapHook(HOOK)
        });

        uint256 r16Kickoff = block.timestamp + 5 days;
        router.registerMatch(R16_MATCH_ID, r16PoolA, r16PoolB, address(braR16), address(espWin), r16Kickoff, 2);
        pm.initialize(r16PoolA, SQRT_PRICE_1_1);
        pm.initialize(r16PoolB, SQRT_PRICE_1_1);

        // ── Quarter-final: Brazil vs France ──────────────────────────────────
        OutcomeToken braQF  = new OutcomeToken("Brazil Win QF",  "BRA_QF",  deployer);
        OutcomeToken fraWin = new OutcomeToken("France Win QF",  "FRA_WIN", deployer);

        (address c0qfA, address c1qfA) = _sort(address(braQF), USDC);
        (address c0qfB, address c1qfB) = _sort(address(fraWin), USDC);

        PoolKey memory qfPoolA = PoolKey({
            currency0: Currency.wrap(c0qfA),
            currency1: Currency.wrap(c1qfA),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: BracketSwapHook(HOOK)
        });
        PoolKey memory qfPoolB = PoolKey({
            currency0: Currency.wrap(c0qfB),
            currency1: Currency.wrap(c1qfB),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: BracketSwapHook(HOOK)
        });

        uint256 qfKickoff = block.timestamp + 12 days;
        router.registerMatch(QF_MATCH_ID, qfPoolA, qfPoolB, address(braQF), address(fraWin), qfKickoff, 3);
        pm.initialize(qfPoolA, SQRT_PRICE_1_1);
        pm.initialize(qfPoolB, SQRT_PRICE_1_1);

        // Mint test tokens to deployer
        braR16.mint(deployer, 10_000e18);
        espWin.mint(deployer, 10_000e18);
        braQF.mint(deployer,  10_000e18);
        fraWin.mint(deployer, 10_000e18);

        vm.stopBroadcast();

        // ── Summary ───────────────────────────────────────────────────────────
        console.log("\n=== BracketSwap - Additional Matches Registered ===");
        console.log("R16 Match ID:  ", uint256(R16_MATCH_ID));
        console.log("BRA_R16 token: ", address(braR16));
        console.log("ESP_WIN token: ", address(espWin));
        console.log("R16 kickoff:   ", r16Kickoff);
        console.log("");
        console.log("QF Match ID:   ", uint256(QF_MATCH_ID));
        console.log("BRA_QF token:  ", address(braQF));
        console.log("FRA_WIN token: ", address(fraWin));
        console.log("QF kickoff:    ", qfKickoff);
    }

    function _sort(address a, address b) internal pure returns (address t0, address t1) {
        (t0, t1) = a < b ? (a, b) : (b, a);
    }
}
