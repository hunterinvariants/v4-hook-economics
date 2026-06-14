// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {W, IFeePolicy} from "./EconHarness.sol";

/// @notice Prototype volume-replay engine. Where the price-only backtest routes only an arbitrageur,
///         this routes uninformed RETAIL flow alongside it. Retail pays fees but extracts no LVR, and
///         its volume shrinks as the fee rises (a linear "choke" model: full volume at baseFee, zero at
///         chokeFee). This surfaces a failure the price-only model cannot see: a fee tuned so
///         aggressively that it kills the profitable retail volume an LP depends on.
///
///         The retail flow is synthetic here. The funded milestone replaces it with real historical
///         pool volume from a Uniswap subgraph (which requires a Graph API key), and calibrates the
///         elasticity from data rather than the stylized linear choke used here.
library FlowEngine {
    uint256 internal constant WAD = 1e18;

    struct FlowScorecard {
        int256 netPnL; // arbFee + retailFee - lvr, in quote units
        uint256 arbFee; // fees paid by arbitrage flow
        uint256 retailFee; // fees paid by uninformed retail flow
        uint256 lvr; // value lost to arbitrage at external prices
    }

    /// @param retailBase retail quote volume per step at the base fee.
    /// @param baseFee    fee at/below which retail volume is full (WAD fraction).
    /// @param chokeFee   fee at/above which retail volume is zero (WAD fraction).
    function runWithRetail(
        uint256 x0,
        uint256 y0,
        uint256[] memory path,
        IFeePolicy policy,
        uint256 retailBase,
        uint256 baseFee,
        uint256 chokeFee
    ) internal view returns (FlowScorecard memory sc) {
        uint256 x = x0;
        uint256 y = y0;
        uint256 arbFeeAcc;
        uint256 retailFeeAcc;
        uint256 lvrAcc;

        for (uint256 i = 0; i < path.length; i++) {
            uint256 P = path[i];
            uint256 p = W.divWad(y, x);
            uint256 f = policy.fee(p, P);

            uint256 lower = W.mulWad(P, WAD - f);
            uint256 upper = W.mulWad(P, WAD + f);
            uint256 pt = p;
            if (p < lower) pt = lower;
            else if (p > upper) pt = upper;

            if (pt != p) {
                uint256 k = W.mulWad(x, y);
                uint256 xt = W.wadSqrt(W.divWad(k, pt));
                uint256 yt = W.divWad(k, xt);
                if (pt > p) {
                    uint256 dXout = x - xt;
                    uint256 dYin = yt - y;
                    arbFeeAcc += W.mulWad(dYin, f);
                    uint256 fair = W.mulWad(dXout, P);
                    if (fair > dYin) lvrAcc += fair - dYin;
                } else {
                    uint256 dXin = xt - x;
                    uint256 dYout = y - yt;
                    uint256 baseVal = W.mulWad(dXin, P);
                    arbFeeAcc += W.mulWad(baseVal, f);
                    if (dYout > baseVal) lvrAcc += dYout - baseVal;
                }
                x = xt;
                y = yt;
            }

            uint256 vol;
            if (f <= baseFee) {
                vol = retailBase;
            } else if (f >= chokeFee) {
                vol = 0;
            } else {
                vol = retailBase * (chokeFee - f) / (chokeFee - baseFee);
            }
            retailFeeAcc += W.mulWad(vol, f);
        }

        sc.arbFee = arbFeeAcc;
        sc.retailFee = retailFeeAcc;
        sc.lvr = lvrAcc;
        sc.netPnL = int256(arbFeeAcc + retailFeeAcc) - int256(lvrAcc);
    }
}
