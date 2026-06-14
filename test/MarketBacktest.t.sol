// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {EconLib, IFeePolicy, StaticFeePolicy} from "../src/EconHarness.sol";
import {VolatilityFeeHook} from "../src/VolatilityFeeHook.sol";
import {HookFeePolicyAdapter} from "../src/HookFeePolicyAdapter.sol";
import {RealPrices} from "./RealPrices.sol";

/// @notice M2 -- the backtest runs over a REAL historical ETH/USD daily series (fetched from a live
///         exchange API by scripts/fetch_prices.py, not hand-entered). Same engine, same real hook
///         (via quoteFee); only the price path is now the actual market.
contract MarketBacktestTest is Test {
    function test_realMarket_backtest() public {
        uint256[] memory path = RealPrices.closesWad();
        require(path.length >= 2, "need a real price series; run scripts/fetch_prices.py first");

        uint256 x0 = 100e18;
        uint256 y0 = x0 * path[0] / 1e18;

        VolatilityFeeHook hook = new VolatilityFeeHook();
        IFeePolicy stat = new StaticFeePolicy(0.003e18);
        IFeePolicy real = new HookFeePolicyAdapter(address(hook));

        EconLib.Scorecard memory s = EconLib.run(x0, y0, path, stat);
        EconLib.Scorecard memory r = EconLib.run(x0, y0, path, real);

        console2.log("days in series   :", path.length);
        console2.log("start price (wad):", path[0]);
        console2.log("end   price (wad):", path[path.length - 1]);
        console2.log("-- static 0.30%");
        console2.log("   netPnL:");
        console2.logInt(s.netPnL);
        console2.log("   lvrExtracted:", s.lvrExtracted);
        console2.log("   feeIncome   :", s.feeIncome);
        console2.log("-- real volatility hook");
        console2.log("   netPnL:");
        console2.logInt(r.netPnL);
        console2.log("   lvrExtracted:", r.lvrExtracted);
        console2.log("   feeIncome   :", r.feeIncome);

        if (s.netPnL < 0) {
            int256 saved = r.netPnL - s.netPnL;
            if (saved > 0) {
                uint256 savedBps = uint256(saved) * 10_000 / uint256(-s.netPnL);
                console2.log("   LP-loss reduction vs static (bps):", savedBps);
            }
        }

        assertGt(r.netPnL, s.netPnL, "the real hook must protect LPs better than static over the real market");
    }
}
