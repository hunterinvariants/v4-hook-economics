// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IFeePolicy, StaticFeePolicy, VolatilityFeePolicy} from "../src/EconHarness.sol";
import {FlowEngine} from "../src/FlowEngine.sol";

contract FlowReplayTest is Test {
    uint256 constant X0 = 100e18;
    uint256 constant Y0 = 200_000e18;
    uint256 constant BASE = 0.003e18;
    uint256 constant CHOKE = 0.05e18;
    uint256 constant RETAIL = 150_000e18;

    StaticFeePolicy stat;
    VolatilityFeePolicy moderate;
    VolatilityFeePolicy aggressive;

    function setUp() public {
        stat = new StaticFeePolicy(BASE);
        moderate = new VolatilityFeePolicy(BASE, 0.02e18, 0.30e18);
        aggressive = new VolatilityFeePolicy(BASE, 0.08e18, 0.60e18);
    }

    function _volatile() internal pure returns (uint256[] memory p) {
        p = new uint256[](12);
        p[0] = 2000e18; p[1] = 2300e18; p[2] = 1750e18; p[3] = 2150e18;
        p[4] = 1850e18; p[5] = 2250e18; p[6] = 1800e18; p[7] = 2200e18;
        p[8] = 1900e18; p[9] = 2100e18; p[10] = 1950e18; p[11] = 2000e18;
    }

    function _run(IFeePolicy pol) internal view returns (FlowEngine.FlowScorecard memory) {
        return FlowEngine.runWithRetail(X0, Y0, _volatile(), pol, RETAIL, BASE, CHOKE);
    }

    function _log(string memory tag, FlowEngine.FlowScorecard memory s) internal pure {
        console2.log(tag);
        console2.log("   LP net PnL (quote):");
        console2.logInt(s.netPnL / int256(1e18));
        console2.log("   retail fees (quote):", s.retailFee / 1e18);
        console2.log("   arb loss / LVR (quote):", s.lvr / 1e18);
    }

    function test_flow_aggressiveFeeKillsRetail() public view {
        FlowEngine.FlowScorecard memory s = _run(stat);
        FlowEngine.FlowScorecard memory m = _run(moderate);
        FlowEngine.FlowScorecard memory a = _run(aggressive);
        _log("static 0.30%", s);
        _log("moderate (cap 2%)", m);
        _log("aggressive (cap 8%)", a);

        assertLt(a.retailFee, m.retailFee, "aggressive fee should collapse retail fee income");
        assertGt(m.netPnL, a.netPnL, "moderate fee should beat the over-aggressive one once retail counts");
    }
}
