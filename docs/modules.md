# Builder-marketplace modules

Write a module that gives holders a new way to earn from a launch (staking, a raffle, a game, a pot). QHooks reviews it and
lists it in Studio, where any creator can give it a share of their launch income. You keep up to 10% of what your module
receives, in every launch that uses it. The split is set in the module's code, so nobody can change it.

Example: a creator gives your module 30% of their launch income and your builder share is 10% of that. Holders, through your
module, get 27%; you get 3%. Shares are the creator's choice; your cap is 10%.

## How it works
1. **Build:** write your module on `QModuleBase`. It is paid like any payee in a launch's revenue split.
2. **Submit:** send the source, the exact creation code and your tests at <https://qhooks.com/market-submit.html>. You get a
   receipt to follow the review.
3. **Review:** QHooks checks it against the checklist below, reruns your tests and its own, then lists it.
4. **Earn:** creators add it in Studio. Each launch gets its own copy at a fixed address and a panel on its launch page.

## What a module is
A contract a launch names as one of its payees. When anyone calls the launch's `release()`, the module receives its share in
the token and the pair currency, by plain transfer. Everything else (who earns it, when, how) is up to your module.

One copy per launch, deployed by anyone through the deterministic deployer `0x4e59b44847b379578588920ca78fbf26c0b4956c` with
the marketplace salt `keccak256("qhooks.module.v1")` and

```
init = creationCode ++ abi.encode(token, quote, builder, uint16 builderBps)
```

so its address is known before the launch exists. Studio writes that address into the launch's split.

## The template
`QModuleBase` counts new income as its balance minus what it already accounts for, takes your share off the top and hands the
rest to your module. Your share is paid only to you, through `claimBuilder()`, which anyone can call.

```solidity
contract MyModule is QModuleBase {
    constructor(address token, address quote, address builder, uint16 builderBps)
        QModuleBase(token, quote, builder, builderBps) {}

    function kind() external pure override returns (string memory) { return "my-module"; }

    // Every deposit you hold + everything booked and unpaid.
    function _reserved(uint256 i) internal view override returns (uint256) { /* ... */ }

    // Your share of new income, after the builder's cut.
    function _income(uint256 i, uint256 net) internal override { /* ... */ }
}
```

Call `_intake(i)` or `_syncAll()` at the start of every function that moves funds, before pulling deposits.

## What the code guarantees
- **Your cap is 10%.** `builderBps` above 1,000 does not deploy, and the registry refuses it.
- **Only the launch's share.** A module receives exactly the share the creator set; your cut comes out of that.
- **Fixed at deployment.** Builder and share are constructor arguments, part of the module's address. Nobody can change them.
- **No owner.** Modules have no admin and no upgrade. The registry lists and pauses; it never touches funds.

## What review checks
- Creation code matches the source at your commit, byte for byte (solc 0.8.26, `via_ir`, optimizer 200 runs, `cancun`,
  `bytecode_hash = none`); creation code ≤ 49,152 bytes, runtime ≤ 24,576 bytes.
- Inherits `QModuleBase` unchanged; constructor exactly `(token, quote, builder, builderBps)`; `kind()` is a short lowercase id.
- No owner, admin, upgrade, `selfdestruct`, `delegatecall` or arbitrary external call; no function moves funds to an address
  chosen by a caller other than the caller's own entitlement.
- Every user deposit is in `_reserved`, so it is never counted as income (test it explicitly).
- Users can always withdraw their deposits; total paid out never exceeds total received, in both currencies (fuzz test).
- Depositing around a payout cannot capture it.
- Plain copy for the launch page: what holders get, what they risk.

## Tests
Submit Foundry tests: one per function, a fuzz test of the payout invariant, and one where a real launch pays your module.

## Building a full hook instead?
Modules sit in a launch's revenue split. A Uniswap v4 hook that changes how each trade works is a different thing: build it
in the Lab at <https://qhooks.com/lab.html>.
