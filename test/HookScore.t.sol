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

import {EconLib, IFeePolicy, StaticFeePolicy} from "../src/EconHarness.sol";
import {VolatilityFeeHook} from "../src/VolatilityFeeHook.sol";
import {HookFeePolicyAdapter} from "../src/HookFeePolicyAdapter.sol";

/// @notice M1 -- the economic scorecard grades a REAL, deployed v4 dynamic-fee hook.
contract HookScoreTest is Test, Deployers {
    uint256 constant X0 = 100e18;
    uint256 constant Y0 = 200_000e18;
    int256 constant V0_DYNAMIC_NETPNL = -10488808350182359438912; // the v0 model's dynamic result

    VolatilityFeeHook hook;
    address hookAddr;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        hookAddr = address(flags ^ (0x4444 << 144));
        deployCodeTo("src/VolatilityFeeHook.sol:VolatilityFeeHook", "", hookAddr);
        hook = VolatilityFeeHook(hookAddr);
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(hookAddr), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );
    }

    function _volatile() internal pure returns (uint256[] memory p) {
        p = new uint256[](12);
        p[0] = 2000e18; p[1] = 2300e18; p[2] = 1750e18; p[3] = 2150e18;
        p[4] = 1850e18; p[5] = 2250e18; p[6] = 1800e18; p[7] = 2200e18;
        p[8] = 1900e18; p[9] = 2100e18; p[10] = 1950e18; p[11] = 2000e18;
    }

    /// The deployed hook's REAL beforeSwap returns a dynamic fee override equal to its quoteFee.
    function test_realHook_beforeSwap_returnsDynamicOverride() public view {
        uint256 poolPrice = 2000e18;
        uint256 extPrice = 2300e18;
        (,, uint24 returnedFee) =
            hook.beforeSwap(address(this), key, _swapParams(), abi.encode(poolPrice, extPrice));
        uint24 quoted = hook.quoteFee(poolPrice, extPrice);
        assertEq(returnedFee, quoted | LPFeeLibrary.OVERRIDE_FEE_FLAG, "beforeSwap must return quoteFee | override flag");
        assertTrue((returnedFee & LPFeeLibrary.OVERRIDE_FEE_FLAG) != 0, "override flag must be set");
    }

    /// The hook is live in a real dynamic-fee pool: a swap carrying price context routes through it.
    function test_realHook_liveInDynamicPool() public {
        BalanceDelta d = swap(key, true, -1e8, abi.encode(uint256(2000e18), uint256(2300e18)));
        uint256 input = uint256(int256(-d.amount0()));
        uint256 output = uint256(int256(d.amount1()));
        assertGt(input, output, "a fee was charged on the swap");
    }

    /// The economic engine, driven by the REAL hook, protects LPs and reproduces the v0 model.
    function test_realHook_economicScore_beatsStatic() public {
        IFeePolicy stat = new StaticFeePolicy(0.003e18);
        IFeePolicy real = new HookFeePolicyAdapter(hookAddr);
        EconLib.Scorecard memory s = EconLib.run(X0, Y0, _volatile(), stat);
        EconLib.Scorecard memory r = EconLib.run(X0, Y0, _volatile(), real);
        console2.log("static   netPnL:");
        console2.logInt(s.netPnL);
        console2.log("realhook netPnL:");
        console2.logInt(r.netPnL);
        assertGt(r.netPnL, s.netPnL, "the real hook must protect LPs better than static");
        assertApproxEqAbs(r.netPnL, V0_DYNAMIC_NETPNL, 200e18, "real hook reproduces the v0 model within fee quantization");
    }

    function _swapParams() internal pure returns (SwapParams memory) {
        return SwapParams({zeroForOne: true, amountSpecified: -1e8, sqrtPriceLimitX96: 0});
    }
}
