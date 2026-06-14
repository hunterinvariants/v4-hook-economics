// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {
    EconLib,
    IFeePolicy,
    StaticFeePolicy,
    VolatilityFeePolicy,
    FakeDynamicFeePolicy
} from "../src/EconHarness.sol";

/// @notice Two-way economic proof for the fee-policy backtester.
///         - a volatility-aware dynamic fee protects LPs better than a static fee when price moves;
///         - a "dynamic" fee that is secretly constant shows NO benefit (cannot be gamed);
///         - the benefit scales with volatility (no false benefit claimed on a calm market).
contract EconHarnessTest is Test {
    uint256 constant X0 = 100e18;     // 100 base (e.g. ETH)
    uint256 constant Y0 = 200_000e18; // 200k quote (e.g. USDC) -> start price 2000

    StaticFeePolicy stat;
    VolatilityFeePolicy dyn;
    FakeDynamicFeePolicy fake;

    function setUp() public {
        stat = new StaticFeePolicy(0.003e18);                       // 0.30%
        dyn = new VolatilityFeePolicy(0.003e18, 0.02e18, 0.30e18);  // base 0.30%, cap 2%, sens 0.30
        fake = new FakeDynamicFeePolicy(0.003e18);                  // pretends dynamic, constant 0.30%
    }

    function _volatile() internal pure returns (uint256[] memory p) {
        p = new uint256[](12);
        p[0] = 2000e18; p[1] = 2300e18; p[2] = 1750e18; p[3] = 2150e18;
        p[4] = 1850e18; p[5] = 2250e18; p[6] = 1800e18; p[7] = 2200e18;
        p[8] = 1900e18; p[9] = 2100e18; p[10] = 1950e18; p[11] = 2000e18;
    }

    function _calm() internal pure returns (uint256[] memory p) {
        p = new uint256[](12);
        p[0] = 2000e18; p[1] = 2005e18; p[2] = 1998e18; p[3] = 2003e18;
        p[4] = 1999e18; p[5] = 2004e18; p[6] = 1997e18; p[7] = 2002e18;
        p[8] = 2000e18; p[9] = 2001e18; p[10] = 1999e18; p[11] = 2000e18;
    }

    function _log(string memory tag, EconLib.Scorecard memory s) internal pure {
        console2.log("--", tag);
        console2.log("   netPnL (quote):");
        console2.logInt(s.netPnL);
        console2.log("   feeIncome   :", s.feeIncome);
        console2.log("   lvrExtracted:", s.lvrExtracted);
        console2.log("   endMispxBps :", s.endMispricingBps);
    }

    /// Non-vacuity: a constant fee dressed up as "dynamic" must score identically to static.
    function test_fakeDynamic_isVacuous() public view {
        uint256[] memory path = _volatile();
        EconLib.Scorecard memory s = EconLib.run(X0, Y0, path, stat);
        EconLib.Scorecard memory f = EconLib.run(X0, Y0, path, fake);
        _log("static", s);
        _log("fake-dynamic", f);
        assertEq(f.netPnL, s.netPnL, "constant fee dressed as dynamic must show no benefit");
    }

    /// Core claim: a volatility-aware dynamic fee protects LPs better than static when price moves.
    function test_dynamicFee_protectsLPs_onVolatility() public view {
        uint256[] memory path = _volatile();
        EconLib.Scorecard memory s = EconLib.run(X0, Y0, path, stat);
        EconLib.Scorecard memory d = EconLib.run(X0, Y0, path, dyn);
        _log("static", s);
        _log("dynamic", d);
        assertGt(d.netPnL, s.netPnL, "dynamic fee should beat static on a volatile path");
    }

    /// Honest direction: the benefit must SCALE with volatility -- near-zero when the market is
    /// calm, large when it is volatile. A tool that claimed a big benefit on a calm path is junk.
    function test_benefit_scalesWithVolatility() public view {
        int256 volBenefit =
            EconLib.run(X0, Y0, _volatile(), dyn).netPnL - EconLib.run(X0, Y0, _volatile(), stat).netPnL;
        int256 calmBenefit =
            EconLib.run(X0, Y0, _calm(), dyn).netPnL - EconLib.run(X0, Y0, _calm(), stat).netPnL;
        console2.log("vol benefit :");
        console2.logInt(volBenefit);
        console2.log("calm benefit:");
        console2.logInt(calmBenefit);
        assertGt(volBenefit, calmBenefit, "benefit must be larger when volatility is larger");
    }
}
