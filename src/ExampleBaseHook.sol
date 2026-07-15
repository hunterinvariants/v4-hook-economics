// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

/// @notice An EXAMPLE Base Uniswap v4 dynamic-fee hook, the kind a team shipping a pool on Base would
///         deploy. Uniswap v4 runs on Base, so this is a plain beforeSwap that returns an LP-fee
///         override on a dynamic-fee pool, the minimal shape a v4-core PoolManager runs. It keeps the
///         same base fee as a static pool and widens the fee as the pool price gaps from the external
///         price, a proxy for toxic flow, so the liquidity provider keeps more of the value an
///         arbitrageur would otherwise take.
///
///         One _computeFee feeds BOTH the beforeSwap override the PoolManager invokes AND the public
///         quoteFee the economic scorecard reads, so the grade is computed from the exact fee logic the
///         Base pool would run. Price context arrives in hookData as abi.encode(poolPrice, externalPrice),
///         both WAD; empty hookData falls back to the base fee so the hook stays swap-safe on a live pool.
///
///         Fee units are v4 LP-fee pips (1e6 = 100%): BASE 3000 = 0.30%, CAP 15000 = 1.50%.
contract ExampleBaseHook {
    uint24 public constant BASE_FEE = 3000;
    uint24 public constant CAP_FEE = 15000;
    uint256 public constant SENS = 40;

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
