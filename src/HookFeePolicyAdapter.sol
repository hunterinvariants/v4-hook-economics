// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IFeePolicy} from "./EconHarness.sol";

interface IQuotingHook {
    function quoteFee(uint256 poolPrice, uint256 externalPrice) external view returns (uint24);
}

/// @notice Bridges a REAL deployed v4 dynamic-fee hook into the economic engine. EconLib.run is
///         unchanged -- it still sees an IFeePolicy -- but every fee now comes from the hook's own
///         deployed logic (quoteFee, the same _computeFee that the hook's beforeSwap uses). v4 LP-fee
///         pips (1e6 = 100%) are converted to the engine's WAD fraction (1e18 = 100%).
contract HookFeePolicyAdapter is IFeePolicy {
    IQuotingHook public immutable hook;

    constructor(address hook_) {
        hook = IQuotingHook(hook_);
    }

    function fee(uint256 poolPrice, uint256 externalPrice) external view returns (uint256) {
        return uint256(hook.quoteFee(poolPrice, externalPrice)) * 1e12; // pips (1e6) -> WAD (1e18)
    }
}
