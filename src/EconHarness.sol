// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Economic scorecard for Uniswap v4 fee-policy hooks
/// @notice Existing hook test tools answer "can the hook be exploited / does it break the
///         contract". This answers a different question that nothing else does: "does the hook
///         make or lose money for the LP". It backtests a hook's fee policy against a price path
///         and reports the LP economics: fee income, value extracted by arbitrage (LVR), and net
///         PnL.
///
///         v0 (this file) runs a deterministic synthetic price path with a stylized arbitrage
///         model: on each external price move, an arbitrageur trades the pool to the edge of the
///         fee band, and trades the opposite side at the external price -- the classic source of
///         loss-versus-rebalancing. The IFeePolicy seam is where a real v4 dynamic-fee hook plugs
///         in. M1: an adapter that reads a deployed hook's beforeSwap fee override. M2: replay of
///         real historical mainnet swap flow instead of a synthetic path.

library W {
    uint256 internal constant WAD = 1e18;

    function mulWad(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b / WAD;
    }

    function divWad(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * WAD / b;
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /// @dev sqrt of a WAD-scaled number, returned WAD-scaled.
    function wadSqrt(uint256 a) internal pure returns (uint256) {
        return sqrt(a * WAD);
    }
}

/// @notice A v4 dynamic-fee hook's decision, abstracted. Given the pool's current price and the
///         new external (true) price, return the fee as a WAD fraction (0.003e18 = 0.30%).
interface IFeePolicy {
    function fee(uint256 poolPrice, uint256 externalPrice) external view returns (uint256);
}

library EconLib {
    uint256 internal constant WAD = 1e18;

    struct Scorecard {
        int256 netPnL;            // feeIncome - lvrExtracted, in quote units. Higher = better for LPs.
        uint256 feeIncome;        // total LP fee income, in quote units
        uint256 lvrExtracted;     // value taken by arbitrage at external prices, in quote units
        uint256 endMispricingBps; // |poolPrice - externalPrice| / externalPrice at the end, in bps
    }

    /// @param x0 base-token reserve (WAD); y0 quote-token reserve (WAD). Pool price = y0/x0.
    /// @param path external price path (WAD), one entry per step. path[0] should equal the start price.
    /// @param policy the fee policy (hook) under test.
    function run(uint256 x0, uint256 y0, uint256[] memory path, IFeePolicy policy)
        internal
        view
        returns (Scorecard memory sc)
    {
        uint256 x = x0;
        uint256 y = y0;
        uint256 feeAcc; // quote units
        uint256 lvrAcc; // quote units

        for (uint256 i = 0; i < path.length; i++) {
            uint256 P = path[i];
            uint256 p = W.divWad(y, x);
            uint256 f = policy.fee(p, P);
            uint256 lower = W.mulWad(P, WAD - f);
            uint256 upper = W.mulWad(P, WAD + f);

            uint256 pt;
            if (p < lower) pt = lower;
            else if (p > upper) pt = upper;
            else continue; // pool price already inside the no-arbitrage band: no trade

            uint256 k = W.mulWad(x, y);
            uint256 xt = W.wadSqrt(W.divWad(k, pt));
            uint256 yt = W.divWad(k, xt);

            if (pt > p) {
                // price up: pool gives base (x - xt) to arb, receives quote (yt - y)
                uint256 dXout = x - xt;
                uint256 dYin = yt - y;
                feeAcc += W.mulWad(dYin, f);
                uint256 fair = W.mulWad(dXout, P);
                if (fair > dYin) lvrAcc += fair - dYin; // pool sold base below the true price
            } else {
                // price down: pool receives base (xt - x), gives quote (y - yt) to arb
                uint256 dXin = xt - x;
                uint256 dYout = y - yt;
                uint256 baseVal = W.mulWad(dXin, P);
                feeAcc += W.mulWad(baseVal, f);
                if (dYout > baseVal) lvrAcc += dYout - baseVal; // pool bought base above the true price
            }

            x = xt;
            y = yt;
        }

        uint256 Pf = path[path.length - 1];
        sc.feeIncome = feeAcc;
        sc.lvrExtracted = lvrAcc;
        sc.netPnL = int256(feeAcc) - int256(lvrAcc);
        uint256 pend = W.divWad(y, x);
        uint256 diff = pend > Pf ? pend - Pf : Pf - pend;
        sc.endMispricingBps = diff * 10000 / Pf;
    }
}

/// @notice Baseline: a vanilla static-fee pool (no hook).
contract StaticFeePolicy is IFeePolicy {
    uint256 public immutable f;

    constructor(uint256 _f) {
        f = _f;
    }

    function fee(uint256, uint256) external view returns (uint256) {
        return f;
    }
}

/// @notice An LP-protecting dynamic-fee hook: widens the fee with the size of the price gap (a
///         proxy for realized volatility / toxic flow), capped. This is the strategy class the
///         Foundation funds -- volatility-aware dynamic fees to cut loss-versus-rebalancing.
contract VolatilityFeePolicy is IFeePolicy {
    uint256 public immutable base;
    uint256 public immutable cap;
    uint256 public immutable sens; // WAD: fee = base + sens * moveFraction, capped at cap

    constructor(uint256 _base, uint256 _cap, uint256 _sens) {
        base = _base;
        cap = _cap;
        sens = _sens;
    }

    function fee(uint256 poolPrice, uint256 externalPrice) external view returns (uint256) {
        uint256 diff = externalPrice > poolPrice ? externalPrice - poolPrice : poolPrice - externalPrice;
        uint256 moveFrac = externalPrice == 0 ? 0 : diff * 1e18 / externalPrice;
        uint256 ff = base + moveFrac * sens / 1e18;
        return ff > cap ? cap : ff;
    }
}

/// @notice A hook that advertises a dynamic fee but returns a constant. The scorecard must show it
///         delivers NO economic benefit over the static baseline -- the non-vacuity guard.
contract FakeDynamicFeePolicy is IFeePolicy {
    uint256 public immutable f;

    constructor(uint256 _f) {
        f = _f;
    }

    function fee(uint256 poolPrice, uint256 externalPrice) external view returns (uint256) {
        poolPrice;
        externalPrice; // reads inputs, ignores them
        return f;
    }
}
