// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

/// @notice A real v4 dynamic-fee hook (same minimal shape as SafeDynamicFeeHook -- a plain beforeSwap
///         that returns an LP-fee override on a dynamic-fee pool). It widens the fee with the size of
///         the price gap, a proxy for realized volatility, capped -- the LP-protecting strategy class
///         the Foundation funds to cut loss-versus-rebalancing.
///
///         One _computeFee feeds BOTH the real beforeSwap override the PoolManager invokes AND the
///         public quoteFee the economic scorecard reads, so the score grades the exact logic the pool
///         runs (HookScore.t.sol asserts beforeSwap == quoteFee for the same inputs).
///
///         Price context arrives in hookData as abi.encode(poolPrice, externalPrice), both WAD; empty
///         hookData falls back to the base fee so the hook stays swap-safe on a live pool. M2 reads
///         that context from pool state / an oracle instead of hookData.
///
///         Fee units are v4 LP-fee pips (1e6 = 100%): BASE 3000 = 0.30%, CAP 20000 = 2.00%. SENS is
///         tuned so the schedule matches the WAD VolatilityFeePolicy in the v0 engine.
contract VolatilityFeeHook {
    uint24 public constant BASE_FEE = 3000;
    uint24 public constant CAP_FEE = 20000;
    uint256 public constant SENS = 30;

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata hookData)
        external
        pure
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 fee = BASE_FEE;
        if (hookData.length > 0) {
            (uint256 poolPrice, uint256 externalPrice) = abi.decode(hookData, (uint256, uint256));
            fee = _computeFee(poolPrice, externalPrice);
        }
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    /// The same fee logic exposed as a view so the economic scorecard can read it without a swap.
    function quoteFee(uint256 poolPrice, uint256 externalPrice) external pure returns (uint24) {
        return _computeFee(poolPrice, externalPrice);
    }

    function _computeFee(uint256 poolPrice, uint256 externalPrice) internal pure returns (uint24) {
        uint256 diff = externalPrice > poolPrice ? externalPrice - poolPrice : poolPrice - externalPrice;
        uint256 movePips = externalPrice == 0 ? 0 : diff * 1e6 / externalPrice;
        uint256 fee = uint256(BASE_FEE) + movePips * SENS / 100;
        if (fee > CAP_FEE) fee = CAP_FEE;
        return uint24(fee);
    }
}
