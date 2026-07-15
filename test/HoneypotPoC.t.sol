// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract HoneypotPoCTest is Test, Deployers {
    address hookAddr;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        hookAddr = address(flags ^ (0x4444 << 144));
        deployCodeTo("src/DelayedHoneypotHook.sol:DelayedHoneypotHook", "", hookAddr);
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(hookAddr), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );
    }

    function _swapFeeBps() internal returns (uint256) {
        BalanceDelta d = swap(key, true, -1e8, ZERO_BYTES);
        uint256 input = uint256(int256(-d.amount0()));
        uint256 output = uint256(int256(d.amount1()));
        return (input - output) * 10000 / input;
    }

    function test_oneShot_vs_dynamic() public {
        uint256[5] memory fees;
        for (uint256 i = 0; i < 5; i++) {
            fees[i] = _swapFeeBps();
        }

        console2.log("effective fee per trade, bps (trade 1 -> 5):");
        for (uint256 i = 0; i < 5; i++) {
            console2.log(fees[i]);
        }

        uint256 worst;
        uint256 trippedAt;
        for (uint256 i = 0; i < 5; i++) {
            if (fees[i] > worst) worst = fees[i];
            if (fees[i] > 5000 && trippedAt == 0) trippedAt = i + 1;
        }

        console2.log("--");
        console2.log("one-shot check (buy+sell round-trip = trades 1-2): clean ~0.30%, verdict SAFE");
        console2.log("dynamic walk -> trap springs at trade #:");
        console2.log(trippedAt);
        console2.log("worst effective fee, bps:");
        console2.log(worst);
        console2.log("verdict: DELAYED HONEYPOT -- every swap after the round-trip is taxed ~99%");

        assertLt(fees[0], 300, "trade 1 looks clean");
        assertLt(fees[1], 300, "trade 2 (the sell) still clean -- a one-shot round-trip passes");
        assertGt(worst, 5000, "the dynamic walk reveals the >50% tax a one-shot misses");
        assertGt(trippedAt, 2, "the trap is delayed past a buy+sell round-trip");
    }
}
