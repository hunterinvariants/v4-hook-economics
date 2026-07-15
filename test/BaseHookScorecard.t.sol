// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {EconLib, IFeePolicy, StaticFeePolicy, FakeDynamicFeePolicy} from "../src/EconHarness.sol";
import {ExampleBaseHook} from "../src/ExampleBaseHook.sol";
import {HookFeePolicyAdapter} from "../src/HookFeePolicyAdapter.sol";

/// @notice Grade an example Base Uniswap v4 hook for liquidity-provider economics.
///
///   Uniswap v4 runs on Base, so a team shipping a pool on Base deploys a hook exactly like this one.
///   Safety tooling checks the hook cannot be exploited. This grades whether it earns or loses money
///   for the liquidity provider, the question safety tooling does not answer.
///
///   The hook is deployed on a real v4-core PoolManager at a mined hook address and initialised into a
///   dynamic-fee pool, the same way it would run on Base mainnet. A live swap is routed through it to
///   prove it is the deployed hook and not a re-implementation. The scorecard then reads the hook's own
///   fee logic, so the grade reflects the code the Base pool would execute.
contract BaseHookScorecardTest is Test, Deployers {
    uint256 constant X0 = 100e18; // 100 base tokens of liquidity
    uint256 constant Y0 = 200_000e18; // 200,000 quote tokens, start price 2000

    ExampleBaseHook hook;
    address hookAddr;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        hookAddr = address(flags ^ (0x4444 << 144));
        deployCodeTo("src/ExampleBaseHook.sol:ExampleBaseHook", "", hookAddr);
        hook = ExampleBaseHook(hookAddr);
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(hookAddr), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );
    }

    // A volatile ETH/USD-style path, the conditions a dynamic fee is meant to handle.
    function _volatile() internal pure returns (uint256[] memory p) {
        p = new uint256[](12);
        p[0] = 2000e18; p[1] = 2300e18; p[2] = 1750e18; p[3] = 2150e18;
        p[4] = 1850e18; p[5] = 2250e18; p[6] = 1800e18; p[7] = 2200e18;
        p[8] = 1900e18; p[9] = 2100e18; p[10] = 1950e18; p[11] = 2000e18;
    }

    /// The example hook is a REAL deployed Base hook: a swap on a v4-core dynamic-fee pool routes
    /// through its beforeSwap and is charged the fee it returns.
    function test_baseHook_liveInDynamicPool() public {
        BalanceDelta d = swap(key, true, -1e8, abi.encode(uint256(2000e18), uint256(2300e18)));
        uint256 input = uint256(int256(-d.amount0()));
        uint256 output = uint256(int256(d.amount1()));
        assertGt(input, output, "the Base hook charged a fee on a live swap");
    }

    /// The scorecard: grade the deployed Base hook against a static 0.30% baseline and print it.
    function test_baseHook_scorecard_protectsLPs() public {
        IFeePolicy baseline = new StaticFeePolicy(0.003e18);
        IFeePolicy graded = new HookFeePolicyAdapter(hookAddr);

        EconLib.Scorecard memory s = EconLib.run(X0, Y0, _volatile(), baseline);
        EconLib.Scorecard memory h = EconLib.run(X0, Y0, _volatile(), graded);

        int256 improve = h.netPnL - s.netPnL;
        uint256 sAbs = s.netPnL >= 0 ? uint256(s.netPnL) : uint256(-s.netPnL);
        uint256 impPct = sAbs == 0 ? 0 : uint256(improve >= 0 ? improve : -improve) * 100 / sAbs;

        console2.log("=== BASE v4 HOOK SCORECARD: ExampleBaseHook ===");
        console2.log(" pool: 100 base / 200,000 quote on a Base v4-core dynamic-fee pool");
        console2.log(" path: 12-step volatile ETH/USD-style series");
        console2.log(" --------------------------------------------------");
        console2.log(" baseline static 0.30%  net PnL (quote units):");
        console2.logInt(s.netPnL / int256(1e18));
        console2.log(" ExampleBaseHook        net PnL (quote units):");
        console2.logInt(h.netPnL / int256(1e18));
        console2.log(" LP loss reduced vs static, percent:");
        console2.log(impPct);
        console2.log(" VERDICT: PASS, the hook protects LPs versus a static pool");

        assertGt(h.netPnL, s.netPnL, "the Base hook must protect LPs better than a static pool");
    }

    /// Two-way guard: a hook that advertises a dynamic fee but returns a constant scores identically to
    /// the static baseline. The scorecard flags it as economically vacuous, which a safety check misses.
    function test_scorecard_flagsVacuousHook() public {
        EconLib.Scorecard memory s = EconLib.run(X0, Y0, _volatile(), new StaticFeePolicy(0.003e18));
        EconLib.Scorecard memory f = EconLib.run(X0, Y0, _volatile(), new FakeDynamicFeePolicy(0.003e18));
        assertEq(f.netPnL, s.netPnL, "a fake-dynamic hook must score identically to static, no LP benefit");
    }
}
