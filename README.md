# v4-hook-economics

[![two-way-proof](https://github.com/hunterinvariants/v4-hook-economics/actions/workflows/ci.yml/badge.svg)](https://github.com/hunterinvariants/v4-hook-economics/actions/workflows/ci.yml)

An economic backtester for Uniswap v4 hooks. Existing hook tooling checks whether a hook is safe to
run: callback access control, value conservation, swap liveness. This checks a different question those
tools do not: whether a hook makes or loses money for the liquidity provider.

It takes a hook's fee policy, runs it against a price path, and reports the LP economics: fee income,
value lost to arbitrage (loss-versus-rebalancing), and net PnL. A hook is scored two ways, against a
deterministic synthetic path and against a real historical series.

## Result

Over 350 real daily ETH/USD closes (Coinbase, ETH falling from 2486 to 1670 across a 1569-4831 range),
a volatility-aware dynamic-fee hook reduced LP losses by 34% versus a static 0.30% fee: net PnL of
-17,999 against -27,107 on a 100-ETH pool. The gain came from charging volatile flow more (about four
times the fee income), not from reducing arbitrage extraction, which the scorecard reports separately.

The same engine over 350 days of BTC/USD reduced LP losses by 38%, so the result is not specific to one
pair. A volume-replay prototype, which routes synthetic retail flow alongside the arbitrageur, adds a
finding the price-only model cannot reach: a fee tuned too aggressively cuts the most arbitrage loss but
chokes off retail volume, leaving LPs worse off than a moderate fee. The best fee is not the highest one.

## How it works

The engine is `EconLib.run(x0, y0, path, policy)`. It walks the price path, and on each move an
arbitrageur trades the pool to the edge of the fee band and settles the opposite side at the external
price. That is the standard source of loss-versus-rebalancing. The fee at each step comes from an
`IFeePolicy`, which is the seam a real hook plugs into.

A real v4 dynamic-fee hook is graded through `HookFeePolicyAdapter`, which reads the hook's deployed
`quoteFee`, the same logic its `beforeSwap` returns. The hook is deployed on a real v4-core
PoolManager and a swap is routed through it, so the score grades the code the pool runs, not a model.

## Layout

    src/EconHarness.sol            the engine, the IFeePolicy interface, and the baseline policies
    src/VolatilityFeeHook.sol      a real v4 dynamic-fee hook (widens the fee with volatility)
    src/HookFeePolicyAdapter.sol   bridges a deployed hook into the engine via IFeePolicy
    src/FlowEngine.sol             prototype volume-replay engine (retail flow alongside arbitrage)
    test/EconHarness.t.sol         the synthetic two-way proof (3 tests)
    test/HookScore.t.sol           the real-hook proof on v4-core (3 tests)
    test/MarketBacktest.t.sol      the real-market backtest, ETH and BTC
    test/FlowReplay.t.sol          the retail-flow finding (a too-aggressive fee kills retail volume)
    scripts/fetch_prices.py        fetches a real daily series and generates a price library

## Build

The v4 dependencies are not committed. Restore them into `lib/` to match `remappings.txt` -- forge-std,
OpenZeppelin's uniswap-hooks (which vendors v4-core and v4-periphery), and hookmate -- for example by
copying `lib/` from a working v4-hook-invariants checkout. Then:

    python3 scripts/fetch_prices.py    # writes test/RealPrices.sol from live ETH/USD data
    forge test -vv                     # 9 passing

## Limits

- The arbitrage model is stylized: one arbitrage trade to the fee-band edge per step. It captures the
  fee versus LVR tradeoff, not full order-flow microstructure.
- Retail volume in the replay prototype is synthetic, on a stylized elasticity. Real historical pool
  volume (from a Uniswap subgraph) is the next step.
- This measures LP economics. It is not a safety audit; that is a separate concern.
