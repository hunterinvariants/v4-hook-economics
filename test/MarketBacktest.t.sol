// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {EconLib, IFeePolicy, StaticFeePolicy} from "../src/EconHarness.sol";
import {VolatilityFeeHook} from "../src/VolatilityFeeHook.sol";
import {HookFeePolicyAdapter} from "../src/HookFeePolicyAdapter.sol";
import {RealPrices} from "./RealPrices.sol";
import {RealPricesBTC} from "./RealPricesBTC.sol";

/// @notice M2 -- the backtest runs over REAL historical daily series (fetched from a live exchange API
///         by scripts/fetch_prices.py, not hand-entered). Run against two pairs to show it generalizes.
contract MarketBacktestTest is Test {
    function _backtest(string memory tag, uint256[] memory path) internal {
        require(path.length >= 2, "need a real price series; run scripts/fetch_prices.py first");

        uint256 x0 = 100e18;
        uint256 y0 = x0 * path[0] / 1e18;

        VolatilityFeeHook hook = new VolatilityFeeHook();
        IFeePolicy stat = new StaticFeePolicy(0.003e18);
        IFeePolicy real = new HookFeePolicyAdapter(address(hook));

        EconLib.Scorecard memory s = EconLib.run(x0, y0, path, stat);
        EconLib.Scorecard memory r = EconLib.run(x0, y0, path, real);

        console2.log("==", tag);
        console2.log("   days        :", path.length);
        console2.log("   static  netPnL:");
        console2.logInt(s.netPnL);
        console2.log("   realhook netPnL:");
        console2.logInt(r.netPnL);

        if (s.netPnL < 0) {
            int256 saved = r.netPnL - s.netPnL;
            if (saved > 0) {
                uint256 savedBps = uint256(saved) * 10_000 / uint256(-s.netPnL);
                console2.log("   LP-loss reduction vs static (bps):", savedBps);
            }
        }

        assertGt(r.netPnL, s.netPnL, "the real hook must protect LPs better than static over the real market");
    }

    function test_realMarket_ETH() public {
        _backtest("ETH/USD", RealPrices.closesWad());
    }

    function test_realMarket_BTC() public {
        _backtest("BTC/USD", RealPricesBTC.closesWad());
    }
}
