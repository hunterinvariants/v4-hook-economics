# v4-hook-economics

[![two-way-proof](https://github.com/hunterinvariants/v4-hook-economics/actions/workflows/ci.yml/badge.svg)](https://github.com/hunterinvariants/v4-hook-economics/actions/workflows/ci.yml)

## Overview

A Uniswap v4 hook changes the economics of the pool it attaches to. A dynamic fee, a loss-versus-rebalancing
mitigation, or an MEV-internalising rule each changes how much a liquidity provider earns or loses. Existing
hook tooling checks whether a hook is safe to run: access control on callbacks, value conservation, and swap
liveness. It does not measure whether the hook is profitable for the liquidity provider.

v4-hook-economics is a backtester for that question. It takes a hook's fee policy, runs it against a price
path, and reports the liquidity provider's outcome: fee income, value lost to arbitrage (loss-versus-rebalancing,
or LVR), and net PnL. The same harness grades a deterministic synthetic path and a real historical market, and
it grades a real v4 hook deployed on a v4-core PoolManager rather than a re-implementation of it.

## Model

The backtester walks a sequence of external prices. At each step it assumes an arbitrageur trades the pool to
the edge of the fee band and settles the opposite leg at the external price. This is the standard source of LVR.
A wider fee band moves the pool less far toward the external price, so the arbitrageur extracts less value, at
the cost of less fee-bearing volume. That tension is the quantity the backtester measures.

For each step the harness records two values. The first is the fee the arbitrageur pays, which accrues to the
liquidity provider. The second is the value the arbitrageur removes when valued at the external price, which is
the provider's loss. Net PnL is the total fee income minus the total value extracted, denominated in the quote
asset.

The fee at each step is not hard-coded. It is returned by an `IFeePolicy`, a single function that takes the
current pool price and the external price and returns a fee. A static-fee pool, a volatility-scaled fee, and a
fee that only claims to be dynamic are each expressed as a policy, which makes the comparison between them exact.

## Two-way checks

A suite that passes on every input establishes nothing. Each property here is checked in both directions. A
volatility-aware fee is shown to improve the provider's net PnL against a static fee when the price moves, and a
fee that advertises itself as dynamic but returns a constant is shown to produce a result identical to the static
baseline. The benefit is also shown to scale with volatility: on a calm path the volatility fee produces no
measurable improvement, which is the correct result and prevents the harness from reporting a benefit that does
not exist.

## Grading a real hook

The `IFeePolicy` seam is where a deployed hook connects. `HookFeePolicyAdapter` wraps a v4 hook and reads its
`quoteFee`, which is the same fee logic the hook returns from `beforeSwap` to the PoolManager. The hook under
test, `VolatilityFeeHook`, is deployed on a real v4-core PoolManager at a mined hook address, a dynamic-fee pool
is initialised with it, and a swap is routed through it. The test asserts that the fee returned from the live
`beforeSwap` equals the fee read from `quoteFee` for the same inputs. The economic grade is therefore computed
from the code the pool executes, not from a separate model of it.

## Results

Over 350 daily ETH/USD closes from Coinbase, covering a decline from 2486 to 1670 within a 1569 to 4831 range, a
volatility-aware dynamic-fee hook reduced the liquidity provider's loss by 34% against a static 0.30% fee. Net
PnL was -17,999 against -27,107 on a pool of 100 ETH. The improvement came from fee income, which was roughly
four times the static baseline, while the value lost to arbitrage was approximately unchanged. The two values are
reported separately so the source of the improvement is visible rather than asserted.

The same harness over 350 daily BTC/USD closes reduced the loss by 38%. The result is not specific to one asset.

A volume-replay prototype routes uninformed retail flow alongside the arbitrageur. Retail pays fees, extracts no
arbitrage value, and its volume falls as the fee rises. Under this model a fee tuned too aggressively produces a
worse outcome for the provider than a moderate fee, even though it minimises the value lost to arbitrage, because
the high fee suppresses the retail volume the provider earns on. On the test path a fee capped at 2% returned net
PnL of +9,785 while a fee capped at 8% returned +3,747, and the aggressive fee's retail income fell from 20,274
to 5,476. A price-only model does not detect this, because it does not represent the flow the fee drives away.

The retail flow in this prototype is synthetic and uses a stylised elasticity. Real historical pool volume is the
next step.

## Layout

    src/EconHarness.sol            the engine, the IFeePolicy interface, and the baseline policies
    src/VolatilityFeeHook.sol      a real v4 dynamic-fee hook (widens the fee with volatility)
    src/HookFeePolicyAdapter.sol   bridges a deployed hook into the engine via IFeePolicy
    src/FlowEngine.sol             the volume-replay prototype (retail flow alongside arbitrage)
    test/EconHarness.t.sol         the synthetic two-way checks (3 tests)
    test/HookScore.t.sol           the real-hook grade on v4-core (3 tests)
    test/MarketBacktest.t.sol      the real-market backtest, ETH and BTC
    test/FlowReplay.t.sol          the retail-flow result (an over-aggressive fee suppresses retail)
    scripts/fetch_prices.py        fetches a real daily series and generates a price library

## Build

The v4 dependencies are not committed. Restore them into `lib/` to match `remappings.txt`: forge-std,
OpenZeppelin's uniswap-hooks (which vendors v4-core and v4-periphery), and hookmate. One way is to copy `lib/`
from a working v4-hook-invariants checkout. Then:

    python3 scripts/fetch_prices.py    # writes test/RealPrices.sol from live ETH/USD data
    forge test -vv                     # 9 passing

The suite builds with `via_ir` enabled, which the volume-replay engine requires.

## Limitations

The arbitrage model is stylised. It assumes a single arbitrage trade to the fee-band edge at each step. This
captures the tradeoff between fee income and LVR but not the full microstructure of order flow, including
transaction ordering, sandwiching, and routing across venues.

Retail volume in the replay prototype is synthetic and uses a linear elasticity rather than demand measured from
the chain. Real historical pool volume from a Uniswap subgraph would replace it.

The harness measures the economics of a hook. It does not assess the hook's safety, which is a separate concern
addressed by invariant and access-control testing.

## License

MIT.
