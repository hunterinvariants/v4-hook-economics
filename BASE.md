# Grade your Base Uniswap v4 hook

Uniswap v4 runs on Base. A team shipping a pool on Base attaches a hook, and that hook changes the
economics of the pool for the liquidity provider. A dynamic fee, a loss-versus-rebalancing mitigation,
or an MEV rule each changes how much the provider earns or loses.

Hook safety tooling checks that a hook cannot be exploited: access control on callbacks, value
conservation, swap liveness. It does not measure whether the hook makes or loses money for the
liquidity provider. That is the question this repository answers, and it is the question a Base builder
needs answered before deploying a pool that other people supply liquidity to.

## What it does

The scorecard takes your hook's fee logic, runs it against a price path, and reports the liquidity
provider's outcome: fee income, value lost to arbitrage (loss-versus-rebalancing), and net PnL. It
grades the hook against a static-fee baseline so the number has a reference. It runs on a hook deployed
on a real v4-core PoolManager, so the grade reflects the code the pool would execute on Base mainnet.

## Grade your own hook

1. Expose a view on your hook, `quoteFee(uint256 poolPrice, uint256 externalPrice) returns (uint24)`,
   that returns the same fee your `beforeSwap` returns to the PoolManager, in v4 LP-fee pips.
2. Deploy the hook and point `HookFeePolicyAdapter` at its address.
3. Run the scorecard over a price path and read the net PnL against the static baseline.

`test/BaseHookScorecard.t.sol` does this end to end for an example hook.

## The worked example

`src/ExampleBaseHook.sol` is an example Base hook, a dynamic fee that keeps the same base fee as a
static pool and widens as the pool price gaps from the external price. `test/BaseHookScorecard.t.sol`
deploys it on a v4-core dynamic-fee pool, routes a live swap through it to prove it is the real deployed
hook, then grades it against a static 0.30% pool over a volatile path and prints the scorecard. The
exact net PnL for the hook and the baseline is printed when you run the test, so the result is read from
the run rather than asserted.

The same test includes a two-way guard. A hook that advertises a dynamic fee but returns a constant is
graded identically to the static baseline. The scorecard flags it as economically vacuous, a result a
safety check does not produce.

## Run it

Restore the v4 dependencies into `lib/` as described in the main README, then:

    forge test --match-contract BaseHookScorecardTest -vv

## Where this fits

The main README covers the full engine, the real-market backtest over historical ETH and BTC closes,
and the retail-flow prototype. This file is the Base entry point: how a team deploying a v4 hook on
Base grades it for liquidity-provider economics before it ships.
